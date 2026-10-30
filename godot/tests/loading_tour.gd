extends Control
## The loading screen: the logo stays up until the game server has answered and accepted the
## login, and nothing of the game (the menu, the player's picture) shows before that.
## It goes through the ways an app start can go: no server yet (it comes up later, as the
## public server does when it wakes), a fresh login, a saved login, a saved login while the
## server is away or cannot check logins, a login the server has ended, and a player who was
## in the middle of a game.
##
## Like session_e2e, it starts and stops its own server (tests/test_server.js, so `node` must
## be on the PATH), on a port and a database nothing else uses:
##   godot --headless --path . res://tests/loading_tour.tscn -- --port=3171 --db=My_Rummy_load_test --profile=loadtour --mute
## The port after it stands for a wrong server address: nothing may answer there.
## The database is dropped and created again at the start. Without --headless it opens a
## window and saves pictures to --shots=<folder> (default user://loading_tour).

const START_SECONDS := 60.0  # a fresh database takes a while when other tests or builds keep the PC busy
const OUTAGE_FLAG := "user://loading_tour_outage.flag"
const PASSWORD := "secret12"

var _port := 3171
var _database := "My_Rummy_load_test"
var _server_script := ProjectSettings.globalize_path("res://tests/test_server.js")
var _server_pid := -1
var _shots := "user://loading_tour"
var _main: Control
var _screens: Array[String] = []  # every screen main put up, in order
var _early: Array[String] = []  # screens with a login that came up before the connection was open
var _passed := 0
var _failed := 0


func _ready() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--port="):
			_port = int(argument.trim_prefix("--port="))
		elif argument.begins_with("--db="):
			_database = argument.trim_prefix("--db=")
		elif argument.begins_with("--server-script="):
			_server_script = argument.trim_prefix("--server-script=")
		elif argument.begins_with("--shots="):
			_shots = argument.trim_prefix("--shots=")
	DirAccess.make_dir_recursive_absolute(_shots)
	_set_outage(false)
	Game.remember_login = false
	Game.server_url = _url()  # first: logging out tells the server
	Game.logout()
	_run()


