extends Node
## 1.1.1 in-place updates from the GitHub releases page (BACKLOG "Settings redesign").
##
## Check: asks GitHub for the latest published release (drafts and pre-releases are never
## offered) and compares it with the running version.
## Update: downloads this build's file (resumes after a dropped connection, up to 3 tries),
## checks it against SHA256SUMS.txt, unpacks it beside the game, swaps it in under the
## same file name, starts it and waits until it reports a good start. Only then does this
## copy quit; the old game is kept as the one backup (GO BACK). If the new copy does not
## start within 30 seconds, the old game is put back and keeps running.
## Protected folders: the swap runs in a small helper that asks for permission (Windows
## "allow changes", Mac password box, Linux desktop password prompt).
## Settings and high scores live in the data folder and are never touched.

const UpdateCore = preload("res://scripts/UpdateCore.gd")

signal check_done(result: Dictionary)
signal progress(done: int, total: int)
signal stage_changed(text: String)
signal install_failed(title: String, message: String)
## The new copy started fine: this copy should quit now.
signal quit_for_update

const REPO := "S8619G/Stellar-Defense-Console"
## Update Test builds only (export feature "update_test"); Stephen 2026-10-26.
const TEST_REPO := "S8619G/Stellar-Defense-Console-Update-Test"
const CONFIRM_ARG := "--sdc-update-confirm="
const TEST_API_ARG := "--sdc-update-test-api="

var api_url: String = ""
var releases_page: String = ""
var user_agent: String = "StellarDefenseConsole"
var work_dir: String = "user://updates"
var backup_dir: String = "user://backup"
var state_file: String = "user://updates/update_state.cfg"
## CHECK NOW waits this long for GitHub (the startup check passes its own limit).
var check_timeout: float = 15.0
## The new copy must report a good start within this many seconds.
var start_confirm_seconds: float = 30.0
## The new copy reports a good start after running this long.
var confirm_after_seconds: float = 2.0
var download_tries: int = 3
var stall_seconds: float = 20.0
var retry_wait_seconds: float = 2.0
## Tests: replace the running game file and platform, and start nothing for real.
var install_target_override: String = ""
var platform_override: String = ""
var executable_override: String = ""
var dry_launch: bool = false
var steam_build: bool = false
var update_test_build: bool = false
var running_version: String = ""

var state := ConfigFile.new()
var busy: bool = false
var cancelled: bool = false
var last_result: Dictionary = {}
var _check_request: HTTPRequest
var _check_timer: SceneTreeTimer
var _check_serial: int = 0
var confirm_token: String = ""
var finishing_after_update: bool = false

func _ready() -> void:
	steam_build = steam_build or OS.has_feature("steam")
	update_test_build = update_test_build or OS.has_feature("update_test")
	if running_version == "":
		running_version = str(ProjectSettings.get_setting("application/config/version", "0"))
	var repo := TEST_REPO if update_test_build else REPO
	if api_url == "":
		api_url = "https://api.github.com/repos/%s/releases/latest" % repo
	if releases_page == "":
		releases_page = "https://github.com/%s/releases" % repo
	user_agent = "StellarDefenseConsole/%s" % running_version
	load_state()
	for arg in OS.get_cmdline_args() + OS.get_cmdline_user_args():
		if str(arg).begins_with(CONFIRM_ARG):
			confirm_token = str(arg).substr(CONFIRM_ARG.length())
		# Sandbox testing only: Update Test builds may be pointed at a local stand-in for
		# GitHub. Normal builds ignore this and always use the game's own GitHub page.
		elif str(arg).begins_with(TEST_API_ARG) and update_test_build:
			api_url = str(arg).substr(TEST_API_ARG.length())

# ------------------------------------------------------------------
# Saved state (its own file, so it is kept even with REMEMBER SETTINGS off)
# ------------------------------------------------------------------
func load_state() -> void:
	state = ConfigFile.new()
	state.load(state_file)

func save_state() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(work_dir))
	state.save(state_file)

func check_at_startup() -> bool:
	return bool(state.get_value("updates", "check_at_startup", true))

func set_check_at_startup(on: bool) -> void:
	load_state()
	state.set_value("updates", "check_at_startup", on)
	save_state()

func skipped_version() -> String:
	return str(state.get_value("updates", "skipped_version", ""))

func skip_version(version: String) -> void:
	load_state()
	state.set_value("updates", "skipped_version", version)
	save_state()

func updates_available_here() -> bool:
	return not steam_build and platform() != ""

func platform() -> String:
	return platform_override if platform_override != "" else UpdateCore.platform_key()

## One line for the ABOUT tab, for example "Last checked today at 9:17 AM.  Up to date."
func status_line() -> Dictionary:
	load_state()
	var note := str(state.get_value("updates", "note", ""))
	if note != "":
		return {"text": note, "good": true}
	var when := int(state.get_value("updates", "last_check_unix", 0))
	if when <= 0:
		return {"text": "Not checked yet.", "good": false}
	var text := "Last checked %s.  %s" % [UpdateCore.when_text(when), str(state.get_value("updates", "last_check_text", ""))]
	return {"text": text, "good": bool(state.get_value("updates", "last_check_ok", false))}

