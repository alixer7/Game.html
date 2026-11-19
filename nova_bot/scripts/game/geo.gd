class_name Geo
extends RefCounted
## Procedural mesh library (cached): bevelled boxes, lathed shapes, curved panels, noisy rocks / island
## undersides, crystal shards and tubes. Godot front faces are clockwise; every triangle passes through
## _tri(), which fixes the winding from the vertex normals, so callers never have to think about it.

static var _cache: Dictionary = {}


class Builder:
	var v := PackedVector3Array()
	var n := PackedVector3Array()
	var uv := PackedVector2Array()
	var col := PackedColorArray()
	var idx := PackedInt32Array()
	var use_col: bool = false

	func add(p: Vector3, nrm: Vector3, t: Vector2 = Vector2.ZERO, c: Color = Color.WHITE) -> int:
		v.append(p)
		n.append(nrm)
		uv.append(t)
		col.append(c)
		return v.size() - 1

	func tri(a: int, b: int, c: int) -> void:
		var pa: Vector3 = v[a]
		var cr: Vector3 = (v[b] - pa).cross(v[c] - pa)
		var ref: Vector3 = n[a] + n[b] + n[c]
		if cr.dot(ref) > 0.0:
			idx.append(a)
			idx.append(c)
			idx.append(b)
		else:
			idx.append(a)
			idx.append(b)
			idx.append(c)

	func quad(a: int, b: int, c: int, d: int) -> void:
		tri(a, b, c)
		tri(a, c, d)

	## Flat-shaded triangle (own vertices, face normal pointing away from `inside`).
	func flat_tri(a: Vector3, b: Vector3, c: Vector3, inside: Vector3, colr: Color = Color.WHITE) -> void:
		var nrm: Vector3 = (b - a).cross(c - a).normalized()
		if nrm.dot((a + b + c) / 3.0 - inside) < 0.0:
			nrm = -nrm
		var ia: int = add(a, nrm, Vector2(a.x, a.z), colr)
		var ib: int = add(b, nrm, Vector2(b.x, b.z), colr)
		var ic: int = add(c, nrm, Vector2(c.x, c.z), colr)
		tri(ia, ib, ic)

	func commit(m: ArrayMesh = null) -> ArrayMesh:
		var mesh: ArrayMesh = m if m != null else ArrayMesh.new()
		if v.size() == 0:
			return mesh
		var arr: Array = []
		arr.resize(Mesh.ARRAY_MAX)
		arr[Mesh.ARRAY_VERTEX] = v
		arr[Mesh.ARRAY_NORMAL] = n
		arr[Mesh.ARRAY_TEX_UV] = uv
		if use_col:
			arr[Mesh.ARRAY_COLOR] = col
		arr[Mesh.ARRAY_INDEX] = idx
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
		return mesh


static func _rb_coords(hh: float, r: float, seg: int, mid: int) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	var inner: float = hh - r
	for k in range(seg + 1):
		var a: float = (1.0 - float(k) / float(seg)) * PI * 0.5
		out.append(-inner - r * sin(a))
	for k in range(1, mid):
		out.append(-inner + 2.0 * inner * float(k) / float(mid))
	for k in range(seg + 1):
		var a2: float = float(k) / float(seg) * PI * 0.5
		var x: float = inner + r * sin(a2)
		if k == 0 and inner < 0.0005:
			continue
		out.append(x)
	return out


