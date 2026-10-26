extends Control
## 1.2.0: the Breacher warning box always holds this many text lines.
const HACK_BOX_LINES := 5
var _hack_text_height: float = -1.0

## 1.2.0: the real height of five lines of warning text (measured once).
func hack_text_height() -> float:
	if _hack_text_height < 0.0:
		var alert: Label = $HackAlert
		var held := alert.text
		alert.text = "\n".join(PackedStringArray(["W", "W", "W", "W", "W"]).slice(0, HACK_BOX_LINES))
		_hack_text_height = alert.get_minimum_size().y
		alert.text = held
	return _hack_text_height
##
## RADAR Console - top-level scene.
##
## Hosts the animated dome, sample contacts, gameplay buttons, and the
## live tuning panel (press F1 to toggle).
##

const HighScores = preload("res://scripts/HighScores.gd")
const GameSettings = preload("res://scripts/GameSettings.gd")
const SettingsPanel = preload("res://scripts/SettingsPanel.gd")
## 1.0.7: test start screen for the Convoy Test build only.
const ConvoyTestPicker = preload("res://scripts/ConvoyTestPicker.gd")
const BonusPickPanel = preload("res://scripts/BonusPickPanel.gd")
const SessionLog = preload("res://scripts/SessionLog.gd")
const ControllerInput = preload("res://scripts/ControllerInput.gd")
const ControllerPanel = preload("res://scripts/ControllerPanel.gd")
const DamageEffects = preload("res://scripts/DamageEffects.gd")
## 1.1.1: in-place updates and the ABOUT tab.
const UpdateCore = preload("res://scripts/UpdateCore.gd")
const Updater = preload("res://scripts/Updater.gd")
const UpdatePopup = preload("res://scripts/UpdatePopup.gd")
## 1.1.1: what's new in this version (ABOUT tab). Short, plain lines.
const WHATS_NEW: Array[String] = [
	"Tabbed Settings: GAME, SYSTEM and ABOUT",
	"Updates from the ABOUT tab, and a quiet check at startup",
	"Stealth Interceptor fires from farther out",
	"Second nuke 3 seconds after the first; faster turn home",
]

@export_group("Audio Mix")
@export_range(-40.0, 0.0) var sweep_volume_db: float = -20.0

@export_group("Build")
## Tick to show the RADAR level and F1 hint and allow the F1 tuning panel (tuning only).
## Off by default from 1.04, so normal play and exported builds hide both labels and F1.
@export var development_build: bool = false
## Test builds add "TEST" to the version shown in Settings and in the session log.
## Off from 1.06 (full builds). The number itself comes from Project Settings >
## Application > Config > Version.
@export var test_build: bool = false
## Pop-up help text when the mouse rests on a button. Off from 1.06, because the
## pop-ups covered the button text. The help text is kept; tick to show it again.
@export var show_hover_tooltips: bool = false
## How quickly the score display counts up toward the real score.
@export_range(1.0, 20.0) var score_count_speed: float = 6.0

@export_group("Display")
## F11 switches between a window and full screen (Esc also leaves full screen).
## On a Mac keyboard you may need Fn-F11.
@export var fullscreen_key_enabled: bool = true
## At startup, size the window to the screen it opens on, so high-resolution
## (4K, Retina) screens do not get a small window. Keeps the 16:9 shape.
@export var fit_window_to_screen: bool = true
## Share of the usable screen (inside the menu bar, taskbar and Dock) the window fills.
@export_range(0.5, 1.0) var window_screen_fraction: float = 0.85

@export_group("Settings")
## Player choices from the gear icon (volumes, mutes, difficulty, auto options).
@export var settings_file: String = "user://radar_settings.cfg"
## Starting Effects volume for a new player. 50% is about 6 dB quieter than before.
@export_range(0, 100, 5) var default_effects_volume: int = 50
## Starting RADAR volume. 100% keeps the approved -20 dB sweep level.
@export_range(0, 100, 5) var default_radar_volume: int = 100
## Gear icon position and size in the header (1920 x 1080 layout).
@export var gear_rect := Rect2(1480, 50, 60, 60)

## 1.0.0: controller button assignments (own file; Settings > DEFAULTS leaves them alone).
@export var controller_file: String = "user://controller_bindings.cfg"

@export_group("Missile Bonus Pick")
## 0.1.2: when both missile bonuses are earned the battle pauses and the player picks
## one. With no pick in this many seconds the current bonus is kept. 1.0.5: 20 s, and the
## countdown stops once the player moves the mouse, presses an arrow key or uses a controller.
@export_range(3.0, 60.0) var bonus_pick_seconds: float = 20.0
## Small tag over the other choice when the pick is offered again after a set.
@export var bonus_pick_set_tag: String = "YOU CAN SWITCH TO"

@export_group("Diagnostic Log")
## 1.05 session log in the app data "logs" folder (click the version text in Settings).
## Stays on in final builds; holds no personal data.
@export var session_log_enabled: bool = true
## Seconds between HEARTBEAT lines.
@export_range(2.0, 120.0) var log_heartbeat_seconds: float = 10.0
## A gap this long without a drawn frame is logged as a STALL.
@export_range(0.5, 30.0) var log_stall_seconds: float = 2.0
## How many session files to keep (oldest are deleted).
@export_range(1, 50) var log_keep_files: int = 10
## 1.0.2: the controller check is written again this many seconds after start.
@export_range(1.0, 30.0) var controller_check_delay: float = 3.0

## 1.08: the Settings version text opens this page.
@export var github_url: String = "https://github.com/S8619G/Stellar-Defense-Console"

@export_group("High Scores")
## Saved in Godot's user data folder, so scores persist between runs.
@export var high_score_file: String = "user://radar_high_scores.json"
@export_range(3, 20) var high_score_slots: int = 10
## 1.08: small BEST score on the SCORE caption line, to its left (there is no room
## above it inside the header frame).
@export var show_best_score: bool = true
@export_range(10, 24) var best_score_font_size: int = 15
@export var best_score_color := Color(0.72, 0.66, 0.70, 0.85)
## 1.08: hovering or tapping a high-score entry shows its battle stats.
@export var show_score_stats: bool = true
## 1.0.9: how solid the high score stats box is (1 = fully solid; 1.0.8 used 0.96). The Game
## Over score screen's own background is the StyleBox_game_over colour in the scene (0.8).
@export_range(0.2, 1.0) var stats_box_opacity: float = 0.8
## 1.0.9: dark outline around the Game Over and stats box text so it reads through the
## see-through background (0 = none).
@export_range(0, 12) var score_screen_text_outline: int = 5

@export_group("Frame Rate and Idle Screens")
## 1.1.0 FRAME RATE setting: STANDARD draws at most this many frames a second.
@export_range(30, 240) var standard_max_fps: int = 60
## 1.1.0: SMOOTH matches the screen's refresh rate (V-Sync stays on). When the rate is
## unknown it uses this. Never below Standard Max Fps, never without a limit.
@export_range(60, 480) var smooth_fallback_fps: int = 144
## 1.1.0: on the Game Over screen, the Settings screen (the pause) the game draws at this
## many frames a second, and after Idle Sleep Seconds with no input it stops asking the
## computer to stay awake. Any key, mouse or controller input restarts the wait.
@export var idle_screens_enabled: bool = true
@export_range(1, 60) var idle_max_fps: int = 10
@export_range(10.0, 3600.0) var idle_sleep_seconds: float = 300.0
## 1.1.0: true while an idle screen is up; seconds with no input on it; and whether the
## game is asking the computer to stay awake.
var idle_screen_active: bool = false
var idle_seconds: float = 0.0
var keep_awake: bool = true
var _idle_last_msec: int = 0
## 1.1.0: the regression gate sets SDC_NO_FRAME_CAP=1 so older timing checks run as in
## 1.0.9; the frame-rate checks turn the limit back on.
var frame_cap_disabled: bool = OS.get_environment("SDC_NO_FRAME_CAP") == "1"

@export_group("Battle Readout")
## 1.1.0: the left-side readout lists enemies destroyed this battle (by every source),
## then our losses. EMP CHARGES is the last line, in the EMP blast color
## (Contacts > EMP Defense > Emp Color).
@export_range(10, 24) var readout_font_size: int = 16

var shown_score: float = 0.0
var was_defeated: bool = false
## 1.0.8: damage effects (nuke-hit scramble, red SYSTEMS OFFLINE screen).
var damage_effects: DamageEffects
## 1.0.8: true from the ship being destroyed until Retry / New Battle.
var sweep_stopped: bool = false
var _sweep_fade_left: float = 0.0
var entry_active: bool = false
var entry_letters: Array[int] = [0, 0, 0]
var entry_slot: int = 0
var board: Dictionary = {"scores": [], "last_initials": "AAA", "note": ""}
var highlight_row: int = -1
var score_rows: Array[Array] = []
var settings: Dictionary = GameSettings.DEFAULTS.duplicate()
var settings_open: bool = false
## 0.1.2 missile bonus pick prompt (battle paused while open).
var bonus_pick_panel: Control
var bonus_pick_open: bool = false
var _bonus_pick_were_processing: bool = true
var settings_saved: bool = true
var gear_button: Button
var screen_flash: ColorRect
var settings_panel: Control
var _contacts_were_processing: bool = true
var game_over_quit_button: Button
## Tests set this so QUIT is recorded without closing the program.
var quit_dry_run: bool = false
var quit_requests: int = 0
var fitted_window_size := Vector2i.ZERO
## 1.05 diagnostic session log (see scripts/SessionLog.gd).
var session_log: Node
## Tests set this so opening the log folder is recorded without opening a window.
var shell_dry_run: bool = false
var log_folder_opens: int = 0
var github_opens: int = 0
## The last folder or page handed to the system (for tests).
var last_shell_target: String = ""
## 1.1.1: updates (scripts/Updater.gd) and the update pop-up.
var updater: Node
var update_popup: Control
## The startup check holds the first battle (splash, then up to startup_extra_seconds).
var startup_hold: bool = false
var startup_check_running: bool = false
var startup_splash: Control
var startup_line: Label
## Seconds the splash shows (the engine's own splash is now only shown while loading).
@export var startup_splash_seconds: float = 4.0
## The check may run on this long after the splash before the battle starts anyway.
@export var startup_extra_seconds: float = 3.0
## Tests: run the startup steps even though this console is not the running game.
var startup_force: bool = false
var startup_finished: bool = false
var startup_popup_shown: bool = false
var pending_release: Dictionary = {}
var check_now_running: bool = false
var updating: bool = false
## Where the update pop-up came from: "startup" or "about".
var update_popup_source: String = ""

@onready var dome: Control = $CenterContainer/Dome
@onready var tuning_panel: Panel = $TuningPanel
@onready var sweep_loop: AudioStreamPlayer = $SweepLoop
@onready var contacts: Control = $CenterContainer/Dome/Contacts
@onready var launch_button: Button = $BottomButtons/LaunchInterceptors
@onready var jump_button: Button = $BottomButtons/Jump
@onready var prox_button: Button = $BottomButtons/ProxDefense
@onready var firewall_button: Button = $BottomButtons/Firewall
@onready var battle_readout: Label = $BattleReadout
@onready var battle_status: Label = $BattleStatus
@onready var restart_button: Button = $CenterContainer/Dome/GameOverPanel/Retry
@onready var game_over_panel: Panel = $CenterContainer/Dome/GameOverPanel
@onready var gunship_button: Button = $BottomButtons/LaunchGunship
@onready var nuclear_alert: Label = $NuclearAlert
## 1.2.7: the status and nuclear alert font sizes set in the scene (the safety net shrinks from these).
@onready var status_base_size: int = battle_status.get_theme_font_size("font_size")
@onready var nuclear_base_size: int = nuclear_alert.get_theme_font_size("font_size")
@onready var repair_button: Button = $BottomButtons/RapidRepair
@onready var score_label: Label = $ScoreValue
## 1.07: right half of the split FIREWALL button, shown only while the EMP is offered.
var emp_split_button: Button
var firewall_split := false
## 1.0.0 controller support (scripts/ControllerInput.gd) and its Settings panel.
var controller: Node
var controller_panel: Control
## 1.08: BEST score line and the high-score stats box.
var best_label: Label
var stats_box: PanelContainer
var stats_label: Label
var stats_row: int = -1
var stats_pinned: bool = false
## 1.1.0: EMP CHARGES line under the battle readout, in the EMP blast color.
var emp_readout: Label
var pulse_readout: Label

