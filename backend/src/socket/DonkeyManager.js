const DonkeyEngine = require('../donkey/DonkeyEngine');
const DonkeyGame = require('../models/DonkeyGame');
const Coins = require('../models/Coins');
const Friend = require('../models/Friend');
const Matchmaker = require('./Matchmaker');
const { WatchedMap } = require('./FriendsManager');
const BotAccounts = require('../bots/BotAccounts');
const DonkeyBots = require('../bots/DonkeyBots');

// Donkey Master over the game connection: private tables with a room code, "Play Online"
// matchmaking, the turn clocks, keeping tables in the database across a restart, and the
// coins. It shares everything else with rummy's SocketManager (`rummy`): the login check on
// the connection, the player's room of sockets, the profile photos, and the one coin balance,
// which both games change through Coins.move and announce with the same `coins` event.
//
// Every event a client sends here starts with "donkey" and is answered through the
// acknowledgement ({ ok: true, ... } or { ok: false, error }). What the server sends:
//   donkeyState        the table as that player sees it (DonkeyEngine.stateFor)
//   donkeyNotice       { type: joined | left | disconnected | reconnected | away, userId, username }
//   donkeyInvite       { userId, username, roomCode, maxPlayers, stake, again }
//   donkeyMatchStatus, donkeyMatchFound, donkeyMatchFailed   the "Play Online" search
//   coins              the balance, after every entry, refund and payout
// The client side is godot/net/donkey_client.gd.

const ROOM_GONE = 'Donkey table not found'; // the client knows this one (DonkeyClient.ROOM_GONE_ERROR)
const PRIVATE_SIZES = [2, 3, 4, 5, 6, 7, 8];
const ONLINE_SIZES = [2, 4, 6, 8];
const CLEANUP_MS = 300000; // a table nobody is connected to closes after 5 minutes
const FINISHED_KEEP_MS = 120000; // a finished table stays this long for its result
const AGAIN_MS = 600000; // players from the same table can call each other back this long
const INVITE_PAUSE_MS = 10000; // between two invitations to the same player
const ROOM_CODE_LENGTH = 6;
const ROOM_CODE_CHARS = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789'; // no 0/O or 1/I, they get misread

class DonkeyManager {
  constructor(io, rummy) {
    this.io = io;
    this.rummy = rummy;
    this.rooms = new Map(); // roomId -> DonkeyEngine
    this.codes = new Map(); // room code -> roomId, for private tables still waiting
    // userId -> roomId of the table they sit at. Friends see a player sit down or get up.
    this.userRooms = new WatchedMap((userId) => rummy.friends.presenceChanged(userId));
    this.lastRooms = new Map(); // userId -> roomId of a finished table they can still look at
    this.tableMates = new Map(); // userId -> { roomId, names: Map(id -> username), until }
    this.finished = new Set(); // roomIds whose end has been handled
    this.timers = new Map(); // roomId -> the turn clock or the pause after a trick
    this.cleanupTimers = new Map();
    this.snapshotWrites = new Map();
    this.lastInvite = new Map();
    this.snapshots = false; // true once the database has the tables
    // Computer players who fill the empty seats of a Play Online table nobody else came to
    this.bots = new DonkeyBots(this, BotAccounts);
    this.matchmaker = new Matchmaker({
      onMatch: (tickets, bots) => this.startMatched(tickets, bots),
      notify: (userId, event, payload) => this.toUser(userId, `donkey${event[0].toUpperCase()}${event.slice(1)}`, payload)
    });
    // After rummy's own preparation (the coins column it adds to users)
    this.ready = Promise.resolve(rummy.ready).then(() => this.restore());
    io.on('connection', (socket) => this.attach(socket));
    rummy.donkey = this; // rummy asks before seating someone (SocketManager.refuseIfPlayingDonkey)
  }

