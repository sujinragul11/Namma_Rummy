class_name TableChat
extends Control
## Chat at the table. Two round buttons at the top right: one opens the chat panel (a line to
## type in, quick phrases, what has been said), the other a choice of emoji. A message pops up
## in a bubble beside the seat of whoever wrote it, an emoji right on their picture.
##
## Nothing here ever stands in the way of a move: this layer lets every tap through except the
## ones on its own buttons and panels, it never makes the game busy, and it waits for nothing.
## The table gives it `seat_of` to know where each player sits.

const BUTTON_SIZE := 52.0
const MARGIN := 14.0
const TOP := 10.0
const PANEL_WIDTH := 360.0  # clear of the open pile on a 1280-wide screen
## The chat panel ends above the table's action bar, so Discard, Declare and Drop can always
## be reached while it is open.
const ACTION_BAR_CLEAR := 88.0
const SLIDE_SECONDS := 0.2
const BUBBLE_SECONDS := 4.0
const BUBBLE_WIDTH := 260.0
const BUBBLE_TEXT := 70  # characters shown in a bubble; the whole message is in the panel
const REACTION_SIZE := 84.0
const REACTION_SECONDS := 1.6
const EMOJI_TILE := 76.0
const EMOJI_COLUMNS := 4
const PHRASES := ["Good luck!", "Well played!", "Nice move!", "Hurry up!", "Thanks!", "Oops!", "So close!", "Good game!"]
const PANEL_COLOR := Color(0.05, 0.19, 0.07, 0.94)
const TEXT_COLOR := Color(1, 1, 1, 0.92)
const DIM_TEXT := Color(1, 1, 1, 0.55)
const BUBBLE_INK := Color("263238")
const UNREAD_RED := Color("e53935")

## Where a player sits: takes a user id and returns the global rectangle of their badge, or an
## empty Rect2 when they have no seat on screen.
var seat_of := Callable()

var _buttons: HBoxContainer
var _chat_button: Button
var _emoji_button: Button
var _chat_panel: PanelContainer
var _emoji_panel: PanelContainer
var _switch: Button
var _input: LineEdit
var _rows: VBoxContainer
var _popups: Control  # bubbles and emoji, over everything else
var _chat_open := false
var _emoji_open := false
var _unread := 0
var _bubbles: Dictionary = {}  # user id -> the bubble beside their seat
var _reactions: Dictionary = {}  # user id -> the emoji on their picture
var _pictures: Dictionary = {}  # emoji name -> Texture2D
var _menu_shade: ColorRect  # dims the table while a choice about a player is open
var _menu: PanelContainer
var _press_at := Vector2.INF  # where the finger went down on a line of the log


func _ready() -> void:
	name = "TableChat"
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	for emoji_name: String in GameClient.EMOJIS:
		_pictures[emoji_name] = load("res://assets/emoji/%s.png" % emoji_name)

	_buttons = HBoxContainer.new()
	_buttons.name = "ChatButtons"
	_buttons.add_theme_constant_override("separation", 12)
	_buttons.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	_buttons.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_buttons.offset_right = -MARGIN
	_buttons.offset_left = -MARGIN
	_buttons.offset_top = TOP
	_buttons.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_buttons)
	_chat_button = _round_button("ChatButton", "Chat", _draw_chat_icon)
	_chat_button.pressed.connect(_toggle_chat)
	_emoji_button = _round_button("EmojiButton", "Emoji", _draw_emoji_icon)
	_emoji_button.pressed.connect(_toggle_emoji)

	_chat_panel = _build_chat_panel()
	add_child(_chat_panel)
	_emoji_panel = _build_emoji_panel()
	add_child(_emoji_panel)

	_popups = Control.new()
	_popups.name = "ChatPopups"
	_popups.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_popups.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_popups)
	_build_menu()

	Game.chat_received.connect(_on_chat_received)
	Game.chat_changed.connect(_rebuild_log)
	Game.chat_blocks_changed.connect(_on_blocks_changed)
	_rebuild_log()


## Closes the choice about a player if one is open, else whichever panel is open; the back
## button calls this.
func close() -> void:
	if _menu_shade.visible:
		_close_menu()
		return
	_show_chat(false)
	_show_emoji(false)


func is_chat_open() -> bool:
	return _chat_open


func is_emoji_open() -> bool:
	return _emoji_open


## Messages from the other players that came while the chat panel was closed.
func unread() -> int:
	return _unread


# ---------- building ----------

