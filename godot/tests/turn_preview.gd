extends Control
## Shows the table with four players and no server, passes the turn round the table and saves
## a picture at each step: our own turn, the turn of the player before us (we are next), and
## the turn of someone further round. Use it to look at the turn highlight after a change.
##
## Run WITH a window (not --headless), from godot/:
##   godot --path . res://tests/turn_preview.tscn -- --profile=turnpreview --mute --shots=<folder>
## Add --resolution 1600x720 before the scene to see a tall phone's shape.

const SEATS := [
	{"id": "1", "username": "Sujin"},
	{"id": "2", "username": "Arun"},
	{"id": "3", "username": "Priya"},
	{"id": "4", "username": "Kavin"},
]

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
	_set_turn("1")
	var hand: Array = Game.state.hand
	Game.groups = [hand.slice(0, 4).map(_id), hand.slice(4, 7).map(_id), hand.slice(7).map(_id)]
	var table: Control = (load("res://scenes/table.tscn") as PackedScene).instantiate()
	add_child(table)
	_run(table)


func _run(table: Control) -> void:
	await _wait(2.0)  # the deal
	var mine: PlayerBadge = table._my_badge
	var badges: Dictionary = table._badges
	_check("our turn: our badge and cards are lit", mine._glow == 1.0 and table._hand_light == 1.0)
	_check("our turn: Arun plays next", badges["2"].up_next and not badges["3"].up_next)
	await _shot("our-turn")

	_set_turn("2")
	await _wait(0.12)
	await _shot("light-moving")  # halfway through the fade
	await _wait(0.6)
	_check("Arun's turn: only his badge is lit", badges["2"]._glow == 1.0 and mine._glow == 0.0 and table._hand_light == 0.0)
	_check("Arun's turn: Priya plays next", badges["3"].up_next and not mine.up_next)
	await _shot("arun-turn")

	_set_turn("4")
	await _wait(0.7)
	_check("Kavin's turn: we play next", mine.up_next and badges["4"]._glow == 1.0 and badges["2"]._glow == 0.0)
	_check("Kavin's turn: the status line says we are next", table._status_label.text == "Waiting for Kavin  ·  You're next", table._status_label.text)
	await _shot("kavin-turn-we-are-next")

	# Priya drops out of the round: after Arun comes Kavin, not her
	_set_turn("2", "3")
	await _wait(0.7)
	_check("a dropped player is skipped as next", badges["4"].up_next and not badges["3"].up_next)
	await _shot("arun-turn-priya-dropped")

	print("turn preview: %d passed, %d failed" % [_passed, _failed])
	Game.socket.is_online = false
	Game.state = {}
	get_tree().quit(1 if _failed > 0 else 0)


# The table as the server would send it, with `current` on turn and `dropped` out of the round.
func _set_turn(current: String, dropped: String = "") -> void:
	var players: Array = []
	for seat: Dictionary in SEATS:
		var player := seat.duplicate()
		player.merge({"status": "dropped" if seat.id == dropped else "active", "connected": true, "handCount": 13, "avatar": 0})
		players.append(player)
	var hand: Array = []
	for code: String in ["2♠", "3♠", "4♠", "5♠", "7♥", "8♥", "9♥", "K♦", "K♣", "K♥", "4♣", "9♦", "Q♠"]:
		hand.append({"id": code + "-1", "suit": code.right(1), "value": code.left(-1), "code": code, "isJoker": false})
	Game.state = {
		"gameId": "preview", "roomCode": "PRVW42", "gameType": "points", "status": "playing",
		"currentPlayer": current, "turnPhase": "draw", "declaredBy": null, "players": players,
		"hand": hand, "groups": [], "discardTop": {"id": "6♦-1", "suit": "♦", "value": "6", "code": "6♦", "isJoker": false},
		"deckCount": 51, "joker": {"id": "A♣-2", "suit": "♣", "value": "A", "code": "A♣", "isJoker": false},
		"round": 1, "maxPlayers": 4,
	}
	Game.turn_total = 30000
	Game.turn_ends_at = Time.get_ticks_msec() + 21000  # a turn a third gone, to see the clock ring
	Game.state_changed.emit()


func _id(card: Dictionary) -> String:
	return str(card.id)


func _shot(label: String) -> void:
	_step += 1
	if _shots.is_empty() or DisplayServer.get_name() == "headless":
		return
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("%s/%02d-%s.png" % [_shots, _step, label])


func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout


func _check(what: String, ok: bool, detail: String = "") -> void:
	if ok:
		_passed += 1
	else:
		_failed += 1
		print("FAIL  %s  %s" % [what, detail])
