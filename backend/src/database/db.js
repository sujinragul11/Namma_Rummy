const { Pool } = require('pg');
require('dotenv').config();

// Hosting platforms hand out one DATABASE_URL; a local setup uses the separate DB_* values.
// A database reached over the internet (a host name with a domain in it) wants SSL; one on
// this machine or on the host's private network (Render's internal URL has no domain) does
// not. PGSSL=1 or PGSSL=0 overrides the guess.
const needsSsl = () => {
  if (process.env.PGSSL) return process.env.PGSSL === '1';
  try {
    const host = new URL(process.env.DATABASE_URL).hostname;
    return host.includes('.') && host !== 'localhost' && !/^[0-9.]+$/.test(host); // a plain IP address is local too
  } catch (error) {
    return false;
  }
};

const connection = process.env.DATABASE_URL
  ? { connectionString: process.env.DATABASE_URL, ssl: needsSsl() ? { rejectUnauthorized: false } : undefined }
  : {
      host: process.env.DB_HOST,
      port: process.env.DB_PORT,
      database: process.env.DB_NAME,
      user: process.env.DB_USER,
      password: process.env.DB_PASSWORD,
    };

const pool = new Pool({
  ...connection,
  max: 20,
  idleTimeoutMillis: 30000,
  connectionTimeoutMillis: 2000,
});

pool.on('connect', () => {
  console.log('✅ PostgreSQL connected');
});

pool.on('error', (err) => {
  console.error('❌ PostgreSQL error:', err);
});

module.exports = {
  query: (text, params) => pool.query(text, params),
  pool,
};
