class_name RacerAI
extends RefCounted
## Opponent driver: follows the race line with a speed profile, overtakes and
## avoids traffic, uses nitro on straights, may take shortcuts, recovers when stuck.

var route: RaceRoute
var idx := 0
var lane := 0.0
var avoid := 0.0
var skill := 0.93
var base_skill := 0.93
var aggression := 0.5
var rubber := 1.0
var shortcut := {}          # active shortcut dict
var sc_idx := 0
var stuck_t := 0.0
var reverse_t := 0.0
var off_route_t := 0.0
var obstacles: Array = []   # Node3D list (set by race manager)
var active := true
var finished := false
var cruise := false         # after finishing: slow down
var _sc_decided := {}


func _init(r: RaceRoute, lane_offset: float, sk: float) -> void:
	route = r
	lane = lane_offset
	base_skill = sk
	skill = sk
	aggression = randf_range(0.3, 0.9)


func drive(car: Car, dt: float) -> void:
	car.tcs = true
	car.abs_on = true
	car.stability = 0.75
	car.steer_assist = 0.6
	if not active:
		car.throttle = 0.0
		car.brake_in = 0.4
		car.steer_in = 0.0
		car.nitro_in = false
		return
	var pos := car.global_position
	idx = route.nearest(pos, idx, 6, 40)
	var spd := car.speed_abs
	# ---- shortcuts
	var path_pts: PackedVector3Array
	var on_sc := not shortcut.is_empty()
	if not on_sc:
		for sc in route.shortcuts:
			var key := str(sc.enter)
			var d_here := route.dist[idx]
			if absf(d_here - float(sc.enter)) < 40.0 and not _sc_decided.has(key):
				_sc_decided[key] = randf() < 0.45 + aggression * 0.3
				if _sc_decided[key]:
					shortcut = sc
					sc_idx = 0
					on_sc = true
	# ---- look-ahead target
	var look := clampf(7.0 + spd * 0.55, 9.0, 48.0)
	var target: Vector3
	var v_target := 0.0
	if on_sc:
		var sp: PackedVector3Array = shortcut.pts
		var best := sc_idx
		var bd := 1e18
		for i in range(sc_idx, mini(sc_idx + 30, sp.size())):
			var dd := sp[i].distance_squared_to(pos)
			if dd < bd:
				bd = dd
				best = i
		sc_idx = best
		var ti := mini(sc_idx + int(look / 4.0), sp.size() - 1)
		target = sp[ti]
		v_target = 26.0
		if sc_idx >= sp.size() - 3:
			idx = route.index_at_distance(float(shortcut.exit))
			shortcut = {}
	else:
		var ti := route.advance(idx, look)
		var w := route.widths[ti]
		var max_off := maxf(w * 0.5 - 1.6, 0.0)
		var off := clampf(lane + avoid, -max_off, max_off)
		target = route.pts[ti] + route.rights[ti] * off
		# speed: the minimum allowed speed over the next ~ few metres (already braking-aware)
		v_target = 1e9
		for k in [0, 2, 5, 9]:
			v_target = minf(v_target, route.v_allow[route.advance(idx, float(k) * 4.0)])
	# open (off-road) races: lower grip
	if route.is_open:
		v_target *= 0.85
	v_target *= skill * rubber
	# ---- avoidance of obstacles ahead
	var fwd := -car.global_transform.basis.z
	var right := car.global_transform.basis.x
	var block := 0.0
	var want_avoid := 0.0
	for o in obstacles:
		if o == car or not is_instance_valid(o):
			continue
		var rel: Vector3 = o.global_position - pos
		var along := rel.dot(fwd)
		var horizon := clampf(spd * 1.7, 35.0, 95.0)
		if along < 2.0 or along > horizon:
			continue
		var lat := rel.dot(right)
		if absf(lat) > 3.2:
			continue
		var closing := spd
		if o is RigidBody3D:
			closing = spd - (o as RigidBody3D).linear_velocity.dot(fwd)
		if closing < 1.0:
			continue
		# steer to the side with more room
		var side := -signf(lat) if absf(lat) > 0.3 else (1.0 if randf() > 0.5 else -1.0)
		want_avoid = side * (3.6 - absf(lat))
		block = maxf(block, 1.0 - along / horizon)
		# brake if we cannot get around it in time
		var t_hit := along / maxf(closing, 0.1)
		if t_hit < 1.6 and absf(lat) < 2.2:
			v_target = minf(v_target, spd - closing * 0.6)
	avoid = move_toward(avoid, want_avoid, dt * (6.0 if want_avoid != 0.0 else 2.0))
	# ---- steering (pure pursuit)
	var loc := car.to_local(target)
	var alpha := atan2(loc.x, -loc.z)
	var ld := maxf(loc.length(), 1.0)
	var steer_needed := atan(2.0 * car.model.wheelbase * sin(alpha) / ld)
	var lock := deg_to_rad(car.spec.steer_lock)
	var sf := clampf(spd / 55.0, 0.0, 1.0)
	var max_steer := lock * lerpf(1.0, lerpf(0.42, 0.24, car.steer_assist), sf)
	var steer := clampf(steer_needed / maxf(max_steer, 0.05), -1.0, 1.0)
	# ---- throttle / brake
	var thr := 0.0
	var brk := 0.0
	if cruise:
		v_target = minf(v_target, 14.0)
	if spd < v_target - 1.0:
		thr = clampf((v_target - spd) / 4.0 + 0.4, 0.0, 1.0)
	elif spd > v_target + 1.5:
		brk = clampf((spd - v_target) / 6.0, 0.15, 1.0)
	else:
		thr = 0.35
	# hairpins: brief handbrake to rotate the car
	var hb := false
	if not on_sc and absf(route.curv[route.advance(idx, 8.0)]) > 1.0 / 22.0 and spd > 14.0 and spd < 30.0 and aggression > 0.5:
		hb = true
	# nitro on straights
	var nit := false
	if not on_sc and spd > 18.0 and car.nitro > 0.0 and not cruise:
		var clear := true
		for k in [6, 12, 20, 30]:
			if route.v_allow[route.advance(idx, float(k) * 4.0)] < spd + 12.0:
				clear = false
				break
		nit = clear and block < 0.3
	# ---- stuck / recovery
	if spd < 2.0 and not car.controls_locked:
		stuck_t += dt
	else:
		stuck_t = maxf(stuck_t - dt * 2.0, 0.0)
	if stuck_t > 2.5 and reverse_t <= 0.0:
		reverse_t = 1.4
	if reverse_t > 0.0:
		reverse_t -= dt
		thr = 0.0
		brk = 1.0
		steer = -steer
		hb = false
		nit = false
		if car.gear > 0 and car.speed < 0.5:
			pass
	var lat_err := Vector2(route.pts[idx].x - pos.x, route.pts[idx].z - pos.z).length()
	if lat_err > (route.widths[idx] * 0.5 + (70.0 if route.is_open else 32.0)) and not on_sc:
		off_route_t += dt
	else:
		off_route_t = 0.0
	if stuck_t > 5.5 or off_route_t > 4.0 or car.upside_timer > 2.0 or car.in_water:
		respawn(car)
	car.steer_in = steer
	car.throttle = thr
	car.brake_in = brk
	car.handbrake = hb
	car.nitro_in = nit


func respawn(car: Car) -> void:
	var back := route.advance(idx, -12.0)
	var p := route.pts[back] + route.rights[back] * lane * 0.5
	var t := route.tangents[back]
	car.place(p + Vector3(0, 0.8, 0), atan2(-t.x, -t.z))
	car.linear_velocity = t * 12.0
	idx = back
	stuck_t = 0.0
	reverse_t = 0.0
	off_route_t = 0.0
	shortcut = {}
