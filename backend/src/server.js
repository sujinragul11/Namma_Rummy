const config = require('./config');
const express = require('express');
const http = require('http');
const socketIo = require('socket.io');
const cors = require('cors');
const helmet = require('helmet');
const rateLimit = require('express-rate-limit');

const db = require('./database/db');
const pages = require('./pages');
const User = require('./models/User');
const Game = require('./models/Game');
const Avatar = require('./models/Avatar');
const DailyBonus = require('./models/DailyBonus');
const AdReward = require('./models/AdReward');
const Session = require('./models/Session');
const SocketManager = require('./socket/SocketManager');
const PhoneVerification = require('./sms/PhoneVerification');
const {
  cleanPhone, displayPhone, looksMadeUp, cleanCode, MESSAGES, MAX_USERNAME_LENGTH, MIN_PASSWORD_LENGTH,
} = require('./validation');

const app = express();
const server = http.createServer(app);
const io = socketIo(server, {
  // Same permissive policy as the HTTP API below; sockets are authenticated by the login token
  cors: {
    origin: (origin, cb) => cb(null, true),
    methods: ["GET", "POST"]
  }
});

// Middleware
app.set('trust proxy', config.trustProxy);
app.use(helmet());

// Allow mobile devices/emulators to call backend.
// Use a permissive mode by default; you can tighten using CLIENT_URL later.
app.use(
  cors({
    origin: (origin, cb) => cb(null, true),
    credentials: true,
    methods: ['GET', 'POST', 'PUT', 'PATCH', 'DELETE', 'OPTIONS'],
    allowedHeaders: ['Content-Type', 'Authorization'],
  })
);

app.use(express.json());
app.use(express.urlencoded({ extended: false })); // the account deletion web form

// Basic request logging (helps diagnose “Network request failed” from the client)
app.use((req, res, next) => {
  if (['/api/auth/register', '/api/auth/login', '/health'].includes(req.path)) {
    console.log(`[HTTP] ${req.method} ${req.path}`);
  }
  next();
});

// Password guessing protection for everything that checks a password.
// Generous, because many phones can share one address on a mobile network.
const passwordLimiter = rateLimit({
  windowMs: 5 * 60 * 1000,
  limit: 40,
  standardHeaders: true,
  legacyHeaders: false,
  message: { error: 'Too many attempts. Please wait a few minutes and try again.' },
});


// Auth middleware: the token the app was given at login (see models/Session.js).
// A login that has ended is answered 401 with code "session_ended", and only that makes the
// app log out. Any other failure says nothing about the login, so the app keeps it.
const authenticateToken = async (req, res, next) => {
  const authHeader = req.headers['authorization'];
  const token = authHeader && authHeader.split(' ')[1];

  if (!token) return res.status(401).json({ error: 'Access token required' });

  let login;
  try {
    login = await Session.verify(token);
  } catch (error) {
    if (error.sessionEnded) return res.status(401).json({ error: error.message, code: 'session_ended' });
    console.error('Login check error:', error.message);
    return res.status(503).json({ error: 'The game server is busy. Please try again in a moment.' });
  }
  req.user = { id: login.userId };
  req.sessionId = login.sessionId; // null for a token from before logins were kept
  next();
};

// Text typed on a phone keyboard often arrives with stray spaces, or not at all
const cleanText = (value) => (typeof value === 'string' ? value.trim() : '');

// The account behind what was typed at login: an email, a phone number or a username.
// A phone number is looked up the way it is stored, however it was typed ("+91 98765 43210").
const findAccount = async (identifier) => {
  const phone = cleanPhone(identifier);
  return (phone && (await User.findByIdentifier(phone))) || User.findByIdentifier(identifier);
};

// Sending SMS codes costs money and can be used to pester a stranger's phone: a few per address.
// Each number also waits between two codes (src/sms/PhoneVerification.js).
const codeLimiter = rateLimit({
  windowMs: 10 * 60 * 1000,
  limit: 20,
  standardHeaders: true,
  legacyHeaders: false,
  message: { error: 'Too many codes were asked for. Please wait a few minutes and try again.' },
});

