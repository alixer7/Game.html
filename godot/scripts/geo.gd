extends RefCounted
## Procedural mesh generation. Generators return {v, n, uv, i, flip} dictionaries
## with counter-clockwise-outward triangles; MB (mesh builder) converts to Godot's
## clockwise front faces and merges parts per material into one ArrayMesh.

static func _crom(a: float, b: float, c: float, d: float, t: float) -> float:
	var t2 := t * t
	var t3 := t2 * t
	return 0.5 * ((2.0 * b) + (-a + c) * t + (2.0 * a - 5.0 * b + 4.0 * c - d) * t2 + (-a + 3.0 * b - 3.0 * c + d) * t3)

## Build normals + indices for a (rows+1) x (cols+1) vertex grid.
## mode 0: outward = along_rows x around ; mode 1: outward = around x along_rows
static func _grid(P: PackedVector3Array, uv: PackedVector2Array, rows: int, cols: int, wrap: bool, mode: int) -> Dictionary:
	var W := cols + 1
	var N := PackedVector3Array()
	N.resize(P.size())
	for r in rows + 1:
		for j in W:
			var jp: int
			var jm: int
			if wrap:
				jp = (j + 1) % cols
				jm = (j - 1 + cols) % cols
			else:
				jp = mini(j + 1, cols)
				jm = maxi(j - 1, 0)
			var tu: Vector3 = P[r * W + jp] - P[r * W + jm]
			var tv: Vector3 = P[mini(r + 1, rows) * W + j] - P[maxi(r - 1, 0) * W + j]
			var n: Vector3 = tv.cross(tu) if mode == 0 else tu.cross(tv)
			if n.length_squared() < 1e-14:
				n = -tv if r < rows * 0.5 else tv
			N[r * W + j] = n.normalized()
	var I := PackedInt32Array()
	for r in rows:
		for j in cols:
			var p00 := r * W + j
			var p01 := p00 + 1
			var p10 := p00 + W
			var p11 := p10 + 1
			if mode == 0:
				I.append_array([p00, p10, p01, p10, p11, p01])
			else:
				I.append_array([p00, p01, p10, p10, p01, p11])
	return {v = P, n = N, uv = uv, i = I, flip = true}

## Lofted tube along +Y. prof entries: [t, rx, rz, ox, oz]; sq = superellipse exponent
static func loft(length: float, prof: Array, radial := 14, rings := 14, sq := 2.0) -> Dictionary:
	var n := prof.size()
	var Pr := []
	for p in prof:
		Pr.append([p[0], p[1], p[2] if p.size() > 2 else p[1], p[3] if p.size() > 3 else 0.0, p[4] if p.size() > 4 else 0.0])
	var V := PackedVector3Array()
	var UV := PackedVector2Array()
	var e := 2.0 / sq
	for r in rings + 1:
		var s := float(r) / rings * (n - 1)
		var i := mini(n - 2, int(s))
		var f := s - i
		var vals := []
		for c in 5:
			vals.append(_crom(Pr[maxi(0, i - 1)][c], Pr[i][c], Pr[mini(n - 1, i + 1)][c], Pr[mini(n - 1, i + 2)][c], f))
		for j in radial + 1:
			var a := float(j) / radial * TAU
			var ca := cos(a)
			var sa := sin(a)
			V.append(Vector3(vals[3] + maxf(0.0006, vals[1]) * signf(ca) * pow(absf(ca), e), vals[0] * length, vals[4] + maxf(0.0006, vals[2]) * signf(sa) * pow(absf(sa), e)))
			UV.append(Vector2(float(j) / radial, vals[0]))
	return _grid(V, UV, rings, radial, true, 0)

static func ell(rx: float, ry: float, rz: float, w := 12, h := 9) -> Dictionary:
	var V := PackedVector3Array()
	var UV := PackedVector2Array()
	for r in h + 1:
		var ph := -PI / 2.0 + PI * r / h
		var cr := cos(ph)
		for j in w + 1:
			var a := float(j) / w * TAU
			V.append(Vector3(cos(a) * cr * rx, sin(ph) * ry, sin(a) * cr * rz))
			UV.append(Vector2(float(j) / w, float(r) / h))
	return _grid(V, UV, h, w, true, 0)

