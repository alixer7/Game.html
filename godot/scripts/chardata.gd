extends RefCounted
## Character definitions: stats, guards, frame data, strings, specials, EX, Wrath, executions, AI.

const PZ = preload("res://scripts/pose.gd")

const ROSTER := ["vorgath", "nyxara", "kharos", "ossirah"]
const BOX := {high = [0.2, 0.84, 1.32, 1.8], mid = [0.2, 0.92, 0.76, 1.38], low = [0.22, 0.98, 0.0, 0.5], overhead = [0.2, 0.92, 0.92, 1.9], throw = [0.1, 0.78, 0.5, 1.7], unblockable = [0.1, 0.85, 0.4, 1.9]}
const LVL_AR := {high = "عالية", mid = "متوسطة", low = "منخفضة", overhead = "علوية", throw = "مسكة", unblockable = "لا تُصد", proj = "مقذوف"}

static var CACHE := {}

static func M(o: Dictionary) -> Dictionary:
	var m := {type = "normal", startup = 10, active = 3, recovery = 15}
	m.merge(o, true)
	m.total = m.startup + m.active + m.recovery
	if not m.has("hits"):
		m.hits = [o.hit.duplicate()] if o.has("hit") else []
	var fa := 9999
	var la := 0
	for h in m.hits:
		if not h.has("f"): h.f = m.startup
		if not h.has("a"): h.a = m.active
		if not h.has("lvl"): h.lvl = "mid"
		if not h.has("box"): h.box = BOX[h.lvl]
		if not h.has("hs"): h.hs = 18
		if not h.has("bs"): h.bs = 12
		if not h.has("push"): h.push = 0.05
		if not h.has("dmg"): h.dmg = 30
		if not h.has("power"): h.power = clampf(h.dmg / 60.0, 0.3, 1.5)
		fa = mini(fa, h.f)
		la = maxi(la, h.f + h.a - 1)
	m.firstActive = fa if m.hits.size() > 0 else m.startup
	m.lastActive = la if m.hits.size() > 0 else m.startup + m.active - 1
	return m

static func adv_of(m: Dictionary, key: String):
	if m.hits.is_empty() or m.get("proj", false): return null
	var h: Dictionary = m.hits[m.hits.size() - 1]
	if h.lvl == "throw" or m.get("grab", false): return null
	if key == "hit" and (h.has("launch") or h.has("kd")): return "KD"
	return (h.hs if key == "hit" else h.bs) - (m.total - h.f)

static func jw(F, k: String) -> Vector3:
	return F.rig.joint_world(k)

static func fire_hand(F, k: String) -> void:
	VFX.fire(jw(F, k), 0.6)

static func normals(spd: int, dm: float) -> Dictionary:
	var d := func(x): return roundi(x * dm)
	return {
		"1": M({name = "Jab", ar = "لكمة سريعة", cmd = "1", startup = 7 + spd, active = 2, recovery = 11, hit = {lvl = "high", dmg = d.call(28), hs = 17, bs = 13, push = 0.035}, anim = func(S, m): return PZ.jab(S.guard, m), voice = "grunt", pros = "أسرع ضربة واقفة وآمنة عند الصد", cons = "عالية: تخطئ الخصم المنخفض، ضرر قليل"}),
		"2": M({name = "Cross", ar = "لكمة مستقيمة", cmd = "2", startup = 10 + spd, active = 3, recovery = 15, hit = {lvl = "high", dmg = d.call(44), hs = 20, bs = 15, push = 0.055}, anim = func(S, m): return PZ.cross(S.guard, m), voice = "atk", pros = "مدى جيد وضرر متوسط", cons = "عالية، -3 عند الصد"}),
		"3": M({name = "Front Kick", ar = "ركلة أمامية", cmd = "3", startup = 11 + spd, active = 3, recovery = 17, hit = {lvl = "mid", dmg = d.call(45), hs = 21, bs = 15, push = 0.07}, anim = func(S, m): return PZ.fkick(S.guard, m), voice = "atk", trail = ["snR", 11, 15], pros = "متوسطة: يجب صدها واقفاً، مدى جيد", cons = "-5 عند الصد"}),
		"4": M({name = "Roundhouse", ar = "ركلة دائرية", cmd = "4", startup = 15 + spd, active = 3, recovery = 20, hit = {lvl = "high", dmg = d.call(66), hs = 25, bs = 16, push = 0.1, power = 1.0}, anim = func(S, m): return PZ.round_k(S.guard, m), voice = "atk2", trail = ["snR", 11, 19], pros = "ضرر عالٍ ومدى طويل، تدفع الخصم بعيداً", cons = "بطيئة، عالية، -6 عند الصد"}),
		"d1": M({name = "Low Jab", ar = "لكمة منخفضة", cmd = "↓ + 1", crouch = true, startup = 6 + spd, active = 2, recovery = 10, hit = {lvl = "mid", box = [0.2, 0.82, 0.6, 1.12], dmg = d.call(18), hs = 15, bs = 12, push = 0.03}, anim = func(S, m): return PZ.cjab(S.guard, S.crouch, m), voice = "grunt", pros = "أسرع ضربة في اللعبة وتصيب المنخفضين", cons = "ضرر ضعيف جداً ومدى قصير"}),
		"d2": M({name = "Uppercut", ar = "لكمة صاعدة", cmd = "↓ + 2", crouch = true, startup = 9 + spd, active = 4, recovery = 24, hit = {lvl = "mid", box = [0.12, 0.78, 0.75, 2.2], dmg = d.call(72), hs = 30, bs = 12, launch = 0.165, push = 0.02, power = 1.2}, anim = func(S, m): return PZ.cupper(S.guard, S.crouch, m), voice = "atk2", pros = "ترفع الخصم في الهواء لبدء كومبو، ممتازة ضد القفز", cons = "-15 عند الصد: عقاب مؤكد"}),
		"d3": M({name = "Shin Kick", ar = "ركلة الساق", cmd = "↓ + 3", crouch = true, startup = 8 + spd, active = 2, recovery = 13, hit = {lvl = "low", box = [0.25, 0.98, 0.0, 0.45], dmg = d.call(24), hs = 16, bs = 12, push = 0.03}, anim = func(S, m): return PZ.clow(S.guard, S.crouch, m), voice = "grunt", pros = "منخفضة سريعة لكسر الصد الواقف", cons = "ضرر قليل"}),
		"d4": M({name = "Sweep", ar = "كنسة", cmd = "↓ + 4", crouch = true, startup = 12 + spd, active = 3, recovery = 26, hit = {lvl = "low", box = [0.25, 1.15, 0.0, 0.35], dmg = d.call(52), kd = true, bs = 10, push = 0.03, power = 0.9}, anim = func(S, m): return PZ.sweep(S.guard, S.crouch, m), voice = "atk", trail = ["snR", 10, 15], pros = "تُسقط الخصم من مسافة", cons = "-18 عند الصد"}),
		"f2": M({name = "Skull Breaker", ar = "كاسرة الجمجمة", cmd = "→ + 2", startup = 20 + spd, active = 3, recovery = 16, hit = {lvl = "overhead", dmg = d.call(58), hs = 22, bs = 16, push = 0.05, power = 1.0}, motion = func(f, F): return 0.02 if f < 18 else 0.0, anim = func(S, m): return PZ.hammer(S.guard, m), voice = "atk2", pros = "علوية: تكسر الصد المنخفض", cons = "بطيئة وسهلة الملاحظة"}),
		"b3": M({name = "Long Kick", ar = "ركلة طويلة", cmd = "← + 3", startup = 12 + spd, active = 3, recovery = 18, hit = {lvl = "mid", box = [0.35, 1.24, 0.55, 1.08], dmg = d.call(40), hs = 18, bs = 14, push = 0.06}, anim = func(S, m): return PZ.sidekick(S.guard, m), voice = "atk", pros = "أطول مدى بين الضربات الأساسية", cons = "-6 عند الصد"}),
		"f4": M({name = "Rising Knee", ar = "ركبة متقدمة", cmd = "→ + 4", startup = 16 + spd, active = 3, recovery = 14, hit = {lvl = "mid", box = [0.12, 0.78, 0.78, 1.45], dmg = d.call(55), hs = 22, bs = 18, push = 0.05, power = 1.0}, motion = func(f, F): return 0.045 if f > 4 and f < 18 else 0.0, anim = func(S, m): return PZ.knee(S.guard, m), voice = "atk2", pros = "+2 عند الصد وتتقدم للأمام", cons = "بطيئة الانطلاق"}),
		"b2": M({name = "Sky Breaker", ar = "مضادة للقفز", cmd = "← + 2", startup = 8 + spd, active = 4, recovery = 18, hit = {lvl = "high", box = [0.08, 0.72, 1.25, 2.4], dmg = d.call(48), hs = 22, bs = 12, airLaunch = 0.14, push = 0.03}, anim = func(S, m): return PZ.elbow(S.guard, m, {ex = {R = [0.42, 1.85, 0.1], RE = [1, -0.2, 0.2]}}), voice = "atk", pros = "مضادة للقفز ممتازة وتطلق الخصم الطائر", cons = "عالية: تخطئ المنخفضين، -9"}),
		"j1": M({name = "Air Strike", ar = "لكمة جوية", cmd = "↑ + 1", air = true, startup = 6, active = 7, recovery = 8, hit = {lvl = "overhead", box = [0.1, 0.82, 0.45, 1.45], dmg = d.call(38), hs = 19, bs = 13, push = 0.03}, anim = func(S, m): return PZ.jpunch(S.guard, S.jump, m), voice = "grunt", pros = "علوية، تبدأ كومبو بعد القفز", cons = "عرضة للضربات المضادة للقفز"}),
		"j2": M({name = "Air Hammer", ar = "مطرقة جوية", cmd = "↑ + 2", air = true, startup = 8, active = 6, recovery = 8, hit = {lvl = "overhead", box = [0.1, 0.88, 0.35, 1.4], dmg = d.call(48), hs = 21, bs = 14, push = 0.03}, anim = func(S, m): return PZ.jpunch(S.guard, S.jump, m, {t = [0.82, 1.05, 0.02]}), voice = "atk", pros = "ضرر أعلى من اللكمة الجوية", cons = "أبطأ قليلاً"}),
		"j3": M({name = "Air Kick", ar = "ركلة جوية", cmd = "↑ + 3", air = true, startup = 7, active = 8, recovery = 8, hit = {lvl = "overhead", box = [0.1, 0.95, 0.05, 1.0], dmg = d.call(46), hs = 20, bs = 13, push = 0.04}, anim = func(S, m): return PZ.jkick(S.guard, S.jump, m), voice = "grunt", pros = "مدى جيد من الأعلى", cons = "تحتاج توقيتاً دقيقاً"}),
		"j4": M({name = "Diving Kick", ar = "ركلة غاطسة", cmd = "↑ + 4", air = true, startup = 9, active = 8, recovery = 8, hit = {lvl = "overhead", box = [0.1, 1.0, -0.1, 0.9], dmg = d.call(56), hs = 22, bs = 14, push = 0.06, airKd = true}, anim = func(S, m): return PZ.jkick(S.guard, S.jump, m, {t = [0.85, 0.1, 0.03]}), voice = "atk", trail = ["snR", 9, 16], pros = "ضرر عالٍ وتُسقط الخصم الطائر", cons = "أبطأ ضربة جوية"}),
		"throw": M({name = "Throw", ar = "مسكة أمامية", cmd = "TH", type = "throw", startup = 7, active = 2, recovery = 26, hit = {lvl = "throw", box = [0.1, 0.8, 0.5, 1.7], dmg = 100}, anim = func(S, m): return [[0, S.guard], [7, PZ.P(S.guard, {"+root": [0.1, -0.02, 0], "L": [0.68, 1.45, -0.08], "R": [0.66, 1.42, 0.1], "LE": [0, -1, -0.6], "RE": [0, -1, 0.6]}), "out"], [12, PZ.P(S.guard, {L = [0.5, 1.45, -0.08], R = [0.48, 1.42, 0.1]})], [35, S.guard]], pros = "لا تُصد، تتجاوز الدفاع", cons = "يمكن الإفلات منها بالضغط على TH، مدى قصير جداً"}),
		"bthrow": M({name = "Back Throw", ar = "مسكة خلفية", cmd = "← + TH", type = "throw", startup = 7, active = 2, recovery = 26, hit = {lvl = "throw", box = [0.1, 0.8, 0.5, 1.7], dmg = 100, back = true}, anim = func(S, m): return [[0, S.guard], [7, PZ.P(S.guard, {"+root": [0.1, -0.02, 0], "L": [0.68, 1.45, -0.08], "R": [0.66, 1.42, 0.1]}), "out"], [35, S.guard]], pros = "ترمي الخصم خلفك وتبدّل المواقع", cons = "يمكن الإفلات منها"}),
	}

