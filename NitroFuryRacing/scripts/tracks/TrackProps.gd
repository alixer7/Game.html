class_name TrackProps
extends RefCounted

## v8 prop catalog + procedural meshes (huts, stalls, pillars, stalagmites, rocks, buildings, pipes, lamps...)
## and landmark builders (voxel massifs such as the stepped pyramid, gates, waterfalls, generic GLB set pieces).
## Collision strength tiers: soft (bushes, snow drifts) / medium (wood, crates, signs) / heavy (stone, steel, trees).

const M := "res://assets/models/"

static var _mesh_cache: Dictionary = {}

static func catalog() -> Dictionary:
	return {
		# ---------------- jungle / temple ----------------
		"canopy_tree": {"glb": M + "prop_canopy_tree.glb", "col_r": 0.9, "col_h": 8.0, "strength": "heavy", "shadow": true},
		"palm": {"glb": M + "prop_palm_tree.glb", "col_r": 0.6, "col_h": 8.0, "strength": "heavy", "shadow": true},
		"bush": {"glb": M + "prop_jungle_bush.glb", "col_r": 1.8, "col_h": 1.6, "strength": "soft"},
		"boulder": {"glb": M + "prop_boulder.glb", "col_r": 2.0, "col_h": 3.5, "strength": "heavy"},
		"ruin": {"glb": M + "prop_jungle_ruin.glb", "col_r": 4.6, "col_h": 9.0, "strength": "heavy"},
		"runestone": {"glb": M + "prop_runestone.glb", "col_r": 2.0, "col_h": 10.0, "strength": "heavy"},
		"tiki_statue": {"glb": M + "prop_tiki_statue.glb", "col_r": 1.3, "col_h": 7.0, "strength": "heavy"},
		"brazier": {"glb": M + "prop_brazier.glb", "col_r": 1.0, "col_h": 5.0, "strength": "heavy"},
		"obelisk": {"glb": M + "prop_pyramid_obelisk.glb", "col_r": 3.0, "col_h": 14.0, "strength": "heavy"},
		"hut": {"proc": "hut", "col_r": 3.6, "col_h": 6.0, "strength": "heavy", "shadow": true},
		"fern": {"proc": "fern"},
		"rock": {"proc": "rock", "col_r": 1.6, "col_h": 2.5, "strength": "heavy"},
		"log": {"proc": "log", "col_r": 0.0},
		"reeds": {"proc": "reeds"},
		"pirate_ship": {"glb": M + "prop_pirate_ship.glb", "col_r": 0.0},
		# ---------------- arctic / lab ----------------
		"pine": {"glb": M + "prop_pine_tree.glb", "col_r": 0.7, "col_h": 8.0, "strength": "heavy", "shadow": true},
		"crystal": {"glb": M + "prop_glacier_crystal.glb", "col_r": 1.3, "col_h": 5.0, "strength": "heavy"},
		"lodge": {"glb": M + "prop_alpine_lodge.glb", "col_r": 6.0, "col_h": 12.0, "strength": "heavy", "shadow": true},
		"snow_rock": {"proc": "snow_rock", "col_r": 1.8, "col_h": 2.5, "strength": "heavy"},
		"snowdrift": {"proc": "snowdrift", "col_r": 1.8, "col_h": 1.2, "strength": "soft"},
		"vat": {"glb": M + "prop_lab_vat.glb", "col_r": 3.8, "col_h": 10.0, "strength": "heavy"},
		"tank": {"proc": "tank", "col_r": 2.6, "col_h": 9.0, "strength": "heavy", "shadow": true},
		"pipes": {"proc": "pipes", "col_r": 0.0},
		"crate_stack": {"proc": "crate_stack", "col_r": 1.6, "col_h": 3.0, "strength": "medium"},
		"barrel": {"glb": M + "prop_sewer_barrel.glb", "col_r": 1.9, "col_h": 4.0, "strength": "medium"},
		"lab_block": {"proc": "lab_block", "col_r": 0.0},
		# ---------------- city / space / volcano ----------------
		"space_tower": {"glb": M + "prop_space_tower.glb", "col_r": 7.0, "col_h": 60.0, "strength": "heavy"},
		"building": {"proc": "building", "col_r": 0.0},
		"lamp": {"proc": "lamp", "col_r": 0.35, "col_h": 8.0, "strength": "medium"},
		"asteroid": {"glb": M + "prop_asteroid.glb", "col_r": 0.0},
		"spire": {"glb": M + "prop_volcano_spire.glb", "col_r": 1.8, "col_h": 9.0, "strength": "heavy"},
		"mine_cart_static": {"glb": M + "prop_mine_cart.glb", "col_r": 1.6, "col_h": 3.0, "strength": "heavy"},
		"neon_sign": {"proc": "neon_sign", "col_r": 0.0},
		"hover_pad": {"proc": "hover_pad", "col_r": 0.0},
	}

