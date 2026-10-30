const assert = require('node:assert/strict');
const Engine = require('../src/game/GameEngine');

function table(scores = [130, 144, 240], type = 'close_joker') {
  const game = new Engine('rejoin-test', type, scores.length);
  game.stake = 1000;
  scores.forEach((_, i) => game.addPlayer(String(i), `Player ${i}`));
  scores.forEach((score, i) => {
    Object.assign(game.players.get(String(i)), { totalScore: score, status: 'dropped', roundScore: 0 });
  });
  game.endRound('0', 'declare');
  return game;
}

const game = table();
assert.deepEqual(game.rejoinOffer('2'), { fee: 500, score: 145 });
assert.equal(game.getGameState('0').rejoin, null);
assert.deepEqual(game.getGameState('2').rejoin, { fee: 500, score: 145 });
const history = JSON.stringify(game.scoreHistory[0]);
assert.deepEqual(game.rejoin('2'), { fee: 500, score: 145 });
assert.equal(game.players.get('2').eliminated, false);
assert.equal(game.getGameState('2').pot, 3500);
assert.equal(JSON.stringify(game.scoreHistory[0]), history);
assert.throws(() => game.rejoin('2'));
const restored = Engine.fromJSON(JSON.parse(JSON.stringify(game.serialize())));
assert.equal(restored.players.get('2').totalScore, 145);
assert.equal(restored.getGameState('2').pot, 3500);
restored.startNextRound();
assert.equal(restored.players.get('2').hand.length, 13);
assert.equal(restored.players.get('2').status, 'active');
assert.equal(restored.rejoinOffer('2'), null);

const last = table([130, 240]);
assert.equal(last.status, 'round_over');
assert.equal(last.lastResult.matchOver, false);
assert.deepEqual(last.rejoinOffer('1'), { fee: 500, score: 131 });
assert.equal(last.startNextRound().matchOver, true);
assert.equal(last.winner, '0');
assert.equal(last.status, 'finished');

const continues = table([130, 240]);
continues.rejoin('1');
assert.equal(continues.startNextRound(), null);
assert.equal(continues.status, 'playing');

assert.equal(table([239, 240]).status, 'finished');
assert.equal(table([130, 144, 239]).rejoinOffer('2'), null);
const left = table();
left.players.get('2').left = true;
assert.equal(left.rejoinOffer('2'), null);
const expired = table();
expired.nextRoundAt = Date.now() - 1;
assert.throws(() => expired.rejoin('2'));
assert.equal(table([10, 20, 240], 'pool').rejoinOffer('2'), null);
const free = table();
free.stake = 0;
assert.equal(free.rejoin('2').fee, 0);
const sequential = table([130, 144, 240, 250]);
sequential.rejoin('2');
assert.equal(sequential.rejoinOffer('3').score, 146);
console.log('PASS: 240 threshold, 50% entry, highest+1, duplicates, history, pot, restore, next deal, expiry, final-player window, free tables and other modes');
