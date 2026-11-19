class_name RoadBuilder
extends Node3D
## Builds every road from the baked network: surfaces with lane markings, skirts,
## bridges (decks, parapets, piers), tunnels (tubes, lamps, portals), guard rails,
## median barriers, street lights and junction patches - with collision.

const STYLE := {"highway": 0, "avenue": 1, "street": 2, "country": 3, "mountain": 4, "track": 5,
	"dirt": 6, "cobble": 6, "alley": 6}
const LAYER := {"dirt": 2, "alley": 2, "cobble": 1}
const SURFACE := {"dirt": "gravel", "alley": "gravel", "cobble": "cobble"}
const SEG := 48

var wd: WorldData
var quality := 1
var lamp_xforms := []        # single-arm side lamps
var lamp2_xforms := []       # double-arm median lamps
var trims := {}              # Vector2i(road, end) -> metres
var patches := []            # [pos, radius, layer]


func build(data: WorldData, q: int) -> void:
	wd = data
	quality = q
	var t0 := Time.get_ticks_msec()
	_compute_trims()
	for ri in wd.roads.size():
		_build_road(ri)
	_build_patches()
	_build_lamps()
	print("[roads] built in %d ms" % (Time.get_ticks_msec() - t0))


func _compute_trims() -> void:
	for j in wd.json.junctions:
		var links: Array = j.links
		var maxw := 0.0
		var lay := 2
		for l in links:
			var r: Dictionary = wd.roads[int(l[0])]
			maxw = maxf(maxw, r.width)
			lay = mini(lay, LAYER.get(r.type, 0))
		var rad := maxw * 0.5 + 1.5
		for l in links:
			var ri := int(l[0])
			var k := int(l[1])
			var r: Dictionary = wd.roads[ri]
			if r.closed:
				continue
			var n: int = r.pv.size()
			if k != 0 and k != n - 1:
				continue
			var other := 0.0
			for l2 in links:
				if l2 == l:
					continue
				other = maxf(other, wd.roads[int(l2[0])].width * 0.5)
			var trim := maxf(other - 0.3, 0.0)
			trims[Vector2i(ri, 0 if k == 0 else 1)] = trim
			rad = maxf(rad, trim + 3.0)
		var pos := Vector3(j.pos[0], j.pos[1], j.pos[2])
		patches.append([pos, rad, lay])


func _tangent(pv: PackedVector3Array, k: int, closed: bool) -> Vector3:
	var n := pv.size()
	var a: Vector3
	var b: Vector3
	if closed:
		a = pv[(k - 1 + n) % n]
		b = pv[(k + 1) % n]
	else:
		a = pv[maxi(k - 1, 0)]
		b = pv[mini(k + 1, n - 1)]
	return (b - a).normalized()


