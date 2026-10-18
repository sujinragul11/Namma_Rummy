// Playful things a player throws at another player's picture at the table: a cake, a tomato,
// a ghost, an aruval... Every player at the table sees it fly from the thrower to the target
// and play its own little scene there. Like the chat, it only passes the throw along: turns,
// cards, coins and the clock are never touched, nothing is written to the database, and the
// game is not saved because of it.

// What can be thrown, by name; the app has a picture and an animation for each
const ITEMS = [
  'aruval', 'knife', 'ghost', 'cake', 'chocolate',
  'tomato', 'egg', 'bomb', 'chappal', 'coconut',
  'hammer', 'boxing', 'firecracker', 'chili', 'ice',
  'balloon', 'rose', 'crown', 'chai', 'money',
];
const BURST = 4; // throws one player may make...
const BURST_MS = 8000; // ...within this time

class Throwables {
  constructor(manager) {
    this.manager = manager; // the SocketManager: who sits at which table
    this.thrown = new Map(); // userId -> when their latest throws went out
    this.nextId = 1;
  }

  // Throws when the player has thrown too much too quickly
  checkPace(userId) {
    const now = Date.now();
    const recent = (this.thrown.get(userId) || []).filter((time) => now - time < BURST_MS);
    if (recent.length >= BURST) {
      this.thrown.set(userId, recent);
      throw new Error('Easy there! Wait a moment before throwing more.');
    }
    recent.push(now);
    this.thrown.set(userId, recent);

    // Players who have stopped throwing are forgotten now and then
    if (this.thrown.size > 500) {
      for (const [id, times] of this.thrown) {
        if (now - times[times.length - 1] >= BURST_MS) this.thrown.delete(id);
      }
    }
  }

  // A player who has blocked someone in the chat does not see what that someone throws either
  hides(viewerId, throwerId) {
    const chat = this.manager.chat;
    return viewerId !== throwerId && Boolean(chat && typeof chat.isBlocked === 'function' && chat.isBlocked(viewerId, throwerId));
  }

  // Called for every new connection, with SocketManager's `handle` for replies
  attach(socket, handle) {
    const { userId } = socket.data;

    // { to: the target's user id, item: one of ITEMS }
    handle('throwItem', async (data) => {
      const gameEngine = this.manager.requireGame(userId);
      const to = String(data.to == null ? '' : data.to);
      if (!ITEMS.includes(data.item)) throw new Error('Unknown item');
      if (to === userId) throw new Error('Pick another player');
      const target = gameEngine.players.get(to);
      if (!target || target.left) throw new Error('That player is not at your table');
      this.checkPace(userId);

      const toss = { id: this.nextId++, gameId: gameEngine.gameId, from: userId, to, item: data.item, at: Date.now() };
      for (const [playerId, player] of gameEngine.players) {
        if (player.left || this.hides(playerId, userId)) continue;
        this.manager.io.to(this.manager.userRoom(playerId)).emit('itemThrown', toss);
      }
      return { id: toss.id };
    });
  }
}

Throwables.ITEMS = ITEMS;

module.exports = Throwables;