# ====================================================================== KHAROS
static func _kh_tick_fire(F, f: int) -> void:
	if f > 3 and f < 14: fire_hand(F, "wrR")
static func _kh_skull_tick(F, f: int) -> void:
	if f > 3 and f < 17: fire_hand(F, "wrR")
static func _kh_pyre_tick(F, f: int) -> void:
	if f > 4 and f < 22:
		fire_hand(F, "wrR")
		VFX.fire(jw(F, "chest") + Vector3(0, -0.6, 0), 1.2)
static func _kh_pyre_ex_tick(F, f: int) -> void:
	if f > 3 and f < 22:
		fire_hand(F, "wrR"); fire_hand(F, "wrL")
		VFX.fire(jw(F, "chest") + Vector3(0, -0.6, 0), 1.5)
static func _kh_rush_tick(F, f: int) -> void:
	if f > 5 and f < 24:
		VFX.fire(jw(F, "wrR"), 0.9)
		VFX.fire(Vector3(F.x, 0.3, 0), 0.8)
static func _kh_slam_tick(F, f: int) -> void:
	if f > 4 and f < 22: fire_hand(F, "wrR"); fire_hand(F, "wrL")
static func _kh_slam_ev(F, big: bool) -> void:
	G.spawn_proj(F, {type = "wave", vx = 0.16 if big else 0.14, dmg = 45 if big else 38, lvl = "low", kd = true, life = 34 if big else 30, x0 = 0.9, big = big})
	G.cam_shake(0.6 if big else 0.5)
	VFX.ring(Vector3(F.x + F.facing * 0.9, 0.05, 0), Color(2, 0.6, 0.1), 3.4 if big else 2.6, 0.4, "ground")
	SFX.play("boom", 0.8)

static func _kharos(spd: int, dm: float, S: Dictionary) -> Dictionary:
	var d := func(x): return roundi(x * dm)
	var g: PackedFloat32Array = S.guard
	var o := {}
	o.k11 = M({name = "Ember Jab", ar = "وخزة الجمر", cmd = "1, 1", startup = 6, active = 2, recovery = 12, hit = {lvl = "high", dmg = d.call(22), hs = 16, bs = 12, push = 0.03}, anim = func(S2, m): return PZ.jab2(S2.guard, m), chain = {"2": "k112"}, voice = "grunt"})
	o.k112 = M({name = "Searing Chain", ar = "سلسلة الحرق", cmd = "1, 1, 2", type = "string", startup = 10, active = 3, recovery = 21, hit = {lvl = "mid", dmg = d.call(56), hs = 26, bs = 16, push = 0.13, power = 1.1, fire = true}, cancel = true, tick = _kh_tick_fire, anim = func(S2, m): return PZ.hook(S2.guard, m, {t = [0.78, 1.38, -0.12]}), voice = "atk2", trail = ["faR", 8, 13], pros = "سلسلة سريعة تنتهي بضربة نارية متوسطة، قابلة للإلغاء بحركة خاصة", cons = "-8 عند الصد"})
	o.k21 = M({name = "Cinder Hook", ar = "خطّاف الرماد", cmd = "2, 1", startup = 8, active = 3, recovery = 14, hit = {lvl = "high", dmg = d.call(30), hs = 18, bs = 13, push = 0.03}, anim = func(S2, m): return PZ.hookL(S2.guard, m), chain = {"4": "k214"}, voice = "grunt"})
	o.k214 = M({name = "Ashen Rise", ar = "نهوض الرماد", cmd = "2, 1, 4", type = "string", startup = 11, active = 4, recovery = 22, hit = {lvl = "mid", box = [0.15, 0.95, 0.7, 2.1], dmg = d.call(50), hs = 30, bs = 12, launch = 0.17, push = 0.02, power = 1.1}, anim = func(S2, m): return PZ.fkick(S2.guard, m, {t = [0.6, 1.55, 0.03], ex = {"+hip": [-0.45, 0.25, 0]}}), voice = "atk2", trail = ["snR", 9, 15], pros = "ترفع الخصم لكومبو جوي طويل", cons = "-15 عند الصد"})
	o.kb33 = M({name = "Grave Step", ar = "خطوة القبر", cmd = "← + 3, 3", type = "string", startup = 9, active = 2, recovery = 15, hit = {lvl = "low", dmg = d.call(30), hs = 18, bs = 13, push = 0.04}, cancel = true, anim = func(S2, m): return PZ.lowkick(S2.guard, m), voice = "grunt", pros = "سلسلة منتصف-منخفض تخدع الدفاع، قابلة للإلغاء", cons = "-4 عند الصد"})
	o.kf24 = M({name = "Funeral Wheel", ar = "عجلة الجنازة", cmd = "→ + 2, 4", type = "string", startup = 12, active = 3, recovery = 24, hit = {lvl = "high", dmg = d.call(55), kd = true, bs = 15, push = 0.08, power = 1.1}, anim = func(S2, m): return PZ.round_k(S2.guard, m), voice = "atk2", trail = ["snR", 8, 16], pros = "تُكمل العلوية بإسقاط قوي", cons = "-12 عند الصد، عالية"})
	var skull_anim := func(S2, m): return PZ.kstrike(S2.guard, m, PZ.P(S2.guard, {"+chest": [-0.12, -0.4, 0], "R": [-0.15, 1.62, 0.32], "RE": [0, -1, 1]}), PZ.P(S2.guard, {"+root": [0.12, -0.04, 0], "+hip": [0.05, 0.25, 0], "+chest": [0.14, 0.5, 0], "R": [0.86, 1.5, 0.02], "RE": [0, -1, 0.3], "rw": [-0.9, 0, 0]}), {cf = 0.6})
	o.hellskull = M({name = "Hellskull", ar = "جمجمة الجحيم", cmd = "↓ ← + 1", type = "special", startup = 16, active = 1, recovery = 30, proj = true, ev = [[16, func(F): G.spawn_proj(F, {type = "skull", vx = 0.17, dmg = d.call(55), lvl = "mid", hs = 22, bs = 14})]], tick = _kh_skull_tick, anim = skull_anim, voice = "atk", pros = "مقذوف متوسط يتحكم بالمسافة", cons = "استرجاع طويل إذا قفز الخصم فوقه"})
	o.hellskullEX = M({name = "Hellskull EX", ar = "جمجمة الجحيم المعززة", cmd = "↓ ← + 1 + BL", type = "ex", startup = 14, active = 1, recovery = 28, proj = true, ev = [[14, func(F): G.spawn_proj(F, {type = "skull", vx = 0.22, dmg = d.call(72), lvl = "mid", hs = 30, bs = 16, launch = 0.17, big = true})]], tick = _kh_skull_tick, anim = skull_anim, voice = "atk2"})
	var pyre_anim := func(S2, m): return [[0, S2.guard], [5, PZ.P(S2.crouch, {R = [0.25, 0.8, 0.2]}), "out"], [12, PZ.P(S2.guard, {"root": [0.12, 1.05, 0], "+hip": [-0.2, 0.4, 0], "+chest": [-0.25, 0.55, 0], "R": [0.42, 2.25, 0.02], "RE": [-0.6, -1, 0.3], "rf": [-0.1, 0.45, 0.12], "lfa": [0, 0.7, 0], "rfa": [0, 0.7, 0]}), "out"], [24, PZ.P(S2.guard, {"root": [0.1, 1.02, 0], "+chest": [-0.2, 0.4, 0], "R": [0.35, 2.15, 0.05], "rf": [-0.1, 0.35, 0.12]})], [52, S2.guard]]
	o.pyre = M({name = "Pyre Rise", ar = "صعود المحرقة", cmd = "↓ → + 2", type = "special", startup = 6, active = 12, recovery = 34, inv = [1, 9], hits = [{f = 6, a = 4, lvl = "mid", box = [0.05, 0.82, 0.6, 2.1], dmg = d.call(40), hs = 26, bs = 10, launch = 0.12, fire = true}, {f = 11, a = 7, lvl = "mid", box = [0.0, 0.75, 1.0, 2.8], dmg = d.call(50), hs = 30, bs = 10, launch = 0.19, fire = true, power = 1.3}], motion = func(f, F): return 0.05 if f > 4 and f < 14 else 0.0, rise = [6, 18], tick = _kh_pyre_tick, anim = pyre_anim, voice = "atk2", pros = "محصّنة في بدايتها — أفضل وسيلة للخروج من الضغط", cons = "-34 عند الصد: عقاب كامل مؤكد"})
	o.pyreEX = M({name = "Pyre Rise EX", ar = "صعود المحرقة المعزز", cmd = "↓ → + 2 + BL", type = "ex", startup = 5, active = 14, recovery = 32, inv = [1, 18], hits = [{f = 5, a = 3, lvl = "mid", box = [0.05, 0.82, 0.6, 2.1], dmg = d.call(35), hs = 26, bs = 10, launch = 0.12, fire = true}, {f = 9, a = 4, lvl = "mid", box = [0.0, 0.75, 0.8, 2.6], dmg = d.call(35), hs = 26, bs = 10, launch = 0.14, fire = true}, {f = 14, a = 5, lvl = "mid", box = [0.0, 0.75, 1.0, 2.9], dmg = d.call(55), hs = 30, bs = 10, launch = 0.2, fire = true, power = 1.4}], motion = func(f, F): return 0.05 if f > 4 and f < 14 else 0.0, rise = [5, 18], tick = _kh_pyre_ex_tick, anim = pyre_anim, voice = "atk2"})
	var rush_anim := func(S2, m): return [[0, S2.guard], [6, PZ.P(S2.guard, {"+root": [-0.05, -0.06, 0], "+chest": [0, -0.3, 0], "R": [-0.1, 1.35, 0.3]}), "io"], [13, PZ.P(S2.guard, {"+root": [0.25, -0.14, 0], "+hip": [0.35, 0.3, 0], "+chest": [0.25, 0.4, 0], "R": [1.0, 1.3, 0.0], "RE": [0, -1, 0.3], "L": [0.1, 1.3, -0.2], "lf": [0.65, 0.1, -0.12], "rf": [-0.55, 0.14, 0.16], "rfa": [-0.5, 0.5, 0]}), "out"], [23, PZ.P(S2.guard, {"+root": [0.25, -0.12, 0], "+hip": [0.35, 0.3, 0], "+chest": [0.25, 0.4, 0], "R": [1.0, 1.32, 0.0], "lf": [0.6, 0.1, -0.12], "rf": [-0.5, 0.14, 0.16]})], [41, S2.guard]]
	o.rush = M({name = "Ember Rush", ar = "اندفاع الجمر", cmd = "← → + 3", type = "special", startup = 13, active = 10, recovery = 18, hit = {lvl = "mid", box = [0.05, 1.0, 0.7, 1.6], dmg = d.call(70), hs = 26, bs = 18, push = 0.14, power = 1.2, fire = true}, motion = func(f, F): return 0.16 if f > 5 and f < 22 else (0.05 if f < 26 else 0.0), tick = _kh_rush_tick, anim = rush_anim, voice = "atk2", pros = "تقطع مسافة كبيرة بسرعة، آمنة نسبياً", cons = "-9 عند الصد، يمكن تفاديها بالقفز"})
	o.rushEX = M({name = "Ember Rush EX", ar = "اندفاع الجمر المعزز", cmd = "← → + 3 + BL", type = "ex", startup = 12, active = 10, recovery = 16, armor = [1, 14, 1], hit = {lvl = "mid", box = [0.05, 1.0, 0.7, 1.6], dmg = d.call(92), hs = 32, bs = 20, launch = 0.15, power = 1.3, fire = true}, motion = func(f, F): return 0.18 if f > 5 and f < 22 else (0.05 if f < 26 else 0.0), tick = _kh_rush_tick, anim = rush_anim, voice = "atk2"})
	var slam_anim := func(S2, m): return PZ.kstrike(S2.guard, m, PZ.P(S2.guard, {"+root": [-0.04, 0.1, 0], "+hip": [-0.2, 0.2, 0], "+chest": [-0.3, 0.25, 0], "R": [0.0, 2.15, 0.12], "L": [0.05, 2.1, -0.12], "RE": [0, 0.2, 1], "LE": [0, 0.2, -1]}), PZ.P(S2.guard, {"root": [0.22, 0.58, 0], "+hip": [0.55, 0.3, 0], "+spine": [0.3, 0, 0], "+chest": [0.3, 0.25, 0], "R": [0.82, 0.22, 0.04], "L": [0.8, 0.24, -0.1], "lf": [0.5, 0.08, -0.2], "rf": [-0.35, 0.08, 0.22], "nod": 0.5}), {cf = 0.6, R = S2.crouch})
	o.slam = M({name = "Brimstone Slam", ar = "ضربة الكبريت", cmd = "↓ ↓ + 4", type = "special", startup = 22, active = 4, recovery = 20, hit = {lvl = "overhead", box = [0.05, 1.05, 0.0, 1.9], dmg = d.call(66), kd = true, bs = 16, push = 0.04, power = 1.3, fire = true}, ev = [[23, func(F): _kh_slam_ev(F, false)]], tick = _kh_slam_tick, anim = slam_anim, voice = "atk2", pros = "علوية قوية + موجة نار منخفضة تزحف على الأرض", cons = "بطيئة جداً، يمكن رؤيتها قادمة"})
	o.slamEX = M({name = "Brimstone Slam EX", ar = "ضربة الكبريت المعززة", cmd = "↓ ↓ + 4 + BL", type = "ex", startup = 18, active = 4, recovery = 18, hit = {lvl = "overhead", box = [0.05, 1.1, 0.0, 1.9], dmg = d.call(70), launch = 0.17, hs = 30, bs = 18, push = 0.02, power = 1.4, fire = true}, ev = [[19, func(F): _kh_slam_ev(F, true)]], tick = _kh_slam_tick, anim = slam_anim, voice = "atk2"})
	return o

