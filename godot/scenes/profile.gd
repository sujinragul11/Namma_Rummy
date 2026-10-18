class_name ProfilePanel
extends MenuOverlay
## The player's own account, over the home screen, in the look of the game's other boxes: a
## cream box in a teal frame with "Profile" on its banner. On the left the photo (tap EDIT or
## Change Photo to pick another), the username in a pill (the pencil edits it) and the coins;
## on the right the statistics: games played and won, the share won and the friends. Under
## them the mobile number, the month the player started, and Delete account.
##
## The numbers come from the server each time the panel opens (`Game.fetch_profile`).
## Built in code. `show_over(screen)` opens it; it is freed when it closes.

const SUNKEN := Color("e8dcc5")  # the two inner panels
const ROW := Color("fff4dc")
const ROW_EDGE := Color("dcc296")
const VALUE := Color("f7d478")
const VALUE_EDGE := Color("d6a842")
const INK := Color("5d3b1e")  # brown writing on the cream
const DIM := Color("8d7b6a")
const PILL := Color(0.32, 0.3, 0.28, 0.6)
const YELLOW := Color("f8cf45")
const YELLOW_EDGE := Color("cf9616")
const GLOW := Color("ff8a3d")
const FRAME_DARK := Color("2b2824")
const AVATAR := 156.0
const ROUND_BUTTON := 42.0
const MONTHS := ["January", "February", "March", "April", "May", "June", "July", "August", "September", "October", "November", "December"]

var _fields_filled := false  # the name takes the account's value once, then belongs to the player
var _avatar: Control
var _name_edit: LineEdit
var _edit_button: Button
var _save_button: Button
var _coins_value: Label
var _played_value: Label
var _won_value: Label
var _rate_value: Label
var _friends_value: Label
var _account_label: Label
var _delete_button: Button
var _keyboard_height := 0


## Opens the profile over `screen`, unless another panel is open already.
static func show_over(screen: Control) -> void:
	if screen.get_tree().get_first_node_in_group(FriendsPanel.BACK_GROUP) != null:
		return
	var panel := ProfilePanel.new()
	screen.add_child(panel)
	panel.open()


func _init() -> void:
	name = "ProfilePanel"
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP

	var shade := ColorRect.new()
	shade.name = "Shade"
	shade.color = Color(0, 0, 0, 0.72)
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(shade)

	var box := PanelContainer.new()
	box.name = "Box"
	box.anchor_left = 0.5
	box.anchor_right = 0.5
	box.anchor_top = 0.5
	box.anchor_bottom = 0.5
	box.offset_left = -480.0
	box.offset_right = 480.0
	box.grow_horizontal = Control.GROW_DIRECTION_BOTH
	box.grow_vertical = Control.GROW_DIRECTION_BOTH
	add_child(box)

	var column := VBoxContainer.new()
	column.name = "ProfileColumn"
	column.add_theme_constant_override("separation", 8)
	box.add_child(column)

	# The header row MenuOverlay dresses: "Profile" on a banner, a tag to close
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 0)
	var left := Control.new()
	left.custom_minimum_size = Vector2(56, 0)
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(left)
	var title := Label.new()
	title.name = "Title"
	title.text = "Profile"
	header.add_child(title)
	var right := Control.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(right)
	var close_button := Button.new()
	close_button.name = "CloseButton"
	close_button.pressed.connect(close)
	header.add_child(close_button)
	column.add_child(header)

	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", 20)
	column.add_child(columns)
	columns.add_child(_build_player_side())
	columns.add_child(_build_statistics())


