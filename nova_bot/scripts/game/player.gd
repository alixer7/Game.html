class_name Player
extends CharacterBody3D
## Third-person platformer hero: camera-relative run, coyote + buffered jump, variable height, double
## jump (front flip), hover jets (with damaging lasers), punch combo (jab, jab, uppercut), air spin,
## charged spin (hold attack), air dash, battery power system, hurt / shutdown / respawn.
## Origin is at the feet. Heading convention: model yaw = atan2(-dir.x, -dir.z).

signal hp_changed(hp: int, max_hp: int)
signal died
signal damaged
signal landed(impact: float)
signal jumped(kind: String)
signal battery_changed(value: float, max_value: float)
signal reserve_changed(active: bool, left: float)

const RUN_SPEED := 9.0
const ACCEL := 70.0
const FRICTION := 80.0
const AIR_ACCEL := 38.0
const AIR_FRICTION := 10.0
const GRAVITY := 34.0
const FALL_MULT := 1.35
const MAX_FALL := 38.0
const JUMP_VEL := 12.8
const DOUBLE_JUMP_VEL := 11.2
const COYOTE := 0.12
const JUMP_BUFFER := 0.14
const JUMP_CUT := 0.45
const HOVER_TIME := 1.1
const HOVER_ACCEL := 45.0
const SPIN_TIME := 0.45
const SPIN_BIG_TIME := 0.8
const SPIN_CD := 0.25
const SPIN_REACH := 2.1
const SPIN_BIG_REACH := 3.5
const PUNCH_TIME := [0.0, 0.3, 0.3, 0.46]
const PUNCH_REACH := 1.55
const CHARGE_TIME := 0.75
const DASH_TIME := 0.2
const DASH_SPEED := 22.0
const DASH_CD := 0.55
const INVULN := 1.6
const HURT_LOCK := 0.35

# ---- battery (percent). Hover is by far the hungriest, attacks cost less, walking the least.
const BAT_MAX := 100.0
const DRAIN_MOVE := 0.2          # per second at full running speed
const DRAIN_JUMP := 0.25
const DRAIN_DOUBLE := 0.8
const DRAIN_HOVER := 6.0         # per second, grows up to x1.6 the longer one hover lasts
const DRAIN_PUNCH := 0.5
const DRAIN_SPIN := 1.0
const DRAIN_SPIN_BIG := 2.6
const DRAIN_DASH := 1.5
const LOW_BAT := 20.0
const RESERVE_TIME := 10.0
const RESPAWN_CHARGE := 45.0

var world: Node = null
var model: RobotModel
var cam_yaw: float = 0.0
var hp: int = 3
var max_hp: int = 3
var alive: bool = true
var controls_enabled: bool = true
var god_mode: bool = false
var battery: float = BAT_MAX
var frozen: bool = false

var _coyote: float = 0.0
var _jump_buf: float = 0.0
var _air_jumps: int = 1
var _hover_fuel: float = HOVER_TIME
var _hovering: bool = false
var _hover_cont: float = 0.0
var _hover_loop: bool = false
var _laser_t: float = 0.0
var _jump_cut_done: bool = true
var _jump_held: bool = false
var _can_dash: bool = true
var _dash_t: float = 0.0
var _dash_cd: float = 0.0
var _dash_dir := Vector3(0.0, 0.0, -1.0)
var _spin_t: float = 0.0
var _spin_big: bool = false
var _spin_cd: float = 0.0
var _air_spin_used: bool = false
var _punch_n: int = 0
var _punch_t: float = 0.0
var _punch_hit: bool = false
var _punch_queue: bool = false
var _combo_t: float = 0.0
var _atk_held: float = 0.0
var _charge: float = 0.0
var _hit_ids: Dictionary = {}
var _inv: float = 0.0
var _lock: float = 0.0
var _boost_t: float = 0.0
var _boost_dir := Vector3.ZERO
var _boost_spd: float = 0.0
var _low_g_t: float = 0.0
var _lift_t: float = 0.0
var _lift_spd: float = 0.0
var _conv_t: float = 0.0
var _conv_vel := Vector3.ZERO
var _wind_t: float = 0.0
var _wind := Vector3.ZERO
var _on_ice: bool = false
var _was_floor: bool = false
var _face_yaw: float = 0.0
var _step_t: float = 0.0
var _reserve: bool = false
var _reserve_t: float = 0.0
var _beep_t: float = 0.0
var _low_warned: bool = false
var _bat_emit_t: float = 0.0
var _shutting_down: bool = false
var _shadow: MeshInstance3D
var _shadow_mat: ShaderMaterial
var _ray: RayCast3D
var _trail: Fx.Trail3D
var _charge_ps: CPUParticles3D


