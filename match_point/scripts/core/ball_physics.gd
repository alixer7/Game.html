class_name BallPhysics
extends RefCounted
## محاكاة فيزيائية لكرة التنس:
##  - الجاذبية + مقاومة الهواء (Cd يتغير مع الدوران)
##  - قوة ماغنوس (الرفع الناتج عن الدوران) Cl = 1 / (2 + v/v_spin)
##  - ارتداد مع احتكاك: انزلاق أو تدحرج (نموذج Rod Cross) مع تحويل الدوران
##  - اصطدام بالشبكة وشريطها
## نفس الدالة step تُستخدم للعب الفعلي وللتنبؤ، فالتنبؤ مطابق تماماً.

const G := 9.81
const MASS := 0.0577
const R := 0.0335
const RHO := 1.21
const KD := 0.5 * RHO * PI * R * R / MASS   # ≈ 0.03697 (يُضرب في Cd·v²)
const CD0 := 0.55
const ALPHA := 0.55          # عزم القصور I = ALPHA·m·R²
const DT := 1.0 / 120.0
const SPIN_DECAY := 0.045    # 1/s اضمحلال الدوران في الهواء (مرجعي عند ~20 م/ث)
const SPIN_DECAY_V := 0.0011 # اضمحلال إضافي يتناسب مع السرعة: عزم الاحتكاك الهوائي أكبر للكرة الأسرع
const GRIP_EX := 0.12        # مرونة مماسية: الكرة «الممسكة» بالأرض تنطلق بدوران أمامي زائد قليلاً (Cross 2005)

const EV_NONE := 0
const EV_BOUNCE := 1
const EV_NET := 2        # اصطدام بجسم الشبكة
const EV_NET_CORD := 4   # لمس شريط الشبكة والعبور
const EV_WALL := 8

## الرياح (م/ث) — تؤثر على المقاومة وقوة ماغنوس عبر السرعة النسبية للهواء
static var wind := Vector3.ZERO

## حالة الكرة: [pos, vel, spin] تُمرَّر كمصفوفة لتفادي إنشاء كائنات
class State:
	var pos := Vector3.ZERO
	var vel := Vector3.ZERO
	var spin := Vector3.ZERO     # rad/s
	var rolling := false
	var bounce_pos := Vector3.ZERO
	var bounce_speed := 0.0

	func copy() -> State:
		var s := State.new()
		s.pos = pos
		s.vel = vel
		s.spin = spin
		s.rolling = rolling
		return s


## نسبة الدوران المتبقية بعد خطوة زمنية واحدة
static func spin_keep(v: float) -> float:
	return 1.0 - (SPIN_DECAY * 0.55 + SPIN_DECAY_V * v) * DT


static func accel(vel_g: Vector3, spin: Vector3, wk: float = 1.0) -> Vector3:
	var vel := vel_g - wind * wk
	var v := vel.length()
	var a := Vector3(0.0, -G, 0.0)
	if v < 0.05:
		return a
	var cd := CD0
	var w := spin.length()
	var vs := w * R
	if vs > 0.05:
		var ratio := v / vs
		cd += 1.0 / pow(22.5 + 4.2 * pow(ratio, 2.5), 0.4)
		var cl := 1.0 / (2.0 + ratio)
		# اتجاه ماغنوس = spin × vel (المركبة المتعامدة فقط تولّد رفعاً)
		a += spin.cross(vel) * (KD * cl * v / w)
	a -= vel * (KD * cd * v)
	return a


