class_name TrackBuilder
extends Node3D

## v8 CTR:NF-style track builder. Reads res://data/tracks/<id>.json produced by tools/trackgen and builds:
##  - chunked multi-surface road (crowned, banked) + flush shoulders, ONE seamless "track" collider whose
##    surface is resolved per contact point (road / shoulder / patch) -> zero floor seams that can block a kart
##  - edges: wall (heavy) / fence (medium) / rail (medium) / cliff (heavy) / halfpipe (drivable) / open (drop)
##  - indoor halls (ceiling, lights, darker ambience), elevated decks with supports, real gaps for jumps
##  - terrain heightmap with collision, water, scatter, landmarks (TrackWorld.gd)
##  - turbo pads, boost rings, static obstacles (tiered collision), jump-only shortcuts (kicker / platforms)

const TRACK_LAYER := 1
const WALL_LAYER := 2
const OFFROAD_LAYER := 4
const CHUNK := 100

var spline: TrackSpline = TrackSpline.new()
var track_def: Dictionary = {}
var data: Dictionary = {}
var mx: float = 1.0
var shortcut_geometries: Array[Dictionary] = []
var turbo_pad_positions: Array[Dictionary] = []
var crate_spawn_points: Array[Vector3] = []
var fruit_spawn_points: Array[Vector3] = []
var spawned_prop_bounds: Array[Dictionary] = []
var obstacle_list: Array[Dictionary] = []
var hazard_defs: Array = []
var world: TrackWorld = null
var focus_kart: Node3D = null
var build_timings: Dictionary = {}

var _env: Environment = null
var _sun: DirectionalLight3D = null
var _sun_energy: float = 1.1
var _amb_energy: float = 0.5
var _indoor_mix: float = 0.0

static var _glb_cache: Dictionary = {}
static var _glb_mesh_cache: Dictionary = {}
static var _shader_cache: Dictionary = {}

# ------------------------------------------------------------------------------------------------ utils
static func _inst_glb(path: String) -> Node3D:
	if not _glb_cache.has(path):
		var res = load(path) if ResourceLoader.exists(path) else null
		if res is PackedScene:
			_glb_cache[path] = res
		else:
			return null
	return (_glb_cache[path] as PackedScene).instantiate() as Node3D

static func _find_first_mesh(node: Node) -> Mesh:
	if node is MeshInstance3D and (node as MeshInstance3D).mesh != null:
		return (node as MeshInstance3D).mesh
	for c in node.get_children():
		var m := _find_first_mesh(c)
		if m != null:
			return m
	return null

static func _extract_glb_mesh(path: String) -> Mesh:
	if _glb_mesh_cache.has(path):
		return _glb_mesh_cache[path]
	var inst := _inst_glb(path)
	var m: Mesh = null
	if inst:
		m = _find_first_mesh(inst)
		inst.free()
	_glb_mesh_cache[path] = m
	return m

static func _load_shader(path: String) -> Shader:
	if not _shader_cache.has(path):
		_shader_cache[path] = load(path)
	return _shader_cache[path]

static func load_track_data(track_id: String) -> Dictionary:
	var path := "res://data/tracks/%s.json" % track_id
	if not FileAccess.file_exists(path):
		push_error("Track data missing: " + path)
		return {}
	var txt := FileAccess.get_file_as_string(path)
	var parsed = JSON.parse_string(txt)
	return parsed if parsed is Dictionary else {}

## Mesh batcher: one SurfaceTool per (material key, chunk) -> chunked MeshInstance3D (frustum culling).
class Batch:
	var sts: Dictionary = {}
	var mats: Dictionary = {}
	var shadows: Dictionary = {}
	func get_st(key: String, mat: Material, cast_shadow: bool = true) -> SurfaceTool:
		if not sts.has(key):
			var st := SurfaceTool.new()
			st.begin(Mesh.PRIMITIVE_TRIANGLES)
			sts[key] = st
			mats[key] = mat
			shadows[key] = cast_shadow
		return sts[key]
	func commit(parent: Node3D) -> int:
		var count := 0
		for key in sts.keys():
			var st: SurfaceTool = sts[key]
			st.generate_tangents()
			var mesh := st.commit()
			if mesh.get_surface_count() == 0:
				continue
			var mi := MeshInstance3D.new()
			mi.mesh = mesh
			mi.material_override = mats[key]
			if not bool(shadows[key]):
				mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			parent.add_child(mi)
			count += 1
		return count

## Adds a triangle whose front face points along n_hint (Godot: clockwise = front).
static func tri(st: SurfaceTool, p0: Vector3, p1: Vector3, p2: Vector3, n0: Vector3, n1: Vector3, n2: Vector3, uv0: Vector2, uv1: Vector2, uv2: Vector2) -> void:
	var fn := (p2 - p0).cross(p1 - p0)
	if fn.dot(n0 + n1 + n2) < 0.0:
		var tp := p1; p1 = p2; p2 = tp
		var tn := n1; n1 = n2; n2 = tn
		var tu := uv1; uv1 = uv2; uv2 = tu
	st.set_normal(n0); st.set_uv(uv0); st.add_vertex(p0)
	st.set_normal(n1); st.set_uv(uv1); st.add_vertex(p1)
	st.set_normal(n2); st.set_uv(uv2); st.add_vertex(p2)

## Quad a0-a1 (at sample i) / b0-b1 (at sample i+1) with per-vertex normals and UVs.
static func quad(st: SurfaceTool, a0: Vector3, a1: Vector3, b0: Vector3, b1: Vector3, na0: Vector3, na1: Vector3, nb0: Vector3, nb1: Vector3, ua0: Vector2, ua1: Vector2, ub0: Vector2, ub1: Vector2) -> void:
	tri(st, a0, b0, b1, na0, nb0, nb1, ua0, ub0, ub1)
	tri(st, a0, b1, a1, na0, nb1, na1, ua0, ub1, ua1)

static func quad_flat(st: SurfaceTool, a0: Vector3, a1: Vector3, b0: Vector3, b1: Vector3, n: Vector3, u0: float, u1: float, v0: float, v1: float) -> void:
	quad(st, a0, a1, b0, b1, n, n, n, n, Vector2(u0, v0), Vector2(u1, v0), Vector2(u0, v1), Vector2(u1, v1))

