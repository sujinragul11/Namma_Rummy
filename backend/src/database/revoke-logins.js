// Ends every login of one account, for example when it may have been taken over. Each phone
// logged in to it is logged out (an open game connection within a minute) and has to log in
// again with the password. Run it where the server's database settings are (.env, or the
// host's environment):
//
//   npm run revoke-logins -- <username, email, mobile number or user id>
const db = require('./db');
const User = require('../models/User');
const Session = require('../models/Session');
const { cleanPhone } = require('../validation');

// The same ways to name an account as the login form takes, and its id
const findAccount = async (who) => {
  const phone = cleanPhone(who);
  const user = (phone && (await User.findByIdentifier(phone))) || (await User.findByIdentifier(who));
  if (user) return user;
  return /^\d{1,9}$/.test(who) ? User.findById(Number(who)) : null;
};

const run = async () => {
  const who = (process.argv[2] || '').trim();
  if (!who) {
    console.error('Usage: npm run revoke-logins -- <username, email, mobile number or user id>');
    return 1;
  }

  await Session.ensureSchema();
  const user = await findAccount(who);
  if (!user) {
    console.error(`No account matches "${who}".`);
    return 1;
  }

  const count = await Session.revokeAll(user.id);
  console.log(`Ended ${count} login(s) of ${user.username} (user ${user.id}).`);
  return 0;
};

run()
  .then((code) => { process.exitCode = code; })
  .catch((error) => {
    console.error('❌ Failed to end the logins:', error.message);
    process.exitCode = 1;
  })
  .finally(() => db.pool.end());
