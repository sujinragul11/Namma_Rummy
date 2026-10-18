extends Node
## A login lasts until the player logs out. It must survive days away, a restart of the app
## and of the server, and a server that cannot check logins for a while; it must end when the
## player logs out, when the server ends it for the account's safety, and with the account.
##
## Like server_restart, this test starts and stops its own server (tests/test_server.js, so
## `node` must be on the PATH), on a port and a database nothing else uses:
##   godot --headless --path . res://tests/session_e2e.tscn -- --port=3141 --db=My_Rummy_session_test
## The database is dropped and created again at the start. `--server-script=<path>` runs
## another copy of test_server.js, with the backend two folders up from it.

const START_SECONDS := 25.0
const HELPER := "user://session_e2e_helper.js"
const OUTAGE_FLAG := "user://session_e2e_outage.flag"
const PASSWORD := "secret12"

# What the test asks of the database and the backend, through node
const HELPER_SOURCE := """
const crypto = require('crypto');
const { execFileSync } = require('child_process');
const [command, backend, database, value, extra] = process.argv.slice(2);
process.chdir(backend);
process.env.DB_NAME = database;
const db = require(backend + '/src/database/db');

const commands = {
  // Makes every login of the user 400 days old, as if it had been made then
  age: async () => {
    const result = await db.query(
      `UPDATE user_sessions SET created_at = now() - interval '400 days', last_used_at = now() - interval '400 days'
       WHERE user_id = $1`, [value]);
    return result.rowCount;
  },
  // How many seconds ago the user's logins were last used
  'last-used': async () => {
    const result = await db.query(
      `SELECT EXTRACT(EPOCH FROM now() - max(last_used_at))::int AS age FROM user_sessions WHERE user_id = $1`, [value]);
    return result.rows[0].age;
  },
  // Rows holding the token as it is / its SHA-256 hash
  stored: async () => {
    const hash = crypto.createHash('sha256').update(value).digest('hex');
    const plain = await db.query(`SELECT 1 FROM user_sessions WHERE token_hash = $1`, [value]);
    const hashed = await db.query(`SELECT 1 FROM user_sessions WHERE token_hash = $1`, [hash]);
    return `${plain.rowCount}/${hashed.rowCount}`;
  },
  // A token of the kind the server gave before logins were kept: it runs out after `extra` seconds
  'old-token': async () => {
    const jwt = require(backend + '/node_modules/jsonwebtoken');
    const config = require(backend + '/src/config');
    return jwt.sign({ id: Number(value) }, config.jwtSecret, { expiresIn: Number(extra) });
  },
  // The real script, as someone looking after the server would run it
  revoke: async () =>
    execFileSync(process.execPath, ['src/database/revoke-logins.js', value], { encoding: 'utf8' }).trim(),
};

commands[command]()
  .then((answer) => console.log(String(answer)))
  .catch((error) => console.log('ERROR ' + error.message))
  .finally(() => db.pool.end());
"""

var _port := 3141
var _database := "My_Rummy_session_test"
var _server_script := ""
var _server_pid := -1
var _passed := 0
var _failed := 0


func _ready() -> void:
	_server_script = ProjectSettings.globalize_path("res://tests/test_server.js")
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--port="):
			_port = int(argument.trim_prefix("--port="))
		elif argument.begins_with("--db="):
			_database = argument.trim_prefix("--db=")
		elif argument.begins_with("--server-script="):
			_server_script = argument.trim_prefix("--server-script=")
	_run()


func _exit_tree() -> void:
	_stop_server()  # never leave it running, whatever happened
	_set_outage(false)


