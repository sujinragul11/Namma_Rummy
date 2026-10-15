extends Control
# Opens the home menu as a logged-in player without a server and saves a picture of each
# box: the three game setups and the private-table box. Run WITH a window:
#   godot --path . -s ... no: run as the main scene via the .tscn next to this file, with
#   -- --profile=preview --mute --server=http://127.0.0.1:9 --shots=<folder>

var _shots := ""
var _step := 0


func _ready() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--shots="):
			_shots = argument.trim_prefix("--shots=")
	DirAccess.make_dir_recursive_absolute(_shots)
	# A fake login: enough for the menu to show, no server is asked anything
	Game.remember_login = false
	Game.token = "preview"
	Game.user = {"id": 1, "username": "Sujin"}
	Game.player_id = "1"
	Game.coins = 155060
	var main: Control = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	add_child(main)
	_run(main)


func _run(main: Control) -> void:
	await _wait(0.8)
	await _shot("menu")
	var home: Node = main.get_node("%Screen").get_child(0)
	for tile_name: String in ["CloseJokerTile", "PoolTile", "DealsTile"]:
		(main.find_child(tile_name, true, false) as Button).pressed.emit()
		await _wait(0.6)
		if tile_name == "PoolTile":
			(main.find_child("StakeSlider", true, false) as HSlider).value = 3
			await _wait(0.3)
		await _shot(tile_name.to_lower())
		(main.find_child("SetupCloseButton", true, false) as Button).pressed.emit()
		await _wait(0.3)
	(main.find_child("FriendsTile", true, false) as Button).pressed.emit()
	await _wait(0.6)
	await _shot("private-table")
	(main.find_child("JoinButton", true, false) as Button).pressed.emit()
	await _wait(0.5)
	await _shot("private-table-code")
	(Ui.get_node("MessageBox") as AcceptDialog).hide()  # "enter the room code", from the empty join
	(main.find_child("JoinCloseButton", true, false) as Button).pressed.emit()
	(main.find_child("FriendsTile", true, false) as Button).pressed.emit()
	await _wait(0.3)
	(main.find_child("CreateTableButton", true, false) as Button).pressed.emit()
	await _wait(0.6)
	await _shot("private-setup")
	print("preview: the private setup's button says ", (main.find_child("CreateButton", true, false) as Button).text)
	(main.find_child("SetupCloseButton", true, false) as Button).pressed.emit()
	# The search box of Play Now, as it looks with three of six players found
	Game.match_search = {"gameType": "pool_201", "maxPlayers": 6, "stake": 500}
	Game.match_status = {"found": 3, "needed": 6, "scope": "nearby", "region": "UTC+5:30", "inQueue": 5}
	Game.match_since = Time.get_ticks_msec() - 11000
	Game.match_starts_at = Time.get_ticks_msec() + 9000
	home.get("_search").call("open_for", "Pool Rummy  ·  201 Points  ·  6 players  ·  entry 500 coins")
	await _wait(0.8)
	await _shot("search")
	home.get("_search").call("close")
	await _wait(0.3)
	(main.find_child("HelpButton", true, false) as Button).pressed.emit()
	await _wait(0.6)
	await _shot("rules")
	(main.find_child("RulesCloseButton", true, false) as Button).pressed.emit()
	(main.find_child("AccountButton", true, false) as Button).pressed.emit()
	await _wait(0.6)
	await _shot("settings")
	# With a photo: one made the way the editor makes them, put straight into the app's store,
	# then a picture chosen and waiting for Save
	var picture := Image.create_empty(480, 640, false, Image.FORMAT_RGB8)
	for y in 640:
		for x in 480:
			picture.set_pixel(x, y, Color.from_hsv(float(x + y) / 1400.0, 0.55, 0.95))
	picture.fill_rect(Rect2i(170, 150, 140, 140), Color("ffcc80"))  # something like a face
	var photo: Dictionary = AvatarEditor.make_photo(picture.save_png_to_buffer())
	Game.user["avatar"] = 1
	Game._avatars["1"] = {"version": 1, "texture": null, "failed": false}
	Game._store_avatar("1", 1, photo.jpeg)
	await _wait(0.4)
	await _shot("settings-photo")
	var editor: AvatarEditor = main.find_child("AvatarEditor", true, false)
	editor.open_picture("res://icon.png")
	await _wait(1.0)
	await _shot("settings-photo-chosen")
	editor._cancel()
	(main.find_child("SettingsCloseButton", true, false) as Button).pressed.emit()
	await _wait(0.3)
	await _shot("menu-photo")
	await _wait(0.3)
	home.call("_open_profile")  # what a tap on the player's picture does
	await _wait(0.6)
	await _shot("profile")
	print("preview: %d pictures in %s (home %s)" % [_step, _shots, home.name])
	Sound.hush()
	get_tree().quit()


func _shot(label: String) -> void:
	_step += 1
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("%s/%02d-%s.png" % [_shots, _step, label])


func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout
