extends MenuOverlay
## Public table profile. Fetching it does not make the game busy or pause the turn clock.

var _user_id := ""
var _username := "Player"
var _photo: Control
var _name_label: Label
var _coins: CoinLabel
var _add: Button
var _message: Label
var _values: Array[Label] = []
var _requesting := false
var load_on_open := true # UI previews can supply a fixture without opening a connection.

func _init(user_id: String = "") -> void:
	_user_id = user_id
	name = "OpponentProfile"
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var shade := ColorRect.new()
	shade.name = "Shade"
	shade.color = Color(0, 0, 0, 0.72)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(shade)
	var box := PanelContainer.new()
	box.name = "Box"
	box.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	box.offset_left = -460
	box.offset_right = 460
	box.grow_vertical = Control.GROW_DIRECTION_BOTH
	add_child(box)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 16)
	box.add_child(column)
	var header := HBoxContainer.new()
	column.add_child(header)
	var gap := Control.new()
	gap.custom_minimum_size.x = 56
	gap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(gap)
	var title := Label.new()
	title.text = "Profile"
	header.add_child(title)
	var gap_right := Control.new()
	gap_right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(gap_right)
	var close_button := Button.new()
	close_button.name = "OpponentProfileClose"
	close_button.pressed.connect(close)
	header.add_child(close_button)
	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 20)
	column.add_child(body)
	var left := PanelContainer.new()
	left.custom_minimum_size.x = 280
	left.add_theme_stylebox_override("panel", Ui.box(ProfilePanel.SUNKEN, 8, 18, 22))
	body.add_child(left)
	var identity := VBoxContainer.new()
	identity.alignment = BoxContainer.ALIGNMENT_CENTER
	identity.add_theme_constant_override("separation", 14)
	left.add_child(identity)
	_photo = Control.new()
	_photo.custom_minimum_size = Vector2(156, 156)
	_photo.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	identity.add_child(_photo)
	_name_label = Label.new()
	_name_label.name = "OpponentName"
	_name_label.clip_text = true
	_name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_name_label.add_theme_font_size_override("font_size", 23)
	_name_label.add_theme_stylebox_override("normal", Ui.box(ProfilePanel.PILL, 22, 12, 6))
	identity.add_child(_name_label)
	_coins = CoinLabel.new()
	_coins.name = "OpponentCoins"
	_coins.font_size = 26
	_coins.text_color = ProfilePanel.INK
	_coins.alignment = BoxContainer.ALIGNMENT_CENTER
	_coins.visible = false
	identity.add_child(_coins)
	_add = Button.new()
	_add.name = "OpponentAddFriend"
	_add.text = "Add as Friend"
	_add.custom_minimum_size.y = 52
	Ui.tint_button(_add, Ui.PRIMARY)
	_add.pressed.connect(_add_friend)
	identity.add_child(_add)
	var stats := VBoxContainer.new()
	stats.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stats.add_theme_constant_override("separation", 12)
	body.add_child(stats)
	var heading := Label.new()
	heading.text = "STATISTICS"
	heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	heading.add_theme_font_size_override("font_size", 32)
	heading.add_theme_color_override("font_color", ProfilePanel.DIM)
	stats.add_child(heading)
	for caption: String in ["GAMES PLAYED", "GAMES WON", "WON RATIO", "FRIENDS"]:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 0)
		stats.add_child(row)
		var label := Label.new()
		label.text = caption
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		label.add_theme_font_size_override("font_size", 22)
		label.add_theme_color_override("font_color", ProfilePanel.INK)
		label.add_theme_stylebox_override("normal", Ui.box(ProfilePanel.ROW, 5, 18, 14))
		row.add_child(label)
		var value := Label.new()
		value.text = "—"
		value.custom_minimum_size.x = 130
		value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		value.add_theme_font_size_override("font_size", 26)
		value.add_theme_color_override("font_color", ProfilePanel.INK)
		value.add_theme_stylebox_override("normal", Ui.box(ProfilePanel.VALUE, 5, 16, 12))
		row.add_child(value)
		_values.append(value)
	_message = Label.new()
	_message.text = "Loading player details… The turn timer continues."
	_message.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_message.add_theme_font_size_override("font_size", 18)
	_message.add_theme_color_override("font_color", ProfilePanel.DIM)
	column.add_child(_message)

func _ready() -> void:
	super._ready()
	closed.connect(queue_free)
	Game.friends_changed.connect(_refresh_friend)
	Game.connection_changed.connect(_refresh_friend)
	for player: Dictionary in Game.players():
		if str(player.get("id", "")) == _user_id:
			_show_identity(player)
	_refresh_friend()
	if load_on_open:
		_load()

func _load() -> void:
	var response: Dictionary = await Game.socket.request("playerProfile", {"userId": _user_id})
	if response.get("ok", false):
		_show_profile(response.get("profile", {}))
	else:
		_message.text = str(response.get("error", "Unable to load this profile. Close and try again."))

func _show_identity(profile: Dictionary) -> void:
	_username = str(profile.get("username", "Player"))
	_name_label.text = _username
	for child in _photo.get_children():
		_photo.remove_child(child)
		child.queue_free()
	var avatar := ScoreCard.Avatar.new(_user_id, _username, int(profile.get("avatar", 0)), false, 0)
	avatar.scale = Vector2(2, 2)
	avatar.position = Vector2(8, 8)
	_photo.add_child(avatar)

func _show_profile(profile: Dictionary) -> void:
	_show_identity(profile)
	_coins.amount = int(profile.get("coins", 0))
	_coins.visible = true
	_values[0].text = Ui.coins_text(int(profile.get("totalGames", 0)))
	_values[1].text = Ui.coins_text(int(profile.get("gamesWon", 0)))
	_values[2].text = "%s %%" % str(profile.get("winPercentage", 0))
	_values[3].text = Ui.coins_text(int(profile.get("friends", 0)))
	_message.text = "The turn timer continues while this profile is open."
	_refresh_friend()

func _refresh_friend() -> void:
	_add.text = "Add as Friend"
	_add.disabled = _requesting or not Game.is_online()
	for friend: Dictionary in Game.friends:
		if str(friend.get("id", "")) == _user_id:
			_add.text = "Friends"
			_add.disabled = true
	for asked: Dictionary in Game.friend_asked:
		if str(asked.get("id", "")) == _user_id:
			_add.text = "Request sent"
			_add.disabled = true
	for incoming: Dictionary in Game.friend_requests:
		if str(incoming.get("id", "")) == _user_id:
			_add.text = "Accept request"

func _add_friend() -> void:
	_requesting = true
	_refresh_friend()
	var response: Dictionary = await Game.add_friend(_username)
	_requesting = false
	_refresh_friend()
	if response.get("ok", false):
		_add.text = "Friends" if response.get("accepted", false) else "Request sent"
		_add.disabled = true
