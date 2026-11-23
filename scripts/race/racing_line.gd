class_name RacingLine
extends RefCounted
## Minimum-curvature line inside the road bounds (iterative relaxation), with
## obstacle clearance and a braking-aware target-speed profile.

var path: SplinePath
var closed := false
var pts := PackedVector3Array()
var offs := PackedFloat32Array()
var speed := PackedFloat32Array()
var radius := PackedFloat32Array()


static func build(sp: SplinePath, obstacles: Array, margin := 1.5, bias := 0.0) -> RacingLine:
	var rl := RacingLine.new()
	rl.path = sp
	rl.closed = sp.closed
	var n := sp.size()
	rl.offs.resize(n)
	rl.offs.fill(0.0)
	rl.pts.resize(n)
	var lim := PackedFloat32Array()
	lim.resize(n)
	for i in n:
		lim[i] = maxf(sp.width[i] * 0.5 - margin, 0.2)
		if sp.style[i] == "gap":
			lim[i] = 0.5
	# obstacles close to this path
	var near: Array = []
	for o in obstacles:
		var p: Vector3 = o[0]
		var j := sp.nearest_index(p, 12.0)
		if j >= 0 and absf(sp.pos[j].y - p.y) < 4.0:
			near.append([j, sp.lateral_offset(j, p), float(o[1])])
	for it in 160:
		for i in n:
			var a: int
			var b: int
			if rl.closed:
				a = (i - 1 + n) % n
				b = (i + 1) % n
			else:
				a = maxi(i - 1, 0)
				b = mini(i + 1, n - 1)
			var pa := sp.pos[a] + sp.right[a] * rl.offs[a]
			var pb := sp.pos[b] + sp.right[b] * rl.offs[b]
			var target := (pa + pb) * 0.5
			var o := (target - sp.pos[i]).dot(sp.right[i]) + bias * signf(sp.curvature_at(i)) * -1.0
			rl.offs[i] = clampf(lerpf(rl.offs[i], o, 0.55), -lim[i], lim[i])
		for ob in near:
			var j: int = ob[0]
			var lat: float = ob[1]
			var r: float = ob[2] + 1.7
			var span := int(ceil((r + 3.0) / sp.spacing))
			for k in range(-span, span + 1):
				var i := j + k
				if rl.closed:
					i = (i + n) % n
				elif i < 0 or i >= n:
					continue
				var along := absf(float(k)) * sp.spacing
				if along > r + 2.0:
					continue
				var need := sqrt(maxf(r * r - along * along * 0.35, 0.0))
				var d := rl.offs[i] - lat
				if absf(d) < need:
					var room_left := lat - need - (-lim[i])
					var room_right := lim[i] - (lat + need)
					var go_right := d > 0.0 if absf(d) > 0.2 else room_right > room_left
					if go_right and room_right > 0.0:
						rl.offs[i] = lat + need
					elif room_left > 0.0:
						rl.offs[i] = lat - need
	for i in n:
		rl.pts[i] = sp.pos[i] + sp.right[i] * rl.offs[i]
	rl._speed_profile()
	return rl


func _speed_profile() -> void:
	var n := pts.size()
	speed.resize(n)
	radius.resize(n)
	for i in n:
		var a: int
		var b: int
		var span := 4
		if closed:
			a = (i - span + n) % n
			b = (i + span) % n
		else:
			a = maxi(i - span, 0)
			b = mini(i + span, n - 1)
		var r := _circle_radius(pts[a], pts[i], pts[b])
		radius[i] = r
		# drift-capable corner speed: yaw rate ~2.2 rad/s sustainable in a slide
		var v := clampf(r * 2.1, 9.0, 40.0)
		speed[i] = v
	# backward pass: braking distance (decel ~16 m/s^2 incl. slide scrub)
	var ds := path.spacing
	for pass in 2:
		for k in range(n - 1, -1, -1):
			var i := k
			var nxt := (i + 1) % n if closed else mini(i + 1, n - 1)
			speed[i] = minf(speed[i], sqrt(speed[nxt] * speed[nxt] + 2.0 * 16.0 * ds))


static func _circle_radius(a: Vector3, b: Vector3, c: Vector3) -> float:
	var A := Vector2(a.x, a.z)
	var B := Vector2(b.x, b.z)
	var C := Vector2(c.x, c.z)
	var ab := A.distance_to(B)
	var bc := B.distance_to(C)
	var ca := C.distance_to(A)
	var cross := absf((B - A).cross(C - A))
	if cross < 1e-4:
		return 1e4
	return (ab * bc * ca) / (2.0 * cross)


func size() -> int:
	return pts.size()
