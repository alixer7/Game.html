class_name Vegetation
extends Node3D
## Procedural trees, bushes, cacti and rocks placed from the baked object list,
## drawn with chunked MultiMeshes (2 LODs) plus a pool of proximity colliders.

const TILE := 512.0
enum { PINE, BROAD, BIRCH, PALM, BUSH, CACTUS, ROCK, DEAD, CYPRESS }

var wd: WorldData
var quality := 1
var meshes := {}      # type -> [lod0, lod1]
var ranges := {}      # type -> [near, far]
var leaf_mat: ShaderMaterial
var pine_mat: ShaderMaterial
var palm_mat: ShaderMaterial
var bark_mat: StandardMaterial3D
var birch_mat: StandardMaterial3D
var lod_mat: ShaderMaterial
var rock_mat: ShaderMaterial
var cactus_mat: StandardMaterial3D
var colliders := []
var collider_used := {}
var _rng := RandomNumberGenerator.new()


func build(data: WorldData, q: int, view: float) -> void:
	wd = data
	quality = q
	_rng.seed = 99
	var far := lerpf(500.0, 1100.0, view) * (0.75 if q == 0 else 1.0)
	var near := 70.0 if q == 0 else (110.0 if q == 1 else 170.0)
	_materials()
	meshes[PINE] = [_pine(), _cone_lod(11.5, 2.6, 2.0, Color(0.13, 0.22, 0.11))]
	meshes[CYPRESS] = [_cypress(), _cone_lod(11.0, 1.1, 1.0, Color(0.14, 0.22, 0.1))]
	meshes[BROAD] = [_broadleaf(Color(1, 1, 1), 1.0), _blob_lod(Vector3(0, 6.2, 0), Vector3(3.6, 3.0, 3.6), Color(0.2, 0.3, 0.1), 7.0)]
	meshes[BIRCH] = [_birch(), _blob_lod(Vector3(0, 7.0, 0), Vector3(2.4, 3.2, 2.4), Color(0.32, 0.4, 0.14), 7.5)]
	meshes[PALM] = [_palm(), _palm()]
	meshes[BUSH] = [_bush(), _blob_lod(Vector3(0, 0.9, 0), Vector3(1.5, 1.0, 1.5), Color(0.2, 0.28, 0.1), 0.0)]
	meshes[CACTUS] = [_cactus(), _cactus()]
	meshes[ROCK] = [_rock(1), _rock(0)]
	meshes[DEAD] = [_dead(), _dead()]
	for t in [PINE, CYPRESS, BROAD, BIRCH, PALM, CACTUS, DEAD]:
		ranges[t] = [near, far]
	ranges[BUSH] = [near * 0.7, far * 0.45]
	ranges[ROCK] = [far * 0.35, far * 0.8]
	_populate()
	for i in 48:
		var b := StaticBody3D.new()
		b.collision_layer = 1
		b.collision_mask = 0
		b.set_meta("surface", "tree")
		var cs := CollisionShape3D.new()
		cs.shape = CylinderShape3D.new()
		b.add_child(cs)
		b.process_mode = Node.PROCESS_MODE_DISABLED
		b.position = Vector3(0, -1000, 0)
		add_child(b)
		colliders.append(b)


