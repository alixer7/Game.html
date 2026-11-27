class_name TrackBuilder
extends Node3D

## CTR:NF v7.0 Procedural Multi-Biome 3D Track, Crowned PBR Road, Living World & Pure Jump-Shortcut Generator!
## - ZERO floor blocking (unified single-face driving collider, Area3D-only Turbo Pads, flush non-overlapping offroad!)
## - ZERO side-lane bypass bridges (all 9 shortcuts are pure jump-based platforming decisions!)
## - Real tiered collision strength (soft / medium / heavy) on walls, fences, landmarks, AND close MultiMesh props!

var spline: TrackSpline = TrackSpline.new()
var track_def: Dictionary = {}
var shortcut_geometries: Array[Dictionary] = []
var turbo_pad_positions: Array[Dictionary] = []
var crate_spawn_points: Array[Vector3] = []
var fruit_spawn_points: Array[Vector3] = []
var spawned_prop_bounds: Array[Dictionary] = []
var _extra_corridors: Array[Dictionary] = []
var _clifftop_spots: Array[Dictionary] = []

static var _glb_cache: Dictionary = {}
static var _glb_mesh_cache: Dictionary = {}
static var _shader_cache: Dictionary = {}
static var _png_tex_cache: Dictionary = {}

static func _inst_glb(path: String) -> Node3D:
	if not _glb_cache.has(path):
		var res = load(path)
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

func build_track(track_id: String, mirrored: bool = false) -> Dictionary:
	for c in get_children():
		c.queue_free()
	shortcut_geometries.clear()
	turbo_pad_positions.clear()
	crate_spawn_points.clear()
	fruit_spawn_points.clear()
	spawned_prop_bounds.clear()
	_extra_corridors.clear()
	_clifftop_spots.clear()

	track_def = TrackDefs.get_track_def(track_id, mirrored)
	spline = TrackSpline.new()
	# 400 uniform samples across 2.18-2.46 km tracks (~5.6m/seg): silky curves & fast mobile physics!
	spline.build_from_control_points(track_def["control_points"], 400)

	_build_environment()
	_build_sea_or_ground_plane()
	_build_sky_atmosphere_and_clouds()
	_build_road_and_shoulders()
	_build_walls_and_halfpipes()
	_build_bridges_and_tunnels()
	_build_start_finish_arch()
	# Build pure jump-based platforming shortcuts BEFORE cliffs/landmarks/scenery so ALL flight corridors are 100% clear!
	_build_aerial_shortcuts()
	_build_canyon_terrain_banks()
	_build_overroad_archways_and_turn_signs()
	_build_turbo_pads()
	_build_aerial_boost_rings()
	_build_horizon_mountain_ring()
	_build_hero_landmarks_and_waterfalls()
	_build_multimesh_lush_foliage()
	_build_scenery_props()
	_compute_pickups()

	return {
		"spline": spline,
		"def": track_def,
		"shortcuts": shortcut_geometries,
		"turbo_pads": turbo_pad_positions,
		"hazards": track_def.get("hazards", []),
		"crate_points": crate_spawn_points,
		"fruit_points": fruit_spawn_points,
		"prop_bounds": spawned_prop_bounds
	}

func _build_environment() -> void:
	var env := Environment.new()
	var sky := Sky.new()
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = track_def["sky_top"]
	sky_mat.sky_horizon_color = track_def["sky_horizon"]
	sky_mat.ground_bottom_color = track_def["ground_color"].darkened(0.35)
	sky_mat.ground_horizon_color = track_def["sky_horizon"].lerp(track_def["ground_color"], 0.35)
	sky_mat.sun_angle_max = 26.0
	sky_mat.sun_curve = 0.14
	sky.sky_material = sky_mat

	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.46
	env.fog_enabled = true
	env.fog_light_color = track_def["fog_color"]
	env.fog_light_energy = 1.05
	env.fog_density = float(track_def.get("fog_density", 0.0010))
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = 0.98
	# Keep fullscreen multi-pass glow OFF in gl_compatibility for locked 60FPS on 1440p phones!
	env.glow_enabled = false

	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

	var sun := DirectionalLight3D.new()
	sun.light_color = track_def["sun_color"]
	sun.light_energy = 1.14
	sun.shadow_enabled = GameState.graphics_high if GameState else true
	sun.directional_shadow_max_distance = 135.0
	sun.rotation_degrees = Vector3(float(track_def.get("sun_pitch", -22.0)), float(track_def.get("sun_yaw", 22.0)), 0.0)
	add_child(sun)

	var rim := DirectionalLight3D.new()
	rim.light_color = track_def["sky_horizon"]
	rim.light_energy = 0.36
	rim.shadow_enabled = false
	rim.rotation_degrees = Vector3(-16.0, -148.0, 0.0)
	add_child(rim)

func _disable_shadow_recursive(node: Node) -> void:
	if node is GeometryInstance3D:
		(node as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for c in node.get_children():
		_disable_shadow_recursive(c)

func _add_cyl_collider(parent: Node3D, radius: float, height: float, local_pos: Vector3 = Vector3.ZERO, record_world: bool = true, strength: String = "heavy") -> void:
	var sb := StaticBody3D.new()
	sb.collision_layer = 2
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
		var wp := parent.position + local_pos
		spawned_prop_bounds.append({"pos": wp, "radius": radius})

func _push_out_of_track_corridor(pos: Vector3, required_radius: float) -> Vector3:
	var pt := Vector2(pos.x, pos.z)
	var safety := required_radius + 8.5
	var guard := 0
	while spline.get_min_2d_track_clearance(pt, _extra_corridors) < safety and guard < 22:
		var dir := pt.normalized()
		if dir.length_squared() < 0.01:
			dir = Vector2(1.0, 0.0)
		pt += dir * 24.0
		guard += 1
	return Vector3(pt.x, pos.y, pt.y)

func _build_sky_atmosphere_and_clouds() -> void:
	var theme: String = track_def["theme"]
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(track_def["id"]) + 515

	if theme == "glacier":
		var aur_shader := _load_shader("res://assets/shaders/aurora_ribbon.gdshader")
		if aur_shader:
			for k in range(3):
				var ribbon := MeshInstance3D.new()
				var pm := PlaneMesh.new()
				pm.size = Vector2(620.0, 95.0)
				pm.subdivide_width = 24
				pm.subdivide_depth = 4
				ribbon.mesh = pm
				var sm := ShaderMaterial.new()
				sm.shader = aur_shader
				ribbon.material_override = sm
				var ang := float(k) * 1.15 - 0.8
				ribbon.position = Vector3(cos(ang) * 280.0, 155.0 + float(k) * 24.0, sin(ang) * 280.0)
				ribbon.rotation_degrees = Vector3(78.0, rad_to_deg(ang) + 90.0, 0.0)
				add_child(ribbon)
	elif theme == "volcano":
		# Cosmic Citadel Starway: Starfield Dome + Ringed Nebula Planet (2 draw calls!)
		var star_m := SphereMesh.new()
		star_m.radius = 1.8; star_m.height = 3.6; star_m.radial_segments = 6; star_m.rings = 4
		var star_mat := StandardMaterial3D.new()
		star_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		star_mat.albedo_color = Color(0.84, 0.94, 1.0)
		star_m.surface_set_material(0, star_mat)
		var star_xforms: Array[Transform3D] = []
		for _si in range(96):
			var ang := rng.randf() * TAU
			var elev := rng.randf_range(0.16, 0.90)
			var dist := rng.randf_range(460.0, 700.0)
			var sp := Vector3(cos(ang) * cos(elev) * dist, sin(elev) * dist + 45.0, sin(ang) * cos(elev) * dist)
			var sc := rng.randf_range(0.7, 2.3)
			star_xforms.append(Transform3D(Basis().scaled(Vector3(sc, sc, sc)), sp))
		_spawn_multimesh_batch(star_m, star_xforms, false)

		var planet := MeshInstance3D.new()
		var pm_sp := SphereMesh.new()
		pm_sp.radius = 64.0; pm_sp.height = 128.0; pm_sp.radial_segments = 20; pm_sp.rings = 12
		planet.mesh = pm_sp
		var p_mat := StandardMaterial3D.new()
		p_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		p_mat.albedo_color = Color(0.56, 0.24, 0.88)
		planet.material_override = p_mat
		planet.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		planet.position = Vector3(260.0, 215.0, -520.0)
		add_child(planet)

		var p_ring := MeshInstance3D.new()
		var tr_m := TorusMesh.new()
		tr_m.inner_radius = 80.0; tr_m.outer_radius = 104.0; tr_m.rings = 28; tr_m.ring_segments = 8
		p_ring.mesh = tr_m
		var r_mat := StandardMaterial3D.new()
		r_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		r_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		r_mat.albedo_color = Color(0.22, 0.88, 1.0, 0.56)
		p_ring.material_override = r_mat
		p_ring.scale = Vector3(1.0, 0.14, 1.0)
		p_ring.rotation_degrees = Vector3(22.0, 15.0, -18.0)
		p_ring.position = planet.position
		p_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(p_ring)
	else:
		# Golden-Hour Sunlit Sky Clouds ringing the tropical canyon horizon (batched MultiMesh = 1 draw call!)
		var cloud_m := SphereMesh.new()
		cloud_m.radial_segments = 10; cloud_m.rings = 6
		var cloud_mat := StandardMaterial3D.new()
		cloud_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		cloud_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		cloud_mat.albedo_color = Color(1.0, 0.88, 0.72, 0.66)
		cloud_m.surface_set_material(0, cloud_mat)
		var c_xforms: Array[Transform3D] = []
		for c in range(20):
			var ang := float(c) / 20.0 * TAU + rng.randf_range(-0.1, 0.1)
			var rad := rng.randf_range(380.0, 580.0)
			var cy := rng.randf_range(100.0, 170.0)
			var base_p := Vector3(cos(ang) * rad, cy, sin(ang) * rad)
			for p_i in range(3):
				var sx := rng.randf_range(28.0, 56.0)
				var sc_v := Vector3(sx, rng.randf_range(8.5, 16.0), sx * 0.65)
				var p_off := Vector3(float(p_i - 1) * sx * 0.58, rng.randf_range(-3.0, 5.0), rng.randf_range(-8.0, 8.0))
				c_xforms.append(Transform3D(Basis().scaled(sc_v), base_p + p_off))
		_spawn_multimesh_batch(cloud_m, c_xforms, false)

func _build_sea_or_ground_plane() -> void:
	var plane_mi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(2200.0, 2200.0)
	pm.subdivide_width = 16
	pm.subdivide_depth = 16
	plane_mi.mesh = pm
	plane_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var theme: String = track_def["theme"]
	if theme == "tiki":
		var sm := ShaderMaterial.new()
		sm.shader = _load_shader("res://assets/shaders/water_ocean.gdshader")
		plane_mi.material_override = sm
	elif theme == "volcano":
		var sm := ShaderMaterial.new()
		sm.shader = _load_shader("res://assets/shaders/lava_sea.gdshader")
		plane_mi.material_override = sm
	else:
		var mat := _make_pbr_mat("offroad_snow", 0.72)
		mat.uv1_scale = Vector3(60.0, 60.0, 1.0)
		plane_mi.material_override = mat
	plane_mi.position = Vector3(0.0, float(track_def.get("sea_level", -3.0)), 0.0)
	add_child(plane_mi)

func _build_horizon_mountain_ring() -> void:
	var theme: String = track_def["theme"]
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(track_def["id"]) + 999
	var sea_y: float = float(track_def.get("sea_level", -3.0))

	var glb_path := "res://assets/models/prop_mountain_tiki.glb"
	if theme == "glacier": glb_path = "res://assets/models/prop_mountain_glacier.glb"
	elif theme == "volcano": glb_path = "res://assets/models/prop_mountain_volcano.glb"

	var mt_mesh := _extract_glb_mesh(glb_path)
	if mt_mesh:
		var xforms: Array[Transform3D] = []
		for k in range(24):
			var ang := float(k) / 24.0 * TAU + rng.randf_range(-0.08, 0.08)
			var rad := rng.randf_range(580.0, 740.0)
			var h := rng.randf_range(80.0, 175.0)
			var w := rng.randf_range(62.0, 112.0)
			var sz_f := rng.randf_range(0.85, 1.15)
			var actual_r := w * maxf(1.0, sz_f) * 1.15
			var pos := _push_out_of_track_corridor(Vector3(cos(ang) * rad, sea_y - 3.5, sin(ang) * rad), actual_r)
			var b := Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(w, h, w * sz_f))
			xforms.append(Transform3D(b, pos))
			spawned_prop_bounds.append({"pos": pos, "radius": actual_r})
		_spawn_multimesh_batch(mt_mesh, xforms, false)

