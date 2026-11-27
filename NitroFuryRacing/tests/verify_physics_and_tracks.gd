extends Node

## Automated v7.0 CTR:NF True Philosophy QA Suite:
## Verifies Rebalanced Speed & +18% Wumpa Economy, Abyss Wumpa Wipe, Precision Start-Boost Bar,
## Zero Floor-Blocking Fix, Tiered Collisions (Soft/Medium/Heavy), 3 Multi-Biome >=2km Tracks,
## 9 Pure Jump-Based Platforming Shortcuts (0 Side Bridges!), Zero Prop Overlap, 60FPS Budget & Soak!

var failures: Array[String] = []

func _assert(cond: bool, msg: String) -> void:
	if cond:
		print("  [PASS] ", msg)
	else:
		print("  [FAIL] ", msg)
		failures.append(msg)

func _ready() -> void:
	print("\n================================================================")
	print("  NITRO FURY RACING v7.0 — CTR:NF TRUE PHILOSOPHY QA SUITE")
	print("================================================================\n")

	await get_tree().process_frame
	await _test_ctr_physics_v7()
	await _test_all_tracks_v7()
	await _test_zero_freeze_soak()

	print("\n================================================================")
	if failures.is_empty():
		print("  ALL v7.0 CTR:NF CHECKS PASSED! (0 failures)")
		print("================================================================\n")
		get_tree().quit(0)
	else:
		print("  FAILED: ", failures.size(), " issue(s):")
		for f in failures:
			print("    - ", f)
		print("================================================================\n")
		get_tree().quit(1)

