const assert = require('node:assert/strict');
const Engine = require('../src/game/GameEngine');
const SocketManager = require('../src/socket/SocketManager');
const Coins = require('../src/models/Coins');

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

// The next deal, which player 0 wins while the players named go over 240
function outAgain(game, ...ids) {
  game.startNextRound();
  for (const player of game.players.values()) Object.assign(player, { status: 'dropped', roundScore: 0 });
  for (const id of ids) game.players.get(id).totalScore = 240;
  game.endRound('0', 'declare');
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

// One player left has won: the match ends at once and nobody can rejoin it
const last = table([130, 240]);
assert.equal(last.status, 'finished');
assert.equal(last.winner, '0');
assert.equal(last.lastResult.matchOver, true);
assert.equal(last.lastResult.matchWinner, '0');
assert.equal(last.rejoinOffer('1'), null);
assert.equal(last.getGameState('1').rejoin, null);
assert.throws(() => last.rejoin('1'));
const both = table([130, 240, 250]);
assert.equal(both.status, 'finished');
assert.equal(both.winner, '0');
assert.equal(both.rejoinOffer('1'), null);
assert.equal(both.rejoinOffer('2'), null);
// Leaving during the break can leave one player too, who then wins there and then
const deserted = table();
assert.ok(deserted.rejoinOffer('2'));
assert.equal(deserted.removePlayer('1').matchWinner, '0');
assert.equal(deserted.status, 'finished');
assert.equal(deserted.rejoinOffer('2'), null);
// A game an older server saved while it held the last player's win open for a rejoin
const saved = table([130, 240]).serialize();
Object.assign(saved, { status: 'round_over', winner: null, nextRoundAt: Date.now() + 10000,
  lastResult: { ...saved.lastResult, matchOver: false, matchWinner: null } });
const resumed = Engine.fromJSON(JSON.parse(JSON.stringify(saved)));
assert.equal(resumed.rejoinOffer('1'), null);
assert.equal(resumed.startNextRound().matchWinner, '0');
assert.equal(resumed.status, 'finished');
// A player who has lost the connection is still in the match
const away = table();
away.players.get('1').connected = false;
assert.ok(away.rejoinOffer('2'));

// Three rejoins a player, each game
const often = table([100, 130, 144, 240]);
for (let time = 1; time <= 3; time++) {
  assert.deepEqual(often.rejoin('3'), { fee: 500, score: 145 });
  outAgain(often, '3');
}
assert.equal(often.players.get('3').rejoins, 3);
assert.equal(often.status, 'round_over');
assert.equal(often.rejoinOffer('3'), null);
assert.equal(often.getGameState('3').rejoin, null);
assert.throws(() => often.rejoin('3'));
assert.equal(Engine.fromJSON(JSON.parse(JSON.stringify(often.serialize()))).rejoinOffer('3'), null);
assert.equal(often.getGameState('0').pot, 5500);
outAgain(often, '2'); // the others play on, and the limit is each player's own
assert.deepEqual(often.rejoinOffer('2'), { fee: 500, score: 131 });
assert.equal(often.rejoinOffer('3'), null);

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

// Through the table server: the count is kept on the live game, so a fourth rejoin is refused
(async () => {
  const manager = Object.create(SocketManager.prototype);
  Object.assign(manager, { rejoinWrites: new Map(), snapshots: true });
  manager.saveSnapshot = async () => {};
  manager.sendCoins = () => {};
  manager.afterMove = async () => {};
  const pay = Coins.rejoin;
  Coins.rejoin = async () => 0;
  try {
    const live = table([100, 130, 144, 240]);
    for (let time = 1; time <= 3; time++) {
      assert.equal((await manager.rejoinGame(live, '3', 145)).score, 145);
      outAgain(live, '3');
    }
    await assert.rejects(manager.rejoinGame(live, '3', 145), /cannot rejoin/);
    assert.equal(live.players.get('3').eliminated, true);
  } finally {
    Coins.rejoin = pay;
  }
  console.log('PASS: 240 threshold, 50% entry, highest+1, duplicates, history, pot, restore, next deal, expiry, ' +
    'no rejoin with one player left, older saved games, three rejoins a player, free tables and other modes');
})().catch(error => { console.error(error); process.exitCode = 1; });