# The left panel: photo, name, coins and the yellow button.
func _build_player_side() -> Control:
	var side := PanelContainer.new()
	side.name = "PlayerSide"
	side.custom_minimum_size = Vector2(300, 0)
	side.add_theme_stylebox_override("panel", Ui.box(SUNKEN, 12, 18, 18))
	var stack := VBoxContainer.new()
	stack.alignment = BoxContainer.ALIGNMENT_CENTER
	stack.add_theme_constant_override("separation", 14)
	side.add_child(stack)

	_avatar = Control.new()
	_avatar.name = "ProfileAvatar"
	_avatar.custom_minimum_size = Vector2(AVATAR, AVATAR)
	_avatar.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_avatar.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_avatar.tooltip_text = "Change your photo"
	_avatar.draw.connect(_draw_avatar)
	_avatar.gui_input.connect(_on_avatar_input)
	stack.add_child(_avatar)

	# The name: a dark pill; the pencil edits it, the tick saves it
	var name_pill := PanelContainer.new()
	name_pill.name = "NamePill"
	name_pill.add_theme_stylebox_override("panel", Ui.box(PILL, 24, 16, 3))
	var name_row := HBoxContainer.new()
	name_row.add_theme_constant_override("separation", 6)
	name_pill.add_child(name_row)
	_name_edit = LineEdit.new()
	_name_edit.name = "ProfileNameEdit"
	_name_edit.placeholder_text = "Username"
	_name_edit.max_length = 20
	_name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_name_edit.add_theme_font_size_override("font_size", 22)
	_name_edit.add_theme_color_override("font_color", Color.WHITE)
	_name_edit.add_theme_color_override("font_placeholder_color", Color(1, 1, 1, 0.5))
	_name_edit.add_theme_color_override("caret_color", Color.WHITE)
	for state_name: String in ["normal", "focus", "read_only"]:
		var flat := StyleBoxFlat.new()
		flat.bg_color = Color(1, 1, 1, 0.12) if state_name == "focus" else Color.TRANSPARENT
		flat.set_corner_radius_all(8)
		flat.content_margin_left = 4
		flat.content_margin_right = 4
		_name_edit.add_theme_stylebox_override(state_name, flat)
	name_row.add_child(_name_edit)
	_edit_button = _round_button("EditNameButton", Color("e7e2da"), _draw_pencil)
	_edit_button.tooltip_text = "Change your username"
	name_row.add_child(_edit_button)
	_save_button = _round_button("SaveProfileButton", Color("43a047"), _draw_tick)
	_save_button.tooltip_text = "Save the new username"
	name_row.add_child(_save_button)
	stack.add_child(name_pill)

	# The coins: a gold coin at the left end of a dark pill
	var coins_pill := PanelContainer.new()
	coins_pill.name = "CoinsPill"
	coins_pill.add_theme_stylebox_override("panel", Ui.box(PILL, 24, 10, 3))
	var coins_row := HBoxContainer.new()
	coins_row.add_theme_constant_override("separation", 10)
	coins_pill.add_child(coins_row)
	var coin := Control.new()
	coin.custom_minimum_size = Vector2(44, 44)
	coin.draw.connect(_draw_coin.bind(coin))
	coins_row.add_child(coin)
	_coins_value = Label.new()
	_coins_value.name = "CoinsValue"
	_coins_value.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_coins_value.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_coins_value.add_theme_font_size_override("font_size", 24)
	_coins_value.add_theme_color_override("font_color", Color.WHITE)
	coins_row.add_child(_coins_value)
	stack.add_child(coins_pill)

	var photo_button := Button.new()
	photo_button.name = "ChangePhotoButton"
	photo_button.text = "CHANGE PHOTO"
	photo_button.custom_minimum_size = Vector2(220, 58)
	photo_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	photo_button.focus_mode = Control.FOCUS_NONE
	photo_button.add_theme_font_size_override("font_size", 21)
	for state_name: String in ["normal", "hover", "pressed", "disabled"]:
		var yellow := Ui.box(YELLOW.lightened(0.08) if state_name == "hover" else YELLOW, 29, 24, 6)
		yellow.border_color = YELLOW_EDGE
		yellow.border_width_bottom = 2 if state_name == "pressed" else 5
		yellow.shadow_color = Color(0, 0, 0, 0.18)
		yellow.shadow_size = 3
		yellow.shadow_offset = Vector2(0, 2)
		photo_button.add_theme_stylebox_override(state_name, yellow)
	for color_name: String in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		photo_button.add_theme_color_override(color_name, INK)
	photo_button.pressed.connect(_open_photo_box)
	stack.add_child(photo_button)
	return side


