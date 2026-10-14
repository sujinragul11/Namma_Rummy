const DeckManager = require('./DeckManager');
const Validator = require('./Validator');

const CARDS_PER_PLAYER = 13;
const FIRST_DROP_POINTS = 20;
const MIDDLE_DROP_POINTS = 40;
const WRONG_DECLARATION_POINTS = 80;
const MAX_LOSS_POINTS = 80; // no hand and no penalty costs more
const MAX_MISSED_TURNS = 3; // consecutive timeouts before a player is dropped
const NEXT_ROUND_DELAY_MS = (parseFloat(process.env.NEXT_ROUND_SECONDS) || 12) * 1000;
// Deals Rummy: every player starts with this many chips for each deal to be played, the most
// a hand can cost (80), so nobody runs out before the last deal
const CHIPS_PER_DEAL = 80;
const TURN_TIMEOUT_MS = (parseInt(process.env.TURN_TIMEOUT_SECONDS, 10) || 30) * 1000;
// After a valid declaration: how long the others have to arrange their cards and hand them in
const ARRANGE_TIMEOUT_MS = (parseInt(process.env.ARRANGE_TIMEOUT_SECONDS, 10) || 15) * 1000;

// The kinds of game. With a pool limit, rounds follow one another and a player reaching the
// limit is out, until one is left; without one the game is a single round.
// A closed joker lies face down: a player gets to see it only once their own hand holds a
// pure sequence (the "first life").
// Deals Rummy is a fixed number of deals played for chips: the winner of a deal takes from
// each loser as many chips as that loser's points, and after the last deal the most chips
// win. Players level on chips then play one more deal between them.
const GAME_TYPES = {
  points: { poolLimit: null, closedJoker: false, deals: null },
  pool: { poolLimit: 101, closedJoker: false, deals: null },
  pool_201: { poolLimit: 201, closedJoker: false, deals: null },
  close_joker: { poolLimit: 240, closedJoker: true, deals: null },
  deals_2: { poolLimit: null, closedJoker: false, deals: 2 },
  deals_3: { poolLimit: null, closedJoker: false, deals: 3 }
};

class GameEngine {
  constructor(gameId, gameType = 'points', maxPlayers = 2, roomCode = null) {
    this.gameId = gameId;
    this.roomCode = roomCode;
    this.gameType = gameType; // a key of GAME_TYPES
    this.maxPlayers = maxPlayers;
    this.players = new Map(); // userId -> player object
    this.deckManager = new DeckManager();
    this.hostId = null;
    this.currentPlayer = null;
    this.turnPhase = 'draw'; // 'draw' then 'discard'; 'arrange' after a valid declaration
    this.turnDeadline = null; // epoch ms
    // A valid declaration does not end the round at once: the others first get a short time
    // to arrange their own cards. Until then this holds the declarer's id.
    this.declaredBy = null;
    this.submitted = []; // userIds who have handed in their arrangement since the declaration
    this.roundPlayers = []; // userIds dealt into the current round, in seat order
    this.nextRoundAt = null; // epoch ms, set between pool rounds
    this.status = 'waiting'; // 'waiting', 'playing', 'round_over', 'finished'
    this.winner = null;
    this.round = 0;
    this.lastResult = null;
    this.stake = 0; // coins each player pays to sit down; 0 is a free table
    // Points rummy for so many coins a point: each loser pays the winner points x pointValue,
    // out of the stake they put down (80 points' worth). 0 when the winner takes the stakes.
    this.pointValue = 0;
    // A private table is for the host's friends: it is never listed, and only someone with
    // the room code can sit down
    this.isPrivate = false;
    this.createdAt = new Date();
  }

  static isGameType(gameType) {
    return Object.hasOwn(GAME_TYPES, gameType);
  }

  get rules() {
    return GameEngine.isGameType(this.gameType) ? GAME_TYPES[this.gameType] : GAME_TYPES.points;
  }

