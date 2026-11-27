extends RefCounted
## One character instance: segmented body, two-bone IK, secondary motion.
## Character geometry is built once per id (template) and shared between instances.

const Geo = preload("res://scripts/geo.gd")
const U = preload("res://scripts/util.gd")

const SEGS := ["pelvis", "spine", "chest", "neck", "head", "uaL", "faL", "hdL", "uaR", "faR", "hdR", "thL", "snL", "ftL", "thR", "snR", "ftR"]
const PELVIS_UP := 0.1
const SPINE_LEN := 0.2
const CHEST_LEN := 0.3
const NECK_LEN := 0.09
const SH := Vector3(-0.01, 0.255, 0.19)
const HIPJ := Vector3(0.0, -0.06, 0.095)
const UA := 0.3
const FA := 0.27
const TH := 0.46
const SN := 0.45

static var TPL := {}

var def: Dictionary
var root: Node3D
var seg := {}
var J := {}
var ropes := []
var ribbons := []      # [MeshInstance3D, ImmediateMesh, Material, [ropes]]
var links := []        # [MultiMeshInstance3D, [ropes]]
var emit := []         # [Node3D marker, type, rate, CPUParticles3D or null]
var det := {}
var inflate := 0.0
var infl := {}
var mats := []
var wounds := []
var extras := {}
var M := {}

# ======================================================================= instance
func _init(d: Dictionary, stone: Material = null) -> void:
	def = d
	var t: Dictionary = template(d.id)
	root = Node3D.new()
	root.name = "Rig_" + d.id
	var clones := {}
	for n in SEGS:
		var mi := MeshInstance3D.new()
		mi.name = n
		mi.mesh = t.meshes[n]
		root.add_child(mi)
		seg[n] = mi
		M[n] = Transform3D()
		if mi.mesh:
			for i in mi.mesh.get_surface_count():
				var m: Material = mi.mesh.surface_get_material(i)
				if stone and not (m is StandardMaterial3D and m.shading_mode == BaseMaterial3D.SHADING_MODE_UNSHADED):
					mi.set_surface_override_material(i, stone)
				elif not stone:
					if not clones.has(m):
						clones[m] = m.duplicate()
						mats.append(clones[m])
					mi.set_surface_override_material(i, clones[m])
	for k in ["shL", "elL", "wrL", "shR", "elR", "wrR", "hpL", "knL", "anL", "hpR", "knR", "anR", "head", "chest", "pelvis", "neck"]:
		J[k] = Vector3.ZERO
	extras = t.extras.duplicate()
	if stone:
		return
	for mk in t.markers:
		var node := Node3D.new()
		node.position = mk[1]
		seg[mk[0]].add_child(node)
		emit.append([node, mk[2], mk[3], null])
	var group_ropes := {}
	for rd in t.ropes:
		var r := Rope.new(self, rd[0], rd[1], rd[2], rd[3], rd[4])
		ropes.append(r)
		if not group_ropes.has(rd[5]): group_ropes[rd[5]] = []
		group_ropes[rd[5]].append(r)
	for g in group_ropes:
		if t.groups.has(g):
			var mat: Material = t.groups[g].duplicate()
			mats.append(mat)
			var im := ImmediateMesh.new()
			var mi := MeshInstance3D.new()
			mi.mesh = im
			mi.top_level = true
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
			mi.extra_cull_margin = 4.0
			root.add_child(mi)
			ribbons.append([mi, im, mat, group_ropes[g]])
		elif t.link_mats.has(g):
			var mm := MultiMesh.new()
			mm.transform_format = MultiMesh.TRANSFORM_3D
			var tm := TorusMesh.new()
			var sz: float = t.link_mats[g][1]
			tm.inner_radius = sz * 0.72
			tm.outer_radius = sz * 1.28
			tm.rings = 10
			tm.ring_segments = 5
			mm.mesh = tm
			var cnt := 0
			for r in group_ropes[g]: cnt += r.n - 1
			mm.instance_count = cnt
			var mmi := MultiMeshInstance3D.new()
			mmi.multimesh = mm
			mmi.material_override = t.link_mats[g][0]
			mmi.top_level = true
			mmi.extra_cull_margin = 4.0
			root.add_child(mmi)
			links.append([mmi, group_ropes[g]])
	for m in mats:
		if m is BaseMaterial3D:
			m.set_meta("c0", m.albedo_color)
			m.set_meta("e0", m.emission if m.emission_enabled else Color.BLACK)
			m.set_meta("ee0", m.emission_energy_multiplier)
			m.set_meta("em0", m.emission_enabled)
		elif m is ShaderMaterial:
			m.set_meta("c0", m.get_shader_parameter("albedo"))

func set_visible(v: bool) -> void:
	root.visible = v

# ======================================================================= IK / pose
static func qrot(p: PackedFloat32Array, o: int) -> Basis:
	# [lean fwd, twist, side bend] -> Ry(twist) * Rz(-lean) * Rx(side)
	return Basis(Vector3.UP, p[o + 1]) * Basis(Vector3.BACK, -p[o]) * Basis(Vector3.RIGHT, p[o + 2])

static func pv(p: PackedFloat32Array, o: int) -> Vector3:
	return Vector3(p[o], p[o + 1], p[o + 2])

static func solve_ik(A: Vector3, T: Vector3, L1: float, L2: float, pole: Vector3) -> Array:
	var d := T - A
	var dist := clampf(d.length(), absf(L1 - L2) + 0.02, (L1 + L2) * 0.9995)
	d = d.normalized()
	var cos_a := clampf((L1 * L1 + dist * dist - L2 * L2) / (2.0 * L1 * dist), -1.0, 1.0)
	var sin_a := sqrt(1.0 - cos_a * cos_a)
	var bend := pole - d * pole.dot(d)
	if bend.length_squared() < 1e-8:
		bend = Vector3.BACK.cross(d)
	bend = bend.normalized()
	var B := A + d * (L1 * cos_a) + bend * (L1 * sin_a)
	var C := A + d * dist
	return [B, C, bend]

static func seg_xf(A: Vector3, B: Vector3, hint: Vector3) -> Transform3D:
	var y := (B - A).normalized()
	var x := hint - y * hint.dot(y)
	if x.length_squared() < 1e-8:
		x = Vector3.RIGHT - y * y.x
	x = x.normalized()
	var z := x.cross(y)
	return Transform3D(Basis(x, y, z), A)

