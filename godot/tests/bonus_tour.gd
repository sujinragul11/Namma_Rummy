extends Control
## The daily bonus wheel through the real home screen, played with a finger like ui_tour:
## the pill beside the coins, the wheel turning to the slot the server drew, the coins paid
## once, the countdown, the wheel opening again by itself, and another phone on the same account
## held to the same 24 hours.
##
## Run against a TEST server whose wheel opens again after a few seconds instead of 24 hours
## (it registers throwaway accounts):
##   set DAILY_BONUS_SECONDS=8
##   node tests/test_server.js --fresh --port=3151 --db=My_Rummy_bonus_test
##   godot --path . res://tests/bonus_tour.tscn -- --profile=bonustour --server=http://127.0.0.1:3151 --shots=<folder>
## With --headless every check runs and no pictures are taken.

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
	Sound.sound_on = false
	Game.logout()  # start from the login form even if this profile has a saved login
	_main = (load("res://scenes/main.tscn") as PackedScene).instantiate() as Control
	add_child(_main)
	_run()


func _run() -> void:
	var tag := "%d%04d" % [int(Time.get_unix_time_from_system()) % 1000000, randi() % 10000]
	var name_a := "bt_" + tag
	var message_box: AcceptDialog = Ui.get_node("MessageBox")
	await _wait(0.5)
	var r: Dictionary = await Game.register(name_a, "9" + tag.substr(0, 9), "secret12")
	_check("registered and connected", r.ok and await _until(func() -> bool: return Game.is_online() and _node("MenuPanel") != null and _node("MenuPanel").visible), str(r.get("error", "")))

	# ---------- the pill in the top bar ----------
	var home: Variant = _screen()  # untyped: the tour looks inside the home script
	_check("the app asks the server about the wheel on connecting", await _until(func() -> bool: return not Game.bonus.is_empty()))
	_check("a new player may spin, on a wheel of 12 slots", Game.bonus_available() and Game.bonus_prizes().size() == 12 and Game.bonus_wait() == 0, str(Game.bonus))
	var pill: Button = _node("BonusButton")
	_check("the Daily Bonus pill sits right of the coins", pill != null and pill.is_visible_in_tree() and pill.get_index() == _node("CoinPill").get_index() + 1)
	_check("it is dressed as a waiting spin", await _until(func() -> bool: return home._bonus_ready_shown, 2.0))
	_check("the top bar still fits: the pill ends before the help button", pill.get_global_rect().end.x < _node("HelpButton").get_global_rect().position.x and pill.get_global_rect().position.y >= 0.0, "%s / %s" % [pill.get_global_rect(), _node("HelpButton").get_global_rect()])
	_check("nothing opens by itself", not _box().visible)
	await _shot("menu-spin-waiting")

	# ---------- opening the wheel ----------
	await _press("BonusButton")
	_check("the pill opens the wheel", await _until(func() -> bool: return _box().visible, 2.0))
	await _wait(0.5)
	var wheel: BonusWheel = _node("BonusWheel")
	_check("the wheel shows the server's prizes", wheel.prizes == Game.bonus_prizes())
	_check("the hub says SPIN", wheel.hub_ready and not wheel.spin_button.disabled)
	_check("the line under the wheel invites a spin", _node("BonusStatus").text == "Spin the wheel for free coins, up to 10,000!", _node("BonusStatus").text)
	_check("the wheel fits on the screen", _box_rect().position.y >= 0.0 and _box_rect().end.y <= get_viewport().get_visible_rect().size.y, str(_box_rect()))
	await _shot("wheel-ready")

	# ---------- spinning ----------
	var before := Game.coins
	var spun := [-1, 0]
	Game.bonus_spun.connect(func(index: int, prize: int) -> void:
		spun[0] = index
		spun[1] = prize, CONNECT_ONE_SHOT)
	await _press("SpinButton")
	_check("the hub sets the wheel turning at once", wheel.is_turning() and _node("BonusStatus").text == "Good luck!", _node("BonusStatus").text)
	_check("the server answers with a slot and its prize", await _until(func() -> bool: return spun[0] >= 0, 5.0) and Game.bonus_prizes()[spun[0]] == spun[1], str(spun))
	_check("the coins are paid once, by the server", await _until(func() -> bool: return Game.coins == before + spun[1], 3.0), "%d -> %d" % [before, Game.coins])
	_check("the balance on show waits for the wheel", wheel.is_turning() and _node("CoinsLabel")._label.text == Ui.coins_text(before), _node("CoinsLabel")._label.text)
	_go_back()
	await _wait(0.1)
	_check("the back button does not close the box while the wheel turns", _box().visible and wheel.is_turning())
	_tap(_middle(_node("BonusCloseButton")))
	_check("nor does the close tag", _box().visible)
	await _wait(0.6)
	await _shot("wheel-turning")
	_check("the wheel comes to rest", await _until(func() -> bool: return not wheel.is_turning(), 9.0))
	_check("on the slot the server drew", wheel.slot_at_pointer() == spun[0], "at %d, drawn %d" % [wheel.slot_at_pointer(), spun[0]])
	await _wait(0.4)
	_check("now the balance shows the prize", _node("CoinsLabel")._label.text == Ui.coins_text(before + spun[1]), _node("CoinsLabel")._label.text)
	_check("the line says what was won and when the next spin is", _node("BonusStatus").text.begins_with("You won %s coins!  Next spin in 00:00:0" % Ui.coins_text(spun[1])), _node("BonusStatus").text)
	_check("the hub shows the time to wait", not wheel.hub_ready and wheel.hub_text.begins_with("00:00:0") and not Game.bonus_available(), wheel.hub_text)
	await _shot("wheel-won")

	# ---------- the wheel is closed until the time is up ----------
	var coins_after := Game.coins
	await _press("SpinButton")
	await _wait(0.3)
	_check("pressing the hub again does nothing", not wheel.is_turning() and not Game.bonus_spinning() and Game.coins == coins_after)
	await _press("BonusCloseButton")
	_check("the close tag closes the box at rest", await _until(func() -> bool: return not _box().visible, 2.0))
	_check("the pill counts down", await _until(func() -> bool: return not home._bonus_ready_shown, 2.0) and Game.bonus_wait() > 0)
	await _shot("menu-countdown")
	await _press("BonusButton")
	await _wait(0.4)
	_check("opened again, it shows the countdown", _node("BonusStatus").text.begins_with("Your next free spin is in 00:00:0"), _node("BonusStatus").text)
	await _shot("wheel-waiting")
	_go_back()
	_check("the back button closes it", await _until(func() -> bool: return not _box().visible, 2.0))

	# ---------- another phone, same account ----------
	var phone := GameClient.new()
	phone.remember_login = false
	add_child(phone)
	var refused := [""]
	phone.bonus_failed.connect(func(message: String) -> void: refused[0] = message)
	r = await phone.login(name_a, "secret12")
	_check("another phone logs in", r.ok and await _until(func() -> bool: return phone.is_online() and not phone.bonus.is_empty()))
	_check("it finds the wheel closed too", not phone.bonus_available() and phone.bonus_wait() > 0, str(phone.bonus))
	phone.spin_bonus()
	_check("and its spin is refused by the server", await _until(func() -> bool: return not refused[0].is_empty(), 4.0) and refused[0].contains("already spun"), refused[0])
	_check("with nothing paid", phone.coins == coins_after and Game.coins == coins_after, "%d %d" % [phone.coins, Game.coins])

	# ---------- the time runs out ----------
	_check("the wheel opens again by itself when the time is up", await _until(func() -> bool: return Game.bonus_available(), float(Game.bonus_wait()) / 1000.0 + 6.0), str(Game.bonus))
	_check("on both phones", await _until(func() -> bool: return phone.bonus_available(), 6.0))
	_check("the pill says so", await _until(func() -> bool: return home._bonus_ready_shown, 2.0))
	await _shot("menu-spin-waiting-again")

	# The other phone spins first: this one hears it, closes its wheel, and gets the coins
	refused[0] = ""
	phone.spin_bonus()
	_check("this time the other phone's spin pays", await _until(func() -> bool: return phone.coins > coins_after, 4.0) and refused[0].is_empty(), refused[0])
	_check("this phone hears that the wheel is closed", await _until(func() -> bool: return not Game.bonus_available() and Game.bonus_wait() > 0, 3.0))
	_check("and gets the new balance", await _until(func() -> bool: return Game.coins == phone.coins, 3.0), "%d vs %d" % [Game.coins, phone.coins])

	# ---------- a spin the server refuses ----------
	# As if this phone had not heard about the other one's spin: the wheel still looks open.
	# (Opening the box asks the server again, so the stale state is set once it is open.)
	await _press("BonusButton")
	await _wait(0.6)
	Game._apply_bonus({"available": true, "nextSpinIn": 0})
	await _wait(0.1)
	_check("the hub looks ready", wheel.hub_ready)
	message_box.hide()
	var coins_now := Game.coins
	await _press("SpinButton")
	_check("the server refuses a spin it already paid", await _until(func() -> bool: return message_box.visible, 5.0) and message_box.dialog_text.contains("already spun"), message_box.dialog_text)
	_check("the wheel comes to rest without a prize", await _until(func() -> bool: return not wheel.is_turning(), 5.0) and Game.coins == coins_now)
	_check("and shows the real countdown", not Game.bonus_available() and not wheel.hub_ready and Game.bonus_wait() > 0, "available %s, hub %s, wait %d, %s" % [Game.bonus_available(), wheel.hub_ready, Game.bonus_wait(), Game.bonus])
	await _shot("wheel-refused")
	message_box.hide()
	await _press("BonusCloseButton")

	# ---------- logging out ----------
	Game.logout()
	_check("logging out forgets the wheel", Game.bonus.is_empty() and Game.bonus_ready_at == 0)

	print("\nbonus tour: %d passed, %d failed" % [_passed, _failed])
	Sound.hush()
	get_tree().quit(1 if _failed > 0 or _passed == 0 else 0)


