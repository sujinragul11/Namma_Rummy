extends Control
## "Play Now" through the real screens: a game tile, its setup box, the search box, and the
## table the server seats the player at, with screenless players searching from other phones.
## No room code anywhere. Covers Points for coins a point, cancelling a search, a six-seat
## Pool 201 table that starts with the three players found, Deals Rummy, and a player from
## another region who is matched only once the search has widened.
##
## Buttons are pressed with a finger (touch events), as in tests/ui_tour.
##
## Against a TEST server started with short matchmaking waits:
##   MATCH_REGION_SECONDS=2 MATCH_NEARBY_SECONDS=4 MATCH_FILL_SECONDS=3 NEXT_ROUND_SECONDS=2 \
##     node tests/test_server.js --fresh --port=3101 --db=My_Rummy_test
##   godot --headless --path . res://tests/match_e2e.tscn -- --profile=matchtest --server=http://127.0.0.1:3101 --mute
## With a window and --shots=<folder> it also saves a picture of every step.

const PASSWORD := "secret12"

var _shots := ""
var _main: Control
var _step := 0
var _passed := 0
var _failed := 0


func _ready() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--shots="):
			_shots = argument.trim_prefix("--shots=")
	if not _shots.is_empty():
		DirAccess.make_dir_recursive_absolute(_shots)

	Game.logout()
	Game.remember_login = false
	_main = (load("res://scenes/main.tscn") as PackedScene).instantiate() as Control
	add_child(_main)
	_run()