static func mesh_for(kind: String, entry: Dictionary) -> Mesh:
	if _mesh_cache.has(kind):
		return _mesh_cache[kind]
	var m: Mesh = null
	if entry.has("glb"):
		m = TrackBuilder._extract_glb_mesh(str(entry["glb"]))
	elif entry.has("proc"):
		m = proc_mesh(str(entry["proc"]))
	_mesh_cache[kind] = m
	return m

# ------------------------------------------------------------------------------------------------ mesh combiner
## parts: Array of [PrimitiveMesh or ArrayMesh, Transform3D, Material]. Same material -> same surface.
static func combine(parts: Array) -> ArrayMesh:
	var by_mat: Dictionary = {}
	for p in parts:
		var mesh: Mesh = p[0]
		var xf: Transform3D = p[1]
		var mat: Material = p[2]
		var key := mat.get_instance_id()
		if not by_mat.has(key):
			var st := SurfaceTool.new()
			st.begin(Mesh.PRIMITIVE_TRIANGLES)
			by_mat[key] = {"st": st, "mat": mat}
		var stt: SurfaceTool = by_mat[key]["st"]
		for si in range(mesh.get_surface_count()):
			stt.append_from(mesh, si, xf)
	var out := ArrayMesh.new()
	for key in by_mat.keys():
		var st2: SurfaceTool = by_mat[key]["st"]
		st2.generate_tangents()
		st2.commit(out)
		out.surface_set_material(out.get_surface_count() - 1, by_mat[key]["mat"])
	return out

static func _box(sx: float, sy: float, sz: float) -> BoxMesh:
	var b := BoxMesh.new()
	b.size = Vector3(sx, sy, sz)
	return b

static func _cyl(rt: float, rb: float, h: float, seg: int = 10) -> CylinderMesh:
	var c := CylinderMesh.new()
	c.top_radius = rt
	c.bottom_radius = rb
	c.height = h
	c.radial_segments = seg
	c.rings = 1
	return c

static func _sphere(r: float, seg: int = 10, rings: int = 6) -> SphereMesh:
	var s := SphereMesh.new()
	s.radius = r
	s.height = r * 2.0
	s.radial_segments = seg
	s.rings = rings
	return s

static func _rock_mesh(seed_v: int, rad: float, squash: float, col: Color, tex: String = "cliff_rock_tiki") -> ArrayMesh:
	var sm := _sphere(rad, 9, 6)
	var arr := sm.get_mesh_arrays()
	var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_v
	var noise := FastNoiseLite.new()
	noise.seed = seed_v
	noise.frequency = 0.9
	for i in range(verts.size()):
		var v := verts[i]
		var dn := noise.get_noise_3d(v.x, v.y, v.z)
		v = v * (1.0 + dn * 0.35)
		v.y *= squash
		if v.y < -rad * 0.3 * squash:
			v.y = -rad * 0.3 * squash
		verts[i] = v
	arr[Mesh.ARRAY_VERTEX] = verts
	var am := ArrayMesh.new()
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	var st := SurfaceTool.new()
	st.create_from(am, 0)
	st.generate_normals()
	st.generate_tangents()
	var out := st.commit()
	var mat := TrackMats.pbr(tex, col, 0.92)
	mat.uv1_scale = Vector3(1.5, 1.5, 1.0)
	out.surface_set_material(0, mat)
	return out

static func proc_mesh(kind: String) -> Mesh:
	var wood := TrackMats.wall_mat("wood")
	match kind:
		"hut":
			var straw := TrackMats.flat(Color(0.78, 0.62, 0.32), 0.95)
			var parts := []
			for sx in [-2.6, 2.6]:
				for sz in [-2.6, 2.6]:
					parts.append([_cyl(0.25, 0.3, 3.0, 6), Transform3D(Basis(), Vector3(sx, 1.5, sz)), wood])
			parts.append([_box(6.4, 0.4, 6.4), Transform3D(Basis(), Vector3(0, 3.1, 0)), wood])
			parts.append([_box(5.6, 3.0, 5.6), Transform3D(Basis(), Vector3(0, 4.8, 0)), TrackMats.wall_mat("hut")])
			var roof := _cyl(0.2, 5.6, 3.4, 4)
			parts.append([roof, Transform3D(Basis(Vector3.UP, PI / 4.0), Vector3(0, 8.0, 0)), straw])
			parts.append([_box(1.4, 2.0, 0.2), Transform3D(Basis(), Vector3(0, 4.3, 2.85)), TrackMats.flat(Color(0.18, 0.12, 0.08))])
			return combine(parts)
		"fern":
			var leaf := TrackMats.flat(Color(0.20, 0.46, 0.16), 0.9)
			var leaf2 := TrackMats.flat(Color(0.32, 0.56, 0.18), 0.9)
			var parts2 := []
			for k in range(5):
				var ang := float(k) / 5.0 * TAU
				var b := Basis(Vector3.UP, ang) * Basis(Vector3.RIGHT, -0.7)
				parts2.append([_box(0.5, 0.06, 2.4), Transform3D(b, Vector3(sin(ang) * 0.7, 0.6, cos(ang) * 0.7)), leaf if k % 2 == 0 else leaf2])
			return combine(parts2)
		"rock":
			return _rock_mesh(7, 1.8, 0.65, Color(0.86, 0.84, 0.80))
		"snow_rock":
			return _rock_mesh(19, 1.9, 0.7, Color(0.86, 0.90, 0.98), "wall_glacier")
		"snowdrift":
			var sm := _sphere(2.2, 10, 5)
			var m := TrackMats.pbr("offroad_snow", Color(1, 1, 1), 0.85)
			return combine([[sm, Transform3D(Basis().scaled(Vector3(1.0, 0.38, 0.8)), Vector3.ZERO), m]])
		"log":
			return combine([[_cyl(0.55, 0.6, 7.0, 8), Transform3D(Basis(Vector3.FORWARD, PI / 2.0), Vector3(0, 0.5, 0)), TrackMats.pbr("mat_bark", Color(1, 1, 1), 0.9)]])
		"reeds":
			var reed := TrackMats.flat(Color(0.42, 0.52, 0.22), 0.9)
			var parts3 := []
			for k in range(7):
				var a2 := float(k) * 2.4
				parts3.append([_cyl(0.03, 0.07, 2.2, 4), Transform3D(Basis(Vector3.RIGHT, sin(a2) * 0.2), Vector3(cos(a2) * 0.6, 1.1, sin(a2) * 0.6)), reed])
			return combine(parts3)
		"tank":
			var metal := TrackMats.flat(Color(0.62, 0.66, 0.70), 0.35, 0.7)
			var band := TrackMats.flat(Color(0.95, 0.75, 0.10), 0.5, 0.2)
			var glow := TrackMats.flat(Color(0.35, 1.0, 0.45), 0.4, 0.0, 2.5)
			return combine([
				[_cyl(2.4, 2.4, 8.0, 14), Transform3D(Basis(), Vector3(0, 4.0, 0)), metal],
				[_sphere(2.4, 14, 6), Transform3D(Basis().scaled(Vector3(1, 0.4, 1)), Vector3(0, 8.0, 0)), metal],
				[_cyl(2.45, 2.45, 0.5, 14), Transform3D(Basis(), Vector3(0, 2.0, 0)), band],
				[_cyl(2.45, 2.45, 0.5, 14), Transform3D(Basis(), Vector3(0, 6.0, 0)), band],
				[_box(0.6, 4.0, 0.1), Transform3D(Basis(), Vector3(0, 4.0, 2.42)), glow],
			])
		"pipes":
			var pm := TrackMats.flat(Color(0.50, 0.55, 0.58), 0.35, 0.75)
			var pr := TrackMats.flat(Color(0.75, 0.30, 0.15), 0.5, 0.5)
			return combine([
				[_cyl(0.6, 0.6, 12.0, 10), Transform3D(Basis(Vector3.FORWARD, PI / 2.0), Vector3(0, 1.2, 0)), pm],
				[_cyl(0.45, 0.45, 12.0, 10), Transform3D(Basis(Vector3.FORWARD, PI / 2.0), Vector3(0, 2.6, 0.4)), pr],
				[_cyl(0.3, 0.3, 12.0, 8), Transform3D(Basis(Vector3.FORWARD, PI / 2.0), Vector3(0, 3.6, -0.3)), pm],
				[_box(0.4, 4.4, 0.4), Transform3D(Basis(), Vector3(-5.5, 2.2, 0)), pm],
				[_box(0.4, 4.4, 0.4), Transform3D(Basis(), Vector3(5.5, 2.2, 0)), pm],
			])
		"crate_stack":
			var cm := TrackMats.pbr("mat_crate_wood", Color(1, 1, 1), 0.9)
			return combine([
				[_box(1.6, 1.6, 1.6), Transform3D(Basis(), Vector3(-0.85, 0.8, 0)), cm],
				[_box(1.6, 1.6, 1.6), Transform3D(Basis(Vector3.UP, 0.3), Vector3(0.85, 0.8, 0.1)), cm],
				[_box(1.6, 1.6, 1.6), Transform3D(Basis(Vector3.UP, -0.2), Vector3(0.0, 2.4, 0)), cm],
			])
		"lab_block":
			var wall := TrackMats.wall_mat("lab")
			var win := TrackMats.flat(Color(0.55, 1.0, 0.7), 0.3, 0.0, 2.2)
			return combine([
				[_box(14.0, 10.0, 10.0), Transform3D(Basis(), Vector3(0, 5.0, 0)), wall],
				[_box(12.0, 0.8, 0.1), Transform3D(Basis(), Vector3(0, 6.5, 5.02)), win],
				[_box(12.0, 0.8, 0.1), Transform3D(Basis(), Vector3(0, 3.5, 5.02)), win],
				[_cyl(1.2, 1.2, 4.0, 10), Transform3D(Basis(), Vector3(4.0, 12.0, 0)), TrackMats.flat(Color(0.6, 0.62, 0.66), 0.4, 0.7)],
			])
		"building":
			var body := TrackMats.wall_mat("space")
			var lit := TrackMats.flat(Color(0.45, 0.85, 1.0), 0.3, 0.0, 2.4)
			var lit2 := TrackMats.flat(Color(1.0, 0.45, 0.85), 0.3, 0.0, 2.4)
			var parts4 := [[_box(12.0, 40.0, 12.0), Transform3D(Basis(), Vector3(0, 20.0, 0)), body],
				[_box(9.0, 8.0, 9.0), Transform3D(Basis(), Vector3(0, 44.0, 0)), body],
				[_cyl(0.2, 0.4, 8.0, 6), Transform3D(Basis(), Vector3(0, 52.0, 0)), lit2]]
			for k in range(9):
				parts4.append([_box(12.1, 0.5, 12.1), Transform3D(Basis(), Vector3(0, 4.0 + float(k) * 4.2, 0)), lit if k % 3 != 1 else lit2])
			return combine(parts4)
		"lamp":
			var pole := TrackMats.flat(Color(0.35, 0.37, 0.42), 0.4, 0.7)
			var bulb := TrackMats.flat(Color(1.0, 0.92, 0.7), 0.3, 0.0, 4.0)
			return combine([
				[_cyl(0.15, 0.22, 8.0, 6), Transform3D(Basis(), Vector3(0, 4.0, 0)), pole],
				[_box(0.2, 0.2, 2.2), Transform3D(Basis(), Vector3(0, 8.0, 1.0)), pole],
				[_box(0.6, 0.2, 0.9), Transform3D(Basis(), Vector3(0, 7.8, 2.0)), bulb],
			])
		"neon_sign":
			var frame := TrackMats.flat(Color(0.12, 0.12, 0.16), 0.5, 0.6)
			var n1 := TrackMats.flat(Color(1.0, 0.25, 0.75), 0.3, 0.0, 3.5)
			var n2 := TrackMats.flat(Color(0.25, 0.95, 1.0), 0.3, 0.0, 3.5)
			return combine([
				[_box(0.5, 12.0, 0.5), Transform3D(Basis(), Vector3(0, 6.0, 0)), frame],
				[_box(8.0, 4.0, 0.4), Transform3D(Basis(), Vector3(0, 13.0, 0)), frame],
				[_box(7.0, 0.5, 0.45), Transform3D(Basis(), Vector3(0, 14.2, 0)), n1],
				[_box(7.0, 0.5, 0.45), Transform3D(Basis(), Vector3(0, 12.0, 0)), n2],
			])
		"hover_pad":
			var hp := TrackMats.wall_mat("space")
			var rim := TrackMats.flat(Color(0.3, 0.9, 1.0), 0.3, 0.0, 3.0)
			return combine([
				[_cyl(6.0, 4.0, 2.0, 12), Transform3D(Basis(), Vector3(0, -1.0, 0)), hp],
				[_cyl(6.1, 6.1, 0.3, 12), Transform3D(Basis(), Vector3(0, 0.0, 0)), rim],
			])
	return null

