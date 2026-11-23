class_name SetPieces
extends RefCounted
## Hand-designed, procedurally modelled set pieces that give each zone its
## identity and act as landmarks for spatial memory.


static func build_all(tb: TrackBuilder) -> void:
	var root := Node3D.new()
	root.name = "SetPieces"
	tb.root.add_child(root)
	_aqueduct(tb, root)
	_start_gantry(tb, root)
	_lower_falls(tb, root)
	_river_arch(tb, root)
	_giants_log(tb, root)
	_ridge(tb, root)
	_ruins(tb, root)
	_mill(tb, root)
	_cave(tb, root)
	_elder_tree(tb, root)
	_background(tb, root)


# =================================================================== Z1 Aqueduct
static func _roof_range(tb: TrackBuilder) -> Vector2i:
	var n := tb.main.size()
	var first := -1
	var last := -1
	for i in n:
		if tb.main.style[i] == "roof":
			if first < 0:
				first = i
			last = i
	return Vector2i(first, last)


static func _aqueduct(tb: TrackBuilder, root: Node3D) -> void:
	var node := Node3D.new()
	node.name = "Aqueduct"
	root.add_child(node)
	var r := _roof_range(tb)
	var sp := tb.main
	var stone := Mats.triplanar("stone")
	var walls := MeshBuilder.new()
	var cols := MeshBuilder.new()
	var vines := MeshBuilder.new()
	var deco := MeshBuilder.new()
	# outer wall profile (lateral offset beyond hw, height relative to deck)
	var prof := [[0.58, 0.0], [0.85, -0.55], [0.85, -1.0], [0.6, -1.05], [0.6, -60.0]]
	for side: int in [-1, 1]:
		var base := walls.vcount()
		var rows := 0
		for k in range(r.x, r.y + 1):
			var hw := sp.width[k] * 0.5
			var rv := sp.right[k] * float(side)
			var ground := tb.ground_y(sp.pos[k].x + rv.x * (hw + 1.0), sp.pos[k].z + rv.z * (hw + 1.0)) - 1.5
			for pp in prof:
				var lat: float = hw + float(pp[0])
				var dy: float = pp[1]
				var p := sp.pos[k] + rv * lat + Vector3.UP * dy
				if dy < -10.0:
					p.y = minf(ground, sp.pos[k].y - 2.0)
				walls.add_vertex(p, rv, Vector2(sp.dist[k], p.y), Color(1, 1, 1, 0.8))
			rows += 1
		var pc := prof.size()
		for s in rows - 1:
			for c in pc - 1:
				var a := base + s * pc + c
				var b := a + 1
				var d := a + pc
				var e := d + 1
				if side == 1:
					walls.quad(a, b, e, d)
				else:
					walls.quad(a, d, e, b)
		# buttresses, vines, lanterns
		var step := int(14.0 / sp.spacing)
		var count := 0
		for k in range(r.x + 4, r.y - 3, step):
			count += 1
			var hw := sp.width[k] * 0.5
			var rv := sp.right[k] * float(side)
			var p := sp.pos[k] + rv * (hw + 1.3)
			var ground := tb.ground_y(p.x, p.z) - 1.5
			var top := sp.pos[k].y - 1.1
			if top - ground > 1.5:
				var b := Basis.looking_at(sp.tan[k], Vector3.UP)
				var h := top - ground
				MeshLib.box(cols, Transform3D(b, Vector3(p.x, ground + h * 0.5, p.z)), Vector3(1.6, h, 2.4), Color(0.95, 0.93, 0.9, 0.9), 0.25)
				MeshLib.box(cols, Transform3D(b, Vector3(p.x, top + 0.15, p.z) + rv * -0.1), Vector3(2.0, 0.3, 2.9), Color(1, 1, 1, 0.5))
			# hanging vines between buttresses
			var vk := k + step / 2
			if vk < r.y:
				var vp := sp.pos[vk] + sp.right[vk] * float(side) * (sp.width[vk] * 0.5 + 0.9)
				var vb := Basis.looking_at(-sp.right[vk] * float(side), Vector3.UP)
				var vlen := tb.rng.randf_range(3.0, 7.5)
				for v in 3:
					var off := sp.tan[vk] * tb.rng.randf_range(-2.0, 2.0)
					var vc := Color(0.55, 0.8, 0.45, 0.6)
					MeshLib.card(vines, Transform3D(vb.rotated(Vector3.UP, 0.0), vp + off + Vector3.DOWN * vlen), 1.6, vlen, Rect2(0.5, 0.5, 0.5, 0.5), vc)
			# lanterns on the parapet every other buttress (alternating sides)
			if (count + (1 if side > 0 else 0)) % 2 == 0:
				var lp := sp.pos[k] + sp.right[k] * float(side) * (sp.width[k] * 0.5 + 0.3) + Vector3.UP * 1.15
				var lant := MeshLib.lantern_post(k)
				var lb := Basis.looking_at(sp.right[k] * float(side), Vector3.UP)
				deco.append_builder(lant["solid"], Transform3D(lb.scaled(Vector3(0.9, 0.9, 0.9)), lp))
				var gl := MeshBuilder.new()
				gl.append_builder(lant["glow"], Transform3D(lb.scaled(Vector3(0.9, 0.9, 0.9)), lp))
				tb.add_static_mesh(node, gl, Mats.glow(Color(1.0, 0.78, 0.4), 3.0), "LanternGlow", false)
	walls.recompute_normals()
	tb.add_static_mesh(node, walls, stone, "AqueductWalls")
	tb.add_static_mesh(node, cols, stone, "Buttresses")
	tb.add_static_mesh(node, vines, Mats.cards(Color(0.8, 1.0, 0.75), "vines"), "Vines", false)
	tb.add_static_mesh(node, deco, Mats.vcol(0.8), "Lanterns")
	_portal(tb, node, r.y)


