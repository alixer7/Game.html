class_name Ruins
extends Node3D
## Historical & landmark structures built from procedural stonework.

var wd: WorldData
var _rng := RandomNumberGenerator.new()
var windmills: Array[Node3D] = []
var stone: ShaderMaterial
var stone_grey: ShaderMaterial


func build(data: WorldData) -> void:
	wd = data
	_rng.seed = 777
	stone = Mats.masonry()
	stone_grey = Mats.triplanar(5, 0.3, Color(0.78, 0.78, 0.8), "grey")
	for r in wd.json.ruins:
		var p := Vector3(r.pos[0], r.pos[1], r.pos[2])
		var xf := Transform3D(Basis(Vector3.UP, r.yaw).scaled(Vector3.ONE * float(r.scale)), p)
		match r.type:
			"temple": _temple(xf)
			"colonnade": _colonnade(xf)
			"amphitheater": _amphitheater(xf)
			"arch": _arch(xf)
			"ziggurat": _ziggurat(xf)
			"obelisk": _obelisk(xf)
			"wall": _wall(xf)
			"broken": _broken(xf)
			"aqueduct": _aqueduct(r.pts)
			"lighthouse": _lighthouse(xf)
			"castle": _castle(xf)
			"windmill": _windmill(xf)
	_circuit_props()


func _process(delta: float) -> void:
	for w in windmills:
		w.rotate_object_local(Vector3.FORWARD, delta * 0.6)


func _commit(m: MeshAcc, mat: Material, collide := true, vis := 1800.0) -> void:
	if m.is_empty():
		return
	var mi := MeshInstance3D.new()
	mi.mesh = m.to_mesh(mat)
	mi.visibility_range_end = vis
	add_child(mi)
	if collide:
		var b := StaticBody3D.new()
		b.set_meta("surface", "stone")
		var cs := CollisionShape3D.new()
		var sh := ConcavePolygonShape3D.new()
		sh.backface_collision = true
		sh.set_faces(m.faces())
		cs.shape = sh
		b.add_child(cs)
		add_child(b)


func _column(m: MeshAcc, xf: Transform3D, h: float, r: float, broken := false) -> void:
	# base, fluted shaft, capital
	m.box(xf * Transform3D(Basis(), Vector3(0, 0.25, 0)), Vector3(r * 2.6, 0.5, r * 2.6))
	var flutes := 16
	var top := h if not broken else h * _rng.randf_range(0.25, 0.7)
	var shaft_top := top - (0.0 if broken else 0.9)
	var ring0 := []
	var ring1 := []
	for i in flutes * 2 + 1:
		var a := TAU * i / (flutes * 2)
		var rr := r * (1.0 if i % 2 == 0 else 0.92)
		var d := Vector3(cos(a), 0, sin(a))
		var n := (xf.basis * d).normalized()
		ring0.append(m.v(xf * (d * rr + Vector3(0, 0.5, 0)), n, Vector2(a * r, 0.5)))
		ring1.append(m.v(xf * (d * rr * 0.86 + Vector3(0, shaft_top, 0)), n, Vector2(a * r, shaft_top)))
	for i in flutes * 2:
		var face := xf.basis * Vector3(cos(TAU * (i + 0.5) / (flutes * 2)), 0, sin(TAU * (i + 0.5) / (flutes * 2)))
		m.quad(ring0[i], ring0[i + 1], ring1[i + 1], ring1[i], face)
	if broken:
		var c := m.v(xf * Vector3(0, shaft_top, 0), xf.basis * Vector3.UP)
		for i in flutes * 2:
			m.tri(c, ring1[i], ring1[i + 1], xf.basis * Vector3.UP)
	else:
		m.cylinder(xf * Transform3D(Basis(), Vector3(0, shaft_top, 0)), r * 0.86, r * 1.15, 0.0, 0.5, 12, false)
		m.box(xf * Transform3D(Basis(), Vector3(0, top - 0.2, 0)), Vector3(r * 2.7, 0.4, r * 2.7))