# ------------------------------------------------------------------------------------------------ obstacles
static func make_obstacle(kind: String, r: float, s: Dictionary, b: TrackBuilder) -> Node3D:
	var node := Node3D.new()
	var mi := MeshInstance3D.new()
	var ceil_h: float = float(s.get("ceil", 0.0))
	match kind:
		"market_stall":
			var cloth := TrackMats.flat(Color(0.86, 0.22, 0.16), 0.9)
			var cloth2 := TrackMats.flat(Color(0.98, 0.86, 0.40), 0.9)
			var wood := TrackMats.wall_mat("wood")
			var parts := []
			for sx in [-1.6, 1.6]:
				for sz in [-1.1, 1.1]:
					parts.append([_cyl(0.1, 0.12, 2.8, 6), Transform3D(Basis(), Vector3(sx, 1.4, sz)), wood])
			parts.append([_box(3.6, 0.9, 2.6), Transform3D(Basis(), Vector3(0, 0.45, 0)), wood])
			for k in range(4):
				parts.append([_box(0.95, 0.12, 3.0), Transform3D(Basis(Vector3.RIGHT, 0.12), Vector3(-1.4 + k * 0.95, 2.9, 0)), cloth if k % 2 == 0 else cloth2])
			parts.append([_sphere(0.35, 8, 4), Transform3D(Basis(), Vector3(-0.8, 1.1, 0.4)), TrackMats.flat(Color(0.98, 0.6, 0.1))])
			parts.append([_sphere(0.35, 8, 4), Transform3D(Basis(), Vector3(0.6, 1.1, -0.3)), TrackMats.flat(Color(0.8, 0.2, 0.15))])
			mi.mesh = combine(parts)
		"obelisk":
			var inst := TrackBuilder._inst_glb(M + "prop_pyramid_obelisk.glb")
			if inst:
				inst.scale = Vector3.ONE * (r / 3.0)
				node.add_child(inst)
		"temple_pillar", "lab_column", "ice_pillar":
			var h := ceil_h if ceil_h > 0.0 else 9.0
			var mat := TrackMats.wall_mat("temple" if kind == "temple_pillar" else ("lab" if kind == "lab_column" else "ice"), ceil_h > 0.0)
			mi.mesh = combine([
				[_cyl(r * 0.85, r, h, 10), Transform3D(Basis(), Vector3(0, h * 0.5, 0)), mat],
				[_box(r * 2.4, 0.8, r * 2.4), Transform3D(Basis(), Vector3(0, 0.4, 0)), mat],
				[_box(r * 2.4, 0.8, r * 2.4), Transform3D(Basis(), Vector3(0, h - 0.4, 0)), mat],
			])
		"stalagmite":
			var rm := TrackMats.pbr("cliff_rock_tiki", Color(0.7, 0.74, 0.78), 0.6)
			mi.mesh = combine([[_cyl(0.15, r, 6.5, 9), Transform3D(Basis(), Vector3(0, 3.25, 0)), rm],
				[_cyl(0.1, r * 0.55, 3.2, 7), Transform3D(Basis(), Vector3(r * 0.7, 1.6, 0.3)), rm]])
		"crate_stack", "barrel_stack":
			mi.mesh = proc_mesh("crate_stack")
		"vat":
			var inst2 := TrackBuilder._inst_glb(M + "prop_lab_vat.glb")
			if inst2:
				inst2.scale = Vector3.ONE * (r / 3.8)
				node.add_child(inst2)
		"tank":
			mi.mesh = proc_mesh("tank")
			mi.scale = Vector3.ONE * (r / 2.6)
		"ice_block", "crystal":
			var inst3 := TrackBuilder._inst_glb(M + "prop_glacier_crystal.glb")
			if inst3:
				inst3.scale = Vector3.ONE * (r / 1.3)
				node.add_child(inst3)
		"rock", "boulder_static":
			mi.mesh = _rock_mesh(31, r, 0.75, Color(0.8, 0.78, 0.74))
		"neon_pylon", "barrier":
			var pm := TrackMats.flat(Color(0.12, 0.12, 0.18), 0.4, 0.5)
			var gm := TrackMats.flat(Color(1.0, 0.3, 0.8) if kind == "neon_pylon" else Color(1.0, 0.75, 0.1), 0.3, 0.0, 3.0)
			mi.mesh = combine([[_cyl(r * 0.7, r, 4.0, 8), Transform3D(Basis(), Vector3(0, 2.0, 0)), pm],
				[_cyl(r * 0.72, r * 0.72, 0.4, 8), Transform3D(Basis(), Vector3(0, 3.2, 0)), gm],
				[_cyl(r * 0.85, r * 0.85, 0.4, 8), Transform3D(Basis(), Vector3(0, 1.4, 0)), gm]])
		"spire":
			var inst4 := TrackBuilder._inst_glb(M + "prop_volcano_spire.glb")
			if inst4:
				inst4.scale = Vector3.ONE * (r / 1.8)
				node.add_child(inst4)
		_:
			mi.mesh = _cyl(r * 0.8, r, 4.0, 8)
			mi.material_override = TrackMats.wall_mat("temple")
	if mi.mesh:
		node.add_child(mi)
	else:
		mi.free()
	return node