func _record_check(ok: bool, text: String) -> void:
	load_state()
	state.set_value("updates", "last_check_unix", int(Time.get_unix_time_from_system()))
	state.set_value("updates", "last_check_ok", ok)
	state.set_value("updates", "last_check_text", text)
	state.set_value("updates", "note", "")
	save_state()

func backup_version() -> String:
	load_state()
	var v := str(state.get_value("backup", "version", ""))
	var item := str(state.get_value("backup", "item", ""))
	if v == "" or item == "":
		return ""
	var path := ProjectSettings.globalize_path(backup_dir).path_join(item)
	if not (FileAccess.file_exists(path) or DirAccess.dir_exists_absolute(path)):
		return ""
	return v

# ------------------------------------------------------------------
# Check
# ------------------------------------------------------------------
## Asks GitHub for the latest release. Emits check_done with:
## ok, newer, version, date, size, notes, asset (url, name), sums_url, page, error.
func check(timeout: float = -1.0) -> void:
	if timeout <= 0.0:
		timeout = check_timeout
	_check_serial += 1
	var serial := _check_serial
	if is_instance_valid(_check_request):
		_check_request.cancel_request()
		_check_request.queue_free()
	_check_request = HTTPRequest.new()
	# The time limit is kept by the timer below (HTTPRequest's own limit was seen to stop
	# requests early in testing).
	_check_request.timeout = 0.0
	_check_request.max_redirects = 5
	add_child(_check_request)
	_check_request.request_completed.connect(_on_check_completed.bind(serial))
	var headers := PackedStringArray(["User-Agent: " + user_agent, "Accept: application/vnd.github+json"])
	var err := _check_request.request(api_url, headers)
	if err != OK:
		_finish_check(serial, {"ok": false, "error": "request %d" % err})
		return
	get_tree().create_timer(timeout).timeout.connect(func() -> void:
		if serial == _check_serial:
			if is_instance_valid(_check_request):
				_check_request.cancel_request()
			_finish_check(serial, {"ok": false, "error": "timeout"}))

func cancel_check() -> void:
	_check_serial += 1
	if is_instance_valid(_check_request):
		_check_request.cancel_request()

func _on_check_completed(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray, serial: int) -> void:
	if result != HTTPRequest.RESULT_SUCCESS:
		_finish_check(serial, {"ok": false, "error": "result %d" % result})
		return
	if code == 404:
		# No published release yet.
		_finish_check(serial, {"ok": true, "newer": false, "version": "", "error": ""})
		return
	if code != 200:
		_finish_check(serial, {"ok": false, "error": "HTTP %d" % code})
		return
	var data = JSON.parse_string(body.get_string_from_utf8())
	if not data is Dictionary:
		_finish_check(serial, {"ok": false, "error": "bad answer"})
		return
	_finish_check(serial, read_release(data))

## Turns GitHub's release answer into what the pop-up needs.
func read_release(data: Dictionary) -> Dictionary:
	var out := {"ok": true, "newer": false, "error": ""}
	if bool(data.get("draft", false)) or bool(data.get("prerelease", false)):
		return out
	var version := str(data.get("tag_name", "")).trim_prefix("v")
	out.version = version
	out.page = str(data.get("html_url", releases_page))
	out.date = str(data.get("published_at", "")).substr(0, 10)
	out.notes = UpdateCore.whats_new(str(data.get("body", "")))
	var assets: Array = data.get("assets", [])
	var key := platform()
	var asset := UpdateCore.find_asset(assets, version, key)
	var sums := UpdateCore.find_sums(assets)
	out.asset_name = str(asset.get("name", ""))
	out.asset_url = str(asset.get("browser_download_url", ""))
	out.size = int(asset.get("size", 0))
	out.sums_url = str(sums.get("browser_download_url", ""))
	out.newer = UpdateCore.is_newer(version, running_version)
	if out.newer and (out.asset_url == "" or out.sums_url == ""):
		out.missing_file = true
	return out

func _finish_check(serial: int, result: Dictionary) -> void:
	if serial != _check_serial:
		return
	_check_serial += 1
	if is_instance_valid(_check_request):
		_check_request.queue_free()
	if bool(result.get("ok", false)):
		var text := "Up to date."
		if bool(result.get("newer", false)):
			text = "Version %s is available." % result.version
		_record_check(true, text)
	else:
		_record_check(false, "Could not reach GitHub.")
	last_result = result
	check_done.emit(result)

# ------------------------------------------------------------------
# Update: download, check, unpack, swap, start, confirm
# ------------------------------------------------------------------
func cancel() -> void:
	cancelled = true

