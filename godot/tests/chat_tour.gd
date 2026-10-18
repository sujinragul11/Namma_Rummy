extends Control
## Chat and emoji at the table, played with a finger like ui_tour: the two buttons, the chat
## panel with its quick phrases and its line to type in, the emoji picker, the bubbles and emoji
## beside the seats, the unread count, the Chat switch, the back button, catching up after a
## dropped connection, and that none of it gets in the way of a move. The opponent is a second,
## screenless player. Typing is the only thing not done with a finger (the field's text is set).
##
## Run against a TEST server (it registers throwaway accounts), with a long turn clock so the
## tour is not timed out while it talks:
##   TURN_TIMEOUT_SECONDS=600 node tests/test_server.js --port=3161 --db=My_Rummy_chat_test
##   godot --path . res://tests/chat_tour.tscn -- --profile=chattour --server=http://127.0.0.1:3161 --shots=<folder> --mute
## With --headless before --path every check runs, without pictures.

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
	Config.save_chat(true)  # a previous run may have left the switch off
	_main = (load("res://scenes/main.tscn") as PackedScene).instantiate() as Control
	add_child(_main)
	_run()


func _run() -> void:
	var tag := "%d%04d" % [int(Time.get_unix_time_from_system()) % 1000000, randi() % 10000]
	var name_a := "ca_" + tag
	var name_b := "cb_" + tag
	if _main.has_method("loading"):
		await _until(func() -> bool: return not _main.call("loading"), 20.0)

	# ---------- two players at one table ----------
	var r: Dictionary = await Game.register(name_a, "9" + tag.substr(0, 9), "secret12")
	_check("A registers", r.ok, str(r.get("error")))
	var b := GameClient.new()
	b.remember_login = false
	add_child(b)
	r = await b.register(name_b, "8" + tag.substr(0, 9), "secret12")
	_check("B registers", r.ok, str(r.get("error")))
	_check("both are online", await _until(func() -> bool: return Game.is_online() and b.is_online()))
	r = await Game.create_game("points", 2, 0, true)
	r = await b.join_by_code(str(r.get("roomCode", "")))
	_check("the game starts", await _until(func() -> bool: return Game.status() == "playing" and _has("TableChat"), 10.0))
	await _wait(2.0)  # the deal
	var table: Variant = _screen()  # untyped: the tour looks inside the table script
	var chat: TableChat = _node("TableChat")
	var quiet := {"busy": 0, "state": 0}
	var count_busy := func() -> void: quiet.busy += 1
	var count_state := func() -> void: quiet.state += 1
	Game.busy_changed.connect(count_busy)
	Game.state_changed.connect(count_state)
	var chat_button: Button = _node("ChatButton")
	var emoji_button: Button = _node("EmojiButton")
	var area := get_viewport().get_visible_rect()

	# ---------- the buttons ----------
	var buttons := chat_button.get_global_rect().merge(emoji_button.get_global_rect())
	_check("the chat buttons sit at the top right", area.encloses(buttons) and buttons.end.x > area.size.x - 30.0 and buttons.position.y < 20.0, str(buttons))
	var clear := true
	for other: String in ["LeaveButton", "SoundSwitches", "RoomLabel"]:
		if (_node(other) as Control).get_global_rect().intersects(buttons):
			clear = false
	for badge: Control in table._badges.values():
		if badge.get_global_rect().intersects(buttons):
			clear = false
	_check("they cover none of the table's own buttons, pills or seats", clear)
	_check("both panels start closed", not chat.is_chat_open() and not chat.is_emoji_open() and not _node("ChatPanel").visible and not _node("EmojiPanel").visible)
	await _shot("table-with-chat-buttons")

	# ---------- the chat panel ----------
	await _press_button(chat_button, "the chat button")
	await _wait(0.35)
	var panel: Control = _node("ChatPanel")
	_check("the chat panel opens", chat.is_chat_open() and panel.visible and panel.modulate.a > 0.99)
	_check("it says nothing was said yet", _row_text(0).begins_with("Nothing said yet"), _row_text(0))
	var reachable := true
	for button_name: String in ["SortButton", "GroupButton", "DiscardButton", "DeclareButton", "DropButton", "DeckCard", "OpenCard", "LeaveButton"]:
		if (_node(button_name) as Control).get_global_rect().intersects(panel.get_global_rect()):
			reachable = false
			print("  covered by the chat panel: ", button_name)
	_check("the open panel leaves the pile and every action button uncovered", reachable)
	_check("the panel fits on the screen", area.encloses(panel.get_global_rect()), str(panel.get_global_rect()))
	await _shot("chat-open")

	await _press_button(_node("Phrase0"), "the Good luck! phrase")
	_check("a phrase reaches the other player", await _until(func() -> bool: return _last(b).get("text") == "Good luck!" and _last(b).get("userId") == Game.player_id))
	_check("and shows in our own log, as You", await _until(func() -> bool: return _row_text(0) == "You  Good luck!"), _row_text(0))
	_check("with a bubble over our own seat", await _until(func() -> bool: return _has("Bubble_" + Game.player_id)))
	var mine: Control = _node("Bubble_" + Game.player_id)
	var my_seat: Rect2 = (_node("MyBadge") as Control).get_global_rect()
	await _wait(0.35)
	_check("our bubble stands just above our seat, on the screen", mine != null and area.encloses(mine.get_global_rect()) and mine.get_global_rect().end.y <= my_seat.position.y and my_seat.position.y - mine.get_global_rect().end.y < 40.0, "%s over %s" % [mine.get_global_rect() if mine != null else Rect2(), my_seat])

	var field: LineEdit = _node("ChatInput")
	field.text = "Anyone up for another game?"
	await _press("SendButton")
	_check("a typed message goes out with Send", await _until(func() -> bool: return _last(b).get("text") == "Anyone up for another game?"))
	_check("and the field is emptied", field.text.is_empty())
	await _press_button(field, "the chat field")
	_check("a finger on the field starts typing", field.has_focus())
	field.text = "Enter sends too 👍"
	field.caret_column = field.text.length()
	var enter := InputEventKey.new()
	enter.keycode = KEY_ENTER
	enter.pressed = true
	Input.parse_input_event(enter)
	Input.flush_buffered_events()
	_check("the keyboard's Enter sends it", await _until(func() -> bool: return _last(b).get("text") == "Enter sends too 👍"), str(_last(b)))

	b.send_chat("Hi from B! Good luck to you too")
	_check("the opponent's message arrives", await _until(func() -> bool: return _row_text(0) == "%s  Hi from B! Good luck to you too" % name_b), _row_text(0))
	_check("with a bubble beside the opponent's seat", await _until(func() -> bool: return _has("Bubble_" + b.player_id)))
	await _wait(0.35)
	var theirs: Control = _node("Bubble_" + b.player_id)
	var their_seat: Rect2 = table._badges[b.player_id].get_global_rect()
	_check("it stands beside their seat without covering it, on the screen", theirs != null and area.encloses(theirs.get_global_rect()) and not theirs.get_global_rect().intersects(their_seat) and theirs.get_global_rect().get_center().distance_to(their_seat.get_center()) < 320.0, "%s beside %s" % [theirs.get_global_rect() if theirs != null else Rect2(), their_seat])
	_check("and clear of the open chat panel and the buttons", theirs != null and not theirs.get_global_rect().intersects(panel.get_global_rect()) and not theirs.get_global_rect().intersects(buttons), str(theirs.get_global_rect() if theirs != null else Rect2()))
	_check("nothing counts as unread while the panel is open", chat.unread() == 0)
	await _shot("chat-bubbles")

	# ---------- closed: the unread count ----------
	await _press("ChatClose")
	await _wait(0.35)
	_check("the cross closes the panel", not chat.is_chat_open() and not panel.visible)
	b.send_chat("Your turn soon")
	_check("a message while it is closed counts as unread", await _until(func() -> bool: return chat.unread() == 1))
	await _wait(0.4)
	await _shot("chat-unread")
	await _press_button(chat_button, "the chat button")
	_check("opening the panel reads it", chat.unread() == 0 and chat.is_chat_open())
	_go_back()
	await _wait(0.35)
	var question_box: ConfirmationDialog = Ui.get_node("QuestionBox")
	_check("the back button closes the panel and does not ask to leave", not chat.is_chat_open() and not question_box.visible and Game.status() == "playing")

	# ---------- emoji ----------
	await _press_button(emoji_button, "the emoji button")
	await _wait(0.35)
	_check("the emoji picker opens", chat.is_emoji_open() and _node("EmojiPanel").visible)
	_check("it offers every emoji", GameClient.EMOJIS.all(func(emoji_name: String) -> bool: return _has("Emoji_" + emoji_name)))
	await _shot("emoji-picker")
	await _press("Emoji_fire")
	_check("an emoji reaches the other player", await _until(func() -> bool: return _last(b).get("emoji") == "fire"))
	_check("the picker closes after a pick", not chat.is_emoji_open())
	_check("our emoji jumps out of our own picture", await _until(func() -> bool: return _has("Reaction_" + Game.player_id)))
	await _wait(0.5)
	var jumped: Control = _node("Reaction_" + Game.player_id)
	_check("close to our seat", jumped != null and jumped.get_global_rect().get_center().distance_to(Vector2(my_seat.position.x + my_seat.size.y / 2.0, my_seat.get_center().y)) < 110.0, str(jumped.get_global_rect() if jumped != null else Rect2()))
	await _shot("reaction-mine")
	b.send_emoji("laugh")
	_check("the opponent's emoji shows at their seat", await _until(func() -> bool: return _has("Reaction_" + b.player_id)))
	await _wait(0.5)
	jumped = _node("Reaction_" + b.player_id)
	_check("close to their picture", jumped != null and jumped.get_global_rect().get_center().distance_to(Vector2(their_seat.position.x + their_seat.size.y / 2.0, their_seat.get_center().y)) < 110.0, str(jumped.get_global_rect() if jumped != null else Rect2()))
	await _shot("reaction-opponent")
	b.send_emoji("no-such-emoji")
	await _wait(0.4)
	_check("an emoji the server does not know is not sent", _last(b).get("emoji") == "laugh")

	# ---------- the Chat switch ----------
	await _press_button(chat_button, "the chat button")
	await _wait(0.35)
	await _press("ChatSwitch")
	_check("the switch turns chat off, and stays off", not Config.chat_on and not _node("ChatSwitch").button_pressed)
	_check("the log says so", _row_text(0).begins_with("Chat is off"), _row_text(0))
	_check("what the opponent wrote is hidden, what we wrote stays", not _log_has("Hi from B!") and _log_has("Good luck!"))
	await _until(func() -> bool: return not _has("Bubble_" + b.player_id), 6.0)
	b.send_chat("can you read this?")
	await _until(func() -> bool: return _last(Game).get("text") == "can you read this?")
	await _wait(0.4)
	_check("with chat off a new message shows nowhere", _last(Game).get("text") == "can you read this?" and not _has("Bubble_" + b.player_id) and not _log_has("can you read this?"))
	var rows_before := _rows()
	b.send_emoji("heart")
	_check("but the opponent's emoji still shows, at the seat and in the log", await _until(func() -> bool: return _has("Reaction_" + b.player_id) and _rows() == rows_before + 1 and _row_text(1).begins_with(name_b)), _row_text(1))
	await _shot("chat-off")
	await _press("ChatSwitch")
	_check("turned on again, everything said is back", Config.chat_on and _log_has("can you read this?") and _log_has("Hi from B!"))

	# ---------- reporting and blocking ----------
	await _wait(3.0)  # B has talked a lot: the server lets a player send six messages in ten seconds
	b.send_chat("you play like a child")
	_check("the opponent writes something rude", await _until(func() -> bool: return _last(Game).get("text") == "you play like a child"))
	var rude: Dictionary = _last(Game)
	var rude_row := "ChatRow_%d" % int(rude.get("id", 0))
	await _wait(0.2)
	_check("our own lines cannot be reported", (_node("ChatRow_%d" % int(_find(Game, "Good luck!").get("id", 0))) as Control).mouse_filter == Control.MOUSE_FILTER_IGNORE)
	await _press_button(_node(rude_row), "the rude line")
	_check("a tap on it offers to report or block", (_node("ChatMenuShade") as Control).visible and _has("ReportButton") and _has("BlockButton") and _has("MenuCancel"))
	await _wait(0.4)
	var menu_box: Rect2 = (_node("ChatMenu") as Control).get_global_rect()
	_check("the choices stand in the middle of the screen", area.encloses(menu_box) and menu_box.get_center().distance_to(area.get_center()) < 40.0, str(menu_box))
	await _shot("report-menu")
	_go_back()
	await _wait(0.2)
	_check("the back button closes the choice, not the panel", not (_node("ChatMenuShade") as Control).visible and chat.is_chat_open())
	await _press_button(_node(rude_row), "the rude line")
	await _press("ReportButton")
	_check("reporting asks first", await _until(func() -> bool: return question_box.visible and question_box.dialog_text.contains("you play like a child") and question_box.dialog_text.contains(name_b)), question_box.dialog_text)
	await _shot("report-question")
	await _press_button(question_box.get_ok_button(), "the question's Report button", Vector2(question_box.position))
	_check("the report blocks the sender", await _until(func() -> bool: return Game.is_chat_blocked(b.player_id)))
	_check("their bubble leaves the table at once", not _has("Bubble_" + b.player_id))
	_check("their lines leave the log", await _until(func() -> bool: return not _log_has("you play like a child") and not _log_has("Hi from B!") and _log_has("Good luck!")))
	_check("and a line says whom we blocked", _has("BlockedNote") and (_node("BlockedNote") as Label).text.contains(name_b))
	await _shot("blocked")
	await _wait(1.0)
	b.send_chat("why did you block me")
	b.send_emoji("angry")
	await _wait(1.0)
	_check("nothing more from the blocked player arrives", _find(Game, "why did you block me").is_empty() and _last(Game).get("emoji") != "angry" and not _has("Reaction_" + b.player_id))
	await _press_button(_node("BlockedNote"), "the line about the blocked player")
	await _press("Unblock_" + b.player_id)
	_check("they can be unblocked from there", await _until(func() -> bool: return not Game.is_chat_blocked(b.player_id) and not _has("BlockedNote")))
	_check("and what they said before comes back", _log_has("you play like a child"))
	await _press_button(_node(rude_row), "the rude line")
	await _press("BlockButton")
	_check("blocking without reporting works too", await _until(func() -> bool: return Game.is_chat_blocked(b.player_id)))
	await _press_button(_node("BlockedNote"), "the line about the blocked player")
	await _press("Unblock_" + b.player_id)
	await _until(func() -> bool: return not Game.is_chat_blocked(b.player_id))

	# ---------- moves are not disturbed ----------
	_check("talking never made the table busy", quiet.busy == 0, str(quiet.busy))
	_check("nor sent a table update", quiet.state == 0, str(quiet.state))
	if not Game.is_my_turn():
		r = await b.draw()
		r = await b.discard(str(b.hand()[0].id))
		await _until(func() -> bool: return Game.is_my_turn())
	_check("with the chat panel open it is our turn", Game.is_my_turn() and chat.is_chat_open())
	await _press("DeckCard")
	_check("a finger draws from the deck", await _until(func() -> bool: return Game.hand().size() == 14))
	await _wait(0.5)
	var thrown := str(table._spans[0].ids[0])
	_tap(_card_spot(table, thrown))
	_check("a card is picked from the hand", table._selected == [thrown], str(table._selected))
	await _press("DiscardButton")
	_check("and discarded with the Discard button", await _until(func() -> bool: return Game.hand().size() == 13 and not Game.is_my_turn()))
	await _shot("move-with-chat-open")

	# ---------- a dropped connection ----------
	var said := b.chat_log.size()
	b.socket.close()
	b.chat_log = []
	b.socket.open(b.server_url, {"token": b.token})
	_check("after a dropped connection the chat comes back", await _until(func() -> bool: return b.is_online() and b.chat_log.size() == said), "%d of %d" % [b.chat_log.size(), said])

	# ---------- leaving ----------
	Game.busy_changed.disconnect(count_busy)
	Game.state_changed.disconnect(count_state)
	Game.leave()
	_check("leaving the table forgets its chat", await _until(func() -> bool: return Game.state.is_empty() and Game.chat_log.is_empty()))
	b.leave()
	await _wait(0.5)

	# ---------- three at a table: the seats at the sides ----------
	var c := GameClient.new()
	c.remember_login = false
	add_child(c)
	r = await c.register("cc_" + tag, "7" + tag.substr(0, 9), "secret12")
	await _until(func() -> bool: return c.is_online() and _has("MenuPanel") and _node("MenuPanel").is_visible_in_tree(), 10.0)
	r = await Game.create_game("points", 3, 0, true)
	await b.join_by_code(str(r.get("roomCode", "")))
	await c.join_by_code(str(r.get("roomCode", "")))
	_check("a table of three starts", await _until(func() -> bool: return Game.status() == "playing" and _has("TableChat") and _screen()._badges.size() == 2, 10.0))
	await _wait(2.0)
	_check("a new table starts with an empty chat", Game.chat_log.is_empty())
	table = _screen()
	b.send_chat("Left side here, hello!")
	c.send_chat("And the right side says hi")
	_check("both side bubbles show", await _until(func() -> bool: return _has("Bubble_" + b.player_id) and _has("Bubble_" + c.player_id)))
	await _wait(0.4)
	var tidy := true
	for client: GameClient in [b, c]:
		var bubble: Control = _node("Bubble_" + client.player_id)
		var seat: Rect2 = table._badges[client.player_id].get_global_rect()
		var box := bubble.get_global_rect()
		var throw_button: Control = _node("ThrowButton_" + client.player_id)
		var covers_button := throw_button != null and box.intersects(throw_button.get_global_rect())
		if not area.encloses(box) or box.intersects(seat) or covers_button or box.get_center().distance_to(seat.get_center()) > 380.0:
			tidy = false
			print("  bubble %s, seat %s" % [box, seat])
	_check("each stands beside its own seat, clear of the throw button, on the screen", tidy)
	b.send_emoji("cool")
	c.send_emoji("party")
	_check("and the side seats get their emoji", await _until(func() -> bool: return _has("Reaction_" + b.player_id) and _has("Reaction_" + c.player_id)))
	await _wait(0.5)
	await _shot("three-players")

	# ---------- dropping out: our hand becomes one stack, face down ----------
	# The others play until it is our turn to draw
	for turn in 3:
		if Game.is_my_turn():
			break
		var mover: GameClient = b if b.is_my_turn() else c
		await mover.draw()
		await mover.discard(str(mover.hand()[0].id))
		await _until(func() -> bool: return not mover.is_my_turn())
	_check("our turn comes round", await _until(func() -> bool: return Game.is_my_turn() and Game.state.get("turnPhase") == "draw"))
	await _wait(0.5)
	_check("before dropping our cards lie face up, ready to play", not table._folded and table._cards.values().all(func(view: CardView) -> bool: return not view.face_down and view.interactive))
	await _press("DropButton")
	await _until(func() -> bool: return question_box.visible)
	await _press_button(question_box.get_ok_button(), "the question's Drop button", Vector2(question_box.position))
	_check("we are out and the round goes on", await _until(func() -> bool: return Game.me().get("status") == "dropped" and Game.status() == "playing"))
	await _wait(1.0)  # the cards gather and turn over
	_check("all 13 cards lie in one stack in the middle of the hand", _one_stack(table, 13), _stack_report(table))
	_check("all face down, and none can be tapped or carried", table._folded and table._cards.values().all(func(view: CardView) -> bool: return view.face_down and not view.interactive and not view.draggable))
	_check("no group names under it", table._group_labels.all(func(label: Button) -> bool: return not label.visible))
	_check("every button is off, Sort too", ["SortButton", "GroupButton", "DiscardButton", "DeclareButton", "DropButton"].all(func(button_name: String) -> bool: return (_node(button_name) as Button).disabled))
	_check("the status says so", (_node("StatusLabel") as Label).text == "You are out of this round", (_node("StatusLabel") as Label).text)
	var hand_area: Control = _node("HandArea")
	_tap(hand_area.get_global_transform_with_canvas() * (hand_area.size / 2.0))
	_check("a tap on the stack picks nothing", table._selected.is_empty())
	await _shot("dropped-stack")
	var next_mover: GameClient = b if b.is_my_turn() else c
	await next_mover.draw()
	await next_mover.discard(str(next_mover.hand()[0].id))
	await _until(func() -> bool: return not next_mover.is_my_turn())
	await _wait(0.4)
	_check("the stack stays while the others play on", _one_stack(table, 13) and table._cards.values().all(func(view: CardView) -> bool: return view.face_down), _stack_report(table))
	Game.leave()
	b.leave()
	c.leave()
	await _wait(0.5)
	Game.logout()
	print("\nchat tour: %d passed, %d failed, %d pictures in %s" % [_passed, _failed, _step, _shots])
	get_tree().quit(1 if _failed > 0 else 0)


