const Validator = require('../game/Validator');

// How a computer player plays rummy: pure decisions, no sockets and no clocks. RummyBots asks
// it what to do and plays the move through GameEngine like any player. It decides only from
// what a player in that seat would know: its own hand, the card on the open pile, and the
// joker once that player may see it (a closed joker it has not earned stays unknown, and then
// only printed jokers are wild).
//
// The heart of it is arrange(): the grouping of a hand with the least points left over, found
// by searching every way of laying out sequences and sets. A hand without a pure sequence, or
// with fewer than two sequences, is worth less than its loose cards say, because nothing in it
// is safe yet; the search weighs that in, so the bot builds towards a declaration rather than
// only towards few points.

const RANKS = ['A', '2', '3', '4', '5', '6', '7', '8', '9', '10', 'J', 'Q', 'K'];
const SUITS = ['♠', '♥', '♦', '♣'];
const ACE_HIGH = 13; // an ace may close a run after the king (Q-K-A), never wrap round (K-A-2)

// What an unfinished hand costs beyond its loose cards: no pure sequence yet, and each of the
// two sequences a declaration needs that is still missing
const NO_PURE = 25;
const MISSING_SEQUENCE = 10;
// A loose card that already pairs with another (same rank, or same suit close by) is half way
// to a meld: it is worth keeping, so the hand counts as this much better for each such link
const LINK_VALUE = 2;
// Taking the open card has to make the hand clearly better than a card from the deck would
const TAKE_OPEN_MARGIN = 3;
// A starting hand worth this much or more, with not one meld in it, is not worth playing
const HOPELESS = 95;

const randomly = (chance) => Math.random() < chance;

// The natural cards' positions in a suit: an ace is both 1 (low) and 14 (high)
const positionsOf = (card) => {
  const index = RANKS.indexOf(card.value);
  return index === 0 ? [0, ACE_HIGH] : [index];
};

class RummyBrain {
  // The best layout of `cards` (13 or 14 of them) with `joker` the joker as this player knows
  // it (null: unknown or none). Returns { groups (arrays of card ids, loose cards left out),
  // loose (the loose cards), value (lower is better, for comparing hands), points (what the
  // hand would count now), valid (all cards melded as a declaration needs) }.
  static arrange(cards, joker) {
    const wilds = cards.filter((card) => Validator.isWild(card, joker));
    const naturals = cards.filter((card) => !Validator.isWild(card, joker));
    const points = naturals.map((card) => Validator.getCardPoints(card, joker));
    const melds = RummyBrain.candidateMelds(naturals, wilds.length, points);

    // Melds by the lowest card they hold: the search always places the lowest card still free
    const byLowest = naturals.map(() => []);
    melds.forEach((meld, index) => byLowest[lowestBit(meld.mask)].push(index));

    const memo = new Map();
    const solve = (mask, wildsLeft, pure, sequences) => {
      if (mask === 0) {
        return { cost: (pure ? 0 : NO_PURE) + Math.max(0, 2 - sequences) * MISSING_SEQUENCE, pick: null };
      }
      const key = ((mask * 16 + wildsLeft) * 2 + (pure ? 1 : 0)) * 3 + sequences;
      const known = memo.get(key);
      if (known) return known;

      const low = lowestBit(mask);
      // The lowest free card stays loose...
      let best = { cost: points[low] + solve(mask & ~(1 << low), wildsLeft, pure, sequences).cost, pick: -1 };
      // ...or goes into one of the melds it can start
      for (const index of byLowest[low]) {
        const meld = melds[index];
        if ((meld.mask & mask) !== meld.mask || meld.wilds > wildsLeft) continue;
        const rest = solve(
          mask & ~meld.mask,
          wildsLeft - meld.wilds,
          pure || meld.kind === 'pure',
          Math.min(2, sequences + (meld.kind === 'set' ? 0 : 1))
        );
        if (rest.cost < best.cost) best = { cost: rest.cost, pick: index };
      }
      memo.set(key, best);
      return best;
    };

    const full = naturals.length === 0 ? 0 : (2 ** naturals.length) - 1;
    const chosen = [];
    const loose = [];
    let state = { mask: full, wildsLeft: wilds.length, pure: false, sequences: 0 };
    const root = solve(state.mask, state.wildsLeft, state.pure, state.sequences);
    while (state.mask !== 0) {
      const step = solve(state.mask, state.wildsLeft, state.pure, state.sequences);
      if (step.pick === -1) {
        const low = lowestBit(state.mask);
        loose.push(naturals[low]);
        state = { ...state, mask: state.mask & ~(1 << low) };
      } else {
        const meld = melds[step.pick];
        chosen.push(meld);
        state = {
          mask: state.mask & ~meld.mask,
          wildsLeft: state.wildsLeft - meld.wilds,
          pure: state.pure || meld.kind === 'pure',
          sequences: Math.min(2, state.sequences + (meld.kind === 'set' ? 0 : 1))
        };
      }
    }

    const groups = RummyBrain.layOut(chosen, naturals, wilds);
    const grouped = new Set(groups.flat());
    const looseWilds = wilds.filter((card) => !grouped.has(card.id));
    const byId = new Map(cards.map((card) => [card.id, card]));
    const asCards = groups.map((ids) => ids.map((id) => byId.get(id)));
    for (const card of [...loose, ...looseWilds]) asCards.push([card]);
    const evaluation = Validator.evaluateHand(asCards, joker);

    return {
      groups,
      loose,
      value: root.cost - LINK_VALUE * RummyBrain.links(loose),
      points: evaluation.points,
      valid: evaluation.valid
    };
  }

