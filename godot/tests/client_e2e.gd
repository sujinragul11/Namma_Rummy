extends Node
## Two players in one process play through a real server: accounts, the Socket.IO connection,
## creating and joining a game, turns, a valid declaration, a dropped connection, a drop.
##
## Run against a TEST server (it registers throwaway accounts); tests/test_server.js is one:
##   godot --headless --path . res://tests/client_e2e.tscn -- --server=http://127.0.0.1:3101 --rig-flag=<file>
## While the flag file exists the test server deals a fixed hand (unshuffled deck, A♠ cut),
## which is what makes a valid declaration possible; with "closed" written in the file it
## deals the hands of the Close Joker game. Without --rig-flag those parts are skipped.

var _passed := 0
var _failed := 0
var _rig_flag := ""


func _ready() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--rig-flag="):
			_rig_flag = argument.trim_prefix("--rig-flag=")
	_run()


func _run() -> void:
	var tag := "%d%04d" % [int(Time.get_unix_time_from_system()) % 1000000, randi() % 10000]
	var name_a := "ga_" + tag
	var name_b := "gb_" + tag
	var a := _new_client()
	var b := _new_client()

	# ---------- accounts and connection ----------
	var r: Dictionary = await a.login(name_a, "secret12")
	_check("login before registering is refused", not r.ok and r.error == "Invalid credentials", str(r.error))

	# An account needs an email address and a mobile number, both of them and both well formed
	var phone_a := "9" + tag.substr(0, 9)
	var phone_b := "8" + tag.substr(0, 9)
	r = await a.register(name_a, name_a + "@test.local", "", "secret12")
	_check("registering without a mobile number is refused", not r.ok and str(r.error).begins_with("Enter a valid mobile number") and not a.is_logged_in(), str(r.error))
	r = await a.register(name_a, "", phone_a, "secret12")
	_check("registering without an email is refused", not r.ok and r.error == "Enter a valid email address", str(r.error))
	r = await a.register(name_a, "not-an-email", phone_a, "secret12")
	_check("a badly formed email is refused", not r.ok and r.error == "Enter a valid email address", str(r.error))
	r = await a.register(name_a, name_a + "@test.local", "12345", "secret12")
	_check("a badly formed mobile number is refused", not r.ok and str(r.error).begins_with("Enter a valid mobile number"), str(r.error))
	_check("the app's own check agrees with the server", not AccountRules.email_problem("not-an-email").is_empty() and not AccountRules.phone_problem("12345").is_empty() and AccountRules.email_problem(name_a + "@test.local").is_empty() and AccountRules.phone_problem(phone_a).is_empty())

	r = await a.register(name_a, name_a + "@Test.Local", "+91 %s %s" % [phone_a.substr(0, 5), phone_a.substr(5)], "secret12")
	_check("A registers with email and mobile number", r.ok and a.is_logged_in() and a.player_id.is_valid_int(), str(r.error))
	_check("the number is kept as its ten digits, the email in lower case", a.user.get("phone") == phone_a and a.user.get("email") == name_a + "@test.local", str(a.user))
	r = await b.register(name_b, name_b + "@test.local", phone_a, "secret12")
	_check("a mobile number already in use is refused", not r.ok and r.error == "Phone already in use", str(r.error))
	r = await b.register(name_b, name_b + "@test.local", phone_b, "secret12")
	_check("B registers with email and mobile number", r.ok and b.is_logged_in(), str(r.error))
	_check("both sockets connect with their token", await _until(func() -> bool: return a.is_online() and b.is_online()))
	_check("no table before joining anything", a.state.is_empty() and a.status() == "")

	var stranger := SocketIOClient.new()
	add_child(stranger)
	var refusals: Array = []
	stranger.connect_refused.connect(func(message: String) -> void: refusals.append(message))
	stranger.open(a.server_url, {"token": "garbage"})
	await _until(func() -> bool: return not refusals.is_empty(), 4.0)
	_check("a bad token is refused", refusals == ["Authentication required"] and not stranger.is_online, str(refusals))
	stranger.queue_free()

	var again := _new_client()
	r = await again.login("  %s " % name_a.to_upper(), "secret12")
	_check("login by username typed with capitals and spaces", r.ok and again.player_id == a.player_id, str(r.error))
	again.logout()
	r = await again.login("0" + phone_a, "secret12")
	_check("login by mobile number, typed with a leading 0", r.ok and again.player_id == a.player_id, str(r.error))
	again.logout()
	again.queue_free()

	r = await a.draw()
	_check("a move without a game is refused", not r.ok and r.error == "Game not found", str(r.error))

	# ---------- game 1: fixed deal, regroup, valid declaration ----------
	if _rig_flag.is_empty():
		print("skipped: fixed-deal game (no --rig-flag given)")
	else:
		await _play_fixed_deal(a, b)

	# ---------- game 2: normal deal, open pile, dropped connection, drop ----------
	r = await a.create_game("points", 2)
	r = await b.join_by_code(str(r.get("roomCode", "")))
	_check("second game dealt", r.ok and await _until(func() -> bool: return a.hand().size() == 13 and b.hand().size() == 13))
	r = await a.discard(str(a.hand()[0].id))
	_check("discard before drawing is refused", not r.ok and r.error == "Draw a card first", str(r.error))
	r = await a.draw()
	_check("A draws", r.ok and await _until(func() -> bool: return a.hand().size() == 14))
	r = await a.draw()
	_check("drawing twice is refused", not r.ok and r.error == "You have already drawn a card", str(r.error))
	var thrown := str(a.hand()[0].id)
	r = await a.discard(thrown)
	_check("discard passes the turn", r.ok and await _until(func() -> bool: return b.is_my_turn() and a.hand().size() == 13))
	_check("the open pile shows the discard", b.state.discardTop.id == thrown)
	_check("the discarded card left A's arrangement", not a.groups.any(func(group: Array) -> bool: return group.has(thrown)))

	r = await b.draw(true)
	_check("B picks from the open pile", r.ok and await _until(func() -> bool: return b.hand().size() == 14) and not b.card(thrown).is_empty())
	r = await b.discard(thrown)
	_check("throwing the picked card straight back is refused", not r.ok and str(r.error).contains("cannot discard"), str(r.error))

	# The connection drops and comes back, as if the app had been restarted
	var arranged: Array = b.groups.duplicate(true)
	arranged.reverse()
	b.set_groups(arranged)
	await get_tree().create_timer(0.4).timeout
	b.socket.close()
	_check("B is offline", not b.is_online())
	_check("A sees B offline", await _until(func() -> bool: return _seat(a, b.player_id).get("connected") == false))
	b.state = {}
	b.groups = []
	b.socket.open(b.server_url, {"token": b.token})
	_check("the server puts B back at the table", await _until(func() -> bool: return b.status() == "playing" and b.hand().size() == 14))
	_check("B's arrangement comes back from the server", b.groups == arranged, "%s vs %s" % [b.groups, arranged])
	_check("A sees B online again", await _until(func() -> bool: return _seat(a, b.player_id).get("connected") == true))

	var other := ""
	for held: Dictionary in b.hand():
		if held.id != thrown:
			other = held.id
			break
	r = await b.discard(other)
	_check("B discards another card", r.ok and await _until(func() -> bool: return a.is_my_turn()))
	r = await a.drop()
	_check("A drops", r.ok and await _until(func() -> bool: return a.status() == "finished" and b.status() == "finished"))
	_check("B wins and A pays 40", a.state.winner == b.player_id and int(_result_row(a, a.player_id).get("points", -1)) == 40)
	await a.leave()
	await b.leave()

	# ---------- game 3: pool rounds have a countdown to the next deal ----------
	r = await a.create_game("pool", 2)
	r = await b.join_by_code(str(r.get("roomCode", "")))
	await _until(func() -> bool: return a.hand().size() == 13 and a.is_my_turn())
	_check("pool game shows its limit", int(a.state.get("poolLimit", 0)) == 101)
	r = await a.drop()
	_check("pool: the round ends but not the match", r.ok and await _until(func() -> bool: return b.status() == "round_over"))
	_check("pool: countdown to the next round", b.next_round_at > Time.get_ticks_msec() and b.seconds_until(b.next_round_at) <= 12)
	_check("pool: totals are kept", int(_seat(b, a.player_id).get("totalScore", -1)) == 20)
	await a.leave()
	await b.leave()
	_check("both left the table", a.state.is_empty() and b.state.is_empty())

	# ---------- game 4: Close Joker, the joker opens with the first pure sequence ----------
	if _rig_flag.is_empty():
		print("skipped: Close Joker game (no --rig-flag given)")
	else:
		await _play_close_joker(a, b)

	# ---------- a private table: for friends, by room code only ----------
	await _private_table(a, b)

	print("\nclient end-to-end: %d passed, %d failed" % [_passed, _failed])
	get_tree().quit(1 if _failed > 0 else 0)


