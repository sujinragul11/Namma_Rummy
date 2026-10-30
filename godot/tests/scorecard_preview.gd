extends Control
## Shows the scorecard and the game result with no server, from results made up here, checks
## what they say and saves a picture of each: a Pool round where we dropped, the end of the
## Pool game with a player out and the coins paid, a Deals round, and a full table of six.
## Use it to look at the result screens after a change.
##
## Run WITH a window to get the pictures (headless only checks), from godot/:
##   godot --path . res://tests/scorecard_preview.tscn -- --profile=scorepreview --mute --shots=<folder>
## Add --resolution 1600x720 before the scene to see a tall phone's shape.

const NAMES := ["Sujin", "guest8230642", "Priya", "Kavin", "Arun", "Meena"]

var _shots := ""
var _step := 0
var _passed := 0
var _failed := 0
var _table: Control


func _ready() -> void:
	# The dummy display reports a square screen; exercise the actual landscape layout.
	if DisplayServer.get_name() == "headless":
		get_window().content_scale_size = Vector2i(1280, 720)
		get_window().content_scale_aspect = Window.CONTENT_SCALE_ASPECT_IGNORE
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--shots="):
			_shots = argument.trim_prefix("--shots=")
	if not _shots.is_empty():
		DirAccess.make_dir_recursive_absolute(_shots)
	theme = Ui.game_theme
	# A fake seat at a table: enough for the table to draw, no server is asked anything
	Game.remember_login = false
	Game.token = "preview"
	Game.user = {"id": 1, "username": "Sujin"}
	Game.player_id = "1"
	Game.socket.is_online = true
	_set_result(2, "round_over", {"poolLimit": 101}, _pool_round())
	_table = (load("res://scenes/table.tscn") as PackedScene).instantiate()
	add_child(_table)
	_run()


