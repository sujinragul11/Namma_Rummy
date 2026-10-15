class_name ProfilePanel
extends Control
## The player's own account, over the home screen: games played and won, the coins, and the
## username and email address, which can be changed here.
##
## The numbers come from the server each time the panel opens (`Game.fetch_profile`).

const SCENE_PATH := "res://scenes/profile.tscn"
const MONTHS := ["January", "February", "March", "April", "May", "June", "July", "August", "September", "October", "November", "December"]

var _fields_filled := false  # the fields take the account's values once, then belong to the player
var _badge: PlayerBadge  # the avatar with the name, and a line about the account under it

@onready var _panel: Control = %Panel
@onready var _title: Label = %Title
@onready var _close_button: Button = %CloseButton
@onready var _name_edit: LineEdit = %ProfileNameEdit
@onready var _email_edit: LineEdit = %ProfileEmailEdit
@onready var _save_button: Button = %SaveProfileButton
@onready var _badge_holder: Control = %BadgeHolder
@onready var _played_value: Label = %PlayedValue
@onready var _won_value: Label = %WonValue
@onready var _rate_value: Label = %RateValue
@onready var _coins_value: Label = %CoinsValue
@onready var _delete_button: Button = %DeleteAccountButton


## Opens the panel over `screen`, unless a panel is open already.
static func open(screen: Control) -> void:
	if screen.get_tree().get_first_node_in_group(FriendsPanel.BACK_GROUP) != null:
		return
	var panel: ProfilePanel = (load(SCENE_PATH) as PackedScene).instantiate()
	screen.add_child(panel)


func _ready() -> void:
	add_to_group(FriendsPanel.BACK_GROUP)  # the back button closes it
	# Solid like the message boxes: the screen underneath must not show through
	var frame := Ui.box(Ui.FELT_DARK, 22, 30, 22)
	frame.border_color = Ui.GOLD.darkened(0.25)
	frame.set_border_width_all(2)
	_panel.add_theme_stylebox_override("panel", frame)
	_title.add_theme_font_override("font", Ui.bold_font)
	for value: Label in [_played_value, _won_value, _rate_value, _coins_value]:
		value.add_theme_font_override("font", Ui.bold_font)
	Ui.tint_button(_save_button, Ui.PRIMARY)
	# The founder's credit at the foot of the panel: small, with the letters a little spaced out
	var credit := FontVariation.new()
	credit.base_font = ThemeDB.fallback_font
	credit.spacing_glyph = 1
	%FounderLabel.add_theme_font_override("font", credit)

	_badge = PlayerBadge.new()
	_badge.avatar_size = 72.0
	_badge_holder.add_child(_badge)

	_close_button.pressed.connect(close)
	_save_button.pressed.connect(_on_save)
	_delete_button.pressed.connect(_on_delete_account)
	_name_edit.text_changed.connect(_refresh.unbind(1))
	_email_edit.text_changed.connect(_refresh.unbind(1))
	_email_edit.text_submitted.connect(_on_save.unbind(1))
	%Shade.gui_input.connect(_on_shade_input)

	Game.profile_changed.connect(_refresh)
	Game.coins_changed.connect(_refresh)
	Game.busy_changed.connect(_refresh)
	Game.connection_changed.connect(_refresh)
	_refresh()
	Game.fetch_profile()
	get_tree().process_frame.connect(_appear, CONNECT_ONE_SHOT)


func close() -> void:
	queue_free()


# Once the first layout has given the panel its size, it grows into place.
func _appear() -> void:
	Ui.pop_in(_panel)


func _on_shade_input(event: InputEvent) -> void:
	# A tap beside the panel closes it
	var click := event as InputEventMouseButton
	if click != null and click.pressed and click.button_index == MOUSE_BUTTON_LEFT:
		close()


func _refresh() -> void:
	var known := Game.profile
	var username := str(Game.user.get("username", ""))
	var email := str(known.get("email", Game.user.get("email", "")))

	# The fields are filled once the server has answered, and again after saving
	if not _fields_filled and not known.is_empty():
		_fields_filled = true
		_name_edit.text = username
		_email_edit.text = email

	var played := int(known.get("totalGames", 0))
	var won := int(known.get("gamesWon", 0))
	_played_value.text = str(played) if not known.is_empty() else "-"
	_won_value.text = str(won) if not known.is_empty() else "-"
	_rate_value.text = "%d%%" % roundi(float(known.get("winPercentage", 0.0))) if played > 0 else "-"
	_coins_value.text = Ui.coins_text(Game.coins)

	var details: Array = []
	if not str(known.get("phone", "")).is_empty():
		details.append("Mobile %s" % known.get("phone"))
	var since := _month_of(str(known.get("created_at", "")))
	if not since.is_empty():
		details.append("Playing since %s" % since)
	_badge.show_player(username, "  ·  ".join(details), false)
	_badge.show_photo(Game.player_id, Game.my_avatar())

	var changed := _name_edit.text.strip_edges() != username or _email_edit.text.strip_edges().to_lower() != email.to_lower()
	_save_button.disabled = not changed or not _fields_filled or Game.busy or not Game.is_online()


func _on_save() -> void:
	if _save_button.disabled:
		return
	var username := _name_edit.text.strip_edges()
	if username.is_empty():
		Ui.alert("Enter a username.", "Profile")
		return
	Game.update_profile(username, _email_edit.text)


# The app stores require that an account made in the app can also be deleted in the app.
func _on_delete_account() -> void:
	Ui.ask_password(
		"Delete account",
		"This permanently deletes your account, your coins, your game results and your friends list. Enter your password to confirm.",
		"Delete",
		Game.delete_account
	)


# "2026-10-09T05:12:44.000Z" -> "October 2026"
func _month_of(timestamp: String) -> String:
	var parts := timestamp.split("-")
	if parts.size() < 2 or not parts[0].is_valid_int() or not parts[1].is_valid_int():
		return ""
	var month := int(parts[1])
	if month < 1 or month > 12:
		return ""
	return "%s %s" % [MONTHS[month - 1], parts[0]]
