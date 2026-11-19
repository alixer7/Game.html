class_name Car
extends RigidBody3D
## Raycast-suspension vehicle with a semi-empirical tyre model.

signal crashed(impulse: float, point: Vector3, other: Object)

const SURF_GRIP := {"asphalt": 1.0, "concrete": 0.97, "cobble": 0.86, "gravel": 0.74, "dirt": 0.7,
	"grass": 0.62, "sand": 0.56, "rock": 0.82, "snow": 0.48, "stone": 0.85, "tree": 0.8, "terrain": 0.7}
const SURF_ROLL := {"asphalt": 0.013, "concrete": 0.014, "cobble": 0.02, "gravel": 0.03, "dirt": 0.035,
	"grass": 0.06, "sand": 0.11, "rock": 0.02, "snow": 0.05, "stone": 0.02, "tree": 0.03, "terrain": 0.04}

var car_id := "falcon"
var spec: Dictionary = {}
var model: CarModel
var controller: Object = null
var fx: CarFX
var audio: CarAudio
var is_player := false
var is_police := false
var display_name := ""
var color := Color.RED

# driver inputs (0..1, steer -1..1)
var throttle := 0.0
var brake_in := 0.0
var steer_in := 0.0
var handbrake := false
var nitro_in := false
var controls_locked := false

# assists (player settings; AI uses its own)
var tcs := true
var abs_on := true
var stability := 0.6
var steer_assist := 0.5

# drivetrain state
var gear := 1
var rpm := 900.0
var shift_timer := 0.0
var reverse_hold := 0.0
var engine_load := 0.0
var nitro := 1.0
var nitro_regen := true
var nitro_active := false
var top_gear := 6

# motion state
var speed := 0.0            # forward speed m/s (signed)
var speed_abs := 0.0
var steer_angle := 0.0
var drift_angle := 0.0      # rad between velocity and heading
var grounded := 0
var air_time := 0.0
var last_air_time := 0.0
var surface := "asphalt"
var skid_amount := 0.0      # 0..1 overall tyre noise
var damage := 0.0
var upside_timer := 0.0
var in_water := false
var odometer := 0.0

# wheel data
var wheels := []
var rest_len := 0.3
var sag := 0.07
var droop := 0.06
var mass_corner := 360.0
var _rays := []
var _crash_cd := 0.0
var _scrape := 0.0
var _world: World


