class_name TrackBuilder
extends RefCounted
## Builds a complete race world from an authored track JSON (see tools/track_*.py).
## Order matters: paths -> terrain features -> stamps -> terrain -> roads ->
## set pieces -> gameplay objects -> scatter -> environmental life.

signal progress(step: String, fraction: float)

var data: Dictionary
var main: SplinePath
var branches := {}          # id -> SplinePath
var branch_style := {}      # id -> base style
var marks := {}
var terrain: TerrainBuilder
var root: Node3D
var quality := 2            # 0 low, 1 medium, 2 high
var rng := RandomNumberGenerator.new()

# outputs consumed by gameplay / AI
var obstacles: Array = []           # [Vector3 centre, float radius, String kind]
var item_boxes: Array = []          # Vector3
var pads: Array = []                # {pos, basis, tier}
var spawn_grid: Array = []          # Transform3D
var river_rocks: Array = []
var chevrons: Array = []
var landmarks: Array = []           # {name, pos}
var dynamic_nodes: Array = []       # nodes needing per-frame updates
var timings := {}


func load_track(json_path: String) -> void:
	var f := FileAccess.open(json_path, FileAccess.READ)
	assert(f != null, "missing track data " + json_path)
	data = JSON.parse_string(f.get_as_text())
	marks = data["marks"]
	rng.seed = 7741


func build(parent: Node3D, q := 2) -> Node3D:
	quality = q
	var t0 := Time.get_ticks_msec()
	root = Node3D.new()
	root.name = "Track"
	parent.add_child(root)
	_make_paths()
	_t("paths", t0)
	terrain = TerrainBuilder.new()
	var b := _bounds()
	terrain.setup(b, 2.5 if quality >= 1 else 3.5, 2207)
	_features()
	terrain.stamp_path(main)
	for id in branches:
		terrain.stamp_path(branches[id])
	for extra in _extra_water_paths():
		terrain.stamp_path(extra)
	terrain.finalize()
	_punch_cave_holes()
	_t("terrain_field", t0)
	TrackGameplay.plan(self)   # obstacle placement first: water foam depends on it
	_build_roads()
	_t("roads", t0)
	var tb := terrain.build_meshes(root, Mats.terrain())
	_t("terrain_mesh", t0)
	SetPieces.build_all(self)
	_t("set_pieces", t0)
	TrackGameplay.build_all(self)
	_t("gameplay", t0)
	Scatter.build_all(self)
	_t("scatter", t0)
	EnvLife.build_all(self)
	_t("life", t0)
	return root


func _t(step: String, t0: int) -> void:
	timings[step] = Time.get_ticks_msec() - t0
	progress.emit(step, 0.0)


# ------------------------------------------------------------------ paths
func _make_paths() -> void:
	var mp: Dictionary = data["main"]
	main = SplinePath.from_points(mp["points"], true, 1.5)
	for b in data["branches"]:
		var sp := SplinePath.from_points(b["points"], false, 1.5)
		branches[b["id"]] = sp
		branch_style[b["id"]] = b["style"]


func _bounds() -> Rect2:
	var mn := Vector2(INF, INF)
	var mx := Vector2(-INF, -INF)
	for p in main.pos:
		mn = mn.min(Vector2(p.x, p.z))
		mx = mx.max(Vector2(p.x, p.z))
	var margin := 170.0
	return Rect2(mn - Vector2(margin, margin), (mx - mn) + Vector2(margin, margin) * 2.0)


func mark(name: String) -> Dictionary:
	return marks.get(name, {})


func mark_pos(name: String) -> Vector3:
	var m: Dictionary = marks[name]
	var p: Array = m["pos"]
	return Vector3(p[0], p[1], p[2])


func mark_index(name: String) -> int:
	return main.nearest_index(mark_pos(name), 30.0)


func heading_dir(name: String) -> Vector3:
	var h := deg_to_rad(float(marks[name]["heading"]))
	return Vector3(cos(h), 0, sin(h))


func ground_y(x: float, z: float) -> float:
	return terrain.height_at(x, z)


# ------------------------------------------------------------------ terrain features
func _features() -> void:
	# West hill: the aqueduct emerges from it; the start grid sits level with its crest.
	var rw := mark_pos("final_approach")
	terrain.add_feature("hill", rw.x - 30.0, rw.z - 20.0, 150.0, 12.0)
	terrain.add_feature("hill", -150.0 - 40.0, -22.0 + 40.0, 70.0, 6.0)
	# Hairpin knoll (the Rootway Cave runs through it)
	var hp := mark_pos("hairpin")
	var hdir := heading_dir("hairpin")
	var left := Vector3(hdir.z, 0, -hdir.x)
	var knoll := hp + left * 17.0 + hdir * 2.0
	terrain.add_feature("mesa", knoll.x, knoll.z, 15.0, 13.0)
	terrain.add_feature("hill", knoll.x, knoll.z, 30.0, 6.0)
	# Giant's Hollow: sinkhole the log spans
	var le := mark_pos("log_entry")
	var rm := mark_pos("ridge_merge")
	var hc := le.lerp(rm, 0.45)
	terrain.add_feature("basin", hc.x, hc.z, 30.0, 9.0)
	# Mill pond inside the mill sweeper
	var ma := mark_pos("mill_apex")
	var mdir := heading_dir("mill_apex")
	var mright := Vector3(-mdir.z, 0, mdir.x)
	var pond := ma + mright * 34.0
	terrain.add_feature("basin", pond.x, pond.z, 30.0, 4.5)
	# Falls plunge pool + infield lake
	var fl := mark_pos("falls_lip")
	var fland := mark_pos("falls_land")
	var pool := fl.lerp(fland, 0.55)
	terrain.add_feature("basin", pool.x, pool.z, 15.0, 3.0)
	# Elder Tree rise in the infield
	var cr := mark_pos("crest_1")
	terrain.add_feature("hill", cr.x - 70.0, cr.z - 10.0, 45.0, 7.0)
	# Rock ridge carrying the Giant's Log landing
	landmarks.append({"name": "hollow", "pos": hc})
	landmarks.append({"name": "pond", "pos": pond})
	landmarks.append({"name": "pool", "pos": pool})
	landmarks.append({"name": "knoll", "pos": knoll})


