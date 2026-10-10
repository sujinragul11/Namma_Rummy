class_name SocketIOClient
extends Node
## A small Socket.IO v4 client (Engine.IO v4 over a WebSocket).
##
## Godot has no Socket.IO support of its own. This covers what the rummy server uses:
## a login token sent when connecting, named events, replies to requests
## (Socket.IO "acknowledgements"), and reconnecting after the connection drops.

signal connected
signal disconnected
## The server refused the connection, for example because the login token is no longer valid.
signal connect_refused(message: String)
signal event_received(event_name: String, payload: Variant)

const REPLY_TIMEOUT := 8.0
const RECONNECT_DELAY := 2.0

var is_online := false

var _peer: WebSocketPeer
var _url := ""
var _auth: Dictionary = {}
var _keep_open := false
var _retry_in := 0.0
var _next_reply_id := 0
var _waiting: Dictionary = {}  # reply id -> Reply


class Reply extends RefCounted:
	signal arrived(response: Dictionary)


## Connects and stays connected (retrying after a drop) until close() is called.
func open(server_url: String, auth: Dictionary) -> void:
	close()
	_url = server_url.replace("https://", "wss://").replace("http://", "ws://")
	_url += "/socket.io/?EIO=4&transport=websocket"
	_auth = auth
	_keep_open = true
	_connect_now()


func close() -> void:
	_keep_open = false
	if _peer != null:
		_peer.close()
		_peer = null
	_went_offline("Not connected to the game server")


## Sends an event without waiting for a reply.
func send_event(event_name: String, payload: Dictionary = {}) -> void:
	if is_online:
		_peer.send_text("42" + JSON.stringify([event_name, payload]))


## Sends an event and returns the server's reply: {"ok": true, ...} or {"ok": false, "error": ...}.
func request(event_name: String, payload: Dictionary = {}) -> Dictionary:
	if not is_online:
		return {"ok": false, "error": "Not connected to the game server"}

	var id := _next_reply_id
	_next_reply_id += 1
	var reply := Reply.new()
	_waiting[id] = reply
	_peer.send_text("42%d%s" % [id, JSON.stringify([event_name, payload])])

	var give_up := {"ok": false, "error": "The game server did not respond"}
	get_tree().create_timer(REPLY_TIMEOUT).timeout.connect(_answer.bind(id, give_up))

	var response: Dictionary = await reply.arrived
	return response


func _process(delta: float) -> void:
	if _peer == null:
		if _keep_open:
			_retry_in -= delta
			if _retry_in <= 0.0:
				_connect_now()
		return

	_peer.poll()
	var ready_state := _peer.get_ready_state()
	if ready_state == WebSocketPeer.STATE_OPEN:
		# Handling a packet can close the connection, hence the null check
		while _peer != null and _peer.get_available_packet_count() > 0:
			_on_packet(_peer.get_packet().get_string_from_utf8())
	elif ready_state == WebSocketPeer.STATE_CLOSED:
		_peer = null
		_retry_in = RECONNECT_DELAY
		_went_offline("Lost connection to the game server")


func _connect_now() -> void:
	_peer = WebSocketPeer.new()
	_peer.inbound_buffer_size = 1024 * 1024  # a full table state is a few kilobytes
	if _peer.connect_to_url(_url) != OK:
		_peer = null
		_retry_in = RECONNECT_DELAY


# Engine.IO layer: the first character says what kind of packet this is.
func _on_packet(packet: String) -> void:
	if packet.is_empty():
		return
	match packet[0]:
		"0":  # the transport is open: now ask Socket.IO to connect, with our login token
			_peer.send_text("40" + JSON.stringify(_auth))
		"2":  # ping from the server
			_peer.send_text("3")
		"4":  # a Socket.IO message
			_on_message(packet.substr(1))


# Socket.IO layer.
func _on_message(message: String) -> void:
	if message.is_empty():
		return
	var body := message.substr(1)
	match message[0]:
		"0":  # connected
			is_online = true
			connected.emit()
		"1":  # the server ended our session
			_peer.close()
		"2":  # an event: optional reply id, then ["name", payload]
			var data: Variant = JSON.parse_string(_split_reply_id(body)[1])
			if data is Array and not data.is_empty():
				event_received.emit(str(data[0]), data[1] if data.size() > 1 else null)
		"3":  # the reply to one of our requests: reply id, then [response]
			var parts := _split_reply_id(body)
			var data: Variant = JSON.parse_string(parts[1])
			var response: Dictionary = {}
			if data is Array and not data.is_empty() and data[0] is Dictionary:
				response = data[0]
			_answer(int(parts[0]), response)
		"4":  # the server refused us; retrying with the same token would fail the same way
			var data: Variant = JSON.parse_string(body)
			var reason := "The game server refused the connection"
			if data is Dictionary:
				reason = str(data.get("message", reason))
			_keep_open = false
			_peer.close()
			_peer = null
			connect_refused.emit(reason)


# Splits "12[...]" into ["12", "[...]"]. The id is empty when the message carries none.
func _split_reply_id(body: String) -> Array:
	var index := 0
	while index < body.length() and body[index] >= "0" and body[index] <= "9":
		index += 1
	return [body.substr(0, index), body.substr(index)]


func _answer(id: int, response: Dictionary) -> void:
	if not _waiting.has(id):
		return  # already answered, or timed out earlier
	var reply: Reply = _waiting[id]
	_waiting.erase(id)
	reply.arrived.emit(response)


func _went_offline(reason: String) -> void:
	for id: int in _waiting.keys():
		_answer(id, {"ok": false, "error": reason})
	if is_online:
		is_online = false
		disconnected.emit()
