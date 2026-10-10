extends Control
## Logged out: login or register, with the logo beside the form (the form scrolls, so it stays
## usable when the on-screen keyboard covers the lower half of a phone).
##
## Logged in: the menu, laid out like a card-game lobby. The player and the coins sit in a bar
## at the top with a few round buttons, big tiles in the middle open the kinds of game, and
## a bar of small buttons runs along the bottom. A game tile opens a box to set up the table;
## the friends tile opens the room-code form.

const GAME_TYPES := [["Points", "points"], ["Pool 101", "pool"], ["Close Joker 240", "close_joker"]]
const GAME_TITLES := ["Points Rummy", "Pool Rummy", "Close Joker Rummy"]
const PLAYER_CHOICES := [2, 3, 4, 6]
# The pool games, offered side by side in the setup box as "101 Points / 240 Points"
const POOL_CHOICES := [["101 Points", 1], ["240 Points", 2]]
const SETUP_BROWN := Color("8d6e63")
const TEAL_BUTTON := Color("2bb3a3")
const GREEN_BUTTON := Color("43b649")
const YELLOW_BUTTON := Color("f2c21b")
# The server answers "Invalid credentials" both for an unknown account and for a wrong password
const WRONG_LOGIN_MESSAGE := "That email, phone or username and password do not match an account.\n\nNew here? Use \"Don't have an account? Register\"."
const ROUND_BUTTON := 52.0
const AVATAR_RING := 3.0
const RULES := """Every player gets 13 cards. On your turn, draw a card from the deck or the open pile, then discard one.

Arrange your cards into sequences (3 or more cards of one suit in a row, like 5-6-7 of hearts) and sets (3 or 4 cards of one rank in different suits). To declare, all your cards must be in sequences and sets, with at least two sequences, one of them pure: no joker standing in for a card.

A card is cut as the joker every round. Every card of that rank is wild, together with the printed jokers.

Points: J, Q, K and A count 10, number cards their value, jokers 0. The winner scores 0; a losing hand counts its loose cards, up to 80. Dropping out costs 20 before your first turn and 40 after. A wrong declaration costs 80.

Points Rummy is one round. Pool Rummy goes round after round: reach 101 and you are out; the last player left wins. Close Joker is pool to 240, and the joker lies face down until you have made a pure sequence.

When someone declares, everyone else gets 15 seconds to arrange their cards before they are counted. Every turn has 30 seconds.

Coins are play tokens with no cash value. Every player pays the table's entry on sitting down, and the winner of the game takes everything paid in."""

var _registering := false
var _keyboard_height := 0
var _frames_until_scroll := 0  # the layout needs a few frames to settle before scrolling to a field
var _float_time := 0.0
var _logo_rest_y := 0.0  # where the layout puts the logo; it floats around this
var _until_twinkle := 1.5  # seconds until the next glint on the logo
var _stake_picked := false  # false until the player has chosen an entry themselves
var _coins_label: CoinLabel
var _stake_coins: CoinLabel  # the amount in the pill above the slider
var _player_chips: Array[ChoiceChip] = []  # one per PLAYER_CHOICES entry
var _pool_chips: Array[ChoiceChip] = []  # one per POOL_CHOICES entry

@onready var _login_row: Control = %Margin
@onready var _brand: VBoxContainer = %Brand
@onready var _logo: TextureRect = %Logo
@onready var _tagline: Label = %Tagline
@onready var _side: ScrollContainer = %Side
@onready var _auth_panel: Control = %AuthPanel
@onready var _auth_title: Label = %AuthTitle
@onready var _username_edit: LineEdit = %UsernameEdit
@onready var _email_edit: LineEdit = %EmailEdit
@onready var _phone_edit: LineEdit = %PhoneEdit
@onready var _identifier_edit: LineEdit = %IdentifierEdit
@onready var _password_edit: LineEdit = %PasswordEdit
@onready var _submit_button: Button = %SubmitButton
@onready var _switch_button: Button = %SwitchButton
@onready var _server_row: Control = %ServerRow
@onready var _server_edit: LineEdit = %ServerEdit

@onready var _menu_panel: Control = %MenuPanel
@onready var _avatar_pill: PanelContainer = %AvatarPill
@onready var _avatar: Control = %Avatar
@onready var _welcome_label: Label = %WelcomeLabel
@onready var _status_label: Label = %StatusLabel
@onready var _coin_pill: PanelContainer = %CoinPill
@onready var _help_button: Button = %HelpButton
@onready var _account_button: Button = %AccountButton
@onready var _points_tile: GameTile = %PointsTile
@onready var _pool_tile: GameTile = %PoolTile
@onready var _close_joker_tile: GameTile = %CloseJokerTile
@onready var _friends_tile: GameTile = %FriendsTile

