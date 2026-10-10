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
	for tile_name: String in ["PointsTile", "PoolTile", "CloseJokerTile"]:
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
	(main.find_child("HelpButton", true, false) as Button).pressed.emit()
	await _wait(0.6)
	await _shot("rules")
	(main.find_child("RulesCloseButton", true, false) as Button).pressed.emit()
	(main.find_child("AccountButton", true, false) as Button).pressed.emit()
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