  // Brings back the tables of the previous run, closes the rest, settles what was left unpaid
  async restore() {
    try {
      await DonkeyGame.ensureSchema();
      this.snapshots = true;
    } catch (error) {
      console.error('Failed to prepare the database for Donkey Master:', error.message);
      return;
    }
    try {
      const restored = [];
      for (const row of await DonkeyGame.findResumable()) {
        try {
          const engine = DonkeyEngine.fromJSON(row.snapshot);
          if (engine.status === 'finished') {
            // It ended in the very moment the server stopped: see that it was paid out
            await this.payOut(engine);
            await DonkeyGame.setStatus(engine.roomId, 'finished');
            continue;
          }
          engine.restartClock();
          for (const player of engine.players.values()) {
            // no person is connected to a table just brought back; computer players are
            player.connected = this.bots.isBot(player.id);
            if (!player.left) this.userRooms.set(player.id, engine.roomId);
          }
          this.rooms.set(engine.roomId, engine);
          if (engine.isPrivate && engine.status === 'waiting') this.codes.set(engine.roomCode, engine.roomId);
          this.cleanupLater(engine.roomId); // closes it if nobody comes back
          restored.push(engine.roomId);
        } catch (error) {
          console.error(`Could not restore Donkey Master table ${row.id}:`, error.message);
        }
      }
      if (restored.length > 0) console.log(`♻️  Restored ${restored.length} Donkey Master table(s)`);
      await DonkeyGame.abandonUnfinished(restored);
      for (const row of await DonkeyGame.settleClosed()) {
        const engine = row.status === 'finished' && row.snapshot ? DonkeyEngine.fromJSON(row.snapshot) : null;
        if (engine && engine.status === 'finished') await DonkeyGame.settle(row.id, engine.settlement());
        else await DonkeyGame.refundAll(row.id);
      }
    } catch (error) {
      console.error('Failed to restore Donkey Master tables:', error.message);
    }
  }

  attach(socket) {
    const { userId } = socket.data;
    if (!userId) return;

    const handle = (event, handler) => {
      socket.on(event, async (data, ack) => {
        try {
          await this.ready;
          const result = await handler(data && typeof data === 'object' ? data : {});
          if (typeof ack === 'function') ack({ ok: true, ...result });
        } catch (error) {
          if (typeof ack === 'function') ack({ ok: false, error: error.message });
        }
      });
    };

    // Back at the table they were sitting at
    this.ready.then(() => {
      if (socket.connected) this.reconnected(userId);
    });

    handle('donkeyCreate', (data) => this.create(socket, data));
    handle('donkeyJoin', (data) => this.join(socket, data));
    handle('donkeyFind', (data) => this.find(socket, data));
    handle('donkeyCancelFind', async () => ({ cancelled: this.matchmaker.cancel(userId) }));
    handle('donkeyStart', async () => this.start(userId));
    handle('donkeyPlay', async (data) => this.play(userId, data));
    // Request Card: ask a neighbour for their hand; they accept or reject (see DonkeyEngine)
    handle('donkeyRequestCard', async (data) => this.requestCard(userId, data));
    handle('donkeyAnswerRequest', async (data) => this.answerRequest(userId, data));
    handle('donkeyInvite', (data) => this.invite(socket, data));
    handle('donkeyLeave', async () => {
      this.matchmaker.cancel(userId);
      this.lastRooms.delete(userId);
      await this.leave(userId);
      return {};
    });
    handle('donkeyState', async () => {
      const engine = this.roomOf(userId) || this.rooms.get(this.lastRooms.get(userId));
      if (!engine) throw new Error(ROOM_GONE);
      return { state: this.stateFor(engine, userId) };
    });

    socket.on('disconnect', () => this.disconnected(userId));
  }

  // ---------- sitting down ----------

