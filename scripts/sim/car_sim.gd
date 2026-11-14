class_name CarSim
extends RefCounted
## Car rigid body: raycast suspension, tyre model, jumps, dodges, air control,
## boost and supersonic state. Arena/ball/car collisions are done by SimWorld.

## Body presets: hitbox half extents (x, y, z), hitbox offset, display name.
const BODIES := [
	{"name": "Striker", "half": Vector3(0.42, 0.18, 0.59), "offset": Vector3(0, 0.21, -0.13)},
	{"name": "Bulldog", "half": Vector3(0.43, 0.205, 0.55), "offset": Vector3(0, 0.225, -0.10)},
	{"name": "Viper", "half": Vector3(0.43, 0.16, 0.64), "offset": Vector3(0, 0.20, -0.15)},
]

const WHEEL_CONN := [
	Vector3(-0.37, Phys.SUSP_CONN_Y, -0.50), Vector3(0.37, Phys.SUSP_CONN_Y, -0.50),
	Vector3(-0.37, Phys.SUSP_CONN_Y, 0.36), Vector3(0.37, Phys.SUSP_CONN_Y, 0.36)]
const WHEEL_RADIUS := [0.135, 0.135, 0.155, 0.155]
const INV_I := Vector3(1.0 / 0.25, 1.0 / 0.35, 1.0 / 0.14)

var id := 0
var team := 0
var display_name := ""
var body_type := 0
var is_player := false

var pos := Vector3.ZERO
var vel := Vector3.ZERO
var basis := Basis.IDENTITY
var ang_vel := Vector3.ZERO
var prev_pos := Vector3.ZERO
var prev_quat := Quaternion.IDENTITY

var controls := CarControls.new()
var _prev_jump := false

var boost := Phys.BOOST_KICKOFF
var infinite_boost := false
var boosting := false
var _boost_timer := 0.0

var half_ext := Vector3(0.42, 0.18, 0.59)
var hitbox_offset := Vector3(0, 0.21, -0.13)

var wheel_contact: Array[bool] = [false, false, false, false]
var wheel_dist := PackedFloat32Array([Phys.SUSP_MAX, Phys.SUSP_MAX, Phys.SUSP_MAX, Phys.SUSP_MAX])
var wheel_spin := 0.0
var num_contacts := 0
var on_ground := false
var contact_normal := Vector3.UP
var ground_time := 0.0
var air_time := 0.0
var body_touching := false
var body_normal := Vector3.UP
var turtle_time := 0.0

var has_jumped := false
var is_jumping := false
var jump_time := 0.0
var air_time_since_jump := 0.0
var has_double_jumped := false
var has_flipped := false
var is_flipping := false
var flip_time := 0.0
var flip_dir := Vector2.ZERO

var supersonic := false
var _ss_time := 0.0

var demolished := false
var respawn_timer := 0.0
var last_ball_touch_tick := -1000
var bump_cooldowns := {}

# One-shot events read by the presentation layer each frame.
var ev_jump := 0
var ev_flip := 0
var ev_land := 0.0


func setup(body: int) -> void:
	body_type = clampi(body, 0, BODIES.size() - 1)
	half_ext = BODIES[body_type]["half"]
	hitbox_offset = BODIES[body_type]["offset"]


func forward() -> Vector3:
	return -basis.z


func up() -> Vector3:
	return basis.y


func right() -> Vector3:
	return basis.x


func hitbox_center() -> Vector3:
	return pos + basis * hitbox_offset


func speed() -> float:
	return vel.length()


func save_prev() -> void:
	prev_pos = pos
	prev_quat = basis.get_rotation_quaternion()


func place(p: Vector3, yaw: float) -> void:
	pos = p
	vel = Vector3.ZERO
	ang_vel = Vector3.ZERO
	basis = Basis(Vector3.UP, yaw)
	prev_pos = pos
	prev_quat = basis.get_rotation_quaternion()
	has_jumped = false
	is_jumping = false
	has_double_jumped = false
	has_flipped = false
	is_flipping = false
	boosting = false
	supersonic = false
	demolished = false
	turtle_time = 0.0
	controls.reset()
	_prev_jump = false