func setup(id: String, paint: Color, world: World, player := false) -> void:
	car_id = id
	is_player = player
	_world = world
	if Game.CARS.has(id):
		spec = Game.CARS[id].duplicate(true)
	else:
		spec = Game.CARS["kaiser"].duplicate(true)
	color = paint
	is_police = id == "police"
	top_gear = spec.gears.size()
	mass = spec.mass
	mass_corner = mass * 0.25
	model = CarModel.new()
	model.name = "Model"
	add_child(model)
	model.build(spec.body, paint, hash(id) + int(paint.r * 1000))
	# collision hull
	var cs := CollisionShape3D.new()
	var hull := ConvexPolygonShape3D.new()
	var pts := PackedVector3Array()
	for p in model.hull_points:
		pts.append(Vector3(p.x * 0.97, maxf(p.y, model.style.cl + 0.06), p.z * 0.98))
	hull.points = pts
	cs.shape = hull
	add_child(cs)
	collision_layer = 2
	collision_mask = 1 | 2
	var pm := PhysicsMaterial.new()
	pm.friction = 0.35
	pm.bounce = 0.05
	physics_material_override = pm
	continuous_cd = true
	can_sleep = false
	contact_monitor = true
	max_contacts_reported = 6
	center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
	var com_z := 0.12 if spec.body in ["supercar", "hyper"] else -0.08
	center_of_mass = Vector3(0, 0.47 if spec.body != "suv" else 0.62, com_z)
	var L := model.length
	var W := model.width
	var H := model.height
	inertia = Vector3(mass * (L * L + H * H) / 12.0 * 0.9, mass * (L * L + W * W) / 12.0 * 0.85, mass * (W * W + H * H) / 12.0 * 0.9)
	linear_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
	angular_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
	linear_damp = 0.0
	angular_damp = 0.08
	# suspension & wheels
	var k: float = spec.susp_k
	sag = mass_corner * 9.81 / k
	rest_len = 0.28
	wheels.clear()
	for i in 4:
		var rp: Vector3 = model.wheel_rest[i]
		var w := {
			"mount": rp + Vector3(0, rest_len, 0),
			"rest": rp,
			"radius": model.wheel_radius,
			"front": i < 2,
			"side": -1.0 if i % 2 == 0 else 1.0,
			"len": rest_len,
			"prev_len": rest_len,
			"contact": false,
			"point": Vector3.ZERO,
			"normal": Vector3.UP,
			"load": mass_corner * 9.81,
			"comp": 0.0,
			"spin": 0.0,
			"omega": 0.0,
			"slip_lat": 0.0,
			"slip_long": 0.0,
			"surface": "asphalt",
			"collider": null,
		}
		var drive: String = spec.drive
		w["driven"] = (drive == "awd") or (drive == "rwd" and i >= 2) or (drive == "fwd" and i < 2)
		wheels.append(w)
		var q := PhysicsRayQueryParameters3D.new()
		q.collision_mask = 1
		q.exclude = [get_rid()]
		q.hit_back_faces = false
		_rays.append(q)
	fx = CarFX.new()
	fx.name = "FX"
	add_child(fx)
	fx.setup(self)
	audio = CarAudio.new()
	audio.name = "Audio"
	add_child(audio)
	audio.setup(self)
	display_name = Game.car_name(id)


func _ready() -> void:
	body_entered.connect(func(_b): pass)


func reset_state() -> void:
	gear = 1
	rpm = spec.idle
	shift_timer = 0.0
	throttle = 0.0
	brake_in = 0.0
	steer_in = 0.0
	handbrake = false
	nitro_in = false
	upside_timer = 0.0
	for w in wheels:
		w.len = rest_len
		w.prev_len = rest_len


func place(pos: Vector3, yaw: float) -> void:
	var xf := Transform3D(Basis(Vector3.UP, yaw), pos + Vector3(0, 0.25, 0))
	global_transform = xf
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	reset_physics_interpolation()
	reset_state()


## move back onto the closest road, facing along it
func respawn_on_road(prefer_dir := Vector3.ZERO) -> void:
	var wd := _world.data
	var nr := wd.nearest_road(global_position, 400.0, ["alley"])
	if nr.is_empty():
		place(global_position + Vector3(0, 3, 0), rotation.y)
		return
	var t := wd.road_tangent(nr.road, nr.idx)
	var fwd := -global_transform.basis.z
	if prefer_dir != Vector3.ZERO:
		fwd = prefer_dir
	if t.dot(fwd) < 0.0:
		t = -t
	var yaw := atan2(-t.x, -t.z)
	place(nr.pos + Vector3(0, 0.6, 0), yaw)


