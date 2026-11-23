class_name DriveTests
extends RefCounted
## Drivability & collision-honesty tests (the problems players notice first):
##  1. step scan   - no lip/step taller than Kart.MAX_STEP across any road
##                   cross-section and its shoulders (road <-> road, road <-> ground)
##  2. edges       - karts drive off-road -> onto the road and road -> off-road at an
##                   angle everywhere along every route; the road surface or the
##                   ground may never stop them like a wall
##  3. junctions   - driving across every branch entry/exit into the main road
##  4. colliders   - every solid prop/structure a kart can reach is solid where it
##                   is visible (no driving through rocks, trunks, logs, ruins ...)

var R: Object
var T: SceneTree
var tb: TrackBuilder
var root: Node3D
var out := {}
var _k: Kart
var _space: PhysicsDirectSpaceState3D


func run(runner: Object) -> void:
	R = runner
	T = (runner as Node).get_tree()
	root = Node3D.new()
	T.root.add_child(root)
	tb = TrackBuilder.new()
	tb.load_track("res://data/timberfall.json")
	tb.build(root, 1)
	await R.frames(3)
	_space = root.get_world_3d().direct_space_state
	_k = Kart.new()
	_k.params = KartParams.new()
	_k.params.accel = 40.0
	root.add_child(_k)
	await R.frames(2)
	_step_scan()
	await _edges()
	await _junctions()
	_collider_audit()
	var f := FileAccess.open("res://tests/results/drive.json", FileAccess.WRITE)
	f.store_string(JSON.stringify(out, "  "))
	root.queue_free()
	await R.frames(2)


func _paths() -> Dictionary:
	var d := {"main": tb.main}
	for id in tb.branches:
		d[id] = tb.branches[id]
	return d


func _ray_down(p: Vector3, top: float, bottom: float) -> Dictionary:
	var q := PhysicsRayQueryParameters3D.create(Vector3(p.x, top, p.z), Vector3(p.x, bottom, p.z), 1)
	q.exclude = [_k.get_rid()]
	return _space.intersect_ray(q)


const ELEVATED := ["Col_kicker", "Col_flume", "Col_log_ramp", "Col_slab", "Col_ridge", "Col_boardwalk", "Col_roof", "Col_deck", "Col_cave"]


static func _seam_body(n: String) -> bool:
	# a blocking contact with one of these is a geometry defect, not an obstacle
	return n == "TerrainBody" or n.begins_with("Col_")


static func _ground_level_body(n: String) -> bool:
	## terrain or a ground-level road (raised structures' sides are real obstacles)
	if n == "TerrainBody":
		return true
	if not n.begins_with("Col_"):
		return false
	for e: String in ELEVATED:
		if n.begins_with(e):
			return false
	return true


# ------------------------------------------------------------------ 1. step scan
func _step_scan() -> void:
	var blocking: Array = []
	var small := 0
	var scanned := 0
	var paths := _paths()
	for id in paths:
		var sp: SplinePath = paths[id]
		var step := maxi(int(4.0 / sp.spacing), 1)
		for i in range(0, sp.size(), step):
			if sp.style[i] == "gap" or sp.terrain_mode[i] == "none" or sp.style[i] in ["river", "flume"]:
				continue
			var hw := sp.width[i] * 0.5
			var prev := {}
			var lat := -(hw + 3.0)
			while lat <= hw + 3.0:
				var p := sp.pos[i] + sp.right[i] * lat
				var hit := _ray_down(p, sp.pos[i].y + 2.5, sp.pos[i].y - 4.0)
				if not hit.is_empty() and prev.size() > 0:
					var n1 := String((prev.collider as Node).name)
					var n2 := String((hit.collider as Node).name)
					var both_walk: bool = (prev.normal as Vector3).y > 0.7 and (hit.normal as Vector3).y > 0.7
					if both_walk and _ground_level_body(n1) and _ground_level_body(n2):
						var dh := absf((hit.position as Vector3).y - (prev.position as Vector3).y)
						scanned += 1
						if dh > Kart.MAX_STEP:
							blocking.append([id, i, snappedf(lat, 0.1), snappedf(dh, 0.01), n1, n2])
						elif dh > 0.08:
							small += 1
				prev = hit
				lat += 0.2
	out["step_scan"] = {"pairs": scanned, "blocking": blocking.size(), "climbable_lips": small, "examples": blocking.slice(0, 12)}
	R.check("drive", "no road/ground step taller than %.2f m on or beside any road" % Kart.MAX_STEP, blocking.is_empty(), out["step_scan"])