func _run() -> void:
	if await _server_answers():
		print("Something already answers on port %d. Stop it, or pass another --port." % _port)
		get_tree().quit(1)
		return
	FileAccess.open(HELPER, FileAccess.WRITE).store_string(HELPER_SOURCE)
	_set_outage(false)
	OS.set_environment("LOGIN_CHECK_SECONDS", "1")  # how often the server looks at open connections
	_start_server(["--fresh"])
	if not await _wait_for_server():
		print("The test server did not start. Is `node` on the PATH and PostgreSQL running?")
		_finish()
		return

	var tag := "%d%04d" % [int(Time.get_unix_time_from_system()) % 1000000, randi() % 10000]
	var number := randi() % 100000000
	var name_a := "sa_" + tag
	var name_b := "sb_" + tag

	# ---------- a login is a key the server keeps, not a token with a date in it ----------
	var a := _new_client()
	var r: Dictionary = await a.register(name_a, "98%08d" % number, PASSWORD)
	_check("A registers", r.ok, str(r.get("error", "")))
	_check("A is connected", await _until(a.is_online))
	_check("the token is a random key with nothing to run out in it", a.token.length() >= 40 and not a.token.contains("."), a.token)
	var stored := _helper(["stored", a.token])
	_check("the server keeps only a hash of it", stored == "0/1", stored)

	# ---------- coming back much later, after the app was closed ----------
	var aged := _helper(["age", a.player_id])
	_check("A's login is made 400 days old", aged == "1", aged)
	var later := _new_client()
	later._set_login(a.token, a.user)  # what the app does with the saved login when it starts
	_check("a 400-day-old login still connects", await _until(later.is_online))
	r = await later.fetch_profile()
	_check("and its requests are answered", r.ok and later.is_logged_in(), str(r.get("error", "")))
	var used := _helper(["last-used", a.player_id])
	_check("the server notes that it was used again", used.is_valid_int() and int(used) < 120, used)

	# ---------- the server restarts ----------
	_stop_server()
	_check("A is offline while the server is down", await _until(func() -> bool: return not a.is_online()))
	_start_server([])
	_check("the server starts again", await _wait_for_server())
	_check("A connects again by itself, still logged in", await _until(a.is_online, 15.0) and a.is_logged_in())

	# ---------- the server cannot check logins for a while ----------
	_set_outage(true)
	var patient := _new_client()
	var patient_notices := _notices(patient)
	patient._set_login(a.token, a.user)
	await _wait(3.0)
	_check("while logins cannot be checked, the app is not let in", not patient.is_online())
	_check("but it stays logged in and says nothing about the login", patient.is_logged_in() and patient_notices.is_empty(), str(patient_notices))
	r = await patient.fetch_profile()
	_check("a request is answered 'busy', and the app stays logged in", not r.ok and patient.is_logged_in(), str(r.get("error", "")))
	_set_outage(false)
	_check("once logins can be checked again, the app connects by itself", await _until(patient.is_online, 8.0))

	# ---------- logging out ----------
	var b := _new_client()
	r = await b.register(name_b, "88%08d" % number, PASSWORD)
	_check("B registers", r.ok, str(r.get("error", "")))
	var b_phone := _new_client()
	r = await b_phone.login(name_b, PASSWORD)
	_check("B logs in on a second phone too", r.ok and await _until(func() -> bool: return b.is_online() and b_phone.is_online()))
	var b_twin := _new_client()  # the second phone's login, connected twice
	var twin_notices := _notices(b_twin)
	b_twin._set_login(b_phone.token, b_phone.user)
	_check("the same login can be connected twice", await _until(b_twin.is_online))
	var logged_out := b_phone.token
	b_phone.logout()
	_check("logging out forgets the login on that phone", not b_phone.is_logged_in() and Array(b_phone.token.to_ascii_buffer()).is_empty())
	_check("the server closes the other connection of that login, which is logged out", await _until(func() -> bool: return not b_twin.is_logged_in(), 8.0))
	_check("and told so", twin_notices == [GameClient.LOGIN_ENDED_MESSAGE], str(twin_notices))
	var answer: Array = await _profile_with(logged_out)
	_check("a request with the logged-out token is refused as an ended login", answer[0] == 401 and answer[1].get("code") == GameClient.LOGIN_ENDED_CODE, str(answer))
	var returned := _new_client()
	returned._set_login(logged_out, b.user)
	_check("so is a connection with it", await _until(func() -> bool: return not returned.is_logged_in()))
	r = await b.fetch_profile()
	_check("B's first phone is still logged in", r.ok and b.is_logged_in() and b.is_online(), str(r.get("error", "")))

	# ---------- tokens from the version before ----------
	var old_token := _helper(["old-token", b.player_id, "3600"])
	var old_app := _new_client()
	old_app._set_login(old_token, b.user)
	_check("a 24-hour token from before still works until it runs out", old_token.count(".") == 2 and await _until(old_app.is_online), old_token)
	var expired := _new_client()
	expired._set_login(_helper(["old-token", b.player_id, "-10"]), b.user)
	_check("one that has run out is refused", await _until(func() -> bool: return not expired.is_logged_in()))
	old_app.logout()

	# ---------- ending an account's logins for its safety ----------
	var a_phone := _new_client()
	r = await a_phone.login(name_a, PASSWORD)
	_check("A logs in on a second phone", r.ok and await _until(a_phone.is_online))
	var a_notices := _notices(a)
	var revoked_token := a.token
	var revoked := _helper(["revoke", name_a])
	_check("revoke-logins ends both of A's logins", revoked.begins_with("Ended 2 login(s) of " + name_a), revoked)
	var everyone_out := func() -> bool:
		return not (a.is_logged_in() or later.is_logged_in() or patient.is_logged_in() or a_phone.is_logged_in())
	_check("every phone of A is logged out within seconds", await _until(everyone_out, 8.0))
	_check("and told to log in again", a_notices.size() == 1 and str(a_notices[0]).ends_with("Please log in again."), str(a_notices))
	answer = await _profile_with(revoked_token)
	_check("a request with that token is told why", answer[0] == 401 and str(answer[1].get("error", "")).contains("keep your account safe"), str(answer))
	_check("B is not affected", b.is_logged_in() and b.is_online())
	r = await a.login(name_a, PASSWORD)
	_check("A can log in again with the password", r.ok and await _until(a.is_online), str(r.get("error", "")))

	# ---------- deleting the account ----------
	var deleted_token := b.token
	r = await b.delete_account(PASSWORD)
	_check("B deletes the account", r.ok and not b.is_logged_in(), str(r.get("error", "")))
	answer = await _profile_with(deleted_token)
	_check("its logins went with it", answer[0] == 401 and answer[1].get("code") == GameClient.LOGIN_ENDED_CODE, str(answer))

	_finish()


