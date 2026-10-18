class_name LoadingScreen
extends Control
## The Namma Rummy logo with the four suits hopping under it, shown while the game server is
## reached: when the app starts, until the server has answered and, for a player with a saved
## login, has accepted that login; and for a moment after logging in, until the game connection
## is open. Nothing of the game (the menu, the player's picture and name) shows before that.
##
## At the start it takes over from the engine's boot splash: the same picture at the same size
## and place, so the logo seems to stay and then rise a little to make room for the suits.
## A slow server is explained; one that cannot be reached gets "Try again" (and, in test builds,
## its address). The login is never dropped here: the game connection keeps trying by itself,
## and this screen goes as soon as it gets through.
##
## Main shows it, and puts the next screen in its place when `finished` comes.

signal finished

enum Pose { BOOT, WAITING, TROUBLE }

const FxScript := preload("res://autoload/fx.gd")
const LOGO := preload("res://assets/logo.png")
## Where the boot splash (assets/splash.png, 1280x720, stretch mode "Keep") has the logo: in the
## middle of the window, this tall in a 720-unit-high screen. logo.png is the same picture.
const BOOT_LOGO_HEIGHT := 428.0
## project.godot: application/boot_splash/bg_color
const BOOT_COLOR := Color(0.0705882, 0.247059, 0.0901961)
## The shortest time on screen, so that the logo and the suits are seen rather than flicker past
const FIRST_SECONDS := 1.6  # at the start, the rise from the boot splash included
const LOGIN_SECONDS := 0.6  # after logging in
## Once connected, how long to wait for the first news: the coins, or a table to go back to
const SETTLE_SECONDS := 1.5
## When the wait gets explained, and when "Try again" is offered
const SLOW_SECONDS := 6.0
const GIVE_UP_SECONDS := 20.0
## The public server sleeps when nobody plays and takes up to a minute to wake
const STORE_GIVE_UP_SECONDS := 60.0
## Nothing at that address, or no network: "Try again" comes sooner
const REFUSED_SECONDS := 4.0
const PROBE_EVERY := 2.0
## How long one question to the server may take. The public server can hold it while it wakes;
## a test server on the PC or the local network answers at once or not at all (a closed port
## on Windows does not refuse quickly either: the question just runs out of time).
const PROBE_TIMEOUT := 30.0
const TEST_PROBE_TIMEOUT := 3.0
const SHINE_EVERY := 2.8
const SHINE_SHADER := """
shader_type canvas_item;
// A band of light crosses the picture as `sweep` runs from -0.2 to 1.6
uniform float sweep = -1.0;
void fragment() {
	float band = 1.0 - smoothstep(0.0, 0.09, abs(UV.x + UV.y * 0.35 - sweep));
	COLOR.rgb = mix(COLOR.rgb, vec3(1.0), band * 0.45);
}
"""

## True when shown right after logging in, rather than when the app starts.
var after_login := false

var _elapsed := 0.0
var _waited := 0.0  # since the screen opened or "Try again": what the slow and give-up times count
var _online_at := -1.0  # _elapsed when the game connection opened; -1 while it is not open
var _settled := false  # news has come over the connection since it opened
var _server_answered := false
var _probing := false
var _probe_at := 0.0  # _elapsed at which the server may be asked again
var _refused_since := -1.0  # _waited when connections began to be refused; -1 while they are not
var _leaving := false
var _pose := Pose.WAITING
var _pose_center := Vector2.ZERO  # where the logo's middle is, before it bobs
var _pose_scale := 1.0
var _pose_tween: Tween
var _float_time := 0.0
var _until_twinkle := 1.2
var _until_shine := 1.0

var _cover: ColorRect
var _halo: TextureRect
var _logo: TextureRect
var _shine: ShaderMaterial
var _suits: SuitRow
var _status: Label
var _trouble: PanelContainer
var _trouble_text: Label
var _address_button: Button
var _address_row: HBoxContainer
var _address_edit: LineEdit


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build()
	Game.coins_changed.connect(_on_news)
	Game.state_changed.connect(_on_news)
	resized.connect(_snap_to_pose)

	if after_login:
		_status.text = "Signing you in..."
		_snap_to_pose()
		_place()
		Ui.pop_in(_logo)
		return

	# The first frame is the boot splash itself; then the cloth shows and the logo rises
	_status.text = "Connecting to the game server..."
	_cover.visible = true
	_pose = Pose.BOOT
	_snap_to_pose()
	_place()  # laid out for the very first frame, before any _process
	for faded: CanvasItem in [_halo, _suits, _status]:
		faded.modulate.a = 0.0
	var tween := create_tween().set_parallel()
	tween.tween_property(_cover, "modulate:a", 0.0, 0.6).set_delay(0.1)
	tween.tween_property(_halo, "modulate:a", 1.0, 0.6).set_delay(0.3)
	tween.tween_property(_suits, "modulate:a", 1.0, 0.35).set_delay(0.65)
	tween.tween_property(_status, "modulate:a", 1.0, 0.35).set_delay(0.75)
	tween.chain().tween_callback(_cover.hide)
	_go_to(Pose.WAITING, 0.8, 0.15)