func _ready() -> void:
	tuning_panel.visible = false  # F1 opens tuning without obscuring the game HUD.
	_wire_tuning_controls()
	_ensure_audio_loops()
	_build_high_score_board()
	_build_best_label()
	_center_title()
	_build_settings()
	_build_game_over_quit()
	_apply_score_screen_outline()
	_apply_tooltip_setting(self)
	$ShipStatus.emp_used.connect(func() -> void: log_event("EMP used | %d charge%s left" % [contacts.emp_charges, "" if contacts.emp_charges == 1 else "s"]))
	_build_emp_split_button()
	_build_emp_readout()
	_build_controller()
	# Only when this console is the running game (not inside a test script).
	call_deferred("_fit_window_on_start")
	# 1.1.1: splash, quiet update check and the good-start report after an update.
	call_deferred("_begin_startup")
	# 1.0.7: the Protect the convoy test start screen, only in the Convoy Test build.
	if ConvoyTestPicker.wanted():
		var picker := ConvoyTestPicker.new()
		picker.z_index = 2
		add_child(picker)
		picker.call_deferred("setup", self, contacts)

# ------------------------------------------------------------------
# Settings (gear icon, top right): volumes, mutes, difficulty, auto options.
# ------------------------------------------------------------------
func _build_settings() -> void:
	var defaults := GameSettings.DEFAULTS.duplicate()
	defaults.effects_volume = default_effects_volume
	defaults.radar_volume = default_radar_volume
	# With Remember Settings OFF, difficulty and the auto options start from their defaults.
	settings = GameSettings.startup(GameSettings.load_settings(settings_file, defaults), defaults)
	# Sounds play through two buses so each slider keeps the existing balance.
	sweep_loop.bus = GameSettings.RADAR_BUS
	for player in find_children("*", "AudioStreamPlayer", true, false):
		if player != sweep_loop:
			player.bus = GameSettings.EFFECTS_BUS
	if not get_tree().node_added.is_connected(_on_node_added):
		get_tree().node_added.connect(_on_node_added)
	# 1.0.8: damage effects over the inner console (nuke-hit scramble, SYSTEMS OFFLINE).
	# Drawn after all the console's own content; the score screen and pop-ups draw above it.
	damage_effects = DamageEffects.new()
	add_child(damage_effects)
	move_child(damage_effects, tuning_panel.get_index())
	contacts.nuke_hit_ship.connect(_on_nuke_hit_ship)
	game_over_panel.z_index = 1
	_apply_settings()
	contacts.active_difficulty = contacts.difficulty  # first battle uses the saved choice
	# Brief warm flash over the console when a nuke explodes (strength set on Contacts).
	screen_flash = ColorRect.new()
	screen_flash.name = "ScreenFlash"
	screen_flash.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	screen_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	screen_flash.color = Color(1.0, 0.9, 0.74, 0.0)
	var glow := CanvasItemMaterial.new()
	glow.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	screen_flash.material = glow
	add_child(screen_flash)
	move_child(screen_flash, tuning_panel.get_index())
	gear_button = Button.new()
	gear_button.name = "SettingsGear"
	gear_button.icon = _gear_icon()
	gear_button.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	gear_button.expand_icon = false
	_tip(gear_button, "Settings: volume, difficulty, auto options and Quit")
	gear_button.position = gear_rect.position
	gear_button.size = gear_rect.size
	gear_button.pressed.connect(toggle_settings)
	add_child(gear_button)
	move_child(gear_button, tuning_panel.get_index())
	settings_panel = SettingsPanel.new()
	settings_panel.name = "SettingsPanel"
	settings_panel.contacts = contacts
	settings_panel.defaults = defaults
	settings_panel.show_tooltips = show_hover_tooltips
	add_child(settings_panel)
	move_child(settings_panel, tuning_panel.get_index())
	settings_panel.changed.connect(_on_settings_changed)
	settings_panel.close_requested.connect(close_settings)
	settings_panel.new_battle_requested.connect(_on_new_battle_from_settings)
	settings_panel.effects_preview.connect(_preview_effects)
	settings_panel.quit_requested.connect(quit_game)
	settings_panel.open_logs_requested.connect(open_log_folder)
	settings_panel.open_github_requested.connect(open_github_page)
	settings_panel.version_text = version_text()
	_build_updates()
	bonus_pick_panel = BonusPickPanel.new()
	bonus_pick_panel.name = "BonusPickPanel"
	add_child(bonus_pick_panel)
	move_child(bonus_pick_panel, tuning_panel.get_index())
	bonus_pick_panel.picked.connect(_on_bonus_picked)
	controller_panel = ControllerPanel.new()
	controller_panel.name = "ControllerPanel"
	add_child(controller_panel)
	move_child(controller_panel, tuning_panel.get_index())
	controller_panel.bindings_changed.connect(_on_controller_bindings_changed)
	controller_panel.close_requested.connect(close_controller_panel)
	settings_panel.controller_requested.connect(open_controller_panel)
	contacts.missile_bonus_offer.connect(open_bonus_pick)
	# 1.0.8: pop-ups stay above the score screen (which is above the damage effects).
	for popup in [gear_button, settings_panel, bonus_pick_panel, controller_panel, tuning_panel]:
		(popup as CanvasItem).z_index = 2
	# 1.1.1: the update pop-up and the startup splash are in front of everything.
	update_popup.z_index = 3
	move_child(update_popup, -1)
	# One line in Godot's log file per start, to help match a log to a build.
	print("[RADAR] Stellar Defense Console %s | %s | difficulty %s | auto options %d | remember settings %s" % [
		ProjectSettings.get_setting("application/config/version", "?"), OS.get_name(),
		GameSettings.DIFFICULTY_NAMES[settings.difficulty], contacts.auto_options_on(),
		"on" if settings.remember_settings else "off"])
	_start_session_log()

# ------------------------------------------------------------------
# Version text and diagnostic session log (1.05)
# ------------------------------------------------------------------
## Sets a button's hover help text; it is shown only with Show Hover Tooltips (1.06).
func _tip(control: Control, text: String) -> void:
	control.set_meta("hover_tip", text)
	control.tooltip_text = text if show_hover_tooltips else ""

## Scene buttons with help text typed in the editor follow the same switch.
func _apply_tooltip_setting(root: Node) -> void:
	for node in root.find_children("*", "Control", true, false):
		var control := node as Control
		if not control.tooltip_text.is_empty():
			control.set_meta("hover_tip", control.tooltip_text)
			if not show_hover_tooltips:
				control.tooltip_text = ""

## Product title and version; RADAR is the sensor display label, not the game title.
func version_text() -> String:
	return "STELLAR DEFENSE CONSOLE %s%s" % [ProjectSettings.get_setting("application/config/version", "?"), " TEST" if test_build else ""]

func _start_session_log() -> void:
	session_log = SessionLog.new()
	session_log.name = "SessionLog"
	session_log.enabled = session_log_enabled
	session_log.heartbeat_seconds = log_heartbeat_seconds
	session_log.stall_seconds = log_stall_seconds
	session_log.keep_files = log_keep_files
	add_child(session_log)
	session_log.start(self)
	session_log.write_start(version_text(), settings, GameSettings.DIFFICULTY_NAMES[settings.difficulty], contacts.auto_options_on())
	contacts.wave_changed.connect(func(number: int) -> void: log_event("wave %d" % number))
	contacts.jump_offline_changed.connect(func(offline: bool) -> void: log_event("JUMP %s | hull %d%%" % ["offline (hack breach)" if offline else "back online", roundi(contacts.hull)]))
	contacts.stealth_event.connect(func(message: String) -> void: log_event(message))
	contacts.battle_event.connect(func(message: String) -> void: log_event(message))
	contacts.jump_completed.connect(func() -> void: log_event("JUMP jump | hull %d%% | auto %s" % [roundi(contacts.hull), "yes" if contacts.auto_jump else "no"]))

## 1.09: window focus changes go to the session log (for freeze reports).
func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		log_event("window lost focus")
		# 1.0.0: a release may be missed while unfocused; never finish a held Jump.
		if is_instance_valid(controller):
			controller.release_all("window lost focus")
	elif what == NOTIFICATION_APPLICATION_FOCUS_IN:
		log_event("window focused")

## Writes one EVENT line to the session log (no-op when logging is off).
func log_event(text: String) -> void:
	if is_instance_valid(session_log):
		session_log.event("%s | battle %.1fs" % [text, contacts.battle_time])

## Settings "!" icon (1.08): shows the app data folder, with the session logs in its
## "logs" folder, in Finder or Explorer.
func open_log_folder() -> int:
	log_folder_opens += 1
	var logs: String = session_log.folder_path() if is_instance_valid(session_log) else ProjectSettings.globalize_path("user://logs")
	DirAccess.make_dir_recursive_absolute(logs)
	var path: String = OS.get_user_data_dir()
	last_shell_target = path
	log_event("open app data folder")
	if shell_dry_run:
		return OK
	return OS.shell_open(path)

## Settings version link (1.08): opens the GitHub page in the default browser.
func open_github_page() -> int:
	github_opens += 1
	last_shell_target = github_url
	log_event("open GitHub page")
	if shell_dry_run or github_url.is_empty():
		return OK
	return OS.shell_open(github_url)

func _on_node_added(node: Node) -> void:
	if node is AudioStreamPlayer and node != sweep_loop and is_ancestor_of(node):
		node.bus = GameSettings.EFFECTS_BUS

func _apply_settings() -> void:
	GameSettings.apply_audio(settings)
	contacts.difficulty = settings.difficulty
	contacts.auto_defense_battery = settings.auto_battery
	contacts.auto_firewall = settings.auto_firewall
	contacts.auto_launch_interceptors = settings.auto_interceptors
	contacts.auto_launch_gunships = settings.auto_gunships
	contacts.auto_jump = settings.auto_jump
	contacts.auto_rapid_repair = settings.auto_repair
	if damage_effects:
		damage_effects.set_screen_effects(settings.screen_effects)
	_apply_frame_rate()

# ------------------------------------------------------------------
# 1.1.0: FRAME RATE setting and idle screens
# ------------------------------------------------------------------
## Frames a second for the chosen FRAME RATE: STANDARD 60, SMOOTH the screen's rate.
func chosen_max_fps() -> int:
	if not settings.get("smooth_frame_rate", false):
		return standard_max_fps
	var rate := roundi(DisplayServer.screen_get_refresh_rate())
	if rate <= 0:
		rate = smooth_fallback_fps
	return maxi(standard_max_fps, rate)

