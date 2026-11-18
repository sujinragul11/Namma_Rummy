extends Control
## The chat, the emoji and the things thrown at a Donkey Master table, with no server: the chat
## and emoji buttons at the top right (the pot moved left of them), a throw button beside each
## opponent, a message bubble and an emoji on a seat, a cake flying from one picture to another
## and the picture it hits squashing and coming back. Saves a picture of each step and checks
## that the buttons lie clear of each other, the seats, the cards and the controls.
##
## Run WITH a window (it can lie off screen), from godot/:
##   godot --path . res://tests/donkey_social_preview.tscn --position -6000,-6000 -- --profile=donkeysocialpreview --mute --players=6 --shots=<folder>
## --players is 2 to 8 (default 6). Add --resolution 1600x720 before the scene for a tall phone.

const NAMES := ["Sujin", "Arun", "Priya", "Kavin", "Meena", "Ravi", "Divya", "Hari"]
const HAND := ["2♠", "7♠", "Q♠", "3♥", "9♥", "K♥", "4♣", "J♣", "A♣", "5♦", "8♦", "10♦"]

var _shots := ""
var _seats := 6
var _step := 0
var _passed := 0
var _failed := 0


func _ready() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--shots="):
			_shots = argument.trim_prefix("--shots=")
		elif argument.begins_with("--players="):
			_seats = clampi(int(argument.trim_prefix("--players=")), 2, 8)
	if not _shots.is_empty():
		DirAccess.make_dir_recursive_absolute(_shots)
	theme = Ui.game_theme
	# A fake seat at a table: enough for the table to draw, no server is asked anything
	Game.remember_login = false
	Game.token = "preview"
	Game.user = {"id": 1, "username": "Sujin"}
	Game.player_id = "1"
	Game.socket.is_online = true
	Game.donkey._apply_state(_state())
	var table := DonkeyTable.new()
	add_child(table)
	_run(table)


func _run(table: DonkeyTable) -> void:
	await _wait(1.5)
	var chat: TableChat = table._chat
	var throws: TableThrows = table.find_children("*", "TableThrows", false, false)[0]
	var chat_buttons: Control = chat.get_node("ChatButtons")
	_check("the chat belongs to this table", Game.table_id() == "preview-room" and Game.table_players().size() == _seats)
	_check("the chat and emoji buttons are at the top right", chat_buttons.get_global_rect().end.x > size.x - 30.0 and chat_buttons.get_global_rect().position.y < 30.0)
	var pot: Control = table._pot_label.get_parent()
	_check("the pot lies clear of them", not pot.get_global_rect().intersects(chat_buttons.get_global_rect()), "%s / %s" % [pot.get_global_rect(), chat_buttons.get_global_rect()])
	_check("a throw button beside every opponent", throws._buttons.size() == _seats - 1, "%d buttons" % throws._buttons.size())
	_check("the throw buttons cover nothing", _covered(table, throws).is_empty(), _covered(table, throws))
	_check("nor anyone's card count", throws._buttons.values().all(func(each: Button) -> bool: return table._seats.values().all(func(seat: DonkeySeat) -> bool: return not each.get_global_rect().intersects(seat.cards_rect()))))
	await _shot("table")

	# Arun writes, Priya laughs
	chat._on_chat_received({"id": 1, "gameId": "preview-room", "userId": "2", "username": "Arun", "at": 0, "kind": "text", "text": "Who has the ace of spades?"})
	chat._on_chat_received({"id": 2, "gameId": "preview-room", "userId": "3", "username": "Priya", "at": 0, "kind": "emoji", "emoji": "laugh"})
	await _wait(0.6)
	await _shot("bubble-and-emoji")

	# Kavin throws a cake at Arun
	var arun: DonkeySeat = table._seats["2"]
	throws._on_item_thrown({"id": 7, "from": "4", "to": "2", "item": "cake"})
	await _wait(0.3)
	await _shot("cake-flying")
	var squashed := false
	for frame in 90:
		await get_tree().process_frame
		if not arun.picture().scale.is_equal_approx(Vector2.ONE) or not is_zero_approx(arun.picture().rotation):
			squashed = true
			await _shot("cake-lands")
			break
	_check("Arun's picture reacts to the cake", squashed)
	await _wait(3.5)
	_check("and comes back to itself", arun.picture().scale.is_equal_approx(Vector2.ONE) and is_zero_approx(arun.picture().rotation) and arun.picture().modulate == Color.WHITE)

	# The choice of things to throw, and the chat panel
	var button: Button = throws._buttons.values()[0]
	button.pressed.emit()
	await _wait(0.4)
	await _shot("throw-choice")
	throws.close()
	chat._toggle_chat()
	await _wait(0.4)
	_check("the chat panel opens", chat.is_chat_open())
	var panel: Control = chat.get_node("ChatPanel")
	_check("no throw button lies over the open chat", throws._buttons.values().all(func(each: Button) -> bool: return not each.visible or not each.get_global_rect().intersects(panel.get_global_rect())))
	await _shot("chat-open")
	chat.close()

	print("donkey social preview: %d passed, %d failed" % [_passed, _failed])
	Game.socket.is_online = false
	Game.donkey.state = {}
	get_tree().quit(1 if _failed > 0 else 0)


func _state() -> Dictionary:
	var players: Array = []
	for index in _seats:
		players.append({
			"id": str(index + 1), "username": NAMES[index], "avatar": 0, "seat": index, "cards": 12 if index == 0 else 11,
			"connected": true, "left": false, "away": false, "out": false, "place": 0, "donkey": false,
		})
	var hand: Array = []
	for code: String in HAND:
		hand.append({"id": code, "suit": code.right(1), "value": code.left(-1)})
	return {
		"roomId": "preview-room", "roomCode": "DNKY42", "private": true, "hostId": "1",
		"maxPlayers": _seats, "stake": 500, "pot": 500 * _seats, "status": "playing",
		"players": players, "hand": hand, "turn": "3", "turnTimeLeft": 12000, "turnSeconds": 15,
		"trickNo": 2, "leader": "2", "leadSuit": "♥", "trick": [{"playerId": "2", "card": {"id": "Q♥", "suit": "♥", "value": "Q"}}],
		"trickEnd": {}, "lastTrick": {}, "mustLead": "", "playable": [], "discarded": 6,
	}


# What the throw buttons lie over: each other, a seat, the cards, a control
func _covered(table: DonkeyTable, throws: TableThrows) -> String:
	var found: Array = []
	var others: Array = table._keep_clear().filter(func(item: Variant) -> bool: return item is Control and (item as Control).is_visible_in_tree())
	others.append_array(table._seats.values())
	var buttons: Array = throws._buttons.values()
	for button: Button in buttons:
		var rect := button.get_global_rect()
		# At a crowded table a small button may sit on the corner of its own player's picture
		var own: Control = table._seats.get(String(button.name).trim_prefix("ThrowButton_"))
		for other: Control in others:
			if other != own and rect.intersects(other.get_global_rect().grow(-2.0)):
				found.append("%s over %s" % [button.name, other.name])
		for second: Button in buttons:
			if second != button and rect.intersects(second.get_global_rect()):
				found.append("%s over %s" % [button.name, second.name])
	return ", ".join(found)


func _shot(label: String) -> void:
	_step += 1
	if _shots.is_empty() or DisplayServer.get_name() == "headless":
		return
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("%s/%d-players-%02d-%s.png" % [_shots, _seats, _step, label])


func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout


func _check(what: String, ok: bool, detail: String = "") -> void:
	if ok:
		_passed += 1
	else:
		_failed += 1
		print("FAIL  %s  %s" % [what, detail])
