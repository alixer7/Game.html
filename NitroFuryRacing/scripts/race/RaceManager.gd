class_name RaceManager
extends Node3D

## Complete Race Scene Orchestrator:
## Builds track, spawns Player + 5 AI Rivals (or Time Trial Ghost), runs 3-2-1-GO countdown,
## routes Multi-Touch & Keyboard/Gamepad inputs, tracks live 1st-6th rankings, and drives HUD & Results.

signal return_to_menu_requested()
signal restart_race_requested()
signal next_gp_track_requested()

var track_builder: TrackBuilder
var track_objects: TrackObjects
var track_hazards: TrackHazards
var ghost_system: GhostSystem
var race_camera: RaceCamera
var player_kart: KartPhysics
var all_karts: Array[KartPhysics] = []
var ai_controllers: Array[KartAI] = []
var hud = null
var touch_controls = null

var track_meta: Dictionary = {}
var built_data: Dictionary = {}
var countdown_timer: float = 3.2
var countdown_stage: int = 4 # 4=wait, 3, 2, 1, 0=GO!
var race_active: bool = false
var is_paused: bool = false
var finish_delay: float = -1.0
var shortcuts_hit_this_race: int = 0
var rank_map: Dictionary = {}
var _weather_nodes: Array[Dictionary] = []
var _weather_theme: String = "tiki"

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE
	_build_race_world()

func _build_race_world() -> void:
	track_meta = GameState.get_selected_track()
	var track_id: String = track_meta["id"]
	var total_laps: int = int(track_meta.get("laps", 3))
	if GameState.selected_mode == GameState.GameMode.PRACTICE_ACADEMY:
		total_laps = 99

	# 1. Procedural Interconnected 3D Track (supports Mirror Mode!)
	track_builder = TrackBuilder.new()
	add_child(track_builder)
	built_data = track_builder.build_track(track_id, GameState.mirror_mode)
	var spline: TrackSpline = built_data["spline"]

	# 2. Spawn Player + Rivals on 2x3 Staggered Starting Grid
	all_karts.clear()
	ai_controllers.clear()
	var racer_lineup := _build_lineup()
	var start_t := fposmod(1.0 - (14.0 / maxf(800.0, spline.total_length)), 1.0)
	var start_s := spline.sample_at_t(start_t)
	var start_fwd: Vector3 = start_s["forward"]
	var start_right: Vector3 = start_s["right"]
	var start_yaw := atan2(-start_fwd.x, -start_fwd.z)

	for i in range(racer_lineup.size()):
		var entry: Dictionary = racer_lineup[i]
		var kart := KartPhysics.new()
		add_child(kart)
		kart.setup_racer(entry["racer"], bool(entry["is_player"]), spline, total_laps)
		kart.world_ref = track_builder
		var row := i / 2
		var col_side := -1.0 if (i % 2 == 0) else 1.0
		var grid_pos: Vector3 = start_s["pos"] - start_fwd * (float(row) * 5.2 + 2.5) + start_right * (col_side * 3.1) + Vector3(0.0, 0.35, 0.0)
		kart.place_at_start(grid_pos, start_yaw, start_t)
		all_karts.append(kart)

		if bool(entry["is_player"]):
			player_kart = kart
			track_builder.set_focus(kart)
			kart.shortcut_triggered.connect(_on_player_shortcut)
			kart.hit_taken.connect(_on_player_hit)
			kart.boost_triggered.connect(_on_player_boost)
			kart.race_finished.connect(_on_player_finished)
		else:
			var ai := KartAI.new()
			add_child(ai)
			var skill := 0.93 + float(i) * 0.025
			ai.setup(kart, spline, built_data["turbo_pads"], GameState.ai_difficulty, 100 + i * 37, player_kart, skill)
			var ai_obs: Array = built_data.get("obstacles", []).duplicate()
			for hz in built_data.get("hazards", []):
				if str(hz.get("kind", "")) in ["frost_geyser", "flame_vent", "chomper", "crusher"] and hz.has("lateral"):
					ai_obs.append({"t": float(hz["t"]), "lat": float(hz["lateral"]), "r": 2.6, "kind": str(hz["kind"])})
			for sc in built_data.get("shortcuts", []):
				ai_obs.append({"t": float(sc["launch_t"]), "lat": float(sc["launch_lat"]), "r": 4.2, "kind": "kicker"})
				ai_obs.append({"t": fposmod(float(sc["launch_t"]) + 6.0 / spline.total_length, 1.0), "lat": float(sc["launch_lat"]), "r": 4.2, "kind": "kicker"})
			ai.obstacles = ai_obs
			ai.on_use_item = Callable(self, "_on_kart_use_item")
			ai_controllers.append(ai)

	# Ensure AI controllers have player_kart reference cleanly
	for ai in ai_controllers:
		ai.player_kart = player_kart

	# 3. Crates, Fruits, Weapons
	track_objects = TrackObjects.new()
	add_child(track_objects)
	var crate_pts: Array[Vector3] = []
	for cp in built_data["crate_points"]:
		crate_pts.append(cp)
	var fruit_pts: Array[Vector3] = []
	for fp in built_data["fruit_points"]:
		fruit_pts.append(fp)
	if GameState.selected_mode == GameState.GameMode.TIME_TRIAL:
		crate_pts.clear() # Pure Time Trial = no weapon RNG, only skill & fruits!
	track_objects.setup(spline, all_karts, crate_pts, fruit_pts)

	# 3b. Dynamic Moving & Static Track Hazards (Boulders, Pendulums, Frost Geysers, Flame Vents!)
	track_hazards = TrackHazards.new()
	add_child(track_hazards)
	track_hazards.setup(spline, all_karts, built_data.get("hazards", []))

	# 4. Time Trial Ghost System
	if GameState.selected_mode == GameState.GameMode.TIME_TRIAL:
		ghost_system = GhostSystem.new()
		add_child(ghost_system)
		ghost_system.start_session(track_id, GameState.get_selected_racer())

	# 5. Dynamic CTR Chase Camera + Atmospheric 3D Weather Particles
	race_camera = RaceCamera.new()
	add_child(race_camera)
	race_camera.make_current()
	race_camera.attach_to(player_kart)
	_build_weather_particles(str(built_data["def"].get("theme", "tiki")))

	# 6. Mobile Touch Controls + CTR HUD Overlay
	var hud_layer := CanvasLayer.new()
	hud_layer.layer = 10
	hud_layer.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(hud_layer)

	var touch_script := load("res://scripts/ui/TouchControls.gd")
	touch_controls = touch_script.new()
	hud_layer.add_child(touch_controls)

	var hud_script := load("res://scripts/ui/RaceHUD.gd")
	hud = hud_script.new()
	hud_layer.add_child(hud)
	hud.setup(player_kart, all_karts, spline, built_data["shortcuts"], track_meta)
	hud.pause_pressed.connect(_toggle_pause)
	hud.resume_pressed.connect(_toggle_pause)
	hud.restart_pressed.connect(_restart_race)
	hud.respawn_pressed.connect(func():
		if player_kart and is_instance_valid(player_kart):
			player_kart.force_respawn()
	)
	hud.menu_pressed.connect(_go_menu)
	hud.next_track_pressed.connect(_go_next_gp)

	player_kart.status_banner.connect(func(key: String, col: Color):
		if hud: hud.show_banner(GameState.t(key), col)
	)

	# Start countdown & audio!
	countdown_timer = 3.2
	countdown_stage = 4
	shortcuts_hit_this_race = 0
	if AudioSynth:
		AudioSynth.start_music(false)
		AudioSynth.set_engine_active(true)
	if hud:
		hud.show_banner(GameState.t("start_boost_hint"), Color(1.0, 0.88, 0.25))

func _build_lineup() -> Array:
	var lineup: Array = []
	var player_r := GameState.get_selected_racer()
	if GameState.selected_mode == GameState.GameMode.TIME_TRIAL or GameState.selected_mode == GameState.GameMode.PRACTICE_ACADEMY:
		lineup.append({"racer": player_r, "is_player": true})
		return lineup

	# 6-Kart CTR Grid (Player starts in position 6 on Arcade/GP for thrilling overtakes, or 4th!)
	var rivals: Array = []
	for r in GameState.RACERS:
		if r["id"] != player_r["id"]:
			rivals.append(r)
	for r in GameState.EXTRA_AI_RACERS:
		rivals.append(r)
	for i in range(min(5, rivals.size())):
		lineup.append({"racer": rivals[i], "is_player": false})
	lineup.append({"racer": player_r, "is_player": true})
	return lineup