func _build_road_and_shoulders() -> void:
	## v7.0 Unified Multi-Biome Crowned Road + Flush Cuttable Off-Road Shoulders:
	## - Single continuous Layer-1 collision mesh across all non-ice biomes (ZERO floor-seam snags!)
	## - Convex 3-vertex crowned road profile (left -> center + crown -> right)
	## - 100% FLUSH off-road shoulder seam (0.00m vertical step!) + inner-turn width clamping!
	var samples := spline.samples
	var n := samples.size()

	var st_road := SurfaceTool.new()
	var st_biolab := SurfaceTool.new()
	var st_space := SurfaceTool.new()
	var st_volcano := SurfaceTool.new()
	var st_ice := SurfaceTool.new()
	var st_wood := SurfaceTool.new()
	var st_road_col := SurfaceTool.new()
	var st_ice_col := SurfaceTool.new()
	var st_off := SurfaceTool.new()
	for st_i in [st_road, st_biolab, st_space, st_volcano, st_ice, st_wood, st_road_col, st_ice_col, st_off]:
		st_i.begin(Mesh.PRIMITIVE_TRIANGLES)

	var has_road := false
	var has_biolab := false
	var has_space := false
	var has_volcano := false
	var has_ice := false
	var has_wood := false
	var has_off := false
	var uv_v := 0.0

	for i in range(n):
		var a := samples[i]
		var b := samples[(i + 1) % n]
		var seg_len: float = a["pos"].distance_to(b["pos"])
		var v0 := uv_v
		var v1 := uv_v + seg_len / 14.0
		uv_v = v1

		var a_up: Vector3 = a["up"]
		var b_up: Vector3 = b["up"]
		var a_right: Vector3 = a["right"]
		var b_right: Vector3 = b["right"]
		var al: Vector3 = a["pos"] - a_right * float(a["half_width"])
		var ar: Vector3 = a["pos"] + a_right * float(a["half_width"])
		var bl: Vector3 = b["pos"] - b_right * float(b["half_width"])
		var br: Vector3 = b["pos"] + b_right * float(b["half_width"])
		var ac: Vector3 = a["pos"] + a_up * float(a.get("crown", 0.0))
		var bc: Vector3 = b["pos"] + b_up * float(b.get("crown", 0.0))

		var surf: String = a["surface"]
		var target_st := st_road
		var target_col := st_road_col
		if surf == "ice":
			target_st = st_ice
			target_col = st_ice_col
			has_ice = true
		elif surf == "wood":
			target_st = st_wood
			has_wood = true
		elif surf == "biolab":
			target_st = st_biolab
			has_biolab = true
		elif surf == "space":
			target_st = st_space
			has_space = true
		elif surf == "volcano":
			target_st = st_volcano
			has_volcano = true
		else:
			has_road = true

		# Two-quad crowned cross-section for BOTH visual & single-face unified physics!
		_add_quad_u(target_st, al, ac, bl, bc, 0.0, 0.5, v0, v1, a_up, b_up)
		_add_quad_u(target_st, ac, ar, bc, br, 0.5, 1.0, v0, v1, a_up, b_up)
		_add_quad_u(target_col, al, ac, bl, bc, 0.0, 0.5, v0, v1, a_up, b_up)
		_add_quad_u(target_col, ac, ar, bc, br, 0.5, 1.0, v0, v1, a_up, b_up)

		# Sculpted road deck skirt (visual-only — zero wasted physics triangles!)
		var thick := 2.2
		var al_d: Vector3 = al - a_up * thick
		var ar_d: Vector3 = ar - a_up * thick
		var bl_d: Vector3 = bl - b_up * thick
		var br_d: Vector3 = br - b_up * thick
		_add_quad(target_st, al_d, al, bl_d, bl, v0, v1, -a_right, -b_right)
		_add_quad(target_st, ar, ar_d, br, br_d, v0, v1, a_right, b_right)

		# 100% FLUSH cuttable off-road shoulders (0.00m drop at road seam + inner-curve clamping!)
		var curv_a: float = float(a.get("curvature", 0.0))
		var curv_b: float = float(b.get("curvature", 0.0))
		var ol_a: float = float(a["off_l"])
		var ol_b: float = float(b["off_l"])
		if curv_a < -0.06: ol_a = maxf(0.0, ol_a - clampf(absf(curv_a) * 22.0, 0.0, ol_a * 0.80))
		if curv_b < -0.06: ol_b = maxf(0.0, ol_b - clampf(absf(curv_b) * 22.0, 0.0, ol_b * 0.80))
		if ol_a > 0.45 and ol_b > 0.45:
			has_off = true
			var ol0: Vector3 = al - a_right * ol_a - a_up * 0.16
			var ol1: Vector3 = bl - b_right * ol_b - b_up * 0.16
			_add_quad(st_off, ol0, al, ol1, bl, v0, v1, a_up, b_up)

		var or_a: float = float(a["off_r"])
		var or_b: float = float(b["off_r"])
		if curv_a > 0.06: or_a = maxf(0.0, or_a - clampf(absf(curv_a) * 22.0, 0.0, or_a * 0.80))
		if curv_b > 0.06: or_b = maxf(0.0, or_b - clampf(absf(curv_b) * 22.0, 0.0, or_b * 0.80))
		if or_a > 0.45 and or_b > 0.45:
			has_off = true
			var or0: Vector3 = ar + a_right * or_a - a_up * 0.16
			var or1: Vector3 = br + b_right * or_b - b_up * 0.16
			_add_quad(st_off, ar, or0, br, or1, v0, v1, a_up, b_up)

	# Commit unified non-ice road collider ONCE (guaranteed seamless across all biome transitions!)
	st_road_col.generate_normals()
	var rc_sb := StaticBody3D.new()
	rc_sb.collision_layer = 1
	rc_sb.set_meta("surface_type", "road")
	var rc_cs := CollisionShape3D.new()
	rc_cs.shape = st_road_col.commit().create_trimesh_shape()
	rc_sb.add_child(rc_cs)
	add_child(rc_sb)

	if has_road:
		var m := _make_pbr_mat(track_def["road_tex"], 0.88)
		m.uv1_scale = Vector3(2.4, 2.2, 1.0)
		_commit_visual_only(st_road, m)
	if has_biolab:
		var m_bio := _make_pbr_mat("road_biolab", 0.56, 0.35)
		m_bio.uv1_scale = Vector3(2.0, 2.0, 1.0)
		_commit_visual_only(st_biolab, m_bio)
	if has_space:
		var m_sp := _make_pbr_mat("road_space", 0.42, 0.48)
		m_sp.uv1_scale = Vector3(1.8, 2.0, 1.0)
		_commit_visual_only(st_space, m_sp)
	if has_volcano:
		var m_vol := _make_pbr_mat("road_volcano", 0.86)
		m_vol.uv1_scale = Vector3(2.2, 2.2, 1.0)
		_commit_visual_only(st_volcano, m_vol)
	if has_wood:
		var wood_mat := _make_pbr_mat("wood_bridge", 0.84)
		wood_mat.uv1_scale = Vector3(1.6, 1.6, 1.0)
		_commit_visual_only(st_wood, wood_mat)
	if has_ice:
		var ice_mat := _make_pbr_mat("ice_surface", 0.24, 0.10)
		ice_mat.uv1_scale = Vector3(1.8, 1.8, 1.0)
		_commit_surface_split_col(st_ice, st_ice_col, "ice", 8, ice_mat)
	if has_off:
		var off_mat := _make_pbr_mat(track_def["offroad_tex"], 0.94)
		off_mat.uv1_scale = Vector3(2.0, 2.0, 1.0)
		_commit_surface(st_off, "offroad", 4, off_mat)

