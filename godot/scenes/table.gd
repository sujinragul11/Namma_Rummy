extends Control
## The card table: opponents, joker, deck, open pile, the player's hand and the action buttons.
## Everything shown comes from Game.state; this screen draws it and sends the player's moves.
##
## Cards can be tapped to select them (then Group / Discard / Declare), or picked up and
## carried: onto another group, beside either end of the hand or between two groups to start
## a new group, or onto the open pile to discard. Each change on the table is shown as a card travelling, by comparing
## the new state with the one before it.

const PILE_CARD_WIDTH := 104.0
const MINI_CARD_WIDTH := 40.0
const GROUP_GAP := 26.0
const HAND_PADDING := 28.0
const SELECT_LIFT := 26.0
const GROUP_LABEL_HEIGHT := 30.0
const MOVE_SECONDS := 0.25
const ARRIVE_SECONDS := 0.32
const FLY_SECONDS := 0.4
const DEAL_STAGGER := 0.05
const OUTCOME_LABELS := {"winner": "Winner", "lost": "Lost", "dropped": "Dropped"}
const DARK_TEXT := Color("333333")
const DIM_TEXT := Color("666666")
const WIN_TEXT := Color("2e7d32")
const VALID_LABEL := Color("2e7d32")
const INVALID_LABEL := Color("8d6e63")
const ROUND_BUTTON := 52.0
## Where the other players sit, as fractions of the screen: around the far side of the
## oval, the way you would see them from your own seat. The badge is centred on the spot.
const SEATS := {
	1: [Vector2(0.5, 0.09)],
	2: [Vector2(0.16, 0.4), Vector2(0.84, 0.4)],
	3: [Vector2(0.15, 0.42), Vector2(0.5, 0.09), Vector2(0.85, 0.42)],
	4: [Vector2(0.14, 0.44), Vector2(0.32, 0.1), Vector2(0.68, 0.1), Vector2(0.86, 0.44)],
	5: [Vector2(0.14, 0.44), Vector2(0.3, 0.1), Vector2(0.5, 0.09), Vector2(0.7, 0.1), Vector2(0.86, 0.44)],
}

var _cards: Dictionary = {}  # card id -> CardView in the hand
var _selected: Array = []  # ids of the selected cards
var _group_labels: Array[Button] = []
## Where each group sits in the hand, for dropping a carried card:
## {"left": x, "right": x, "ids": [card ids], "xs": [left edge of each card]}
var _spans: Array = []
var _badges: Dictionary = {}  # opponent id -> PlayerBadge
var _card_width := 120.0
var _laid_out := false  # false until the first layout pass has given the nodes their places
var _seen: Dictionary = {}  # what the previous update showed, to animate what changed since
var _dragging_id := ""
var _drag_offset := Vector2.ZERO
var _marker: ColorRect
var _confetti: CPUParticles2D
var _prize: CoinLabel
var _result_key := ""
var _was_my_turn := false
var _last_tick := -1  # the second of the turn clock that last ticked aloud
var _last_beep := -1  # the same for the countdown to the next round
var _valid_melds: Dictionary = {}  # the melds in the hand at the last layout, to notice new ones
var _quiet_melds := true  # melds that come with the deal are not announced
var _deal_ends_at := 0  # Time.get_ticks_msec() when the last dealt card has arrived
var _joker_was_hidden := false  # Close Joker: the joker lay face down at the last update
var _declare_submits := false  # the Declare button currently reads "Submit" (see _refresh_actions)
var _my_coins: CoinLabel
var _slot_lit := false  # the Declare slot is lit while a card is carried over it

@onready var _leave_button: Button = %LeaveButton
@onready var _room_label: Label = %RoomLabel
@onready var _opponents: Control = %Opponents
@onready var _declare_slot: PanelContainer = %DeclareSlot
@onready var _joker_card: CardView = %JokerCard
@onready var _joker_label: Label = %JokerLabel
@onready var _deck_card: CardView = %DeckCard
@onready var _deck_label: Label = %DeckLabel
@onready var _open_card: CardView = %OpenCard
@onready var _status_label: Label = %StatusLabel
@onready var _clock_label: Label = %ClockLabel
@onready var _total_label: Label = %TotalLabel
@onready var _hand_area: Control = %HandArea
@onready var _my_badge: PlayerBadge = %MyBadge
@onready var _my_coins_pill: PanelContainer = %MyCoinsPill
@onready var _sort_button: Button = %SortButton
@onready var _group_button: Button = %GroupButton
@onready var _discard_button: Button = %DiscardButton
@onready var _declare_button: Button = %DeclareButton
@onready var _drop_button: Button = %DropButton
@onready var _fly_layer: Control = %FlyLayer
@onready var _result_overlay: Control = %ResultOverlay
@onready var _result_panel: Control = %ResultPanel
@onready var _result_title: Label = %ResultTitle
@onready var _result_scroll: ScrollContainer = %ResultScroll
@onready var _result_rows: VBoxContainer = %ResultRows
@onready var _next_round_label: Label = %NextRoundLabel
@onready var _leave_game_button: Button = %LeaveGameButton
@onready var _play_again_button: Button = %PlayAgainButton
@onready var _back_button: Button = %BackButton


func _ready() -> void:
	Ui.tint_button(_group_button, Ui.TEAL)
	Ui.tint_button(_discard_button, Ui.BLUE)
	Ui.tint_button(_declare_button, Ui.ORANGE)
	Ui.tint_button(_drop_button, Ui.RED)
	Ui.tint_button(_back_button, Ui.PRIMARY)
	Ui.tint_button(_leave_game_button, Ui.RED)
	_status_label.add_theme_font_override("font", Ui.bold_font)
	_result_title.add_theme_font_override("font", Ui.bold_font)
	_joker_card.interactive = false
	_deck_card.face_down = true
	_dress_table()

	_marker = ColorRect.new()
	_marker.color = Ui.AMBER
	_marker.visible = false
	_marker.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hand_area.add_child(_marker)
	_confetti = _make_confetti()
	_result_overlay.add_child(_confetti)
	# At a table played for coins the result says where the pot goes, right under its title
	_prize = CoinLabel.new()
	_prize.name = "PrizeLabel"
	_prize.font_size = 26
	_prize.text_color = Color("b26a00")  # gold would not show on the white panel
	_prize.visible = false
	_result_title.add_sibling(_prize)

	_leave_button.pressed.connect(_on_leave)
	_declare_slot.gui_input.connect(_on_declare_slot_input)
	_leave_game_button.pressed.connect(_on_leave)
	_back_button.pressed.connect(Game.leave)
	Ui.tint_button(_play_again_button, Ui.TEAL)
	_play_again_button.pressed.connect(Game.play_again)
	_sort_button.pressed.connect(_on_sort)
	_group_button.pressed.connect(_on_group)
	_discard_button.pressed.connect(_on_discard)
	_declare_button.pressed.connect(_on_declare)
	_drop_button.pressed.connect(_on_drop)
	_deck_card.tapped.connect(_on_pile_tapped.bind(false))
	_open_card.tapped.connect(_on_pile_tapped.bind(true))
	_hand_area.resized.connect(_place_cards.bind(false))
	_opponents.resized.connect(_place_opponents)

	Game.state_changed.connect(_refresh)
	Game.connection_changed.connect(_refresh)
	Game.busy_changed.connect(_refresh_actions)
	Game.coins_changed.connect(_refresh_coins)
	Game.action_failed.connect(_on_action_failed)
	# Cards fly in from the deck, so wait until the deck has been given its place on screen
	get_tree().process_frame.connect(_on_first_frame, CONNECT_ONE_SHOT)