func _box() -> Control:
	return _node("DailyBonusBox")


func _box_rect() -> Rect2:
	return (_box().get_node("Box") as Control).get_global_rect()


func _node(node_name: String) -> Variant:
	return _main.find_child(node_name, true, false)


func _screen() -> Control:
	var holder := _main.get_node("%Screen")
	return holder.get_child(holder.get_child_count() - 1)


# ---------- a finger (as in ui_tour) ----------

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


func _middle(control: Control) -> Vector2:
	return control.get_global_transform_with_canvas() * (control.size / 2.0)


## Taps a button. A button a finger cannot reach fails the tour.
func _press(button_name: String) -> void:
	var button := _node(button_name) as BaseButton
	if button == null or not button.is_visible_in_tree():
		_check("%s can be pressed" % button_name, false)
		return
	var answered := [false]
	var on_pressed := func() -> void: answered[0] = true
	button.pressed.connect(on_pressed)
	var at := _middle(button)
	_tap(at)
	if is_instance_valid(button) and button.pressed.is_connected(on_pressed):
		button.pressed.disconnect(on_pressed)
	_check("%s answers a finger" % button_name, answered[0] or button.disabled, "touched %s; %s" % [at, _under_finger()])
	await get_tree().process_frame


func _go_back() -> void:
	get_tree().root.propagate_notification(NOTIFICATION_WM_GO_BACK_REQUEST)


func _shot(label: String) -> void:
	_step += 1
	if DisplayServer.get_name() == "headless" or _shots.is_empty():
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
