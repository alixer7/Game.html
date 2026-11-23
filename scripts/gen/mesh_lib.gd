class_name MeshLib
extends RefCounted
## Procedural model library. All geometry is generated here (no external assets),
## stylized-but-detailed: smooth displaced shapes, baked vertex occlusion and
## colour variation, separate LODs for scattering.

static var _ico_cache := {}


# =================================================================== primitives
static func icosphere(subdiv: int) -> Dictionary:
	if _ico_cache.has(subdiv):
		return _ico_cache[subdiv]
	var t := (1.0 + sqrt(5.0)) / 2.0
	var v: Array[Vector3] = [
		Vector3(-1, t, 0), Vector3(1, t, 0), Vector3(-1, -t, 0), Vector3(1, -t, 0),
		Vector3(0, -1, t), Vector3(0, 1, t), Vector3(0, -1, -t), Vector3(0, 1, -t),
		Vector3(t, 0, -1), Vector3(t, 0, 1), Vector3(-t, 0, -1), Vector3(-t, 0, 1)]
	for i in v.size():
		v[i] = v[i].normalized()
	var f: Array = [
		[0, 11, 5], [0, 5, 1], [0, 1, 7], [0, 7, 10], [0, 10, 11],
		[1, 5, 9], [5, 11, 4], [11, 10, 2], [10, 7, 6], [7, 1, 8],
		[3, 9, 4], [3, 4, 2], [3, 2, 6], [3, 6, 8], [3, 8, 9],
		[4, 9, 5], [2, 4, 11], [6, 2, 10], [8, 6, 7], [9, 8, 1]]
	for s in subdiv:
		var cache := {}
		var nf: Array = []
		for tri in f:
			var m := []
			for k in 3:
				var a: int = tri[k]
				var b: int = tri[(k + 1) % 3]
				var key := Vector2i(mini(a, b), maxi(a, b))
				if not cache.has(key):
					v.append(((v[a] + v[b]) * 0.5).normalized())
					cache[key] = v.size() - 1
				m.append(cache[key])
			nf.append([tri[0], m[0], m[2]])
			nf.append([tri[1], m[1], m[0]])
			nf.append([tri[2], m[2], m[1]])
			nf.append([m[0], m[1], m[2]])
		f = nf
	var res := {"v": v, "f": f}
	_ico_cache[subdiv] = res
	return res


static func blob(mb: MeshBuilder, center: Vector3, radii: Vector3, subdiv: int, noise: FastNoiseLite,
		amp: float, col_bottom: Color, col_top: Color, fluffy := 0.0, sway_base := -1.0, flat_bottom := -2.0) -> void:
	## Noise-displaced ellipsoid with vertical colour gradient (baked AO underneath).
	## fluffy > 0 blends normals toward the radial direction (soft canopy shading).
	## sway_base >= 0 writes a sway weight into COLOR.a based on height above it.
	var ico := icosphere(subdiv)
	var base := mb.vcount()
	var vs: Array = ico["v"]
	var pts := PackedVector3Array()
	pts.resize(vs.size())
	for i in vs.size():
		var d: Vector3 = vs[i]
		var p := d * radii
		var nv := noise.get_noise_3dv(center + p * 1.7) if noise else 0.0
		p += d * radii * nv * amp
		if p.y < flat_bottom * radii.y:
			p.y = lerpf(p.y, flat_bottom * radii.y, 0.85)
		pts[i] = center + p
	for i in vs.size():
		var d: Vector3 = vs[i]
		var h := clampf(d.y * 0.5 + 0.5, 0.0, 1.0)
		var c := col_bottom.lerp(col_top, smoothstep(0.0, 1.0, h))
		if sway_base >= 0.0:
			c.a = clampf((pts[i].y - sway_base) / 6.0, 0.0, 1.0)
		else:
			c.a = 1.0
		mb.add_vertex(pts[i], d, Vector2(d.x * 0.5 + 0.5, d.y * 0.5 + 0.5), c)
	for tri in ico["f"]:
		var ta: int = tri[0]
		var tb: int = tri[1]
		var tc: int = tri[2]
		var fn: Vector3 = (vs[tb] - vs[ta]).cross(vs[tc] - vs[ta])
		if fn.dot(vs[ta] + vs[tb] + vs[tc]) >= 0.0:
			mb.tri(base + ta, base + tb, base + tc)
		else:
			mb.tri(base + ta, base + tc, base + tb)
	# smooth normals for this blob only
	var sub := MeshBuilder.new()
	sub.verts = mb.verts.slice(base)
	sub.norms = mb.norms.slice(base)
	for k in range(mb.idx.size() - ico["f"].size() * 3, mb.idx.size()):
		sub.idx.append(mb.idx[k] - base)
	sub.recompute_normals()
	for i in sub.verts.size():
		var n := sub.norms[i]
		if fluffy > 0.0:
			var radial: Vector3 = (sub.verts[i] - center).normalized()
			n = n.lerp(radial, fluffy).normalized()
		mb.norms[base + i] = n


static func lathe(mb: MeshBuilder, profile: PackedVector2Array, segments: int, xf: Transform3D,
		col_fn: Callable = Callable(), cap_top := false) -> void:
	## profile: (radius, y) pairs from bottom to top.
	var base := mb.vcount()
	var rows := profile.size()
	for r in rows:
		var pr := profile[r]
		var tang := Vector2.ZERO
		if r == 0:
			tang = profile[1] - profile[0]
		elif r == rows - 1:
			tang = profile[r] - profile[r - 1]
		else:
			tang = profile[r + 1] - profile[r - 1]
		var n2 := Vector2(tang.y, -tang.x).normalized()   # outward in (r, y)
		for s in segments + 1:
			var a := TAU * float(s) / float(segments)
			var dir := Vector3(cos(a), 0.0, sin(a))
			var p := dir * pr.x + Vector3.UP * pr.y
			var n := (dir * n2.x + Vector3.UP * n2.y).normalized()
			var c := Color.WHITE
			if col_fn.is_valid():
				c = col_fn.call(float(r) / float(rows - 1), a, p)
			mb.add_vertex(xf * p, (xf.basis * n).normalized(), Vector2(float(s) / segments, float(r) / (rows - 1)), c)
	for r in rows - 1:
		for s in segments:
			var a := base + r * (segments + 1) + s
			var b := a + segments + 1
			mb.quad(a, b, b + 1, a + 1)
	if cap_top:
		var top := profile[rows - 1]
		var ci := mb.add_vertex(xf * Vector3(0, top.y, 0), (xf.basis * Vector3.UP).normalized(), Vector2(0.5, 0.5),
			col_fn.call(1.0, 0.0, Vector3(0, top.y, 0)) if col_fn.is_valid() else Color.WHITE)
		var ring := base + (rows - 1) * (segments + 1)
		for s in segments:
			mb.tri(ci, ring + s + 1, ring + s)


