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

// ---------- asking a neighbour for their cards: from here on the clock is the test's ----------
let clock = 1000000;
Date.now = () => clock;
const { REQUEST_MS, REQUEST_GAP_MS, REQUEST_SHOWN_MS } = Engine;
const ids = (player) => player.hand.map((c) => c.id);

// ---- only between tricks, once the A♠ has been led; accepted, the whole hand moves at once,
//      the giver is out (the Master, being first) and the turn moves on; rejected, nothing
//      moves; a player waits between requests; one holder left between tricks is the Donkey ----
{
  const game = table([['A♠', '2♥', '3♥'], ['5♠', '9♥', 'K♣'], ['7♠', '4♦', '8♦']], 100);
  assert.throws(() => game.requestCard('1', '0'), /Wait until the A♠ has been led/);
  assert.equal(game.stateFor('1').canRequest, false);
  game.play('0', 'A♠');
  assert.throws(() => game.requestCard('2', '1'), /Ask between tricks/);
  game.play('1', '5♠');
  game.play('2', '7♠');
  assert.throws(() => game.requestCard('2', '1'), /Ask between tricks/); // the trick still lies there
  game.resolveTrick();
  assert.equal(game.turn, '0');
  assert.deepEqual(game.neighbours('0'), ['1', '2']);
  assert.equal(game.stateFor('1').canRequest, true);
  const start = clock;
  assert.deepEqual(game.requestCard('1', '0'), { id: 'r1', from: '1', to: '0', status: 'pending', at: start, until: start + REQUEST_MS, moved: 0 });
  assert.throws(() => game.requestCard('1', '2'), /Wait for the answer to your request/);
  assert.throws(() => game.answerRequest('2', 'r1', true), /no such request for you/);
  assert.deepEqual(game.stateFor('2').requests, [{ id: 'r1', from: '1', to: '0', status: 'pending', expiresIn: REQUEST_MS, moved: 0 }]);

  game.answerRequest('0', 'r1', true);
  assert.deepEqual(ids(game.players.get('1')), ['2♥', '3♥', '9♥', 'K♣']); // all of them, in hand order
  assert.deepEqual(game.players.get('0').hand, []);
  assert.equal(game.players.get('0').out, true);
  assert.equal(game.players.get('0').place, 1);
  assert.equal(game.masterId, '0');
  assert.equal(game.turn, '1'); // 0 was to lead: the next one in the game leads
  assert.equal(game.leader, '1');
  assert.equal(game.status, 'playing');
  assert.deepEqual(game.stateFor('2').requests, [{ id: 'r1', from: '1', to: '0', status: 'accepted', expiresIn: 0, moved: 2 }]);
  assert.deepEqual(game.neighbours('1'), ['2']); // two left: the same player on both sides
  assert.deepEqual(game.neighbours('0'), []);
  assert.deepEqual(game.stateFor('0').neighbours, []);
  assert.throws(() => game.requestCard('0', '1'), /out of this game/);
  assert.throws(() => game.requestCard('1', '2'), new RegExp(`Wait ${REQUEST_GAP_MS / 1000} s before asking again`));
  assert.equal(game.stateFor('1').requestWait, REQUEST_GAP_MS);

  // The answer stays on show for a while, and the table's clock knows when it goes
  assert.deepEqual(game.nextDeadline(), { at: start + REQUEST_SHOWN_MS, what: 'requests' });
  clock = start + REQUEST_SHOWN_MS;
  assert.equal(game.settleRequests(), true);
  assert.deepEqual(game.requests, []);
  assert.equal(game.settleRequests(), false);
  assert.deepEqual(game.nextDeadline(), { at: game.turnDeadline, what: 'turn' });
  clock = start + REQUEST_GAP_MS - 1;
  assert.throws(() => game.requestCard('1', '2'), /Wait 1 s before asking again/);
  clock = start + REQUEST_GAP_MS;

  game.requestCard('1', '2');
  game.answerRequest('2', 'r2', false);
  assert.equal(game.requests[0].status, 'rejected');
  assert.deepEqual(ids(game.players.get('2')), ['4♦', '8♦']);
  assert.equal(game.players.get('1').hand.length, 4);

  // 2 asks 1, and 1 accepts: 2 holds every card left and is the Donkey; the Master wins
  game.requestCard('2', '1');
  game.answerRequest('1', 'r3', true);
  assert.equal(game.status, 'finished');
  assert.equal(game.endedBy, 'play');
  assert.equal(game.donkeyId, '2');
  assert.deepEqual(ids(game.players.get('2')), ['2♥', '3♥', '9♥', 'K♣', '4♦', '8♦']);
  assert.deepEqual(game.results.map((r) => [r.id, r.place, r.donkey, r.coins]), [
    ['0', 1, false, 100], ['1', 2, false, 0], ['2', 3, true, -100],
  ]);
  assert.deepEqual(game.settlement(), { 0: 200, 1: 100 });
  assert.equal(game.nextDeadline(), null);
  assert.equal(game.stateFor('1').canRequest, false);
}