static func col_quad(faces: PackedVector3Array, a0: Vector3, a1: Vector3, b0: Vector3, b1: Vector3, n: Vector3) -> void:
	for t in [[a0, b0, b1], [a0, b1, a1]]:
		var p0: Vector3 = t[0]
		var p1: Vector3 = t[1]
		var p2: Vector3 = t[2]
		if (p2 - p0).cross(p1 - p0).dot(n) < 0.0:
			var tp := p1; p1 = p2; p2 = tp
		faces.append(p0); faces.append(p1); faces.append(p2)

func _static_body(faces: PackedVector3Array, layer: int, surface: String, strength: String = "") -> StaticBody3D:
	var sb := StaticBody3D.new()
	sb.collision_layer = layer
	sb.collision_mask = 0
	sb.set_meta("surface_type", surface)
	if strength != "":
		sb.set_meta("collision_strength", strength)
	var cs := CollisionShape3D.new()
	var shape := ConcavePolygonShape3D.new()
	shape.set_faces(faces)
	cs.shape = shape
	sb.add_child(cs)
	add_child(sb)
	return sb

func _add_cyl_collider(parent: Node3D, radius: float, height: float, local_pos: Vector3 = Vector3.ZERO, record_world: bool = true, strength: String = "heavy") -> void:
	var sb := StaticBody3D.new()
	sb.collision_layer = WALL_LAYER
	sb.collision_mask = 0
	sb.set_meta("surface_type", "prop_obstacle")
	sb.set_meta("collision_strength", strength)
	var cs := CollisionShape3D.new()
	var cyl := CylinderShape3D.new()
	cyl.radius = radius
	cyl.height = height
	cs.shape = cyl
	cs.position = local_pos + Vector3(0.0, height * 0.5, 0.0)
	sb.add_child(cs)
	parent.add_child(sb)
	if record_world:
		spawned_prop_bounds.append({"pos": parent.position + local_pos, "radius": radius})

# ------------------------------------------------------------------------------------------------ build
func build_track(track_id: String, mirrored: bool = false) -> Dictionary:
	for c in get_children():
		c.queue_free()
	shortcut_geometries.clear()
	turbo_pad_positions.clear()
	crate_spawn_points.clear()
	fruit_spawn_points.clear()
	spawned_prop_bounds.clear()
	obstacle_list.clear()
	hazard_defs.clear()

	data = load_track_data(track_id)
	mx = -1.0 if mirrored else 1.0
	spline = TrackSpline.new()
	spline.load_from_data(data, mirrored)
	var env_d: Dictionary = data.get("env", {})
	track_def = {
		"id": track_id,
		"theme": str(env_d.get("theme", "tiki")),
		"mirrored": mirrored,
		"name_en": data.get("name_en", ""),
		"name_ar": data.get("name_ar", ""),
		"env": env_d,
	}

	world = TrackWorld.new()
	world.name = "World"
	add_child(world)
	world.setup(self, data, mirrored)

	var steps: Array = [
		["env", func(): _build_environment(env_d)],
		["terrain", func(): world.build_terrain_and_water()],
		["road", func(): _build_road()],
		["edges", func(): _build_edges()],
		["indoor", func(): _build_indoor()],
		["supports", func(): _build_supports()],
		["gantry", func(): _build_start_gantry()],
		["pads", func(): _build_turbo_pads()],
		["rings", func(): _build_boost_rings()],
		["obstacles", func(): _build_obstacles()],
		["shortcuts", func(): _build_shortcuts()],
		["landmarks", func(): world.build_landmarks()],
		["scatter", func(): world.build_scatter()],
		["horizon", func(): world.build_horizon()],
		["pickups", func(): _compute_pickups()],
		["hazards", func(): _convert_hazards()],
	]
	build_timings.clear()
	for stp in steps:
		var t0 := Time.get_ticks_usec()
		(stp[1] as Callable).call()
		build_timings[stp[0]] = float(Time.get_ticks_usec() - t0) / 1000.0
		if OS.get_environment("NFR_TRACE") == "1":
			printt("[build]", stp[0], build_timings[stp[0]])
	if OS.has_feature("editor") or OS.is_debug_build():
		print("[TrackBuilder] build ms: ", build_timings)

	return {
		"spline": spline,
		"def": track_def,
		"shortcuts": shortcut_geometries,
		"turbo_pads": turbo_pad_positions,
		"hazards": hazard_defs,
		"crate_points": crate_spawn_points,
		"fruit_points": fruit_spawn_points,
		"prop_bounds": spawned_prop_bounds,
		"obstacles": obstacle_list,
	}

# ------------------------------------------------------------------------------------------------ environment
func _build_environment(env_d: Dictionary) -> void:
	var env := Environment.new()
	var sky := Sky.new()
	var sky_mat := ProceduralSkyMaterial.new()
	var sky_top: Color = Color.html(str(env_d.get("sky_top", "#3d55a8")))
	var sky_hor: Color = Color.html(str(env_d.get("sky_horizon", "#f2c48a")))
	var ground_c: Color = Color.html(str(env_d.get("ground", "#2f5a3a")))
	sky_mat.sky_top_color = sky_top
	sky_mat.sky_horizon_color = sky_hor
	sky_mat.ground_bottom_color = ground_c.darkened(0.35)
	sky_mat.ground_horizon_color = sky_hor.lerp(ground_c, 0.35)
	sky_mat.sun_angle_max = 26.0
	sky_mat.sun_curve = 0.14
	sky.sky_material = sky_mat
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	_amb_energy = float(env_d.get("ambient", 0.5))
	env.ambient_light_energy = _amb_energy
	env.fog_enabled = true
	env.fog_light_color = Color.html(str(env_d.get("fog", "#e8c8a0")))
	env.fog_light_energy = 1.0
	env.fog_density = float(env_d.get("fog_density", 0.0012))
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = float(env_d.get("exposure", 1.0))
	env.glow_enabled = false
	_env = env
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

	_sun = DirectionalLight3D.new()
	_sun.light_color = Color.html(str(env_d.get("sun", "#ffe2b0")))
	_sun_energy = float(env_d.get("sun_energy", 1.15))
	_sun.light_energy = _sun_energy
	_sun.shadow_enabled = GameState.graphics_high if GameState else true
	_sun.directional_shadow_max_distance = 140.0
	_sun.rotation_degrees = Vector3(float(env_d.get("sun_pitch", -38.0)), float(env_d.get("sun_yaw", 30.0)) * mx, 0.0)
	add_child(_sun)
	var rim := DirectionalLight3D.new()
	rim.light_color = sky_hor
	rim.light_energy = 0.32
	rim.shadow_enabled = false
	rim.rotation_degrees = Vector3(-16.0, -148.0 * mx, 0.0)
	add_child(rim)