func _build_walls_and_halfpipes() -> void:
	var samples := spline.samples
	var n := samples.size()
	var theme: String = track_def["theme"]

	var st_wall := SurfaceTool.new()
	var st_wall_bio := SurfaceTool.new()
	var st_wall_space := SurfaceTool.new()
	var st_wall_vol := SurfaceTool.new()
	var st_wall_col := SurfaceTool.new()
	var st_fence := SurfaceTool.new()
	var st_fence_col := SurfaceTool.new()
	var st_hp := SurfaceTool.new()
	for st_i in [st_wall, st_wall_bio, st_wall_space, st_wall_vol, st_wall_col, st_fence, st_fence_col, st_hp]:
		st_i.begin(Mesh.PRIMITIVE_TRIANGLES)
	var has_wall := false
	var has_wall_bio := false
	var has_wall_space := false
	var has_wall_vol := false
	var has_wall_col := false
	var has_fence := false
	var has_hp := false
	var uv_v := 0.0

	for i in range(n):
		var a := samples[i]
		var b := samples[(i + 1) % n]
		var seg_len: float = a["pos"].distance_to(b["pos"])
		var v0 := uv_v
		var v1 := uv_v + seg_len / 7.0
		uv_v = v1

		var a_right: Vector3 = a["right"]
		var b_right: Vector3 = b["right"]
		var a_up: Vector3 = a["up"]
		var b_up: Vector3 = b["up"]
		var biome: String = str(a.get("biome", ""))

		for side_idx in range(2):
			var side := -1.0 if side_idx == 0 else 1.0
			var hp_key := "halfpipe_l" if side < 0.0 else "halfpipe_r"
			var w_key := "wall_l" if side < 0.0 else "wall_r"
			var off_key := "off_l" if side < 0.0 else "off_r"

			if a[hp_key] and b[hp_key]:
				has_hp = true
				_add_halfpipe_strip(st_hp, a, b, side, v0, v1)
			elif float(a[w_key]) > 0.35 and float(b[w_key]) > 0.35:
				var a_base: Vector3 = a["pos"] + a_right * (side * (float(a["half_width"]) + float(a[off_key])))
				var b_base: Vector3 = b["pos"] + b_right * (side * (float(b["half_width"]) + float(b[off_key])))
				var wa := float(a[w_key])
				var wb := float(b[w_key])
				var use_fence: bool = (theme != "volcano") and (biome != "bio_lab") and (biome != "reactor_overpass") and (wa <= 2.35) and (wb <= 2.35) and (not bool(a["tunnel"])) and (not bool(b["tunnel"]))
				if use_fence:
					has_fence = true
					_add_wooden_fence_segment(st_fence, st_fence_col, a_base, b_base, a_right, b_right, a_up, b_up, side, v0, v1, (i % 2 == 0))
				else:
					has_wall_col = true
					var target_w := st_wall
					if biome == "bio_lab" or biome == "reactor_overpass":
						target_w = st_wall_bio; has_wall_bio = true
					elif biome == "space_hangar" or biome == "asteroid_nebula" or biome == "plasma_conduit":
						target_w = st_wall_space; has_wall_space = true
					elif biome == "magma_mine":
						target_w = st_wall_vol; has_wall_vol = true
					else:
						has_wall = true

					var a_top: Vector3 = a_base + a_up * wa
					var b_top: Vector3 = b_base + b_up * wb
					var a_out: Vector3 = a_top + a_right * (side * 1.4)
					var b_out: Vector3 = b_top + b_right * (side * 1.4)
					var a_out_b: Vector3 = a_base + a_right * (side * 1.4) - a_up * 2.0
					var b_out_b: Vector3 = b_base + b_right * (side * 1.4) - b_up * 2.0
					if side < 0.0:
						_add_quad(target_w, a_top, a_base, b_top, b_base, v0, v1, a_right, b_right)
						_add_quad(st_wall_col, a_top, a_base, b_top, b_base, v0, v1, a_right, b_right)
						_add_quad(target_w, a_out, a_top, b_out, b_top, v0, v1, a_up, b_up)
						_add_quad(target_w, a_out_b, a_out, b_out_b, b_out, v0, v1, -a_right, -b_right)
					else:
						_add_quad(target_w, a_base, a_top, b_base, b_top, v0, v1, -a_right, -b_right)
						_add_quad(st_wall_col, a_base, a_top, b_base, b_top, v0, v1, -a_right, -b_right)
						_add_quad(target_w, a_top, a_out, b_top, b_out, v0, v1, a_up, b_up)
						_add_quad(target_w, a_out, a_out_b, b_out, b_out_b, v0, v1, a_right, b_right)

	if has_wall_col:
		st_wall_col.generate_normals()
		var w_sb := StaticBody3D.new()
		w_sb.collision_layer = 2
		w_sb.set_meta("surface_type", "wall")
		w_sb.set_meta("collision_strength", "heavy")
		var w_cs := CollisionShape3D.new()
		w_cs.shape = st_wall_col.commit().create_trimesh_shape()
		w_sb.add_child(w_cs)
		add_child(w_sb)
	if has_wall:
		_commit_visual_only(st_wall, _make_pbr_mat(track_def["wall_tex"], 0.86))
	if has_wall_bio:
		_commit_visual_only(st_wall_bio, _make_pbr_mat("wall_biolab", 0.50, 0.35))
	if has_wall_space:
		_commit_visual_only(st_wall_space, _make_pbr_mat("wall_space", 0.42, 0.45))
	if has_wall_vol:
		_commit_visual_only(st_wall_vol, _make_pbr_mat("wall_volcano", 0.86))
	if has_fence:
		st_fence.generate_normals()
		var f_mi := MeshInstance3D.new()
		f_mi.mesh = st_fence.commit()
		f_mi.material_override = _make_pbr_mat("wood_bridge", 0.82)
		add_child(f_mi)
		st_fence_col.generate_normals()
		var f_sb := StaticBody3D.new()
		f_sb.collision_layer = 2
		f_sb.set_meta("surface_type", "wall")
		f_sb.set_meta("collision_strength", "medium")
		var f_cs := CollisionShape3D.new()
		f_cs.shape = st_fence_col.commit().create_trimesh_shape()
		f_sb.add_child(f_cs)
		add_child(f_sb)
	if has_hp:
		_commit_surface(st_hp, "kicker", 1, _make_pbr_mat(track_def["wall_tex"], 0.70))

func _add_wooden_fence_segment(st_vis: SurfaceTool, st_col: SurfaceTool, a_base: Vector3, b_base: Vector3, a_r: Vector3, b_r: Vector3, a_u: Vector3, b_u: Vector3, side: float, v0: float, v1: float, add_post: bool) -> void:
	var a_c_top := a_base + a_u * 2.1
	var b_c_top := b_base + b_u * 2.1
	if side < 0.0:
		_add_quad(st_col, a_c_top, a_base, b_c_top, b_base, v0, v1, a_r, b_r)
	else:
		_add_quad(st_col, a_base, a_c_top, b_base, b_c_top, v0, v1, -a_r, -b_r)

	for rail_h_v in [0.72, 1.42]:
		var rail_h: float = float(rail_h_v)
		var rh := 0.22
		var rt := 0.18
		var a0: Vector3 = a_base + a_u * (rail_h - rh * 0.5)
		var a1: Vector3 = a_base + a_u * (rail_h + rh * 0.5)
		var b0: Vector3 = b_base + b_u * (rail_h - rh * 0.5)
		var b1: Vector3 = b_base + b_u * (rail_h + rh * 0.5)
		var a1_o: Vector3 = a1 + a_r * (side * rt)
		var b1_o: Vector3 = b1 + b_r * (side * rt)
		var a0_o: Vector3 = a0 + a_r * (side * rt)
		var b0_o: Vector3 = b0 + b_r * (side * rt)
		if side < 0.0:
			_add_quad(st_vis, a1, a0, b1, b0, v0, v1, a_r, b_r)
			_add_quad(st_vis, a1_o, a1, b1_o, b1, v0, v1, a_u, b_u)
			_add_quad(st_vis, a0_o, a1_o, b0_o, b1_o, v0, v1, -a_r, -b_r)
		else:
			_add_quad(st_vis, a0, a1, b0, b1, v0, v1, -a_r, -b_r)
			_add_quad(st_vis, a1, a1_o, b1, b1_o, v0, v1, a_u, b_u)
			_add_quad(st_vis, a1_o, a0_o, b1_o, b0_o, v0, v1, a_r, b_r)

	if add_post:
		var fwd_dir := (b_base - a_base).normalized()
		var pw := 0.19
		var ph := 1.85
		var p_c := a_base + a_r * (side * 0.14)
		var p00 := p_c - a_r * pw - fwd_dir * pw - a_u * 0.25
		var p10 := p_c + a_r * pw - fwd_dir * pw - a_u * 0.25
		var p11 := p_c + a_r * pw + fwd_dir * pw - a_u * 0.25
		var p01 := p_c - a_r * pw + fwd_dir * pw - a_u * 0.25
		var t00 := p00 + a_u * ph
		var t10 := p10 + a_u * ph
		var t11 := p11 + a_u * ph
		var t01 := p01 + a_u * ph
		_add_quad(st_vis, p00, p10, t00, t10, 0.0, 0.5, -fwd_dir, -fwd_dir)
		_add_quad(st_vis, p10, p11, t10, t11, 0.0, 0.5, a_r, a_r)
		_add_quad(st_vis, p11, p01, t11, t01, 0.0, 0.5, fwd_dir, fwd_dir)
		_add_quad(st_vis, p01, p00, t01, t00, 0.0, 0.5, -a_r, -a_r)
		_add_quad(st_vis, t00, t10, t01, t11, 0.0, 0.25, a_u, a_u)

