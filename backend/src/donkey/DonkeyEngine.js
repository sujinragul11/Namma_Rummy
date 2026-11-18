// Donkey Master: the card game, one table of it. Pure rules, no sockets and no database:
// DonkeyManager (socket/DonkeyManager.js) seats the players, runs the clocks, keeps the
// table in the database and moves the coins.
//
// The game, as played in South India (Kazhuthai) and elsewhere (Bhabhi, Getaway):
// - One pack of 52 cards, no jokers, aces high, dealt out completely among 2 to 8 players.
// - Whoever holds the ace of spades leads it to the first trick.
// - Each player in turn, clockwise, plays one card and must follow the suit led if they can.
// - A player who cannot follow plays any other card: a cut. The trick stops there, and the
//   player who played the highest card of the suit led picks up every card of the trick and
//   leads the next one.
// - When everyone followed suit, the trick's cards go out of the game, and the player who
//   played the highest card leads next (or, if their hand is now empty, the next player who
//   still has cards).
// - A player whose hand is empty when a trick is over is out and safe. The first one out is
//   the Master. The last player still holding cards is the Donkey. Should the last players
//   all run out in the same trick, the one who played its highest card, who would have had to
//   lead the next one, is the Donkey.
// - A player who gets up during the game while still holding cards loses, like the Donkey.
//   Their cards leave the game with them.
// - Between tricks a player may ask the player next to them, on either side, for their cards.
//   If that player accepts, their whole hand goes to the one who asked, and they are out at
//   once (the Master, if nobody is out yet). An unanswered request runs out after
//   REQUEST_MS, and a player asks at most once every REQUEST_GAP_MS.
//
// Coins (see settlement): everyone pays the table's entry on sitting down. At the end the
// Donkey, and everyone who left while holding cards, lose their entry, and it all goes to the
// Master; everyone else gets their own entry back.

const SUITS = ['♠', '♥', '♣', '♦']; // the order a hand is sorted in: the colours alternate
const VALUES = ['2', '3', '4', '5', '6', '7', '8', '9', '10', 'J', 'Q', 'K', 'A'];
const RANK = Object.fromEntries(VALUES.map((value, index) => [value, index + 2]));
const FIRST_CARD = 'A♠';
const MIN_PLAYERS = 2;
const MAX_PLAYERS = 8;

const seconds = (name, fallback) => {
  const value = parseFloat(process.env[name]);
  return (Number.isFinite(value) && value >= 0 ? value : fallback) * 1000;
};

// A turn. A player who missed MISSES_BEFORE_AWAY turns in a row, or has lost the connection,
// gets AWAY_MS instead: the table does not wait long for someone who is not there.
const TURN_MS = seconds('DONKEY_TURN_SECONDS', 15);
const AWAY_MS = seconds('DONKEY_AWAY_SECONDS', 3);
const MISSES_BEFORE_AWAY = 3;
// A finished trick stays on the table this long, so everyone sees the last card and who
// takes it, before it goes
const TRICK_PAUSE_MS = seconds('DONKEY_TRICK_PAUSE_SECONDS', 1.2);
// The first turn also waits for the cards to be dealt out on the screens
const DEAL_MS = seconds('DONKEY_DEAL_SECONDS', 2.5);
// A request for a neighbour's cards: the time they have to answer it, the time a player waits
// between two requests of their own (counted from sending), and how long an answered, run out
// or cancelled request stays in the state for everyone to see
const REQUEST_MS = seconds('DONKEY_REQUEST_SECONDS', 10);
const REQUEST_GAP_MS = seconds('DONKEY_REQUEST_GAP_SECONDS', 10);
const REQUEST_SHOWN_MS = 4000;

const rankOf = (card) => RANK[card.value];
const byHandOrder = (a, b) => SUITS.indexOf(a.suit) - SUITS.indexOf(b.suit) || rankOf(a) - rankOf(b);

