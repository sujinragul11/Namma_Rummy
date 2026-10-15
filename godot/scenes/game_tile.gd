class_name GameTile
extends Button
## A big coloured tile on the home menu that opens one kind of game. Drawn in code, like the
## cards: a rounded box in the tile's colour with a glossy top, a few cards or faces as
## decoration, and the name in big letters along the bottom (on the right of a wide tile).

## What the decoration shows: "points", "pool", "closed" (Close Joker), "deals" or "friends".
@export var kind := "points"
@export_multiline var title := "POINTS\nRUMMY"
@export var color := Color("e53935")
## A wide tile has its name beside the decoration instead of under it.
@export var wide := false

var _back: Control  # drawn under the cards: gloss, dots
var _front: Control  # drawn over the cards: crown, faces
var _label: Label
var _cards: Array[CardView] = []


func _init() -> void:
	focus_mode = Control.FOCUS_NONE


func _ready() -> void:
	for state_name: String in ["normal", "hover", "pressed", "disabled"]:
		add_theme_stylebox_override(state_name, _box(state_name))
	add_theme_stylebox_override("focus", StyleBoxEmpty.new())

	_back = _layer(_draw_back)
	_make_cards()
	_front = _layer(_draw_front)

	_label = Label.new()
	_label.text = title
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_label.add_theme_font_override("font", Ui.bold_font)
	_label.add_theme_color_override("font_color", Color.WHITE)
	_label.add_theme_color_override("font_outline_color", color.darkened(0.5))
	_label.add_theme_constant_override("outline_size", 8)
	_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.35))
	_label.add_theme_constant_override("shadow_offset_y", 4)
	_label.add_theme_constant_override("line_spacing", -8)
	add_child(_label)

	resized.connect(_layout)
	_layout()


func _layer(draw: Callable) -> Control:
	var layer := Control.new()
	layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.draw.connect(draw)
	add_child(layer)
	return layer


func _make_cards() -> void:
	var faces: Array = []
	match kind:
		"points":
			faces = [{"id": "A♣", "suit": "♣", "value": "A"}, {"id": "A♠", "suit": "♠", "value": "A"}, {"id": "A♥", "suit": "♥", "value": "A"}]
		"pool":
			faces = [{"id": "A♠", "suit": "♠", "value": "A"}, {"id": "K♥", "suit": "♥", "value": "K"}]
		"closed":
			faces = [{"id": "JOKER", "isJoker": true}, {}]
		"deals":
			faces = [{"id": "K♠", "suit": "♠", "value": "K"}, {"id": "Q♦", "suit": "♦", "value": "Q"}]
		"friends":
			faces = [{"id": "Q♦", "suit": "♦", "value": "Q"}]
	for face: Dictionary in faces:
		var view := CardView.new()
		view.interactive = false
		if face.is_empty():
			view.face_down = true
		else:
			view.card = face
		add_child(view)
		_cards.append(view)


func _layout() -> void:
	for layer: Control in [_back, _front]:
		layer.position = Vector2.ZERO
		layer.size = size
		layer.queue_redraw()

	var font_size := int(minf(46.0, size.y * 0.12)) if not wide else int(size.y * 0.26)
	_label.add_theme_font_size_override("font_size", font_size)
	if wide:
		_label.position = Vector2(size.x * 0.42, 0.0)
		_label.size = Vector2(size.x * 0.54, size.y)
	else:
		_label.size = Vector2(size.x, font_size * 2.5)
		_label.position = Vector2(0.0, size.y - _label.size.y - size.y * 0.04)

	# Where the decoration sits, and how wide a card is in it
	var center := Vector2(size.x * 0.5, size.y * 0.4) if not wide else Vector2(size.x * 0.2, size.y * 0.5)
	var width := size.x * 0.36 if not wide else size.y * 0.42
	match kind:
		"points":
			_place(0, width, center + Vector2(-width * 0.5, width * 0.12), -20.0)
			_place(1, width, center + Vector2(0.0, -width * 0.05), 0.0)
			_place(2, width, center + Vector2(width * 0.5, width * 0.12), 20.0)
		"pool":
			# The cards peep out above the crown, which sits low on them
			_place(0, width * 0.85, center + Vector2(-width * 0.4, -width * 0.12), -14.0)
			_place(1, width * 0.85, center + Vector2(width * 0.4, -width * 0.12), 14.0)
		"closed":
			# The printed joker behind, and in front of it the round's joker lying face down
			_place(0, width * 1.15, center + Vector2(-width * 0.46, -width * 0.1), -14.0)
			_place(1, width * 1.15, center + Vector2(width * 0.42, width * 0.14), 9.0)
		"deals":
			# The cards stand behind the chips the deals are played for
			_place(0, width * 0.9, center + Vector2(-width * 0.38, -width * 0.18), -12.0)
			_place(1, width * 0.9, center + Vector2(width * 0.38, -width * 0.18), 12.0)
		"friends":
			_place(0, width, center + Vector2(width * 0.9, -width * 0.1), 14.0)


