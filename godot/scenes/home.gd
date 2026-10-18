extends Control
## Logged out: login or register, with the logo beside the form (the form scrolls, so it stays
## usable when the on-screen keyboard covers the lower half of a phone).
##
## Logged in: the menu, laid out like a card-game lobby. The player and the coins sit in a bar
## at the top with a few round buttons, big tiles in the middle open the kinds of game, and
## a bar of small buttons runs along the bottom. Beside the coins, the Daily Bonus pill opens
## the wheel that can be spun once every 24 hours, and counts down to the next spin. A game tile opens a box to set up the table;
## the friends tile opens the room-code form.
##
## Points Rummy is not on the menu (since 2026-10-14 the big tile is Close Joker). It stays in
## GAME_TYPES because the server still plays it and the table still shows it.

const GAME_TYPES := [
	["Points", "points"], ["Pool 101", "pool"], ["Close Joker 240", "close_joker"],
	["2-Deal", "deals_2"], ["3-Deal", "deals_3"], ["Pool 201", "pool_201"],
]
const GAME_TITLES := ["Points Rummy", "Pool Rummy", "Close Joker Rummy", "Deals Rummy", "Deals Rummy", "Pool Rummy"]
const PLAYER_CHOICES := [2, 3, 4, 5, 6]
# "Play Now" offers the two tables most players look for, so a search finds company quickly;
# a private table can have any number of seats. Deals Rummy is played two-handed.
const MATCH_PLAYERS := [2, 6]
# The value of a point offered first at a Points table
const FIRST_POINT_VALUE := 10
# The tabs of the setup box: each holds one or more GAME_TYPES entries (by index). A tab with
# more than one shows a row of marks to pick between them, under the heading given here, with
# the names in VARIANT_NAMES.
const MODES := [
	["Close Joker", [2], ""],
	["Pool Rummy", [1, 5], "SELECT POOL"],
	["Deals Rummy", [3, 4], "SELECT DEALS"],
]
# Close Joker's has no mark of its own (it is alone in its tab); it names the search
const VARIANT_NAMES := {1: "101 Points", 5: "201 Points", 2: "240 Points", 3: "2 Deals", 4: "3 Deals"}
const SETUP_BROWN := Color("8d6e63")
const TAB_CREAM := Color("f7eed9")
const TAB_GOLD := Color("f6c232")
const TAB_EDGE := Color("b8a28f")
const TEAL_BUTTON := Color("2bb3a3")
const GREEN_BUTTON := Color("43b649")
const YELLOW_BUTTON := Color("f2c21b")
# The server answers "Invalid credentials" both for an unknown account and for a wrong password
const WRONG_LOGIN_MESSAGE := "That mobile number or username and password do not match an account.\n\nNew here? Use \"Don't have an account? Register\". Forgotten your password? Use \"Forgot password?\"."
const ROUND_BUTTON := 52.0
const BONUS_PILL := Vector2(226, 60)
const AVATAR_RING := 3.0
const RULES := """Every player gets 13 cards. On your turn, draw a card from the deck or the open pile, then discard one.

Arrange your cards into sequences (3 or more cards of one suit in a row, like 5-6-7 of hearts) and sets (3 or 4 cards of one rank in different suits). To declare, all your cards must be in sequences and sets, with at least two sequences, one of them pure: no joker standing in for a card.

A card is cut as the joker every round. Every card of that rank is wild, together with the printed jokers.

Points: J, Q, K and A count 10, number cards their value, jokers 0. The winner scores 0; a losing hand counts its loose cards, up to 80. Dropping out costs 20 before your first turn and 40 after. A wrong declaration costs 80.

Close Joker goes round after round like Pool Rummy: reach 240 and you are out; the last player left wins. The joker is cut face down. You see it, and which cards are wild, only once your own cards hold a pure sequence; a green dot on a player's picture shows who has seen it. Pool Rummy is the same without the hidden joker: reach 101 (or 201) and you are out. Deals Rummy is 2 or 3 deals played for chips: the winner of a deal takes each loser's points in chips, and the most chips after the last deal win.

Play Now finds players for you, the ones in your region first: no room code needed. To play with your friends, open a private table under Play with Friends and give them its room code.

When someone declares, everyone else gets 15 seconds to arrange their cards before they are counted. Every turn has 30 seconds.

Coins are play tokens with no cash value. Every player pays the table's entry on sitting down, and the winner of the game takes everything paid in."""

## What the login form shows: logging in, signing up, the number for a forgotten password, or
## the box for the code the server sent by SMS.
enum AuthStep { LOGIN, REGISTER, FORGOT, CODE }