static func _portal(tb: TrackBuilder, node: Node3D, lip_i: int) -> void:
	## The east face of the aqueduct: an arched river portal under the jump lip.
	var sp := tb.main
	var k := lip_i
	var pos := sp.pos[k]
	var fwd := sp.tan[k]
	fwd.y = 0.0
	fwd = fwd.normalized()
	var right := fwd.cross(Vector3.UP).normalized()
	var hw := sp.width[k] * 0.5 + 0.85
	var river_y := tb.mark_pos("river_land").y - 0.4
	var deck := pos.y
	var arch_w := 7.5
	var arch_h := 8.5
	var mb := MeshBuilder.new()
	var segs := 16
	var face := pos + fwd * 0.6
	# arch boundary from left foot over the top to right foot, outer boundary mirrored
	var arch_pts: Array[Vector3] = []
	var outer_pts: Array[Vector3] = []
	for i in segs + 1:
		var t := float(i) / segs
		var a := PI * (1.0 - t)
		var ax := cos(a) * arch_w
		var ay := river_y + arch_h - arch_w + sin(a) * arch_w
		if t < 0.0001:
			ay = river_y
		arch_pts.append(face + right * ax + Vector3.UP * (ay - face.y + face.y) - Vector3.UP * face.y + Vector3.UP * 0.0)
		var ox := lerpf(-hw, hw, t)
		outer_pts.append(face + right * ox + Vector3.UP * (deck + 0.1 - face.y))
	# feet: connect left/right foot down to river level
	for i in segs + 1:
		arch_pts[i].y = river_y + arch_h - arch_w + sin(PI * (1.0 - float(i) / segs)) * arch_w if i > 0 and i < segs else river_y
	var c := Color(1, 1, 1, 0.7)
	for i in segs:
		var a0 := mb.add_vertex(arch_pts[i], fwd, Vector2.ZERO, c)
		var a1 := mb.add_vertex(arch_pts[i + 1], fwd, Vector2.ZERO, c)
		var o1 := mb.add_vertex(outer_pts[i + 1], fwd, Vector2.ZERO, c)
		var o0 := mb.add_vertex(outer_pts[i], fwd, Vector2.ZERO, c)
		mb.quad(a0, o0, o1, a1)
	# side panels down to the ground outside the arch
	for side: int in [-1, 1]:
		var top := face + right * hw * side + Vector3.UP * (deck + 0.1 - face.y)
		var foot := face + right * arch_w * side + Vector3.UP * (river_y - face.y)
		var corner := face + right * hw * side + Vector3.UP * (river_y - 2.0 - face.y)
		var i0 := mb.add_vertex(top, fwd, Vector2.ZERO, c)
		var i1 := mb.add_vertex(corner, fwd, Vector2.ZERO, c)
		var i2 := mb.add_vertex(foot, fwd, Vector2.ZERO, c)
		if side == -1:
			mb.tri(i0, i1, i2)
		else:
			mb.tri(i0, i2, i1)
	# intrados: the arch's inner vault going back into the tunnel
	for i in segs:
		var a0 := arch_pts[i]
		var a1 := arch_pts[i + 1]
		var b0 := a0 - fwd * 6.0
		var b1 := a1 - fwd * 6.0
		var n := ((a0 + a1) * 0.5 - (face + Vector3.UP * (river_y + arch_h - arch_w - face.y))).normalized() * -1.0
		var i0 := mb.add_vertex(a0, n, Vector2.ZERO, c * 0.7)
		var i1 := mb.add_vertex(a1, n, Vector2.ZERO, c * 0.7)
		var i2 := mb.add_vertex(b1, n, Vector2.ZERO, c * 0.4)
		var i3 := mb.add_vertex(b0, n, Vector2.ZERO, c * 0.4)
		mb.quad(i0, i3, i2, i1)
	tb.add_static_mesh(node, mb, Mats.triplanar("stone"), "Portal")
	# keystone + voussoir accents
	var acc := MeshBuilder.new()
	for i in range(1, segs, 2):
		var p := arch_pts[i]
		var dir := (p - (face + Vector3.UP * (river_y + arch_h - arch_w - face.y))).normalized()
		var b := Basis.looking_at(fwd, dir)
		var sz := Vector3(1.0, 1.4 if i == segs / 2 else 1.0, 0.8)
		MeshLib.box(acc, Transform3D(b, p + dir * 0.5 + fwd * 0.25), sz, Color(0.92, 0.88, 0.8, 0.4))
	tb.add_static_mesh(node, acc, Mats.triplanar("stone"), "Voussoirs")
	# dark tunnel interior + portcullis grate (blocks reversing into the tunnel)
	var dark := MeshBuilder.new()
	MeshLib.box(dark, Transform3D(Basis.looking_at(fwd, Vector3.UP), face - fwd * 6.5 + Vector3.UP * (river_y + arch_h * 0.5 - face.y)), Vector3(arch_w * 2.0, arch_h + 1.0, 0.5), Color(0.02, 0.025, 0.03))
	var dm := StandardMaterial3D.new()
	dm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	dm.albedo_color = Color(0.015, 0.02, 0.025)
	tb.add_static_mesh(node, dark, dm, "TunnelDark", false)
	var grate := MeshBuilder.new()
	for i in 9:
		var x := lerpf(-arch_w * 0.9, arch_w * 0.9, float(i) / 8.0)
		var bp := face - fwd * 1.5 + right * x + Vector3.UP * (river_y - face.y)
		var hh := arch_h - arch_w + sqrt(maxf(arch_w * arch_w - x * x, 0.0)) - 0.2
		MeshLib.box(grate, Transform3D(Basis(), bp + Vector3.UP * hh * 0.5), Vector3(0.14, hh, 0.14), Color(0.18, 0.17, 0.16))
	for j in 3:
		var y := river_y + 1.0 + j * 2.2
		MeshLib.box(grate, Transform3D(Basis.looking_at(fwd, Vector3.UP), face - fwd * 1.5 + Vector3.UP * (y - face.y)), Vector3(arch_w * 1.8, 0.12, 0.12), Color(0.18, 0.17, 0.16))
	tb.add_static_mesh(node, grate, Mats.vcol(0.5, 0.6), "Grate")
	tb.add_box_collider(node, Transform3D(Basis.looking_at(fwd, Vector3.UP), face - fwd * 1.5 + Vector3.UP * (river_y + 3.0 - face.y)), Vector3(arch_w * 2.0, 6.0, 0.4))


