class_name GameClient
extends Node
## One player's session: the login, the game socket, and the latest table state from the server.
##
## The project runs one of these as the `Game` autoload. Screens read from it and call its
## actions without waiting for the answer: results come back through the signals below, so a
## screen that has been closed in the meantime is never left waiting.

signal auth_changed
signal auth_failed(message: String)
## The server has sent a 6-digit code by SMS: to sign up (`purpose` "register") or to set a new
## password ("password"). `phone` is the number as the server shows it; another code can be
## asked for after `resend_seconds`.
signal code_sent(purpose: String, phone: String, resend_seconds: int)
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
## A player's profile photo has arrived (or changed); avatar_texture() now has it.
signal avatar_loaded(user_id: String)
## The daily bonus wheel opened, closed, or got a new countdown (see `bonus`).
signal bonus_changed
## Our spin of the wheel was accepted: it stops on slot `index`, which pays `prize` coins.
signal bonus_spun(index: int, prize: int)
## Our spin was refused (the 24 hours are not over) or did not reach the server.
signal bonus_failed(message: String)
## A player at our table (ourselves included) wrote something or sent an emoji; it is also the
## last entry of chat_log now.
signal chat_received(message: Dictionary)
## chat_log was replaced as a whole: a new table, or caught up after the connection came back.
signal chat_changed
## The players we blocked in the chat changed (see chat_blocked).
signal chat_blocks_changed
## A player at our table (ourselves included) threw one of THROWABLES at another player's
## picture: {"id", "from", "to", "item"}, the two being user ids.
signal item_thrown(toss: Dictionary)

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
## Profile photos already fetched, kept between runs: "<user id>-<version>.jpg".
const AVATAR_CACHE := "user://avatars"
const AVATAR_FETCHES_AT_ONCE := 4
## When the wheel's countdown has run out but the server could not be asked, ask again after this.
const BONUS_RETRY_MSEC := 5000
## The emoji a player can send at the table, by the names the server knows them by. Each has
## its picture in res://assets/emoji/<name>.png.
const EMOJIS := ["laugh", "cool", "thumbs", "heart", "fire", "clap", "wow", "cry", "angry", "think", "pray", "party"]
## What can be thrown at another player's picture at the table, by the names the server knows
## them by (TableThrows has a picture and an animation for each). The server has the same list.
const THROWABLES := [
	"aruval", "knife", "ghost", "cake", "chocolate",
	"tomato", "egg", "bomb", "chappal", "coconut",
	"hammer", "boxing", "firecracker", "chili", "ice",
	"balloon", "rose", "crown", "chai", "money",
]
## The server cuts a message at this many characters and keeps this many per table.
const CHAT_MAX_LENGTH := 120
const CHAT_LOG_SIZE := 40
## What the server adds to a 401 answer when our login has ended; only that logs us out.
const LOGIN_ENDED_CODE := "session_ended"
const LOGIN_ENDED_MESSAGE := "Your login has ended. Please log in again."

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
## Our friends, as {"id", "username", "avatar", "status"}; status is "online", "lobby"
## (waiting at a table), "playing" or "offline". "avatar" is the profile photo's version, 0
## for none, here and wherever a player is listed (the table's players, the lists below).
var friends: Array = []
## Players who ask to be our friend, players we asked, and players we met at a table who are
## in none of the lists yet; each {"id", "username", "avatar"}.
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
## The daily bonus wheel as the server last described it: {"available", "nextSpinIn" (msec),
## "cooldown" (msec between spins), "prizes" (the coins on each slot, clockwise from the
## pointer), "lastPrize"}. Empty until fetched. One spin every 24 hours: the server keeps the
## time of the last one and draws the prize, so the app can only show what it is told.
var bonus: Dictionary = {}
## When the wheel opens again, as a Time.get_ticks_msec() value; 0 while it is open or unknown.
var bonus_ready_at := 0
## What has been said at our table, oldest first; empty when not at a table. Each entry:
## {"id", "userId", "username", "kind": "text" or "emoji", "text" or "emoji", "at"}.
var chat_log: Array = []
## The players we blocked in the chat, as {"id", "username"}: nothing they write or send at a
## table reaches us. The server keeps the list with our account.
var chat_blocked: Array = []
var socket: SocketIOClient
## True while a request is on its way to the server.
var busy: bool:
	get:
		return _pending > 0

