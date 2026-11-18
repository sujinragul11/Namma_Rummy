extends Node
## Voice chat through a real server: three players at one table, a fourth at a table of
## their own. Each "microphone" is a recorded tone that comes and goes, played in its place.
## What A says reaches B and C, as sound that is still the same tone, and never D; D's voice
## never reaches the first table. Who has a microphone on is known to the whole table. With
## the microphone off, nothing goes out and the server passes on nothing. Speaker off still
## shows who speaks. A player who blocked A does not hear A. A dropped connection switches the
## microphone off for the others, and coming back switches it on again. The server refuses
## junk and too much at once. Leaving the table switches the microphone off. The game itself
## is never touched.
##
## Like throw_e2e, this test starts and stops its own server (tests/test_server.js, so `node`
## must be on the PATH), on a port and a database nothing else uses:
##   godot --headless --path . res://tests/voice_e2e.tscn -- --port=3213 --db=My_Rummy_voice_test
## The database is dropped and created again at the start.

const START_SECONDS := 25.0
const PASSWORD := "secret12"
## VoiceRelay.js passes on at most 40 pieces of sound a second from one player.
const PACKETS_PER_SECOND := 40

var _port := 3213
var _database := "My_Rummy_voice_test"
var _server_pid := -1
var _passed := 0
var _failed := 0
var _heard := {}  # client -> [{"from", "level", "data", "at"}] of the "voice" events it got
var _mic_news := {}  # client -> how many "voiceMics" events it got


func _ready() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--port="):
			_port = int(argument.trim_prefix("--port="))
		elif argument.begins_with("--db="):
			_database = argument.trim_prefix("--db=")
	_run()


func _exit_tree() -> void:
	_stop_server()  # never leave it running, whatever happened