static func _start_gantry(tb: TrackBuilder, root: Node3D) -> void:
	var node := Node3D.new()
	node.name = "StartGantry"
	root.add_child(node)
	var k := tb.mark_index("start_line")
	var sp := tb.main
	var pos := sp.pos[k]
	var b := Basis.looking_at(sp.tan[k], Vector3.UP)
	var hw := sp.width[k] * 0.5 + 1.2
	var mb := MeshBuilder.new()
	for side: int in [-1, 1]:
		var pp := pos + sp.right[k] * hw * side
		MeshLib.box(mb, Transform3D(b, pp + Vector3.UP * 3.5), Vector3(1.3, 7.0, 1.3), Color(0.95, 0.92, 0.88), 0.2)
		MeshLib.box(mb, Transform3D(b, pp + Vector3.UP * 7.2), Vector3(1.7, 0.5, 1.7), Color(1, 1, 1))
	MeshLib.box(mb, Transform3D(b, pos + Vector3.UP * 6.6), Vector3(hw * 2.0 + 1.0, 1.0, 0.7), Color(0.55, 0.38, 0.22))
	tb.add_static_mesh(node, mb, Mats.triplanar("stone"), "Pillars")
	# chequered start line painted on the deck
	var line := MeshBuilder.new()
	var cells := 16
	for i in cells:
		for j in 2:
			var c := Color(0.95, 0.95, 0.95) if (i + j) % 2 == 0 else Color(0.08, 0.08, 0.1)
			var x0 := lerpf(-hw + 1.2, hw - 1.2, float(i) / cells)
			var x1 := lerpf(-hw + 1.2, hw - 1.2, float(i + 1) / cells)
			var z0 := float(j) * 0.7 - 0.7
			var z1 := z0 + 0.7
			var pa := pos + sp.right[k] * x0 + sp.tan[k] * z0 + Vector3.UP * 0.075
			var pb := pos + sp.right[k] * x1 + sp.tan[k] * z0 + Vector3.UP * 0.075
			var pc := pos + sp.right[k] * x1 + sp.tan[k] * z1 + Vector3.UP * 0.075
			var pd := pos + sp.right[k] * x0 + sp.tan[k] * z1 + Vector3.UP * 0.075
			var i0 := line.add_vertex(pa, Vector3.UP, Vector2.ZERO, c)
			line.add_vertex(pb, Vector3.UP, Vector2.ZERO, c)
			line.add_vertex(pc, Vector3.UP, Vector2.ZERO, c)
			line.add_vertex(pd, Vector3.UP, Vector2.ZERO, c)
			line.quad(i0, i0 + 3, i0 + 2, i0 + 1)
	tb.add_static_mesh(node, line, Mats.vcol(0.6), "StartLine", false)
	# banner
	var banner := Label3D.new()
	banner.text = "WILDSPARK  GRAND  PRIX"
	banner.font_size = 96
	banner.pixel_size = 0.012
	banner.modulate = Color(1.0, 0.92, 0.6)
	banner.outline_size = 18
	banner.outline_modulate = Color(0.25, 0.12, 0.05)
	banner.transform = Transform3D(b, pos + Vector3.UP * 6.6 - sp.tan[k] * 0.4)
	node.add_child(banner)
	# countdown lamps (the race manager toggles their materials)
	var lamps := Node3D.new()
	lamps.name = "CountdownLamps"
	node.add_child(lamps)
	for i in 3:
		var lm := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 0.38
		sm.height = 0.76
		lm.mesh = sm
		lm.position = pos + Vector3.UP * 5.6 + sp.right[k] * (float(i) - 1.0) * 1.3 - sp.tan[k] * 0.45
		var m := StandardMaterial3D.new()
		m.albedo_color = Color(0.2, 0.05, 0.05)
		m.emission_enabled = true
		m.emission = Color(1, 0.1, 0.05)
		m.emission_energy_multiplier = 0.0
		lm.material_override = m
		lm.name = "Lamp%d" % i
		lamps.add_child(lm)


# =================================================================== Z2/Z3 river & falls
static func _lower_falls(tb: TrackBuilder, root: Node3D) -> void:
	var node := Node3D.new()
	node.name = "LowerFalls"
	root.add_child(node)
	var sp := tb.main
	var k := tb.mark_index("falls_lip")
	# lip index: last river-style sample
	var lip := k
	while lip + 1 < sp.size() and sp.style[lip + 1] == "river":
		lip += 1
	var p := sp.pos[lip]
	var fwd := Vector3(sp.tan[lip].x, 0, sp.tan[lip].z).normalized()
	var right := fwd.cross(Vector3.UP).normalized()
	var hw := sp.width[lip] * 0.5 + 1.0
	var pool_y := tb.ground_y(p.x + fwd.x * 12.0, p.z + fwd.z * 12.0) + 0.6
	var drop := p.y + 0.42 - pool_y
	var mb := MeshBuilder.new()
	var rows := 12
	var colsn := 8
	for j in rows + 1:
		var t := float(j) / rows
		var out := 1.6 * sqrt(t) + t * 0.8
		for c in colsn:
			var f := float(c) / (colsn - 1) * 2.0 - 1.0
			var q := p + Vector3.UP * 0.42 + fwd * out + right * f * hw * (1.0 + t * 0.12) + Vector3.DOWN * drop * t
			var foam := smoothstep(0.55, 1.0, t)
			mb.add_vertex(q, -fwd, Vector2(f * hw, t * drop * 1.4), Color(absf(f) * 0.4, foam, 2.0, 1.0))
	for j in rows:
		for c in colsn - 1:
			var a := j * colsn + c
			mb.quad(a, a + colsn, a + colsn + 1, a + 1)
			mb.quad(a, a + 1, a + colsn + 1, a + colsn)   # double-sided
	var mi := tb.add_static_mesh(node, mb, Mats.water("falls"), "FallSheet", false)
	mi.sorting_offset = 1.0
	# plunge pool
	var pool_c := p + fwd * 11.0
	_pond_disc(tb, node, Vector3(pool_c.x, pool_y, pool_c.z), 13.0, "pond", 0.8)
	# framing boulders on both sides of the lip
	var rocks := MeshBuilder.new()
	for side: int in [-1, 1]:
		for i in 3:
			var rp := p + right * float(side) * (hw + 1.5 + i * 2.2) + fwd * (i * 2.5 - 1.0)
			var gy := tb.ground_y(rp.x, rp.z)
			var rm := MeshLib.rock(400 + i * 7 + (side + 1) * 31, 0)
			var s := tb.rng.randf_range(2.0, 3.4)
			rocks.append_builder(rm, Transform3D(Basis(Vector3.UP, tb.rng.randf() * TAU).scaled(Vector3(s, s * 1.2, s)), Vector3(rp.x, gy - 0.8, rp.z)))
	tb.add_static_mesh(node, rocks, Mats.triplanar("rock"), "FallRocks")
	EnvLife.mist(node, pool_c + Vector3.UP * (pool_y - pool_c.y + 0.5), hw * 2.0)
	tb.landmarks.append({"name": "lower_falls", "pos": p})


static func _pond_disc(tb: TrackBuilder, parent: Node3D, c: Vector3, r: float, kind: String, foam_edge := 0.6) -> void:
	var mb := MeshBuilder.new()
	var rings := 6
	var segs := 28
	var ci := mb.add_vertex(c, Vector3.UP, Vector2(c.x, c.z), Color(0, 0, 0.3, 1))
	for ring in range(1, rings + 1):
		var rr := r * float(ring) / rings
		for s in segs:
			var a := TAU * float(s) / segs
			var q := c + Vector3(cos(a) * rr, 0, sin(a) * rr)
			var edge := float(ring) / rings
			mb.add_vertex(q, Vector3.UP, Vector2(q.x, q.z), Color(edge, smoothstep(0.8, 1.0, edge) * foam_edge, 0.3, 1))
	for s in segs:
		var s2 := (s + 1) % segs
		mb.tri(ci, 1 + s2, 1 + s)
	for ring in range(1, rings):
		var base0 := 1 + (ring - 1) * segs
		var base1 := 1 + ring * segs
		for s in segs:
			var s2 := (s + 1) % segs
			mb.quad(base0 + s, base0 + s2, base1 + s2, base1 + s)
	tb.add_static_mesh(parent, mb, Mats.water(kind), "Pond", false)
	tb.terrain.mark_water_disc(c.x, c.z, r * 0.85)