func update(P: PackedFloat32Array) -> void:
	var Mp := Transform3D(qrot(P, 3), pv(P, 0))
	var Ms := Mp * Transform3D(qrot(P, 6), Vector3(0, PELVIS_UP, 0))
	var Mc := Ms * Transform3D(qrot(P, 9), Vector3(0, SPINE_LEN, 0))
	var Mn := Mc * Transform3D(qrot(P, 12), Vector3(0, CHEST_LEN, 0))
	var Mh := Mn * Transform3D(qrot(P, 15), Vector3(0, NECK_LEN, 0))
	M.pelvis = Mp; M.spine = Ms; M.chest = Mc; M.neck = Mn; M.head = Mh
	J.pelvis = Mp.origin; J.chest = Mc * Vector3(0, 0.16, 0); J.neck = Mn.origin; J.head = Mh * Vector3(0.01, 0.11, 0)
	for s in 2:
		var sd := "R" if s == 1 else "L"
		var sz := 1.0 if s == 1 else -1.0
		var ho := 21 if s == 1 else 18
		var po := 27 if s == 1 else 24
		var wo := 45 if s == 1 else 42
		var A := Mc * Vector3(SH.x, SH.y, SH.z * sz)
		var T := Mc * pv(P, ho)
		var pole := (Mc.basis * pv(P, po)).normalized()
		var r := solve_ik(A, T, UA, FA, pole)
		J["sh" + sd] = A; J["el" + sd] = r[0]; J["wr" + sd] = r[1]
		M["ua" + sd] = seg_xf(A, r[0], r[2])
		var fx := seg_xf(r[0], r[1], r[2])
		M["fa" + sd] = fx
		M["hd" + sd] = Transform3D(fx.basis * Basis(Vector3.UP, P[wo + 1]) * Basis(Vector3.BACK, -P[wo]), r[1])
		# legs
		var fo := 33 if s == 1 else 30
		var ko := 39 if s == 1 else 36
		var ao := 51 if s == 1 else 48
		var H := Mp * Vector3(HIPJ.x, HIPJ.y, HIPJ.z * sz)
		var kp := pv(P, ko).normalized()
		var lr := solve_ik(H, pv(P, fo), TH, SN, kp)
		J["hp" + sd] = H; J["kn" + sd] = lr[0]; J["an" + sd] = lr[1]
		M["th" + sd] = seg_xf(H, lr[0], lr[2])
		M["sn" + sd] = seg_xf(lr[0], lr[1], lr[2])
		var flat := Basis(Vector3.UP, P[ao]) * Basis(Vector3.BACK, P[ao + 2])
		var fxv: Vector3 = (lr[1] - lr[0]).normalized()
		var fy := flat.x - fxv * flat.x.dot(fxv)
		if fy.length_squared() < 1e-6:
			fy = Vector3.UP - fxv * fxv.y
		fy = fy.normalized()
		var pointed := Basis(fxv, fy, fxv.cross(fy))
		var q := flat.get_rotation_quaternion().slerp(pointed.get_rotation_quaternion(), clampf(P[ao + 1], 0.0, 1.0))
		M["ft" + sd] = Transform3D(Basis(q), lr[1])
	for n in SEGS:
		if det.has(n): continue
		var m: Transform3D = M[n]
		if inflate > 0.0:
			m.basis = m.basis * Basis.from_scale(Vector3.ONE * (1.0 + inflate * infl.get(n, 1.0)))
		seg[n].transform = m

func joint_world(k: String) -> Vector3:
	return root.global_transform * J[k]

# ======================================================================= secondary motion
func secondary(dt: float) -> void:
	if ropes.is_empty(): return
	var g := root.global_transform
	var s: float = def.scale
	var cols := []
	if not det.has("thL"): cols.append([g * J.hpL, g * J.knL, 0.085 * s])
	if not det.has("thR"): cols.append([g * J.hpR, g * J.knR, 0.085 * s])
	if not det.has("snL"): cols.append([g * J.knL, g * J.anL, 0.06 * s])
	if not det.has("snR"): cols.append([g * J.knR, g * J.anR, 0.06 * s])
	cols.append([g * J.pelvis, g * J.chest, 0.15 * s])
	cols.append([g * J.head, g * J.head, 0.11 * s])
	var step := minf(dt, 1.0 / 40.0)
	for r in ropes:
		r.step(step, cols)
	for rb in ribbons:
		_ribbon(rb)
	for lk in links:
		_links(lk)

func _ribbon(rb: Array) -> void:
	var im: ImmediateMesh = rb[1]
	im.clear_surfaces()
	if not root.is_visible_in_tree(): return
	im.surface_begin(Mesh.PRIMITIVE_TRIANGLES, rb[2])
	for r in rb[3]:
		var n: int = r.n
		var L := []
		var R := []
		for i in n:
			var a: Vector3 = r.p[maxi(0, i - 1)]
			var b: Vector3 = r.p[mini(n - 1, i + 1)]
			var d := (b - a).normalized()
			var sd: Vector3 = r.side - d * r.side.dot(d)
			sd = sd.normalized() * (r.w * 0.5 * (1.0 - r.taper * float(i) / (n - 1)))
			L.append(r.p[i] - sd)
			R.append(r.p[i] + sd)
		for i in n - 1:
			var v0 := float(i) / (n - 1)
			var v1 := float(i + 1) / (n - 1)
			var nrm: Vector3 = (R[i] - L[i]).cross(L[i + 1] - L[i]).normalized()
			im.surface_set_normal(nrm); im.surface_set_uv(Vector2(0, v0)); im.surface_add_vertex(L[i])
			im.surface_set_normal(nrm); im.surface_set_uv(Vector2(1, v0)); im.surface_add_vertex(R[i])
			im.surface_set_normal(nrm); im.surface_set_uv(Vector2(0, v1)); im.surface_add_vertex(L[i + 1])
			im.surface_set_normal(nrm); im.surface_set_uv(Vector2(1, v0)); im.surface_add_vertex(R[i])
			im.surface_set_normal(nrm); im.surface_set_uv(Vector2(1, v1)); im.surface_add_vertex(R[i + 1])
			im.surface_set_normal(nrm); im.surface_set_uv(Vector2(0, v1)); im.surface_add_vertex(L[i + 1])
	im.surface_end()

func _links(lk: Array) -> void:
	var mm: MultiMesh = lk[0].multimesh
	var k := 0
	for r in lk[1]:
		for i in r.n - 1:
			var a: Vector3 = r.p[i]
			var b: Vector3 = r.p[i + 1]
			var x := (b - a).normalized()
			if x.length_squared() < 0.5: x = Vector3.DOWN
			var up := Vector3.FORWARD if absf(x.dot(Vector3.FORWARD)) < 0.9 else Vector3.RIGHT
			var y := (up - x * up.dot(x)).normalized()
			if i % 2 == 1: y = x.cross(y)
			mm.set_instance_transform(k, Transform3D(Basis(x, y, x.cross(y)), (a + b) * 0.5))
			k += 1

func reset_ropes() -> void:
	for r in ropes: r.ok = false