func _temple(xf: Transform3D) -> void:
	var m := MeshAcc.new()
	var L := 40.0
	var W := 20.0
	for s in 3:
		m.box(xf * Transform3D(Basis(), Vector3(0, -0.6 + s * 0.6 + 0.3, 0)), Vector3(L + 6 - s * 2.0, 0.6, W + 6 - s * 2.0))
	var base_y := 1.2
	var nx := 13
	var nz := 6
	var h := 9.5
	var intact := {}
	for i in nx:
		for j in nz:
			if i != 0 and i != nx - 1 and j != 0 and j != nz - 1:
				continue
			var x := -L * 0.5 + 1.5 + (L - 3.0) * i / (nx - 1)
			var z := -W * 0.5 + 1.5 + (W - 3.0) * j / (nz - 1)
			var broken := _rng.randf() < 0.3
			_column(m, xf * Transform3D(Basis(), Vector3(x, base_y, z)), h, 0.72, broken)
			if not broken:
				intact[Vector2i(i, j)] = true
	# architrave on runs of intact columns along the long sides
	for j: int in [0, nz - 1]:
		for i in nx - 1:
			if intact.has(Vector2i(i, j)) and intact.has(Vector2i(i + 1, j)):
				var x := -L * 0.5 + 1.5 + (L - 3.0) * (i + 0.5) / (nx - 1)
				var z := -W * 0.5 + 1.5 + (W - 3.0) * j / (nz - 1)
				m.box(xf * Transform3D(Basis(), Vector3(x, base_y + h + 0.6, z)), Vector3((L - 3.0) / (nx - 1) + 0.2, 1.2, 1.8))
	# cella walls (ruined)
	for side: float in [-1.0, 1.0]:
		for k in 6:
			var hh := _rng.randf_range(1.0, 6.5)
			m.box(xf * Transform3D(Basis(), Vector3(-12 + k * 4.4, base_y + hh * 0.5, side * 4.5)), Vector3(4.2, hh, 0.9))
	# fallen drums
	for k in 5:
		var p := Vector3(_rng.randf_range(-L, L) * 0.7, 0.7, _rng.randf_range(W * 0.6, W * 1.1) * (1 if k % 2 == 0 else -1))
		m.cylinder(xf * Transform3D(Basis(Vector3(0, 0, 1), PI * 0.5).rotated(Vector3.UP, _rng.randf() * PI), p), 0.7, 0.7, -1.0, 1.0, 12, true)
	_commit(m, stone)


func _colonnade(xf: Transform3D) -> void:
	var m := MeshAcc.new()
	for i in 12:
		var broken := _rng.randf() < 0.35
		_column(m, xf * Transform3D(Basis(), Vector3(i * 4.2 - 23, 0, 0)), 7.5, 0.55, broken)
	m.box(xf * Transform3D(Basis(), Vector3(-14, 8.0, 0)), Vector3(17, 1.0, 1.4))
	_commit(m, stone)


func _amphitheater(xf: Transform3D) -> void:
	var m := MeshAcc.new()
	var rows := 12
	var segs := 22
	for i in rows:
		var r0 := 16.0 + i * 2.6
		var y := i * 0.85
		for s in segs:
			if _rng.randf() < 0.06 + i * 0.012:
				continue
			var a0 := PI * s / segs
			var a1 := PI * (s + 1) / segs
			var am := (a0 + a1) * 0.5
			var arc := (a1 - a0) * (r0 + 1.3)
			var pos := Vector3(cos(am) * (r0 + 1.3), y + 0.45, sin(am) * (r0 + 1.3))
			var basis := Basis(Vector3.UP, -am + PI * 0.5)
			m.box(xf * Transform3D(basis, pos), Vector3(arc + 0.05, 0.9 + y, 2.6) if i == 0 else Vector3(arc + 0.05, 0.9, 2.6))
			if i > 0:
				m.box(xf * Transform3D(basis, Vector3(pos.x, y * 0.5, pos.z)), Vector3(arc + 0.05, y, 2.6))
	# stage
	m.box(xf * Transform3D(Basis(), Vector3(0, 0.6, -6)), Vector3(30, 1.2, 8))
	for i in 7:
		_column(m, xf * Transform3D(Basis(), Vector3(-12 + i * 4, 1.2, -9)), 6.0, 0.45, _rng.randf() < 0.4)
	_commit(m, stone)


