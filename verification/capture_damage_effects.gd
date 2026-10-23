extends SceneTree
## 1.0.8: still captures of the damage effects in the real game (review only).
## Usage: godot --path . --script res://verification/capture_damage_effects.gd -- <folder>
var folder := ""
var console: Control
var fx: Control

func _initialize() -> void:
	call_deferred("_run")

func grab(name: String) -> void:
	await process_frame
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	image.save_png(folder.path_join(name + ".png"))
	print("CAPTURE ", name, " ", image.get_size(), " strength ", fx.scramble_strength)

## Moves the effect clock to an exact time without letting frames advance it.
func at(seconds_after: float, from: float) -> void:
	fx._update(seconds_after - from)

func _run() -> void:
	folder = OS.get_cmdline_user_args()[0]
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://capture_fx.cfg"))
	console = load("res://scenes/RadarConsole.tscn").instantiate()
	console.settings_file = "user://capture_fx.cfg"
	console.high_score_file = "user://capture_fx_scores.json"
	console.shell_dry_run = true
	console.quit_dry_run = true
	var c: Control = console.get_node("CenterContainer/Dome/Contacts")
	c.klaxon_enabled = false
	c.arrival_sound_enabled = false
	c.launch_sound_enabled = false
	c.wave_cues_enabled = false
	root.add_child(console)
	var dims := OS.get_cmdline_user_args()[1].split("x") if OS.get_cmdline_user_args().size() > 1 else PackedStringArray(["1600", "900"])
	root.size = Vector2i(int(dims[0]), int(dims[1]))
	fx = console.damage_effects
	fx.rng.seed = 4101
	c.difficulty = 1
	c.reset_battle()
	c.rng.seed = 7
	for i in range(900):
		c._process(1.0 / 30.0)
		if i % 150 == 0:
			c.spawn_contact("interceptor", "friendly")
	c.hull = c.max_hull
	c.set_process(false)
	fx.set_process(false)
	await grab("01_before")
	console.screen_flash.visible = false
	fx.nuke_hit(true)
	fx._update(0.05)
	await grab("02_full_nuke_hit_peak")
	fx._update(0.35)
	await grab("03_full_nuke_hit_fading")
	fx._update(0.5)
	fx.nuke_hit(false)
	fx._update(0.04)
	await grab("04_partial_nuke_hit_peak")
	fx._update(0.5)
	await grab("05_after_hit_normal")
	# Ship destroyed.
	c.hull = 0.0
	console._process(0.0)
	fx._update(0.0)
	fx._update(0.2)
	await grab("06_destroyed_heavy_scramble")
	fx.destroyed_time = 0.70
	fx._update(0.0)
	await grab("07_flicker_half_red")
	fx.destroyed_time = 0.734
	fx._update(0.0)
	await grab("08_flicker_red")
	fx.destroyed_time = 2.0
	fx._update(0.0)
	console._process(0.0)
	await grab("09_red_offline_1s")
	fx.destroyed_time = 2.9
	fx._update(0.0)
	console._process(0.0)
	print("SCORE READY at 2.9: ", fx.score_screen_ready(), " panel ", console.game_over_panel.visible)
	fx.destroyed_time = 3.0
	fx._update(0.0)
	console._process(0.0)
	print("SCORE READY at 3.0: ", fx.score_screen_ready(), " panel ", console.game_over_panel.visible)
	await grab("10_score_in_front")
	var p: float = fx.pulses[fx.pulses.size() - 1]
	fx.destroyed_time = p + 0.03
	fx._update(0.0)
	console._process(0.0)
	await grab("11_light_scramble_with_score")
	fx.destroyed_time = 12.0
	fx._update(0.0)
	console._process(0.0)
	await grab("12_list_scrolled")
	# Effects off.
	console.get_node("CenterContainer/Dome/GameOverPanel/Retry").pressed.emit()
	console._process(0.0)
	fx._update(0.0)
	await grab("13_after_retry")
	console.toggle_settings()
	console.settings_panel.screen_effects_button.button_pressed = false
	await grab("14_settings_effects_off")
	console.toggle_settings()
	c.set_process(false)
	c.hull = 0.0
	console._process(0.0)
	fx._update(0.1)
	await grab("15_effects_off_destroyed")
	console.queue_free()
	quit()