func _test_ctr_physics_v7() -> void:
	print("--- 1. CTR:NF Rebalanced Speed, +18% Wumpa Economy, Start Bar & Tiered Collisions ---")
	var test_root := Node3D.new()
	add_child(test_root)

	var floor_sb := StaticBody3D.new()
	floor_sb.collision_layer = 1
	floor_sb.set_meta("surface_type", "road")
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(800.0, 2.0, 800.0)
	cs.shape = box
	floor_sb.position = Vector3(0.0, -1.0, 0.0)
	floor_sb.add_child(cs)
	test_root.add_child(floor_sb)

	var kart := KartPhysics.new()
	test_root.add_child(kart)
	kart.setup_racer(GameState.RACERS[0], false, null, 3)
	kart.place_at_start(Vector3(0.0, 0.2, 0.0), 0.0)

	# A. Precision Start-Line Boost Timing Bar (Gold Sweet Spot vs Overheat!)
	kart.start_rev_meter = 0.85
	kart.start_rev_overheated = false
	kart.trigger_start_go()
	_assert(kart.fire_tier == KartPhysics.FireTier.ORANGE and kart.reserves >= 2.0, "Start-Line Gold Sweet Spot (85%%) awards Perfect Orange Launch (tier=%d, res=%.2fs)" % [kart.fire_tier, kart.reserves])

	kart.place_at_start(Vector3(0.0, 0.2, 0.0), 0.0)
	kart.race_started = false
	kart.start_rev_meter = 1.0
	kart.start_rev_overheated = true
	kart.trigger_start_go()
	_assert(kart.fire_tier == KartPhysics.FireTier.NONE and kart.start_stall_timer > 0.2, "Start-Line Overheat triggers backfire stall & 0 boost")
	kart.start_stall_timer = 0.0

	# B. Rebalanced CTR:NF Base Speed (~34 m/s) + Crucial +18% Wumpa Economy (~40.1 m/s)!
	kart.place_at_start(Vector3(0.0, 0.2, 0.0), 0.0)
	kart.race_started = true
	kart.input_accel = true
	for _i in range(210):
		await get_tree().physics_frame
	var base_spd := kart.forward_speed
	var normal_friction := kart.current_tire_friction
	_assert(base_spd >= 33.2 and base_spd <= 34.8, "Rebalanced controllable CTR:NF base top speed (~34 m/s): %.2f m/s" % base_spd)
	_assert(float(KartPhysics.TIER_SPEEDS[KartPhysics.FireTier.BLUE]) <= 56.0, "Blue Fire speed tamed for crisp control (%.1f m/s)" % float(KartPhysics.TIER_SPEEDS[KartPhysics.FireTier.BLUE]))

	kart.add_fruit(10)
	for _i in range(70):
		await get_tree().physics_frame
	_assert(kart.forward_speed >= base_spd + 5.4, "10 Wumpa Fruits give decisive +18%% base speed boost (%.2f -> %.2f m/s)" % [base_spd, kart.forward_speed])

	# C. Abyss Respawn Wipes ALL Wumpa Fruits!
	kart.force_respawn(true)
	_assert(kart.fruit_count == 0, "Falling into abyss wipes ALL collected Wumpa Fruits (count=%d)" % kart.fruit_count)
	kart.respawn_timer = 0.0

	# D. FLOOR-SEAM ZERO-BLOCKING FIX: Layer-1 vertical step must NEVER trigger wall crash or kill reserves!
	var floor_step := StaticBody3D.new()
	floor_step.collision_layer = 1 # Road floor layer!
	floor_step.set_meta("surface_type", "road")
	var fsc := CollisionShape3D.new()
	var fsb := BoxShape3D.new()
	fsb.size = Vector3(12.0, 2.5, 1.0)
	fsc.shape = fsb
	floor_step.position = Vector3(0.0, 1.0, -28.0)
	floor_step.add_child(fsc)
	test_root.add_child(floor_step)

	kart.place_at_start(Vector3(0.0, 0.2, -20.0), 0.0)
	kart.race_started = true
	kart.add_fruit(10)
	kart.add_boost(KartPhysics.FireTier.SACRED, 4.0, 10.0, false)
	kart.forward_speed = 40.0
	kart.input_accel = true
	for _i in range(18):
		await get_tree().physics_frame
	_assert(kart.fire_tier == KartPhysics.FireTier.SACRED and kart.fruit_count == 10, "Layer-1 floor collision NEVER triggers wall crash, reserve loss, or Wumpa loss!")
	floor_step.queue_free()

	# E. TIERED COLLISION SEVERITY (Soft Bush vs Medium Fence vs Heavy Stone Wall!)
	var soft_wall := _make_test_wall(test_root, Vector3(0.0, 1.2, -55.0), "soft")
	kart.place_at_start(Vector3(0.0, 0.2, -48.0), 0.0)
	kart.race_started = true
	kart.add_fruit(10)
	kart.add_boost(KartPhysics.FireTier.ORANGE, 3.5, 8.0, false)
	kart.forward_speed = 32.0
	kart.input_accel = true
	for _i in range(20):
		await get_tree().physics_frame
	_assert(kart.last_collision_strength == "soft" and kart.fruit_count == 10 and kart.reserves > 1.5, "Soft prop impact (bush) preserves reserves & loses 0 Wumpa (fruits=%d)" % kart.fruit_count)
	soft_wall.queue_free()

	var med_wall := _make_test_wall(test_root, Vector3(0.0, 1.2, -85.0), "medium")
	kart.place_at_start(Vector3(0.0, 0.2, -78.0), 0.0)
	kart.race_started = true
	kart.add_fruit(10)
	kart.wall_bump_cooldown = 0.0
	kart.forward_speed = 32.0
	kart.input_accel = true
	for _i in range(20):
		await get_tree().physics_frame
	_assert(kart.last_collision_strength == "medium" and kart.fruit_count == 9, "Medium prop impact (wooden fence) loses exactly 1 Wumpa (fruits=%d)" % kart.fruit_count)
	med_wall.queue_free()

	var heavy_wall := _make_test_wall(test_root, Vector3(0.0, 1.2, -115.0), "heavy")
	kart.place_at_start(Vector3(0.0, 0.2, -108.0), 0.0)
	kart.race_started = true
	kart.add_fruit(10)
	kart.wall_bump_cooldown = 0.0
	kart.add_boost(KartPhysics.FireTier.SACRED, 3.5, 8.0, false)
	kart.forward_speed = 40.0
	kart.input_accel = true
	for _i in range(20):
		await get_tree().physics_frame
	_assert(kart.last_collision_strength == "heavy" and kart.reserves == 0.0 and kart.fruit_count <= 8, "Heavy wall impact kills reserves & drops 2-3 Wumpa (fruits=%d)" % kart.fruit_count)
	heavy_wall.queue_free()

	# F. Silky Obtuse Wide-Arc Power-Slide + Increased Tire Friction + Triple Drift + Air U-Turn!
	kart.place_at_start(Vector3(0.0, 0.2, 0.0), 0.0)
	kart.race_started = true
	kart.add_fruit(10)
	kart.forward_speed = 36.0
	kart.input_accel = true
	kart.input_steer = 1.0
	kart.input_hop_held = true
	kart.input_hop_just_pressed = true
	await get_tree().physics_frame
	for _i in range(65):
		await get_tree().physics_frame
		if kart.is_drifting:
			break
	_assert(kart.is_drifting, "Hop + Steer latches cleanly into CTR Power-Slide")

	kart.input_steer = 0.0
	for _i in range(25):
		await get_tree().physics_frame
	var drift_friction := kart.current_tire_friction
	var neutral_drift_yaw_rate := absf(kart.angular_yaw_vel)
	_assert(drift_friction >= normal_friction * 2.5, "Tire friction dramatically increases during Drift (%.1f -> %.1f)" % [normal_friction, drift_friction])
	_assert(neutral_drift_yaw_rate >= 0.45 and neutral_drift_yaw_rate <= 0.72, "Drift follows silky obtuse wide arc (%.2f rad/s)" % neutral_drift_yaw_rate)

	var boosts_done := 0
	for _step in range(230):
		if kart.is_drifting and kart.drift_charge >= 0.80:
			kart.input_boost_just_pressed = true
			boosts_done += 1
		await get_tree().physics_frame
		if boosts_done >= 3 and not kart.is_drifting:
			break
	kart.input_hop_held = false
	kart.input_steer = 0.0
	_assert(boosts_done == 3, "Executed full 3-stage Power-Slide Triple Boost (%d/3)" % boosts_done)

	kart.trigger_turbo_pad(true)
	var yaw_before := kart.heading_yaw
	kart.input_hop_just_pressed = true
	await get_tree().physics_frame
	kart.input_brake_uturn = true
	kart.input_steer = -1.0
	for _i in range(28):
		await get_tree().physics_frame
	var yaw_delta := absf(angle_difference(yaw_before, kart.heading_yaw))
	kart.input_brake_uturn = false
	kart.input_steer = 0.0
	_assert(rad_to_deg(yaw_delta) >= 75.0, "Air-Brake U-Turn pivots sharply mid-air (%.1f deg)" % rad_to_deg(yaw_delta))
	_assert(kart.fire_tier == KartPhysics.FireTier.BLUE and kart.reserves > 2.0, "Air-Brake U-Turn preserves 100%% of Blue Fire & Reserves")

	for _i in range(45):
		await get_tree().physics_frame
	kart.apply_hit("test_tnt", true)
	for _h in range(5):
		kart.input_hop_just_pressed = true
		await get_tree().physics_frame
	_assert(not kart.tnt_attached, "5 Hops cleanly shake off ticking TNT crate!")

	test_root.queue_free()
	await get_tree().process_frame