func _round_button(node_name: String, tip: String, draw_icon: Callable) -> Button:
	var button := Button.new()
	button.name = node_name
	button.tooltip_text = tip
	button.custom_minimum_size = Vector2(BUTTON_SIZE, BUTTON_SIZE)
	button.focus_mode = Control.FOCUS_NONE
	_light_button(button, false)
	button.draw.connect(draw_icon.bind(button))
	_buttons.add_child(button)
	return button


# Dark round buttons like the others at the top of the table; teal while their panel is open.
func _light_button(button: Button, lit: bool) -> void:
	for state_name: String in ["normal", "hover", "pressed"]:
		var round_box := StyleBoxFlat.new()
		if lit:
			round_box.bg_color = Ui.TEAL.lightened(0.1 if state_name == "hover" else 0.0)
		else:
			round_box.bg_color = Color(0, 0, 0, 0.5 if state_name == "hover" else 0.36)
		round_box.set_corner_radius_all(int(BUTTON_SIZE / 2.0))
		round_box.anti_aliasing = true
		button.add_theme_stylebox_override(state_name, round_box)


func _build_chat_panel() -> PanelContainer:
	var panel := PanelContainer.new()
	panel.name = "ChatPanel"
	panel.visible = false
	var style := Ui.box(PANEL_COLOR, 20, 16, 14)
	style.border_color = Ui.GOLD.darkened(0.3)
	style.set_border_width_all(2)
	style.shadow_color = Color(0, 0, 0, 0.35)
	style.shadow_size = 10
	panel.add_theme_stylebox_override("panel", style)
	panel.anchor_left = 1.0
	panel.anchor_right = 1.0
	panel.anchor_bottom = 1.0
	panel.offset_left = -(PANEL_WIDTH + MARGIN)
	panel.offset_right = -MARGIN
	panel.offset_top = TOP + BUTTON_SIZE + 10.0
	panel.offset_bottom = -ACTION_BAR_CLEAR

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	panel.add_child(column)

	# Title, the Chat switch, and a cross to close
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 12)
	column.add_child(header)
	var title := Label.new()
	title.text = "Chat"
	title.add_theme_font_override("font", Ui.bold_font)
	title.add_theme_font_size_override("font_size", 28)
	title.add_theme_color_override("font_color", Ui.GOLD)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	_switch = Button.new()
	_switch.name = "ChatSwitch"
	_switch.toggle_mode = true
	_switch.button_pressed = Config.chat_on
	_switch.focus_mode = Control.FOCUS_NONE
	_switch.tooltip_text = "Show what the other players write"
	_switch.custom_minimum_size = Vector2(96, 44)
	_switch.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	for state_name: String in ["normal", "hover", "pressed", "hover_pressed", "focus"]:
		_switch.add_theme_stylebox_override(state_name, StyleBoxEmpty.new())
	_switch.draw.connect(_draw_switch)
	_switch.toggled.connect(_on_switch)
	header.add_child(_switch)
	var cross := Button.new()
	cross.name = "ChatClose"
	cross.tooltip_text = "Close"
	cross.focus_mode = Control.FOCUS_NONE
	cross.custom_minimum_size = Vector2(44, 44)
	cross.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	for state_name: String in ["normal", "hover", "pressed"]:
		var round_box := Ui.box(Color(1, 1, 1, 0.16 if state_name == "hover" else 0.08), 22, 0, 0)
		cross.add_theme_stylebox_override(state_name, round_box)
	cross.draw.connect(_draw_cross.bind(cross))
	cross.pressed.connect(close)
	header.add_child(cross)

	# The line to type in sits high in the panel, where a phone's keyboard does not cover it
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 8)
	column.add_child(line)
	_input = LineEdit.new()
	_input.name = "ChatInput"
	_input.placeholder_text = "Type a message"
	_input.max_length = GameClient.CHAT_MAX_LENGTH
	_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_input.add_theme_font_size_override("font_size", 20)
	_input.text_submitted.connect(func(_text: String) -> void: _send_typed())
	line.add_child(_input)
	var send := Button.new()
	send.name = "SendButton"
	send.text = "Send"
	send.focus_mode = Control.FOCUS_NONE
	send.add_theme_font_size_override("font_size", 20)
	Ui.tint_button(send, Ui.TEAL)
	send.pressed.connect(_send_typed)
	line.add_child(send)

	# One tap says one of these
	var phrases := HFlowContainer.new()
	phrases.name = "Phrases"
	phrases.add_theme_constant_override("h_separation", 8)
	phrases.add_theme_constant_override("v_separation", 8)
	column.add_child(phrases)
	for index in PHRASES.size():
		var chip := Button.new()
		chip.name = "Phrase%d" % index
		chip.text = PHRASES[index]
		chip.focus_mode = Control.FOCUS_NONE
		chip.add_theme_font_size_override("font_size", 18)
		for state_name: String in ["normal", "hover", "pressed"]:
			var shade := {"normal": 0.12, "hover": 0.2, "pressed": 0.28}[state_name] as float
			var chip_box := Ui.box(Color(1, 1, 1, shade), 16, 12, 6)
			chip_box.border_color = Color(1, 1, 1, 0.18)
			chip_box.set_border_width_all(1)
			chip.add_theme_stylebox_override(state_name, chip_box)
		chip.pressed.connect(Game.send_chat.bind(PHRASES[index]))
		phrases.add_child(chip)

	# What has been said, the newest on top, right under the line it was typed in
	var scroll := ScrollContainer.new()
	scroll.name = "ChatScroll"
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	column.add_child(scroll)
	_rows = VBoxContainer.new()
	_rows.name = "ChatRows"
	_rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_rows.add_theme_constant_override("separation", 6)
	scroll.add_child(_rows)

	var hint := Label.new()
	hint.name = "ChatHint"
	hint.text = "Tap a message to report or block its sender."
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.add_theme_font_size_override("font_size", 15)
	hint.add_theme_color_override("font_color", DIM_TEXT)
	column.add_child(hint)
	return panel