# ====================================================================== VORGATH
static func _vg_lance_tick(F, f: int) -> void:
	if f > 5 and f < 18: VFX.blood(jw(F, "wrR"), F.facing, 1, {speed = 1.0, mist = false})
static func _vg_geyser_mark(F, big: bool) -> void:
	F.store["gx"] = F.opp.x
	VFX.ring(Vector3(F.opp.x, 0.03, 0), Color(1.4, 0.05, 0.02), 2.2 if big else 1.6, 0.9, "ground", 0.8)
	for i in 6: VFX.blood(Vector3(F.opp.x, 0.05, 0), randf_range(-1, 1), 2, {speed = 1.5, up = 1.3})
static func _vg_charge_tick(F, f: int) -> void:
	if f > 6 and f < 26 and f % 3 == 0: VFX.dust(Vector3(F.x, 0, 0), 3, 0.8)

static func _vorgath(spd: int, dm: float, S: Dictionary) -> Dictionary:
	var d := func(x): return roundi(x * dm)
	var o := {}
	o.v12 = M({name = "Gut Ripper", ar = "ممزّق الأحشاء", cmd = "1, 2", type = "string", startup = 11, active = 3, recovery = 19, hit = {lvl = "mid", dmg = d.call(48), hs = 24, bs = 15, push = 0.12, power = 1.1, slash = true}, cancel = true, anim = func(S2, m): return PZ.hook(S2.guard, m, {t = [0.8, 1.25, -0.1]}), voice = "atk2", trail = ["faR", 9, 14], pros = "سلسلة قصيرة ثقيلة الضرر، قابلة للإلغاء", cons = "-9 عند الصد"})
	o.v22 = M({name = "Hammer Fist", ar = "قبضة المطرقة", cmd = "2, 2", startup = 12, active = 3, recovery = 16, hit = {lvl = "mid", dmg = d.call(42), hs = 22, bs = 15, push = 0.04}, anim = func(S2, m): return PZ.hookL(S2.guard, m, {t = [0.8, 1.3, 0.1]}), chain = {"1": "v221"}, voice = "grunt"})
	o.v221 = M({name = "Ruin", ar = "الخراب", cmd = "2, 2, 1", type = "string", startup = 16, active = 3, recovery = 22, hit = {lvl = "overhead", dmg = d.call(72), kd = true, bs = 14, push = 0.06, power = 1.4}, ev = [[16, func(F): G.cam_shake(0.45); VFX.dust(Vector3(F.x + F.facing * 0.8, 0, 0), 12, 1.2); SFX.play("boom", 0.5)]], anim = func(S2, m): return PZ.hammer(S2.guard, m, {t = [0.88, 0.9, 0.02]}), voice = "roar", pros = "سلسلة تنتهي بضربة علوية مدمرة تُسقط الخصم", cons = "-10 عند الصد، بطيئة"})
	o.b1 = M({name = "Flay Swipe", ar = "مخلب السلخ", cmd = "← + 1", startup = 10, active = 3, recovery = 15, hit = {lvl = "low", box = [0.25, 1.0, 0.0, 0.55], dmg = d.call(34), hs = 18, bs = 13, push = 0.04, slash = true}, anim = func(S2, m): return PZ.kstrike(S2.guard, m, PZ.P(S2.guard, {"+root": [0, -0.15, 0], "+hip": [0.3, -0.2, 0], "R": [0.1, 1.2, 0.4]}), PZ.P(S2.crouch, {"+root": [0.1, -0.05, 0], "+hip": [0.25, 0.5, 0], "+chest": [0.3, 0.5, 0], "R": [0.95, 0.25, -0.15], "RE": [0, 0.3, 1]})), chain = {"2": "vb12"}, voice = "grunt", trail = ["faR", 8, 12], pros = "منخفضة طويلة المدى", cons = "-5 عند الصد"})
	o.vb12 = M({name = "Throne Rise", ar = "نهوض العرش", cmd = "← + 1, 2", type = "string", startup = 11, active = 4, recovery = 24, hit = {lvl = "mid", box = [0.1, 0.85, 0.7, 2.2], dmg = d.call(54), hs = 30, bs = 12, launch = 0.165, power = 1.2}, anim = func(S2, m): return PZ.upper(S2.guard, m), voice = "atk2", pros = "منخفضة ثم رافعة: خليط مزعج للدفاع", cons = "-16 عند الصد"})
	o.vf44 = M({name = "Grave Stomp", ar = "دعسة القبر", cmd = "→ + 4, 4", type = "string", startup = 14, active = 3, recovery = 22, hit = {lvl = "low", box = [0.1, 1.0, 0.0, 0.5], dmg = d.call(58), kd = true, bs = 14, power = 1.2}, ev = [[14, func(F): G.cam_shake(0.35); VFX.dust(Vector3(F.x + F.facing * 0.7, 0, 0), 10, 1.0)]], anim = func(S2, m): return PZ.axe(S2.guard, m, {t = [0.75, 0.1, 0.03]}), voice = "atk2", pros = "تكمل الركبة بدعسة منخفضة تُسقط", cons = "-12 عند الصد"})
	var lance_anim := func(S2, m): return PZ.kstrike(S2.guard, m, PZ.P(S2.guard, {"+root": [-0.06, 0.02, 0], "+chest": [-0.2, -0.45, 0], "R": [-0.35, 1.85, 0.25], "RE": [0, -1, 1]}), PZ.P(S2.guard, {"+root": [0.15, -0.04, 0], "+hip": [0.1, 0.35, 0], "+chest": [0.25, 0.6, 0], "R": [0.92, 1.45, 0.0], "RE": [0, -1, 0.3], "rw": [-0.5, 0, 0]}), {cf = 0.6})
	o.lance = M({name = "Blood Lance", ar = "رمح الدم", cmd = "← → + 1", type = "special", startup = 18, active = 1, recovery = 28, proj = true, ev = [[18, func(F): G.spawn_proj(F, {type = "lance", vx = 0.2, dmg = d.call(58), lvl = "mid", hs = 22, bs = 14})]], tick = _vg_lance_tick, anim = lance_anim, voice = "atk2", pros = "مقذوف متوسط قوي الضرر", cons = "بطيء الانطلاق (18 إطاراً)"})
	o.lanceEX = M({name = "Blood Lance EX", ar = "رماح الدم الثلاثة", cmd = "← → + 1 + BL", type = "ex", startup = 16, active = 1, recovery = 34, proj = true, ev = [[16, func(F): G.spawn_proj(F, {type = "lance", vx = 0.22, dmg = d.call(40), lvl = "mid", hs = 20, bs = 12, y = 1.5})], [22, func(F): G.spawn_proj(F, {type = "lance", vx = 0.22, dmg = d.call(40), lvl = "mid", hs = 20, bs = 12, y = 1.05})], [28, func(F): G.spawn_proj(F, {type = "lance", vx = 0.22, dmg = d.call(45), lvl = "mid", hs = 26, bs = 14, y = 1.3, kd = true})]], anim = lance_anim, voice = "roar"})
	var gey_anim := func(S2, m): return [[0, S2.guard], [8, PZ.P(S2.crouch, {"+root": [0.1, -0.05, 0], "+hip": [0.3, 0.2, 0], "R": [0.7, 0.12, 0.1], "RE": [0, 1, 1], "nod": 0.4}), "out"], [26, PZ.P(S2.crouch, {"+root": [0.1, -0.06, 0], "+hip": [0.3, 0.2, 0], "R": [0.72, 0.1, 0.1], "nod": 0.4})], [34, PZ.P(S2.guard, {"+chest": [-0.2, 0, 0], "R": [0.3, 1.9, 0.3], "L": [0.3, 1.85, -0.3]}), "out"], [45, S2.guard]]
	o.geyser = M({name = "Marrow Geyser", ar = "نافورة النخاع", cmd = "↓ ← + 4", type = "special", startup = 28, active = 1, recovery = 16, proj = true, ev = [[8, func(F): _vg_geyser_mark(F, false)], [28, func(F): G.spawn_proj(F, {type = "geyser", x = F.store.get("gx", F.opp.x), dmg = d.call(84), lvl = "mid", launch = 0.2, hs = 30, bs = 14})]], anim = gey_anim, voice = "roar", pros = "تنفجر تحت قدمي الخصم أينما كان — تعاقب المقذوفات", cons = "بطيئة جداً، يمكن تفاديها بالتحرك أو المراوغة"})
	o.geyserEX = M({name = "Marrow Geyser EX", ar = "نافورتا النخاع", cmd = "↓ ← + 4 + BL", type = "ex", startup = 20, active = 1, recovery = 16, proj = true, ev = [[6, func(F): _vg_geyser_mark(F, true)], [20, func(F): G.spawn_proj(F, {type = "geyser", x = F.store.get("gx", F.opp.x), dmg = d.call(60), lvl = "mid", launch = 0.2, hs = 30, bs = 14})], [30, func(F): G.spawn_proj(F, {type = "geyser", x = F.store.get("gx", F.opp.x) - F.facing * 0.9, dmg = d.call(45), lvl = "mid", launch = 0.22, hs = 30, bs = 14})]], anim = gey_anim, voice = "roar"})
	var charge_anim := func(S2, m): return [[0, S2.guard], [7, PZ.P(S2.guard, {"+root": [-0.08, -0.05, 0], "+hip": [0.1, -0.5, 0], "+chest": [0.1, -0.4, 0]}), "io"], [12, PZ.P(S2.guard, {"+root": [0.2, -0.15, 0], "+hip": [0.45, -0.7, 0], "+chest": [0.25, -0.6, 0], "L": [0.35, 1.15, -0.35], "R": [0.0, 1.2, 0.3], "lf": [0.6, 0.1, -0.2], "rf": [-0.55, 0.14, 0.2], "rfa": [-0.5, 0.5, 0], "nod": 0.3}), "out"], [26, PZ.P(S2.guard, {"+root": [0.2, -0.15, 0], "+hip": [0.45, -0.7, 0], "+chest": [0.25, -0.6, 0], "L": [0.35, 1.15, -0.35], "R": [0.0, 1.2, 0.3], "lf": [0.55, 0.1, -0.2], "rf": [-0.5, 0.14, 0.2], "nod": 0.3})], [46, S2.guard]]
	o.charge = M({name = "Tyrant Charge", ar = "هجمة الطاغية", cmd = "← → + 3", type = "special", startup = 12, active = 14, recovery = 20, hit = {lvl = "mid", box = [0.05, 1.0, 0.5, 1.7], dmg = d.call(88), hs = 30, bs = 18, push = 0.2, power = 1.4}, motion = func(f, F): return 0.18 if f > 6 and f < 26 else (0.05 if f < 30 else 0.0), tick = _vg_charge_tick, anim = charge_anim, voice = "roar", pros = "تكتسح المسافة بضرر هائل", cons = "-15 عند الصد، تُقفز بسهولة"})
	o.chargeEX = M({name = "Tyrant Charge EX", ar = "هجمة الطاغية المعززة", cmd = "← → + 3 + BL", type = "ex", startup = 12, active = 14, recovery = 16, armor = [1, 24, 2], hit = {lvl = "mid", box = [0.05, 1.0, 0.5, 1.7], dmg = d.call(115), hs = 34, bs = 20, launch = 0.14, push = 0.2, power = 1.5}, motion = func(f, F): return 0.2 if f > 6 and f < 26 else (0.05 if f < 30 else 0.0), tick = _vg_charge_tick, anim = charge_anim, voice = "roar"})
	var grasp_anim := func(S2, m): return PZ.kstrike(S2.guard, m, PZ.P(S2.guard, {"+chest": [-0.1, 0, 0], "L": [0.2, 1.65, -0.45], "R": [0.15, 1.6, 0.45]}), PZ.P(S2.guard, {"+root": [0.15, -0.03, 0], "+chest": [0.2, 0.2, 0], "L": [0.85, 1.55, -0.12], "R": [0.82, 1.5, 0.12], "LE": [0, -1, -0.6], "RE": [0, -1, 0.6]}))
	o.grasp = M({name = "Flayer's Grasp", ar = "قبضة السالخ", cmd = "→ ← + 2", type = "special", grab = true, startup = 9, active = 3, recovery = 34, hit = {lvl = "unblockable", box = [0.1, 0.9, 0.4, 1.9], dmg = d.call(118), grab = true, heal = 40}, anim = grasp_anim, voice = "roar", pros = "مسكة لا تُصد ولا يمكن الإفلات منها، تشفي جراحك", cons = "إن أخطأت: -34 وعقاب كامل"})
	o.graspEX = M({name = "Flayer's Grasp EX", ar = "قبضة السالخ المعززة", cmd = "→ ← + 2 + BL", type = "ex", grab = true, startup = 8, active = 4, recovery = 30, hit = {lvl = "unblockable", box = [0.1, 1.0, 0.4, 1.9], dmg = d.call(155), grab = true, heal = 70}, anim = grasp_anim, voice = "roar"})
	return o

