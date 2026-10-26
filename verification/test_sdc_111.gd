extends SceneTree
## Stellar Defense Console 1.1.1: the changes of this version.
## 1. Settings redesign: GAME / SYSTEM / ABOUT tabs (opens on GAME, LB / RB switch tabs).
## 2. ABOUT tab: version panel, CHECK NOW, CHECK AT STARTUP, GO BACK, WHAT'S NEW, links.
## 3. In-place updates from GitHub: quiet check at startup (splash + up to 3 seconds), the
##    pop-up (LATER / SKIP THIS VERSION / UPDATE NOW), UPDATE NOW only between battles,
##    download with resume, checksum, swap, good-start confirmation, roll back, GO BACK.
##    Network parts run against verification/update_test_server.py on 127.0.0.1.
## 4. Stealth Interceptor: fires from farther out, second nuke 3 seconds after the first,
##    faster turn home.
const UpdateCore = preload("res://scripts/UpdateCore.gd")
const Updater = preload("res://scripts/Updater.gd")
var checks := 0
var failures := 0
var console: Control
var c: Control
var server_pid := 0
var cfg_path := ""
var files_dir := ""
var base := ""
var tmp := ""

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("FAIL " + label)
	print("PASS " if ok else "FAIL ", label)

func _initialize() -> void:
	call_deferred("_run")

func frames(count: int = 3) -> void:
	for i in range(count):
		await process_frame

func wait(seconds: float) -> void:
	await create_timer(seconds).timeout

func _run() -> void:
	tmp = ProjectSettings.globalize_path("user://t111")
	OS.execute("rm", ["-rf", tmp])
	DirAccess.make_dir_recursive_absolute(tmp)
	core_checks()
	release_checks()
	await start_server()
	await console_checks()
	await network_checks()
	await install_checks()
	await startup_checks()
	stealth_checks()
	tls_checks()
	naming_checks()
	if server_pid > 0:
		OS.kill(server_pid)
	print("SDC111_RESULT checks=%d failures=%d" % [checks, failures])
	quit(1 if failures > 0 else 0)

