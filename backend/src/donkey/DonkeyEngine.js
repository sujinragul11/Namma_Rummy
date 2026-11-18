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

  // After a restart of the server nobody has lost any time
  restartClock() {
    if (this.status !== 'playing') return;
    if (this.trickEnd) this.resolveAt = Date.now() + TRICK_PAUSE_MS;
    else if (this.turn) this.setTurn(this.turn);
  }

  // The next thing the table waits for: { at, what: 'resolve' | 'turn' }, or null
  nextDeadline() {
    if (this.status !== 'playing') return null;
    if (this.trickEnd) return { at: this.resolveAt, what: 'resolve' };
    if (this.turn) return { at: this.turnDeadline, what: 'turn' };
    return null;
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
      endedBy: this.endedBy || ''
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
DonkeyEngine.byHandOrder = byHandOrder;

module.exports = DonkeyEngine;
