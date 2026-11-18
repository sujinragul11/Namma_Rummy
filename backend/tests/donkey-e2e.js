// Donkey Master end to end, over real sockets, against a running test server:
//   node tests/donkey-e2e.js --url=http://127.0.0.1:3193 --deal-flag=<file>
// The server must be the Godot tests' test server (godot/tests/test_server.js) started with
// --donkey-deal=<the same file> and quick clocks:
//   DONKEY_TURN_SECONDS=2 DONKEY_AWAY_SECONDS=0.4 DONKEY_TRICK_PAUSE_SECONDS=0.1
//   DONKEY_DEAL_SECONDS=0 MATCH_REGION_SECONDS=0.5 MATCH_NEARBY_SECONDS=1 MATCH_FILL_SECONDS=1
// Checks: private tables (create, join by code, host start, getting up and the entry coming
// back, a full table dealing itself), whole games played by simple bots, follow-suit refused,
// the coins (entries, payouts, one balance with rummy), Play Online, leaving mid-game,
// losing the connection and coming back, rummy refusing a player busy at a donkey table, and
// voice chat at a donkey table (VoiceRelay through tables.js) reaching that table only.
const assert = require('node:assert/strict');
const fs = require('fs');
const path = require('path');
// socket.io-client comes from the Expo app's packages (the backend has none); SOCKET_IO_CLIENT may point elsewhere
const { io } = require([process.env.SOCKET_IO_CLIENT, path.join(__dirname, '..', '..', 'mobile', 'node_modules', 'socket.io-client')]
  .find((place) => place && fs.existsSync(place)));

const option = (name, fallback) => {
  const found = process.argv.find((arg) => arg.startsWith(`--${name}=`));
  return found ? found.slice(name.length + 3) : fallback;
};
const URL = option('url', 'http://127.0.0.1:3193');
const DEAL_FLAG = option('deal-flag', '');
const START = 50000;
let checks = 0;
const check = (condition, message) => { assert.ok(condition, message); checks++; };
const equal = (actual, expected, message) => { assert.deepEqual(actual, expected, message); checks++; };
const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));

async function until(what, test, ms = 15000) {
  const end = Date.now() + ms;
  while (Date.now() < end) {
    const value = test();
    if (value) return value;
    await sleep(20);
  }
  throw new Error(`timed out waiting for ${what}`);
}

async function http(method, route, body, token) {
  const response = await fetch(URL + route, {
    method,
    headers: { 'Content-Type': 'application/json', ...(token ? { Authorization: `Bearer ${token}` } : {}) },
    body: body ? JSON.stringify(body) : undefined
  });
  return { status: response.status, data: await response.json().catch(() => ({})) };
}

const stamp = Date.now() % 100000;
let phoneSeed = 0;
async function player(name) {
  const phone = `+9198${String(stamp).padStart(5, '0')}${String(++phoneSeed).padStart(3, '0')}`;
  const { status, data } = await http('POST', '/api/auth/register', { username: `${name}${stamp}`, phone, password: 'secret123' });
  assert.equal(status, 201, `register ${name}: ${JSON.stringify(data)}`);
  const me = { name, id: String(data.user.id), token: data.token, coins: null, state: null, notices: [], invites: [], found: 0, failed: [], voices: [], micLists: [] };
  me.connect = () => new Promise((resolve, reject) => {
    me.socket = io(URL, { auth: { token: me.token }, transports: ['websocket'], forceNew: true, reconnection: false });
    me.socket.on('connect', resolve);
    me.socket.on('connect_error', reject);
    me.socket.on('coins', (payload) => { me.coins = payload.coins; });
    me.socket.on('donkeyState', (state) => { me.state = state; });
    me.socket.on('donkeyNotice', (notice) => me.notices.push(notice));
    me.socket.on('donkeyInvite', (invite) => me.invites.push(invite));
    me.socket.on('donkeyMatchFound', () => { me.found++; });
    me.socket.on('donkeyMatchFailed', (payload) => me.failed.push(payload.message));
    me.socket.on('voice', (payload) => me.voices.push(payload));
    me.socket.on('voiceMics', (payload) => me.micLists.push(payload));
  });
  me.ask = (event, payload = {}) => new Promise((resolve) => me.socket.emit(event, payload, resolve));
  me.balance = async () => (await http('GET', '/api/user/profile', null, me.token)).data.user.coins;
  await me.connect();
  await until(`${name}'s balance`, () => me.coins !== null);
  return me;
}