## The frame-rate limit right now: Idle Max Fps on an idle screen, else the chosen rate.
## Headless test runs (no window) keep no limit, as in 1.0.9.
func target_max_fps() -> int:
	if DisplayServer.get_name() == "headless" or frame_cap_disabled:
		return 0
	if idle_screen_active:
		return idle_max_fps
	return chosen_max_fps()

func _apply_frame_rate() -> void:
	Engine.max_fps = target_max_fps()

## Game Over (from the ship being destroyed), the Settings screen (the pause) and its
## Controller panel. The bonus pick pop-up closes by itself and is not included.
func idle_screen_wanted() -> bool:
	return idle_screens_enabled and (settings_open or contacts.is_defeated())

func _set_keep_awake(on: bool) -> void:
	if keep_awake == on:
		return
	keep_awake = on
	DisplayServer.screen_set_keep_on(on)
	log_event("computer may sleep (idle %d s)" % roundi(idle_seconds) if not on else "keeping the computer awake again")

## Runs every frame: switches the idle screen on and off and counts the idle time with
## the real clock (frames are slow on an idle screen).
func _update_idle_screen() -> void:
	var now := Time.get_ticks_msec()
	var step := clampf(float(now - _idle_last_msec) / 1000.0, 0.0, 5.0) if _idle_last_msec > 0 else 0.0
	_idle_last_msec = now
	var wanted := idle_screen_wanted()
	if wanted != idle_screen_active:
		idle_screen_active = wanted
		idle_seconds = 0.0
		_set_keep_awake(true)
		_apply_frame_rate()
	if not idle_screen_active:
		return
	idle_seconds += step
	if keep_awake and idle_seconds >= idle_sleep_seconds:
		_set_keep_awake(false)

## Any key, mouse or controller input on an idle screen restarts the 5-minute wait.
func note_activity() -> void:
	idle_seconds = 0.0
	if idle_screen_active:
		_set_keep_awake(true)

func _on_settings_changed(new_settings: Dictionary) -> void:
	var old_difficulty: int = settings.difficulty
	settings = GameSettings.clean(new_settings)
	if settings.difficulty != old_difficulty:
		log_event("difficulty %s (next battle)" % GameSettings.DIFFICULTY_NAMES[settings.difficulty])
	_apply_settings()
	settings_saved = GameSettings.save_settings(settings_file, settings)

func toggle_settings() -> void:
	if bonus_pick_open:
		return
	if settings_open:
		close_settings()
	else:
		open_settings()

func open_settings() -> void:
	if settings_open:
		return
	# 1.1.1: not over the startup splash or an update pop-up (answer that first).
	if (is_instance_valid(update_popup) and update_popup.visible) or (is_instance_valid(startup_splash) and startup_splash.visible):
		return
	settings_open = true
	# 1.1.1: the startup hold keeps the battle stopped; it restarts it when it ends.
	_contacts_were_processing = contacts.is_processing() or startup_hold
	contacts.set_process(false)
	_pause_effects(true)
	settings_panel.open(settings, contacts.active_difficulty)
	settings_panel.set_paused_text("BATTLE OVER" if contacts.is_defeated() else ("STARTING" if startup_hold else "BATTLE PAUSED"))
	refresh_about()
	log_event("settings opened")

func close_settings() -> void:
	if not settings_open:
		return
	if is_instance_valid(controller_panel) and controller_panel.visible:
		controller_panel.close()
	settings_open = false
	settings_panel.visible = false
	contacts.set_process(_contacts_were_processing and not startup_hold and not (is_instance_valid(update_popup) and update_popup.visible and update_popup_source == "startup"))
	_pause_effects(false)
	gear_button.grab_focus()
	log_event("settings closed")

# ------------------------------------------------------------------
# 1.0.0 controller support
# ------------------------------------------------------------------
## 1.0.2: writes the controller check to the session log, one line each.
func log_controller_check(when: String) -> void:
	if not is_instance_valid(controller) or not is_instance_valid(session_log):
		return
	for line in controller.check_report().split("\n"):
		session_log.write("CONTROLLER", "%s | %s" % [when, line.strip_edges()])

func _build_controller() -> void:
	controller = ControllerInput.new()
	controller.name = "ControllerInput"
	controller.console = self
	controller.bindings_file = controller_file
	controller.load_saved()
	# Added last, so its highlight draws above Settings and the other panels.
	add_child(controller)
	# 1.0.2: what the game sees of controllers, at start and again a few seconds later
	# (some controllers report in a moment after the window opens).
	log_controller_check("start")
	if is_inside_tree():
		get_tree().create_timer(controller_check_delay, true).timeout.connect(log_controller_check.bind("after %.0f s" % controller_check_delay))

## Settings > CONTROLLER (Settings stays open beneath it; the battle stays paused).
func open_controller_panel() -> void:
	if not settings_open or not is_instance_valid(controller_panel):
		return
	controller_panel.device_text = controller.device_label()
	controller_panel.playstation_names = controller.uses_playstation_names()
	controller_panel.controller_input = controller
	controller_panel.open(controller.bindings)
	log_event("controller panel opened")

func close_controller_panel() -> void:
	if not is_instance_valid(controller_panel) or not controller_panel.visible:
		return
	controller_panel.close()
	if settings_open:
		settings_panel.controller_button.grab_focus()

func _on_controller_bindings_changed(new_bindings: Dictionary) -> void:
	controller.set_bindings(new_bindings)
	var parts := PackedStringArray()
	for button in ControllerInput.ControllerBindings.BUTTONS:
		parts.append("%s=%s" % [button, controller.bindings[button] if controller.bindings[button] != "" else "-"])
	log_event("controller buttons %s%s" % [" ".join(parts), "" if controller.bindings_saved else " | NOT SAVED"])

## A controller was connected or disconnected (ControllerInput.gd).
func _on_controller_connection() -> void:
	if is_instance_valid(controller_panel) and controller_panel.visible:
		controller_panel.device_text = controller.device_label()
		controller_panel.playstation_names = controller.uses_playstation_names()
		controller_panel.controller_input = controller
		controller_panel.update_status()
		controller_panel.refresh()

## 0.1.2: pause the battle and ask which missile bonus to keep.
func open_bonus_pick(current: String, other: String, set_offer: bool) -> void:
	if bonus_pick_open:
		return
	if settings_open:
		close_settings()
	bonus_pick_open = true
	_bonus_pick_were_processing = contacts.is_processing()
	contacts.set_process(false)
	_pause_effects(true)
	bonus_pick_panel.timeout_seconds = bonus_pick_seconds
	bonus_pick_panel.set_offer_tag = bonus_pick_set_tag
	bonus_pick_panel.rapid_seconds = contacts.rapid_missile_interval()
	bonus_pick_panel.double_seconds = contacts.own_missile_interval
	bonus_pick_panel.rapid_speed_factor = contacts.rapid_missile_speed_factor
	bonus_pick_panel.open(current, other, set_offer)
	log_event("missile bonus pick opened | has %s, can take %s | %s" % [current, other, "after set" if set_offer else "just earned"])

func _on_bonus_picked(pick: String, timed_out: bool) -> void:
	if not bonus_pick_open:
		return
	bonus_pick_open = false
	contacts.choose_missile_bonus(pick, timed_out)
	contacts.set_process(_bonus_pick_were_processing)
	_pause_effects(false)
	log_event("missile bonus pick closed | %s%s" % [pick, " (no pick in time)" if timed_out else ""])

## The battle was reset while the prompt was open: close it without a pick.
func _drop_bonus_pick() -> void:
	bonus_pick_open = false
	bonus_pick_panel.visible = false
	bonus_pick_panel.set_process(false)
	bonus_pick_panel.set_process_input(false)
	contacts.set_process(_bonus_pick_were_processing)
	_pause_effects(false)

func _pause_effects(paused: bool) -> void:
	for player in find_children("*", "AudioStreamPlayer", true, false):
		if player != sweep_loop:
			player.stream_paused = paused

func _preview_effects() -> void:
	# Short sample beep so the Effects level can be heard while paused.
	var player: AudioStreamPlayer = contacts.arrival_player
	if is_instance_valid(player) and player.stream:
		player.stream_paused = false
		player.play()

# ------------------------------------------------------------------
# Quit (Settings panel and Game Over panel)
# ------------------------------------------------------------------
func _build_game_over_quit() -> void:
	# A copy of Retry (same look), placed beside it. Retry shifts left to make room.
	game_over_quit_button = restart_button.duplicate(Node.DUPLICATE_GROUPS | Node.DUPLICATE_SCRIPTS) as Button
	game_over_quit_button.name = "Quit"
	game_over_quit_button.text = "Quit"
	game_over_panel.add_child(game_over_quit_button)
	restart_button.position.x = 90.0
	game_over_quit_button.position = Vector2(310.0, restart_button.position.y)
	game_over_quit_button.size = restart_button.size
	game_over_quit_button.pressed.connect(quit_game)

## Saves a pending high score (as Retry does) and the settings, then closes the program.
func quit_game() -> void:
	if entry_active:
		submit_initials()
	settings_saved = GameSettings.save_settings(settings_file, settings)
	quit_requests += 1
	log_event("quit | score %d" % contacts.score)
	if is_instance_valid(session_log) and not quit_dry_run:
		session_log.stop("quit")
	if quit_dry_run:
		return
	get_tree().quit()

# ------------------------------------------------------------------
# Window size from the screen resolution (high-resolution screens)
# ------------------------------------------------------------------
## Largest 16:9 size that fits inside the given share of the usable screen area.
static func window_size_for(usable: Vector2i, fraction: float) -> Vector2i:
	var room := Vector2(usable) * clampf(fraction, 0.5, 1.0)
	var width := minf(room.x, room.y * 16.0 / 9.0)
	return Vector2i(maxi(640, roundi(width)), maxi(360, roundi(width * 9.0 / 16.0)))

func _fit_window_on_start() -> void:
	if not is_inside_tree() or get_tree().current_scene != self:
		return
	fit_window()

func fit_window() -> Vector2i:
	if not fit_window_to_screen or DisplayServer.get_name() == "headless" or is_fullscreen():
		return Vector2i.ZERO
	if Engine.has_method("is_embedded_in_editor") and Engine.call("is_embedded_in_editor"):
		return Vector2i.ZERO  # running inside the editor's Game tab; the editor sizes it
	if DisplayServer.window_get_mode() != DisplayServer.WINDOW_MODE_WINDOWED:
		return Vector2i.ZERO
	var screen := DisplayServer.window_get_current_screen()
	var usable := DisplayServer.screen_get_usable_rect(screen)
	if usable.size.x <= 0 or usable.size.y <= 0:
		return Vector2i.ZERO
	var target := window_size_for(usable.size, window_screen_fraction)
	DisplayServer.window_set_size(target)
	DisplayServer.window_set_position(usable.position + (usable.size - target) / 2)
	fitted_window_size = target
	return target

func _on_new_battle_from_settings() -> void:
	close_settings()
	_on_restart_pressed()

func _gear_icon() -> Texture2D:
	# Eight-tooth gear in the console's pink, drawn as a small SVG.
	var points := PackedStringArray()
	for i in range(16):
		var angle := TAU * (i + 0.5) / 16.0
		var tooth := i % 2 == 0
		for edge in [-0.13, 0.13]:
			var a: float = angle + edge
			var r := 15.0 if tooth else 11.5
			points.append("%.2f,%.2f" % [18.0 + cos(a) * r, 18.0 + sin(a) * r])
	var svg := '<svg xmlns="http://www.w3.org/2000/svg" width="36" height="36"><polygon points="%s" fill="#ff99c7"/><circle cx="18" cy="18" r="5" fill="#0b0609"/></svg>' % " ".join(points)
	var image := Image.new()
	if image.load_svg_from_string(svg, 1.0) != OK:
		return null
	return ImageTexture.create_from_image(image)

