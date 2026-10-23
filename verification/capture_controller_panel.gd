extends SceneTree
## 1.0.4 screenshots of Settings > CONTROLLER: the button table, the action list and
## the "already on another button" choice. Usage:
##   godot --path . --script res://verification/capture_controller_panel.gd -- <folder> [width] [height]
const ControllerBindings = preload("res://scripts/ControllerBindings.gd")
var folder := ""
var console: Control
var pad: Node
var panel: Control

func _initialize() -> void:
	call_deferred("_run")

func grab(name: String) -> void:
	for i in range(8):
		await process_frame
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	image.save_png(folder.path_join(name + ".png"))
	print("CAPTURE ", name, " ", image.get_size())

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	folder = args[0]
	var size := Vector2i(1600, 900)
	if args.size() >= 3:
		size = Vector2i(int(args[1]), int(args[2]))
	console = load("res://scenes/RadarConsole.tscn").instantiate()
	console.settings_file = "user://capture_controller.cfg"
	console.high_score_file = "user://capture_controller_scores.json"
	console.controller_file = "user://capture_controller_buttons.cfg"
	if FileAccess.file_exists(console.controller_file):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(console.controller_file))
	console.shell_dry_run = true
	console.quit_dry_run = true
	var c: Control = console.get_node("CenterContainer/Dome/Contacts")
	c.klaxon_enabled = false
	c.auto_spawn = false
	root.add_child(console)
	root.size = size
	DisplayServer.window_set_size(size)
	for i in range(8):
		await process_frame
	c.reset_battle()
	c.set_process(false)
	pad = console.controller
	panel = console.controller_panel
	console.open_settings()
	console.open_controller_panel()
	await grab("01_table_defaults")
	# Controller highlight on A's CHANGE, then A opens the list.
	pad.used_controller = true
	pad.active_device = 0
	pad.target = panel.rows[0].button
	pad.overlay.queue_redraw()
	await grab("02_table_highlight")
	panel.open_picker("a")
	pad._after_context_change()
	pad.overlay.queue_redraw()
	await grab("03_list_for_A")
	pad.target = panel.picker_items[7]
	pad.overlay.queue_redraw()
	await grab("04_list_highlight_emp")
	panel.pick("emp")
	pad._after_context_change()
	pad.overlay.queue_redraw()
	await grab("05_choice_emp_on_RT")
	panel.apply_choice("emp", "swap")
	pad._after_context_change()
	pad.overlay.queue_redraw()
	await grab("06_after_swap")
	panel.open_picker("rb")
	panel.pick("launch_gunship")
	panel.apply_choice("launch_gunship", "move")
	pad._after_context_change()
	await grab("07_after_move_not_set")
	panel.open_picker("x")
	pad._after_context_change()
	await grab("08_list_for_X_after_changes")
	panel.cancel_picker()
	panel.start_test()
	panel.light("lt", true)
	panel.light("rt", true)
	await grab("09_test_lt_rt")
	panel.stop_test()
	console.queue_free()
	await process_frame
	quit()
