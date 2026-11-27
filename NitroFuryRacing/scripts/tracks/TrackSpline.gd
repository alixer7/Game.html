class_name TrackSpline
extends RefCounted

## Closed 3D Catmull-Rom Spline v7.0 (CTR:NF True Philosophy Edition).
## Supports 2.2-2.5 km circuits (400 uniform arc-length samples), banking, road undulations/moguls
## (bump_amp / bump_freq), convex crowned ridges (crown), corrugated surface ribs (rib_amp / rib_freq),
## seamless multi-biome transitions per track, half-pipes, and overpass-safe 3D projection.

var samples: Array[Dictionary] = []
var total_length: float = 0.0
var bounds_min: Vector3 = Vector3.ZERO
var bounds_max: Vector3 = Vector3.ZERO

func build_from_control_points(ctrl_pts: Array, num_samples: int = 400) -> void:
	samples.clear()
	var n := ctrl_pts.size()
	if n < 4:
		push_error("TrackSpline requires at least 4 control points.")
		return

	var raw_steps := num_samples * 4
	var raw_pts: Array[Dictionary] = []
	var cum_len := PackedFloat32Array()
	cum_len.resize(raw_steps + 1)
	cum_len[0] = 0.0

	for i in range(raw_steps):
		var u_global := float(i) / float(raw_steps) * float(n)
		var seg := int(floorf(u_global)) % n
		var local_t := u_global - floorf(u_global)
		var p0: Dictionary = ctrl_pts[(seg - 1 + n) % n]
		var p1: Dictionary = ctrl_pts[seg]
		var p2: Dictionary = ctrl_pts[(seg + 1) % n]
		var p3: Dictionary = ctrl_pts[(seg + 2) % n]

		var pos := _catmull_vec3(p0["pos"], p1["pos"], p2["pos"], p3["pos"], local_t)
		# Natural rolling road undulations / moguls / speed bumps!
		var bump_amp := lerpf(float(p1.get("bump_amp", 0.0)), float(p2.get("bump_amp", 0.0)), local_t)
		var bump_freq := float(p1.get("bump_freq", 2.0))
		if bump_amp > 0.01:
			var env := sin(local_t * PI)
			pos.y += sin(local_t * PI * bump_freq * 2.0) * bump_amp * env

		# Subtle tactile transverse road ribs / stepped ripples!
		var rib_amp := lerpf(float(p1.get("rib_amp", 0.0)), float(p2.get("rib_amp", 0.0)), local_t)
		var rib_freq := float(p1.get("rib_freq", 6.0))
		if rib_amp > 0.01:
			var renv := sin(local_t * PI)
			pos.y += absf(sin(local_t * PI * rib_freq)) * rib_amp * renv

		var w := _catmull_f(float(p0.get("width", 24.0)), float(p1.get("width", 24.0)), float(p2.get("width", 24.0)), float(p3.get("width", 24.0)), local_t)
		var bank := _catmull_f(float(p0.get("bank", 0.0)), float(p1.get("bank", 0.0)), float(p2.get("bank", 0.0)), float(p3.get("bank", 0.0)), local_t)
		var crown := lerpf(float(p1.get("crown", 0.0)), float(p2.get("crown", 0.0)), local_t)
		var wl := lerpf(float(p1.get("wall_l", 2.0)), float(p2.get("wall_l", 2.0)), local_t)
		var wr := lerpf(float(p1.get("wall_r", 2.0)), float(p2.get("wall_r", 2.0)), local_t)
		var ol := lerpf(float(p1.get("off_l", 0.0)), float(p2.get("off_l", 0.0)), local_t)
		var or_w := lerpf(float(p1.get("off_r", 0.0)), float(p2.get("off_r", 0.0)), local_t)

		raw_pts.append({
			"pos": pos,
			"half_width": maxf(7.5, w * 0.5),
			"bank_deg": bank,
			"crown": crown,
			"wall_l": wl,
			"wall_r": wr,
			"off_l": ol,
			"off_r": or_w,
			"surface": str(p1.get("surface", "road")),
			"biome": str(p1.get("biome", "")),
			"tunnel": bool(p1.get("tunnel", false)),
			"bridge": bool(p1.get("bridge", false)),
			"halfpipe_l": bool(p1.get("halfpipe_l", false)),
			"halfpipe_r": bool(p1.get("halfpipe_r", false)),
			"zone": str(p1.get("zone", "Zone"))
		})
		if i > 0:
			cum_len[i] = cum_len[i - 1] + raw_pts[i - 1]["pos"].distance_to(pos)

	total_length = cum_len[raw_steps - 1] + raw_pts[raw_steps - 1]["pos"].distance_to(raw_pts[0]["pos"])
	cum_len[raw_steps] = total_length

	var cursor := 0
	bounds_min = Vector3(1e9, 1e9, 1e9)
	bounds_max = Vector3(-1e9, -1e9, -1e9)

	for s in range(num_samples):
		var target_d := float(s) / float(num_samples) * total_length
		while cursor < raw_steps - 1 and cum_len[cursor + 1] < target_d:
			cursor += 1
		var d0 := cum_len[cursor]
		var d1 := cum_len[cursor + 1]
		var frac := 0.0 if (d1 - d0) < 1e-5 else clampf((target_d - d0) / (d1 - d0), 0.0, 1.0)
		var a: Dictionary = raw_pts[cursor]
		var b: Dictionary = raw_pts[(cursor + 1) % raw_steps]
		var pos: Vector3 = a["pos"].lerp(b["pos"], frac)

		bounds_min.x = minf(bounds_min.x, pos.x)
		bounds_min.y = minf(bounds_min.y, pos.y)
		bounds_min.z = minf(bounds_min.z, pos.z)
		bounds_max.x = maxf(bounds_max.x, pos.x)
		bounds_max.y = maxf(bounds_max.y, pos.y)
		bounds_max.z = maxf(bounds_max.z, pos.z)

		samples.append({
			"t": float(s) / float(num_samples),
			"dist": target_d,
			"pos": pos,
			"half_width": lerpf(a["half_width"], b["half_width"], frac),
			"bank_deg": lerpf(a["bank_deg"], b["bank_deg"], frac),
			"crown": lerpf(a["crown"], b["crown"], frac),
			"wall_l": lerpf(a["wall_l"], b["wall_l"], frac),
			"wall_r": lerpf(a["wall_r"], b["wall_r"], frac),
			"off_l": lerpf(a["off_l"], b["off_l"], frac),
			"off_r": lerpf(a["off_r"], b["off_r"], frac),
			"surface": a["surface"],
			"biome": a["biome"],
			"tunnel": a["tunnel"],
			"bridge": a["bridge"],
			"halfpipe_l": a["halfpipe_l"],
			"halfpipe_r": a["halfpipe_r"],
			"zone": a["zone"],
			"forward": Vector3.FORWARD,
			"right": Vector3.RIGHT,
			"up": Vector3.UP,
			"curvature": 0.0
		})

	for i in range(num_samples):
		var prev_pos: Vector3 = samples[(i - 1 + num_samples) % num_samples]["pos"]
		var next_pos: Vector3 = samples[(i + 1) % num_samples]["pos"]
		var fwd := (next_pos - prev_pos).normalized()
		var flat_right := fwd.cross(Vector3.UP).normalized()
		if flat_right.length_squared() < 0.001:
			flat_right = Vector3.RIGHT
		var flat_up := flat_right.cross(fwd).normalized()
		var bank_rad := deg_to_rad(float(samples[i]["bank_deg"]))
		var right := (flat_right * cos(bank_rad) + flat_up * sin(bank_rad)).normalized()
		var up := right.cross(fwd).normalized()
		samples[i]["forward"] = fwd
		samples[i]["right"] = right
		samples[i]["up"] = up

	for i in range(num_samples):
		var f_prev: Vector3 = samples[(i - 2 + num_samples) % num_samples]["forward"]
		var f_next: Vector3 = samples[(i + 2) % num_samples]["forward"]
		var f0 := Vector3(f_prev.x, 0.0, f_prev.z).normalized()
		var f1 := Vector3(f_next.x, 0.0, f_next.z).normalized()
		var cross_y := f0.cross(f1).y
		samples[i]["curvature"] = asin(clampf(-cross_y, -1.0, 1.0))

