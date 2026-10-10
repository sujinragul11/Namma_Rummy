class_name Rummy
extends RefCounted
## Meld rules for the on-screen hints. This mirrors backend/src/game/Validator.js;
## the server is the judge, so keep the two in step.
##
## A card is a Dictionary as the server sends it: {id, suit, value, code, isJoker}.

const VALUES: Array[String] = ["A", "2", "3", "4", "5", "6", "7", "8", "9", "10", "J", "Q", "K"]
## Order used when sorting a hand: black, red, black, red.
const SUITS: Array[String] = ["♠", "♥", "♣", "♦"]
const SUIT_NAMES := {"♠": "spades", "♥": "hearts", "♣": "clubs", "♦": "diamonds"}
const MAX_HAND_POINTS := 80
const MELD_LABELS := {
	"pure_sequence": "Pure sequence",
	"impure_sequence": "Sequence",
	"set": "Set",
	"invalid": "Not a meld",
}


## The rank that is wild this round. If the cut card is a printed joker, aces are wild.
static func wild_rank(joker: Variant) -> String:
	if not (joker is Dictionary) or joker.is_empty():
		return ""
	return "A" if joker.get("isJoker", false) else str(joker.get("value", ""))


static func is_wild(card: Dictionary, joker: Variant) -> bool:
	return card.get("isJoker", false) or card.get("value") == wild_rank(joker)


## Can these cards form a same-suit run when `wilds` jokers fill the gaps?
## Ace counts low (A-2-3) or high (Q-K-A), never both (K-A-2).
static func _fits_run(cards: Array, wilds: int) -> bool:
	var suit: String = cards[0].suit
	var low: Array[int] = []
	for card: Dictionary in cards:
		if card.suit != suit:
			return false
		var index := VALUES.find(card.value)
		if low.has(index):
			return false
		low.append(index)
	if cards.size() + wilds > VALUES.size():
		return false

	var high: Array[int] = []
	for index in low:
		high.append(VALUES.size() if index == 0 else index)

	for indexes: Array[int] in [low, high]:
		var gaps: int = indexes.max() - indexes.min() + 1 - indexes.size()
		if gaps <= wilds:
			return true
	return false


static func _is_pure_sequence(cards: Array) -> bool:
	if cards.size() < 3:
		return false
	# A wild-rank card may sit in a pure sequence as itself, a printed joker never can
	for card: Dictionary in cards:
		if card.get("isJoker", false):
			return false
	return _fits_run(cards, 0)


static func _is_impure_sequence(cards: Array, joker: Variant) -> bool:
	if cards.size() < 3:
		return false
	var naturals := cards.filter(func(card: Dictionary) -> bool: return not is_wild(card, joker))
	var wilds := cards.size() - naturals.size()
	if wilds == 0:
		return false
	if naturals.is_empty():
		return true
	return _fits_run(naturals, wilds)


static func _is_set(cards: Array, joker: Variant) -> bool:
	if cards.size() < 3 or cards.size() > 4:
		return false
	var naturals := cards.filter(func(card: Dictionary) -> bool: return not is_wild(card, joker))
	if naturals.is_empty():
		return true

	# Same rank, and every suit different
	var suits: Array = []
	for card: Dictionary in naturals:
		if card.value != naturals[0].value or suits.has(card.suit):
			return false
		suits.append(card.suit)
	return true


## "pure_sequence", "impure_sequence", "set" or "invalid".
static func classify_meld(cards: Array, joker: Variant) -> String:
	if _is_pure_sequence(cards):
		return "pure_sequence"
	if _is_impure_sequence(cards, joker):
		return "impure_sequence"
	if _is_set(cards, joker):
		return "set"
	return "invalid"


static func card_points(card: Dictionary, joker: Variant) -> int:
	if is_wild(card, joker):
		return 0
	if card.value in ["A", "J", "Q", "K"]:
		return 10
	return str(card.value).to_int()


## Judges a full arrangement. `groups` are arrays of cards covering the whole hand.
## Returns {"valid": bool, "points": int, "melds": [{"type": String, "cards": Array}]}.
static func evaluate_hand(groups: Array, joker: Variant) -> Dictionary:
	var melds: Array = []
	var pure_sequences := 0
	var sequences := 0
	var all_melded := true
	for cards: Array in groups:
		if cards.is_empty():
			continue
		var type := classify_meld(cards, joker)
		melds.append({"type": type, "cards": cards})
		if type == "pure_sequence":
			pure_sequences += 1
			sequences += 1
		elif type == "impure_sequence":
			sequences += 1
		elif type == "invalid":
			all_melded = false

	# A declaration needs every card melded, two sequences, and one of them pure
	var valid := not melds.is_empty() and all_melded and pure_sequences >= 1 and sequences >= 2

	var points := 0
	for meld: Dictionary in melds:
		var counted: bool
		if pure_sequences == 0:
			counted = true  # nothing is safe without a pure sequence
		elif sequences < 2:
			counted = meld.type != "pure_sequence"
		else:
			counted = meld.type == "invalid"
		if counted:
			for card: Dictionary in meld.cards:
				points += card_points(card, joker)

	return {"valid": valid, "points": mini(points, MAX_HAND_POINTS), "melds": melds}


## Suit by suit, low to high, printed jokers last.
static func sort_cards(cards: Array) -> Array:
	var sorted := cards.duplicate()
	sorted.sort_custom(_comes_before)
	return sorted


static func _comes_before(a: Dictionary, b: Dictionary) -> bool:
	var a_joker: bool = a.get("isJoker", false)
	var b_joker: bool = b.get("isJoker", false)
	if a_joker != b_joker:
		return b_joker
	if not a_joker:
		if a.suit != b.suit:
			return SUITS.find(a.suit) < SUITS.find(b.suit)
		if a.value != b.value:
			return VALUES.find(a.value) < VALUES.find(b.value)
	# Two decks hold identical cards; the id keeps their order steady
	return str(a.id) < str(b.id)


## A starting arrangement: one group of card ids per suit, printed jokers together at the end.
static func sort_into_groups(hand: Array) -> Array:
	var groups: Array = []
	var current_key := ""
	for card: Dictionary in sort_cards(hand):
		var key: String = "joker" if card.get("isJoker", false) else str(card.suit)
		if key != current_key:
			groups.append([])
			current_key = key
		groups.back().append(card.id)
	return groups


## A card's name in plain words, e.g. "K of hearts".
static func card_name(card: Dictionary) -> String:
	if card.get("isJoker", false):
		return "the joker"
	return "%s of %s" % [card.value, SUIT_NAMES.get(card.suit, card.suit)]
