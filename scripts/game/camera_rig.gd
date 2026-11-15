class_name CameraRig
extends Camera3D
## Chase camera with car-cam / ball-cam, cinematic replay cam and menu orbit.

enum Mode { CAR, ORBIT, REPLAY, SPECTATE, GOAL }

var mode := Mode.ORBIT
var ball_cam := true
var base_fov := 100.0
var distance := 2.9
var height := 1.05
var angle_deg := -4.0
var stiffness := 0.5
var swivel := 6.0

var _dir := Vector3(0, 0, -1)
var _up := Vector3.UP
var _pos := Vector3(0, 12, 40)
var _look := Vector3.ZERO
var _look_dir := Vector3(0, 0, -1)
var _offset := Vector3(0, 1, 3)
var _fov_kick := 0.0
var _trauma := 0.0
var _orbit_t := 0.0
var _initialized := false
var _ball_cam_blend := 1.0
var _goal_point := Vector3.ZERO


func _ready() -> void:
	keep_aspect = Camera3D.KEEP_WIDTH
	near = 0.08
	far = 600.0
	fov = base_fov
	current = true


func apply_settings(s: Dictionary) -> void:
	base_fov = s.get("cam_fov", base_fov)
	distance = s.get("cam_distance", distance)
	height = s.get("cam_height", height)
	angle_deg = s.get("cam_angle", angle_deg)
	stiffness = s.get("cam_stiffness", stiffness)


func shake(amount: float) -> void:
	_trauma = clampf(_trauma + amount, 0.0, 1.0)


func snap_behind(car_pos: Vector3, car_basis: Basis) -> void:
	var f := -car_basis.z
	_dir = Vector3(f.x, 0, f.z).normalized()
	_up = Vector3.UP
	_pos = car_pos - _dir * distance + Vector3.UP * height
	_look = car_pos + _dir * 4.0
	_look_dir = (_look - _pos).normalized()
	_offset = _pos - car_pos
	_initialized = true


func set_goal_point(p: Vector3) -> void:
	_goal_point = p


## Follow a car (position/basis already interpolated).
## Ball cam looks toward the ball first, but the car is always kept inside a
## view cone so it never leaves the bottom of the screen - also on walls.
func follow(car_pos: Vector3, car_basis: Basis, car_vel: Vector3, grounded: bool, ball_pos: Vector3,
		boosting: bool, supersonic: bool, delta: float) -> void:
	if not _initialized:
		snap_behind(car_pos, car_basis)
	# Camera "up" follows the driving surface smoothly (walls), world-up in the air.
	var target_up := Vector3.UP
	if grounded:
		target_up = car_basis.y
		if target_up.y < -0.2:
			# on the ceiling keep the view mostly upright
			target_up = (Vector3.UP * 0.7 + target_up * 0.3).normalized()
	_up = _slerp_dir(_up, target_up, 1.0 - exp(-delta * (3.2 if grounded else 1.8)))

	_ball_cam_blend = move_toward(_ball_cam_blend, 1.0 if ball_cam else 0.0, delta * 2.5)
	var f := -car_basis.z
	var car_dir := f - _up * f.dot(_up)
	if car_dir.length_squared() < 0.04:
		var hv := car_vel - _up * car_vel.dot(_up)
		car_dir = hv if hv.length_squared() > 1.0 else _dir
	car_dir = car_dir.normalized()
	var to_ball := ball_pos - car_pos
	var ball_dir := to_ball - _up * to_ball.dot(_up)
	if ball_dir.length_squared() < 1.0:
		ball_dir = _dir
	ball_dir = ball_dir.normalized()
	var target_dir := _slerp_dir(car_dir, ball_dir, _ball_cam_blend)
	var rate := swivel * (0.6 + stiffness)
	if _ball_cam_blend > 0.5:
		rate = lerpf(rate, 4.5, _ball_cam_blend)
		if to_ball.length() < 5.0:
			rate *= 0.5
	_dir = _slerp_dir(_dir, target_dir, 1.0 - exp(-delta * rate))
	_dir = _dir - _up * _dir.dot(_up)
	if _dir.length_squared() < 1e-4:
		_dir = car_dir
	_dir = _dir.normalized()

	# Smooth the offset relative to the car (not the absolute position) so the
	# follow distance never shrinks at speed.
	var want_off := -_dir * distance + _up * height
	var follow_rate := lerpf(10.0, 40.0, stiffness)
	_offset = _offset.lerp(want_off, 1.0 - exp(-delta * follow_rate))
	if _offset.length() > 0.01:
		_offset = _offset.normalized() * want_off.length()
	_pos = _keep_inside(car_pos + _up * 0.6, car_pos + _offset)

	# --- where to look
	var focus := car_pos + _up * 0.35
	var look := (focus + _dir * 4.0 + _up * 0.25 - _pos).normalized()
	if _ball_cam_blend > 0.0:
		look = _slerp_dir(look, (ball_pos - _pos).normalized(), _ball_cam_blend)
	var right := look.cross(_up)
	if right.length_squared() > 1e-4:
		look = look.rotated(right.normalized(), deg_to_rad(angle_deg))
	look = _constrain_to_car(look, focus)
	_look_dir = _slerp_dir(_look_dir, look, 1.0 - exp(-delta * 14.0))
	_look_dir = _constrain_to_car(_look_dir, focus)
	_look = _pos + _look_dir * 10.0

	var kick := 0.0
	if boosting:
		kick += 3.0
	if supersonic:
		kick += 4.0
	_fov_kick = lerpf(_fov_kick, kick, 1.0 - exp(-delta * 4.0))
	_apply(delta, 0.0)