@onready var _setup_overlay: MenuOverlay = %SetupOverlay
@onready var _setup_title: Label = %SetupTitle
@onready var _setup_close_button: Button = %SetupCloseButton
@onready var _type_option: OptionButton = %TypeOption
@onready var _players_option: OptionButton = %PlayersOption
@onready var _stake_option: OptionButton = %StakeOption
@onready var _players_chips: HBoxContainer = %PlayersChips
@onready var _pool_column: Control = %PoolColumn
@onready var _pool_divider: Control = %Divider
@onready var _pool_chips_row: HBoxContainer = %PoolChips
@onready var _stake_pill: PanelContainer = %StakePill
@onready var _free_label: Label = %FreeLabel
@onready var _stake_slider: HSlider = %StakeSlider
@onready var _create_button: Button = %CreateButton
@onready var _join_overlay: MenuOverlay = %JoinOverlay
@onready var _join_close_button: Button = %JoinCloseButton
@onready var _code_edit: LineEdit = %CodeEdit
@onready var _create_table_button: Button = %CreateTableButton
@onready var _join_button: Button = %JoinButton
@onready var _invite_friends_button: Button = %InviteFriendsButton
@onready var _rules_overlay: MenuOverlay = %RulesOverlay
@onready var _rules_close_button: Button = %RulesCloseButton
@onready var _rules_text: Label = %RulesText

@onready var _bottom_bar: PanelContainer = %BottomBar
@onready var _friends_button: Button = %FriendsButton
@onready var _profile_button: Button = %ProfileButton
@onready var _privacy_button: Button = %PrivacyButton
@onready var _terms_button: Button = %TermsButton
@onready var _logout_button: Button = %LogoutButton
@onready var _sound_switches: Control = %SoundSwitches


func _ready() -> void:
	for game_type: Array in GAME_TYPES:
		_type_option.add_item(game_type[0])
	for count: int in PLAYER_CHOICES:
		_players_option.add_item("%d players" % count)
	# What a table costs to sit at; the winner takes everything paid in
	for stake: int in GameClient.STAKES:
		_stake_option.add_item("Free table" if stake == 0 else "%s coins" % Ui.coins_text(stake))
	_stake_option.item_selected.connect(func(_index: int) -> void: _stake_picked = true)
	_type_option.item_selected.connect(func(index: int) -> void: _setup_title.text = GAME_TITLES[index])
	_server_edit.text = Game.server_url
	# The builds for the app stores always play on the public server
	_server_row.visible = not Config.store_build
	_rules_text.text = RULES

	_auth_title.add_theme_font_override("font", Ui.bold_font)
	_welcome_label.add_theme_font_override("font", Ui.bold_font)
	Ui.tint_button(_submit_button, Ui.PRIMARY)
	# The boxes' buttons in the lobby's colours: teal to play, green to open a table, yellow to join
	Ui.tint_button(_create_button, TEAL_BUTTON)
	Ui.tint_button(_create_table_button, GREEN_BUTTON)
	Ui.tint_button(_join_button, YELLOW_BUTTON)
	for button: Button in [_create_button, _create_table_button, _join_button]:
		button.add_theme_color_override("font_color", Color("1b5e20") if button != _create_button else Color("0b4d44"))
		button.add_theme_color_override("font_hover_color", button.get_theme_color("font_color"))
		button.add_theme_color_override("font_pressed_color", button.get_theme_color("font_color"))
	_build_top_bar()
	_build_setup_widgets()

	_submit_button.pressed.connect(_on_submit)
	_password_edit.text_submitted.connect(_on_submit.unbind(1))
	_switch_button.pressed.connect(_on_switch_mode)
	_points_tile.pressed.connect(_open_setup.bind(0))
	_pool_tile.pressed.connect(_open_setup.bind(1))
	_close_joker_tile.pressed.connect(_open_setup.bind(2))
	_friends_tile.pressed.connect(_join_overlay.open)
	_setup_close_button.pressed.connect(_setup_overlay.close)
	_join_close_button.pressed.connect(_join_overlay.close)
	_rules_close_button.pressed.connect(_rules_overlay.close)
	_create_button.pressed.connect(_on_create)
	_create_table_button.pressed.connect(_on_create_table)
	_join_button.pressed.connect(_on_join)
	_code_edit.text_submitted.connect(_on_join.unbind(1))
	_invite_friends_button.pressed.connect(_open_friends)
	_help_button.pressed.connect(_rules_overlay.open)
	_account_button.pressed.connect(_open_profile)
	_avatar_pill.gui_input.connect(_on_pill_input)
	_coin_pill.gui_input.connect(_on_pill_input)
	_friends_button.pressed.connect(_open_friends)
	_profile_button.pressed.connect(_open_profile)
	_logout_button.pressed.connect(Game.logout)
	_privacy_button.pressed.connect(_open_page.bind("/privacy"))
	_terms_button.pressed.connect(_open_page.bind("/terms"))

	Game.auth_changed.connect(_on_auth_changed)
	Game.auth_failed.connect(_on_auth_failed)
	Game.connection_changed.connect(_refresh)
	Game.busy_changed.connect(_refresh)
	Game.friends_changed.connect(_refresh)
	Game.coins_changed.connect(_refresh_coins)
	_refresh_coins()
	_brand.resized.connect(_fit_logo)
	_brand.sort_children.connect(_on_brand_sorted)
	_refresh()
	get_tree().process_frame.connect(_play_entrance, CONNECT_ONE_SHOT)


