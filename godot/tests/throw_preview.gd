extends Control
## The things thrown at pictures, on a table with four players and no server: the buttons
## beside the opponents, the choice of items opened and closed with a finger, then every item
## thrown once (from us, at us, and between two opponents) with pictures in flight, on arrival
## and just after. Checks that each scene ends by itself, frees what it made, and leaves the
## picture as it was, and that a flood of throws is cut short.
##
## Run WITH a window for the pictures (with --headless every check still runs):
##   godot --path . res://tests/throw_preview.tscn -- --profile=throwpreview --mute --shots=<folder>
## Add --resolution 1600x720 before the scene to see a tall phone's shape.

const SEATS := [
	{"id": "1", "username": "Sujin"},
	{"id": "2", "username": "Arun"},
	{"id": "3", "username": "Priya"},
	{"id": "4", "username": "Kavin"},
]
## A full table, where the badges along the top sit close together.
const FULL_TABLE := [
	{"id": "1", "username": "Sujin"},
	{"id": "2", "username": "Arun"},
	{"id": "3", "username": "Priya"},
	{"id": "4", "username": "Kavin"},
	{"id": "5", "username": "Meena"},
	{"id": "6", "username": "Vijay"},
]
## Who throws at whom, in turn: us at someone, someone at us, one opponent at another.
const PAIRS := [["1", "3"], ["2", "1"], ["4", "2"], ["1", "4"], ["3", "2"]]
const FLIGHT := 0.7  # about how long an item is in the air

var _shots := ""
var _step := 0
var _passed := 0
var _failed := 0


func _ready() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--shots="):
			_shots = argument.trim_prefix("--shots=")
	if not _shots.is_empty():
		DirAccess.make_dir_recursive_absolute(_shots)
	theme = Ui.game_theme
	# A fake seat at a table: enough for the table to draw, no server is asked anything
	Game.remember_login = false
	Game.token = "preview"
	Game.user = {"id": 1, "username": "Sujin"}
	Game.player_id = "1"
	Game.socket.is_online = true  # or the status line says "Reconnecting..."
	_seat_table(SEATS)
	var table: Control = (load("res://scenes/table.tscn") as PackedScene).instantiate()
	add_child(table)
	_run(table)