var _step := AuthStep.LOGIN
var _code_purpose := ""  # in the CODE step: "register" or "password"
var _code_phone := ""  # the whole number the code went to, as it was sent to the server
var _code_shown := ""  # the same number as the server writes it, "+91 98765 43210"
var _resend_at := 0  # Time.get_ticks_msec() from when another code may be asked for
var _keyboard_height := 0
var _frames_until_scroll := 0  # the layout needs a few frames to settle before scrolling to a field
var _float_time := 0.0
var _logo_rest_y := 0.0  # where the layout puts the logo; it floats around this
var _until_twinkle := 1.5  # seconds until the next glint on the logo
var _stake_picked := false  # false until the player has chosen an entry themselves
var _point_index := GameClient.POINT_VALUES.find(FIRST_POINT_VALUE)  # the value of a point chosen
var _point_picked := false  # the same for the value of a point
var _search: MatchSearch  # the box shown while "Play Now" looks for players
var _settings: SettingsBox  # behind the cog: sound, the privacy policy and terms, logging out
var _bonus_box: DailyBonusBox  # the daily bonus wheel
var _bonus_button: Button  # the pill beside the coins that opens it
var _bonus_ready_shown := false  # whether the pill is dressed as "a spin is waiting"
var _coins_label: CoinLabel
var _stake_coins: CoinLabel  # the amount in the pill above the slider
var _player_chips: Array[ChoiceChip] = []  # one per PLAYER_CHOICES entry
var _mode_tabs: Array[Button] = []  # one per MODES entry
var _variant_chips: Dictionary = {}  # GAME_TYPES index -> ChoiceChip, for the tabs that hold several
# The setup box was opened from the Private Table box: the table is for the player's own
# friends, joinable with its code only
var _private_table := false

@onready var _login_row: Control = %Margin
@onready var _brand: VBoxContainer = %Brand
@onready var _logo: TextureRect = %Logo
@onready var _tagline: Label = %Tagline
@onready var _side: ScrollContainer = %Side
@onready var _auth_panel: Control = %AuthPanel
@onready var _auth_title: Label = %AuthTitle
@onready var _auth_info: Label = %AuthInfoLabel
@onready var _username_edit: LineEdit = %UsernameEdit
@onready var _phone_row: Control = %PhoneRow
@onready var _country_edit: LineEdit = %CountryCodeEdit
@onready var _phone_edit: LineEdit = %PhoneEdit
@onready var _identifier_edit: LineEdit = %IdentifierEdit
@onready var _otp_edit: LineEdit = %OtpEdit
@onready var _password_edit: LineEdit = %PasswordEdit
@onready var _submit_button: Button = %SubmitButton
@onready var _resend_button: Button = %ResendButton
@onready var _forgot_button: Button = %ForgotButton
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
@onready var _close_joker_tile: GameTile = %CloseJokerTile
@onready var _pool_tile: GameTile = %PoolTile
@onready var _deals_tile: GameTile = %DealsTile
@onready var _friends_tile: GameTile = %FriendsTile

