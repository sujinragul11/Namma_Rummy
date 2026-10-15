class_name AvatarEditor
extends VBoxContainer
## The player's own profile photo, at the top of Settings: the photo (or the letter) in a big
## circle, with buttons to choose a picture from the phone's gallery or to go back to the
## letter. A chosen picture is first shown the way others will see it; Save sends it.
##
## The picture never leaves the phone as it was taken: make_photo() turns it upright, cuts the
## middle square out of it and makes that a small JPEG, which is all the server gets.
##
## Choosing uses the system's own picker (DisplayServer.file_dialog_show). On Android that is
## the document picker, which shows the gallery and the photo apps; it hands back a content://
## address that FileAccess can read. Godot 4.7 has no picker on iOS, so there the button says so.

const PHOTO_SIZE := 256
const JPEG_QUALITY := 0.85
const LARGEST_FILE := 30 * 1024 * 1024  # a bigger file is not opened at all
const CIRCLE := 108.0
const BROWN := Color("5d4037")
const DIM := Color("8d6e63")
const LINE := Color("e0d3bd")
const TEAL := Color("2bb3a3")
const GREEN := Color("43a047")
const GREY := Color("9e9e9e")
const PICTURES := "*.jpg, *.jpeg, *.png, *.webp ; Pictures"

var _circle: Control
var _hint: Label
var _choose_button: Button
var _remove_button: Button
var _save_button: Button
var _cancel_button: Button
var _preview: ImageTexture  # the picture chosen and made ready, not saved yet
var _preview_jpeg := PackedByteArray()
var _task := -1  # the picture being made ready on another thread
var _task_result: Dictionary = {}
var _saving := false


func _init() -> void:
	name = "AvatarEditor"
	add_theme_constant_override("separation", 10)

	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 20)
	add_child(row)

	_circle = Control.new()
	_circle.name = "AvatarCircle"
	_circle.custom_minimum_size = Vector2(CIRCLE, CIRCLE)
	_circle.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_circle.draw.connect(_draw_circle)
	row.add_child(_circle)

	var side := VBoxContainer.new()
	side.add_theme_constant_override("separation", 6)
	side.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(side)
	var heading := Label.new()
	heading.text = "PROFILE PHOTO"
	heading.add_theme_font_size_override("font_size", 18)
	heading.add_theme_color_override("font_color", DIM)
	side.add_child(heading)
	_hint = Label.new()
	_hint.name = "AvatarHint"
	_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_hint.custom_minimum_size.x = 400.0
	_hint.add_theme_font_size_override("font_size", 18)
	_hint.add_theme_color_override("font_color", BROWN)
	side.add_child(_hint)

	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 12)
	side.add_child(buttons)
	_choose_button = _button(buttons, "Choose photo", "ChoosePhotoButton", _choose)
	_remove_button = _button(buttons, "Remove", "RemovePhotoButton", _ask_remove)
	_save_button = _button(buttons, "Save photo", "SavePhotoButton", _save)
	_cancel_button = _button(buttons, "Cancel", "CancelPhotoButton", _cancel)

	var line := ColorRect.new()
	line.color = LINE
	line.custom_minimum_size = Vector2(0, 2)
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(line)
	set_process(false)


func _ready() -> void:
	Ui.tint_button(_choose_button, TEAL)
	Ui.tint_button(_remove_button, GREY)
	Ui.tint_button(_save_button, GREEN)
	Ui.tint_button(_cancel_button, GREY)
	Game.avatar_loaded.connect(_on_avatar_loaded)
	Game.action_failed.connect(_on_action_failed)
	Game.busy_changed.connect(_refresh)
	Game.profile_changed.connect(_refresh)
	_refresh()


func _exit_tree() -> void:
	if _task >= 0:
		WorkerThreadPool.wait_for_task_completion(_task)
		_task = -1


## Opens a picture (a file path, or the content:// address Android's picker gives) and shows
## it the way it would be saved. The work is done on another thread: a big photo takes a
## moment, and the screen keeps moving meanwhile.
func open_picture(path: String) -> void:
	if _task >= 0:
		return
	var bytes := FileAccess.get_file_as_bytes(path)
	if bytes.is_empty():
		Ui.alert("That picture could not be opened.", "Profile photo")
		return
	if bytes.size() > LARGEST_FILE:
		Ui.alert("That picture is too large. Choose a smaller one.", "Profile photo")
		return
	var result := {}
	_task_result = result
	_task = WorkerThreadPool.add_task(func() -> void: result.merge(AvatarEditor.make_photo(bytes)))
	set_process(true)
	_refresh()


func _process(_delta: float) -> void:
	if _task < 0 or not WorkerThreadPool.is_task_completed(_task):
		return
	WorkerThreadPool.wait_for_task_completion(_task)
	_task = -1
	set_process(false)
	if _task_result.has("error"):
		Ui.alert(str(_task_result.error), "Profile photo")
	else:
		_preview = ImageTexture.create_from_image(_task_result.image)
		_preview_jpeg = _task_result.jpeg
	_refresh()


