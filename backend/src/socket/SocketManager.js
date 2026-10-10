const jwt = require('jsonwebtoken');
const Redis = require('ioredis');
const GameEngine = require('../game/GameEngine');
const Game = require('../models/Game');
const User = require('../models/User');
const Coins = require('../models/Coins');
const db = require('../database/db');
const config = require('../config');
const { FriendsManager, WatchedMap } = require('./FriendsManager');

const GAME_TTL_SECONDS = 86400; // 24 hours
const CLEANUP_DELAY_MS = 300000; // 5 minutes
const ROOM_CODE_LENGTH = 6;
const ROOM_CODE_CHARS = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789'; // no 0/O or 1/I, they get misread

class SocketManager {
  constructor(io) {
    this.io = io;
    this.games = new Map(); // gameId -> GameEngine instance
    this.friends = new FriendsManager(this);
    // userId -> gameId. Friends are told whenever a player sits down or gets up
    this.userGames = new WatchedMap((userId) => this.friends.presenceChanged(userId));
    this.timers = new Map(); // gameId -> turn clock or next-round countdown
    this.cleanupTimers = new Map(); // gameId -> pending removal
    this.snapshots = false; // true once the database can hold games in progress
    this.snapshotWrites = new Map(); // gameId -> the write of that game still under way

    // Redis for room persistence
    this.redis = this.connectRedis();

    this.setupSocketHandlers();
    // Resolves once the games of the previous run are back; nothing is answered before that
    this.ready = this.restoreGames();
  }

  // Redis is optional: games in progress are kept in the database either way (see restoreGames)
  connectRedis() {
    if (!process.env.REDIS_URL && !process.env.REDIS_HOST) {
      console.log('ℹ️  REDIS_HOST not set, running without game persistence');
      return null;
    }

    try {
      const options = {
        maxRetriesPerRequest: 3,
        retryStrategy: (times) => (times > 5 ? null : Math.min(times * 200, 2000))
      };
      const redis = process.env.REDIS_URL
        ? new Redis(process.env.REDIS_URL, options)
        : new Redis({
            host: process.env.REDIS_HOST,
            port: process.env.REDIS_PORT || 6379,
            password: process.env.REDIS_PASSWORD || undefined,
            ...options
          });

      redis.on('error', (err) => {
        console.warn('⚠️  Redis error:', err.message);
      });

      redis.on('connect', () => {
        console.log('🔗 Redis connected successfully');
      });

      // Fired once the retry strategy gives up
      redis.on('end', () => {
        console.warn('⚠️  Redis connection failed, running without persistence');
        this.redis = null;
      });

      return redis;
    } catch (error) {
      console.warn('⚠️  Redis initialization failed, running without persistence:', error.message);
      return null;
    }
  }

  // Brings back the games that were in progress when the server last stopped. Each one is
  // kept whole in its database row (see persistGame), so a restart does not end it: the
  // players reconnect and find the table as they left it.
  async restoreGames() {
    try {
      await Coins.ensureSchema();
    } catch (error) {
      console.error('Failed to prepare the database for coins:', error.message);
    }

    const restored = [];
    try {
      await Game.ensureSnapshotColumn();
      this.snapshots = true;

      for (const row of await Game.findResumable()) {
        try {
          const gameEngine = GameEngine.fromJSON(row.snapshot);
          if (gameEngine.status === 'finished') {
            // It ended in the very moment the server stopped: see that its pot was paid
            if (gameEngine.winner) await Coins.payWinner(gameEngine.gameId, gameEngine.winner);
            await Game.updateGameState(gameEngine.gameId, { status: 'finished', ended_at: new Date() });
            continue;
          }

          gameEngine.restartClock();
          for (const [playerId, player] of gameEngine.players) {
            // Nobody is connected to a game that was just restored
            player.connected = false;
            if (!player.left) this.userGames.set(playerId, gameEngine.gameId);
          }
          this.games.set(gameEngine.gameId, gameEngine);
          this.scheduleTimer(gameEngine);
          // If nobody comes back, it is closed like any game everyone walked away from
          this.cleanupGame(gameEngine.gameId);
          restored.push(gameEngine.gameId);
        } catch (error) {
          console.error(`Could not restore game ${row.id}:`, error.message);
        }
      }
      if (restored.length > 0) {
        console.log(`♻️  Restored ${restored.length} game(s) that were in progress`);
      }
    } catch (error) {
      console.error('Failed to restore games:', error.message);
    }

    // Whatever else was open cannot be resumed (with Redis it still can: see loadGame)
    if (!this.redis) {
      try {
        await Game.abandonUnfinished(restored);
      } catch (error) {
        console.error('Failed to close stale games:', error.message);
      }
    }

    // What was paid to sit at a game that is closed now goes back to its players
    try {
      await Coins.refundClosedGames();
    } catch (error) {
      console.error('Failed to give back the entries of closed games:', error.message);
    }
  }