# ======================================================================= rope
class Rope extends RefCounted:
	var rig
	var segn: String
	var local: Vector3
	var n: int
	var len: float
	var w: float
	var taper: float
	var grav: float
	var damp: float
	var stiff: float
	var rad: float
	var dir: Vector3
	var side_l: Vector3
	var side := Vector3.BACK
	var p := []
	var q := []
	var rest := []
	var ok := false

	func _init(r, sg: String, lc: Vector3, cnt: int, ln: float, o: Dictionary) -> void:
		rig = r; segn = sg; local = lc; n = cnt; len = ln
		w = o.get("w", 0.05); taper = o.get("taper", 0.5); grav = o.get("grav", 1.0); damp = o.get("damp", 0.96); stiff = o.get("stiff", 0.0); rad = o.get("rad", 0.02)
		dir = U.v3(o.get("dir", [0, -1, 0])).normalized()
		side_l = U.v3(o.get("side", [0, 0, 1])).normalized()
		for i in n:
			p.append(Vector3.ZERO); q.append(Vector3.ZERO); rest.append(local + dir * (i * len))

	func step(dt: float, cols: Array) -> void:
		var m: Transform3D = rig.seg[segn].global_transform
		if not ok:
			for i in n:
				p[i] = m * rest[i]; q[i] = p[i]
			ok = true
		p[0] = m * local
		q[0] = p[0]
		var g := 9.8 * grav * dt * dt
		for i in range(1, n):
			var v: Vector3 = (p[i] - q[i]) * damp
			q[i] = p[i]
			var np: Vector3 = p[i] + v
			np.y -= g
			if stiff > 0.0:
				np = np.lerp(m * rest[i], stiff)
			p[i] = np
		for it in 2:
			for i in range(1, n):
				var a: Vector3 = p[i] - p[i - 1]
				var l := a.length()
				if l < 1e-5: continue
				var df := (l - len) / l
				if i == 1:
					p[i] -= a * df
				else:
					p[i] -= a * (df * 0.5)
					p[i - 1] += a * (df * 0.5)
			for i in range(1, n):
				var P: Vector3 = p[i]
				if P.y < 0.015: P.y = 0.015
				for c in cols:
					var b: Vector3 = c[1] - c[0]
					var L2 := b.length_squared()
					var t := 0.0
					if L2 > 0.0: t = clampf((P - c[0]).dot(b) / L2, 0.0, 1.0)
					var cp: Vector3 = c[0] + b * t
					var d := P - cp
					var dl := d.length()
					var rr: float = c[2] + rad
					if dl < rr and dl > 1e-6:
						P += d * ((rr - dl) / dl)
				p[i] = P
		side = (m.basis * side_l).normalized()

# ======================================================================= templates
class Bld extends RefCounted:
	var mb := {}
	var markers := []
	var ropes := []
	var groups := {}
	var link_mats := {}
	var extras := {}

	func add(sg: String, g: Dictionary, mat: Material, p := Vector3.ZERO, r := Vector3.ZERO, s := Vector3.ONE) -> void:
		if not mb.has(sg): mb[sg] = Geo.MB.new()
		mb[sg].add(g, U.xf(p, r, s), mat)

	func marker(sg: String, p: Vector3, type: String, rate: float) -> void:
		markers.append([sg, p, type, rate])

	func rope(sg: String, lc: Vector3, n: int, ln: float, o: Dictionary, group: String) -> void:
		ropes.append([sg, lc, n, ln, o, group])

static func template(id: String) -> Dictionary:
	if TPL.has(id): return TPL[id]
	var b := Bld.new()
	match id:
		"vorgath": _vorgath(b)
		"nyxara": _nyxara(b)
		"kharos": _kharos(b)
		"ossirah": _ossirah(b)
	var meshes := {}
	for n in SEGS:
		meshes[n] = b.mb[n].build() if b.mb.has(n) else null
	var t := {meshes = meshes, markers = b.markers, ropes = b.ropes, groups = b.groups, link_mats = b.link_mats, extras = b.extras}
	TPL[id] = t
	return t

static func V(a: float, b: float, c: float) -> Vector3:
	return Vector3(a, b, c)

static func body(b: Bld, sk: Material, bulk: float, fem := false, no_abs := false) -> void:
	var k := bulk
	var f := 1.0 if fem else 0.0
	b.add("pelvis", Geo.loft(0.28, [[-0.06, 0.02, 0.02], [0, 0.08 * k, 0.11 * k], [0.3, 0.1 * k, (0.15 + f * 0.025) * k], [0.62, 0.098 * k, (0.148 + f * 0.015) * k], [1, 0.092 * k, 0.132 * k], [1.07, 0.06, 0.09]], 16, 12, 2.2), sk, V(0, -0.15, 0))
	for z in [-1.0, 1.0]:
		b.add("pelvis", Geo.ell(0.068 * k, 0.075 * k, 0.072 * k), sk, V(-0.058 * k, -0.05, z * 0.066 * k))
	b.add("spine", Geo.loft(0.27, [[-0.06, 0.06, 0.09], [0, 0.092 * k, 0.13 * k], [0.45, (0.088 - f * 0.012) * k, (0.128 - f * 0.025) * k], [1, 0.102 * k, 0.148 * k], [1.08, 0.08, 0.12]], 16, 10, 2.2), sk, V(0, -0.03, 0))
	if not no_abs:
		for i in 3:
			for z in [-1.0, 1.0]:
				b.add("spine", Geo.ell(0.02 * k, 0.028, 0.032 * k, 8, 6), sk, V(0.08 * k, 0.035 + i * 0.062, z * 0.036 * k))
	for z in [-1.0, 1.0]:
		b.add("spine", Geo.ell(0.04 * k, 0.09, 0.03 * k, 8, 6), sk, V(0.03 * k, 0.08, z * 0.11 * k), V(0, 0, z * 0.1))
	b.add("chest", Geo.loft(0.37, [[-0.05, 0.08, 0.12], [0, 0.102 * k, 0.148 * k], [0.33, 0.118 * k, (0.172 - f * 0.02) * k], [0.66, 0.118 * k, (0.18 - f * 0.03) * k], [0.88, 0.098 * k, (0.163 - f * 0.025) * k], [1, 0.07, 0.1], [1.05, 0.04, 0.05]], 18, 14, 2.4), sk, V(0, -0.03, 0))
	for z in [-1.0, 1.0]:
		if fem:
			b.add("chest", Geo.ell(0.05, 0.052, 0.05, 10, 7), sk, V(0.095, 0.15, z * 0.068), V(0, 0, -0.25))
		else:
			b.add("chest", Geo.ell(0.046 * k, 0.064 * k, 0.082 * k, 10, 7), sk, V(0.083 * k, 0.185, z * 0.074 * k), V(z * 0.15, 0, -0.12))
		b.add("chest", Geo.ell(0.055 * k, 0.06 * k, 0.1 * k, 10, 7), sk, V(-0.035, 0.282, z * 0.075 * k), V(z * 0.45, 0, 0))
		b.add("chest", Geo.ell(0.06 * k, 0.13, 0.045 * k, 10, 7), sk, V(-0.035 * k, 0.14, z * 0.125 * k), V(z * -0.15, 0, 0))
		b.add("chest", Geo.ell(0.04 * k, 0.05, 0.03, 8, 6), sk, V(-0.09 * k, 0.2, z * 0.06 * k))
	b.add("neck", Geo.loft(0.17, [[-0.12, 0.05, 0.05], [0, 0.052 * k, 0.058 * k], [0.6, (0.046 - f * 0.008) * k, (0.05 - f * 0.008) * k], [1, 0.05, 0.052]], 12, 6), sk, V(0, -0.045, 0))
	if not fem:
		for z in [-1.0, 1.0]:
			b.add("neck", Geo.ell(0.016, 0.07, 0.016, 6, 5), sk, V(0.025, 0.03, z * 0.028), V(z * 0.4, 0, -0.5))
	for sd in ["L", "R"]:
		b.add("ua" + sd, Geo.loft(0.36, [[-0.1, 0.03, 0.03], [0, 0.058 * k, 0.06 * k], [0.3, (0.06 - f * 0.012) * k, (0.056 - f * 0.01) * k, -0.008], [0.65, 0.048 * k, 0.045 * k, -0.004], [0.95, 0.043, 0.043], [1.04, 0.032, 0.032]], 12, 12), sk, V(0, -0.03, 0))
		b.add("ua" + sd, Geo.ell((0.068 - f * 0.015) * k, (0.088 - f * 0.015) * k, (0.072 - f * 0.015) * k), sk, V(0, 0.035, 0))
		b.add("ua" + sd, Geo.ell(0.03 * k, 0.085, 0.038 * k, 8, 6), sk, V(0.026 * k, 0.13, 0))
		b.add("fa" + sd, Geo.loft(0.31, [[-0.08, 0.03, 0.03], [0, 0.042 * k, 0.045 * k], [0.22, (0.05 - f * 0.01) * k, (0.048 - f * 0.01) * k, 0.004], [0.62, 0.036 * k, 0.038 * k], [0.95, 0.028, 0.033], [1.04, 0.025, 0.03]], 12, 10), sk, V(0, -0.03, 0))
		b.add("th" + sd, Geo.loft(0.54, [[-0.08, 0.06, 0.06], [0, 0.085 * k, 0.088 * k], [0.25, 0.088 * k, (0.082 + f * 0.008) * k, 0.008], [0.6, 0.07 * k, 0.066 * k, 0.004], [0.88, 0.055, 0.056], [1.02, 0.05, 0.052]], 14, 12), sk, V(0, -0.04, 0))
		b.add("th" + sd, Geo.ell(0.042 * k, 0.13, 0.05 * k, 8, 6), sk, V(0.045 * k, 0.22, 0))
		b.add("th" + sd, Geo.ell(0.028, 0.032, 0.032, 8, 6), sk, V(0.045, 0.455, 0))
		b.add("sn" + sd, Geo.loft(0.5, [[-0.06, 0.045, 0.045], [0.03, 0.053, 0.053], [0.22, 0.06 * k, 0.054 * k, -0.013], [0.5, 0.046 * k, 0.042 * k, -0.006], [0.86, 0.033, 0.034], [1.02, 0.034, 0.04]], 12, 12), sk, V(0, -0.03, 0))
		b.add("sn" + sd, Geo.ell(0.036 * k, 0.1, 0.04 * k, 8, 6), sk, V(-0.03 * k, 0.14, 0))