const passwordProblem = (password) =>
  typeof password !== 'string' || password.length < MIN_PASSWORD_LENGTH ? MESSAGES.password : '';

// Checks a sign-up form. Returns { error } for the first thing wrong with it, or the account
// to make: { username, phone, password }. Nothing is sent by SMS before all of it is right.
const checkSignUp = async (body) => {
  const username = cleanText(body.username);
  const phone = cleanPhone(body.phone);
  if (!username || username.length > MAX_USERNAME_LENGTH) return { error: MESSAGES.username };
  if (!phone) return { error: MESSAGES.phone };
  if (looksMadeUp(phone)) return { error: MESSAGES.madeUpPhone };
  const passwordError = passwordProblem(body.password);
  if (passwordError) return { error: passwordError };
  if (await User.findByUsername(username)) return { error: 'That username is taken. Choose another one.' };
  if (await User.findByPhone(phone)) {
    return { error: 'An account with this mobile number already exists. Log in, or use "Forgot password?".' };
  }
  return { username, phone, password: body.password };
};

// What the app shows once a code is on its way.
const codeSentReply = (phone, sent) => ({ codeSent: true, phone: displayPhone(phone), resendSeconds: sent.resendSeconds });

// The login a register or password reset ends with, as /api/auth/login answers it.
const loginReply = async (user) => {
  const token = await Session.create(user.id); // lasts until the player logs out
  delete user.password_hash;
  delete user.wallet; // a column left from an earlier idea; nothing uses it
  user.avatar = await Avatar.versionOf(user.id);
  return { user, token };
};

// Auth routes. Signing up takes two steps while SMS codes are on: the form is checked and a
// code is sent (/register/start), then the account is made with that code (/register).
// With codes off, /register/start answers { codeSent: false } and /register needs no code.
app.post('/api/auth/register/start', codeLimiter, async (req, res) => {
  try {
    const account = await checkSignUp(req.body);
    if (account.error) return res.status(400).json({ error: account.error });
    if (!PhoneVerification.enabled()) return res.json({ codeSent: false });

    const sent = await PhoneVerification.send(account.phone);
    if (!sent.ok) return res.status(sent.status).json({ error: sent.error, waitSeconds: sent.waitSeconds });
    res.json(codeSentReply(account.phone, sent));
  } catch (error) {
    console.error('Registration start error:', error);
    res.status(500).json({ error: 'Internal server error' });
  }
});

app.post('/api/auth/register', passwordLimiter, async (req, res) => {
  try {
    const account = await checkSignUp(req.body);
    if (account.error) return res.status(400).json({ error: account.error });

    if (PhoneVerification.enabled()) {
      // An app from before codes sends no code at all; it cannot show the step that asks for it
      if (req.body.code === undefined) {
        return res.status(400).json({ error: 'Please update Namma Rummy to the newest version to create an account.' });
      }
      const code = cleanCode(req.body.code);
      if (!code) return res.status(400).json({ error: MESSAGES.code });
      const checked = await PhoneVerification.check(account.phone, code);
      if (!checked.ok) return res.status(checked.status).json({ error: checked.error });
    }

    const user = await User.create(account);
    const token = await Session.create(user.id); // lasts until the player logs out
    res.status(201).json({ user: { ...user, avatar: 0 }, token });
  } catch (error) {
    // 23505: the same name or number was registered a moment ago
    if (error.code === '23505') {
      return res.status(400).json({ error: 'That username or mobile number was registered a moment ago. Try another one.' });
    }
    console.error('Registration error:', error);
    res.status(500).json({ error: 'Internal server error' });
  }
});

// A forgotten password: a code goes to the account's mobile number (/password/start), and with
// it the password is replaced (/password/reset). Every other login of the account then ends,
// and the player is logged in here.
app.post('/api/auth/password/start', codeLimiter, async (req, res) => {
  try {
    const phone = cleanPhone(req.body.phone);
    if (!phone) return res.status(400).json({ error: MESSAGES.phone });
    if (!PhoneVerification.enabled()) {
      const contact = config.supportEmail || 'the support address in the app store listing';
      return res.status(503).json({ error: `Resetting a password by SMS is not available yet. For help, write to ${contact} with your username and mobile number.` });
    }
    if (!(await User.findByPhone(phone))) {
      return res.status(404).json({ error: 'No account has this mobile number. Check it, or register a new account.' });
    }
    const sent = await PhoneVerification.send(phone);
    if (!sent.ok) return res.status(sent.status).json({ error: sent.error, waitSeconds: sent.waitSeconds });
    res.json(codeSentReply(phone, sent));
  } catch (error) {
    console.error('Password reset start error:', error);
    res.status(500).json({ error: 'Internal server error' });
  }
});

