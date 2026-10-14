extends CanvasLayer
## What every screen shares: the look of the game, message boxes, confirmations,
## the short notices that drop in at the top of the screen, and small touches of motion.
##
## Sizes are chosen for a phone held sideways: the game is laid out 720 units tall, so a
## button about 60 units high is roughly as tall as a fingertip.

const NOTICE_SECONDS := 3.5
## Notices stand on this line, in the strip between the table's top bar and its piles.
const NOTICES_BOTTOM := 134.0
const PASSWORD_BOX_TOP := 48
## The strip at the right end of a password field that holds the show/hide eye; a fingertip wide.
const REVEAL_WIDTH := 60.0
const NOTICE_COLORS := {
	"info": Color(0, 0, 0, 0.82),
	"warning": Color("ef6c00"),
	"error": Color("c62828"),
}
const NOTICE_SOUNDS := {"info": "notice", "warning": "warning", "error": "wrong"}

const FELT := Color("1b5e20")
const FELT_DARK := Color("0f3814")
const BAR := Color("0c2f11")
const PALE_GREEN := Color("c8e6c9")
const GOLD := Color("ffca28")
const PRIMARY := Color("43a047")
const BLUE := Color("1e88e5")
const TEAL := Color("00897b")
const ORANGE := Color("f57c00")
const RED := Color("d32f2f")
const SLATE := Color("546e7a")
const AMBER := Color("ffc107")

## The theme the main scene applies to itself; dialogs and notices use it too.
var game_theme: Theme
## A heavier cut of the default font, for titles and buttons.
var bold_font: FontVariation

var _message_box: AcceptDialog
var _question_box: ConfirmationDialog
var _password_box: ConfirmationDialog
var _password_text: Label
var _password_edit: LineEdit
var _password_eye: BaseButton
var _on_accept := Callable()
var _notices: VBoxContainer


func _ready() -> void:
	layer = 50
	bold_font = FontVariation.new()
	bold_font.base_font = ThemeDB.fallback_font
	bold_font.variation_embolden = 0.6
	game_theme = _build_theme()

	_message_box = AcceptDialog.new()
	_message_box.name = "MessageBox"
	_message_box.theme = game_theme
	_message_box.dialog_autowrap = true
	add_child(_message_box)

	_question_box = ConfirmationDialog.new()
	_question_box.name = "QuestionBox"
	_question_box.theme = game_theme
	_question_box.dialog_autowrap = true
	_question_box.confirmed.connect(_on_question_accepted)
	add_child(_question_box)

	_password_box = ConfirmationDialog.new()
	_password_box.name = "PasswordBox"
	_password_box.theme = game_theme
	_password_box.confirmed.connect(_on_password_accepted)
	add_child(_password_box)
	var password_form := VBoxContainer.new()
	password_form.add_theme_constant_override("separation", 12)
	_password_box.add_child(password_form)
	_password_text = Label.new()
	_password_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	# Wrapped at a known width from the start: otherwise the first box opened wraps the text a
	# word per line and runs far off the bottom of the screen, buttons and all
	_password_text.custom_minimum_size.x = 500
	password_form.add_child(_password_text)
	_password_edit = LineEdit.new()
	_password_edit.name = "PasswordBoxEdit"
	_password_edit.placeholder_text = "Password"
	_password_edit.secret = true
	password_form.add_child(_password_edit)
	_password_box.register_text_enter(_password_edit)

	_notices = VBoxContainer.new()
	_notices.name = "Notices"
	_notices.theme = game_theme
	_notices.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_notices.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_notices.grow_horizontal = Control.GROW_DIRECTION_BOTH
	# The newest notice is the lowest. When two are up at once the older one moves up over
	# the top bar, so they never hang down over the piles and the status text.
	_notices.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_notices.offset_top = NOTICES_BOTTOM
	_notices.offset_bottom = NOTICES_BOTTOM
	add_child(_notices)

	Game.notice.connect(notify)
	Game.action_failed.connect(alert)
	# Every button in the game dips a little when pressed, and every password field gets an eye
	get_tree().node_added.connect(_on_node_added)
	_password_eye = add_reveal_button(_password_edit)