func _center_title() -> void:
	# Center RADAR over the TACTICAL DEFENSE CONSOLE line beneath it.
	var sub: Label = $Subtitle
	var title: Label = $TopChrome
	var width := sub.get_theme_font("font").get_string_size(sub.text, HORIZONTAL_ALIGNMENT_LEFT, -1, sub.get_theme_font_size("font_size")).x
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.anchor_left = sub.anchor_left
	title.anchor_right = sub.anchor_left
	title.offset_left = sub.offset_left
	title.offset_right = sub.offset_left + width

## 1.0.5: second line of a launch button: ALL DEPLOYED when every ship is out, "2 READY"
## when ships can launch, otherwise the countdown for the next ship. 1.0.6: "ready" is
## how many the next press sends (up to 2 Interceptors, 1 Gunship), not the whole hangar.
static func launch_state_text(in_hangar: int, ready: int, ready_in: float) -> String:
	if in_hangar <= 0:
		return "ALL DEPLOYED"
	if ready > 0:
		return "%d READY" % ready
	return "READY IN %ds" % maxi(1, ceili(ready_in))

func _process(delta: float) -> void:
	_update_idle_screen()
	_update_sweep_sound(delta)
	if bonus_pick_open and not contacts.missile_bonus_offer_open:
		_drop_bonus_pick()
	_update_score_display(delta)
	# 1.0.5: ALL DEPLOYED first (no countdown when nothing can launch), then the number
	# ready, then the countdown for the next one coming back.
	var interceptors_home: int = contacts.interceptors_in_hangar()
	var interceptors_ready: int = contacts.interceptors_ready()
	launch_button.disabled = interceptors_ready <= 0 or contacts.is_defeated() or contacts.safe_remaining > 0.0
	var interceptor_tag := "AUTO " if contacts.auto_launch_interceptors else ""
	launch_button.text = "LAUNCH INTERCEPTORS\n%s%s" % [interceptor_tag, launch_state_text(interceptors_home, contacts.interceptors_next_launch(), contacts.interceptor_ready_in())]
	_tip(launch_button, "Each press launches up to %d Interceptors. Ready in the hangar: %d | Out: %d / %d" % [contacts.interceptors_per_launch, interceptors_ready, contacts.count_interceptors(), contacts.interceptor_limit()])
	jump_button.disabled = not contacts.can_jump()
	var jump_tag := "AUTO " if contacts.auto_jump else ""
	if contacts.jump_offline:
		jump_button.text = "JUMP\n%sOFFLINE" % jump_tag
	else:
		jump_button.text = ("JUMP\n%s-%d POINTS" % [jump_tag, contacts.jump_cost_now()]) if contacts.jump_recharge_remaining <= 0.0 else "JUMP\n%sCHARGING %ds" % [jump_tag, ceili(contacts.jump_recharge_remaining)]
	if contacts.protect_active():
		jump_button.text = "JUMP\nHELD | PROTECT THE CONVOY"
	_tip(jump_button, "Escape for %d points: %d or %d%% of the score, whichever is bigger (score cannot go below zero). Free between waves. Damage and remaining defense reserve are retained." % [contacts.jump_cost_now(), contacts.jump_score_cost, roundi(contacts.jump_score_percent)])
	prox_button.disabled = not contacts.can_fire_battery()
	prox_button.set_pressed_no_signal(contacts.prox_active)
	var charge := int(contacts.battery_percent())
	var auto_tag := "AUTO " if contacts.battery_auto_on() else ""
	if contacts.prox_active:
		prox_button.text = "DEFENSE SHIELD\n%sFIRING %d%%" % [auto_tag, charge]
	elif charge >= 100:
		prox_button.text = "DEFENSE SHIELD\n%sREADY 100%%" % auto_tag
	else:
		prox_button.text = "DEFENSE SHIELD\n%sRECHARGING %d%%" % [auto_tag, charge]
	if contacts.protect_active():
		prox_button.text = "DEFENSE SHIELD\nOFF | INTERCEPTORS ONLY"
	_tip(prox_button, "Toggle firing on/off. Charge drains quickly while firing and recharges slowly when stopped. Standard missiles only; cannot hurt Breachers or nukes.")
	firewall_button.disabled = not contacts.can_deploy_firewall()
	firewall_button.set_pressed_no_signal(contacts.firewall_active)
	var shield := int(contacts.firewall_percent())
	var wall_tag := "AUTO " if contacts.auto_firewall else ""
	if contacts.firewall_active:
		firewall_button.text = "FIREWALL\n%sACTIVE %d%%" % [wall_tag, shield]
	elif shield < 100:
		firewall_button.text = "FIREWALL\n%sRECHARGING %d%%" % [wall_tag, shield]
	elif contacts.firewall_needed():
		firewall_button.text = "FIREWALL\n%sREADY 100%%" % wall_tag
	else:
		firewall_button.text = "FIREWALL\n%sSTANDBY" % wall_tag
	_tip(firewall_button, "Slows a Breacher hack while deployed. Usable once a Breacher starts hacking; used up in %d seconds, recharges in %d." % [int(contacts.firewall_seconds), int(contacts.firewall_recharge_seconds)])
	_update_emp_split(shield)
	var gunships_ready: int = contacts.gunships_ready()
	gunship_button.disabled = contacts.is_defeated() or contacts.safe_remaining > 0.0 or gunships_ready <= 0
	var gunship_tag := "AUTO " if contacts.auto_launch_gunships else ""
	gunship_button.text = "LAUNCH GUNSHIP\n%s%s" % [gunship_tag, launch_state_text(contacts.gunships_in_hangar(), contacts.gunships_next_launch(), contacts.gunship_ready_in())]
	if contacts.protect_active():
		gunship_button.text = "LAUNCH GUNSHIP\nOFF | INTERCEPTORS ONLY"
	_tip(gunship_button, "Launch one Gunship. Prioritizes nukes, then Breachers, then attacks Enemy Carriers with light missiles.")
	repair_button.disabled = not contacts.can_rapid_repair()
	var repair_tag := "AUTO " if contacts.auto_rapid_repair else ""
	if contacts.rapid_repair_remaining > 0.0:
		repair_button.text = "RAPID REPAIR\n%sREPAIRING %.1fs" % [repair_tag, contacts.rapid_repair_remaining]
	elif contacts.repair_charges <= 0:
		repair_button.text = "RAPID REPAIR\n%sNO CHARGES" % repair_tag
	else:
		repair_button.text = "RAPID REPAIR\n%s+%d%% / %d CHARGE%s" % [repair_tag, int(contacts.rapid_repair_percent), contacts.repair_charges, "" if contacts.repair_charges == 1 else "S"]
	_tip(repair_button, "Restore up to %d%% of maximum hull over %.1f seconds per charge. Bonus charges at %d, %d and %d earned points, then every %d more; JUMP penalties do not reduce progress. At most %d charges are held; at the limit, earning starts again when %d is left." % [int(contacts.rapid_repair_percent), contacts.rapid_repair_seconds, contacts.repair_bonus_threshold(1), contacts.repair_bonus_threshold(2), contacts.repair_bonus_threshold(3), contacts.later_bonus_step, contacts.repair_limit(), contacts.repair_resume_charges])
	score_label.text = str(int(shown_score))
	best_label.visible = show_best_score
	best_label.text = "BEST %d" % best_score()
	# Warm flash for nuke explosions, blue-white for an JUMP jump (whichever is stronger).
	var warm: float = contacts.screen_flash_alpha()
	var jump: float = contacts.jump_screen_alpha()
	if jump > warm:
		screen_flash.color = Color(0.7, 0.86, 1.0, jump)
	else:
		screen_flash.color = Color(1.0, 0.9, 0.74, warm)
	gear_button.set_pressed_no_signal(settings_open)
	$HeaderMetrics/Enemies/Value.text = str(contacts.count_kind("drone") + contacts.count_kind("breacher"))
	$HeaderMetrics/Interceptors/Value.text = "%d / %d" % [contacts.count_interceptors(),contacts.interceptor_limit()]
	# 1.2.9: the Protect the fleet repair Gunship is not counted as one of yours.
	$HeaderMetrics/Gunships/Value.text = "%d / %d" % [contacts.player_gunship_count(),contacts.gunship_limit()]
	$"HeaderMetrics/Enemy Carriers/Value".text = str(contacts.count_kind("carrier"))
	_update_battle_readout()
	$HackAlert.text = contacts.hacking_warning()
	$HackAlert.visible = not $HackAlert.text.is_empty()
	var hack_state: String = contacts.hack_state()
	# 1.2.0: one fixed box for both messages; the approach warning sits centred in it.
	$HackAlert.size.y = hack_text_height()
	var centred: bool = hack_state == "approach"
	$HackAlert.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER if centred else HORIZONTAL_ALIGNMENT_LEFT
	$HackAlert.vertical_alignment = VERTICAL_ALIGNMENT_CENTER if centred else VERTICAL_ALIGNMENT_TOP
	var hack_blink: bool = int(contacts.battle_time * 4.0) % 2 == 0
	if hack_state == "draining":
		$HackAlert.modulate = Color(1.0, 0.25, 0.3) if hack_blink else Color(1.0, 0.55, 0.58)
	elif hack_state == "hacking":
		$HackAlert.modulate = Color(1.0, 0.25, 0.3) if hack_blink else Color(1.0, 0.78, 0.25)
	else:
		$HackAlert.modulate = Color(1.0, 0.78, 0.25)
	battle_status.text = contacts.status_message
	if contacts.safe_remaining > 0.0 and not contacts.is_defeated():
		battle_status.text += "   |   SAFE %ds" % ceili(contacts.safe_remaining)
	var defeated: bool = contacts.is_defeated()
	if defeated and not was_defeated:
		begin_game_over()
		# 1.0.8: radar sound stops; heavy scramble, then the red SYSTEMS OFFLINE screen.
		damage_effects.ship_destroyed()
		_stop_sweep_sound()
		log_event("ship destroyed | systems offline screen%s" % ("" if damage_effects.screen_effects_enabled else " (screen effects off)"))
	elif not defeated and was_defeated:
		entry_active = false
		damage_effects.reset()
		_restart_sweep_sound()
	was_defeated = defeated
	# 1.0.9: low hull warning (below 6%): the HULL bar flashes and a light screen flicker.
	var frame: Control = get_node_or_null("ConsoleFrame")
	damage_effects.set_low_hull_warning(frame != null and frame.low_hull_warning_active())
	# 1.0.8: the score screen comes in front 2 s after the red screen shows.
	game_over_panel.visible = defeated and damage_effects.score_screen_ready()
	$CenterContainer/Dome/GameOverPanel/FinalScore.text = "FINAL SCORE  %d" % contacts.score
	if defeated:
		_refresh_high_score_panel()
	var nukes: int = contacts.count_kind("nuke")
	nuclear_alert.visible = nukes > 0 and not contacts.is_defeated()
	battle_status.visible = not nuclear_alert.visible
	nuclear_alert.text = "NUCLEAR MISSILE INBOUND (%d) | GUNSHIP OR JUMP" % nukes
	nuclear_alert.modulate = Color(1.0, 0.8, 0.2) if int(contacts.battle_time * 4.0) % 2 == 0 else Color(1.0, 0.15, 0.2)
	_fit_status_label(battle_status, status_base_size)
	_fit_status_label(nuclear_alert, nuclear_base_size)

