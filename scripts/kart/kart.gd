class_name Kart
extends CharacterBody3D
## Arcade kart physics core.
##
## Design notes (see DESIGN_BIBLE.md, "Handling model"):
##  * Heading (where the chassis points) and velocity (where the kart travels) are
##    separate. Lateral grip pulls velocity toward the heading; absorbed lateral
##    slip is converted back into forward speed minus a small scrub, so momentum
##    is conserved through corners instead of being snapped.
##  * Power slides lower grip, widen the yaw-rate range and charge a 3-stage
##    spark meter. Tapping BOOST inside the hot zone adds seconds to the boost
##    RESERVE (stored), plus a small instant kick. Late taps backfire (stage
##    lost), early taps fizzle (meter resets, time lost).
##  * The reserve is burned at a surface-dependent rate. While it lasts the kart
##    is in tier 1 (Boost) or tier 2 (Overdrive) and the top-speed cap rises.
##  * Hang time on a clean landing feeds the reserve, so jump lines are a
##    trade-off between flight time and boost gained.

signal spark(stage: int, quality: float, perfect: bool, hooked: bool)
signal fizzle(reason: StringName)
signal landed(airtime: float, good: bool, impact_speed: float)
signal impact(severity: int, strength: float, point: Vector3)
signal boost_gained(amount: float, source: StringName)
signal tier_changed(tier: int)
signal drift_started(dir: int)
signal drift_ended(stage: int)
signal hopped()
signal item_requested()

const GRAVITY := 24.0
const WORLD_MASK := 1
const KILL_Y := -45.0

enum Severity { GRAZE, GLANCE, HEAD_ON }

@export var params: KartParams

var racer_index := 0
var display_name := "Racer"
var is_player := false

# ---------------------------------------------------------------- inputs
var in_throttle := 0.0
var in_brake := 0.0
var in_steer := 0.0
var in_drift := false
var in_boost := false   # edge, consumed every tick
var in_item := false    # edge, consumed every tick

# ---------------------------------------------------------------- public state
var yaw := 0.0
var yaw_rate := 0.0
var grounded := false
var ground_normal := Vector3.UP
var smooth_normal := Vector3.UP
var surface := Surfaces.ROAD
var flow := Vector3.ZERO
var forward_speed := 0.0
var lateral_speed := 0.0
var speed := 0.0
var slip_angle := 0.0
var drifting := false
var drift_dir := 0
var drift_charge := 0.0
var drift_stage := 0
var drift_time := 0.0
var hooking := false
var reserve := 0.0
var tier := 0
var airtime := 0.0
var stun_time := 0.0
var spin_time := 0.0
var frozen := false
var steer_smoothed := 0.0
var shielded := false
var amber := 0
var last_impact_severity := -1
var wall_contact := false
var total_distance := 0.0

# stats for tests / results
var stat_sparks := 0
var stat_perfect := 0
var stat_fizzles := 0
var stat_impacts := [0, 0, 0]
var stat_boost_time := 0.0
var stat_overdrive_time := 0.0
var stat_air_boosts := 0

# ---------------------------------------------------------------- internals
var _drift_was_held := false
var _drift_dir_pending := 0
var _hop_active := false
var _recover_t := 1.0
var _hook_release_timer := 99.0
var _since_land := 0.0
var _pending_kick := 0.0
var _impact_cooldown := 0.0
var _was_on_floor := false
var _ground_hit := {}
var _ground_collider: Object = null
var _last_safe_xform := Transform3D.IDENTITY
var _last_pos := Vector3.ZERO
var _ray_query := PhysicsRayQueryParameters3D.new()


