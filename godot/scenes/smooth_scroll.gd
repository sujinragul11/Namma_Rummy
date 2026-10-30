class_name SmoothScroll
extends ScrollContainer
## A vertical list that scrolls like a phone's: it follows a finger, or the mouse held down on a
## PC, from anywhere on it (buttons included), glides on after a flick and slows to a stop, and
## a wheel notch glides instead of jumping. A finger on a gliding list stops it.
##
## A press that moves less than DEADZONE stays a tap for the button under it. Once it moves
## further the button lets go, so a swipe never presses anything. For that everything inside
## that would keep a press to itself (buttons, the panels of rows) passes it on to the list
## (MOUSE_FILTER_PASS); buttons still answer taps as before. Godot's own dragging is left out:
## it only works on touchscreens, and not from a button or a panel.

const DEADZONE := 12.0  # how far a press may wander and still be a tap
const WHEEL_STEP := 90.0  # one notch of the wheel
const CATCH_UP := 14.0  # how quickly a wheel glide reaches its place (higher is quicker)
const FRICTION := 2.6  # how quickly a flick slows down (higher stops sooner)
const STOP_SPEED := 30.0  # a glide slower than this, in units per second, has stopped
const MAX_SPEED := 6000.0
const SAMPLE_TIME := 0.08  # the last part of a drag, in seconds, that sets a flick's speed
const CATCH_SPEED := 120.0  # a press on a list gliding faster than this only stops it
const BAR_GAP := 10.0  # between the rows and the scrollbar

var _holding := false  # a press on the list is down
var _dragging := false  # ... and has moved far enough to scroll
var _press_y := 0.0
var _press_scroll := 0.0
var _trail: Array[Vector2] = []  # (seconds, y) of the pointer during the last moments of a drag
var _position := 0.0  # where the list is, with the fraction that scroll_vertical drops
var _speed := 0.0  # of a flick, in units per second
var _target := -1.0  # where a wheel glide is heading; below 0 while none is
var _written := 0  # what was last put in scroll_vertical, to notice the scrollbar moving it


func _ready() -> void:
	set_process(false)
	sort_children.connect(_make_room_for_bar)
	get_tree().node_added.connect(_on_node_added)
	for control: Node in find_children("*", "Control", true, false):
		_on_node_added(control)


## Gives the scrollbar a thumb a finger can find: `width` wide, in the panel's own colours.
func paint_bar(track: Color, thumb: Color, width: float = 20.0) -> void:
	var bar := get_v_scroll_bar()
	bar.custom_minimum_size.x = width
	bar.add_theme_stylebox_override("scroll", Ui.box(track, int(width / 2.0), 0, 0))
	for state_name: String in ["grabber", "grabber_highlight", "grabber_pressed"]:
		var grabber := Ui.box(thumb.lightened(0.12) if state_name != "grabber" else thumb, int(width / 2.0), 0, 0)
		grabber.content_margin_top = 24  # never shorter than a fingertip
		grabber.content_margin_bottom = 24
		bar.add_theme_stylebox_override(state_name, grabber)


# Godot keeps room only for the width its default scrollbar style asks for, so a wider bar lay
# over the right edge of the rows. While the bar shows, the rows end a little before it.
func _make_room_for_bar() -> void:
	var bar := get_v_scroll_bar()
	if not bar.visible:
		return
	var room := size.x - bar.size.x - BAR_GAP
	for child in get_children():
		var content := child as Control
		if content != null and content.size.x > room:
			content.size.x = room


func _on_node_added(node: Node) -> void:
	var control := node as Control
	if control == null or control.mouse_filter != Control.MOUSE_FILTER_STOP or not is_ancestor_of(control):
		return
	# The scrollbar keeps its presses: dragging its thumb is not a swipe
	for bar: ScrollBar in [get_v_scroll_bar(), get_h_scroll_bar()]:
		if control == bar or bar.is_ancestor_of(control):
			return
	control.mouse_filter = Control.MOUSE_FILTER_PASS


func _gui_input(event: InputEvent) -> void:
	var button := event as InputEventMouseButton
	var motion := event as InputEventMouseMotion
	if button != null:
		match button.button_index:
			MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN:
				if button.pressed:
					var notches := button.factor if button.factor > 0.0 else 1.0
					_wheel(WHEEL_STEP * notches * (1.0 if button.button_index == MOUSE_BUTTON_WHEEL_DOWN else -1.0))
				accept_event()
			MOUSE_BUTTON_LEFT:
				if button.pressed:
					_press(button.position.y)
				else:
					_release()
				accept_event()
	elif motion != null and _holding:
		# A release the list never heard of (it happened beside it) ends the drag too
		if (motion.button_mask & MOUSE_BUTTON_MASK_LEFT) == 0:
			_release()
		else:
			_move(motion.position.y)
		accept_event()


