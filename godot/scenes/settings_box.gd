class_name SettingsBox
extends MenuOverlay
## Settings, behind the cog in the menu's top bar: music and sound effects on or off, the
## privacy policy and the terms of use, Google's privacy choices for ads (only for players
## who must have them), and logging out. The profile (name, email, games,
## deleting the account) stays behind the player's name and coins.
##
## Built in code, like the search box of Play Now: a cream box in a teal frame with its title
## on a banner, closed by its tag, a tap beside it, or the phone's back button.

const BROWN := Color("5d4037")
const DIM := Color("8d6e63")
const LINE := Color("e0d3bd")
const ON_COLOR := Color("43a047")
const OFF_COLOR := Color("9e9e9e")
const TEAL := Color("2bb3a3")

var _music_button: Button
var _effects_button: Button
var _logout_button: Button
var _privacy_choices: Button


func _init() -> void:
	name = "SettingsBox"
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP

	var shade := ColorRect.new()
	shade.name = "Shade"
	shade.color = Color(0, 0, 0, 0.72)
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(shade)

	var box := PanelContainer.new()
	box.name = "Box"
	box.anchor_left = 0.5
	box.anchor_right = 0.5
	box.anchor_top = 0.5
	box.anchor_bottom = 0.5
	box.offset_left = -330.0
	box.offset_right = 330.0
	box.grow_horizontal = Control.GROW_DIRECTION_BOTH
	box.grow_vertical = Control.GROW_DIRECTION_BOTH
	add_child(box)

	var column := VBoxContainer.new()
	column.name = "SettingsColumn"
	column.add_theme_constant_override("separation", 10)
	box.add_child(column)

	# The header row MenuOverlay dresses: the title on a banner, a tag to close
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 0)
	var left := Control.new()
	left.custom_minimum_size = Vector2(56, 0)
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(left)
	var title := Label.new()
	title.name = "SettingsTitle"
	title.text = "Settings"
	header.add_child(title)
	var right := Control.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(right)
	var close_button := Button.new()
	close_button.name = "SettingsCloseButton"
	close_button.pressed.connect(close)
	header.add_child(close_button)
	column.add_child(header)

	# Room for the player's photo (added by the avatar editor); takes no space while empty
	var avatar_slot := VBoxContainer.new()
	avatar_slot.name = "AvatarSlot"
	column.add_child(avatar_slot)

	column.add_child(_heading("SOUND"))
	_music_button = _switch_row(column, "Music", "MusicToggle")
	_effects_button = _switch_row(column, "Sound effects", "SoundToggle")
	column.add_child(_rule())

	column.add_child(_heading("ABOUT"))
	var links := HBoxContainer.new()
	links.alignment = BoxContainer.ALIGNMENT_CENTER
	links.add_theme_constant_override("separation", 16)
	links.add_child(_link_button("Privacy policy", "SettingsPrivacyButton", "/privacy"))
	links.add_child(_link_button("Terms of use", "SettingsTermsButton", "/terms"))
	column.add_child(links)
	# Google's form for changing the choice about ads made at the first start. Only players
	# who were asked (in the EEA, the UK and Switzerland) have it; see open().
	_privacy_choices = Button.new()
	_privacy_choices.name = "PrivacyChoicesButton"
	_privacy_choices.text = "Privacy choices for ads"
	_privacy_choices.custom_minimum_size = Vector2(300, 52)
	_privacy_choices.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_privacy_choices.focus_mode = Control.FOCUS_NONE
	_privacy_choices.add_theme_font_size_override("font_size", 20)
	_privacy_choices.visible = false
	_privacy_choices.pressed.connect(func() -> void: Ads.show_privacy_options())
	column.add_child(_privacy_choices)
	column.add_child(_rule())

	_logout_button = Button.new()
	_logout_button.name = "LogoutButton"
	_logout_button.text = "Log out"
	_logout_button.custom_minimum_size = Vector2(260, 60)
	_logout_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_logout_button.add_theme_font_size_override("font_size", 26)
	_logout_button.pressed.connect(_on_logout)
	column.add_child(_logout_button)

	var version := Label.new()
	version.name = "VersionLabel"
	version.text = "%s %s" % [
		ProjectSettings.get_setting("application/config/name", "Namma Rummy"),
		ProjectSettings.get_setting("application/config/version", ""),
	]
	version.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	version.add_theme_font_size_override("font_size", 16)
	version.add_theme_color_override("font_color", DIM)
	column.add_child(version)


func _ready() -> void:
	super._ready()
	Ui.tint_button(_logout_button, Ui.RED)
	Ui.tint_button(_privacy_choices, Ui.SLATE)
	_music_button.pressed.connect(func() -> void: Sound.music_on = not Sound.music_on)
	_effects_button.pressed.connect(_on_effects_pressed)
	Sound.switches_changed.connect(_refresh)
	_refresh()


## Opens the box. Whether the player needs the privacy choices for ads is known only once
## Google has answered at the start of the app, so it is asked each time.
func open() -> void:
	_privacy_choices.visible = Ads.privacy_options_required()
	super.open()


func _on_effects_pressed() -> void:
	Sound.sound_on = not Sound.sound_on
	Sound.play("click")  # heard only when the switch has just gone on


func _on_logout() -> void:
	Ui.confirm("Log out", "Log out of Namma Rummy? You will need your password to log in again.", "Log out", Game.logout)


# The two switches say what they are set to, green for on and grey for off.
func _refresh() -> void:
	_show_switch(_music_button, Sound.music_on)
	_show_switch(_effects_button, Sound.sound_on)


func _show_switch(button: Button, on: bool) -> void:
	button.text = "ON" if on else "OFF"
	Ui.tint_button(button, ON_COLOR if on else OFF_COLOR)


func _heading(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 18)
	label.add_theme_color_override("font_color", DIM)
	return label


# A thin line between the parts of the box.
func _rule() -> Control:
	var line := ColorRect.new()
	line.color = LINE
	line.custom_minimum_size = Vector2(0, 2)
	return line


# "Music ........ ON": the words at the left, the switch at the right.
func _switch_row(column: VBoxContainer, words: String, node_name: String) -> Button:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	var label := Label.new()
	label.text = words
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.add_theme_font_size_override("font_size", 26)
	label.add_theme_color_override("font_color", BROWN)
	row.add_child(label)
	var button := Button.new()
	button.name = node_name
	button.custom_minimum_size = Vector2(120, 54)
	button.focus_mode = Control.FOCUS_NONE
	button.add_theme_font_size_override("font_size", 22)
	row.add_child(button)
	column.add_child(row)
	return button


# A page of the game server's site, opened in the phone's browser.
func _link_button(words: String, node_name: String, path: String) -> Button:
	var button := Button.new()
	button.name = node_name
	button.text = words
	button.custom_minimum_size = Vector2(220, 56)
	button.focus_mode = Control.FOCUS_NONE
	button.add_theme_font_size_override("font_size", 22)
	button.pressed.connect(func() -> void: OS.shell_open(Game.server_url + path))
	button.ready.connect(func() -> void: Ui.tint_button(button, TEAL))
	return button