  // Every sequence and set the natural cards can make, with up to `wildCount` wilds:
  // { mask (which naturals), wilds (how many wilds it needs), kind: 'pure' | 'impure' | 'set' }
  static candidateMelds(naturals, wildCount, points) {
    const melds = [];
    const seen = new Set();
    const add = (indexes, wilds, kind) => {
      let mask = 0;
      for (const index of indexes) mask |= 1 << index;
      const key = `${mask}:${wilds}:${kind}`;
      if (seen.has(key)) return;
      seen.add(key);
      melds.push({ mask, wilds, kind, points: indexes.reduce((sum, index) => sum + points[index], 0) });
    };

    // Runs: for each suit, the naturals at each position, then every window of positions
    for (const suit of SUITS) {
      const at = Array.from({ length: ACE_HIGH + 1 }, () => []);
      naturals.forEach((card, index) => {
        if (card.suit === suit) for (const position of positionsOf(card)) at[position].push(index);
      });
      for (let start = 0; start <= ACE_HIGH; start++) {
        for (let end = start + 2; end <= ACE_HIGH && end - start + 1 <= RANKS.length; end++) {
          const present = [];
          for (let position = start; position <= end; position++) if (at[position].length > 0) present.push(position);
          const gaps = end - start + 1 - present.length;
          if (present.length === 0 || gaps > wildCount) continue;
          // the first card at each position; with two decks, the second copy is a variant
          const first = present.map((position) => at[position][0]);
          add(first, gaps, gaps === 0 ? 'pure' : 'impure');
          const doubled = present.findIndex((position) => at[position].length > 1);
          if (doubled >= 0) {
            const other = first.slice();
            other[doubled] = at[present[doubled]][1];
            add(other, gaps, gaps === 0 ? 'pure' : 'impure');
          }
        }
      }
    }

    // Sets: one card of each suit of a rank, three or four with wilds
    for (const rank of RANKS) {
      const bySuit = new Map();
      naturals.forEach((card, index) => {
        if (card.value === rank && !bySuit.has(card.suit)) bySuit.set(card.suit, index);
      });
      const indexes = [...bySuit.values()];
      for (let subset = 1; subset < 2 ** indexes.length; subset++) {
        const picked = indexes.filter((_, bit) => subset & (1 << bit));
        for (let wilds = 0; picked.length + wilds <= 4 && wilds <= wildCount; wilds++) {
          if (picked.length + wilds >= 3) add(picked, wilds, 'set');
        }
      }
    }
    return melds;
  }

