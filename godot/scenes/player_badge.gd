class_name PlayerBadge
extends HBoxContainer
## A player's seat marker: a round avatar with the first letter of the name, the turn clock
## drawn as a ring around it, and two lines of text (name, and what the player is doing).
## The player on turn is lit up: a gold glow round the avatar, a glowing pill and a tag over it
## that bobs. The light eases from badge to badge as the turn moves round the table.

const AVATAR_COLORS: Array[Color] = [
	Color("1e88e5"), Color("8e24aa"), Color("d81b60"), Color("f4511e"), Color("00897b"), Color("5c6bc0"),
]
const RING_WIDTH := 5.0
const JOKER_SEEN_COLOR := Color("00e676")
const PHOTO_EDGE := 48  # corners of the circle a photo is cut to
const TURN_GOLD := Color("ffca28")
const TURN_PILL := Color(0.3, 0.2, 0.0, 0.85)  # the pill's background while lit
const GLOW_SECONDS := 0.3  # how long the light takes to come on or go out
const BEAT_SECONDS := 1.2  # one pulse of the light
const TAG_FONT_SIZE := 14
const TAG_HEIGHT := 22.0

## Words on the tag over the player on turn; our own badge says "YOUR TURN".
var turn_tag := "PLAYING"
## Words on the quieter tag over the player who plays after them.
var next_tag := "NEXT"
## This player plays after the one on turn.
var up_next := false:
	set(value):
		if value != up_next:
			up_next = value
			if _lines_box != null:
				_lines_box.queue_redraw()

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
			_light_pill()

var _player_name := ""
var _is_turn := false
var _glow := 0.0  # how lit the badge is, 0 to 1; eases in and out as the turn comes and goes
var _glow_tween: Tween
var _beat := 0.0  # seconds of light, for the pulse
var _pill_style: StyleBoxFlat
var _joker_seen := false
var _dot_grow := 1.0  # the green dot pops in from 0
var _photo: Texture2D  # the player's profile photo, drawn in place of the letter
var _photo_owner := ""  # whose photo, and which version of it
var _photo_version := 0
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
	# One box for every state: lighting it up changes its colours, never its size
	_pill_style = Ui.box(Color.TRANSPARENT, 18, 14, 4)
	_pill_style.border_color = TURN_GOLD
	_pill_style.shadow_color = TURN_GOLD
	_lines_box.add_theme_stylebox_override("panel", _pill_style)
	_lines_box.draw.connect(_draw_tag)  # over the pill, under the two lines of text
	_lines_box.add_child(lines)
	add_child(_lines_box)
	_light_pill()


## `sitting_out` greys the badge: dropped, eliminated or offline.
## `joker_seen` puts a green dot on the avatar: in Close Joker, this player has seen the joker.
func show_player(player_name: String, info: String, is_turn: bool, sitting_out: bool = false, joker_seen: bool = false) -> void:
	var turn_started := is_turn and not _is_turn
	if joker_seen and not _joker_seen and not _player_name.is_empty() and is_inside_tree():
		# It happened just now, not before we sat down: let the dot pop in so it is noticed
		_dot_grow = 0.0
		var pop := _avatar.create_tween()
		pop.tween_method(_grow_dot, 0.0, 1.0, 0.45).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_joker_seen = joker_seen
	_player_name = player_name
	if is_turn != _is_turn:
		_fade_light(1.0 if is_turn else 0.0)
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


## The player's profile photo in the circle, in place of the letter. `version` comes with the
## player from the server; 0 means no photo. Until the photo has arrived the letter shows.
func show_photo(user_id: String, version: int) -> void:
	if user_id == _photo_owner and version == _photo_version:
		return
	_photo_owner = user_id
	_photo_version = version
	if not Game.avatar_loaded.is_connected(_on_avatar_loaded):
		Game.avatar_loaded.connect(_on_avatar_loaded)
	_photo = Game.avatar_texture(user_id, version)
	_avatar.queue_redraw()