static func tube(mb: MeshBuilder, path: PackedVector3Array, radii: PackedFloat32Array, sides: int,
		col_fn: Callable = Callable(), uv_v_scale := 1.0, cap_end := true, wobble: FastNoiseLite = null, wobble_amp := 0.0) -> void:
	## Generalized cylinder with parallel-transport frames.
	var n := path.size()
	if n < 2:
		return
	var base := mb.vcount()
	var t0 := (path[1] - path[0]).normalized()
	var ref := Vector3.UP if absf(t0.dot(Vector3.UP)) < 0.95 else Vector3.RIGHT
	var nrm := t0.cross(ref).normalized()
	var acc_len := 0.0
	for i in n:
		var t: Vector3
		if i == 0:
			t = path[1] - path[0]
		elif i == n - 1:
			t = path[i] - path[i - 1]
		else:
			t = path[i + 1] - path[i - 1]
		t = t.normalized()
		# parallel transport
		nrm = (nrm - t * nrm.dot(t)).normalized()
		var bin := t.cross(nrm).normalized()
		if i > 0:
			acc_len += path[i].distance_to(path[i - 1])
		var r := radii[i]
		for s in sides + 1:
			var a := TAU * float(s) / float(sides)
			var dir := (nrm * cos(a) + bin * sin(a))
			var rr := r
			if wobble:
				rr *= 1.0 + wobble.get_noise_3dv(path[i] * 2.0 + dir) * wobble_amp
			var p := path[i] + dir * rr
			var c := Color.WHITE
			if col_fn.is_valid():
				c = col_fn.call(float(i) / float(n - 1), a, p)
			mb.add_vertex(p, dir, Vector2(float(s) / sides, acc_len * uv_v_scale), c)
	for i in n - 1:
		for s in sides:
			var a := base + i * (sides + 1) + s
			var b := a + sides + 1
			mb.quad(a, a + 1, b + 1, b)
	if cap_end and radii[n - 1] > 0.02:
		var last := base + (n - 1) * (sides + 1)
		var tend := (path[n - 1] - path[n - 2]).normalized()
		var c := mb.cols[last]
		var ci := mb.add_vertex(path[n - 1] + tend * radii[n - 1] * 0.3, tend, Vector2(0.5, 0.5), c)
		for s in sides:
			mb.tri(ci, last + s, last + s + 1)


static func box(mb: MeshBuilder, xf: Transform3D, size: Vector3, col: Color, bevel := 0.0) -> void:
	## Axis box (optionally chamfered on vertical edges) with flat normals.
	var h := size * 0.5
	if bevel <= 0.0:
		var faces := [
			[Vector3(1, 0, 0), Vector3(0, 0, -1), Vector3(0, 1, 0)],
			[Vector3(-1, 0, 0), Vector3(0, 0, 1), Vector3(0, 1, 0)],
			[Vector3(0, 1, 0), Vector3(1, 0, 0), Vector3(0, 0, -1)],
			[Vector3(0, -1, 0), Vector3(1, 0, 0), Vector3(0, 0, 1)],
			[Vector3(0, 0, 1), Vector3(1, 0, 0), Vector3(0, 1, 0)],
			[Vector3(0, 0, -1), Vector3(-1, 0, 0), Vector3(0, 1, 0)]]
		for fc in faces:
			var nn: Vector3 = fc[0]
			var u: Vector3 = fc[1]
			var v: Vector3 = fc[2]
			var cen := nn * h
			var su := absf(u.dot(h))
			var sv := absf(v.dot(h))
			var wn := (xf.basis * nn).normalized()
			var shade := col * (0.82 + 0.18 * maxf(nn.y, 0.0))
			shade.a = col.a
			var i0 := mb.add_vertex(xf * (cen - u * su - v * sv), wn, Vector2(0, 1), shade)
			mb.add_vertex(xf * (cen + u * su - v * sv), wn, Vector2(1, 1), shade)
			mb.add_vertex(xf * (cen + u * su + v * sv), wn, Vector2(1, 0), shade)
			mb.add_vertex(xf * (cen - u * su + v * sv), wn, Vector2(0, 0), shade)
			mb.quad(i0, i0 + 1, i0 + 2, i0 + 3)
		return
	# chamfered prism: octagon footprint extruded in Y
	var b := minf(bevel, minf(h.x, h.z) * 0.9)
	var ring := PackedVector2Array([
		Vector2(h.x - b, -h.z), Vector2(h.x, -h.z + b), Vector2(h.x, h.z - b), Vector2(h.x - b, h.z),
		Vector2(-h.x + b, h.z), Vector2(-h.x, h.z - b), Vector2(-h.x, -h.z + b), Vector2(-h.x + b, -h.z)])
	prism(mb, xf * Transform3D(Basis(), Vector3(0, -h.y, 0)), ring, size.y, col)