var _pending := 0
var _friends_known := false  # false until the server has sent the lists once
# Profile photos: user id -> {"version": int, "texture": the photo or null, "failed": bool}.
# A photo being fetched has its version here already, so it is asked for once.
var _avatars: Dictionary = {}
var _avatar_queue: Array = []  # [user id, version] still to fetch
var _avatar_fetches := 0  # how many are on their way
var _bonus_fetching := false
var _bonus_spinning := false
var _bonus_retry_at := 0  # no new question about the wheel before this (ticks)


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


func _process(_delta: float) -> void:
	# The wheel's countdown has run out: the server says whether it really is open again
	var now := Time.get_ticks_msec()
	if bonus_ready_at > 0 and now >= bonus_ready_at and now >= _bonus_retry_at and not _bonus_fetching and is_logged_in():
		_bonus_retry_at = now + BONUS_RETRY_MSEC
		fetch_bonus()


func _notification(what: int) -> void:
	# A phone's tick clock stands still while it sleeps, so the countdown is behind: ask again
	if what == NOTIFICATION_APPLICATION_RESUMED and is_logged_in():
		fetch_bonus()


# ---------- account ----------

func is_logged_in() -> bool:
	return not token.is_empty()


func is_online() -> bool:
	return socket.is_online


## Opens the game connection again with the same login, e.g. after the server address changed.
func reconnect() -> void:
	if is_logged_in():
		socket.open(server_url, {"token": token})


func set_server_url(url: String) -> void:
	var clean := Config.clean_server_url(url)
	if clean == server_url:
		return
	server_url = clean
	if remember_login:
		Config.set_server_url(clean)


# ---------- phone codes ----------

## Signing up, first step: the server checks the form and sends a code by SMS to `phone`
## (code_sent follows; then register() with that code). While the server does not verify
## numbers it makes the account at once instead. A refusal comes through auth_failed.
## `phone` is the whole number with its country code, as AccountRules.full_number makes it.
func start_registration(username: String, phone: String, password: String) -> Dictionary:
	_begin()
	var response: Dictionary = await _http(HTTPClient.METHOD_POST, "/api/auth/register/start", _sign_up_body(username, phone, password))
	_end()
	if not response.ok:
		auth_failed.emit(response.error)
	elif not response.data.get("codeSent", false):
		return await register(username, phone, password)
	else:
		code_sent.emit("register", str(response.data.get("phone", phone)), int(response.data.get("resendSeconds", 30)))
	return response


## Signing up, second step: makes the account with the code from the SMS. Without a code where
## the server does not verify numbers (the tests' default server).
func register(username: String, phone: String, password: String, code: String = "") -> Dictionary:
	var body := _sign_up_body(username, phone, password)
	if not code.is_empty():
		body["code"] = code.replace(" ", "")
	return await _authenticate("/api/auth/register", body)


## A forgotten password, first step: a code goes by SMS to the account's number (code_sent),
## or auth_failed says why it cannot.
func start_password_reset(phone: String) -> Dictionary:
	_begin()
	var response: Dictionary = await _http(HTTPClient.METHOD_POST, "/api/auth/password/start", {"phone": phone.strip_edges()})
	_end()
	if response.ok:
		code_sent.emit("password", str(response.data.get("phone", phone)), int(response.data.get("resendSeconds", 30)))
	else:
		auth_failed.emit(response.error)
	return response