func _ready() -> void:
	add_to_group("player")
	collision_layer = 2
	collision_mask = 1
	floor_snap_length = 0.45
	floor_max_angle = deg_to_rad(52.0)
	floor_stop_on_slope = true
	max_slides = 6
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.38
	cap.height = 1.05
	cs.shape = cap
	cs.position = Vector3(0.0, 0.525, 0.0)
	add_child(cs)
	model = RobotModel.make(Color(0.25, 0.9, 1.0))
	add_child(model)
	_build_fx()


func _build_fx() -> void:
	_ray = RayCast3D.new()
	_ray.target_position = Vector3(0.0, -90.0, 0.0)
	_ray.collision_mask = 1
	_ray.position = Vector3(0.0, 0.4, 0.0)
	add_child(_ray)
	_shadow = MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(1.9, 1.9)
	_shadow.mesh = pm
	_shadow_mat = ShaderMaterial.new()
	_shadow_mat.shader = Mats.shader("res://shaders/blob_shadow.gdshader")
	_shadow.material_override = _shadow_mat
	_shadow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_shadow.top_level = true
	add_child(_shadow)
	_trail = Fx.Trail3D.new()
	_trail.target = self
	_trail.offset = Vector3(0.0, 0.55, 0.0)
	_trail.width = 0.7
	_trail.life = 0.3
	add_child(_trail)
	_charge_ps = CPUParticles3D.new()
	_charge_ps.mesh = Fx.quad()
	_charge_ps.amount = 24
	_charge_ps.lifetime = 0.5
	_charge_ps.emitting = false
	_charge_ps.local_coords = true
	_charge_ps.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	_charge_ps.emission_sphere_radius = 1.2
	_charge_ps.radial_accel_min = -9.0
	_charge_ps.radial_accel_max = -6.0
	_charge_ps.gravity = Vector3.ZERO
	_charge_ps.scale_amount_min = 0.08
	_charge_ps.scale_amount_max = 0.16
	_charge_ps.scale_amount_curve = Fx.shrink_curve()
	_charge_ps.color = Color(0.5, 0.95, 1.0, 0.9)
	_charge_ps.position = Vector3(0.0, 0.6, 0.0)
	add_child(_charge_ps)


func _exit_tree() -> void:
	Sfx.loop_stop("hover")


