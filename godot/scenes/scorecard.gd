class_name ScoreCard
extends Control
## What the table shows when a round is over (the scorecard) and when the whole game is over
## (the game result): a cream sheet with a row for each player (their picture and name, the
## hand as it was scored, group by group, the round's points and the running total), a teal
## bar along the bottom, and the wild joker in the corner.
##
## Between rounds the bar only counts down to the next round, which deals itself: there is no
## way out here (the user's choice, 2026-10-18; the phone's back button still asks before
## leaving). Once the whole game is over it holds Leave game and Play again.
##
## The table calls refresh() with every update; everything shown is read from Game.state.

const SHEET_EDGE := Color("fbf6e9")
const SHEET := Color("ece2c8")
const DOTS := Color(0.83, 0.76, 0.6)
const ROW := Color("fffbf1")
const ROW_EDGE := Color("e0ad45")
const HEADING := Color("1d564c")
const NAME := Color("b0560a")
const NUMBER := Color("8a4500")
const GAIN := Color("2f9e44")
const LOSS := Color("e03131")
const BAR := Color("19a68b")
const BAR_LIGHT := Color("6fe0c6")
const BAR_TEXT := Color("0b3b31")
const BUTTON := Color("f7c531")
const BUTTON_TEXT := Color("5b3a00")
const TITLE_FILL := Color("ffd43b")
const TITLE_EDGE := Color("e8590c")
const GLOW := Color("b14cff")

const CARD_WIDTH := 54.0
const PLAYER_WIDTH := 150.0
const SCORE_WIDTH := 110.0
const TOTAL_WIDTH := 160.0
const SIDE := 18.0  # between the screen's sides and the sheet
const TOP := 36.0  # above the sheet, where the heading stands half over its edge
const BAR_HEIGHT := 84.0
const BAR_OVER_SHEET := 24.0  # the bar lies over the bottom of the sheet
const WILD_WIDTH := 58.0

var _key := ""  # which result is shown, so that the same one is not built again
var _last_beep := -1
var _shade: ColorRect
var _sheet: Control
var _heading: Label
var _title: Label
var _total_heading: Label
var _rows: VBoxContainer
var _bar: Control
var _bar_row: HBoxContainer
var _next_label: Label
var _leave_button: Button
var _again_button: Button
var _rejoin_button: Button
var _wild: VBoxContainer
var _wild_card: CardView
var _confetti: CPUParticles2D


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build()
	resized.connect(_layout)
	_layout()


## Shows the result of the round or the game when there is one, and hides it otherwise.
func refresh() -> void:
	var status := Game.status()
	var result: Variant = Game.state.get("lastResult")
	if not (status in ["round_over", "finished"] and result is Dictionary):
		visible = false
		_confetti.emitting = false
		_key = ""
		return

	var finished := status == "finished"
	_leave_button.visible = finished
	_again_button.visible = finished
	var offer: Variant = Game.state.get("rejoin")
	_rejoin_button.visible = not finished and offer is Dictionary
	if _rejoin_button.visible:
		_rejoin_button.text = "Rejoin · %s coins" % Ui.coins_text(int(offer.get("fee", 0)))
		_rejoin_button.disabled = Game.busy or not Game.is_online()
	# The same result arrives again with every update; build it only when it changes
	var key := "%s/%s/%s" % [Game.state.get("gameId"), result.get("round"), status]
	if key != _key:
		_key = key
		_show(result, finished)
	# Buttons just shown sit on top of one another until the next layout pass, and a finger
	# can be quicker than that: put them in their places now
	_bar_row.notification(Container.NOTIFICATION_SORT_CHILDREN)


func _process(_delta: float) -> void:
	if not visible or Game.status() != "round_over":
		return
	var prefix := "You are out of the match. " if Game.me().get("eliminated", false) else ""
	var seconds := Game.seconds_until(Game.next_round_at)
	_next_label.text = "%sNext %s in %d %s" % [prefix, "deal" if Game.deals() > 0 else "round", seconds, "second" if seconds == 1 else "seconds"]
	var offer: Variant = Game.state.get("rejoin")
	if offer is Dictionary:
		_next_label.text = "Rejoin at %d points · %ds left" % [int(offer.get("score", 0)), seconds]
		_rejoin_button.disabled = seconds <= 0 or Game.busy or not Game.is_online()
	if seconds > 3:
		_last_beep = -1
	elif seconds > 0 and seconds != _last_beep:
		_last_beep = seconds
		Sound.play("beep")


