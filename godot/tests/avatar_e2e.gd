extends Node
## Profile photos, through a real server and the real code. A picture is made into a photo on
## the phone (turned upright by its EXIF note, cut square, made small) and saved; another
## player sees it at the table, in the friends list and in a badge; it is replaced, removed,
## saved again from the Settings editor, and goes with a deleted account. The server refuses
## anything that is not a small picture.
##
## Run against a TEST server (it registers throwaway accounts); tests/test_server.js is one:
##   godot --headless --path . res://tests/avatar_e2e.tscn -- --server=http://127.0.0.1:3101 --mute
## The Game autoload plays the second player, since badges and the editor read it.

const PASSWORD := "secret12"

var _passed := 0
var _failed := 0


func _ready() -> void:
	_run()


func _run() -> void:
	# ---------- making the photo, on the phone ----------
	var made := AvatarEditor.make_photo(_halves(600, 300, true).save_png_to_buffer())
	_check("a wide PNG becomes a 256 pixel square JPEG", made.has("jpeg") and made.image.get_size() == Vector2i(256, 256) and made.jpeg[0] == 0xFF and made.jpeg[1] == 0xD8, str(made.get("error", "")))
	_check("its middle square is cut out: red on the left, blue on the right", _is_red(made.image, 40, 128) and _is_blue(made.image, 216, 128))

	# A camera holding the phone upright stores the picture on its side and notes "turn it"
	var sideways := _halves(400, 200, true).save_jpg_to_buffer(0.95)  # red left, blue right
	made = AvatarEditor.make_photo(_with_orientation(sideways, 6, false))
	_check("EXIF 6 is turned clockwise: the red left side ends up on top", _is_red(made.image, 128, 30) and _is_blue(made.image, 128, 226))
	made = AvatarEditor.make_photo(_with_orientation(sideways, 8, true))
	_check("EXIF 8 (written little-endian) is turned the other way: red at the bottom", _is_blue(made.image, 128, 30) and _is_red(made.image, 128, 226))
	made = AvatarEditor.make_photo(_with_orientation(_halves(300, 300, false).save_jpg_to_buffer(0.95), 3, false))
	_check("EXIF 3 is turned upside down", _is_blue(made.image, 128, 30) and _is_red(made.image, 128, 226))
	made = AvatarEditor.make_photo(sideways)
	_check("a JPEG without EXIF stays as it is", _is_red(made.image, 30, 128) and _is_blue(made.image, 226, 128))

	# A tall picture is cut a little above its middle, where a face usually is
	var tall := Image.create_empty(200, 600, false, Image.FORMAT_RGB8)
	tall.fill(Color.BLUE)
	tall.fill_rect(Rect2i(0, 120, 200, 40), Color.RED)  # a red band at 120..160
	made = AvatarEditor.make_photo(tall.save_png_to_buffer())
	_check("a tall picture keeps more of its top", _is_red(made.image, 128, 20), str(made.image.get_pixel(128, 20)) if made.has("image") else "")

	made = AvatarEditor.make_photo("not a picture at all".to_utf8_buffer())
	_check("a file that is no picture is refused with a message", made.get("error", "").begins_with("That file is not a picture"), str(made))
	var heic := PackedByteArray([0, 0, 0, 24]) + "ftypheic".to_ascii_buffer() + PackedByteArray([0, 0, 0, 0])
	made = AvatarEditor.make_photo(heic)
	_check("an iPhone HEIC photo gets its own explanation", str(made.get("error", "")).contains("HEIC"), str(made))

	# ---------- saving it ----------
	var tag := "%d%04d" % [int(Time.get_unix_time_from_system()) % 1000000, randi() % 10000]
	var number := randi() % 10000000
	var a := _new_client()
	var a_name := "pa_" + tag
	var b_name := "pb_" + tag
	var r: Dictionary = await a.register(a_name, "pa_%s@test.local" % tag, "96%08d" % number, PASSWORD)
	_check("A registers, without a photo", r.ok and a.my_avatar() == 0, str(r.get("error", "")))
	Game.remember_login = false
	r = await Game.register(b_name, "pb_%s@test.local" % tag, "86%08d" % number, PASSWORD)
	_check("B (the Game autoload) registers", r.ok, str(r.get("error", "")))
	_check("both are connected", await _until(func() -> bool: return a.is_online() and Game.is_online()))

	var red_photo: Dictionary = AvatarEditor.make_photo(_halves(300, 300, true).save_png_to_buffer())
	r = await a.upload_avatar(red_photo.jpeg)
	_check("A saves a photo: version 1", r.ok and a.my_avatar() == 1 and int(r.data.get("avatar", 0)) == 1, str(r))
	_check("A keeps it without fetching it back", a.avatar_texture(a.player_id, 1) != null)

	r = await a._http(HTTPClient.METHOD_PUT, "/api/user/avatar", "hello".to_utf8_buffer(), "image/jpeg")
	_check("the server refuses bytes that are no picture", not r.ok and r.error == "The picture must be a JPEG or PNG image", r.error)
	r = await a._http(HTTPClient.METHOD_PUT, "/api/user/avatar", Image.create_empty(600, 600, false, Image.FORMAT_RGB8).save_png_to_buffer(), "image/png")
	_check("and a picture bigger than 512 pixels a side", not r.ok and r.error.contains("at most 512 pixels"), r.error)
	var huge := PackedByteArray()
	huge.resize(300 * 1024)
	huge[0] = 0xFF
	huge[1] = 0xD8
	huge[2] = 0xFF
	r = await a._http(HTTPClient.METHOD_PUT, "/api/user/avatar", huge, "image/jpeg")
	_check("and a file larger than 200 KB", not r.ok and r.error == "That picture is too large", r.error)
	r = await a._http(HTTPClient.METHOD_PUT, "/api/user/avatar", red_photo.jpeg, "text/plain")
	_check("and a request that is not a picture", not r.ok and r.error == "No picture was sent", r.error)
	_check("none of that changed the photo", a.my_avatar() == 1 and int((await a.fetch_profile()).data.get("user", {}).get("avatar", 0)) == 1)

	# ---------- others see it ----------
	await a.add_friend(b_name)
	await Game.add_friend(a_name)
	_check("the friends list carries the photo's version", await _until(func() -> bool: return _entry(Game.friends, a.player_id).get("avatar", -1) == 1), str(Game.friends))
	r = await a.create_game("pool", 2)
	r = await Game.join_by_code(str(r.get("roomCode", "")))
	_check("at the table, the state says A has photo 1", r.get("ok", false) and await _until(func() -> bool: return _entry(Game.players(), a.player_id).get("avatar", -1) == 1), str(Game.players()))
	# (A's own copy of the table arrives on its own; wait for it to list B)
	_check("and B has none", await _until(func() -> bool: return _entry(a.players(), Game.player_id).get("avatar", -1) == 0), str(a.players()))

	var badge := PlayerBadge.new()
	add_child(badge)
	badge.show_player(a_name, "", false)
	badge.show_photo(a.player_id, 1)
	_check("a badge shows the photo once it has arrived", await _until(func() -> bool: return badge._photo != null) and badge._photo.get_size() == Vector2(256, 256))
	_check("the photo is kept for the next run", FileAccess.file_exists("%s/%s-1.jpg" % [GameClient.AVATAR_CACHE, a.player_id]))
	var fetched: Image = badge._photo.get_image()
	_check("it is A's red and blue photo", _is_red(fetched, 40, 128) and _is_blue(fetched, 216, 128))

	# ---------- replacing and removing ----------
	var blue := Image.create_empty(300, 300, false, Image.FORMAT_RGB8)
	blue.fill(Color.BLUE)
	r = await a.upload_avatar(AvatarEditor.make_photo(blue.save_png_to_buffer()).jpeg)
	_check("a new photo is version 2", r.ok and a.my_avatar() == 2)
	_check("the table hears of it at once", await _until(func() -> bool: return _entry(Game.players(), a.player_id).get("avatar", -1) == 2))
	_check("so does the friends list", await _until(func() -> bool: return _entry(Game.friends, a.player_id).get("avatar", -1) == 2))
	badge.show_photo(a.player_id, 2)
	_check("the badge changes to the new photo", await _until(func() -> bool: return badge._photo != null and _is_blue(badge._photo.get_image(), 40, 128)))
	_check("and only the new one is kept on disk", FileAccess.file_exists("%s/%s-2.jpg" % [GameClient.AVATAR_CACHE, a.player_id]) and not FileAccess.file_exists("%s/%s-1.jpg" % [GameClient.AVATAR_CACHE, a.player_id]))

	r = await a.remove_avatar()
	_check("A removes the photo", r.ok and a.my_avatar() == 0)
	_check("the table goes back to the letter", await _until(func() -> bool: return _entry(Game.players(), a.player_id).get("avatar", -1) == 0))
	badge.show_photo(a.player_id, 0)
	_check("the badge shows the letter", badge._photo == null)
	r = await Game._http(HTTPClient.METHOD_GET, "/api/avatars/" + a.player_id)
	_check("and the server has no photo to give", not r.ok and r.error == "No photo", r.error)
	r = await a.upload_avatar(red_photo.jpeg)
	# Removing counted as a change too (version 3), so no phone can mistake it for photo 2
	_check("a photo saved after removing one gets a new version, never an old one", r.ok and a.my_avatar() == 4, str(a.my_avatar()))

	var again := _new_client()
	r = await again.login(a_name, PASSWORD)
	_check("logging in tells the app its photo", r.ok and again.my_avatar() == 4, str(again.user.get("avatar")))

	# ---------- the Settings editor ----------
	var path := "user://avatar_test_picture.png"
	_halves(500, 400, false).save_png(path)
	var editor := AvatarEditor.new()
	add_child(editor)
	_check("the editor offers to choose a photo, nothing to remove yet", editor._choose_button.visible and not editor._remove_button.visible and not editor._save_button.visible)
	editor.open_picture(path)
	_check("a chosen picture is made ready on another thread", editor._task >= 0 and editor._hint.text == "Opening the picture...")
	_check("and shown before it is saved", await _until(func() -> bool: return editor._preview != null) and editor._save_button.visible and editor._cancel_button.visible and not editor._choose_button.visible)
	_check("nothing is sent before Save", Game.my_avatar() == 0)
	editor._cancel_button.pressed.emit()
	_check("Cancel puts it away", editor._preview == null and editor._choose_button.visible)
	editor.open_picture(path)
	await _until(func() -> bool: return editor._preview != null)
	editor._save_button.pressed.emit()
	_check("Save sends it", await _until(func() -> bool: return Game.my_avatar() == 1 and editor._preview == null))
	_check("then Remove is offered", editor._remove_button.visible and editor._hint.text.begins_with("The players at your table"), editor._hint.text)
	_check("A's table sees B's photo", await _until(func() -> bool: return _entry(a.players(), Game.player_id).get("avatar", -1) == 1))
	editor.open_picture("user://no_such_picture.png")
	_check("a picture that cannot be read is not opened", editor._task < 0 and editor._preview == null)
	Ui.get_node("MessageBox").hide()

	# ---------- deleting the account ----------
	await a.leave()
	await Game.leave()
	r = await a.delete_account(PASSWORD)
	_check("A deletes the account", r.ok)
	r = await Game._http(HTTPClient.METHOD_GET, "/api/avatars/" + again.player_id)
	_check("and the photo goes with it", not r.ok and r.error == "No photo", r.error)

	Game.logout()
	await get_tree().create_timer(0.3).timeout
	Sound.hush()
	print("\navatar e2e: %d passed, %d failed" % [_passed, _failed])
	get_tree().quit(1 if _failed > 0 else 0)