## 1.2.7: room for a status line: the label, and inside the status box when it is drawn.
func status_text_room(label: Label) -> float:
	var room := label.size.x
	var frame: Control = get_node_or_null("ConsoleFrame")
	if frame != null and frame.console_layout_v2 and frame.scope_frame_visible and frame.corner_panels_visible:
		room = minf(room, frame._v2_status_rect().size.x)
	return room - 24.0

## 1.2.7: the largest font size, from the scene size down to 12, at which the text fits.
## Every 1.2.7 message fits at the scene size in the default window; this is a safety net.
func status_font_size(label: Label, text: String, base_size: int) -> int:
	var font := label.get_theme_font("font")
	var room := status_text_room(label)
	var fs := base_size
	while fs > 12 and font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x > room:
		fs -= 1
	return fs

func _fit_status_label(label: Label, base_size: int) -> void:
	var fs := status_font_size(label, label.text, base_size)
	if label.get_theme_font_size("font_size") != fs:
		label.add_theme_font_size_override("font_size", fs)

# ------------------------------------------------------------------
# Load the sweep audio manually from the raw WAV file. This avoids
# depending on Godot's import pipeline — we read the WAV bytes ourselves,
# construct an AudioStreamWAV in code, and play it in an infinite loop.
# ------------------------------------------------------------------
func _ensure_audio_loops() -> void:
	print("[AUDIO] _ensure_audio_loops() starting...")
	if sweep_loop == null:
		push_error("[AUDIO] SweepLoop node MISSING - scene tree broken")
		return
	print("[AUDIO] SweepLoop node found: ", sweep_loop)

	var stream := _load_wav("res://assets/audio/radar_sweep_loop.wav")
	if stream == null:
		push_error("[AUDIO] Failed to load radar_sweep_loop.wav")
		return
	print("[AUDIO] WAV loaded - rate=", stream.mix_rate, " stereo=", stream.stereo,
		  " format=", stream.format, " bytes=", stream.data.size())

	stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	stream.loop_begin = 0
	# Runtime loop points are sample frames; zero would create an empty loop.
	var bytes_per_sample := 2 if stream.format == AudioStreamWAV.FORMAT_16_BITS else 1
	var channel_count := 2 if stream.stereo else 1
	stream.loop_end = int(stream.data.size() / float(bytes_per_sample * channel_count))
	print("[AUDIO] loop_mode set to LOOP_FORWARD; loop_end=", stream.loop_end)

	sweep_loop.stream = stream
	sweep_loop.volume_db = sweep_volume_db  # ambient background, not foreground
	sweep_loop.play()
	print("[AUDIO] play() called - playing=", sweep_loop.playing,
		  " volume_db=", sweep_loop.volume_db,
		  " bus=", sweep_loop.bus)

	# Fallback: if the loop ever ends (shouldn't with LOOP_FORWARD), restart it.
	if not sweep_loop.finished.is_connected(_on_sweep_finished):
		sweep_loop.finished.connect(_on_sweep_finished)

func _on_sweep_finished() -> void:
	if sweep_loop and not sweep_stopped:
		sweep_loop.play()

# ------------------------------------------------------------------
# 1.0.8: damage effects and the radar sound stopping
# ------------------------------------------------------------------
## Radar sweep loop fades out over this many seconds when the ship is destroyed (no click).
const SWEEP_STOP_FADE := 0.03

func _on_nuke_hit_ship(full: bool) -> void:
	damage_effects.nuke_hit(full)

func _stop_sweep_sound() -> void:
	sweep_stopped = true
	_sweep_fade_left = SWEEP_STOP_FADE

func _restart_sweep_sound() -> void:
	sweep_stopped = false
	_sweep_fade_left = 0.0
	sweep_loop.volume_db = sweep_volume_db
	if sweep_loop.stream != null:
		sweep_loop.play()

func _update_sweep_sound(delta: float) -> void:
	if not sweep_stopped:
		sweep_loop.volume_db = sweep_volume_db
		return
	if not sweep_loop.playing:
		return
	_sweep_fade_left -= delta
	if _sweep_fade_left <= 0.0:
		sweep_loop.stop()
		sweep_loop.volume_db = sweep_volume_db
		return
	sweep_loop.volume_db = sweep_volume_db + linear_to_db(maxf(0.001, _sweep_fade_left / SWEEP_STOP_FADE))

# Exported games (.exe / .app) hold Godot's imported copy of each sound, not the
# raw .wav file. The .import settings keep it uncompressed 16-bit PCM, so the
# exported copy has exactly the same samples as the raw file.
static func load_exported_wav(path: String) -> AudioStreamWAV:
	var imported := load(path) as AudioStreamWAV
	if imported == null or imported.format != AudioStreamWAV.FORMAT_16_BITS:
		push_error("[AUDIO] Exported copy of %s is missing or not uncompressed PCM" % path)
		return null
	print("[AUDIO] Using exported copy of ", path)
	return imported.duplicate() as AudioStreamWAV

# Parse a minimal PCM WAV file into an AudioStreamWAV.
# Handles 16-bit mono/stereo PCM at any sample rate.
func _load_wav(path: String) -> AudioStreamWAV:
	print("[AUDIO] Opening ", path, " - exists=", FileAccess.file_exists(path))
	if not FileAccess.file_exists(path):
		return load_exported_wav(path)
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("[AUDIO] Cannot open %s (error=%d)" % [path, FileAccess.get_open_error()])
		return null
	var bytes := file.get_buffer(file.get_length())
	file.close()

	if bytes.size() < 44 or bytes.slice(0, 4).get_string_from_ascii() != "RIFF":
		push_error("Not a RIFF file: %s" % path)
		return null

	# Walk chunks starting at offset 12 (after RIFF header + WAVE tag)
	var i := 12
	var sample_rate := 0
	var channels := 1
	var bits := 16
	var data: PackedByteArray
	while i + 8 <= bytes.size():
		var tag := bytes.slice(i, i + 4).get_string_from_ascii()
		var chunk_size := int(bytes.decode_u32(i + 4))
		var payload_start := i + 8
		if tag == "fmt ":
			channels = bytes.decode_u16(payload_start + 2)
			sample_rate = bytes.decode_u32(payload_start + 4)
			bits = bytes.decode_u16(payload_start + 14)
		elif tag == "data":
			data = bytes.slice(payload_start, payload_start + chunk_size)
		i += 8 + chunk_size + (chunk_size & 1)

	if data.is_empty():
		push_error("No data chunk in %s" % path)
		return null

	var stream := AudioStreamWAV.new()
	stream.mix_rate = sample_rate
	stream.stereo = channels == 2
	stream.format = AudioStreamWAV.FORMAT_16_BITS if bits == 16 else AudioStreamWAV.FORMAT_8_BITS
	stream.data = data
	return stream

func _input(event: InputEvent) -> void:
	if event is InputEventKey or event is InputEventMouse or event is InputEventJoypadButton or event is InputEventScreenTouch or event is InputEventScreenDrag \
			or (event is InputEventJoypadMotion and absf(event.axis_value) > 0.3):
		note_activity()
	# 1.1.1: Esc in the update pop-up is LATER, CANCEL or OK (never UPDATE NOW).
	if is_instance_valid(update_popup) and update_popup.visible:
		if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
			update_popup.back()
			get_viewport().set_input_as_handled()
		return
	# 1.0.0: Esc in the Controller panel cancels CHANGE, then goes back to Settings.
	if is_instance_valid(controller_panel) and controller_panel.visible and event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		controller_panel.back()
		get_viewport().set_input_as_handled()
		return
	if settings_open and event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		close_settings()
		get_viewport().set_input_as_handled()
		return
	if development_build and event is InputEventKey and event.pressed and event.keycode == KEY_F1:
		tuning_panel.visible = not tuning_panel.visible
	if event is InputEventKey and event.pressed and not event.echo and fullscreen_key_enabled:
		if event.keycode == KEY_F11:
			toggle_fullscreen()
			get_viewport().set_input_as_handled()
			return
		if event.keycode == KEY_ESCAPE and is_fullscreen():
			toggle_fullscreen()
			get_viewport().set_input_as_handled()
			return
	if entry_active and game_over_panel.visible and not settings_open and event is InputEventKey and event.pressed:
		if _handle_entry_key(event):
			get_viewport().set_input_as_handled()

# ------------------------------------------------------------------
# Full screen (F11)
# ------------------------------------------------------------------
func is_fullscreen() -> bool:
	var mode := DisplayServer.window_get_mode()
	return mode == DisplayServer.WINDOW_MODE_FULLSCREEN or mode == DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN

func toggle_fullscreen() -> void:
	if is_fullscreen():
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	else:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)

# ------------------------------------------------------------------
# Arcade high score board on Game Over: top 10, three upper-case initials.
# Mouse: click the arrows above/below each letter, then ENTER.
# Keyboard: type letters, or Up/Down to change and Left/Right to move; Enter saves.
# ------------------------------------------------------------------
func _build_high_score_board() -> void:
	var rows: Control = $CenterContainer/Dome/GameOverPanel/Rows
	for child in rows.get_children():
		child.queue_free()
	score_rows.clear()
	for index in range(high_score_slots):
		var row: Array = []
		for column in range(4):
			var label := Label.new()
			label.add_theme_font_size_override("font_size", 19)
			label.mouse_filter = Control.MOUSE_FILTER_IGNORE
			label.position = Vector2([0.0, 60.0, 130.0, 300.0][column], index * 26.0)
			label.size = Vector2([50.0, 70.0, 160.0, 80.0][column], 26.0)
			label.horizontal_alignment = [HORIZONTAL_ALIGNMENT_RIGHT, HORIZONTAL_ALIGNMENT_LEFT, HORIZONTAL_ALIGNMENT_RIGHT, HORIZONTAL_ALIGNMENT_RIGHT][column]
			rows.add_child(label)
			row.append(label)
		score_rows.append(row)
		# 1.08: an invisible hover/tap area over the whole row opens its battle stats.
		var hit := Control.new()
		hit.name = "StatsHit%d" % index
		hit.position = Vector2(0.0, index * 26.0)
		hit.size = Vector2(380.0, 26.0)
		hit.mouse_filter = Control.MOUSE_FILTER_STOP
		hit.mouse_entered.connect(_on_score_row_hover.bind(index, true))
		hit.mouse_exited.connect(_on_score_row_hover.bind(index, false))
		hit.gui_input.connect(_on_score_row_input.bind(index))
		rows.add_child(hit)
	_build_stats_box()
	var entry: Control = $CenterContainer/Dome/GameOverPanel/Entry
	var up_icon := _arrow_icon(true)
	var down_icon := _arrow_icon(false)
	for slot in range(3):
		var up: Button = entry.get_node("Up%d" % slot)
		var down: Button = entry.get_node("Down%d" % slot)
		up.icon = up_icon
		down.icon = down_icon
		up.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		down.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		up.pressed.connect(change_letter.bind(slot, 1))
		down.pressed.connect(change_letter.bind(slot, -1))
	entry.get_node("Enter").pressed.connect(submit_initials)
	board = HighScores.load_board(high_score_file, high_score_slots)

## 1.08: the small box with one entry's battle stats (shown on hover or tap).
func _build_stats_box() -> void:
	stats_box = PanelContainer.new()
	stats_box.name = "ScoreStats"
	stats_box.visible = false
	stats_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.06, 0.02, 0.05, stats_box_opacity)
	style.border_color = Color(1.0, 0.6, 0.78, 0.8)
	style.set_border_width_all(2)
	style.set_corner_radius_all(4)
	style.content_margin_left = 14
	style.content_margin_right = 14
	style.content_margin_top = 8
	style.content_margin_bottom = 8
	stats_box.add_theme_stylebox_override("panel", style)
	stats_label = Label.new()
	stats_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stats_label.add_theme_font_size_override("font_size", 16)
	stats_label.add_theme_color_override("font_color", Color(0.93, 0.88, 0.91))
	stats_box.add_child(stats_label)
	game_over_panel.add_child(stats_box)