## World-space inverse inertia (per unit mass) applied to v.
func inv_inertia(v: Vector3) -> Vector3:
	var l := basis.transposed() * v
	return basis * Vector3(l.x * INV_I.x, l.y * INV_I.y, l.z * INV_I.z)


func can_air_jump() -> bool:
	return not has_double_jumped and not has_flipped and \
		(not has_jumped or air_time_since_jump < Phys.DOUBLE_JUMP_WINDOW)


# ------------------------------------------------------------------ step

func step(dt: float, w: SimWorld) -> void:
	var c := controls
	var up_v := basis.y
	_update_wheels(w, up_v)
	var was_on_ground := on_ground
	on_ground = num_contacts >= 3
	var pressed := c.jump and not _prev_jump
	_prev_jump = c.jump

	if on_ground:
		if not was_on_ground and air_time > 0.15:
			ev_land = maxf(ev_land, absf(vel.dot(contact_normal)))
		ground_time += dt
		air_time = 0.0
		if not is_jumping:
			has_jumped = false
			has_double_jumped = false
			has_flipped = false
			is_flipping = false
			air_time_since_jump = 0.0
	else:
		ground_time = 0.0
		air_time += dt
		if has_jumped and not is_jumping:
			air_time_since_jump += dt

	# ---------------------------------------------------- boost
	var want_boost := c.boost and (boost > 0.0 or infinite_boost)
	if want_boost:
		if not boosting:
			_boost_timer = Phys.BOOST_MIN_TIME
		boosting = true
	elif boosting and _boost_timer > 0.0 and (boost > 0.0 or infinite_boost):
		boosting = true
	else:
		boosting = false
	if boosting:
		_boost_timer -= dt
		if not infinite_boost:
			boost = maxf(0.0, boost - Phys.BOOST_USE * dt)

	# ---------------------------------------------------- jumping / dodges
	var turtled := body_touching and num_contacts == 0 and up_v.dot(body_normal) < 0.35 and vel.length() < 6.0
	if turtled:
		turtle_time += dt
	else:
		turtle_time = 0.0
	if pressed:
		if on_ground and not is_jumping:
			_start_jump(up_v)
		elif turtled:
			_auto_roll(up_v)
		elif num_contacts == 0 and can_air_jump():
			var side := clampf(c.yaw + c.roll, -1.0, 1.0)
			var fw := c.pitch
			if absf(side) + absf(fw) >= Phys.DODGE_DEADZONE:
				_start_flip(Vector2(side, fw))
			else:
				vel += up_v * Phys.JUMP_IMPULSE
				has_double_jumped = true
				ev_jump += 1
	elif turtled and turtle_time > 2.5:
		_auto_roll(up_v)

	if is_jumping:
		jump_time += dt
		if c.jump and jump_time < Phys.JUMP_HOLD_TIME:
			vel += up_v * Phys.JUMP_HOLD_ACCEL * dt
		elif jump_time >= Phys.JUMP_MIN_TIME:
			is_jumping = false

	if is_flipping:
		flip_time += dt
		if flip_time >= Phys.FLIP_TORQUE_TIME or on_ground:
			is_flipping = false
		elif flip_time >= Phys.FLIP_ZDAMP_START and (vel.y < 0.0 or flip_time < Phys.FLIP_ZDAMP_END):
			vel.y *= pow(1.0 - Phys.FLIP_ZDAMP, dt * 120.0)

	# ---------------------------------------------------- forces
	vel.y -= Phys.GRAVITY * dt
	var fwd := -basis.z
	var rgt := basis.x
	if num_contacts > 0:
		_suspension(dt, up_v)
		_drive(dt, c, fwd, rgt, up_v)
	else:
		_air_control(dt, c, fwd)
	if boosting:
		var ba := Phys.BOOST_ACCEL_GROUND if on_ground else Phys.BOOST_ACCEL_AIR
		vel += fwd * ba * dt

	# ---------------------------------------------------- limits & integrate
	var sp := vel.length()
	if sp > Phys.CAR_MAX_SPEED:
		vel *= Phys.CAR_MAX_SPEED / sp
		sp = Phys.CAR_MAX_SPEED
	var wl := ang_vel.length()
	if wl > Phys.MAX_ANG_SPEED:
		ang_vel *= Phys.MAX_ANG_SPEED / wl
		wl = Phys.MAX_ANG_SPEED

	if sp >= Phys.SUPERSONIC_START:
		supersonic = true
		_ss_time = 0.0
	elif supersonic and sp >= Phys.SUPERSONIC_MAINTAIN and _ss_time < Phys.SUPERSONIC_MAINTAIN_TIME:
		_ss_time += dt
	else:
		supersonic = false

	pos += vel * dt
	if wl > 1e-6:
		basis = Basis(ang_vel / wl, wl * dt) * basis
		basis = basis.orthonormalized()
	wheel_spin += vel.dot(-basis.z) * dt / 0.145
	body_touching = false
	w.car_arena_collide(self)


