class_name VoiceChat
extends Node
## Voice chat at the table, like a call between the players sitting at it. Every GameClient
## has one as its `voice` (the app's is `Game.voice`); the table shows it with TableVoice.
## The table is the rummy table we sit at, or else our Donkey Master table (Game.donkey).
##
## The Mic switch sends what our microphone hears to the other players at our table, and only
## to them: the server passes each piece of sound on to that table and forgets it
## (backend/src/socket/VoiceRelay.js). The Speaker switch plays or silences what they say.
## The microphone starts off at every new table; the Speaker switch is remembered (Config).
##
## Sound goes out only while we speak: a noise gate listens to the microphone and opens on a
## voice, with a moment's grace at the end of each word. Phones have no echo cancelling that
## Godot can reach, so when the others are heard through our loudspeaker, the gate also
## learns how much of that comes back into our microphone and stays shut for it: with
## earphones both sides can talk at once, on a loudspeaker the louder voice gets through.
##
## Sound travels on the game's own connection, as base64 text (Godot's Socket.IO client is
## text only). Pieces of 40 ms at about 64 kbit/s (VoiceCodec). A slow line drops sound rather
## than hold up the moves of the game behind it.

## The microphone or speaker was switched, the question about the microphone was asked or
## answered, or someone else's microphone went on or off.
signal changed
## The microphone could not be switched on: say why.
signal mic_failed(message: String)

const PERMISSION := "android.permission.RECORD_AUDIO"
const NO_PERMISSION_MESSAGE := "To talk at the table, allow Namma Rummy to use the microphone in your phone's Settings, then tap Mic again."
const FRAME := 640  # samples in one piece of sound: 40 ms at VoiceCodec.RATE
const OUT_BUS := "Voice"
## Sound waiting to go out on our connection beyond this means the line is slow: skip a piece.
const MAX_BACKLOG := 4096

# The noise gate. Loudness is the root mean square of a piece, 0 to 1.
const MIN_SPEECH := 0.006  # quieter than this is never a voice (about -44 dB)
const NOISE_MARGIN := 3.0  # a voice is at least this many times louder than the room
const NOISE_START := 0.01
const NOISE_RISE := 1.006  # the room's level creeps up this much a piece while it is loud...
const NOISE_FALL := 0.2  # ...and comes down this fast in the quiet moments
const HANG_FRAMES := 8  # pieces still sent after the voice fell quiet: the end of a word
# Echo: how much of what our loudspeaker plays comes back into the microphone
const ECHO_START := 1.0  # until it is known, assume a loudspeaker on the table
const ECHO_MAX := 2.0
const ECHO_RISE := 1.01
const ECHO_FALL := 0.3
const ECHO_MARGIN := 2.0  # a voice has to be this much louder than the echo to get through
const ECHO_LEARN := 0.02  # only what we play louder than this teaches the echo
const ECHO_TAIL_MSEC := 250  # the echo of a piece lasts this long after it has played
# Our voice is brought towards a steady loudness for the others (the phone may lie on the table)
const TARGET_LOUDNESS := 0.08
const MAX_GAIN := 4.0
const MIN_GAIN := 0.5
const FULL_LEVEL := 0.12  # this loud (after the gain) fills the speaking ring

# Playing the others: each speaker gets a little store against an uneven connection
const PREBUFFER_FRAMES := 1280  # 80 ms gathered before a speaker starts...
const PREBUFFER_MSEC := 120  # ...or this long after their first piece arrived
const MAX_LAG_FRAMES := 6400  # more than 0.4 s behind (after a stall): skip ahead
const HEARD_MSEC := 250  # someone counts as speaking until this long after their last piece
const DUCK_EVERY_MSEC := 300  # the music steps back while someone is heard

## Our microphone is on: what we say goes to the table. Change it with set_mic.
var mic_on := false
## The others are heard. Change it with set_speaker.
var speaker_on := true
## The phone is asking the player whether the game may use the microphone.
var asking := false
## Plays in place of the microphone, for tests and previews.
var test_source: AudioStream
## Pieces of our sound the noise gate has let through since the start (for tests).
var pieces_passed := 0