  addPlayer(userId, username) {
    const existing = this.players.get(userId);
    if (existing) {
      if (existing.left) {
        throw new Error('You have left this game');
      }
      // Coming back after a reconnect or app restart keeps the same seat
      existing.connected = true;
      return existing;
    }

    if (this.status !== 'waiting') {
      throw new Error('Game has already started');
    }

    if (this.players.size >= this.maxPlayers) {
      throw new Error('Game is full');
    }

    this.players.set(userId, {
      id: userId,
      username,
      hand: [],
      groups: [], // the player's own arrangement: arrays of card ids
      connected: true,
      status: 'active', // 'active' or 'dropped', per round
      eliminated: false, // out for the rest of the match
      left: false,
      roundScore: 0,
      totalScore: 0,
      turnsTaken: 0,
      missedTurns: 0,
      lastDrawnId: null,
      drawnFromDiscard: false,
      seenJoker: false, // per round; matters only while the joker is closed
      chips: 0, // Deals Rummy only; given out when the first deal is dealt
      joinedAt: new Date()
    });

    if (!this.hostId) {
      this.hostId = userId;
    }

    // Start game if enough players
    if (this.players.size === this.maxPlayers) {
      this.startGame();
    }

    return this.players.get(userId);
  }

  // Returns the round result if leaving ended the round, otherwise null
  removePlayer(userId) {
    const player = this.players.get(userId);
    if (!player) return null;

    if (this.status === 'waiting') {
      this.players.delete(userId);
      if (this.hostId === userId) {
        this.hostId = this.players.size > 0 ? this.players.keys().next().value : null;
      }
      return null;
    }

    // Leaving a running game forfeits it
    player.connected = false;
    player.left = true;
    player.eliminated = true;

    if (this.status === 'playing' && this.declaredBy) {
      // The round is already decided. A declarer who leaves has still won it, and anyone
      // else's hand is counted as it lies, so leaving now is never cheaper than staying.
      if (!this.submitted.includes(userId)) this.submitted.push(userId);
      return this.endShowIfReady();
    }

    if (this.status === 'playing' && player.status === 'active') {
      player.status = 'dropped';
      player.roundScore = MIDDLE_DROP_POINTS;
      return this.afterPlayerOut(player);
    }

    if (this.status === 'round_over' && this.getContenders().length <= 1) {
      const lastContender = this.getContenders()[0];
      this.status = 'finished';
      this.winner = lastContender ? lastContender.id : null;
      this.nextRoundAt = null;
      this.lastResult = { ...this.lastResult, matchOver: true, matchWinner: this.winner };
      return this.lastResult;
    }

    return null;
  }

  startGame() {
    if (this.status !== 'waiting') {
      throw new Error('Game has already started');
    }

    if (this.players.size < 2) {
      throw new Error('Need at least 2 players to start');
    }

    const { deals } = this.rules;
    if (deals) {
      for (const player of this.players.values()) player.chips = CHIPS_PER_DEAL * deals;
    }

    this.startRound();
  }

  startNextRound() {
    if (this.status !== 'round_over') {
      throw new Error('Round is still in progress');
    }

    this.startRound();
  }

  startRound() {
    const contenders = this.getContenders();
    this.round += 1;
    this.status = 'playing';
    this.lastResult = null;
    this.nextRoundAt = null;
    this.declaredBy = null;
    this.submitted = [];
    this.roundPlayers = contenders.map(player => player.id);

    for (const player of this.players.values()) {
      player.hand = [];
      player.groups = [];
      player.roundScore = 0;
      player.turnsTaken = 0;
      player.missedTurns = 0;
      player.lastDrawnId = null;
      player.drawnFromDiscard = false;
      player.seenJoker = !this.rules.closedJoker;
    }

    // Deal cards: one deck is enough for two players, more players need two
    this.deckManager = new DeckManager(contenders.length > 2 ? 2 : 1);
    const dealResult = this.deckManager.dealCards(contenders.length, CARDS_PER_PLAYER);

    contenders.forEach((player, index) => {
      player.hand = dealResult.hands[index];
      player.status = 'active';
    });

    // The opening seat moves round the table each round
    this.currentPlayer = this.roundPlayers[(this.round - 1) % this.roundPlayers.length];
    this.beginTurn();
  }

  beginTurn() {
    this.turnPhase = 'draw';
    this.turnDeadline = Date.now() + TURN_TIMEOUT_MS;
  }

  getContenders() {
    return Array.from(this.players.values()).filter(player => !player.eliminated);
  }

  getActivePlayers() {
    return this.roundPlayers
      .map(id => this.players.get(id))
      .filter(player => player.status === 'active');
  }