func _run() -> void:
	var tag := "%d%03d" % [int(Time.get_unix_time_from_system()) % 100000, randi() % 1000]
	var b := await _player("Bala" + tag)
	var c := await _player("Chitra" + tag)
	await Game.register("Anu" + tag, "anu%s@test.local" % tag, _phone(), PASSWORD)
	_check("logged in and online", await _until(func() -> bool: return Game.is_online() and _shown("MenuPanel")))
	await _wait(0.6)
	_check("the tiles are the four of the lobby", _shown("PointsTile") and _shown("PoolTile") and _shown("DealsTile") and _shown("FriendsTile"))
	await _shot("menu")

	# ---------- Points, 2 players, 10 coins a point ----------
	await _press("PointsTile")
	await _wait(0.4)
	_check("the Points box offers 2 or 6 players", _chip("2P").visible and _chip("6P").visible and not _chip("3P").visible and not _chip("4P").visible and not _chip("5P").visible)
	_check("and a point value, 10 to begin with", _node("StakeCoins")._label.text == "10 per point" and _text("StakeLabel") == "SELECT POINT VALUE", _node("StakeCoins")._label.text)
	_check("its button is Play Now", _text("CreateButton") == "Play Now", _text("CreateButton"))
	await _shot("points-setup")
	await _press("CreateButton")
	_check("Play Now opens the search box", await _until(func() -> bool: return _shown("CancelSearchButton")) and not _shown("CreateButton"))
	_check("which names the table", _text("SearchGame").contains("Points Rummy") and _text("SearchGame").contains("2 players") and _text("SearchGame").contains("10 coins a point"), _text("SearchGame"))
	_check("and says it looks in the player's region first", await _until(func() -> bool: return _text("SearchScope").begins_with("Looking for players in your region")), _text("SearchScope"))
	_check("nobody is found yet", _text("SearchCount") == "Searching for players..." and Game.searching(), _text("SearchCount"))
	await _shot("searching")

	var r: Dictionary = await b.find_match("points", 2, 0, 10)
	_check("another phone searching for the same table", r.get("ok", false), str(r))
	_check("the table opens by itself, with no room code typed", await _until(func() -> bool: return _has("HandArea") and Game.hand().size() == 13))
	_check("the search is over on both phones", not Game.searching() and not b.searching())
	_check("both sit at the same table", Game.state.get("gameId") == b.state.get("gameId") and Game.players().size() == 2)
	_check("played for 10 coins a point", Game.point_value() == 10 and await _until(func() -> bool: return _text("RoomLabel").contains("10 coins a point")), _text("RoomLabel"))
	_check("800 coins are held while playing", await _until(func() -> bool: return Game.coins == 49200), str(Game.coins))
	await _wait(1.5)
	await _shot("points-table")

	# Whoever is on turn drops: 20 points, 200 coins
	var dropper := Game if Game.is_my_turn() else b
	var other := b if dropper == Game else Game
	await dropper.drop()
	_check("the result opens", await _until(func() -> bool: return _shown("ResultOverlay")))
	await _wait(1.0)
	var rows_text := _labels_in("ResultRows")
	_check("the result shows the coins lost and won", rows_text.contains("-200 coins") and rows_text.contains("+200 coins"), rows_text)
	var prize_text: String = _node("PrizeLabel")._label.text
	var prize_says := "200 coins won" if other == Game else "200 coins go to %s" % str(b.user.get("username", ""))
	_check("the result names the coins won", _shown("PrizeLabel") and prize_text == prize_says, prize_text)
	_check("the loser paid 200, the winner got it", await _until(func() -> bool: return dropper.coins == 49800 and other.coins == 50200), "%d / %d" % [dropper.coins, other.coins])
	await _shot("points-result")
	await _press("BackButton")
	_check("back on the menu", await _until(func() -> bool: return _shown("MenuPanel")))
	await b.leave()
	await _wait(0.5)

	# ---------- cancelling a search ----------
	await _press("PoolTile")
	await _wait(0.4)
	await _press_button(_chip("201 Points"), "the 201 Points mark")
	await _press_button(_chip("6P"), "the 6P mark")
	_check("Pool offers 101 and 201", _chip("101 Points").visible and _chip("201 Points").visible and _text("SetupTitle") == "Pool Rummy")
	_check("and an entry, 500 to begin with", _node("StakeCoins")._label.text == "500" and _text("StakeLabel") == "SELECT ENTRY AMOUNT", _node("StakeCoins")._label.text)
	await _press("CreateButton")
	await _until(func() -> bool: return _shown("CancelSearchButton"))
	r = await c.find_match("pool_201", 6, 500)
	_check("a second searcher shows up in the box with a countdown", await _until(func() -> bool: return _text("SearchCount").begins_with("2 of 6 players found") and _text("SearchCount").contains("starting in")), _text("SearchCount"))
	await _shot("found-two-of-six")
	await _press("CancelSearchButton")
	_check("Cancel closes the box and ends the search", not _shown("CancelSearchButton") and not Game.searching())
	_check("the other searcher sees one player fewer", await _until(func() -> bool: return int(c.match_status.get("found", 0)) == 1), str(c.match_status))
	await c.cancel_match()
	await _wait(0.3)

	# ---------- six seats: three players start together when the countdown ends ----------
	await _press("PoolTile")
	await _wait(0.4)
	await _press_button(_chip("201 Points"), "the 201 Points mark")
	await _press_button(_chip("6P"), "the 6P mark")
	await _press("CreateButton")
	await b.find_match("pool_201", 6, 500)
	await c.find_match("pool_201", 6, 500)
	_check("three of six found", await _until(func() -> bool: return _text("SearchCount").begins_with("3 of 6 players found")), _text("SearchCount"))
	_check("the table starts with the three after the countdown", await _until(func() -> bool: return _has("HandArea") and Game.hand().size() == 13, 10.0))
	_check("Pool 201 with three players", Game.players().size() == 3 and int(Game.state.get("poolLimit", 0)) == 201 and await _until(func() -> bool: return _text("RoomLabel").contains("Pool 201")), _text("RoomLabel"))
	_check("the pot holds the three entries", _text("RoomLabel").ends_with("Pot 1,500"), _text("RoomLabel"))
	await _wait(1.5)
	await _shot("pool-201-three")
	await b.leave()
	await c.leave()
	_check("the last player left wins", await _until(func() -> bool: return _shown("ResultOverlay") and Game.status() == "finished"))
	await _press("BackButton")
	await _until(func() -> bool: return _shown("MenuPanel"))
	await _wait(0.5)

	# ---------- Deals Rummy ----------
	await _press("DealsTile")
	await _wait(0.4)
	_check("the Deals box offers 2 or 3 deals and no seats", _chip("2 Deals").visible and _chip("3 Deals").visible and not _shown("PlayersColumn") and _text("SetupTitle") == "Deals Rummy")
	await _shot("deals-setup")
	await _press("CreateButton")
	await _until(func() -> bool: return _shown("CancelSearchButton"))
	await b.find_match("deals_2", 2, 500)
	_check("the Deals table opens", await _until(func() -> bool: return _has("HandArea") and Game.hand().size() == 13))
	_check("it says which deal is played", await _until(func() -> bool: return _text("RoomLabel").contains("2-Deal") and _text("RoomLabel").contains("Deal 1 of 2")), _text("RoomLabel"))
	_check("each player starts with 160 chips", await _until(func() -> bool: return _text("TotalLabel") == "Your chips: 160" and _badge_text().contains("160 chips")), "%s | %s" % [_text("TotalLabel"), _badge_text()])
	await _wait(1.5)
	await _shot("deals-table")
	dropper = Game if Game.is_my_turn() else b
	await dropper.drop()
	_check("the deal's result opens", await _until(func() -> bool: return _shown("ResultOverlay")))
	await _wait(1.0)
	_check("it names the deal", _text("ResultTitle").ends_with("won deal 1"), _text("ResultTitle"))
	rows_text = _labels_in("ResultRows")
	_check("and the chips that changed hands", rows_text.contains("-20 chips (140)") and rows_text.contains("+20 chips (180)"), rows_text)
	await _shot("deals-result")
	_check("the second deal follows by itself", await _until(func() -> bool: return Game.status() == "playing" and int(Game.state.get("round", 0)) == 2, 8.0) and _text("RoomLabel").contains("Deal 2 of 2"), _text("RoomLabel"))
	await b.leave()
	_check("leaving the deals ends the game for the one left", await _until(func() -> bool: return Game.status() == "finished"))
	await _wait(0.5)
	await _press("BackButton")
	await _until(func() -> bool: return _shown("MenuPanel"))
	await _wait(0.5)

	# ---------- a player from another region ----------
	await _press("PointsTile")
	await _wait(0.4)
	(_node("StakeSlider") as HSlider).value = 0  # a free table
	_check("a free Points table", _shown("FreeLabel"))
	await _press("CreateButton")
	await _until(func() -> bool: return _shown("CancelSearchButton"))
	# A phone on New York time: five and a half hours and more from here
	var far_zone := GameClient.time_zone_minutes() - 600
	var far: Dictionary = await b.socket.request("findMatch", {"gameType": "points", "maxPlayers": 2, "pointValue": 0, "timezone": far_zone})
	_check("the far player is searching", far.get("ok", false), str(far))
	await _wait(1.0)
	_check("players far apart are not matched at first", Game.searching() and _text("SearchScope").contains("your region"), _text("SearchScope"))
	_check("then the search reaches nearby regions", await _until(func() -> bool: return _text("SearchScope").contains("nearby regions"), 6.0), _text("SearchScope"))
	await _shot("searching-nearby")
	_check("and in the end everywhere, where the far player is found", await _until(func() -> bool: return _has("HandArea") and Game.hand().size() == 13, 8.0))
	await b.leave()
	await _until(func() -> bool: return Game.status() == "finished")
	await _wait(0.3)

	Game.logout()
	await _wait(0.3)
	Sound.hush()
	print("\nmatch e2e: %d passed, %d failed, %d pictures in %s" % [_passed, _failed, _step, _shots])
	get_tree().quit(1 if _failed > 0 else 0)