func _build_emoji_panel() -> PanelContainer:
	var panel := PanelContainer.new()
	panel.name = "EmojiPanel"
	panel.visible = false
	var style := Ui.box(PANEL_COLOR, 20, 14, 14)
	style.border_color = Ui.GOLD.darkened(0.3)
	style.set_border_width_all(2)
	style.shadow_color = Color(0, 0, 0, 0.35)
	style.shadow_size = 10
	panel.add_theme_stylebox_override("panel", style)
	panel.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	panel.offset_left = -MARGIN
	panel.offset_right = -MARGIN
	panel.offset_top = TOP + BUTTON_SIZE + 10.0

	var grid := GridContainer.new()
	grid.columns = EMOJI_COLUMNS
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
	panel.add_child(grid)
	for emoji_name: String in GameClient.EMOJIS:
		var tile := Button.new()
		tile.name = "Emoji_" + emoji_name
		tile.tooltip_text = emoji_name.capitalize()
		tile.icon = _pictures[emoji_name]
		tile.expand_icon = true
		tile.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		tile.custom_minimum_size = Vector2(EMOJI_TILE, EMOJI_TILE)
		tile.focus_mode = Control.FOCUS_NONE
		for state_name: String in ["normal", "hover", "pressed"]:
			var shade := {"normal": 0.08, "hover": 0.16, "pressed": 0.24}[state_name] as float
			tile.add_theme_stylebox_override(state_name, Ui.box(Color(1, 1, 1, shade), 16, 8, 8))
		tile.pressed.connect(_send_emoji.bind(emoji_name))
		grid.add_child(tile)
	return panel


# ---------- opening and closing ----------

func _toggle_chat() -> void:
	_show_chat(not _chat_open)


func _toggle_emoji() -> void:
	_show_emoji(not _emoji_open)


func _show_chat(open: bool) -> void:
	if open == _chat_open:
		return
	_chat_open = open
	if open:
		_show_emoji(false)
		_unread = 0
		_chat_button.queue_redraw()
	else:
		_input.release_focus()  # and a phone puts its keyboard away
		_close_menu()
	_grow(_chat_panel, open)
	_light_button(_chat_button, open)
	_keep_back_button()


func _show_emoji(open: bool) -> void:
	if open == _emoji_open:
		return
	_emoji_open = open
	if open:
		_show_chat(false)
	_grow(_emoji_panel, open)
	_light_button(_emoji_button, open)
	_keep_back_button()


# A panel grows out of the buttons above it, and shrinks back into them.
func _grow(panel: Control, open: bool) -> void:
	if panel.has_meta("tween"):
		(panel.get_meta("tween") as Tween).kill()
	panel.visible = true
	panel.pivot_offset = Vector2(panel.size.x, 0.0)
	var tween := panel.create_tween().set_parallel()
	tween.tween_property(panel, "modulate:a", 1.0 if open else 0.0, SLIDE_SECONDS)
	tween.tween_property(panel, "scale", Vector2.ONE if open else Vector2(0.9, 0.9), SLIDE_SECONDS).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	if not open:
		tween.chain().tween_callback(panel.hide)
	panel.set_meta("tween", tween)
	if open and panel.modulate.a >= 1.0:
		panel.modulate.a = 0.0
		panel.scale = Vector2(0.9, 0.9)