  getGameState(userId) {
    const me = this.players.get(userId);
    // A closed joker is never sent to a player who has not earned the sight of it.
    // Once somebody has declared it lies open for everyone, next to the hands it scores.
    const jokerHidden =
      this.rules.closedJoker && this.status === 'playing' && !this.declaredBy && !(me && me.seenJoker);
    const joker = jokerHidden ? null : this.deckManager.joker;
    const gameState = {
      gameId: this.gameId,
      roomCode: this.roomCode,
      gameType: this.gameType,
      maxPlayers: this.maxPlayers,
      status: this.status,
      hostId: this.hostId,
      currentPlayer: this.currentPlayer,
      turnPhase: this.turnPhase,
      // Set while the others arrange their cards after this player's valid declaration;
      // turnTimeLeft is then the time they have left for it
      declaredBy: this.declaredBy,
      // Durations rather than timestamps, so client clocks don't have to match the server's
      turnTimeLeft: this.turnDeadline ? Math.max(0, this.turnDeadline - Date.now()) : null,
      nextRoundIn: this.nextRoundAt ? Math.max(0, this.nextRoundAt - Date.now()) : null,
      players: [],
      discardTop: this.deckManager.getTopDiscard(),
      deckCount: this.deckManager.deck.length,
      joker,
      wildRank: Validator.getWildRank(joker),
      closedJoker: this.rules.closedJoker,
      jokerHidden,
      poolLimit: this.rules.poolLimit,
      deals: this.rules.deals, // Deals Rummy: how many deals; round is the deal being played
      // Coins: what each player paid to sit down, and what the winner takes. A player who
      // left a game in progress stays in the list, and so does their entry in the pot.
      // At a Points table played for a value a point, the stake is only held: each loser
      // pays their points x pointValue out of it, so there is no pot.
      stake: this.stake,
      pointValue: this.pointValue,
      pot: this.pointValue ? 0 : this.stake * this.players.size,
      private: this.isPrivate,
      round: this.round,
      winner: this.winner,
      lastResult: this.lastResult,
      // Only show own hand
      hand: me ? me.hand : [],
      groups: me ? me.groups : [],
      lastDrawnId: me ? me.lastDrawnId : null
    };

    // Add player info
    for (const [playerId, player] of this.players) {
      gameState.players.push({
        id: playerId,
        username: player.username,
        connected: player.connected,
        status: player.status,
        eliminated: player.eliminated,
        handCount: player.hand.length,
        totalScore: player.totalScore,
        chips: player.chips || 0,
        seenJoker: player.seenJoker,
        submitted: this.submitted.includes(playerId)
      });
    }

    return gameState;
  }

  // Closed joker: turns it face up for a player whose arrangement now holds a pure sequence.
  // Returns true if this call is what earned it.
  earnJokerSight(player) {
    if (player.seenJoker || this.status !== 'playing' || player.status !== 'active') return false;
    if (!this.getMelds(player).some(cards => Validator.isPureSequence(cards))) return false;

    player.seenJoker = true;
    return true;
  }

  requireTurn(userId, phase) {
    if (this.status !== 'playing') {
      throw new Error('Game not in playing state');
    }

    const player = this.players.get(userId);
    if (!player) {
      throw new Error('Player not found');
    }

    if (this.currentPlayer !== userId) {
      throw new Error('Not your turn');
    }

    if (this.turnPhase !== phase) {
      throw new Error(phase === 'draw' ? 'You have already drawn a card' : 'Draw a card first');
    }

    return player;
  }

  drawCard(userId, fromDiscard = false) {
    const player = this.requireTurn(userId, 'draw');

    if (fromDiscard && !this.deckManager.getTopDiscard()) {
      throw new Error('Discard pile is empty');
    }

    const card = this.deckManager.drawCard(fromDiscard);
    if (!card) {
      throw new Error('No cards left to draw');
    }

    player.hand.push(card);
    player.lastDrawnId = card.id;
    player.drawnFromDiscard = fromDiscard;
    player.missedTurns = 0;
    this.turnPhase = 'discard';

    return {
      card,
      fromDiscard,
      handCount: player.hand.length
    };
  }

