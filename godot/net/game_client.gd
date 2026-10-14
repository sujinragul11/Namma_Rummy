class_name GameClient
extends Node
## One player's session: the login, the game socket, and the latest table state from the server.
##
## The project runs one of these as the `Game` autoload. Screens read from it and call its
## actions without waiting for the answer: results come back through the signals below, so a
## screen that has been closed in the meantime is never left waiting.

signal auth_changed
signal auth_failed(message: String)
signal connection_changed
signal state_changed
signal busy_changed
signal notice(kind: String, message: String)
signal action_failed(message: String)
signal friends_changed
signal coins_changed
signal profile_changed
## A friend calls us to their table: {"username", "roomCode", "poolLimit", "closedJoker",
## "deals", "maxPlayers", "stake", "pointValue"}.
signal invite_received(invite: Dictionary)
## "Play Now": a search for players began, moved on (see match_status) or ended.
signal match_changed

const HTTP_TIMEOUT := 10.0
## What the server answers to a move when it no longer has the table we are sitting at.
const GAME_GONE_ERROR := "Game not found"
## What a Pool or Deals table can cost to sit at, in coins; 0 is a free table. The server has
## the same list.
const STAKES := [0, 500, 1000, 2000, 5000, 10000, 25000, 50000]
## Points Rummy is played for so many coins a point: every loser pays the winner their points
## times that. Sitting down holds what MAX_POINTS points cost, and what is not lost comes back.
const POINT_VALUES := [0, 5, 10, 20, 50, 100, 200, 500]
const MAX_POINTS := 80

## Tests set this to false so their throwaway logins are not saved.
var remember_login := true
## Where the backend is. Empty means: use the saved setting.
var server_url := ""

var user: Dictionary = {}
var token := ""
## Our id as it appears in table states.
var player_id := ""
## Our play coins. The server keeps the balance and sends it when we connect and whenever it
## changes: an entry paid, an entry given back, a pot won.
var coins := 0
## The latest table state from the server; empty when not in a game.
var state: Dictionary = {}
## How our hand is arranged: arrays of card ids.
var groups: Array = []
## Deadlines as Time.get_ticks_msec() values; 0 when no clock is running.
var turn_ends_at := 0
var next_round_at := 0
## How long the current turn lasts in all (msec), so the clock can be drawn as a shrinking ring.
var turn_total := 0
## Our friends, as {"id", "username", "status"}; status is "online", "lobby" (waiting at a
## table), "playing" or "offline".
var friends: Array = []
## Players who ask to be our friend, players we asked, and players we met at a table who are
## in none of the lists yet; each {"id", "username"}.
var friend_requests: Array = []
var friend_asked: Array = []
var recent_players: Array = []
## Our account as the server has it, with the games counted: {"username", "email", "phone",
## "coins", "totalGames", "gamesWon", "winPercentage", "created_at"}. Empty until fetched.
var profile: Dictionary = {}
## "Play Now": the table we are looking for players for, as sent to the server; empty when
## not searching.
var match_search: Dictionary = {}
## Where the search stands, as the server last told it: {"found", "needed", "inQueue",
## "scope" ("region", "nearby" or "everywhere"), "region" (e.g. "UTC+5:30")}. Empty until then.
var match_status: Dictionary = {}
## When the search began, and when a table found with free seats starts anyway
## (Time.get_ticks_msec() values; match_starts_at is 0 while there is no such table yet).
var match_since := 0
var match_starts_at := 0
var socket: SocketIOClient
## True while a request is on its way to the server.
var busy: bool:
	get:
		return _pending > 0

var _pending := 0
var _friends_known := false  # false until the server has sent the lists once


func _ready() -> void:
	if server_url.is_empty():
		server_url = Config.server_url

	socket = SocketIOClient.new()
	add_child(socket)
	socket.connected.connect(_on_connected)
	socket.disconnected.connect(func() -> void: connection_changed.emit())
	socket.connect_refused.connect(_on_connect_refused)
	socket.event_received.connect(_on_event)

	if remember_login:
		var saved := Config.load_login()
		if not saved.is_empty():
			_set_login(saved.token, saved.user)