func _play_fixed_deal(a: GameClient, b: GameClient) -> void:
	_set_rigged(true)
	var r: Dictionary = await a.create_game("points", 2)
	var room := str(r.get("roomCode", ""))
	_check("create game", r.ok and room.length() == 6 and r.get("status") == "waiting", str(r))
	_check("host is in the lobby", await _until(func() -> bool: return a.status() == "waiting"))
	_check("lobby lists the host", a.players().size() == 1 and a.state.hostId == a.player_id and a.state.roomCode == room)

	r = await b.join_by_code("zzzzzz")
	_check("unknown room code", not r.ok and r.error == "Game not found", str(r.error))
	r = await b.join_by_code(" %s " % room.to_lower())
	_check("join by room code", r.ok and r.get("status") == "playing", str(r))
	_check("both are dealt 13 cards", await _until(func() -> bool: return a.hand().size() == 13 and b.hand().size() == 13))
	_set_rigged(false)

	_check("the host has the first turn", a.is_my_turn() and not b.is_my_turn() and a.state.turnPhase == "draw")
	_check("a fresh deal is sorted into suit groups", a.groups.size() == 2 and a.groups[0].size() == 12 and a.groups[1] == ["JOKER-1"], str(a.groups))
	_check("the sorted run is recognised", Rummy.classify_meld(a.meld_cards()[0], a.state.joker) == "pure_sequence")
	_check("aces are wild after an ace is cut", Rummy.wild_rank(a.state.joker) == "A" and a.state.wildRank == "A")
	var a_view := JSON.stringify(a.state)
	_check("the opponent's cards are never sent", b.hand().all(func(held: Dictionary) -> bool: return not a_view.contains('"%s"' % held.id)))
	_check("the turn clock is running", a.turn_ends_at > Time.get_ticks_msec() and a.seconds_until(a.turn_ends_at) <= 30)

	r = await b.draw()
	_check("not your turn", not r.ok and r.error == "Not your turn", str(r.error))
	r = await a.draw()
	_check("draw", r.ok and await _until(func() -> bool: return a.hand().size() == 14))
	_check("the drawn card sits alone at the right", a.groups.back() == ["K♥-1"] and a.state.lastDrawnId == "K♥-1", str(a.groups))
	_check("the opponent sees 14 cards", await _until(func() -> bool: return int(_seat(b, a.player_id).get("handCount", 0)) == 14))

	# Regroup the way a player would: 2-3-4 of clubs, then 5..K of clubs with the joker
	var clubs: Array = a.groups[0]
	a.set_groups([clubs.slice(0, 3), clubs.slice(3) + ["JOKER-1"], ["K♥-1"]])
	var types: Array = a.meld_cards().map(func(cards: Array) -> String: return Rummy.classify_meld(cards, a.state.joker))
	_check("regrouped hand is judged locally", types == ["pure_sequence", "impure_sequence", "invalid"], str(types))

	# B has not arranged anything: every card lies on its own, which would cost the full 80
	b.set_groups(b.hand().map(func(held: Dictionary) -> Array: return [held.id]))
	_check("B's scattered hand would cost 80", Rummy.evaluate_hand(b.meld_cards(), b.state.joker).points == 80)
	await get_tree().create_timer(0.4).timeout

	r = await a.declare("K♥-1")
	_check("valid declaration", r.ok and r.get("valid") == true, str(r))

	# The round is won, but before the hands are counted the other player gets 15 seconds
	_check("after a declaration the round waits for the other player", await _until(func() -> bool: return b.declared_by() == a.player_id) and a.status() == "playing" and b.status() == "playing", "%s / %s" % [a.status(), b.status()])
	_check("the other player is the one to arrange, not the declarer", b.arranging() and not a.arranging() and a.declared_by() == a.player_id)
	var seconds_left := b.seconds_until(b.turn_ends_at)
	_check("the clock gives them 15 seconds", seconds_left <= 15 and seconds_left >= 13, str(seconds_left))
	r = await b.draw()
	_check("nobody can play on meanwhile", not r.ok and r.error == "Not your turn", str(r.error))
	r = await a.submit_hand()
	_check("the declarer has nothing to hand in", not r.ok and r.error == "Your cards are already in", str(r.error))

	b.sort_hand()  # the diamonds 2 to K become one run, and the ace of clubs is wild
	var b_points: int = Rummy.evaluate_hand(b.meld_cards(), b.state.joker).points
	_check("arranged, B's hand costs nothing", b_points == 0, str(b_points))
	r = await b.submit_hand()
	_check("handing the cards in ends the round at once", r.ok and await _until(func() -> bool: return a.status() == "finished" and b.status() == "finished", 4.0))
	_check("A is the winner", a.state.winner == a.player_id and a.state.lastResult.matchWinner == a.player_id)
	var b_row := _result_row(b, b.player_id)
	_check("the loser is charged for the hand as arranged in that time, not as it lay before", int(b_row.get("points", -1)) == b_points, "%s vs %s" % [b_row.get("points"), b_points])
	_check("the declaration is settled", a.declared_by().is_empty() and b.declared_by().is_empty())
	var a_row := _result_row(b, a.player_id)
	var shown: Array = a_row.get("melds", []).map(func(meld: Dictionary) -> String: return meld.type)
	_check("the winner's hand is shown to the loser", shown == ["pure_sequence", "impure_sequence"], str(shown))
	await a.leave()
	await b.leave()
	_check("left the table", a.state.is_empty() and b.state.is_empty())