## خطوة واحدة بزمن DT. تُعيد أعلام الأحداث.
## surf: قاموس الأرضية من Court.SURFACES ، rng اختياري لعشوائية الارتداد (العشب/التراب)
static func step(s: State, surf: Dictionary, rng: RandomNumberGenerator = null) -> int:
	var ev := EV_NONE
	if s.rolling:
		return _roll_step(s, surf)

	var a := accel(s.vel, s.spin)
	var prev := s.pos
	s.vel += a * DT
	s.pos += s.vel * DT
	s.spin *= spin_keep(s.vel.length())

	# ---- الشبكة (المستوى z = 0) ----
	if true:
		if (prev.z > 0.0) != (s.pos.z > 0.0):
			var t := prev.z / (prev.z - s.pos.z)
			var cx := prev.x + (s.pos.x - prev.x) * t
			var cy := prev.y + (s.pos.y - prev.y) * t
			if absf(cx) <= Court.POST_X + 0.05:
				var top := Court.net_height(cx)
				var d := cy - top
				if d < -R * 0.35:
					# جسم الشبكة: تمتص معظم الطاقة وتسقط الكرة
					var sgn := 1.0 if prev.z > 0.0 else -1.0
					s.pos = Vector3(cx, cy, sgn * (R + 0.005))
					s.vel = Vector3(s.vel.x * 0.15, minf(s.vel.y * 0.25, 0.3), -s.vel.z * 0.06)
					s.spin *= 0.2
					ev |= EV_NET
				elif d < R:
					# شريط الشبكة: الكرة تلمسه وتعبر مع فقدان سرعة وانحراف للأعلى
					var depth := (R - d) / (R * 1.35)       # 0..1 عمق اللمس
					var keep := lerpf(0.82, 0.30, depth)
					var vz := s.vel.z * keep
					var up := absf(s.vel.z) * lerpf(0.04, 0.16, depth) + maxf(s.vel.y, 0.0) * 0.5
					if rng != null:
						up *= rng.randf_range(0.6, 1.3)
					s.vel = Vector3(s.vel.x * keep, up, vz)
					s.spin *= 0.4
					s.pos.y = maxf(s.pos.y, top + R * 0.6)
					ev |= EV_NET_CORD

	# ---- الأرض ----
	if s.pos.y <= R and s.vel.y < 0.0:
		# نقطة التلامس الدقيقة داخل الخطوة (مهم لدقة قرارات الخطوط)
		var k := 1.0
		if prev.y > s.pos.y and prev.y > R:
			k = clampf((prev.y - R) / (prev.y - s.pos.y), 0.0, 1.0)
		s.pos = prev.lerp(s.pos, k)
		s.pos.y = R
		s.bounce_pos = Vector3(s.pos.x, 0.0, s.pos.z)
		s.bounce_speed = s.vel.length()
		_bounce(s, surf, rng)
		ev |= EV_BOUNCE
		if absf(s.vel.y) < 0.55:
			s.vel.y = 0.0
			s.rolling = true
		else:
			s.pos += s.vel * (DT * (1.0 - k))

	# ---- حدود الصالة ----
	if absf(s.pos.x) > Court.ARENA_HALF_W - R:
		s.pos.x = signf(s.pos.x) * (Court.ARENA_HALF_W - R)
		s.vel.x = -s.vel.x * 0.45
		s.vel.z *= 0.7
		s.spin *= 0.5
		ev |= EV_WALL
	if absf(s.pos.z) > Court.ARENA_HALF_L - R:
		s.pos.z = signf(s.pos.z) * (Court.ARENA_HALF_L - R)
		s.vel.z = -s.vel.z * 0.45
		s.vel.x *= 0.7
		s.spin *= 0.5
		ev |= EV_WALL
	return ev


