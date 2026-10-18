class_name TableThrows
extends Control
## Things to throw at another player's picture: an aruval, a cake, a ghost, a tomato...
## A small round button sits beside each opponent's badge. It opens a choice of items, and the
## chosen one flies from the thrower's picture to that player's and plays its own little scene
## there: the cake is eaten, the knife pokes, the aruval cuts, the ghost says boo. Everyone at
## the table sees it, because the server passes every throw to the whole table (see
## GameClient.throw_item); the thrower sees it when it comes back, like the others.
##
## Like TableChat this layer lets every tap through except those on its own buttons and the
## open choice, never makes the game busy and waits for nothing. Effects are drawn in code or
## with the pictures in res://assets/throw, run on tweens that die with their nodes, and are
## freed the moment they end. The table gives it `badge_of` to find each player's badge.

## The choice of items opened; the table closes the chat panels then.
signal picker_opened

const BUTTON_SIZE := 46.0
const SMALL_BUTTON := 36.0  # at a crowded table, on the corner of the player's own picture
const BUTTON_GAP := 8.0
const ICON_SECONDS := 3.0  # the buttons show another item every so often
const TILE := 60.0
const COLUMNS := 5
const EDGE := 12.0  # the choice keeps this far from the screen's edges
const ITEM_SIZE := 72.0  # an item in flight, at full size
const MAX_SHOWN := 6  # throws playing at once; one more is skipped, not kept for later
const PANEL_COLOR := Color(0.05, 0.19, 0.07, 0.95)
## Where the hand is on each picture (in pixels of the 128-pixel picture): an aruval or a
## hammer swings round it.
const ARUVAL_GRIP := Vector2(35, 98)
const HAMMER_GRIP := Vector2(104, 106)
## Where the fuse burns, measured from the middle of the picture.
const BOMB_FUSE := Vector2(26, -46)
const CRACKER_FUSE := Vector2(34, -42)
const SPARK_COLORS: Array[Color] = [Color("ff5252"), Color("ffd740"), Color("69f0ae"), Color("40c4ff"), Color("ff4081"), Color("ffffff")]

## Where a player sits: takes a user id and returns their PlayerBadge, or null when they have
## no seat on screen.
var badge_of := Callable()
## What the buttons must never cover: returns the Controls a player taps or reads during a turn
## (the piles, the hand, the action buttons...).
var keep_clear := Callable()

var _pictures: Dictionary = {}  # item or effect name -> Texture2D
var _buttons: Dictionary = {}  # opponent id -> the round button beside their badge
var _picker: PanelContainer
var _picker_title: Label
var _target := ""  # whom the open choice throws at; "" while it is closed
var _icon := 0  # which item the buttons show
var _icon_clock := 0.0
var _shown := 0  # throws playing now
var _aimed_at: Dictionary = {}  # user id -> how many throws are playing on their picture


func _ready() -> void:
	name = "TableThrows"
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	for item: String in GameClient.THROWABLES:
		_pictures[item] = load("res://assets/throw/%s.%s" % [item, "svg" if item == "aruval" else "png"])
	for effect: String in ["boom", "dizzy", "yum", "scream", "drops", "sparkles", "heart", "cold", "hot", "rich", "proud", "dazed", "love", "shock", "sweat"]:
		_pictures[effect] = load("res://assets/throw/fx_%s.png" % effect)
	_picker = _build_picker()
	add_child(_picker)
	Game.item_thrown.connect(_on_item_thrown)


## Closes the choice of items (the back button does this too).
func close() -> void:
	if _target.is_empty():
		return
	_target = ""
	var tween := _picker.create_tween().set_parallel()
	tween.tween_property(_picker, "modulate:a", 0.0, 0.12)
	tween.tween_property(_picker, "scale", Vector2(0.92, 0.92), 0.12)
	tween.chain().tween_callback(_picker.hide)
	if is_in_group(FriendsPanel.BACK_GROUP):
		remove_from_group(FriendsPanel.BACK_GROUP)


func is_picker_open() -> bool:
	return not _target.is_empty()


## The player the open choice throws at, "" while it is closed.
func target() -> String:
	return _target


func _process(delta: float) -> void:
	_icon_clock += delta
	if _icon_clock >= ICON_SECONDS:
		_icon_clock = 0.0
		_icon = (_icon + 1) % GameClient.THROWABLES.size()
	_place_buttons()
	if not _target.is_empty():
		# Another panel opened over the table (the chat, a menu): this one makes way
		for panel: Node in get_tree().get_nodes_in_group(FriendsPanel.BACK_GROUP):
			if panel != self:
				close()
				break


# A button beside every opponent while a round is being played: on the side of the badge that
# faces the middle of the table, unless another badge is in the way there.
func _place_buttons() -> void:
	var present := {}
	var playing := Game.status() == "playing"
	var seats: Array[Rect2] = []
	for player: Dictionary in Game.players():
		var badge := _badge(str(player.get("id", "")))
		if badge != null:
			seats.append(_local_rect(badge.get_global_rect()))
	var controls: Array[Rect2] = []
	if keep_clear.is_valid() and playing:
		for control: Variant in keep_clear.call():
			if control is Control and is_instance_valid(control) and (control as Control).is_visible_in_tree():
				controls.append(_local_rect((control as Control).get_global_rect()))
	for player: Dictionary in Game.players():
		var id := str(player.get("id", ""))
		if id == Game.player_id or id.is_empty():
			continue
		var badge := _badge(id)
		if badge == null or not playing or player.get("left", false):
			continue
		var own := _local_rect(badge.get_global_rect())
		var spot := _button_spot(own, _to_local(badge.avatar_center()), badge.picture().size.x / 2.0, seats, controls)
		if not spot.has_area():
			continue  # nowhere to put it without covering the game: no button rather than in the way
		present[id] = true
		var button: Button = _buttons.get(id)
		if button == null:
			button = _make_button(id)
			_buttons[id] = button
		button.position = spot.position
		if button.size != spot.size:
			button.custom_minimum_size = spot.size
			button.size = spot.size
		seats.append(spot)  # the next button keeps clear of it
		var icon: Texture2D = _pictures[GameClient.THROWABLES[_icon]]
		if button.icon != icon:
			button.icon = icon
	for id: String in _buttons.keys():
		if not present.has(id):
			_buttons[id].queue_free()
			_buttons.erase(id)
			if id == _target:
				close()


