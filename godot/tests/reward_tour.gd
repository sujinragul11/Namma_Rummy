extends Control
## Free coins for watching ads through the real home screen, played with a finger like
## bonus_tour: the pill right of the Daily Bonus, the box, a video per tap (a stand-in for
## AdMob's), the server counting each one, the coins collected once, a video closed early, no
## full-screen ad straight after a video, another phone on the same account, the day's limit
## and the videos coming back when the day turns.
##
## Run against a TEST server whose day lasts a minute instead of 24 hours (it registers
## throwaway accounts):
##   set AD_REWARD_DAY_SECONDS=60
##   node tests/test_server.js --fresh --port=3191 --db=My_Rummy_reward_test
##   godot --path . res://tests/reward_tour.tscn -- --profile=rewardtour --server=http://127.0.0.1:3191 --shots=<folder>
## With --headless every check runs and no pictures are taken. It takes about two minutes:
## it starts right after the day has turned, so that it does not turn halfway through.

const VIDEO_SECONDS := 0.8

var _shots := ""
var _main: Control
var _step := 0
var _passed := 0
var _failed := 0


func _ready() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--shots="):
			_shots = argument.trim_prefix("--shots=")
	if not _shots.is_empty():
		DirAccess.make_dir_recursive_absolute(_shots)
	Sound.sound_on = false
	Game.logout()  # start from the login form even if this profile has a saved login
	_main = (load("res://scenes/main.tscn") as PackedScene).instantiate() as Control
	add_child(_main)
	_run()


