class_name DonkeyHome
extends VBoxContainer
## The Donkey Master home: what the middle of the menu shows in place of the rummy tiles once
## the game switch in the top bar is on Donkey Master. The top bar and the bottom bar stay the
## same, coins included: both games play from the one wallet.
##
## Two big cards: Play Online (a box to pick the seats and the entry, then a search for players)
## and Play with Friends (a box to create a private room or join one with its code). The boxes
## lie over the whole home screen, so the home adds them to itself (add_boxes_to).

const ONLINE_COLOR := Color("2196f3")
const FRIENDS_COLOR := Color("b55be0")
const TITLE_GOLD := Color("ffd54f")
const SETUP_BROWN := Color("8d6e63")
const LABEL_BROWN := Color("5d4037")
const HINT_BROWN := Color("8d6e63")
const TEAL_BUTTON := Color("2bb3a3")
const GREEN_BUTTON := Color("43b649")
const YELLOW_BUTTON := Color("f2c21b")
const CARD_SIZE := Vector2(440, 404)
const PICTURES := {
	"donkey": preload("res://assets/donkey/donkey.png"),
	"globe": preload("res://assets/donkey/globe.png"),
	"handshake": preload("res://assets/donkey/handshake.png"),
	"trophy": preload("res://assets/donkey/trophy.png"),
	"crown": preload("res://assets/donkey/crown.png"),
	"party": preload("res://assets/donkey/party.png"),
	"escape": preload("res://assets/donkey/escape.png"),
}
const RULES := """One pack of 52 cards is dealt out completely among 2 to 8 players. Aces are high.

Whoever holds the ace of spades leads it to the first trick. Then each player in turn, clockwise, plays one card, and must follow the suit that was led whenever they can.

Cannot follow suit? Play any other card: that is a cut. The trick stops at once, and whoever played the highest card of the suit led picks up every card of the trick and leads the next one.

When everyone follows suit, the trick's cards go out of the game, and whoever played the highest card leads the next one.

Empty your hand and you are out and safe. The first player out is the Master. The last player left holding cards is the Donkey!

Every turn has 15 seconds; when time runs out, a card is played for you.

Coins are play tokens with no cash value, the same coins as in Namma Rummy. Every player pays the table's entry on sitting down. At the end the Donkey (and anyone who left while still holding cards) loses the entry, and all of it goes to the Master; everyone else gets their own entry back.

Play Online finds players for you, the ones in your region first. When not enough players are online, computer players fill the empty seats after a few seconds. To play with your friends, create a room under Play with Friends and give them its room code."""

## True while the menu shows Donkey Master rather than rummy. It outlives the home screen, so
## coming back from a game opens the menu of the game that was played.
static var chosen := false

var online_card: DonkeyCard
var friends_card: DonkeyCard

var _heading: Control
var _title_label: Label
var _setup: MenuOverlay
var _setup_title: Label
var _players_chips: HBoxContainer
var _player_chips: Dictionary = {}  # seats -> ChoiceChip
var _stake_coins: CoinLabel
var _free_label: Label
var _stake_slider: HSlider
var _stake_hint: Label
var _setup_button: Button
var _room_box: MenuOverlay
var _code_edit: LineEdit
var _create_button: Button
var _join_button: Button
var _search: DonkeySearch
var _private := false  # the setup box is for a private room, not for Play Online
var _players := 4
var _stake_index := 1
var _stake_picked := false  # false until the player has chosen an entry themselves


## A picture from res://assets/donkey by name: "donkey", "globe", "trophy", ...
static func picture(picture_name: String) -> Texture2D:
	return PICTURES.get(picture_name)


## The first row of a box MenuOverlay dresses: the title on a banner, a tag to close it.
static func box_header(title: String, title_name: String, close_name: String, on_close: Callable) -> HBoxContainer:
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 0)
	var left := Control.new()
	left.custom_minimum_size = Vector2(56, 0)
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(left)
	var label := Label.new()
	label.name = title_name
	label.text = title
	header.add_child(label)
	var right := Control.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(right)
	var close_button := Button.new()
	close_button.name = close_name
	close_button.pressed.connect(on_close)
	header.add_child(close_button)
	return header