## Catmull-Rom tube with taper, optional flattening (blades)
static func taper(pts: Array, r0: float, r1: float, radial := 7, segs := 12, flat := 1.0) -> Dictionary:
	var P := []
	for p in pts:
		P.append(Vector3(p[0], p[1], p[2]))
	var m := P.size()
	var C := []
	for k in segs + 1:
		var s := float(k) / segs * (m - 1)
		var i := mini(m - 2, int(s))
		var f := s - i
		var a: Vector3 = P[maxi(0, i - 1)]
		var b: Vector3 = P[i]
		var c: Vector3 = P[mini(m - 1, i + 1)]
		var d: Vector3 = P[mini(m - 1, i + 2)]
		C.append(Vector3(_crom(a.x, b.x, c.x, d.x, f), _crom(a.y, b.y, c.y, d.y, f), _crom(a.z, b.z, c.z, d.z, f)))
	var V := PackedVector3Array()
	var UV := PackedVector2Array()
	var T0: Vector3 = (C[1] - C[0]).normalized()
	var Nn := Vector3.UP if absf(T0.y) < 0.9 else Vector3.RIGHT
	Nn = (Nn - T0 * Nn.dot(T0)).normalized()
	for k in segs + 1:
		var T: Vector3 = (C[mini(segs, k + 1)] - C[maxi(0, k - 1)]).normalized()
		Nn = (Nn - T * Nn.dot(T)).normalized()
		var B := T.cross(Nn)
		var r := lerpf(r0, r1, float(k) / segs)
		for j in radial + 1:
			var a := float(j) / radial * TAU
			V.append(C[k] + Nn * cos(a) * r + B * sin(a) * r * flat)
			UV.append(Vector2(float(j) / radial, float(k) / segs))
	return _grid(V, UV, segs, radial, true, 1)

## three.js-style sphere (x = -cos(phi) sin(theta)) used for heads, masks, hoods
static func sphere_part(phi0: float, phil: float, th0: float, thl: float, w := 28, h := 20) -> Dictionary:
	var V := PackedVector3Array()
	var UV := PackedVector2Array()
	for r in h + 1:
		var th := th0 + thl * r / h
		for j in w + 1:
			var ph := phi0 + phil * j / w
			V.append(Vector3(-cos(ph) * sin(th), cos(th), sin(ph) * sin(th)))
			UV.append(Vector2(float(j) / w, float(r) / h))
	return {V = V, UV = UV, w = w, h = h, wrap = phil >= TAU - 0.001}

static func _ft(F: Array, c: Array, s: Array, a: float) -> void:
	F.append([c[0], c[1], c[2], s[0], s[1], s[2], a])

static func _sym(F: Array, c: Array, s: Array, a: float) -> void:
	_ft(F, c, s, a)
	_ft(F, [c[0], c[1], -c[2]], s, a)

## open cylinder band (three.js convention: x = r sin t, z = r cos t)
static func band(rt: float, rb: float, h: float, th0: float, thl: float, seg := 16) -> Dictionary:
	var V := PackedVector3Array()
	var UV := PackedVector2Array()
	for r in 2:
		var rad := rb if r == 0 else rt
		for j in seg + 1:
			var t := th0 + thl * j / seg
			V.append(Vector3(rad * sin(t), -h * 0.5 + h * r, rad * cos(t)))
			UV.append(Vector2(float(j) / seg, float(r)))
	return _grid(V, UV, 1, seg, false, 1)

## apply a transform to a generator dict (returns a copy)
static func xform(g: Dictionary, x: Transform3D) -> Dictionary:
	var v := PackedVector3Array()
	var n := PackedVector3Array()
	var nb := x.basis.inverse().transposed()
	for k in g.v.size():
		v.append(x * g.v[k])
		n.append((nb * g.n[k]).normalized())
	var o := g.duplicate()
	o.v = v
	o.n = n
	if x.basis.determinant() < 0.0: o.flip = not g.get("flip", true)
	return o