@onready var _setup_overlay: MenuOverlay = %SetupOverlay
@onready var _setup_title: Label = %SetupTitle
@onready var _setup_close_button: Button = %SetupCloseButton
@onready var _type_option: OptionButton = %TypeOption
@onready var _players_option: OptionButton = %PlayersOption
@onready var _stake_option: OptionButton = %StakeOption
@onready var _players_chips: HBoxContainer = %PlayersChips
@onready var _players_column: Control = %PlayersColumn
@onready var _mode_tabs_row: HBoxContainer = %ModeTabs
@onready var _variant_column: Control = %VariantColumn
@onready var _variant_label: Label = %VariantLabel
@onready var _variant_chips_row: HBoxContainer = %VariantChips
@onready var _stake_pill: PanelContainer = %StakePill
@onready var _stake_label: Label = %StakeLabel
@onready var _stake_hint: Label = %StakeHint
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
@onready var _privacy_button: Button = %PrivacyButton
@onready var _terms_button: Button = %TermsButton
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
	_otp_edit.text_submitted.connect(_on_submit.unbind(1))
	_otp_edit.text_changed.connect(_on_code_typed)
	_username_edit.text_submitted.connect(func(_text: String) -> void: _phone_edit.grab_focus())
	_phone_edit.text_submitted.connect(_on_phone_submitted.unbind(1))
	_switch_button.pressed.connect(_on_switch_mode)
	_forgot_button.pressed.connect(_on_forgot)
	_resend_button.pressed.connect(_on_resend)
	_auth_info.add_theme_font_override("font", Ui.bold_font)
	_close_joker_tile.pressed.connect(_open_setup.bind(2))
	_pool_tile.pressed.connect(_open_setup.bind(1))
	_deals_tile.pressed.connect(_open_setup.bind(3))
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
	_account_button.pressed.connect(_open_settings)
	_avatar_pill.gui_input.connect(_on_pill_input.bind(_avatar_pill))
	_friends_button.pressed.connect(_open_friends)
	_privacy_button.pressed.connect(_open_page.bind("/privacy"))
	_terms_button.pressed.connect(_open_page.bind("/terms"))

	Game.auth_changed.connect(_on_auth_changed)
	Game.auth_failed.connect(_on_auth_failed)
	Game.code_sent.connect(_on_code_sent)
	Game.connection_changed.connect(_refresh)
	Game.busy_changed.connect(_refresh)
	Game.friends_changed.connect(_refresh)
	Game.coins_changed.connect(_refresh_coins)
	_search = MatchSearch.new()
	add_child(_search)
	_search.closed.connect(Game.cancel_match)  # closing the box ends the search
	_settings = SettingsBox.new()
	add_child(_settings)
	_settings.get_node("Box/SettingsColumn/AvatarSlot").add_child(AvatarEditor.new())
	_bonus_box = DailyBonusBox.new()
	add_child(_bonus_box)
	_bonus_box.wheel.stopped.connect(_refresh_coins)  # the coins won show once the wheel is at rest
	_bonus_button.pressed.connect(_open_bonus)
	Game.bonus_changed.connect(_dress_bonus_button)
	_dress_bonus_button()
	# The top bar shows the player's photo once it is here, and a new one as soon as it is saved
	Game.avatar_loaded.connect(func(user_id: String) -> void:
		if user_id == Game.player_id:
			_avatar.queue_redraw())
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

	# The daily bonus, right of the coins: a little wheel, and "FREE SPIN!" or the time to wait
	_bonus_button = Button.new()
	_bonus_button.name = "BonusButton"
	_bonus_button.custom_minimum_size = BONUS_PILL
	_bonus_button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_bonus_button.focus_mode = Control.FOCUS_NONE
	_bonus_button.tooltip_text = "Daily bonus"
	_bonus_button.draw.connect(_draw_bonus_pill)
	_coin_pill.get_parent().add_child(_bonus_button)
	_coin_pill.get_parent().move_child(_bonus_button, _coin_pill.get_index() + 1)


# The setup box the way a card-game lobby does it: round marks to pick the players and the
# pool, the entry on a pill with a slider under it. The hidden OptionButtons keep the choice;
# these widgets only show it and change it.
func _build_setup_widgets() -> void:
	# The kinds of game as a row of tabs; the chosen one is gold
	var mode_group := ButtonGroup.new()
	for index in MODES.size():
		var tab := Button.new()
		tab.text = str(MODES[index][0]).to_upper()
		tab.toggle_mode = true
		tab.button_group = mode_group
		tab.focus_mode = Control.FOCUS_NONE
		tab.custom_minimum_size = Vector2(0, 54)
		tab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tab.add_theme_font_override("font", Ui.bold_font)
		tab.add_theme_font_size_override("font_size", 20)
		for color_name: String in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color", "font_focus_color"]:
			tab.add_theme_color_override(color_name, ChoiceChip.TEXT)
		for state_name: String in ["normal", "hover"]:
			tab.add_theme_stylebox_override(state_name, _tab_box(TAB_CREAM if state_name == "normal" else TAB_CREAM.darkened(0.04)))
		for state_name: String in ["pressed", "hover_pressed"]:
			tab.add_theme_stylebox_override(state_name, _tab_box(TAB_GOLD))
		tab.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
		tab.toggled.connect(func(on: bool) -> void:
			if on:
				_show_mode(index))
		_mode_tabs_row.add_child(tab)
		_mode_tabs.append(tab)
	_mode_tabs_row.custom_minimum_size.x = 700.0

	# The marks for the games inside a tab (101 or 201 for the pool games); one group for all,
	# since only one tab's marks are on show at a time
	var variant_group := ButtonGroup.new()
	for mode: Array in MODES:
		for type_index: int in mode[1]:
			if mode[1].size() < 2:
				continue
			var chip := ChoiceChip.new(VARIANT_NAMES.get(type_index, GAME_TITLES[type_index]), variant_group)
			chip.toggled.connect(func(on: bool) -> void:
				if on:
					_pick_game(type_index))
			_variant_chips_row.add_child(chip)
			_variant_chips[type_index] = chip

	var players_group := ButtonGroup.new()
	for index in PLAYER_CHOICES.size():
		var chip := ChoiceChip.new("%dP" % PLAYER_CHOICES[index], players_group)
		chip.toggled.connect(func(on: bool) -> void:
			if on:
				_players_option.select(index))
		_players_chips.add_child(chip)
		_player_chips.append(chip)

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