func _build_road(ri: int) -> void:
	var r: Dictionary = wd.roads[ri]
	var pv: PackedVector3Array = r.pv
	var n := pv.size()
	var closed: bool = r.closed
	var w: float = r.width
	var hw := w * 0.5
	var style: int = STYLE.get(r.type, 6)
	var layer: int = LAYER.get(r.type, 0)
	var bridge: Array = r.bridge
	var tunnel: Array = r.tunnel
	var is_highway: bool = r.type == "highway"
	# per-sample frames
	var pts := PackedVector3Array()
	var tans := PackedVector3Array()
	var rights := PackedVector3Array()
	var dist := PackedFloat32Array()
	var br := []
	var tu := []
	var count := n + (1 if closed else 0)
	var acc := 0.0
	for k in count:
		var kk := k % n
		var p := pv[kk]
		if k > 0:
			acc += p.distance_to(pts[k - 1])
		pts.append(p)
		var t := _tangent(pv, kk, closed)
		tans.append(t)
		var th := Vector3(t.x, 0, t.z).normalized()
		rights.append(th.cross(Vector3.UP).normalized())
		dist.append(acc)
		br.append(int(bridge[kk]) == 1)
		tu.append(int(tunnel[kk]) == 1)
	var total := acc
	var k0 := 0
	var k1 := count - 1
	if not closed:
		var ts: float = trims.get(Vector2i(ri, 0), 0.0)
		var te: float = trims.get(Vector2i(ri, 1), 0.0)
		while k0 < k1 and dist[k0] < ts:
			k0 += 1
		while k1 > k0 and dist[k1] > total - te:
			k1 -= 1
	if k1 - k0 < 1:
		return
	# samples close to junctions: no median barrier there so cars can turn across
	var near_junction := {}
	if r.rail or is_highway:
		for j in wd.json.junctions:
			for l in j.links:
				if int(l[0]) == ri:
					var kk := int(l[1])
					for o in range(-8, 9):
						near_junction[posmod(kk + o, n)] = true
	var road_mat := Mats.road(style, layer, w)
	var conc := Mats.concrete()
	var metal := Mats.metal()
	var surf_name: String = SURFACE.get(r.type, "asphalt")
	var seg_start := k0
	while seg_start < k1:
		var seg_end := mini(seg_start + SEG, k1)
		var surf := MeshAcc.new()
		var cmesh := MeshAcc.new()     # concrete parts
		var mmesh := MeshAcc.new()     # metal parts
		var glow := MeshAcc.new()      # tunnel lamps
		var col := PackedVector3Array()
		# --- road surface
		var rows := []
		for k in range(seg_start, seg_end + 1):
			var p := pts[k] + Vector3(0, 0.02, 0)
			var rt := rights[k]
			var nrm := rt.cross(tans[k]).normalized()
			var a := surf.v(p - rt * hw, nrm, Vector2(0.0, dist[k]))
			var c := surf.v(p, nrm, Vector2(0.5, dist[k]))
			var b := surf.v(p + rt * hw, nrm, Vector2(1.0, dist[k]))
			rows.append([a, c, b])
		for i in rows.size() - 1:
			var A: Array = rows[i]
			var B: Array = rows[i + 1]
			surf.quad(A[0], A[1], B[1], B[0], Vector3.UP)
			surf.quad(A[1], A[2], B[2], B[1], Vector3.UP)
		col.append_array(surf.faces())
		# --- skirts / bridge decks / tunnels / rails / median
		for k in range(seg_start, seg_end):
			var p0 := pts[k]
			var p1 := pts[k + 1]
			var r0 := rights[k]
			var r1 := rights[k + 1]
			var is_bridge: bool = br[k] or br[k + 1]
			var is_tunnel: bool = tu[k] and tu[k + 1]
			if is_bridge:
				_deck_piece(cmesh, p0, p1, r0, r1, hw, dist[k], dist[k + 1])
				# parapets
				for side: float in [-1.0, 1.0]:
					var e0 := p0 + r0 * hw * side
					var e1 := p1 + r1 * hw * side
					_wall_piece(cmesh, col, e0, e1, r0 * side, r1 * side, 0.35, 0.95, dist[k], dist[k + 1])
			else:
				for side: float in [-1.0, 1.0]:
					var e0 := p0 + r0 * hw * side + Vector3(0, 0.02, 0)
					var e1 := p1 + r1 * hw * side + Vector3(0, 0.02, 0)
					var o0 := e0 + r0 * side * 0.35 - Vector3(0, 0.9, 0)
					var o1 := e1 + r1 * side * 0.35 - Vector3(0, 0.9, 0)
					var nn := (r0 * side + Vector3(0, 0.3, 0)).normalized()
					var a := cmesh.v(e0, nn, Vector2(dist[k], 0))
					var b := cmesh.v(e1, nn, Vector2(dist[k + 1], 0))
					var c := cmesh.v(o1, nn, Vector2(dist[k + 1], 1))
					var d := cmesh.v(o0, nn, Vector2(dist[k], 1))
					cmesh.quad(a, b, c, d, nn)
			if is_tunnel:
				_tunnel_piece(cmesh, glow, col, p0, p1, r0, r1, hw, dist[k], dist[k + 1], k)
			if is_highway and not near_junction.has(k % n):
				_median_piece(cmesh, col, p0, p1, r0, r1, dist[k], dist[k + 1])
			# guard rails
			if r.rail and not is_bridge and not is_tunnel and not near_junction.has(k % n):
				for side: float in [-1.0, 1.0]:
					var need := is_highway
					if not need:
						var probe := p0 + r0 * side * (hw + 3.0)
						need = wd.height(probe.x, probe.z) < p0.y - 1.4
					if need:
						_rail_piece(mmesh, col, p0 + r0 * side * (hw + 0.45), p1 + r1 * side * (hw + 0.45), r0 * side, k)
			# street lights
			if r.light > 0 and not is_tunnel and int(dist[k] / r.light) != int(dist[k + 1] / r.light):
				if is_highway:
					lamp2_xforms.append(Transform3D(Basis.looking_at(Vector3(r0.x, 0, r0.z), Vector3.UP), p0))
				else:
					var side := 1.0 if int(dist[k] / r.light) % 2 == 0 else -1.0
					var lp := p0 + r0 * side * (hw + 1.2)
					lamp_xforms.append(Transform3D(Basis.looking_at(-r0 * side, Vector3.UP), lp))
		# --- tunnel portals
		for k in range(seg_start, seg_end):
			if tu[k] != tu[k + 1]:
				var inside := k + 1 if tu[k + 1] else k
				var outward := -tans[inside] if tu[k + 1] else tans[inside]
				_portal(cmesh, col, pts[inside], rights[inside], outward, hw)
		# --- commit
		var mesh := surf.to_mesh(road_mat)
		if not cmesh.is_empty():
			cmesh.to_mesh(conc, mesh)
		if not mmesh.is_empty():
			mmesh.to_mesh(metal, mesh)
		if not glow.is_empty():
			glow.to_mesh(Mats.std("tunnel_lamp", Color(1, 0.9, 0.7), 0.0, 0.4, Color(1.0, 0.82, 0.55), 4.0), mesh)
		var mi := MeshInstance3D.new()
		mi.mesh = mesh
		mi.visibility_range_end = 2600.0
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		add_child(mi)
		var body := StaticBody3D.new()
		body.collision_layer = 1
		body.collision_mask = 0
		body.set_meta("surface", surf_name)
		body.set_meta("road", ri)
		var cs := CollisionShape3D.new()
		var sh := ConcavePolygonShape3D.new()
		sh.backface_collision = true
		sh.set_faces(col)
		cs.shape = sh
		body.add_child(cs)
		add_child(body)
		seg_start = seg_end