# The hands of this game are the CLOSED_DEAL in tests/test_server.js: A can make 2-3-4 of
# spades, B can make no sequence at all, and the 7 of hearts is cut as the joker.
func _play_close_joker(a: GameClient, b: GameClient) -> void:
	_set_rigged(true, "closed")
	var r: Dictionary = await a.create_game("close_joker", 2)
	_check("close joker: the game can be created", r.ok and await _until(func() -> bool: return a.status() == "waiting"), str(r))
	_check("close joker: the lobby names it, with its limit", a.game_name() == "Close Joker 240" and a.is_pool() and a.state.get("closedJoker") == true, a.game_name())
	r = await b.join_by_code(str(r.get("roomCode", "")))
	await _until(func() -> bool: return a.hand().size() == 13 and b.hand().size() == 13)
	_set_rigged(false)
	if a.card("2♠-1").is_empty() or a.card("9♠-1").is_empty():
		print("skipped: Close Joker game (this test server does not know the \"closed\" deal)")
		await a.leave()
		await b.leave()
		return

	# Both hands have been sorted by suit and sent to the server by now, which opens nothing
	await get_tree().create_timer(0.5).timeout
	_check("close joker: the joker is not sent at the deal", a.joker_hidden() and a.state.get("joker") == null and a.state.get("wildRank") == null and b.joker_hidden() and b.state.get("joker") == null)
	_check("close joker: it is nowhere in what the server sent", not JSON.stringify(a.state).contains("7♥") and not JSON.stringify(b.state).contains("7♥"))
	_check("close joker: without it the sevens are ordinary cards", not Rummy.is_wild({"value": "7", "suit": "♣"}, a.state.get("joker")))

	var told: Array = []
	b.notice.connect(func(_kind: String, message: String) -> void: told.append(message))
	# A takes 2-3-4 of spades out of the spades: the first life
	var spades: Array = a.groups[0]
	a.set_groups([spades.slice(0, 3), spades.slice(3)] + a.groups.slice(1))
	_check("close joker: a pure sequence opens the joker", await _until(func() -> bool: return not a.joker_hidden()) and a.state.joker.code == "7♥" and a.state.wildRank == "7", str(a.state.get("joker")))
	_check("close joker: only for the player who made it", await _until(func() -> bool: return _seat(b, a.player_id).get("seenJoker") == true) and b.joker_hidden() and b.state.get("joker") == null)
	_check("close joker: the opponent is told", told.any(func(message: String) -> bool: return message.contains("has seen the joker")), str(told))

	r = await a.draw()
	await _until(func() -> bool: return a.hand().size() == 14)
	r = await a.discard(str(a.state.lastDrawnId))
	_check("close joker: play goes on as in pool", r.ok and await _until(func() -> bool: return b.is_my_turn()))
	_check("close joker: a turn later it is still closed for the other player", b.joker_hidden())
	r = await b.drop()
	_check("close joker: the round ends but not the match", r.ok and await _until(func() -> bool: return a.status() == "round_over" and b.status() == "round_over"))
	_check("close joker: after the round it lies open for everyone", not b.joker_hidden() and b.state.joker.code == "7♥")
	_check("close joker: scored as pool, a first drop costs 20", int(_seat(a, b.player_id).get("totalScore", -1)) == 20)
	await a.leave()
	await b.leave()