func set_focus(k: Node3D) -> void:
	focus_kart = k

func _process(delta: float) -> void:
	## Indoor ambience: darken sun/ambient while the focused kart is inside a hall / cave / pipe.
	if focus_kart == null or not is_instance_valid(focus_kart) or _env == null:
		return
	var t: float = float(focus_kart.get("spline_t")) if focus_kart.get("spline_t") != null else 0.0
	var idx := spline.index_at_t(t)
	var target := 1.0 if float(spline.samples[idx]["ceil"]) > 0.0 else 0.0
	_indoor_mix = move_toward(_indoor_mix, target, delta * 2.2)
	_sun.light_energy = lerpf(_sun_energy, _sun_energy * 0.22, _indoor_mix)
	_env.ambient_light_energy = lerpf(_amb_energy, _amb_energy * 0.75, _indoor_mix)

# ------------------------------------------------------------------------------------------------ road
func _lat_stations(hw: float) -> Array[float]:
	return [-hw, -hw * 0.5, 0.0, hw * 0.5, hw]

func _crown_y(crown: float, lat: float, hw: float) -> float:
	var u := lat / maxf(1.0, hw)
	return crown * maxf(0.0, 1.0 - u * u)

func _road_point(s: Dictionary, lat: float) -> Vector3:
	var hw: float = s["half_width"]
	return s["pos"] + s["right"] * lat + s["up"] * _crown_y(float(s["crown"]), lat, hw)

func _road_normal(s: Dictionary, lat: float) -> Vector3:
	var hw: float = maxf(1.0, float(s["half_width"]))
	var slope := -2.0 * float(s["crown"]) * lat / (hw * hw)
	return (s["up"] - s["right"] * slope).normalized()

func _seg_skipped(i: int) -> bool:
	var n := spline.samples.size()
	return bool(spline.samples[i]["gap"]) or bool(spline.samples[(i + 1) % n]["gap"])

func _build_road() -> void:
	var S := spline.samples
	var n := S.size()
	var batch := Batch.new()
	var faces := PackedVector3Array()
	var line_mat := TrackMats.flat(Color(0.95, 0.92, 0.82), 0.6)
	for i in range(n):
		if _seg_skipped(i):
			continue
		var a: Dictionary = S[i]
		var b: Dictionary = S[(i + 1) % n]
		var chunk := i / CHUNK
		var surf: String = a["surface"]
		var indoor := float(a["ceil"]) > 0.0
		var rep := TrackMats.surface_repeat(surf)
		var st := batch.get_st("road|%s|%s|%d" % [surf, str(indoor), chunk], TrackMats.surface_mat(surf, indoor))
		var va := float(a["dist"]) / rep
		var vb := (float(a["dist"]) + spline.step) / rep
		var ha: float = a["half_width"]
		var hb: float = b["half_width"]
		var la := _lat_stations(ha)
		var lb := _lat_stations(hb)
		for k in range(4):
			var pa0 := _road_point(a, la[k]); var pa1 := _road_point(a, la[k + 1])
			var pb0 := _road_point(b, lb[k]); var pb1 := _road_point(b, lb[k + 1])
			quad(st, pa0, pa1, pb0, pb1, _road_normal(a, la[k]), _road_normal(a, la[k + 1]), _road_normal(b, lb[k]), _road_normal(b, lb[k + 1]),
				Vector2(la[k] / rep, va), Vector2(la[k + 1] / rep, va), Vector2(lb[k] / rep, vb), Vector2(lb[k + 1] / rep, vb))
			col_quad(faces, pa0, pa1, pb0, pb1, a["up"])
		# painted edge lines on sealed surfaces (readability of the racing surface)
		if surf in ["asphalt", "neon", "metal", "stone", "packed_snow"] and not indoor:
			var lst := batch.get_st("lines|%d" % chunk, line_mat, false)
			for side in [-1.0, 1.0]:
				var la0: float = side * (ha - 0.9); var la1: float = side * (ha - 0.55)
				var lb0: float = side * (hb - 0.9); var lb1: float = side * (hb - 0.55)
				var off_a: Vector3 = a["up"] * 0.025
				var off_b: Vector3 = b["up"] * 0.025
				quad_flat(lst, _road_point(a, la0) + off_a, _road_point(a, la1) + off_a, _road_point(b, lb0) + off_b, _road_point(b, lb1) + off_b, a["up"], 0, 1, 0, 1)
		# shoulders (flush, drivable, off-road surface) + skirts
		for side_i in range(2):
			var side := -1.0 if side_i == 0 else 1.0
			var sk := "l" if side < 0.0 else "r"
			var edge: String = a["edge_" + sk]
			var sha: float = float(a["sh_" + sk])
			var shb: float = float(b["sh_" + sk])
			var ea := _road_point(a, side * ha)
			var eb := _road_point(b, side * hb)
			var oa := ea
			var ob := eb
			if sha > 0.1 and shb > 0.1 and edge != "halfpipe":
				var shs: String = a["shs_" + sk]
				var srep := TrackMats.surface_repeat(shs)
				var sst := batch.get_st("sh|%s|%d" % [shs, chunk], TrackMats.surface_mat(shs, indoor))
				oa = ea + a["right"] * (side * sha) - a["up"] * 0.12
				ob = eb + b["right"] * (side * shb) - b["up"] * 0.12
				var na: Vector3 = a["up"]
				var nb: Vector3 = b["up"]
				var ua0 := float(side * ha) / srep
				var ua1 := float(side * (ha + sha)) / srep
				var ub0 := float(side * hb) / srep
				var ub1 := float(side * (hb + shb)) / srep
				quad(sst, ea, oa, eb, ob, na, na, nb, nb, Vector2(ua0, float(a["dist"]) / srep), Vector2(ua1, float(a["dist"]) / srep), Vector2(ub0, float(b["dist"]) / srep), Vector2(ub1, float(b["dist"]) / srep))
				col_quad(faces, ea, oa, eb, ob, a["up"])
				# gentle apron sloping down into the terrain so karts can roll on/off the shoulder without a step
				if str(a["ground"]) == "terrain":
					var aa: Vector3 = oa + a["right"] * (side * 3.0) - a["up"] * 0.9
					var ab: Vector3 = ob + b["right"] * (side * 3.0) - b["up"] * 0.9
					col_quad(faces, oa, aa, ob, ab, a["up"])
					quad(sst, oa, aa, ob, ab, na, na, nb, nb, Vector2(ua1, float(a["dist"]) / srep), Vector2(ua1 + side * 3.0 / srep, float(a["dist"]) / srep), Vector2(ub1, float(b["dist"]) / srep), Vector2(ub1 + side * 3.0 / srep, float(b["dist"]) / srep))
			# road deck skirt (side face) - deeper for elevated decks
			var ground: String = a["ground"]
			var depth := 1.4 if ground == "elevated" else (2.2 if ground == "void" else 1.2)
			var skirt_mat := TrackMats.wall_mat(TrackMats.wall_style_for(a), indoor) if ground != "elevated" else _deck_mat(a)
			var kst := batch.get_st("skirt|%s|%d" % [str(skirt_mat.get_instance_id()), chunk], skirt_mat, false)
			var da: Vector3 = oa - a["up"] * depth
			var db: Vector3 = ob - b["up"] * depth
			quad_flat(kst, oa, da, ob, db, a["right"] * side, 0.0, depth / 4.0, float(a["dist"]) / 4.0, float(b["dist"]) / 4.0)
		# deck underside for elevated / void roads (visible from below)
		if str(a["ground"]) in ["elevated", "void"]:
			var ust := batch.get_st("under|%d" % chunk, _deck_mat(a), false)
			var depth2 := 1.4 if str(a["ground"]) == "elevated" else 2.2
			var al: Vector3 = _road_point(a, -ha - float(a["sh_l"])) - a["up"] * depth2
			var ar: Vector3 = _road_point(a, ha + float(a["sh_r"])) - a["up"] * depth2
			var bl: Vector3 = _road_point(b, -hb - float(b["sh_l"])) - b["up"] * depth2
			var br: Vector3 = _road_point(b, hb + float(b["sh_r"])) - b["up"] * depth2
			quad_flat(ust, al, ar, bl, br, -a["up"], 0, 1, float(a["dist"]) / 6.0, float(b["dist"]) / 6.0)
	batch.commit(self)
	var body := _static_body(faces, TRACK_LAYER, "track")
	body.name = "TrackCollider"