# ---------- account ----------

func is_logged_in() -> bool:
	return not token.is_empty()


func is_online() -> bool:
	return socket.is_online


func set_server_url(url: String) -> void:
	var clean := Config.clean_server_url(url)
	if clean == server_url:
		return
	server_url = clean
	if remember_login:
		Config.set_server_url(clean)


func register(username: String, email: String, phone: String, password: String) -> Dictionary:
	var body := {"username": username.strip_edges(), "password": password}
	if not email.strip_edges().is_empty():
		body["email"] = email.strip_edges()
	if not phone.strip_edges().is_empty():
		body["phone"] = phone.strip_edges()
	return await _authenticate("/api/auth/register", body)


## `identifier` is an email, phone number or username.
func login(identifier: String, password: String) -> Dictionary:
	var body := {"identifier": identifier.strip_edges(), "password": password}
	return await _authenticate("/api/auth/login", body)


func logout() -> void:
	_stop_search()
	socket.close()
	token = ""
	user = {}
	player_id = ""
	coins = 0
	_forget_game()
	_forget_friends()
	if remember_login:
		Config.clear_login()
	auth_changed.emit()
	state_changed.emit()


## Deletes the account for good, after the server has checked the password again.
## On success the player is logged out.
func delete_account(password: String) -> Dictionary:
	_begin()
	var response: Dictionary = await _http(HTTPClient.METHOD_POST, "/api/user/delete", {"password": password})
	_end()
	if response.ok:
		logout()
		notice.emit("info", "Your account has been deleted")
	else:
		action_failed.emit(response.error)
	return response


# ---------- reading the table ----------

## "waiting", "playing", "round_over", "finished", or "" when not in a game.
func status() -> String:
	return str(state.get("status", ""))


func hand() -> Array:
	return state.get("hand", [])


func players() -> Array:
	return state.get("players", [])


## Our own entry in the player list, or an empty Dictionary.
func me() -> Dictionary:
	for player: Dictionary in players():
		if player.get("id") == player_id:
			return player
	return {}


func player_name(id: Variant) -> String:
	for player: Dictionary in players():
		if player.get("id") == id:
			return str(player.get("username", "Player"))
	return "Player"


func is_my_turn() -> bool:
	return status() == "playing" and state.get("currentPlayer") == player_id


## The coins each player paid to sit at this table; 0 at a free table. At a Points table
## played for a value a point, this is what is held while playing (see point_value).
func stake() -> int:
	return int(state.get("stake", 0))


## Coins a point at a Points table; 0 when the table is free or the winner takes the pot.
func point_value() -> int:
	return int(state.get("pointValue", 0))


## What the winner of this table takes: everything that was paid in. 0 at a Points table
## played for a value a point, where each loser pays the winner their own points.
func pot() -> int:
	return int(state.get("pot", 0))


## True for the games played round after round up to a points limit (Pool 101, Pool 201,
## Close Joker).
func is_pool() -> bool:
	return state.get("poolLimit") != null


## Deals Rummy: how many deals are played; 0 in any other game.
func deals() -> int:
	var count: Variant = state.get("deals")
	return 0 if count == null else int(count)


## What is being played, e.g. "Pool 101".
func game_name() -> String:
	return name_of_game(state.get("poolLimit"), state.get("closedJoker", false), state.get("deals"))


## What a game with these rules is called. `pool_limit` is null for a Points game, `deals`
## null or 0 unless it is a Deals game.
func name_of_game(pool_limit: Variant, closed_joker: bool, deal_count: Variant = null) -> String:
	if deal_count != null and int(deal_count) > 0:
		return "%d-Deal" % int(deal_count)
	if pool_limit == null:
		return "Points"
	return ("Close Joker %d" if closed_joker else "Pool %d") % int(pool_limit)