## Runs the whole update for a check result. Returns "" when this copy is about to quit
## (quit_for_update is emitted), otherwise the reason it stopped (install_failed emitted).
func update_to(release: Dictionary) -> String:
	if busy:
		return "busy"
	busy = true
	cancelled = false
	var why := await _update_to(release)
	busy = false
	return why

func _update_to(release: Dictionary) -> String:
	var problem := preflight()
	if problem != "":
		return _fail(problem)
	var version := str(release.get("version", ""))
	var dir := ProjectSettings.globalize_path(work_dir)
	DirAccess.make_dir_recursive_absolute(dir)
	var part := dir.path_join(str(release.asset_name) + ".part")
	stage_changed.emit("DOWNLOADING")
	var got := await download(str(release.asset_url), part, int(release.get("size", 0)))
	if cancelled:
		_remove_path(part)
		return _fail("cancelled")
	if got != "":
		return _fail("download", got)
	var sums_path := dir.path_join("SHA256SUMS.txt")
	_remove_path(sums_path)
	got = await download(str(release.sums_url), sums_path, 0, false)
	if got != "":
		_remove_path(part)
		return _fail("download", got)
	stage_changed.emit("CHECKING")
	var sums := UpdateCore.parse_sums(FileAccess.get_file_as_string(sums_path))
	var expected := UpdateCore.expected_hash(sums, version, platform(), str(release.asset_name))
	var actual := await sha256_file(part)
	_remove_path(sums_path)
	if expected == "" or actual != expected:
		_remove_path(part)
		return _fail("checksum")
	if cancelled:
		_remove_path(part)
		return _fail("cancelled")
	stage_changed.emit("UNPACKING")
	var staged := unpack(part, dir.path_join("staged"))
	_remove_path(part)
	if staged == "":
		return _fail("unpack")
	stage_changed.emit("STARTING")
	return await swap_and_start(staged, "update", running_version, version)

## GO BACK: swaps the backup copy in the same way (asks first, in the pop-up).
func go_back() -> String:
	if busy:
		return "busy"
	busy = true
	cancelled = false
	var why := ""
	var problem := preflight()
	var to := backup_version()
	if problem != "":
		why = _fail(problem)
	elif to == "":
		why = _fail("no_backup")
	else:
		stage_changed.emit("STARTING")
		var src := ProjectSettings.globalize_path(backup_dir).path_join(str(state.get_value("backup", "item", "")))
		var staged_dir := ProjectSettings.globalize_path(work_dir).path_join("staged")
		_remove_path(staged_dir)
		DirAccess.make_dir_recursive_absolute(staged_dir)
		var staged := staged_dir.path_join(src.get_file())
		if not _copy_path(src, staged):
			why = _fail("unpack")
		else:
			why = await swap_and_start(staged, "goback", running_version, to)
	busy = false
	return why

## Reasons the update cannot run here at all.
func preflight() -> String:
	if steam_build:
		return "steam"
	if platform() == "":
		return "platform"
	if platform() == "Mac" and executable_path().contains("/AppTranslocation/"):
		return "mac_translocated"
	var target := install_target()
	if target == "" or not (FileAccess.file_exists(target) or DirAccess.dir_exists_absolute(target)):
		return "no_target"
	if OS.has_feature("editor") and install_target_override == "":
		return "editor"
	return ""

func executable_path() -> String:
	return executable_override if executable_override != "" else OS.get_executable_path()

## The file (Windows, Linux) or app bundle (Mac) that is swapped.
func install_target() -> String:
	if install_target_override != "":
		return install_target_override
	var exe := executable_path()
	if platform() == "Mac":
		var at := exe.find(".app/Contents/MacOS/")
		return exe.substr(0, at + 4) if at > 0 else ""
	return exe

# ---------------- download ----------------
## Downloads url to path. Resumes after a dropped connection (up to download_tries
## tries in all). Returns "" when done, else a short reason.
func download(url: String, path: String, expected_size: int = 0, report: bool = true) -> String:
	var why := ""
	for attempt in range(maxi(1, download_tries)):
		if cancelled:
			return "cancelled"
		if attempt > 0:
			await get_tree().create_timer(retry_wait_seconds).timeout
		why = await _download_once(url, path, expected_size, report)
		if why == "":
			return ""
		if why == "http":
			break  # a refusal (for example 404) will not get better by trying again
	return why

