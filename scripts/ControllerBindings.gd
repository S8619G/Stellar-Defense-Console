extends RefCounted
## 1.0.0 controller button assignments: which controller button performs which
## battle action. Saved in its own small file next to the other settings, so the
## existing settings file, high scores and Settings > DEFAULTS are unaffected.
##
## 1.0.4: each button's action is picked from a list in the Controller panel. When
## the picked action is already on another button, the player chooses: swap the two
## buttons, use both, move it here, or cancel. A button may be left (not set), and
## an action may have no button (it is still on screen for the mouse and the D-pad
## highlight). Stealth Interceptor and EMP are now actions too (LT and RT).
##
## Fixed (not reassignable): MENU opens/closes Settings, the D-pad / left stick
## moves the highlight, and in menus A (Cross) presses the highlighted control and
## B (Circle) goes back.

const SECTION := "controller"
## 1.0.4: format 2. Format 1 files (1.0.0-1.0.3) had no Stealth/EMP actions, so
## their blank LT/RT are filled with the new defaults when loaded.
const FORMAT := 2

## Battle actions, in the order shown in the action list.
const ACTIONS := ["launch_interceptors", "defense_shield", "launch_gunship", "firewall", "rapid_repair", "jump", "launch_stealth", "emp"]
const ACTION_NAMES := {
	"launch_interceptors": "LAUNCH INTERCEPTORS",
	"defense_shield": "DEFENSE SHIELD",
	"launch_gunship": "LAUNCH GUNSHIP",
	"firewall": "FIREWALL",
	"rapid_repair": "RAPID REPAIR",
	"jump": "JUMP",
	"launch_stealth": "LAUNCH STEALTH INTERCEPTOR",
	"emp": "USE EMP",
}
## Shorter names for the tags on the controller drawing, where room is tight.
const SHORT_NAMES := {"launch_stealth": "STEALTH INTERCEPTOR"}

## Buttons that can carry a battle action. Triggers are analog axes in Godot; they
## are read as buttons with a press threshold (see ControllerInput.gd).
const BUTTONS := ["a", "b", "x", "y", "lb", "rb", "lt", "rt"]
const BUTTON_NAMES := {"a": "A", "b": "B", "x": "X", "y": "Y", "lb": "LB", "rb": "RB", "lt": "LT", "rt": "RT", "menu": "MENU"}
const PLAYSTATION_NAMES := {"a": "CROSS", "b": "CIRCLE", "x": "SQUARE", "y": "TRIANGLE", "lb": "L1", "rb": "R1", "lt": "L2", "rt": "R2", "menu": "OPTIONS"}
const JOY_BUTTON_IDS := {
	JOY_BUTTON_A: "a", JOY_BUTTON_B: "b", JOY_BUTTON_X: "x", JOY_BUTTON_Y: "y",
	JOY_BUTTON_LEFT_SHOULDER: "lb", JOY_BUTTON_RIGHT_SHOULDER: "rb",
}

## Approved defaults (design/controller-1.3.1, translated to current names).
## 1.0.4: LT launches the Stealth Interceptor and RT uses the EMP.
const DEFAULTS := {
	"a": "launch_interceptors", "b": "defense_shield", "x": "launch_gunship",
	"y": "firewall", "rb": "rapid_repair", "lb": "jump", "lt": "launch_stealth", "rt": "emp",
}
## Ways to resolve a picked action that another button already has.
const CHOICES := ["swap", "both", "move"]

## Valid, complete copy of a saved or edited assignment table. A button with an
## unknown value gets its default; blank buttons stay blank.
static func clean(raw: Dictionary) -> Dictionary:
	var out := {}
	for button in BUTTONS:
		var action = raw.get(button, DEFAULTS[button])
		out[button] = action if typeof(action) == TYPE_STRING and (action == "" or action in ACTIONS) else DEFAULTS[button]
	return out

static func defaults() -> Dictionary:
	return DEFAULTS.duplicate()

static func action_for(bindings: Dictionary, button: String) -> String:
	return str(bindings.get(button, ""))

static func buttons_for(bindings: Dictionary, action: String) -> Array[String]:
	var found: Array[String] = []
	for button in BUTTONS:
		if bindings.get(button, "") == action:
			found.append(button)
	return found