## 1.0.9: a dark outline on every line of text on the Game Over screen (and its stats box).
func _apply_score_screen_outline() -> void:
	if score_screen_text_outline <= 0:
		return
	for label in game_over_panel.find_children("*", "Label", true, false):
		label.add_theme_constant_override("outline_size", score_screen_text_outline)
		label.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 0.85))

## 1.08: the text for one entry's stats; entries saved before 1.08 have none.
func score_stats_text(entry: Dictionary) -> String:
	var names := {"E": "EASY", "N": "NORMAL", "H": "HARD"}
	var head := "%s  %d  |  WAVE %d  |  %s" % [entry.get("initials", "---"), int(entry.get("score", 0)), int(entry.get("wave", 1)), names.get(entry.get("difficulty", "N"), "NORMAL")]
	var stats: Dictionary = entry.get("stats", {})
	if stats.is_empty():
		return head + "\nNO BATTLE STATS (SAVED BEFORE 1.08)"
	var total := 0
	for kind in HighScores.STAT_KINDS:
		total += int(stats.get(kind, 0))
	if stats.has("sets"):
		head += "\nWAVES CLEARED %d   SETS COMPLETED %d" % [int(stats.get("waves_cleared", 0)), int(stats.get("sets", 0))]
	return head + "\nENEMIES DESTROYED  %d\nATTACK DRONES %d   BREACHERS %d\nMISSILES %d   NUKES %d\nENEMY CARRIERS %d   SIEGE SHIPS %d" % [
		total, int(stats.get("drone", 0)), int(stats.get("breacher", 0)), int(stats.get("missile", 0)),
		int(stats.get("nuke", 0)), int(stats.get("carrier", 0)), int(stats.get("siege_ship", 0))]

## 1.08: shows (or with -1 hides) the stats for a high-score row.
func show_score_stats_for(index: int) -> bool:
	if not show_score_stats or index < 0 or index >= board.scores.size() or not game_over_panel.visible:
		stats_row = -1
		stats_pinned = false
		if stats_box:
			stats_box.visible = false
		return false
	stats_row = index
	stats_label.text = score_stats_text(board.scores[index])
	stats_box.size = Vector2.ZERO
	stats_box.reset_size()
	var rows: Control = game_over_panel.get_node("Rows")
	var box_size := stats_box.get_combined_minimum_size()
	# Just below the row, or above it near the bottom of the table; centred on the panel.
	var y := rows.position.y + (index + 1) * 26.0 + 4.0
	if y + box_size.y > game_over_panel.size.y - 8.0:
		y = rows.position.y + index * 26.0 - box_size.y - 4.0
	stats_box.position = Vector2((game_over_panel.size.x - box_size.x) * 0.5, maxf(8.0, y))
	stats_box.visible = true
	return true

func _on_score_row_hover(index: int, entered: bool) -> void:
	if entered:
		show_score_stats_for(index)
	elif stats_row == index and not stats_pinned:
		show_score_stats_for(-1)

## A tap (touch) or click keeps the stats open; tapping the same row again closes them.
func _on_score_row_input(event: InputEvent, index: int) -> void:
	var pressed: bool = (event is InputEventScreenTouch and event.pressed) or (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT)
	if not pressed:
		return
	if stats_pinned and stats_row == index:
		show_score_stats_for(-1)
	elif show_score_stats_for(index):
		stats_pinned = true

## 1.08: the small BEST score, on the SCORE caption line just left of "SCORE".
func _build_best_label() -> void:
	best_label = Label.new()
	best_label.name = "BestScore"
	best_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	best_label.anchor_left = 1.0
	best_label.anchor_right = 1.0
	var caption: Label = $ScoreCaption
	var caption_width := caption.get_theme_font("font").get_string_size(caption.text, HORIZONTAL_ALIGNMENT_LEFT, -1, caption.get_theme_font_size("font_size")).x
	# From just right of the gear icon (1920-wide layout) to just left of "SCORE".
	best_label.offset_left = gear_rect.end.x + 8.0 - 1920.0
	best_label.offset_right = caption.offset_right - caption_width - 18.0
	best_label.offset_top = caption.offset_top
	best_label.offset_bottom = caption.offset_bottom
	best_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	best_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	best_label.add_theme_font_size_override("font_size", best_score_font_size)
	best_label.add_theme_color_override("font_color", best_score_color)
	add_child(best_label)
	move_child(best_label, $ScoreCaption.get_index())

## Best saved score, or the current score once it is higher.
func best_score() -> int:
	return maxi(HighScores.best_score(board.scores), contacts.score)

func _arrow_icon(pointing_up: bool) -> Texture2D:
	# The built-in font has no arrow characters, so draw a small smooth triangle.
	var points := "2,12 9,3 16,12" if pointing_up else "2,3 9,12 16,3"
	var svg := '<svg xmlns="http://www.w3.org/2000/svg" width="18" height="15"><polygon points="%s" fill="#ede0e8"/></svg>' % points
	var image := Image.new()
	if image.load_svg_from_string(svg, 1.0) != OK:
		return null
	return ImageTexture.create_from_image(image)

func begin_game_over() -> void:
	board = HighScores.load_board(high_score_file, high_score_slots)
	show_score_stats_for(-1)
	highlight_row = -1
	entry_slot = 0
	var last := HighScores.clean_initials(board.last_initials)
	for slot in range(3):
		entry_letters[slot] = HighScores.LETTERS.find(last[slot])
	entry_active = HighScores.qualifies(board.scores, contacts.score, high_score_slots)
	_refresh_high_score_panel()
	log_event("game over | score %d | wave %d" % [contacts.score, contacts.wave])

func entry_initials() -> String:
	var text := ""
	for slot in range(3):
		text += HighScores.LETTERS[posmod(entry_letters[slot], 26)]
	return text

func change_letter(slot: int, step: int) -> void:
	if not entry_active:
		return
	entry_slot = clampi(slot, 0, 2)
	entry_letters[entry_slot] = posmod(entry_letters[entry_slot] + step, 26)
	_refresh_high_score_panel()

func submit_initials() -> int:
	if not entry_active:
		return -1
	entry_active = false
	highlight_row = HighScores.insert(board.scores, entry_initials(), contacts.score, contacts.wave, high_score_slots, contacts.difficulty_letter(), contacts.battle_stats())
	board.last_initials = entry_initials()
	if not HighScores.save_board(high_score_file, board.scores, board.last_initials):
		board.note = "HIGH SCORE COULD NOT BE SAVED"
	_refresh_high_score_panel()
	restart_button.grab_focus()
	return highlight_row

func _handle_entry_key(event: InputEventKey) -> bool:
	match event.keycode:
		KEY_UP:
			change_letter(entry_slot, 1)
		KEY_DOWN:
			change_letter(entry_slot, -1)
		KEY_LEFT, KEY_BACKSPACE:
			entry_slot = maxi(0, entry_slot - 1)
		KEY_RIGHT:
			entry_slot = mini(2, entry_slot + 1)
		KEY_ENTER, KEY_KP_ENTER:
			submit_initials()
		_:
			var typed := String.chr(event.unicode).to_upper() if event.unicode > 0 else ""
			if typed.length() != 1 or not HighScores.LETTERS.contains(typed):
				return false
			entry_letters[entry_slot] = HighScores.LETTERS.find(typed)
			entry_slot = mini(2, entry_slot + 1)
	_refresh_high_score_panel()
	return true

func _refresh_high_score_panel() -> void:
	var panel := game_over_panel
	var blink: bool = int(Time.get_ticks_msec() / 250.0) % 2 == 0
	panel.get_node("Entry").visible = entry_active
	var prompt: Label = panel.get_node("EntryPrompt")
	if entry_active:
		prompt.text = "NEW HIGH SCORE  |  ENTER YOUR INITIALS"
	elif highlight_row >= 0:
		prompt.text = "SAVED  |  RANK %d" % (highlight_row + 1)
	elif not str(board.get("note", "")).is_empty():
		prompt.text = board.note
	else:
		prompt.text = "SCORE DID NOT REACH THE TOP %d" % high_score_slots
	for slot in range(3):
		var letter: Label = panel.get_node("Entry/Letter%d" % slot)
		letter.text = HighScores.LETTERS[posmod(entry_letters[slot], 26)]
		var active := slot == entry_slot
		letter.add_theme_color_override("font_color", Color(1.0, 0.89, 0.55) if active and blink else (Color(1.0, 0.89, 0.55, 0.75) if active else Color(0.93, 0.88, 0.91)))
	panel.get_node("BoardTitle").text = "TOP %d HIGH SCORES" % high_score_slots
	for index in range(score_rows.size()):
		var row: Array = score_rows[index]
		var has_entry: bool = index < board.scores.size()
		var entry: Dictionary = board.scores[index] if has_entry else {}
		row[0].text = "%d." % (index + 1)
		row[1].text = entry.initials if has_entry else "---"
		row[2].text = str(entry.score) if has_entry else ""
		# 1.09: difficulty in full; the wave and stats are in the hover box.
		row[3].text = {"E": "EASY", "N": "NORMAL", "H": "HARD"}.get(entry.get("difficulty", "N"), "NORMAL") if has_entry else ""
		var color := Color(0.93, 0.88, 0.91) if has_entry else Color(0.45, 0.40, 0.44)
		if index == highlight_row:
			color = Color(1.0, 0.89, 0.55) if blink else Color(1.0, 0.6, 0.78)
		for column in range(4):
			row[column].add_theme_color_override("font_color", color if column != 3 else Color(color, 0.7))

func _update_score_display(delta: float) -> void:
	# Count toward the real score instead of jumping; Retry snaps back to zero.
	var target := float(contacts.score)
	if contacts.score == 0 and contacts.earned_points == 0:
		shown_score = 0.0
		return
	var gap := target - shown_score
	var step := maxf(absf(gap) * score_count_speed, 120.0) * maxf(0.0, delta)
	shown_score = target if absf(gap) <= step else shown_score + signf(gap) * step