# ------------------------------------------------------------------------------------------------ landmarks
static func build_landmark(w: TrackWorld, lm: Dictionary, mx: float) -> void:
	var kind := str(lm.get("kind", "glb"))
	match kind:
		"blocks":
			_build_blocks(w, lm, mx)
		"glb":
			var inst := TrackBuilder._inst_glb(str(lm["glb"]))
			if inst == null:
				return
			inst.position = Vector3(float(lm["x"]) * mx, float(lm["y"]), float(lm["z"]))
			inst.rotation.y = float(lm.get("rot", 0.0)) * mx
			var sc := float(lm.get("scale", 1.0))
			inst.scale = Vector3(sc, float(lm.get("sy", sc)), sc)
			w.add_child(inst)
			if float(lm.get("col_r", 0.0)) > 0.0:
				w.builder._add_cyl_collider(inst, float(lm["col_r"]) / sc, float(lm.get("col_h", 12.0)) / float(lm.get("sy", sc)), Vector3.ZERO, false, str(lm.get("strength", "heavy")))
		"waterfall":
			_build_waterfall(w, lm, mx)
		"pillar_col":
			var holder := Node3D.new()
			holder.position = Vector3(float(lm["x"]) * mx, float(lm["y"]), float(lm["z"]))
			w.add_child(holder)
			w.builder._add_cyl_collider(holder, float(lm.get("r", 2.0)), 14.0, Vector3.ZERO, false, "heavy")
		"light":
			var ol := OmniLight3D.new()
			ol.position = Vector3(float(lm["x"]) * mx, float(lm["y"]), float(lm["z"]))
			ol.light_color = Color.html(str(lm.get("color", "#ffb060")))
			ol.light_energy = float(lm.get("energy", 2.0))
			ol.omni_range = float(lm.get("range", 20.0))
			w.add_child(ol)

