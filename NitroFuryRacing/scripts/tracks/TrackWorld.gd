class_name TrackWorld
extends Node3D

## v8 world around the track: real terrain heightmap (visual + HeightMapShape3D collision + per-cell surface ids),
## water / lava / acid bodies, instanced scatter (trees, rocks, ruins, buildings...) with tiered colliders near the
## road, hero landmarks (pyramid massif, waterfalls, labs, towers...) and a distant horizon ring.
## All placement data is precomputed by tools/trackgen/world.py so loading stays fast on phones.

var builder: TrackBuilder
var data: Dictionary
var mirrored := false
var mx := 1.0

# terrain grid (world space, already mirrored)
var has_terrain := false
var t_nx := 0
var t_nz := 0
var t_cell := 4.0
var t_ox := 0.0
var t_oz := 0.0
var t_h := PackedFloat32Array()
var t_surf := PackedByteArray()
var surf_names: Array = []
var waters: Array[Dictionary] = []

func setup(b: TrackBuilder, d: Dictionary, mirror: bool) -> void:
	builder = b
	data = d
	mirrored = mirror
	mx = -1.0 if mirror else 1.0

# ------------------------------------------------------------------------------------------------ helpers
func spawn_multimesh(mesh: Mesh, xforms: Array[Transform3D], cast_shadows: bool = false, mat: Material = null) -> MultiMeshInstance3D:
	if xforms.is_empty() or mesh == null:
		return null
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = xforms.size()
	for idx in range(xforms.size()):
		mm.set_instance_transform(idx, xforms[idx])
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	if mat:
		mmi.material_override = mat
	if not cast_shadows:
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mmi)
	return mmi

func _read_f32(path: String) -> PackedFloat32Array:
	if not FileAccess.file_exists(path):
		return PackedFloat32Array()
	var f := FileAccess.open(path, FileAccess.READ)
	var bytes := f.get_buffer(f.get_length())
	f.close()
	return bytes.to_float32_array()

func _read_u8(path: String) -> PackedByteArray:
	if not FileAccess.file_exists(path):
		return PackedByteArray()
	var f := FileAccess.open(path, FileAccess.READ)
	var bytes := f.get_buffer(f.get_length())
	f.close()
	return bytes

## Terrain height at world x,z (bilinear). Returns -1000 if outside / no terrain.
func ground_height(x: float, z: float) -> float:
	if not has_terrain:
		return -1000.0
	var fx := (x - t_ox) / t_cell
	var fz := (z - t_oz) / t_cell
	if fx < 0.0 or fz < 0.0 or fx >= float(t_nx - 1) or fz >= float(t_nz - 1):
		return -1000.0
	var ix := int(fx)
	var iz := int(fz)
	var ux := fx - float(ix)
	var uz := fz - float(iz)
	var h00 := t_h[iz * t_nx + ix]
	var h10 := t_h[iz * t_nx + ix + 1]
	var h01 := t_h[(iz + 1) * t_nx + ix]
	var h11 := t_h[(iz + 1) * t_nx + ix + 1]
	return lerpf(lerpf(h00, h10, ux), lerpf(h01, h11, ux), uz)

func terrain_surface_at(pos: Vector3) -> String:
	if not has_terrain or t_surf.is_empty():
		return "grass"
	var ix := clampi(int(round((pos.x - t_ox) / t_cell)), 0, t_nx - 1)
	var iz := clampi(int(round((pos.z - t_oz) / t_cell)), 0, t_nz - 1)
	var sid := int(t_surf[iz * t_nx + ix])
	if sid < surf_names.size():
		return str(surf_names[sid])
	return "grass"

## Water / lava / acid surface level under x,z (or -INF). Karts sinking below it are respawned.
func liquid_at(x: float, z: float) -> Dictionary:
	for w in waters:
		var p := Vector2(x, z)
		var c: Vector2 = w["c"]
		var hs: Vector2 = w["hs"]
		var rel := p - c
		var rot: float = w["rot"]
		var lr := rel.rotated(-rot)
		if absf(lr.x) <= hs.x and absf(lr.y) <= hs.y:
			return w
	return {}

