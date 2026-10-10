class DeckManager {
  constructor(numDecks = 1) {
    this.SUITS = ['♠', '♥', '♦', '♣'];
    this.VALUES = ['A', '2', '3', '4', '5', '6', '7', '8', '9', '10', 'J', 'Q', 'K'];
    this.numDecks = numDecks;
    this.deck = [];
    this.discardPile = [];
    this.joker = null;
    this.initializeDeck();
  }

  initializeDeck() {
    this.deck = [];
    for (let deckNumber = 1; deckNumber <= this.numDecks; deckNumber++) {
      for (const suit of this.SUITS) {
        for (const value of this.VALUES) {
          this.deck.push({
            // `code` repeats when two decks are in play, `id` never does
            id: `${value}${suit}-${deckNumber}`,
            suit,
            value,
            code: `${value}${suit}`,
            isJoker: false
          });
        }
      }
      // One printed joker (wild) per deck
      this.deck.push({ id: `JOKER-${deckNumber}`, suit: '★', value: 'Joker', code: 'JOKER', isJoker: true });
    }
  }

  shuffle() {
    for (let i = this.deck.length - 1; i > 0; i--) {
      const j = Math.floor(Math.random() * (i + 1));
      [this.deck[i], this.deck[j]] = [this.deck[j], this.deck[i]];
    }
    return this.deck;
  }

  pickRandomCard() {
    const randomIndex = Math.floor(Math.random() * this.deck.length);
    const card = this.deck[randomIndex];
    this.deck.splice(randomIndex, 1);
    return card;
  }

  setJoker() {
    const jokerCard = this.pickRandomCard();
    this.joker = {
      value: jokerCard.value,
      suit: jokerCard.suit,
      code: jokerCard.code,
      isJoker: jokerCard.isJoker
    };
    return this.joker;
  }

  drawCard(fromDiscard = false) {
    if (fromDiscard && this.discardPile.length > 0) {
      return this.discardPile.pop();
    }

    if (this.deck.length === 0) {
      // Reshuffle discard pile (except top card) if deck is empty
      const topCard = this.discardPile.pop();
      this.deck = this.discardPile;
      this.discardPile = topCard ? [topCard] : [];
      this.shuffle();
    }

    return this.deck.pop();
  }

  discardCard(card) {
    this.discardPile.push(card);
    return this.discardPile;
  }

  getTopDiscard() {
    return this.discardPile.length > 0
      ? this.discardPile[this.discardPile.length - 1]
      : null;
  }

  dealCards(numPlayers, cardsPerPlayer = 13) {
    this.shuffle();
    this.setJoker();

    const hands = [];
    for (let i = 0; i < numPlayers; i++) {
      const hand = [];
      for (let j = 0; j < cardsPerPlayer; j++) {
        hand.push(this.deck.pop());
      }
      hands.push(hand);
    }

    // Put one card in discard pile to start
    this.discardPile.push(this.deck.pop());

    return {
      hands,
      deck: this.deck,
      discardPile: this.discardPile,
      joker: this.joker
    };
  }

  serialize() {
    return {
      numDecks: this.numDecks,
      deck: this.deck,
      discardPile: this.discardPile,
      joker: this.joker,
      remaining: this.deck.length
    };
  }

  static fromJSON(data) {
    const deckManager = new DeckManager(data.numDecks);
    deckManager.deck = data.deck;
    deckManager.discardPile = data.discardPile;
    deckManager.joker = data.joker;
    return deckManager;
  }
}

module.exports = DeckManager;