func _deck_mat(s: Dictionary) -> StandardMaterial3D:
	var deck: String = s["deck"]
	match deck:
		"wood": return TrackMats.wall_mat("wood")
		"metal": return TrackMats.wall_mat("metal")
		"ice": return TrackMats.wall_mat("ice")
		"neon", "space": return TrackMats.wall_mat("space")
		"basalt", "volcano": return TrackMats.wall_mat("volcano")
		"lab": return TrackMats.wall_mat("lab")
	return TrackMats.wall_mat("temple")

# ------------------------------------------------------------------------------------------------ edges
func _edge_base(s: Dictionary, side: float) -> Vector3:
	var sk := "l" if side < 0.0 else "r"
	var hw: float = s["half_width"]
	var sh: float = float(s["sh_" + sk])
	var p := _road_point(s, side * hw)
	if sh > 0.1:
		p += s["right"] * (side * sh) - s["up"] * 0.12
	return p

func _build_edges() -> void:
	var S := spline.samples
	var n := S.size()
	var batch := Batch.new()
	var wall_faces := PackedVector3Array()
	var fence_faces := PackedVector3Array()
	var hp_faces := PackedVector3Array()
	var cliff_faces := PackedVector3Array()
	var post_xf: Array[Transform3D] = []
	var rail_post_xf: Array[Transform3D] = []
	for i in range(n):
		if _seg_skipped(i):
			continue
		var a: Dictionary = S[i]
		var b: Dictionary = S[(i + 1) % n]
		var chunk := i / CHUNK
		var indoor := float(a["ceil"]) > 0.0
		var v0 := float(a["dist"])
		var v1 := v0 + spline.step
		for side_i in range(2):
			var side := -1.0 if side_i == 0 else 1.0
			var sk := "l" if side < 0.0 else "r"
			var edge: String = a["edge_" + sk]
			if edge != str(b["edge_" + sk]) and edge != "halfpipe":
				edge = str(b["edge_" + sk]) if edge in ["open", "none", "shoulder"] else edge
			var inward: Vector3 = a["right"] * (-side)
			var inward_b: Vector3 = b["right"] * (-side)
			var ba := _edge_base(a, side)
			var bb := _edge_base(b, side)
			match edge:
				"wall", "cliff":
					var ha := float(a["wall_h_" + sk])
					var hb := float(b["wall_h_" + sk])
					if indoor:
						ha = maxf(ha, float(a["ceil"]) + 0.3)
						hb = maxf(hb, float(b["ceil"]) + 0.3) if float(b["ceil"]) > 0.0 else ha
					if edge == "cliff":
						ha = maxf(ha, 6.0 + sin(float(i) * 0.31) * 2.5)
						hb = maxf(hb, 6.0 + sin(float(i + 1) * 0.31) * 2.5)
					var style := "rock" if edge == "cliff" else TrackMats.wall_style_for(a)
					var mat := TrackMats.wall_mat(style, indoor)
					var rep := TrackMats.wall_repeat(style)
					var st := batch.get_st("wall|%s|%s|%d" % [style, str(indoor), chunk], mat)
					var ta: Vector3 = ba + a["up"] * ha
					var tb: Vector3 = bb + b["up"] * hb
					var down_a: Vector3 = ba - a["up"] * 1.4
					var down_b: Vector3 = bb - b["up"] * 1.4
					quad_flat(st, down_a, ta, down_b, tb, inward, 0.0, (ha + 1.4) / rep, v0 / rep, v1 / rep)
					# cap + outer face (thickness 0.9 m)
					var oa: Vector3 = ta - inward * 0.9
					var ob: Vector3 = tb - inward_b * 0.9
					quad_flat(st, ta, oa, tb, ob, a["up"], 0.0, 0.9 / rep, v0 / rep, v1 / rep)
					if not indoor:
						quad_flat(st, oa, oa - a["up"] * (ha + 2.0), ob, ob - b["up"] * (hb + 2.0), -inward, 0.0, (ha + 2.0) / rep, v0 / rep, v1 / rep)
					col_quad(cliff_faces if edge == "cliff" else wall_faces, down_a, ta, down_b, tb, inward)
				"fence":
					var hf := 1.15
					var mat_f := TrackMats.wall_mat("wood")
					var stf := batch.get_st("fence|%d" % chunk, mat_f)
					for rail_h in [0.45, 0.95]:
						var r0a: Vector3 = ba + a["up"] * rail_h
						var r0b: Vector3 = bb + b["up"] * rail_h
						var r1a: Vector3 = r0a + a["up"] * 0.22
						var r1b: Vector3 = r0b + b["up"] * 0.22
						quad_flat(stf, r0a, r1a, r0b, r1b, inward, 0.0, 0.2, v0 / 3.0, v1 / 3.0)
						quad_flat(stf, r1a, r1a - inward * 0.16, r1b, r1b - inward_b * 0.16, a["up"], 0.0, 0.1, v0 / 3.0, v1 / 3.0)
					if i % 2 == 0:
						var basis := Basis(a["right"], a["up"], -a["forward"]).orthonormalized()
						post_xf.append(Transform3D(basis, ba - inward * 0.08))
					col_quad(fence_faces, ba - a["up"] * 0.5, ba + a["up"] * hf, bb - b["up"] * 0.5, bb + b["up"] * hf, inward)
				"rail":
					var hr := float(a["wall_h_" + sk])
					hr = clampf(hr, 0.7, 1.4)
					var mat_r := TrackMats.wall_mat("wood") if str(a["deck"]) == "wood" else TrackMats.flat(Color(0.62, 0.64, 0.68), 0.35, 0.7)
					var str_ := batch.get_st("rail|%s|%d" % [str(mat_r.get_instance_id()), chunk], mat_r)
					var r0a2: Vector3 = ba + a["up"] * (hr - 0.32)
					var r0b2: Vector3 = bb + b["up"] * (hr - 0.32)
					var r1a2: Vector3 = ba + a["up"] * hr
					var r1b2: Vector3 = bb + b["up"] * hr
					quad_flat(str_, r0a2, r1a2, r0b2, r1b2, inward, 0.0, 0.3, v0 / 3.0, v1 / 3.0)
					quad_flat(str_, r1a2, r1a2 - inward * 0.2, r1b2, r1b2 - inward_b * 0.2, a["up"], 0.0, 0.1, v0 / 3.0, v1 / 3.0)
					quad_flat(str_, r1a2 - inward * 0.2, r0a2 - inward * 0.2, r1b2 - inward_b * 0.2, r0b2 - inward_b * 0.2, -inward, 0.0, 0.3, v0 / 3.0, v1 / 3.0)
					if i % 2 == 0:
						var basis2 := Basis(a["right"], a["up"], -a["forward"]).orthonormalized()
						rail_post_xf.append(Transform3D(basis2.scaled(Vector3(1.0, hr / 1.15, 1.0)), ba - inward * 0.1))
					col_quad(fence_faces, ba - a["up"] * 0.5, ba + a["up"] * (hr + 0.1), bb - b["up"] * 0.5, bb + b["up"] * (hr + 0.1), inward)
				"halfpipe":
					_add_halfpipe(batch, hp_faces, a, b, side, chunk, indoor)
				"open":
					# thin visual curb only: an honest open edge you can fall from
					var cmat := TrackMats.wall_mat(TrackMats.wall_style_for(a), indoor)
					var stc := batch.get_st("curb|%d" % chunk, cmat, false)
					quad_flat(stc, ba, ba + a["up"] * 0.14, bb, bb + b["up"] * 0.14, inward, 0.0, 0.05, v0 / 4.0, v1 / 4.0)
					quad_flat(stc, ba + a["up"] * 0.14, ba + a["up"] * 0.14 - inward * 0.5, bb + b["up"] * 0.14, bb + b["up"] * 0.14 - inward_b * 0.5, a["up"], 0.0, 0.1, v0 / 4.0, v1 / 4.0)
	batch.commit(self)
	if wall_faces.size() > 0:
		_static_body(wall_faces, WALL_LAYER, "wall", "heavy").name = "WallCollider"
	if cliff_faces.size() > 0:
		_static_body(cliff_faces, WALL_LAYER, "wall", "heavy").name = "CliffCollider"
	if fence_faces.size() > 0:
		_static_body(fence_faces, WALL_LAYER, "wall", "medium").name = "FenceCollider"
	if hp_faces.size() > 0:
		var hp := _static_body(hp_faces, TRACK_LAYER, "track")
		hp.name = "HalfpipeCollider"
	_spawn_posts(post_xf, Color(0.44, 0.30, 0.18))
	_spawn_posts(rail_post_xf, Color(0.55, 0.56, 0.6))