func _arch(xf: Transform3D) -> void:
	var m := MeshAcc.new()
	var span := 7.0
	for s: float in [-1.0, 1.0]:
		m.box(xf * Transform3D(Basis(), Vector3(s * (span * 0.5 + 2.0), 5.5, 0)), Vector3(4.0, 11.0, 5.0))
	var segs := 10
	var rr := span * 0.5
	for i in segs:
		var a0 := PI * i / segs
		var a1 := PI * (i + 1) / segs
		var am := (a0 + a1) * 0.5
		var p := Vector3(cos(am) * (rr + 0.7), 7.0 + sin(am) * (rr + 0.7), 0)
		m.box(xf * Transform3D(Basis(Vector3.BACK, am - PI * 0.5), p), Vector3((a1 - a0) * (rr + 0.7) + 0.1, 1.4, 5.0))
	m.box(xf * Transform3D(Basis(), Vector3(0, 13.0, 0)), Vector3(span + 8.0, 3.6, 5.2))
	m.box(xf * Transform3D(Basis(), Vector3(0, 15.2, 0)), Vector3(span + 8.6, 0.8, 5.8))
	_commit(m, stone)


func _ziggurat(xf: Transform3D) -> void:
	var m := MeshAcc.new()
	var y := 0.0
	for i in 6:
		var s := 46.0 - i * 7.0
		var h := 4.0
		m.box(xf * Transform3D(Basis(), Vector3(0, y + h * 0.5 - 0.5, 0)), Vector3(s, h, s))
		y += h
	m.box(xf * Transform3D(Basis(), Vector3(0, y + 2.0, 0)), Vector3(6, 4, 6))
	# staircase
	for k in 24:
		m.box(xf * Transform3D(Basis(), Vector3(0, k * 1.0 + 0.0, 23.0 - k * 0.95 + 3.0)), Vector3(6.0, 1.0, 1.2))
	_commit(m, stone)


func _obelisk(xf: Transform3D) -> void:
	var m := MeshAcc.new()
	m.box(xf * Transform3D(Basis(), Vector3(0, 0.8, 0)), Vector3(4.5, 1.6, 4.5))
	m.cylinder(xf * Transform3D(Basis(Vector3.UP, PI * 0.25), Vector3(0, 1.6, 0)), 1.45, 1.0, 0.0, 17.0, 4, false)
	m.cylinder(xf * Transform3D(Basis(Vector3.UP, PI * 0.25), Vector3(0, 18.6, 0)), 1.0, 0.0, 0.0, 1.6, 4, false)
	_commit(m, stone)


func _wall(xf: Transform3D) -> void:
	var m := MeshAcc.new()
	for i in 14:
		var h := _rng.randf_range(0.8, 5.5) if _rng.randf() > 0.15 else 0.4
		m.box(xf * Transform3D(Basis(), Vector3(i * 3.6 - 25, h * 0.5 - 0.3, 0)), Vector3(3.5, h, 1.6))
	_commit(m, stone)


func _broken(xf: Transform3D) -> void:
	var m := MeshAcc.new()
	for i in 10:
		var p := Vector3(_rng.randf_range(-14, 14), 0.0, _rng.randf_range(-14, 14))
		if _rng.randf() < 0.5:
			m.cylinder(xf * Transform3D(Basis(Vector3(0, 0, 1), PI * 0.5).rotated(Vector3.UP, _rng.randf() * PI), p + Vector3(0, 0.5, 0)), 0.55, 0.55, -0.6, 0.6, 12, true)
		else:
			m.box(xf * Transform3D(Basis(Vector3.UP, _rng.randf() * PI), p + Vector3(0, 0.4, 0)), Vector3(_rng.randf_range(1, 2.4), 0.9, _rng.randf_range(0.8, 1.6)))
	_commit(m, stone, true, 900.0)