class DonkeyEngine {
  static newDeck() {
    const deck = [];
    for (const suit of SUITS) {
      for (const value of VALUES) deck.push({ id: `${value}${suit}`, suit, value });
    }
    return deck;
  }

  // Fisher-Yates with Math.random, like the rummy deck. Tests replace it to deal fixed hands.
  static shuffle(deck) {
    for (let i = deck.length - 1; i > 0; i--) {
      const j = Math.floor(Math.random() * (i + 1));
      [deck[i], deck[j]] = [deck[j], deck[i]];
    }
    return deck;
  }

  constructor({ roomId, roomCode = '', maxPlayers = 2, stake = 0, isPrivate = false }) {
    if (!Number.isInteger(maxPlayers) || maxPlayers < MIN_PLAYERS || maxPlayers > MAX_PLAYERS) {
      throw new Error(`A table has ${MIN_PLAYERS} to ${MAX_PLAYERS} players`);
    }
    this.roomId = roomId;
    this.roomCode = roomCode;
    this.maxPlayers = maxPlayers;
    this.stake = stake;
    this.isPrivate = isPrivate;
    this.hostId = null;
    this.status = 'waiting'; // 'playing', 'finished'
    // id -> { id, username, seat, hand, connected, left, away, missed, out, place, donkey }
    this.players = new Map();
    this.turn = null; // whose turn it is; null between tricks and when nobody can play
    this.turnDeadline = null;
    this.trickNo = 0;
    this.leader = null;
    this.leadSuit = null;
    this.trick = []; // [{ playerId, card }] in the order played
    this.trickEnd = null; // a finished trick still on the table: { outcome, by, cutBy, highest }
    this.resolveAt = null; // when it goes
    this.lastTrick = null;
    this.mustLead = null; // the card that has to be led (the ace of spades, first trick only)
    this.discarded = 0;
    this.nextPlace = 1;
    this.masterId = null;
    this.donkeyId = null;
    this.endedBy = null; // 'play' or 'leave'
    this.results = [];
    // Requests for a neighbour's cards: [{ id, from, to, status, at, until, moved }]. Status
    // 'pending' until answered ('accepted', 'rejected') or over ('expired', 'cancelled');
    // `until` is when a pending one runs out, or when a finished one stops being shown;
    // `moved` is how many cards an accepted one moved.
    this.requests = [];
    this.requestedAt = {}; // player id -> when they last asked
    this.nextRequestId = 1;
  }

  // ---------- seats ----------

  // Adds a player while the table waits; seats fill from 0 up. A player who is already
  // seated stays where they are.
  addPlayer(id, username) {
    id = String(id);
    const existing = this.players.get(id);
    if (existing && !existing.left) return existing;
    if (this.status !== 'waiting') throw new Error('This game has already started');
    if (this.players.size >= this.maxPlayers) throw new Error('This table is full');
    const taken = new Set([...this.players.values()].map((player) => player.seat));
    let seat = 0;
    while (taken.has(seat)) seat++;
    const player = {
      id, username, seat, hand: [], connected: true,
      left: false, away: false, missed: 0, out: false, place: 0, donkey: false
    };
    this.players.set(id, player);
    if (!this.hostId) this.hostId = id;
    return player;
  }

  isFull() {
    return this.players.size >= this.maxPlayers;
  }

  // The players in seat order, which is the order of play
  seated() {
    return [...this.players.values()].sort((a, b) => a.seat - b.seat);
  }

  // Still in the game: not gone, not out. (In the middle of a trick a player in play may hold
  // no cards: they played their last one, and are out once the trick is over, unless they
  // have to pick it up.)
  inPlay(player) {
    return Boolean(player) && !player.left && !player.out;
  }