# --------------------------------------------------------------------------- physics
func _physics_process(dt: float) -> void:
	if controller and controller.has_method("drive"):
		controller.drive(self, dt)
	if controls_locked:
		throttle = 0.0
		nitro_in = false
	var xf := global_transform
	var basis := xf.basis
	var up := basis.y
	var fwd := -basis.z
	var right := basis.x
	var com := xf * center_of_mass
	var v := linear_velocity
	speed = v.dot(fwd)
	speed_abs = v.length()
	odometer += speed_abs * dt
	var space := get_world_3d().direct_space_state

	# ---- steering
	var lock := deg_to_rad(spec.steer_lock)
	var speed_factor := clampf(speed_abs / 55.0, 0.0, 1.0)
	var max_steer := lock * lerpf(1.0, lerpf(0.42, 0.24, steer_assist), speed_factor)
	var target := steer_in * max_steer
	# counter-steer assist while drifting
	if speed_abs > 6.0 and absf(drift_angle) > 0.12 and steer_assist > 0.0 and grounded >= 2:
		target += clampf(-drift_angle, -lock, lock) * steer_assist * 0.55
	var steer_rate := (3.6 if not is_player else 2.6) * (1.0 - speed_factor * 0.45)
	steer_angle = move_toward(steer_angle, clampf(target, -lock, lock), steer_rate * dt)

	# ---- drivetrain
	_update_gearbox(dt)
	var ratios: Array = spec.gears
	var gr: float = 0.0
	if gear > 0:
		gr = ratios[gear - 1]
	elif gear < 0:
		gr = -3.1
	var final: float = spec.final
	var total_ratio := gr * final
	var driven := 0
	for w in wheels:
		if w.driven:
			driven += 1
	var wheel_speed := absf(speed) / model.wheel_radius
	var rpm_target := wheel_speed * absf(total_ratio) * 60.0 / TAU
	var idle: float = spec.idle
	var redline: float = spec.redline
	var accel_in := throttle if gear >= 0 else brake_in
	var launch := idle + accel_in * (redline * 0.55 - idle)
	if gear != 0 and absf(gear) <= 1 and rpm_target < launch:
		rpm_target = launch  # clutch slip at launch
	rpm_target = clampf(rpm_target, idle, redline * 1.02)
	var torque := _torque_at(rpm) * accel_in
	if shift_timer > 0.0:
		torque = 0.0
	if rpm >= redline:
		torque *= 0.1
	nitro_active = false
	if nitro_in and nitro > 0.0 and gear > 0 and throttle > 0.2:
		nitro_active = true
		torque *= 1.3
		nitro = maxf(nitro - dt / 7.0, 0.0)
	elif nitro_regen:
		nitro = minf(nitro + dt / 25.0, 1.0)
	var drive_force_total := torque * total_ratio * 0.9 / model.wheel_radius
	engine_load = accel_in

	# ---- wheels
	grounded = 0
	var k: float = spec.susp_k
	var c: float = spec.susp_c
	var arb: float = spec.arb
	var max_len := rest_len + sag + droop
	var comps := [0.0, 0.0, 0.0, 0.0]
	for i in 4:
		var w: Dictionary = wheels[i]
		var origin: Vector3 = xf * w.mount
		var q: PhysicsRayQueryParameters3D = _rays[i]
		q.from = origin
		q.to = origin - up * (max_len + w.radius)
		var hit := space.intersect_ray(q)
		if hit.is_empty():
			w.contact = false
			w.len = move_toward(w.len, max_len, dt * 2.0)
			w.prev_len = w.len
			continue
		var dist := origin.distance_to(hit.position) - float(w.radius)
		w.contact = true
		w.point = hit.position
		w.normal = hit.normal
		w.collider = hit.collider
		w.len = clampf(dist, 0.0, max_len)
		comps[i] = (rest_len + sag) - w.len
		grounded += 1
	for i in 4:
		var w: Dictionary = wheels[i]
		if not w.contact:
			w.load = 0.0
			continue
		var comp: float = comps[i]
		var other: float = comps[i ^ 1]
		var vel_c: float = (w.prev_len - w.len) / dt
		w.prev_len = w.len
		var damp := c * vel_c * (1.0 if vel_c > 0.0 else 0.75)
		var fs := k * comp + damp + (comp - other) * arb
		if w.len < 0.03:
			fs += (0.03 - w.len) * k * 6.0  # bump stop
		fs = maxf(fs, 0.0)
		w.load = fs
		w.comp = comp

	var downforce: float = spec.downforce * 0.5 * 1.225 * speed * speed
	var surf_votes := {}
	var total_slip := 0.0
	var gravity_stab := 0.0
	for i in 4:
		var w: Dictionary = wheels[i]
		if not w.contact:
			w.slip_lat = 0.0
			w.slip_long = 0.0
			w.omega = lerpf(w.omega, w.omega * 0.98, dt)
			w.spin += w.omega * dt
			continue
		var n: Vector3 = w.normal
		var p: Vector3 = w.point
		var fz: float = w.load + downforce * 0.25
		# wheel heading
		var wheel_fwd := fwd
		if w.front:
			wheel_fwd = fwd.rotated(up, -steer_angle)   # positive steer = right
		var f := (wheel_fwd - n * wheel_fwd.dot(n)).normalized()
		var s := f.cross(n).normalized()
		var vc := v + angular_velocity.cross(p - com)
		var vl := vc.dot(f)
		var vs := vc.dot(s)
		# surface
		var sname := _surface_of(w.collider, p)
		w.surface = sname
		surf_votes[sname] = surf_votes.get(sname, 0) + 1
		var off_bonus := 1.0
		if spec.stats[3] > 0.85 and sname != "asphalt" and sname != "concrete":
			off_bonus = 1.18
		var mu: float = spec.grip * SURF_GRIP.get(sname, 0.8) * off_bonus
		mu *= clampf(1.08 - 0.08 * fz / (mass_corner * 9.81), 0.85, 1.1)  # load sensitivity
		var fmax := mu * fz
		# ---- longitudinal
		var flong := 0.0
		if w.driven:
			var share := 1.0 / driven
			if spec.drive == "awd":
				share = 0.4 * 0.5 if w.front else 0.6 * 0.5
			flong += drive_force_total * share
			if accel_in < 0.05 and gear != 0 and shift_timer <= 0.0:
				flong -= signf(vl) * rpm / redline * 900.0 * share * 2.0  # engine braking
		var brake_force: float = spec.brake * (0.62 if w.front else 0.38) * 0.5
		var b_in := brake_in if gear >= 0 else throttle
		var locked := false
		if b_in > 0.01:
			var bf := b_in * brake_force
			if abs_on:
				bf = minf(bf, fmax * 0.95)
			elif bf > fmax:
				locked = true
			if absf(vl) > 0.6:
				flong -= signf(vl) * bf
			else:
				flong -= clampf(vl * mass_corner / dt * 0.5, -bf, bf)
		if handbrake and not w.front:
			locked = true
		flong -= signf(vl) * fz * SURF_ROLL.get(sname, 0.02)
		var spinning := false
		if absf(flong) > fmax:
			if tcs and w.driven and not locked and signf(flong) == signf(drive_force_total):
				flong = signf(flong) * fmax * 0.97
			else:
				spinning = not locked
				flong = signf(flong) * fmax * 0.88
		if locked:
			flong = -signf(vl) * fmax * 0.78 if absf(vl) > 0.4 else -vl * mass_corner / dt * 0.3
		# ---- lateral (Pacejka-like)
		var alpha := atan2(vs, maxf(absf(vl), 2.5))
		var bb := 11.0 if w.front else 10.0
		var cc := 1.38 if w.front else 1.32
		var x := absf(alpha)
		var mf := sin(cc * atan(bb * x - 0.25 * (bb * x - atan(bb * x))))
		var fy := -signf(alpha) * fmax * mf
		# low speed: kill sideways creep
		var ls := clampf(1.0 - speed_abs / 4.0, 0.0, 1.0)
		if ls > 0.0:
			fy = lerpf(fy, clampf(-vs * mass_corner / dt * 0.35, -fmax, fmax), ls)
		var lat_cap := sqrt(maxf(fmax * fmax - flong * flong, 0.0))
		if locked:
			lat_cap = fmax * 0.42
		elif spinning:
			lat_cap = minf(lat_cap, fmax * 0.5)
		fy = clampf(fy, -lat_cap, lat_cap)
		# ---- apply
		var app := p.lerp(com, 0.32)
		var force: Vector3 = f * flong + s * fy + up * w.load
		apply_force(force, app - global_position)
		# wheel visuals / audio data
		var slip_long := 0.0
		if spinning:
			slip_long = 1.0
		elif locked and absf(vl) > 1.0:
			slip_long = -1.0
		w.slip_long = slip_long
		w.slip_lat = clampf(x / 0.35, 0.0, 1.0) if speed_abs > 4.0 else 0.0
		var roll := vl / float(w.radius)
		if locked:
			roll = 0.0
		elif spinning:
			roll = signf(drive_force_total) * maxf(absf(roll), rpm / 60.0 * TAU / maxf(absf(total_ratio), 0.1))
		w.omega = roll
		w.spin += roll * dt
		total_slip += maxf(w.slip_lat * smoothstep(0.35, 0.8, w.slip_lat), absf(slip_long))
	skid_amount = clampf(total_slip / 2.2, 0.0, 1.0) if grounded > 0 else 0.0
	var best := 0
	for sname in surf_votes:
		if surf_votes[sname] > best:
			best = surf_votes[sname]
			surface = sname

	# rpm follows the wheels (with wheelspin flare)
	var spin_flare := 0.0
	for w in wheels:
		if w.driven and w.slip_long > 0.5:
			spin_flare = 0.35
	if grounded == 0:
		rpm_target = lerpf(rpm, idle + accel_in * redline, 0.5)
	rpm = lerpf(rpm, clampf(rpm_target * (1.0 + spin_flare * accel_in), idle, redline * 1.02), clampf(dt * 12.0, 0.0, 1.0))

	# ---- aero
	var drag_k: float = 0.5 * 1.225 * float(spec.drag) * 2.2
	apply_central_force(-v * speed_abs * drag_k)
	if grounded > 0:
		var df := -up * downforce
		apply_force(df * 0.5, (xf * (center_of_mass + Vector3(0, 0, -1.3))) - global_position)
		apply_force(df * 0.5, (xf * (center_of_mass + Vector3(0, 0, 1.3))) - global_position)
	if nitro_active:
		apply_central_force(fwd * mass * 3.2)

	# ---- drift angle & stability
	if speed_abs > 3.0:
		var vh := Vector3(v.x, 0, v.z).normalized()
		var fh := Vector3(fwd.x, 0, fwd.z).normalized()
		drift_angle = atan2(fh.cross(vh).y, fh.dot(vh)) if speed > -1.0 else 0.0
	else:
		drift_angle = 0.0
	if grounded >= 3 and stability > 0.0 and not handbrake and speed_abs > 8.0:
		var yaw_rate := angular_velocity.dot(up)
		var expected := -speed * tan(steer_angle) / model.wheelbase
		var excess := yaw_rate - expected
		var limit := 0.35 + (1.0 - stability) * 1.2
		if absf(excess) > limit:
			apply_torque(-up * (excess - signf(excess) * limit) * inertia.y * 4.0 * stability)

	# ---- airborne
	if grounded == 0:
		air_time += dt
		# gentle self-levelling so landings are drivable (pitch/roll only)
		var lvl := up.cross(Vector3.UP)
		apply_torque(lvl * mass * 2.2)
		angular_velocity *= 1.0 - dt * 0.6
	else:
		if air_time > 0.0:
			last_air_time = air_time
			if air_time > 0.35 and fx:
				fx.landed(air_time)
		air_time = 0.0

	# ---- flipped / water
	if up.y < 0.25 and speed_abs < 3.0:
		upside_timer += dt
	else:
		upside_timer = 0.0
	in_water = _world != null and _world.data.water_level(global_position) > global_position.y + 0.4
	if in_water:
		apply_central_force(-v * mass * 1.5)
	_crash_cd = maxf(_crash_cd - dt, 0.0)

	# ---- visuals
	for i in 4:
		var w: Dictionary = wheels[i]
		var center: Vector3 = w.mount - Vector3(0, w.len, 0)
		model.set_wheel(i, -steer_angle if w.front else 0.0, w.spin, center)
	model.set_lights(clampf(brake_in if gear >= 0 else 0.0, 0.0, 1.0), Game.settings.time_of_day == 3)


func _torque_at(r: float) -> float:
	var peak: float = spec.peak_rpm
	var red: float = spec.redline
	var tmax: float = spec.torque
	var x := r / peak
	var t := 0.0
	if x < 1.0:
		t = 0.52 + 0.48 * sin(x * PI * 0.5)
	else:
		t = 1.0 - 0.32 * pow((r - peak) / maxf(red - peak, 1.0), 1.6)
	return tmax * t


func _update_gearbox(dt: float) -> void:
	shift_timer = maxf(shift_timer - dt, 0.0)
	var red: float = spec.redline
	# reverse handling
	if gear >= 1 and speed < 0.8 and brake_in > 0.5 and throttle < 0.1:
		reverse_hold += dt
		if reverse_hold > 0.35:
			gear = -1
			reverse_hold = 0.0
	elif gear == -1 and throttle > 0.3 and speed > -1.0:
		gear = 1
	else:
		reverse_hold = 0.0
	if gear <= 0 or shift_timer > 0.0:
		return
	var ratios: Array = spec.gears
	if rpm > red * 0.93 and gear < top_gear and grounded > 0:
		gear += 1
		shift_timer = 0.16
		if fx:
			fx.shifted()
		if audio:
			audio.shift_pop()
	elif gear > 1:
		var lower: float = ratios[gear - 2]
		var cur: float = ratios[gear - 1]
		var rpm_lower := rpm * lower / cur
		if rpm_lower < red * 0.8 and rpm < red * 0.5:
			gear -= 1
			shift_timer = 0.12


func _surface_of(collider: Object, p: Vector3) -> String:
	if collider and collider.has_meta("surface"):
		var s: String = collider.get_meta("surface")
		if s != "terrain":
			return s
	if _world == null:
		return "asphalt"
	var sp := _world.data.splat_at(p.x, p.z)
	var grass := 1.0 - sp.r - sp.g - sp.b - sp.a
	var best := "grass"
	var bv := grass
	if sp.r > bv:
		best = "rock"; bv = sp.r
	if sp.g > bv:
		best = "sand"; bv = sp.g
	if sp.b > bv:
		best = "dirt"; bv = sp.b
	if sp.a > bv:
		best = "snow"
	return best


func _integrate_forces(state: PhysicsDirectBodyState3D) -> void:
	var n := state.get_contact_count()
	var scraping := false
	for i in n:
		var imp := state.get_contact_impulse(i).length()
		var other := state.get_contact_collider_object(i)
		var pt := state.get_contact_local_position(i)
		var nrm := state.get_contact_local_normal(i)
		# ignore our own wheels' ground contact (body touching road at low clearance counts as scrape)
		if imp > mass * 2.2 and _crash_cd <= 0.0:
			_crash_cd = 0.35
			_on_impact(imp, pt, nrm, other)
		elif state.linear_velocity.length() > 6.0:
			scraping = true
			if fx and Engine.get_physics_frames() % 3 == 0:
				fx.sparks(pt, nrm, 0.3)
	_scrape = lerpf(_scrape, 1.0 if scraping else 0.0, 0.2)
	if audio:
		audio.scrape_level = _scrape


func _on_impact(impulse: float, point: Vector3, normal: Vector3, other: Object) -> void:
	var severity := clampf(impulse / (mass * 9.0), 0.0, 1.5)
	var lp := to_local(point)
	var ldir := (global_transform.basis.inverse() * normal).normalized()
	# push the panel inward (towards the car centre)
	var inward := -lp.normalized()
	if ldir.dot(inward) < 0.0:
		ldir = -ldir
	model.deform(lp, ldir, severity * 0.12)
	damage = minf(damage + severity * 0.08, 1.0)
	if fx:
		fx.sparks(point, normal, severity)
		fx.debris(point, severity)
	if audio:
		audio.crash(severity)
	crashed.emit(impulse, point, other)


func get_progress_dir() -> Vector3:
	return -global_transform.basis.z


func kmh() -> float:
	return speed_abs * 3.6
