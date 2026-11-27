extends Node
## Diagnostic capture: dumps track spline data to JSON and grabs in-race screenshots at given t values.
## Usage: godot --path . res://tests/tools/DiagCapture.tscn -- out=/abs/dir tracks=0,1,2 ts=0.02,0.3 json=1 shots=1

var out_dir := "user://diag"
var track_list: Array[int] = [0, 1, 2]
var t_list: Array[float] = [0.02, 0.25, 0.5, 0.75]
var do_json := true
var do_shots := true
var cam_mode := "chase"

func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.split("=")
		if kv.size() != 2: continue
		match kv[0]:
			"out": out_dir = kv[1]
			"tracks":
				track_list.clear()
				for s in kv[1].split(","): track_list.append(int(s))
			"ts":
				t_list.clear()
				for s in kv[1].split(","): t_list.append(float(s))
			"json": do_json = kv[1] == "1"
			"shots": do_shots = kv[1] == "1"
			"cam": cam_mode = kv[1]
	DirAccess.make_dir_recursive_absolute(out_dir)
	get_window().size = Vector2i(1280, 720)
	await get_tree().process_frame
	for ti in track_list:
		await _do_track(ti)
	get_tree().quit(0)

func _do_track(ti: int) -> void:
	GameState.selected_mode = GameState.GameMode.TIME_TRIAL
	GameState.selected_track_index = ti
	var race := RaceManager.new()
	add_child(race)
	for _i in range(4): await get_tree().process_frame
	var tid: String = GameState.TRACKS[ti]["id"]
	var sp: TrackSpline = race.built_data["spline"]
	if do_json:
		var arr := []
		for s in sp.samples:
			var p: Vector3 = s["pos"]
			var r: Vector3 = s["right"]
			arr.append({"x": p.x, "y": p.y, "z": p.z, "rx": r.x, "rz": r.z, "hw": s["half_width"], "bank": s["bank_deg"],
				"surf": s["surface"], "biome": s["biome"], "zone": s["zone"], "tunnel": s["tunnel"], "bridge": s["bridge"],
				"curv": s["curvature"], "ol": s["off_l"], "or": s["off_r"], "wl": s["wall_l"], "wr": s["wall_r"]})
		var extra := {}
		extra["length"] = sp.total_length
		extra["shortcuts"] = []
		for sc in race.built_data["shortcuts"]:
			var lt: Vector3 = sc["launch_tip"]
			var rj: Vector3 = sc["rejoin_pos"]
			extra["shortcuts"].append({"id": sc["id"], "lx": lt.x, "lz": lt.z, "ly": lt.y, "tx": rj.x, "tz": rj.z, "ty": rj.y})
		extra["pads"] = []
		for pd in race.built_data["turbo_pads"]:
			var pp: Vector3 = pd["pos"]
			extra["pads"].append({"x": pp.x, "z": pp.z, "super": pd["super"]})
		extra["hazards"] = []
		for hz in race.built_data["hazards"]:
			var hs := sp.sample_at_t(float(hz["t"]))
			extra["hazards"].append({"x": hs["pos"].x, "z": hs["pos"].z, "kind": hz["kind"]})
		var f := FileAccess.open(out_dir + "/track_%s.json" % tid, FileAccess.WRITE)
		f.store_string(JSON.stringify({"samples": arr, "meta": extra}))
		f.close()
	if do_shots:
		race.countdown_timer = 0.0
		race.race_active = true
		if race.hud and race.hud.has_method("set_countdown"):
			race.hud.set_countdown(0)
		for t in t_list:
			var s := sp.sample_at_t(t)
			var fwd: Vector3 = s["forward"]
			var pk: KartPhysics = race.player_kart
			pk.global_position = s["pos"] + Vector3(0, 1.2, 0)
			pk.heading_yaw = atan2(-fwd.x, -fwd.z)
			pk.spline_t = t
			pk.prev_spline_t = t
			pk.velocity = Vector3.ZERO
			pk.forward_speed = 0.0
			if cam_mode == "high":
				race.race_camera.global_position = s["pos"] + Vector3(0, 60, 0) - fwd * 50.0
				race.race_camera.look_at(s["pos"] + fwd * 30.0)
				race.race_camera.set_process(false)
				race.race_camera.set_physics_process(false)
			for _i in range(20): await get_tree().process_frame
			var img := get_viewport().get_texture().get_image()
			img.save_png(out_dir + "/shot_%s_%03d_%s.png" % [tid, int(t * 1000.0), cam_mode])
	race.queue_free()
	for _i in range(3): await get_tree().process_frame
