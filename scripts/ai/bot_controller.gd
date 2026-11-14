class_name BotController
extends RefCounted
## Computer-controlled driver. Plans on the predicted ball path, then steers,
## boosts, dodges, jumps and aerials toward the chosen intercept.

enum Man { NONE, DODGE, JUMP_SHOT, AERIAL, UNSTUCK, WAIT }

const SKILLS := [
	{"react": 0.30, "boost": 0.3, "dodge": 0.2, "jump_shot": false, "aerial": 0.0, "aim": 0.30,
		"speed": 0.8, "max_air_h": 0.0, "kick_flip": false, "kick_delay": 0.45},
	{"react": 0.14, "boost": 0.9, "dodge": 0.8, "jump_shot": true, "aerial": 0.25, "aim": 0.12,
		"speed": 1.0, "max_air_h": 8.0, "kick_flip": true, "kick_delay": 0.12},
	{"react": 0.06, "boost": 1.0, "dodge": 1.0, "jump_shot": true, "aerial": 0.7, "aim": 0.05,
		"speed": 1.0, "max_air_h": 16.0, "kick_flip": true, "kick_delay": 0.0},
]

var car: CarSim
var world: SimWorld
var pred: BallPredictor
var coord: BotCoordinator
var skill: Dictionary
var level := 1

var target := Vector3.ZERO
var target_time := -1.0
var arrive_stop := false
var face_ball := false
var allow_boost := true
var shot_dir := Vector3.FORWARD
var hit_point := Vector3.ZERO
var hit_time := -1.0
var aerial_plan := false

var man := Man.NONE
var m_time := 0.0
var m_dir := Vector2.ZERO
var m_target := Vector3.ZERO
var m_target_t := 0.0

var now := 0.0
var _decide_timer := 0.0
var _stuck := 0.0
var _rng := RandomNumberGenerator.new()
var _kick_wait := 0.0
var _was_kickoff := false


func _init(c: CarSim, w: SimWorld, p: BallPredictor, co: BotCoordinator, lvl: int) -> void:
	car = c
	world = w
	pred = p
	coord = co
	level = clampi(lvl, 0, SKILLS.size() - 1)
	skill = SKILLS[level]
	_rng.seed = hash(c.id * 7919 + Time.get_ticks_usec())


# ------------------------------------------------------------------ main

func update_controls(dt: float) -> void:
	now = world.tick * Phys.DT
	pred.maybe_update(6)
	coord.refresh()
	var c := car.controls
	c.reset()
	if man != Man.NONE:
		m_time += dt
		_run_maneuver(dt, c)
		return
	var kickoff := coord.is_kickoff()
	if kickoff and not _was_kickoff:
		_kick_wait = skill["kick_delay"] * _rng.randf_range(0.6, 1.4)
	_was_kickoff = kickoff
	_decide_timer -= dt
	if _decide_timer <= 0.0:
		_decide(kickoff)
		_decide_timer = skill["react"] * _rng.randf_range(0.7, 1.3)
	if car.num_contacts == 0:
		_air_recover(c)
		return
	if kickoff and _kick_wait > 0.0:
		_kick_wait -= dt
		return
	_drive(c, dt)
	_triggers(c, kickoff)


func _decide(kickoff: bool) -> void:
	arrive_stop = false
	face_ball = false
	aerial_plan = false
	allow_boost = _rng.randf() < skill["boost"]
	var role := coord.role_of(car)
	if kickoff:
		_plan_kickoff()
		return
	if pred.threatens(car.team, 3.0) and (role != BotCoordinator.Role.SUPPORT or _closest_teammate_to_ball()):
		_plan_attack(true)
		return
	match role:
		BotCoordinator.Role.ATTACK:
			if _should_retreat():
				_plan_retreat()
			else:
				_plan_attack(false)
		BotCoordinator.Role.SUPPORT:
			_plan_support()
		_:
			_plan_defend()


func _closest_teammate_to_ball() -> bool:
	var b := world.ball.pos
	var my := car.pos.distance_to(b)
	for other in world.cars:
		if other != car and other.team == car.team and not other.demolished and other.pos.distance_to(b) < my:
			return false
	return true


# ------------------------------------------------------------------ planning

