extends Control
## Signing up with a mobile number and the code the server sends to it by SMS, and setting a
## new password with such a code, driven through the real login form with a finger. A second,
## screenless player checks the server's side: a number that is taken, and another phone's
## login ending when the password is reset.
##
## Needs a TEST server that asks for codes, with a fixed code and a short wait between codes:
##   node tests/test_server.js --fresh --port=3131 --db=My_Rummy_phone_test --sms-code=246810 --sms-resend=3
## Then, from godot/ (--headless is fine; with a window it also saves a picture of each step):
##   godot --headless --path . res://tests/phone_tour.tscn -- --profile=phonetour --server=http://127.0.0.1:3131 --mute --shots=<folder>
## (tests/client_e2e and tests/ui_tour cover a server that asks for no codes.)

const CODE := "246810"
const RESEND_SECONDS := 3
const PASSWORD := "secret12"
const NEW_PASSWORD := "newpass9"

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
	Game.logout()  # start from the login form even if this profile has a saved login
	_main = (load("res://scenes/main.tscn") as PackedScene).instantiate() as Control
	add_child(_main)
	_run()


func _run() -> void:
	var tag := "%d%04d" % [int(Time.get_unix_time_from_system()) % 100000, randi() % 10000]
	var username := "ph_" + tag
	var first_number := "9" + tag.substr(0, 9).rpad(9, "3")
	var number := "8" + tag.substr(0, 9).rpad(9, "7")
	var shown := "+91 %s %s" % [number.substr(0, 5), number.substr(5)]
	var message_box: AcceptDialog = Ui.get_node("MessageBox")
	var b := GameClient.new()
	b.remember_login = false
	add_child(b)

	await _wait(0.7)
	await _until(func() -> bool: return not _main.loading(), 15.0)  # the logo stays until the server answers

	# ---------- the sign-up form ----------
	await _press("SwitchButton")
	_check("the sign-up form has no email field", not _has("EmailEdit"))
	_check("it asks for a username, the number with its country code, and a password", _shown("UsernameEdit") and _shown("CountryCodeEdit") and _shown("PhoneEdit") and _shown("PasswordEdit") and _node("CountryCodeEdit").text == "+91")
	_check("the password box says how long a password must be", _node("PasswordEdit").placeholder_text.contains("at least 6"), _node("PasswordEdit").placeholder_text)
	_check("Forgot password belongs to the login form only", not _shown("ForgotButton"))
	_node("UsernameEdit").text = username
	_node("PhoneEdit").text = "%s %s" % [first_number.substr(0, 5), first_number.substr(5)]
	_node("PasswordEdit").text = "abc"
	await _press("SubmitButton")
	_check("a short password is refused before anything is sent", await _until(func() -> bool: return message_box.visible, 2.0) and message_box.dialog_text.contains("at least 6"), message_box.dialog_text)
	await _press_in_box(message_box, "the message's OK")
	_node("PasswordEdit").text = PASSWORD
	await _shot("sign-up-form")

	# ---------- the code ----------
	await _press("SubmitButton")
	_check("Sign up asks for the code from the SMS", await _until(func() -> bool: return _node("AuthTitle").text == "Enter the code" and _shown("OtpEdit")), _node("AuthTitle").text)
	_check("it says which number the code went to", _node("AuthInfoLabel").text.contains("+91 %s %s" % [first_number.substr(0, 5), first_number.substr(5)]), _node("AuthInfoLabel").text)
	_check("the number and password boxes have made way for the code", not _shown("PhoneRow") and not _shown("PasswordEdit") and not _shown("UsernameEdit"))
	_check("no account yet", not Game.is_logged_in())
	await _wait(0.1)
	_check("another code can be asked for only after a countdown", _node("ResendButton").disabled and _node("ResendButton").text.begins_with("Send the code again in "), _node("ResendButton").text)
	_check("the button under the form offers to change the number", _node("SwitchButton").text == "Change the number", _node("SwitchButton").text)
	await _shot("code-step")

	_type("OtpEdit", "12a3 45")
	_check("the code box keeps digits only", _node("OtpEdit").text == "12345", _node("OtpEdit").text)
	_type("OtpEdit", "111111")  # the sixth digit sends it
	_check("a wrong code is refused with a message", await _until(func() -> bool: return message_box.visible) and message_box.dialog_text.contains("not right") and message_box.title == "Code not accepted", message_box.dialog_text)
	_check("the box is emptied to type the code again", _node("OtpEdit").text.is_empty() and not Game.is_logged_in())
	await _press_in_box(message_box, "the message's OK")

	_check("once the countdown is over, another code can be asked for", await _until(func() -> bool: return not _node("ResendButton").disabled, RESEND_SECONDS + 2.0) and _node("ResendButton").text == "Send the code again", _node("ResendButton").text)
	await _press("ResendButton")
	_check("asking again says a new code is coming", await _until(func() -> bool: return _notices().any(func(text: String) -> bool: return text.begins_with("A new code is on its way"))), str(_notices()))
	_check("and the countdown starts again", await _until(func() -> bool: return _node("ResendButton").disabled))

	# A typing mistake in the number: back to the form, which kept everything typed in it
	await _press("SwitchButton")
	_check("Change the number goes back to the filled-in form", _shown("PhoneRow") and _node("UsernameEdit").text == username and _node("PasswordEdit").text == PASSWORD and _node("AuthTitle").text == "Register")
	_node("PhoneEdit").text = "0" + number  # the 0 dialled inside India is not part of the number
	await _press("SubmitButton")
	_check("the code goes to the corrected number", await _until(func() -> bool: return _node("AuthInfoLabel").text.contains(shown) and _shown("OtpEdit")), _node("AuthInfoLabel").text)
	_type("OtpEdit", CODE)
	_check("the right code makes the account and logs in", await _until(func() -> bool: return Game.is_logged_in() and Game.is_online(), 8.0))
	_check("the account has the corrected number and no email", Game.user.get("phone") == number and Game.user.get("email") == null, str(Game.user))
	await _until(func() -> bool: return not _main.loading(), 15.0)
	_check("the menu greets the new player", await _until(func() -> bool: return _shown("MenuPanel") and _node("WelcomeLabel").text == username), _node("WelcomeLabel").text)
	await _shot("signed-up")

	# The server's side: the number is taken, typed however
	var r: Dictionary = await b.start_registration("other_" + tag, "+91 " + number, PASSWORD)
	_check("a number with an account cannot sign up again", not r.ok and str(r.error).contains("already exists"), str(r.error))
	r = await b.login(shown, PASSWORD)
	_check("a second phone logs in with the number", r.ok and await _until(func() -> bool: return b.is_online()), str(r.error))

	# ---------- a forgotten password ----------
	Game.logout()
	_check("logging out shows the login form", await _until(func() -> bool: return _shown("AuthPanel") and _node("AuthTitle").text == "Login" and _shown("ForgotButton")))
	_node("IdentifierEdit").text = number
	_node("PasswordEdit").text = "not-my-password"
	await _press("SubmitButton")
	_check("a wrong password points to Forgot password", await _until(func() -> bool: return message_box.visible) and message_box.dialog_text.contains("Forgot password?"), message_box.dialog_text)
	await _press_in_box(message_box, "the message's OK")

	await _press("ForgotButton")
	_check("Forgot password asks for the number only", _node("AuthTitle").text == "Forgot password" and _shown("PhoneRow") and not _shown("PasswordEdit") and not _shown("UsernameEdit") and _node("SubmitButton").text == "Send code")
	_check("the number typed to log in is filled in", _node("PhoneEdit").text == number, _node("PhoneEdit").text)
	_node("PhoneEdit").text = first_number
	await _press("SubmitButton")
	_check("a number without an account is told so", await _until(func() -> bool: return message_box.visible) and message_box.dialog_text.contains("No account has this mobile number"), message_box.dialog_text)
	await _press_in_box(message_box, "the message's OK")
	_node("PhoneEdit").text = number
	await _shot("forgot-password")
	await _press("SubmitButton")
	_check("a code is sent to the account's number", await _until(func() -> bool: return _shown("OtpEdit") and _node("AuthInfoLabel").text.contains(shown)), _node("AuthInfoLabel").text)
	_check("the code step asks for a new password too", _shown("PasswordEdit") and _node("PasswordEdit").text.is_empty() and _node("PasswordEdit").placeholder_text.begins_with("New password") and _node("SubmitButton").text == "Set new password", _node("PasswordEdit").placeholder_text)
	_type("OtpEdit", CODE)
	await _wait(0.3)
	_check("with a new password to type, the sixth digit does not send it", not message_box.visible and not Game.is_logged_in())
	_node("PasswordEdit").text = "abc"
	await _press("SubmitButton")
	_check("a short new password is refused", await _until(func() -> bool: return message_box.visible, 2.0) and message_box.dialog_text.contains("at least 6"), message_box.dialog_text)
	await _press_in_box(message_box, "the message's OK")
	_node("PasswordEdit").text = NEW_PASSWORD
	await _shot("new-password")
	await _press("SubmitButton")
	_check("the new password is set and the player is logged in", await _until(func() -> bool: return Game.is_logged_in() and Game.is_online(), 8.0))
	_check("the player is told", await _until(func() -> bool: return _notices().has("Your password has been changed")), str(_notices()))
	_check("the other phone's login has ended", await _until(func() -> bool: return not b.is_logged_in(), 10.0))
	r = await b.login(number, PASSWORD)
	_check("the old password no longer works", not r.ok and r.error == "Invalid credentials", str(r.error))
	r = await b.login(number, NEW_PASSWORD)
	_check("the new one does", r.ok, str(r.error))
	await _until(func() -> bool: return not _main.loading(), 15.0)
	await _shot("password-changed")

	b.logout()
	Game.logout()
	print("\nphone tour: %d passed, %d failed, %d pictures in %s" % [_passed, _failed, _step, _shots])
	get_tree().quit(1 if _failed > 0 else 0)