func _ready() -> void:
	if params == null:
		params = KartParams.new()
	collision_layer = 2
	collision_mask = WORLD_MASK
	# FLOATING: move_and_slide only slides velocity along contact normals. Ground
	# detection and snapping are done here (see _ground_check) so the controller
	# isn't affected by CharacterBody3D's floor heuristics (gravity reset on
	# descents, snap suppression while moving up, etc.).
	max_slides = 5
	safe_margin = 0.02
	motion_mode = CharacterBody3D.MOTION_MODE_FLOATING
	wall_min_slide_angle = 0.0
	_ray_query.collision_mask = WORLD_MASK
	_ray_query.exclude = [get_rid()]
	_ray_query.hit_from_inside = false
	if get_node_or_null("Shape") == null:
		var cs := CollisionShape3D.new()
		cs.name = "Shape"
		var cap := CapsuleShape3D.new()
		cap.radius = 0.5
		cap.height = 1.75
		cs.shape = cap
		cs.rotation = Vector3(PI * 0.5, 0, 0)
		cs.position = Vector3(0, 0.52, 0)
		add_child(cs)
	yaw = rotation.y
	_last_pos = global_position
	_last_safe_xform = global_transform


# ------------------------------------------------------------------ helpers
func heading() -> Vector3:
	return Vector3(-sin(yaw), 0.0, -cos(yaw))


func heading_on_plane(n: Vector3) -> Vector3:
	var h := heading()
	var f := h - n * h.dot(n)
	if f.length_squared() < 1e-6:
		return h
	return f.normalized()


func current_cap() -> float:
	var info := Surfaces.get_info(surface)
	var p := params
	var surf_speed: float = info.speed
	if tier > 0:
		var bonus := p.boost_bonus if tier == 1 else p.overdrive_bonus
		# boosting partially overcomes off-road slowdown
		return p.max_speed * (1.0 + bonus) * lerpf(1.0, surf_speed, 0.5)
	return p.max_speed * surf_speed


func add_reserve(amount: float, source: StringName, force_tier := 0) -> void:
	if amount <= 0.0:
		return
	var old_tier := tier
	reserve = minf(reserve + amount, params.reserve_cap)
	if tier == 0:
		tier = 1
	if force_tier > tier:
		tier = force_tier
	if tier == 1 and reserve >= params.overdrive_threshold:
		tier = 2
	if tier != old_tier:
		tier_changed.emit(tier)
	boost_gained.emit(amount, source)


func apply_pad(amount: float, pad_tier: int) -> void:
	## Boost pads top the reserve up to at least `amount` and force a tier.
	var old_tier := tier
	var add := maxf(amount - reserve, 0.25)
	reserve = minf(reserve + add, params.reserve_cap)
	tier = maxi(tier, pad_tier)
	if tier != old_tier:
		tier_changed.emit(tier)
	_pending_kick += 2.0 if pad_tier >= 2 else 1.2
	boost_gained.emit(add, &"pad")


func lose_boost() -> void:
	if tier != 0:
		tier = 0
		tier_changed.emit(0)
	reserve = 0.0


func cancel_drift() -> void:
	if drifting:
		drifting = false
		drift_ended.emit(drift_stage)
	drift_charge = 0.0
	drift_stage = 0
	hooking = false
	_recover_t = 0.0


func spin_out(duration := 1.1) -> void:
	## Called by items. Shield absorbs one hit.
	if shielded:
		shielded = false
		return
	cancel_drift()
	lose_boost()
	spin_time = duration
	var hv := Vector3(velocity.x, 0, velocity.z)
	velocity = Vector3(hv.x * 0.45, maxf(velocity.y, 0.0) + 3.0, hv.z * 0.45)
	amber = maxi(amber - 3, 0)


func teleport(xform: Transform3D) -> void:
	global_transform = Transform3D(Basis(Vector3.UP, xform.basis.get_euler().y), xform.origin)
	yaw = global_rotation.y
	velocity = Vector3.ZERO
	cancel_drift()
	lose_boost()
	airtime = 0.0
	_last_pos = global_position
	smooth_normal = Vector3.UP
	ground_normal = Vector3.UP


func last_safe_transform() -> Transform3D:
	return _last_safe_xform