func _travel_time(d: float, v0: float, boost: bool) -> float:
	if d <= 0.0:
		return 0.0
	var vmax := 22.5 if boost else 14.0
	var a := 15.0 if boost else 7.5
	v0 = maxf(v0, 0.0)
	if v0 >= vmax:
		return d / vmax
	var t1 := (vmax - v0) / a
	var d1 := v0 * t1 + 0.5 * a * t1 * t1
	if d1 >= d:
		return (-v0 + sqrt(v0 * v0 + 2.0 * a * d)) / a
	return t1 + (d - d1) / vmax


func _eta(p: Vector3) -> float:
	var to := Vector3(p.x - car.pos.x, 0, p.z - car.pos.z)
	var d := maxf(0.0, to.length() - (Phys.BALL_R + 0.75))
	var f := car.forward()
	var ff := Vector3(f.x, 0, f.z)
	var ang := 0.0
	if ff.length_squared() > 0.01 and to.length_squared() > 0.01:
		ang = ff.normalized().angle_to(to.normalized())
	var v := car.vel.length()
	var turn := ang * (0.28 + v / 45.0)
	var boost_ok := car.boost > 8.0 and allow_boost
	return turn + _travel_time(d, car.vel.dot(ff.normalized()) if ff.length_squared() > 0.01 else 0.0, boost_ok) / skill["speed"]


func _shot_direction(b: Vector3, clear: bool) -> Vector3:
	var opp_z := -Phys.own_goal_z(car.team)
	var own_z := Phys.own_goal_z(car.team)
	var gp := Vector3(clampf(b.x * 0.4, -Phys.GOAL_HALF_W + 2.5, Phys.GOAL_HALF_W - 2.5), 0, opp_z)
	var sd := Vector3(gp.x - b.x, 0, gp.z - b.z).normalized()
	sd = sd.rotated(Vector3.UP, _rng.randf_range(-skill["aim"], skill["aim"]))
	var car_to_ball := Vector3(b.x - car.pos.x, 0, b.z - car.pos.z).normalized()
	var away_own := Vector3(b.x, 0, b.z - own_z).normalized()
	if clear or car_to_ball.dot(sd) < 0.0:
		# can't line up a shot: push the ball away from our goal
		var blend := (car_to_ball * 1.2 + away_own).normalized()
		if blend.dot(away_own) < 0.2:
			blend = (blend + away_own).normalized()
		sd = blend
	# Never aim back toward our own goal from our defensive third.
	var out_dir := -signf(own_z)
	if absf(b.z - own_z) < 32.0 and sd.z * out_dir < 0.25:
		var side := signf(b.x) if absf(b.x) > 1.0 else (1.0 if car.pos.x < b.x else -1.0)
		sd = Vector3(side * 0.75, 0, out_dir * 0.66).normalized()
	return sd


## True when the ball sits between us and our own goal in our half: get goal-side first.
func _should_retreat() -> bool:
	var own_z := Phys.own_goal_z(car.team)
	var b := world.ball.pos
	var s := signf(own_z)
	if b.z * s < -8.0:
		return false
	var car_depth := car.pos.z * s
	var ball_depth := b.z * s
	return car_depth < ball_depth - 2.5 and Vector2(b.x - car.pos.x, b.z - car.pos.z).length() > 4.0


