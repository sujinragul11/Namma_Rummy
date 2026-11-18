const DonkeyBrain = require('./DonkeyBrain');

// The computer players at Donkey Master tables. After every change at a table (DonkeyManager
// calls schedule() wherever it sets the table's clock), a computer player whose turn it is
// plays a card after a pause like a person's, through DonkeyEngine as a player does. The turn
// clock stays as a safety net.
//
// Request Card: asked for its hand, a computer player always accepts after a moment (giving
// the hand away gets it out of the game), and now and then, between tricks, it asks a
// neighbour itself (DonkeyBrain.whomToAsk).
//
// Once no person is left at a table, the computer players play the game out at once, so its
// coins are settled by the rules.

const pause = (from, to) => from + Math.floor(Math.random() * (to - from));
const HURRY_MS = 30;
const ANSWER_RETRY_MS = 800; // the engine says wait (a card of ours still in the trick)

class DonkeyBots {
  constructor(manager, accounts) {
    this.manager = manager; // the DonkeyManager
    this.accounts = accounts;
    this.timers = new Map(); // roomId -> the next card a computer player plays
    this.answers = new Map(); // `${roomId}:${requestId}` -> a computer player's answer to come
    this.asks = new Map(); // roomId -> a request a computer player is about to send
    this.askedAt = new Map(); // roomId -> the trick at whose start the bots last thought of asking
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
    clearTimeout(this.asks.get(roomId));
    this.asks.delete(roomId);
    this.askedAt.delete(roomId);
    for (const [key, timer] of this.answers) {
      if (key.startsWith(`${roomId}:`)) {
        clearTimeout(timer);
        this.answers.delete(key);
      }
    }
  }

  schedule(engine) {
    this.scheduleTurn(engine);
    this.scheduleAnswers(engine);
    this.scheduleAsk(engine);
  }

  scheduleTurn(engine) {
    clearTimeout(this.timers.get(engine.roomId));
    this.timers.delete(engine.roomId);
    if (engine.status !== 'playing' || engine.trickEnd || !engine.turn || !this.isBot(engine.turn)) return;
    const hurry = this.people(engine).length === 0;
    this.later(this.timers, engine.roomId, hurry ? HURRY_MS : pause(900, 2600), () => this.play(engine));
  }

  // Every request to a computer player gets its answer, once
  scheduleAnswers(engine) {
    for (const request of engine.requests || []) {
      const key = `${engine.roomId}:${request.id}`;
      if (request.status !== 'pending' || !this.isBot(request.to) || this.answers.has(key)) continue;
      // A moment like a person's, but never so long that the request runs out first
      const wait = Math.min(pause(1500, 4000), Math.max(200, (request.until - Date.now()) / 2));
      this.later(this.answers, key, wait, () => this.answer(engine, request.id, key));
    }
  }

  // At the start of a trick, maybe one computer player asks a neighbour for their hand
  scheduleAsk(engine) {
    if (engine.status !== 'playing' || engine.mustLead || engine.trickEnd || engine.trick.length > 0) return;
    if (this.askedAt.get(engine.roomId) === engine.trickNo || this.asks.has(engine.roomId)) return;
    this.askedAt.set(engine.roomId, engine.trickNo);
    if (this.people(engine).length === 0) return; // nobody to play for
    for (const player of engine.seated()) {
      if (!this.isBot(player.id) || !engine.inPlay(player) || player.hand.length === 0) continue;
      if (engine.requestWait(player.id) > 0) continue;
      const target = DonkeyBrain.whomToAsk(engine, player.id);
      if (!target) continue;
      this.later(this.asks, engine.roomId, pause(300, 900), () => this.ask(engine, player.id, target));
      return;
    }
  }

  later(timers, key, wait, action) {
    const timer = setTimeout(() => {
      timers.delete(key);
      action().catch((error) => console.error('Computer player error:', error));
    }, wait);
    if (timer.unref) timer.unref();
    timers.set(key, timer);
  }

  live(engine) {
    return this.manager.rooms.get(engine.roomId) === engine && engine.status === 'playing';
  }

  async play(engine) {
    if (!this.live(engine) || engine.trickEnd || !this.isBot(engine.turn)) return;
    // Asked for its cards and on turn, it answers before it plays, as a person would: once a
    // card of its own is in the trick it could not accept until the trick is over
    const asked = (engine.requests || []).find((request) => request.status === 'pending' && request.to === engine.turn);
    if (asked) {
      try {
        engine.answerRequest(asked.to, asked.id, true);
        await this.manager.afterMove(engine);
        return;
      } catch (error) {
        // not now after all: play the card
      }
    }
    const cardId = DonkeyBrain.choose(engine, engine.turn);
    if (!cardId) return;
    engine.play(engine.turn, cardId);
    await this.manager.afterMove(engine);
  }

  async answer(engine, requestId, key) {
    if (!this.live(engine)) return;
    const request = (engine.requests || []).find((one) => one.id === requestId);
    if (!request || request.status !== 'pending') return;
    try {
      engine.answerRequest(request.to, requestId, true);
    } catch (error) {
      // Not now (a card of ours is still in the trick): again in a moment, while it lasts
      if (request.status === 'pending') this.later(this.answers, key, ANSWER_RETRY_MS, () => this.answer(engine, requestId, key));
      return;
    }
    await this.manager.afterMove(engine);
  }

  async ask(engine, botId, target) {
    if (!this.live(engine)) return;
    try {
      engine.requestCard(botId, target);
    } catch (error) {
      return; // the moment has passed (the trick was led meanwhile)
    }
    await this.manager.afterMove(engine);
  }
}

module.exports = DonkeyBots;
