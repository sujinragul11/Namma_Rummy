// Computer players at real tables, over real sockets, against a running test server:
//   node tests/bots-e2e.js --url=http://127.0.0.1:3221 --db=My_Rummy_bots_test
// The server must be the Godot tests' test server (godot/tests/test_server.js) started with
// computer players after 2 seconds and short breaks between rounds:
//   NEXT_ROUND_SECONDS=2 node ../godot/tests/test_server.js --fresh --port=3221 --db=My_Rummy_bots_test --bot-seconds=2
// Checks: a lone player's Play Now table fills with computer players after the wait and is
// played to the end, the computer players move like people (a pause, never instantly), look
// like people (a username, a profile, no photo, connected), pay and win coins; two people
// searching together are seated together without computer players; a private table never gets
// any; a table everyone has left is played out by the computer players and its pot paid; and
// Donkey Master's Play Online does the same.
const assert = require('node:assert/strict');
const fs = require('fs');
const path = require('path');
const { io } = require([process.env.SOCKET_IO_CLIENT, path.join(__dirname, '..', '..', 'mobile', 'node_modules', 'socket.io-client')]
  .find((place) => place && fs.existsSync(place)));

const option = (name, fallback) => {
  const found = process.argv.find((arg) => arg.startsWith(`--${name}=`));
  return found ? found.slice(name.length + 3) : fallback;
};
const URL = option('url', 'http://127.0.0.1:3221');
const DB = option('db', 'My_Rummy_bots_test');
if (!DB.endsWith('_test')) throw new Error('Use a database whose name ends in _test');
process.chdir(path.join(__dirname, '..'));
require('dotenv').config();
process.env.DB_NAME = DB;
const db = require('../src/database/db');

