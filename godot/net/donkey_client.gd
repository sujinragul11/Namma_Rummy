class_name DonkeyClient
extends Node
## Donkey Master, the second game, as one player sees it. Every GameClient has one as its
## `donkey` (the app's is `Game.donkey`). It shares that client's login, game connection and
## coins: a Donkey Master table is paid for and pays out through the same balance as rummy, so
## Game.coins and Game.coins_changed always show the one wallet. Its table state is kept apart
## from the rummy one: Game.status() stays "" during a Donkey Master game.
##
## Like GameClient, the screens call the actions below without waiting for the answer. What
## follows comes back through the signals; a refusal comes through Game.action_failed (shown
## by Ui as an alert) and news about the other players through Game.notice.
##
## The game (the server plays it: backend/src/donkey/DonkeyEngine.js). One pack of 52 cards,
## no jokers, aces high, dealt out completely among 2 to 8 players. Whoever holds the ace of
## spades leads it to the first trick. Then each player in turn, clockwise, plays one card and
## must follow the suit led when they can. A player who cannot follow plays any other card: a
## cut. The trick stops there, and whoever played the highest card of the suit led picks up
## every card of the trick and leads the next one. When everyone followed suit, the cards go
## out of the game and the highest card leads next. A player whose hand is empty is out and
## safe; the first one out is the Master. The last player left holding cards is the Donkey.
## (Should the last players all run out in the same trick, the one who played its highest
## card, who would have had to lead next, is the Donkey.)
##
## Coins. Every player pays the table's entry (`stake`, one of STAKES; 0 is a free table) on
## sitting down, and gets it back on leaving before the cards are dealt. At the end the Donkey,
## and anyone who left while still holding cards, lose their entry; it all goes to the Master.
## Everyone else gets their own entry back. (If nobody got out before the others left, the
## players who stayed share it.) The server sends the new balance at each step.

## The table state changed, or went away (`state` is then empty): after every move, a player
## arriving or leaving, the end of the game.
signal changed
## "Play Online": a search for players began, moved on (see search_status) or ended.
signal search_changed
## A friend calls us to their private table: {"userId", "username", "roomCode", "maxPlayers",
## "stake", "again"}; "again" when they played with us at the table that just ended. Join with
## join_room(invite.roomCode).
signal invite_received(invite: Dictionary)

## What a table can cost to sit at, in coins; 0 is a free table. The server has the same list.
const STAKES := [0, 500, 1000, 2000, 5000, 10000, 25000, 50000]
const MIN_PLAYERS := 2
const MAX_PLAYERS := 8
## The table sizes "Play Online" offers. A search for a bigger table starts with fewer players
## when no more turn up for a while (like rummy's Play Now), so it never waits for all 8.
const ONLINE_SIZES := [2, 4, 6, 8]
## What the server answers when it no longer has our table.
const ROOM_GONE_ERROR := "Donkey table not found"
## The suits in the order the hand is sorted, alternating colours.
const SUIT_ORDER := ["♠", "♥", "♣", "♦"]
const RANKS := ["2", "3", "4", "5", "6", "7", "8", "9", "10", "J", "Q", "K", "A"]

## Our table as the server last sent it; empty when we are not at a Donkey Master table.
## {
##   "roomId": String, "roomCode": String (6 letters; share it at a private table),
##   "private": bool, "hostId": String (who may start a private table),
##   "maxPlayers": int, "stake": int (each player's entry), "pot": int (all entries paid),
##   "status": "waiting" | "playing" | "finished",
##   "players": [ {   # in seat order, clockwise; seat 0 opened the table
##       "id": String, "username": String, "avatar": int (photo version, 0 = none),
##       "seat": int, "cards": int (how many they hold), "connected": bool,
##       "left": bool (got up from the table), "away": bool (missed turns: played for them),
##       "out": bool (hand empty: safe), "place": int (1 = the Master; 0 = not placed yet),
##       "donkey": bool } ],
##   "hand": [ {"id": "A♠", "suit": "♠", "value": "A"} ],  # ours only, sorted (SUIT_ORDER, low to high)
##   "turn": String,  # the player to play; "" when nobody is (waiting, between tricks, over)
##   "turnTimeLeft": int msec or null, "turnSeconds": int (a whole turn),
##   "trickNo": int (from 1), "leader": String (who led this trick),
##   "leadSuit": String ("" while the trick is empty),
##   "trick": [ {"playerId": String, "card": {...}} ],  # on the table now, in the order played
##   "trickEnd": {} or {"outcome": "discard" | "pickup", "by": String, "cutBy": String,
##       "highest": String},  # set while a finished trick still lies on the table, for a
##       # moment before it goes: "discard" (all followed: the cards leave the game, `by` leads
##       # next) or "pickup" (`cutBy` cut; `by` played the highest card of the suit led and
##       # takes the trick). `highest` played the trick's highest card of the suit led.
##   "lastTrick": {} or the same as trickEnd plus "no" (its trickNo) and "plays" (its cards),
##       # once that trick has gone: to animate it when the moment above was missed
##   "mustLead": String,  # a card id we have to lead ("A♠" on the first trick), else ""
##   "playable": [card ids],  # what we may play now; empty when it is not our turn
##   "discarded": int,  # cards gone out of the game
##   "masterId": String, "donkeyId": String,  # "" until known
##   "results": [] while playing; when finished, by place: [ {"id", "username", "place",
##       "donkey": bool, "left": bool, "coins": int (what they won, or lost if negative)} ],
##   "endedBy": "" | "play" | "leave",  # the last card was played, or the others got up
##   # Request Card: between tricks a player may ask a player next to them for their cards
##   # (request_card). The asked player accepts (all their cards go to the one who asked, and
##   # they are out and safe) or rejects, within requestSeconds; otherwise it expires. Who
##   # asked waits requestGapSeconds before asking again. The server checks all of it.
##   "requests": [ {"id": String, "from": String, "to": String,
##       "status": "pending" | "accepted" | "rejected" | "expired" | "cancelled",
##       "expiresIn": int msec (pending only), "moved": int (cards that went, accepted only)} ],
##       # every request at the table still on show, for everyone to see
##   "neighbours": [player ids],  # whom we may ask: the nearest players in play on either side
##   "canRequest": bool,  # between tricks, and we are in play with cards
##   "requestWait": int msec,  # until we may ask again; 0 when we may now
##   "requestSeconds": int, "requestGapSeconds": int
## }
var state: Dictionary = {}
## When we may ask for cards again (ticks); 0 when we may now.
var request_ready_at := 0
## The turn's deadline as a Time.get_ticks_msec() value, 0 when no clock runs, and how long
## the whole turn is (msec), so a clock can be drawn as a shrinking ring.
var turn_ends_at := 0
var turn_total := 0
## "Play Online": the table we are looking for players for ({"maxPlayers", "stake",
## "timezone"}), empty when not searching. search_status is where the search stands, as for
## rummy's Play Now: {"found", "needed", "inQueue", "scope" ("region", "nearby" or
## "everywhere"), "region", "startsIn"}. search_starts_at: when a table found with free seats
## starts anyway (ticks), 0 while there is none.
var search: Dictionary = {}
var search_status: Dictionary = {}
var search_since := 0
var search_starts_at := 0

var _client: GameClient
# The table last sat at, for play_again(): {"private", "maxPlayers", "stake", "roomId"}
var _last_table: Dictionary = {}
var _request_ends: Dictionary = {}  # request id -> when a pending request runs out (ticks)


func _init(client: GameClient) -> void:
	name = "Donkey"
	_client = client


func _ready() -> void:
	_client.socket.event_received.connect(_on_event)
	_client.socket.connected.connect(_on_connected)
	_client.auth_changed.connect(_on_auth_changed)


func _notification(what: int) -> void:
	# The clocks kept running while the app was in the background
	if what == NOTIFICATION_APPLICATION_RESUMED:
		resync()


# ---------- reading the table ----------

func in_room() -> bool:
	return not state.is_empty()


## "waiting", "playing", "finished", or "" when not at a table.
func status() -> String:
	return str(state.get("status", ""))


func players() -> Array:
	return state.get("players", [])


func hand() -> Array:
	return state.get("hand", [])


## Our own entry in the player list, or an empty Dictionary.
func me() -> Dictionary:
	return player(_client.player_id)


func player(id: Variant) -> Dictionary:
	for entry: Dictionary in players():
		if str(entry.get("id")) == str(id):
			return entry
	return {}


func player_name(id: Variant) -> String:
	return str(player(id).get("username", ""))


func is_host() -> bool:
	return str(state.get("hostId", "")) == _client.player_id


