extends SceneTree
## اختبار فيزياء الكرة: godot --headless --path . --script tools/test_physics.gd

func _init() -> void:
	var hard: Dictionary = Court.SURFACES[Court.Surface.HARD]
	print("=== KD = ", BallPhysics.KD)
	# 1) إرسال مسطح 200 كم/س من ارتفاع 2.75
	_serve_case("FLAT 200", Shot.Type.SERVE_FLAT, 0.65, Vector3(-0.4, 0, -5.9), hard)
	_serve_case("KICK", Shot.Type.SERVE_KICK, 0.6, Vector3(-2.0, 0, -5.4), hard)
	_serve_case("SLICE wide", Shot.Type.SERVE_SLICE, 0.6, Vector3(-3.7, 0, -5.0), hard)
	# 2) ضربات أرضية من خلف الخط
	for t in [Shot.Type.FLAT, Shot.Type.TOPSPIN, Shot.Type.SLICE, Shot.Type.LOB, Shot.Type.DROP]:
		for surf_id in [Court.Surface.HARD, Court.Surface.CLAY, Court.Surface.GRASS]:
			_rally_case(t, 0.75, Court.SURFACES[surf_id])
	# 3) سقوط حر من 2.54 م (اختبار ITF: الارتداد 1.35 - 1.47 م)
	var s := BallPhysics.State.new()
	s.pos = Vector3(0, 2.54, 3)
	var apex := 0.0
	var bounced := false
	for i in 400:
		var ev := BallPhysics.step(s, hard)
		if ev & BallPhysics.EV_BOUNCE:
			bounced = true
		if bounced:
			apex = maxf(apex, s.pos.y)
			if s.vel.y < 0: break
	print("drop test 2.54m -> rebound ", snappedf(apex - BallPhysics.R, 0.01), " m (ITF 1.35-1.47)")
	# 4) مونت كارلو: نسبة نجاح الضربات بخطأ قياسي
	_monte("FLAT rally p=0.75", Shot.Type.FLAT, 0.75, Vector3(2.5, 0.95, 12.3), Vector3(-2.8, 0, -9.5), 1.0, hard)
	_monte("TOPSPIN rally p=0.75", Shot.Type.TOPSPIN, 0.75, Vector3(2.5, 0.95, 12.3), Vector3(-2.8, 0, -9.5), 1.0, hard)
	_monte("TOPSPIN line p=0.9", Shot.Type.TOPSPIN, 0.9, Vector3(2.5, 0.95, 12.3), Vector3(3.7, 0, -10.8), 1.0, hard)
	_monte("FLAT line p=1", Shot.Type.FLAT, 1.0, Vector3(2.5, 0.95, 12.3), Vector3(3.7, 0, -10.8), 1.0, hard)
	_monte("SLICE", Shot.Type.SLICE, 0.6, Vector3(-2.5, 0.7, 12.3), Vector3(-2.0, 0, -9.0), 1.0, hard)
	_monte("DROP", Shot.Type.DROP, 0.5, Vector3(1.0, 0.8, 9.0), Vector3(-2.0, 0, -2.2), 1.0, hard)
	_monte("LOB", Shot.Type.LOB, 0.3, Vector3(1.0, 0.8, 12.5), Vector3(-1.0, 0, -10.3), 1.0, hard)
	_monte_serve("SERVE FLAT T", Shot.Type.SERVE_FLAT, 0.7, Vector3(-0.45, 0, -5.75), hard)
	_monte_serve("SERVE FLAT wide", Shot.Type.SERVE_FLAT, 0.7, Vector3(-3.6, 0, -5.2), hard)
	_monte_serve("SERVE KICK", Shot.Type.SERVE_KICK, 0.6, Vector3(-2.0, 0, -5.2), hard)
	_monte_serve("SERVE SLICE", Shot.Type.SERVE_SLICE, 0.6, Vector3(-3.4, 0, -5.0), hard)
	var t0 := Time.get_ticks_usec()
	for i in 50:
		ShotSolver.plan(Vector3(2.5, 0.95, 12.3), Vector3(-2.8, 0, -9.5), 30.0, 280.0, 0.0, 0.0, 0.2)
	print("solver avg ms: ", (Time.get_ticks_usec() - t0) / 50000.0)
	quit()


func _kmh(v: float) -> float:
	return snappedf(v * 3.6, 0.1)


func _serve_case(label: String, type: int, power: float, target: Vector3, surf: Dictionary) -> void:
	var prm := Shot.params(type, power)
	var p0 := Vector3(1.0, 2.75, 12.1)
	var r := ShotSolver.plan(p0, target, prm["speed"], prm["top"], prm["side"], prm["gyro"], prm["clear"])
	if not r.get("ok", false):
		print(label, " -> NO SOLUTION")
		return
	var s := BallPhysics.State.new()
	s.pos = p0
	s.vel = r["vel"]
	s.spin = r["spin"]
	var v_before := 0.0
	var v_after := 0.0
	var apex2 := 0.0
	var at_base := Vector3.ZERO
	var v_base := 0.0
	var done_b := false
	for i in 400:
		var pv := s.vel.length()
		var ev := BallPhysics.step(s, surf)
		if ev & BallPhysics.EV_BOUNCE and not done_b:
			done_b = true
			v_before = pv
			v_after = s.vel.length()
		elif done_b:
			apex2 = maxf(apex2, s.pos.y)
			if s.pos.z < -12.4 and v_base == 0.0:
				v_base = s.vel.length()
				at_base = s.pos
			if ev & BallPhysics.EV_BOUNCE: break
	print(label, ": v0=", _kmh(prm["speed"]), " elev=", snappedf(rad_to_deg(r["elev"]), 0.01), "° clear=", snappedf(r["clear"], 0.01),
		" land=", r["land"].snapped(Vector3.ONE * 0.01), " t=", snappedf(r["t"], 0.01),
		" | pre-bounce=", _kmh(v_before), " post=", _kmh(v_after), " at-returner=", _kmh(v_base), " pos=", at_base.snapped(Vector3.ONE * 0.01), " apex2=", snappedf(apex2, 0.01))