func _run() -> void:
	if await _server_answers():
		print("Something already answers on port %d. Stop it, or pass another --port." % _port)
		get_tree().quit(1)
		return
	_start_server()
	if not await _wait_for_server():
		print("The test server did not start. Is `node` on the PATH and PostgreSQL running?")
		_finish()
		return

	# ---------- three players at one table, a fourth at a table of their own ----------
	var tag := "%06d%04d" % [int(Time.get_unix_time_from_system()) % 1000000, randi() % 10000]
	var number := randi() % 10000000
	var a := _new_client()
	var b := _new_client()
	var c := _new_client()
	var d := _new_client()
	var e := _new_client()  # at no table at all
	var everyone := [a, b, c, d, e]
	for index in everyone.size():
		var r: Dictionary = await _register(everyone[index], "v%s_%s" % ["abcde"[index], tag], "9%d%08d" % [index + 5, number])
		_check("player %s registers" % "ABCDE"[index], r.ok, str(r.get("error", "")))
	_check("all five are connected", await _until(func() -> bool: return everyone.all(func(client: GameClient) -> bool: return client.is_online())))
	for client: GameClient in everyone:
		var heard: Array = []
		_heard[client] = heard
		_mic_news[client] = 0
		client.socket.event_received.connect(_on_event.bind(client))

	var r: Dictionary = await a.create_game("points", 3, 0, true)
	var code := str(r.get("roomCode", ""))
	await b.join_by_code(code)
	await c.join_by_code(code)
	_check("three players are dealt in", await _until(func() -> bool: return [a, b, c].all(func(client: GameClient) -> bool: return client.status() == "playing" and client.hand().size() == 13)))
	r = await d.create_game("points", 2, 0, true)
	_check("D waits at a table of their own", r.ok and d.status() == "waiting", str(r))
	_check("nobody's microphone is on to begin with", everyone.all(func(client: GameClient) -> bool: return not client.voice.mic_on and not client.voice.has_mic(a.player_id)))

	a.voice.test_source = _tone(300.0)
	b.voice.test_source = _tone(500.0)
	d.voice.test_source = _tone(700.0)
	var on_turn := str(a.state.get("currentPlayer", ""))
	var hands := [a.hand().size(), b.hand().size(), c.hand().size()]

	# ---------- A switches the microphone on ----------
	a.voice.set_mic(true)
	_check("A's microphone is on", a.voice.mic_on and a.voice.has_mic(a.player_id))
	_check("B and C see A's microphone on", await _until(func() -> bool: return b.voice.has_mic(a.player_id) and c.voice.has_mic(a.player_id)))
	_check("D, at another table, is told nothing about it", _mic_news[d] == 0, str(_mic_news[d]))
	_check("B and C hear A", await _until(func() -> bool: return _from(b, a).size() >= 10 and _from(c, a).size() >= 10, 8.0))
	_check("B sees A speaking", await _until(func() -> bool: return b.voice.level_of(a.player_id) > 0.0))
	_check("D hears nothing", _heard[d].is_empty(), str(_heard[d].size()))
	_check("A does not hear themselves", _from(a, a).is_empty())

	var spoken: Array = _from(b, a).filter(func(packet: Dictionary) -> bool: return int(packet.level) > 0)
	var hz := _pitch(spoken[spoken.size() / 2]) if not spoken.is_empty() else 0.0
	_check("what B hears is still A's 300 Hz tone", absf(hz - 300.0) < 30.0, "%.0f Hz" % hz)
	_check("loud enough to hear", not spoken.is_empty() and _loudness(spoken[spoken.size() / 2]) > 0.03)
	var speaker: VoiceChat.Speaker = b.voice._speakers.get(a.player_id)
	_check("B's phone plays it", speaker != null and speaker.player != null and speaker.player.playing)

	# The tone sounds for 0.8 s in every 2 s: only that, and the end of each word, goes out
	var counted_from := _from(b, a).size()
	await _wait(4.0)
	var in_four_seconds := _from(b, a).size() - counted_from
	_check("silence between words is not sent (about 15 pieces a second, not 25)", in_four_seconds >= 40 and in_four_seconds <= 80, str(in_four_seconds))

	# ---------- both talk at once ----------
	b.voice.set_mic(true)
	_check("B's microphone on is seen by A and C", await _until(func() -> bool: return a.voice.has_mic(b.player_id) and c.voice.has_mic(b.player_id)))
	counted_from = _from(b, a).size()
	_check("A hears B", await _until(func() -> bool: return _from(a, b).size() >= 10, 8.0))
	_check("while B goes on hearing A", _from(b, a).size() - counted_from >= 10, str(_from(b, a).size() - counted_from))
	_check("C hears both", _from(c, b).size() >= 10)

	# ---------- Speaker off ----------
	c.voice.set_speaker(false)
	var c_speaker: VoiceChat.Speaker = c.voice._speakers.get(a.player_id)
	await _wait(1.2)
	_check("C with Speaker off has nothing waiting to play", c_speaker == null or c_speaker.waiting.is_empty())
	_check("but still sees who is speaking", await _until(func() -> bool: return c.voice.level_of(a.player_id) > 0.0 or c.voice.level_of(b.player_id) > 0.0, 3.0))
	c.voice.set_speaker(true)

	# ---------- the microphone off ----------
	b.voice.set_mic(false)
	_check("B's microphone off is seen by A and C", await _until(func() -> bool: return not a.voice.has_mic(b.player_id) and not c.voice.has_mic(b.player_id)))
	await _wait(0.5)
	counted_from = _from(a, b).size()
	await _wait(2.5)
	_check("nothing more comes from B", _from(a, b).size() == counted_from, str(_from(a, b).size() - counted_from))
	_check("B's microphone has stopped", not b.voice._microphone.playing)

	# Sound sent by hand with the microphone off is not passed on
	var piece := Marshalls.raw_to_base64(VoiceCodec.encode(_samples(300.0)))
	for i in 5:
		b.socket.send_event("voice", {"level": 50, "data": piece})
	await _wait(0.6)
	_check("the server passes on nothing from a microphone that is off", _from(a, b).size() == counted_from)

	# ---------- D, at the other table ----------
	d.voice.set_mic(true)
	await _wait(2.5)
	_check("D's microphone is on at their own table", d.voice.mic_on and d.voice.has_mic(d.player_id))
	_check("nobody at the first table hears D or sees D's microphone", [a, b, c].all(func(client: GameClient) -> bool: return _from(client, d).is_empty() and not client.voice.has_mic(d.player_id)))
	d.voice.set_mic(false)

	# ---------- blocked in the chat ----------
	b.block_chat_player(a.player_id, a.user.get("username", "A"))
	_check("B blocks A in the chat", await _until(func() -> bool: return b.is_chat_blocked(a.player_id)))
	await _wait(0.5)
	var b_before := _from(b, a).size()
	var c_before := _from(c, a).size()
	await _wait(2.5)
	_check("C still hears A", _from(c, a).size() > c_before)
	_check("B, who blocked A, does not", _from(b, a).size() == b_before, str(_from(b, a).size() - b_before))
	b.block_chat_player(a.player_id, a.user.get("username", "A"), false)
	_check("B unblocks A", await _until(func() -> bool: return not b.is_chat_blocked(a.player_id)))

	# ---------- what the server refuses ----------
	b.voice.set_mic(true)
	_check("B's microphone is on again", await _until(func() -> bool: return c.voice.has_mic(b.player_id)))
	b.voice.set_mic(false)  # the hand-made pieces below are the only ones from B...
	await _wait(0.4)
	var answer: Dictionary = await b.socket.request("voiceMic", {"on": true})  # ...with the server told it is on
	_check("the server takes B's microphone on", answer.get("ok", false), str(answer))
	await _start_of_second()  # the server counts the pace per second of the clock
	counted_from = _from(c, b).size()
	for i in 60:
		b.socket.send_event("voice", {"level": 50, "data": piece})
	await _wait(0.8)
	var through := _from(c, b).size() - counted_from
	_check("60 pieces at once: no more than %d get through" % PACKETS_PER_SECOND, through > 0 and through <= PACKETS_PER_SECOND, str(through))
	await _start_of_second()
	counted_from = _from(c, b).size()
	b.socket.send_event("voice", {"level": 50, "data": "this is not sound!"})
	b.socket.send_event("voice", {"level": 50, "data": "A".repeat(5000)})
	b.socket.send_event("voice", {"level": 50})
	b.socket.send_event("voice", {"level": 50, "data": piece})
	await _wait(0.6)
	_check("junk is dropped, real sound still passes", _from(c, b).size() == counted_from + 1, str(_from(c, b).size() - counted_from))
	await b.socket.request("voiceMic", {"on": false})
	answer = await e.socket.request("voiceMic", {"on": true})
	_check("a player at no table cannot switch a microphone on", not answer.get("ok", false) and answer.get("error") == "Game not found", str(answer))
	e.socket.send_event("voice", {"level": 50, "data": piece})
	await _wait(0.5)
	_check("nor be heard anywhere", everyone.all(func(client: GameClient) -> bool: return _from(client, e).is_empty()))
	_check("and hears nothing", _heard[e].is_empty(), str(_heard[e].size()))

	# ---------- a dropped connection ----------
	_check("A's microphone is still on", a.voice.mic_on and b.voice.has_mic(a.player_id))
	a.socket.close()
	_check("A's dropped connection switches A's microphone off for the others", await _until(func() -> bool: return not b.voice.has_mic(a.player_id) and not c.voice.has_mic(a.player_id), 8.0))
	_check("A still means to talk", a.voice.mic_on)
	a.reconnect()
	_check("back on the line, A's microphone is on again for the others", await _until(func() -> bool: return b.voice.has_mic(a.player_id) and c.voice.has_mic(a.player_id), 10.0))
	counted_from = _from(b, a).size()
	_check("and B hears A again", await _until(func() -> bool: return _from(b, a).size() > counted_from + 5, 6.0))

	_check("talking changes nothing in the game", str(a.state.get("currentPlayer", "")) == on_turn and [a.hand().size(), b.hand().size(), c.hand().size()] == hands and a.status() == "playing", "%s %s" % [a.state.get("currentPlayer"), [a.hand().size(), b.hand().size(), c.hand().size()]])
	_check("talking never makes the game busy", not a.busy and not b.busy and not c.busy)
	_check("the game still answers at once while A talks", (await a.socket.request("voiceMics")).get("ok", false))

	# ---------- leaving the table ----------
	await a.leave()
	_check("leaving the table switches A's microphone off", not a.voice.mic_on and not a.voice._microphone.playing)
	_check("and B sees it gone", await _until(func() -> bool: return not b.voice.has_mic(a.player_id)))
	counted_from = _from(b, a).size()
	await _wait(1.5)
	_check("nothing more comes from A", _from(b, a).size() == counted_from, str(_from(b, a).size() - counted_from))

	_finish()


