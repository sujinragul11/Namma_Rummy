class_name FriendsPanel
extends Control
## The friends list, over the home screen or the lobby: who is online, friend requests,
## adding a friend by username. In the lobby every friend who is free gets an Invite button.
##
## Everything shown comes from the lists on `Game`; the buttons send the player's wishes and
## the server answers with fresh lists.

const SCENE_PATH := "res://scenes/friends.tscn"
## The main scene closes whatever is in this group when the back button is pressed.
const BACK_GROUP := "closes_on_back"
const STATUS_TEXT := {"online": "Online", "lobby": "Waiting at a table", "playing": "In a game", "offline": "Offline"}
const STATUS_ORDER := {"online": 0, "lobby": 1, "playing": 2, "offline": 3}
const STATUS_COLORS := {
	"online": Color("66bb6a"), "lobby": Color("66bb6a"), "playing": Color("ffc107"), "offline": Color("78909c"),
}
const DOT_SIZE := 16.0
const NAME_WIDTH := 340.0  # room for a 20-letter username beside three buttons

var _asked_name := ""  # the username last sent, to clear the field once it shows up in a list
var _rebuild_queued := false

@onready var _panel: Control = %Panel
@onready var _title: Label = %Title
@onready var _close_button: Button = %CloseButton
@onready var _name_edit: LineEdit = %NameEdit
@onready var _add_button: Button = %AddButton
@onready var _rows: VBoxContainer = %Rows


## Opens the panel over `screen`, unless it is open already.
static func open(screen: Control) -> void:
	if screen.get_tree().get_first_node_in_group(BACK_GROUP) != null:
		return
	var panel: FriendsPanel = (load(SCENE_PATH) as PackedScene).instantiate()
	screen.add_child(panel)


func _ready() -> void:
	add_to_group(BACK_GROUP)
	# Solid like the message boxes: the screen underneath must not show through the list
	var frame := Ui.box(Ui.FELT_DARK, 22, 30, 22)
	frame.border_color = Ui.GOLD.darkened(0.25)
	frame.set_border_width_all(2)
	_panel.add_theme_stylebox_override("panel", frame)
	_title.add_theme_font_override("font", Ui.bold_font)
	Ui.tint_button(_add_button, Ui.PRIMARY)
	_close_button.pressed.connect(close)
	_add_button.pressed.connect(_on_add)
	_name_edit.text_submitted.connect(_on_add.unbind(1))
	%Shade.gui_input.connect(_on_shade_input)

	Game.friends_changed.connect(_queue_rebuild)
	Game.state_changed.connect(_queue_rebuild)
	Game.connection_changed.connect(_queue_rebuild)
	Game.busy_changed.connect(_refresh_buttons)
	_rebuild()
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


func _on_add() -> void:
	var username := _name_edit.text.strip_edges()
	if username.is_empty():
		Ui.alert("Type your friend's username: the name they see after \"Welcome\" on their own screen.", "Add friend")
		return
	_asked_name = username
	Game.add_friend(username)


# Several signals often arrive together; the rows are rebuilt once, on the next frame.
func _queue_rebuild() -> void:
	if not _rebuild_queued:
		_rebuild_queued = true
		_rebuild.call_deferred()


