extends Node

## v8 REAL-PHYSICS verification suite (run with --fixed-fps 60 for speed):
##   godot --headless --fixed-fps 60 res://tests/VerifyV8.tscn -- [tracks=0,1,2] [parts=struct,drive,shortcuts,ai,collide]
## 1. Track structure: >= 2 km, zones, surfaces, indoor/outdoor, elevated, gaps, corner variety, open/closed edges.
## 2. Autopilot lap at base speed on every track: no stuck kart (floor seams), no unexpected fall, jumps give air.
## 3. Every jump shortcut, driven for real at several fire tiers: base speed must FAIL, required tier + hop must SUCCEED.
## 4. Six-kart AI race: everyone keeps moving and completes laps.
## 5. Tiered collisions against real track props (soft bush / medium fence / heavy wall).

var failures: Array[String] = []
var report: Dictionary = {}
var track_list: Array[int] = [0, 1, 2]
var parts: Array = ["struct", "drive", "shortcuts", "ai", "collide"]

func _assert(cond: bool, msg: String) -> void:
	print(("  [PASS] " if cond else "  [FAIL] ") + msg)
	if not cond:
		failures.append(msg)

func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.split("=")
		if kv.size() != 2:
			continue
		if kv[0] == "tracks":
			track_list.clear()
			for s in kv[1].split(","):
				track_list.append(int(s))
		elif kv[0] == "parts":
			parts = Array(kv[1].split(","))
	print("\n=========== NITRO FURY RACING v8 — REAL PHYSICS TRACK VERIFICATION ===========")
	await get_tree().process_frame
	for ti in track_list:
		if ti >= GameState.TRACKS.size():
			continue
		var tid: String = GameState.TRACKS[ti]["id"]
		if not FileAccess.file_exists("res://data/tracks/%s.json" % tid):
			print("  (skip %s: no data)" % tid)
			continue
		report[tid] = {}
		print("\n######## TRACK %d: %s ########" % [ti, tid])
		if "struct" in parts:
			await _test_structure(ti)
		if "drive" in parts:
			await _test_drive(ti)
		if "shortcuts" in parts:
			await _test_shortcuts(ti)
		if "ai" in parts:
			await _test_ai(ti)
		if "collide" in parts:
			await _test_collisions(ti)
	var f := FileAccess.open("user://v8_report.json", FileAccess.WRITE)
	f.store_string(JSON.stringify(report, "  "))
	f.close()
	print("\n==============================================================================")
	if failures.is_empty():
		print("  ALL v8 CHECKS PASSED")
	else:
		print("  FAILED: %d" % failures.size())
		for m in failures:
			print("   - " + m)
	print("  report: " + ProjectSettings.globalize_path("user://v8_report.json"))
	get_tree().quit(0 if failures.is_empty() else 1)

func _make_race(ti: int, mode: int) -> RaceManager:
	GameState.selected_mode = mode
	GameState.selected_track_index = ti
	GameState.mirror_mode = false
	var race := RaceManager.new()
	add_child(race)
	await get_tree().process_frame
	await get_tree().process_frame
	race.countdown_timer = 0.0
	race.race_active = true
	for k in race.all_karts:
		k.race_started = true
	if AudioSynth:
		AudioSynth.set_engine_active(false)
	return race

