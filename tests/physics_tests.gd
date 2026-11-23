class_name PhysicsTests
extends RefCounted
## Measures the handling model on a programmatic arena and checks it against
## the design targets in DESIGN_BIBLE.md ("Handling targets").

var T: SceneTree
var arena: Node3D
var R: Object


func run(runner: Object) -> void:
	R = runner
	T = (runner as Node).get_tree()
	arena = Node3D.new()
	T.root.add_child(arena)
	_ground(Vector3(0, -0.5, 0), Vector3(4000, 1, 4000), Surfaces.ROAD)
	await _accel()
	await _surfaces()
	await _turning()
	await _drift_sparks()
	await _bad_taps()
	await _reserve_and_tiers()
	await _chain()
	await _hop()
	await _ramp_air_boost()
	await _walls()
	await _hook()
	await _current()
	await _slopes()
	await _determinism()
	arena.queue_free()


func _ground(pos: Vector3, size: Vector3, surface: int, rot := Vector3.ZERO) -> StaticBody3D:
	var b := StaticBody3D.new()
	b.set_meta("surface", surface)
	b.collision_layer = 1
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = size
	cs.shape = bs
	b.add_child(cs)
	b.position = pos
	b.rotation = rot
	arena.add_child(b)
	return b


func _kart(pos := Vector3.ZERO, yaw := 0.0, kind := "balanced") -> Kart:
	var k := Kart.new()
	k.params = KartParams.make_class(kind)
	arena.add_child(k)
	k.teleport(Transform3D(Basis(Vector3.UP, yaw), pos + Vector3.UP * 0.3))
	return k


func _settle(k: Kart) -> void:
	await R.frames(20)


func _drive_until(k: Kart, max_frames: int, cond: Callable) -> int:
	for i in max_frames:
		await T.physics_frame
		if cond.call():
			return i
	return -1


# -------------------------------------------------------------------- tests
func _accel() -> void:
	var k := _kart()
	await _settle(k)
	k.in_throttle = 1.0
	var t90 := -1.0
	var v2 := 0.0
	for i in 600:
		await T.physics_frame
		if i == 120:
			v2 = k.speed
		if t90 < 0.0 and k.speed >= k.params.max_speed * 0.9:
			t90 = i / 60.0
	R.check("physics", "top speed ~ base max (26 m/s)", absf(k.speed - k.params.max_speed) < 0.6, "v=%.2f" % k.speed)
	R.check("physics", "0->90%% in 2.0-4.5 s", t90 > 2.0 and t90 < 4.5, "t90=%.2f s, v@2s=%.1f" % [t90, v2])
	k.queue_free()


func _surfaces() -> void:
	var res := {}
	var x := 300.0
	for sid: int in [Surfaces.GRASS, Surfaces.SAND, Surfaces.MUD, Surfaces.DIRT]:
		var plate := _ground(Vector3(x, -0.45, -600), Vector3(30, 1, 1400), sid)
		var k := _kart(Vector3(x, 0.1, 0), 0.0)
		await _settle(k)
		k.in_throttle = 1.0
		await R.frames(540)
		res[Surfaces.NAMES[sid]] = snappedf(k.speed / k.params.max_speed, 0.01)
		var expect: float = Surfaces.get_info(sid).speed
		R.check("physics", "surface %s top speed ratio ~ %.2f" % [Surfaces.NAMES[sid], expect], absf(k.speed / k.params.max_speed - expect) < 0.06, "ratio=%.2f" % (k.speed / k.params.max_speed))
		k.queue_free()
		plate.queue_free()
		x += 60.0


func _turning() -> void:
	var k := _kart()
	await _settle(k)
	k.in_throttle = 1.0
	await R.frames(360)
	k.in_steer = 1.0
	var y0 := k.yaw
	await R.frames(60)
	var rate := absf(angle_difference(y0, k.yaw))
	var radius := k.speed / maxf(rate, 0.01)
	R.check("physics", "full-speed steering radius 20-32 m (slides needed for tight corners)", radius > 20.0 and radius < 32.0, "R=%.1f m at %.1f m/s" % [radius, k.speed])
	k.queue_free()