func _on_first_frame() -> void:
	_laid_out = true
	_refresh()


# The dressing of the table: round buttons and dark pills at the top, the stacked deck with
# the joker tucked under it, the Declare slot, the player's own pill with the coins.
func _dress_table() -> void:
	_leave_button.custom_minimum_size = Vector2(ROUND_BUTTON, ROUND_BUTTON)
	_leave_button.focus_mode = Control.FOCUS_NONE
	for state_name: String in ["normal", "hover", "pressed"]:
		var round_box := StyleBoxFlat.new()
		round_box.bg_color = Color(0, 0, 0, 0.5 if state_name == "hover" else 0.36)
		round_box.set_corner_radius_all(int(ROUND_BUTTON / 2.0))
		round_box.anti_aliasing = true
		_leave_button.add_theme_stylebox_override(state_name, round_box)
	_leave_button.draw.connect(_draw_leave_arrow)

	for pill: Label in [_room_label, _total_label, _deck_label]:
		pill.add_theme_stylebox_override("normal", Ui.box(Color(0, 0, 0, 0.45), 14, 12, 3))
	_deck_label.add_theme_font_override("font", Ui.bold_font)
	for back: CardView in [%DeckBack1, %DeckBack2]:
		back.face_down = true
		back.interactive = false
	_light_slot(false)
	%DeclareWord.add_theme_font_override("font", Ui.bold_font)
	%HereWord.add_theme_font_override("font", Ui.bold_font)

	_my_badge.pill = true
	_my_coins_pill.add_theme_stylebox_override("panel", Ui.box(Color(0, 0, 0, 0.5), 22, 16, 6))
	_my_coins = CoinLabel.new()
	_my_coins.name = "MyCoins"
	_my_coins.font_size = 22
	_my_coins_pill.add_child(_my_coins)
	_refresh_coins()


func _refresh_coins() -> void:
	_my_coins.amount = Game.coins


# The Declare slot: a pale box on the felt; lit when a card is carried over it.
func _light_slot(lit: bool) -> void:
	_slot_lit = lit
	var style := Ui.box(Color(1, 0.85, 0.4, 0.3) if lit else Color(1, 1, 1, 0.1), 16, 6, 6)
	style.border_color = Ui.GOLD if lit else Color(1, 1, 1, 0.4)
	style.set_border_width_all(3 if lit else 2)
	_declare_slot.add_theme_stylebox_override("panel", style)


# A chevron pointing left: out of the table.
func _draw_leave_arrow() -> void:
	var middle := _leave_button.size / 2.0
	var points := PackedVector2Array([middle + Vector2(6, -11), middle + Vector2(-6, 0), middle + Vector2(6, 11)])
	_leave_button.draw_polyline(points, Color.WHITE, 4.0, true)
	_leave_button.draw_line(middle + Vector2(-6, 0), middle + Vector2(12, 0), Color.WHITE, 4.0, true)


# Seats the other players around the far side of the table.
func _place_opponents() -> void:
	var seated: Array = []
	for player: Dictionary in Game.players():
		var badge: PlayerBadge = _badges.get(str(player.get("id", "")))
		if badge != null:
			seated.append(badge)
	if seated.is_empty():
		return
	var spots: Array = SEATS.get(seated.size(), SEATS[5])
	for index in seated.size():
		var badge: PlayerBadge = seated[index]
		var badge_size := badge.get_combined_minimum_size()
		var spot: Vector2 = spots[mini(index, spots.size() - 1)] * _opponents.size
		var at := spot - badge_size / 2.0
		badge.position = at.clamp(Vector2(8.0, 8.0), _opponents.size - badge_size - Vector2(8.0, 8.0))


func _exit_tree() -> void:
	Fx.danger(false)  # the red edges belong to this screen's clock
	Fx.clear()  # and a winner's fireworks do not follow the player to the next screen


func _process(_delta: float) -> void:
	var playing := Game.status() == "playing"
	_clock_label.visible = playing and Game.turn_ends_at > 0
	if _clock_label.visible:
		var seconds := Game.seconds_until(Game.turn_ends_at)
		_clock_label.text = "%ds" % seconds
		_clock_label.modulate = Color("ff8a80") if seconds <= 5 else Color.WHITE
		# The last five seconds of our own turn tick, a little higher each time
		if seconds > 5:
			_last_tick = -1
		elif _on_the_clock() and seconds > 0 and seconds != _last_tick:
			_last_tick = seconds
			Sound.play("tick", 0.0, 1.0 + (5 - seconds) * 0.06)
			Ui.pulse(_clock_label, 1.3)
			if seconds <= 3:
				Fx.shake(3.0, 0.15)
	# Red creeps in from the edges of the screen while our own time runs out
	Fx.danger(_clock_label.visible and _on_the_clock() and Game.seconds_until(Game.turn_ends_at) <= 5)

	if _result_overlay.visible and Game.status() == "round_over":
		var prefix := "You are out of the match. " if Game.me().get("eliminated", false) else ""
		var until_deal := Game.seconds_until(Game.next_round_at)
		_next_round_label.text = "%sNext %s in %ds" % [prefix, "deal" if Game.deals() > 0 else "round", until_deal]
		if until_deal > 3:
			_last_beep = -1
		elif until_deal > 0 and until_deal != _last_beep:
			_last_beep = until_deal
			Sound.play("beep")


# True while the clock is counting our own time: our turn, or our time to arrange our cards
# after someone else's declaration.
func _on_the_clock() -> bool:
	return Game.is_my_turn() or Game.arranging()


# ---------- drawing the table ----------

func _refresh() -> void:
	var state := Game.state
	if state.is_empty() or not _laid_out:
		return  # leaving the table (the main scene is about to close this screen), or not ready

	var is_pool := Game.is_pool()
	var deals := Game.deals()
	_room_label.text = "%s  ·  %s" % [state.get("roomCode", ""), Game.game_name()]
	if is_pool:
		_room_label.text += "  ·  Round %d" % int(state.get("round", 1))
	elif deals > 0:
		_room_label.text += "  ·  %s" % _deal_name(int(state.get("round", 1)))
	if Game.point_value() > 0:
		_room_label.text += "  ·  %s coins a point" % Ui.coins_text(Game.point_value())
	elif Game.stake() > 0:
		_room_label.text += "  ·  Pot %s" % Ui.coins_text(Game.pot())
	_total_label.visible = is_pool or deals > 0
	if deals > 0:
		_total_label.text = "Your chips: %d" % int(Game.me().get("chips", 0))
	else:
		_total_label.text = "Your total: %d" % int(Game.me().get("totalScore", 0))

	_refresh_opponents(is_pool)
	_refresh_piles()
	_animate_opponents()
	_sync_hand()
	_refresh_status()
	_refresh_actions()
	_announce_declaration()
	_refresh_result(is_pool)
	_remember()


