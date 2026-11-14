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
	_initialized = true


func set_goal_point(p: Vector3) -> void:
	_goal_point = p


## Follow a car (position/basis already interpolated).
func follow(car_pos: Vector3, car_basis: Basis, car_vel: Vector3, grounded: bool, ball_pos: Vector3,
		boosting: bool, supersonic: bool, delta: float) -> void:
	if not _initialized:
		snap_behind(car_pos, car_basis)
	var target_up := car_basis.y if grounded else Vector3.UP
	if grounded and car_basis.y.y < -0.2:
		target_up = Vector3.UP.lerp(car_basis.y, 0.5).normalized()
	_up = _slerp_dir(_up, target_up, 1.0 - exp(-delta * (6.0 if grounded else 2.5)))

	_ball_cam_blend = move_toward(_ball_cam_blend, 1.0 if ball_cam else 0.0, delta * 3.0)
	var f := -car_basis.z
	var car_dir := f - _up * f.dot(_up)
	if car_dir.length_squared() < 0.04:
		var hv := car_vel - _up * car_vel.dot(_up)
		car_dir = hv if hv.length_squared() > 1.0 else _dir
	car_dir = car_dir.normalized()
	var to_ball := ball_pos - car_pos
	var ball_dir := to_ball - _up * to_ball.dot(_up)
	if ball_dir.length_squared() < 0.25:
		ball_dir = car_dir
	ball_dir = ball_dir.normalized()
	var target_dir := _slerp_dir(car_dir, ball_dir, _ball_cam_blend)
	var rate := swivel * (0.6 + stiffness)
	if ball_cam and to_ball.length() < 4.0:
		rate *= 0.5
	_dir = _slerp_dir(_dir, target_dir, 1.0 - exp(-delta * rate))
	_dir = (_dir - _up * _dir.dot(_up)).normalized()

	var dist := distance
	var hgt := height
	var want := car_pos - _dir * dist + _up * hgt
	# positional lag scaled by stiffness (0 = loose, 1 = rigid)
	var follow_rate := lerpf(10.0, 40.0, stiffness)
	_pos = _pos.lerp(want, 1.0 - exp(-delta * follow_rate))
	_pos = _keep_inside(car_pos + _up * 0.6, _pos)

	var look_car := car_pos + _up * 0.55 + _dir * 3.0
	var look_target := look_car
	if _ball_cam_blend > 0.0:
		var lb := ball_pos
		var to_lb := (lb - _pos)
		# limit how far the camera pitches up so the car stays in shot
		var flat := to_lb - _up * to_lb.dot(_up)
		var up_amt := to_lb.dot(_up)
		var max_up := flat.length() * 0.75
		up_amt = clampf(up_amt, -flat.length() * 0.35, max_up)
		var look_ball := _pos + flat + _up * up_amt
		look_target = look_car.lerp(look_ball, _ball_cam_blend * 0.85)
	_look = _look.lerp(look_target, 1.0 - exp(-delta * 18.0))

	var kick := 0.0
	if boosting:
		kick += 3.0
	if supersonic:
		kick += 4.0
	_fov_kick = lerpf(_fov_kick, kick, 1.0 - exp(-delta * 4.0))
	_apply(delta, angle_deg)


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
	var margin := 0.45
	if ArenaGeo.sdf(anchor) < margin:
		return p
	if ArenaGeo.sdf(p) >= margin:
		return p
	var lo := 0.0
	var hi := 1.0
	for i in range(10):
		var mid := (lo + hi) * 0.5
		if ArenaGeo.sdf(anchor.lerp(p, mid)) >= margin:
			lo = mid
		else:
			hi = mid
	return anchor.lerp(p, lo)


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
