class_name Scatter
extends RefCounted
## Rule-based vegetation & rock scattering with MultiMesh cells and LODs.

# quality -> spacing multipliers (lower quality = sparser)
const DENSITY := [1.7, 1.3, 1.0]


static func _variant(meshes: Array, mats: Array) -> ArrayMesh:
	var am := ArrayMesh.new()
	for i in meshes.size():
		var mb: MeshBuilder = meshes[i]
		if mb == null or mb.vcount() == 0:
			continue
		mb.commit(am, mats[i])
	return am


static func build_all(tb: TrackBuilder) -> void:
	var q := clampi(tb.quality, 0, 2)
	var dens: float = DENSITY[q]
	var root := Node3D.new()
	root.name = "Scatter"
	tb.root.add_child(root)
	var bark_mat := Mats.triplanar("bark")
	var leaf_mat := Mats.foliage(Color.WHITE, "trees")
	var card_mat := Mats.cards(Color.WHITE, "trees")
	var small_mat := Mats.foliage(Color.WHITE, "small")
	small_mat.set_shader_parameter("fade_far", 55.0)
	var grass_mat := Mats.grass_blades()
	grass_mat.set_shader_parameter("fade_far", [26.0, 36.0, 48.0][q])
	var rock_mat := Mats.triplanar("rock")
	var fern_mat := Mats.foliage(Color.WHITE, "ferns")
	fern_mat.set_shader_parameter("fade_far", 60.0)

	# ---------------------------------------------------------------- variants
	var V := []   # {name, lod0, lod1, r0, r1, collide}
	for s in 3:
		var t0 := MeshLib.broadleaf_tree(100 + s, 0, s % 3)
		var t1 := MeshLib.broadleaf_tree(100 + s, 1, s % 3)
		V.append({"name": "oak%d" % s, "lod0": _variant([t0.bark, t0.leaves, t0.cards], [bark_mat, leaf_mat, card_mat]),
			"lod1": _variant([t1.bark, t1.leaves], [bark_mat, leaf_mat]), "r": t0.trunk_r, "kind": "tree"})
	var ta := MeshLib.broadleaf_tree(140, 0, 3)
	var ta1 := MeshLib.broadleaf_tree(140, 1, 3)
	V.append({"name": "autumn", "lod0": _variant([ta.bark, ta.leaves, ta.cards], [bark_mat, leaf_mat, card_mat]),
		"lod1": _variant([ta1.bark, ta1.leaves], [bark_mat, leaf_mat]), "r": ta.trunk_r, "kind": "tree"})
	for s in 2:
		var p0 := MeshLib.pine_tree(200 + s, 0)
		var p1 := MeshLib.pine_tree(200 + s, 1)
		V.append({"name": "pine%d" % s, "lod0": _variant([p0.bark, p0.leaves], [bark_mat, leaf_mat]),
			"lod1": _variant([p1.bark, p1.leaves], [bark_mat, leaf_mat]), "r": p0.trunk_r, "kind": "tree"})
	var b0 := MeshLib.birch_tree(300, 0)
	var b1 := MeshLib.birch_tree(300, 1)
	V.append({"name": "birch", "lod0": _variant([b0.bark, b0.leaves, b0.cards], [Mats.vcol(0.7), leaf_mat, card_mat]),
		"lod1": _variant([b1.bark, b1.leaves], [Mats.vcol(0.7), leaf_mat]), "r": 0.3, "kind": "tree"})
	for s in 2:
		var bu := MeshLib.bush(400 + s, 0, s == 1)
		var bu1 := MeshLib.bush(400 + s, 1, s == 1)
		V.append({"name": "bush%d" % s, "lod0": _variant([bu.leaves, bu.cards], [leaf_mat, card_mat]),
			"lod1": _variant([bu1.leaves], [leaf_mat]), "r": 0.0, "kind": "bush"})
	V.append({"name": "fern", "lod0": _variant([MeshLib.fern(500)], [fern_mat]), "lod1": null, "r": 0.0, "kind": "fern"})
	var gm := MeshBuilder.new()
	for g in 5:
		gm.append_builder(MeshLib.grass_clump(600 + g, 9, 0.55), Transform3D(Basis(Vector3.UP, g * 1.3), Vector3(cos(g * 2.4) * 0.9, 0, sin(g * 2.4) * 0.9)))
	V.append({"name": "grass", "lod0": _variant([gm], [grass_mat]), "lod1": null, "r": 0.0, "kind": "grass"})
	var gd := MeshBuilder.new()
	for g in 4:
		gd.append_builder(MeshLib.grass_clump(650 + g, 7, 0.75, true), Transform3D(Basis(Vector3.UP, g * 1.7), Vector3(cos(g * 1.9) * 0.7, 0, sin(g * 1.9) * 0.7)))
	V.append({"name": "grass_tall", "lod0": _variant([gd], [grass_mat]), "lod1": null, "r": 0.0, "kind": "grass"})
	var fl := MeshBuilder.new()
	var fcols := [Color(1.0, 0.95, 0.95), Color(1.0, 0.85, 0.2), Color(0.85, 0.45, 0.95), Color(1.0, 0.45, 0.5), Color(0.5, 0.7, 1.0)]
	for f in 7:
		fl.append_builder(MeshLib.flower(700 + f, fcols[f % fcols.size()]), Transform3D(Basis(), Vector3(cos(f * 2.2) * 1.2, 0, sin(f * 2.2) * 1.2)))
	V.append({"name": "flowers", "lod0": _variant([fl], [small_mat]), "lod1": null, "r": 0.0, "kind": "flower"})
	V.append({"name": "mushroom", "lod0": _variant([MeshLib.mushroom_cluster(800)], [Mats.vcol(0.7)]), "lod1": null, "r": 0.0, "kind": "mushroom"})
	V.append({"name": "reeds", "lod0": _variant([MeshLib.reeds(850)], [small_mat]), "lod1": null, "r": 0.0, "kind": "reeds"})
	V.append({"name": "lily", "lod0": _variant([MeshLib.lily_pad(870)], [Mats.vcol(0.5)]), "lod1": null, "r": 0.0, "kind": "lily"})
	for s in 4:
		V.append({"name": "rock%d" % s, "lod0": _variant([MeshLib.rock(900 + s, s % 3, 0)], [rock_mat]),
			"lod1": _variant([MeshLib.rock(900 + s, s % 3, 1)], [rock_mat]), "r": 1.0, "kind": "rock"})
	V.append({"name": "stump", "lod0": _variant([MeshLib.stump(950)], [bark_mat]), "lod1": null, "r": 0.6, "kind": "stump"})
	V.append({"name": "deadlog", "lod0": _variant([MeshLib.log_mesh(5.0, 0.45, 960)], [bark_mat]), "lod1": null, "r": 0.0, "kind": "deadlog"})

	var by_name := {}
	for i in V.size():
		by_name[V[i].name] = i

	# ---------------------------------------------------------------- placement
	var terrain := tb.terrain
	var rng := RandomNumberGenerator.new()
	rng.seed = 5150
	var nz := FastNoiseLite.new()
	nz.seed = 77
	nz.frequency = 0.018
	var nz2 := FastNoiseLite.new()
	nz2.seed = 78
	nz2.frequency = 0.06
	var buckets := {}    # Vector3i(cx, cz, variant) -> Array[Transform3D]
	var colliders: Array = []   # [Vector3, radius, height]
	var exclusions: Array = []
	for lm in tb.landmarks:
		var rad := {"elder_tree": 16.0, "guardian_owl": 8.0, "mill": 11.0, "lower_falls": 9.0, "giants_log": 7.0, "rootway_cave": 6.0}.get(lm.name, 0.0) as float
		if rad > 0.0:
			exclusions.append([lm.pos, rad])
	for o in tb.obstacles:
		exclusions.append([o[0], float(o[1]) + 1.5])
	var b := tb._bounds()
	var ruins_c := tb.mark_pos("flytraps")
	var river_c := tb.mark_pos("gravel_bar")

	var place := func(name: String, x: float, z: float, scale: float, yaw: float, tilt_normal := false, cell := 64.0, sink := 0.0) -> void:
		var vi: int = by_name[name]
		var y := terrain.height_at(x, z) - sink
		var basis := Basis(Vector3.UP, yaw).scaled(Vector3.ONE * scale)
		if tilt_normal:
			var n := terrain.normal_at(x, z)
			var tq := Quaternion(Vector3.UP, n)
			basis = Basis(tq) * basis
		var key := Vector3i(floori(x / cell), floori(z / cell), vi)
		if not buckets.has(key):
			buckets[key] = []
		(buckets[key] as Array).append(Transform3D(basis, Vector3(x, y, z)))

	var excluded := func(x: float, z: float, extra: float) -> bool:
		for e in exclusions:
			var p: Vector3 = e[0]
			if Vector2(p.x - x, p.z - z).length() < float(e[1]) + extra:
				return true
		return false

	# --- trees
	var tree_step := 6.5 * dens
	var gx := b.position.x
	while gx < b.end.x:
		var gz := b.position.y
		while gz < b.end.y:
			var x := gx + rng.randf_range(-0.45, 0.45) * tree_step
			var z := gz + rng.randf_range(-0.45, 0.45) * tree_step
			gz += tree_step
			var d := terrain.dist_at(x, z)
			if d < 4.5 or terrain.water_at(x, z):
				continue
			var far := d > 70.0
			if far and rng.randf() < 0.45:
				continue   # sparser in the deep background
			var clear := nz.get_noise_2d(x, z)
			if d < 30.0 and clear < -0.25:
				continue   # meadows & clearings near the road keep sightlines open
			if d < 12.0 and rng.randf() < 0.45:
				continue
			if excluded.call(x, z, 2.0):
				continue
			var nrm := terrain.normal_at(x, z)
			if nrm.y < 0.6:
				continue
			var name := "oak%d" % rng.randi_range(0, 2)
			var near_river := Vector2(x - river_c.x, z - river_c.z).length() < 120.0
			var near_ruins := Vector2(x - ruins_c.x, z - ruins_c.z).length() < 90.0
			var hgt := terrain.height_at(x, z)
			if hgt > 14.0 or (far and rng.randf() < 0.5):
				name = "pine%d" % rng.randi_range(0, 1)
			elif near_river and rng.randf() < 0.35:
				name = "birch"
			elif near_ruins and rng.randf() < 0.3:
				name = "autumn"
			var sc := rng.randf_range(0.8, 1.3) * (1.15 if far else 1.0)
			place.call(name, x, z, sc, rng.randf() * TAU, false, 64.0, 0.2)
			if d < 32.0:
				var vr: float = V[by_name[name]].r
				colliders.append([Vector3(x, hgt, z), maxf(vr * sc, 0.35), 4.0])
		gx += tree_step

	# --- undergrowth, rocks, flowers, grass
	var small_step := 2.2 * dens
	gx = b.position.x
	while gx < b.end.x:
		var gz := b.position.y
		while gz < b.end.y:
			var x := gx + rng.randf_range(-0.5, 0.5) * small_step
			var z := gz + rng.randf_range(-0.5, 0.5) * small_step
			gz += small_step
			var d := terrain.dist_at(x, z)
			if d > 60.0:
				# rocks and bushes only in the far field
				if rng.randf() < 0.03 and not terrain.water_at(x, z):
					place.call("rock%d" % rng.randi_range(0, 3), x, z, rng.randf_range(1.2, 3.5), rng.randf() * TAU, true, 96.0, 0.6)
				elif rng.randf() < 0.05:
					place.call("bush%d" % rng.randi_range(0, 1), x, z, rng.randf_range(1.0, 1.8), rng.randf() * TAU, false, 96.0)
				continue
			var water := terrain.water_at(x, z)
			var surf := terrain.surface_at_xz(x, z)
			var nn := nz2.get_noise_2d(x, z)
			if water:
				# lily pads on still water away from the racing river
				if terrain.dist_at(x, z) > 6.0 and rng.randf() < 0.12:
					place.call("lily", x, z, rng.randf_range(0.8, 1.3), rng.randf() * TAU, false, 32.0, -0.55)
				continue
			if excluded.call(x, z, 0.0):
				continue
			if surf == Surfaces.SAND:
				if d > 1.5 and rng.randf() < 0.3:
					place.call("reeds", x, z, rng.randf_range(0.8, 1.3), rng.randf() * TAU, false, 32.0, 0.1)
				continue
			if d < 0.9:
				continue
			var r := rng.randf()
			if d > 2.0 and r < 0.025:
				place.call("rock%d" % rng.randi_range(0, 3), x, z, rng.randf_range(0.5, 1.6), rng.randf() * TAU, true, 64.0, 0.25)
				if d < 18.0:
					colliders.append([Vector3(x, terrain.height_at(x, z), z), 0.9, 1.6])
			elif d > 3.0 and r < 0.07:
				place.call("bush%d" % rng.randi_range(0, 1), x, z, rng.randf_range(0.7, 1.4), rng.randf() * TAU, false, 64.0)
			elif d > 2.0 and r < 0.12 and nn > -0.1:
				place.call("fern", x, z, rng.randf_range(0.8, 1.5), rng.randf() * TAU, false, 32.0)
			elif d > 2.0 and r < 0.135 and nn > 0.2:
				place.call("mushroom", x, z, rng.randf_range(0.8, 1.6), rng.randf() * TAU, false, 32.0)
			elif d > 1.6 and r < 0.17 and nn < -0.2:
				place.call("flowers", x, z, rng.randf_range(0.8, 1.2), rng.randf() * TAU, false, 32.0)
			elif d > 8.0 and r < 0.172:
				place.call("stump", x, z, rng.randf_range(0.8, 1.3), rng.randf() * TAU, false, 64.0, 0.1)
			elif d > 9.0 and r < 0.174:
				place.call("deadlog", x, z, rng.randf_range(0.8, 1.2), rng.randf() * TAU, true, 64.0, 0.2)
			elif d < 28.0 and r < 0.17 + 0.55 * (1.0 if q >= 2 else 0.6):
				place.call("grass" if nn < 0.35 else "grass_tall", x, z, rng.randf_range(0.8, 1.3), rng.randf() * TAU, false, 24.0)
		gx += small_step

	# ---------------------------------------------------------------- emit MultiMeshes
	var ranges := {"tree": [150.0, 620.0], "bush": [110.0, 260.0], "fern": [62.0, 0.0], "grass": [58.0, 0.0],
		"flower": [60.0, 0.0], "mushroom": [55.0, 0.0], "reeds": [80.0, 0.0], "lily": [110.0, 0.0],
		"rock": [140.0, 420.0], "stump": [80.0, 0.0], "deadlog": [90.0, 0.0]}
	var count := 0
	for key in buckets:
		var vi: int = key.z
		var v: Dictionary = V[vi]
		var xfs: Array = buckets[key]
		var rr: Array = ranges[v.kind]
		for lod in 2:
			var mesh: ArrayMesh = v.lod0 if lod == 0 else v.lod1
			if mesh == null:
				continue
			var mm := MultiMesh.new()
			mm.transform_format = MultiMesh.TRANSFORM_3D
			mm.mesh = mesh
			mm.instance_count = xfs.size()
			for i in xfs.size():
				mm.set_instance_transform(i, xfs[i])
			var mmi := MultiMeshInstance3D.new()
			mmi.multimesh = mm
			mmi.name = "%s_%d_%d_L%d" % [v.name, key.x, key.y, lod]
			if lod == 0:
				mmi.visibility_range_end = rr[0]
				mmi.visibility_range_end_margin = 8.0
				if v.lod1 == null:
					mmi.visibility_range_end = rr[0]
			else:
				mmi.visibility_range_begin = rr[0] - 8.0
				mmi.visibility_range_end = rr[1]
				mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			if v.kind in ["grass", "flower", "fern", "mushroom", "reeds", "lily"]:
				mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			root.add_child(mmi)
			count += xfs.size()
	# ---------------------------------------------------------------- colliders near the track
	var body := StaticBody3D.new()
	body.name = "ScatterColliders"
	body.collision_layer = 1
	body.set_meta("surface", Surfaces.WOOD)
	for c in colliders:
		var cs := CollisionShape3D.new()
		var cyl := CylinderShape3D.new()
		cyl.radius = c[1]
		cyl.height = c[2]
		cs.shape = cyl
		cs.position = (c[0] as Vector3) + Vector3.UP * float(c[2]) * 0.5
		body.add_child(cs)
	root.add_child(body)
	tb.timings["scatter_instances"] = count
	tb.timings["scatter_colliders"] = colliders.size()