  async create(socket, data) {
    const { userId } = socket.data;
    const options = this.tableOptions(data, PRIVATE_SIZES);
    this.checkFree(userId);
    await this.checkCoins(userId, options.stake);
    this.matchmaker.cancel(userId); // opening a table of one's own ends a search

    const engine = await this.openTable(options, userId, true);
    try {
      await this.payEntry(engine, userId);
    } catch (error) {
      this.closeRoom(engine, 'abandoned'); // the coins were spent elsewhere meanwhile
      throw error;
    }
    await this.getUpElsewhere(userId, engine.roomId);
    engine.addPlayer(userId, socket.data.username);
    this.userRooms.set(userId, engine.roomId);
    console.log(`🫏 Donkey Master table ${engine.roomCode} opened by ${socket.data.username}`);
    await this.afterMove(engine);
    if (data.again) this.inviteTableMates(socket, engine, String(data.again));
    return { roomId: engine.roomId, roomCode: engine.roomCode };
  }

  async join(socket, data) {
    const { userId } = socket.data;
    const code = String(data.roomCode || '').trim().toUpperCase().slice(0, 10);
    if (!code) throw new Error('Enter the room code your friend gave you');
    const mine = this.roomOf(userId);
    if (mine && mine.roomCode === code) {
      // Already sitting there: just the table again
      this.broadcast(mine);
      return { roomId: mine.roomId, roomCode: code };
    }
    const engine = this.rooms.get(this.codes.get(code));
    if (!engine) throw new Error('Room not found. Check the code with your friend.');
    if (engine.status !== 'waiting') throw new Error('This game has already started');
    if (engine.isFull()) throw new Error('This table is full');
    this.checkFree(userId, engine.roomId);
    await this.checkCoins(userId, engine.stake);

    await this.payEntry(engine, userId);
    try {
      engine.addPlayer(userId, socket.data.username);
    } catch (error) {
      // somebody took the last seat, or the host dealt, while the entry was being paid
      await this.refundEntry(engine, userId);
      throw error;
    }
    await this.getUpElsewhere(userId, engine.roomId);
    this.matchmaker.cancel(userId); // e.g. an invitation accepted while searching
    this.userRooms.set(userId, engine.roomId);
    this.cancelCleanup(engine.roomId);
    this.notice(engine, 'joined', userId);
    if (engine.isFull()) this.deal(engine); // a full table does not wait for the host
    await this.afterMove(engine);
    return { roomId: engine.roomId, roomCode: engine.roomCode };
  }

  // "Play Online": the search goes on until the matchmaker seats the player (donkeyMatchFound
  // and the table's state follow), they cancel, or the connection drops.
  async find(socket, data) {
    const { userId } = socket.data;
    const options = this.tableOptions(data, ONLINE_SIZES);
    this.checkFree(userId);
    await this.checkCoins(userId, options.stake);
    await this.getUpElsewhere(userId);
    const zone = Number(data.timezone);
    const offset = Number.isInteger(zone) && zone >= -720 && zone <= 840 ? zone : null;
    this.matchmaker.find(userId, socket.data.username, {
      gameType: 'donkey', maxPlayers: options.maxPlayers, stake: options.stake, pointValue: 0, offset
    });
    return { searching: true, region: Matchmaker.regionLabel(offset) };
  }

  // The matchmaker found players: open a table, take everyone's entry, deal. With `bots`,
  // computer players take the seats nobody came for. Resolves to the players who should
  // search on because the table could not start.
  async startMatched(tickets, bots = false) {
    const [first] = tickets;
    const engine = await this.openTable({ maxPlayers: first.maxPlayers, stake: first.stake }, first.userId, false);
    const seated = [];
    for (const ticket of tickets) {
      if (ticket.cancelled) continue;
      try {
        this.checkFree(ticket.userId);
        await this.payEntry(engine, ticket.userId);
      } catch (error) {
        this.toUser(ticket.userId, 'donkeyMatchFailed', { message: error.message });
        continue;
      }
      await this.getUpElsewhere(ticket.userId, engine.roomId);
      engine.addPlayer(ticket.userId, ticket.username);
      this.userRooms.set(ticket.userId, engine.roomId);
      seated.push(ticket);
    }
    let computers = 0;
    if (bots && seated.length > 0) {
      try {
        computers = await this.seatBots(engine);
      } catch (error) {
        console.error('Failed to seat computer players:', error.message);
      }
    }
    if (seated.length === 0 || seated.length + computers < 2) {
      this.closeRoom(engine, 'abandoned'); // gives back the entries taken
      return seated;
    }
    this.deal(engine);
    for (const ticket of seated) {
      this.toUser(ticket.userId, 'donkeyMatchFound', { roomId: engine.roomId, players: seated.length });
    }
    await this.afterMove(engine);
    return [];
  }