# While a panel is open, the back button closes it instead of asking to leave the table.
func _keep_back_button() -> void:
	var open := _chat_open or _emoji_open
	if open and not is_in_group(FriendsPanel.BACK_GROUP):
		add_to_group(FriendsPanel.BACK_GROUP)
	elif not open and is_in_group(FriendsPanel.BACK_GROUP):
		remove_from_group(FriendsPanel.BACK_GROUP)


# ---------- sending ----------

func _send_typed() -> void:
	var text := _input.text.strip_edges()
	if text.is_empty():
		return
	Game.send_chat(text)
	_input.clear()


func _send_emoji(emoji_name: String) -> void:
	Game.send_emoji(emoji_name)
	_show_emoji(false)


func _on_switch(on: bool) -> void:
	Config.save_chat(on)
	_switch.queue_redraw()
	_rebuild_log()


# ---------- what comes in ----------

func _on_chat_received(message: Dictionary) -> void:
	var mine := str(message.get("userId", "")) == Game.player_id
	if message.get("kind") == "emoji":
		_show_reaction(message)
		Sound.play("sparkle", -4.0)
	elif mine or Config.chat_on:
		_show_bubble(message)
		if not mine:
			Sound.play("notice")
			if not _chat_open:
				_unread += 1
				_chat_button.queue_redraw()
				Ui.pulse(_chat_button, 1.18)
	else:
		return  # the Chat switch is off
	# The newest on top, under the lines about blocked players and the Chat switch
	var pinned := 0
	for row: Node in _rows.get_children():
		if row.has_meta("nothing_yet"):
			_rows.remove_child(row)
			row.queue_free()
		elif row.has_meta("pinned"):
			pinned += 1
	var row := _log_row(message)
	_rows.add_child(row)
	_rows.move_child(row, pinned)
	while _rows.get_child_count() > GameClient.CHAT_LOG_SIZE + 1:
		var oldest := _rows.get_child(_rows.get_child_count() - 1)
		_rows.remove_child(oldest)
		oldest.queue_free()


# Whoever was just blocked disappears from the log and from beside their seat at once.
func _on_blocks_changed() -> void:
	for entry: Dictionary in Game.chat_blocked:
		var user_id := str(entry.get("id", ""))
		_drop_popup(_bubbles, user_id)
		_drop_popup(_reactions, user_id)
	_rebuild_log()


func _rebuild_log() -> void:
	for row: Node in _rows.get_children():
		_rows.remove_child(row)
		row.queue_free()
	_close_menu()  # what it offered may have changed
	var blocked := _blocked_here()
	if not blocked.is_empty():
		var names := ", ".join(blocked.map(func(entry: Dictionary) -> String: return str(entry.get("username", "Player"))))
		var line := _note("You blocked %s. Tap here to unblock." % names)
		line.name = "BlockedNote"
		line.set_meta("pinned", true)
		_make_tappable(line, _open_unblock_menu.bind(blocked))
		_rows.add_child(line)
	if not Config.chat_on:
		var off := _note("Chat is off: what the other players write is hidden. Their emoji still show.")
		off.set_meta("pinned", true)
		_rows.add_child(off)
	var shown: Array = Game.chat_log.filter(func(message: Dictionary) -> bool:
		var from := str(message.get("userId", ""))
		if Game.is_chat_blocked(from):
			return false
		return message.get("kind") == "emoji" or from == Game.player_id or Config.chat_on)
	shown.reverse()
	for message: Dictionary in shown:
		_rows.add_child(_log_row(message))
	if Game.chat_log.is_empty():
		var nothing_yet := _note("Nothing said yet. Say hello to the table!")
		nothing_yet.set_meta("nothing_yet", true)
		_rows.add_child(nothing_yet)
	_unread = 0
	_chat_button.queue_redraw()


# One line of the chat: the name in the colour of the player's picture, then the words or emoji.
func _log_row(message: Dictionary) -> RichTextLabel:
	var row := RichTextLabel.new()
	row.fit_content = true
	row.scroll_active = false
	row.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE  # a finger on it scrolls the list
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.name = "ChatRow_%d" % int(message.get("id", 0))
	row.add_theme_font_size_override("normal_font_size", 20)
	row.add_theme_font_size_override("bold_font_size", 20)
	row.add_theme_font_override("bold_font", Ui.bold_font)
	row.add_theme_color_override("default_color", TEXT_COLOR)
	var username := str(message.get("username", "Player"))
	var mine := str(message.get("userId", "")) == Game.player_id
	row.push_bold()
	row.push_color(Ui.GOLD if mine else _name_color(username))
	row.add_text("You" if mine else username)
	row.pop()
	row.pop()
	row.add_text("  ")
	if message.get("kind") == "emoji":
		var picture: Texture2D = _pictures.get(str(message.get("emoji", "")))
		if picture != null:
			row.add_image(picture, 34, 34)
	else:
		row.add_text(str(message.get("text", "")))
	if not mine:
		# A tap on another player's line offers to report it or block them
		_make_tappable(row, _open_message_menu.bind(message))
	return row