func _download_once(start_url: String, path: String, expected_size: int, report: bool) -> String:
	var url := start_url
	for _redirect in range(6):
		var have := 0
		if FileAccess.file_exists(path):
			var f := FileAccess.open(path, FileAccess.READ)
			if f:
				have = f.get_length()
				f.close()
		if expected_size > 0 and have >= expected_size:
			return ""
		var parts := _split_url(url)
		if parts.is_empty():
			return "url"
		var client := HTTPClient.new()
		var tls: TLSOptions = TLSOptions.client() if parts.tls else null
		if client.connect_to_host(parts.host, parts.port, tls) != OK:
			return "connect"
		var idle := 0.0
		while client.get_status() in [HTTPClient.STATUS_RESOLVING, HTTPClient.STATUS_CONNECTING]:
			client.poll()
			idle += await _tick()
			if cancelled:
				client.close()
				return "cancelled"
			if idle > stall_seconds:
				client.close()
				return "timeout"
		if client.get_status() != HTTPClient.STATUS_CONNECTED:
			client.close()
			return "connect"
		var headers := PackedStringArray(["User-Agent: " + user_agent, "Accept: application/octet-stream"])
		if have > 0:
			headers.append("Range: bytes=%d-" % have)
		if client.request(HTTPClient.METHOD_GET, parts.path, headers) != OK:
			client.close()
			return "request"
		idle = 0.0
		while client.get_status() == HTTPClient.STATUS_REQUESTING:
			client.poll()
			idle += await _tick()
			if cancelled:
				client.close()
				return "cancelled"
			if idle > stall_seconds:
				client.close()
				return "timeout"
		if not client.has_response():
			client.close()
			return "dropped"
		var code := client.get_response_code()
		var response_headers := client.get_response_headers_as_dictionary()
		if code in [301, 302, 303, 307, 308]:
			var location := ""
			for k in response_headers:
				if str(k).to_lower() == "location":
					location = str(response_headers[k])
			client.close()
			if location == "":
				return "http"
			if location.begins_with("/"):
				location = "%s://%s%s%s" % ["https" if parts.tls else "http", parts.host, (":%d" % parts.port) if parts.port_given else "", location]
			url = location
			continue
		var mode := FileAccess.READ_WRITE
		if code == 200:
			have = 0
			mode = FileAccess.WRITE
		elif code == 206 and have > 0:
			mode = FileAccess.READ_WRITE
		elif code == 416 and have > 0:
			client.close()
			_remove_path(path)
			return "dropped"
		else:
			client.close()
			return "http"
		var total := expected_size
		var length := int(client.get_response_body_length())
		if length > 0:
			total = have + length
		var file := FileAccess.open(path, mode)
		if file == null:
			client.close()
			return "disk"
		file.seek_end()
		var done := have
		if report:
			progress.emit(done, total)
		idle = 0.0
		while client.get_status() == HTTPClient.STATUS_BODY:
			# Read while the status is still BODY, then poll; polling first could end the
			# body (or note a dropped connection) and make the read report an engine error.
			var chunk := client.read_response_body_chunk()
			client.poll()
			if chunk.size() > 0:
				file.store_buffer(chunk)
				done += chunk.size()
				idle = 0.0
				if report:
					progress.emit(done, total)
			else:
				idle += await _tick()
			if cancelled:
				file.close()
				client.close()
				return "cancelled"
			if idle > stall_seconds:
				file.close()
				client.close()
				return "timeout"
		file.close()
		client.close()
		if (total > 0 and done < total) or (length > 0 and done - have < length):
			return "dropped"
		return ""
	return "redirects"

func _tick() -> float:
	await get_tree().process_frame
	return maxf(get_process_delta_time(), 0.001)

func _split_url(url: String) -> Dictionary:
	var tls := url.begins_with("https://")
	if not tls and not url.begins_with("http://"):
		return {}
	var rest := url.substr(8 if tls else 7)
	var slash := rest.find("/")
	var hostport := rest if slash < 0 else rest.substr(0, slash)
	var path := "/" if slash < 0 else rest.substr(slash)
	var port := 443 if tls else 80
	var given := false
	var colon := hostport.rfind(":")
	if colon > 0 and hostport.substr(colon + 1).is_valid_int():
		port = int(hostport.substr(colon + 1))
		hostport = hostport.substr(0, colon)
		given = true
	return {"tls": tls, "host": hostport, "port": port, "path": path, "port_given": given}

## SHA-256 of a file, read 1 MB per frame so the screen keeps moving.
func sha256_file(path: String) -> String:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return ""
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	while f.get_position() < f.get_length():
		ctx.update(f.get_buffer(1048576))
		if is_inside_tree():
			await get_tree().process_frame
	f.close()
	return ctx.finish().hex_encode()

# ---------------- unpack ----------------
## Unpacks the download into folder and returns the game file or app inside ("" on failure).
func unpack(archive: String, folder: String) -> String:
	_remove_path(folder)
	DirAccess.make_dir_recursive_absolute(folder)
	match platform():
		"Windows_x64", "Windows_arm64":
			var zip := ZIPReader.new()
			if zip.open(archive) != OK:
				return ""
			for entry in zip.get_files():
				if entry.to_lower().ends_with(".exe"):
					var bytes := zip.read_file(entry)
					zip.close()
					if bytes.size() < 1048576 or bytes[0] != 0x4D or bytes[1] != 0x5A:
						return ""
					var out := folder.path_join(entry.get_file())
					var f := FileAccess.open(out, FileAccess.WRITE)
					if f == null:
						return ""
					f.store_buffer(bytes)
					f.close()
					return out
			zip.close()
			return ""
		"Mac":
			if OS.execute("ditto", ["-x", "-k", archive, folder]) != 0:
				return ""
			for name in DirAccess.get_directories_at(folder):
				if name.ends_with(".app") and DirAccess.dir_exists_absolute(folder.path_join(name).path_join("Contents/MacOS")):
					return folder.path_join(name)
			return ""
		"Linux":
			if OS.execute("tar", ["-xzf", archive, "-C", folder]) != 0:
				return ""
			for name in DirAccess.get_files_at(folder):
				var path := folder.path_join(name)
				var f := FileAccess.open(path, FileAccess.READ)
				if f and f.get_length() > 1048576 and f.get_buffer(4) == PackedByteArray([0x7F, 0x45, 0x4C, 0x46]):
					f.close()
					OS.execute("chmod", ["+x", path])
					return path
			return ""
	return ""

