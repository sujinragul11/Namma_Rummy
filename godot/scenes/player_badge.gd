class_name PlayerBadge
extends HBoxContainer
## A player's seat marker: a round avatar with the first letter of the name, the turn clock
## drawn as a ring around it, and two lines of text (name, and what the player is doing).

const AVATAR_COLORS: Array[Color] = [
	Color("1e88e5"), Color("8e24aa"), Color("d81b60"), Color("f4511e"), Color("00897b"), Color("5c6bc0"),
]
const RING_WIDTH := 5.0

## Size of the avatar circle, ring included.
var avatar_size := 58.0:
	set(value):
		avatar_size = value
		if _avatar != null:
			_avatar.custom_minimum_size = Vector2(value, value)

## Fixed width for the name, longer names are cut with "…". 0 lets the name take what it needs.
var name_width := 0.0:
	set(value):
		name_width = value
		_name_label.clip_text = value > 0.0
		_name_label.custom_minimum_size.x = value

## A dark rounded box behind the two lines of text, for badges that lie on the felt.
var pill := false:
	set(value):
		pill = value
		if _lines_box != null:
			_lines_box.add_theme_stylebox_override("panel", Ui.box(Color(0, 0, 0, 0.5), 18, 14, 4) if value else StyleBoxEmpty.new())

var _player_name := ""
var _is_turn := false
var _avatar: Control
var _lines_box: PanelContainer
var _name_label: Label
var _info_label: Label


func _init() -> void:
	add_theme_constant_override("separation", 10)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	_avatar = Control.new()
	_avatar.custom_minimum_size = Vector2(avatar_size, avatar_size)
	_avatar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_avatar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_avatar.draw.connect(_draw_avatar)
	add_child(_avatar)

	var lines := VBoxContainer.new()
	lines.add_theme_constant_override("separation", -2)
	lines.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	lines.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_name_label = Label.new()
	_name_label.add_theme_font_size_override("font_size", 22)
	_name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	lines.add_child(_name_label)
	_info_label = Label.new()
	_info_label.add_theme_font_size_override("font_size", 18)
	_info_label.add_theme_color_override("font_color", Color("c8e6c9"))
	lines.add_child(_info_label)
	_lines_box = PanelContainer.new()
	_lines_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_lines_box.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_lines_box.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	_lines_box.add_child(lines)
	add_child(_lines_box)


## `sitting_out` greys the badge: dropped, eliminated or offline.
func show_player(player_name: String, info: String, is_turn: bool, sitting_out: bool = false) -> void:
	var turn_started := is_turn and not _is_turn
	_player_name = player_name
	_is_turn = is_turn
	_name_label.text = player_name
	_name_label.add_theme_color_override("font_color", Color("ffca28") if is_turn else Color.WHITE)
	_info_label.text = info
	modulate.a = 0.5 if sitting_out else 1.0
	_avatar.queue_redraw()
	if turn_started and is_inside_tree():
		# A small bounce when the turn arrives
		_avatar.pivot_offset = _avatar.size / 2.0
		var tween := _avatar.create_tween()
		tween.tween_property(_avatar, "scale", Vector2(1.18, 1.18), 0.14)
		tween.tween_property(_avatar, "scale", Vector2.ONE, 0.2)


## Where cards fly to and from: the middle of the avatar, in global coordinates.
func avatar_center() -> Vector2:
	return _avatar.global_position + _avatar.size / 2.0


func _process(_delta: float) -> void:
	if _is_turn:
		_avatar.queue_redraw()  # the clock ring keeps shrinking


func _draw_avatar() -> void:
	var center := _avatar.size / 2.0
	var radius := minf(center.x, center.y) - RING_WIDTH - 2.0
	var color := AVATAR_COLORS[absi(hash(_player_name)) % AVATAR_COLORS.size()]
	_avatar.draw_circle(center, radius, color, true, -1.0, true)

	var letter := _player_name.substr(0, 1).to_upper()
	var font := get_theme_default_font()
	var font_size := int(radius * 1.05)
	var baseline := center.y + (font.get_ascent(font_size) - font.get_descent(font_size)) / 2.0
	_avatar.draw_string(font, Vector2(0, baseline), letter, HORIZONTAL_ALIGNMENT_CENTER, _avatar.size.x, font_size, Color.WHITE)

	if not _is_turn:
		return
	# The turn clock: a full ring that empties clockwise, turning red near the end
	var ring_radius := radius + RING_WIDTH / 2.0 + 2.0
	var left := Game.turn_fraction()
	_avatar.draw_arc(center, ring_radius, 0.0, TAU, 48, Color(1, 1, 1, 0.22), RING_WIDTH, true)
	var ring_color := Color("ffca28") if left > 0.34 else Color("ff5252")
	if left > 0.0:
		_avatar.draw_arc(center, ring_radius, -PI / 2.0, -PI / 2.0 + TAU * left, 48, ring_color, RING_WIDTH, true)