# ------------------------------------------------------------------ main loop
func _physics_process(delta: float) -> void:
	if not alive:
		return
	if frozen:
		velocity = Vector3.ZERO
		_set_hover_loop(false)
		_sync_model(true, 0.0, Vector3.ZERO)
		return
	var on_floor: bool = is_on_floor()
	_tick(delta, on_floor)

	var can_ctrl: bool = controls_enabled and _lock <= 0.0 and not _shutting_down
	var iv := Vector2.ZERO
	if can_ctrl:
		iv = Input.get_vector("move_left", "move_right", "move_forward", "move_back", 0.05)
	var fwd := Vector3(-sin(cam_yaw), 0.0, -cos(cam_yaw))
	var right := Vector3(cos(cam_yaw), 0.0, -sin(cam_yaw))
	var dir: Vector3 = right * iv.x + fwd * (-iv.y)
	var mag: float = minf(dir.length(), 1.0)
	var spd_mul: float = 0.62 if _reserve else 1.0
	if _punch_n > 0 and on_floor:
		spd_mul *= 0.35
	if _charge > 0.0:
		spd_mul *= 0.25

	if can_ctrl:
		_handle_attack_input(on_floor, dir, mag)
		if Input.is_action_just_pressed("dash") and _dash_t <= 0.0 and _can_dash and _dash_cd <= 0.0 and not _reserve:
			_start_dash(dir, mag)

	# ---- horizontal velocity
	var hv := Vector3(velocity.x, 0.0, velocity.z) - _wind_part()
	if _dash_t > 0.0:
		hv = _dash_dir * DASH_SPEED
	else:
		var target: Vector3 = dir * RUN_SPEED * spd_mul
		var ac: float = ACCEL if on_floor else AIR_ACCEL
		if not can_ctrl:
			target = Vector3.ZERO
			ac = 5.0 if _lock > 0.0 else 40.0
		elif _boost_t > 0.0:
			target = _boost_dir * _boost_spd + dir * 2.5
			ac = 36.0
		elif mag <= 0.05:
			ac = FRICTION if on_floor else AIR_FRICTION
		if on_floor and _on_ice:
			ac *= 0.13 if mag > 0.05 else 0.035
		if on_floor and _conv_t > 0.0:
			target += _conv_vel
		if _hovering:
			ac *= 1.2
		hv = hv.move_toward(target, ac * delta)

	# ---- vertical velocity
	var vy: float = velocity.y
	if _dash_t > 0.0:
		vy = 0.0
	else:
		if _jump_buf > 0.0 and can_ctrl:
			if _coyote > 0.0:
				vy = JUMP_VEL * (0.88 if _reserve else 1.0)
				_start_jump("jump")
			elif _air_jumps > 0 and not on_floor and not _reserve:
				vy = DOUBLE_JUMP_VEL
				_air_jumps -= 1
				_start_jump("double")
			elif _hover_fuel > 0.05 and not on_floor and not _hovering and not _reserve:
				_hovering = true
				_jump_held = true
				_jump_buf = 0.0
		elif not _hovering and _jump_held and _air_jumps <= 0 and not on_floor and vy < -1.0 and _hover_fuel > 0.05 and can_ctrl and not _reserve:
			_hovering = true
		var g: float = GRAVITY
		if vy < 0.0:
			g *= FALL_MULT
		if _low_g_t > 0.0:
			g *= 0.28
		if _spin_t > 0.0 and not on_floor and vy < 0.0:
			g *= 0.55
		if on_floor and vy <= 0.0:
			vy = 0.0
		else:
			vy -= g * delta
		if not _jump_cut_done and vy > 0.0 and not Input.is_action_pressed("jump"):
			vy *= JUMP_CUT
			_jump_cut_done = true
		if vy <= 0.0:
			_jump_cut_done = true
		if _hovering:
			if Input.is_action_pressed("jump") and _hover_fuel > 0.0 and can_ctrl and not _reserve:
				_hover_fuel = maxf(_hover_fuel - delta, 0.0)
				_hover_cont += delta
				drain(DRAIN_HOVER * delta * (1.0 + minf(_hover_cont, 1.2) * 0.5))
				var tv: float = lerpf(-1.9, 1.3, _hover_fuel / HOVER_TIME)
				vy = move_toward(vy, tv, HOVER_ACCEL * delta)
				_laser_t -= delta
				if _laser_t <= 0.0:
					_laser_t = 0.08
					_laser_scan()
			else:
				_hovering = false
				_hover_cont = 0.0
		if _lift_t > 0.0:
			vy = move_toward(vy, _lift_spd, 70.0 * delta)
			_hover_fuel = HOVER_TIME
			_air_jumps = 1
		var vmin: float = -MAX_FALL * (0.3 if _low_g_t > 0.0 else 1.0)
		vy = maxf(vy, vmin)
	_set_hover_loop(_hovering)

	# ---- move
	var pre_vy: float = vy
	var wind: Vector3 = _wind_part()
	velocity = Vector3(hv.x + wind.x, vy, hv.z + wind.z)
	move_and_slide()
	_read_floor()
	var now_floor: bool = is_on_floor()
	if now_floor and not _was_floor:
		_on_land(-pre_vy)
	_was_floor = now_floor

	# ---- battery drain from movement
	var spd: float = Vector3(hv.x, 0.0, hv.z).length()
	if now_floor and mag > 0.05:
		drain(DRAIN_MOVE * delta * clampf(spd / RUN_SPEED, 0.0, 1.0))

	# ---- attacks
	_tick_attacks(delta, now_floor)
	if _dash_t > 0.0:
		_dash_t -= delta
		_hit_scan(global_position + Vector3(0.0, 0.6, 0.0), 1.4, "dash")
		if _dash_t <= 0.0:
			_end_dash()
	_kick_debris(spd)

	# ---- visuals
	if _dash_t > 0.0:
		_face_yaw = lerp_angle(_face_yaw, atan2(-_dash_dir.x, -_dash_dir.z), 1.0 - exp(-30.0 * delta))
	elif mag > 0.1 and can_ctrl and _charge <= 0.0:
		var turn_k: float = 20.0 if _punch_n == 0 else 6.0
		_face_yaw = lerp_angle(_face_yaw, atan2(-dir.x, -dir.z), 1.0 - exp(-turn_k * delta))
	model.rotation.y = _face_yaw
	_sync_model(now_floor, spd, hv)
	if now_floor and spd > 2.5:
		_step_t -= delta * (spd / RUN_SPEED)
		if _step_t <= 0.0:
			_step_t = 0.27
			Sfx.play("step", -10.0, randf_range(0.9, 1.15))
			if Game.quality() >= 1:
				var dust: Color = Color(0.85, 0.92, 1.0, 0.45) if not _on_ice else Color(0.9, 0.97, 1.0, 0.7)
				Fx.burst(get_parent(), global_position + Vector3(0.0, 0.05, 0.0), dust, 3, 1.4, 0.3, 0.4, 0.0, 70.0)
	if _hovering and randf() < 0.5:
		Fx.burst(get_parent(), global_position + Vector3(0.0, -0.4, 0.0), Color(0.5, 0.9, 1.0, 0.8), 2, 3.0, 0.3, 0.35, -2.0, 25.0, Vector3.DOWN)
	_update_shadow()