func _materials() -> void:
	var broad_tex: Texture2D = load("res://assets/textures/leaves_broad.png")
	var pine_tex: Texture2D = load("res://assets/textures/leaves_pine.png")
	leaf_mat = _foliage(broad_tex, Color(1.0, 1.0, 1.0), 0.3)
	pine_mat = _foliage(pine_tex, Color(1.0, 1.05, 1.0), 0.2)
	palm_mat = _foliage(pine_tex, Color(1.6, 1.7, 1.1), 0.35)
	bark_mat = StandardMaterial3D.new()
	bark_mat.albedo_texture = load("res://assets/textures/bark_albedo.png")
	bark_mat.albedo_color = Color(0.9, 0.85, 0.8)
	bark_mat.roughness = 0.95
	bark_mat.uv1_scale = Vector3(1, 1, 1)
	bark_mat.vertex_color_use_as_albedo = true
	birch_mat = StandardMaterial3D.new()
	birch_mat.albedo_color = Color(0.86, 0.85, 0.8)
	birch_mat.roughness = 0.8
	birch_mat.vertex_color_use_as_albedo = true
	lod_mat = ShaderMaterial.new()
	lod_mat.shader = load("res://shaders/foliage.gdshader")
	lod_mat.set_shader_parameter("use_texture", false)
	lod_mat.set_shader_parameter("wind", 0.0)
	rock_mat = ShaderMaterial.new()
	rock_mat.shader = load("res://shaders/triplanar.gdshader")
	rock_mat.set_shader_parameter("surf_albedo", load("res://assets/textures/terrain_albedo.png"))
	rock_mat.set_shader_parameter("surf_normal", load("res://assets/textures/terrain_normal.png"))
	rock_mat.set_shader_parameter("layer", 1.0)
	rock_mat.set_shader_parameter("scale", 0.35)
	rock_mat.set_shader_parameter("tint", Color(0.95, 0.92, 0.88))
	cactus_mat = StandardMaterial3D.new()
	cactus_mat.albedo_color = Color(0.28, 0.42, 0.2)
	cactus_mat.roughness = 0.7
	cactus_mat.vertex_color_use_as_albedo = true


func _foliage(tex: Texture2D, tint: Color, wind: float) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = load("res://shaders/foliage.gdshader")
	m.set_shader_parameter("leaf_tex", tex)
	m.set_shader_parameter("tint", Color(tint.r, tint.g, tint.b))
	m.set_shader_parameter("wind", wind)
	return m


# --------------------------------------------------------------------------- placement
func _populate() -> void:
	var buckets := {}   # Vector3i(tx, tz, type) -> Array[Transform3D]
	var o := wd.objects
	for i in wd.object_count:
		var t := int(o[i * 6])
		var x := o[i * 6 + 1]
		var y := o[i * 6 + 2]
		var z := o[i * 6 + 3]
		var yaw := o[i * 6 + 4]
		var s := o[i * 6 + 5]
		if quality == 0 and t == BUSH and (i % 2 == 0):
			continue
		var key := Vector3i(floori(x / TILE), floori(z / TILE), t)
		if not buckets.has(key):
			buckets[key] = []
		var basis := Basis(Vector3.UP, yaw).scaled(Vector3(s, s, s))
		if t == ROCK:
			basis = Basis(Vector3.UP, yaw).scaled(Vector3(s * 1.3, s * 0.8, s))
			y -= s * 0.35
		elif t == PALM:
			basis = Basis(Vector3(cos(yaw), 0, sin(yaw)), 0.08) * basis
		buckets[key].append(Transform3D(basis, Vector3(x, y - 0.1, z)))
	for key in buckets:
		var t: int = key.z
		var xs: Array = buckets[key]
		var lods: Array = meshes[t]
		var rg: Array = ranges[t]
		for li in 2:
			if li == 1 and lods[1] == lods[0]:
				# same mesh for both LODs: a single instance covering the whole range
				continue
			var mm := MultiMesh.new()
			mm.transform_format = MultiMesh.TRANSFORM_3D
			mm.mesh = lods[li]
			mm.instance_count = xs.size()
			for k in xs.size():
				mm.set_instance_transform(k, xs[k])
			var mmi := MultiMeshInstance3D.new()
			mmi.multimesh = mm
			if lods[1] == lods[0]:
				mmi.visibility_range_end = rg[1]
			elif li == 0:
				mmi.visibility_range_end = rg[0]
			else:
				mmi.visibility_range_begin = rg[0]
				mmi.visibility_range_end = rg[1]
			mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if li == 0 else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			add_child(mmi)


