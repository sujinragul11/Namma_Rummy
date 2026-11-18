class_name DonkeyRequests
extends Control
## Request Card at the Donkey Master table (the rules are the server's: DonkeyEngine).
##
## - Under the seat of each player next to us (the nearest players in play on either side) a
##   "Request Your Card" pill. It asks at once when we may: between tricks, after the wait since
##   our last request, with no request of ours still open. Otherwise it is dimmed and a tap says
##   why.
## - Asked ourselves: a box with Accept and Reject and the time left to answer. Accepting gives
##   all our cards to whoever asked, and we are out and safe; the server moves them only then.
## - On every seat a request concerns, a tag says where it stands (ASKED and ASKING with the
##   time running down, then ACCEPTED, REJECTED or NO ANSWER), for everyone at the table.
## - Cards that change hands fly, face down, from one seat to the other for the players who
##   watch; DonkeyTable moves the cards of our own hand.
##
## Built in code. DonkeyTable adds it over the cards, the chat and the throw buttons, under the
## result box, and keeps the throw buttons clear of controls().

const PILL := Vector2(150, 34)
const ASKED := Color("ef6c00")
const ASKING := Color("1e88e5")
const ACCEPTED := Color("43a047")
const REJECTED := Color("d32f2f")
const NO_ANSWER := Color("616161")
const FLYING := 6  # at most this many cards fly between two seats for those who watch

## id -> DonkeySeat or null (DonkeyTable sets it)
var seat_of: Callable

var _pills: Dictionary = {}  # player id -> the "Request Your Card" pill under their seat
var _box: PanelContainer
var _box_title: Label
var _box_text: Label
var _box_clock: Control
var _accept: Button
var _reject: Button
var _asked_id := ""  # the request the box answers
var _seen: Dictionary = {}  # request id -> status already shown


func _init() -> void:
	name = "DonkeyRequests"
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	_box = PanelContainer.new()
	_box.name = "CardRequestBox"
	_box.visible = false
	_box.custom_minimum_size = Vector2(440, 0)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	_box.add_child(column)
	_box_title = Label.new()
	_box_title.name = "CardRequestTitle"
	_box_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_box_title.add_theme_font_size_override("font_size", 24)
	_box_title.add_theme_color_override("font_color", Ui.GOLD)
	column.add_child(_box_title)
	_box_text = Label.new()
	_box_text.name = "CardRequestText"
	_box_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_box_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_box_text.add_theme_font_size_override("font_size", 18)
	_box_text.add_theme_color_override("font_color", Color.WHITE)
	column.add_child(_box_text)
	_box_clock = Control.new()
	_box_clock.name = "CardRequestClock"
	_box_clock.custom_minimum_size = Vector2(0, 10)
	_box_clock.draw.connect(_draw_clock)
	column.add_child(_box_clock)
	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	buttons.add_theme_constant_override("separation", 18)
	column.add_child(buttons)
	_accept = _button("CardRequestAccept", "Accept")
	_accept.pressed.connect(func() -> void: _answer(true))
	buttons.add_child(_accept)
	_reject = _button("CardRequestReject", "Reject")
	_reject.pressed.connect(func() -> void: _answer(false))
	buttons.add_child(_reject)
	add_child(_box)


func _ready() -> void:
	_box.add_theme_stylebox_override("panel", Ui.box(Color(0.05, 0.12, 0.07, 0.94), 18, 22, 16))
	_box_title.add_theme_font_override("font", Ui.bold_font)
	Ui.tint_button(_accept, ACCEPTED)
	Ui.tint_button(_reject, REJECTED)


## What the throw buttons must keep clear of.
func controls() -> Array:
	var list: Array = [_box]
	list.append_array(_pills.values())
	return list


## After a new table state, before DonkeyTable lays the cards out: the requests that have just
## been accepted, as [{"giver", "taker", "moved"}], for the cards of our own hand to fly.
func refresh() -> Array:
	var accepted: Array = []
	var live := {}
	for request: Dictionary in Game.donkey.requests():
		var id := str(request.get("id"))
		live[id] = true
		var status := str(request.get("status"))
		if status == "accepted" and _seen.get(id, "") != "accepted":
			var giver := str(request.get("to"))
			var taker := str(request.get("from"))
			accepted.append({"giver": giver, "taker": taker, "moved": int(request.get("moved", 0))})
			if giver != Game.player_id and taker != Game.player_id:
				_fly_cards(giver, taker, int(request.get("moved", 0)))
			Sound.play("card")
		_seen[id] = status
	for id: String in _seen.keys():
		if not live.has(id):
			_seen.erase(id)
	_update_pills()
	_update_box()
	return accepted