func _sync_model(now_floor: bool, spd: float, _hv: Vector3) -> void:
	model.speed_ratio = spd / RUN_SPEED
	model.grounded = now_floor or frozen
	model.vy = velocity.y if not frozen else 0.0
	model.velocity = velocity
	model.spinning = _spin_t > 0.0
	model.spin_big = _spin_big
	model.hovering = _hovering
	model.dashing = _dash_t > 0.0
	model.charging = _charge
	model.punch = _punch_n
	model.punch_t = 1.0 - _punch_t / float(PUNCH_TIME[_punch_n]) if _punch_n > 0 else 0.0
	model.flicker = _inv > 0.0 and not frozen
	model.battery_level = battery / BAT_MAX
	model.battery_blink = battery < LOW_BAT
	model.low_power = 1.0 if _reserve else clampf((12.0 - battery) / 12.0, 0.0, 0.5)


func _tick(delta: float, on_floor: bool) -> void:
	_inv = maxf(_inv - delta, 0.0)
	_lock = maxf(_lock - delta, 0.0)
	_spin_cd = maxf(_spin_cd - delta, 0.0)
	_dash_cd = maxf(_dash_cd - delta, 0.0)
	_boost_t = maxf(_boost_t - delta, 0.0)
	_low_g_t = maxf(_low_g_t - delta, 0.0)
	_lift_t = maxf(_lift_t - delta, 0.0)
	_conv_t = maxf(_conv_t - delta, 0.0)
	_wind_t = maxf(_wind_t - delta, 0.0)
	_combo_t = maxf(_combo_t - delta, 0.0)
	if on_floor:
		_coyote = COYOTE
		_air_jumps = 1
		_hover_fuel = HOVER_TIME
		_hovering = false
		_hover_cont = 0.0
		_air_spin_used = false
		if _dash_cd <= 0.0:
			_can_dash = true
	else:
		_coyote = maxf(_coyote - delta, 0.0)
	if controls_enabled and Input.is_action_just_pressed("jump"):
		_jump_buf = JUMP_BUFFER
	else:
		_jump_buf = maxf(_jump_buf - delta, 0.0)
	if not Input.is_action_pressed("jump"):
		_jump_held = false
	_tick_battery(delta)


# ------------------------------------------------------------------ battery
func drain(amount: float) -> void:
	if god_mode or amount <= 0.0 or not alive:
		return
	var before: float = battery
	battery = maxf(battery - amount, 0.0)
	if battery < LOW_BAT and before >= LOW_BAT and not _low_warned:
		_low_warned = true
		if world != null:
			world.toast("البطارية ضعيفة! ابحث عن بطارية جديدة", Color(1.0, 0.55, 0.2))
		Sfx.play("battery_low", -2.0)
	_emit_battery()


func set_battery(v: float) -> void:
	battery = clampf(v, 0.0, BAT_MAX)
	if battery >= LOW_BAT:
		_low_warned = false
	if battery > 0.0 and _reserve:
		_reserve = false
		reserve_changed.emit(false, 0.0)
	_emit_battery()


func _emit_battery() -> void:
	_bat_emit_t = 0.0
	battery_changed.emit(battery, BAT_MAX)


func battery_ratio() -> float:
	return battery / BAT_MAX


func _tick_battery(delta: float) -> void:
	if battery <= 0.0 and not _reserve and alive and not _shutting_down:
		_reserve = true
		_reserve_t = RESERVE_TIME
		_hovering = false
		_charge = 0.0
		Sfx.play("power_down", -1.0)
		if world != null:
			world.toast("نفدت البطارية! وضع الطاقة الاحتياطية", Color(1.0, 0.3, 0.25))
		Game.vibrate(80)
	if _reserve:
		_reserve_t -= delta
		reserve_changed.emit(true, maxf(_reserve_t, 0.0))
		_beep_t -= delta
		if _beep_t <= 0.0:
			_beep_t = 0.35 if _reserve_t < 3.0 else 0.9
			Sfx.play("battery_low", -6.0, 1.3 if _reserve_t < 3.0 else 1.0)
		if _reserve_t <= 0.0 and not _shutting_down:
			shutdown()
	elif battery < LOW_BAT:
		_beep_t -= delta
		if _beep_t <= 0.0:
			_beep_t = 2.2 if battery > 10.0 else 1.2
			Sfx.play("battery_low", -14.0, 0.9)


## Battery ran flat: the robot sits down and powers off, then warps back to the checkpoint.
func shutdown() -> void:
	if _shutting_down or not alive:
		return
	_shutting_down = true
	_hovering = false
	_spin_t = 0.0
	_punch_n = 0
	model.pose_override = "shutdown"
	Sfx.play("shutdown")
	Game.vibrate(120)
	if world != null:
		world.toast("توقّف الروبوت عن العمل...", Color(1.0, 0.35, 0.3))
	var tw := create_tween()
	tw.tween_interval(1.7)
	tw.tween_callback(_finish_shutdown)


func _finish_shutdown() -> void:
	_shutting_down = false
	model.pose_override = ""
	battery = 0.0
	die()


func is_reserve() -> bool:
	return _reserve