## Makes the picture a player chose into their profile photo: turned the way the camera was
## held, the middle square cut out (a little above the middle in a tall picture, where a face
## usually is), PHOTO_SIZE pixels a side, as JPEG. Returns {"image", "jpeg"}, or {"error"}
## with a message for the player. Safe to run on another thread.
static func make_photo(bytes: PackedByteArray) -> Dictionary:
	var kind := _kind_of(bytes)
	if kind == "heic":
		return {"error": "Photos saved as HEIC or AVIF cannot be opened here. Choose a JPG or PNG picture, or set the camera to save photos as JPG."}
	var image := Image.new()
	var loaded := ERR_FILE_UNRECOGNIZED
	match kind:
		"jpeg":
			loaded = image.load_jpg_from_buffer(bytes)
		"png":
			loaded = image.load_png_from_buffer(bytes)
		"webp":
			loaded = image.load_webp_from_buffer(bytes)
		"bmp":
			loaded = image.load_bmp_from_buffer(bytes)
	if loaded != OK or image.is_empty():
		return {"error": "That file is not a picture the game can open. Choose a JPG or PNG photo."}
	if image.is_compressed():
		image.decompress()
	image.convert(Image.FORMAT_RGBA8)
	if kind == "jpeg":
		_turn_upright(image, _jpeg_orientation(bytes))

	var width := image.get_width()
	var height := image.get_height()
	var side := mini(width, height)
	var top := int((height - side) * (0.35 if height > width else 0.5))
	image = image.get_region(Rect2i((width - side) / 2, top, side, side))
	# Halving first keeps a big photo smooth when it is made this small
	while image.get_width() >= PHOTO_SIZE * 2:
		image.resize(image.get_width() / 2, image.get_height() / 2, Image.INTERPOLATE_BILINEAR)
	image.resize(PHOTO_SIZE, PHOTO_SIZE, Image.INTERPOLATE_CUBIC)

	# JPEG has no transparency: a see-through picture lies on white
	var flat := Image.create_empty(PHOTO_SIZE, PHOTO_SIZE, false, Image.FORMAT_RGBA8)
	flat.fill(Color.WHITE)
	flat.blend_rect(image, Rect2i(0, 0, PHOTO_SIZE, PHOTO_SIZE), Vector2i.ZERO)
	flat.convert(Image.FORMAT_RGB8)
	return {"image": flat, "jpeg": flat.save_jpg_to_buffer(JPEG_QUALITY)}


# What the first bytes say the file is; "" when it is none of the pictures this knows.
static func _kind_of(bytes: PackedByteArray) -> String:
	if bytes.size() < 12:
		return ""
	if bytes[0] == 0xFF and bytes[1] == 0xD8:
		return "jpeg"
	if bytes[0] == 0x89 and bytes[1] == 0x50 and bytes[2] == 0x4E and bytes[3] == 0x47:
		return "png"
	if bytes.slice(0, 4).get_string_from_ascii() == "RIFF" and bytes.slice(8, 12).get_string_from_ascii() == "WEBP":
		return "webp"
	if bytes[0] == 0x42 and bytes[1] == 0x4D:
		return "bmp"
	if bytes.slice(4, 8).get_string_from_ascii() == "ftyp":
		if bytes.slice(8, 12).get_string_from_ascii() in ["heic", "heix", "hevc", "heim", "heis", "mif1", "msf1", "avif"]:
			return "heic"
	return ""


# How the camera says the picture is to be turned: the EXIF orientation, 1 to 8 (1 = as it
# is stored). A phone held upright usually stores its photo sideways and says 6.
static func _jpeg_orientation(bytes: PackedByteArray) -> int:
	var at := 2
	while at + 4 <= bytes.size():
		if bytes[at] != 0xFF:
			return 1
		var marker := bytes[at + 1]
		if marker == 0xDA or marker == 0xD9:
			return 1  # the picture itself begins: no EXIF before it
		var length := (bytes[at + 2] << 8) | bytes[at + 3]
		if marker == 0xE1 and bytes.slice(at + 4, at + 8).get_string_from_ascii() == "Exif":
			return _tiff_orientation(bytes, at + 10, mini(at + 2 + length, bytes.size()))
		at += 2 + length
	return 1


# The orientation entry (0x0112) of the first directory of the TIFF block in [start, end).
static func _tiff_orientation(bytes: PackedByteArray, start: int, end: int) -> int:
	if start + 8 > end:
		return 1
	var little := bytes[start] == 0x49  # "II"; "MM" is big-endian
	var read := func(at: int, count: int) -> int:
		var value := 0
		for index in count:
			var byte: int = bytes[at + (index if not little else count - 1 - index)]
			value = (value << 8) | byte
		return value
	var directory: int = start + read.call(start + 4, 4)
	if directory + 2 > end:
		return 1
	for index in int(read.call(directory, 2)):
		var entry: int = directory + 2 + index * 12
		if entry + 12 > end:
			return 1
		if read.call(entry, 2) == 0x0112:
			var value: int = read.call(entry + 8, 2)
			return value if value >= 1 and value <= 8 else 1
	return 1