func _run() -> void:
	var tag := "%d%04d" % [int(Time.get_unix_time_from_system()) % 1000000, randi() % 10000]
	var name_a := "rt_" + tag
	await _wait(0.5)
	var r: Dictionary = await Game.register(name_a, "9" + tag.substr(0, 9), "secret12")
	_check("registered and connected", r.ok and await _until(func() -> bool: return Game.is_online() and _node("MenuPanel") != null and _node("MenuPanel").visible), str(r.get("error", "")))

	# ---------- what the server says ----------
	_check("the app asks the server about free coins on connecting", await _until(func() -> bool: return not Game.ad_reward.is_empty()))
	_check("a new player: 2 videos for 1,000 coins, 5 times a day", Game.ads_to_watch() == 2 and Game.ad_rewards_left() == 5 and int(Game.ad_reward.get("reward", 0)) == 1000 and not Game.ad_reward_ready(), str(Game.ad_reward))
	_check("this server's day lasts a minute (AD_REWARD_DAY_SECONDS=60)", Game.ad_reward_wait() > 0 and Game.ad_reward_wait() <= 60000, str(Game.ad_reward_wait()))
	if Game.ad_reward_wait() < 45000:
		await _wait(Game.ad_reward_wait() / 1000.0)
		_check("the app hears by itself that a new day has begun", await _until(func() -> bool: return Game.ad_reward_wait() > 45000, 8.0), str(Game.ad_reward_wait()))

	# ---------- the pill in the top bar ----------
	var home: Variant = _screen()  # untyped: the tour looks inside the home script
	var pill: Button = _node("FreeCoinsButton")
	_check("the Free Coins pill sits right of the Daily Bonus", pill != null and pill.is_visible_in_tree() and pill.get_index() == _node("BonusButton").get_index() + 1)
	_check("the top bar still fits: the pill ends before the help button", pill.get_global_rect().end.x < _node("HelpButton").get_global_rect().position.x and pill.get_global_rect().position.y >= 0.0, "%s / %s" % [pill.get_global_rect(), _node("HelpButton").get_global_rect()])
	_check("it is not dressed for collecting", not home._free_coins_ready_shown)
	_check("nothing opens by itself", not _box().visible)
	await _shot("menu")

	# ---------- the box, on a PC without videos ----------
	_check("this PC has no videos of its own", not Ads.rewarded_available())
	await _press("FreeCoinsButton")
	_check("the pill opens the box", await _until(func() -> bool: return _box().visible, 2.0))
	await _wait(0.5)
	var button: Button = _node("AdRewardButton")
	var status: Label = _node("AdRewardStatus")
	_check("the box fits on the screen", _box_rect().position.y >= 0.0 and _box_rect().end.y <= get_viewport().get_visible_rect().size.y, str(_box_rect()))
	_check("it says what the videos are worth", _node("AdRewardIntro").text == "Watch 2 short videos, then collect 1,000 coins!", _node("AdRewardIntro").text)
	_check("one tile per video", _node("VideoTiles").get_child_count() == 2)
	_check("without videos the button says so and cannot be pressed", button.text == "Videos play in the phone app" and button.disabled, button.text)
	_check("the line counts the rewards left today", status.text == "Free coins left today: 5 of 5", status.text)
	await _shot("box-no-videos")

	# ---------- watching ----------
	Ads.use_reward_stand_in(VIDEO_SECONDS)
	_check("with a video ready the button offers it", await _until(func() -> bool: return button.text == "Watch video 1 of 2" and not button.disabled, 2.0), button.text)
	var tile_1: Variant = _node("VideoTile1")
	var tile_2: Variant = _node("VideoTile2")
	_check("the first tile is the next to watch", not tile_1._watched and tile_1._next and not tile_2._next)
	var before := Game.coins
	await _press("AdRewardButton")
	_check("a tap plays the video over everything", get_tree().root.find_child("StandInAd", true, false) != null and Ads.shown[-1] == Ads.REWARD)
	_check("while it plays the button waits", button.text == "Playing video..." and button.disabled, button.text)
	await _shot("video-playing")
	_check("the video counts on the server once watched", await _until(func() -> bool: return int(Game.ad_reward.get("watched", 0)) == 1, 5.0), str(Game.ad_reward))
	_check("then the first tile is ticked and the button offers the second", await _until(func() -> bool: return button.text == "Watch video 2 of 2", 3.0) and tile_1._watched and not tile_2._watched and tile_2._next, button.text)
	_check("no coins yet", Game.coins == before)
	await _shot("box-one-watched")
	await _press("AdRewardButton")
	_check("the second video counts", await _until(func() -> bool: return int(Game.ad_reward.get("watched", 0)) == 2, 5.0))
	_check("the button turns to collecting", await _until(func() -> bool: return button.text == "Collect 1,000 coins" and not button.disabled, 3.0), button.text)
	_check("the pill is dressed for collecting", await _until(func() -> bool: return home._free_coins_ready_shown, 2.0))
	await _shot("box-collect")

	# ---------- no full-screen ad straight after a video ----------
	Ads.use_stand_in(0.3)
	await Ads.before_table()
	_check("sitting down right after a video shows no full-screen ad", Ads.shown.count(Ads.TABLE) == 0 and Ads.shown[-1] == Ads.REWARD, str(Ads.shown))

	# ---------- collecting ----------
	await _press("AdRewardButton")
	_check("the server pays 1,000 coins", await _until(func() -> bool: return Game.coins == before + 1000, 4.0), "%d -> %d" % [before, Game.coins])
	_check("the top bar shows the new balance", await _until(func() -> bool: return _node("CoinsLabel")._label.text == Ui.coins_text(before + 1000), 2.0), _node("CoinsLabel")._label.text)
	_check("the tiles start again with 4 rewards left", await _until(func() -> bool: return Game.ads_to_watch() == 2 and status.text == "Free coins left today: 4 of 5" and button.text == "Watch video 1 of 2" and not tile_1._watched, 3.0), "%s / %s" % [status.text, button.text])
	_check("the pill is back to watching", await _until(func() -> bool: return not home._free_coins_ready_shown, 2.0))
	await _shot("box-collected")

	# ---------- a video closed early ----------
	Ads.use_reward_stand_in(0.4, false)
	await _press("AdRewardButton")
	_check("a video closed before its end says so", await _until(func() -> bool: return status.text == "Watch the whole video to make it count.", 3.0), status.text)
	await _wait(0.5)
	_check("and counts nothing", int(Game.ad_reward.get("watched", 0)) == 0 and not tile_1._watched)
	Ads.use_reward_stand_in(0.3)

	# ---------- another phone, same account ----------
	var phone := GameClient.new()
	phone.remember_login = false
	add_child(phone)
	var refused := [""]
	phone.ad_reward_failed.connect(func(message: String) -> void: refused[0] = message)
	r = await phone.login(name_a, "secret12")
	_check("another phone logs in and finds 4 rewards left", r.ok and await _until(func() -> bool: return phone.is_online() and phone.ad_rewards_left() == 4), str(phone.ad_reward))
	phone.report_ad_watched()
	_check("a video watched on the other phone ticks the tile here", await _until(func() -> bool: return int(Game.ad_reward.get("watched", 0)) == 1, 4.0) and await _until(func() -> bool: return tile_1._watched and button.text == "Watch video 2 of 2", 2.0), button.text)

	# ---------- the day's limit ----------
	for reward in range(2, 6):
		while not Game.ad_reward_ready():
			var watched := int(Game.ad_reward.get("watched", 0))
			if not await _until(func() -> bool: return button.text.begins_with("Watch video") and not button.disabled, 4.0):
				_check("reward %d: a video is offered" % reward, false, button.text)
				break
			await _press("AdRewardButton")
			# Until the server has counted it the button offers nothing, so no extra video
			# is watched for nothing
			_check("reward %d: the button waits for the server" % reward, await _until(func() -> bool: return button.text in ["Playing video...", "Counting video..."] and button.disabled, 1.0), button.text)
			if not await _until(func() -> bool: return int(Game.ad_reward.get("watched", 0)) == watched + 1, 5.0):
				_check("reward %d: the video counts" % reward, false, str(Game.ad_reward))
				break
		_check("reward %d: the videos fill it" % reward, await _until(func() -> bool: return button.text == "Collect 1,000 coins" and not button.disabled, 4.0), "%s / %s" % [Game.ad_reward, button.text])
		await _press("AdRewardButton")
		_check("reward %d is paid" % reward, await _until(func() -> bool: return Game.ad_rewards_left() == 5 - reward, 4.0), str(Game.ad_reward))
	_check("five rewards in a day paid 5,000 coins", Game.coins == before + 5000 and phone.coins == Game.coins, "%d -> %d (other phone %d)" % [before, Game.coins, phone.coins])
	_check("then the button says to come back tomorrow", await _until(func() -> bool: return button.text == "Come back tomorrow" and button.disabled, 2.0), button.text)
	_check("and the line counts down to new videos", status.text.begins_with("That's all the free coins for today. New videos in 00:00:"), status.text)
	_check("no tile waits to be watched", not tile_1._next and not tile_2._next)
	await _shot("box-day-done")
	phone.report_ad_watched()
	_check("a video reported now is refused by the server", await _until(func() -> bool: return refused[0].contains("all the free coins for today"), 4.0), refused[0])
	_check("with nothing counted", int(Game.ad_reward.get("watched", 0)) == 0 and Game.coins == before + 5000)
	await _press("AdRewardCloseButton")
	_check("the close tag closes the box", await _until(func() -> bool: return not _box().visible, 2.0))
	await _shot("menu-day-done")

	# ---------- a new day ----------
	_check("the videos come back by themselves when the day turns", await _until(func() -> bool: return Game.ad_rewards_left() == 5, Game.ad_reward_wait() / 1000.0 + 8.0), str(Game.ad_reward))
	_check("on both phones", await _until(func() -> bool: return phone.ad_rewards_left() == 5, 8.0), str(phone.ad_reward))
	await _press("FreeCoinsButton")
	_check("the box offers a video again", await _until(func() -> bool: return button.text == "Watch video 1 of 2" and status.text == "Free coins left today: 5 of 5", 3.0), "%s / %s" % [button.text, status.text])
	await _shot("box-new-day")
	_go_back()
	_check("the back button closes it", await _until(func() -> bool: return not _box().visible, 2.0))

	# ---------- logging out ----------
	phone.logout()
	Game.logout()
	_check("logging out forgets the free coins", Game.ad_reward.is_empty() and Game.ad_reward_resets_at == 0)

	print("\nreward tour: %d passed, %d failed" % [_passed, _failed])
	Sound.hush()
	get_tree().quit(1 if _failed > 0 or _passed == 0 else 0)


