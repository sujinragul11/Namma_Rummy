extends Control

func _ready() -> void:
	Game.socket.is_online = true
	Game.player_id = "1"
	Game.friends = []
	Game.friend_asked = []
	Game.friend_requests = []
	Game.state = {"players": [{"id": "2", "username": "Opponent", "avatar": 0}]}
	var panel := preload("res://scenes/opponent_profile.gd").new("2")
	panel.load_on_open = false
	add_child(panel)
	panel.open()
	panel._show_profile({"username": "Opponent", "avatar": 0, "coins": 500,
		"totalGames": 20, "gamesWon": 5, "winPercentage": 25, "friends": 3})
	await get_tree().process_frame
	assert(panel.visible)
	assert(panel._name_label.text == "Opponent")
	assert(panel._values[0].text == "20")
	assert(panel._values[2].text == "25 %")
	assert(panel._add.text == "Add as Friend")
	Game.friend_asked = [{"id": "2"}]
	panel._refresh_friend()
	assert(panel._add.disabled and panel._add.text == "Request sent")
	Game.friend_asked = []
	Game.friends = [{"id": "2"}]
	panel._refresh_friend()
	assert(panel._add.disabled and panel._add.text == "Friends")
	var badge := PlayerBadge.new()
	add_child(badge)
	badge.profile_clickable = true
	var pressed := [false]
	badge.profile_pressed.connect(func() -> void: pressed[0] = true)
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = true
	badge._avatar.gui_input.emit(event)
	assert(not pressed[0]) # opens on the release, never under a finger still down
	event.pressed = false
	badge._avatar.gui_input.emit(event)
	assert(pressed[0])
	panel.close()
	await get_tree().process_frame
	assert(get_tree().get_first_node_in_group(FriendsPanel.BACK_GROUP) == null)
	print("PASS: avatar click, public profile panel, stats, friend states and close")
	Sound.hush()
	get_tree().quit()
