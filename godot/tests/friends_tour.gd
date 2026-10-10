extends Control
## Drives the friends list through the real screens, with two screenless players as the
## friends, and saves a picture of every step: adding a friend, a request arriving, who is
## online, inviting from the lobby, being invited, "Play again" and "Add friend" after a
## game, and the profile.
##
## Buttons are pressed with a finger (touch events), as in tests/ui_tour.
##
## Against a TEST server (it registers throwaway accounts). With a window and --shots it saves
## the pictures; with --headless and without --shots it only checks:
##   godot --path . res://tests/friends_tour.tscn -- --profile=friendstour --server=http://127.0.0.1:3101 --shots=<folder> --mute
## Add --resolution 1600x720 before the scene to see it at a tall phone's shape.

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

	Game.logout()  # start from the login form even if this profile has a saved login
	_main = (load("res://scenes/main.tscn") as PackedScene).instantiate() as Control
	add_child(_main)
	_run()


func _run() -> void:
	var tag := "%d%03d" % [int(Time.get_unix_time_from_system()) % 100000, randi() % 1000]
	var name_a := "Anu" + tag
	var name_b := "Bala" + tag
	var name_c := "Chitra" + tag
	var message_box: AcceptDialog = Ui.get_node("MessageBox")
	var question_box: ConfirmationDialog = Ui.get_node("QuestionBox")

	var b := await _player(name_b)
	var c := await _player(name_c)
	var invites_to_b: Array = []
	b.invite_received.connect(func(invite: Dictionary) -> void: invites_to_b.append(invite))

	Game.register(name_a, name_a + "@test.local", _phone(), PASSWORD)
	_check("registered and connected", await _until(func() -> bool: return Game.is_logged_in() and Game.is_online()))
	await _wait(0.6)
	_check("the menu has a Friends button", _shown("FriendsButton") and _node("FriendsButton").text == "Friends", _text("FriendsButton"))
	_check("the bottom bar is on screen", _on_screen("PrivacyButton") and _on_screen("TermsButton") and _on_screen("LogoutButton"))
	_check("the bars hold Profile, Logout and How to play", _on_screen("ProfileButton") and _on_screen("LogoutButton") and _on_screen("HelpButton"))
	_check("the four tiles are on screen", _on_screen("PointsTile") and _on_screen("PoolTile") and _on_screen("CloseJokerTile") and _on_screen("FriendsTile"))

	# ---------- the boxes the tiles open ----------
	await _press("PoolTile")
	await _wait(0.4)
	_check("a game tile opens the table setup for that game", _shown("CreateButton") and _text("SetupTitle") == "Pool Rummy" and (_node("TypeOption") as OptionButton).selected == 1, _text("SetupTitle"))
	await _shot("table-setup")
	await _press("SetupCloseButton")
	await _wait(0.2)
	_check("Close closes the setup", not _shown("CreateButton"))
	await _press("FriendsTile")
	await _wait(0.4)
	_check("the friends tile opens the room-code form", _shown("CodeEdit") and _shown("JoinButton") and _shown("InviteFriendsButton"))
	await _shot("join")
	get_tree().root.propagate_notification(NOTIFICATION_WM_GO_BACK_REQUEST)
	await _wait(0.2)
	_check("the back button closes it", not _shown("CodeEdit") and not question_box.visible)
	await _press("HelpButton")
	await _wait(0.4)
	_check("the ? opens the rules", _shown("RulesText") and _text("RulesText").contains("pure"))
	await _shot("rules")
	await _press("RulesCloseButton")
	await _wait(0.2)
	_check("and Close closes them", not _shown("RulesText"))
	await _shot("menu")

	# ---------- an empty list ----------
	await _press("FriendsButton")
	_check("the friends list opens", await _until(func() -> bool: return _has("Rows")))
	await _wait(0.5)
	_check("an empty list says how to add a friend", _rows_text().contains("No friends yet"), _rows_text())
	await _shot("friends-empty")

	# ---------- adding ----------
	await _press("AddButton")
	_check("an empty name is answered with a hint", await _until(func() -> bool: return message_box.visible) and message_box.dialog_text.contains("username"), message_box.dialog_text)
	await _press_in_box(message_box, "the hint's OK")
	_node("NameEdit").text = "nobody_" + tag
	await _press("AddButton")
	_check("an unknown name is refused with a message", await _until(func() -> bool: return message_box.visible) and message_box.dialog_text.contains("No player is called"), message_box.dialog_text)
	await _press_in_box(message_box, "the refusal's OK")
	_check("the name stays in the field to be corrected", _node("NameEdit").text == "nobody_" + tag)

	_node("NameEdit").text = name_b.to_upper()
	await _press("AddButton")
	_check("the request is listed as waiting", await _until(func() -> bool: return _has_row(name_b)) and _rows_text().contains("Waiting for an answer"), _rows_text())
	_check("the field is cleared", _node("NameEdit").text.is_empty(), _node("NameEdit").text)
	_check("the friend sees the request", await _until(func() -> bool: return b.friend_requests.size() == 1))
	await _shot("friends-asked")

	# ---------- the friend accepts, and is online ----------
	b.answer_friend(Game.player_id, "accept")
	_check("the friend appears as online", await _until(func() -> bool: return _row_text(name_b).contains("Online")), _row_text(name_b))
	_check("the heading counts who is online", _rows_text().contains("1 online"), _rows_text())

	# ---------- a request arrives ----------
	c.add_friend(name_a)
	_check("a request shows up while the list is open", await _until(func() -> bool: return _rows_text().contains("Friend requests") and _has_row(name_c)), _rows_text())
	await _wait(0.3)
	await _shot("friends-request")
	await _press_in_row(name_c, "Accept")
	_check("accepting makes a second friend", await _until(func() -> bool: return Game.friends.size() == 2 and not _rows_text().contains("Friend requests")), _rows_text())

	# ---------- online and offline ----------
	c.logout()
	_check("a friend who leaves is shown offline", await _until(func() -> bool: return _row_text(name_c).contains("Offline")), _row_text(name_c))
	_check("friends who can play are listed first", _row_index(name_b) < _row_index(name_c))
	await _wait(0.3)
	await _shot("friends-online-offline")

	# ---------- closing ----------
	await _press("CloseButton")
	await _wait(0.2)
	_check("Close closes the list", not _has("Rows"))
	_check("the button tells how many are online", _node("FriendsButton").text == "Friends  ·  1 online", _text("FriendsButton"))
	await _press("FriendsButton")
	await _until(func() -> bool: return _has("Rows"))
	get_tree().root.propagate_notification(NOTIFICATION_WM_GO_BACK_REQUEST)
	await _wait(0.2)
	_check("the back button closes the list, not the game", not _has("Rows") and not question_box.visible)
	await _press("FriendsButton")
	await _until(func() -> bool: return _has("Rows"))
	await _wait(0.5)
	_tap(Vector2(40, 360))
	await _wait(0.2)
	_check("a tap beside the list closes it", not _has("Rows"))

	# ---------- inviting from the lobby ----------
	await _press("PointsTile")
	await _wait(0.4)
	await _press("CreateButton")
	_check("the lobby opens", await _until(func() -> bool: return _has("CodeLabel") and _node("CodeLabel").text.length() == 6))
	var room: String = _node("CodeLabel").text
	await _wait(0.6)
	_check("the lobby offers to invite friends", _node("InviteButton").text == "Invite friends  ·  1 online" and _shown("WhatsAppButton"), _text("InviteButton"))
	await _shot("lobby")
	await _press("InviteButton")
	_check("the list opens over the lobby", await _until(func() -> bool: return _has("Rows")))
	await _wait(0.5)
	_check("a friend who is online can be invited", not _row_button(name_b, "Invite").disabled)
	_check("a friend who is offline cannot", _row_button(name_c, "Invite").disabled)
	await _shot("lobby-invite")
	await _press_in_row(name_b, "Invite")
	_check("the friend receives the invitation", await _until(func() -> bool: return invites_to_b.size() == 1) and invites_to_b[0].get("roomCode") == room and invites_to_b[0].get("username") == name_a, str(invites_to_b))
	await _wait(0.3)
	await _press_in_row(name_b, "Invite")
	_check("inviting twice in a row is refused kindly", await _until(func() -> bool: return message_box.visible) and message_box.dialog_text.contains("just invited"), message_box.dialog_text)
	await _press_in_box(message_box, "the refusal's OK")

	b.join_by_code(room)
	_check("the table opens when the friend joins", await _until(func() -> bool: return _has("HandArea") and Game.hand().size() == 13))
	_check("the list is gone with the lobby", not _has("Rows"))
	await _wait(1.5)
	await b.leave()
	await _wait(0.5)
	Game.leave()
	_check("back on the menu", await _until(func() -> bool: return _has("MenuPanel") and _shown("MenuPanel")))

	# ---------- being invited ----------
	var created: Dictionary = await b.create_game("pool", 2)
	_check("the friend's table is seen", await _until(func() -> bool: return _status_of(name_b) == "lobby"), _status_of(name_b))
	await _press("FriendsButton")
	await _until(func() -> bool: return _has("Rows"))
	await _wait(0.5)
	_check("the list says the friend waits at a table", _row_text(name_b).contains("Waiting at a table"), _row_text(name_b))
	await _press("CloseButton")
	await _wait(0.2)

	b.invite_friend(Game.player_id)
	_check("an invitation asks before joining", await _until(func() -> bool: return question_box.visible))
	_check("it names the friend and the game", question_box.dialog_text.contains(name_b) and question_box.dialog_text.contains("Pool 101"), question_box.dialog_text)
	await _wait(0.3)
	await _shot("invitation")
	await _press_in_box(question_box, "Join")
	_check("Join seats the player at the friend's table", await _until(func() -> bool: return _has("HandArea") and Game.hand().size() == 13) and Game.state.get("roomCode") == created.get("roomCode"))
	_check("the friend is now shown as playing", await _until(func() -> bool: return _status_of(name_b) == "playing"), _status_of(name_b))
	await _wait(1.5)
	await b.leave()
	await _wait(0.5)
	Game.leave()
	await _until(func() -> bool: return _has("MenuPanel") and _shown("MenuPanel"))

	# ---------- removing ----------
	await _press("FriendsButton")
	await _until(func() -> bool: return _has("Rows"))
	await _wait(0.5)
	_check("a player met at a table is not suggested when already a friend", not _rows_text().contains("Played with recently"), _rows_text())
	await _press_in_row(name_c, "Remove")
	_check("removing asks first", await _until(func() -> bool: return question_box.visible) and question_box.dialog_text.contains(name_c), question_box.dialog_text)
	await _press_in_box(question_box, "Remove")
	_check("the friend is removed", await _until(func() -> bool: return Game.friends.size() == 1 and not _has_row(name_c)), _rows_text())
	await _press("CloseButton")
	await _wait(0.2)

	# ---------- after a game with a player who is not a friend ----------
	await c.login(name_c, PASSWORD)
	await _until(func() -> bool: return c.is_online())
	var invites_to_c: Array = []
	c.invite_received.connect(func(invite: Dictionary) -> void: invites_to_c.append(invite))
	await _press("PointsTile")
	await _wait(0.4)
	await _press("CreateButton")
	_check("a second lobby opens", await _until(func() -> bool: return _has("CodeLabel") and _node("CodeLabel").text.length() == 6))
	var first_table: String = _node("CodeLabel").text
	var first_rules := [Game.game_name(), int(Game.state.get("maxPlayers", 0)), Game.stake()]
	c.join_by_code(first_table)
	_check("the table opens", await _until(func() -> bool: return _has("HandArea") and Game.hand().size() == 13))
	await _wait(1.5)
	await c.leave()
	_check("the result offers to play again", await _until(func() -> bool: return _shown("PlayAgainButton") and _shown("BackButton")))
	await _wait(1.0)  # the result drops in
	var add_button := _node("AddFriendButton") as Button
	_check("the other player can be added as a friend from the result", add_button != null and add_button.is_visible_in_tree() and add_button.text == "Add friend")
	_check("the result still fits its panel", _on_screen("PlayAgainButton") and _on_screen("BackButton") and _on_screen("AddFriendButton"))
	await _shot("result-add-friend")
	await _press_button(add_button, "Add friend on the result")
	_check("that sends a friend request", await _until(func() -> bool: return c.friend_requests.size() == 1) and add_button.disabled and add_button.text == "Asked", add_button.text)
	await _press("PlayAgainButton")
	_check("Play again opens a new table", await _until(func() -> bool: return _has("CodeLabel") and _node("CodeLabel").text.length() == 6 and _node("CodeLabel").text != first_table))
	var second_table: String = _node("CodeLabel").text
	var second_rules := [Game.game_name(), int(Game.state.get("maxPlayers", 0)), Game.stake()]
	_check("with the same game, seats and entry", second_rules == first_rules, "%s, was %s" % [second_rules, first_rules])
	_check("the other player is called to it, friend or not", await _until(func() -> bool: return invites_to_c.size() == 1) and invites_to_c[0].get("again") == true and invites_to_c[0].get("roomCode") == second_table, str(invites_to_c))
	c.join_by_code(second_table)
	_check("and can sit down again", await _until(func() -> bool: return _has("HandArea") and Game.hand().size() == 13))
	await _wait(1.5)
	await c.leave()
	await _until(func() -> bool: return _shown("BackButton"))
	await _wait(0.6)
	_check("no Add friend for a player already asked", _node("AddFriendButton") == null)
	await _press("BackButton")
	_check("Back to home returns to the menu", await _until(func() -> bool: return _has("MenuPanel") and _shown("MenuPanel")))

	# ---------- the profile: four games played by now, all won because the others left ----------
	await _wait(0.8)  # the last result is written to the database
	await _press("ProfileButton")
	_check("the profile opens", await _until(func() -> bool: return _has("StatsRow")))
	_check("it counts the games played and won", await _until(func() -> bool: return _text("PlayedValue") == "4") and _text("WonValue") == "4" and _text("RateValue") == "100%", "%s played, %s won, %s" % [_text("PlayedValue"), _text("WonValue"), _text("RateValue")])
	_check("it shows the coins", _text("CoinsValue") == Ui.coins_text(Game.coins), _text("CoinsValue"))
	_check("the fields hold the name and the email", _node("ProfileNameEdit").text == name_a and _node("ProfileEmailEdit").text == (name_a + "@test.local").to_lower(), _node("ProfileEmailEdit").text)
	_check("there is nothing to save yet", _node("SaveProfileButton").disabled)
	_check("Delete account lives in the profile", _shown("DeleteAccountButton"))
	_check("the whole profile fits the screen", _on_screen("ProfileNameEdit") and _on_screen("ProfileEmailEdit") and _on_screen("SaveProfileButton") and _on_screen("StatsRow") and _on_screen("CoinsValue"), str(get_viewport().get_visible_rect().size))
	# A phone's keyboard covers about the lower half; the fields must stay above it
	_check("the fields sit in the upper half of the screen", (_node("ProfileEmailEdit") as Control).get_global_rect().end.y < 320.0, str((_node("ProfileEmailEdit") as Control).get_global_rect()))
	_check("the four numbers share the row evenly", absf((_node("PlayedValue") as Control).size.x - (_node("CoinsValue") as Control).size.x) < 2.0 and (_node("CoinsValue") as Control).size.x > 120.0, str((_node("CoinsValue") as Control).size))
	await _wait(0.5)
	await _shot("profile")

	_type("ProfileEmailEdit", "not an address")
	await _press("SaveProfileButton")
	_check("a bad email address is refused with a message", await _until(func() -> bool: return message_box.visible) and message_box.dialog_text.contains("valid email"), message_box.dialog_text)
	await _press_in_box(message_box, "the refusal's OK")
	_check("the account is unchanged", Game.user.get("username") == name_a)

	var new_name := "Anu" + tag + "x"
	_type("ProfileNameEdit", new_name)
	_type("ProfileEmailEdit", "new." + tag + "@test.local")
	await _press("SaveProfileButton")
	_check("the new name and email are saved", await _until(func() -> bool: return Game.user.get("username") == new_name and Game.user.get("email") == "new." + tag + "@test.local"), str(Game.user))
	_check("Save has nothing left to do", await _until(func() -> bool: return _node("SaveProfileButton").disabled))
	_check("the player is connected again under the new name", await _until(func() -> bool: return Game.is_online()))
	_check("friends see the new name", await _until(func() -> bool: return b.friends.size() == 1 and b.friends[0].get("username") == new_name), str(b.friends))
	await _press("CloseButton")
	await _wait(0.2)
	_check("the menu greets the player by the new name", _text("WelcomeLabel").contains(new_name), _text("WelcomeLabel"))
	_check("the saved login has the new name", Config.load_login().get("user", {}).get("username") == new_name)

	Game.logout()
	await _wait(0.3)
	_check("logging out forgets the friends", Game.friends.is_empty() and _shown("AuthPanel"))
	Sound.hush()
	print("\nfriends tour: %d passed, %d failed, %d pictures in %s" % [_passed, _failed, _step, _shots])
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