static func _river_arch(tb: TrackBuilder, root: Node3D) -> void:
	## "Moss Arch": a natural stone arch spanning the river and both banks.
	var k := tb.mark_index("gravel_bar")
	var sp := tb.main
	var p := sp.pos[k]
	var right := sp.right[k]
	right.y = 0
	right = right.normalized()
	var span := 26.0
	var nz := MeshLib.make_noise(99, 0.25, 3)
	var path := PackedVector3Array()
	var rad := PackedFloat32Array()
	for i in 15:
		var t := float(i) / 14.0
		var a := PI * t
		var q := p + right * (-cos(a) * span) + Vector3.UP * (sin(a) * 14.0 - 2.0)
		path.append(q)
		rad.append(lerpf(3.8, 2.2, sin(a)))
	var mb := MeshBuilder.new()
	MeshLib.tube(mb, path, rad, 10, func(t: float, _a: float, _p: Vector3) -> Color: return Color(0.9, 0.86, 0.8, 1.0), 0.2, false, nz, 0.35)
	var node := Node3D.new()
	node.name = "MossArch"
	root.add_child(node)
	tb.add_static_mesh(node, mb, Mats.triplanar("rock"), "Arch")
	for side: int in [-1, 1]:
		var foot := p + right * span * side
		tb.add_cylinder_collider(node, Vector3(foot.x, tb.ground_y(foot.x, foot.z) - 1.0, foot.z), 3.6, 10.0)
		tb.obstacles.append([foot, 3.6, "arch_leg"])
	# vines hanging from the arch
	var vines := MeshBuilder.new()
	for i in range(3, 12):
		var q := path[i]
		var len := tb.rng.randf_range(2.0, 5.0)
		MeshLib.card(vines, Transform3D(Basis.looking_at(sp.tan[k], Vector3.UP), q + Vector3.DOWN * (rad[i] + len - 0.3)), 1.4, len, Rect2(0.5, 0.5, 0.5, 0.5), Color(0.6, 0.85, 0.5, 0.7))
	tb.add_static_mesh(node, vines, Mats.cards(Color(0.8, 1.0, 0.75), "vines"), "ArchVines", false)
	tb.landmarks.append({"name": "moss_arch", "pos": p})


# =================================================================== Z4 log & ridge
static func _style_range(sp: SplinePath, st: String) -> Vector2i:
	var a := -1
	var b := -1
	for i in sp.size():
		if sp.style[i] == st:
			if a < 0:
				a = i
			b = i
	return Vector2i(a, b)


static func _giants_log(tb: TrackBuilder, root: Node3D) -> void:
	var sp: SplinePath = tb.branches.get("giants_log")
	if sp == null:
		return
	var rr := _style_range(sp, "log_ramp")
	if rr.x < 0:
		return
	var node := Node3D.new()
	node.name = "GiantsLog"
	root.add_child(node)
	var R := 2.5
	var path := PackedVector3Array()
	var rad := PackedFloat32Array()
	var start := maxi(rr.x - 6, 0)
	# extend the trunk backwards into the mound so it looks buried
	var back := sp.pos[rr.x] - sp.tan[rr.x] * 7.0 - sp.up[rr.x] * R + Vector3.DOWN * 1.2
	path.append(back)
	rad.append(R * 1.05)
	for k in range(rr.x, rr.y + 2, 2):
		var kk := mini(k, sp.size() - 1)
		path.append(sp.pos[kk] - sp.up[kk] * (R - 0.05))
		rad.append(R * lerpf(1.0, 0.92, float(k - rr.x) / maxf(rr.y - rr.x, 1)))
	var mb := MeshBuilder.new()
	var nz := MeshLib.make_noise(5, 0.6)
	MeshLib.tube(mb, path, rad, 16, func(_t: float, _a: float, _p: Vector3) -> Color: return Color(0.95, 0.9, 0.86, 1.0), 0.3, false, nz, 0.05)
	tb.add_static_mesh(node, mb, Mats.triplanar("bark"), "Trunk")
	# broken, splintered end at the lip
	var end := path[path.size() - 1]
	var tdir := (path[path.size() - 1] - path[path.size() - 2]).normalized()
	var spl := MeshBuilder.new()
	for i in 9:
		var a := TAU * float(i) / 9.0
		var off := Vector3(cos(a), sin(a), 0) * R * 0.75
		var b := Basis.looking_at(tdir, Vector3.UP)
		var base_p := end + b * off
		if (b * off).y > R * 0.55:
			continue   # keep the driving surface clean
		var tipp := base_p + tdir * tb.rng.randf_range(0.8, 2.2) + (b * off).normalized() * 0.3
		MeshLib.tube(spl, PackedVector3Array([base_p, tipp]), PackedFloat32Array([0.45, 0.02]), 4, func(_t: float, _a: float, _p: Vector3) -> Color: return Color(0.9, 0.75, 0.55))
	tb.add_static_mesh(node, spl, Mats.vcol(0.9), "Splinters")
	# supporting boulder under the high end and the buried mound at the low end
	var rocks := MeshBuilder.new()
	var under := end - tdir * 4.0
	var gy := tb.ground_y(under.x, under.z)
	var s := maxf((under.y - R - gy) * 0.75, 2.0)
	rocks.append_builder(MeshLib.rock(777, 0), Transform3D(Basis().scaled(Vector3(s * 1.3, s, s * 1.2)), Vector3(under.x, gy - 0.5, under.z)))
	tb.add_static_mesh(node, rocks, Mats.triplanar("rock"), "LogRest")
	tb.add_cylinder_collider(node, Vector3(under.x, gy - 0.5, under.z), s * 1.1, maxf(under.y - R - gy - 0.3, 1.0))
	# shelf fungus on the trunk sides (decor)
	var fungus := MeshBuilder.new()
	for i in range(2, path.size() - 1):
		for side: int in [-1, 1]:
			if tb.rng.randf() < 0.6:
				var b := Basis.looking_at((path[i + 1] - path[i]).normalized(), Vector3.UP)
				var sidev := b.x * float(side)
				var fp := path[i] + sidev * rad[i] * 0.98 + Vector3.DOWN * tb.rng.randf_range(0.2, 1.2)
				MeshLib.blob(fungus, fp + sidev * 0.25, Vector3(0.55, 0.12, 0.45), 1, null, 0.0, Color(0.7, 0.45, 0.25), Color(0.95, 0.8, 0.5))
	tb.add_static_mesh(node, fungus, Mats.vcol(0.8), "Fungus")
	tb.landmarks.append({"name": "giants_log", "pos": end})