func _finish() -> void:
	_stop_server()
	print("session_e2e: %d passed, %d failed" % [_passed, _failed])
	get_tree().quit(1 if _failed > 0 else 0)


# ---------- the server ----------

func _url() -> String:
	return "http://127.0.0.1:%d" % _port


func _start_server(options: Array) -> void:
	var arguments := PackedStringArray([_server_script, "--port=%d" % _port, "--db=%s" % _database])
	arguments.append("--outage-flag=" + ProjectSettings.globalize_path(OUTAGE_FLAG))
	arguments.append_array(PackedStringArray(options))
	_server_pid = OS.create_process("node", arguments)


func _stop_server() -> void:
	if _server_pid > 0:
		OS.kill(_server_pid)
		_server_pid = -1


func _server_answers() -> bool:
	var http := HTTPRequest.new()
	http.timeout = 2.0
	add_child(http)
	var answered := false
	if http.request(_url() + "/health") == OK:
		var result: Array = await http.request_completed
		answered = result[0] == HTTPRequest.RESULT_SUCCESS and result[1] == 200
	http.queue_free()
	return answered


func _wait_for_server() -> bool:
	var deadline := Time.get_ticks_msec() + int(START_SECONDS * 1000.0)
	while Time.get_ticks_msec() < deadline:
		if await _server_answers():
			return true
		await _wait(0.3)
	return false


# While the flag file exists the server cannot check logins (see test_server.js).
func _set_outage(on: bool) -> void:
	var path := ProjectSettings.globalize_path(OUTAGE_FLAG)
	if on:
		FileAccess.open(path, FileAccess.WRITE).store_string("down")
	elif FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)


# Runs one of the helper's commands and returns its answer: the last line it printed (the
# database module says hello first).
func _helper(arguments: Array) -> String:
	var backend := _server_script.get_base_dir().path_join("../../backend").simplify_path()
	var command := PackedStringArray([ProjectSettings.globalize_path(HELPER), arguments[0], backend, _database])
	command.append_array(PackedStringArray(arguments.slice(1)))
	var output: Array = []
	OS.execute("node", command, output, true)
	var lines := "".join(output).strip_edges().split("\n")
	return lines[lines.size() - 1].strip_edges()


# ---------- helpers ----------

func _new_client() -> GameClient:
	var client := GameClient.new()
	client.remember_login = false
	client.server_url = _url()
	add_child(client)
	return client


# The warnings a client shows from now on, as they come.
func _notices(client: GameClient) -> Array:
	var shown: Array = []
	client.notice.connect(func(kind: String, message: String) -> void:
		if kind == "warning":
			shown.append(message))
	return shown


# The server's answer to a profile request made with `token`: [status code, body].
func _profile_with(token: String) -> Array:
	var http := HTTPRequest.new()
	http.timeout = 5.0
	add_child(http)
	var answer: Array = [0, {}]
	if http.request(_url() + "/api/user/profile", PackedStringArray(["Authorization: Bearer " + token])) == OK:
		var result: Array = await http.request_completed
		var parsed: Variant = JSON.parse_string((result[3] as PackedByteArray).get_string_from_utf8())
		answer = [result[1], parsed if parsed is Dictionary else {}]
	http.queue_free()
	return answer


func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout


# Waits until the condition holds, or gives up after `seconds`.
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
