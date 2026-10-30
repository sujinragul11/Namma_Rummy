const assert = require('node:assert/strict');
const db = require('../src/database/db');
const User = require('../src/models/User');
const SocketManager = require('../src/socket/SocketManager');

(async () => {
  const client = await db.pool.connect();
  const query = db.query;
  try {
    await client.query('BEGIN');
    await client.query(`
      CREATE TEMP TABLE users (id INTEGER, username TEXT, coins INTEGER, phone TEXT, email TEXT, password_hash TEXT) ON COMMIT DROP;
      CREATE TEMP TABLE avatars (user_id INTEGER, image BYTEA, version INTEGER) ON COMMIT DROP;
      CREATE TEMP TABLE player_games (user_id INTEGER, is_winner BOOLEAN) ON COMMIT DROP;
      CREATE TEMP TABLE friendships (requester_id INTEGER, addressee_id INTEGER, status TEXT) ON COMMIT DROP;
      INSERT INTO users VALUES (1, 'Opponent', 500, 'private', 'private', 'private');
      INSERT INTO avatars VALUES (1, 'photo', 3);
      INSERT INTO player_games VALUES (1, TRUE), (1, FALSE);
      INSERT INTO friendships VALUES (1, 2, 'accepted'), (3, 1, 'pending'), (4, 1, 'blocked');
    `);
    db.query = (...args) => client.query(...args);
    const profile = await User.publicProfile(1);
    assert.deepEqual(profile, { id: 1, username: 'Opponent', coins: 500, avatar: 3,
      totalGames: 2, gamesWon: 1, friends: 1, winPercentage: 50 });
    await client.query('DELETE FROM player_games');
    assert.equal((await User.publicProfile(1)).winPercentage, 0);
    assert.equal(await User.publicProfile(999), null);
    const manager = Object.create(SocketManager.prototype);
    manager.games = new Map([['game', { players: new Map([['1', {}], ['2', {}]]) }]]);
    manager.userGames = new Map([['2', 'game']]);
    assert.equal((await manager.playerProfile('2', '1')).profile.username, 'Opponent');
    await assert.rejects(manager.playerProfile('2', '999'), /not at your table/);
    await assert.rejects(manager.playerProfile('3', '1'));
    console.log('PASS: public fields only, real stats, zero games, friend count, missing account and table access checks');
  } finally {
    db.query = query;
    await client.query('ROLLBACK');
    client.release();
    await db.pool.end();
  }
})().catch(error => { console.error(error); process.exitCode = 1; });