static func prism(mb: MeshBuilder, xf: Transform3D, ring: PackedVector2Array, height: float, col: Color, cap := true) -> void:
	## Extrude a convex CCW (seen from above, x/z) polygon upward by height.
	var n := ring.size()
	for i in n:
		var a := ring[i]
		var b := ring[(i + 1) % n]
		var e := (b - a)
		var nn := Vector3(e.y, 0, -e.x).normalized()
		# make sure the normal points outward (polygon centred near origin)
		var mid := (a + b) * 0.5
		if nn.dot(Vector3(mid.x, 0, mid.y)) < 0.0:
			nn = -nn
		var wn := (xf.basis * nn).normalized()
		var c := col * 0.9
		c.a = col.a
		var i0 := mb.add_vertex(xf * Vector3(a.x, 0, a.y), wn, Vector2(0, 1), c)
		mb.add_vertex(xf * Vector3(b.x, 0, b.y), wn, Vector2(1, 1), c)
		mb.add_vertex(xf * Vector3(b.x, height, b.y), wn, Vector2(1, 0), col)
		mb.add_vertex(xf * Vector3(a.x, height, a.y), wn, Vector2(0, 0), col)
		# orientation: outward-facing quad
		var p0 := Vector3(a.x, 0, a.y)
		var p1 := Vector3(b.x, 0, b.y)
		var face_n := (p1 - p0).cross(Vector3.UP)
		if face_n.dot(nn) > 0.0:
			mb.quad(i0, i0 + 1, i0 + 2, i0 + 3)
		else:
			mb.quad(i0, i0 + 3, i0 + 2, i0 + 1)
	if cap:
		var up := (xf.basis * Vector3.UP).normalized()
		var c0 := mb.add_vertex(xf * Vector3(0, height, 0), up, Vector2(0.5, 0.5), col)
		for i in n:
			var a := ring[i]
			var b := ring[(i + 1) % n]
			var ia := mb.add_vertex(xf * Vector3(a.x, height, a.y), up, Vector2(a.x, a.y), col)
			var ib := mb.add_vertex(xf * Vector3(b.x, height, b.y), up, Vector2(b.x, b.y), col)
			var cr := Vector3(b.x, 0, b.y).cross(Vector3(a.x, 0, a.y))
			if cr.y > 0.0:
				mb.tri(c0, ib, ia)
			else:
				mb.tri(c0, ia, ib)


static func card(mb: MeshBuilder, xf: Transform3D, w: float, h: float, uv_rect: Rect2, col: Color, bend := 0.0) -> void:
	## Vertical card centred at bottom-middle, facing +Z, optionally bent backwards.
	var rows := 3 if bend != 0.0 else 1
	var base := mb.vcount()
	for r in rows + 1:
		var fy := float(r) / rows
		var z := -bend * fy * fy
		for cidx in 2:
			var fx := float(cidx)
			var p := Vector3((fx - 0.5) * w, fy * h, z)
			var c := col
			c.a = col.a * fy
			mb.add_vertex(xf * p, (xf.basis * Vector3(0, 0.3, 1)).normalized(),
				Vector2(uv_rect.position.x + uv_rect.size.x * fx, uv_rect.position.y + uv_rect.size.y * (1.0 - fy)), c)
	for r in rows:
		var a := base + r * 2
		mb.quad(a, a + 1, a + 3, a + 2)


static func make_noise(seed: int, freq := 0.6, octaves := 3) -> FastNoiseLite:
	var n := FastNoiseLite.new()
	n.seed = seed
	n.frequency = freq
	n.fractal_octaves = octaves
	n.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	return n


static func atlas_rect(q: int) -> Rect2:
	return Rect2(float(q % 2) * 0.5, float(q / 2) * 0.5, 0.5, 0.5)


# =================================================================== vegetation
static func broadleaf_tree(seed: int, lod: int, palette: int = 0) -> Dictionary:
	## Returns {"bark": MeshBuilder, "leaves": MeshBuilder, "cards": MeshBuilder, "height", "trunk_r"}
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var nz := make_noise(seed, 0.55)
	var H := rng.randf_range(7.5, 12.5)
	var r0 := rng.randf_range(0.28, 0.42) * H / 10.0 + 0.1
	var bark := MeshBuilder.new()
	var leaves := MeshBuilder.new()
	var cards := MeshBuilder.new()
	# (mobile budget: LOD0 ~650 tris, LOD1 ~150, LOD2 ~80)
	var sides: int = [7, 5, 4][lod]
	var bark_col := func(t: float, _a: float, _p: Vector3) -> Color:
		var k := lerpf(0.62, 1.0, clampf(t * 3.0, 0.0, 1.0))
		return Color(k, k * 0.97, k * 0.93, 1.0)
	# trunk with a slight S-curve
	var lean := Vector3(rng.randf_range(-0.6, 0.6), 0, rng.randf_range(-0.6, 0.6))
	var path := PackedVector3Array()
	var rad := PackedFloat32Array()
	var trunk_top := H * rng.randf_range(0.48, 0.58)
	var segs: int = [5, 3, 2][lod]
	for i in segs + 1:
		var t := float(i) / segs
		path.append(Vector3(lean.x * sin(t * PI * 0.8) , -0.4 + trunk_top * t, lean.z * sin(t * PI * 0.8)))
		rad.append(r0 * (1.0 + 0.9 * pow(1.0 - t, 4.0)) * lerpf(1.0, 0.62, t))
	tube(bark, path, rad, sides, bark_col, 0.35, false, nz if lod == 0 else null, 0.12)
	var top := path[path.size() - 1]
	# root flares
	if lod == 0:
		var nroots := rng.randi_range(3, 4)
		for k in nroots:
			var a := TAU * (float(k) + rng.randf() * 0.5) / nroots
			var dir := Vector3(cos(a), 0, sin(a))
			var rp := PackedVector3Array()
			var rr := PackedFloat32Array()
			var L := rng.randf_range(1.0, 2.0) * r0 * 3.0
			for j in 4:
				var t := float(j) / 3.0
				rp.append(dir * (r0 * 0.6 + L * t) + Vector3.UP * (0.55 * r0 * 2.0 * (1.0 - t) - 0.15 - t * 0.25))
				rr.append(r0 * 0.55 * (1.0 - t * 0.85))
			tube(bark, rp, rr, 4, bark_col, 0.35, false)
	# branches + canopy clusters
	var nb := rng.randi_range(3, 5)
	var canopy_centres: Array[Vector3] = []
	var R := H * rng.randf_range(0.24, 0.3)
	canopy_centres.append(top + Vector3(0, R * 0.75, 0))
	for k in nb:
		var a := TAU * (float(k) + rng.randf() * 0.6) / nb
		var dir := Vector3(cos(a), rng.randf_range(0.5, 0.95), sin(a)).normalized()
		var L := H * rng.randf_range(0.26, 0.36)
		var start := top - Vector3(0, rng.randf_range(0.0, trunk_top * 0.25), 0)
		var bp := PackedVector3Array()
		var br := PackedFloat32Array()
		for j in 4:
			var t := float(j) / 3.0
			bp.append(start + dir * L * t + Vector3.UP * (t * t * L * 0.25))
			br.append(r0 * 0.55 * (1.0 - t * 0.7))
		if lod == 0:
			tube(bark, bp, br, 4, bark_col, 0.35, true)
		if lod < 2 or k < 2:
			canopy_centres.append(bp[3] + Vector3.UP * R * 0.25)
	var pal := [
		[Color(0.13, 0.30, 0.10), Color(0.42, 0.66, 0.20)],
		[Color(0.16, 0.32, 0.08), Color(0.55, 0.72, 0.22)],
		[Color(0.10, 0.27, 0.14), Color(0.30, 0.58, 0.26)],
		[Color(0.30, 0.25, 0.06), Color(0.85, 0.62, 0.18)],
	]
	var pc: Array = pal[palette % pal.size()]
	for i in canopy_centres.size():
		var c := canopy_centres[i]
		var rr := R * (1.0 if i == 0 else rng.randf_range(0.62, 0.8))
		var radii := Vector3(rr * rng.randf_range(0.95, 1.2), rr * rng.randf_range(0.72, 0.9), rr * rng.randf_range(0.95, 1.2))
		var hue := rng.randf_range(-0.04, 0.04)
		var cb: Color = pc[0]
		var ct: Color = pc[1]
		cb = Color.from_hsv(fposmod(cb.h + hue, 1.0), cb.s, cb.v)
		ct = Color.from_hsv(fposmod(ct.h + hue, 1.0), ct.s, ct.v * rng.randf_range(0.9, 1.08))
		var sub := 1 if lod == 0 else 0
		blob(leaves, c, radii * (1.12 if lod == 2 else 1.0), sub, nz, 0.3, cb, ct, 0.78, trunk_top * 0.7)
		if lod == 0:
			var ncards := 6
			for k in ncards:
				var a := TAU * (float(k) + rng.randf()) / ncards
				var el := rng.randf_range(-0.4, 0.9)
				var dir := Vector3(cos(a) * cos(el), sin(el), sin(a) * cos(el))
				var pos := c + dir * radii * 0.9
				var b := Basis.looking_at(-dir, Vector3.UP if absf(dir.y) < 0.9 else Vector3.FORWARD)
				var size := rr * rng.randf_range(0.7, 1.0)
				var cc := ct.lightened(0.35)
				cc.a = clampf((pos.y - trunk_top * 0.7) / 6.0, 0.2, 1.0)
				card(cards, Transform3D(b, pos - b.y * size * 0.5), size, size, atlas_rect(palette % 4 if palette < 3 else 3), cc)
	return {"bark": bark, "leaves": leaves, "cards": cards, "height": H, "trunk_r": r0 * 1.2}


