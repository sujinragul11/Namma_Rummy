class_name DriftingSuits
extends Control
## Large, faint hearts, spades, diamonds and clubs rising slowly across the felt, so the
## screens outside a game are never quite still. It sits between the felt and the screen.

const FxScript := preload("res://autoload/fx.gd")
const COUNT := 14
const KINDS: Array[FxScript.Kind] = [FxScript.Kind.HEART, FxScript.Kind.SPADE, FxScript.Kind.DIAMOND, FxScript.Kind.CLUB]

var _shapes: FxScript.Layer


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_shapes = FxScript.Layer.new()
	add_child(_shapes)
	for index in COUNT:
		var suit := FxScript.Piece.new()
		suit.kind = KINDS[index % KINDS.size()]
		suit.size = randf_range(26.0, 70.0)
		suit.color = Color(1, 1, 1, randf_range(0.035, 0.075))
		suit.angle = randf() * TAU
		suit.spin = randf_range(-0.25, 0.25)
		# The larger ones are nearer, so they pass more quickly
		suit.velocity = Vector2(randf_range(-8.0, 8.0), -suit.size * randf_range(0.35, 0.6))
		suit.position = Vector2(randf() * size.x, randf() * size.y)
		_shapes.pieces.append(suit)


func _process(delta: float) -> void:
	if not is_visible_in_tree():
		return
	for suit in _shapes.pieces:
		suit.position += suit.velocity * delta
		suit.angle += suit.spin * delta
		# Gone off the top: it comes back in at the bottom, somewhere else
		if suit.position.y < -suit.size * 1.5:
			suit.position = Vector2(randf() * size.x, size.y + suit.size * 1.5)
	_shapes.queue_redraw()