# ---------------- swap ----------------
func _folder_writable(folder: String) -> bool:
	var probe := folder.path_join(".sdc_write_check_%d" % OS.get_process_id())
	var f := FileAccess.open(probe, FileAccess.WRITE)
	if f == null:
		return false
	f.close()
	DirAccess.remove_absolute(probe)
	return true

## Swaps staged in for the running game, starts it and waits for its good start.
func swap_and_start(staged: String, kind: String, from_version: String, to_version: String) -> String:
	var target := install_target()
	var folder := target.get_base_dir()
	var stamp := "%d" % int(Time.get_unix_time_from_system())
	var token := "%s-%d" % [stamp, OS.get_process_id()]
	var old := target + ".old-" + stamp
	var dir := ProjectSettings.globalize_path(work_dir)
	for marker in ["ok", "commit", "rollback", "swapped", "helperfail", "done"]:
		_remove_path(dir.path_join(token + "." + marker))
	var protected := not _folder_writable(folder)
	var pending := ConfigFile.new()
	pending.set_value("pending", "token", token)
	pending.set_value("pending", "kind", kind)
	pending.set_value("pending", "old", old)
	pending.set_value("pending", "target", target)
	pending.set_value("pending", "from", from_version)
	pending.set_value("pending", "to", to_version)
	pending.set_value("pending", "parent_pid", OS.get_process_id())
	pending.set_value("pending", "helper", protected)
	pending.save(dir.path_join("pending.cfg"))
	if protected:
		var asked := await _helper_swap(staged, target, old, token)
		if asked != "":
			_remove_path(staged)
			_remove_path(dir.path_join("pending.cfg"))
			return _fail(asked)
	else:
		var next := target + ".new-" + stamp
		_remove_path(next)
		if not _move_path(staged, next):
			_remove_path(staged)
			return _fail("swap")
		if not _move_path(target, old):
			_remove_path(next)
			return _fail("swap")
		if not _move_path(next, target):
			_move_path(old, target)
			_remove_path(next)
			return _fail("swap")
	# Start the new copy and wait for its good start.
	var pid := _launch(target, token)
	var waited := 0.0
	var started := false
	while waited < start_confirm_seconds:
		if FileAccess.file_exists(dir.path_join(token + ".ok")):
			started = true
			break
		if pid > 0 and not dry_launch and waited > 1.0 and not OS.is_process_running(pid):
			break
		waited += await _wait(0.25)
	if started:
		if kind == "update":
			_keep_backup(old, from_version, target.get_file())
		else:
			_drop_backup()
			load_state()
			state.set_value("updates", "skipped_version", from_version)
			save_state()
		FileAccess.open(dir.path_join(token + ".commit"), FileAccess.WRITE).store_string("ok")
		if protected:
			await _wait_for(dir.path_join(token + ".done"), 5.0)
		quit_for_update.emit()
		return ""
	# No good start: put the old game back. This copy keeps running.
	if pid > 0 and not dry_launch and OS.is_process_running(pid):
		OS.kill(pid)
		await _wait(0.5)
	if protected:
		FileAccess.open(dir.path_join(token + ".rollback"), FileAccess.WRITE).store_string("rollback")
		await _wait_for(dir.path_join(token + ".done"), 15.0)
	else:
		var removed := false
		for i in range(12):
			if _remove_path(target):
				removed = true
				break
			await _wait(0.25)
		if not removed:
			_move_path(target, target + ".failed-" + stamp)
		_move_path(old, target)
	_remove_path(dir.path_join("pending.cfg"))
	return _fail("no_start", to_version)

func _launch(target: String, token: String) -> int:
	var args := PackedStringArray([CONFIRM_ARG + token])
	if dry_launch:
		return 0
	var exe := target
	if platform() == "Mac":
		var macos := target.path_join("Contents/MacOS")
		var files := DirAccess.get_files_at(macos)
		if files.is_empty():
			return 0
		exe = macos.path_join(files[0])
	return OS.create_process(exe, args)