app.post('/api/auth/password/reset', passwordLimiter, async (req, res) => {
  try {
    const phone = cleanPhone(req.body.phone);
    const code = cleanCode(req.body.code);
    if (!phone) return res.status(400).json({ error: MESSAGES.phone });
    if (!code) return res.status(400).json({ error: MESSAGES.code });
    const passwordError = passwordProblem(req.body.password);
    if (passwordError) return res.status(400).json({ error: passwordError });
    if (!PhoneVerification.enabled()) {
      return res.status(503).json({ error: 'Resetting a password by SMS is not available yet.' });
    }
    const user = await User.findByPhone(phone);
    if (!user) return res.status(404).json({ error: 'No account has this mobile number.' });

    const checked = await PhoneVerification.check(phone, code);
    if (!checked.ok) return res.status(checked.status).json({ error: checked.error });

    await User.setPassword(user.id, req.body.password);
    // Whoever knew the old password is logged out everywhere, at once
    await Session.revokeAll(user.id, 'password_reset');
    const sockets = await io.in(socketManager.userRoom(String(user.id))).fetchSockets();
    closeEndedLogins(sockets, () => false);
    console.log(`🔑 Password of account ${user.id} reset by SMS code`);
    res.json(await loginReply(user));
  } catch (error) {
    console.error('Password reset error:', error);
    res.status(500).json({ error: 'Internal server error' });
  }
});

app.post('/api/auth/login', passwordLimiter, async (req, res) => {
  try {
    const { password } = req.body;
    const identifier = cleanText(req.body.identifier); // email, phone or username

    if (!identifier || !password) {
      return res.status(400).json({ error: 'Identifier and password required' });
    }

    const user = await findAccount(identifier);
    if (!user) {
      return res.status(401).json({ error: 'Invalid credentials' });
    }

    const isValidPassword = await User.comparePassword(password, user.password_hash);
    if (!isValidPassword) {
      return res.status(401).json({ error: 'Invalid credentials' });
    }

    res.json(await loginReply(user)); // with the profile photo's version, 0 for none
  } catch (error) {
    console.error('Login error:', error);
    res.status(500).json({ error: 'Internal server error' });
  }
});

// Game routes
app.get('/api/games/active', authenticateToken, async (req, res) => {
  try {
    const games = await Game.findActive();
    res.json({ games });
  } catch (error) {
    console.error('Get active games error:', error);
    res.status(500).json({ error: 'Internal server error' });
  }
});

app.post('/api/games/create', authenticateToken, async (req, res) => {
  try {
    const { gameType = 'points', maxPlayers = 2 } = req.body;
    const game = await Game.create({
      gameType,
      maxPlayers,
      createdBy: req.user.id
    });
    res.status(201).json({ game });
  } catch (error) {
    console.error('Create game error:', error);
    res.status(500).json({ error: 'Internal server error' });
  }
});

app.get('/api/games/:id', authenticateToken, async (req, res) => {
  try {
    const game = await Game.findById(req.params.id);
    if (!game) {
      return res.status(404).json({ error: 'Game not found' });
    }
    res.json({ game });
  } catch (error) {
    console.error('Get game error:', error);
    res.status(500).json({ error: 'Internal server error' });
  }
});

// User profile route (includes stats)
app.get('/api/user/profile', authenticateToken, async (req, res) => {
  try {
    const user = await User.findById(req.user.id);
    if (!user) {
      return res.status(404).json({ error: 'User not found' });
    }
    const stats = await User.getStats(req.user.id);
    const total = stats.total_games || 0;
    const won = stats.games_won || 0;
    const winPct = total > 0 ? Math.round((won / total) * 1000) / 10 : 0; // one decimal

    res.json({
      user: {
        id: user.id,
        username: user.username,
        email: user.email,
        phone: user.phone,
        coins: user.coins,
        totalGames: total,
        gamesWon: won,
        winPercentage: winPct,
        avatar: user.avatar,
        created_at: user.created_at,
      }
    });
  } catch (error) {
    console.error('Get profile error:', error);
    res.status(500).json({ error: 'Internal server error' });
  }
});