func _place(index: int, width: float, at: Vector2, degrees: float) -> void:
	var view := _cards[index]
	view.set_width(width)
	view.pivot_offset = view.size / 2.0
	view.position = at - view.size / 2.0
	view.rotation_degrees = degrees


# A glossy upper half, and for the tall tile a field of faint dots.
func _draw_back() -> void:
	var gloss := StyleBoxFlat.new()
	gloss.bg_color = Color(1, 1, 1, 0.1)
	gloss.set_corner_radius_all(20)
	gloss.anti_aliasing = true
	_back.draw_style_box(gloss, Rect2(8.0, 8.0, size.x - 16.0, size.y * 0.52))
	if kind in ["points", "closed"]:
		var step := 22.0
		var y := 30.0
		while y < size.y - 30.0:
			var x := 30.0
			while x < size.x - 30.0:
				_back.draw_circle(Vector2(x, y), 2.2, Color(1, 1, 1, 0.09), true, -1.0, true)
				x += step
			y += step


# What lies over the cards: the pool tile's crown, the deals tile's chips, the faces on the
# friends tile, the lock on Close Joker's hidden joker.
func _draw_front() -> void:
	if kind == "closed":
		# Turned with the card it lies on
		var hidden := _cards[1]
		_front.draw_set_transform(hidden.position + hidden.pivot_offset, hidden.rotation)
		_draw_lock(Vector2(0.0, hidden.size.y * 0.06), hidden.size.x * 0.46)
		_front.draw_set_transform(Vector2.ZERO)
	elif kind == "pool":
		_draw_crown(Vector2(size.x * 0.5, size.y * 0.5), size.x * 0.46)
	elif kind == "deals":
		_draw_chips(Vector2(size.x * 0.5, size.y * 0.56), size.x * 0.13)
	elif kind == "friends":
		var radius := size.y * 0.24
		var at := Vector2(size.x * 0.12, size.y * 0.5)
		_draw_face(at, radius, PlayerBadge.AVATAR_COLORS[0], "A")
		_draw_face(at + Vector2(radius * 1.3, radius * 0.3), radius, PlayerBadge.AVATAR_COLORS[2], "B")


func _draw_crown(center: Vector2, width: float) -> void:
	var w := width / 2.0
	var h := width * 0.42
	var gold := Ui.GOLD
	var dark := gold.darkened(0.35)
	var points := PackedVector2Array([
		center + Vector2(-w, h * 0.5), center + Vector2(-w, -h * 0.35), center + Vector2(-w * 0.5, 0.0),
		center + Vector2(0.0, -h * 0.5), center + Vector2(w * 0.5, 0.0), center + Vector2(w, -h * 0.35),
		center + Vector2(w, h * 0.5),
	])
	_front.draw_colored_polygon(points, gold)
	points.append(points[0])
	_front.draw_polyline(points, dark, 3.0, true)
	_front.draw_rect(Rect2(center.x - w, center.y + h * 0.5 - h * 0.18, width, h * 0.2), dark)
	for spike: Vector2 in [Vector2(-w, -h * 0.35), Vector2(0.0, -h * 0.5), Vector2(w, -h * 0.35)]:
		_front.draw_circle(center + spike, h * 0.11, Color("e53935"), true, -1.0, true)
	_front.draw_circle(center + Vector2(0.0, h * 0.12), h * 0.14, Color("1e88e5"), true, -1.0, true)


