// Donkey Master survives a restart of the server: a table in play comes back as it was, its
// players return to it, and its coins are settled once. Starts and stops its own test server.
//   node tests/donkey-restart.js --port=3195 --server=<godot/tests/test_server.js>
const assert = require('node:assert/strict');
const fs = require('fs');
const path = require('path');
const { spawn } = require('child_process');
const { io } = require([process.env.SOCKET_IO_CLIENT, path.join(__dirname, '..', '..', 'mobile', 'node_modules', 'socket.io-client')]
  .find((place) => place && fs.existsSync(place)));

const option = (name, fallback) => {
  const found = process.argv.find((arg) => arg.startsWith(`--${name}=`));
  return found ? found.slice(name.length + 3) : fallback;
};
const PORT = option('port', '3195');
const URL = `http://127.0.0.1:${PORT}`;
const SERVER = option('server', path.join(__dirname, '..', '..', 'godot', 'tests', 'test_server.js'));
const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));
let checks = 0;
const equal = (actual, expected, message) => { assert.deepEqual(actual, expected, message); checks++; };

async function until(what, test, ms = 20000) {
  const end = Date.now() + ms;
  while (Date.now() < end) {
    const value = await test();
    if (value) return value;
    await sleep(50);
  }
  throw new Error(`timed out waiting for ${what}`);
}

let server = null;
async function startServer(fresh) {
  const args = [SERVER, `--port=${PORT}`, '--db=My_Rummy_donkey_restart_test'];
  if (fresh) args.push('--fresh');
  server = spawn(process.execPath, args, {
    env: { ...process.env, DONKEY_TURN_SECONDS: '30', DONKEY_TRICK_PAUSE_SECONDS: '0.1', DONKEY_DEAL_SECONDS: '0' },
    stdio: ['ignore', 'pipe', 'pipe']
  });
  server.log = '';
  server.stdout.on('data', (data) => { server.log += data; });
  server.stderr.on('data', (data) => { server.log += data; });
  await until('the server', async () => fetch(`${URL}/health`).then((r) => r.ok).catch(() => false));
}

async function stopServer() {
  const done = new Promise((resolve) => server.once('exit', resolve));
  server.kill();
  await done;
}

async function http(method, route, body, token) {
  const response = await fetch(URL + route, {
    method,
    headers: { 'Content-Type': 'application/json', ...(token ? { Authorization: `Bearer ${token}` } : {}) },
    body: body ? JSON.stringify(body) : undefined
  });
  return response.json();
}

async function player(name, n) {
  const data = await http('POST', '/api/auth/register', { username: `${name}${Date.now() % 100000}`, phone: `+91970000${String(Date.now() % 1000).padStart(3, '0')}${n}`, password: 'secret123' });
  const me = { id: String(data.user.id), token: data.token, state: null, coins: null };
  me.connect = () => new Promise((resolve, reject) => {
    me.socket = io(URL, { auth: { token: me.token }, transports: ['websocket'], forceNew: true, reconnection: false });
    me.socket.on('connect', resolve);
    me.socket.on('connect_error', reject);
    me.socket.on('donkeyState', (state) => { me.state = state; });
    me.socket.on('coins', (payload) => { me.coins = payload.coins; });
  });
  me.ask = (event, payload = {}) => new Promise((resolve) => me.socket.emit(event, payload, resolve));
  me.balance = async () => (await http('GET', '/api/user/profile', null, me.token)).user.coins;
  await me.connect();
  return me;
}

(async () => {
  await startServer(true);
  const a = await player('rea', 1);
  const b = await player('reb', 2);
  const created = await a.ask('donkeyCreate', { maxPlayers: 2, stake: 5000 });
  await b.ask('donkeyJoin', { roomCode: created.roomCode });
  await until('the deal', () => a.state && a.state.status === 'playing' && b.state && b.state.status === 'playing');
  // a few moves, so the table is not as it was dealt
  for (let i = 0; i < 6; i++) {
    const mover = [a, b].find((p) => p.state.turn === p.id && p.state.playable.length > 0);
    if (!mover) { await sleep(100); continue; }
    const trick = mover.state.trickNo * 10 + mover.state.trick.length;
    await mover.ask('donkeyPlay', { cardId: mover.state.playable[0] });
    await until('the move', () => mover.state.trickNo * 10 + mover.state.trick.length !== trick || Object.keys(mover.state.trickEnd).length > 0);
    await sleep(150);
  }
  const before = { hand: a.state.hand.map((c) => c.id), trickNo: a.state.trickNo, turn: a.state.turn, discarded: a.state.discarded };
  equal(await a.balance(), 45000, 'entry paid before the restart');

  for (const p of [a, b]) p.socket.disconnect();
  await stopServer();
  await startServer(false);
  for (const p of [a, b]) { p.state = null; await p.connect(); }
  await until('back at the table', () => a.state && b.state);
  equal({ hand: a.state.hand.map((c) => c.id), trickNo: a.state.trickNo, turn: a.state.turn, discarded: a.state.discarded }, before, 'the table as it was');
  equal(a.state.status, 'playing', 'still being played');
  equal(await a.balance(), 45000, 'the entry was not given back by the restart');

  // play it out
  for (let moves = 0; moves < 600 && a.state.status === 'playing'; moves++) {
    const mover = [a, b].find((p) => p.state.turn === p.id && p.state.playable.length > 0 && Object.keys(p.state.trickEnd).length === 0);
    if (!mover) { await sleep(30); continue; }
    const step = mover.state.trickNo * 100 + mover.state.trick.length;
    await mover.ask('donkeyPlay', { cardId: mover.state.playable[0] });
    await until('the move', () => mover.state.status !== 'playing' || mover.state.trickNo * 100 + mover.state.trick.length !== step || Object.keys(mover.state.trickEnd).length > 0);
  }
  equal(a.state.status, 'finished', 'finished after the restart');
  await sleep(500);
  const total = (await a.balance()) + (await b.balance());
  equal(total, 100000, 'the pot paid out once: no coins made or lost');
  const master = a.state.masterId === a.id ? a : b;
  equal(await master.balance(), 55000, 'the Master won the Donkey\'s entry');

  // a second restart: the finished table is not paid again
  for (const p of [a, b]) p.socket.disconnect();
  await stopServer();
  await startServer(false);
  equal((await a.balance()) + (await b.balance()), 100000, 'nothing paid twice after another restart');
  await stopServer();
  console.log(`donkey-restart: all ${checks} checks passed`);
  process.exit(0);
})().catch(async (error) => {
  console.error('donkey-restart FAILED:', error, server && server.log.slice(-3000));
  if (server) server.kill();
  process.exit(1);
});
