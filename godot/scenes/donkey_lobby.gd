class_name DonkeyLobby
extends Control
## Donkey Master's waiting room: the room code to share on the left, the seats on the right.
## The cards are dealt by themselves when the table is full; the host can deal earlier, as
## soon as two players sit. Built in code; Game.donkey's state is all it shows.

const SEAT_COLUMNS := 2

var _shown_players: Dictionary = {}  # player id -> PlayerBadge
var _listed_once := false  # the players already there when the room opens arrive silently
var _dots_time := 0.0
var _title: Label
var _code_panel: PanelContainer
var _code_label: Label
var _share_row: HBoxContainer
var _info_label: Label
var _players_title: Label
var _seats: GridContainer
var _waiting_label: Label
var _start_button: Button
var _invite_box: MenuOverlay
var _invite_list: VBoxContainer


## What a player is told before leaving the room: the entry comes back, nothing was played.
static func leave_warning() -> String:
	var text := "Are you sure you want to leave the room?"
	var stake := int(Game.donkey.state.get("stake", 0))
	if stake > 0:
		text += "\n\nYou get your %s coins back." % Ui.coins_text(stake)
	return text


func _init() -> void:
	name = "DonkeyLobby"
	set_anchors_preset(Control.PRESET_FULL_RECT)

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side: String in ["left", "right"]:
		margin.add_theme_constant_override("margin_" + side, 48)
	for side: String in ["top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 24)
	add_child(margin)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 32)
	margin.add_child(row)

	var left := VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.alignment = BoxContainer.ALIGNMENT_CENTER
	left.add_theme_constant_override("separation", 16)
	row.add_child(left)
	var heading := HBoxContainer.new()
	heading.add_theme_constant_override("separation", 12)
	var donkey := TextureRect.new()
	donkey.texture = DonkeyHome.picture("donkey")
	donkey.custom_minimum_size = Vector2(64, 64)
	donkey.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	donkey.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	heading.add_child(donkey)
	_title = Label.new()
	_title.name = "DonkeyLobbyTitle"
	_title.text = "Donkey Master"
	_title.add_theme_font_size_override("font_size", 40)
	_title.add_theme_color_override("font_color", DonkeyHome.TITLE_GOLD)
	_title.add_theme_color_override("font_outline_color", Color("4e2a0c"))
	_title.add_theme_constant_override("outline_size", 8)
	heading.add_child(_title)
	left.add_child(heading)

	_code_panel = PanelContainer.new()
	_code_panel.name = "DonkeyCodePanel"
	var code_row := HBoxContainer.new()
	code_row.add_theme_constant_override("separation", 16)
	_code_panel.add_child(code_row)
	var texts := VBoxContainer.new()
	texts.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	texts.add_theme_constant_override("separation", 0)
	var code_title := Label.new()
	code_title.text = "ROOM CODE"
	code_title.add_theme_font_size_override("font_size", 18)
	code_title.add_theme_color_override("font_color", Ui.PALE_GREEN)
	texts.add_child(code_title)
	_code_label = Label.new()
	_code_label.name = "DonkeyRoomCode"
	_code_label.text = "------"
	_code_label.add_theme_font_size_override("font_size", 60)
	_code_label.add_theme_color_override("font_color", Ui.GOLD)
	texts.add_child(_code_label)
	code_row.add_child(texts)
	var copy_button := _button("Copy", Ui.SLATE, _on_copy)
	copy_button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	code_row.add_child(copy_button)
	left.add_child(_code_panel)

	_share_row = HBoxContainer.new()
	_share_row.add_theme_constant_override("separation", 12)
	_share_row.add_child(_button("Invite friends", Ui.TEAL, _open_invites, "DonkeyInviteButton"))
	_share_row.add_child(_button("Share on WhatsApp", Ui.PRIMARY, _on_whatsapp))
	left.add_child(_share_row)

	_info_label = Label.new()
	_info_label.name = "DonkeyLobbyInfo"
	_info_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_info_label.add_theme_font_size_override("font_size", 20)
	_info_label.add_theme_color_override("font_color", Ui.PALE_GREEN)
	left.add_child(_info_label)
	var leave := _button("Leave", Ui.RED, _on_leave, "DonkeyLobbyLeaveButton")
	leave.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	left.add_child(leave)

	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.alignment = BoxContainer.ALIGNMENT_CENTER
	right.add_theme_constant_override("separation", 14)
	row.add_child(right)
	_players_title = Label.new()
	_players_title.add_theme_font_size_override("font_size", 28)
	right.add_child(_players_title)
	var seats_panel := PanelContainer.new()
	_seats = GridContainer.new()
	_seats.name = "DonkeySeats"
	_seats.columns = SEAT_COLUMNS
	_seats.add_theme_constant_override("h_separation", 24)
	_seats.add_theme_constant_override("v_separation", 12)
	seats_panel.add_child(_seats)
	right.add_child(seats_panel)
	_waiting_label = Label.new()
	_waiting_label.name = "DonkeyWaitingLabel"
	_waiting_label.add_theme_font_size_override("font_size", 20)
	_waiting_label.add_theme_color_override("font_color", Ui.PALE_GREEN)
	right.add_child(_waiting_label)
	_start_button = _button("Start", Ui.PRIMARY, Game.donkey.start, "DonkeyStartButton")
	_start_button.custom_minimum_size = Vector2(300, 62)
	_start_button.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	right.add_child(_start_button)

	_build_invite_box()