func _add_halfpipe_strip(st: SurfaceTool, a: Dictionary, b: Dictionary, side: float, v0: float, v1: float) -> void:
	var steps := 5
	var radius := 10.5
	var max_angle := deg_to_rad(46.0)
	for k in range(steps):
		var ang0 := float(k) / float(steps) * max_angle
		var ang1 := float(k + 1) / float(steps) * max_angle
		var lat0 := sin(ang0) * radius
		var h0 := (1.0 - cos(ang0)) * radius
		var lat1 := sin(ang1) * radius
		var h1 := (1.0 - cos(ang1)) * radius

		var a0: Vector3 = a["pos"] + a["right"] * (side * (float(a["half_width"]) + lat0)) + a["up"] * h0
		var a1: Vector3 = a["pos"] + a["right"] * (side * (float(a["half_width"]) + lat1)) + a["up"] * h1
		var b0: Vector3 = b["pos"] + b["right"] * (side * (float(b["half_width"]) + lat0)) + b["up"] * h0
		var b1: Vector3 = b["pos"] + b["right"] * (side * (float(b["half_width"]) + lat1)) + b["up"] * h1

		var na: Vector3 = (a["up"] * cos((ang0 + ang1) * 0.5) - a["right"] * side * sin((ang0 + ang1) * 0.5)).normalized()
		var nb: Vector3 = (b["up"] * cos((ang0 + ang1) * 0.5) - b["right"] * side * sin((ang0 + ang1) * 0.5)).normalized()
		if side < 0.0:
			_add_quad(st, a1, a0, b1, b0, v0, v1, na, nb)
		else:
			_add_quad(st, a0, a1, b0, b1, v0, v1, na, nb)

func _build_bridges_and_tunnels() -> void:
	var samples := spline.samples
	var n := samples.size()
	var pillar_mat := _make_pbr_mat(track_def["wall_tex"], 0.84)
	var tunnel_mat_default := _make_pbr_mat(track_def["wall_tex"], 0.78)
	var tunnel_mat_bio := _make_pbr_mat("wall_biolab", 0.48, 0.40)
	var tunnel_mat_space := _make_pbr_mat("wall_space", 0.40, 0.48)
	var glow_mat := StandardMaterial3D.new()
	glow_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	glow_mat.albedo_color = Color(0.20, 0.96, 0.56) if track_def["theme"] == "glacier" else (Color(0.32, 0.84, 1.0) if track_def["theme"] == "volcano" else Color(1.0, 0.76, 0.22))

	var sea_y: float = float(track_def.get("sea_level", -4.0))
	for i in range(0, n, 11):
		var s := samples[i]
		var s_pos: Vector3 = s["pos"]
		if s["bridge"] and s_pos.y > sea_y + 5.0:
			var h: float = s_pos.y - sea_y + 3.0
			for side in [-1.0, 1.0]:
				var p_pos: Vector3 = s_pos + s["right"] * (side * (float(s["half_width"]) - 1.5)) - Vector3(0.0, h * 0.5 + 1.8, 0.0)
				# NEVER place a bridge support pillar inside a lower road crossing underneath!
				var proj := spline.project_point(Vector3(p_pos.x, s_pos.y - 20.0, p_pos.z))
				if float(proj["lateral_dist"]) < float(proj["half_width"]) + 4.5 and absf(float(proj["pos"].y) - s_pos.y) > 8.0:
					continue
				var pil := MeshInstance3D.new()
				var cyl := CylinderMesh.new()
				cyl.top_radius = 1.1; cyl.bottom_radius = 1.6; cyl.height = h; cyl.radial_segments = 8
				pil.mesh = cyl
				pil.material_override = pillar_mat
				pil.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				pil.position = p_pos
				add_child(pil)

		if s["tunnel"]:
			var b_t: String = str(s.get("biome", ""))
			var tunnel_mat := tunnel_mat_bio if b_t == "bio_lab" else (tunnel_mat_space if b_t == "space_hangar" else tunnel_mat_default)
			var arch_root := Node3D.new()
			arch_root.position = s_pos
			arch_root.basis = Basis(s["right"], s["up"], -s["forward"]).orthonormalized()
			add_child(arch_root)

			var span: float = float(s["half_width"]) * 2.0 + 3.4
			var roof_h := 12.5
			var top_beam := MeshInstance3D.new()
			var tb := BoxMesh.new()
			tb.size = Vector3(span, 2.4, 7.6)
			top_beam.mesh = tb; top_beam.material_override = tunnel_mat
			top_beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			top_beam.position = Vector3(0.0, roof_h, 0.0)
			arch_root.add_child(top_beam)

			for side in [-1.0, 1.0]:
				var col := MeshInstance3D.new()
				var cb := BoxMesh.new()
				cb.size = Vector3(2.4, roof_h, 7.2)
				col.mesh = cb; col.material_override = tunnel_mat
				col.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				col.position = Vector3(side * (float(s["half_width"]) + 1.1), roof_h * 0.5, 0.0)
				arch_root.add_child(col)

				var light_gem := MeshInstance3D.new()
				var gm := BoxMesh.new()
				gm.size = Vector3(0.55, 2.4, 1.1)
				light_gem.mesh = gm; light_gem.material_override = glow_mat
				light_gem.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				light_gem.position = Vector3(side * (float(s["half_width"]) - 0.1), roof_h * 0.68, 0.0)
				arch_root.add_child(light_gem)

func _build_start_finish_arch() -> void:
	var s := spline.sample_at_t(0.0)
	var arch := Node3D.new()
	arch.position = s["pos"]
	arch.basis = Basis(s["right"], s["up"], -s["forward"]).orthonormalized()
	add_child(arch)

	var w: float = float(s["half_width"]) * 2.0
	var check_mat := _make_pbr_mat("checkerboard", 0.55)
	check_mat.uv1_scale = Vector3(6.0, 1.0, 1.0)

	var strip := MeshInstance3D.new()
	var sm := BoxMesh.new()
	sm.size = Vector3(w - 1.4, 0.05, 3.8)
	strip.mesh = sm; strip.material_override = check_mat
	strip.position = Vector3(0.0, 0.04 + float(s.get("crown", 0.0)), 0.0)
	arch.add_child(strip)

	var gantry := _inst_glb("res://assets/models/prop_start_arch.glb")
	var scale_x := clampf(float(s["half_width"]) / 13.0, 0.85, 1.25)
	if gantry:
		gantry.scale = Vector3(scale_x, 1.0, 1.0)
		arch.add_child(gantry)
	for side in [-1.0, 1.0]:
		_add_cyl_collider(arch, 2.1, 14.0, Vector3(side * 14.0 * scale_x, 0.0, 0.0), false, "heavy")
		var br := _inst_glb("res://assets/models/prop_brazier.glb")
		if br:
			var br_pos := Vector3(side * (float(s["half_width"]) + 3.4), 0.0, 0.0)
			br.position = br_pos
			arch.add_child(br)
			_add_cyl_collider(arch, 1.15, 4.5, br_pos, false, "heavy")

func _build_overroad_archways_and_turn_signs() -> void:
	var theme: String = track_def["theme"]
	var default_glb := "res://assets/models/prop_tiki_arch.glb"
	if theme == "glacier": default_glb = "res://assets/models/prop_sewer_arch.glb"
	elif theme == "volcano": default_glb = "res://assets/models/prop_space_arch.glb"

	for aw in track_def.get("archways", []):
		var t_val: float = float(aw["t"]) if aw is Dictionary else float(aw)
		var arch_glb: String = str(aw.get("glb", default_glb)) if aw is Dictionary else default_glb
		var s := spline.sample_at_t(t_val)
		var node := Node3D.new()
		node.position = s["pos"]
		node.basis = Basis(s["right"], s["up"], -s["forward"]).orthonormalized()
		var sx := clampf(float(s["half_width"]) / 13.5, 0.86, 1.24)
		var inst := _inst_glb(arch_glb)
		if inst:
			inst.scale = Vector3(sx, 1.05, 1.05)
			node.add_child(inst)
		for side in [-1.0, 1.0]:
			_add_cyl_collider(node, 2.2, 14.0, Vector3(side * 14.8 * sx, 0.0, 0.0), false, "heavy")
		add_child(node)

	for rb_t in track_def.get("rope_bridges", []):
		var s := spline.sample_at_t(float(rb_t))
		var rb := _inst_glb("res://assets/models/prop_rope_bridge.glb")
		if rb:
			rb.position = s["pos"] + Vector3(0.0, 16.2, 0.0)
			rb.basis = Basis(s["right"], Vector3.UP, -s["forward"]).orthonormalized()
			rb.rotate_y(deg_to_rad(14.0))
			rb.scale = Vector3(1.15, 1.0, 1.0)
			_disable_shadow_recursive(rb)
			add_child(rb)

	for ca_t in track_def.get("canyon_arches", []):
		var s := spline.sample_at_t(float(ca_t))
		var ca := _inst_glb("res://assets/models/prop_canyon_arch.glb")
		if ca:
			var side_shift := -44.0 if (int(float(ca_t) * 100.0) % 2 == 0) else 44.0
			var raw_p: Vector3 = s["pos"] + s["right"] * side_shift + Vector3(0.0, -4.0, 0.0)
			ca.position = _push_out_of_track_corridor(raw_p, 18.0)
			ca.rotation.y = atan2(-s["forward"].x, -s["forward"].z) + 0.35
			ca.scale = Vector3(1.15, 1.15, 1.15)
			_disable_shadow_recursive(ca)
			add_child(ca)

	var neon_palette: Array[Color] = [
		Color(0.18, 1.0, 0.34),
		Color(0.16, 0.84, 1.0),
		Color(0.86, 0.28, 1.0),
		Color(1.0, 0.44, 0.12),
		Color(1.0, 0.86, 0.16),
		Color(1.0, 0.18, 0.28),
	]
	var samples := spline.samples
	var n := samples.size()
	var last_sign_i := -24
	var placed_indices: Dictionary = {}

	for k_i in range(5):
		var s_idx := (14 + k_i * 5) % n
		var s2 := samples[s_idx]
		var side_s := -1.0 if (k_i < 3) else 1.0
		_spawn_neon_chevron(s2, side_s, neon_palette[k_i % neon_palette.size()], true)
		placed_indices[s_idx] = true

	for i in range(44, n - 8, 4):
		if i - last_sign_i < 22:
			continue
		var s := samples[i]
		if s["tunnel"] or s["bridge"]:
			continue
		var curv: float = float(s["curvature"])
		if absf(curv) > 0.075:
			last_sign_i = i
			var outer_side := -1.0 if curv > 0.0 else 1.0
			for step_idx in range(3):
				var idx2 := (i + step_idx * 4) % n
				if placed_indices.has(idx2):
					continue
				var s2 := samples[idx2]
				_spawn_neon_chevron(s2, outer_side, neon_palette[(i + step_idx) % neon_palette.size()], curv > 0.0)
				placed_indices[idx2] = true