# ------------------------------------------------------------------
func core_checks() -> void:
	check(UpdateCore.compare_versions("1.1.2", "1.1.1") == 1 and UpdateCore.compare_versions("1.1.1", "1.1.1") == 0 \
		and UpdateCore.compare_versions("1.1.0", "1.1.1") == -1, "Version order 1.1.0 < 1.1.1 < 1.1.2")
	check(UpdateCore.compare_versions("1.10.0", "1.9.9") == 1 and UpdateCore.compare_versions("v1.1", "1.1.0") == 0, "Version numbers compared as numbers; v and missing parts handled")
	check(not UpdateCore.is_newer("banana", "1.1.1") and not UpdateCore.is_newer("", "1.1.1"), "A tag that is not a version is never offered")
	check(UpdateCore.platform_key("Windows", "x86_64") == "Windows_x64" and UpdateCore.platform_key("Windows", "arm64") == "Windows_arm64" \
		and UpdateCore.platform_key("macOS", "arm64") == "Mac" and UpdateCore.platform_key("Linux", "x86_64") == "Linux", "Build type from system and processor")
	check(UpdateCore.build_label("Windows_x64") == "WINDOWS X64" and UpdateCore.build_label("Windows_arm64") == "WINDOWS ARM64" \
		and UpdateCore.build_label("Mac") == "MAC (UNIVERSAL)" and UpdateCore.build_label("Linux") == "LINUX X86_64", "ABOUT build type words")
	check(UpdateCore.asset_name("1.1.2", "Windows_x64") == "Stellar_Defense_Console_1.1.2_Windows_x64.exe.zip" \
		and UpdateCore.asset_name("1.1.2", "Windows_arm64") == "Stellar_Defense_Console_1.1.2_Windows_arm64.exe.zip" \
		and UpdateCore.asset_name("v1.1.2", "Mac") == "Stellar_Defense_Console_1.1.2_Mac.zip" \
		and UpdateCore.asset_name("1.1.2", "Linux") == "Stellar_Defense_Console_1.1.2_Linux.tar.gz", "Fixed GitHub file names")
	# The real 1.1.0 release list (the ARM64 file was renamed on upload).
	var real := [{"name": "SHA256SUMS.txt"}, {"name": "Stellar.Defense.Console.1.1.0.for.Windows.ARM64.zip"},
		{"name": "Stellar_Defense_Console_1.1.0_Linux.tar.gz"}, {"name": "Stellar_Defense_Console_1.1.0_Mac.zip"},
		{"name": "Stellar_Defense_Console_1.1.0_Windows_x64.exe.zip"}]
	check(UpdateCore.find_asset(real, "1.1.0", "Windows_arm64").get("name", "") == "Stellar.Defense.Console.1.1.0.for.Windows.ARM64.zip", "Renamed ARM64 upload still found")
	check(UpdateCore.find_asset(real, "1.1.0", "Windows_x64").get("name", "") == "Stellar_Defense_Console_1.1.0_Windows_x64.exe.zip", "Windows x64 file found (not the ARM64 one)")
	check(UpdateCore.find_asset(real, "1.1.0", "Mac").get("name", "") == "Stellar_Defense_Console_1.1.0_Mac.zip" \
		and UpdateCore.find_asset(real, "1.1.0", "Linux").get("name", "") == "Stellar_Defense_Console_1.1.0_Linux.tar.gz", "Mac and Linux files found")
	check(UpdateCore.find_asset([{"name": "SHA256SUMS.txt"}], "1.1.0", "Linux").is_empty(), "No file for this computer: nothing picked")
	check(UpdateCore.find_sums(real).get("name", "") == "SHA256SUMS.txt", "Checksum list found")
	var h := "ab".repeat(32)
	var sums := UpdateCore.parse_sums("%s  Stellar_Defense_Console_1.1.2_Linux.tar.gz\r\n%s *Other.zip\nnot a line\n" % [h, "CD".repeat(32)])
	check(sums.size() == 2 and sums["Stellar_Defense_Console_1.1.2_Linux.tar.gz"] == h and sums["Other.zip"] == "cd".repeat(32), "Checksum list read (both styles, Windows line ends)")
	check(UpdateCore.expected_hash(sums, "1.1.2", "Linux", "x") == h and UpdateCore.expected_hash(sums, "1.1.2", "Mac", "Other.zip") == "cd".repeat(32) \
		and UpdateCore.expected_hash(sums, "1.1.2", "Mac", "Missing.zip") == "", "Expected checksum by fixed or uploaded name; none when unlisted")
	var body := "Intro line.\n\n## New in 1.1.0\n\n- **Defend the Aegis.** The top message bar reads DEFEND THE AEGIS. More words here.\n- **Jump cost.** JUMP costs 3,000 points.\n- `Rapid Repair` limit\n- Fourth item\n- Fifth item\n\n## Downloads\n- not this"
	var news := UpdateCore.whats_new(body)
	check(news.size() == 4 and news[0] == "Defend the Aegis" and news[2] == "Rapid Repair limit", "WHAT'S NEW lines: New in section, first sentence, no Markdown marks, 4 at most")
	var long := UpdateCore.whats_new("## New in 9\n- " + "word ".repeat(30))
	check(long.size() == 1 and long[0].length() <= 66 and long[0].ends_with("..."), "Long WHAT'S NEW line is shortened to fit")
	check(UpdateCore.mb(33554432) == "32.0 MB", "Megabytes shown with one decimal")
	var now := int(Time.get_unix_time_from_system())
	check(UpdateCore.when_text(now, now).begins_with("today at ") and UpdateCore.when_text(now - 86400 * 3, now).begins_with("on "), "Check time words (today / on date)")

func release_checks() -> void:
	var u := Updater.new()
	u.running_version = "1.1.1"
	u.platform_override = "Windows_arm64"
	var rel := {"tag_name": "v1.1.2", "html_url": "https://github.com/x/releases/tag/v1.1.2", "published_at": "2026-11-02T10:00:00Z",
		"body": "## New in 1.1.2\n- **One.** a\n- **Two.** b",
		"assets": [{"name": "SHA256SUMS.txt", "browser_download_url": "u1"}, {"name": "Stellar.Defense.Console.1.1.2.for.Windows.ARM64.zip", "browser_download_url": "u2", "size": 5}]}
	var r := u.read_release(rel)
	check(r.ok and r.newer and r.version == "1.1.2" and r.date == "2026-11-02" and r.asset_url == "u2" and r.sums_url == "u1" and r.size == 5 \
		and not r.has("missing_file") and r.notes.size() == 2, "Release answer read (version, date, file, checksum list, notes)")
	var d := rel.duplicate(true)
	d.draft = true
	check(not u.read_release(d).newer, "Draft releases are never offered")
	d = rel.duplicate(true)
	d.prerelease = true
	check(not u.read_release(d).newer, "Pre-releases are never offered")
	d = rel.duplicate(true)
	d.tag_name = "v1.1.1"
	check(not u.read_release(d).newer, "Same version: up to date")
	d = rel.duplicate(true)
	d.tag_name = "v1.0.9"
	check(not u.read_release(d).newer, "Older version on GitHub: not offered")
	u.platform_override = "Mac"
	check(bool(u.read_release(rel).get("missing_file", false)), "Newer version without a file for this computer is flagged")
	check(u.failure_text("no_start", "1.1.2").text.contains("1.1.1 was put back") and u.failure_text("checksum").title == "DOWNLOAD DID NOT CHECK OUT", "Failure messages in plain words")
	for reason in ["cancelled", "download", "checksum", "unpack", "swap", "no_start", "mac_translocated", "protected_refused", "protected_no_prompt", "no_backup", "steam", "editor"]:
		var t: Dictionary = u.failure_text(reason, "1.1.2")
		check(not t.text.contains("!") and not t.title.contains("!") and t.title == t.title.to_upper(), "Message '%s' is plain (no exclamation points, title in capitals)" % reason)
	u.steam_build = true
	u.platform_override = "Windows_x64"
	check(not u.updates_available_here() and u.preflight() == "steam", "Steam builds never update themselves")
	u.free()

