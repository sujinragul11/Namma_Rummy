extends Control
## Shows the screen that fits the session: home (login or menu), the lobby, or the table.
## Screens never switch to one another directly; they change the session and this follows.
##
## It also looks after what a phone needs around the screens: keeping clear of the notch,
## the back button, and catching up after the app was in the background.

const SCREENS := {
	"home": preload("res://scenes/home.tscn"),
	"lobby": preload("res://scenes/lobby.tscn"),
	"table": preload("res://scenes/table.tscn"),
}
const FADE_SECONDS := 0.22

var _showing := ""
var _drift: DriftingSuits

@onready var _screen: Control = %Screen


func _ready() -> void:
	theme = Ui.game_theme
	# Faint card suits rising over the felt, behind the home screen and the lobby
	_drift = DriftingSuits.new()
	add_child(_drift)
	move_child(_drift, _screen.get_index())
	Game.auth_changed.connect(_refresh)
	Game.state_changed.connect(_refresh)
	Game.invite_received.connect(_on_invite)
	get_viewport().size_changed.connect(_keep_clear_of_cutouts)
	_keep_clear_of_cutouts()
	_refresh()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		_on_back()
	elif what == NOTIFICATION_APPLICATION_RESUMED:
		Game.resync()


func _unhandled_input(event: InputEvent) -> void:
	# Escape does on a PC what the back button does on a phone
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		_on_back()


func _refresh() -> void:
	var wanted := "home"
	if Game.is_logged_in():
		match Game.status():
			"waiting":
				wanted = "lobby"
			"playing", "round_over", "finished":
				wanted = "table"
	if wanted == _showing:
		return

	if not _showing.is_empty():
		Sound.play("whoosh")  # not for the very first screen
	Sound.music("table" if wanted == "table" else "menu")
	_drift.visible = wanted != "table"  # nothing moves behind the cards during a game
	_showing = wanted
	for child in _screen.get_children():
		child.queue_free()
	var screen: Control = SCREENS[wanted].instantiate()
	_screen.add_child(screen)
	# The new screen fades in over the felt
	screen.modulate.a = 0.0
	screen.create_tween().tween_property(screen, "modulate:a", 1.0, FADE_SECONDS)


# The back button never throws the player out of a game without asking.
func _on_back() -> void:
	if Ui.close_dialogs():
		return
	# A panel lying over the screen (the friends list) closes before the screen itself
	var panel := get_tree().get_first_node_in_group(FriendsPanel.BACK_GROUP)
	if panel != null:
		panel.call("close")
		return
	match _showing:
		"table":
			if Game.status() == "finished":
				Game.leave()
			else:
				Ui.confirm("Leave game", Ui.leave_game_warning(), "Leave", Game.leave)
		"lobby":
			Ui.confirm("Leave lobby", Ui.leave_lobby_warning(), "Leave", Game.leave)
		_:
			Ui.confirm("Exit", "Close Namma Rummy?", "Exit", _quit)


func _quit() -> void:
	Sound.hush()  # the engine reports a tune still playing when the game closes as a leak
	get_tree().quit()


# A friend calls us to their table. The question takes every touch until it is answered, so
# it never opens over a game in progress; the server does not send invitations there either.
func _on_invite(invite: Dictionary) -> void:
	var friend := str(invite.get("username", "A friend"))
	if _showing == "table" and Game.status() != "finished":
		Ui.notify("info", "%s invited you to a game" % friend)
		return
	Sound.play("go")
	Input.vibrate_handheld(200)
	var game := Game.name_of_game(invite.get("poolLimit"), invite.get("closedJoker", false), invite.get("deals"))
	var text := "%s invites you to a game of %s rummy for %d players." % [friend, game, int(invite.get("maxPlayers", 2))]
	if invite.get("again", false):
		# Someone we have just played with opened a new table with the same rules
		text = "%s wants to play again: %s rummy for %d players." % [friend, game, int(invite.get("maxPlayers", 2))]
	var stake := int(invite.get("stake", 0))
	var point_value := int(invite.get("pointValue", 0))
	if point_value > 0:
		text += "\n\n%s coins a point: you pay what your points cost, at most %s coins." % [Ui.coins_text(point_value), Ui.coins_text(stake)]
	elif stake > 0:
		text += "\n\nEntry: %s coins. The winner takes the pot." % Ui.coins_text(stake)
	Ui.confirm(
		"Game invitation",
		text,
		"Join",
		Game.join_by_code.bind(str(invite.get("roomCode", "")))
	)


# Phones have notches and rounded corners; the system reports the area that is safe to use.
func _keep_clear_of_cutouts() -> void:
	if not OS.has_feature("mobile"):
		return
	var window_size := DisplayServer.window_get_size()
	var safe := DisplayServer.get_display_safe_area()
	if window_size.x <= 0 or window_size.y <= 0 or safe.size.x <= 0 or safe.size.y <= 0:
		return
	# Window pixels to the units the game is laid out in
	var units := get_viewport().get_visible_rect().size.x / float(window_size.x)
	_screen.offset_left = maxf(0.0, safe.position.x * units)
	_screen.offset_top = maxf(0.0, safe.position.y * units)
	_screen.offset_right = -maxf(0.0, (window_size.x - safe.end.x) * units)
	_screen.offset_bottom = -maxf(0.0, (window_size.y - safe.end.y) * units)