# A line of the log that answers a tap, and still lets a finger slide over it to scroll.
func _make_tappable(line: Control, on_tap: Callable) -> void:
	line.mouse_filter = Control.MOUSE_FILTER_PASS
	line.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	line.gui_input.connect(_on_line_input.bind(line, on_tap))


# Acts when the finger lifts where it went down, as a button does; a slide scrolls instead.
func _on_line_input(event: InputEvent, line: Control, on_tap: Callable) -> void:
	var click := event as InputEventMouseButton
	if click == null or click.button_index != MOUSE_BUTTON_LEFT:
		return
	if click.pressed:
		_press_at = click.global_position
		return
	var still := _press_at.distance_to(click.global_position) < 14.0
	_press_at = Vector2.INF
	if still and Rect2(Vector2.ZERO, line.size).has_point(click.position):
		on_tap.call()


# The players at this table whom we blocked.
func _blocked_here() -> Array:
	var here := {}
	for player: Dictionary in Game.players():
		here[str(player.get("id", ""))] = true
	return Game.chat_blocked.filter(func(entry: Dictionary) -> bool: return here.has(str(entry.get("id", ""))))


func _note(text: String) -> Label:
	var note := Label.new()
	note.text = text
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.add_theme_font_size_override("font_size", 18)
	note.add_theme_color_override("font_color", DIM_TEXT)
	return note


# The colour the player's badge gives their picture, a little lighter to read on the dark panel.
func _name_color(username: String) -> Color:
	var colors := PlayerBadge.AVATAR_COLORS
	return colors[absi(hash(username)) % colors.size()].lightened(0.45)


# ---------- reporting and blocking ----------

func _build_menu() -> void:
	_menu_shade = ColorRect.new()
	_menu_shade.name = "ChatMenuShade"
	_menu_shade.color = Color(0, 0, 0, 0.4)
	_menu_shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_menu_shade.visible = false
	_menu_shade.gui_input.connect(_on_shade_input)
	add_child(_menu_shade)

	var middle := CenterContainer.new()
	middle.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	middle.mouse_filter = Control.MOUSE_FILTER_IGNORE  # a tap beside the choices reaches the shade
	_menu_shade.add_child(middle)
	_menu = PanelContainer.new()
	_menu.name = "ChatMenu"
	var style := Ui.box(PANEL_COLOR, 20, 22, 18)
	style.border_color = Ui.GOLD.darkened(0.3)
	style.set_border_width_all(2)
	_menu.add_theme_stylebox_override("panel", style)
	middle.add_child(_menu)
	var column := VBoxContainer.new()
	column.name = "Choices"
	column.custom_minimum_size.x = 400
	column.add_theme_constant_override("separation", 12)
	_menu.add_child(column)


# Opens a short list of choices: [label, colour, what it does, node name] for each.
func _open_menu(title: String, choices: Array) -> void:
	var column := _menu.get_node("Choices")
	for old: Node in column.get_children():
		column.remove_child(old)
		old.queue_free()
	var heading := Label.new()
	heading.text = title
	heading.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	heading.add_theme_font_size_override("font_size", 20)
	heading.add_theme_color_override("font_color", TEXT_COLOR)
	column.add_child(heading)
	for choice: Array in choices + [["Cancel", Ui.SLATE, Callable(), "MenuCancel"]]:
		var button := Button.new()
		button.name = choice[3]
		button.text = choice[0]
		button.focus_mode = Control.FOCUS_NONE
		Ui.tint_button(button, choice[1])
		var action: Callable = choice[2]
		button.pressed.connect(func() -> void:
			_close_menu()
			if action.is_valid():
				action.call())
		column.add_child(button)
	_menu_shade.visible = true
	# Grows in once the container has given it its place
	_menu.modulate.a = 0.0
	(func() -> void: Ui.pop_in(_menu)).call_deferred()


func _close_menu() -> void:
	if _menu_shade != null:
		_menu_shade.visible = false


# A tap on the dimmed table, outside the choices, closes them.
func _on_shade_input(event: InputEvent) -> void:
	var click := event as InputEventMouseButton
	if click != null and not click.pressed and click.button_index == MOUSE_BUTTON_LEFT:
		_close_menu()


