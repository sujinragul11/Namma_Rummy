extends Control
# Request Card at the Donkey Master table without a server: made-up table states for each step
# (the pills under the neighbours' seats between tricks, our own request waiting, a request to
# us with Accept and Reject, Accept held back while our card is in the trick, a whole hand
# received, a rejected request seen by someone else), checked and saved as pictures.
# Run WITH a window (it can lie off screen):
#   godot --path . res://tests/donkey_request_preview.tscn --position -6000,-6000 -- --profile=requestpreview --mute --server=http://127.0.0.1:9 --shots=<folder>

var _shots := ""
var _step := 0
var _failures := 0
var _main: Control


func _ready() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--shots="):
			_shots = argument.trim_prefix("--shots=")
	if not _shots.is_empty():
		DirAccess.make_dir_recursive_absolute(_shots)
	Game.remember_login = false
	Game.token = "preview"
	Game.user = {"id": 1, "username": "Sujin"}
	Game.player_id = "1"
	Game.coins = 50000
	_main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	_main.set("wait_for_server", false)
	add_child(_main)
	_run()


func _run() -> void:
	await _wait(0.8)
	var names := ["Sujin", "Arun", "Priya", "Karthik"]
	var players: Array = []
	for index in 4:
		players.append({"id": str(index + 1), "username": names[index], "avatar": 0, "seat": index, "cards": [10, 6, 9, 7][index],
			"connected": true, "left": false, "away": false, "out": false, "place": 0, "donkey": false})
	var hand := _cards(["2♠", "9♠", "Q♠", "4♥", "J♥", "3♣", "8♣", "K♣", "5♦", "6♦"])
	# Between tricks, our lead: we may ask Arun (on our left) or Karthik (on our right)
	var state := {"roomId": "r1", "roomCode": "", "private": false, "hostId": "1", "maxPlayers": 4, "stake": 500, "pot": 2000,
		"status": "playing", "players": players, "hand": hand, "turn": "1", "turnTimeLeft": 14000, "turnSeconds": 15,
		"trickNo": 6, "leader": "1", "leadSuit": "", "trick": [], "trickEnd": {}, "lastTrick": {}, "mustLead": "",
		"playable": hand.map(func(card: Dictionary) -> String: return card.id), "discarded": 9, "masterId": "", "donkeyId": "",
		"results": [], "endedBy": "", "requests": [], "neighbours": ["2", "4"], "canRequest": true, "requestWait": 0,
		"requestSeconds": 10, "requestGapSeconds": 10}
	Game.donkey._apply_state(state.duplicate(true))
	await _wait(1.6)
	await _shot("pills")
	var pill_left: Button = _node("RequestCardButton_2")
	var pill_right: Button = _node("RequestCardButton_4")
	_check("a Request Your Card pill under each neighbour, none for the player across", pill_left != null and pill_right != null and _node("RequestCardButton_3") == null)
	_check("they read Request Your Card and are bright", pill_left.text == "Request Your Card" and pill_left.modulate.a > 0.9)
	for id: String in ["2", "4"]:
		var seat: DonkeySeat = _node("DonkeySeat_" + id)
		var pill: Button = _node("RequestCardButton_" + id)
		var rect := pill.get_global_rect()
		_check("%s's pill is next to the seat" % names[int(id) - 1], rect.get_center().distance_to(seat.avatar_center()) < 220.0, "%s / %s" % [rect, seat.avatar_center()])
		var pile: Control = _node("DonkeyPile")
		_check("and clear of the pile of cards out", not rect.intersects(pile.get_global_rect().grow(4.0)), "%s / %s" % [rect, pile.get_global_rect()])
		var covers: Array = []
		for other: String in ["1", "2", "3", "4"]:
			var picture := Rect2(_seat(other).avatar_center() - Vector2.ONE * 40.0, Vector2.ONE * 80.0)
			if rect.intersects(picture):
				covers.append(names[int(other) - 1])
		_check("and covers no player's picture", covers.is_empty(), str(covers))
		_check("on the screen", get_viewport().get_visible_rect().encloses(rect), str(rect))
	_check("no throw button covers a pill", _throws_clear(), "")

	# Our request to Arun waits for his answer
	state.merge({"requests": [{"id": "r1", "from": "1", "to": "2", "status": "pending", "expiresIn": 7000, "moved": 0}], "requestWait": 9000}, true)
	Game.donkey._apply_state(state.duplicate(true))
	await _wait(0.6)
	await _shot("asking")
	_check("Arun's seat says ASKED, ours ASKING", _seat("2").request_tag == "ASKED" and _seat("1").request_tag == "ASKING")
	_check("the time runs down on the tag", _seat("2").request_left > 0.4 and _seat("2").request_left < 0.8, str(_seat("2").request_left))
	_check("the pills wait", pill_left.text == "Waiting..." and pill_left.modulate.a < 0.9, pill_left.text)

	# Karthik asks us
	state.merge({"requests": [{"id": "r2", "from": "4", "to": "1", "status": "pending", "expiresIn": 8000, "moved": 0}], "requestWait": 0}, true)
	Game.donkey._apply_state(state.duplicate(true))
	await _wait(0.8)
	await _shot("asked")
	var box: Control = _node("CardRequestBox")
	_check("the box asks us, with Accept and Reject", box.visible and _node("CardRequestTitle").text == "Karthik asks for your cards"
		and not (_node("CardRequestAccept") as Button).disabled, _node("CardRequestTitle").text)
	_check("it says what accepting means", (_node("CardRequestText").text as String).begins_with("Accept: all 10 of your cards go to Karthik"))
	_check("the box is on the screen", get_viewport().get_visible_rect().encloses(box.get_global_rect()), str(box.get_global_rect()))
	_check("no throw button covers the box", _throws_clear(), "")
	var pressed := [false]
	(_node("CardRequestReject") as Button).pressed.connect(func() -> void: pressed[0] = true, CONNECT_ONE_SHOT)
	_tap((_node("CardRequestReject") as Control).get_global_rect().get_center())
	_check("Reject answers a finger", pressed[0])
	await _wait(0.2)
	Ui.close_dialogs()  # no server here: the answer could not be sent
	Game.donkey._apply_state(state.duplicate(true))  # the server has not answered here: still asked
	await _wait(0.4)

	# Our card is in the trick: Accept waits until the trick is over
	state.merge({"turn": "2", "leadSuit": "♠", "trick": [{"playerId": "1", "card": {"id": "9♠", "suit": "♠", "value": "9"}}],
		"hand": hand.filter(func(card: Dictionary) -> bool: return card.id != "9♠"), "playable": []}, true)
	Game.donkey._apply_state(state.duplicate(true))
	await _wait(0.8)
	await _shot("asked-card-in-trick")
	_check("Accept is held back while our card is in the trick", (_node("CardRequestAccept") as Button).disabled
		and (_node("CardRequestText").text as String).ends_with("You can accept once this trick is over."))

	# Arun accepted our request: his six cards are ours, he is out and the Master
	var received := _cards(["3♥", "7♥", "10♣", "A♣", "2♦", "J♦"])
	hand = hand.filter(func(card: Dictionary) -> bool: return card.id != "9♠")
	var bigger := hand + received
	players[1].merge({"cards": 0, "out": true, "place": 1}, true)
	players[0]["cards"] = bigger.size()
	state.merge({"turn": "1", "leadSuit": "", "trick": [], "trickNo": 7, "hand": bigger, "players": players, "masterId": "2",
		"playable": bigger.map(func(card: Dictionary) -> String: return card.id), "neighbours": ["3", "4"],
		"requests": [{"id": "r1", "from": "1", "to": "2", "status": "accepted", "expiresIn": 0, "moved": 6}], "requestWait": 4000}, true)
	Game.donkey._apply_state(state.duplicate(true))
	await _wait(0.3)
	await _shot("cards-arriving")
	await _wait(1.2)
	await _shot("received")
	_check("the box is gone", not box.visible)
	_check("all of Arun's cards are in our hand", _count_hand() == bigger.size(), "%d / %d" % [_count_hand(), bigger.size()])
	_check("our seat says +6 CARDS, Arun's MASTER", _seat("1").request_tag == "+6 CARDS")
	_check("Arun, out, has no pill; Priya, now next to us, has one", _node("RequestCardButton_2") == null and _node("RequestCardButton_3") != null)

	# Priya asked Karthik, who rejected: we only watch
	state.merge({"requests": [{"id": "r3", "from": "3", "to": "4", "status": "rejected", "expiresIn": 0, "moved": 0}]}, true)
	Game.donkey._apply_state(state.duplicate(true))
	await _wait(0.6)
	await _shot("rejected-seen")
	_check("Karthik's seat says REJECTED for everyone", _seat("4").request_tag == "REJECTED")

	# The game is over: requests left in the state show no more
	state.merge({"status": "finished", "results": []}, true)
	Game.donkey._apply_state(state.duplicate(true))
	await _wait(0.4)
	_check("after the game no request tags", _seat("4").request_tag.is_empty())

	print("donkey_request_preview: %d pictures, %d failed checks" % [_step, _failures])
	Sound.hush()
	get_tree().quit(1 if _failures > 0 else 0)