func _refresh_opponents(is_pool: bool) -> void:
	var playing := Game.status() == "playing"
	var declared_by := Game.declared_by()
	var present := {}
	for player: Dictionary in Game.players():
		var id := str(player.get("id", ""))
		if id == Game.player_id:
			continue
		present[id] = true
		var badge: PlayerBadge = _badges.get(id)
		if badge == null:
			badge = PlayerBadge.new()
			badge.name_width = 150.0
			badge.pill = true
			_opponents.add_child(badge)
			_badges[id] = badge

		var info := "%d cards" % int(player.get("handCount", 0))
		var sitting_out := true
		if player.get("eliminated", false):
			info = "Out"
		elif player.get("status") == "dropped":
			info = "Dropped"
		elif not player.get("connected", true):
			info = "Offline"
		else:
			sitting_out = false
			# After a declaration: who declared, and who is still arranging their cards
			if id == declared_by:
				info = "Declared"
			elif not declared_by.is_empty():
				info = "Cards in" if player.get("submitted", false) else "Arranging..."
		if is_pool:
			info += "  ·  %d pts" % int(player.get("totalScore", 0))
		elif Game.deals() > 0:
			info += "  ·  %d chips" % int(player.get("chips", 0))
		var their_turn: bool = playing and Game.state.get("currentPlayer") == id
		badge.show_player(str(player.get("username", "Player")), info, their_turn, sitting_out, _has_seen_joker(player))
		badge.show_photo(id, int(player.get("avatar", 0)))

	for id: String in _badges.keys():
		if not present.has(id):
			_badges[id].queue_free()
			_badges.erase(id)
	_place_opponents()


# Close Joker: the green dot on a badge, for a player who has seen the joker while it is still
# closed for the table. Once somebody declares it lies open for everyone and the dot goes.
func _has_seen_joker(player: Dictionary) -> bool:
	return (
		Game.state.get("closedJoker", false) and Game.status() == "playing"
		and Game.declared_by().is_empty() and player.get("seenJoker", false)
	)


func _refresh_piles() -> void:
	var state := Game.state
	var joker: Variant = state.get("joker")
	# Close Joker: the joker shows its back until our hand holds a pure sequence
	var hidden := Game.joker_hidden()
	_joker_card.card = joker if joker is Dictionary else {}
	_joker_card.face_down = hidden
	var wild_rank := Rummy.wild_rank(joker)
	if hidden:
		_joker_label.text = "Joker  ·  hidden"
	else:
		_joker_label.text = "Joker" if wild_rank.is_empty() else "Joker  ·  %ss wild" % wild_rank
	if _joker_was_hidden and not hidden and Game.status() == "playing":
		_open_joker()
	_joker_was_hidden = hidden
	_deck_label.text = str(int(state.get("deckCount", 0)))  # cards left, on the deck's corner
	_show_open_card(_open_now())
	_refresh_pile_highlights()


# Close Joker: our first pure sequence has earned us the joker, and it turns face up.
func _open_joker() -> void:
	_joker_card.reveal_after(0.0)
	Sound.play("flip")
	Sound.play("sparkle")
	var at := _center_of(_joker_card)
	Fx.sparkle(at, Color("ce93d8"), 26)
	Fx.float_text(at - Vector2(0.0, _joker_card.size.y * 0.7), "JOKER OPEN", Fx.GOLD, 34)


func _show_open_card(card: Dictionary) -> void:
	_open_card.card = card
	_open_card.wild = not card.is_empty() and Rummy.is_wild(card, Game.state.get("joker"))


func _open_now() -> Dictionary:
	var top: Variant = Game.state.get("discardTop")
	return top if top is Dictionary else {}


func _refresh_pile_highlights() -> void:
	var can_draw := _can_draw()
	_deck_card.highlighted = can_draw
	_open_card.highlighted = can_draw and not _open_card.card.is_empty()


func _refresh_status() -> void:
	var me := Game.me()
	var text := ""
	if not Game.is_online():
		text = "Reconnecting..."
	elif Game.status() != "playing":
		text = ""
	elif me.get("eliminated", false):
		text = "You are out of the match"
	elif me.get("status") == "dropped":
		text = "You are out of this round"
	elif Game.declared_by() == Game.player_id:
		text = "You declared! The others are arranging their cards"
	elif Game.arranging():
		text = "%s declared! Arrange your cards, then Submit" % Game.player_name(Game.declared_by())
	elif not Game.declared_by().is_empty():
		text = "Your cards are in. Waiting for the others"
	elif Game.is_my_turn() and Game.state.get("turnPhase") == "draw":
		text = "Your turn: draw from the deck or the open pile"
	elif Game.is_my_turn():
		text = "Select a card, then Discard or Declare"
	else:
		text = "Waiting for %s" % Game.player_name(Game.state.get("currentPlayer"))
	_status_label.text = text

	# The turn arriving is worth a nudge: the text swells, and a phone buzzes
	var my_turn := Game.is_my_turn()
	if my_turn and not _was_my_turn:
		Ui.pulse.call_deferred(_status_label, 1.06)
		Input.vibrate_handheld(40)
		_announce_my_turn.call_deferred()
	_was_my_turn = my_turn
	# And every change of turn has its sound (_seen still holds the turn before this update)
	var turn_owner := str(Game.state.get("currentPlayer", ""))
	if Game.status() == "playing" and Game.declared_by().is_empty() and turn_owner != str(_seen.get("current", "")):
		Sound.play("turn" if my_turn else "pass")


# Someone's declaration has just been accepted: the table hears it, and whoever still has
# cards to arrange is told that the clock is now theirs.
func _announce_declaration() -> void:
	var by := Game.declared_by()
	if by.is_empty() or by == str(_seen.get("declared", "")) or _seen.is_empty():
		return
	if by == Game.player_id:
		Fx.banner("YOU DECLARED")
		return
	Sound.play("declare")  # the declarer heard it when pressing the button
	Fx.banner("%s DECLARED" % Game.player_name(by).to_upper(), Color("ff8a65"))
	if Game.arranging():
		Input.vibrate_handheld(120)
		Ui.pulse.call_deferred(_declare_button, 1.2)


# "YOUR TURN" rises from above the hand, and light spreads from our own badge.
func _announce_my_turn() -> void:
	var announce := create_tween()
	# While a hand is being dealt, the words wait for the last card
	announce.tween_interval(maxf(0.0, (_deal_ends_at - Time.get_ticks_msec()) / 1000.0))
	announce.tween_callback(func() -> void:
		var above_hand := _hand_area.global_position + Vector2(_hand_area.size.x / 2.0, -30.0)
		Fx.float_text(above_hand, "YOUR TURN", Fx.GOLD, 46)
		Fx.ring(_my_badge.avatar_center(), Fx.GOLD, 90.0, 0.5)
		if _can_draw():
			# The two piles to choose from nod
			Ui.pulse(_deck_card, 1.1)
			Ui.pulse(_open_card, 1.1))