// Plays every turn of whoever is on turn with the first card they may play, until the end.
// `refuse` once tries a card that does not follow suit, which the server must refuse.
async function playOut(players, { refuse = false } = {}) {
  let refused = !refuse;
  for (let moves = 0; moves < 2000; moves++) {
    const any = players.find((p) => p.state);
    if (any.state.status === 'finished') return any.state;
    const mover = players.find((p) => p.state && p.state.status === 'playing' && p.state.turn === p.id
      && p.state.playable.length > 0 && Object.keys(p.state.trickEnd).length === 0);
    if (!mover) {
      await sleep(15);
      continue;
    }
    const state = mover.state;
    if (!refused && state.leadSuit && state.playable.length < state.hand.length) {
      const wrong = state.hand.find((card) => !state.playable.includes(card.id));
      const answer = await mover.ask('donkeyPlay', { cardId: wrong.id });
      equal(answer.ok, false, 'a card that does not follow suit is refused');
      check(/Follow suit/.test(answer.error), `refusal says why: ${answer.error}`);
      refused = true;
    }
    const before = state.trickNo * 100 + state.trick.length;
    const answer = await mover.ask('donkeyPlay', { cardId: state.playable[0] });
    if (!answer.ok && /not your turn/.test(answer.error)) continue; // the clock played it first
    assert.ok(answer.ok, `play refused: ${answer.error}`);
    await until('the move to come back', () => mover.state.status !== 'playing' || mover.state.trickNo * 100 + mover.state.trick.length !== before
      || Object.keys(mover.state.trickEnd).length > 0);
  }
  throw new Error('the game did not end');
}

function checkResult(state, stake, count) {
  equal(state.status, 'finished', 'the game is over');
  const donkeys = state.players.filter((p) => p.donkey);
  equal(donkeys.length, 1, 'one Donkey');
  equal(state.donkeyId, donkeys[0].id, 'donkeyId names it');
  check(state.masterId && state.masterId !== state.donkeyId, 'a Master who is not the Donkey');
  equal(state.results.length, count, 'a result for everyone');
  equal(state.results.reduce((sum, r) => sum + r.coins, 0), 0, 'no coins made or lost');
  equal(state.results.find((r) => r.id === state.masterId).coins, stake, 'the Master wins the Donkey\'s entry');
  equal(state.results.find((r) => r.id === state.donkeyId).coins, -stake, 'the Donkey loses the entry');
  return state;
}