## A forgotten password, second step: the code from the SMS and the new password. The player
## is logged in with it, and every other login of the account has ended.
func reset_password(phone: String, code: String, password: String) -> Dictionary:
	var body := {"phone": phone.strip_edges(), "code": code.replace(" ", ""), "password": password}
	var response: Dictionary = await _authenticate("/api/auth/password/reset", body)
	if response.ok:
		notice.emit("info", "Your password has been changed")
	return response


func _sign_up_body(username: String, phone: String, password: String) -> Dictionary:
	return {"username": username.strip_edges(), "phone": phone.strip_edges(), "password": password}


## `identifier` is an email, phone number or username.
func login(identifier: String, password: String) -> Dictionary:
	var body := {"identifier": identifier.strip_edges(), "password": password}
	return await _authenticate("/api/auth/login", body)


## Logs out. The login ends on the server too, so its token is not accepted anywhere any more.
## A login does not run out: only this, or the server ending it, logs the player out.
func logout() -> void:
	if not token.is_empty():
		# Not waited for: the token is forgotten here at once, whether the server is reached or not
		_http(HTTPClient.METHOD_POST, "/api/auth/logout")
	_forget_login()


# Forgets the login and everything that came with it, on this device only.
func _forget_login() -> void:
	_stop_search()
	socket.close()
	token = ""
	user = {}
	player_id = ""
	coins = 0
	_forget_game()
	_forget_friends()
	_forget_bonus()
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
		_forget_login()  # the account's logins went with it
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
	await _ad_before_table()
	var request := table_request(game_type, max_players, stake, point_value)
	request["private"] = is_private
	return await _ask("createGame", request)


## "Play Now": asks the server to find players who want the same table, the ones in our own
## region (time zone) first, with no room code. The search runs until the server seats us,
## which brings the table's state, or until cancel_match(). Follow it through match_changed.
func find_match(game_type: String, max_players: int, stake: int, point_value: int = -1) -> Dictionary:
	await _ad_before_table()
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
	await _ad_before_table()
	return await _ask("joinGameByRoomCode", {"roomCode": room_code.strip_edges().to_upper()})


# Sitting down at a table is one of the moments an ad may show (see autoload/ads.gd): before the
# request leaves, so no turn clock runs while it is on screen. Only for this device's own
# player, not for the extra players the tests create.
func _ad_before_table() -> void:
	if self == Game:
		await Ads.before_table()


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


func rejoin_game(score: int) -> Dictionary:
	return await _ask("rejoinGame", {"score": score})


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
		# The photo may have been changed on another phone since this login was saved
		if int(profile.get("avatar", 0)) != my_avatar():
			_keep_own_avatar(int(profile.get("avatar", 0)))
		profile_changed.emit()
	return response


## Changes the username. (The mobile number stays: the SMS code proved it when signing up.)
func update_profile(username: String) -> Dictionary:
	_begin()
	var body := {"username": username.strip_edges()}
	var response: Dictionary = await _http(HTTPClient.METHOD_PATCH, "/api/user/profile", body)
	_end()
	if not response.ok:
		action_failed.emit(response.error)
		return response

	var saved: Dictionary = response.data.get("user", {})
	user["username"] = saved.get("username", user.get("username"))
	profile["username"] = user["username"]
	if remember_login:
		Config.save_login(token, user)
	# The server reads the name once, when the socket connects; connecting again makes tables,
	# invitations and friends lists show the new one
	socket.open(server_url, {"token": token})
	auth_changed.emit()
	profile_changed.emit()
	notice.emit("info", "Profile saved")
	return response


# ---------- profile photos ----------

## Our own photo's version; 0 when we have none.
func my_avatar() -> int:
	return int(user.get("avatar", 0))