# ------------------------------------------------------------------
func write_cfg(extra: Dictionary) -> void:
	var cfg := {"files": files_dir, "redirect": true, "latest": latest_json("1.1.2")}
	for k in extra:
		cfg[k] = extra[k]
	var f := FileAccess.open(cfg_path, FileAccess.WRITE)
	f.store_string(JSON.stringify(cfg))
	f.close()

func server_log() -> String:
	return FileAccess.get_file_as_string(cfg_path + ".log")

func latest_json(version: String, asset := "") -> Dictionary:
	if asset == "":
		asset = UpdateCore.asset_name(version, "Linux")
	return {"tag_name": "v" + version, "html_url": "{base}/releases/tag/v" + version, "published_at": "2026-11-02T10:00:00Z",
		"draft": false, "prerelease": false,
		"body": "## New in %s\n- **Practice update.** Test line.\n- **Second line.** More." % version,
		"assets": [{"name": "SHA256SUMS.txt", "browser_download_url": "{base}/download/SHA256SUMS.txt", "size": 200},
			{"name": asset, "browser_download_url": "{base}/download/" + asset, "size": file_size(asset)}]}

func file_size(name: String) -> int:
	var f := FileAccess.open(files_dir.path_join(name), FileAccess.READ)
	return f.get_length() if f else 0

func fake_game(path: String, marker: String, mb: int = 3) -> void:
	# Random bytes (they do not compress), so the download is a few megabytes and a resumed
	# download that joined the wrong bytes would be caught by the checksum.
	var bytes := Crypto.new().generate_random_bytes(mb * 1048576)
	var head := PackedByteArray([0x7F, 0x45, 0x4C, 0x46])
	for i in 4:
		bytes[i] = head[i]
	var tail := marker.to_utf8_buffer()
	for i in 16:
		bytes[100 + i] = tail[i] if i < tail.size() else 0
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_buffer(bytes)
	f.close()

func marker_of(path: String) -> String:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return ""
	f.seek(100)
	return f.get_buffer(16).get_string_from_utf8()

func sha(path: String) -> String:
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update(FileAccess.get_file_as_bytes(path))
	return ctx.finish().hex_encode()

func start_server() -> void:
	files_dir = tmp.path_join("files")
	DirAccess.make_dir_recursive_absolute(files_dir)
	var stage := tmp.path_join("pack")
	DirAccess.make_dir_recursive_absolute(stage)
	fake_game(stage.path_join("Stellar_Defense_Console_1.1.2.x86_64"), "GAME-1.1.2")
	var tar := files_dir.path_join(UpdateCore.asset_name("1.1.2", "Linux"))
	OS.execute("tar", ["-czf", tar, "-C", stage, "Stellar_Defense_Console_1.1.2.x86_64"])
	var sums := "%s  %s\n" % [sha(tar), tar.get_file()]
	var f := FileAccess.open(files_dir.path_join("SHA256SUMS.txt"), FileAccess.WRITE)
	f.store_string(sums)
	f.close()
	cfg_path = tmp.path_join("server.json")
	write_cfg({})
	server_pid = OS.create_process("python3", [ProjectSettings.globalize_path("res://verification/update_test_server.py"), cfg_path])
	for i in range(100):
		if FileAccess.file_exists(cfg_path + ".port"):
			break
		await wait(0.1)
	var port := FileAccess.get_file_as_string(cfg_path + ".port").strip_edges()
	base = "http://127.0.0.1:%s" % port
	check(server_pid > 0 and port.is_valid_int(), "Local stand-in for GitHub started")

func make_updater(name: String) -> Node:
	var u := Updater.new()
	u.running_version = "1.1.1"
	u.platform_override = "Linux"
	u.work_dir = tmp.path_join(name + "/updates")
	u.backup_dir = tmp.path_join(name + "/backup")
	u.state_file = tmp.path_join(name + "/updates/update_state.cfg")
	u.api_url = base + "/api/latest"
	u.retry_wait_seconds = 0.2
	u.stall_seconds = 3.0
	DirAccess.make_dir_recursive_absolute(u.work_dir)
	root.add_child(u)
	return u

# ------------------------------------------------------------------
func console_checks() -> void:
	console = load("res://scenes/RadarConsole.tscn").instantiate()
	c = console.get_node("CenterContainer/Dome/Contacts")
	c.auto_spawn = false
	root.add_child(console)
	await frames(3)
	var u: Node = console.updater
	u.work_dir = tmp.path_join("console/updates")
	u.backup_dir = tmp.path_join("console/backup")
	u.state_file = tmp.path_join("console/updates/update_state.cfg")
	u.api_url = base + "/api/latest"
	u.platform_override = "Linux"
	DirAccess.make_dir_recursive_absolute(u.work_dir)
	u.load_state()
	var p: Control = console.settings_panel
	check(not console.startup_hold and console.contacts.is_processing(), "No startup hold when the console is not the main scene (tests, tools)")
	console.open_settings()
	await frames(2)
	check(p.visible and p.tab_index == 0 and p.pages[0].visible and not p.pages[1].visible and not p.pages[2].visible, "Settings opens on the GAME tab")
	check(p.tab_buttons.size() == 3 and p.tab_buttons[0].text == "GAME" and p.tab_buttons[1].text == "SYSTEM" and p.tab_buttons[2].text == "ABOUT", "Three tabs: GAME, SYSTEM, ABOUT")
	check(p.difficulty_buttons[0].is_visible_in_tree() and p.auto_jump_button.is_visible_in_tree() and not p.remember_button.is_visible_in_tree(), "GAME tab: difficulty and automatic help")
	p.step_tab(1)
	check(p.tab_index == 1 and p.remember_button.is_visible_in_tree() and p.screen_effects_button.is_visible_in_tree() \
		and p.frame_rate_button.is_visible_in_tree() and p.controller_button.is_visible_in_tree(), "SYSTEM tab: sound, screen, controller, remember")
	p.step_tab(1)
	check(p.tab_index == 2 and p.check_button.is_visible_in_tree() and p.startup_button.is_visible_in_tree() and p.github_button.is_visible_in_tree() \
		and p.data_button.is_visible_in_tree(), "ABOUT tab: CHECK NOW, CHECK AT STARTUP, links")
	p.step_tab(1)
	check(p.tab_index == 0, "Tabs wrap around (ABOUT to GAME)")
	p.step_tab(-1)
	check(p.tab_index == 2, "Tabs wrap around (GAME to ABOUT)")
	# Controller LB / RB.
	var pad: Node = console.controller
	p.show_tab(0)
	pad._press("rb")
	check(p.tab_index == 1, "Controller RB: next tab")
	pad._press("lb")
	pad._press("lb")
	check(p.tab_index == 2, "Controller LB: previous tab (wraps to ABOUT)")
	p.show_tab(2)
	await frames(1)
	check(p.about_version.text == "VERSION 1.1.1" and p.about_build.text.begins_with("LINUX X86_64") and p.about_build.text.contains("RELEASED 2026-10-26"), "ABOUT shows version, build type and release date")
	check(p.news_head.text == "WHAT'S NEW IN 1.1.1" and p.news_lines[0].visible and not p.news_lines[0].text.contains("!"), "ABOUT shows WHAT'S NEW IN 1.1.1")
	check(not p.go_back_button.visible, "GO BACK hidden while no earlier version is kept")
	check(p.startup_button.text == "ON" and console.updater.check_at_startup(), "CHECK AT STARTUP is on at first")
	p.startup_button.button_pressed = false
	p.startup_button.toggled.emit(false)
	await frames(1)
	var reread := ConfigFile.new()
	reread.load(console.updater.state_file)
	check(not bool(reread.get_value("updates", "check_at_startup", true)), "CHECK AT STARTUP OFF is saved in its own file")
	console.updater.set_check_at_startup(true)
	var vp := console.get_viewport().get_visible_rect().size
	var rect := Rect2(p.panel.global_position, p.panel.size) if "panel" in p and p.panel else Rect2()
	check(rect.size == Vector2(860, 800) and Rect2(Vector2.ZERO, vp).encloses(rect), "Settings panel 860 x 800 fits the screen")
	# Mid-battle CHECK NOW: the update is offered, UPDATE NOW greyed out.
	write_cfg({})
	console.check_for_updates_now()
	check(p.check_button.disabled and p.check_button.text == "CHECKING", "CHECK NOW turns into CHECKING while asking")
	for i in range(60):
		if not console.check_now_running:
			break
		await wait(0.1)
	await frames(2)
	var pop: Control = console.update_popup
	check(pop.visible and pop.mode == "found" and pop.update_button.disabled and pop.note.text.contains("Finish or end the battle first"), "Mid-battle: newer version shown, UPDATE NOW greyed out")
	check(pop.later_button.is_visible_in_tree() and pop.skip_button.is_visible_in_tree() and pop.title.text == "NEW VERSION AVAILABLE" and pop.sub.text.begins_with("1.1.2 for"), "Pop-up shows the new version with LATER and SKIP THIS VERSION")
	console.start_update()
	check(not console.updating, "UPDATE NOW does nothing mid-battle")
	pop.back()
	await frames(1)
	check(not pop.visible and p.visible, "B / Esc closes the pop-up back to Settings")
	check(p.about_status.text.contains("Version 1.1.2 is available"), "ABOUT status line after the check")
	# Game Over: UPDATE NOW works.
	c.hull = 0.0
	await frames(2)
	check(console.between_battles(), "Game Over counts as between battles")
	console.check_for_updates_now()
	for i in range(60):
		if not console.check_now_running:
			break
		await wait(0.1)
	await frames(2)
	check(pop.visible and not pop.update_button.disabled, "Game Over: UPDATE NOW can be pressed")
	pop.back()
	# A failed check.
	write_cfg({"api_status": 500})
	console.check_for_updates_now()
	for i in range(60):
		if not console.check_now_running:
			break
		await wait(0.1)
	await frames(2)
	check(pop.visible and pop.mode == "message" and pop.title.text == "COULD NOT CHECK FOR UPDATES", "Failed check: plain message")
	pop.back()
	check(p.about_status.text.contains("Could not reach GitHub"), "ABOUT status line after a failed check")
	# 1.1.1 fix: a refused certificate gets its own message (Windows ARM64 report).
	console.check_now_running = true
	console._on_check_done({"ok": false, "secure": true, "error": "secure connection, result 5"})
	await frames(2)
	check(pop.visible and pop.mode == "message" and pop.title.text == "COULD NOT CHECK FOR UPDATES" and pop.note.text.contains("secure connection"), "Refused certificate: secure-connection message")
	pop.back()
	# GO BACK asks first.
	var bk := ConfigFile.new()
	bk.load(console.updater.state_file)
	bk.set_value("backup", "version", "1.1.0")
	bk.set_value("backup", "item", "fake.x86_64")
	bk.save(console.updater.state_file)
	DirAccess.make_dir_recursive_absolute(console.updater.backup_dir)
	FileAccess.open(console.updater.backup_dir.path_join("fake.x86_64"), FileAccess.WRITE).store_string("x")
	console.refresh_about()
	check(p.go_back_button.visible and p.go_back_note.text == "to version 1.1.0", "GO BACK shown with the kept version")
	p.go_back_button.pressed.emit()
	await frames(1)
	check(pop.visible and pop.mode == "confirm" and pop.title.text == "GO BACK TO VERSION 1.1.0?" and pop.go_back_button.visible and pop.cancel_button.visible, "GO BACK asks to confirm first")
	pop.back()
	check(not pop.visible and FileAccess.file_exists(console.updater.backup_dir.path_join("fake.x86_64")), "CANCEL on the confirm changes nothing")
	c.hull = 1.0
	await frames(1)
	p.go_back_button.pressed.emit()
	await frames(1)
	check(pop.mode == "message" and pop.title.text == "FINISH THE BATTLE FIRST", "GO BACK mid-battle: finish the battle first")
	pop.back()
	console.updater._drop_backup()
	console.close_settings()
	write_cfg({})

