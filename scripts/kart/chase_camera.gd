class_name ChaseCamera
extends Camera3D
## Third-person racing camera tuned for phones: shows the road ahead, swings
## out during slides to reveal the corner, keeps jumps readable.

@export var distance := 5.3
@export var height := 2.05
@export var look_ahead := 4.5
@export var base_fov := 72.0

var target: Kart
var look_back := false
var _yaw := 0.0
var _pos := Vector3.ZERO
var _y := 0.0
var _shake := 0.0
var _fov := 72.0
var _ray := PhysicsRayQueryParameters3D.new()
var _initialized := false


func _ready() -> void:
	current = true
	near = 0.15
	far = 1600.0
	_ray.collision_mask = 1


func attach(k: Kart) -> void:
	target = k
	target.impact.connect(func(sev: int, _s: float, _p: Vector3) -> void: _shake = maxf(_shake, 0.05 + sev * 0.1))
	target.landed.connect(func(at: float, _g: bool, imp: float) -> void:
		if at > 0.5: _shake = maxf(_shake, clampf(imp * 0.01, 0.0, 0.15)))
	snap()


func snap() -> void:
	if target == null:
		return
	_yaw = target.yaw
	_y = target.global_position.y
	_pos = _desired()
	global_position = _pos
	_initialized = true


func _desired() -> Vector3:
	var dir := Vector3(-sin(_yaw), 0, -cos(_yaw))
	if look_back:
		dir = -dir
	var tp := target.global_position
	var speed_k := clampf(target.speed / 30.0, 0.0, 1.0)
	var dist := distance + speed_k * 0.9
	return Vector3(tp.x, _y, tp.z) - dir * dist + Vector3.UP * (height + speed_k * 0.25)


func _physics_process(dt: float) -> void:
	if target == null:
		return
	if not _initialized:
		snap()
	# follow the travel direction more than the chassis while sliding
	var hv := Vector3(target.velocity.x, 0, target.velocity.z)
	var follow_yaw := target.yaw
	if hv.length() > 4.0:
		var vel_yaw := atan2(-hv.x, -hv.z)
		var w := 0.55 if target.drifting else 0.25
		if not target.grounded:
			w = 0.7
		follow_yaw = lerp_angle(target.yaw, vel_yaw, w)
	if target.spin_time > 0.0:
		follow_yaw = _yaw
	_yaw = lerp_angle(_yaw, follow_yaw, clampf(dt * (5.0 if target.grounded else 2.5), 0.0, 1.0))
	# vertical: track the kart quickly when grounded, lag in the air (shows landings)
	var ty := target.global_position.y
	var vrate := 6.0 if target.grounded else 1.6
	_y = lerpf(_y, ty, clampf(dt * vrate, 0.0, 1.0))
	if ty - _y > 3.0:
		_y = ty - 3.0
	if _y - ty > 4.0:
		_y = ty + 4.0
	var want := _desired()
	_pos = _pos.lerp(want, clampf(dt * 12.0, 0.0, 1.0))
	# keep the camera out of walls / terrain
	var anchor := target.global_position + Vector3.UP * 1.3
	_ray.from = anchor
	_ray.to = _pos
	_ray.exclude = [target.get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(_ray)
	var final := _pos
	if not hit.is_empty():
		final = (hit.position as Vector3) + (anchor - (hit.position as Vector3)).normalized() * 0.4
	var shake_off := Vector3.ZERO
	if _shake > 0.0:
		shake_off = Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)) * _shake
		_shake = maxf(_shake - dt * 0.6, 0.0)
	global_position = final + shake_off
	var dir := Vector3(-sin(_yaw), 0, -cos(_yaw))
	if look_back:
		dir = -dir
	var look := target.global_position + dir * look_ahead + Vector3.UP * 0.9
	if not target.grounded:
		look += Vector3.DOWN * clampf(-target.velocity.y * 0.08, 0.0, 1.5)
	if global_position.distance_to(look) > 0.1:
		look_at(look, Vector3.UP)
	# speed / boost FOV
	var f := base_fov + clampf(target.speed / 32.0, 0.0, 1.0) * 6.0
	if target.tier == 1:
		f += 6.0
	elif target.tier == 2:
		f += 11.0
	_fov = lerpf(_fov, f, clampf(dt * 3.0, 0.0, 1.0))
	fov = _fov