## True once this screen may give way: the server has answered and accepted the login.
func is_done() -> bool:
	if _elapsed < (LOGIN_SECONDS if after_login else FIRST_SECONDS):
		return false
	if Game.is_logged_in():
		return _online_at >= 0.0 and (_settled or _elapsed - _online_at >= SETTLE_SECONDS)
	# The login form needs a server to talk to
	return _server_answered


func _process(delta: float) -> void:
	_elapsed += delta
	_waited += delta
	_float_time += delta

	if Game.is_online():
		if _online_at < 0.0:
			_online_at = _elapsed
	else:
		_online_at = -1.0
		_settled = false

	if not _leaving:
		_ask_server_when_useful()
		if is_done():
			_leave()
		else:
			_explain_the_wait()
	_animate(delta)
	_place()


func _build() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP  # nothing behind it takes a tap meanwhile

	# The boot splash's colour over everything for the first moment, up to the window's edges
	_cover = ColorRect.new()
	_cover.color = BOOT_COLOR
	_cover.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_cover.visible = false
	add_child(_cover)

	# A soft light behind the logo
	var gradient := Gradient.new()
	gradient.set_color(0, Color(1.0, 0.96, 0.8, 0.2))
	gradient.set_color(1, Color(1.0, 0.96, 0.8, 0.0))
	var light := GradientTexture2D.new()
	light.gradient = gradient
	light.fill = GradientTexture2D.FILL_RADIAL
	light.fill_from = Vector2(0.5, 0.5)
	light.fill_to = Vector2(1.0, 0.5)
	_halo = TextureRect.new()
	_halo.texture = light
	_halo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_halo.stretch_mode = TextureRect.STRETCH_SCALE
	_halo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_halo)

	_logo = TextureRect.new()
	_logo.name = "LoadingLogo"
	_logo.texture = LOGO
	_logo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_logo.stretch_mode = TextureRect.STRETCH_SCALE
	_logo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_logo.size = LOGO.get_size() * (BOOT_LOGO_HEIGHT / LOGO.get_size().y)
	_logo.pivot_offset = _logo.size / 2.0
	var shader := Shader.new()
	shader.code = SHINE_SHADER
	_shine = ShaderMaterial.new()
	_shine.shader = shader
	_logo.material = _shine
	add_child(_logo)
	_halo.size = _logo.size * Vector2(1.5, 1.7)
	_halo.pivot_offset = _halo.size / 2.0
	move_child(_halo, _logo.get_index())

	_suits = SuitRow.new()
	add_child(_suits)

	_status = Label.new()
	_status.name = "LoadingStatus"
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status.add_theme_font_size_override("font_size", 22)
	_status.add_theme_color_override("font_color", Ui.PALE_GREEN)
	add_child(_status)

	_build_trouble()


