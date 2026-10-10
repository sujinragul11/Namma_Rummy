extends Node
## Play coins, through a real server: every account starts with 50,000; sitting down at a
## table costs its entry; leaving before the start gives it back; the winner takes the pot;
## nobody can sit at a table they cannot pay for.
##
## Run against a TEST server (it registers throwaway accounts); tests/test_server.js is one:
##   godot --headless --path . res://tests/coins_e2e.tscn -- --server=http://127.0.0.1:3101

const START := 50000

var _passed := 0
var _failed := 0


func _ready() -> void:
	_run()


func _run() -> void:
	var tag := "%d%04d" % [int(Time.get_unix_time_from_system()) % 1000000, randi() % 10000]
	var number := randi() % 10000000
	var a := _new_client()
	var b := _new_client()
	var c := _new_client()
	var errors: Array = []
	for client: GameClient in [a, b, c]:
		client.action_failed.connect(func(message: String) -> void: errors.append(message))

	var r: Dictionary = await a.register("ca_" + tag, "ca_%s@test.local" % tag, "97%08d" % number, "secret12")
	_check("A registers", r.ok, str(r.get("error", "")))
	r = await b.register("cb_" + tag, "cb_%s@test.local" % tag, "87%08d" % number, "secret12")
	r = await c.register("cc_" + tag, "cc_%s@test.local" % tag, "77%08d" % number, "secret12")
	_check("all three are connected", await _until(func() -> bool: return a.is_online() and b.is_online() and c.is_online()))
	_check("a new account has 50,000 coins", await _has(a, START) and await _has(b, START) and await _has(c, START), "%d %d %d" % [a.coins, b.coins, c.coins])

	# ---------- sitting down and getting up again ----------
	r = await a.create_game("points", 2, 5000)
	_check("opening a table costs its entry", r.ok and await _has(a, 45000), "%s %d" % [r.get("error", ""), a.coins])
	_check("the table says what it is played for", a.stake() == 5000 and a.pot() == 5000, "%d / %d" % [a.stake(), a.pot()])
	await a.leave()
	_check("leaving before the start gives the entry back", await _has(a, START), str(a.coins))

	# ---------- a game for coins: the winner takes the pot ----------
	r = await a.create_game("points", 2, 5000)
	r = await b.join_by_code(str(r.get("roomCode", "")))
	_check("the second player pays to sit down too", r.ok and await _has(b, 45000) and await _has(a, 45000), "%d %d" % [a.coins, b.coins])
	_check("the game is dealt with both entries in the pot", await _until(func() -> bool: return a.hand().size() == 13 and b.hand().size() == 13) and a.pot() == 10000 and b.stake() == 5000, str(a.pot()))
	var mover := a if a.is_my_turn() else b
	var other := b if mover == a else a
	r = await mover.drop()
	_check("one player gives up", r.ok and await _until(func() -> bool: return a.status() == "finished" and b.status() == "finished"), str(r.get("error", "")))
	_check("the other takes the pot", await _has(other, 55000) and await _has(mover, 45000), "%d %d" % [other.coins, mover.coins])
	_check("the result still shows the pot", other.pot() == 10000 and other.state.get("winner") == other.player_id)
	await a.leave()
	await b.leave()

	# ---------- leaving a game in progress forfeits the entry ----------
	r = await mover.create_game("points", 2, 1000)
	r = await other.join_by_code(str(r.get("roomCode", "")))
	_check("a second game is dealt", r.ok and await _until(func() -> bool: return a.hand().size() == 13 and b.hand().size() == 13))
	await mover.leave()
	_check("whoever stays wins the pot of a player who walks away", await _has(other, 56000) and await _has(mover, 44000), "%d %d" % [other.coins, mover.coins])
	await other.leave()
	# from here: `other` has 56,000 and `mover` 44,000

	# ---------- tables one cannot afford ----------
	errors.clear()
	r = await mover.create_game("points", 2, 50000)
	_check("a table one cannot pay for cannot be opened", not r.ok and str(r.get("error", "")).contains("50,000 coins") and mover.state.is_empty(), str(r.get("error", "")))
	_check("and nothing was taken", await _has(mover, 44000) and errors.size() == 1, "%d %s" % [mover.coins, errors])
	r = await c.create_game("points", 2, 50000)
	_check("exactly enough is enough", r.ok and await _has(c, 0), "%s %d" % [r.get("error", ""), c.coins])
	var dear_table := str(r.get("roomCode", ""))
	r = await mover.join_by_code(dear_table)
	_check("nor can it be joined", not r.ok and str(r.get("error", "")) == "You need 50,000 coins to sit at this table" and mover.state.is_empty(), str(r.get("error", "")))
	_check("still nothing was taken", await _has(mover, 44000), str(mover.coins))
	await c.leave()
	_check("the host of the table nobody could join gets the entry back", await _has(c, START), str(c.coins))
	r = await c.create_game("points", 2, 3000)
	_check("only the listed entries exist", not r.ok and c.state.is_empty() and await _has(c, START), str(r.get("error", "")))

	# ---------- a free table ----------
	r = await c.create_game("points", 2)
	_check("a free table costs nothing", r.ok and c.stake() == 0 and c.pot() == 0 and await _has(c, START))
	await c.leave()

	# ---------- three players ----------
	r = await a.create_game("pool", 3, 2000)
	var code := str(r.get("roomCode", ""))
	r = await b.join_by_code(code)
	r = await c.join_by_code(code)
	_check("three players sit down", r.ok and await _until(func() -> bool: return a.hand().size() == 13 and b.hand().size() == 13 and c.hand().size() == 13) and a.pot() == 6000, str(a.pot()))
	var before_a := a.coins
	await b.leave()
	_check("with two still playing nobody is paid yet", a.status() in ["playing", "round_over"] and a.coins == before_a and a.pot() == 6000, "%s %d" % [a.status(), a.pot()])
	await c.leave()
	_check("the last one at the table takes all three entries", await _has(a, before_a + 6000), "%d, was %d" % [a.coins, before_a])
	await a.leave()

	# ---------- the balance is the server's, not the app's ----------
	var again := _new_client()
	r = await again.login("ca_" + tag, "secret12")
	_check("logging in elsewhere shows the same balance", r.ok and await _has(again, a.coins), "%d vs %d" % [again.coins, a.coins])
	_check("all coins are accounted for", a.coins + b.coins + c.coins == START * 3, "%d + %d + %d" % [a.coins, b.coins, c.coins])

	print("\ncoins end-to-end: %d passed, %d failed" % [_passed, _failed])
	get_tree().quit(1 if _failed > 0 or _passed == 0 else 0)


# Waits for a balance to arrive: the server sends it after the move that changed it.
func _has(client: GameClient, coins: int) -> bool:
	return await _until(func() -> bool: return client.coins == coins, 4.0)


func _new_client() -> GameClient:
	var client := GameClient.new()
	client.remember_login = false
	add_child(client)
	return client


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