## The table described for a request. `stake` is the entry each player pays to sit down (one
## of STAKES), which the winner takes. A Points table can instead be played for `point_value`
## coins a point (one of POINT_VALUES; -1 for none), and `stake` is then not used.
static func table_request(game_type: String, max_players: int, stake: int, point_value: int = -1) -> Dictionary:
	var request := {"gameType": game_type, "maxPlayers": max_players}
	if game_type == "points" and point_value >= 0:
		request["pointValue"] = point_value
	else:
		request["stake"] = stake
	return request


## Close Joker: true while this round's joker still lies face down for us. It opens once our
## hand holds a pure sequence; until then the server does not send it.
func joker_hidden() -> bool:
	return state.get("jokerHidden", false)


## The player whose valid declaration has won the round, while the others still have their
## short time to arrange their own cards before the hands are counted; "" at any other time.
func declared_by() -> String:
	var id: Variant = state.get("declaredBy")
	return "" if id == null or status() != "playing" else str(id)


## True while it is on us to arrange our cards and hand them in after someone else's declaration.
func arranging() -> bool:
	var by := declared_by()
	var seat := me()
	return not by.is_empty() and by != player_id and seat.get("status") == "active" and not seat.get("submitted", false)


func card(card_id: String) -> Dictionary:
	for held: Dictionary in hand():
		if held.get("id") == card_id:
			return held
	return {}


## The hand as arranged: an array of groups, each an array of cards.
func meld_cards() -> Array:
	var cards_by_id := {}
	for held: Dictionary in hand():
		cards_by_id[held.id] = held
	var melds: Array = []
	for group: Array in groups:
		var cards: Array = []
		for id: Variant in group:
			if cards_by_id.has(id):
				cards.append(cards_by_id[id])
		melds.append(cards)
	return melds


## Whole seconds left until a deadline such as turn_ends_at.
func seconds_until(deadline: int) -> int:
	return maxi(0, ceili((deadline - Time.get_ticks_msec()) / 1000.0))


## How much of the current turn is left, from 1 (just started) down to 0 (time is up).
func turn_fraction() -> float:
	if turn_total <= 0 or turn_ends_at <= 0:
		return 0.0
	return clampf((turn_ends_at - Time.get_ticks_msec()) / float(turn_total), 0.0, 1.0)


# ---------- actions ----------

## `stake` is what each player pays to sit down, one of STAKES; the winner takes it all.
## `point_value` plays a Points table for coins a point instead (see table_request).
## A private table (`is_private`) is for the player's own friends: it is never listed, and
## only someone with its room code can sit down.
func create_game(game_type: String = "points", max_players: int = 2, stake: int = 0, is_private: bool = false, point_value: int = -1) -> Dictionary:
	var request := table_request(game_type, max_players, stake, point_value)
	request["private"] = is_private
	return await _ask("createGame", request)


## "Play Now": asks the server to find players who want the same table, the ones in our own
## region (time zone) first, with no room code. The search runs until the server seats us,
## which brings the table's state, or until cancel_match(). Follow it through match_changed.
func find_match(game_type: String, max_players: int, stake: int, point_value: int = -1) -> Dictionary:
	match_search = table_request(game_type, max_players, stake, point_value)
	match_search["timezone"] = time_zone_minutes()
	match_status = {}
	match_since = Time.get_ticks_msec()
	match_starts_at = 0
	match_changed.emit()
	var response: Dictionary = await _ask("findMatch", match_search)
	if not response.get("ok", false):
		_stop_search()
	elif searching() and match_status.is_empty():
		match_status = {"found": 1, "needed": max_players, "scope": "region", "region": str(response.get("region", ""))}
		match_changed.emit()
	return response


func cancel_match() -> void:
	if not searching():
		return
	_stop_search()
	if is_online():
		await socket.request("cancelMatch")


func searching() -> bool:
	return not match_search.is_empty()


## The phone's time zone in minutes east of UTC (330 in India). The server matches players by it.
static func time_zone_minutes() -> int:
	return int(Time.get_time_zone_from_system().get("bias", 0))


func join_by_code(room_code: String) -> Dictionary:
	return await _ask("joinGameByRoomCode", {"roomCode": room_code.strip_edges().to_upper()})


