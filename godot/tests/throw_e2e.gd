extends Node
## Things thrown at pictures, through a real server: three players at one table, a fourth
## elsewhere. A throw reaches everyone at the table with the right thrower and target; what the
## server refuses (an unknown item, ourselves, someone at another table, no table at all, too
## many at once); a throw changes nothing in the game; a player who blocked the thrower in the
## chat does not see it.
##
## Like session_e2e, this test starts and stops its own server (tests/test_server.js, so `node`
## must be on the PATH), on a port and a database nothing else uses:
##   godot --headless --path . res://tests/throw_e2e.tscn -- --port=3181 --db=My_Rummy_throw_test
## The database is dropped and created again at the start.

const START_SECONDS := 25.0
const PASSWORD := "secret12"
## The server allows 4 throws per player in 8 seconds (BURST, BURST_MS in Throwables.js).
const BURST_SECONDS := 8.2

var _port := 3181
var _database := "My_Rummy_throw_test"
var _server_pid := -1
var _passed := 0
var _failed := 0


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

	# ---------- three players at one table, a fourth at none ----------
	var tag := "%d%04d" % [int(Time.get_unix_time_from_system()) % 1000000, randi() % 10000]
	var number := randi() % 10000000
	var a := _new_client()
	var b := _new_client()
	var c := _new_client()
	var d := _new_client()
	var everyone := [a, b, c, d]
	for index in everyone.size():
		var r: Dictionary = await _register(everyone[index], "t%s_%s" % ["abcd"[index], tag], "9%d%08d" % [index + 6, number])
		_check("player %s registers" % "ABCD"[index], r.ok, str(r.get("error", "")))
	_check("all four are connected", await _until(func() -> bool: return everyone.all(func(client: GameClient) -> bool: return client.is_online())))

	var r: Dictionary = await a.create_game("points", 3, 0, true)
	var code := str(r.get("roomCode", ""))
	r = await b.join_by_code(code)
	r = await c.join_by_code(code)
	_check("three players are dealt in", await _until(func() -> bool: return [a, b, c].all(func(client: GameClient) -> bool: return client.status() == "playing" and client.hand().size() == 13)))

	var seen := {}
	for client: GameClient in everyone:
		var tosses: Array = []
		client.item_thrown.connect(func(toss: Dictionary) -> void: tosses.append(toss))
		seen[client] = tosses
	var notices := {}
	for client: GameClient in everyone:
		var shown: Array = []
		client.notice.connect(func(kind: String, message: String) -> void:
			if kind == "warning":
				shown.append(message))
		notices[client] = shown

	# ---------- a throw reaches the whole table ----------
	var on_turn := str(a.state.get("currentPlayer", ""))
	var hands := [a.hand().size(), b.hand().size(), c.hand().size()]
	a.throw_item(b.player_id, "cake")
	_check("A's cake at B reaches A, B and C", await _until(func() -> bool: return [a, b, c].all(func(client: GameClient) -> bool: return seen[client].size() == 1)))
	var toss: Dictionary = seen[c][0] if not seen[c].is_empty() else {}
	_check("it says who threw what at whom", toss.get("from") == a.player_id and toss.get("to") == b.player_id and toss.get("item") == "cake", str(toss))
	_check("everyone saw the same throw", [a, b].all(func(client: GameClient) -> bool: return not seen[client].is_empty() and seen[client][0].get("id") == toss.get("id")))
	_check("a player at another table sees nothing", seen[d].is_empty())

	b.throw_item(a.player_id, "aruval")
	c.throw_item(a.player_id, "ghost")
	_check("throws back and forth all arrive", await _until(func() -> bool: return [a, b, c].all(func(client: GameClient) -> bool: return seen[client].size() == 3)))
	_check("they arrive with the right items", seen[a].map(func(each: Dictionary) -> String: return each.item).has("aruval") and seen[b].map(func(each: Dictionary) -> String: return each.item).has("ghost"))
	await get_tree().create_timer(0.3).timeout
	_check("throwing changes nothing in the game", str(a.state.get("currentPlayer", "")) == on_turn and [a.hand().size(), b.hand().size(), c.hand().size()] == hands and a.status() == "playing")
	_check("throwing never makes the game busy", not a.busy and not b.busy)

	# ---------- what the server refuses ----------
	var answer: Dictionary = await a.socket.request("throwItem", {"to": a.player_id, "item": "cake"})
	_check("not at ourselves", not answer.ok and answer.error == "Pick another player", str(answer))
	answer = await a.socket.request("throwItem", {"to": b.player_id, "item": "brick"})
	_check("not something that is not on the list", not answer.ok and answer.error == "Unknown item", str(answer))
	answer = await a.socket.request("throwItem", {"to": d.player_id, "item": "egg"})
	_check("not at someone at another table", not answer.ok and answer.error == "That player is not at your table", str(answer))
	answer = await d.socket.request("throwItem", {"to": a.player_id, "item": "egg"})
	_check("not from someone at no table", not answer.ok and answer.error == "Game not found", str(answer))
	d.throw_item(a.player_id, "egg")
	_check("the app does not even ask when it has no table", notices[d].is_empty())

	# ---------- blocked in the chat ----------
	b.block_chat_player(a.player_id, a.user.get("username", "A"))
	_check("B blocks A in the chat", await _until(func() -> bool: return b.is_chat_blocked(a.player_id)))
	var before_b: int = seen[b].size()
	var before_c: int = seen[c].size()
	a.throw_item(c.player_id, "rose")
	_check("C still sees A's rose", await _until(func() -> bool: return seen[c].size() == before_c + 1))
	await get_tree().create_timer(0.4).timeout
	_check("B, who blocked A, does not", seen[b].size() == before_b, str(seen[b].size()))
	c.throw_item(a.player_id, "crown")
	_check("B still sees what others throw, even at A", await _until(func() -> bool: return seen[b].size() == before_b + 1))

	# ---------- too many at once ----------
	await get_tree().create_timer(BURST_SECONDS).timeout  # C's earlier throws no longer count
	before_b = seen[b].size()
	for index in 4:
		c.throw_item(b.player_id, "tomato")
	_check("four throws in a row are fine", await _until(func() -> bool: return seen[b].size() == before_b + 4), str(seen[b].size() - before_b))
	c.throw_item(b.player_id, "tomato")
	_check("the fifth one is refused with a notice", await _until(func() -> bool: return not notices[c].is_empty()) and str(notices[c][0]).begins_with("Easy there!"), str(notices[c]))
	await get_tree().create_timer(0.4).timeout
	_check("and nobody sees it", seen[b].size() == before_b + 4, str(seen[b].size() - before_b))

	_finish()


func _finish() -> void:
	_stop_server()
	print("throw_e2e: %d passed, %d failed" % [_passed, _failed])
	get_tree().quit(1 if _failed > 0 else 0)


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
