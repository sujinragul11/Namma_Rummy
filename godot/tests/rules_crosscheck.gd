extends Node
## Checks rules/rummy.gd against answers computed by the server's rule engine
## (backend/src/game/Validator.js), so the hints on screen never disagree with the judge.
##
## Run:  godot --headless --path . res://tests/rules_crosscheck.tscn -- --vectors=<file.json>
## The vectors file holds random melds and hands with the server's verdict for each.


func _ready() -> void:
	var path := ""
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--vectors="):
			path = argument.trim_prefix("--vectors=")

	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not (data is Dictionary):
		print("could not read test vectors from '%s'" % path)
		get_tree().quit(2)
		return

	var mismatches := 0
	var seen := {}

	for sample: Dictionary in data.melds:
		var type := Rummy.classify_meld(sample.cards, sample.joker)
		seen[type] = seen.get(type, 0) + 1
		if type != sample.type:
			mismatches += 1
			if mismatches <= 5:
				print("meld mismatch: %s  joker %s  server=%s godot=%s" % [_codes(sample.cards), sample.joker.code, sample.type, type])
		for index: int in sample.cards.size():
			var card: Dictionary = sample.cards[index]
			if Rummy.card_points(card, sample.joker) != int(sample.points[index]):
				mismatches += 1
			if Rummy.is_wild(card, sample.joker) != sample.wild[index]:
				mismatches += 1

	var valid_hands := 0
	for sample: Dictionary in data.hands:
		var result := Rummy.evaluate_hand(sample.groups, sample.joker)
		var types: Array = result.melds.map(func(meld: Dictionary) -> String: return meld.type)
		if result.valid:
			valid_hands += 1
		if result.valid != sample.valid or result.points != int(sample.points) or types != sample.types:
			mismatches += 1
			if mismatches <= 5:
				print("hand mismatch: server=[%s, %s] godot=[%s, %s]" % [sample.valid, sample.points, result.valid, result.points])

		# Sorting must keep every card exactly once
		var cards: Array = []
		for group: Array in sample.groups:
			cards.append_array(group)
		var sorted_ids := {}
		for group: Array in Rummy.sort_into_groups(cards):
			for id: Variant in group:
				sorted_ids[id] = true
		if sorted_ids.size() != cards.size():
			mismatches += 1

	print("meld types seen: %s" % [seen])
	print("rules cross-check: %d mismatches over %d melds and %d hands (%d valid declarations)" % [
		mismatches, data.melds.size(), data.hands.size(), valid_hands
	])
	get_tree().quit(1 if mismatches > 0 else 0)


func _codes(cards: Array) -> String:
	return " ".join(cards.map(func(card: Dictionary) -> String: return card.code))