static func pine_tree(seed: int, lod: int) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var H := rng.randf_range(9.0, 16.0)
	var r0 := 0.18 + H * 0.018
	var bark := MeshBuilder.new()
	var leaves := MeshBuilder.new()
	var bark_col := func(t: float, _a: float, _p: Vector3) -> Color:
		var k := lerpf(0.55, 0.9, t)
		return Color(k, k * 0.92, k * 0.88)
	tube(bark, PackedVector3Array([Vector3(0, -0.4, 0), Vector3(0, H * 0.5, 0), Vector3(0, H * 0.95, 0)]),
		PackedFloat32Array([r0 * 1.4, r0 * 0.7, r0 * 0.15]), [7, 5, 4][lod], bark_col, 0.3, false)
	var tiers := rng.randi_range(5, 7) if lod == 0 else (4 if lod == 1 else 3)
	var sides: int = [11, 7, 5][lod]
	var base_y := H * 0.22
	for k in tiers:
		var t := float(k) / tiers
		var y0 := lerpf(base_y, H * 0.86, t)
		var tier_h := (H - base_y) / tiers * 1.55
		var rad := lerpf(H * 0.25, H * 0.07, t) * rng.randf_range(0.92, 1.08)
		var dark := Color(0.06, 0.20, 0.13).lerp(Color(0.10, 0.27, 0.15), t)
		var light := Color(0.17, 0.40, 0.22).lerp(Color(0.30, 0.52, 0.26), t)
		var base_i := leaves.vcount()
		var apex := leaves.add_vertex(Vector3(0, y0 + tier_h, 0), Vector3.UP, Vector2(0.5, 0), Color(light.r, light.g, light.b, clampf(t + 0.3, 0, 1)))
		var rim: Array[int] = []
		var inner: Array[int] = []
		for s in sides:
			var a := TAU * (float(s) + rng.randf() * 0.25) / sides + k * 0.4
			var droop := rng.randf_range(0.25, 0.6)
			var rr := rad * rng.randf_range(0.85, 1.12)
			var p := Vector3(cos(a) * rr, y0 - droop, sin(a) * rr)
			var n := Vector3(cos(a), 0.65, sin(a)).normalized()
			var cc := dark.lerp(light, 0.4)
			cc.a = clampf(t + 0.35, 0, 1)
			rim.append(leaves.add_vertex(p, n, Vector2(float(s) / sides, 1), cc))
			var a2 := a + PI / sides
			var p2 := Vector3(cos(a2) * rr * 0.72, y0 + 0.1, sin(a2) * rr * 0.72)
			var dc := dark
			dc.a = cc.a
			inner.append(leaves.add_vertex(p2, Vector3(cos(a2), 0.3, sin(a2)).normalized(), Vector2(float(s) / sides, 0.9), dc))
		for s in sides:
			var s2 := (s + 1) % sides
			leaves.tri(apex, rim[s], inner[s])
			leaves.tri(apex, inner[s], rim[s2])
			# underside
			var uc := leaves.add_vertex(Vector3(0, y0 + 0.2, 0), Vector3.DOWN, Vector2(0.5, 0.5), Color(dark.r * 0.6, dark.g * 0.6, dark.b * 0.6, 0.3))
			leaves.tri(uc, inner[s], rim[s])
			leaves.tri(uc, rim[s2], inner[s])
		var _unused := base_i
	return {"bark": bark, "leaves": leaves, "cards": MeshBuilder.new(), "height": H, "trunk_r": r0 * 1.3}