var _client: GameClient
var _game_id := ""  # the table the voice belongs to; "" at none
var _mics: Dictionary = {}  # user id -> true: their microphone is on (ours too)
var _speakers: Dictionary = {}  # user id -> Speaker
var _in_bus := ""
var _microphone: AudioStreamPlayer
var _capture: AudioEffectCapture
var _resampler: VoiceCodec.Resampler
var _pending := PackedFloat32Array()  # captured, not yet a whole piece
var _quiet_piece := PackedFloat32Array()  # the piece before, sent first when a word starts
var _hang := 0  # pieces still to send (0: we are not speaking)
var _noise := NOISE_START
var _echo := ECHO_START
var _gain := 1.0
var _my_level := 0.0
var _played: Array = []  # [from msec, until msec, loudness]: what our loudspeaker is putting out
var _ducked_at := 0
var _paused := false


## One of the others, as we hear them.
class Speaker extends RefCounted:
	var player: AudioStreamPlayer
	var playback: AudioStreamGeneratorPlayback
	var capacity := 0  # frames the generator holds
	var waiting: Array[PackedVector2Array] = []  # arrived, not yet handed to the generator
	var waiting_frames := 0
	var first_waiting_at := 0
	var started := false  # playing; false while the first pieces of a sentence gather
	var level := 0.0  # how loud their latest piece was, 0 to 1
	var heard_at := -100000


func _init(client: GameClient) -> void:
	_client = client
	speaker_on = Config.voice_speaker_on
	name = "Voice"


func _ready() -> void:
	_client.socket.event_received.connect(_on_event)
	_client.socket.connected.connect(_on_connected)
	_client.state_changed.connect(_on_table_changed)
	_client.donkey.changed.connect(_on_table_changed)
	get_tree().on_request_permissions_result.connect(_on_permission)


func _exit_tree() -> void:
	_leave_table()
	if not _in_bus.is_empty() and AudioServer.get_bus_index(_in_bus) != -1:
		AudioServer.remove_bus(AudioServer.get_bus_index(_in_bus))


## Switches our microphone on or off. The first time, the phone asks the player for leave.
func set_mic(on: bool) -> void:
	if not on:
		asking = false
		_switch_mic(false)
		return
	if mic_on or _game_id.is_empty():
		return
	# Android asks the player; the answer comes back through _on_permission. Asking again
	# while the question is open is harmless, and finds a leave given meanwhile in Settings.
	# (iPhones ask by themselves when the microphone starts, and a PC does not ask.)
	if OS.get_name() == "Android" and not OS.request_permission(PERMISSION):
		asking = true
		changed.emit()
		return
	asking = false
	_switch_mic(true)


## Plays or silences the others. Remembered for the next tables.
func set_speaker(on: bool) -> void:
	if on == speaker_on:
		return
	speaker_on = on
	Config.save_voice_speaker(on)
	if not on:
		for speaker: Speaker in _speakers.values():
			_silence(speaker)
	changed.emit()


## Whether this player's microphone is on (we are one of them). A player who has left the
## table, or lost the connection, cannot be heard.
func has_mic(user_id: String) -> bool:
	if not _mics.has(user_id):
		return false
	if user_id == _client.player_id:
		return true
	for player: Dictionary in table_players():
		if str(player.get("id", "")) == user_id:
			return player.get("connected", true) and not player.get("left", false)
	return false


## The players at the table the voice belongs to, as its state lists them: the rummy table's,
## or the Donkey Master table's.
func table_players() -> Array:
	if not _client.state.is_empty():
		return _client.players()
	return _client.donkey.players()


## How loud this player is speaking right now, from 0 (silent) to 1; never quite 0 while they
## speak. For us it is what our own microphone sends.
func level_of(user_id: String) -> float:
	if user_id == _client.player_id:
		return maxf(_my_level, 0.05) if mic_on and _hang > 0 else 0.0
	var speaker: Speaker = _speakers.get(user_id)
	if speaker == null or Time.get_ticks_msec() - speaker.heard_at > HEARD_MSEC:
		return 0.0
	return maxf(speaker.level, 0.05)


func _process(_delta: float) -> void:
	if mic_on and not _paused and _microphone != null and _microphone.playing:
		_listen()
	if speaker_on:
		var now := Time.get_ticks_msec()
		for speaker: Speaker in _speakers.values():
			_play(speaker, now)


