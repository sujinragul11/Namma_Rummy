extends Control
## Shows the voice chat at a table with no server: the Mic and Speaker switches by our coins,
## a microphone on the pictures of the players whose microphone is on, and the green ring
## round whoever speaks. Saves a picture of each step. Use it to look at the voice chat after
## a change; it also checks that the switches lie clear of the cards, buttons and seats.
##
## Run WITH a window (not --headless), from godot/:
##   godot --path . res://tests/voice_preview.tscn -- --profile=voicepreview --mute --players=6 --shots=<folder>
## --players is 2 to 6 (default 6). Add --resolution 1600x720 before the scene for a tall phone.

const NAMES := ["Sujin", "Arun", "Priya", "Kavin", "Meena", "Ravi"]

var _shots := ""
var _seats := 6
var _step := 0
var _passed := 0
var _failed := 0
var _talking: Dictionary = {}  # user id -> how loud they speak in this picture


func _ready() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--shots="):
			_shots = argument.trim_prefix("--shots=")
		elif argument.begins_with("--players="):
			_seats = clampi(int(argument.trim_prefix("--players=")), 2, 6)
	if not _shots.is_empty():
		DirAccess.make_dir_recursive_absolute(_shots)
	theme = Ui.game_theme
	# A fake seat at a table: enough for the table to draw, no server is asked anything
	Game.remember_login = false
	Game.token = "preview"
	Game.user = {"id": 1, "username": "Sujin"}
	Game.player_id = "1"
	Game.socket.is_online = true  # or the status line says "Reconnecting..."
	_set_table()
	var hand: Array = Game.state.hand
	Game.groups = [hand.slice(0, 4).map(func(card: Dictionary) -> String: return str(card.id)), hand.slice(4).map(func(card: Dictionary) -> String: return str(card.id))]
	var table: Control = (load("res://scenes/table.tscn") as PackedScene).instantiate()
	add_child(table)
	_run(table)


func _process(_delta: float) -> void:
	# The others "speak": as if their sound kept arriving
	var voice := Game.voice
	for id: String in _talking:
		var speaker: VoiceChat.Speaker = voice._speaker(id)
		speaker.level = _talking[id] * (0.75 + 0.25 * sin(Time.get_ticks_msec() / 90.0))
		speaker.heard_at = Time.get_ticks_msec()


func _run(table: Control) -> void:
	await _wait(2.0)  # the deal
	var voice := Game.voice
	var switches: Control = table.find_child("VoiceSwitches", true, false)
	_check("the voice switches sit after our coins", switches != null and switches.get_index() == table._my_coins_pill.get_index() + 1)
	_check("Mic starts off, Speaker on", not voice.mic_on and voice.speaker_on)
	_check("the voice switches are clear of everything else", _overlaps(table, switches).is_empty(), _overlaps(table, switches))
	await _shot("voice-off")

	# Arun and Meena have their microphones on; Arun speaks
	voice._mics = {"2": true, "5": true}
	_talking = {"2": 0.8}
	await _wait(0.5)
	var arun: PlayerBadge = table._badges["2"]
	_check("a microphone shows on Arun's picture", arun.mic_on)
	_check("and the ring round it while he speaks", arun.voice_level > 0.3, str(arun.voice_level))
	var priya: PlayerBadge = table._badges.get("3")
	_check("not on Priya, whose microphone is off", priya == null or (not priya.mic_on and priya.voice_level == 0.0))
	await _shot("arun-speaks")

	# We switch our own microphone on and speak too
	voice.mic_on = true
	voice._mics["1"] = true
	voice._hang = VoiceChat.HANG_FRAMES
	voice._my_level = 0.7
	voice.changed.emit()
	_talking = {"2": 0.3, "5": 1.0}
	await _wait(0.5)
	_check("our own picture shows us speaking", table._my_badge.mic_on and table._my_badge.voice_level > 0.3)
	await _shot("we-and-meena-speak")

	# Quiet again: the rings go, the microphones stay
	_talking = {}
	voice._hang = 0
	await _wait(1.5)
	_check("when nobody speaks the rings go", arun.voice_level == 0.0 and table._my_badge.voice_level == 0.0)
	_check("the microphones stay", arun.mic_on and table._my_badge.mic_on)
	voice.set_speaker(false)
	voice.asking = false
	await _wait(0.2)
	await _shot("speaker-off")
	voice.mic_on = false
	voice.asking = true  # as while the phone asks for the microphone
	voice.changed.emit()
	await _wait(0.3)
	await _shot("asking-for-the-microphone")
	voice.asking = false
	voice.set_speaker(true)

	print("voice preview: %d passed, %d failed" % [_passed, _failed])
	voice._mics = {}
	Game.socket.is_online = false
	Game.state = {}
	get_tree().quit(1 if _failed > 0 else 0)


func _set_table() -> void:
	var players: Array = []
	for index in _seats:
		players.append({"id": str(index + 1), "username": NAMES[index], "status": "active", "connected": true, "handCount": 13, "avatar": 0})
	var hand: Array = []
	for code: String in ["2♠", "3♠", "4♠", "5♠", "7♥", "8♥", "9♥", "K♦", "K♣", "K♥", "4♣", "9♦", "Q♠"]:
		hand.append({"id": code + "-1", "suit": code.right(1), "value": code.left(-1), "code": code, "isJoker": false})
	Game.state = {
		"gameId": "preview", "roomCode": "PRVW42", "gameType": "points", "status": "playing",
		"currentPlayer": "2", "turnPhase": "draw", "declaredBy": null, "players": players,
		"hand": hand, "groups": [], "discardTop": {"id": "6♦-1", "suit": "♦", "value": "6", "code": "6♦", "isJoker": false},
		"deckCount": 51, "joker": {"id": "A♣-2", "suit": "♣", "value": "A", "code": "A♣", "isJoker": false},
		"round": 1, "maxPlayers": _seats,
	}
	Game.turn_total = 30000
	Game.turn_ends_at = Time.get_ticks_msec() + 21000
	Game.state_changed.emit()


# What the voice switches lie over: the other things in the bottom bar, the cards, a seat
func _overlaps(table: Control, switches: Control) -> String:
	if switches == null:
		return "no switches"
	var found: Array = []
	var others: Array = table._my_coins_pill.get_parent().get_children().filter(func(item: Control) -> bool: return item != switches and item.name != "Spacer")
	others.append(table._hand_area)
	others.append_array(table._badges.values())
	for other: Control in others:
		if other.is_visible_in_tree() and switches.get_global_rect().intersects(other.get_global_rect()):
			found.append(str(other.name))
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