## Shows a message with an OK button.
func alert(text: String, title: String = "Namma Rummy") -> void:
	Sound.play("error")
	_message_box.title = title
	_message_box.dialog_text = text
	_message_box.popup_centered(Vector2i(620, 0))


## Asks a question; `on_accept` runs only if the player agrees.
func confirm(title: String, text: String, accept_text: String, on_accept: Callable) -> void:
	_on_accept = on_accept
	_question_box.title = title
	_question_box.dialog_text = text
	_question_box.ok_button_text = accept_text
	_question_box.popup_centered(Vector2i(620, 0))


## Asks for the password before something that cannot be undone; `on_accept` gets what was typed.
func ask_password(title: String, text: String, accept_text: String, on_accept: Callable) -> void:
	_on_accept = on_accept
	_password_box.title = title
	_password_text.text = text
	_password_edit.text = ""
	_password_eye.button_pressed = false
	_password_box.ok_button_text = accept_text
	_password_box.popup_centered(Vector2i(560, 0))
	# Near the top of the screen, so a phone's keyboard does not cover the field
	_password_box.position.y = PASSWORD_BOX_TOP
	_password_edit.grab_focus()


## Closes whatever message or question is open. Returns false if there was none.
func close_dialogs() -> bool:
	var closed := false
	for dialog: Window in [_message_box, _question_box, _password_box]:
		if dialog.visible:
			dialog.hide()
			closed = true
	return closed


## Shows a short notice at the top of the screen. `kind` is "info", "warning" or "error".
func notify(kind: String, message: String) -> void:
	Sound.play(NOTICE_SOUNDS.get(kind, "notice"))
	if kind == "error":
		# Bad news (a wrong declaration, a server error) jolts the table
		Fx.shake(9.0, 0.35)
		Fx.flash(Color(0.8, 0.0, 0.0, 0.3), 0.5)
	var panel := PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	panel.add_theme_stylebox_override("panel", box(NOTICE_COLORS.get(kind, NOTICE_COLORS.info), 22, 24, 10))
	var label := Label.new()
	label.text = message
	label.add_theme_font_size_override("font_size", 22)
	panel.add_child(label)
	_notices.add_child(panel)

	# Drops in, stays, fades out
	panel.modulate.a = 0.0
	panel.scale = Vector2(0.9, 0.9)
	panel.pivot_offset = panel.get_combined_minimum_size() / 2.0
	var tween := panel.create_tween()
	tween.tween_property(panel, "modulate:a", 1.0, 0.18)
	tween.parallel().tween_property(panel, "scale", Vector2.ONE, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_interval(NOTICE_SECONDS)
	tween.tween_property(panel, "modulate:a", 0.0, 0.4)
	tween.tween_callback(panel.queue_free)


## A number of coins the way amounts are written in India: 125000 is "1,25,000".
func coins_text(amount: int) -> String:
	var digits := str(absi(amount))
	var text := digits.substr(maxi(0, digits.length() - 3))
	digits = digits.substr(0, maxi(0, digits.length() - 3))
	while not digits.is_empty():
		text = digits.substr(maxi(0, digits.length() - 2)) + "," + text
		digits = digits.substr(0, maxi(0, digits.length() - 2))
	return ("-" if amount < 0 else "") + text


## What a player is told before leaving a game in progress. At a table played for coins the
## entry is not given back.
func leave_game_warning() -> String:
	var text := "Leaving counts as a drop and you cannot rejoin this game."
	var stake := int(Game.state.get("stake", 0))
	var point_value := int(Game.state.get("pointValue", 0))
	if point_value > 0:
		# A Points table for coins a point: leaving costs the 40 points of a middle drop
		text += "\n\nThe drop costs 40 points: %s coins." % coins_text(40 * point_value)
	elif stake > 0:
		text += "\n\nThe %s coins you paid to sit down stay in the pot." % coins_text(stake)
	return text


## The same before leaving a lobby, where nothing has been played yet.
func leave_lobby_warning() -> String:
	var text := "Are you sure you want to leave the game?"
	var stake := int(Game.state.get("stake", 0))
	if stake > 0:
		text += "\n\nYou get your %s coins back." % coins_text(stake)
	return text


## A flat, rounded background box.
func box(color: Color, radius: int, margin_x: float, margin_y: float) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.set_corner_radius_all(radius)
	style.content_margin_left = margin_x
	style.content_margin_right = margin_x
	style.content_margin_top = margin_y
	style.content_margin_bottom = margin_y
	style.anti_aliasing = true
	return style


## Gives one button its own colour (the theme's buttons are slate).
func tint_button(button: Button, color: Color) -> void:
	for state_name: String in ["normal", "hover", "pressed", "disabled"]:
		button.add_theme_stylebox_override(state_name, _button_box(color, state_name))


## Puts an eye at the right end of a password field: tap it to see what was typed, tap again to
## hide it. Every field with `secret` set gets one on its own; this is for fields made before that.
func add_reveal_button(edit: LineEdit) -> BaseButton:
	if edit.has_node("RevealButton"):
		return edit.get_node("RevealButton")
	var eye := TextureButton.new()
	eye.name = "RevealButton"
	eye.toggle_mode = true
	# The field keeps the cursor (and a phone its keyboard) while the eye is tapped
	eye.focus_mode = Control.FOCUS_NONE
	eye.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	eye.tooltip_text = "Show password"
	eye.anchor_left = 1.0
	eye.anchor_right = 1.0
	eye.anchor_bottom = 1.0
	eye.offset_left = -REVEAL_WIDTH
	eye.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	eye.toggled.connect(func(shown: bool) -> void:
		edit.secret = not shown
		eye.tooltip_text = "Hide password" if shown else "Show password")
	eye.draw.connect(_draw_eye.bind(eye, edit))
	# The text stops short of the eye instead of running under it
	for state_name: String in ["normal", "read_only"]:
		var style := edit.get_theme_stylebox(state_name).duplicate() as StyleBox
		style.content_margin_right = REVEAL_WIDTH
		edit.add_theme_stylebox_override(state_name, style)
	edit.add_child(eye)
	return eye


## Makes a control grow from small to full size, with a little bounce. For things that appear.
func pop_in(control: Control, delay: float = 0.0) -> void:
	control.pivot_offset = control.size / 2.0
	control.scale = Vector2(0.8, 0.8)
	control.modulate.a = 0.0
	var tween := control.create_tween()
	if delay > 0.0:
		tween.tween_interval(delay)
	tween.tween_property(control, "modulate:a", 1.0, 0.15)
	tween.parallel().tween_property(control, "scale", Vector2.ONE, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


## A quick swell and settle, to draw the eye to something that just changed.
func pulse(control: Control, amount: float = 1.12) -> void:
	control.pivot_offset = control.size / 2.0
	var tween := control.create_tween()
	tween.tween_property(control, "scale", Vector2(amount, amount), 0.14).set_trans(Tween.TRANS_SINE)
	tween.tween_property(control, "scale", Vector2.ONE, 0.22).set_trans(Tween.TRANS_SINE)


func _on_question_accepted() -> void:
	# The screen that asked may have closed while the question was open
	if _on_accept.is_valid():
		_on_accept.call()
	_on_accept = Callable()


func _on_password_accepted() -> void:
	if _on_accept.is_valid():
		_on_accept.call(_password_edit.text)
	_on_accept = Callable()
	_password_edit.text = ""


func _on_node_added(node: Node) -> void:
	var edit := node as LineEdit
	if edit != null and edit.secret:
		add_reveal_button(edit)
		return
	var button := node as BaseButton
	if button == null or button is LinkButton or button is CheckBox:
		return
	button.button_down.connect(_press.bind(button, true))
	button.button_up.connect(_press.bind(button, false))


func _press(button: BaseButton, down: bool) -> void:
	if down:
		Sound.play("click")
	button.pivot_offset = button.size / 2.0
	var target := Vector2(0.95, 0.95) if down else Vector2.ONE
	button.create_tween().tween_property(button, "scale", target, 0.08)


# An eye drawn in code, like the cards, so a phone without an icon font shows no empty box.
# Struck through while the password is showing: tapping it then hides the password again.
func _draw_eye(eye: BaseButton, edit: LineEdit) -> void:
	var color := Color("424242") if eye.is_hovered() or eye.button_pressed else Color("757575")
	var middle := eye.size / 2.0
	var half_width := 15.0
	var half_height := 9.0
	var outline := PackedVector2Array()
	for lid: float in [-1.0, 1.0]:
		for i in range(17):
			var t := i / 16.0
			if lid > 0.0:
				t = 1.0 - t  # the lower lid runs back, so the outline closes
			outline.append(middle + Vector2(lerpf(-half_width, half_width, t), lid * half_height * sin(PI * t)))
	eye.draw_polyline(outline, color, 2.5, true)
	eye.draw_circle(middle, 5.0, color, true, -1.0, true)
	if eye.button_pressed:
		var slash := Vector2(13, 12)
		var field := edit.get_theme_stylebox("normal") as StyleBoxFlat
		if field != null:
			eye.draw_line(middle - slash, middle + slash, field.bg_color, 7.0, true)
		eye.draw_line(middle - slash, middle + slash, color, 2.5, true)


# A button with a darker lower edge, so it reads as something to press.
func _button_box(color: Color, state_name: String) -> StyleBoxFlat:
	var shade := color
	if state_name == "hover":
		shade = color.lightened(0.1)
	elif state_name == "pressed":
		shade = color.darkened(0.12)
	elif state_name == "disabled":
		shade = Color(color, 0.32)
	var style := box(shade, 16, 26, 13)
	if state_name != "disabled":
		style.border_color = shade.darkened(0.32)
		style.border_width_bottom = 4
		style.shadow_color = Color(0, 0, 0, 0.28)
		style.shadow_size = 3
		style.shadow_offset = Vector2(0, 2)
	return style


func _build_theme() -> Theme:
	var built := Theme.new()
	built.default_font_size = 24

	for state_name: String in ["normal", "hover", "pressed", "disabled"]:
		built.set_stylebox(state_name, "Button", _button_box(SLATE, state_name))
	built.set_stylebox("focus", "Button", StyleBoxEmpty.new())
	built.set_font("font", "Button", bold_font)
	for color_name: String in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color", "font_hover_pressed_color"]:
		built.set_color(color_name, "Button", Color.WHITE)
	built.set_color("font_disabled_color", "Button", Color(1, 1, 1, 0.5))

	var field := box(Color.WHITE, 12, 18, 13)
	field.border_color = Color("bdbdbd")
	field.set_border_width_all(1)
	built.set_stylebox("normal", "LineEdit", field)
	var field_focus := box(Color.TRANSPARENT, 12, 18, 13)
	field_focus.draw_center = false
	field_focus.border_color = BLUE
	field_focus.set_border_width_all(3)
	built.set_stylebox("focus", "LineEdit", field_focus)
	built.set_color("font_color", "LineEdit", Color("212121"))
	built.set_color("font_placeholder_color", "LineEdit", Color("9e9e9e"))
	built.set_color("caret_color", "LineEdit", Color("212121"))
	built.set_color("selection_color", "LineEdit", Color(BLUE, 0.35))

	var panel := box(Color(0, 0, 0, 0.34), 22, 30, 24)
	panel.border_color = Color(1, 1, 1, 0.1)
	panel.set_border_width_all(1)
	built.set_stylebox("panel", "PanelContainer", panel)

	# Drop-down lists: rows tall enough for a finger
	built.set_font_size("font_size", "PopupMenu", 24)
	built.set_constant("v_separation", "PopupMenu", 18)

	# Message boxes in the table's colours instead of the engine's grey
	var dialog := box(Color("123f17"), 0, 22, 18)
	built.set_stylebox("panel", "AcceptDialog", dialog)
	var frame := ThemeDB.get_default_theme().get_stylebox("embedded_border", "Window").duplicate() as StyleBoxFlat
	if frame != null:
		frame.bg_color = BAR
		frame.border_color = GOLD.darkened(0.25)
		frame.set_border_width_all(2)
		frame.set_corner_radius_all(14)
		built.set_stylebox("embedded_border", "Window", frame)
		built.set_stylebox("embedded_unfocused_border", "Window", frame)
	built.set_font("title_font", "Window", bold_font)
	built.set_font_size("title_font_size", "Window", 22)
	built.set_color("title_color", "Window", GOLD)
	return built