static func hand(b: Bld, sd: String, style: String, mat: Material, claw: Material) -> void:
	var S := "hd" + sd
	var th := -1.0 if sd == "R" else 1.0
	if style == "fist":
		b.add(S, Geo.box(0.046, 0.085, 0.082), mat, V(0, 0.045, 0))
		b.add(S, Geo.box(0.05, 0.04, 0.084), mat, V(0.01, 0.095, 0))
		for i in 4:
			b.add(S, Geo.ell(0.013, 0.012, 0.011, 6, 5), mat, V(-0.012, 0.11, -0.03 + i * 0.02))
		b.add(S, Geo.capsule(0.012, 0.035), mat, V(0.03, 0.07, th * 0.022), V(PI / 2, 0, 0.3 * th))
		return
	b.add(S, Geo.box(0.036, 0.085, 0.08), mat, V(0, 0.045, 0))
	var L := 1.35 if style == "long" else 1.0
	var c := 1.6 if style == "grip" else 1.0
	for i in 4:
		var z := -0.03 + i * 0.02
		var l := (0.8 if i == 0 or i == 3 else 1.0) * L
		var pts := [[0, 0.085, z], [0.008 * c, 0.085 + 0.04 * l, z], [0.03 * c, 0.085 + 0.07 * l, z], [0.055 * c, 0.085 + 0.085 * l, z * 0.9]]
		b.add(S, Geo.taper(pts, 0.0105, 0.007, 5, 6), mat)
		if claw:
			b.add(S, Geo.taper([pts[3], [0.07 * c, 0.085 + 0.085 * l + 0.005, z * 0.9], [0.085 * c, 0.085 + 0.07 * l, z * 0.9]], 0.007, 0.0005, 5, 5), claw)
	var tp := [[0.01, 0.03, th * 0.035], [0.035, 0.06, th * 0.045], [0.055, 0.085, th * 0.035]]
	b.add(S, Geo.taper(tp, 0.012, 0.008, 5, 6), mat)
	if claw:
		b.add(S, Geo.taper([tp[2], [0.07, 0.1, th * 0.03]], 0.008, 0.0005, 5, 4), claw)

static func foot(b: Bld, sd: String, style: String, mat: Material, claw: Material = null) -> void:
	var S := "ft" + sd
	var g := Geo.loft(0.27, [[-0.04, 0.01, 0.01], [0, 0.038, 0.036], [0.22, 0.042, 0.045], [0.62, 0.026, 0.05], [0.92, 0.018, 0.046], [1.03, 0.006, 0.02]], 12, 12)
	g = Geo.xform(g, Transform3D(Basis(Vector3.BACK, -PI / 2), Vector3(-0.07, -0.045, 0)))
	var vv: PackedVector3Array = g.v
	for i in vv.size():
		if vv[i].y < -0.078: vv[i].y = -0.078
	g.v = vv
	b.add(S, g, mat)
	if style == "boot":
		b.add(S, Geo.loft(0.2, [[0, 0.05, 0.05], [0.5, 0.048, 0.052], [1, 0.055, 0.058]], 12, 4), mat, V(-0.005, -0.02, 0))
	if style == "claw" and claw:
		for i in 3:
			var z := -0.03 + i * 0.03
			b.add(S, Geo.taper([[0.17, -0.06, z], [0.22, -0.065, z * 1.1], [0.25, -0.078, z * 1.2]], 0.012, 0.002, 5, 5), claw)
	if style == "bare":
		for i in 5:
			b.add(S, Geo.ell(0.011, 0.009, 0.009, 6, 5), mat, V(0.19 - absf(i - 1) * 0.008, -0.07, -0.03 + i * 0.016))

static func eyes(b: Bld, mat: Material, x: float, y: float, z: float, r: float) -> void:
	for s in [-1.0, 1.0]:
		b.add("head", Geo.ell(r, r, r, 8, 6), mat, V(x, y, s * z))

