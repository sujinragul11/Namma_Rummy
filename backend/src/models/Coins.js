const db = require('../database/db');

// Play coins. Every account starts with STARTING_COINS. Sitting down at a table costs its
// entry, and whoever wins the game takes everything that was paid in. Coins are play money:
// nothing here sells them or pays them out.
const STARTING_COINS = 50000;
// What a table can cost to sit at; 0 is a free table
const STAKES = [0, 1000, 2000, 5000, 10000, 25000, 50000];

// 125000 -> "1,25,000": the way amounts are written in India
const format = (amount) => Number(amount).toLocaleString('en-IN');

class Coins {
  static isStake(value) {
    return STAKES.includes(value);
  }

  // Databases made before coins existed get what coins need here; the server calls it at startup
  static async ensureSchema() {
    await db.query(
      `ALTER TABLE users ADD COLUMN IF NOT EXISTS coins INTEGER NOT NULL DEFAULT ${STARTING_COINS}`
    );
    // Who has paid to sit at which table. A row is there from the moment the entry is paid
    // until it is given back or paid out, so nothing is ever charged or paid twice, also not
    // when the server stops in between.
    await db.query(`
      CREATE TABLE IF NOT EXISTS game_entries (
        id SERIAL PRIMARY KEY,
        game_id UUID NOT NULL REFERENCES games(id) ON DELETE CASCADE,
        user_id INTEGER REFERENCES users(id) ON DELETE SET NULL,
        amount INTEGER NOT NULL,
        paid_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        UNIQUE (game_id, user_id)
      )
    `);
    // The history of every balance was sized for small amounts
    await db.query(`
      ALTER TABLE transactions
        ALTER COLUMN amount TYPE NUMERIC(14,2),
        ALTER COLUMN balance_before TYPE NUMERIC(14,2),
        ALTER COLUMN balance_after TYPE NUMERIC(14,2)
    `);
  }

  static async balance(userId) {
    const result = await db.query(`SELECT coins FROM users WHERE id = $1`, [userId]);
    return result.rows[0] ? result.rows[0].coins : 0;
  }

  // Pays the entry of a table and returns the balance afterwards. Paying for the same table
  // again charges nothing. Throws when the player does not have the coins.
  static async enter(userId, gameId, amount) {
    return Coins.transaction(async (client) => {
      const entry = await client.query(
        `INSERT INTO game_entries (game_id, user_id, amount) VALUES ($1, $2, $3)
         ON CONFLICT (game_id, user_id) DO NOTHING
         RETURNING id`,
        [gameId, userId, amount]
      );
      if (entry.rowCount > 0) {
        const balance = await Coins.move(client, userId, gameId, 'entry', -amount);
        if (balance === null) {
          throw new Error(`You need ${format(amount)} coins to sit at this table`);
        }
        return balance;
      }
      const current = await client.query(`SELECT coins FROM users WHERE id = $1`, [userId]);
      return current.rows[0] ? current.rows[0].coins : 0;
    });
  }

  // Gives a player their entry back, e.g. when they leave before the game has started.
  // Returns the balance afterwards, or null when there was nothing to give back.
  static async refund(userId, gameId) {
    return Coins.transaction(async (client) => {
      const entry = await client.query(
        `DELETE FROM game_entries WHERE game_id = $1 AND user_id = $2 RETURNING amount`,
        [gameId, userId]
      );
      if (entry.rowCount === 0) return null;
      return Coins.move(client, userId, gameId, 'refund', entry.rows[0].amount);
    });
  }

  // The game is over: everything that was paid in goes to the winner. Returns the pot and the
  // winner's balance afterwards; a second call finds nothing left to pay.
  static async payWinner(gameId, winnerId) {
    return Coins.transaction(async (client) => {
      const entries = await client.query(
        `DELETE FROM game_entries WHERE game_id = $1 RETURNING amount`,
        [gameId]
      );
      const pot = entries.rows.reduce((sum, entry) => sum + entry.amount, 0);
      if (pot === 0) return { pot: 0, balance: null };
      // null when the winner's account no longer exists
      const balance = await Coins.move(client, winnerId, gameId, 'win', pot);
      return { pot, balance };
    });
  }

  // The game ended without a winner: everyone gets their own entry back.
  // Returns [{ userId, balance }] for the players who got something.
  static async refundAll(gameId) {
    return Coins.transaction(async (client) => {
      const entries = await client.query(
        `DELETE FROM game_entries WHERE game_id = $1 RETURNING user_id, amount`,
        [gameId]
      );
      const refunded = [];
      for (const entry of entries.rows) {
        if (entry.user_id === null) continue; // the account was deleted meanwhile
        const balance = await Coins.move(client, entry.user_id, gameId, 'refund', entry.amount);
        if (balance !== null) refunded.push({ userId: String(entry.user_id), balance });
      }
      return refunded;
    });
  }

  // Entries of games that are closed without anybody having been paid, which happens when the
  // server stops at the wrong moment or loses a game: they go back to the players.
  // Returns how many games that were.
  static async refundClosedGames() {
    const games = await db.query(
      `SELECT DISTINCT e.game_id
       FROM game_entries e JOIN games g ON g.id = e.game_id
       WHERE g.status IN ('abandoned', 'finished')`
    );
    for (const row of games.rows) {
      await Coins.refundAll(row.game_id);
    }
    return games.rowCount;
  }

  // Adds `amount` (negative to take) and writes the line in the history. Returns the balance
  // afterwards, or null when the player would end up below zero or does not exist.
  static async move(client, userId, gameId, type, amount) {
    const result = await client.query(
      `UPDATE users SET coins = coins + $2, updated_at = CURRENT_TIMESTAMP
       WHERE id = $1 AND coins + $2 >= 0
       RETURNING coins`,
      [userId, amount]
    );
    if (result.rowCount === 0) return null;

    const balance = result.rows[0].coins;
    await client.query(
      `INSERT INTO transactions (user_id, type, amount, game_id, balance_before, balance_after)
       VALUES ($1, $2, $3, $4, $5, $6)`,
      [userId, type, amount, gameId, balance - amount, balance]
    );
    return balance;
  }

  // Everything that moves coins happens completely or not at all
  static async transaction(work) {
    const client = await db.pool.connect();
    try {
      await client.query('BEGIN');
      const result = await work(client);
      await client.query('COMMIT');
      return result;
    } catch (error) {
      await client.query('ROLLBACK');
      throw error;
    } finally {
      client.release();
    }
  }
}

Coins.STARTING_COINS = STARTING_COINS;
Coins.STAKES = STAKES;
Coins.format = format;

module.exports = Coins;
