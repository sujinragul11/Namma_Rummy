class_name MatchSearch
extends MenuOverlay
## "Play Now": the box shown while the server looks for players for the table that was set
## up. No room code: players who want the same table are seated together as they come,
## the ones in the same region (the phone's time zone) first, then further afield.
##
## The seats of the table are drawn in a row: the ones taken by players found so far show a
## face, the free ones wait with a question mark while a ring turns round the next one.
## Closing the box (Cancel, the cross, the shade, the back button) ends the search; when the
## server seats the player the table's state takes them to the game and the box goes away.

const SEAT_RADIUS := 34.0
const SEAT_GAP := 18.0
const LONELY_SECONDS := 30  # after this long alone, the box suggests something else
const BROWN := Color("5d4037")
const DIM := Color("8d6e63")
const EMPTY_SEAT := Color("d7ccc8")
const SCOPE_TEXT := {
	"region": "Looking for players in your region%s",
	"nearby": "Nobody free in your region%s yet: looking in nearby regions too",
	"everywhere": "Looking for players everywhere%s",
}

var _title: Label
var _game_label: Label
var _seats: Control
var _scope_label: Label
var _count_label: Label
var _time_label: Label
var _cancel_button: Button
var _spin := 0.0
var _found := 0


func _init() -> void:
	name = "MatchSearch"
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

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 12)
	box.add_child(column)

	# The header row MenuOverlay dresses: the title on a banner, a tag to close
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 0)
	var left := Control.new()
	left.custom_minimum_size = Vector2(56, 0)
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(left)
	_title = Label.new()
	_title.name = "SearchTitle"
	_title.text = "Finding Players"
	header.add_child(_title)
	var right := Control.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(right)
	var close_button := Button.new()
	close_button.name = "SearchCloseButton"
	close_button.pressed.connect(close)
	header.add_child(close_button)
	column.add_child(header)

	_game_label = _line("SearchGame", 24, BROWN)
	column.add_child(_game_label)

	_seats = Control.new()
	_seats.name = "SearchSeats"
	_seats.custom_minimum_size = Vector2(0, SEAT_RADIUS * 2.0 + 16.0)
	_seats.draw.connect(_draw_seats)
	column.add_child(_seats)

	_count_label = _line("SearchCount", 26, BROWN)
	column.add_child(_count_label)
	_scope_label = _line("SearchScope", 19, DIM)
	column.add_child(_scope_label)
	_time_label = _line("SearchTime", 18, DIM)
	column.add_child(_time_label)

	_cancel_button = Button.new()
	_cancel_button.name = "CancelSearchButton"
	_cancel_button.text = "Cancel"
	_cancel_button.custom_minimum_size = Vector2(240, 60)
	_cancel_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_cancel_button.add_theme_font_size_override("font_size", 26)
	_cancel_button.pressed.connect(close)
	column.add_child(_cancel_button)


func _ready() -> void:
	super._ready()
	_game_label.add_theme_font_override("font", Ui.bold_font)
	_count_label.add_theme_font_override("font", Ui.bold_font)
	Ui.tint_button(_cancel_button, Ui.RED)
	Game.match_changed.connect(_on_match_changed)


## Opens the box for the table being searched for, described in `game` (e.g. "Points Rummy
## · 2 players · 10 coins a point").
func open_for(game: String) -> void:
	_game_label.text = game
	_found = 1
	_refresh()
	open()


