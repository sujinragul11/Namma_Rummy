// The computer players' decisions, without a server or a database: whole games played by
// computer players only, through the real GameEngine and DonkeyEngine and the same code the
// server runs for them (RummyBots.playTurn, RummyBrain, DonkeyBrain).
//   node tests/bots-brain.js [--games=40]
// Checks: a ready hand is declared, never a wrong declaration, every move is one the engine
// accepts, every game type comes to an end, and how long a decision takes.
const assert = require('node:assert/strict');
const RummyBrain = require('../src/bots/RummyBrain');
const RummyBots = require('../src/bots/RummyBots');
const DonkeyBrain = require('../src/bots/DonkeyBrain');
const GameEngine = require('../src/game/GameEngine');
const DonkeyEngine = require('../src/donkey/DonkeyEngine');
const Validator = require('../src/game/Validator');

const option = (name, fallback) => {
  const found = process.argv.find((arg) => arg.startsWith(`--${name}=`));
  return found ? found.slice(name.length + 3) : fallback;
};
const GAMES = parseInt(option('games', '40'), 10);
let checks = 0;
const check = (condition, message) => { assert.ok(condition, message); checks++; };

const card = (code, deck = 0) => {
  const [, value, suit] = code.match(/^(10|[A2-9JQK])(.)$/);
  return { id: `${code}-${deck}`, value, suit, code, isJoker: false };
};
const JOKER = { id: 'JOKER-0', value: 'Joker', suit: '★', code: 'JOKER', isJoker: true };
const hand = (codes) => codes.split(' ').map((code) => (code === 'JOKER' ? JOKER : card(code)));

// ---------- a hand that is ready is declared ----------
{
  // A-2-3♠ pure, 5-6-7♥ pure, four nines, Q-K♥ with the printed joker; the 10♦ goes
  const ready = hand('A♠ 2♠ 3♠ 5♥ 6♥ 7♥ 9♦ 9♣ 9♠ 9♥ Q♥ K♥ JOKER 10♦');
  for (const joker of [card('3♦', 1), null]) {
    const plan = RummyBrain.discard(ready, joker);
    check(plan.declare && plan.cardId === '10♦-0', `a ready hand is declared, throwing the 10♦ (joker ${joker && joker.code})`);
    const byId = new Map(ready.map((c) => [c.id, c]));
    check(Validator.evaluateHand(plan.groups.map((ids) => ids.map((id) => byId.get(id))), joker).valid, 'and its groups are a valid show');
  }
  // Without any wild a hand needs naturals only
  const plain = hand('A♠ 2♠ 3♠ 4♠ 5♥ 6♥ 7♥ 9♦ 9♣ 9♠ J♣ J♦ J♥ K♣');
  const plan = RummyBrain.discard(plain, null);
  check(plan.declare && plan.cardId === 'K♣-0', 'a ready hand without jokers is declared');
  // One card short is not declared
  const almost = hand('A♠ 2♠ 3♠ 5♥ 6♥ 7♥ 9♦ 9♣ 9♠ Q♥ K♥ 8♣ 10♦ 4♦');
  check(!RummyBrain.discard(almost, null).declare, 'a hand that is not ready is not declared');
  // The open card that completes a sequence is taken; one that helps nothing is not
  const waiting = hand('4♠ 5♠ 7♥ 8♥ 9♥ K♦ K♣ 2♣ 9♣ Q♦ 3♦ 6♣ J♠');
  check(RummyBrain.takeOpenCard(waiting, card('6♠', 1), null), 'the open card that makes 4-5-6♠ is taken');
  let passes = 0;
  for (let n = 0; n < 20; n++) if (!RummyBrain.takeOpenCard(waiting, card('A♥', 1), null)) passes++;
  check(passes >= 18, `an open card that helps nothing is left (${passes}/20)`);
}

// ---------- whole rummy games of computer players ----------
const quiet = { emitToGame() {}, nameOf: (engine, id) => id };
const bots = new RummyBots(quiet, { isBot: () => true });