# ------------------------------------------------------------------------------------------------ terrain + water
func build_terrain_and_water() -> void:
	var tinfo: Dictionary = data.get("terrain", {})
	if not tinfo.is_empty():
		_load_terrain(tinfo)
	if has_terrain:
		_build_terrain_mesh(tinfo)
		_build_terrain_collision()
	for wd in data.get("waters", []):
		_build_water(wd)
	if not has_terrain:
		_build_void_floor()

func _load_terrain(tinfo: Dictionary) -> void:
	var base := "res://data/tracks/"
	var h := _read_f32(base + str(tinfo["height_file"]))
	var s := _read_u8(base + str(tinfo.get("surf_file", "")))
	t_nx = int(tinfo["nx"])
	t_nz = int(tinfo["nz"])
	t_cell = float(tinfo["cell"])
	if h.size() != t_nx * t_nz:
		push_warning("terrain size mismatch")
		return
	surf_names = tinfo.get("surf_names", [])
	if mirrored:
		# flip columns so world x -> -x
		var h2 := PackedFloat32Array()
		h2.resize(h.size())
		var s2 := PackedByteArray()
		s2.resize(s.size())
		for iz in range(t_nz):
			for ix in range(t_nx):
				h2[iz * t_nx + ix] = h[iz * t_nx + (t_nx - 1 - ix)]
				if s.size() == h.size():
					s2[iz * t_nx + ix] = s[iz * t_nx + (t_nx - 1 - ix)]
		h = h2
		s = s2 if s.size() == h.size() else s
		t_ox = -(float(tinfo["ox"]) + float(t_nx - 1) * t_cell)
	else:
		t_ox = float(tinfo["ox"])
	t_oz = float(tinfo["oz"])
	t_h = h
	t_surf = s
	has_terrain = true

func _build_terrain_mesh(tinfo: Dictionary) -> void:
	var splat := _read_u8("res://data/tracks/" + str(tinfo.get("splat_file", "")))
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var cols := PackedColorArray()
	var idx := PackedInt32Array()
	verts.resize(t_nx * t_nz)
	norms.resize(t_nx * t_nz)
	cols.resize(t_nx * t_nz)
	for iz in range(t_nz):
		for ix in range(t_nx):
			var i := iz * t_nx + ix
			verts[i] = Vector3(t_ox + float(ix) * t_cell, t_h[i], t_oz + float(iz) * t_cell)
			var hl := t_h[iz * t_nx + maxi(ix - 1, 0)]
			var hr := t_h[iz * t_nx + mini(ix + 1, t_nx - 1)]
			var hd := t_h[maxi(iz - 1, 0) * t_nx + ix]
			var hu := t_h[mini(iz + 1, t_nz - 1) * t_nx + ix]
			norms[i] = Vector3(hl - hr, 2.0 * t_cell, hd - hu).normalized()
			if splat.size() == t_nx * t_nz * 4:
				var sx := ix if not mirrored else (t_nx - 1 - ix)
				var j := (iz * t_nx + sx) * 4
				cols[i] = Color(splat[j] / 255.0, splat[j + 1] / 255.0, splat[j + 2] / 255.0, splat[j + 3] / 255.0)
			else:
				cols[i] = Color(1, 0, 0, 0)
	# chunked index buffers (64x64 cells) for frustum culling; skip fully "hole" cells (h < -400)
	var CH := 48
	var shader := load("res://assets/shaders/terrain_splat.gdshader")
	var mat := ShaderMaterial.new()
	mat.shader = shader
	var texs: Array = tinfo.get("textures", ["terrain_grass", "cliff_rock_tiki", "terrain_sand", "road_dirt"])
	var keys := ["tex_r", "tex_g", "tex_b", "tex_a"]
	for k in range(4):
		var tn: String = str(texs[k]) if k < texs.size() else "terrain_grass"
		var tex := TrackMats.load_tex("res://assets/textures/%s_albedo.png" % tn)
		if tex:
			mat.set_shader_parameter(keys[k], tex)
	var tints: Array = tinfo.get("tints", [])
	var tkeys := ["tint_r", "tint_g", "tint_b", "tint_a"]
	for k in range(mini(4, tints.size())):
		mat.set_shader_parameter(tkeys[k], Color.html(str(tints[k])))
	for cz in range(0, t_nz - 1, CH):
		for cx in range(0, t_nx - 1, CH):
			idx = PackedInt32Array()
			for iz in range(cz, mini(cz + CH, t_nz - 1)):
				for ix in range(cx, mini(cx + CH, t_nx - 1)):
					var i0 := iz * t_nx + ix
					var i1 := i0 + 1
					var i2 := i0 + t_nx
					var i3 := i2 + 1
					if t_h[i0] < -400.0 and t_h[i1] < -400.0 and t_h[i2] < -400.0 and t_h[i3] < -400.0:
						continue
					idx.append_array(PackedInt32Array([i0, i1, i3, i0, i3, i2]))
			if idx.is_empty():
				continue
			var arr := []
			arr.resize(Mesh.ARRAY_MAX)
			arr[Mesh.ARRAY_VERTEX] = verts
			arr[Mesh.ARRAY_NORMAL] = norms
			arr[Mesh.ARRAY_COLOR] = cols
			arr[Mesh.ARRAY_INDEX] = idx
			var am := ArrayMesh.new()
			am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
			var mi := MeshInstance3D.new()
			mi.mesh = am
			mi.material_override = mat
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			mi.name = "Terrain_%d_%d" % [cx, cz]
			add_child(mi)

