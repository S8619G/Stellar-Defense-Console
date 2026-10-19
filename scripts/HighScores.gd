extends RefCounted
## Arcade high score table: top entries with three upper-case initials.
## Saved as a small JSON file in Godot's user data folder so it survives
## restarts. Writes go to a temporary file first and are checked before they
## replace the old table; an unreadable table is backed up, never discarded.

const LegacyNames = preload("res://scripts/LegacyNames.gd")

const LETTERS := "ABCDEFGHIJKLMNOPQRSTUVWXYZ"
## 1.08: enemy kinds kept in each entry's battle stats (entries saved before 1.08 have none).
const STAT_KINDS := ["drone", "breacher", "missile", "nuke", "carrier", "siege_ship"]

## 1.08: whole, non-negative counts for the known kinds; {} when there are none.
static func clean_stats(raw: Variant) -> Dictionary:
	var stats := {}
	if typeof(raw) != TYPE_DICTIONARY:
		return stats
	# 1.0.1: stats saved by earlier builds under older kind names carry over.
	raw = LegacyNames.upgrade_keys(raw, LegacyNames.STAT_KEYS)
	for kind in STAT_KINDS:
		if raw.has(kind):
			stats[kind] = maxi(0, int(raw[kind]))
	# 1.2.0: defined-wave progress, when the entry has it.
	for key in ["waves_cleared", "sets"]:
		if not stats.is_empty() and raw.has(key):
			stats[key] = maxi(0, int(raw[key]))
	return stats

static func clean_initials(text: String) -> String:
	var result := ""
	for character in text.to_upper():
		if LETTERS.contains(character):
			result += character
		if result.length() == 3:
			break
	while result.length() < 3:
		result += "A"
	return result

static func _clean_entries(raw: Variant, slots: int) -> Array:
	var entries: Array = []
	if typeof(raw) != TYPE_ARRAY:
		return entries
	for item in raw:
		if typeof(item) != TYPE_DICTIONARY or not item.has("score"):
			continue
		var entry := {
			"initials": clean_initials(str(item.get("initials", "AAA"))),
			"score": maxi(0, int(item.get("score", 0))),
			"wave": maxi(1, int(item.get("wave", 1))),
			"difficulty": str(item.get("difficulty", "N")) if str(item.get("difficulty", "N")) in ["E", "N", "H"] else "N"
		}
		var stats := clean_stats(item.get("stats", null))
		if not stats.is_empty():
			entry["stats"] = stats
		entries.append(entry)
	# Highest first; equal scores keep their saved order.
	var ordered: Array = []
	for entry in entries:
		var index := ordered.size()
		while index > 0 and ordered[index - 1].score < entry.score:
			index -= 1
		ordered.insert(index, entry)
	return ordered.slice(0, maxi(1, slots))

## Returns {"scores": Array, "last_initials": String, "note": String}.
static func load_board(path: String, slots: int = 10) -> Dictionary:
	var board := {"scores": [], "last_initials": "AAA", "note": ""}
	if not FileAccess.file_exists(path):
		return board
	var text := FileAccess.get_file_as_string(path)
	var parsed: Variant = _parse(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		# Keep the unreadable file for recovery instead of overwriting it.
		var backup := path + ".unreadable-%d.bak" % int(Time.get_unix_time_from_system())
		DirAccess.copy_absolute(ProjectSettings.globalize_path(path), ProjectSettings.globalize_path(backup))
		board.note = "HIGH SCORE FILE UNREADABLE | BACKED UP"
		return board
	board.scores = _clean_entries(parsed.get("scores", []), slots)
	board.last_initials = clean_initials(str(parsed.get("last_initials", "AAA")))
	return board

static func qualifies(scores: Array, score: int, slots: int = 10) -> bool:
	if score <= 0:
		return false
	if scores.size() < slots:
		return true
	return score > int(scores[slots - 1].score)

## Inserts below any equal scores. Returns the 0-based row, or -1 if it did not place.
static func insert(scores: Array, initials: String, score: int, wave: int, slots: int = 10, difficulty: String = "N", stats: Dictionary = {}) -> int:
	if not qualifies(scores, score, slots):
		return -1
	var index := scores.size()
	while index > 0 and int(scores[index - 1].score) < score:
		index -= 1
	var entry := {"initials": clean_initials(initials), "score": score, "wave": maxi(1, wave), "difficulty": difficulty if difficulty in ["E", "N", "H"] else "N"}
	var clean := clean_stats(stats)
	if not clean.is_empty():
		entry["stats"] = clean
	scores.insert(index, entry)
	while scores.size() > slots:
		scores.pop_back()
	return index if index < slots else -1

static func save_board(path: String, scores: Array, last_initials: String) -> bool:
	var data := {"version": 1, "last_initials": clean_initials(last_initials), "scores": scores}
	var text := JSON.stringify(data, "  ")
	var temporary := path + ".tmp"
	var file := FileAccess.open(temporary, FileAccess.WRITE)
	if file == null:
		push_warning("High scores could not be saved: %s" % temporary)
		return false
	file.store_string(text)
	file.close()
	# Verify the new copy reads back before it replaces the old table.
	var check: Variant = _parse(FileAccess.get_file_as_string(temporary))
	if typeof(check) != TYPE_DICTIONARY or (check.get("scores", []) as Array).size() != scores.size():
		push_warning("High score save did not verify; previous table kept")
		return false
	var error := DirAccess.rename_absolute(ProjectSettings.globalize_path(temporary), ProjectSettings.globalize_path(path))
	if error != OK:
		push_warning("High score file could not be replaced (error %d); previous table kept" % error)
		return false
	return true


## 1.08: the highest saved score (0 when the table is empty).
static func best_score(scores: Array) -> int:
	var best := 0
	for entry in scores:
		best = maxi(best, int(entry.get("score", 0)))
	return best

static func _parse(text: String) -> Variant:
	# Quiet parse: a damaged file returns null instead of printing an engine error.
	var json := JSON.new()
	if json.parse(text) != OK:
		return null
	return json.data
