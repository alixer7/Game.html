class_name SimWorld
extends Node3D
## Fixed-step simulation of cars, ball and boost pads. Uses the physics
## server only for collision queries against the static arena trimesh; all
## dynamics are integrated here at Phys.TICK_RATE.

signal goal_scored(scoring_team: int, scorer_id: int)
signal ball_touched(car_id: int, strength: float)
signal ball_bounced(strength: float, pos: Vector3)
signal car_demolished(attacker_id: int, victim_id: int)
signal car_bumped(a_id: int, b_id: int, strength: float)
signal pad_collected(pad_index: int, car_id: int)

class Pad:
	var pos := Vector3.ZERO
	var big := false
	var active := true
	var timer := 0.0

const BIG_PADS := [Vector2(32.0, 0.0), Vector2(-32.0, 0.0), Vector2(30.5, 38.5),
	Vector2(-30.5, 38.5), Vector2(30.5, -38.5), Vector2(-30.5, -38.5)]
const SMALL_PADS_Q := [Vector2(0, 13), Vector2(0, 30), Vector2(0, 43), Vector2(12, 7),
	Vector2(12, 24), Vector2(24, 15), Vector2(22, 36), Vector2(8, 40), Vector2(18, 0)]

var cars: Array[CarSim] = []
var controllers: Array = []
var ball := BallSim.new()
var pads: Array[Pad] = []
var tick := 0
var running := true
var cars_frozen := false
var ball_frozen := false
var goal_enabled := true
var demolitions_enabled := true
var unlimited_boost := false

var hit_pos := Vector3.ZERO
var hit_normal := Vector3.UP

var _space: PhysicsDirectSpaceState3D
var _ray := PhysicsRayQueryParameters3D.new()
var _sphere_shape := SphereShape3D.new()
var _sphere_q := PhysicsShapeQueryParameters3D.new()
var _box_shape := BoxShape3D.new()
var _box_q := PhysicsShapeQueryParameters3D.new()
var _surfs: Dictionary = {}


func _ready() -> void:
	_surfs = ArenaGeo.build()
	var body := StaticBody3D.new()
	body.name = "ArenaCollision"
	var shape := ConcavePolygonShape3D.new()
	shape.set_faces(ArenaGeo.collision_faces(_surfs))
	shape.backface_collision = false
	var cs := CollisionShape3D.new()
	cs.shape = shape
	body.add_child(cs)
	add_child(body)
	_ray.hit_back_faces = false
	_ray.hit_from_inside = false
	_sphere_shape.radius = Phys.BALL_R
	_sphere_q.shape = _sphere_shape
	_box_q.shape = _box_shape
	_build_pads()


func arena_surfaces() -> Dictionary:
	return _surfs


func _build_pads() -> void:
	pads.clear()
	for p in BIG_PADS:
		var pad := Pad.new()
		pad.pos = Vector3(p.x, 0.0, p.y)
		pad.big = true
		pads.append(pad)
	for q in SMALL_PADS_Q:
		var seen := {}
		for sx in [1.0, -1.0]:
			for sz in [1.0, -1.0]:
				var v := Vector3(q.x * sx, 0.0, q.y * sz)
				var key := "%0.2f,%0.2f" % [v.x, v.z]
				if seen.has(key):
					continue
				seen[key] = true
				var pad := Pad.new()
				pad.pos = v
				pads.append(pad)


func add_car(car: CarSim, controller: Object) -> void:
	car.id = cars.size()
	cars.append(car)
	controllers.append(controller)


func clear_cars() -> void:
	cars.clear()
	controllers.clear()


func get_car(id: int) -> CarSim:
	return cars[id] if id >= 0 and id < cars.size() else null


# ------------------------------------------------------------------ queries

func _ensure_space() -> void:
	if _space == null:
		_space = get_world_3d().direct_space_state


func raycast(from: Vector3, to: Vector3) -> bool:
	_ensure_space()
	_ray.from = from
	_ray.to = to
	var r := _space.intersect_ray(_ray)
	if r.is_empty():
		return false
	hit_pos = r["position"]
	hit_normal = r["normal"]
	return true