func _private_table(a: GameClient, b: GameClient) -> void:
	var r: Dictionary = await a.create_game("points", 3, 0, true)
	var room := str(r.get("roomCode", ""))
	_check("private: the table is created with a room code", r.ok and room.length() == 6 and await _until(func() -> bool: return a.status() == "waiting"), str(r))
	_check("private: the state says it is private", a.state.get("private") == true, str(a.state.get("private")))
	var listed: Dictionary = await b._http(HTTPClient.METHOD_GET, "/api/games/active")
	var codes: Array = (listed.data.get("games", []) as Array).map(func(game: Dictionary) -> String: return str(game.get("room_code")))
	_check("private: it is not among the open tables", listed.ok and not codes.has(room), str(codes.size()))
	var by_id: Dictionary = await b.socket.request("joinGame", {"gameId": str(r.get("gameId", ""))})
	_check("private: it cannot be joined without the code", not by_id.get("ok", false) and str(by_id.get("error", "")).contains("private table") and b.state.is_empty(), str(by_id))
	r = await b.join_by_code(room.to_lower())
	_check("private: a friend with the code sits down", r.ok and await _until(func() -> bool: return a.players().size() == 2 and b.state.get("private") == true), str(r))
	await b.leave()
	await a.leave()

	r = await a.create_game("points", 2)
	room = str(r.get("roomCode", ""))
	listed = await b._http(HTTPClient.METHOD_GET, "/api/games/active")
	codes = (listed.data.get("games", []) as Array).map(func(game: Dictionary) -> String: return str(game.get("room_code")))
	_check("an ordinary table is listed and not private", codes.has(room) and a.state.get("private") == false, str(a.state.get("private")))
	await a.leave()


