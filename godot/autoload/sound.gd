extends Node
## Music and sound effects.
##
## Sound.play("card") plays an effect; Sound.music("table") changes the tune, fading from
## one into the other. The player can switch either off; the choice is kept in Config.
##
## The files in res://audio/ are made by tools/make_audio.js. To use a recording instead,
## replace the .wav and keep its name.

signal switches_changed

const VOICES := 14  # how many effects can sound at once
const MUSIC_DB := -13.0  # the music sits under the effects
const MUSIC_FADE := 0.9
const DUCKED_DB := -12.0  # how far the music steps back for a fanfare
const SILENT_DB := -60.0
const SAME_SOUND_GAP_MSEC := 25  # the same effect twice within this is heard as one, only louder

## Each effect: how loud it is (decibels), and how far its pitch may wander from one play to
## the next, so thirteen cards dealt in a row do not sound like a machine.
const EFFECTS := {
	"card": [-7.0, 0.12],
	"place": [-6.0, 0.1],
	"flip": [-6.0, 0.08],
	"shuffle": [-2.0, 0.0],
	"group": [-6.0, 0.06],
	"select": [-12.0, 0.04],
	"deselect": [-14.0, 0.04],
	"click": [-9.0, 0.03],
	"whoosh": [-9.0, 0.08],
	"turn": [-4.0, 0.0],
	"pass": [-16.0, 0.0],
	"tick": [-8.0, 0.0],
	"beep": [-12.0, 0.0],
	"go": [-8.0, 0.0],
	"meld": [-5.0, 0.0],
	"meld_pure": [-3.0, 0.0],
	"sparkle": [-8.0, 0.1],
	"notice": [-12.0, 0.0],
	"warning": [-9.0, 0.0],
	"error": [-10.0, 0.0],
	"join": [-8.0, 0.0],
	"leave": [-8.0, 0.0],
	"count": [-14.0, 0.05],
	"declare": [-1.0, 0.0],
	"win": [-2.0, 0.0],
	"lose": [-4.0, 0.0],
	"drop": [-6.0, 0.0],
	"wrong": [-7.0, 0.0],
	"firework": [-5.0, 0.15],
	"confetti": [-4.0, 0.1],
}
const TUNES := {"menu": "music_menu", "table": "music_table"}

var music_on: bool:
	get:
		return Config.music_on
	set(value):
		Config.save_sound(value, Config.sound_on)
		_apply_switches()

var sound_on: bool:
	get:
		return Config.sound_on
	set(value):
		Config.save_sound(Config.music_on, value)
		_apply_switches()

var _streams: Dictionary = {}  # effect name -> AudioStream
var _voices: Array[AudioStreamPlayer] = []
var _next_voice := 0
var _last_played: Dictionary = {}  # effect name -> Time.get_ticks_msec() of its last start
var _decks: Array[AudioStreamPlayer] = []  # two music players, to fade from one tune into another
var _deck_fades: Array = [null, null]
var _playing_deck := 0
var _tune := ""
var _duck: Tween
var _in_focus := true
# False in a run without a screen (the tests): there is nothing to play through, and a
# stream started there is never let go of by the engine, which it reports as a leak on exit.
var _has_output := AudioServer.get_driver_name() != "Dummy"


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for bus_name: String in ["Music", "Effects"]:
		AudioServer.add_bus()
		var index := AudioServer.bus_count - 1
		AudioServer.set_bus_name(index, bus_name)
		AudioServer.set_bus_send(index, "Master")
	AudioServer.set_bus_mute(0, Config.muted)

	for effect: String in EFFECTS:
		var stream := _load(effect)
		if stream != null:
			_streams[effect] = stream
	for index in VOICES:
		var voice := AudioStreamPlayer.new()
		voice.bus = "Effects"
		add_child(voice)
		_voices.append(voice)
	for index in 2:
		var deck := AudioStreamPlayer.new()
		deck.bus = "Music"
		deck.volume_db = SILENT_DB
		add_child(deck)
		_decks.append(deck)
	_apply_switches()