# The pills and round buttons of the top bar: dark glass over the felt, pictures drawn in code.
func _build_top_bar() -> void:
	for pill: PanelContainer in [_avatar_pill, _coin_pill]:
		pill.add_theme_stylebox_override("panel", Ui.box(Color(0, 0, 0, 0.36), 34, 16, 6))
	_coins_label = CoinLabel.new()
	_coins_label.name = "CoinsLabel"
	_coins_label.font_size = 26
	_coins_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_coin_pill.add_child(_coins_label)
	_avatar.draw.connect(_draw_avatar)
	_round_button(_help_button, _draw_question)
	_round_button(_account_button, _draw_gear)


# The setup box the way a card-game lobby does it: round marks to pick the players and the
# pool, the entry on a pill with a slider under it. The hidden OptionButtons keep the choice;
# these widgets only show it and change it.
func _build_setup_widgets() -> void:
	var players_group := ButtonGroup.new()
	for index in PLAYER_CHOICES.size():
		var chip := ChoiceChip.new("%d Players" % PLAYER_CHOICES[index], players_group)
		chip.toggled.connect(func(on: bool) -> void:
			if on:
				_players_option.select(index))
		_players_chips.add_child(chip)
		_player_chips.append(chip)

	var pool_group := ButtonGroup.new()
	for index in POOL_CHOICES.size():
		var chip := ChoiceChip.new(POOL_CHOICES[index][0], pool_group)
		chip.toggled.connect(func(on: bool) -> void:
			if on:
				_type_option.select(POOL_CHOICES[index][1])
				_setup_title.text = GAME_TITLES[POOL_CHOICES[index][1]])
		_pool_chips_row.add_child(chip)
		_pool_chips.append(chip)

	# The entry: a brown pill with the coins on it
	_stake_pill.add_theme_stylebox_override("panel", Ui.box(SETUP_BROWN, 30, 30, 8))
	_stake_coins = CoinLabel.new()
	_stake_coins.name = "StakeCoins"
	_stake_coins.font_size = 32
	_stake_coins.text_color = Color.WHITE
	_stake_coins.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_stake_pill.get_child(0).add_child(_stake_coins)
	_free_label.add_theme_font_override("font", Ui.bold_font)

	# and the slider: a brown groove, a white knob with a teal rim
	var groove := Ui.box(Color("b8a28f"), 8, 0, 0)
	groove.content_margin_top = 7
	groove.content_margin_bottom = 7
	_stake_slider.add_theme_stylebox_override("slider", groove)
	var filled := Ui.box(Color("8d6e63"), 8, 0, 0)
	filled.content_margin_top = 7
	filled.content_margin_bottom = 7
	_stake_slider.add_theme_stylebox_override("grabber_area", filled)
	_stake_slider.add_theme_stylebox_override("grabber_area_highlight", filled)
	var knob := _knob_texture()
	for icon_name: String in ["grabber", "grabber_highlight", "grabber_disabled"]:
		_stake_slider.add_theme_icon_override(icon_name, knob)
	_stake_slider.add_theme_color_override("tick_color", Color(0, 0, 0, 0))  # the ticks only snap, unseen
	_stake_slider.max_value = GameClient.STAKES.size() - 1
	_stake_slider.tick_count = GameClient.STAKES.size()
	_stake_slider.value_changed.connect(_on_stake_slid)