# The box that says the server cannot be reached, with "Try again".
func _build_trouble() -> void:
	_trouble = PanelContainer.new()
	_trouble.name = "LoadingTrouble"
	_trouble.visible = false
	add_child(_trouble)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 14)
	_trouble.add_child(column)

	var title := Label.new()
	title.text = "Can't reach the game server"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_override("font", Ui.bold_font)
	title.add_theme_font_size_override("font_size", 28)
	title.add_theme_color_override("font_color", Ui.GOLD)
	column.add_child(title)

	_trouble_text = Label.new()
	_trouble_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_trouble_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_trouble_text.custom_minimum_size.x = 560  # wrapped at a known width from the start
	_trouble_text.add_theme_font_size_override("font_size", 21)
	column.add_child(_trouble_text)

	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	buttons.add_theme_constant_override("separation", 16)
	column.add_child(buttons)
	var retry := Button.new()
	retry.name = "TryAgainButton"
	retry.text = "Try again"
	retry.custom_minimum_size = Vector2(200, 60)
	Ui.tint_button(retry, Ui.PRIMARY)
	retry.pressed.connect(_on_try_again)
	buttons.add_child(retry)
	# Test builds talk to a PC on the same network, whose address can change
	_address_button = Button.new()
	_address_button.name = "ServerAddressButton"
	_address_button.text = "Server address"
	_address_button.custom_minimum_size = Vector2(200, 60)
	_address_button.visible = not Config.store_build
	_address_button.pressed.connect(_on_address_button)
	buttons.add_child(_address_button)

	_address_row = HBoxContainer.new()
	_address_row.add_theme_constant_override("separation", 12)
	_address_row.visible = false
	column.add_child(_address_row)
	_address_edit = LineEdit.new()
	_address_edit.name = "ServerAddressEdit"
	_address_edit.placeholder_text = "http://192.168.1.5:3001"
	_address_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_address_edit.custom_minimum_size.y = 60
	_address_edit.text_submitted.connect(_on_address_entered.unbind(1))
	_address_row.add_child(_address_edit)
	var connect := Button.new()
	connect.name = "ServerAddressConnect"
	connect.text = "Connect"
	connect.custom_minimum_size = Vector2(150, 60)
	Ui.tint_button(connect, Ui.BLUE)
	connect.pressed.connect(_on_address_entered)
	_address_row.add_child(connect)

	var note := Label.new()
	note.text = "Still trying in the background: the game opens by itself once the server answers."
	note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.custom_minimum_size.x = 560
	note.add_theme_font_size_override("font_size", 18)
	note.add_theme_color_override("font_color", Color(Ui.PALE_GREEN, 0.75))
	column.add_child(note)


# Without a login, the server's answer is what this screen waits for. With one, the game
# connection is the test; asking the server as well only tells why that is slow.
func _ask_server_when_useful() -> void:
	if _probing or _elapsed < _probe_at or _server_answered:
		return
	if Game.is_logged_in() and (_online_at >= 0.0 or _waited < 2.0):
		return
	_probing = true
	var http := HTTPRequest.new()
	http.timeout = PROBE_TIMEOUT if Config.store_build else TEST_PROBE_TIMEOUT
	add_child(http)
	var url := Game.server_url
	http.request_completed.connect(_on_server_answer.bind(http, url))
	if http.request(url + "/health") != OK:
		_on_server_answer(HTTPRequest.RESULT_CANT_CONNECT, 0, PackedStringArray(), PackedByteArray(), http, url)


func _on_server_answer(result: int, code: int, _headers: PackedStringArray, _body: PackedByteArray, http: HTTPRequest, url: String) -> void:
	http.queue_free()
	_probing = false
	_probe_at = _elapsed + PROBE_EVERY
	if url != Game.server_url:
		_probe_at = _elapsed  # the address was changed meanwhile: ask the new one at once
		return
	var waking := result == HTTPRequest.RESULT_TIMEOUT and Config.store_build
	if result == HTTPRequest.RESULT_SUCCESS and code >= 200 and code < 300:
		_server_answered = true
		_refused_since = -1.0
	elif result == HTTPRequest.RESULT_SUCCESS or waking:
		_refused_since = -1.0  # something is there, only slow or not ready yet
	elif _refused_since < 0.0:
		# (a question that ran out of time was refused from when it was asked)
		_refused_since = maxf(0.0, _waited - TEST_PROBE_TIMEOUT) if result == HTTPRequest.RESULT_TIMEOUT else _waited


# Words for a wait that goes on, and "Try again" for one that will not end by itself soon.
func _explain_the_wait() -> void:
	if _pose == Pose.TROUBLE:
		return
	var give_up := STORE_GIVE_UP_SECONDS if Config.store_build else GIVE_UP_SECONDS
	var refused := _refused_since >= 0.0 and _waited - _refused_since >= REFUSED_SECONDS
	if _waited >= give_up or refused:
		_show_trouble()
	elif _waited >= SLOW_SECONDS and _pose == Pose.WAITING:
		if Config.store_build:
			_status.text = "Waking up the game server. This can take up to a minute..."
		else:
			_status.text = "Still connecting to %s..." % Game.server_url