  discardCard(userId, cardId) {
    const player = this.requireTurn(userId, 'discard');

    const discardedCard = this.takeFromHand(player, cardId);
    this.deckManager.discardCard(discardedCard);
    player.missedTurns = 0;
    player.turnsTaken += 1;
    player.lastDrawnId = null;
    player.drawnFromDiscard = false;
    // Throwing the odd card out of a group can be what completes a pure sequence
    this.earnJokerSight(player);

    // Move to next player
    this.nextPlayer();

    return {
      discarded: discardedCard,
      topDiscard: this.deckManager.getTopDiscard(),
      nextPlayer: this.currentPlayer
    };
  }

  // Find and remove card from hand
  takeFromHand(player, cardId) {
    const cardIndex = player.hand.findIndex(card => card.id === cardId);
    if (cardIndex === -1) {
      throw new Error('Card not in hand');
    }

    if (player.drawnFromDiscard && player.lastDrawnId === cardId) {
      throw new Error('You cannot discard the card you just picked from the open pile');
    }

    const card = player.hand.splice(cardIndex, 1)[0];
    player.groups = this.sanitizeGroups(player, player.groups);
    return card;
  }

  // Keep only ids that are really in the hand, each at most once
  sanitizeGroups(player, groups) {
    const inHand = new Set(player.hand.map(card => card.id));
    const used = new Set();
    const clean = [];

    for (const group of Array.isArray(groups) ? groups : []) {
      if (!Array.isArray(group)) continue;

      const ids = [];
      for (const cardId of group) {
        if (inHand.has(cardId) && !used.has(cardId)) {
          used.add(cardId);
          ids.push(cardId);
        }
      }
      if (ids.length > 0) clean.push(ids);
    }

    return clean;
  }

  // Returns true if the new arrangement turned a closed joker face up for this player
  arrangeHand(userId, groups) {
    const player = this.players.get(userId);
    if (!player) {
      throw new Error('Player not found');
    }

    player.groups = this.sanitizeGroups(player, groups);
    return this.earnJokerSight(player);
  }

  // The player's arrangement as card objects; cards left out of every group stand alone
  getMelds(player) {
    const cardsById = new Map(player.hand.map(card => [card.id, card]));
    const melds = player.groups.map(group => group.map(id => cardsById.get(id)).filter(Boolean));

    const grouped = new Set(player.groups.flat());
    for (const card of player.hand) {
      if (!grouped.has(card.id)) melds.push([card]);
    }

    return melds;
  }

  // The finishing card is discarded and the remaining 13 cards are judged as arranged
  declare(userId, cardId, groups) {
    const player = this.requireTurn(userId, 'discard');

    const finishCard = this.takeFromHand(player, cardId);
    this.deckManager.discardCard(finishCard);
    player.missedTurns = 0;
    if (groups) {
      player.groups = this.sanitizeGroups(player, groups);
    }

    // Check if player has valid declaration
    const evaluation = Validator.evaluateHand(this.getMelds(player), this.deckManager.joker);
    if (evaluation.valid) {
      return { valid: true, roundResult: this.beginShow(userId) };
    }

    // A wrong declaration costs the maximum and puts the player out of the round
    player.status = 'dropped';
    player.roundScore = WRONG_DECLARATION_POINTS;
    return { valid: false, roundResult: this.afterPlayerOut(player) };
  }

  // A valid declaration has won the round. Before the hands are counted, everyone else gets
  // a short time to put their own cards into the best groups they can and hand them in.
  // Nobody is on turn meanwhile, and the turn clock counts that time down.
  // Returns the round result if there is nobody to wait for.
  beginShow(winnerId) {
    this.declaredBy = winnerId;
    this.submitted = [];
    this.currentPlayer = null;
    this.turnPhase = 'arrange';
    this.turnDeadline = Date.now() + ARRANGE_TIMEOUT_MS;
    return this.endShowIfReady();
  }

  // The players a declaration is still waiting for
  getArranging() {
    return this.getActivePlayers().filter(
      player => player.id !== this.declaredBy && !this.submitted.includes(player.id)
    );
  }

  // Counts the hands once nobody is arranging any more. Returns the round result, or null.
  endShowIfReady() {
    if (this.getArranging().length > 0) return null;
    return this.endRound(this.declaredBy, 'declare');
  }

