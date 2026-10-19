extends Node
## 1.05 diagnostic session log, to help explain freezes and crashes.
##
## One small text file per play session in the game's app data folder:
##   Mac:     ~/Library/Application Support/Godot/app_userdata/Stellar Defense Console/logs/
##   Windows: %APPDATA%\Godot\app_userdata\Stellar Defense Console\logs\
## Settings > OPEN LOG FOLDER opens it. Every line is written to disk at once, so
## the file survives a crash or a forced close. The last 10 files are kept.
## The log holds no personal data: no names, no folder paths, no typed text.
##
## Lines:
##   START      version, system, CPU, screen, graphics driver and GPU, settings
##   HEARTBEAT  every 10 s: battle time, FPS, slowest frame, paused, Settings open,
##              contacts and the clicks, taps and keys received since the last one
##   EVENT      Settings opened/closed, difficulty, waves, JUMP, game over, Retry, Quit
##   STALL      no frame drawn for 2 s or more (a background check); RECOVERED after
##   SCRIPT     script errors and warnings copied from Godot (Godot 4.5 and newer)

## Untick to stop writing session logs (Godot's own godot.log is not affected).
@export var enabled: bool = true
@export var log_folder: String = "user://logs"
@export_range(1, 50) var keep_files: int = 10
## Each file stops growing at about this size (bytes).
@export_range(50000, 10000000) var max_file_bytes: int = 1000000
@export_range(2.0, 120.0) var heartbeat_seconds: float = 10.0
## A gap of this many seconds without a drawn frame is logged as a STALL.
@export_range(0.5, 30.0) var stall_seconds: float = 2.0

const FILE_PREFIX := "radar_session_"
const FILE_SUFFIX := ".log"

var file_path: String = ""
var lines_written: int = 0
var bytes_written: int = 0
var stalls_logged: int = 0
var limit_reached: bool = false
var console: Node
var _file: FileAccess
var _mutex := Mutex.new()
var _thread: Thread
var _watching: bool = false
var _last_frame_msec: int = 0
var _stall_started_msec: int = 0
var _stalled: bool = false
var _next_heartbeat_msec: int = 0
var _slowest_frame: float = 0.0
var _clicks: int = 0
var _taps: int = 0
var _keys: int = 0
## 1.0.0: controller presses since the last heartbeat (counted by ControllerInput.gd,
## which consumes controller events before this node sees them).
var _pads: int = 0
var _logger: Object
var _started_msec: int = 0
## Written after the start-up lines (how script errors are copied on this Godot).
var _error_copy_note: String = ""

## Opens a new session file, removes the oldest ones and starts the freeze watcher.
func start(owner_console: Node) -> void:
	console = owner_console
	if not enabled or _file != null:
		return
	_started_msec = Time.get_ticks_msec()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(log_folder))
	_remove_old_files(keep_files - 1)
	var stamp := Time.get_datetime_string_from_system(false, false).replace(":", "-").replace("T", "_")
	file_path = "%s/%s%s%s" % [log_folder, FILE_PREFIX, stamp, FILE_SUFFIX]
	var serial := 2
	while FileAccess.file_exists(file_path):
		file_path = "%s/%s%s-%d%s" % [log_folder, FILE_PREFIX, stamp, serial, FILE_SUFFIX]
		serial += 1
	_file = FileAccess.open(file_path, FileAccess.WRITE)
	if _file == null:
		push_warning("Session log could not be created (error %d)" % FileAccess.get_open_error())
		return
	_last_frame_msec = Time.get_ticks_msec()
	_next_heartbeat_msec = _last_frame_msec + int(heartbeat_seconds * 1000.0)
	if not RenderingServer.frame_post_draw.is_connected(_on_frame_drawn):
		RenderingServer.frame_post_draw.connect(_on_frame_drawn)
	_watching = true
	_thread = Thread.new()
	_thread.start(_watch)
	_add_script_error_logger()

## Writes one line, flushed to disk straight away. Safe to call from any thread.
func write(kind: String, text: String) -> void:
	_mutex.lock()
	if _file != null and not limit_reached:
		var line := "%s %8.1f %-9s %s" % [Time.get_time_string_from_system(), (Time.get_ticks_msec() - _started_msec) / 1000.0, kind, text]
		# Room is kept for the final "limit reached" line, so the file stays under the limit.
		if bytes_written + line.length() + 1 > max_file_bytes - 120:
			limit_reached = true
			line = "%s %8.1f %-9s %s" % [Time.get_time_string_from_system(), (Time.get_ticks_msec() - _started_msec) / 1000.0, "LIMIT", "file size limit reached; logging stops for this session"]
		_file.store_line(line)
		_file.flush()
		lines_written += 1
		bytes_written += line.length() + 1
	_mutex.unlock()

