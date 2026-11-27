class_name RaceCamera
extends Camera3D

## Dynamic CTR-Style Chase Camera.
## Smooth spring follow, widens FOV on Sacred/Blue Fire, pulls up & back on aerial jumps
## so players clearly see shortcut landings, leans subtly into power slides, and shakes on hits/boosts.

var target: KartPhysics = null
var _cam_yaw: float = 0.0
var _shake: float = 0.0
var _look_ahead_offset: Vector3 = Vector3.ZERO
var _air_pullback: float = 0.0
var _intro_orbit_timer: float = 0.0
var _is_finish_orbit: bool = false
var _finish_angle: float = 0.0
var is_looking_back: bool = false
var _turbo_lag: float = 0.0

const BASE_FOV := 64.0
const BASE_DIST := 5.45
const BASE_HEIGHT := 2.38

func attach_to(kart: KartPhysics) -> void:
	target = kart
	_cam_yaw = kart.heading_yaw
	_is_finish_orbit = false
	_intro_orbit_timer = 1.6
	_turbo_lag = 0.0
	fov = BASE_FOV
	near = 0.15
	far = 1100.0
	if not kart.landing_impact.is_connected(_on_landing_impact):
		kart.landing_impact.connect(_on_landing_impact)
	if not kart.collision_impact.is_connected(_on_collision_impact):
		kart.collision_impact.connect(_on_collision_impact)
	if not kart.boost_triggered.is_connected(_on_boost_triggered):
		kart.boost_triggered.connect(_on_boost_triggered)
	_snap_behind()

func _on_landing_impact(strength: float) -> void:
	if strength > 0.25:
		trigger_shake(strength * 0.55)

func _on_collision_impact(strength: float) -> void:
	trigger_shake(strength * 0.72)

func _on_boost_triggered(_tier: int, is_perf: String, _stage: int) -> void:
	_turbo_lag = 0.85 if is_perf == "perfect" else 0.55
	trigger_shake(0.26)

func trigger_shake(amount: float) -> void:
	_shake = maxf(_shake, amount)

func start_finish_orbit() -> void:
	_is_finish_orbit = true
	_finish_angle = _cam_yaw + PI * 0.25

func _snap_behind() -> void:
	if not target or not is_instance_valid(target):
		return
	var back := Vector3(sin(_cam_yaw), 0.0, cos(_cam_yaw))
	global_position = target.global_position + back * BASE_DIST + Vector3(0.0, BASE_HEIGHT, 0.0)
	look_at(target.global_position + Vector3(0.0, 1.35, 0.0), Vector3.UP)

func _physics_process(delta: float) -> void:
	if not target or not is_instance_valid(target):
		return

	if _shake > 0.0:
		_shake = maxf(0.0, _shake - delta * 2.8)
	if _turbo_lag > 0.0:
		_turbo_lag = maxf(0.0, _turbo_lag - delta * 2.4)

	# Victory celebration orbit around winning kart!
	if _is_finish_orbit:
		_finish_angle += delta * 1.15
		var orbit_pos := target.global_position + Vector3(sin(_finish_angle) * 6.2, 2.5, cos(_finish_angle) * 6.2)
		global_position = global_position.lerp(orbit_pos, minf(1.0, delta * 4.5))
		look_at(target.global_position + Vector3(0.0, 1.15, 0.0), Vector3.UP)
		fov = lerpf(fov, 60.0, delta * 3.0)
		return

	# Smoothly track kart heading (snappier during U-Turn & Drift so corners stay framed!)
	var follow_speed := 8.8
	if target.air_uturn_active:
		follow_speed = 11.5
	elif target.is_drifting:
		follow_speed = 7.4
	_cam_yaw = lerp_angle(_cam_yaw, target.heading_yaw, minf(1.0, delta * follow_speed))

	# Dynamic FOV & Distance boost for Sacred Fire & Blue Fire!
	var tier_fov_add := 0.0
	var tier_dist_add := 0.0
	match target.fire_tier:
		1:
			tier_fov_add = 4.0
			tier_dist_add = 0.25
		2:
			tier_fov_add = 8.5
			tier_dist_add = 0.55
		3: # SACRED FIRE
			tier_fov_add = 14.0
			tier_dist_add = 0.95
		4: # BLUE FIRE!!
			tier_fov_add = 21.0
			tier_dist_add = 1.45

	# Pull slightly higher/wider during aerial jumps so hidden ledges & shortcut landings are crystal clear!
	var target_air := 1.0 if (not target.is_grounded and target.air_time > 0.16) else 0.0
	_air_pullback = lerpf(_air_pullback, target_air, minf(1.0, delta * 4.5))

	var desired_fov := BASE_FOV + tier_fov_add + (target.boost_kick_timer * 14.0)
	fov = lerpf(fov, clampf(desired_fov, 62.0, 94.0), minf(1.0, delta * 7.5))

	var back := Vector3(sin(_cam_yaw), 0.0, cos(_cam_yaw))
	var right := Vector3(cos(_cam_yaw), 0.0, -sin(_cam_yaw))

	# Subtle lateral framing shift during Power-Slide so apex & upcoming zone are clearly visible!
	var drift_side := float(target.drift_dir) * 0.95 if target.is_drifting else 0.0
	var dist := BASE_DIST + tier_dist_add + _air_pullback * 1.45 + sin(_turbo_lag * PI) * 0.88
	var height := BASE_HEIGHT + _air_pullback * 1.35 - sin(_turbo_lag * PI) * 0.18

	var desired_pos := target.global_position + back * dist + right * drift_side + Vector3(0.0, height, 0.0)
	if is_looking_back:
		# Instant CTR Rear-View Mirror Glance!
		var fwd_look := Vector3(-sin(_cam_yaw), 0.0, -cos(_cam_yaw))
		global_position = target.global_position + fwd_look * 5.6 + Vector3(0.0, 2.55, 0.0)
		look_at(target.global_position - fwd_look * 8.0 + Vector3(0.0, 1.2, 0.0), Vector3.UP)
		return

	if _shake > 0.01:
		desired_pos += Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)) * _shake * 0.36

	global_position = global_position.lerp(desired_pos, minf(1.0, delta * 14.0))

	var fwd := Vector3(-sin(_cam_yaw), 0.0, -cos(_cam_yaw))
	var look_target := target.global_position + fwd * 4.2 + Vector3(0.0, 1.35 - _air_pullback * 0.35, 0.0)
	_look_ahead_offset = _look_ahead_offset.lerp(look_target, minf(1.0, delta * 18.0))
	look_at(_look_ahead_offset, Vector3.UP)
