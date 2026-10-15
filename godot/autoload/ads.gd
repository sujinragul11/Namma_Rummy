extends Node
## Full-screen ads (AdMob interstitials) in the phone app. This script is the only one that
## shows an ad, and it shows one at three moments of a game, never at any other:
##
##   TABLE        the player is about to sit down at a table: Play Now, a new table, a room
##                code, an invitation, Play again. The ad comes before the request goes to the
##                server (GameClient awaits before_table()), so no table, no turn clock and no
##                other player is waiting while it is on screen.
##   ROUND_BREAK  a round has ended (a declaration, or everybody else dropped) and another one
##                follows, as in Pool and Deals: the ad fills the countdown to the next deal.
##   GAME_OVER    the player leaves the result of a finished game.
##
## Also never during anyone's turn or the time to arrange cards after a declaration, never twice
## within min_gap_seconds, and only when an ad has already been downloaded: nobody waits for
## one to load. There are no ads on the PC or in the tests. A test build on a phone shows
## Google's test ads; a store build shows the game's own once Config.RELEASE_INTERSTITIAL_ID
## and the AdMob App ID (project.godot, admob/general/android/app_id) are filled in.

signal ad_opened(moment: String)
signal ad_closed(moment: String)

const TABLE := "table"
const ROUND_BREAK := "round_break"
const GAME_OVER := "game_over"

## Google's ad unit that always serves test ads. Test builds only.
const TEST_INTERSTITIAL_ID := "ca-app-pub-3940256099942544/1033173712"
## A downloaded ad is good for an hour; an older one is thrown away and a fresh one loaded.
const AD_SHELF_LIFE_MSEC := 50 * 60 * 1000
## After a failed download the next try waits a little longer each time.
const RETRY_SECONDS: Array[float] = [15.0, 30.0, 60.0, 120.0, 300.0]

## The least time between two ads.
var min_gap_seconds := 90.0
## A break between rounds gets an ad only while at least this much of it is still ahead. The
## break lasts 12 seconds; whatever the ad takes beyond it comes off the next round.
var round_break_min_seconds := 9.0
## The moments an ad was shown at, oldest first. For the tests.
var shown: Array[String] = []

var _backend: AdBackend = null  # null: no ads in this build
var _showing := ""  # the moment of the ad on screen; "" when there is none
var _last_shown_msec := -1
var _status_seen := ""  # the table's status at the previous update
var _in_foreground := true


func _ready() -> void:
	Game.state_changed.connect(_on_state_changed)
	_backend = _make_backend()
	if _backend != null:
		_backend.closed.connect(_on_closed)
		_backend.start()


func _notification(what: int) -> void:
	match what:
		NOTIFICATION_APPLICATION_FOCUS_OUT, NOTIFICATION_APPLICATION_PAUSED:
			_in_foreground = false
		NOTIFICATION_APPLICATION_FOCUS_IN, NOTIFICATION_APPLICATION_RESUMED:
			_in_foreground = true
			if not _showing.is_empty():
				# The ad reports its own closing; should that ever get lost, the game does not
				# stay waiting behind an ad that is no longer there
				var moment := _showing
				get_tree().create_timer(3.0).timeout.connect(func() -> void:
					if _showing == moment and _in_foreground:
						_on_closed())


## True when this build can show ads at all.
func available() -> bool:
	return _backend != null


## Before the player sits down at a table. Shows an ad if one is due and returns once it has
## gone; returns at once when none is due.
func before_table() -> void:
	if not _may_show(TABLE):
		return
	_show(TABLE)
	if not _showing.is_empty():
		await ad_closed


## Tests: show a stand-in for `seconds` instead of a real ad, on any platform.
func use_stand_in(seconds: float) -> void:
	_backend = StandIn.new(self, seconds)
	_backend.closed.connect(_on_closed)
	_backend.start()


## Some countries require a way to change the choice about personalised ads at any time. True
## when this player is in one of them; then Settings should offer show_privacy_options().
func privacy_options_required() -> bool:
	return _backend is AdMob and (_backend as AdMob).privacy_options_required()


func show_privacy_options() -> void:
	if _backend is AdMob:
		(_backend as AdMob).show_privacy_options()


func _make_backend() -> AdBackend:
	if OS.get_name() != "Android":
		return null  # the iPhone app is not built yet; on the PC there are no ads
	if not Engine.has_singleton("PoingGodotAdMob"):
		push_warning("Ads: the AdMob plugin is not in this build (Gradle build and the plugin must be enabled)")
		return null
	var unit_id := Config.RELEASE_INTERSTITIAL_ID if Config.store_build else TEST_INTERSTITIAL_ID
	if unit_id.is_empty():
		return null  # a store build without the game's own ad unit has no ads
	return AdMob.new(self, unit_id)


func _on_state_changed() -> void:
	var status := Game.status()
	var was := _status_seen
	_status_seen = status
	if status == was:
		return
	if was == "playing" and status == "round_over":
		var ahead := (Game.next_round_at - Time.get_ticks_msec()) / 1000.0
		if ahead >= round_break_min_seconds and _may_show(ROUND_BREAK):
			_show(ROUND_BREAK)
	elif was == "finished" and _may_show(GAME_OVER):
		_show(GAME_OVER)