func _spawn_neon_chevron(s2: Dictionary, outer_side: float, glow_col: Color, point_right: bool) -> void:
	var sign_node := _inst_glb("res://assets/models/prop_chevron_sign.glb")
	if sign_node == null:
		sign_node = _inst_glb("res://assets/models/prop_turn_sign.glb")
	if sign_node == null:
		return
	var offset_w := float(s2["half_width"]) + float(s2["off_l"] if outer_side < 0.0 else s2["off_r"]) + 2.3
	var wp: Vector3 = s2["pos"] + s2["right"] * (outer_side * offset_w)
	if spline.get_min_2d_track_clearance(Vector2(wp.x, wp.z), _extra_corridors) < 1.2:
		sign_node.queue_free()
		return
	sign_node.position = wp
	var look_fwd: Vector3 = -s2["forward"]
	sign_node.rotation.y = atan2(-look_fwd.x, -look_fwd.z) + outer_side * 0.28
	var sx := -1.18 if point_right else 1.18
	sign_node.scale = Vector3(sx, 1.18, 1.18)
	_tint_chevron_glow(sign_node, glow_col)
	add_child(sign_node)
	_add_cyl_collider(sign_node, 0.82, 4.2, Vector3.ZERO, false, "medium")

func _tint_chevron_glow(node: Node, col: Color) -> void:
	if node is MeshInstance3D:
		var mi := node as MeshInstance3D
		if mi.mesh:
			for si in range(mi.mesh.get_surface_count()):
				var sm := mi.get_active_material(si)
				if sm is StandardMaterial3D and sm.resource_name.begins_with("ChevronGlow"):
					var m := sm.duplicate() as StandardMaterial3D
					m.albedo_color = col
					m.emission_enabled = true
					m.emission = col
					m.emission_energy_multiplier = 1.15
					mi.set_surface_override_material(si, m)
	for c in node.get_children():
		_tint_chevron_glow(c, col)

func _build_hero_landmarks_and_waterfalls() -> void:
	for lm in track_def.get("hero_landmarks", []):
		var inst := _inst_glb(str(lm["glb"]))
		if inst:
			var sc := float(lm.get("scale", 1.0))
			var rad := float(lm.get("radius", 8.0 * sc))
			var safe_pos := _push_out_of_track_corridor(lm["pos"], rad)
			inst.position = safe_pos
			inst.rotation_degrees.y = float(lm.get("rot_y", 0.0))
			inst.scale = Vector3(sc, sc, sc)
			add_child(inst)
			_add_cyl_collider(inst, rad / maxf(0.1, sc), 14.0, Vector3.ZERO, false, "heavy")
			spawned_prop_bounds.append({"pos": safe_pos, "radius": rad})

	var wf_shader := _load_shader("res://assets/shaders/waterfall.gdshader")
	var cliff_glb := "res://assets/models/prop_mountain_tiki.glb" if track_def["theme"] == "tiki" else ("res://assets/models/prop_mountain_glacier.glb" if track_def["theme"] == "glacier" else "res://assets/models/prop_mountain_volcano.glb")
	for wf in track_def.get("waterfalls", []):
		var rot_y := float(wf.get("rot_y", 0.0))
		var w := float(wf.get("width", 20.0))
		var h := float(wf.get("height", 46.0))
		var is_lava := bool(wf.get("lava", false))
		var cliff_scale_w := w * 1.35
		var cliff_world_r := cliff_scale_w * 1.12
		var back_dir := Vector3(-sin(deg_to_rad(rot_y)), 0.0, -cos(deg_to_rad(rot_y)))
		var raw_cliff_pos: Vector3 = wf["pos"] - back_dir * (w * 0.85) - Vector3(0.0, h * 0.55, 0.0)
		var safe_cliff_pos := _push_out_of_track_corridor(raw_cliff_pos, cliff_world_r)
		var safe_wf_pos := safe_cliff_pos + back_dir * (w * 0.85) + Vector3(0.0, h * 0.55, 0.0)

		var cliff := _inst_glb(cliff_glb)
		if cliff:
			cliff.position = safe_cliff_pos
			cliff.rotation_degrees.y = rot_y + 18.0
			cliff.scale = Vector3(cliff_scale_w, h * 1.20, cliff_scale_w)
			_disable_shadow_recursive(cliff)
			add_child(cliff)
			spawned_prop_bounds.append({"pos": safe_cliff_pos, "radius": cliff_world_r})

		if wf_shader:
			var streams := 2 if bool(wf.get("multi_stream", false)) else 1
			var side_dir := Vector3(cos(deg_to_rad(rot_y)), 0.0, -sin(deg_to_rad(rot_y)))
			for st_i in range(streams):
				var mi := MeshInstance3D.new()
				var pm := PlaneMesh.new()
				pm.size = Vector2(w * (0.58 if streams == 2 else 1.0), h)
				mi.mesh = pm
				mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				var sm := ShaderMaterial.new()
				sm.shader = wf_shader
				if is_lava:
					sm.set_shader_parameter("color_deep", Color(0.88, 0.16, 0.02))
					sm.set_shader_parameter("color_foam", Color(1.0, 0.86, 0.24))
					sm.set_shader_parameter("flow_speed", 0.95)
					sm.set_shader_parameter("alpha_base", 0.95)
				else:
					sm.set_shader_parameter("color_deep", Color(0.24, 0.68, 0.88))
					sm.set_shader_parameter("color_foam", Color(0.96, 0.98, 1.0))
					sm.set_shader_parameter("flow_speed", 1.75 + float(st_i) * 0.25)
					sm.set_shader_parameter("alpha_base", 0.82)
				mi.material_override = sm
				var off_s := (float(st_i) - 0.5) * w * 0.62 if streams == 2 else 0.0
				mi.position = safe_wf_pos + side_dir * off_s
				mi.rotation_degrees = Vector3(90.0, rot_y, 0.0)
				add_child(mi)

func _build_aerial_boost_rings() -> void:
	for br in track_def.get("boost_rings", []):
		var s := spline.sample_at_t(float(br["t"]))
		var pos: Vector3 = s["pos"] + s["right"] * float(br.get("lateral", 0.0)) + s["up"] * float(br.get("height", 4.5))
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
				if body.visuals:
					body.visuals.trigger_boost_flash(body.fire_tier)
		)
		ring_node.add_child(area)
		add_child(ring_node)

func _build_turbo_pads() -> void:
	## v7.0 ZERO-SNAG TURBO PADS: Flush glowing chevron decal + Area3D trigger ONLY (NO solid StaticBody3D box!)
	var pads: Array = track_def.get("turbo_pads", [])
	var pad_shader := _load_shader("res://assets/shaders/turbo_pad.gdshader")
	for pd in pads:
		var t_val: float = float(pd["t"])
		var lat: float = float(pd.get("lateral", 0.0))
		var is_super: bool = bool(pd.get("super", false))
		var s := spline.sample_at_t(t_val)
		var crown_off := float(s.get("crown", 0.0)) * maxf(0.0, 1.0 - absf(lat) / maxf(1.0, float(s["half_width"])))
		var world_pos: Vector3 = s["pos"] + s["right"] * lat + s["up"] * (crown_off + 0.04)
		turbo_pad_positions.append({"pos": world_pos, "t": t_val, "lateral": lat, "super": is_super})

		var pad_node := Node3D.new()
		pad_node.position = world_pos
		pad_node.basis = Basis(s["right"], s["up"], -s["forward"]).orthonormalized()
		add_child(pad_node)

		var pad_w := 7.6 if is_super else 6.8
		var pad_l := 13.5 if is_super else 11.2

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

		if is_super:
			var b_mat := StandardMaterial3D.new()
			b_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			b_mat.albedo_color = Color(0.18, 0.94, 1.0)
			for side in [-1.0, 1.0]:
				var beacon := MeshInstance3D.new()
				var cyl := CylinderMesh.new()
				cyl.top_radius = 0.14; cyl.bottom_radius = 0.30; cyl.height = 3.4
				beacon.mesh = cyl; beacon.material_override = b_mat
				beacon.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				beacon.position = Vector3(side * (pad_w * 0.56), 1.7, 0.0)
				pad_node.add_child(beacon)

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