func _plan_attack(clear: bool) -> void:
	var reach_h := 1.75
	if skill["jump_shot"]:
		reach_h = 3.5
	var try_aerial := float(skill["aerial"]) > 0.0 and car.boost > 35.0 and car.on_ground \
		and _rng.randf() < float(skill["aerial"]) * 0.5
	var found := -1
	var n := pred.count()
	for i in range(1, n, 2):
		var b := pred.pos[i]
		var t := i * BallPredictor.STEP
		if absf(b.z) > Phys.HALF_L + 1.0:
			break
		if b.y <= reach_h:
			if _eta(b) <= t:
				found = i
				break
		elif try_aerial and b.y <= float(skill["max_air_h"]) and b.y > 3.2 and t > 0.9 and t < 2.8 \
				and Vector2(b.x - car.pos.x, b.z - car.pos.z).length() < 24.0:
			if _aerial_ok(b, t):
				found = i
				aerial_plan = true
				break
	var b: Vector3
	var t: float
	if found == -1:
		var idx := mini(n - 1, 45)
		b = pred.pos[idx]
		t = -1.0
	else:
		b = pred.pos[found]
		t = found * BallPredictor.STEP
	shot_dir = _shot_direction(b, clear)
	var contact := b - shot_dir * (Phys.BALL_R + 0.85)
	contact.y = 0.0
	var to := Vector3(contact.x - car.pos.x, 0, contact.z - car.pos.z)
	var dist := to.length()
	var align := 1.0
	if dist > 0.1:
		align = (to / dist).dot(shot_dir)
	var off := clampf(dist * 0.42, 0.0, 10.0) * clampf(1.0 - align, 0.0, 1.0)
	target = contact - shot_dir * off
	if align < -0.2:
		# on the wrong side of the ball: swing around it instead of through it
		var perp := Vector3(-shot_dir.z, 0, shot_dir.x)
		var side := signf(perp.dot(Vector3(car.pos.x - b.x, 0, car.pos.z - b.z)))
		if side == 0.0:
			side = 1.0
		target = b - shot_dir * 4.5 + perp * side * 4.5
		t = -1.0
	_clamp_target()
	target_time = now + t if t > 0.0 else -1.0
	hit_point = b
	hit_time = now + t if t > 0.0 else -1.0
	# Close range with a decent angle: just drive through the ball.
	var bp := world.ball.pos
	var to_ball := Vector3(bp.x - car.pos.x, 0, bp.z - car.pos.z)
	var lb := car.basis.transposed() * to_ball
	if to_ball.length() < 7.0 and bp.y < 2.2 and to_ball.normalized().dot(shot_dir) > 0.3 \
			and absf(atan2(lb.x, -lb.z)) < 0.8:
		target = bp - shot_dir * 0.4
		target.y = 0.0
		target_time = -1.0
		hit_point = bp
		hit_time = now + to_ball.length() / maxf(6.0, car.vel.length())


func _aerial_ok(b: Vector3, t: float) -> bool:
	# rough check: average acceleration needed after a full jump
	var p0 := car.pos + Vector3.UP * 2.0
	var v0 := car.vel + Vector3.UP * 4.5
	var tt := maxf(0.3, t - 0.3)
	var delta := b - p0 - v0 * tt - Vector3(0, -Phys.GRAVITY, 0) * 0.5 * tt * tt
	var a := 2.0 * delta.length() / (tt * tt)
	var fuel := car.boost / Phys.BOOST_USE
	return a < Phys.BOOST_ACCEL_AIR * 0.85 and fuel > tt * 0.6


func _plan_retreat() -> void:
	# Drive back toward the far post, staying wide of the ball.
	var own_z := Phys.own_goal_z(car.team)
	var b := world.ball.pos
	var side := -signf(b.x) if absf(b.x) > 2.0 else (signf(car.pos.x) if absf(car.pos.x) > 0.5 else 1.0)
	target = Vector3(side * (Phys.GOAL_HALF_W - 1.0), 0, own_z - signf(own_z) * 4.0)
	target_time = -1.0
	hit_time = -1.0
	arrive_stop = false
	allow_boost = true


func _plan_support() -> void:
	var b := world.ball.pos
	var own_z := Phys.own_goal_z(car.team)
	var back := Vector3(0 - b.x * 0.4, 0, own_z - b.z)
	back.y = 0.0
	if back.length() < 0.1:
		back = Vector3(0, 0, signf(own_z))
	var p := b + back.normalized() * 22.0
	if car.boost < 45.0:
		var pad := _nearest_big_pad(p, own_z)
		if pad != Vector3.INF:
			p = pad
	target = p
	_clamp_target()
	target_time = -1.0
	arrive_stop = true
	face_ball = true


func _plan_defend() -> void:
	var b := world.ball.pos
	var own_z := Phys.own_goal_z(car.team)
	target = Vector3(clampf(b.x * 0.3, -6.0, 6.0), 0, own_z - signf(own_z) * 5.0)
	# Defender takes the ball when it's close to our goal and nobody is on it
	if absf(b.z - own_z) < 26.0 and _closest_teammate_to_ball():
		_plan_attack(true)
		return
	if car.boost < 30.0:
		var pad := _nearest_big_pad(target, own_z)
		if pad != Vector3.INF and pad.distance_to(car.pos) < 25.0:
			target = pad
	target_time = -1.0
	arrive_stop = true
	face_ball = true