  // Gets a player up from the table. Before the deal their seat is simply free again; during
  // the game a player still in play loses and their cards leave the game. Returns true when
  // that ended the game.
  removePlayer(id) {
    id = String(id);
    const player = this.players.get(id);
    if (!player || player.left) return false;

    if (this.status === 'waiting') {
      this.players.delete(id);
      if (this.hostId === id) {
        const next = this.seated()[0];
        this.hostId = next ? next.id : null;
      }
      return false;
    }

    const wasInPlay = this.inPlay(player);
    player.left = true;
    player.connected = false;
    if (this.status !== 'playing' || !wasInPlay) return false;

    this.discarded += player.hand.length;
    if (player.hand.some((card) => card.id === this.mustLead)) this.mustLead = null;
    player.hand = [];
    this.settleRequests(); // nobody asks them for cards any more, nor gives them any

    const remaining = this.seated().filter((other) => this.inPlay(other));
    if (remaining.length < 2) {
      this.finish('leave');
      return true;
    }
    if (this.trickEnd) {
      // The trick on the table is settled when its pause ends, but not in favour of someone
      // who has gone: the next highest card takes it, or it leaves the game
      if (this.trickEnd.by === id) {
        const taker = this.trickEnd.outcome === 'pickup' ? this.highestPlay((other) => other && !other.left) : null;
        if (!taker) this.trickEnd.outcome = 'discard';
        this.trickEnd.by = taker ? taker.playerId : null;
      }
      return false;
    }
    if (this.turn === id) {
      if (this.trick.length === 0) {
        this.setTurn(this.nextInPlay(id));
      } else {
        this.moveOn(id);
      }
    }
    return false;
  }

  setConnected(id, connected) {
    const player = this.players.get(String(id));
    if (!player || player.left) return;
    player.connected = connected;
    // Nobody waits long for a player who is not there
    if (!connected && this.turn === player.id && this.turnDeadline) {
      this.turnDeadline = Math.min(this.turnDeadline, Date.now() + AWAY_MS);
    }
  }

  // ---------- the game ----------

  start() {
    if (this.status !== 'waiting') throw new Error('This game has already started');
    const seated = this.seated();
    if (seated.length < MIN_PLAYERS) throw new Error('Wait for at least one more player');

    // Seats close up, so the order of play has no gaps
    seated.forEach((player, index) => { player.seat = index; });
    const deck = DonkeyEngine.shuffle(DonkeyEngine.newDeck());
    deck.forEach((card, index) => seated[index % seated.length].hand.push(card));
    for (const player of seated) player.hand.sort(byHandOrder);

    this.status = 'playing';
    this.trickNo = 1;
    const first = seated.find((player) => player.hand.some((card) => card.id === FIRST_CARD));
    this.mustLead = FIRST_CARD;
    this.setTurn(first.id, DEAL_MS);
    this.leader = first.id;
  }

  // The cards `id` may play now: none when it is not their turn.
  playable(id) {
    const player = this.players.get(String(id));
    if (!player || this.status !== 'playing' || this.turn !== player.id) return [];
    if (this.mustLead && this.trick.length === 0) {
      return player.hand.some((card) => card.id === this.mustLead) ? [this.mustLead] : player.hand.map((card) => card.id);
    }
    if (this.leadSuit) {
      const following = player.hand.filter((card) => card.suit === this.leadSuit);
      if (following.length > 0) return following.map((card) => card.id);
    }
    return player.hand.map((card) => card.id);
  }

