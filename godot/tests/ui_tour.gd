extends Control
## Drives the real screens through three games and saves a picture of every step, with a
## second, screenless player as the opponent. Use it to look at the game after a change.
##
## The tour plays with a finger: every tap and every carried card is sent as the touch events
## a phone reports, which the engine turns into presses and drags. So a button that something
## invisible lies on top of fails here, which calling its handler directly would never show.
## Only typing is skipped (the text of a field is set directly).
##
## Run WITH a window (not --headless) against a TEST server (it registers throwaway accounts):
##   godot --path . res://tests/ui_tour.tscn -- --profile=uitour --server=http://127.0.0.1:3111 --shots=<folder> --rig-flag=<file>
## Add --resolution 1600x720 before the scene to see it at a tall phone's shape.
## While the flag file exists the test server deals a fixed hand, which the first game relies on;
## the third (Close Joker) needs the "closed" deal of tests/test_server.js and is skipped on a
## test server that does not have it.

var _shots := ""
var _rig_flag := ""
var _main: Control
var _step := 0
var _passed := 0
var _failed := 0


func _ready() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--shots="):
			_shots = argument.trim_prefix("--shots=")
		elif argument.begins_with("--rig-flag="):
			_rig_flag = argument.trim_prefix("--rig-flag=")
	DirAccess.make_dir_recursive_absolute(_shots)

	Game.logout()  # start from the login form even if this profile has a saved login
	_main = (load("res://scenes/main.tscn") as PackedScene).instantiate() as Control
	add_child(_main)
	_run()