## Saves our profile photo: `jpeg` is the small square picture AvatarEditor made.
func upload_avatar(jpeg: PackedByteArray) -> Dictionary:
	_begin()
	var response: Dictionary = await _http(HTTPClient.METHOD_PUT, "/api/user/avatar", jpeg, "image/jpeg")
	_end()
	if response.ok:
		# No need to fetch what we just sent
		var version := int(response.data.get("avatar", 0))
		_avatars[player_id] = {"version": version, "texture": null, "failed": false}
		if _store_avatar(player_id, version, jpeg):
			_save_avatar_file(player_id, version, jpeg)
		_keep_own_avatar(version)
		notice.emit("info", "Profile photo saved")
	else:
		action_failed.emit(response.error)
	return response


## Goes back to the letter in a coloured circle.
func remove_avatar() -> Dictionary:
	_begin()
	var response: Dictionary = await _http(HTTPClient.METHOD_DELETE, "/api/user/avatar")
	_end()
	if response.ok:
		_keep_own_avatar(0)
		notice.emit("info", "Profile photo removed")
	else:
		action_failed.emit(response.error)
	return response


## A player's photo at this version, or null: when they have none (version 0), or while it is
## still on its way, in which case avatar_loaded follows. A photo that was replaced stays
## until the new one is here.
func avatar_texture(user_id: String, version: int) -> Texture2D:
	if version <= 0 or user_id.is_empty():
		return null
	var known: Dictionary = _avatars.get(user_id, {})
	if int(known.get("version", 0)) == version:
		return known.get("texture")
	_avatars[user_id] = {"version": version, "texture": known.get("texture"), "failed": false}
	var cached := FileAccess.get_file_as_bytes(_avatar_path(user_id, version))
	if not cached.is_empty() and _store_avatar(user_id, version, cached):
		return _avatars[user_id].texture
	_avatar_queue.append([user_id, version])
	_next_avatar_fetch()
	return known.get("texture")


func _keep_own_avatar(version: int) -> void:
	user["avatar"] = version
	profile["avatar"] = version
	if remember_login:
		Config.save_login(token, user)
	profile_changed.emit()
	avatar_loaded.emit(player_id)


func _avatar_path(user_id: String, version: int) -> String:
	return "%s/%s-%d.jpg" % [AVATAR_CACHE, user_id.validate_filename(), version]


func _next_avatar_fetch() -> void:
	while _avatar_fetches < AVATAR_FETCHES_AT_ONCE and not _avatar_queue.is_empty():
		var wanted: Array = _avatar_queue.pop_front()
		if int(_avatars.get(wanted[0], {}).get("version", 0)) == wanted[1]:
			_fetch_avatar(wanted[0], wanted[1])


func _fetch_avatar(user_id: String, version: int) -> void:
	_avatar_fetches += 1
	var http := HTTPRequest.new()
	http.timeout = HTTP_TIMEOUT
	add_child(http)
	var headers := PackedStringArray(["Authorization: Bearer " + token])
	var url := "%s/api/avatars/%s?v=%d" % [server_url, user_id.uri_encode(), version]
	var result: Array = []
	if http.request(url, headers) == OK:
		result = await http.request_completed
	http.queue_free()
	_avatar_fetches -= 1
	var arrived: bool = not result.is_empty() and result[0] == HTTPRequest.RESULT_SUCCESS and result[1] == 200
	if arrived and _store_avatar(user_id, version, result[3]):
		_save_avatar_file(user_id, version, result[3])
	elif int(_avatars.get(user_id, {}).get("version", 0)) == version:
		_avatars[user_id].failed = true  # the letter stays; asked again only for a new version
	_next_avatar_fetch()


# Keeps a photo for the next run, in place of the player's earlier one.
func _save_avatar_file(user_id: String, version: int, bytes: PackedByteArray) -> void:
	DirAccess.make_dir_recursive_absolute(AVATAR_CACHE)
	var prefix := user_id.validate_filename() + "-"
	for old: String in DirAccess.get_files_at(AVATAR_CACHE):
		if old.begins_with(prefix):
			DirAccess.remove_absolute("%s/%s" % [AVATAR_CACHE, old])
	var file := FileAccess.open(_avatar_path(user_id, version), FileAccess.WRITE)
	if file != null:
		file.store_buffer(bytes)