# Registration asks for an Indian mobile number: ten digits, the first from 6 to 9.
func _phone() -> String:
	return "9%09d" % (randi() % 1000000000)


# A second player without a screen, registered and connected.
func _player(username: String) -> GameClient:
	var client := GameClient.new()
	client.remember_login = false
	add_child(client)
	await client.register(username, username + "@test.local", _phone(), PASSWORD)
	await _until(func() -> bool: return client.is_online())
	return client


# ---------- reading the screen ----------

func _node(node_name: String) -> Variant:
	return _main.find_child(node_name, true, false)


func _has(node_name: String) -> bool:
	var node: Node = _node(node_name)
	return node != null and not node.is_queued_for_deletion()


func _shown(node_name: String) -> bool:
	var control := _node(node_name) as Control
	return control != null and control.is_visible_in_tree()


func _text(node_name: String) -> String:
	return str(_node(node_name).text) if _has(node_name) else "(no %s)" % node_name


# A round mark of the setup box (players, pool or deals), found by its words.
func _chip(words: String) -> Control:
	for chip: Node in _main.find_children("*", "Button", true, false):
		if chip is ChoiceChip and (chip as Button).text == words:
			return chip as Control
	return Control.new()  # not there: invisible, so the checks fail


# Everything written under a node, joined.
func _labels_in(node_name: String) -> String:
	var root := _node(node_name) as Node
	if root == null:
		return ""
	var texts: Array = []
	for label: Label in root.find_children("*", "Label", true, false):
		texts.append(label.text)
	return " | ".join(texts)


# What the opponents' badges say.
func _badge_text() -> String:
	return _labels_in("Opponents")


# ---------- a finger ----------

func _touch(at: Vector2, down: bool) -> void:
	var event := InputEventScreenTouch.new()
	event.index = 0
	event.pressed = down
	event.position = get_viewport().get_final_transform() * at  # layout units to window pixels
	Input.parse_input_event(event)
	Input.flush_buffered_events()


func _tap(at: Vector2) -> void:
	_touch(at, true)
	_touch(at, false)


func _middle(control: Control) -> Vector2:
	return control.get_global_transform_with_canvas() * (control.size / 2.0)


## Taps a button of the screen. A button a finger cannot reach fails the test.
func _press(button_name: String) -> void:
	await _press_button(_node(button_name) as BaseButton, button_name)


func _press_button(button: Control, what: String) -> void:
	var base := button as BaseButton
	if base == null or base.disabled or not base.is_visible_in_tree():
		_check("%s can be pressed" % what, false)
		return
	var answered := [false]
	var on_pressed := func() -> void: answered[0] = true
	base.pressed.connect(on_pressed)
	_tap(_middle(base))
	if is_instance_valid(base) and base.pressed.is_connected(on_pressed):
		base.pressed.disconnect(on_pressed)
	var hit := get_viewport().gui_get_hovered_control()
	_check("%s answers a finger" % what, answered[0], "touched %s, which is on %s" % [_middle(base), "nothing" if hit == null else str(hit.get_path())])
	await _wait(0.15)


func _shot(label: String) -> void:
	_step += 1
	if _shots.is_empty():
		return
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("%s/%02d-%s.png" % [_shots, _step, label])


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
