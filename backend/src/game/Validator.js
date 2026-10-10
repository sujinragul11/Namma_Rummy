const VALUE_ORDER = ['A', '2', '3', '4', '5', '6', '7', '8', '9', '10', 'J', 'Q', 'K'];
const MAX_HAND_POINTS = 80;

class RummyValidator {
  static getValueIndex(value) {
    return VALUE_ORDER.indexOf(value);
  }

  // The rank that is wild this round. If the cut card is a printed joker, aces are wild.
  static getWildRank(joker) {
    if (!joker) return null;
    return joker.isJoker ? 'A' : joker.value;
  }

  static isWild(card, joker) {
    return card.isJoker || card.value === this.getWildRank(joker);
  }

  // Can these cards form a same-suit run when `wilds` jokers fill the gaps?
  // Ace counts low (A-2-3) or high (Q-K-A), never both (K-A-2).
  static fitsRun(cards, wilds) {
    const suit = cards[0].suit;
    if (!cards.every(card => card.suit === suit)) return false;

    const low = cards.map(card => this.getValueIndex(card.value));
    if (new Set(low).size !== low.length) return false;
    if (cards.length + wilds > VALUE_ORDER.length) return false;

    const high = low.map(index => (index === 0 ? VALUE_ORDER.length : index));
    return [low, high].some(indexes => {
      const gaps = Math.max(...indexes) - Math.min(...indexes) + 1 - indexes.length;
      return gaps <= wilds;
    });
  }

  static isPureSequence(cards) {
    if (!cards || cards.length < 3) return false;
    // A wild-rank card may sit in a pure sequence as itself, a printed joker never can
    if (cards.some(card => card.isJoker)) return false;
    return this.fitsRun(cards, 0);
  }

  static isImpureSequence(cards, joker) {
    if (!cards || cards.length < 3) return false;

    const naturals = cards.filter(card => !this.isWild(card, joker));
    const wilds = cards.length - naturals.length;
    if (wilds === 0) return false;
    if (naturals.length === 0) return true;

    return this.fitsRun(naturals, wilds);
  }

  static isSet(cards, joker) {
    if (!cards || cards.length < 3 || cards.length > 4) return false;

    const naturals = cards.filter(card => !this.isWild(card, joker));
    if (naturals.length === 0) return true;

    const firstValue = naturals[0].value;
    if (!naturals.every(card => card.value === firstValue)) return false;

    // In a set, all cards should be different suits
    return new Set(naturals.map(card => card.suit)).size === naturals.length;
  }

  static classifyMeld(cards, joker) {
    if (this.isPureSequence(cards)) return 'pure_sequence';
    if (this.isImpureSequence(cards, joker)) return 'impure_sequence';
    if (this.isSet(cards, joker)) return 'set';
    return 'invalid';
  }

  static isValidMeld(cards, joker) {
    return this.classifyMeld(cards, joker) !== 'invalid';
  }

  static getCardPoints(card, joker) {
    if (this.isWild(card, joker)) return 0; // Jokers have 0 points
    if (['A', 'J', 'Q', 'K'].includes(card.value)) return 10;
    return parseInt(card.value, 10);
  }

  // Judge a full arrangement. `groups` must cover every card in the hand,
  // with each ungrouped card passed as a group of its own.
  static evaluateHand(groups, joker) {
    const melds = groups
      .filter(cards => cards.length > 0)
      .map(cards => ({ type: this.classifyMeld(cards, joker), cards }));

    const pureSequences = melds.filter(meld => meld.type === 'pure_sequence').length;
    const sequences = pureSequences + melds.filter(meld => meld.type === 'impure_sequence').length;

    // A declaration needs every card melded, two sequences, and one of them pure
    const valid =
      melds.length > 0 &&
      melds.every(meld => meld.type !== 'invalid') &&
      pureSequences >= 1 &&
      sequences >= 2;

    let counted;
    if (pureSequences === 0) {
      counted = melds; // nothing is safe without a pure sequence
    } else if (sequences < 2) {
      counted = melds.filter(meld => meld.type !== 'pure_sequence');
    } else {
      counted = melds.filter(meld => meld.type === 'invalid');
    }

    let points = 0;
    for (const meld of counted) {
      for (const card of meld.cards) {
        points += this.getCardPoints(card, joker);
      }
    }

    return {
      valid,
      melds,
      points: Math.min(points, MAX_HAND_POINTS)
    };
  }
}

module.exports = RummyValidator;