func _run() -> void:
	var tag := "%d%04d" % [int(Time.get_unix_time_from_system()) % 1000000, randi() % 10000]
	var name_a := "ua_" + tag
	var name_b := "ub_" + tag
	var message_box: AcceptDialog = Ui.get_node("MessageBox")
	var question_box: ConfirmationDialog = Ui.get_node("QuestionBox")

	# ---------- login and register ----------
	await _wait(0.7)
	_check("starts on the login form", _node("AuthPanel").visible and not _node("MenuPanel").visible)
	_check("the logo is shown", _node("Logo").texture != null and _node("Logo").size.y > 200.0, str(_node("Logo").size))
	await _shot("login")

	_node("IdentifierEdit").text = name_a
	_node("PasswordEdit").text = "secret12"
	await _press("SubmitButton")
	_check("an unknown account gets a message", await _until(func() -> bool: return message_box.visible))
	_check("the message explains and points to Register", message_box.dialog_text.contains("do not match an account") and message_box.dialog_text.contains("Register"), message_box.dialog_text)
	await _shot("login-refused")
	await _press_in_box(message_box, "the message's OK button")
	_check("OK closes the message", await _until(func() -> bool: return not message_box.visible, 2.0))

	await _press("SwitchButton")
	_node("UsernameEdit").text = name_a
	_node("EmailEdit").text = name_a + "@test.local"
	await _wait(0.1)
	await _shot("register")

	# A phone's keyboard covers the lower half: the form must stay reachable above it
	var home: Variant = _screen()
	var field: Control = _node("PasswordEdit")
	await _bring_into_view(field)
	_tap(_middle(field))
	_check("tapping a field puts the cursor in it", field.has_focus(), _under_finger())
	home.make_room_for_keyboard(int(DisplayServer.window_get_size().y * 0.52))
	await _wait(0.3)
	var visible_bottom: float = home.global_position.y + home.size.y
	_check("with the keyboard up, the field being typed in is still on screen", field.global_position.y >= 0.0 and field.global_position.y + field.size.y <= visible_bottom + 1.0, "field %s..%s, screen ends %s" % [field.global_position.y, field.global_position.y + field.size.y, visible_bottom])
	await _shot("register-keyboard-up")
	home.make_room_for_keyboard(0)
	await _wait(0.2)

	# The mobile number is not optional, and it has to be one
	await _press("SubmitButton")
	_check("signing up without a mobile number gets a message", await _until(func() -> bool: return message_box.visible, 2.0) and message_box.dialog_text == "Enter your mobile number.", message_box.dialog_text)
	await _press_in_box(message_box, "the message's OK button")
	_node("PhoneEdit").text = "12345"
	await _press("SubmitButton")
	_check("a number that is not a mobile number is refused before anything is sent", await _until(func() -> bool: return message_box.visible, 2.0) and message_box.dialog_text.begins_with("That mobile number is not valid.") and not Game.is_logged_in(), message_box.dialog_text)
	await _shot("register-refused")
	await _press_in_box(message_box, "the message's OK button")
	_node("PhoneEdit").text = "9" + tag.substr(0, 9)

	await _press("SubmitButton")
	_check("registered and connected", await _until(func() -> bool: return Game.is_logged_in() and Game.is_online()))
	await _wait(0.5)
	_check("the menu greets the player", _node("MenuPanel").visible and _node("WelcomeLabel").text == name_a, _node("WelcomeLabel").text)
	_check("the menu shows the connection", _node("StatusLabel").text == "Online", _node("StatusLabel").text)
	_check("a new player has 50,000 coins, shown beside the welcome", await _until(func() -> bool: return Game.coins == 50000) and _node("CoinsLabel")._label.text == "50,000" and _node("CoinsLabel").is_visible_in_tree(), _node("CoinsLabel")._label.text)
	_check("the entry offered first is the 500 coin one", _node("StakeOption").get_item_text(_node("StakeOption").selected) == "500 coins" and _node("StakeOption").item_count == 8, _node("StakeOption").get_item_text(_node("StakeOption").selected))
	_check("the menu still fits on the screen", _node("LogoutButton").get_global_rect().end.y <= get_viewport().get_visible_rect().size.y and _node("PrivacyButton").get_global_rect().end.y <= get_viewport().get_visible_rect().size.y, "%s / %s" % [_node("LogoutButton").get_global_rect().end.y, _node("PrivacyButton").get_global_rect().end.y])
	await _shot("menu")

	# ---------- game 1: fixed deal, group cards, declare ----------
	_set_rigged(true)
	await _open_private_table()
	_check("a Points table is played for coins a point, 10 offered first", _node("StakeCoins")._label.text == "10 per point" and _node("StakeLabel").text == "SELECT POINT VALUE", _node("StakeCoins")._label.text)
	await _press("CreateButton")
	_check("the lobby opens", await _until(func() -> bool: return _has("CodeLabel") and _node("CodeLabel").text.length() == 6))
	var room: String = _node("CodeLabel").text
	await _wait(0.5)
	_check("the lobby lists the host", _node("PlayersTitle").text == "Players (1/2)" and not _node("StartButton").visible and _node("PlayersList").get_child_count() == 1, _node("PlayersTitle").text)
	_check("sitting down holds what 80 points cost, and the lobby says what is played for", await _until(func() -> bool: return Game.coins == 49200) and _node("InfoLabel").text.contains("10 coins a point: each loser pays the winner what their points cost (at most 800)."), "%d | %s" % [Game.coins, _node("InfoLabel").text])
	_check("the lobby still fits on the screen", _node("LeaveButton").get_global_rect().end.y <= get_viewport().get_visible_rect().size.y, str(_node("LeaveButton").get_global_rect().end.y))
	await _shot("lobby")

	var b := GameClient.new()
	b.remember_login = false
	add_child(b)
	var r: Dictionary = await b.register(name_b, name_b + "@test.local", "8" + tag.substr(0, 9), "secret12")
	await _until(func() -> bool: return b.is_online())
	r = await b.join_by_code(room)
	_check("the table opens when the opponent joins", r.ok and await _until(func() -> bool: return _has("HandArea") and Game.hand().size() == 13))
	_set_rigged(false)
	await _wait(0.45)
	await _shot("table-dealing")  # mid-deal: cards on their way, still face down
	await _wait(1.4)
	var table: Variant = _screen()  # untyped: the tour looks inside the table script
	_check("13 cards are on the table", table._cards.size() == 13)
	_check("the deal has finished face up", table._cards.values().all(func(view: CardView) -> bool: return not view.face_down and view.scale.is_equal_approx(Vector2.ONE)))
	_check("the player is told to draw", _node("StatusLabel").text == "Your turn: draw from the deck or the open pile", _node("StatusLabel").text)
	_check("only Sort and Drop can be used", not _node("SortButton").disabled and _node("GroupButton").disabled and _node("DiscardButton").disabled and _node("DeclareButton").disabled and not _node("DropButton").disabled)
	_check("the room is named", _node("RoomLabel").text.begins_with(room) and _node("JokerLabel").text.contains("As wild"), _node("JokerLabel").text)
	_check("the top bar shows the value of a point", _node("RoomLabel").text.ends_with("10 coins a point") and b.coins == 49200, _node("RoomLabel").text)
	_check("the opponent has a badge", table._badges.size() == 1)
	_check("cards are big enough for a finger", table._card_width >= 112.0 and _node("DiscardButton").size.y >= 54.0, "card %s, button %s" % [table._card_width, _node("DiscardButton").size.y])
	_check("the hand fits on the screen", table._spans[-1].right <= _node("HandArea").size.x and table._spans[0].left >= 0.0, "%s of %s" % [table._spans[-1].right, _node("HandArea").size.x])
	await _shot("table-dealt")

	_tap(_middle(_node("DeckCard")))
	_check("tapping the deck draws a card", await _until(func() -> bool: return table._cards.size() == 14), _under_finger())
	await _wait(0.9)
	_check("the player is told to discard", _node("StatusLabel").text == "Select a card, then Discard or Declare", _node("StatusLabel").text)
	for id: String in ["2♣-1", "3♣-1", "4♣-1"]:
		_tap(_card_spot(table, id))
		_check("tapping the %s selects it" % id, table._selected.has(id), _under_finger())
		await _wait(0.12)
	await _wait(0.4)
	_check("Group can be used with three cards selected", not _node("GroupButton").disabled and _node("DiscardButton").disabled)
	await _shot("table-selected")

	await _press("GroupButton")
	await _wait(0.4)
	_tap(_card_spot(table, "JOKER-1"))
	await _wait(0.3)
	_check("other groups offer '+ Add'", table._group_labels[1].text == "+ Add" and not table._group_labels[1].disabled, table._group_labels[1].text)
	await _press_button(table._group_labels[1], "the '+ Add' label")
	await _wait(0.5)
	_check("the labels name the melds", table._group_labels[0].text == "Pure sequence" and table._group_labels[1].text == "Sequence", "%s / %s" % [table._group_labels[0].text, table._group_labels[1].text])
	_check("the points hint counts only the loose king", _badge_info() == "Points in hand: 10", _badge_info())
	await _shot("table-grouped")

	# Carrying a card with a finger: onto another group, between two groups, beside either end
	# of the hand, onto the bare table, and (later) onto the open pile
	var hand_area: Control = _node("HandArea")
	var king := "K♥-1"
	_check("the hand reaches from edge to edge, as it will on a phone", table._spans[0].left < 60.0 and table._spans[-1].right > hand_area.size.x - 60.0, "%s..%s of %s" % [table._spans[0].left, table._spans[-1].right, hand_area.size.x])

	# on the front card of the first group, left of its middle: in front of that group
	var first: Dictionary = table._spans[0]
	var over_first_group := _in_hand(Vector2(first.left + (first.xs[1] - first.xs[0]) * 0.4, 110.0))
	_carry(_card_spot(table, king), over_first_group)
	_check("sliding a finger picks the card up", table._dragging_id == king, _under_finger())
	await _wait(0.15)
	_slide(over_first_group, over_first_group)
	_check("the carried card stays under the finger, even after a fast swipe", Rect2(table._cards[king].global_position, table._cards[king].size).has_point(over_first_group), "%s, finger at %s" % [table._cards[king].global_position, over_first_group])
	_check("a marker shows where the carried card would go", table._marker.visible)
	await _shot("table-carrying")
	_touch(over_first_group, false)
	await _wait(0.4)
	_check("dropping on a group puts the card there, at that spot", Game.groups.size() == 2 and Game.groups[0][0] == king, str(Game.groups))
	_check("the marker is gone after the drop", not table._marker.visible)

	var gap_middle: float = (table._spans[0].right + table._spans[1].left) / 2.0
	var in_the_gap := _in_hand(Vector2(gap_middle, 110.0))
	_carry(_card_spot(table, king), in_the_gap)
	_check("the marker stands in the gap between two groups", table._marker.visible and absf(table._marker.position.x + 3.0 - gap_middle) < 1.0, "%s, gap at %s" % [table._marker.position, gap_middle])
	await _shot("table-carrying-between-groups")
	_touch(in_the_gap, false)
	await _wait(0.4)
	_check("dropping between two groups starts a new group there", Game.groups.size() == 3 and Game.groups[1] == [king], str(Game.groups))

	# beside either end: these spots must be on the screen, however full the hand is
	var before_the_start := _in_hand(Vector2(table._spans[0].left - 8.0, 110.0))
	_check("there is room for a finger left of the hand", before_the_start.x >= 8.0, str(before_the_start))
	_carry(_card_spot(table, king), before_the_start)
	_touch(before_the_start, false)
	await _wait(0.4)
	_check("dropping left of the hand starts a new group at the front", Game.groups.size() == 3 and Game.groups[0] == [king], str(Game.groups))

	var past_the_end := _in_hand(Vector2(table._spans[-1].right + 8.0, 110.0))
	_check("there is room for a finger right of the hand", past_the_end.x <= get_viewport().get_visible_rect().size.x - 8.0, str(past_the_end))
	_carry(_card_spot(table, king), past_the_end)
	_touch(past_the_end, false)
	await _wait(0.4)
	_check("dropping right of the hand starts a new group at the end", Game.groups.size() == 3 and Game.groups[2] == [king], str(Game.groups))

	var bare_table := Vector2(160, 280)  # felt with nothing on it, at every width, well above the hand
	_carry(_card_spot(table, king), bare_table)
	_touch(bare_table, false)
	await _wait(0.4)
	_check("dropping on the bare table changes nothing", Game.groups.size() == 3 and Game.groups[2] == [king], str(Game.groups))
	_check("and the card goes back to its place", table._cards[king].position.is_equal_approx(Vector2(table._spans[2].xs[0], table.SELECT_LIFT + 6.0)), str(table._cards[king].position))

	# Dropping the finishing card on "Declare here" asks the same question as the button
	var slot: Control = _node("DeclareSlot")
	_carry(_card_spot(table, king), _middle(slot))
	_touch(_middle(slot), false)
	_check("dropping a card on Declare here asks first", await _until(func() -> bool: return question_box.visible) and question_box.dialog_text.begins_with("Finish with the K of hearts"), question_box.dialog_text)
	await _wait(0.3)  # the box takes a frame to find its place (headless too)
	await _press_button(question_box.get_cancel_button(), "the question's Cancel button", Vector2(question_box.position))
	await _wait(0.3)
	_check("cancelling keeps the card, selected", not question_box.visible and table._cards.has(king) and table._selected == [king])
	_tap(_card_spot(table, king))  # selected by the drop; a tap puts it down again
	await _wait(0.3)
	_tap(_card_spot(table, king))
	_check("tapping the king selects it", table._selected == [king], _under_finger())
	await _wait(0.3)
	await _press("DeclareButton")
	_check("declaring asks first", await _until(func() -> bool: return question_box.visible))
	_check("the question names the card", question_box.dialog_text == "Finish with the K of hearts and show your hand?", question_box.dialog_text)
	await _shot("declare-question")
	await _press_in_box(question_box, "the question's Declare button")
	# The round is won, but the opponent first gets 15 seconds to arrange their own cards
	_check("after declaring, the player waits for the opponent", await _until(func() -> bool: return _node("StatusLabel").text == "You declared! The others are arranging their cards") and not _node("ResultOverlay").visible, _node("StatusLabel").text)
	_check("the opponent's badge says what they are doing", table._badges.values()[0]._info_label.text == "Arranging...", table._badges.values()[0]._info_label.text)
	await _wait(0.7)
	await _shot("declared-waiting")
	r = await b.submit_hand()
	_check("the result appears once the opponent's cards are in", r.ok and await _until(func() -> bool: return _node("ResultOverlay").visible))
	await _wait(0.9)
	_check("the winner is announced", _node("ResultTitle").text == "You won!" and _node("BackButton").visible and not _node("LeaveGameButton").visible, _node("ResultTitle").text)
	_check("both hands are listed", _node("ResultRows").get_child_count() == 2)
	# The loser pays their points at 10 coins each
	var lost := 0
	for row: Dictionary in Game.state.get("lastResult", {}).get("players", []):
		if row.get("id") != Game.player_id:
			lost = mini(int(row.get("points", 0)), 80) * 10
	# (In this fixed deal the opponent's cards make a valid hand once sorted: 0 points, nothing to pay)
	var prize_ok: bool = _node("PrizeLabel").visible and _node("PrizeLabel")._label.text == "%s coins won" % Ui.coins_text(lost) if lost > 0 else not _node("PrizeLabel").visible
	_check("the result says what was won", prize_ok, "%d | %s" % [lost, _node("PrizeLabel")._label.text])
	_check("the loser pays the winner their points", await _until(func() -> bool: return Game.coins == 50000 + lost and b.coins == 50000 - lost), "%d / %d" % [Game.coins, b.coins])
	_check("the winner gets confetti", table._confetti.emitting)
	_check("the finishing card has landed on the open pile", _node("OpenCard").card.get("id") == king and _node("FlyLayer").get_child_count() == 0, str(_node("OpenCard").card))
	await _shot("result")
	await _press("BackButton")
	_check("back on the menu", await _until(func() -> bool: return _has("MenuPanel") and _node("MenuPanel").visible))
	_check("the menu shows the new balance", _node("CoinsLabel")._label.text == Ui.coins_text(50000 + lost), _node("CoinsLabel")._label.text)
	await b.leave()

	# ---------- game 2: pool, the opponent starts, open pile, drop ----------
	r = await b.create_game("pool", 2)
	await _press("FriendsTile")
	await _wait(0.4)
	_node("CodeEdit").text = str(r.get("roomCode", "")).to_lower()
	await _press("JoinButton")
	_check("joining by room code opens the table", await _until(func() -> bool: return _has("HandArea") and Game.hand().size() == 13))
	await _wait(1.9)
	table = _screen()
	hand_area = _node("HandArea")
	_check("the player waits for the opponent", _node("StatusLabel").text == "Waiting for %s" % name_b, _node("StatusLabel").text)
	_check("a pool game shows round and total", _node("RoomLabel").text.contains("Pool 101") and _node("TotalLabel").visible and _node("DropButton").disabled, _node("RoomLabel").text)
	await _shot("table-waiting")

	r = await b.draw()
	await _wait(0.12)
	_check("the opponent's draw is shown as a card crossing the table", _node("FlyLayer").get_child_count() == 1)
	await _until(func() -> bool: return b.hand().size() == 14)
	await _wait(0.5)
	var thrown := str(b.hand()[0].id)
	r = await b.discard(thrown)
	await _wait(0.15)
	_check("the opponent's discard is shown flying to the open pile", _node("FlyLayer").get_child_count() == 1 and _node("OpenCard").card.get("id") != thrown)
	await _shot("opponent-discarding")
	_check("the turn comes to the player", r.ok and await _until(func() -> bool: return Game.is_my_turn()))
	await _wait(0.6)
	_check("the discard has landed", _node("OpenCard").card.get("id") == thrown and _node("FlyLayer").get_child_count() == 0)
	_tap(_middle(_node("OpenCard")))
	_check("tapping the open pile picks it up", await _until(func() -> bool: return table._cards.has(thrown)), _under_finger())
	await _wait(0.6)
	_check("a card from the open pile arrives face up", not table._cards[thrown].face_down)
	await _shot("table-picked-open-card")

	# Carrying a card onto the open pile is a discard; the server refuses the card just picked up
	var pile_center := _middle(_node("OpenCard"))
	_carry(_card_spot(table, thrown), pile_center)
	_check("the open pile lights up under a carried card", _node("OpenCard").highlighted, _under_finger())
	_touch(pile_center, false)
	_check("throwing it straight back is refused with a message", await _until(func() -> bool: return message_box.visible) and message_box.dialog_text.contains("cannot discard"), message_box.dialog_text)
	await _press_in_box(message_box, "the message's OK button")
	await _wait(0.4)
	_check("the refused card is back in the hand", table._cards.size() == 14 and table._cards[thrown].position.y > 0.0)

	var other := ""
	for held: Dictionary in Game.hand():
		if held.id != thrown:
			other = held.id
			break
	_carry(_card_spot(table, other), pile_center)
	_touch(pile_center, false)
	_check("carrying another card onto the open pile discards it", await _until(func() -> bool: return table._cards.size() == 13 and not Game.is_my_turn()), _under_finger())
	await _wait(0.6)

	# The back button asks before leaving, and going back closes the question again
	_go_back()
	_check("the back button asks before leaving a game", question_box.visible and question_box.title == "Leave game", question_box.title)
	_go_back()
	_check("back again closes the question", not question_box.visible and _has("HandArea"))

	r = await b.draw()
	await _until(func() -> bool: return b.hand().size() == 14)
	r = await b.discard(str(b.hand()[0].id))
	await _until(func() -> bool: return Game.is_my_turn())
	await _wait(0.6)
	await _press("DropButton")
	_check("dropping asks first", await _until(func() -> bool: return question_box.visible))
	await _press_in_box(question_box, "the question's Drop button")
	_check("the round result appears", await _until(func() -> bool: return _node("ResultOverlay").visible))
	await _wait(0.8)
	_check("a pool round shows the countdown", _node("ResultTitle").text == "%s won round 1" % name_b and _node("NextRoundLabel").text.begins_with("Next round in ") and _node("LeaveGameButton").visible and not _node("BackButton").visible, "%s | %s" % [_node("ResultTitle").text, _node("NextRoundLabel").text])
	_check("no confetti for the loser", not table._confetti.emitting)
	await _shot("round-over")

	await _press("LeaveGameButton")
	await _until(func() -> bool: return question_box.visible)
	await _press_in_box(question_box, "the question's Leave button")
	_check("leaving returns to the menu", await _until(func() -> bool: return _has("MenuPanel") and _node("MenuPanel").visible))
	await b.leave()

	# ---------- game 3: Close Joker, the joker opens with the first pure sequence ----------
	await _play_close_joker(b)
	await _see_the_opponent_open_the_joker(b)

	# ---------- game 4: the opponent declares; the player arranges and submits ----------
	await _play_opponent_declares(b)

	Game.logout()
	await _wait(0.4)
	_check("logout returns to the login form", _node("AuthPanel").visible)
	print("\nui tour: %d passed, %d failed, %d pictures in %s" % [_passed, _failed, _step, _shots])
	get_tree().quit(1 if _failed > 0 else 0)