# ------------------------------------------------------------------------------------------------ 1
func _test_structure(ti: int) -> void:
	print("--- structure ---")
	var tid: String = GameState.TRACKS[ti]["id"]
	var tb := TrackBuilder.new()
	add_child(tb)
	var built := tb.build_track(tid, false)
	var sp: TrackSpline = built["spline"]
	var zones := {}
	var surfaces := {}
	var biomes := {}
	var edges := {}
	var indoor := 0.0
	var elevated := 0.0
	var gaps := 0
	var in_gap := false
	var ymin := 1e9
	var ymax := -1e9
	var wmin := 1e9
	var wmax := 0.0
	for s in sp.samples:
		zones[s["zone"]] = true
		surfaces[s["surface"]] = true
		biomes[s["biome"]] = true
		edges[s["edge_l"]] = true
		edges[s["edge_r"]] = true
		if float(s["ceil"]) > 0.0:
			indoor += sp.step
		if str(s["ground"]) == "elevated":
			elevated += sp.step
		if bool(s["gap"]) and not in_gap:
			gaps += 1
		in_gap = bool(s["gap"])
		ymin = minf(ymin, s["pos"].y)
		ymax = maxf(ymax, s["pos"].y)
		wmin = minf(wmin, float(s["half_width"]) * 2.0)
		wmax = maxf(wmax, float(s["half_width"]) * 2.0)
	var corners := _classify_corners(sp)
	report[tid]["structure"] = {"length": sp.total_length, "zones": zones.size(), "surfaces": surfaces.keys(), "indoor_m": indoor,
		"elevated_m": elevated, "gaps": gaps, "corners": corners, "y_range": [ymin, ymax], "w_range": [wmin, wmax]}
	print("  ", report[tid]["structure"])
	_assert(sp.total_length >= 2000.0, "%s length >= 2 km (%.0f m)" % [tid, sp.total_length])
	_assert(zones.size() >= 8, "%s has >= 8 distinct zones (%d)" % [tid, zones.size()])
	_assert(surfaces.size() >= 4, "%s uses >= 4 road surfaces (%s)" % [tid, str(surfaces.keys())])
	_assert(indoor >= 150.0, "%s has indoor sections (%.0f m)" % [tid, indoor])
	_assert(elevated >= 150.0, "%s has elevated sections (%.0f m)" % [tid, elevated])
	_assert(gaps >= 2, "%s has main-route jump gaps (%d)" % [tid, gaps])
	_assert(ymax - ymin >= 18.0, "%s elevation range >= 18 m (%.1f)" % [tid, ymax - ymin])
	_assert(wmax - wmin >= 9.0, "%s width varies (%.0f..%.0f m)" % [tid, wmin, wmax])
	_assert(edges.has("open") and (edges.has("wall") or edges.has("cliff")), "%s mixes open and closed edges (%s)" % [tid, str(edges.keys())])
	_assert(int(corners.get("sharp_90", 0)) >= 2 and int(corners.get("u_turn", 0)) >= 1 and int(corners.get("sweeper", 0)) >= 2, "%s corner variety %s" % [tid, str(corners)])
	_assert(built["shortcuts"].size() >= 3, "%s has >= 3 jump shortcuts" % tid)
	_assert(built["hazards"].size() + built["obstacles"].size() >= 8, "%s has static + moving obstacles (%d + %d)" % [tid, built["obstacles"].size(), built["hazards"].size()])
	tb.queue_free()
	await get_tree().process_frame

func _classify_corners(sp: TrackSpline) -> Dictionary:
	## integrate heading change over contiguous curved stretches
	var out := {"sharp_90": 0, "u_turn": 0, "sweeper": 0, "chicane_or_kink": 0, "obtuse": 0}
	var acc := 0.0
	var length := 0.0
	var max_k := 0.0
	var prev_sign := 0
	for s in sp.samples + [sp.samples[0]]:
		var k: float = s["curvature"]
		var sg := 0 if absf(k) < 0.004 else int(signf(k))
		if sg != 0 and (prev_sign == 0 or sg == prev_sign):
			acc += k * sp.step
			length += sp.step
			max_k = maxf(max_k, absf(k))
		else:
			if length > 0.0:
				var deg := absf(rad_to_deg(acc))
				var r := 1.0 / maxf(max_k, 0.0001)
				if deg >= 150.0:
					out["u_turn"] += 1
				elif deg >= 75.0 and r < 26.0:
					out["sharp_90"] += 1
				elif deg >= 60.0:
					out["sweeper"] += 1
				elif deg >= 35.0:
					out["obtuse"] += 1
				elif deg >= 12.0:
					out["chicane_or_kink"] += 1
			acc = k * sp.step if sg != 0 else 0.0
			length = sp.step if sg != 0 else 0.0
			max_k = absf(k) if sg != 0 else 0.0
		prev_sign = sg
	return out