func _box() -> Control:
	return _node("AdRewardBox")


func _box_rect() -> Rect2:
	return (_box().get_node("Box") as Control).get_global_rect()


func _node(node_name: String) -> Variant:
	return _main.find_child(node_name, true, false)


func _screen() -> Control:
	var holder := _main.get_node("%Screen")
	return holder.get_child(holder.get_child_count() - 1)


# ---------- a finger (as in ui_tour) ----------

func _to_window(at: Vector2) -> Vector2:
	return get_viewport().get_final_transform() * at


func _touch(at: Vector2, down: bool) -> void:
	var event := InputEventScreenTouch.new()
	event.index = 0
	event.pressed = down
	event.position = _to_window(at)
	Input.parse_input_event(event)
	Input.flush_buffered_events()


func _tap(at: Vector2) -> void:
	_touch(at, true)
	_touch(at, false)


func _under_finger() -> String:
	var hit := get_viewport().gui_get_hovered_control()
	return "the finger was on nothing" if hit == null else "the finger was on %s" % hit.get_path()


func _middle(control: Control) -> Vector2:
	return control.get_global_transform_with_canvas() * (control.size / 2.0)


## Taps a button. A button a finger cannot reach fails the tour.
func _press(button_name: String) -> void:
	var button := _node(button_name) as BaseButton
	if button == null or not button.is_visible_in_tree():
		_check("%s can be pressed" % button_name, false)
		return
	var answered := [false]
	var on_pressed := func() -> void: answered[0] = true
	button.pressed.connect(on_pressed)
	var at := _middle(button)
	_tap(at)
	if is_instance_valid(button) and button.pressed.is_connected(on_pressed):
		button.pressed.disconnect(on_pressed)
	_check("%s answers a finger" % button_name, answered[0] or button.disabled, "touched %s; %s" % [at, _under_finger()])
	await get_tree().process_frame


func _go_back() -> void:
	get_tree().root.propagate_notification(NOTIFICATION_WM_GO_BACK_REQUEST)


func _shot(label: String) -> void:
	_step += 1
	if DisplayServer.get_name() == "headless" or _shots.is_empty():
		return
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("%s/%02d-%s.png" % [_shots, _step, label])


func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout


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
