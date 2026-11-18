class_name DonkeyTable
extends Control
## The Donkey Master table: everyone around an oval table, our own cards fanned along the
## bottom, the trick in the middle. Everything shown comes from Game.donkey.state; this screen
## draws it, animates each change by comparing it with what is already on the table, and sends
## our card when we play one.
##
## Every card on screen is one CardView in `_views`, by card id (one pack, so ids are unique):
## it glides from our hand to the trick, from a player's picture to the trick, from the trick
## into a hand or to the pile of cards out of the game. Opponents' hands are only counts.
##
## Playing: tap a card that may be played (they stand up on our turn; the others are dimmed) to
## pick it, then tap it again or press PLAY.

const HAND_CARD := 104.0
const TRICK_CARD := 86.0
const PILE_CARD := 60.0
const HAND_LIFT := 18.0  # a card that may be played stands up this far
const PICK_LIFT := 44.0  # and the one picked this far
const GLIDE := 0.3
const FLY := 0.42
const DEAL_STAGGER := 0.025
const RESULT_DELAY := 2.4  # seconds between the last card and the result box
const SUIT_NAMES := {"♠": "spade", "♥": "heart", "♦": "diamond", "♣": "club"}
const WOOD := Color("8d5a2b")
const WOOD_DARK := Color("4e2f14")
const FELT_LIGHT := Color("3d9c49")
const FELT_EDGE := Color("15541f")
## The pot sits this far from the right edge, left of the chat and emoji buttons.
const POT_RIGHT := TableChat.MARGIN + TableChat.BUTTON_SIZE * 2.0 + 12.0 + 22.0

var _views: Dictionary = {}  # card id -> CardView
var _seats: Dictionary = {}  # player id -> DonkeySeat
var _picked := ""  # the card picked to play
var _sent := ""  # the card sent to the server, shown on the table until the answer comes
var _sent_at := 0
var _trick_no := 0  # the trick on the table as last drawn
var _trick_end_shown := -1  # the trick whose end has been announced
var _leaving: Dictionary = {}  # how the last trick went: {"outcome", "by", ...}, for cards leaving
var _places_seen: Dictionary = {}  # player id -> place already celebrated
var _dealt := false
var _finish_shown := false
var _hand_glow := 0.0
var _time := 0.0

var _felt: Control
var _seat_layer: Control
var _card_layer: Control
var _pile: CardView
var _pile_label: Label
var _info_label: Label
var _pot_label: CoinLabel
var _hint: Label
var _play_button: Button
var _leave_button: Button
var _voice: TableVoice
var _chat: TableChat
var _lead_area: Control  # nothing drawn: where the felt shows the suit led
var _requests: DonkeyRequests
var _result: DonkeyResult
# Request Card, for one layout: whose seat the cards that arrive in our hand come from, and
# whose seat the cards that leave it go to (all our cards, given away)
var _received_from := ""
var _given_to := ""


## What a player is told before leaving a game in progress.
static func leave_warning() -> String:
	var me := Game.donkey.me()
	var stake := int(Game.donkey.state.get("stake", 0))
	if int(me.get("cards", 0)) > 0 and stake > 0 and int(me.get("place", 0)) == 0:
		return "You still hold cards: leaving now counts as losing, and your %s coins go to the Master." % Ui.coins_text(stake)
	if int(me.get("place", 0)) > 0:
		return "You are already safe: leaving now costs you nothing."
	return "Leave this game? You cannot come back to it."


## Draws a suit symbol in a circle of radius `r` round `center`, like the cards do (no font
## glyphs, so no empty boxes on phones).
static func draw_suit(canvas: CanvasItem, suit: String, center: Vector2, r: float, color: Color) -> void:
	match suit:
		"♦":
			canvas.draw_colored_polygon(PackedVector2Array([center + Vector2(0, -r), center + Vector2(r * 0.74, 0), center + Vector2(0, r), center + Vector2(-r * 0.74, 0)]), color)
		"♥":
			canvas.draw_circle(center + Vector2(-r * 0.48, -r * 0.34), r * 0.54, color, true, -1.0, true)
			canvas.draw_circle(center + Vector2(r * 0.48, -r * 0.34), r * 0.54, color, true, -1.0, true)
			canvas.draw_colored_polygon(PackedVector2Array([center + Vector2(-r * 0.96, -r * 0.1), center + Vector2(r * 0.96, -r * 0.1), center + Vector2(0, r)]), color)
		"♠":
			canvas.draw_circle(center + Vector2(-r * 0.46, r * 0.14), r * 0.52, color, true, -1.0, true)
			canvas.draw_circle(center + Vector2(r * 0.46, r * 0.14), r * 0.52, color, true, -1.0, true)
			canvas.draw_colored_polygon(PackedVector2Array([center + Vector2(-r * 0.93, -r * 0.08), center + Vector2(r * 0.93, -r * 0.08), center + Vector2(0, -r)]), color)
			canvas.draw_colored_polygon(PackedVector2Array([center + Vector2(0, r * 0.15), center + Vector2(-r * 0.36, r), center + Vector2(r * 0.36, r)]), color)
		"♣":
			canvas.draw_circle(center + Vector2(0, -r * 0.5), r * 0.46, color, true, -1.0, true)
			canvas.draw_circle(center + Vector2(-r * 0.52, r * 0.16), r * 0.46, color, true, -1.0, true)
			canvas.draw_circle(center + Vector2(r * 0.52, r * 0.16), r * 0.46, color, true, -1.0, true)
			canvas.draw_circle(center, r * 0.3, color, true, -1.0, true)
			canvas.draw_colored_polygon(PackedVector2Array([center + Vector2(0, -r * 0.1), center + Vector2(-r * 0.34, r), center + Vector2(r * 0.34, r)]), color)