func _spawn_posts(xfs: Array[Transform3D], col: Color) -> void:
	if xfs.is_empty():
		return
	var bm := BoxMesh.new()
	bm.size = Vector3(0.24, 1.5, 0.24)
	var shifted: Array[Transform3D] = []
	for x in xfs:
		shifted.append(x.translated_local(Vector3(0.0, 0.55, 0.0)))
	bm.material = TrackMats.flat(col, 0.85)
	world.spawn_multimesh(bm, shifted, false)

func _add_halfpipe(batch: Batch, faces: PackedVector3Array, a: Dictionary, b: Dictionary, side: float, chunk: int, indoor: bool) -> void:
	## Drivable curved wall: quarter-circle radius 9 m up to 58 deg (+ a short lip). Part of the track collider.
	var steps := 6
	var radius := 9.0
	var max_ang := deg_to_rad(58.0)
	var surf: String = a["surface"]
	var mat := TrackMats.surface_mat(surf, indoor)
	var rep := TrackMats.surface_repeat(surf)
	var st := batch.get_st("hp|%s|%d" % [surf, chunk], mat)
	var ea := _road_point(a, side * float(a["half_width"]))
	var eb := _road_point(b, side * float(b["half_width"]))
	var arc_len := 0.0
	for k in range(steps):
		var ang0 := float(k) / float(steps) * max_ang
		var ang1 := float(k + 1) / float(steps) * max_ang
		var pa0: Vector3 = ea + a["right"] * (side * sin(ang0) * radius) + a["up"] * ((1.0 - cos(ang0)) * radius)
		var pa1: Vector3 = ea + a["right"] * (side * sin(ang1) * radius) + a["up"] * ((1.0 - cos(ang1)) * radius)
		var pb0: Vector3 = eb + b["right"] * (side * sin(ang0) * radius) + b["up"] * ((1.0 - cos(ang0)) * radius)
		var pb1: Vector3 = eb + b["right"] * (side * sin(ang1) * radius) + b["up"] * ((1.0 - cos(ang1)) * radius)
		var na0: Vector3 = (a["up"] * cos(ang0) - a["right"] * side * sin(ang0)).normalized()
		var na1: Vector3 = (a["up"] * cos(ang1) - a["right"] * side * sin(ang1)).normalized()
		var nb0: Vector3 = (b["up"] * cos(ang0) - b["right"] * side * sin(ang0)).normalized()
		var nb1: Vector3 = (b["up"] * cos(ang1) - b["right"] * side * sin(ang1)).normalized()
		var u0 := (float(a["half_width"]) + arc_len) / rep * side
		arc_len += radius * (ang1 - ang0)
		var u1 := (float(a["half_width"]) + arc_len) / rep * side
		var v0 := float(a["dist"]) / rep
		var v1 := (float(a["dist"]) + spline.step) / rep
		quad(st, pa0, pa1, pb0, pb1, na0, na1, nb0, nb1, Vector2(u0, v0), Vector2(u1, v0), Vector2(u0, v1), Vector2(u1, v1))
		col_quad(faces, pa0, pa1, pb0, pb1, (na0 + nb1).normalized())
	# outer shell (visual) closing the pipe behind the curved wall
	var top_a: Vector3 = ea + a["right"] * (side * sin(max_ang) * radius) + a["up"] * ((1.0 - cos(max_ang)) * radius)
	var top_b: Vector3 = eb + b["right"] * (side * sin(max_ang) * radius) + b["up"] * ((1.0 - cos(max_ang)) * radius)
	var wst := batch.get_st("hpwall|%d" % chunk, TrackMats.wall_mat(TrackMats.wall_style_for(a), indoor), false)
	quad_flat(wst, top_a, top_a + a["up"] * 1.2, top_b, top_b + b["up"] * 1.2, -a["right"] * side, 0, 0.2, 0, 1)
	quad_flat(wst, top_a + a["up"] * 1.2, top_a + a["up"] * 1.2 + a["right"] * side * 1.0, top_b + b["up"] * 1.2, top_b + b["up"] * 1.2 + b["right"] * side * 1.0, a["up"], 0, 0.2, 0, 1)

