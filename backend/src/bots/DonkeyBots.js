const DonkeyBrain = require('./DonkeyBrain');

// The computer players at Donkey Master tables. After every change at a table (DonkeyManager
// calls schedule() wherever it sets the table's clock), a computer player whose turn it is
// plays a card after a pause like a person's, through DonkeyEngine as a player does. The turn
// clock stays as a safety net.
//
// Once no person is left at a table, the computer players play the game out at once, so its
// coins are settled by the rules.

const pause = (from, to) => from + Math.floor(Math.random() * (to - from));
const HURRY_MS = 30;

class DonkeyBots {
  constructor(manager, accounts) {
    this.manager = manager; // the DonkeyManager
    this.accounts = accounts;
    this.timers = new Map(); // roomId -> the next computer move
  }

  isBot(userId) {
    return this.accounts.isBot(userId);
  }

  // People still seated at the table: not computer players, not gone
  people(engine) {
    return [...engine.players.values()].filter((player) => !player.left && !this.isBot(player.id));
  }

  forget(roomId) {
    clearTimeout(this.timers.get(roomId));
    this.timers.delete(roomId);
  }

  schedule(engine) {
    this.forget(engine.roomId);
    if (engine.status !== 'playing' || engine.trickEnd || !engine.turn || !this.isBot(engine.turn)) return;
    const hurry = this.people(engine).length === 0;
    const timer = setTimeout(() => {
      this.timers.delete(engine.roomId);
      this.act(engine).catch((error) => console.error('Computer player error:', error));
    }, hurry ? HURRY_MS : pause(900, 2600));
    if (timer.unref) timer.unref();
    this.timers.set(engine.roomId, timer);
  }

  async act(engine) {
    const manager = this.manager;
    if (manager.rooms.get(engine.roomId) !== engine) return;
    if (engine.status !== 'playing' || engine.trickEnd || !this.isBot(engine.turn)) return;
    const cardId = DonkeyBrain.choose(engine, engine.turn);
    if (!cardId) return;
    engine.play(engine.turn, cardId);
    await manager.afterMove(engine);
  }
}

module.exports = DonkeyBots;