# The unshuffled deal again: the opponent holds the ace of clubs (wild) and the diamonds 2 to K,
# which wins as soon as it is grouped. After that declaration the player has 15 seconds to
# arrange and hand in, and the Declare button is the one that submits.
func _play_opponent_declares(b: GameClient) -> void:
	var opponent := str(b.user.get("username", ""))
	await _open_private_table()
	(_node("TypeOption") as OptionButton).select(0)  # a points game
	_set_rigged(true)
	await _press("CreateButton")
	_check("show: the lobby opens", await _until(func() -> bool: return _has("CodeLabel") and _node("CodeLabel").text.length() == 6))
	var r: Dictionary = await b.join_by_code(_node("CodeLabel").text)
	_check("show: the table opens", r.ok and await _until(func() -> bool: return _has("HandArea") and Game.hand().size() == 13))
	_set_rigged(false)
	await _wait(2.0)
	var table: Variant = _screen()

	# The player draws and throws the card straight back, so the turn comes to the opponent
	_tap(_middle(_node("DeckCard")))
	_check("show: the player draws", await _until(func() -> bool: return table._cards.size() == 14), _under_finger())
	await _wait(0.9)
	_tap(_card_spot(table, str(Game.state.get("lastDrawnId"))))
	await _wait(0.3)
	await _press("DiscardButton")
	await _until(func() -> bool: return b.is_my_turn())

	r = await b.draw()
	await _until(func() -> bool: return b.hand().size() == 14)
	var drawn := str(b.state.get("lastDrawnId"))
	var diamonds: Array = b.groups[1]  # sorted by suit: the ace of clubs, the diamonds, the drawn card
	b.set_groups([diamonds.slice(0, 3), diamonds.slice(3, 6), diamonds.slice(6, 9), diamonds.slice(9) + ["A♣-1"], [drawn]])
	await _wait(0.3)
	r = await b.declare(drawn)
	_check("show: the opponent's declaration is accepted", r.ok and r.get("valid") == true, str(r))

	var told := "%s declared! Arrange your cards, then Submit" % opponent
	_check("show: the player is told to arrange and submit", await _until(func() -> bool: return _node("StatusLabel").text == told) and not _node("ResultOverlay").visible, _node("StatusLabel").text)
	var submit: Button = _node("DeclareButton")
	_check("show: the Declare button now reads Submit, and nothing else can be played", submit.text == "Submit" and not submit.disabled and _node("DiscardButton").disabled and _node("DropButton").disabled, submit.text)
	_check("show: the clock counts down from 15", _node("ClockLabel").visible and Game.seconds_until(Game.turn_ends_at) <= 15 and Game.seconds_until(Game.turn_ends_at) >= 12, _node("ClockLabel").text)
	_check("show: the opponent's badge says who declared", table._badges.values()[0]._info_label.text == "Declared", table._badges.values()[0]._info_label.text)
	await _wait(1.0)
	await _shot("arrange-after-declaration")

	await _press("DeclareButton")
	_check("show: submitting brings the result", await _until(func() -> bool: return _node("ResultOverlay").visible, 4.0))
	await _wait(0.9)
	_check("show: the opponent has won", _node("ResultTitle").text == "%s won the game" % opponent, _node("ResultTitle").text)
	_check("show: the player's sorted hand cost nothing", Game.state.lastResult.players.any(func(row: Dictionary) -> bool: return row.get("id") == Game.player_id and int(row.get("points", -1)) == 0), str(Game.state.lastResult.players))
	_check("show: the button is Declare again", submit.text == "Declare")
	await _press("BackButton")
	_check("show: back on the menu", await _until(func() -> bool: return _has("MenuPanel") and _node("MenuPanel").visible))
	await b.leave()


