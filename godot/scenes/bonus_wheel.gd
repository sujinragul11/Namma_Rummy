class_name BonusWheel
extends Control
## The daily bonus wheel, drawn in code like the cards and the coins: purple slots with their
## prizes inside a gold rim of lights, a "DAILY BONUS" ribbon over the top and a gold pointer.
## The slots turn; the ribbon and the pointer stay where they are. The hub in the middle is the
## Spin button (`spin_button`), which the box around the wheel connects.
##
## The prize is drawn by the server, so a spin has two parts: spin() sets the wheel turning at
## once, and land_on() brings it to rest on the slot the server named. stop() brings it to rest
## on no slot in particular, for when the server could not be asked.

## The wheel came to rest on the slot given to land_on().
signal landed(index: int)
## The wheel came to rest, with a prize or without.
signal stopped

const RIM_DARK := Color("b8730e")
const RIM := Color("ffc93c")
const RIM_LIGHT := Color("fff1a8")
const RING := Color("3a1560")
const SLOT_A := Color("9b51d6")
const SLOT_B := Color("8441c0")
const DIVIDER := Color("c79bea")
const RIBBON := Color("b25a1e")
const RIBBON_DARK := Color("5e2a0b")
const RIBBON_TEXT := Color("fff6e0")
const BULB_ON := Color("8ff5ff")
const BULB_OFF := Color("fff3c8")
const GEM := Color("2ecc71")
const HUB_LIVE := Color("ff9f1c")
const HUB_ASLEEP := Color("a89878")
const BULBS := 16
const TOP_SPEED := 14.0  # radians a second while the server is asked
const SPIN_UP := 0.35  # seconds to reach it
const LEAST_SPIN := 0.9  # seconds at least before the wheel starts slowing down
const LANDING_TURNS := 3.0  # whole turns at least while slowing down to the prize
const STOPPING_TURNS := 0.5  # and when stopping without one
const NOWHERE := -2  # `_wanted` when the wheel is to stop without a prize
# Room the ribbon and the pointer need above the wheel, and the glow below it
const ABOVE := 44.0
const BELOW := 10.0

## The coins on each slot, clockwise from the one under the pointer at rest.
var prizes: Array = []:
	set(value):
		prizes = value
		queue_redraw()
## How far the slots have turned, clockwise, in radians.
var angle := 0.0
## The hub says SPIN and glows while true; otherwise it shows `hub_text`, the time still to wait.
var hub_ready := false
var hub_text := ""
## The hub: the button in the middle that spins the wheel.
var spin_button: Button

enum Phase { REST, SPINNING, LANDING }

var _phase := Phase.REST
var _speed := 0.0
var _spinning_for := 0.0
var _wanted := -1  # the slot to land on once the wheel has spun long enough, NOWHERE, or -1
var _land_from := 0.0
var _land_by := 0.0
var _land_seconds := 1.0
var _land_elapsed := 0.0
var _land_index := -1  # the slot being landed on; -1 when stopping without a prize
var _boundary := 0  # which gap between slots is under the pointer, to tick when it changes
var _pointer_kick := 0.0  # the pointer flips back when a peg passes it, then settles
var _time := 0.0


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	spin_button = Button.new()
	spin_button.name = "SpinButton"
	spin_button.focus_mode = Control.FOCUS_NONE
	for state_name: String in ["normal", "hover", "pressed", "disabled", "focus"]:
		spin_button.add_theme_stylebox_override(state_name, StyleBoxEmpty.new())
	spin_button.draw.connect(_draw_hub)
	add_child(spin_button)
	resized.connect(_place_hub)


## True from spin() until the wheel is at rest again.
func is_turning() -> bool:
	return _phase != Phase.REST


## Sets the wheel turning, fast, until land_on() or stop().
func spin() -> void:
	if _phase != Phase.REST:
		return
	_phase = Phase.SPINNING
	_spinning_for = 0.0
	_wanted = -1


## Slows the wheel down until slot `index` is under the pointer, then emits `landed`.
func land_on(index: int) -> void:
	if prizes.is_empty():
		return
	index = posmod(index, prizes.size())
	if _phase == Phase.REST:
		spin()
	if _phase == Phase.SPINNING:
		_wanted = index  # picked up once the wheel has spun long enough to look like a spin


## Brings the wheel to rest without a prize, e.g. when the spin did not reach the server.
func stop() -> void:
	if _phase == Phase.SPINNING:
		_wanted = NOWHERE