  // Plays a card. `auto`: the server played it for a player whose time ran out. Returns
  // { trickOver } when that card finished the trick (it then lies on the table until
  // resolveTrick).
  play(id, cardId, { auto = false } = {}) {
    id = String(id);
    const player = this.players.get(id);
    if (!player || player.left) throw new Error('You are not playing at this table');
    if (this.status !== 'playing') throw new Error('The game is not being played');
    if (this.turn !== id) throw new Error('It is not your turn');
    const card = player.hand.find((held) => held.id === cardId);
    if (!card) throw new Error('You do not have that card');
    if (!this.playable(id).includes(cardId)) {
      if (this.mustLead && this.trick.length === 0) throw new Error(`Lead the ${this.mustLead} to start`);
      throw new Error(`Follow suit: play a ${this.leadSuit}`);
    }

    if (!auto) {
      player.missed = 0;
      player.away = false;
    }
    player.hand = player.hand.filter((held) => held !== card);
    if (this.trick.length === 0) {
      this.leader = id;
      this.leadSuit = card.suit;
      this.mustLead = null;
    }
    this.trick.push({ playerId: id, card });
    // With no cards left they can neither give their hand nor take someone else's
    if (player.hand.length === 0) this.settleRequests();

    if (card.suit !== this.leadSuit) {
      this.endTrick('pickup', id);
      return { trickOver: true };
    }
    return { trickOver: this.moveOn(id) };
  }

  // The turn passes from `id` to the next player in play who has not played to this trick.
  // When there is nobody left to play, everyone followed suit and the trick is over.
  moveOn(id) {
    const played = new Set(this.trick.map((play) => play.playerId));
    const next = this.nextInPlay(id, (player) => !played.has(player.id));
    if (next) {
      this.setTurn(next);
      return false;
    }
    this.endTrick('discard', null);
    return true;
  }

  // The first player clockwise after `id` who is in play (and passes `also`); null if none.
  nextInPlay(id, also = () => true) {
    const seated = this.seated();
    const from = this.players.has(id) ? seated.findIndex((player) => player.id === id) : -1;
    for (let step = 1; step <= seated.length; step++) {
      const player = seated[(from + step + seated.length) % seated.length];
      if (player.id !== id && this.inPlay(player) && also(player)) return player.id;
    }
    return null;
  }

  // The play with the highest card of the suit led, among the players `eligible` accepts
  highestPlay(eligible = () => true) {
    let best = null;
    for (const play of this.trick) {
      if (play.card.suit !== this.leadSuit || !eligible(this.players.get(play.playerId))) continue;
      if (!best || rankOf(play.card) > rankOf(best.card)) best = play;
    }
    return best;
  }

  endTrick(outcome, cutBy) {
    const highest = this.highestPlay();
    let by = highest ? highest.playerId : null;
    if (outcome === 'pickup') {
      // A player who has got up cannot take the trick: the next highest card does
      const taker = this.highestPlay((player) => player && !player.left);
      by = taker ? taker.playerId : null;
      if (!by) outcome = 'discard';
    }
    this.trickEnd = { outcome, by, cutBy: cutBy || null, highest: highest ? highest.playerId : null };
    this.turn = null;
    this.turnDeadline = null;
    this.resolveAt = Date.now() + TRICK_PAUSE_MS;
  }

  // The pause after a trick is over: its cards leave the game or go to the player who picks
  // them up, players with empty hands are out, and the next trick begins, or the game ends.
  // Returns true when the game is over.
  resolveTrick() {
    if (this.status !== 'playing' || !this.trickEnd) return false;
    const end = this.trickEnd;
    const plays = this.trick;

    const taker = end.outcome === 'pickup' ? this.players.get(end.by) : null;
    if (taker && !taker.left) {
      taker.hand.push(...plays.map((play) => play.card));
      taker.hand.sort(byHandOrder);
    } else {
      this.discarded += plays.length;
    }
    this.lastTrick = { ...end, no: this.trickNo, plays };
    this.trick = [];
    this.leadSuit = null;
    this.trickEnd = null;
    this.resolveAt = null;

    // Who emptied their hand in this trick, in the order they played
    const emptied = plays
      .map((play) => this.players.get(play.playerId))
      .filter((player) => this.inPlay(player) && player.hand.length === 0);
    const holders = this.seated().filter((player) => this.inPlay(player) && player.hand.length > 0);

    if (holders.length === 0) {
      // Everyone ran out together: who played the highest card would have had to lead. (If
      // they have got up from the table meanwhile, they already lost, and the rest are safe.)
      const highest = this.players.get(end.highest);
      const donkey = highest && !highest.left ? highest : null;
      for (const player of emptied) if (player !== donkey) this.placeOut(player);
      if (donkey) this.makeDonkey(donkey);
      this.finish('play');
      return true;
    }
    for (const player of emptied) this.placeOut(player);
    if (holders.length === 1) {
      this.makeDonkey(holders[0]);
      this.finish('play');
      return true;
    }

    this.trickNo += 1;
    let next = end.by;
    if (!next || !holders.some((player) => player.id === next)) {
      next = this.nextInPlay(end.by || end.highest || plays[plays.length - 1].playerId);
    }
    this.leader = next;
    this.setTurn(next);
    this.settleRequests(); // those now out can neither give nor take cards
    return false;
  }