static func birch_tree(seed: int, lod: int) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var nz := make_noise(seed + 7, 0.8)
	var H := rng.randf_range(8.0, 12.0)
	var bark := MeshBuilder.new()
	var leaves := MeshBuilder.new()
	var cards := MeshBuilder.new()
	var marks := make_noise(seed + 3, 2.2)
	var bark_col := func(_t: float, a: float, p: Vector3) -> Color:
		var m := marks.get_noise_2d(a * 3.0, p.y * 4.0)
		var k := 0.2 if m > 0.45 else 0.95
		return Color(k, k, k * 0.96)
	var lean := Vector3(rng.randf_range(-0.8, 0.8), 0, rng.randf_range(-0.8, 0.8))
	var path := PackedVector3Array()
	var rad := PackedFloat32Array()
	for i in 6:
		var t := float(i) / 5.0
		path.append(Vector3(lean.x * t * t, -0.3 + H * 0.75 * t, lean.z * t * t))
		rad.append(lerpf(0.24, 0.07, t))
	tube(bark, path, rad, 7 if lod == 0 else 5, bark_col, 0.5, true)
	var top := path[5]
	for k in 4:
		var c := top + Vector3(rng.randf_range(-1.4, 1.4), rng.randf_range(-2.2, 0.8), rng.randf_range(-1.4, 1.4))
		var r := rng.randf_range(1.4, 2.1)
		blob(leaves, c, Vector3(r, r * 1.15, r), 1 if lod == 0 else 0, nz, 0.35, Color(0.25, 0.42, 0.10), Color(0.68, 0.80, 0.28), 0.6, H * 0.4)
		if lod == 0:
			for j in 5:
				var a := TAU * (float(j) + rng.randf()) / 5.0
				var dir := Vector3(cos(a), rng.randf_range(-0.3, 0.6), sin(a)).normalized()
				var b := Basis.looking_at(-dir, Vector3.UP)
				var cc := Color(0.75, 0.85, 0.45, clampf((c.y - H * 0.4) / 6.0, 0.2, 1.0))
				card(cards, Transform3D(b, c + dir * r * 0.85 - b.y * r * 0.5), r * 1.1, r * 1.1, atlas_rect(1), cc)
	return {"bark": bark, "leaves": leaves, "cards": cards, "height": H, "trunk_r": 0.28}


static func bush(seed: int, lod: int, flowering := false) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var nz := make_noise(seed, 0.9)
	var leaves := MeshBuilder.new()
	var cards := MeshBuilder.new()
	var n := rng.randi_range(3, 4) if lod == 0 else 1
	var R := rng.randf_range(0.7, 1.3)
	var cols := [Color(0.12, 0.30, 0.09), Color(0.40, 0.62, 0.17)]
	if rng.randf() < 0.3:
		cols = [Color(0.10, 0.28, 0.16), Color(0.30, 0.56, 0.30)]
	for k in n:
		var a := TAU * float(k) / n + rng.randf()
		var c := Vector3(cos(a) * R * 0.5, R * rng.randf_range(0.45, 0.8), sin(a) * R * 0.5)
		var r := R * rng.randf_range(0.55, 0.8)
		if lod > 0:
			c = Vector3(0, R * 0.6, 0)
			r = R * 1.05
		blob(leaves, c, Vector3(r, r * 0.85, r), 1, nz, 0.3, cols[0], cols[1], 0.7, 0.0, -0.6)
		if flowering:
			for j in 6:
				var d := Vector3(rng.randf_range(-1, 1), rng.randf_range(0.1, 1), rng.randf_range(-1, 1)).normalized()
				var fc := [Color(1.0, 0.55, 0.75), Color(1.0, 0.95, 0.9), Color(1.0, 0.82, 0.3)][rng.randi_range(0, 2)] as Color
				blob(leaves, c + d * r * 0.95, Vector3.ONE * 0.12, 0, null, 0.0, fc * 0.9, fc, 0.0, 0.0)
		if lod == 0:
			for j in 2:
				var a2 := TAU * (float(j) + rng.randf()) / 2.0
				var dir := Vector3(cos(a2), rng.randf_range(0.0, 0.7), sin(a2)).normalized()
				var b := Basis.looking_at(-dir, Vector3.UP)
				var cc: Color = (cols[1] as Color).lerp(cols[0], 0.3)
				cc.a = 0.5
				card(cards, Transform3D(b, c + dir * r * 0.8 - b.y * r * 0.5), r * 1.2, r * 1.2, atlas_rect(rng.randi_range(0, 2)), cc)
	return {"leaves": leaves, "cards": cards, "radius": R}


static func fern(seed: int) -> MeshBuilder:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var mb := MeshBuilder.new()
	var fronds := rng.randi_range(7, 11)
	var dark := Color(0.08, 0.26, 0.08)
	var light := Color(0.35, 0.62, 0.18)
	for f in fronds:
		var a := TAU * (float(f) + rng.randf() * 0.4) / fronds
		var L := rng.randf_range(0.8, 1.4)
		var dir := Vector3(cos(a), 0, sin(a))
		var side := dir.cross(Vector3.UP)
		var rise := rng.randf_range(0.6, 1.0)
		var segs := 9
		var prev := Vector3.ZERO
		for s in segs:
			var t0 := float(s) / segs
			var t1 := float(s + 1) / segs
			var p0 := dir * L * t0 + Vector3.UP * (sin(t0 * PI * 0.85) * rise * L * 0.7)
			var p1 := dir * L * t1 + Vector3.UP * (sin(t1 * PI * 0.85) * rise * L * 0.7)
			var lw := 0.16 * L * sin((1.0 - t0) * PI * 0.5 + 0.2) * (1.0 - t0 * 0.6)
			var c0 := dark.lerp(light, t0)
			c0.a = t0
			var c1 := dark.lerp(light, t1)
			c1.a = t1
			var nrm := Vector3.UP
			var i0 := mb.add_vertex(p0, nrm, Vector2(0, t0), c0)
			var i1 := mb.add_vertex(p1, nrm, Vector2(0, t1), c1)
			var il := mb.add_vertex((p0 + p1) * 0.5 + side * lw + Vector3.DOWN * lw * 0.3, nrm, Vector2(1, t0), c0)
			var ir := mb.add_vertex((p0 + p1) * 0.5 - side * lw + Vector3.DOWN * lw * 0.3, nrm, Vector2(1, t0), c0)
			mb.tri(i0, il, i1)
			mb.tri(i0, i1, ir)
			prev = p1
	mb.recompute_normals()
	for i in mb.norms.size():
		mb.norms[i] = (mb.norms[i] + Vector3.UP * 1.5).normalized()
	return mb