# Makes a texture of a photo's bytes and keeps it, if it is still the version wanted.
func _store_avatar(user_id: String, version: int, bytes: PackedByteArray) -> bool:
	var image := Image.new()
	var loaded := image.load_jpg_from_buffer(bytes) if bytes.size() > 2 and bytes[0] == 0xFF and bytes[1] == 0xD8 else image.load_png_from_buffer(bytes)
	if loaded != OK or image.is_empty():
		return false
	if int(_avatars.get(user_id, {}).get("version", version)) != version:
		return false  # a newer photo was asked for meanwhile
	_avatars[user_id] = {"version": version, "texture": ImageTexture.create_from_image(image), "failed": false}
	avatar_loaded.emit(user_id)
	return true


# ---------- the daily bonus wheel ----------

## True when the server last said the wheel may be spun.
func bonus_available() -> bool:
	return not bonus.is_empty() and bool(bonus.get("available", false))


## The coins on each slot of the wheel, clockwise from the pointer; empty until fetched.
func bonus_prizes() -> Array:
	return bonus.get("prizes", [])


## Milliseconds until the wheel opens again; 0 while it is open (or not known yet).
func bonus_wait() -> int:
	return maxi(0, bonus_ready_at - Time.get_ticks_msec()) if bonus_ready_at > 0 else 0


## True while a spin is on its way to the server.
func bonus_spinning() -> bool:
	return _bonus_spinning


## Asks the server where the wheel stands. The answer comes as bonus_changed.
func fetch_bonus() -> void:
	if _bonus_fetching or not is_logged_in():
		return
	_bonus_fetching = true
	var asked_with := token
	var response: Dictionary = await _http(HTTPClient.METHOD_GET, "/api/bonus/daily")
	_bonus_fetching = false
	if response.ok and token == asked_with:  # not for an account logged out meanwhile
		_apply_bonus(response.data)


## Spins the wheel. The server checks the 24 hours and draws the prize; the answer comes as
## bonus_spun (with the new balance already in `coins`) or bonus_failed.
func spin_bonus() -> void:
	if _bonus_spinning or not is_logged_in():
		return
	_bonus_spinning = true
	var asked_with := token
	var response: Dictionary = await _http(HTTPClient.METHOD_POST, "/api/bonus/daily/spin")
	_bonus_spinning = false
	if token != asked_with:
		return
	var data: Dictionary = response.data
	# A refusal says how long is left; a win starts the next 24 hours
	if data.has("available"):
		_apply_bonus(data)
	if response.ok:
		coins = int(data.get("coins", coins))
		coins_changed.emit()
		bonus_spun.emit(int(data.get("index", 0)), int(data.get("prize", 0)))
	else:
		bonus_failed.emit(response.error)


## "23:59:59" for a wait in milliseconds, rounded up to the second.
static func countdown_text(msec: int) -> String:
	var left := ceili(maxi(0, msec) / 1000.0)
	return "%02d:%02d:%02d" % [floori(left / 3600.0), floori(left / 60.0) % 60, left % 60]


# What the server says about the wheel, from an answer or from the "dailyBonus" event; only
# the parts it sends change.
func _apply_bonus(data: Dictionary) -> void:
	for key: String in ["available", "nextSpinIn", "cooldown", "prizes", "lastPrize"]:
		if data.has(key):
			bonus[key] = data[key]
	var wait := int(bonus.get("nextSpinIn", 0))
	bonus_ready_at = 0 if bonus_available() or wait <= 0 else Time.get_ticks_msec() + wait
	_bonus_retry_at = 0
	bonus_changed.emit()