func _cards(ids: Array) -> Array:
	var cards: Array = []
	for card_id: String in ids:
		cards.append({"id": card_id, "suit": card_id.right(1), "value": card_id.left(-1)})
	return cards


func _seat(id: String) -> DonkeySeat:
	return _node("DonkeySeat_" + id)


# No button for throwing things lies over a Request Card control
func _throws_clear() -> bool:
	var controls: Array = (_node("DonkeyRequests") as DonkeyRequests).controls()
	for node: Node in _main.find_children("ThrowButton*", "", true, false):
		var button := node as Control
		if button == null or not button.is_visible_in_tree():
			continue
		for control: Control in controls:
			if control.is_visible_in_tree() and control.get_global_rect().intersects(button.get_global_rect()):
				print("    throw button %s over %s" % [button.name, control.name])
				return false
	return true


func _count_hand() -> int:
	var table: Variant = _node("DonkeyTable")
	return table._views.values().filter(func(view: CardView) -> bool: return view.has_meta("in_hand")).size()


func _tap(at: Vector2) -> void:
	for down: bool in [true, false]:
		var event := InputEventScreenTouch.new()
		event.index = 0
		event.pressed = down
		event.position = get_viewport().get_final_transform() * at
		Input.parse_input_event(event)
		Input.flush_buffered_events()


func _node(node_name: String) -> Variant:
	return _main.find_child(node_name, true, false)


func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout


func _shot(label: String) -> void:
	_step += 1
	if DisplayServer.get_name() == "headless" or _shots.is_empty():
		return
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("%s/%02d-%s.png" % [_shots, _step, label])


func _check(what: String, ok: bool, detail: String = "") -> void:
	if ok:
		print("  ok    ", what)
	else:
		_failures += 1
		print("  FAIL  ", what, "  ", detail)