static func skull_geo() -> Dictionary:
	var g := Geo.head({w = 0.072, h = 0.1, d = 0.095, sock = 0.028, skull = true, jaw = 0.3, res = 18})
	var c := PackedColorArray()
	for v in g.v:
		var n: Vector3 = v.normalized()
		var k := 1.0
		var dz := absf(n.z) - 0.38
		var dy := n.y - 0.05
		if n.x > 0.5 and dz * dz + dy * dy < 0.05: k = 0.1
		if n.x > 0.7 and absf(n.z) < 0.1 and n.y < -0.05 and n.y > -0.3: k = 0.15
		c.append(Color(k, k, k))
	g.c = c
	return Geo.xform(g, Transform3D(Basis().scaled(Vector3.ONE * 1.6), Vector3.ZERO))

static func _mask_tex() -> ImageTexture:
	var S := 128
	var img := Image.create(S, S, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.94, 0.92, 0.88))
	var rng := RandomNumberGenerator.new()
	rng.seed = 12
	for i in 9:
		var x := rng.randf() * S
		var y := rng.randf() * S
		for k in 7:
			var nx := x + (rng.randf() - 0.5) * 20.0
			var ny := y + (rng.randf() - 0.5) * 20.0
			for t in 12:
				var px := int(lerpf(x, nx, t / 12.0))
				var py := int(lerpf(y, ny, t / 12.0))
				if px >= 0 and px < S and py >= 0 and py < S: img.set_pixel(px, py, Color(0.16, 0.12, 0.12))
			x = nx; y = ny
	for ex in [0.332, 0.668]:
		var cx: float = ex * S
		var cy := 0.571 * S
		for y in S:
			for x in S:
				var dx: float = (x - cx) / 11.0
				var dy := (y - cy) / 7.0
				if dx * dx + dy * dy < 1.0: img.set_pixel(x, y, Color(0, 0, 0))
				elif absf(x - cx) < 1.6 and y > cy and y < cy + 40: img.set_pixel(x, y, Color(0.05, 0.03, 0.03))
	for x in range(54, 74):
		img.set_pixel(x, 118, Color(0.45, 0, 0))
	for k in 7:
		for y in range(114, 123):
			img.set_pixel(56 + k * 3, y, Color(0.45, 0, 0))
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)

static func cloth_mat(col: Color, holes := 0.72) -> ShaderMaterial:
	return Mats.smat("cloth", {albedo = Vector3(col.r, col.g, col.b), noise_tex = Mats.T.cloth_noise, holes = holes})

# ---------------------------------------------------------------- VORGATH
static func _vorgath(b: Bld) -> void:
	var T: Dictionary = Mats.T
	var mus := Mats.std({map = T.muscle_c, nmap = T.muscle_n, ns = 1.4, r = 0.32, cc = 0.5, ccr = 0.3, rim = 0.35, rim_tint = 0.6, uv = Vector3(6, 1.2, 1), color = Color(0.85, 0.6, 0.58)})
	var bone := Mats.std({map = T.bone_c, nmap = T.bone_n, r = 0.55, color = Color(0.92, 0.88, 0.78)})
	var dark := Mats.std({color = Color(0.06, 0.04, 0.04), r = 0.4, metal = 0.2})
	var iron: Material = Mats.M.iron
	var k := 1.32
	body(b, mus, k)
	for i in 5:
		for s in [-1.0, 1.0]:
			var y := 0.06 + i * 0.048
			var rx := 0.118 * k * 1.04
			var rz := 0.178 * k * 1.03
			var pts := []
			for q in 6:
				var a := 0.18 + q / 5.0 * (1.05 - i * 0.06)
				pts.append([cos(a) * rx, y - q * 0.006, s * sin(a) * rz])
			b.add("chest", Geo.taper(pts, 0.011, 0.008, 5, 8), bone)
	b.add("chest", Geo.box(0.025, 0.2, 0.03), bone, V(0.158, 0.13, 0))
	for i in 6:
		var sg := "spine" if i < 3 else "chest"
		var y := 0.03 + i * 0.07 if i < 3 else 0.02 + (i - 3) * 0.1
		b.add(sg, Geo.taper([[-0.1 * k, y, 0], [-0.18 * k, y + 0.05, 0], [-0.24 * k - i * 0.01, y + 0.13, 0]], 0.03, 0.002, 6, 6), bone)
	for sd in ["L", "R"]:
		var z := -1.0 if sd == "L" else 1.0
		b.add("ua" + sd, Geo.spherep(0.105, 0, TAU, 0, PI / 2.2, 12, 6), bone, V(0, 0.02, 0), V(0, 0, z * -0.3), V(1, 0.9, 1.1))
		for q in 3:
			b.add("ua" + sd, Geo.taper([[0, -0.02, 0], [-0.02, -0.12 - q * 0.02, z * 0.05], [-0.08 + q * 0.04, -0.24 - q * 0.04, z * 0.12]], 0.025, 0.002, 5, 6), bone, V(q * 0.03 - 0.03, 0, 0))
		b.add("fa" + sd, Geo.torus(0.045, 0.016), iron, V(0, 0.24, 0))
		hand(b, sd, "claw", mus, dark)
		foot(b, sd, "claw", mus, dark)
	b.add("head", Geo.head({w = 0.082, h = 0.122, d = 0.108, sock = 0.02, brow = 0.022, nose = 0.006, cheek = 0.014, jaw = 0.12, jawF = 0.02, chin = 0.014, mouth = 0.012, hollow = 0.01}), mus, V(0.015, 0.11, 0))
	for i in 12:
		var a := (i / 11.0 - 0.5) * 1.7
		var x := 0.1 + cos(a) * 0.02
		var z := sin(a) * 0.045
		for y in [0.055, 0.036]:
			b.add("head", Geo.cone(0.0065, 0.022, 4), bone, V(x + 0.015, y, z), V(PI if y > 0.05 else 0.0, 0, 0))
	eyes(b, Mats.glow(Color(1, 0.65, 0.08), 5.0), 0.097, 0.12, 0.033, 0.011)
	for i in 9:
		var a := -0.9 + i / 8.0 * 1.8
		b.add("head", Geo.taper([[cos(a) * 0.06 - 0.01, 0.21, sin(a) * 0.07], [cos(a) * 0.075 - 0.01, 0.27, sin(a) * 0.085], [cos(a) * 0.08 - 0.02, 0.32 + (i % 2) * 0.05, sin(a) * 0.1]], 0.012, 0.0015, 5, 6), bone)
	for z in [-1.0, 1.0]:
		b.add("head", Geo.taper([[0.02, 0.19, z * 0.07], [-0.02, 0.26, z * 0.16], [-0.12, 0.3, z * 0.22], [-0.22, 0.25, z * 0.2], [-0.26, 0.17, z * 0.16]], 0.036, 0.003, 8, 16), bone)
	b.groups["cloth"] = cloth_mat(Color(0.32, 0.12, 0.1))
	for i in 4:
		b.rope("pelvis", V(0.1 * k, -0.04, -0.06 + i * 0.04), 6, 0.085, {w = 0.07, side = [0, 0, 1], dir = [0.3, -1, 0], stiff = 0.015, taper = 0.2, rad = 0.03}, "cloth")
		b.rope("pelvis", V(-0.1 * k, -0.04, -0.06 + i * 0.04), 6, 0.085, {w = 0.07, side = [0, 0, 1], dir = [-0.3, -1, 0], stiff = 0.015, taper = 0.2, rad = 0.03}, "cloth")
	b.add("pelvis", Geo.loft(0.06, [[0, 0.108 * k, 0.145 * k], [1, 0.108 * k, 0.145 * k]], 16, 2, 2.2), dark, V(0, 0.02, 0))
	var sk := skull_geo()
	for i in 5:
		var a := -1.1 + i * 0.55
		b.add("pelvis", sk, Mats.M.bone_v, V(cos(a) * 0.15 * k, 0, sin(a) * 0.19 * k), V(0, -a, 0), Vector3.ONE * 0.32)
	b.link_mats["chain"] = [iron, 0.028]
	b.rope("faL", V(0, 0.25, 0), 6, 0.07, {rad = 0.02}, "chain")
	b.rope("faR", V(0, 0.25, 0), 6, 0.07, {rad = 0.02}, "chain")
	b.marker("head", V(0.11, 0.04, 0), "drip", 1.2)
	b.marker("chest", V(0.12, 0.1, 0), "drip", 0.8)