## The slot under the pointer now.
func slot_at_pointer() -> int:
	if prizes.is_empty():
		return -1
	return posmod(roundi(-angle / _step()), prizes.size())


## Where the pointer's tip is, in this control's coordinates: where a win sparkles.
func pointer_tip() -> Vector2:
	return _center() - Vector2(0.0, _radius() - 36.0)


func _process(delta: float) -> void:
	_time += delta
	match _phase:
		Phase.SPINNING:
			_spinning_for += delta
			_speed = TOP_SPEED * smoothstep(0.0, SPIN_UP, _spinning_for)
			angle += _speed * delta
			if _wanted != -1 and _spinning_for >= LEAST_SPIN:
				_begin_landing(_wanted, LANDING_TURNS if _wanted >= 0 else STOPPING_TURNS)
		Phase.LANDING:
			_land_elapsed += delta
			var t := minf(1.0, _land_elapsed / _land_seconds)
			# Slowing down evenly to a stop: the cubic starts at the speed it was spinning at
			angle = _land_from + _land_by * (1.0 - pow(1.0 - t, 3.0))
			if t >= 1.0:
				_phase = Phase.REST
				_speed = 0.0
				if _land_index >= 0:
					landed.emit(_land_index)
				stopped.emit()
	_tick_past_pegs()
	_pointer_kick = move_toward(_pointer_kick, 0.0, delta * 6.0)
	if is_visible_in_tree():
		queue_redraw()
		spin_button.queue_redraw()


# Starts slowing down: at least `turns` more turns, ending a little off the middle of the slot,
# as a real wheel would. Slot i is under the pointer when the wheel has turned -i slots.
# NOWHERE stops on whatever slot comes, without `landed`.
func _begin_landing(index: int, turns: float) -> void:
	var step := _step()
	var rest := -index * step + randf_range(-0.3, 0.3) * step if index >= 0 else angle + randf() * TAU
	var by := fposmod(rest - angle, TAU) + TAU * turns
	_land_from = angle
	_land_by = by
	# The cubic's speed at the start is 3 * by / seconds: as fast as the wheel was going
	_land_seconds = clampf(3.0 * by / maxf(_speed, 1.0), 1.2 if index < 0 else 3.2, 6.0)
	_land_elapsed = 0.0
	_land_index = index if index >= 0 else -1
	_wanted = -1
	_phase = Phase.LANDING


# A click each time a peg between two slots passes the pointer, which flips back a little.
func _tick_past_pegs() -> void:
	if prizes.is_empty():
		return
	var boundary := floori((angle + _step() / 2.0) / _step())
	if boundary != _boundary:
		_boundary = boundary
		if _phase != Phase.REST:
			_pointer_kick = 1.0
			Sound.play("tick", -4.0)


func _step() -> float:
	return TAU / maxi(1, prizes.size())


func _radius() -> float:
	return maxf(40.0, minf((size.x - 2.0 * BELOW) / 2.0, (size.y - ABOVE - BELOW) / 2.0))


func _center() -> Vector2:
	var radius := _radius()
	var spare := size.y - (2.0 * radius + ABOVE + BELOW)
	return Vector2(size.x / 2.0, spare / 2.0 + ABOVE + radius)


func _hub_radius() -> float:
	return _radius() * 0.21


func _place_hub() -> void:
	var hub := _hub_radius()
	spin_button.position = _center() - Vector2(hub, hub)
	spin_button.size = Vector2(hub, hub) * 2.0


# ---------- drawing ----------

func _draw() -> void:
	var center := _center()
	var radius := _radius()
	draw_circle(center, radius + BELOW, Color(RIM, 0.16), true, -1.0, true)
	_draw_rim(center, radius)
	_draw_slots(center, radius - 24.0)
	draw_circle(center, _hub_radius() + 7.0, RING, true, -1.0, true)
	_draw_ribbon(center, radius)
	_draw_pointer(center, radius)


# A gold rim with a shine on its upper left, and a ring of lights that chase while it spins.
func _draw_rim(center: Vector2, radius: float) -> void:
	draw_circle(center, radius, RIM_DARK, true, -1.0, true)
	draw_circle(center, radius - 3.0, RIM, true, -1.0, true)
	draw_arc(center, radius - 6.0, PI * 1.05, PI * 1.55, 24, RIM_LIGHT, 3.0, true)
	draw_circle(center, radius - 16.0, RIM_DARK, true, -1.0, true)
	draw_circle(center, radius - 19.0, RING, true, -1.0, true)
	var lit := int(_time * (14.0 if _phase != Phase.REST else 2.5))
	for bulb in BULBS:
		var at := center + Vector2.from_angle((bulb + 0.5) * TAU / BULBS) * (radius - 9.5)
		var on := (bulb + lit) % 2 == 0
		if on:
			draw_circle(at, 9.0, Color(BULB_ON, 0.35), true, -1.0, true)
		draw_circle(at, 4.5, BULB_ON if on else BULB_OFF, true, -1.0, true)