func _init() -> void:
	name = "DonkeyTable"
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	_felt = Control.new()
	_felt.name = "DonkeyFelt"
	_felt.set_anchors_preset(Control.PRESET_FULL_RECT)
	_felt.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_felt.draw.connect(_draw_table)
	add_child(_felt)
	_lead_area = Control.new()
	_lead_area.name = "DonkeyLeadArea"
	_lead_area.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_lead_area)

	_pile = CardView.new()
	_pile.name = "DonkeyPile"
	_pile.interactive = false
	_pile.face_down = true
	_pile.set_width(PILE_CARD)
	_pile.visible = false
	add_child(_pile)
	_pile_label = _label("", 16, Ui.PALE_GREEN)
	_pile_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(_pile_label)

	_seat_layer = Control.new()
	_seat_layer.name = "DonkeySeatLayer"
	_seat_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	_seat_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_seat_layer)

	_card_layer = Control.new()
	_card_layer.name = "DonkeyCardLayer"
	_card_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	_card_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_card_layer.draw.connect(_draw_hand_glow)
	add_child(_card_layer)

	# The top bar: leave on the left, the game and the trick, the pot on the right
	_leave_button = Button.new()
	_leave_button.name = "DonkeyLeaveTableButton"
	_leave_button.custom_minimum_size = Vector2(52, 52)
	_leave_button.position = Vector2(18, 14)
	_leave_button.focus_mode = Control.FOCUS_NONE
	_leave_button.tooltip_text = "Leave"
	for state_name: String in ["normal", "hover", "pressed"]:
		_leave_button.add_theme_stylebox_override(state_name, Ui.box(Color(0, 0, 0, 0.5 if state_name == "hover" else 0.36), 26, 0, 0))
	_leave_button.draw.connect(_draw_back_arrow)
	_leave_button.pressed.connect(_on_leave)
	add_child(_leave_button)
	_info_label = _label("", 20, Color.WHITE)
	_info_label.name = "DonkeyInfo"
	_info_label.position = Vector2(84, 16)
	add_child(_info_label)
	var pot_corner := HBoxContainer.new()
	pot_corner.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	pot_corner.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	pot_corner.offset_right = -POT_RIGHT
	pot_corner.offset_top = 20.0
	pot_corner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(pot_corner)
	var pot_word := _label("POT", 18, Ui.PALE_GREEN)
	pot_word.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	pot_corner.add_child(pot_word)
	_pot_label = CoinLabel.new()
	_pot_label.name = "DonkeyPot"
	_pot_label.font_size = 24
	pot_corner.add_child(_pot_label)

	_hint = _label("", 22, Ui.GOLD)
	_hint.name = "DonkeyHint"
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(_hint)
	_play_button = Button.new()
	_play_button.name = "DonkeyPlayButton"
	_play_button.text = "PLAY"
	_play_button.visible = false
	_play_button.custom_minimum_size = Vector2(120, 50)
	_play_button.add_theme_font_size_override("font_size", 22)
	_play_button.pressed.connect(func() -> void: _play(_picked))
	add_child(_play_button)

	# Voice chat, as at the rummy table: Mic and Speaker beside our own picture, and the speaking
	# ring and microphone on every seat. Added before the PLAY button would cover it, and before
	# the result box, which must take every tap once it is up.
	_voice = TableVoice.new()
	_voice.badge_of = func(id: String) -> Object: return _seats.get(id)
	add_child(_voice)
	move_child(_voice, _play_button.get_index())

	# Chat and emoji (two buttons at the top right, bubbles beside the seats), and things to
	# throw at another player's picture (a button beside each opponent), as at the rummy table.
	# Over the cards and PLAY, under the result box.
	_chat = TableChat.new()
	_chat.seat_of = _seat_rect
	add_child(_chat)
	var throws := TableThrows.new()
	throws.badge_of = func(id: String) -> Object: return _seats.get(id)
	throws.keep_clear = _keep_clear
	throws.picker_opened.connect(_chat.close)
	add_child(throws)

	# Request Card: the pills under our neighbours' seats, the box when we are asked, the tags
	# on the seats. Over the chat and the throw buttons, so its box takes the taps; under the result
	_requests = DonkeyRequests.new()
	_requests.seat_of = func(id: String) -> Object: return _seats.get(id)
	add_child(_requests)

	_result = DonkeyResult.new()
	add_child(_result)