  // Computer players for every seat still free; each pays the entry like anyone. Returns how
  // many sat down.
  async seatBots(engine) {
    const free = engine.maxPlayers - engine.players.size;
    if (free <= 0) return 0;
    const isBusy = (id) => this.userRooms.has(id) || this.rummy.userGames.has(id);
    const chosen = await BotAccounts.pickFree(free, isBusy, engine.stake);
    let seated = 0;
    for (const bot of chosen) {
      if (engine.status !== 'waiting' || isBusy(bot.id)) continue;
      await this.payEntry(engine, bot.id);
      engine.addPlayer(bot.id, bot.username);
      this.userRooms.set(bot.id, engine.roomId);
      seated += 1;
    }
    return seated;
  }

  async start(userId) {
    const engine = this.requireRoom(userId);
    if (engine.status !== 'waiting') throw new Error('This game has already started');
    if (engine.hostId !== userId) throw new Error('Only the host can start the game');
    this.deal(engine);
    await this.afterMove(engine);
    return {};
  }

  deal(engine) {
    engine.start();
    if (this.codes.get(engine.roomCode) === engine.roomId) this.codes.delete(engine.roomCode);
    this.cancelCleanup(engine.roomId);
    DonkeyGame.setStatus(engine.roomId, 'playing')
      .catch((error) => console.error('Failed to mark a Donkey Master table as started:', error.message));
    for (const id of engine.players.keys()) this.rummy.friends.presenceChanged(id); // now playing
    console.log(`🃏 Donkey Master dealt at ${engine.roomCode}: ${engine.players.size} players, entry ${engine.stake}`);
  }

  // ---------- playing ----------

  async play(userId, data) {
    const engine = this.requireRoom(userId);
    engine.play(userId, String(data.cardId || '').slice(0, 4));
    await this.afterMove(engine);
    return {};
  }

  // Request Card. Between tricks a player may ask the player next to them, on either side,
  // for their cards; at most one request every few seconds. Everything is checked by the
  // engine: who may ask whom and when, the wait, the answer within its time.
  async requestCard(userId, data) {
    const engine = this.requireRoom(userId);
    const request = engine.requestCard(userId, String(data.to || ''));
    await this.afterMove(engine);
    return { requestId: request.id };
  }

  // The asked player's answer. Only an explicit accept moves the cards: all of the asked
  // player's hand goes to the one who asked, and the asked player is out.
  async answerRequest(userId, data) {
    const engine = this.requireRoom(userId);
    const request = engine.answerRequest(userId, String(data.requestId || ''), data.accept === true);
    await this.afterMove(engine);
    return { status: request.status };
  }

  // Gets a player up. Before the deal their entry comes back; holding cards during the game
  // they lose it (DonkeyEngine.removePlayer); out of the game already, it costs nothing.
  async leave(userId) {
    const engine = this.roomOf(userId);
    if (!engine) return;
    const player = engine.players.get(userId);
    const username = player ? player.username : '';
    const wasWaiting = engine.status === 'waiting';
    engine.removePlayer(userId);
    this.userRooms.delete(userId);
    if (wasWaiting) await this.refundEntry(engine, userId);
    this.notice(engine, 'left', userId, username);
    if (wasWaiting && engine.players.size === 0) {
      this.closeRoom(engine, 'abandoned');
      return;
    }
    await this.afterMove(engine);
  }

