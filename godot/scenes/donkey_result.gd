class_name DonkeyResult
extends Control
## The end of a Donkey Master game, over the table: how it went for us in big words with a
## picture (the trophy for the Master, the runner for a safe player, the donkey for the
## Donkey), every player in the order they got out with the coins they won or lost, and two
## buttons: play again, or leave. Built in code.

const PANEL := Color("123f17")
const WON := Color("69f0ae")
const LOST := Color("ff8a80")

var _box: PanelContainer
var _picture: TextureRect
var _title: Label
var _subtitle: Label
var _rows: VBoxContainer
var _again_button: Button
var _leave_button: Button
var _time := 0.0


func _init() -> void:
	name = "DonkeyResult"
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	z_index = 200
	var shade := ColorRect.new()
	shade.color = Color(0, 0, 0, 0.66)
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(shade)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	_box = PanelContainer.new()
	_box.name = "DonkeyResultBox"
	_box.custom_minimum_size = Vector2(640, 0)
	center.add_child(_box)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	_box.add_child(column)

	var top := HBoxContainer.new()
	top.alignment = BoxContainer.ALIGNMENT_CENTER
	top.add_theme_constant_override("separation", 14)
	_picture = TextureRect.new()
	_picture.custom_minimum_size = Vector2(96, 96)
	_picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	top.add_child(_picture)
	var words := VBoxContainer.new()
	words.alignment = BoxContainer.ALIGNMENT_CENTER
	_title = Label.new()
	_title.name = "DonkeyResultTitle"
	_title.add_theme_font_size_override("font_size", 38)
	_title.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.6))
	_title.add_theme_constant_override("outline_size", 8)
	words.add_child(_title)
	_subtitle = Label.new()
	_subtitle.add_theme_font_size_override("font_size", 19)
	_subtitle.add_theme_color_override("font_color", Ui.PALE_GREEN)
	words.add_child(_subtitle)
	top.add_child(words)
	column.add_child(top)

	_rows = VBoxContainer.new()
	_rows.name = "DonkeyResultRows"
	_rows.add_theme_constant_override("separation", 4)
	column.add_child(_rows)

	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	buttons.add_theme_constant_override("separation", 24)
	_again_button = Button.new()
	_again_button.name = "DonkeyPlayAgainButton"
	_again_button.text = "Play Again"
	_again_button.custom_minimum_size = Vector2(230, 60)
	_again_button.pressed.connect(func() -> void: Game.donkey.play_again())
	buttons.add_child(_again_button)
	_leave_button = Button.new()
	_leave_button.name = "DonkeyResultLeaveButton"
	_leave_button.text = "Leave"
	_leave_button.custom_minimum_size = Vector2(230, 60)
	_leave_button.pressed.connect(func() -> void: Game.donkey.leave())
	buttons.add_child(_leave_button)
	column.add_child(buttons)


func _ready() -> void:
	var frame := Ui.box(PANEL, 22, 30, 22)
	frame.border_color = Ui.GOLD.darkened(0.2)
	frame.set_border_width_all(3)
	frame.shadow_color = Color(0, 0, 0, 0.5)
	frame.shadow_size = 16
	_box.add_theme_stylebox_override("panel", frame)
	_title.add_theme_font_override("font", Ui.bold_font)
	Ui.tint_button(_again_button, Ui.PRIMARY)
	Ui.tint_button(_leave_button, Ui.RED)
	Game.busy_changed.connect(func() -> void: _again_button.disabled = Game.busy)


func _process(delta: float) -> void:
	if not visible:
		return
	_time += delta
	_picture.pivot_offset = _picture.size / 2.0
	_picture.rotation = sin(_time * 3.0) * 0.12
	_picture.scale = Vector2.ONE * (1.0 + absf(sin(_time * 3.0)) * 0.06)