func _show_trouble() -> void:
	if Config.store_build:
		_trouble_text.text = "Check that your phone is connected to the internet."
	elif OS.has_feature("mobile"):
		_trouble_text.text = "Nothing answers at %s.\nConnect this phone to the same Wi-Fi or hotspot as the PC that runs the game server, or change the address." % Game.server_url
	else:
		_trouble_text.text = "Nothing answers at %s.\nCheck that the game server is running (npm run dev in the backend folder)." % Game.server_url
	_address_row.visible = false
	_trouble.reset_size()
	_go_to(Pose.TROUBLE, 0.5)
	_trouble.visible = true
	_trouble.modulate.a = 0.0
	var tween := create_tween().set_parallel()
	tween.tween_property(_trouble, "modulate:a", 1.0, 0.3).set_delay(0.2)
	tween.tween_property(_suits, "modulate:a", 0.0, 0.2)
	tween.tween_property(_status, "modulate:a", 0.0, 0.2)
	Sound.play("warning")


func _on_try_again() -> void:
	_waited = 0.0
	_refused_since = -1.0
	_server_answered = false
	_probe_at = _elapsed
	_status.text = "Connecting to the game server..."
	_go_to(Pose.WAITING, 0.5)
	var tween := create_tween().set_parallel()
	tween.tween_property(_trouble, "modulate:a", 0.0, 0.2)
	tween.tween_property(_suits, "modulate:a", 1.0, 0.3).set_delay(0.2)
	tween.tween_property(_status, "modulate:a", 1.0, 0.3).set_delay(0.2)
	tween.chain().tween_callback(_trouble.hide)


func _on_address_button() -> void:
	_address_row.visible = not _address_row.visible
	_trouble.reset_size()
	if _address_row.visible:
		_address_edit.text = Game.server_url
		_address_edit.grab_focus()


func _on_address_entered() -> void:
	Game.set_server_url(_address_edit.text)
	_address_edit.release_focus()
	if Game.is_logged_in():
		Game.reconnect()  # the same login, at the new address
	_on_try_again()


func _on_news() -> void:
	if Game.is_online():
		_settled = true


func _leave() -> void:
	_leaving = true
	var tween := create_tween()
	if Game.is_logged_in():
		_status.text = ("Welcome, %s!" if after_login else "Welcome back, %s!") % str(Game.user.get("username", ""))
		_status.add_theme_color_override("font_color", Ui.GOLD)
		_status.modulate.a = 1.0
		_suits.modulate.a = 1.0
		Ui.pulse(_status, 1.08)
		tween.tween_interval(0.45)
	tween.set_parallel()
	tween.tween_property(self, "modulate:a", 0.0, 0.35).set_trans(Tween.TRANS_SINE)
	tween.tween_property(self, "_pose_scale", _pose_scale * 1.08, 0.35).set_trans(Tween.TRANS_SINE)
	tween.chain().tween_callback(finished.emit)


func _go_to(pose: Pose, seconds: float, delay: float = 0.0) -> void:
	_pose = pose
	if _pose_tween != null:
		_pose_tween.kill()
	var target := _pose_target(pose)
	_pose_tween = create_tween().set_parallel().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	_pose_tween.tween_property(self, "_pose_center", target[0], seconds).set_delay(delay)
	_pose_tween.tween_property(self, "_pose_scale", target[1], seconds).set_delay(delay)


func _snap_to_pose() -> void:
	if _leaving:
		return
	if _pose_tween != null:
		_pose_tween.kill()
	var target := _pose_target(_pose)
	_pose_center = target[0]
	_pose_scale = target[1]
	# The cover reaches past the safe area this screen lies in, to the window's edges
	_cover.position = -global_position
	_cover.size = get_viewport().get_visible_rect().size


# [the logo's middle, its scale] for a pose, in this screen's units.
func _pose_target(pose: Pose) -> Array:
	match pose:
		Pose.BOOT:
			return [get_viewport().get_visible_rect().size / 2.0 - global_position, 1.0]
		Pose.TROUBLE:
			return [Vector2(size.x / 2.0, size.y * 0.2), 0.5]
	return [Vector2(size.x / 2.0, size.y * 0.38), 0.78]