# ---------- reading the screen ----------

# Whether our cards lie in one pile, as many as said, near the middle of the hand.
func _one_stack(table: Variant, count: int) -> bool:
	var views: Array = table._cards.values()
	if views.size() != count:
		return false
	var xs: Array = views.map(func(view: CardView) -> float: return view.position.x)
	var ys: Array = views.map(func(view: CardView) -> float: return view.position.y)
	var hand: Control = _node("HandArea")
	var middle: float = (xs.min() + xs.max() + (views[0] as CardView).size.x) / 2.0
	return xs.max() - xs.min() < 40.0 and ys.max() - ys.min() < 20.0 and absf(middle - hand.size.x / 2.0) < 40.0


func _stack_report(table: Variant) -> String:
	var spots: Array = table._cards.values().map(func(view: CardView) -> String: return "(%d,%d)" % [view.position.x, view.position.y])
	return "%d cards at %s" % [spots.size(), " ".join(spots)]

func _last(client: GameClient) -> Dictionary:
	return client.chat_log.back() if not client.chat_log.is_empty() else {}


# The latest message with these words in a player's chat, or {} when there is none.
func _find(client: GameClient, text: String) -> Dictionary:
	for index in range(client.chat_log.size() - 1, -1, -1):
		if client.chat_log[index].get("text") == text:
			return client.chat_log[index]
	return {}