## Fills the box from the finished table and brings it in.
func show_result() -> void:
	var state := Game.donkey.state
	var me := Game.donkey.me()
	var place := int(me.get("place", 0))
	var donkey: bool = me.get("donkey", false) or str(state.get("donkeyId", "")) == Game.player_id
	if donkey:
		_title.text = "YOU ARE THE DONKEY!"
		_title.add_theme_color_override("font_color", Color("ffab91"))
		_picture.texture = DonkeyHome.picture("donkey")
	elif place == 1:
		_title.text = "YOU ARE THE MASTER!"
		_title.add_theme_color_override("font_color", Ui.GOLD)
		_picture.texture = DonkeyHome.picture("trophy")
	elif place > 0:
		_title.text = "YOU ESCAPED!  %s" % DonkeySeat.ordinal(place)
		_title.add_theme_color_override("font_color", WON)
		_picture.texture = DonkeyHome.picture("escape")
	else:
		_title.text = "GAME OVER"
		_title.add_theme_color_override("font_color", Color.WHITE)
		_picture.texture = DonkeyHome.picture("donkey")
	var donkey_name := Game.donkey.player_name(state.get("donkeyId", ""))
	if str(state.get("endedBy", "")) == "leave":
		_subtitle.text = "The other players left the table."
	elif not donkey_name.is_empty() and not donkey:
		_subtitle.text = "%s is the Donkey this time." % donkey_name
	else:
		_subtitle.text = "Last one holding cards. Better luck next game!" if donkey else ""
	_subtitle.visible = not _subtitle.text.is_empty()

	for child in _rows.get_children():
		child.queue_free()
	var results: Array = state.get("results", [])
	for entry: Dictionary in results:
		_rows.add_child(_row(entry))
	_again_button.text = "Play Again" if state.get("private", false) else "Play Again Online"
	_again_button.disabled = Game.busy
	visible = true
	Ui.pop_in(_box)
	if place == 1:
		Sound.duck(2.0)


# One player's line: their place (or DONKEY), name, and the coins they won or lost.
func _row(entry: Dictionary) -> Control:
	var row := PanelContainer.new()
	var mine := str(entry.get("id", "")) == Game.player_id
	row.add_theme_stylebox_override("panel", Ui.box(Color(1, 1, 1, 0.12) if mine else Color(0, 0, 0, 0.25), 12, 16, 6))
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 14)
	row.add_child(line)
	var place := int(entry.get("place", 0))
	var donkey: bool = entry.get("donkey", false)
	var badge := Label.new()
	badge.custom_minimum_size = Vector2(110, 0)
	badge.add_theme_font_override("font", Ui.bold_font)
	badge.add_theme_font_size_override("font_size", 20)
	if donkey:
		badge.text = "DONKEY"
		badge.add_theme_color_override("font_color", Color("ffab91"))
	elif place == 1:
		badge.text = "MASTER"
		badge.add_theme_color_override("font_color", Ui.GOLD)
	elif place > 0:
		badge.text = DonkeySeat.ordinal(place)
		badge.add_theme_color_override("font_color", WON)
	else:
		badge.text = "LEFT" if entry.get("left", false) else "-"
		badge.add_theme_color_override("font_color", Color(1, 1, 1, 0.6))
	line.add_child(badge)
	var icon := TextureRect.new()
	icon.custom_minimum_size = Vector2(34, 34)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.texture = DonkeyHome.picture("donkey") if donkey else (DonkeyHome.picture("crown") if place == 1 else null)
	line.add_child(icon)
	var name_label := Label.new()
	name_label.text = "You" if mine else str(entry.get("username", "Player"))
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.add_theme_font_size_override("font_size", 22)
	line.add_child(name_label)
	var coins := int(entry.get("coins", 0))
	var amount := CoinLabel.new()
	amount.font_size = 22
	amount.prefix = "+" if coins > 0 else ""
	amount.amount = coins
	amount.text_color = WON if coins > 0 else (LOST if coins < 0 else Color(1, 1, 1, 0.7))
	amount.visible = int(Game.donkey.state.get("stake", 0)) > 0
	line.add_child(amount)
	return row
