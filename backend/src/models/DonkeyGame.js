const db = require('../database/db');
const Coins = require('./Coins');
const { v4: uuidv4 } = require('uuid');

// Donkey Master tables in the database, and the coins paid to sit at them. They have their own
// tables, apart from rummy's `games`, so that nothing rummy does at startup (bringing games
// back, closing stale ones, giving back entries) ever touches a Donkey Master table, and the
// other way round. The coins are the same: users.coins, written through Coins.move, so both
// games share one balance and one history (transactions, with these types and no game_id).
const ENTRY = 'donkey_entry';
const REFUND = 'donkey_refund';
const WIN = 'donkey_win';

class DonkeyGame {
  // The server calls this at startup; it only adds what is missing
  static async ensureSchema() {
    await db.query(`
      CREATE TABLE IF NOT EXISTS donkey_games (
        id UUID PRIMARY KEY,
        room_code VARCHAR(10) NOT NULL,
        is_private BOOLEAN NOT NULL DEFAULT FALSE,
        max_players INTEGER NOT NULL,
        stake INTEGER NOT NULL DEFAULT 0,
        status VARCHAR(12) NOT NULL DEFAULT 'waiting',
        created_by INTEGER REFERENCES users(id) ON DELETE SET NULL,
        snapshot JSONB,
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        started_at TIMESTAMP,
        ended_at TIMESTAMP
      )
    `);
    await db.query(`CREATE UNIQUE INDEX IF NOT EXISTS donkey_games_room_code ON donkey_games (room_code)`);
    await db.query(`CREATE INDEX IF NOT EXISTS donkey_games_status ON donkey_games (status)`);
    // Who has paid to sit at which table: a row from the moment the entry is paid until it is
    // given back or paid out, so nothing is charged or paid twice, also across a restart
    await db.query(`
      CREATE TABLE IF NOT EXISTS donkey_entries (
        id SERIAL PRIMARY KEY,
        game_id UUID NOT NULL REFERENCES donkey_games(id) ON DELETE CASCADE,
        user_id INTEGER REFERENCES users(id) ON DELETE SET NULL,
        amount INTEGER NOT NULL,
        paid_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        UNIQUE (game_id, user_id)
      )
    `);
  }

  // A new table. Throws with code 23505 when the room code is taken (the caller tries another).
  static async create({ roomCode, isPrivate, maxPlayers, stake, createdBy }) {
    const id = uuidv4();
    await db.query(
      `INSERT INTO donkey_games (id, room_code, is_private, max_players, stake, created_by)
       VALUES ($1, $2, $3, $4, $5, $6)`,
      [id, roomCode, isPrivate, maxPlayers, stake, createdBy]
    );
    return id;
  }

  static async setStatus(id, status) {
    const stamp = status === 'playing' ? ', started_at = CURRENT_TIMESTAMP'
      : status === 'finished' || status === 'abandoned' ? ', ended_at = CURRENT_TIMESTAMP' : '';
    await db.query(`UPDATE donkey_games SET status = $2${stamp} WHERE id = $1`, [id, status]);
  }

  static async saveSnapshot(id, snapshot) {
    await db.query(`UPDATE donkey_games SET snapshot = $2 WHERE id = $1`, [id, JSON.stringify(snapshot)]);
  }

  static async clearSnapshot(id) {
    await db.query(`UPDATE donkey_games SET snapshot = NULL WHERE id = $1`, [id]);
  }

  // The tables that were open when the server last stopped
  static async findResumable() {
    const result = await db.query(
      `SELECT id, snapshot FROM donkey_games WHERE status IN ('waiting', 'playing') AND snapshot IS NOT NULL`
    );
    return result.rows;
  }

  // Closes the open tables that were not brought back
  static async abandonUnfinished(keepIds) {
    const result = await db.query(
      `UPDATE donkey_games SET status = 'abandoned', ended_at = CURRENT_TIMESTAMP
       WHERE status IN ('waiting', 'playing') AND NOT (id = ANY($1::uuid[]))`,
      [keepIds]
    );
    return result.rowCount;
  }

  // ---------- coins ----------