func start_game() -> Dictionary:
	return await _ask("startGame")


func draw(from_discard: bool = false) -> Dictionary:
	return await _ask("drawCard", {"fromDiscard": from_discard})


func discard(card_id: String) -> Dictionary:
	return await _ask("discardCard", {"cardId": card_id})


## Discards the finishing card; the rest of the hand is judged as currently grouped.
func declare(card_id: String) -> Dictionary:
	var remaining: Array = []
	for group: Array in groups:
		var kept := group.filter(func(id: Variant) -> bool: return id != card_id)
		if not kept.is_empty():
			remaining.append(kept)
	var response: Dictionary = await _ask("declare", {"cardId": card_id, "groups": remaining})
	if response.get("ok", false) and not response.get("valid", false):
		notice.emit("error", "Wrong declaration: you are out of this round with 80 points")
	return response


## After someone else's declaration: hands in our cards as they are grouped now. Without it
## they are counted as they lie when the time to arrange runs out.
func submit_hand() -> Dictionary:
	return await _ask("submitHand", {"groups": groups})


func drop() -> Dictionary:
	return await _ask("drop")


func set_groups(new_groups: Array) -> void:
	groups = new_groups.filter(func(group: Array) -> bool: return not group.is_empty())
	_send_groups()
	state_changed.emit()


func sort_hand() -> void:
	set_groups(Rummy.sort_into_groups(hand()))


func leave() -> void:
	# Whatever the server answers (we may be offline), this player is done with the table
	await socket.request("leaveGame")
	_forget_game()
	state_changed.emit()


## Asks the server for the table again. Used when the app comes back from the background,
## where the clocks kept running without us.
func resync() -> void:
	if not is_online() or state.is_empty():
		return
	var response: Dictionary = await socket.request("reconnectGame")
	var fresh: Variant = response.get("gameState")
	if response.get("ok", false) and fresh is Dictionary:
		_apply_state(fresh)
	elif response.get("error") == GAME_GONE_ERROR and status() in ["waiting", "playing", "round_over"]:
		_game_is_gone()  # a finished game may be gone: its result stays on screen


# ---------- profile ----------

## Asks the server for our account details and how many games we played and won.
func fetch_profile() -> Dictionary:
	var response: Dictionary = await _http(HTTPClient.METHOD_GET, "/api/user/profile")
	if response.ok:
		profile = response.data.get("user", {})
		profile_changed.emit()
	return response


## Changes the username and the email address.
func update_profile(username: String, email: String) -> Dictionary:
	_begin()
	var body := {"username": username.strip_edges(), "email": email.strip_edges()}
	var response: Dictionary = await _http(HTTPClient.METHOD_PATCH, "/api/user/profile", body)
	_end()
	if not response.ok:
		action_failed.emit(response.error)
		return response

	var saved: Dictionary = response.data.get("user", {})
	for key: String in ["username", "email"]:
		user[key] = saved.get(key, user.get(key))
		profile[key] = user[key]
	if remember_login:
		Config.save_login(token, user)
	# The server reads the name once, when the socket connects; connecting again makes tables,
	# invitations and friends lists show the new one
	socket.open(server_url, {"token": token})
	auth_changed.emit()
	profile_changed.emit()
	notice.emit("info", "Profile saved")
	return response


# ---------- friends ----------

## Asks a player to be our friend. If they had already asked us, this accepts.
func add_friend(username: String) -> Dictionary:
	var response: Dictionary = await _ask("friendRequest", {"username": username.strip_edges()})
	if response.get("ok", false):
		var friend_name := str(response.get("username", username))
		if response.get("accepted", false):
			notice.emit("info", "You and %s are now friends" % friend_name)
		else:
			notice.emit("info", "Friend request sent to %s" % friend_name)
	return response


## Answers a friend request: `answer` is "accept", "decline" or "block".
func answer_friend(user_id: String, answer: String) -> Dictionary:
	return await _ask("friendRespond", {"userId": user_id, "action": answer})


## Ends a friendship, or takes back a request we sent.
func remove_friend(user_id: String) -> Dictionary:
	return await _ask("friendRemove", {"userId": user_id})