# --------------------------------------------------------------------------- colliders
func update_colliders(points: Array) -> void:
	var want := []
	for p in points:
		var cx := floori(p.x / 64.0)
		var cz := floori(p.z / 64.0)
		for dz in range(-1, 2):
			for dx in range(-1, 2):
				var key := Vector2i(cx + dx, cz + dz)
				if not wd.obj_grid.has(key):
					continue
				for i in wd.obj_grid[key]:
					var t := int(wd.objects[i * 6])
					if t == BUSH:
						continue
					var q := Vector3(wd.objects[i * 6 + 1], wd.objects[i * 6 + 2], wd.objects[i * 6 + 3])
					if Vector2(q.x - p.x, q.z - p.z).length_squared() < 38.0 * 38.0:
						want.append(i)
	var used := {}
	var slot := 0
	for i in want:
		if used.has(i) or slot >= colliders.size():
			continue
		used[i] = true
		var b: StaticBody3D = colliders[slot]
		slot += 1
		var t := int(wd.objects[i * 6])
		var s := wd.objects[i * 6 + 5]
		var cs: CollisionShape3D = b.get_child(0)
		var sh: CylinderShape3D = cs.shape
		var r := 0.32 * s
		var h := 6.0 * s
		if t == ROCK:
			r = 1.0 * s
			h = 1.6 * s
		elif t == CACTUS:
			r = 0.35 * s
			h = 4.0 * s
		elif t == PALM:
			r = 0.25 * s
		if not is_equal_approx(sh.radius, r) or not is_equal_approx(sh.height, h):
			sh.radius = r
			sh.height = h
		b.set_meta("surface", "rock" if t == ROCK else "tree")
		b.process_mode = Node.PROCESS_MODE_INHERIT
		b.global_position = Vector3(wd.objects[i * 6 + 1], wd.objects[i * 6 + 2] + h * 0.5 - 0.2, wd.objects[i * 6 + 3])
	for k in range(slot, colliders.size()):
		var b: StaticBody3D = colliders[k]
		if b.position.y > -900.0:
			b.position = Vector3(0, -1000, 0)
			b.process_mode = Node.PROCESS_MODE_DISABLED


# --------------------------------------------------------------------------- tree meshes
func _trunk(m: MeshAcc, r0: float, r1: float, h: float, sides := 7, color := Color(1, 1, 1, 0)) -> void:
	m.use_colors = true
	m.color = color
	m.cylinder(Transform3D(), r0, r1, -0.3, h, sides, false, 0.5)


func _card(m: MeshAcc, center: Vector3, right: Vector3, up: Vector3, nrm: Vector3, w: float, h: float, shade: float, uv_rect := Rect2(0, 0, 1, 1)) -> void:
	m.use_colors = true
	m.color = Color(shade, shade, shade, 1.0)
	var a := m.v(center - right * w * 0.5 - up * h * 0.5, nrm, uv_rect.position + Vector2(0, uv_rect.size.y))
	var b := m.v(center + right * w * 0.5 - up * h * 0.5, nrm, uv_rect.position + uv_rect.size)
	var c := m.v(center + right * w * 0.5 + up * h * 0.5, nrm, uv_rect.position + Vector2(uv_rect.size.x, 0))
	var d := m.v(center - right * w * 0.5 + up * h * 0.5, nrm, uv_rect.position)
	m.quad(a, b, c, d, nrm)


func _pine() -> ArrayMesh:
	var trunk := MeshAcc.new()
	_trunk(trunk, 0.3, 0.05, 11.5, 7, Color(0.8, 0.75, 0.7, 0.0))
	var f := MeshAcc.new()
	var tiers := 9
	for ti in tiers:
		var t := float(ti) / (tiers - 1)
		var y := lerpf(2.4, 11.0, t)
		var length := lerpf(3.1, 0.7, t)
		var cards := 7 if t < 0.7 else 5
		var off := _rng.randf() * TAU
		for c in cards:
			var a := off + TAU * c / cards + _rng.randf_range(-0.2, 0.2)
			var dir := Vector3(cos(a), 0, sin(a))
			var droop := -0.38
			var along := (dir + Vector3(0, droop, 0)).normalized()
			var side := dir.cross(Vector3.UP).normalized()
			var center := Vector3(0, y, 0) + along * length * 0.5
			var nrm := (dir * 0.6 + Vector3(0, 0.8, 0)).normalized()
			var shade := lerpf(0.65, 1.05, t) * _rng.randf_range(0.9, 1.05)
			# card: width along the branch, height across it
			_card_branch(f, center, along, side, nrm, length, length * 0.62, shade)
	# top spike
	_card_branch(f, Vector3(0, 11.6, 0), Vector3.UP, Vector3.RIGHT, Vector3.UP, 1.4, 0.6, 1.0)
	_card_branch(f, Vector3(0, 11.6, 0), Vector3.UP, Vector3.BACK, Vector3.UP, 1.4, 0.6, 1.0)
	var mesh := trunk.to_mesh(bark_mat)
	f.to_mesh(pine_mat, mesh)
	return mesh