## Box with rounded edges / corners (radius r), centred on the origin. UV = local xz (top) for shaders.
static func rounded_box(size: Vector3, radius: float, seg: int = 3) -> ArrayMesh:
	var key: String = "rb%.3f_%.3f_%.3f_%.3f_%d" % [size.x, size.y, size.z, radius, seg]
	if _cache.has(key):
		return _cache[key]
	var h: Vector3 = size * 0.5
	var r: float = clampf(radius, 0.001, minf(h.x, minf(h.y, h.z)) * 0.999)
	var inner: Vector3 = h - Vector3(r, r, r)
	var b := Builder.new()
	var coords: Array = []
	for ax in range(3):
		var mid: int = clampi(int(inner[ax] * 2.0 / 2.5), 1, 8)
		coords.append(_rb_coords(h[ax], r, seg, mid))
	for ax in range(3):
		var ua: int = (ax + 1) % 3
		var va: int = (ax + 2) % 3
		var cu: PackedFloat32Array = coords[ua]
		var cv: PackedFloat32Array = coords[va]
		for s in [-1.0, 1.0]:
			var sg: float = s
			var base: int = b.v.size()
			for i in range(cu.size()):
				for j in range(cv.size()):
					var p := Vector3.ZERO
					p[ax] = sg * h[ax]
					p[ua] = cu[i]
					p[va] = cv[j]
					var q: Vector3 = p.clamp(-inner, inner)
					var d: Vector3 = p - q
					var nrm: Vector3
					if d.length() < 0.00001:
						nrm = Vector3.ZERO
						nrm[ax] = sg
					else:
						nrm = d.normalized()
					b.add(q + nrm * r, nrm, Vector2(cu[i], cv[j]))
			var nj: int = cv.size()
			for i in range(cu.size() - 1):
				for j in range(nj - 1):
					var a0: int = base + i * nj + j
					b.quad(a0, a0 + nj, a0 + nj + 1, a0 + 1)
	var mesh: ArrayMesh = b.commit()
	_cache[key] = mesh
	return mesh


## Surface of revolution around Y. profile = [Vector2(radius, y), ...] bottom to top. Repeat a point to make a crease.
static func lathe(profile: PackedVector2Array, segs: int = 24, key: String = "") -> ArrayMesh:
	if key != "" and _cache.has(key):
		return _cache[key]
	var b := Builder.new()
	var np: int = profile.size()
	var lens := PackedFloat32Array()
	var total: float = 0.0
	for i in range(np):
		if i > 0:
			total += profile[i].distance_to(profile[i - 1])
		lens.append(total)
	var rows: Array = []
	for i in range(np):
		var p: Vector2 = profile[i]
		var t := Vector2.ZERO
		var has_prev: bool = i > 0 and profile[i].distance_to(profile[i - 1]) > 0.0001
		var has_next: bool = i < np - 1 and profile[i].distance_to(profile[i + 1]) > 0.0001
		if has_prev and has_next:
			t = (profile[i + 1] - profile[i - 1])
		elif has_next:
			t = profile[i + 1] - profile[i]
		elif has_prev:
			t = profile[i] - profile[i - 1]
		else:
			t = Vector2(0.0, 1.0)
		var n2 := Vector2(t.y, -t.x).normalized()
		var row := PackedInt32Array()
		for j in range(segs + 1):
			var th: float = TAU * float(j) / float(segs)
			var c: float = cos(th)
			var s: float = sin(th)
			var pos := Vector3(p.x * c, p.y, p.x * s)
			var nrm := Vector3(n2.x * c, n2.y, n2.x * s)
			if nrm.length() < 0.001:
				nrm = Vector3.UP
			row.append(b.add(pos, nrm.normalized(), Vector2(float(j) / float(segs), lens[i] / maxf(total, 0.0001))))
		rows.append(row)
	for i in range(np - 1):
		var r0: PackedInt32Array = rows[i]
		var r1: PackedInt32Array = rows[i + 1]
		for j in range(segs):
			b.quad(r0[j], r1[j], r1[j + 1], r0[j + 1])
	var mesh: ArrayMesh = b.commit()
	if key != "":
		_cache[key] = mesh
	return mesh


