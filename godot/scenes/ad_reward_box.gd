class_name AdRewardBox
extends MenuOverlay
## Free coins for watching ads. It opens from the Free Coins pill right of the Daily Bonus in the
## menu's top bar. The player watches a few short videos, one per tap on "Watch video", and
## then collects the coins of the reward; that can be done a few times a day.
##
## The server counts the videos and pays (see the free coins part of GameClient); Ads plays
## them and reports each one watched far enough. A video only ever plays after a tap here.
##
## Built in code, like Settings: a cream box with its title on a banner, a row with one tile
## per video and the coins they lead to, the button, and a line saying where things stand.

const BROWN := Color("5d4037")
const DIM := Color("8d6e63")
const LINE := Color("e0d3bd")
const WATCH_COLOR := Color("43a047")
const COLLECT_COLOR := Color("f57c00")
const SLOT_SIZE := Vector2(116, 92)

var _intro: Label
var _slots: HBoxContainer  # one VideoTile per video of a reward
var _prize: CoinLabel
var _action: Button
var _status: Label
var _action_color := Color.TRANSPARENT  # the colour the button was last tinted
var _video_on_screen := false  # a video the player asked for is playing
var _video_earned := false  # and it has been watched far enough
var _watched_shown := -1  # the videos the tiles showed as watched last time
var _sparkle_waiting := false  # a video counted while it was still on screen
var _message := ""  # what the server last refused, shown until the next tap


func _init() -> void:
	name = "AdRewardBox"
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP

	var shade := ColorRect.new()
	shade.name = "Shade"
	shade.color = Color(0, 0, 0, 0.72)
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(shade)

	var box := PanelContainer.new()
	box.name = "Box"
	box.anchor_left = 0.5
	box.anchor_right = 0.5
	box.anchor_top = 0.5
	box.anchor_bottom = 0.5
	box.offset_left = -330.0
	box.offset_right = 330.0
	box.grow_horizontal = Control.GROW_DIRECTION_BOTH
	box.grow_vertical = Control.GROW_DIRECTION_BOTH
	add_child(box)

	var column := VBoxContainer.new()
	column.name = "AdRewardColumn"
	column.add_theme_constant_override("separation", 14)
	box.add_child(column)

	# The header row MenuOverlay dresses: the title on a banner, a tag to close
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 0)
	var left := Control.new()
	left.custom_minimum_size = Vector2(56, 0)
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(left)
	var title := Label.new()
	title.name = "AdRewardTitle"
	title.text = "Free Coins"
	header.add_child(title)
	var right := Control.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(right)
	var close_button := Button.new()
	close_button.name = "AdRewardCloseButton"
	close_button.pressed.connect(close)
	header.add_child(close_button)
	column.add_child(header)

	_intro = Label.new()
	_intro.name = "AdRewardIntro"
	_intro.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_intro.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_intro.add_theme_font_size_override("font_size", 23)
	_intro.add_theme_color_override("font_color", BROWN)
	column.add_child(_intro)

	# The videos, then an arrow to the coins they are worth
	var row := HBoxContainer.new()
	row.name = "AdRewardRow"
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 14)
	_slots = HBoxContainer.new()
	_slots.name = "VideoTiles"
	_slots.add_theme_constant_override("separation", 12)
	row.add_child(_slots)
	var arrow := Label.new()
	arrow.text = "→"
	arrow.add_theme_font_size_override("font_size", 40)
	arrow.add_theme_color_override("font_color", DIM)
	row.add_child(arrow)
	_prize = CoinLabel.new()
	_prize.name = "AdRewardPrize"
	_prize.prefix = "+"
	_prize.font_size = 34
	_prize.text_color = COLLECT_COLOR.darkened(0.15)
	_prize.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(_prize)
	column.add_child(row)

	_action = Button.new()
	_action.name = "AdRewardButton"
	_action.custom_minimum_size = Vector2(360, 64)
	_action.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_action.focus_mode = Control.FOCUS_NONE
	_action.add_theme_font_size_override("font_size", 26)
	_action.pressed.connect(_on_action_pressed)
	column.add_child(_action)

	_status = Label.new()
	_status.name = "AdRewardStatus"
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.add_theme_font_size_override("font_size", 20)
	_status.add_theme_color_override("font_color", DIM)
	column.add_child(_status)


func _ready() -> void:
	super._ready()
	_action.add_theme_font_override("font", Ui.bold_font)
	Game.ad_reward_changed.connect(_show)
	Game.ad_reward_collected.connect(_on_collected)
	Game.ad_reward_failed.connect(_on_failed)
	Ads.ad_opened.connect(_on_ad_opened)
	Ads.ad_closed.connect(_on_ad_closed)
	Ads.reward_earned.connect(func() -> void: _video_earned = true)
	_show()


## Opens the box, and asks the server again: videos may have been watched on another phone.
func open() -> void:
	_message = ""
	_show()
	Game.fetch_ad_reward()
	super.open()


func _process(_delta: float) -> void:
	if visible:
		_show()  # a video finishing its download, the countdown to a new day


