class_name TableVoice
extends HBoxContainer
## The voice chat at the table: a Mic switch and a Speaker switch (headphones) beside our own
## picture and coins, and on the players' pictures a small microphone for each player whose
## microphone is on and a green ring that swells while they speak. The voice itself is
## Game.voice (net/voice_chat.gd); this only shows it and passes the taps on.
## The pictures are drawn in code, like the sound switches, so no symbol font is needed.

const BUTTON_SIZE := 52.0
const MIC_GREEN := Color("1e8e3e")
const SPEAKING_GREEN := Color("00e676")
const ASKING_AMBER := Color("f9a825")
const OFF := Color(1, 1, 1, 0.55)
const STRUCK := Color("ff5252")

## Gives the picture of a player by id, or null: anything with `voice_level` and `mic_on`
## (a PlayerBadge at the rummy table, table.gd's _badge_of; a DonkeySeat at Donkey Master).
var badge_of: Callable

var _mic: Button
var _speaker: Button
var _rings: Dictionary = {}  # user id -> how full their ring is drawn, easing after the voice
var _beat := 0.0


func _init() -> void:
	name = "VoiceSwitches"
	size_flags_vertical = Control.SIZE_SHRINK_CENTER
	add_theme_constant_override("separation", 10)
	_mic = _make_button("MicSwitch", _draw_mic_button)
	_speaker = _make_button("SpeakerSwitch", _draw_speaker_button)


func _ready() -> void:
	_mic.pressed.connect(func() -> void: Game.voice.set_mic(not Game.voice.mic_on and not Game.voice.asking))
	_speaker.pressed.connect(func() -> void: Game.voice.set_speaker(not Game.voice.speaker_on))
	Game.voice.changed.connect(_refresh)
	Game.voice.mic_failed.connect(_on_mic_failed)
	_refresh()


func _process(delta: float) -> void:
	_beat += delta
	var voice := Game.voice
	for player: Dictionary in voice.table_players():
		var id := str(player.get("id", ""))
		var badge: Object = badge_of.call(id) if badge_of.is_valid() else null
		if badge == null:
			continue
		var level := voice.level_of(id)
		var target := 0.25 + 0.75 * level if level > 0.0 else 0.0
		var shown: float = _rings.get(id, 0.0)
		# Swells at once with the voice, sinks back more gently between words
		shown = lerpf(shown, target, minf(1.0, delta * (20.0 if target > shown else 5.0)))
		if shown < 0.02 and target == 0.0:
			shown = 0.0
		_rings[id] = shown
		badge.set("voice_level", shown)
		badge.set("mic_on", voice.has_mic(id))
	if voice.mic_on or voice.asking:
		_mic.queue_redraw()  # our own voice rings the button; the question pulses it


func _refresh() -> void:
	var voice := Game.voice
	if voice.asking:
		_mic.tooltip_text = "Mic: waiting for your answer to the phone's question"
	elif voice.mic_on:
		_mic.tooltip_text = "Mic: on. The players at this table can hear you. Tap to mute"
	else:
		_mic.tooltip_text = "Mic: off. Tap to talk with the players at this table"
	_speaker.tooltip_text = "Speaker: on. You hear the other players" if voice.speaker_on else "Speaker: off. Tap to hear the other players"
	var fill := Color(0, 0, 0, 0.36)
	if voice.mic_on:
		fill = MIC_GREEN
	elif voice.asking:
		fill = ASKING_AMBER.darkened(0.3)
	_paint(_mic, fill)
	_mic.queue_redraw()
	_speaker.queue_redraw()


func _on_mic_failed(message: String) -> void:
	Ui.alert(message, "Microphone")


func _make_button(node_name: String, picture: Callable) -> Button:
	var button := Button.new()
	button.name = node_name
	button.custom_minimum_size = Vector2(BUTTON_SIZE, BUTTON_SIZE)
	button.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	button.focus_mode = Control.FOCUS_NONE
	_paint(button, Color(0, 0, 0, 0.36))
	button.draw.connect(picture.bind(button))
	add_child(button)
	return button


