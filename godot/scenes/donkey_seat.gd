class_name DonkeySeat
extends Control
## One player at the Donkey Master table, drawn in code: the round picture with the turn
## clock around it (and a gold glow while it is their turn), the name on a dark pill under it,
## a little stack of cards with how many they hold, and a tag over the picture saying where
## they stand: playing, Master, out in 3rd place, the Donkey, away, offline, left.
## The seat's position is the middle of the picture.
##
## It is drawn in three layers, back to front: the glow and the speaking ring on the seat
## itself, the picture on a child of its own (`picture()`: what is thrown at the player makes
## it squash and tilt, as on rummy's PlayerBadge), then the cards, the name and the tag.

const SIZE := Vector2(156, 132)
const RADIUS := 32.0
const RING := 5.0
const TURN_GOLD := Color("ffca28")
const SAFE_GREEN := Color("43a047")
const DONKEY_BROWN := Color("8d6e63")

## The player as the table state lists them.
var player: Dictionary = {}:
	set(value):
		player = value
		_redraw()
## True while it is this player's turn; the seat bounces when it comes.
var is_turn := false:
	set(value):
		if value and not is_turn and is_inside_tree():
			_bounce()
		is_turn = value
## Voice chat (TableVoice sets these, as on rummy's PlayerBadge): how loud the player is
## speaking, 0 to 1, for a green ring round the picture, and whether their microphone is on,
## for a small microphone on it.
var voice_level := 0.0:
	set(value):
		if not is_equal_approx(value, voice_level):
			voice_level = value
			_redraw()
var mic_on := false:
	set(value):
		if value != mic_on:
			mic_on = value
			_redraw()
var _photo: Texture2D
var _photo_key := ""
var _time := 0.0
var _glow := 0.0
var _picture: Control  # the round picture, over the seat
var _front: Control  # the cards, the name and the tag, over the picture


func _init() -> void:
	size = SIZE
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	pivot_offset = Vector2(SIZE.x / 2.0, avatar_center_y())
	_picture = Control.new()
	_picture.name = "Picture"
	_picture.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_picture.size = Vector2.ONE * (RADIUS + RING) * 2.0
	_picture.position = Vector2(SIZE.x / 2.0, avatar_center_y()) - _picture.size / 2.0
	_picture.pivot_offset = _picture.size / 2.0
	_picture.draw.connect(_draw_picture)
	add_child(_picture)
	_front = Control.new()
	_front.name = "Front"
	_front.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_front.size = SIZE
	_front.draw.connect(_draw_front)
	add_child(_front)


func _ready() -> void:
	Game.avatar_loaded.connect(func(user_id: String) -> void:
		if user_id == str(player.get("id", "")):
			_photo_key = ""
			_redraw())


static func avatar_center_y() -> float:
	return 26.0 + RADIUS + RING


## Puts the middle of the picture at `at` (in the parent's coordinates).
func place_at(at: Vector2) -> void:
	position = at - Vector2(SIZE.x / 2.0, avatar_center_y())


## The middle of the picture, in global coordinates: where cards fly to and from.
func avatar_center() -> Vector2:
	return global_position + Vector2(SIZE.x / 2.0, avatar_center_y())


## The round picture itself, for things that make it react (TableThrows squashes and tilts it,
## and always lets it come back to its own size and colour).
func picture() -> Control:
	return _picture


## Where a small throw button may sit on the seat itself when there is no room beside it
## (TableThrows asks): left of the picture, which is empty. The cards and their count are on
## its right, and the microphone on its lower left. In global coordinates.
func throw_spot(button_size: Vector2) -> Rect2:
	var picture_left := SIZE.x / 2.0 - RADIUS - RING
	var at := Vector2(maxf(0.0, picture_left - button_size.x - 1.0), avatar_center_y() - button_size.y / 2.0)
	return Rect2(global_position + at, button_size)


## The little stack of cards and their count at the picture's lower right, in global coordinates.
func cards_rect() -> Rect2:
	var corner := Vector2(SIZE.x / 2.0, avatar_center_y()) + Vector2(RADIUS * 0.72, RADIUS * 0.3)
	return Rect2(global_position + corner + Vector2(-13.0, -20.0), Vector2(46.0, 48.0))


func _process(delta: float) -> void:
	_time += delta
	var target := 1.0 if is_turn else 0.0
	if not is_equal_approx(_glow, target):
		_glow = move_toward(_glow, target, delta * 4.0)
	if is_turn or _glow > 0.0:
		_redraw()


func _redraw() -> void:
	queue_redraw()
	if _picture != null:
		_picture.queue_redraw()
		_front.queue_redraw()


