// Donkey Master's rules: fixed hands for the cases that matter, then thousands of random games
// (random table sizes, random legal cards, players getting up) checked for what must always
// hold: no card made or lost, one Donkey, coins neither made nor lost.
//   node tests/donkey-engine.js
const assert = require('node:assert/strict');
const Engine = require('../src/donkey/DonkeyEngine');

const card = (id) => ({ id, suit: id.slice(-1), value: id.slice(0, -1) });

// A started table whose hands are exactly `hands` (card ids, one array per seat)
function table(hands, stake = 0) {
  const game = new Engine({ roomId: 'test', maxPlayers: hands.length, stake });
  hands.forEach((_, i) => game.addPlayer(String(i), `P${i}`));
  game.start();
  hands.forEach((ids, i) => {
    game.players.get(String(i)).hand = ids.map(card).sort(Engine.byHandOrder);
  });
  const first = hands.findIndex((ids) => ids.includes('A♠'));
  game.turn = String(first);
  game.leader = game.turn;
  return game;
}

const play = (game, id, cardId) => {
  const result = game.play(id, cardId);
  if (result.trickOver) game.resolveTrick();
  return result;
};

// ---- the first trick is the ace of spades; suit must be followed; all followed: discarded ----
{
  const game = table([['A♠', '2♥', '3♥'], ['5♠', '9♥', 'K♣'], ['7♠', '4♦', '8♦']]);
  assert.deepEqual(game.playable('0'), ['A♠']);
  assert.deepEqual(game.playable('1'), []);
  assert.throws(() => game.play('0', '2♥'), /Lead the A♠/);
  assert.throws(() => game.play('1', '5♠'), /not your turn/);
  game.play('0', 'A♠');
  assert.equal(game.stateFor('1').leadSuit, '♠');
  assert.deepEqual(game.playable('1'), ['5♠']);
  assert.throws(() => game.play('1', '9♥'), /Follow suit: play a ♠/);
  game.play('1', '5♠');
  assert.equal(game.play('2', '7♠').trickOver, true);
  assert.deepEqual(game.trickEnd, { outcome: 'discard', by: '0', cutBy: null, highest: '0' });
  assert.equal(game.turn, null); // nobody plays while the finished trick lies there
  assert.equal(game.stateFor('0').trick.length, 3);
  assert.equal(game.resolveTrick(), false);
  assert.equal(game.discarded, 3);
  assert.equal(game.turn, '0'); // the ace was highest, so it leads
  assert.equal(game.trickNo, 2);
  assert.equal(game.stateFor('2').lastTrick.plays.length, 3);
  assert.equal(game.stateFor('2').mustLead, '');
}

// ---- cuts: the highest card of the suit led takes the trick; cutting with the last card
//      gets a player out; the last one holding cards is the Donkey; coins ----
{
  const game = table([['A♠', '2♥', '3♦'], ['5♠', '9♥', 'K♣'], ['7♠', '4♦', '8♦']], 100);
  assert.equal(game.pot(), 300);
  play(game, '0', 'A♠'); play(game, '1', '5♠'); play(game, '2', '7♠');
  play(game, '0', '2♥');
  play(game, '1', '9♥');
  const cut = game.play('2', '4♦'); // no hearts: a cut
  assert.equal(cut.trickOver, true);
  assert.deepEqual(game.trickEnd, { outcome: 'pickup', by: '1', cutBy: '2', highest: '1' });
  game.resolveTrick();
  assert.deepEqual(game.players.get('1').hand.map((c) => c.id), ['9♥', '2♥', 'K♣', '4♦'].sort((a, b) => Engine.byHandOrder(card(a), card(b))));
  assert.equal(game.turn, '1');
  play(game, '1', 'K♣');
  play(game, '2', '8♦'); // cuts with the last card: out, and first out is the Master
  assert.equal(game.players.get('2').place, 1);
  assert.equal(game.masterId, '2');
  assert.equal(game.turn, '1'); // took the trick back, leads
  play(game, '1', '2♥');
  play(game, '0', '3♦'); // 0 cuts with its last card: out; 1 is left holding cards
  assert.equal(game.status, 'finished');
  assert.equal(game.endedBy, 'play');
  assert.equal(game.donkeyId, '1');
  assert.deepEqual(game.results.map((r) => [r.id, r.place, r.donkey, r.coins]), [
    ['2', 1, false, 100], ['0', 2, false, 0], ['1', 3, true, -100],
  ]);
  assert.deepEqual(game.settlement(), { 0: 100, 2: 200 });
}

