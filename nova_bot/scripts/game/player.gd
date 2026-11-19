class_name Player
extends CharacterBody3D
## Third-person platformer hero: camera-relative run, coyote + buffered jump, variable height,
## double jump, hover jets, spin attack, air dash, hurt / die / respawn.
## Origin is at the feet. Heading convention: model yaw = atan2(-dir.x, -dir.z).

signal hp_changed(hp: int, max_hp: int)
signal died
signal damaged
signal landed(impact: float)
signal jumped(kind: String)

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
const SPIN_CD := 0.25
const SPIN_REACH := 2.1
const DASH_TIME := 0.2
const DASH_SPEED := 22.0
const DASH_CD := 0.55
const INVULN := 1.6
const HURT_LOCK := 0.35

var world: Node = null
var model: RobotModel
var cam_yaw: float = 0.0
var hp: int = 3
var max_hp: int = 3
var alive: bool = true
var controls_enabled: bool = true

var _coyote: float = 0.0
var _jump_buf: float = 0.0
var _air_jumps: int = 1
var _hover_fuel: float = HOVER_TIME
var _hovering: bool = false
var _hover_loop: bool = false
var _jump_cut_done: bool = true
var _jump_held: bool = false
var _can_dash: bool = true
var _dash_t: float = 0.0
var _dash_cd: float = 0.0
var _dash_dir := Vector3(0.0, 0.0, -1.0)
var _spin_t: float = 0.0
var _spin_cd: float = 0.0
var _air_spin_used: bool = false
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
var _was_floor: bool = false
var _face_yaw: float = 0.0
var _step_t: float = 0.0
var _shadow: MeshInstance3D
var _shadow_mat: ShaderMaterial
var _ray: RayCast3D
var _trail: Fx.Trail3D


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


func _exit_tree() -> void:
	Sfx.loop_stop("hover")