# Where the button goes, as a rectangle. It tries beside the badge toward the middle, beside it
# on the other side, under and over the picture, under and over the name, and takes the first
# place on the screen that is clear of every badge, of the buttons placed before it (all in
# `seats`) and of the game's own controls. At a crowded table there may be no such place: then
# a smaller button sits on the lower corner of the player's own picture, if that corner is clear
# of everything else. Failing that, an empty rectangle.
func _button_spot(rect: Rect2, middle: Vector2, radius: float, seats: Array[Rect2], controls: Array[Rect2]) -> Rect2:
	var full := Vector2(BUTTON_SIZE, BUTTON_SIZE)
	var half := BUTTON_SIZE / 2.0
	var right := Vector2(rect.end.x + BUTTON_GAP, middle.y - half)
	var left := Vector2(rect.position.x - BUTTON_GAP - BUTTON_SIZE, middle.y - half)
	var spots: Array[Rect2] = []
	for spot: Vector2 in ([right, left] if rect.get_center().x <= size.x / 2.0 + 1.0 else [left, right]):
		spots.append(Rect2(spot, full))
	for x: float in [middle.x - half, rect.get_center().x - half]:
		spots.append(Rect2(Vector2(x, rect.end.y + BUTTON_GAP), full))
		spots.append(Rect2(Vector2(x, rect.position.y - BUTTON_GAP - BUTTON_SIZE), full))
	var small := Vector2(SMALL_BUTTON, SMALL_BUTTON)
	var corner := middle + Vector2(radius, radius) * 0.7 - small * 0.35
	spots.append(Rect2(corner, small))  # over the picture's corner, so its own badge is no obstacle
	var screen := Rect2(Vector2(EDGE, EDGE), size - Vector2(EDGE, EDGE) * 2.0)
	for spot: Rect2 in spots:
		var on_own_badge := spot.size == small
		if not screen.encloses(spot):
			continue
		if controls.any(func(control: Rect2) -> bool: return control.intersects(spot)):
			continue
		if seats.any(func(seat: Rect2) -> bool: return seat.intersects(spot) and not (on_own_badge and seat == rect)):
			continue
		return spot
	return Rect2()


func _make_button(id: String) -> Button:
	var button := Button.new()
	button.name = "ThrowButton_" + id
	button.tooltip_text = "Throw something"
	button.focus_mode = Control.FOCUS_NONE
	button.size = Vector2(BUTTON_SIZE, BUTTON_SIZE)
	button.custom_minimum_size = button.size
	button.expand_icon = true
	button.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	for state_name: String in ["normal", "hover", "pressed"]:
		var shade := {"normal": 0.0, "hover": 0.1, "pressed": 0.2}[state_name] as float
		var style := Ui.box(PANEL_COLOR.lightened(shade), int(BUTTON_SIZE / 2.0), 7, 7)
		style.border_color = Ui.GOLD.darkened(0.15)
		style.set_border_width_all(2)
		style.shadow_color = Color(0, 0, 0, 0.3)
		style.shadow_size = 4
		button.add_theme_stylebox_override(state_name, style)
	button.pressed.connect(_on_button.bind(id))
	add_child(button)
	move_child(button, _picker.get_index())  # under the choice when it opens
	return button


# ---------- the choice of items ----------

func _build_picker() -> PanelContainer:
	var panel := PanelContainer.new()
	panel.name = "ThrowPicker"
	panel.visible = false
	var style := Ui.box(PANEL_COLOR, 20, 14, 12)
	style.border_color = Ui.GOLD.darkened(0.3)
	style.set_border_width_all(2)
	style.shadow_color = Color(0, 0, 0, 0.4)
	style.shadow_size = 12
	panel.add_theme_stylebox_override("panel", style)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	panel.add_child(column)
	_picker_title = Label.new()
	_picker_title.add_theme_font_override("font", Ui.bold_font)
	_picker_title.add_theme_font_size_override("font_size", 19)
	_picker_title.add_theme_color_override("font_color", Ui.GOLD)
	_picker_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_picker_title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	column.add_child(_picker_title)

	var grid := GridContainer.new()
	grid.columns = COLUMNS
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	column.add_child(grid)
	for item: String in GameClient.THROWABLES:
		var tile := Button.new()
		tile.name = "Throw_" + item
		tile.tooltip_text = item.capitalize()
		tile.icon = _pictures[item]
		tile.expand_icon = true
		tile.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		tile.custom_minimum_size = Vector2(TILE, TILE)
		tile.focus_mode = Control.FOCUS_NONE
		for state_name: String in ["normal", "hover", "pressed"]:
			var shade := {"normal": 0.08, "hover": 0.16, "pressed": 0.26}[state_name] as float
			tile.add_theme_stylebox_override(state_name, Ui.box(Color(1, 1, 1, shade), 14, 7, 7))
		tile.pressed.connect(_on_tile.bind(item))
		grid.add_child(tile)
	return panel


func _on_button(id: String) -> void:
	if id == _target:
		close()
		return
	_target = id
	_picker_title.text = "Throw at %s" % Game.player_name(id)
	_picker.reset_size()
	var panel_size := _picker.get_combined_minimum_size()
	_picker.size = panel_size
	# Beside the button, toward the middle of the table, and inside the screen
	var button: Button = _buttons[id]
	var at := Vector2(button.position.x + button.size.x / 2.0 - panel_size.x / 2.0, button.position.y + button.size.y + 10.0)
	if at.y + panel_size.y > size.y - EDGE:
		at.y = button.position.y - panel_size.y - 10.0
	_picker.position = at.clamp(Vector2(EDGE, EDGE), (size - panel_size - Vector2(EDGE, EDGE)).max(Vector2(EDGE, EDGE)))
	_picker.pivot_offset = (button.position + button.size / 2.0 - _picker.position).clamp(Vector2.ZERO, panel_size)
	_picker.visible = true
	_picker.modulate.a = 0.0
	_picker.scale = Vector2(0.85, 0.85)
	var tween := _picker.create_tween().set_parallel()
	tween.tween_property(_picker, "modulate:a", 1.0, 0.15)
	tween.tween_property(_picker, "scale", Vector2.ONE, 0.2).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	if not is_in_group(FriendsPanel.BACK_GROUP):
		add_to_group(FriendsPanel.BACK_GROUP)  # the back button closes it, not the table
	picker_opened.emit()


func _on_tile(item: String) -> void:
	var target_id := _target
	close()
	if not target_id.is_empty():
		Game.throw_item(target_id, item)


# A tap anywhere else closes the choice, and still does what it was meant for: it is not taken.
func _input(event: InputEvent) -> void:
	if _target.is_empty():
		return
	var at := Vector2.INF
	if event is InputEventScreenTouch and event.pressed:
		at = event.position
	elif event is InputEventMouseButton and event.pressed:
		at = event.position
	if at == Vector2.INF:
		return
	if _picker.get_global_rect().has_point(at):
		return
	for button: Button in _buttons.values():
		if button.get_global_rect().has_point(at):
			return  # the buttons open and close it themselves
	close()


# ---------- a throw arrives ----------

func _on_item_thrown(toss: Dictionary) -> void:
	var item := str(toss.get("item", ""))
	var to_id := str(toss.get("to", ""))
	var target_badge := _badge(to_id)
	if target_badge == null or not _pictures.has(item) or _shown >= MAX_SHOWN or not is_visible_in_tree():
		return
	var from_badge := _badge(str(toss.get("from", "")))
	var from := _to_local(from_badge.avatar_center()) if from_badge != null else Vector2(size.x / 2.0, size.y - 60.0)
	var picture := target_badge.picture()
	var to := _to_local(target_badge.avatar_center())
	var radius := picture.size.x / 2.0

	var show := Toss.new()
	show.name = "Toss_%s" % str(toss.get("id", randi()))
	show.layer = self
	show.item = item
	show.from = from
	show.to = to
	show.radius = radius
	show.picture = picture
	add_child(show)
	_shown += 1
	_aimed_at[to_id] = int(_aimed_at.get(to_id, 0)) + 1
	show.tree_exiting.connect(_on_toss_done.bind(to_id, picture))
	Sound.play("whoosh", -4.0, randf_range(0.9, 1.15))
	show.play()