func _forget_bonus() -> void:
	bonus = {}
	bonus_ready_at = 0
	_bonus_retry_at = 0
	bonus_changed.emit()


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


# ---------- chat at the table ----------

## Says something to the players at our table. What comes back arrives through chat_received,
## for us as for everyone else; a refusal (too many messages at once) shows as a notice.
func send_chat(text: String) -> void:
	var clean := text.strip_edges()
	if not clean.is_empty():
		_say({"text": clean.left(CHAT_MAX_LENGTH)})


## Sends one of EMOJIS to the players at our table.
func send_emoji(emoji_name: String) -> void:
	if emoji_name in EMOJIS:
		_say({"emoji": emoji_name})


# Chat goes out on its own, not through _ask: it never makes the table busy, so it cannot hold
# up a move, and a refusal is a passing notice rather than a message box over the cards.
func _say(payload: Dictionary) -> void:
	var response: Dictionary = await socket.request("sendChat", payload)
	if not response.get("ok", false):
		notice.emit("warning", str(response.get("error", "The message was not sent")))


# Catches up with what was said at our table: when we sit down, and after the connection was
# lost for a while.
func _fetch_chat() -> void:
	var game_id: Variant = state.get("gameId")
	var response: Dictionary = await socket.request("chatHistory")
	if response.get("ok", false) and game_id != null and state.get("gameId") == game_id and response.get("gameId") == game_id:
		chat_log = response.get("messages", [])
		chat_changed.emit()


func _add_chat(message: Dictionary) -> void:
	if state.is_empty() or message.get("gameId") != state.get("gameId"):
		return  # said at a table we have left
	if is_chat_blocked(str(message.get("userId", ""))):
		return  # sent just before we blocked them
	chat_log.append(message)
	if chat_log.size() > CHAT_LOG_SIZE:
		chat_log = chat_log.slice(chat_log.size() - CHAT_LOG_SIZE)
	chat_received.emit(message)


## Whether we blocked this player in the chat.
func is_chat_blocked(user_id: String) -> bool:
	return chat_blocked.any(func(entry: Dictionary) -> bool: return str(entry.get("id", "")) == user_id)


## Blocks a player in the chat, or unblocks them: what they write or send at a table stops
## reaching us, at every table, until we unblock them. The list follows through
## chat_blocks_changed; the outcome is told in a notice.
func block_chat_player(user_id: String, username: String, blocked: bool = true) -> void:
	var response: Dictionary = await socket.request("blockPlayer", {"userId": user_id, "blocked": blocked})
	if not response.get("ok", false):
		notice.emit("warning", str(response.get("error", "That did not work. Please try again.")))
		return
	_apply_chat_blocks(response.get("blocked", []))
	if blocked:
		notice.emit("info", "You will not see messages from %s any more" % username)
	else:
		notice.emit("info", "%s is unblocked" % username)


## Reports a message from another player at our table to the game's team. Its sender is
## blocked for us at the same time.
func report_chat(message: Dictionary) -> void:
	var response: Dictionary = await socket.request("reportChat", {"messageId": message.get("id")})
	if not response.get("ok", false):
		notice.emit("warning", str(response.get("error", "The report was not sent. Please try again.")))
		return
	_apply_chat_blocks(response.get("blocked", []))
	notice.emit("info", "Thank you. The message is reported and %s is blocked" % str(message.get("username", "the player")))


func _fetch_chat_blocks() -> void:
	var response: Dictionary = await socket.request("chatBlocks")
	if response.get("ok", false):
		_apply_chat_blocks(response.get("blocked", []))


func _apply_chat_blocks(list: Array) -> void:
	chat_blocked = list
	chat_blocks_changed.emit()


# ---------- things thrown at another player ----------

