class_name TrackSpline
extends RefCounted

## v8 Track centre line loaded from the track designer (tools/trackgen -> res://data/tracks/<id>.json).
## Samples every ~2 m carry the full road description: width, bank, crown, surface, edge types (wall / fence /
## rail / open / shoulder / halfpipe / cliff), flush shoulders, indoor ceiling, ground mode (terrain / elevated /
## indoor / void / water), real gaps for main-route jumps, biome & zone.
## Keeps the v7 API (samples, sample_at_t, project_point, total_length, get_min_2d_track_clearance).

var samples: Array[Dictionary] = []
var total_length: float = 0.0
var step: float = 2.0
var bounds_min: Vector3 = Vector3.ZERO
var bounds_max: Vector3 = Vector3.ZERO
var patches: Array[Dictionary] = []
var mirrored: bool = false

const CELL := 16.0
var _grid: Dictionary = {}

func load_from_data(data: Dictionary, mirror: bool = false) -> void:
	samples.clear()
	mirrored = mirror
	var cols: Dictionary = data["cols"]
	var n: int = int(data["count"])
	total_length = float(data["length"])
	step = float(data["step"])
	var xs: Array = cols["x"]
	var ys: Array = cols["y"]
	var zs: Array = cols["z"]
	var mx := -1.0 if mirror else 1.0
	bounds_min = Vector3(1e9, 1e9, 1e9)
	bounds_max = Vector3(-1e9, -1e9, -1e9)
	for i in range(n):
		var l := "l" if not mirror else "r"
		var r := "r" if not mirror else "l"
		var pos := Vector3(float(xs[i]) * mx, float(ys[i]), float(zs[i]))
		bounds_min = bounds_min.min(pos)
		bounds_max = bounds_max.max(pos)
		var el: String = str(cols["edge_" + l][i])
		var er: String = str(cols["edge_" + r][i])
		var ceil_h := float(cols["ceil"][i])
		var ground: String = str(cols["ground"][i])
		var wl := float(cols["wall_" + l][i])
		var wr := float(cols["wall_" + r][i])
		samples.append({
			"t": float(i) / float(n),
			"dist": float(i) * step,
			"pos": pos,
			"half_width": float(cols["w"][i]) * 0.5,
			"bank_deg": float(cols["bank"][i]) * mx,
			"crown": float(cols["crown"][i]),
			"curvature": float(cols["curv"][i]) * mx,
			"surface": str(cols["surf"][i]),
			"biome": str(cols["biome"][i]),
			"zone": str(cols["zone"][i]),
			"edge_l": el,
			"edge_r": er,
			"wall_l": wl if el in ["wall", "fence", "rail", "cliff"] else 0.0,
			"wall_r": wr if er in ["wall", "fence", "rail", "cliff"] else 0.0,
			"wall_h_l": wl,
			"wall_h_r": wr,
			"sh_l": float(cols["sh_" + l][i]),
			"sh_r": float(cols["sh_" + r][i]),
			"off_l": float(cols["sh_" + l][i]),
			"off_r": float(cols["sh_" + r][i]),
			"shs_l": str(cols["shs_" + l][i]),
			"shs_r": str(cols["shs_" + r][i]),
			"ceil": ceil_h,
			"ground": ground,
			"deck": str(cols["deck"][i]),
			"theme_wall": str(cols["theme_wall"][i]),
			"gap": bool(cols["gap"][i]),
			"ramp": bool(cols["ramp"][i]),
			"tunnel": ceil_h > 0.0,
			"bridge": ground == "elevated",
			"halfpipe_l": el == "halfpipe",
			"halfpipe_r": er == "halfpipe",
			"forward": Vector3.FORWARD,
			"right": Vector3.RIGHT,
			"up": Vector3.UP,
		})
	_compute_frames()
	_build_grid()
	patches.clear()
	var feats: Dictionary = data.get("features", {})
	for p in feats.get("patches", []):
		var l0 := float(p["lat0"]) * mx
		var l1 := float(p["lat1"]) * mx
		patches.append({"t0": float(p["d0"]) / total_length, "t1": float(p["d1"]) / total_length,
			"lat0": minf(l0, l1), "lat1": maxf(l0, l1), "surf": str(p["surf"])})

func _compute_frames() -> void:
	var n := samples.size()
	for i in range(n):
		var prev_pos: Vector3 = samples[(i - 1 + n) % n]["pos"]
		var next_pos: Vector3 = samples[(i + 1) % n]["pos"]
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

func _cell_key(x: float, z: float) -> Vector2i:
	return Vector2i(int(floor(x / CELL)), int(floor(z / CELL)))

func _build_grid() -> void:
	_grid.clear()
	for i in range(samples.size()):
		var p: Vector3 = samples[i]["pos"]
		var k := _cell_key(p.x, p.z)
		if not _grid.has(k):
			_grid[k] = PackedInt32Array()
		var arr: PackedInt32Array = _grid[k]
		arr.append(i)
		_grid[k] = arr

func candidates_near(x: float, z: float, radius: float) -> PackedInt32Array:
	var out := PackedInt32Array()
	var r_cells := int(ceil(radius / CELL))
	var c := _cell_key(x, z)
	for dx in range(-r_cells, r_cells + 1):
		for dz in range(-r_cells, r_cells + 1):
			var k := Vector2i(c.x + dx, c.y + dz)
			if _grid.has(k):
				out.append_array(_grid[k])
	return out