func _run() -> void:
	await _wait(1.6)  # the result drops in and the numbers run up

	# ---------- a Pool round: we dropped, the other player won it ----------
	_check("the scorecard is shown", _shown("ResultOverlay") and _text("ResultHeading") == "SCORECARD", _text("ResultHeading"))
	_check("it says who won the round", _text("ResultTitle") == "guest8230642 won round 2", _text("ResultTitle"))
	_check("a row for each player", _node("ResultRows").get_child_count() == 2)
	_check("our row says You and DROPPED, with the hand face down", _row_has(0, "You") and _row_has(0, "DROPPED") and _cards_in(0).all(func(view: CardView) -> bool: return view.face_down))
	_check("the winner's hand is face up, with a WINNER ribbon", _cards_in(1).all(func(view: CardView) -> bool: return not view.face_down) and _row_has(1, "WINNER!"))
	_check("the numbers have run up: score 20, total 20", _row_numbers(0) == ["20", "20"], str(_row_numbers(0)))
	_check("the countdown to the next round", _text("NextRoundLabel").begins_with("Next round in "), _text("NextRoundLabel"))
	_check("between rounds no way out", not _shown("BackButton") and not _shown("PlayAgainButton"))
	_check("the wild joker in the corner", _shown("WildCard"))
	await _shot("pool-round")

	# ---------- the Pool game is over: we are out, the other player takes the pot ----------
	_set_result(3, "finished", {"poolLimit": 101, "stake": 500, "pot": 1000}, _pool_finished())
	await _wait(1.6)
	_check("the game result is shown", _text("ResultHeading") == "GAME RESULT", _text("ResultHeading"))
	_check("it says who won the game", _text("ResultTitle") == "guest8230642 won the game", _text("ResultTitle"))
	_check("our row says OUT, total 120 and the entry lost", _row_has(0, "OUT") and _row_numbers(0)[1] == "120" and _row_has(0, "-500"), str(_row_texts(0)))
	_check("the winner's row shows the pot won", _row_has(1, "+1,000"), str(_row_texts(1)))
	_check("Leave Game and Play Again", _shown("BackButton") and _text("BackButton") == "Leave Game" and _shown("PlayAgainButton"))
	_check("the buttons are on the screen", _on_screen("BackButton") and _on_screen("PlayAgainButton"))
	await _shot("pool-finished")

	# ---------- a Deals round: the chips that changed hands ----------
	_set_result(1, "round_over", {"deals": 2}, _deals_round())
	await _wait(1.6)
	_check("Deals: the total column is the chips", _text_in("ResultScroll").contains("Chips") or _node("ResultOverlay").find_children("*", "Label", true, false).any(func(label: Label) -> bool: return label.text == "Chips"))
	_check("Deals: the chips won and lost", _row_has(0, "-20 chips") and _row_has(1, "+20 chips") and _row_numbers(0)[1] == "140" and _row_numbers(1)[1] == "180", "%s / %s" % [_row_texts(0), _row_texts(1)])
	_check("Deals: the countdown names the deal", _text("NextRoundLabel").begins_with("Next deal in "), _text("NextRoundLabel"))
	await _shot("deals-round")

	# ---------- six players: the rows scroll, the bar stays ----------
	_set_result(4, "round_over", {"poolLimit": 201}, _six_players())
	await _wait(1.8)
	_check("six rows", _node("ResultRows").get_child_count() == 6)
	_check("the countdown stays on the screen", _on_screen("NextRoundLabel"))
	var score_scroll: ScrollContainer = _node("ResultScroll")
	var score_rows: VBoxContainer = _node("ResultRows")
	_check("six-player scores overflow into a visible scrollbar", score_scroll.get_v_scroll_bar().visible and score_rows.size.y > score_scroll.size.y, "scroll=%s rows=%s viewport=%s" % [score_scroll.size, score_rows.size, get_viewport_rect().size])
	var at := score_scroll.global_position + Vector2(220, 60)
	var wheel := InputEventMouseButton.new()
	wheel.button_index = MOUSE_BUTTON_WHEEL_DOWN
	wheel.pressed = true
	wheel.position = at
	wheel.global_position = at
	get_viewport().push_input(wheel, true)
	await get_tree().process_frame
	_check("wheel scrolling works over player cards", score_scroll.scroll_vertical > 0)
	score_scroll.scroll_vertical = 0
	await get_tree().process_frame
	var touch := InputEventScreenTouch.new()
	touch.index = 0
	touch.pressed = true
	touch.position = at
	get_viewport().push_input(touch, true)
	var swipe := InputEventScreenDrag.new()
	swipe.index = 0
	swipe.position = at - Vector2(0, 100)
	swipe.relative = Vector2(0, -100)
	get_viewport().push_input(swipe, true)
	touch.pressed = false
	touch.position = swipe.position
	get_viewport().push_input(touch, true)
	await get_tree().process_frame
	_check("finger swipes work over player cards", score_scroll.scroll_vertical >= 90, "scroll=%s touch=%s at=%s rect=%s" % [score_scroll.scroll_vertical, score_scroll._touch_index, at, score_scroll.get_global_rect()])
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	press.position = at
	press.global_position = at
	get_viewport().push_input(press, true)
	var motion := InputEventMouseMotion.new()
	motion.position = at - Vector2(0, 1000)
	motion.global_position = motion.position
	motion.relative = Vector2(0, -1000)
	motion.button_mask = MOUSE_BUTTON_MASK_LEFT
	get_viewport().push_input(motion, true)
	press.pressed = false
	press.position = motion.position
	press.global_position = motion.position
	get_viewport().push_input(press, true)
	await get_tree().process_frame
	var last_row: Control = score_rows.get_child(5)
	_check("dragging reaches the full sixth player's row above the footer", last_row.get_global_rect().end.y <= score_scroll.get_global_rect().end.y + 1 and last_row.global_position.y >= score_scroll.global_position.y)
	score_scroll.ensure_control_visible(score_rows.get_child(3))
	await get_tree().process_frame
	var fourth: Control = score_rows.get_child(3)
	_check("the complete fourth player's score is reachable", fourth.global_position.y >= score_scroll.global_position.y - 1 and fourth.get_global_rect().end.y <= score_scroll.get_global_rect().end.y + 1)
	await _shot("six-players")

	# A wrong declaration shows the complete hand, including thirteen separate groups.
	var wrong_result := _pool_round()
	wrong_result.players[0].outcome = "wrong_declaration"
	wrong_result.players[0].points = 80
	wrong_result.players[0].eliminated = true
	var singles: Array = []
	for card: Dictionary in wrong_result.players[0].melds[0].cards:
		singles.append({"cards": [card]})
	wrong_result.players[0].melds = singles
	_set_result(2, "round_over", {"poolLimit": 240}, wrong_result)
	await _wait(1.6)
	_check("wrong declaration has its own label", _row_has(0, "Wrong Declaration") and not _row_has(0, "DROPPED"))
	_check("wrong declaration reveals every card", _cards_in(0).size() == 13 and _cards_in(0).all(func(view: CardView) -> bool: return not view.face_down))
	var shown_hand: Control = _row(0).find_child("ResultHand", true, false)
	_check("thirteen ungrouped cards fit inside the hand column", _cards_in(0).all(func(view: CardView) -> bool: return shown_hand.get_global_rect().encloses(view.get_global_rect())))

	# ---------- a game that ends during play: the buttons are in place in the very first frame ----------
	# (on a new table, whose result buttons have never been laid out before)
	_table.queue_free()
	_set_result(5, "playing", {"poolLimit": 201}, _pool_finished())
	_table = (load("res://scenes/table.tscn") as PackedScene).instantiate()
	add_child(_table)
	await _wait(0.6)
	_check("during play there is no result", not _shown("ResultOverlay"))
	_set_result(5, "finished", {"poolLimit": 201}, _pool_finished())
	var back := (_node("BackButton") as Control).get_global_rect()
	var again := (_node("PlayAgainButton") as Control).get_global_rect()
	_check("in the first frame Leave Game and Play Again do not lie on each other", not back.intersects(again) and back.position.x < again.position.x, "%s / %s" % [back, again])

	print("scorecard preview: %d passed, %d failed" % [_passed, _failed])
	Game.socket.is_online = false
	Game.state = {}
	get_tree().quit(1 if _failed > 0 else 0)