# ------------------------------------------------------------------ main loop
func _physics_process(dt: float) -> void:
	if frozen:
		velocity = Vector3.ZERO
		in_boost = false
		in_item = false
		_drift_was_held = in_drift
		return
	_probe_ground()
	_tick_timers(dt)
	_update_drift_state(dt)
	_update_boost(dt)
	if _was_on_floor:
		_ground_motion(dt)
	else:
		_air_motion(dt)
	var v_before := velocity
	rotation = Vector3(0.0, yaw, 0.0)
	move_and_slide()
	_handle_impacts(v_before, dt)
	_post_move(v_before, dt)
	if in_item:
		item_requested.emit()
	in_boost = false
	in_item = false
	_drift_was_held = in_drift


func _probe_ground() -> void:
	var space := get_world_3d().direct_space_state
	var origin := global_position + Vector3.UP * 0.7
	_ray_query.from = origin
	_ray_query.to = origin + Vector3.DOWN * 1.9
	_ground_hit = space.intersect_ray(_ray_query)
	flow = Vector3.ZERO
	if _ground_hit.is_empty():
		_ground_collider = null
		return
	var col: Object = _ground_hit.collider
	_ground_collider = col
	var pos: Vector3 = _ground_hit.position
	var sid := Surfaces.ROAD
	if col.has_method("surface_at"):
		sid = col.surface_at(pos)
	elif col.has_meta("surface"):
		sid = int(col.get_meta("surface"))
	if col.has_method("flow_at"):
		flow = col.flow_at(pos)
	# Only adopt the new surface when actually close to it (avoids flicker in the air).
	if pos.distance_to(global_position) < 0.6 or _was_on_floor:
		surface = sid


func _tick_timers(dt: float) -> void:
	stun_time = maxf(stun_time - dt, 0.0)
	spin_time = maxf(spin_time - dt, 0.0)
	_impact_cooldown = maxf(_impact_cooldown - dt, 0.0)
	_hook_release_timer += dt
	_since_land += dt
	if _recover_t < 1.0:
		_recover_t = minf(_recover_t + dt / params.drift_recover_time, 1.0)
	# steering smoothing; analog inputs still get a tiny filter for stability
	steer_smoothed = move_toward(steer_smoothed, clampf(in_steer, -1.0, 1.0), params.steer_response * dt)