func _show(result: Dictionary, finished: bool) -> void:
	var winner: Variant = result.get("matchWinner") if finished else result.get("winner")
	var winner_id := "" if winner == null else str(winner)
	var i_won := not winner_id.is_empty() and winner_id == Game.player_id

	_heading.text = "GAME RESULT" if finished else "SCORECARD"
	if finished:
		if winner_id.is_empty():
			_title.text = "Game over"
		elif i_won:
			_title.text = "You won!"
		else:
			_title.text = "%s won the game" % Game.player_name(winner_id)
		_next_label.text = "Game over"
	else:
		var round_name := ("deal %d" if Game.deals() > 0 else "round %d") % int(result.get("round", 1))
		_title.text = "%s won %s" % ["You" if i_won else Game.player_name(winner_id), round_name]
	_title.add_theme_color_override("font_color", GAIN if i_won else HEADING)
	_total_heading.text = "Chips" if Game.deals() > 0 else "Total"

	for child in _rows.get_children():
		_rows.remove_child(child)
		child.queue_free()
	var rows: Array = result.get("players", [])
	for index in rows.size():
		var delay := 0.25 + index * 0.12
		var entry := _build_row(rows[index], finished, winner_id, delay)
		_rows.add_child(entry)
		# The players are read out one after another, each with a tick
		Ui.pop_in.call_deferred(entry, delay)
		Sound.play_later("count", delay)

	var joker: Variant = Game.state.get("joker")
	_wild.visible = joker is Dictionary and not (joker as Dictionary).is_empty()
	if _wild.visible:
		_wild_card.card = joker

	# The sheet drops in, the heading lands on it, the bar fades in. The bar does not slide:
	# its buttons must be where they are seen from the first moment, for a quick finger
	_layout()
	visible = true
	modulate.a = 0.0
	create_tween().tween_property(self, "modulate:a", 1.0, 0.2)
	Ui.pop_in.call_deferred(_sheet)
	var heading_at := _heading.position.y
	_heading.position.y = heading_at - 60.0
	var tween := _heading.create_tween()
	tween.tween_property(_heading, "position:y", heading_at, 0.45).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT).set_delay(0.1)
	_bar.modulate.a = 0.0
	_bar.create_tween().tween_property(_bar, "modulate:a", 1.0, 0.3).set_delay(0.1)
	if _wild.visible:
		Ui.pop_in.call_deferred(_wild, 0.45)

	# The winner gets confetti and fireworks; the rest a gentler word
	_confetti.position = Vector2(size.x / 2.0, -20.0)
	_confetti.emission_rect_extents = Vector2(size.x / 2.0, 6.0)
	_confetti.emitting = i_won
	if i_won:
		Input.vibrate_handheld(120)
		Sound.play("win")
		Sound.duck(3.0)  # the music steps back for the fanfare
		Fx.victory(finished)
	else:
		Sound.play("lose")
		Fx.flash(Color(0.45, 0.0, 0.0, 0.4), 0.7)