func _build_aerial_shortcuts() -> void:
	## v7.0 PURE CTR:NF JUMP-BASED PLATFORMING SHORTCUTS (ZERO Side Bridges, ZERO Bypass Lanes!):
	## - "chasm_leap": Subtle flush road-edge lip -> soar directly across open chasm -> land directly on Main Road!
	## - "stepping_island": Road-edge lip -> fly onto mid-air Floating Stepping-Stone Island (prop_floating_pad.glb) -> immediately hop again across Gap 2 onto Main Road!
	## - "crest_vault": Natural elevated parapet crest -> timed hop vaults over corner hazards straight onto Main Road!
	var shortcuts: Array = track_def.get("shortcuts", [])
	var natural_lip_mat := _make_pbr_mat(track_def["offroad_tex"], 0.88)

	for sc in shortcuts:
		var sc_id: String = str(sc["id"])
		var sc_name_en: String = str(sc["name_en"])
		var jump_type: String = str(sc.get("jump_type", "chasm_leap"))
		var s_launch := spline.sample_at_t(float(sc["launch_t"]))
		var s_target := spline.sample_at_t(float(sc["target_t"]))
		var launch_base: Vector3 = s_launch["pos"] + s_launch["right"] * float(sc["launch_lateral"])
		var target_pos: Vector3 = s_target["pos"] + s_target["right"] * float(sc["target_lateral"])
		var pitch_rad := deg_to_rad(float(sc.get("kicker_pitch_deg", 19.5)))
		var kw := float(sc.get("kicker_width", 6.4))
		var kl := float(sc.get("kicker_length", 7.5))

		# Protect aerial flight corridor so cliffs/trees NEVER intrude into the jump arc!
		for c_step in range(9):
			var p_corr := launch_base.lerp(target_pos, float(c_step) / 8.0)
			_extra_corridors.append({"xz": Vector2(p_corr.x, p_corr.z), "radius": 13.5})

		var to_target := Vector3(target_pos.x - launch_base.x, 0.0, target_pos.z - launch_base.z).normalized()
		var launch_yaw := atan2(-to_target.x, -to_target.z)

		# 1. Flush Natural Launch Lip right at Main Road Edge (Layer 1 kicker — never blocks kart!)
		var kicker_node := Node3D.new()
		kicker_node.position = launch_base
		kicker_node.rotation = Vector3(0.0, launch_yaw, 0.0)
		add_child(kicker_node)

		var ramp_h := tan(pitch_rad) * kl
		var st_k := SurfaceTool.new()
		st_k.begin(Mesh.PRIMITIVE_TRIANGLES)
		var hw := kw * 0.5
		var z_back := kl * 0.40
		var z_front := -kl * 0.60
		var p_bl := Vector3(-hw, -0.04, z_back)
		var p_br := Vector3(hw, -0.04, z_back)
		var p_fl := Vector3(-hw, ramp_h, z_front)
		var p_fr := Vector3(hw, ramp_h, z_front)
		var p_fl_b := Vector3(-hw, -3.2, z_front)
		var p_fr_b := Vector3(hw, -3.2, z_front)
		var ramp_n := Vector3(0.0, cos(pitch_rad), sin(pitch_rad)).normalized()
		_add_quad(st_k, p_bl, p_br, p_fl, p_fr, 0.0, 1.0, ramp_n, ramp_n)
		_add_quad(st_k, p_fl, p_fr, p_fl_b, p_fr_b, 0.0, 1.0, Vector3.FORWARD, Vector3.FORWARD)
		st_k.generate_normals()
		var k_mesh := st_k.commit()

		var k_mi := MeshInstance3D.new()
		k_mi.mesh = k_mesh; k_mi.material_override = natural_lip_mat
		kicker_node.add_child(k_mi)

		# Collision uses ONLY top inclined driving face (single quad, Layer 1!) so approach is 100% seamless!
		var st_kc := SurfaceTool.new()
		st_kc.begin(Mesh.PRIMITIVE_TRIANGLES)
		_add_quad(st_kc, p_bl, p_br, p_fl, p_fr, 0.0, 1.0, ramp_n, ramp_n)
		st_kc.generate_normals()
		var k_sb := StaticBody3D.new()
		k_sb.collision_layer = 1
		k_sb.set_meta("surface_type", "kicker")
		var k_cs := CollisionShape3D.new()
		k_cs.shape = st_kc.commit().create_trimesh_shape()
		k_sb.add_child(k_cs)
		kicker_node.add_child(k_sb)

		var launch_tip_world := kicker_node.to_global(Vector3(0.0, ramp_h, z_front))
		var total_chord := Vector2(launch_tip_world.x - target_pos.x, launch_tip_world.z - target_pos.z).length()
		var single_hop_gap := total_chord
		var landing_entry := target_pos
		var landing_center := target_pos

		# 2. If "stepping_island": Spawn Floating Mid-Air Stepping-Stone Pad (prop_floating_pad.glb)!
		if jump_type == "stepping_island":
			var mid_pos := launch_tip_world.lerp(target_pos, 0.5) + Vector3(0.0, 1.1, 0.0)
			var pad_root := Node3D.new()
			pad_root.position = mid_pos
			pad_root.rotation = Vector3(0.0, launch_yaw, 0.0)
			add_child(pad_root)

			var pad_vis := _inst_glb("res://assets/models/prop_floating_pad.glb")
			if pad_vis:
				pad_vis.scale = Vector3(1.32, 1.15, 1.32)
				pad_root.add_child(pad_vis)

			# Flat generous Layer-1 kicker deck on top of floating island so kart lands & immediately hops across Gap 2!
			var pad_sb := StaticBody3D.new()
			pad_sb.collision_layer = 1
			pad_sb.set_meta("surface_type", "kicker")
			var pad_cs := CollisionShape3D.new()
			var pad_cyl := CylinderShape3D.new()
			pad_cyl.radius = 7.6
			pad_cyl.height = 1.4
			pad_cs.shape = pad_cyl
			pad_cs.position = Vector3(0.0, -0.35, 0.0)
			pad_sb.add_child(pad_cs)
			pad_root.add_child(pad_sb)

			# Subtle glint of 3 Wumpa/Crystals resting right on the floating stone pad!
			for f_i in range(-1, 2):
				fruit_spawn_points.append(mid_pos + to_target * (float(f_i) * 2.6) + Vector3(0.0, 1.45, 0.0))

			# Compute clear gap of each individual hop (Road -> Floating Island edge, and Floating Island edge -> Main Road!)
			var g1 := maxf(8.0, Vector2(launch_tip_world.x - mid_pos.x, launch_tip_world.z - mid_pos.z).length() - 7.4)
			var g2 := maxf(8.0, Vector2(mid_pos.x - target_pos.x, mid_pos.z - target_pos.z).length() - 7.4)
			single_hop_gap = maxf(g1, g2)
			landing_entry = mid_pos
			landing_center = mid_pos

			# Mid-Island Shortcut Discovery Trigger!
			var mid_area := Area3D.new()
			mid_area.collision_layer = 32
			mid_area.collision_mask = 16
			mid_area.position = mid_pos + Vector3(0.0, 2.8, 0.0)
			var m_cs := CollisionShape3D.new()
			var m_sph := SphereShape3D.new()
			m_sph.radius = 8.4
			m_cs.shape = m_sph
			mid_area.add_child(m_cs)
			mid_area.body_entered.connect(func(body):
				if body is KartPhysics:
					body.notify_shortcut(sc_id, sc_name_en)
			)
			add_child(mid_area)
		else:
			# Pure open-void Chasm Leap or Crest Vault: Trigger right in mid-air / landing approach on main road!
			var air_trigger := Area3D.new()
			air_trigger.collision_layer = 32
			air_trigger.collision_mask = 16
			air_trigger.position = launch_tip_world.lerp(target_pos, 0.65) + Vector3(0.0, 2.4, 0.0)
			var a_cs := CollisionShape3D.new()
			var a_sph := SphereShape3D.new()
			a_sph.radius = 9.5
			a_cs.shape = a_sph
			air_trigger.add_child(a_cs)
			air_trigger.body_entered.connect(func(body):
				if body is KartPhysics:
					body.notify_shortcut(sc_id, sc_name_en)
			)
			add_child(air_trigger)

		shortcut_geometries.append({
			"id": sc_id,
			"name_en": sc_name_en,
			"jump_type": jump_type,
			"required_fire": int(sc.get("required_fire", 3)),
			"launch_tip": launch_tip_world,
			"launch_pitch_deg": float(sc.get("kicker_pitch_deg", 19.5)),
			"landing_entry": landing_entry,
			"landing_center": landing_center,
			"rejoin_pos": target_pos,
			"gap_horizontal": single_hop_gap,
			"total_chord": total_chord,
			"gap_delta_y": landing_entry.y - launch_tip_world.y,
			"has_side_bridge": false
		})

func _build_canyon_terrain_banks() -> void:
	## Continuous Extruded Sculpted Rocky Canyon Walls & Terrain Embankments (ONLY 1 DRAW CALL, visual-only!).
	var samples := spline.samples
	var n := samples.size()
	var theme: String = track_def["theme"]
	var sea_y: float = float(track_def.get("sea_level", -3.0))

	var st_cliff := SurfaceTool.new()
	st_cliff.begin(Mesh.PRIMITIVE_TRIANGLES)
	var has_cliff := false

	for side_idx in range(2):
		var side := -1.0 if side_idx == 0 else 1.0
		var hp_key := "halfpipe_l" if side < 0.0 else "halfpipe_r"
		var off_key := "off_l" if side < 0.0 else "off_r"

		var ring_valid: Array[bool] = []
		var ring_pts: Array[Array] = []
		ring_valid.resize(n)
		ring_pts.resize(n)

		for i in range(n):
			var s := samples[i]
			ring_valid[i] = false
			var biome: String = str(s.get("biome", ""))
			if s["bridge"] or s["tunnel"] or s[hp_key] or biome == "asteroid_nebula" or biome == "space_hangar":
				continue
			var edge_w: float = float(s["half_width"]) + float(s[off_key])
			var base_p: Vector3 = s["pos"] + s["right"] * (side * (edge_w + 2.6)) - Vector3(0.0, 0.4, 0.0)
			var verge_p: Vector3 = s["pos"] + s["right"] * (side * (edge_w + 7.2)) + Vector3(0.0, 1.6, 0.0)
			var h_wave := 19.0 + sin(float(i) * 0.19 + side * 1.4) * 7.5 + cos(float(i) * 0.41) * 4.5
			if theme == "volcano":
				h_wave *= 1.15
			var cliff_p: Vector3 = s["pos"] + s["right"] * (side * (edge_w + 16.5 + sin(float(i) * 0.27) * 2.5)) + Vector3(0.0, h_wave, 0.0)
			var plat_p: Vector3 = s["pos"] + s["right"] * (side * (edge_w + 36.0)) + Vector3(0.0, h_wave + 3.2, 0.0)
			var back_p: Vector3 = s["pos"] + s["right"] * (side * (edge_w + 52.0))
			back_p.y = sea_y - 3.0

			if spline.get_min_2d_track_clearance(Vector2(verge_p.x, verge_p.z), _extra_corridors) < 5.0:
				continue
			if spline.get_min_2d_track_clearance(Vector2(cliff_p.x, cliff_p.z), _extra_corridors) < 10.5:
				continue
			if spline.get_min_2d_track_clearance(Vector2(plat_p.x, plat_p.z), _extra_corridors) < 12.0:
				continue

			ring_valid[i] = true
			ring_pts[i] = [base_p, verge_p, cliff_p, plat_p, back_p]
			if i % 5 == 0:
				_clifftop_spots.append({
					"pos": cliff_p.lerp(plat_p, 0.35),
					"verge": verge_p,
					"side": side,
					"right": s["right"],
					"forward": s["forward"]
				})

		for i in range(n):
			var j := (i + 1) % n
			if not ring_valid[i] or not ring_valid[j]:
				continue
			has_cliff = true
			var ra: Array = ring_pts[i]
			var rb: Array = ring_pts[j]
			var v0 := float(i) * 0.32
			var v1 := float(i + 1) * 0.32
			for tier in range(4):
				var a0: Vector3 = ra[tier]
				var a1: Vector3 = ra[tier + 1]
				var b0: Vector3 = rb[tier]
				var b1: Vector3 = rb[tier + 1]
				if side < 0.0:
					_add_quad(st_cliff, a1, a0, b1, b0, v0, v1, Vector3.UP, Vector3.UP)
				else:
					_add_quad(st_cliff, a0, a1, b0, b1, v0, v1, Vector3.UP, Vector3.UP)

	if has_cliff:
		var cliff_tex := "cliff_rock_tiki" if theme == "tiki" else ("wall_glacier" if theme == "glacier" else "wall_volcano")
		var cmat := _make_pbr_mat(cliff_tex, 0.90)
		cmat.uv1_scale = Vector3(2.8, 2.4, 1.0)
		st_cliff.generate_normals()
		var c_mi := MeshInstance3D.new()
		c_mi.mesh = st_cliff.commit()
		c_mi.material_override = cmat
		c_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(c_mi)

