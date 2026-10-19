extends SceneTree
## 1.0.1: every internal name matches the public game. Checks that no retired name is left
## anywhere in the project, that settings and high scores saved by earlier builds still load,
## that contact placement keeps its original footprint, and that both texture compression
## settings are written into project.godot.
const LegacyNames = preload("res://scripts/LegacyNames.gd")
const GameSettings = preload("res://scripts/GameSettings.gd")
const HighScores = preload("res://scripts/HighScores.gd")
const TEXT_TYPES := ["gd", "tscn", "tres", "cfg", "godot", "md", "txt", "json", "import"]
## Two further retired words checked here only (encoded, like LegacyNames). The game itself
## never uses them, so they stay out of the game scripts.
const EXTRA_RETIRED := ["QlNH", "U1RBUkJVQ0s="]
var checks := 0
var failures := 0

func check(ok: bool, label: String) -> void:
	checks += 1
	print("PASS " if ok else "FAIL ", label)
	if not ok:
		failures += 1

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	_project_text()
	_settings_upgrade()
	_high_score_upgrade()
	_footprint()
	_texture_compression()
	print("INTERNAL_NAMES_RESULT checks=%d failures=%d" % [checks, failures])
	await create_timer(.2).timeout
	quit(1 if failures else 0)

## Splits text into word parts: letters only, and camelCase / snake_case pieces separately.
static func word_parts(text: String) -> PackedStringArray:
	var parts := PackedStringArray()
	var regex := RegEx.create_from_string("[A-Z]?[a-z]+|[A-Z]+(?![a-z])")
	for m in regex.search_all(text):
		parts.append(m.get_string().to_upper())
	return parts

func _retired_hits(text: String) -> int:
	var hits := 0
	var words := LegacyNames.retired_words()
	for encoded in EXTRA_RETIRED:
		words.append(LegacyNames.decode(encoded))
	for part in word_parts(text):
		for word in words:
			# Exact word or plural; longer names also match as a prefix (e.g. +ING).
			if part == word or part == word + "S" or (word.length() >= 6 and part.begins_with(word)):
				hits += 1
	return hits

func _collect(path: String, out: Array) -> void:
	var dir := DirAccess.open(path)
	if dir == null:
		return
	for name in dir.get_files():
		if name.get_extension() in TEXT_TYPES and name != "LegacyNames.gd":
			out.append(path.path_join(name))
	for sub in dir.get_directories():
		if not sub.begins_with("."):
			_collect(path.path_join(sub), out)

func _project_text() -> void:
	var files: Array = ["res://project.godot", "res://export_presets.cfg"]
	for folder in ["res://scripts", "res://scenes", "res://verification", "res://assets"]:
		_collect(folder, files)
	check(files.size() > 60, "Project text files found to scan (%d)" % files.size())
	var bad: Array = []
	var total := 0
	for path in files:
		var hits := _retired_hits(FileAccess.get_file_as_string(path))
		total += hits
		if hits > 0:
			bad.append("%s (%d)" % [path, hits])
	check(bad.is_empty(), "No retired name in any project file%s" % ("" if bad.is_empty() else ": " + ", ".join(bad)))
	var names_bad: Array = []
	for path in files:
		if _retired_hits(String(path).get_file()) > 0:
			names_bad.append(path)
	check(names_bad.is_empty(), "No retired name in any file name")
	check(_retired_hits("softly adamant interceptor drone gunship carrier siege_ship jump radar") == 0, "Ordinary words are not mistaken for retired names")
	check(_retired_hits(LegacyNames.decode(LegacyNames.SIEGE_FOOTPRINT).to_lower()) == 1, "The retired-name check does catch a retired name")
	var words := LegacyNames.retired_words()
	check(words.size() == 16 and words.all(func(w): return w == String(w).to_upper() and String(w).length() >= 3), "Sixteen retired words decode to upper-case text")
	check(_retired_hits(LegacyNames.decode(EXTRA_RETIRED[0]) + " removed") == 1 and _retired_hits(LegacyNames.decode(EXTRA_RETIRED[1]).to_lower()) == 1, "The two further retired words are caught too")