func _init() -> void:
	name = "DonkeyHome"
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	alignment = BoxContainer.ALIGNMENT_CENTER
	add_theme_constant_override("separation", 14)

	# The heading: the donkey, the name of the game and what it is about
	var heading := HBoxContainer.new()
	heading.name = "DonkeyHeading"
	heading.alignment = BoxContainer.ALIGNMENT_CENTER
	heading.add_theme_constant_override("separation", 14)
	var donkey := TextureRect.new()
	donkey.name = "HeadingDonkey"
	donkey.texture = picture("donkey")
	donkey.custom_minimum_size = Vector2(72, 72)
	donkey.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	donkey.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	heading.add_child(donkey)
	var words := VBoxContainer.new()
	words.add_theme_constant_override("separation", -4)
	words.alignment = BoxContainer.ALIGNMENT_CENTER
	var title := Label.new()
	_title_label = title
	title.name = "DonkeyTitle"
	title.text = "DONKEY MASTER"
	title.add_theme_font_size_override("font_size", 40)
	title.add_theme_color_override("font_color", TITLE_GOLD)
	title.add_theme_color_override("font_outline_color", Color("4e2a0c"))
	title.add_theme_constant_override("outline_size", 10)
	title.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.4))
	title.add_theme_constant_override("shadow_offset_y", 4)
	words.add_child(title)
	var tagline := Label.new()
	tagline.name = "DonkeyTagline"
	tagline.text = "Get rid of every card. The last one holding cards is the Donkey!"
	tagline.add_theme_font_size_override("font_size", 19)
	tagline.add_theme_color_override("font_color", Ui.PALE_GREEN)
	words.add_child(tagline)
	heading.add_child(words)
	add_child(heading)
	_heading = heading

	var row := HBoxContainer.new()
	row.name = "DonkeyCards"
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 28)
	online_card = DonkeyCard.new()
	online_card.name = "DonkeyOnlineCard"
	online_card.title = "PLAY ONLINE"
	online_card.subtitle = "Join players online at a table for 2, 4, 6 or 8"
	online_card.color = ONLINE_COLOR
	online_card.picture = picture("globe")
	online_card.tags = PackedStringArray(["LIVE", "2-8 PLAYERS"])
	online_card.live = true
	online_card.action = "PLAY NOW"
	online_card.custom_minimum_size = CARD_SIZE
	online_card.pressed.connect(open_setup.bind(false))
	row.add_child(online_card)
	friends_card = DonkeyCard.new()
	friends_card.name = "DonkeyFriendsCard"
	friends_card.title = "PLAY WITH FRIENDS"
	friends_card.subtitle = "Create a private room, or join one with its code"
	friends_card.color = FRIENDS_COLOR
	friends_card.picture = picture("handshake")
	friends_card.tags = PackedStringArray(["PRIVATE ROOM", "2-8 PLAYERS"])
	friends_card.action = "CREATE / JOIN"
	friends_card.custom_minimum_size = CARD_SIZE
	friends_card.pressed.connect(open_room_box)
	row.add_child(friends_card)
	add_child(row)


func _ready() -> void:
	_title_label.add_theme_font_override("font", Ui.bold_font)
	Game.coins_changed.connect(_show_stake)
	Game.busy_changed.connect(_refresh_buttons)
	Game.connection_changed.connect(_refresh_buttons)


func _process(_delta: float) -> void:
	# The donkey in the heading kicks up its heels now and then
	var donkey: Control = _heading.get_child(0)
	if donkey.is_visible_in_tree():
		var time := Time.get_ticks_msec() / 1000.0
		var kick := maxf(0.0, sin(time * 2.2)) ** 6.0
		donkey.pivot_offset = donkey.size / 2.0
		donkey.rotation = -0.25 * kick + 0.04 * sin(time * 1.3)


## The boxes lie over the whole home screen, top bar and all: `home` holds them.
func add_boxes_to(home: Control) -> void:
	_build_setup()
	home.add_child(_setup)
	_build_room_box()
	home.add_child(_room_box)
	_search = DonkeySearch.new()
	home.add_child(_search)
	_search.closed.connect(Game.donkey.cancel_match)  # closing the box ends the search
	# A search begun elsewhere (Play Again after an online game) shows here too
	Game.donkey.search_changed.connect(_show_search)
	_show_search()
	_refresh_buttons()
	_show_stake()