// Update the username. The mobile number stays: it was proven by SMS when the account was made.
// (An email address sent by an older app is ignored; accounts no longer have one.)
app.patch('/api/user/profile', authenticateToken, async (req, res) => {
  try {
    const username = cleanText(req.body.username);

    if (!username || username.length > 50) {
      return res.status(400).json({ error: 'Username must be 1 to 50 characters' });
    }

    const current = await User.findById(req.user.id);
    if (!current) {
      return res.status(404).json({ error: 'User not found' });
    }
    const taken = await User.findByUsername(username);
    if (taken && taken.id !== current.id) {
      return res.status(400).json({ error: 'That username is taken. Choose another one.' });
    }

    const user = await User.updateProfile(req.user.id, { username });
    res.json({ user });
  } catch (error) {
    // 23505 = unique violation on the username
    if (error.code === '23505') {
      return res.status(400).json({ error: 'That username is taken. Choose another one.' });
    }
    console.error('Update profile error:', error);
    res.status(500).json({ error: 'Internal server error' });
  }
});

// Initialize Socket.IO
const socketManager = new SocketManager(io);

// Closes the game connections opened with logins that have ended. The app then tries to
// connect again, is told its login has ended, and shows the login screen.
const closeEndedLogins = (sockets, isActive) => {
  for (const socket of sockets) {
    if (socket.data.sessionId && !isActive(socket.data.sessionId)) socket.disconnect(true);
  }
};

// Logging out ends the login on the server too, so its token cannot be used again
app.post('/api/auth/logout', authenticateToken, async (req, res) => {
  try {
    if (req.sessionId) {
      await Session.end(req.sessionId);
      const sockets = await io.in(socketManager.userRoom(String(req.user.id))).fetchSockets();
      closeEndedLogins(sockets, (sessionId) => sessionId !== req.sessionId);
    }
    res.json({ loggedOut: true });
  } catch (error) {
    console.error('Logout error:', error);
    res.status(500).json({ error: 'Internal server error' });
  }
});

// A login can also be ended from outside this server (src/database/revoke-logins.js).
// Every so often the connections still open are checked, so it reaches them within a minute.
const LOGIN_CHECK_MS = (Number(process.env.LOGIN_CHECK_SECONDS) || 60) * 1000;
setInterval(async () => {
  try {
    const sockets = await io.fetchSockets();
    const sessionIds = [...new Set(sockets.map((socket) => socket.data.sessionId).filter(Boolean))];
    if (sessionIds.length === 0) return;
    const active = await Session.activeAmong(sessionIds);
    closeEndedLogins(sockets, (sessionId) => active.has(sessionId));
  } catch (error) {
    console.warn('⚠️  Failed to check open logins:', error.message);
  }
}, LOGIN_CHECK_MS).unref();

// Account deletion. Both app stores require it wherever an account can be created:
// inside the app (the route below) and on a web page (further down).
const deleteAccount = async (user) => {
  const contacts = await socketManager.friends.contactsOf(user.id);
  await socketManager.removeUser(String(user.id));
  await User.deleteAccount(user.id);
  socketManager.friends.pushAll(contacts); // their friends lists no longer hold this player
  console.log(`🗑️  Account ${user.id} deleted`);
};

app.post('/api/user/delete', passwordLimiter, authenticateToken, async (req, res) => {
  try {
    const user = await User.findByIdWithPassword(req.user.id);
    if (!user) {
      return res.status(404).json({ error: 'User not found' });
    }
    if (typeof req.body.password !== 'string' || !(await User.comparePassword(req.body.password, user.password_hash))) {
      return res.status(401).json({ error: 'That password is not correct' });
    }

    await deleteAccount(user);
    res.json({ deleted: true });
  } catch (error) {
    console.error('Delete account error:', error);
    res.status(500).json({ error: 'Internal server error' });
  }
});