# ---------- made-up results ----------

func _pool_round() -> Dictionary:
	return {"round": 2, "winner": "2", "matchOver": false, "matchWinner": null, "players": [
		{"id": "1", "username": "Sujin", "outcome": "dropped", "points": 20, "totalScore": 20, "eliminated": false,
			"melds": [{"cards": _cards(["4♠", "5♠", "K♠", "3♥", "6♥", "9♥", "6♦", "9♦", "10♦", "Q♦", "K♦", "4♣", "9♣"])}]},
		{"id": "2", "username": "guest8230642", "outcome": "winner", "points": 0, "totalScore": 0, "eliminated": false,
			"melds": [{"cards": _cards(["7♥", "6♥", "5♥"])}, {"cards": _cards(["7♠", "6♠", "5♠"])}, {"cards": _cards(["10♣", "J♣", "Q♣", "JK"])}, {"cards": _cards(["Q♦", "Q♥", "Q♠"])}]},
	]}


func _pool_finished() -> Dictionary:
	return {"round": 3, "winner": "2", "matchOver": true, "matchWinner": "2", "players": [
		{"id": "1", "username": "Sujin", "outcome": "lost", "points": 20, "totalScore": 120, "eliminated": true,
			"melds": [{"cards": _cards(["4♠", "5♠", "K♠"])}, {"cards": _cards(["3♥", "6♥", "9♥"])}, {"cards": _cards(["6♦", "9♦", "10♦", "Q♦", "K♦"])}, {"cards": _cards(["4♣", "9♣"])}]},
		{"id": "2", "username": "guest8230642", "outcome": "winner", "points": 0, "totalScore": 0, "eliminated": false,
			"melds": [{"cards": _cards(["Q♥", "JK", "2♦"])}, {"cards": _cards(["7♦", "3♠", "A♠", "Q♣"])}, {"cards": _cards(["9♥", "7♣", "2♥"])}, {"cards": _cards(["J♦", "A♦", "2♠"])}]},
	]}


func _deals_round() -> Dictionary:
	return {"round": 1, "winner": "2", "matchOver": false, "matchWinner": null, "players": [
		{"id": "1", "username": "Sujin", "outcome": "dropped", "points": 20, "totalScore": 20, "chips": 140, "chipsWon": -20, "eliminated": false,
			"melds": [{"cards": _cards(["4♠", "5♠", "K♠", "3♥", "6♥", "9♥", "6♦", "9♦", "10♦", "Q♦", "K♦", "4♣", "9♣"])}]},
		{"id": "2", "username": "guest8230642", "outcome": "winner", "points": 0, "totalScore": 0, "chips": 180, "chipsWon": 20, "eliminated": false,
			"melds": [{"cards": _cards(["A♥", "2♥", "3♥"])}, {"cards": _cards(["5♣", "6♣", "7♣", "8♣"])}, {"cards": _cards(["K♦", "K♠", "K♥"])}, {"cards": _cards(["9♠", "9♦", "JK"])}]},
	]}