  // ---------- coins ----------
  // A table can have an entry (gameEngine.stake). Sitting down pays it, leaving before the
  // cards are dealt gives it back, and the winner of the match takes everything paid in.

  // Throws when the player cannot pay
  async payEntry(gameEngine, userId) {
    if (!gameEngine.stake) return;
    this.sendCoins(userId, await Coins.enter(userId, gameEngine.gameId, gameEngine.stake));
  }

  async refundEntry(gameEngine, userId) {
    if (!gameEngine.stake) return;
    try {
      this.sendCoins(userId, await Coins.refund(userId, gameEngine.gameId));
    } catch (error) {
      console.error('Failed to give back an entry:', error.message);
    }
  }

  async payPot(gameEngine, winnerId) {
    if (!gameEngine.stake) return;
    if (!winnerId) {
      await this.refundEveryone(gameEngine);
      return;
    }
    try {
      const { pot, balance } = await Coins.payWinner(gameEngine.gameId, winnerId);
      if (pot > 0) this.sendCoins(winnerId, balance);
    } catch (error) {
      console.error('Failed to pay the pot:', error.message);
    }
  }

  // The game ended without a winner
  async refundEveryone(gameEngine) {
    if (!gameEngine.stake) return;
    try {
      for (const { userId, balance } of await Coins.refundAll(gameEngine.gameId)) {
        this.sendCoins(userId, balance);
      }
    } catch (error) {
      console.error('Failed to give back the entries:', error.message);
    }
  }

  // Tells a player how many coins they have now
  sendCoins(userId, balance) {
    if (balance === null || balance === undefined) return;
    this.io.to(this.userRoom(userId)).emit('coins', { coins: balance });
  }

  // Keeps the game where a restart of the server will find it again
  async persistGame(gameEngine) {
    await Promise.all([this.saveGameToRedis(gameEngine), this.saveSnapshot(gameEngine)]);
  }

  // Writes for one game go one after another, each storing the state as it is by then,
  // so a slow write is never overtaken by an older one.
  saveSnapshot(gameEngine) {
    if (!this.snapshots) return Promise.resolve();

    const { gameId } = gameEngine;
    const write = (this.snapshotWrites.get(gameId) || Promise.resolve())
      .then(() => (this.games.get(gameId) === gameEngine ? Game.saveSnapshot(gameId, gameEngine.serialize()) : null))
      .catch(error => console.warn('⚠️  Failed to save game:', error.message))
      .then(() => {
        if (this.snapshotWrites.get(gameId) === write) this.snapshotWrites.delete(gameId);
      });
    this.snapshotWrites.set(gameId, write);
    return write;
  }

  // The game is over or gone: its row no longer needs to hold it
  dropSnapshot(gameId) {
    if (!this.snapshots) return;
    (this.snapshotWrites.get(gameId) || Promise.resolve())
      .then(() => Game.clearSnapshot(gameId))
      .catch(error => console.warn('⚠️  Failed to clear saved game:', error.message));
  }