func _deck_piece(m: MeshAcc, p0: Vector3, p1: Vector3, r0: Vector3, r1: Vector3, hw: float, d0: float, d1: float) -> void:
	var depth := 1.5
	var down := Vector3(0, -depth, 0)
	var l0 := p0 - r0 * hw
	var l1 := p1 - r1 * hw
	var rr0 := p0 + r0 * hw
	var rr1 := p1 + r1 * hw
	# underside
	var a := m.v(l0 + down, Vector3.DOWN, Vector2(0, d0))
	var b := m.v(l1 + down, Vector3.DOWN, Vector2(0, d1))
	var c := m.v(rr1 + down, Vector3.DOWN, Vector2(hw * 2, d1))
	var d := m.v(rr0 + down, Vector3.DOWN, Vector2(hw * 2, d0))
	m.quad(a, b, c, d, Vector3.DOWN)
	# outer sides
	for side in [[l0, l1, -r0], [rr0, rr1, r0]]:
		var e0: Vector3 = side[0]
		var e1: Vector3 = side[1]
		var nn: Vector3 = side[2]
		var q0 := m.v(e0, nn, Vector2(d0, 0))
		var q1 := m.v(e1, nn, Vector2(d1, 0))
		var q2 := m.v(e1 + down, nn, Vector2(d1, depth))
		var q3 := m.v(e0 + down, nn, Vector2(d0, depth))
		m.quad(q0, q1, q2, q3, nn)
	# pier every ~32 m
	if int(d0 / 32.0) != int(d1 / 32.0):
		var g := wd.height(p0.x, p0.z)
		var top := p0.y - depth
		if top - g > 2.0:
			var hgt := top - g + 2.0
			var basis := Basis.looking_at(Vector3(r0.z, 0, -r0.x) if absf(r0.x) + absf(r0.z) > 0 else Vector3.FORWARD, Vector3.UP)
			var offs := [0.0] if hw < 7.0 else [-hw * 0.45, hw * 0.45]
			for o: float in offs:
				var base := p0 + r0 * float(o) + Vector3(0, -depth - hgt * 0.5, 0)
				m.box(Transform3D(basis, base), Vector3(1.7, hgt, 1.7), 0.25)
			m.box(Transform3D(basis, p0 + Vector3(0, -depth - 0.5, 0)), Vector3(hw * 1.7, 1.0, 2.2), 0.25)


