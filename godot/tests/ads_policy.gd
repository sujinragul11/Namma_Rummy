extends Node
## When full-screen ads may show (autoload/ads.gd): only when the player leaves the result of a
## whole game that has finished, before the next request goes out. Never before sitting down,
## never during a game or between its rounds, never twice within the minimum gap, never without
## an ad ready. Real games against a real server; the ads are stand-ins (a dark cover for a
## moment), since a PC has no AdMob.
##
## Run against a TEST server with the normal 12 s break between rounds, so not one started with
## NEXT_ROUND_SECONDS (it registers throwaway accounts):
##   godot --headless --path . res://tests/ads_policy.tscn -- --profile=adstest --server=http://127.0.0.1:3101

const STAND_IN_SECONDS := 0.6

var _passed := 0
var _failed := 0
var _status_at_open := []  # the table's status each time an ad opened


func _ready() -> void:
	_run()


func _run() -> void:
	# ---------- a PC build has no ads ----------
	_check("there are no real ads on the PC", not Ads.available())
	await Ads.after_game()
	_check("so the end of a game shows nothing", Ads.shown.is_empty())

	Ads.use_stand_in(STAND_IN_SECONDS)
	Ads.ad_opened.connect(func(_moment: String) -> void: _status_at_open.append(Game.status()))
	var closed_with: Array = []  # the table's status each time an ad closed
	Ads.ad_closed.connect(func(_moment: String) -> void: closed_with.append(Game.status()))

	Game.logout()
	var tag := "%06d%04d" % [int(Time.get_unix_time_from_system()) % 1000000, randi() % 10000]
	var number := randi() % 100000000
	var r: Dictionary = await Game.register("ad_" + tag, "95%08d" % number, "secret12")
	_check("player A registers", r.ok, str(r.get("error", "")))
	var b := GameClient.new()
	b.remember_login = false
	add_child(b)
	r = await b.register("bd_" + tag, "85%08d" % number, "secret12")
	_check("player B registers", r.ok, str(r.get("error", "")))
	_check("both are online", await _until(func() -> bool: return Game.is_online() and b.is_online()))
	_check("signing up showed no ad", Ads.shown.is_empty(), str(Ads.shown))

	# ---------- sitting down: no ad ----------
	var started := Time.get_ticks_msec()
	r = await Game.create_game("points", 2)
	_check("opening a table shows no ad", r.ok and Ads.shown.is_empty(), str(Ads.shown))
	_check("and does not wait for one", Time.get_ticks_msec() - started < STAND_IN_SECONDS * 1000.0, "%d ms" % (Time.get_ticks_msec() - started))
	await Game.leave()
	_check("leaving a lobby is not the end of a game: no ad", Ads.shown.is_empty(), str(Ads.shown))

	r = await Game.create_game("points", 2)
	r = await b.join_by_code(str(Game.state.get("roomCode", "")))
	_check("the game is dealt", r.ok and await _until(func() -> bool: return Game.status() == "playing" and Game.hand().size() == 13))
	_check("the other player sitting down shows this player nothing", Ads.shown.is_empty(), str(Ads.shown))
	await Ads.after_game()
	_check("no ad while a game is being played, whatever asks for one", Ads.shown.is_empty(), str(Ads.shown))

	# ---------- the end of the whole game ----------
	var mover := Game if Game.is_my_turn() else b
	r = await mover.drop()
	_check("a points game ends when a player drops", r.ok and await _until(func() -> bool: return Game.status() == "finished"))
	await _wait(0.3)
	_check("the result itself shows no ad", Ads.shown.is_empty(), str(Ads.shown))
	started = Time.get_ticks_msec()
	await Game.leave()
	_check("leaving the result shows an ad first", Ads.shown == [Ads.GAME_OVER] and Time.get_ticks_msec() - started >= STAND_IN_SECONDS * 1000.0, "%s, %d ms" % [Ads.shown, Time.get_ticks_msec() - started])
	_check("over the result, before the table was left", _status_at_open == ["finished"] and closed_with == ["finished"], "%s / %s" % [_status_at_open, closed_with])
	await b.leave()

	# ---------- the next game too soon: no second ad ----------
	r = await Game.create_game("points", 2)
	r = await b.join_by_code(str(Game.state.get("roomCode", "")))
	_check("a second game is dealt", r.ok and await _until(func() -> bool: return Game.status() == "playing" and Game.hand().size() == 13))
	mover = Game if Game.is_my_turn() else b
	await mover.drop()
	_check("and ends", await _until(func() -> bool: return Game.status() == "finished"))
	r = await Game.play_again()
	_check("Play Again within the minimum gap: no second ad", r.ok and Ads.shown.size() == 1 and Game.status() == "waiting", "%s, %s" % [Ads.shown, Game.status()])
	await Game.leave()
	await b.leave()

	# From here on the gap is lifted, to see each moment on its own
	Ads.min_gap_seconds = 0.0

	# ---------- between rounds: never ----------
	r = await Game.create_game("pool", 2)
	_check("a pool table: no ad before sitting down", r.ok and Ads.shown.size() == 1, str(Ads.shown))
	r = await b.join_by_code(str(Game.state.get("roomCode", "")))
	_check("the pool game is dealt", r.ok and await _until(func() -> bool: return Game.status() == "playing" and Game.hand().size() == 13))
	mover = Game if Game.is_my_turn() else b
	r = await mover.drop()
	_check("a drop ends the round, and another round follows", r.ok and await _until(func() -> bool: return Game.status() == "round_over"))
	await _wait(2.0)
	_check("the break between rounds shows no ad", Ads.shown.size() == 1, str(Ads.shown))
	_check("the next round is dealt", await _until(func() -> bool: return Game.status() == "playing" and int(Game.state.get("round", 0)) == 2, 20.0))
	await _wait(0.5)
	_check("the new deal shows no ad", Ads.shown.size() == 1, str(Ads.shown))

	# Walking away from a game in progress is not the end of a game for this player
	await Game.leave()
	await _wait(0.5)
	_check("leaving a game in progress shows no ad", Ads.shown.size() == 1, str(Ads.shown))
	await b.leave()

	# ---------- Play Again from a finished game ----------
	r = await Game.create_game("points", 2)
	r = await b.join_by_code(str(Game.state.get("roomCode", "")))
	_check("a third game is dealt", r.ok and await _until(func() -> bool: return Game.status() == "playing" and Game.hand().size() == 13))
	mover = Game if Game.is_my_turn() else b
	await mover.drop()
	_check("and ends", await _until(func() -> bool: return Game.status() == "finished"))
	r = await Game.play_again()
	_check("Play Again shows the ad first", r.ok and Ads.shown.size() == 2 and Ads.shown[-1] == Ads.GAME_OVER, str(Ads.shown))
	_check("over the result, before the new table was asked for", _status_at_open[-1] == "finished" and closed_with[-1] == "finished", "%s / %s" % [_status_at_open, closed_with])
	_check("then the new table opens with no other ad", Game.status() == "waiting" and Ads.shown.size() == 2, "%s, %s" % [Game.status(), Ads.shown])
	await Game.leave()
	await b.leave()

	# ---------- the only moment ----------
	_check("ads showed only when a finished game was left", Ads.shown.all(func(m: String) -> bool: return m == Ads.GAME_OVER), str(Ads.shown))
	_check("never at a table with a game under way", _status_at_open.all(func(s: String) -> bool: return s == "finished"), str(_status_at_open))

	Game.logout()
	print("\nads policy: %d passed, %d failed" % [_passed, _failed])
	get_tree().quit(1 if _failed > 0 or _passed == 0 else 0)


func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout


# Waits until the condition holds, or gives up after `seconds`.
func _until(condition: Callable, seconds: float = 8.0) -> bool:
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
