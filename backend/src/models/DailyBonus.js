const crypto = require('crypto');
const db = require('../database/db');
const Coins = require('./Coins');

// The daily bonus: once every 24 hours a player may spin the wheel on the home screen and wins
// the coins of the slot it stops on. The server decides everything. When the last spin was is
// kept in the database, so restarting the app, logging in on another phone or restarting the
// server changes nothing; and which slot the wheel stops on is drawn here, so the app only
// shows the wheel turning to the slot it was told.
//
// The 24 hours count from the moment of the last spin (not from midnight), measured by the
// database's clock alone: the phone's clock is never asked.

// The slots of the wheel, clockwise from the one under the pointer while the wheel is at rest,
// with how often each comes up (weight out of the sum of all weights, here 100).
const SLOTS = [
  { coins: 5000, weight: 2 },
  { coins: 1000, weight: 20 },
  { coins: 2500, weight: 7 },
  { coins: 1500, weight: 13 },
  { coins: 1400, weight: 14 },
  { coins: 2000, weight: 9 },
  { coins: 5000, weight: 2 },
  { coins: 1200, weight: 16 },
  { coins: 6000, weight: 2 },
  { coins: 3000, weight: 5 },
  { coins: 2000, weight: 9 },
  { coins: 10000, weight: 1 },
];
const TOTAL_WEIGHT = SLOTS.reduce((sum, slot) => sum + slot.weight, 0);

// How long a player waits between two spins. Tests shorten it with DAILY_BONUS_SECONDS.
const COOLDOWN_SECONDS = (() => {
  const value = parseFloat(process.env.DAILY_BONUS_SECONDS);
  return Number.isFinite(value) && value > 0 ? value : 24 * 60 * 60;
})();

// The milliseconds still to wait, computed by the database: 0 when the wheel may be spun
const WAIT_MS = `GREATEST(0, CEIL(EXTRACT(EPOCH FROM
  (last_spin_at + make_interval(secs => $2::double precision) - now())) * 1000))::bigint AS wait_ms`;

// A refusal the player can be shown as it is
const refuse = (message, extra) => Object.assign(new Error(message), { forPlayer: true }, extra);

// 5025000 ms -> "1 h 24 min"; under a minute -> "less than a minute"
const describeWait = (ms) => {
  if (ms < 60000) return 'less than a minute';
  const minutes = Math.ceil(ms / 60000);
  const hours = Math.floor(minutes / 60);
  const rest = minutes % 60;
  if (hours === 0) return `${rest} min`;
  return rest === 0 ? `${hours} h` : `${hours} h ${rest} min`;
};

class DailyBonus {
  // The server does this at every start as well as in migrate.js, so an existing database gets
  // the table without a migration. The row goes with the account (ON DELETE CASCADE).
  static async ensureSchema() {
    await db.query(`
      CREATE TABLE IF NOT EXISTS daily_bonus (
        user_id INTEGER PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
        last_spin_at TIMESTAMPTZ NOT NULL,
        last_prize INTEGER NOT NULL DEFAULT 0,
        spins INTEGER NOT NULL DEFAULT 0
      )
    `);
  }

  // The coins on each slot of the wheel, in the order the app draws them
  static prizes() {
    return SLOTS.map((slot) => slot.coins);
  }

  static get COOLDOWN_MS() {
    return COOLDOWN_SECONDS * 1000;
  }

  // Where the player stands: { available, nextSpinIn (ms, 0 when available), cooldown (ms),
  // prizes, lastPrize (0 before the first spin) }
  static async status(userId) {
    const result = await db.query(
      `SELECT last_prize, ${WAIT_MS} FROM daily_bonus WHERE user_id = $1`,
      [userId, COOLDOWN_SECONDS]
    );
    const row = result.rows[0];
    const wait = row ? Number(row.wait_ms) : 0;
    return {
      available: wait === 0,
      nextSpinIn: wait,
      cooldown: DailyBonus.COOLDOWN_MS,
      prizes: DailyBonus.prizes(),
      lastPrize: row ? row.last_prize : 0,
    };
  }

  // Spins the wheel for the player: draws the slot, pays its coins and starts the next 24 hours,
  // all at once or not at all. Returns { index, prize, coins (the balance afterwards),
  // nextSpinIn, cooldown, prizes }.
  //
  // Throws a refusal with { tooEarly: true, nextSpinIn } while the 24 hours are not over. The
  // check and the claim are one statement: two spins sent at the same moment (from two phones,
  // or a tap repeated) find the same row, one waits for the other, and only the first pays.
  static async spin(userId) {
    const index = DailyBonus.draw();
    const prize = SLOTS[index].coins;
    return Coins.transaction(async (client) => {
      let claimed;
      try {
        claimed = await client.query(
          `INSERT INTO daily_bonus (user_id, last_spin_at, last_prize, spins) VALUES ($1, now(), $3, 1)
           ON CONFLICT (user_id) DO UPDATE
             SET last_spin_at = now(), last_prize = $3, spins = daily_bonus.spins + 1
             WHERE daily_bonus.last_spin_at + make_interval(secs => $2::double precision) <= now()
           RETURNING user_id`,
          [userId, COOLDOWN_SECONDS, prize]
        );
      } catch (error) {
        if (error.code === '23503') throw refuse('User not found', { notFound: true }); // account deleted
        throw error;
      }

      if (claimed.rowCount === 0) {
        const result = await client.query(
          `SELECT ${WAIT_MS} FROM daily_bonus WHERE user_id = $1`,
          [userId, COOLDOWN_SECONDS]
        );
        // At least a moment: the row was claimed, so the wheel is not free to spin
        const wait = Math.max(1, Number(result.rows[0] ? result.rows[0].wait_ms : 0));
        throw refuse(
          `You have already spun the wheel in the last 24 hours. The next spin is in ${describeWait(wait)}.`,
          { tooEarly: true, nextSpinIn: wait }
        );
      }

      const balance = await Coins.move(client, userId, null, 'daily_bonus', prize);
      if (balance === null) throw refuse('User not found', { notFound: true }); // rolls the claim back
      return {
        index,
        prize,
        coins: balance,
        available: false,
        nextSpinIn: DailyBonus.COOLDOWN_MS,
        cooldown: DailyBonus.COOLDOWN_MS,
        prizes: DailyBonus.prizes(),
      };
    });
  }

  // A slot, by weight, from the system's secure random numbers
  static draw() {
    let ticket = crypto.randomInt(TOTAL_WEIGHT);
    for (let index = 0; index < SLOTS.length; index++) {
      ticket -= SLOTS[index].weight;
      if (ticket < 0) return index;
    }
    return 0; // not reached
  }
}

DailyBonus.SLOTS = SLOTS;
DailyBonus.describeWait = describeWait;

module.exports = DailyBonus;