func _plan_kickoff() -> void:
	var team := car.team
	if coord.kicker[team] == car.id:
		target = Vector3.ZERO
		target_time = -1.0
		allow_boost = true
		hit_point = world.ball.pos
		hit_time = -1.0
		shot_dir = Vector3(0, 0, Phys.attack_dir(team))
	elif coord.kick_support[team] == car.id and world.cars.size() > 2:
		var own_z := Phys.own_goal_z(team)
		var sx := signf(car.pos.x) if absf(car.pos.x) > 1.0 else 1.0
		target = Vector3(sx * 30.5, 0, own_z * 0.74)
		arrive_stop = true
		face_ball = true
	else:
		var own_z := Phys.own_goal_z(team)
		target = Vector3(0, 0, own_z - signf(own_z) * 5.0)
		arrive_stop = true
		face_ball = true


func _nearest_big_pad(near: Vector3, own_z: float) -> Vector3:
	var best := Vector3.INF
	var best_d := 1e9
	for pad in world.pads:
		if not pad.big or not pad.active:
			continue
		if pad.pos.z * signf(own_z) < -5.0:
			continue
		var d := pad.pos.distance_to(near) + pad.pos.distance_to(car.pos) * 0.5
		if d < best_d:
			best_d = d
			best = pad.pos
	return best


func _clamp_target() -> void:
	target.x = clampf(target.x, -Phys.HALF_W + 3.0, Phys.HALF_W - 3.0)
	target.z = clampf(target.z, -Phys.HALF_L + 3.0, Phys.HALF_L - 3.0)
	var s := absf(target.x) + absf(target.z)
	var lim := Phys.HALF_W + Phys.HALF_L - Phys.CHAMFER - 4.0
	if s > lim:
		var k := lim / s
		target.x *= k
		target.z *= k
	target.y = 0.0


# ------------------------------------------------------------------ driving

func _drive(c: CarControls, dt: float) -> void:
	var to := target - car.pos
	var local := car.basis.transposed() * to
	var ang := atan2(local.x, -local.z)
	var dist := Vector2(local.x, local.z).length()
	var fwd := car.forward()
	var v_f := car.vel.dot(fwd)
	var yaw_rate := car.ang_vel.dot(car.up())
	c.steer = clampf(ang * 3.0 + yaw_rate * 0.25, -1.0, 1.0)
	if absf(ang) > 1.6 and v_f > 9.0 and car.on_ground:
		c.handbrake = true

	var desired := 23.0 * float(skill["speed"])
	if target_time > 0.0 and hit_point.y > 1.7:
		# airborne ball: time the arrival so we meet it as it comes down
		var trem := target_time - now
		if trem > 0.08:
			desired = clampf(dist / trem * 1.05, 4.0, 23.0)
	if arrive_stop:
		desired = minf(desired, maxf(0.0, dist - 1.0) * 1.4)
	var near := arrive_stop and dist < 3.0
	if near:
		# hold position, turn to face the ball
		var lb := car.basis.transposed() * (world.ball.pos - car.pos)
		var fang := atan2(lb.x, -lb.z)
		c.steer = clampf(fang * 2.5, -1, 1)
		c.throttle = 0.25 if absf(fang) > 0.4 else 0.0
		c.handbrake = absf(fang) > 0.5
		_stuck = 0.0
		return
	if absf(ang) > 2.3 and dist < 8.0 and v_f < 5.0:
		c.throttle = -1.0
		c.steer = -signf(ang)
		return
	# Target inside our turning circle: slow down (and slide) instead of orbiting it
	var r := 1.0 / maxf(Phys.steer_curvature(v_f), 0.02)
	var lx := local.x
	var lz := -local.z
	var inside := Vector2(absf(lx) - r, lz).length() < r * 0.92
	if inside and absf(ang) > 0.35 and v_f > 4.0:
		desired = minf(desired, maxf(4.0, v_f * 0.6))
		if absf(ang) > 1.1:
			c.handbrake = true
	var err := desired - v_f
	if err > 0.4:
		c.throttle = 1.0
	elif err < -3.0:
		c.throttle = -1.0
	elif err < -0.5:
		c.throttle = 0.0
	else:
		c.throttle = 0.6 if v_f > 13.5 else clampf(err, 0.0, 1.0)
	if allow_boost and err > 2.0 and absf(ang) < 0.3 and car.boost > 0.0 and v_f < 22.7 and car.on_ground:
		c.boost = true
	# stuck detection
	if c.throttle > 0.5 and car.vel.length() < 1.5:
		_stuck += dt
		if _stuck > 1.2:
			_start(Man.UNSTUCK)
			m_dir = Vector2(-signf(ang) if ang != 0.0 else 1.0, 0)
			_stuck = 0.0
	else:
		_stuck = maxf(0.0, _stuck - dt)
	# get back to the floor from walls
	if car.contact_normal.y < 0.5 and target.y < 1.0 and dist > 8.0:
		c.boost = false


