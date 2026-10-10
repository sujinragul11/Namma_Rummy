extends Control
## Plays every effect and every sound once, saves a picture of each effect, and checks that
## sound really reaches the mixer. Needs no server. Use it to look at the effects after a change.
##
## Run WITH a window (not --headless), from godot/:
##   godot --path . res://tests/fx_preview.tscn -- --profile=fxpreview --mute --shots=<folder>
## --mute silences the speakers only; the mixer still carries the sound, so the checks hold.

const HEARD_DB := -50.0  # anything above this on a mixer bus counts as sound

var _shots := ""
var _step := 0
var _passed := 0
var _failed := 0


func _ready() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--shots="):
			_shots = argument.trim_prefix("--shots=")
	if not _shots.is_empty():
		DirAccess.make_dir_recursive_absolute(_shots)

	theme = Ui.game_theme
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var felt := FeltBackground.new()
	felt.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(felt)
	var switches := SoundSwitches.new()
	switches.position = Vector2(24, 24)
	add_child(switches)
	_run(switches)


func _run(switches: SoundSwitches) -> void:
	await _wait(0.3)
	# The window may open behind another one; the game is silent then, which would fail every check
	Sound._in_focus = true
	Sound.music_on = true
	Sound.sound_on = true

	# ---------- sound ----------
	_check("every effect has a sound file", Sound._streams.size() == Sound.EFFECTS.size(), "%d of %d" % [Sound._streams.size(), Sound.EFFECTS.size()])
	Sound.music("menu")
	_check("the menu tune reaches the mixer", await _heard("Music", 1.5))
	Sound.music("table")
	await _wait(Sound.MUSIC_FADE + 0.4)
	_check("the table tune takes over", Sound._decks[Sound._playing_deck].playing and not Sound._decks[1 - Sound._playing_deck].playing)
	_check("the tune loops instead of ending", (Sound._decks[Sound._playing_deck].stream as AudioStreamWAV).loop_mode == AudioStreamWAV.LOOP_FORWARD)

	Sound.music_on = false
	await _wait(0.3)
	_check("switching music off silences it", not await _heard("Music", 0.4))
	Sound.music_on = true

	var silent: Array = []
	for effect: String in Sound.EFFECTS:
		Sound.play(effect)
		if not await _heard("Effects", 0.5):
			silent.append(effect)
		await _wait(0.08)
	_check("every effect reaches the mixer", silent.is_empty(), str(silent))

	await _wait(1.5)  # let the long ones ring out
	Sound.sound_on = false
	await _wait(0.3)
	Sound.play("turn")
	_check("switching sound off silences effects", not await _heard("Effects", 0.4))
	await _shot("switches-off-sound")
	Sound.sound_on = true
	_check("the switches are remembered", Config.sound_on and Config.music_on)

	for index in 20:
		Sound.play("card")
		await get_tree().process_frame
	_check("twenty cards at once do not run out of voices", true)

	# ---------- effects ----------
	var middle := get_viewport_rect().size / 2.0
	Fx.sparkle(middle)
	Fx.float_text(middle - Vector2(0, 60), "Pure sequence!")
	Fx.ring(middle + Vector2(300, 0), Color.WHITE)
	await _wait(0.25)
	await _shot("sparkle")

	Fx.banner("ROUND 2")
	await _wait(0.6)
	await _shot("banner")
	await _wait(1.0)

	Fx.flash()
	await _wait(0.1)
	await _shot("flash")

	Fx.shake(14.0, 0.4)
	await _wait(0.15)
	_check("the screen is shaken", get_viewport().canvas_transform != Transform2D.IDENTITY)
	await _shot("shake")
	await _wait(0.4)
	_check("and comes to rest where it was", get_viewport().canvas_transform == Transform2D.IDENTITY)

	Fx.danger(true)
	await _wait(0.3)
	await _shot("danger")
	Fx.danger(false)
	await _wait(0.4)
	_check("the red edges go away", not Fx._danger.visible)

	Fx.confetti()
	await _wait(0.7)
	_check("confetti is in the air", Fx._paper.pieces.size() > 100, str(Fx._paper.pieces.size()))
	await _shot("confetti")

	Fx.fireworks(4, 1.0)
	await _wait(0.9)
	await _shot("fireworks")
	Fx.suit_fountain()
	await _wait(0.8)
	await _shot("suits")

	await _wait(4.5)
	_check("everything has cleared away", Fx._paper.pieces.is_empty() and Fx._glow.pieces.is_empty() and not Fx.is_processing(), "%d + %d left" % [Fx._paper.pieces.size(), Fx._glow.pieces.size()])

	Sound.music("menu")
	await _wait(Sound.MUSIC_FADE + 0.3)
	var music_bus := AudioServer.get_bus_index("Music")
	Sound.play("win")
	Sound.duck(1.0)
	Fx.victory(true)
	await _wait(0.6)
	_check("the music steps back for the fanfare", is_equal_approx(AudioServer.get_bus_volume_db(music_bus), Sound.DUCKED_DB), str(AudioServer.get_bus_volume_db(music_bus)))
	await _wait(1.0)
	await _shot("victory")
	await _wait(1.0)
	_check("and comes back afterwards", is_zero_approx(AudioServer.get_bus_volume_db(music_bus)), str(AudioServer.get_bus_volume_db(music_bus)))
	_check("the music switch is still on", Sound.music_on)

	# Rockets are still due at this point; clearing must cancel them too
	Fx.clear()
	await _wait(1.5)
	_check("clearing ends the show at once", Fx._paper.pieces.is_empty() and Fx._glow.pieces.is_empty(), "%d + %d left" % [Fx._paper.pieces.size(), Fx._glow.pieces.size()])

	# Wait for the last sounds to end: the engine reports streams still playing at exit as leaks
	Sound.music("")
	await _wait(4.0)
	print("\nfx preview: %d passed, %d failed, %d pictures in %s" % [_passed, _failed, _step, _shots])
	get_tree().quit(1 if _failed > 0 else 0)


# True if the named mixer bus carries sound at some point in the next `seconds`.
func _heard(bus_name: String, seconds: float) -> bool:
	var bus := AudioServer.get_bus_index(bus_name)
	var deadline := Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < deadline:
		if maxf(AudioServer.get_bus_peak_volume_left_db(bus, 0), AudioServer.get_bus_peak_volume_right_db(bus, 0)) > HEARD_DB:
			return true
		await get_tree().process_frame
	return false


func _shot(label: String) -> void:
	_step += 1
	if _shots.is_empty():
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
