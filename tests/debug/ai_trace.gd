extends Node
## Debug: trace one AI kart around the track.  -- <difficulty> <seconds> [forced,branch,ids | -]

func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var diff := int(args[0]) if args.size() > 0 else 3
	var secs := int(args[1]) if args.size() > 1 else 60
	var root := Node3D.new()
	add_child(root)
	var tb := TrackBuilder.new()
	tb.load_track("res://data/timberfall.json")
	tb.build(root, 0)
	var race := RaceManager.new()
	root.add_child(race)
	race.setup(tb, 1)
	var lanes: Dictionary = load("res://scripts/race/race_scene.gd").build_lane_graph(tb)
	var k := Kart.new()
	k.params = KartParams.make_class("balanced")
	root.add_child(k)
	k.add_to_group("karts")
	k.teleport(tb.spawn_grid[0])
	race.add_kart(k)
	race.player = k
	var ai := AIDriver.new()
	root.add_child(ai)
	ai.setup(k, lanes, diff, tb.obstacles, 7)
	ai.race = race
	if args.size() > 2:
		# forced route: every branch off except the listed ones ("-" = none)
		for id: String in lanes:
			if id != "main":
				ai.forced_route[id] = id in args[2].split(",")
	k.set_meta("ai", ai)
	k.impact.connect(func(sev: int, st: float, p: Vector3) -> void:
		if sev >= 1:
			var names := []
			for i in k.get_slide_collision_count():
				var c := k.get_slide_collision(i)
				names.append("%s n=%s" % [String((c.get_collider() as Node).get_path()).replace("/root/AITrace/@Node3D@15/Track/", ""), c.get_normal().snapped(Vector3.ONE * 0.01)])
			print("   IMPACT sev=%d strength=%.1f at %s lane=%s idx=%d v=%.1f drift=%s %s" % [sev, st, p.snapped(Vector3.ONE * 0.1), ai.lane, ai.idx, k.speed, k.drifting, names]))
	race.start_countdown()
	for f in secs * 60:
		await get_tree().physics_frame
		if race.state == "countdown":
			k.in_throttle = 1.0
		if f % 60 == 0:
			var pr := race.progress_of(k)
			var rl: RacingLine = lanes[ai.lane].line
			var target: Vector3 = rl.pts[ai.idx]
			print("t=%3d lane=%-14s idx=%4d dist_to_line=%5.1f v=%5.1f steer=%5.2f thr=%.1f brk=%.1f drift=%s stage=%d res=%.1f surf=%s rel=%.0f lap=%d pos=%s" % [f / 60, ai.lane, ai.idx, Vector2(target.x - k.global_position.x, target.z - k.global_position.z).length(), k.speed, k.in_steer, k.in_throttle, k.in_brake, k.drifting, k.drift_stage, k.reserve, Surfaces.NAMES[k.surface], float(pr.rel), int(pr.lap), k.global_position.snapped(Vector3.ONE)])
		if OS.get_environment("WK_TRACE_FROM") != "" and f >= int(OS.get_environment("WK_TRACE_FROM")) * 60 and f < int(OS.get_environment("WK_TRACE_FROM")) * 60 + 90 and f % 3 == 0:
			var cols := []
			for i in k.get_slide_collision_count():
				var c := k.get_slide_collision(i)
				cols.append("%s n=%s" % [(c.get_collider() as Node).get_path(), c.get_normal().snapped(Vector3.ONE * 0.01)])
			var sp: SplinePath = tb.branches[ai.lane] if tb.branches.has(ai.lane) else tb.main
			var j := sp.nearest_index(k.global_position, 20.0)
			print("   f=%d v=%.1f pos=%s vel=%s grounded=%s air=%.2f lane=%s idx=%d cols=%s" % [f, k.speed, k.global_position.snapped(Vector3.ONE * 0.01), k.velocity.snapped(Vector3.ONE * 0.1), k.grounded, k.airtime, ai.lane, ai.idx, cols])
		if false:
			var rl2: RacingLine = lanes[ai.lane].line
			print("  %.2f lane=%s idx=%d off=%.1f v=%.1f drift=%s dir=%d slip=%.0f yawr=%.2f steer=%.2f turn34=%.0f %s" % [f / 60.0, ai.lane, ai.idx, Vector2(rl2.pts[ai.idx].x - k.global_position.x, rl2.pts[ai.idx].z - k.global_position.z).length(), k.speed, k.drifting, k.drift_dir, rad_to_deg(k.slip_angle), k.yaw_rate, k.in_steer, rad_to_deg(ai._turn_ahead(ai.lane, ai.idx, 34.0)), ai.dbg if k.drifting else ""])
		if race.progress_of(k).finished:
			print("FINISHED at ", race.race_time)
			break
	get_tree().quit()