func is_my_turn() -> bool:
	return status() == "playing" and str(state.get("turn", "")) == _client.player_id


## The ids of the cards we may play now; empty when it is not our turn.
func playable() -> Array:
	return state.get("playable", []) if is_my_turn() else []


func seconds_left() -> int:
	return _client.seconds_until(turn_ends_at)


## How much of the current turn is left, from 1 (just started) down to 0 (time is up).
func turn_fraction() -> float:
	if turn_ends_at == 0 or turn_total <= 0:
		return 0.0
	return clampf(float(turn_ends_at - Time.get_ticks_msec()) / turn_total, 0.0, 1.0)


func searching() -> bool:
	return not search.is_empty()


# ---------- Request Card ----------

func requests() -> Array:
	return state.get("requests", [])


## Whom we may ask: the nearest players still in play on either side of us.
func neighbours() -> Array:
	return state.get("neighbours", [])


## The newest request on show that `player_id` asked or was asked; empty when there is none.
func request_about(player_id: String) -> Dictionary:
	var found: Dictionary = {}
	for request: Dictionary in requests():
		if str(request.get("from")) == player_id or str(request.get("to")) == player_id:
			found = request
	return found


## The oldest request to us still waiting for our answer; empty when there is none.
func request_to_me() -> Dictionary:
	for request: Dictionary in requests():
		if str(request.get("to")) == _client.player_id and request.get("status") == "pending":
			return request
	return {}


## Our own request still waiting for an answer; empty when there is none.
func my_pending_request() -> Dictionary:
	for request: Dictionary in requests():
		if str(request.get("from")) == _client.player_id and request.get("status") == "pending":
			return request
	return {}


## Milliseconds until we may ask again; 0 when we may now.
func request_wait() -> int:
	return maxi(0, request_ready_at - Time.get_ticks_msec()) if request_ready_at > 0 else 0


## True when we may ask `player_id` for their cards right now.
func may_request(player_id: String) -> bool:
	return status() == "playing" and state.get("canRequest", false) and neighbours().has(player_id) \
		and request_wait() == 0 and my_pending_request().is_empty()


## How much of a pending request's time to answer is left, from 1 down to 0.
func request_time_left(request: Dictionary) -> float:
	var ends: int = _request_ends.get(str(request.get("id")), 0)
	var total := int(state.get("requestSeconds", 10)) * 1000.0
	if ends == 0 or total <= 0.0:
		return 0.0
	return clampf((ends - Time.get_ticks_msec()) / total, 0.0, 1.0)


## Asks `player_id` (a neighbour) for their cards.
func request_card(player_id: String) -> Dictionary:
	return await _ask("donkeyRequestCard", {"to": player_id})


## Our answer to a request: only an accept moves our cards (all of them) to whoever asked.
func answer_request(request_id: String, accept: bool) -> Dictionary:
	return await _ask("donkeyAnswerRequest", {"requestId": request_id, "accept": accept})


## The table we last sat at was private (for play_again: a new private table, or a new search).
func last_table_private() -> bool:
	return _last_table.get("private", false)


# ---------- actions ----------

## "Play Online": the server seats us with other players who want the same table (seats and
## entry), the ones in our region first. Follow it through search_changed; once seated, the
## table's state arrives (changed). `max_players` is one of ONLINE_SIZES.
func find_match(max_players: int, stake: int) -> Dictionary:
	await _ad_after_game()
	search = {"maxPlayers": max_players, "stake": stake, "timezone": GameClient.time_zone_minutes()}
	search_status = {}
	search_since = Time.get_ticks_msec()
	search_starts_at = 0
	search_changed.emit()
	var response := await _ask("donkeyFind", search)
	if not response.get("ok", false):
		_stop_search()
	elif searching() and search_status.is_empty():
		search_status = {"found": 1, "needed": max_players, "scope": "region", "region": str(response.get("region", ""))}
		search_changed.emit()
	return response


func cancel_match() -> void:
	if not searching():
		return
	_stop_search()
	if _client.is_online():
		await _client.socket.request("donkeyCancelFind")


## "Play with Friends": opens a private table for 2 to 8 players, which only someone with its
## room code (state.roomCode) can join; we are its host and pay its entry at once.
func create_room(max_players: int, stake: int) -> Dictionary:
	await _ad_after_game()
	return await _ask("donkeyCreate", {"maxPlayers": max_players, "stake": stake})


