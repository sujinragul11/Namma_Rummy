'use strict';
// The backend for the Godot tests: the real server code, on its own port and its own
// database, able to deal fixed hands so that a test knows which cards it holds.
//
//   node tests/test_server.js --fresh --port=3101 --db=My_Rummy_test --rig-flag=<file>
//
// --fresh      drop and re-create the database first
// --forget-games  start as if the games of the previous run had been lost: their players
//              then sit at tables this server knows nothing about (tests/server_restart)
// --rig-flag   while this file exists, deals are fixed. What is in the file names the deal:
//                closed         the hands in CLOSED_DEAL below, for the Close Joker test
//                anything else  the deck as it comes out of the box, with the first card (A♠) cut
// The tests are given the same --rig-flag and create and remove the file themselves.
// Stop the server with Ctrl+C. It refuses the real port and any database not named ..._test.

const fs = require('fs');
const path = require('path');
const { execFileSync } = require('child_process');

const BACKEND = path.join(__dirname, '..', '..', 'backend');

// Two hands that sorting by suit leaves without a run, so the joker stays closed for both;
// the first player can make 2-3-4 of spades to open it, the second can make nothing.
const CLOSED_DEAL = {
  joker: '7♥',
  hands: [
    ['2♠', '3♠', '4♠', '9♠', '5♥', '6♥', 'J♥', '2♦', '8♦', 'K♦', '3♣', '10♣', 'Q♣'],
    ['A♠', '5♠', '10♠', 'K♠', '2♥', '9♥', 'Q♥', '4♦', '6♦', 'J♦', '5♣', '8♣', 'A♣'],
  ],
  open: '9♦',
};

function option(name, fallback) {
  const prefix = `--${name}=`;
  const found = process.argv.find((argument) => argument.startsWith(prefix));
  return found ? found.slice(prefix.length) : fallback;
}

const port = option('port', '3101');
const database = option('db', 'My_Rummy_test');
const rigFlag = option('rig-flag', '');

if (port === '3001' || !database.endsWith('_test')) {
  console.error('Refusing to run: use a port other than 3001 and a database whose name ends in _test.');
  process.exit(1);
}

process.chdir(BACKEND);
require(path.join(BACKEND, 'node_modules', 'dotenv')).config();
process.env.DB_NAME = database; // set before the server reads its settings
process.env.PORT = port;

// The name of the deal asked for, or '' for a normal shuffle.
function riggedDeal() {
  if (!rigFlag || !fs.existsSync(rigFlag)) return '';
  return fs.readFileSync(rigFlag, 'utf8').trim() || 'plain';
}

// Lays the deck out so that dealing hands out exactly the cards of `deal`:
// the cut card first, then the rest, the open card, and the hands on top.
function stack(deck, deal) {
  const byCode = new Map(deck.map((card) => [card.code, card]));
  const take = (code) => {
    const card = byCode.get(code);
    byCode.delete(code);
    return card;
  };
  const cut = take(deal.joker);
  const hands = deal.hands.map((hand) => hand.map(take));
  const open = take(deal.open);
  // Cards are dealt from the end: the first hand, the second, then the open card
  const onTop = hands.slice().reverse().flatMap((hand) => hand.slice().reverse());
  return [cut, ...byCode.values(), open, ...onTop];
}

function rigDeals() {
  const DeckManager = require(path.join(BACKEND, 'src', 'game', 'DeckManager'));
  const realShuffle = DeckManager.prototype.shuffle;
  const realPick = DeckManager.prototype.pickRandomCard;
  DeckManager.prototype.shuffle = function () {
    const deal = riggedDeal();
    if (!deal) return realShuffle.call(this);
    // The stacked deal is written for one pack of cards, which is what two players get
    if (deal === 'closed' && this.numDecks === 1) this.deck = stack(this.deck, CLOSED_DEAL);
    return this.deck;
  };
  DeckManager.prototype.pickRandomCard = function () {
    return riggedDeal() ? this.deck.splice(0, 1)[0] : realPick.call(this);
  };
}

async function freshDatabase() {
  const { Client } = require(path.join(BACKEND, 'node_modules', 'pg'));
  const client = new Client({
    host: process.env.DB_HOST,
    port: process.env.DB_PORT,
    user: process.env.DB_USER,
    password: process.env.DB_PASSWORD,
    database: 'postgres',
  });
  await client.connect();
  try {
    await client.query(`DROP DATABASE IF EXISTS "${database}" WITH (FORCE)`);
    await client.query(`CREATE DATABASE "${database}"`);
  } finally {
    await client.end();
  }
  execFileSync(process.execPath, ['src/database/migrate.js'], { cwd: BACKEND, env: process.env, stdio: 'inherit' });
}

// Throws away what the previous run kept of its games in progress.
async function forgetGames() {
  const { Client } = require(path.join(BACKEND, 'node_modules', 'pg'));
  const client = new Client({
    host: process.env.DB_HOST,
    port: process.env.DB_PORT,
    user: process.env.DB_USER,
    password: process.env.DB_PASSWORD,
    database,
  });
  await client.connect();
  try {
    await client.query('UPDATE games SET snapshot = NULL');
  } finally {
    await client.end();
  }
}

(async () => {
  if (process.argv.includes('--fresh')) await freshDatabase();
  if (process.argv.includes('--forget-games')) await forgetGames();
  rigDeals();
  console.log(`Test server: port ${port}, database ${database}${rigFlag ? `, rig flag ${rigFlag}` : ''}`);
  require(path.join(BACKEND, 'src', 'server.js'));
})().catch((error) => {
  console.error('Test server error:', error.message);
  process.exit(1);
});