function playRummy(gameType, seats) {
  const engine = new GameEngine(`g-${gameType}-${seats}`, gameType, seats, 'TEST');
  for (let seat = 0; seat < seats; seat++) engine.addPlayer(`b${seat}`, `bot${seat}`);
  const stats = { moves: 0, declares: 0, wrong: 0, drops: 0, rounds: 1, slowest: 0 };
  for (let step = 0; step < 20000; step++) {
    if (engine.status === 'finished') return stats;
    if (engine.status === 'round_over') {
      engine.startNextRound();
      stats.rounds++;
      continue;
    }
    if (engine.declaredBy) {
      for (const player of engine.getArranging()) {
        const { groups } = RummyBrain.arrange(player.hand, engine.getGameState(player.id).joker);
        if (engine.submitHand(player.id, groups)) break;
      }
      continue;
    }
    const mover = engine.players.get(engine.currentPlayer);
    const phase = engine.turnPhase;
    const before = mover.status;
    const started = Date.now();
    bots.playTurn(engine); // throws if a move is refused
    stats.slowest = Math.max(stats.slowest, Date.now() - started);
    stats.moves++;
    if (mover.wrongDeclaration) stats.wrong++;
    if (engine.declaredBy === mover.id || (engine.lastResult && engine.lastResult.winner === mover.id && phase === 'discard')) stats.declares++;
    if (before === 'active' && mover.status === 'dropped' && !mover.wrongDeclaration) stats.drops++;
  }
  throw new Error(`${gameType} for ${seats} did not end`);
}

const totals = { moves: 0, declares: 0, wrong: 0, drops: 0, rounds: 0, slowest: 0, games: 0 };
const started = Date.now();
const types = ['points', 'pool', 'pool_201', 'close_joker', 'deals_2', 'deals_3'];
for (let n = 0; n < GAMES; n++) {
  const gameType = types[n % types.length];
  const seats = [2, 6, 3, 2, 4, 2][n % 6];
  const stats = playRummy(gameType, seats);
  for (const key of ['moves', 'declares', 'wrong', 'drops', 'rounds']) totals[key] += stats[key];
  totals.slowest = Math.max(totals.slowest, stats.slowest);
  totals.games++;
}
check(totals.games === GAMES, `${GAMES} rummy games of every kind came to an end`);
check(totals.wrong === 0, `no computer player ever declared wrongly (${totals.wrong})`);
check(totals.declares > 0, `computer players finish hands by declaring (${totals.declares} times)`);
check(totals.slowest < 400, `the slowest move took ${totals.slowest} ms`);
console.log(`rummy: ${totals.games} games, ${totals.rounds} rounds, ${totals.moves} moves, ${totals.declares} shows, ${totals.drops} drops; slowest move ${totals.slowest} ms; ${Date.now() - started} ms in all`);

// ---------- whole Donkey Master games of computer players ----------
let donkeyGames = 0;
for (let n = 0; n < GAMES; n++) {
  const seats = 2 + (n % 7);
  const engine = new DonkeyEngine({ roomId: `d${n}`, maxPlayers: seats });
  for (let seat = 0; seat < seats; seat++) engine.addPlayer(`b${seat}`, `bot${seat}`);
  engine.start();
  for (let step = 0; step < 5000 && engine.status !== 'finished'; step++) {
    if (engine.trickEnd) {
      engine.resolveTrick();
      continue;
    }
    const cardId = DonkeyBrain.choose(engine, engine.turn);
    assert.ok(engine.playable(engine.turn).includes(cardId), 'the computer player plays a card it may play');
    engine.play(engine.turn, cardId);
  }
  assert.equal(engine.status, 'finished', `a Donkey Master game for ${seats} came to an end`);
  assert.ok(engine.donkeyId || [...engine.players.values()].every((p) => p.out), 'it has a Donkey');
  donkeyGames++;
}
check(donkeyGames === GAMES, `${GAMES} Donkey Master games for 2 to 8 came to an end, every card one that may be played`);

console.log(`\nbots-brain: ${checks} checks passed`);