  setupSocketHandlers() {
    // Every socket must present the JWT issued at login; the user id comes from it, never from the payload
    this.io.use(async (socket, next) => {
      try {
        await this.ready; // the database is being prepared in the first moment after a start
        const token = socket.handshake.auth && socket.handshake.auth.token;
        const payload = jwt.verify(token, config.jwtSecret);
        const user = await User.findById(payload.id);
        if (!user) throw new Error('User not found');

        socket.data.userId = String(user.id);
        socket.data.username = user.username;
        next();
      } catch (error) {
        next(new Error('Authentication required'));
      }
    });

    this.io.on('connection', (socket) => {
      const { userId } = socket.data;
      console.log('🔌 New connection:', socket.id, 'user', userId);

      socket.join(this.userRoom(userId));

      // Put the player straight back into a game they are still part of
      this.ready.then(() => {
        if (!socket.connected) return;
        this.resumeGame(userId);
        // and tell them how many coins they have
        Coins.balance(userId)
          .then(balance => this.sendCoins(userId, balance))
          .catch(error => console.error('Failed to read a balance:', error.message));
      });

      // Replies go through the acknowledgement callback when the client passes one
      const handle = (event, handler) => {
        socket.on(event, async (data, ack) => {
          try {
            await this.ready; // right after a restart the games are still being brought back
            const result = await handler(data || {});
            if (typeof ack === 'function') ack({ ok: true, ...result });
          } catch (error) {
            if (typeof ack === 'function') ack({ ok: false, error: error.message });
            else socket.emit('gameError', { message: error.message });
          }
        });
      };

      // Create new game
      handle('createGame', async (data) => {
        const { gameType = 'points' } = data;
        const maxPlayers = parseInt(data.maxPlayers, 10) || 2;

        if (!GameEngine.isGameType(gameType)) {
          throw new Error('Invalid game type');
        }
        if (maxPlayers < 2 || maxPlayers > 6) {
          throw new Error('A game needs 2 to 6 players');
        }
        // What each player pays to sit down; 0 or nothing is a free table
        const stake = parseInt(data.stake, 10) || 0;
        if (!Coins.isStake(stake)) {
          throw new Error('There is no table with that entry');
        }

        const previousGame = this.requireFreeFor(userId, null);
        if (stake > 0 && (await Coins.balance(userId)) < stake) {
          throw new Error(`You need ${Coins.format(stake)} coins to open this table`);
        }

        // Create in database; its id is the gameId everywhere
        const gameRow = await this.createGameRow({
          gameType,
          maxPlayers,
          createdBy: Number(userId),
          currentPlayers: 1
        });
        const gameEngine = new GameEngine(gameRow.id, gameType, maxPlayers, gameRow.room_code);
        gameEngine.stake = stake;
        this.games.set(gameRow.id, gameEngine);

        try {
          await this.payEntry(gameEngine, userId);
        } catch (error) {
          this.deleteGame(gameEngine, 'abandoned'); // the coins were spent elsewhere meanwhile
          throw error;
        }

        if (previousGame) {
          await this.removeFromGame(previousGame, userId);
        }

        // Add creator as first player
        gameEngine.addPlayer(userId, this.displayName(socket, data.username));
        this.userGames.set(userId, gameRow.id);

        console.log(`🎮 Game created: ${gameRow.id} (room ${gameRow.room_code}) by ${socket.data.username}`);

        await this.afterMove(gameEngine);
        return { gameId: gameRow.id, roomCode: gameRow.room_code, status: gameEngine.status };
      });

      // Join a game by roomCode (backend resolves real gameId)
      handle('joinGameByRoomCode', async (data) => {
        const roomCode = String(data.roomCode || '').trim().toUpperCase();
        if (!roomCode) throw new Error('Room code required');

        const gameRow = await Game.findByRoomCode(roomCode);
        if (!gameRow) throw new Error('Game not found');

        return this.joinGame(socket, gameRow.id, data.username);
      });

      // Player joins a game room by backend-generated gameId
      handle('joinGame', async (data) => {
        return this.joinGame(socket, data.gameId, data.username);
      });

      // Host starts before the table is full
      handle('startGame', async () => {
        const gameEngine = this.requireGame(userId);
        if (gameEngine.hostId !== userId) {
          throw new Error('Only the host can start the game');
        }

        gameEngine.startGame();
        this.markStarted(gameEngine);
        await this.afterMove(gameEngine);
      });

      // Draw card
      handle('drawCard', async (data) => {
        const gameEngine = this.requireGame(userId);
        const result = gameEngine.drawCard(userId, Boolean(data.fromDiscard));

        await this.afterMove(gameEngine);
        return { card: result.card };
      });

      // Discard card
      handle('discardCard', async (data) => {
        const gameEngine = this.requireGame(userId);
        gameEngine.discardCard(userId, data.cardId);

        await this.afterMove(gameEngine);
      });

      // Player rearranged their hand into groups
      handle('arrangeHand', async (data) => {
        const gameEngine = this.requireGame(userId);
        // An arrangement is private, so nothing is sent out, unless it has just turned a
        // closed joker face up: then the player gets the joker and the table hears of it
        if (gameEngine.arrangeHand(userId, data.groups)) {
          this.broadcastState(gameEngine);
        }

        await this.persistGame(gameEngine);
      });

      // Declare win
      handle('declare', async (data) => {
        const gameEngine = this.requireGame(userId);
        const { valid, roundResult } = gameEngine.declare(userId, data.cardId, data.groups);

        if (!valid) {
          this.emitToGame(gameEngine, 'wrongDeclaration', { userId, username: this.nameOf(gameEngine, userId) }, userId);
        }

        await this.afterMove(gameEngine, roundResult);
        return { valid };
      });

      // After someone else's valid declaration: hand in the final arrangement of one's own cards
      handle('submitHand', async (data) => {
        const gameEngine = this.requireGame(userId);
        const roundResult = gameEngine.submitHand(userId, data.groups);

        await this.afterMove(gameEngine, roundResult);
      });

      // Drop out of the round
      handle('drop', async () => {
        const gameEngine = this.requireGame(userId);
        const roundResult = gameEngine.drop(userId);

        this.emitToGame(gameEngine, 'playerDropped', { userId, username: this.nameOf(gameEngine, userId) }, userId);
        await this.afterMove(gameEngine, roundResult);
      });

      // Ask for the current state again
      handle('reconnectGame', async () => {
        const gameEngine = this.requireGame(userId);
        return { gameState: gameEngine.getGameState(userId) };
      });

      // Leave game
      handle('leaveGame', async () => {
        const gameEngine = this.getUserGame(userId);
        if (gameEngine) {
          await this.removeFromGame(gameEngine, userId);
        }
      });

      // Friends lists, who is online, invitations
      this.friends.attach(socket, handle);

      // Disconnect
      socket.on('disconnect', () => {
        console.log('🔌 Disconnected:', socket.id);

        // The same user may still be connected from another socket
        const remaining = this.io.sockets.adapter.rooms.get(this.userRoom(userId));
        if (remaining && remaining.size > 0) return;

        this.friends.presenceChanged(userId); // friends see the player go offline

        const gameEngine = this.getUserGame(userId);
        if (!gameEngine) return;

        const player = gameEngine.players.get(userId);
        if (player) {
          player.connected = false;
        }

        this.emitToGame(gameEngine, 'playerDisconnected', { userId, username: this.nameOf(gameEngine, userId) }, userId);
        this.broadcastState(gameEngine);

        const anyoneConnected = Array.from(gameEngine.players.values()).some(p => p.connected);
        if (!anyoneConnected) {
          this.cleanupGame(gameEngine.gameId);
        }
      });
    });
  }