func _six_players() -> Dictionary:
	var rows: Array = []
	for index in NAMES.size():
		var outcome := "winner" if index == 3 else ("dropped" if index == 4 else "lost")
		var points := 0 if index == 3 else (40 if index == 4 else 12 + index * 9)
		rows.append({"id": str(index + 1), "username": NAMES[index], "outcome": outcome, "points": points, "totalScore": points + index * 15, "eliminated": false,
			"melds": [{"cards": _cards(["2♠", "3♠", "4♠"])}, {"cards": _cards(["7♥", "8♥", "9♥", "10♥"])}, {"cards": _cards(["K♦", "K♣", "K♥"])}, {"cards": _cards(["4♣", "9♦", "Q♠"])}]})
	return {"round": 4, "winner": "4", "matchOver": false, "matchWinner": null, "players": rows}


func _cards(codes: Array) -> Array:
	var cards: Array = []
	for code: String in codes:
		if code == "JK":
			cards.append({"id": "JK-%d" % cards.size(), "suit": null, "value": "JOKER", "code": "JK", "isJoker": true})
		else:
			cards.append({"id": "%s-%d" % [code, randi() % 1000], "suit": code.right(1), "value": code.left(-1), "code": code, "isJoker": false})
	return cards


# The table as the server would send it once a round or the game is over.
func _set_result(seats: int, status: String, rules: Dictionary, result: Dictionary) -> void:
	var players: Array = []
	for row: Dictionary in result.players:
		players.append({"id": row.id, "username": row.username, "status": "active", "connected": true, "handCount": 13,
			"avatar": 0, "totalScore": row.totalScore, "eliminated": row.eliminated})
	Game.state = {
		"gameId": "preview-%d" % seats, "roomCode": "PRVW42", "status": status, "currentPlayer": null,
		"players": players, "hand": [], "groups": [], "discardTop": {}, "deckCount": 0,
		"joker": {"id": "A♣-2", "suit": "♣", "value": "A", "code": "A♣", "isJoker": false},
		"round": result.round, "maxPlayers": maxi(2, players.size()), "lastResult": result,
	}
	Game.state.merge(rules)
	Game.next_round_at = Time.get_ticks_msec() + 11000 if status == "round_over" else 0
	Game.state_changed.emit()


# ---------- reading the screen ----------

func _node(node_name: String) -> Node:
	return _table.find_child(node_name, true, false)


func _shown(node_name: String) -> bool:
	var node := _node(node_name) as CanvasItem
	return node != null and node.is_visible_in_tree()


func _text(node_name: String) -> String:
	var node := _node(node_name)
	return str(node.get("text")) if node != null else ""


func _text_in(node_name: String) -> String:
	var texts: Array[String] = []
	for label: Label in _node(node_name).find_children("*", "Label", true, false):
		texts.append(label.text)
	return " | ".join(texts)


func _row(index: int) -> Node:
	return _node("ResultRows").get_child(index)


func _row_texts(index: int) -> Array[String]:
	var texts: Array[String] = []
	for label: Label in _row(index).find_children("*", "Label", true, false):
		texts.append(label.text)
	return texts


func _row_has(index: int, text: String) -> bool:
	return _row_texts(index).any(func(found: String) -> bool: return found.contains(text))


# The score and the total, the two big numbers of a row.
func _row_numbers(index: int) -> Array:
	var numbers: Array = []
	for label: Label in _row(index).find_children("*", "Label", true, false):
		if label.get_theme_font_size("font_size") == 34:
			numbers.append(label.text)
	return numbers


func _cards_in(index: int) -> Array:
	return _row(index).find_children("*", "Control", true, false).filter(func(node: Node) -> bool: return node is CardView)


func _on_screen(node_name: String) -> bool:
	var control := _node(node_name) as Control
	return control != null and get_viewport().get_visible_rect().encloses(control.get_global_rect())


func _shot(label: String) -> void:
	_step += 1
	if _shots.is_empty() or DisplayServer.get_name() == "headless":
		return
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("%s/%02d-%s.png" % [_shots, _step, label])


func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout


func _check(what: String, ok: bool, detail: String = "") -> void:
	if ok:
		_passed += 1
	else:
		_failed += 1
		print("FAIL  %s  %s" % [what, detail])