static func _ridge(tb: TrackBuilder, root: Node3D) -> void:
	var sp: SplinePath = tb.branches.get("giants_log")
	if sp == null:
		return
	var rr := _style_range(sp, "ridge")
	if rr.x < 0:
		return
	var node := Node3D.new()
	node.name = "Ridge"
	root.add_child(node)
	var mb := MeshBuilder.new()
	var split := rr.y
	for k in sp.size():
		if sp.tags[k] == "shelf_split":
			split = k
			break
	for k in range(rr.x, rr.y, 5):
		if absi(k - split) < 14:
			continue   # leave the Shelf Rock take-off clear
		for side: int in [-1, 1]:
			if tb.rng.randf() < 0.35:
				continue   # gaps: falling off into the hollow is possible
			var hw := sp.width[k] * 0.5
			var p := sp.pos[k] + sp.right[k] * float(side) * (hw + 1.4)
			var s := tb.rng.randf_range(1.0, 1.7)
			mb.append_builder(MeshLib.rock(k * 3 + side, 0), Transform3D(Basis(Vector3.UP, tb.rng.randf() * TAU).scaled(Vector3(s, s * 0.8, s)), Vector3(p.x, p.y - 0.6, p.z)))
			tb.add_cylinder_collider(node, Vector3(p.x, p.y - 0.6, p.z), s * 0.95, s * 1.4)
	tb.add_static_mesh(node, mb, Mats.triplanar("rock"), "RidgeRocks")
	# shelf rock slab: a rock mass under the stage-2 ramp
	var sh: SplinePath = tb.branches.get("shelf_rock")
	if sh != null:
		var sr := _style_range(sh, "slab")
		if sr.x >= 0:
			var mid := sh.pos[(sr.x + sr.y) / 2]
			var gy := tb.ground_y(mid.x, mid.z)
			var slab := MeshBuilder.new()
			var hgt := maxf(mid.y - gy, 1.0)
			slab.append_builder(MeshLib.rock(4242, 2), Transform3D(Basis.looking_at(sh.tan[sr.x], Vector3.UP).scaled(Vector3(2.6, hgt * 0.9, 4.0)), Vector3(mid.x, gy - 0.4, mid.z)))
			tb.add_static_mesh(node, slab, Mats.triplanar("rock"), "ShelfMass")


# =================================================================== Z5 ruins
static func _ruins(tb: TrackBuilder, root: Node3D) -> void:
	var node := Node3D.new()
	node.name = "Ruins"
	root.add_child(node)
	var sp := tb.main
	var stone := Mats.triplanar("stone")
	# entry arch over the corridor
	var k := tb.mark_index("swing_log")
	var k0 := maxi(k - int(4.0 / sp.spacing), 0)
	var p := sp.pos[k0]
	var hw := sp.width[k0] * 0.5 + 1.2
	var b := Basis.looking_at(sp.tan[k0], Vector3.UP)
	var mb := MeshBuilder.new()
	for side: int in [-1, 1]:
		var pp := p + sp.right[k0] * hw * side
		mb.append_builder(MeshLib.ruin_pillar(70 + side, false), Transform3D(b, pp + Vector3.DOWN * 0.3))
		tb.add_cylinder_collider(node, pp + Vector3.DOWN * 0.3, 0.7, 6.0)
	var segs := 9
	for i in segs:
		var a0 := PI * float(i) / segs
		var a1 := PI * float(i + 1) / segs
		var am := (a0 + a1) * 0.5
		var cpos := p + sp.right[k0] * (-cos(am) * hw) + Vector3.UP * (5.6 + sin(am) * hw * 0.55)
		var dir := (sp.right[k0] * -cos(am) + Vector3.UP * sin(am)).normalized()
		var bb := Basis.looking_at(sp.tan[k0], dir)
		if i == 6:
			continue   # a missing stone: the arch is ancient
		MeshLib.box(mb, Transform3D(bb, cpos), Vector3(hw * 0.36, 0.9, 1.1), Color(0.9, 0.88, 0.82, 0.9))
	tb.add_static_mesh(node, mb, stone, "EntryArch")
	# scattered pillars & fallen blocks beside the corridor
	var deco := MeshBuilder.new()
	var k1 := tb.mark_index("od_pad")
	for kk in range(k0, k1, 7):
		for side: int in [-1, 1]:
			if tb.rng.randf() < 0.45:
				continue
			var hw2 := sp.width[kk] * 0.5
			var pp := sp.pos[kk] + sp.right[kk] * float(side) * (hw2 + tb.rng.randf_range(3.0, 7.0))
			var gy := tb.ground_y(pp.x, pp.z)
			if tb.rng.randf() < 0.5:
				deco.append_builder(MeshLib.ruin_pillar(kk * 2 + side, true), Transform3D(Basis(Vector3.UP, tb.rng.randf() * TAU), Vector3(pp.x, gy - 0.2, pp.z)))
			else:
				var bb := Basis(Vector3(tb.rng.randf(), tb.rng.randf(), tb.rng.randf()).normalized(), tb.rng.randf_range(0.1, 0.5))
				MeshLib.box(deco, Transform3D(bb, Vector3(pp.x, gy + 0.3, pp.z)), Vector3(1.8, 0.9, 1.0), Color(0.88, 0.86, 0.8, 1.0), 0.1)
	tb.add_static_mesh(node, deco, stone, "RuinDeco")
	_owl_statue(tb, node)


static func _owl_statue(tb: TrackBuilder, node: Node3D) -> void:
	## The Guardian: a 13 m stone owl watching over the Rootwork ruins.
	var sp := tb.main
	var k := tb.mark_index("flytraps")
	var side := 1.0
	var base := sp.pos[k] + sp.right[k] * side * (sp.width[k] * 0.5 + 14.0)
	base.y = tb.ground_y(base.x, base.z) - 0.5
	var face_dir := -sp.right[k] * side
	var b := Basis.looking_at(face_dir, Vector3.UP)
	var xf := Transform3D(b, base)
	var mb := MeshBuilder.new()
	var glow := MeshBuilder.new()
	var nz := MeshLib.make_noise(31, 0.35)
	var c0 := Color(0.75, 0.72, 0.66, 1.0)
	var c1 := Color(1.0, 0.97, 0.9, 1.0)
	# plinth
	MeshLib.box(mb, xf * Transform3D(Basis(), Vector3(0, 1.0, 0)), Vector3(8.0, 2.0, 8.0), c1, 0.6)
	var tmp := MeshBuilder.new()
	MeshLib.blob(tmp, Vector3(0, 6.0, 0), Vector3(3.6, 4.4, 3.2), 2, nz, 0.06, c0, c1)        # body
	MeshLib.blob(tmp, Vector3(0, 11.0, 0.2), Vector3(3.0, 2.6, 2.7), 2, nz, 0.05, c0, c1)     # head
	for s: float in [-1.0, 1.0]:
		MeshLib.blob(tmp, Vector3(3.3 * s, 6.2, -0.4), Vector3(1.0, 3.6, 2.4), 2, nz, 0.08, c0, c1)  # wings
		MeshLib.tube(tmp, PackedVector3Array([Vector3(1.8 * s, 12.8, 0), Vector3(2.4 * s, 14.6, -0.3)]), PackedFloat32Array([0.8, 0.05]), 6,
			func(_t: float, _a: float, _p: Vector3) -> Color: return c1)  # ear tufts
		MeshLib.blob(tmp, Vector3(1.0 * s, 1.9, 1.4), Vector3(0.8, 0.5, 1.0), 1, null, 0.0, c0, c1)  # feet
		MeshLib.blob(tmp, Vector3(1.2 * s, 11.4, 2.25), Vector3(0.95, 0.95, 0.35), 1, null, 0.0, c0 * 0.9, c0)  # eye rims
		MeshLib.blob(glow, Vector3(1.2 * s, 11.4, 2.5), Vector3(0.62, 0.62, 0.2), 1, null, 0.0, Color(1.0, 0.55, 0.1), Color(1.0, 0.85, 0.3))
	MeshLib.tube(tmp, PackedVector3Array([Vector3(0, 10.6, 2.4), Vector3(0, 9.7, 3.1)]), PackedFloat32Array([0.45, 0.05]), 5,
		func(_t: float, _a: float, _p: Vector3) -> Color: return c0)  # beak
	mb.append_builder(tmp, xf)
	var g2 := MeshBuilder.new()
	g2.append_builder(glow, xf)
	tb.add_static_mesh(node, mb, Mats.triplanar("rock"), "OwlStatue")
	tb.add_static_mesh(node, g2, Mats.glow(Color(1.0, 0.6, 0.15), 4.0), "OwlEyes", false)
	tb.add_cylinder_collider(node, base, 4.5, 9.0)
	tb.landmarks.append({"name": "guardian_owl", "pos": base})


