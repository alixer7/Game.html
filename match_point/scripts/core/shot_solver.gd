class_name ShotSolver
extends RefCounted
## حلّال الضربات: يحسب سرعة انطلاق الكرة (اتجاه + زاوية ارتفاع) لتسقط على الهدف
## تحت تأثير المقاومة وماغنوس، بطريقة الرمي العددي (bisection) على نفس محاكاة اللعب.

const DT := BallPhysics.DT
const R := BallPhysics.R


## طيران حتى أول ملامسة للأرض. يعيد: land, t, clear (الخلوص فوق الشبكة), apex, vel
static func fly(p0: Vector3, v0: Vector3, spin0: Vector3, max_t: float = 7.0, wk: float = 1.0) -> Dictionary:
	var p := p0
	var v := v0
	var sp := spin0
	var n := int(max_t / DT)
	var clearance := 99.0
	var apex := p0.y
	for i in n:
		var prev := p
		v += BallPhysics.accel(v, sp, wk) * DT
		p += v * DT
		sp *= BallPhysics.spin_keep(v.length())
		if p.y > apex:
			apex = p.y
		if (prev.z > 0.0) != (p.z > 0.0):
			var k := prev.z / (prev.z - p.z)
			var cx := prev.x + (p.x - prev.x) * k
			if absf(cx) <= Court.POST_X + 0.05:
				clearance = prev.y + (p.y - prev.y) * k - Court.net_height(cx) - R
		if p.y <= R and v.y < 0.0:
			var k2 := 1.0
			if prev.y > p.y and prev.y > R:
				k2 = clampf((prev.y - R) / (prev.y - p.y), 0.0, 1.0)
			var l := prev.lerp(p, k2)
			return {"land": Vector3(l.x, 0.0, l.z), "t": (i + k2) * DT, "clear": clearance, "apex": apex, "vel": v}
	return {"land": Vector3(p.x, 0.0, p.z), "t": max_t, "clear": clearance, "apex": apex, "vel": v}


## متجه الدوران: top (موجب = توب سبين، سالب = باك سبين)، side حول المحور العمودي،
## gyro حول اتجاه الحركة (يؤثر على الارتداد فقط — ضربة الكيك)
static func make_spin(h: Vector3, top: float, side: float, gyro: float) -> Vector3:
	return Vector3(h.z, 0.0, -h.x) * top + Vector3.UP * side + h * gyro


static func _launch(h: Vector3, elev: float, speed: float) -> Vector3:
	var c := cos(elev)
	return Vector3(h.x * c, sin(elev), h.z * c) * speed


## ضربة مستقيمة: السرعة ثابتة ونبحث عن زاوية الارتفاع (الفرع المنخفض)
static func solve_drive(p0: Vector3, target: Vector3, speed: float, top: float, side: float, gyro: float, wk: float = 1.0) -> Dictionary:
	var d := Vector3(target.x - p0.x, 0.0, target.z - p0.z)
	var dist := d.length()
	if dist < 0.5:
		return {"ok": false}
	var h := d / dist
	var res := {}
	var elev := 0.0
	var lo := deg_to_rad(-32.0)
	var hi := deg_to_rad(36.0)
	for outer in 3:
		var spin := make_spin(h, top, side, gyro)
		var f_hi: Dictionary = fly(p0, _launch(h, hi, speed), spin, 7.0, wk)
		if (f_hi["land"] - p0).dot(h) < dist:
			return {"ok": false, "reach": false}
		var a := lo
		var b := hi
		var iters := 12 if outer == 0 else 7
		for i in iters:
			elev = (a + b) * 0.5
			res = fly(p0, _launch(h, elev, speed), spin, 7.0, wk)
			if (res["land"] - p0).dot(h) < dist:
				a = elev
			else:
				b = elev
		elev = (a + b) * 0.5
		res = fly(p0, _launch(h, elev, speed), spin, 7.0, wk)
		# تصحيح الانحراف الجانبي الناتج عن الدوران الجانبي
		var miss: Vector3 = res["land"] - Vector3(target.x, 0.0, target.z)
		var lateral := miss.dot(Vector3(h.z, 0.0, -h.x))
		if absf(lateral) < 0.03:
			break
		h = h.rotated(Vector3.UP, -atan2(lateral, dist))
		lo = elev - deg_to_rad(1.5)
		hi = elev + deg_to_rad(1.5)
	var spin_f := make_spin(h, top, side, gyro)
	return {"ok": true, "vel": _launch(h, elev, speed), "spin": spin_f, "elev": elev, "speed": speed,
		"clear": res["clear"], "land": res["land"], "t": res["t"], "apex": res["apex"], "h": h}