# Everything in the box from what the server last said and whether a video is ready.
func _show() -> void:
	var known := not Game.ad_reward.is_empty()
	var per_reward := int(Game.ad_reward.get("adsPerReward", 2))
	var watched := mini(int(Game.ad_reward.get("watched", 0)), per_reward)
	var reward := int(Game.ad_reward.get("reward", 0))

	_set_text(_intro, "Watch %d short videos, then collect %s coins!" % [per_reward, Ui.coins_text(reward)] if known
		else "Watch short videos and collect free coins!")
	_prize.visible = known
	if _prize.amount != reward:
		_prize.amount = reward
	_show_tiles(per_reward, watched if known else 0)

	var text := ""
	var color := WATCH_COLOR
	var enabled := false
	if not known:
		text = "Loading..."
	elif Game.ad_rewards_left() == 0:
		text = "Come back tomorrow"
	elif Game.ad_reward_ready():
		text = "Collecting..." if Game.ad_reward_collecting() else "Collect %s coins" % Ui.coins_text(reward)
		color = COLLECT_COLOR
		enabled = not Game.ad_reward_collecting()
	elif _video_on_screen:
		text = "Playing video..."
	elif Game.ad_reports_pending():
		# Another video now could be one more than the reward needs, watched for nothing
		text = "Counting video..."
	elif not Ads.rewarded_available():
		text = "Videos play in the phone app"
	elif not Ads.rewarded_ready():
		text = "Loading video..."
	else:
		text = "Watch video %d of %d" % [watched + 1, per_reward]
		enabled = true
	_set_text(_action, text)
	_action.disabled = not enabled
	if color != _action_color:
		_action_color = color
		Ui.tint_button(_action, color)

	var line := ""
	if not known:
		line = "Reconnecting..." if not Game.is_online() else ""
	elif not Game.is_online():
		line = "Reconnecting..."  # a video watched meanwhile counts once the line is back
	elif not _message.is_empty():
		line = _message
	elif Game.ad_rewards_left() == 0:
		line = "That's all the free coins for today. New videos in %s" % GameClient.countdown_text(Game.ad_reward_wait())
	else:
		line = "Free coins left today: %d of %d" % [Game.ad_rewards_left(), int(Game.ad_reward.get("dailyLimit", 0))]
	_set_text(_status, line)


# One tile per video: ticked once watched, the next one to watch edged in gold.
func _show_tiles(count: int, watched: int) -> void:
	while _slots.get_child_count() < count:
		var tile := VideoTile.new()
		tile.name = "VideoTile%d" % (_slots.get_child_count() + 1)
		tile.custom_minimum_size = SLOT_SIZE
		_slots.add_child(tile)
	while _slots.get_child_count() > count:
		var extra := _slots.get_child(_slots.get_child_count() - 1)
		_slots.remove_child(extra)
		extra.queue_free()
	for index in count:
		var tile := _slots.get_child(index) as VideoTile
		tile.set_state(index + 1, index < watched, index == watched and Game.ad_rewards_left() > 0)
	# A video just counted: its tile lights up once the video is off the screen
	if _watched_shown >= 0 and watched > _watched_shown:
		_sparkle_waiting = true
	_watched_shown = watched
	if _sparkle_waiting and not _video_on_screen and watched > 0 and visible:
		_sparkle_waiting = false
		var tile := _slots.get_child(watched - 1) as Control
		Sound.play("sparkle")
		Fx.sparkle(tile.get_global_rect().get_center(), Fx.GOLD, 16)
		Ui.pulse(tile)


func _set_text(control: Control, text: String) -> void:
	if control.get("text") != text:
		control.set("text", text)


func _on_action_pressed() -> void:
	_message = ""
	if Game.ad_reward_ready():
		Game.collect_ad_reward()
	elif not Ads.show_rewarded():
		Ui.pulse(_status)  # the button says why not; let the line under it be seen as well
	_show()


func _on_ad_opened(moment: String) -> void:
	if moment == Ads.REWARD:
		_video_on_screen = true
		_video_earned = false


func _on_ad_closed(moment: String) -> void:
	if moment != Ads.REWARD:
		return
	_video_on_screen = false
	if not _video_earned:
		_message = "Watch the whole video to make it count."
	_show()


func _on_collected(prize: int) -> void:
	_message = ""
	var at := _prize.get_global_rect().get_center()
	Sound.play("win")
	Fx.sparkle(at, Fx.GOLD, 26)
	Fx.float_text(at - Vector2(0.0, 60.0), "+%s" % Ui.coins_text(prize), Fx.GOLD, 48)
	Input.vibrate_handheld(120)
	_show()
	Ui.pulse(_status)


func _on_failed(message: String) -> void:
	_message = message
	_show()
	Ui.pulse(_status)


## One video of a reward: a play sign while it waits, a tick once watched. Drawn in code.
class VideoTile:
	extends Control

	var _number := 0
	var _watched := false
	var _next := false

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func set_state(number: int, watched: bool, next: bool) -> void:
		if number == _number and watched == _watched and next == _next:
			return
		_number = number
		_watched = watched
		_next = next
		queue_redraw()

	func _draw() -> void:
		var style := Ui.box(WATCH_COLOR if _watched else Color.WHITE, 14, 0, 0)
		style.border_color = Ui.GOLD if _next else (WATCH_COLOR.darkened(0.2) if _watched else LINE)
		style.set_border_width_all(4 if _next else 2)
		style.shadow_color = Color(0, 0, 0, 0.18)
		style.shadow_size = 3
		draw_style_box(style, Rect2(Vector2.ZERO, size))
		var center := Vector2(size.x / 2.0, size.y / 2.0 - 10.0)
		if _watched:
			draw_polyline(PackedVector2Array([center + Vector2(-16, 0), center + Vector2(-4, 12), center + Vector2(18, -12)]), Color.WHITE, 7.0, true)
		else:
			draw_circle(center, 22.0, Ui.RED, true, -1.0, true)
			draw_colored_polygon(PackedVector2Array([center + Vector2(-7, -11), center + Vector2(-7, 11), center + Vector2(12, 0)]), Color.WHITE)
		var font := Ui.bold_font
		var label := "Watched" if _watched else "Video %d" % _number
		draw_string(font, Vector2(0, size.y - 12.0), label, HORIZONTAL_ALIGNMENT_CENTER, size.x, 18, Color.WHITE if _watched else BROWN)