func _run() -> void:
	if await _server_answers() or await _server_answers(_wrong_url()):
		_check("nothing else runs on ports %d and %d" % [_port, _port + 1], false)
		_finish()
		return

	# ---------- the app starts and no server answers ----------
	Game.server_url = _wrong_url()  # as when the PC with the server has a new address
	_open_main()
	var logo: Control = _node("LoadingLogo")
	_check("the app opens on the loading screen", _main.loading() and logo != null)
	var middle := get_viewport().get_visible_rect().size / 2.0
	var logo_box := _box(logo)
	_check("the logo starts where the boot splash has it: in the middle", logo_box.get_center().distance_to(middle) < 8.0, str(logo_box))
	_check("and at the boot splash's size", absf(logo_box.size.y - LoadingScreen.BOOT_LOGO_HEIGHT) < 8.0, str(logo_box.size))
	await _shot("1-boot")
	await _wait(1.2)
	logo_box = _box(logo)
	_check("then it rises to make room", logo_box.get_center().y < middle.y - 40.0 and logo_box.size.y < LoadingScreen.BOOT_LOGO_HEIGHT, str(logo_box))
	_check("the suits hop under it", _shown("LoadingSuits") and _node("LoadingSuits").global_position.y > logo_box.end.y)
	_check("and it says what it waits for", _text("LoadingStatus").contains("Connecting"), _text("LoadingStatus"))
	await _shot("2-connecting")
	_check("no login form while nothing answers", not _has("AuthPanel") and not _has("MenuPanel"))
	_check("nothing answering is soon said, with Try again", await _until(func() -> bool: return _shown("LoadingTrouble"), 12.0))
	_check("it asks to check the connection and names no address", _text_in("LoadingTrouble").contains("Unable to connect") and not _text_in("LoadingTrouble").contains("127.0.0.1"), _text_in("LoadingTrouble"))
	_check("Try again is offered, and no server address", _shown("TryAgainButton") and not _shown("ServerAddressButton"))
	_check("still no login form", not _has("AuthPanel") and _main.loading())
	await _wait(0.6)
	await _shot("3-no-server")
	# Players cannot change the address; a developer starts the app with --server. As that would:
	Game.set_server_url(_url())
	await _tap(_node("TryAgainButton"))
	_check("the new address is used", Game.server_url == _url(), Game.server_url)
	_check("and waited for again", await _until(func() -> bool: return not _node("LoadingTrouble").visible, 2.0) and _main.loading())
	_check("nothing there either: said again", await _until(func() -> bool: return _shown("LoadingTrouble"), 12.0), _text_in("LoadingTrouble"))

	# ---------- the server comes up: the screen moves on by itself ----------
	_start_server(["--fresh"])
	_check("the test server started", await _wait_for_server())
	_check("the login form follows by itself", await _until(func() -> bool: return not _main.loading() and _shown("AuthPanel"), 10.0))
	_check("it was the only screen before the form", _screens == ["loading", "Home"], str(_screens))
	await _wait(0.4)
	await _shot("4-login-form")

	# ---------- a fresh login: the menu waits for the game connection ----------
	var tag := "%d%04d" % [int(Time.get_unix_time_from_system()) % 1000000, randi() % 10000]
	var username := "lt_" + tag
	var r: Dictionary = await Game.register(username, "93%08d" % (randi() % 100000000), PASSWORD)
	_check("registered", r.ok, str(r.get("error", "")))
	_check("logging in shows the loading screen, not the menu", _main.loading() and not _has("MenuPanel"))
	_check("it welcomes the player once connected", await _until(func() -> bool: return _text("LoadingStatus") == "Welcome, %s!" % username, 8.0), _text("LoadingStatus"))
	await _shot("5-welcome")
	_check("then the menu", await _until(func() -> bool: return _shown("MenuPanel"), 5.0))
	_check("which says Online", _text("StatusLabel") == "Online", _text("StatusLabel"))

	# ---------- the app starts again with the saved login ----------
	await _restart_app()
	_check("a saved login opens on the loading screen", _main.loading() and not _has("MenuPanel"))
	_check("it is never asked for again: no login form", not _has("AuthPanel"))
	_check("the server takes it back: welcome back", await _until(func() -> bool: return _text("LoadingStatus") == "Welcome back, %s!" % username, 10.0), _text("LoadingStatus"))
	_check("then the menu, connected", await _until(func() -> bool: return _shown("MenuPanel"), 5.0) and Game.is_online())
	_check("nothing came between", _screens == ["loading", "Home"], str(_screens))

	# ---------- a saved login while the server is away ----------
	_stop_server()
	await _restart_app()
	_check("server away: the logo stays", await _until(func() -> bool: return _shown("LoadingTrouble"), 15.0))
	_check("the login is kept", Game.is_logged_in() and Game.user.get("username") == username)
	_check("and nothing of the game shows", _main.loading() and not _has("MenuPanel") and not _has("AuthPanel"))
	_start_server([])
	_check("the server is back", await _wait_for_server())
	await _tap(_node("TryAgainButton"))
	_check("Try again goes back to waiting", await _until(func() -> bool: return not _node("LoadingTrouble").visible, 2.0))
	_check("and on to the menu, still logged in", await _until(func() -> bool: return _shown("MenuPanel"), 10.0) and Game.user.get("username") == username)

	# ---------- a saved login, and the server has a new address ----------
	Game.server_url = _wrong_url()
	await _restart_app()
	_check("old address: the logo stays", await _until(func() -> bool: return _shown("LoadingTrouble"), 15.0) and Game.is_logged_in())
	Game.set_server_url(_url())
	Game.reconnect()  # the same login, at the new address
	await _tap(_node("TryAgainButton"))
	_check("the new address takes the same login to the menu", await _until(func() -> bool: return _shown("MenuPanel"), 10.0) and Game.user.get("username") == username and Game.server_url == _url())

	# ---------- a saved login while the server cannot check logins ----------
	_set_outage(true)
	await _restart_app()
	await _wait(4.0)
	_check("logins unchecked: still waiting, still logged in", _main.loading() and Game.is_logged_in() and not _has("MenuPanel"))
	_set_outage(false)
	_check("they are checked again: the menu", await _until(func() -> bool: return _shown("MenuPanel"), 10.0) and Game.is_logged_in())

	# ---------- a saved login the server has ended ----------
	Game.token = "not-a-login-the-server-gave"
	await _restart_app()
	_check("an ended login leads to the login form", await _until(func() -> bool: return _shown("AuthPanel"), 10.0) and not Game.is_logged_in())
	_check("with a word why", _notices().contains("log in again"), _notices())
	_check("and no menu on the way", not _screens.has("Home") or _screens == ["loading", "Home"], str(_screens))

	# ---------- back into a game that is still being played ----------
	r = await Game.login(username, PASSWORD)
	_check("logged in again", r.ok, str(r.get("error", "")))
	_check("to the menu", await _until(func() -> bool: return _shown("MenuPanel"), 10.0))
	var other := GameClient.new()
	other.remember_login = false
	other.server_url = _url()
	add_child(other)
	r = await other.register("lu_" + tag, "94%08d" % (randi() % 100000000), PASSWORD)
	_check("a second player is connected", r.ok and await _until(other.is_online), str(r.get("error", "")))
	r = await Game.create_game("points", 2)
	r = await other.join_by_code(str(r.get("roomCode", "")))
	_check("a game is dealt", r.ok and await _until(func() -> bool: return Game.hand().size() == 13 and _has("Table"), 8.0))
	Game.state = {}  # a restarted app knows nothing of the game; the server brings it back
	Game.groups = []
	await _restart_app()
	_check("the app comes back to the table", await _until(func() -> bool: return _has("Table") and not _main.loading(), 10.0))
	_check("straight from the loading screen, the menu never shown", _screens == ["loading", "Table"], str(_screens))
	await _wait(0.6)
	await _shot("6-back-at-the-table")
	Game.leave()
	other.leave()

	_check("no screen with a login came up before the connection was open", _early.is_empty(), str(_early))
	_finish()