func _refresh_actions() -> void:
	if Game.state.is_empty():
		return
	var can_discard := _can_discard()
	_sort_button.disabled = Game.hand().is_empty()
	_group_button.disabled = _selected.size() < 2
	_discard_button.disabled = not can_discard or _selected.size() != 1
	_drop_button.disabled = not _can_draw()
	_refresh_pile_highlights()

	# After someone else's declaration the Declare button hands in our own cards instead
	var arranging := Game.arranging()
	if arranging != _declare_submits:
		_declare_submits = arranging
		_declare_button.text = "Submit" if arranging else "Declare"
		Ui.tint_button(_declare_button, Ui.PRIMARY if arranging else Ui.ORANGE)
	_declare_button.disabled = Game.busy if arranging else (not can_discard or _selected.size() != 1)

	var points: int = Rummy.evaluate_hand(Game.meld_cards(), Game.state.get("joker")).points
	var me := Game.me()
	var sitting_out: bool = me.get("eliminated", false) or me.get("status") == "dropped"
	_my_badge.show_player(str(Game.user.get("username", "You")), "Points in hand: %d" % points, Game.is_my_turn(), sitting_out, _has_seen_joker(me))
	_my_badge.show_photo(Game.player_id, int(me.get("avatar", 0)))


# What this update showed, kept so the next one can be compared with it.
func _remember() -> void:
	var state := Game.state
	var counts := {}
	for player: Dictionary in Game.players():
		counts[str(player.get("id", ""))] = int(player.get("handCount", 0))
	_seen = {
		"game": state.get("gameId"),
		"round": state.get("round"),
		"open": _open_now(),
		"deck": int(state.get("deckCount", 0)),
		"counts": counts,
		"current": str(state.get("currentPlayer", "")),
		"declared": Game.declared_by(),
	}


# ---------- cards travelling across the table ----------

# Shows what the other players just did: a card going from a pile to them, or from them
# to the open pile.
func _animate_opponents() -> void:
	var state := Game.state
	if _seen.is_empty() or _seen.game != state.get("gameId") or _seen.round != state.get("round"):
		return
	var open_now := _open_now()
	var open_before: Dictionary = _seen.open
	var open_changed: bool = open_now.get("id", "") != open_before.get("id", "")
	var deck_now := int(state.get("deckCount", 0))

	for player: Dictionary in Game.players():
		var id := str(player.get("id", ""))
		var badge: PlayerBadge = _badges.get(id)
		if badge == null or not _seen.counts.has(id):
			continue
		var before: int = _seen.counts[id]
		var now := int(player.get("handCount", 0))
		if now == before + 1:
			if open_changed and deck_now == _seen.deck and not open_before.is_empty():
				_fly(open_before, false, _center_of(_open_card), badge.avatar_center(), 1.0, 0.3)
			else:
				_fly({}, true, _center_of(_deck_card), badge.avatar_center(), 1.0, 0.3)
			_play_card_sounds(-6.0)
		elif open_changed and not open_now.is_empty():
			# One card fewer means a discard. Same count with a smaller deck means the clock
			# ran out and the server drew and threw for them in one step.
			var played_by_clock: bool = now == before and _seen.current == id and deck_now == _seen.deck - 1
			if now == before - 1 or played_by_clock:
				_show_open_card(open_before)  # the pile keeps its old card until the new one lands
				_fly(open_now, false, badge.avatar_center(), _center_of(_open_card), 0.3, 1.0, _on_open_pile_landing)
				_play_card_sounds(-6.0)


# A card leaving one place and landing in another: a swish now, a tap when it arrives.
# Other players' cards are played more quietly than our own.
func _play_card_sounds(volume_db: float = 0.0, seconds: float = FLY_SECONDS) -> void:
	Sound.play("card", volume_db)
	Sound.play_later("place", seconds, volume_db)


# A card that belongs to nobody on screen: it only crosses the table and disappears.
func _fly(card: Dictionary, face_down: bool, from: Vector2, to: Vector2, from_scale: float, to_scale: float, on_arrival: Callable = Callable()) -> void:
	var ghost := CardView.new()
	ghost.interactive = false
	ghost.card = card
	ghost.face_down = face_down
	ghost.set_width(PILE_CARD_WIDTH)
	_fly_layer.add_child(ghost)

	var to_layer := _fly_layer.get_global_transform().affine_inverse()
	ghost.position = to_layer * from - ghost.size / 2.0
	ghost.scale = Vector2(from_scale, from_scale)
	var tween := ghost.create_tween()
	tween.tween_property(ghost, "position", to_layer * to - ghost.size / 2.0, FLY_SECONDS).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	tween.parallel().tween_property(ghost, "scale", Vector2(to_scale, to_scale), FLY_SECONDS)
	tween.parallel().tween_property(ghost, "rotation", TAU, FLY_SECONDS)  # tossed, so it spins once on the way
	if on_arrival.is_valid():
		tween.tween_callback(on_arrival)
	tween.tween_callback(ghost.queue_free)


# Our own discard: the card itself leaves the hand and lands on the open pile.
func _throw_to_open_pile(view: CardView) -> void:
	view.stop_gliding()
	view.interactive = false
	view.selected = false
	view.highlighted = false
	view.z_index = 0
	view.reparent(_fly_layer)
	_show_open_card(_seen.get("open", {}))  # the pile keeps its old card until this one lands
	_play_card_sounds()

	var to_layer := _fly_layer.get_global_transform().affine_inverse()
	var landing: Vector2 = to_layer * _center_of(_open_card) - view.size / 2.0
	var shrink := PILE_CARD_WIDTH / view.size.x
	var tween := view.create_tween()
	tween.tween_property(view, "position", landing, FLY_SECONDS).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	tween.parallel().tween_property(view, "scale", Vector2(shrink, shrink), FLY_SECONDS)
	tween.parallel().tween_property(view, "rotation", TAU, FLY_SECONDS)  # tossed, so it spins once on the way
	tween.tween_callback(_on_open_pile_landing)
	tween.tween_callback(view.queue_free)


# A thrown card has reached the open pile: the pile shows it, with a ripple of light.
func _on_open_pile_landing() -> void:
	_refresh_piles()
	Fx.ring(_center_of(_open_card), Color.WHITE, 90.0)
	Ui.pulse(_open_card, 1.08)


func _center_of(control: Control) -> Vector2:
	return control.global_position + control.size / 2.0


# ---------- the hand ----------