# ====================================================================== NYXARA
static func _nx_glide_tick(F, f: int) -> void:
	if f > 6 and f < 26 and f % 2 == 1:
		VFX.dust(Vector3(F.x, 0, 0), 2, 0.6)
		VFX.wisp(Vector3(F.x, 0.3, 0))

static func _nyxara(spd: int, dm: float, S: Dictionary) -> Dictionary:
	var d := func(x): return roundi(x * dm)
	var o := {}
	o.n11 = M({name = "Bone Lash", ar = "جلدة العظم", cmd = "1, 1", startup = 6, active = 2, recovery = 12, hit = {lvl = "high", dmg = d.call(22), hs = 16, bs = 12, push = 0.03, slash = true}, anim = func(S2, m): return PZ.hookL(S2.guard, m, {t = [0.8, 1.5, 0.1]}), chain = {"2": "n112"}, voice = "grunt", trail = ["faL", 4, 9]})
	o.n112 = M({name = "Widow Cut", ar = "قطع الأرملة", cmd = "1, 1, 2", startup = 8, active = 3, recovery = 14, hit = {lvl = "mid", dmg = d.call(28), hs = 18, bs = 13, push = 0.03, slash = true}, anim = func(S2, m): return PZ.hook(S2.guard, m, {t = [0.8, 1.2, -0.1]}), chain = {"1": "n1121"}, voice = "grunt", trail = ["faR", 5, 11]})
	o.n1121 = M({name = "Thousand Cuts", ar = "الألف جرح", cmd = "1, 1, 2, 1", type = "string", startup = 10, active = 6, recovery = 18, hits = [{f = 10, a = 3, lvl = "mid", dmg = d.call(22), hs = 18, bs = 12, push = 0.02, slash = true}, {f = 14, a = 3, lvl = "mid", dmg = d.call(30), hs = 24, bs = 14, push = 0.12, slash = true, power = 1.0}], cancel = true, anim = func(S2, m): return [[0, S2.guard], [6, PZ.P(S2.guard, {"+hip": [0, -0.6, 0], "+chest": [0, -0.5, 0], "L": [-0.2, 1.4, -0.5], "R": [0.1, 1.5, 0.5]}), "io"], [12, PZ.P(S2.guard, {"+root": [0.12, -0.05, 0], "+hip": [0.1, 1.6, 0], "+chest": [0.15, 0.6, 0], "L": [0.8, 1.3, 0.3], "R": [0.6, 1.6, 0.45]}), "out"], [17, PZ.P(S2.guard, {"+root": [0.15, -0.06, 0], "+hip": [0.1, 3.4, 0], "+chest": [0.15, 0.9, 0], "L": [0.7, 1.35, -0.3], "R": [0.85, 1.25, 0.2]}), "out"], [34, S2.guard]], voice = "atk2", trail = ["faL", 8, 18], pros = "سلسلة من 4 ضربات سريعة، قابلة للإلغاء بحركة خاصة", cons = "ضرر كل ضربة منخفض"})
	o.n21 = M({name = "Rising Thorn", ar = "الشوكة الصاعدة", cmd = "2, 1", startup = 8, active = 3, recovery = 14, hit = {lvl = "mid", dmg = d.call(26), hs = 18, bs = 13, push = 0.03, slash = true}, anim = func(S2, m): return PZ.upper(S2.guard, m, {t = [0.7, 1.7, -0.1]}), chain = {"3": "n213"}, voice = "grunt", trail = ["faR", 5, 11]})
	o.n213 = M({name = "Widow's Lift", ar = "رفعة الأرملة", cmd = "2, 1, 3", type = "string", startup = 10, active = 4, recovery = 22, hit = {lvl = "mid", box = [0.1, 0.9, 0.7, 2.3], dmg = d.call(40), hs = 30, bs = 12, launch = 0.175, push = 0.02, power = 1.1}, anim = func(S2, m): return [[0, S2.guard], [10, PZ.P(S2.guard, {root = [-0.1, 1.15, 0], hip = [-1.6, -0.3, 0], free = 1, rf = [0.65, 1.8, 0.05], lf = [-0.05, 0.7, -0.12], rk = [1, 1, 0], rfa = [0, 0.8, 0]}), "out"], [16, PZ.P(S2.guard, {root = [-0.15, 1.1, 0], hip = [-2.8, -0.3, 0], free = 1, rf = [0.1, 1.6, 0.05], lf = [0.1, 0.9, -0.12], rk = [0, 1, 0]}), "lin"], [24, PZ.P(S2.jump, {root = [-0.1, 0.7, 0]}), "io"], [36, S2.guard]], voice = "atk2", trail = ["snR", 8, 16], pros = "ركلة شقلبة ترفع الخصم لكومبو", cons = "-13 عند الصد"})
	o.b1 = M({name = "Grave Needle", ar = "إبرة القبر", cmd = "← + 1", startup = 9, active = 3, recovery = 13, hit = {lvl = "low", box = [0.25, 1.05, 0.0, 0.55], dmg = d.call(25), hs = 17, bs = 12, push = 0.03, slash = true}, anim = func(S2, m): return PZ.kstrike(S2.crouch, m, PZ.P(S2.crouch, {L = [0.3, 0.9, -0.1]}), PZ.P(S2.crouch, {"+root": [0.12, -0.1, 0], "+hip": [0.2, -0.2, 0], "L": [1.02, 0.25, -0.02], "LE": [0, 1, -0.5], "lw": [-0.4, 0, 0]}), {end = S2.guard}), chain = {"2": "nb12"}, voice = "grunt", trail = ["faL", 6, 11], pros = "منخفضة سريعة طويلة المدى", cons = "ضرر ضعيف"})
	o.nb12 = M({name = "Hollow Rise", ar = "النهوض الأجوف", cmd = "← + 1, 2", type = "string", startup = 9, active = 3, recovery = 16, hit = {lvl = "mid", dmg = d.call(36), hs = 22, bs = 14, push = 0.08, slash = true}, cancel = true, anim = func(S2, m): return PZ.upper(S2.guard, m), voice = "atk", trail = ["faR", 6, 12], pros = "منخفضة ثم متوسطة، قابلة للإلغاء", cons = "-5 عند الصد"})
	o.f4 = M({name = "Moon Axe", ar = "فأس القمر", cmd = "→ + 4", startup = 18, active = 3, recovery = 15, hit = {lvl = "overhead", box = [0.15, 1.0, 0.9, 1.95], dmg = d.call(50), hs = 22, bs = 16, push = 0.05, power = 1.0}, motion = func(f, F): return 0.025 if f < 16 else 0.0, anim = func(S2, m): return PZ.axe(S2.guard, m), chain = {"3": "nf43"}, voice = "atk", trail = ["snR", 12, 20], pros = "ركلة فأسية علوية", cons = "بطيئة"})
	o.nf43 = M({name = "Shroud Sweep", ar = "كنسة الكفن", cmd = "→ + 4, 3", type = "string", startup = 10, active = 3, recovery = 24, hit = {lvl = "low", box = [0.2, 1.15, 0.0, 0.4], dmg = d.call(40), kd = true, bs = 10, power = 0.9}, anim = func(S2, m): return PZ.sweep(S2.guard, S2.crouch, m), voice = "atk", trail = ["snR", 8, 13], pros = "علوية ثم منخفضة — خلطة قاتلة", cons = "-17 عند الصد"})
	var shade_anim := func(S2, m): return PZ.kstrike(S2.guard, m, PZ.P(S2.guard, {"+chest": [-0.25, 0, 0], "L": [-0.2, 1.45, -0.4], "R": [-0.25, 1.45, 0.4], "LE": [0, -1, -1], "RE": [0, -1, 1]}), PZ.P(S2.guard, {"+root": [0.1, 0, 0], "+chest": [0.3, 0.2, 0], "L": [0.7, 1.55, -0.12], "R": [0.68, 1.52, 0.14], "LE": [0, -1, -0.6], "RE": [0, -1, 0.6], "nod": -0.3}))
	o.shade = M({name = "Wailing Shade", ar = "شبح النواح", cmd = "↓ → + 1", type = "special", startup = 12, active = 1, recovery = 24, proj = true, ev = [[12, func(F): G.spawn_proj(F, {type = "shade", vx = 0.28, dmg = d.call(42), lvl = "high", hs = 20, bs = 13, y = 1.55}); SFX.play("spectral", 1.0)]], anim = shade_anim, voice = "scream", pros = "أسرع مقذوف في اللعبة", cons = "عالية: يمكن الانحناء تحتها"})
	o.shadeEX = M({name = "Wailing Shade EX", ar = "شبحا النواح", cmd = "↓ → + 1 + BL", type = "ex", startup = 11, active = 1, recovery = 24, proj = true, ev = [[11, func(F): G.spawn_proj(F, {type = "shade", vx = 0.3, dmg = d.call(34), lvl = "mid", hs = 20, bs = 13, y = 1.25}); SFX.play("spectral", 1.2)], [17, func(F): G.spawn_proj(F, {type = "shade", vx = 0.3, dmg = d.call(34), lvl = "mid", hs = 26, bs = 13, y = 1.35, kd = true})]], anim = shade_anim, voice = "scream"})
	o.veil = M({name = "Veil Step", ar = "خطوة الحجاب", cmd = "↓ ← + 3", type = "special", startup = 22, active = 4, recovery = 16, inv = [5, 19], vanish = [5, 18], tele = 18, hit = {lvl = "mid", box = [0.1, 0.95, 0.6, 1.7], dmg = d.call(58), kd = true, bs = 14, push = 0.05, power = 1.1, slash = true}, anim = func(S2, m): return [[0, S2.guard], [5, PZ.P(S2.crouch, {L = [0.1, 0.8, -0.3], R = [0.1, 0.8, 0.3]}), "out"], [18, S2.crouch], [22, PZ.P(S2.guard, {"+root": [0.15, -0.05, 0], "+hip": [0.1, 0.4, 0], "+chest": [0.15, 0.5, 0], "R": [0.85, 1.35, -0.05], "L": [0.3, 1.5, -0.3]}), "out"], [26, PZ.P(S2.guard, {"+root": [0.15, -0.05, 0], "R": [0.85, 1.3, -0.1]})], [42, S2.guard]], voice = "laugh", trail = ["faR", 19, 25], pros = "تختفي وتظهر خلف الخصم — تخدع الصد", cons = "بطيئة، يمكن قراءتها والضرب عند ظهورها"})
	o.veilEX = M({name = "Veil Step EX", ar = "خطوة الحجاب المعززة", cmd = "↓ ← + 3 + BL", type = "ex", startup = 15, active = 4, recovery = 14, inv = [1, 14], vanish = [3, 12], tele = 12, hit = {lvl = "mid", box = [0.1, 0.95, 0.6, 1.7], dmg = d.call(62), launch = 0.17, hs = 30, bs = 14, power = 1.2, slash = true}, anim = func(S2, m): return [[0, S2.guard], [3, S2.crouch, "out"], [12, S2.crouch], [15, PZ.P(S2.guard, {"+root": [0.15, -0.05, 0], "+hip": [-0.1, 0.4, 0], "+chest": [-0.2, 0.5, 0], "R": [0.6, 2.0, -0.05]}), "out"], [33, S2.guard]], voice = "laugh", trail = ["faR", 12, 19]})
	var waltz_anim := func(S2, m, k): return _nx_waltz(S2, k)
	o.waltz = M({name = "Widow's Waltz", ar = "رقصة الأرملة", cmd = "← → + 2", type = "special", startup = 12, active = 15, recovery = 24, hits = [{f = 12, a = 3, lvl = "mid", dmg = d.call(25), hs = 16, bs = 12, push = 0.01, slash = true}, {f = 18, a = 3, lvl = "mid", dmg = d.call(25), hs = 16, bs = 12, push = 0.01, slash = true}, {f = 24, a = 3, lvl = "mid", dmg = d.call(30), hs = 24, bs = 12, push = 0.12, slash = true, power = 1.0}], motion = func(f, F): return 0.11 if f > 7 and f < 28 else 0.0, anim = func(S2, m): return _nx_waltz(S2, 1.0), voice = "atk2", trail = ["faL", 9, 28], pros = "3 ضربات تتقدم، ممتازة لإنهاء الكومبو", cons = "-18 عند الصد، خطيرة جداً"})
	var exhits := []
	for f in [11, 16, 21, 26]: exhits.append({f = f, a = 3, lvl = "mid", dmg = d.call(20), hs = 16, bs = 12, push = 0.0, slash = true})
	exhits.append({f = 31, a = 3, lvl = "mid", dmg = d.call(30), hs = 30, bs = 12, launch = 0.17, slash = true, power = 1.2})
	o.waltzEX = M({name = "Widow's Waltz EX", ar = "رقصة الأرملة المعززة", cmd = "← → + 2 + BL", type = "ex", startup = 11, active = 22, recovery = 22, hits = exhits, motion = func(f, F): return 0.1 if f > 6 and f < 33 else 0.0, anim = func(S2, m): return _nx_waltz(S2, 1.25), voice = "atk2", trail = ["faL", 9, 33]})
	var glide_anim := func(S2, m): return [[0, S2.guard], [6, S2.crouch, "io"], [12, _nx_glide_pose(S2), "out"], [26, _nx_glide_pose(S2)], [44, S2.guard]]
	o.glide = M({name = "Grave Glide", ar = "انزلاق القبر", cmd = "↓ → + 4", type = "special", startup = 14, active = 12, recovery = 18, lowHurt = [6, 28], hit = {lvl = "low", box = [0.1, 1.1, 0.0, 0.5], dmg = d.call(55), kd = true, bs = 12, push = 0.04, power = 1.0}, motion = func(f, F): return 0.17 if f > 6 and f < 26 else (0.04 if f < 30 else 0.0), tick = _nx_glide_tick, anim = glide_anim, voice = "atk", pros = "تنزلق تحت المقذوفات والضربات العالية", cons = "-10 عند الصد"})
	o.glideEX = M({name = "Grave Glide EX", ar = "انزلاق القبر المعزز", cmd = "↓ → + 4 + BL", type = "ex", startup = 13, active = 12, recovery = 18, lowHurt = [6, 26], hit = {lvl = "low", box = [0.1, 1.1, 0.0, 0.6], dmg = d.call(68), launch = 0.18, hs = 30, bs = 12, power = 1.2}, motion = func(f, F): return 0.19 if f > 6 and f < 26 else (0.04 if f < 30 else 0.0), tick = _nx_glide_tick, anim = glide_anim, voice = "atk"})
	return o