# Main again, as when the app is closed and opened: the login stays, the connection starts over.
func _restart_app() -> void:
	if _main != null:
		_main.queue_free()
		await get_tree().process_frame
	Game.socket.close()
	Game.reconnect()
	_open_main()


func _open_main() -> void:
	_screens.clear()
	_main = (load("res://scenes/main.tscn") as PackedScene).instantiate() as Control
	_main.get_node("%Screen").child_entered_tree.connect(_on_screen)
	add_child(_main)


func _on_screen(screen: Node) -> void:
	if screen is LoadingScreen:
		_screens.append("loading")
		return
	_screens.append(str(screen.name))
	if Game.is_logged_in() and not Game.is_online():
		_early.append(str(screen.name))


func _finish() -> void:
	_stop_server()
	_set_outage(false)
	print("loading_tour: %d passed, %d failed" % [_passed, _failed])
	get_tree().quit(1 if _failed > 0 else 0)


# ---------- the server ----------

func _url() -> String:
	return "http://127.0.0.1:%d" % _port


# An address nothing answers at.
func _wrong_url() -> String:
	return "http://127.0.0.1:%d" % (_port + 1)


func _start_server(options: Array) -> void:
	var arguments := PackedStringArray([_server_script, "--port=%d" % _port, "--db=%s" % _database])
	arguments.append("--outage-flag=" + ProjectSettings.globalize_path(OUTAGE_FLAG))
	arguments.append_array(PackedStringArray(options))
	_server_pid = OS.create_process("node", arguments)


func _stop_server() -> void:
	if _server_pid > 0:
		OS.kill(_server_pid)
		_server_pid = -1
	# Gone for good before the test goes on
	var deadline := Time.get_ticks_msec() + 5000
	while Time.get_ticks_msec() < deadline and await _server_answers():
		await _wait(0.2)


func _server_answers(url: String = _url()) -> bool:
	var http := HTTPRequest.new()
	http.timeout = 2.0
	add_child(http)
	var answered := false
	if http.request(url + "/health") == OK:
		var result: Array = await http.request_completed
		answered = result[0] == HTTPRequest.RESULT_SUCCESS and result[1] == 200
	http.queue_free()
	return answered


func _wait_for_server() -> bool:
	var deadline := Time.get_ticks_msec() + int(START_SECONDS * 1000.0)
	while Time.get_ticks_msec() < deadline:
		if await _server_answers():
			return true
		await _wait(0.3)
	return false


# While the flag file exists the server cannot check logins (see test_server.js).
func _set_outage(on: bool) -> void:
	var path := ProjectSettings.globalize_path(OUTAGE_FLAG)
	if on:
		FileAccess.open(path, FileAccess.WRITE).store_string("down")
	elif FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)


# ---------- helpers ----------

func _node(node_name: String) -> Variant:
	return _main.find_child(node_name, true, false)


# Found, and not on its way out with a screen that is being replaced.
func _has(node_name: String) -> bool:
	var node: Node = _node(node_name)
	while node != null and node != _main:
		if node.is_queued_for_deletion():
			return false
		node = node.get_parent()
	return node != null


func _shown(node_name: String) -> bool:
	return _has(node_name) and (_node(node_name) as CanvasItem).is_visible_in_tree()


func _text(node_name: String) -> String:
	return str(_node(node_name).text) if _has(node_name) else ""


func _text_in(node_name: String) -> String:
	var texts: Array[String] = []
	for label: Label in (_node(node_name) as Node).find_children("*", "Label", true, false):
		texts.append(label.text)
	return " | ".join(texts)


func _notices() -> String:
	var texts: Array[String] = []
	for label: Label in Ui.get_node("Notices").find_children("*", "Label", true, false):
		texts.append(label.text)
	return " | ".join(texts)


# Where a control is drawn, scale included, in screen units.
func _box(control: Control) -> Rect2:
	var transform := control.get_global_transform()
	return Rect2(transform.origin, control.size * transform.get_scale())


func _tap(control: Control) -> void:
	var at := get_viewport().get_final_transform() * (control.get_global_transform_with_canvas() * (control.size / 2.0))
	for down: bool in [true, false]:
		var event := InputEventScreenTouch.new()
		event.index = 0
		event.pressed = down
		event.position = at
		Input.parse_input_event(event)
		Input.flush_buffered_events()
		await get_tree().process_frame


func _shot(shot_name: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("%s/%s.png" % [_shots, shot_name])


func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout


func _until(condition: Callable, seconds: float = 8.0) -> bool:
	var deadline := Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < deadline:
		if condition.call():
			return true
		await get_tree().process_frame
	return condition.call()


func _check(what: String, ok: bool, detail: String = "") -> void:
	if ok:
		_passed += 1
		print("ok    %s" % what)
	else:
		_failed += 1
		print("FAIL  %s  %s" % [what, detail])
