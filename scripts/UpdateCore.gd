extends RefCounted
## 1.1.1: small helpers for in-place updates (no network, no files), so they can be
## checked on their own: version numbers, the fixed GitHub file names, the checksum
## list, the short "what's new" lines and the build type shown on the ABOUT tab.

## GitHub file names are fixed (BACKLOG, Settings redesign): the updater finds its file
## by them. Older or hand-renamed uploads are also matched by their words (for example
## "Stellar.Defense.Console.1.1.0.for.Windows.ARM64.zip").
const PREFIX := "Stellar_Defense_Console_"
const SUMS_NAME := "SHA256SUMS.txt"

## "v1.1.2" or "1.1.2" -> [1, 1, 2]. Anything after a space or "-" is ignored.
static func parse_version(text: String) -> Array[int]:
	var clean := text.strip_edges().to_lower()
	if clean.begins_with("v"):
		clean = clean.substr(1)
	for cut in [" ", "-", "+"]:
		var at := clean.find(cut)
		if at >= 0:
			clean = clean.substr(0, at)
	var parts: Array[int] = []
	for piece in clean.split("."):
		if not piece.is_valid_int():
			return []
		parts.append(int(piece))
	return parts

## -1 when a is older than b, 0 when the same, 1 when newer. 1.1 equals 1.1.0.
static func compare_versions(a: String, b: String) -> int:
	var pa := parse_version(a)
	var pb := parse_version(b)
	var n := maxi(pa.size(), pb.size())
	for i in range(n):
		var x: int = pa[i] if i < pa.size() else 0
		var y: int = pb[i] if i < pb.size() else 0
		if x != y:
			return -1 if x < y else 1
	return 0

static func is_newer(candidate: String, running: String) -> bool:
	return parse_version(candidate).size() > 0 and compare_versions(candidate, running) > 0

## Which build this copy is: Windows_x64, Windows_arm64, Mac or Linux.
static func platform_key(os_name: String = "", arch: String = "") -> String:
	if os_name == "":
		os_name = OS.get_name()
	if arch == "":
		arch = Engine.get_architecture_name()
	match os_name:
		"Windows":
			return "Windows_arm64" if arch.begins_with("arm") else "Windows_x64"
		"macOS":
			return "Mac"
		"Linux", "FreeBSD", "NetBSD", "OpenBSD", "BSD":
			return "Linux"
	return ""

## Build type for the ABOUT tab, for example "WINDOWS ARM64".
static func build_label(key: String) -> String:
	match key:
		"Windows_x64": return "WINDOWS X64"
		"Windows_arm64": return "WINDOWS ARM64"
		"Mac": return "MAC (UNIVERSAL)"
		"Linux": return "LINUX X86_64"
	return "UNKNOWN"

static func asset_name(version: String, key: String) -> String:
	var v := version.trim_prefix("v")
	match key:
		"Windows_x64": return PREFIX + v + "_Windows_x64.exe.zip"
		"Windows_arm64": return PREFIX + v + "_Windows_arm64.exe.zip"
		"Mac": return PREFIX + v + "_Mac.zip"
		"Linux": return PREFIX + v + "_Linux.tar.gz"
	return ""

## Words in a file name: "Stellar.Defense.Console.1.1.0.for.Windows.ARM64.zip" ->
## ["stellar", "defense", "console", "1", "1", "0", "for", "windows", "arm64", "zip"].
static func _words(file_name: String) -> PackedStringArray:
	var out := ""
	for ch in file_name.to_lower():
		out += ch if (ch >= "a" and ch <= "z") or (ch >= "0" and ch <= "9") else " "
	return out.split(" ", false)

static func _matches_platform(file_name: String, key: String) -> bool:
	var lower := file_name.to_lower()
	var w := _words(file_name)
	if "sha256sums" in w or lower.ends_with(".txt"):
		return false
	match key:
		"Windows_x64":
			return "windows" in w and ("x64" in w or "x86" in w) and not "arm64" in w and lower.ends_with(".zip")
		"Windows_arm64":
			return "windows" in w and "arm64" in w and lower.ends_with(".zip")
		"Mac":
			return ("mac" in w or "macos" in w) and lower.ends_with(".zip")
		"Linux":
			return "linux" in w and (lower.ends_with(".tar.gz") or lower.ends_with(".tgz"))
	return false