static func _nx_waltz(S: Dictionary, k: float) -> Array:
	var sp := func(a): return PZ.P(S.guard, {root = [0.05, 0.9, 0], hip = [0.05, -0.5 + a * TAU, 0], spine = [0.05, 0, 0], chest = [0.05, 0, 0], L = [0.1, 1.4, -0.65], R = [0.1, 1.4, 0.65], LE = [0, 1, -1], RE = [0, 1, 1], lf = [0.15, 0.08, -0.15], rf = [-0.15, 0.1, 0.15], free = 1, head = [0, 0.2, 0]})
	return [[0, S.guard], [roundi(8 * k), sp.call(0.0), "io"], [roundi(14 * k), sp.call(0.45), "lin"], [roundi(20 * k), sp.call(1.05), "lin"], [roundi(26 * k), sp.call(1.6), "lin"], [roundi(30 * k), sp.call(2.0), "out"], [roundi(51 * k), S.guard]]

static func _nx_glide_pose(S: Dictionary) -> PackedFloat32Array:
	return PZ.P(S.guard, {root = [-0.15, 0.32, 0], hip = [-0.9, -0.3, 0], spine = [0.2, 0, 0], chest = [0.3, 0, 0], lf = [0.75, 0.1, -0.1], rf = [0.15, 0.1, 0.12], lk = [1, 0.3, 0], rk = [0, 1, 0.3], lfa = [0, 0.5, 0], L = [-0.4, 0.15, -0.35], R = [0.3, 0.9, 0.3], nod = 0.3})