# The hands are the CLOSED_DEAL of tests/test_server.js: the player can make 2-3-4 of spades,
# the opponent can make no sequence at all, and the 7 of hearts is cut as the joker.
func _play_close_joker(b: GameClient) -> void:
	var question_box: ConfirmationDialog = Ui.get_node("QuestionBox")
	await _open_private_table()
	var types: OptionButton = _node("TypeOption")
	_check("the menu offers Close Joker", types.item_count == 6 and types.get_item_text(2) == "Close Joker 240", str(types.item_count))
	types.select(2)  # a tap would have to land inside the drop-down list
	_set_rigged(true, "closed")
	await _press("CreateButton")
	_check("close joker: the lobby opens", await _until(func() -> bool: return _has("CodeLabel") and _node("CodeLabel").text.length() == 6))
	await _wait(0.5)
	var info: String = _node("InfoLabel").text
	_check("close joker: the lobby names the game and explains the joker", info.contains("Close Joker 240 rummy") and info.contains("face down"), info)
	await _shot("close-joker-lobby")

	var r: Dictionary = await b.join_by_code(_node("CodeLabel").text)
	_check("close joker: the table opens", r.ok and await _until(func() -> bool: return _has("HandArea") and Game.hand().size() == 13))
	_set_rigged(false)
	var table: Variant = _screen()
	if not Game.card("2♠-1").is_empty():
		await _see_the_joker_open(table, b)
	else:
		print("skipped: Close Joker game (this test server does not know the \"closed\" deal)")
		await _wait(2.0)

	await _press("LeaveButton")
	await _until(func() -> bool: return question_box.visible)
	await _press_in_box(question_box, "the question's Leave button")
	_check("close joker: leaving returns to the menu", await _until(func() -> bool: return _has("MenuPanel") and _node("MenuPanel").visible))
	await b.leave()


