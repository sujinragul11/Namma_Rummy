extends Node
## When full-screen ads may show (autoload/ads.gd): before sitting down at a table, in the
## break between two rounds, and when leaving a finished game; never during a game, never
## twice within the minimum gap, and never without an ad ready. Real games against a real
## server; the ads are stand-ins (a dark cover for a moment), since a PC has no AdMob.
##
## Run against a TEST server (it registers throwaway accounts):
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
	await Ads.before_table()
	_check("so sitting down shows nothing", Ads.shown.is_empty())

	Ads.use_stand_in(STAND_IN_SECONDS)
	Ads.ad_opened.connect(func(_moment: String) -> void: _status_at_open.append(Game.status()))
	var closed_with: Array = []  # the table's status each time an ad closed
	Ads.ad_closed.connect(func(_moment: String) -> void: closed_with.append(Game.status()))

	Game.logout()
	var tag := "%d%04d" % [int(Time.get_unix_time_from_system()) % 1000000, randi() % 10000]
	var number := randi() % 100000000
	var r: Dictionary = await Game.register("ad_" + tag, "ad_%s@test.local" % tag, "95%08d" % number, "secret12")
	_check("player A registers", r.ok, str(r.get("error", "")))
	var b := GameClient.new()
	b.remember_login = false
	add_child(b)
	r = await b.register("bd_" + tag, "bd_%s@test.local" % tag, "85%08d" % number, "secret12")
	_check("player B registers", r.ok, str(r.get("error", "")))
	_check("both are online", await _until(func() -> bool: return Game.is_online() and b.is_online()))
	_check("signing up showed no ad", Ads.shown.is_empty(), str(Ads.shown))

	# ---------- 1. sitting down at a table ----------
	var started := Time.get_ticks_msec()
	r = await Game.create_game("points", 2)
	var took := Time.get_ticks_msec() - started
	_check("opening a table shows an ad first", r.ok and Ads.shown == ["table"], str(Ads.shown))
	_check("the request waits until the ad has gone", took >= STAND_IN_SECONDS * 1000.0 and closed_with == [""], "%d ms, closed while '%s'" % [took, closed_with])
	_check("the ad took every touch while it was up", _status_at_open == [""])
	await Game.leave()
	_check("leaving a lobby is not the end of a game: no ad", Ads.shown.size() == 1, str(Ads.shown))

	r = await Game.create_game("points", 2)
	_check("a second table right after the first: no ad, they are too close", r.ok and Ads.shown.size() == 1, str(Ads.shown))

	# From here on the gap is lifted, to see each moment on its own
	Ads.min_gap_seconds = 0.0

	# ---------- nothing during a game ----------
	r = await b.join_by_code(str(Game.state.get("roomCode", "")))
	_check("the game is dealt", r.ok and await _until(func() -> bool: return Game.status() == "playing" and Game.hand().size() == 13))
	_check("the other player sitting down shows this player nothing", Ads.shown.size() == 1, str(Ads.shown))
	await Ads.before_table()
	_check("no ad while a game is being played, whatever asks for one", Ads.shown.size() == 1, str(Ads.shown))

	# ---------- 3. leaving a finished game ----------
	var mover := Game if Game.is_my_turn() else b
	r = await mover.drop()
	_check("a points game ends when a player drops", r.ok and await _until(func() -> bool: return Game.status() == "finished"))
	await _wait(0.3)
	_check("the result itself shows no ad", Ads.shown.size() == 1, str(Ads.shown))
	await Game.leave()
	_check("leaving the result shows an ad", await _until(func() -> bool: return Ads.shown.size() == 2) and Ads.shown[-1] == "game_over", str(Ads.shown))
	await _until(func() -> bool: return closed_with.size() == 2)
	await b.leave()

	# ---------- 2. the break between two rounds ----------
	r = await Game.create_game("pool", 2)
	_check("a pool table: an ad before sitting down", r.ok and Ads.shown.size() == 3 and Ads.shown[-1] == "table", str(Ads.shown))
	r = await b.join_by_code(str(Game.state.get("roomCode", "")))
	_check("the pool game is dealt", r.ok and await _until(func() -> bool: return Game.status() == "playing" and Game.hand().size() == 13))
	mover = Game if Game.is_my_turn() else b
	r = await mover.drop()
	_check("a drop ends the round, and another round follows", r.ok and await _until(func() -> bool: return Game.status() == "round_over"))
	_check("the break shows an ad", await _until(func() -> bool: return Ads.shown.size() == 4) and Ads.shown[-1] == "round_break", str(Ads.shown))
	var ahead := (Game.next_round_at - Time.get_ticks_msec()) / 1000.0
	_check("with most of the break still ahead", ahead >= Ads.round_break_min_seconds - 1.0, "%.1f s ahead" % ahead)
	_check("the break started after the round, not during it", _status_at_open[-1] == "round_over", str(_status_at_open))
	_check("the next round is dealt", await _until(func() -> bool: return Game.status() == "playing" and int(Game.state.get("round", 0)) == 2, 20.0))
	await _wait(0.5)
	_check("the new deal shows no ad", Ads.shown.size() == 4, str(Ads.shown))

	# A break with too little of it left gets no ad
	Ads.round_break_min_seconds = 13.0  # the break is 12 s
	mover = Game if Game.is_my_turn() else b
	r = await mover.drop()
	await _until(func() -> bool: return Game.status() in ["round_over", "finished"])
	await _wait(0.5)
	if Game.status() == "round_over":
		_check("a break too short for an ad gets none", Ads.shown.size() == 4, str(Ads.shown))
	else:
		print("skipped: the second drop ended the whole pool game")
	Ads.round_break_min_seconds = 9.0

	# Walking away from a game in progress is not the end of a game for this player
	await _until(func() -> bool: return Game.status() in ["playing", "finished"], 20.0)
	var before := Ads.shown.size()
	if Game.status() == "playing":
		await Game.leave()
		await _wait(0.5)
		_check("leaving a game in progress shows no ad", Ads.shown.size() == before, str(Ads.shown))
	await b.leave()
	await Game.leave()

	# ---------- the only moments ----------
	var moments := {}
	for moment: String in Ads.shown:
		moments[moment] = true
	_check("ads showed only at the three moments", moments.keys().all(func(m: String) -> bool: return m in [Ads.TABLE, Ads.ROUND_BREAK, Ads.GAME_OVER]), str(Ads.shown))
	_check("never while a game was being played", not _status_at_open.has("playing"), str(_status_at_open))

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
