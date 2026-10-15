extends Control
## Opening the profile must show the profile, and nothing else: no question pops up by itself.
## It is opened with a finger, from the avatar at the top left, from the coins beside it and
## from the gear, and once more with a mouse click as on a PC.
##
## Run against a TEST server (it registers a throwaway account):
##   godot --headless --path . res://tests/profile_open.tscn -- --profile=profiletest --server=http://127.0.0.1:3101

var _main: Control
var _passed := 0
var _failed := 0


func _ready() -> void:
	Game.logout()
	_main = (load("res://scenes/main.tscn") as PackedScene).instantiate() as Control
	add_child(_main)
	_run()


func _run() -> void:
	var tag := "%d%04d" % [int(Time.get_unix_time_from_system()) % 1000000, randi() % 10000]
	var r: Dictionary = await Game.register("po_" + tag, "po_%s@test.local" % tag, "96%08d" % (randi() % 100000000), "secret12")
	_check("registered", r.ok, str(r.get("error", "")))
	_check("the menu is shown", await _until(func() -> bool: return _has("AvatarPill") and _node("AvatarPill").is_visible_in_tree() and Game.is_online()))
	await _wait(0.8)

	await _open_with("AvatarPill", true)
	await _open_with("AvatarPill", false)
	# The picture is the only way to the profile (the user's choice, 2026-10-14): neither the
	# bottom bar nor the coins beside the picture lead there
	_check("the bottom bar has no Profile button", _main.find_child("ProfileButton", true, false) == null)
	var coins := _middle(_node("CoinPill"))
	_touch(coins, true)
	await get_tree().process_frame
	_touch(coins, false)
	await _wait(0.6)
	_check("a finger on the coins opens nothing", get_tree().get_first_node_in_group(FriendsPanel.BACK_GROUP) == null and _open_boxes().is_empty())
	# The cog opens Settings (with Log out in it), and its lift must not press anything there either
	await _open_with("AccountButton", true, "SettingsBox")

	# A finger that touches the avatar and slides off it before lifting has changed its mind
	var from := _middle(_node("AvatarPill"))
	_touch(from, true)
	var drag := InputEventScreenDrag.new()
	drag.index = 0
	drag.position = _to_window(from + Vector2(0, 300))
	drag.relative = drag.position - _to_window(from)
	Input.parse_input_event(drag)
	Input.flush_buffered_events()
	_touch(from + Vector2(0, 300), false)
	await _wait(0.5)
	_check("a finger that slides off the avatar opens nothing", get_tree().get_first_node_in_group(FriendsPanel.BACK_GROUP) == null and _open_boxes().is_empty())

	print("\nprofile open: %d passed, %d failed" % [_passed, _failed])
	get_tree().quit(1 if _failed > 0 or _passed == 0 else 0)


func _open_with(opener: String, finger: bool, expected: String = "ProfilePanel") -> void:
	var how := "a finger" if finger else "a mouse click"
	var at := _middle(_node(opener))
	if finger:
		_touch(at, true)
		await get_tree().process_frame
		_touch(at, false)
	else:
		_click(at, true)
		await get_tree().process_frame
		_click(at, false)
	await _wait(0.6)
	var panel: Node = get_tree().get_first_node_in_group(FriendsPanel.BACK_GROUP)
	var boxes := _open_boxes()
	var right_one := panel is SettingsBox if expected == "SettingsBox" else panel is ProfilePanel
	_check("%s on %s opens the %s" % [how, opener, "settings" if expected == "SettingsBox" else "profile"], right_one, str(panel))
	var delete_button := _main.find_child("DeleteAccountButton", true, false) as Control
	_check("%s on %s opens no question with it" % [how, opener], boxes.is_empty(), "%s; finger at %s; Delete account button at %s" % [", ".join(boxes), at, delete_button.get_global_rect() if delete_button != null else "-"])
	Ui.close_dialogs()
	if panel != null:
		panel.call("close")
	await _wait(0.4)


func _open_boxes() -> PackedStringArray:
	var open := PackedStringArray()
	for box: String in ["MessageBox", "QuestionBox", "PasswordBox"]:
		var window := Ui.get_node_or_null(box) as Window
		if window != null and window.visible:
			open.append("%s (%s)" % [box, window.title])
	return open


# ---------- input ----------

func _to_window(at: Vector2) -> Vector2:
	return get_viewport().get_final_transform() * at


func _touch(at: Vector2, down: bool) -> void:
	var event := InputEventScreenTouch.new()
	event.index = 0
	event.pressed = down
	event.position = _to_window(at)
	Input.parse_input_event(event)
	Input.flush_buffered_events()


func _click(at: Vector2, down: bool) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = down
	event.button_mask = MOUSE_BUTTON_MASK_LEFT if down else 0
	event.position = _to_window(at)
	event.global_position = event.position
	Input.parse_input_event(event)
	Input.flush_buffered_events()


func _middle(control: Control) -> Vector2:
	return control.get_global_transform_with_canvas() * (control.size / 2.0)


# ---------- helpers ----------

func _node(node_name: String) -> Variant:
	return _main.find_child(node_name, true, false)


func _has(node_name: String) -> bool:
	return _node(node_name) != null


func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout


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