# A round white knob with a teal rim, as a picture for the slider to carry.
func _knob_texture() -> Texture2D:
	var gradient := Gradient.new()
	gradient.offsets = PackedFloat32Array([0.0, 0.66, 0.72, 0.9, 0.96, 1.0])
	gradient.colors = PackedColorArray([
		Color.WHITE, Color.WHITE, Color("26a69a"), Color("26a69a"), Color(0.15, 0.65, 0.6, 0.0), Color(0, 0, 0, 0),
	])
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.width = 52
	texture.height = 52
	texture.fill = GradientTexture2D.FILL_RADIAL
	texture.fill_from = Vector2(0.5, 0.5)
	texture.fill_to = Vector2(1.0, 0.5)
	return texture


func _round_button(button: Button, picture: Callable) -> void:
	button.custom_minimum_size = Vector2(ROUND_BUTTON, ROUND_BUTTON)
	button.focus_mode = Control.FOCUS_NONE
	for state_name: String in ["normal", "hover", "pressed"]:
		var round_box := StyleBoxFlat.new()
		round_box.bg_color = Color(0, 0, 0, 0.5 if state_name == "hover" else 0.36)
		round_box.set_corner_radius_all(int(ROUND_BUTTON / 2.0))
		round_box.anti_aliasing = true
		button.add_theme_stylebox_override(state_name, round_box)
	button.draw.connect(picture)


func _process(delta: float) -> void:
	# The logo drifts gently up and down
	_float_time += delta
	_logo.position.y = _logo_rest_y + sin(_float_time * 1.6) * 6.0
	# and catches the light now and then
	_until_twinkle -= delta
	# (not through the friends list while it lies over the logo)
	var covered := get_tree().get_first_node_in_group(FriendsPanel.BACK_GROUP) != null
	if _until_twinkle <= 0.0 and _logo.is_visible_in_tree() and not covered:
		_until_twinkle = randf_range(1.2, 2.8)
		var spot := Vector2(randf_range(0.15, 0.85), randf_range(0.3, 0.7)) * _logo.size
		Fx.sparkle(_logo.global_position + spot, Fx.GOLD, 5)

	if DisplayServer.has_feature(DisplayServer.FEATURE_VIRTUAL_KEYBOARD):
		make_room_for_keyboard(DisplayServer.virtual_keyboard_get_height())

	if _frames_until_scroll > 0:
		_frames_until_scroll -= 1
		if _frames_until_scroll == 0:
			_show_focused_field()


## Shrinks the screen to the part the on-screen keyboard leaves visible and keeps the field
## being typed in on screen. `height` is in window pixels, as the system reports it.
func make_room_for_keyboard(height: int) -> void:
	if height == _keyboard_height:
		return
	_keyboard_height = height
	var units := get_viewport().get_visible_rect().size.y / float(maxi(1, DisplayServer.window_get_size().y))
	offset_bottom = -height * units
	_tagline.visible = height == 0
	# With little height left, the logo and the bottom bar give their place to the form
	_logo.visible = height == 0
	_bottom_bar.visible = height == 0
	_login_row.add_theme_constant_override("margin_bottom", 90 if height == 0 else 16)
	_frames_until_scroll = 3


func _show_focused_field() -> void:
	var focused := get_viewport().gui_get_focus_owner()
	if focused != null and _side.is_ancestor_of(focused):
		_side.ensure_control_visible(focused)


# The logo is as large as its column allows, with the tagline right under it.
func _fit_logo() -> void:
	var texture_size := _logo.texture.get_size()
	var room := _brand.size - Vector2(0.0, _tagline.size.y + 30.0)
	var height := minf(room.x * texture_size.y / texture_size.x, room.y)
	_logo.custom_minimum_size.y = maxf(110.0, height)


func _on_brand_sorted() -> void:
	_logo_rest_y = _logo.position.y


func _play_entrance() -> void:
	if Game.is_logged_in():
		# The tiles deal themselves out one after another
		for index in 4:
			Ui.pop_in([_points_tile, _pool_tile, _close_joker_tile, _friends_tile][index], 0.06 * index)
	else:
		Ui.pop_in(_logo)
		Ui.pop_in(_auth_panel, 0.08)


func _refresh() -> void:
	var logged_in := Game.is_logged_in()
	_login_row.visible = not logged_in
	_auth_panel.visible = not logged_in
	_menu_panel.visible = logged_in
	if not logged_in:
		# Whatever lay over the menu goes with it: a setup box, the friends list, the profile
		for panel: Node in get_tree().get_nodes_in_group(FriendsPanel.BACK_GROUP):
			panel.call("close")

	_auth_title.text = "Register" if _registering else "Login"
	_username_edit.visible = _registering
	_email_edit.visible = _registering
	_phone_edit.visible = _registering
	_identifier_edit.visible = not _registering
	_submit_button.text = "Sign up" if _registering else "Login"
	_submit_button.disabled = Game.busy
	_switch_button.text = "Already have an account? Login" if _registering else "Don't have an account? Register"

	_welcome_label.text = str(Game.user.get("username", ""))
	_avatar.queue_redraw()
	if Game.is_online():
		_status_label.text = "Online"
		_status_label.add_theme_color_override("font_color", Ui.PALE_GREEN)
	else:
		_status_label.text = "Connecting..."
		_status_label.add_theme_color_override("font_color", Ui.AMBER)
	_create_button.disabled = Game.busy or not Game.is_online()
	_join_button.disabled = Game.busy or not Game.is_online()

	# The button tells what is waiting behind it: friends who can play, requests to answer
	var news: Array = ["Friends"]
	if Game.friends_online() > 0:
		news.append("%d online" % Game.friends_online())
	var requests := Game.friend_requests.size()
	if requests > 0:
		news.append("1 request" if requests == 1 else "%d requests" % requests)
	_friends_button.text = "  ·  ".join(news)

	# The bottom bar: a dark strip of buttons under the menu; only the links under the login form
	for button: Control in [_friends_button, _profile_button, _logout_button]:
		button.visible = logged_in
	_sound_switches.visible = not logged_in  # the menu has its own switches in the top bar
	_bottom_bar.add_theme_stylebox_override("panel", Ui.box(Color(0, 0, 0, 0.38), 0, 24, 10) if logged_in else StyleBoxEmpty.new())


# The balance, and the tables it reaches: one that costs more than the player has cannot be picked.
func _refresh_coins() -> void:
	_coins_label.amount = Game.coins
	for index in GameClient.STAKES.size():
		_stake_option.set_item_disabled(index, GameClient.STAKES[index] > Game.coins)
	# Until the player chooses, the cheapest table played for coins is offered
	if not _stake_picked or GameClient.STAKES[_stake_option.selected] > Game.coins:
		_stake_option.select(1 if Game.coins >= GameClient.STAKES[1] else 0)
	_show_stake()


# The slider reaches only the tables the player can afford; the pill shows the one chosen.
func _show_stake() -> void:
	var reach := 0
	for index in GameClient.STAKES.size():
		if GameClient.STAKES[index] <= Game.coins:
			reach = index
	_stake_slider.max_value = maxi(reach, 0)
	_stake_slider.set_value_no_signal(_stake_option.selected)
	var stake: int = GameClient.STAKES[_stake_option.selected]
	_stake_coins.visible = stake > 0
	_stake_coins.amount = stake
	_free_label.visible = stake == 0


func _on_stake_slid(value: float) -> void:
	_stake_picked = true
	_stake_option.select(int(value))
	_show_stake()
	Sound.play("select")


func _on_auth_changed() -> void:
	_refresh()
	# The form gives way to the menu (or back) with a little bounce
	_play_entrance.call_deferred()


func _on_switch_mode() -> void:
	_registering = not _registering
	_refresh()


func _on_submit() -> void:
	if Game.busy:
		return
	if not Config.store_build:
		Game.set_server_url(_server_edit.text)
		_server_edit.text = Game.server_url
	var password := _password_edit.text

	if _registering:
		var username := _username_edit.text.strip_edges()
		var email := _email_edit.text.strip_edges()
		var phone := _phone_edit.text.strip_edges()
		var problem := _sign_up_problem(username, email, phone, password)
		if problem.is_empty():
			Game.register(username, email, phone, password)
		else:
			Ui.alert(problem, "Register")
	else:
		var identifier := _identifier_edit.text.strip_edges()
		if identifier.is_empty() or password.is_empty():
			Ui.alert("Enter your email, phone or username, and your password.", "Login")
		else:
			Game.login(identifier, password)


# What is missing or wrong in the sign-up form, going down its fields; "" when it can be sent.
# An account needs all four: the email address and the mobile number are not optional.
func _sign_up_problem(username: String, email: String, phone: String, password: String) -> String:
	if username.is_empty():
		return "Enter a username."
	var problem := AccountRules.email_problem(email)
	if problem.is_empty():
		problem = AccountRules.phone_problem(phone)
	if problem.is_empty() and password.is_empty():
		problem = "Enter a password."
	return problem


func _on_auth_failed(message: String) -> void:
	if _registering:
		Ui.alert(message, "Registration failed")
	else:
		Ui.alert(WRONG_LOGIN_MESSAGE if message == "Invalid credentials" else message, "Login failed")


# A game tile was tapped: the setup box opens with that game chosen
func _open_setup(type_index: int) -> void:
	_type_option.select(type_index)
	_setup_title.text = GAME_TITLES[type_index]
	# The marks show what the hidden options hold; the pool choice only for the pool games
	_player_chips[_players_option.selected].button_pressed = true
	var pool := type_index > 0
	_pool_column.visible = pool
	_pool_divider.visible = pool
	if pool:
		for index in POOL_CHOICES.size():
			if POOL_CHOICES[index][1] == type_index:
				_pool_chips[index].button_pressed = true
	_show_stake()
	_join_overlay.close()  # one box at a time
	_setup_overlay.open()


# "Create table" in the private-table box: the setup box takes over, with a points game offered
func _on_create_table() -> void:
	_open_setup(0)


func _on_create() -> void:
	var game_type: String = GAME_TYPES[_type_option.selected][1]
	var max_players: int = PLAYER_CHOICES[_players_option.selected]
	Game.create_game(game_type, max_players, GameClient.STAKES[_stake_option.selected])


func _on_join() -> void:
	var code := _code_edit.text.strip_edges()
	if code.is_empty():
		Ui.alert("Enter the room code your friend gave you.", "Join table")
		_code_edit.grab_focus()
	else:
		Game.join_by_code(code)


func _open_friends() -> void:
	_join_overlay.close()  # one box at a time
	FriendsPanel.open(self)


func _open_profile() -> void:
	ProfilePanel.open(self)


# A tap on the name or the coins opens the profile, where both are explained
func _on_pill_input(event: InputEvent) -> void:
	var click := event as InputEventMouseButton
	if click != null and click.pressed and click.button_index == MOUSE_BUTTON_LEFT:
		_open_profile()


# The privacy policy and the terms are web pages served by the game server.
func _open_page(path: String) -> void:
	OS.shell_open(Game.server_url + path)


# ---------- pictures drawn in code ----------

# The player's avatar: a coloured disc with the first letter of the name, as at the table.
func _draw_avatar() -> void:
	var center := _avatar.size / 2.0
	var radius := minf(center.x, center.y) - AVATAR_RING
	var username := str(Game.user.get("username", ""))
	var color: Color = PlayerBadge.AVATAR_COLORS[absi(hash(username)) % PlayerBadge.AVATAR_COLORS.size()]
	_avatar.draw_circle(center, radius + AVATAR_RING, Ui.GOLD, true, -1.0, true)
	_avatar.draw_circle(center, radius, color, true, -1.0, true)
	var font := Ui.bold_font
	var font_size := int(radius * 1.1)
	var baseline := center.y + (font.get_ascent(font_size) - font.get_descent(font_size)) / 2.0
	_avatar.draw_string(font, Vector2(0, baseline), username.substr(0, 1).to_upper(), HORIZONTAL_ALIGNMENT_CENTER, _avatar.size.x, font_size, Color.WHITE)


func _draw_question() -> void:
	var font := Ui.bold_font
	var font_size := 32
	var baseline := _help_button.size.y / 2.0 + (font.get_ascent(font_size) - font.get_descent(font_size)) / 2.0
	_help_button.draw_string(font, Vector2(0, baseline), "?", HORIZONTAL_ALIGNMENT_CENTER, _help_button.size.x, font_size, Color.WHITE)


# A cog: a thick ring with eight teeth.
func _draw_gear() -> void:
	var center := _account_button.size / 2.0
	_account_button.draw_arc(center, 11.0, 0.0, TAU, 32, Color.WHITE, 6.0, true)
	for tooth in 8:
		var direction := Vector2.RIGHT.rotated(tooth * TAU / 8.0)
		_account_button.draw_line(center + direction * 13.0, center + direction * 18.0, Color.WHITE, 5.0, true)