(async () => {
  const [a, b, c] = [await player('ann'), await player('bob'), await player('cat')];
  equal([a.coins, b.coins, c.coins], [START, START, START], 'every account starts with 50,000');
  if (DEAL_FLAG) fs.writeFileSync(DEAL_FLAG, 'plain');

  // ---- a private table: refusals, the host, getting up before the deal ----
  equal((await a.ask('donkeyCreate', { maxPlayers: 9, stake: 1000 })).error, 'There is no Donkey Master table for that many players', '9 seats refused');
  equal((await a.ask('donkeyCreate', { maxPlayers: 3, stake: 777 })).error, 'There is no table with that entry', 'odd entry refused');
  const created = await a.ask('donkeyCreate', { maxPlayers: 3, stake: 1000 });
  check(created.ok && /^[A-Z2-9]{6}$/.test(created.roomCode), `a private table with a code: ${JSON.stringify(created)}`);
  await until('ann pays the entry', () => a.coins === START - 1000);
  await until('ann sees the table', () => a.state && a.state.roomCode === created.roomCode);
  equal([a.state.status, a.state.private, a.state.hostId, a.state.pot], ['waiting', true, a.id, 1000], 'waiting, private, ann hosts');
  equal((await b.ask('donkeyJoin', { roomCode: 'ZZZZZZ' })).error, 'Room not found. Check the code with your friend.', 'a wrong code');
  const joined = await b.ask('donkeyJoin', { roomCode: created.roomCode.toLowerCase() });
  check(joined.ok, `bob joins with the code in lower case: ${joined.error}`);
  await until('bob pays', () => b.coins === START - 1000);
  await until('ann hears bob joined', () => a.notices.some((n) => n.type === 'joined' && n.userId === b.id));
  equal((await b.ask('donkeyStart')).error, 'Only the host can start the game', 'only the host starts');
  equal(await b.balance(), START - 1000, 'the balance the server keeps is the one sent');
  await b.ask('donkeyLeave');
  await until('bob gets his entry back', () => b.coins === START);
  await until('ann sees bob go', () => a.state.players.length === 1);
  equal((await a.ask('donkeyStart')).error, 'Wait for at least one more player', 'one player cannot start');
  await b.ask('donkeyJoin', { roomCode: created.roomCode });
  await c.ask('donkeyJoin', { roomCode: created.roomCode }); // the third seat: it deals itself
  await until('the full table deals', () => [a, b, c].every((p) => p.state && p.state.status === 'playing'));
  equal([a.coins, b.coins, c.coins], [START - 1000, START - 1000, START - 1000], 'three entries paid');
  equal(a.state.pot, 3000, 'the pot');
  equal(a.state.hand.length + b.state.hand.length + c.state.hand.length, 52, 'the whole pack is dealt');
  equal(a.state.players.map((p) => p.cards), [18, 17, 17], 'card counts by seat');
  check(!JSON.stringify(a.state).includes('"3♠"'), 'nobody sees another player\'s cards (3♠ is bob\'s)');
  equal([a.state.turn, a.state.mustLead, a.state.playable], [a.id, 'A♠', ['A♠']], 'the A♠ leads the first trick');
  equal(b.state.mustLead, '', 'only the player on turn is told what to lead');
  equal((await c.ask('donkeyJoin', { roomCode: created.roomCode })).ok, true, 'joining one\'s own table again is harmless');

  // voice chat at the donkey table: the mic is known to the table, sound reaches the others only
  const roomId = a.state.roomId;
  const micOn = await a.ask('voiceMic', { on: true });
  equal([micOn.ok, micOn.mics], [true, [a.id]], 'a microphone switched on at a donkey table');
  await until('the table hears whose mic is on', () => [b, c].every((p) => p.micLists.some((m) => m.gameId === roomId && m.mics.includes(a.id))));
  equal((await c.ask('voiceMics')), { ok: true, gameId: roomId, mics: [a.id] }, 'asking whose mic is on at a donkey table');
  a.socket.emit('voice', { level: 60, data: 'AAAAAAAA' });
  await until('the sound reaches the other two', () => [b, c].every((p) => p.voices.some((v) => v.gameId === roomId && v.from === a.id && v.level === 60)));
  await sleep(200);
  equal(a.voices.length, 0, 'the speaker does not hear themselves');
  b.socket.emit('voice', { level: 30, data: 'AAAA' });
  await sleep(300);
  equal(a.voices.length + c.voices.filter((v) => v.from === b.id).length, 0, 'a player whose mic is off sends nothing');
  equal((await a.ask('voiceMic', { on: false })).mics, [], 'and switched off again');

  // rummy refuses a player who holds cards at a donkey table
  const rummy = await new Promise((resolve) => a.socket.emit('createGame', { gameType: 'pool', maxPlayers: 2, stake: 0 }, resolve));
  equal(rummy.error, 'You are playing Donkey Master. Finish or leave that table first.', 'no rummy table meanwhile');
  const elsewhere = await a.ask('donkeyCreate', { maxPlayers: 2, stake: 0 });
  equal(elsewhere.error, 'You are already playing at a Donkey Master table. Finish or leave it first.', 'one donkey table at a time');

  const first = checkResult(await playOut([a, b, c], { refuse: true }), 1000, 3);
  await until('everyone sees the end', () => [a, b, c].every((p) => p.state.status === 'finished'));
  const expected = {};
  for (const r of first.results) expected[r.id] = START - 1000 + 1000 + r.coins;
  await until('the payout arrives', () => [a, b, c].every((p) => p.coins === expected[p.id]));
  for (const p of [a, b, c]) equal(await p.balance(), expected[p.id], `${p.name}'s balance after the game`);
  equal((await a.ask('voiceMic', { on: true })).error, 'Game not found', 'no voice once the donkey game is over, as at rummy');
  const looked = await a.ask('donkeyState');
  equal(looked.ok && looked.state.status, 'finished', 'a finished table can still be looked at');

  // ---- play again: a new private table, the others invited ----
  const again = await a.ask('donkeyCreate', { maxPlayers: 3, stake: 500, again: first.roomId });
  check(again.ok, `play again: ${again.error}`);
  await until('bob and cat are invited back', () => b.invites.some((i) => i.roomCode === again.roomCode && i.again)
    && c.invites.some((i) => i.roomCode === again.roomCode && i.again));
  equal((await b.ask('donkeyInvite', { userId: c.id })).error, 'Donkey table not found', 'only someone at a table can invite');
  await b.ask('donkeyJoin', { roomCode: again.roomCode });
  const invited = await a.ask('donkeyInvite', { userId: c.id });
  equal([invited.ok, invited.username], [true, c.state.players.find((p) => p.id === c.id).username], 'inviting a table-mate');
  equal((await a.ask('donkeyInvite', { userId: c.id })).error.startsWith('You have just invited'), true, 'not twice at once');
  await a.ask('donkeyStart'); // two of three seats: the host deals
  await until('a two-player deal', () => a.state.status === 'playing' && b.state.status === 'playing');
  equal(a.state.players.length, 2, 'two players');
  const balances = { [a.id]: a.coins, [b.id]: b.coins };

  // ---- losing the connection: the clock plays for the absent player; coming back ----
  b.socket.disconnect();
  await until('ann hears bob is gone', () => a.notices.some((n) => n.type === 'disconnected' && n.userId === b.id));
  await until('bob shown offline', () => a.state.players.find((p) => p.id === b.id).connected === false);
  await until('the game moves on for bob', () => a.state.trickNo >= 3 || a.state.status === 'finished', 30000);
  b.state = null;
  await b.connect();
  await until('bob is back at the table', () => b.state && b.state.roomId === a.state.roomId);
  check(b.state.hand.length === b.state.players.find((p) => p.id === b.id).cards, 'bob gets his own cards back');
  await until('ann hears bob is back', () => a.notices.some((n) => n.type === 'reconnected' && n.userId === b.id));
  const second = await playOut([a, b]);
  if (second.endedBy === 'play') checkResult(second, 500, 2);
  await until('second payout', () => a.coins + b.coins === balances[a.id] + balances[b.id] + 1000);

  // ---- Play Online: two players searching for the same table are seated together ----
  if (DEAL_FLAG) fs.unlinkSync(DEAL_FLAG); // random hands from here
  const before = { a: a.coins, c: c.coins };
  equal((await a.ask('donkeyFind', { maxPlayers: 3, stake: 500 })).error, 'There is no Donkey Master table for that many players', 'online sizes are 2, 4, 6, 8');
  const search = await a.ask('donkeyFind', { maxPlayers: 2, stake: 500, timezone: 330 });
  equal([search.ok, search.region], [true, 'UTC+5:30'], 'searching in UTC+5:30');
  await c.ask('donkeyFind', { maxPlayers: 2, stake: 500, timezone: 330 });
  await until('both are seated', () => a.found === 1 && c.found === 1 && a.state.status === 'playing' && c.state.status === 'playing'
    && a.state.roomId === c.state.roomId);
  equal(a.state.private, false, 'an online table is not private');
  await until('online entries', () => a.coins === before.a - 500 && c.coins === before.c - 500);

  // ---- getting up mid-game loses the entry to the one who stayed ----
  await c.ask('donkeyLeave');
  await until('ann wins by c leaving', () => a.state.status === 'finished');
  equal([a.state.endedBy, a.state.results.find((r) => r.id === c.id).left], ['leave', true], 'ended by leaving');
  await until('online payout', () => a.coins === before.a + 500);
  equal(await c.balance(), before.c - 500, 'cat lost her entry');

  // ---- a search is cancelled; a lobby seat is given up to search ----
  await a.ask('donkeyLeave');
  await a.ask('donkeyFind', { maxPlayers: 8, stake: 0 });
  equal((await a.ask('donkeyCancelFind')).cancelled, true, 'a search can be cancelled');
  const lobby = await a.ask('donkeyCreate', { maxPlayers: 4, stake: 2000 });
  await until('lobby entry', () => a.coins === before.a + 500 - 2000);
  await a.ask('donkeyFind', { maxPlayers: 4, stake: 0 });
  await until('searching gives the lobby seat and its entry back', () => a.coins === before.a + 500);
  equal((await b.ask('donkeyJoin', { roomCode: lobby.roomCode })).error, 'Room not found. Check the code with your friend.', 'the emptied table is gone');
  await a.ask('donkeyCancelFind');

  for (const p of [a, b, c]) p.socket.disconnect();
  console.log(`donkey-e2e: all ${checks} checks passed`);
  process.exit(0);
})().catch((error) => {
  console.error('donkey-e2e FAILED:', error);
  process.exit(1);
});