# ------------------------------------------------------------------
func network_checks() -> void:
	var u: Node = make_updater("net")
	var got: Array = []
	u.check_done.connect(func(r: Dictionary) -> void: got.append(r))
	write_cfg({})
	u.check()
	for i in range(60):
		if got.size() > 0:
			break
		await wait(0.1)
	check(got.size() == 1 and got[0].ok and got[0].newer and got[0].version == "1.1.2" and got[0].asset_name == UpdateCore.asset_name("1.1.2", "Linux"), "Check finds 1.1.2 on the stand-in")
	check(server_log().contains("ua=StellarDefenseConsole/1.1.1"), "The check names the game (User-Agent)")
	var rel: Dictionary = got[0]
	# Slow answer: gives up at the time limit.
	got.clear()
	write_cfg({"api_delay": 3})
	var t0 := Time.get_ticks_msec()
	u.check(1.0)
	for i in range(60):
		if got.size() > 0:
			break
		await wait(0.1)
	check(got.size() == 1 and not got[0].ok and Time.get_ticks_msec() - t0 < 2500, "No answer in time: the check gives up quietly")
	await wait(2.5)
	# Download with a dropped connection: resumed.
	write_cfg({"drop_once": [rel.asset_name]})
	var part := tmp.path_join("net/dl.part")
	var why: String = await u.download(rel.asset_url, part, int(rel.size))
	check(why == "" and sha(part) == sha(files_dir.path_join(rel.asset_name)), "Dropped download is resumed and the file comes out whole")
	check(server_log().contains("DROP " + rel.asset_name) and server_log().contains("range=bytes="), "Resume asked only for the missing part")
	DirAccess.remove_absolute(part)
	# Always dropping: gives up after three tries.
	write_cfg({"drop_always": [rel.asset_name]})
	why = await u.download(rel.asset_url, part, int(rel.size))
	check(why == "dropped", "Download that keeps dropping stops after three tries")
	DirAccess.remove_absolute(part)
	write_cfg({})
	why = await u.download(base + "/download/nothing.zip", part)
	check(why == "http", "Missing file: download stops at once")
	u.queue_free()