func _drift_sparks() -> void:
	var k := _kart(Vector3(0, 0, 400))
	await _settle(k)
	k.in_throttle = 1.0
	await R.frames(300)
	var v_before := k.speed
	k.in_steer = 1.0
	k.in_drift = true
	var started := await _drive_until(k, 60, func() -> bool: return k.drifting)
	R.check("physics", "hop + steer starts a slide", started >= 0)
	var slips: Array = []
	var radii: Array = []
	var gained_acc := [0.0]   # lambdas capture locals by value -> use a container
	k.boost_gained.connect(func(a: float, _s: StringName) -> void: gained_acc[0] += a)
	var stage_taps := 0
	for i in 400:
		await T.physics_frame
		slips.append(rad_to_deg(k.slip_angle))
		if k.drift_stage < 3 and k.drift_charge >= 0.93:
			k.in_boost = true
			stage_taps += 1
		if i > 30 and i % 10 == 0:
			radii.append(k.speed / maxf(absf(k.yaw_rate), 0.01))
	var mean_slip := 0.0
	for s in slips.slice(60):
		mean_slip += s
	mean_slip /= maxf(slips.size() - 60, 1)
	R.check("physics", "steady slide angle 15-45 deg", mean_slip > 15.0 and mean_slip < 45.0, "slip=%.1f" % mean_slip)
	R.check("physics", "3 perfect sparks per slide", k.stat_perfect >= 3, "perfect=%d taps=%d" % [k.stat_perfect, stage_taps])
	var gained: float = gained_acc[0]
	R.check("physics", "3-stage chain adds ~2.3 s reserve", absf(gained - 2.3) < 0.3, "gained=%.2f" % gained)
	var min_r := 1e9
	for r in radii:
		min_r = minf(min_r, r)
	R.check("physics", "slide (steering in) is tighter than plain steering (< 16 m)", min_r < 16.0, "R_min=%.1f" % min_r)
	R.check("physics", "slide + sparks keep/raise speed", k.speed >= v_before * 0.97, "before=%.1f after=%.1f" % [v_before, k.speed])
	k.in_drift = false
	k.in_steer = 0.0
	k.queue_free()


func _bad_taps() -> void:
	var k := _kart(Vector3(-400, 0, 0))
	await _settle(k)
	k.in_throttle = 1.0
	await R.frames(300)
	k.in_steer = -1.0
	k.in_drift = true
	await _drive_until(k, 60, func() -> bool: return k.drifting)
	await _drive_until(k, 200, func() -> bool: return k.drift_charge > 0.3)
	var res0 := k.reserve
	k.in_boost = true
	await R.frames(2)
	R.check("physics", "early tap fizzles (no reserve, stage kept)", k.reserve <= res0 + 0.01 and k.drift_stage == 0 and k.stat_fizzles == 1)
	await _drive_until(k, 200, func() -> bool: return k.drift_stage >= 1)
	R.check("physics", "waiting too long backfires (stage lost)", k.drift_stage == 1 and k.stat_sparks == 0, "fizzles=%d" % k.stat_fizzles)
	k.queue_free()


func _reserve_and_tiers() -> void:
	var k := _kart(Vector3(400, 0, 400))
	await _settle(k)
	k.in_throttle = 1.0
	await R.frames(300)
	k.add_reserve(2.0, &"test")
	await R.frames(60)
	R.check("physics", "reserve drains ~1 s per s on road", absf(k.reserve - 1.0) < 0.1, "reserve=%.2f" % k.reserve)
	R.check("physics", "tier 1 while reserve lasts", k.tier == 1)
	var boosted := k.speed
	R.check("physics", "boost raises speed toward +24%", boosted > k.params.max_speed * 1.12, "v=%.1f" % boosted)
	await _drive_until(k, 200, func() -> bool: return k.tier == 0)
	await R.frames(20)
	R.check("physics", "reserve empty -> tier 0, speed bleeds gradually (momentum)", k.tier == 0 and k.speed > k.params.max_speed + 1.0, "v=%.1f 0.33 s after the boost ended" % k.speed)
	await R.frames(150)
	k.apply_pad(3.4, 2)
	await R.frames(150)
	R.check("physics", "Overdrive pad -> tier 2 & ~+40% speed", k.tier == 2 and k.speed > k.params.max_speed * 1.3, "v=%.1f tier=%d" % [k.speed, k.tier])
	k.queue_free()