# ------------------------------------------------------------------
# Wire the tuning sliders/checkboxes to dome properties. Every change
# updates the animation immediately — no restart needed.
# ------------------------------------------------------------------
func _wire_tuning_controls() -> void:
	var vbox: VBoxContainer = tuning_panel.get_node("VBox")

	# Ring count
	var ring_count_slider: HSlider = vbox.get_node("RingCount/Slider")
	ring_count_slider.value = dome.ring_count
	ring_count_slider.value_changed.connect(func(v):
		dome.ring_count = int(v)
		vbox.get_node("RingCount/Value").text = str(int(v))
	)
	vbox.get_node("RingCount/Value").text = str(dome.ring_count)

	# Rotation speed (seconds per full rotation)
	var speed_slider: HSlider = vbox.get_node("Speed/Slider")
	speed_slider.value = dome.ring_rotation_seconds
	speed_slider.value_changed.connect(func(v):
		dome.ring_rotation_seconds = v
		vbox.get_node("Speed/Value").text = "%.1fs" % v
	)
	vbox.get_node("Speed/Value").text = "%.1fs" % dome.ring_rotation_seconds

	# Hinged mode
	var hinged_check: CheckBox = vbox.get_node("Hinged/Check")
	hinged_check.button_pressed = dome.rings_hinged_at_top
	hinged_check.toggled.connect(func(pressed):
		dome.rings_hinged_at_top = pressed
	)

	# Ring A tilt
	var a_slider: HSlider = vbox.get_node("RingATilt/Slider")
	a_slider.value = dome.ring_a_axis_tilt_deg
	a_slider.value_changed.connect(func(v):
		dome.ring_a_axis_tilt_deg = v
		vbox.get_node("RingATilt/Value").text = "%d°" % int(v)
	)
	vbox.get_node("RingATilt/Value").text = "%d°" % int(dome.ring_a_axis_tilt_deg)

	# Ring B tilt
	var b_slider: HSlider = vbox.get_node("RingBTilt/Slider")
	b_slider.value = dome.ring_b_axis_tilt_deg
	b_slider.value_changed.connect(func(v):
		dome.ring_b_axis_tilt_deg = v
		vbox.get_node("RingBTilt/Value").text = "%d°" % int(v)
	)
	vbox.get_node("RingBTilt/Value").text = "%d°" % int(dome.ring_b_axis_tilt_deg)

	# Sphere visibility
	var sphere_check: CheckBox = vbox.get_node("Sphere/Check")
	sphere_check.button_pressed = dome.sphere_visible
	sphere_check.toggled.connect(func(pressed):
		dome.sphere_visible = pressed
	)

	# Ripples visibility
	var ripple_check: CheckBox = vbox.get_node("Ripples/Check")
	ripple_check.button_pressed = dome.ripples_visible
	ripple_check.toggled.connect(func(pressed):
		dome.ripples_visible = pressed
	)

	# Scanlines visibility
	var scan_check: CheckBox = vbox.get_node("Scanlines/Check")
	scan_check.button_pressed = dome.scanlines_visible
	scan_check.toggled.connect(func(pressed):
		dome.scanlines_visible = pressed
	)

# ------------------------------------------------------------------
# Launch, proximity defense and JUMP are functional. HAIL is still a placeholder.
# ------------------------------------------------------------------
func _on_rapid_repair_pressed() -> void:
	contacts.request_rapid_repair()

func _on_jump_pressed() -> void:
	if contacts.request_jump():
		print("[JUMP] Jump complete; hull retained=", contacts.hull)

func _on_prox_defense_toggled(enabled: bool) -> void:
	contacts.set_prox_defense(enabled)

# ------------------------------------------------------------------
# 1.07: the FIREWALL button splits into FIREWALL | EMP while the EMP is offered
# (a Breacher hacking, a charge ready, and the Firewall out for 2 seconds).
# ------------------------------------------------------------------
func _build_emp_split_button() -> void:
	emp_split_button = Button.new()
	emp_split_button.name = "EmpSplitButton"
	emp_split_button.focus_mode = Control.FOCUS_NONE
	emp_split_button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	var blue: Color = $ShipStatus.emp_blue
	for state in ["normal", "hover", "pressed", "focus", "hover_pressed"]:
		var box := StyleBoxFlat.new()
		box.bg_color = Color(0.0, 0.05, 0.10, 1.0) if state in ["normal", "focus"] else Color(0.02, 0.12, 0.20, 1.0)
		box.border_color = blue if state in ["normal", "focus"] else blue.lerp(Color.WHITE, 0.45)
		box.set_border_width_all(3 if state in ["hover", "pressed", "hover_pressed"] else 2)
		box.set_corner_radius_all(10)
		box.anti_aliasing = true
		emp_split_button.add_theme_stylebox_override(state, box)
	emp_split_button.add_theme_color_override("font_color", blue.lerp(Color.WHITE, 0.55))
	emp_split_button.add_theme_color_override("font_hover_color", Color(0.92, 0.98, 1.0))
	emp_split_button.add_theme_color_override("font_pressed_color", Color.WHITE)
	emp_split_button.add_theme_font_size_override("font_size", 18)
	emp_split_button.visible = false
	emp_split_button.pressed.connect(_on_emp_split_pressed)
	_tip(emp_split_button, "Overloads every hacking Breacher: they stop hacking and fly back to their Enemy Carrier for repairs. Uses one EMP charge.")
	# A child of the FIREWALL button, so Settings and the game-over panel stay on top.
	firewall_button.add_child(emp_split_button)

func _on_emp_split_pressed() -> void:
	if contacts.request_emp():
		log_event("EMP used | %d charge%s left" % [contacts.emp_charges, "" if contacts.emp_charges == 1 else "s"])

func _update_emp_split(shield: int) -> void:
	if not is_instance_valid(emp_split_button):
		return
	var split: bool = contacts.can_use_emp()
	var full := firewall_button.size
	if split:
		var half := floorf(full.x * 0.5)
		emp_split_button.position = Vector2(half + 3.0, 0.0)
		emp_split_button.size = Vector2(full.x - half - 3.0, full.y)
		var charges: int = contacts.emp_charges
		emp_split_button.text = "EMP\n%d CHARGE%s" % [charges, "" if charges == 1 else "S"]
		firewall_button.text = "FIREWALL\n%d%%" % shield
	if split != firewall_split:
		firewall_split = split
		emp_split_button.visible = split
		# Keep the FIREWALL text in the left half while split.
		for state in ["normal", "hover", "pressed", "disabled", "focus"]:
			if split:
				var box: StyleBox = firewall_button.get_theme_stylebox(state).duplicate()
				box.content_margin_right = full.x * 0.5 + 3.0
				firewall_button.add_theme_stylebox_override(state, box)
			else:
				firewall_button.remove_theme_stylebox_override(state)
		if split:
			firewall_button.add_theme_font_size_override("font_size", 18)
		else:
			firewall_button.remove_theme_font_size_override("font_size")

func _on_firewall_toggled(enabled: bool) -> void:
	contacts.set_firewall(enabled)

func _on_restart_pressed() -> void:
	# A high score is never lost: Retry saves it under the initials shown.
	if entry_active:
		submit_initials()
	log_event("retry | score %d" % contacts.score)
	contacts.reset_battle()

func _on_launch_interceptors_pressed() -> void:
	var launched: int = contacts.launch_interceptors()
	print("[INTERCEPTORS] Launched ", launched, "; active=", contacts.count_interceptors())

func _on_launch_gunship_pressed() -> void:
	print("[GUNSHIPS] Launched ", contacts.launch_gunship(), "; active=", contacts.count_kind("gunship"))

# ------------------------------------------------------------------
# 1.1.0 battle readout (left side): destroyed totals from every source, our
# losses, then EMP CHARGES in the EMP blast color.
# ------------------------------------------------------------------
func readout_text() -> String:
	var k: Dictionary = contacts.battle_stats()
	return "ATTACK DRONES DESTROYED  %d\nBREACHERS DESTROYED  %d\nMISSILES DESTROYED  %d\nNUKES DESTROYED  %d\nENEMY CARRIERS DESTROYED  %d\nSIEGE SHIPS DESTROYED  %d\nINTERCEPTORS LOST  %d\nGUNSHIPS LOST  %d\nSTEALTH INTERCEPTORS LOST  %d" % [
		k.drone, k.breacher, k.missile, k.nuke, k.carrier, k.siege_ship,
		contacts.interceptors_lost, contacts.gunships_lost, contacts.stealth_lost]

func _build_emp_readout() -> void:
	battle_readout.add_theme_font_size_override("font_size", readout_font_size)
	emp_readout = Label.new()
	emp_readout.name = "EmpReadout"
	emp_readout.mouse_filter = Control.MOUSE_FILTER_IGNORE
	emp_readout.add_theme_font_size_override("font_size", readout_font_size)
	battle_readout.add_child(emp_readout)
	# 1.1.0: PULSE BOMB charges on their own line under EMP CHARGES.
	pulse_readout = Label.new()
	pulse_readout.name = "PulseReadout"
	pulse_readout.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pulse_readout.add_theme_font_size_override("font_size", readout_font_size)
	battle_readout.add_child(pulse_readout)
	_update_battle_readout()

func _update_battle_readout() -> void:
	battle_readout.text = readout_text()
	if not is_instance_valid(emp_readout):
		return
	emp_readout.text = "EMP CHARGES  %d" % contacts.emp_charges
	emp_readout.add_theme_color_override("font_color", contacts.emp_color)
	emp_readout.position = Vector2(0.0, battle_readout.get_line_height() * battle_readout.get_line_count()
		+ battle_readout.get_theme_constant("line_spacing") * battle_readout.get_line_count())
	if is_instance_valid(pulse_readout):
		# Normal and Hard only (no PULSE BOMB on Easy).
		pulse_readout.visible = contacts.active_difficulty >= 1 and contacts.pulse_bomb_enabled and contacts.stealth_interceptor_enabled
		pulse_readout.text = "PULSE BOMB  %d" % contacts.pulse_charges
		pulse_readout.add_theme_color_override("font_color", contacts.emp_color)
		pulse_readout.position = emp_readout.position + Vector2(0.0, emp_readout.get_line_height() + battle_readout.get_theme_constant("line_spacing"))

# ------------------------------------------------------------------
# 1.1.1: updates, the ABOUT tab and the startup check (BACKLOG "Settings redesign";
# decisions asked one at a time, Stephen 2026-10-26)
# ------------------------------------------------------------------
func _build_updates() -> void:
	updater = Updater.new()
	updater.name = "Updater"
	add_child(updater)
	updater.check_done.connect(_on_check_done)
	updater.progress.connect(func(done: int, total: int) -> void: update_popup.set_progress(done, total))
	updater.stage_changed.connect(func(stage: String) -> void: update_popup.set_stage(stage, str(pending_release.get("version", ""))))
	updater.install_failed.connect(_on_update_failed)
	updater.quit_for_update.connect(_quit_for_update)
	update_popup = UpdatePopup.new()
	update_popup.name = "UpdatePopup"
	add_child(update_popup)
	update_popup.later_pressed.connect(_on_update_later)
	update_popup.skip_pressed.connect(_on_update_skip)
	update_popup.update_pressed.connect(start_update)
	update_popup.cancel_pressed.connect(_on_update_cancel)
	update_popup.ok_pressed.connect(_close_update_popup)
	update_popup.go_back_confirmed.connect(start_go_back)
	settings_panel.check_now_requested.connect(check_for_updates_now)
	settings_panel.check_at_startup_changed.connect(func(on: bool) -> void:
		updater.set_check_at_startup(on)
		log_event("check at startup %s" % ("on" if on else "off")))
	settings_panel.go_back_requested.connect(_on_go_back_requested)
	refresh_about()
	if updater.update_test_build:
		for arg in OS.get_cmdline_args() + OS.get_cmdline_user_args():
			if str(arg).begins_with("--sdc-update-test-press="):
				_test_presses = Array(str(arg).substr(24).split(",", false))
		if not _test_presses.is_empty():
			_test_driver.call_deferred()

## Update Test builds only (sandbox end-to-end runs without a mouse): presses the pop-up
## buttons named in --sdc-update-test-press=update,ok,goback,confirm,later,skip,quit as
## they appear, one second after each, the same as a click. Normal builds never read it.
var _test_presses: Array = []
func _test_driver() -> void:
	while not _test_presses.is_empty() and is_inside_tree():
		await get_tree().create_timer(1.0).timeout
		var want := str(_test_presses[0])
		var done := false
		match want:
			"update":
				if update_popup.visible and update_popup.mode == "found" and not update_popup.update_button.disabled:
					update_popup.update_button.pressed.emit()
					done = true
			"later", "skip":
				if update_popup.visible and update_popup.mode == "found":
					(update_popup.later_button if want == "later" else update_popup.skip_button).pressed.emit()
					done = true
			"ok":
				if update_popup.visible and update_popup.mode == "message":
					update_popup.ok_button.pressed.emit()
					done = true
			"goback":
				if startup_finished and not update_popup.visible and updater.backup_version() != "":
					contacts.hull = 0.0
					_on_go_back_requested()
					done = true
			"confirm":
				if update_popup.visible and update_popup.mode == "confirm":
					update_popup.go_back_button.pressed.emit()
					done = true
			"quit":
				if startup_finished and not update_popup.visible and not updating and not updater.finishing_after_update:
					log_event("update test: quit")
					get_tree().quit()
					done = true
		if done:
			log_event("update test: pressed %s" % want)
			_test_presses.pop_front()