// ---- the last two run out in the same trick: who played its highest card is the Donkey ----
{
  const game = table([['A♠', '2♥'], ['3♠', '5♥']], 50);
  play(game, '0', 'A♠'); play(game, '1', '3♠');
  play(game, '0', '2♥'); play(game, '1', '5♥');
  assert.equal(game.status, 'finished');
  assert.equal(game.donkeyId, '1');
  assert.equal(game.masterId, '0');
  assert.deepEqual(game.results.map((r) => r.coins), [50, -50]);
}

// ---- getting up: before the deal the seat is free and the host moves on; during the game
//      the player loses, and with one player left the game ends ----
{
  const game = new Engine({ roomId: 'w', maxPlayers: 4, stake: 100 });
  game.addPlayer('a', 'A'); game.addPlayer('b', 'B'); game.addPlayer('c', 'C');
  assert.equal(game.hostId, 'a');
  game.removePlayer('a');
  assert.equal(game.hostId, 'b');
  assert.equal(game.players.size, 2);
  assert.equal(game.addPlayer('d', 'D').seat, 0); // the free seat
  assert.throws(() => new Engine({ roomId: 'x', maxPlayers: 9 }), /2 to 8/);
  const two = new Engine({ roomId: 'y', maxPlayers: 2 });
  two.addPlayer('a', 'A');
  assert.throws(() => two.start(), /at least one more/);
  two.addPlayer('b', 'B');
  assert.throws(() => two.addPlayer('c', 'C'), /full/);
}
{
  const game = table([['A♠', '2♥'], ['3♠', '5♥']], 100);
  assert.equal(game.removePlayer('0'), true);
  assert.equal(game.status, 'finished');
  assert.equal(game.endedBy, 'leave');
  assert.deepEqual(game.results.map((r) => [r.id, r.left, r.coins]), [['1', false, 100], ['0', true, -100]]);
}

// ---- the player who would take a cut trick gets up during the pause: the next highest card
//      of the suit takes it; leaving on one's turn passes the turn on ----
{
  const game = table([['A♠', '2♥', '3♥'], ['5♠', '9♥', 'J♥'], ['7♠', '4♦', '8♦'], ['6♠', '10♥', 'Q♦']], 10);
  play(game, '0', 'A♠'); play(game, '1', '5♠'); play(game, '2', '7♠'); play(game, '3', '6♠');
  game.play('0', '2♥');
  game.play('1', '9♥');
  game.play('2', '4♦');
  assert.equal(game.trickEnd.by, '1');
  assert.equal(game.removePlayer('1'), false);
  assert.deepEqual(game.trickEnd, { outcome: 'pickup', by: '0', cutBy: '2', highest: '1' });
  game.resolveTrick();
  assert.equal(game.players.get('0').hand.length, 4); // 3♥ and the trick
  assert.equal(game.turn, '0');
  game.play('0', '3♥');
  assert.equal(game.turn, '2');
  game.removePlayer('2'); // on turn in the middle of a trick: the next player plays
  assert.equal(game.turn, '3');
  game.removePlayer('3'); // on turn: the trick goes on without them, nobody left to play
  assert.equal(game.status, 'finished');
  assert.equal(game.endedBy, 'leave');
  assert.deepEqual(game.settlement(), { 0: 40 }); // all three who left lose to the one who stayed
}

// ---- the clock: lowest card of the suit when following, highest when cutting; three missed
//      turns and the player is away ----
{
  const game = table([['A♠', '2♥', 'K♥', '3♦'], ['5♠', '9♥', 'J♥', '4♣'], ['7♠', '4♦', '8♦', 'A♦']]);
  const first = game.autoPlay();
  assert.equal(first.playerId, '0');
  assert.equal(game.trick[0].card.id, 'A♠');
  game.autoPlay(); game.autoPlay();
  game.resolveTrick();
  game.play('0', 'K♥');
  const following = game.autoPlay();
  assert.equal(game.trick[1].card.id, '9♥'); // lowest heart
  assert.equal(following.wentAway, false);
  const cutting = game.autoPlay(); // no hearts: the highest card goes
  assert.equal(game.trick[2].card.id, 'A♦');
  assert.equal(cutting.trickOver, true);
  assert.equal(game.players.get('2').missed, 2);
  game.resolveTrick();
  game.play('0', '2♥');
  game.play('1', 'J♥');
  assert.equal(game.autoPlay().wentAway, true); // the third in a row
  assert.equal(game.players.get('2').away, true);
}