func _chain() -> void:
	## Alternating slides with good taps should sustain the reserve: the core
	## "keep the fire alive" mastery loop.
	var k := _kart(Vector3(-800, 0, -800))
	await _settle(k)
	k.in_throttle = 1.0
	await R.frames(240)
	k.add_reserve(2.0, &"test")
	var dir := 1.0
	var min_res := 99.0
	for slide in 6:
		k.in_steer = dir
		k.in_drift = true
		await _drive_until(k, 40, func() -> bool: return k.drifting)
		for i in 170:
			await T.physics_frame
			if k.drift_stage < 3 and k.drift_charge >= 0.93:
				k.in_boost = true
		k.in_drift = false
		k.in_steer = 0.0
		await R.frames(8)
		min_res = minf(min_res, k.reserve)
		dir = -dir
	R.check("physics", "skilled slide chaining sustains boost (reserve never empties)", min_res > 0.0 and k.tier > 0, "min reserve=%.2f end=%.2f tier=%d" % [min_res, k.reserve, k.tier])
	k.queue_free()


func _hop() -> void:
	var k := _kart(Vector3(800, 0, 0))
	await _settle(k)
	k.in_throttle = 1.0
	await R.frames(120)
	k.in_drift = true
	var air := 0
	await T.physics_frame
	for i in 60:
		await T.physics_frame
		if not k.grounded:
			air += 1
	k.in_drift = false
	R.check("physics", "hop airtime 0.25-0.5 s", air / 60.0 > 0.25 and air / 60.0 < 0.5, "air=%.2f s" % (air / 60.0))
	R.check("physics", "hop without steer does not start a slide", not k.drifting)
	k.queue_free()


func _ramp_air_boost() -> void:
	# 14 deg ramp, 2.4 m lip, lands on flat ground
	var base := Vector3(0, 0, -1200)
	_ground(base + Vector3(0, 1.2, 0), Vector3(12, 0.4, 10), Surfaces.WOOD, Vector3(deg_to_rad(14), 0, 0))
	var k := _kart(base + Vector3(0, 0, 60))
	await _settle(k)
	k.in_throttle = 1.0
	var max_air := 0.0
	var got := []
	k.boost_gained.connect(func(a: float, s: StringName) -> void:
		if s == &"air": got.append(a))
	for i in 360:
		await T.physics_frame
		max_air = maxf(max_air, k.airtime)
	R.check("physics", "ramp launch gives hang time > 0.5 s", max_air > 0.5, "air=%.2f" % max_air)
	R.check("physics", "clean landing after hang time grants an air boost", got.size() > 0, str(got))
	k.queue_free()


func _walls() -> void:
	var results := {}
	var angles := [8.0, 30.0, 80.0]
	var x := -1500.0
	for ang: float in angles:
		_ground(Vector3(x, 1.5, -100), Vector3(1, 3, 600), Surfaces.ROCK)   # wall along Z at x
		var gap := 10.0 if ang < 20.0 else 30.0
		var k := _kart(Vector3(x - gap, 0, 150), 0.0)
		await _settle(k)
		k.in_throttle = 1.0
		await R.frames(240)
		k.yaw = -deg_to_rad(ang)   # heading rotated toward +X (the wall)
		k.rotation.y = k.yaw
		var hv := Vector3(k.velocity.x, 0, k.velocity.z)
		k.velocity = Vector3(-sin(k.yaw), 0, -cos(k.yaw)) * hv.length()
		var sev_acc := [-1]
		k.impact.connect(func(s: int, _st: float, _p: Vector3) -> void:
			if sev_acc[0] < 0:
				sev_acc[0] = s)
		var pre := k.speed
		var post := 0.0
		for i in 600:
			await T.physics_frame
			if sev_acc[0] < 0:
				pre = k.speed
			else:
				await R.frames(2)
				post = k.speed
				break
		results[ang] = {"sev": sev_acc[0], "retained": snappedf(post / maxf(pre, 0.1), 0.01)}
		k.queue_free()
		x -= 80.0
	R.check("physics", "8 deg contact = graze, small loss", int(results[8.0].sev) == 0 and float(results[8.0].retained) > 0.85, results[8.0])
	R.check("physics", "30 deg contact = glance, medium loss", int(results[30.0].sev) == 1, results[30.0])
	R.check("physics", "80 deg contact = head-on, big loss", int(results[80.0].sev) == 2 and float(results[80.0].retained) < 0.45, results[80.0])