func _new_client() -> GameClient:
	var client := GameClient.new()
	client.remember_login = false
	add_child(client)
	return client


func _seat(client: GameClient, id: String) -> Dictionary:
	for player: Dictionary in client.players():
		if player.get("id") == id:
			return player
	return {}


func _result_row(client: GameClient, id: String) -> Dictionary:
	var result: Variant = client.state.get("lastResult")
	if result is Dictionary:
		for row: Dictionary in result.get("players", []):
			if row.get("id") == id:
				return row
	return {}


# What is written in the flag file names the fixed deal; "1" is the unshuffled deck.
func _set_rigged(on: bool, deal: String = "1") -> void:
	if on:
		FileAccess.open(_rig_flag, FileAccess.WRITE).store_string(deal)
	elif FileAccess.file_exists(_rig_flag):
		DirAccess.remove_absolute(_rig_flag)


# Waits until the condition holds, or gives up after `seconds`.
func _until(condition: Callable, seconds: float = 6.0) -> bool:
	var deadline := Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < deadline:
		if condition.call():
			return true
		await get_tree().process_frame
	return condition.call()


func _check(what: String, ok: bool, detail: String = "") -> void:
	if ok:
		_passed += 1
	else:
		_failed += 1
		print("FAIL  %s  %s" % [what, detail])