// ---- kept and brought back: the same view ----
{
  const game = table([['A♠', '2♥', '3♦'], ['5♠', '9♥', 'K♣'], ['7♠', '4♦', '8♦']], 500);
  game.play('0', 'A♠');
  const copy = Engine.fromJSON(JSON.parse(JSON.stringify(game.serialize())));
  const strip = (state) => ({ ...state, turnTimeLeft: null });
  for (const id of ['0', '1', '2']) assert.deepEqual(strip(copy.stateFor(id)), strip(game.stateFor(id)));
  assert.equal(copy.stateFor('1').hand.length, 3);
  assert.equal(copy.stateFor('1').players[0].cards, 2);
  assert.equal(copy.stateFor('1').hand.some((c) => c.id === '2♥'), false); // only one's own cards
}

// ---- thousands of random games ----
let seed = 12345;
const random = () => {
  seed = (seed * 1103515245 + 12345) % 2147483648;
  return seed / 2147483648;
};
const pick = (list) => list[Math.floor(random() * list.length)];
Engine.shuffle = (deck) => {
  for (let i = deck.length - 1; i > 0; i--) {
    const j = Math.floor(random() * (i + 1));
    [deck[i], deck[j]] = [deck[j], deck[i]];
  }
  return deck;
};

const counted = (game) => [...game.players.values()].reduce((sum, p) => sum + p.hand.length, 0)
  + game.trick.length + game.discarded;
const GAMES = 6000;
let longest = 0;
let leftGames = 0;
for (let g = 0; g < GAMES; g++) {
  const n = 2 + (g % 7);
  const stake = 100;
  const game = new Engine({ roomId: `r${g}`, maxPlayers: n, stake });
  for (let i = 0; i < n; i++) game.addPlayer(String(i), `P${i}`);
  game.start();
  assert.equal(counted(game), 52);
  const leaving = g % 5 === 0; // some games have players getting up
  let steps = 0;
  while (game.status === 'playing') {
    steps++;
    assert.ok(steps < 20000, `game ${g} does not end`);
    if (leaving && random() < 0.01) {
      const stillIn = game.seated().filter((p) => game.inPlay(p));
      game.removePlayer(pick(stillIn).id);
    } else if (game.trickEnd) {
      game.resolveTrick();
    } else if (random() < 0.1) {
      game.autoPlay();
    } else {
      const choices = game.playable(game.turn);
      assert.ok(choices.length > 0, 'the player on turn always has a card to play');
      game.play(game.turn, pick(choices));
    }
    assert.equal(counted(game), 52, `cards made or lost in game ${g}`);
    if (game.status === 'playing' && !game.trickEnd) {
      assert.ok(game.inPlay(game.players.get(game.turn)), 'the turn is with a player in the game');
    }
  }
  longest = Math.max(longest, steps);
  const players = game.seated();
  const left = players.filter((p) => p.left && !p.place);
  if (left.length > 0) leftGames++;
  if (game.endedBy === 'play' && left.length === 0) {
    assert.equal(players.filter((p) => p.donkey).length, 1, `one Donkey in game ${g}`);
    assert.equal(game.donkeyId, players.find((p) => p.donkey).id);
    assert.equal(players.find((p) => p.donkey).place, n);
  }
  const places = players.filter((p) => p.place).map((p) => p.place).sort((a, b) => a - b);
  assert.deepEqual(places, places.map((_, i) => i + 1), `places 1..k in game ${g}`);
  assert.equal(players.filter((p) => !p.left && !p.place).length, 0, 'everyone who stayed is placed');
  const payouts = game.settlement();
  const paid = Object.values(payouts).reduce((sum, coins) => sum + coins, 0);
  assert.equal(paid, stake * n, `coins made or lost in game ${g}`);
  assert.equal(game.results.reduce((sum, r) => sum + r.coins, 0), 0);
  for (const r of game.results) {
    const loser = r.donkey || r.left;
    assert.equal(r.coins < 0, loser, `only losers lose in game ${g}`);
  }
  for (const p of players) game.stateFor(p.id); // every view can be made
}

console.log(`donkey-engine: all checks passed (${GAMES} random games, longest ${longest} steps, ${leftGames} with players leaving)`);
