extends Control
## Donkey Master through the real screens and a real server. The player on screen (the Game
## autoload) plays with synthetic touches; two more players are GameClients without a screen.
##   1. the game switch opens the Donkey Master home and says Namma Rummy there;
##   2. Play with Friends > Create Room for 3, two friends join with the code, the full table
##      deals by itself, and the whole game is played to the end: the screen player taps their
##      cards (a card that may not be played is refused), the others play what they may;
##   3. the coins: everyone paid the entry, the Donkey lost it to the Master, and the balance in
##      the app is the server's; the result box lists all three;
##   4. Play Again opens a new room and invites the others; leaving it gives the entry back;
##   5. Play Online for 2 finds the other player; leaving mid-game loses the entry to them;
##   6. the switch brings the rummy tiles back.
##
## Run against a TEST server that has Donkey Master (it registers throwaway accounts), with or
## without a window:
##   godot --path . res://tests/donkey_tour.tscn --position -6000,-6000 -- --profile=donkeytour --mute --server=http://127.0.0.1:3191 --shots=<folder>

const PASSWORD := "secret12"
const STAKE := 500
const MAX_PLAYS := 900  # a game of three never needs this many cards played

var _shots := ""
var _main: Control
var _step := 0
var _passed := 0
var _failed := 0
var _url := ""


func _ready() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--shots="):
			_shots = argument.trim_prefix("--shots=")
		elif argument.begins_with("--server="):
			_url = argument.trim_prefix("--server=")
	if not _shots.is_empty():
		DirAccess.make_dir_recursive_absolute(_shots)
	Game.remember_login = false
	Game.logout()
	_main = (load("res://scenes/main.tscn") as PackedScene).instantiate() as Control
	add_child(_main)
	_run()


