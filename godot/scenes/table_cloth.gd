class_name TableCloth
extends Control
## The card table itself, drawn in code: a dark floor, the oval table with its wooden rim,
## and green felt that is lighter where the lamp shines on it. The oval is wider than the
## screen, so only its lower arc shows, the way a table looks from your own seat.

const FLOOR := Color("1a3650")
const FLOOR_EDGE := Color("0a1826")
const WOOD := Color("b07840")
const WOOD_DARK := Color("5a371a")
const FELT_LIGHT := Color("3d9c49")
const FELT_EDGE := Color("12471a")
const RIM_WIDTH := Vector2(28.0, 22.0)
const SEGMENTS := 120

var _floor_texture: GradientTexture2D
var _felt_texture: GradientTexture2D
var _wood_texture: GradientTexture2D


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_floor_texture = _gradient(FLOOR, FLOOR_EDGE, GradientTexture2D.FILL_RADIAL, Vector2(0.5, 0.7), Vector2(1.1, 0.7))
	_felt_texture = _gradient(FELT_LIGHT, FELT_EDGE, GradientTexture2D.FILL_RADIAL, Vector2(0.5, 0.6), Vector2(1.0, 0.6))
	_wood_texture = _gradient(WOOD, WOOD_DARK, GradientTexture2D.FILL_LINEAR, Vector2(0.5, 0.55), Vector2(0.5, 1.0))
	resized.connect(queue_redraw)


func _draw() -> void:
	draw_texture_rect(_floor_texture, Rect2(Vector2.ZERO, size), false)
	var center := Vector2(size.x * 0.5, size.y * 0.40)
	var radii := Vector2(size.x * 0.68, size.y * 0.52)
	_ellipse(center, radii + RIM_WIDTH, _wood_texture)
	_ellipse(center, radii, _felt_texture)
	# A fine shadow where the felt meets the wood, and a glint along the rim's outer edge
	draw_polyline(_outline(center, radii), Color(0, 0, 0, 0.4), 3.0, true)
	draw_polyline(_outline(center, radii + RIM_WIDTH), Color(1, 1, 1, 0.22), 2.0, true)


func _gradient(from: Color, to: Color, fill: GradientTexture2D.Fill, fill_from: Vector2, fill_to: Vector2) -> GradientTexture2D:
	var gradient := Gradient.new()
	gradient.set_color(0, from)
	gradient.set_color(1, to)
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.width = 256
	texture.height = 256
	texture.fill = fill
	texture.fill_from = fill_from
	texture.fill_to = fill_to
	return texture


# An ellipse filled with a texture stretched over its bounding box.
func _ellipse(center: Vector2, radii: Vector2, texture: Texture2D) -> void:
	var points := _outline(center, radii)
	points.remove_at(points.size() - 1)
	var uvs := PackedVector2Array()
	var colors := PackedColorArray()
	for point: Vector2 in points:
		uvs.append((point - (center - radii)) / (radii * 2.0))
		colors.append(Color.WHITE)
	draw_polygon(points, colors, uvs, texture)


# The ellipse's edge, closed: the last point repeats the first.
func _outline(center: Vector2, radii: Vector2) -> PackedVector2Array:
	var points := PackedVector2Array()
	for index in SEGMENTS + 1:
		var angle := TAU * index / SEGMENTS
		points.append(center + Vector2(cos(angle) * radii.x, sin(angle) * radii.y))
	return points