## Keeps the game that was just replaced as the one backup (replacing an older backup).
## item is the game's own file name, taken before the swap: once the running file has been
## renamed, the system reports the renamed path for it (seen on Linux).
func _keep_backup(old: String, version: String, item: String) -> void:
	var dir := ProjectSettings.globalize_path(backup_dir)
	_drop_backup()
	DirAccess.make_dir_recursive_absolute(dir)
	if _copy_path(old, dir.path_join(item)):
		load_state()
		state.set_value("backup", "version", version)
		state.set_value("backup", "item", item)
		save_state()

func _drop_backup() -> void:
	load_state()
	var item := str(state.get_value("backup", "item", ""))
	if item != "":
		_remove_path(ProjectSettings.globalize_path(backup_dir).path_join(item))
	if state.has_section("backup"):
		state.erase_section("backup")
	save_state()

## The swap helper for protected folders, started with the system's permission prompt.
func _helper_swap(staged: String, target: String, old: String, token: String) -> String:
	var dir := ProjectSettings.globalize_path(work_dir)
	var key := platform()
	var pid := 0
	if key.begins_with("Windows"):
		var script := dir.path_join("swap_%s.ps1" % token)
		var f := FileAccess.open(script, FileAccess.WRITE)
		f.store_string(_powershell_script(staged, target, old, dir, token))
		f.close()
		var inner := "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File \"%s\"" % script
		var outer := "try { Start-Process -FilePath powershell.exe -Verb RunAs -WindowStyle Hidden -ArgumentList '%s'; exit 0 } catch { exit 5 }" % inner.replace("'", "''")
		if dry_launch:
			return "protected_refused"
		var code := OS.execute("powershell.exe", ["-NoProfile", "-ExecutionPolicy", "Bypass", "-Command", outer])
		if code != 0:
			return "protected_refused"
	else:
		var script := dir.path_join("swap_%s.sh" % token)
		var f := FileAccess.open(script, FileAccess.WRITE)
		f.store_string(_shell_script(staged, target, old, dir, token))
		f.close()
		if key == "Mac":
			var apple := "do shell script \"/bin/sh \" & quoted form of \"%s\" with administrator privileges" % script.replace("\"", "\\\"")
			if dry_launch:
				return "protected_refused"
			pid = OS.create_process("osascript", ["-e", apple])
		else:
			if OS.execute("sh", ["-c", "command -v pkexec"]) != 0:
				return "protected_no_prompt"
			if dry_launch:
				return "protected_refused"
			pid = OS.create_process("pkexec", ["/bin/sh", script])
		if pid <= 0:
			return "protected_no_prompt" if key == "Linux" else "protected_refused"
	# Wait for the helper to swap (the player may take a while with the password box).
	var waited := 0.0
	while waited < 180.0:
		if FileAccess.file_exists(dir.path_join(token + ".swapped")):
			return ""
		if FileAccess.file_exists(dir.path_join(token + ".helperfail")):
			return "swap"
		if pid > 0 and waited > 1.0 and not OS.is_process_running(pid):
			# The prompt was cancelled (or there is no desktop password agent on Linux).
			if FileAccess.file_exists(dir.path_join(token + ".swapped")):
				return ""
			return "protected_no_prompt" if key == "Linux" and waited < 3.0 else "protected_refused"
		waited += await _wait(0.25)
	return "protected_refused"

func _ps(path: String) -> String:
	return "'" + path.replace("/", "\\").replace("'", "''") + "'"

func _powershell_script(staged: String, target: String, old: String, markers: String, token: String) -> String:
	var lines := [
		"$ErrorActionPreference = 'Stop'",
		"$S = %s; $T = %s; $O = %s; $N = $T + '.new-%s'; $M = %s; $K = '%s'" % [_ps(staged), _ps(target), _ps(old), token, _ps(markers), token],
		"try {",
		"  Copy-Item -LiteralPath $S -Destination $N -Force",
		"  Move-Item -LiteralPath $T -Destination $O",
		"  try { Move-Item -LiteralPath $N -Destination $T } catch { Move-Item -LiteralPath $O -Destination $T; throw }",
		"} catch {",
		"  Remove-Item -LiteralPath $N -Force -ErrorAction SilentlyContinue",
		"  Set-Content -LiteralPath (Join-Path $M ($K + '.helperfail')) -Value $_.Exception.Message",
		"  exit 1",
		"}",
		"Set-Content -LiteralPath (Join-Path $M ($K + '.swapped')) -Value 'ok'",
		"$end = (Get-Date).AddSeconds(150)",
		"while ((Get-Date) -lt $end) { if ((Test-Path -LiteralPath (Join-Path $M ($K + '.commit'))) -or (Test-Path -LiteralPath (Join-Path $M ($K + '.rollback')))) { break }; Start-Sleep -Milliseconds 300 }",
		"if ((Test-Path -LiteralPath (Join-Path $M ($K + '.commit'))) -or ((Test-Path -LiteralPath (Join-Path $M ($K + '.ok'))) -and -not (Test-Path -LiteralPath (Join-Path $M ($K + '.rollback'))))) {",
		"  for ($i = 0; $i -lt 200; $i++) { try { Remove-Item -LiteralPath $O -Force; break } catch { Start-Sleep -Milliseconds 300 } }",
		"} else {",
		"  for ($i = 0; $i -lt 50; $i++) { try { Remove-Item -LiteralPath $T -Force; break } catch { Start-Sleep -Milliseconds 300 } }",
		"  Move-Item -LiteralPath $O -Destination $T -Force",
		"}",
		"Set-Content -LiteralPath (Join-Path $M ($K + '.done')) -Value 'ok'",
	]
	return "\r\n".join(PackedStringArray(lines)) + "\r\n"

