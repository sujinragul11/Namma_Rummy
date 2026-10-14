const Friend = require('../models/Friend');

const INVITE_PAUSE_MS = 10000; // between two invitations to the same friend
const PRESENCE_DELAY_MS = 50; // gathers the changes of one move into one update

// A Map that reports every key whose value changes. SocketManager keeps "who sits at which
// table" in one, so friends are told when a player sits down or gets up wherever in the
// code that happens.
class WatchedMap extends Map {
  constructor(onChange) {
    super();
    this.onChange = onChange;
  }

  set(key, value) {
    const changed = this.get(key) !== value;
    super.set(key, value);
    if (changed) this.onChange(key);
    return this;
  }

  delete(key) {
    const existed = super.delete(key);
    if (existed) this.onChange(key);
    return existed;
  }
}

// Friends lists, who is online, and invitations to a table.
// Every change is answered by sending the players concerned their whole lists again
// ('friendsState'): they are short, and the client never has to patch one.
class FriendsManager {
  constructor(manager) {
    this.manager = manager; // the SocketManager: sockets, tables, who sits where
    this.changed = new Set(); // players whose status changed since the last update
    this.timer = null;
    this.lastInvite = new Map(); // "from:to" -> time of the last invitation
  }

  // 'offline', 'online', 'lobby' (waiting at a table) or 'playing'
  statusOf(userId) {
    const sockets = this.manager.io.sockets.adapter.rooms.get(this.manager.userRoom(userId));
    if (!sockets || sockets.size === 0) return 'offline';

    const gameEngine = this.manager.getUserGame(userId);
    if (!gameEngine) return 'online';
    return gameEngine.status === 'waiting' ? 'lobby' : 'playing';
  }

  async stateFor(userId) {
    const me = Number(userId);
    const [lists, recent] = await Promise.all([Friend.list(me), Friend.recentPlayers(me)]);
    const plain = (entry) => ({ id: String(entry.id), username: entry.username });
    return {
      friends: lists.friends.map((friend) => ({ ...plain(friend), status: this.statusOf(String(friend.id)) })),
      incoming: lists.incoming.map(plain),
      outgoing: lists.outgoing.map(plain),
      recent: recent.map(plain),
    };
  }

  // Sends a player their lists as they are now
  async push(userId) {
    if (this.statusOf(String(userId)) === 'offline') return;
    try {
      const state = await this.stateFor(userId);
      this.manager.io.to(this.manager.userRoom(String(userId))).emit('friendsState', state);
    } catch (error) {
      console.error('Failed to send a friends list:', error.message);
    }
  }

  pushAll(userIds) {
    for (const userId of userIds) this.push(userId);
  }

  // Everyone whose lists show this player (used before an account is deleted)
  contactsOf(userId) {
    return Friend.contactIds(Number(userId));
  }

  // The player came online, went offline, sat down or got up: their friends see it
  presenceChanged(userId) {
    this.changed.add(String(userId));
    if (!this.timer) {
      this.timer = setTimeout(() => this.tellFriends(), PRESENCE_DELAY_MS);
    }
  }

  async tellFriends() {
    const players = [...this.changed];
    this.changed.clear();
    this.timer = null;

    try {
      const toTell = new Set();
      for (const userId of players) {
        for (const friendId of await Friend.friendIds(Number(userId))) toTell.add(friendId);
      }
      this.pushAll(toTell);
    } catch (error) {
      console.error('Failed to update friends:', error.message);
    }
  }

  // Called for every new connection, with SocketManager's `handle` for replies
  attach(socket, handle) {
    const { userId } = socket.data;
    const me = Number(userId);
    const other = (data) => {
      const id = Number(data.userId);
      if (!Number.isInteger(id) || id <= 0) throw new Error('Unknown player');
      return id;
    };

    handle('friends', () => this.stateFor(userId));

    handle('friendRequest', async (data) => {
      const { user, accepted, silent } = await Friend.request(me, data.username);
      this.push(userId);
      if (!silent) this.push(user.id);
      return { username: user.username, accepted };
    });

    handle('friendRespond', async (data) => {
      const otherId = other(data);
      await Friend.respond(me, otherId, data.action);
      this.pushAll([userId, otherId]);
    });

    handle('friendRemove', async (data) => {
      const otherId = other(data);
      await Friend.remove(me, otherId);
      this.pushAll([userId, otherId]);
    });

    // Calls a friend to the table we are waiting at. Players who have just finished a game
    // together may call each other too, friends or not: that is "play again".
    handle('inviteFriend', async (data) => {
      const gameEngine = this.manager.getUserGame(userId);
      if (!gameEngine || gameEngine.status !== 'waiting') {
        throw new Error('Create a game first, then invite your friends');
      }
      if (gameEngine.players.size >= gameEngine.maxPlayers) throw new Error('Your table is full');

      const otherId = other(data);
      const tableMate = await Friend.tableMate(me, otherId);
      const friend = tableMate || (await Friend.friendOf(me, otherId));
      if (!friend) throw new Error('You can only invite your friends');
      const friendId = String(friend.id);
      if (gameEngine.players.has(friendId)) throw new Error(`${friend.username} is already at your table`);

      const status = this.statusOf(friendId);
      if (status === 'offline') throw new Error(`${friend.username} is not online right now`);
      if (status === 'playing') throw new Error(`${friend.username} is in a game right now`);

      const pair = `${userId}:${friendId}`;
      if (Date.now() - (this.lastInvite.get(pair) || 0) < INVITE_PAUSE_MS) {
        throw new Error(`You have just invited ${friend.username}. Give them a moment.`);
      }
      for (const [key, time] of this.lastInvite) {
        if (Date.now() - time >= INVITE_PAUSE_MS) this.lastInvite.delete(key);
      }
      this.lastInvite.set(pair, Date.now());

      this.manager.io.to(this.manager.userRoom(friendId)).emit('gameInvite', {
        userId,
        username: socket.data.username,
        roomCode: gameEngine.roomCode,
        poolLimit: gameEngine.rules.poolLimit,
        closedJoker: gameEngine.rules.closedJoker,
        deals: gameEngine.rules.deals, // Deals Rummy: how many deals, otherwise null
        maxPlayers: gameEngine.maxPlayers,
        stake: gameEngine.stake || 0, // the coins it costs to sit down
        pointValue: gameEngine.pointValue || 0, // Points Rummy for coins a point; the stake is then only held
        again: Boolean(tableMate), // they have just played together
      });
      return { username: friend.username };
    });

    this.push(userId);
    this.presenceChanged(userId);
  }
}

module.exports = { FriendsManager, WatchedMap };