func _run() -> void:
	var tag := "%d%03d" % [int(Time.get_unix_time_from_system()) % 1000000, randi() % 1000]
	var question_box: ConfirmationDialog = Ui.get_node("QuestionBox")
	await _until(func() -> bool: return not _main.loading(), 20.0)

	# ---------- three players ----------
	var r: Dictionary = await Game.register("da_" + tag, "+919%s1" % tag.substr(0, 8), PASSWORD)
	_check("the screen player registers", r.get("ok", false), str(r.get("error", "")))
	var b := _new_client()
	var c := _new_client()
	r = await b.register("db_" + tag, "+918%s2" % tag.substr(0, 8), PASSWORD)
	_check("player B registers", r.get("ok", false), str(r.get("error", "")))
	r = await c.register("dc_" + tag, "+917%s3" % tag.substr(0, 8), PASSWORD)
	_check("player C registers", r.get("ok", false), str(r.get("error", "")))
	_check("everyone is connected", await _until(func() -> bool: return Game.is_online() and b.is_online() and c.is_online(), 15.0))
	await _until(func() -> bool: return not _main.loading() and _has("MenuPanel"), 15.0)
	_check("everyone starts with 50,000 coins", await _until(func() -> bool: return Game.coins == 50000 and b.coins == 50000 and c.coins == 50000))
	await _wait(0.6)

	# ---------- 1. the switch ----------
	_check("the rummy tiles show first", _node("CloseJokerTile").is_visible_in_tree() and not _node("DonkeyHome").is_visible_in_tree())
	await _press("GameSwitchButton")
	await _wait(0.8)
	_check("the switch opens the Donkey Master home", _node("DonkeyHome").is_visible_in_tree() and not _node("CloseJokerTile").is_visible_in_tree())
	_check("there the switch offers Namma Rummy", (_node("GameSwitchButton") as Button).tooltip_text == "Namma Rummy")
	_check("the coins are the same wallet", _node("CoinsLabel").is_visible_in_tree() and _node("CoinsLabel")._label.text == "50,000", _node("CoinsLabel")._label.text)
	await _shot("donkey-home")

	# ---------- 2. a private room for three ----------
	await _press("DonkeyFriendsCard")
	await _wait(0.4)
	await _press("DonkeyCreateRoomButton")
	await _wait(0.4)
	_check("the setup box offers 2 to 8 seats for a room", range(2, 9).all(func(seats: int) -> bool: return _node("DonkeySeats%d" % seats).is_visible_in_tree()))
	await _press("DonkeySeats3")
	_check("the entry offered first is 500", _node("DonkeyStakeCoins")._label.text == "500", _node("DonkeyStakeCoins")._label.text)
	await _shot("create-room")
	await _press("DonkeySetupButton")
	_check("the room opens with a code", await _until(func() -> bool: return _has("DonkeyRoomCode") and _node("DonkeyRoomCode").text.length() == 6, 8.0))
	var code: String = _node("DonkeyRoomCode").text if _has("DonkeyRoomCode") else ""
	_check("sitting down paid the entry", await _until(func() -> bool: return Game.coins == 50000 - STAKE), str(Game.coins))
	b.donkey.join_room(code)
	_check("B joins with the code and shows in the room", await _until(func() -> bool: return _node("DonkeySeats") != null and _node("DonkeySeats").get_child_count() == 2))
	_check("the host may start with two", await _until(func() -> bool: return _node("DonkeyStartButton").visible))
	await _shot("room")
	c.donkey.join_room(code)
	_check("the full table deals by itself and the table opens", await _until(func() -> bool: return _has("DonkeyTable") and Game.donkey.status() == "playing", 10.0))
	_check("52 cards dealt: 18, 17, 17", Game.donkey.hand().size() + b.donkey.hand().size() + c.donkey.hand().size() == 52 and Game.donkey.hand().size() >= 17, "%d %d %d" % [Game.donkey.hand().size(), b.donkey.hand().size(), c.donkey.hand().size()])
	await _wait(1.0)
	await _shot("dealt")

	var table: Variant = _node("DonkeyTable")
	var plays := 0
	var mine := 0
	var refusals := 0  # turns on which a card that may not be played was tapped first
	var button_checked := false
	var others := [b, c]
	while Game.donkey.status() == "playing" and plays < MAX_PLAYS:
		var turn := str(Game.donkey.state.get("turn", ""))
		if turn.is_empty():
			await get_tree().process_frame  # a trick lies on the table for a moment
			continue
		if turn == Game.player_id:
			var playable: Array = Game.donkey.playable()
			if playable.is_empty():
				await get_tree().process_frame
				continue
			await _wait(0.35)  # the cards settle
			if not Game.donkey.is_my_turn():
				continue
			playable = Game.donkey.playable()
			# On a few turns: a card that may not be played is refused, and nothing is sent
			var not_playable: Array = Game.donkey.hand().filter(func(card: Dictionary) -> bool: return not playable.has(card.id))
			if refusals < 6 and not not_playable.is_empty():
				refusals += 1
				var wrong := str(not_playable[0].id)
				var held := Game.donkey.hand().size()
				_tap(_card_spot(table, wrong))
				await _wait(0.3)
				_check("a card that may not be played is refused", Game.donkey.hand().size() == held and table._picked.is_empty() and table._sent.is_empty(), wrong)
			var id := str(playable[0])
			_tap(_card_spot(table, id))
			await _wait(0.25)
			_check("a tap picks the card and PLAY shows", table._picked == id and _node("DonkeyPlayButton").visible, "%s / %s; %s; view %s; hand %s; playable %s; message %s; question %s" % [
				table._picked, id, _under_finger(), (table._views[id] as CardView).get_global_rect() if table._views.has(id) else "none",
				Game.donkey.hand().map(func(card: Dictionary) -> String: return card.id), Game.donkey.playable(),
				(Ui.get_node("MessageBox") as AcceptDialog).visible, question_box.visible])
			if not button_checked:
				button_checked = true
				await _shot("picked")
				await _press("DonkeyPlayButton")
			else:
				_tap(_card_spot(table, id))  # a second tap plays it
			var played := await _until(func() -> bool: return not Game.donkey.hand().any(func(card: Dictionary) -> bool: return card.id == id) or Game.donkey.status() != "playing", 5.0)
			_check("the card is played", played, id)
			mine += 1
			plays += 1
			if mine == 3:
				await _shot("playing")
			continue
		for client: GameClient in others:
			if turn == client.player_id and client.donkey.is_my_turn() and not client.donkey.playable().is_empty():
				var before := str(client.donkey.state.get("turn", ""))
				await client.donkey.play(str(client.donkey.playable()[0]))
				plays += 1
				await _until(func() -> bool: return str(client.donkey.state.get("turn", "")) != before or client.donkey.status() != "playing", 3.0)
		await get_tree().process_frame
	_check("the game ends", Game.donkey.status() == "finished", "%d cards played" % plays)
	print("donkey_tour: the game took %d cards, %d of them tapped on screen" % [plays, mine])
	var state: Dictionary = Game.donkey.state
	_check("there is a Master and a Donkey", not str(state.get("masterId", "")).is_empty() and not str(state.get("donkeyId", "")).is_empty(), str(state.get("results", [])))
	await _wait(1.0)
	await _shot("finished")
	_check("the result box comes up", await _until(func() -> bool: return _node("DonkeyResult").visible, 6.0))
	_check("it lists all three", _node("DonkeyResultRows").get_child_count() == 3)
	await _wait(0.6)
	await _shot("result")

	# ---------- 3. the coins ----------
	var expected := {}
	for entry: Dictionary in state.get("results", []):
		expected[str(entry.id)] = 50000 + int(entry.coins)
	_check("the Donkey lost the entry, the Master won it, the third got theirs back", expected.values().has(50000 - STAKE) and expected.values().has(50000 + STAKE) and expected.values().has(50000), str(expected))
	_check("the balances on every phone are the server's", await _until(func() -> bool: return Game.coins == expected.get(Game.player_id, -1) and b.coins == expected.get(b.player_id, -1) and c.coins == expected.get(c.player_id, -1)), "%d %d %d / %s" % [Game.coins, b.coins, c.coins, expected])
	_check("no coin was made or lost: 150,000 in all", Game.coins + b.coins + c.coins == 150000)

	# ---------- 4. play again ----------
	var invites := [[], []]
	b.donkey.invite_received.connect(func(invite: Dictionary) -> void: invites[0].append(invite))
	c.donkey.invite_received.connect(func(invite: Dictionary) -> void: invites[1].append(invite))
	var before_again := Game.coins
	await _press("DonkeyPlayAgainButton")
	_check("Play Again opens a new room", await _until(func() -> bool: return _has("DonkeyLobby") and Game.donkey.status() == "waiting" and str(Game.donkey.state.get("roomCode", "")) != code, 8.0))
	_check("and invites the other two to play again", await _until(func() -> bool: return invites[0].size() == 1 and invites[1].size() == 1) and invites[0][0].get("again", false), str(invites))
	_check("the new room took the entry", await _until(func() -> bool: return Game.coins == before_again - STAKE), str(Game.coins))
	await _press("DonkeyLobbyLeaveButton")
	_check("leaving asks first", await _until(func() -> bool: return question_box.visible, 2.0))
	await _press_in_box(question_box, "the question's Leave button")
	_check("back on the Donkey Master home", await _until(func() -> bool: return _has("DonkeyHome") and _node("DonkeyHome").is_visible_in_tree(), 6.0))
	_check("the entry came back", await _until(func() -> bool: return Game.coins == before_again), str(Game.coins))
	b.donkey.leave()
	c.donkey.leave()
	await _wait(0.5)

	# ---------- 5. play online, then leave mid-game ----------
	var before_online := Game.coins
	var b_before := b.coins
	await _press("DonkeyOnlineCard")
	await _wait(0.4)
	_check("Play Online offers 2, 4, 6 and 8 seats", [2, 4, 6, 8].all(func(seats: int) -> bool: return _node("DonkeySeats%d" % seats).is_visible_in_tree()) and not _node("DonkeySeats3").is_visible_in_tree())
	await _press("DonkeySeats2")
	await _press("DonkeySetupButton")
	_check("the search box opens", await _until(func() -> bool: return _node("DonkeySearch").visible and Game.donkey.searching(), 4.0))
	await _wait(0.5)
	await _shot("search")
	b.donkey.find_match(2, STAKE)
	_check("the two are seated together and the table opens", await _until(func() -> bool: return _has("DonkeyTable") and Game.donkey.status() == "playing" and b.donkey.status() == "playing", 30.0))
	_check("the search box went away", not _node("DonkeySearch").visible if _has("DonkeySearch") else true)
	await _wait(1.2)
	await _shot("online-table")
	await _press("DonkeyLeaveTableButton")
	_check("leaving a game asks first and says what it costs", await _until(func() -> bool: return question_box.visible, 2.0) and question_box.dialog_text.contains("500"), question_box.dialog_text)
	await _press_in_box(question_box, "the question's Leave button")
	_check("back home after leaving", await _until(func() -> bool: return _has("DonkeyHome") and _node("DonkeyHome").is_visible_in_tree(), 6.0))
	_check("the other player won: the game ended by leaving", await _until(func() -> bool: return b.donkey.status() == "finished" and str(b.donkey.state.get("endedBy", "")) == "leave", 6.0))
	_check("leaving cost the entry, which went to the other player", await _until(func() -> bool: return Game.coins == before_online - STAKE and b.coins == b_before + STAKE), "%d / %d" % [Game.coins - before_online, b.coins - b_before])
	b.donkey.leave()

	# ---------- 6. back to rummy ----------
	await _press("GameSwitchButton")
	await _wait(0.8)
	_check("the switch brings the rummy tiles back", _node("CloseJokerTile").is_visible_in_tree() and not _node("DonkeyHome").is_visible_in_tree())
	await _shot("rummy-again")
	_finish()