func _notification(what: int) -> void:
	# A phone in the background is not listening, and what was said meanwhile is stale
	if what == NOTIFICATION_APPLICATION_PAUSED:
		_paused = true
		if _microphone != null:
			_microphone.stop()
	elif what == NOTIFICATION_APPLICATION_RESUMED and _paused:
		_paused = false
		for speaker: Speaker in _speakers.values():
			_silence(speaker)
		if mic_on:
			_start_microphone()


# ---------- the table ----------

func _on_table_changed() -> void:
	var game_id := _table_id()
	if game_id == _game_id:
		return
	_leave_table()
	_game_id = game_id
	if not game_id.is_empty():
		_fetch_mics()


# The table we sit at, as the server knows it (and puts in every voice event's "gameId"):
# the rummy table's gameId, or else the Donkey Master table's roomId; "" at none. A rummy
# table comes first, as on screen (main.gd).
func _table_id() -> String:
	if not _client.state.is_empty():
		return str(_client.state.get("gameId", ""))
	if _client.donkey.in_room():
		return str(_client.donkey.state.get("roomId", ""))
	return ""


# Back on the line: the server forgot our microphone when the connection dropped
func _on_connected() -> void:
	if not _game_id.is_empty():
		_fetch_mics()


func _leave_table() -> void:
	asking = false
	if mic_on:
		mic_on = false
		_stop_microphone()
	for speaker: Speaker in _speakers.values():
		if speaker.player != null:
			speaker.player.queue_free()
	_speakers.clear()
	_mics.clear()
	_played.clear()
	if not _game_id.is_empty():
		_game_id = ""
		changed.emit()


func _fetch_mics() -> void:
	var game_id := _game_id
	var response: Dictionary = await _client.socket.request("voiceMics")
	if not response.get("ok", false) or game_id != _game_id or response.get("gameId") != game_id:
		return
	var listed: Variant = response.get("mics")
	var server_has_ours: bool = listed is Array and (listed as Array).has(_client.player_id)
	_apply_mics(response)
	# Put the server right about our own microphone, either way
	if mic_on != server_has_ours:
		_tell_server(mic_on)


func _apply_mics(data: Dictionary) -> void:
	var list: Variant = data.get("mics")
	if not (list is Array):
		return
	_mics.clear()
	for id: Variant in list:
		_mics[str(id)] = true
	# Our own switch is ours to say, whatever an older answer still thought
	if mic_on:
		_mics[_client.player_id] = true
	else:
		_mics.erase(_client.player_id)
	changed.emit()


func _on_event(event_name: String, payload: Variant) -> void:
	if not (payload is Dictionary) or _game_id.is_empty() or str(payload.get("gameId", "")) != _game_id:
		return
	match event_name:
		"voice":
			_hear(payload)
		"voiceMics":
			_apply_mics(payload)


# ---------- our microphone ----------

func _on_permission(permission: String, granted: bool) -> void:
	if not asking or not permission.ends_with("RECORD_AUDIO"):
		return
	asking = false
	if granted and not _game_id.is_empty():
		_switch_mic(true)
	else:
		changed.emit()
		if not granted:
			mic_failed.emit(NO_PERMISSION_MESSAGE)


func _switch_mic(on: bool) -> void:
	if on == mic_on:
		changed.emit()
		return
	mic_on = on
	if on:
		_start_microphone()
		_mics[_client.player_id] = true
	else:
		_stop_microphone()
		_mics.erase(_client.player_id)
	changed.emit()
	_tell_server(on)


func _tell_server(on: bool) -> void:
	var game_id := _game_id
	var response: Dictionary = await _client.socket.request("voiceMic", {"on": on})
	if game_id != _game_id or game_id.is_empty():
		return
	if response.get("ok", false):
		_apply_mics(response)
	elif on and mic_on and _client.socket.is_online:
		# The server said no (offline, we keep it on and say so again when the line is back)
		_switch_mic(false)
		mic_failed.emit(str(response.get("error", "The microphone could not be switched on")))