## ضربة قوسية: زاوية الارتفاع ثابتة ونبحث عن السرعة (لوب، دروب، وحالات الطوارئ)
static func solve_arc(p0: Vector3, target: Vector3, elev: float, top: float, side: float, gyro: float, wk: float = 1.0) -> Dictionary:
	var d := Vector3(target.x - p0.x, 0.0, target.z - p0.z)
	var dist := d.length()
	if dist < 0.3:
		return {"ok": false}
	var h := d / dist
	var res := {}
	var speed := 0.0
	var lo := 2.5
	var hi := 62.0
	for outer in 3:
		var spin := make_spin(h, top, side, gyro)
		var a := lo
		var b := hi
		var iters := 12 if outer == 0 else 7
		for i in iters:
			speed = (a + b) * 0.5
			res = fly(p0, _launch(h, elev, speed), spin, 7.0, wk)
			if (res["land"] - p0).dot(h) < dist:
				a = speed
			else:
				b = speed
		speed = (a + b) * 0.5
		res = fly(p0, _launch(h, elev, speed), spin, 7.0, wk)
		var miss: Vector3 = res["land"] - Vector3(target.x, 0.0, target.z)
		var lateral := miss.dot(Vector3(h.z, 0.0, -h.x))
		if absf(lateral) < 0.03:
			break
		h = h.rotated(Vector3.UP, -atan2(lateral, dist))
		lo = maxf(speed - 2.0, 1.0)
		hi = speed + 2.0
	var spin_f := make_spin(h, top, side, gyro)
	return {"ok": true, "vel": _launch(h, elev, speed), "spin": spin_f, "elev": elev, "speed": speed,
		"clear": res["clear"], "land": res["land"], "t": res["t"], "apex": res["apex"], "h": h}


## التخطيط الكامل: يحاول الضربة المستقيمة بالسرعة المطلوبة؛ إن لم تعبر الشبكة بالهامش
## المطلوب يرفع القوس ويخفّض السرعة حتى تصبح ممكنة فيزيائياً.
static func plan(p0: Vector3, target: Vector3, speed: float, top: float, side: float, gyro: float,
		min_clear: float, arc_elev: float = -1.0, wk: float = 1.0) -> Dictionary:
	if arc_elev > 0.0:
		var ra := solve_arc(p0, target, arc_elev, top, side, gyro, wk)
		if ra.get("ok", false) and float(ra["clear"]) >= min_clear:
			return ra
		for i in 5:
			var r3 := solve_arc(p0, target, arc_elev + deg_to_rad(6.0) * (i + 1), top, side, gyro, wk)
			if r3.get("ok", false) and float(r3["clear"]) >= min_clear:
				return r3
			ra = r3
		return ra
	var r := solve_drive(p0, target, speed, top, side, gyro, wk)
	if r.get("ok", false) and float(r["clear"]) >= min_clear:
		return r
	# زاوية هندسية دنيا لعبور الشبكة
	var dz := absf(p0.z)
	var need := atan2(Court.NET_H_CENTER + min_clear + R - p0.y, maxf(dz, 0.3))
	var base: float = maxf(need, float(r["elev"]) if r.get("ok", false) else need) + deg_to_rad(1.0)
	var last := r
	for i in 8:
		var r2 := solve_arc(p0, target, base + deg_to_rad(2.5) * i, top, side, gyro, wk)
		if r2.get("ok", false):
			last = r2
			if float(r2["clear"]) >= min_clear and float(r2["speed"]) <= speed * 1.02:
				return r2
	return last


## تطبيق خطأ التنفيذ: انحراف أفقي (موجب = يمين الضارب)، خطأ ارتفاع، ومعامل سرعة
static func perturb(vel: Vector3, az_err: float, el_err: float, speed_scale: float) -> Vector3:
	var hv := Vector2(vel.x, vel.z)
	var hs := hv.length()
	if hs < 0.001:
		return vel
	var el := atan2(vel.y, hs) + el_err
	var sp := vel.length() * speed_scale
	var hd := (hv / hs).rotated(az_err)
	return Vector3(hd.x * cos(el), sin(el), hd.y * cos(el)) * sp