## Rounded "pill" profile helper for lathe(): a capsule-ish solid of radius r and height h (bottom at 0).
static func pill_profile(r: float, h: float, round_r: float, steps: int = 4) -> PackedVector2Array:
	var p := PackedVector2Array()
	var rr: float = minf(round_r, minf(r, h * 0.5))
	p.append(Vector2(0.0, 0.0))
	for k in range(steps + 1):
		var a: float = -PI * 0.5 + PI * 0.5 * float(k) / float(steps)
		p.append(Vector2(r - rr + cos(a) * rr, rr + sin(a) * rr))
	for k in range(steps + 1):
		var a2: float = PI * 0.5 * float(k) / float(steps)
		p.append(Vector2(r - rr + cos(a2) * rr, h - rr + sin(a2) * rr))
	p.append(Vector2(0.0, h))
	return p


## Gently curved rectangular panel facing -Z (visor / screens). UV covers 0..1 on both axes.
static func curved_panel(w: float, h: float, bulge_x: float, bulge_y: float, segs: int = 12) -> ArrayMesh:
	var key: String = "cp%.3f_%.3f_%.3f_%.3f_%d" % [w, h, bulge_x, bulge_y, segs]
	if _cache.has(key):
		return _cache[key]
	var b := Builder.new()
	var grid: Array = []
	for i in range(segs + 1):
		var row := PackedInt32Array()
		var u: float = float(i) / float(segs)
		for j in range(segs + 1):
			var vv: float = float(j) / float(segs)
			var x: float = (u - 0.5) * w
			var y: float = (vv - 0.5) * h
			var ux: float = 2.0 * u - 1.0
			var vy: float = 2.0 * vv - 1.0
			var z: float = -(bulge_x * (1.0 - ux * ux) + bulge_y * (1.0 - vy * vy))
			var dzdx: float = -(bulge_x * (-2.0 * ux) * 2.0 / w)
			var dzdy: float = -(bulge_y * (-2.0 * vy) * 2.0 / h)
			var nrm := Vector3(dzdx, dzdy, -1.0).normalized()
			row.append(b.add(Vector3(x, y, z), nrm, Vector2(u, 1.0 - vv)))
		grid.append(row)
	for i in range(segs):
		var r0: PackedInt32Array = grid[i]
		var r1: PackedInt32Array = grid[i + 1]
		for j in range(segs):
			b.quad(r0[j], r1[j], r1[j + 1], r0[j + 1])
	var mesh: ArrayMesh = b.commit()
	_cache[key] = mesh
	return mesh


static func _noise(seed_v: int, freq: float) -> FastNoiseLite:
	var fn := FastNoiseLite.new()
	fn.seed = seed_v
	fn.frequency = freq
	fn.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	fn.fractal_type = FastNoiseLite.FRACTAL_FBM
	fn.fractal_octaves = 3
	return fn