# ------------------------------------------------------------------------------------------------ indoor
func _build_indoor() -> void:
	var S := spline.samples
	var n := S.size()
	var batch := Batch.new()
	var light_spots: Array[Dictionary] = []
	var last_light := -999.0
	for i in range(n):
		var a: Dictionary = S[i]
		var b: Dictionary = S[(i + 1) % n]
		if float(a["ceil"]) <= 0.0 or float(b["ceil"]) <= 0.0 or _seg_skipped(i):
			continue
		var chunk := i / CHUNK
		var style := TrackMats.wall_style_for(a)
		var ca := float(a["ceil"])
		var cb := float(b["ceil"])
		var la: Vector3 = _edge_base(a, -1.0) + a["up"] * ca
		var ra: Vector3 = _edge_base(a, 1.0) + a["up"] * ca
		var lb: Vector3 = _edge_base(b, -1.0) + b["up"] * cb
		var rb: Vector3 = _edge_base(b, 1.0) + b["up"] * cb
		var rep := TrackMats.wall_repeat(style)
		var st := batch.get_st("ceil|%s|%d" % [style, chunk], TrackMats.wall_mat(style, true), false)
		quad_flat(st, la, ra, lb, rb, -a["up"], -float(a["half_width"]) / rep, float(a["half_width"]) / rep, float(a["dist"]) / rep, float(b["dist"]) / rep)
		# roof top (seen from outside / above), lifted 1.2 m
		var roof := batch.get_st("roof|%s|%d" % [style, chunk], TrackMats.wall_mat("rock" if style == "cave" else style), false)
		var lift_a: Vector3 = a["up"] * 1.2
		var lift_b: Vector3 = b["up"] * 1.2
		quad_flat(roof, la + lift_a - a["right"] * 1.0, ra + lift_a + a["right"] * 1.0, lb + lift_b - b["right"] * 1.0, rb + lift_b + b["right"] * 1.0, a["up"], 0, 2, float(a["dist"]) / 8.0, float(b["dist"]) / 8.0)
		# ceiling beams / light strips every ~14 m
		if float(a["dist"]) - last_light >= 14.0:
			last_light = float(a["dist"])
			light_spots.append({"s": a, "style": style, "i": i})
	batch.commit(self)
	_build_indoor_lights(light_spots)

func _build_indoor_lights(spots: Array[Dictionary]) -> void:
	var beam_xf: Array[Transform3D] = []
	var glow_xf: Array[Transform3D] = []
	var torch_xf: Array[Transform3D] = []
	var lit_count := 0
	for sp in spots:
		var s: Dictionary = sp["s"]
		var style: String = sp["style"]
		var basis := Basis(s["right"], s["up"], -s["forward"]).orthonormalized()
		var hw: float = s["half_width"]
		var ceil_h: float = s["ceil"]
		var top: Vector3 = s["pos"] + s["up"] * (ceil_h - 0.6)
		beam_xf.append(Transform3D(basis.scaled(Vector3(hw * 2.0 + 1.0, 1.0, 1.0)), top))
		if style in ["lab", "space", "metal"]:
			glow_xf.append(Transform3D(basis.scaled(Vector3(hw * 1.2, 1.0, 1.0)), top - s["up"] * 0.6))
		else:
			for side in [-1.0, 1.0]:
				torch_xf.append(Transform3D(basis, s["pos"] + s["right"] * (side * (hw - 0.3)) + s["up"] * 4.2))
		# a few real lights (no shadows) so karts & props catch light inside
		if int(sp["i"]) % 3 == 0 and lit_count < 24:
			lit_count += 1
			var ol := OmniLight3D.new()
			ol.light_color = Color(1.0, 0.72, 0.42) if style in ["temple", "cave", "rock", "volcano", "wood"] else (Color(0.5, 1.0, 0.7) if style == "lab" else Color(0.6, 0.75, 1.0))
			ol.light_energy = 2.4
			ol.omni_range = 22.0
			ol.shadow_enabled = false
			ol.position = s["pos"] + s["up"] * (ceil_h * 0.6)
			add_child(ol)
	var bm := BoxMesh.new()
	bm.size = Vector3(1.0, 0.7, 0.9)
	bm.material = TrackMats.wall_mat("wood")
	world.spawn_multimesh(bm, beam_xf, false)
	if not glow_xf.is_empty():
		var gm := BoxMesh.new()
		gm.size = Vector3(1.0, 0.12, 0.5)
		gm.material = TrackMats.flat(Color(0.75, 1.0, 0.85), 0.4, 0.0, 3.0)
		world.spawn_multimesh(gm, glow_xf, false)
	if not torch_xf.is_empty():
		var tm := CylinderMesh.new()
		tm.top_radius = 0.28; tm.bottom_radius = 0.12; tm.height = 0.7; tm.radial_segments = 6
		tm.material = TrackMats.flat(Color(1.0, 0.62, 0.2), 0.5, 0.0, 4.0)
		world.spawn_multimesh(tm, torch_xf, false)