# The tab that holds this game (an index into GAME_TYPES).
func _mode_of(type_index: int) -> int:
	for index in MODES.size():
		if type_index in MODES[index][1]:
			return index
	return 0


# A tab was chosen: its marks come on show, and its first game is picked unless the game
# already picked belongs to it.
func _show_mode(mode_index: int) -> void:
	var games: Array = MODES[mode_index][1]
	var several := games.size() > 1
	_variant_column.visible = several
	_variant_label.text = MODES[mode_index][2]
	for type_index: int in _variant_chips:
		_variant_chips[type_index].visible = type_index in games
	_pick_game(_type_option.selected if _type_option.selected in games else games[0])


# Pressing a tab or mark here releases the others of its group; the `toggled` that follows
# comes back to this game, finds everything already pressed, and goes no further.
func _pick_game(type_index: int) -> void:
	_type_option.select(type_index)
	_setup_title.text = GAME_TITLES[type_index]
	if _variant_chips.has(type_index):
		_variant_chips[type_index].button_pressed = true
	_mode_tabs[_mode_of(type_index)].button_pressed = true
	# The seats and the coins offered depend on the game
	_refresh_players()
	_show_stake()


func _game_type() -> String:
	return GAME_TYPES[_type_option.selected][1]


# A Points table is played for coins a point; every other table for an entry.
func _per_point() -> bool:
	return _game_type() == "points"


# Deals Rummy found by "Play Now" is two-handed, so its box asks nothing about seats.
func _seats_fixed() -> bool:
	return not _private_table and _game_type().begins_with("deals")


# The seat counts on offer: all of them for a private table, two or six for "Play Now".
func _refresh_players() -> void:
	var offered: Array = PLAYER_CHOICES if _private_table else MATCH_PLAYERS
	for index in PLAYER_CHOICES.size():
		_player_chips[index].visible = PLAYER_CHOICES[index] in offered
	_players_column.visible = not _seats_fixed()
	if not PLAYER_CHOICES[_players_option.selected] in offered:
		_player_chips[0].button_pressed = true  # two players
	elif not _player_chips[_players_option.selected].button_pressed:
		_player_chips[_players_option.selected].button_pressed = true


func _chosen_players() -> int:
	return 2 if _seats_fixed() else PLAYER_CHOICES[_players_option.selected]


# One tab of the game-mode row: a flat box with a brown edge, square so the tabs join up.
func _tab_box(fill: Color) -> StyleBoxFlat:
	var box := Ui.box(fill, 4, 16, 8)
	box.border_color = TAB_EDGE
	box.set_border_width_all(2)
	return box


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

	# The pill's little wheel turns while a spin waits; otherwise its countdown runs
	if _bonus_button.is_visible_in_tree():
		if Game.bonus_available() != _bonus_ready_shown:
			_dress_bonus_button()
		_bonus_button.queue_redraw()

	# The SMS code: another one may be asked for once its countdown has run out
	if _resend_button.is_visible_in_tree():
		var wait := Game.seconds_until(_resend_at)
		_resend_button.disabled = wait > 0 or Game.busy
		_resend_button.text = "Send the code again in %ds" % wait if wait > 0 else "Send the code again"

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
			Ui.pop_in([_close_joker_tile, _pool_tile, _deals_tile, _friends_tile][index], 0.06 * index)
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

	_refresh_form()

	_welcome_label.text = str(Game.user.get("username", ""))
	_avatar.queue_redraw()
	if Game.is_online():
		_status_label.text = "Online"
		_status_label.add_theme_color_override("font_color", Ui.PALE_GREEN)
	else:
		_status_label.text = "Reconnecting..."  # the menu shows only once connected (LoadingScreen)
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

	# The bottom bar: a dark strip with Friends under the menu (the profile opens from the
	# player's picture at the top). Under the login form it holds the privacy policy, the terms
	# and the sound switches instead; logged in, those are in Settings, behind the cog.
	_friends_button.visible = logged_in
	for link: Control in [_privacy_button, _terms_button, _sound_switches]:
		link.visible = not logged_in
	_bottom_bar.add_theme_stylebox_override("panel", Ui.box(Color(0, 0, 0, 0.38), 0, 24, 10) if logged_in else StyleBoxEmpty.new())