  userRoom(userId) {
    return `user:${userId}`;
  }

  displayName(socket, requested) {
    const name = typeof requested === 'string' ? requested.trim().slice(0, 20) : '';
    return name || socket.data.username;
  }

  nameOf(gameEngine, userId) {
    const player = gameEngine.players.get(userId);
    return player ? player.username : '';
  }

  generateRoomCode() {
    let roomCode = '';
    for (let i = 0; i < ROOM_CODE_LENGTH; i++) {
      roomCode += ROOM_CODE_CHARS[Math.floor(Math.random() * ROOM_CODE_CHARS.length)];
    }
    return roomCode;
  }

  async createGameRow(fields) {
    for (let attempt = 0; attempt < 5; attempt++) {
      try {
        return await Game.create({ ...fields, roomCode: this.generateRoomCode() });
      } catch (error) {
        // 23505 = room code already taken, try another one
        if (error.code !== '23505') throw error;
      }
    }
    throw new Error('Could not allocate a room code');
  }

  // The game a user is currently seated in, if it still exists
  getUserGame(userId) {
    const gameId = this.userGames.get(userId);
    if (!gameId) return null;

    const gameEngine = this.games.get(gameId);
    if (!gameEngine) {
      this.userGames.delete(userId);
      return null;
    }
    return gameEngine;
  }