## Floating-island underside below a platform footprint (top rim at y = 0, tip at -depth).
## round_shape = true for discs. Flat shaded for a carved low-poly look. Vertex colour.r = depth ratio.
static func island(half_w: float, half_d: float, depth: float, seed_v: int, round_shape: bool, rough: float = 0.35) -> ArrayMesh:
	var key: String = "is%.2f_%.2f_%.2f_%d_%d_%.2f" % [half_w, half_d, depth, seed_v, 1 if round_shape else 0, rough]
	if _cache.has(key):
		return _cache[key]
	var fn: FastNoiseLite = _noise(seed_v, 0.35)
	var segs: int = clampi(int((half_w + half_d) * 2.2), 12, 40)
	var rings: int = clampi(int(depth * 1.1), 4, 10)
	var ex: float = 2.0 if round_shape else 6.0
	var pts: Array = []
	for k in range(rings + 1):
		var t: float = float(k) / float(rings)
		var row: Array = []
		var sc: float = (1.0 - pow(t, 1.35)) * (1.0 - 0.1 * t)
		var y: float = -depth * pow(t, 0.85)
		for j in range(segs):
			var th: float = TAU * float(j) / float(segs)
			var c: float = cos(th)
			var s: float = sin(th)
			var x: float = half_w * signf(c) * pow(absf(c), 2.0 / ex)
			var z: float = half_d * signf(s) * pow(absf(s), 2.0 / ex)
			var p := Vector3(x * sc, y, z * sc)
			if k > 0:
				var nz: float = fn.get_noise_3d(p.x * 1.3, p.y * 1.3, p.z * 1.3)
				var horiz := Vector3(p.x, 0.0, p.z)
				var hl: float = horiz.length()
				if hl > 0.01:
					p += horiz / hl * nz * rough * minf(half_w, half_d) * (0.6 + t)
				p.y += fn.get_noise_3d(p.x * 0.7 + 50.0, 0.0, p.z * 0.7) * rough * 0.8
			row.append(p)
		pts.append(row)
	var tip := Vector3(fn.get_noise_2d(3.0, 7.0) * half_w * 0.2, -depth * 1.08, fn.get_noise_2d(9.0, 1.0) * half_d * 0.2)
	var b := Builder.new()
	b.use_col = true
	var ctr := Vector3(0.0, -depth * 0.4, 0.0)
	for k in range(rings):
		var r0: Array = pts[k]
		var r1: Array = pts[k + 1]
		var ca := Color(float(k) / float(rings), 0.0, 0.0)
		var cb := Color(float(k + 1) / float(rings), 0.0, 0.0)
		for j in range(segs):
			var j1: int = (j + 1) % segs
			b.flat_tri(r0[j], r1[j], r1[j1], ctr, ca)
			b.flat_tri(r0[j], r1[j1], r0[j1], ctr, cb)
	var last: Array = pts[rings]
	for j in range(segs):
		b.flat_tri(last[j], tip, last[(j + 1) % segs], ctr, Color(1.0, 0.0, 0.0))
	var mesh: ArrayMesh = b.commit()
	_cache[key] = mesh
	return mesh


## Lumpy rock (displaced icosphere), flat shaded. Used for scenery, debris and asteroid chunks.
static func rock(radius: float, seed_v: int, detail: int = 1, rough: float = 0.3) -> ArrayMesh:
	var key: String = "rk%.2f_%d_%d_%.2f" % [radius, seed_v, detail, rough]
	if _cache.has(key):
		return _cache[key]
	var ico: Array = _icosphere(detail)
	var verts: PackedVector3Array = ico[0]
	var faces: PackedInt32Array = ico[1]
	var fn: FastNoiseLite = _noise(seed_v, 1.2)
	var disp := PackedVector3Array()
	for p in verts:
		var d: float = 1.0 + fn.get_noise_3d(p.x * 2.0, p.y * 2.0, p.z * 2.0) * rough * 2.0
		disp.append(p * radius * d)
	var b := Builder.new()
	for i in range(0, faces.size(), 3):
		b.flat_tri(disp[faces[i]], disp[faces[i + 1]], disp[faces[i + 2]], Vector3.ZERO)
	var mesh: ArrayMesh = b.commit()
	_cache[key] = mesh
	return mesh


static func _icosphere(detail: int) -> Array:
	var t: float = (1.0 + sqrt(5.0)) / 2.0
	var verts := PackedVector3Array([
		Vector3(-1, t, 0), Vector3(1, t, 0), Vector3(-1, -t, 0), Vector3(1, -t, 0),
		Vector3(0, -1, t), Vector3(0, 1, t), Vector3(0, -1, -t), Vector3(0, 1, -t),
		Vector3(t, 0, -1), Vector3(t, 0, 1), Vector3(-t, 0, -1), Vector3(-t, 0, 1)])
	for i in range(verts.size()):
		verts[i] = verts[i].normalized()
	var faces := PackedInt32Array([0, 11, 5, 0, 5, 1, 0, 1, 7, 0, 7, 10, 0, 10, 11, 1, 5, 9, 5, 11, 4, 11, 10, 2, 10, 7, 6, 7, 1, 8,
		3, 9, 4, 3, 4, 2, 3, 2, 6, 3, 6, 8, 3, 8, 9, 4, 9, 5, 2, 4, 11, 6, 2, 10, 8, 6, 7, 9, 8, 1])
	for _d in range(detail):
		var mids: Dictionary = {}
		var nf := PackedInt32Array()
		for i in range(0, faces.size(), 3):
			var a: int = faces[i]
			var bb: int = faces[i + 1]
			var c: int = faces[i + 2]
			var ab: int = _mid(verts, mids, a, bb)
			var bc: int = _mid(verts, mids, bb, c)
			var ca: int = _mid(verts, mids, c, a)
			nf.append_array(PackedInt32Array([a, ab, ca, bb, bc, ab, c, ca, bc, ab, bc, ca]))
		faces = nf
	return [verts, faces]