## Draws `photo` filling a circle, for every place that shows a player's picture.
static func draw_photo(canvas: CanvasItem, center: Vector2, radius: float, photo: Texture2D) -> void:
	var points := PackedVector2Array()
	var uvs := PackedVector2Array()
	for index in PHOTO_EDGE:
		var direction := Vector2.from_angle(TAU * index / PHOTO_EDGE)
		points.append(center + direction * radius)
		uvs.append(Vector2(0.5, 0.5) + direction * 0.5)
	canvas.draw_colored_polygon(points, Color.WHITE, uvs, photo)
	# A polygon's edge is not smoothed: a thin line round it is
	canvas.draw_arc(center, radius, 0.0, TAU, PHOTO_EDGE, Color(0, 0, 0, 0.3), 1.5, true)


func _on_avatar_loaded(user_id: String) -> void:
	if user_id == _photo_owner:
		_photo = Game.avatar_texture(_photo_owner, _photo_version)
		_avatar.queue_redraw()


## Where cards fly to and from: the middle of the avatar, in global coordinates.
func avatar_center() -> Vector2:
	return _avatar.global_position + _avatar.size / 2.0


## The round avatar itself, for things that make it react (TableThrows squashes and tilts it,
## and always lets it come back to its own size and colour).
func picture() -> Control:
	return _avatar


func _process(delta: float) -> void:
	if _is_turn or _glow > 0.0:
		_beat += delta
		_light_pill()
		_lines_box.queue_redraw()  # the tag bobs
		_avatar.queue_redraw()  # the clock ring keeps shrinking, the glow breathes


# The light comes on (1) or goes out (0) over a moment, so the eye can follow it to the next player.
func _fade_light(to: float) -> void:
	if _glow_tween != null:
		_glow_tween.kill()
	if not is_inside_tree():
		_glow = to
		_light_pill()
		return
	if to > 0.0:
		_beat = 0.0  # every turn starts its glow from the same point of the pulse
	_glow_tween = create_tween()
	_glow_tween.tween_property(self, "_glow", to, GLOW_SECONDS).set_trans(Tween.TRANS_SINE)
	# The last frame of a fade has to be drawn too, after _process has stopped asking
	_glow_tween.tween_callback(func() -> void:
		_light_pill()
		_lines_box.queue_redraw()
		_avatar.queue_redraw())


# The light's pulse, from 0 to 1 and back once every BEAT_SECONDS.
func _pulse() -> float:
	return 0.5 - 0.5 * cos(_beat * TAU / BEAT_SECONDS)


# The pill behind the name: dark on the felt, warm gold with a glowing edge while on turn.
func _light_pill() -> void:
	# Without a pill (lobby, profile) the text sits right beside the avatar
	_pill_style.content_margin_left = 14.0 if pill else 0.0
	_pill_style.content_margin_right = 14.0 if pill else 0.0
	_pill_style.content_margin_top = 4.0 if pill else 0.0
	_pill_style.content_margin_bottom = 4.0 if pill else 0.0
	var resting := Color(0, 0, 0, 0.5) if pill else Color.TRANSPARENT
	_pill_style.bg_color = resting.lerp(TURN_PILL, _glow)
	var lit := _glow > 0.0
	_pill_style.set_border_width_all(3 if lit else 0)
	_pill_style.border_color.a = _glow * (0.75 + 0.25 * _pulse())
	_pill_style.shadow_size = int(round((5.0 + 9.0 * _pulse()) * _glow)) if lit else 0
	_pill_style.shadow_color.a = 0.55 * _glow