# The words of the popups on screen now.
func _notices() -> Array:
	return Ui.get_node("Notices").get_children().map(func(panel: Node) -> String: return (panel.get_child(0) as Label).text)


func _type(field_name: String, text: String) -> void:
	var field := _node(field_name) as LineEdit
	field.text = text
	field.text_changed.emit(text)


func _node(node_name: String) -> Variant:
	return _main.find_child(node_name, true, false)


func _has(node_name: String) -> bool:
	return _node(node_name) != null


func _shown(node_name: String) -> bool:
	var control := _node(node_name) as Control
	return control != null and control.is_visible_in_tree()


# ---------- a finger (as in tests/ui_tour) ----------

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


func _under_finger() -> String:
	var hit := get_viewport().gui_get_hovered_control()
	return "the finger was on nothing" if hit == null else "the finger was on %s" % hit.get_path()


func _middle(control: Control) -> Vector2:
	return control.get_global_transform_with_canvas() * (control.size / 2.0)


func _bring_into_view(control: Control) -> void:
	var parent := control.get_parent()
	while parent != null:
		if parent is ScrollContainer:
			(parent as ScrollContainer).ensure_control_visible(control)
			await get_tree().process_frame
			await get_tree().process_frame
			return
		parent = parent.get_parent()


## Taps a button of one of the screens. A button a finger cannot reach fails the tour.
func _press(button_name: String) -> void:
	var button := _node(button_name) as BaseButton
	if button == null or button.disabled or not button.is_visible_in_tree():
		_check("%s can be pressed" % button_name, false)
		return
	await _press_button(button, button_name)


func _press_button(button: BaseButton, what: String, origin: Vector2 = Vector2.ZERO) -> void:
	await _bring_into_view(button)
	var answered := [false]
	var on_pressed := func() -> void: answered[0] = true
	button.pressed.connect(on_pressed)
	var at := origin + _middle(button)
	_tap(at)
	if is_instance_valid(button) and button.pressed.is_connected(on_pressed):
		button.pressed.disconnect(on_pressed)
	_check("%s answers a finger" % what, answered[0], "touched %s; %s" % [at, _under_finger()])


func _press_in_box(box: AcceptDialog, what: String) -> void:
	if not box.visible:
		_check("%s is on screen" % what, false)
		return
	await _wait(0.2)  # the box takes a frame to find its place
	await _press_button(box.get_ok_button(), what, Vector2(box.position))
	await _until(func() -> bool: return not box.visible, 2.0)


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