static func unassigned_buttons(bindings: Dictionary) -> Array[String]:
	var found: Array[String] = []
	for button in BUTTONS:
		if str(bindings.get(button, "")) == "":
			found.append(button)
	return found

## Actions that no button performs (still usable with the mouse or the highlight).
static func unassigned_actions(bindings: Dictionary) -> Array[String]:
	var found: Array[String] = []
	for action in ACTIONS:
		if buttons_for(bindings, action).is_empty():
			found.append(action)
	return found

## Other buttons that already perform Action (not counting Button itself).
static func conflicts(bindings: Dictionary, button: String, action: String) -> Array[String]:
	var found := buttons_for(clean(bindings), action)
	found.erase(button)
	return found

## 1.0.4 pick from the list: give Button the Action. When other buttons already
## have it, Choice decides what happens to them:
##   "swap": they take Button's previous action (the buttons trade actions)
##   "both": they keep it, so more than one button performs it
##   "move": they become (not set)
## Without other buttons, Choice is ignored. An unknown choice changes nothing.
static func choose(bindings: Dictionary, button: String, action: String, choice: String = "") -> Dictionary:
	var out := clean(bindings)
	if not button in BUTTONS or not action in ACTIONS:
		return out
	var previous := action_for(out, button)
	if previous == action:
		return out
	var others := conflicts(out, button, action)
	if not others.is_empty():
		if not choice in CHOICES:
			return out
		for other in others:
			match choice:
				"swap":
					out[other] = previous
				"move":
					out[other] = ""
	out[button] = action
	return out

## Name of an action, or (not set). Short = the drawing's tag name.
static func action_name(action: String, short := false) -> String:
	if action == "":
		return "(not set)"
	if short and SHORT_NAMES.has(action):
		return SHORT_NAMES[action]
	return ACTION_NAMES.get(action, "(not set)")

static func button_name(button: String, playstation := false) -> String:
	var names := PLAYSTATION_NAMES if playstation else BUTTON_NAMES
	return names.get(button, button.to_upper())

static func label_for(bindings: Dictionary, action: String, playstation := false) -> String:
	var names := PLAYSTATION_NAMES if playstation else BUTTON_NAMES
	var parts := PackedStringArray()
	for button in buttons_for(bindings, action):
		parts.append(names[button])
	if parts.is_empty():
		return "(not set)"
	var text := " + ".join(parts)
	if action == "jump":
		text += "  (hold 1 s)"
	return text

static func load_bindings(path: String) -> Dictionary:
	var config := ConfigFile.new()
	if not FileAccess.file_exists(path) or config.load(path) != OK:
		return defaults()
	var raw := {}
	for button in BUTTONS:
		if config.has_section_key(SECTION, button):
			raw[button] = config.get_value(SECTION, button)
	return migrate(raw, int(config.get_value(SECTION, "format", 1)))

## 1.0.4: buttons saved by 1.0.0-1.0.3 (format 1). Stealth Interceptor and EMP did
## not exist as actions then, so a blank LT or RT gets its new default. Buttons the
## player set themselves are kept.
static func migrate(raw: Dictionary, format: int) -> Dictionary:
	var out := clean(raw)
	if format < 2:
		for button in ["lt", "rt"]:
			if out[button] == "":
				out[button] = DEFAULTS[button]
	return out

## Verified write, the same way as the settings: the new copy must read back
## before it replaces the old one.
static func save_bindings(path: String, bindings: Dictionary) -> bool:
	var data := clean(bindings)
	var config := ConfigFile.new()
	config.set_value(SECTION, "format", FORMAT)
	for button in BUTTONS:
		config.set_value(SECTION, button, data[button])
	var temporary := path + ".tmp"
	if config.save(temporary) != OK:
		push_warning("Controller buttons could not be saved: %s" % temporary)
		return false
	var check := ConfigFile.new()
	if check.load(temporary) != OK:
		push_warning("Controller button save did not verify; previous file kept")
		return false
	for button in BUTTONS:
		if check.get_value(SECTION, button, null) != data[button]:
			push_warning("Controller button save did not verify; previous file kept")
			return false
	var error := DirAccess.rename_absolute(ProjectSettings.globalize_path(temporary), ProjectSettings.globalize_path(path))
	if error != OK:
		push_warning("Controller button file could not be replaced (error %d); previous file kept" % error)
		return false
	return true