  requireGame(userId) {
    const gameEngine = this.getUserGame(userId);
    if (!gameEngine) {
      throw new Error('Game not found');
    }
    return gameEngine;
  }

  // A user sits at one table at a time. Returns a lobby they would have to leave first, if any.
  requireFreeFor(userId, targetGameId) {
    const current = this.getUserGame(userId);
    if (!current || current.gameId === targetGameId) return null;

    if (current.status !== 'waiting') {
      throw new Error(`You are already in a game (room ${current.roomCode}). Finish or leave it first.`);
    }
    return current;
  }

  // Find a game in memory, or bring it back from Redis
  async loadGame(gameId) {
    let gameEngine = this.games.get(gameId);

    if (!gameEngine && this.redis) {
      try {
        const gameData = await this.redis.get(`game:${gameId}`);
        if (gameData) {
          gameEngine = GameEngine.fromJSON(JSON.parse(gameData));
          for (const [playerId, player] of gameEngine.players) {
            // Nobody is connected to a game that was just restored
            player.connected = false;
            if (!player.left) this.userGames.set(playerId, gameId);
          }
          this.games.set(gameId, gameEngine);
          this.scheduleTimer(gameEngine);
        }
      } catch (error) {
        console.warn('⚠️  Failed to load game from Redis:', error.message);
      }
    }

    return gameEngine || null;
  }

  async joinGame(socket, gameId, requestedName) {
    const { userId } = socket.data;

    const gameEngine = await this.loadGame(gameId);
    if (!gameEngine || gameEngine.status === 'finished') {
      throw new Error('Game is no longer available');
    }

    const previousGame = this.requireFreeFor(userId, gameId);
    const isNewPlayer = !gameEngine.players.has(userId);
    const wasWaiting = gameEngine.status === 'waiting';

    // A new player pays the table's entry before sitting down
    if (isNewPlayer) {
      if (!wasWaiting) throw new Error('Game has already started');
      if (gameEngine.players.size >= gameEngine.maxPlayers) throw new Error('Game is full');
      await this.payEntry(gameEngine, userId);
    }

    // Add player to game
    let player;
    try {
      player = gameEngine.addPlayer(userId, this.displayName(socket, requestedName));
    } catch (error) {
      // e.g. somebody else took the last seat while the entry was being paid
      if (isNewPlayer) await this.refundEntry(gameEngine, userId);
      throw error;
    }

    if (previousGame) {
      await this.removeFromGame(previousGame, userId);
    }

    // Track player
    this.userGames.set(userId, gameId);
    this.cancelCleanup(gameId);

    if (isNewPlayer) {
      // Notify others
      this.emitToGame(gameEngine, 'playerJoined', {
        userId,
        username: player.username,
        totalPlayers: gameEngine.players.size
      }, userId);

      Game.updateGameState(gameId, { current_players: gameEngine.players.size })
        .catch(error => console.error('Failed to update player count:', error.message));
    }

    if (wasWaiting && gameEngine.status === 'playing') {
      this.markStarted(gameEngine);
    }

    await this.afterMove(gameEngine);
    return { gameId, roomCode: gameEngine.roomCode, status: gameEngine.status };
  }

  resumeGame(userId) {
    const gameEngine = this.getUserGame(userId);
    if (!gameEngine) return;

    const player = gameEngine.players.get(userId);
    if (player && !player.connected) {
      player.connected = true;
      this.emitToGame(gameEngine, 'playerReconnected', { userId, username: player.username }, userId);
    }

    this.cancelCleanup(gameEngine.gameId);
    this.broadcastState(gameEngine);
  }

  async removeFromGame(gameEngine, userId) {
    const username = this.nameOf(gameEngine, userId);
    const wasWaiting = gameEngine.status === 'waiting';
    const roundResult = gameEngine.removePlayer(userId);
    this.userGames.delete(userId);
    // Nothing was played yet, so the entry goes back. Once the cards are dealt it stays in the pot
    if (wasWaiting) await this.refundEntry(gameEngine, userId);

    this.emitToGame(gameEngine, 'playerLeft', { userId, username }, userId);

    if (gameEngine.players.size === 0) {
      // The lobby emptied before the game started
      this.deleteGame(gameEngine, 'abandoned');
      return;
    }

    if (gameEngine.status === 'waiting') {
      Game.updateGameState(gameEngine.gameId, { current_players: gameEngine.players.size })
        .catch(error => console.error('Failed to update player count:', error.message));
    }

    await this.afterMove(gameEngine, roundResult);
  }

  // The account is being deleted: take the player out of their game and close their connections
  async removeUser(userId) {
    const gameEngine = this.getUserGame(userId);
    if (gameEngine) {
      await this.removeFromGame(gameEngine, userId);
    }
    this.io.in(this.userRoom(userId)).disconnectSockets(true);
  }

  // Push everything that follows a change: results, timers, fresh state for every player, persistence
  async afterMove(gameEngine, roundResult = null) {
    if (roundResult) {
      this.onRoundEnded(gameEngine, roundResult);
    }

    this.scheduleTimer(gameEngine);
    this.broadcastState(gameEngine);

    await this.persistGame(gameEngine);
  }

  onRoundEnded(gameEngine, roundResult) {
    if (!roundResult.matchOver) return;

    // Broadcast results
    this.emitToGame(gameEngine, 'gameOver', roundResult);

    // Save to database
    this.saveGameToDatabase(gameEngine, roundResult);

    // The winner takes what everyone paid to sit down
    this.payPot(gameEngine, roundResult.matchWinner);

    // Players are free to start another game straight away
    for (const playerId of gameEngine.players.keys()) {
      if (this.userGames.get(playerId) === gameEngine.gameId) {
        this.userGames.delete(playerId);
      }
    }

    // Cleanup
    this.cleanupGame(gameEngine.gameId);
  }

  markStarted(gameEngine) {
    const joker = gameEngine.deckManager.joker;
    Game.updateGameState(gameEngine.gameId, {
      status: 'playing',
      started_at: new Date(),
      current_players: gameEngine.players.size,
      joker: joker ? joker.code : null
    }).catch(error => console.error('Failed to mark game as started:', error.message));

    // Their friends see them go from waiting to playing
    for (const playerId of gameEngine.players.keys()) {
      this.friends.presenceChanged(playerId);
    }
  }

  // One pending timer per game: the turn clock while playing, the countdown between pool rounds
  scheduleTimer(gameEngine) {
    const { gameId } = gameEngine;
    clearTimeout(this.timers.get(gameId));
    this.timers.delete(gameId);

    let deadline = null;
    if (gameEngine.status === 'playing') deadline = gameEngine.turnDeadline;
    else if (gameEngine.status === 'round_over') deadline = gameEngine.nextRoundAt;
    if (!deadline) return;

    const timer = setTimeout(() => this.onTimer(gameEngine), Math.max(0, deadline - Date.now()));
    this.timers.set(gameId, timer);
  }

  async onTimer(gameEngine) {
    if (this.games.get(gameEngine.gameId) !== gameEngine) return;

    try {
      let roundResult = null;

      if (gameEngine.status === 'playing') {
        if (Date.now() < gameEngine.turnDeadline) {
          // The turn moved on while this timer was pending
          this.scheduleTimer(gameEngine);
          return;
        }
        // Nobody is on turn while the table arranges its cards after a declaration
        const timedOut = gameEngine.players.get(gameEngine.currentPlayer);
        const timedOutId = gameEngine.currentPlayer;
        roundResult = gameEngine.autoPlay();
        if (timedOut && timedOut.status === 'dropped') {
          this.emitToGame(gameEngine, 'playerDropped', {
            userId: timedOutId,
            username: this.nameOf(gameEngine, timedOutId),
            timedOut: true
          });
        }
      } else if (gameEngine.status === 'round_over') {
        gameEngine.startNextRound();
      }

      await this.afterMove(gameEngine, roundResult);
    } catch (error) {
      console.error('Game timer error:', error);
    }
  }

