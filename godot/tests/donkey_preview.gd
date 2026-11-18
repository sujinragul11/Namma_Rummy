extends Control
# Donkey Master without a server: the home menu with the switch between the two games, the
# Donkey Master home and its boxes, saved as pictures. Run WITH a window (it can lie off screen):
#   godot --path . res://tests/donkey_preview.tscn --position -6000,-6000 -- --profile=donkeypreview --mute --server=http://127.0.0.1:9 --shots=<folder>

var _shots := ""
var _step := 0
var _failures := 0
var _main: Control


func _ready() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--shots="):
			_shots = argument.trim_prefix("--shots=")
	DirAccess.make_dir_recursive_absolute(_shots)
	# A fake login: enough for the menu to show, no server is asked anything
	Game.remember_login = false
	Game.token = "preview"
	Game.user = {"id": 1, "username": "Sujin"}
	Game.player_id = "1"
	Game.coins = 155060
	_main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	_main.set("wait_for_server", false)  # no server here: the menu at once
	add_child(_main)
	_run()


func _run() -> void:
	await _wait(0.8)
	await _shot("menu")
	_top_bar_report()
	var switch: Button = _node("GameSwitchButton")
	_check("the game switch sits right before the daily bonus", switch != null and switch.get_index() + 1 == _node("BonusButton").get_index())
	_check("Free Coins still right after the daily bonus", _node("FreeCoinsButton").get_index() == _node("BonusButton").get_index() + 1)
	_check("the top bar fits", _node("FreeCoinsButton").get_global_rect().end.x < _node("HelpButton").get_global_rect().position.x)
	switch.pressed.emit()
	await _wait(0.9)
	await _shot("donkey-home")
	_check("donkey home on show, tiles hidden", _node("DonkeyHome").is_visible_in_tree() and not _node("CloseJokerTile").is_visible_in_tree())
	(_node("DonkeyOnlineCard") as Button).pressed.emit()
	await _wait(0.6)
	await _shot("online-setup")
	(_node("DonkeySetupCloseButton") as Button).pressed.emit()
	(_node("DonkeyFriendsCard") as Button).pressed.emit()
	await _wait(0.6)
	await _shot("room-box")
	(_node("DonkeyCreateRoomButton") as Button).pressed.emit()
	await _wait(0.6)
	await _shot("private-setup")
	(_node("DonkeySetupCloseButton") as Button).pressed.emit()
	Game.donkey.search = {"maxPlayers": 6, "stake": 500}
	Game.donkey.search_status = {"found": 3, "needed": 6, "scope": "nearby", "region": "UTC+5:30", "inQueue": 4}
	Game.donkey.search_since = Time.get_ticks_msec() - 9000
	(_node("DonkeySearch") as DonkeySearch).open_for(DonkeyHome.describe_table(6, 500))
	await _wait(0.8)
	await _shot("search")
	Game.donkey.search = {}
	(_node("DonkeySearch") as DonkeySearch).close()
	(_node("HelpButton") as Button).pressed.emit()
	await _wait(0.5)
	await _shot("rules")
	(_node("RulesCloseButton") as Button).pressed.emit()
	switch.pressed.emit()
	await _wait(0.8)
	_check("back on the rummy tiles", _node("CloseJokerTile").is_visible_in_tree() and not _node("DonkeyHome").is_visible_in_tree())
	await _tables()