  // After someone else's declaration: this is how I want my cards counted.
  // Returns the round result if that was the last hand awaited, otherwise null.
  submitHand(userId, groups) {
    if (this.status !== 'playing' || !this.declaredBy) {
      throw new Error('Nobody has declared');
    }

    const player = this.players.get(userId);
    if (!player) {
      throw new Error('Player not found');
    }
    if (!this.getArranging().includes(player)) {
      throw new Error('Your cards are already in');
    }

    if (groups) {
      player.groups = this.sanitizeGroups(player, groups);
    }
    this.submitted.push(userId);
    return this.endShowIfReady();
  }

  // Give up the round at the start of your turn. Returns the round result if that ended the round.
  drop(userId) {
    const player = this.requireTurn(userId, 'draw');

    player.status = 'dropped';
    player.roundScore = player.turnsTaken === 0 ? FIRST_DROP_POINTS : MIDDLE_DROP_POINTS;
    return this.afterPlayerOut(player);
  }

  // The clock has run out: plays the current turn for the player who ran out of time, or,
  // after a declaration, counts the hands as they lie.
  // Returns the round result if that ended the round.
  autoPlay() {
    if (this.status !== 'playing') return null;
    if (this.declaredBy) return this.endRound(this.declaredBy, 'declare');

    const player = this.players.get(this.currentPlayer);
    const missedTurns = player.missedTurns + 1;

    if (missedTurns >= MAX_MISSED_TURNS) {
      player.status = 'dropped';
      player.roundScore = MIDDLE_DROP_POINTS;
      return this.afterPlayerOut(player);
    }

    if (this.turnPhase === 'draw') {
      this.drawCard(player.id, false);
    }

    // Throw back the card just drawn, unless it came from the open pile
    const discard = player.drawnFromDiscard
      ? player.hand.find(card => card.id !== player.lastDrawnId)
      : player.hand.find(card => card.id === player.lastDrawnId);
    this.discardCard(player.id, discard.id);
    player.missedTurns = missedTurns;

    return null;
  }

  // Called once a player is out of the round (drop, wrong declaration, leaving)
  afterPlayerOut(player) {
    const active = this.getActivePlayers();
    if (active.length <= 1) {
      return this.endRound(active.length === 1 ? active[0].id : null, 'last_player');
    }

    if (this.currentPlayer === player.id) {
      this.nextPlayer();
    }

    return null;
  }

  endRound(winnerId, reason) {
    const joker = this.deckManager.joker;

    // Calculate scores
    const results = this.roundPlayers.map(playerId => {
      const player = this.players.get(playerId);
      const evaluation = Validator.evaluateHand(this.getMelds(player), joker);

      if (playerId === winnerId) {
        player.roundScore = 0; // Winner gets 0
      } else if (player.status === 'active') {
        player.roundScore = evaluation.points;
      }
      // Dropped players keep the penalty they were given
      player.totalScore += player.roundScore;

      let outcome = 'lost';
      if (playerId === winnerId) outcome = 'winner';
      else if (player.status === 'dropped') outcome = 'dropped';

      return {
        id: playerId,
        username: player.username,
        outcome,
        points: player.roundScore,
        totalScore: player.totalScore,
        melds: evaluation.melds
      };
    });

    // A points game is a single round. A pool game runs until one player is left under the limit.
    let matchOver = true;
    let matchWinner = winnerId;
    const { poolLimit, deals } = this.rules;
    if (poolLimit) {
      for (const player of this.players.values()) {
        if (player.totalScore >= poolLimit) player.eliminated = true;
      }
      const contenders = this.getContenders();
      matchOver = contenders.length <= 1;
      matchWinner = matchOver ? (contenders.length === 1 ? contenders[0].id : winnerId) : null;
    } else if (deals) {
      ({ matchOver, matchWinner } = this.settleDeal(results, winnerId, deals));
    } else if (this.pointValue) {
      // Points for coins: each loser pays their points at the table's value to the winner
      let won = 0;
      for (const result of results) {
        if (result.id === winnerId) continue;
        result.coins = -Math.min(result.points, MAX_LOSS_POINTS) * this.pointValue;
        won -= result.coins;
      }
      const winnerResult = results.find(result => result.id === winnerId);
      if (winnerResult) winnerResult.coins = won;
    }

    for (const result of results) {
      result.eliminated = this.players.get(result.id).eliminated;
    }

    this.lastResult = {
      round: this.round,
      reason,
      winner: winnerId,
      players: results,
      matchOver,
      matchWinner
    };

    this.currentPlayer = null;
    this.turnDeadline = null;
    this.declaredBy = null;
    this.submitted = [];
    if (matchOver) {
      this.status = 'finished';
      this.winner = matchWinner;
    } else {
      this.status = 'round_over';
      this.nextRoundAt = Date.now() + NEXT_ROUND_DELAY_MS;
    }

    return this.lastResult;
  }

  // Deals Rummy, at the end of a deal: the winner takes each loser's points in chips. After
  // the last deal the player with the most chips has won; players level at the top play one
  // more deal between them. Adds `chips` (after the deal) and `chipsWon` to each result.
  settleDeal(results, winnerId, deals) {
    const winner = winnerId ? this.players.get(winnerId) : null;
    let won = 0;
    for (const result of results) {
      const player = this.players.get(result.id);
      if (result.id !== winnerId) {
        const lost = Math.min(result.points, player.chips);
        player.chips -= lost;
        won += lost;
        result.chipsWon = -lost;
      }
    }
    if (winner) winner.chips += won;
    for (const result of results) {
      result.chips = this.players.get(result.id).chips;
      if (result.id === winnerId) result.chipsWon = won;
    }

    const contenders = this.getContenders(); // a player who left is out of the running
    if (contenders.length <= 1) {
      return { matchOver: true, matchWinner: contenders.length === 1 ? contenders[0].id : winnerId };
    }
    if (this.round < deals) return { matchOver: false, matchWinner: null };

    const most = Math.max(...contenders.map(player => player.chips));
    const leaders = contenders.filter(player => player.chips === most);
    if (leaders.length === 1) return { matchOver: true, matchWinner: leaders[0].id };

    // A tie: only the leaders play the next deal
    for (const player of contenders) {
      if (player.chips < most) player.eliminated = true;
    }
    return { matchOver: false, matchWinner: null };
  }

  nextPlayer() {
    const currentIndex = this.roundPlayers.indexOf(this.currentPlayer);
    for (let step = 1; step <= this.roundPlayers.length; step++) {
      const candidateId = this.roundPlayers[(currentIndex + step) % this.roundPlayers.length];
      if (this.players.get(candidateId).status === 'active') {
        this.currentPlayer = candidateId;
        break;
      }
    }
    this.beginTurn();
  }

  // The server was away for a while: whoever is on turn gets the whole time again, and so
  // does the countdown to the next round. Otherwise a player who could not reach the server
  // would be auto-played or dropped for it.
  restartClock() {
    if (this.status === 'playing') {
      this.turnDeadline = Date.now() + (this.declaredBy ? ARRANGE_TIMEOUT_MS : TURN_TIMEOUT_MS);
    } else if (this.status === 'round_over') {
      this.nextRoundAt = Date.now() + NEXT_ROUND_DELAY_MS;
    }
  }

  serialize() {
    return {
      gameId: this.gameId,
      roomCode: this.roomCode,
      gameType: this.gameType,
      maxPlayers: this.maxPlayers,
      players: Array.from(this.players.entries()),
      deckManager: this.deckManager.serialize(),
      hostId: this.hostId,
      currentPlayer: this.currentPlayer,
      turnPhase: this.turnPhase,
      turnDeadline: this.turnDeadline,
      declaredBy: this.declaredBy,
      submitted: this.submitted,
      roundPlayers: this.roundPlayers,
      nextRoundAt: this.nextRoundAt,
      status: this.status,
      winner: this.winner,
      round: this.round,
      lastResult: this.lastResult,
      stake: this.stake,
      pointValue: this.pointValue,
      isPrivate: this.isPrivate,
      createdAt: this.createdAt
    };
  }

  static fromJSON(data) {
    const gameEngine = new GameEngine(data.gameId, data.gameType, data.maxPlayers, data.roomCode);
    Object.assign(gameEngine, data, {
      players: new Map(data.players),
      deckManager: DeckManager.fromJSON(data.deckManager),
      createdAt: new Date(data.createdAt)
    });
    return gameEngine;
  }
}

module.exports = GameEngine;