  // Each player gets their own view: only their own hand is included
  broadcastState(gameEngine) {
    for (const [playerId, player] of gameEngine.players) {
      if (player.left) continue;
      this.io.to(this.userRoom(playerId)).emit('gameState', gameEngine.getGameState(playerId));
    }
  }

  emitToGame(gameEngine, event, payload, exceptUserId = null) {
    for (const [playerId, player] of gameEngine.players) {
      if (playerId === exceptUserId || player.left) continue;
      this.io.to(this.userRoom(playerId)).emit(event, payload);
    }
  }

  async saveGameToRedis(gameEngine) {
    if (!this.redis) return; // Skip if Redis not available
    try {
      const key = `game:${gameEngine.gameId}`;
      const data = JSON.stringify(gameEngine.serialize());
      await this.redis.setex(key, GAME_TTL_SECONDS, data);
    } catch (error) {
      console.warn('⚠️  Failed to save game to Redis:', error.message);
    }
  }

  async saveGameToDatabase(gameEngine, result) {
    try {
      // Update game status in database
      await Game.updateGameState(gameEngine.gameId, {
        status: 'finished',
        ended_at: new Date(),
        deck: JSON.stringify(gameEngine.deckManager.deck),
        discard_pile: JSON.stringify(gameEngine.deckManager.discardPile)
      });

      // Record player results
      let seatPosition = 0;
      for (const [playerId, player] of gameEngine.players) {
        const isWinner = playerId === result.matchWinner;
        try {
          await db.query(
            `INSERT INTO player_games (game_id, user_id, seat_position, cards, melds, score, is_winner, joined_at)
             VALUES ($1, $2, $3, $4, $5, $6, $7, CURRENT_TIMESTAMP)`,
            [
              gameEngine.gameId,
              Number(playerId),
              seatPosition++,
              JSON.stringify(player.hand || []),
              JSON.stringify(player.groups || []),
              player.totalScore,
              isWinner,
            ]
          );
        } catch (e) {
          console.error('Failed to record player game row:', e.message);
        }
      }

    } catch (error) {
      console.error('Error saving game to database:', error);
    }
  }

  cancelCleanup(gameId) {
    clearTimeout(this.cleanupTimers.get(gameId));
    this.cleanupTimers.delete(gameId);
  }

  cleanupGame(gameId) {
    // Remove from memory after delay
    this.cancelCleanup(gameId);
    const timer = setTimeout(() => {
      const gameEngine = this.games.get(gameId);
      if (gameEngine) {
        this.deleteGame(gameEngine, gameEngine.status === 'finished' ? null : 'abandoned');
      }
    }, CLEANUP_DELAY_MS);
    this.cleanupTimers.set(gameId, timer);
  }

  deleteGame(gameEngine, finalStatus = null) {
    const { gameId } = gameEngine;

    clearTimeout(this.timers.get(gameId));
    this.timers.delete(gameId);
    this.cancelCleanup(gameId);
    this.games.delete(gameId);

    for (const playerId of gameEngine.players.keys()) {
      if (this.userGames.get(playerId) === gameId) {
        this.userGames.delete(playerId);
      }
    }

    if (this.redis) {
      this.redis.del(`game:${gameId}`).catch(() => {});
    }
    this.dropSnapshot(gameId);
    if (finalStatus === 'abandoned') {
      // Nobody won: whoever still has an entry in this game gets it back
      this.refundEveryone(gameEngine);
    }

    if (finalStatus) {
      Game.updateGameState(gameId, { status: finalStatus, ended_at: new Date() })
        .catch(error => console.error('Failed to close game:', error.message));
    }
  }
}

module.exports = SocketManager;