## vertical box-section wall along an edge (parapet), outward = direction away from road
func _wall_piece(m: MeshAcc, col: PackedVector3Array, e0: Vector3, e1: Vector3, o0: Vector3, o1: Vector3, thick: float, h: float, d0: float, d1: float) -> void:
	var up := Vector3(0, h, 0)
	var i0 := e0 - o0 * 0.05
	var i1 := e1 - o1 * 0.05
	var x0 := e0 + o0 * thick
	var x1 := e1 + o1 * thick
	var faces := [
		[i0, i1, i1 + up, i0 + up, -o0],
		[i0 + up, i1 + up, x1 + up, x0 + up, Vector3.UP],
		[x0, x1, x1 + up, x0 + up, o0],
	]
	for f in faces:
		var nn: Vector3 = f[4]
		var a := m.v(f[0], nn, Vector2(d0, 0))
		var b := m.v(f[1], nn, Vector2(d1, 0))
		var c := m.v(f[2], nn, Vector2(d1, h))
		var d := m.v(f[3], nn, Vector2(d0, h))
		m.quad(a, b, c, d, nn)
		col.append_array([f[0], f[1], f[2], f[0], f[2], f[3]])


func _median_piece(m: MeshAcc, col: PackedVector3Array, p0: Vector3, p1: Vector3, r0: Vector3, r1: Vector3, d0: float, d1: float) -> void:
	var prof := [[-0.32, 0.0], [-0.14, 0.28], [-0.09, 0.82], [0.09, 0.82], [0.14, 0.28], [0.32, 0.0]]
	var pts0 := []
	var pts1 := []
	for q in prof:
		pts0.append(p0 + r0 * float(q[0]) + Vector3(0, float(q[1]) + 0.02, 0))
		pts1.append(p1 + r1 * float(q[0]) + Vector3(0, float(q[1]) + 0.02, 0))
	for i in prof.size() - 1:
		var mid: Vector3 = (pts0[i] + pts0[i + 1]) * 0.5 - (p0 + Vector3(0, 0.3, 0))
		var nn := mid.normalized()
		var a := m.v(pts0[i], nn, Vector2(d0, i))
		var b := m.v(pts1[i], nn, Vector2(d1, i))
		var c := m.v(pts1[i + 1], nn, Vector2(d1, i + 1))
		var d := m.v(pts0[i + 1], nn, Vector2(d0, i + 1))
		m.quad(a, b, c, d, nn)
		col.append_array([pts0[i], pts1[i], pts1[i + 1], pts0[i], pts1[i + 1], pts0[i + 1]])