// Profile photos. The app sends the photo itself as the request body: a small square JPEG it
// made from the picture the player chose. Everyone who sees the player at a table or in a
// friends list sees it; it goes away with the account.
const avatarLimiter = rateLimit({
  windowMs: 10 * 60 * 1000,
  limit: 30,
  standardHeaders: true,
  legacyHeaders: false,
  message: { error: 'Too many photo changes. Please wait a few minutes and try again.' },
});
const readPhoto = express.raw({ type: ['image/jpeg', 'image/png'], limit: Avatar.MAX_BYTES });
const photoBody = (req, res, next) => readPhoto(req, res, (error) => {
  if (!error) return next();
  const tooLarge = error.type === 'entity.too.large';
  res.status(tooLarge ? 413 : 400).json({ error: tooLarge ? 'That picture is too large' : 'The picture could not be read' });
});

app.put('/api/user/avatar', avatarLimiter, authenticateToken, photoBody, async (req, res) => {
  try {
    const version = await Avatar.save(req.user.id, req.body);
    socketManager.avatarChanged(String(req.user.id), version);
    res.json({ avatar: version });
  } catch (error) {
    if (error.forPlayer) return res.status(400).json({ error: error.message });
    console.error('Save photo error:', error);
    res.status(500).json({ error: 'Internal server error' });
  }
});

app.delete('/api/user/avatar', avatarLimiter, authenticateToken, async (req, res) => {
  try {
    await Avatar.remove(req.user.id);
    socketManager.avatarChanged(String(req.user.id), 0);
    res.json({ avatar: 0 });
  } catch (error) {
    console.error('Remove photo error:', error);
    res.status(500).json({ error: 'Internal server error' });
  }
});

// A player's photo. The app asks with the version it was told about (?v=), so a changed photo
// is a new address and the old one may be kept as long as the phone likes.
app.get('/api/avatars/:userId', authenticateToken, async (req, res) => {
  try {
    const userId = Number(req.params.userId);
    const photo = Number.isInteger(userId) ? await Avatar.load(userId) : undefined;
    if (!photo) return res.status(404).json({ error: 'No photo' });
    res.set('Cache-Control', 'private, max-age=604800');
    res.type(photo.mime).send(photo.image);
  } catch (error) {
    console.error('Get photo error:', error);
    res.status(500).json({ error: 'Internal server error' });
  }
});

// The daily bonus wheel: one spin every 24 hours. The server keeps when each player last spun
// and draws the slot the wheel stops on; the app only shows it. See models/DailyBonus.js.
app.get('/api/bonus/daily', authenticateToken, async (req, res) => {
  try {
    res.json(await DailyBonus.status(req.user.id));
  } catch (error) {
    console.error('Daily bonus status error:', error);
    res.status(500).json({ error: 'Internal server error' });
  }
});

app.post('/api/bonus/daily/spin', authenticateToken, async (req, res) => {
  const userId = String(req.user.id);
  try {
    const result = await DailyBonus.spin(req.user.id);
    // The new balance, and the wheel closing for a day, reach every phone the player is on
    socketManager.sendCoins(userId, result.coins);
    socketManager.bonusChanged(userId, { available: false, nextSpinIn: result.nextSpinIn });
    console.log(`🎡 Daily bonus: user ${userId} won ${result.prize} coins`);
    res.json(result);
  } catch (error) {
    if (error.tooEarly) {
      res.set('Retry-After', String(Math.ceil(error.nextSpinIn / 1000)));
      return res.status(429).json({ error: error.message, available: false, nextSpinIn: error.nextSpinIn });
    }
    if (error.notFound) return res.status(404).json({ error: 'User not found' });
    console.error('Daily bonus spin error:', error);
    res.status(500).json({ error: 'Internal server error' });
  }
});

// Free coins for watching ads: a few videos fill a reward the player then collects, a few
// times a day. The app reports each video watched; the server counts, pays and keeps the
// daily limit. See models/AdReward.js.
const adRewardRefused = (res, error) => {
  if (error.notFound) return res.status(404).json({ error: 'User not found' });
  res.status(error.limitReached ? 429 : 409).json({ error: error.message, ...error.status });
};

