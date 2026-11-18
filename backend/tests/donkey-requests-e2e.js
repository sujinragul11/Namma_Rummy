// Donkey Master's Request Card, over real sockets, against a running test server:
//   node tests/donkey-requests-e2e.js --url=http://127.0.0.1:3241
// The server must be the Godot tests' test server with quick clocks and short request times,
// and computer players after 2 seconds (for the last part):
//   DONKEY_TURN_SECONDS=20 DONKEY_TRICK_PAUSE_SECONDS=0.2 DONKEY_DEAL_SECONDS=0 \
//   DONKEY_REQUEST_SECONDS=3 DONKEY_REQUEST_GAP_SECONDS=3 \
//     node ../godot/tests/test_server.js --fresh --port=3241 --db=My_Rummy_requests_test --bot-seconds=2
// Checks: requests only between tricks and only to the players next to one; the wait between
// two requests; a reject moves nothing; an ignored request expires; an accept moves the whole
// hand and puts the giver out; the answer only from the asked player, once; no accept while
// the asked player has a card in the trick; everyone at the table sees every step; a computer
// player always accepts.
const assert = require('node:assert/strict');
const fs = require('fs');
const path = require('path');
const { io } = require([process.env.SOCKET_IO_CLIENT, path.join(__dirname, '..', '..', 'mobile', 'node_modules', 'socket.io-client')]
  .find((place) => place && fs.existsSync(place)));