# ====================================================================== OSSIRAH
static func _os_lunge_tick(F, f: int) -> void:
	if f > 5 and f < 18: VFX.plague(jw(F, "wrL"), 0.6)
static func _os_burst_ev(F) -> void:
	var p := jw(F, "chest")
	for i in 24: VFX.plague(p + Vector3(randf_range(-0.5, 0.5), randf_range(-0.8, 0.5), randf_range(-0.4, 0.4)), 2.0)
	VFX.ring(p, Color(0.5, 1.8, 0.2), 3.0, 0.4)
	G.cam_shake(0.4)
	SFX.play("boom", 0.5)
	SFX.play("swarm", 0.8)

static func _ossirah(spd: int, dm: float, S: Dictionary) -> Dictionary:
	var d := func(x): return roundi(x * dm)
	var o := {}
	o.o12 = M({name = "Bleeding Arc", ar = "القوس النازف", cmd = "1, 2", startup = 9, active = 3, recovery = 15, hit = {lvl = "mid", dmg = d.call(34), hs = 19, bs = 13, push = 0.04, slash = true}, anim = func(S2, m): return PZ.hook(S2.guard, m, {t = [0.75, 1.35, -0.15]}), chain = {"1": "o121"}, voice = "grunt", trail = ["hdR", 6, 12]})
	o.o121 = M({name = "Sickle Hymn", ar = "ترنيمة المنجل", cmd = "1, 2, 1", type = "string", startup = 11, active = 3, recovery = 19, hit = {lvl = "mid", dmg = d.call(44), hs = 24, bs = 15, push = 0.13, slash = true, power = 1.1}, cancel = true, anim = func(S2, m): return PZ.hookL(S2.guard, m, {t = [0.8, 1.35, 0.1]}), voice = "atk2", pros = "سلسلة متوسطة آمنة نسبياً، قابلة للإلغاء", cons = "-7 عند الصد"})
	o.o33 = M({name = "Rot Kick", ar = "ركلة العفن", cmd = "3, 3", startup = 9, active = 2, recovery = 14, hit = {lvl = "low", dmg = d.call(28), hs = 18, bs = 12, push = 0.03}, anim = func(S2, m): return PZ.lowkick(S2.guard, m), chain = {"2": "o332"}, voice = "grunt"})
	o.o332 = M({name = "Harvest", ar = "الحصاد", cmd = "3, 3, 2", type = "string", startup = 11, active = 4, recovery = 23, hit = {lvl = "mid", box = [0.1, 0.95, 0.7, 2.2], dmg = d.call(42), hs = 30, bs = 12, launch = 0.165, slash = true, power = 1.1}, anim = func(S2, m): return PZ.upper(S2.guard, m, {t = [0.6, 2.0, 0.1]}), voice = "atk2", trail = ["hdR", 9, 15], pros = "متوسطة، منخفضة، ثم رافعة", cons = "-15 عند الصد"})
	o.b2 = M({name = "Reaping Low", ar = "الحصد المنخفض", cmd = "← + 2", startup = 11, active = 3, recovery = 16, hit = {lvl = "low", box = [0.25, 1.15, 0.0, 0.5], dmg = d.call(38), hs = 18, bs = 13, push = 0.04, slash = true}, anim = func(S2, m): return PZ.kstrike(S2.guard, m, PZ.P(S2.guard, {R = [-0.1, 1.5, 0.4]}), PZ.P(S2.crouch, {"+root": [0.08, -0.06, 0], "+hip": [0.2, 0.5, 0], "+chest": [0.2, 0.5, 0], "R": [0.85, 0.25, -0.2], "RE": [0, 1, 1]})), chain = {"1": "ob21"}, voice = "grunt", trail = ["hdR", 8, 13], pros = "منخفضة طويلة المدى بالمنجل", cons = "-6 عند الصد"})
	o.ob21 = M({name = "Lancet", ar = "المِبضع", cmd = "← + 2, 1", type = "string", startup = 7, active = 2, recovery = 13, hit = {lvl = "high", dmg = d.call(26), hs = 18, bs = 14, push = 0.05}, cancel = true, anim = func(S2, m): return PZ.jab(S2.guard, m), voice = "grunt", pros = "تكمل المنخفضة بضربة سريعة، قابلة للإلغاء", cons = "عالية"})
	o.of22 = M({name = "Last Rites", ar = "الطقوس الأخيرة", cmd = "→ + 2, 2", type = "string", startup = 12, active = 3, recovery = 21, hit = {lvl = "mid", dmg = d.call(48), hs = 26, bs = 14, push = 0.14, slash = true, power = 1.1}, cancel = true, anim = func(S2, m): return PZ.hook(S2.guard, m), voice = "atk2", trail = ["hdR", 9, 15], pros = "علوية ثم متوسطة قوية", cons = "-9 عند الصد"})
	var swarm_anim := func(S2, m): return PZ.cast(S2.guard, m, {t = [0.78, 1.42, -0.05], t2 = [0.2, 1.5, 0.2]})
	o.swarm = M({name = "Locust Swarm", ar = "سرب الجراد", cmd = "← → + 1", type = "special", startup = 20, active = 1, recovery = 22, proj = true, ev = [[20, func(F): G.spawn_proj(F, {type = "swarm", vx = 0.075, dmg = d.call(17), lvl = "mid", hs = 14, bs = 10, hits = 3, cd = 11, life = 100}); SFX.play("swarm", 1.0)]], anim = swarm_anim, voice = "taunt", pros = "سرب بطيء متعدد الضربات يحمي تقدّمك", cons = "بطيء جداً، يمكن تجاوزه بالقفز أو المراوغة"})
	o.swarmEX = M({name = "Locust Swarm EX", ar = "سرب الجراد المعزز", cmd = "← → + 1 + BL", type = "ex", startup = 18, active = 1, recovery = 22, proj = true, ev = [[18, func(F): G.spawn_proj(F, {type = "swarm", vx = 0.09, dmg = d.call(15), lvl = "mid", hs = 14, bs = 10, hits = 5, cd = 9, life = 110, poison = 180, big = true}); SFX.play("swarm", 1.4)]], anim = swarm_anim, voice = "laugh"})
	var mia_anim := func(S2, m): return PZ.kstrike(S2.guard, m, PZ.P(S2.guard, {"+chest": [-0.2, -0.2, 0], "L": [-0.15, 1.9, -0.3], "LE": [0, -1, -1]}), PZ.P(S2.guard, {"+root": [0.08, 0, 0], "+chest": [0.25, 0.2, 0], "L": [0.9, 1.55, -0.1], "lw": [-0.8, 0, 0]}), {cf = 0.6})
	o.miasma = M({name = "Miasma", ar = "الوباء", cmd = "↓ ← + 2", type = "special", startup = 18, active = 1, recovery = 16, proj = true, ev = [[18, func(F): G.spawn_proj(F, {type = "cloud", x = F.x + F.facing * 2.6, life = 180, dmg = 9, poison = 90, r = 0.85})]], anim = mia_anim, voice = "laugh", pros = "سحابة سامة تمنع الخصم من التقدم وتسممه", cons = "ضرر بطيء، لا تمنع الضربات"})
	o.miasmaEX = M({name = "Miasma EX", ar = "الوباء المعزز", cmd = "↓ ← + 2 + BL", type = "ex", startup = 16, active = 1, recovery = 16, proj = true, ev = [[16, func(F): G.spawn_proj(F, {type = "cloud", x = F.x + F.facing * 2.4, life = 300, dmg = 12, poison = 150, r = 1.25})]], anim = mia_anim, voice = "laugh"})
	var lunge_anim := func(S2, m): return [[0, S2.guard], [6, PZ.P(S2.guard, {"+root": [-0.05, 0, 0], "L": [-0.1, 1.3, -0.3]}), "io"], [13, PZ.P(S2.guard, {"+root": [0.25, -0.12, 0], "+hip": [0.35, -0.2, 0], "+chest": [0.25, -0.4, 0], "L": [1.05, 1.22, -0.02], "LE": [0, -1, -0.3], "lw": [0, 0, 0], "lf": [0.65, 0.1, -0.14], "rf": [-0.5, 0.13, 0.16], "rfa": [-0.5, 0.5, 0]}), "out"], [17, PZ.P(S2.guard, {"+root": [0.25, -0.12, 0], "+hip": [0.35, -0.2, 0], "+chest": [0.25, -0.4, 0], "L": [1.05, 1.22, -0.02], "lf": [0.6, 0.1, -0.14], "rf": [-0.5, 0.13, 0.16]})], [37, S2.guard]]
	o.lunge = M({name = "Plague Lancet", ar = "حقنة الطاعون", cmd = "← → + 3", type = "special", startup = 13, active = 4, recovery = 20, hit = {lvl = "mid", box = [0.05, 1.05, 0.8, 1.5], dmg = d.call(52), hs = 24, bs = 14, push = 0.08, poison = 150, power = 1.1}, motion = func(f, F): return 0.16 if f > 5 and f < 17 else 0.0, tick = _os_lunge_tick, anim = lunge_anim, voice = "atk", pros = "تقدّم سريع وتسمم الخصم (ضرر مستمر)", cons = "-9 عند الصد"})
	o.lungeEX = M({name = "Plague Lancet EX", ar = "حقنة الطاعون المعززة", cmd = "← → + 3 + BL", type = "ex", startup = 12, active = 4, recovery = 18, armor = [1, 12, 1], hit = {lvl = "mid", box = [0.05, 1.05, 0.8, 1.5], dmg = d.call(62), hs = 30, bs = 16, launch = 0.16, poison = 220, power = 1.2}, motion = func(f, F): return 0.18 if f > 5 and f < 16 else 0.0, tick = _os_lunge_tick, anim = lunge_anim, voice = "atk"})
	var burst_anim := func(S2, m): return [[0, S2.guard], [5, PZ.P(S2.crouch, {L = [0.1, 0.9, -0.2], R = [0.1, 0.9, 0.2]}), "io"], [9, PZ.P(S2.guard, {"+root": [0, 0.05, 0], "+chest": [-0.35, 0.3, 0], "+spine": [-0.15, 0, 0], "L": [0.05, 1.75, -0.75], "R": [0.05, 1.75, 0.75], "LE": [0, -1, -1], "RE": [0, -1, 1], "nod": -0.4}), "snap"], [18, PZ.P(S2.guard, {"+chest": [-0.3, 0.3, 0], "L": [0.05, 1.7, -0.75], "R": [0.05, 1.7, 0.75]})], [46, S2.guard]]
	o.burst = M({name = "Rot Burst", ar = "انفجار العفن", cmd = "↓ ↓ + 1", type = "special", startup = 8, active = 6, recovery = 32, inv = [1, 11], hit = {lvl = "mid", box = [-0.75, 1.15, 0.0, 2.3], dmg = d.call(68), hs = 30, bs = 10, launch = 0.17, poison = 90, power = 1.3}, ev = [[8, _os_burst_ev]], anim = burst_anim, voice = "roar", pros = "محصّنة: تنفجر حولك وتبعد الخصم الضاغط", cons = "-28 عند الصد"})
	o.burstEX = M({name = "Rot Burst EX", ar = "انفجار العفن المعزز", cmd = "↓ ↓ + 1 + BL", type = "ex", startup = 7, active = 7, recovery = 30, inv = [1, 15], hit = {lvl = "mid", box = [-0.9, 1.3, 0.0, 2.4], dmg = d.call(90), hs = 32, bs = 10, launch = 0.19, poison = 160, power = 1.4}, ev = [[7, _os_burst_ev]], anim = burst_anim, voice = "roar"})
	return o