func _card_branch(m: MeshAcc, center: Vector3, along: Vector3, side: Vector3, nrm: Vector3, length: float, width: float, shade: float) -> void:
	# the pine atlas has branches running along +u, so map u -> along
	m.use_colors = true
	m.color = Color(shade, shade, shade, 1.0)
	var a := m.v(center - along * length * 0.5 - side * width * 0.5, nrm, Vector2(0, 1))
	var b := m.v(center + along * length * 0.5 - side * width * 0.5, nrm, Vector2(1, 1))
	var c := m.v(center + along * length * 0.5 + side * width * 0.5, nrm, Vector2(1, 0))
	var d := m.v(center - along * length * 0.5 + side * width * 0.5, nrm, Vector2(0, 0))
	m.quad(a, b, c, d, nrm)


func _cypress() -> ArrayMesh:
	var trunk := MeshAcc.new()
	_trunk(trunk, 0.2, 0.05, 10.5, 6, Color(0.8, 0.75, 0.7, 0.0))
	var f := MeshAcc.new()
	for ti in 16:
		var t := ti / 15.0
		var y := lerpf(1.2, 11.0, t)
		var rad := sin(PI * (0.15 + t * 0.85)) * 1.05 + 0.15
		for c in 4:
			var a := TAU * c / 4.0 + ti * 0.7
			var dir := Vector3(cos(a), 0, sin(a))
			var center := Vector3(0, y, 0) + dir * rad * 0.5
			var side := dir.cross(Vector3.UP)
			_card(f, center, side, Vector3.UP, (dir + Vector3(0, 0.3, 0)).normalized(), rad * 2.2, 1.6, lerpf(0.6, 1.0, t))
	var mesh := trunk.to_mesh(bark_mat)
	f.to_mesh(leaf_mat, mesh)
	return mesh


func _crown(f: MeshAcc, center: Vector3, radii: Vector3, count: int, size: float, shade_lo := 0.6) -> void:
	for i in count:
		# fibonacci sphere distribution, biased to the upper half
		var k := float(i) + 0.5
		var phi := acos(1.0 - 2.0 * k / count)
		var theta := PI * (1.0 + sqrt(5.0)) * k
		var dir := Vector3(cos(theta) * sin(phi), cos(phi), sin(theta) * sin(phi))
		var p := center + dir * radii * _rng.randf_range(0.55, 0.95)
		var nrm := dir.normalized()
		var right := nrm.cross(Vector3.UP if absf(nrm.y) < 0.9 else Vector3.RIGHT).normalized()
		right = right.rotated(nrm, _rng.randf() * TAU)
		var up := right.cross(nrm).normalized()
		var shade := lerpf(shade_lo, 1.05, clampf(dir.y * 0.5 + 0.5, 0.0, 1.0))
		_card(f, p, right, up, nrm, size, size, shade)
	# inner cards for density
	for i in count / 3:
		var p := center + Vector3(_rng.randf_range(-1, 1), _rng.randf_range(-0.6, 0.8), _rng.randf_range(-1, 1)) * radii * 0.45
		var a := _rng.randf() * TAU
		var right := Vector3(cos(a), 0, sin(a))
		_card(f, p, right, Vector3.UP, (p - center).normalized(), size * 1.2, size * 1.2, shade_lo)


func _broadleaf(_tint: Color, _s: float) -> ArrayMesh:
	var trunk := MeshAcc.new()
	_trunk(trunk, 0.38, 0.18, 5.5, 8, Color(0.85, 0.8, 0.75, 0.0))
	for b in 4:
		var a := TAU * b / 4.0 + 0.4
		var xf := Transform3D(Basis(Vector3(cos(a + PI * 0.5), 0, sin(a + PI * 0.5)), 0.75), Vector3(0, 4.2 + b * 0.3, 0))
		trunk.cylinder(xf, 0.16, 0.06, 0.0, 2.6, 5, false, 0.5)
	var f := MeshAcc.new()
	_crown(f, Vector3(0, 6.4, 0), Vector3(3.3, 2.6, 3.3), 34 if quality > 0 else 22, 2.9)
	var mesh := trunk.to_mesh(bark_mat)
	f.to_mesh(leaf_mat, mesh)
	return mesh


