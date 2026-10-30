extends Control
## Scrolls a long friends list the ways a player does, with no server: the mouse wheel, the mouse
## held down and dragged, finger swipes and flicks (also ones that start on a Remove button),
## taps, the scrollbar, and the list being rebuilt while scrolled.
##
## From godot/ (headless only checks; with a window it also saves pictures):
##   godot --headless --path . res://tests/friends_scroll.tscn -- --profile=friendsscroll --mute
##   godot --path . res://tests/friends_scroll.tscn -- --profile=friendsscroll --mute --shots=<folder>

const NAMES := ["Ragul kumar", "Naan", "sujineey", "Nathiya", "Ramesh", "jose", "abi", "Prabhu",
	"dhamu", "Boss", "Abishek", "karthi", "Rasla", "Aathiran", "eshant", "comali"]

var _shots := ""
var _step := 0
var _passed := 0
var _failed := 0
var _panel: Control
var _scroll: ScrollContainer
var _rows: VBoxContainer


func _ready() -> void:
	# The dummy display reports a square screen; use the phone's landscape layout
	if DisplayServer.get_name() == "headless":
		get_window().content_scale_size = Vector2i(1280, 720)
		get_window().content_scale_aspect = Window.CONTENT_SCALE_ASPECT_IGNORE
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--shots="):
			_shots = argument.trim_prefix("--shots=")
	if not _shots.is_empty():
		DirAccess.make_dir_recursive_absolute(_shots)
	theme = Ui.game_theme
	Game.socket.is_online = true
	Game.friends = []
	for index in NAMES.size():
		Game.friends.append({"id": str(100 + index), "username": NAMES[index], "coins": 50000 - index * 1750,
			"status": "online" if index < 2 else "offline"})
	Game.friend_requests = []
	Game.friend_asked = []
	Game.recent_players = []
	_panel = (load("res://scenes/friends.tscn") as PackedScene).instantiate()
	add_child(_panel)
	# A step that breaks must not leave the run hanging
	get_tree().create_timer(60.0).timeout.connect(func() -> void:
		print("friends scroll: stopped after 60 s at %d passed, %d failed" % [_passed, _failed + 1])
		get_tree().quit(1))
	_run()