func join_room(room_code: String) -> Dictionary:
	await _ad_after_game()
	return await _ask("donkeyJoin", {"roomCode": room_code.strip_edges().to_upper()})


## The host deals once at least two players sit at the private table. A full table deals by
## itself.
func start() -> Dictionary:
	return await _ask("donkeyStart")


func play(card_id: String) -> Dictionary:
	return await _ask("donkeyPlay", {"cardId": card_id})


## Asks a friend (or a player from the table that just ended) to join our private table.
func invite(friend_id: String) -> Dictionary:
	var response := await _ask("donkeyInvite", {"userId": friend_id})
	if response.get("ok", false):
		_client.notice.emit("info", "Invitation sent to %s" % str(response.get("username", "your friend")))
	return response


## Gets up from the table. Before the deal the entry comes back; during the game a player who
## still holds cards loses it; once out, or after the end, leaving costs nothing.
func leave() -> void:
	await _ad_after_game()
	# Whatever the server answers (we may be offline), this player is done with the table
	if in_room():
		await _client.socket.request("donkeyLeave")
	_forget_table()
	changed.emit()


## After a game: the same again. A private table opens a new one with the same seats and
## entry and invites the players who were at it; an online table searches again.
func play_again() -> Dictionary:
	var last := _last_table.duplicate()
	if in_room():
		await leave()
	if last.is_empty():
		return {"ok": false}
	if last.get("private", false):
		return await _ask("donkeyCreate", {
			"maxPlayers": int(last.get("maxPlayers", 2)), "stake": int(last.get("stake", 0)), "again": str(last.get("roomId", "")),
		})
	return await find_match(_online_size(int(last.get("maxPlayers", 2))), int(last.get("stake", 0)))


## Asks the server for the table again, e.g. when the app comes back from the background.
func resync() -> void:
	if not _client.is_online() or not in_room():
		return
	var response: Dictionary = await _client.socket.request("donkeyState")
	var fresh: Variant = response.get("state")
	if response.get("ok", false) and fresh is Dictionary:
		_apply_state(fresh)
	elif response.get("error") == ROOM_GONE_ERROR and status() != "finished":
		_table_is_gone()


# ---------- the connection ----------

# Leaving a finished game is the one moment an ad may show (autoload/ads.gd), as at a rummy
# table: before the request leaves, so the ad covers only the result. Never before sitting
# down or during a game. Only for this device's own player, not for the extra players the
# tests create.
func _ad_after_game() -> void:
	if _client == Game and in_room() and status() == "finished":
		await Ads.after_game()


func _ask(event_name: String, payload: Dictionary = {}) -> Dictionary:
	_client._begin()
	var response: Dictionary = await _client.socket.request(event_name, payload)
	_client._end()
	if not response.get("ok", false):
		var error := str(response.get("error", "The request failed"))
		if error == ROOM_GONE_ERROR and in_room():
			_table_is_gone()
		else:
			_client.action_failed.emit(error)
	return response


func _on_connected() -> void:
	# The server seats us again by itself; asking all the same tells us at once if the table
	# is gone
	if in_room() and status() != "finished":
		resync()
	# A search ends when the connection drops; it goes on from where it was
	if searching():
		_client.socket.request("donkeyFind", search)


func _on_auth_changed() -> void:
	if not _client.is_logged_in():
		_stop_search()
		if in_room():
			_forget_table()
			changed.emit()


func _on_event(event_name: String, payload: Variant) -> void:
	if not (payload is Dictionary) or not event_name.begins_with("donkey"):
		return
	match event_name:
		"donkeyState":
			_apply_state(payload)
		"donkeyNotice":
			_announce(payload)
		"donkeyInvite":
			invite_received.emit(payload)
		"donkeyMatchStatus":
			if searching():
				search_status = payload
				var starts_in: Variant = payload.get("startsIn")
				search_starts_at = Time.get_ticks_msec() + int(starts_in) if starts_in != null else 0
				search_changed.emit()
		"donkeyMatchFound":
			_stop_search()  # the table's state follows at once
		"donkeyMatchFailed":
			_stop_search()
			_client.action_failed.emit(str(payload.get("message", "No table could be found")))