func _aqueduct(pts: Array) -> void:
	var m := MeshAcc.new()
	var top := -1e9
	var ps := []
	for q in pts:
		var p := Vector3(q[0], q[1], q[2])
		ps.append(p)
		top = maxf(top, p.y)
	top += 15.0
	for i in ps.size():
		var p: Vector3 = ps[i]
		var dir: Vector3 = (ps[mini(i + 1, ps.size() - 1)] - ps[maxi(i - 1, 0)]).normalized()
		var basis := Basis.looking_at(Vector3(dir.x, 0, dir.z), Vector3.UP)
		var h := top - p.y + 2.0
		if _rng.randf() < 0.12 and i > 2 and i < ps.size() - 3:
			# collapsed pier
			m.box(Transform3D(basis, p + Vector3(0, 1.5, 0)), Vector3(3.2, 3.0, 3.0))
			continue
		m.box(Transform3D(basis, Vector3(p.x, p.y + h * 0.5 - 2.0, p.z)), Vector3(3.0, h, 2.8))
		if i < ps.size() - 1:
			var nxt: Vector3 = ps[i + 1]
			var mid := (p + nxt) * 0.5
			var span := Vector2(nxt.x - p.x, nxt.z - p.z).length()
			m.box(Transform3D(basis, Vector3(mid.x, top - 1.0, mid.z)), Vector3(2.8, 3.0, span + 0.2))
			for k in 6:
				var a := PI * (k + 0.5) / 6
				var off := basis * Vector3(0, 0, -cos(a) * (span * 0.5 - 1.5))
				m.box(Transform3D(basis, Vector3(mid.x, top - 2.5 - sin(a) * 0.0, mid.z) + off - Vector3(0, (1.0 - sin(a)) * 4.0, 0)), Vector3(2.6, 1.2, 2.0))
	_commit(m, stone)


func _lighthouse(xf: Transform3D) -> void:
	var m := MeshAcc.new()
	m.use_colors = true
	for i in 7:
		m.color = Color(0.95, 0.95, 0.93) if i % 2 == 0 else Color(0.75, 0.12, 0.1)
		m.cylinder(xf * Transform3D(Basis(), Vector3(0, i * 4.0, 0)), 4.2 - i * 0.18, 4.2 - (i + 1) * 0.18, 0.0, 4.0, 16, false)
	m.color = Color(0.2, 0.2, 0.22)
	m.cylinder(xf * Transform3D(Basis(), Vector3(0, 28, 0)), 4.0, 4.0, 0.0, 0.5, 16, true)
	m.cylinder(xf * Transform3D(Basis(), Vector3(0, 31.5, 0)), 2.6, 0.4, 0.0, 2.0, 12, true)
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 0.6
	_commit(m, mat)
	var g := MeshAcc.new()
	g.cylinder(xf * Transform3D(Basis(), Vector3(0, 28.5, 0)), 2.5, 2.5, 0.0, 3.0, 12, false)
	_commit(g, Mats.std("beacon", Color(1, 0.95, 0.8), 0.0, 0.2, Color(1, 0.9, 0.6), 3.0), false)


