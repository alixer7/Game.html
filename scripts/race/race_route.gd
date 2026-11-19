class_name RaceRoute
extends RefCounted
## Race line with cumulative distances, tangents and a braking-aware speed profile.

var pts := PackedVector3Array()
var widths := PackedFloat32Array()
var dist := PackedFloat32Array()
var tangents := PackedVector3Array()
var rights := PackedVector3Array()
var v_allow := PackedFloat32Array()
var curv := PackedFloat32Array()
var closed := false
var length := 0.0
var is_open := false
var shortcuts := []      # [{enter, exit, pts: PackedVector3Array}]


static func from_event(e: Dictionary) -> RaceRoute:
	var r := RaceRoute.new()
	var raw: Array = e.route
	var n := raw.size() / 4
	for k in n:
		r.pts.append(Vector3(raw[k * 4], raw[k * 4 + 1], raw[k * 4 + 2]))
		r.widths.append(float(raw[k * 4 + 3]))
	r.closed = e.closed
	r.is_open = e.get("open", false)
	r._prepare()
	for sc in e.get("shortcuts", []):
		var sp := PackedVector3Array()
		var a: Array = sc.pts
		for k in a.size() / 3:
			sp.append(Vector3(a[k * 3], a[k * 3 + 1], a[k * 3 + 2]))
		r.shortcuts.append({"enter": float(sc.enter), "exit": float(sc.exit), "pts": sp})
	return r


func _prepare() -> void:
	var n := pts.size()
	# round off sharp polyline corners (junction turns) so cars follow an arc
	if not is_open:
		for it in 4:
			var sm := pts.duplicate()
			for i in n:
				if not closed and (i == 0 or i == n - 1):
					continue
				var a := pts[posmod(i - 1, n)]
				var b := pts[posmod(i + 1, n)]
				var q := pts[i].lerp((a + b) * 0.5, 0.5)
				sm[i] = Vector3(q.x, pts[i].y, q.z)
			pts = sm
	dist.resize(n)
	tangents.resize(n)
	rights.resize(n)
	curv.resize(n)
	v_allow.resize(n)
	var acc := 0.0
	for i in n:
		if i > 0:
			acc += pts[i].distance_to(pts[i - 1])
		dist[i] = acc
	length = acc + (pts[0].distance_to(pts[n - 1]) if closed else 0.0)
	for i in n:
		var a := _p(i - 2)
		var b := _p(i + 2)
		var t := b - a
		t.y = 0.0
		t = t.normalized()
		tangents[i] = t
		rights[i] = t.cross(Vector3.UP).normalized()
	# curvature from heading change over ~16 m
	for i in n:
		var t0 := tangents[_wrap(i - 2)]
		var t1 := tangents[_wrap(i + 2)]
		var ang := atan2(t0.cross(t1).y, t0.dot(t1))
		curv[i] = ang / 11.0
	# lateral-grip speed limit, then backward braking pass (twice for loops)
	var mu_g := 9.81 * 1.05
	for i in n:
		var k := absf(curv[i])
		v_allow[i] = minf(sqrt(mu_g / maxf(k, 1e-4)), 95.0)
		# slopes / crests: be a little careful over sharp vertical changes
		var dy := absf((_p(i + 2).y - _p(i).y) - (_p(i).y - _p(i - 2).y))
		if dy > 0.6:
			v_allow[i] = minf(v_allow[i], 40.0)
		# downtown streets with cross traffic: opponents stay a bit more careful
		var q := pts[i]
		if q.x > 470.0 and q.x < 1660.0 and q.z > -590.0 and q.z < 700.0:
			v_allow[i] = minf(v_allow[i], 46.0)
	var a_brake := 8.5
	for rep in (2 if closed else 1):
		for j in n:
			var i := n - 1 - j
			var nx := i + 1
			if nx >= n:
				if not closed:
					continue
				nx = 0
			var ds := pts[i].distance_to(pts[nx])
			v_allow[i] = minf(v_allow[i], sqrt(v_allow[nx] * v_allow[nx] + 2.0 * a_brake * ds))


func _wrap(i: int) -> int:
	var n := pts.size()
	if closed:
		return posmod(i, n)
	return clampi(i, 0, n - 1)


func _p(i: int) -> Vector3:
	return pts[_wrap(i)]


## nearest route index near a hint (searching a window)
func nearest(pos: Vector3, hint: int, back := 6, fwd := 50) -> int:
	var n := pts.size()
	var best := hint
	var bd := 1e18
	for o in range(-back, fwd + 1):
		var i := _wrap(hint + o)
		var d := Vector2(pts[i].x - pos.x, pts[i].z - pos.z).length_squared()
		if d < bd:
			bd = d
			best = i
	return best


func nearest_global(pos: Vector3) -> int:
	var best := 0
	var bd := 1e18
	for i in range(0, pts.size(), 2):
		var d := pts[i].distance_squared_to(pos)
		if d < bd:
			bd = d
			best = i
	return best


func index_at_distance(d: float) -> int:
	if closed:
		d = fposmod(d, length)
	d = clampf(d, 0.0, dist[dist.size() - 1])
	var lo := 0
	var hi := dist.size() - 1
	while lo < hi:
		var mid := (lo + hi) / 2
		if dist[mid] < d:
			lo = mid + 1
		else:
			hi = mid
	return lo


func point_at(d: float) -> Vector3:
	return pts[index_at_distance(d)]


func advance(i: int, metres: float) -> int:
	return _wrap(i + int(round(metres / 4.0)))