func _finish() -> void:
	print("donkey_tour: %d passed, %d failed" % [_passed, _failed])
	Sound.hush()
	get_tree().quit(1 if _failed > 0 else 0)


# ---------- helpers ----------

func _new_client() -> GameClient:
	var client := GameClient.new()
	client.remember_login = false
	client.server_url = Game.server_url if _url.is_empty() else _url
	add_child(client)
	return client


# The middle of the strip of a hand card that the next card does not cover.
func _card_spot(table: Variant, id: String) -> Vector2:
	var view: CardView = table._views.get(id)
	if view == null:
		_check("the %s is on screen" % id, false)
		return Vector2.ZERO
	var right := view.global_position.x + view.size.x
	for other_id: String in table._views:
		var other: CardView = table._views[other_id]
		if other != view and other.has_meta("in_hand") and other.global_position.x > view.global_position.x and other.global_position.x < right:
			right = other.global_position.x
	return Vector2((view.global_position.x + right) / 2.0, view.global_position.y + 34.0)


func _node(node_name: String) -> Variant:
	return _main.find_child(node_name, true, false)


func _has(node_name: String) -> bool:
	return _node(node_name) != null


func _to_window(at: Vector2) -> Vector2:
	return get_viewport().get_final_transform() * at


func _touch(at: Vector2, down: bool) -> void:
	var event := InputEventScreenTouch.new()
	event.index = 0
	event.pressed = down
	event.position = _to_window(at)
	Input.parse_input_event(event)
	Input.flush_buffered_events()