func _see_the_joker_open(table: Variant, b: GameClient) -> void:
	await _wait(2.4)  # the deal, and the hint that follows it
	var joker_card: CardView = _node("JokerCard")
	_check("close joker: the room is named", _node("RoomLabel").text.contains("Close Joker 240") and _node("RoomLabel").text.contains("Round 1"), _node("RoomLabel").text)
	_check("close joker: the joker shows its back", joker_card.face_down and joker_card.card.is_empty() and _node("JokerLabel").text == "Joker  ·  hidden", _node("JokerLabel").text)
	_check("close joker: the server has not sent it", Game.joker_hidden() and Game.state.get("joker") == null)
	var notices: Array = Ui.get_node("Notices").get_children().map(func(panel: Node) -> String: return (panel.get_child(0) as Label).text)
	_check("close joker: the player is told how to see it", notices.has("Make a pure sequence to see the joker"), str(notices))
	_check("close joker: it is scored as a pool game", _node("TotalLabel").visible)
	var my_badge: PlayerBadge = _node("MyBadge")
	var their_badge: PlayerBadge = table._badges.values()[0]
	_check("close joker: no green dot while nobody has seen the joker", not my_badge._joker_seen and not their_badge._joker_seen)
	await _shot("close-joker-hidden")

	# 2-3-4 of spades in a group of their own: the first life
	for id: String in ["2♠-1", "3♠-1", "4♠-1"]:
		_tap(_card_spot(table, id))
		_check("close joker: tapping the %s selects it" % id, table._selected.has(id), _under_finger())
		await _wait(0.12)
	await _wait(0.3)
	await _press("GroupButton")
	_check("close joker: grouping a pure sequence opens the joker", await _until(func() -> bool: return not Game.joker_hidden()))
	await _wait(0.2)
	await _shot("close-joker-opening")
	await _wait(1.0)
	_check("close joker: the joker is face up", not joker_card.face_down and joker_card.card.get("code") == "7♥" and _node("JokerLabel").text == "Joker  ·  7s wild", _node("JokerLabel").text)
	_check("close joker: the sequence is named under its cards", table._group_labels[0].text == "Pure sequence", table._group_labels[0].text)
	_check("close joker: the opponent still sees nothing", b.joker_hidden() and b.state.get("joker") == null)
	_check("close joker: the green dot is on our own badge only", my_badge._joker_seen and my_badge._dot_grow == 1.0 and not their_badge._joker_seen, "%s %s %s" % [my_badge._joker_seen, my_badge._dot_grow, their_badge._joker_seen])
	await _shot("close-joker-open")

	# A turn, then the opponent gives up the round; the next round closes the joker again
	_tap(_middle(_node("DeckCard")))
	_check("close joker: a card is drawn", await _until(func() -> bool: return table._cards.size() == 14), _under_finger())
	await _wait(0.9)
	var drawn := str(Game.state.get("lastDrawnId"))
	_tap(_card_spot(table, drawn))
	await _wait(0.3)
	await _press("DiscardButton")
	_check("close joker: the turn passes", await _until(func() -> bool: return b.is_my_turn()))
	var r: Dictionary = await b.drop()
	_check("close joker: the round result appears", r.ok and await _until(func() -> bool: return _node("ResultOverlay").visible))
	await _wait(1.2)
	_check("close joker: it is a round of a longer game", _node("ResultTitle").text == "You won round 1" and _node("NextRoundLabel").text.begins_with("Next round in "), _node("ResultTitle").text)
	_check("close joker: the green dot goes when the round ends", not my_badge._joker_seen)
	_check("close joker: the next round is dealt", await _until(func() -> bool: return Game.status() == "playing" and int(Game.state.get("round", 0)) == 2, 16.0))
	await _wait(2.4)
	# Now and then a random deal holds a whole suit that is a run: then the joker opens at once
	_check("close joker: the joker pile shows what the server sent", joker_card.face_down == Game.joker_hidden() and (_node("JokerLabel").text == "Joker  ·  hidden") == Game.joker_hidden(), _node("JokerLabel").text)
	_check("close joker: round 2 has the green dot only if the deal opened the joker", my_badge._joker_seen == (not Game.joker_hidden()))
	_check("close joker: round 2 is named", _node("RoomLabel").text.contains("Round 2"), _node("RoomLabel").text)
	await _shot("close-joker-round-2")