func _bounce() -> void:
	var tween := create_tween()
	tween.tween_property(self, "scale", Vector2(1.14, 1.14), 0.13)
	tween.tween_property(self, "scale", Vector2.ONE, 0.2)


## A quick swell, e.g. when the player picks up a trick.
func pulse() -> void:
	_bounce()


# Behind the picture: the glow of the player on turn and the ring of a player speaking.
func _draw() -> void:
	if player.is_empty():
		return
	var center := Vector2(SIZE.x / 2.0, avatar_center_y())
	var left: bool = player.get("left", false)
	modulate.a = 0.45 if left or not player.get("connected", true) else 1.0

	# The glow of the player on turn, breathing
	if _glow > 0.0:
		var breath := 0.5 + 0.5 * sin(_time * 5.0)
		for layer in 6:
			draw_circle(center, RADIUS + RING + 5.0 + breath * 5.0 + layer * 2.5, Color(TURN_GOLD, (0.26 - layer * 0.04) * _glow), true, -1.0, true)

	# Speaking: a green ring outside the turn clock, swelling with the voice, on a soft halo
	if voice_level > 0.0:
		var speaking := RADIUS + RING + 6.0 + 3.0 * voice_level
		draw_circle(center, speaking + 3.0, Color(TableVoice.SPEAKING_GREEN, 0.22 * voice_level), true, -1.0, true)
		draw_arc(center, speaking, 0.0, TAU, 48, Color(TableVoice.SPEAKING_GREEN, 0.55 + 0.45 * voice_level), 2.5 + 1.5 * voice_level, true)


# The picture, on its own layer: drawn round the middle of _picture.
func _draw_picture() -> void:
	if player.is_empty():
		return
	var canvas := _picture
	var id := str(player.get("id", ""))
	var username := str(player.get("username", "Player"))
	var center := _picture.size / 2.0
	var place := int(player.get("place", 0))
	var donkey: bool = player.get("donkey", false)

	# The picture: the photo, or a coloured disc with the first letter
	var rim := TURN_GOLD if is_turn else (SAFE_GREEN if place > 0 else (DONKEY_BROWN if donkey else Color(1, 1, 1, 0.85)))
	canvas.draw_circle(center, RADIUS + 3.0, rim, true, -1.0, true)
	var version := int(player.get("avatar", 0))
	var key := "%s-%d" % [id, version]
	if key != _photo_key:
		_photo_key = key
		_photo = Game.avatar_texture(id, version)
	if _photo != null:
		PlayerBadge.draw_photo(canvas, center, RADIUS, _photo)
	else:
		var color: Color = PlayerBadge.AVATAR_COLORS[absi(hash(username)) % PlayerBadge.AVATAR_COLORS.size()]
		canvas.draw_circle(center, RADIUS, color, true, -1.0, true)
		_text_centered(canvas, username.substr(0, 1).to_upper(), center, int(RADIUS * 1.05), Color.WHITE)
	if donkey:
		var side := RADIUS * 2.1
		canvas.draw_texture_rect(DonkeyHome.picture("donkey"), Rect2(center - Vector2(side, side) / 2.0, Vector2(side, side)), false)
	elif place == 1:
		# The crown sits tilted on the picture's upper left, clear of the tag above it
		var side := RADIUS * 1.1
		canvas.draw_set_transform(center + Vector2(-RADIUS * 0.78, -RADIUS * 0.62), deg_to_rad(-24.0))
		canvas.draw_texture_rect(DonkeyHome.picture("crown"), Rect2(Vector2(-side, -side) / 2.0, Vector2(side, side)), false)
		canvas.draw_set_transform(Vector2.ZERO)

	# The turn clock: a ring that empties clockwise, red near the end
	if is_turn:
		var ring_radius := RADIUS + RING / 2.0 + 3.0
		var time_left := Game.donkey.turn_fraction()
		canvas.draw_arc(center, ring_radius, 0.0, TAU, 48, Color(0, 0, 0, 0.45), RING + 3.0, true)
		if time_left > 0.0:
			canvas.draw_arc(center, ring_radius, -PI / 2.0, -PI / 2.0 + TAU * time_left, 48, TURN_GOLD if time_left > 0.34 else Color("ff5252"), RING, true)

	# Voice chat: a microphone on a green disc at the lower left, a little bigger while speaking
	if mic_on:
		var spot := center + Vector2(-RADIUS, RADIUS) * 0.72
		var disc := maxf(RADIUS * 0.36, 9.0) * (1.0 + 0.18 * voice_level)
		canvas.draw_circle(spot, disc + 2.0, Color("0b2e17"), true, -1.0, true)
		canvas.draw_circle(spot, disc, TableVoice.MIC_GREEN.lerp(TableVoice.SPEAKING_GREEN, voice_level * 0.6), true, -1.0, true)
		TableVoice.draw_mic(canvas, spot + Vector2(0, -0.6), disc / 11.0, Color.WHITE)