func _sh(path: String) -> String:
	return "'" + path.replace("'", "'\\''") + "'"

func _shell_script(staged: String, target: String, old: String, markers: String, token: String) -> String:
	var lines := [
		"#!/bin/sh",
		"S=%s; T=%s; O=%s; N=\"$T.new-%s\"; M=%s; K='%s'" % [_sh(staged), _sh(target), _sh(old), token, _sh(markers), token],
		"rm -rf \"$N\"",
		"if ! cp -Rp \"$S\" \"$N\"; then rm -rf \"$N\"; echo copy > \"$M/$K.helperfail\"; exit 1; fi",
		"if ! mv \"$T\" \"$O\"; then rm -rf \"$N\"; echo move > \"$M/$K.helperfail\"; exit 1; fi",
		"if ! mv \"$N\" \"$T\"; then mv \"$O\" \"$T\"; rm -rf \"$N\"; echo move > \"$M/$K.helperfail\"; exit 1; fi",
		"echo ok > \"$M/$K.swapped\"",
		"i=0",
		"while [ $i -lt 500 ]; do [ -f \"$M/$K.commit\" ] && break; [ -f \"$M/$K.rollback\" ] && break; sleep 0.3; i=$((i+1)); done",
		"if [ -f \"$M/$K.commit\" ] || { [ -f \"$M/$K.ok\" ] && [ ! -f \"$M/$K.rollback\" ]; }; then rm -rf \"$O\"; else rm -rf \"$T\"; mv \"$O\" \"$T\"; fi",
		"echo ok > \"$M/$K.done\"",
	]
	return "\n".join(PackedStringArray(lines)) + "\n"

# ------------------------------------------------------------------
# The new copy's side: report a good start, then tidy up
# ------------------------------------------------------------------
## Called by the console once it is up and running (after confirm_after_seconds).
func confirm_started() -> void:
	if confirm_token == "":
		return
	var dir := ProjectSettings.globalize_path(work_dir)
	var f := FileAccess.open(dir.path_join(confirm_token + ".ok"), FileAccess.WRITE)
	if f:
		f.store_string("ok")
		f.close()
	finishing_after_update = true
	_finish_after_update()

## Waits for the old copy to accept (commit) and quit, then removes the replaced game.
func _finish_after_update() -> void:
	var dir := ProjectSettings.globalize_path(work_dir)
	var pending := ConfigFile.new()
	if pending.load(dir.path_join("pending.cfg")) != OK or str(pending.get_value("pending", "token", "")) != confirm_token:
		finishing_after_update = false
		return
	await _wait_for(dir.path_join(confirm_token + ".commit"), start_confirm_seconds + 10.0)
	if not FileAccess.file_exists(dir.path_join(confirm_token + ".commit")):
		finishing_after_update = false
		return
	tidy_pending()

## Removes the replaced game (retrying while the old copy is still closing) and writes the
## note shown on the ABOUT tab. Also runs at a normal start if an earlier tidy-up was cut short.
func tidy_pending() -> void:
	var dir := ProjectSettings.globalize_path(work_dir)
	var pending := ConfigFile.new()
	if pending.load(dir.path_join("pending.cfg")) != OK:
		finishing_after_update = false
		return
	var token := str(pending.get_value("pending", "token", ""))
	if not FileAccess.file_exists(dir.path_join(token + ".commit")):
		_remove_path(dir.path_join("pending.cfg"))
		finishing_after_update = false
		return
	var old := str(pending.get_value("pending", "old", ""))
	if not bool(pending.get_value("pending", "helper", false)) and old != "":
		for i in range(240):
			if not (FileAccess.file_exists(old) or DirAccess.dir_exists_absolute(old)) or _remove_path(old):
				break
			if is_inside_tree():
				await _wait(0.25)
	var kind := str(pending.get_value("pending", "kind", "update"))
	load_state()
	var to := str(pending.get_value("pending", "to", running_version))
	var from := str(pending.get_value("pending", "from", ""))
	var note := ("Updated from %s %s." % [from, UpdateCore.when_text(int(Time.get_unix_time_from_system()))]) if kind == "update" \
		else ("Went back from %s %s." % [from, UpdateCore.when_text(int(Time.get_unix_time_from_system()))])
	state.set_value("updates", "note", note)
	state.set_value("updates", "note_version", to)
	save_state()
	for marker in ["ok", "commit", "rollback", "swapped", "helperfail", "done"]:
		_remove_path(dir.path_join(token + "." + marker))
	for name in DirAccess.get_files_at(dir):
		if name.begins_with("swap_" + token):
			_remove_path(dir.path_join(name))
	_remove_path(dir.path_join("staged"))
	_remove_path(dir.path_join("pending.cfg"))
	finishing_after_update = false