# =================================================================== Z6 mill
static func _mill(tb: TrackBuilder, root: Node3D) -> void:
	var sp: SplinePath = tb.branches.get("millrace_flume")
	if sp == null:
		return
	var node := Node3D.new()
	node.name = "Mill"
	root.add_child(node)
	var wood := Mats.triplanar("wood")
	var tres := MeshBuilder.new()
	var wc := Color(0.75, 0.6, 0.45, 0.4)
	for k in range(0, sp.size(), int(5.0 / sp.spacing)):
		var st := sp.style[k]
		if st != "flume" and st != "kicker":
			continue
		var hw := sp.width[k] * 0.5 + 0.1
		var b := Basis.looking_at(sp.tan[k], Vector3.UP)
		var top := sp.pos[k].y - (0.45 if st == "flume" else 0.4)
		for side: int in [-1, 1]:
			var lp := sp.pos[k] + sp.right[k] * float(side) * hw
			var gy := tb.ground_y(lp.x, lp.z) - 0.5
			var h := top - gy
			if h > 0.3:
				MeshLib.box(tres, Transform3D(b, Vector3(lp.x, gy + h * 0.5, lp.z)), Vector3(0.35, h, 0.35), wc)
		var cp := sp.pos[k]
		var gyc := tb.ground_y(cp.x, cp.z)
		if top - gyc > 2.0:
			MeshLib.box(tres, Transform3D(b, Vector3(cp.x, (top + gyc) * 0.5, cp.z)), Vector3(hw * 2.0, 0.25, 0.25), wc)
			MeshLib.box(tres, Transform3D(b.rotated(b.z, 0.6), Vector3(cp.x, (top + gyc) * 0.5, cp.z)), Vector3(hw * 2.3, 0.2, 0.2), wc)
	tb.add_static_mesh(node, tres, wood, "Trestles")
	# the mill house on the pond shore, beside the flume
	var fr := _style_range(sp, "flume")
	if fr.x < 0:
		return
	# pick the spot beside the flume with the most clearance from every road
	var km := fr.x + int((fr.y - fr.x) * 0.55)
	var hp := sp.pos[km] + sp.right[km] * -9.0
	var best := -1e9
	for fi in 11:
		var kk := fr.x + int((fr.y - fr.x) * lerpf(0.25, 0.85, float(fi) / 10.0))
		for side2: float in [-1.0, 1.0]:
			var cand := sp.pos[kk] + sp.right[kk] * side2 * 9.5
			var clear := _road_clearance(tb, cand)
			if clear > best:
				best = clear
				km = kk
				hp = cand
	hp.y = tb.ground_y(hp.x, hp.z)
	var b := Basis.looking_at(sp.tan[km], Vector3.UP)
	var house := MeshBuilder.new()
	var xf := Transform3D(b, hp)
	MeshLib.box(house, xf * Transform3D(Basis(), Vector3(0, 2.0, 0)), Vector3(8.0, 4.4, 10.0), Color(0.9, 0.88, 0.84, 0.6), 0.3)
	tb.add_static_mesh(node, house, Mats.triplanar("stone"), "MillBase")
	var upper := MeshBuilder.new()
	MeshLib.box(upper, xf * Transform3D(Basis(), Vector3(0, 6.0, 0)), Vector3(7.6, 3.6, 9.6), Color(0.85, 0.7, 0.55, 0.2))
	tb.add_static_mesh(node, upper, wood, "MillUpper")
	var roof := MeshBuilder.new()
	var rc := Color(0.62, 0.25, 0.18)
	for s2: float in [-1.0, 1.0]:
		var rb := b * Basis(Vector3(0, 0, 1), s2 * 0.62)
		MeshLib.box(roof, Transform3D(rb, hp + b * Vector3(s2 * 2.3, 9.4, 0)), Vector3(5.8, 0.35, 11.2), rc)
	MeshLib.box(roof, xf * Transform3D(Basis(), Vector3(2.2, 10.5, 2.5)), Vector3(1.0, 3.0, 1.0), Color(0.6, 0.55, 0.5))
	tb.add_static_mesh(node, roof, Mats.vcol(0.75), "MillRoof")
	tb.add_box_collider(node, xf * Transform3D(Basis(), Vector3(0, 4, 0)), Vector3(8.2, 8.0, 10.2))
	# water wheel, turned by a side chute from the flume
	var wheel := MeshInstance3D.new()
	var wmb := MeshBuilder.new()
	var R := 3.6
	for i in 12:
		var a := TAU * float(i) / 12.0
		var sb := Basis(Vector3.RIGHT, a)
		MeshLib.box(wmb, Transform3D(sb, sb * Vector3(0, R, 0)), Vector3(1.8, 0.12, 0.9), Color(0.7, 0.55, 0.4))
		MeshLib.box(wmb, Transform3D(sb, sb * Vector3(0, R * 0.5, 0)), Vector3(0.18, R, 0.18), Color(0.55, 0.4, 0.3))
	for ring: float in [-0.85, 0.85]:
		var path := PackedVector3Array()
		var rr := PackedFloat32Array()
		for i in 25:
			var a := TAU * float(i) / 24.0
			path.append(Vector3(ring, cos(a) * R, sin(a) * R))
			rr.append(0.12)
		MeshLib.tube(wmb, path, rr, 5, func(_t: float, _a: float, _p: Vector3) -> Color: return Color(0.6, 0.45, 0.32), 1.0, false)
	wheel.mesh = wmb.commit(null, Mats.vcol(0.8))
	wheel.name = "WaterWheel"
	var wheel_pos := hp + b * Vector3(-4.6, 3.6, 0)
	var pivot := Node3D.new()
	pivot.transform = Transform3D(b, wheel_pos)
	pivot.name = "WheelPivot"
	node.add_child(pivot)
	pivot.add_child(wheel)
	var spin: Node = load("res://scripts/env/spinner.gd").new()
	spin.axis = Vector3.RIGHT
	spin.speed = -0.6
	spin.target_path = NodePath("../WaterWheel")
	pivot.add_child(spin)
	tb.landmarks.append({"name": "mill", "pos": hp})
	EnvLife.chimney_smoke(node, hp + b * Vector3(2.2, 12.2, 2.5))


