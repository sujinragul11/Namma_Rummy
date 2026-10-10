extends CanvasLayer
## The big moments: fireworks, confetti, sparkles, a flash of light, a shake of the whole
## table, a banner across the screen.
##
## All of it is decoration drawn over the screens: it never takes a tap and it removes
## itself. Positions are screen positions, the same as Control.global_position.

enum Kind { PAPER, SPARK, STAR, RING, HEART, DIAMOND, SPADE, CLUB }

const GOLD := Color("ffca28")
const PAPER_COLORS: Array[Color] = [
	Color("ffca28"), Color("ef5350"), Color("42a5f5"), Color("66bb6a"), Color("ab47bc"), Color("ffffff"), Color("ff7043"),
]
const FIREWORK_COLORS: Array[Color] = [
	Color("ffd54f"), Color("ff5252"), Color("40c4ff"), Color("69f0ae"), Color("e040fb"), Color("ffab40"),
]
const SUIT_COLORS: Array[Color] = [Color("ff5252"), Color.WHITE, Color("ffca28")]
const BANNER_HEIGHT := 116.0

var _glow: Layer  # light: sparks and stars, which brighten what is under them
var _paper: Layer  # solid things: confetti and card suits
var _flash: ColorRect
var _danger: TextureRect
var _danger_pulse: Tween
var _shake: Tween
var _steady := Transform2D.IDENTITY  # how the screen sits when nothing shakes it
var _show := 0  # goes up when the specks are cleared, so rockets still waiting know not to fire


## One moving speck. A negative `age` means it has not appeared yet.
class Piece:
	var kind := Kind.PAPER
	var position := Vector2.ZERO
	var velocity := Vector2.ZERO
	var gravity := 0.0
	var drag := 0.0  # share of its speed lost per second
	var age := 0.0
	var life := 1.0
	var size := 8.0
	var color := Color.WHITE
	var angle := 0.0
	var spin := 0.0
	var flutter := 0.0  # how fast a piece of paper tumbles


class Layer extends Node2D:
	const STAR: PackedVector2Array = [
		Vector2(0, -1), Vector2(0.2, -0.2), Vector2(1, 0), Vector2(0.2, 0.2),
		Vector2(0, 1), Vector2(-0.2, 0.2), Vector2(-1, 0), Vector2(-0.2, -0.2),
	]
	const DIAMOND: PackedVector2Array = [Vector2(0, -1), Vector2(0.74, 0), Vector2(0, 1), Vector2(-0.74, 0)]
	const STEM: PackedVector2Array = [Vector2(0, 0.1), Vector2(-0.34, 1), Vector2(0.34, 1)]

	var pieces: Array[Piece] = []
	var _heart := PackedVector2Array()
	var _spade := PackedVector2Array()

	func _init() -> void:
		# A heart from its textbook curve; a spade is the same shape upside down, on a stem
		for step in 28:
			var t := step * TAU / 28.0
			var x := 16.0 * pow(sin(t), 3.0)
			var y := -(13.0 * cos(t) - 5.0 * cos(2.0 * t) - 2.0 * cos(3.0 * t) - cos(4.0 * t))
			_heart.append(Vector2(x, y + 2.5) / 17.0)
			_spade.append(Vector2(x, -y - 6.0) / 19.0)

	func _draw() -> void:
		for piece in pieces:
			if piece.age < 0.0:
				continue
			var left := 1.0 - piece.age / piece.life  # 1 when new, 0 when gone
			var color := piece.color
			match piece.kind:
				Kind.PAPER:
					color.a *= minf(1.0, left * 4.0)
					draw_set_transform(piece.position, piece.angle, Vector2(cos(piece.age * piece.flutter), 1.0))
					draw_rect(Rect2(-piece.size * 0.5, -piece.size * 0.3, piece.size, piece.size * 0.6), color)
				Kind.SPARK:
					color.a *= left
					draw_set_transform(Vector2.ZERO)
					draw_line(piece.position, piece.position - piece.velocity * 0.06, color, piece.size, true)
					draw_circle(piece.position, piece.size * 0.7, color)
				Kind.STAR:
					# Twinkles as it fades
					var twinkle := piece.size * left * (0.75 + 0.25 * sin(piece.age * 30.0))
					draw_set_transform(piece.position, piece.angle, Vector2(twinkle, twinkle))
					draw_colored_polygon(STAR, color)
				Kind.RING:
					color.a *= left
					draw_set_transform(Vector2.ZERO)
					draw_arc(piece.position, piece.size * (1.0 - left * left), 0.0, TAU, 48, color, 1.0 + 7.0 * left, true)
				_:
					color.a *= minf(1.0, left * 3.0)
					draw_set_transform(piece.position, piece.angle, Vector2(piece.size, piece.size))
					_draw_suit(piece.kind, color)
		draw_set_transform(Vector2.ZERO)

	func _draw_suit(kind: Kind, color: Color) -> void:
		match kind:
			Kind.HEART:
				draw_colored_polygon(_heart, color)
			Kind.DIAMOND:
				draw_colored_polygon(DIAMOND, color)
			Kind.SPADE:
				draw_colored_polygon(_spade, color)
				draw_colored_polygon(STEM, color)
			Kind.CLUB:
				draw_circle(Vector2(0, -0.48), 0.44, color)
				draw_circle(Vector2(-0.5, 0.16), 0.44, color)
				draw_circle(Vector2(0.5, 0.16), 0.44, color)
				draw_circle(Vector2.ZERO, 0.3, color)
				draw_colored_polygon(STEM, color)