# One player's line: picture and name, the hand, the round's points, the total.
func _build_row(row: Dictionary, finished: bool, winner_id: String, delay: float) -> Control:
	var id := str(row.get("id", ""))
	var is_winner := id == winner_id
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _row_box())
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 10)
	panel.add_child(line)

	var player := VBoxContainer.new()
	player.custom_minimum_size.x = PLAYER_WIDTH
	player.alignment = BoxContainer.ALIGNMENT_CENTER
	player.add_theme_constant_override("separation", 4)
	var username := str(row.get("username", "Player"))
	player.add_child(Avatar.new(id, username, _avatar_version(id), is_winner, delay + 0.35))
	var name_label := _label("You" if id == Game.player_id else username, 20, NAME, true)
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.custom_minimum_size.x = PLAYER_WIDTH
	name_label.clip_text = true
	name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	player.add_child(name_label)
	var wrong_declaration: bool = row.get("outcome") == "wrong_declaration"
	if wrong_declaration:
		var reason := _label("Wrong Declaration", 18, LOSS, true)
		reason.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		reason.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		player.add_child(reason)
	line.add_child(player)

	# The hand as it was scored. A dropped hand stays face down, as it was never shown.
	var dropped: bool = row.get("outcome") == "dropped"
	var mark := ""
	if row.get("eliminated", false) and not is_winner and not wrong_declaration:
		mark = "OUT"
	elif dropped:
		mark = "DROPPED"
	var hand := HandStrip.new(row.get("melds", []), Game.state.get("joker"), dropped, mark)
	hand.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	line.add_child(hand)
	var friend_button := _friend_button(row)
	if friend_button != null:
		line.add_child(friend_button)

	var points := int(row.get("points", 0))
	var score := _label("0", 34, NUMBER, true)
	score.custom_minimum_size.x = SCORE_WIDTH
	score.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	line.add_child(score)
	_count_up.call_deferred(score, 0, points, delay)  # (once the row is in the tree)

	var total_column := VBoxContainer.new()
	total_column.custom_minimum_size.x = TOTAL_WIDTH
	total_column.alignment = BoxContainer.ALIGNMENT_CENTER
	total_column.add_theme_constant_override("separation", 2)
	var total := _label("", 34, NUMBER, true)
	total.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	total_column.add_child(total)
	if row.has("chips"):
		# Deals Rummy: the chips the player has now, and how many changed hands
		var chips := int(row.get("chips", 0))
		var won := int(row.get("chipsWon", 0))
		_count_up.call_deferred(total, chips - won, chips, delay)
		var change := _label("%+d chips" % won, 20, GAIN if won >= 0 else LOSS, true)
		change.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		total_column.add_child(change)
	else:
		var total_score := int(row.get("totalScore", points))
		_count_up.call_deferred(total, total_score - points, total_score, delay)
	var coins := _coins_for(row, finished, winner_id)
	if coins != 0:
		var money := CoinLabel.new()
		money.font_size = 22
		money.prefix = "+" if coins > 0 else ""
		money.amount = coins
		money.text_color = GAIN if coins > 0 else LOSS
		money.alignment = BoxContainer.ALIGNMENT_CENTER
		total_column.add_child(money)
	line.add_child(total_column)
	# Decorative cards, labels and avatars must let swipes reach the scroll container.
	_pass_scroll_input(panel)
	return panel


func _pass_scroll_input(control: Control) -> void:
	if control is Button:
		return
	control.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for child in control.get_children():
		if child is Control:
			_pass_scroll_input(child)


# What the result did to a player's coins: at a table for so many coins a point, what their
# points cost or won; at a table with an entry, once the whole game is over, the pot for the
# winner and the entry for everyone else. 0 shows nothing.
func _coins_for(row: Dictionary, finished: bool, winner_id: String) -> int:
	if row.has("coins"):
		return int(row.get("coins", 0))
	if not finished or Game.stake() <= 0 or winner_id.is_empty():
		return 0
	return Game.pot() if str(row.get("id", "")) == winner_id else -(Game.stake() + int(row.get("rejoinPaid", 0)))


func _avatar_version(user_id: String) -> int:
	for player: Dictionary in Game.players():
		if str(player.get("id", "")) == user_id:
			return int(player.get("avatar", 0))
	return 0


# "Add friend" for a player met at this table who is not in the friends list yet.
func _friend_button(row: Dictionary) -> Button:
	var id := str(row.get("id", ""))
	var username := str(row.get("username", ""))
	if id == Game.player_id or username.is_empty():
		return null
	for known: Dictionary in Game.friends + Game.friend_asked:
		if str(known.get("id", "")) == id:
			return null

	var button := Button.new()
	button.name = "AddFriendButton"
	button.text = "Add friend"
	button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	button.add_theme_font_size_override("font_size", 20)
	Ui.tint_button(button, Ui.TEAL)
	button.pressed.connect(func() -> void:
		Game.add_friend(username)
		button.disabled = true
		button.text = "Asked"
	)
	return button


# A number that runs up to its value once its row is in.
func _count_up(label: Label, from: int, to: int, delay: float) -> void:
	label.text = str(from)
	if from == to:
		return
	var tween := label.create_tween()
	tween.tween_interval(delay + 0.1)
	tween.tween_method(func(value: float) -> void: label.text = str(roundi(value)), float(from), float(to), 0.4)


# ---------- building ----------