static func _bounce(s: State, surf: Dictionary, rng: RandomNumberGenerator) -> void:
	var e: float = surf["e"]
	var mu: float = surf["mu"]
	var vy := -s.vel.y           # موجبة
	# معامل الارتداد ينخفض قليلاً مع السرعة العمودية العالية
	var e_eff := clampf(e - 0.006 * (vy - 6.0), e - 0.06, e + 0.03)
	if rng != null and float(surf["noise"]) > 0.0:
		e_eff *= 1.0 + rng.randf_range(-1.0, 1.0) * float(surf["noise"])
	# سرعة نقطة التلامس (انزلاق أسفل الكرة على الأرض)
	var slip := Vector2(s.vel.x + R * s.spin.z, s.vel.z - R * s.spin.x)
	var slip_len := slip.length()
	if slip_len > 0.0001:
		# الدفع اللازم لإيقاف الانزلاق (تدحرج) مقابل أقصى دفع احتكاكي
		var j_roll := slip_len * ALPHA / (1.0 + ALPHA)
		var j_max := mu * (1.0 + e_eff) * vy
		# في حالة الإمساك (تدحرج) تنعكس المرونة المماسية جزئياً فتخرج الكرة بدوران أمامي زائد
		var j := minf(j_roll * (1.0 + GRIP_EX), j_max) if j_roll <= j_max else j_max
		var jv := slip / slip_len * j
		if rng != null and float(surf["noise"]) > 0.0:
			jv = jv.rotated(rng.randf_range(-1.0, 1.0) * float(surf["noise"]) * 0.6)
		s.vel.x -= jv.x
		s.vel.z -= jv.y
		s.spin.x += jv.y / (ALPHA * R)
		s.spin.z -= jv.x / (ALPHA * R)
	s.spin.y *= 0.85
	s.vel.y = vy * e_eff


static func _roll_step(s: State, surf: Dictionary) -> int:
	var ev := EV_NONE
	var h := Vector2(s.vel.x, s.vel.z)
	var sp := h.length()
	var prev_z := s.pos.z
	if sp > 0.02:
		var dec: float = float(surf["roll"]) * G + 0.02 * sp * sp
		var nsp := maxf(sp - dec * DT, 0.0)
		h = h / sp * nsp
		s.vel = Vector3(h.x, 0.0, h.y)
		s.pos += s.vel * DT
		s.pos.y = R
		# دوران التدحرج
		s.spin = Vector3(h.y / R, 0.0, -h.x / R)
	else:
		s.vel = Vector3.ZERO
		s.spin = Vector3.ZERO
	# الشبكة أثناء التدحرج
	if (prev_z > 0.0) != (s.pos.z > 0.0) and absf(s.pos.x) < Court.POST_X:
		s.pos.z = (R + 0.003) * (1.0 if prev_z > 0.0 else -1.0)
		s.vel.z = -s.vel.z * 0.2
		ev |= EV_NET
	if absf(s.pos.x) > Court.ARENA_HALF_W - R:
		s.pos.x = signf(s.pos.x) * (Court.ARENA_HALF_W - R)
		s.vel.x = -s.vel.x * 0.4
	if absf(s.pos.z) > Court.ARENA_HALF_L - R:
		s.pos.z = signf(s.pos.z) * (Court.ARENA_HALF_L - R)
		s.vel.z = -s.vel.z * 0.4
	return ev


## تنبؤ بالمسار: يعيد قائمة عينات كل sample_every خطوة حتى زمن max_t أو عدد ارتدادات
## كل عينة: {t, pos, vel, bounces}
## كما يعيد معلومات أول ارتدادين.
static func predict(src: State, surf: Dictionary, max_t: float, max_bounces: int = 2, sample_every: int = 2) -> Dictionary:
	var s := src.copy()
	var samples: Array = []
	var bounces: Array = []
	var net := EV_NONE
	var n := int(max_t / DT)
	var bc := 0
	for i in n:
		var ev := step(s, surf, null)
		if ev & EV_BOUNCE:
			bc += 1
			bounces.append({"t": (i + 1) * DT, "pos": s.bounce_pos, "vel": s.vel})
			if bc >= max_bounces:
				samples.append({"t": (i + 1) * DT, "pos": s.pos, "vel": s.vel, "bounces": bc})
				break
		if ev & (EV_NET | EV_NET_CORD):
			net |= ev
		if i % sample_every == 0:
			samples.append({"t": (i + 1) * DT, "pos": s.pos, "vel": s.vel, "bounces": bc})
		if s.rolling:
			break
	return {"samples": samples, "bounces": bounces, "net": net}