func _show_search() -> void:
	if Game.donkey.searching() and not _search.visible:
		var search := Game.donkey.search
		_search.open_for(describe_table(int(search.get("maxPlayers", 2)), int(search.get("stake", 0))))


## The cards deal themselves out one after another.
func entrance() -> void:
	Ui.pop_in(_heading)
	Ui.pop_in(online_card, 0.08)
	Ui.pop_in(friends_card, 0.16)


## Closes whatever box of Donkey Master is open (the search ends with it).
func close_boxes() -> void:
	for box: MenuOverlay in [_setup, _room_box, _search]:
		if box != null:
			box.close()


# ---------- the setup box: seats and entry ----------

## Opens the box to set up a table: for Play Online, or (`private`) a room for friends.
func open_setup(private: bool) -> void:
	_private = private
	_setup_title.text = "Create Room" if private else "Play Online"
	_setup_button.text = "CREATE ROOM" if private else "PLAY NOW"
	var offered: Array = _seat_choices()
	for seats: int in _player_chips:
		_player_chips[seats].visible = seats in offered
	if not _players in offered:
		_players = offered[0]
	_player_chips[_players].button_pressed = true
	_show_stake()
	_refresh_buttons()
	_room_box.close()  # one box at a time
	_setup.open()


func _seat_choices() -> Array:
	if _private:
		return range(DonkeyClient.MIN_PLAYERS, DonkeyClient.MAX_PLAYERS + 1)
	return DonkeyClient.ONLINE_SIZES


func _build_setup() -> void:
	_setup = _overlay("DonkeySetupOverlay", 400.0)
	var column: VBoxContainer = _setup.get_node("Box").get_child(0)
	var header := box_header("Play Online", "DonkeySetupTitle", "DonkeySetupCloseButton", _setup.close)
	_setup_title = header.get_child(1)
	column.add_child(header)

	column.add_child(_box_label("SELECT PLAYERS", 20))
	_players_chips = HBoxContainer.new()
	_players_chips.name = "DonkeyPlayersChips"
	_players_chips.alignment = BoxContainer.ALIGNMENT_CENTER
	_players_chips.add_theme_constant_override("separation", 6)
	var group := ButtonGroup.new()
	for seats in range(DonkeyClient.MIN_PLAYERS, DonkeyClient.MAX_PLAYERS + 1):
		var chip := ChoiceChip.new("%dP" % seats, group)
		chip.name = "DonkeySeats%d" % seats
		chip.add_theme_font_size_override("font_size", 24)
		chip.toggled.connect(func(on: bool) -> void:
			if on:
				_players = seats
				Sound.play("select"))
		_players_chips.add_child(chip)
		_player_chips[seats] = chip
	column.add_child(_players_chips)

	column.add_child(_box_label("SELECT ENTRY AMOUNT", 18))
	var pill := PanelContainer.new()
	pill.name = "DonkeyStakePill"
	pill.custom_minimum_size = Vector2(250, 0)
	pill.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	pill.add_theme_stylebox_override("panel", Ui.box(SETUP_BROWN, 30, 30, 8))
	var pill_row := HBoxContainer.new()
	pill_row.alignment = BoxContainer.ALIGNMENT_CENTER
	pill.add_child(pill_row)
	_free_label = Label.new()
	_free_label.text = "FREE TABLE"
	_free_label.add_theme_font_size_override("font_size", 30)
	_free_label.add_theme_color_override("font_color", Color.WHITE)
	pill_row.add_child(_free_label)
	_stake_coins = CoinLabel.new()
	_stake_coins.name = "DonkeyStakeCoins"
	_stake_coins.font_size = 32
	_stake_coins.text_color = Color.WHITE
	pill_row.add_child(_stake_coins)
	column.add_child(pill)

	_stake_slider = HSlider.new()
	_stake_slider.name = "DonkeyStakeSlider"
	_stake_slider.custom_minimum_size = Vector2(0, 56)
	_stake_slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_stake_slider.rounded = true
	_stake_slider.scrollable = false
	_stake_slider.ticks_on_borders = true
	_dress_slider(_stake_slider)
	_stake_slider.value_changed.connect(_on_stake_slid)
	column.add_child(_stake_slider)

	_stake_hint = _box_label("", 16)
	_stake_hint.add_theme_color_override("font_color", HINT_BROWN)
	_stake_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(_stake_hint)

	_setup_button = Button.new()
	_setup_button.name = "DonkeySetupButton"
	_setup_button.text = "PLAY NOW"
	_setup_button.custom_minimum_size = Vector2(290, 66)
	_setup_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_setup_button.add_theme_font_size_override("font_size", 28)
	_tint(_setup_button, TEAL_BUTTON, Color("0b4d44"))
	_setup_button.pressed.connect(_on_setup_button)
	column.add_child(_setup_button)