# Untyped on purpose: the tour reads properties of many different kinds of node.
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


# Puts text into a field the way typing does: the field tells its listeners.
func _type(field_name: String, text: String) -> void:
	var field := _node(field_name) as LineEdit
	field.text = text
	field.text_changed.emit(text)


# True when the whole control lies inside the window.
func _on_screen(node_name: String) -> bool:
	var control := _node(node_name) as Control
	if control == null or not control.is_visible_in_tree():
		return false
	return get_viewport().get_visible_rect().encloses(control.get_global_rect())


# Everything written in the list, row after row.
func _rows_text() -> String:
	var rows := _node("Rows") as Control
	if rows == null:
		return ""
	var texts: Array = []
	for label: Label in rows.find_children("*", "Label", true, false):
		texts.append(label.text)
	return " | ".join(texts)


func _row(username: String) -> Control:
	var rows := _node("Rows") as Control
	return null if rows == null else rows.get_node_or_null("Row_" + username) as Control


func _has_row(username: String) -> bool:
	var row := _row(username)
	return row != null and not row.is_queued_for_deletion()


func _row_text(username: String) -> String:
	var row := _row(username)
	if row == null:
		return ""
	var texts: Array = []
	for label: Label in row.find_children("*", "Label", true, false):
		texts.append(label.text)
	return " | ".join(texts)