func _line(node_name: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.name = node_name
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size = Vector2(600, 0)
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	return label


func _on_match_changed() -> void:
	if not visible:
		return
	if not Game.searching():
		close()  # seated at a table (its screen opens now), or the search failed
		return
	var found := int(Game.match_status.get("found", 1))
	if found > _found:
		Sound.play("join")  # someone else is coming to the table
		Ui.pulse(_count_label, 1.08)
	_found = found
	_refresh()


func _process(delta: float) -> void:
	if not visible:
		return
	_spin += delta * 3.0
	_seats.queue_redraw()
	_refresh_clock()


func _refresh() -> void:
	var status := Game.match_status
	var needed := int(Game.match_search.get("maxPlayers", 2))
	_found = clampi(int(status.get("found", 1)), 1, needed)
	var region := str(status.get("region", ""))
	var scope := str(status.get("scope", "region"))
	_scope_label.text = str(SCOPE_TEXT.get(scope, SCOPE_TEXT.region)) % ("" if region.is_empty() or scope == "everywhere" else " (%s)" % region)
	var searching_too := int(status.get("inQueue", 1))
	if searching_too > _found:
		_scope_label.text += "\n%d players are looking for this table right now" % searching_too
	_refresh_clock()


# The parts that change every second: the countdown to a table that starts without all its
# seats taken, and how long the search has been going.
func _refresh_clock() -> void:
	var needed := int(Game.match_search.get("maxPlayers", 2))
	if _found < 2:
		_count_label.text = "Searching for players..."
	elif Game.match_starts_at > 0:
		_count_label.text = "%d of %d players found  ·  starting in %d s" % [_found, needed, Game.seconds_until(Game.match_starts_at)]
	else:
		_count_label.text = "%d of %d players found" % [_found, needed]

	var waited := 0 if Game.match_since == 0 else int((Time.get_ticks_msec() - Game.match_since) / 1000.0)
	_time_label.text = "Searching for %d:%02d" % [floori(waited / 60.0), waited % 60]
	if _found < 2 and waited >= LONELY_SECONDS:
		_time_label.text += "\nNobody else wants this table right now. Keep waiting, pick another table, or play with friends."


# The table's seats in a row: faces for the players found, the next free seat with a ring
# turning round it, the rest waiting with a question mark.
func _draw_seats() -> void:
	var needed := int(Game.match_search.get("maxPlayers", 2))
	if needed < 1:
		return
	var width := needed * SEAT_RADIUS * 2.0 + (needed - 1) * SEAT_GAP
	var start := Vector2((_seats.size.x - width) / 2.0 + SEAT_RADIUS, _seats.size.y / 2.0)
	var font := Ui.bold_font
	var font_size := int(SEAT_RADIUS * 0.9)
	var me := str(Game.user.get("username", "?"))
	for seat in needed:
		var center := start + Vector2(seat * (SEAT_RADIUS * 2.0 + SEAT_GAP), 0.0)
		var letter := "?"
		if seat < _found:
			# The player is the first face; the others are not named until the table opens
			var color: Color = PlayerBadge.AVATAR_COLORS[(absi(hash(me)) + seat) % PlayerBadge.AVATAR_COLORS.size()]
			_seats.draw_circle(center, SEAT_RADIUS + 3.0, Ui.GOLD, true, -1.0, true)
			_seats.draw_circle(center, SEAT_RADIUS, color, true, -1.0, true)
			if seat > 0:
				# A tick: a player found for this seat
				var tick := PackedVector2Array([center + Vector2(-13, 1), center + Vector2(-4, 11), center + Vector2(14, -10)])
				_seats.draw_polyline(tick, Color.WHITE, 6.0, true)
				continue
			letter = me.substr(0, 1).to_upper()
		else:
			_seats.draw_circle(center, SEAT_RADIUS, EMPTY_SEAT, true, -1.0, true)
			if seat == _found:
				_seats.draw_arc(center, SEAT_RADIUS + 5.0, _spin, _spin + PI * 1.3, 32, Ui.TEAL, 5.0, true)
		var baseline := center.y + (font.get_ascent(font_size) - font.get_descent(font_size)) / 2.0
		var ink := Color.WHITE if seat < _found else DIM
		_seats.draw_string(font, Vector2(center.x - SEAT_RADIUS, baseline), letter, HORIZONTAL_ALIGNMENT_CENTER, SEAT_RADIUS * 2.0, font_size, ink)