# A gold padlock with a steel shackle: the joker stays shut until a pure sequence opens it.
func _draw_lock(center: Vector2, width: float) -> void:
	var dark := Ui.GOLD.darkened(0.45)
	var body := Rect2(center.x - width / 2.0, center.y - width * 0.28, width, width * 0.76)
	var radius := width * 0.3
	var arch := Vector2(center.x, body.position.y + width * 0.06)
	_front.draw_arc(arch, radius, PI, TAU, 24, dark, width * 0.22, true)
	_front.draw_arc(arch, radius, PI, TAU, 24, Color("cfd8dc"), width * 0.12, true)
	var box := StyleBoxFlat.new()
	box.bg_color = Ui.GOLD
	box.set_corner_radius_all(int(width * 0.14))
	box.border_color = dark
	box.set_border_width_all(3)
	box.anti_aliasing = true
	_front.draw_style_box(box, body)
	var hole := body.get_center() - Vector2(0.0, width * 0.06)
	_front.draw_circle(hole, width * 0.1, dark, true, -1.0, true)
	_front.draw_rect(Rect2(hole.x - width * 0.04, hole.y, width * 0.08, width * 0.2), dark)


# Three stacks of round chips, red, gold and blue, each with a white ring.
func _draw_chips(center: Vector2, radius: float) -> void:
	var stacks := [[Vector2(-radius * 1.7, radius * 0.25), Color("e53935"), 3], [Vector2(radius * 1.7, radius * 0.25), Color("1e88e5"), 2], [Vector2.ZERO, Ui.GOLD, 4]]
	for stack: Array in stacks:
		var base: Vector2 = center + stack[0]
		var color: Color = stack[1]
		for level in int(stack[2]):
			var at := base - Vector2(0.0, level * radius * 0.28)
			var squash := Vector2(1.0, 0.42)
			_front.draw_set_transform(at, 0.0, squash)
			_front.draw_circle(Vector2(0.0, radius * 0.5), radius, color.darkened(0.35), true, -1.0, true)
			_front.draw_circle(Vector2.ZERO, radius, color, true, -1.0, true)
			_front.draw_arc(Vector2.ZERO, radius * 0.68, 0.0, TAU, 32, Color(1, 1, 1, 0.85), radius * 0.16, true)
			_front.draw_set_transform(Vector2.ZERO)


func _draw_face(center: Vector2, radius: float, fill: Color, letter: String) -> void:
	_front.draw_circle(center, radius + 4.0, Color.WHITE, true, -1.0, true)
	_front.draw_circle(center, radius, fill, true, -1.0, true)
	var font := Ui.bold_font
	var font_size := int(radius * 1.1)
	var baseline := center.y + (font.get_ascent(font_size) - font.get_descent(font_size)) / 2.0
	_front.draw_string(font, Vector2(center.x - radius, baseline), letter, HORIZONTAL_ALIGNMENT_CENTER, radius * 2.0, font_size, Color.WHITE)


# The tile's box: its colour, a darker rim that is thicker at the bottom, a soft shadow.
func _box(state_name: String) -> StyleBoxFlat:
	var shade := color
	if state_name == "hover":
		shade = color.lightened(0.07)
	elif state_name == "pressed":
		shade = color.darkened(0.1)
	elif state_name == "disabled":
		shade = Color(color, 0.4)
	var style := StyleBoxFlat.new()
	style.bg_color = shade
	style.set_corner_radius_all(24)
	style.border_color = color.darkened(0.38)
	style.set_border_width_all(3)
	style.border_width_bottom = 8
	style.shadow_color = Color(0, 0, 0, 0.35)
	style.shadow_size = 6
	style.shadow_offset = Vector2(0, 4)
	style.anti_aliasing = true
	return style