# The login form shows what its step needs. Signing up asks for a username, the mobile number
# (country code in its own box) and a password; then for the code the server sent by SMS.
# A forgotten password asks for the number, then for the code and a new password.
func _refresh_form() -> void:
	var code_step := _step == AuthStep.CODE
	var resetting := _step == AuthStep.FORGOT or (code_step and _code_purpose == "password")
	_auth_title.text = {
		AuthStep.LOGIN: "Login",
		AuthStep.REGISTER: "Register",
		AuthStep.FORGOT: "Forgot password",
		AuthStep.CODE: "Enter the code",
	}[_step]
	_auth_info.visible = _step == AuthStep.FORGOT or code_step
	if _step == AuthStep.FORGOT:
		_auth_info.text = "Enter the mobile number of your account. We will send you a code by SMS."
	elif resetting:
		_auth_info.text = "We sent a 6-digit code by SMS to %s. Enter it, and choose a new password." % _code_shown
	else:
		_auth_info.text = "We sent a 6-digit code by SMS to %s. Enter it to finish signing up." % _code_shown
	_username_edit.visible = _step == AuthStep.REGISTER
	_phone_row.visible = _step == AuthStep.REGISTER or _step == AuthStep.FORGOT
	_identifier_edit.visible = _step == AuthStep.LOGIN
	_otp_edit.visible = code_step
	# The password was given with the sign-up form; a reset asks for the new one with the code
	_password_edit.visible = _step == AuthStep.LOGIN or _step == AuthStep.REGISTER or (resetting and code_step)
	if resetting:
		_password_edit.placeholder_text = "New password (at least %d characters)" % AccountRules.MIN_PASSWORD_LENGTH
	elif _step == AuthStep.REGISTER:
		_password_edit.placeholder_text = "Password (at least %d characters)" % AccountRules.MIN_PASSWORD_LENGTH
	else:
		_password_edit.placeholder_text = "Password"
	_submit_button.text = {
		AuthStep.LOGIN: "Login",
		AuthStep.REGISTER: "Sign up",
		AuthStep.FORGOT: "Send code",
		AuthStep.CODE: "Set new password" if resetting else "Verify",
	}[_step]
	_submit_button.disabled = Game.busy
	_resend_button.visible = code_step
	_forgot_button.visible = _step == AuthStep.LOGIN
	_switch_button.text = {
		AuthStep.LOGIN: "Don't have an account? Register",
		AuthStep.REGISTER: "Already have an account? Login",
		AuthStep.FORGOT: "Back to login",
		AuthStep.CODE: "Change the number",
	}[_step]


# The balance, and the tables it reaches: one that costs more than the player has cannot be picked.
func _refresh_coins() -> void:
	# While the bonus wheel turns, the coins it pays stay hidden until it is at rest
	if _bonus_box != null and _bonus_box.is_turning():
		return
	_coins_label.amount = Game.coins
	for index in GameClient.STAKES.size():
		_stake_option.set_item_disabled(index, GameClient.STAKES[index] > Game.coins)
	# Until the player chooses, the cheapest table played for coins is offered
	if not _stake_picked or GameClient.STAKES[_stake_option.selected] > Game.coins:
		_stake_option.select(1 if Game.coins >= GameClient.STAKES[1] else 0)
	# and at a Points table the value of a point in the picture, or the dearest within reach
	if not _point_picked or _point_cost(_point_index) > Game.coins:
		_point_index = GameClient.POINT_VALUES.find(FIRST_POINT_VALUE)
		while _point_index > 0 and _point_cost(_point_index) > Game.coins:
			_point_index -= 1
	_show_stake()


# What sitting at a Points table holds back: the worst hand at that value of a point.
func _point_cost(index: int) -> int:
	return GameClient.POINT_VALUES[index] * GameClient.MAX_POINTS