func reserve_left() -> float:
	return _reserve_t


# ------------------------------------------------------------------ attacks
func _handle_attack_input(on_floor: bool, dir: Vector3, mag: float) -> void:
	var pressed: bool = Input.is_action_just_pressed("attack")
	var held: bool = Input.is_action_pressed("attack")
	if _dash_t > 0.0:
		return
	if pressed:
		_atk_held = 0.0
		if not on_floor:
			if _spin_t <= 0.0 and _spin_cd <= 0.0 and not _reserve:
				_start_spin(false, false)
		elif _punch_n > 0:
			_punch_queue = true
		elif _spin_t <= 0.0:
			var next: int = 1
			if _combo_t > 0.0:
				next = clampi(_last_punch + 1, 1, 3)
			_start_punch(next, dir, mag)
	if held and on_floor and not _reserve and _spin_t <= 0.0:
		_atk_held += get_physics_process_delta_time()
		if _atk_held > 0.32 and _punch_n == 0:
			if _charge <= 0.0:
				Sfx.play("charge", -4.0)
			_charge = minf(_charge + get_physics_process_delta_time() / CHARGE_TIME, 1.0)
			_charge_ps.emitting = true
	elif _charge > 0.0:
		var c: float = _charge
		_charge = 0.0
		_charge_ps.emitting = false
		if c >= 0.4 and on_floor:
			_start_spin(true, true)
	if not held:
		_atk_held = 0.0
		if _charge <= 0.0:
			_charge_ps.emitting = false


var _last_punch: int = 0


func _start_punch(n: int, dir: Vector3, mag: float) -> void:
	_punch_n = n
	_last_punch = n
	_punch_t = float(PUNCH_TIME[n])
	_punch_hit = false
	_punch_queue = false
	_hit_ids.clear()
	if mag > 0.2:
		_face_yaw = atan2(-dir.x, -dir.z)
	drain(DRAIN_PUNCH * (1.5 if n == 3 else 1.0))
	Sfx.play("punch_swing", -3.0, randf_range(0.95, 1.1) * (0.85 if n == 3 else 1.0))
	model.set_trails(true)


func _tick_attacks(delta: float, on_floor: bool) -> void:
	if _punch_n > 0:
		_punch_t -= delta
		var dur: float = float(PUNCH_TIME[_punch_n])
		var u: float = 1.0 - _punch_t / dur
		var fwd := Vector3(-sin(_face_yaw), 0.0, -cos(_face_yaw))
		if u > 0.18 and u < 0.3 and on_floor:
			var lunge: float = 7.0 if _punch_n == 3 else 4.5
			velocity.x = fwd.x * lunge
			velocity.z = fwd.z * lunge
		if _punch_n == 3 and u > 0.2 and u < 0.26 and on_floor:
			velocity.y = 6.5
		if u > 0.2 and u < 0.62:
			var reach: float = PUNCH_REACH + (0.35 if _punch_n == 3 else 0.0)
			var c: Vector3 = global_position + Vector3(0.0, 0.55, 0.0) + fwd * 0.5
			var n: int = _hit_scan(c, reach, "punch3" if _punch_n == 3 else "punch", fwd, 0.15)
			if n > 0 and not _punch_hit:
				_punch_hit = true
		if _punch_t <= 0.0:
			var was: int = _punch_n
			_punch_n = 0
			model.set_trails(false)
			_combo_t = 0.38 if was < 3 else 0.0
			if was == 3:
				_last_punch = 0
			if _punch_queue and was < 3 and on_floor:
				var iv: Vector2 = Input.get_vector("move_left", "move_right", "move_forward", "move_back", 0.05)
				var f := Vector3(-sin(cam_yaw), 0.0, -cos(cam_yaw))
				var r := Vector3(cos(cam_yaw), 0.0, -sin(cam_yaw))
				var d: Vector3 = r * iv.x + f * (-iv.y)
				_start_punch(was + 1, d, d.length())
	if _spin_t > 0.0:
		_spin_t -= delta
		var reach2: float = SPIN_BIG_REACH if _spin_big else SPIN_REACH
		_hit_scan(global_position + Vector3(0.0, 0.6, 0.0), reach2, "spin_big" if _spin_big else "spin")
		if _spin_t <= 0.0:
			_spin_cd = SPIN_CD
			_spin_big = false