  // The account is being deleted
  async removeUser(userId) {
    this.matchmaker.cancel(userId);
    await this.leave(userId);
  }

  // Everything that follows a change: the clock, every player's view, the saved table, and
  // at the end the coins
  async afterMove(engine) {
    this.schedule(engine);
    this.broadcast(engine);
    await this.persist(engine);
    if (engine.status === 'finished' && !this.finished.has(engine.roomId)) {
      this.finished.add(engine.roomId);
      await this.onFinished(engine);
    }
  }

  async onFinished(engine) {
    const names = new Map([...engine.players.values()].map((player) => [player.id, player.username]));
    for (const id of engine.players.keys()) {
      // free to sit down elsewhere at once, and able to look at the result for a while
      if (this.userRooms.get(id) === engine.roomId) this.userRooms.delete(id);
      if (!engine.players.get(id).left) this.lastRooms.set(id, engine.roomId);
      this.tableMates.set(id, { roomId: engine.roomId, names, until: Date.now() + AGAIN_MS });
    }
    console.log(`🫏 Donkey Master over at ${engine.roomCode}: Master ${names.get(engine.masterId) || '-'}, Donkey ${names.get(engine.donkeyId) || '-'}`);
    await this.payOut(engine);
    DonkeyGame.setStatus(engine.roomId, 'finished')
      .catch((error) => console.error('Failed to close a Donkey Master table:', error.message));
    this.cancelCleanup(engine.roomId);
    const timer = setTimeout(() => this.closeRoom(engine, null), FINISHED_KEEP_MS);
    if (timer.unref) timer.unref();
    this.cleanupTimers.set(engine.roomId, timer);
  }

  // ---------- clocks ----------

  // One timer a table: the turn clock, or the pause after a trick
  schedule(engine) {
    clearTimeout(this.timers.get(engine.roomId));
    this.timers.delete(engine.roomId);
    this.bots.schedule(engine); // a computer player whose turn it is plays
    const next = engine.nextDeadline();
    if (!next) return;
    // Nobody there: the clock waits. Unless every person has got up for good: then the
    // computer players play the game out.
    if (!this.anyoneConnected(engine) && this.bots.people(engine).length > 0) return;
    const timer = setTimeout(() => this.onTimer(engine), Math.max(0, next.at - Date.now()));
    this.timers.set(engine.roomId, timer);
  }

  async onTimer(engine) {
    if (this.rooms.get(engine.roomId) !== engine) return;
    try {
      const next = engine.nextDeadline();
      if (!next) return;
      if (Date.now() < next.at) {
        this.schedule(engine); // a move came in while this timer was pending
        return;
      }
      if (next.what === 'resolve') {
        engine.resolveTrick();
      } else if (next.what === 'requests') {
        engine.settleRequests(); // an unanswered request has run out, or an answer has been shown
      } else {
        const result = engine.autoPlay();
        if (result.wentAway) this.notice(engine, 'away', result.playerId, '', true);
      }
      await this.afterMove(engine);
    } catch (error) {
      console.error('Donkey Master timer error:', error);
    }
  }

  // ---------- connections ----------

  reconnected(userId) {
    const engine = this.roomOf(userId);
    if (!engine) return;
    const player = engine.players.get(userId);
    const wasEmpty = !this.anyoneConnected(engine);
    if (player && !player.connected) {
      engine.setConnected(userId, true);
      this.notice(engine, 'reconnected', userId);
    }
    this.cancelCleanup(engine.roomId);
    if (wasEmpty) engine.restartClock(); // the clock stood still while nobody was there
    this.schedule(engine);
    this.broadcast(engine);
  }

