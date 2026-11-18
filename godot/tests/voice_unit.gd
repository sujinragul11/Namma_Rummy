extends Node
## The voice chat's sound handling, without a server: the codec, the resampler, the noise
## gate, the echo guard and the store in front of each speaker. tests/voice_e2e covers the
## server and the table.
##
##   godot --headless --path . res://tests/voice_unit.tscn

var _passed := 0
var _failed := 0


func _ready() -> void:
	_codec()
	_resampler(44100.0)
	_resampler(48000.0)
	var client := GameClient.new()
	client.remember_login = false
	add_child(client)
	_gate(client.voice)
	_echo(client.voice)
	await _speakers(client.voice)
	print("voice_unit: %d passed, %d failed" % [_passed, _failed])
	get_tree().quit(1 if _failed > 0 else 0)


func _codec() -> void:
	# Something like a voice: a few harmonics under a rising and falling envelope
	var samples := PackedFloat32Array()
	for i in 16000:
		var t := i / 16000.0
		var envelope := 0.5 - 0.5 * cos(TAU * t * 3.0)
		samples.append(envelope * (0.3 * sin(TAU * 220.0 * t) + 0.15 * sin(TAU * 660.0 * t) + 0.06 * sin(TAU * 1500.0 * t)))
	var packet := VoiceCodec.encode(samples)
	_check("a second of sound packs into 8 kB", packet.size() == VoiceCodec.HEADER + 8000, str(packet.size()))
	var frames := VoiceCodec.decode(packet)
	_check("and unpacks into as many samples", frames.size() == samples.size(), str(frames.size()))
	var signal_power := 0.0
	var error_power := 0.0
	for i in mini(frames.size(), samples.size()):
		signal_power += samples[i] * samples[i]
		error_power += (samples[i] - frames[i].x) * (samples[i] - frames[i].x)
	var snr := 10.0 * log(signal_power / maxf(error_power, 1e-12)) / log(10.0)
	_check("clearly enough (over 25 dB)", snr > 25.0, "%.1f dB" % snr)
	_check("both channels carry it", frames[1234].x == frames[1234].y)

	var piece := VoiceCodec.encode(samples.slice(0, VoiceChat.FRAME))
	var written := Marshalls.raw_to_base64(piece).length()
	_check("a 40 ms piece is 324 bytes, 432 characters as text (the server takes 4000)", piece.size() == 324 and written == 432, "%d / %d" % [piece.size(), written])
	_check("a piece starts where the sound starts", absf(VoiceCodec.decode(piece)[0].x - samples[0]) < 0.001)
	var loud := PackedFloat32Array([2.0, -2.0, 1.5, -1.5])
	var clipped := VoiceCodec.decode(VoiceCodec.encode(loud))
	_check("sound past full scale is held at it", absf(clipped[0].x) <= 1.0 and absf(clipped[1].x) <= 1.0)
	_check("an odd number of samples rounds up to whole bytes", VoiceCodec.encode(samples.slice(0, 5)).size() == VoiceCodec.HEADER + 3)
	_check("a packet too short to be one gives nothing", VoiceCodec.decode(PackedByteArray([1, 2, 3])).is_empty() and VoiceCodec.decode(PackedByteArray()).is_empty())
	_check("gain multiplies on the way", absf(VoiceCodec.decode(VoiceCodec.encode(PackedFloat32Array([0.1, 0.1]), 3.0))[0].x - 0.3) < 0.01)


func _resampler(rate: float) -> void:
	var resampler := VoiceCodec.Resampler.new(rate)
	var out := PackedFloat32Array()
	var total := int(rate)
	var given := 0
	var sizes := [512, 100, 1, 2048, 7, 333]
	var turn := 0
	while given < total:
		var count := mini(sizes[turn % sizes.size()], total - given)
		turn += 1
		var frames := PackedVector2Array()
		for i in count:
			var value := 0.5 * sin(TAU * 1000.0 * (given + i) / rate)
			frames.append(Vector2(value, value))
		resampler.feed(frames, out)
		given += count
	_check("%d Hz: a second becomes 16,000 samples" % int(rate), absi(out.size() - 16000) <= 2, str(out.size()))
	var crossings := 0
	var largest_step := 0.0
	for i in range(1, out.size()):
		if (out[i - 1] < 0.0) != (out[i] < 0.0):
			crossings += 1
		largest_step = maxf(largest_step, absf(out[i] - out[i - 1]))
	_check("%d Hz: a 1 kHz tone stays 1 kHz" % int(rate), absi(crossings - 2000) <= 20, str(crossings))
	# A 1 kHz sine of 0.5 moves at most 0.5 * 2π * 1000 / 16000 = 0.196 between samples
	_check("%d Hz: no jumps where buffers meet" % int(rate), largest_step < 0.21, "%.3f" % largest_step)


func _piece(loudness: float) -> PackedFloat32Array:
	# A 300 Hz tone with this root mean square
	var piece := PackedFloat32Array()
	for i in VoiceChat.FRAME:
		piece.append(loudness * sqrt(2.0) * sin(TAU * 300.0 * i / VoiceCodec.RATE))
	return piece


func _gate(voice: VoiceChat) -> void:
	voice.mic_on = true  # as if switched on; no microphone is started here
	var start := voice.pieces_passed
	for i in 30:
		voice._gate(_piece(0.001))
	_check("a quiet room sends nothing", voice.pieces_passed == start, str(voice.pieces_passed - start))
	_check("and nobody sees us speaking", voice.level_of(voice._client.player_id) == 0.0)
	for i in 10:
		voice._gate(_piece(0.1))
	_check("a voice is sent, with the quiet piece before it", voice.pieces_passed == start + 11, str(voice.pieces_passed - start))
	_check("we show as speaking", voice.level_of(voice._client.player_id) > 0.3, str(voice.level_of(voice._client.player_id)))
	var after_voice := voice.pieces_passed
	for i in 20:
		voice._gate(_piece(0.001))
	_check("the end of a word follows it, then nothing", voice.pieces_passed == after_voice + VoiceChat.HANG_FRAMES - 1, str(voice.pieces_passed - after_voice))
	_check("and we no longer show as speaking", voice.level_of(voice._client.player_id) == 0.0)
	# A soft voice is brought up for the others, a loud one down
	for i in 60:
		voice._gate(_piece(0.03))
	_check("a soft voice is made louder", voice._gain > 1.8, "%.2f" % voice._gain)
	for i in 30:
		voice._gate(_piece(0.4))
	_check("a loud voice quieter", voice._gain < VoiceChat.MIN_GAIN + 0.01, "%.2f" % voice._gain)
	voice.mic_on = false


func _echo(voice: VoiceChat) -> void:
	voice.mic_on = true
	var forever := Time.get_ticks_msec() + 600000
	# On a loudspeaker: the others play at 0.2 and 60% of that comes back into the microphone
	voice._echo = VoiceChat.ECHO_START
	voice._hang = 0
	voice._played = [[0, forever, 0.2]]
	var start := voice.pieces_passed
	for i in 30:
		voice._gate(_piece(0.12))
	_check("the others' voices from our loudspeaker are not sent back", voice.pieces_passed == start, str(voice.pieces_passed - start))
	_check("the echo is learnt (about 0.6)", absf(voice._echo - 0.6) < 0.1, "%.2f" % voice._echo)
	start = voice.pieces_passed
	for i in 5:
		voice._gate(_piece(0.5))
	_check("a voice clearly over the echo still gets through", voice.pieces_passed - start >= 5, str(voice.pieces_passed - start))

	# With earphones: the microphone hears nothing of what plays
	voice._echo = VoiceChat.ECHO_START
	voice._hang = 0
	for i in 15:
		voice._gate(_piece(0.001))
	_check("with earphones the echo is learnt to be next to none", voice._echo < 0.05, "%.3f" % voice._echo)
	start = voice.pieces_passed
	for i in 5:
		voice._gate(_piece(0.05))
	_check("so both can talk at once", voice.pieces_passed - start >= 5, str(voice.pieces_passed - start))
	voice._played = []
	voice._hang = 0
	voice.mic_on = false


func _speakers(voice: VoiceChat) -> void:
	var piece := Marshalls.raw_to_base64(VoiceCodec.encode(_piece(0.1)))
	voice._hear({"from": "2", "level": 50, "data": piece})
	var speaker: VoiceChat.Speaker = voice._speakers.get("2")
	_check("someone speaking shows at once", voice.level_of("2") == 0.5)
	voice._process(0.016)
	_check("one piece waits for the next before playing", speaker != null and not speaker.started and speaker.waiting.size() == 1)
	voice._hear({"from": "2", "level": 60, "data": piece})
	voice._process(0.016)
	var queued := speaker.capacity - speaker.playback.get_frames_available()
	_check("two pieces start the sentence", speaker.started and speaker.waiting.is_empty() and queued > 0, "started %s, queued %d" % [speaker.started, queued])
	_check("what plays is remembered for the echo guard", voice._played_loudness() > 0.05, str(voice._played))

	# A stalled line delivers a second of sound at once: only the latest part is played
	for i in 25:
		voice._hear({"from": "2", "level": 60, "data": piece})
	voice._process(0.016)
	queued = speaker.capacity - speaker.playback.get_frames_available()
	_check("after a stall it catches up rather than lag behind", queued + speaker.waiting_frames <= VoiceChat.MAX_LAG_FRAMES + VoiceChat.FRAME, "%d frames behind" % (queued + speaker.waiting_frames))

	voice._hear({"from": "2", "level": 60, "data": ""})
	_check("an empty piece is ignored", speaker.waiting_frames <= VoiceChat.MAX_LAG_FRAMES)
	voice._hear({"from": "", "level": 60, "data": piece})
	_check("sound from nobody is ignored", not voice._speakers.has(""))

	voice.set_speaker(false)
	_check("Speaker off silences what was waiting", speaker.waiting.is_empty() and speaker.playback.get_frames_available() == speaker.capacity)
	voice._hear({"from": "3", "level": 40, "data": piece})
	_check("Speaker off: nothing is played...", voice._speakers["3"].player == null)
	_check("...but who speaks still shows", voice.level_of("3") == 0.4)
	voice.set_speaker(true)
	await get_tree().create_timer(0.4).timeout
	_check("someone who stopped speaking no longer shows", voice.level_of("3") == 0.0 and voice.level_of("2") == 0.0)
	voice._leave_table()
	_check("leaving the table lets every speaker go", voice._speakers.is_empty())


func _check(what: String, ok: bool, detail: String = "") -> void:
	if ok:
		_passed += 1
	else:
		_failed += 1
		print("FAIL  %s  %s" % [what, detail])