func _notification(what: int) -> void:
	# Android hardware back button safely pauses/resumes the race!
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		_toggle_pause()

func _build_weather_particles(theme: String) -> void:
	_weather_nodes.clear()
	_weather_theme = theme
	var mesh := SphereMesh.new()
	mesh.radius = 0.14 if theme == "glacier" else 0.11
	mesh.height = 0.28 if theme == "glacier" else 0.22
	mesh.radial_segments = 5
	mesh.rings = 3
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	if theme == "glacier":
		mat.albedo_color = Color(0.95, 0.99, 1.0, 0.78)
	elif theme == "volcano":
		mat.albedo_color = Color(1.0, 0.56, 0.12, 0.88)
	else:
		mat.albedo_color = Color(1.0, 0.96, 0.74, 0.45)

	var rng := RandomNumberGenerator.new()
	rng.seed = 777
	var count := 34 if theme != "tiki" else 20
	for _i in range(count):
		var mi := MeshInstance3D.new()
		mi.mesh = mesh
		mi.material_override = mat
		add_child(mi)
		var off := Vector3(rng.randf_range(-24.0, 24.0), rng.randf_range(-2.0, 18.0), rng.randf_range(-24.0, 24.0))
		mi.position = (player_kart.global_position if player_kart else Vector3.ZERO) + off
		var vy := rng.randf_range(-5.5, -2.8) if theme == "glacier" else (rng.randf_range(2.8, 6.2) if theme == "volcano" else rng.randf_range(-1.2, 0.8))
		_weather_nodes.append({"node": mi, "off": off, "vel": Vector3(rng.randf_range(-2.2, 2.2), vy, rng.randf_range(-2.2, 2.2))})

func _step_weather_particles(delta: float) -> void:
	if not player_kart or not is_instance_valid(player_kart):
		return
	var center := player_kart.global_position
	for p in _weather_nodes:
		var off: Vector3 = p["off"] + (p["vel"] as Vector3) * delta
		if off.x > 26.0: off.x -= 52.0
		elif off.x < -26.0: off.x += 52.0
		if off.z > 26.0: off.z -= 52.0
		elif off.z < -26.0: off.z += 52.0
		if off.y < -3.0: off.y += 22.0
		elif off.y > 19.0: off.y -= 22.0
		p["off"] = off
		(p["node"] as MeshInstance3D).global_position = center + off

func _process(delta: float) -> void:
	if Input.is_action_just_pressed("pause_game"):
		_toggle_pause()
	if is_paused:
		return

	# Countdown 3 -> 2 -> 1 -> GO!
	if not race_active:
		countdown_timer -= delta
		var stage := int(ceilf(countdown_timer))
		if stage < countdown_stage and stage >= 1 and stage <= 3:
			countdown_stage = stage
			if hud: hud.set_countdown(stage)
			if AudioSynth: AudioSynth.play_sfx("countdown_beep", 0.92 + float(3 - stage) * 0.1)
		elif countdown_timer <= 0.0:
			race_active = true
			if hud: hud.set_countdown(0)
			if AudioSynth: AudioSynth.play_sfx("countdown_go")
			for k in all_karts:
				k.trigger_start_go()

	_poll_player_inputs()
	_resolve_kart_collisions()
	_update_rankings()
	_step_weather_particles(delta)

	if ghost_system:
		ghost_system.step(delta, player_kart)

	if finish_delay > 0.0:
		finish_delay -= delta
		if finish_delay <= 0.0:
			_show_finish_results()