  placeOut(player) {
    player.out = true;
    player.place = this.nextPlace++;
    if (player.place === 1) this.masterId = player.id;
  }

  makeDonkey(player) {
    player.donkey = true;
    player.out = true;
    player.place = this.nextPlace++;
    this.donkeyId = player.id;
  }

  // The turn's time ran out: the server plays for them. Leading, the lowest card; following,
  // the lowest of the suit; unable to follow, the highest card, to be rid of it.
  autoPlay() {
    const player = this.players.get(this.turn);
    if (!player) return { trickOver: false };
    const choices = this.playable(player.id).map((id) => player.hand.find((card) => card.id === id));
    const cutting = this.leadSuit && !choices.some((card) => card.suit === this.leadSuit);
    choices.sort((a, b) => rankOf(a) - rankOf(b) || SUITS.indexOf(a.suit) - SUITS.indexOf(b.suit));
    const card = cutting ? choices[choices.length - 1] : choices[0];
    player.missed += 1;
    const wentAway = !player.away && player.missed >= MISSES_BEFORE_AWAY;
    if (wentAway) player.away = true;
    return { ...this.play(player.id, card.id, { auto: true }), wentAway, playerId: player.id };
  }

  setTurn(id, extra = 0) {
    this.turn = id;
    const player = this.players.get(id);
    const quick = player && (player.away || !player.connected);
    this.turnDeadline = id ? Date.now() + extra + (quick ? AWAY_MS : TURN_MS) : null;
  }

  // After a restart of the server nobody has lost any time, to play or to answer a request
  restartClock() {
    if (this.status !== 'playing') return;
    if (this.trickEnd) this.resolveAt = Date.now() + TRICK_PAUSE_MS;
    else if (this.turn) this.setTurn(this.turn);
    for (const request of this.requests) {
      if (request.status === 'pending') request.until = Date.now() + REQUEST_MS;
    }
  }

  // The next thing the table waits for: { at, what: 'resolve' | 'turn' | 'requests' }, or
  // null. 'requests': a request runs out, or an answered one stops being shown (settleRequests).
  nextDeadline() {
    if (this.status !== 'playing') return null;
    let next = null;
    if (this.trickEnd) next = { at: this.resolveAt, what: 'resolve' };
    else if (this.turn) next = { at: this.turnDeadline, what: 'turn' };
    for (const request of this.requests) {
      if (!next || request.until < next.at) next = { at: request.until, what: 'requests' };
    }
    return next;
  }

  finish(endedBy) {
    this.status = 'finished';
    this.endedBy = endedBy;
    this.turn = null;
    this.turnDeadline = null;
    this.trickEnd = null;
    this.resolveAt = null;
    // Ended by the others getting up: whoever still holds cards is safe, after those out
    for (const player of this.seated()) {
      if (this.inPlay(player)) this.placeOut(player);
    }
    this.settleRequests(); // nothing is asked for any more
    const coins = this.settlement();
    this.results = this.seated()
      .map((player) => ({
        id: player.id,
        username: player.username,
        place: player.place,
        donkey: player.donkey,
        left: player.left && !player.place,
        coins: (coins[player.id] || 0) - this.stake
      }))
      .sort((a, b) => (a.place || 99) - (b.place || 99));
  }