# ------------------------------------------------------------------ 2. edges
func _drive(start: Vector3, dir: Vector3, speed: float, frames: int, sp: SplinePath, i_ref: int) -> Dictionary:
	_k.params.max_speed = speed
	var yaw := atan2(-dir.x, -dir.z)
	_k.teleport(Transform3D(Basis(Vector3.UP, yaw), start + Vector3.UP * 0.05))
	await T.physics_frame
	_k.velocity = dir * speed
	var res := {"seam": "", "reached": false, "min_speed": speed}
	for f in frames:
		_k.in_throttle = 1.0
		_k.in_steer = 0.0
		_k.in_drift = false
		await T.physics_frame
		for c in _k.get_slide_collision_count():
			var col := _k.get_slide_collision(c)
			var nrm := col.get_normal()
			if nrm.y < 0.55 and col.get_position().y - _k.global_position.y > Kart.CAP_CENTRE - Kart.CAP_RADIUS + 0.15:
				var nm := String((col.get_collider() as Node).name)
				if _seam_body(nm) and res.seam == "":
					res.seam = "%s at %s n=%s" % [nm, col.get_position().snapped(Vector3.ONE * 0.1), nrm.snapped(Vector3.ONE * 0.01)]
		var j := sp.nearest_index(_k.global_position, 30.0)
		if j >= 0 and absf(sp.lateral_offset(j, _k.global_position)) < sp.width[j] * 0.5 - 1.0:
			res.reached = true
		if f > 10:
			res.min_speed = minf(res.min_speed, _k.speed)
	return res


func _edges() -> void:
	var trials := 0
	var fails: Array = []
	var paths := _paths()
	for id in paths:
		var sp: SplinePath = paths[id]
		var step := maxi(int(28.0 / sp.spacing), 1)
		for i in range(step / 2, sp.size(), step):
			if sp.style[i] in ["gap", "river", "flume", "cave", "kicker", "log_ramp", "slab", "ridge", "deck", "boardwalk"] or sp.terrain_mode[i] == "none":
				continue
			if _near_style(sp, i, "gap", 14.0):
				continue
			var hw := sp.width[i] * 0.5
			var t := Vector3(sp.tan[i].x, 0.0, sp.tan[i].z).normalized()
			var r := Vector3(sp.right[i].x, 0.0, sp.right[i].z).normalized()
			for side: float in [-1.0, 1.0]:
				if (sp.wall_l[i] if side < 0.0 else sp.wall_r[i]) != "none":
					continue
				# off-road -> onto the road at 40 degrees
				var s0 := sp.pos[i] + r * side * (hw + 5.0)
				var g := _ray_down(s0, sp.pos[i].y + 3.0, sp.pos[i].y - 3.0)
				if g.is_empty() or String((g.collider as Node).name) != "TerrainBody" or (g.normal as Vector3).y < 0.8:
					continue
				if absf((g.position as Vector3).y - sp.pos[i].y) > 1.2:
					continue
				var into := (t * cos(deg_to_rad(40.0)) - r * side * sin(deg_to_rad(40.0))).normalized()
				var a: Dictionary = await _drive(g.position, into, 16.0, 75, sp, i)
				trials += 1
				if a.seam != "":
					fails.append(["onto", id, i, side, a.seam])
				# on the road -> off at 40 degrees
				var s1 := sp.pos[i] + r * side * (hw - 2.0)
				var g1 := _ray_down(s1, sp.pos[i].y + 2.0, sp.pos[i].y - 2.0)
				if g1.is_empty():
					continue
				var outward := (t * cos(deg_to_rad(40.0)) + r * side * sin(deg_to_rad(40.0))).normalized()
				var b: Dictionary = await _drive(g1.position, outward, 16.0, 60, sp, i)
				trials += 1
				if b.seam != "":
					fails.append(["off", id, i, side, b.seam])
	out["edges"] = {"trials": trials, "blocked_by_road_or_ground": fails.size(), "examples": fails.slice(0, 15)}
	R.check("drive", "driving onto/off every road edge is never blocked by the road or the ground", trials > 40 and fails.is_empty(), out["edges"])


func _near_style(sp: SplinePath, i: int, st: String, metres: float) -> bool:
	var w := int(metres / sp.spacing)
	for k in range(i - w, i + w + 1):
		var kk := posmod(k, sp.size()) if sp.closed else clampi(k, 0, sp.size() - 1)
		if sp.style[kk] == st:
			return true
	return false


# ------------------------------------------------------------------ 3. junctions
func _follow(sp: SplinePath, from_i: int, to_i: int, speed: float) -> String:
	## Scripted pure-pursuit along sp from from_i to to_i; returns the first seam hit.
	_k.params.max_speed = speed
	var t := sp.tan[from_i]
	var yaw := atan2(-t.x, -t.z)
	_k.teleport(Transform3D(Basis(Vector3.UP, yaw), sp.pos[from_i] + Vector3.UP * 0.2))
	await T.physics_frame
	_k.velocity = Vector3(-sin(yaw), 0.0, -cos(yaw)) * speed
	var seam := ""
	var last := from_i
	for f in 420:
		var i := sp.nearest_index(_k.global_position, 25.0)
		if i < 0:
			i = last
		last = i
		if i >= to_i - 1:
			break
		var tgt := sp.pos[mini(i + 5, sp.size() - 1)]
		var to := tgt - _k.global_position
		to.y = 0.0
		var ang := _k.heading().signed_angle_to(to.normalized(), Vector3.UP) if to.length() > 0.5 else 0.0
		_k.in_steer = clampf(-ang * 2.2, -1.0, 1.0)
		_k.in_throttle = 1.0
		_k.in_drift = false
		await T.physics_frame
		for c in _k.get_slide_collision_count():
			var col := _k.get_slide_collision(c)
			var nrm := col.get_normal()
			if nrm.y < 0.55 and col.get_position().y - _k.global_position.y > Kart.CAP_CENTRE - Kart.CAP_RADIUS + 0.15:
				var nm := String((col.get_collider() as Node).name)
				if _seam_body(nm) and seam == "":
					seam = "%s at %s" % [nm, col.get_position().snapped(Vector3.ONE * 0.1)]
	return seam