func _birch() -> ArrayMesh:
	var trunk := MeshAcc.new()
	_trunk(trunk, 0.2, 0.07, 9.0, 6, Color(1, 1, 1, 0))
	var f := MeshAcc.new()
	_crown(f, Vector3(0, 7.0, 0), Vector3(2.1, 2.9, 2.1), 22, 2.1, 0.75)
	var mesh := trunk.to_mesh(birch_mat)
	f.to_mesh(leaf_mat, mesh)
	return mesh


func _bush() -> ArrayMesh:
	var f := MeshAcc.new()
	_crown(f, Vector3(0, 0.85, 0), Vector3(1.3, 0.8, 1.3), 12, 1.6, 0.55)
	return f.to_mesh(leaf_mat)


func _palm() -> ArrayMesh:
	var trunk := MeshAcc.new()
	trunk.use_colors = true
	trunk.color = Color(0.75, 0.68, 0.55, 0.0)
	var segs := 8
	var top := Vector3.ZERO
	for i in segs:
		var t0 := float(i) / segs
		var t1 := float(i + 1) / segs
		var p0 := Vector3(t0 * t0 * 1.6, t0 * 9.0, 0)
		var p1 := Vector3(t1 * t1 * 1.6, t1 * 9.0, 0)
		var dir := (p1 - p0).normalized()
		var basis := Basis(Quaternion(Vector3.UP, dir))
		trunk.cylinder(Transform3D(basis, p0), lerpf(0.26, 0.17, t0), lerpf(0.26, 0.17, t1) * 1.08, 0.0, p0.distance_to(p1), 7, false, 0.6)
		top = p1
	var f := MeshAcc.new()
	for k in 10:
		var a := TAU * k / 10.0 + _rng.randf_range(-0.15, 0.15)
		var dir := Vector3(cos(a), 0, sin(a))
		var side := dir.cross(Vector3.UP)
		var L := _rng.randf_range(3.6, 4.6)
		# two segments: up-out then drooping
		var mid := top + dir * L * 0.45 + Vector3(0, 0.55, 0)
		var tip := top + dir * L + Vector3(0, -1.0, 0)
		var w := 1.1
		f.use_colors = true
		f.color = Color(1, 1, 1, 1)
		var n1 := (Vector3.UP + dir * 0.2).normalized()
		var v0 := f.v(top - side * w * 0.3, n1, Vector2(0, 1))
		var v1 := f.v(top + side * w * 0.3, n1, Vector2(0, 0))
		var v2 := f.v(mid + side * w * 0.5, n1, Vector2(0.5, 0))
		var v3 := f.v(mid - side * w * 0.5, n1, Vector2(0.5, 1))
		var v4 := f.v(tip + side * w * 0.15, n1, Vector2(1, 0))
		var v5 := f.v(tip - side * w * 0.15, n1, Vector2(1, 1))
		f.quad(v0, v1, v2, v3, n1)
		f.quad(v3, v2, v4, v5, n1)
	var mesh := trunk.to_mesh(bark_mat)
	f.to_mesh(palm_mat, mesh)
	return mesh


func _cactus() -> ArrayMesh:
	var m := MeshAcc.new()
	m.use_colors = true
	m.color = Color(1, 1, 1, 0)
	m.cylinder(Transform3D(), 0.34, 0.3, -0.2, 4.6, 10, true)
	for s: float in [-1.0, 1.0]:
		var h := 1.8 if s > 0 else 2.4
		m.cylinder(Transform3D(Basis(Vector3(0, 0, 1), -s * PI * 0.5), Vector3(0, h, 0)), 0.2, 0.2, 0.0, 0.8, 8, false)
		m.cylinder(Transform3D(Basis(), Vector3(s * 0.8, h - 0.1, 0)), 0.2, 0.18, 0.0, 1.6, 8, true)
	return m.to_mesh(cactus_mat)


func _dead() -> ArrayMesh:
	var m := MeshAcc.new()
	_trunk(m, 0.3, 0.08, 7.0, 6, Color(0.6, 0.55, 0.5, 0))
	for b in 5:
		var a := TAU * b / 5.0
		var xf := Transform3D(Basis(Vector3(cos(a + PI * 0.5), 0, sin(a + PI * 0.5)), 0.85), Vector3(0, 3.0 + b * 0.7, 0))
		m.cylinder(xf, 0.1, 0.02, 0.0, 2.2, 5, false)
	return m.to_mesh(bark_mat)


