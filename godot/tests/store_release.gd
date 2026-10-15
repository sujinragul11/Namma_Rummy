extends Control
## Checks what the app stores insist on: an account can be deleted from inside the app, the
## privacy policy and terms can be reached, and a store build shows no developer options.
##
## Run against a TEST server (it registers a throwaway account), once as a store build and
## once as a developer build:
##   godot --headless --path . res://tests/store_release.tscn -- --profile=storetest --server=http://127.0.0.1:3101 --store-build
##   godot --headless --path . res://tests/store_release.tscn -- --profile=storetest --server=http://127.0.0.1:3101

const PASSWORD := "secret12"

var _main: Control
var _passed := 0
var _failed := 0


func _ready() -> void:
	Game.logout()  # start from the login form even if this profile has a saved login
	_main = (load("res://scenes/main.tscn") as PackedScene).instantiate() as Control
	add_child(_main)
	_run()


func _run() -> void:
	var username := "sr_%d%04d" % [int(Time.get_unix_time_from_system()) % 1000000, randi() % 10000]
	var message_box: AcceptDialog = Ui.get_node("MessageBox")
	var password_box: ConfirmationDialog = Ui.get_node("PasswordBox")
	var password_edit: LineEdit = password_box.find_child("PasswordBoxEdit", true, false)

	await _wait(0.3)
	print("store release test, %s build" % ("store" if Config.store_build else "developer"))

	# ---------- the login form ----------
	_check("starts on the login form", _shown("AuthPanel") and not _shown("MenuPanel"))
	_check("the Server field is only for developers", _shown("ServerRow") == (not Config.store_build))
	_check("the privacy policy can be opened before signing up", _shown("PrivacyButton") and _shown("TermsButton"))
	_check("nothing to delete while logged out", not _shown("DeleteAccountButton"))

	# ---------- an account ----------
	Game.register(username, username + "@test.local", "9%09d" % (randi() % 1000000000), PASSWORD)
	_check("registered and connected", await _until(func() -> bool: return Game.is_logged_in() and Game.is_online()))
	await _wait(0.3)
	_check("the menu has the player's picture (the way to the profile) and Settings", _shown("MenuPanel") and _shown("AvatarPill") and _shown("AccountButton") and _node("ProfileButton") == null)
	_press("AccountButton")
	await _wait(0.3)
	_check("Settings has Log out", _shown("LogoutButton"))
	_check("the privacy policy can be opened when logged in, from Settings", _shown("SettingsPrivacyButton") and _shown("SettingsTermsButton"))
	_press("SettingsCloseButton")
	await _wait(0.2)
	_lift_on("AvatarPill")
	_check("the profile opens", await _until(func() -> bool: return _node("StatsRow") != null))
	_check("the profile offers Delete account", _shown("DeleteAccountButton"))

	# ---------- a wrong password deletes nothing ----------
	_press("DeleteAccountButton")
	_check("deleting asks for the password", await _until(func() -> bool: return password_box.visible))
	_check("the question says it is permanent", _password_text(password_box).contains("permanently"), _password_text(password_box))
	password_edit.text = "not-my-password"
	password_box.get_ok_button().pressed.emit()
	_check("a wrong password is refused with a message", await _until(func() -> bool: return message_box.visible) and message_box.dialog_text.contains("not correct"), message_box.dialog_text)
	message_box.hide()
	_check("the account is still logged in", Game.is_logged_in() and _shown("MenuPanel"))

	# ---------- cancelling deletes nothing ----------
	_press("DeleteAccountButton")
	await _until(func() -> bool: return password_box.visible)
	_check("the password field starts empty", password_edit.text.is_empty(), password_edit.text)
	password_edit.text = PASSWORD
	password_box.get_cancel_button().pressed.emit()
	await _wait(0.8)
	_check("cancel keeps the account", Game.is_logged_in() and _shown("MenuPanel"))

	# ---------- the right password deletes the account ----------
	_press("DeleteAccountButton")
	await _until(func() -> bool: return password_box.visible)
	password_edit.text = PASSWORD
	password_box.get_ok_button().pressed.emit()
	_check("the right password deletes and logs out", await _until(func() -> bool: return not Game.is_logged_in()))
	await _wait(0.3)
	_check("back on the login form", _shown("AuthPanel") and not _shown("MenuPanel"))
	_check("no login is kept on the device", Config.load_login().is_empty())

	var again: Dictionary = await Game.login(username, PASSWORD)
	_check("the deleted account cannot log in", not again.ok and not Game.is_logged_in(), str(again.get("error", "")))
	Ui.close_dialogs()

	print("\nstore release test: %d passed, %d failed" % [_passed, _failed])
	get_tree().quit(1 if _failed > 0 else 0)


func _node(node_name: String) -> Node:
	return _main.find_child(node_name, true, false)


func _shown(node_name: String) -> bool:
	var control := _node(node_name) as Control
	return control != null and control.is_visible_in_tree()


func _password_text(password_box: ConfirmationDialog) -> String:
	for label: Label in password_box.find_children("*", "Label", true, false):
		if not label.text.is_empty() and label.text != password_box.title:
			return label.text
	return ""


func _press(button_name: String) -> void:
	var button := _node(button_name) as BaseButton
	if button == null or button.disabled or not button.is_visible_in_tree():
		_check("%s can be pressed" % button_name, false)
		return
	button.pressed.emit()


# The release of a tap in the middle of a control that is not a button (the player's picture).
func _lift_on(node_name: String) -> void:
	var control := _node(node_name) as Control
	if control == null or not control.is_visible_in_tree():
		_check("%s can be tapped" % node_name, false)
		return
	var lift := InputEventMouseButton.new()
	lift.button_index = MOUSE_BUTTON_LEFT
	lift.pressed = false
	lift.position = control.size / 2.0
	control.gui_input.emit(lift)


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