func _run(table: Control) -> void:
	await _wait(2.0)  # the deal
	var throws: TableThrows = table.get_node_or_null("TableThrows")
	_check("the table has the throwing layer", throws != null)
	if throws == null:
		_finish()
		return
	var badges: Dictionary = table._badges
	var screen := Rect2(Vector2.ZERO, get_viewport_rect().size)

	# ---------- a button beside each opponent ----------
	for id: String in ["2", "3", "4"]:
		var button := throws.get_node_or_null("ThrowButton_" + id) as Button
		var badge: PlayerBadge = badges[id]
		_check("%s has a throw button" % id, button != null and button.is_visible_in_tree())
		if button == null:
			continue
		var box := button.get_global_rect()
		_check("%s's button is on the screen" % id, screen.encloses(box), str(box))
		_check("%s's button does not cover the badge" % id, not box.intersects(badge.get_global_rect()), "%s vs %s" % [box, badge.get_global_rect()])
		_check("%s's button sits at the height of the picture" % id, absf(box.get_center().y - badge.avatar_center().y) < 2.0)
		_check("%s's button covers nothing of the game" % id, _covers(table, box).is_empty(), str(_covers(table, box)))
	_check("there is no button beside our own badge", throws.get_node_or_null("ThrowButton_1") == null)
	await _shot("buttons")

	# ---------- the choice, opened and closed with a finger ----------
	var priya := throws.get_node("ThrowButton_3") as Button
	_tap(priya.get_global_rect().get_center())
	await _wait(0.3)
	var picker := throws.get_node("ThrowPicker") as Control
	_check("tapping the button opens the choice", throws.is_picker_open() and throws.target() == "3" and picker.visible)
	_check("the choice has every item", picker.find_children("Throw_*", "Button", true, false).size() == GameClient.THROWABLES.size())
	_check("the choice says whom it throws at", _label_text(picker).contains("Throw at Priya"), _label_text(picker))
	_check("the choice is on the screen", screen.encloses(picker.get_global_rect()), str(picker.get_global_rect()))
	await _shot("picker")
	# A tap on the table's Sort button closes it, and the Sort button still sorts: the choice
	# never swallows a tap meant for the game (offline for a moment, so nothing is sent)
	var groups_before: Array = Game.groups.duplicate(true)
	Game.socket.is_online = false
	_tap((table._sort_button as Button).get_global_rect().get_center())
	await _wait(0.3)
	Game.socket.is_online = true
	_check("a tap elsewhere closes it", not throws.is_picker_open() and not picker.visible)
	_check("and still does what it was meant for", Game.groups != groups_before, str(Game.groups))
	_tap(priya.get_global_rect().get_center())
	await _wait(0.25)
	_tap(priya.get_global_rect().get_center())
	await _wait(0.3)
	_check("its own button closes it again", not throws.is_picker_open())
	_tap((throws.get_node("ThrowButton_2") as Button).get_global_rect().get_center())
	await _wait(0.25)
	_check("the button of another player opens it for them", throws.target() == "2")
	throws.close()
	await _wait(0.2)

	# ---------- every item ----------
	for index in GameClient.THROWABLES.size():
		var item: String = GameClient.THROWABLES[index]
		var pair: Array = PAIRS[index % PAIRS.size()]
		var target: Control = (table._my_badge if pair[1] == "1" else badges[pair[1]]).picture()
		Game.item_thrown.emit({"id": index + 1, "gameId": "preview", "from": pair[0], "to": pair[1], "item": item})
		var toss_name := "Toss_%d" % (index + 1)
		_check("%s starts" % item, throws.has_node(toss_name))
		await _wait(FLIGHT * 0.5)
		await _shot("%s-1-flying" % item)
		await _wait(FLIGHT * 0.5 + 0.35)
		await _shot("%s-2-arriving" % item)
		await _wait(0.55)
		await _shot("%s-3-after" % item)
		var ended := await _until(func() -> bool: return not throws.has_node(toss_name), 3.5)
		_check("%s ends by itself" % item, ended)
		await _wait(0.25)
		_check("%s leaves the picture as it was" % item, target.scale.is_equal_approx(Vector2.ONE) and is_zero_approx(target.rotation) and target.modulate.is_equal_approx(Color.WHITE), "%s %s %s" % [target.scale, target.rotation, target.modulate])

	# ---------- a flood ----------
	for index in 9:
		Game.item_thrown.emit({"id": 100 + index, "gameId": "preview", "from": "2", "to": "3", "item": "tomato"})
	var playing := throws.find_children("Toss_*", "", false, false).size()
	_check("a flood of throws is cut short", playing == TableThrows.MAX_SHOWN, str(playing))
	await _shot("flood")
	_check("the flood ends too", await _until(func() -> bool: return throws.find_children("Toss_*", "", false, false).is_empty(), 4.0))
	_check("a throw at someone not on screen is ignored", _throw_count_after(throws, {"id": 200, "from": "2", "to": "99", "item": "cake"}) == 0)

	# ---------- the buttons at a full table and at a table for two ----------
	for seats: Array in [FULL_TABLE, SEATS.slice(0, 2)]:
		_seat_table(seats)
		await _wait(0.6)
		var badges_now: Dictionary = table._badges
		var everyone: Array = badges_now.values() + [table._my_badge]
		for seat: Dictionary in seats.slice(1):
			var button := throws.get_node_or_null("ThrowButton_" + str(seat.id)) as Button
			_check("%d players: %s has a button" % [seats.size(), seat.username], button != null and button.is_visible_in_tree())
			if button == null:
				continue
			var box := button.get_global_rect()
			# At a crowded table a smaller button may sit on the corner of the player's own picture
			var own: PlayerBadge = badges_now[str(seat.id)]
			var on_own := button.size.x < TableThrows.BUTTON_SIZE
			var covered: Array = everyone.filter(func(badge: PlayerBadge) -> bool:
				return badge.get_global_rect().intersects(box) and not (on_own and badge == own))
			_check("%d players: %s's button is on the screen and covers no other badge" % [seats.size(), seat.username], screen.encloses(box) and covered.is_empty(), str(box))
			_check("%d players: %s's button is big enough for a finger" % [seats.size(), seat.username], button.size.x >= TableThrows.SMALL_BUTTON)
			_check("%d players: %s's button covers nothing of the game" % [seats.size(), seat.username], _covers(table, box).is_empty(), str(_covers(table, box)))
		var buttons: Array = throws.find_children("ThrowButton_*", "", false, false)
		_check("%d players: no buttons for players who are not there" % seats.size(), buttons.size() == seats.size() - 1)
		for one in buttons.size():
			for other in range(one + 1, buttons.size()):
				_check("%d players: buttons %s and %s do not overlap" % [seats.size(), buttons[one].name, buttons[other].name], not (buttons[one] as Control).get_global_rect().intersects((buttons[other] as Control).get_global_rect()))
		await _shot("buttons-%d-players" % seats.size())

	# ---------- only while a round is played ----------
	Game.state.status = "round_over"
	Game.state_changed.emit()
	await _wait(0.2)
	_check("no buttons between rounds", throws.find_children("ThrowButton_*", "", false, false).is_empty())

	_finish()