func _ready() -> void:
	_title.add_theme_font_override("font", Ui.bold_font)
	_code_label.add_theme_font_override("font", Ui.bold_font)
	_players_title.add_theme_font_override("font", Ui.bold_font)
	Game.donkey.changed.connect(_refresh)
	Game.busy_changed.connect(_refresh)
	Game.friends_changed.connect(_refresh_invites)
	_refresh()
	get_tree().process_frame.connect(Ui.pop_in.bind(_code_panel), CONNECT_ONE_SHOT)


func _process(delta: float) -> void:
	# "Waiting..." counts its dots, so the screen never looks frozen
	_dots_time += delta
	var seats_left := int(Game.donkey.state.get("maxPlayers", 2)) - Game.donkey.players().size()
	if seats_left > 0 and Game.donkey.in_room():
		var dots := ".".repeat(1 + int(_dots_time * 2.0) % 3)
		_waiting_label.text = "Waiting for %d more %s%s" % [seats_left, "player" if seats_left == 1 else "players", dots]
		if Game.donkey.state.get("private", false):
			_waiting_label.text += "\nShare the room code with your friends."


func _refresh() -> void:
	var state := Game.donkey.state
	if state.is_empty():
		return  # leaving; the main scene is about to close this screen
	var players := Game.donkey.players()
	var max_players := int(state.get("maxPlayers", 2))
	var private: bool = state.get("private", false)
	_code_panel.visible = private
	_share_row.visible = private
	_code_label.text = str(state.get("roomCode", ""))
	_players_title.text = "Players (%d/%d)" % [players.size(), max_players]
	var stake := int(state.get("stake", 0))
	_info_label.text = "Donkey Master  ·  up to %d players  ·  all 52 cards dealt\nThe cards are dealt by themselves when the table is full." % max_players
	if private:
		_info_label.text += "\nPrivate room: only friends with the room code can sit down."
	if stake > 0:
		_info_label.text += "\nEntry: %s coins each. The Donkey loses theirs to the Master; everyone else gets theirs back." % Ui.coins_text(stake)
	else:
		_info_label.text += "\nA free table: no coins change hands."

	# One badge per player; a new arrival pops in
	var present := {}
	for player: Dictionary in players:
		var id := str(player.get("id", ""))
		present[id] = true
		var badge: PlayerBadge = _shown_players.get(id)
		if badge == null:
			if _listed_once:
				Sound.play("join")  # someone arrived after the room opened
			badge = PlayerBadge.new()
			badge.name_width = 200.0
			_seats.add_child(badge)
			_shown_players[id] = badge
			Ui.pop_in.call_deferred(badge)
		var notes: Array = []
		if id == Game.player_id:
			notes.append("You")
		if id == str(state.get("hostId", "")):
			notes.append("Host")
		notes.append("Ready" if player.get("connected", true) else "Offline")
		badge.show_player(str(player.get("username", "Player")), "  ·  ".join(notes), false, not player.get("connected", true))
		badge.show_photo(id, int(player.get("avatar", 0)))
	for id: String in _shown_players.keys():
		if not present.has(id):
			Sound.play("leave")
			_shown_players[id].queue_free()
			_shown_players.erase(id)
	_listed_once = true

	var seats_left := max_players - players.size()
	if seats_left <= 0:
		_waiting_label.text = "Dealing..."
	_start_button.visible = Game.donkey.is_host() and players.size() >= DonkeyClient.MIN_PLAYERS and seats_left > 0
	_start_button.text = "Start with %d players" % players.size()
	_start_button.disabled = Game.busy
	_refresh_invites()