func _on_toss_done(to_id: String, picture: Control) -> void:
	_shown -= 1
	_aimed_at[to_id] = int(_aimed_at.get(to_id, 1)) - 1
	if int(_aimed_at[to_id]) <= 0:
		_aimed_at.erase(to_id)
		# Nothing else is playing on this picture: make sure it is as it was
		if is_instance_valid(picture) and picture.is_inside_tree():
			if picture.has_meta("throw_tween"):
				(picture.get_meta("throw_tween") as Tween).kill()
			if picture.has_meta("throw_tint"):
				(picture.get_meta("throw_tint") as Tween).kill()
			var settle := picture.create_tween().set_parallel()
			settle.tween_property(picture, "scale", Vector2.ONE, 0.15)
			settle.tween_property(picture, "rotation", 0.0, 0.15)
			settle.tween_property(picture, "modulate", Color.WHITE, 0.15)


func _badge(user_id: String) -> PlayerBadge:
	if user_id.is_empty() or not badge_of.is_valid():
		return null
	var badge: PlayerBadge = badge_of.call(user_id)
	if badge == null or not is_instance_valid(badge) or not badge.is_visible_in_tree():
		return null
	return badge


func _to_local(global_point: Vector2) -> Vector2:
	return get_global_transform().affine_inverse() * global_point


func _local_rect(global_rect: Rect2) -> Rect2:
	return Rect2(_to_local(global_rect.position), global_rect.size / get_global_transform().get_scale())


# ---------- one throw: the flight and what happens on arrival ----------