func _rally_case(type: int, power: float, surf: Dictionary) -> void:
	var prm := Shot.params(type, power)
	var p0 := Vector3(1.5, 0.95, 12.3)
	var target := Vector3(-2.0, 0, -9.5)
	if type == Shot.Type.DROP:
		target = Vector3(-2.0, 0, -2.3)
		p0 = Vector3(1.5, 0.8, 9.0)
	if type == Shot.Type.LOB:
		target = Vector3(-1.0, 0, -10.5)
	var r := ShotSolver.plan(p0, target, prm["speed"], prm["top"], prm["side"], prm["gyro"], prm["clear"], prm["arc"])
	if not r.get("ok", false):
		print(Shot.NAMES[type], " -> NO SOLUTION")
		return
	var s := BallPhysics.State.new()
	s.pos = p0
	s.vel = r["vel"]
	s.spin = r["spin"]
	var v_before := 0.0
	var v_after := 0.0
	var apex2 := 0.0
	var b1 := Vector3.ZERO
	var b2 := Vector3.ZERO
	var nb := 0
	var spin_after := 0.0
	for i in 900:
		var pv := s.vel.length()
		var ev := BallPhysics.step(s, surf)
		if ev & BallPhysics.EV_BOUNCE:
			nb += 1
			if nb == 1:
				v_before = pv
				v_after = s.vel.length()
				b1 = s.bounce_pos
				spin_after = s.spin.length() * 9.549
			else:
				b2 = s.bounce_pos
				break
		elif nb == 1:
			apex2 = maxf(apex2, s.pos.y)
	print(Shot.NAMES[type], " [", surf["name"], "] v0=", _kmh(r["speed"]), " elev=", snappedf(rad_to_deg(r["elev"]), 0.1), "° clear=", snappedf(r["clear"], 0.01),
		" apex=", snappedf(r["apex"], 0.01), " t=", snappedf(r["t"], 0.01), " land=", b1.snapped(Vector3.ONE * 0.01),
		" | pre=", _kmh(v_before), " post=", _kmh(v_after), " apex2=", snappedf(apex2, 0.01), " b2=", b2.snapped(Vector3.ONE * 0.01), " rpm_after=", int(spin_after))


func _monte(label: String, type: int, power: float, p0: Vector3, target: Vector3, d: float, surf: Dictionary) -> void:
	var prm := Shot.params(type, power)
	var r := ShotSolver.plan(p0, target, prm["speed"], prm["top"], prm["side"], prm["gyro"], prm["clear"], prm["arc"])
	if not r.get("ok", false):
		print(label, " -> NO SOLUTION")
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = 12345
	var n := 600
	var net := 0
	var long := 0
	var wide := 0
	var ok := 0
	var spread := 0.0
	for i in n:
		var v := ShotSolver.perturb(r["vel"], deg_to_rad(rng.randfn(0.0, prm["sig_az"] * d)), deg_to_rad(rng.randfn(0.0, prm["sig_el"] * d)), 1.0 + rng.randfn(0.0, prm["sig_v"] * d))
		var f := ShotSolver.fly(p0, v, r["spin"])
		if f["clear"] < -BallPhysics.R * 0.35:
			net += 1
		elif Court.in_singles(f["land"], -1):
			ok += 1
			spread += (f["land"] - target).length()
		elif absf(f["land"].x) > Court.SINGLES_HALF_W + Court.LINE_TOUCH:
			wide += 1
		else:
			long += 1
	print(label, ": speed=", _kmh(r["speed"]), " clear=", snappedf(r["clear"], 0.01), " IN=", snappedf(100.0 * ok / n, 0.1), "% net=", snappedf(100.0 * net / n, 0.1), "% long=", snappedf(100.0 * long / n, 0.1), "% wide=", snappedf(100.0 * wide / n, 0.1), "% avg-miss=", snappedf(spread / maxf(ok, 1), 0.01), "m")


func _monte_serve(label: String, type: int, power: float, target: Vector3, surf: Dictionary) -> void:
	var prm := Shot.params(type, power)
	var p0 := Vector3(1.0, 2.75, 12.1)
	var r := ShotSolver.plan(p0, target, prm["speed"], prm["top"], prm["side"], prm["gyro"], prm["clear"])
	if not r.get("ok", false):
		print(label, " -> NO SOLUTION")
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = 999
	var n := 600
	var net := 0
	var ok := 0
	var fault := 0
	for i in n:
		var v := ShotSolver.perturb(r["vel"], deg_to_rad(rng.randfn(0.0, prm["sig_az"])), deg_to_rad(rng.randfn(0.0, prm["sig_el"])), 1.0 + rng.randfn(0.0, prm["sig_v"]))
		var f := ShotSolver.fly(p0, v, r["spin"])
		if f["clear"] < -BallPhysics.R * 0.35:
			net += 1
		elif Court.in_service_box(f["land"], 1, true):
			ok += 1
		else:
			fault += 1
	print(label, ": speed=", _kmh(r["speed"]), " elev=", snappedf(rad_to_deg(r["elev"]), 0.01), " clear=", snappedf(r["clear"], 0.01), " IN=", snappedf(100.0 * ok / n, 0.1), "% net=", snappedf(100.0 * net / n, 0.1), "% out=", snappedf(100.0 * fault / n, 0.1), "%")
