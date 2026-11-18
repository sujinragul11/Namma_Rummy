extends Control
## Voice chat at the Donkey Master table, through the real screens and a real server. The
## Mic and Speaker switches stand beside our own seat, on the screen and clear of the hand and
## the other seats. Another player's microphone shows on their seat, and their voice swells
## the green ring there. Our Mic, tapped with a finger, reaches the other players at the table
## and nobody at another table; Speaker turns their voices off and on; leaving the table
## switches the microphone off. The microphones are recorded tones (VoiceChat.test_source).
##
## Run against a TEST server that has Donkey Master (it registers throwaway accounts):
##   godot --headless --path . res://tests/donkey_voice.tscn -- --profile=donkeyvoice --mute --server=http://127.0.0.1:<port>
## With a window (e.g. --position -6000,-6000 --resolution 1280x720) and --shots=<folder> it also
## saves pictures of the table: B speaking, and our own Mic on.

const PASSWORD := "secret12"

var _main: Control
var _passed := 0
var _failed := 0
var _url := ""
var _shots := ""
var _heard: Dictionary = {}  # GameClient -> pieces of the screen player's voice it received


func _ready() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--server="):
			_url = argument.trim_prefix("--server=")
		elif argument.begins_with("--shots="):
			_shots = argument.trim_prefix("--shots=")
	if not _shots.is_empty():
		DirAccess.make_dir_recursive_absolute(_shots)
	Game.remember_login = false
	Game.logout()
	_main = (load("res://scenes/main.tscn") as PackedScene).instantiate() as Control
	add_child(_main)
	_run()


func _run() -> void:
	var tag := "%06d%03d" % [int(Time.get_unix_time_from_system()) % 1000000, randi() % 1000]
	await _until(func() -> bool: return not _main.loading(), 20.0)

	# ---------- four players: three at one table, D at a table of their own ----------
	var r: Dictionary = await Game.register("va_" + tag, "+919%s1" % tag.substr(0, 8), PASSWORD)
	_check("the screen player registers", r.get("ok", false), str(r.get("error", "")))
	var b := _new_client()
	var c := _new_client()
	var d := _new_client()
	var digits := ["8", "7", "6"]
	for index in 3:
		var client: GameClient = [b, c, d][index]
		r = await client.register("v%s_%s" % ["bcd"[index], tag], "+91%s%s%d" % [digits[index], tag.substr(0, 8), index + 2], PASSWORD)
		_check("player %s registers" % "BCD"[index], r.get("ok", false), str(r.get("error", "")))
		_heard[client] = 0
		client.socket.event_received.connect(_on_event.bind(client))
	_check("everyone is connected", await _until(func() -> bool: return Game.is_online() and b.is_online() and c.is_online() and d.is_online(), 15.0))
	await _until(func() -> bool: return not _main.loading() and _has("MenuPanel"), 15.0)

	r = await Game.donkey.create_room(3, 0)
	var code := str(r.get("roomCode", ""))
	_check("a free private table for three", r.get("ok", false) and code.length() == 6, str(r))
	await b.donkey.join_room(code)
	await c.donkey.join_room(code)  # the third seat: the table deals by itself
	r = await d.donkey.create_room(2, 0)
	_check("D waits at a table of their own", r.get("ok", false), str(r))
	_check("the table is dealt and on screen", await _until(func() -> bool: return Game.donkey.status() == "playing" and _has("DonkeyTable"), 15.0))
	await _wait(1.2)  # the deal settles

	# ---------- the switches ----------
	var switches := _node("VoiceSwitches") as Control
	var mic := _node("MicSwitch") as Button
	var speaker := _node("SpeakerSwitch") as Button
	_check("Mic and Speaker are on the Donkey Master table", switches != null and mic != null and speaker != null and mic.is_visible_in_tree() and speaker.is_visible_in_tree())
	if switches == null or mic == null or speaker == null:
		_finish()
		return
	var box := switches.get_global_rect()
	var mine := _seat(Game.player_id)
	_check("beside our own seat, on its right, level with its picture", mine != null and box.position.x >= mine.get_global_rect().end.x - 1.0
		and absf(box.get_center().y - mine.avatar_center().y) < 40.0, "switches %s, seat %s" % [box, mine.get_global_rect() if mine != null else Rect2()])
	_check("inside the screen", get_viewport().get_visible_rect().encloses(box), str(box))
	var hand_clear := true
	for view: Node in _node("DonkeyCardLayer").get_children():
		if view is CardView and view.has_meta("in_hand") and (view as CardView).get_global_rect().intersects(box):
			hand_clear = false
	_check("clear of the hand", hand_clear)
	var seats_clear := true
	for seat: Node in _node("DonkeySeatLayer").get_children():
		if seat is DonkeySeat and seat != mine and (seat as DonkeySeat).get_global_rect().intersects(box):
			seats_clear = false
	_check("clear of the other seats", seats_clear)
	_check("nobody's microphone is on to begin with", not Game.voice.mic_on and not _seat(b.player_id).mic_on and not _seat(c.player_id).mic_on)

	# ---------- B speaks ----------
	b.voice.test_source = _tone(500.0)
	b.voice.set_mic(true)
	_check("B's microphone shows on B's seat", await _until(func() -> bool: return _seat(b.player_id).mic_on))
	_check("B's voice swells the green ring on B's seat", await _until(func() -> bool: return _seat(b.player_id).voice_level > 0.0, 8.0))
	_check("we hear B", Game.voice.level_of(b.player_id) > 0.0)
	await _shot("donkey-voice-b-speaking")
	_check("C's seat shows no microphone", not _seat(c.player_id).mic_on)
	b.voice.set_mic(false)
	_check("B's microphone off shows on B's seat", await _until(func() -> bool: return not _seat(b.player_id).mic_on))

	# ---------- our Mic, with a finger ----------
	Game.voice.test_source = _tone(300.0)
	_tap_button(mic)
	_check("a tap on Mic switches our microphone on", await _until(func() -> bool: return Game.voice.mic_on), _under_finger())
	_check("our own seat shows our microphone", await _until(func() -> bool: return _seat(Game.player_id).mic_on))
	_check("B and C see our microphone on", await _until(func() -> bool: return b.voice.has_mic(Game.player_id) and c.voice.has_mic(Game.player_id)))
	await _shot("donkey-voice-our-mic")
	_check("B and C hear us", await _until(func() -> bool: return _heard[b] >= 5 and _heard[c] >= 5, 8.0), "%d / %d" % [_heard[b], _heard[c]])
	_check("D, at another table, hears nothing and sees no microphone", _heard[d] == 0 and not d.voice.has_mic(Game.player_id), str(_heard[d]))

	_tap_button(speaker)
	_check("a tap on Speaker turns the others off", await _until(func() -> bool: return not Game.voice.speaker_on))
	_tap_button(speaker)
	_check("and on again", await _until(func() -> bool: return Game.voice.speaker_on))
	_tap_button(mic)
	_check("another tap on Mic switches it off", await _until(func() -> bool: return not Game.voice.mic_on))
	_check("B sees our microphone off", await _until(func() -> bool: return not b.voice.has_mic(Game.player_id)))

	# ---------- leaving the table ----------
	_tap_button(mic)
	await _until(func() -> bool: return Game.voice.mic_on and c.voice.has_mic(Game.player_id))
	await Game.donkey.leave()
	_check("leaving the table switches our microphone off", await _until(func() -> bool: return not Game.voice.mic_on))
	_check("the others no longer see it", await _until(func() -> bool: return not c.voice.has_mic(Game.player_id)))
	_finish()