func _build_multimesh_lush_foliage() -> void:
	## v7.0 Hardware-Instanced Living Multi-Biome Worlds + Shared Tiered Layer-2 Colliders (ZERO Prop Clipping!):
	var theme: String = track_def["theme"]
	var samples := spline.samples
	var n := samples.size()
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(track_def["id"]) + 505

	var mm_col_soft := StaticBody3D.new()
	mm_col_soft.collision_layer = 2
	mm_col_soft.set_meta("surface_type", "prop_obstacle")
	mm_col_soft.set_meta("collision_strength", "soft")
	add_child(mm_col_soft)

	var mm_col_heavy := StaticBody3D.new()
	mm_col_heavy.collision_layer = 2
	mm_col_heavy.set_meta("surface_type", "prop_obstacle")
	mm_col_heavy.set_meta("collision_strength", "heavy")
	add_child(mm_col_heavy)

	# --- BATCH 1: Close Trackside Foliage / Acid Vats / Asteroids (WITH REAL TIERED COLLISION!) ---
	var close_path := "res://assets/models/prop_jungle_bush.glb"
	var close_is_soft := true
	if theme == "glacier":
		close_path = "res://assets/models/prop_glacier_crystal.glb"
		close_is_soft = false
	elif theme == "volcano":
		close_path = "res://assets/models/prop_volcano_spire.glb"
		close_is_soft = false

	var close_mesh := _extract_glb_mesh(close_path)
	if close_mesh:
		var xforms: Array[Transform3D] = []
		for i in range(0, n, 4):
			var s := samples[i]
			var biome: String = str(s.get("biome", ""))
			if s["bridge"] or s["tunnel"] or biome == "asteroid_nebula" or biome == "space_hangar":
				continue
			for side in [-1.0, 1.0]:
				var off_w: float = float(s["off_l"] if side < 0.0 else s["off_r"])
				var dist: float = float(s["half_width"]) + off_w + rng.randf_range(2.6, 5.8)
				var p: Vector3 = s["pos"] + s["right"] * (side * dist) + Vector3(0.0, 0.15, 0.0)
				if spline.get_min_2d_track_clearance(Vector2(p.x, p.z), _extra_corridors) < 2.2:
					continue
				var sc_v := rng.randf_range(1.15, 1.85) if theme == "tiki" else rng.randf_range(0.85, 1.38)
				var b := Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(sc_v, sc_v * rng.randf_range(0.95, 1.35), sc_v))
				xforms.append(Transform3D(b, p))
				# Attach real lightweight collider so karts NEVER clip through roadside bushes/crystals/spires!
				var cs := CollisionShape3D.new()
				var cyl := CylinderShape3D.new()
				cyl.radius = 1.15 * sc_v
				cyl.height = 4.2
				cs.shape = cyl
				cs.position = p + Vector3(0.0, 2.1, 0.0)
				if close_is_soft:
					mm_col_soft.add_child(cs)
				else:
					mm_col_heavy.add_child(cs)
		_spawn_multimesh_batch(close_mesh, xforms, false)

	# --- BATCH 2: Towering Valley Canopy Trees / Pines crowning canyon cliffs ---
	var tree_path := "res://assets/models/prop_canopy_tree.glb"
	if theme == "glacier": tree_path = "res://assets/models/prop_pine_tree.glb"
	elif theme == "volcano": tree_path = "res://assets/models/prop_volcano_spire.glb"
	var tree_mesh := _extract_glb_mesh(tree_path)
	if tree_mesh:
		var xforms_t: Array[Transform3D] = []
		for spot in _clifftop_spots:
			var cp: Vector3 = spot["pos"] + Vector3(rng.randf_range(-3.0, 3.0), -0.8, rng.randf_range(-3.0, 3.0))
			if spline.get_min_2d_track_clearance(Vector2(cp.x, cp.z), _extra_corridors) < 8.5:
				continue
			var sc_t := rng.randf_range(1.30, 2.25) if theme == "tiki" else rng.randf_range(1.45, 2.35)
			var bt := Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(sc_t, sc_t * rng.randf_range(0.92, 1.24), sc_t))
			xforms_t.append(Transform3D(bt, cp))
		_spawn_multimesh_batch(tree_mesh, xforms_t, false)

	# --- BATCH 3: MULTI-BIOME LIVING ARCHITECTURE & CITY SKYLINE (1 MultiMesh per Landmark Type!) ---
	if theme == "tiki":
		# Jungle Village Ruins + Carved Runestones + Mayan Obelisks!
		_spawn_roadside_mm_ring("res://assets/models/prop_runestone.glb", samples, 14, 5.5, 9.2, 0.95, 1.48, 1.4, mm_col_heavy, rng, "")
		_spawn_roadside_mm_ring("res://assets/models/prop_pyramid_obelisk.glb", samples, 26, 8.5, 14.5, 1.0, 1.5, 1.8, mm_col_heavy, rng, "")
		_spawn_roadside_mm_ring("res://assets/models/prop_jungle_ruin.glb", samples, 32, 16.0, 28.0, 0.95, 1.35, 5.0, mm_col_heavy, rng, "")
	elif theme == "glacier":
		# Bio-Lab Glowing Acid Vats flanking Bio-Lab & Reactor zones + Pine Groves around Arctic!
		_spawn_roadside_mm_ring("res://assets/models/prop_lab_vat.glb", samples, 10, 5.5, 11.5, 1.25, 1.90, 2.2, mm_col_heavy, rng, "bio_lab")
		_spawn_roadside_mm_ring("res://assets/models/prop_lab_vat.glb", samples, 12, 8.0, 15.0, 1.45, 2.15, 2.4, mm_col_heavy, rng, "hydro_sewer")
		_spawn_roadside_mm_ring("res://assets/models/prop_pine_tree.glb", samples, 8, 9.0, 22.0, 1.25, 2.05, 1.6, mm_col_heavy, rng, "arctic_exterior")
	elif theme == "volcano":
		# Futuristic Orbital Space City Skyscrapers + Floating Asteroid Belt around Space/Nebula zones!
		var tower_mesh := _extract_glb_mesh("res://assets/models/prop_space_tower.glb")
		if tower_mesh:
			var x_tw: Array[Transform3D] = []
			for i in range(0, n, 14):
				var s := samples[i]
				var b_name: String = str(s.get("biome", ""))
				if b_name == "magma_mine":
					continue
				for side in [-1.0, 1.0]:
					var dist := float(s["half_width"]) + rng.randf_range(26.0, 68.0)
					var p: Vector3 = s["pos"] + s["right"] * (side * dist)
					p.y -= rng.randf_range(16.0, 32.0)
					if spline.get_min_2d_track_clearance(Vector2(p.x, p.z), _extra_corridors) < 16.0:
						continue
					var sc_tw := rng.randf_range(1.25, 2.35)
					var bt := Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(sc_tw, sc_tw * rng.randf_range(1.0, 1.7), sc_tw))
					x_tw.append(Transform3D(bt, p))
					spawned_prop_bounds.append({"pos": p, "radius": 6.5 * sc_tw})
			_spawn_multimesh_batch(tower_mesh, x_tw, false)

		var ast_mesh := _extract_glb_mesh("res://assets/models/prop_asteroid.glb")
		if ast_mesh:
			var x_as: Array[Transform3D] = []
			for i in range(4, n, 9):
				var s := samples[i]
				var b_name: String = str(s.get("biome", ""))
				if b_name == "magma_mine":
					continue
				for side in [-1.0, 1.0]:
					var dist := float(s["half_width"]) + rng.randf_range(18.0, 56.0)
					var p: Vector3 = s["pos"] + s["right"] * (side * dist) + Vector3(0.0, rng.randf_range(-8.0, 32.0), 0.0)
					if spline.get_min_2d_track_clearance(Vector2(p.x, p.z), _extra_corridors) < 11.0:
						continue
					var sc_a := rng.randf_range(0.9, 2.2)
					var ba := Basis(Vector3.UP, rng.randf() * TAU).rotated(Vector3.RIGHT, rng.randf() * TAU).scaled(Vector3(sc_a, sc_a, sc_a))
					x_as.append(Transform3D(ba, p))
			_spawn_multimesh_batch(ast_mesh, x_as, false)

func _spawn_roadside_mm_ring(glb_path: String, samples: Array[Dictionary], stride: int, d_min: float, d_max: float, sc_min: float, sc_max: float, col_r: float, col_body: StaticBody3D, rng: RandomNumberGenerator, biome_filter: String) -> void:
	var mesh := _extract_glb_mesh(glb_path)
	if mesh == null:
		return
	var xforms: Array[Transform3D] = []
	var n := samples.size()
	for i in range(4, n, stride):
		var s := samples[i]
		if s["bridge"] or s["tunnel"]:
			continue
		if biome_filter != "" and str(s.get("biome", "")) != biome_filter:
			continue
		var side := 1.0 if ((i / max(1, stride)) % 2 == 0) else -1.0
		var off_w: float = float(s["off_l"] if side < 0.0 else s["off_r"])
		var dist: float = float(s["half_width"]) + off_w + rng.randf_range(d_min, d_max)
		var p: Vector3 = s["pos"] + s["right"] * (side * dist) - Vector3(0.0, 0.5, 0.0)
		var sc_r := rng.randf_range(sc_min, sc_max)
		var wr := col_r * sc_r
		if spline.get_min_2d_track_clearance(Vector2(p.x, p.z), _extra_corridors) < wr + 3.2:
			continue
		var look_y := atan2(-s["right"].x * side, -s["right"].z * side) + rng.randf_range(-0.35, 0.35)
		var br := Basis(Vector3.UP, look_y).scaled(Vector3(sc_r, sc_r * rng.randf_range(0.95, 1.25), sc_r))
		xforms.append(Transform3D(br, p))
		spawned_prop_bounds.append({"pos": p, "radius": wr})
		# Add real Layer-2 collider for close roadside props!
		if dist < float(s["half_width"]) + off_w + 18.0:
			var cs := CollisionShape3D.new()
			var cyl := CylinderShape3D.new()
			cyl.radius = wr
			cyl.height = 8.0
			cs.shape = cyl
			cs.position = p + Vector3(0.0, 4.0, 0.0)
			col_body.add_child(cs)
	_spawn_multimesh_batch(mesh, xforms, false)

