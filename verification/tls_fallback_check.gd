extends SceneTree
## 1.1.1: with GitHub's certificate authorities hidden from the engine's default list
## (as on the Windows ARM64 computer), the check and a download must still work by
## switching to the game's own list. Uses the real practice page on GitHub.
const Updater := preload("res://scripts/Updater.gd")
var fails := 0
func ok(c: bool, what: String) -> void:
	print(("PASS " if c else "FAIL ") + what)
	if not c: fails += 1
func _init() -> void:
	call_deferred("_run")
func _run() -> void:
	var u = Updater.new()
	u.update_test_build = true
	u.running_version = "1.1.1"
	u.work_dir = "user://tls_test"
	u.state_file = "user://tls_test/state.cfg"
	root.add_child(u)
	await process_frame
	# 1) default list only: confirm the failure is reproduced
	var plain := HTTPRequest.new()
	plain.set_tls_options(TLSOptions.client())
	root.add_child(plain)
	plain.request(u.api_url, PackedStringArray(["User-Agent: SDC-test"]))
	var r: Array = await plain.request_completed
	ok(r[0] == HTTPRequest.RESULT_TLS_HANDSHAKE_ERROR, "default list fails as on Windows (result %d)" % r[0])
	# 2) the updater check switches to the game's list and gets the answer
	u.check(20.0)
	var res: Dictionary = await u.check_done
	ok(bool(res.get("ok", false)), "check works (%s)" % res.get("error", ""))
	ok(u.use_bundled_roots, "the game's list was used")
	ok(str(res.get("version", "")) == "1.1.2" and bool(res.get("newer", false)), "finds 1.1.2 (%s)" % res.get("version", ""))
	# 3) a fresh updater downloads SHA256SUMS (GitHub redirect to its file host) with fallback
	var u2 = Updater.new()
	u2.update_test_build = true
	u2.running_version = "1.1.1"
	root.add_child(u2)
	await process_frame
	var p := OS.get_user_data_dir() + "/tls_sums.txt"
	DirAccess.remove_absolute(p)
	var why: String = await u2.download(str(res.get("sums_url", "")), p, 0, false)
	ok(why == "" and FileAccess.get_file_as_string(p).contains("1.1.2_Windows_arm64.exe.zip"), "download works (%s)" % why)
	ok(u2.use_bundled_roots, "download switched to the game's list")
	# 4) a broken list of its own: clear secure-connection message, no endless retry
	var u3 = Updater.new()
	u3.update_test_build = true
	u3.running_version = "1.1.1"
	u3.trusted_roots_path = "res://missing_roots.crt"
	u3.work_dir = "user://tls_test3"
	u3.state_file = "user://tls_test3/state.cfg"
	root.add_child(u3)
	await process_frame
	u3.check(20.0)
	var r3: Dictionary = await u3.check_done
	ok(not bool(r3.get("ok", true)) and bool(r3.get("secure", false)), "still failing gives the secure-connection result (%s)" % r3.get("error", ""))
	ok(u3.state.get_value("updates", "last_check_text", "") == "Could not make a secure connection to GitHub.", "ABOUT line text")
	print("TLS_RESULT failures=%d" % fails)
	quit(1 if fails else 0)
