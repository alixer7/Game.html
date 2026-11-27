extends Node

## Live v7.0 CTR:NF True Philosophy Visual Showcase & Runtime Screenshot Capture!
## Captures Start-Line Precision Timing Bar, Arabic Track Select, and ALL 3 Multi-Biome 2.2+ km Worlds!

const OUT_DIR := "C:/Users/ali77/.gemini/antigravity/brain/f77adea1-50f1-415f-8265-46a6675cf481"

func _ready() -> void:
	print("=== v7.0 CTR:NF TRUE PHILOSOPHY VISUAL SMOKE & SCREENSHOT CAPTURE START ===")
	get_window().size = Vector2i(1600, 720)
	GameState.language = "ar"
	GameState.mirror_mode = false
	await _wait_frames(5)

	# 1. Track Select Screen showing the 3 new >= 2.2 km Multi-Biome CTR:NF Tracks in Arabic!
	GameState.selected_racer_index = 0
	var menu := MainMenu.new()
	add_child(menu)
	await _wait_frames(8)
	menu._current_screen = MainMenu.Screen.TRACK_SELECT
	menu._render_screen()
	await _wait_frames(12)
	await _snap("v7_01_track_select.png")
	menu.queue_free()
	await _wait_frames(4)

	# 2. Live Start-Line Countdown with Precision Golden Sweet-Spot Timing Bar!
	await _capture_start_bar("v7_02_start_timing_bar.png")

	# 3. Track 1: EMERALD TEMPLE CIRCUIT — Golden Jungle Village + Mayan Ruins + Canopy Overpass + Drift Sparks!
	await _capture_track(0, 0.015, "v7_03_emerald_jungle_village.png", false)

	# 4. Track 1: EMERALD TEMPLE CIRCUIT — Turquoise Lagoon + Floating Stepping-Stone Island Double-Hop!
	await _capture_track(0, 0.692, "v7_04_emerald_floating_pad.png", false)

	# 5. Track 2: BIO-LAB HYDRO SPEEDWAY — High-Tech Chemical Bio-Lab + Glowing Emerald Acid Vats!
	await _capture_track(1, 0.018, "v7_05_biolab_chemical_hall.png", false)

	# 6. Track 2: BIO-LAB HYDRO SPEEDWAY — Frozen Arctic Coolant Exterior + Half-Pipe + Blue Fire!
	await _capture_track(1, 0.375, "v7_06_biolab_arctic_ice.png", true)

	# 7. Track 3: COSMIC CITADEL STARWAY — Orbital City Skyline, Ringed Planet, Asteroids & Blue Fire!
	await _capture_track(2, 0.135, "v7_07_cosmic_citadel_nebula.png", true)

	print("=== ALL 7 v7.0 CTR:NF SCREENSHOTS CAPTURED CLEANLY! ===")
	get_tree().quit(0)

func _capture_start_bar(filename: String) -> void:
	GameState.selected_mode = GameState.GameMode.ARCADE_RACE
	GameState.selected_track_index = 0
	var race := RaceManager.new()
	add_child(race)
	await _wait_frames(6)
	# Freeze cleanly at countdown stage 2 with needle right inside the Glowing Golden Sweet Spot (85%)!
	race.countdown_timer = 1.8
	race.countdown_stage = 2
	race.race_active = false
	if race.hud:
		race.hud.set_countdown(2)
	race.player_kart.start_rev_meter = 0.85
	race.player_kart.start_rev_overheated = false
	for _i in range(10):
		race.player_kart.start_rev_meter = 0.85
		await get_tree().process_frame
	await _snap(filename)
	race.queue_free()
	await _wait_frames(4)

func _capture_track(track_idx: int, demo_t: float, filename: String, use_blue_fire: bool) -> void:
	GameState.selected_mode = GameState.GameMode.ARCADE_RACE
	GameState.selected_track_index = track_idx
	var race := RaceManager.new()
	add_child(race)
	await _wait_frames(6)

	race.countdown_timer = 0.0
	race.race_active = true
	if race.hud:
		race.hud.set_countdown(0)
		if race.hud._countdown_box:
			race.hud._countdown_box.visible = false
	for k in race.all_karts:
		k.race_started = true

	var sp: TrackSpline = race.built_data["spline"]
	var s := sp.sample_at_t(demo_t)
	var yaw := atan2(-s["forward"].x, -s["forward"].z)
	race.player_kart.global_position = s["pos"] + Vector3(0.0, 0.45 + float(s.get("crown", 0.0)), 0.0)
	race.player_kart.heading_yaw = yaw
	race.player_kart.spline_t = demo_t
	race.player_kart.add_fruit(10)
	race.player_kart.held_item = "missile"
	race.player_kart.item_roulette_timer = 0.0
	if use_blue_fire:
		race.player_kart.trigger_turbo_pad(true)
	else:
		race.player_kart.trigger_turbo_pad(false)
		race.player_kart.is_drifting = true
		race.player_kart.drift_dir = 1
		race.player_kart.drift_charge = 0.84
		race.player_kart.drift_boost_count = 2

	var rival_idx := 0
	for k in race.all_karts:
		if k == race.player_kart: continue
		var rs := sp.sample_at_t(demo_t + 0.010 + float(rival_idx) * 0.008)
		k.global_position = rs["pos"] + rs["right"] * (float(rival_idx % 2) * 7.0 - 3.5) + Vector3(0.0, 0.45, 0.0)
		k.heading_yaw = atan2(-rs["forward"].x, -rs["forward"].z)
		k.forward_speed = 40.0
		k.fire_tier = 2
		k.reserves = 3.0
		rival_idx += 1

	race.race_camera.attach_to(race.player_kart)
	for _f in range(18):
		race.player_kart.input_accel = true
		if not use_blue_fire:
			race.player_kart.input_hop_held = true
			race.player_kart.input_steer = 0.40
			race.player_kart.is_drifting = true
			race.player_kart.drift_dir = 1
			race.player_kart.drift_charge = 0.82
		await get_tree().process_frame
	if race.player_kart.visuals:
		race.player_kart.visuals.trigger_boost_flash(race.player_kart.fire_tier)
	for _f in range(4):
		if not use_blue_fire:
			race.player_kart.is_drifting = true
			race.player_kart.drift_dir = 1
			race.player_kart.drift_charge = 0.84
		await get_tree().process_frame
	await _snap(filename)
	race.queue_free()
	await _wait_frames(4)

func _wait_frames(count: int) -> void:
	for _i in range(count):
		await get_tree().process_frame

func _snap(filename: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	if img:
		var path := OUT_DIR + "/" + filename
		img.save_png(path)
		print("  Saved: ", path)