func _on_copy() -> void:
	DisplayServer.clipboard_set(_code_label.text)
	Ui.notify("info", "Room code copied")
	Ui.pulse(_code_label, 1.06)


func _on_whatsapp() -> void:
	var message := "Play Donkey Master with me on Namma Rummy! Open the game, tap Donkey Master, then Play with Friends, and enter room code %s" % _code_label.text
	OS.shell_open("https://wa.me/?text=" + message.uri_encode())


func _on_leave() -> void:
	Ui.confirm("Leave room", leave_warning(), "Leave", Game.donkey.leave)


# ---------- inviting friends ----------

func _build_invite_box() -> void:
	_invite_box = MenuOverlay.new()
	_invite_box.name = "DonkeyInviteOverlay"
	_invite_box.set_anchors_preset(Control.PRESET_FULL_RECT)
	var shade := ColorRect.new()
	shade.name = "Shade"
	shade.color = Color(0, 0, 0, 0.72)
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	_invite_box.add_child(shade)
	var box := PanelContainer.new()
	box.name = "Box"
	box.anchor_left = 0.5
	box.anchor_right = 0.5
	box.offset_left = -360.0
	box.offset_right = 360.0
	box.offset_top = 40.0
	box.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_invite_box.add_child(box)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	box.add_child(column)
	column.add_child(DonkeyHome.box_header("Invite Friends", "DonkeyInviteTitle", "DonkeyInviteCloseButton", _invite_box.close))
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 380)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	column.add_child(scroll)
	_invite_list = VBoxContainer.new()
	_invite_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_invite_list.add_theme_constant_override("separation", 8)
	scroll.add_child(_invite_list)
	add_child(_invite_box)


func _open_invites() -> void:
	_invite_box.open()
	_refresh_invites()


# Friends who are online and not at our table, each with a button that calls them over.
func _refresh_invites() -> void:
	if _invite_list == null or not _invite_box.visible:
		return
	for child in _invite_list.get_children():
		child.queue_free()
	var seated := {}
	for player: Dictionary in Game.donkey.players():
		seated[str(player.get("id", ""))] = true
	var shown := 0
	for friend: Dictionary in Game.friends:
		var id := str(friend.get("id", ""))
		if seated.has(id):
			continue
		var status := str(friend.get("status", "offline"))
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 12)
		var name_label := Label.new()
		name_label.text = "%s  ·  %s" % [friend.get("username", "Friend"), status.capitalize()]
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name_label.add_theme_color_override("font_color", DonkeyHome.LABEL_BROWN)
		row.add_child(name_label)
		var invite := _button("Invite", Ui.BLUE, Game.donkey.invite.bind(id), "DonkeyInvite_" + id)
		invite.disabled = status != "online"
		row.add_child(invite)
		_invite_list.add_child(row)
		shown += 1
	if shown == 0:
		var none := Label.new()
		none.text = "None of your friends is online right now. Share the room code instead."
		none.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		none.add_theme_color_override("font_color", DonkeyHome.HINT_BROWN)
		_invite_list.add_child(none)


func _button(text: String, color: Color, action: Callable, button_name: String = "") -> Button:
	var button := Button.new()
	button.text = text
	if not button_name.is_empty():
		button.name = button_name
	Ui.tint_button(button, color)
	button.pressed.connect(action)
	return button
