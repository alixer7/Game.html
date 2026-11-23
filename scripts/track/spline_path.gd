class_name SplinePath
extends RefCounted
## Centripetal Catmull-Rom path resampled at uniform arc length.
##
## Control point format (Array):
##   [x, y, z, width, bank_deg]            or
##   [x, y, z, width, bank_deg, {attrs}]   where attrs may contain
##     "s":  surface id (Surfaces.*) from this point on
##     "wl"/"wr": wall style left/right from this point on ("none", "stone", "rail", "rock", "log", "flume")
##     "tm": terrain mode from this point on ("conform", "none")
##     "tag": free-form tag for this stretch (used by gameplay e.g. "lip", "pad")
## Positive bank raises the RIGHT edge (good for left-handers).

var closed := false
var spacing := 1.5
var length := 0.0

var pos := PackedVector3Array()
var tan := PackedVector3Array()
var right := PackedVector3Array()
var up := PackedVector3Array()
var width := PackedFloat32Array()
var bank := PackedFloat32Array()
var dist := PackedFloat32Array()
var surface := PackedInt32Array()
var wall_l := PackedStringArray()
var wall_r := PackedStringArray()
var terrain_mode := PackedStringArray()
var tags := PackedStringArray()

var _grid := {}
var _cell := 12.0


static func from_points(points: Array, is_closed := false, sample_spacing := 1.5) -> SplinePath:
	var sp := SplinePath.new()
	sp.closed = is_closed
	sp.spacing = sample_spacing
	sp._build(points)
	return sp


func size() -> int:
	return pos.size()


func _build(points: Array) -> void:
	var n := points.size()
	assert(n >= 2)
	var P: Array[Vector3] = []
	var W := PackedFloat32Array()
	var B := PackedFloat32Array()
	var attrs: Array = []
	var cur := {"s": Surfaces.ROAD, "wl": "none", "wr": "none", "tm": "conform", "tag": ""}
	for i in n:
		var cp: Array = points[i]
		P.append(Vector3(cp[0], cp[1], cp[2]))
		W.append(cp[3] if cp.size() > 3 else 10.0)
		B.append(cp[4] if cp.size() > 4 else 0.0)
		if cp.size() > 5 and cp[5] is Dictionary:
			var d: Dictionary = cp[5]
			for k in d:
				cur[k] = d[k]
			if not d.has("tag"):
				cur["tag"] = ""
		else:
			cur["tag"] = ""
		attrs.append(cur.duplicate())

	# ---- dense sampling of the curve
	var seg_count := n if closed else n - 1
	var dense_p: Array[Vector3] = []
	var dense_seg := PackedInt32Array()
	var dense_t := PackedFloat32Array()
	var sub := 24
	for s in seg_count:
		var i1 := s
		var i2 := (s + 1) % n
		var i0 := (s - 1 + n) % n if closed else maxi(s - 1, 0)
		var i3 := (s + 2) % n if closed else mini(s + 2, n - 1)
		var p0 := P[i0]
		var p1 := P[i1]
		var p2 := P[i2]
		var p3 := P[i3]
		if not closed and s == 0:
			p0 = p1 - (p2 - p1)
		if not closed and s == seg_count - 1:
			p3 = p2 + (p2 - p1)
		var last := sub if (not closed and s == seg_count - 1) else sub - 1
		for k in last + 1:
			var t := float(k) / float(sub)
			dense_p.append(_catmull(p0, p1, p2, p3, t))
			dense_seg.append(s)
			dense_t.append(t)
	# cumulative length
	var cum := PackedFloat32Array()
	cum.resize(dense_p.size())
	cum[0] = 0.0
	for i in range(1, dense_p.size()):
		cum[i] = cum[i - 1] + dense_p[i].distance_to(dense_p[i - 1])
	var total := cum[cum.size() - 1]
	if closed:
		total += dense_p[dense_p.size() - 1].distance_to(dense_p[0])
	length = total

	# ---- uniform resample
	var count := maxi(int(ceil(total / spacing)), 2)
	var step := total / float(count)
	if not closed:
		count += 1
	var j := 0
	for k in count:
		var d := minf(step * k, total)
		while j < dense_p.size() - 1 and cum[j + 1] < d:
			j += 1
		var a := dense_p[j]
		var b: Vector3
		var seg_len: float
		var j2 := j + 1
		if j2 >= dense_p.size():
			b = dense_p[0]
			seg_len = total - cum[j]
		else:
			b = dense_p[j2]
			seg_len = cum[j2] - cum[j]
		var f := 0.0 if seg_len <= 1e-5 else clampf((d - cum[j]) / seg_len, 0.0, 1.0)
		var p := a.lerp(b, f)
		var seg := dense_seg[j]
		var tt := lerpf(dense_t[j], dense_t[j2] if j2 < dense_p.size() and dense_seg[j2] == seg else 1.0, f)
		var i1 := seg
		var i2 := (seg + 1) % n
		var ws := smoothstep(0.0, 1.0, tt)
		pos.append(p)
		width.append(lerpf(W[i1], W[i2], ws))
		bank.append(lerpf(B[i1], B[i2], ws))
		dist.append(d)
		var at: Dictionary = attrs[i1]
		surface.append(int(at["s"]))
		wall_l.append(str(at["wl"]))
		wall_r.append(str(at["wr"]))
		terrain_mode.append(str(at["tm"]))
		tags.append(str(at["tag"]))
	_compute_frames()
	_build_grid()