func _row_index(username: String) -> int:
	var row := _row(username)
	return -1 if row == null else row.get_index()


func _row_button(username: String, text: String) -> Button:
	var row := _row(username)
	if row != null:
		for button: Button in row.find_children("*", "Button", true, false):
			if button.text == text:
				return button
	return null


func _status_of(username: String) -> String:
	for friend: Dictionary in Game.friends:
		if friend.get("username") == username:
			return str(friend.get("status", ""))
	return ""


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


## Taps a button of the screen. A button a finger cannot reach fails the tour.
func _press(button_name: String) -> void:
	await _press_button(_node(button_name) as BaseButton, button_name)


func _press_in_row(username: String, text: String) -> void:
	await _press_button(_row_button(username, text), "%s for %s" % [text, username])


## `origin` is where the button's window sits on the screen, for buttons inside a message box.
func _press_button(button: BaseButton, what: String, origin: Vector2 = Vector2.ZERO) -> void:
	if button == null or button.disabled or not button.is_visible_in_tree():
		_check("%s can be pressed" % what, false)
		return
	await _bring_into_view(button)
	var answered := [false]
	var on_pressed := func() -> void: answered[0] = true
	button.pressed.connect(on_pressed)
	var at := origin + _middle(button)
	_tap(at)
	if is_instance_valid(button) and button.pressed.is_connected(on_pressed):
		button.pressed.disconnect(on_pressed)
	var hit := get_viewport().gui_get_hovered_control()
	_check("%s answers a finger" % what, answered[0], "touched %s, which is on %s" % [at, "nothing" if hit == null else str(hit.get_path())])


func _press_in_box(box: AcceptDialog, what: String) -> void:
	if not box.visible:
		_check("%s is on screen" % what, false)
		return
	await _press_button(box.get_ok_button(), what, Vector2(box.position))


## Scrolls a list until the control can be seen, as a player would before touching it.
func _bring_into_view(control: Control) -> void:
	var parent := control.get_parent()
	while parent != null:
		if parent is ScrollContainer:
			(parent as ScrollContainer).ensure_control_visible(control)
			await get_tree().process_frame
			await get_tree().process_frame
			return
		parent = parent.get_parent()


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