func _rail_piece(m: MeshAcc, col: PackedVector3Array, a0: Vector3, a1: Vector3, out: Vector3, k: int) -> void:
	var y0 := 0.48
	var y1 := 0.8
	for s: float in [-1.0, 1.0]:
		var nn: Vector3 = out * s
		var off: Vector3 = out * s * 0.02
		var a := m.v(a0 + off + Vector3(0, y0, 0), nn, Vector2(0, 0))
		var b := m.v(a1 + off + Vector3(0, y0, 0), nn, Vector2(1, 0))
		var c := m.v(a1 + off + Vector3(0, y1, 0), nn, Vector2(1, 1))
		var d := m.v(a0 + off + Vector3(0, y1, 0), nn, Vector2(0, 1))
		m.quad(a, b, c, d, nn)
	col.append_array([a0 + Vector3(0, 0.0, 0), a1, a1 + Vector3(0, 1.0, 0), a0, a1 + Vector3(0, 1.0, 0), a0 + Vector3(0, 1.0, 0)])
	if k % 1 == 0:
		var basis := Basis.looking_at(Vector3(out.z, 0, -out.x), Vector3.UP)
		m.box(Transform3D(basis, a0 + out * 0.08 + Vector3(0, 0.4, 0)), Vector3(0.1, 0.8, 0.1))


func _tunnel_piece(m: MeshAcc, glow: MeshAcc, col: PackedVector3Array, p0: Vector3, p1: Vector3, r0: Vector3, r1: Vector3, hw: float, d0: float, d1: float, k: int) -> void:
	var prof := _tunnel_profile(hw)
	var c0 := []
	var c1 := []
	for q in prof:
		c0.append(p0 + r0 * q.x + Vector3(0, q.y, 0))
		c1.append(p1 + r1 * q.x + Vector3(0, q.y, 0))
	for i in prof.size() - 1:
		var mid: Vector2 = (prof[i] + prof[i + 1]) * 0.5
		var inward := -(r0 * mid.x + Vector3(0, mid.y - 3.0, 0)).normalized()
		var a := m.v(c0[i], inward, Vector2(d0, i * 2.0))
		var b := m.v(c1[i], inward, Vector2(d1, i * 2.0))
		var c := m.v(c1[i + 1], inward, Vector2(d1, i * 2.0 + 2.0))
		var d := m.v(c0[i + 1], inward, Vector2(d0, i * 2.0 + 2.0))
		m.quad(a, b, c, d, inward)
		col.append_array([c0[i], c1[i], c1[i + 1], c0[i], c1[i + 1], c0[i + 1]])
	# lamps along both upper sides
	if k % 3 == 0:
		for side: float in [-1.0, 1.0]:
			var lp := p0 + r0 * side * (hw - 0.6) + Vector3(0, 5.6, 0)
			var basis := Basis.looking_at(Vector3(r0.z, 0, -r0.x), Vector3.UP)
			glow.box(Transform3D(basis, lp), Vector3(0.35, 0.12, 1.6))


func _tunnel_profile(hw: float) -> Array:
	var wx := hw + 1.2
	var prof := [Vector2(-wx, -0.3), Vector2(-wx, 4.6)]
	for i in range(1, 8):
		var a := PI - PI * i / 8.0
		prof.append(Vector2(cos(a) * wx, 4.6 + sin(a) * 3.2))
	prof.append(Vector2(wx, 4.6))
	prof.append(Vector2(wx, -0.3))
	return prof


func _portal(m: MeshAcc, col: PackedVector3Array, p: Vector3, rt: Vector3, outward: Vector3, hw: float) -> void:
	var prof := _tunnel_profile(hw)
	var W := hw + 9.0
	var H := 14.0
	var c := Vector2(0, 3.0)
	var face := outward.normalized()
	var front := p + face * 0.8
	var inner := []
	var outer := []
	for q in prof:
		var d: Vector2 = (q - c)
		var dn := d.normalized()
		var s := 1e9
		if absf(dn.x) > 1e-4:
			s = minf(s, (W if dn.x > 0 else -W) / dn.x)
		if dn.y > 1e-4:
			s = minf(s, (H - c.y) / dn.y)
		elif dn.y < -1e-4:
			s = minf(s, (-0.3 - c.y) / dn.y)
		var o := c + dn * s
		inner.append(front + rt * q.x + Vector3(0, q.y, 0))
		outer.append(front + rt * o.x + Vector3(0, o.y, 0))
	for i in prof.size() - 1:
		var a := m.v(inner[i], face, Vector2(i, 0))
		var b := m.v(inner[i + 1], face, Vector2(i + 1, 0))
		var cc := m.v(outer[i + 1], face, Vector2(i + 1, 4))
		var d := m.v(outer[i], face, Vector2(i, 4))
		m.quad(a, b, cc, d, face)
	# thick frame top and sides going back into the mountain
	var basis := Basis.looking_at(-face, Vector3.UP)
	m.box(Transform3D(basis, front - face * 3.0 + Vector3(0, H + 0.6, 0)), Vector3(W * 2.0, 1.2, 7.0), 0.25)
	for side: float in [-1.0, 1.0]:
		m.box(Transform3D(basis, front - face * 3.0 + rt * side * (W + 0.6) + Vector3(0, H * 0.5, 0)), Vector3(1.2, H + 0.6, 7.0), 0.25)