  // What each player gets at the end, in coins (their own entry included): the losers get
  // nothing, the others their entry back, and the Master everything the losers paid in.
  // Without a Master (nobody got out before the others left) those who stayed share it,
  // the odd coins going to the earliest seats. With nobody who stayed, entries go back.
  settlement() {
    const payouts = {};
    if (!this.stake) return payouts;
    const seated = this.seated();
    const losers = seated.filter((player) => player.donkey || (player.left && !player.place));
    const winners = seated.filter((player) => !losers.includes(player));
    if (winners.length === 0) {
      for (const player of seated) payouts[player.id] = this.stake;
      return payouts;
    }
    for (const player of winners) payouts[player.id] = this.stake;
    const lost = losers.length * this.stake;
    const master = this.masterId && winners.find((player) => player.id === this.masterId);
    const sharing = master ? [master] : winners;
    const share = Math.floor(lost / sharing.length);
    sharing.forEach((player, index) => {
      payouts[player.id] += share + (index < lost - share * sharing.length ? 1 : 0);
    });
    return payouts;
  }

  pot() {
    return this.stake * this.players.size;
  }

  // ---------- asking a neighbour for their cards ----------

  // The nearest players in play on either side of `id`, clockwise first (one id when both
  // sides are the same player); [] when `id` is not in play
  neighbours(id) {
    id = String(id);
    if (this.status !== 'playing' || !this.inPlay(this.players.get(id))) return [];
    const seated = this.seated();
    const from = seated.findIndex((player) => player.id === id);
    const found = [];
    for (const direction of [1, -1]) {
      for (let step = 1; step < seated.length; step++) {
        const player = seated[(((from + direction * step) % seated.length) + seated.length) % seated.length];
        if (!this.inPlay(player)) continue;
        if (!found.includes(player.id)) found.push(player.id);
        break;
      }
    }
    return found;
  }

  // Requests are sent between tricks: once the ace of spades has been led, while no trick is
  // being played and none lies on the table
  betweenTricks() {
    return this.status === 'playing' && !this.mustLead && this.trick.length === 0 && !this.trickEnd;
  }

  // How long `id` still has to wait before asking again, in ms; 0 when they may ask
  requestWait(id, now = Date.now()) {
    const last = this.requestedAt[String(id)];
    return last === undefined ? 0 : Math.max(0, last + REQUEST_GAP_MS - now);
  }

  // `fromId` asks `toId`, a player next to them, for their cards: between tricks, one open
  // request at a time, and not again within REQUEST_GAP_MS of the last one. Returns the request.
  requestCard(fromId, toId, now = Date.now()) {
    fromId = String(fromId);
    toId = String(toId);
    const from = this.players.get(fromId);
    if (!from || from.left) throw new Error('You are not playing at this table');
    if (this.status !== 'playing') throw new Error('The game is not being played');
    if (from.out) throw new Error('You are out of this game');
    if (this.mustLead) throw new Error(`Wait until the ${this.mustLead} has been led`);
    if (!this.betweenTricks()) throw new Error('Ask between tricks');
    if (this.requests.some((request) => request.from === fromId && request.status === 'pending')) {
      throw new Error('Wait for the answer to your request');
    }
    const wait = this.requestWait(fromId, now);
    if (wait > 0) throw new Error(`Wait ${Math.ceil(wait / 1000)} s before asking again`);
    if (!this.neighbours(fromId).includes(toId)) throw new Error('You can ask only the players next to you');
    // Between tricks everyone in play holds cards; this is only to be sure
    if (from.hand.length === 0 || this.players.get(toId).hand.length === 0) throw new Error('There are no cards to move');

    const request = { id: `r${this.nextRequestId++}`, from: fromId, to: toId, status: 'pending', at: now, until: now + REQUEST_MS, moved: 0 };
    this.requests.push(request);
    this.requestedAt[fromId] = now;
    return request;
  }

  // `toId` answers a request for their cards. Rejected, nothing moves. Accepted, their whole
  // hand goes to the player who asked, and they are out at once (the Master, if nobody is out
  // yet); not while a card of theirs lies in the trick, though: then it waits until the trick
  // is over. Returns the request.
  answerRequest(toId, requestId, accept, now = Date.now()) {
    toId = String(toId);
    const request = this.requests.find((asked) => asked.id === String(requestId));
    if (!request || request.to !== toId) throw new Error('There is no such request for you');
    if (request.status !== 'pending' || now >= request.until) throw new Error('This request is over');
    if (!accept) {
      this.closeRequest(request, 'rejected', now);
      return request;
    }
    if (this.trickEnd || this.trick.some((play) => play.playerId === toId)) throw new Error('Wait until this trick is over');
    const giver = this.players.get(toId);
    const taker = this.players.get(request.from);
    if (!this.requestPossible(request)) {
      // settleRequests closes these as they happen; this is only to be sure
      this.closeRequest(request, 'cancelled', now);
      throw new Error(`${taker ? taker.username : 'That player'} cannot take your cards any more`);
    }

    request.moved = giver.hand.length;
    taker.hand.push(...giver.hand);
    taker.hand.sort(byHandOrder);
    giver.hand = [];
    this.closeRequest(request, 'accepted', now);
    this.placeOut(giver);
    if (this.turn === giver.id) {
      // Their turn passes on, as when a player gets up
      if (this.trick.length === 0) {
        this.leader = this.nextInPlay(giver.id);
        this.setTurn(this.leader);
      } else {
        this.moveOn(giver.id);
      }
    }
    // Between tricks the one player left holding cards is the Donkey. In the middle of a trick
    // that waits until the trick is over: a cut can still give someone cards again.
    if (this.trick.length === 0 && !this.trickEnd) {
      const holders = this.seated().filter((player) => this.inPlay(player) && player.hand.length > 0);
      if (holders.length === 1) {
        this.makeDonkey(holders[0]);
        this.finish('play');
        return request;
      }
    }
    this.settleRequests(now); // the giver's other requests, to and from them, are over
    return request;
  }

  // A pending request can still be answered: the game goes on, and both players are in it
  // with cards in their hands
  requestPossible(request) {
    const from = this.players.get(request.from);
    const to = this.players.get(request.to);
    return this.status === 'playing' && this.inPlay(from) && this.inPlay(to) && from.hand.length > 0 && to.hand.length > 0;
  }

  closeRequest(request, status, now = Date.now()) {
    request.status = status;
    request.until = now + REQUEST_SHOWN_MS;
  }

  // Pending requests run out at their time or end when they can no longer be answered, and
  // finished ones are dropped once they have been shown. Returns true when anything changed.
  settleRequests(now = Date.now()) {
    let changed = false;
    for (const request of this.requests) {
      if (request.status !== 'pending') continue;
      if (now >= request.until) {
        this.closeRequest(request, 'expired', now);
        changed = true;
      } else if (!this.requestPossible(request)) {
        this.closeRequest(request, 'cancelled', now);
        changed = true;
      }
    }
    const kept = this.requests.filter((request) => request.status === 'pending' || now < request.until);
    if (kept.length !== this.requests.length) {
      this.requests = kept;
      changed = true;
    }
    return changed;
  }

  // ---------- what a player sees ----------