## partial sphere shell (pauldrons, hoods)
static func spherep(r: float, phi0: float, phil: float, th0: float, thl: float, w := 16, h := 8) -> Dictionary:
	var sp := sphere_part(phi0, phil, th0, thl, w, h)
	var V: PackedVector3Array = sp.V
	for i in V.size():
		V[i] = V[i] * r
	return _grid(V, sp.UV, h, w, sp.wrap, 0)

## Sculpted head / skull / mask shell. o: w,h,d (radii), feature amounts, part=[phi0,phil,th0,thl]
static func head(o: Dictionary) -> Dictionary:
	var part: Array = o.get("part", [0.0, TAU, 0.0, PI])
	var res: int = o.get("res", 30)
	var sp := sphere_part(part[0], part[1], part[2], part[3], res, int(res * 0.72))
	var F := []
	_sym(F, [0.82, 0.22, 0.32], [0.22, 0.1, 0.22], o.get("brow", 0.012)); _ft(F, [0.92, 0.24, 0.0], [0.15, 0.1, 0.2], o.get("brow", 0.012) * 0.7)
	_sym(F, [0.8, 0.07, 0.36], [0.17, 0.13, 0.16], -o.get("sock", 0.012))
	_ft(F, [0.98, -0.12, 0.0], [0.1, 0.22, 0.09], o.get("nose", 0.018))
	_sym(F, [0.62, -0.06, 0.72], [0.22, 0.15, 0.18], o.get("cheek", 0.008))
	_sym(F, [0.65, -0.42, 0.62], [0.25, 0.2, 0.2], -o.get("hollow", 0.004))
	_ft(F, [0.94, -0.47, 0.0], [0.1, 0.06, 0.32], -o.get("mouth", 0.004))
	_ft(F, [0.85, -0.82, 0.0], [0.18, 0.15, 0.25], o.get("chin", 0.01))
	_sym(F, [0.3, 0.35, 0.92], [0.2, 0.2, 0.15], -0.004)
	if o.get("skull", false): _ft(F, [0.97, -0.13, 0.0], [0.08, 0.12, 0.07], -0.024)
	var V: PackedVector3Array = sp.V
	var D: float = o.d
	var H: float = o.h
	var Wd: float = o.w
	var jaw: float = o.get("jaw", 0.25)
	var jawF: float = o.get("jawF", 0.012)
	var k: float = o.get("scale", 1.0)
	for i in V.size():
		var x := V[i].x
		var y := V[i].y
		var z := V[i].z
		var X := x * D
		var Y := y * H
		var Z := z * Wd
		if x < 0.0: X *= 1.08
		var jl := smoothstep(-0.15, -1.0, y)
		Z *= 1.0 - jaw * jl
		X += jawF * jl * maxf(0.0, x)
		if x > 0.55: X = lerpf(X, X * 0.93, smoothstep(0.55, 1.0, x))
		var disp := 0.0
		for q in F:
			var dx: float = (x - q[0]) / q[3]
			var dy: float = (y - q[1]) / q[4]
			var dz: float = (z - q[2]) / q[5]
			disp += q[6] * exp(-(dx * dx + dy * dy + dz * dz))
		var l := sqrt(X * X + Y * Y + Z * Z)
		if l < 1e-6: l = 1.0
		V[i] = Vector3(X + X / l * disp, Y + Y / l * disp, Z + Z / l * disp) * k
	return _grid(V, sp.UV, sp.h, sp.w, sp.wrap, 0)

## convert a Godot primitive mesh to a generator dict (already clockwise)
static func prim(mesh: PrimitiveMesh) -> Dictionary:
	var a := mesh.get_mesh_arrays()
	var idx = a[Mesh.ARRAY_INDEX]
	if idx == null or idx.size() == 0:
		idx = PackedInt32Array(range(a[Mesh.ARRAY_VERTEX].size()))
	return {v = a[Mesh.ARRAY_VERTEX], n = a[Mesh.ARRAY_NORMAL], uv = a[Mesh.ARRAY_TEX_UV], i = idx, flip = false}

