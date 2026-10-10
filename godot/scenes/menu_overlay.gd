class_name MenuOverlay
extends Control
## A box over the home menu: the table setup after a game tile is tapped, the room-code form,
## the rules. The home screen fills the box; this opens and closes it, and gives it the look
## of a card-game lobby: a cream panel in a teal frame, the title on a teal banner hanging
## from the top edge, and a small tag with a cross at the right to close it. The phone's back
## button and a tap on the dark shade beside the box close it too.
##
## Children: a full-screen "Shade" and the "Box" (a PanelContainer). The box's first row is
## the header: it holds the title Label and the close Button, which are dressed up here.

signal closed

const CREAM := Color("f3ead8")
const FRAME := Color("3fbfae")
const BANNER := Color("2bb3a3")
const TAG := Color("fff6e5")
const CROSS := Color("ef7d1a")
const TASSEL := Color("e53935")
const CLOSE_TAG := 56.0

var _box: Control
var _close_button: Button


func _ready() -> void:
	visible = false
	_box = get_node("Box")
	var frame := Ui.box(CREAM, 18, 30, 0)
	frame.content_margin_bottom = 26
	frame.border_color = FRAME
	frame.set_border_width_all(4)
	frame.shadow_color = Color(0, 0, 0, 0.45)
	frame.shadow_size = 14
	_box.add_theme_stylebox_override("panel", frame)
	get_node("Shade").gui_input.connect(_on_shade_input)
	_dress_header()


func open() -> void:
	if visible:
		return
	visible = true
	add_to_group(FriendsPanel.BACK_GROUP)  # the back button closes whatever is in this group
	Ui.pop_in.call_deferred(_box)  # once the layout has given the box its size


func close() -> void:
	if not visible:
		return
	visible = false
	remove_from_group(FriendsPanel.BACK_GROUP)
	closed.emit()


func _on_shade_input(event: InputEvent) -> void:
	var click := event as InputEventMouseButton
	if click != null and click.pressed and click.button_index == MOUSE_BUTTON_LEFT:
		close()


# The title becomes a teal banner, the close button a tag with an orange cross.
func _dress_header() -> void:
	var column := _box.get_child(0) if _box.get_child_count() > 0 else null
	var header := column.get_child(0) if column != null and column.get_child_count() > 0 else null
	if header == null:
		return
	for child in header.get_children():
		if child is Label:
			_dress_title(child)
		elif child is Button:
			_dress_close_button(child)


func _dress_title(title: Label) -> void:
	var slanted := FontVariation.new()
	slanted.base_font = ThemeDB.fallback_font
	slanted.variation_embolden = 0.7
	slanted.variation_transform = Transform2D(Vector2(1, 0), Vector2(-0.18, 1), Vector2.ZERO)
	title.add_theme_font_override("font", slanted)
	title.add_theme_font_size_override("font_size", 34)
	title.add_theme_color_override("font_color", Color.WHITE)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var banner := Ui.box(BANNER, 0, 44, 8)
	banner.corner_radius_bottom_left = 22
	banner.corner_radius_bottom_right = 22
	banner.border_color = FRAME.lightened(0.25)
	banner.border_width_bottom = 3
	banner.shadow_color = Color(0, 0, 0, 0.25)
	banner.shadow_size = 4
	banner.shadow_offset = Vector2(0, 2)
	title.add_theme_stylebox_override("normal", banner)


func _dress_close_button(button: Button) -> void:
	_close_button = button
	button.text = ""
	button.focus_mode = Control.FOCUS_NONE
	button.custom_minimum_size = Vector2(CLOSE_TAG, CLOSE_TAG + 18.0)  # room for the tassel below
	button.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	for state_name: String in ["normal", "hover", "pressed", "disabled"]:
		button.add_theme_stylebox_override(state_name, StyleBoxEmpty.new())
	button.draw.connect(_draw_close_tag)


func _draw_close_tag() -> void:
	var button := _close_button
	var tag := Rect2(Vector2(0, 2), Vector2(CLOSE_TAG, CLOSE_TAG))
	var style := Ui.box(TAG.darkened(0.08) if button.is_hovered() else TAG, 10, 0, 0)
	style.border_color = Color("e0d3bd")
	style.set_border_width_all(2)
	style.shadow_color = Color(0, 0, 0, 0.3)
	style.shadow_size = 4
	button.draw_style_box(style, tag)
	var center := tag.get_center()
	button.draw_line(center + Vector2(-11, -11), center + Vector2(11, 11), CROSS, 6.0, true)
	button.draw_line(center + Vector2(11, -11), center + Vector2(-11, 11), CROSS, 6.0, true)
	# the red tassel hanging from the tag
	var knot := Vector2(center.x + 8.0, tag.end.y)
	button.draw_line(knot, knot + Vector2(0, 8), TASSEL, 2.0, true)
	button.draw_line(knot + Vector2(0, 8), knot + Vector2(-5, 17), TASSEL, 4.0, true)
	button.draw_line(knot + Vector2(0, 8), knot + Vector2(4, 17), TASSEL, 4.0, true)