  disconnected(userId) {
    // The same player may still be connected from another phone
    const remaining = this.io.sockets.adapter.rooms.get(this.rummy.userRoom(userId));
    if (remaining && remaining.size > 0) return;
    this.matchmaker.cancel(userId); // nobody is matched with a player who is not there
    const engine = this.roomOf(userId);
    if (!engine) return;
    engine.setConnected(userId, false);
    this.notice(engine, 'disconnected', userId);
    this.schedule(engine);
    this.broadcast(engine);
    if (!this.anyoneConnected(engine)) this.cleanupLater(engine.roomId);
  }

  // A person connected to the table (computer players are always there; they do not count)
  anyoneConnected(engine) {
    return [...engine.players.values()].some((player) => player.connected && !player.left && !this.bots.isBot(player.id));
  }

  isOnline(userId) {
    const sockets = this.io.sockets.adapter.rooms.get(this.rummy.userRoom(userId));
    return Boolean(sockets && sockets.size > 0);
  }

  // ---------- invitations ----------

  async invite(socket, data) {
    const { userId } = socket.data;
    const engine = this.requireRoom(userId);
    if (!engine.isPrivate || engine.status !== 'waiting') {
      throw new Error('Open a private table first, then invite your friends');
    }
    if (engine.isFull()) throw new Error('Your table is full');
    const otherId = String(parseInt(data.userId, 10) || '');
    if (!otherId || otherId === userId) throw new Error('Choose a friend to invite');

    const mates = this.tableMates.get(userId);
    const again = Boolean(mates && mates.until > Date.now() && mates.names.has(otherId));
    const friend = again ? { id: otherId, username: mates.names.get(otherId) } : await Friend.friendOf(Number(userId), Number(otherId));
    if (!friend) throw new Error('You can only invite your friends');
    const friendId = String(friend.id);
    if (engine.players.has(friendId)) throw new Error(`${friend.username} is already at your table`);
    if (!this.isOnline(friendId)) throw new Error(`${friend.username} is not online right now`);
    if (this.isPlaying(friendId)) throw new Error(`${friend.username} is in a game right now`);

    const pair = `${userId}:${friendId}`;
    if (Date.now() - (this.lastInvite.get(pair) || 0) < INVITE_PAUSE_MS) {
      throw new Error(`You have just invited ${friend.username}. Give them a moment.`);
    }
    for (const [key, time] of this.lastInvite) {
      if (Date.now() - time >= INVITE_PAUSE_MS) this.lastInvite.delete(key);
    }
    this.lastInvite.set(pair, Date.now());
    this.sendInvite(socket, engine, friendId, again);
    return { username: friend.username };
  }

  // "Play again" from a private table: everyone who was at it and is free gets called back
  inviteTableMates(socket, engine, previousRoomId) {
    const mates = this.tableMates.get(socket.data.userId);
    if (!mates || mates.roomId !== previousRoomId || mates.until <= Date.now()) return;
    for (const friendId of mates.names.keys()) {
      if (friendId === socket.data.userId || !this.isOnline(friendId) || this.isPlaying(friendId)) continue;
      this.sendInvite(socket, engine, friendId, true);
    }
  }

  sendInvite(socket, engine, friendId, again) {
    this.toUser(friendId, 'donkeyInvite', {
      userId: socket.data.userId,
      username: socket.data.username,
      roomCode: engine.roomCode,
      maxPlayers: engine.maxPlayers,
      stake: engine.stake,
      again
    });
  }

  // Holding cards at a Donkey Master table that is being played
  playingAt(userId) {
    const engine = this.roomOf(userId);
    return Boolean(engine && engine.status === 'playing' && engine.inPlay(engine.players.get(userId)));
  }

  // For the friends lists: 'playing', 'lobby' (waiting at a table) or null
  statusOf(userId) {
    const engine = this.roomOf(userId);
    if (!engine) return null;
    if (engine.status === 'waiting') return 'lobby';
    return this.playingAt(userId) ? 'playing' : null;
  }

  // A player saved or removed their photo: their table shows the new one at once
  avatarChanged(userId) {
    const engine = this.roomOf(userId);
    if (engine) this.broadcast(engine);
  }