func _paint(button: Button, fill: Color) -> void:
	for state_name: String in ["normal", "hover", "pressed"]:
		var round_box := StyleBoxFlat.new()
		round_box.bg_color = fill.lightened(0.12) if state_name == "hover" else fill
		round_box.set_corner_radius_all(int(BUTTON_SIZE / 2.0))
		round_box.anti_aliasing = true
		button.add_theme_stylebox_override(state_name, round_box)


func _draw_mic_button(button: Button) -> void:
	var middle := button.size / 2.0
	var voice := Game.voice
	if voice.asking:
		# Waiting for the phone's question to be answered: a slow amber pulse round the edge
		var pulse := 0.5 + 0.5 * sin(_beat * TAU)
		button.draw_arc(middle, BUTTON_SIZE / 2.0 - 2.0, 0.0, TAU, 40, Color(ASKING_AMBER, 0.5 + 0.5 * pulse), 3.0, true)
	elif voice.mic_on:
		var level := voice.level_of(Game.player_id)
		if level > 0.0:
			# We are being heard: a ring round the button grows with the voice
			button.draw_arc(middle, BUTTON_SIZE / 2.0 + 2.0 + 4.0 * level, 0.0, TAU, 40, Color(SPEAKING_GREEN, 0.9), 2.0 + 3.0 * level, true)
	draw_mic(button, middle, 1.25, Color.WHITE if voice.mic_on else OFF)
	if not voice.mic_on and not voice.asking:
		_strike(button)


func _draw_speaker_button(button: Button) -> void:
	var middle := button.size / 2.0
	var on := Game.voice.speaker_on
	draw_headphones(button, middle, 1.0, Color.WHITE if on else OFF)
	if not on:
		_strike(button)


func _strike(button: Button) -> void:
	var middle := button.size / 2.0
	button.draw_line(middle + Vector2(-13, -13), middle + Vector2(13, 13), STRUCK, 3.5, true)


## A microphone: a rounded head on a U-shaped holder, a stem and a foot. About 20 tall at
## `size_scale` 1, centred on `center`. PlayerBadge draws the same one on the pictures.
static func draw_mic(canvas: CanvasItem, center: Vector2, size_scale: float, color: Color) -> void:
	var head := 3.6 * size_scale  # half the width of the head
	var top := center + Vector2(0, -5.0 * size_scale)
	var bottom := center + Vector2(0, 0.5 * size_scale)
	canvas.draw_circle(top, head, color, true, -1.0, true)
	canvas.draw_rect(Rect2(top - Vector2(head, 0), Vector2(head * 2.0, bottom.y - top.y)), color)
	canvas.draw_circle(bottom, head, color, true, -1.0, true)
	var line := maxf(1.2, 1.8 * size_scale)
	canvas.draw_arc(center + Vector2(0, 0.5 * size_scale), 6.2 * size_scale, 0.15, PI - 0.15, 16, color, line, true)
	canvas.draw_line(center + Vector2(0, 6.7 * size_scale), center + Vector2(0, 9.5 * size_scale), color, line, true)
	canvas.draw_line(center + Vector2(-3.8 * size_scale, 9.5 * size_scale), center + Vector2(3.8 * size_scale, 9.5 * size_scale), color, line, true)


## Headphones: a band over the top and a cup on each side, centred on `center`.
static func draw_headphones(canvas: CanvasItem, center: Vector2, size_scale: float, color: Color) -> void:
	var band := 11.0 * size_scale
	canvas.draw_arc(center + Vector2(0, 2.0 * size_scale), band, PI + 0.1, TAU - 0.1, 24, color, 3.0 * size_scale, true)
	var cup := StyleBoxFlat.new()
	cup.bg_color = color
	cup.set_corner_radius_all(int(3.0 * size_scale))
	cup.anti_aliasing = true
	var cup_size := Vector2(6.5, 12.0) * size_scale
	canvas.draw_style_box(cup, Rect2(center + Vector2(-band - 3.2 * size_scale, 0.5 * size_scale), cup_size))
	canvas.draw_style_box(cup, Rect2(center + Vector2(band - 3.3 * size_scale, 0.5 * size_scale), cup_size))