func _finish() -> void:
	print("throw preview: %d passed, %d failed" % [_passed, _failed])
	Game.socket.is_online = false
	Game.state = {}
	get_tree().quit(1 if _failed > 0 else 0)


# The names of the table's own controls that `box` lies over.
func _covers(table: Control, box: Rect2) -> Array:
	var names: Array = []
	for control: Variant in table._keep_clear(table.get_node("TableChat")):
		if control is Control and (control as Control).is_visible_in_tree() and (control as Control).get_global_rect().intersects(box):
			names.append((control as Control).name)
	return names


func _throw_count_after(throws: TableThrows, toss: Dictionary) -> int:
	Game.item_thrown.emit(toss)
	return throws.find_children("Toss_*", "", false, false).size()


# The table as the server would send it, with Arun on turn.
func _seat_table(seats: Array) -> void:
	var players: Array = []
	for seat: Dictionary in seats:
		var player := seat.duplicate()
		player.merge({"status": "active", "connected": true, "handCount": 13, "avatar": 0})
		players.append(player)
	var hand: Array = []
	for code: String in ["2♠", "3♠", "4♠", "5♠", "7♥", "8♥", "9♥", "K♦", "K♣", "K♥", "4♣", "9♦", "Q♠"]:
		hand.append({"id": code + "-1", "suit": code.right(1), "value": code.left(-1), "code": code, "isJoker": false})
	Game.state = {
		"gameId": "preview", "roomCode": "PRVW42", "gameType": "points", "status": "playing",
		"currentPlayer": "2", "turnPhase": "draw", "declaredBy": null, "players": players,
		"hand": hand, "groups": [], "discardTop": {"id": "6♦-1", "suit": "♦", "value": "6", "code": "6♦", "isJoker": false},
		"deckCount": 51, "joker": {"id": "A♣-2", "suit": "♣", "value": "A", "code": "A♣", "isJoker": false},
		"round": 1, "maxPlayers": seats.size(),
	}
	Game.groups = [hand.slice(0, 4).map(_id), hand.slice(4, 7).map(_id), hand.slice(7).map(_id)]
	Game.turn_total = 30000
	Game.turn_ends_at = Time.get_ticks_msec() + 21000
	Game.state_changed.emit()


func _label_text(root: Node) -> String:
	var words := ""
	for label: Node in root.find_children("*", "Label", true, false):
		words += (label as Label).text + " "
	return words


func _id(card: Dictionary) -> String:
	return str(card.id)


func _to_window(at: Vector2) -> Vector2:
	return get_viewport().get_final_transform() * at


func _touch(at: Vector2, down: bool) -> void:
	var event := InputEventScreenTouch.new()
	event.index = 0
	event.pressed = down
	event.position = _to_window(at)
	Input.parse_input_event(event)
	Input.flush_buffered_events()


func _tap(at: Vector2) -> void:
	_touch(at, true)
	_touch(at, false)


func _shot(label: String) -> void:
	_step += 1
	if _shots.is_empty() or DisplayServer.get_name() == "headless":
		return
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("%s/%02d-%s.png" % [_shots, _step, label])


func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout


func _until(condition: Callable, seconds: float = 6.0) -> bool:
	var deadline := Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < deadline:
		if condition.call():
			return true
		await get_tree().process_frame
	return condition.call()


func _check(what: String, ok: bool, detail: String = "") -> void:
	if ok:
		_passed += 1
	else:
		_failed += 1
		print("FAIL  %s  %s" % [what, detail])