# ---------------------------------------------------------------- NYXARA
static func _nyxara(b: Bld) -> void:
	var T: Dictionary = Mats.T
	var skin := Mats.std({map = T.mottle, detail = T.veins, nmap = T.skin_n, ns = 0.4, color = Color(0.6, 0.6, 0.68), r = 0.55, rim = 0.35, rim_tint = 0.2})
	var leather := Mats.std({map = T.leather_c, nmap = T.leather_n, color = Color(0.55, 0.48, 0.58), r = 0.5, metal = 0.1})
	var obs := Mats.std({color = Color(0.03, 0.025, 0.05), r = 0.12, metal = 0.3, cc = 1.0, emit = Color(0.35, 0.12, 1.0), ee = 0.25})
	var claw := Mats.std({color = Color(0.02, 0.02, 0.02), r = 0.2})
	var bone := Mats.std({map = T.bone_c, nmap = T.bone_n, r = 0.5, color = Color(0.85, 0.82, 0.78)})
	var hair := Mats.std({color = Color(0.02, 0.02, 0.025), r = 0.35, metal = 0.2, double = true})
	var mask := Mats.std({map = _mask_tex(), color = Color(0.72, 0.69, 0.66), r = 0.3, cc = 0.8, double = true})
	var wrap := Mats.std({color = Color(0.07, 0.06, 0.07), r = 0.9})
	body(b, skin, 0.8, true, true)
	b.add("spine", Geo.loft(0.27, [[0, 0.072, 0.092], [0.45, 0.074, 0.088], [1, 0.084, 0.108]], 16, 5, 2.3), leather, V(0, -0.03, 0))
	b.add("chest", Geo.loft(0.24, [[0, 0.086, 0.12], [0.4, 0.1, 0.132], [0.7, 0.1, 0.13], [1, 0.08, 0.112]], 16, 6, 2.3), leather, V(0, -0.03, 0))
	for i in 9:
		var a := PI * 0.25 + i / 8.0 * PI * 1.5
		b.add("chest", Geo.taper([[cos(a) * 0.07, 0.3, sin(a) * 0.1], [cos(a) * 0.1, 0.38, sin(a) * 0.14], [cos(a) * 0.13 - 0.03, 0.46, sin(a) * 0.17]], 0.012, 0.001, 4, 5), bone)
	b.add("head", Geo.head({w = 0.068, h = 0.113, d = 0.093, sock = 0.014, brow = 0.006, nose = 0.012, cheek = 0.01, jaw = 0.34, chin = 0.006, mouth = 0.003}), skin, V(0.012, 0.11, 0))
	b.add("head", Geo.head({w = 0.07, h = 0.115, d = 0.095, sock = 0.006, brow = 0.004, nose = 0.01, cheek = 0.008, jaw = 0.3, chin = 0.006, scale = 1.075, part = [PI - 1.25, 2.5, 0.5, 1.75], res = 24}), mask, V(0.012, 0.11, 0))
	eyes(b, Mats.glow(Color(0.25, 0.7, 1.0), 2.2), 0.097, 0.118, 0.028, 0.0055)
	b.add("head", Geo.head({w = 0.075, h = 0.12, d = 0.1, sock = 0.0, brow = 0.0, nose = 0.0, cheek = 0.0, jaw = 0.1, chin = 0.0, mouth = 0.0, part = [-1.7, 3.4, 0.0, 1.95], res = 22}), hair, V(0, 0.118, 0))
	b.groups["hair"] = hair
	for i in 10:
		var a := PI * 0.5 + (i / 9.0) * PI
		var y := 0.2 - absf(i - 4.5) * 0.008
		b.rope("head", V(cos(a) * 0.07 - 0.01, y, sin(a) * 0.08), 9, 0.075, {w = 0.065, side = [-sin(a), 0, cos(a)], dir = [cos(a) * 0.7, -1, sin(a) * 0.5], stiff = 0.06, damp = 0.95, taper = 0.7, rad = 0.025}, "hair")
	for i in 3:
		var z := -0.035 + i * 0.035
		b.rope("head", V(0.07, 0.2, z), 6, 0.06, {w = 0.035, side = [0, 0, 1], dir = [0.6, -1, z * 4], stiff = 0.08, taper = 0.6}, "hair")
	for sd in ["L", "R"]:
		b.add("fa" + sd, Geo.taper([[0.035, -0.02, 0], [0.06, 0.18, 0], [0.055, 0.38, 0], [0.02, 0.56, 0], [-0.04, 0.68, 0]], 0.028, 0.002, 7, 16, 0.22), obs)
		b.add("fa" + sd, Geo.taper([[0.03, -0.03, 0], [0.08, -0.06, 0], [0.12, -0.03, 0]], 0.016, 0.001, 5, 5), bone)
		hand(b, sd, "long", skin, claw)
		foot(b, sd, "bare", skin)
		for i in 4:
			b.add("sn" + sd, Geo.torus(0.038 - i * 0.001, 0.006, 12, 4), wrap, V(-0.003, 0.3 + i * 0.035, 0), V(0.2, 0, 0))
	b.groups["shroud"] = cloth_mat(Color(0.06, 0.055, 0.07), 0.7)
	for i in 10:
		var a := i / 10.0 * TAU
		b.rope("pelvis", V(cos(a) * 0.12, 0.02, sin(a) * 0.155), 8, 0.115, {w = 0.13, side = [-sin(a), 0, cos(a)], dir = [cos(a) * 0.25, -1, sin(a) * 0.25], stiff = 0.012, taper = 0.1, rad = 0.035}, "shroud")
	for i in 3:
		b.rope("chest", V(-0.1, 0.28, -0.09 + i * 0.09), 9, 0.12, {w = 0.13, side = [0, 0, 1], dir = [-0.2, -1, 0], stiff = 0.01, taper = 0.1, rad = 0.04}, "shroud")
	b.marker("hdL", V(0, 0.1, 0), "wisp", 4)
	b.marker("hdR", V(0, 0.1, 0), "wisp", 4)
	b.marker("head", V(-0.06, 0.15, 0), "wisp", 2)
	b.extras["blades"] = true