## Calls a friend to the table we are waiting at.
func invite_friend(user_id: String) -> Dictionary:
	var response: Dictionary = await _ask("inviteFriend", {"userId": user_id})
	if response.get("ok", false):
		notice.emit("info", "Invitation sent to %s" % response.get("username", "your friend"))
	return response


## After a finished game: opens a new table with the same rules and the same entry, and calls
## the other players of that game to it. They do not have to be friends.
func play_again() -> Dictionary:
	var others: Array = []
	for player: Dictionary in players():
		if player.get("id") != player_id:
			others.append(player.get("id"))
	var game_type := str(state.get("gameType", "points"))
	var per_point := point_value() if point_value() > 0 else -1
	var response: Dictionary = await create_game(game_type, int(state.get("maxPlayers", 2)), stake(), state.get("private", false), per_point)
	if response.get("ok", false):
		for id: Variant in others:
			# Not through _ask: a player who has gone offline or already sits at another table
			# is simply not called, without a message about each of them
			socket.request("inviteFriend", {"userId": id})
	return response


## How many friends are connected right now, whatever they are doing.
func friends_online() -> int:
	var count := 0
	for friend: Dictionary in friends:
		if friend.get("status") != "offline":
			count += 1
	return count


# ---------- internals ----------

func _authenticate(path: String, body: Dictionary) -> Dictionary:
	_begin()
	var response: Dictionary = await _http(HTTPClient.METHOD_POST, path, body)
	_end()
	if response.ok:
		_set_login(str(response.data.get("token", "")), response.data.get("user", {}))
	else:
		auth_failed.emit(response.error)
	return response


func _set_login(new_token: String, new_user: Dictionary) -> void:
	token = new_token
	user = new_user
	player_id = str(int(new_user.get("id", 0)))  # JSON numbers arrive as floats
	coins = int(new_user.get("coins", 0))  # until the socket brings the balance of this moment
	coins_changed.emit()
	if remember_login:
		Config.save_login(token, user)
	socket.open(server_url, {"token": token})
	auth_changed.emit()


## Returns {"ok": bool, "error": String, "data": Dictionary}.
func _http(method: HTTPClient.Method, path: String, body: Variant = null) -> Dictionary:
	var unreachable := {
		"ok": false,
		"data": {},
		"error": "Cannot reach the game server at %s.\n\nCheck that the backend is running and that the server address is right." % server_url,
	}
	if Config.store_build:
		unreachable.error = "Cannot reach the game server.\n\nCheck your internet connection and try again."
	elif OS.has_feature("mobile"):
		# A test build on a phone: the server is a PC somewhere on the same network
		unreachable.error = "Cannot reach the game server at %s.\n\nConnect this phone to the same Wi-Fi or hotspot as the PC that runs the game server. Then type that PC's address into the Server field; the server's window shows it when it starts." % server_url

	var http := HTTPRequest.new()
	http.timeout = HTTP_TIMEOUT
	add_child(http)
	var headers := PackedStringArray(["Content-Type: application/json"])
	if not token.is_empty():
		headers.append("Authorization: Bearer " + token)
	var text := "" if body == null else JSON.stringify(body)
	if http.request(server_url + path, headers, method, text) != OK:
		http.queue_free()
		return unreachable

	var result: Array = await http.request_completed
	http.queue_free()
	if result[0] != HTTPRequest.RESULT_SUCCESS:
		return unreachable

	var code: int = result[1]
	var parsed: Variant = JSON.parse_string((result[3] as PackedByteArray).get_string_from_utf8())
	var data: Dictionary = parsed if parsed is Dictionary else {}
	if code >= 200 and code < 300:
		return {"ok": true, "error": "", "data": data}
	return {"ok": false, "data": data, "error": str(data.get("error", "The server answered with error %d" % code))}