static func _mid(verts: PackedVector3Array, mids: Dictionary, a: int, b: int) -> int:
	var k: int = mini(a, b) * 100000 + maxi(a, b)
	if mids.has(k):
		return mids[k]
	verts.append(((verts[a] + verts[b]) * 0.5).normalized())
	mids[k] = verts.size() - 1
	return verts.size() - 1


## Crystal: hexagonal prism with a pointed tip (base at y = 0). Returns the mesh; facets are flat shaded.
static func crystal(r: float, h: float, tip: float, sides: int = 6) -> ArrayMesh:
	var key: String = "cr%.2f_%.2f_%.2f_%d" % [r, h, tip, sides]
	if _cache.has(key):
		return _cache[key]
	var b := Builder.new()
	var ctr := Vector3(0.0, h * 0.5, 0.0)
	var lo: Array = []
	var hi: Array = []
	for i in range(sides):
		var a: float = TAU * float(i) / float(sides)
		lo.append(Vector3(cos(a) * r * 0.82, 0.0, sin(a) * r * 0.82))
		hi.append(Vector3(cos(a) * r, h, sin(a) * r))
	var top := Vector3(0.0, h + tip, 0.0)
	for i in range(sides):
		var j: int = (i + 1) % sides
		b.flat_tri(lo[i], hi[i], hi[j], ctr)
		b.flat_tri(lo[i], hi[j], lo[j], ctr)
		b.flat_tri(hi[i], top, hi[j], ctr)
		b.flat_tri(lo[i], lo[j], Vector3.ZERO, ctr + Vector3(0.0, 1.0, 0.0))
	var mesh: ArrayMesh = b.commit()
	_cache[key] = mesh
	return mesh


## Random sharp shard (for glass / crystal / ice shatter). Returns [mesh, points] (points for a convex shape).
static func shard(size: float, seed_v: int) -> Array:
	var key: String = "sh%.2f_%d" % [size, seed_v]
	if _cache.has(key):
		return _cache[key]
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_v
	var pts := PackedVector3Array()
	var n: int = 5 + rng.randi() % 2
	for i in range(n):
		var dir := Vector3(rng.randf_range(-1.0, 1.0), rng.randf_range(-1.0, 1.0), rng.randf_range(-1.0, 1.0)).normalized()
		var stretch := Vector3(0.55, 1.6, 0.4)
		pts.append(dir * stretch * size * rng.randf_range(0.45, 1.0))
	var hull: Array = _hull_tris(pts)
	var b := Builder.new()
	var ctr := Vector3.ZERO
	for p in pts:
		ctr += p
	ctr /= float(pts.size())
	for tr in hull:
		var t3: Array = tr
		b.flat_tri(pts[t3[0]], pts[t3[1]], pts[t3[2]], ctr)
	var res: Array = [b.commit(), pts]
	_cache[key] = res
	return res


