const db = require('./db');
const Coins = require('../models/Coins');

const createTables = async () => {
  try {
    // Users table
    await db.query(`
      CREATE TABLE IF NOT EXISTS users (
        id SERIAL PRIMARY KEY,
        username VARCHAR(50) UNIQUE NOT NULL,
        email VARCHAR(100) UNIQUE,
        phone VARCHAR(20) UNIQUE,
        password_hash VARCHAR(255) NOT NULL,
        wallet DECIMAL(10,2) DEFAULT 1000.00,
        total_games INTEGER DEFAULT 0,
        games_won INTEGER DEFAULT 0,
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
      );
    `);
    // make sure old installations get the phone column
    await db.query(`
      ALTER TABLE users ADD COLUMN IF NOT EXISTS phone VARCHAR(20) UNIQUE;
    `);
    // and let them register with a phone number alone: the email used to be required
    await db.query(`
      ALTER TABLE users ALTER COLUMN email DROP NOT NULL;
    `);

    // Games table
    await db.query(`
      CREATE TABLE IF NOT EXISTS games (
        id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
        room_code VARCHAR(10) UNIQUE,
        game_type VARCHAR(20) DEFAULT 'points',
        max_players INTEGER DEFAULT 2,
        current_players INTEGER DEFAULT 0,
        status VARCHAR(20) DEFAULT 'waiting',
        joker VARCHAR(10),
        turn_index INTEGER DEFAULT 0,
        deck JSONB,
        discard_pile JSONB,
        created_by INTEGER REFERENCES users(id),
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        started_at TIMESTAMP,
        ended_at TIMESTAMP
      );
    `);
    // a game in progress is kept whole here, so it survives a restart of the server
    await db.query(`
      ALTER TABLE games ADD COLUMN IF NOT EXISTS snapshot JSONB;
    `);

    // Player games table (junction)
    await db.query(`
      CREATE TABLE IF NOT EXISTS player_games (
        id SERIAL PRIMARY KEY,
        game_id UUID REFERENCES games(id) ON DELETE CASCADE,
        user_id INTEGER REFERENCES users(id) ON DELETE CASCADE,
        seat_position INTEGER,
        cards JSONB,
        melds JSONB DEFAULT '[]',
        score INTEGER DEFAULT 0,
        is_winner BOOLEAN DEFAULT FALSE,
        joined_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
      );
    `);

    // Game moves history
    await db.query(`
      CREATE TABLE IF NOT EXISTS game_moves (
        id SERIAL PRIMARY KEY,
        game_id UUID REFERENCES games(id) ON DELETE CASCADE,
        user_id INTEGER REFERENCES users(id),
        move_type VARCHAR(20),
        card VARCHAR(10),
        position INTEGER,
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
      );
    `);

    // Transactions table
    await db.query(`
      CREATE TABLE IF NOT EXISTS transactions (
        id SERIAL PRIMARY KEY,
        user_id INTEGER REFERENCES users(id),
        type VARCHAR(20),
        amount DECIMAL(10,2),
        game_id UUID REFERENCES games(id),
        balance_before DECIMAL(10,2),
        balance_after DECIMAL(10,2),
        status VARCHAR(20) DEFAULT 'completed',
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
      );
    `);

    // Friends: one row per pair of players (see models/Friend.js). They go with either account
    await db.query(`
      CREATE TABLE IF NOT EXISTS friendships (
        id SERIAL PRIMARY KEY,
        requester_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
        addressee_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
        status VARCHAR(10) NOT NULL DEFAULT 'pending',
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        CHECK (requester_id <> addressee_id)
      );
    `);

    // Play coins: the balance of each account and who has paid to sit at which table.
    // The server does the same at every start, so there is one place that says how
    await Coins.ensureSchema();

    console.log('✅ All tables created successfully!');

    // Create indexes
    await db.query(`
      CREATE INDEX IF NOT EXISTS idx_games_status ON games(status);
      CREATE INDEX IF NOT EXISTS idx_player_games_game_id ON player_games(game_id);
      CREATE INDEX IF NOT EXISTS idx_player_games_user_id ON player_games(user_id);
      CREATE INDEX IF NOT EXISTS idx_game_moves_game_id ON game_moves(game_id);
      CREATE UNIQUE INDEX IF NOT EXISTS idx_friendships_pair
        ON friendships (LEAST(requester_id, addressee_id), GREATEST(requester_id, addressee_id));
      CREATE INDEX IF NOT EXISTS idx_friendships_requester ON friendships(requester_id);
      CREATE INDEX IF NOT EXISTS idx_friendships_addressee ON friendships(addressee_id);
    `);

    console.log('✅ Indexes created successfully!');

  } catch (error) {
    console.error('❌ Migration error:', error);
    process.exit(1);
  } finally {
    process.exit();
  }
};

createTables();