# ---------------------------------------------------------------- KHAROS
static func _kharos(b: Bld) -> void:
	var T: Dictionary = Mats.T
	var armor := Mats.std({map = T.metal_c, nmap = T.metal_n, rmap = T.metal_r, metal = 0.8, r = 1.0, color = Color(0.36, 0.34, 0.33), emit = Color(1, 0.32, 0.05), emap = T.lava, ee = 2.4, double = true, uv = Vector3(1.2, 1.2, 1)})
	var chr := Mats.std({color = Color(0.07, 0.045, 0.04), r = 0.85, nmap = T.skin_n, ns = 1.0})
	var skull := Mats.std({map = T.bone_c, nmap = T.bone_n, color = Color(0.4, 0.33, 0.27), r = 0.75, emit = Color(0.4, 0.08, 0.0), ee = 0.15})
	var iron: Material = Mats.M.iron
	var k := 1.12
	body(b, chr, k, false, true)
	b.add("chest", Geo.loft(0.36, [[-0.04, 0.108 * k, 0.158 * k], [0.3, 0.132 * k, 0.19 * k], [0.66, 0.13 * k, 0.195 * k], [0.88, 0.112 * k, 0.18 * k], [1, 0.08, 0.12]], 18, 12, 2.6), armor, V(0, -0.04, 0))
	b.add("chest", Geo.box(0.03, 0.3, 0.03), armor, V(0.148 * k, 0.14, 0))
	for i in 3:
		b.add("spine", Geo.loft(0.08, [[0, 0.1 * k, 0.14 * k], [1, 0.104 * k, 0.145 * k]], 16, 2, 2.5), armor, V(0, 0.02 + i * 0.065, 0))
	b.add("neck", Geo.loft(0.09, [[0, 0.085, 0.1], [1, 0.068, 0.075]], 14, 3), armor, V(0, -0.03, 0))
	b.add("pelvis", Geo.loft(0.2, [[0, 0.108 * k, 0.152 * k], [0.6, 0.106 * k, 0.15 * k], [1, 0.1 * k, 0.14 * k]], 16, 4, 2.5), armor, V(0, -0.1, 0))
	for t in [[0.1, -0.07, 0.3], [0.1, 0.07, -0.3], [0.0, -0.15, PI / 2], [0.0, 0.15, -PI / 2], [-0.1, 0.0, PI]]:
		var x: float = t[0]
		var z: float = t[1]
		var rx := 0.0
		if x == 0.0: rx = -0.18 if z > 0.0 else 0.18
		b.add("pelvis", Geo.box(0.012, 0.2, 0.12), armor, V(x * 1.15, -0.13, z * 1.1), V(rx, t[2], signf(x) * 0.18))
	for sd in ["L", "R"]:
		var z := -1.0 if sd == "L" else 1.0
		for q in 3:
			b.add("ua" + sd, Geo.spherep(0.12 - q * 0.012, 0, TAU, 0, PI / 2.1, 14, 6), armor, V(0, 0.03 + q * 0.055, 0), V(0, 0, PI), V(1.05, 0.9, 1.15))
		b.add("ua" + sd, Geo.spherep(0.12, 0, TAU, 0, PI / 2.1, 14, 6), armor, V(0, -0.01, 0), Vector3.ZERO, V(1.05, 0.9, 1.15))
		for q in 3:
			b.add("ua" + sd, Geo.cone(0.025, 0.14, 6), armor, V(-0.02 + q * 0.03, -0.08, z * 0.02), V(0, 0, PI))
		b.add("ua" + sd, Geo.loft(0.26, [[0, 0.066 * k, 0.068 * k], [0.5, 0.064 * k, 0.062 * k], [1, 0.05, 0.05]], 12, 4), armor, V(0, 0.05, 0))
		b.add("ua" + sd, Geo.torus(0.05, 0.012, 12, 4), armor, V(0, 0.3, 0))
		b.add("fa" + sd, Geo.loft(0.28, [[0, 0.05 * k, 0.052 * k], [0.3, 0.058 * k, 0.058 * k], [0.8, 0.045 * k, 0.047 * k], [1, 0.047, 0.049]], 12, 5), armor)
		for q in 3:
			b.add("fa" + sd, Geo.torus(0.056 - q * 0.003, 0.009, 12, 4), iron, V(0, 0.08 + q * 0.05, 0), V((q - 1) * 0.25, 0, 0))
		hand(b, sd, "fist", armor, null)
		b.add("th" + sd, Geo.loft(0.36, [[0, 0.094 * k, 0.096 * k], [0.5, 0.088 * k, 0.086 * k], [1, 0.066, 0.066]], 14, 5), armor, V(0, 0.04, 0))
		b.add("th" + sd, Geo.spherep(0.055, 0, TAU, 0, PI / 1.8, 10, 6), armor, V(0.04, 0.455, 0), V(0, 0, -PI / 2))
		b.add("th" + sd, Geo.cone(0.018, 0.08, 6), armor, V(0.095, 0.455, 0), V(0, 0, -PI / 2))
		b.add("sn" + sd, Geo.loft(0.36, [[0, 0.06, 0.058], [0.3, 0.064 * k, 0.06 * k], [1, 0.044, 0.046]], 12, 5), armor, V(0, 0.04, 0))
		foot(b, sd, "boot", armor)
	b.add("head", Geo.head({w = 0.075, h = 0.115, d = 0.1, sock = 0.03, brow = 0.018, nose = 0.0, cheek = 0.014, jaw = 0.28, chin = 0.012, mouth = 0.01, hollow = 0.014, skull = true}), skull, V(0.012, 0.11, 0))
	for i in 10:
		var a := (i / 9.0 - 0.5) * 1.4
		b.add("head", Geo.box(0.012, 0.02, 0.01), skull, V(0.093 + cos(a) * 0.012, 0.045, sin(a) * 0.036))
	eyes(b, Mats.glow(Color(1, 0.3, 0.04), 6.0), 0.086, 0.118, 0.031, 0.013)
	b.add("head", Geo.band(0.098, 0.092, 0.07, PI * 0.85, PI * 1.3, 16), armor, V(0, 0.19, 0))
	for i in 7:
		var a := PI * 0.95 + i / 6.0 * PI * 1.1
		b.add("head", Geo.cone(0.014, 0.08 + (i % 2) * 0.05, 5), armor, V(sin(a) * 0.095, 0.26 + (i % 2) * 0.025, cos(a) * 0.095))
	for z in [-1.0, 1.0]:
		b.add("head", Geo.box(0.06, 0.1, 0.012), armor, V(-0.005, 0.13, z * 0.088))
	b.groups["cape"] = cloth_mat(Color(0.33, 0.1, 0.07), 0.74)
	for i in 5:
		b.rope("chest", V(-0.13, 0.3, -0.15 + i * 0.075), 9, 0.13, {w = 0.11, side = [0, 0, 1], dir = [-0.15, -1, 0], stiff = 0.008, taper = 0.15, rad = 0.05}, "cape")
	b.link_mats["chain"] = [iron, 0.03]
	b.rope("pelvis", V(0.1, 0, -0.12), 8, 0.065, {rad = 0.03}, "chain")
	b.rope("pelvis", V(-0.08, 0, 0.14), 7, 0.065, {rad = 0.03}, "chain")
	b.marker("head", V(-0.01, 0.22, 0), "fire", 26)
	b.marker("head", V(0.09, 0.12, 0), "eyefire", 20)
	b.marker("chest", V(0.1, 0.1, 0), "ember", 3)
	b.marker("hdR", V(0, 0.08, 0), "ember", 3)
	b.marker("hdL", V(0, 0.08, 0), "ember", 3)
	b.extras["armor"] = true

