// Uses temporary PostgreSQL tables and rolls everything back; no real accounts or games change.
const assert = require('node:assert/strict');
const db = require('../src/database/db');
const Coins = require('../src/models/Coins');

(async () => {
  const client = await db.pool.connect();
  const transaction = Coins.transaction;
  try {
    await client.query('BEGIN');
    await client.query(`
      CREATE TEMP TABLE users (id INTEGER PRIMARY KEY, coins INTEGER, updated_at TIMESTAMP) ON COMMIT DROP;
      CREATE TEMP TABLE games (id TEXT PRIMARY KEY, snapshot JSONB) ON COMMIT DROP;
      CREATE TEMP TABLE game_entries (id SERIAL, game_id TEXT, user_id INTEGER, amount INTEGER) ON COMMIT DROP;
      CREATE TEMP TABLE transactions (user_id INTEGER, type TEXT, amount INTEGER, game_id TEXT,
        balance_before INTEGER, balance_after INTEGER) ON COMMIT DROP;
      INSERT INTO users VALUES (1, 4000, NOW()), (2, 4000, NOW()), (3, 4000, NOW());
      INSERT INTO game_entries (game_id, user_id, amount) VALUES ('test', 1, 1000), ('test', 2, 1000), ('test', 3, 1000);
    `);
    Coins.transaction = async work => {
      await client.query('SAVEPOINT payment');
      try {
        const result = await work(client);
        await client.query('RELEASE SAVEPOINT payment');
        return result;
      } catch (error) {
        await client.query('ROLLBACK TO SAVEPOINT payment');
        throw error;
      }
    };
    const before = { status: 'round_over', round: 1, players: [['1', { eliminated: true, totalScore: 240 }]] };
    const after = { ...before, players: [['1', { eliminated: false, totalScore: 145, rejoinPaid: 500 }]] };
    await client.query('INSERT INTO games VALUES ($1, $2)', ['test', before]);
    assert.equal(await Coins.rejoin('test', '1', 500, after), 3500);
    assert.equal((await client.query('SELECT amount FROM game_entries WHERE user_id = 1')).rows[0].amount, 1500);
    assert.equal((await client.query('SELECT snapshot FROM games')).rows[0].snapshot.players[0][1].totalScore, 145);
    await assert.rejects(Coins.rejoin('test', '1', 500, after), /no longer available/);
    assert.equal((await client.query('SELECT COUNT(*)::int AS count FROM transactions')).rows[0].count, 1);

    await client.query('UPDATE games SET snapshot = $1', [before]);
    await client.query('UPDATE users SET coins = 100 WHERE id = 1');
    await assert.rejects(Coins.rejoin('test', '1', 500, after), /need 500 coins/);
    assert.equal((await client.query('SELECT amount FROM game_entries WHERE user_id = 1')).rows[0].amount, 1500);
    assert.equal((await client.query('SELECT snapshot FROM games')).rows[0].snapshot.players[0][1].eliminated, true);
    assert.equal((await client.query('SELECT coins FROM users WHERE id = 1')).rows[0].coins, 100);
    const payout = await Coins.payWinner('test', '2');
    assert.equal(payout.pot, 3500);
    assert.equal(payout.balance, 7500);
    assert.equal((await Coins.payWinner('test', '2')).pot, 0);
    console.log('PASS: PostgreSQL fee debit, increased pot, atomic snapshot, duplicate rejection, insufficient-funds rollback and single payout');
  } finally {
    Coins.transaction = transaction;
    await client.query('ROLLBACK');
    client.release();
    await db.pool.end();
  }
})().catch(error => { console.error(error.message); process.exitCode = 1; });
