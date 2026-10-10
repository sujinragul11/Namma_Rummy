class_name CardView
extends Control
## One playing card, drawn in code: it needs no image files and no symbol fonts,
## so it looks the same on every device and stays sharp at any size.
##
## A card can be tapped, and (when `draggable`) picked up and carried with a finger.

signal tapped(card_id: String)
signal drag_started(card_id: String)
## `pointer` is where the finger is, in global coordinates.
signal dragged(card_id: String, pointer: Vector2)
signal dropped(card_id: String, pointer: Vector2)

const HEIGHT_RATIO := 1.4
## How far a finger must travel before a press becomes a drag instead of a tap.
const DRAG_THRESHOLD := 16.0
const RED := Color("d32f2f")
const BLACK := Color("212121")
const PURPLE := Color("6a1b9a")
const BLUE := Color("2196f3")
const AMBER := Color("ffc107")
const GREY := Color("9e9e9e")

## The card as the server sends it. Empty shows an empty slot.
var card: Dictionary = {}:
	set(value):
		card = value
		queue_redraw()

var face_down := false:
	set(value):
		face_down = value
		queue_redraw()

var selected := false:
	set(value):
		selected = value
		queue_redraw()

## An amber outline: the card just drawn, or a pile that can be picked from.
var highlighted := false:
	set(value):
		highlighted = value
		queue_redraw()

## Marks a card that counts as a joker this round.
var wild := false:
	set(value):
		wild = value
		queue_redraw()

## Cards that are only shown (the joker, result rows) let taps pass through.
var interactive := true:
	set(value):
		interactive = value
		mouse_filter = Control.MOUSE_FILTER_STOP if value else Control.MOUSE_FILTER_IGNORE

var draggable := false

## Where the finger went down on the card, in global coordinates. Whoever carries the card
## keeps this spot of it under the finger.
var pressed_at := Vector2.ZERO

var _glide: Tween
var _pressed := false
var _dragging := false


static func height_for(width: float) -> float:
	return roundf(width * HEIGHT_RATIO)


func set_width(width: float) -> void:
	custom_minimum_size = Vector2(width, height_for(width))
	size = custom_minimum_size
	pivot_offset = size / 2.0  # so turning over and growing happen around the middle


## Slides the card to a new place inside its parent.
func glide_to(target: Vector2, seconds: float = 0.25, delay: float = 0.0) -> void:
	stop_gliding()
	_glide = create_tween()
	if delay > 0.0:
		_glide.tween_interval(delay)
	_glide.tween_property(self, "position", target, seconds).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)


func stop_gliding() -> void:
	if _glide != null:
		_glide.kill()
		_glide = null


## Shows the back now and turns the card over after `delay` seconds.
func reveal_after(delay: float) -> void:
	face_down = true
	var tween := create_tween()
	tween.tween_interval(delay)
	tween.tween_property(self, "scale:x", 0.0, 0.09)
	tween.tween_callback(func() -> void: face_down = false)
	tween.tween_property(self, "scale:x", 1.0, 0.09)


func _gui_input(event: InputEvent) -> void:
	var click := event as InputEventMouseButton
	if click != null and click.button_index == MOUSE_BUTTON_LEFT:
		accept_event()
		if click.pressed:
			_pressed = true
			_dragging = false
			pressed_at = click.global_position
		elif _pressed:
			_pressed = false
			var id := str(card.get("id", ""))
			if _dragging:
				_dragging = false
				dropped.emit(id, click.global_position)
			else:
				tapped.emit(id)
		return

	var motion := event as InputEventMouseMotion
	if motion != null and _pressed:
		var id := str(card.get("id", ""))
		if not _dragging and draggable and motion.global_position.distance_to(pressed_at) > DRAG_THRESHOLD:
			_dragging = true
			drag_started.emit(id)
		if _dragging:
			accept_event()
			dragged.emit(id, motion.global_position)