# ------------------------------------------------------------------------------------------------ 2
func _test_drive(ti: int) -> void:
	print("--- autopilot lap (real physics) ---")
	var tid: String = GameState.TRACKS[ti]["id"]
	var race: RaceManager = await _make_race(ti, GameState.GameMode.TIME_TRIAL)
	var k := race.player_kart
	race.set_process(false)  # no input polling
	var ap := V8Autopilot.new(k, race.built_data["spline"], race.built_data.get("obstacles", []))
	var flags := {"lap": false, "lap_time": 0.0}
	k.lap_completed.connect(func(_l, lt): flags["lap"] = true; flags["lap_time"] = lt)
	var t := 0.0
	var trace := []
	var last_t := 0.0
	var progress_max := 0.0
	while t < 160.0 and not bool(flags["lap"]):
		ap.step(1.0 / 60.0)
		await get_tree().physics_frame
		t += 1.0 / 60.0
		progress_max = maxf(progress_max, k.total_progress)
		if int(t * 2.0) != int((t - 1.0 / 60.0) * 2.0):
			trace.append([snappedf(t, 0.1), snappedf(k.spline_t, 0.001), snappedf(k.forward_speed, 0.1), k.surface_type, k.global_position.snapped(Vector3(0.1, 0.1, 0.1)), k.is_grounded, k.velocity.snapped(Vector3(0.1, 0.1, 0.1))])
	var st: Dictionary = ap.stats
	var lap_done: bool = flags["lap"]
	report[tid]["drive"] = {"lap_done": lap_done, "time": t, "stats": st, "progress": progress_max}
	print("  lap_done=%s time=%.1fs progress=%.3f stats=%s" % [str(lap_done), t, progress_max, str(st)])
	_assert(lap_done, "%s: autopilot completes a full lap at base speed (%.1f s)" % [tid, t])
	_assert(int(st["stuck_events"]) == 0, "%s: kart never gets stuck on floors/seams (stuck=%d)" % [tid, int(st["stuck_events"])])
	_assert(int(st["respawns"]) <= 1, "%s: no unexpected falls off the main route (respawns=%d)" % [tid, int(st["respawns"])])
	_assert(int(st["jumps"]) >= 2 and float(st["max_air"]) >= 0.45, "%s: main-route jumps give hang time (jumps=%d, max air=%.2fs)" % [tid, int(st["jumps"]), float(st["max_air"])])
	if not lap_done:
		print("  last trace: ", trace.slice(maxi(0, trace.size() - 12)))
	race.queue_free()
	await get_tree().process_frame

# ------------------------------------------------------------------------------------------------ 3
func _test_shortcuts(ti: int) -> void:
	print("--- shortcuts (real physics, per fire tier) ---")
	var tid: String = GameState.TRACKS[ti]["id"]
	var race: RaceManager = await _make_race(ti, GameState.GameMode.TIME_TRIAL)
	race.set_process(false)
	var k := race.player_kart
	var sp: TrackSpline = race.built_data["spline"]
	var res := {}
	for sc in race.built_data["shortcuts"]:
		var req := int(sc["required_fire"])
		var tiers := [[KartPhysics.FireTier.NONE, 0], [KartPhysics.FireTier.NONE, 10], [req, 0], [req, 10], [KartPhysics.FireTier.BLUE, 10]]
		var outcomes := []
		for tr in tiers:
			var ok := await _attempt_shortcut(k, sp, sc, int(tr[0]), int(tr[1]))
			outcomes.append(ok)
		res[sc["id"]] = {"base": outcomes[0], "base_fruit": outcomes[1], "req": outcomes[2], "req_fruit": outcomes[3], "blue": outcomes[4], "skip_m": sc.get("skip_m", 0.0)}
		print("  %-26s base=%s base+10fruit=%s req(%d)=%s req+fruit=%s blue=%s  skips %.0f m" % [sc["id"], str(outcomes[0]), str(outcomes[1]), req, str(outcomes[2]), str(outcomes[3]), str(outcomes[4]), float(sc.get("skip_m", 0.0))])
		_assert(not outcomes[0], "%s: base speed cannot make it" % sc["id"])
		_assert(outcomes[3] and outcomes[4], "%s: required fire + hop makes it (with fruit) / blue fire makes it" % sc["id"])
	report[tid]["shortcuts"] = res
	race.queue_free()
	await get_tree().process_frame

