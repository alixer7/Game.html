class_name ChaseCamera
extends Camera3D
## Chase camera with drift-aware follow, speed FOV, shake, collision avoidance
## and cinematic slow-motion while the car is airborne.

var target: Car
var mode := 0                 # 0 far chase, 1 near chase, 2 bumper, 3 hood
var look_back := false
var shake := 0.0
var air_cine := 0.0
var cine_side := 1.0
var _pos := Vector3.ZERO
var _vel := Vector3.ZERO
var _look := Vector3.ZERO
var _dir := Vector3.FORWARD
var _inited := false
var _slow_timer := 0.0
var _slow_scale := 1.0
var _fov := 68.0
var _air_start_y := 0.0
var orbit := false            # menu orbit mode
var orbit_angle := 0.0
var _ray := PhysicsRayQueryParameters3D.new()

const MODES := [
	{"dist": 6.4, "height": 2.05, "look_h": 1.05, "fov": 68.0},
	{"dist": 4.6, "height": 1.6, "look_h": 0.95, "fov": 72.0},
	{"dist": -0.4, "height": 0.62, "look_h": 0.62, "fov": 78.0},
	{"dist": -1.2, "height": 1.08, "look_h": 1.0, "fov": 74.0},
]


func _ready() -> void:
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	far = 4200.0
	near = 0.12
	fov = 68.0
	_ray.collision_mask = 1


func set_target(c: Car, snap := true) -> void:
	target = c
	if snap:
		_inited = false


func cycle_mode() -> void:
	mode = (mode + 1) % MODES.size()
	_inited = false
	Game.settings.camera_mode = mode


func add_shake(v: float) -> void:
	shake = minf(shake + v, 1.2)


## brief global slow motion (crash cams, finish line)
func slowmo(scale: float, duration: float) -> void:
	_slow_scale = scale
	_slow_timer = duration