func _hook() -> void:
	var k := _kart(Vector3(1500, 0, 1500))
	await _settle(k)
	k.in_throttle = 1.0
	await R.frames(300)
	k.in_steer = 1.0
	k.in_drift = true
	await _drive_until(k, 60, func() -> bool: return k.drifting)
	await R.frames(20)
	var rate_drift := absf(k.yaw_rate)
	k.in_brake = 1.0
	await R.frames(20)
	var rate_hook := absf(k.yaw_rate)
	var v_hook := k.speed
	k.in_brake = 0.0
	R.check("physics", "hook turn rotates much faster than a slide", rate_hook > rate_drift * 1.3, "slide=%.2f hook=%.2f rad/s v=%.1f" % [rate_drift, rate_hook, v_hook])
	k.queue_free()


func _current() -> void:
	var body: StaticBody3D = load("res://scripts/track/road_body.gd").new()
	body.set("surface", Surfaces.CURRENT)
	var pts := []
	for i in 30:
		pts.append([2200.0, 0.0, -float(i) * 40.0, 16.0, 0.0, {}])
	var sp := SplinePath.from_points(pts, false, 1.5)
	body.set("path", sp)
	body.set("flow_speed", 6.5)
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(16, 1, 1200)
	cs.shape = bs
	body.add_child(cs)
	body.position = Vector3(2200, -0.45, -580)
	arena.add_child(body)
	var k := _kart(Vector3(2200, 0, 0), 0.0)
	await _settle(k)
	k.in_throttle = 1.0
	await R.frames(600)
	var v_cur := k.speed
	R.check("physics", "river current: faster than the road cap (flow pushes)", v_cur > k.params.max_speed * 1.0, "v=%.1f (road max %.1f)" % [v_cur, k.params.max_speed])
	k.queue_free()
	body.queue_free()


func _slopes() -> void:
	## Regression guard: CharacterBody3D floor heuristics once bled speed on descents.
	var res := {}
	var x := 3000.0
	for deg: float in [-12.0, 12.0]:
		var ramp := _ground(Vector3(x, 0, -500), Vector3(30, 1, 1200), Surfaces.ROAD, Vector3(deg_to_rad(deg), 0, 0))
		var k := _kart(Vector3(x, 0.9, -500.0), 0.0)
		await R.frames(10)
		k.in_throttle = 1.0
		await R.frames(420)
		res[deg] = [snappedf(k.speed, 0.1), k.grounded]
		k.queue_free()
		ramp.queue_free()
		x += 60.0
	R.check("physics", "downhill: reaches the cap and stays grounded", float(res[-12.0][0]) > 25.5 and bool(res[-12.0][1]), res[-12.0])
	R.check("physics", "uphill: slower than flat but grounded", float(res[12.0][0]) > 20.0 and float(res[12.0][0]) < 25.9 and bool(res[12.0][1]), res[12.0])


func _determinism() -> void:
	var ends := []
	for run in 2:
		var k := _kart(Vector3(-2200, 0, 0))
		await _settle(k)
		for i in 420:
			k.in_throttle = 1.0
			k.in_steer = sin(i * 0.05)
			k.in_drift = (i / 90) % 2 == 1
			if i % 37 == 0:
				k.in_boost = true
			await T.physics_frame
		ends.append(k.global_position)
		k.queue_free()
		await R.frames(5)
	R.check("physics", "same inputs -> same result (deterministic)", (ends[0] as Vector3).distance_to(ends[1]) < 0.05, "delta=%.4f" % (ends[0] as Vector3).distance_to(ends[1]))
