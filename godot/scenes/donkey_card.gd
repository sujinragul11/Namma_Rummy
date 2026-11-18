class_name DonkeyCard
extends Button
## One of the two big cards on the Donkey Master home: Play Online and Play with Friends.
## Drawn in code like the rummy tiles: a rounded box in the card's colour with a darker rim,
## slow rays turning behind a picture that floats, the name in big outlined letters, two small
## tags at the top, and an action pill along the bottom. Now and then a streak of light runs
## across it, so the menu never stands still.

const RADIUS := 26
const SHINE_EVERY := 4.2  # seconds between two streaks of light
const SHINE_SECONDS := 0.9

@export var title := "PLAY ONLINE"
@export var subtitle := ""
@export var color := Color("1e88e5")
@export var picture: Texture2D
## The small tags along the top: the first on the left, the second on the right.
@export var tags: PackedStringArray = []
## The words on the pill along the bottom, e.g. "PLAY NOW".
@export var action := "PLAY NOW"
## A green light that blinks before the first tag: players are online now.
@export var live := false

var _time := 0.0
var _shine := 0.0  # where the streak of light is, from 0 (left) to 1 (right); <0 while waiting
var _back: Control
var _front: Control
var _title_label: Label
var _subtitle_label: Label


func _init() -> void:
	focus_mode = Control.FOCUS_NONE
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND


func _ready() -> void:
	_time = randf() * 10.0
	_shine = -randf_range(0.5, SHINE_EVERY)
	for state_name: String in ["normal", "hover", "pressed", "disabled"]:
		add_theme_stylebox_override(state_name, _box(state_name))
	add_theme_stylebox_override("focus", StyleBoxEmpty.new())

	_back = _layer(_draw_back)
	_title_label = Label.new()
	_title_label.text = title
	_title_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title_label.add_theme_font_override("font", Ui.bold_font)
	_title_label.add_theme_color_override("font_color", Color.WHITE)
	_title_label.add_theme_color_override("font_outline_color", color.darkened(0.55))
	_title_label.add_theme_constant_override("outline_size", 10)
	_title_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.35))
	_title_label.add_theme_constant_override("shadow_offset_y", 4)
	add_child(_title_label)
	_subtitle_label = Label.new()
	_subtitle_label.text = subtitle
	_subtitle_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_subtitle_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_subtitle_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_subtitle_label.add_theme_color_override("font_color", Color(1, 1, 1, 0.92))
	_subtitle_label.add_theme_color_override("font_outline_color", color.darkened(0.45))
	_subtitle_label.add_theme_constant_override("outline_size", 4)
	add_child(_subtitle_label)
	_front = _layer(_draw_front)

	resized.connect(_layout)
	_layout()


func _process(delta: float) -> void:
	if not is_visible_in_tree():
		return
	_time += delta
	_shine += delta / SHINE_SECONDS
	if _shine > 1.4:
		_shine = -SHINE_EVERY / SHINE_SECONDS
	_back.queue_redraw()
	_front.queue_redraw()


func _layer(draw: Callable) -> Control:
	var layer := Control.new()
	layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.draw.connect(draw)
	add_child(layer)
	return layer


func _layout() -> void:
	for layer: Control in [_back, _front]:
		layer.position = Vector2.ZERO
		layer.size = size
	var title_size := int(clampf(size.y * 0.1, 26.0, 50.0))
	_title_label.add_theme_font_size_override("font_size", title_size)
	_title_label.size = Vector2(size.x, title_size * 1.3)
	_title_label.position = Vector2(0.0, size.y * 0.54)
	var subtitle_size := int(clampf(size.y * 0.045, 15.0, 21.0))
	_subtitle_label.add_theme_font_size_override("font_size", subtitle_size)
	_subtitle_label.size = Vector2(size.x - 48.0, subtitle_size * 2.6)
	_subtitle_label.position = Vector2(24.0, _title_label.position.y + _title_label.size.y)


# The picture's square: in the upper half, floating gently.
func _picture_rect() -> Rect2:
	var side := minf(size.x * 0.5, size.y * 0.4)
	var bob := sin(_time * 1.8) * size.y * 0.012
	return Rect2(Vector2((size.x - side) / 2.0, size.y * 0.3 - side / 2.0 + bob), Vector2(side, side))


# The action pill along the bottom.
func _pill_rect() -> Rect2:
	var pill := Vector2(minf(size.x * 0.62, 280.0), clampf(size.y * 0.11, 40.0, 54.0))
	return Rect2(Vector2((size.x - pill.x) / 2.0, size.y - pill.y - size.y * 0.055), pill)