// ---- four players: only the players next to you; requests both ways; an accept waits while
//      the giver's card lies in the trick; accepted in the middle of a trick, the cards move at
//      once and the trick goes on; the giver's own request ends with them ----
{
  const game = table([['A♠', '2♥', '3♣'], ['5♠', '9♥', 'K♣', '4♣'], ['7♠', '4♦', '8♦'], ['6♠', '10♥', 'Q♦']]);
  play(game, '0', 'A♠'); play(game, '1', '5♠'); play(game, '2', '7♠'); play(game, '3', '6♠');
  assert.equal(game.turn, '0');
  assert.deepEqual(game.neighbours('0'), ['1', '3']);
  assert.throws(() => game.requestCard('0', '2'), /only the players next to you/);
  game.requestCard('1', '0'); // r1
  game.requestCard('2', '3'); // r2
  game.requestCard('3', '2'); // r3: the other way round
  game.play('0', '2♥');
  assert.throws(() => game.requestCard('0', '1'), /Ask between tricks/);
  assert.equal(game.stateFor('0').canRequest, false);
  assert.throws(() => game.answerRequest('0', 'r1', true), /Wait until this trick is over/);
  assert.equal(game.requests[0].status, 'pending');
  game.play('1', '9♥');
  assert.equal(game.turn, '2');

  game.answerRequest('3', 'r2', true); // 3 has not played to this trick: the cards move now
  assert.deepEqual(ids(game.players.get('2')), ['10♥', '4♦', '8♦', 'Q♦']);
  assert.equal(game.players.get('3').place, 1);
  assert.equal(game.requests[2].status, 'cancelled'); // 3 is out: their own request is over
  assert.equal(game.turn, '2');
  assert.deepEqual(game.playable('2'), ['10♥']); // now they can follow suit
  assert.equal(game.play('2', '10♥').trickOver, true); // 3 is out: nobody else is to play
  assert.deepEqual(game.trickEnd, { outcome: 'discard', by: '2', cutBy: null, highest: '2' });
  assert.throws(() => game.answerRequest('0', 'r1', true), /Wait until this trick is over/);
  game.resolveTrick();
  assert.equal(game.turn, '2');

  game.answerRequest('0', 'r1', true); // the trick is over: now it can be accepted
  assert.deepEqual(ids(game.players.get('1')), ['3♣', '4♣', 'K♣']);
  assert.equal(game.players.get('0').place, 2);
  assert.equal(game.turn, '2');
  assert.deepEqual(game.neighbours('1'), ['2']);

  clock += REQUEST_GAP_MS;
  game.requestCard('1', '2');
  game.answerRequest('2', 'r4', true); // 2 was to lead, and gives everything away
  assert.equal(game.status, 'finished');
  assert.equal(game.donkeyId, '1');
  assert.deepEqual(game.results.map((r) => [r.id, r.place]), [['3', 1], ['0', 2], ['2', 3], ['1', 4]]);
}

// ---- the giver on turn in the middle of a trick: the turn moves on, and when nobody else is
//      to play the trick is over ----
{
  const game = table([['A♠', '2♥', '5♥'], ['5♠', '9♥', 'K♣'], ['7♠', '4♦', '8♦', '10♥'], ['6♠', 'J♥', 'Q♦']]);
  play(game, '0', 'A♠'); play(game, '1', '5♠'); play(game, '2', '7♠'); play(game, '3', '6♠');
  game.requestCard('1', '2');
  game.play('0', '2♥');
  game.play('1', '9♥');
  assert.equal(game.turn, '2');
  game.answerRequest('2', 'r1', true);
  assert.deepEqual(ids(game.players.get('1')), ['10♥', 'K♣', '4♦', '8♦']);
  assert.equal(game.turn, '3');
  assert.equal(game.play('3', 'J♥').trickOver, true);
  game.resolveTrick();
  assert.equal(game.turn, '3'); // the jack was highest
}
{
  const game = table([['A♠', '2♥', '3♥'], ['5♠', '9♥', 'K♣'], ['7♠', '4♦', '8♦']]);
  play(game, '0', 'A♠'); play(game, '1', '5♠'); play(game, '2', '7♠');
  game.requestCard('1', '2');
  game.play('0', '2♥');
  game.play('1', '9♥');
  game.answerRequest('2', 'r1', true); // the last to play gives their cards away
  assert.deepEqual(game.trickEnd, { outcome: 'discard', by: '1', cutBy: null, highest: '1' });
  assert.equal(game.resolveTrick(), false);
  assert.equal(game.turn, '1');
  assert.deepEqual(ids(game.players.get('1')), ['K♣', '4♦', '8♦']);
}