func _build_terrain_collision() -> void:
	var sb := StaticBody3D.new()
	sb.collision_layer = TrackBuilder.OFFROAD_LAYER
	sb.collision_mask = 0
	sb.set_meta("surface_type", "terrain")
	sb.name = "TerrainCollider"
	var cs := CollisionShape3D.new()
	var hm := HeightMapShape3D.new()
	hm.map_width = t_nx
	hm.map_depth = t_nz
	var scaled := PackedFloat32Array()
	scaled.resize(t_h.size())
	for i in range(t_h.size()):
		scaled[i] = t_h[i] / t_cell
	hm.map_data = scaled
	cs.shape = hm
	# HeightMapShape3D is centred on its origin with 1 unit spacing -> uniform scale by the cell size
	cs.scale = Vector3(t_cell, t_cell, t_cell)
	cs.position = Vector3(t_ox + float(t_nx - 1) * t_cell * 0.5, 0.0, t_oz + float(t_nz - 1) * t_cell * 0.5)
	sb.add_child(cs)
	add_child(sb)

func _build_water(wd: Dictionary) -> void:
	var c := Vector2(float(wd["x"]) * mx, float(wd["z"]))
	var hs := Vector2(float(wd["sx"]) * 0.5, float(wd["sz"]) * 0.5)
	var rot := float(wd.get("rot", 0.0)) * mx
	var level := float(wd["y"])
	var kind := str(wd.get("kind", "water"))
	waters.append({"c": c, "hs": hs, "rot": rot, "y": level, "kind": kind, "deep": float(wd.get("deep", 1.6))})
	var mi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(hs.x * 2.0, hs.y * 2.0)
	pm.subdivide_width = int(clampf(hs.x / 8.0, 2, 40))
	pm.subdivide_depth = int(clampf(hs.y / 8.0, 2, 40))
	mi.mesh = pm
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var sm := ShaderMaterial.new()
	if kind == "lava":
		sm.shader = TrackBuilder._load_shader("res://assets/shaders/lava_sea.gdshader")
	else:
		sm.shader = TrackBuilder._load_shader("res://assets/shaders/water_ocean.gdshader")
		if kind == "acid":
			sm.set_shader_parameter("shallow_color", Color(0.45, 1.0, 0.25))
			sm.set_shader_parameter("deep_color", Color(0.10, 0.45, 0.10))
			sm.set_shader_parameter("foam_color", Color(0.85, 1.0, 0.7))
		elif kind == "ice_water":
			sm.set_shader_parameter("shallow_color", Color(0.45, 0.80, 0.92))
			sm.set_shader_parameter("deep_color", Color(0.06, 0.24, 0.42))
		elif wd.has("shallow"):
			sm.set_shader_parameter("shallow_color", Color.html(str(wd["shallow"])))
	mi.material_override = sm
	mi.position = Vector3(c.x, level, c.y)
	mi.rotation.y = rot
	add_child(mi)