app.get('/api/rewards/ads', authenticateToken, async (req, res) => {
  try {
    res.json(await AdReward.status(req.user.id));
  } catch (error) {
    console.error('Ad reward status error:', error);
    res.status(500).json({ error: 'Internal server error' });
  }
});

app.post('/api/rewards/ads/watched', authenticateToken, async (req, res) => {
  const userId = String(req.user.id);
  try {
    const status = await AdReward.watched(req.user.id);
    socketManager.adRewardChanged(userId, status); // the player's other phones count along
    res.json(status);
  } catch (error) {
    if (error.forPlayer) return adRewardRefused(res, error);
    console.error('Ad watched error:', error);
    res.status(500).json({ error: 'Internal server error' });
  }
});

app.post('/api/rewards/ads/collect', authenticateToken, async (req, res) => {
  const userId = String(req.user.id);
  try {
    const result = await AdReward.collect(req.user.id);
    socketManager.sendCoins(userId, result.coins);
    const { prize, coins, ...status } = result;
    socketManager.adRewardChanged(userId, status);
    console.log(`📺 Ad reward: user ${userId} collected ${prize} coins`);
    res.json(result);
  } catch (error) {
    if (error.forPlayer) return adRewardRefused(res, error);
    console.error('Ad reward collect error:', error);
    res.status(500).json({ error: 'Internal server error' });
  }
});

// Ad networks allowed to sell the app's ad space (IAB app-ads.txt). AdMob reads it from
// the root of the developer website named on Google Play and the App Store.
const APP_ADS_TXT = 'google.com, pub-1137151357132919, DIRECT, f08c47fec0942fa0\n';

// Web pages: what the store listings link to
app.get('/app-ads.txt', (req, res) => res.type('text/plain').send(APP_ADS_TXT));
app.get('/', (req, res) => res.send(pages.home()));
app.get('/privacy', (req, res) => res.send(pages.privacy()));
app.get('/terms', (req, res) => res.send(pages.terms()));
app.get('/delete-account', (req, res) => res.send(pages.deleteAccount()));

app.post('/delete-account', passwordLimiter, async (req, res) => {
  try {
    const identifier = cleanText(req.body.identifier);
    const { password } = req.body;
    const user = identifier && typeof password === 'string' ? await findAccount(identifier) : null;

    if (!user || !(await User.comparePassword(password, user.password_hash))) {
      return res.status(401).send(pages.deleteAccount({ error: 'Those details do not match an account.' }));
    }

    await deleteAccount(user);
    res.send(pages.deleteAccount({ done: true }));
  } catch (error) {
    console.error('Delete account error:', error);
    res.status(500).send(pages.deleteAccount({ error: 'Something went wrong. Please try again.' }));
  }
});

// Health check
app.get('/health', (req, res) => {
  res.json({ status: 'OK', timestamp: new Date().toISOString() });
});

const PORT = process.env.PORT || 3001;

server.on('error', (error) => {
  if (error.code === 'EADDRINUSE') {
    console.error(`❌ Port ${PORT} is already in use: the backend is already running in another window.`);
    console.error('   The app can use that one, so there is no need to start it again.');
    console.error('   To restart it, press Ctrl+C in that window (or close it) first, then run npm start.');
    process.exit(1);
  }
  throw error;
});

server.listen(PORT, '0.0.0.0', () => {
  console.log(`🚀 Server running on port ${PORT} (0.0.0.0)`);
  console.log(`📡 Socket.IO ready`);
  console.log(PhoneVerification.describe());
  if (!config.isProduction) printPhoneAddresses();
});

// On a development PC: what a phone on the same Wi-Fi or hotspot types into the game's
// Server field. A PC has one address per network it is on.
function printPhoneAddresses() {
  const addresses = Object.values(require('os').networkInterfaces())
    .flat()
    .filter((address) => address.family === 'IPv4' && !address.internal)
    .map((address) => address.address);
  if (addresses.length === 0) return;

  console.log('📱 To play from a phone on the same network, type one of these into the Server field:');
  for (const address of addresses) console.log(`     ${address}:${PORT}`);
}

module.exports = app;