static func _build_blocks(w: TrackWorld, lm: Dictionary, mx: float) -> void:
	## Voxel massif (stepped pyramid, lab block, rock mass). boxes: [cx, cz, y0, y1, sx, sz]. Corridors already carved.
	var tex := str(lm.get("tex", "wall_tiki"))
	var tint := Color.html(str(lm.get("tint", "#ffffff")))
	var mat := TrackMats.pbr(tex, tint, 0.9)
	var top_mat := TrackMats.pbr(str(lm.get("top_tex", tex)), Color.html(str(lm.get("top_tint", lm.get("tint", "#ffffff")))), 0.9)
	var rep := float(lm.get("rep", 6.0))
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var stt := SurfaceTool.new()
	stt.begin(Mesh.PRIMITIVE_TRIANGLES)
	var faces := PackedVector3Array()
	for bx in lm.get("boxes", []):
		var cx := float(bx[0]) * mx
		var cz := float(bx[1])
		var y0 := float(bx[2])
		var y1 := float(bx[3])
		var hx := float(bx[4]) * 0.5
		var hz := float(bx[5]) * 0.5
		if y1 - y0 < 0.05:
			continue
		var c := Vector3(cx, (y0 + y1) * 0.5, cz)
		var e := Vector3(hx, (y1 - y0) * 0.5, hz)
		_box_faces(st, stt, c, e, rep)
		_box_col(faces, c, e)
	# one trimesh collider for the whole massif (layer 2 -> walls of the massif are solid; tops are out of bounds)
	var sb := StaticBody3D.new()
	sb.collision_layer = TrackBuilder.OFFROAD_LAYER | TrackBuilder.WALL_LAYER
	sb.set_meta("surface_type", "rock")
	sb.set_meta("collision_strength", "heavy")
	sb.set_meta("oob", true)
	var cs := CollisionShape3D.new()
	var shape := ConcavePolygonShape3D.new()
	shape.set_faces(faces)
	cs.shape = shape
	sb.add_child(cs)
	w.add_child(sb)
	st.generate_tangents()
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if bool(lm.get("shadow", true)) else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	w.add_child(mi)
	stt.generate_tangents()
	var mt := MeshInstance3D.new()
	mt.mesh = stt.commit()
	mt.material_override = top_mat
	mt.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	w.add_child(mt)