func _settings_upgrade() -> void:
	for target in LegacyNames.SETTING_KEYS.values():
		check(GameSettings.DEFAULTS.has(target), "Setting %s exists in the current settings" % target)
	var path := "user://verify_internal_names_settings.cfg"
	var config := ConfigFile.new()
	for encoded in LegacyNames.SETTING_KEYS:
		config.set_value(GameSettings.SECTION, LegacyNames.decode(encoded), true)
	config.set_value(GameSettings.SECTION, "difficulty", 2)
	config.save(path)
	var loaded := GameSettings.load_settings(path)
	check(loaded.auto_interceptors and loaded.auto_gunships and loaded.auto_jump, "Auto options saved by earlier builds still load")
	check(loaded.difficulty == 2 and not loaded.auto_firewall, "Other saved settings are unchanged")
	# A file holding both an older and a current key keeps the current value.
	var old_jump := ""
	for encoded in LegacyNames.SETTING_KEYS:
		if LegacyNames.SETTING_KEYS[encoded] == "auto_jump":
			old_jump = LegacyNames.decode(encoded)
	config.set_value(GameSettings.SECTION, old_jump, true)
	config.set_value(GameSettings.SECTION, "auto_jump", false)
	config.save(path)
	check(not GameSettings.load_settings(path).auto_jump, "When both are present the current key wins")
	check(GameSettings.save_settings(path, loaded), "Upgraded settings save")
	var saved_text := FileAccess.get_file_as_string(path)
	check(_retired_hits(saved_text) == 0 and saved_text.contains("auto_interceptors"), "Saving writes only current key names")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))

func _high_score_upgrade() -> void:
	for target in LegacyNames.STAT_KEYS.values():
		check(target in HighScores.STAT_KINDS, "Stat %s exists in the current high-score stats" % target)
	var old_stats := {"missile": 4, "nuke": 1, "waves_cleared": 3}
	var count := 10
	for encoded in LegacyNames.STAT_KEYS:
		old_stats[LegacyNames.decode(encoded)] = count
		count += 1
	var stats := HighScores.clean_stats(old_stats)
	check(stats.get("drone") == 10 and stats.get("breacher") == 11 and stats.get("carrier") == 12 and stats.get("siege_ship") == 13, "High-score stats saved by earlier builds carry over")
	check(stats.get("missile") == 4 and stats.get("nuke") == 1 and stats.get("waves_cleared") == 3, "Other stats are unchanged")
	check(_retired_hits(JSON.stringify(stats)) == 0, "Upgraded stats use only current names")
	var path := "user://verify_internal_names_scores.json"
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify({"scores": [{"initials": "ABC", "score": 5000, "wave": 3, "difficulty": "N", "stats": old_stats}], "last_initials": "ABC"}))
	file.close()
	var board := HighScores.load_board(path)
	check(board.scores.size() == 1 and board.scores[0].score == 5000 and board.scores[0].stats.get("drone") == 10, "A saved high-score table from an earlier build loads with its stats")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))

func _footprint() -> void:
	var siege := LegacyNames.footprint_text("siege_ship")
	var carrier := LegacyNames.footprint_text("carrier")
	check(siege.length() == 12 and siege == siege.to_upper(), "Siege Ship placement footprint uses the original 12-letter label")
	check(carrier.length() == 8 and carrier == carrier.to_upper(), "Carrier placement footprint uses the original 8-letter label")
	check(LegacyNames.footprint_text("unknown") == carrier, "Unknown contacts keep the carrier footprint, as before")

func _texture_compression() -> void:
	var text := FileAccess.get_file_as_string("res://project.godot")
	check(text.contains("textures/vram_compression/import_s3tc_bptc=true"), "project.godot explicitly enables S3TC/BPTC (Windows x64, Linux and Intel Mac exports)")
	check(text.contains("textures/vram_compression/import_etc2_astc=true"), "project.godot explicitly enables ETC2/ASTC (Windows ARM64 and Apple M-series exports)")
