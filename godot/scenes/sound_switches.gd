class_name SoundSwitches
extends HBoxContainer
## Two small round buttons, music and sound effects, each switching its part on or off.
## The pictures are drawn in code, like the cards, so no symbol font is needed.

const BUTTON_SIZE := 52.0
const ON := Color.WHITE
const OFF := Color(1, 1, 1, 0.4)
const STRUCK := Color("ff5252")

var _music: Button
var _effects: Button


func _init() -> void:
	add_theme_constant_override("separation", 10)
	_music = _make_button("MusicSwitch", _draw_note)
	_effects = _make_button("SoundSwitch", _draw_speaker)


func _ready() -> void:
	_music.pressed.connect(func() -> void: Sound.music_on = not Sound.music_on)
	_effects.pressed.connect(_on_effects_pressed)
	Sound.switches_changed.connect(_refresh)
	_refresh()


func _on_effects_pressed() -> void:
	Sound.sound_on = not Sound.sound_on
	Sound.play("click")  # heard only when the switch has just gone on


func _refresh() -> void:
	_music.tooltip_text = "Music: on" if Sound.music_on else "Music: off"
	_effects.tooltip_text = "Sound: on" if Sound.sound_on else "Sound: off"
	_music.queue_redraw()
	_effects.queue_redraw()


func _make_button(node_name: String, picture: Callable) -> Button:
	var button := Button.new()
	button.name = node_name
	button.custom_minimum_size = Vector2(BUTTON_SIZE, BUTTON_SIZE)
	button.focus_mode = Control.FOCUS_NONE
	for state_name: String in ["normal", "hover", "pressed"]:
		var round_box := StyleBoxFlat.new()
		round_box.bg_color = Color(0, 0, 0, 0.5 if state_name == "hover" else 0.36)
		round_box.set_corner_radius_all(int(BUTTON_SIZE / 2.0))
		round_box.anti_aliasing = true
		button.add_theme_stylebox_override(state_name, round_box)
	button.draw.connect(picture.bind(button))
	add_child(button)
	return button


# Two joined quavers.
func _draw_note(button: Button) -> void:
	var middle := button.size / 2.0
	var ink := ON if Sound.music_on else OFF
	var heads: Array[Vector2] = [Vector2(-8, 9), Vector2(7, 6)]
	for head in heads:
		button.draw_circle(middle + head, 5.5, ink, true, -1.0, true)
		button.draw_line(middle + head + Vector2(4.5, 0), middle + head + Vector2(4.5, -19), ink, 2.5, true)
	button.draw_line(middle + Vector2(-3.5, -10), middle + Vector2(11.5, -13), ink, 5.0, true)
	if not Sound.music_on:
		_strike(button)


# A loudspeaker with two waves coming out of it.
func _draw_speaker(button: Button) -> void:
	var middle := button.size / 2.0 - Vector2(3, 0)
	var ink := ON if Sound.sound_on else OFF
	var cone := PackedVector2Array()
	for point: Vector2 in [Vector2(-12, -4), Vector2(-6, -4), Vector2(1, -11), Vector2(1, 11), Vector2(-6, 4), Vector2(-12, 4)]:
		cone.append(middle + point)
	button.draw_colored_polygon(cone, ink)
	if Sound.sound_on:
		button.draw_arc(middle + Vector2(2, 0), 7.0, -0.8, 0.8, 12, ink, 2.5, true)
		button.draw_arc(middle + Vector2(2, 0), 13.0, -0.8, 0.8, 16, ink, 2.5, true)
	else:
		_strike(button)


func _strike(button: Button) -> void:
	var middle := button.size / 2.0
	button.draw_line(middle + Vector2(-13, -13), middle + Vector2(13, 13), STRUCK, 3.5, true)