func _ready() -> void:
	layer = 40  # over the screens, under the message boxes

	_paper = Layer.new()
	add_child(_paper)
	_glow = Layer.new()
	var light := CanvasItemMaterial.new()
	light.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	_glow.material = light
	add_child(_glow)

	# Red creeping in from the edges of the screen, for when time is running out
	var gradient := Gradient.new()
	gradient.offsets = PackedFloat32Array([0.0, 0.55, 1.0])
	gradient.colors = PackedColorArray([Color(1, 0, 0, 0), Color(1, 0, 0, 0), Color(0.9, 0.05, 0.05, 0.6)])
	var edges := GradientTexture2D.new()
	edges.gradient = gradient
	edges.width = 128
	edges.height = 128
	edges.fill = GradientTexture2D.FILL_RADIAL
	edges.fill_from = Vector2(0.5, 0.5)
	edges.fill_to = Vector2(1.0, 0.5)
	_danger = TextureRect.new()
	_danger.texture = edges
	_danger.stretch_mode = TextureRect.STRETCH_SCALE
	_danger.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_danger.visible = false
	_cover_screen(_danger)

	_flash = ColorRect.new()
	_flash.color = Color(1, 1, 1, 0)
	_cover_screen(_flash)
	set_process(false)


func _process(delta: float) -> void:
	for moving: Layer in [_paper, _glow]:
		var kept: Array[Piece] = []
		for piece in moving.pieces:
			piece.age += delta
			if piece.age >= piece.life:
				continue
			kept.append(piece)
			if piece.age < 0.0:
				continue
			piece.velocity.y += piece.gravity * delta
			piece.velocity *= maxf(0.0, 1.0 - piece.drag * delta)
			piece.position += piece.velocity * delta
			piece.angle += piece.spin * delta
		moving.pieces = kept
		moving.queue_redraw()
	if _paper.pieces.is_empty() and _glow.pieces.is_empty():
		set_process(false)


# ---------- light and movement ----------

## The whole screen lights up for a moment.
func flash(color: Color = Color(1, 1, 1, 0.7), seconds: float = 0.4) -> void:
	_flash.color = color
	_flash.create_tween().tween_property(_flash, "color:a", 0.0, seconds).set_ease(Tween.EASE_OUT)


## Shakes everything under the message boxes. `strength` is how far, in screen units.
func shake(strength: float = 10.0, seconds: float = 0.35) -> void:
	if _shake != null and _shake.is_valid():
		_shake.kill()
	else:
		_steady = get_viewport().canvas_transform
	_shake = create_tween()
	_shake.tween_method(_shake_step.bind(strength), 1.0, 0.0, seconds)
	_shake.tween_callback(func() -> void: get_viewport().canvas_transform = _steady)


## Red at the edges of the screen, throbbing, until switched off again.
func danger(on: bool) -> void:
	if on == (_danger_pulse != null):
		return
	if _danger_pulse != null:
		_danger_pulse.kill()
		_danger_pulse = null
	if on:
		_danger.visible = true
		_danger.modulate.a = 0.0
		_danger_pulse = _danger.create_tween().set_loops()
		_danger_pulse.tween_property(_danger, "modulate:a", 1.0, 0.25)
		_danger_pulse.tween_property(_danger, "modulate:a", 0.3, 0.75)
	else:
		var fade := _danger.create_tween()
		fade.tween_property(_danger, "modulate:a", 0.0, 0.3)
		fade.tween_callback(_danger.hide)


