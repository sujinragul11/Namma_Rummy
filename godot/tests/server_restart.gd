extends Node
## Restarting the game server must not end the games on it. Two players sit down, the server
## is stopped dead and started again, and they must find their table as they left it and play
## on. Then the server comes back having lost its games: the players must be told, and taken
## off a table that no longer exists, instead of having every move refused.
##
## Unlike the other tests this one starts and stops its own server (tests/test_server.js, so
## `node` must be on the PATH), on a port and a database nothing else uses:
##   godot --headless --path . res://tests/server_restart.tscn -- --port=3112 --db=My_Rummy_restart_test
## The database is dropped and created again at the start.

const START_SECONDS := 25.0

var _port := 3112
var _database := "My_Rummy_restart_test"
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
	_start_server(["--fresh"])
	if not await _wait_for_server():
		print("The test server did not start. Is `node` on the PATH and PostgreSQL running?")
		_finish()
		return

	var tag := "%d%04d" % [int(Time.get_unix_time_from_system()) % 1000000, randi() % 10000]
	var a := _new_client()
	var b := _new_client()
	var errors_a: Array = []
	var errors_b: Array = []
	a.action_failed.connect(func(message: String) -> void: errors_a.append(message))
	b.action_failed.connect(func(message: String) -> void: errors_b.append(message))
	var online := func() -> bool: return a.is_online() and b.is_online()
	var offline := func() -> bool: return not a.is_online() and not b.is_online()

	# An account needs an email and a mobile number of its own (10 digits, starting 6 to 9)
	var number := randi() % 100000000
	var r: Dictionary = await a.register("ra_" + tag, "ra_%s@test.local" % tag, "98%08d" % number, "secret12")
	_check("player A registers", r.ok, str(r.get("error", "")))
	r = await b.register("rb_" + tag, "rb_%s@test.local" % tag, "88%08d" % number, "secret12")
	_check("player B registers", r.ok, str(r.get("error", "")))
	_check("two players are connected", await _until(online))

	# ---------- a game in progress ----------
	r = await a.create_game("points", 2, 5000)  # played for coins: 5,000 each
	r = await b.join_by_code(str(r.get("roomCode", "")))
	_check("a game is dealt", r.ok and await _until(func() -> bool: return a.hand().size() == 13 and b.hand().size() == 13))
	_check("both paid to sit down", await _until(func() -> bool: return a.coins == 45000 and b.coins == 45000) and a.pot() == 10000, "%d %d" % [a.coins, b.coins])
	var mover := a if a.is_my_turn() else b
	var other := b if mover == a else a
	r = await mover.draw()
	_check("the player on turn draws", r.ok and await _until(func() -> bool: return mover.hand().size() == 14))

	# An arrangement no sorting would produce, so that finding it again means it was kept
	var ids := _ids(mover.hand())
	var arrangement: Array = [ids.slice(0, 5), ids.slice(5, 9), ids.slice(9)]
	arrangement[0].reverse()
	mover.set_groups(arrangement)
	await _wait(0.6)  # arrangements are sent without waiting for an answer
	await mover.resync()
	_check("the server has the player's arrangement", mover.state.get("groups") == arrangement, str(mover.state.get("groups")))
	await _wait(0.4)

	var game_id: Variant = a.state.get("gameId")
	var hand_a := _ids(a.hand())
	var hand_b := _ids(b.hand())
	var groups_other: Array = other.groups.duplicate(true)
	var open_card: Variant = a.state.get("discardTop", {}).get("id")
	var deck_count := int(a.state.get("deckCount", 0))

	# ---------- the server is stopped dead and started again ----------
	_stop_server()
	_check("both players notice that the server is gone", await _until(offline, 10.0))
	_check("they keep seeing their table meanwhile", a.status() == "playing" and b.status() == "playing")
	_start_server([])
	_check("both get back in by themselves", await _until(online, START_SECONDS))
	await _wait(1.2)

	_check("it is the same game", a.state.get("gameId") == game_id and b.state.get("gameId") == game_id and a.status() == "playing", str(a.state.get("gameId")))
	_check("both hold the cards they held", _ids(a.hand()) == hand_a and _ids(b.hand()) == hand_b)
	_check("the turn is where it was", mover.is_my_turn() and mover.state.get("turnPhase") == "discard", "%s / %s" % [mover.state.get("currentPlayer"), mover.state.get("turnPhase")])
	_check("the open pile and the deck are as they were", a.state.get("discardTop", {}).get("id") == open_card and int(a.state.get("deckCount", 0)) == deck_count)
	_check("the hands are arranged as their players left them", mover.groups == arrangement and other.groups == groups_other, str(mover.groups))
	_check("the player on turn gets the whole time again", int(mover.state.get("turnTimeLeft", 0)) > 20000, str(mover.state.get("turnTimeLeft")))
	_check("both are shown as connected", mover.players().all(func(player: Dictionary) -> bool: return player.get("connected", false)))
	_check("nobody was shown an error", errors_a.is_empty() and errors_b.is_empty(), "%s %s" % [errors_a, errors_b])
	_check("nobody was charged again or paid back, and the pot is whole", a.coins == 45000 and b.coins == 45000 and a.pot() == 10000, "%d %d pot %d" % [a.coins, b.coins, a.pot()])

	r = await mover.discard(str(mover.hand()[0].id))
	_check("the game goes on: a discard passes the turn", r.ok and await _until(func() -> bool: return other.is_my_turn()), str(r.get("error", "")))
	r = await other.draw()
	_check("and the other player draws", r.ok and await _until(func() -> bool: return other.hand().size() == 14), str(r.get("error", "")))

	# ---------- twice in a row, as when several files are saved one after another ----------
	_stop_server()
	await _until(offline, 10.0)
	_start_server([])
	await _wait_for_server()
	_stop_server()
	await _wait(0.5)
	_start_server([])
	_check("after two restarts in a row both are back", await _until(online, START_SECONDS))
	await _wait(1.2)
	_check("and the game is still theirs", a.state.get("gameId") == game_id and other.is_my_turn() and other.hand().size() == 14 and mover.hand().size() == 13)
	_check("still without an error", errors_a.is_empty() and errors_b.is_empty(), "%s %s" % [errors_a, errors_b])

	# ---------- the server comes back without its games ----------
	_stop_server()
	await _until(offline, 10.0)
	_start_server(["--forget-games"])
	_check("both get back in after the games were lost", await _until(online, START_SECONDS))
	_check("both are taken off the table that no longer exists", await _until(func() -> bool: return a.state.is_empty() and b.state.is_empty(), 8.0))
	_check("and each is told why, once", errors_a.size() == 1 and errors_b.size() == 1 and str(errors_a[0]).contains("no longer running") and str(errors_b[0]).contains("no longer running"), "%s %s" % [errors_a, errors_b])
	_check("a game that was lost gives everyone their coins back", await _until(func() -> bool: return a.coins == 50000 and b.coins == 50000), "%d %d" % [a.coins, b.coins])
	errors_a.clear()
	errors_b.clear()

	# ---------- a lobby survives too ----------
	r = await a.create_game("pool", 2, 2000)
	var code := str(r.get("roomCode", ""))
	_check("a new game can be created straight away", r.ok and a.status() == "waiting", str(r.get("error", "")))
	await _wait(0.4)
	_stop_server()
	await _until(offline, 10.0)
	_start_server([])
	_check("both are back after one more restart", await _until(online, START_SECONDS))
	await _wait(1.2)
	_check("the lobby is still there, with its room code", a.status() == "waiting" and str(a.state.get("roomCode", "")) == code, a.status())
	_check("and its entry is still paid, once", a.coins == 48000 and a.stake() == 2000, str(a.coins))
	r = await b.join_by_code(code)
	_check("and a friend can still join it by that code", r.ok and await _until(func() -> bool: return a.hand().size() == 13 and b.hand().size() == 13), str(r.get("error", "")))
	_check("no error on the way", errors_a.is_empty() and errors_b.is_empty(), "%s %s" % [errors_a, errors_b])

	await a.leave()
	await b.leave()
	_finish()


func _finish() -> void:
	_stop_server()
	print("\nserver restart: %d passed, %d failed" % [_passed, _failed])
	get_tree().quit(1 if _failed > 0 or _passed == 0 else 0)


# ---------- the server ----------

func _url() -> String:
	return "http://127.0.0.1:%d" % _port


func _start_server(options: Array) -> void:
	var script := ProjectSettings.globalize_path("res://tests/test_server.js")
	var arguments := PackedStringArray([script, "--port=%d" % _port, "--db=%s" % _database])
	arguments.append_array(PackedStringArray(options))
	_server_pid = OS.create_process("node", arguments)


# Stopped dead, with no chance to tidy up: the worst a restart can be.
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
		await _wait(0.3)
	return false


# ---------- helpers ----------

func _new_client() -> GameClient:
	var client := GameClient.new()
	client.remember_login = false
	client.server_url = _url()
	add_child(client)
	return client


func _ids(cards: Array) -> Array:
	return cards.map(func(card: Dictionary) -> Variant: return card.get("id"))


func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout


# Waits until the condition holds, or gives up after `seconds`.
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
