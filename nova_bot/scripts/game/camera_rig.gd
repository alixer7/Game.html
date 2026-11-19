class_name CameraRig
extends Node3D
## Follow camera for the platformer: orbit with drag / right-stick, soft vertical follow, look-ahead,
## optional auto-steer assist, obstruction pull-in, speed FOV kick and trauma-based shake.

const PITCH_MIN := 0.12
const PITCH_MAX := 1.1

var player: Player
var cam: Camera3D
var yaw: float = 0.0
var pitch: float = 0.42
var dist: float = 7.6
var base_fov: float = 64.0
var height: float = 1.25

var _focus := Vector3.ZERO
var _look := Vector3.ZERO
var _dist_cur: float = 7.6
var _dist_eff: float = 7.6
var _pitch_cur: float = 0.42
var _fov: float = 64.0
var _trauma: float = 0.0
var _manual_t: float = 10.0


func _ready() -> void:
	cam = Camera3D.new()
	cam.fov = base_fov
	cam.near = 0.1
	cam.far = 700.0
	cam.current = true
	add_child(cam)


func snap() -> void:
	if player == null:
		return
	_focus = player.global_position + Vector3(0.0, height, 0.0)
	_look = Vector3.ZERO
	_dist_cur = dist
	_dist_eff = dist
	_pitch_cur = pitch
	_fov = base_fov
	_apply(0.016, false)


func shake(amount: float) -> void:
	_trauma = minf(_trauma + amount, 1.0)


func add_drag(d: Vector2) -> void:
	var sens: float = float(Game.settings.get("cam_sens", 1.0))
	var inv: float = -1.0 if bool(Game.settings.get("invert_y", false)) else 1.0
	yaw -= d.x * 0.0042 * sens
	pitch = clampf(pitch + d.y * 0.0036 * sens * inv, PITCH_MIN, PITCH_MAX)
	_manual_t = 0.0


func _physics_process(delta: float) -> void:
	if player == null or not is_instance_valid(player):
		return
	# keyboard / gamepad camera
	var cx: float = Input.get_axis("cam_right", "cam_left")
	var cy: float = Input.get_axis("cam_down", "cam_up")
	if absf(cx) > 0.05 or absf(cy) > 0.05:
		yaw += cx * 2.4 * delta
		pitch = clampf(pitch + cy * 1.3 * delta, PITCH_MIN, PITCH_MAX)
		_manual_t = 0.0
	_manual_t += delta
	# gentle auto-steer toward the side the player is pushing
	var assist: int = int(Game.settings.get("cam_assist", 1))
	if assist > 0 and _manual_t > 1.4 and player.alive and player.controls_enabled:
		var iv: Vector2 = Input.get_vector("move_left", "move_right", "move_forward", "move_back", 0.2)
		var hs: float = Vector2(player.velocity.x, player.velocity.z).length()
		if absf(iv.x) > 0.25 and hs > 2.0:
			var rate: float = 0.55 if assist == 1 else 1.1
			yaw -= iv.x * rate * delta * (1.0 - 0.6 * maxf(-iv.y, 0.0))
	_apply(delta, true)


func _apply(delta: float, smooth: bool) -> void:
	var tp: Vector3 = player.global_position
	var want: Vector3 = tp + Vector3(0.0, height, 0.0)
	var ahead := Vector3(player.velocity.x, 0.0, player.velocity.z) * 0.16
	if smooth:
		_look = _look.lerp(ahead, 1.0 - exp(-4.0 * delta))
	want += _look
	var kh: float = 1.0 if not smooth else 1.0 - exp(-14.0 * delta)
	_focus.x = lerpf(_focus.x, want.x, kh)
	_focus.z = lerpf(_focus.z, want.z, kh)
	var dy: float = want.y - _focus.y
	var ky: float = 1.0 - exp(-5.0 * delta) if player.is_on_floor() else 1.0 - exp(-2.2 * delta)
	if dy < -3.0 or dy > 2.5:
		ky = 1.0 - exp(-9.0 * delta)
	if not smooth:
		ky = 1.0
	_focus.y = lerpf(_focus.y, want.y, ky)

	var kd: float = 1.0 - exp(-3.0 * delta) if smooth else 1.0
	_dist_cur = lerpf(_dist_cur, dist, kd)
	var extra: float = 0.0
	if player.velocity.y < -6.0:
		extra = clampf((-player.velocity.y - 6.0) / 60.0, 0.0, 0.3)
	_pitch_cur = lerpf(_pitch_cur, clampf(pitch + extra, PITCH_MIN, PITCH_MAX + 0.2), kd)

	var cp: float = cos(_pitch_cur)
	var back := Vector3(sin(yaw) * cp, sin(_pitch_cur), cos(yaw) * cp)
	var allowed: float = _dist_cur
	if smooth:
		var space: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
		if space != null:
			var q := PhysicsRayQueryParameters3D.create(_focus, _focus + back * (_dist_cur + 0.4))
			q.collision_mask = 1
			var hit: Dictionary = space.intersect_ray(q)
			if not hit.is_empty():
				var hit_pos: Vector3 = hit["position"]
				allowed = clampf(_focus.distance_to(hit_pos) - 0.4, 1.8, _dist_cur)
	if allowed < _dist_eff or not smooth:
		_dist_eff = allowed
	else:
		_dist_eff = lerpf(_dist_eff, allowed, 1.0 - exp(-4.0 * delta))
	global_position = _focus + back * _dist_eff
	look_at(_focus, Vector3.UP)

	# FOV kick with speed / dash
	var hspeed: float = Vector2(player.velocity.x, player.velocity.z).length()
	var fov_t: float = base_fov + clampf(hspeed - 9.0, 0.0, 14.0) * 0.55
	if player.is_dashing():
		fov_t += 5.0
	_fov = lerpf(_fov, fov_t, 1.0 - exp(-6.0 * delta)) if smooth else fov_t
	cam.fov = _fov

	# shake
	_trauma = maxf(_trauma - delta * 1.8, 0.0)
	var s: float = _trauma * _trauma
	cam.h_offset = randf_range(-1.0, 1.0) * 0.35 * s
	cam.v_offset = randf_range(-1.0, 1.0) * 0.35 * s
	cam.rotation.z = randf_range(-1.0, 1.0) * 0.02 * s