func _open_message_menu(message: Dictionary) -> void:
	var username := str(message.get("username", "Player"))
	var user_id := str(message.get("userId", ""))
	var words := "an emoji" if message.get("kind") == "emoji" else "“%s”" % str(message.get("text", ""))
	_open_menu("%s wrote %s" % [username, words], [
		["Report message", Ui.ORANGE, _ask_report.bind(message), "ReportButton"],
		["Block %s" % username, Ui.RED, Game.block_chat_player.bind(user_id, username, true), "BlockButton"],
	])


func _ask_report(message: Dictionary) -> void:
	var username := str(message.get("username", "Player"))
	var words := "an emoji" if message.get("kind") == "emoji" else "“%s”" % str(message.get("text", ""))
	Ui.confirm("Report message",
		"Report this message from %s to the Namma Rummy team?\n\n%s\n\n%s will also be blocked: you will not see what they write or send any more." % [username, words, username],
		"Report", Game.report_chat.bind(message))


func _open_unblock_menu(blocked: Array) -> void:
	var choices: Array = []
	for entry: Dictionary in blocked:
		var username := str(entry.get("username", "Player"))
		var user_id := str(entry.get("id", ""))
		choices.append(["Unblock %s" % username, Ui.TEAL, Game.block_chat_player.bind(user_id, username, false), "Unblock_" + user_id])
	_open_menu("Players at this table you blocked. Unblock one to see their messages again.", choices)


# ---------- beside the seats ----------

# The seat of a player in this layer's own coordinates; empty when they have none on screen.
func _seat(user_id: String) -> Rect2:
	if not seat_of.is_valid():
		return Rect2()
	var seat: Rect2 = seat_of.call(user_id)
	if not seat.has_area():
		return Rect2()
	return Rect2(seat.position - _popups.get_global_rect().position, seat.size)


# What a player wrote, in a speech bubble beside their seat for a few seconds.
func _show_bubble(message: Dictionary) -> void:
	var user_id := str(message.get("userId", ""))
	var seat := _seat(user_id)
	if not seat.has_area():
		return
	_drop_popup(_bubbles, user_id)

	var text := str(message.get("text", ""))
	if text.length() > BUBBLE_TEXT:
		text = text.left(BUBBLE_TEXT - 1).strip_edges() + "…"
	var bubble := PanelContainer.new()
	bubble.name = "Bubble_" + user_id
	bubble.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := Ui.box(Color.WHITE, 16, 14, 8)
	style.shadow_color = Color(0, 0, 0, 0.3)
	style.shadow_size = 6
	style.shadow_offset = Vector2(0, 2)
	bubble.add_theme_stylebox_override("panel", style)
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", 20)
	label.add_theme_color_override("font_color", BUBBLE_INK)
	var font := label.get_theme_font("font")
	var width := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 20).x + 4.0
	label.custom_minimum_size.x = clampf(width, 24.0, BUBBLE_WIDTH)
	bubble.add_child(label)
	_popups.add_child(bubble)
	bubble.size = bubble.get_combined_minimum_size()

	# Above our own seat at the bottom. Beside the others: to the right, else to the left, else
	# below, whichever is on the screen and clear of the open panels and the buttons.
	var size := bubble.size
	var ours := seat.get_center().y > _popups.size.y * 0.6
	var middle_y := seat.get_center().y - size.y / 2.0
	var spots: Array[Vector2] = []
	if ours:
		spots.append(Vector2(seat.position.x, seat.position.y - size.y - 14.0))
	else:
		# Beside the badge and the round button that may stand next to it (things to throw)
		var beside := seat
		var button := _seat_button(user_id)
		if button != null:
			var rect := button.get_global_rect()
			beside = beside.merge(Rect2(rect.position - _popups.get_global_rect().position, rect.size))
		spots.append(Vector2(beside.end.x + 16.0, middle_y))
		spots.append(Vector2(beside.position.x - 16.0 - size.x, middle_y))
		spots.append(Vector2(beside.get_center().x - size.x / 2.0, beside.end.y + 14.0))
	var screen := Rect2(Vector2.ZERO, _popups.size).grow(-8.0)
	var at := spots[0].clamp(screen.position, (screen.end - size).max(screen.position))
	for spot: Vector2 in spots:
		if screen.encloses(Rect2(spot, size)) and not _in_the_way(Rect2(spot, size)):
			at = spot
			break
	bubble.position = at
	# The point of the bubble touches the player's picture, at the left end of the badge
	var target := Vector2(seat.position.x + minf(seat.size.y, seat.size.x) / 2.0, seat.get_center().y)
	if ours:
		target.y = seat.position.y
	var tail := target - at  # where the point touches, in the bubble's own coordinates
	bubble.draw.connect(_draw_tail.bind(bubble, tail))
	_bubbles[user_id] = bubble

	bubble.pivot_offset = tail.clamp(Vector2.ZERO, bubble.size)
	bubble.scale = Vector2(0.6, 0.6)
	bubble.modulate.a = 0.0
	var tween := bubble.create_tween()
	tween.tween_property(bubble, "modulate:a", 1.0, 0.12)
	tween.parallel().tween_property(bubble, "scale", Vector2.ONE, 0.28).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_interval(BUBBLE_SECONDS)
	tween.tween_property(bubble, "modulate:a", 0.0, 0.35)
	tween.tween_callback(_drop_popup.bind(_bubbles, user_id, bubble))