func install_checks() -> void:
	# A pretend installed game in a pretend folder.
	var game_dir := tmp.path_join("game")
	DirAccess.make_dir_recursive_absolute(game_dir)
	var target := game_dir.path_join("Stellar_Defense_Console_1.1.1.x86_64")
	fake_game(target, "GAME-1.1.1")
	var u: Node = make_updater("inst")
	u.install_target_override = target
	u.dry_launch = true
	u.start_confirm_seconds = 3.0
	var rel: Dictionary = u.read_release(JSON.parse_string(JSON.stringify(latest_json("1.1.2")).replace("{base}", base)))
	var failed: Array = []
	var quit := [0]
	u.install_failed.connect(func(t: String, _x: String) -> void: failed.append(t))
	u.quit_for_update.connect(func() -> void: quit[0] += 1)
	# Wrong checksum: nothing changed.
	var sums_path := files_dir.path_join("SHA256SUMS.txt")
	var good_sums := FileAccess.get_file_as_string(sums_path)
	FileAccess.open(sums_path, FileAccess.WRITE).store_string("%s  %s\n" % ["0".repeat(64), rel.asset_name])
	var why: String = await u.update_to(rel)
	check(why == "checksum" and failed.back() == "DOWNLOAD DID NOT CHECK OUT" and marker_of(target) == "GAME-1.1.1", "Wrong checksum: update stops, game unchanged")
	check(DirAccess.get_files_at(game_dir).size() == 1, "Wrong checksum: no extra files left next to the game")
	FileAccess.open(sums_path, FileAccess.WRITE).store_string(good_sums)
	# New copy never reports a good start: put back.
	why = await u.update_to(rel)
	check(why == "no_start" and failed.back() == "NEW VERSION DID NOT START" and marker_of(target) == "GAME-1.1.1", "New version did not start: old version put back")
	check(DirAccess.get_files_at(game_dir).size() <= 2 and u.backup_version() == "", "Did not start: no backup kept, game folder clean")
	for n in DirAccess.get_files_at(game_dir):
		if n != target.get_file():
			DirAccess.remove_absolute(game_dir.path_join(n))
	# Good start: the pretend new copy writes its .ok file.
	var answer := func() -> void:
		for i in range(200):
			var pending := ConfigFile.new()
			if pending.load(u.work_dir.path_join("pending.cfg")) == OK:
				var token := str(pending.get_value("pending", "token", ""))
				if token != "" and FileAccess.file_exists(target) and marker_of(target) == "GAME-1.1.2":
					FileAccess.open(u.work_dir.path_join(token + ".ok"), FileAccess.WRITE).store_string("ok")
					return
			await wait(0.1)
	answer.call()
	why = await u.update_to(rel)
	check(why == "" and quit[0] == 1 and marker_of(target) == "GAME-1.1.2", "Good start: new version in place, old copy closes")
	check(u.backup_version() == "1.1.1" and marker_of(u.backup_dir.path_join(target.get_file())) == "GAME-1.1.1", "The replaced version is kept as the one backup")
	# The new copy tidies up.
	var nu: Node = make_updater("inst")
	nu.running_version = "1.1.2"
	nu.tidy_pending()
	await wait(0.5)
	check(DirAccess.get_files_at(game_dir) == PackedStringArray([target.get_file()]), "New copy removes the replaced file from the game folder")
	check(nu.status_line().text.begins_with("Updated from 1.1.1 today at"), "ABOUT note: Updated from 1.1.1 today at ...")
	check(not FileAccess.file_exists(u.work_dir.path_join("pending.cfg")) and not DirAccess.dir_exists_absolute(u.work_dir.path_join("staged")), "Update work files removed")
	# GO BACK from 1.1.2 to 1.1.1.
	nu.install_target_override = target
	nu.dry_launch = true
	nu.start_confirm_seconds = 3.0
	var nquit := [0]
	nu.quit_for_update.connect(func() -> void: nquit[0] += 1)
	var answer2 := func() -> void:
		for i in range(200):
			var pending := ConfigFile.new()
			if pending.load(nu.work_dir.path_join("pending.cfg")) == OK:
				var token := str(pending.get_value("pending", "token", ""))
				if token != "" and marker_of(target) == "GAME-1.1.1":
					FileAccess.open(nu.work_dir.path_join(token + ".ok"), FileAccess.WRITE).store_string("ok")
					return
			await wait(0.1)
	answer2.call()
	why = await nu.go_back()
	check(why == "" and nquit[0] == 1 and marker_of(target) == "GAME-1.1.1", "GO BACK: 1.1.1 back in place")
	check(nu.backup_version() == "" and nu.skipped_version() == "1.1.2", "GO BACK: backup used up; 1.1.2 is skipped at startup")
	var back_copy: Node = make_updater("inst")
	back_copy.tidy_pending()
	await wait(0.5)
	check(DirAccess.get_files_at(game_dir) == PackedStringArray([target.get_file()]) and back_copy.status_line().text.begins_with("Went back from 1.1.2"), "After GO BACK: folder clean, ABOUT note Went back from 1.1.2")
	# Protected folder on Linux with no permission prompt available is reported plainly.
	check(u.failure_text("protected_no_prompt").text.contains("Move the game to a folder you own"), "Protected folder message")
	u.queue_free()
	nu.queue_free()
	back_copy.queue_free()