func _start_spin(on_floor: bool, big: bool) -> void:
	_spin_t = SPIN_BIG_TIME if big else SPIN_TIME
	_spin_big = big
	_punch_n = 0
	model.set_trails(false)
	_hit_ids.clear()
	drain(DRAIN_SPIN_BIG if big else DRAIN_SPIN)
	Sfx.play("spin", -1.0 if big else -2.0, randf_range(0.95, 1.08) * (0.8 if big else 1.0))
	if big:
		Game.vibrate(35)
		var p: Node = get_parent()
		Fx.ring(p, global_position + Vector3(0.0, 0.2, 0.0), Color(0.5, 0.95, 1.0), SPIN_BIG_REACH * 2.4, 0.45, 3.0)
		Fx.burst(p, global_position + Vector3(0.0, 0.5, 0.0), Color(0.6, 0.95, 1.0, 0.9), 22, 9.0, 0.3, 0.5, 0.0, 90.0, Vector3.UP)
		if world != null:
			world.shake(0.3)
	if not on_floor and not _air_spin_used:
		_air_spin_used = true
		velocity.y = maxf(velocity.y, 3.2)


func _start_dash(dir: Vector3, mag: float) -> void:
	var d: Vector3 = dir
	if mag < 0.2:
		d = Vector3(-sin(_face_yaw), 0.0, -cos(_face_yaw))
	d.y = 0.0
	_dash_dir = d.normalized()
	_dash_t = DASH_TIME
	_can_dash = false
	_dash_cd = DASH_CD
	_hit_ids.clear()
	_hovering = false
	_punch_n = 0
	_charge = 0.0
	_trail.emitting = true
	drain(DRAIN_DASH)
	Sfx.play("dash", -2.0)
	Game.vibrate(15)
	var p: Node = get_parent()
	Fx.ring(p, global_position + Vector3(0.0, 0.3, 0.0), Color(1.0, 0.85, 0.3), 2.6, 0.35, 2.4)
	Fx.burst(p, global_position + Vector3(0.0, 0.5, 0.0), Color(1.0, 0.85, 0.4, 0.9), 8, 4.0, 0.3, 0.4, 0.0, 60.0, -_dash_dir)


func _end_dash() -> void:
	_trail.emitting = false
	velocity = _dash_dir * 12.0


## Hits every "hittable" within reach of `c` (optionally inside a cone around `cone`). Returns the number hit.
func _hit_scan(c: Vector3, reach: float, kind: String, cone: Vector3 = Vector3.ZERO, min_dot: float = -2.0) -> int:
	var hits: int = 0
	for n in get_tree().get_nodes_in_group("hittable"):
		var node: Node3D = n as Node3D
		if node == null or not is_instance_valid(node) or not node.is_inside_tree():
			continue
		var id: int = node.get_instance_id()
		if _hit_ids.has(id):
			continue
		var hrv: Variant = node.get("hit_radius")
		var hr: float = 0.6 if hrv == null else float(hrv)
		var hov: Variant = node.get("hit_offset")
		var tp: Vector3 = node.global_position + (Vector3.ZERO if hov == null else (hov as Vector3))
		var d: Vector3 = tp - c
		if absf(d.y) > 1.6 + hr * 0.6:
			continue
		var flat := Vector3(d.x, 0.0, d.z)
		if flat.length() > reach + hr:
			continue
		if min_dot > -1.5 and flat.length() > hr + 0.2:
			if flat.normalized().dot(cone) < min_dot:
				continue
		_hit_ids[id] = true
		if bool(node.call("hit", self, kind)):
			hits += 1
			_impact(tp.lerp(c, 0.35), kind)
	return hits


func _impact(at: Vector3, kind: String) -> void:
	var heavy: bool = kind == "punch3" or kind == "spin_big" or kind == "stomp"
	Game.vibrate(35 if heavy else 22)
	var p: Node = get_parent()
	Fx.burst(p, at, Color(1.0, 0.95, 0.7, 1.0), 10 if heavy else 6, 7.0, 0.35, 0.25, 0.0)
	Fx.ring(p, at, Color(1.0, 0.9, 0.6), 2.6 if heavy else 1.8, 0.22, 3.5)
	Sfx.play("punch_hit", -1.0, randf_range(0.9, 1.05) * (0.85 if heavy else 1.0))
	if world != null:
		world.hitstop(0.085 if heavy else 0.055)
		world.shake(0.32 if heavy else 0.2)


func _laser_scan() -> void:
	var feet: Vector3 = global_position
	for n in get_tree().get_nodes_in_group("enemy"):
		var node: Node3D = n as Node3D
		if node == null or not is_instance_valid(node) or not node.is_inside_tree() or not node.is_in_group("hittable"):
			continue
		var hrv: Variant = node.get("hit_radius")
		var hr: float = 0.6 if hrv == null else float(hrv)
		var d: Vector3 = node.global_position - feet
		if d.y > 0.4 or d.y < -4.5:
			continue
		if Vector2(d.x, d.z).length() > 0.7 + hr * 0.6:
			continue
		if bool(node.call("hit", self, "laser")):
			Fx.burst(get_parent(), node.global_position, Color(0.5, 0.95, 1.0), 8, 5.0, 0.3, 0.3)