# One item on its way and its little scene at the target. Everything it draws is its own
# child, and it frees itself at the end.
class Toss extends Node2D:
	var layer: TableThrows
	var item := ""
	var from := Vector2.ZERO
	var to := Vector2.ZERO
	var radius := 29.0  # of the target's picture
	var picture: Control  # the target's picture, which reacts
	var bits: Bits
	var sprite: Sprite2D
	var line: Tween  # the whole scene, step by step

	func play() -> void:
		bits = Bits.new()
		sprite = Sprite2D.new()
		sprite.texture = layer._pictures[item]
		add_child(sprite)
		add_child(bits)  # specks in front of the item
		line = create_tween()
		var r := radius
		match item:
			"cake":
				_bite_scene(to + Vector2(0, r * 0.55), 0.75, Color("ffe0b2"), Color("f48fb1"), "yum", "Yum!", false)
			"chocolate":
				_bite_scene(to + Vector2(0, r * 0.5), 0.7, Color("6d4c41"), Color("a1887f"), "love", "Yummy!", true)
			"knife":
				_knife()
			"aruval":
				_aruval()
			"ghost":
				_ghost()
			"tomato":
				_splat(Color("e53935"), Color("ffeb3b"), "Splat!", false)
			"egg":
				_splat(Color("fffde7"), Color("ffc107"), "Crack!", true)
			"bomb":
				_bomb()
			"chappal":
				_chappal()
			"coconut":
				_coconut()
			"hammer":
				_hammer()
			"boxing":
				_boxing()
			"firecracker":
				_firecracker()
			"chili":
				_chili()
			"ice":
				_ice()
			"balloon":
				_balloon()
			"rose":
				_rose()
			"crown":
				_crown()
			"chai":
				_chai()
			"money":
				_money()
		line.tween_callback(queue_free)

	# ---------- the items ----------

	# Cake and chocolate: they land at the mouth and go in three bites.
	func _bite_scene(mouth: Vector2, size_share: float, crumb: Color, crumb_light: Color, face: String, words: String, gift_first: bool) -> void:
		_size(size_share)
		_fly(mouth, 0.7, 150.0, 0.0)
		line.tween_callback(_squish.bind(sprite))
		if gift_first:
			# Received first: it pops up with a little sparkle
			line.tween_callback(func() -> void:
				_pop(sprite, 1.25)
				for index in 6:
					bits.add("star", mouth + _scatter(10.0), {"velocity": Vector2.from_angle(randf() * TAU) * randf_range(60, 140), "drag": 2.0, "life": 0.6, "size": randf_range(6, 10), "color": Ui.GOLD, "spin": 4.0})
				_face_at("heart", 0.6)
				Sound.play("sparkle", -6.0))
			line.tween_interval(0.45)
		for bite in 3:
			line.tween_interval(0.3)
			line.tween_callback(func() -> void:
				_cut_top(sprite, (bite + 1) / 3.0)
				_react("chomp")
				for index in 7:
					var color := crumb if index % 2 == 0 else crumb_light
					bits.add("crumb", mouth + Vector2(randf_range(-14, 14), -16), {"velocity": Vector2(randf_range(-120, 120), randf_range(-220, -80)), "gravity": 700.0, "life": 0.7, "size": randf_range(4, 7), "color": color, "spin": randf_range(-8, 8)})
				Sound.play("select", -4.0, randf_range(0.8, 1.0)))
		line.tween_interval(0.15)
		line.tween_callback(func() -> void:
			sprite.hide()
			_face_at(face, 0.9)
			_say(words, Color("ff80ab"))
			for index in 3:
				bits.add("heart", to + Vector2(randf_range(-r_(0.6), r_(0.6)), -r_(0.4)), {"velocity": Vector2(randf_range(-20, 20), -70), "life": 1.0, "size": 9.0, "color": Color("ff4081"), "wait": index * 0.12}))
		line.tween_interval(1.0)

	func _knife() -> void:
		_size(0.8)
		var direction := (to - from).normalized()
		var rest := to - direction * (radius + 26.0)
		sprite.rotation = direction.angle() - PI / 4.0  # the picture's tip points down to the right
		_fly(rest, 0.55, 0.0, 0.0)
		for poke in 3:
			line.tween_property(sprite, "position", rest + direction * 20.0, 0.07).set_ease(Tween.EASE_IN)
			line.tween_callback(func() -> void:
				var hit := to - direction * radius * 0.5
				for index in 6:
					bits.add("star", hit, {"velocity": Vector2.from_angle(randf() * TAU) * randf_range(80, 170), "drag": 3.0, "life": 0.45, "size": randf_range(6, 10), "color": Color("fff59d"), "spin": 5.0})
				_react("jolt", 1.0 if poke % 2 == 0 else -1.0)
				Sound.play("click", -2.0, 1.1 + poke * 0.12))
			line.tween_property(sprite, "position", rest, 0.12)
			line.tween_interval(0.08)
		line.tween_callback(func() -> void:
			_say("Ouch!", Color("ffab40"))
			_face_at("sweat", 0.7)
			_fall_away(sprite, Vector2(direction.x * -60.0, 40.0)))
		line.tween_interval(0.9)

	func _aruval() -> void:
		_size(0.95)
		_grip(ARUVAL_GRIP)
		var hand := to + Vector2(-radius * 1.55, radius * 0.1)
		var blade := 0.62 * sprite.scale.x * 128.0  # from the hand to the middle of the blade
		_fly(hand, 0.65, 130.0, 0.0)
		# Two swings across the picture, forehand and back, each leaving a white streak
		var base := -0.9  # the blade's own slant in the picture
		for swing in 2:
			var start := -1.0 if swing == 0 else 1.2
			var finish := 1.2 if swing == 0 else -1.0
			line.tween_property(sprite, "rotation", start, 0.12)
			line.tween_interval(0.08)
			line.tween_callback(func() -> void:
				bits.add("slash", hand, {"radius": blade + swing * 8.0, "from": base + start, "to": base + finish, "life": 0.4, "size": 7.0, "color": Color.WHITE})
				Sound.play("whoosh", -2.0, 1.35 + swing * 0.15))
			line.tween_property(sprite, "rotation", finish, 0.14).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
			line.tween_callback(func() -> void:
				_react("squash", 0.8)
				for index in 4:
					bits.add("star", to + _scatter(radius * 0.5), {"velocity": Vector2.from_angle(randf() * TAU) * 120.0, "drag": 3.0, "life": 0.4, "size": 7.0, "color": Color("e0f7fa"), "spin": 6.0}))
			line.tween_interval(0.12)
		line.tween_callback(func() -> void:
			# A cartoon plaster on each cut: nobody really gets hurt here
			bits.add("plaster", to + Vector2(-3, -2), {"angle": 0.6, "life": 1.1, "size": 11.0, "color": Color("f3c58e")})
			bits.add("plaster", to + Vector2(3, 4), {"angle": -0.7, "life": 1.1, "size": 11.0, "color": Color("f3c58e"), "wait": 0.12})
			_say("Swish!", Color("e0f7fa"))
			_fade_up(sprite, 0.4))
		line.tween_interval(1.1)

	func _ghost() -> void:
		_size(1.0)
		sprite.modulate.a = 0.85
		sprite.scale *= 0.6
		var arrive := to + Vector2(0, -radius * 0.25)
		_fly(arrive, 1.0, 70.0, 0.0, 34.0, 1.0 / 0.6)
		line.tween_callback(func() -> void:
			var grow := sprite.create_tween()
			grow.tween_property(sprite, "scale", sprite.scale * 1.6, 0.16).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
			_say("BOO!", Color("e1bee7"), 42)
			_react("jump")
			_face_at("scream", 0.9)
			for index in 3:
				bits.add("drop", to + Vector2((index - 1) * radius * 0.6, -radius * 0.9), {"velocity": Vector2((index - 1) * 70.0, -90.0), "gravity": 400.0, "life": 0.7, "size": 6.0, "color": Color("81d4fa")})
			Sound.play("warning", -4.0, 1.4))
		line.tween_interval(0.45)
		line.tween_callback(func() -> void:
			var away := sprite.create_tween().set_parallel()
			away.tween_property(sprite, "position", sprite.position + Vector2(40, -130), 0.8).set_ease(Tween.EASE_IN)
			away.tween_property(sprite, "modulate:a", 0.0, 0.8))
		line.tween_interval(0.85)

	# Tomato and egg: they burst on the picture and drip.
	func _splat(color: Color, inner: Color, words: String, shell: bool) -> void:
		_size(0.65 if shell else 0.7)
		_fly(to, 0.7, 160.0, TAU * 1.5)
		line.tween_callback(func() -> void:
			var squash := sprite.create_tween()
			squash.tween_property(sprite, "scale", Vector2(sprite.scale.x * 1.7, sprite.scale.y * 0.3), 0.07)
			squash.tween_callback(sprite.hide)
			var parts: Array = []
			for index in 8:
				parts.append([_scatter(radius * 0.75), randf_range(6.0, 15.0)])
			bits.add("blob", to, {"parts": parts, "life": 1.5, "fade": 0.5, "color": color})
			if shell:
				bits.add("dot", to + _scatter(4.0), {"life": 1.5, "fade": 0.5, "size": 11.0, "color": inner})
				for index in 6:
					bits.add("shard", to, {"velocity": Vector2.from_angle(randf() * TAU) * randf_range(120, 220), "gravity": 600.0, "life": 0.8, "size": randf_range(5, 8), "color": Color("f5e6c8"), "spin": randf_range(-9, 9)})
			else:
				for index in 6:
					bits.add("dot", to, {"velocity": Vector2.from_angle(randf() * TAU) * randf_range(90, 200), "drag": 2.5, "life": 0.7, "size": 2.5, "color": inner})
			for index in 4:
				bits.add("drop", to + Vector2(randf_range(-radius * 0.7, radius * 0.7), radius * 0.2), {"velocity": Vector2(0, 30), "gravity": 70.0, "life": 1.4, "fade": 0.5, "size": randf_range(4, 7), "color": color, "wait": randf_range(0.1, 0.4)})
			_react("squash", 0.7)
			_say(words, color.lightened(0.2) if not shell else Color("ffe082"))
			Sound.play("place", -2.0, 0.7))
		line.tween_interval(1.5)

	func _bomb() -> void:
		_size(0.75)
		var spot := to + Vector2(radius * 0.95, radius * 0.55)
		_fly(spot, 0.7, 120.0, PI * 0.5)
		# The fuse fizzes for a moment...
		for spark in 12:
			line.tween_callback(func() -> void:
				sprite.rotation = randf_range(-0.12, 0.12)
				var fuse := sprite.position + BOMB_FUSE.rotated(sprite.rotation) * sprite.scale.x
				for index in 2:
					bits.add("spark", fuse, {"velocity": Vector2(randf_range(-90, 90), randf_range(-170, -60)), "gravity": 300.0, "life": 0.3, "size": 7.0, "color": SPARK_COLORS[1] if index == 0 else Color("ff9100")}))
			line.tween_interval(0.06)
		# ...then it goes off
		line.tween_callback(func() -> void:
			sprite.hide()
			var middle := (spot + to) / 2.0
			var boom := _effect("boom", middle, 0.3)
			var grow := boom.create_tween()
			grow.tween_property(boom, "scale", boom.scale * 5.0, 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
			grow.tween_property(boom, "modulate:a", 0.0, 0.35)
			for index in 8:
				bits.add("puff", middle + _scatter(radius * 0.6), {"velocity": Vector2(randf_range(-40, 40), randf_range(-70, -20)), "life": 1.1, "fade": 0.6, "size": randf_range(8, 14), "grow": 18.0, "color": Color(0.35, 0.35, 0.35, 0.8)})
			for index in 12:
				bits.add("spark", middle, {"velocity": Vector2.from_angle(randf() * TAU) * randf_range(160, 320), "drag": 2.5, "life": 0.5, "size": 9.0, "color": Color("ffab00")})
			_tint(Color(0.3, 0.3, 0.3), 1.1)
			_react("jolt", 1.4)
			_say("BOOM!", Color("ff9100"), 42)
			Sound.play("firework", -2.0, 0.8))
		line.tween_interval(1.4)

	func _chappal() -> void:
		_size(0.75)
		_fly(to, 0.55, 90.0, TAU * 2.0)
		line.tween_callback(func() -> void:
			sprite.rotation = -0.3
			_squish(sprite)
			_react("tilt")
			for index in 5:
				bits.add("star", to + _scatter(radius * 0.4), {"velocity": Vector2.from_angle(randf() * TAU) * randf_range(90, 170), "drag": 2.5, "life": 0.6, "size": randf_range(8, 12), "color": Ui.GOLD, "spin": 5.0})
			_say("Thwack!", Color("80deea"))
			Sound.play("drop", -1.0, 1.2))
		line.tween_interval(0.12)
		line.tween_callback(_fall_away.bind(sprite, Vector2(radius * 2.4, -radius * 1.2)))
		line.tween_interval(1.0)

	func _coconut() -> void:
		_size(0.7)
		var head := to + Vector2(0, -radius * 0.9)
		_fly(head, 0.9, 260.0, PI * 1.5)
		line.tween_callback(func() -> void:
			_react("squash", 0.9)
			_fall_away(sprite, Vector2(radius * 2.2, -radius * 2.0))
			for index in 3:
				bits.add("orbit", to, {"rx": radius * 0.95, "ry": radius * 0.32, "lift": -radius * 1.05, "phase": index * TAU / 3.0, "speed": 7.0, "life": 1.3, "size": 9.0, "color": Ui.GOLD})
			_say("Bonk!", Color("d7ccc8"))
			Sound.play("drop", 0.0, 0.9))
		line.tween_interval(1.4)

	func _hammer() -> void:
		_size(0.95)
		_grip(HAMMER_GRIP)
		var hand := to + Vector2(radius * 1.9, -radius * 0.1)
		_fly(hand, 0.65, 140.0, 0.0)
		line.tween_property(sprite, "rotation", 0.5, 0.18).set_ease(Tween.EASE_OUT)  # wind up
		line.tween_property(sprite, "rotation", -0.84, 0.12).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		line.tween_callback(func() -> void:
			_react("squash", 1.4)
			Fx.ring(_global(to), Color.WHITE, 60.0, 0.3)
			for index in 6:
				bits.add("star", to + Vector2(0, -radius * 0.5), {"velocity": Vector2.from_angle(randf_range(PI, TAU)) * randf_range(100, 190), "drag": 2.5, "life": 0.6, "size": randf_range(8, 12), "color": Ui.GOLD, "spin": 5.0})
			_say("Wham!", Color("ffe082"))
			Sound.play("drop", 0.0, 0.75))
		line.tween_interval(0.35)
		line.tween_callback(_fade_up.bind(sprite, 0.4))
		line.tween_interval(0.8)

	func _boxing() -> void:
		_size(0.8)
		var direction := (to - from).normalized()
		var rest := to - direction * (radius + 22.0)
		sprite.rotation = direction.angle() + PI / 2.0  # the knuckles point up in the picture
		_fly(rest, 0.45, 0.0, 0.0)
		line.tween_property(sprite, "position", rest + direction * 26.0, 0.06)
		line.tween_callback(func() -> void:
			var hit := to - direction * radius * 0.4
			bits.add("burst", hit, {"life": 0.45, "size": 34.0, "color": Color("ffeb3b")})
			_react("tilt", signf(direction.x) if direction.x != 0.0 else 1.0)
			_face_at("dazed", 0.8)
			_say("POW!", Color("ff5252"), 40)
			Sound.play("drop", 0.0, 1.1))
		line.tween_property(sprite, "position", rest - direction * 40.0, 0.25).set_ease(Tween.EASE_OUT)
		line.tween_callback(_fade_up.bind(sprite, 0.3))
		line.tween_interval(0.8)

	func _firecracker() -> void:
		_size(0.7)
		var spot := to + Vector2(0, radius * 1.35)
		_fly(spot, 0.7, 120.0, PI)
		for spark in 7:
			line.tween_callback(func() -> void:
				sprite.rotation = randf_range(-0.1, 0.1)
				var fuse := sprite.position + CRACKER_FUSE.rotated(sprite.rotation) * sprite.scale.x
				bits.add("spark", fuse, {"velocity": Vector2(randf_range(-80, 80), randf_range(-160, -60)), "gravity": 300.0, "life": 0.3, "size": 7.0, "color": SPARK_COLORS[1]}))
			line.tween_interval(0.06)
		for crack in 5:
			line.tween_callback(func() -> void:
				if crack == 0:
					sprite.hide()
				var at := to + _scatter(radius * 1.2)
				var color: Color = SPARK_COLORS[randi() % SPARK_COLORS.size()]
				for index in 10:
					bits.add("spark", at, {"velocity": Vector2.from_angle(index * TAU / 10.0 + randf() * 0.3) * randf_range(120, 200), "drag": 3.0, "life": 0.45, "size": 8.0, "color": color})
				bits.add("star", at, {"life": 0.25, "size": 14.0, "color": Color.WHITE})
				_react("jolt", 0.4 if crack % 2 == 0 else -0.4)
				if crack % 2 == 0:
					Sound.play("firework", -10.0, randf_range(1.3, 1.6)))
			line.tween_interval(randf_range(0.14, 0.22))
		line.tween_callback(_say.bind("Pattasu!", Color("ffd740"), 34))
		line.tween_interval(1.0)

	func _chili() -> void:
		_size(0.7)
		var mouth := to + Vector2(0, radius * 0.5)
		_fly(mouth, 0.7, 140.0, PI)
		line.tween_callback(func() -> void:
			var gulp := sprite.create_tween().set_parallel()
			gulp.tween_property(sprite, "scale", sprite.scale * 0.1, 0.22).set_ease(Tween.EASE_IN)
			gulp.tween_property(sprite, "position", to + Vector2(0, radius * 0.3), 0.22)
			_react("chomp"))
		line.tween_interval(0.25)
		line.tween_callback(func() -> void:
			sprite.hide()
			_tint(Color(1.0, 0.45, 0.4), 1.2, 3)
			_react("shiver")
			_face_at("hot", 0.9)
			_say("Spicy!", Color("ff6e40"))
			for index in 8:
				var side := -1.0 if index % 2 == 0 else 1.0
				bits.add("puff", to + Vector2(side * radius * 0.9, -radius * 0.7), {"velocity": Vector2(side * randf_range(30, 60), randf_range(-90, -50)), "life": 0.8, "fade": 0.5, "size": 6.0, "grow": 14.0, "color": Color(1, 1, 1, 0.85), "wait": index * 0.1})
			for index in 6:
				bits.add("spark", to + Vector2(randf_range(-radius * 0.6, radius * 0.6), -radius), {"velocity": Vector2(0, randf_range(-140, -80)), "life": 0.5, "size": 7.0, "color": Color("ff9100"), "wait": index * 0.12})
			Sound.play("turn", -6.0, 1.3))
		line.tween_interval(1.4)

	func _ice() -> void:
		_size(0.7)
		var spot := to + Vector2(radius * 0.85, radius * 0.6)
		_fly(spot, 0.7, 140.0, PI)
		line.tween_callback(func() -> void:
			_squish(sprite)
			_tint(Color(0.6, 0.85, 1.0), 1.3)
			_react("shiver")
			_face_at("cold", 0.9)
			_say("Brrr!", Color("b3e5fc"))
			for index in 8:
				bits.add("flake", to + Vector2.from_angle(index * TAU / 8.0) * radius * randf_range(0.9, 1.3), {"life": 1.2, "fade": 0.5, "size": randf_range(5, 8), "color": Color(1, 1, 1, 0.95), "spin": 1.5, "wait": index * 0.05})
			var melt := sprite.create_tween().set_parallel()
			melt.tween_property(sprite, "scale:y", sprite.scale.y * 0.5, 1.3).set_delay(0.2)
			melt.tween_property(sprite, "position:y", sprite.position.y + 14.0, 1.3).set_delay(0.2)
			melt.tween_property(sprite, "modulate:a", 0.0, 0.6).set_delay(0.9)
			bits.add("drop", spot + Vector2(-8, 18), {"velocity": Vector2(0, 20), "gravity": 60.0, "life": 1.0, "size": 4.0, "color": Color("81d4fa"), "wait": 0.5})
			Sound.play("flip", -4.0, 1.4))
		line.tween_interval(1.6)

	func _balloon() -> void:
		_size(0.8)
		var above := to + Vector2(0, -radius * 0.6)
		_fly(above, 1.0, 80.0, 0.0, 18.0)
		line.tween_property(sprite, "position:y", above.y - 6.0, 0.15)
		line.tween_property(sprite, "position:y", above.y, 0.15)
		line.tween_callback(func() -> void:
			sprite.hide()
			for index in 18:
				bits.add("confetti", above, {"velocity": Vector2.from_angle(randf() * TAU) * randf_range(120, 260), "gravity": 320.0, "drag": 1.5, "life": 1.0, "size": randf_range(5, 8), "color": SPARK_COLORS[index % SPARK_COLORS.size()], "spin": randf_range(-10, 10)})
			Fx.ring(_global(above), Color.WHITE, 50.0, 0.3)
			_react("jump")
			_face_at("shock", 0.8)
			_say("Pop!", Color("ff8a80"))
			Sound.play("confetti", -6.0, 1.2))
		line.tween_interval(1.2)

	func _rose() -> void:
		_size(0.75)
		var spot := to + Vector2(radius * 0.95, radius * 0.3)
		_fly(spot, 0.95, 70.0, 0.3, 10.0)
		line.tween_callback(func() -> void:
			_pop(sprite, 1.3)
			_react("pulse")
			_face_at("love", 0.9)
			_say("Aww!", Color("ff80ab"))
			for index in 6:
				bits.add("heart", to + Vector2(randf_range(-radius, radius), -radius * 0.3), {"velocity": Vector2(randf_range(-25, 25), randf_range(-110, -60)), "life": 1.2, "size": randf_range(7, 11), "color": Color("ff4081") if index % 2 == 0 else Color("f8bbd0"), "wait": index * 0.1})
			for index in 5:
				bits.add("star", spot + _scatter(16.0), {"life": 0.6, "size": 7.0, "color": Ui.GOLD, "spin": 3.0, "wait": index * 0.08})
			Sound.play("sparkle", -4.0))
		line.tween_interval(1.4)
		line.tween_callback(_fade_up.bind(sprite, 0.3))
		line.tween_interval(0.3)

	func _crown() -> void:
		_size(0.7)
		var head := to + Vector2(0, -radius * 1.15)
		_fly(head + Vector2(0, -14), 0.9, 90.0, 0.0)
		line.tween_property(sprite, "position", head, 0.25).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
		line.tween_callback(func() -> void:
			_react("pulse")
			_face_at("proud", 0.9)
			_say("Champion!", Ui.GOLD)
			for index in 7:
				bits.add("star", head + _scatter(radius * 0.9), {"life": 0.7, "size": randf_range(6, 10), "color": Color("fff8e1"), "spin": 4.0, "wait": index * 0.12})
			Sound.play("sparkle", -2.0, 1.1))
		line.tween_interval(1.3)
		line.tween_callback(_fade_up.bind(sprite, 0.35))
		line.tween_interval(0.35)

	func _chai() -> void:
		_size(0.65)
		var spot := to + Vector2(radius * 1.05, radius * 0.4)
		_fly(spot, 0.9, 60.0, 0.0)
		line.tween_callback(func() -> void:
			for index in 4:
				bits.add("wisp", spot + Vector2(randf_range(-10, 10), -18), {"velocity": Vector2(0, -28), "life": 1.4, "fade": 0.6, "size": 3.0, "color": Color(1, 1, 1, 0.75), "phase": randf() * TAU, "wait": index * 0.25}))
		for sip in 2:
			line.tween_interval(0.12)
			line.tween_property(sprite, "position", to + Vector2(radius * 0.5, radius * 0.45), 0.2)
			line.parallel().tween_property(sprite, "rotation", -0.55, 0.2)
			line.tween_callback(func() -> void:
				_react("nod")
				Sound.play("select", -6.0, 0.7))
			line.tween_property(sprite, "position", spot, 0.2)
			line.parallel().tween_property(sprite, "rotation", 0.0, 0.2)
		line.tween_callback(_say.bind("Aaha!", Color("ffe0b2"), 32))
		line.tween_interval(0.7)
		line.tween_callback(_fade_up.bind(sprite, 0.3))
		line.tween_interval(0.3)

	func _money() -> void:
		_size(0.75)
		var above := to + Vector2(0, -radius * 1.1)
		_fly(above, 0.9, 80.0, 0.0, 12.0)
		line.tween_callback(func() -> void:
			var flap := sprite.create_tween().set_loops(4)
			flap.tween_property(sprite, "scale:x", sprite.scale.x * 0.75, 0.08)
			flap.tween_property(sprite, "scale:x", sprite.scale.x, 0.08)
			for index in 10:
				bits.add("note", Vector2(to.x + randf_range(-radius * 1.3, radius * 1.3), to.y - radius * 1.6), {"velocity": Vector2(randf_range(-20, 20), randf_range(40, 80)), "gravity": 90.0, "drag": 0.8, "life": 1.2, "fade": 0.4, "size": 8.0, "color": Color("43a047"), "spin": randf_range(-4, 4), "wait": index * 0.06})
			_face_at("rich", 0.9)
			_say("Cha-ching!", Color("b9f6ca"))
			Sound.play("count", -4.0)
			Sound.play_later("sparkle", 0.25, -6.0))
		line.tween_interval(0.7)
		line.tween_callback(_fade_up.bind(sprite, 0.35))
		line.tween_interval(0.8)

	# ---------- moving the item ----------

	# Sizes the item to a share of ITEM_SIZE.
	func _size(share: float) -> void:
		var side := ITEM_SIZE * share / float(sprite.texture.get_width())
		sprite.scale = Vector2(side, side)

	# The picture turns round the hand holding it instead of round its middle.
	func _grip(grip: Vector2) -> void:
		sprite.centered = false
		sprite.offset = -grip

	# Flies the item from the thrower to `land` along an arc `height` high, turning `spin`
	# radians on the way; `sway` makes it wobble from side to side like a ghost. It grows from
	# half its size as it leaves the thrower's picture.
	func _fly(land: Vector2, seconds: float, height: float, spin: float, sway: float = 0.0, grow: float = 1.0) -> void:
		var bend := (from + land) / 2.0 + Vector2(0, -height)
		var side := (land - from).normalized().orthogonal()
		var turn := sprite.rotation
		var full := sprite.scale * grow
		sprite.position = from
		sprite.scale = full * 0.5
		line.tween_method(func(t: float) -> void:
			var at := from.lerp(bend, t).lerp(bend.lerp(land, t), t)
			sprite.position = at + side * sin(t * TAU * 1.5) * sway * (1.0 - t)
			sprite.rotation = turn + spin * t
			sprite.scale = full * lerpf(0.5, 1.0, minf(1.0, t * 2.5)), 0.0, 1.0, seconds).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

	# A landing squash, and back.
	func _squish(target: Node2D) -> void:
		var rest := target.scale
		var tween := target.create_tween()
		tween.tween_property(target, "scale", Vector2(rest.x * 1.2, rest.y * 0.8), 0.06)
		tween.tween_property(target, "scale", rest, 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

	func _pop(target: Node2D, amount: float) -> void:
		var rest := target.scale
		var tween := target.create_tween()
		tween.tween_property(target, "scale", rest * amount, 0.12).set_ease(Tween.EASE_OUT)
		tween.tween_property(target, "scale", rest, 0.2).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

	# Eats the item from the top: `eaten` is the share gone so far (1 is all of it).
	func _cut_top(target: Sprite2D, eaten: float) -> void:
		var side := float(target.texture.get_width())
		target.centered = false
		target.region_enabled = true
		var cut := side * clampf(eaten, 0.0, 1.0)
		target.region_rect = Rect2(0, cut, side, maxf(1.0, side - cut))
		target.offset = Vector2(-side / 2.0, -side / 2.0 + cut)
		target.visible = eaten < 1.0

	# Knocked off: it tumbles away under gravity and fades.
	func _fall_away(target: Node2D, push: Vector2) -> void:
		var start := target.position
		var tween := target.create_tween().set_parallel()
		tween.tween_method(func(t: float) -> void:
			target.position = start + push * t + Vector2(0, 520.0 * t * t), 0.0, 1.0, 0.7)
		tween.tween_property(target, "rotation", target.rotation + 5.0 * signf(push.x if push.x != 0.0 else 1.0), 0.7)
		tween.tween_property(target, "modulate:a", 0.0, 0.3).set_delay(0.4)

	func _fade_up(target: Node2D, seconds: float) -> void:
		var tween := target.create_tween().set_parallel()
		tween.tween_property(target, "position:y", target.position.y - 30.0, seconds)
		tween.tween_property(target, "modulate:a", 0.0, seconds)

	# ---------- the target's picture ----------

	# The picture reacts: "chomp", "squash", "jolt", "tilt", "jump", "shiver", "pulse", "nod".
	func _react(how: String, amount: float = 1.0) -> void:
		if not is_instance_valid(picture) or not picture.is_inside_tree():
			return
		if picture.has_meta("throw_tween"):
			(picture.get_meta("throw_tween") as Tween).kill()
		picture.pivot_offset = picture.size / 2.0
		picture.scale = Vector2.ONE
		picture.rotation = 0.0
		var tween := picture.create_tween()
		picture.set_meta("throw_tween", tween)
		match how:
			"chomp":
				tween.tween_property(picture, "scale", Vector2(1.08, 0.86), 0.07)
				tween.tween_property(picture, "scale", Vector2.ONE, 0.12)
			"squash":
				picture.scale = Vector2(1.0 + 0.2 * amount, 1.0 - 0.28 * amount)
				tween.tween_property(picture, "scale", Vector2.ONE, 0.6).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
			"jolt":
				picture.rotation = 0.16 * amount
				picture.scale = Vector2(0.92, 0.92)
				tween.set_parallel()
				tween.tween_property(picture, "rotation", 0.0, 0.35).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
				tween.tween_property(picture, "scale", Vector2.ONE, 0.2)
			"tilt":
				picture.rotation = -0.38 * amount
				tween.tween_property(picture, "rotation", 0.0, 0.7).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
			"jump":
				tween.tween_property(picture, "scale", Vector2(1.25, 1.25), 0.1).set_ease(Tween.EASE_OUT)
				for shake in 4:
					tween.tween_property(picture, "rotation", 0.18 if shake % 2 == 0 else -0.18, 0.06)
				tween.tween_property(picture, "rotation", 0.0, 0.06)
				tween.tween_property(picture, "scale", Vector2.ONE, 0.2)
			"shiver":
				for shake in 12:
					tween.tween_property(picture, "rotation", 0.06 if shake % 2 == 0 else -0.06, 0.05)
				tween.tween_property(picture, "rotation", 0.0, 0.05)
			"pulse":
				tween.tween_property(picture, "scale", Vector2(1.12, 1.12), 0.15).set_ease(Tween.EASE_OUT)
				tween.tween_property(picture, "scale", Vector2.ONE, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
			"nod":
				tween.tween_property(picture, "scale", Vector2(1.0, 0.94), 0.12)
				tween.tween_property(picture, "scale", Vector2.ONE, 0.15)

	# Colours the picture for `seconds` (pulsing `beats` times), then lets it come back.
	func _tint(color: Color, seconds: float, beats: int = 1) -> void:
		if not is_instance_valid(picture) or not picture.is_inside_tree():
			return
		if picture.has_meta("throw_tint"):
			(picture.get_meta("throw_tint") as Tween).kill()
		var tween := picture.create_tween()
		picture.set_meta("throw_tint", tween)
		picture.modulate = color
		var beat := seconds / float(beats)
		for index in beats:
			if index > 0:
				tween.tween_property(picture, "modulate", color, beat * 0.3)
			tween.tween_property(picture, "modulate", color.lerp(Color.WHITE, 0.45), beat * 0.7)
		tween.tween_property(picture, "modulate", Color.WHITE, 0.4)

	# A face beside the picture showing how it went down: "yum", "scream", "love"...
	func _face_at(face: String, seconds: float) -> void:
		var at := to + Vector2(radius * 1.05, -radius * 0.95)
		var shown := _effect(face, at, 0.0)
		var tween := shown.create_tween()
		tween.tween_property(shown, "scale", Vector2(0.34, 0.34), 0.2).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tween.tween_interval(seconds)
		tween.tween_property(shown, "modulate:a", 0.0, 0.25)
		tween.tween_callback(shown.queue_free)

	func _effect(effect: String, at: Vector2, scale_now: float) -> Sprite2D:
		var shown := Sprite2D.new()
		shown.texture = layer._pictures[effect]
		shown.position = at
		shown.scale = Vector2(scale_now, scale_now)
		add_child(shown)
		return shown

	# The words rise from above the picture, or from below it for a seat at the top edge.
	func _say(words: String, color: Color, font_size: int = 36) -> void:
		var at := to + Vector2(0, -radius * 1.6)
		if at.y < font_size * 1.5:
			at = to + Vector2(0, radius * 2.4)
		Fx.float_text(_global(at), words, color, font_size)

	func _global(at: Vector2) -> Vector2:
		return get_global_transform() * at

	func _scatter(reach: float) -> Vector2:
		return Vector2.from_angle(randf() * TAU) * randf() * reach

	func r_(share: float) -> float:
		return radius * share


# ---------- specks drawn in code ----------

# Crumbs, splats, drops, stars, hearts, smoke, sparks, slashes and the rest, each a Dictionary
# that moves on its own and fades out at the end of its life.
class Bits extends Node2D:
	var specks: Array = []

	func add(kind: String, at: Vector2, settings: Dictionary = {}) -> void:
		var speck := {
			"kind": kind, "at": at, "velocity": Vector2.ZERO, "gravity": 0.0, "drag": 0.0,
			"life": 1.0, "age": 0.0, "wait": 0.0, "fade": 0.3, "size": 8.0, "grow": 0.0,
			"color": Color.WHITE, "spin": 0.0, "angle": randf() * TAU,
		}
		speck.merge(settings, true)
		specks.append(speck)

	func _process(delta: float) -> void:
		if specks.is_empty():
			return
		for speck: Dictionary in specks:
			if speck.wait > 0.0:
				speck.wait -= delta
				continue
			speck.age += delta
			speck.velocity.y += speck.gravity * delta
			speck.velocity *= maxf(0.0, 1.0 - speck.drag * delta)
			speck.at += speck.velocity * delta
			speck.angle += speck.spin * delta
			speck.size += speck.grow * delta
		specks = specks.filter(func(speck: Dictionary) -> bool: return speck.age < speck.life)
		queue_redraw()

	func _draw() -> void:
		for speck: Dictionary in specks:
			if speck.wait > 0.0:
				continue
			var color: Color = speck.color
			var left: float = speck.life - speck.age
			if left < speck.fade:
				color.a *= left / speck.fade
			var at: Vector2 = speck.at
			var s: float = speck.size
			match speck.kind:
				"dot":
					draw_circle(at, s, color)
				"crumb", "confetti":
					draw_set_transform(at, speck.angle)
					draw_rect(Rect2(-s / 2.0, -s * 0.3, s, s * (0.6 if speck.kind == "confetti" else 0.8)), color)
					draw_set_transform(Vector2.ZERO)
				"star":
					draw_colored_polygon(_star(at, s, 5, speck.angle, 0.45), color)
				"flake":
					for arm in 3:
						var direction := Vector2.from_angle(speck.angle + arm * PI / 3.0) * s
						draw_line(at - direction, at + direction, color, 2.0, true)
				"heart":
					draw_circle(at + Vector2(-s * 0.45, -s * 0.15), s * 0.5, color)
					draw_circle(at + Vector2(s * 0.45, -s * 0.15), s * 0.5, color)
					draw_colored_polygon(PackedVector2Array([at + Vector2(-s * 0.93, 0.0), at + Vector2(s * 0.93, 0.0), at + Vector2(0.0, s * 1.05)]), color)
				"drop":
					draw_circle(at, s * 0.6, color)
					draw_colored_polygon(PackedVector2Array([at + Vector2(-s * 0.55, -s * 0.15), at + Vector2(s * 0.55, -s * 0.15), at + Vector2(0.0, -s * 1.3)]), color)
				"puff":
					draw_circle(at, s, color)
				"spark":
					var velocity: Vector2 = speck.velocity
					draw_line(at, at - velocity * 0.035, color, 3.0, true)
					draw_circle(at, 2.0, color.lightened(0.5))
				"shard":
					draw_colored_polygon(_star(at, s, 3, speck.angle, 1.0), color)
				"blob":
					for part: Array in speck.parts:
						draw_circle(at + part[0], part[1], color)
				"slash":
					var width: float = s * left / float(speck.life)
					draw_arc(at, speck.radius, speck.from, speck.to, 28, color, width, true)
					draw_arc(at, speck.radius, speck.from, speck.to, 28, Color(0.7, 0.95, 1.0, color.a * 0.6), width * 2.2, true)
				"plaster":
					draw_set_transform(at, speck.angle)
					var body := Rect2(-s * 1.3, -s * 0.38, s * 2.6, s * 0.76)
					draw_rect(body, color)
					draw_circle(Vector2(-s * 1.3, 0.0), s * 0.38, color)
					draw_circle(Vector2(s * 1.3, 0.0), s * 0.38, color)
					draw_rect(Rect2(-s * 0.42, -s * 0.38, s * 0.84, s * 0.76), color.lightened(0.35))
					draw_set_transform(Vector2.ZERO)
				"note":
					draw_set_transform(at, speck.angle)
					draw_rect(Rect2(-s, -s * 0.55, s * 2.0, s * 1.1), color)
					draw_rect(Rect2(-s * 0.8, -s * 0.38, s * 1.6, s * 0.76), color.lightened(0.45), false, 1.5)
					draw_circle(Vector2.ZERO, s * 0.25, color.lightened(0.45))
					draw_set_transform(Vector2.ZERO)
				"wisp":
					var points := PackedVector2Array()
					for index in 8:
						points.append(at + Vector2(sin(speck.phase + speck.age * 5.0 + index * 0.9) * 4.0, -index * 4.0))
					draw_polyline(points, color, s, true)
				"burst":
					var grow := 0.6 + 0.4 * minf(1.0, speck.age / 0.08)
					var shape := _star(at, s * grow, 12, 0.0, 0.62)
					draw_colored_polygon(shape, color)
					shape.append(shape[0])
					draw_polyline(shape, Color(0.85, 0.1, 0.1, color.a), 3.0, true)
				"orbit":
					var turn: float = speck.phase + speck.age * speck.speed
					var spot := at + Vector2(cos(turn) * speck.rx, speck.lift + sin(turn) * speck.ry)
					draw_colored_polygon(_star(spot, s, 5, turn, 0.45), color)

	# A star with `points` tips, `inner` being how far in its dents reach.
	func _star(at: Vector2, outer: float, points: int, turn: float, inner: float) -> PackedVector2Array:
		var shape := PackedVector2Array()
		for index in points * 2:
			var reach := outer if index % 2 == 0 else outer * inner
			shape.append(at + Vector2.from_angle(turn - PI / 2.0 + index * PI / points) * reach)
		if inner >= 1.0:
			shape = PackedVector2Array([shape[0], shape[2], shape[4]])
		return shape