func _build_patches() -> void:
	for pdef in patches:
		var pos: Vector3 = pdef[0]
		var rad: float = pdef[1]
		var lay: int = pdef[2]
		var m := MeshAcc.new()
		var segs := 20
		var c := m.v(pos + Vector3(0, -0.02, 0), Vector3.UP, Vector2(0.5, pos.z))
		var ring := []
		for i in segs + 1:
			var a := TAU * i / segs
			var q := pos + Vector3(cos(a) * rad, -0.02, sin(a) * rad)
			ring.append(m.v(q, Vector3.UP, Vector2(0.5 + cos(a) * rad / 200.0, pos.z + sin(a) * rad)))
		for i in segs:
			m.tri(c, ring[i], ring[i + 1], Vector3.UP)
		var mi := MeshInstance3D.new()
		mi.mesh = m.to_mesh(Mats.road(6, lay, 200.0, 0.0))
		mi.visibility_range_end = 1500.0
		add_child(mi)
		var body := StaticBody3D.new()
		body.set_meta("surface", "gravel" if lay == 2 else "asphalt")
		var cs := CollisionShape3D.new()
		var sh := ConcavePolygonShape3D.new()
		sh.backface_collision = true
		sh.set_faces(m.faces())
		cs.shape = sh
		body.add_child(cs)
		add_child(body)


func _lamp_mesh(double: bool) -> ArrayMesh:
	var pole := MeshAcc.new()
	var head := MeshAcc.new()
	var h := 9.0
	pole.cylinder(Transform3D(), 0.13, 0.09, 0.0, h, 8, true)
	var arms := [1.0, -1.0] if double else [1.0]
	for s in arms:
		var arm_xf := Transform3D(Basis(Vector3(0, 0, 1), -PI * 0.5 * float(s)), Vector3(0, h - 0.1, 0))
		pole.cylinder(arm_xf, 0.06, 0.06, 0.0, 2.4, 6, false)
		var head_pos := Vector3(2.4 * float(s), h - 0.15, 0)
		pole.box(Transform3D(Basis(), head_pos + Vector3(0, 0.05, 0)), Vector3(0.9, 0.18, 0.4))
		head.box(Transform3D(Basis(), head_pos - Vector3(0, 0.07, 0)), Vector3(0.7, 0.05, 0.3))
	var mesh := pole.to_mesh(Mats.dark_metal())
	head.to_mesh(Mats.lamp_glow(), mesh)
	return mesh


func _build_lamps() -> void:
	for pair in [[lamp_xforms, false], [lamp2_xforms, true]]:
		var xs: Array = pair[0]
		if xs.is_empty():
			continue
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = _lamp_mesh(pair[1])
		mm.instance_count = xs.size()
		for i in xs.size():
			var xf: Transform3D = xs[i]
			# the lamp arm points along local +X; rotate so the arm reaches over the road
			xf.basis = xf.basis * Basis(Vector3.UP, PI * 0.5)
			mm.set_instance_transform(i, xf)
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.visibility_range_end = 900.0
		add_child(mmi)