func _update_drift_state(dt: float) -> void:
	var p := params
	var drift_pressed := in_drift and not _drift_was_held
	var can_control := stun_time <= 0.0 and spin_time <= 0.0
	# --- hop
	if drift_pressed and _was_on_floor and can_control and not drifting:
		velocity -= ground_normal * minf(velocity.dot(ground_normal), 0.0)   # drop the contact push
		velocity += smooth_normal * p.hop_velocity
		_hop_active = true
		_was_on_floor = false   # integrate this tick as airborne so the hop isn't projected away
		_drift_dir_pending = int(signf(in_steer)) if absf(in_steer) > 0.35 else 0
		hopped.emit()
	# --- remember the steer direction while airborne with drift held
	if in_drift and not _was_on_floor and not drifting and absf(in_steer) > 0.35:
		_drift_dir_pending = int(signf(in_steer))
	# --- late steer buffer right after landing
	if in_drift and _was_on_floor and not drifting and _since_land < 0.2 and absf(in_steer) > 0.5:
		_drift_dir_pending = int(signf(in_steer))
	# --- start
	if in_drift and _was_on_floor and not drifting and _drift_dir_pending != 0 and can_control \
			and absf(forward_speed) >= p.drift_min_speed and not _hop_active_upwards():
		drifting = true
		drift_dir = _drift_dir_pending
		drift_charge = 0.0
		drift_stage = 0
		drift_time = 0.0
		_drift_dir_pending = 0
		drift_started.emit(drift_dir)
	if not in_drift:
		_drift_dir_pending = 0
	# --- sustain / end
	if drifting:
		drift_time += dt
		if not in_drift or not can_control:
			_end_drift()
		elif forward_speed < p.drift_min_speed * 0.55:
			_end_drift()
		elif slip_angle > deg_to_rad(78.0):
			_end_drift()
	# --- hook turn: pull back while sliding into the corner
	var was_hooking := hooking
	hooking = drifting and in_brake > 0.5 and steer_smoothed * drift_dir > 0.35
	if was_hooking and not hooking:
		_hook_release_timer = 0.0
	# --- charge meter
	if drifting and _was_on_floor and drift_stage < 3:
		var info := Surfaces.get_info(surface)
		drift_charge += dt / p.charge_times[drift_stage] * float(info.charge)
		if drift_charge >= 1.0 + p.overheat_grace:
			drift_stage += 1
			drift_charge = 0.0
			stat_fizzles += 1
			fizzle.emit(&"late")
	# --- boost tap
	if in_boost and drifting and drift_stage < 3:
		if drift_charge < p.hot_zone:
			drift_charge = 0.0
			stat_fizzles += 1
			fizzle.emit(&"early")
		else:
			var perfect := drift_charge >= p.perfect_zone
			var q := 1.0
			if not perfect:
				q = lerpf(0.55, 0.85, inverse_lerp(p.hot_zone, p.perfect_zone, drift_charge))
			var amount: float = p.spark_reserve[drift_stage] * q
			var kick: float = p.spark_kick[drift_stage] * q
			var hooked := _hook_release_timer < p.hook_boost_window
			if hooked:
				amount *= 1.0 + p.hook_boost_bonus
				kick *= 1.0 + p.hook_boost_bonus
				_hook_release_timer = 99.0
			add_reserve(amount, &"spark")
			_pending_kick += kick
			stat_sparks += 1
			if perfect:
				stat_perfect += 1
			spark.emit(drift_stage, q, perfect, hooked)
			drift_stage += 1
			drift_charge = 0.0


func _hop_active_upwards() -> bool:
	return _hop_active and velocity.dot(smooth_normal) > 0.5


func _end_drift() -> void:
	drifting = false
	hooking = false
	drift_ended.emit(drift_stage)
	drift_charge = 0.0
	drift_stage = 0
	_recover_t = 0.0


func _update_boost(dt: float) -> void:
	if reserve > 0.0:
		var info := Surfaces.get_info(surface)
		var drain: float = info.drain if _was_on_floor else 1.0
		if tier == 2:
			drain *= params.overdrive_drain
			stat_overdrive_time += dt
		stat_boost_time += dt
		reserve -= dt * drain
		if reserve <= 0.0:
			reserve = 0.0
			if tier != 0:
				tier = 0
				tier_changed.emit(0)


