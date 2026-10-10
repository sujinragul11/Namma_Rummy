const config = require('./config');
const express = require('express');
const http = require('http');
const socketIo = require('socket.io');
const cors = require('cors');
const helmet = require('helmet');
const jwt = require('jsonwebtoken');
const rateLimit = require('express-rate-limit');

const db = require('./database/db');
const pages = require('./pages');
const User = require('./models/User');
const Game = require('./models/Game');
const SocketManager = require('./socket/SocketManager');
const { cleanEmail, cleanPhone, MESSAGES } = require('./validation');

const app = express();
const server = http.createServer(app);
const io = socketIo(server, {
  // Same permissive policy as the HTTP API below; sockets are authenticated by JWT
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


// Auth middleware
const authenticateToken = (req, res, next) => {
  const authHeader = req.headers['authorization'];
  const token = authHeader && authHeader.split(' ')[1];

  if (!token) return res.status(401).json({ error: 'Access token required' });

  jwt.verify(token, config.jwtSecret, (err, user) => {
    if (err) return res.status(403).json({ error: 'Invalid token' });
    req.user = user;
    next();
  });
};

// Text typed on a phone keyboard often arrives with stray spaces, or not at all
const cleanText = (value) => (typeof value === 'string' ? value.trim() : '');

// The account behind what was typed at login: an email, a phone number or a username.
// A phone number is looked up the way it is stored, however it was typed ("+91 98765 43210").
const findAccount = async (identifier) => {
  const phone = cleanPhone(identifier);
  return (phone && (await User.findByIdentifier(phone))) || User.findByIdentifier(identifier);
};

// Auth routes
app.post('/api/auth/register', passwordLimiter, async (req, res) => {
  try {
    const { password } = req.body;
    const username = cleanText(req.body.username);
    // A new account needs both an email address and a mobile number; '' means not a valid one
    const email = cleanEmail(req.body.email);
    const phone = cleanPhone(req.body.phone);

    if (!username || !password) {
      return res.status(400).json({ error: 'Username and password required' });
    }
    if (!email) {
      return res.status(400).json({ error: MESSAGES.email });
    }
    if (!phone) {
      return res.status(400).json({ error: MESSAGES.phone });
    }

    // make sure username/email/phone are unique
    if (await User.findByUsername(username)) {
      return res.status(400).json({ error: 'Username already in use' });
    }
    if (await User.findByEmail(email)) {
      return res.status(400).json({ error: 'Email already in use' });
    }
    if (await User.findByPhone(phone)) {
      return res.status(400).json({ error: 'Phone already in use' });
    }

    const user = await User.create({ username, email, phone, password });
    const token = jwt.sign(
      { id: user.id, email: user.email, phone: user.phone },
      config.jwtSecret,
      { expiresIn: '24h' }
    );

    res.status(201).json({ user, token });
  } catch (error) {
    console.error('Registration error:', error);
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

    const token = jwt.sign(
      { id: user.id, email: user.email, phone: user.phone },
      config.jwtSecret,
      { expiresIn: '24h' }
    );

    delete user.password_hash;
    delete user.wallet; // a column left from an earlier idea; nothing uses it
    res.json({ user, token });
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
        created_at: user.created_at,
      }
    });
  } catch (error) {
    console.error('Get profile error:', error);
    res.status(500).json({ error: 'Internal server error' });
  }
});

// Update username / email
app.patch('/api/user/profile', authenticateToken, async (req, res) => {
  try {
    const username = cleanText(req.body.username);
    const email = cleanEmail(req.body.email);

    if (!username || username.length > 50) {
      return res.status(400).json({ error: 'Username must be 1 to 50 characters' });
    }
    // Every account has an email address; it can be changed but not removed
    if (!email) {
      return res.status(400).json({ error: MESSAGES.email });
    }

    const current = await User.findById(req.user.id);
    if (!current) {
      return res.status(404).json({ error: 'User not found' });
    }

    const user = await User.updateProfile(req.user.id, { username, email });
    res.json({ user });
  } catch (error) {
    // 23505 = unique violation on username or email
    if (error.code === '23505') {
      return res.status(400).json({ error: 'Username or email already in use' });
    }
    console.error('Update profile error:', error);
    res.status(500).json({ error: 'Internal server error' });
  }
});

// Initialize Socket.IO
const socketManager = new SocketManager(io);

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

// Web pages: what the store listings link to
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
