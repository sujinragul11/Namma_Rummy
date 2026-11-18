const RummyBrain = require('./RummyBrain');

// The computer players at rummy tables. After every change at a table (SocketManager calls
// schedule() wherever it sets the table's clock), a computer player whose move it is makes it
// after a pause like a person's: draw, then a moment later discard or declare. After someone
// else's declaration each one hands in its best arrangement. The moves go through GameEngine
// exactly as a player's do, and the turn clock stays as a safety net: should a computer player
// ever not move, the clock plays for it as for anyone.
//
// Once no person is left at a table (all of them got up), nobody is waiting for the computer
// players any more: they play the game out at once, so its coins are settled by the rules.

const pause = (from, to) => from + Math.floor(Math.random() * (to - from));
const HURRY_MS = 30;
const GIVE_UP_HURRY_MS = 10 * 60 * 1000; // a game left to computer players closes after this

class RummyBots {
  constructor(manager, accounts) {
    this.manager = manager; // the SocketManager
    this.accounts = accounts;
    this.timers = new Map(); // gameId -> the next computer move
    this.hurrySince = new Map(); // gameId -> when the last person got up
  }

  isBot(userId) {
    return this.accounts.isBot(userId);
  }

  // People still seated at the table: not computer players, not gone
  people(engine) {
    return [...engine.players.values()].filter((player) => !player.left && !this.isBot(player.id));
  }

  forget(gameId) {
    clearTimeout(this.timers.get(gameId));
    this.timers.delete(gameId);
    this.hurrySince.delete(gameId);
  }

  schedule(engine) {
    const { gameId } = engine;
    clearTimeout(this.timers.get(gameId));
    this.timers.delete(gameId);
    if (!this.hasBots(engine)) return;

    const hurry = this.people(engine).length === 0;
    if (hurry && !this.hurrySince.has(gameId)) this.hurrySince.set(gameId, Date.now());
    if (!hurry) this.hurrySince.delete(gameId);

    const wait = this.nextWait(engine, hurry);
    if (wait === null) return;
    const timer = setTimeout(() => {
      this.timers.delete(gameId);
      this.act(engine).catch((error) => console.error('Computer player error:', error));
    }, hurry ? HURRY_MS : wait);
    if (timer.unref) timer.unref();
    this.timers.set(gameId, timer);
  }

  hasBots(engine) {
    return [...engine.players.keys()].some((id) => this.isBot(id));
  }

  // How long until a computer player moves, or null when none is to move
  nextWait(engine, hurry) {
    if (engine.status === 'round_over') return hurry ? 0 : null; // the clock deals the next round
    if (engine.status !== 'playing') return null;
    if (engine.declaredBy) {
      return engine.getArranging().some((player) => this.isBot(player.id)) ? pause(2500, 5500) : null;
    }
    const player = engine.players.get(engine.currentPlayer);
    if (!player || !this.isBot(player.id) || player.status !== 'active') return null;
    return engine.turnPhase === 'draw' ? pause(1800, 4500) : pause(1000, 2800);
  }

  async act(engine) {
    const manager = this.manager;
    await manager.rejoinWrites.get(engine.gameId)?.catch(() => {});
    if (manager.games.get(engine.gameId) !== engine) return;

    const since = this.hurrySince.get(engine.gameId);
    if (since && Date.now() - since > GIVE_UP_HURRY_MS && this.people(engine).length === 0) {
      console.warn(`Closing ${engine.gameId}: computer players could not finish it`);
      manager.deleteGame(engine, 'abandoned');
      return;
    }

    let roundResult = null;
    if (engine.status === 'round_over') {
      if (this.people(engine).length > 0) return;
      roundResult = engine.startNextRound();
    } else if (engine.status !== 'playing') {
      return;
    } else if (engine.declaredBy) {
      for (const player of engine.getArranging()) {
        if (!this.isBot(player.id)) continue;
        const { groups } = RummyBrain.arrange(player.hand, this.jokerFor(engine, player.id));
        roundResult = engine.submitHand(player.id, groups) || roundResult;
        if (roundResult) break;
      }
    } else {
      roundResult = this.playTurn(engine);
      if (roundResult === undefined) return; // not a computer player's move after all
    }
    await manager.afterMove(engine, roundResult);
  }

  // One step of a computer player's turn. Returns the round result (or null), undefined when
  // it is not a computer player's move.
  playTurn(engine) {
    const manager = this.manager;
    const player = engine.players.get(engine.currentPlayer);
    if (!player || !this.isBot(player.id) || player.status !== 'active') return undefined;
    const id = player.id;
    const joker = this.jokerFor(engine, id);

    if (engine.turnPhase === 'draw') {
      if (player.turnsTaken === 0 && RummyBrain.dropAtStart(player.hand, joker)) {
        const result = engine.drop(id);
        manager.emitToGame(engine, 'playerDropped', { userId: id, username: manager.nameOf(engine, id) }, id);
        return result;
      }
      const top = engine.deckManager.getTopDiscard();
      engine.drawCard(id, RummyBrain.takeOpenCard(player.hand, top, joker));
      // Laying the cards out, as a person arranges theirs: a pure sequence shows a closed joker
      engine.arrangeHand(id, RummyBrain.arrange(player.hand, this.jokerFor(engine, id)).groups);
      return null;
    }

    const keep = player.drawnFromDiscard ? player.lastDrawnId : null;
    const plan = RummyBrain.discard(player.hand, this.jokerFor(engine, id), keep);
    if (plan.declare) {
      const { valid, roundResult } = engine.declare(id, plan.cardId, plan.groups);
      if (!valid) {
        manager.emitToGame(engine, 'wrongDeclaration', { userId: id, username: manager.nameOf(engine, id) }, id);
      }
      return roundResult;
    }
    engine.arrangeHand(id, plan.groups);
    engine.discardCard(id, plan.cardId);
    return null;
  }

  // The joker as this player sees it: null while a closed joker is still hidden from them
  jokerFor(engine, userId) {
    return engine.getGameState(userId).joker;
  }
}

module.exports = RummyBots;
