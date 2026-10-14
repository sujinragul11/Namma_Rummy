const db = require('../database/db');
const { v4: uuidv4 } = require('uuid');

class Game {
  static async create({
    roomCode,
    gameType = 'points',
    maxPlayers = 2,
    createdBy,
    currentPlayers = 0,
    entryFee = 0,
    isPrivate = false
  }) {
    const gameId = uuidv4();
    const result = await db.query(
      `INSERT INTO games (id, room_code, game_type, max_players, created_by, current_players, is_private)
       VALUES ($1, $2, $3, $4, $5, $6, $7)
       RETURNING *`,
      [gameId, roomCode, gameType, maxPlayers, createdBy, currentPlayers, isPrivate]
    );
    return result.rows[0];
  }

  // Open lobbies that anyone can join; private tables (for friends, by room code) are left out
  static async findActive() {
    const result = await db.query(
      `SELECT id, room_code, game_type, max_players, current_players, status, created_at
       FROM games
       WHERE status = 'waiting' AND room_code IS NOT NULL AND NOT is_private
       ORDER BY created_at DESC
       LIMIT 50`
    );
    return result.rows;
  }

  // Databases created before private tables existed get the column here
  static async ensurePrivateColumn() {
    await db.query(`ALTER TABLE games ADD COLUMN IF NOT EXISTS is_private BOOLEAN NOT NULL DEFAULT FALSE`);
  }

  // Close games that were still open when the server last stopped, except the ones in
  // `keepIds`, which were brought back
  static async abandonUnfinished(keepIds = []) {
    const result = await db.query(
      `UPDATE games
       SET status = 'abandoned', ended_at = CURRENT_TIMESTAMP
       WHERE status IN ('waiting', 'playing') AND NOT (id = ANY($1::uuid[]))`,
      [keepIds]
    );
    return result.rowCount;
  }

  // A game in progress is kept whole in its row, so it survives a restart of the server.
  // Databases created before this existed get the column here.
  static async ensureSnapshotColumn() {
    await db.query(`ALTER TABLE games ADD COLUMN IF NOT EXISTS snapshot JSONB`);
  }

  static async saveSnapshot(gameId, snapshot) {
    await db.query(
      `UPDATE games SET snapshot = $2 WHERE id = $1`,
      [gameId, JSON.stringify(snapshot)]
    );
  }

  static async clearSnapshot(gameId) {
    await db.query(`UPDATE games SET snapshot = NULL WHERE id = $1`, [gameId]);
  }

  // The games that were being played, or waited for, when the server last stopped
  static async findResumable() {
    const result = await db.query(
      `SELECT id, snapshot FROM games
       WHERE status IN ('waiting', 'playing') AND snapshot IS NOT NULL`
    );
    return result.rows;
  }

  static async findById(gameId) {
    const result = await db.query(
      `SELECT * FROM games WHERE id = $1`,
      [gameId]
    );
    return result.rows[0];
  }

  static async findByRoomCode(roomCode) {
    const result = await db.query(
      `SELECT * FROM games WHERE room_code = $1`,
      [roomCode]
    );
    return result.rows[0];
  }

  static async updateGameState(gameId, updates) {
    const setClause = Object.keys(updates)
      .map((key, index) => `${key} = $${index + 2}`)
      .join(', ');

    const values = [gameId, ...Object.values(updates)];

    const result = await db.query(
      `UPDATE games SET ${setClause} WHERE id = $1 RETURNING *`,
      values
    );
    return result.rows[0];
  }

  static async addPlayer(gameId, userId, seatPosition, cards) {
    const result = await db.query(
      `INSERT INTO player_games (game_id, user_id, seat_position, cards)
       VALUES ($1, $2, $3, $4)
       RETURNING *`,
      [gameId, userId, seatPosition, JSON.stringify(cards)]
    );

    // Update player count
    await db.query(
      `UPDATE games SET current_players = current_players + 1 WHERE id = $1`,
      [gameId]
    );

    return result.rows[0];
  }

  static async getGameWithPlayers(gameId) {
    const gameResult = await db.query(
      `SELECT * FROM games WHERE id = $1`,
      [gameId]
    );

    const playersResult = await db.query(
      `SELECT pg.*, u.username, u.email
       FROM player_games pg
       JOIN users u ON pg.user_id = u.id
       WHERE pg.game_id = $1
       ORDER BY pg.seat_position`,
      [gameId]
    );

    return {
      ...gameResult.rows[0],
      players: playersResult.rows
    };
  }

  static async recordMove(gameId, userId, moveType, card, position = null) {
    await db.query(
      `INSERT INTO game_moves (game_id, user_id, move_type, card, position)
       VALUES ($1, $2, $3, $4, $5)`,
      [gameId, userId, moveType, card, position]
    );
  }

  static async updatePlayerCards(playerGameId, cards, melds = null) {
    const updates = { cards: JSON.stringify(cards) };
    if (melds !== null) {
      updates.melds = JSON.stringify(melds);
    }

    const setClause = Object.keys(updates)
      .map((key, index) => `${key} = $${index + 1}`)
      .join(', ');

    const values = [...Object.values(updates), playerGameId];

    await db.query(
      `UPDATE player_games SET ${setClause} WHERE id = $${values.length}`,
      values
    );
  }
}

module.exports = Game;