func _process(_delta: float) -> void:
	if Game.donkey.state.is_empty():
		return
	_update_tags()
	_update_pills()
	if _box.visible:
		_update_box()
		_box_clock.queue_redraw()


# ---------- the pills under our neighbours' seats ----------

func _update_pills() -> void:
	var playing := Game.donkey.status() == "playing"
	var wanted := {}
	if playing:
		for id: Variant in Game.donkey.neighbours():
			wanted[str(id)] = true
	for id: String in _pills.keys():
		if not wanted.has(id):
			_pills[id].queue_free()
			_pills.erase(id)
	for id: String in wanted:
		var seat: DonkeySeat = seat_of.call(id) if seat_of.is_valid() else null
		if seat == null:
			continue
		var pill: Button = _pills.get(id)
		if pill == null:
			pill = _button("RequestCardButton_" + id, "Request Your Card")
			pill.custom_minimum_size = PILL
			pill.add_theme_font_size_override("font_size", 15)
			pill.pressed.connect(_on_pill.bind(id))
			add_child(pill)
			move_child(pill, 0)  # under the answer box
			_pills[id] = pill
		pill.reset_size()
		pill.position = _pill_spot(seat, pill.size)
		var may := Game.donkey.may_request(id)
		var wait := Game.donkey.request_wait()
		var text := "Request Your Card"
		if not Game.donkey.my_pending_request().is_empty():
			text = "Waiting..."
		elif wait > 0:
			text = "Request in %ds" % ceili(wait / 1000.0)
		if pill.text != text:
			pill.text = text
		pill.modulate = Color.WHITE if may else Color(1, 1, 1, 0.55)
		if pill.get_meta("may", null) != may:
			pill.set_meta("may", may)
			Ui.tint_button(pill, ASKING if may else Ui.SLATE)
			for state_name: String in ["normal", "hover", "pressed", "disabled"]:
				var style := pill.get_theme_stylebox(state_name) as StyleBoxFlat
				if style != null:
					style.content_margin_top = 4.0
					style.content_margin_bottom = 4.0
					style.content_margin_left = 12.0
					style.content_margin_right = 12.0


# Next to a neighbour's seat, clear of every seat and of the pile of cards out of the game: a
# seat on the left gets it right of its picture (under it sits our own seat); any other under
# its name.
func _pill_spot(seat: DonkeySeat, pill_size: Vector2) -> Vector2:
	var center := seat.avatar_center() - global_position
	if center.x < size.x * 0.35:
		var reach := DonkeySeat.RADIUS + DonkeySeat.RING + 58.0  # past the cards and their count
		return Vector2(center.x + reach, center.y - pill_size.y / 2.0)
	var below := seat.global_position.y - global_position.y + DonkeySeat.SIZE.y + 2.0
	return Vector2(clampf(center.x - pill_size.x / 2.0, 8.0, size.x - pill_size.x - 8.0), below)


func _on_pill(id: String) -> void:
	if Game.donkey.may_request(id):
		Game.donkey.request_card(id)
		return
	# Say why not, as the server would
	var message := "You can ask for cards between tricks, before the next card is led."
	if not Game.donkey.my_pending_request().is_empty():
		message = "Wait for %s to answer your request." % Game.donkey.player_name(str(Game.donkey.my_pending_request().get("to")))
	elif Game.donkey.request_wait() > 0:
		message = "Wait %d s before asking again." % ceili(Game.donkey.request_wait() / 1000.0)
	Game.notice.emit("info", message)


# ---------- the box when we are asked ----------

func _update_box() -> void:
	var request := Game.donkey.request_to_me()
	if request.is_empty():
		_box.visible = false
		_asked_id = ""
		return
	var fresh := not _box.visible or _asked_id != str(request.get("id"))
	_asked_id = str(request.get("id"))
	var asker := Game.donkey.player_name(str(request.get("from")))
	var count := Game.donkey.hand().size()
	_box_title.text = "%s asks for your cards" % asker
	var busy := _card_in_trick()
	_box_text.text = ("Accept: all %d of your cards go to %s, and you are out and safe.\nReject: you keep them." % [count, asker]) \
		+ ("\n\nYou can accept once this trick is over." if busy else "")
	_accept.disabled = busy
	_box.visible = true
	_box.reset_size()
	_box.position = Vector2((size.x - _box.size.x) / 2.0, size.y * 0.5 - _box.size.y / 2.0)
	if fresh:
		Ui.pop_in.call_deferred(_box)
		Sound.play("notice")


# Our own card lies in the trick on the table (or a trick is being settled): the server takes
# our answer only once it is over.
func _card_in_trick() -> bool:
	var state := Game.donkey.state
	if not (state.get("trickEnd", {}) as Dictionary).is_empty():
		return true
	for play: Dictionary in state.get("trick", []):
		if str(play.get("playerId")) == Game.player_id:
			return true
	return false


func _answer(accept: bool) -> void:
	if _asked_id.is_empty():
		return
	Game.donkey.answer_request(_asked_id, accept)
	_box.visible = false  # the next state brings it back if the server did not take the answer


func _draw_clock() -> void:
	var request := Game.donkey.request_to_me()
	var left := Game.donkey.request_time_left(request) if not request.is_empty() else 0.0
	var bar := Rect2(Vector2.ZERO, _box_clock.size)
	_box_clock.draw_style_box(Ui.box(Color(1, 1, 1, 0.15), 5, 0, 0), bar)
	_box_clock.draw_style_box(Ui.box(ASKED, 5, 0, 0), Rect2(bar.position, Vector2(maxf(10.0, bar.size.x * left), bar.size.y)))


# ---------- the tags on the seats ----------

func _update_tags() -> void:
	var tags := {}  # player id -> [text, colour, time left]
	# Requests are shown while the game is played; once it is over the seats say who won
	var shown: Array = Game.donkey.requests() if Game.donkey.status() == "playing" else []
	for request: Dictionary in shown:
		var from := str(request.get("from"))
		var to := str(request.get("to"))
		match str(request.get("status")):
			"pending":
				var left := Game.donkey.request_time_left(request)
				tags[to] = ["ASKED", ASKED, left]
				tags[from] = ["ASKING", ASKING, left]
			"accepted":
				tags[from] = ["+%d CARDS" % int(request.get("moved", 0)), ACCEPTED, -1.0]
				tags[to] = ["ACCEPTED", ACCEPTED, -1.0]
			"rejected":
				tags[to] = ["REJECTED", REJECTED, -1.0]
			"expired":
				tags[to] = ["NO ANSWER", NO_ANSWER, -1.0]
	for player: Dictionary in Game.donkey.players():
		var id := str(player.get("id"))
		var seat: DonkeySeat = seat_of.call(id) if seat_of.is_valid() else null
		if seat == null:
			continue
		var tag: Array = tags.get(id, ["", Color.BLACK, -1.0])
		seat.request_fill = tag[1]
		seat.request_left = tag[2]
		seat.request_tag = tag[0]


# ---------- cards that change hands, for those who watch ----------

func _fly_cards(giver: String, taker: String, moved: int) -> void:
	var from: DonkeySeat = seat_of.call(giver) if seat_of.is_valid() else null
	var to: DonkeySeat = seat_of.call(taker) if seat_of.is_valid() else null
	if from == null or to == null:
		return
	var start: Vector2 = from.avatar_center() - global_position
	var end: Vector2 = to.avatar_center() - global_position
	for index in mini(maxi(moved, 1), FLYING):
		var card := CardView.new()
		card.interactive = false
		card.face_down = true
		card.set_width(44.0)
		card.position = start - card.size / 2.0
		card.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(card)
		move_child(card, 0)
		var delay := index * 0.07
		var tween := card.create_tween()
		tween.tween_interval(delay)
		tween.tween_property(card, "position", end - card.size / 2.0, 0.5).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
		tween.tween_property(card, "modulate:a", 0.0, 0.15)
		tween.tween_callback(card.queue_free)


func _button(button_name: String, text: String) -> Button:
	var button := Button.new()
	button.name = button_name
	button.text = text
	button.focus_mode = Control.FOCUS_NONE
	button.custom_minimum_size = Vector2(150, 50)
	button.add_theme_font_size_override("font_size", 20)
	return button
