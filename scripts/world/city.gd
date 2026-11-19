class_name City
extends Node3D
## Downtown: buildings (glass towers, offices, brick blocks), sidewalks, parks,
## construction site, parking lot, harbour containers and cranes.

var wd: WorldData
var quality := 1
var bmat: ShaderMaterial
var _rng := RandomNumberGenerator.new()


func build(data: WorldData, q: int) -> void:
	wd = data
	quality = q
	_rng.seed = 4242
	bmat = ShaderMaterial.new()
	bmat.shader = load("res://shaders/building.gdshader")
	bmat.set_shader_parameter("surf_albedo", Mats.surf_tex()[0])
	var c: Dictionary = wd.json.city
	var ground: float = c.height
	_blocks(c, ground)
	_buildings(c, ground)
	_harbour()


func set_night(v: float) -> void:
	bmat.set_shader_parameter("night", v)


func _blocks(c: Dictionary, ground: float) -> void:
	var side := MeshAcc.new()
	var tops := {}
	var body := StaticBody3D.new()
	body.set_meta("surface", "concrete")
	add_child(body)
	for b in c.blocks:
		var r: Array = b.rect
		var kind: String = b.kind
		var top := ground + 0.18
		var x0: float = r[0]
		var z0: float = r[1]
		var x1: float = r[2]
		var z1: float = r[3]
		var layer_key := "sidewalk"
		match kind:
			"park", "plaza":
				layer_key = "grass" if kind == "park" else "sidewalk"
			"construction":
				layer_key = "gravel"
			"parking":
				layer_key = "asphalt"
		if not tops.has(layer_key):
			tops[layer_key] = MeshAcc.new()
		var t: MeshAcc = tops[layer_key]
		var a := t.v(Vector3(x0, top, z0), Vector3.UP, Vector2(x0, z0))
		var bb := t.v(Vector3(x1, top, z0), Vector3.UP, Vector2(x1, z0))
		var cc := t.v(Vector3(x1, top, z1), Vector3.UP, Vector2(x1, z1))
		var d := t.v(Vector3(x0, top, z1), Vector3.UP, Vector2(x0, z1))
		t.quad(a, bb, cc, d, Vector3.UP)
		# kerb faces
		var corners := [Vector3(x0, 0, z0), Vector3(x1, 0, z0), Vector3(x1, 0, z1), Vector3(x0, 0, z1)]
		for i in 4:
			var p0: Vector3 = corners[i]
			var p1: Vector3 = corners[(i + 1) % 4]
			var mid := (p0 + p1) * 0.5 - Vector3((x0 + x1) * 0.5, 0, (z0 + z1) * 0.5)
			var nn := mid.normalized()
			var q0 := side.v(Vector3(p0.x, top, p0.z), nn, Vector2(0, 0))
			var q1 := side.v(Vector3(p1.x, top, p1.z), nn, Vector2(p0.distance_to(p1), 0))
			var q2 := side.v(Vector3(p1.x, ground - 0.4, p1.z), nn, Vector2(p0.distance_to(p1), 0.6))
			var q3 := side.v(Vector3(p0.x, ground - 0.4, p0.z), nn, Vector2(0, 0.6))
			side.quad(q0, q1, q2, q3, nn)
		var cs := CollisionShape3D.new()
		var sh := BoxShape3D.new()
		sh.size = Vector3(x1 - x0, 0.6, z1 - z0)
		cs.shape = sh
		cs.position = Vector3((x0 + x1) * 0.5, top - 0.3, (z0 + z1) * 0.5)
		body.add_child(cs)
		if kind == "construction":
			_construction((x0 + x1) * 0.5, (z0 + z1) * 0.5, top)
		elif kind == "parking":
			_parking(x0, z0, x1, z1, top)
	var mats := {
		"sidewalk": Mats.triplanar(4, 0.3),
		"grass": _grass_mat(),
		"gravel": Mats.triplanar(2, 0.25),
		"asphalt": Mats.triplanar(0, 0.2, Color(1.3, 1.3, 1.3)),
	}
	var mesh := side.to_mesh(Mats.concrete())
	for k in tops:
		tops[k].to_mesh(mats[k], mesh)
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	add_child(mi)


func _grass_mat() -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = load("res://shaders/triplanar.gdshader")
	m.set_shader_parameter("surf_albedo", load("res://assets/textures/terrain_albedo.png"))
	m.set_shader_parameter("surf_normal", load("res://assets/textures/terrain_normal.png"))
	m.set_shader_parameter("layer", 0.0)
	m.set_shader_parameter("scale", 0.15)
	return m