# ------------------------------------------------------------------------------------------------ supports
func _build_supports() -> void:
	var S := spline.samples
	var n := S.size()
	var stone_xf: Array[Transform3D] = []
	var wood_xf: Array[Transform3D] = []
	var metal_xf: Array[Transform3D] = []
	var col_body := StaticBody3D.new()
	col_body.collision_layer = WALL_LAYER
	col_body.set_meta("surface_type", "prop_obstacle")
	col_body.set_meta("collision_strength", "heavy")
	add_child(col_body)
	var every := maxi(1, int(round(14.0 / spline.step)))
	for i in range(0, n, every):
		var s: Dictionary = S[i]
		if str(s["ground"]) != "elevated" or bool(s["gap"]):
			continue
		for side in [-1.0, 1.0]:
			var top: Vector3 = _road_point(s, side * (float(s["half_width"]) - 1.2)) - s["up"] * 1.3
			var ground_y := world.ground_height(top.x, top.z)
			if ground_y < -900.0:
				ground_y = top.y - 60.0
			var h := top.y - ground_y
			if h < 1.5:
				continue
			# never drop a pillar onto another road below
			var blocked := false
			for idx in spline.candidates_near(top.x, top.z, 30.0):
				var o: Dictionary = S[idx]
				if absf(float(o["pos"].y) - top.y) < 4.0:
					continue
				var rel: Vector3 = top - o["pos"]
				if absf(rel.dot(o["right"])) < float(o["half_width"]) + 3.5 and absf(rel.dot(o["forward"])) < spline.step * 1.5 and float(o["pos"].y) < top.y:
					blocked = true
					break
			if blocked:
				continue
			var xf := Transform3D(Basis().scaled(Vector3(1.0, h, 1.0)), Vector3(top.x, ground_y + h * 0.5, top.z))
			var deck: String = s["deck"]
			if deck == "wood":
				wood_xf.append(xf)
			elif deck in ["metal", "neon", "space", "lab"]:
				metal_xf.append(xf)
			else:
				stone_xf.append(xf)
			var cs := CollisionShape3D.new()
			var cyl := CylinderShape3D.new()
			cyl.radius = 1.0
			cyl.height = h
			cs.shape = cyl
			cs.position = Vector3(top.x, ground_y + h * 0.5, top.z)
			col_body.add_child(cs)
	var cm := CylinderMesh.new()
	cm.top_radius = 0.9; cm.bottom_radius = 1.3; cm.height = 1.0; cm.radial_segments = 8
	cm.material = TrackMats.wall_mat("temple")
	world.spawn_multimesh(cm, stone_xf, true)
	var wm := BoxMesh.new()
	wm.size = Vector3(0.9, 1.0, 0.9)
	wm.material = TrackMats.wall_mat("wood")
	world.spawn_multimesh(wm, wood_xf, true)
	var mm := CylinderMesh.new()
	mm.top_radius = 0.6; mm.bottom_radius = 0.8; mm.height = 1.0; mm.radial_segments = 8
	mm.material = TrackMats.flat(Color(0.5, 0.54, 0.6), 0.35, 0.75)
	world.spawn_multimesh(mm, metal_xf, true)

# ------------------------------------------------------------------------------------------------ start gantry
func _build_start_gantry() -> void:
	var s := spline.sample_at_t(0.0)
	var arch := Node3D.new()
	arch.position = s["pos"]
	arch.basis = Basis(s["right"], s["up"], -s["forward"]).orthonormalized()
	add_child(arch)
	var w: float = float(s["half_width"]) * 2.0
	var check_mat := TrackMats.pbr("checkerboard", Color.WHITE, 0.55)
	if check_mat.albedo_texture == null and ProceduralTextures:
		check_mat = StandardMaterial3D.new()
		check_mat.albedo_texture = ProceduralTextures.get_texture("checkerboard")
	check_mat.uv1_scale = Vector3(6.0, 1.0, 1.0)
	var strip := MeshInstance3D.new()
	var sm := BoxMesh.new()
	sm.size = Vector3(w - 1.0, 0.05, 3.8)
	strip.mesh = sm
	strip.material_override = check_mat
	strip.position = Vector3(0.0, 0.05 + float(s.get("crown", 0.0)), 0.0)
	arch.add_child(strip)
	var gantry := _inst_glb("res://assets/models/prop_start_arch.glb")
	var scale_x := clampf(float(s["half_width"]) / 13.0, 0.85, 1.3)
	if gantry:
		gantry.scale = Vector3(scale_x, 1.0, 1.0)
		arch.add_child(gantry)
	for side in [-1.0, 1.0]:
		_add_cyl_collider(arch, 2.1, 14.0, Vector3(side * 14.0 * scale_x, 0.0, 0.0), false, "heavy")