func _finish() -> void:
	for client: Node in get_children():
		if client is GameClient:
			client.voice._leave_table()
	_stop_server()
	print("voice_e2e: %d passed, %d failed" % [_passed, _failed])
	get_tree().quit(1 if _failed > 0 else 0)


func _on_event(event_name: String, payload: Variant, client: GameClient) -> void:
	if not (payload is Dictionary):
		return
	if event_name == "voice":
		_heard[client].append(payload)
	elif event_name == "voiceMics":
		_mic_news[client] += 1


func _from(client: GameClient, speaker: GameClient) -> Array:
	return _heard[client].filter(func(packet: Dictionary) -> bool: return str(packet.get("from", "")) == speaker.player_id)


# A "microphone": `hz` for 0.8 s, then 1.2 s of a faint hiss, over and over.
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


func _samples(hz: float) -> PackedFloat32Array:
	var samples := PackedFloat32Array()
	for i in VoiceChat.FRAME:
		samples.append(0.2 * sin(TAU * hz * i / VoiceCodec.RATE))
	return samples


# The pitch of a piece of sound, from how often it crosses zero
func _pitch(packet: Dictionary) -> float:
	var frames := VoiceCodec.decode(Marshalls.base64_to_raw(str(packet.get("data", ""))))
	if frames.size() < 2:
		return 0.0
	var crossings := 0
	for i in range(1, frames.size()):
		if (frames[i - 1].x < 0.0) != (frames[i].x < 0.0):
			crossings += 1
	return crossings / 2.0 / (frames.size() / float(VoiceCodec.RATE))