func _run() -> void:
	await _wait(0.6)  # the panel pops in
	await _tap(_middle(_panel._tabs["all"]))
	await _wait(0.2)
	_scroll = _panel.find_child("Scroll", true, false)
	_rows = _panel.find_child("Rows", true, false)
	var bar := _scroll.get_v_scroll_bar()
	_check("sixteen friends make a list taller than its box", _rows.get_child_count() == NAMES.size() and _max_scroll() > 300.0, "rows=%d max=%s" % [_rows.get_child_count(), _max_scroll()])
	_check("the scrollbar shows and is wide enough to grab", bar.is_visible_in_tree() and bar.size.x >= 18.0, "visible=%s width=%s" % [bar.is_visible_in_tree(), bar.size.x])
	var first: Control = _rows.get_child(0)
	_check("the rows end before the scrollbar", first.get_global_rect().end.x <= bar.get_global_rect().position.x - 4.0, "row ends at %s, bar starts at %s" % [first.get_global_rect().end.x, bar.get_global_rect().position.x])
	await _shot("top")

	# ---------- the mouse wheel ----------
	var over_name := _middle(_name_label(1))
	await _wheel(over_name, true)
	await _wait(0.03)
	var early := _scroll.scroll_vertical
	await _wait(0.5)
	var settled := _scroll.scroll_vertical
	_check("a wheel notch glides instead of jumping", early > 0 and early < settled, "after 30 ms %d, settled at %d" % [early, settled])
	await _wheel(over_name, true)
	await _wheel(over_name, true)
	await _wheel(over_name, true)
	await _wait(0.6)
	_check("quick notches add up", _scroll.scroll_vertical >= settled * 3, "one notch %d, four notches %d" % [settled, _scroll.scroll_vertical])
	await _wait(0.3)
	var before_wheel := _scroll.scroll_vertical
	await _wheel(_middle(_visible_button("Remove")), true)
	await _wait(0.5)
	_check("the wheel works over the Remove buttons too", _scroll.scroll_vertical > before_wheel, "%d -> %d" % [before_wheel, _scroll.scroll_vertical])

	# ---------- the mouse held down and dragged, as on a PC ----------
	await _to_top()
	var start := _middle(_name_label(1))
	await _mouse_move(start, false)
	await _mouse_button(start, true)
	var steps: Array[int] = []
	for step in 6:
		await _mouse_move(start - Vector2(0, 30 * (step + 1)), true)
		if not is_instance_valid(_scroll):
			_check("the list stays open while the mouse drags it", false)
			return
		steps.append(_scroll.scroll_vertical)
	_check("the list follows the held mouse one to one", steps[5] - steps[1] == 120 and steps[5] - steps[4] == 30, str(steps))
	await _wait(0.25)  # held still before letting go
	await _mouse_button(start - Vector2(0, 180), false)
	var let_go := _scroll.scroll_vertical
	await _wait(0.4)
	_check("a slow release leaves the list where it was let go", _scroll.scroll_vertical == let_go, "%d -> %d" % [let_go, _scroll.scroll_vertical])

	# ---------- a finger flick that starts on a Remove button ----------
	await _to_top()
	var remove := _visible_button("Remove", true)
	var pressed := [false]
	remove.pressed.connect(func() -> void: pressed[0] = true)
	var from := _middle(remove)
	await _finger(from, true)
	for step in 6:
		await _finger_move(from - Vector2(0, 40 * (step + 1)))
	await _finger(from - Vector2(0, 240), false)
	var lifted := _scroll.scroll_vertical
	_check("a swipe that starts on a Remove button scrolls the list", lifted >= 150, "scrolled %d" % lifted)
	_check("and does not press Remove", not pressed[0] and not Ui._question_box.visible)
	await _wait(0.15)
	var gliding := _scroll.scroll_vertical
	_check("a flick glides on after the finger lifts", gliding > lifted + 20, "%d at lift, %d 150 ms later" % [lifted, gliding])
	await _wait(2.5)
	var stopped := _scroll.scroll_vertical
	await _wait(0.2)
	_check("and slows to a stop", _scroll.scroll_vertical == stopped and stopped > gliding, "%d then %d" % [stopped, _scroll.scroll_vertical])
	_check("the Remove button springs back up", not is_instance_valid(remove) or remove.scale.is_equal_approx(Vector2.ONE), str(remove.scale))
	await _shot("after-flick")

	# ---------- a hard flick to the end ----------
	from = _middle(_name_label(_first_visible_row()))
	await _finger(from, true)
	for step in 6:
		await _finger_move(from - Vector2(0, 70 * (step + 1)))
	await _finger(from - Vector2(0, 420), false)
	await _wait(3.0)
	var last: Control = _rows.get_child(_rows.get_child_count() - 1)
	_check("a hard flick stops at the last friend, fully in view", _scroll.scroll_vertical == roundi(_max_scroll()) and _scroll.get_global_rect().encloses(last.get_global_rect()),
		"scroll %d of %s, last row %s in %s" % [_scroll.scroll_vertical, _max_scroll(), last.get_global_rect(), _scroll.get_global_rect()])
	await _shot("bottom")

	# ---------- a finger on a gliding list stops it, and presses nothing ----------
	from = _middle(_name_label(_first_visible_row() + 1))
	await _finger(from, true)
	for step in 5:
		await _finger_move(from + Vector2(0, 60 * (step + 1)))
	await _finger(from + Vector2(0, 300), false)
	await _wait(0.08)
	remove = _visible_button("Remove", true)
	pressed = [false]
	remove.pressed.connect(func() -> void: pressed[0] = true)
	await _finger(_middle(remove), true)
	var caught := _scroll.scroll_vertical
	await _wait(0.25)
	_check("a finger on a gliding list stops it", absi(_scroll.scroll_vertical - caught) <= 2, "%d -> %d" % [caught, _scroll.scroll_vertical])
	await _finger(_middle(remove), false)
	_check("and that touch does not press the button under it", not pressed[0] and not Ui._question_box.visible, "pressed=%s question=%s" % [pressed[0], Ui._question_box.visible])
	Ui.close_dialogs()

	# ---------- taps still press ----------
	await _wait(0.3)
	remove = _visible_button("Remove", true)
	pressed = [false]
	remove.pressed.connect(func() -> void: pressed[0] = true)
	var at := _middle(remove)
	await _finger(at, true)
	await _finger_move(at + Vector2(3, -4))
	await _finger(at + Vector2(3, -4), false)
	_check("a tap on Remove still presses it, even with a little wobble", pressed[0] and Ui._question_box.visible)
	Ui.close_dialogs()
	await _wait(0.1)
	at = _middle(_visible_button("Remove", true))
	pressed = [false]
	_visible_button("Remove", true).pressed.connect(func() -> void: pressed[0] = true)
	await _mouse_move(at, false)
	await _mouse_button(at, true)
	await _mouse_button(at, false)
	_check("a mouse click on Remove presses it", pressed[0] and Ui._question_box.visible)

	# ---------- an open question box keeps the list still ----------
	var under_box := _scroll.scroll_vertical
	from = _middle(_name_label(_first_visible_row()))
	await _finger(from, true)
	for step in 4:
		await _finger_move(from + Vector2(0, 50 * (step + 1)))
	await _finger(from + Vector2(0, 200), false)
	await _wheel(from, false)
	await _wait(0.5)
	_check("an open question box keeps the list still", _scroll.scroll_vertical == under_box and Ui._question_box.visible, "%d -> %d" % [under_box, _scroll.scroll_vertical])
	Ui.close_dialogs()

	# ---------- the scrollbar ----------
	await _to_top()
	var grab := bar.get_global_rect().position + Vector2(bar.size.x / 2.0, 30)
	await _mouse_move(grab, false)
	await _mouse_button(grab, true)
	for step in 5:
		await _mouse_move(grab + Vector2(0, 20 * (step + 1)), true)
	await _mouse_button(grab + Vector2(0, 100), false)
	var dragged := _scroll.scroll_vertical
	await _wait(0.3)
	_check("the scrollbar's thumb can be dragged, and stays put", dragged > 100 and _scroll.scroll_vertical == dragged, "%d then %d" % [dragged, _scroll.scroll_vertical])

	# ---------- the list is rebuilt while scrolled ----------
	_scroll.scroll_vertical = 260
	await _wait(0.1)
	var kept := _scroll.scroll_vertical
	Game.friends[9].status = "online"
	Game.friends_changed.emit()
	await _wait(0.2)
	_check("a friend coming online does not move the list", kept == 260 and absi(_scroll.scroll_vertical - kept) <= 2, "%d -> %d" % [kept, _scroll.scroll_vertical])
	Game.friends[9].status = "offline"
	Game.friends_changed.emit()
	await _wait(0.2)

	# ---------- another tab starts at the top ----------
	await _tap(_middle(_panel._tabs["online"]))
	await _wait(0.2)
	var short_row: Control = _rows.get_child(0)
	_check("a short list has no scrollbar and its rows use the full width", not bar.is_visible_in_tree() and is_equal_approx(short_row.size.x, _scroll.size.x), "bar=%s row=%s list=%s" % [bar.is_visible_in_tree(), short_row.size.x, _scroll.size.x])
	await _tap(_middle(_panel._tabs["all"]))
	await _wait(0.2)
	_check("a tab opens at the top of its list", _scroll.scroll_vertical == 0, str(_scroll.scroll_vertical))

	print("friends scroll: %d passed, %d failed" % [_passed, _failed])
	Game.socket.is_online = false
	Sound.hush()
	get_tree().quit(1 if _failed > 0 else 0)