func _build() -> void:
	_shade = ColorRect.new()
	_shade.color = Color(0, 0, 0, 0.66)
	_shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_shade)  # it takes every tap that misses the sheet's buttons

	_sheet = Control.new()
	_sheet.name = "ResultPanel"
	_sheet.mouse_filter = Control.MOUSE_FILTER_STOP
	_sheet.draw.connect(_draw_sheet)
	add_child(_sheet)
	var column := VBoxContainer.new()
	column.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	column.offset_left = 26.0
	column.offset_right = -26.0
	column.offset_top = 46.0
	column.offset_bottom = -(BAR_OVER_SHEET + 8.0)
	column.add_theme_constant_override("separation", 8)
	_sheet.add_child(column)

	_title = _label("", 22, HEADING, true)
	_title.name = "ResultTitle"
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(_title)

	# The column headings, over the same widths as the rows (whose box has the same margins)
	var headings := MarginContainer.new()
	headings.add_theme_constant_override("margin_left", 12)
	headings.add_theme_constant_override("margin_right", 16)
	column.add_child(headings)
	var heading_row := HBoxContainer.new()
	heading_row.add_theme_constant_override("separation", 10)
	headings.add_child(heading_row)
	for heading: Array in [["Players", PLAYER_WIDTH], ["Cards", 0.0], ["Score", SCORE_WIDTH], ["Total", TOTAL_WIDTH]]:
		var label := _label(heading[0], 20, HEADING, true)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.custom_minimum_size.x = heading[1]
		if heading[1] == 0.0:
			label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		heading_row.add_child(label)
		if heading[0] == "Total":
			_total_heading = label

	var scroll := preload("res://scenes/score_scroll.gd").new()
	scroll.name = "ResultScroll"
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	scroll.scroll_deadzone = 6
	var scrollbar := scroll.get_v_scroll_bar()
	scrollbar.custom_minimum_size.x = 24
	scrollbar.add_theme_stylebox_override("scroll", Ui.box(Color("ded1b2"), 10, 0, 0))
	for state_name: String in ["grabber", "grabber_highlight", "grabber_pressed"]:
		var thumb := Ui.box(Color("19a68b"), 10, 0, 0)
		thumb.content_margin_top = 20
		thumb.content_margin_bottom = 20
		scrollbar.add_theme_stylebox_override(state_name, thumb)
	column.add_child(scroll)
	_rows = VBoxContainer.new()
	_rows.name = "ResultRows"
	_rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_rows.add_theme_constant_override("separation", 12)
	scroll.add_child(_rows)

	_heading = _label("SCORECARD", 50, TITLE_FILL, true)
	_heading.name = "ResultHeading"
	_heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_heading.add_theme_color_override("font_outline_color", TITLE_EDGE)
	_heading.add_theme_constant_override("outline_size", 14)
	_heading.add_theme_color_override("font_shadow_color", Color(0.35, 0.12, 0.0, 0.45))
	_heading.add_theme_constant_override("shadow_offset_y", 4)
	_heading.add_theme_constant_override("shadow_outline_size", 14)
	add_child(_heading)

	_bar = Control.new()
	_bar.name = "ResultBar"
	_bar.mouse_filter = Control.MOUSE_FILTER_STOP
	_bar.draw.connect(_draw_bar)
	add_child(_bar)
	_bar_row = HBoxContainer.new()
	_bar_row.name = "ResultBarRow"
	_bar_row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_bar_row.offset_left = 40.0
	_bar_row.offset_right = -(WILD_WIDTH + 52.0)  # the wild joker sits at the right end
	_bar_row.offset_top = 16.0
	_bar_row.offset_bottom = -8.0
	_bar_row.add_theme_constant_override("separation", 16)
	_bar.add_child(_bar_row)
	_leave_button = _bar_button("BackButton", "Leave Game")
	_leave_button.pressed.connect(Game.leave)
	_bar_row.add_child(_leave_button)
	_next_label = _label("", 26, BAR_TEXT, true)
	_next_label.name = "NextRoundLabel"
	_next_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_next_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_next_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_next_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_bar_row.add_child(_next_label)
	_again_button = _bar_button("PlayAgainButton", "Play Again")  # a new table, same rules, same players
	_again_button.pressed.connect(Game.play_again)
	_bar_row.add_child(_again_button)
	_rejoin_button = _bar_button("RejoinButton", "Rejoin")
	_rejoin_button.visible = false
	_rejoin_button.pressed.connect(_confirm_rejoin)
	_bar_row.add_child(_rejoin_button)

	# This round's wild joker, in the corner
	_wild = VBoxContainer.new()
	_wild.name = "WildCard"
	_wild.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_wild.add_theme_constant_override("separation", 0)
	add_child(_wild)
	var wild_label := _label("WILD", 20, Color.WHITE, true)
	wild_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	wild_label.add_theme_color_override("font_outline_color", BAR_TEXT)
	wild_label.add_theme_constant_override("outline_size", 6)
	_wild.add_child(wild_label)
	_wild_card = CardView.new()
	_wild_card.interactive = false
	_wild_card.set_width(WILD_WIDTH)
	_wild_card.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_wild.add_child(_wild_card)

	_confetti = _make_confetti()
	add_child(_confetti)


func _layout() -> void:
	if _sheet == null:
		return
	_sheet.position = Vector2(SIDE, TOP)
	_sheet.size = Vector2(size.x - SIDE * 2.0, size.y - TOP - BAR_HEIGHT + BAR_OVER_SHEET)
	_sheet.pivot_offset = _sheet.size / 2.0
	_heading.position = Vector2(0.0, 0.0)
	_heading.size = Vector2(size.x, TOP * 2.0)
	_bar.position = Vector2(0.0, size.y - BAR_HEIGHT)
	_bar.size = Vector2(size.x, BAR_HEIGHT)
	_wild.reset_size()
	_wild.position = Vector2(size.x - WILD_WIDTH - 28.0, size.y - _wild.size.y - 6.0)
	_wild.pivot_offset = _wild.size / 2.0


func _bar_button(node_name: String, text: String) -> Button:
	var button := Button.new()
	button.name = node_name
	button.text = text
	button.custom_minimum_size = Vector2(210, 58)
	button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	button.add_theme_font_size_override("font_size", 24)
	Ui.tint_button(button, BUTTON)
	for color_name: String in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		button.add_theme_color_override(color_name, BUTTON_TEXT)
	return button


func _confirm_rejoin() -> void:
	var offer: Variant = Game.state.get("rejoin")
	if not offer is Dictionary:
		return
	var fee := int(offer.get("fee", 0))
	var score := int(offer.get("score", 0))
	Ui.confirm("Rejoin Close Joker", "Pay %s coins (50%% of the original entry) and rejoin at %d points?\nThe extra coins go into the prize pot. Confirm before the countdown ends." % [Ui.coins_text(fee), score], "Rejoin", Game.rejoin_game.bind(score))


func _row_box() -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = ROW
	box.set_corner_radius_all(12)
	box.border_color = ROW_EDGE
	box.border_width_bottom = 5
	box.shadow_color = Color(0, 0, 0, 0.12)
	box.shadow_size = 4
	box.shadow_offset = Vector2(0, 2)
	box.content_margin_left = 12
	box.content_margin_right = 16
	box.content_margin_top = 8
	box.content_margin_bottom = 8
	box.anti_aliasing = true
	return box


func _label(text: String, font_size: int, color: Color, bold: bool = false) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	if bold:
		label.add_theme_font_override("font", Ui.bold_font)
	return label


# A light frame round a parchment middle, with a patch of printed dots in the top corner.
func _draw_sheet() -> void:
	var whole := Rect2(Vector2.ZERO, _sheet.size)
	var frame := StyleBoxFlat.new()
	frame.bg_color = SHEET_EDGE
	frame.set_corner_radius_all(22)
	frame.shadow_color = Color(0, 0, 0, 0.35)
	frame.shadow_size = 16
	frame.shadow_offset = Vector2(0, 6)
	frame.anti_aliasing = true
	_sheet.draw_style_box(frame, whole)
	var middle := StyleBoxFlat.new()
	middle.bg_color = SHEET
	middle.set_corner_radius_all(14)
	middle.anti_aliasing = true
	_sheet.draw_style_box(middle, whole.grow(-10.0))
	for row in 5:
		for dot in 14 - row * 2:
			var at := Vector2(24.0 + dot * 14.0 + (row % 2) * 7.0, 22.0 + row * 12.0)
			_sheet.draw_circle(at, 3.0 - row * 0.4, Color(DOTS, 0.55 - row * 0.1), true, -1.0, true)


# Teal, with its upper corners cut at a slant and a light rim along the top.
func _draw_bar() -> void:
	var width := _bar.size.x
	var height := _bar.size.y
	var slant := 26.0
	var top := PackedVector2Array([Vector2(0, slant), Vector2(slant * 1.6, 0), Vector2(width - slant * 1.6, 0), Vector2(width, slant)])
	var shape := top.duplicate()
	shape.append(Vector2(width, height))
	shape.append(Vector2(0, height))
	_bar.draw_colored_polygon(shape, BAR)
	_bar.draw_rect(Rect2(0, height * 0.6, width, height * 0.4), Color(0, 0, 0, 0.08))
	_bar.draw_polyline(top, BAR_LIGHT, 4.0, true)