func _tap(at: Vector2) -> void:
	_touch(at, true)
	_touch(at, false)


func _under_finger() -> String:
	var hit := get_viewport().gui_get_hovered_control()
	return "the finger was on nothing" if hit == null else "the finger was on %s" % hit.get_path()


## Taps a button of one of the screens. A button a finger cannot reach fails the tour.
func _press(button_name: String) -> void:
	var button := _node(button_name) as BaseButton
	if button == null or button.disabled or not button.is_visible_in_tree():
		_check("%s can be pressed" % button_name, false)
		return
	await _press_button(button, button_name)


func _press_button(button: BaseButton, what: String, origin: Vector2 = Vector2.ZERO) -> void:
	await get_tree().process_frame
	var answered := [false]
	var on_pressed := func() -> void: answered[0] = true
	button.pressed.connect(on_pressed)
	var at := origin + button.get_global_transform_with_canvas() * (button.size / 2.0)
	_tap(at)
	if is_instance_valid(button) and button.pressed.is_connected(on_pressed):
		button.pressed.disconnect(on_pressed)
	_check("%s answers a finger" % what, answered[0], "touched %s; %s" % [at, _under_finger()])


func _press_in_box(box: AcceptDialog, what: String) -> void:
	if not box.visible:
		_check("%s is on screen" % what, false)
		return
	await _press_button(box.get_ok_button(), what, Vector2(box.position))


func _shot(label: String) -> void:
	_step += 1
	if _shots.is_empty() or DisplayServer.get_name() == "headless":
		return
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("%s/%02d-%s.png" % [_shots, _step, label])


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