static func cyl(r_top: float, r_bot: float, h: float, seg := 10) -> Dictionary:
	var m := CylinderMesh.new()
	m.top_radius = r_top
	m.bottom_radius = r_bot
	m.height = h
	m.radial_segments = seg
	m.rings = 1
	return prim(m)

static func cone(r: float, h: float, seg := 7) -> Dictionary:
	return cyl(0.0, r, h, seg)

static func torus(r: float, tube: float, seg := 14, ring := 6) -> Dictionary:
	var m := TorusMesh.new()
	m.inner_radius = r - tube
	m.outer_radius = r + tube
	m.rings = seg
	m.ring_segments = ring
	return prim(m)

static func box(x: float, y: float, z: float) -> Dictionary:
	var m := BoxMesh.new()
	m.size = Vector3(x, y, z)
	return prim(m)

static func capsule(r: float, h: float) -> Dictionary:
	var m := CapsuleMesh.new()
	m.radius = r
	m.height = h + r * 2.0
	m.radial_segments = 8
	m.rings = 2
	return prim(m)

static func plane(w: float, h: float, sx := 1, sz := 1) -> Dictionary:
	var m := PlaneMesh.new()
	m.size = Vector2(w, h)
	m.subdivide_width = sx
	m.subdivide_depth = sz
	return prim(m)

## Mesh builder: merges generator parts per material
class MB extends RefCounted:
	var parts := {}
	var order := []

	func add(g: Dictionary, x: Transform3D, mat: Material) -> void:
		if not parts.has(mat):
			parts[mat] = [PackedVector3Array(), PackedVector3Array(), PackedVector2Array(), PackedInt32Array(), PackedColorArray()]
			order.append(mat)
		var P: Array = parts[mat]
		var base: int = P[0].size()
		var nb := x.basis.inverse().transposed()
		var gv: PackedVector3Array = g.v
		var gn: PackedVector3Array = g.n
		var guv: PackedVector2Array = g.uv
		var vv: PackedVector3Array = P[0]
		var nn: PackedVector3Array = P[1]
		var uu: PackedVector2Array = P[2]
		var cc: PackedColorArray = P[4]
		var has_c := g.has("c")
		for k in gv.size():
			vv.append(x * gv[k])
			nn.append((nb * gn[k]).normalized())
			uu.append(guv[k] if k < guv.size() else Vector2.ZERO)
			cc.append(g.c[k] if has_c else Color.WHITE)
		var gi: PackedInt32Array = g.i
		var ii: PackedInt32Array = P[3]
		var flip: bool = g.get("flip", true)
		if x.basis.determinant() < 0.0: flip = not flip
		for k in range(0, gi.size(), 3):
			if flip:
				ii.append(base + gi[k]); ii.append(base + gi[k + 2]); ii.append(base + gi[k + 1])
			else:
				ii.append(base + gi[k]); ii.append(base + gi[k + 1]); ii.append(base + gi[k + 2])
		P[0] = vv; P[1] = nn; P[2] = uu; P[3] = ii; P[4] = cc

	func empty() -> bool:
		return parts.is_empty()

	func build() -> ArrayMesh:
		var am := ArrayMesh.new()
		for mat in order:
			var P: Array = parts[mat]
			var arr := []
			arr.resize(Mesh.ARRAY_MAX)
			arr[Mesh.ARRAY_VERTEX] = P[0]
			arr[Mesh.ARRAY_NORMAL] = P[1]
			arr[Mesh.ARRAY_TEX_UV] = P[2]
			arr[Mesh.ARRAY_COLOR] = P[4]
			arr[Mesh.ARRAY_INDEX] = P[3]
			am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
			am.surface_set_material(am.get_surface_count() - 1, mat)
		return am