func _ground_motion(dt: float) -> void:
	var p := params
	var info := Surfaces.get_info(surface)
	var n := ground_normal
	var can_control := stun_time <= 0.0 and spin_time <= 0.0

	# ---------------- yaw
	var spd_est := absf(forward_speed)
	if drifting:
		var into := steer_smoothed * float(drift_dir)
		var rate := p.drift_base_rate + p.drift_steer_range * into
		rate *= clampf(spd_est / 12.0, 0.45, 1.0)
		if hooking:
			rate = p.hook_rate
		yaw_rate = -float(drift_dir) * rate
	else:
		var auth := clampf(spd_est / p.turn_full_speed, 0.0, 1.0)
		var hi := clampf((spd_est - p.turn_full_speed) / maxf(p.max_speed - p.turn_full_speed, 1.0), 0.0, 1.0)
		var rate := lerpf(p.turn_rate_max, p.turn_rate_top, hi) * auth
		if forward_speed < -0.5:
			rate = -rate
		if not can_control:
			rate *= 0.4
		yaw_rate = -steer_smoothed * rate
	if spin_time > 0.0:
		yaw_rate = 0.0
	yaw = wrapf(yaw + yaw_rate * dt, -PI, PI)

	# ---------------- decompose velocity on the ground plane
	var fwd := heading_on_plane(n)
	var right := fwd.cross(n).normalized()
	var v := velocity
	var v_plane := v - n * v.dot(n)
	var vf := v_plane.dot(fwd)
	var vl := v_plane.dot(right)

	# ---------------- lateral grip with momentum redirection
	var grip_rate := p.grip * float(info.grip)
	var drift_grip_rate := p.drift_grip * float(info.drift_grip)
	if drifting:
		grip_rate = drift_grip_rate
		if hooking:
			grip_rate *= 0.75
	elif _recover_t < 1.0:
		grip_rate = lerpf(drift_grip_rate, grip_rate, smoothstep(0.0, 1.0, _recover_t))
	if spin_time > 0.0:
		grip_rate = 1.5
	var spd_before := sqrt(vf * vf + vl * vl)
	var keep := exp(-grip_rate * dt)
	var vl_new := vl * keep
	var absorbed := absf(vl) - absf(vl_new)
	var scrub := p.drift_scrub if drifting else p.turn_scrub
	if Surfaces.is_offroad(surface):
		scrub *= 1.5
	var spd_after := maxf(spd_before - absorbed * scrub, 0.0)
	var vf_mag := sqrt(maxf(spd_after * spd_after - vl_new * vl_new, 0.0))
	vf = vf_mag if vf >= 0.0 else -vf_mag
	vl = vl_new

	# ---------------- engine / brakes
	var cap := current_cap()
	var throttle := in_throttle if can_control else 0.0
	var brake := in_brake if can_control else 0.0
	if flow != Vector3.ZERO:
		cap += maxf(flow.dot(fwd), 0.0) * float(info.flow) * 0.9
	if drifting:
		if hooking:
			vf = move_toward(vf, 0.0, p.hook_decel * dt)
		elif brake > 0.1:
			vf = move_toward(vf, 0.0, p.brake_decel * 0.35 * brake * dt)
		brake = 0.0
	if throttle > 0.01 and vf > -1.0:
		if vf < cap:
			var a: float
			if tier > 0:
				a = p.boost_accel
			else:
				var x := clampf(vf / cap, 0.0, 1.0)
				a = p.accel * float(info.accel) * (1.0 - pow(x, p.accel_falloff) * 0.93)
			vf = minf(vf + a * throttle * dt, cap)
	if brake > 0.01:
		if vf > 0.3:
			vf = move_toward(vf, 0.0, p.brake_decel * brake * dt)
		else:
			vf = move_toward(vf, -p.reverse_speed, p.reverse_accel * brake * dt)
	if throttle <= 0.01 and brake <= 0.01:
		vf = move_toward(vf, 0.0, p.coast_decel * dt)
	if vf > cap:
		vf = move_toward(vf, cap, (p.overspeed_decel + float(info.drag) * 2.0) * dt)
	# surface drag only bites when coasting: on throttle the surface's speed
	# multiplier is the cap (drag above the cap is in overspeed_decel above)
	if throttle <= 0.01:
		vf = move_toward(vf, 0.0, float(info.drag) * dt)
	if spin_time > 0.0:
		vf = move_toward(vf, 0.0, 14.0 * dt)
	# slopes
	vf += -GRAVITY * p.slope_factor * fwd.y * dt
	# spark / pad kicks
	if _pending_kick > 0.0:
		vf += _pending_kick
		_pending_kick = 0.0

	# ---------------- recompose
	var v_new := fwd * vf + right * vl
	if flow != Vector3.ZERO:
		var fl := flow - n * flow.dot(n)
		var along := v_new.dot(fl.normalized()) if fl.length() > 0.01 else 0.0
		if along < fl.length() + cap:
			v_new += fl.normalized() * minf(fl.length() * 0.9, 9.0) * float(info.flow) * dt
	# gentle push into the ground; any part not absorbed by the contact is
	# exactly along n and is projected out next tick
	v_new -= n * 1.5
	velocity = v_new
	forward_speed = vf
	lateral_speed = vl
	speed = sqrt(vf * vf + vl * vl)
	slip_angle = atan2(absf(vl), maxf(absf(vf), 0.1))