func _ready() -> void:
	Ui.tint_button(_play_button, Ui.PRIMARY)
	_info_label.add_theme_font_override("font", Ui.bold_font)
	_hint.add_theme_font_override("font", Ui.bold_font)
	Game.donkey.changed.connect(_refresh)
	Game.action_failed.connect(func(_message: String) -> void:
		# A card the server refused goes back into the hand
		if not _sent.is_empty():
			_sent = ""
			_layout(false))
	resized.connect(func() -> void: _layout(false))
	_refresh()


func _process(delta: float) -> void:
	_time += delta
	var my_turn := Game.donkey.is_my_turn()
	_hand_glow = move_toward(_hand_glow, 1.0 if my_turn else 0.0, delta * 3.0)
	_card_layer.queue_redraw()
	for seat: DonkeySeat in _seats.values():
		seat.is_turn = str(Game.donkey.state.get("turn", "")) == str(seat.player.get("id", "")) and Game.donkey.status() == "playing"
	# A card sent but never answered goes back after a while
	if not _sent.is_empty() and Time.get_ticks_msec() - _sent_at > 4000:
		_sent = ""
		_layout(false)
	if my_turn:
		var seconds := Game.donkey.seconds_left()
		_hint.text = _turn_hint() + ("   %ds" % seconds if seconds > 0 else "")


# ---------- reading the state ----------

func _refresh() -> void:
	var state := Game.donkey.state
	if state.is_empty():
		return  # leaving; the main scene is about to close this screen
	# The card we sent stays on the table until the state shows it gone from our hand
	if not _sent.is_empty() and not Game.donkey.hand().any(func(card: Dictionary) -> bool: return str(card.get("id")) == _sent):
		_sent = ""
	_seat_players()
	var trick_no := int(state.get("trickNo", 0))
	var trick_end: Dictionary = state.get("trickEnd", {})
	if not trick_end.is_empty():
		_leaving = trick_end
		if _trick_end_shown != trick_no:
			_trick_end_shown = trick_no
			_announce_trick_end(trick_end)
	elif trick_no != _trick_no:
		var last: Dictionary = state.get("lastTrick", {})
		if not last.is_empty():
			_leaving = last
			if _trick_end_shown != int(last.get("no", -1)):
				_trick_end_shown = int(last.get("no", -1))
				_announce_trick_end(last)
	_trick_no = trick_no
	if not Game.donkey.playable().has(_picked):
		_picked = ""
	# A request accepted: a whole hand changed owner, and ours may be the one
	for moved: Dictionary in _requests.refresh():
		if moved.taker == Game.player_id:
			_received_from = moved.giver
		elif moved.giver == Game.player_id:
			_given_to = moved.taker
	_layout(true)
	_received_from = ""
	_given_to = ""
	_refresh_texts()
	_celebrate_places()
	if Game.donkey.status() == "finished" and not _finish_shown:
		_finish_shown = true
		_on_finished()


func _refresh_texts() -> void:
	var state := Game.donkey.state
	var parts: Array = ["DONKEY MASTER"]
	if int(state.get("trickNo", 0)) > 0:
		parts.append("Trick %d" % int(state.get("trickNo", 0)))
	var stake := int(state.get("stake", 0))
	parts.append("Entry %s" % Ui.coins_text(stake) if stake > 0 else "Free table")
	_info_label.text = "  ·  ".join(parts)
	_pot_label.amount = int(state.get("pot", 0))
	_pot_label.get_parent().visible = stake > 0
	var out := int(state.get("discarded", 0))
	_pile.visible = out > 0
	_pile_label.visible = out > 0
	_pile_label.text = "%d out" % out
	if not Game.donkey.is_my_turn():
		_hint.text = _waiting_hint()


func _turn_hint() -> String:
	var state := Game.donkey.state
	var must := str(state.get("mustLead", ""))
	if not must.is_empty():
		return "Your turn: lead the %s" % _card_name(must)
	var lead := str(state.get("leadSuit", ""))
	if lead.is_empty():
		return "Your turn: lead any card"
	var follows := false
	for card: Dictionary in Game.donkey.hand():
		if str(card.get("suit", "")) == lead:
			follows = true
			break
	if follows:
		return "Your turn: play a %s" % SUIT_NAMES.get(lead, lead)
	return "No %ss: cut with any card!" % SUIT_NAMES.get(lead, lead)