func _is_lead_in(sp: SplinePath, i: int) -> bool:
	## gap samples from the branch start up to the first real sample = the lead-in
	for k in range(0, i + 1):
		if sp.style[k] != "gap":
			return false
	return true


func _junctions() -> void:
	var fails: Array = []
	var n := 0
	for id in tb.branches:
		var sp: SplinePath = tb.branches[id]
		if id == "river_upstream":
			continue
		# entry: from the start of the branch (incl. its lead-in) 40 m in, stopping
		# before the first jump gap (jumps have their own suite)
		var e1 := mini(int(40.0 / sp.spacing), sp.size() - 1)
		for gi in range(int(6.0 / sp.spacing), e1):
			if sp.style[gi] == "gap" and sp.tags[gi] != "lead_in" and not _is_lead_in(sp, gi):
				e1 = maxi(gi - int(10.0 / sp.spacing), 2)
				break
		var s1 := await _follow(sp, 0, e1, 22.0)
		n += 1
		if s1 != "":
			fails.append(["entry", id, s1])
		# exit: the last 30 m of the branch
		var e0 := maxi(sp.size() - 1 - int(30.0 / sp.spacing), 0)
		if _near_style(sp, e0, "gap", 6.0):
			continue
		var s2 := await _follow(sp, e0, sp.size() - 1, 22.0)
		n += 1
		if s2 != "":
			fails.append(["exit", id, s2])
	out["junctions"] = {"runs": n, "blocked": fails}
	R.check("drive", "every branch entry/exit is driven without hitting a road/ground seam", fails.is_empty(), out["junctions"])


# ------------------------------------------------------------------ 4. colliders
func _solid_here(p: Vector3, r: float) -> bool:
	var q := PhysicsShapeQueryParameters3D.new()
	var sh := SphereShape3D.new()
	sh.radius = r
	q.shape = sh
	q.transform = Transform3D(Basis(), p)
	q.collision_mask = 1
	q.exclude = [_k.get_rid()]
	for h in _space.intersect_shape(q, 8):
		var nm := String((h.collider as Node).name)
		if nm != "TerrainBody" and not nm.begins_with("Col_"):
			return true
	return false


func _collider_audit() -> void:
	# set pieces flagged solid: every visible vertex at kart-body height must be solid
	var missing := {}
	var checked := 0
	for mi in tb.solid_meshes:
		var mesh := mi.mesh
		for si in mesh.get_surface_count():
			var verts: PackedVector3Array = mesh.surface_get_arrays(si)[Mesh.ARRAY_VERTEX]
			var stride := maxi(verts.size() / 160, 1)
			for vi in range(0, verts.size(), stride):
				var p := mi.global_transform * verts[vi]
				if tb.terrain.dist_at(p.x, p.z) > 46.0:
					continue
				var gy := tb.terrain.height_at(p.x, p.z)
				if p.y - gy < 0.25 or p.y - gy > 1.8:
					continue
				var near_corridor := tb.in_road_corridor(p)
				for o: Vector3 in [Vector3(0.6, 0, 0), Vector3(-0.6, 0, 0), Vector3(0, 0, 0.6), Vector3(0, 0, -0.6)]:
					near_corridor = near_corridor or tb.in_road_corridor(p + o)
				if near_corridor:
					continue   # in (or at the edge of) a road corridor: deliberately not solid
				checked += 1
				if not _solid_here(p, 0.3):
					missing[mi.name] = int(missing.get(mi.name, 0)) + 1
	# scattered solid props (trees, rocks, stumps, fallen logs) in reach
	var props_checked := 0
	var props_missing: Array = []
	for pr in tb.solid_props:
		var p: Vector3 = pr[1]
		if tb.terrain.dist_at(p.x, p.z) > 46.0:
			continue
		props_checked += 1
		if not _solid_here(p, 0.25):
			props_missing.append([pr[0], p.snapped(Vector3.ONE * 0.1)])
	out["colliders"] = {"set_piece_points": checked, "set_piece_missing": missing, "props_checked": props_checked, "props_missing": props_missing.size(), "examples": props_missing.slice(0, 10)}
	R.check("drive", "every reachable solid structure and prop has a collider where it is visible", checked > 100 and props_checked > 200 and missing.is_empty() and props_missing.is_empty(), out["colliders"])