  // One player's view: everybody's card count, only their own cards.
  stateFor(viewerId, avatarOf = () => 0) {
    viewerId = String(viewerId);
    const viewer = this.players.get(viewerId);
    const timeLeft = this.status === 'playing' && this.turn && this.turnDeadline
      ? Math.max(0, this.turnDeadline - Date.now()) : null;
    const plays = (trick) => trick.map((play) => ({ playerId: play.playerId, card: play.card }));
    return {
      roomId: this.roomId,
      roomCode: this.roomCode,
      private: this.isPrivate,
      hostId: this.hostId || '',
      maxPlayers: this.maxPlayers,
      stake: this.stake,
      pot: this.pot(),
      status: this.status,
      players: this.seated().map((player) => ({
        id: player.id,
        username: player.username,
        avatar: avatarOf(player.id) || 0,
        seat: player.seat,
        cards: player.hand.length,
        connected: player.connected,
        left: player.left,
        away: player.away,
        out: player.out,
        place: player.place,
        donkey: player.donkey
      })),
      hand: viewer ? viewer.hand.slice() : [],
      turn: this.turn || '',
      turnTimeLeft: timeLeft,
      turnSeconds: Math.round(TURN_MS / 1000),
      trickNo: this.trickNo,
      leader: this.leader || '',
      leadSuit: this.leadSuit || '',
      trick: plays(this.trick),
      trickEnd: this.trickEnd ? { ...this.trickEnd, by: this.trickEnd.by || '', cutBy: this.trickEnd.cutBy || '', highest: this.trickEnd.highest || '' } : {},
      lastTrick: this.lastTrick ? {
        ...this.lastTrick, by: this.lastTrick.by || '', cutBy: this.lastTrick.cutBy || '',
        highest: this.lastTrick.highest || '', plays: plays(this.lastTrick.plays)
      } : {},
      mustLead: this.turn === viewerId && this.trick.length === 0 && this.mustLead ? this.mustLead : '',
      playable: this.playable(viewerId),
      discarded: this.discarded,
      masterId: this.masterId || '',
      donkeyId: this.donkeyId || '',
      results: this.results,
      endedBy: this.endedBy || '',
      // Requests for cards, everyone's, for the whole table to see; expiresIn (ms) while pending
      requests: this.requests.map((request) => ({
        id: request.id,
        from: request.from,
        to: request.to,
        status: request.status,
        expiresIn: request.status === 'pending' ? Math.max(0, request.until - Date.now()) : 0,
        moved: request.moved
      })),
      neighbours: this.neighbours(viewerId),
      canRequest: this.betweenTricks() && this.inPlay(viewer) && viewer.hand.length > 0,
      requestWait: this.requestWait(viewerId),
      requestSeconds: Math.round(REQUEST_MS / 1000),
      requestGapSeconds: Math.round(REQUEST_GAP_MS / 1000)
    };
  }

  // ---------- keeping it ----------

  serialize() {
    const fields = { ...this };
    fields.players = [...this.players.values()];
    return JSON.parse(JSON.stringify(fields));
  }

  static fromJSON(data) {
    const engine = new DonkeyEngine({
      roomId: data.roomId, roomCode: data.roomCode, maxPlayers: data.maxPlayers,
      stake: data.stake, isPrivate: data.isPrivate
    });
    for (const [key, value] of Object.entries(data)) {
      if (key !== 'players') engine[key] = value;
    }
    engine.players = new Map(data.players.map((player) => [player.id, player]));
    return engine;
  }
}

DonkeyEngine.SUITS = SUITS;
DonkeyEngine.VALUES = VALUES;
DonkeyEngine.FIRST_CARD = FIRST_CARD;
DonkeyEngine.MIN_PLAYERS = MIN_PLAYERS;
DonkeyEngine.MAX_PLAYERS = MAX_PLAYERS;
DonkeyEngine.TURN_MS = TURN_MS;
DonkeyEngine.AWAY_MS = AWAY_MS;
DonkeyEngine.TRICK_PAUSE_MS = TRICK_PAUSE_MS;
DonkeyEngine.REQUEST_MS = REQUEST_MS;
DonkeyEngine.REQUEST_GAP_MS = REQUEST_GAP_MS;
DonkeyEngine.REQUEST_SHOWN_MS = REQUEST_SHOWN_MS;
DonkeyEngine.byHandOrder = byHandOrder;

module.exports = DonkeyEngine;