## Distance (m) from p to the nearest road edge of the main line or any branch.
static func _road_clearance(tb: TrackBuilder, p: Vector3) -> float:
	var best := 1e9
	var paths: Array = [tb.main]
	paths.append_array(tb.branches.values())
	for spx: SplinePath in paths:
		var i := spx.nearest_index(p, 60.0)
		if i < 0 or spx.style[i] == "gap":
			continue
		var d := Vector2(p.x - spx.pos[i].x, p.z - spx.pos[i].z).length() - spx.width[i] * 0.5
		best = minf(best, d)
	return best


# =================================================================== Z7 cave
static func _cave(tb: TrackBuilder, root: Node3D) -> void:
	var sp: SplinePath = tb.branches.get("rootway_cave")
	if sp == null:
		return
	var node := Node3D.new()
	node.name = "RootwayCave"
	root.add_child(node)
	var nz := MeshLib.make_noise(1313, 0.35, 3)
	var mb := MeshBuilder.new()
	var ring := 14
	var cr := _style_range(sp, "cave")
	# shell only over the cave section (not the lead-in, not the merge ramp)
	var k0 := maxi(cr.x, 0)
	var n := cr.y - k0 + 1
	for kl in n:
		var k := k0 + kl
		var hw := sp.width[k] * 0.5 + 1.3
		for s in ring + 1:
			var a := lerpf(-0.15, PI + 0.15, float(s) / ring)
			var lat := -cos(a) * hw
			var hh := sin(a) * 5.6
			var p := sp.pos[k] + sp.right[k] * lat + Vector3.UP * (hh - 0.6)
			var inward := (sp.pos[k] + Vector3.UP * 2.0 - p).normalized()
			p += -inward * absf(nz.get_noise_3dv(p * 1.3)) * 0.9   # bulges outward only
			var c := Color(0.75, 0.72, 0.78, 0.3)
			mb.add_vertex(p, inward, Vector2.ZERO, c)
	for k in n - 1:
		for s in ring:
			var a := k * (ring + 1) + s
			var b := a + ring + 1
			mb.quad(a, b, b + 1, a + 1)
	mb.recompute_normals()
	tb.add_static_mesh(node, mb, Mats.triplanar("rock"), "CaveShell")
	tb.add_trimesh_collider(node, mb, Surfaces.ROCK)
	# portal rocks framing both mouths
	var rocks := MeshBuilder.new()
	for end: int in [k0, k0 + n - 1]:
		var hw := sp.width[end] * 0.5 + 2.0
		for i in 7:
			var a := PI * float(i) / 6.0
			var p := sp.pos[end] + sp.right[end] * (-cos(a) * hw) + Vector3.UP * (sin(a) * 5.8 - 0.8)
			var s := tb.rng.randf_range(1.4, 2.4)
			rocks.append_builder(MeshLib.rock(end * 10 + i, 0), Transform3D(Basis(Vector3.UP, tb.rng.randf() * TAU).scaled(Vector3(s, s, s)), p))
	tb.add_static_mesh(node, rocks, Mats.triplanar("rock"), "CaveMouths")
	# glowing crystals (also light the way)
	var crystals := MeshBuilder.new()
	var crystals2 := MeshBuilder.new()
	for k in range(k0 + 3, k0 + n - 3, 3):
		for side: int in [-1, 1]:
			if tb.rng.randf() < 0.4:
				continue
			var hw := sp.width[k] * 0.5 + 0.9
			var p := sp.pos[k] + sp.right[k] * float(side) * hw + Vector3.UP * tb.rng.randf_range(0.0, 3.5)
			for c in 3:
				var dir := (Vector3.UP * 0.8 - sp.right[k] * float(side) * 0.6 + Vector3(tb.rng.randf_range(-0.3, 0.3), 0, tb.rng.randf_range(-0.3, 0.3))).normalized()
				var target_mb := crystals if (k + c) % 3 != 0 else crystals2
				MeshLib.tube(target_mb, PackedVector3Array([p, p + dir * tb.rng.randf_range(0.6, 1.4)]), PackedFloat32Array([0.22, 0.0]), 5,
					func(_t: float, _a: float, _p: Vector3) -> Color: return Color.WHITE)
	tb.add_static_mesh(node, crystals, Mats.glow(Color(0.35, 0.95, 1.0), 2.5), "Crystals", false)
	tb.add_static_mesh(node, crystals2, Mats.glow(Color(0.8, 0.45, 1.0), 2.5), "Crystals2", false)
	# hanging vine curtain hides the entrance (subtle cue: it sways, light leaks through)
	var vines := MeshBuilder.new()
	var e := k0 + 1
	var hw0 := sp.width[e] * 0.5 + 1.0
	for i in 9:
		var x := lerpf(-hw0, hw0, float(i) / 8.0)
		var top := sp.pos[e] + sp.right[e] * x + Vector3.UP * 5.0
		var len := tb.rng.randf_range(3.2, 4.6)
		MeshLib.card(vines, Transform3D(Basis.looking_at(-sp.tan[e], Vector3.UP), top + Vector3.DOWN * len), 1.3, len, Rect2(0.5, 0.5, 0.5, 0.5), Color(0.6, 0.85, 0.5, 1.0))
	tb.add_static_mesh(node, vines, Mats.cards(Color(0.8, 1.0, 0.75), "vines"), "VineCurtain", false)
	EnvLife.fireflies(node, sp.pos[k0] + Vector3.UP * 1.5, 7.0, 24)
	EnvLife.fireflies(node, sp.pos[k0 + n / 2] + Vector3.UP * 2.0, 6.0, 18)
	tb.landmarks.append({"name": "rootway_cave", "pos": sp.pos[k0 + n / 2]})