# ------------------------------------------------------------------ main loop
func _physics_process(delta: float) -> void:
	if not alive:
		return
	var on_floor: bool = is_on_floor()
	_tick(delta, on_floor)

	var can_ctrl: bool = controls_enabled and _lock <= 0.0
	var iv := Vector2.ZERO
	if can_ctrl:
		iv = Input.get_vector("move_left", "move_right", "move_forward", "move_back", 0.05)
	var fwd := Vector3(-sin(cam_yaw), 0.0, -cos(cam_yaw))
	var right := Vector3(cos(cam_yaw), 0.0, -sin(cam_yaw))
	var dir: Vector3 = right * iv.x + fwd * (-iv.y)
	var mag: float = minf(dir.length(), 1.0)

	if can_ctrl:
		if Input.is_action_just_pressed("spin") and _spin_t <= 0.0 and _spin_cd <= 0.0 and _dash_t <= 0.0:
			_start_spin(on_floor)
		if Input.is_action_just_pressed("dash") and _dash_t <= 0.0 and _can_dash and _dash_cd <= 0.0:
			_start_dash(dir, mag)

	# ---- horizontal velocity
	var hv := Vector3(velocity.x, 0.0, velocity.z)
	if _dash_t > 0.0:
		hv = _dash_dir * DASH_SPEED
	else:
		var target: Vector3 = dir * RUN_SPEED
		var ac: float = ACCEL if on_floor else AIR_ACCEL
		if not can_ctrl:
			target = Vector3.ZERO
			ac = 5.0 if _lock > 0.0 else 40.0
		elif _boost_t > 0.0:
			target = _boost_dir * _boost_spd + dir * 2.5
			ac = 36.0
		elif mag <= 0.05:
			ac = FRICTION if on_floor else AIR_FRICTION
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
				vy = JUMP_VEL
				_start_jump("jump")
			elif _air_jumps > 0 and not on_floor:
				vy = DOUBLE_JUMP_VEL
				_air_jumps -= 1
				_start_jump("double")
			elif _hover_fuel > 0.05 and not on_floor and not _hovering:
				_hovering = true
				_jump_held = true
				_jump_buf = 0.0
		elif not _hovering and _jump_held and _air_jumps <= 0 and not on_floor and vy < -1.0 and _hover_fuel > 0.05 and can_ctrl:
			_hovering = true   # keep holding jump after the double jump to glide automatically
		var g: float = GRAVITY
		if vy < 0.0:
			g *= FALL_MULT
		if _low_g_t > 0.0:
			g *= 0.28
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
			if Input.is_action_pressed("jump") and _hover_fuel > 0.0 and can_ctrl:
				_hover_fuel = maxf(_hover_fuel - delta, 0.0)
				var tv: float = lerpf(-1.9, 1.3, _hover_fuel / HOVER_TIME)
				vy = move_toward(vy, tv, HOVER_ACCEL * delta)
			else:
				_hovering = false
		if _lift_t > 0.0:
			vy = move_toward(vy, _lift_spd, 70.0 * delta)
			_hover_fuel = HOVER_TIME
			_air_jumps = 1
		var vmin: float = -MAX_FALL * (0.3 if _low_g_t > 0.0 else 1.0)
		vy = maxf(vy, vmin)
	_set_hover_loop(_hovering)

	# ---- move
	var pre_vy: float = vy
	velocity = Vector3(hv.x, vy, hv.z)
	move_and_slide()
	var now_floor: bool = is_on_floor()
	if now_floor and not _was_floor:
		_on_land(-pre_vy)
	_was_floor = now_floor

	# ---- attacks
	if _spin_t > 0.0:
		_spin_t -= delta
		_hit_scan(SPIN_REACH, "spin")
		if _spin_t <= 0.0:
			_spin_cd = SPIN_CD
	if _dash_t > 0.0:
		_dash_t -= delta
		_hit_scan(1.4, "dash")
		if _dash_t <= 0.0:
			_end_dash()

	# ---- visuals
	if _dash_t > 0.0:
		_face_yaw = lerp_angle(_face_yaw, atan2(-_dash_dir.x, -_dash_dir.z), 1.0 - exp(-30.0 * delta))
	elif mag > 0.1 and can_ctrl:
		_face_yaw = lerp_angle(_face_yaw, atan2(-dir.x, -dir.z), 1.0 - exp(-20.0 * delta))
	model.rotation.y = _face_yaw
	var spd: float = Vector3(velocity.x, 0.0, velocity.z).length()
	model.speed_ratio = spd / RUN_SPEED
	model.grounded = now_floor
	model.vy = velocity.y
	model.spinning = _spin_t > 0.0
	model.hovering = _hovering
	model.dashing = _dash_t > 0.0
	model.flicker = _inv > 0.0
	if now_floor and spd > 2.5:
		_step_t -= delta * (spd / RUN_SPEED)
		if _step_t <= 0.0:
			_step_t = 0.27
			Sfx.play("step", -10.0, randf_range(0.9, 1.15))
			if Game.quality() >= 1:
				Fx.burst(get_parent(), global_position + Vector3(0.0, 0.05, 0.0), Color(0.75, 0.88, 1.0, 0.45), 3, 1.4, 0.3, 0.4, 0.0, 70.0)
	if _hovering:
		if randf() < 0.5:
			Fx.burst(get_parent(), global_position + Vector3(0.0, 0.1, 0.0), Color(0.5, 0.9, 1.0, 0.8), 2, 3.0, 0.3, 0.35, -2.0, 25.0, Vector3.DOWN)
	_update_shadow()


func _tick(delta: float, on_floor: bool) -> void:
	_inv = maxf(_inv - delta, 0.0)
	_lock = maxf(_lock - delta, 0.0)
	_spin_cd = maxf(_spin_cd - delta, 0.0)
	_dash_cd = maxf(_dash_cd - delta, 0.0)
	_boost_t = maxf(_boost_t - delta, 0.0)
	_low_g_t = maxf(_low_g_t - delta, 0.0)
	_lift_t = maxf(_lift_t - delta, 0.0)
	_conv_t = maxf(_conv_t - delta, 0.0)
	if on_floor:
		_coyote = COYOTE
		_air_jumps = 1
		_hover_fuel = HOVER_TIME
		_hovering = false
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


# ------------------------------------------------------------------ actions
func _start_jump(kind: String) -> void:
	_jump_buf = 0.0
	_coyote = 0.0
	_jump_cut_done = false
	_jump_held = true
	_hovering = false
	var p: Node = get_parent()
	if kind == "double":
		Sfx.play("double_jump", -2.0)
		Fx.ring(p, global_position + Vector3(0.0, 0.15, 0.0), Color(0.5, 0.9, 1.0), 2.4, 0.4, 2.5)
		Fx.burst(p, global_position + Vector3(0.0, 0.1, 0.0), Color(0.5, 0.9, 1.0, 0.9), 8, 3.5, 0.3, 0.5, 0.0, 90.0, Vector3.DOWN)
	else:
		Sfx.play("jump", -3.0, randf_range(0.95, 1.08))
		Fx.burst(p, global_position + Vector3(0.0, 0.05, 0.0), Color(0.75, 0.9, 1.0, 0.6), 5, 2.5, 0.35, 0.4, 0.0, 80.0)
	jumped.emit(kind)