func _resolve_kart_collisions() -> void:
	## Authentic CTR Kart-vs-Kart Elastic Momentum Transfer & Bumper Shove Physics!
	if not race_active:
		return
	var n := all_karts.size()
	for i in range(n):
		var a := all_karts[i]
		if not is_instance_valid(a) or a.respawn_timer > 0.0:
			continue
		for j in range(i + 1, n):
			var b := all_karts[j]
			if not is_instance_valid(b) or b.respawn_timer > 0.0:
				continue
			var diff := a.global_position - b.global_position
			if absf(diff.y) > 2.0:
				continue
			var flat := Vector3(diff.x, 0.0, diff.z)
			var dist := flat.length()
			var min_dist := 2.28
			if dist < min_dist and dist > 0.001:
				var n_dir := flat / dist
				var overlap := min_dist - dist
				a.global_position += n_dir * (overlap * 0.52)
				b.global_position -= n_dir * (overlap * 0.52)
				# Heavier/Faster kart (higher FireTier or speed) shoves the other kart harder!
				var weight_a := 1.0 + float(a.fire_tier) * 0.25 + (0.35 if a.top_speed_mult > 1.02 else 0.0)
				var weight_b := 1.0 + float(b.fire_tier) * 0.25 + (0.35 if b.top_speed_mult > 1.02 else 0.0)
				var rel_spd := clampf((absf(a.forward_speed) + absf(b.forward_speed)) * 0.14, 4.5, 14.0)
				var right_a := Vector3(cos(a.heading_yaw), 0.0, -sin(a.heading_yaw))
				var right_b := Vector3(cos(b.heading_yaw), 0.0, -sin(b.heading_yaw))
				a.apply_kart_bump(n_dir * (rel_spd * (weight_b / weight_a)), signf(n_dir.dot(right_a)), 0.72)
				b.apply_kart_bump(-n_dir * (rel_spd * (weight_a / weight_b)), signf((-n_dir).dot(right_b)), 0.72)

func _poll_player_inputs() -> void:
	if not player_kart or not is_instance_valid(player_kart):
		return
	if player_kart.race_finished_flag:
		player_kart.input_accel = false
		player_kart.input_steer = 0.0
		player_kart.input_hop_held = false
		player_kart.input_brake_uturn = false
		return

	# Merge Touch Controls + Keyboard / Gamepad cleanly!
	var kb_steer := Input.get_axis("steer_left", "steer_right")
	var touch_steer: float = touch_controls.steer_value if touch_controls else 0.0
	player_kart.input_steer = touch_steer if absf(touch_steer) > 0.05 else kb_steer

	var kb_accel := Input.is_action_pressed("accelerate")
	var touch_accel: bool = touch_controls.gas_held if touch_controls else false
	var auto_gas := GameState.auto_accelerate and player_kart.race_started
	player_kart.input_accel = auto_gas or kb_accel or touch_accel

	var kb_brake := Input.is_action_pressed("brake_uturn")
	var touch_brake: bool = touch_controls.uturn_held if touch_controls else false
	player_kart.input_brake_uturn = kb_brake or touch_brake

	var kb_hop := Input.is_action_pressed("hop_drift")
	var touch_hop: bool = touch_controls.hop_held if touch_controls else false
	player_kart.input_hop_held = kb_hop or touch_hop

	if Input.is_action_just_pressed("hop_drift") or (touch_controls and touch_controls.consume_hop_just_pressed()):
		player_kart.input_hop_just_pressed = true

	if Input.is_action_just_pressed("drift_boost") or (touch_controls and touch_controls.consume_boost_just_pressed()):
		player_kart.input_boost_just_pressed = true

	if Input.is_action_just_pressed("use_item") or (touch_controls and touch_controls.consume_item_just_pressed()):
		_on_kart_use_item(player_kart)

	if race_camera:
		var kb_rear := Input.is_key_pressed(KEY_C)
		race_camera.is_looking_back = kb_rear or (touch_controls and touch_controls.look_back_held)

	if touch_controls:
		touch_controls.update_visual_state(player_kart)

func _on_kart_use_item(k: KartPhysics) -> void:
	if track_objects:
		track_objects.fire_item(k, rank_map)

func _update_rankings() -> void:
	var sorted := all_karts.duplicate()
	sorted.sort_custom(func(a: KartPhysics, b: KartPhysics): return a.total_progress > b.total_progress)
	rank_map.clear()
	for i in range(sorted.size()):
		rank_map[sorted[i]] = i + 1
	if hud:
		hud.update_hud(rank_map.get(player_kart, 1), sorted.size())

