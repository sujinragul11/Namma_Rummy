const ChatModeration = require('../models/ChatModeration');

// Chat at the table: short messages and emoji reactions between the players of one game.
// It only passes words along. Turns, cards and the clock are never touched, and the game is
// not saved because of it. Messages are not written down either, except one that a player
// reports (see ChatModeration). A player who blocked another gets nothing from them.

// The reactions a player can send, by name; the app has a picture for each
const EMOJIS = ['laugh', 'cool', 'thumbs', 'heart', 'fire', 'clap', 'wow', 'cry', 'angry', 'think', 'pray', 'party'];
const MAX_LENGTH = 120; // characters in one message
const HISTORY = 40; // messages kept per table, for a player who comes back after losing the connection
const BURST = 6; // messages one player may send...
const BURST_MS = 10000; // ...within this time
const REPORTS_PER_HOUR = 20; // more than this from one player is not taken
// Words shown as stars. A short list, meant to be added to
const BLOCKED_WORDS = /\b(fuck\w*|f+u+c+k+\w*|shit\w*|bitch\w*|bastard\w*|asshole\w*|cunt\w*|dick|dickhead\w*|slut\w*|whore\w*|motherf\w*)\b/gi;
// Invisible characters and direction marks that could disguise a message
const HIDDEN_CHARACTERS = /[\x00-\x1f\x7f-\x9f\u200b-\u200f\u202a-\u202e\u2060-\u206f\ufeff]/g;

class ChatManager {
  constructor(manager) {
    this.manager = manager; // the SocketManager: who sits at which table
    this.logs = new Map(); // gameId -> the latest messages, oldest first
    this.sent = new Map(); // userId -> when their latest messages went out
    this.blocks = new Map(); // userId -> Set of the ids they blocked, for players who are connected
    this.loading = new Map(); // userId -> the reading of their blocks, while it is under way
    this.reported = new Set(); // "reporter:message id", so a message is reported once
    this.nextId = 1;
    this.preparing = null;
    this.prepared().catch((error) => console.warn('Chat tables not ready yet, will try again:', error.message));
  }

  // The tables for blocks and reports, made once. After a failure (the database may still be
  // starting) the next request tries again.
  prepared() {
    if (!this.preparing) {
      this.preparing = ChatModeration.ensureSchema().catch((error) => {
        this.preparing = null;
        throw error;
      });
    }
    return this.preparing;
  }

  // A message as the players see it: the words cleaned up and cut to length, rude words starred
  static clean(text) {
    const flat = String(text == null ? '' : text)
      .normalize('NFC')
      .replace(HIDDEN_CHARACTERS, '')
      .replace(/\s+/g, ' ')
      .trim();
    // Counted in characters as people see them, so an emoji is never cut in half
    const cut = Array.from(flat).slice(0, MAX_LENGTH).join('');
    return cut.replace(BLOCKED_WORDS, (word) => '*'.repeat(Array.from(word).length));
  }

  // Whether `viewerId` has blocked `senderId`. Throwing things at a seat may ask the same.
  isBlocked(viewerId, senderId) {
    const blocked = this.blocks.get(String(viewerId));
    return Boolean(blocked && blocked.has(String(senderId)));
  }

  // Reads whom the player has blocked, keeps it for the messages to come, and returns the list
  async loadBlocks(userId) {
    const reading = this.prepared()
      .then(() => ChatModeration.blockedBy(Number(userId)))
      .then((list) => {
        this.blocks.set(userId, new Set(list.map((entry) => entry.id)));
        return list;
      });
    this.loading.set(userId, reading.catch(() => []));
    return reading;
  }

  // Throws when the player has sent too much too quickly
  checkPace(userId) {
    const now = Date.now();
    const recent = (this.sent.get(userId) || []).filter((time) => now - time < BURST_MS);
    if (recent.length >= BURST) {
      this.sent.set(userId, recent);
      throw new Error('You are sending messages too fast. Wait a moment.');
    }
    recent.push(now);
    this.sent.set(userId, recent);

    // Players who have gone quiet are forgotten now and then
    if (this.sent.size > 500) {
      for (const [id, times] of this.sent) {
        if (now - times[times.length - 1] >= BURST_MS) this.sent.delete(id);
      }
    }
  }

  remember(gameId, message) {
    const log = this.logs.get(gameId) || [];
    log.push(message);
    if (log.length > HISTORY) log.splice(0, log.length - HISTORY);
    this.logs.set(gameId, log);

    // The chat of a table that is over goes with it
    if (this.logs.size > this.manager.games.size) {
      for (const id of this.logs.keys()) {
        if (!this.manager.games.has(id)) this.logs.delete(id);
      }
    }
  }

