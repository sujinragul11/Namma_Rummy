class_name VoiceCodec
## Sound for the voice chat, made small enough to send many times a second: 16,000 samples a
## second, one channel, each sample squeezed into 4 bits (IMA ADPCM), about 64 kbit/s.
##
## Godot has no speech codec of its own. ADPCM is simple enough for GDScript (a second of
## sound takes a few milliseconds each way on a PC) and keeps speech clear (about 30 dB SNR).
## Each packet stands on its own: a 4-byte header (the starting sample, little-endian, and the
## step index) and then two samples per byte, the first in the low half.

const RATE := 16000
const HEADER := 4
const STEPS := [
	7, 8, 9, 10, 11, 12, 13, 14, 16, 17, 19, 21, 23, 25, 28, 31, 34, 37, 41, 45, 50, 55, 60,
	66, 73, 80, 88, 97, 107, 118, 130, 143, 157, 173, 190, 209, 230, 253, 279, 307, 337,
	371, 408, 449, 494, 544, 598, 658, 724, 796, 876, 963, 1060, 1166, 1282, 1411, 1552,
	1707, 1878, 2066, 2272, 2499, 2749, 3024, 3327, 3660, 4026, 4428, 4871, 5358, 5894,
	6484, 7132, 7845, 8630, 9493, 10442, 11487, 12635, 13899, 15289, 16818, 18500, 20350,
	22385, 24623, 27086, 29794, 32767,
]
const INDEX_MOVES := [-1, -1, -1, -1, 2, 4, 6, 8]


## `samples` from -1 to 1, multiplied by `gain` on the way (and held at full scale).
## An even number of samples makes whole bytes.
static func encode(samples: PackedFloat32Array, gain: float = 1.0) -> PackedByteArray:
	var count := samples.size()
	var out := PackedByteArray()
	out.resize(HEADER + (count + 1) / 2)
	if count == 0:
		return out
	var scale := gain * 32767.0
	var predicted := clampi(int(samples[0] * scale), -32768, 32767)
	var index := 0
	out.encode_s16(0, predicted)
	out[2] = index
	var low := 0
	for i in count:
		var step: int = STEPS[index]
		var diff: int = clampi(int(samples[i] * scale), -32768, 32767) - predicted
		var nibble := 0
		if diff < 0:
			nibble = 8
			diff = -diff
		var delta := step >> 3
		if diff >= step:
			nibble |= 4
			diff -= step
			delta += step
		step >>= 1
		if diff >= step:
			nibble |= 2
			diff -= step
			delta += step
		step >>= 1
		if diff >= step:
			nibble |= 1
			delta += step
		predicted = clampi(predicted - delta if nibble & 8 else predicted + delta, -32768, 32767)
		index = clampi(index + INDEX_MOVES[nibble & 7], 0, 88)
		if i & 1:
			out[HEADER + (i >> 1)] = low | (nibble << 4)
		else:
			low = nibble
	if count & 1:
		out[HEADER + (count >> 1)] = low
	return out


## The samples of one packet as stereo frames, ready for an AudioStreamGenerator.
## Empty when the packet is too short to be one.
static func decode(packet: PackedByteArray) -> PackedVector2Array:
	var frames := PackedVector2Array()
	if packet.size() <= HEADER:
		return frames
	var count := (packet.size() - HEADER) * 2
	frames.resize(count)
	var predicted := packet.decode_s16(0)
	var index := clampi(packet[2], 0, 88)
	for i in count:
		var byte: int = packet[HEADER + (i >> 1)]
		var nibble: int = (byte >> 4) if i & 1 else (byte & 15)
		var step: int = STEPS[index]
		var delta := step >> 3
		if nibble & 4:
			delta += step
		if nibble & 2:
			delta += step >> 1
		if nibble & 1:
			delta += step >> 2
		predicted = clampi(predicted - delta if nibble & 8 else predicted + delta, -32768, 32767)
		index = clampi(index + INDEX_MOVES[nibble & 7], 0, 88)
		var value := predicted / 32768.0
		frames[i] = Vector2(value, value)
	return frames


## How loud the samples are: their root mean square, 0 to 1.
static func loudness(samples: PackedFloat32Array) -> float:
	if samples.is_empty():
		return 0.0
	var total := 0.0
	for sample in samples:
		total += sample * sample
	return sqrt(total / samples.size())


## The same for frames on their way out, from their left channel.
static func frames_loudness(frames: PackedVector2Array) -> float:
	if frames.is_empty():
		return 0.0
	var total := 0.0
	for frame in frames:
		total += frame.x * frame.x
	return sqrt(total / frames.size())


## Turns sound captured at the mixer's rate into mono at RATE, by linear interpolation.
## The low-pass filter on the capture bus keeps what lies above RATE / 2 out beforehand.
## Feed it buffer after buffer: it carries its place over from one to the next.
class Resampler extends RefCounted:
	var _step := 1.0  # input frames per output sample
	var _position := 0.0  # where the next output sample lies; 0 is the last frame of the buffer before
	var _previous := 0.0  # that frame, as mono

	func _init(input_rate: float) -> void:
		_step = input_rate / RATE

	## Appends the samples that `frames` gives to `out`.
	func feed(frames: PackedVector2Array, out: PackedFloat32Array) -> void:
		var count := frames.size()
		if count == 0:
			return
		var position := _position
		# Position k lies on frames[k - 1]; position 0 on the frame kept from before
		while position < count:
			var whole := int(position)
			var part := position - whole
			var before: float = _previous
			if whole > 0:
				var frame: Vector2 = frames[whole - 1]
				before = (frame.x + frame.y) * 0.5
			var next: Vector2 = frames[whole]
			var after := (next.x + next.y) * 0.5
			out.append(before + (after - before) * part)
			position += _step
		_position = position - count
		var last: Vector2 = frames[count - 1]
		_previous = (last.x + last.y) * 0.5