# The coins on the slider: the value of a point at a Points table, the entry at any other.
# The slider reaches only the tables the player can afford; the pill shows the one chosen.
func _show_stake() -> void:
	var per_point := _per_point()
	var count := GameClient.POINT_VALUES.size() if per_point else GameClient.STAKES.size()
	var reach := 0
	for index in count:
		var cost: int = _point_cost(index) if per_point else GameClient.STAKES[index]
		if cost <= Game.coins:
			reach = index
	_stake_slider.max_value = maxi(reach, 0)
	_stake_slider.tick_count = count
	var chosen := _point_index if per_point else _stake_option.selected
	_stake_slider.set_value_no_signal(chosen)
	var amount: int = GameClient.POINT_VALUES[chosen] if per_point else GameClient.STAKES[chosen]
	_stake_coins.visible = amount > 0
	_stake_coins.amount = amount
	_stake_coins.suffix = "per point" if per_point else ""
	_free_label.visible = amount == 0
	_stake_label.text = "SELECT POINT VALUE" if per_point else "SELECT ENTRY AMOUNT"
	if amount == 0:
		_stake_hint.text = "A free table: played for fun, no coins change hands."
	elif per_point:
		_stake_hint.text = "Each loser pays the winner their points x %s coins. Up to %s coins (80 points) are held while you play." % [
			Ui.coins_text(amount), Ui.coins_text(_point_cost(chosen))
		]
	else:
		_stake_hint.text = "Every player pays the entry on sitting down; the winner takes it all."


func _on_stake_slid(value: float) -> void:
	if _per_point():
		_point_picked = true
		_point_index = int(value)
	else:
		_stake_picked = true
		_stake_option.select(int(value))
	_show_stake()
	Sound.play("select")


func _on_auth_changed() -> void:
	if Game.is_logged_in():
		# Logging out later starts from the login form, not from a code that was used
		_step = AuthStep.LOGIN
		_otp_edit.text = ""
	_refresh()
	# The form gives way to the menu (or back) with a little bounce
	_play_entrance.call_deferred()


# The flat button under the form: to sign up, back to login, or (in the code step) back to
# the number, to correct it.
func _on_switch_mode() -> void:
	match _step:
		AuthStep.LOGIN:
			_step = AuthStep.REGISTER
		AuthStep.CODE:
			_step = AuthStep.REGISTER if _code_purpose == "register" else AuthStep.FORGOT
			_phone_edit.grab_focus.call_deferred()
		_:
			_step = AuthStep.LOGIN
	_otp_edit.text = ""
	_refresh()


func _on_forgot() -> void:
	_step = AuthStep.FORGOT
	# A number typed to log in is most likely the account's number
	var typed := _identifier_edit.text.strip_edges()
	if not typed.is_empty() and AccountRules.phone_problem(_country_edit.text, typed).is_empty():
		_phone_edit.text = typed
	_refresh()
	_phone_edit.grab_focus.call_deferred()


func _on_phone_submitted() -> void:
	if _step == AuthStep.FORGOT:
		_on_submit()
	else:
		_password_edit.grab_focus()


func _on_submit() -> void:
	if Game.busy:
		return
	if not Config.store_build:
		Game.set_server_url(_server_edit.text)
		_server_edit.text = Game.server_url
	var password := _password_edit.text

	match _step:
		AuthStep.REGISTER:
			var username := _username_edit.text.strip_edges()
			var problem := _sign_up_problem(username, password)
			if not problem.is_empty():
				Ui.alert(problem, "Register")
				return
			_code_phone = _typed_phone()
			Game.start_registration(username, _code_phone, password)
		AuthStep.FORGOT:
			var problem := AccountRules.phone_problem(_country_edit.text, _phone_edit.text)
			if not problem.is_empty():
				Ui.alert(problem, "Forgot password")
				return
			_code_phone = _typed_phone()
			Game.start_password_reset(_code_phone)
		AuthStep.CODE:
			var resetting := _code_purpose == "password"
			var problem := AccountRules.code_problem(_otp_edit.text)
			if problem.is_empty() and resetting:
				problem = AccountRules.password_problem(password)
			if not problem.is_empty():
				Ui.alert(problem, "Forgot password" if resetting else "Register")
				return
			if resetting:
				Game.reset_password(_code_phone, _otp_edit.text, password)
			else:
				Game.register(_username_edit.text.strip_edges(), _code_phone, password, _otp_edit.text)
		_:
			var identifier := _identifier_edit.text.strip_edges()
			if identifier.is_empty() or password.is_empty():
				Ui.alert("Enter your mobile number or username, and your password.", "Login")
			else:
				Game.login(identifier, password)


# The number as the two boxes give it, with its country code: "+919876543210".
func _typed_phone() -> String:
	return AccountRules.full_number(_country_edit.text, _phone_edit.text)


# What is missing or wrong in the sign-up form, going down its fields; "" when it can be sent.
func _sign_up_problem(username: String, password: String) -> String:
	if username.is_empty():
		return "Enter a username."
	var problem := AccountRules.phone_problem(_country_edit.text, _phone_edit.text)
	if problem.is_empty():
		problem = AccountRules.password_problem(password)
	return problem


# The server has sent a code: the form asks for it.
func _on_code_sent(purpose: String, phone: String, resend_seconds: int) -> void:
	var again := _step == AuthStep.CODE
	_code_purpose = purpose
	_code_shown = phone
	_resend_at = Time.get_ticks_msec() + resend_seconds * 1000
	if not again:
		_otp_edit.text = ""
		if purpose == "password":
			_password_edit.text = ""  # the one that was forgotten
	_step = AuthStep.CODE
	_refresh()
	_otp_edit.grab_focus.call_deferred()
	if again:
		Ui.notify("info", "A new code is on its way to %s" % phone)


func _on_resend() -> void:
	if Game.busy or Game.seconds_until(_resend_at) > 0:
		return
	if _code_purpose == "register":
		Game.start_registration(_username_edit.text.strip_edges(), _code_phone, _password_edit.text)
	else:
		Game.start_password_reset(_code_phone)


# The code box takes digits only; when signing up, the sixth one sends the code by itself.
func _on_code_typed(text: String) -> void:
	var digits := RegEx.create_from_string("[^0-9]").sub(text, "", true)
	if digits != text:
		_otp_edit.text = digits
		_otp_edit.caret_column = digits.length()
	if digits.length() == AccountRules.CODE_LENGTH and _code_purpose == "register" and not Game.busy:
		_on_submit()


func _on_auth_failed(message: String) -> void:
	match _step:
		AuthStep.LOGIN:
			Ui.alert(WRONG_LOGIN_MESSAGE if message == "Invalid credentials" else message, "Login failed")
		AuthStep.REGISTER:
			Ui.alert(message, "Registration failed")
		AuthStep.FORGOT:
			Ui.alert(message, "Forgot password")
		AuthStep.CODE:
			_otp_edit.text = ""  # to type it again
			Ui.alert(message, "Code not accepted")


# The setup box opens with a game chosen: from a game tile, or from the Private Table box
# (`private`: the table is for the player's friends and can only be joined with its code).
func _open_setup(type_index: int, private: bool = false) -> void:
	_private_table = private
	# The tabs and marks show what the hidden options hold
	_type_option.select(type_index)
	_show_mode(_mode_of(type_index))
	_player_chips[_players_option.selected].button_pressed = true
	_create_button.text = "Create Table" if private else "Play Now"
	_show_stake()
	_join_overlay.close()  # one box at a time
	_setup_overlay.open()


# "Create table" in the Private Table box: the setup box takes over for a private table,
# on the first tab's game
func _on_create_table() -> void:
	_open_setup(MODES[0][1][0], true)


# "Create Table" opens a private table and its lobby, with a room code to give to friends.
# "Play Now" asks the server for players who want the same table, nearest region first, and
# shows the search until they are found: no room code, no waiting for a host.
func _on_create() -> void:
	var game_type := _game_type()
	var max_players := _chosen_players()
	var stake: int = GameClient.STAKES[_stake_option.selected]
	var point_value: int = GameClient.POINT_VALUES[_point_index] if _per_point() else -1
	if _private_table:
		Game.create_game(game_type, max_players, stake, true, point_value)
		return
	if Game.searching():
		return
	_setup_overlay.close()
	_search.open_for(_describe_table(max_players, stake, point_value))
	Game.find_match(game_type, max_players, stake, point_value)


# The table being searched for, in a line: "Pool Rummy · 201 Points · 6 players · 500 coins".
func _describe_table(max_players: int, stake: int, point_value: int) -> String:
	var parts: Array = [GAME_TITLES[_type_option.selected]]
	if VARIANT_NAMES.has(_type_option.selected):
		parts.append(VARIANT_NAMES[_type_option.selected])
	parts.append("%d players" % max_players)
	if point_value > 0:
		parts.append("%s coins a point" % Ui.coins_text(point_value))
	elif point_value < 0 and stake > 0:
		parts.append("entry %s coins" % Ui.coins_text(stake))
	else:
		parts.append("free table")
	return "  ·  ".join(parts)


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


func _open_settings() -> void:
	_join_overlay.close()  # one box at a time
	_settings.open()


func _open_bonus() -> void:
	_join_overlay.close()  # one box at a time
	_bonus_box.open()


# A gold edge on the pill while a spin is waiting, the dark glass of the other pills otherwise.
func _dress_bonus_button() -> void:
	_bonus_ready_shown = Game.bonus_available()
	for state_name: String in ["normal", "hover", "pressed"]:
		var pill := Ui.box(Color(0, 0, 0, 0.5 if state_name == "hover" else 0.36), 30, 14, 6)
		if _bonus_ready_shown:
			pill.border_color = Ui.GOLD
			pill.set_border_width_all(2)
		_bonus_button.add_theme_stylebox_override(state_name, pill)
	_bonus_button.queue_redraw()


