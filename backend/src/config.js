require('dotenv').config();

// Settings the server needs before it faces the public. In development every one of them
// has a working default; with NODE_ENV=production the server refuses to start until they
// are set, so a placeholder can never go live by accident.

const DEV_JWT_SECRET = 'your-secret-key';
const MIN_SECRET_LENGTH = 32;

const isProduction = process.env.NODE_ENV === 'production';

const config = {
  isProduction,
  jwtSecret: process.env.JWT_SECRET || DEV_JWT_SECRET,
  // Shown on the privacy policy, the terms and the account deletion page
  appName: process.env.APP_NAME || 'Namma Rummy',
  legalOwner: process.env.LEGAL_OWNER || '',
  supportEmail: process.env.SUPPORT_EMAIL || '',
  // How many proxies sit in front of the server (nginx, a hosting platform's router).
  // Needed to see each player's own address instead of the proxy's.
  trustProxy: parseInt(process.env.TRUST_PROXY, 10) || 0,
};

const problems = [];
if (config.jwtSecret === DEV_JWT_SECRET || config.jwtSecret.length < MIN_SECRET_LENGTH) {
  problems.push(`JWT_SECRET must be a random text of at least ${MIN_SECRET_LENGTH} characters`);
}
if (!config.legalOwner) {
  problems.push('LEGAL_OWNER must name the person or company that publishes the app');
}
if (!config.supportEmail) {
  problems.push('SUPPORT_EMAIL must be an address players can write to');
}

if (isProduction && problems.length > 0) {
  console.error('❌ The server is not ready for production. Set these in the environment (see .env.example):');
  for (const problem of problems) console.error(`   - ${problem}`);
  process.exit(1);
}

module.exports = config;