  // At a table where the cards are dealt, in either game
  isPlaying(userId) {
    const rummyGame = this.rummy.getUserGame(userId);
    if (rummyGame && rummyGame.status !== 'waiting') return true;
    const engine = this.roomOf(userId);
    return Boolean(engine && engine.status === 'playing' && engine.inPlay(engine.players.get(userId)));
  }

  // ---------- coins ----------

  async payEntry(engine, userId) {
    if (!engine.stake) return;
    this.rummy.sendCoins(userId, await DonkeyGame.enter(userId, engine.roomId, engine.stake));
  }

  async refundEntry(engine, userId) {
    if (!engine.stake) return;
    try {
      this.rummy.sendCoins(userId, await DonkeyGame.refund(userId, engine.roomId));
    } catch (error) {
      console.error('Failed to give back a Donkey Master entry:', error.message);
    }
  }

  async payOut(engine) {
    if (!engine.stake) return;
    try {
      for (const { userId, balance } of await DonkeyGame.settle(engine.roomId, engine.settlement())) {
        this.rummy.sendCoins(userId, balance);
      }
    } catch (error) {
      console.error('Failed to pay out a Donkey Master table:', error.message);
    }
  }

  async checkCoins(userId, stake) {
    if (stake > 0 && (await Coins.balance(userId)) < stake) {
      throw new Error(`You need ${Coins.format(stake)} coins to sit at this table`);
    }
  }

  // ---------- tables ----------

  tableOptions(data, sizes) {
    const maxPlayers = parseInt(data.maxPlayers, 10);
    if (!sizes.includes(maxPlayers)) throw new Error('There is no Donkey Master table for that many players');
    const stake = parseInt(data.stake, 10) || 0;
    if (!Coins.isStake(stake)) throw new Error('There is no table with that entry');
    return { maxPlayers, stake };
  }

  // One table at a time, in either game: refuses while the player has cards in a game that is
  // being played
  checkFree(userId, exceptRoomId = null) {
    const rummyGame = this.rummy.getUserGame(userId);
    if (rummyGame && rummyGame.status !== 'waiting') {
      throw new Error('You are in a rummy game. Finish or leave it first.');
    }
    const engine = this.roomOf(userId);
    if (engine && engine.roomId !== exceptRoomId && engine.status === 'playing' && engine.inPlay(engine.players.get(userId))) {
      throw new Error('You are already playing at a Donkey Master table. Finish or leave it first.');
    }
  }

  // and gets up from a table that has not started (its entry comes back), in either game
  async getUpElsewhere(userId, exceptRoomId = null) {
    const rummyGame = this.rummy.getUserGame(userId);
    if (rummyGame && rummyGame.status === 'waiting') await this.rummy.removeFromGame(rummyGame, userId);
    this.rummy.matchmaker.cancel(userId);
    const engine = this.roomOf(userId);
    if (engine && engine.roomId !== exceptRoomId) await this.leave(userId);
  }

  async openTable({ maxPlayers, stake }, createdBy, isPrivate) {
    let roomId = null;
    let roomCode = '';
    for (let attempt = 0; attempt < 6 && !roomId; attempt++) {
      roomCode = '';
      for (let i = 0; i < ROOM_CODE_LENGTH; i++) {
        roomCode += ROOM_CODE_CHARS[Math.floor(Math.random() * ROOM_CODE_CHARS.length)];
      }
      try {
        roomId = await DonkeyGame.create({ roomCode, isPrivate, maxPlayers, stake, createdBy: Number(createdBy) });
      } catch (error) {
        if (error.code !== '23505') throw error; // 23505: the code is taken, try another
      }
    }
    if (!roomId) throw new Error('Could not open a table. Please try again.');
    const engine = new DonkeyEngine({ roomId, roomCode, maxPlayers, stake, isPrivate });
    this.rooms.set(roomId, engine);
    if (isPrivate) this.codes.set(roomCode, roomId);
    return engine;
  }