func _attempt_shortcut(k: KartPhysics, sp: TrackSpline, sc: Dictionary, tier: int, fruit: int) -> bool:
	## line up 34 m behind the kicker on its axis at the tier's speed, hop at the lip, steer to the landing in the air,
	## re-hop on platforms; success = grounded on the track beyond the target before a respawn.
	var fwd: Vector3 = sc["launch_fwd"]
	var flat := Vector3(fwd.x, 0.0, fwd.z).normalized()
	var base: Vector3 = sc["launch_base"]
	var back := 34.0
	var start := base - flat * back
	var proj := sp.project_point(start + Vector3(0, 3, 0), float(sc["launch_t"]))
	while back > 8.0:
		start = base - flat * back
		proj = sp.project_point(start + Vector3(0, 3, 0), float(sc["launch_t"]))
		if float(proj["lateral_dist"]) < float(proj["half_width"]) - 1.2:
			break
		back -= 2.0
	var y := sp.surface_point(float(proj["t"]), float(proj["lateral"])).y
	k.respawn_timer = 0.0
	k.spinout_timer = 0.0
	k.fruit_count = fruit
	k.place_at_start(Vector3(start.x, y + 1.0, start.z), atan2(-flat.x, -flat.z), float(sc["launch_t"]))
	k.race_started = true
	k.fruit_count = fruit
	k.reserves = 0.0
	k.fire_tier = KartPhysics.FireTier.NONE
	if tier > 0:
		k.add_boost(tier, 12.0, 0.0, false)
	k.forward_speed = k.get_current_top_speed()
	k.velocity = flat * k.forward_speed
	var target_t: float = sc["target_t"]
	var tp: Vector3 = sc["rejoin_pos"]
	var plats: Array = sc.get("platforms", [])
	var lip: Vector3 = sc["launch_tip"]
	var hopped := false
	var t := 0.0
	var air_time := 0.0
	var launched := false
	var plat_hops := 0
	while t < 7.0:
		if tier > 0:
			k.reserves = maxf(k.reserves, 6.0)
		else:
			# a driver who misses the lined-up turbo pad: no boost of any kind
			k.reserves = 0.0
			if k.fire_tier != 0:
				k.fire_tier = 0
		k.input_accel = true
		k.input_hop_held = false
		k.input_brake_uturn = false
		var to_lip := lip - k.global_position
		var on_kicker := k.is_grounded and k.surface_type == "kicker"
		# hop at the lip (within ~2.2 m) or at a platform's far side
		if not hopped and on_kicker and Vector2(to_lip.x, to_lip.z).length() < 2.6:
			k.input_hop_just_pressed = true
			hopped = true
		if launched and k.is_grounded and on_kicker and plat_hops < plats.size():
			var plip: Vector3 = plats[plat_hops]["lip"]
			var to_pl := plip - k.global_position
			if Vector2(to_pl.x, to_pl.z).length() < 2.6:
				k.input_hop_just_pressed = true
				plat_hops += 1
		# steering: on the ramp keep straight; in the air aim at the landing and brake-turn when the error is large
		var aim := tp
		if launched and plat_hops < plats.size():
			aim = plats[plat_hops]["pos"]
		var to_a := aim - k.global_position
		var desired := atan2(-to_a.x, -to_a.z)
		if not launched:
			desired = atan2(-flat.x, -flat.z)
		var err := wrapf(desired - k.heading_yaw, -PI, PI)
		k.input_steer = clampf(-err * 2.5, -1.0, 1.0)
		if launched and not k.is_grounded:
			# near the landing: align with the road direction for a clean touchdown
			var dist_l := Vector2(to_a.x, to_a.z).length()
			if aim == tp and dist_l < 22.0:
				var s := sp.sample_at_t(target_t)
				var rf: Vector3 = s["forward"]
				var e2 := wrapf(atan2(-rf.x, -rf.z) - k.heading_yaw, -PI, PI)
				k.input_steer = clampf(-e2 * 2.5, -1.0, 1.0)
				k.input_brake_uturn = absf(e2) > 0.35
		await get_tree().physics_frame
		t += 1.0 / 60.0
		if OS.get_environment("NFR_SCDBG") == "1" and int(t * 60.0) % 6 == 0:
			var qd := sp.project_point(k.global_position, target_t)
			printt("    dbg", str(sc["id"]).substr(0, 14), "tier", tier, "t", snappedf(t, 0.01), "pos", k.global_position.snapped(Vector3(0.1, 0.1, 0.1)), "v", snappedf(k.forward_speed, 0.1), "vy", snappedf(k.vertical_speed, 0.1), "gnd", k.is_grounded, k.surface_type, "hop", hopped, "st", snappedf(float(qd["t"]), 0.001), "lat", snappedf(float(qd["lateral"]), 0.1), "h", snappedf(float(qd["height"]), 0.1), "resp", k.respawn_timer > 0.0)
		if not k.is_grounded:
			air_time += 1.0 / 60.0
			if air_time > 0.15 and hopped:
				launched = true
		else:
			air_time = 0.0
		if k.respawn_timer > 0.0:
			return false
		if launched and k.is_grounded and k.surface_type != "kicker":
			var q := sp.project_point(k.global_position, target_t)
			var launch_t: float = sc["launch_t"]
			var need := fposmod(target_t - launch_t, 1.0) * sp.total_length
			var got := fposmod(float(q["t"]) - launch_t, 1.0) * sp.total_length
			var on_road: bool = float(q["lateral_dist"]) <= float(q["half_width"]) + 1.0 and absf(float(q["height"])) < 2.5
			if on_road and got >= need - 14.0 and got <= need + 140.0:
				return true
			if k.forward_speed < 8.0 or not on_road:
				return false
	return false