# In front of the picture: the cards they hold, their name and the tag.
func _draw_front() -> void:
	if player.is_empty():
		return
	var canvas := _front
	var id := str(player.get("id", ""))
	var username := str(player.get("username", "Player"))
	var left: bool = player.get("left", false)
	var center := Vector2(SIZE.x / 2.0, avatar_center_y())
	var place := int(player.get("place", 0))
	var donkey: bool = player.get("donkey", false)

	# How many cards they hold: a small fanned stack at the lower right of the picture
	var cards := int(player.get("cards", 0))
	if cards > 0:
		var corner := center + Vector2(RADIUS * 0.72, RADIUS * 0.3)
		for back in mini(3, cards):
			canvas.draw_set_transform(corner + Vector2(back * 4.0, -back * 1.5), deg_to_rad(-8.0 + back * 9.0))
			var card_box := Ui.box(Color("1565c0"), 4, 0, 0)
			card_box.border_color = Color.WHITE
			card_box.set_border_width_all(2)
			canvas.draw_style_box(card_box, Rect2(Vector2(-11, -16), Vector2(22, 32)))
			canvas.draw_set_transform(Vector2.ZERO)
		var badge := corner + Vector2(18.0, 14.0)
		canvas.draw_circle(badge, 13.0, Color("0b2e17"), true, -1.0, true)
		canvas.draw_circle(badge, 11.0, Ui.GOLD, true, -1.0, true)
		_text_centered(canvas, str(cards), badge, 15 if cards < 10 else 13, Color("3e2723"))

	# The name on a dark pill under the picture
	var font := Ui.bold_font
	var pill := Rect2(Vector2(4.0, center.y + RADIUS + RING + 4.0), Vector2(SIZE.x - 8.0, 26.0))
	var pill_box := Ui.box(Color(0.3, 0.2, 0.0, 0.9) if is_turn else Color(0, 0, 0, 0.55), 13, 0, 0)
	if is_turn:
		pill_box.border_color = TURN_GOLD
		pill_box.set_border_width_all(2)
	canvas.draw_style_box(pill_box, pill)
	var name_text := "You" if id == Game.player_id else username
	canvas.draw_string(font, Vector2(pill.position.x + 6.0, pill.get_center().y + 6.0), name_text, HORIZONTAL_ALIGNMENT_CENTER, pill.size.x - 12.0, 17, TURN_GOLD if is_turn else Color.WHITE)

	# The tag over the picture
	var tag := ""
	var fill := Color(0, 0, 0, 0.75)
	var ink := Color.WHITE
	if donkey:
		tag = "DONKEY"
		fill = DONKEY_BROWN
	elif place == 1:
		tag = "MASTER"
		fill = TURN_GOLD
		ink = Color("3e2723")
	elif place > 0:
		tag = "SAFE  ·  %s" % ordinal(place)
		fill = SAFE_GREEN
	elif left:
		tag = "LEFT"
	elif not player.get("connected", true):
		tag = "OFFLINE"
	elif is_turn:
		tag = "YOUR TURN" if id == Game.player_id else "PLAYING"
		fill = TURN_GOLD
		ink = Color("3e2723")
	elif player.get("away", false):
		tag = "AWAY"
		fill = Color("ef6c00")
	if tag.is_empty():
		return
	var lift := 3.0 * sin(_time * 6.0) if is_turn else 0.0
	var width := font.get_string_size(tag, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x + 20.0
	var tag_rect := Rect2(Vector2((SIZE.x - width) / 2.0, 2.0 - lift), Vector2(width, 22.0))
	canvas.draw_style_box(Ui.box(fill, 11, 0, 0), tag_rect)
	canvas.draw_string(font, Vector2(tag_rect.position.x, tag_rect.position.y + 16.0), tag, HORIZONTAL_ALIGNMENT_CENTER, tag_rect.size.x, 14, ink)


func _text_centered(canvas: CanvasItem, text: String, at: Vector2, font_size: int, color: Color) -> void:
	var font := Ui.bold_font
	var baseline := at.y + (font.get_ascent(font_size) - font.get_descent(font_size)) / 2.0
	canvas.draw_string(font, Vector2(at.x - 40.0, baseline), text, HORIZONTAL_ALIGNMENT_CENTER, 80.0, font_size, color)


## 1 -> "1st", 2 -> "2nd", 3 -> "3rd", 4 -> "4th".
static func ordinal(number: int) -> String:
	var suffix := "th"
	if number % 100 < 11 or number % 100 > 13:
		suffix = {1: "st", 2: "nd", 3: "rd"}.get(number % 10, "th")
	return "%d%s" % [number, suffix]