func _make_test_wall(parent: Node3D, pos: Vector3, strength: String) -> StaticBody3D:
	var sb := StaticBody3D.new()
	sb.collision_layer = 2
	sb.set_meta("surface_type", "wall")
	sb.set_meta("collision_strength", strength)
	var cs := CollisionShape3D.new()
	var b := BoxShape3D.new()
	b.size = Vector3(12.0, 3.0, 1.2)
	cs.shape = b
	sb.position = pos
	sb.add_child(cs)
	parent.add_child(sb)
	return sb

func _test_all_tracks_v7() -> void:
	print("\n--- 2. Multi-Biome >= 2.0 km Tracks, Crowned Profiles & 9 Pure Jump Shortcuts ---")
	for t_meta in GameState.TRACKS:
		var tid: String = t_meta["id"]
		print("\n  [TRACK] %s (%s)" % [t_meta["name_en"], tid])
		var builder := TrackBuilder.new()
		add_child(builder)
		var built := builder.build_track(tid)
		var sp: TrackSpline = built["spline"]

		_assert(sp.total_length >= 2000.0 and sp.total_length <= 2800.0, "CTR:NF >= 2.0 km circuit length verified: %.1fm" % sp.total_length)

		var biomes := {}
		var min_w := 999.0
		var max_w := 0.0
		var max_crown := 0.0
		for sm in sp.samples:
			biomes[str(sm.get("biome", ""))] = true
			var w: float = float(sm["half_width"]) * 2.0
			min_w = minf(min_w, w)
			max_w = maxf(max_w, w)
			max_crown = maxf(max_crown, float(sm.get("crown", 0.0)))
		_assert(biomes.size() >= 3, "Multi-biome world within single track: %d distinct biomes (%s)" % [biomes.size(), str(biomes.keys())])
		_assert(min_w <= 21.0 and max_w >= 26.5, "Dynamic width pacing (narrow %.1fm <-> wide %.1fm)" % [min_w, max_w])
		_assert(max_crown >= 0.35, "Convex crowned road ridges active (max crown=%.2fm)" % max_crown)
		_assert(built["hazards"].size() >= 5, "Strategic static & moving hazards configured: %d" % built["hazards"].size())
		_assert(built["turbo_pads"].size() >= 5, "Smart Turbo Pad pacing configured: %d" % built["turbo_pads"].size())
		_assert(built["shortcuts"].size() == 3, "Has 3 pure jump-based CTR:NF shortcuts (9 total across 3 tracks!)")

		var has_island := false
		for sc in built["shortcuts"]:
			var jtype: String = str(sc.get("jump_type", ""))
			_assert(not bool(sc.get("has_side_bridge", true)), "Shortcut '%s' (%s): ZERO side-lane/bypass bridge!" % [sc["id"], jtype])
			if jtype == "stepping_island":
				has_island = true
			var gap_h: float = float(sc["gap_horizontal"])
			var dy: float = float(sc["gap_delta_y"])
			var pitch: float = deg_to_rad(float(sc["launch_pitch_deg"]))
			var req_fire: int = int(sc["required_fire"])
			# Skilled player carries Required Fire + Wumpa speed bonus (+14% at ~8 Wumpa)!
			var req_speed: float = float(KartPhysics.TIER_SPEEDS[req_fire]) * 1.14

			var base_reach := _calc_ballistic_reach(KartPhysics.BASE_TOP_SPEED, pitch, 0.0, dy)
			_assert(base_reach < gap_h - 4.0, "Shortcut '%s': Base drive-off CANNOT reach (reach=%.1fm < gap=%.1fm)" % [sc["id"], base_reach, gap_h])

			var hop_vy := KartPhysics.HOP_IMPULSE + 6.4
			var pro_reach := _calc_ballistic_reach(req_speed, pitch, hop_vy, dy)
			_assert(pro_reach >= gap_h + 4.0, "Shortcut '%s' (%s): Boost + Hop CLEARS cleanly (reach=%.1fm >= gap=%.1fm)" % [sc["id"], jtype, pro_reach, gap_h])
		_assert(has_island, "Track includes a Floating Stepping-Stone Island Double-Hop shortcut!")

		var prop_bounds: Array = built.get("prop_bounds", [])
		var overlap_count := 0
		for pb in prop_bounds:
			var p3: Vector3 = pb["pos"]
			var pr: float = float(pb["radius"])
			var clear_2d := sp.get_min_2d_track_clearance(Vector2(p3.x, p3.z))
			if clear_2d < pr + 1.5:
				overlap_count += 1
		_assert(overlap_count == 0 and prop_bounds.size() > 25, "Zero prop/mountain overlap with road in 2D XZ (0/%d props)" % prop_bounds.size())

		var mesh_count := _count_mesh_instances(builder)
		var mm_count := _count_multimeshes(builder)
		_assert(mesh_count < 450 and mm_count >= 3, "60FPS draw-call budget verified: %d MeshInstance3D (< 450) + %d MultiMesh batches" % [mesh_count, mm_count])

		var built_m := builder.build_track(tid, true)
		var sp_m: TrackSpline = built_m["spline"]
		_assert(absf(sp_m.total_length - sp.total_length) < 12.0, "Mirror Mode generates cleanly (len=%.1fm)" % sp_m.total_length)

		builder.queue_free()
		await get_tree().process_frame