static func _catmull(p0: Vector3, p1: Vector3, p2: Vector3, p3: Vector3, t: float) -> Vector3:
	# centripetal Catmull-Rom (alpha = 0.5) -> no cusps or self intersections
	var t0 := 0.0
	var t1 := t0 + pow(maxf(p0.distance_to(p1), 1e-4), 0.5)
	var t2 := t1 + pow(maxf(p1.distance_to(p2), 1e-4), 0.5)
	var t3 := t2 + pow(maxf(p2.distance_to(p3), 1e-4), 0.5)
	var tt := lerpf(t1, t2, t)
	var a1 := p0 * ((t1 - tt) / (t1 - t0)) + p1 * ((tt - t0) / (t1 - t0))
	var a2 := p1 * ((t2 - tt) / (t2 - t1)) + p2 * ((tt - t1) / (t2 - t1))
	var a3 := p2 * ((t3 - tt) / (t3 - t2)) + p3 * ((tt - t2) / (t3 - t2))
	var b1 := a1 * ((t2 - tt) / (t2 - t0)) + a2 * ((tt - t0) / (t2 - t0))
	var b2 := a2 * ((t3 - tt) / (t3 - t1)) + a3 * ((tt - t1) / (t3 - t1))
	return b1 * ((t2 - tt) / (t2 - t1)) + b2 * ((tt - t1) / (t2 - t1))


func _compute_frames() -> void:
	var n := pos.size()
	tan.resize(n)
	right.resize(n)
	up.resize(n)
	for i in n:
		var a: Vector3
		var b: Vector3
		if closed:
			a = pos[(i - 1 + n) % n]
			b = pos[(i + 1) % n]
		else:
			a = pos[maxi(i - 1, 0)]
			b = pos[mini(i + 1, n - 1)]
		var t := (b - a).normalized()
		var r := t.cross(Vector3.UP)
		if r.length_squared() < 1e-6:
			r = Vector3.RIGHT
		r = r.normalized()
		var u := r.cross(t).normalized()
		var bk := deg_to_rad(bank[i])
		var r2 := r * cos(bk) + u * sin(bk)
		var u2 := u * cos(bk) - r * sin(bk)
		tan[i] = t
		right[i] = r2.normalized()
		up[i] = u2.normalized()


func _key(x: float, z: float) -> Vector2i:
	return Vector2i(floori(x / _cell), floori(z / _cell))


func _build_grid() -> void:
	_grid.clear()
	for i in pos.size():
		var k := _key(pos[i].x, pos[i].z)
		if not _grid.has(k):
			_grid[k] = PackedInt32Array()
		var arr: PackedInt32Array = _grid[k]
		arr.append(i)
		_grid[k] = arr


func nearest_index(p: Vector3, max_radius := 40.0) -> int:
	## Nearest sample in XZ (with a mild vertical penalty so stacked roads resolve).
	var best := -1
	var best_d := INF
	var r := int(ceil(max_radius / _cell))
	var c := _key(p.x, p.z)
	for dx in range(-r, r + 1):
		for dz in range(-r, r + 1):
			var k := Vector2i(c.x + dx, c.y + dz)
			if not _grid.has(k):
				continue
			for i in _grid[k]:
				var q := pos[i]
				var d := Vector2(q.x - p.x, q.z - p.z).length_squared() + pow((q.y - p.y) * 0.6, 2.0)
				if d < best_d:
					best_d = d
					best = i
	return best


func lateral_offset(i: int, p: Vector3) -> float:
	return (p - pos[i]).dot(right[i])


func sample_at_distance(d: float) -> int:
	if closed:
		d = fposmod(d, length)
	else:
		d = clampf(d, 0.0, length)
	return clampi(int(round(d / (length / float(pos.size() - (0 if closed else 1))))), 0, pos.size() - 1)


func point_at(i: int, lateral: float, lift := 0.0) -> Vector3:
	return pos[i] + right[i] * lateral + up[i] * lift


func transform_at(i: int) -> Transform3D:
	var b := Basis(right[i], up[i], -tan[i])
	return Transform3D(b.orthonormalized(), pos[i])


func curvature_at(i: int, span := 4) -> float:
	## signed curvature (1/m), positive = turning left
	var n := pos.size()
	var a: int
	var b: int
	if closed:
		a = (i - span + n) % n
		b = (i + span) % n
	else:
		a = maxi(i - span, 0)
		b = mini(i + span, n - 1)
	var ta := tan[a]
	var tb := tan[b]
	var ds := spacing * float(span * 2)
	var ang := Vector2(ta.x, ta.z).angle_to(Vector2(tb.x, tb.z))
	return -ang / maxf(ds, 0.01)
