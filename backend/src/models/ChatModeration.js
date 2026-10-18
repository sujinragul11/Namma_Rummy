const db = require('../database/db');

// Keeping the chat at the table civil. A player can block another: nothing the blocked player
// writes or sends at a table reaches them any more, at any table, until they unblock. A player
// can report a message: it is kept here with who sent it, for the game's team to review
// (npm run chat-reports), and its sender is blocked for the one who reported it.
// Messages that nobody reports are never written down. Blocks and reports go with either
// account (ON DELETE CASCADE).
class ChatModeration {
  // The server does this at every start, so an existing database gets the tables without a
  // migration
  static async ensureSchema() {
    await db.query(`
      CREATE TABLE IF NOT EXISTS chat_blocks (
        user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
        blocked_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
        created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
        PRIMARY KEY (user_id, blocked_id),
        CHECK (user_id <> blocked_id)
      )
    `);
    await db.query(`
      CREATE TABLE IF NOT EXISTS chat_reports (
        id SERIAL PRIMARY KEY,
        reporter_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
        reported_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
        game_id TEXT,
        message TEXT NOT NULL,
        reviewed_at TIMESTAMP,
        created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
      )
    `);
    await db.query('CREATE INDEX IF NOT EXISTS idx_chat_reports_open ON chat_reports(reviewed_at, created_at)');
  }

  // The players this one has blocked, as { id, username }, the earliest first
  static async blockedBy(userId) {
    const result = await db.query(
      `SELECT u.id, u.username FROM chat_blocks b JOIN users u ON u.id = b.blocked_id
       WHERE b.user_id = $1 ORDER BY b.created_at, u.id`,
      [userId]
    );
    return result.rows.map((row) => ({ id: String(row.id), username: row.username }));
  }

  static async block(userId, otherId) {
    try {
      await db.query(
        'INSERT INTO chat_blocks (user_id, blocked_id) VALUES ($1, $2) ON CONFLICT DO NOTHING',
        [userId, otherId]
      );
    } catch (error) {
      if (error.code === '23503') throw new Error('Unknown player'); // no such account
      throw error;
    }
  }

  static async unblock(userId, otherId) {
    await db.query('DELETE FROM chat_blocks WHERE user_id = $1 AND blocked_id = $2', [userId, otherId]);
  }

  // Keeps a reported message for review; returns the report's number
  static async report(reporterId, reportedId, gameId, message) {
    const result = await db.query(
      `INSERT INTO chat_reports (reporter_id, reported_id, game_id, message)
       VALUES ($1, $2, $3, $4) RETURNING id`,
      [reporterId, reportedId, gameId, message]
    );
    return result.rows[0].id;
  }

  // How many reports this player has made in the last hour
  static async recentReports(reporterId) {
    const result = await db.query(
      `SELECT COUNT(*)::int AS count FROM chat_reports
       WHERE reporter_id = $1 AND created_at > CURRENT_TIMESTAMP - INTERVAL '1 hour'`,
      [reporterId]
    );
    return result.rows[0].count;
  }

  // Reports still to be looked at (or all of them), the oldest first, with both players' names
  // and how often the reported player has been reported in all
  static async reports({ all = false } = {}) {
    const result = await db.query(
      `SELECT r.id, r.created_at, r.reviewed_at, r.message, r.game_id,
              r.reported_id, reported.username AS reported_name,
              r.reporter_id, reporter.username AS reporter_name,
              (SELECT COUNT(*)::int FROM chat_reports o WHERE o.reported_id = r.reported_id) AS times_reported
       FROM chat_reports r
       JOIN users reported ON reported.id = r.reported_id
       JOIN users reporter ON reporter.id = r.reporter_id
       ${all ? '' : 'WHERE r.reviewed_at IS NULL'}
       ORDER BY r.created_at, r.id`
    );
    return result.rows;
  }

  static async markReviewed(reportId) {
    const result = await db.query(
      'UPDATE chat_reports SET reviewed_at = CURRENT_TIMESTAMP WHERE id = $1 AND reviewed_at IS NULL',
      [reportId]
    );
    return result.rowCount > 0;
  }
}

module.exports = ChatModeration;