## Returns contact pairs (point on query shape, point on arena) for a sphere.
func sphere_contacts(center: Vector3, radius: float) -> Array[Vector3]:
	_ensure_space()
	_sphere_shape.radius = radius
	_sphere_q.transform = Transform3D(Basis.IDENTITY, center)
	return _space.collide_shape(_sphere_q, 8)


# ------------------------------------------------------------------ step

func _physics_process(_delta: float) -> void:
	if running:
		step(Phys.DT)


func step(dt: float) -> void:
	_space = get_world_3d().direct_space_state
	tick += 1
	for i in range(cars.size()):
		var car := cars[i]
		car.save_prev()
		var ctrl: Object = controllers[i]
		if ctrl != null and not cars_frozen and not car.demolished:
			ctrl.call("update_controls", dt)
		if cars_frozen:
			car.controls.throttle = 0.0
			car.controls.boost = false
			car.controls.jump = false
	ball.save_prev()

	for car in cars:
		if car.demolished:
			car.respawn_timer -= dt
			if car.respawn_timer <= 0.0:
				_respawn(car)
			continue
		car.infinite_boost = unlimited_boost
		if cars_frozen:
			car.vel = Vector3.ZERO
			car.ang_vel = Vector3.ZERO
			continue
		car.step(dt, self)

	if not ball_frozen:
		ball.integrate(dt)
		var s := ball_arena_collide(ball)
		if s > 2.0:
			ball_bounced.emit(s, ball.pos)

	for car in cars:
		if not car.demolished:
			_car_ball(car)
	for i in range(cars.size()):
		for j in range(i + 1, cars.size()):
			if not cars[i].demolished and not cars[j].demolished:
				_car_car(cars[i], cars[j])
	_update_pads(dt)

	if goal_enabled and absf(ball.pos.z) > Phys.HALF_L + Phys.BALL_R:
		var scoring_team := 1 if ball.pos.z > 0.0 else 0
		goal_enabled = false
		goal_scored.emit(scoring_team, ball.last_touch_car)


# ------------------------------------------------------------------ ball

## Resolves ball/arena contacts. Returns the strongest impact speed.
func ball_arena_collide(b: BallSim) -> float:
	if ArenaGeo.sdf(b.pos) > Phys.BALL_R + 0.05:
		return 0.0
	var pts := sphere_contacts(b.pos, Phys.BALL_R)
	if pts.is_empty():
		return 0.0
	var best := 0.0
	var applied := Vector3.ZERO
	var count := pts.size() / 2
	# deepest contacts first
	var order: Array = []
	for k in range(count):
		order.append([pts[k * 2 + 1].distance_squared_to(pts[k * 2]), k])
	order.sort_custom(func(x, y): return x[0] > y[0])
	for item in order:
		var k: int = item[1]
		var d: Vector3 = pts[k * 2 + 1] - pts[k * 2]
		var depth := d.length()
		if depth < 1e-6:
			continue
		var n := d / depth
		var rem := depth - applied.dot(n)
		if rem > 0.0:
			b.pos += n * rem
			applied += n * rem
		var vn := b.vel.dot(n)
		if vn < 0.0:
			best = maxf(best, -vn)
			b.bounce(n)
	return best