// ---- a request ends when it can no longer be answered: the asker played their last card;
//      a player gets up ----
{
  const game = table([['A♠', '2♥', '3♥'], ['5♠', '9♥'], ['7♠', '4♦', '8♦']]);
  play(game, '0', 'A♠'); play(game, '1', '5♠'); play(game, '2', '7♠');
  game.requestCard('1', '2'); // 1 has one card left
  game.play('0', '2♥');
  game.play('1', '9♥'); // their last: they cannot take cards now
  assert.equal(game.requests[0].status, 'cancelled');
  assert.throws(() => game.answerRequest('2', 'r1', true), /This request is over/);
  game.play('2', '4♦'); // a cut: 1 played the highest heart and picks the trick up
  game.resolveTrick();
  assert.equal(game.players.get('1').hand.length, 3);
  assert.equal(game.players.get('1').out, false);
}
{
  const game = table([['A♠', '2♥', '3♥'], ['5♠', '9♥', 'K♣'], ['7♠', '4♦', '8♦'], ['6♠', 'J♥', 'Q♦']]);
  play(game, '0', 'A♠'); play(game, '1', '5♠'); play(game, '2', '7♠'); play(game, '3', '6♠');
  game.requestCard('1', '0');
  game.requestCard('3', '0');
  game.removePlayer('0');
  assert.deepEqual(game.requests.map((r) => r.status), ['cancelled', 'cancelled']);
  assert.equal(game.turn, '1'); // 0 was to lead
  assert.deepEqual(game.neighbours('1'), ['2', '3']);
}

