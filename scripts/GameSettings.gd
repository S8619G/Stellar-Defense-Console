extends RefCounted
## Player settings from the gear icon: two volumes with mute switches,
## difficulty and the auto options (battery, firewall, launches, JUMP). Saved in Godot's user data folder
## with a verified write, the same way as the high scores.

const LegacyNames = preload("res://scripts/LegacyNames.gd")

const SECTION := "settings"
const DEFAULTS := {
	"effects_volume": 50, "effects_muted": false,
	"radar_volume": 100, "radar_muted": false,
	"difficulty": 1, "auto_battery": false, "auto_firewall": false,
	"auto_interceptors": false, "auto_gunships": false, "auto_jump": false,
	"auto_repair": false, "remember_settings": true,
	"screen_effects": true,
}
## Settings that go back to their defaults on start when Remember Settings is OFF
## (volumes and mutes are always kept).
const BATTLE_KEYS := ["difficulty", "auto_battery", "auto_firewall", "auto_interceptors", "auto_gunships", "auto_jump", "auto_repair"]
const DIFFICULTY_NAMES := ["EASY", "NORMAL", "HARD"]
const EFFECTS_BUS := "Effects"
const RADAR_BUS := "Radar"

static func clean(raw: Dictionary, defaults: Dictionary = DEFAULTS) -> Dictionary:
	var out := DEFAULTS.duplicate()
	for key in defaults:
		out[key] = defaults[key]
	for key in ["effects_volume", "radar_volume"]:
		if raw.has(key) and typeof(raw[key]) in [TYPE_INT, TYPE_FLOAT]:
			out[key] = clampi(int(raw[key]), 0, 100)
	for key in ["effects_muted", "radar_muted", "auto_battery", "auto_firewall", "auto_interceptors", "auto_gunships", "auto_jump", "auto_repair", "remember_settings", "screen_effects"]:
		if raw.has(key) and typeof(raw[key]) == TYPE_BOOL:
			out[key] = raw[key]
	if raw.has("difficulty") and typeof(raw.difficulty) in [TYPE_INT, TYPE_FLOAT]:
		out.difficulty = clampi(int(raw.difficulty), 0, 2)
	return out

## Settings used for a new start: with Remember Settings OFF, difficulty and the
## auto options return to their defaults; volumes, mutes and the switch are kept.
static func startup(saved: Dictionary, defaults: Dictionary = DEFAULTS) -> Dictionary:
	var out := clean(saved, defaults)
	if out.remember_settings:
		return out
	for key in BATTLE_KEYS:
		out[key] = defaults.get(key, DEFAULTS[key])
	return out

## Everything back to the defaults (Reset to Defaults); the Remember Settings choice is kept.
static func reset_all(current: Dictionary, defaults: Dictionary = DEFAULTS) -> Dictionary:
	var out := clean({}, defaults)
	out.remember_settings = clean(current, defaults).remember_settings
	return out

static func load_settings(path: String, defaults: Dictionary = DEFAULTS) -> Dictionary:
	var config := ConfigFile.new()
	if not FileAccess.file_exists(path) or config.load(path) != OK:
		return clean({}, defaults)
	var saved := {}
	if config.has_section(SECTION):
		for key in config.get_section_keys(SECTION):
			saved[key] = config.get_value(SECTION, key)
	# 1.0.1: settings saved by earlier builds under older key names carry over.
	saved = LegacyNames.upgrade_keys(saved, LegacyNames.SETTING_KEYS)
	var raw := {}
	for key in DEFAULTS:
		if saved.has(key):
			raw[key] = saved[key]
	return clean(raw, defaults)

static func save_settings(path: String, settings: Dictionary) -> bool:
	var data := clean(settings)
	var config := ConfigFile.new()
	for key in DEFAULTS:
		config.set_value(SECTION, key, data[key])
	var temporary := path + ".tmp"
	if config.save(temporary) != OK:
		push_warning("Settings could not be saved: %s" % temporary)
		return false
	# Verify the new copy reads back before it replaces the old one.
	var check := ConfigFile.new()
	if check.load(temporary) != OK or check.get_value(SECTION, "difficulty", -1) != data.difficulty:
		push_warning("Settings save did not verify; previous settings kept")
		return false
	var error := DirAccess.rename_absolute(ProjectSettings.globalize_path(temporary), ProjectSettings.globalize_path(path))
	if error != OK:
		push_warning("Settings file could not be replaced (error %d); previous settings kept" % error)
		return false
	return true

## Slider percent to bus level: 100% = full level, 50% = about -6 dB, 0% = silent.
static func bus_db(percent: int) -> float:
	return -80.0 if percent <= 0 else linear_to_db(clampi(percent, 0, 100) / 100.0)

static func ensure_bus(bus_name: String) -> int:
	var index := AudioServer.get_bus_index(bus_name)
	if index == -1:
		AudioServer.add_bus()
		index = AudioServer.bus_count - 1
		AudioServer.set_bus_name(index, bus_name)
		AudioServer.set_bus_send(index, "Master")
	return index

static func apply_audio(settings: Dictionary) -> void:
	var effects := ensure_bus(EFFECTS_BUS)
	var radar := ensure_bus(RADAR_BUS)
	AudioServer.set_bus_volume_db(effects, bus_db(settings.effects_volume))
	AudioServer.set_bus_mute(effects, settings.effects_muted or settings.effects_volume <= 0)
	AudioServer.set_bus_volume_db(radar, bus_db(settings.radar_volume))
	AudioServer.set_bus_mute(radar, settings.radar_muted or settings.radar_volume <= 0)