func _start_spin(on_floor: bool) -> void:
	_spin_t = SPIN_TIME
	_hit_ids.clear()
	Sfx.play("spin", -2.0, randf_range(0.95, 1.08))
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
	_trail.emitting = true
	Sfx.play("dash", -2.0)
	Game.vibrate(15)
	var p: Node = get_parent()
	Fx.ring(p, global_position + Vector3(0.0, 0.3, 0.0), Color(1.0, 0.85, 0.3), 2.6, 0.35, 2.4)
	Fx.burst(p, global_position + Vector3(0.0, 0.5, 0.0), Color(1.0, 0.85, 0.4, 0.9), 8, 4.0, 0.3, 0.4, 0.0, 60.0, -_dash_dir)


func _end_dash() -> void:
	_trail.emitting = false
	velocity = _dash_dir * 12.0


func _hit_scan(reach: float, kind: String) -> void:
	var c: Vector3 = global_position + Vector3(0.0, 0.6, 0.0)
	for n in get_tree().get_nodes_in_group("hittable"):
		var node: Node3D = n as Node3D
		if node == null or not is_instance_valid(node):
			continue
		var id: int = node.get_instance_id()
		if _hit_ids.has(id):
			continue
		var hrv: Variant = node.get("hit_radius")
		var hr: float = 0.6 if hrv == null else float(hrv)
		if c.distance_to(node.global_position) <= reach + hr:
			_hit_ids[id] = true
			if bool(node.call("hit", self, kind)):
				Game.vibrate(25)
				if world != null:
					world.hitstop(0.05)
					world.shake(0.25)


func _on_land(impact: float) -> void:
	landed.emit(impact)
	if impact < 5.0:
		return
	var p: Node = get_parent()
	Sfx.play("land", clampf(-14.0 + impact * 0.6, -14.0, -2.0))
	Fx.burst(p, global_position + Vector3(0.0, 0.05, 0.0), Color(0.75, 0.88, 1.0, 0.7), 6 + int(impact * 0.3), 3.0 + impact * 0.15, 0.4, 0.45, 0.0, 85.0)
	if impact > 16.0:
		Fx.ring(p, global_position, Color(0.5, 0.9, 1.0), 3.0, 0.4, 2.0)
		Game.vibrate(20)
		if world != null:
			world.shake(0.15)


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


func hurt(from: Vector3, dmg: int = 1) -> bool:
	if not alive or _inv > 0.0 or _dash_t > 0.0:
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
	die()


func die() -> void:
	if not alive:
		return
	alive = false
	_set_hover_loop(false)
	model.shown = false
	_trail.emitting = false
	_shadow.visible = false
	var p: Node = get_parent()
	Fx.burst(p, global_position + Vector3(0.0, 0.6, 0.0), Color(0.4, 0.95, 1.0), 28, 9.0, 0.45, 0.9, -4.0)
	Fx.ring(p, global_position + Vector3(0.0, 0.5, 0.0), Color(1.0, 0.4, 0.6), 4.0, 0.6)
	Sfx.play("die")
	Game.vibrate(140)
	died.emit()


func respawn(pos: Vector3, yaw: float) -> void:
	global_position = pos
	velocity = Vector3.ZERO
	alive = true
	hp = max_hp
	_inv = 1.6
	_lock = 0.0
	_dash_t = 0.0
	_spin_t = 0.0
	_boost_t = 0.0
	_hovering = false
	_was_floor = false
	_face_yaw = yaw
	_hover_fuel = HOVER_TIME
	_can_dash = true
	_air_jumps = 1
	model.shown = true
	model.rotation.y = yaw
	hp_changed.emit(hp, max_hp)
	Fx.ring(get_parent(), pos, Color(0.3, 0.9, 1.0), 3.5, 0.6)
	Sfx.play("warp")


func celebrate() -> void:
	controls_enabled = false
	model.wave = true
	velocity.y = 8.0
	_jump_cut_done = true


func is_dashing() -> bool:
	return _dash_t > 0.0


func is_spinning() -> bool:
	return _spin_t > 0.0


func hover_ratio() -> float:
	return clampf(_hover_fuel / HOVER_TIME, 0.0, 1.0)


func dash_ratio() -> float:
	if not _can_dash:
		return 0.0
	return clampf(1.0 - _dash_cd / DASH_CD, 0.0, 1.0)