let checks = 0;
const check = (condition, message) => { assert.ok(condition, message); checks++; };
const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));
async function until(what, test, ms = 20000) {
  const end = Date.now() + ms;
  while (Date.now() < end) {
    const value = await test();
    if (value) return value;
    await sleep(25);
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
let seed = 0;
async function person(name) {
  const phone = `+9197${String(stamp).padStart(5, '0')}${String(++seed).padStart(3, '0')}`;
  const { status, data } = await http('POST', '/api/auth/register', { username: `${name}${stamp}`, phone, password: 'secret123' });
  assert.equal(status, 201, `register ${name}: ${JSON.stringify(data)}`);
  const me = { name, id: String(data.user.id), token: data.token, state: null, donkey: null, over: null, found: 0, moves: [] };
  await new Promise((resolve, reject) => {
    me.socket = io(URL, { auth: { token: me.token }, transports: ['websocket'], forceNew: true, reconnection: false });
    me.socket.on('connect', resolve);
    me.socket.on('connect_error', reject);
  });
  me.socket.on('gameState', (state) => {
    // when the turn moves on, note when, to see how long the computer players take
    if (me.state && state.currentPlayer !== me.state.currentPlayer) me.moves.push({ at: Date.now(), to: state.currentPlayer });
    me.state = state;
  });
  me.socket.on('gameOver', (result) => { me.over = result; });
  me.socket.on('matchFound', () => { me.found++; });
  me.socket.on('donkeyState', (state) => { me.donkey = state; });
  me.ask = (event, payload = {}) => new Promise((resolve) => me.socket.emit(event, payload, resolve));
  me.balance = async () => (await http('GET', '/api/user/profile', null, me.token)).data.user.coins;
  return me;
}

const isBot = async (id) => (await db.query('SELECT is_bot FROM users WHERE id = $1', [id])).rows[0]?.is_bot === true;

// This person's moves at a rummy table: draw from the deck, throw back that card; after
// someone's declaration, hand in the cards as they lie
async function playRummy(me, { until: stop = () => false } = {}) {
  // The computer player takes a few seconds over every turn, as a person does
  const deadline = Date.now() + 6 * 60 * 1000;
  while (Date.now() < deadline) {
    const state = me.state;
    if (!state || state.status === 'finished' || stop()) return;
    if (state.status === 'playing' && state.declaredBy && state.declaredBy !== me.id) {
      const answer = await me.ask('submitHand', {});
      if (answer.ok) await until('the show to move on', () => me.state !== state);
      else await sleep(50);
      continue;
    }
    if (state.status === 'playing' && !state.declaredBy && state.currentPlayer === me.id) {
      if (state.turnPhase === 'draw') {
        const drawn = await me.ask('drawCard', { fromDiscard: false });
        if (drawn.ok) {
          await until('the draw to come back', () => me.state.turnPhase === 'discard' || me.state.currentPlayer !== me.id);
          await me.ask('discardCard', { cardId: drawn.card.id });
        }
      } else {
        const last = state.hand[state.hand.length - 1];
        if (last) await me.ask('discardCard', { cardId: last.id });
      }
      await sleep(30);
      continue;
    }
    await sleep(40);
  }
  throw new Error('the rummy game did not end');
}

(async () => {
  // ---------- 1. a lone player's Play Now table fills with computer players ----------
  const asha = await person('asha');
  const startCoins = await asha.balance();
  const searched = Date.now();
  // A Points table with an entry: one round, which the computer player ends by declaring
  let answer = await asha.ask('findMatch', { gameType: 'points', maxPlayers: 2, stake: 500, timezone: 330 });
  check(answer.ok, `Play Now starts a search: ${answer.error || ''}`);
  await until('a table with a computer player', () => asha.state && asha.state.status === 'playing', 15000);
  const waited = Date.now() - searched;
  check(waited >= 1800 && waited < 6000, `the computer player came after the wait, not before (${waited} ms)`);
  const other = asha.state.players.find((p) => p.id !== asha.id);
  check(asha.state.players.length === 2 && other, 'two players at the table');
  check(await isBot(other.id), 'the other one is a computer player');
  check(/^[\w .]{1,20}$/.test(other.username) && !/bot/i.test(other.username), `it has a username like a person's: ${other.username}`);
  check(other.avatar === 0 && other.connected !== false, 'no photo, and connected');
  const profile = await asha.ask('playerProfile', { userId: other.id });
  check(profile.ok && profile.profile.username === other.username, 'its profile opens like anyone\'s');
  check(asha.found === 1, 'matchFound came once');

  await playRummy(asha);
  check(asha.state.status === 'finished', 'the game was played to the end');
  const gaps = [];
  for (let i = 1; i < asha.moves.length; i++) {
    if (asha.moves[i - 1].to === other.id) gaps.push(asha.moves[i].at - asha.moves[i - 1].at);
  }
  check(gaps.length > 0 && Math.min(...gaps) >= 900, `the computer player takes its time over a turn (shortest ${Math.min(...gaps)} ms)`);
  const winner = asha.over && asha.over.matchWinner;
  const afterCoins = await until('the pot to be paid', async () => {
    const coins = await asha.balance();
    return coins !== startCoins - 500 || winner !== asha.id ? coins : null;
  });
  check(afterCoins === startCoins - 500 + (winner === asha.id ? 1000 : 0), `the entry and the pot moved like any game's (${startCoins} -> ${afterCoins}, winner ${winner === asha.id ? 'Asha' : 'the computer player'})`);
  const botWin = await db.query(`SELECT COUNT(*)::int AS n FROM transactions WHERE user_id = $1 AND type IN ('entry', 'win')`, [other.id]);
  check(botWin.rows[0].n >= 1, 'the computer player paid its entry too');

  // ---------- 2. two people searching together sit together ----------
  const bala = await person('bala');
  const chitra = await person('chitra');
  await bala.ask('findMatch', { gameType: 'pool', maxPlayers: 2, stake: 0, timezone: 330 });
  await chitra.ask('findMatch', { gameType: 'pool', maxPlayers: 2, stake: 0, timezone: 330 });
  await until('the two to be seated', () => bala.state && chitra.state && bala.state.status === 'playing');
  check(bala.state.gameId === chitra.state.gameId && bala.state.players.length === 2, 'two people searching together are seated together, no computer player');
  await bala.ask('leaveGame');
  await chitra.ask('leaveGame');

  // ---------- 3. a private table never gets computer players ----------
  answer = await bala.ask('createGame', { gameType: 'pool', maxPlayers: 2, stake: 0, private: true });
  check(answer.ok, 'a private table opens');
  await sleep(3500);
  check(bala.state.status === 'waiting' && bala.state.players.length === 1, 'after the wait it still has only its host');
  await bala.ask('leaveGame');

  // ---------- 4. six seats, five computer players; everyone leaves; they play it out ----------
  const devi = await person('devi');
  await devi.ask('findMatch', { gameType: 'pool', maxPlayers: 6, stake: 1000, timezone: 330 });
  await until('the six-seat table', () => devi.state && devi.state.status === 'playing', 15000);
  check(devi.state.players.length === 6, 'five computer players filled the six-seat table');
  const ids = devi.state.players.map((p) => p.id).filter((id) => id !== devi.id);
  check((await Promise.all(ids.map(isBot))).every(Boolean), 'all five are computer players');
  check(new Set(devi.state.players.map((p) => p.username)).size === 6, 'each has its own name');
  const gameId = devi.state.gameId;
  await sleep(4000); // a few moves of theirs
  await devi.ask('leaveGame');
  const closed = await until('the computer players to finish the game', async () => {
    const row = (await db.query('SELECT status FROM games WHERE id = $1', [gameId])).rows[0];
    return row && row.status === 'finished' ? row : null;
  }, 120000);
  check(closed.status === 'finished', 'a game everyone left is played out by the computer players');
  const pot = await until('the pot to go to a computer player', async () => {
    const rows = (await db.query(`SELECT user_id, amount FROM transactions WHERE game_id = $1 AND type = 'win'`, [gameId])).rows;
    return rows.length > 0 ? rows : null;
  });
  check(Number(pot[0].amount) === 6000 && ids.includes(String(pot[0].user_id)), `and its pot of 6,000 is paid to the winner (${pot[0].amount})`);

  // ---------- 5. Donkey Master: Play Online fills with computer players ----------
  const ezhil = await person('ezhil');
  const ezhilCoins = await ezhil.balance();
  answer = await ezhil.ask('donkeyFind', { maxPlayers: 4, stake: 500, timezone: 330 });
  check(answer.ok, `Play Online starts a search: ${answer.error || ''}`);
  await until('a Donkey Master table', () => ezhil.donkey && ezhil.donkey.status === 'playing', 15000);
  check(ezhil.donkey.players.length === 4, 'three computer players took the other seats');
  check(ezhil.donkey.players.every((p) => p.connected !== false && !p.away), 'all shown as there');
  let lastPlay = Date.now();
  const playGaps = [];
  let seen = 0;
  // Three computer players at a person's pace: a game of many tricks takes some minutes
  const donkeyDeadline = Date.now() + 8 * 60 * 1000;
  while (Date.now() < donkeyDeadline && ezhil.donkey.status !== 'finished') {
    const state = ezhil.donkey;
    const count = state.trickNo * 100 + state.trick.length;
    if (count !== seen) {
      if (state.trick.length > 0 && state.trick[state.trick.length - 1].playerId !== ezhil.id) playGaps.push(Date.now() - lastPlay);
      lastPlay = Date.now();
      seen = count;
    }
    if (state.status === 'playing' && state.turn === ezhil.id && state.playable.length > 0 && Object.keys(state.trickEnd || {}).length === 0) {
      await ezhil.ask('donkeyPlay', { cardId: state.playable[0] });
    }
    await sleep(20);
  }
  check(ezhil.donkey.status === 'finished', 'the Donkey Master game was played to the end');
  check(playGaps.length > 0 && Math.min(...playGaps) >= 700, `the computer players take their time over a card (shortest ${Math.min(...playGaps)} ms)`);
  const ezhilAfter = await ezhil.balance();
  const mine = ezhil.donkey.players.find((p) => p.id === ezhil.id);
  check(ezhilAfter === ezhilCoins - 500 || ezhilAfter === ezhilCoins || ezhilAfter > ezhilCoins, `Ezhil's coins follow the result (${ezhilCoins} -> ${ezhilAfter}, place ${mine && mine.place})`);

  for (const someone of [asha, bala, chitra, devi, ezhil]) someone.socket.close();
  await db.pool.end();
  console.log(`\nbots-e2e: ${checks} checks passed`);
  process.exit(0);
})().catch(async (error) => {
  console.error(error);
  try { await db.pool.end(); } catch (_) { /* closing anyway */ }
  process.exit(1);
});