func _rock(detail: int) -> ArrayMesh:
	# subdivided octahedron displaced by noise
	var m := MeshAcc.new()
	var verts := [Vector3.UP, Vector3.DOWN, Vector3.LEFT, Vector3.RIGHT, Vector3.FORWARD, Vector3.BACK]
	var faces := [[0, 4, 3], [0, 3, 5], [0, 5, 2], [0, 2, 4], [1, 3, 4], [1, 5, 3], [1, 2, 5], [1, 4, 2]]
	for it in detail + 2:
		var nf := []
		var mid := {}
		for f in faces:
			var ids := []
			for e in [[f[0], f[1]], [f[1], f[2]], [f[2], f[0]]]:
				var key := Vector2i(mini(e[0], e[1]), maxi(e[0], e[1]))
				if not mid.has(key):
					verts.append(((verts[e[0]] + verts[e[1]]) * 0.5).normalized())
					mid[key] = verts.size() - 1
				ids.append(mid[key])
			nf.append([f[0], ids[0], ids[2]])
			nf.append([f[1], ids[1], ids[0]])
			nf.append([f[2], ids[2], ids[1]])
			nf.append([ids[0], ids[1], ids[2]])
		faces = nf
	var noise := FastNoiseLite.new()
	noise.seed = 5
	noise.frequency = 1.3
	var disp := []
	for p in verts:
		var d: float = 1.0 + noise.get_noise_3dv(p * 1.0) * 0.35
		var q: Vector3 = p * d
		q.y = maxf(q.y, -0.4) * (0.75 if q.y > 0 else 1.0)
		disp.append(q)
	# flat-ish shading: accumulate face normals per vertex
	var acc := []
	acc.resize(disp.size())
	for i in acc.size():
		acc[i] = Vector3.ZERO
	for f in faces:
		var nn: Vector3 = (disp[f[1]] - disp[f[0]]).cross(disp[f[2]] - disp[f[0]])
		if nn.dot(disp[f[0]]) < 0:
			nn = -nn
		for k in 3:
			acc[f[k]] += nn
	var ids := []
	for i in disp.size():
		ids.append(m.v(disp[i], acc[i].normalized()))
	for f in faces:
		var c: Vector3 = (disp[f[0]] + disp[f[1]] + disp[f[2]]) / 3.0
		m.tri(ids[f[0]], ids[f[1]], ids[f[2]], c)
	return m.to_mesh(rock_mat)


func _cone_lod(h: float, r: float, y0: float, color: Color) -> ArrayMesh:
	var m := MeshAcc.new()
	m.use_colors = true
	m.color = Color(0.35, 0.28, 0.22, 0)
	m.cylinder(Transform3D(), 0.25, 0.15, -0.3, y0 + 0.5, 5, false)
	m.color = Color(color.r * 1.25, color.g * 1.25, color.b * 1.25, 0)
	m.cylinder(Transform3D(), r, 0.05, y0, h + 0.5, 8, true)
	return m.to_mesh(lod_mat)


func _blob_lod(center: Vector3, radii: Vector3, color: Color, trunk_h: float) -> ArrayMesh:
	var m := MeshAcc.new()
	m.use_colors = true
	if trunk_h > 0.0:
		m.color = Color(0.35, 0.28, 0.22, 0)
		m.cylinder(Transform3D(), 0.3, 0.2, -0.3, trunk_h * 0.6, 5, false)
	m.color = Color(color.r * 1.25, color.g * 1.25, color.b * 1.25, 0)
	var rings := 5
	var segs := 8
	var grid := []
	for i in rings + 1:
		var phi := PI * i / rings
		var row := []
		for j in segs + 1:
			var th := TAU * j / segs
			var d := Vector3(sin(phi) * cos(th), cos(phi), sin(phi) * sin(th))
			row.append(m.v(center + d * radii, d))
		grid.append(row)
	for i in rings:
		for j in segs:
			var c: Vector3 = (m.verts[grid[i][j]] + m.verts[grid[i + 1][j + 1]]) * 0.5 - center
			m.quad(grid[i][j], grid[i][j + 1], grid[i + 1][j + 1], grid[i + 1][j], c)
	return m.to_mesh(lod_mat)