# ------------------------------------------------------------------------------------------------ pads / rings
func _build_turbo_pads() -> void:
	var pad_shader := _load_shader("res://assets/shaders/turbo_pad.gdshader")
	for pd in data.get("features", {}).get("pads", []):
		var t_val := spline.t_of_dist(float(pd["d"]))
		var lat: float = float(pd.get("lat", 0.0)) * mx
		var is_super: bool = bool(pd.get("super", false))
		var s := spline.sample_at_t(t_val)
		var world_pos: Vector3 = spline.surface_point(t_val, lat) + s["up"] * 0.04
		turbo_pad_positions.append({"pos": world_pos, "t": t_val, "lateral": lat, "super": is_super})
		var pad_node := Node3D.new()
		pad_node.position = world_pos
		pad_node.basis = Basis(s["right"], s["up"], -s["forward"]).orthonormalized()
		add_child(pad_node)
		var pad_w := 7.6 if is_super else 6.8
		var pad_l := 13.5 if is_super else float(pd.get("len", 11.2))
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(pad_w, 0.05, pad_l)
		mi.mesh = bm
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var mat := ShaderMaterial.new()
		mat.shader = pad_shader
		if is_super:
			mat.set_shader_parameter("base_dark", Color(0.03, 0.06, 0.18))
			mat.set_shader_parameter("main_glow", Color(0.06, 0.56, 1.0))
			mat.set_shader_parameter("hot_glow", Color(0.38, 0.98, 1.0))
			mat.set_shader_parameter("scroll_speed", 3.6)
		else:
			mat.set_shader_parameter("base_dark", Color(0.12, 0.07, 0.04))
			mat.set_shader_parameter("main_glow", Color(1.0, 0.44, 0.04))
			mat.set_shader_parameter("hot_glow", Color(1.0, 0.94, 0.28))
			mat.set_shader_parameter("scroll_speed", 2.4)
		mi.material_override = mat
		pad_node.add_child(mi)
		var area := Area3D.new()
		area.collision_layer = 32
		area.collision_mask = 16
		var acs := CollisionShape3D.new()
		var abs_shape := BoxShape3D.new()
		abs_shape.size = Vector3(pad_w + 1.0, 2.6, pad_l + 1.2)
		acs.shape = abs_shape
		acs.position = Vector3(0.0, 1.2, 0.0)
		area.add_child(acs)
		area.body_entered.connect(func(body):
			if body is KartPhysics:
				body.trigger_turbo_pad(is_super)
		)
		pad_node.add_child(area)

func _build_boost_rings() -> void:
	for br in data.get("features", {}).get("rings", []):
		var t_val := spline.t_of_dist(float(br["d"]))
		var s := spline.sample_at_t(t_val)
		var pos: Vector3 = spline.surface_point(t_val, float(br.get("lat", 0.0)) * mx) + s["up"] * float(br.get("h", 4.6))
		var ring_node := Node3D.new()
		ring_node.position = pos
		ring_node.basis = Basis(s["right"], s["up"], -s["forward"]).orthonormalized()
		var inst := _inst_glb("res://assets/models/prop_boost_ring.glb")
		if inst:
			ring_node.add_child(inst)
		var area := Area3D.new()
		area.collision_layer = 32
		area.collision_mask = 16
		var cs := CollisionShape3D.new()
		var sph := SphereShape3D.new()
		sph.radius = 4.8
		cs.shape = sph
		area.add_child(cs)
		area.body_entered.connect(func(body):
			if body is KartPhysics:
				body.add_boost(KartPhysics.FireTier.SACRED, 2.0, 9.0, true)
				body.add_fruit(2)
		)
		ring_node.add_child(area)
		add_child(ring_node)

# ------------------------------------------------------------------------------------------------ obstacles
func _build_obstacles() -> void:
	for ob in data.get("features", {}).get("obstacles", []):
		var t_val := spline.t_of_dist(float(ob["d"]))
		var lat: float = float(ob.get("lat", 0.0)) * mx
		var s := spline.sample_at_t(t_val)
		var pos := spline.surface_point(t_val, lat)
		var kind: String = str(ob["kind"])
		var r := float(ob.get("r", 1.5))
		var strength := str(ob.get("strength", "heavy"))
		var node := TrackProps.make_obstacle(kind, r, s, self)
		node.position = pos
		node.basis = Basis(s["right"], s["up"], -s["forward"]).orthonormalized()
		add_child(node)
		var h := float(s["ceil"]) if float(s["ceil"]) > 0.0 and kind in ["temple_pillar", "lab_column", "ice_pillar"] else 4.5
		_add_cyl_collider(node, r, maxf(3.0, h), Vector3.ZERO, false, strength)
		spawned_prop_bounds.append({"pos": pos, "radius": r})
		obstacle_list.append({"t": t_val, "lat": lat, "r": r, "kind": kind})

# ------------------------------------------------------------------------------------------------ shortcuts
func _build_shortcuts() -> void:
	for sc in data.get("features", {}).get("shortcuts", []):
		var g := TrackShortcuts.build(self, sc, mx)
		if not g.is_empty():
			shortcut_geometries.append(g)

# ------------------------------------------------------------------------------------------------ pickups / hazards
func _compute_pickups() -> void:
	var feats: Dictionary = data.get("features", {})
	for cr in feats.get("crates", []):
		var t_val := spline.t_of_dist(float(cr["d"]))
		var s := spline.sample_at_t(t_val)
		var cnt := int(cr.get("n", 4))
		var span: float = float(s["half_width"]) * 2.0 * float(cr.get("spread", 0.7))
		for k in range(cnt):
			var frac := -0.5 + float(k) / float(maxi(1, cnt - 1))
			crate_spawn_points.append(spline.surface_point(t_val, frac * span) + s["up"] * 1.25)
	for tr in feats.get("fruit", []):
		var count: int = int(tr.get("n", 5))
		for k in range(count):
			var u := float(k) / float(maxi(1, count - 1))
			var d := lerpf(float(tr["d0"]), float(tr["d1"]), u)
			var lat := lerpf(float(tr["lat"]), float(tr.get("lat1", tr["lat"])), u) * mx
			var t_val := spline.t_of_dist(d)
			var s := spline.sample_at_t(t_val)
			fruit_spawn_points.append(spline.surface_point(t_val, lat) + s["up"] * 1.2)

func _convert_hazards() -> void:
	for hz in data.get("features", {}).get("hazards", []):
		var h: Dictionary = hz.duplicate(true)
		h["t"] = spline.t_of_dist(float(hz["d"]))
		if h.has("lat"):
			h["lateral"] = float(h["lat"]) * mx
		hazard_defs.append(h)