func _buildings(c: Dictionary, ground: float) -> void:
	var per_block := {}
	var body := StaticBody3D.new()
	body.set_meta("surface", "concrete")
	add_child(body)
	for lot in c.lots:
		var cx: float = lot[0]
		var cz: float = lot[1]
		var w: float = lot[2]
		var d: float = lot[3]
		var h: float = lot[4]
		var style: int = int(lot[5])
		var seed: float = float(int(lot[6]) % 1000) / 1000.0
		var key := Vector2i(floori(cx / 160.0), floori(cz / 160.0))
		if not per_block.has(key):
			var acc := MeshAcc.new()
			acc.use_colors = true
			per_block[key] = acc
		var m: MeshAcc = per_block[key]
		var lit := _rng.randf_range(0.15, 0.45)
		var base := ground + 0.18
		var boxes := []
		if h > 70.0:
			var podium := _rng.randf_range(12.0, 22.0)
			boxes.append([cx, cz, w, d, base, base + podium])
			var tw := w * _rng.randf_range(0.68, 0.82)
			var td := d * _rng.randf_range(0.68, 0.82)
			var mid := base + h * _rng.randf_range(0.72, 0.85)
			boxes.append([cx, cz, tw, td, base + podium, mid])
			boxes.append([cx, cz, tw * 0.78, td * 0.78, mid, base + h])
		else:
			boxes.append([cx, cz, w, d, base, base + h])
		for bx in boxes:
			_box_building(m, bx, style, seed, lit)
			var cs := CollisionShape3D.new()
			var sh := BoxShape3D.new()
			sh.size = Vector3(bx[2], bx[5] - bx[4], bx[3])
			cs.shape = sh
			cs.position = Vector3(bx[0], (bx[4] + bx[5]) * 0.5, bx[1])
			body.add_child(cs)
		# rooftop units
		var top: Array = boxes[boxes.size() - 1]
		var ty: float = top[5]
		m.color = Color(0.25, seed, 0.0, 0.0)
		for u in _rng.randi_range(1, 4):
			var ux: float = top[0] + _rng.randf_range(-0.3, 0.3) * float(top[2])
			var uz: float = top[1] + _rng.randf_range(-0.3, 0.3) * float(top[3])
			m.box(Transform3D(Basis(), Vector3(ux, ty + 1.0, uz)), Vector3(_rng.randf_range(2, 5), 2.0, _rng.randf_range(2, 4)))
		# parapet
		_parapet(m, top, ty, seed)
	for key in per_block:
		var mi := MeshInstance3D.new()
		mi.mesh = per_block[key].to_mesh(bmat)
		mi.visibility_range_end = 3200.0
		add_child(mi)


func _box_building(m: MeshAcc, bx: Array, style: int, seed: float, lit: float) -> void:
	var cx: float = bx[0]
	var cz: float = bx[1]
	var hw: float = bx[2] * 0.5
	var hd: float = bx[3] * 0.5
	var y0: float = bx[4]
	var y1: float = bx[5]
	var ground: float = wd.json.city.height + 0.18
	var corners := [Vector3(cx - hw, 0, cz - hd), Vector3(cx + hw, 0, cz - hd), Vector3(cx + hw, 0, cz + hd), Vector3(cx - hw, 0, cz + hd)]
	m.color = Color(style / 4.0, seed, lit, 1.0)
	for i in 4:
		var p0: Vector3 = corners[i]
		var p1: Vector3 = corners[(i + 1) % 4]
		var nn := ((p0 + p1) * 0.5 - Vector3(cx, 0, cz)).normalized()
		var L := p0.distance_to(p1)
		var a := m.v(Vector3(p0.x, y0, p0.z), nn, Vector2(0, y0 - ground))
		var b := m.v(Vector3(p1.x, y0, p1.z), nn, Vector2(L, y0 - ground))
		var c := m.v(Vector3(p1.x, y1, p1.z), nn, Vector2(L, y1 - ground))
		var d := m.v(Vector3(p0.x, y1, p0.z), nn, Vector2(0, y1 - ground))
		m.quad(a, b, c, d, nn)
	m.color = Color(style / 4.0, seed, lit, 0.0)
	var r := []
	for p in corners:
		r.append(m.v(Vector3(p.x, y1, p.z), Vector3.UP, Vector2(p.x, p.z)))
	m.quad(r[0], r[1], r[2], r[3], Vector3.UP)


func _parapet(m: MeshAcc, top: Array, y: float, seed: float) -> void:
	m.color = Color(0.25, seed, 0.0, 0.0)
	var hw: float = float(top[2]) * 0.5
	var hd: float = float(top[3]) * 0.5
	var cx: float = top[0]
	var cz: float = top[1]
	m.box(Transform3D(Basis(), Vector3(cx, y + 0.5, cz - hd + 0.2)), Vector3(hw * 2, 1.0, 0.4))
	m.box(Transform3D(Basis(), Vector3(cx, y + 0.5, cz + hd - 0.2)), Vector3(hw * 2, 1.0, 0.4))
	m.box(Transform3D(Basis(), Vector3(cx - hw + 0.2, y + 0.5, cz)), Vector3(0.4, 1.0, hd * 2))
	m.box(Transform3D(Basis(), Vector3(cx + hw - 0.2, y + 0.5, cz)), Vector3(0.4, 1.0, hd * 2))