# Coloured paper falling from the top of the screen, for the winner.
func _make_confetti() -> CPUParticles2D:
	var confetti := CPUParticles2D.new()
	confetti.emitting = false
	confetti.amount = 150
	confetti.lifetime = 3.4
	confetti.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	confetti.direction = Vector2.DOWN
	confetti.spread = 30.0
	confetti.gravity = Vector2(0, 380)
	confetti.initial_velocity_min = 90.0
	confetti.initial_velocity_max = 300.0
	confetti.angular_velocity_min = -400.0
	confetti.angular_velocity_max = 400.0
	confetti.angle_max = 360.0
	confetti.scale_amount_min = 8.0
	confetti.scale_amount_max = 15.0

	var paper := Gradient.new()
	paper.interpolation_mode = Gradient.GRADIENT_INTERPOLATE_CONSTANT
	paper.offsets = PackedFloat32Array([0.0, 0.17, 0.34, 0.51, 0.68, 0.85])
	paper.colors = PackedColorArray([
		Color("ffca28"), Color("ef5350"), Color("42a5f5"), Color("66bb6a"), Color("ab47bc"), Color("ffffff"),
	])
	confetti.color_initial_ramp = paper
	return confetti


## The corners of a rectangle with rounded corners, clockwise from the top left.
static func rounded_rect(rect: Rect2, radius: float, steps: int = 6) -> PackedVector2Array:
	var points := PackedVector2Array()
	var corners := [
		[rect.position + Vector2(radius, radius), PI],
		[Vector2(rect.end.x - radius, rect.position.y + radius), PI * 1.5],
		[rect.end - Vector2(radius, radius), 0.0],
		[Vector2(rect.position.x + radius, rect.end.y - radius), PI * 0.5],
	]
	for corner: Array in corners:
		for step in steps + 1:
			var angle: float = corner[1] + PI * 0.5 * step / steps
			points.append(corner[0] + Vector2.from_angle(angle) * radius)
	return points


## A player's picture in a rounded square: their photo, or their initial on a colour. The
## winner's glows purple and wears a "WINNER!" ribbon.
class Avatar extends Control:
	const SIDE_LENGTH := 70.0
	const FRAME := Color("2b2b2b")

	var _user_id := ""
	var _player_name := ""
	var _version := 0
	var _winner := false
	var _ribbon: Label
	var _ribbon_delay := 0.0
	var _photo: Texture2D
	var _time := 0.0

	func _init(user_id: String, player_name: String, version: int, winner: bool, ribbon_delay: float) -> void:
		_user_id = user_id
		_player_name = player_name
		_version = version
		_winner = winner
		_ribbon_delay = ribbon_delay
		name = "ResultAvatar"
		custom_minimum_size = Vector2(SIDE_LENGTH, SIDE_LENGTH)
		size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		set_process(winner)
		if winner:
			_ribbon = Label.new()
			_ribbon.name = "WinnerRibbon"
			_ribbon.text = "WINNER!"
			_ribbon.add_theme_font_override("font", Ui.bold_font)
			_ribbon.add_theme_font_size_override("font_size", 20)
			_ribbon.add_theme_color_override("font_color", ScoreCard.TITLE_FILL)
			_ribbon.add_theme_color_override("font_outline_color", Color("8a3b00"))
			_ribbon.add_theme_constant_override("outline_size", 8)
			# Across the top of the picture, inside its own row
			_ribbon.position = Vector2(-16.0, -2.0)
			_ribbon.rotation = -0.17
			_ribbon.scale = Vector2.ZERO
			add_child(_ribbon)

	func _ready() -> void:
		_photo = Game.avatar_texture(_user_id, _version)
		Game.avatar_loaded.connect(_on_avatar_loaded)
		if _ribbon != null:
			# The ribbon lands once the row is in
			var tween := _ribbon.create_tween()
			tween.tween_interval(_ribbon_delay)
			tween.tween_property(_ribbon, "scale", Vector2.ONE, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

	func _on_avatar_loaded(user_id: String) -> void:
		if user_id == _user_id:
			_photo = Game.avatar_texture(_user_id, _version)
			queue_redraw()

	func _process(delta: float) -> void:
		_time += delta
		queue_redraw()

	func _draw() -> void:
		var box := Rect2(Vector2.ZERO, size)
		var middle := size / 2.0
		if _winner:
			# A purple glow breathing round the picture
			var breath := 0.5 + 0.5 * sin(_time * 3.0)
			for layer in 7:
				draw_circle(middle, size.x * 0.5 + 4.0 + layer * 4.0 + breath * 3.0, Color(ScoreCard.GLOW, 0.2 - layer * 0.025), true, -1.0, true)
		draw_colored_polygon(ScoreCard.rounded_rect(box, 12.0), FRAME)
		var inner := box.grow(-3.0)
		var shape := ScoreCard.rounded_rect(inner, 10.0)
		if _photo != null:
			var uvs := PackedVector2Array()
			for point in shape:
				uvs.append((point - inner.position) / inner.size)
			draw_colored_polygon(shape, Color.WHITE, uvs, _photo)
		else:
			var colors := PlayerBadge.AVATAR_COLORS
			draw_colored_polygon(shape, colors[absi(hash(_player_name)) % colors.size()])
			var font := get_theme_default_font()
			var font_size := int(size.y * 0.5)
			var baseline := middle.y + (font.get_ascent(font_size) - font.get_descent(font_size)) / 2.0
			draw_string(font, Vector2(0, baseline), _player_name.substr(0, 1).to_upper(), HORIZONTAL_ALIGNMENT_CENTER, size.x, font_size, Color.WHITE)


## A hand laid out group by group, the cards of a group overlapping, with a dark band across
## it for a word like DROPPED. The cards shrink together to fit the room there is.
class HandStrip extends Control:
	const GAP := 14.0  # between groups
	const OVERLAP := 0.62  # how much of a card shows before the next one in its group

	var _views: Array[CardView] = []
	var _groups: Array[int] = []
	var _band: ColorRect

	func _init(melds: Array, joker: Variant, face_down: bool, mark: String) -> void:
		name = "ResultHand"
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		custom_minimum_size.y = CardView.height_for(ScoreCard.CARD_WIDTH) + 6.0
		for meld: Dictionary in melds:
			var cards: Array = meld.get("cards", [])
			if cards.is_empty():
				continue
			_groups.append(cards.size())
			for card: Dictionary in cards:
				var view := CardView.new()
				view.interactive = false
				view.card = card
				view.face_down = face_down
				view.wild = not face_down and Rummy.is_wild(card, joker)
				add_child(view)
				_views.append(view)
		if not mark.is_empty():
			_band = ColorRect.new()
			_band.name = "HandMark"
			_band.color = Color(0.16, 0.08, 0.0, 0.62)
			_band.mouse_filter = Control.MOUSE_FILTER_IGNORE
			var word := Label.new()
			word.text = mark
			word.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			word.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			word.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
			word.add_theme_font_override("font", Ui.bold_font)
			word.add_theme_font_size_override("font_size", 22)
			word.add_theme_color_override("font_color", Color.WHITE)
			_band.add_child(word)
			add_child(_band)
		resized.connect(_arrange)

	func _arrange() -> void:
		if size.x <= 0.0:
			return # Wait for the container's first layout before sizing card text.
		if _views.is_empty():
			if _band != null:
				_band.position = Vector2(0.0, size.y / 2.0 - 17.0)
				_band.size = Vector2(size.x, 34.0)
			return
		var width := ScoreCard.CARD_WIDTH
		var gap := GAP
		var step := width * OVERLAP
		var groups := _groups.size()
		var steps := _views.size() - groups
		var natural := groups * width + steps * step + (groups - 1) * GAP
		if natural > size.x:
			# Even thirteen ungrouped cards must fit without covering the points columns.
			var factor := maxf(0.0, size.x) / natural
			width *= factor
			step *= factor
			gap *= factor
		var y := (size.y - CardView.height_for(width)) / 2.0
		var x := 0.0
		var index := 0
		for count in _groups:
			for place in count:
				var view := _views[index]
				view.set_width(width)
				view.position = Vector2(x, y)
				x += step if place < count - 1 else width
				index += 1
			x += gap
		if _band != null:
			_band.position = Vector2(0.0, size.y / 2.0 - 17.0)
			_band.size = Vector2(x - gap, 34.0)