func _extra_water_paths() -> Array:
	## Decorative river course from the aqueduct portal down to where karts land.
	var out: Array = []
	var lip_i := mark_index("lip")
	var land_i := mark_index("river_land")
	var pts: Array = []
	var n := main.size()
	var y_land := main.pos[land_i].y
	var first := (lip_i - 4 + n) % n
	var count := (land_i + 2 - first + n) % n
	var steps := 0
	for s in range(0, count + 1, 3):
		var p := main.pos[(first + s) % n]
		pts.append([p.x, y_land + 0.25, p.z, 15.0, 0.0, {"s": Surfaces.CURRENT, "style": "river", "tm": "river"} if steps == 0 else {}])
		steps += 1
	if pts.size() >= 2:
		var sp := SplinePath.from_points(pts, false, 1.5)
		branches["river_upstream"] = sp
		branch_style["river_upstream"] = "river"
		out.append(sp)
	return out


func _punch_cave_holes() -> void:
	var cave: SplinePath = branches.get("rootway_cave")
	if cave == null:
		return
	var last := 0
	for i in cave.size():
		if cave.style[i] == "cave":
			last = i
	terrain.punch_holes_along(cave, 0, 10, 6.5, 7.0)
	terrain.punch_holes_along(cave, maxi(last - 10, 0), last + 1, 6.5, 7.0)


# ------------------------------------------------------------------ roads
func _build_roads() -> void:
	var roads := Node3D.new()
	roads.name = "Roads"
	root.add_child(roads)
	RoadMesher.build(main, roads, "Main", 6.5, main.style)
	for id in branches:
		var sp: SplinePath = branches[id]
		var flow := 6.0
		if id == "millrace_flume":
			flow = 9.0
		RoadMesher.build(sp, roads, id, flow, sp.style)
	# flowing water over every river/flume run
	_water_for(main, roads, 0.42, 1.5)
	for id in branches:
		_water_for(branches[id], roads, 0.42 if id != "millrace_flume" else 0.55, 1.2 if id != "millrace_flume" else -0.05)


func _water_for(sp: SplinePath, parent: Node3D, depth: float, extra: float) -> void:
	var n := sp.size()
	var i := 0
	while i < n:
		if sp.style[i] == "river" or sp.style[i] == "flume":
			var j := i
			while j + 1 < n and sp.style[j + 1] == sp.style[i]:
				j += 1
			var kind := "flume" if sp.style[i] == "flume" else "river"
			var foam: Array = []
			for r in river_rocks:
				foam.append([r[0], r[1]])
			RoadMesher.water_surface(sp, parent, i, mini(j + 1, n - 1), extra, depth, foam, 1.0 if kind == "river" else 1.6, kind)
			i = j + 1
		else:
			i += 1


# ------------------------------------------------------------------ helpers for modules
func add_static_mesh(parent: Node3D, mb: MeshBuilder, mat: Material, name := "Mesh", shadows := true) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = name
	mi.mesh = mb.commit(null, mat)
	if not shadows:
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi


func add_box_collider(parent: Node3D, xf: Transform3D, size: Vector3, surface := Surfaces.ROCK) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	body.set_meta("surface", surface)
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = size
	cs.shape = bs
	body.add_child(cs)
	body.transform = xf
	parent.add_child(body)
	return body


func add_cylinder_collider(parent: Node3D, pos: Vector3, radius: float, height: float, surface := Surfaces.ROCK) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	body.set_meta("surface", surface)
	var cs := CollisionShape3D.new()
	var shp := CylinderShape3D.new()
	shp.radius = radius
	shp.height = height
	cs.shape = shp
	body.add_child(cs)
	body.position = pos + Vector3.UP * height * 0.5
	parent.add_child(body)
	return body


func add_trimesh_collider(parent: Node3D, mb: MeshBuilder, surface := Surfaces.ROCK, xf := Transform3D.IDENTITY) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	body.set_meta("surface", surface)
	var shape := ConcavePolygonShape3D.new()
	shape.set_faces(mb.to_collision_faces())
	shape.backface_collision = true
	var cs := CollisionShape3D.new()
	cs.shape = shape
	body.add_child(cs)
	body.transform = xf
	parent.add_child(body)
	return body


func near_any_road(p: Vector3, margin: float) -> bool:
	return terrain.dist_at(p.x, p.z) < margin