func event(text: String) -> void:
	write("EVENT", text)

## The start-up line: build, system and settings (no names or paths).
func write_start(version_text: String, settings: Dictionary, difficulty_name: String, autos: int) -> void:
	var screen := DisplayServer.screen_get_size(DisplayServer.window_get_current_screen()) if DisplayServer.get_name() != "headless" else Vector2i.ZERO
	var window := DisplayServer.window_get_size() if DisplayServer.get_name() != "headless" else Vector2i.ZERO
	write("START", "%s | Godot %s | %s %s | CPU %s, %d threads | screen %dx%d, window %dx%d, scale %.2f" % [
		version_text, Engine.get_version_info().string, OS.get_name(), OS.get_version(),
		Engine.get_architecture_name(), OS.get_processor_count(),
		screen.x, screen.y, window.x, window.y, DisplayServer.screen_get_scale() if DisplayServer.get_name() != "headless" else 1.0])
	write("START", "graphics driver %s | display %s | GPU %s / %s | API %s" % [
		rendering_driver_name(), DisplayServer.get_name(),
		RenderingServer.get_video_adapter_vendor(), RenderingServer.get_video_adapter_name(),
		RenderingServer.get_video_adapter_api_version()])
	write("START", "difficulty %s | auto options %d (battery %s, firewall %s, interceptors %s, gunships %s, jump %s, repair %s) | effects %d%%%s | radar %d%%%s | remember settings %s" % [
		difficulty_name, autos, _on(settings.auto_battery), _on(settings.auto_firewall), _on(settings.auto_interceptors),
		_on(settings.auto_gunships), _on(settings.auto_jump), _on(settings.auto_repair),
		settings.effects_volume, " muted" if settings.effects_muted else "",
		settings.radar_volume, " muted" if settings.radar_muted else "", _on(settings.remember_settings)])
	if _error_copy_note != "":
		write("NOTE", _error_copy_note)

## The graphics driver in use, for example "opengl3" or "opengl3_angle". Read through
## whichever call this Godot version has, so 4.4 and newer all run.
func rendering_driver_name() -> String:
	for source in [OS, RenderingServer]:
		if source.has_method("get_current_rendering_driver_name"):
			return str(source.call("get_current_rendering_driver_name"))
	return "%s (project setting)" % ProjectSettings.get_setting("rendering/gl_compatibility/driver", "?")

func _on(value: bool) -> String:
	return "on" if value else "off"

func _input(event_in: InputEvent) -> void:
	if event_in is InputEventMouseButton and event_in.pressed:
		_clicks += 1
	elif event_in is InputEventScreenTouch and event_in.pressed:
		_taps += 1
	elif event_in is InputEventKey and event_in.pressed and not event_in.echo:
		_keys += 1

## 1.0.0: one controller button press (so controller-only play is not idle).
func count_controller_press() -> void:
	_pads += 1

func _process(delta: float) -> void:
	if _file == null:
		return
	_slowest_frame = maxf(_slowest_frame, delta)
	var now := Time.get_ticks_msec()
	if now >= _next_heartbeat_msec:
		_next_heartbeat_msec = now + int(heartbeat_seconds * 1000.0)
		write("HEARTBEAT", heartbeat_text())
		_slowest_frame = 0.0
		_clicks = 0
		_taps = 0
		_keys = 0
		_pads = 0

func heartbeat_text() -> String:
	var battle_time := 0.0
	var contact_count := 0
	var settings_open := false
	var battle_paused := false
	if is_instance_valid(console):
		var c: Node = console.get("contacts")
		if is_instance_valid(c):
			battle_time = c.battle_time
			contact_count = c.contacts.size()
			battle_paused = not c.is_processing()
		settings_open = console.get("settings_open")
	return "battle %.1fs | fps %d | slowest frame %d ms | paused %s | settings %s | contacts %d | input clicks %d, taps %d, keys %d, controller %d" % [
		battle_time, Engine.get_frames_per_second(), roundi(_slowest_frame * 1000.0),
		"yes" if battle_paused or get_tree().paused else "no", "open" if settings_open else "closed",
		contact_count, _clicks, _taps, _keys, _pads]

