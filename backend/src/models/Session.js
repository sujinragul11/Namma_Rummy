const crypto = require('crypto');
const jwt = require('jsonwebtoken');
const db = require('../database/db');
const config = require('../config');

// A login. Logging in or registering starts one and hands the app its token, which the app
// keeps and sends with every request and when its game socket connects. A login does not run
// out: it lasts until the player logs out on that phone, or until the server ends it (the
// account is deleted, or src/database/revoke-logins.js ends all of an account's logins when
// it may have been taken over). Every request checks it, so an ended login stops working at
// once, on every phone that held it.
//
// The token is 32 random bytes. The server keeps only its SHA-256 hash, so the table alone
// is not enough to log in as anybody.
const TOKEN_BYTES = 32;
// When a login was last used is written at most this often, not at every request
const TOUCH_INTERVAL_MS = 60 * 60 * 1000;

const ENDED = 'Your login has ended. Please log in again.';
const REVOKED = 'You were logged out to keep your account safe. Please log in again.';

const hash = (token) => crypto.createHash('sha256').update(token).digest('hex');

// The token is not (or no longer) a login. Any other error while checking one, such as the
// database not answering, says nothing about the token: the app keeps it and tries again.
const ended = (message = ENDED) => Object.assign(new Error(message), { sessionEnded: true });

class Session {
  // The server does this at every start as well as in migrate.js, so an existing database
  // gets the table without a migration. Logins go with the account (ON DELETE CASCADE).
  static async ensureSchema() {
    await db.query(`
      CREATE TABLE IF NOT EXISTS user_sessions (
        id SERIAL PRIMARY KEY,
        user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
        token_hash CHAR(64) NOT NULL UNIQUE,
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        last_used_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        revoked_at TIMESTAMP,
        revoked_reason VARCHAR(50)
      )
    `);
    await db.query(`CREATE INDEX IF NOT EXISTS idx_user_sessions_user ON user_sessions(user_id)`);
  }

  static ended(message) {
    return ended(message);
  }

  // Starts a login for the player and returns its token, the only time the token exists in full
  static async create(userId) {
    const token = crypto.randomBytes(TOKEN_BYTES).toString('base64url');
    await db.query(`INSERT INTO user_sessions (user_id, token_hash) VALUES ($1, $2)`, [userId, hash(token)]);
    return token;
  }

  // Whose login a token is: { userId, sessionId }. Throws an error with `sessionEnded` set
  // when the token is not a login, or one that has ended.
  static async verify(token) {
    if (typeof token !== 'string' || token.length === 0 || token.length > 2048) throw ended();
    if (token.split('.').length === 3) return Session.verifyOldToken(token);

    const result = await db.query(
      `SELECT id, user_id, revoked_at, last_used_at FROM user_sessions WHERE token_hash = $1`,
      [hash(token)]
    );
    const row = result.rows[0];
    if (!row) throw ended();
    if (row.revoked_at) throw ended(REVOKED);

    if (Date.now() - new Date(row.last_used_at).getTime() > TOUCH_INTERVAL_MS) {
      db.query(`UPDATE user_sessions SET last_used_at = CURRENT_TIMESTAMP WHERE id = $1`, [row.id])
        .catch((error) => console.warn('⚠️  Failed to note a login as used:', error.message));
    }
    return { userId: row.user_id, sessionId: row.id };
  }

  // Before logins were kept on the server, the app was given a token that ran out after 24
  // hours. Phones that still hold one stay logged in until it runs out; from their next login
  // on they get a login that lasts.
  static async verifyOldToken(token) {
    let payload;
    try {
      payload = jwt.verify(token, config.jwtSecret, { algorithms: ['HS256'] });
    } catch (error) {
      throw ended();
    }
    const userId = Number(payload && payload.id);
    if (!Number.isInteger(userId)) throw ended();
    const result = await db.query(`SELECT 1 FROM users WHERE id = $1`, [userId]);
    if (result.rowCount === 0) throw ended();
    return { userId, sessionId: null };
  }

  // Logging out: this login is gone and its token no longer works anywhere
  static async end(sessionId) {
    await db.query(`DELETE FROM user_sessions WHERE id = $1`, [sessionId]);
  }

  // Ends every login of the account, for its safety. The rows stay, marked, so a phone that
  // comes back with one of the tokens is told why it was logged out. Returns how many ended.
  static async revokeAll(userId, reason = 'security') {
    const result = await db.query(
      `UPDATE user_sessions SET revoked_at = CURRENT_TIMESTAMP, revoked_reason = $2
       WHERE user_id = $1 AND revoked_at IS NULL`,
      [userId, reason]
    );
    return result.rowCount;
  }

  // Which of these logins are still going
  static async activeAmong(sessionIds) {
    const result = await db.query(
      `SELECT id FROM user_sessions WHERE id = ANY($1::int[]) AND revoked_at IS NULL`,
      [sessionIds]
    );
    return new Set(result.rows.map((row) => row.id));
  }
}

module.exports = Session;