func _waiting_hint() -> String:
	var state := Game.donkey.state
	var me := Game.donkey.me()
	if Game.donkey.status() == "finished":
		return ""
	if int(me.get("place", 0)) > 0:
		return "You are safe! Watch who ends up the Donkey."
	var turn := str(state.get("turn", ""))
	if turn.is_empty():
		return ""
	if me.get("away", false):
		return "You were away: your cards are played for you. Play a card to come back."
	return "%s is playing..." % Game.donkey.player_name(turn)


func _card_name(card_id: String) -> String:
	for suit: String in SUIT_NAMES:
		if card_id.ends_with(suit):
			var value := card_id.trim_suffix(suit)
			var names := {"A": "ace", "K": "king", "Q": "queen", "J": "jack"}
			return "%s of %ss" % [names.get(value, value), SUIT_NAMES[suit]]
	return card_id


# ---------- where everything goes ----------

# The players in seat order starting from us, so we sit at the bottom and the others follow
# clockwise: up the left side, across the top, down the right.
func _ordered_players() -> Array:
	var players := Game.donkey.players()
	var mine := 0
	for index in players.size():
		if str(players[index].get("id", "")) == Game.player_id:
			mine = index
	var ordered: Array = []
	for step in players.size():
		ordered.append(players[(mine + step) % players.size()])
	return ordered


func _table_center() -> Vector2:
	return Vector2(size.x / 2.0, size.y * 0.42)


func _table_radii() -> Vector2:
	return Vector2(minf(size.x * 0.36, 470.0), size.y * 0.24)


# The angle (radians, screen y down) at which a seat sits round the table; ours is straight down.
func _seat_angle(order: int, count: int) -> float:
	if order == 0:
		return PI / 2.0
	if count <= 2:
		return PI * 1.5
	var from := deg_to_rad(166.0)
	var to := deg_to_rad(374.0)
	return lerpf(from, to, float(order - 1) / float(count - 2))


func _seat_spot(order: int, count: int) -> Vector2:
	if order == 0:
		return Vector2(84.0, size.y - HAND_CARD * CardView.HEIGHT_RATIO - 118.0)
	var angle := _seat_angle(order, count)
	var reach := Vector2(size.x / 2.0 - 104.0, size.y * 0.29)
	return Vector2(size.x / 2.0, size.y * 0.385) + Vector2(cos(angle) * reach.x, sin(angle) * reach.y)


# Where a player's card lies in the trick: toward their seat from the middle of the table.
func _trick_spot(player_id: String) -> Vector2:
	var ordered := _ordered_players()
	for order in ordered.size():
		if str(ordered[order].get("id", "")) == player_id:
			var angle := _seat_angle(order, ordered.size())
			return _table_center() + Vector2(cos(angle) * 118.0, sin(angle) * 58.0)
	return _table_center()


func _seat_players() -> void:
	var ordered := _ordered_players()
	var present := {}
	for order in ordered.size():
		var player: Dictionary = ordered[order]
		var id := str(player.get("id", ""))
		present[id] = true
		var seat: DonkeySeat = _seats.get(id)
		if seat == null:
			seat = DonkeySeat.new()
			seat.name = "DonkeySeat_" + id
			_seat_layer.add_child(seat)
			_seats[id] = seat
			Ui.pop_in.call_deferred(seat, 0.05 * order)
		seat.player = player
		seat.place_at(_seat_spot(order, ordered.size()))
	for id: String in _seats.keys():
		if not present.has(id):
			_seats[id].queue_free()
			_seats.erase(id)


# Where a player sits on screen, for the chat bubbles: their seat, or nothing.
func _seat_rect(user_id: String) -> Rect2:
	var seat: DonkeySeat = _seats.get(user_id)
	if seat == null or not seat.is_visible_in_tree():
		return Rect2()
	return seat.get_global_rect()


# What the buttons for throwing things must never cover: what a player taps or reads during
# a turn, the cards on the table and in the hand among them.
func _keep_clear() -> Array:
	var controls: Array = [
		_leave_button, _info_label, _pot_label.get_parent(), _hint, _play_button, _pile, _pile_label,
		_voice, _lead_area,
		_chat.get_node_or_null("ChatButtons"), _chat.get_node_or_null("ChatPanel"), _chat.get_node_or_null("EmojiPanel"),
	]
	controls.append_array(_card_layer.get_children())
	controls.append_array(_requests.controls())
	return controls