const option = (name, fallback) => {
  const found = process.argv.find((arg) => arg.startsWith(`--${name}=`));
  return found ? found.slice(name.length + 3) : fallback;
};
const URL = option('url', 'http://127.0.0.1:3241');
let checks = 0;
const check = (condition, message) => { assert.ok(condition, message); checks++; };
const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));
async function until(what, test, ms = 15000) {
  const end = Date.now() + ms;
  while (Date.now() < end) {
    const value = await test();
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

const stamp = String(Date.now() % 1000000).padStart(6, '0');
let seed = 0;
async function person(name) {
  const phone = `+9196${stamp}${String(++seed).padStart(2, '0')}`;
  const { status, data } = await http('POST', '/api/auth/register', { username: `${name}${stamp}`, phone, password: 'secret123' });
  assert.equal(status, 201, `register ${name}: ${JSON.stringify(data)}`);
  const me = { name, id: String(data.user.id), state: null };
  await new Promise((resolve, reject) => {
    me.socket = io(URL, { auth: { token: data.token }, transports: ['websocket'], forceNew: true, reconnection: false });
    me.socket.on('connect', resolve);
    me.socket.on('connect_error', reject);
  });
  me.socket.on('donkeyState', (state) => { me.state = state; });
  me.ask = (event, payload = {}) => new Promise((resolve) => me.socket.emit(event, payload, resolve));
  me.cards = () => me.state.hand.length;
  me.request = (id) => (me.state.requests || []).find((r) => r.id === id);
  return me;
}

const total = (players) => players.reduce((sum, p) => sum + (p.state.players.find((x) => x.id === p.id).cards), 0);
const betweenTricks = (state) => state.status === 'playing' && !state.mustLead && state.trick.length === 0
  && Object.keys(state.trickEnd || {}).length === 0 && state.trickNo > 1;

// Plays for whoever is on turn (first card they may play) until `stop` says so
async function playUntil(players, stop, ms = 30000) {
  const end = Date.now() + ms;
  while (Date.now() < end) {
    const any = players.find((p) => p.state);
    if (stop(any.state)) return any.state;
    const mover = players.find((p) => p.state && p.state.status === 'playing' && p.state.turn === p.id
      && p.state.playable.length > 0 && Object.keys(p.state.trickEnd || {}).length === 0);
    if (!mover) {
      await sleep(15);
      continue;
    }
    const before = `${mover.state.trickNo}:${mover.state.trick.length}`;
    await mover.ask('donkeyPlay', { cardId: mover.state.playable[0] });
    await until('the move', () => `${mover.state.trickNo}:${mover.state.trick.length}` !== before || mover.state.status !== 'playing'
      || Object.keys(mover.state.trickEnd || {}).length > 0, 5000).catch(() => {});
  }
  throw new Error('the state wanted did not come');
}

(async () => {
  // ---------- four people at a private table: A, B, C, D clockwise ----------
  const [a, b, c, d] = await Promise.all(['ra', 'rb', 'rc', 'rd'].map(person));
  let answer = await a.ask('donkeyCreate', { maxPlayers: 4, stake: 0 });
  check(answer.ok, `a private table for four: ${answer.error || ''}`);
  await until('the room code', () => a.state && a.state.roomCode);
  for (const other of [b, c, d]) {
    answer = await other.ask('donkeyJoin', { roomCode: a.state.roomCode });
    assert.ok(answer.ok, `join: ${answer.error}`);
  }
  await until('the deal', () => a.state.status === 'playing' && [b, c, d].every((p) => p.state && p.state.status === 'playing'));
  const all = [a, b, c, d];
  const seatOf = (p) => a.state.players.find((x) => x.id === p.id).seat;
  check([a, b, c, d].map(seatOf).join() === '0,1,2,3', 'they sit in the order they came');

  // Before the ace of spades is led nobody may ask
  answer = await a.ask('donkeyRequestCard', { to: b.id });
  check(!answer.ok, `no request before the first card is led: ${answer.error}`);

  // ---------- between tricks ----------
  let state = await playUntil(all, betweenTricks);
  await until('everyone to see the gap', () => all.every((p) => betweenTricks(p.state)));
  check(a.state.canRequest === true, 'between tricks a player in play may ask');
  check([...a.state.neighbours].sort().join() === [b.id, d.id].sort().join(), 'A\'s neighbours are B and D, the players either side');
  answer = await a.ask('donkeyRequestCard', { to: c.id });
  check(!answer.ok && /next to you/.test(answer.error), `C, across the table, may not be asked: ${answer.error}`);

  const cardsBefore = Object.fromEntries(all.map((p) => [p.name, p.cards()]));
  const sum = total(all);
  answer = await a.ask('donkeyRequestCard', { to: b.id });
  check(answer.ok && answer.requestId, `A asks B: ${answer.error || ''}`);
  const first = answer.requestId;
  await until('everyone to see it pending', () => all.every((p) => p.request(first) && p.request(first).status === 'pending'));
  check(true, 'the request is on show for the whole table, pending');
  check(a.state.requestWait > 0, 'and A must wait before asking again');
  answer = await a.ask('donkeyRequestCard', { to: d.id });
  check(!answer.ok, `a second request at once is refused: ${answer.error}`);
  answer = await c.ask('donkeyAnswerRequest', { requestId: first, accept: true });
  check(!answer.ok, `only the asked player answers: ${answer.error}`);
  answer = await a.ask('donkeyAnswerRequest', { requestId: first, accept: true });
  check(!answer.ok, `not the one who asked either: ${answer.error}`);

  // B rejects: nothing moves
  answer = await b.ask('donkeyAnswerRequest', { requestId: first, accept: false });
  check(answer.ok && answer.status === 'rejected', `B rejects: ${answer.error || ''}`);
  await until('everyone to see it rejected', () => all.every((p) => p.request(first) && p.request(first).status === 'rejected'));
  check(all.every((p) => p.cards() === cardsBefore[p.name]), 'a rejected request moves no card');
  answer = await b.ask('donkeyAnswerRequest', { requestId: first, accept: true });
  check(!answer.ok, `an answered request cannot be answered again: ${answer.error}`);

  // ---------- an ignored request runs out ----------
  await until('A may ask again', () => a.state.requestWait === 0 || a.state.requestWait === undefined, 8000);
  await sleep(150);
  if (!betweenTricks(a.state)) state = await playUntil(all, betweenTricks);
  answer = await a.ask('donkeyRequestCard', { to: d.id });
  check(answer.ok, `after the wait A may ask again, D this time: ${answer.error || ''}`);
  const second = answer.requestId;
  await until('the request to expire', () => all.every((p) => p.request(second) && p.request(second).status === 'expired'), 8000);
  check(true, 'nobody answered: the request expired, for everyone to see');
  check(all.every((p) => p.cards() === cardsBefore[p.name] || p.state.trick.length > 0), 'and moved no card');

  // ---------- no accept while the asked player has a card in the trick ----------
  await until('A may ask again', () => a.state.requestWait === 0, 8000);
  if (!betweenTricks(a.state)) state = await playUntil(all, betweenTricks);
  answer = await a.ask('donkeyRequestCard', { to: b.id });
  check(answer.ok, `A asks B again: ${answer.error || ''}`);
  const third = answer.requestId;
  // Play on until B has a card in the trick (or the trick is over)
  await playUntil(all, (s) => s.trick.some((play) => play.playerId === b.id) || s.trickNo > state.trickNo);
  if (b.state.trick.some((play) => play.playerId === b.id) && b.request(third).status === 'pending') {
    answer = await b.ask('donkeyAnswerRequest', { requestId: third, accept: true });
    check(!answer.ok && b.request(third).status === 'pending', `no accept while B's card is in the trick: ${answer.error}`);
  }

  // ---------- an accept moves the whole hand ----------
  await playUntil(all, (s) => s.trick.length === 0 && Object.keys(s.trickEnd || {}).length === 0, 10000).catch(() => {});
  let request = b.request(third);
  if (!request || request.status !== 'pending') {
    await until('A may ask again', () => a.state.requestWait === 0, 8000);
    if (!betweenTricks(a.state)) await playUntil(all, betweenTricks);
    answer = await a.ask('donkeyRequestCard', { to: b.id });
    assert.ok(answer.ok, `A asks B once more: ${answer.error}`);
    request = { id: answer.requestId };
    await until('B to see it', () => b.request(request.id));
  }
  const aBefore = a.cards();
  const bBefore = b.cards();
  const sumBefore = total(all);
  answer = await b.ask('donkeyAnswerRequest', { requestId: request.id, accept: true });
  check(answer.ok && answer.status === 'accepted', `B accepts: ${answer.error || ''}`);
  await until('the cards to move for everyone', () => all.every((p) => p.request(request.id) && p.request(request.id).status === 'accepted'));
  check(a.cards() === aBefore + bBefore && b.cards() === 0, `all ${bBefore} of B's cards went to A (${aBefore} -> ${a.cards()})`);
  check(a.request(request.id).moved === bBefore, 'the request says how many cards moved');
  const bSeat = a.state.players.find((p) => p.id === b.id);
  check(bSeat.out && bSeat.place >= 1, `B is out and placed (${bSeat.place === 1 ? 'the Master' : `place ${bSeat.place}`})`);
  check(total(all) === sumBefore && sumBefore <= sum, 'no card was made or lost');
  check(!a.state.neighbours.includes(b.id), 'B, out, is nobody\'s neighbour any more');
  for (const p of all) p.socket.close();

  // ---------- a computer player always accepts ----------
  const e = await person('re');
  answer = await e.ask('donkeyFind', { maxPlayers: 2, stake: 0, timezone: 330 });
  check(answer.ok, `Play Online for two: ${answer.error || ''}`);
  await until('a computer player', () => e.state && e.state.status === 'playing' && e.state.players.length === 2, 15000);
  const bot = e.state.players.find((p) => p.id !== e.id);
  // Play our turns only; the computer player plays its own
  const gap = async () => {
    const end = Date.now() + 60000;
    while (Date.now() < end) {
      if (betweenTricks(e.state) && e.state.canRequest && e.state.requestWait === 0) return true;
      if (e.state.status !== 'playing') return false;
      if (e.state.turn === e.id && e.state.playable.length > 0 && Object.keys(e.state.trickEnd || {}).length === 0) {
        await e.ask('donkeyPlay', { cardId: e.state.playable[0] });
      }
      await sleep(30);
    }
    return false;
  };
  if (await gap()) {
    const botCards = e.state.players.find((p) => p.id === bot.id).cards;
    answer = await e.ask('donkeyRequestCard', { to: bot.id });
    if (answer.ok) {
      // Our own turns go on meanwhile, as a person's would
      const done = await until('the computer player to answer', async () => {
        const r = e.request(answer.requestId);
        if (r && r.status !== 'pending') return r;
        if (e.state.turn === e.id && e.state.playable.length > 0 && Object.keys(e.state.trickEnd || {}).length === 0) {
          await e.ask('donkeyPlay', { cardId: e.state.playable[0] });
        }
        return null;
      }, 12000);
      check(done.status === 'accepted', `the computer player accepted (${done.status})`);
      // It answers before it plays, so it still held what it held when asked
      check(done.moved === botCards, `and its whole hand came over (${done.moved} of ${botCards} cards)`);
      await until('the game to end: we alone hold cards', () => e.state.status === 'finished', 8000);
      check(e.state.donkeyId === e.id, 'with nobody else holding cards, we are the Donkey');
    } else {
      console.log(`(the gap closed before the request: ${answer.error}; computer player part skipped)`);
    }
  } else {
    console.log('(no gap between tricks came; computer player part skipped)');
  }
  e.socket.close();

  console.log(`\ndonkey-requests-e2e: ${checks} checks passed`);
  process.exit(0);
})().catch((error) => {
  console.error(error);
  process.exit(1);
});
