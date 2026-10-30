extends ScrollContainer
## ScrollContainer handles touch swipes and the wheel. Also allow desktop mouse dragging.
var _dragging := false
var _pressed_at := Vector2.ZERO
var _starting_scroll := 0
var _touch_index := -1

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.device != InputEvent.DEVICE_ID_EMULATION:
		if event.button_index == MOUSE_BUTTON_LEFT:
			_dragging = event.pressed
			_pressed_at = event.global_position
			_starting_scroll = scroll_vertical

func _input(event: InputEvent) -> void:
	# Native touch events do not pass through every Control's mouse GUI path.
	if event is InputEventScreenTouch and event.pressed and is_visible_in_tree() and get_global_rect().has_point(event.position):
		for button: Button in find_children("*", "Button", true, false):
			if button.is_visible_in_tree() and button.get_global_rect().has_point(event.position):
				return
		_touch_index = event.index
		_pressed_at = event.position
		_starting_scroll = scroll_vertical
	if event is InputEventScreenTouch and event.index == _touch_index and not event.pressed:
		_touch_index = -1
	elif event is InputEventScreenDrag and event.index == _touch_index:
		scroll_vertical = _starting_scroll - roundi(event.position.y - _pressed_at.y)
		get_viewport().set_input_as_handled()
	if not _dragging:
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
		_dragging = false
	elif event is InputEventMouseMotion:
		var distance: float = event.global_position.y - _pressed_at.y
		if absf(distance) >= 6:
			scroll_vertical = _starting_scroll - roundi(distance)
			get_viewport().set_input_as_handled()

func _notification(what: int) -> void:
	if what == NOTIFICATION_VISIBILITY_CHANGED and not is_visible_in_tree():
		_dragging = false
		_touch_index = -1