# ---------------------------------------------------------------- OSSIRAH
static func _ossirah(b: Bld) -> void:
	var T: Dictionary = Mats.T
	var coat := Mats.std({map = T.leather_c, nmap = T.leather_n, color = Color(0.78, 0.66, 0.54), r = 0.55, double = true})
	var coat2 := Mats.std({map = T.leather_c, nmap = T.leather_n, color = Color(0.58, 0.49, 0.42), r = 0.65, double = true})
	var hood := Mats.std({map = T.cloth_noise, color = Color(0.3, 0.26, 0.28), r = 0.95, double = true})
	var mask := Mats.std({map = T.leather_c, nmap = T.leather_n, color = Color(0.95, 0.82, 0.66), r = 0.5})
	var brass := Mats.std({color = Color(0.63, 0.48, 0.23), metal = 0.9, r = 0.35})
	var vial := Mats.glow(Color(0.15, 1.0, 0.18), 3.2)
	var steel := Mats.std({color = Color(0.72, 0.7, 0.69), metal = 1.0, r = 0.28})
	var k := 0.95
	body(b, coat2, k, false, true)
	b.add("chest", Geo.loft(0.4, [[-0.05, 0.11, 0.155], [0.3, 0.128 * k, 0.185 * k], [0.7, 0.13 * k, 0.195 * k], [0.92, 0.11 * k, 0.18 * k], [1.05, 0.09, 0.13], [1.2, 0.1, 0.13]], 18, 12, 2.4), coat, V(0, -0.05, 0))
	b.add("spine", Geo.loft(0.27, [[0, 0.1 * k, 0.14 * k], [0.5, 0.098 * k, 0.138 * k], [1, 0.11 * k, 0.156 * k]], 16, 5, 2.3), coat, V(0, -0.03, 0))
	b.add("pelvis", Geo.loft(0.12, [[0, 0.112, 0.158], [1, 0.115, 0.16]], 16, 2, 2.3), coat2)
	for s in [-1.0, 1.0]:
		b.add("chest", Geo.box(0.012, 0.42, 0.022), coat2, V(0.128 * k * 1.08, 0.15, 0), V(s * 0.55, 0, 0))
	for i in 5:
		var a := -0.7 + i * 0.35
		b.add("spine", Geo.cyl(0.012, 0.012, 0.06, 6), vial, V(cos(a) * 0.125, 0.1, sin(a) * 0.155))
		b.add("spine", Geo.cyl(0.014, 0.014, 0.01, 6), brass, V(cos(a) * 0.125, 0.135, sin(a) * 0.155))
	b.add("spine", Geo.torus(0.15, 0.01, 18, 4), brass, V(0, 0.09, 0), Vector3.ZERO, V(0.85, 1, 1.08))
	b.add("head", Geo.head({w = 0.07, h = 0.112, d = 0.095, sock = 0.01, jaw = 0.2}), coat2, V(0.012, 0.11, 0))
	b.add("head", Geo.head({w = 0.07, h = 0.115, d = 0.095, sock = 0.004, brow = 0.006, nose = 0.0, cheek = 0.006, jaw = 0.24, scale = 1.08, part = [PI - 1.35, 2.7, 0.55, 1.95], res = 24}), mask, V(0.012, 0.11, 0))
	b.add("head", Geo.taper([[0.08, 0.09, 0], [0.17, 0.07, 0], [0.27, 0.04, 0], [0.35, -0.01, 0]], 0.042, 0.004, 10, 14), mask)
	for z in [-1.0, 1.0]:
		b.add("head", Geo.cyl(0.022, 0.022, 0.022, 12), brass, V(0.1, 0.125, z * 0.032), V(0, 0, PI / 2))
		b.add("head", Geo.cyl(0.02, 0.02, 0.004, 12), Mats.glow(Color(0.2, 1.0, 0.25), 3.5), V(0.112, 0.125, z * 0.032), V(0, 0, PI / 2))
	b.add("head", Geo.spherep(0.12, PI * 1.32, PI * 1.36, 0, PI * 0.72, 16, 10), hood, V(-0.012, 0.13, 0), V(0, 0, -0.15), V(1.05, 1.05, 1.02))
	b.add("neck", Geo.loft(0.2, [[0, 0.1, 0.12], [0.6, 0.11, 0.14], [1, 0.12, 0.15]], 14, 4), hood, V(-0.01, -0.06, 0))
	b.groups["coat"] = coat
	for i in 8:
		var a := i / 8.0 * TAU + 0.3
		b.rope("pelvis", V(cos(a) * 0.12, 0, sin(a) * 0.16), 7, 0.115, {w = 0.17, side = [-sin(a), 0, cos(a)], dir = [cos(a) * 0.3, -1, sin(a) * 0.3], stiff = 0.018, taper = 0.0, rad = 0.04}, "coat")
	for sd in ["L", "R"]:
		b.add("fa" + sd, Geo.loft(0.12, [[0, 0.05, 0.052], [1, 0.06, 0.062]], 12, 3), coat, V(0, 0.17, 0))
		hand(b, sd, "grip" if sd == "R" else "glove", coat2, null)
		foot(b, sd, "boot", coat2)
		b.add("sn" + sd, Geo.loft(0.3, [[0, 0.058, 0.058], [1, 0.064, 0.062]], 12, 4), coat2, V(0, 0.18, 0))
	b.add("hdR", Geo.cyl(0.013, 0.015, 0.3, 8), coat2, V(0.03, 0.1, 0.06), V(PI / 2, 0, 0))
	b.add("hdR", Geo.taper([[0.03, 0.1, 0.2], [0.12, 0.12, 0.26], [0.24, 0.08, 0.24], [0.31, -0.01, 0.15], [0.3, -0.08, 0.05]], 0.016, 0.001, 6, 18, 0.25), steel)
	b.marker("pelvis", V(0, -0.4, 0), "miasma", 3)
	b.marker("chest", V(0, 0.2, 0), "fly", 3)
	b.marker("hdL", V(0, 0.08, 0), "plague", 4)
	b.extras["swarm"] = true