static func _box_col(faces: PackedVector3Array, c: Vector3, e: Vector3) -> void:
	for n in [Vector3.RIGHT, Vector3.LEFT, Vector3.FORWARD, Vector3.BACK, Vector3.UP]:
		var u: Vector3
		var v: Vector3
		if absf(n.y) > 0.5:
			u = Vector3(e.x, 0, 0); v = Vector3(0, 0, e.z)
		elif absf(n.x) > 0.5:
			u = Vector3(0, 0, e.z); v = Vector3(0, e.y, 0)
		else:
			u = Vector3(e.x, 0, 0); v = Vector3(0, e.y, 0)
		var fc: Vector3 = c + n * Vector3(absf(n.x) * e.x, absf(n.y) * e.y, absf(n.z) * e.z).length()
		TrackBuilder.col_quad(faces, fc - u - v, fc + u - v, fc - u + v, fc + u + v, n)

static func _box_faces(st: SurfaceTool, st_top: SurfaceTool, c: Vector3, e: Vector3, rep: float) -> void:
	var dirs := [Vector3.RIGHT, Vector3.LEFT, Vector3.FORWARD, Vector3.BACK, Vector3.UP, Vector3.DOWN]
	for n in dirs:
		var target := st_top if n == Vector3.UP else st
		var u: Vector3
		var v: Vector3
		if absf(n.y) > 0.5:
			u = Vector3(e.x, 0, 0); v = Vector3(0, 0, e.z)
		elif absf(n.x) > 0.5:
			u = Vector3(0, 0, e.z); v = Vector3(0, e.y, 0)
		else:
			u = Vector3(e.x, 0, 0); v = Vector3(0, e.y, 0)
		var fc: Vector3 = c + n * Vector3(absf(n.x) * e.x, absf(n.y) * e.y, absf(n.z) * e.z).length()
		var p00: Vector3 = fc - u - v
		var p10: Vector3 = fc + u - v
		var p01: Vector3 = fc - u + v
		var p11: Vector3 = fc + u + v
		var uvf := func(p: Vector3) -> Vector2:
			if absf(n.y) > 0.5:
				return Vector2(p.x, p.z) / rep
			elif absf(n.x) > 0.5:
				return Vector2(p.z, -p.y) / rep
			return Vector2(p.x, -p.y) / rep
		TrackBuilder.tri(target, p00, p10, p11, n, n, n, uvf.call(p00), uvf.call(p10), uvf.call(p11))
		TrackBuilder.tri(target, p00, p11, p01, n, n, n, uvf.call(p00), uvf.call(p11), uvf.call(p01))

static func _build_waterfall(w: TrackWorld, lm: Dictionary, mx: float) -> void:
	var shader := TrackBuilder._load_shader("res://assets/shaders/waterfall.gdshader")
	if shader == null:
		return
	var mi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(float(lm.get("w", 20.0)), float(lm.get("h", 30.0)))
	pm.subdivide_depth = 8
	mi.mesh = pm
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var sm := ShaderMaterial.new()
	sm.shader = shader
	if bool(lm.get("lava", false)):
		sm.set_shader_parameter("color_deep", Color(0.88, 0.16, 0.02))
		sm.set_shader_parameter("color_foam", Color(1.0, 0.86, 0.24))
		sm.set_shader_parameter("flow_speed", 0.95)
		sm.set_shader_parameter("alpha_base", 0.95)
	mi.material_override = sm
	mi.position = Vector3(float(lm["x"]) * mx, float(lm["y"]), float(lm["z"]))
	mi.rotation_degrees = Vector3(90.0, rad_to_deg(float(lm.get("rot", 0.0))) * mx, 0.0)
	w.add_child(mi)
