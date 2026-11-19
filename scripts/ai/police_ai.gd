class_name PoliceAI
extends RefCounted
## Police interceptor: follows the race route towards its target, then switches
## to direct intercept / ramming when close.

var route: RaceRoute
var target: Car
var idx := 0
var siren_on := true
var stuck_t := 0.0
var reverse_t := 0.0
var roadblock := false
var aggression := 1.0
var obstacles: Array = []


func _init(r: RaceRoute, tgt: Car) -> void:
	route = r
	target = tgt


func drive(car: Car, dt: float) -> void:
	car.tcs = true
	car.abs_on = true
	car.stability = 0.8
	car.steer_assist = 0.6
	if roadblock or target == null or not is_instance_valid(target):
		car.throttle = 0.0
		car.brake_in = 1.0
		car.steer_in = 0.0
		return
	var pos := car.global_position
	var spd := car.speed_abs
	var tp := target.global_position
	var tv := target.linear_velocity
	var dist := pos.distance_to(tp)
	var aim: Vector3
	var v_target := 92.0
	if route and dist > 70.0:
		idx = route.nearest(pos, idx, 8, 50)
		var look := clampf(8.0 + spd * 0.55, 10.0, 50.0)
		var ti := route.advance(idx, look)
		aim = route.pts[ti]
		v_target = route.v_allow[route.advance(idx, 12.0)] * 1.02
		# if the route goes away from the target (we are ahead of it), turn back
		var to_t := (tp - pos).normalized()
		if route.tangents[idx].dot(to_t) < -0.3 and dist < 260.0:
			aim = tp
			v_target = 30.0
	else:
		# intercept: lead the target a bit
		var closing := maxf(spd - tv.dot((tp - pos).normalized()), 8.0)
		var t := clampf(dist / closing, 0.0, 1.2)
		aim = tp + tv * t
		v_target = tv.length() + clampf(dist * 0.4, 4.0, 25.0) * aggression
	var loc := car.to_local(aim)
	var alpha := atan2(loc.x, -loc.z)
	var ld := maxf(loc.length(), 1.0)
	var need := atan(2.0 * car.model.wheelbase * sin(alpha) / ld)
	var lock := deg_to_rad(car.spec.steer_lock)
	var sf := clampf(spd / 55.0, 0.0, 1.0)
	var max_steer := lock * lerpf(1.0, lerpf(0.42, 0.24, car.steer_assist), sf)
	var steer := clampf(need / maxf(max_steer, 0.05), -1.0, 1.0)
	var thr := 0.0
	var brk := 0.0
	# target behind us: turn around (J-turn)
	if loc.z > 4.0 and dist < 80.0:
		steer = signf(loc.x) if absf(loc.x) > 0.5 else 1.0
		v_target = 12.0
	if spd < v_target - 1.0:
		thr = 1.0
	elif spd > v_target + 2.0:
		brk = clampf((spd - v_target) / 8.0, 0.2, 1.0)
	else:
		thr = 0.4
	if spd < 1.5:
		stuck_t += dt
	else:
		stuck_t = 0.0
	if stuck_t > 2.0 and reverse_t <= 0.0:
		reverse_t = 1.3
		stuck_t = 0.0
	if reverse_t > 0.0:
		reverse_t -= dt
		thr = 0.0
		brk = 1.0
		steer = -steer
	car.steer_in = steer
	car.throttle = thr
	car.brake_in = brk
	car.handbrake = false
	car.nitro_in = false