# The slots, turned by `angle`: a wedge each, its prize near the rim and a coin under it.
func _draw_slots(center: Vector2, outer: float) -> void:
	if prizes.is_empty():
		draw_circle(center, outer, SLOT_B, true, -1.0, true)
		return
	var step := _step()
	for index in prizes.size():
		var middle := -PI / 2.0 + index * step + angle
		var points := PackedVector2Array([center])
		for k in 17:
			points.append(center + Vector2.from_angle(middle - step / 2.0 + step * k / 16.0) * outer)
		draw_colored_polygon(points, SLOT_A if index % 2 == 0 else SLOT_B)
	# light falling on the middle of the wheel
	draw_circle(center, outer * 0.62, Color(1, 1, 1, 0.05), true, -1.0, true)
	for index in prizes.size():
		var direction := Vector2.from_angle(-PI / 2.0 + (index - 0.5) * step + angle)
		draw_line(center + direction * _hub_radius(), center + direction * outer, DIVIDER, 2.0, true)
	draw_arc(center, outer, 0.0, TAU, 96, RING, 4.0, true)

	var font := Ui.bold_font
	var font_size := maxi(10, int(outer * 0.092))
	var baseline := (font.get_ascent(font_size) - font.get_descent(font_size)) / 2.0
	for index in prizes.size():
		var middle := -PI / 2.0 + index * step + angle
		# Turned so that the slot under the pointer reads upright, like the printing on a wheel
		draw_set_transform(center, middle + PI / 2.0)
		var text := Ui.coins_text(int(prizes[index]))
		var width := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
		var at := Vector2(-width / 2.0, -outer * 0.84 + baseline)
		draw_string_outline(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, maxi(4, font_size / 4), RING)
		draw_string(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color.WHITE)
		_draw_coin(Vector2(0.0, -outer * 0.58), outer * 0.085)
	draw_set_transform_matrix(Transform2D.IDENTITY)


func _draw_coin(at: Vector2, radius: float) -> void:
	draw_circle(at + Vector2(0.0, radius * 0.18), radius, Color(0, 0, 0, 0.28), true, -1.0, true)
	draw_circle(at, radius, CoinLabel.RIM, true, -1.0, true)
	draw_circle(at, radius * 0.8, Ui.GOLD, true, -1.0, true)
	draw_arc(at, radius * 0.55, PI * 1.05, PI * 1.5, 10, CoinLabel.SHINE, maxf(1.5, radius * 0.16), true)


# A brown ribbon over the top of the wheel, edged in gold, "DAILY" left of the pointer and
# "BONUS" right of it, the letters following the curve.
func _draw_ribbon(center: Vector2, radius: float) -> void:
	var middle := radius + 16.0
	var half := 24.0
	var start := -PI / 2.0 - 1.08
	var end := -PI / 2.0 + 1.08
	draw_arc(center + Vector2(0, 5), middle, start, end, 64, Color(0, 0, 0, 0.3), half * 2.0 + 4.0, true)
	draw_arc(center, middle, start, end, 64, RIBBON, half * 2.0, true)
	draw_arc(center, middle - half * 0.45, start, end, 64, Color(RIBBON_DARK, 0.25), half * 0.9, true)
	for edge: float in [middle - half, middle + half]:
		draw_arc(center, edge, start, end, 64, RIM, 4.0, true)
	for cut: float in [start, end]:
		var direction := Vector2.from_angle(cut)
		draw_line(center + direction * (middle - half), center + direction * (middle + half), RIM, 4.0, true)
	var font_size := int(clampf(radius * 0.13, 16.0, 34.0))
	_draw_curved_text(center, middle, -PI / 2.0 - 0.56, "DAILY", font_size)
	_draw_curved_text(center, middle, -PI / 2.0 + 0.56, "BONUS", font_size)