func _apply_state(new_state: Dictionary) -> void:
	if searching() and new_state.get("status") in ["waiting", "playing"]:
		_stop_search()
	var turn_changed: bool = state.get("roomId") != new_state.get("roomId") or state.get("turn") != new_state.get("turn")
	var before: Array = state.get("requests", []) if state.get("roomId") == new_state.get("roomId") else []
	state = new_state
	_apply_requests(before)
	_last_table = {
		"private": new_state.get("private", false), "maxPlayers": int(new_state.get("maxPlayers", 2)),
		"stake": int(new_state.get("stake", 0)), "roomId": str(new_state.get("roomId", "")),
	}
	var turn_time: Variant = new_state.get("turnTimeLeft")
	turn_ends_at = Time.get_ticks_msec() + int(turn_time) if turn_time != null else 0
	if turn_time == null:
		turn_total = 0
	elif turn_changed or int(turn_time) > turn_total:
		turn_total = maxi(int(turn_time), int(new_state.get("turnSeconds", 0)) * 1000)
	changed.emit()


# Request Card: the clocks of the requests, and news of each one that came or was answered,
# told to the two players it concerns and, when cards moved, to the whole table.
func _apply_requests(before: Array) -> void:
	var wait := int(state.get("requestWait", 0))
	request_ready_at = Time.get_ticks_msec() + wait if wait > 0 else 0
	var now := Time.get_ticks_msec()
	var seen := {}
	for request: Dictionary in before:
		seen[str(request.get("id"))] = str(request.get("status"))
	var ends := {}
	for request: Dictionary in requests():
		var id := str(request.get("id"))
		if request.get("status") == "pending":
			ends[id] = now + int(request.get("expiresIn", 0))
		var was: String = seen.get(id, "")
		var status_now := str(request.get("status"))
		if was != status_now:
			_announce_request(request, was)
	_request_ends = ends


func _announce_request(request: Dictionary, was: String) -> void:
	var me := _client.player_id
	var from := str(request.get("from"))
	var to := str(request.get("to"))
	var asker := player_name(from)
	var asked := player_name(to)
	match str(request.get("status")):
		"pending":
			if was.is_empty() and to == me:
				_client.notice.emit("info", "%s asks for your cards" % asker)
			elif was.is_empty() and from == me:
				_client.notice.emit("info", "Request sent to %s" % asked)
		"accepted":
			var moved := int(request.get("moved", 0))
			if from == me:
				_client.notice.emit("warning", "%s accepted: you got all %d of their cards" % [asked, moved])
			elif to == me:
				_client.notice.emit("info", "You gave your cards to %s: you are out and safe!" % asker)
			else:
				_client.notice.emit("info", "%s gave all %d cards to %s" % [asked, moved, asker])
		"rejected":
			if from == me:
				_client.notice.emit("info", "%s rejected your request" % asked)
		"expired":
			if from == me:
				_client.notice.emit("info", "No answer from %s" % asked)
			elif to == me:
				_client.notice.emit("info", "You did not answer %s in time" % asker)


# What happened to another player at our table, for Game.notice.
func _announce(news: Dictionary) -> void:
	var who := str(news.get("username", "A player"))
	var mine := str(news.get("userId", "")) == _client.player_id
	match str(news.get("type", "")):
		"joined":
			_client.notice.emit("info", "%s joined the table" % who)
		"left":
			_client.notice.emit("warning", "%s left the table" % who)
		"disconnected":
			_client.notice.emit("warning", "%s lost connection" % who)
		"reconnected":
			_client.notice.emit("info", "%s is back" % who)
		"away":
			_client.notice.emit("info", "You missed your turns: cards are played for you until you play again" if mine else "%s is away: their cards are played for them" % who)


func _table_is_gone() -> void:
	_forget_table()
	changed.emit()
	_client.action_failed.emit("This Donkey Master table is no longer running on the game server.\n\nYou are back on the home screen and can start a new game.")


func _stop_search() -> void:
	if not searching():
		return
	search = {}
	search_status = {}
	search_since = 0
	search_starts_at = 0
	search_changed.emit()


func _forget_table() -> void:
	state = {}
	turn_ends_at = 0
	turn_total = 0
	request_ready_at = 0
	_request_ends = {}


# The online size nearest to a table's seats (a private table may have had any number).
func _online_size(seats: int) -> int:
	for size: int in ONLINE_SIZES:
		if size >= seats:
			return size
	return MAX_PLAYERS
