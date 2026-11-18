// How a computer player plays Donkey Master: which card to play, from what a player in that
// seat can see (its own hand and the cards on the table). DonkeyBots plays the card through
// DonkeyEngine like any player.
//
// The aim is to be rid of cards without picking up a trick:
// - leading, a low card of the longest suit, which the others are most likely to follow;
// - following, the highest card that stays under the best card played so far; when every
//   other player has already played, the trick cannot be cut any more and leaves the game,
//   so the highest card of the suit goes;
// - unable to follow, the highest card held, to be rid of it while the trick is cut.

const VALUES = ['2', '3', '4', '5', '6', '7', '8', '9', '10', 'J', 'Q', 'K', 'A'];
const rankOf = (card) => VALUES.indexOf(card.value);

const randomly = (chance) => Math.random() < chance;

class DonkeyBrain {
  // The id of the card `botId` plays now, or null when it may play none
  static choose(engine, botId) {
    const player = engine.players.get(String(botId));
    const allowed = new Set(engine.playable(botId));
    const choices = player ? player.hand.filter((card) => allowed.has(card.id)) : [];
    if (choices.length <= 1) return choices.length === 1 ? choices[0].id : null;

    const byRank = (a, b) => rankOf(a) - rankOf(b);
    if (engine.trick.length === 0) {
      // Leading: the lowest card of the suit held most of
      const count = new Map();
      for (const card of choices) count.set(card.suit, (count.get(card.suit) || 0) + 1);
      const longest = Math.max(...count.values());
      const suit = [...count.keys()].find((key) => count.get(key) === longest);
      const lowest = choices.filter((card) => card.suit === suit).sort(byRank)[0];
      // now and then any low card, as people do
      return randomly(0.2) ? choices.slice().sort(byRank)[0].id : lowest.id;
    }

    const following = choices.every((card) => card.suit === engine.leadSuit);
    if (!following) {
      // Cutting: away with the highest card
      return choices.slice().sort(byRank).pop().id;
    }

    const played = new Set(engine.trick.map((play) => play.playerId));
    const stillToPlay = engine.seated().filter((other) => engine.inPlay(other) && !played.has(other.id)).length;
    const sorted = choices.slice().sort(byRank);
    if (stillToPlay <= 1) return sorted[sorted.length - 1].id; // last to play: nobody can cut now

    const best = Math.max(...engine.trick
      .filter((play) => play.card.suit === engine.leadSuit)
      .map((play) => rankOf(play.card)));
    const under = sorted.filter((card) => rankOf(card) < best);
    return (under.length > 0 ? under[under.length - 1] : sorted[0]).id;
  }
}

module.exports = DonkeyBrain;