func _animate(delta: float) -> void:
	# A glint crosses the logo now and then, and a sparkle catches it
	_until_shine -= delta
	if _until_shine <= 0.0:
		_until_shine = SHINE_EVERY
		# (through a method: without a renderer, as in the headless tests, the parameter is no property)
		create_tween().tween_method(_set_shine, -0.2, 1.6, 0.9).set_trans(Tween.TRANS_SINE)
	_until_twinkle -= delta
	if _until_twinkle <= 0.0 and not _leaving and _pose != Pose.BOOT:
		_until_twinkle = randf_range(1.0, 2.2)
		var spot := Vector2(randf_range(-0.35, 0.35), randf_range(-0.25, 0.1)) * _logo.size * _pose_scale
		Fx.sparkle(global_position + _pose_center + spot, Fx.GOLD, 5)


func _set_shine(sweep: float) -> void:
	_shine.set_shader_parameter("sweep", sweep)


# The logo bobs and breathes gently around its pose; the rest is laid out under it.
func _place() -> void:
	var breathe := 1.0 + 0.012 * sin(_float_time * 2.2)
	var center := _pose_center + Vector2(0.0, sin(_float_time * 1.6) * 5.0 * _pose_scale)
	_logo.scale = Vector2.ONE * _pose_scale * breathe
	_logo.position = center - _logo.size / 2.0
	_halo.scale = Vector2.ONE * _pose_scale * (1.0 + 0.04 * sin(_float_time * 1.3))
	_halo.position = center - _halo.size / 2.0

	_suits.position = Vector2((size.x - _suits.size.x) / 2.0, size.y * 0.66)
	_status.position = Vector2(0.0, _suits.position.y + _suits.size.y + 12.0)
	_status.size.x = size.x

	# On a phone, the keyboard for the server address covers the lower half: the box moves up
	var keyboard := DisplayServer.has_feature(DisplayServer.FEATURE_VIRTUAL_KEYBOARD) and DisplayServer.virtual_keyboard_get_height() > 0
	_logo.visible = not keyboard
	_halo.visible = not keyboard
	_trouble.position = Vector2((size.x - _trouble.size.x) / 2.0, 12.0 if keyboard else size.y * 0.37)


## The four suits in a row, each hopping in turn: the loading animation.
class SuitRow extends Control:
	const KINDS: Array[FxScript.Kind] = [FxScript.Kind.SPADE, FxScript.Kind.HEART, FxScript.Kind.CLUB, FxScript.Kind.DIAMOND]
	const RED := Color("ff6b6b")
	const CREAM := Color("f7eed9")
	const GAP := 56.0
	const RADIUS := 15.0
	const HOP := 20.0
	const CYCLE := 1.15  # seconds from one suit's hop to its next
	const BEAT := 0.15  # seconds between one suit's hop and its neighbour's
	const HOP_SECONDS := 0.42

	var _time := 0.0
	var _layer: FxScript.Layer

	func _init() -> void:
		name = "LoadingSuits"
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		size = Vector2(GAP * KINDS.size(), HOP + RADIUS * 2.0 + 14.0)
		_layer = FxScript.Layer.new()
		add_child(_layer)
		for kind in KINDS:
			var suit := FxScript.Piece.new()
			suit.kind = kind
			suit.life = 1.0  # never ages: it stays fully drawn
			suit.color = RED if kind in [FxScript.Kind.HEART, FxScript.Kind.DIAMOND] else CREAM
			_layer.pieces.append(suit)

	func _process(delta: float) -> void:
		_time += delta
		var ground := size.y - RADIUS - 10.0
		for index in _layer.pieces.size():
			var suit: FxScript.Piece = _layer.pieces[index]
			var lift := _lift(index)
			suit.position = Vector2(GAP * (index + 0.5), ground - lift * HOP)
			suit.size = RADIUS * (1.0 + 0.2 * lift)
		_layer.queue_redraw()
		queue_redraw()

	# Shadows on the cloth, smaller while their suit is in the air.
	func _draw() -> void:
		var ground := size.y - 6.0
		for index in _layer.pieces.size():
			var lift := _lift(index)
			draw_set_transform(Vector2(GAP * (index + 0.5), ground), 0.0, Vector2(1.0, 0.3))
			draw_circle(Vector2.ZERO, RADIUS * (1.0 - 0.35 * lift), Color(0, 0, 0, 0.28 * (1.0 - 0.5 * lift)), true, -1.0, true)
		draw_set_transform(Vector2.ZERO)

	# 0 on the ground, 1 at the top of the hop.
	func _lift(index: int) -> float:
		var t := fposmod(_time - index * BEAT, CYCLE)
		return sin(t / HOP_SECONDS * PI) if t < HOP_SECONDS else 0.0