## Brute-force convex hull for a handful of points (fine for <= 8 points).
static func _hull_tris(pts: PackedVector3Array) -> Array:
	var out: Array = []
	var n: int = pts.size()
	for i in range(n):
		for j in range(i + 1, n):
			for k in range(j + 1, n):
				var nrm: Vector3 = (pts[j] - pts[i]).cross(pts[k] - pts[i])
				if nrm.length() < 0.000001:
					continue
				var pos: int = 0
				var neg: int = 0
				for m in range(n):
					if m == i or m == j or m == k:
						continue
					var d: float = nrm.dot(pts[m] - pts[i])
					if d > 0.00001:
						pos += 1
					elif d < -0.00001:
						neg += 1
				if pos == 0 or neg == 0:
					out.append([i, j, k])
	return out


## Tube along a polyline (pipes, cables). Smooth normals, open ends.
static func tube(path: PackedVector3Array, radius: float, sides: int = 8) -> ArrayMesh:
	var b := Builder.new()
	var rows: Array = []
	for i in range(path.size()):
		var t: Vector3
		if i == 0:
			t = path[1] - path[0]
		elif i == path.size() - 1:
			t = path[i] - path[i - 1]
		else:
			t = path[i + 1] - path[i - 1]
		t = t.normalized()
		var up: Vector3 = Vector3.UP if absf(t.dot(Vector3.UP)) < 0.95 else Vector3.RIGHT
		var x: Vector3 = t.cross(up).normalized()
		var y: Vector3 = x.cross(t).normalized()
		var row := PackedInt32Array()
		for j in range(sides + 1):
			var a: float = TAU * float(j) / float(sides)
			var nrm: Vector3 = x * cos(a) + y * sin(a)
			row.append(b.add(path[i] + nrm * radius, nrm, Vector2(float(j) / float(sides), float(i))))
		rows.append(row)
	for i in range(path.size() - 1):
		var r0: PackedInt32Array = rows[i]
		var r1: PackedInt32Array = rows[i + 1]
		for j in range(sides):
			b.quad(r0[j], r1[j], r1[j + 1], r0[j + 1])
	return b.commit()


## Simple sphere / capsule / cylinder wrappers with shared settings.
static func sphere(r: float, segs: int = 20) -> SphereMesh:
	var key: String = "sp%.3f_%d" % [r, segs]
	if _cache.has(key):
		return _cache[key]
	var m := SphereMesh.new()
	m.radius = r
	m.height = r * 2.0
	m.radial_segments = segs
	m.rings = maxi(segs / 2, 4)
	_cache[key] = m
	return m


static func cyl(rt: float, rb: float, h: float, segs: int = 20) -> CylinderMesh:
	var key: String = "cy%.3f_%.3f_%.3f_%d" % [rt, rb, h, segs]
	if _cache.has(key):
		return _cache[key]
	var m := CylinderMesh.new()
	m.top_radius = rt
	m.bottom_radius = rb
	m.height = h
	m.radial_segments = segs
	m.rings = 1
	_cache[key] = m
	return m


static func torus(r_in: float, r_out: float, rings: int = 32, segs: int = 8) -> TorusMesh:
	var key: String = "to%.3f_%.3f_%d_%d" % [r_in, r_out, rings, segs]
	if _cache.has(key):
		return _cache[key]
	var m := TorusMesh.new()
	m.inner_radius = r_in
	m.outer_radius = r_out
	m.rings = rings
	m.ring_segments = segs
	_cache[key] = m
	return m


static func box(s: Vector3) -> BoxMesh:
	var key: String = "bx%.3f_%.3f_%.3f" % [s.x, s.y, s.z]
	if _cache.has(key):
		return _cache[key]
	var m := BoxMesh.new()
	m.size = s
	_cache[key] = m
	return m


## Adds a MeshInstance3D child; returns it.
static func put(parent: Node3D, mesh: Mesh, mat: Material, pos: Vector3 = Vector3.ZERO, rot_deg: Vector3 = Vector3.ZERO, scl: Vector3 = Vector3.ONE, shadow: bool = true) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	mi.rotation_degrees = rot_deg
	mi.scale = scl
	if not shadow:
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi
