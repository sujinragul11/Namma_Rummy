class_name ChoiceChip
extends Button
## One choice in a row of them, the way a card-game lobby offers "2 players / 6 players":
## a round mark that fills with a tick when chosen, and the words beside it. The chips of
## one row share a ButtonGroup, so exactly one is on. Drawn in code, like the cards.

const MARK := 40.0
const OFF := Color("8d6e63")
const ON := Color("26a69a")
const TEXT := Color("5d4037")


func _init(label: String = "", group: ButtonGroup = null) -> void:
	text = label
	toggle_mode = true
	button_group = group
	focus_mode = Control.FOCUS_NONE
	alignment = HORIZONTAL_ALIGNMENT_LEFT
	add_theme_font_override("font", Ui.bold_font)
	add_theme_font_size_override("font_size", 26)
	for color_name: String in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color", "font_focus_color"]:
		add_theme_color_override(color_name, TEXT)
	# No box of its own: only the mark and the words. Room is left at the left for the mark.
	var empty := StyleBoxEmpty.new()
	empty.content_margin_left = MARK + 12.0
	empty.content_margin_right = 4.0
	empty.content_margin_top = 6.0
	empty.content_margin_bottom = 6.0
	for state_name: String in ["normal", "hover", "pressed", "hover_pressed", "focus", "disabled"]:
		add_theme_stylebox_override(state_name, empty)
	toggled.connect(func(_on: bool) -> void: queue_redraw())


func _draw() -> void:
	var center := Vector2(MARK / 2.0, size.y / 2.0)
	var radius := MARK / 2.0
	if button_pressed:
		draw_circle(center, radius, ON, true, -1.0, true)
		draw_circle(center, radius - 5.0, Color.WHITE, true, -1.0, true)
		# the tick
		var points := PackedVector2Array([center + Vector2(-8, 1), center + Vector2(-3, 6), center + Vector2(9, -6)])
		draw_polyline(points, ON, 4.0, true)
	else:
		draw_circle(center, radius, OFF, true, -1.0, true)
	if disabled:
		draw_circle(center, radius, Color(1, 1, 1, 0.55), true, -1.0, true)