# =================================================================== landmarks
static func _elder_tree(tb: TrackBuilder, root: Node3D) -> void:
	var cr := tb.mark_pos("crest_1")
	var p := Vector3(cr.x - 70.0, 0, cr.z - 10.0)
	p.y = tb.ground_y(p.x, p.z) - 1.0
	var node := Node3D.new()
	node.name = "ElderTree"
	root.add_child(node)
	var bark := MeshBuilder.new()
	var leaves := MeshBuilder.new()
	var glow := MeshBuilder.new()
	var nz := MeshLib.make_noise(808, 0.12, 3)
	var bc := func(t: float, _a: float, _p: Vector3) -> Color: return Color(0.9, 0.86, 0.8, 1.0).lerp(Color(1, 1, 1, 0.3), t)
	var trunk := PackedVector3Array()
	var tr := PackedFloat32Array()
	for i in 9:
		var t := float(i) / 8.0
		trunk.append(p + Vector3(sin(t * 2.2) * 2.0, t * 30.0, cos(t * 1.7) * 1.5 - 1.5))
		tr.append(lerpf(5.0, 2.2, t) * (1.0 + 0.6 * pow(1.0 - t, 5.0)))
	MeshLib.tube(bark, trunk, tr, 18, bc, 0.1, false, nz, 0.18)
	for i in 7:
		var a := TAU * float(i) / 7.0 + 0.3
		var dir := Vector3(cos(a), 0, sin(a))
		var rp := PackedVector3Array()
		var rr := PackedFloat32Array()
		for j in 6:
			var t := float(j) / 5.0
			rp.append(p + dir * (3.0 + t * 11.0) + Vector3.UP * (5.5 * pow(1.0 - t, 1.6) - 0.8))
			rr.append(lerpf(2.4, 0.25, t))
		MeshLib.tube(bark, rp, rr, 8, bc, 0.1, false, nz, 0.1)
	var top := trunk[8]
	var canopy: Array[Vector3] = [top + Vector3(0, 6, 0)]
	for i in 6:
		var a := TAU * float(i) / 6.0
		var dir := Vector3(cos(a), 0.45, sin(a)).normalized()
		var bp := PackedVector3Array([top - Vector3(0, 6, 0), top - Vector3(0, 6, 0) + dir * 9.0, top - Vector3(0, 6, 0) + dir * 16.0 + Vector3.UP * 3.0])
		MeshLib.tube(bark, bp, PackedFloat32Array([1.8, 1.1, 0.4]), 8, bc, 0.1, true)
		canopy.append(bp[2] + Vector3.UP * 3.0)
	for c in canopy:
		MeshLib.blob(leaves, c, Vector3(9.5, 7.0, 9.5), 2, nz, 0.35, Color(0.12, 0.3, 0.14), Color(0.45, 0.72, 0.32), 0.55, p.y + 20.0)
	# glowing fungi climbing the trunk
	for i in 14:
		var t := tb.rng.randf_range(0.05, 0.6)
		var a := tb.rng.randf() * TAU
		var q := p + Vector3(cos(a) * 4.0 * (1.0 - t * 0.5), t * 30.0, sin(a) * 4.0 * (1.0 - t * 0.5))
		MeshLib.blob(glow, q, Vector3(0.9, 0.2, 0.9), 1, null, 0.0, Color(0.3, 0.9, 1.0), Color(0.6, 1.0, 0.95))
	tb.add_static_mesh(node, bark, Mats.triplanar("bark"), "ElderBark")
	tb.add_static_mesh(node, leaves, Mats.foliage(Color(1, 1, 1), "elder"), "ElderCanopy")
	tb.add_static_mesh(node, glow, Mats.glow(Color(0.4, 1.0, 0.95), 2.0), "ElderGlow", false)
	tb.add_cylinder_collider(node, p, 5.5, 30.0, Surfaces.WOOD)
	tb.landmarks.append({"name": "elder_tree", "pos": p})


static func _background(tb: TrackBuilder, root: Node3D) -> void:
	## Layered mountain ring, a distant waterfall and a ruined watchtower:
	## the world reads as much larger than the drivable area.
	var node := Node3D.new()
	node.name = "Background"
	root.add_child(node)
	var b := tb._bounds()
	var centre := Vector3(b.get_center().x, 0, b.get_center().y)
	var ring_specs := [[900.0, 34, Color(0.42, 0.52, 0.55), Color(0.80, 0.86, 0.90), 260.0, 170.0],
		[700.0, 26, Color(0.28, 0.40, 0.30), Color(0.55, 0.66, 0.52), 190.0, 110.0]]
	for spec in ring_specs:
		var mb := MeshBuilder.new()
		var dist: float = spec[0]
		var count: int = spec[1]
		for i in count:
			var a := TAU * (float(i) + tb.rng.randf() * 0.6) / count
			var d := dist * tb.rng.randf_range(0.9, 1.15)
			var c := centre + Vector3(cos(a) * d, -20.0, sin(a) * d)
			var rad: float = spec[4] * tb.rng.randf_range(0.7, 1.2)
			var hgt: float = spec[5] * tb.rng.randf_range(0.6, 1.4)
			var nz := MeshLib.make_noise(i * 17 + int(dist), 0.004, 4)
			MeshLib.blob(mb, c, Vector3(rad, hgt, rad * 0.8), 3, nz, 0.45, spec[2], spec[3], 0.15)
		var mi := tb.add_static_mesh(node, mb, Mats.vcol(1.0, 0.0, "mountains"), "Mountains%d" % int(dist), false)
		mi.extra_cull_margin = 100.0
	# Skyveil Falls: a tall ribbon of water down the northern range
	var nf := centre + Vector3(80, 0, -760)
	var fall := MeshBuilder.new()
	for j in 9:
		var t := float(j) / 8.0
		for c in 4:
			var f := float(c) / 3.0 * 2.0 - 1.0
			var q := nf + Vector3(f * 14.0 * (1.0 + t * 0.4), 150.0 - t * 160.0, t * 18.0)
			fall.add_vertex(q, Vector3.BACK, Vector2(f * 14.0, t * 200.0), Color(absf(f) * 0.5, smoothstep(0.6, 1.0, t), 2.0, 1.0))
	for j in 8:
		for c in 3:
			var a := j * 4 + c
			fall.quad(a, a + 4, a + 5, a + 1)
			fall.quad(a, a + 1, a + 5, a + 4)
	tb.add_static_mesh(node, fall, Mats.water("falls"), "SkyveilFalls", false)
	# ruined watchtower on a south-western hill
	var tw := centre + Vector3(-520, 0, 420)
	var tower := MeshBuilder.new()
	var prof := PackedVector2Array([Vector2(16, -20), Vector2(13, 10), Vector2(11, 60), Vector2(12, 64), Vector2(12, 68)])
	MeshLib.lathe(tower, prof, 14, Transform3D(Basis(), tw), func(t: float, _a: float, _p: Vector3) -> Color: return Color(0.62, 0.6, 0.62).lerp(Color(0.8, 0.78, 0.76), t))
	for i in 7:
		var a := TAU * float(i) / 7.0
		MeshLib.box(tower, Transform3D(Basis(Vector3.UP, a), tw + Vector3(cos(a) * 11.0, 71.0, sin(a) * 11.0)), Vector3(4.0, 6.0 + (i % 3) * 2.0, 3.0), Color(0.72, 0.7, 0.7))
	tb.add_static_mesh(node, tower, Mats.vcol(1.0, 0.0, "mountains"), "Watchtower", false)
