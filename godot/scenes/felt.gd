class_name FeltBackground
extends Control
## The card-table cloth behind every screen: green felt, lighter in the middle and
## darker towards the corners, the way a lamp over a table lights it.

const CENTER := Color("2e7d32")
const EDGE := Color("0b2b0f")


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	var gradient := Gradient.new()
	gradient.set_color(0, CENTER)
	gradient.set_color(1, EDGE)
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.width = 256
	texture.height = 256
	texture.fill = GradientTexture2D.FILL_RADIAL
	texture.fill_from = Vector2(0.5, 0.45)
	texture.fill_to = Vector2(1.05, 0.45)

	var cloth := TextureRect.new()
	cloth.texture = texture
	cloth.stretch_mode = TextureRect.STRETCH_SCALE
	cloth.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	cloth.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cloth.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(cloth)