func _draw() -> void:
	var w := size.x
	var h := size.y
	var radius := int(w * 0.1)
	var whole := Rect2(Vector2.ZERO, size)

	if card.is_empty() and not face_down:
		# An empty slot, e.g. no open card yet
		var slot := _box(Color(1, 1, 1, 0.06), radius)
		slot.border_color = Color(1, 1, 1, 0.45)
		slot.set_border_width_all(2)
		draw_style_box(slot, whole)
		return

	if face_down:
		var back := _box(Color("1565c0"), radius)
		back.border_color = AMBER if highlighted else Color.WHITE
		back.set_border_width_all(maxi(3, int(w * 0.035)))
		_add_shadow(back, w)
		draw_style_box(back, whole)
		var inset := w * 0.13
		var pattern := _box(Color("1976d2"), int(radius * 0.6))
		pattern.border_color = Color(1, 1, 1, 0.55)
		pattern.set_border_width_all(2)
		draw_style_box(pattern, Rect2(inset, inset, w - inset * 2.0, h - inset * 2.0))
		_draw_suit("♠", Vector2(w * 0.5, h * 0.5), w * 0.16, Color(1, 1, 1, 0.5))
		return

	var face := _box(Color.WHITE, radius)
	face.border_color = BLUE if selected else (AMBER if highlighted else GREY)
	face.set_border_width_all(maxi(3, int(w * 0.035)) if selected or highlighted else 1)
	_add_shadow(face, w)
	draw_style_box(face, whole)

	var font := get_theme_default_font()
	if card.get("isJoker", false):
		_draw_star(Vector2(w * 0.25, w * 0.27), w * 0.17, PURPLE)
		var joker_size := int(w * 0.2)
		draw_string(font, Vector2(0, h - w * 0.14), "JOKER", HORIZONTAL_ALIGNMENT_CENTER, w, joker_size, PURPLE)
		return

	var suit := str(card.get("suit", ""))
	var value := str(card.get("value", ""))
	var color := RED if suit in ["♥", "♦"] else BLACK

	# Rank and a small suit in the top-left corner, which stays visible when cards overlap
	var rank_size := int(w * (0.3 if value.length() > 1 else 0.36))
	draw_string(font, Vector2(w * 0.08, w * 0.05 + font.get_ascent(rank_size)), value, HORIZONTAL_ALIGNMENT_LEFT, -1, rank_size, color)
	_draw_suit(suit, Vector2(w * 0.22, w * 0.64), w * 0.13, color)
	_draw_suit(suit, Vector2(w * 0.64, h - w * 0.36), w * 0.27, color)

	if wild:
		var badge := Vector2(w * 0.2, h - w * 0.2)
		draw_circle(badge, w * 0.13, AMBER, true, -1.0, true)
		var badge_size := int(w * 0.18)
		draw_string(font, Vector2(badge.x - w * 0.13, badge.y + badge_size * 0.36), "J", HORIZONTAL_ALIGNMENT_CENTER, w * 0.26, badge_size, BLACK)


func _box(color: Color, radius: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.set_corner_radius_all(radius)
	style.anti_aliasing = true
	return style


# A soft shadow, so overlapping cards read as lying on top of one another.
func _add_shadow(style: StyleBoxFlat, width: float) -> void:
	style.shadow_color = Color(0, 0, 0, 0.28)
	style.shadow_size = maxi(2, int(width * 0.04))
	style.shadow_offset = Vector2(-1, 2)


# Draws a suit symbol that fits in a circle of radius `r` around `center`.
func _draw_suit(suit: String, center: Vector2, r: float, color: Color) -> void:
	match suit:
		"♦":
			_fill([Vector2(0, -r), Vector2(r * 0.74, 0), Vector2(0, r), Vector2(-r * 0.74, 0)], center, color)
		"♥":
			draw_circle(center + Vector2(-r * 0.48, -r * 0.34), r * 0.54, color, true, -1.0, true)
			draw_circle(center + Vector2(r * 0.48, -r * 0.34), r * 0.54, color, true, -1.0, true)
			_fill([Vector2(-r * 0.96, -r * 0.1), Vector2(r * 0.96, -r * 0.1), Vector2(0, r)], center, color)
		"♠":
			draw_circle(center + Vector2(-r * 0.46, r * 0.14), r * 0.52, color, true, -1.0, true)
			draw_circle(center + Vector2(r * 0.46, r * 0.14), r * 0.52, color, true, -1.0, true)
			_fill([Vector2(-r * 0.93, -r * 0.08), Vector2(r * 0.93, -r * 0.08), Vector2(0, -r)], center, color)
			_fill([Vector2(0, r * 0.15), Vector2(-r * 0.36, r), Vector2(r * 0.36, r)], center, color)
		"♣":
			draw_circle(center + Vector2(0, -r * 0.5), r * 0.46, color, true, -1.0, true)
			draw_circle(center + Vector2(-r * 0.52, r * 0.16), r * 0.46, color, true, -1.0, true)
			draw_circle(center + Vector2(r * 0.52, r * 0.16), r * 0.46, color, true, -1.0, true)
			draw_circle(center, r * 0.3, color, true, -1.0, true)  # closes the gap between the three leaves
			_fill([Vector2(0, -r * 0.1), Vector2(-r * 0.34, r), Vector2(r * 0.34, r)], center, color)


func _draw_star(center: Vector2, r: float, color: Color) -> void:
	var points: Array = []
	for index in 10:
		var length := r if index % 2 == 0 else r * 0.45
		points.append(Vector2.UP.rotated(index * TAU / 10.0) * length)
	_fill(points, center, color)


# A filled shape with smoothed edges. `offsets` are relative to `center`.
func _fill(offsets: Array, center: Vector2, color: Color) -> void:
	var points := PackedVector2Array()
	for offset: Vector2 in offsets:
		points.append(center + offset)
	draw_colored_polygon(points, color)
	points.append(points[0])
	draw_polyline(points, color, 1.0, true)