// ---- unanswered, a request runs out; kept and brought back, it is still there; after a
//      restart the time to answer starts again ----
{
  const game = table([['A♠', '2♥', '3♥'], ['5♠', '9♥', 'K♣'], ['7♠', '4♦', '8♦']]);
  play(game, '0', 'A♠'); play(game, '1', '5♠'); play(game, '2', '7♠');
  const start = clock;
  game.requestCard('1', '2');
  assert.deepEqual(game.nextDeadline(), { at: start + REQUEST_MS, what: 'requests' });
  const copy = Engine.fromJSON(JSON.parse(JSON.stringify(game.serialize())));
  for (const id of ['0', '1', '2']) assert.deepEqual(copy.stateFor(id), game.stateFor(id));
  assert.throws(() => copy.requestCard('1', '0'), /Wait for the answer/);
  copy.requestCard('0', '2');
  assert.equal(copy.requests[1].id, 'r2');
  clock = start + 3000;
  copy.restartClock();
  assert.equal(copy.requests[0].until, clock + REQUEST_MS);

  clock = start + REQUEST_MS;
  assert.throws(() => game.answerRequest('2', 'r1', true), /This request is over/);
  assert.equal(game.requests[0].status, 'pending'); // a refused answer changes nothing
  assert.equal(game.settleRequests(), true);
  assert.equal(game.stateFor('0').requests[0].status, 'expired');
  clock += REQUEST_SHOWN_MS;
  assert.equal(game.settleRequests(), true);
  assert.equal(game.requests.length, 0);
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

// The players next to `id`, worked out here on its own to check the engine by
function besides(game, id) {
  const seated = game.seated();
  const at = seated.findIndex((p) => p.id === id);
  if (game.status !== 'playing' || at < 0 || seated[at].left || seated[at].out) return [];
  const found = [];
  for (const step of [1, -1]) {
    for (let k = 1; k < seated.length; k++) {
      const p = seated[(at + step * k + seated.length * k) % seated.length];
      if (p.left || p.out) continue;
      if (!found.includes(p.id)) found.push(p.id);
      break;
    }
  }
  return found;
}

// A random player asks a random player (mostly one next to them): sent exactly when the
// rules allow it
function randomRequest(game) {
  const inGame = game.seated().filter((p) => game.inPlay(p));
  const from = random() < 0.85 && inGame.length ? pick(inGame) : pick(game.seated());
  const near = besides(game, from.id);
  const to = near.length && random() < 0.7 ? game.players.get(pick(near)) : pick(game.seated());
  assert.deepEqual(game.neighbours(from.id), near);
  const last = game.requestedAt[from.id];
  const allowed = game.status === 'playing' && !from.left && !from.out && !game.mustLead
    && game.trick.length === 0 && !game.trickEnd
    && !game.requests.some((r) => r.from === from.id && r.status === 'pending')
    && (last === undefined || clock - last >= REQUEST_GAP_MS)
    && near.includes(to.id);
  let request = null;
  try {
    request = game.requestCard(from.id, to.id);
  } catch (error) {
    assert.ok(!allowed, `a request the rules allow was refused: ${error.message}`);
    return;
  }
  assert.ok(allowed, 'a request the rules do not allow was sent');
  assert.ok(from.hand.length > 0 && to.hand.length > 0, 'between tricks everyone in the game holds cards');
  assert.equal(request.status, 'pending');
}

// A random open request is answered, yes or no: taken exactly when the rules allow it, and
// accepted, the giver's whole hand goes over at once
function randomAnswer(game) {
  const open = game.requests.filter((r) => r.status === 'pending');
  if (open.length === 0) return null;
  const request = pick(open);
  const accept = random() < 0.6;
  const giver = game.players.get(request.to);
  const taker = game.players.get(request.from);
  const had = { giver: giver.hand.length, taker: taker.hand.length };
  const waits = accept && (Boolean(game.trickEnd) || game.trick.some((p) => p.playerId === giver.id));
  try {
    game.answerRequest(request.to, request.id, accept);
  } catch (error) {
    assert.ok(waits, `an answer the rules allow was refused: ${error.message}`);
    assert.equal(request.status, 'pending');
    return null;
  }
  assert.ok(!waits, 'an accept went through while the giver\'s card lay in the trick');
  if (!accept) {
    assert.equal(request.status, 'rejected');
    assert.equal(giver.hand.length, had.giver);
    return 'rejected';
  }
  assert.equal(request.status, 'accepted');
  assert.equal(request.moved, had.giver);
  assert.equal(giver.hand.length, 0);
  assert.ok(giver.out && giver.place > 0, 'the giver is out at once, with a place');
  assert.equal(taker.hand.length, had.taker + had.giver, 'the whole hand went over');
  return 'accepted';
}

const GAMES = 6000;
let longest = 0;
let leftGames = 0;
const asked = { pending: 0, accepted: 0, rejected: 0, expired: 0, cancelled: 0, endedByOne: 0 };
for (let g = 0; g < GAMES; g++) {
  const n = 2 + (g % 7);
  const stake = 100;
  const game = new Engine({ roomId: `r${g}`, maxPlayers: n, stake });
  for (let i = 0; i < n; i++) game.addPlayer(String(i), `P${i}`);
  game.start();
  assert.equal(counted(game), 52);
  const leaving = g % 5 === 0; // some games have players getting up
  const seen = new Map(); // request id -> the last status seen
  let steps = 0;
  while (game.status === 'playing') {
    steps++;
    assert.ok(steps < 20000, `game ${g} does not end`);
    // Time passes; what has run out is settled, as the table's timer does
    clock += Math.floor(random() * 1500);
    if (game.requests.some((r) => r.until <= clock)) assert.equal(game.settleRequests(), true);
    const action = random();
    if (leaving && action < 0.01) {
      const stillIn = game.seated().filter((p) => game.inPlay(p));
      game.removePlayer(pick(stillIn).id);
    } else if (action < 0.1) {
      randomRequest(game);
    } else if (action < 0.18) {
      if (randomAnswer(game) === 'accepted' && game.status === 'finished') asked.endedByOne++;
    } else if (game.trickEnd) {
      game.resolveTrick();
    } else if (action < 0.27) {
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
    // An open request can always still be answered, and a player has one open at most
    const open = game.requests.filter((r) => r.status === 'pending');
    for (const r of open) {
      const from = game.players.get(r.from);
      const to = game.players.get(r.to);
      assert.ok(game.status === 'playing' && game.inPlay(from) && game.inPlay(to) && from.hand.length > 0 && to.hand.length > 0,
        `an open request that cannot be answered in game ${g}`);
    }
    assert.equal(new Set(open.map((r) => r.from)).size, open.length, 'one open request a player');
    if (game.requests.length > 0 && game.status === 'playing') {
      assert.ok(game.nextDeadline().at <= Math.min(...game.requests.map((r) => r.until)), 'the timer comes for the requests');
    }
    for (const r of game.requests) seen.set(r.id, r.status);
  }
  for (const status of seen.values()) asked[status]++;
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
assert.equal(asked.pending, 0, 'no request is left open when a game ends');
for (const outcome of ['accepted', 'rejected', 'expired', 'cancelled', 'endedByOne']) {
  assert.ok(asked[outcome] > 0, `the random games had no ${outcome} requests`);
}

console.log(`donkey-engine: all checks passed (${GAMES} random games, longest ${longest} steps, ${leftGames} with players leaving; `
  + `requests: ${asked.accepted} accepted, ${asked.rejected} rejected, ${asked.expired} ran out, ${asked.cancelled} cancelled, `
  + `${asked.endedByOne} games ended by one)`);