# A picture of the screen, when asked for with --shots and drawn in a window
func _shot(shot_name: String) -> void:
	if _shots.is_empty() or DisplayServer.get_name() == "headless":
		return
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(_shots.path_join(shot_name + ".png"))


func _seat(user_id: String) -> DonkeySeat:
	return _node("DonkeySeat_" + user_id) as DonkeySeat


func _on_event(event_name: String, payload: Variant, client: GameClient) -> void:
	if event_name == "voice" and payload is Dictionary and str(payload.get("from", "")) == Game.player_id:
		_heard[client] += 1


# A tone of `hz` for 0.8 s in every 2 s, like voice_e2e's: a voice that comes and goes.
func _tone(hz: float) -> AudioStreamWAV:
	var rate := 44100
	var data := PackedByteArray()
	data.resize(rate * 2 * 2)
	for i in rate * 2:
		var t := float(i) / rate
		var value := 0.25 * sin(TAU * hz * t) if t < 0.8 else randf_range(-0.001, 0.001)
		data.encode_s16(i * 2, int(value * 32767.0))
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = rate
	stream.stereo = false
	stream.data = data
	stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	stream.loop_end = rate * 2
	return stream


# A finger on the middle of the button, down and up again
func _tap_button(button: Control) -> void:
	var at := get_viewport().get_final_transform() * button.get_global_rect().get_center()
	for down: bool in [true, false]:
		var event := InputEventScreenTouch.new()
		event.index = 0
		event.pressed = down
		event.position = at
		Input.parse_input_event(event)
		Input.flush_buffered_events()


func _under_finger() -> String:
	var hit := get_viewport().gui_get_hovered_control()
	return "the finger was on nothing" if hit == null else "the finger was on %s" % hit.get_path()


func _node(node_name: String) -> Variant:
	return _main.find_child(node_name, true, false)


func _has(node_name: String) -> bool:
	return _node(node_name) != null


func _new_client() -> GameClient:
	var client := GameClient.new()
	client.remember_login = false
	client.server_url = Game.server_url if _url.is_empty() else _url
	add_child(client)
	return client


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
		print("FAILED: %s %s" % [what, detail])


func _finish() -> void:
	print("donkey_voice: %d passed, %d failed" % [_passed, _failed])
	Sound.hush()
	get_tree().quit(1 if _failed > 0 else 0)