func _car_ball(car: CarSim) -> void:
	var hb := car.hitbox_center()
	var d := ball.pos - hb
	if d.length_squared() > 3.0:
		return
	var local := car.basis.transposed() * d
	var he := car.half_ext
	var q := Vector3(clampf(local.x, -he.x, he.x), clampf(local.y, -he.y, he.y), clampf(local.z, -he.z, he.z))
	var diff := local - q
	var dist := diff.length()
	var n_local: Vector3
	var pen: float
	if dist > 1e-5:
		if dist >= Phys.BALL_R:
			return
		n_local = diff / dist
		pen = Phys.BALL_R - dist
	else:
		var px := he.x - absf(local.x)
		var py := he.y - absf(local.y)
		var pz := he.z - absf(local.z)
		if px <= py and px <= pz:
			n_local = Vector3(signf(local.x) if local.x != 0.0 else 1.0, 0, 0)
			pen = Phys.BALL_R + px
		elif py <= pz:
			n_local = Vector3(0, signf(local.y) if local.y != 0.0 else 1.0, 0)
			pen = Phys.BALL_R + py
		else:
			n_local = Vector3(0, 0, signf(local.z) if local.z != 0.0 else -1.0)
			pen = Phys.BALL_R + pz
	var n := car.basis * n_local
	var cp := hb + car.basis * q
	var r_c := cp - car.pos
	var r_b := -n * Phys.BALL_R
	var v_c := car.vel + car.ang_vel.cross(r_c)
	var v_b := ball.vel + ball.ang_vel.cross(r_b)
	var rel := v_b - v_c
	var vn := rel.dot(n)
	var new_touch := car.last_ball_touch_tick < tick - 1
	var pre_ball_vel := ball.vel
	var pre_car_vel := car.vel

	var mb := Phys.BALL_MASS
	var mc := Phys.CAR_MASS
	var wb := mc / (mb + mc)
	ball.pos += n * pen * wb
	car.pos -= n * pen * (1.0 - wb)
	if ball_frozen:
		ball_frozen = false

	if vn < 0.0:
		var k_n := 1.0 / mb + 1.0 / mc + n.dot(car.inv_inertia(r_c.cross(n)).cross(r_c)) / mc
		var jn := -vn / k_n
		var J := n * jn
		var vt := rel - n * vn
		var vt_len := vt.length()
		if vt_len > 1e-4:
			var t := vt / vt_len
			var k_t := 1.0 / mb + 1.0 / mc + t.dot(car.inv_inertia(r_c.cross(t)).cross(r_c)) / mc \
				+ t.dot((r_b.cross(t) * BallSim.INV_INERTIA).cross(r_b))
			var jt := minf(vt_len / k_t, 2.0 * jn)
			J -= t * jt
		ball.vel += J / mb
		ball.ang_vel += r_b.cross(J) * BallSim.INV_INERTIA
		car.vel -= J / mc
		car.ang_vel -= car.inv_inertia(r_c.cross(J)) / mc

	var strength := 0.0
	if new_touch:
		var rel_pos := ball.pos - car.pos
		var rel_vel := pre_ball_vel - pre_car_vel
		var rel_speed := minf(rel_vel.length(), 46.0)
		strength = rel_speed
		if rel_speed > 0.0:
			var hit_dir := Vector3(rel_pos.x, rel_pos.y * 0.35, rel_pos.z).normalized()
			var fwd := car.forward()
			hit_dir = (hit_dir - fwd * hit_dir.dot(fwd) * (1.0 - 0.65)).normalized()
			ball.vel += hit_dir * rel_speed * Phys.hit_factor(rel_speed)
		var sp := ball.vel.length()
		if sp > Phys.BALL_MAX_SPEED:
			ball.vel *= Phys.BALL_MAX_SPEED / sp
		ball.last_touch_car = car.id
		ball.last_touch_team = car.team
		ball.last_touch_tick = tick
		ball.touched = true
		ball.hit_flash = clampf(rel_speed / 25.0, 0.25, 1.0)
		ball_touched.emit(car.id, strength)
	car.last_ball_touch_tick = tick
	# keep the ball out of walls after being pushed by a car
	ball_arena_collide(ball)


# ------------------------------------------------------------------ cars