## Big words that sweep in from the left, stop in the middle, and leave to the right.
func banner(text: String, color: Color = GOLD, hold_seconds: float = 0.6) -> void:
	var screen := _screen()
	var band := ColorRect.new()
	band.color = Color(0, 0, 0, 0.62)
	band.mouse_filter = Control.MOUSE_FILTER_IGNORE
	band.position = Vector2(0.0, screen.y * 0.36 - BANNER_HEIGHT / 2.0)
	band.size = Vector2(screen.x, BANNER_HEIGHT)
	band.pivot_offset = band.size / 2.0
	band.scale.y = 0.0
	add_child(band)
	for edge_y: float in [0.0, BANNER_HEIGHT - 4.0]:
		var edge := ColorRect.new()
		edge.color = color
		edge.mouse_filter = Control.MOUSE_FILTER_IGNORE
		edge.position = Vector2(0.0, edge_y)
		edge.size = Vector2(screen.x, 4.0)
		band.add_child(edge)

	var words := _label(text, 70, color)
	words.size = band.size
	words.position.x = -screen.x
	band.add_child(words)

	var tween := band.create_tween()
	tween.tween_property(band, "scale:y", 1.0, 0.12)
	tween.tween_property(words, "position:x", 0.0, 0.28).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_interval(hold_seconds)
	tween.tween_property(words, "position:x", screen.x, 0.22).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	tween.tween_property(band, "scale:y", 0.0, 0.1)
	tween.tween_callback(band.queue_free)
	Sound.play("whoosh", 0.0, 1.3)


