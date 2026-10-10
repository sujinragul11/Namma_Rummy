const db = require('../database/db');
const bcrypt = require('bcrypt');

class User {
  // helper that hashes password, called by both register and update if needed
  static async _hashPassword(password) {
    return await bcrypt.hash(password, 10);
  }

  static async create({ username, email, phone, password }) {
    const passwordHash = await User._hashPassword(password);
    const result = await db.query(
      `INSERT INTO users (username, email, phone, password_hash)
       VALUES ($1, $2, $3, $4)
       RETURNING id, username, email, phone, coins, total_games, games_won`,
      [username, email || null, phone || null, passwordHash]
    );
    return result.rows[0];
  }

  static async findByEmail(email) {
    const result = await db.query(
      `SELECT * FROM users WHERE LOWER(email) = LOWER($1)`,
      [email]
    );
    return result.rows[0];
  }

  static async findByUsername(username) {
    const result = await db.query(
      `SELECT * FROM users WHERE LOWER(username) = LOWER($1)`,
      [username]
    );
    return result.rows[0];
  }

  static async findByPhone(phone) {
    const result = await db.query(
      `SELECT * FROM users WHERE phone = $1`,
      [phone]
    );
    return result.rows[0];
  }

  // Login accepts email, phone or username; capital letters don't matter for email and username.
  // An email or phone match wins over a username match.
  static async findByIdentifier(identifier) {
    const result = await db.query(
      `SELECT * FROM users
       WHERE LOWER(email) = LOWER($1) OR phone = $1 OR LOWER(username) = LOWER($1)
       ORDER BY
         (LOWER(email) IS NOT DISTINCT FROM LOWER($1) OR phone IS NOT DISTINCT FROM $1) DESC,
         (username = $1) DESC
       LIMIT 1`,
      [identifier]
    );
    return result.rows[0];
  }

  static async findById(id) {
    const result = await db.query(
      `SELECT 
        id,
        username,
        email,
        phone,
        coins,
        total_games,
        games_won,
        created_at,
        updated_at
       FROM users WHERE id = $1`,
      [id]
    );
    return result.rows[0];
  }

  // Only for checking the password again, e.g. before deleting the account
  static async findByIdWithPassword(id) {
    const result = await db.query(
      `SELECT id, password_hash FROM users WHERE id = $1`,
      [id]
    );
    return result.rows[0];
  }

  static async updateProfile(userId, { username, email }) {
    const result = await db.query(
      `UPDATE users
       SET username = $1, email = $2, updated_at = CURRENT_TIMESTAMP
       WHERE id = $3
       RETURNING id, username, email, phone, coins, created_at`,
      [username, email, userId]
    );
    return result.rows[0];
  }

  // Removes the account and everything that identifies its owner. Tables they played at stay,
  // without them: their results go with the account (player_games cascades).
  static async deleteAccount(userId) {
    const client = await db.pool.connect();
    try {
      await client.query('BEGIN');
      await client.query(`UPDATE games SET created_by = NULL WHERE created_by = $1`, [userId]);
      await client.query(`UPDATE game_moves SET user_id = NULL WHERE user_id = $1`, [userId]);
      await client.query(`DELETE FROM transactions WHERE user_id = $1`, [userId]);
      const result = await client.query(`DELETE FROM users WHERE id = $1`, [userId]);
      await client.query('COMMIT');
      return result.rowCount > 0;
    } catch (error) {
      await client.query('ROLLBACK');
      throw error;
    } finally {
      client.release();
    }
  }

  // convenience method to compute stats from player_games
  static async getStats(userId) {
    const result = await db.query(
      `SELECT 
          COUNT(*)::int AS total_games,
          COALESCE(SUM(CASE WHEN is_winner THEN 1 ELSE 0 END),0)::int AS games_won
       FROM player_games
       WHERE user_id = $1`,
      [userId]
    );
    return result.rows[0];
  }

  static async comparePassword(password, hash) {
    return await bcrypt.compare(password, hash);
  }
}


module.exports = User;