func _notification(what: int) -> void:
	if what == NOTIFICATION_VISIBILITY_CHANGED and not is_visible_in_tree():
		_holding = false
		_dragging = false
		_stop()


func _press(y: float) -> void:
	_sync()
	var was_gliding := absf(_speed) > CATCH_SPEED or _target >= 0.0
	_stop()
	_holding = true
	_dragging = false
	_press_y = y
	_press_scroll = _position
	_trail.clear()
	_note(y)
	# On a phone the touch that stops a gliding list does nothing else. Deferred: a touch also
	# reaches the button as itself, after the mouse press made from it, and would press it again.
	if was_gliding:
		_let_go_of_buttons.call_deferred()


func _move(y: float) -> void:
	if not _dragging:
		if absf(y - _press_y) < DEADZONE:
			return
		# From here on the list follows the pointer, starting where it is now
		_dragging = true
		_press_y = y
		_press_scroll = _position
		_let_go_of_buttons()
	_position = clampf(_press_scroll - (y - _press_y), 0.0, _max_scroll())
	_write()
	_note(y)


func _release() -> void:
	if not _holding:
		return
	_holding = false
	if not _dragging:
		return
	_dragging = false
	_speed = clampf(_flick_speed(), -MAX_SPEED, MAX_SPEED)
	if absf(_speed) >= STOP_SPEED:
		set_process(true)
	else:
		_speed = 0.0


func _wheel(amount: float) -> void:
	_sync()
	_speed = 0.0
	var from := _target if _target >= 0.0 else _position
	_target = clampf(from + amount, 0.0, _max_scroll())
	set_process(true)


func _process(delta: float) -> void:
	if _sync():
		# Something else moved the list meanwhile (the scrollbar's thumb): it has the last word
		_stop()
		return
	if _target >= 0.0:
		_position = lerpf(_position, _target, 1.0 - exp(-CATCH_UP * delta))
		if absf(_target - _position) < 0.5:
			_position = _target
			_target = -1.0
	else:
		_position += _speed * delta
		_speed *= exp(-FRICTION * delta)
		if absf(_speed) < STOP_SPEED or _position <= 0.0 or _position >= _max_scroll():
			_speed = 0.0
		_position = clampf(_position, 0.0, _max_scroll())
	_write()
	if _target < 0.0 and _speed == 0.0:
		set_process(false)


func _stop() -> void:
	_speed = 0.0
	_target = -1.0
	set_process(false)


# Reads the list's place again when something other than this script changed it. True if so.
func _sync() -> bool:
	if scroll_vertical == _written:
		return false
	_position = scroll_vertical
	_written = scroll_vertical
	return true


func _write() -> void:
	scroll_vertical = roundi(_position)
	_written = scroll_vertical


func _max_scroll() -> float:
	var bar := get_v_scroll_bar()
	return maxf(0.0, bar.max_value - bar.page)


func _note(y: float) -> void:
	var now := Time.get_ticks_usec() / 1000000.0
	_trail.append(Vector2(now, y))
	while _trail.size() > 2 and now - _trail[0].x > SAMPLE_TIME:
		_trail.pop_front()


# How fast the pointer was moving when it let go; nothing if it had stopped first.
func _flick_speed() -> float:
	var now := Time.get_ticks_usec() / 1000000.0
	if _trail.size() < 2 or now - _trail[-1].x > SAMPLE_TIME:
		return 0.0
	var first := _trail[0]
	var last := _trail[-1]
	if last.x - first.x <= 0.0:
		return 0.0
	return -(last.y - first.y) / (last.x - first.x)


# The button a press began on must not press when the finger lifts. Switching it off and on
# again cancels its press, and its button_up still comes with the release.
func _let_go_of_buttons() -> void:
	for button: BaseButton in find_children("*", "BaseButton", true, false):
		var mode := button.get_draw_mode()
		if not button.disabled and (mode == BaseButton.DRAW_PRESSED or mode == BaseButton.DRAW_HOVER_PRESSED):
			button.disabled = true
			button.disabled = false