## A few words that rise from a spot and fade, e.g. the name of a meld just made.
func float_text(at: Vector2, text: String, color: Color = GOLD, font_size: int = 30) -> void:
	var words := _label(text, font_size, color)
	add_child(words)
	words.size = words.get_minimum_size()
	words.position = at - words.size / 2.0
	words.pivot_offset = words.size / 2.0
	words.scale = Vector2(0.4, 0.4)
	var tween := words.create_tween()
	tween.tween_property(words, "scale", Vector2.ONE, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.parallel().tween_property(words, "position:y", words.position.y - 70.0, 1.2).set_ease(Tween.EASE_OUT)
	tween.parallel().tween_property(words, "modulate:a", 0.0, 0.4).set_delay(0.8)
	tween.tween_callback(words.queue_free)


# ---------- specks ----------

## A puff of twinkling stars, e.g. where a meld was made. A dozen or more come with a ring of light.
func sparkle(at: Vector2, color: Color = GOLD, count: int = 18) -> void:
	for index in count:
		var star := _piece(_glow, Kind.STAR, at + _scatter(14.0), randf_range(0.5, 0.95))
		star.velocity = Vector2.from_angle(randf() * TAU) * randf_range(90.0, 380.0)
		star.drag = 3.0
		star.size = randf_range(9.0, 20.0)
		star.spin = randf_range(-3.0, 3.0)
		star.color = color.lerp(Color.WHITE, randf() * 0.6)
	if count >= 12:
		ring(at, color, 70.0)


## A circle of light spreading from a spot, e.g. where a card lands.
func ring(at: Vector2, color: Color = Color.WHITE, radius: float = 60.0, seconds: float = 0.4) -> void:
	var circle := _piece(_glow, Kind.RING, at, seconds)
	circle.size = radius
	circle.color = Color(color, 0.7)


## Paper shot up from both bottom corners, then more falling from above.
func confetti() -> void:
	var screen := _screen()
	for side: float in [0.0, 1.0]:
		var mouth := Vector2(screen.x * side, screen.y + 10.0)
		var aim := -PI / 3.0 if side == 0.0 else -2.0 * PI / 3.0
		for index in 70:
			var paper := _paper_piece(mouth, 0.0)
			paper.velocity = Vector2.from_angle(aim + randf_range(-0.35, 0.35)) * randf_range(650.0, 1500.0)
			paper.gravity = 950.0
			paper.drag = 1.3
	for index in 60:
		var paper := _paper_piece(Vector2(randf() * screen.x, -20.0), randf() * 1.6)
		paper.velocity = Vector2(randf_range(-60.0, 60.0), randf_range(80.0, 240.0))
		paper.gravity = 260.0
		paper.drag = 0.4
	Sound.play("confetti")


## Rockets that climb and burst, one after another over `seconds`.
func fireworks(count: int = 5, seconds: float = 2.0) -> void:
	var screen := _screen()
	var show := create_tween().set_parallel(true)
	for index in count:
		var at := Vector2(screen.x * randf_range(0.12, 0.88), screen.y * randf_range(0.12, 0.46))
		var color: Color = FIREWORK_COLORS[(index + randi()) % FIREWORK_COLORS.size()]
		var start := seconds * index / maxf(1.0, count) + randf() * 0.15
		show.tween_callback(_launch.bind(at, color, _show)).set_delay(start)


## Hearts, spades, diamonds and clubs thrown up from the bottom of the screen.
func suit_fountain(count: int = 28) -> void:
	var screen := _screen()
	for index in count:
		var kind: Kind = [Kind.HEART, Kind.DIAMOND, Kind.SPADE, Kind.CLUB][index % 4]
		var suit := _piece(_paper, kind, Vector2(screen.x * randf_range(0.35, 0.65), screen.y + 30.0), randf_range(2.2, 3.0), randf() * 0.7)
		suit.velocity = Vector2.from_angle(-PI / 2.0 + randf_range(-0.6, 0.6)) * randf_range(820.0, 1250.0)
		suit.gravity = 1000.0
		suit.drag = 0.5
		suit.size = randf_range(14.0, 26.0)
		suit.spin = randf_range(-4.0, 4.0)
		suit.color = SUIT_COLORS[index % SUIT_COLORS.size()]


## Everything at once, for the winner. `whole_game` is for winning the match, not just a round.
func victory(whole_game: bool = false) -> void:
	flash(Color(1, 0.95, 0.7, 0.55), 0.5)
	confetti()
	fireworks(8 if whole_game else 3, 4.0 if whole_game else 1.4)
	if whole_game:
		suit_fountain()


## Ends the show at once: everything in the air disappears and no more rockets go up.
## For when the screen that was being celebrated on closes.
func clear() -> void:
	_show += 1
	_paper.pieces.clear()
	_glow.pieces.clear()
	_paper.queue_redraw()
	_glow.queue_redraw()


# ---------- internals ----------

func _launch(at: Vector2, color: Color, show: int) -> void:
	if show != _show:
		return
	# The rocket: a streak climbing from the bottom of the screen to where it bursts
	var climb := 0.45
	var rocket := _piece(_glow, Kind.SPARK, Vector2(at.x + randf_range(-40.0, 40.0), _screen().y), climb)
	rocket.velocity = (at - rocket.position) / climb
	rocket.size = 3.0
	rocket.color = Color(1, 0.9, 0.6)
	create_tween().tween_callback(_burst.bind(at, color, show)).set_delay(climb)


func _burst(at: Vector2, color: Color, show: int) -> void:
	if show != _show:
		return
	for index in 90:
		var spark := _piece(_glow, Kind.SPARK, at, randf_range(0.9, 1.6))
		spark.velocity = Vector2.from_angle(randf() * TAU) * randf_range(140.0, 620.0)
		spark.gravity = 240.0
		spark.drag = 1.7
		spark.size = randf_range(3.0, 5.5)
		spark.color = color.lerp(Color.WHITE, randf() * 0.35)
	for index in 12:
		var star := _piece(_glow, Kind.STAR, at + _scatter(90.0), randf_range(0.5, 1.0), randf() * 0.5)
		star.size = randf_range(9.0, 18.0)
		star.color = Color.WHITE
	ring(at, color, 150.0, 0.5)
	Sound.play("firework")


func _paper_piece(at: Vector2, wait: float) -> Piece:
	var paper := _piece(_paper, Kind.PAPER, at, randf_range(2.6, 3.8), wait)
	paper.size = randf_range(10.0, 18.0)
	paper.color = PAPER_COLORS[randi() % PAPER_COLORS.size()]
	paper.angle = randf() * TAU
	paper.spin = randf_range(-8.0, 8.0)
	paper.flutter = randf_range(6.0, 13.0)
	return paper


# A new speck on `target`, appearing after `wait` seconds and living for `life`.
func _piece(target: Layer, kind: Kind, at: Vector2, life: float, wait: float = 0.0) -> Piece:
	var piece := Piece.new()
	piece.kind = kind
	piece.position = at
	piece.life = life
	piece.age = -wait
	target.pieces.append(piece)
	set_process(true)
	return piece


func _scatter(reach: float) -> Vector2:
	return Vector2(randf_range(-reach, reach), randf_range(-reach, reach))


func _shake_step(left: float, strength: float) -> void:
	var screen := _screen()
	var reach := strength * left
	# Grown just enough that no edge of the picture comes into view
	var grow := 1.0 + 2.0 * reach / minf(screen.x, screen.y)
	var offset := screen / 2.0 * (1.0 - grow) + _scatter(reach)
	get_viewport().canvas_transform = _steady * Transform2D(0.0, Vector2(grow, grow), 0.0, offset)


func _screen() -> Vector2:
	return get_viewport().get_visible_rect().size


func _cover_screen(control: Control) -> void:
	control.mouse_filter = Control.MOUSE_FILTER_IGNORE
	control.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(control)


func _label(text: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_override("font", Ui.bold_font)
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	label.add_theme_constant_override("outline_size", maxi(4, font_size / 6))
	return label