func _count_mesh_instances(root: Node) -> int:
	var c := 1 if (root is MeshInstance3D) else 0
	for ch in root.get_children():
		c += _count_mesh_instances(ch)
	return c

func _count_multimeshes(root: Node) -> int:
	var c := 1 if (root is MultiMeshInstance3D) else 0
	for ch in root.get_children():
		c += _count_multimeshes(ch)
	return c

func _calc_ballistic_reach(speed: float, pitch_rad: float, extra_hop_vy: float, target_dy: float) -> float:
	var vx := speed * cos(pitch_rad)
	var vy := speed * sin(pitch_rad) * (0.62 if extra_hop_vy > 0.0 else 1.0) + extra_hop_vy
	var g := KartPhysics.GRAVITY
	var disc := vy * vy - 2.0 * g * target_dy
	if disc < 0.0:
		return 0.0
	var t_flight := (vy + sqrt(disc)) / g
	return maxf(0.0, vx * t_flight)

func _test_zero_freeze_soak() -> void:
	print("\n--- 3. Live 6-Kart Multi-Biome Drift + Weapon Pool Zero-Freeze Soak Test ---")
	GameState.selected_mode = GameState.GameMode.ARCADE_RACE
	GameState.selected_track_index = 0
	var race := RaceManager.new()
	add_child(race)
	await get_tree().process_frame
	race.countdown_timer = 0.0
	race.race_active = true
	for k in race.all_karts:
		k.race_started = true

	var max_frame_ms := 0.0
	var prev_us := Time.get_ticks_usec()
	for f in range(180):
		race.player_kart.input_accel = true
		race.player_kart.input_hop_held = (f >= 20 and f < 46)
		if f == 20:
			race.player_kart.input_hop_just_pressed = true
			race.player_kart.input_steer = 0.35
		elif f >= 46:
			race.player_kart.input_steer = 0.0
		if f == 40 or f == 100:
			race.player_kart.held_item = "missile" if f == 40 else "bomb"
			race.player_kart.item_roulette_timer = 0.0
			race.track_objects.fire_item(race.player_kart, race.rank_map)
		if f == 120:
			race.player_kart.held_item = "tnt"
			race.player_kart.item_roulette_timer = 0.0
			race.track_objects.fire_item(race.player_kart, race.rank_map)
		await get_tree().physics_frame
		var now_us := Time.get_ticks_usec()
		var dt_ms := float(now_us - prev_us) / 1000.0
		prev_us = now_us
		if f >= 5:
			max_frame_ms = maxf(max_frame_ms, dt_ms)

	var all_finite := true
	for k in race.all_karts:
		if not is_finite(k.global_position.x) or not is_finite(k.global_position.y) or not is_finite(k.global_position.z):
			all_finite = false
	_assert(all_finite, "Zero NaN / corrupted transforms across 6 racing karts + weapons + hazards")
	_assert(max_frame_ms < 85.0, "Zero main-thread freeze/stall during 180-frame soak (max frame=%.1fms)" % max_frame_ms)
	_assert(race.player_kart.forward_speed > 20.0, "Player kart accelerates smoothly across crowned multi-biome road (%.1f m/s)" % race.player_kart.forward_speed)
	race.queue_free()
	await get_tree().process_frame