# The text of a line of the chat log, 0 being the top one.
func _row_text(index: int) -> String:
	var rows: Control = _node("ChatRows")
	if rows == null or index >= rows.get_child_count():
		return ""
	var row := rows.get_child(index)
	if row is RichTextLabel:
		return (row as RichTextLabel).get_parsed_text()
	return (row as Label).text if row is Label else ""


func _log_has(text: String) -> bool:
	var rows: Control = _node("ChatRows")
	for index in rows.get_child_count():
		if _row_text(index).contains(text):
			return true
	return false


func _rows() -> int:
	return (_node("ChatRows") as Control).get_child_count()


func _node(node_name: String) -> Variant:
	return _main.find_child(node_name, true, false)


func _has(node_name: String) -> bool:
	return _node(node_name) != null


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


func _card_spot(table: Variant, id: String) -> Vector2:
	for span: Dictionary in table._spans:
		var index: int = span.ids.find(id)
		if index >= 0:
			var left: float = span.xs[index]
			var shown_until: float = span.xs[index + 1] if index + 1 < span.xs.size() else span.right
			var view: CardView = table._cards[id]
			var hand: Control = _node("HandArea")
			return hand.get_global_transform_with_canvas() * Vector2((left + shown_until) / 2.0, view.position.y + view.size.y / 2.0)
	_check("the %s is in the hand" % id, false)
	return Vector2.ZERO