## Rotates `look` toward the car so the car stays inside the vertical field of view.
func _constrain_to_car(look: Vector3, focus: Vector3) -> Vector3:
	var to_car := focus - _pos
	if to_car.length_squared() < 0.01:
		return look
	var c := to_car.normalized()
	# the closer the car, the bigger it appears: keep all of it inside the frame
	var car_ang := rad_to_deg(atan(0.5 / maxf(to_car.length(), 0.5)))
	var max_ang := deg_to_rad(maxf(2.0, _vfov() * 0.5 - car_ang - 3.0))
	var a := look.angle_to(c)
	if a > max_ang:
		return _slerp_dir(c, look, max_ang / a)
	return look


func _vfov() -> float:
	var vp := get_viewport().get_visible_rect().size
	var aspect := vp.x / maxf(vp.y, 1.0)
	return rad_to_deg(2.0 * atan(tan(deg_to_rad(fov) * 0.5) / aspect))


func orbit(center: Vector3, radius: float, h: float, speed: float, delta: float) -> void:
	_orbit_t += delta * speed
	var want := center + Vector3(cos(_orbit_t) * radius, h, sin(_orbit_t) * radius)
	_pos = _pos.lerp(want, 1.0 - exp(-delta * 2.0))
	_look = _look.lerp(center, 1.0 - exp(-delta * 2.0))
	_up = Vector3.UP
	_fov_kick = 0.0
	_apply(delta, 0.0, 70.0)


## Broadcast-style camera that tracks a point (ball) from a moving vantage.
func track(target: Vector3, target_vel: Vector3, delta: float, side_bias: float = 1.0) -> void:
	var v := Vector3(target_vel.x, 0, target_vel.z)
	var back := -v.normalized() if v.length() > 2.0 else Vector3(0, 0, 1)
	var want := target + back * 13.0 + Vector3(side_bias * 4.0, 5.5, 0)
	want.y = clampf(want.y, 2.0, Phys.HEIGHT - 2.0)
	_pos = _pos.lerp(want, 1.0 - exp(-delta * 2.2))
	_pos = _keep_inside(target, _pos)
	_look = _look.lerp(target, 1.0 - exp(-delta * 7.0))
	_up = Vector3.UP
	_fov_kick = lerpf(_fov_kick, 0.0, delta * 3.0)
	_apply(delta, 0.0, 78.0)


## Fixed camera inside/behind a goal looking at the target.
func goal_view(goal_z: float, target: Vector3, delta: float) -> void:
	var want := Vector3(target.x * 0.3, 7.0, goal_z - signf(goal_z) * 6.0)
	_pos = _pos.lerp(want, 1.0 - exp(-delta * 2.5))
	_look = _look.lerp(target, 1.0 - exp(-delta * 6.0))
	_up = Vector3.UP
	_apply(delta, 0.0, 80.0)


func _keep_inside(anchor: Vector3, p: Vector3) -> Vector3:
	# Push the camera back inside the arena along the shell normal so it keeps
	# its distance from the car instead of collapsing onto it.
	var margin := 0.6
	if ArenaGeo.sdf(anchor) < margin:
		return p
	var s := ArenaGeo.sdf(p)
	var i := 0
	while s < margin and i < 4:
		p += ArenaGeo.sdf_normal(p) * (margin - s + 0.02)
		s = ArenaGeo.sdf(p)
		i += 1
	if s < margin * 0.5:
		# fall back to sliding toward the car
		var lo := 0.0
		var hi := 1.0
		for k in range(10):
			var mid := (lo + hi) * 0.5
			if ArenaGeo.sdf(anchor.lerp(p, mid)) >= margin:
				lo = mid
			else:
				hi = mid
		p = anchor.lerp(p, lo)
	return p


func _apply(delta: float, pitch_offset_deg: float, fov_override: float = -1.0) -> void:
	var look_dir := (_look - _pos)
	if look_dir.length_squared() < 1e-6:
		look_dir = _dir
	var up_ref := _up
	if absf(look_dir.normalized().dot(up_ref)) > 0.98:
		up_ref = _dir
	var xf := Transform3D().looking_at(look_dir, up_ref)
	if pitch_offset_deg != 0.0:
		xf.basis = xf.basis.rotated(xf.basis.x, deg_to_rad(pitch_offset_deg))
	xf.origin = _pos
	_trauma = maxf(0.0, _trauma - delta * 1.6)
	if _trauma > 0.0:
		var s := _trauma * _trauma
		var t := Time.get_ticks_msec() / 1000.0
		xf.origin += xf.basis.x * sin(t * 47.0) * 0.25 * s + xf.basis.y * sin(t * 61.0 + 1.3) * 0.2 * s
		xf.basis = xf.basis.rotated(xf.basis.z, sin(t * 33.0) * 0.03 * s)
	global_transform = xf
	var target_fov := (fov_override if fov_override > 0.0 else base_fov) + _fov_kick
	fov = lerpf(fov, target_fov, 1.0 - exp(-delta * 6.0))


static func _slerp_dir(a: Vector3, b: Vector3, t: float) -> Vector3:
	var an := a.normalized()
	var bn := b.normalized()
	var d := clampf(an.dot(bn), -1.0, 1.0)
	if d > 0.9999:
		return bn
	if d < -0.999:
		var perp := an.cross(Vector3.UP)
		if perp.length_squared() < 0.01:
			perp = an.cross(Vector3.RIGHT)
		return an.rotated(perp.normalized(), PI * t).normalized()
	return an.slerp(bn, t).normalized()