func _start_microphone() -> void:
	if _microphone == null:
		_make_buses()
		_microphone = AudioStreamPlayer.new()
		_microphone.name = "Microphone"
		_microphone.bus = _in_bus
		add_child(_microphone)
	_microphone.stream = test_source if test_source != null else AudioStreamMicrophone.new()
	_capture.clear_buffer()
	_resampler = VoiceCodec.Resampler.new(AudioServer.get_mix_rate())
	_pending = PackedFloat32Array()
	_quiet_piece = PackedFloat32Array()
	_hang = 0
	_my_level = 0.0
	_microphone.play()


func _stop_microphone() -> void:
	if _microphone != null:
		_microphone.stop()  # the phone's microphone light goes out
	_hang = 0
	_my_level = 0.0


# Our microphone goes through its own bus: filtered to what a voice needs, caught, and not
# passed on to the loudspeaker. The others are heard through the "Voice" bus.
func _make_buses() -> void:
	_in_bus = "VoiceIn%d" % get_instance_id()
	var index := AudioServer.bus_count
	AudioServer.add_bus(index)
	AudioServer.set_bus_name(index, _in_bus)
	AudioServer.set_bus_mute(index, true)  # nobody hears themselves; the capture still does
	var rumble := AudioEffectHighPassFilter.new()
	rumble.cutoff_hz = 120.0
	var hiss := AudioEffectLowPassFilter.new()  # nothing above what 16 kHz can carry
	hiss.cutoff_hz = 6800.0
	hiss.db = AudioEffectFilter.FILTER_24DB
	_capture = AudioEffectCapture.new()
	_capture.buffer_length = 0.5
	AudioServer.add_bus_effect(index, rumble)
	AudioServer.add_bus_effect(index, hiss)
	AudioServer.add_bus_effect(index, _capture)
	_make_out_bus()


func _make_out_bus() -> void:
	if AudioServer.get_bus_index(OUT_BUS) != -1:
		return
	var index := AudioServer.bus_count
	AudioServer.add_bus(index)
	AudioServer.set_bus_name(index, OUT_BUS)
	AudioServer.set_bus_send(index, "Master")


# Takes what the microphone caught since the last frame and sends it on, piece by piece.
func _listen() -> void:
	var available := _capture.get_frames_available()
	if available > 0:
		_resampler.feed(_capture.get_buffer(available), _pending)
	while _pending.size() >= FRAME:
		var piece := _pending.slice(0, FRAME)
		_pending = _pending.slice(FRAME)
		_gate(piece)


# The noise gate: sends the piece when it holds a voice.
func _gate(piece: PackedFloat32Array) -> void:
	var loudness := VoiceCodec.loudness(piece)
	var played := _played_loudness()
	if loudness < _noise:
		_noise = lerpf(_noise, loudness, NOISE_FALL)
	else:
		_noise *= NOISE_RISE
	_noise = clampf(_noise, 0.0005, 0.1)
	if played > ECHO_LEARN:
		# The quietest the microphone gets while we play is the echo alone: we were not speaking
		var ratio := loudness / played
		_echo = lerpf(_echo, ratio, ECHO_FALL) if ratio < _echo else minf(_echo * ECHO_RISE, ECHO_MAX)
	var threshold := maxf(maxf(MIN_SPEECH, _noise * NOISE_MARGIN), _echo * played * ECHO_MARGIN)

	var was_speaking := _hang > 0
	if loudness > threshold:
		_hang = HANG_FRAMES
		var wanted := clampf(TARGET_LOUDNESS / loudness, MIN_GAIN, MAX_GAIN)
		_gain = lerpf(_gain, wanted, 0.25 if wanted < _gain else 0.02)  # down quickly, up slowly
		_my_level = clampf(loudness * _gain / FULL_LEVEL, 0.0, 1.0)
	elif _hang > 0:
		_hang -= 1
		_my_level *= 0.6
	if _hang > 0:
		if not was_speaking and not _quiet_piece.is_empty():
			_send(_quiet_piece, 0.0)  # the very start of the word
		_send(piece, _my_level)
	else:
		_my_level = 0.0
	_quiet_piece = piece


func _send(piece: PackedFloat32Array, level: float) -> void:
	pieces_passed += 1
	if not _client.socket.is_online or _client.socket.backlog() > MAX_BACKLOG:
		return
	var packet := VoiceCodec.encode(piece, _gain)
	_client.socket.send_event("voice", {"level": int(round(level * 100.0)), "data": Marshalls.raw_to_base64(packet)})