# ------------------------------------------------------------------------------------------------ 4
func _test_ai(ti: int) -> void:
	print("--- 6-kart AI race ---")
	var tid: String = GameState.TRACKS[ti]["id"]
	var race: RaceManager = await _make_race(ti, GameState.GameMode.ARCADE_RACE)
	race.set_process(true)
	var ap := V8Autopilot.new(race.player_kart, race.built_data["spline"], race.built_data.get("obstacles", []))
	var t := 0.0
	var stuck := {}
	var still := {}
	var resp_log := []
	var was_resp := {}
	var wall0 := Time.get_ticks_msec()
	while t < 100.0:
		ap.step(1.0 / 60.0)
		await get_tree().physics_frame
		t += 1.0 / 60.0
		if int(t * 60.0) % 600 == 0:
			var pp := []
			for kk2 in race.all_karts:
				pp.append(snappedf(kk2.total_progress, 0.01))
			print("    [ai t=%.0fs wall=%.1fs] %s" % [t, float(Time.get_ticks_msec() - wall0) / 1000.0, str(pp)])
		for kk in race.all_karts:
			if kk.is_player:
				continue
			var id := kk.get_instance_id()
			if kk.respawn_timer > 0.0 and not bool(was_resp.get(id, false)):
				var q: Dictionary = race.built_data["spline"].project_point(kk.global_position, kk.spline_t)
				resp_log.append([kk.racer_id, snappedf(kk.spline_t, 0.001), snappedf(float(q["lateral"]), 0.1), str(q["zone"]), kk.surface_type, snappedf(kk.forward_speed, 0.1)])
			was_resp[id] = kk.respawn_timer > 0.0
			if absf(kk.forward_speed) < 2.5 and kk.respawn_timer <= 0.0 and kk.spinout_timer <= 0.0:
				still[id] = float(still.get(id, 0.0)) + 1.0 / 60.0
				if float(still[id]) > 2.0:
					stuck[id] = int(stuck.get(id, 0)) + 1
					still[id] = -3.0
			else:
				still[id] = maxf(0.0, float(still.get(id, 0.0)))
	var prog := []
	var min_prog := 99.0
	for kk in race.all_karts:
		if not kk.is_player:
			prog.append(snappedf(kk.total_progress, 0.01))
			min_prog = minf(min_prog, kk.total_progress)
	report[tid]["ai"] = {"progress_100s": prog, "stuck": stuck.size(), "respawns": resp_log}
	print("  AI respawns: ", resp_log)
	print("  AI progress after 100 s: %s  stuck karts: %d" % [str(prog), stuck.size()])
	_assert(min_prog >= 0.85, "%s: every AI kart keeps racing (min progress %.2f laps in 100 s)" % [tid, min_prog])
	race.queue_free()
	await get_tree().process_frame