func _process(delta: float) -> void:
	var real_dt := delta / maxf(Engine.time_scale, 0.05)
	if target == null or not is_instance_valid(target):
		_update_time_scale(real_dt)
		return
	var xf := target.get_global_transform_interpolated()
	var car_pos := xf.origin
	var up := Vector3.UP
	if orbit:
		orbit_angle += real_dt * 0.18
		var off := Vector3(sin(orbit_angle), 0, cos(orbit_angle)) * 7.5 + Vector3(0, 2.2, 0)
		global_position = global_position.lerp(car_pos + off, clampf(real_dt * 3.0, 0, 1)) if _inited else car_pos + off
		_inited = true
		look_at(car_pos + Vector3(0, 0.7, 0), up)
		fov = 55.0
		return
	var m: Dictionary = MODES[mode]
	var fwd := -xf.basis.z
	fwd.y = 0.0
	fwd = fwd.normalized()
	var vel := target.linear_velocity
	var vh := Vector3(vel.x, 0, vel.z)
	var spd := vh.length()
	# chase direction: heading, swinging towards the travel direction in slides
	var want_dir := fwd
	if spd > 4.0 and target.speed > 0.0:
		var vdir := vh.normalized()
		want_dir = fwd.slerp(vdir, clampf(absf(target.drift_angle) * 0.9, 0.0, 0.55)).normalized()
	if look_back:
		want_dir = -want_dir
	if not _inited:
		_dir = want_dir
	var lag := 6.5 if mode <= 1 else 20.0
	_dir = _dir.slerp(want_dir, clampf(real_dt * lag, 0.0, 1.0)).normalized()
	var dist: float = m.dist
	var hgt: float = m.height
	# speed pulls the camera back a little
	if mode <= 1:
		dist += clampf(spd / 80.0, 0.0, 1.0) * 1.1
		hgt -= clampf(spd / 80.0, 0.0, 1.0) * 0.25
	# airborne cinematic orbit
	var airborne := target.grounded == 0 and target.air_time > 0.18 and spd > 12.0
	var above: float = car_pos.y - (Game.world.ground_y(car_pos) if Game.world else car_pos.y)
	if airborne and above > 1.1:
		if air_cine < 0.01:
			cine_side = 1.0 if randf() > 0.5 else -1.0
		air_cine = move_toward(air_cine, 1.0, real_dt * 2.6)
	else:
		air_cine = move_toward(air_cine, 0.0, real_dt * 3.2)
	var cam_dir := _dir
	if air_cine > 0.0 and mode <= 1:
		var e := air_cine * air_cine * (3.0 - 2.0 * air_cine)
		cam_dir = _dir.rotated(up, deg_to_rad(62.0) * cine_side * e)
		dist = lerpf(dist, dist * 0.95, e)
		hgt = lerpf(hgt, 0.7, e)
	var desired: Vector3
	var look_t: Vector3
	if mode <= 1:
		desired = car_pos - cam_dir * dist + up * hgt
		look_t = car_pos + up * float(m.look_h) + _dir * (2.5 + air_cine * 1.5)
	else:
		# bumper / hood cams ride with the car body
		var b := xf.basis
		var local := Vector3(0, hgt, -dist if not look_back else dist + target.model.length * 0.55)
		if mode == 2:
			local.z = -target.model.length * 0.5 - 0.1 if not look_back else target.model.length * 0.5 + 0.3
		desired = xf * local
		look_t = desired + (-b.z if not look_back else b.z) * 20.0 + b.y * 0.2
	# spring follow (critically damped) for chase modes
	if not _inited:
		_pos = desired
		_vel = Vector3.ZERO
		_look = look_t
		_inited = true
	if mode <= 1:
		var w := 9.0
		var acc := (desired - _pos) * w * w - _vel * 2.0 * w
		_vel += acc * real_dt
		_pos += _vel * real_dt
		# never trail too far behind at high speed
		var off := _pos - desired
		if off.length() > 3.0:
			_pos = desired + off.normalized() * 3.0
		_look = _look.lerp(look_t, clampf(real_dt * 12.0, 0.0, 1.0))
	else:
		_pos = desired
		_look = look_t
	# avoid clipping through walls / terrain
	var final_pos := _pos
	if mode <= 1:
		var pivot := car_pos + up * 1.2
		_ray.from = pivot
		_ray.to = _pos
		_ray.exclude = [target.get_rid()]
		var hit := get_world_3d().direct_space_state.intersect_ray(_ray)
		if not hit.is_empty():
			final_pos = hit.position + (pivot - _pos).normalized() * 0.35
		var gy: float = Game.world.ground_y(final_pos) if Game.world else -1e9
		final_pos.y = maxf(final_pos.y, gy + 0.45)
	# shake
	var rough := 0.0
	if target.grounded > 0 and not (target.surface in ["asphalt", "concrete"]):
		rough = clampf(spd / 40.0, 0.0, 1.0) * 0.08
	var s := shake + rough + (0.05 if target.nitro_active else 0.0) * clampf(spd / 50.0, 0, 1)
	var t := Time.get_ticks_msec() * 0.001
	var jitter := Vector3(sin(t * 47.0), sin(t * 59.0 + 1.3), sin(t * 53.0 + 2.1)) * s * 0.12
	global_position = final_pos + jitter
	look_at(_look + jitter * 0.5, up)
	shake = move_toward(shake, 0.0, real_dt * 2.2)
	# fov
	var target_fov: float = m.fov + clampf(spd / 85.0, 0.0, 1.0) * 14.0 + (9.0 if target.nitro_active else 0.0)
	target_fov -= air_cine * 6.0
	_fov = lerpf(_fov, target_fov, clampf(real_dt * 3.0, 0.0, 1.0))
	fov = _fov
	_update_time_scale(real_dt)


func _update_time_scale(real_dt: float) -> void:
	var want := 1.0
	if Game.settings.slowmo_jumps and air_cine > 0.0:
		want = lerpf(1.0, 0.42, air_cine)
	if _slow_timer > 0.0:
		_slow_timer -= real_dt
		want = minf(want, _slow_scale)
	if get_tree().paused:
		want = 1.0
	var ts := move_toward(Engine.time_scale, want, real_dt * 2.5)
	Engine.time_scale = ts
	AudioServer.playback_speed_scale = lerpf(0.75, 1.0, (ts - 0.4) / 0.6)