## Throws one of THROWABLES at another player at our table. Everyone there sees it fly, us
## included, through item_thrown. Like the chat it never makes the table busy, and a refusal
## (too many at once) is a passing notice.
func throw_item(to_id: String, item: String) -> void:
	if not item in THROWABLES or to_id.is_empty() or to_id == player_id or state.is_empty():
		return
	var response: Dictionary = await socket.request("throwItem", {"to": to_id, "item": item})
	if not response.get("ok", false):
		notice.emit("warning", str(response.get("error", "That did not reach the table")))


func _on_item_thrown(toss: Dictionary) -> void:
	if state.is_empty() or toss.get("gameId") != state.get("gameId"):
		return  # thrown at a table we have left
	toss["from"] = str(toss.get("from", ""))
	toss["to"] = str(toss.get("to", ""))
	item_thrown.emit(toss)


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


## Returns {"ok": bool, "error": String, "data": Dictionary}. `body` is sent as JSON, or as it
## is when it is a PackedByteArray (a photo), with `content_type`.
func _http(method: HTTPClient.Method, path: String, body: Variant = null, content_type := "application/json") -> Dictionary:
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
	var headers := PackedStringArray(["Content-Type: " + content_type])
	var asked_with := token
	if not token.is_empty():
		headers.append("Authorization: Bearer " + token)
	var sent: int
	if body is PackedByteArray:
		sent = http.request_raw(server_url + path, headers, method, body)
	else:
		sent = http.request(server_url + path, headers, method, "" if body == null else JSON.stringify(body))
	if sent != OK:
		http.queue_free()
		return unreachable

	var result: Array = await http.request_completed
	http.queue_free()
	if result[0] != HTTPRequest.RESULT_SUCCESS:
		return unreachable

	var code: int = result[1]
	# Not JSON.parse_string, which prints an engine error for an answer that is not JSON, such
	# as the HTML page of a proxy in front of a server that is starting up
	var json := JSON.new()
	var parsed: Variant = json.data if json.parse((result[3] as PackedByteArray).get_string_from_utf8()) == OK else null
	var data: Dictionary = parsed if parsed is Dictionary else {}
	if code >= 200 and code < 300:
		return {"ok": true, "error": "", "data": data}
	var error := str(data.get("error", "The server answered with error %d" % code))
	if code == 401 and data.get("code") == LOGIN_ENDED_CODE and not asked_with.is_empty() and asked_with == token:
		_login_ended(error)
	return {"ok": false, "data": data, "error": error}


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
	# Where the daily bonus stands: it may have been spun on another phone meanwhile
	fetch_bonus()
	_fetch_chat_blocks()  # whom we blocked in the chat, perhaps on another phone
	# The server puts us back at our table by itself. Ask all the same: if the table no longer
	# exists we must hear it now, not when the next move is refused.
	if status() in ["waiting", "playing", "round_over"]:
		resync()
		_fetch_chat()  # and hear what was said while we were away
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
	# A refusal that only meant "not just now" never gets here: the socket keeps trying
	_login_ended(LOGIN_ENDED_MESSAGE)


# The server has ended our login: for the account's safety, or because the account is gone
# (or it is a 24-hour token from an older version that has run out). A slow or unreachable
# server never ends up here.
func _login_ended(message: String) -> void:
	if token.is_empty():
		return  # already logged out, e.g. the socket and a request saying the same
	_forget_login()
	notice.emit("warning", message)


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
		"dailyBonus":
			_apply_bonus(payload)
		"friendsState":
			_apply_friends(payload)
		"gameInvite":
			invite_received.emit(payload)
		"chat":
			_add_chat(payload)
		"itemThrown":
			_on_item_thrown(payload)
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
	var new_table: bool = state.get("gameId") != new_state.get("gameId")
	groups = _reconcile_groups(groups, new_state, is_new_deal)
	if not is_new_deal:
		_note_joker_seen(new_state)
	state = new_state
	if new_table:
		# Each table has its own chat, and what was said there before we sat down comes along
		chat_log = []
		chat_changed.emit()
		_fetch_chat()

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
	chat_log = []
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
