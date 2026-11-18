extends Node
## The table chat, the emoji and the things thrown, at a Donkey Master table, through a real
## server: three players at one Donkey Master table (A, B, C), two at a rummy table (D, E).
## Messages, emoji and throws reach everyone at the Donkey Master table and nobody at the rummy
## table, and the other way round. What the server refuses (a target at another table, no table
## at all). A player who comes back after losing the connection catches up with what was said.
## A player who blocked another hears nothing from them there either. Talking changes nothing
## in the game, and getting up clears the chat.
##
## Like throw_e2e, this test starts and stops its own server (tests/test_server.js, so `node`
## must be on the PATH), on a port and a database nothing else uses:
##   godot --headless --path . res://tests/donkey_social_e2e.tscn -- --port=3213 --db=My_Rummy_voice_test
## The database is dropped and created again at the start.

const START_SECONDS := 25.0
const PASSWORD := "secret12"

var _port := 3213
var _database := "My_Rummy_voice_test"
var _server_pid := -1
var _passed := 0
var _failed := 0
var _said := {}  # client -> [chat messages it received]
var _tossed := {}  # client -> [throws it saw]


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

	# ---------- three at a Donkey Master table, two at a rummy table ----------
	var tag := "%06d%04d" % [int(Time.get_unix_time_from_system()) % 1000000, randi() % 10000]
	var number := randi() % 10000000
	var a := _new_client()
	var b := _new_client()
	var c := _new_client()
	var d := _new_client()
	var e := _new_client()
	var everyone := [a, b, c, d, e]
	for index in everyone.size():
		var r: Dictionary = await _register(everyone[index], "s%s_%s" % ["abcde"[index], tag], "9%d%08d" % [index + 5, number])
		_check("player %s registers" % "ABCDE"[index], r.ok, str(r.get("error", "")))
	_check("all five are connected", await _until(func() -> bool: return everyone.all(func(client: GameClient) -> bool: return client.is_online())))
	for client: GameClient in everyone:
		var said: Array = []
		_said[client] = said
		client.chat_received.connect(func(message: Dictionary) -> void: said.append(message))
		var tossed: Array = []
		_tossed[client] = tossed
		client.item_thrown.connect(func(toss: Dictionary) -> void: tossed.append(toss))

	var r: Dictionary = await a.donkey.create_room(3, 0)
	var code := str(a.donkey.state.get("roomCode", ""))
	_check("A opens a Donkey Master table", r.get("ok", false) and not code.is_empty(), str(r))
	await b.donkey.join_room(code)
	await c.donkey.join_room(code)
	_check("the full table deals by itself", await _until(func() -> bool: return [a, b, c].all(func(client: GameClient) -> bool: return client.donkey.status() == "playing"), 10.0))
	r = await d.create_game("points", 2, 0, true)
	await e.join_by_code(str(r.get("roomCode", "")))
	_check("D and E play rummy", await _until(func() -> bool: return [d, e].all(func(client: GameClient) -> bool: return client.status() == "playing")))
	var room := str(a.donkey.state.get("roomId", ""))
	_check("the chat belongs to the Donkey Master table", a.table_id() == room and not room.is_empty() and a.table_players().size() == 3, a.table_id())
	_check("and to the rummy table at the rummy table", d.table_id() == str(d.state.get("gameId", "")))
	_check("a round is being played at both", a.table_playing() and d.table_playing())
	var turn := str(a.donkey.state.get("turn", ""))
	var cards := [a.donkey.hand().size(), b.donkey.hand().size(), c.donkey.hand().size()]

	# ---------- chat and emoji ----------
	a.send_chat("Hello donkeys")
	_check("A's message reaches A, B and C", await _until(func() -> bool: return [a, b, c].all(func(client: GameClient) -> bool: return _texts(client).has("Hello donkeys"))))
	var message: Dictionary = _said[b].back() if not _said[b].is_empty() else {}
	_check("with A's name and the table's id", message.get("username") == a.user.get("username") and str(message.get("gameId")) == room, str(message))
	_check("it is in B's chat log", b.chat_log.any(func(entry: Dictionary) -> bool: return entry.get("text") == "Hello donkeys"))
	b.send_emoji("laugh")
	_check("B's emoji reaches the table", await _until(func() -> bool: return [a, c].all(func(client: GameClient) -> bool: return _said[client].any(func(entry: Dictionary) -> bool: return entry.get("emoji") == "laugh"))))
	d.send_chat("Rummy here")
	_check("D's message reaches E at the rummy table", await _until(func() -> bool: return _texts(e).has("Rummy here")))
	await _wait(0.4)
	_check("nothing crosses between the two tables", _texts(d).all(func(text: String) -> bool: return text != "Hello donkeys") and [a, b, c].all(func(client: GameClient) -> bool: return not _texts(client).has("Rummy here")))
	_check("and no emoji either", _said[d].all(func(entry: Dictionary) -> bool: return entry.get("kind") != "emoji"))

	# ---------- things thrown ----------
	b.throw_item(c.player_id, "cake")
	_check("B's cake at C reaches A, B and C", await _until(func() -> bool: return [a, b, c].all(func(client: GameClient) -> bool: return _tossed[client].size() == 1)))
	var toss: Dictionary = _tossed[a][0] if not _tossed[a].is_empty() else {}
	_check("it says who threw what at whom", toss.get("from") == b.player_id and toss.get("to") == c.player_id and toss.get("item") == "cake", str(toss))
	await _wait(0.3)
	_check("the rummy table sees nothing", _tossed[d].is_empty() and _tossed[e].is_empty())
	var answer: Dictionary = await a.socket.request("throwItem", {"to": d.player_id, "item": "egg"})
	_check("nothing can be thrown at someone at another table", not answer.ok and answer.error == "That player is not at your table", str(answer))
	d.throw_item(e.player_id, "rose")
	_check("rummy throws still work", await _until(func() -> bool: return _tossed[e].size() == 1))
	await _wait(0.3)
	_check("and stay at the rummy table", _tossed[a].size() == 1)

	# ---------- blocked in the chat ----------
	c.block_chat_player(a.player_id, a.user.get("username", "A"))
	_check("C blocks A", await _until(func() -> bool: return c.is_chat_blocked(a.player_id)))
	a.send_chat("Can you hear me")
	a.throw_item(b.player_id, "tomato")
	_check("B gets A's message and A's tomato", await _until(func() -> bool: return _texts(b).has("Can you hear me") and _tossed[b].size() == 2))
	await _wait(0.4)
	_check("C, who blocked A, gets neither", not _texts(c).has("Can you hear me") and _tossed[c].size() == 1, "%s / %d" % [_texts(c), _tossed[c].size()])

	# ---------- coming back after losing the connection ----------
	b.socket.close()
	await _wait(0.6)
	a.send_chat("Said while B was away")
	await _until(func() -> bool: return _texts(a).has("Said while B was away"))
	b.reconnect()
	_check("B, back on the line, catches up with what was said", await _until(func() -> bool: return b.chat_log.any(func(entry: Dictionary) -> bool: return entry.get("text") == "Said while B was away"), 10.0))

	_check("talking and throwing change nothing in the game", str(a.donkey.state.get("turn", "")) == turn and [a.donkey.hand().size(), b.donkey.hand().size(), c.donkey.hand().size()] == cards, "%s %s" % [a.donkey.state.get("turn"), [a.donkey.hand().size(), b.donkey.hand().size(), c.donkey.hand().size()]])
	_check("and never make the table busy", not a.busy and not b.busy and not c.busy)

	# ---------- getting up ----------
	await c.donkey.leave()
	_check("getting up clears C's chat", c.chat_log.is_empty() and c.table_id().is_empty(), str(c.chat_log.size()))
	answer = await c.socket.request("sendChat", {"text": "anyone?"})
	_check("and C can no longer write there", not answer.ok and answer.error == "Game not found", str(answer))
	var seen_by_a: int = _tossed[a].size()
	c.throw_item(a.player_id, "egg")
	answer = await c.socket.request("throwItem", {"to": a.player_id, "item": "egg"})
	await _wait(0.4)
	_check("nor throw", _tossed[a].size() == seen_by_a and not answer.ok and answer.error == "Game not found", str(answer))

	_finish()


func _texts(client: GameClient) -> Array:
	return _said[client].filter(func(entry: Dictionary) -> bool: return entry.get("kind") == "text").map(func(entry: Dictionary) -> String: return str(entry.get("text")))


func _finish() -> void:
	_stop_server()
	print("donkey_social_e2e: %d passed, %d failed" % [_passed, _failed])
	get_tree().quit(1 if _failed > 0 else 0)


# The one place that knows how an account is made (it changes with the sign-up form).
func _register(client: GameClient, username: String, phone: String) -> Dictionary:
	return await client.register(username, phone, PASSWORD)


# ---------- the server ----------

func _url() -> String:
	return "http://127.0.0.1:%d" % _port


func _start_server() -> void:
	# Slow turn clocks, so nobody is played for while the test talks (the server inherits these)
	OS.set_environment("DONKEY_TURN_SECONDS", "600")
	OS.set_environment("TURN_TIMEOUT_SECONDS", "600")
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