  // Everyone at the table hears it, except whoever has blocked the sender
  deliver(gameEngine, message) {
    for (const [playerId, player] of gameEngine.players) {
      if (player.left || this.isBlocked(playerId, message.userId)) continue;
      this.manager.io.to(this.manager.userRoom(playerId)).emit('chat', message);
    }
  }

  // Called for every new connection, with SocketManager's `handle` for replies
  attach(socket, handle) {
    const { userId } = socket.data;
    const other = (data) => {
      const id = Number(data.userId);
      if (!Number.isInteger(id) || id <= 0) throw new Error('Unknown player');
      if (String(id) === userId) throw new Error('You cannot block yourself');
      return id;
    };

    this.loadBlocks(userId).catch((error) => console.error('Failed to read chat blocks:', error.message));
    socket.on('disconnect', () => {
      const sockets = this.manager.io.sockets.adapter.rooms.get(this.manager.userRoom(userId));
      if (!sockets || sockets.size === 0) {
        this.blocks.delete(userId);
        this.loading.delete(userId);
      }
    });

    // { text } for a message, or { emoji } with one of EMOJIS for a reaction
    handle('sendChat', async (data) => {
      const gameEngine = this.manager.requireGame(userId);
      const message = {
        id: this.nextId++,
        gameId: gameEngine.gameId,
        userId,
        username: this.manager.nameOf(gameEngine, userId),
        at: Date.now(),
      };
      if (data.emoji !== undefined) {
        if (!EMOJIS.includes(data.emoji)) throw new Error('Unknown emoji');
        message.kind = 'emoji';
        message.emoji = data.emoji;
      } else {
        const text = ChatManager.clean(data.text);
        if (!text) throw new Error('Type a message first');
        message.kind = 'text';
        message.text = text;
      }
      this.checkPace(userId);

      this.remember(gameEngine.gameId, message);
      this.deliver(gameEngine, message);
      return { id: message.id };
    });

    // What has been said at the player's table, oldest first, leaving out whom they blocked
    handle('chatHistory', async () => {
      const gameEngine = this.manager.requireGame(userId);
      await this.loading.get(userId);
      const messages = (this.logs.get(gameEngine.gameId) || [])
        .filter((message) => !this.isBlocked(userId, message.userId));
      return { gameId: gameEngine.gameId, messages };
    });

    // The players this one has blocked: { blocked: [{ id, username }] }
    handle('chatBlocks', async () => ({ blocked: await this.loadBlocks(userId) }));

    // { userId, blocked: true or false }
    handle('blockPlayer', async (data) => {
      const otherId = other(data);
      await this.prepared();
      if (data.blocked === false) {
        await ChatModeration.unblock(Number(userId), otherId);
      } else {
        await ChatModeration.block(Number(userId), otherId);
      }
      return { blocked: await this.loadBlocks(userId) };
    });

    // { messageId } of a message at the player's table: kept for review, and its sender blocked
    handle('reportChat', async (data) => {
      const gameEngine = this.manager.requireGame(userId);
      const message = (this.logs.get(gameEngine.gameId) || []).find((entry) => entry.id === Number(data.messageId));
      if (!message) throw new Error('That message can no longer be reported');
      if (message.userId === userId) throw new Error('You cannot report your own message');
      await this.prepared();

      const key = `${userId}:${message.id}`;
      if (!this.reported.has(key)) {
        if ((await ChatModeration.recentReports(Number(userId))) >= REPORTS_PER_HOUR) {
          throw new Error('You have sent many reports. Please wait a while before sending more.');
        }
        const words = message.kind === 'emoji' ? `[emoji: ${message.emoji}]` : message.text;
        const reportId = await ChatModeration.report(Number(userId), Number(message.userId), gameEngine.gameId, words);
        this.reported.add(key);
        if (this.reported.size > 5000) this.reported.clear();
        console.warn(`🚩 Chat report #${reportId}: ${socket.data.username} reported ${message.username}: ${words}`);
      }
      await ChatModeration.block(Number(userId), Number(message.userId));
      return { reported: true, blocked: await this.loadBlocks(userId) };
    });
  }
}

ChatManager.EMOJIS = EMOJIS;
ChatManager.MAX_LENGTH = MAX_LENGTH;

module.exports = ChatManager;