# Close Joker the other way round: the opponent sits first, so the CLOSED_DEAL gives them
# 2-3-4 of spades. When they make it, their badge gets the green dot on our screen.
func _see_the_opponent_open_the_joker(b: GameClient) -> void:
	var question_box: ConfirmationDialog = Ui.get_node("QuestionBox")
	_set_rigged(true, "closed")
	var r: Dictionary = await b.create_game("close_joker", 2)
	await _press("FriendsTile")
	await _wait(0.4)
	_node("CodeEdit").text = str(r.get("roomCode", ""))
	await _press("JoinButton")
	_check("their close joker: the table opens", await _until(func() -> bool: return _has("HandArea") and Game.hand().size() == 13 and b.hand().size() == 13))
	_set_rigged(false)
	if b.card("2♠-1").is_empty():
		print("skipped: their Close Joker game (this test server does not know the \"closed\" deal)")
	else:
		await _wait(2.4)  # the deal
		var table: Variant = _screen()
		var my_badge: PlayerBadge = _node("MyBadge")
		var their_badge: PlayerBadge = table._badges.values()[0]
		_check("their close joker: no green dot yet", not my_badge._joker_seen and not their_badge._joker_seen)

		var spades: Array = b.groups[0]
		b.set_groups([spades.slice(0, 3), spades.slice(3)] + b.groups.slice(1))
		_check("their close joker: the opponent's pure sequence opens the joker for them", await _until(func() -> bool: return not b.joker_hidden()))
		_check("their close joker: their badge gets the green dot", await _until(func() -> bool: return their_badge._joker_seen))
		var notices: Array = Ui.get_node("Notices").get_children().map(func(panel: Node) -> String: return (panel.get_child(0) as Label).text)
		_check("their close joker: the popup says so too", notices.any(func(text: String) -> bool: return text.contains("has seen the joker")), str(notices))
		_check("their close joker: not on our badge, and our joker stays closed", not my_badge._joker_seen and Game.joker_hidden())
		await _wait(0.2)
		await _shot("close-joker-their-dot-popping")
		await _wait(0.6)
		_check("their close joker: the dot has popped to full size", their_badge._dot_grow == 1.0, str(their_badge._dot_grow))
		# The popups stand over the opponent's badge for a few seconds; the dot stays after them
		await _until(func() -> bool: return Ui.get_node("Notices").get_child_count() == 0, 6.0)
		_check("their close joker: the dot is still there after the popup has gone", their_badge._joker_seen)
		await _shot("close-joker-their-dot")

	await _press("LeaveButton")
	await _until(func() -> bool: return question_box.visible)
	await _press_in_box(question_box, "the question's Leave button")
	_check("their close joker: leaving returns to the menu", await _until(func() -> bool: return _has("MenuPanel") and _node("MenuPanel").visible))
	await b.leave()