func _notification(what: int) -> void:
	# Two copies of the game on one PC would otherwise play over each other
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		_in_focus = false
		_apply_switches()
	elif what == NOTIFICATION_APPLICATION_FOCUS_IN:
		_in_focus = true
		_apply_switches()
	elif what == NOTIFICATION_WM_CLOSE_REQUEST:
		hush()


## Plays an effect. `volume_db` and `pitch` adjust this one play, e.g. a quieter, lower
## card sound for an opponent's move.
func play(effect: String, volume_db: float = 0.0, pitch: float = 1.0) -> void:
	var stream: AudioStream = _streams.get(effect)
	if stream == null or not sound_on or not _in_focus or not _has_output:
		return
	var now := Time.get_ticks_msec()
	if now - int(_last_played.get(effect, -1000)) < SAME_SOUND_GAP_MSEC:
		return
	_last_played[effect] = now

	var voice := _free_voice()
	var settings: Array = EFFECTS[effect]
	voice.stream = stream
	voice.volume_db = settings[0] + volume_db
	voice.pitch_scale = pitch * (1.0 + randf_range(-1.0, 1.0) * float(settings[1]))
	voice.play()


## Plays an effect after a pause; for sounds that belong to a moment in an animation.
func play_later(effect: String, seconds: float, volume_db: float = 0.0, pitch: float = 1.0) -> void:
	if seconds <= 0.0:
		play(effect, volume_db, pitch)
	else:
		get_tree().create_timer(seconds).timeout.connect(play.bind(effect, volume_db, pitch))


## Changes the tune: "menu", "table", or "" for none. Asking for the one already playing does nothing.
func music(tune: String) -> void:
	if tune == _tune:
		return
	_tune = tune
	_fade_deck(_playing_deck, SILENT_DB, true)
	if tune.is_empty() or not _has_output:
		return
	var stream := _load(str(TUNES.get(tune, "")))
	if stream == null:
		return
	_playing_deck = 1 - _playing_deck
	var deck := _decks[_playing_deck]
	deck.stream = stream
	deck.play()
	_fade_deck(_playing_deck, MUSIC_DB, false)


## Turns the music down for a moment so a fanfare can be heard over it.
func duck(seconds: float) -> void:
	if _duck != null:
		_duck.kill()
	_duck = create_tween()
	_duck.tween_method(_set_music_db, AudioServer.get_bus_volume_db(AudioServer.get_bus_index("Music")), DUCKED_DB, 0.15)
	_duck.tween_interval(seconds)
	_duck.tween_method(_set_music_db, DUCKED_DB, 0.0, 0.8)


## Stops everything at once. Call it right before get_tree().quit(): the engine reports a
## looping tune that is still playing when the game closes as a leak.
func hush() -> void:
	_tune = ""
	for player: AudioStreamPlayer in _decks + _voices:
		player.stop()


func _set_music_db(volume_db: float) -> void:
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index("Music"), volume_db)


func _load(file_name: String) -> AudioStream:
	var path := "res://audio/%s.wav" % file_name
	if not ResourceLoader.exists(path):
		# A new file that Godot has not imported yet: the game runs without that sound
		push_warning("Sound not found: %s (open the project in the Godot editor once to import it)" % path)
		return null
	return load(path)


func _free_voice() -> AudioStreamPlayer:
	for step in VOICES:
		var voice := _voices[(_next_voice + step) % VOICES]
		if not voice.playing:
			_next_voice = (_next_voice + step + 1) % VOICES
			return voice
	# All busy: take over the one that started longest ago
	var oldest := _voices[_next_voice]
	_next_voice = (_next_voice + 1) % VOICES
	return oldest


func _fade_deck(index: int, to_db: float, stop_after: bool) -> void:
	var deck := _decks[index]
	if _deck_fades[index] != null:
		_deck_fades[index].kill()
	var fade := create_tween()
	fade.tween_property(deck, "volume_db", to_db, MUSIC_FADE)
	if stop_after:
		fade.tween_callback(deck.stop)
	_deck_fades[index] = fade


func _apply_switches() -> void:
	AudioServer.set_bus_mute(AudioServer.get_bus_index("Music"), not music_on or not _in_focus)
	AudioServer.set_bus_mute(AudioServer.get_bus_index("Effects"), not sound_on or not _in_focus)
	switches_changed.emit()