static func _turn_upright(image: Image, orientation: int) -> void:
	match orientation:
		2:
			image.flip_x()
		3:
			image.rotate_180()
		4:
			image.flip_y()
		5:
			image.rotate_90(CLOCKWISE)
			image.flip_x()
		6:
			image.rotate_90(CLOCKWISE)
		7:
			image.rotate_90(CLOCKWISE)
			image.flip_y()
		8:
			image.rotate_90(COUNTERCLOCKWISE)


func _choose() -> void:
	if DisplayServer.has_feature(DisplayServer.FEATURE_NATIVE_DIALOG_FILE):
		# Android's picker filters by kind of file; the desktop ones by name
		var filters := PackedStringArray(["image/*"]) if OS.has_feature("android") else PackedStringArray([PICTURES])
		DisplayServer.file_dialog_show("Choose a photo", "", "", false, DisplayServer.FILE_DIALOG_MODE_OPEN_FILE, filters, _on_picked)
	elif OS.has_feature("mobile"):
		Ui.alert("Choosing a photo from the gallery is not available on this phone yet.", "Profile photo")
	else:
		var dialog := FileDialog.new()
		dialog.access = FileDialog.ACCESS_FILESYSTEM
		dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
		dialog.filters = PackedStringArray([PICTURES])
		dialog.file_selected.connect(open_picture)
		dialog.visibility_changed.connect(func() -> void:
			if not dialog.visible:
				dialog.queue_free())
		add_child(dialog)
		dialog.popup_centered_ratio(0.8)


func _on_picked(chosen: bool, paths: PackedStringArray, _filter: int) -> void:
	if chosen and not paths.is_empty() and is_inside_tree():
		open_picture.call_deferred(paths[0])


func _save() -> void:
	if _preview_jpeg.is_empty() or Game.busy:
		return
	_saving = true
	Game.upload_avatar(_preview_jpeg)
	_refresh()


func _cancel() -> void:
	_preview = null
	_preview_jpeg = PackedByteArray()
	_refresh()


func _ask_remove() -> void:
	Ui.confirm("Profile photo", "Remove your photo? The first letter of your name shows again.", "Remove", Game.remove_avatar)


func _on_avatar_loaded(user_id: String) -> void:
	if user_id != Game.player_id:
		return
	if _saving:
		_saving = false
		_cancel()  # saved: the circle shows the photo as everyone has it now
	_refresh()


func _on_action_failed(_message: String) -> void:
	if _saving:
		_saving = false  # the picture stays on show, to try again
		_refresh()


func _refresh() -> void:
	var previewing := _preview != null
	var has_photo := Game.my_avatar() > 0
	_choose_button.visible = not previewing
	_remove_button.visible = not previewing and has_photo
	_save_button.visible = previewing
	_cancel_button.visible = previewing
	for button: Button in [_choose_button, _remove_button, _save_button, _cancel_button]:
		button.disabled = Game.busy or _task >= 0
	if _task >= 0:
		_hint.text = "Opening the picture..."
	elif _saving:
		_hint.text = "Saving..."
	elif previewing:
		_hint.text = "This is how the other players will see you."
	elif has_photo:
		_hint.text = "The players at your table and your friends see this photo."
	else:
		_hint.text = "Add a photo from your gallery. The players at your table and your friends will see it."
	_circle.queue_redraw()


func _draw_circle() -> void:
	var center := _circle.size / 2.0
	var radius := minf(center.x, center.y) - 4.0
	_circle.draw_circle(center, radius + 4.0, Color.WHITE, true, -1.0, true)
	var photo: Texture2D = _preview if _preview != null else Game.avatar_texture(Game.player_id, Game.my_avatar())
	if photo != null:
		PlayerBadge.draw_photo(_circle, center, radius, photo)
		return
	var username := str(Game.user.get("username", ""))
	var color := PlayerBadge.AVATAR_COLORS[absi(hash(username)) % PlayerBadge.AVATAR_COLORS.size()]
	_circle.draw_circle(center, radius, color, true, -1.0, true)
	var font := Ui.bold_font
	var font_size := int(radius * 1.05)
	var baseline := center.y + (font.get_ascent(font_size) - font.get_descent(font_size)) / 2.0
	_circle.draw_string(font, Vector2(0, baseline), username.substr(0, 1).to_upper(), HORIZONTAL_ALIGNMENT_CENTER, _circle.size.x, font_size, Color.WHITE)


func _button(row: HBoxContainer, text: String, node_name: String, action: Callable) -> Button:
	var button := Button.new()
	button.name = node_name
	button.text = text
	button.custom_minimum_size = Vector2(0, 56)
	button.add_theme_font_size_override("font_size", 22)
	button.pressed.connect(action)
	row.add_child(button)
	return button