# Under the picture: a glossy upper half, faint dots, and rays turning behind the picture.
func _draw_back() -> void:
	var gloss := StyleBoxFlat.new()
	gloss.bg_color = Color(1, 1, 1, 0.1)
	gloss.set_corner_radius_all(RADIUS - 6)
	gloss.anti_aliasing = true
	_back.draw_style_box(gloss, Rect2(8.0, 8.0, size.x - 16.0, size.y * 0.5))
	var step := 24.0
	var y := 34.0
	while y < size.y - 30.0:
		var x := 34.0
		while x < size.x - 30.0:
			_back.draw_circle(Vector2(x, y), 2.0, Color(1, 1, 1, 0.07), true, -1.0, true)
			x += step
		y += step

	var art := _picture_rect()
	var middle := art.get_center()
	var reach := art.size.x * 0.95
	for ray in 12:
		var angle := _time * 0.35 + ray * TAU / 12.0
		var points := PackedVector2Array([
			middle, middle + Vector2.from_angle(angle - 0.11) * reach, middle + Vector2.from_angle(angle + 0.11) * reach,
		])
		_back.draw_colored_polygon(points, Color(1, 1, 1, 0.08))
	_back.draw_circle(middle, art.size.x * 0.45, Color(1, 1, 1, 0.12), true, -1.0, true)

	# A soft shadow under the floating picture, smaller when it is higher
	var lift := (sin(_time * 1.8) + 1.0) / 2.0
	_back.draw_set_transform(Vector2(middle.x, art.end.y + 4.0), 0.0, Vector2(1.0, 0.22))
	_back.draw_circle(Vector2.ZERO, art.size.x * (0.34 - lift * 0.04), Color(0, 0, 0, 0.22), true, -1.0, true)
	_back.draw_set_transform(Vector2.ZERO)


# Over everything: the picture, the tags, the action pill and the streak of light.
func _draw_front() -> void:
	if picture != null:
		_front.draw_texture_rect(picture, _picture_rect(), false)

	var font := Ui.bold_font
	var tag_size := int(clampf(size.y * 0.036, 13.0, 17.0))
	for index in mini(tags.size(), 2):
		var text := tags[index]
		var light := live and index == 0
		var text_width := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, tag_size).x
		var tag := Vector2(text_width + 24.0 + (16.0 if light else 0.0), tag_size + 14.0)
		var at := Vector2(16.0, 16.0) if index == 0 else Vector2(size.x - 16.0 - tag.x, 16.0)
		_front.draw_style_box(Ui.box(Color(0, 0, 0, 0.32), int(tag.y / 2.0), 0, 0), Rect2(at, tag))
		var left := at.x + 12.0
		if light:
			var blink := 0.55 + 0.45 * sin(_time * 4.0)
			_front.draw_circle(Vector2(left + 5.0, at.y + tag.y / 2.0), 5.0, Color(0.4, 1.0, 0.5, blink), true, -1.0, true)
			left += 16.0
		var baseline := at.y + (tag.y + font.get_ascent(tag_size) - font.get_descent(tag_size)) / 2.0
		_front.draw_string(font, Vector2(left, baseline), text, HORIZONTAL_ALIGNMENT_LEFT, -1, tag_size, Color.WHITE)

	# The pill breathes a little, to say "tap me"
	var pill := _pill_rect()
	var breath := 1.0 + 0.025 * sin(_time * 3.2)
	pill = Rect2(pill.get_center() - pill.size * breath / 2.0, pill.size * breath)
	var pill_box := Ui.box(Color.WHITE, int(pill.size.y / 2.0), 0, 0)
	pill_box.border_color = Ui.GOLD
	pill_box.border_width_bottom = 4
	pill_box.shadow_color = Color(0, 0, 0, 0.3)
	pill_box.shadow_size = 4
	pill_box.shadow_offset = Vector2(0, 3)
	_front.draw_style_box(pill_box, pill)
	var pill_font := int(pill.size.y * 0.46)
	var baseline := pill.position.y + (pill.size.y + font.get_ascent(pill_font) - font.get_descent(pill_font)) / 2.0
	_front.draw_string(font, Vector2(pill.position.x, baseline - 1.0), action, HORIZONTAL_ALIGNMENT_CENTER, pill.size.x, pill_font, color.darkened(0.3))

	_draw_shine()


# A slanted band of light crossing the card, kept inside its rounded edge.
func _draw_shine() -> void:
	if _shine < 0.0 or _shine > 1.4:
		return
	var x := lerpf(-size.x * 0.4, size.x * 1.2, _shine / 1.4)
	var slant := size.y * 0.35
	var band := PackedVector2Array([
		Vector2(x, 0.0), Vector2(x + size.x * 0.16, 0.0), Vector2(x + size.x * 0.16 - slant, size.y), Vector2(x - slant, size.y),
	])
	for piece: PackedVector2Array in Geometry2D.intersect_polygons(band, _rounded_outline(Rect2(Vector2(4, 4), size - Vector2(8, 12)), RADIUS - 4)):
		_front.draw_colored_polygon(piece, Color(1, 1, 1, 0.16))


static func _rounded_outline(rect: Rect2, radius: float) -> PackedVector2Array:
	var points := PackedVector2Array()
	var corners := [
		[rect.position + Vector2(radius, radius), PI], [Vector2(rect.end.x - radius, rect.position.y + radius), PI * 1.5],
		[rect.end - Vector2(radius, radius), 0.0], [Vector2(rect.position.x + radius, rect.end.y - radius), PI * 0.5],
	]
	for corner: Array in corners:
		for step in 7:
			points.append(corner[0] + Vector2.from_angle(corner[1] + step * PI / 12.0) * radius)
	return points


# The card's box: its colour, a darker rim that is thicker at the bottom, a soft shadow.
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
	style.set_corner_radius_all(RADIUS)
	style.border_color = color.darkened(0.38)
	style.set_border_width_all(3)
	style.border_width_bottom = 9
	style.shadow_color = Color(0, 0, 0, 0.38)
	style.shadow_size = 8
	style.shadow_offset = Vector2(0, 5)
	style.anti_aliasing = true
	return style