func _press(button_name: String) -> void:
	var button := _node(button_name) as Control
	if button == null or not button.is_visible_in_tree() or (button is BaseButton and (button as BaseButton).disabled):
		_check("%s can be pressed" % button_name, false)
		return
	await _press_button(button, button_name)


# Taps the middle of a control and checks that the tap reached it.
## `origin` is where the control's window sits, for buttons inside a message box.
func _press_button(control: Control, what: String, origin: Vector2 = Vector2.ZERO) -> void:
	if control == null:
		_check("%s is on screen" % what, false)
		return
	var answered := [false]
	var on_answer := func(_a: Variant = null) -> void: answered[0] = true
	# A button is pressed, a card tapped, a text field takes the focus; a line of the chat log
	# opens the choices about its player
	var answer := ""
	if control is BaseButton:
		answer = "pressed"
	elif control.has_signal("tapped"):
		answer = "tapped"
	elif control is LineEdit:
		answer = "focus_entered"
	if not answer.is_empty():
		control.connect(answer, on_answer)
	var at := origin + _middle(control)
	_tap(at)
	await get_tree().process_frame
	if answer.is_empty():
		answered[0] = (_node("ChatMenuShade") as Control).visible
	else:
		control.disconnect(answer, on_answer)
	_check("%s answers a finger" % what, answered[0], "touched %s; %s" % [at, _under_finger()])


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