# ====================================================================== definitions
static func base_defs() -> Dictionary:
	return {
		"kharos": {id = "kharos", name = "KHAROS", title = "THE ASH REVENANT", title_ar = "رماد المنبعث", color = Color("#ff6a2a"),
			desc = "فارس ملعون احترق حياً في محرقة الآلهة، وعاد من رماده بدرعٍ تسيل منه الحمم. لا يعرف الرحمة، ولا يشعر بالألم، ولا يتوقف حتى يحترق كل شيء.",
			style = "متوازن · نار", stats = {power = 7, speed = 6, range = 6, diff = 4}, scale = 1.07, hp = 1000, walkF = 0.046, walkB = 0.036, dashV = 0.15, jumpV = 0.19,
			voice = {f0 = 82.0, fs = 0.78, dist = 4.0, rasp = 0.7}, spd = 0, dm = 1.0,
			guard_mods = {"+root": [0, -0.02, 0], "lf": [0.33, 0.08, -0.15], "rf": [-0.33, 0.08, 0.17], "L": [0.42, 1.5, -0.03], "R": [0.22, 1.46, 0.12]},
			chains = {"1": {"1": "k11"}, "2": {"1": "k21"}, "b3": {"3": "kb33"}, "f2": {"4": "kf24"}},
			specials = [["slam", ["D", "N", "D"], "4"], ["hellskull", ["D", "B"], "1"], ["pyre", ["D", "F"], "2"], ["rush", ["B", "F"], "3"]],
			sup = {name = "INFERNAL JUDGEMENT", ar = "حُكم الجحيم"},
			exec = {name = "PYRE OF SOULS", ar = "محرقة الأرواح", seq = ["B", "F", "B"], btn = "4", cmd = "← → ← + 4", range = "close"},
			ai = {zone = 0.35, rush = 0.6, combos = ["1 w5 1 w7 2 w10 D F+2", "2 w8 1 w8 4 w26 B F+3", "B+3 w12 3 w10 D B+1", "F+2 w20 4", "D+3 w10 D F+2"], juggles = ["w8 2 w9 1 w9 4 w28 B F+3", "w6 1 w6 1 w8 2 w12 D F+2", "w10 B F+3"], antiair = "D F+2", punish = ["D F+2", "2 w8 1 w8 4 w26 B F+3", "D+2"]}},
		"vorgath": {id = "vorgath", name = "VORGATH", title = "THE FLAYED KING", title_ar = "الملك المسلوخ", color = Color("#c81020"),
			desc = "ملكٌ قديم سلخه شعبه حياً، فتعاقد مع الهاوية ليعود عملاقاً من العضلات العارية والعظام. يتغذى على دماء ضحاياه، وكل قطرة تسيل تزيده قوة.",
			style = "ثقيل · مصارع · دم", stats = {power = 10, speed = 3, range = 7, diff = 6}, scale = 1.13, hp = 1080, walkF = 0.036, walkB = 0.028, dashV = 0.13, jumpV = 0.175,
			voice = {f0 = 58.0, fs = 0.62, dist = 9.0, rasp = 1.0}, spd = 2, dm = 1.16,
			guard_mods = {root = [-0.02, 0.86, 0], hip = [0.2, -0.4, 0], spine = [0.14, -0.06, 0], chest = [0.2, -0.1, 0], neck = [0.05, 0.25, 0], lf = [0.38, 0.08, -0.22], rf = [-0.36, 0.08, 0.24], lk = [1, 0.1, -0.5], rk = [0.7, 0.1, 0.9], L = [0.52, 1.22, -0.3], R = [0.32, 1.12, 0.36], LE = [-0.3, -0.4, -1], RE = [-0.4, -0.4, 1], lw = [-0.4, 0, 0], rw = [-0.4, 0, 0], nod = 0.05},
			chains = {"1": {"2": "v12"}, "2": {"2": "v22"}, "b1": {"2": "vb12"}, "f4": {"4": "vf44"}},
			specials = [["lance", ["B", "F"], "1"], ["geyser", ["D", "B"], "4"], ["charge", ["B", "F"], "3"], ["grasp", ["F", "B"], "2"]],
			sup = {name = "THRONE OF AGONY", ar = "عرش العذاب"},
			exec = {name = "CROWN OF THORNS", ar = "تاج الأشواك", seq = ["D", "F", "D"], btn = "2", cmd = "↓ → ↓ + 2", range = "close"},
			ai = {zone = 0.45, rush = 0.45, combos = ["1 w9 2 w12 B F+3", "2 w10 2 w12 1", "B+1 w10 2 w30 B F+1", "F+4 w16 4", "F B+2"], juggles = ["w10 2 w11 2 w12 1", "w10 1 w9 2 w14 B F+3", "w12 B F+3"], antiair = "D+2", punish = ["F B+2", "1 w9 2 w12 B F+3", "D+2"]}},
		"nyxara": {id = "nyxara", name = "NYXARA", title = "THE HOLLOW WIDOW", title_ar = "الأرملة الجوفاء", color = Color("#7ad8ff"),
			desc = "روحٌ معذبة لأرملة قُتلت ليلة زفافها، عادت بقناعٍ من خزف مكسور ونصلين من عظام زوجها. تتحرك كالظل، وتغني لضحاياها قبل أن تقطعهم إرباً.",
			style = "سريعة · هجومية · أشباح", stats = {power = 5, speed = 10, range = 6, diff = 8}, scale = 1.04, hp = 940, walkF = 0.056, walkB = 0.046, dashV = 0.18, jumpV = 0.2,
			voice = {f0 = 330.0, fs = 1.25, dist = 0.0, rasp = 0.35}, spd = -1, dm = 0.86,
			guard_mods = {root = [0, 0.86, 0], hip = [0.12, -0.55, 0], spine = [0.06, -0.1, 0], chest = [0.1, -0.15, 0], lf = [0.42, 0.08, -0.14], rf = [-0.32, 0.08, 0.16], L = [0.56, 1.32, -0.06], R = [0.08, 1.62, 0.22], LE = [-0.5, -1, -0.3], RE = [-0.6, 0.2, 1], lw = [-0.3, 0, 0], rw = [0.6, 0, 0], nod = 0.05},
			chains = {"1": {"1": "n11"}, "2": {"1": "n21"}, "b1": {"2": "nb12"}},
			specials = [["shade", ["D", "F"], "1"], ["veil", ["D", "B"], "3"], ["waltz", ["B", "F"], "2"], ["glide", ["D", "F"], "4"]],
			sup = {name = "REQUIEM OF KNIVES", ar = "قدّاس الشفرات"},
			exec = {name = "RIBBON OF FLESH", ar = "شرائط اللحم", seq = ["F", "B", "D"], btn = "3", cmd = "→ ← ↓ + 3", range = "mid"},
			ai = {zone = 0.3, rush = 0.8, combos = ["1 w5 1 w7 2 w8 1 w20 B F+2", "2 w7 1 w8 3", "B+1 w9 2 w16 D F+4", "F+4 w18 3", "D B+3"], juggles = ["w6 1 w5 1 w7 2 w8 1 w18 B F+2", "w8 2 w7 1 w8 3", "w10 B F+2"], antiair = "D+2", punish = ["2 w7 1 w8 3", "1 w5 1 w7 2 w8 1 w20 B F+2", "D+2"]}},
		"ossirah": {id = "ossirah", name = "OSSIRAH", title = "THE PLAGUE SAINT", title_ar = "قدّيس الطاعون", color = Color("#9cff5a"),
			desc = "طبيبٌ ادّعى أنه يشفي الطاعون، فصار هو الطاعون. يحمل منجلاً جراحياً وسرباً من الجراد يأكل اللحم الحي، ويرى في كل جسد تجربة جديدة.",
			style = "تحكّم · سموم · مسافة", stats = {power = 6, speed = 5, range = 9, diff = 7}, scale = 1.02, hp = 990, walkF = 0.042, walkB = 0.036, dashV = 0.15, jumpV = 0.185,
			voice = {f0 = 120.0, fs = 0.95, dist = 1.5, rasp = 0.8}, spd = 1, dm = 0.95,
			guard_mods = {root = [0, 0.9, 0], hip = [0.1, -0.45, 0], spine = [0.1, -0.06, 0], chest = [0.15, -0.1, 0], neck = [0.1, 0.3, 0], lf = [0.3, 0.08, -0.13], rf = [-0.28, 0.08, 0.15], L = [0.45, 1.28, -0.12], R = [0.3, 1.56, 0.18], LE = [-0.2, -1, -0.6], RE = [-0.6, -0.4, 0.8], lw = [-0.6, 0, 0], rw = [0.3, 0, 0], nod = 0.08},
			chains = {"1": {"2": "o12"}, "3": {"3": "o33"}, "b2": {"1": "ob21"}, "f2": {"2": "of22"}},
			specials = [["burst", ["D", "N", "D"], "1"], ["swarm", ["B", "F"], "1"], ["miasma", ["D", "B"], "2"], ["lunge", ["B", "F"], "3"]],
			sup = {name = "LAST SACRAMENT", ar = "القربان الأخير"},
			exec = {name = "THE BLOAT", ar = "الانتفاخ", seq = ["D", "D", "B"], btn = "1", cmd = "↓ ↓ ← + 1", range = "far"},
			ai = {zone = 0.7, rush = 0.35, combos = ["1 w8 2 w10 1 w20 B F+3", "3 w8 3 w10 2", "B+2 w12 1 w14 B F+3", "F+2 w20 2", "D B+2"], juggles = ["w8 1 w8 2 w10 1 w18 B F+3", "w10 3 w9 3 w10 2", "w10 B F+3"], antiair = "D N D+1", punish = ["D N D+1", "1 w8 2 w10 1 w20 B F+3", "D+2"]}},
	}