# The second line of the player's own badge, e.g. "Points in hand: 10".
func _badge_info() -> String:
	return _node("MyBadge")._info_label.text


# Untyped on purpose: the tour reads properties of many different kinds of node.
func _node(node_name: String) -> Variant:
	return _main.find_child(node_name, true, false)


func _has(node_name: String) -> bool:
	return _node(node_name) != null


# The screen currently shown by the main scene.
func _screen() -> Control:
	var holder := _main.get_node("%Screen")
	return holder.get_child(holder.get_child_count() - 1)


# ---------- a finger ----------
# Places are in the units the game is laid out in; `_to_window` turns them into the window
# pixels in which a phone reports a touch.

func _to_window(at: Vector2) -> Vector2:
	return get_viewport().get_final_transform() * at


## Puts the finger down at `at`, or lifts it there.
func _touch(at: Vector2, down: bool) -> void:
	var event := InputEventScreenTouch.new()
	event.index = 0
	event.pressed = down
	event.position = _to_window(at)
	Input.parse_input_event(event)
	Input.flush_buffered_events()


## Moves the finger, which is down, from one place to another.
func _slide(from: Vector2, to: Vector2) -> void:
	var event := InputEventScreenDrag.new()
	event.index = 0
	event.position = _to_window(to)
	event.relative = _to_window(to) - _to_window(from)
	Input.parse_input_event(event)
	Input.flush_buffered_events()


func _tap(at: Vector2) -> void:
	_touch(at, true)
	_touch(at, false)


## Puts the finger down at `from` and slides it to `to`. It stays down: lift it with _touch.
func _carry(from: Vector2, to: Vector2) -> void:
	_touch(from, true)
	var at := from
	for step in range(1, 9):
		var next := from.lerp(to, step / 8.0)
		_slide(at, next)
		at = next


## What the last touch landed on, for the report when a touch did nothing.
func _under_finger() -> String:
	var hit := get_viewport().gui_get_hovered_control()
	return "the finger was on nothing" if hit == null else "the finger was on %s" % hit.get_path()


func _middle(control: Control) -> Vector2:
	return control.get_global_transform_with_canvas() * (control.size / 2.0)


## A place in the hand area, given in its own coordinates.
func _in_hand(local: Vector2) -> Vector2:
	return (_node("HandArea") as Control).get_global_transform_with_canvas() * local


## The middle of the part of a hand card that its neighbour does not cover.
func _card_spot(table: Variant, id: String) -> Vector2:
	for span: Dictionary in table._spans:
		var index: int = span.ids.find(id)
		if index >= 0:
			var left: float = span.xs[index]
			var shown_until: float = span.xs[index + 1] if index + 1 < span.xs.size() else span.right
			var view: CardView = table._cards[id]
			return _in_hand(Vector2((left + shown_until) / 2.0, view.position.y + view.size.y / 2.0))
	_check("the %s is in the hand" % id, false)
	return Vector2.ZERO


## Scrolls a form until the control can be seen, as a player would before touching it.
func _bring_into_view(control: Control) -> void:
	var parent := control.get_parent()
	while parent != null:
		if parent is ScrollContainer:
			(parent as ScrollContainer).ensure_control_visible(control)
			await get_tree().process_frame
			await get_tree().process_frame
			return
		parent = parent.get_parent()


# Play with Friends > Create Table: the setup box for a private table, which has a lobby and a
# room code for the opponent to join with. (A game tile's Play Now searches for players instead.)
func _open_private_table() -> void:
	await _press("FriendsTile")
	await _wait(0.4)
	await _press("CreateTableButton")
	await _wait(0.4)


## Taps a button of one of the screens. A button a finger cannot reach fails the tour.
func _press(button_name: String) -> void:
	var button := _node(button_name) as BaseButton
	if button == null or button.disabled or not button.is_visible_in_tree():
		_check("%s can be pressed" % button_name, false)
		return
	await _press_button(button, button_name)


## `origin` is where the button's window sits on the screen, for buttons inside a message box.
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


## Taps the confirming button of a message box or a question.
func _press_in_box(box: AcceptDialog, what: String) -> void:
	if not box.visible:
		_check("%s is on screen" % what, false)
		return
	await _press_button(box.get_ok_button(), what, Vector2(box.position))


## The phone's back button, the way the system reports it to the game.
func _go_back() -> void:
	get_tree().root.propagate_notification(NOTIFICATION_WM_GO_BACK_REQUEST)


func _shot(label: String) -> void:
	_step += 1
	if DisplayServer.get_name() == "headless":
		return  # run with --headless nothing is drawn: every check still runs, without pictures
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("%s/%02d-%s.png" % [_shots, _step, label])


# What is written in the flag file names the fixed deal; "1" is the unshuffled deck.
func _set_rigged(on: bool, deal: String = "1") -> void:
	if _rig_flag.is_empty():
		return
	if on:
		FileAccess.open(_rig_flag, FileAccess.WRITE).store_string(deal)
	elif FileAccess.file_exists(_rig_flag):
		DirAccess.remove_absolute(_rig_flag)


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