# The right side: STATISTICS over four rows, then the account line and Delete account.
func _build_statistics() -> Control:
	var side := VBoxContainer.new()
	side.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	side.add_theme_constant_override("separation", 10)

	var heading := Label.new()
	heading.name = "StatsTitle"
	heading.text = "STATISTICS"
	heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	heading.add_theme_font_size_override("font_size", 34)
	heading.add_theme_color_override("font_color", DIM)
	heading.add_theme_color_override("font_shadow_color", Color(1, 1, 1, 0.9))
	heading.add_theme_constant_override("shadow_offset_x", 0)
	heading.add_theme_constant_override("shadow_offset_y", 2)
	side.add_child(heading)

	var stats := PanelContainer.new()
	stats.name = "StatsRow"
	stats.add_theme_stylebox_override("panel", Ui.box(SUNKEN, 10, 12, 12))
	var rows := VBoxContainer.new()
	rows.add_theme_constant_override("separation", 10)
	stats.add_child(rows)
	_played_value = _stat_row(rows, "GAMES PLAYED", "PlayedValue")
	_won_value = _stat_row(rows, "GAMES WON", "WonValue")
	_rate_value = _stat_row(rows, "WON RATIO", "RateValue")
	_friends_value = _stat_row(rows, "FRIENDS", "FriendsValue")
	side.add_child(stats)

	_account_label = Label.new()
	_account_label.name = "AccountLabel"
	_account_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_account_label.add_theme_font_size_override("font_size", 18)
	_account_label.add_theme_color_override("font_color", DIM)
	side.add_child(_account_label)

	var foot := HBoxContainer.new()
	foot.add_theme_constant_override("separation", 12)
	_delete_button = Button.new()
	_delete_button.name = "DeleteAccountButton"
	_delete_button.text = "Delete account"
	_delete_button.flat = true
	_delete_button.focus_mode = Control.FOCUS_NONE
	_delete_button.add_theme_font_size_override("font_size", 18)
	for color_name: String in ["font_color", "font_hover_color", "font_pressed_color"]:
		_delete_button.add_theme_color_override(color_name, Color("c62828"))
	_delete_button.pressed.connect(_on_delete_account)
	foot.add_child(_delete_button)
	var gap := Control.new()
	gap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	foot.add_child(gap)
	# The founder's credit: small, with the letters a little spaced out
	var founder := Label.new()
	founder.name = "FounderLabel"
	founder.text = "Founder : Sujin Ragul"
	founder.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var credit := FontVariation.new()
	credit.base_font = ThemeDB.fallback_font
	credit.spacing_glyph = 1
	founder.add_theme_font_override("font", credit)
	founder.add_theme_font_size_override("font_size", 15)
	founder.add_theme_color_override("font_color", Color(DIM, 0.8))
	foot.add_child(founder)
	side.add_child(foot)
	return side


# One row of the statistics: the name on a cream bar, the number on a yellow one beside it.
func _stat_row(rows: VBoxContainer, caption: String, value_name: String) -> Label:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 0)
	var name_bar := PanelContainer.new()
	name_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var name_style := Ui.box(ROW, 6, 24, 9)
	name_style.corner_radius_top_right = 0
	name_style.corner_radius_bottom_right = 0
	name_style.border_color = ROW_EDGE
	name_style.border_width_bottom = 4
	name_bar.add_theme_stylebox_override("panel", name_style)
	var label := Label.new()
	label.text = caption
	label.add_theme_font_size_override("font_size", 22)
	label.add_theme_color_override("font_color", INK)
	name_bar.add_child(label)
	row.add_child(name_bar)

	var value_bar := PanelContainer.new()
	value_bar.custom_minimum_size = Vector2(150, 0)
	var value_style := Ui.box(VALUE, 6, 20, 9)
	value_style.corner_radius_top_left = 0
	value_style.corner_radius_bottom_left = 0
	value_style.border_color = VALUE_EDGE
	value_style.border_width_bottom = 4
	value_bar.add_theme_stylebox_override("panel", value_style)
	var value := Label.new()
	value.name = value_name
	value.text = "-"
	value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	value.add_theme_font_size_override("font_size", 28)
	value.add_theme_color_override("font_color", INK)
	value_bar.add_child(value)
	row.add_child(value_bar)
	rows.add_child(row)
	return value