# A picture in two colours: red on the left (or top) half, blue on the other.
func _halves(width: int, height: int, side_by_side: bool) -> Image:
	var image := Image.create_empty(width, height, false, Image.FORMAT_RGB8)
	image.fill(Color.BLUE)
	image.fill_rect(Rect2i(0, 0, width / 2, height) if side_by_side else Rect2i(0, 0, width, height / 2), Color.RED)
	return image


# Puts an EXIF block saying `orientation` right after the JPEG's start, as a camera does.
func _with_orientation(jpeg: PackedByteArray, orientation: int, little_endian: bool) -> PackedByteArray:
	var tiff: PackedByteArray
	if little_endian:
		tiff = PackedByteArray([0x49, 0x49, 0x2A, 0, 8, 0, 0, 0, 1, 0, 0x12, 0x01, 3, 0, 1, 0, 0, 0, orientation, 0, 0, 0, 0, 0, 0, 0])
	else:
		tiff = PackedByteArray([0x4D, 0x4D, 0, 0x2A, 0, 0, 0, 8, 0, 1, 0x01, 0x12, 0, 3, 0, 0, 0, 1, 0, orientation, 0, 0, 0, 0, 0, 0])
	var body := "Exif".to_ascii_buffer() + PackedByteArray([0, 0]) + tiff
	var length := body.size() + 2
	return jpeg.slice(0, 2) + PackedByteArray([0xFF, 0xE1, length >> 8, length & 0xFF]) + body + jpeg.slice(2)


func _is_red(image: Image, x: int, y: int) -> bool:
	var pixel := image.get_pixel(x, y)
	return pixel.r > 0.7 and pixel.b < 0.3


func _is_blue(image: Image, x: int, y: int) -> bool:
	var pixel := image.get_pixel(x, y)
	return pixel.b > 0.7 and pixel.r < 0.3


func _entry(list: Array, id: String) -> Dictionary:
	for entry: Dictionary in list:
		if str(entry.get("id", "")) == id:
			return entry
	return {}


func _new_client() -> GameClient:
	var client := GameClient.new()
	client.remember_login = false
	add_child(client)
	return client


# Waits until the condition holds, or gives up after `seconds`.
func _until(condition: Callable, seconds: float = 6.0) -> bool:
	var deadline := Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < deadline:
		if condition.call():
			return true
		await get_tree().process_frame
	return condition.call()


func _check(what: String, ok: bool, detail: String = "") -> void:
	if ok:
		_passed += 1
	else:
		_failed += 1
		print("FAIL  %s  %s" % [what, detail])