# The entry on the pill, and the slider reaching only the tables the player can afford.
func _show_stake() -> void:
	if _stake_slider == null:
		return
	var stakes := DonkeyClient.STAKES
	var reach := 0
	for index in stakes.size():
		if stakes[index] <= Game.coins:
			reach = index
	# Until the player chooses, the cheapest table played for coins is offered
	if not _stake_picked:
		_stake_index = 1 if reach >= 1 else 0
	_stake_index = mini(_stake_index, reach)
	_stake_slider.max_value = maxi(reach, 0)
	_stake_slider.tick_count = stakes.size()
	_stake_slider.set_value_no_signal(_stake_index)
	var amount: int = stakes[_stake_index]
	_stake_coins.visible = amount > 0
	_stake_coins.amount = amount
	_free_label.visible = amount == 0
	if amount == 0:
		_stake_hint.text = "A free table: played for fun, no coins change hands."
	else:
		_stake_hint.text = "Everyone pays the entry. The Donkey's entry goes to the Master; everyone else gets theirs back."


func _on_stake_slid(value: float) -> void:
	_stake_picked = true
	_stake_index = int(value)
	_show_stake()
	Sound.play("select")


func _on_setup_button() -> void:
	var stake: int = DonkeyClient.STAKES[_stake_index]
	if _private:
		Game.donkey.create_room(_players, stake)
		_setup.close()
		return
	if Game.donkey.searching():
		return
	_setup.close()
	_search.open_for(describe_table(_players, stake))
	Game.donkey.find_match(_players, stake)


## A table in a line: "Donkey Master  ·  4 players  ·  entry 500 coins".
static func describe_table(players: int, stake: int) -> String:
	var parts: Array = ["Donkey Master", "%d players" % players]
	parts.append("entry %s coins" % Ui.coins_text(stake) if stake > 0 else "free table")
	return "  ·  ".join(parts)


# ---------- the room box: create or join a private room ----------

func open_room_box() -> void:
	_refresh_buttons()
	_setup.close()  # one box at a time
	_room_box.open()


func _build_room_box() -> void:
	_room_box = _overlay("DonkeyRoomOverlay", 390.0)
	_room_box.get_node("Box").offset_top = 60.0
	var column: VBoxContainer = _room_box.get_node("Box").get_child(0)
	column.add_theme_constant_override("separation", 16)
	column.add_child(box_header("Play with Friends", "DonkeyRoomTitle", "DonkeyRoomCloseButton", _room_box.close))
	var hint := _box_label("Create a private room and share its code with your friends, or enter the code a friend gave you to join their room. Only players with the code can sit down.", 23)
	hint.add_theme_color_override("font_color", HINT_BROWN)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(hint)

	_code_edit = LineEdit.new()
	_code_edit.name = "DonkeyCodeEdit"
	_code_edit.custom_minimum_size = Vector2(300, 0)
	_code_edit.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_code_edit.add_theme_font_size_override("font_size", 30)
	_code_edit.placeholder_text = "Room code"
	_code_edit.alignment = HORIZONTAL_ALIGNMENT_CENTER
	_code_edit.max_length = 6
	_code_edit.text_changed.connect(func(text: String) -> void:
		if text != text.to_upper():
			var caret := _code_edit.caret_column
			_code_edit.text = text.to_upper()
			_code_edit.caret_column = caret)
	_code_edit.text_submitted.connect(_on_join.unbind(1))
	column.add_child(_code_edit)

	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	buttons.add_theme_constant_override("separation", 28)
	_create_button = Button.new()
	_create_button.name = "DonkeyCreateRoomButton"
	_create_button.text = "CREATE ROOM"
	_create_button.custom_minimum_size = Vector2(250, 62)
	_tint(_create_button, GREEN_BUTTON, Color("1b5e20"))
	_create_button.pressed.connect(open_setup.bind(true))
	buttons.add_child(_create_button)
	_join_button = Button.new()
	_join_button.name = "DonkeyJoinRoomButton"
	_join_button.text = "JOIN ROOM"
	_join_button.custom_minimum_size = Vector2(250, 62)
	_tint(_join_button, YELLOW_BUTTON, Color("1b5e20"))
	_join_button.pressed.connect(_on_join)
	buttons.add_child(_join_button)
	column.add_child(buttons)