func _on_player_shortcut(sc_id: String, _sc_name: String) -> void:
	shortcuts_hit_this_race += 1
	GameState.record_shortcut(sc_id)
	if race_camera:
		race_camera.trigger_shake(0.5)

func _on_player_hit(_reason: String) -> void:
	if race_camera:
		race_camera.trigger_shake(1.1)

func _on_player_boost(tier: int, quality: String, _stage: int) -> void:
	if race_camera:
		race_camera.trigger_shake(0.42 if quality == "perfect" or tier >= 3 else 0.22)

func _on_player_finished(total_time: float) -> void:
	if AudioSynth:
		AudioSynth.play_sfx("victory", 1.0, 1.1)
	if race_camera:
		race_camera.start_finish_orbit()
	if ghost_system:
		ghost_system.finish_and_save_if_best(track_meta["id"], total_time, GameState.get_selected_racer())
	finish_delay = 1.6

func _show_finish_results() -> void:
	var sorted := all_karts.duplicate()
	sorted.sort_custom(func(a: KartPhysics, b: KartPhysics): return a.total_progress > b.total_progress)
	var finish_list: Array = []
	var player_rank := 1
	for i in range(sorted.size()):
		var k: KartPhysics = sorted[i]
		if k.is_player:
			player_rank = i + 1
		finish_list.append({
			"id": k.racer_id,
			"name": GameState.get_racer_name(k.racer_data),
			"is_player": k.is_player,
			"time": k.race_elapsed if k.race_finished_flag else (player_kart.race_elapsed + float(i) * 1.45)
		})

	var is_new_rec := GameState.record_times(track_meta["id"], player_kart.race_elapsed, player_kart.best_lap_time)
	if GameState.selected_mode == GameState.GameMode.GRAND_PRIX:
		GameState.add_gp_race_points(finish_list)
		if GameState.gp_track_index >= GameState.TRACKS.size() - 1 and GameState.gp_standings.size() > 0 and GameState.gp_standings[0]["is_player"]:
			GameState.cups_won += 1
			GameState.save_data()

	var medal := ""
	var medals: Dictionary = track_meta.get("medals", {})
	if player_kart.race_elapsed <= float(medals.get("gold", 90.0)):
		medal = "GOLD"
	elif player_kart.race_elapsed <= float(medals.get("silver", 110.0)):
		medal = "SILVER"
	elif player_kart.race_elapsed <= float(medals.get("bronze", 130.0)):
		medal = "BRONZE"

	if hud:
		hud.show_results({
			"rank": player_rank,
			"total_karts": sorted.size(),
			"total_time": player_kart.race_elapsed,
			"best_lap": player_kart.best_lap_time,
			"new_record": is_new_rec,
			"shortcuts": shortcuts_hit_this_race,
			"medal": medal,
			"finish_list": finish_list,
			"is_gp": GameState.selected_mode == GameState.GameMode.GRAND_PRIX,
			"gp_has_next": GameState.selected_mode == GameState.GameMode.GRAND_PRIX and GameState.gp_track_index < GameState.TRACKS.size() - 1
		})

func _toggle_pause() -> void:
	if player_kart and player_kart.race_finished_flag:
		return
	is_paused = not is_paused
	get_tree().paused = is_paused
	if AudioSynth:
		AudioSynth.set_engine_active(not is_paused)
	if hud:
		hud.set_paused(is_paused)

func _restart_race() -> void:
	get_tree().paused = false
	is_paused = false
	if AudioSynth:
		AudioSynth.set_engine_active(false)
	restart_race_requested.emit()

func _go_menu() -> void:
	get_tree().paused = false
	is_paused = false
	if AudioSynth:
		AudioSynth.set_engine_active(false)
	return_to_menu_requested.emit()

func _go_next_gp() -> void:
	get_tree().paused = false
	is_paused = false
	GameState.gp_track_index += 1
	GameState.selected_track_index = GameState.gp_track_index
	next_gp_track_requested.emit()