func _rebuild() -> void:
	_rebuild_queued = false
	_clear_field_when_asked()
	for row in _rows.get_children():
		_rows.remove_child(row)
		row.queue_free()

	if not Game.is_online():
		_add_note("Connecting to the game server... Your friends will show up in a moment.")

	if not Game.friend_requests.is_empty():
		_add_heading("Friend requests")
		for request: Dictionary in Game.friend_requests:
			var id := str(request.get("id", ""))
			var username := str(request.get("username", "Player"))
			_add_row(username, "wants to be your friend", "", [
				_button("Accept", Ui.PRIMARY, Game.answer_friend.bind(id, "accept")),
				_button("Decline", Ui.SLATE, Game.answer_friend.bind(id, "decline")),
				_button("Block", Ui.SLATE, _confirm_block.bind(id, username)),
			], request)

	var online := Game.friends_online()
	_add_heading("Friends  ·  %d online" % online if online > 0 else "Friends")
	if Game.friends.is_empty():
		_add_note("No friends yet. Type a friend's username above and tap Add friend. They see your request the next time they open the game.")
	var inviting := Game.status() == "waiting"
	var seats_left := int(Game.state.get("maxPlayers", 0)) - Game.players().size()
	for friend: Dictionary in _sorted(Game.friends):
		var id := str(friend.get("id", ""))
		var username := str(friend.get("username", "Player"))
		var status := str(friend.get("status", "offline"))
		var buttons: Array[Button] = []
		if inviting:
			var invite := _button("Invite", Ui.BLUE, Game.invite_friend.bind(id))
			# Friends who are playing or away cannot come; neither can anyone once the table is full
			invite.disabled = status not in ["online", "lobby"] or seats_left <= 0 or _at_my_table(id)
			invite.set_meta("free", not invite.disabled)
			buttons.append(invite)
		buttons.append(_button("Remove", Ui.SLATE, _confirm_remove.bind(id, username)))
		_add_row(username, "At your table" if _at_my_table(id) else STATUS_TEXT.get(status, "Offline"), status, buttons, friend)

	if not Game.friend_asked.is_empty():
		_add_heading("Waiting for an answer")
		for asked: Dictionary in Game.friend_asked:
			_add_row(str(asked.get("username", "Player")), "has not answered yet", "", [
				_button("Cancel", Ui.SLATE, Game.remove_friend.bind(str(asked.get("id", "")))),
			], asked)

	if not Game.recent_players.is_empty():
		_add_heading("Played with recently")
		for player: Dictionary in Game.recent_players:
			var username := str(player.get("username", "Player"))
			_add_row(username, "you met at a table", "", [
				_button("Add friend", Ui.PRIMARY, Game.add_friend.bind(username)),
			], player)
	_refresh_buttons()


# Nothing can be sent twice while a request is on its way, or while offline.
func _refresh_buttons() -> void:
	var blocked := Game.busy or not Game.is_online()
	_add_button.disabled = blocked
	for button: Button in _rows.find_children("*", "Button", true, false):
		button.disabled = blocked or not button.get_meta("free", true)


func _clear_field_when_asked() -> void:
	if _asked_name.is_empty():
		return
	for entry: Dictionary in Game.friend_asked + Game.friends:
		if str(entry.get("username", "")).to_lower() == _asked_name.to_lower():
			_name_edit.text = ""
			_asked_name = ""
			return


func _at_my_table(friend_id: String) -> bool:
	for player: Dictionary in Game.players():
		if str(player.get("id", "")) == friend_id:
			return true
	return false


# Friends who can play come first, then by name.
func _sorted(friends: Array) -> Array:
	var sorted := friends.duplicate()
	sorted.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var a_rank: int = STATUS_ORDER.get(a.get("status"), 3)
		var b_rank: int = STATUS_ORDER.get(b.get("status"), 3)
		if a_rank != b_rank:
			return a_rank < b_rank
		return str(a.get("username", "")).naturalnocasecmp_to(str(b.get("username", ""))) < 0
	)
	return sorted


func _confirm_remove(id: String, username: String) -> void:
	Ui.confirm("Remove friend", "Remove %s from your friends?" % username, "Remove", Game.remove_friend.bind(id))


func _confirm_block(id: String, username: String) -> void:
	Ui.confirm("Block", "Block %s? Their friend requests will no longer reach you." % username, "Block", Game.answer_friend.bind(id, "block"))


# ---------- building rows ----------

func _add_heading(text: String) -> void:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 20)
	label.add_theme_color_override("font_color", Ui.PALE_GREEN)
	_rows.add_child(label)


func _add_note(text: String) -> void:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", 20)
	_rows.add_child(label)


# One player: a status dot, the avatar with two lines of text, and the buttons on the right.
# `who` is the player's entry in the list, for their photo.
func _add_row(username: String, info: String, status: String, buttons: Array, who: Dictionary = {}) -> void:
	var row := HBoxContainer.new()
	row.name = "Row_" + username
	row.add_theme_constant_override("separation", 12)

	var dot := Panel.new()
	dot.custom_minimum_size = Vector2(DOT_SIZE, DOT_SIZE)
	dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dot.add_theme_stylebox_override("panel", Ui.box(STATUS_COLORS.get(status, STATUS_COLORS.offline), int(DOT_SIZE / 2.0), 0, 0))
	row.add_child(dot)

	var badge := PlayerBadge.new()
	badge.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	badge.name_width = NAME_WIDTH
	badge.show_player(username, info, false, status == "offline")
	badge.show_photo(str(who.get("id", "")), int(who.get("avatar", 0)))
	row.add_child(badge)

	for button: Button in buttons:
		row.add_child(button)
	_rows.add_child(row)


func _button(text: String, color: Color, on_press: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	Ui.tint_button(button, color)
	button.pressed.connect(on_press)
	return button