func _build_void_floor() -> void:
	pass

# ------------------------------------------------------------------------------------------------ scatter
func build_scatter() -> void:
	## Instanced props; colliders are bucketed into 80 m chunk bodies that enter the tree only once fully built
	## (adding thousands of shapes to one live body is O(n^2) in the physics server).
	var scat: Dictionary = data.get("scatter", {})
	var catalog := TrackProps.catalog()
	var bodies: Dictionary = {}
	for kind in scat.keys():
		var entry: Dictionary = catalog.get(kind, {})
		if entry.is_empty():
			continue
		var mesh: Mesh = TrackProps.mesh_for(kind, entry)
		if mesh == null:
			continue
		var xforms: Array[Transform3D] = []
		var col_r := float(entry.get("col_r", 0.0))
		var col_h := float(entry.get("col_h", 6.0))
		var strength := str(entry.get("strength", "heavy"))
		for it in scat[kind]:
			var p := Vector3(float(it[0]) * mx, float(it[1]), float(it[2]))
			var rot := float(it[3]) * mx
			var sc := float(it[4])
			var sy := float(it[5]) if it.size() > 5 else sc
			var b := Basis(Vector3.UP, rot).scaled(Vector3(sc, sy, sc))
			xforms.append(Transform3D(b, p))
			if col_r > 0.0 and (it.size() <= 6 or int(it[6]) == 1):
				var key := "%s|%d|%d" % [strength, int(floor(p.x / 80.0)), int(floor(p.z / 80.0))]
				if not bodies.has(key):
					var sb := StaticBody3D.new()
					sb.collision_layer = TrackBuilder.WALL_LAYER
					sb.collision_mask = 0
					sb.set_meta("surface_type", "prop_obstacle")
					sb.set_meta("collision_strength", strength)
					bodies[key] = sb
				var cs := CollisionShape3D.new()
				var cyl := CylinderShape3D.new()
				cyl.radius = col_r * sc
				cyl.height = col_h * sy
				cs.shape = cyl
				cs.position = p + Vector3(0.0, col_h * sy * 0.5, 0.0)
				(bodies[key] as StaticBody3D).add_child(cs)
				builder.spawned_prop_bounds.append({"pos": p, "radius": col_r * sc})
		spawn_multimesh(mesh, xforms, bool(entry.get("shadow", false)))
	for key in bodies.keys():
		add_child(bodies[key])

# ------------------------------------------------------------------------------------------------ landmarks
func build_landmarks() -> void:
	for lm in data.get("landmarks_world", []):
		TrackProps.build_landmark(self, lm, mx)

# ------------------------------------------------------------------------------------------------ horizon
func build_horizon() -> void:
	var hz: Dictionary = data.get("horizon", {})
	if hz.is_empty():
		return
	var glb := str(hz.get("glb", "res://assets/models/prop_mountain_tiki.glb"))
	var mesh := TrackBuilder._extract_glb_mesh(glb)
	if mesh == null:
		return
	var xforms: Array[Transform3D] = []
	for m in hz.get("items", []):
		var p := Vector3(float(m[0]) * mx, float(m[1]), float(m[2]))
		var b := Basis(Vector3.UP, float(m[3])).scaled(Vector3(float(m[4]), float(m[5]), float(m[4]) * float(m[6])))
		xforms.append(Transform3D(b, p))
	spawn_multimesh(mesh, xforms, false)
