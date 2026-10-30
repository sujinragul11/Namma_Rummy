extends Control

func _ready() -> void:
	Game.socket.is_online = true
	Game.friends = [
		{"id": "100", "username": "Nathi", "coins": 183700, "status": "online"},
		{"id": "101", "username": "Jose", "coins": 8600, "status": "offline"}
	]
	Game.friend_requests = []
	Game.friend_asked = []
	Game.recent_players = []
	var panel: FriendsPanel = load(FriendsPanel.SCENE_PATH).instantiate()
	add_child(panel)
	await get_tree().process_frame
	await get_tree().process_frame
	assert(panel._rows.find_child("Row_Nathi", true, false) != null)
	assert(panel._rows.find_child("Row_Jose", true, false) == null)
	panel._select_tab("all")
	await get_tree().process_frame
	assert(panel._rows.find_child("Row_Jose", true, false) != null)
	var row: Control = panel._rows.find_child("Row_Nathi", true, false)
	assert(row.size.x <= panel._rows.size.x)
	panel._select_tab("requests")
	assert(panel._rows.find_child("Row_Nathi", true, false) == null)
	assert(panel._rows.get_child_count() == 1)
	Game.friend_requests = [{"id": "102", "username": "New friend"}]
	panel._rebuild()
	assert(panel._rows.find_child("Row_New friend", true, false) != null)
	panel._select_tab("add")
	assert(panel.get_node("%AddRow").visible)
	assert(panel._rows.get_child_count() == 1)
	panel._select_tab("online")
	assert(not panel.get_node("%AddRow").visible)
	Game.state = {"status": "waiting", "maxPlayers": 6, "players": []}
	panel._rebuild()
	assert(panel._rows.find_children("*", "Button", true, false).size() == 2)
	panel.close()
	await get_tree().process_frame
	assert(get_tree().get_first_node_in_group(FriendsPanel.BACK_GROUP) == null)
	print("PASS: friends online/all filtering, requests, add, cards fit, lobby invite and close")
	Sound.hush()
	get_tree().quit()
