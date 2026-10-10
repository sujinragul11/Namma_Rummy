extends Node
## Settings kept between runs: the server address and the saved login.
##
## To play two players on one PC, start a second copy with its own profile so each keeps
## its own login:  godot --path . --profile=two
## `--server=http://192.168.1.5:3001` uses another server for that run without saving it.
## `--side=left` / `--side=right` makes the window fill that half of the screen.
## `--store-build` shows the game the way the app stores get it (see `store_build`).
## `--mute` keeps this run silent.
## All options are also accepted after the `--` separator.

## The public game server the app store builds play on. It must start with https://.
## The release build scripts refuse to build while this is empty.
const RELEASE_SERVER_URL := ""
const DEFAULT_SERVER_URL := "http://127.0.0.1:3001"
## Where a test build on a phone looks first. On a phone 127.0.0.1 is the phone itself, so
## the default there is the address a Windows PC always has on its own Mobile hotspot.
const PHONE_TEST_SERVER_URL := "http://192.168.137.1:3001"

var profile := "default"
var server_url := DEFAULT_SERVER_URL
## True in the builds made for the app stores: they play on RELEASE_SERVER_URL only and
## show no developer options.
var store_build := OS.has_feature("release")
## The player's sound switches; change them through the Sound autoload.
var music_on := true
var sound_on := true
## Silent for this run only (`--mute`); the saved switches stay as they are.
var muted := false

var _file := ConfigFile.new()


func _ready() -> void:
	var server_for_this_run := ""
	for argument in OS.get_cmdline_args() + OS.get_cmdline_user_args():
		if argument.begins_with("--profile="):
			profile = argument.trim_prefix("--profile=")
		elif argument.begins_with("--server="):
			server_for_this_run = argument.trim_prefix("--server=")
		elif argument.begins_with("--side="):
			_fill_half_of_screen(argument.trim_prefix("--side=") == "right")
		elif argument == "--store-build":
			store_build = true
		elif argument == "--mute":
			muted = true

	_file.load(_path())  # no file yet just means this is the first run
	music_on = _file.get_value("sound", "music", true)
	sound_on = _file.get_value("sound", "effects", true)
	if store_build:
		server_url = RELEASE_SERVER_URL
	else:
		server_url = _file.get_value("server", "url", default_server_url())
		if OS.has_feature("mobile") and server_url == DEFAULT_SERVER_URL:
			server_url = default_server_url()  # "this device" is never the server on a phone
	if not server_for_this_run.is_empty():
		server_url = clean_server_url(server_for_this_run)


func set_server_url(url: String) -> void:
	server_url = clean_server_url(url)
	_file.set_value("server", "url", server_url)
	_file.save(_path())


## The server a test build uses until another address is typed in.
func default_server_url() -> String:
	return PHONE_TEST_SERVER_URL if OS.has_feature("mobile") else DEFAULT_SERVER_URL


## Accepts what people type: "192.168.1.5:3001", with or without http://, with a trailing slash.
func clean_server_url(url: String) -> String:
	var clean := url.strip_edges().trim_suffix("/")
	if clean.is_empty():
		return default_server_url()
	if not clean.begins_with("http://") and not clean.begins_with("https://"):
		clean = "http://" + clean
	return clean


func save_sound(music: bool, effects: bool) -> void:
	music_on = music
	sound_on = effects
	_file.set_value("sound", "music", music)
	_file.set_value("sound", "effects", effects)
	_file.save(_path())


func save_login(token: String, user: Dictionary) -> void:
	_file.set_value("login", "token", token)
	_file.set_value("login", "user", user)
	_file.save(_path())


## Returns {"token": ..., "user": ...}, or an empty Dictionary when nobody is logged in.
func load_login() -> Dictionary:
	var token: String = _file.get_value("login", "token", "")
	if token.is_empty():
		return {}
	return {"token": token, "user": _file.get_value("login", "user", {})}


func clear_login() -> void:
	if _file.has_section("login"):
		_file.erase_section("login")
		_file.save(_path())


func _path() -> String:
	return "user://settings_%s.cfg" % profile


# Two players on one PC: each window takes one half of the screen, at the game's 16:9 shape.
func _fill_half_of_screen(right_half: bool) -> void:
	var window := get_window()
	var screen := DisplayServer.screen_get_usable_rect(window.current_screen)
	var margin := 12
	var width := screen.size.x / 2 - margin * 2
	var height := mini(width * 9 / 16, screen.size.y - 120)
	window.size = Vector2i(width, height)
	var left := screen.position.x + margin + (screen.size.x / 2 if right_half else 0)
	window.position = Vector2i(left, screen.position.y + 80)