func _start_jump(up_v: Vector3) -> void:
	vel += up_v * Phys.JUMP_IMPULSE
	is_jumping = true
	has_jumped = true
	jump_time = 0.0
	air_time_since_jump = 0.0
	ev_jump += 1


func _start_flip(d: Vector2) -> void:
	if d.length() > 1.0:
		d = d.normalized()
	has_flipped = true
	is_flipping = true
	flip_time = 0.0
	flip_dir = d
	var f := -basis.z
	var fwd_flat := Vector3(f.x, 0.0, f.z)
	if fwd_flat.length_squared() < 0.01:
		var u := basis.y
		fwd_flat = Vector3(u.x, 0.0, u.z) * (-signf(f.y))
		if fwd_flat.length_squared() < 0.0001:
			fwd_flat = Vector3(0, 0, -1)
	fwd_flat = fwd_flat.normalized()
	var right_flat := fwd_flat.cross(Vector3.UP)
	var v_f := vel.dot(fwd_flat)
	var ratio := absf(v_f) / Phys.CAR_MAX_SPEED
	var backwards: bool
	if absf(v_f) < 1.0:
		backwards = d.y < 0.0
	else:
		backwards = (d.y >= 0.0) != (v_f > 0.0)
	var imp_f := d.y * Phys.FLIP_IMPULSE
	var imp_s := d.x * Phys.FLIP_IMPULSE
	var max_x := Phys.FLIP_BACK_MAX_SCALE if backwards else 1.0
	imp_f *= (max_x - 1.0) * ratio + 1.0
	imp_s *= (Phys.FLIP_SIDE_MAX_SCALE - 1.0) * ratio + 1.0
	if backwards:
		imp_f *= 16.0 / 15.0
	vel += fwd_flat * imp_f + right_flat * imp_s
	ev_flip += 1


func _auto_roll(up_v: Vector3) -> void:
	var axis := up_v.cross(body_normal)
	if axis.length_squared() < 0.01:
		axis = -basis.z
	ang_vel = axis.normalized() * 6.5
	vel += body_normal * 3.2
	turtle_time = 0.0
	ev_jump += 1


func _update_wheels(w: SimWorld, up_v: Vector3) -> void:
	num_contacts = 0
	var nsum := Vector3.ZERO
	var far := ArenaGeo.sdf(pos) > 1.6
	for i in range(4):
		wheel_contact[i] = false
		wheel_dist[i] = Phys.SUSP_MAX
		if far:
			continue
		var conn: Vector3 = pos + basis * WHEEL_CONN[i]
		if w.raycast(conn, conn - up_v * Phys.SUSP_MAX) and w.hit_normal.dot(up_v) > 0.3:
			wheel_contact[i] = true
			wheel_dist[i] = conn.distance_to(w.hit_pos)
			nsum += w.hit_normal
			num_contacts += 1
	if num_contacts > 0:
		contact_normal = nsum.normalized()


func _suspension(dt: float, up_v: Vector3) -> void:
	for i in range(4):
		if not wheel_contact[i]:
			continue
		var r: Vector3 = basis * WHEEL_CONN[i]
		var comp := Phys.SUSP_REST - wheel_dist[i]
		var pv := (vel + ang_vel.cross(r)).dot(up_v)
		var f := Phys.SUSP_K * comp - Phys.SUSP_C * pv
		if f < 0.0:
			f = 0.0
		var imp := f * dt
		if wheel_dist[i] < Phys.SUSP_BOTTOM and pv < 0.0:
			imp += -pv * 0.3
		var J := up_v * imp
		vel += J
		ang_vel += inv_inertia(r.cross(J))


func _drive(dt: float, c: CarControls, fwd: Vector3, rgt: Vector3, up_v: Vector3) -> void:
	var fac := minf(1.0, float(num_contacts) / 3.0)
	var v_f := vel.dot(fwd)
	var thr := c.throttle
	if boosting:
		thr = 1.0
	var a := 0.0
	var stopping := false
	if absf(thr) > 0.02:
		if v_f * thr < 0.0 and absf(v_f) > 0.1:
			a = -signf(v_f) * Phys.BRAKE_ACCEL
			stopping = true
		else:
			a = thr * Phys.throttle_accel(v_f)
	else:
		a = -signf(v_f) * Phys.COAST_ACCEL
		stopping = true
	if stopping and absf(a * dt) > absf(v_f):
		a = -v_f / dt
	vel += fwd * a * dt * fac

	# Tyre lateral grip
	var drift := c.handbrake
	var v_lat := vel.dot(rgt)
	var rate := Phys.LAT_FRICTION_DRIFT if drift else Phys.LAT_FRICTION
	var maxa := Phys.LAT_MAX_ACCEL_DRIFT if drift else Phys.LAT_MAX_ACCEL
	var dv := clampf(v_lat * minf(1.0, rate * dt), -maxa * dt, maxa * dt)
	vel -= rgt * dv * fac

	# Steering: yaw rate follows the speed-dependent turning curvature
	var steer := c.steer
	var target := -steer * Phys.steer_curvature(v_f) * v_f
	var resp := 11.0
	if drift:
		target *= 1.65
		if absf(v_f) < 6.0:
			target = -steer * 2.2 * signf(v_f if absf(v_f) > 0.5 else 1.0)
		resp = 7.0
	var cur := ang_vel.dot(up_v)
	ang_vel += up_v * (target - cur) * minf(1.0, resp * dt) * fac

	# Sticky force keeps the car glued to walls
	if num_contacts >= 3:
		var sticky := 0.5 + (1.0 - absf(contact_normal.y))
		vel -= contact_normal * Phys.GRAVITY * sticky * dt


func _air_control(dt: float, c: CarControls, fwd: Vector3) -> void:
	var wl := basis.transposed() * ang_vel
	var p_in := c.pitch
	var y_in := c.yaw
	var r_in := c.roll
	var al := Vector3.ZERO
	if is_flipping:
		var cancel := 0.0
		if flip_dir.y != 0.0 and p_in * flip_dir.y < 0.0:
			cancel = absf(p_in)
		al.x = -flip_dir.y * Phys.FLIP_ANG_ACCEL * (1.0 - cancel) - Phys.T_PITCH * p_in * cancel
		al.y = -Phys.T_YAW * y_in - Phys.D_YAW * wl.y * (1.0 - absf(y_in))
		al.z = -flip_dir.x * Phys.FLIP_ANG_ACCEL - Phys.T_ROLL * r_in
	else:
		al.x = -Phys.T_PITCH * p_in - Phys.D_PITCH * wl.x * (1.0 - absf(p_in))
		al.y = -Phys.T_YAW * y_in - Phys.D_YAW * wl.y * (1.0 - absf(y_in))
		al.z = -Phys.T_ROLL * r_in - Phys.D_ROLL * wl.z
	ang_vel += basis * (al * dt)
	vel += fwd * c.throttle * Phys.AIR_THROTTLE_ACCEL * dt