  roomOf(userId) {
    const roomId = this.userRooms.get(userId);
    if (!roomId) return null;
    const engine = this.rooms.get(roomId);
    if (!engine) {
      this.userRooms.delete(userId);
      return null;
    }
    return engine;
  }

  requireRoom(userId) {
    const engine = this.roomOf(userId);
    if (!engine) throw new Error(ROOM_GONE);
    return engine;
  }

  cleanupLater(roomId) {
    this.cancelCleanup(roomId);
    const timer = setTimeout(() => {
      const engine = this.rooms.get(roomId);
      if (engine && !this.anyoneConnected(engine)) this.closeRoom(engine, engine.status === 'finished' ? null : 'abandoned');
    }, CLEANUP_MS);
    if (timer.unref) timer.unref();
    this.cleanupTimers.set(roomId, timer);
  }

  cancelCleanup(roomId) {
    clearTimeout(this.cleanupTimers.get(roomId));
    this.cleanupTimers.delete(roomId);
  }

  // Takes a table out of memory. 'abandoned': nobody won, so every entry goes back.
  closeRoom(engine, finalStatus) {
    const { roomId } = engine;
    clearTimeout(this.timers.get(roomId));
    this.timers.delete(roomId);
    this.bots.forget(roomId);
    this.cancelCleanup(roomId);
    this.rooms.delete(roomId);
    this.finished.delete(roomId);
    if (this.codes.get(engine.roomCode) === roomId) this.codes.delete(engine.roomCode);
    for (const id of engine.players.keys()) {
      if (this.userRooms.get(id) === roomId) this.userRooms.delete(id);
      if (this.lastRooms.get(id) === roomId) this.lastRooms.delete(id);
    }
    if (finalStatus !== 'abandoned') return;
    (this.snapshotWrites.get(roomId) || Promise.resolve())
      .then(() => DonkeyGame.setStatus(roomId, 'abandoned'))
      .then(() => DonkeyGame.refundAll(roomId))
      .then((refunded) => refunded.forEach(({ userId, balance }) => this.rummy.sendCoins(userId, balance)))
      .catch((error) => console.error('Failed to close a Donkey Master table:', error.message));
  }

  // Writes for one table go one after another, so a slow write is never overtaken by an older one
  persist(engine) {
    if (!this.snapshots) return Promise.resolve();
    const { roomId } = engine;
    const write = (this.snapshotWrites.get(roomId) || Promise.resolve())
      .then(() => (this.rooms.get(roomId) === engine ? DonkeyGame.saveSnapshot(roomId, engine.serialize()) : null))
      .catch((error) => console.warn('⚠️  Failed to save a Donkey Master table:', error.message))
      .then(() => {
        if (this.snapshotWrites.get(roomId) === write) this.snapshotWrites.delete(roomId);
      });
    this.snapshotWrites.set(roomId, write);
    return write;
  }

  // ---------- sending ----------

  stateFor(engine, userId) {
    return engine.stateFor(userId, (id) => this.rummy.avatars.get(String(id)) || 0);
  }

  // Each player gets their own view, with only their own cards
  broadcast(engine) {
    for (const [id, player] of engine.players) {
      if (!player.left) this.toUser(id, 'donkeyState', this.stateFor(engine, id));
    }
  }

  // News about `userId` for the others at the table (and for them too with `toThemToo`)
  notice(engine, type, userId, username = '', toThemToo = false) {
    const player = engine.players.get(userId);
    const payload = { type, userId, username: username || (player ? player.username : '') };
    for (const [id, other] of engine.players) {
      if (other.left || (id === userId && !toThemToo)) continue;
      this.toUser(id, 'donkeyNotice', payload);
    }
  }

  toUser(userId, event, payload) {
    this.io.to(this.rummy.userRoom(userId)).emit(event, payload);
  }
}

DonkeyManager.ROOM_GONE = ROOM_GONE;

module.exports = DonkeyManager;