## The ABOUT note ("Updated from ...") is shown until the next check.
func clear_note_if_other_version() -> void:
	load_state()
	if str(state.get_value("updates", "note_version", "")) != running_version and str(state.get_value("updates", "note", "")) != "":
		state.set_value("updates", "note", "")
		save_state()

# ------------------------------------------------------------------
# Small file helpers (the game's own folder and the data folder only)
# ------------------------------------------------------------------
func _wait(seconds: float) -> float:
	if not is_inside_tree():
		return seconds
	await get_tree().create_timer(seconds).timeout
	return seconds

func _wait_for(path: String, seconds: float) -> bool:
	var waited := 0.0
	while waited < seconds:
		if FileAccess.file_exists(path):
			return true
		waited += await _wait(0.2)
	return FileAccess.file_exists(path)

func _move_path(from: String, to: String) -> bool:
	if DirAccess.rename_absolute(from, to) == OK:
		return true
	# Across drives: copy, then remove the original.
	if _copy_path(from, to):
		if _remove_path(from):
			return true
		_remove_path(to)
	return false

func _copy_path(from: String, to: String) -> bool:
	if DirAccess.dir_exists_absolute(from):
		if OS.get_name() == "Windows":
			return false
		_remove_path(to)
		return OS.execute("cp", ["-Rp", from, to]) == 0
	if not FileAccess.file_exists(from):
		return false
	if DirAccess.copy_absolute(from, to) != OK:
		return false
	if OS.get_name() != "Windows":
		OS.execute("chmod", ["+x", to])
	return true

## Removes a file or folder. True when it is gone.
func _remove_path(path: String) -> bool:
	if path == "":
		return true
	if DirAccess.dir_exists_absolute(path):
		if OS.get_name() == "Windows":
			_remove_dir_windows(path)
		else:
			OS.execute("rm", ["-rf", path])
		return not DirAccess.dir_exists_absolute(path)
	if FileAccess.file_exists(path):
		return DirAccess.remove_absolute(path) == OK
	return true

func _remove_dir_windows(path: String) -> void:
	for name in DirAccess.get_files_at(path):
		DirAccess.remove_absolute(path.path_join(name))
	for name in DirAccess.get_directories_at(path):
		_remove_dir_windows(path.path_join(name))
	DirAccess.remove_absolute(path)

func _fail(reason: String, detail: String = "") -> String:
	var info := failure_text(reason, detail)
	if reason != "cancelled":
		install_failed.emit(info.title, info.text)
	return reason

## Plain titles and messages for each way an update can stop.
func failure_text(reason: String, detail: String = "") -> Dictionary:
	match reason:
		"cancelled":
			return {"title": "UPDATE CANCELLED", "text": "Nothing was changed."}
		"download":
			return {"title": "DOWNLOAD DID NOT FINISH", "text": "The download stopped and could not be resumed. Nothing was changed. Check the internet connection and try again."}
		"checksum":
			return {"title": "DOWNLOAD DID NOT CHECK OUT", "text": "The downloaded file did not match the checksum list, so it was not used. Nothing was changed."}
		"unpack":
			return {"title": "UPDATE COULD NOT BE UNPACKED", "text": "The downloaded file could not be unpacked. Nothing was changed."}
		"swap":
			return {"title": "GAME FILE COULD NOT BE REPLACED", "text": "The game file could not be swapped. The current version was kept and nothing else was changed."}
		"no_start":
			return {"title": "NEW VERSION DID NOT START", "text": "Version %s did not start, so version %s was put back. Nothing else was changed." % [detail, running_version]}
		"mac_translocated":
			return {"title": "MOVE THE GAME FIRST", "text": "Move Stellar Defense Console to your Applications folder, open it from there and update again. Nothing was changed."}
		"protected_refused":
			return {"title": "PERMISSION NOT GIVEN", "text": "The game's folder is protected and permission to change it was not given. Nothing was changed."}
		"protected_no_prompt":
			return {"title": "FOLDER IS PROTECTED", "text": "This folder is protected. Move the game to a folder you own, or update it manually. Nothing was changed."}
		"no_backup":
			return {"title": "NO EARLIER VERSION KEPT", "text": "There is no earlier version to go back to."}
		"steam":
			return {"title": "UPDATES COME FROM STEAM", "text": "Steam keeps this copy up to date."}
		"editor":
			return {"title": "NOT IN THE EDITOR", "text": "Updates work only in an exported game."}
	return {"title": "UPDATE DID NOT RUN", "text": "Nothing was changed."}