func car_arena_collide(car: CarSim) -> void:
	var hb := car.hitbox_center()
	if ArenaGeo.sdf(hb) > 0.85:
		return
	_ensure_space()
	_box_shape.size = car.half_ext * 2.0
	_box_q.transform = Transform3D(car.basis, hb)
	var pts := _space.collide_shape(_box_q, 8)
	if pts.is_empty():
		return
	var count := pts.size() / 2
	var applied := Vector3.ZERO
	var nsum := Vector3.ZERO
	for k in range(count):
		var d: Vector3 = pts[k * 2 + 1] - pts[k * 2]
		var depth := d.length()
		if depth < 1e-6:
			continue
		var n := d / depth
		nsum += n * depth
		var rem := depth - applied.dot(n)
		if rem > 0.0:
			car.pos += n * rem
			applied += n * rem
	if nsum.length_squared() > 1e-10:
		car.body_touching = true
		car.body_normal = nsum.normalized()
	if car.num_contacts >= 2 and nsum.length_squared() > 1e-10:
		# Driving: the chassis grazed the surface (e.g. entering a quarter-pipe).
		# Remove only the into-surface velocity and pitch toward the surface.
		var bn := car.body_normal
		var vn0 := car.vel.dot(bn)
		if vn0 < 0.0:
			var sp := car.vel.length()
			car.vel -= bn * vn0
			if -vn0 < sp * 0.6:
				car.vel = car.vel.normalized() * sp * 0.97
		car.ang_vel += car.basis.y.cross(bn) * 4.0
		return
	# velocity impulses (two passes of sequential impulses)
	for it in range(2):
		for k in range(count):
			var a: Vector3 = pts[k * 2]
			var d: Vector3 = pts[k * 2 + 1] - a
			var depth := d.length()
			if depth < 1e-6:
				continue
			var n := d / depth
			var r := pts[k * 2 + 1] - car.pos
			var vp := car.vel + car.ang_vel.cross(r)
			var vn := vp.dot(n)
			if vn >= 0.0:
				continue
			var e := 0.25 if it == 0 and vn < -2.0 else 0.0
			var kk := 1.0 + n.dot(car.inv_inertia(r.cross(n)).cross(r))
			var j := -(1.0 + e) * vn / kk
			var J := n * j
			var vt := vp - n * vn
			var vtl := vt.length()
			if vtl > 1e-4:
				var t := vt / vtl
				var kt := 1.0 + t.dot(car.inv_inertia(r.cross(t)).cross(r))
				var mu := 0.4 if car.num_contacts < 2 else 0.03
				J -= t * minf(vtl / kt, mu * j)
			car.vel += J
			car.ang_vel += car.inv_inertia(r.cross(J))
			if it == 0 and vn < -3.0:
				car.ev_land = maxf(car.ev_land, -vn)


static func _closest_seg_seg(p1: Vector3, q1: Vector3, p2: Vector3, q2: Vector3) -> Array:
	var d1 := q1 - p1
	var d2 := q2 - p2
	var r := p1 - p2
	var a := d1.dot(d1)
	var e := d2.dot(d2)
	var f := d2.dot(r)
	var s := 0.0
	var t := 0.0
	var c := d1.dot(r)
	var b := d1.dot(d2)
	var denom := a * e - b * b
	if denom > 1e-8:
		s = clampf((b * f - c * e) / denom, 0.0, 1.0)
	t = (b * s + f) / e
	if t < 0.0:
		t = 0.0
		s = clampf(-c / a, 0.0, 1.0)
	elif t > 1.0:
		t = 1.0
		s = clampf((b - c) / a, 0.0, 1.0)
	return [p1 + d1 * s, p2 + d2 * t]


func _car_car(a: CarSim, b: CarSim) -> void:
	var ca := a.hitbox_center()
	var cb := b.hitbox_center()
	if ca.distance_squared_to(cb) > 6.0:
		return
	var ra := (a.half_ext.x + a.half_ext.y) * 0.5
	var rb := (b.half_ext.x + b.half_ext.y) * 0.5
	var ha := a.half_ext.z - ra
	var hb := b.half_ext.z - rb
	var fa := a.forward()
	var fb := b.forward()
	var cp: Array = _closest_seg_seg(ca - fa * ha, ca + fa * ha, cb - fb * hb, cb + fb * hb)
	var pa: Vector3 = cp[0]
	var pb: Vector3 = cp[1]
	var d := pb - pa
	var dist := d.length()
	if dist >= ra + rb:
		return
	var n := d / dist if dist > 1e-5 else Vector3.UP
	var pen := ra + rb - dist
	a.pos -= n * pen * 0.5
	b.pos += n * pen * 0.5
	var rel := b.vel - a.vel
	var vn := rel.dot(n)
	var closing := -vn
	if vn < 0.0:
		var j := -(1.0 + 0.15) * vn * 0.5
		a.vel -= n * j
		b.vel += n * j
	if closing < 1.5:
		return
	var key := a.id * 100 + b.id
	if bump_ok(a, key, tick):
		var a_hits := fa.dot(n) > 0.55 and a.vel.dot(n) > 2.0
		var b_hits := fb.dot(-n) > 0.55 and b.vel.dot(-n) > 2.0
		if a_hits:
			_hit_car(a, b, n)
		if b_hits:
			_hit_car(b, a, -n)
		car_bumped.emit(a.id, b.id, closing)