# Makes the cards on screen match the hand: removes the ones that left, adds the new ones.
func _sync_hand() -> void:
	var state := Game.state
	var joker: Variant = state.get("joker")
	var held := {}
	for card: Dictionary in Game.hand():
		held[card.id] = card
	var open_id := str(_open_now().get("id", ""))

	for id: Variant in _cards.keys():
		if held.has(id):
			continue
		var gone: CardView = _cards[id]
		_cards.erase(id)
		if id == _dragging_id:
			_dragging_id = ""
			_marker.visible = false
		if id == open_id and not _seen.is_empty():
			_throw_to_open_pile(gone)
		else:
			gone.queue_free()
	_selected = _selected.filter(func(id: Variant) -> bool: return held.has(id))

	# A whole new hand is dealt out one card after another; a single card just arrives
	var dealing := _cards.is_empty()
	var seen_open_id := str(_seen.get("open", {}).get("id", ""))
	var arrivals := 0
	for id: Variant in held:
		var view: CardView = _cards.get(id)
		if view == null:
			view = CardView.new()
			view.set_width(_card_width)
			view.card = held[id]
			view.draggable = true
			view.tapped.connect(_on_card_tapped)
			view.drag_started.connect(_on_drag_started)
			view.dragged.connect(_on_dragged)
			view.dropped.connect(_on_dropped)
			_hand_area.add_child(view)
			# It starts on the pile it came from, at that pile's size
			var from_open_pile: bool = not dealing and id == seen_open_id
			var source := _open_card if from_open_pile else _deck_card
			view.position = _hand_area.get_global_transform().affine_inverse() * _center_of(source) - view.size / 2.0
			view.scale = Vector2.ONE * (PILE_CARD_WIDTH / _card_width)
			view.rotation = randf_range(-0.45, 0.45)  # askew on the pile; it straightens as it arrives
			view.set_meta("arriving", arrivals)
			view.set_meta("turn_over", not from_open_pile)
			view.set_meta("dealt", dealing)
			arrivals += 1
			_cards[id] = view
		view.wild = Rummy.is_wild(held[id], joker)
		view.highlighted = id == state.get("lastDrawnId")
		view.selected = _selected.has(id)

	if dealing and arrivals > 0:
		Sound.play("shuffle")
		_quiet_melds = true  # melds that come with the deal are not the player's doing
		_deal_ends_at = Time.get_ticks_msec() + int((arrivals * DEAL_STAGGER + ARRIVE_SECONDS + 0.2) * 1000.0)
		_announce_deal(arrivals * DEAL_STAGGER + ARRIVE_SECONDS)
	_place_cards()


# A new hand: the round is named across the table, and once the cards are out the joker
# that is wild this round gets a moment of its own.
func _announce_deal(deal_seconds: float) -> void:
	if Game.is_pool():
		Fx.banner("ROUND %d" % int(Game.state.get("round", 1)))
	elif Game.deals() > 0:
		Fx.banner(_deal_name(int(Game.state.get("round", 1))).to_upper())
	else:
		Fx.banner("GAME ON")
	var after_deal := create_tween()
	after_deal.tween_interval(deal_seconds)
	after_deal.tween_callback(func() -> void:
		if Game.joker_hidden():
			# Close Joker: nothing to show yet, only how to get to see it
			Ui.notify("info", "Make a pure sequence to see the joker")
			return
		Fx.sparkle(_center_of(_joker_card), Color("ce93d8"))
		Ui.pulse(_joker_card, 1.15)
		Sound.play("sparkle"))


# Deals Rummy: "Deal 1 of 2", and after the last deal "Tie-breaker" for the deal between
# the players level on chips.
func _deal_name(deal: int) -> String:
	if deal > Game.deals():
		return "Tie-breaker"
	return "Deal %d of %d" % [deal, Game.deals()]


# Lays the cards out group by group. Cards in a group overlap as little as the width allows.
func _place_cards(animate: bool = true) -> void:
	# Card size follows the screen: a wider phone gets wider cards
	var width := clampf(size.x / 10.6, 112.0, 150.0)
	if not is_equal_approx(width, _card_width):
		_card_width = width
		for view: CardView in _cards.values():
			view.set_width(width)
	var card_height := CardView.height_for(_card_width)
	var needed := SELECT_LIFT + 6.0 + card_height + 6.0 + GROUP_LABEL_HEIGHT + 8.0
	if not is_equal_approx(_hand_area.custom_minimum_size.y, needed):
		_hand_area.custom_minimum_size.y = needed

	var groups := Game.groups
	_spans = []
	if _cards.is_empty() or groups.is_empty():
		_hide_group_labels(0)
		return

	var group_count := groups.size()
	var overlapped := _cards.size() - group_count
	var available := _hand_area.size.x - HAND_PADDING * 2.0
	var step := _card_width
	if overlapped > 0:
		var room := available - group_count * _card_width - (group_count - 1) * GROUP_GAP
		step = clampf(room / overlapped, _card_width * 0.4, _card_width * 0.92)
	var gap := GROUP_GAP
	if group_count > 1:
		# With many small groups, close the gaps (even overlap a little) before running off screen
		var room := available - group_count * _card_width - overlapped * step
		gap = clampf(room / (group_count - 1), -_card_width * 0.4, GROUP_GAP)
	var total := group_count * _card_width + overlapped * step + (group_count - 1) * gap

	var x := maxf(HAND_PADDING, (_hand_area.size.x - total) / 2.0)
	var top := SELECT_LIFT + 6.0
	var joker: Variant = Game.state.get("joker")
	var cards_by_group := Game.meld_cards()

	var order := 0
	for group_index in group_count:
		var ids: Array = groups[group_index]
		var group_left := x
		var xs: Array = []
		for card_index in ids.size():
			var id: Variant = ids[card_index]
			xs.append(x)
			var view: CardView = _cards.get(id)
			if view != null:
				_hand_area.move_child(view, order)  # later cards are drawn on top
				order += 1
				if id != _dragging_id:
					_send_card(view, Vector2(x, top - (SELECT_LIFT if _selected.has(id) else 0.0)), animate)
			x += _card_width if card_index == ids.size() - 1 else step
		_spans.append({"left": group_left, "right": x, "ids": ids, "xs": xs})
		_place_group_label(group_index, cards_by_group[group_index], group_left, x - group_left, top + card_height + 6.0, joker)
		x += gap
	_hide_group_labels(group_count)
	_hand_area.move_child(_marker, -1)
	_note_new_melds(cards_by_group, joker)


# A chime when the player has just formed a meld that was not in the hand before.
func _note_new_melds(cards_by_group: Array, joker: Variant) -> void:
	var melds_now := {}
	var chime := ""
	for group_index in cards_by_group.size():
		var cards: Array = cards_by_group[group_index]
		if cards.size() < 3:
			continue
		var type := Rummy.classify_meld(cards, joker)
		if type == "invalid":
			continue
		var ids: Array = cards.map(func(card: Dictionary) -> String: return str(card.get("id")))
		ids.sort()
		var key := ",".join(ids)
		melds_now[key] = true
		if not _valid_melds.has(key):
			if chime != "meld_pure":
				chime = "meld_pure" if type == "pure_sequence" else "meld"
			if not _quiet_melds:
				_celebrate_meld(group_index, type)
	if not chime.is_empty() and not _quiet_melds:
		Sound.play(chime)
	_valid_melds = melds_now
	_quiet_melds = false


# Stars over the cards of a meld just made, and its name rising above them.
func _celebrate_meld(group_index: int, type: String) -> void:
	if group_index >= _spans.size():
		return
	var span: Dictionary = _spans[group_index]
	var card_height := CardView.height_for(_card_width)
	var middle := Vector2((span.left + span.right) / 2.0, SELECT_LIFT + 6.0 + card_height * 0.45)
	var at: Vector2 = _hand_area.get_global_transform() * middle
	var pure := type == "pure_sequence"
	Fx.sparkle(at, Fx.GOLD if pure else Color("a5d6a7"), 26 if pure else 16)
	Fx.float_text(at - Vector2(0.0, card_height * 0.55), "%s!" % Rummy.MELD_LABELS[type], Fx.GOLD if pure else Color.WHITE, 34)
	if group_index < _group_labels.size():
		Ui.pulse.call_deferred(_group_labels[group_index], 1.15)


func _send_card(view: CardView, target: Vector2, animate: bool) -> void:
	if view.has_meta("arriving"):
		# Newly taken: it glides in from its pile, grows to hand size, then turns face up
		var delay: float = int(view.get_meta("arriving")) * DEAL_STAGGER
		view.remove_meta("arriving")
		if view.get_meta("dealt", false):
			Sound.play_later("card", delay)  # one soft swish per card of the deal
		else:
			_play_card_sounds(0.0, ARRIVE_SECONDS)
		view.glide_to(target, ARRIVE_SECONDS, delay)
		var grow := view.create_tween()
		if delay > 0.0:
			grow.tween_interval(delay)
		grow.tween_property(view, "scale", Vector2.ONE, ARRIVE_SECONDS)
		grow.parallel().tween_property(view, "rotation", 0.0, ARRIVE_SECONDS)
		if view.get_meta("turn_over", false):
			view.reveal_after(delay + ARRIVE_SECONDS)
	elif not animate:
		view.stop_gliding()
		view.position = target
	elif not view.position.is_equal_approx(target):
		view.glide_to(target, MOVE_SECONDS)


# The label under a group names the meld, or offers "+ Add" while other cards are selected.
func _place_group_label(index: int, cards: Array, left: float, width: float, top: float, joker: Variant) -> void:
	while _group_labels.size() <= index:
		var created := Button.new()
		created.clip_text = true
		created.focus_mode = Control.FOCUS_NONE
		created.add_theme_font_size_override("font_size", 17)
		created.add_theme_color_override("font_disabled_color", Color.WHITE)
		created.pressed.connect(_on_group_label_pressed.bind(_group_labels.size()))
		_hand_area.add_child(created)
		_group_labels.append(created)

	var label := _group_labels[index]
	var ids: Array = Game.groups[index]
	var can_move_here := not _selected.is_empty() and not _selected.all(func(id: Variant) -> bool: return ids.has(id))
	var type := Rummy.classify_meld(cards, joker)

	var color := Color.TRANSPARENT
	label.text = ""
	if can_move_here:
		label.text = "+ Add"
		color = Ui.BLUE
	elif cards.size() >= 3:
		label.text = Rummy.MELD_LABELS[type]
		color = INVALID_LABEL if type == "invalid" else VALID_LABEL

	label.visible = not label.text.is_empty()
	label.disabled = not can_move_here
	for state_name: String in ["normal", "hover", "pressed", "disabled"]:
		label.add_theme_stylebox_override(state_name, Ui.box(color, 14, 6, 2))
	label.position = Vector2(left, top)
	label.size = Vector2(width, GROUP_LABEL_HEIGHT)
	_hand_area.move_child(label, -1)

	# While a hand is being dealt the labels wait for the cards they describe
	var until_dealt := (_deal_ends_at - Time.get_ticks_msec()) / 1000.0
	if until_dealt > 0.0 and label.visible:
		label.modulate.a = 0.0
		var fade := label.create_tween()
		fade.tween_interval(until_dealt)
		fade.tween_property(label, "modulate:a", 1.0, 0.2)


func _hide_group_labels(from_index: int) -> void:
	for index in range(from_index, _group_labels.size()):
		_group_labels[index].visible = false


func _sorted_ids(ids: Array) -> Array:
	var cards := ids.map(func(id: Variant) -> Dictionary: return Game.card(str(id)))
	return Rummy.sort_cards(cards).map(func(card: Dictionary) -> Variant: return card.get("id"))


# ---------- carrying a card ----------

func _on_drag_started(card_id: String) -> void:
	var view: CardView = _cards.get(card_id)
	if view == null:
		return
	_dragging_id = card_id
	Sound.play("card", -4.0)
	view.stop_gliding()
	# The spot the finger took hold of stays under it, however fast the finger moved since.
	# (Measured from the touch, not from the mouse cursor: a phone has no cursor.)
	_drag_offset = view.global_position - view.pressed_at
	view.z_index = 20
	view.create_tween().tween_property(view, "scale", Vector2(1.1, 1.1), 0.1)
	# Selections are for the buttons; a carried card goes alone
	if not _selected.is_empty():
		_selected = []
		for held: CardView in _cards.values():
			held.selected = false
		_place_cards()
		_refresh_actions()


func _on_dragged(card_id: String, pointer: Vector2) -> void:
	var view: CardView = _cards.get(card_id)
	if view == null or card_id != _dragging_id:
		return
	view.global_position = pointer + _drag_offset
	var over_pile := _over_open_pile(pointer) and _can_discard()
	var over_slot := _over_declare_slot(pointer) and _can_discard()
	_open_card.highlighted = over_pile
	if over_slot != _slot_lit:
		_light_slot(over_slot)
	_show_marker({} if over_pile or over_slot else _drop_target(pointer))


func _on_dropped(card_id: String, pointer: Vector2) -> void:
	var view: CardView = _cards.get(card_id)
	_dragging_id = ""
	_marker.visible = false
	_refresh_pile_highlights()
	if _slot_lit:
		_light_slot(false)
	if view == null:
		return
	view.z_index = 0
	view.create_tween().tween_property(view, "scale", Vector2.ONE, 0.1)

	if _over_open_pile(pointer) and _can_discard():
		Game.discard(card_id)  # the card stays where it was let go until the server answers
		return
	if _over_declare_slot(pointer) and _can_discard():
		# Dropped on "Declare here": this is the card to finish with
		_selected = [card_id]
		view.selected = true
		_place_cards()
		_refresh_actions()
		_on_declare()
		return
	var target := _drop_target(pointer)
	if target.is_empty():
		_place_cards()  # let go somewhere that means nothing: back to its place
		return

	Sound.play("place")
	var next: Array = []
	for group: Array in Game.groups:
		next.append(group.filter(func(id: Variant) -> bool: return id != card_id))
	if target.has("new_group"):
		next.insert(mini(int(target.new_group), next.size()), [card_id])
	else:
		var group: Array = next[int(target.group)]
		group.insert(mini(int(target.at), group.size()), card_id)
	Game.set_groups(next)


# Where a card let go at `pointer` would land: {"group": index, "at": place among its cards},
# {"new_group": index} for a group of its own, or {} for nowhere.
#
# A card dropped on a group joins it. A card dropped beside either end of the hand, or in the
# gap between two groups, starts a group of its own there. Those strips are always on screen,
# also when the hand fills the whole width of a phone, and they reach a little over the cards
# on either side, because a gap alone is too narrow to hit with a finger.
func _drop_target(pointer: Vector2) -> Dictionary:
	if _spans.is_empty():
		return {}
	var local: Vector2 = _hand_area.get_global_transform().affine_inverse() * pointer
	if local.y < -70.0 or local.y > _hand_area.size.y + 50.0:
		return {}

	var reach := _card_width * 0.12
	for index in _spans.size():
		var span: Dictionary = _spans[index]
		# A group's front card may show only a narrow strip: most of it stays "in front of this group"
		var front_strip: float = span.xs[1] - span.xs[0] if span.xs.size() > 1 else _card_width
		if local.x < span.left + minf(reach, front_strip * 0.25):
			return {"new_group": index}
		if local.x <= span.right - reach:
			# Among this group's other cards: before the first one whose visible part is right of the finger
			var at := 0
			for card_index in span.ids.size():
				if span.ids[card_index] == _dragging_id:
					continue
				var shown_until: float = span.xs[card_index + 1] if card_index + 1 < span.xs.size() else span.right
				if local.x > (span.xs[card_index] + shown_until) / 2.0:
					at += 1
			return {"group": index, "at": at}
	return {"new_group": _spans.size()}


# A thin bar showing where the carried card would go.
func _show_marker(target: Dictionary) -> void:
	if target.is_empty():
		_marker.visible = false
		return
	var x := 0.0
	if target.has("new_group"):
		var index := int(target.new_group)
		if index <= 0:
			x = _spans[0].left - GROUP_GAP * 0.5
		elif index >= _spans.size():
			x = _spans[-1].right + GROUP_GAP * 0.5
		else:
			x = (_spans[index - 1].right + _spans[index].left) / 2.0
		x = clampf(x, 6.0, _hand_area.size.x - 6.0)  # never off the edge of the screen
	else:
		var span: Dictionary = _spans[int(target.group)]
		var others: Array = []
		for card_index in span.ids.size():
			if span.ids[card_index] != _dragging_id:
				others.append(span.xs[card_index])
		var at := int(target.at)
		x = others[at] if at < others.size() else span.right
	_marker.position = Vector2(x - 3.0, SELECT_LIFT + 6.0)
	_marker.size = Vector2(6.0, CardView.height_for(_card_width))
	_marker.visible = true


func _over_open_pile(pointer: Vector2) -> bool:
	return Rect2(_open_card.global_position, _open_card.size).grow(40.0).has_point(pointer)


func _over_declare_slot(pointer: Vector2) -> bool:
	return Rect2(_declare_slot.global_position, _declare_slot.size).grow(24.0).has_point(pointer)


# A tap on "Declare here" declares with the selected card, like the Declare button.
# Like a button it reacts when the finger lifts: the question it opens is not laid out yet on
# touch-down, and the lift of the same finger could land on one of its buttons.
func _on_declare_slot_input(event: InputEvent) -> void:
	var click := event as InputEventMouseButton
	if click == null or click.pressed or click.button_index != MOUSE_BUTTON_LEFT:
		return
	if not Rect2(Vector2.ZERO, _declare_slot.size).has_point(click.position):
		return  # the finger slid away before lifting
	if not _can_discard():
		return
	if _selected.size() == 1:
		_on_declare()
	else:
		Ui.notify("info", "Select the card to finish with, then tap here (or drop it here)")


func _on_action_failed(_message: String) -> void:
	_place_cards()  # e.g. a card dropped on the pile that the server would not take


# ---------- the player's moves ----------

func _in_round() -> bool:
	var me := Game.me()
	return Game.status() == "playing" and me.get("status") == "active" and not me.get("eliminated", false)


func _can_draw() -> bool:
	return _in_round() and Game.is_my_turn() and Game.state.get("turnPhase") == "draw" and not Game.busy


func _can_discard() -> bool:
	return _in_round() and Game.is_my_turn() and Game.state.get("turnPhase") == "discard" and not Game.busy


func _on_pile_tapped(_card_id: String, from_open_pile: bool) -> void:
	if not _can_draw():
		return
	if from_open_pile and _open_card.card.is_empty():
		return
	Game.draw(from_open_pile)


func _on_card_tapped(card_id: String) -> void:
	if _selected.has(card_id):
		_selected.erase(card_id)
		Sound.play("deselect")
	else:
		_selected.append(card_id)
		Sound.play("select")
	var view: CardView = _cards.get(card_id)
	if view != null:
		view.selected = _selected.has(card_id)
	_place_cards()
	_refresh_actions()


func _on_sort() -> void:
	_selected.clear()
	Sound.play("group")
	Game.sort_hand()


# Pulls the selected cards out into a group of their own, where the first of them was.
func _on_group() -> void:
	if _selected.size() < 2:
		return
	var next: Array = []
	var insert_at := -1
	for group: Array in Game.groups:
		if insert_at == -1 and group.any(func(id: Variant) -> bool: return _selected.has(id)):
			insert_at = next.size()
		next.append(group.filter(func(id: Variant) -> bool: return not _selected.has(id)))
	next.insert(maxi(insert_at, 0), _sorted_ids(_selected))
	_selected = []
	Sound.play("group")
	Game.set_groups(next)


func _on_group_label_pressed(index: int) -> void:
	if _selected.is_empty() or index >= Game.groups.size():
		return
	var moving := _selected
	_selected = []
	var next: Array = []
	for group_index in Game.groups.size():
		var kept: Array = Game.groups[group_index].filter(func(id: Variant) -> bool: return not moving.has(id))
		next.append(_sorted_ids(kept + moving) if group_index == index else kept)
	Sound.play("group")
	Game.set_groups(next)


func _on_discard() -> void:
	if _selected.size() != 1 or not _can_discard():
		return
	var card_id := str(_selected[0])
	_selected = []
	Game.discard(card_id)


func _on_declare() -> void:
	if Game.arranging():
		# The button reads "Submit" now: our cards are counted the way they are grouped
		_selected = []
		Sound.play("group")
		Game.submit_hand()
		return
	if _selected.size() != 1 or not _can_discard():
		return
	var card_id := str(_selected[0])
	var remaining: Array = []
	for cards: Array in Game.meld_cards():
		remaining.append(cards.filter(func(card: Dictionary) -> bool: return card.get("id") != card_id))
	var valid: bool = Rummy.evaluate_hand(remaining, Game.state.get("joker")).valid

	var question := "Your groups are not a valid declaration yet. Declaring now costs 80 points."
	if valid:
		question = "Finish with the %s and show your hand?" % Rummy.card_name(Game.card(card_id))
	Ui.confirm("Declare", question, "Declare", _declare.bind(card_id))


func _declare(card_id: String) -> void:
	_selected = []
	Sound.play("declare")
	# The sound is a rush of air and then a heavy hit; the table jumps on the hit
	var hit := create_tween()
	hit.tween_interval(0.3)
	hit.tween_callback(Fx.flash.bind(Color(1, 1, 1, 0.6), 0.45))
	hit.tween_callback(Fx.shake.bind(12.0, 0.4))
	Game.declare(card_id)


func _on_drop() -> void:
	if not _can_draw():
		return
	Ui.confirm("Drop", "Give up this round? It costs 20 points before your first turn and 40 after.", "Drop", _drop_round)


func _drop_round() -> void:
	Sound.play("drop")
	Game.drop()


func _on_leave() -> void:
	if Game.status() == "finished":
		Game.leave()
	else:
		Ui.confirm("Leave game", Ui.leave_game_warning(), "Leave", Game.leave)


# ---------- round and game results ----------