static func grass_clump(seed: int, blades := 9, height := 0.55, dry := false) -> MeshBuilder:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var mb := MeshBuilder.new()
	var base_c := Color(0.12, 0.30, 0.07) if not dry else Color(0.35, 0.33, 0.12)
	var tip_c := Color(0.50, 0.74, 0.22) if not dry else Color(0.85, 0.78, 0.40)
	for b in blades:
		var a := rng.randf() * TAU
		var r := rng.randf() * 0.25
		var root := Vector3(cos(a) * r, -0.05, sin(a) * r)
		var lean_dir := Vector3(cos(a + rng.randf_range(-0.6, 0.6)), 0, sin(a + rng.randf_range(-0.6, 0.6)))
		var h := height * rng.randf_range(0.6, 1.25)
		var w := 0.05 * rng.randf_range(0.8, 1.3)
		var side := lean_dir.cross(Vector3.UP).normalized()
		var mid := root + Vector3.UP * h * 0.55 + lean_dir * h * 0.15
		var tip := root + Vector3.UP * h + lean_dir * h * 0.45
		var n := (lean_dir * -0.3 + Vector3.UP).normalized()
		var tc := tip_c * rng.randf_range(0.85, 1.1)
		var i0 := mb.add_vertex(root - side * w, n, Vector2(0, 1), Color(base_c.r, base_c.g, base_c.b, 0.0))
		var i1 := mb.add_vertex(root + side * w, n, Vector2(1, 1), Color(base_c.r, base_c.g, base_c.b, 0.0))
		var i2 := mb.add_vertex(mid + side * w * 0.7, n, Vector2(1, 0.5), Color(base_c.lerp(tc, 0.55), 0.45))
		var i3 := mb.add_vertex(mid - side * w * 0.7, n, Vector2(0, 0.5), Color(base_c.lerp(tc, 0.55), 0.45))
		var i4 := mb.add_vertex(tip, n, Vector2(0.5, 0), Color(tc.r, tc.g, tc.b, 1.0))
		mb.quad(i0, i1, i2, i3)
		mb.tri(i3, i2, i4)
	return mb


static func flower(seed: int, col: Color) -> MeshBuilder:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var mb := MeshBuilder.new()
	var stems := rng.randi_range(2, 4)
	for s in stems:
		var off := Vector3(rng.randf_range(-0.15, 0.15), 0, rng.randf_range(-0.15, 0.15))
		var h := rng.randf_range(0.3, 0.6)
		var stem_c := Color(0.18, 0.42, 0.12, 0.0)
		var top := off + Vector3(rng.randf_range(-0.05, 0.05), h, rng.randf_range(-0.05, 0.05))
		var side := Vector3(0.012, 0, 0)
		var i0 := mb.add_vertex(off - side, Vector3.UP, Vector2.ZERO, stem_c)
		var i1 := mb.add_vertex(off + side, Vector3.UP, Vector2.ZERO, stem_c)
		var i2 := mb.add_vertex(top + side, Vector3.UP, Vector2.ZERO, Color(0.22, 0.5, 0.15, 1.0))
		var i3 := mb.add_vertex(top - side, Vector3.UP, Vector2.ZERO, Color(0.22, 0.5, 0.15, 1.0))
		mb.quad(i0, i1, i2, i3)
		var petals := 5
		var pr := rng.randf_range(0.07, 0.11)
		var pc := col * rng.randf_range(0.9, 1.1)
		pc.a = 1.0
		var ci := mb.add_vertex(top + Vector3.UP * 0.02, Vector3.UP, Vector2.ZERO, Color(1.0, 0.85, 0.25, 1.0))
		for p in petals:
			var a0 := TAU * float(p) / petals
			var a1 := TAU * (float(p) + 0.5) / petals
			var a2 := TAU * (float(p) + 1.0) / petals
			var pa := mb.add_vertex(top + Vector3(cos(a0) * pr * 0.5, 0.0, sin(a0) * pr * 0.5), Vector3.UP, Vector2.ZERO, pc)
			var pb := mb.add_vertex(top + Vector3(cos(a1) * pr, 0.03, sin(a1) * pr), Vector3.UP, Vector2.ZERO, pc * 1.1)
			var pd := mb.add_vertex(top + Vector3(cos(a2) * pr * 0.5, 0.0, sin(a2) * pr * 0.5), Vector3.UP, Vector2.ZERO, pc)
			mb.tri(ci, pa, pb)
			mb.tri(ci, pb, pd)
	return mb


static func mushroom_cluster(seed: int, giant := false) -> MeshBuilder:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var mb := MeshBuilder.new()
	var n := 1 if giant else rng.randi_range(2, 5)
	var caps := [Color(0.85, 0.18, 0.12), Color(0.92, 0.55, 0.20), Color(0.75, 0.62, 0.45), Color(0.55, 0.35, 0.75)]
	for k in n:
		var s := (rng.randf_range(2.5, 4.5) if giant else rng.randf_range(0.12, 0.3))
		var off := Vector3.ZERO if giant else Vector3(rng.randf_range(-0.3, 0.3), 0, rng.randf_range(-0.3, 0.3))
		var tilt := Basis(Vector3(rng.randf_range(-1, 1), 0, rng.randf_range(-1, 1)).normalized(), rng.randf_range(0.0, 0.25))
		var xf := Transform3D(tilt.scaled(Vector3.ONE * s), off)
		var stem := PackedVector2Array([Vector2(0.22, 0), Vector2(0.18, 0.4), Vector2(0.15, 0.9), Vector2(0.17, 1.15)])
		lathe(mb, stem, 8, xf, func(t: float, _a: float, _p: Vector3) -> Color: return Color(0.95, 0.92, 0.82).lerp(Color(0.85, 0.8, 0.7), t))
		var cap_col: Color = caps[rng.randi_range(0, caps.size() - 1)]
		var spots := make_noise(seed + k, 3.5)
		var cap := PackedVector2Array([Vector2(0.15, 1.05), Vector2(0.55, 1.0), Vector2(0.72, 1.12), Vector2(0.62, 1.35), Vector2(0.38, 1.55), Vector2(0.0, 1.62)])
		lathe(mb, cap, 12, xf, func(t: float, a: float, p: Vector3) -> Color:
			var sp := spots.get_noise_2d(a * 4.0, p.y * 6.0)
			if t < 0.2:
				return Color(0.9, 0.86, 0.75)
			return Color(1.0, 0.97, 0.9) if sp > 0.35 else cap_col * lerpf(0.85, 1.1, t))
	return mb