func _may_show(_moment: String) -> bool:
	if _backend == null or not _showing.is_empty() or not _in_foreground:
		return false
	if _last_shown_msec >= 0 and Time.get_ticks_msec() - _last_shown_msec < min_gap_seconds * 1000.0:
		return false
	# Never while a turn or the time to arrange cards is running, nor during a search for players
	if Game.status() == "playing" or Game.searching():
		return false
	return _backend.ready_to_show()


func _show(moment: String) -> void:
	_showing = moment
	_last_shown_msec = Time.get_ticks_msec()
	shown.append(moment)
	ad_opened.emit(moment)
	_backend.show()


func _on_closed() -> void:
	if _showing.is_empty():
		return
	var moment := _showing
	_showing = ""
	ad_closed.emit(moment)


# ---------- where the ads come from ----------

## Shows one full-screen ad at a time and says when it has gone.
class AdBackend:
	extends RefCounted
	## The ad has gone: closed by the player, or it could not be shown at all.
	signal closed

	func start() -> void:
		pass

	func ready_to_show() -> bool:
		return false

	func show() -> void:
		closed.emit.call_deferred()


## Google's AdMob, through the Poing Studios plugin (addons/admob).
class AdMob:
	extends AdBackend

	var _host: Node
	var _unit_id: String
	var _ad: InterstitialAd = null
	var _loaded_at := 0
	var _loading := false
	var _failures := 0
	var _started := false

	func _init(host: Node, unit_id: String) -> void:
		_host = host
		_unit_id = unit_id

	# The consent message comes first: players in the EEA, the UK and Switzerland are asked once
	# about personalised ads, as Google requires. Everyone else goes straight on.
	func start() -> void:
		var request := ConsentRequestParameters.new()
		request.tag_for_under_age_of_consent = false
		UserMessagingPlatform.consent_information.update(request, _on_consent_info, _on_consent_error)

	func _on_consent_info() -> void:
		var info := UserMessagingPlatform.consent_information
		if info.get_is_consent_form_available() and info.get_consent_status() == ConsentInformation.ConsentStatus.REQUIRED:
			UserMessagingPlatform.load_consent_form(_on_consent_form, _on_consent_error)
		else:
			_initialize()

	func _on_consent_form(form: ConsentForm) -> void:
		form.show(func(_error: FormError) -> void: _initialize())

	func _on_consent_error(_error: FormError) -> void:
		_initialize()  # without an answer the SDK serves only the ads the law allows

	func _initialize() -> void:
		if _started:
			return
		_started = true
		var listener := OnInitializationCompleteListener.new()
		listener.on_initialization_complete = func(_status: InitializationStatus) -> void: _load()
		MobileAds.initialize(listener)

	func _load() -> void:
		if _loading or _ad != null:
			return
		_loading = true
		var callback := InterstitialAdLoadCallback.new()
		callback.on_ad_loaded = func(ad: InterstitialAd) -> void:
			_loading = false
			_failures = 0
			_ad = ad
			_loaded_at = Time.get_ticks_msec()
		callback.on_ad_failed_to_load = func(_error: LoadAdError) -> void:
			_loading = false
			var wait: float = RETRY_SECONDS[mini(_failures, RETRY_SECONDS.size() - 1)]
			_failures += 1
			_host.get_tree().create_timer(wait).timeout.connect(_load)
		InterstitialAdLoader.new().load(_unit_id, AdRequest.new(), callback)

	func ready_to_show() -> bool:
		if _ad != null and Time.get_ticks_msec() - _loaded_at > AD_SHELF_LIFE_MSEC:
			_ad.destroy()
			_ad = null
			_load()
		return _ad != null

	func show() -> void:
		var ad := _ad
		_ad = null
		if ad == null:
			closed.emit.call_deferred()
			return
		var done := [false]
		var finish := func() -> void:
			if done[0]:
				return
			done[0] = true
			ad.destroy()
			closed.emit()
			_load()  # the next one is ready long before it is needed
		var callback := FullScreenContentCallback.new()
		callback.on_ad_dismissed_full_screen_content = finish
		callback.on_ad_failed_to_show_full_screen_content = func(_error: AdError) -> void: finish.call()
		ad.full_screen_content_callback = callback
		ad.show()

	func privacy_options_required() -> bool:
		return UserMessagingPlatform.consent_information.get_privacy_options_requirement_status() == ConsentInformation.PrivacyOptionsRequirementStatus.REQUIRED

	func show_privacy_options() -> void:
		UserMessagingPlatform.show_privacy_options_form()


## For the tests: a dark cover over the whole screen that takes every touch, for a while.
class StandIn:
	extends AdBackend

	var _host: Node
	var _seconds: float

	func _init(host: Node, seconds: float) -> void:
		_host = host
		_seconds = seconds

	func ready_to_show() -> bool:
		return true

	func show() -> void:
		var layer := CanvasLayer.new()
		layer.name = "StandInAd"
		layer.layer = 100
		var cover := ColorRect.new()
		cover.color = Color(0, 0, 0, 0.85)
		cover.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		layer.add_child(cover)
		_host.add_child(layer)
		_host.get_tree().create_timer(_seconds).timeout.connect(func() -> void:
			layer.queue_free()
			closed.emit())