func _refresh_result(is_pool: bool) -> void:
	var status := Game.status()
	var result: Variant = Game.state.get("lastResult")
	var showing: bool = status in ["round_over", "finished"] and result is Dictionary
	if not showing:
		_result_overlay.visible = false
		_confetti.emitting = false
		_result_key = ""
		return

	var finished := status == "finished"
	_back_button.visible = finished
	_play_again_button.visible = finished  # a new table with the same rules, for the same players
	_leave_game_button.visible = not finished
	_next_round_label.visible = not finished

	# The same result arrives again with every update; rebuild the rows only when it changes
	var key := "%s/%s/%s" % [Game.state.get("gameId"), result.get("round"), status]
	if key == _result_key:
		return
	_result_key = key

	var winner: Variant = result.get("matchWinner") if finished else result.get("winner")
	var i_won: bool = winner == Game.player_id
	if finished:
		if winner == null:
			_result_title.text = "Game over"
		elif i_won:
			_result_title.text = "You won!"
		else:
			_result_title.text = "%s won the game" % Game.player_name(winner)
	else:
		var round_name := "deal %d" % int(result.get("round", 1)) if Game.deals() > 0 else "round %d" % int(result.get("round", 1))
		_result_title.text = "%s won %s" % ["You" if i_won else Game.player_name(winner), round_name]
	_result_title.add_theme_color_override("font_color", WIN_TEXT if i_won else DARK_TEXT)

	# The pot is paid when the whole game is over, not after a round of it. At a Points table
	# for coins a point the winner gets what the others' points cost instead.
	var prize := Game.pot()
	if Game.point_value() > 0:
		for row: Dictionary in result.get("players", []):
			if row.get("id") == winner:
				prize = int(row.get("coins", 0))
	_prize.visible = finished and winner != null and prize > 0
	_prize.amount = prize
	_prize.suffix = "coins won" if i_won else "coins go to %s" % Game.player_name(winner)

	for child in _result_rows.get_children():
		_result_rows.remove_child(child)
		child.queue_free()
	var rows: Array = result.get("players", [])
	for index in rows.size():
		var entry := _build_result_row(rows[index], is_pool)
		_result_rows.add_child(entry)
		# The players are read out one after another, each with a tick
		Ui.pop_in.call_deferred(entry, 0.25 + index * 0.12)
		Sound.play_later("count", 0.25 + index * 0.12)
	_result_scroll.custom_minimum_size.y = minf(400.0, rows.size() * 114.0)

	# The result drops in; the winner gets confetti
	_result_overlay.visible = true
	_result_overlay.modulate.a = 0.0
	_result_overlay.create_tween().tween_property(_result_overlay, "modulate:a", 1.0, 0.2)
	Ui.pop_in.call_deferred(_result_panel)
	_confetti.position = Vector2(size.x / 2.0, -20.0)
	_confetti.emission_rect_extents = Vector2(size.x / 2.0, 6.0)
	_confetti.emitting = i_won
	if i_won:
		Input.vibrate_handheld(120)
		Sound.play("win")
		Sound.duck(3.0)  # the music steps back for the fanfare
		Fx.victory(finished)  # fireworks and paper; the whole show for winning the game
	else:
		Sound.play("lose")
		Fx.flash(Color(0.45, 0.0, 0.0, 0.4), 0.7)


func _build_result_row(row: Dictionary, is_pool: bool) -> Control:
	var entry := VBoxContainer.new()
	entry.add_theme_constant_override("separation", 6)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 18)
	var is_winner: bool = row.get("outcome") == "winner"
	var player_name := str(row.get("username", "Player"))
	if row.get("id") == Game.player_id:
		player_name += "  (you)"
	var name_label := _text(player_name, 24, WIN_TEXT if is_winner else DARK_TEXT)
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(name_label)

	var outcome := str(OUTCOME_LABELS.get(row.get("outcome"), ""))
	if is_pool and row.get("eliminated", false) and not is_winner:
		outcome += "  ·  eliminated"
	header.add_child(_text(outcome, 20, DIM_TEXT))

	var points := "%d pts" % int(row.get("points", 0))
	if is_pool:
		points += "  (total %d)" % int(row.get("totalScore", 0))
	elif row.has("chips"):
		# Deals Rummy: the chips that changed hands, and what the player has now
		points += "  ·  %+d chips (%d)" % [int(row.get("chipsWon", 0)), int(row.get("chips", 0))]
	if row.has("coins"):
		var coins := int(row.get("coins", 0))
		points += "  ·  %s%s coins" % ["+" if coins > 0 else "", Ui.coins_text(coins)]
	header.add_child(_text(points, 24, DARK_TEXT))
	entry.add_child(header)

	# The hand as it was scored, group by group
	var melds := HBoxContainer.new()
	melds.add_theme_constant_override("separation", 12)
	for meld: Dictionary in row.get("melds", []):
		var group := HBoxContainer.new()
		group.add_theme_constant_override("separation", -int(MINI_CARD_WIDTH * 0.42))
		for card: Dictionary in meld.get("cards", []):
			var view := CardView.new()
			view.interactive = false
			view.card = card
			view.set_width(MINI_CARD_WIDTH)
			group.add_child(view)
		melds.add_child(group)
	var friend_button := _friend_button(row)
	if friend_button != null:
		# At the right end of the cards, where it fits without making the row taller
		var gap := Control.new()
		gap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		melds.add_child(gap)
		melds.add_child(friend_button)
	entry.add_child(melds)
	return entry


# "Add friend" for a player met at this table who is not in the friends list yet.
func _friend_button(row: Dictionary) -> Button:
	var id := str(row.get("id", ""))
	var username := str(row.get("username", ""))
	if id == Game.player_id or username.is_empty():
		return null
	for known: Dictionary in Game.friends + Game.friend_asked:
		if str(known.get("id", "")) == id:
			return null

	var button := Button.new()
	button.name = "AddFriendButton"
	button.text = "Add friend"
	button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	button.add_theme_font_size_override("font_size", 20)
	Ui.tint_button(button, Ui.TEAL)
	button.pressed.connect(func() -> void:
		Game.add_friend(username)
		button.disabled = true
		button.text = "Asked"
	)
	return button


func _text(text: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	return label


# Coloured paper falling from the top of the screen, for the winner.
func _make_confetti() -> CPUParticles2D:
	var confetti := CPUParticles2D.new()
	confetti.emitting = false
	confetti.amount = 150
	confetti.lifetime = 3.4
	confetti.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	confetti.direction = Vector2.DOWN
	confetti.spread = 30.0
	confetti.gravity = Vector2(0, 380)
	confetti.initial_velocity_min = 90.0
	confetti.initial_velocity_max = 300.0
	confetti.angular_velocity_min = -400.0
	confetti.angular_velocity_max = 400.0
	confetti.angle_max = 360.0
	confetti.scale_amount_min = 8.0
	confetti.scale_amount_max = 15.0

	var paper := Gradient.new()
	paper.interpolation_mode = Gradient.GRADIENT_INTERPOLATE_CONSTANT
	paper.offsets = PackedFloat32Array([0.0, 0.17, 0.34, 0.51, 0.68, 0.85])
	paper.colors = PackedColorArray([
		Color("ffca28"), Color("ef5350"), Color("42a5f5"), Color("66bb6a"), Color("ab47bc"), Color("ffffff"),
	])
	confetti.color_initial_ramp = paper
	return confetti