  // The melds as groups of card ids, each given the wilds it needs. Wilds left over join a
  // meld that can take them, so a finished hand has no wild lying loose.
  static layOut(melds, naturals, wilds) {
    const spare = wilds.slice();
    const groups = melds.map((meld) => {
      const ids = naturals.filter((_, index) => meld.mask & (1 << index)).map((card) => card.id);
      for (let n = 0; n < meld.wilds; n++) ids.push(spare.shift().id);
      return { ids, kind: meld.kind };
    });
    while (spare.length > 0) {
      const home = groups.find((group) => group.kind === 'impure')
        || groups.find((group) => group.kind === 'set' && group.ids.length < 4)
        || (groups.filter((group) => group.kind === 'pure').length >= 2 ? groups.filter((group) => group.kind === 'pure').pop() : null);
      if (home) {
        if (home.kind === 'pure') home.kind = 'impure';
        home.ids.push(spare.shift().id);
      } else if (spare.length >= 3) {
        groups.push({ ids: spare.splice(0, 3).map((card) => card.id), kind: 'impure' });
      } else {
        break; // one or two wilds with nowhere to go stay loose; they count no points
      }
    }
    return groups.map((group) => group.ids);
  }

  // How many pairs of loose cards could grow into a meld together
  static links(loose) {
    let links = 0;
    for (let i = 0; i < loose.length; i++) {
      for (let j = i + 1; j < loose.length; j++) {
        const a = loose[i];
        const b = loose[j];
        if (a.value === b.value && a.suit !== b.suit) {
          links += 1;
        } else if (a.suit === b.suit) {
          const apart = Math.min(...positionsOf(a).flatMap((x) => positionsOf(b).map((y) => Math.abs(x - y))));
          if (apart === 1) links += 1;
          else if (apart === 2) links += 0.5;
        }
      }
    }
    return links;
  }

  // At the start of a turn: take the open card (true) or draw from the deck (false)?
  static takeOpenCard(hand, top, joker) {
    if (!top) return false;
    if (Validator.isWild(top, joker)) return true;
    const now = RummyBrain.arrange(hand, joker).value;
    const withTop = [...hand, top];
    let best = Infinity;
    for (const card of hand) {
      best = Math.min(best, RummyBrain.arrange(withTop.filter((other) => other !== card), joker).value);
    }
    // Like a person, a bot sometimes passes up a small gain
    return best <= now - TAKE_OPEN_MARGIN && !(best > now - TAKE_OPEN_MARGIN * 2 && randomly(0.15));
  }

  // After drawing (14 cards): which card goes, and whether that finishes the hand.
  // `keep` is the card just taken from the open pile, which may not go straight back.
  // Returns { cardId, declare, groups (the 13 cards left, as they would be shown) }.
  static discard(hand, joker, keep = null) {
    const options = [];
    for (const card of hand) {
      if (card.id === keep) continue;
      const rest = hand.filter((other) => other !== card);
      const layout = RummyBrain.arrange(rest, joker);
      if (layout.valid) return { cardId: card.id, declare: true, groups: layout.groups };
      options.push({ card, layout });
    }
    // Lowest value first; between equals, the card worth more points goes (fewer points held)
    options.sort((a, b) => a.layout.value - b.layout.value
      || Validator.getCardPoints(b.card, joker) - Validator.getCardPoints(a.card, joker));
    let choice = options[0];
    // Now and then a bot keeps the wrong one of two nearly equal cards
    if (options.length > 1 && options[1].layout.value - choice.layout.value < 2 && randomly(0.15)) {
      choice = options[1];
    }
    return { cardId: choice.card.id, declare: false, groups: choice.layout.groups };
  }

  // Before the first draw: is this hand so poor that the cheap first drop is better?
  static dropAtStart(hand, joker) {
    const layout = RummyBrain.arrange(hand, joker);
    // Hopeless: not one meld, many points, little that links up. That is about 8 starting
    // hands in 100, and most of them are dropped, as people drop now and then
    return layout.groups.length === 0 && layout.value >= HOPELESS && randomly(0.9);
  }
}

// The index of the lowest set bit of a non-zero mask
function lowestBit(mask) {
  return 31 - Math.clz32(mask & -mask);
}

RummyBrain.NO_PURE = NO_PURE;
RummyBrain.MISSING_SEQUENCE = MISSING_SEQUENCE;

module.exports = RummyBrain;