func _triggers(c: CarControls, kickoff: bool) -> void:
	if not car.on_ground:
		return
	var local := car.basis.transposed() * (world.ball.pos - car.pos)
	var flat := Vector2(local.x, local.z).length()
	var ang := atan2(local.x, -local.z)
	var spd := car.vel.length()
	if kickoff and coord.kicker[car.team] == car.id:
		if skill["kick_flip"] and flat < 4.2 + spd * 0.24 and absf(ang) < 0.3 and spd > 12.0:
			_start_dodge(local)
		return
	if hit_time < 0.0:
		_try_contact_dodge()
		return
	var t_rem := hit_time - now
	var hb := hit_point
	if aerial_plan and t_rem > 0.8:
		var to_h := Vector3(hb.x - car.pos.x, 0, hb.z - car.pos.z)
		var lh := car.basis.transposed() * to_h
		if absf(atan2(lh.x, -lh.z)) < 0.35:
			_start(Man.AERIAL)
			m_target = hb - shot_dir * (Phys.BALL_R + 0.55)
			m_target_t = hit_time
			return
	if hb.y > 2.1 and skill["jump_shot"]:
		var tj := _jump_time(hb.y - 0.75)
		var lh := car.basis.transposed() * (hb - car.pos)
		var d_hit := Vector2(lh.x, lh.z).length() - (Phys.BALL_R + 0.8)
		var a_hit := atan2(lh.x, -lh.z)
		if t_rem <= tj + 0.02 and t_rem > tj - 0.15 and absf(a_hit) < 0.35 and absf(d_hit - spd * t_rem) < 2.2:
			_start(Man.JUMP_SHOT)
			m_target = hb
			m_target_t = hit_time
		return
	_try_contact_dodge()


## Dodge into the ball when contact is imminent (time-to-contact based).
func _try_contact_dodge() -> void:
	if _rng.randf() > float(skill["dodge"]):
		return
	var b := world.ball
	if b.pos.y > 1.7:
		return
	var rp := Vector3(b.pos.x - car.pos.x, 0, b.pos.z - car.pos.z)
	var rv := Vector3(b.vel.x - car.vel.x, 0, b.vel.z - car.vel.z)
	var d := rp.length()
	if d < 0.5 or d > 6.0:
		return
	var closing := -rp.dot(rv) / d
	if closing < 5.0:
		return
	var ttc := (d - 1.75) / closing
	if ttc > 0.16 or ttc < 0.0:
		return
	# where the ball will be relative to the car when the flip lands
	var lead := rp + rv * (ttc + 0.08)
	var local := car.basis.transposed() * lead
	if absf(atan2(local.x, -local.z)) > 0.6:
		return
	# only dodge if it sends the ball roughly where we want
	if rp.normalized().dot(shot_dir) < 0.2:
		return
	_start_dodge(local)


func _jump_time(h: float) -> float:
	# time for a full-hold single jump to reach height h above the rest position
	var v := Phys.JUMP_IMPULSE
	var a := Phys.JUMP_HOLD_ACCEL - Phys.GRAVITY
	var hold := Phys.JUMP_HOLD_TIME
	var h1 := v * hold + 0.5 * a * hold * hold
	if h <= h1:
		return (-v + sqrt(v * v + 2.0 * a * h)) / a
	var v1 := v + a * hold
	var disc := v1 * v1 - 2.0 * Phys.GRAVITY * (h - h1)
	if disc < 0.0:
		return hold + v1 / Phys.GRAVITY
	return hold + (v1 - sqrt(disc)) / Phys.GRAVITY


func _start(m: int) -> void:
	man = m
	m_time = 0.0


func _start_dodge(local: Vector3) -> void:
	var d := Vector2(local.x, -local.z)
	if d.length() < 0.01:
		d = Vector2(0, 1)
	m_dir = d.normalized()
	_start(Man.DODGE)


# ------------------------------------------------------------------ maneuvers

func _run_maneuver(_dt: float, c: CarControls) -> void:
	match man:
		Man.DODGE:
			if m_time < 0.05:
				c.jump = true
				c.throttle = 1.0
			elif m_time < 0.075:
				c.jump = false
			elif m_time < 0.11:
				c.jump = true
				c.pitch = m_dir.y
				c.yaw = m_dir.x
				c.throttle = 1.0
			elif m_time < 0.8:
				c.pitch = m_dir.y * 0.4
				c.throttle = 1.0
			elif car.on_ground or m_time > 1.6:
				man = Man.NONE
			else:
				_air_recover(c)
		Man.JUMP_SHOT:
			c.jump = m_time < 0.2
			var t_rem := m_target_t - now
			var to := world.ball.pos - car.pos
			if m_time > 0.25 and not car.has_flipped and to.length() < 3.2 and car.num_contacts == 0:
				var l := car.basis.transposed() * to
				var d := Vector2(l.x, -l.z).normalized()
				c.jump = true
				c.pitch = d.y
				c.yaw = d.x
			else:
				_aim(c, Vector3(to.x, 0, to.z).normalized() if to.length() > 0.5 else car.forward(), Vector3.UP)
			c.throttle = 1.0
			if (car.on_ground and m_time > 0.3) or m_time > 2.0 or t_rem < -0.8:
				man = Man.NONE
		Man.AERIAL:
			_aerial(c)
		Man.UNSTUCK:
			c.throttle = -1.0
			c.steer = m_dir.x
			if m_time > 0.7:
				man = Man.NONE
		_:
			man = Man.NONE


func _aerial(c: CarControls) -> void:
	var t_rem := m_target_t - now
	if m_time < 0.2:
		c.jump = true
	elif m_time < 0.24:
		c.jump = false
	elif m_time < 0.28 and m_target.y > 5.0:
		c.jump = true
	var tr := maxf(t_rem, 0.05)
	var delta := m_target - car.pos - car.vel * tr - Vector3(0, -Phys.GRAVITY, 0) * 0.5 * tr * tr
	var a_req := delta * 2.0 / (tr * tr)
	var dir := a_req.normalized() if a_req.length() > 0.5 else (m_target - car.pos).normalized()
	_aim(c, dir, Vector3.UP)
	if m_time > 0.05 and car.forward().dot(dir) > 0.8 and a_req.length() > 1.5:
		c.boost = true
	if m_time > 0.1 and m_time < 0.24:
		c.jump = true
	var touched := world.tick - car.last_ball_touch_tick < 10
	if t_rem < -0.35 or touched or (car.on_ground and m_time > 0.5) or m_time > 4.0:
		man = Man.NONE
		m_time = 0.0


func _air_recover(c: CarControls) -> void:
	# Land on the wheels, nose along the direction of travel.
	if car.body_touching and car.up().dot(car.body_normal) < 0.35:
		c.jump = (world.tick % 20) < 3
		return
	var hv := Vector3(car.vel.x, 0, car.vel.z)
	var fwd: Vector3
	if hv.length() > 2.0:
		fwd = hv.normalized()
	else:
		var f := car.forward()
		fwd = Vector3(f.x, 0, f.z).normalized() if Vector3(f.x, 0, f.z).length() > 0.1 else Vector3(0, 0, -1)
	var up := Vector3.UP
	var s := ArenaGeo.sdf(car.pos)
	if s < 3.5 and car.pos.y > 2.5:
		up = ArenaGeo.sdf_normal(car.pos)
		fwd = (fwd - up * fwd.dot(up))
		if fwd.length() < 0.1:
			fwd = Vector3.DOWN - up * up.dot(Vector3.DOWN)
		fwd = fwd.normalized()
	_aim(c, fwd, up)
	c.throttle = 1.0


## PD controller that turns the car toward a desired forward/up orientation.
func _aim(c: CarControls, fwd_d: Vector3, up_d: Vector3) -> void:
	var b := car.basis
	var f := -b.z
	var u := b.y
	var e := f.cross(fwd_d)
	var fd := f.dot(fwd_d)
	if fd < 0.0:
		if e.length() < 1e-3:
			e = u
		e = e.normalized() * (2.0 - e.length())
	var roll_e := u.cross(up_d)
	e += f * f.dot(roll_e) * 0.9
	var el := b.transposed() * e
	var wl := b.transposed() * car.ang_vel
	var w_des := el * 5.5
	var acc := (w_des - wl) * 10.0
	c.pitch = clampf(-acc.x / Phys.T_PITCH, -1.0, 1.0)
	c.yaw = clampf(-acc.y / Phys.T_YAW, -1.0, 1.0)
	c.roll = clampf(-acc.z / Phys.T_ROLL, -1.0, 1.0)