# Made-up table states, fed to Game.donkey as the server would send them.
func _tables() -> void:
	var names := ["Sujin", "Arun", "Priya", "Karthik", "Meena", "Ravi", "Divya", "Selva"]
	var seats := 8
	var players: Array = []
	for index in seats:
		players.append({"id": str(index + 1), "username": names[index], "avatar": 0, "seat": index, "cards": 0,
			"connected": true, "left": false, "away": false, "out": false, "place": 0, "donkey": false})
	var state := {"roomId": "r1", "roomCode": "KZT4QX", "private": true, "hostId": "1", "maxPlayers": 8, "stake": 500,
		"pot": 500 * seats, "status": "waiting", "players": players.slice(0, 3), "hand": [], "turn": "", "trick": [],
		"trickEnd": {}, "lastTrick": {}, "mustLead": "", "playable": [], "discarded": 0, "results": []}
	Game.donkey._apply_state(state.duplicate(true))
	await _wait(0.9)
	await _shot("lobby")
	_check("the lobby is on screen", _node("DonkeyLobby") != null and _node("DonkeyStartButton").visible)

	var hand: Array = []
	for card_id: String in ["2♠", "9♠", "Q♠", "4♥", "J♥", "A♥", "3♣", "8♣", "K♣", "5♦", "6♦"]:
		hand.append({"id": card_id, "suit": card_id.right(1), "value": card_id.left(-1)})
	for index in seats:
		players[index]["cards"] = [11, 6, 7, 5, 6, 7, 6, 5][index]
	players[3]["place"] = 1
	players[3]["out"] = true
	players[3]["cards"] = 0
	players[6]["away"] = true
	state.merge({"status": "playing", "players": players, "hand": hand, "turn": "1", "turnTimeLeft": 11000, "turnSeconds": 15,
		"trickNo": 9, "leader": "6", "leadSuit": "♥", "discarded": 14,
		"trick": [{"playerId": "6", "card": {"id": "10♥", "suit": "♥", "value": "10"}}, {"playerId": "7", "card": {"id": "2♥", "suit": "♥", "value": "2"}},
			{"playerId": "8", "card": {"id": "7♥", "suit": "♥", "value": "7"}}],
		"playable": ["4♥", "J♥", "A♥"]}, true)
	Game.donkey._apply_state(state.duplicate(true))
	await _wait(1.6)
	await _shot("table-my-turn")
	_check("the table is on screen with my 11 cards", _node("DonkeyTable") != null and _count_cards() == 14, str(_count_cards()))
	var jack: CardView = _node("DonkeyCard_J♥".validate_node_name())
	jack.tapped.emit("J♥")
	await _wait(0.4)
	await _shot("table-picked")
	_check("PLAY shows over the picked card", _node("DonkeyPlayButton").visible)

	# Arun cuts with a club: Selva picks the trick up
	state["trick"].append({"playerId": "1", "card": {"id": "J♥", "suit": "♥", "value": "J"}})
	hand = hand.filter(func(card: Dictionary) -> bool: return card.id != "J♥")
	state["hand"] = hand
	state["trick"].append({"playerId": "2", "card": {"id": "9♣", "suit": "♣", "value": "9"}})
	state.merge({"turn": "", "turnTimeLeft": null, "playable": [], "trickEnd": {"outcome": "pickup", "by": "1", "cutBy": "2", "highest": "1"}}, true)
	Game.donkey._apply_state(state.duplicate(true))
	await _wait(0.5)
	await _shot("table-cut")
	var picked: Array = []
	for play: Dictionary in state["trick"]:
		picked.append(play.card)
	hand.append_array(picked)
	state.merge({"hand": hand, "trick": [], "trickEnd": {}, "trickNo": 10, "turn": "1", "turnTimeLeft": 15000, "leadSuit": "",
		"lastTrick": {"outcome": "pickup", "by": "1", "cutBy": "2", "highest": "1", "no": 9}, "playable": hand.map(func(card: Dictionary) -> String: return card.id)}, true)
	Game.donkey._apply_state(state.duplicate(true))
	await _wait(1.2)
	await _shot("table-picked-up")
	_check("the trick came into my hand", _count_cards() == hand.size(), "%d / %d" % [_count_cards(), hand.size()])
	# Every card answers a finger on the part of it that shows, also the ones just picked up
	# (made later than their neighbours, they must not take the neighbours' taps)
	await _wait(0.6)
	var table: Variant = _node("DonkeyTable")
	var wrong: Array = []
	for card: Dictionary in Game.donkey.hand():
		_tap(_card_spot(table, card.id))
		if table._picked != card.id:
			wrong.append("%s->%s" % [card.id, table._picked])
		table._picked = ""
		table._layout(false)
	_check("a tap on any card of the hand picks that card", wrong.is_empty(), str(wrong))

	# The end: Arun is the Donkey
	for index in seats:
		players[index].merge({"cards": 0, "out": true, "place": index + 1 if index != 1 else 0}, true)
	players[1].merge({"cards": 3, "donkey": true}, true)
	players[0]["place"] = 2
	players[3]["place"] = 1
	var results: Array = []
	for index in [3, 0, 2, 4, 5, 6, 7, 1]:
		if index < seats:
			results.append({"id": players[index].id, "username": players[index].username, "place": players[index].place,
				"donkey": index == 1, "left": false, "coins": 500 if index == 3 else (-500 if index == 1 else 0)})
	state.merge({"status": "finished", "players": players, "hand": [], "trick": [], "turn": "", "turnTimeLeft": null,
		"masterId": "4", "donkeyId": "2", "results": results, "endedBy": "play", "lastTrick": {}}, true)
	Game.donkey._apply_state(state.duplicate(true))
	await _wait(1.0)
	await _shot("finished-donkey")
	await _wait(DonkeyTable.RESULT_DELAY + 0.6)
	await _shot("result")
	_check("the result box is up", _node("DonkeyResult").visible and _node("DonkeyResultRows").get_child_count() == seats)


# The middle of the strip of a hand card that the next card does not cover.
func _card_spot(table: Variant, id: String) -> Vector2:
	var view: CardView = table._views[id]
	var right := view.global_position.x + view.size.x
	for other: CardView in table._views.values():
		if other != view and other.has_meta("in_hand") and other.global_position.x > view.global_position.x and other.global_position.x < right:
			right = other.global_position.x
	return Vector2((view.global_position.x + right) / 2.0, view.global_position.y + 34.0)


func _tap(at: Vector2) -> void:
	for down: bool in [true, false]:
		var event := InputEventScreenTouch.new()
		event.index = 0
		event.pressed = down
		event.position = get_viewport().get_final_transform() * at
		Input.parse_input_event(event)
		Input.flush_buffered_events()


func _count_cards() -> int:
	var layer: Node = _node("DonkeyCardLayer")
	return 0 if layer == null else layer.get_children().filter(func(view: Node) -> bool: return not view.is_queued_for_deletion()).size()
	print("donkey_preview: %d pictures in %s, %d failed checks" % [_step, _shots, _failures])
	Sound.hush()
	get_tree().quit(1 if _failures > 0 else 0)


func _top_bar_report() -> void:
	var bar: Node = _main.find_child("TopBar", true, false)
	for child: Control in bar.get_children():
		print("  %-18s %s" % [child.name, child.get_global_rect()])


func _check(what: String, ok: bool, detail: String = "") -> void:
	if ok:
		print("  ok    ", what)
	else:
		_failures += 1
		print("  FAIL  ", what, "  ", detail)


func _node(node_name: String) -> Node:
	return _main.find_child(node_name, true, false)


func _shot(label: String) -> void:
	_step += 1
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("%s/%02d-%s.png" % [_shots, _step, label])


func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout
