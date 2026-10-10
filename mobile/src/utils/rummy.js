// Meld rules for the on-screen hints. This mirrors backend/src/game/Validator.js;
// the server is the judge, so keep the two in step.
import { VALUES } from './constants';

const MAX_HAND_POINTS = 80;

export const MELD_LABELS = {
  pure_sequence: 'Pure sequence',
  impure_sequence: 'Sequence',
  set: 'Set',
  invalid: 'Not a meld',
};

const getValueIndex = (value) => VALUES.indexOf(value);

// The rank that is wild this round. If the cut card is a printed joker, aces are wild.
export const getWildRank = (joker) => {
  if (!joker) return null;
  return joker.isJoker ? 'A' : joker.value;
};

export const isWild = (card, joker) => card.isJoker || card.value === getWildRank(joker);

// Can these cards form a same-suit run when `wilds` jokers fill the gaps?
// Ace counts low (A-2-3) or high (Q-K-A), never both (K-A-2).
const fitsRun = (cards, wilds) => {
  const suit = cards[0].suit;
  if (!cards.every((card) => card.suit === suit)) return false;

  const low = cards.map((card) => getValueIndex(card.value));
  if (new Set(low).size !== low.length) return false;
  if (cards.length + wilds > VALUES.length) return false;

  const high = low.map((index) => (index === 0 ? VALUES.length : index));
  return [low, high].some((indexes) => {
    const gaps = Math.max(...indexes) - Math.min(...indexes) + 1 - indexes.length;
    return gaps <= wilds;
  });
};

const isPureSequence = (cards) => {
  if (cards.length < 3) return false;
  if (cards.some((card) => card.isJoker)) return false;
  return fitsRun(cards, 0);
};

const isImpureSequence = (cards, joker) => {
  if (cards.length < 3) return false;

  const naturals = cards.filter((card) => !isWild(card, joker));
  const wilds = cards.length - naturals.length;
  if (wilds === 0) return false;
  if (naturals.length === 0) return true;

  return fitsRun(naturals, wilds);
};

const isSet = (cards, joker) => {
  if (cards.length < 3 || cards.length > 4) return false;

  const naturals = cards.filter((card) => !isWild(card, joker));
  if (naturals.length === 0) return true;

  const firstValue = naturals[0].value;
  if (!naturals.every((card) => card.value === firstValue)) return false;

  return new Set(naturals.map((card) => card.suit)).size === naturals.length;
};

export const classifyMeld = (cards, joker) => {
  if (isPureSequence(cards)) return 'pure_sequence';
  if (isImpureSequence(cards, joker)) return 'impure_sequence';
  if (isSet(cards, joker)) return 'set';
  return 'invalid';
};

export const getCardPoints = (card, joker) => {
  if (isWild(card, joker)) return 0;
  if (['A', 'J', 'Q', 'K'].includes(card.value)) return 10;
  return parseInt(card.value, 10);
};

// Judge a full arrangement. `groups` are arrays of cards covering the whole hand.
export const evaluateHand = (groups, joker) => {
  const melds = groups
    .filter((cards) => cards.length > 0)
    .map((cards) => ({ type: classifyMeld(cards, joker), cards }));

  const pureSequences = melds.filter((meld) => meld.type === 'pure_sequence').length;
  const sequences = pureSequences + melds.filter((meld) => meld.type === 'impure_sequence').length;

  // A declaration needs every card melded, two sequences, and one of them pure
  const valid =
    melds.length > 0 &&
    melds.every((meld) => meld.type !== 'invalid') &&
    pureSequences >= 1 &&
    sequences >= 2;

  let counted;
  if (pureSequences === 0) {
    counted = melds; // nothing is safe without a pure sequence
  } else if (sequences < 2) {
    counted = melds.filter((meld) => meld.type !== 'pure_sequence');
  } else {
    counted = melds.filter((meld) => meld.type === 'invalid');
  }

  let points = 0;
  for (const meld of counted) {
    for (const card of meld.cards) {
      points += getCardPoints(card, joker);
    }
  }

  return { valid, melds, points: Math.min(points, MAX_HAND_POINTS) };
};

// Suit by suit, low to high, printed jokers last
export const sortCards = (cards) =>
  [...cards].sort((a, b) => {
    if (a.isJoker !== b.isJoker) return a.isJoker ? 1 : -1;
    if (a.suit !== b.suit) return a.suit.localeCompare(b.suit);
    return getValueIndex(a.value) - getValueIndex(b.value);
  });

// A starting arrangement: one group of card ids per suit, printed jokers together at the end
export const sortIntoGroups = (hand) => {
  const groups = new Map();
  for (const card of sortCards(hand)) {
    const key = card.isJoker ? 'joker' : card.suit;
    if (!groups.has(key)) groups.set(key, []);
    groups.get(key).push(card.id);
  }
  return Array.from(groups.values());
};

export const formatCard = (card) => (card.isJoker ? 'Joker' : card.code);
