extends Control
## The waiting room: the room code to share on the left, who has joined on the right.
## The game starts by itself when the table is full; the host can start it earlier.

const TURN_SECONDS := 30

var _shown_players: Dictionary = {}  # player id -> PlayerBadge
var _listed_once := false  # the players already there when the lobby opens arrive silently
var _dots_time := 0.0

@onready var _title: Label = %Title
@onready var _code_panel: Control = %CodePanel
@onready var _code_label: Label = %CodeLabel
@onready var _copy_button: Button = %CopyButton
@onready var _invite_button: Button = %InviteButton
@onready var _whatsapp_button: Button = %WhatsAppButton
@onready var _players_title: Label = %PlayersTitle
@onready var _info_label: Label = %InfoLabel
@onready var _players_list: VBoxContainer = %PlayersList
@onready var _waiting_label: Label = %WaitingLabel
@onready var _start_button: Button = %StartButton
@onready var _leave_button: Button = %LeaveButton


func _ready() -> void:
	_title.add_theme_font_override("font", Ui.bold_font)
	_code_label.add_theme_font_override("font", Ui.bold_font)
	Ui.tint_button(_start_button, Ui.PRIMARY)
	Ui.tint_button(_leave_button, Ui.RED)
	Ui.tint_button(_invite_button, Ui.TEAL)
	Ui.tint_button(_whatsapp_button, Ui.PRIMARY)
	_copy_button.pressed.connect(_on_copy)
	_invite_button.pressed.connect(_on_invite)
	_whatsapp_button.pressed.connect(_on_whatsapp)
	_start_button.pressed.connect(Game.start_game)
	_leave_button.pressed.connect(_on_leave)
	Game.state_changed.connect(_refresh)
	Game.busy_changed.connect(_refresh)
	Game.friends_changed.connect(_refresh)
	_refresh()
	get_tree().process_frame.connect(Ui.pop_in.bind(_code_panel), CONNECT_ONE_SHOT)


func _process(delta: float) -> void:
	# "Waiting..." counts its dots, so the screen never looks frozen
	_dots_time += delta
	var state := Game.state
	var seats_left := int(state.get("maxPlayers", 2)) - Game.players().size()
	if seats_left > 0:
		var dots := ".".repeat(1 + int(_dots_time * 2.0) % 3)
		_waiting_label.text = "Waiting for %d more %s%s\nShare the room code with your friends." % [
			seats_left, "player" if seats_left == 1 else "players", dots
		]


func _refresh() -> void:
	var state := Game.state
	if state.is_empty():
		return  # leaving; the main scene is about to close this screen

	var players := Game.players()
	var max_players := int(state.get("maxPlayers", 2))
	var seats_left := max_players - players.size()

	_code_label.text = str(state.get("roomCode", ""))
	_players_title.text = "Players (%d/%d)" % [players.size(), max_players]
	_info_label.text = "%s rummy  ·  13 cards each  ·  %d seconds per turn\nThe game starts by itself when the table is full." % [
		Game.game_name(), TURN_SECONDS
	]
	if state.get("closedJoker", false):
		_info_label.text += "\nThe joker lies face down: you see it once you make a pure sequence."
	if Game.deals() > 0:
		_info_label.text += "\n%d deals played for chips; the most chips after the last deal win." % Game.deals()
	if state.get("private", false):
		_info_label.text += "\nPrivate table: only the friends you give the room code to can sit down."
	var stake := int(state.get("stake", 0))
	if Game.point_value() > 0:
		_info_label.text += "\n%s coins a point: each loser pays the winner what their points cost (at most %s)." % [
			Ui.coins_text(Game.point_value()), Ui.coins_text(stake)
		]
	elif stake > 0:
		_info_label.text += "\nEntry: %s coins each. The winner takes the pot (%s with a full table)." % [
			Ui.coins_text(stake), Ui.coins_text(stake * max_players)
		]

	# One badge per player; a new arrival pops in
	var present := {}
	for player: Dictionary in players:
		var id := str(player.get("id", ""))
		present[id] = true
		var badge: PlayerBadge = _shown_players.get(id)
		if badge == null:
			if _listed_once:
				Sound.play("join")  # someone arrived after the lobby opened
			badge = PlayerBadge.new()
			_players_list.add_child(badge)
			_shown_players[id] = badge
			Ui.pop_in.call_deferred(badge)

		var notes: Array = []
		if id == Game.player_id:
			notes.append("You")
		if id == str(state.get("hostId", "")):
			notes.append("Host")
		notes.append("Ready" if player.get("connected", true) else "Offline")
		badge.show_player(str(player.get("username", "Player")), "  ·  ".join(notes), false, not player.get("connected", true))
	for id: String in _shown_players.keys():
		if not present.has(id):
			Sound.play("leave")
			_shown_players[id].queue_free()
			_shown_players.erase(id)
	_listed_once = true

	if seats_left <= 0:
		_waiting_label.text = "Starting..."
	var is_host: bool = state.get("hostId") == Game.player_id
	_start_button.visible = is_host and players.size() >= 2 and seats_left > 0
	_start_button.text = "Start with %d players" % players.size()
	_start_button.disabled = Game.busy

	var online := Game.friends_online()
	_invite_button.text = "Invite friends  ·  %d online" % online if online > 0 else "Invite friends"


func _on_copy() -> void:
	DisplayServer.clipboard_set(_code_label.text)
	Ui.notify("info", "Room code copied")
	Ui.pulse(_code_label, 1.06)


func _on_invite() -> void:
	FriendsPanel.open(self)


# For friends who are not in the friends list yet: the room code as a WhatsApp message.
func _on_whatsapp() -> void:
	var message := "Join my Namma Rummy game! Open the game, tap \"Join game\" and enter room code %s" % _code_label.text
	OS.shell_open("https://wa.me/?text=" + message.uri_encode())


func _on_leave() -> void:
	Ui.confirm("Leave lobby", Ui.leave_lobby_warning(), "Leave", Game.leave)