static func reeds(seed: int) -> MeshBuilder:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var mb := MeshBuilder.new()
	for b in rng.randi_range(8, 14):
		var a := rng.randf() * TAU
		var r := rng.randf() * 0.4
		var root := Vector3(cos(a) * r, -0.2, sin(a) * r)
		var h := rng.randf_range(1.0, 1.9)
		var lean := Vector3(rng.randf_range(-0.2, 0.2), 0, rng.randf_range(-0.2, 0.2))
		var side := Vector3(-lean.z, 0, lean.x).normalized() * 0.035 if lean.length() > 0.01 else Vector3(0.035, 0, 0)
		var tip := root + Vector3.UP * h + lean * h
		var i0 := mb.add_vertex(root - side, Vector3.UP, Vector2.ZERO, Color(0.2, 0.35, 0.12, 0.0))
		var i1 := mb.add_vertex(root + side, Vector3.UP, Vector2.ZERO, Color(0.2, 0.35, 0.12, 0.0))
		var i2 := mb.add_vertex(tip, Vector3.UP, Vector2.ZERO, Color(0.55, 0.68, 0.28, 1.0))
		mb.tri(i0, i1, i2)
		if rng.randf() < 0.35:
			var head := root + (tip - root) * 0.8
			var hp := PackedVector3Array([head, head + (tip - root).normalized() * 0.22])
			tube(mb, hp, PackedFloat32Array([0.045, 0.04]), 5, func(_t: float, _a: float, _p: Vector3) -> Color: return Color(0.38, 0.22, 0.1, 0.8))
	return mb


static func lily_pad(seed: int) -> MeshBuilder:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var mb := MeshBuilder.new()
	var r := rng.randf_range(0.35, 0.7)
	var ci := mb.add_vertex(Vector3(0, 0.02, 0), Vector3.UP, Vector2.ZERO, Color(0.25, 0.5, 0.15))
	var segs := 14
	var first := -1
	var prev := -1
	for s in segs + 1:
		var a := lerpf(0.35, TAU - 0.05, float(s) / segs)
		var i := mb.add_vertex(Vector3(cos(a) * r, 0.0, sin(a) * r), Vector3.UP, Vector2.ZERO, Color(0.30, 0.58, 0.18))
		if prev >= 0:
			mb.tri(ci, i, prev)
		prev = i
		if first < 0:
			first = i
	if rng.randf() < 0.35:
		var f := flower(seed + 1, Color(1.0, 0.8, 0.9))
		mb.append_builder(f, Transform3D(Basis().scaled(Vector3(1.4, 0.15, 1.4)), Vector3(0, 0.0, 0)))
	return mb


static func rock(seed: int, kind := 0, lod := 0) -> MeshBuilder:
	## kind 0 = boulder, 1 = tall standing stone, 2 = flat slab, 3 = river stone (smooth)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var nz := make_noise(seed, 0.7, 4)
	var mb := MeshBuilder.new()
	var radii: Vector3
	var amp := 0.45
	match kind:
		1:
			radii = Vector3(rng.randf_range(0.7, 1.0), rng.randf_range(1.6, 2.4), rng.randf_range(0.7, 1.0))
		2:
			radii = Vector3(rng.randf_range(1.4, 2.0), rng.randf_range(0.35, 0.55), rng.randf_range(1.1, 1.6))
		3:
			radii = Vector3(rng.randf_range(0.8, 1.2), rng.randf_range(0.45, 0.7), rng.randf_range(0.7, 1.0))
			amp = 0.18
		_:
			radii = Vector3(rng.randf_range(0.9, 1.3), rng.randf_range(0.7, 1.0), rng.randf_range(0.9, 1.2))
	var g := rng.randf_range(0.85, 1.05)
	blob(mb, Vector3(0, radii.y * 0.55, 0), radii, 2 if lod == 0 else 1, nz, amp,
		Color(0.62 * g, 0.6 * g, 0.6 * g, 1.0), Color(1.0 * g, 0.97 * g, 0.92 * g, 1.0), 0.0, -1.0, -0.45)
	return mb


static func log_mesh(length: float, radius: float, seed: int, with_branch_stubs := true) -> MeshBuilder:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var nz := make_noise(seed, 0.9)
	var mb := MeshBuilder.new()
	var path := PackedVector3Array()
	var rad := PackedFloat32Array()
	var n := maxi(4, int(length / 1.5))
	for i in n + 1:
		var t := float(i) / n
		path.append(Vector3(0, 0, -length * 0.5 + length * t) + Vector3(sin(t * 3.0 + seed) * 0.1, 0, 0))
		rad.append(radius * (1.0 - 0.15 * t))
	tube(mb, path, rad, 12, func(_t: float, _a: float, _p: Vector3) -> Color: return Color(0.95, 0.9, 0.85, 1.0), 0.4, false, nz, 0.06)
	# end caps with growth rings
	for e in 2:
		var cpos := path[0] if e == 0 else path[n]
		var nrm := Vector3(0, 0, -1) if e == 0 else Vector3(0, 0, 1)
		var r := rad[0] if e == 0 else rad[n]
		var ci := mb.add_vertex(cpos, nrm, Vector2(0.5, 0.5), Color(0.82, 0.62, 0.4))
		var ring_start := mb.vcount()
		for s in 13:
			var a := TAU * float(s) / 12.0
			var ring_c := Color(0.62, 0.42, 0.25) if s % 2 == 0 else Color(0.75, 0.55, 0.33)
			mb.add_vertex(cpos + Vector3(cos(a) * r, sin(a) * r, 0), nrm, Vector2(cos(a), sin(a)), ring_c)
		for s in 12:
			if e == 0:
				mb.tri(ci, ring_start + s + 1, ring_start + s)
			else:
				mb.tri(ci, ring_start + s, ring_start + s + 1)
	if with_branch_stubs:
		for k in rng.randi_range(2, 4):
			var t := rng.randf_range(0.2, 0.85)
			var a := rng.randf() * TAU
			var base := Vector3(0, 0, -length * 0.5 + length * t)
			var dir := Vector3(cos(a), sin(a), rng.randf_range(-0.3, 0.3)).normalized()
			tube(mb, PackedVector3Array([base + dir * radius * 0.6, base + dir * (radius + 0.6)]),
				PackedFloat32Array([radius * 0.25, radius * 0.12]), 5, func(_t: float, _a: float, _p: Vector3) -> Color: return Color(0.9, 0.85, 0.8))
	return mb