func _open_profile() -> void:
	ProfilePanel.show_over(self)


# A tap on the player's picture or name opens the profile: the only way to it (the user's
# choice, 2026-10-14; the coins beside it open nothing). Like a button, it reacts when the finger lifts, not when it touches down: a panel opened on
# touch-down is not laid out yet when that same finger lifts, all its buttons still lie in the
# top-left corner under the finger, and the lift pressed one of them ("Delete account").
func _on_pill_input(event: InputEvent, pill: Control) -> void:
	var click := event as InputEventMouseButton
	if click == null or click.pressed or click.button_index != MOUSE_BUTTON_LEFT:
		return
	if Rect2(Vector2.ZERO, pill.size).has_point(click.position):  # the finger did not slide away
		_open_profile()


# The privacy policy and the terms are web pages served by the game server.
func _open_page(path: String) -> void:
	OS.shell_open(Game.server_url + path)


# ---------- pictures drawn in code ----------

# The player's avatar: their photo, or a coloured disc with the first letter of the name, as
# at the table.
func _draw_avatar() -> void:
	var center := _avatar.size / 2.0
	var radius := minf(center.x, center.y) - AVATAR_RING
	var username := str(Game.user.get("username", ""))
	var color: Color = PlayerBadge.AVATAR_COLORS[absi(hash(username)) % PlayerBadge.AVATAR_COLORS.size()]
	_avatar.draw_circle(center, radius + AVATAR_RING, Ui.GOLD, true, -1.0, true)
	var photo := Game.avatar_texture(Game.player_id, Game.my_avatar())
	if photo != null:
		PlayerBadge.draw_photo(_avatar, center, radius, photo)
		return
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


# The daily bonus pill: a little wheel with eight slots and a pointer, then two lines. While a
# spin waits the wheel turns, the words say so in gold and a red dot sits on the corner.
func _draw_bonus_pill() -> void:
	var button := _bonus_button
	var spin_waits := Game.bonus_available()
	var height := button.size.y
	var radius := 21.0
	var center := Vector2(14.0 + radius, height / 2.0 + 2.0)
	var turned := _float_time * 1.4 if spin_waits else 0.0
	button.draw_circle(center, radius + 2.5, BonusWheel.RIM_DARK, true, -1.0, true)
	button.draw_circle(center, radius, BonusWheel.RIM, true, -1.0, true)
	for slot in 8:
		var points := PackedVector2Array([center])
		for k in 5:
			points.append(center + Vector2.from_angle(turned + (slot + k / 4.0) * TAU / 8.0) * (radius - 3.0))
		button.draw_colored_polygon(points, BonusWheel.SLOT_A if slot % 2 == 0 else BonusWheel.SLOT_B)
	button.draw_circle(center, 6.0, BonusWheel.RIM, true, -1.0, true)
	var top := center - Vector2(0.0, radius)
	button.draw_colored_polygon(PackedVector2Array([top + Vector2(-6, -5), top + Vector2(6, -5), top + Vector2(0, 7)]), BonusWheel.RIM_LIGHT)

	var font := Ui.bold_font
	var left := center.x + radius + 12.0
	var width := button.size.x - left - 10.0
	button.draw_string(font, Vector2(left, height / 2.0 - 5.0), "DAILY BONUS", HORIZONTAL_ALIGNMENT_LEFT, width, 15, Color(1, 1, 1, 0.75))
	var line := "..."
	if spin_waits:
		line = "FREE SPIN!"
	elif not Game.bonus.is_empty():
		line = GameClient.countdown_text(Game.bonus_wait())
	button.draw_string(font, Vector2(left, height / 2.0 + 21.0), line, HORIZONTAL_ALIGNMENT_LEFT, width, 23, Ui.GOLD if spin_waits else Color.WHITE)
	if spin_waits:
		var beat := 0.5 + 0.5 * sin(_float_time * 5.0)
		button.draw_circle(Vector2(button.size.x - 9.0, 9.0), 7.0 + beat * 1.5, Ui.RED, true, -1.0, true)


# A cog: a thick ring with eight teeth.
func _draw_gear() -> void:
	var center := _account_button.size / 2.0
	_account_button.draw_arc(center, 11.0, 0.0, TAU, 32, Color.WHITE, 6.0, true)
	for tooth in 8:
		var direction := Vector2.RIGHT.rotated(tooth * TAU / 8.0)
		_account_button.draw_line(center + direction * 13.0, center + direction * 18.0, Color.WHITE, 5.0, true)