## Push loose physics debris around when running / dashing through it.
func _kick_debris(spd: float) -> void:
	if spd < 1.5 and _spin_t <= 0.0:
		return
	var c: Vector3 = global_position + Vector3(0.0, 0.3, 0.0)
	var r: float = 0.85 if _spin_t <= 0.0 else 2.0
	for n in get_tree().get_nodes_in_group("debris"):
		var rb: RigidBody3D = n as RigidBody3D
		if rb == null or not is_instance_valid(rb):
			continue
		var d: Vector3 = rb.global_position - c
		if d.length() > r:
			continue
		var push: Vector3 = Vector3(velocity.x, 0.0, velocity.z) * 0.12
		if _spin_t > 0.0:
			push += Vector3(d.x, 0.0, d.z).normalized() * 2.5
		push.y = 1.2 + spd * 0.08
		rb.apply_central_impulse(push * rb.mass)


func _on_land(impact: float) -> void:
	landed.emit(impact)
	if impact < 5.0:
		return
	var p: Node = get_parent()
	Sfx.play("land", clampf(-14.0 + impact * 0.6, -14.0, -2.0))
	Fx.burst(p, global_position + Vector3(0.0, 0.05, 0.0), Color(0.85, 0.92, 1.0, 0.7), 6 + int(impact * 0.3), 3.0 + impact * 0.15, 0.4, 0.45, 0.0, 85.0)
	if impact > 16.0:
		Fx.ring(p, global_position, Color(0.5, 0.9, 1.0), 3.0, 0.4, 2.0)
		Game.vibrate(20)
		if world != null:
			world.shake(0.15)


func _read_floor() -> void:
	_on_ice = false
	if not is_on_floor():
		return
	for i in range(get_slide_collision_count()):
		var col: KinematicCollision3D = get_slide_collision(i)
		if col.get_normal().y > 0.6:
			var o: Object = col.get_collider()
			if o != null and o.has_meta("ice"):
				_on_ice = true
				return


func _wind_part() -> Vector3:
	if _wind_t <= 0.0:
		return Vector3.ZERO
	return _wind


# ------------------------------------------------------------------ jumps
func _start_jump(kind: String) -> void:
	_jump_buf = 0.0
	_coyote = 0.0
	_jump_cut_done = false
	_jump_held = true
	_hovering = false
	_punch_n = 0
	_charge = 0.0
	model.set_trails(false)
	var p: Node = get_parent()
	if kind == "double":
		drain(DRAIN_DOUBLE)
		model.trigger_flip(1.0)
		Sfx.play("double_jump", -2.0)
		Fx.ring(p, global_position + Vector3(0.0, 0.15, 0.0), Color(0.5, 0.9, 1.0), 2.4, 0.4, 2.5)
		Fx.burst(p, global_position + Vector3(0.0, 0.1, 0.0), Color(0.5, 0.9, 1.0, 0.9), 8, 3.5, 0.3, 0.5, 0.0, 90.0, Vector3.DOWN)
	else:
		drain(DRAIN_JUMP)
		Sfx.play("jump", -3.0, randf_range(0.95, 1.08))
		Fx.burst(p, global_position + Vector3(0.0, 0.05, 0.0), Color(0.85, 0.92, 1.0, 0.6), 5, 2.5, 0.35, 0.4, 0.0, 80.0)
	jumped.emit(kind)


func _set_hover_loop(on: bool) -> void:
	if on == _hover_loop:
		return
	_hover_loop = on
	if on:
		Sfx.loop_start("hover", -8.0)
	else:
		Sfx.loop_stop("hover")


func _update_shadow() -> void:
	_ray.force_raycast_update()
	if _ray.is_colliding() and alive:
		var hit: Vector3 = _ray.get_collision_point()
		var h: float = maxf(global_position.y - hit.y, 0.0)
		_shadow.visible = true
		_shadow.global_position = Vector3(global_position.x, hit.y + 0.03, global_position.z)
		var s: float = clampf(1.0 - h / 26.0, 0.3, 1.0)
		_shadow.scale = Vector3(s, 1.0, s)
		_shadow_mat.set_shader_parameter("strength", 0.6 * s)
		_shadow_mat.set_shader_parameter("ring", clampf((h - 1.2) / 3.0, 0.0, 0.85))
	else:
		_shadow.visible = false


# -------------------------------------------------------------------- API
func bounce(power: float) -> void:
	velocity.y = power
	_jump_cut_done = true
	_air_jumps = 1
	_hover_fuel = HOVER_TIME
	_can_dash = true
	_hovering = false
	_coyote = 0.0


func stomp_bounce() -> void:
	bounce(JUMP_VEL * 0.95)
	_impact(global_position, "stomp")


func launch(v: Vector3) -> void:
	velocity = v
	_jump_cut_done = true
	_hovering = false
	_lock = maxf(_lock, 0.18)
	_coyote = 0.0


func boost(dir: Vector3, spd: float, time: float = 0.9) -> void:
	if _boost_t <= 0.0:
		Sfx.play("whoosh", -2.0)
		Game.vibrate(20)
	_boost_dir = Vector3(dir.x, 0.0, dir.z).normalized()
	_boost_spd = spd
	_boost_t = time