# ---------- the list ----------

func _max_scroll() -> float:
	var bar := _scroll.get_v_scroll_bar()
	return maxf(0.0, bar.max_value - bar.page)


func _to_top() -> void:
	_scroll.scroll_vertical = 0
	await _wait(0.15)


func _name_label(row: int) -> Label:
	return (_rows.get_child(row).find_children("*", "Label", true, false) as Array)[0]


func _first_visible_row() -> int:
	for index in _rows.get_child_count():
		if (_rows.get_child(index) as Control).get_global_rect().position.y >= _scroll.get_global_rect().position.y:
			return index
	return 0


# A button of that text lying fully inside the list's box; with `low`, the lowest such one.
func _visible_button(text: String, low: bool = false) -> Button:
	var found: Button = null
	for button: Button in _rows.find_children("*", "Button", true, false):
		if button.text == text and _scroll.get_global_rect().encloses(button.get_global_rect()):
			found = button
			if not low:
				return found
	return found


func _middle(control: Control) -> Vector2:
	return control.get_global_transform_with_canvas() * (control.size / 2.0)


# ---------- a finger and a mouse, through the engine's input like real ones ----------

func _window(at: Vector2) -> Vector2:
	return get_viewport().get_final_transform() * at  # layout units to window pixels


var _finger_at := Vector2.ZERO