# The tag over the pill: "PLAYING" (gold, bobbing) for the player on turn, "NEXT" (dark, still)
# for the player after them.
func _draw_tag() -> void:
	var text := ""
	var fill := Color.BLACK
	var ink := Color.BLACK
	var lift := 0.0
	if _glow > 0.0:
		text = turn_tag
		fill = Color(TURN_GOLD, _glow)
		ink = Color(Color("3e2723"), _glow)
		lift = 3.0 * sin(_beat * TAU / BEAT_SECONDS * 1.5)
	elif up_next:
		text = next_tag
		fill = Color(0, 0, 0, 0.78)
		ink = TURN_GOLD
	else:
		return
	var font: Font = Ui.bold_font
	var text_width := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, TAG_FONT_SIZE).x
	var tag_size := Vector2(text_width + 20.0, TAG_HEIGHT)
	# Mostly above the pill, just overlapping its top edge
	var at := Vector2((_lines_box.size.x - tag_size.x) / 2.0, -tag_size.y * 0.72 - lift)
	var style := Ui.box(fill, int(TAG_HEIGHT / 2.0), 0.0, 0.0)
	if _glow <= 0.0:
		style.border_color = Color(TURN_GOLD, 0.8)
		style.set_border_width_all(2)
	_lines_box.draw_style_box(style, Rect2(at, tag_size))
	var baseline := at.y + (tag_size.y + font.get_ascent(TAG_FONT_SIZE) - font.get_descent(TAG_FONT_SIZE)) / 2.0
	_lines_box.draw_string(font, Vector2(at.x, baseline), text, HORIZONTAL_ALIGNMENT_CENTER, tag_size.x, TAG_FONT_SIZE, ink)


func _draw_avatar() -> void:
	var center := _avatar.size / 2.0
	var radius := minf(center.x, center.y) - RING_WIDTH - 2.0
	if _glow > 0.0:
		# The glow: soft gold rings fading outwards from under the avatar, breathing in and out
		var reach := radius + RING_WIDTH + 4.0 + 6.0 * _pulse()
		for layer in 6:
			var alpha := (0.26 - layer * 0.04) * _glow
			_avatar.draw_circle(center, reach + layer * 2.5, Color(TURN_GOLD, alpha), true, -1.0, true)
	if _photo != null:
		draw_photo(_avatar, center, radius, _photo)
	else:
		var color := AVATAR_COLORS[absi(hash(_player_name)) % AVATAR_COLORS.size()]
		_avatar.draw_circle(center, radius, color, true, -1.0, true)
		var letter := _player_name.substr(0, 1).to_upper()
		var font := get_theme_default_font()
		var font_size := int(radius * 1.05)
		var baseline := center.y + (font.get_ascent(font_size) - font.get_descent(font_size)) / 2.0
		_avatar.draw_string(font, Vector2(0, baseline), letter, HORIZONTAL_ALIGNMENT_CENTER, _avatar.size.x, font_size, Color.WHITE)

	if _is_turn:
		# The turn clock: a full ring that empties clockwise, turning red near the end
		var ring_radius := radius + RING_WIDTH / 2.0 + 2.0
		var left := Game.turn_fraction()
		# A dark bed under the ring keeps the clock readable on the gold glow
		_avatar.draw_arc(center, ring_radius, 0.0, TAU, 48, Color(0, 0, 0, 0.45), RING_WIDTH + 3.0, true)
		_avatar.draw_arc(center, ring_radius, 0.0, TAU, 48, Color(1, 1, 1, 0.22), RING_WIDTH, true)
		var ring_color := Color("ffca28") if left > 0.34 else Color("ff5252")
		if left > 0.0:
			_avatar.draw_arc(center, ring_radius, -PI / 2.0, -PI / 2.0 + TAU * left, 48, ring_color, RING_WIDTH, true)

	if _joker_seen and _dot_grow > 0.0:
		# Close Joker: a green dot at the lower right, over the ring, like an "online" light
		var dot := center + Vector2(radius, radius) * 0.72
		var dot_radius := maxf(radius * 0.3, 6.0) * _dot_grow
		_avatar.draw_circle(dot, dot_radius + 2.5, Color("0b2e17"), true, -1.0, true)
		_avatar.draw_circle(dot, dot_radius, JOKER_SEEN_COLOR, true, -1.0, true)


func _grow_dot(amount: float) -> void:
	_dot_grow = amount
	_avatar.queue_redraw()