# Every card to where the state says it is: the hand along the bottom, the trick in the
# middle; the ones in neither are leaving the table (to whoever picked up the trick, or out of
# the game). `animate` false puts them in place at once (the window changed size).
func _layout(animate: bool) -> void:
	if size.x <= 0.0:
		return
	# The voice switches right of our own seat, level with its picture: clear of the seat to
	# the left above it, and of the cards and the PLAY button rising from the hand below
	var mine := _seat_spot(0, 1)
	_voice.position = Vector2(mine.x + DonkeySeat.SIZE.x / 2.0 + 6.0, mine.y - TableVoice.BUTTON_SIZE)
	var state := Game.donkey.state
	# Where the felt shows the suit led (see _draw_table), for the throw buttons to keep clear of
	_lead_area.position = _table_center() + Vector2(-_table_radii().x + 92.0, 0.0) - Vector2(40.0, 34.0)
	_lead_area.size = Vector2(80.0, 96.0)
	_lead_area.visible = not str(state.get("leadSuit", "")).is_empty() and Game.donkey.status() == "playing"
	var hand: Array = Game.donkey.hand().filter(func(card: Dictionary) -> bool: return str(card.get("id")) != _sent)
	var trick: Array = state.get("trick", []).duplicate()
	if not _sent.is_empty():
		trick.append({"playerId": Game.player_id, "card": {"id": _sent}})
	var playable := Game.donkey.playable()
	var wanted := {}
	var deal_order := 0

	# Our hand, fanned along the bottom; the cards we may play stand up, the others are dimmed
	var count := hand.size()
	var hand_width := HAND_CARD
	var room := size.x - 48.0
	var step := 0.0 if count < 2 else minf(HAND_CARD * 0.66, (room - hand_width) / (count - 1))
	var start_x := (size.x - (hand_width + step * maxi(0, count - 1))) / 2.0
	var base_y := size.y - CardView.height_for(HAND_CARD) - 14.0
	for index in count:
		var card: Dictionary = hand[index]
		var id := str(card.get("id", ""))
		wanted[id] = true
		var view := _view_for(card, _hand_origin())
		var fresh := not view.has_meta("in_hand")
		view.set_meta("in_hand", true)
		if view.has_meta("in_trick"):
			view.remove_meta("in_trick")
		view.set_width(HAND_CARD)
		view.interactive = true
		view.face_down = false
		view.z_index = index
		var may := playable.has(id)
		view.highlighted = may and _picked.is_empty()
		view.selected = id == _picked
		view.modulate = Color.WHITE if may or playable.is_empty() else Color(0.6, 0.6, 0.6)
		var lift := PICK_LIFT if id == _picked else (HAND_LIFT if may else 0.0)
		var target := Vector2(start_x + step * index, base_y - lift)
		view.rotation = 0.0
		if fresh and animate:
			# Dealt, or picked up: in from the middle of the table, one after another
			var delay := DEAL_STAGGER * deal_order if not _dealt else 0.0
			deal_order += 1
			view.glide_to(target, FLY, delay)
			view.reveal_after(delay + FLY * 0.5)
			Sound.play_later("card", delay, -8.0)
		elif animate:
			view.glide_to(target, GLIDE)
		else:
			view.stop_gliding()
			view.position = target
	if count > 0:
		_dealt = true
	# A tap goes to the card that comes later among the layer's children, whatever z_index
	# says, so the children follow the hand from left to right. (A card picked up from a trick
	# was made later; left where it was, it took the taps meant for the card to its right.)
	for index in count:
		_card_layer.move_child(_views[str(hand[index].get("id", ""))], index)

	# The trick, each card toward the seat of whoever played it, in the order played
	var highest := str(state.get("trickEnd", {}).get("highest", ""))
	for index in trick.size():
		var play: Dictionary = trick[index]
		var card: Dictionary = play.get("card", {})
		var id := str(card.get("id", ""))
		var player_id := str(play.get("playerId", ""))
		wanted[id] = true
		var seat: DonkeySeat = _seats.get(player_id)
		var origin := seat.avatar_center() - global_position if seat != null else _table_center()
		var view := _view_for(card, origin)
		var arriving := not view.has_meta("in_trick")
		view.set_meta("in_trick", true)
		if view.has_meta("in_hand"):
			view.remove_meta("in_hand")
		view.interactive = false
		view.selected = false
		view.modulate = Color.WHITE
		view.highlighted = player_id == highest and not highest.is_empty()
		view.z_index = 100 + index
		var spot := _trick_spot(player_id)
		var target := spot - Vector2(TRICK_CARD, CardView.height_for(TRICK_CARD)) / 2.0
		var turn_to := deg_to_rad(float(absi(hash(id)) % 25) - 12.0)
		if arriving and animate:
			var from_hand := view.size.x >= HAND_CARD - 1.0
			view.set_width(TRICK_CARD)
			if not from_hand:
				# Someone else's card: from their picture, small and face down, turning over on the way
				view.scale = Vector2(0.45, 0.45)
				view.reveal_after(FLY * 0.4)
			var tween := view.create_tween().set_parallel()
			tween.tween_property(view, "scale", Vector2.ONE, FLY).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
			tween.tween_property(view, "rotation", turn_to, FLY)
			view.glide_to(target, FLY)
			Sound.play("card", 0.0 if player_id == Game.player_id else -4.0)
		else:
			view.set_width(TRICK_CARD)
			view.rotation = turn_to
			if animate:
				view.glide_to(target, GLIDE)
			else:
				view.position = target

	# The rest leave the table: to the player who picked up the trick, or out of the game
	for id: String in _views.keys():
		if wanted.has(id):
			continue
		var view: CardView = _views[id]
		_views.erase(id)
		_send_away(view)

	# The pile of cards out of the game, at the right end of the table
	var center := _table_center()
	var radii := _table_radii()
	_pile.position = center + Vector2(radii.x - 70.0, -10.0) - _pile.size / 2.0
	_pile.rotation = deg_to_rad(8.0)
	_pile_label.position = _pile.position + Vector2(-20.0, _pile.size.y + 2.0)
	_pile_label.size = Vector2(_pile.size.x + 40.0, 22.0)
	_hint.size = Vector2(size.x * 0.6, 30.0)
	_hint.position = Vector2(size.x * 0.2, base_y - PICK_LIFT - 44.0)

	# PLAY over the card picked
	_play_button.visible = not _picked.is_empty() and _views.has(_picked)
	if _play_button.visible:
		var picked: CardView = _views[_picked]
		var target_x := start_x + step * _index_in(hand, _picked)
		_play_button.position = Vector2(clampf(target_x + HAND_CARD / 2.0 - 60.0, 8.0, size.x - 128.0), base_y - PICK_LIFT - 58.0)
		_play_button.z_index = picked.z_index + 1
		_hint.visible = false
	else:
		_hint.visible = true
	_felt.queue_redraw()


# Where a card new in our hand comes from: the seat of a player who gave us their cards, or the
# middle of the table (dealt, or a trick picked up).
func _hand_origin() -> Vector2:
	var seat: DonkeySeat = _seats.get(_received_from)
	return seat.avatar_center() - global_position if seat != null else _table_center()


func _index_in(cards: Array, card_id: String) -> int:
	for index in cards.size():
		if str(cards[index].get("id", "")) == card_id:
			return index
	return 0


# The view of a card, made (at `origin`) if it is not on the table yet.
func _view_for(card: Dictionary, origin: Vector2) -> CardView:
	var id := str(card.get("id", ""))
	var view: CardView = _views.get(id)
	if view == null:
		view = CardView.new()
		view.name = "DonkeyCard_" + id.validate_node_name()
		view.set_width(TRICK_CARD)
		view.position = origin - view.size / 2.0
		view.tapped.connect(_on_card_tapped)
		_card_layer.add_child(view)
		_views[id] = view
	if card.size() > 1:
		view.card = card
	return view


# A card that left the table flies to whoever picked up the trick, or to the pile.
func _send_away(view: CardView) -> void:
	view.interactive = false
	view.stop_gliding()
	var outcome := str(_leaving.get("outcome", "discard"))
	var to := _pile.position + _pile.size / 2.0
	var shrink := Vector2(PILE_CARD / maxf(1.0, view.size.x), PILE_CARD / maxf(1.0, view.size.x))
	var receiver: DonkeySeat = _seats.get(_given_to)
	if view.has_meta("in_hand") and receiver != null:
		# Our cards, given away on a request: to the seat of the player who asked
		to = receiver.avatar_center() - global_position
		shrink = Vector2(0.4, 0.4)
	elif outcome == "pickup":
		var seat: DonkeySeat = _seats.get(str(_leaving.get("by", "")))
		if seat != null:
			to = seat.avatar_center() - global_position
			shrink = Vector2(0.4, 0.4)
	var tween := view.create_tween().set_parallel()
	tween.tween_property(view, "position", to - view.size / 2.0, FLY).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	tween.tween_property(view, "scale", shrink, FLY)
	tween.tween_property(view, "modulate:a", 0.0, FLY).set_delay(FLY * 0.5)
	tween.chain().tween_callback(view.queue_free)


# ---------- the moments ----------

# A trick is over: a cut (someone picks it all up) or everyone followed (the cards go out).
func _announce_trick_end(end: Dictionary) -> void:
	var outcome := str(end.get("outcome", ""))
	var by := str(end.get("by", ""))
	var seat: DonkeySeat = _seats.get(by)
	if outcome == "pickup":
		var cutter := str(end.get("cutBy", ""))
		var cut_at := _trick_spot(cutter) + global_position
		Fx.float_text(cut_at + Vector2(0, -60), "CUT!", Color("ff5252"), 46)
		Fx.shake(6.0, 0.25)
		Sound.play("warning")
		var who := "You pick" if by == Game.player_id else "%s picks" % Game.donkey.player_name(by)
		var trick_size := (Game.donkey.state.get("trick", []) as Array).size()
		if trick_size == 0:
			trick_size = (end.get("plays", []) as Array).size()
		Ui.notify("warning" if by == Game.player_id else "info", "%s up %d cards" % [who, trick_size])
		if seat != null:
			get_tree().create_timer(1.0).timeout.connect(func() -> void:
				if is_instance_valid(seat):
					seat.pulse()
					Fx.ring(seat.avatar_center(), Color("ff5252"), 70.0))
	elif outcome == "discard":
		Fx.ring(_table_center() + global_position, Color.WHITE, 120.0, 0.5)
		Sound.play_later("whoosh", 0.9)


# Someone emptied their hand: the Master gets a crown, the others a cheer.
func _celebrate_places() -> void:
	for player: Dictionary in Game.donkey.players():
		var id := str(player.get("id", ""))
		var place := int(player.get("place", 0))
		if place <= 0 or _places_seen.has(id) or player.get("donkey", false):
			continue
		_places_seen[id] = place
		var seat: DonkeySeat = _seats.get(id)
		if seat == null:
			continue
		var at := seat.avatar_center()
		Fx.sparkle(at, Fx.GOLD if place == 1 else Color("69f0ae"), 22)
		var mine := id == Game.player_id
		if place == 1:
			Fx.float_text(at + Vector2(0, -70), "MASTER!", Fx.GOLD, 40)
			Sound.play("win" if mine else "sparkle")
			if mine and Game.donkey.status() == "playing":
				Fx.banner("YOU ARE THE MASTER!", Fx.GOLD, 0.8)
		else:
			Fx.float_text(at + Vector2(0, -70), "SAFE!", Color("69f0ae"), 34)
			Sound.play("sparkle")
			if mine and Game.donkey.status() == "playing":
				Fx.banner("YOU ARE SAFE!", Color("69f0ae"), 0.6)


func _on_finished() -> void:
	var state := Game.donkey.state
	var donkey_id := str(state.get("donkeyId", ""))
	_picked = ""
	if not donkey_id.is_empty():
		var seat: DonkeySeat = _seats.get(donkey_id)
		var at := seat.avatar_center() if seat != null else _table_center() + global_position
		_donkey_jump(at)
		if donkey_id == Game.player_id:
			Sound.play("lose")
			Fx.banner("YOU ARE THE DONKEY!", Color("ff8a65"), 0.9)
		else:
			Sound.play_later("lose", 0.2, -6.0)
			Fx.banner("%s IS THE DONKEY!" % Game.donkey.player_name(donkey_id).to_upper(), Color("ff8a65"), 0.8)
	if str(state.get("masterId", "")) == Game.player_id:
		Fx.victory(true)
	get_tree().create_timer(RESULT_DELAY).timeout.connect(func() -> void:
		if is_inside_tree() and Game.donkey.status() == "finished":
			_result.show_result())


# The donkey kicks its way across the table to the loser's picture.
func _donkey_jump(at: Vector2) -> void:
	var donkey := TextureRect.new()
	donkey.texture = DonkeyHome.picture("donkey")
	donkey.mouse_filter = Control.MOUSE_FILTER_IGNORE
	donkey.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	donkey.size = Vector2(170, 170)
	donkey.pivot_offset = donkey.size / 2.0
	donkey.z_index = 300
	donkey.position = Vector2(-200.0, size.y * 0.3)
	add_child(donkey)
	var land := at - global_position - donkey.size / 2.0
	var tween := donkey.create_tween()
	for hop in 3:
		var t := float(hop + 1) / 3.0
		var step_to := Vector2(-200.0, size.y * 0.3).lerp(land, t)
		tween.tween_property(donkey, "position", step_to - Vector2(0, 60), 0.18).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		tween.parallel().tween_property(donkey, "rotation", -0.35, 0.18)
		tween.tween_property(donkey, "position", step_to, 0.16).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
		tween.parallel().tween_property(donkey, "rotation", 0.15, 0.16)
	tween.tween_callback(func() -> void:
		Fx.shake(10.0, 0.3)
		Fx.ring(at, Color("ff8a65"), 110.0))
	tween.tween_property(donkey, "scale", Vector2(1.25, 1.25), 0.15)
	tween.tween_property(donkey, "scale", Vector2.ONE, 0.2)
	tween.tween_interval(1.4)
	tween.tween_property(donkey, "modulate:a", 0.0, 0.4)
	tween.tween_callback(donkey.queue_free)


# ---------- our moves ----------

func _on_card_tapped(card_id: String) -> void:
	if not Game.donkey.hand().any(func(card: Dictionary) -> bool: return str(card.get("id")) == card_id):
		return
	if not Game.donkey.is_my_turn():
		Sound.play("deselect")
		Ui.notify("info", "Wait for your turn")
		return
	if not Game.donkey.playable().has(card_id):
		Sound.play("wrong")
		var view: CardView = _views.get(card_id)
		if view != null:
			_wiggle(view)
		var lead := str(Game.donkey.state.get("leadSuit", ""))
		var must := str(Game.donkey.state.get("mustLead", ""))
		if not must.is_empty():
			Ui.notify("warning", "Lead the %s first" % _card_name(must))
		elif not lead.is_empty():
			Ui.notify("warning", "Follow suit: play a %s" % SUIT_NAMES.get(lead, lead))
		return
	if _picked == card_id:
		_play(card_id)
		return
	_picked = card_id
	Sound.play("select")
	_layout(true)


func _play(card_id: String) -> void:
	if card_id.is_empty() or not Game.donkey.playable().has(card_id):
		return
	_picked = ""
	_sent = card_id
	_sent_at = Time.get_ticks_msec()
	_layout(true)
	Game.donkey.play(card_id)


func _wiggle(view: CardView) -> void:
	var tween := view.create_tween()
	for side in [1.0, -1.0, 1.0, 0.0]:
		tween.tween_property(view, "rotation", deg_to_rad(5.0 * side), 0.05)


func _on_leave() -> void:
	if Game.donkey.status() == "finished":
		Game.donkey.leave()
	else:
		Ui.confirm("Leave game", leave_warning(), "Leave", Game.donkey.leave)


# ---------- pictures drawn in code ----------

# The floor, and the oval table with its wooden rim; the suit led shows in the middle.
func _draw_table() -> void:
	var center := _table_center()
	var radii := _table_radii()
	_ellipse(center + Vector2(0, 10), radii + Vector2(30, 26), Color(0, 0, 0, 0.35))
	_ellipse(center, radii + Vector2(26, 22), WOOD_DARK)
	_ellipse(center, radii + Vector2(20, 16), WOOD)
	_ellipse(center, radii, FELT_EDGE)
	_ellipse(center, radii * 0.94, FELT_LIGHT.darkened(0.12))
	_ellipse(center + Vector2(0, -radii.y * 0.08), radii * 0.7, FELT_LIGHT)
	var line := PackedVector2Array()
	for index in 65:
		var angle := TAU * index / 64.0
		line.append(center + Vector2(cos(angle) * (radii.x - 18.0), sin(angle) * (radii.y - 14.0)))
	_felt.draw_polyline(line, Color(1, 1, 1, 0.12), 2.0, true)

	var lead := str(Game.donkey.state.get("leadSuit", ""))
	if not lead.is_empty() and Game.donkey.status() == "playing":
		var red := lead in ["♥", "♦"]
		var spot := center + Vector2(-radii.x + 92.0, 0.0)
		_felt.draw_circle(spot, 34.0, Color(1, 1, 1, 0.9), true, -1.0, true)
		draw_suit(_felt, lead, spot, 20.0, CardView.RED if red else CardView.BLACK)
		_felt.draw_string(Ui.bold_font, spot + Vector2(-40, 54), "LEAD", HORIZONTAL_ALIGNMENT_CENTER, 80.0, 15, Color(1, 1, 1, 0.8))


func _ellipse(center: Vector2, radii: Vector2, color: Color) -> void:
	var points := PackedVector2Array()
	for index in 96:
		var angle := TAU * index / 96.0
		points.append(center + Vector2(cos(angle) * radii.x, sin(angle) * radii.y))
	_felt.draw_colored_polygon(points, color)
	points.append(points[0])
	_felt.draw_polyline(points, color, 1.5, true)


# Our turn: a gold light breathing under the hand.
func _draw_hand_glow() -> void:
	if _hand_glow <= 0.0 or Game.donkey.hand().is_empty():
		return
	var top := size.y - CardView.height_for(HAND_CARD) - 14.0 - HAND_LIFT - 10.0
	var breath := 0.5 + 0.5 * sin(_time * 4.0)
	var glow := Ui.box(Color(Ui.GOLD, 0.04 * _hand_glow), 26, 0, 0)
	glow.border_color = Color(Ui.GOLD, (0.5 + 0.4 * breath) * _hand_glow)
	glow.set_border_width_all(3)
	glow.shadow_color = Color(Ui.GOLD, 0.4 * _hand_glow)
	glow.shadow_size = int(6.0 + 8.0 * breath)
	_card_layer.draw_style_box(glow, Rect2(Vector2(12.0, top), Vector2(size.x - 24.0, size.y - top - 4.0)))


func _draw_back_arrow() -> void:
	var center := _leave_button.size / 2.0
	_leave_button.draw_line(center + Vector2(10, 0), center + Vector2(-10, 0), Color.WHITE, 5.0, true)
	_leave_button.draw_polyline(PackedVector2Array([center + Vector2(-1, -10), center + Vector2(-11, 0), center + Vector2(-1, 10)]), Color.WHITE, 5.0, true)


func _label(text: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.6))
	label.add_theme_constant_override("outline_size", 4)
	return label