func _draw_curved_text(center: Vector2, radius: float, middle: float, text: String, font_size: int) -> void:
	var font := Ui.bold_font
	var widths: Array[float] = []
	var total := 0.0
	for letter in text:
		var width := font.get_string_size(letter, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x + 1.0
		widths.append(width)
		total += width
	var baseline := (font.get_ascent(font_size) - font.get_descent(font_size)) / 2.0
	var along := middle - total / radius / 2.0
	for index in text.length():
		var at := along + widths[index] / radius / 2.0
		draw_set_transform(center + Vector2.from_angle(at) * radius, at + PI / 2.0)
		var spot := Vector2(-widths[index] / 2.0, baseline)
		draw_string_outline(font, spot, text[index], HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, 7, RIBBON_DARK)
		draw_string(font, spot, text[index], HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, RIBBON_TEXT)
		along += widths[index] / radius
	draw_set_transform_matrix(Transform2D.IDENTITY)


# A gold drop pointing down into the wheel, with a green gem in its head. It flips back a
# little each time a peg passes and swings back into place.
func _draw_pointer(center: Vector2, radius: float) -> void:
	var head := center - Vector2(0.0, radius + 16.0)
	var head_radius := 22.0
	var reach := head_radius + 30.0  # from the middle of the head to the tip
	var side := acos(head_radius / reach)
	var outline := PackedVector2Array()
	for k in 25:
		outline.append(Vector2.from_angle(PI / 2.0 + side + (TAU - 2.0 * side) * k / 24.0) * head_radius)
	outline.append(Vector2(0.0, reach))
	draw_set_transform(head + Vector2(0, 4), -_pointer_kick * 0.35)
	draw_colored_polygon(outline, Color(0, 0, 0, 0.3))
	draw_set_transform(head, -_pointer_kick * 0.35)
	draw_colored_polygon(outline, RIM)
	var closed := outline.duplicate()
	closed.append(outline[0])
	draw_polyline(closed, RIM_DARK, 3.0, true)
	var inner := PackedVector2Array()
	for point in outline:
		inner.append(point * 0.62 + Vector2(0.0, 2.0))
	draw_colored_polygon(inner, RIM_LIGHT)
	var gem := PackedVector2Array([Vector2(0, -11), Vector2(9, 0), Vector2(0, 11), Vector2(-9, 0)])
	draw_colored_polygon(gem, GEM)
	draw_colored_polygon(PackedVector2Array([Vector2(0, -11), Vector2(9, 0), Vector2(0, 0)]), GEM.lightened(0.45))
	draw_set_transform_matrix(Transform2D.IDENTITY)


# The hub, upright whatever the slots do: SPIN on gold while the wheel may be spun, otherwise
# dimmed with the time still to wait.
func _draw_hub() -> void:
	var button := spin_button
	var center := button.size / 2.0
	var radius := center.x
	var live := hub_ready
	if live and _phase == Phase.REST:
		var glow := 0.5 + 0.5 * sin(_time * 4.0)
		button.draw_circle(center, radius + 4.0 + 6.0 * glow, Color(RIM, 0.25 + 0.2 * glow), true, -1.0, true)
	button.draw_circle(center + Vector2(0, 3), radius, Color(0, 0, 0, 0.35), true, -1.0, true)
	button.draw_circle(center, radius, RIM_DARK, true, -1.0, true)
	button.draw_circle(center, radius - 3.0, RIM if live else HUB_ASLEEP.lightened(0.2), true, -1.0, true)
	var face := HUB_LIVE if live else HUB_ASLEEP
	if button.is_pressed() and live:
		face = face.darkened(0.15)
	button.draw_circle(center, radius - 9.0, face, true, -1.0, true)
	button.draw_arc(center, radius - 13.0, PI * 1.1, PI * 1.55, 16, Color(1, 1, 1, 0.45), 4.0, true)

	var font := Ui.bold_font
	if live:
		_hub_line(font, "SPIN", int(radius * 0.5), center.y, Color.WHITE)
	else:
		_hub_line(font, "NEXT SPIN", int(radius * 0.22), center.y - radius * 0.24, Color(1, 1, 1, 0.9))
		_hub_line(font, hub_text, int(radius * 0.34), center.y + radius * 0.16, Color.WHITE)


func _hub_line(font: Font, text: String, font_size: int, middle_y: float, color: Color) -> void:
	var baseline := middle_y + (font.get_ascent(font_size) - font.get_descent(font_size)) / 2.0
	var width := spin_button.size.x
	spin_button.draw_string_outline(font, Vector2(0, baseline), text, HORIZONTAL_ALIGNMENT_CENTER, width, font_size, maxi(3, font_size / 5), Color(RIBBON_DARK, 0.8))
	spin_button.draw_string(font, Vector2(0, baseline), text, HORIZONTAL_ALIGNMENT_CENTER, width, font_size, color)