func _loudness(packet: Dictionary) -> float:
	return VoiceCodec.frames_loudness(VoiceCodec.decode(Marshalls.base64_to_raw(str(packet.get("data", "")))))


# The one place that knows how an account is made (it changes with the sign-up form).
func _register(client: GameClient, username: String, phone: String) -> Dictionary:
	return await client.register(username, phone, PASSWORD)


# ---------- the server ----------

func _url() -> String:
	return "http://127.0.0.1:%d" % _port


func _start_server() -> void:
	var script := ProjectSettings.globalize_path("res://tests/test_server.js")
	_server_pid = OS.create_process("node", PackedStringArray([script, "--fresh", "--port=%d" % _port, "--db=%s" % _database]))


func _stop_server() -> void:
	if _server_pid > 0:
		OS.kill(_server_pid)
		_server_pid = -1


func _server_answers() -> bool:
	var http := HTTPRequest.new()
	http.timeout = 2.0
	add_child(http)
	var answered := false
	if http.request(_url() + "/health") == OK:
		var result: Array = await http.request_completed
		answered = result[0] == HTTPRequest.RESULT_SUCCESS and result[1] == 200
	http.queue_free()
	return answered


func _wait_for_server() -> bool:
	var deadline := Time.get_ticks_msec() + int(START_SECONDS * 1000.0)
	while Time.get_ticks_msec() < deadline:
		if await _server_answers():
			return true
		await get_tree().create_timer(0.3).timeout
	return false


# ---------- helpers ----------

func _new_client() -> GameClient:
	var client := GameClient.new()
	client.remember_login = false
	client.server_url = _url()
	add_child(client)
	return client


func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout


# Waits for the clock (the server's too, on this PC) to start a new second
func _start_of_second() -> void:
	await _wait(0.2)
	while fmod(Time.get_unix_time_from_system(), 1.0) > 0.2:
		await get_tree().process_frame


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