# ------------------------------------------------------------------------------------------------ 5
func _test_collisions(ti: int) -> void:
	print("--- tiered collisions vs real props ---")
	var tid: String = GameState.TRACKS[ti]["id"]
	var race: RaceManager = await _make_race(ti, GameState.GameMode.TIME_TRIAL)
	race.set_process(false)
	var k := race.player_kart
	var found := {}
	# drive into a few real colliders of each strength found in the world
	var bodies: Array = []
	_collect_bodies(race.track_builder, bodies)
	for strength in ["soft", "medium", "heavy"]:
		for b in bodies:
			if str(b.get_meta("collision_strength", "")) != strength:
				continue
			var target: Vector3 = Vector3.ZERO
			var got := false
			for c in b.get_children():
				if c is CollisionShape3D and c.shape is CylinderShape3D:
					target = (c as CollisionShape3D).global_position
					got = true
					break
			if not got:
				continue
			var gy: float = race.track_builder.world.ground_height(target.x, target.z)
			if gy < -900.0:
				continue
			var dir := Vector3(1, 0, 0)
			var start := Vector3(target.x, gy + 1.2, target.z) - dir * 14.0
			k.place_at_start(start, atan2(-dir.x, -dir.z), k.spline_t)
			k.race_started = true
			k.mask_timer = 5.0  # ignore off-road slowdown for the test run-up
			k.forward_speed = 30.0
			k.velocity = dir * 30.0
			k.last_collision_strength = ""
			k.wall_bump_cooldown = 0.0
			for _i in range(50):
				k.input_accel = true
				k.input_steer = 0.0
				await get_tree().physics_frame
				if k.last_collision_strength != "":
					break
			if k.last_collision_strength == strength:
				found[strength] = true
				break
	report[tid]["collisions"] = found
	print("  strengths confirmed against real props: ", found.keys())
	_assert(found.has("heavy"), "%s: heavy props (trees / stone) really block the kart" % tid)
	race.queue_free()
	await get_tree().process_frame

func _collect_bodies(n: Node, out: Array) -> void:
	if n is StaticBody3D and n.has_meta("collision_strength"):
		out.append(n)
	for c in n.get_children():
		_collect_bodies(c, out)