func _on_join() -> void:
	var code := _code_edit.text.strip_edges()
	if code.is_empty():
		Ui.alert("Enter the room code your friend gave you.", "Join room")
		_code_edit.grab_focus()
		return
	Game.donkey.join_room(code)


func _refresh_buttons() -> void:
	var can_ask := Game.is_online() and not Game.busy
	for button: Button in [_setup_button, _join_button]:
		if button != null:
			button.disabled = not can_ask


# ---------- building blocks ----------

# A box over the home screen in the lobby's look (MenuOverlay): a shade and a cream panel
# hanging from the top, `half_width` either side of the middle. Its column is the Box's child.
func _overlay(overlay_name: String, half_width: float) -> MenuOverlay:
	var overlay := MenuOverlay.new()
	overlay.name = overlay_name
	overlay.visible = false
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	var shade := ColorRect.new()
	shade.name = "Shade"
	shade.color = Color(0, 0, 0, 0.72)
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(shade)
	var box := PanelContainer.new()
	box.name = "Box"
	box.anchor_left = 0.5
	box.anchor_right = 0.5
	box.offset_left = -half_width
	box.offset_right = half_width
	box.offset_top = 22.0
	box.grow_horizontal = Control.GROW_DIRECTION_BOTH
	overlay.add_child(box)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	box.add_child(column)
	return overlay


func _box_label(text: String, font_size: int) -> Label:
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", LABEL_BROWN)
	return label


func _tint(button: Button, fill: Color, ink: Color) -> void:
	Ui.tint_button(button, fill)
	for color_name: String in ["font_color", "font_hover_color", "font_pressed_color"]:
		button.add_theme_color_override(color_name, ink)


# The entry slider in the lobby's look: a brown groove, a white knob with a teal rim.
func _dress_slider(slider: HSlider) -> void:
	var groove := Ui.box(Color("b8a28f"), 8, 0, 0)
	groove.content_margin_top = 7
	groove.content_margin_bottom = 7
	slider.add_theme_stylebox_override("slider", groove)
	var filled := Ui.box(SETUP_BROWN, 8, 0, 0)
	filled.content_margin_top = 7
	filled.content_margin_bottom = 7
	slider.add_theme_stylebox_override("grabber_area", filled)
	slider.add_theme_stylebox_override("grabber_area_highlight", filled)
	var gradient := Gradient.new()
	gradient.offsets = PackedFloat32Array([0.0, 0.66, 0.72, 0.9, 0.96, 1.0])
	gradient.colors = PackedColorArray([
		Color.WHITE, Color.WHITE, Color("26a69a"), Color("26a69a"), Color(0.15, 0.65, 0.6, 0.0), Color(0, 0, 0, 0),
	])
	var knob := GradientTexture2D.new()
	knob.gradient = gradient
	knob.width = 52
	knob.height = 52
	knob.fill = GradientTexture2D.FILL_RADIAL
	knob.fill_from = Vector2(0.5, 0.5)
	knob.fill_to = Vector2(1.0, 0.5)
	for icon_name: String in ["grabber", "grabber_highlight", "grabber_disabled"]:
		slider.add_theme_icon_override(icon_name, knob)
	slider.add_theme_color_override("tick_color", Color(0, 0, 0, 0))  # the ticks only snap, unseen