## Picks this build's download from a GitHub release's asset list (each entry has at
## least "name"). The fixed name wins; otherwise the one whose words match.
static func find_asset(assets: Array, version: String, key: String) -> Dictionary:
	var wanted := asset_name(version, key)
	for a in assets:
		if a is Dictionary and str(a.get("name", "")) == wanted:
			return a
	for a in assets:
		if a is Dictionary and _matches_platform(str(a.get("name", "")), key):
			return a
	return {}

static func find_sums(assets: Array) -> Dictionary:
	for a in assets:
		if a is Dictionary and str(a.get("name", "")).to_lower() == SUMS_NAME.to_lower():
			return a
	return {}

## SHA256SUMS.txt -> {file name: lower-case hash}. Accepts "hash  name" and "hash *name".
static func parse_sums(text: String) -> Dictionary:
	var out := {}
	for raw in text.split("\n"):
		var line := raw.strip_edges()
		if line == "" or line.begins_with("#"):
			continue
		var space := line.find(" ")
		if space != 64:
			continue
		var digest := line.substr(0, 64).to_lower()
		var file_name := line.substr(64).strip_edges().trim_prefix("*")
		var ok := true
		for ch in digest:
			if not ((ch >= "0" and ch <= "9") or (ch >= "a" and ch <= "f")):
				ok = false
				break
		if ok and file_name != "":
			out[file_name] = digest
	return out

## The hash the download must have: listed under the fixed name, or under the name it
## was uploaded with. "" when the list does not name it (then the update stops).
static func expected_hash(sums: Dictionary, version: String, key: String, uploaded_name: String) -> String:
	var fixed := asset_name(version, key)
	if sums.has(fixed):
		return sums[fixed]
	if sums.has(uploaded_name):
		return sums[uploaded_name]
	return ""

## Short "what's new" lines from a release's notes: the bullets under the first heading
## that starts with "New in" (else the first bullets), each cut to its first sentence,
## without Markdown marks. At most max_lines lines of at most max_chars characters.
static func whats_new(body: String, max_lines: int = 4, max_chars: int = 66) -> Array[String]:
	var lines := body.replace("\r", "").split("\n")
	var start := -1
	for i in lines.size():
		var l := lines[i].strip_edges()
		if l.begins_with("#") and l.lstrip("#").strip_edges().to_lower().begins_with("new in"):
			start = i + 1
			break
	var in_section := start >= 0
	if start < 0:
		start = 0
	var out: Array[String] = []
	for i in range(start, lines.size()):
		var l := lines[i].strip_edges()
		if in_section and l.begins_with("#"):
			break
		if not (l.begins_with("- ") or l.begins_with("* ")):
			continue
		var t := l.substr(2).replace("**", "").replace("`", "").replace("__", "").strip_edges()
		var cut := t.find(". ")
		if cut > 0:
			t = t.substr(0, cut)
		t = t.trim_suffix(".")
		if t.length() > max_chars:
			t = t.substr(0, max_chars - 3).strip_edges() + "..."
		if t != "":
			out.append(t)
		if out.size() >= max_lines:
			break
	return out

## Megabytes for the pop-up, for example 33554432 -> "32.0 MB".
static func mb(bytes: int) -> String:
	return "%.1f MB" % (float(bytes) / 1048576.0)

## "today at 9:17 AM" or "on 2026-10-25 at 9:17 AM" (local time).
static func when_text(unix_utc: int, now_utc: int = -1) -> String:
	if unix_utc <= 0:
		return ""
	if now_utc < 0:
		now_utc = int(Time.get_unix_time_from_system())
	var bias := int(Time.get_time_zone_from_system().get("bias", 0)) * 60
	var d := Time.get_datetime_dict_from_unix_time(unix_utc + bias)
	var today := Time.get_datetime_dict_from_unix_time(now_utc + bias)
	var hour: int = int(d.hour) % 12
	if hour == 0:
		hour = 12
	var clock := "%d:%02d %s" % [hour, int(d.minute), "PM" if int(d.hour) >= 12 else "AM"]
	if d.year == today.year and d.month == today.month and d.day == today.day:
		return "today at " + clock
	return "on %04d-%02d-%02d at %s" % [int(d.year), int(d.month), int(d.day), clock]