# ------------------------------------------------------------------
func startup_console(name: String) -> Control:
	var k: Control = load("res://scenes/RadarConsole.tscn").instantiate()
	k.startup_force = true
	k.startup_splash_seconds = 1.0
	k.startup_extra_seconds = 1.5
	k.get_node("CenterContainer/Dome/Contacts").auto_spawn = false
	root.add_child(k)
	var u: Node = k.updater
	u.work_dir = tmp.path_join(name + "/updates")
	u.backup_dir = tmp.path_join(name + "/backup")
	u.state_file = tmp.path_join(name + "/updates/update_state.cfg")
	u.api_url = base + "/api/latest"
	u.platform_override = "Linux"
	DirAccess.make_dir_recursive_absolute(u.work_dir)
	u.load_state()
	return k

func startup_checks() -> void:
	if is_instance_valid(console):
		console.queue_free()
	await frames(2)
	write_cfg({})
	var before := server_log().length()
	var k := startup_console("start")
	await frames(3)
	check(k.startup_hold and not k.contacts.is_processing() and is_instance_valid(k.startup_splash) and k.startup_splash.visible, "Startup: splash shown and the battle waits")
	await wait(1.6)
	await frames(2)
	var pop: Control = k.update_popup
	check(server_log().length() > before, "Startup: quiet check asked the stand-in")
	check(pop.visible and pop.mode == "found" and not pop.update_button.disabled and k.startup_hold, "Startup: pop-up offers 1.1.2, UPDATE NOW available, battle still waiting")
	check(pop.later_button.text == "LATER" and pop.skip_button.text == "SKIP THIS VERSION" and pop.update_button.text == "UPDATE NOW", "Startup pop-up buttons LATER, SKIP THIS VERSION, UPDATE NOW")
	k.open_settings()
	check(not k.settings_open, "Settings does not open over the startup pop-up")
	pop.later_button.pressed.emit()
	await frames(2)
	check(not pop.visible and not k.startup_hold and k.contacts.is_processing(), "LATER: pop-up closes and the battle starts")
	check(k.updater.skipped_version() == "", "LATER does not skip the version")
	k.queue_free()
	await frames(2)
	# SKIP THIS VERSION.
	k = startup_console("start")
	await wait(2.0)
	pop = k.update_popup
	check(pop.visible, "Next start: offered again after LATER")
	pop.skip_button.pressed.emit()
	await frames(2)
	check(k.updater.skipped_version() == "1.1.2" and not k.startup_hold, "SKIP THIS VERSION saved, battle starts")
	k.queue_free()
	await frames(2)
	k = startup_console("start")
	await wait(2.0)
	check(not k.update_popup.visible and not k.startup_hold, "Skipped version is not offered at startup")
	k.open_settings()
	k.settings_panel.show_tab(2)
	k.check_for_updates_now()
	for i in range(60):
		if not k.check_now_running:
			break
		await wait(0.1)
	check(k.update_popup.visible and k.update_popup.sub.text.begins_with("1.1.2 for"), "CHECK NOW still offers a skipped version")
	k.update_popup.back()
	k.close_settings()
	k.queue_free()
	await frames(2)
	# A newer version than the skipped one is offered again.
	write_cfg({"latest": latest_json("1.1.2")})
	var cfgf := ConfigFile.new()
	cfgf.load(tmp.path_join("start/updates/update_state.cfg"))
	cfgf.set_value("updates", "skipped_version", "1.1.1")
	cfgf.save(tmp.path_join("start/updates/update_state.cfg"))
	k = startup_console("start")
	await wait(2.0)
	check(k.update_popup.visible, "A version newer than the skipped one is offered")
	k.update_popup.later_button.pressed.emit()
	k.queue_free()
	await frames(2)
	# CHECK AT STARTUP off: no request at all.
	k = startup_console("off")
	k.updater.set_check_at_startup(false)
	k.queue_free()
	await frames(2)
	before = server_log().length()
	k = startup_console("off")
	await wait(1.4)
	check(server_log().length() == before and not k.update_popup.visible and not k.startup_hold, "CHECK AT STARTUP OFF: no check, battle starts after the splash")
	k.queue_free()
	await frames(2)
	# Slow GitHub: CHECKING FOR UPDATES shown, then gives up and the battle starts.
	write_cfg({"api_delay": 6})
	k = startup_console("slow")
	var t0 := Time.get_ticks_msec()
	await wait(1.3)
	check(is_instance_valid(k.startup_line) and k.startup_line.visible and k.startup_line.text == "CHECKING FOR UPDATES", "Slow answer: CHECKING FOR UPDATES shown after the splash")
	await wait(1.6)
	check(not k.startup_line.visible and not k.startup_hold and not k.update_popup.visible, "Slow answer: battle starts after the extra 3 seconds (1.5 here), no pop-up")
	k.queue_free()
	await frames(2)
	# No internet: quiet.
	k = startup_console("noweb")
	k.updater.api_url = "http://127.0.0.1:9/api/latest"
	await wait(2.8)
	check(not k.update_popup.visible and not k.startup_hold, "No internet: nothing shown, battle starts")
	k.queue_free()
	# Steam builds: no check, no updater controls.
	await frames(2)
	k = startup_console("steam")
	k.updater.steam_build = true
	k.refresh_about()
	k.open_settings()
	k.settings_panel.show_tab(2)
	check(not k.settings_panel.check_button.visible and not k.settings_panel.startup_button.visible and k.settings_panel.about_build.text.begins_with("STEAM"), "Steam build: ABOUT has no update controls")
	k.close_settings()
	k.queue_free()
	await wait(3.0)
	write_cfg({})