static func stump(seed: int) -> MeshBuilder:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var mb := MeshBuilder.new()
	var r := rng.randf_range(0.4, 0.7)
	var h := rng.randf_range(0.5, 1.1)
	var prof := PackedVector2Array([Vector2(r * 1.6, -0.2), Vector2(r * 1.15, 0.15), Vector2(r, 0.5), Vector2(r * 0.98, h)])
	lathe(mb, prof, 10, Transform3D(), func(_t: float, _a: float, _p: Vector3) -> Color: return Color(0.9, 0.85, 0.8), false)
	var ci := mb.add_vertex(Vector3(0, h, 0), Vector3.UP, Vector2(0.5, 0.5), Color(0.85, 0.65, 0.42))
	var rs := mb.vcount()
	for s in 11:
		var a := TAU * float(s) / 10.0
		mb.add_vertex(Vector3(cos(a) * r * 0.98, h, sin(a) * r * 0.98), Vector3.UP, Vector2.ZERO, Color(0.7, 0.5, 0.3))
	for s in 10:
		mb.tri(ci, rs + s + 1, rs + s)
	return mb


# =================================================================== props
static func lantern_post(seed: int) -> Dictionary:
	var mb := MeshBuilder.new()
	var glow := MeshBuilder.new()
	var wood := Color(0.45, 0.3, 0.18)
	box(mb, Transform3D(Basis(), Vector3(0, 1.1, 0)), Vector3(0.18, 2.2, 0.18), wood, 0.03)
	box(mb, Transform3D(Basis(), Vector3(0.3, 2.15, 0)), Vector3(0.7, 0.12, 0.12), wood)
	box(mb, Transform3D(Basis(), Vector3(0.55, 1.95, 0)), Vector3(0.05, 0.3, 0.05), Color(0.2, 0.2, 0.2))
	box(glow, Transform3D(Basis(), Vector3(0.55, 1.7, 0)), Vector3(0.28, 0.36, 0.28), Color(1.0, 0.8, 0.4))
	box(mb, Transform3D(Basis(), Vector3(0.55, 1.92, 0)), Vector3(0.36, 0.06, 0.36), Color(0.25, 0.22, 0.2))
	box(mb, Transform3D(Basis(), Vector3(0.55, 1.5, 0)), Vector3(0.32, 0.05, 0.32), Color(0.25, 0.22, 0.2))
	return {"solid": mb, "glow": glow}


static func chevron_sign(left: bool) -> MeshBuilder:
	## Wooden board with painted chevrons pointing the turn direction (readability).
	var mb := MeshBuilder.new()
	var wood := Color(0.42, 0.28, 0.16)
	box(mb, Transform3D(Basis(), Vector3(-0.9, 0.7, 0)), Vector3(0.14, 1.4, 0.14), wood)
	box(mb, Transform3D(Basis(), Vector3(0.9, 0.7, 0)), Vector3(0.14, 1.4, 0.14), wood)
	box(mb, Transform3D(Basis(), Vector3(0, 1.25, 0)), Vector3(2.3, 0.8, 0.08), Color(0.95, 0.92, 0.85))
	var dir := -1.0 if left else 1.0
	for k in 3:
		var x := (-0.7 + k * 0.7) * dir
		var c := Color(0.85, 0.18, 0.12)
		var p0 := Vector3(x - 0.18 * dir, 1.55, 0.05)
		var p1 := Vector3(x + 0.18 * dir, 1.25, 0.05)
		var p2 := Vector3(x - 0.18 * dir, 0.95, 0.05)
		var w := Vector3(0.16 * dir, 0, 0)
		var i0 := mb.add_vertex(p0, Vector3.BACK, Vector2.ZERO, c)
		var i1 := mb.add_vertex(p0 + w, Vector3.BACK, Vector2.ZERO, c)
		var i2 := mb.add_vertex(p1 + w, Vector3.BACK, Vector2.ZERO, c)
		var i3 := mb.add_vertex(p1, Vector3.BACK, Vector2.ZERO, c)
		var i4 := mb.add_vertex(p2 + w, Vector3.BACK, Vector2.ZERO, c)
		var i5 := mb.add_vertex(p2, Vector3.BACK, Vector2.ZERO, c)
		if dir > 0:
			mb.quad(i0, i3, i2, i1)
			mb.quad(i3, i5, i4, i2)
		else:
			mb.quad(i0, i1, i2, i3)
			mb.quad(i3, i2, i4, i5)
	return mb


static func ruin_pillar(seed: int, broken := true) -> MeshBuilder:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var mb := MeshBuilder.new()
	var h := rng.randf_range(2.0, 4.5) if broken else 5.0
	var stone := Color(0.9, 0.88, 0.82, 1.0)
	box(mb, Transform3D(Basis(), Vector3(0, 0.3, 0)), Vector3(1.6, 0.6, 1.6), stone, 0.15)
	var ring := PackedVector2Array()
	for s in 8:
		var a := TAU * float(s) / 8.0
		ring.append(Vector2(cos(a), sin(a)) * 0.55)
	var y := 0.6
	while y < h:
		var seg := rng.randf_range(0.7, 1.1)
		var off := Vector3(rng.randf_range(-0.05, 0.05), 0, rng.randf_range(-0.05, 0.05))
		var rot := Basis(Vector3.UP, rng.randf_range(-0.1, 0.1))
		prism(mb, Transform3D(rot, Vector3(off.x, y, off.z)), ring, minf(seg, h - y) - 0.03, stone * rng.randf_range(0.9, 1.0))
		y += seg
	if not broken:
		box(mb, Transform3D(Basis(), Vector3(0, h + 0.2, 0)), Vector3(1.5, 0.4, 1.5), stone, 0.1)
	return mb