func _round_button(node_name: String, color: Color, picture: Callable) -> Button:
	var button := Button.new()
	button.name = node_name
	button.custom_minimum_size = Vector2(ROUND_BUTTON, ROUND_BUTTON)
	button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	button.focus_mode = Control.FOCUS_NONE
	for state_name: String in ["normal", "hover", "pressed", "disabled"]:
		var round_box := Ui.box(color.darkened(0.08) if state_name == "pressed" else color, int(ROUND_BUTTON / 2.0), 0, 0)
		round_box.border_color = Color(0, 0, 0, 0.25)
		round_box.set_border_width_all(1)
		if state_name == "disabled":
			round_box.bg_color = color.lerp(Color.GRAY, 0.6)
		button.add_theme_stylebox_override(state_name, round_box)
	button.draw.connect(picture.bind(button))
	return button


func _ready() -> void:
	super._ready()  # the frame, the banner and the tag
	for value: Label in [_coins_value, _played_value, _won_value, _rate_value, _friends_value]:
		value.add_theme_font_override("font", Ui.bold_font)
	for node: Control in [find_child("StatsTitle", true, false), _name_edit, find_child("ChangePhotoButton", true, false)]:
		node.add_theme_font_override("font", Ui.bold_font)
	for row_label: Node in find_child("StatsRow", true, false).find_children("*", "Label", true, false):
		if not row_label.name.ends_with("Value"):
			(row_label as Label).add_theme_font_override("font", Ui.bold_font)

	_name_edit.text_changed.connect(_refresh.unbind(1))
	_name_edit.text_submitted.connect(_on_save.unbind(1))
	_edit_button.pressed.connect(_start_editing)
	_save_button.pressed.connect(_on_save)
	Game.profile_changed.connect(_refresh)
	Game.coins_changed.connect(_refresh)
	Game.busy_changed.connect(_refresh)
	Game.connection_changed.connect(_refresh)
	Game.friends_changed.connect(_refresh)
	Game.avatar_loaded.connect(_on_avatar_loaded)
	_refresh()
	Game.fetch_profile()


func close() -> void:
	super.close()
	queue_free()


func _process(_delta: float) -> void:
	if DisplayServer.has_feature(DisplayServer.FEATURE_VIRTUAL_KEYBOARD):
		make_room_for_keyboard(DisplayServer.virtual_keyboard_get_height())


## Lifts the box while the on-screen keyboard is up, so the name being typed stays above it.
## `height` is in window pixels, as the system reports it.
func make_room_for_keyboard(height: int) -> void:
	if height == _keyboard_height:
		return
	_keyboard_height = height
	_box.position.y = _resting_top()
	if height <= 0:
		return
	var units := get_viewport().get_visible_rect().size.y / float(maxi(1, DisplayServer.window_get_size().y))
	var visible_bottom := size.y - height * units
	var field_bottom := _name_edit.get_global_rect().end.y - global_position.y
	var lift := field_bottom + 16.0 - visible_bottom
	if lift > 0.0:
		_box.position.y -= lift


# Where the box sits without a keyboard: in the middle of the screen.
func _resting_top() -> float:
	return (size.y - _box.size.y) / 2.0


func _refresh() -> void:
	var known := Game.profile
	var username := str(Game.user.get("username", ""))

	# The name is filled in once the server has answered
	if not _fields_filled and not known.is_empty():
		_fields_filled = true
		_name_edit.text = username

	var played := int(known.get("totalGames", 0))
	var won := int(known.get("gamesWon", 0))
	_played_value.text = str(played) if not known.is_empty() else "-"
	_won_value.text = str(won) if not known.is_empty() else "-"
	_rate_value.text = "%d %%" % roundi(float(known.get("winPercentage", 0.0))) if played > 0 else "-"
	_friends_value.text = str(Game.friends.size())
	_coins_value.text = Ui.coins_text(Game.coins)

	var details: Array = []
	if not str(known.get("phone", "")).is_empty():
		details.append("Mobile %s" % AccountRules.display_phone(str(known.get("phone"))))
	var since := _month_of(str(known.get("created_at", "")))
	if not since.is_empty():
		details.append("Playing since %s" % since)
	_account_label.text = "  ·  ".join(details)
	_avatar.queue_redraw()

	# The pencil while the name is as saved; the tick once it has been changed
	var changed := _name_edit.text.strip_edges() != username
	_edit_button.visible = not changed
	_save_button.visible = changed
	_save_button.disabled = not _fields_filled or Game.busy or not Game.is_online()


func _start_editing() -> void:
	_name_edit.grab_focus()
	_name_edit.select_all()


func _on_save() -> void:
	if not _save_button.visible or _save_button.disabled:
		return
	var username := _name_edit.text.strip_edges()
	if username.is_empty():
		Ui.alert("Enter a username.", "Profile")
		return
	_name_edit.release_focus()
	Game.update_profile(username)


# A tap on the photo opens the photo box, on the finger's release (as every tap in the game).
func _on_avatar_input(event: InputEvent) -> void:
	var click := event as InputEventMouseButton
	if click == null or click.pressed or click.button_index != MOUSE_BUTTON_LEFT:
		return
	if Rect2(Vector2.ZERO, _avatar.size).has_point(click.position):  # the finger did not slide away
		_open_photo_box()


# The photo is chosen in a box of its own over the profile, with the same editor as Settings.
func _open_photo_box() -> void:
	if find_child("PhotoBox", true, false) != null:
		return
	var photo_box := MenuOverlay.new()
	photo_box.name = "PhotoBox"
	photo_box.set_anchors_preset(Control.PRESET_FULL_RECT)
	photo_box.mouse_filter = Control.MOUSE_FILTER_STOP
	var shade := ColorRect.new()
	shade.name = "Shade"
	shade.color = Color(0, 0, 0, 0.5)
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	photo_box.add_child(shade)
	var box := PanelContainer.new()
	box.name = "Box"
	box.anchor_left = 0.5
	box.anchor_right = 0.5
	box.anchor_top = 0.5
	box.anchor_bottom = 0.5
	box.offset_left = -300.0
	box.offset_right = 300.0
	box.grow_horizontal = Control.GROW_DIRECTION_BOTH
	box.grow_vertical = Control.GROW_DIRECTION_BOTH
	photo_box.add_child(box)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 12)
	box.add_child(column)
	var header := HBoxContainer.new()
	var left := Control.new()
	left.custom_minimum_size = Vector2(56, 0)
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(left)
	var title := Label.new()
	title.text = "Photo"
	header.add_child(title)
	var right := Control.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(right)
	var close_button := Button.new()
	close_button.name = "PhotoCloseButton"
	close_button.pressed.connect(photo_box.close)
	header.add_child(close_button)
	column.add_child(header)
	column.add_child(AvatarEditor.new())
	photo_box.closed.connect(photo_box.queue_free)
	add_child(photo_box)
	photo_box.open()


func _on_avatar_loaded(user_id: String) -> void:
	if user_id == Game.player_id:
		_avatar.queue_redraw()


# The photo in a dark frame with EDIT along its foot, on a warm glow.
func _draw_avatar() -> void:
	var whole := Rect2(Vector2.ZERO, _avatar.size)
	var center := whole.get_center()
	for layer in 7:
		_avatar.draw_circle(center, AVATAR * 0.5 + 4.0 + layer * 7.0, Color(GLOW, 0.13 - layer * 0.016), true, -1.0, true)
	var frame := Ui.box(FRAME_DARK, 14, 0, 0)
	frame.border_color = Color("16140f")
	frame.set_border_width_all(2)
	frame.shadow_color = Color(0, 0, 0, 0.35)
	frame.shadow_size = 6
	frame.shadow_offset = Vector2(0, 3)
	_avatar.draw_style_box(frame, whole)

	var inner := whole.grow(-7.0)
	var photo := Game.avatar_texture(Game.player_id, Game.my_avatar())
	if photo != null:
		_avatar.draw_texture_rect(photo, inner, false)
	else:
		var username := str(Game.user.get("username", ""))
		_avatar.draw_rect(inner, PlayerBadge.AVATAR_COLORS[absi(hash(username)) % PlayerBadge.AVATAR_COLORS.size()])
		var letter_size := int(inner.size.y * 0.55)
		var font: Font = Ui.bold_font
		var baseline := inner.position.y + (inner.size.y - 30.0 + font.get_ascent(letter_size) - font.get_descent(letter_size)) / 2.0
		_avatar.draw_string(font, Vector2(inner.position.x, baseline), username.substr(0, 1).to_upper(), HORIZONTAL_ALIGNMENT_CENTER, inner.size.x, letter_size, Color.WHITE)
	var strip := Rect2(inner.position.x, inner.end.y - 32.0, inner.size.x, 32.0)
	_avatar.draw_rect(strip, Color(0, 0, 0, 0.6))
	var word_size := 18
	var font: Font = Ui.bold_font
	var word_base := strip.position.y + (strip.size.y + font.get_ascent(word_size) - font.get_descent(word_size)) / 2.0
	_avatar.draw_string(font, Vector2(strip.position.x, word_base), "EDIT", HORIZONTAL_ALIGNMENT_CENTER, strip.size.x, word_size, Color("f3e2b3"))
	_avatar.draw_rect(inner, Color("f1ebe0"), false, 3.0)


func _draw_coin(coin: Control) -> void:
	var center := coin.size / 2.0
	var radius := minf(center.x, center.y)
	coin.draw_circle(center, radius, CoinLabel.RIM, true, -1.0, true)
	coin.draw_circle(center, radius * 0.8, Ui.GOLD, true, -1.0, true)
	coin.draw_arc(center, radius * 0.55, PI * 1.05, PI * 1.5, 10, CoinLabel.SHINE, maxf(1.5, radius * 0.16), true)


func _draw_pencil(button: Button) -> void:
	var middle := button.size / 2.0
	var tip := middle + Vector2(-8, 8)
	var back := middle + Vector2(8, -8)
	button.draw_line(tip + Vector2(3, -3), back, Color("6d6258"), 7.0, true)
	button.draw_line(back - Vector2(2.5, -2.5), back, Color("ef7d1a"), 7.0, true)  # the rubber
	button.draw_colored_polygon(PackedVector2Array([tip, tip + Vector2(6, -1), tip + Vector2(1, -6)]), Color("3e352d"))


func _draw_tick(button: Button) -> void:
	var middle := button.size / 2.0
	var points := PackedVector2Array([middle + Vector2(-9, 0), middle + Vector2(-3, 7), middle + Vector2(9, -7)])
	button.draw_polyline(points, Color.WHITE, 4.5, true)


# The app stores require that an account made in the app can also be deleted in the app.
func _on_delete_account() -> void:
	Ui.ask_password(
		"Delete account",
		"This permanently deletes your account, your coins, your game results and your friends list. Enter your password to confirm.",
		"Delete",
		Game.delete_account
	)


# "2026-10-09T05:12:44.000Z" -> "October 2026"
func _month_of(timestamp: String) -> String:
	var parts := timestamp.split("-")
	if parts.size() < 2 or not parts[0].is_valid_int() or not parts[1].is_valid_int():
		return ""
	var month := int(parts[1])
	if month < 1 or month > 12:
		return ""
	return "%s %s" % [MONTHS[month - 1], parts[0]]