# The round button the throwing layer (TableThrows) puts beside a player's badge, if any.
func _seat_button(user_id: String) -> Control:
	var throws := get_parent().get_node_or_null("TableThrows") if get_parent() != null else null
	if throws == null:
		return null
	var button := throws.find_child("ThrowButton_" + user_id, true, false) as Control
	return button if button != null and button.is_visible_in_tree() else null


# Whether a bubble there would lie over an open panel or the chat buttons.
func _in_the_way(box: Rect2) -> bool:
	var origin := _popups.get_global_rect().position
	var taken: Array[Control] = [_buttons]
	if _chat_open:
		taken.append(_chat_panel)
	if _emoji_open:
		taken.append(_emoji_panel)
	for control: Control in taken:
		var rect := control.get_global_rect()
		if box.intersects(Rect2(rect.position - origin, rect.size)):
			return true
	return false


# An emoji jumps out of the player's picture, hangs there a moment and floats away.
func _show_reaction(message: Dictionary) -> void:
	var user_id := str(message.get("userId", ""))
	var picture: Texture2D = _pictures.get(str(message.get("emoji", "")))
	var seat := _seat(user_id)
	if picture == null or not seat.has_area():
		return
	_drop_popup(_reactions, user_id)

	var emoji := TextureRect.new()
	emoji.name = "Reaction_" + user_id
	emoji.texture = picture
	emoji.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	emoji.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	emoji.mouse_filter = Control.MOUSE_FILTER_IGNORE
	emoji.size = Vector2(REACTION_SIZE, REACTION_SIZE)
	emoji.pivot_offset = emoji.size / 2.0
	# The picture is the left end of a badge, as tall as the badge
	var center := Vector2(seat.position.x + minf(seat.size.y, seat.size.x) / 2.0, seat.get_center().y)
	var rest := (center - emoji.size / 2.0 - Vector2(0.0, seat.size.y * 0.55))
	rest = rest.clamp(Vector2(4, 4), (_popups.size - emoji.size - Vector2(4, 4)).max(Vector2(4, 4)))
	emoji.position = center - emoji.size / 2.0
	emoji.scale = Vector2(0.2, 0.2)
	_popups.add_child(emoji)
	_reactions[user_id] = emoji
	Fx.sparkle(_popups.get_global_rect().position + rest + emoji.size / 2.0, Ui.GOLD, 10)

	var tween := emoji.create_tween()
	tween.tween_property(emoji, "position", rest, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.parallel().tween_property(emoji, "scale", Vector2(1.2, 1.2), 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(emoji, "scale", Vector2.ONE, 0.15)
	tween.tween_property(emoji, "rotation", 0.12, 0.2).set_trans(Tween.TRANS_SINE)
	tween.tween_property(emoji, "rotation", -0.12, 0.4).set_trans(Tween.TRANS_SINE)
	tween.tween_property(emoji, "rotation", 0.0, 0.2).set_trans(Tween.TRANS_SINE)
	tween.tween_interval(REACTION_SECONDS - 0.8)
	tween.tween_property(emoji, "position:y", rest.y - 50.0, 0.6).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	tween.parallel().tween_property(emoji, "modulate:a", 0.0, 0.6)
	tween.tween_callback(_drop_popup.bind(_reactions, user_id, emoji))


# Takes a bubble or emoji off the screen: the one given, or whatever the player has up there.
func _drop_popup(shown: Dictionary, user_id: String, only: Node = null) -> void:
	var popup: Node = shown.get(user_id)
	if popup == null or (only != null and popup != only):
		popup = only  # already replaced by a newer one, which stays
	else:
		shown.erase(user_id)
	# Out of the way at once, so the next one can take its place (and its name) straight away
	if popup != null and is_instance_valid(popup):
		if popup.get_parent() != null:
			popup.get_parent().remove_child(popup)
		popup.queue_free()


# ---------- drawing ----------

# A speech bubble with three dots, and a red count of unread messages in the corner.
func _draw_chat_icon(button: Button) -> void:
	var middle := button.size / 2.0
	var body := Rect2(middle + Vector2(-14, -12), Vector2(28, 20))
	var outline := PackedVector2Array()
	var radius := 6.0
	for corner in 4:
		var center := [body.position + Vector2(radius, radius), Vector2(body.end.x - radius, body.position.y + radius), body.end - Vector2(radius, radius), Vector2(body.position.x + radius, body.end.y - radius)][corner] as Vector2
		for step in 5:
			var angle := PI + corner * PI / 2.0 + step * PI / 8.0
			outline.append(center + Vector2.from_angle(angle) * radius)
	outline.append(outline[0])
	button.draw_colored_polygon(outline, Color.WHITE)
	button.draw_colored_polygon(PackedVector2Array([middle + Vector2(-8, 6), middle + Vector2(-1, 6), middle + Vector2(-10, 15)]), Color.WHITE)
	for dot in 3:
		button.draw_circle(middle + Vector2(-7 + dot * 7, -2), 2.4, Color("37474f"), true, -1.0, true)
	if _unread > 0:
		var spot := Vector2(button.size.x - 7, 7)
		button.draw_circle(spot, 11.0, UNREAD_RED, true, -1.0, true)
		button.draw_arc(spot, 11.0, 0.0, TAU, 24, Color.WHITE, 2.0, true)
		var count := str(_unread) if _unread < 10 else "9+"
		var font := Ui.bold_font
		var text_size := font.get_string_size(count, HORIZONTAL_ALIGNMENT_LEFT, -1, 15)
		button.draw_string(font, spot + Vector2(-text_size.x / 2.0, 5.5), count, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color.WHITE)


# A smiling face.
func _draw_emoji_icon(button: Button) -> void:
	var middle := button.size / 2.0
	button.draw_circle(middle, 15.0, Ui.GOLD, true, -1.0, true)
	var ink := Color("5d4037")
	button.draw_circle(middle + Vector2(-5.5, -4), 2.4, ink, true, -1.0, true)
	button.draw_circle(middle + Vector2(5.5, -4), 2.4, ink, true, -1.0, true)
	button.draw_arc(middle + Vector2(0, 1), 8.0, 0.2, PI - 0.2, 12, ink, 2.6, true)


func _draw_cross(button: Button) -> void:
	var middle := button.size / 2.0
	button.draw_line(middle + Vector2(-8, -8), middle + Vector2(8, 8), Color.WHITE, 3.0, true)
	button.draw_line(middle + Vector2(8, -8), middle + Vector2(-8, 8), Color.WHITE, 3.0, true)


# A switch drawn in code: ON in green with the knob at the right, OFF grey with it at the left.
func _draw_switch() -> void:
	var on := _switch.button_pressed
	var track := Rect2(Vector2(0, (_switch.size.y - 34.0) / 2.0), Vector2(_switch.size.x, 34.0))
	var style := Ui.box(Ui.PRIMARY if on else Color("78909c"), 17, 0, 0)
	_switch.draw_style_box(style, track)
	var knob := Vector2(track.end.x - 17.0 if on else track.position.x + 17.0, track.get_center().y)
	_switch.draw_circle(knob, 13.0, Color.WHITE, true, -1.0, true)
	var word := "ON" if on else "OFF"
	var font := Ui.bold_font
	var word_size := font.get_string_size(word, HORIZONTAL_ALIGNMENT_LEFT, -1, 16)
	var word_x := track.position.x + 12.0 if on else track.end.x - 12.0 - word_size.x
	_switch.draw_string(font, Vector2(word_x, track.get_center().y + 6.0), word, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color.WHITE)


# The bubble's point, towards the seat it belongs to.
func _draw_tail(bubble: Control, tail: Vector2) -> void:
	var box := Rect2(Vector2.ZERO, bubble.size)
	var base := tail.clamp(box.position + Vector2(18, 10), box.end - Vector2(18, 10))
	var across: Vector2
	if tail.y >= box.end.y:
		base.y = box.end.y - 1.0
		across = Vector2(9, 0)
	elif tail.y <= 0.0:
		base.y = 1.0
		across = Vector2(9, 0)
	elif tail.x <= 0.0:
		base.x = 1.0
		across = Vector2(0, 9)
	elif tail.x >= box.end.x:
		base.x = box.end.x - 1.0
		across = Vector2(0, 9)
	else:
		return  # the seat is behind the bubble itself
	var tip := base + (tail - base).limit_length(16.0)
	bubble.draw_colored_polygon(PackedVector2Array([base - across, tip, base + across]), Color.WHITE)