func mark_low_g() -> void:
	_low_g_t = 0.12


func mark_lift(spd: float) -> void:
	_lift_t = 0.12
	_lift_spd = spd


func mark_conveyor(v: Vector3) -> void:
	_conv_t = 0.12
	_conv_vel = v


## Moving air (wind gusts): added on top of the player's own velocity while inside the zone.
func mark_wind(v: Vector3) -> void:
	_wind_t = 0.1
	_wind = Vector3(v.x, 0.0, v.z)


func hurt(from: Vector3, dmg: int = 1) -> bool:
	if not alive or _inv > 0.0 or _dash_t > 0.0 or frozen or _shutting_down:
		return false
	if god_mode:
		return false
	hp = maxi(hp - dmg, 0)
	hp_changed.emit(hp, max_hp)
	damaged.emit()
	var away: Vector3 = global_position - from
	away.y = 0.0
	if away.length() < 0.05:
		away = Vector3(sin(_face_yaw), 0.0, cos(_face_yaw))
	away = away.normalized()
	velocity = away * 7.5 + Vector3(0.0, 8.0, 0.0)
	_lock = HURT_LOCK
	_inv = INVULN
	_hovering = false
	_spin_t = 0.0
	_punch_n = 0
	_charge = 0.0
	model.on_hurt()
	Sfx.play("hurt")
	Game.vibrate(70)
	Fx.burst(get_parent(), global_position + Vector3(0.0, 0.6, 0.0), Color(1.0, 0.45, 0.5), 12, 6.0, 0.35, 0.5)
	if world != null:
		world.shake(0.5)
	if hp <= 0:
		die()
	return true


func heal(n: int) -> void:
	hp = mini(hp + n, max_hp)
	hp_changed.emit(hp, max_hp)


func kill() -> void:
	if god_mode:
		return
	die()


func die() -> void:
	if not alive:
		return
	alive = false
	_set_hover_loop(false)
	model.shown = false
	_trail.emitting = false
	_shadow.visible = false
	_charge_ps.emitting = false
	model.set_trails(false)
	var p: Node = get_parent()
	Fx.burst(p, global_position + Vector3(0.0, 0.6, 0.0), Color(0.4, 0.95, 1.0), 28, 9.0, 0.45, 0.9, -4.0)
	Fx.ring(p, global_position + Vector3(0.0, 0.5, 0.0), Color(1.0, 0.4, 0.6), 4.0, 0.6)
	Debris.robot_parts(p, global_position, velocity)
	Sfx.play("die")
	Game.vibrate(140)
	died.emit()


func respawn(pos: Vector3, yaw: float) -> void:
	global_position = pos
	velocity = Vector3.ZERO
	alive = true
	frozen = false
	hp = max_hp
	_inv = 1.6
	_lock = 0.0
	_dash_t = 0.0
	_spin_t = 0.0
	_punch_n = 0
	_charge = 0.0
	_boost_t = 0.0
	_hovering = false
	_was_floor = false
	_face_yaw = yaw
	_hover_fuel = HOVER_TIME
	_can_dash = true
	_air_jumps = 1
	_shutting_down = false
	_reserve = false
	reserve_changed.emit(false, 0.0)
	battery = maxf(battery, RESPAWN_CHARGE)
	_low_warned = battery < LOW_BAT
	_emit_battery()
	model.shown = true
	model.pose_override = ""
	model.rotation.y = yaw
	hp_changed.emit(hp, max_hp)
	Fx.ring(get_parent(), pos, Color(0.3, 0.9, 1.0), 3.5, 0.6)
	Sfx.play("warp")


func celebrate() -> void:
	controls_enabled = false
	model.celebrate = true
	velocity.y = 8.0
	_jump_cut_done = true


func face_yaw() -> float:
	return _face_yaw


func set_face_yaw(y: float) -> void:
	_face_yaw = y
	model.rotation.y = y


func is_dashing() -> bool:
	return _dash_t > 0.0


func is_spinning() -> bool:
	return _spin_t > 0.0


func is_attacking() -> bool:
	return _spin_t > 0.0 or (_punch_n > 0 and _punch_t < float(PUNCH_TIME[_punch_n]) * 0.8)


func deflect_radius() -> float:
	if _spin_t > 0.0:
		return SPIN_BIG_REACH if _spin_big else 2.3
	if _punch_n > 0:
		return 1.7
	return 0.0


func charge_ratio() -> float:
	return _charge


func hover_ratio() -> float:
	return clampf(_hover_fuel / HOVER_TIME, 0.0, 1.0)


func dash_ratio() -> float:
	if not _can_dash:
		return 0.0
	return clampf(1.0 - _dash_cd / DASH_CD, 0.0, 1.0)