# ------------------------------------------------------------------
func stealth_checks() -> void:
	var k: Control = load("res://scenes/RadarConsole.tscn").instantiate()
	var ct: Control = k.get_node("CenterContainer/Dome/Contacts")
	check(absf(ct.stealth_fire_range - 0.60) < 0.001, "Stealth Interceptor fires from farther out (0.60 of the radar, was 0.35)")
	check(absf(ct.stealth_shot_seconds - 3.0) < 0.001, "Second nuke 3 seconds after the first (was 4)")
	check(ct.stealth_home_turn >= 2.0, "Stealth Interceptor turns home faster (%.1f times)" % ct.stealth_home_turn)
	k.free()

# ------------------------------------------------------------------
## 1.1.1 fix: the game's own list of trusted certificate authorities, used after the
## computer's list refuses GitHub's certificate. The network part is
## verification/tls_fallback_test.py (real GitHub, authorities hidden from the engine).
func tls_checks() -> void:
	var u := Updater.new()
	root.add_child(u)
	var roots: X509Certificate = u.bundled_roots()
	check(roots != null, "TLS: the game's list of trusted authorities loads")
	var pem := FileAccess.get_file_as_string(Updater.TRUSTED_ROOTS_PATH)
	check(pem.count("BEGIN CERTIFICATE") >= 100, "TLS: the list has %d authorities" % pem.count("BEGIN CERTIFICATE"))
	check(not u.use_bundled_roots, "TLS: the computer's own list is tried first")
	check(u.switch_to_bundled_roots() and u.use_bundled_roots, "TLS: switches to the game's list after a failure")
	check(not u.switch_to_bundled_roots(), "TLS: switches only once (no endless retry)")
	check(u.tls_options() != null, "TLS: secure connection settings with the game's list")
	var cfg := FileAccess.get_file_as_string("res://export_presets.cfg")
	check(cfg.count('include_filter="*.crt"') == 4, "TLS: all four builds include the list")
	u.queue_free()

# ------------------------------------------------------------------
# 1.1.1: the game file has no version in its name, so the name is still right after an
# update (the updater keeps the running file's name). The downloads keep the version.
func naming_checks() -> void:
	var presets := ConfigFile.new()
	presets.load("res://export_presets.cfg")
	var names := {}
	for i in range(4):
		names[str(presets.get_value("preset.%d" % i, "name", ""))] = str(presets.get_value("preset.%d" % i, "export_path", "")).get_file()
	check(names.get("Windows Desktop", "") == "Stellar_Defense_Console_Windows_x64.exe", "Windows x64 game file: Stellar_Defense_Console_Windows_x64.exe (no version)")
	check(names.get("Windows Desktop ARM64", "") == "Stellar_Defense_Console_Windows_arm64.exe", "Windows ARM64 game file: Stellar_Defense_Console_Windows_arm64.exe (no version)")
	check(names.get("Linux x86_64", "") == "Stellar_Defense_Console_Linux.x86_64", "Linux game file: Stellar_Defense_Console_Linux.x86_64 (no version)")
	check(names.get("macOS", "") == "Stellar_Defense_Console_1.1.1_Mac.zip", "Mac download keeps the version; the app inside is Stellar Defense Console.app")
	check(UpdateCore.asset_name("1.1.2", "Windows_arm64") == "Stellar_Defense_Console_1.1.2_Windows_arm64.exe.zip", "Download names on GitHub still carry the version")