## Main thread, after each frame is drawn: the freeze watcher's clock.
func _on_frame_drawn() -> void:
	_mutex.lock()
	_last_frame_msec = Time.get_ticks_msec()
	var recovered := _stalled
	var stall_length := (_last_frame_msec - _stall_started_msec) / 1000.0
	_stalled = false
	_mutex.unlock()
	if recovered:
		write("RECOVERED", "frames resumed after %.1f s without a drawn frame" % stall_length)

## Background thread: checks four times a second whether frames are still drawn.
func _watch() -> void:
	while true:
		OS.delay_msec(250)
		_mutex.lock()
		var keep_going := _watching
		var gap := Time.get_ticks_msec() - _last_frame_msec
		var report := false
		if keep_going and not _stalled and gap >= int(stall_seconds * 1000.0):
			_stalled = true
			_stall_started_msec = _last_frame_msec
			stalls_logged += 1
			report = true
		_mutex.unlock()
		if not keep_going:
			return
		if report:
			write("STALL", "no frame drawn for %.1f s (watch continues)" % (gap / 1000.0))

## Script errors and warnings are copied into the log on Godot 4.5 and newer (the
## Logger API). The code is compiled only when the engine has it, so 4.4 still runs.
func _add_script_error_logger() -> void:
	if not ClassDB.class_exists("Logger") or not OS.has_method("add_logger"):
		_error_copy_note = "script error copying needs Godot 4.5 or newer; godot.log still has them"
		return
	var script := GDScript.new()
	script.source_code = """extends Logger
var target: WeakRef
func _log_error(function: String, file: String, line: int, code: String, rationale: String, editor_notify: bool, error_type: int, script_backtraces: Array[ScriptBacktrace]) -> void:
	var log = target.get_ref()
	if log == null:
		return
	var kind := "SCRIPT" if error_type != 1 else "WARNING"
	var text := rationale if rationale != "" else code
	var where := "%s:%d %s" % [file.get_file(), line, function]
	# For GDScript errors, name the game script and line rather than the engine source.
	for trace in script_backtraces:
		if trace != null and trace.get_frame_count() > 0:
			where = "%s:%d %s" % [trace.get_frame_file(0).get_file(), trace.get_frame_line(0), trace.get_frame_function(0)]
			break
	log.write(kind, "%s (%s)" % [text, where])
func _log_message(message: String, error: bool) -> void:
	if not error:
		return
	var log = target.get_ref()
	if log != null:
		log.write("STDERR", message.strip_edges())
"""
	if script.reload() != OK:
		_error_copy_note = "script error copying unavailable on this Godot version"
		return
	_error_copy_note = "script errors and warnings are copied into this log"
	_logger = script.new()
	_logger.set("target", weakref(self))
	OS.call("add_logger", _logger)

## Stops the watcher and closes the file. Called on exit; safe to call twice.
func stop(reason: String = "exit") -> void:
	if _thread != null:
		_mutex.lock()
		_watching = false
		_mutex.unlock()
		_thread.wait_to_finish()
		_thread = null
	if _logger != null:
		OS.call("remove_logger", _logger)
		_logger = null
	if RenderingServer.frame_post_draw.is_connected(_on_frame_drawn):
		RenderingServer.frame_post_draw.disconnect(_on_frame_drawn)
	if _file != null:
		write("END", reason)
		_mutex.lock()
		_file.close()
		_file = null
		_mutex.unlock()

func _exit_tree() -> void:
	stop("exit")

## Session files in the log folder, oldest first (names sort by date and time).
func session_files() -> PackedStringArray:
	var names := PackedStringArray()
	var dir := DirAccess.open(log_folder)
	if dir == null:
		return names
	for name in dir.get_files():
		if name.begins_with(FILE_PREFIX) and name.ends_with(FILE_SUFFIX):
			names.append(name)
	names.sort()
	return names

## Deletes the oldest session files so that at most `keep` remain.
func _remove_old_files(keep: int) -> void:
	var names := session_files()
	var extra := names.size() - maxi(0, keep)
	for index in range(maxi(0, extra)):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(log_folder + "/" + names[index]))

## Full path of the log folder, for Settings > OPEN LOG FOLDER.
func folder_path() -> String:
	return ProjectSettings.globalize_path(log_folder)