func sample_at_t(t: float) -> Dictionary:
	var n := samples.size()
	if n == 0:
		return {"pos": Vector3.ZERO, "forward": Vector3.FORWARD, "right": Vector3.RIGHT, "up": Vector3.UP, "half_width": 12.0, "curvature": 0.0, "crown": 0.0, "biome": ""}
	var wt := fposmod(t, 1.0)
	var f_idx := wt * float(n)
	var i0 := int(floorf(f_idx)) % n
	var i1 := (i0 + 1) % n
	var frac := f_idx - floorf(f_idx)
	var a := samples[i0]
	var b := samples[i1]
	return {
		"t": wt,
		"pos": a["pos"].lerp(b["pos"], frac),
		"forward": a["forward"].lerp(b["forward"], frac).normalized(),
		"right": a["right"].lerp(b["right"], frac).normalized(),
		"up": a["up"].lerp(b["up"], frac).normalized(),
		"half_width": lerpf(a["half_width"], b["half_width"], frac),
		"crown": lerpf(a["crown"], b["crown"], frac),
		"curvature": lerpf(a["curvature"], b["curvature"], frac),
		"surface": a["surface"],
		"biome": a["biome"],
		"zone": a["zone"]
	}

func project_point(world_pos: Vector3, hint_t: float = -1.0) -> Dictionary:
	var n := samples.size()
	var best_idx := 0
	var best_d2 := 1e18

	if hint_t >= 0.0:
		var center := int(round(fposmod(hint_t, 1.0) * float(n))) % n
		var window := 34
		for offset in range(-window, window + 1):
			var idx := (center + offset + n) % n
			var p: Vector3 = samples[idx]["pos"]
			var dv := world_pos - p
			# Strong Y weighting ensures figure-8 overpasses NEVER snap to the lower deck!
			var d2 := dv.x * dv.x + dv.z * dv.z + (dv.y * 3.4) * (dv.y * 3.4)
			if d2 < best_d2:
				best_d2 = d2
				best_idx = idx

	if best_d2 > 76.0 * 76.0 or hint_t < 0.0:
		for idx in range(n):
			var p: Vector3 = samples[idx]["pos"]
			var dv := world_pos - p
			var d2 := dv.x * dv.x + dv.z * dv.z + (dv.y * 3.4) * (dv.y * 3.4)
			if d2 < best_d2:
				best_d2 = d2
				best_idx = idx

	var s := samples[best_idx]
	var rel: Vector3 = world_pos - s["pos"]
	var lat := rel.dot(s["right"])
	return {
		"t": s["t"],
		"index": best_idx,
		"pos": s["pos"],
		"forward": s["forward"],
		"right": s["right"],
		"up": s["up"],
		"half_width": s["half_width"],
		"lateral": lat,
		"lateral_dist": absf(lat),
		"zone": s["zone"],
		"biome": s["biome"]
	}