  // Pays the entry and returns the balance afterwards. Paying again for the same table charges
  // nothing. Throws when the player does not have the coins.
  static async enter(userId, gameId, amount) {
    return Coins.transaction(async (client) => {
      const entry = await client.query(
        `INSERT INTO donkey_entries (game_id, user_id, amount) VALUES ($1, $2, $3)
         ON CONFLICT (game_id, user_id) DO NOTHING RETURNING id`,
        [gameId, userId, amount]
      );
      if (entry.rowCount > 0) {
        const balance = await Coins.move(client, userId, null, ENTRY, -amount);
        if (balance === null) throw new Error(`You need ${Coins.format(amount)} coins to sit at this table`);
        return balance;
      }
      const current = await client.query(`SELECT coins FROM users WHERE id = $1`, [userId]);
      return current.rows[0] ? current.rows[0].coins : 0;
    });
  }

  // Gives one player's entry back (they got up before the deal). The balance, or null.
  static async refund(userId, gameId) {
    return Coins.transaction(async (client) => {
      const entry = await client.query(
        `DELETE FROM donkey_entries WHERE game_id = $1 AND user_id = $2 RETURNING amount`,
        [gameId, userId]
      );
      if (entry.rowCount === 0) return null;
      return Coins.move(client, userId, null, REFUND, entry.rows[0].amount);
    });
  }

  // The game is over: `payouts` maps a user id to the coins they get back (their own entry
  // included; see DonkeyEngine.settlement). Everything still paid in for the table is taken
  // out in the same transaction, so a second call pays nothing. Returns [{ userId, balance }].
  static async settle(gameId, payouts) {
    return Coins.transaction(async (client) => {
      const entries = await client.query(
        `DELETE FROM donkey_entries WHERE game_id = $1 RETURNING user_id, amount`,
        [gameId]
      );
      const pot = entries.rows.reduce((sum, entry) => sum + entry.amount, 0);
      const owed = Object.values(payouts).reduce((sum, coins) => sum + Math.max(0, Number(coins) || 0), 0);
      const paid = [];
      if (pot === 0) return paid;
      if (owed > pot) {
        // Never pay out more than was paid in: give everyone their own entry back instead
        console.error(`Donkey table ${gameId}: payouts ${owed} exceed the pot ${pot}; refunding`);
        for (const entry of entries.rows) {
          if (entry.user_id === null) continue;
          const balance = await Coins.move(client, entry.user_id, null, REFUND, entry.amount);
          if (balance !== null) paid.push({ userId: String(entry.user_id), balance });
        }
        return paid;
      }
      const paidIn = new Map(entries.rows.filter((e) => e.user_id !== null).map((e) => [String(e.user_id), e.amount]));
      for (const [userId, coins] of Object.entries(payouts)) {
        const amount = Math.max(0, Number(coins) || 0);
        if (amount === 0) continue;
        // Paid only to players who really paid in (a deleted account cannot be paid)
        if (!paidIn.has(userId)) continue;
        const type = amount > paidIn.get(userId) ? WIN : REFUND;
        const balance = await Coins.move(client, userId, null, type, amount);
        if (balance !== null) paid.push({ userId, balance });
      }
      return paid;
    });
  }

  // The table closed without a result: everyone gets their own entry back
  static async refundAll(gameId) {
    return Coins.transaction(async (client) => {
      const entries = await client.query(
        `DELETE FROM donkey_entries WHERE game_id = $1 RETURNING user_id, amount`,
        [gameId]
      );
      const refunded = [];
      for (const entry of entries.rows) {
        if (entry.user_id === null) continue;
        const balance = await Coins.move(client, entry.user_id, null, REFUND, entry.amount);
        if (balance !== null) refunded.push({ userId: String(entry.user_id), balance });
      }
      return refunded;
    });
  }

  // Entries still held for tables that are closed (the server stopped at the wrong moment):
  // a finished table whose result was kept pays it out, any other gives the entries back.
  static async settleClosed() {
    const result = await db.query(
      `SELECT DISTINCT g.id, g.status, g.snapshot
       FROM donkey_entries e JOIN donkey_games g ON g.id = e.game_id
       WHERE g.status IN ('abandoned', 'finished')`
    );
    return result.rows;
  }
}

DonkeyGame.ENTRY = ENTRY;
DonkeyGame.REFUND = REFUND;
DonkeyGame.WIN = WIN;

module.exports = DonkeyGame;