func _construction(cx: float, cz: float, top: float) -> void:
	# dirt mounds, a crane mast and concrete blocks: an obstacle course for the shortcut
	var m := MeshAcc.new()
	var body := StaticBody3D.new()
	body.set_meta("surface", "concrete")
	add_child(body)
	for i in 6:
		var p := Vector3(cx + _rng.randf_range(-55, 55), top + 0.6, cz + _rng.randf_range(-55, 55))
		if absf((p.x - cx) - (p.z - cz)) < 14.0:
			continue  # keep the diagonal shortcut free
		var s := Vector3(_rng.randf_range(2, 5), 1.2, _rng.randf_range(1.5, 3))
		m.box(Transform3D(Basis(Vector3.UP, _rng.randf() * PI), p), s)
		var cs := CollisionShape3D.new()
		var sh := BoxShape3D.new()
		sh.size = s
		cs.shape = sh
		cs.transform = Transform3D(Basis(), p)
		body.add_child(cs)
	var crane := MeshAcc.new()
	var base := Vector3(cx + 40, top, cz - 40)
	for i in 12:
		crane.box(Transform3D(Basis(), base + Vector3(0, 3.0 + i * 6.0, 0)), Vector3(1.8, 6.0, 1.8))
	crane.box(Transform3D(Basis(), base + Vector3(-18, 75, 0)), Vector3(52, 1.6, 1.6))
	var mi := MeshInstance3D.new()
	var mesh := m.to_mesh(Mats.concrete())
	crane.to_mesh(Mats.std("crane", Color(0.9, 0.7, 0.1), 0.3, 0.5), mesh)
	mi.mesh = mesh
	add_child(mi)


func _parking(x0: float, z0: float, x1: float, z1: float, top: float) -> void:
	var m := MeshAcc.new()
	for i in range(int((x1 - x0 - 10) / 3.0)):
		var x := x0 + 6 + i * 3.0
		for zz in [z0 + 20, z1 - 20]:
			m.box(Transform3D(Basis(), Vector3(x, top + 0.005, zz)), Vector3(0.12, 0.01, 5.0))
	var mi := MeshInstance3D.new()
	mi.mesh = m.to_mesh(Mats.std("paint_white", Color(0.9, 0.9, 0.88), 0.0, 0.6))
	add_child(mi)


func _harbour() -> void:
	var m := MeshAcc.new()
	m.use_colors = true
	var body := StaticBody3D.new()
	body.set_meta("surface", "concrete")
	add_child(body)
	var cols := [Color(0.7, 0.15, 0.1), Color(0.1, 0.3, 0.6), Color(0.85, 0.55, 0.1), Color(0.2, 0.5, 0.3), Color(0.6, 0.6, 0.62), Color(0.45, 0.2, 0.4)]
	var y0 := 3.6
	for row in 5:
		for colm in 9:
			var x := 1150.0 + colm * 14.0
			var z := 860.0 + row * 9.0
			var h := wd.height(x, z)
			if absf(h - y0) > 1.0:
				continue
			var stack := _rng.randi_range(1, 4)
			for s in stack:
				m.color = cols[_rng.randi() % cols.size()]
				m.box(Transform3D(Basis(), Vector3(x, h + 1.3 + s * 2.6, z)), Vector3(12.2, 2.6, 2.45))
			var cs := CollisionShape3D.new()
			var sh := BoxShape3D.new()
			sh.size = Vector3(12.2, 2.6 * stack, 2.45)
			cs.shape = sh
			cs.position = Vector3(x, h + 2.6 * stack * 0.5, z)
			body.add_child(cs)
	# gantry cranes on the quay
	var cr := MeshAcc.new()
	for i in 2:
		var p := Vector3(1450.0 + i * 70.0, 3.6, 990.0)
		for lx: float in [-9.0, 9.0]:
			for lz: float in [-6.0, 6.0]:
				cr.box(Transform3D(Basis(), p + Vector3(lx, 14, lz)), Vector3(1.4, 28, 1.4))
		cr.box(Transform3D(Basis(), p + Vector3(0, 28, 0)), Vector3(22, 2.5, 14))
		cr.box(Transform3D(Basis(), p + Vector3(0, 30, 20)), Vector3(4, 2.0, 60))
	var mesh := m.to_mesh(Mats.std("container", Color(1, 1, 1), 0.4, 0.55))
	(mesh.surface_get_material(0) as StandardMaterial3D).vertex_color_use_as_albedo = true
	cr.to_mesh(Mats.std("crane_blue", Color(0.15, 0.35, 0.65), 0.4, 0.5), mesh)
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	add_child(mi)