func get_min_2d_track_clearance(pt_xz: Vector2, extra_corridors: Array = []) -> float:
	## Pure 2D (X, Z) horizontal clearance from ANY road/shoulder/bridge/tunnel/shortcut segment!
	var min_clear := 1e9
	for s in samples:
		var sp: Vector3 = s["pos"]
		var d_center := pt_xz.distance_to(Vector2(sp.x, sp.z))
		var road_extent: float = float(s["half_width"]) + maxf(float(s["off_l"]), float(s["off_r"]))
		var c := d_center - road_extent
		if c < min_clear:
			min_clear = c
	for corr in extra_corridors:
		var cp: Vector2 = corr["xz"]
		var cr: float = float(corr["radius"])
		var c2 := pt_xz.distance_to(cp) - cr
		if c2 < min_clear:
			min_clear = c2
	return min_clear

func _catmull_vec3(p0: Vector3, p1: Vector3, p2: Vector3, p3: Vector3, t: float) -> Vector3:
	var t2 := t * t
	var t3 := t2 * t
	return 0.5 * (
		(2.0 * p1) +
		(-p0 + p2) * t +
		(2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t2 +
		(-p0 + 3.0 * p1 - 3.0 * p2 + p3) * t3
	)

func _catmull_f(p0: float, p1: float, p2: float, p3: float, t: float) -> float:
	var t2 := t * t
	var t3 := t2 * t
	return 0.5 * (
		(2.0 * p1) +
		(-p0 + p2) * t +
		(2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t2 +
		(-p0 + 3.0 * p1 - 3.0 * p2 + p3) * t3
	)
