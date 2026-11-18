const crypto = require('crypto');
const bcrypt = require('bcrypt');
const db = require('../database/db');
const Coins = require('../models/Coins');

// Computer players. When a player has waited a little while for Play Now (rummy) or Play
// Online (Donkey Master) and not enough people come, computer players fill the empty seats
// (see Matchmaker). The owner's choice (2026-11-18): they look exactly like people in the app,
// and only the rules and the terms say that computer players fill empty seats.
//
// So each one is an ordinary account, marked is_bot, with a username like people choose, no
// photo, its own coins, games and wins. Nobody can log in to it: it has no phone number and a
// random password nobody knows. It pays a table's entry and wins or loses like anyone else;
// when one runs short of coins it is given some more (type 'bot_topup' in the history).

const POOL_SIZE = 40; // made at server start; more are made when they are all busy
const RESERVE_MS = 15000; // a table seats the computer players it chose well within this

const NAMES = [
  'Karthik', 'Vignesh', 'Priya', 'Divya', 'Arun', 'Muthu', 'Selvi', 'Ramesh', 'Senthil',
  'Kavitha', 'Bala', 'Deepa', 'Gopi', 'Lakshmi', 'Mani', 'Nandhini', 'Prakash', 'Revathi',
  'Saravanan', 'Vijay', 'Anitha', 'Dinesh', 'Gayathri', 'Hari', 'Ilango', 'Jaya', 'Kumar',
  'Meena', 'Naveen', 'Pandi', 'Ragu', 'Sathya', 'Thenmozhi', 'Uma', 'Velu', 'Yamuna', 'Ajith',
  'Surya', 'Keerthi', 'Murugan', 'Sakthi', 'Durai', 'Malar', 'Raja', 'Sundar', 'Babu', 'Kannan'
];
const INITIALS = 'ABGKMNPRSTV';

const pick = (list) => list[crypto.randomInt(list.length)];
const digits = (count) => String(crypto.randomInt(10 ** (count - 1), 10 ** count));

// A username of the kinds people choose: "Karthik_87", "priya2k", "Vignesh R", "muthu.raja"
function makeUsername() {
  const name = pick(NAMES);
  const styles = [
    () => `${name}_${digits(2)}`,
    () => `${name.toLowerCase()}${digits(2)}`,
    () => `${name} ${pick(INITIALS.split(''))}`,
    () => `${name.toLowerCase()}.${pick(NAMES).toLowerCase()}`,
    () => `${name}${digits(3)}`,
    () => `${name.toLowerCase()}_${pick(['tn', 'mdu', 'cbe', 'chennai', 'trichy'])}`,
    () => name
  ];
  return pick(styles)().slice(0, 20);
}

class BotAccounts {
  constructor() {
    this.ids = new Set(); // user ids of the computer players
    this.names = new Map(); // user id -> username
    this.reserved = new Set(); // chosen for a table that is still seating them
  }

  // The server does this at every start: the column, and the computer players it has. Making
  // the ones still missing (a new database) does not hold up the start: that goes on alone.
  async prepare() {
    await db.query(`ALTER TABLE users ADD COLUMN IF NOT EXISTS is_bot BOOLEAN NOT NULL DEFAULT FALSE`);
    const result = await db.query(`SELECT id, username FROM users WHERE is_bot`);
    for (const row of result.rows) this.remember(row);
    this.filling = this.fill().catch((error) => console.error('Failed to make computer players:', error.message));
  }

  async fill() {
    while (this.ids.size < POOL_SIZE) await this.create();
  }

  remember(row) {
    const id = String(row.id);
    this.ids.add(id);
    this.names.set(id, row.username);
  }

  isBot(userId) {
    return this.ids.has(String(userId));
  }

  // A new computer player; a username that is taken already is drawn again
  async create() {
    // The password is 64 random hex digits nobody is told: a quick hash is safe enough
    const hash = await bcrypt.hash(crypto.randomBytes(32).toString('hex'), 4);
    for (let attempt = 0; attempt < 20; attempt++) {
      const result = await db.query(
        `INSERT INTO users (username, password_hash, is_bot) VALUES ($1, $2, TRUE)
         ON CONFLICT (username) DO NOTHING
         RETURNING id, username`,
        [makeUsername(), hash]
      );
      if (result.rows[0]) {
        this.remember(result.rows[0]);
        return { id: String(result.rows[0].id), username: result.rows[0].username };
      }
    }
    throw new Error('Could not find a free username for a computer player');
  }

  // `count` computer players who are not busy (`isBusy(id)`), each with at least `coins`
  // coins, in random order: [{ id, username }]
  // The ones chosen are held back from other tables for a moment, until their own table has
  // seated them: two tables starting at once never get the same computer player.
  async pickFree(count, isBusy, coins) {
    const free = [...this.ids].filter((id) => !isBusy(id) && !this.reserved.has(id));
    for (let i = free.length - 1; i > 0; i--) {
      const j = crypto.randomInt(i + 1);
      [free[i], free[j]] = [free[j], free[i]];
    }
    const chosen = free.slice(0, count).map((id) => ({ id, username: this.names.get(id) }));
    this.reserve(chosen);
    while (chosen.length < count) {
      const made = await this.create();
      this.reserve([made]);
      chosen.push(made);
    }
    for (const bot of chosen) await this.ensureCoins(bot.id, coins);
    return chosen;
  }

  reserve(bots) {
    for (const bot of bots) this.reserved.add(bot.id);
    const timer = setTimeout(() => bots.forEach((bot) => this.reserved.delete(bot.id)), RESERVE_MS);
    if (timer.unref) timer.unref();
  }

  // A computer player short of coins for a table gets some more: what the table needs and an
  // ordinary-looking amount on top, as a player's balance looks in their profile
  async ensureCoins(userId, needed) {
    const balance = await Coins.balance(userId);
    if (balance >= needed) return balance;
    const target = needed + 20000 + crypto.randomInt(130000);
    return Coins.transaction((client) => Coins.move(client, userId, null, 'bot_topup', target - balance));
  }
}

module.exports = new BotAccounts();
module.exports.BotAccounts = BotAccounts;
module.exports.makeUsername = makeUsername;