func _finger(at: Vector2, down: bool) -> void:
	var event := InputEventScreenTouch.new()
	event.index = 0
	event.pressed = down
	event.position = _window(at)
	_finger_at = at
	Input.parse_input_event(event)
	Input.flush_buffered_events()
	await _wait(0.016)


func _finger_move(at: Vector2) -> void:
	var event := InputEventScreenDrag.new()
	event.index = 0
	event.position = _window(at)
	event.relative = _window(at) - _window(_finger_at)
	_finger_at = at
	Input.parse_input_event(event)
	Input.flush_buffered_events()
	await _wait(0.016)


func _tap(at: Vector2) -> void:
	await _finger(at, true)
	await _finger(at, false)


var _mouse_at := Vector2.ZERO


func _mouse_move(at: Vector2, held: bool) -> void:
	var event := InputEventMouseMotion.new()
	event.position = _window(at)
	event.global_position = event.position
	event.relative = _window(at) - _window(_mouse_at)
	event.button_mask = MOUSE_BUTTON_MASK_LEFT if held else 0
	_mouse_at = at
	Input.parse_input_event(event)
	Input.flush_buffered_events()
	await _wait(0.016)


func _mouse_button(at: Vector2, down: bool) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = down
	event.position = _window(at)
	event.global_position = event.position
	event.button_mask = MOUSE_BUTTON_MASK_LEFT if down else 0
	_mouse_at = at
	Input.parse_input_event(event)
	Input.flush_buffered_events()
	await _wait(0.016)


func _wheel(at: Vector2, down: bool) -> void:
	await _mouse_move(at, false)
	for pressed in [true, false]:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_WHEEL_DOWN if down else MOUSE_BUTTON_WHEEL_UP
		event.pressed = pressed
		event.factor = 1.0
		event.position = _window(at)
		event.global_position = event.position
		Input.parse_input_event(event)
	Input.flush_buffered_events()


# ---------- bookkeeping ----------

func _shot(label: String) -> void:
	_step += 1
	if _shots.is_empty() or DisplayServer.get_name() == "headless":
		return
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("%s/%02d-%s.png" % [_shots, _step, label])


func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout


func _check(what: String, ok: bool, detail: String = "") -> void:
	if ok:
		_passed += 1
		print("ok    %s" % what)
	else:
		_failed += 1
		print("FAIL  %s  %s" % [what, detail])