func _air_motion(dt: float) -> void:
	var p := params
	var can_control := stun_time <= 0.0 and spin_time <= 0.0
	airtime += dt
	if can_control:
		yaw_rate = -steer_smoothed * p.air_turn_rate
		if drifting:
			yaw_rate = -float(drift_dir) * (p.drift_base_rate * 0.6 + 0.5 * steer_smoothed * float(drift_dir))
	else:
		yaw_rate = 0.0
	yaw = wrapf(yaw + yaw_rate * dt, -PI, PI)
	var hv := Vector3(velocity.x, 0.0, velocity.z)
	var hs := hv.length()
	if hs > 1.0 and can_control:
		# small air-steer: nudge the flight path toward the heading
		var h := heading()
		var ang := hv.signed_angle_to(h, Vector3.UP)
		var step := clampf(ang, -p.air_steer_vel * dt, p.air_steer_vel * dt)
		hv = hv.rotated(Vector3.UP, step)
	# light air drag above the cap so huge launches don't run away
	var cap := current_cap()
	if hs > cap:
		hv = hv.normalized() * move_toward(hs, cap, 1.0 * dt)
	if _pending_kick > 0.0 and hs > 0.5:
		hv += hv.normalized() * _pending_kick
		_pending_kick = 0.0
	velocity = Vector3(hv.x, velocity.y - GRAVITY * dt, hv.z)
	var h2 := heading()
	forward_speed = hv.dot(h2)
	lateral_speed = hv.dot(h2.cross(Vector3.UP))
	speed = hv.length()
	slip_angle = atan2(absf(lateral_speed), maxf(absf(forward_speed), 0.1))


func _handle_impacts(v_before: Vector3, dt: float) -> void:
	var strongest := -1.0
	var best_n := Vector3.ZERO
	var best_point := Vector3.ZERO
	var contact := false
	for i in get_slide_collision_count():
		var c := get_slide_collision(i)
		var nrm := c.get_normal()
		if nrm.y > 0.55:
			continue
		# contacts near the bottom of the capsule are seams/bumps, not walls
		if c.get_position().y - global_position.y < 0.2:
			continue
		var hn := Vector3(nrm.x, 0.0, nrm.z)
		if hn.length_squared() < 1e-4:
			continue
		hn = hn.normalized()
		var vh := Vector3(v_before.x, 0.0, v_before.z)
		var into := -vh.dot(hn)
		if into <= 0.4:
			continue
		contact = true
		var ratio := into / maxf(vh.length(), 0.01)
		if ratio > strongest:
			strongest = ratio
			best_n = hn
			best_point = c.get_position()
	wall_contact = contact
	if not contact:
		return
	var p := params
	var hv := Vector3(velocity.x, 0.0, velocity.z)
	var pre_speed := Vector3(v_before.x, 0.0, v_before.z).length()
	# continuous scraping drag
	hv = hv.normalized() * move_toward(hv.length(), 0.0, 4.0 * dt) if hv.length() > 0.01 else hv
	if _impact_cooldown <= 0.0 and pre_speed > 3.0:
		var sev: int
		if strongest < p.graze_threshold:
			sev = Severity.GRAZE
			hv *= 0.97
			reserve = maxf(reserve - 0.15, 0.0)
		elif strongest < p.head_on_threshold:
			sev = Severity.GLANCE
			var t := inverse_lerp(p.graze_threshold, p.head_on_threshold, strongest)
			hv *= lerpf(0.86, 0.6, t)
			reserve *= 0.4
			if strongest > 0.45:
				cancel_drift()
			# deflect the chassis along the wall so the kart doesn't stay pointed into it
			if hv.length() > 1.0:
				var tangent := hv.normalized()
				var target_yaw := atan2(-tangent.x, -tangent.z)
				yaw = lerp_angle(yaw, target_yaw, 0.45)
		else:
			sev = Severity.HEAD_ON
			hv *= 0.25
			cancel_drift()
			lose_boost()
			stun_time = 0.35
			hv += best_n * pre_speed * strongest * p.bounce_damping * 0.6
		if reserve <= 0.0 and tier != 0:
			tier = 0
			tier_changed.emit(0)
		stat_impacts[sev] += 1
		last_impact_severity = sev
		_impact_cooldown = 0.25 if sev == Severity.GRAZE else 0.45
		impact.emit(sev, strongest * pre_speed, best_point)
	velocity = Vector3(hv.x, velocity.y, hv.z)


func _ground_check() -> bool:
	## Own ground detection + snap (FLOATING motion mode).
	var space := get_world_3d().direct_space_state
	var origin := global_position + Vector3.UP * 0.7
	_ray_query.from = origin
	_ray_query.to = origin + Vector3.DOWN * 1.5
	var hit := space.intersect_ray(_ray_query)
	if hit.is_empty():
		return false
	var n: Vector3 = hit.normal
	if n.y < 0.6:
		return false
	var gap := global_position.y - (hit.position as Vector3).y
	var away := velocity.dot(n)
	if gap <= 0.16 and away < 0.6:
		ground_normal = n
		return true
	# snap down over convex transitions, but let real launches (crests, lips, hops) fly
	if _was_on_floor and gap < 0.6 and away < 0.8 and not _hop_active:
		global_position.y -= gap - 0.03
		velocity -= n * maxf(velocity.dot(n), 0.0)
		ground_normal = n
		return true
	return false


func _post_move(v_before: Vector3, dt: float) -> void:
	var on_floor := _ground_check()
	smooth_normal = smooth_normal.slerp(ground_normal if on_floor else Vector3.UP, clampf((14.0 if on_floor else 2.5) * dt, 0.0, 1.0)).normalized()
	if on_floor and not _was_on_floor:
		_on_landed(v_before)
	if on_floor:
		airtime = 0.0
		if velocity.dot(ground_normal) <= 0.1:
			_hop_active = false
		if spin_time <= 0.0 and not wall_contact and ground_normal.y > 0.85:
			_last_safe_xform = global_transform
	_was_on_floor = on_floor
	grounded = on_floor
	total_distance += global_position.distance_to(_last_pos)
	_last_pos = global_position


func _on_landed(v_before: Vector3) -> void:
	var p := params
	var at := airtime
	_since_land = 0.0
	var hv := Vector3(velocity.x, 0.0, velocity.z)
	var ang := 0.0
	if hv.length() > 2.0:
		ang = absf(hv.signed_angle_to(heading(), Vector3.UP))
	var good := ang < deg_to_rad(30.0) or drifting
	var impact_speed := -v_before.y
	if at >= p.air_boost_min_time and good and spin_time <= 0.0:
		var amt := clampf((at - (p.air_boost_min_time - 0.12)) * p.air_boost_rate, 0.1, p.air_boost_max)
		add_reserve(amt, &"air")
		stat_air_boosts += 1
	elif not good and at > 0.3:
		hv *= 0.82
		_recover_t = 0.0
		velocity = Vector3(hv.x, velocity.y, hv.z)
	if impact_speed > 15.0:
		hv *= 0.96
		velocity = Vector3(hv.x, velocity.y, hv.z)
	landed.emit(at, good, impact_speed)
	airtime = 0.0


func get_debug_state() -> Dictionary:
	return {
		"speed": speed, "fwd": forward_speed, "slip_deg": rad_to_deg(slip_angle),
		"drift": drifting, "stage": drift_stage, "charge": drift_charge,
		"reserve": reserve, "tier": tier, "grounded": grounded, "surface": surface,
		"air": airtime, "pos": global_position,
	}
