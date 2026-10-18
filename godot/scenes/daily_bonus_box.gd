class_name DailyBonusBox
extends MenuOverlay
## The daily bonus: a wheel the player may spin once every 24 hours for free coins. It opens
## from the pill beside the coins in the menu's top bar, and closes with its tag, a tap beside
## it, or the phone's back button (but not while the wheel turns).
##
## The server keeps the time of the last spin and draws the prize (see the daily bonus part of
## GameClient). The hub asks it; the wheel turns while it answers and comes to rest on the slot
## it named. Until the 24 hours are over the hub shows the time still to wait, and the wheel
## opens again by itself when they are.
##
## Built in code, like Settings: no cream panel this time, the wheel stands on the shade, with
## the close tag at the top right and a line under the wheel saying where things stand.

const WHEEL_SIZE := Vector2(520, 560)

var wheel: BonusWheel
var _status: Label
var _won := 0  # what the last spin paid, shown until the box is closed


func _init() -> void:
	name = "DailyBonusBox"
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP

	var shade := ColorRect.new()
	shade.name = "Shade"
	shade.color = Color(0, 0, 0, 0.72)
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(shade)

	var box := PanelContainer.new()
	box.name = "Box"
	box.anchor_left = 0.5
	box.anchor_right = 0.5
	box.anchor_top = 0.5
	box.anchor_bottom = 0.5
	box.offset_left = -360.0
	box.offset_right = 360.0
	box.grow_horizontal = Control.GROW_DIRECTION_BOTH
	box.grow_vertical = Control.GROW_DIRECTION_BOTH
	add_child(box)

	# The header row MenuOverlay dresses: here only the close tag, at the top right
	var column := VBoxContainer.new()
	column.name = "BonusColumn"
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var header := HBoxContainer.new()
	header.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var spacer := Control.new()
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(spacer)
	var close_button := Button.new()
	close_button.name = "BonusCloseButton"
	close_button.pressed.connect(close)
	header.add_child(close_button)
	column.add_child(header)
	box.add_child(column)

	# The wheel and the line under it lie over the header row (a PanelContainer stacks its
	# children); they let touches through, except on the hub, so the tag can still be tapped
	var layout := VBoxContainer.new()
	layout.name = "BonusLayout"
	layout.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layout.add_theme_constant_override("separation", 6)
	wheel = BonusWheel.new()
	wheel.name = "BonusWheel"
	wheel.custom_minimum_size = WHEEL_SIZE
	wheel.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	layout.add_child(wheel)
	_status = Label.new()
	_status.name = "BonusStatus"
	_status.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status.add_theme_font_size_override("font_size", 26)
	_status.add_theme_color_override("font_color", Color.WHITE)
	_status.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	_status.add_theme_constant_override("outline_size", 6)
	layout.add_child(_status)
	box.add_child(layout)


func _ready() -> void:
	super._ready()
	# The wheel stands on the shade without a panel behind it
	get_node("Box").add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	_status.add_theme_font_override("font", Ui.bold_font)
	wheel.spin_button.pressed.connect(_on_spin_pressed)
	wheel.landed.connect(_on_landed)
	wheel.stopped.connect(_show)
	Game.bonus_changed.connect(_show)
	Game.bonus_spun.connect(_on_spun)
	Game.bonus_failed.connect(_on_failed)
	_show()


## Opens the box, and asks the server again: the wheel may have been spun on another phone.
func open() -> void:
	_won = 0
	_show()
	Game.fetch_bonus()
	super.open()


## Nothing closes the box while the wheel turns, except logging out.
func close() -> void:
	if wheel.is_turning() and Game.is_logged_in():
		return
	super.close()


func is_turning() -> bool:
	return wheel.is_turning()


func _process(_delta: float) -> void:
	if visible:
		_show_wait()


# What the server last said: the slots, and whether the hub may be pressed.
func _show() -> void:
	if wheel.is_turning():
		return  # the slots stay as they are until the wheel is at rest
	if not Game.bonus_prizes().is_empty():
		wheel.prizes = Game.bonus_prizes()
	_show_wait()


# The hub and the line under the wheel, with the countdown running.
func _show_wait() -> void:
	var turning := wheel.is_turning()
	wheel.hub_ready = turning or Game.bonus_available()
	wheel.hub_text = "--:--:--" if Game.bonus.is_empty() else GameClient.countdown_text(Game.bonus_wait())
	wheel.spin_button.disabled = turning
	var text := ""
	if turning:
		text = "Good luck!"
	elif Game.bonus_available():
		text = "Spin the wheel for free coins, up to %s!" % Ui.coins_text(_top_prize())
	elif _won > 0:
		text = "You won %s coins!  Next spin in %s" % [Ui.coins_text(_won), wheel.hub_text]
	elif Game.bonus.is_empty():
		text = "Reconnecting..." if not Game.is_online() else "Loading..."
	else:
		text = "Your next free spin is in %s" % wheel.hub_text
	if _status.text != text:
		_status.text = text


func _top_prize() -> int:
	var best := 0
	for prize: Variant in Game.bonus_prizes():
		best = maxi(best, int(prize))
	return best


func _on_spin_pressed() -> void:
	if wheel.is_turning() or Game.bonus_spinning():
		return
	if not Game.bonus_available():
		Ui.pulse(_status)  # the line under the wheel says how long is left
		return
	_won = 0
	wheel.spin()
	Sound.play("whoosh")
	Game.spin_bonus()
	_show_wait()


func _on_spun(index: int, prize: int) -> void:
	_won = prize
	wheel.land_on(index)


func _on_failed(message: String) -> void:
	wheel.stop()
	_show()
	Ui.alert(message, "Daily Bonus")


func _on_landed(_index: int) -> void:
	var tip := wheel.global_position + wheel.pointer_tip()
	Sound.play("win")
	Fx.sparkle(tip, Fx.GOLD, 26)
	Fx.float_text(tip - Vector2(0.0, 70.0), "+%s" % Ui.coins_text(_won), Fx.GOLD, 48)
	if _won >= 5000:
		Fx.confetti()
	Input.vibrate_handheld(120)
	_show()
	Ui.pulse(_status)