func bump_ok(a: CarSim, key: int, now: int) -> bool:
	var last: int = a.bump_cooldowns.get(key, -100000)
	if now - last < 30:
		return false
	a.bump_cooldowns[key] = now
	return true


func _hit_car(att: CarSim, vic: CarSim, n: Vector3) -> void:
	if att.supersonic and att.team != vic.team and demolitions_enabled:
		demolish(vic)
		car_demolished.emit(att.id, vic.id)
		return
	var s := att.vel.dot(n)
	var flat := Vector3(n.x, 0.0, n.z)
	if flat.length_squared() < 0.01:
		flat = n
	flat = flat.normalized()
	vic.vel += flat * s * 0.62 + Vector3.UP * (s * 0.22 if vic.on_ground else s * 0.08)


func demolish(car: CarSim) -> void:
	car.demolished = true
	car.respawn_timer = Phys.DEMO_RESPAWN
	car.vel = Vector3.ZERO
	car.ang_vel = Vector3.ZERO
	car.boosting = false
	car.supersonic = false


func _respawn(car: CarSim) -> void:
	var gz := Phys.own_goal_z(car.team)
	var options := [Vector3(-12.0, 0.17, gz * 0.86), Vector3(12.0, 0.17, gz * 0.86), Vector3(0.0, 0.17, gz * 0.9)]
	var best: Vector3 = options[0]
	var best_d := -1.0
	for o in options:
		var md := 1e9
		for other in cars:
			if other != car and not other.demolished:
				md = minf(md, other.pos.distance_to(o))
		if md > best_d:
			best_d = md
			best = o
	var yaw := atan2(best.x, best.z)
	car.place(best, yaw)
	car.boost = Phys.BOOST_KICKOFF


# ------------------------------------------------------------------ pads

func _update_pads(dt: float) -> void:
	for i in range(pads.size()):
		var pad := pads[i]
		if not pad.active:
			pad.timer -= dt
			if pad.timer <= 0.0:
				pad.active = true
			continue
		var r2 := 4.4 if pad.big else 2.0
		var hmax := 2.6 if pad.big else 1.7
		for car in cars:
			if car.demolished or car.boost >= 100.0:
				continue
			var dx := car.pos.x - pad.pos.x
			var dz := car.pos.z - pad.pos.z
			if dx * dx + dz * dz < r2 and car.pos.y < hmax:
				car.boost = minf(100.0, car.boost + (Phys.BIG_PAD_AMOUNT if pad.big else Phys.SMALL_PAD_AMOUNT))
				pad.active = false
				pad.timer = Phys.BIG_PAD_RESPAWN if pad.big else Phys.SMALL_PAD_RESPAWN
				pad_collected.emit(i, car.id)
				break


func reset_pads() -> void:
	for pad in pads:
		pad.active = true
		pad.timer = 0.0


# ------------------------------------------------------------------ kickoff

const KICKOFF_SPOTS := [Vector2(-20.0, 26.0), Vector2(20.0, 26.0), Vector2(-3.0, 38.5),
	Vector2(3.0, 38.5), Vector2(0.0, 45.5)]


static func kickoff_transform(team: int, spot: int) -> Array:
	var s: Vector2 = KICKOFF_SPOTS[spot]
	var p := Vector3(s.x, 0.17, s.y)
	if team == 1:
		p = Vector3(-s.x, 0.17, -s.y)
	var yaw := atan2(p.x, p.z)
	return [p, yaw]