func _castle(xf: Transform3D) -> void:
	var m := MeshAcc.new()
	var s := 30.0
	for i in 4:
		var a := TAU * i / 4.0
		var c := Vector3(cos(a) * s, 0, sin(a) * s)
		var c2 := Vector3(cos(a + TAU / 4.0) * s, 0, sin(a + TAU / 4.0) * s)
		var mid := (c + c2) * 0.5
		var len := c.distance_to(c2)
		var basis := Basis.looking_at((c2 - c).normalized(), Vector3.UP)
		m.box(xf * Transform3D(basis, mid + Vector3(0, 5, 0)), Vector3(2.5, 12, len))
		for k in int(len / 3.0):
			var off := basis * Vector3(0, 0, -len * 0.5 + 1.5 + k * 3.0)
			m.box(xf * Transform3D(basis, mid + off + Vector3(0, 11.6, 0)), Vector3(2.6, 1.3, 1.4))
		m.cylinder(xf * Transform3D(Basis(), c - Vector3(0, 2, 0)), 5.0, 4.4, 0.0, 19.0, 14, true)
		m.cylinder(xf * Transform3D(Basis(), c + Vector3(0, 17, 0)), 4.8, 0.2, 0.0, 6.0, 14, false)
	m.box(xf * Transform3D(Basis(), Vector3(0, 9, 0)), Vector3(16, 22, 16))
	_commit(m, stone_grey)


func _windmill(xf: Transform3D) -> void:
	var m := MeshAcc.new()
	m.cylinder(xf * Transform3D(Basis(), Vector3(0, -1, 0)), 4.0, 2.6, 0.0, 15.0, 10, false)
	m.cylinder(xf * Transform3D(Basis(), Vector3(0, 14, 0)), 3.0, 0.3, 0.0, 4.0, 10, false)
	_commit(m, Mats.std("windmill_white", Color(0.92, 0.9, 0.85), 0.0, 0.75))
	var hub := Node3D.new()
	add_child(hub)
	hub.global_transform = xf * Transform3D(Basis(), Vector3(0, 14.5, 3.0))
	var b := MeshAcc.new()
	for i in 4:
		var bx := Transform3D(Basis(Vector3.BACK, TAU * i / 4.0), Vector3.ZERO)
		b.box(bx * Transform3D(Basis(), Vector3(0, 6.0, 0)), Vector3(1.8, 11.0, 0.15))
		b.box(bx * Transform3D(Basis(), Vector3(0, 6.0, 0.15)), Vector3(0.25, 12.0, 0.25))
	var mi := MeshInstance3D.new()
	mi.mesh = b.to_mesh(Mats.std("wood", Color(0.45, 0.33, 0.22), 0.0, 0.85))
	hub.add_child(mi)
	windmills.append(hub)


func _circuit_props() -> void:
	# grandstands + start gantry at the grand prix start line
	for e in wd.events:
		if e.id != "grand_prix":
			continue
		var cp: Dictionary = e.checkpoints[e.checkpoints.size() - 1]
		var p := Vector3(cp.pos[0], cp.pos[1], cp.pos[2])
		var d := Vector3(cp.dir[0], 0, cp.dir[1]).normalized()
		var rt := d.cross(Vector3.UP).normalized()
		var basis := Basis.looking_at(d, Vector3.UP)
		var m := MeshAcc.new()
		for side: float in [-1.0, 1.0]:
			for k in 10:
				var off := rt * side * (17.0 + k * 1.4) + Vector3(0, k * 0.9 + 0.45, 0)
				m.box(Transform3D(basis, p + off - d * 30.0), Vector3(1.4, 0.9 + k * 0.0, 120.0))
			m.box(Transform3D(basis, p + rt * side * 31.0 + Vector3(0, 7.5, 0) - d * 30.0), Vector3(1.0, 15.0, 120.0))
			m.box(Transform3D(basis, p + rt * side * 24.0 + Vector3(0, 15.5, 0) - d * 30.0), Vector3(16.0, 0.5, 122.0))
		# gantry over the line
		for side: float in [-1.0, 1.0]:
			m.box(Transform3D(basis, p + rt * side * 10.5 + Vector3(0, 4.0, 0)), Vector3(0.8, 8.0, 0.8))
		m.box(Transform3D(basis, p + Vector3(0, 8.2, 0)), Vector3(22.0, 1.4, 1.2))
		_commit(m, Mats.concrete())
