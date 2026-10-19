extends RefCounted
## 1.0.0 controller button assignments: which controller button performs which
## battle action. Saved in its own small file next to the other settings, so the
## existing settings file, high scores and Settings > DEFAULTS are unaffected.
##
## Each button does at most one action. An action may have more than one button
## (for example A and RT), but never none after a CHANGE: taking a button that
## belongs to another action swaps the two buttons.
##
## Fixed (not reassignable): MENU opens/closes Settings, the D-pad / left stick
## moves the highlight, and in menus A (Cross) presses the highlighted control and
## B (Circle) goes back.

const SECTION := "controller"
const FORMAT := 1

## Battle actions, in the order shown in the Controller panel.
const ACTIONS := ["launch_interceptors", "defense_shield", "launch_gunship", "firewall", "rapid_repair", "jump"]
const ACTION_NAMES := {
	"launch_interceptors": "LAUNCH INTERCEPTORS",
	"defense_shield": "DEFENSE SHIELD",
	"launch_gunship": "LAUNCH GUNSHIP",
	"firewall": "FIREWALL",
	"rapid_repair": "RAPID REPAIR",
	"jump": "JUMP",
}

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
## LT and RT start unassigned.
const DEFAULTS := {
	"a": "launch_interceptors", "b": "defense_shield", "x": "launch_gunship",
	"y": "firewall", "rb": "rapid_repair", "lb": "jump", "lt": "", "rt": "",
}

## Valid, complete copy of a saved or edited assignment table.
static func clean(raw: Dictionary) -> Dictionary:
	var out := {}
	for button in BUTTONS:
		var action = raw.get(button, DEFAULTS[button])
		out[button] = action if typeof(action) == TYPE_STRING and (action == "" or action in ACTIONS) else DEFAULTS[button]
	# An action left with no button (a damaged file) gets its default button back
	# when that button is free; otherwise it stays reachable through the panel.
	for action in ACTIONS:
		if buttons_for(out, action).is_empty():
			for button in DEFAULTS:
				if DEFAULTS[button] == action and out[button] == "":
					out[button] = action
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

## CHANGE: give Button to Action. The action's previous buttons are freed. If Button
## belonged to another action, that action takes this action's previous button, so
## no action is left without a button.
static func assign(bindings: Dictionary, action: String, button: String) -> Dictionary:
	var out := clean(bindings)
	if not action in ACTIONS or not button in BUTTONS:
		return out
	var previous := buttons_for(out, action)
	var displaced := action_for(out, button)
	for old in previous:
		out[old] = ""
	out[button] = action
	if displaced != "" and displaced != action:
		previous.erase(button)
		if not previous.is_empty():
			out[previous[0]] = displaced
		else:
			# The action had no other button: give the displaced action its default.
			for fallback in DEFAULTS:
				if DEFAULTS[fallback] == displaced and out[fallback] == "":
					out[fallback] = displaced
					break
	return out

## SET on an unassigned button's row: choose an extra button for Action ("" clears).
static func set_extra(bindings: Dictionary, button: String, action: String) -> Dictionary:
	var out := clean(bindings)
	if not button in BUTTONS or not (action == "" or action in ACTIONS):
		return out
	if action == "" and buttons_for(out, out[button]).size() <= 1:
		return out  # never leave an action without a button
	out[button] = action
	return out

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
	return clean(raw)

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