static var _defs := {}
static func get_def(id: String) -> Dictionary:
	if CACHE.has(id): return CACHE[id]
	if _defs.is_empty(): _defs = base_defs()
	var D: Dictionary = _defs[id]
	var g := PZ.P(PZ.guard(), D.guard_mods)
	var S := PZ.std_poses(g)
	D.S = S
	var mv := normals(D.spd, D.dm)
	match id:
		"kharos": mv.merge(_kharos(D.spd, D.dm, S), true)
		"vorgath": mv.merge(_vorgath(D.spd, D.dm, S), true)
		"nyxara": mv.merge(_nyxara(D.spd, D.dm, S), true)
		"ossirah": mv.merge(_ossirah(D.spd, D.dm, S), true)
	for base in D.chains:
		mv[base].chain = D.chains[base]
	for k in mv:
		var m: Dictionary = mv[k]
		if m.has("chain"):
			m.chainAt = m.lastActive + 1
			m.chainEnd = m.total - 2
	mv["super"] = M({type = "super", startup = 12, active = 5, recovery = 44, armor = [1, 13, 3], hit = {lvl = "mid", box = [0.05, 1.2, 0.55, 1.95], dmg = 0, hs = 30, bs = 12, power = 1.4, cine = true}, cost = 300, voice = "atk2",
		name = D.sup.name, ar = D.sup.ar, cmd = "SP (عداد ممتلئ)", pros = "دروع ضد 3 ضربات أثناء الانطلاق، ضرر هائل", cons = "تستهلك العداد كاملاً، -40 عند الصد",
		anim = func(S2, m): return [[0, S2.guard], [3, PZ.P(S2.guard, {"+chest": [-0.3, 0, 0], "L": [-0.1, 1.8, -0.5], "R": [-0.1, 1.8, 0.5], "LE": [0, -1, -1], "RE": [0, -1, 1], "nod": -0.5}), "out"], [12, PZ.P(S2.guard, {"+root": [0.2, -0.06, 0], "+hip": [0.15, 0.3, 0], "+chest": [0.2, 0.45, 0], "R": [0.95, 1.4, 0], "L": [0.4, 1.4, -0.25]}), "snap"], [17, PZ.P(S2.guard, {"+root": [0.2, -0.06, 0], "R": [0.95, 1.4, 0]})], [61, S2.guard]]})
	for k in mv:
		var m: Dictionary = mv[k]
		m.id = k
		m.clip = PZ.clip(m.anim.call(S, m))
	var spec := []
	for s in D.specials:
		spec.append({id = s[0], seq = s[1], btn = s[2], len = s[1].size()})
	spec.sort_custom(func(a, b): return a.len > b.len)
	D.spec = spec
	D.mv = mv
	D.clips = {
		idle = PZ.clip([[0, S.guard], [40, S.idleB, "sine"], [80, S.guard, "sine"]], true),
		walk = PZ.clip([[0, S.guard], [1, S.guard]], true),
		crouch = PZ.clip([[0, S.crouch]]), block = PZ.clip([[0, S.block]]), cblock = PZ.clip([[0, S.cblock]]),
		blockHit = PZ.clip([[0, S.blockHit], [8, S.block]]), cblockHit = PZ.clip([[0, S.cblockHit], [8, S.cblock]]),
		jsquat = PZ.clip([[0, S.jsquat]]), jump = PZ.clip([[0, S.jump], [14, S.jump], [30, S.fall]]),
		flip = PZ.clip([[0, S.jump], [10, PZ.P(S.jump, {hip = [-PI, -0.3, 0], free = 1})], [20, PZ.P(S.jump, {hip = [-TAU, -0.3, 0], free = 1})], [34, S.fall]]),
		land = PZ.clip([[0, S.land], [5, S.guard]]),
		dash = PZ.clip([[0, S.dash], [10, S.dash], [16, S.guard]]), bdash = PZ.clip([[0, S.bdash], [12, S.bdash], [20, S.guard]]),
		side = PZ.clip([[0, S.side1], [16, S.side1], [24, S.guard]]),
		hitHi = PZ.clip([[0, S.guard], [3, S.hitHi, "out"], [16, S.guard]]), hitHi2 = PZ.clip([[0, S.guard], [3, S.hitHi2, "out"], [16, S.guard]]),
		hitMid = PZ.clip([[0, S.guard], [3, S.hitMid, "out"], [18, S.guard]]), hitLo = PZ.clip([[0, S.guard], [3, S.hitLo, "out"], [16, S.guard]]),
		hitHeavy = PZ.clip([[0, S.guard], [4, S.hitHeavy, "out"], [22, S.guard]]),
		hitCr = PZ.clip([[0, S.crouch], [3, PZ.P(S.crouch, {"+root": [-0.08, -0.04, 0], "+chest": [-0.25, 0.2, 0], "free": 1, "+head": [-0.3, 0.2, 0]}), "out"], [14, S.crouch]]),
		air = PZ.clip([[0, S.airHit], [12, S.airHit2], [40, S.airHit2]]),
		down = PZ.clip([[0, S.down], [30, S.downB, "sine"], [60, S.down, "sine"]]),
		getup = PZ.clip([[0, S.down], [8, S.getup1], [15, S.getup2], [22, S.guard]]),
		dizzy = PZ.clip([[0, S.dizzy], [50, S.dizzy2, "sine"], [100, S.dizzy, "sine"]], true),
		kneel = PZ.clip([[0, S.kneel]]),
		taunt = PZ.clip([[0, S.guard], [10, S.taunt], [60, S.taunt], [75, S.guard]]),
	}
	CACHE[id] = D
	return D

static func victory(id: String, S: Dictionary) -> PackedFloat32Array:
	match id:
		"vorgath": return PZ.P(S.guard, {"+root": [0, 0.03, 0], "+chest": [-0.35, 0.45, 0], "L": [0.3, 1.35, -0.85], "R": [0.2, 1.35, 0.85], "LE": [0, -1, -1], "RE": [0, -1, 1], "nod": -0.6})
		"nyxara": return PZ.P(S.guard, {"+chest": [-0.1, 0.3, 0], "L": [0.4, 1.62, 0.16], "R": [0.42, 1.66, -0.16], "LE": [0, -1, -1], "RE": [0, -1, 1], "free": 1, "head": [0.1, 0.2, 0.35]})
		"kharos": return PZ.P(S.guard, {"+chest": [-0.22, 0.2, 0], "R": [0.3, 2.22, 0.1], "RE": [0, -1, 1], "L": [0.3, 1.3, -0.3], "nod": -0.4})
	return PZ.P(S.guard, {"+root": [0, -0.04, 0], "+hip": [0.25, 0, 0], "+chest": [0.45, 0.2, 0], "L": [0.35, 1.2, 0.05], "R": [-0.35, 1.1, 0.35], "nod": 0.3})