func _spawn_multimesh_batch(mesh: Mesh, xforms: Array[Transform3D], cast_shadows: bool = false) -> void:
	if xforms.is_empty():
		return
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = xforms.size()
	for idx in range(xforms.size()):
		mm.set_instance_transform(idx, xforms[idx])
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	if not cast_shadows:
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mmi)

func _build_scenery_props() -> void:
	## Hero Trackside Palms/Statues/Braziers + Mid-Ground Sculpted Rocky Cliffs (Strictly 2D-cleared + Heavy Colliders!)
	var samples := spline.samples
	var n := samples.size()
	var theme: String = track_def["theme"]
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(track_def["id"]) + 42
	var sea_y: float = float(track_def.get("sea_level", -3.0))

	for i in range(0, n, 14):
		var s := samples[i]
		if s["tunnel"] or s["bridge"]:
			continue
		var biome: String = str(s.get("biome", ""))
		if biome == "asteroid_nebula" or biome == "space_hangar":
			continue
		for side in [-1.0, 1.0]:
			if (side < 0.0 and float(s["wall_l"]) < 0.25) or (side > 0.0 and float(s["wall_r"]) < 0.25):
				continue
			var margin: float = float(s["half_width"]) + float(s["off_l"] if side < 0.0 else s["off_r"]) + rng.randf_range(7.5, 24.0)
			var p: Vector3 = s["pos"] + s["right"] * (side * margin)
			p.y -= rng.randf_range(0.0, 1.4)

			var glb_path := ""
			var sc_f := rng.randf_range(0.95, 1.48)
			var col_rad := 1.4
			var col_h := 7.5
			match theme:
				"tiki":
					var r := rng.randf()
					if r < 0.65:
						glb_path = "res://assets/models/prop_palm_tree.glb"; col_rad = 0.95
					elif r < 0.88:
						glb_path = "res://assets/models/prop_tiki_statue.glb"; col_rad = 1.65
					else:
						glb_path = "res://assets/models/prop_brazier.glb"; col_rad = 1.2
				"glacier":
					if biome == "bio_lab" or biome == "reactor_overpass":
						glb_path = "res://assets/models/prop_lab_vat.glb"; col_rad = 2.0; sc_f = rng.randf_range(1.2, 1.7)
					elif rng.randf() < 0.65:
						glb_path = "res://assets/models/prop_pine_tree.glb"; col_rad = 1.35
					else:
						glb_path = "res://assets/models/prop_glacier_crystal.glb"; col_rad = 1.85
				"volcano":
					if rng.randf() < 0.68:
						glb_path = "res://assets/models/prop_volcano_spire.glb"; sc_f = rng.randf_range(1.05, 1.75); col_rad = 2.4
					else:
						glb_path = "res://assets/models/prop_brazier.glb"; col_rad = 1.2

			var world_rad := col_rad * sc_f
			if spline.get_min_2d_track_clearance(Vector2(p.x, p.z), _extra_corridors) < world_rad + 4.8:
				continue

			var inst := _inst_glb(glb_path)
			if inst:
				inst.position = p
				inst.rotation.y = rng.randf_range(0.0, TAU)
				inst.scale = Vector3(sc_f, sc_f, sc_f)
				add_child(inst)
				_add_cyl_collider(inst, col_rad, col_h, Vector3.ZERO, false, "heavy")
				spawned_prop_bounds.append({"pos": p, "radius": world_rad})

	# Layer 2: Mid-Ground Sculpted Rocky Cliffs (Batched MultiMesh = 1 draw call!)
	var cliff_glb := "res://assets/models/prop_mountain_tiki.glb"
	if theme == "glacier": cliff_glb = "res://assets/models/prop_mountain_glacier.glb"
	elif theme == "volcano": cliff_glb = "res://assets/models/prop_mountain_volcano.glb"
	var cliff_mesh := _extract_glb_mesh(cliff_glb)
	if cliff_mesh:
		var cxforms: Array[Transform3D] = []
		for i in range(0, n, 26):
			var s := samples[i]
			for side in [-1.0, 1.0]:
				var cw := rng.randf_range(22.0, 36.0)
				var ch := rng.randf_range(34.0, 72.0)
				var sz_mult := rng.randf_range(0.88, 1.12)
				var actual_cliff_r := cw * maxf(1.0, sz_mult) * 1.15
				var dist := float(s["half_width"]) + actual_cliff_r + rng.randf_range(26.0, 62.0)
				var p: Vector3 = s["pos"] + s["right"] * (side * dist)
				p.y = sea_y - 3.0
				if spline.get_min_2d_track_clearance(Vector2(p.x, p.z), _extra_corridors) < actual_cliff_r + 11.0:
					continue
				var b := Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(cw, ch, cw * sz_mult))
				cxforms.append(Transform3D(b, p))
				spawned_prop_bounds.append({"pos": p, "radius": actual_cliff_r})
		_spawn_multimesh_batch(cliff_mesh, cxforms, false)

func _compute_pickups() -> void:
	for row_t in track_def.get("crate_rows", []):
		var s := spline.sample_at_t(float(row_t))
		var span: float = minf(float(s["half_width"]) * 1.4, 15.0)
		for k in range(4):
			var frac := -1.0 + 2.0 * float(k) / 3.0
			crate_spawn_points.append(s["pos"] + s["right"] * (frac * span * 0.5) + s["up"] * (1.25 + float(s.get("crown", 0.0))))

	for tr in track_def.get("fruit_trails", []):
		var count: int = int(tr["count"])
		for k in range(count):
			var t_val := lerpf(float(tr["t0"]), float(tr["t1"]), float(k) / float(max(1, count - 1)))
			var s := spline.sample_at_t(t_val)
			fruit_spawn_points.append(s["pos"] + s["right"] * float(tr["lat"]) + s["up"] * (1.20 + float(s.get("crown", 0.0))))

func _add_quad(st: SurfaceTool, a0: Vector3, a1: Vector3, b0: Vector3, b1: Vector3, v0: float, v1: float, na: Vector3, nb: Vector3) -> void:
	_add_quad_u(st, a0, a1, b0, b1, 0.0, 1.0, v0, v1, na, nb)

func _add_quad_u(st: SurfaceTool, a0: Vector3, a1: Vector3, b0: Vector3, b1: Vector3, u0: float, u1: float, v0: float, v1: float, na: Vector3, nb: Vector3) -> void:
	st.set_normal(na); st.set_uv(Vector2(u0, v0)); st.add_vertex(a0)
	st.set_normal(nb); st.set_uv(Vector2(u0, v1)); st.add_vertex(b0)
	st.set_normal(nb); st.set_uv(Vector2(u1, v1)); st.add_vertex(b1)
	st.set_normal(na); st.set_uv(Vector2(u0, v0)); st.add_vertex(a0)
	st.set_normal(nb); st.set_uv(Vector2(u1, v1)); st.add_vertex(b1)
	st.set_normal(na); st.set_uv(Vector2(u1, v0)); st.add_vertex(a1)

func _commit_visual_only(st: SurfaceTool, mat: Material) -> void:
	st.generate_normals()
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = mat
	add_child(mi)

func _commit_surface(st: SurfaceTool, surf_type: String, col_layer: int, mat: Material) -> void:
	st.generate_normals()
	var mesh := st.commit()
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	add_child(mi)

	var sb := StaticBody3D.new()
	sb.collision_layer = col_layer
	sb.set_meta("surface_type", surf_type)
	var cs := CollisionShape3D.new()
	cs.shape = mesh.create_trimesh_shape()
	sb.add_child(cs)
	add_child(sb)

func _commit_surface_split_col(st_vis: SurfaceTool, st_col: SurfaceTool, surf_type: String, col_layer: int, mat: Material) -> void:
	st_vis.generate_normals()
	var mi := MeshInstance3D.new()
	mi.mesh = st_vis.commit()
	mi.material_override = mat
	add_child(mi)

	st_col.generate_normals()
	var sb := StaticBody3D.new()
	sb.collision_layer = col_layer
	sb.set_meta("surface_type", surf_type)
	var cs := CollisionShape3D.new()
	cs.shape = st_col.commit().create_trimesh_shape()
	sb.add_child(cs)
	add_child(sb)

static func _load_png_tex(path: String) -> Texture2D:
	if _png_tex_cache.has(path):
		return _png_tex_cache[path]
	if ResourceLoader.exists(path):
		var t = load(path)
		if t is Texture2D:
			_png_tex_cache[path] = t
			return t
	_png_tex_cache[path] = null
	return null

func _make_pbr_mat(tex_name: String, rough: float = 0.84, metal: float = 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	var alb_png := _load_png_tex("res://assets/textures/%s_albedo.png" % tex_name)
	if alb_png != null:
		m.albedo_texture = alb_png
		var nrm_png := _load_png_tex("res://assets/textures/%s_normal.png" % tex_name)
		if nrm_png != null:
			m.normal_enabled = true
			m.normal_texture = nrm_png
			m.normal_scale = 1.35
		var rgh_png := _load_png_tex("res://assets/textures/%s_rough.png" % tex_name)
		if rgh_png != null:
			m.roughness_texture = rgh_png
			m.roughness = 1.0
		else:
			m.roughness = rough
	elif ProceduralTextures:
		m.albedo_texture = ProceduralTextures.get_texture(tex_name)
		m.normal_enabled = true
		m.normal_texture = ProceduralTextures.get_normal_map(tex_name)
		m.normal_scale = 1.25
		m.roughness = rough
	else:
		m.roughness = rough
	m.metallic = metal
	if tex_name != "ice_surface":
		m.specular_mode = BaseMaterial3D.SPECULAR_SCHLICK_GGX
		m.metallic_specular = 0.24
	else:
		m.metallic_specular = 0.72
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	return m