func index_at_t(t: float) -> int:
	var n := samples.size()
	return int(round(fposmod(t, 1.0) * float(n))) % n

func t_of_dist(d: float) -> float:
	return fposmod(d / total_length, 1.0)

func sample_at_t(t: float) -> Dictionary:
	var n := samples.size()
	if n == 0:
		return {"pos": Vector3.ZERO, "forward": Vector3.FORWARD, "right": Vector3.RIGHT, "up": Vector3.UP, "half_width": 12.0, "curvature": 0.0, "crown": 0.0, "biome": "", "surface": "stone", "zone": "", "gap": false}
	var wt := fposmod(t, 1.0)
	var f_idx := wt * float(n)
	var i0 := int(floorf(f_idx)) % n
	var i1 := (i0 + 1) % n
	var frac := f_idx - floorf(f_idx)
	var a := samples[i0]
	var b := samples[i1]
	return {
		"t": wt,
		"index": i0,
		"pos": a["pos"].lerp(b["pos"], frac),
		"forward": a["forward"].lerp(b["forward"], frac).normalized(),
		"right": a["right"].lerp(b["right"], frac).normalized(),
		"up": a["up"].lerp(b["up"], frac).normalized(),
		"half_width": lerpf(a["half_width"], b["half_width"], frac),
		"crown": lerpf(a["crown"], b["crown"], frac),
		"curvature": lerpf(a["curvature"], b["curvature"], frac),
		"surface": a["surface"],
		"biome": a["biome"],
		"zone": a["zone"],
		"gap": a["gap"],
		"off_l": a["off_l"],
		"off_r": a["off_r"],
		"ceil": a["ceil"],
		"ground": a["ground"],
		"edge_l": a["edge_l"],
		"edge_r": a["edge_r"],
	}

## World point on the driving surface (bank & crown aware) at track parameter t and lateral offset.
func surface_point(t: float, lateral: float) -> Vector3:
	var s := sample_at_t(t)
	var hw: float = s["half_width"]
	var cr: float = float(s["crown"]) * maxf(0.0, 1.0 - absf(lateral) / maxf(1.0, hw))
	return s["pos"] + s["right"] * lateral + s["up"] * cr

func _dist2_weighted(world_pos: Vector3, p: Vector3) -> float:
	var dv := world_pos - p
	# Strong Y weighting keeps overpass / underpass decks apart.
	return dv.x * dv.x + dv.z * dv.z + (dv.y * 3.4) * (dv.y * 3.4)

func project_point(world_pos: Vector3, hint_t: float = -1.0) -> Dictionary:
	var n := samples.size()
	var best_idx := 0
	var best_d2 := 1e18
	if hint_t >= 0.0:
		var center := int(round(fposmod(hint_t, 1.0) * float(n))) % n
		for offset in range(-36, 37):
			var idx := (center + offset + n) % n
			var d2 := _dist2_weighted(world_pos, samples[idx]["pos"])
			if d2 < best_d2:
				best_d2 = d2
				best_idx = idx
	if best_d2 > 60.0 * 60.0 or hint_t < 0.0:
		var cands := candidates_near(world_pos.x, world_pos.z, 48.0)
		if cands.is_empty():
			for idx in range(n):
				var d2 := _dist2_weighted(world_pos, samples[idx]["pos"])
				if d2 < best_d2:
					best_d2 = d2
					best_idx = idx
		else:
			for idx in cands:
				var d2 := _dist2_weighted(world_pos, samples[idx]["pos"])
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
		"height": rel.dot(s["up"]),
		"zone": s["zone"],
		"biome": s["biome"],
		"gap": s["gap"],
		"ground": s["ground"],
	}

## Surface id under a point that touches the TRACK collider (road / shoulder / halfpipe / patches).
func surface_at(world_pos: Vector3, hint_t: float = -1.0) -> String:
	var q := project_point(world_pos, hint_t)
	var s := samples[int(q["index"])]
	var lat: float = q["lateral"]
	var t: float = q["t"]
	for p in patches:
		if t >= float(p["t0"]) and t <= float(p["t1"]) and lat >= float(p["lat0"]) and lat <= float(p["lat1"]):
			return str(p["surf"])
	var hw: float = s["half_width"]
	if absf(lat) <= hw + 0.05:
		return str(s["surface"])
	var side := "l" if lat < 0.0 else "r"
	if str(s["edge_" + side]) == "halfpipe":
		return str(s["surface"])
	if float(s["sh_" + side]) > 0.1:
		return str(s["shs_" + side])
	return str(s["surface"])

func get_min_2d_track_clearance(pt_xz: Vector2, extra_corridors: Array = []) -> float:
	## Pure 2D (X, Z) clearance from any road + shoulder (uses the spatial grid).
	var min_clear := 1e9
	var cands := candidates_near(pt_xz.x, pt_xz.y, 64.0)
	for idx in cands:
		var s := samples[idx]
		var sp: Vector3 = s["pos"]
		var d_center := pt_xz.distance_to(Vector2(sp.x, sp.z))
		var road_extent: float = float(s["half_width"]) + maxf(float(s["off_l"]), float(s["off_r"]))
		min_clear = minf(min_clear, d_center - road_extent)
	if cands.is_empty():
		min_clear = 64.0
	for corr in extra_corridors:
		var cp: Vector2 = corr["xz"]
		min_clear = minf(min_clear, pt_xz.distance_to(cp) - float(corr["radius"]))
	return min_clear