## What the ABOUT tab shows.
func about_info() -> Dictionary:
	var updates: bool = updater.updates_available_here()
	var line: Dictionary = updater.status_line()
	var build := UpdateCore.build_label(updater.platform())
	if updater.update_test_build:
		build += "   |   UPDATE TEST"
	var info := {
		"version": str(ProjectSettings.get_setting("application/config/version", "?")),
		"build": build,
		"date": str(ProjectSettings.get_setting("application/config/release_date", "")),
		"status": line.text,
		"status_good": line.good,
		"checking": check_now_running,
		"check_at_startup": updater.check_at_startup(),
		"backup_version": updater.backup_version(),
		"updates": updates,
		"news": WHATS_NEW,
		"github": not github_url.is_empty(),
	}
	if updater.steam_build:
		info.build = "STEAM   |   " + build
		info.status = "Steam keeps this copy up to date."
		info.status_good = true
		info.updates_note = ""
	return info

func refresh_about() -> void:
	if is_instance_valid(settings_panel) and is_instance_valid(updater):
		settings_panel.set_about(about_info())

## UPDATE NOW and GO BACK work only between battles: while the first battle is held at
## startup, or on the Game Over screen (Stephen 2026-10-26).
func between_battles() -> bool:
	return startup_hold or contacts.is_defeated()

# ---------------- startup ----------------
func _begin_startup() -> void:
	if not startup_force and (not is_inside_tree() or get_tree().current_scene != self):
		return
	if updater.confirm_token != "":
		# Started by an update: report a good start once running, then tidy up.
		get_tree().create_timer(updater.confirm_after_seconds).timeout.connect(updater.confirm_started)
	else:
		updater.tidy_pending()
	updater.clear_note_if_other_version()
	startup_hold = true
	contacts.set_process(false)
	_show_startup_splash()
	var want_check: bool = updater.updates_available_here() and updater.check_at_startup() \
			and updater.confirm_token == "" and not ConvoyTestPicker.wanted()
	# The engine's own splash already showed while loading; keep about 4 seconds in all.
	var splash_left := maxf(0.5, startup_splash_seconds - Time.get_ticks_msec() / 1000.0) if not startup_force else startup_splash_seconds
	if want_check:
		startup_check_running = true
		log_event("startup update check")
		updater.check(splash_left + startup_extra_seconds)
	await get_tree().create_timer(splash_left).timeout
	_hide_startup_splash()
	if startup_check_running:
		startup_line.visible = true
		var waited := 0.0
		while startup_check_running and waited < startup_extra_seconds:
			await get_tree().create_timer(0.1).timeout
			waited += 0.1
		startup_line.visible = false
		if startup_check_running:
			startup_check_running = false
			updater.cancel_check()
			log_event("startup update check: no answer in time")
	startup_finished = true
	var r: Dictionary = updater.last_result if want_check else {}
	if bool(r.get("ok", false)) and bool(r.get("newer", false)) and not bool(r.get("missing_file", false)) \
			and str(r.get("version", "")) != updater.skipped_version():
		pending_release = r
		update_popup_source = "startup"
		startup_popup_shown = true
		update_popup.show_found(r, _running_version(), UpdateCore.build_label(updater.platform()), true)
		log_event("startup: version %s offered" % r.version)
		if is_instance_valid(controller):
			controller.call("_after_context_change")
	else:
		release_startup_hold()

## Lets the first battle start (after the startup check or its pop-up).
func release_startup_hold() -> void:
	if not startup_hold:
		return
	startup_hold = false
	if settings_open:
		_contacts_were_processing = true
		settings_panel.set_paused_text("BATTLE PAUSED")
	elif not bonus_pick_open:
		contacts.set_process(true)
	log_event("battle starts")

func _show_startup_splash() -> void:
	if not is_instance_valid(startup_splash):
		startup_splash = Control.new()
		startup_splash.name = "StartupSplash"
		startup_splash.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		startup_splash.mouse_filter = Control.MOUSE_FILTER_STOP
		var black := ColorRect.new()
		black.color = Color(0, 0, 0, 1)
		black.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		black.mouse_filter = Control.MOUSE_FILTER_IGNORE
		startup_splash.add_child(black)
		var picture := TextureRect.new()
		picture.texture = load(str(ProjectSettings.get_setting("application/boot_splash/image", "")))
		picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		picture.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		picture.mouse_filter = Control.MOUSE_FILTER_IGNORE
		startup_splash.add_child(picture)
		# Own top layer, so it always fills the window whatever the console layout is doing.
		var layer := CanvasLayer.new()
		layer.name = "StartupLayer"
		layer.layer = 90
		add_child(layer)
		layer.add_child(startup_splash)
		startup_line = Label.new()
		startup_line.name = "StartupCheckLine"
		startup_line.text = "CHECKING FOR UPDATES"
		startup_line.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		startup_line.add_theme_font_size_override("font_size", 20)
		startup_line.add_theme_color_override("font_color", Color("#b9a8b2"))
		startup_line.add_theme_color_override("font_outline_color", Color(0, 0, 0, 1))
		startup_line.add_theme_constant_override("outline_size", 6)
		# Full window width, centred in the (still empty) radar.
		startup_line.anchor_left = 0.0
		startup_line.anchor_right = 1.0
		startup_line.anchor_top = 0.0
		startup_line.anchor_bottom = 0.0
		startup_line.offset_left = 0.0
		startup_line.offset_right = 0.0
		startup_line.offset_top = 465.0
		startup_line.offset_bottom = 495.0
		startup_line.visible = false
		startup_line.mouse_filter = Control.MOUSE_FILTER_IGNORE
		layer.add_child(startup_line)
	startup_splash.modulate.a = 1.0
	startup_splash.visible = true

func _hide_startup_splash() -> void:
	if not is_instance_valid(startup_splash):
		return
	var fade := create_tween()
	fade.tween_property(startup_splash, "modulate:a", 0.0, 0.25)
	fade.tween_callback(func() -> void: startup_splash.visible = false)

func _running_version() -> String:
	return str(ProjectSettings.get_setting("application/config/version", "?"))

# ---------------- CHECK NOW ----------------
func check_for_updates_now() -> void:
	if check_now_running or updating or not updater.updates_available_here():
		return
	check_now_running = true
	log_event("check now")
	refresh_about()
	updater.check()

func _on_check_done(result: Dictionary) -> void:
	if startup_check_running:
		startup_check_running = false
		log_event("startup update check: %s" % _check_words(result))
		return
	if not check_now_running:
		return
	check_now_running = false
	log_event("check now: %s" % _check_words(result))
	refresh_about()
	update_popup_source = "about"
	if not bool(result.get("ok", false)) and bool(result.get("secure", false)):
		update_popup.show_message("COULD NOT CHECK FOR UPDATES", "A secure connection to GitHub could not be made. Security software may be blocking it. Press CHECK NOW to try again later.")
	elif not bool(result.get("ok", false)):
		update_popup.show_message("COULD NOT CHECK FOR UPDATES", "The GitHub releases page could not be reached. Check the internet connection and press CHECK NOW again.")
	elif bool(result.get("newer", false)):
		if bool(result.get("missing_file", false)):
			update_popup.show_message("UPDATE FILE NOT READY", "Version %s is on the GitHub releases page, but the file for this computer is not there yet. Try again later." % result.version)
		else:
			pending_release = result
			update_popup.show_found(result, _running_version(), UpdateCore.build_label(updater.platform()), between_battles())
	else:
		return
	if is_instance_valid(controller):
		controller.call("_after_context_change")

func _check_words(result: Dictionary) -> String:
	var words := ""
	if not bool(result.get("ok", false)):
		words = "failed (%s)" % result.get("error", "")
	elif bool(result.get("newer", false)):
		words = "version %s available" % result.version
	else:
		words = "up to date"
	if updater.use_bundled_roots:
		words += " (with the game's list of trusted certificates)"
	return words

# ---------------- pop-up buttons ----------------
func _on_update_later() -> void:
	log_event("update later")
	_close_update_popup()

func _on_update_skip() -> void:
	updater.skip_version(str(pending_release.get("version", "")))
	log_event("skip version %s" % pending_release.get("version", ""))
	_close_update_popup()

func _close_update_popup() -> void:
	update_popup.close()
	if update_popup_source == "startup":
		release_startup_hold()
	update_popup_source = "about" if settings_open else ""
	refresh_about()
	if is_instance_valid(controller):
		controller.call("_after_context_change")

func _on_update_cancel() -> void:
	if update_popup.mode == "working":
		updater.cancel()
		log_event("update cancelled")
	else:
		_close_update_popup()

## UPDATE NOW: a high score is saved first; settings are saved; then the updater runs.
func start_update() -> void:
	if updating or not between_battles() or pending_release.is_empty():
		return
	if entry_active:
		submit_initials()
	settings_saved = GameSettings.save_settings(settings_file, settings)
	updating = true
	log_event("update to %s" % pending_release.get("version", ""))
	update_popup.show_working(str(pending_release.version), pending_release, _running_version(), UpdateCore.build_label(updater.platform()))
	if is_instance_valid(controller):
		controller.call("_after_context_change")
	var why: String = await updater.update_to(pending_release)
	updating = false
	log_event("update result: %s" % ("starting new version" if why == "" else why))
	if why == "cancelled":
		_close_update_popup()

func _on_go_back_requested() -> void:
	var version: String = updater.backup_version()
	if version == "":
		return
	update_popup_source = "startup" if startup_hold else "about"
	if not between_battles():
		update_popup.show_message("FINISH THE BATTLE FIRST", "GO BACK works when the battle is over (Game Over screen), or right after the game starts.")
	else:
		update_popup.show_confirm_go_back(version)
	if is_instance_valid(controller):
		controller.call("_after_context_change")

func start_go_back() -> void:
	var version: String = updater.backup_version()
	if updating or not between_battles() or version == "":
		return
	if entry_active:
		submit_initials()
	settings_saved = GameSettings.save_settings(settings_file, settings)
	updating = true
	log_event("go back to %s" % version)
	update_popup.show_working(version, {}, _running_version(), UpdateCore.build_label(updater.platform()))
	update_popup.title.text = "GOING BACK TO %s" % version
	update_popup.set_stage("STARTING", version)
	var why: String = await updater.go_back()
	updating = false
	log_event("go back result: %s" % ("starting" if why == "" else why))

func _on_update_failed(title: String, text: String) -> void:
	log_event("update stopped: %s" % title)
	update_popup.show_message(title, text)
	refresh_about()
	if is_instance_valid(controller):
		controller.call("_after_context_change")

func _quit_for_update() -> void:
	settings_saved = GameSettings.save_settings(settings_file, settings)
	quit_requests += 1
	if is_instance_valid(session_log) and not quit_dry_run:
		session_log.stop("update")
	if quit_dry_run:
		return
	get_tree().quit()