# Sends a game action and reports a refusal through `action_failed`.
func _ask(event_name: String, payload: Dictionary = {}) -> Dictionary:
	_begin()
	var response: Dictionary = await socket.request(event_name, payload)
	_end()
	if not response.get("ok", false):
		var error := str(response.get("error", "The request failed"))
		if error == GAME_GONE_ERROR and not state.is_empty():
			_game_is_gone()
		else:
			action_failed.emit(error)
	return response


func _begin() -> void:
	_pending += 1
	if _pending == 1:
		busy_changed.emit()


func _end() -> void:
	_pending -= 1
	if _pending == 0:
		busy_changed.emit()


# Connected, or connected again after the line dropped or the server was restarted.
func _on_connected() -> void:
	connection_changed.emit()
	# The server puts us back at our table by itself. Ask all the same: if the table no longer
	# exists we must hear it now, not when the next move is refused.
	if status() in ["waiting", "playing", "round_over"]:
		resync()
	# A search ends when the connection drops; it goes on from where it was
	if searching():
		socket.request("findMatch", match_search)


# The server no longer has the table we are sitting at, so nothing can be played there any
# more. Leave it and say why, instead of refusing every move with "Game not found".
func _game_is_gone() -> void:
	if state.is_empty():
		return  # already left, e.g. two answers saying the same
	_forget_game()
	state_changed.emit()
	action_failed.emit("This game is no longer running on the game server, so it cannot be continued.\n\nYou are back on the home screen and can start a new game.")


func _on_connect_refused(_message: String) -> void:
	# The server no longer accepts the saved login, e.g. the token has expired
	logout()
	notice.emit("warning", "Your login has expired. Please log in again.")


func _on_event(event_name: String, payload: Variant) -> void:
	if not (payload is Dictionary):
		return
	var who := str(payload.get("username", "A player"))
	match event_name:
		"gameState":
			_apply_state(payload)
		"playerJoined":
			notice.emit("info", "%s joined the game" % who)
		"playerLeft":
			notice.emit("warning", "%s left the game" % who)
		"playerDisconnected":
			notice.emit("warning", "%s lost connection" % who)
		"playerReconnected":
			notice.emit("info", "%s is back" % who)
		"playerDropped":
			if payload.get("timedOut", false):
				var subject := "You were" if payload.get("userId") == player_id else "%s was" % who
				notice.emit("info", "%s dropped for inactivity" % subject)
			else:
				notice.emit("info", "%s dropped out of the round" % who)
		"wrongDeclaration":
			notice.emit("warning", "%s made a wrong declaration" % who)
		"gameError":
			notice.emit("error", str(payload.get("message", "Something went wrong")))
		"coins":
			coins = int(payload.get("coins", coins))
			coins_changed.emit()
		"friendsState":
			_apply_friends(payload)
		"gameInvite":
			invite_received.emit(payload)
		"matchStatus":
			if searching():
				match_status = payload
				var starts_in: Variant = payload.get("startsIn")
				match_starts_at = Time.get_ticks_msec() + int(starts_in) if starts_in != null else 0
				match_changed.emit()
		"matchFound":
			# The table's state follows at once and takes us to it
			_stop_search()
		"matchFailed":
			_stop_search()
			action_failed.emit(str(payload.get("message", "No table could be found")))


# The server sends the whole table after every change, with only our own hand in it.
# It also sends it when we (re)connect and are still seated in a game.
func _apply_state(new_state: Dictionary) -> void:
	# Seated at a table, whichever way we came to it: no more searching
	if searching() and new_state.get("status") in ["waiting", "playing", "round_over"]:
		_stop_search()
	var is_new_deal: bool = (
		state.is_empty()
		or state.get("gameId") != new_state.get("gameId")
		or state.get("round") != new_state.get("round")
		or groups.is_empty()
	)
	var turn_changed: bool = is_new_deal or state.get("currentPlayer") != new_state.get("currentPlayer")
	groups = _reconcile_groups(groups, new_state, is_new_deal)
	if not is_new_deal:
		_note_joker_seen(new_state)
	state = new_state

	var now := Time.get_ticks_msec()
	var turn_time: Variant = new_state.get("turnTimeLeft")
	var round_time: Variant = new_state.get("nextRoundIn")
	turn_ends_at = now + int(turn_time) if turn_time != null else 0
	next_round_at = now + int(round_time) if round_time != null else 0
	if turn_time == null:
		turn_total = 0
	elif turn_changed or int(turn_time) > turn_total:
		turn_total = int(turn_time)  # a turn starts with its full time on the clock

	# The server scores a losing hand by its arrangement, so it must always hold the one
	# shown on screen, including the automatic sort of a fresh deal.
	if status() == "playing" and groups != new_state.get("groups", []):
		_send_groups()

	state_changed.emit()