# How loud our loudspeaker is right now (the loudest piece playing or still echoing)
func _played_loudness() -> float:
	if _played.is_empty():
		return 0.0
	var now := Time.get_ticks_msec()
	var loudest := 0.0
	var still: Array = []
	for entry: Array in _played:
		if entry[1] < now:
			continue
		still.append(entry)
		if entry[0] <= now:
			loudest = maxf(loudest, entry[2])
	_played = still
	return loudest


# ---------- the others ----------

func _hear(payload: Dictionary) -> void:
	var from := str(payload.get("from", ""))
	if from.is_empty() or from == _client.player_id:
		return
	var speaker := _speaker(from)
	speaker.level = clampf(float(payload.get("level", 0)) / 100.0, 0.0, 1.0)
	speaker.heard_at = Time.get_ticks_msec()
	if not speaker_on or _paused:
		return  # the ring round their picture still shows who is speaking
	var frames := VoiceCodec.decode(Marshalls.base64_to_raw(str(payload.get("data", ""))))
	if frames.is_empty():
		return
	if speaker.player == null:
		_start_player(speaker)
	if speaker.waiting.is_empty() and not speaker.started:
		speaker.first_waiting_at = speaker.heard_at
	speaker.waiting.append(frames)
	speaker.waiting_frames += frames.size()


func _speaker(user_id: String) -> Speaker:
	var speaker: Speaker = _speakers.get(user_id)
	if speaker == null:
		speaker = Speaker.new()
		_speakers[user_id] = speaker
	return speaker


func _start_player(speaker: Speaker) -> void:
	_make_out_bus()
	var stream := AudioStreamGenerator.new()
	stream.mix_rate_mode = AudioStreamGenerator.MIX_RATE_CUSTOM
	stream.mix_rate = VoiceCodec.RATE
	stream.buffer_length = 1.0
	speaker.player = AudioStreamPlayer.new()
	speaker.player.stream = stream
	speaker.player.bus = OUT_BUS
	add_child(speaker.player)
	speaker.player.play()
	speaker.playback = speaker.player.get_stream_playback()
	speaker.capacity = speaker.playback.get_frames_available()


# Hands what has arrived to the speaker's generator, a sentence at a time.
func _play(speaker: Speaker, now: int) -> void:
	if speaker.playback == null:
		return
	var room := speaker.playback.get_frames_available()
	var queued := speaker.capacity - room  # handed over, not yet played
	if not speaker.started:
		if speaker.waiting.is_empty():
			return
		if speaker.waiting_frames < PREBUFFER_FRAMES and now - speaker.first_waiting_at < PREBUFFER_MSEC:
			return
		speaker.started = true
	# Far behind (the line stalled, then everything came at once): skip the oldest
	while speaker.waiting.size() > 1 and queued + speaker.waiting_frames > MAX_LAG_FRAMES:
		speaker.waiting_frames -= speaker.waiting.pop_front().size()
	while not speaker.waiting.is_empty() and speaker.waiting[0].size() <= room:
		var frames: PackedVector2Array = speaker.waiting.pop_front()
		speaker.waiting_frames -= frames.size()
		speaker.playback.push_buffer(frames)
		var starts := now + queued * 1000 / VoiceCodec.RATE
		var ends := starts + frames.size() * 1000 / VoiceCodec.RATE
		_played.append([starts, ends + ECHO_TAIL_MSEC, VoiceCodec.frames_loudness(frames)])
		room -= frames.size()
		queued += frames.size()
		if now - _ducked_at >= DUCK_EVERY_MSEC:
			_ducked_at = now
			Sound.duck(0.6)  # the music steps back while someone talks
	if speaker.waiting.is_empty() and queued <= 0:
		speaker.started = false  # the sentence is over, or the next piece is late: gather again


func _silence(speaker: Speaker) -> void:
	speaker.waiting.clear()
	speaker.waiting_frames = 0
	speaker.started = false
	if speaker.player != null:
		# A generator cannot be emptied while it plays: start it again, empty
		speaker.player.stop()
		speaker.player.play()
		speaker.playback = speaker.player.get_stream_playback()
