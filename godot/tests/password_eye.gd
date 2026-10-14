extends Control
## Every password field has an eye at its right end: a tap shows what was typed, another tap
## hides it, and the field keeps the cursor (on a phone, the keyboard) all the while. Checked on
## the login form and in the box that asks for the password before deleting an account, with a
## finger and with a mouse click.
##
## Needs no server. Use its own profile, since it logs that profile out:
##   godot --headless --path . res://tests/password_eye.tscn -- --profile=eyetest --mute
## Without --headless, and with --shots=<folder>, it also saves a picture of each state.

const DELETE_TEXT := "This permanently deletes your account, your coins, your game results and your friends list. Enter your password to confirm."

var _shots := ""
var _main: Control
var _step := 0
var _passed := 0
var _failed := 0


func _ready() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--shots="):
			_shots = argument.trim_prefix("--shots=")
	Game.logout()
	_main = (load("res://scenes/main.tscn") as PackedScene).instantiate() as Control
	add_child(_main)
	_run()


func _run() -> void:
	await _wait(0.7)

	# ---------- the login form ----------
	var field: LineEdit = _main.find_child("PasswordEdit", true, false)
	var eye: BaseButton = field.get_node_or_null("RevealButton")
	_check("the password field has an eye", eye != null)
	if eye == null:
		_finish()
		return
	_check("the password starts hidden", field.secret and not eye.button_pressed)
	var field_rect := field.get_global_rect()
	var eye_rect := eye.get_global_rect()
	_check("the eye sits at the right end of the field, full height", is_equal_approx(eye_rect.end.x, field_rect.end.x) and is_equal_approx(eye_rect.size.y, field_rect.size.y) and is_equal_approx(eye_rect.size.x, Ui.REVEAL_WIDTH), "field %s, eye %s" % [field_rect, eye_rect])
	_check("typed text stops short of the eye", is_equal_approx(field.get_theme_stylebox("normal").content_margin_right, Ui.REVEAL_WIDTH))

	_tap(field.get_global_transform_with_canvas() * Vector2(40, field.size.y / 2.0))
	field.text = "secret12"
	field.caret_column = field.text.length()
	_check("tapping the field puts the cursor in it", field.has_focus())
	await _shot("login-hidden")

	_tap(_middle(eye))
	await _wait(0.2)
	_check("a tap on the eye shows the password", not field.secret and eye.button_pressed)
	_check("the field keeps the cursor", field.has_focus())
	_check("the text is untouched", field.text == "secret12" and field.caret_column == 8, "%s / %d" % [field.text, field.caret_column])
	await _shot("login-shown")

	_tap(_middle(eye))
	await _wait(0.2)
	_check("another tap hides it again", field.secret and not eye.button_pressed)
	_check("the field still has the cursor", field.has_focus())

	_click(_middle(eye))
	await _wait(0.2)
	_check("a mouse click on the eye shows it too", not field.secret)
	_click(_middle(eye))
	await _wait(0.2)
	_check("and a second click hides it", field.secret)

	# ---------- the box that asks for the password ----------
	var box: ConfirmationDialog = Ui.get_node("PasswordBox")
	var box_field: LineEdit = box.find_child("PasswordBoxEdit", true, false)
	var box_eye: BaseButton = box_field.get_node_or_null("RevealButton")
	_check("the password box's field has an eye", box_eye != null)
	if box_eye == null:
		_finish()
		return
	Ui.ask_password("Delete account", DELETE_TEXT, "Delete", func(_password: String) -> void: pass)
	await _wait(0.4)
	var screen := get_viewport().get_visible_rect()
	var ok_button := box.get_ok_button()
	_check("the first box opened fits on the screen, Delete button included", screen.encloses(Rect2(box.position, box.size)) and screen.has_point(Vector2(box.position) + ok_button.get_global_rect().end), "box %s, screen %s" % [Rect2(box.position, box.size), screen])
	box_field.text = "secret12"
	_check("in the box the password starts hidden", box_field.secret)
	await _shot("box-hidden")
	# Inside the box, places are measured from the box's corner
	var at := Vector2(box.position) + _middle(box_eye)
	_tap(at)
	await _wait(0.2)
	_check("a tap on the box's eye shows it", not box_field.secret, "finger at %s, box at %s" % [at, box.position])
	_check("the box's field keeps the cursor", box_field.has_focus())
	await _shot("box-shown")
	Ui.close_dialogs()
	Ui.ask_password("Delete account", DELETE_TEXT, "Delete", func(_password: String) -> void: pass)
	await _wait(0.3)
	_check("asked again, the password is hidden again", box_field.secret and not box_eye.button_pressed)
	Ui.close_dialogs()

	_finish()


func _finish() -> void:
	print("\npassword eye: %d passed, %d failed" % [_passed, _failed])
	get_tree().quit(1 if _failed > 0 or _passed == 0 else 0)


# ---------- input ----------

func _to_window(at: Vector2) -> Vector2:
	return get_viewport().get_final_transform() * at


func _tap(at: Vector2) -> void:
	for down: bool in [true, false]:
		var event := InputEventScreenTouch.new()
		event.index = 0
		event.pressed = down
		event.position = _to_window(at)
		Input.parse_input_event(event)
		Input.flush_buffered_events()


func _click(at: Vector2) -> void:
	for down: bool in [true, false]:
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

func _shot(label: String) -> void:
	_step += 1
	if _shots.is_empty() or DisplayServer.get_name() == "headless":
		return
	DirAccess.make_dir_recursive_absolute(_shots)
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("%s/%02d-%s.png" % [_shots, _step, label])


func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout


func _check(what: String, ok: bool, detail: String = "") -> void:
	if ok:
		_passed += 1
	else:
		_failed += 1
		print("FAIL  %s  %s" % [what, detail])