# Close Joker: tells the table when another player has earned the sight of the joker.
# `state` still holds the table as it was before this update.
func _note_joker_seen(new_state: Dictionary) -> void:
	if not new_state.get("closedJoker", false) or new_state.get("status") != "playing":
		return
	var had_seen := {}
	for player: Dictionary in players():
		had_seen[player.get("id")] = player.get("seenJoker", false)
	for player: Dictionary in new_state.get("players", []):
		var id: Variant = player.get("id")
		if id != player_id and player.get("seenJoker", false) and not had_seen.get(id, true):
			notice.emit("info", "%s made a pure sequence and has seen the joker" % player.get("username", "A player"))


# Keeps the player's arrangement across updates: cards that left the hand are removed,
# a newly drawn card sits on its own at the right.
func _reconcile_groups(previous: Array, new_state: Dictionary, is_new_deal: bool) -> Array:
	var held: Array = new_state.get("hand", [])
	if held.is_empty():
		return []

	var base := previous
	if is_new_deal:
		# After a reconnect the server still has the arrangement; a fresh deal is sorted by suit
		var saved: Array = new_state.get("groups", [])
		base = saved if not saved.is_empty() else Rummy.sort_into_groups(held)

	var in_hand := {}
	for held_card: Dictionary in held:
		in_hand[held_card.id] = true

	var result: Array = []
	var placed := {}
	for group: Array in base:
		var kept: Array = []
		for id: Variant in group:
			if in_hand.has(id) and not placed.has(id):
				placed[id] = true
				kept.append(id)
		if not kept.is_empty():
			result.append(kept)

	var added: Array = []
	for held_card: Dictionary in held:
		if not placed.has(held_card.id):
			added.append(held_card.id)
	if not added.is_empty():
		result.append(added)
	return result


func _send_groups() -> void:
	socket.send_event("arrangeHand", {"groups": groups})


func _stop_search() -> void:
	if not searching():
		return
	match_search = {}
	match_status = {}
	match_since = 0
	match_starts_at = 0
	match_changed.emit()


func _forget_game() -> void:
	state = {}
	groups = []
	turn_ends_at = 0
	next_round_at = 0
	turn_total = 0


# The server sends all four lists after every change: a request, an answer, a friend coming
# online or sitting down at a table.
func _apply_friends(lists: Dictionary) -> void:
	var was_offline := {}
	for friend: Dictionary in friends:
		was_offline[friend.get("id")] = friend.get("status") == "offline"
	var had_asked := {}
	for request: Dictionary in friend_requests:
		had_asked[request.get("id")] = true
	var first_lists := not _friends_known

	friends = lists.get("friends", [])
	friend_requests = lists.get("incoming", [])
	friend_asked = lists.get("outgoing", [])
	recent_players = lists.get("recent", [])
	_friends_known = true

	# News is announced, but not what was already so when we connected, and never over a game
	if not first_lists and status() not in ["playing", "round_over"]:
		for friend: Dictionary in friends:
			if friend.get("status") != "offline" and was_offline.get(friend.get("id"), false):
				notice.emit("info", "%s is online" % friend.get("username", "A friend"))
		for request: Dictionary in friend_requests:
			if not had_asked.has(request.get("id")):
				notice.emit("info", "%s wants to be your friend" % request.get("username", "A player"))
	friends_changed.emit()


func _forget_friends() -> void:
	friends = []
	friend_requests = []
	friend_asked = []
	recent_players = []
	profile = {}
	_friends_known = false
	friends_changed.emit()
