class_name PlayerRig
extends Node3D
## جسم اللاعب (نموذج تشريحي من MakeHuman بهيكل عظمي من 55 عظمة) + نظام الأنيميشن الإجرائي.
## الحركة مبنية على أهداف (المضرب، اليدان، القدمان) تُحل بالحركة العكسية (IK) وتُطبَّق على العظام،
## بحيث يلتقي وجه المضرب بالكرة فعلياً لحظة الضرب، وتلتف الأصابع حول المقبض.
## الإحداثيات المحلية: -Z للأمام (نحو الشبكة)، +X يمين اللاعب، +Y للأعلى.

const SWING_NOMINAL := 0.24
const HEAD_DIST := 0.46       # من مركز القبضة إلى مركز رأس المضرب
const GRIP_BETA := deg_to_rad(42.0)   # ميل اليد على المقبض (قبضة المصافحة)
const GRIP_A := 0.083         # من مفصل الرسغ إلى مركز الكف على محور اليد
const GRIP_B := 0.030         # إزاحة المقبض نحو باطن الكف

enum Mode { READY, PREP, SWING, SERVE_STANCE, SERVE_TOSS, SERVE_SWING, REACT }
enum Clip { FH_DRIVE, BH_DRIVE, FH_SLICE, BH_SLICE, FH_VOLLEY, BH_VOLLEY, OVERHEAD, BH2_DRIVE }
enum React { NONE, FIST, ARMS_UP, DEJECT, HANDS_HIPS, BOUNCE, STRINGS, WIPE }

# أبعاد الجسم (تُقرأ من الهيكل العظمي)
var STAND_HIP := 0.975
var THIGH := 0.46
var SHIN := 0.45
var ANKLE_H := 0.09
var UPPER_ARM := 0.31
var FOREARM := 0.27


class Pose:
	var grip := Vector3(0.12, 1.08, -0.32)
	var axis := Vector3(-0.35, 0.45, -0.82)
	var nrm := Vector3(1, 0, 0)
	var lhand := Vector3(-0.1, 1.1, -0.4)
	var pole := Vector3(0.4, -0.8, 0.45)
	var turn := 0.0
	var hip := 0.0
	var lf := 6.0
	var ls := 0.0
	var cr := 0.3
	var jp := 0.0
	var sway := Vector3.ZERO
	var stance := 0.0
	var foot_l := Vector2(-0.24, 0.0)
	var foot_r := Vector2(0.24, 0.0)
	var offgrip := 0.0        # اليد الحرة على المضرب (1) أو حرة (0)
	var off_ps := 1.0         # اتجاه باطن اليد الحرة بالنسبة لوجه المضرب
	var dom_ps := 1.0         # اتجاه باطن اليد الضاربة (1 أمامية، -1 خلفية)
	var off_curl := 0.25      # انقباض أصابع اليد الحرة
	var off_pole := Vector3(-0.4, -0.8, 0.45)
	var head_pitch := 0.0
	var look_w := 1.0         # وزن متابعة الرأس للهدف (0 = الرأس حر حسب الوضعية)

	func blend(o: Pose, w: float) -> Pose:
		var p := Pose.new()
		p.grip = grip.lerp(o.grip, w)
		p.axis = axis.lerp(o.axis, w).normalized()
		p.nrm = nrm.lerp(o.nrm, w).normalized()
		p.lhand = lhand.lerp(o.lhand, w)
		p.pole = pole.lerp(o.pole, w)
		p.turn = lerpf(turn, o.turn, w)
		p.hip = lerpf(hip, o.hip, w)
		p.lf = lerpf(lf, o.lf, w)
		p.ls = lerpf(ls, o.ls, w)
		p.cr = lerpf(cr, o.cr, w)
		p.jp = lerpf(jp, o.jp, w)
		p.sway = sway.lerp(o.sway, w)
		p.stance = lerpf(stance, o.stance, w)
		p.foot_l = foot_l.lerp(o.foot_l, w)
		p.foot_r = foot_r.lerp(o.foot_r, w)
		p.offgrip = lerpf(offgrip, o.offgrip, w)
		p.off_ps = lerpf(off_ps, o.off_ps, w)
		p.dom_ps = lerpf(dom_ps, o.dom_ps, w)
		p.off_curl = lerpf(off_curl, o.off_curl, w)
		p.off_pole = off_pole.lerp(o.off_pole, w)
		p.head_pitch = lerpf(head_pitch, o.head_pitch, w)
		p.look_w = lerpf(look_w, o.look_w, w)
		return p


var hand := 1
var two_handed := false
var body_id := "athlete"
var look := {}

# --- مدخلات من اللاعب ---
var move_vel := Vector3.ZERO      # السرعة في الإحداثيات المحلية
var look_target := Vector3(0, 1.2, -10)   # محلي
var alert := 0.0                  # 0..1 حالة التأهب (الكرة في اللعب)
var balance := Vector2.ZERO       # اختلال التوازن (x جانبي، y أمامي) يتلاشى تلقائياً
var fatigue := 0.0                # 0..1 يؤثر على الوقفة والتنفس

# --- حالة الأنيميشن ---
var mode := Mode.READY
var clip_id := Clip.FH_DRIVE
var clip_keys: Array = []
var clip_t := 0.0
var lift := 0.5
var prep_w := 0.0
var contact := Vector3(0.75, 0.95, -0.42)
var hit_dir := Vector3(0, 0, -1)
var serve_t := 0.0
var react_id := React.NONE
var react_t := 0.0
var _gait := 0.0
var _run_turn := 0.0
var _time := 0.0
var _split_t := -1.0
var _blend_from: Pose = null
var _blend_t := 1.0
var _blend_dur := 0.2
var _last: Pose = Pose.new()
var _foot_pos := [Vector3(-0.2, 0.09, 0), Vector3(0.2, 0.09, 0)]
var _lhand_world_cache := Vector3.ZERO

# --- الهيكل العظمي ---
var _model: Node3D
var skel: Skeleton3D
var _bi := {}            # اسم ← فهرس
var _rest := {}          # اسم ← التحويل العالمي في وضع الراحة
var _rest_local := {}    # اسم ← التحويل المحلي في وضع الراحة
var _parent := {}
var _g := {}             # التحويلات العالمية المحسوبة لهذا الإطار
var _dom := "R"
var _off := "L"
var _fa_hand_rel := {}   # علاقة الرسغ المحايدة بين الساعد واليد
var _curl_cache := {}
var _racket: Node3D
var _ball_hand := Vector3.ZERO
var catch_pt := Vector3.ZERO
var catch_w := 0.0
var _acc := Vector3.ZERO
var _prev_vel := Vector3.ZERO
var _brake := 0.0
var _skin_mat: ShaderMaterial
var _cloth_mats: Array = []

# --- تثبيت القدمين على الأرض (بإحداثيات العالم) ---
var _fw := [Vector3.ZERO, Vector3.ZERO]        # موضع القدم المثبّتة على الأرض (عالمي)
var _fyaw := [0.0, 0.0]                        # اتجاه القدم (عالمي)
var _fs := [1.0, 1.0]                          # تقدّم الخطوة 0..1 (1 = القدم على الأرض)
var _ffrom := [Vector3.ZERO, Vector3.ZERO]
var _fyaw_from := [0.0, 0.0]
var _fdur := [0.2, 0.2]
var _flift := [0.05, 0.05]
var _plant_t := [0.0, 0.0]
var _feet_init := false
var _last_step := 1
var _stride_sig := 0.0     # +1 القدم اليسرى في الأمام، -1 اليمنى
var _lat_shift := 0.0      # انتقال الوزن نحو قدم الارتكاز
var _hip_drop := 0.0
var _bob := 0.0
# --- الرأس والرقبة ---
var _head_yaw := 0.0
var _head_pitch := 0.0
var _head_vy := 0.0
var _head_vp := 0.0
var _sweat := 0.0
var _sweat_t := 0.0

const DRIVEN := ["Hips", "Spine", "Chest", "Neck", "Head",
	"Clavicle.L", "UpperArm.L", "UpperArmTwist.L", "ForeArm.L", "ForeArmTwist.L", "Hand.L",
	"Clavicle.R", "UpperArm.R", "UpperArmTwist.R", "ForeArm.R", "ForeArmTwist.R", "Hand.R",
	"UpLeg.L", "Leg.L", "Foot.L", "Toes.L", "UpLeg.R", "Leg.R", "Foot.R", "Toes.R"]
const FINGERS := ["Thumb", "Index", "Middle", "Ring", "Pinky"]


func setup(p_look: Dictionary, p_hand: int, p_body: String = "athlete", p_two_handed: bool = false) -> void:
	look = p_look
	hand = p_hand
	body_id = p_body
	two_handed = p_two_handed
	_dom = "R" if hand > 0 else "L"
	_off = "L" if hand > 0 else "R"
	_model = (load("res://assets/characters/body_%s.glb" % body_id) as PackedScene).instantiate()
	add_child(_model)
	var mats := HumanLook.apply(_model, look)
	_skin_mat = mats.get("skin")
	_cloth_mats = [mats.get("shirt"), mats.get("shorts")]
	skel = _find_skel(_model)
	for i in skel.get_bone_count():
		var n := skel.get_bone_name(i)
		_bi[n] = i
		_rest[n] = skel.get_bone_global_rest(i)
		_rest_local[n] = skel.get_bone_rest(i)
		var pi := skel.get_bone_parent(i)
		_parent[n] = skel.get_bone_name(pi) if pi >= 0 else ""
	STAND_HIP = _o("Hips").y
	THIGH = _o("Leg.L").distance_to(_o("UpLeg.L"))
	SHIN = _o("Foot.L").distance_to(_o("Leg.L"))
	ANKLE_H = _o("Foot.L").y
	UPPER_ARM = _o("ForeArm.R").distance_to(_o("UpperArm.R"))
	FOREARM = _o("Hand.R").distance_to(_o("ForeArm.R"))
	for s in ["L", "R"]:
		_fa_hand_rel[s] = (_rest["ForeArm." + s] as Transform3D).basis.inverse() * (_rest["Hand." + s] as Transform3D).basis
	_foot_pos = [Vector3(_o("Foot.L").x, ANKLE_H, 0), Vector3(_o("Foot.R").x, ANKLE_H, 0)]
	_build_racket()
	_add_wristbands()
	_build_contact_shadows()
	for m in _all_meshes(_model):
		m.extra_cull_margin = 0.6
	_apply(_ready_pose(0.0), 0.0)


## ظل تماسّ ناعم تحت كل قدم (يربط اللاعب بالأرض بصرياً ويخفت عند ارتفاع القدم)
var _foot_blobs: Array = []
func _build_contact_shadows() -> void:
	for i in 2:
		var pm := PlaneMesh.new()
		pm.size = Vector2(0.30, 0.44)
		var mi := MeshInstance3D.new()
		mi.mesh = pm
		var m := ShaderMaterial.new()
		m.shader = load("res://shaders/blob_shadow.gdshader")
		m.set_shader_parameter("strength", 0.4)
		mi.material_override = m
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)
		_foot_blobs.append(mi)


func _add_wristbands() -> void:
	var col: Color = look.get("wristband", look.get("shirt_trim", Color(0.95, 0.95, 0.95)))
	for s in ["L", "R"]:
		var ba := BoneAttachment3D.new()
		ba.bone_name = "ForeArmTwist." + s
		skel.add_child(ba)
		var ln := _o("Hand." + s).distance_to(_o("ForeArmTwist." + s))
		var st := MeshKit.begin()
		MeshKit.add_tube(st, [[ln * 0.60, 0.036, 0.033, col], [ln * 0.97, 0.035, 0.032, col]], 12, Transform3D.IDENTITY, false, false)
		var mi := MeshInstance3D.new()
		mi.mesh = MeshKit.finish(st)
		var m := MeshKit.vcol_material(0.95)
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		mi.material_override = m
		ba.add_child(mi)


func _find_skel(n: Node) -> Skeleton3D:
	if n is Skeleton3D:
		return n
	for c in n.get_children():
		var s := _find_skel(c)
		if s != null:
			return s
	return null


func _all_meshes(n: Node) -> Array:
	var out := []
	if n is MeshInstance3D:
		out.append(n)
	for c in n.get_children():
		out += _all_meshes(c)
	return out


func set_shadow(on: bool) -> void:
	for m in _all_meshes(_model):
		(m as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if on else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func _o(n: String) -> Vector3:
	return (_rest[n] as Transform3D).origin


func _build_racket() -> void:
	_racket = Node3D.new()
	add_child(_racket)
	var frame_c: Color = look.get("racket", Color(0.08, 0.08, 0.1))
	var grip_c := Color(0.92, 0.92, 0.9)
	var st := MeshKit.begin()
	MeshKit.add_tube(st, [[-0.075, 0.016, 0.014, grip_c], [0.10, 0.015, 0.013, grip_c], [0.102, 0.012, 0.011, frame_c], [0.15, 0.011, 0.010, frame_c]], 8)
	for sgn in [-1.0, 1.0]:
		var a := Vector3(0.0, 0.15, 0.0)
		var b := Vector3(0.085 * sgn, 0.325, 0.0)
		var dir := (b - a)
		var ln := dir.length()
		var bas := Basis(Quaternion(Vector3.UP, dir / ln))
		MeshKit.add_tube(st, [[0.0, 0.010, 0.010, frame_c], [ln, 0.010, 0.010, frame_c]], 6, Transform3D(bas, a))
	var segs := 28
	var hc := Vector3(0, HEAD_DIST, 0)
	var ra := 0.128
	var rb := 0.168
	var tube := 0.0105
	var verts: Array = []
	var ring := 6
	for i in segs:
		var a := TAU * i / segs
		var c := hc + Vector3(cos(a) * ra, sin(a) * rb, 0)
		var outward := Vector3(cos(a) * rb, sin(a) * ra, 0).normalized()
		for j in ring:
			var b := TAU * j / ring
			verts.append(c + outward * cos(b) * tube + Vector3(0, 0, 1) * sin(b) * tube * 1.25)
	for i in segs:
		var i2 := (i + 1) % segs
		for j in ring:
			var j2 := (j + 1) % ring
			var q := [verts[i * ring + j], verts[i2 * ring + j], verts[i2 * ring + j2], verts[i * ring + j2]]
			for t in [[0, 2, 1], [0, 3, 2]]:
				for k in t:
					st.set_smooth_group(0)
					st.set_color(frame_c)
					st.add_vertex(q[k])
	var mi := MeshInstance3D.new()
	mi.mesh = MeshKit.finish(st)
	var rm := MeshKit.vcol_material(0.35, 0.3)
	rm.cull_mode = BaseMaterial3D.CULL_DISABLED
	mi.material_override = rm
	_racket.add_child(mi)
	var q := QuadMesh.new()
	q.size = Vector2(ra * 2.0, rb * 2.0)
	var smi := MeshInstance3D.new()
	smi.mesh = q
	smi.position = hc
	var sm := ShaderMaterial.new()
	sm.shader = load("res://shaders/strings.gdshader")
	smi.material_override = sm
	smi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_racket.add_child(smi)


# =====================================================================
#  ردود الفعل والحركات بين النقاط
# =====================================================================
func react(id: int) -> void:
	if react_id == id and mode == Mode.REACT:
		return
	_start_blend(0.35)
	mode = Mode.REACT
	react_id = id
	react_t = 0.0


func ball_bounce_hand() -> Vector3:
	return _ball_hand


# =====================================================================
#  واجهة التحكم بالأنيميشن
# =====================================================================
func set_ready(blend: float = 0.22) -> void:
	if mode == Mode.READY:
		return
	_start_blend(blend)
	mode = Mode.READY


func set_prep(side: int, type: int, volley: bool, overhead: bool) -> void:
	var id := _clip_for(side, type, volley, overhead)
	if mode == Mode.PREP and id == clip_id:
		return
	_start_blend(0.20)
	mode = Mode.PREP
	clip_id = id
	lift = _lift_for(type)
	clip_keys = _make_clip(id)
	var nc := _nominal_contact(id)
	contact = Vector3(nc.x * hand, nc.y, nc.z)
	prep_w = 0.0


func start_swing(side: int, type: int, volley: bool, overhead: bool, time_to_contact: float, contact_local: Vector3, dir_local: Vector3) -> void:
	var id := _clip_for(side, type, volley, overhead)
	_start_blend(0.07 if mode == Mode.PREP and id == clip_id else 0.10)
	mode = Mode.SWING
	clip_id = id
	lift = _lift_for(type)
	contact = contact_local
	hit_dir = dir_local
	clip_keys = _make_clip(id)
	clip_t = -time_to_contact


func update_contact(contact_local: Vector3, time_to_contact: float) -> void:
	contact = contact_local
	if mode == Mode.SWING and clip_t < 0.0:
		clip_t = -time_to_contact


func serve_stance() -> void:
	_start_blend(0.35)
	mode = Mode.SERVE_STANCE


func serve_toss() -> void:
	_start_blend(0.08)
	mode = Mode.SERVE_TOSS
	serve_t = 0.0


func serve_swing(time_to_contact: float, contact_local: Vector3, dir_local: Vector3) -> void:
	_start_blend(0.08)
	mode = Mode.SERVE_SWING
	clip_id = Clip.OVERHEAD
	contact = contact_local
	hit_dir = dir_local
	clip_keys = _make_clip(Clip.OVERHEAD)
	clip_t = -time_to_contact


func split_step() -> void:
	if _split_t < 0.0:
		_split_t = 0.0


func is_swinging() -> bool:
	return mode == Mode.SWING or mode == Mode.SERVE_SWING


## موضع اليد الحرة (التي تمسك الكرة عند الإرسال) بالإحداثيات العالمية
func off_hand_world() -> Vector3:
	return global_transform * _lhand_world_cache


func _start_blend(dur: float) -> void:
	_blend_from = _last
	_blend_t = 0.0
	_blend_dur = maxf(dur, 0.01)


func _clip_for(side: int, type: int, volley: bool, overhead: bool) -> int:
	if overhead:
		return Clip.OVERHEAD
	if volley:
		return Clip.FH_VOLLEY if side > 0 else Clip.BH_VOLLEY
	if type == Shot.Type.SLICE or type == Shot.Type.DROP:
		return Clip.FH_SLICE if side > 0 else Clip.BH_SLICE
	if side < 0 and two_handed:
		return Clip.BH2_DRIVE
	return Clip.FH_DRIVE if side > 0 else Clip.BH_DRIVE


func _lift_for(type: int) -> float:
	match type:
		Shot.Type.FLAT: return 0.15
		Shot.Type.TOPSPIN: return 0.85
		Shot.Type.LOB: return 1.0
	return 0.4


# =====================================================================
#  تعريف الحركات (مفاتيح زمنية بالنسبة للحظة الضرب)
#  كل مفتاح: t, g (القبضة) أو c (من نقطة التلامس)، ax اتجاه المضرب، nr عمودي الأوتار،
#  turn دوران الصدر (موجب نحو يد الضرب)، hip دوران الحوض، cr انثناء الركب، lh اليد الحرة
# =====================================================================
func _k(t: float, g: Variant, ax: Vector3, nr: Vector3, turn: float, hip: float, cr: float, lh: Variant, extra: Dictionary = {}) -> Dictionary:
	var d := {"t": t, "g": g, "ax": ax.normalized(), "nr": nr.normalized(), "turn": turn, "hip": hip, "cr": cr, "lh": lh,
		"lf": 6.0, "ls": 0.0, "jp": 0.0, "pole": Vector3(0.4, -0.8, 0.45), "sw": Vector3.ZERO}
	for k in extra:
		d[k] = extra[k]
	return d


func _make_clip(id: int) -> Array:
	var L := lift
	match id:
		Clip.FH_DRIVE:
			# لفّ الكتفين ← إسقاط المضرب ← تأخّر رأس المضرب ← التلامس ← الامتداد عبر الكرة ← الالتفاف حول الكتف
			return [
				_k(-0.24, Vector3(0.50, 1.24, 0.28), Vector3(0.20, 0.92, 0.33), Vector3(0.9, -0.1, -0.4), 88, 52, 0.46, Vector3(0.36, 1.20, -0.30), {"sw": Vector3(0.07, 0, 0.07), "lf": 5.0}),
				_k(-0.11, Vector3(0.62, 0.82 - 0.14 * L, 0.34), Vector3(0.35, -0.25 - 0.25 * L, 0.90), Vector3(0.5, -0.6, -0.6), 66, 36, 0.66, Vector3(0.12, 1.14, -0.44), {"sw": Vector3(0.06, 0, 0.05), "lf": 8.0}),
				_k(-0.045, Vector3(0.52, 0.80 - 0.10 * L, 0.02), Vector3(0.55, -0.15 - 0.15 * L, 0.82), Vector3(0.35, -0.45, -0.82), 36, 12, 0.54, Vector3(-0.10, 1.12, -0.36), {"sw": Vector3(0.02, 0, -0.02), "lf": 9.0}),
				_k(0.0, null, Vector3(0.93, 0.08 + 0.12 * L, -0.30), Vector3(0, -0.12 * L, -1), 6, -4, 0.36, Vector3(-0.26, 1.12, -0.16), {"lf": 10.0, "sw": Vector3(-0.02, 0, -0.08)}),
				_k(0.05, Vector3(-0.10, 0.10 + 0.16 * L, -0.34), Vector3(0.62, 0.35 + 0.20 * L, -0.70), Vector3(-0.3, -0.25, -0.92), -16, -14, 0.28, Vector3(-0.28, 1.14, -0.10), {"rel": true, "lf": 9.0, "sw": Vector3(-0.04, 0, -0.11)}),
				_k(0.13, Vector3(0.02, 1.36 + 0.12 * L, -0.56), Vector3(-0.55, 0.75, -0.30), Vector3(-0.6, -0.5, -0.6), -42, -24, 0.22, Vector3(-0.28, 1.18, -0.06), {"lf": 7.0, "sw": Vector3(-0.05, 0, -0.12)}),
				_k(0.32, Vector3(-0.26, 1.42, -0.12), Vector3(-0.45, 0.20, 0.87), Vector3(-0.8, 0.1, -0.5), -66, -34, 0.20, Vector3(-0.25, 1.27, -0.10), {"sw": Vector3(-0.04, 0, -0.08)}),
			]
		Clip.BH_DRIVE:
			return [
				_k(-0.24, Vector3(-0.42, 1.05, 0.30), Vector3(-0.15, 0.85, 0.50), Vector3(-0.8, -0.1, -0.5), -108, -62, 0.46, "throat", {"sw": Vector3(-0.06, 0, 0.07)}),
				_k(-0.11, Vector3(-0.50, 0.72 - 0.10 * L, 0.22), Vector3(-0.25, -0.30 - 0.15 * L, 0.92), Vector3(-0.5, -0.6, -0.6), -98, -56, 0.66, Vector3(-0.45, 0.88, 0.35), {"sw": Vector3(-0.05, 0, 0.05), "lf": 8.0}),
				_k(-0.045, Vector3(-0.46, 0.76 - 0.08 * L, -0.06), Vector3(-0.60, -0.15 - 0.10 * L, 0.78), Vector3(-0.35, -0.45, -0.82), -86, -50, 0.54, Vector3(-0.42, 0.95, 0.42), {"sw": Vector3(-0.02, 0, -0.02), "lf": 8.0}),
				_k(0.0, null, Vector3(-0.93, 0.12 + 0.10 * L, -0.32), Vector3(0, -0.10 * L, -1), -72, -45, 0.36, Vector3(-0.35, 1.0, 0.50), {"lf": 8.0, "sw": Vector3(0.0, 0, -0.08)}),
				_k(0.05, Vector3(0.14, 0.12 + 0.12 * L, -0.30), Vector3(-0.55, 0.45 + 0.15 * L, -0.70), Vector3(0.3, -0.25, -0.92), -62, -40, 0.28, Vector3(-0.42, 1.0, 0.56), {"rel": true, "sw": Vector3(0.02, 0, -0.10)}),
				_k(0.13, Vector3(0.24, 1.38 + 0.08 * L, -0.62), Vector3(0.30, 0.90, -0.30), Vector3(0.6, -0.4, -0.6), -48, -35, 0.22, Vector3(-0.46, 1.0, 0.58), {"sw": Vector3(0.03, 0, -0.10)}),
				_k(0.32, Vector3(0.46, 1.58, -0.30), Vector3(0.35, 0.80, 0.48), Vector3(0.8, 0.0, -0.5), -30, -25, 0.18, Vector3(-0.40, 0.95, 0.45), {"sw": Vector3(0.02, 0, -0.06)}),
			]
		Clip.BH2_DRIVE:
			return [
				_k(-0.24, Vector3(-0.46, 1.06, 0.26), Vector3(-0.15, 0.85, 0.50), Vector3(-0.8, -0.1, -0.5), -100, -62, 0.46, "handle", {"sw": Vector3(-0.06, 0, 0.07)}),
				_k(-0.11, Vector3(-0.52, 0.74 - 0.10 * L, 0.16), Vector3(-0.25, -0.30 - 0.15 * L, 0.92), Vector3(-0.5, -0.6, -0.6), -90, -54, 0.66, "handle", {"sw": Vector3(-0.05, 0, 0.05), "lf": 8.0}),
				_k(-0.045, Vector3(-0.44, 0.78 - 0.08 * L, -0.08), Vector3(-0.55, -0.20 - 0.10 * L, 0.80), Vector3(-0.35, -0.45, -0.82), -72, -42, 0.54, "handle", {"sw": Vector3(-0.02, 0, -0.02), "lf": 8.0}),
				_k(0.0, null, Vector3(-0.93, 0.12 + 0.10 * L, -0.32), Vector3(0, -0.10 * L, -1), -50, -32, 0.36, "handle", {"lf": 8.0, "sw": Vector3(0.0, 0, -0.08)}),
				_k(0.05, Vector3(0.10, 0.10 + 0.10 * L, -0.26), Vector3(-0.60, 0.40, -0.70), Vector3(0.3, -0.25, -0.92), -34, -22, 0.28, "handle", {"rel": true, "sw": Vector3(0.02, 0, -0.10)}),
				_k(0.13, Vector3(0.08, 1.30 + 0.08 * L, -0.60), Vector3(0.35, 0.85, -0.38), Vector3(0.6, -0.4, -0.6), -14, -8, 0.22, "handle", {"sw": Vector3(0.03, 0, -0.10)}),
				_k(0.32, Vector3(0.30, 1.52, 0.04), Vector3(0.20, 0.40, 0.89), Vector3(0.85, 0.0, -0.4), 22, 8, 0.18, "handle", {"sw": Vector3(0.02, 0, -0.06)}),
			]
		Clip.FH_SLICE:
			return [
				_k(-0.24, Vector3(0.45, 1.45, 0.20), Vector3(0.2, 0.85, 0.45), Vector3(0.8, 0.2, -0.5), 70, 40, 0.3, Vector3(0.2, 1.2, -0.35)),
				_k(-0.10, Vector3(0.50, 1.25, 0.12), Vector3(0.5, 0.6, 0.6), Vector3(0.5, 0.3, -0.8), 55, 30, 0.38, Vector3(0.0, 1.15, -0.35)),
				_k(0.0, null, Vector3(0.92, 0.22, -0.25), Vector3(0, 0.35, -0.94), 20, 10, 0.42, Vector3(-0.25, 1.1, -0.15)),
				_k(0.12, Vector3(0.05, 0.80, -0.75), Vector3(-0.3, 0.1, -0.95), Vector3(0.2, 0.9, -0.3), -15, -5, 0.45, Vector3(-0.3, 1.1, 0.0)),
				_k(0.30, Vector3(-0.15, 0.95, -0.50), Vector3(-0.55, 0.4, -0.7), Vector3(0.2, 0.8, -0.5), -30, -10, 0.3, Vector3(-0.28, 1.15, -0.05)),
			]
		Clip.BH_SLICE:
			return [
				_k(-0.24, Vector3(-0.30, 1.42, 0.22), Vector3(-0.20, 0.80, 0.55), Vector3(-0.8, 0.2, -0.5), -100, -55, 0.28, "throat"),
				_k(-0.10, Vector3(-0.36, 1.25, 0.10), Vector3(-0.45, 0.60, 0.65), Vector3(-0.5, 0.3, -0.8), -92, -52, 0.36, "throat"),
				_k(0.0, null, Vector3(-0.90, 0.25, -0.20), Vector3(0, 0.35, -0.94), -80, -50, 0.42, Vector3(-0.40, 1.05, 0.45)),
				_k(0.12, Vector3(0.20, 0.78, -0.78), Vector3(0.35, 0.10, -0.93), Vector3(-0.2, 0.9, -0.3), -65, -42, 0.46, Vector3(-0.42, 1.0, 0.55)),
				_k(0.30, Vector3(0.42, 0.95, -0.55), Vector3(0.6, 0.45, -0.65), Vector3(-0.2, 0.8, -0.5), -50, -35, 0.3, Vector3(-0.38, 0.98, 0.45)),
			]
		Clip.FH_VOLLEY:
			return [
				_k(-0.16, Vector3(0.38, 1.18, -0.15), Vector3(0.35, 0.90, 0.10), Vector3(0.3, 0.1, -0.95), 40, 15, 0.38, Vector3(-0.2, 1.15, -0.3)),
				_k(0.0, null, Vector3(0.80, 0.55, -0.20), Vector3(0, 0.15, -1), 25, 8, 0.46, Vector3(-0.24, 1.12, -0.2)),
				_k(0.12, Vector3(-0.12, -0.12, -0.28), Vector3(0.70, 0.55, -0.45), Vector3(0, 0.25, -1), 10, 0, 0.42, Vector3(-0.26, 1.1, -0.15), {"rel": true}),
				_k(0.28, Vector3(0.15, 1.05, -0.35), Vector3(-0.3, 0.6, -0.75), Vector3(1, 0, 0), 0, 0, 0.32, "throat"),
			]
		Clip.BH_VOLLEY:
			return [
				_k(-0.16, Vector3(-0.25, 1.18, -0.12), Vector3(-0.30, 0.92, 0.15), Vector3(-0.3, 0.1, -0.95), -55, -20, 0.38, "throat"),
				_k(0.0, null, Vector3(-0.80, 0.55, -0.22), Vector3(0, 0.15, -1), -45, -15, 0.46, Vector3(-0.3, 1.1, 0.2)),
				_k(0.12, Vector3(0.12, -0.12, -0.28), Vector3(-0.70, 0.55, -0.45), Vector3(0, 0.25, -1), -35, -10, 0.42, Vector3(-0.35, 1.05, 0.3), {"rel": true}),
				_k(0.28, Vector3(0.10, 1.05, -0.35), Vector3(-0.3, 0.6, -0.75), Vector3(1, 0, 0), 0, 0, 0.32, "throat"),
			]
		Clip.OVERHEAD:
			var up := Vector3(0.9, -0.15, 0.5)
			return [
				_k(-0.26, Vector3(0.42, 1.60, 0.26), Vector3(-0.10, 0.97, 0.05), Vector3(0.9, 0.1, -0.4), 95, 70, 0.66, Vector3(-0.02, 2.08, -0.40), {"lf": -10.0, "pole": up, "sw": Vector3(0, 0, -0.06)}),
				_k(-0.13, Vector3(0.32, 1.76, 0.20), Vector3(-0.15, -0.95, 0.28), Vector3(0.9, -0.1, -0.4), 70, 50, 0.38, Vector3(-0.10, 1.55, -0.30), {"lf": -2.0, "pole": up}),
				_k(0.0, null, Vector3(0.03, 0.98, -0.17), Vector3(0, -0.15, -1), 15, 10, 0.0, Vector3(-0.12, 1.15, -0.22), {"lf": 10.0, "jp": 0.14, "ls": -10.0, "pole": up}),
				_k(0.12, Vector3(0.02, 1.55, -0.72), Vector3(-0.30, -0.45, -0.84), Vector3(-0.3, -0.8, -0.4), -25, -10, 0.1, Vector3(-0.15, 1.1, -0.2), {"lf": 22.0, "jp": 0.08}),
				_k(0.34, Vector3(-0.34, 0.92, -0.42), Vector3(-0.45, -0.75, 0.45), Vector3(-0.8, -0.2, -0.5), -50, -25, 0.32, Vector3(-0.2, 1.1, -0.15), {"lf": 18.0}),
			]
	return []


func _mir(v: Vector3) -> Vector3:
	return Vector3(v.x * hand, v.y, v.z)


## تحويل مفتاح إلى وضعية (مع ربط مفتاح التلامس بموضع الكرة الفعلي)
func _key_pose(k: Dictionary, id: int) -> Pose:
	var p := Pose.new()
	p.axis = _mir(k["ax"])
	p.nrm = _mir(k["nr"])
	var nominal := _nominal_contact(id)
	var dy: float = (contact.y - nominal.y) * 0.65
	var c_grip := contact - _contact_axis(id) * HEAD_DIST
	if k["g"] == null:
		p.grip = c_grip
		if id != Clip.OVERHEAD:
			# وجه المضرب يتجه نحو اتجاه الضربة
			var n: Vector3 = (hit_dir + Vector3(0, float(k["nr"].y), 0)).normalized()
			p.nrm = n
	elif k.get("rel", false):
		p.grip = c_grip + _mir(k["g"])
	else:
		var g: Vector3 = _mir(k["g"])
		# تكييف المسار مع ارتفاع وبعد الكرة الفعلي
		var w := clampf(1.0 - absf(float(k["t"])) / 0.34, 0.0, 1.0)
		g.y += dy * (0.5 + 0.5 * w)
		g.x += (contact.x - nominal.x * hand) * 0.6 * w
		g.z += (contact.z - nominal.z) * 0.5 * w
		p.grip = g
	p.turn = k["turn"]
	p.hip = k["hip"]
	p.cr = float(k["cr"]) + clampf((nominal.y - contact.y) * 0.9, -0.15, 0.45) * (0.0 if id == Clip.OVERHEAD else 1.0)
	p.lf = k["lf"]
	p.ls = k["ls"]
	p.jp = k["jp"]
	p.pole = _mir(k["pole"])
	if id == Clip.OVERHEAD:
		p.jp += clampf(contact.y - 2.70, -0.14, 0.25) * clampf(1.0 - absf(float(k["t"])) / 0.2, 0.0, 1.0)
	# الميل الجانبي عند التمدد نحو كرة بعيدة
	var lat := contact.x * hand
	var side_sign := 1.0 if nominal.x > 0.0 else -1.0
	var ext := (absf(lat) - absf(nominal.x)) if id != Clip.OVERHEAD else 0.0
	var wk := clampf(1.0 - absf(float(k["t"])) / 0.25, 0.0, 1.0)
	p.ls += clampf(ext * 24.0, -8.0, 30.0) * side_sign * wk
	p.sway = Vector3(clampf(ext * 0.4, -0.15, 0.5) * side_sign * hand * wk, 0, clampf((contact.z - nominal.z) * 0.35, -0.35, 0.2) * wk)
	p.sway += _mir(k["sw"])       # نقل الوزن من القدم الخلفية إلى الأمامية
	if k["lh"] is String:
		if k["lh"] == "handle":
			p.lhand = p.grip + p.axis * 0.088
			p.off_ps = 1.0
		else:
			p.lhand = p.grip + p.axis * 0.24
			p.off_ps = -1.0
		p.offgrip = 1.0
	else:
		p.lhand = _mir(k["lh"])
		p.offgrip = 0.0
		p.off_curl = 0.45
		p.off_pole = _mir(Vector3(-0.45, -0.75, 0.45))
	if id == Clip.BH_DRIVE or id == Clip.BH_SLICE or id == Clip.BH_VOLLEY or id == Clip.BH2_DRIVE:
		p.dom_ps = -1.0
	p.stance = 1.0
	var fs := _stance_feet(id)
	p.foot_l = fs[0]
	p.foot_r = fs[1]
	# اندفاع جانبي (لانج) للكرات البعيدة: القدم الخارجية تخطو بعيداً والركبة تنثني بعمق
	if id != Clip.OVERHEAD and ext > 0.22:
		var e := clampf((ext - 0.22) / 0.9, 0.0, 1.0) * wk
		var dxs := 0.55 * e * signf(contact.x)
		if contact.x > 0.0:
			p.foot_r += Vector2(dxs, -0.22 * e)
		else:
			p.foot_l += Vector2(dxs, -0.22 * e)
		p.cr += 0.45 * e
		p.sway.x += dxs * 0.35
	# قفزة للكرات العالية فوق الكتف
	if id != Clip.OVERHEAD and contact.y > 1.45:
		p.jp += clampf((contact.y - 1.45) * 0.32, 0.0, 0.16) * wk
		p.cr = maxf(p.cr - 0.2 * wk, 0.0)
	return p


func _hip_at(t: float) -> float:
	var n := clip_keys.size()
	if t <= float(clip_keys[0]["t"]):
		return float(clip_keys[0]["hip"])
	for i in n - 1:
		var a: float = clip_keys[i]["t"]
		var b: float = clip_keys[i + 1]["t"]
		if t <= b:
			return lerpf(float(clip_keys[i]["hip"]), float(clip_keys[i + 1]["hip"]), (t - a) / (b - a))
	return float(clip_keys[n - 1]["hip"])


func _nominal_contact(id: int) -> Vector3:
	match id:
		Clip.FH_DRIVE, Clip.FH_SLICE: return Vector3(0.75, 0.95, -0.42)
		Clip.BH_DRIVE, Clip.BH_SLICE: return Vector3(-0.60, 0.92, -0.52)
		Clip.BH2_DRIVE: return Vector3(-0.52, 0.92, -0.50)
		Clip.FH_VOLLEY: return Vector3(0.65, 1.25, -0.55)
		Clip.BH_VOLLEY: return Vector3(-0.55, 1.25, -0.55)
	return Vector3(0.20, 2.70, -0.42)


func _contact_axis(id: int) -> Vector3:
	for k in clip_keys:
		if k["g"] == null:
			return _mir(k["ax"])
	return Vector3.UP


## مواضع القدمين في وقفة الضربة (x, z) — [يسار، يمين] بعد عكس اليد
func _stance_feet(id: int) -> Array:
	var a: Vector2
	var b: Vector2
	match id:
		Clip.FH_DRIVE, Clip.FH_SLICE, Clip.FH_VOLLEY:
			a = Vector2(-0.22, -0.26)      # القدم المعاكسة لليد
			b = Vector2(0.31, 0.17)        # قدم جهة اليد
		Clip.BH_DRIVE, Clip.BH_SLICE, Clip.BH_VOLLEY, Clip.BH2_DRIVE:
			a = Vector2(-0.20, 0.28)
			b = Vector2(0.02, -0.40)
		_:
			a = Vector2(-0.09, -0.21)
			b = Vector2(0.19, 0.23)
	if hand > 0:
		return [a, b]
	return [Vector2(-b.x, b.y), Vector2(-a.x, a.y)]


func _sample_clip(t: float) -> Pose:
	var n := clip_keys.size()
	if n == 0:
		return _ready_pose(0.0)
	if t <= float(clip_keys[0]["t"]):
		return _key_pose(clip_keys[0], clip_id)
	if t >= float(clip_keys[n - 1]["t"]):
		return _key_pose(clip_keys[n - 1], clip_id)
	var i := 0
	while i < n - 2 and t > float(clip_keys[i + 1]["t"]):
		i += 1
	var t0: float = clip_keys[i]["t"]
	var t1: float = clip_keys[i + 1]["t"]
	var u := (t - t0) / (t1 - t0)
	var p1 := _key_pose(clip_keys[i], clip_id)
	var p2 := _key_pose(clip_keys[i + 1], clip_id)
	var p0 := _key_pose(clip_keys[maxi(i - 1, 0)], clip_id)
	var p3 := _key_pose(clip_keys[mini(i + 2, n - 1)], clip_id)
	var out := p1.blend(p2, u)
	# مسار القبضة منحنى Catmull-Rom لحركة قوسية طبيعية
	out.grip = _catmull(p0.grip, p1.grip, p2.grip, p3.grip, u)
	out.lhand = _catmull(p0.lhand, p1.lhand, p2.lhand, p3.lhand, u)
	# سلسلة الحركة: الورك يسبق الكتفين بنحو 50 ملّي ثانية (فصل الورك عن الكتفين)
	out.hip = _hip_at(t + 0.05)
	return out


func _catmull(a: Vector3, b: Vector3, c: Vector3, d: Vector3, u: float) -> Vector3:
	var u2 := u * u
	var u3 := u2 * u
	return 0.5 * ((2.0 * b) + (-a + c) * u + (2.0 * a - 5.0 * b + 4.0 * c - d) * u2 + (-a + 3.0 * b - 3.0 * c + d) * u3)


# =====================================================================
#  الجذع: يحسب إطارات الحوض والبطن والصدر بنفس سلسلة الهيكل العظمي
# =====================================================================
func _torso(p: Pose, extra_y: float = 0.0, lf_add: float = 0.0, ls_add: float = 0.0) -> Dictionary:
	var lf := deg_to_rad(p.lf + lf_add)
	var ls := deg_to_rad(p.ls + ls_add)
	var yaw_h := -deg_to_rad(p.hip) * hand
	var yaw_c := -deg_to_rad(p.turn) * hand
	var lean := Basis(Vector3.RIGHT, -lf) * Basis(Vector3.BACK, -ls)
	var bp := Basis(Vector3.RIGHT, -lf * 0.35) * Basis(Vector3.BACK, -ls * 0.3) * Basis(Vector3.UP, yaw_h)
	var bc := lean * Basis(Vector3.UP, yaw_c)
	var ba := Basis(bp.get_rotation_quaternion().slerp(bc.get_rotation_quaternion(), 0.5))
	var hip_y := STAND_HIP - 0.22 * p.cr + p.jp + extra_y
	var pp := Vector3(p.sway.x, hip_y, p.sway.z)
	var ps := pp + bp * (_o("Spine") - _o("Hips"))
	var pc := ps + ba * (_o("Chest") - _o("Spine"))
	return {"bp": bp, "ba": ba, "bc": bc, "pp": pp, "ps": ps, "pc": pc, "yaw_h": yaw_h}


func _chest_frame(p: Pose) -> Transform3D:
	var t := _torso(p)
	return Transform3D(t["bc"], t["pc"] + (t["bc"] as Basis) * Vector3(0, 0.0, 0))


## وضعية حمل المضرب المسترخية (بين النقاط): المضرب متدلٍّ بجانب الجسم والذراعان تتأرجحان مع المشي
func _carry_into(p: Pose, cf: Transform3D, swing: float, amt: float) -> void:
	var sw := swing * amt
	p.grip = cf * Vector3(0.27 * hand, -0.50 + 0.02 * absf(sw), -0.02 - 0.17 * sw * hand)
	p.axis = (cf.basis * Vector3(0.06 * hand, -0.30, -0.95)).normalized()
	p.nrm = (cf.basis * Vector3(hand, 0.05, 0)).normalized()
	p.lhand = cf * Vector3(-0.27 * hand, -0.53 + 0.02 * absf(sw), 0.0 + 0.19 * sw * hand)
	p.offgrip = 0.0
	p.off_curl = 0.32
	p.pole = Vector3(0.35 * hand, -0.3, 0.9)
	p.off_pole = Vector3(-0.35 * hand, -0.3, 0.9)


func _ready_pose(dt: float) -> Pose:
	var p := Pose.new()
	var v := Vector2(move_vel.x, move_vel.z)
	var speed := v.length()
	var run := smoothstep(2.6, 5.2, speed)
	var relax := (1.0 - smoothstep(0.25, 0.7, alert)) * (1.0 - run)
	var want_turn := 0.0
	if speed > 2.6:
		want_turn = clampf(rad_to_deg(atan2(v.x, -v.y)), -115.0, 115.0) * run
	elif relax > 0.5 and speed > 0.5:
		# المشي المسترخي: الجسم يتجه نحو وجهة السير
		want_turn = clampf(rad_to_deg(atan2(v.x, -v.y)), -80.0, 80.0) * smoothstep(0.5, 1.2, speed)
	_run_turn = move_toward(_run_turn, want_turn, (420.0 if run > 0.0 else 240.0) * dt)
	p.turn = _run_turn * hand
	p.hip = _run_turn * hand * 0.85
	var tired := fatigue * (1.0 - alert * 0.6)
	var idle := (1.0 - smoothstep(0.2, 0.9, speed))
	p.cr = lerpf(lerpf(0.16, 0.42, alert), 0.26, run) + 0.06 * tired
	p.lf = lerpf(lerpf(3.0, 11.0, alert), 13.0, run) + 6.0 * tired
	p.ls = 0.0
	p.stance = 0.0
	# تأرجح المستقبِل المتأهب: نقل الوزن بين القدمين
	var sway_t := sin(_time * 2.3)
	p.sway = Vector3(0.035 * sway_t * alert * idle, 0, 0)
	p.cr += 0.03 * absf(sway_t) * alert * idle
	var cf := _chest_frame(p)
	var swing := _stride_sig * smoothstep(0.3, 1.2, speed)
	var g_ready := Vector3(0.12 * hand, -0.07, -0.40)
	var g_run := Vector3(0.24 * hand, -0.20 + 0.07 * swing * hand, -0.14 - 0.26 * swing * hand)
	p.grip = cf * g_ready.lerp(g_run, run)
	var ax_ready := Vector3(-0.38 * hand, 0.50, -0.78)
	var ax_run := Vector3(-0.10 * hand, 0.55, -0.83)
	p.axis = (cf.basis * ax_ready.lerp(ax_run, run)).normalized()
	p.nrm = (cf.basis * Vector3(hand, 0.1, 0)).normalized()
	var throat := p.grip + p.axis * 0.24
	var l_run := cf * Vector3(-0.22 * hand, -0.16 - 0.10 * swing * hand, -0.12 + 0.30 * swing * hand)
	p.lhand = throat.lerp(l_run, run)
	p.offgrip = 1.0 - run
	p.off_ps = -1.0
	p.off_curl = lerpf(0.55, 0.85, run)
	p.pole = Vector3(0.4 * hand, -0.8, 0.45)
	p.off_pole = Vector3(-0.4 * hand, -0.8, 0.5)
	var w := lerpf(0.17, 0.30, alert)
	p.foot_l = Vector2(-w, 0.02)
	p.foot_r = Vector2(w, 0.02)
	if relax > 0.01:
		var q := Pose.new()
		q.turn = p.turn
		q.hip = p.hip
		q.cr = 0.07 + 0.05 * tired
		q.lf = 2.5 + 7.0 * tired
		q.foot_l = Vector2(-0.14, 0.02)
		q.foot_r = Vector2(0.14, 0.02)
		q.look_w = 0.45
		q.head_pitch = 6.0 + 10.0 * tired
		_carry_into(q, _chest_frame(q), swing, 1.0)
		p = p.blend(q, relax)
	return p


func _react_pose(t: float) -> Pose:
	var p := Pose.new()
	p.stance = 0.0
	p.foot_l = Vector2(-0.16, 0.02)
	p.foot_r = Vector2(0.16, 0.02)
	p.pole = Vector3(0.4 * hand, -0.8, 0.45)
	p.off_pole = Vector3(-0.4 * hand, -0.8, 0.5)
	match react_id:
		React.FIST:
			# قبضة انتصار: انحناء خفيف للأمام ورفع اليد الحرة بقوة
			var pump := 0.5 + 0.5 * sin(minf(t, 1.2) * 10.0)
			p.cr = 0.42
			p.lf = 14.0
			p.turn = 10.0
			var cf := _chest_frame(p)
			p.grip = cf * Vector3(0.24 * hand, -0.36, -0.10)
			p.axis = (cf.basis * Vector3(0.15 * hand, -0.35, -0.9)).normalized()
			p.nrm = (cf.basis * Vector3(hand, 0, 0)).normalized()
			p.lhand = cf * Vector3(-0.22 * hand, 0.02 + 0.12 * pump, -0.26)
			p.off_pole = Vector3(-0.3 * hand, -0.9, 0.2)
			p.off_curl = 1.0
			p.head_pitch = -8.0
		React.ARMS_UP:
			p.cr = 0.05
			p.lf = -6.0
			p.jp = 0.06 * maxf(sin(t * 7.0), 0.0) * (1.0 if t < 2.0 else 0.0)
			var cf2 := _chest_frame(p)
			p.grip = cf2 * Vector3(0.30 * hand, 0.62, -0.08)
			p.axis = Vector3(0.1 * hand, 1.0, 0.1).normalized()
			p.nrm = Vector3(0, 0, -1)
			p.lhand = cf2 * Vector3(-0.30 * hand, 0.62, -0.06)
			p.pole = Vector3(0.9 * hand, -0.2, 0.4)
			p.off_pole = Vector3(-0.9 * hand, -0.2, 0.4)
			p.off_curl = 1.0
			p.head_pitch = -18.0
		React.DEJECT:
			# رأس منخفض وكتفان متدليان والمضرب يتدلى
			p.cr = 0.10
			p.lf = 16.0
			var cf3 := _chest_frame(p)
			p.grip = cf3 * Vector3(0.24 * hand, -0.52, 0.02)
			p.axis = (cf3.basis * Vector3(0.05 * hand, -0.9, -0.3)).normalized()
			p.nrm = (cf3.basis * Vector3(hand, 0, 0)).normalized()
			p.lhand = cf3 * Vector3(-0.20 * hand, -0.38, 0.06)
			p.off_curl = 0.35
			p.head_pitch = 30.0
		React.HANDS_HIPS:
			p.cr = 0.08
			p.lf = 4.0
			var cf4 := _chest_frame(p)
			var hips_l := Vector3(-0.17 * hand, -0.24, 0.02)
			p.grip = cf4 * Vector3(0.20 * hand, -0.26, -0.02)
			p.axis = (cf4.basis * Vector3(0.6 * hand, -0.7, 0.2)).normalized()
			p.nrm = (cf4.basis * Vector3(0, 0, -1)).normalized()
			p.lhand = cf4 * hips_l
			p.pole = Vector3(0.9 * hand, -0.1, 0.3)
			p.off_pole = Vector3(-0.9 * hand, -0.1, 0.3)
			p.off_curl = 0.4
			p.head_pitch = 12.0 + 6.0 * sin(t * 1.3)
		React.BOUNCE:
			# روتين ما قبل الإرسال: نطّ الكرة بالأرض
			var cyc := fmod(t, 0.62) / 0.62
			var push := sin(cyc * TAU) * 0.5 + 0.5
			p.cr = 0.22 + 0.08 * push
			p.lf = 14.0
			p.turn = 50.0
			p.hip = 45.0
			var cf5 := _chest_frame(p)
			p.grip = cf5 * Vector3(0.20 * hand, -0.20, -0.22)
			p.axis = (cf5.basis * Vector3(-0.3 * hand, 0.3, -0.9)).normalized()
			p.nrm = (cf5.basis * Vector3(hand, 0, 0)).normalized()
			p.lhand = cf5 * Vector3(-0.06 * hand, -0.32 - 0.10 * push, -0.42)
			p.off_curl = 0.2
			p.off_pole = Vector3(-0.6 * hand, -0.7, 0.4)
			p.head_pitch = 32.0
			var fs := _stance_feet(Clip.OVERHEAD)
			p.foot_l = fs[0]
			p.foot_r = fs[1]
			p.stance = 1.0
		React.STRINGS:
			# تسوية الأوتار: المضرب أمام الصدر والنظر إليه
			p.cr = 0.08
			p.lf = 5.0
			var cf6 := _chest_frame(p)
			p.grip = cf6 * Vector3(0.17 * hand, -0.30, -0.24)
			p.axis = (cf6.basis * Vector3(-0.55 * hand, 0.25, -0.80)).normalized()
			p.nrm = (cf6.basis * Vector3(0.1 * hand, 0.9, 0.42)).normalized()
			p.lhand = p.grip + p.axis * (HEAD_DIST - 0.03 + 0.045 * sin(t * 5.0)) + p.nrm * 0.035 + cf6.basis * Vector3(0.03 * sin(t * 3.1) * hand, 0, 0)
			p.off_pole = Vector3(-0.7 * hand, -0.6, 0.4)
			p.off_curl = 0.4
			p.head_pitch = 36.0
			p.look_w = 0.0
		React.WIPE:
			# مسح العرق عن الجبين بسوار المعصم
			p.cr = 0.08
			p.lf = 4.0
			var cf7 := _chest_frame(p)
			var wv := sin(minf(t, 1.3) / 1.3 * PI)
			p.grip = cf7 * Vector3((0.16 - 0.10 * wv) * hand, 0.33, -0.19)
			p.axis = (cf7.basis * Vector3(0.80 * hand, 0.55, -0.15)).normalized()
			p.nrm = (cf7.basis * Vector3(0, 0.2, -1)).normalized()
			p.pole = Vector3(0.9 * hand, 0.25, -0.3)
			p.lhand = cf7 * Vector3(-0.27 * hand, -0.52, 0.02)
			p.off_pole = Vector3(-0.35 * hand, -0.3, 0.9)
			p.off_curl = 0.3
			p.head_pitch = 14.0
			p.look_w = 0.0
	p.offgrip = 0.0
	if react_id == React.DEJECT or react_id == React.HANDS_HIPS or react_id == React.BOUNCE:
		p.look_w = 0.0
	elif react_id == React.FIST or react_id == React.ARMS_UP:
		p.look_w = 0.25
	# الحركات القصيرة تنتهي بوضعية الحمل المسترخية
	var endt := {React.FIST: 1.5, React.STRINGS: 3.2, React.WIPE: 1.35}
	if endt.has(react_id) and t > float(endt[react_id]):
		var q := Pose.new()
		q.cr = 0.07
		q.lf = 2.5
		q.foot_l = p.foot_l
		q.foot_r = p.foot_r
		q.look_w = 0.45
		q.head_pitch = 6.0
		_carry_into(q, _chest_frame(q), _stride_sig * smoothstep(0.3, 1.2, Vector2(move_vel.x, move_vel.z).length()), 1.0)
		p = p.blend(q, smoothstep(0.0, 0.45, t - float(endt[react_id])))
	return p


func _serve_stance_pose() -> Pose:
	var p := Pose.new()
	p.turn = 75.0
	p.hip = 72.0
	p.cr = 0.14
	p.lf = 3.0
	p.grip = _mir(Vector3(0.10, 1.04, -0.28))
	p.axis = _mir(Vector3(-0.2, 0.4, -0.9)).normalized()
	p.nrm = _mir(Vector3(0.9, 0.2, -0.2)).normalized()
	p.lhand = _mir(Vector3(-0.04, 1.08, -0.40))
	p.offgrip = 0.0
	p.off_curl = 0.45
	p.stance = 1.0
	var fs := _stance_feet(Clip.OVERHEAD)
	p.foot_l = fs[0]
	p.foot_r = fs[1]
	return p


func _serve_toss_pose(t: float) -> Pose:
	var up := Vector3(0.9, -0.15, 0.5)
	var keys := [
		_k(0.0, Vector3(0.10, 1.04, -0.28), Vector3(-0.2, 0.4, -0.9), Vector3(0.9, 0.2, -0.2), 75, 72, 0.14, Vector3(-0.04, 1.08, -0.40), {"lf": 3.0}),
		_k(0.25, Vector3(0.30, 0.82, 0.10), Vector3(0.1, -0.6, -0.8), Vector3(0.9, 0.1, -0.3), 78, 72, 0.22, Vector3(-0.04, 0.98, -0.42), {"lf": 5.0}),
		_k(0.45, Vector3(0.50, 0.98, 0.38), Vector3(0.3, -0.2, 0.93), Vector3(0.9, 0.0, -0.4), 85, 72, 0.28, Vector3(-0.02, 1.95, -0.44), {"lf": 0.0, "pole": up}),
		_k(0.80, Vector3(0.42, 1.60, 0.26), Vector3(-0.10, 0.97, 0.05), Vector3(0.9, 0.1, -0.4), 95, 70, 0.66, Vector3(-0.02, 2.08, -0.40), {"lf": -10.0, "pole": up, "sw": Vector3(0, 0, -0.06)}),
	]
	var saved := clip_keys
	var saved_id := clip_id
	var saved_contact := contact
	clip_keys = keys
	clip_id = Clip.OVERHEAD
	contact = Vector3(0.20 * hand, 2.70, -0.42)
	var p := _sample_clip(t)
	clip_keys = saved
	clip_id = saved_id
	contact = saved_contact
	p.off_curl = 0.3 if t < 0.45 else 0.1
	return p


# =====================================================================
#  التحديث كل إطار
# =====================================================================
func _process(dt: float) -> void:
	_time += dt
	var speed := Vector2(move_vel.x, move_vel.z).length()
	if speed > 0.2:
		var step_len := 0.30 + 0.135 * speed
		_gait = fposmod(_gait + dt * speed / (2.0 * step_len), 1.0)
	if _split_t >= 0.0:
		_split_t += dt
		if _split_t > 0.42:
			_split_t = -1.0
	balance = balance.move_toward(Vector2.ZERO, dt * 1.6)
	if dt > 0.0:
		_acc = _acc.lerp((move_vel - _prev_vel) / dt, clampf(dt * 10.0, 0.0, 1.0))
		_prev_vel = move_vel
		var spd := move_vel.length()
		var dec := -_acc.dot(move_vel / spd) if spd > 0.5 else 0.0
		_brake = move_toward(_brake, clampf((dec - 4.0) / 6.0, 0.0, 1.0), dt * 4.0)
	_sweat_t -= dt
	if _sweat_t <= 0.0 and _skin_mat != null:
		_sweat_t = 0.5
		_sweat = maxf(_sweat * 0.995, fatigue)
		_skin_mat.set_shader_parameter("sweat", clampf(_sweat * 1.3, 0.0, 1.0))
		_skin_mat.set_shader_parameter("flush", clampf(_sweat, 0.0, 1.0))
	# القماش: يرفرف مع السرعة ويتأخر عن الجسم عند التسارع
	var fl := clampf(0.18 + speed / 6.0 + _acc.length() / 30.0, 0.0, 1.5)
	var sw := (-_acc * 0.0022).limit_length(0.028)
	for cm in _cloth_mats:
		if cm != null:
			(cm as ShaderMaterial).set_shader_parameter("flutter", fl)
			(cm as ShaderMaterial).set_shader_parameter("sway", sw)

	var target: Pose
	match mode:
		Mode.READY:
			target = _ready_pose(dt)
		Mode.PREP:
			prep_w = minf(prep_w + dt / 0.22, 1.0)
			target = _key_pose(clip_keys[0], clip_id)
		Mode.SWING:
			clip_t += dt
			target = _sample_clip(clip_t)
			if clip_t > float(clip_keys[clip_keys.size() - 1]["t"]) + 0.02:
				set_ready(0.28)
		Mode.SERVE_STANCE:
			target = _serve_stance_pose()
		Mode.SERVE_TOSS:
			serve_t += dt
			target = _serve_toss_pose(serve_t)
		Mode.SERVE_SWING:
			clip_t += dt
			target = _sample_clip(clip_t)
			if clip_t > 0.36:
				set_ready(0.35)
		Mode.REACT:
			react_t += dt
			target = _react_pose(react_t)
		_:
			target = _ready_pose(dt)

	if _blend_t < 1.0 and _blend_from != null:
		_blend_t = minf(_blend_t + dt / _blend_dur, 1.0)
		var w := _blend_t * _blend_t * (3.0 - 2.0 * _blend_t)
		target = _blend_from.blend(target, w)
	_last = target
	_apply(target, dt)


# ---------------------------------------------------------------------
func _frame(y: Vector3, hint: Vector3) -> Basis:
	y = y.normalized()
	var z := hint - y * hint.dot(y)
	if z.length_squared() < 0.000001:
		z = Vector3.BACK - y * Vector3.BACK.dot(y)
		if z.length_squared() < 0.000001:
			z = Vector3.RIGHT
	z = z.normalized()
	return Basis(y.cross(z), y, z)


## حل IK لعظمتين. يعيد موضع المفصل الأوسط.
func _ik(a: Vector3, t: Vector3, l1: float, l2: float, pole: Vector3) -> Vector3:
	var d := t - a
	var dist := clampf(d.length(), absf(l1 - l2) + 0.01, l1 + l2 - 0.002)
	var dir := d.normalized() if d.length_squared() > 0.000001 else Vector3.DOWN
	var along := (l1 * l1 - l2 * l2 + dist * dist) / (2.0 * dist)
	var h := sqrt(maxf(l1 * l1 - along * along, 0.0))
	var pp := pole - dir * pole.dot(dir)
	if pp.length_squared() < 0.0001:
		pp = Vector3.BACK - dir * Vector3.BACK.dot(dir)
	return a + dir * along + pp.normalized() * h


## إطار اليد من المضرب: axis محور المقبض، palm اتجاه باطن الكف، hs = 1 لليد اليمنى و-1 لليسرى
func _hand_frame(axis: Vector3, palm: Vector3, hs: float) -> Basis:
	axis = axis.normalized()
	var P := palm - axis * palm.dot(axis)
	if P.length_squared() < 0.0001:
		P = Vector3.FORWARD - axis * Vector3.FORWARD.dot(axis)
	P = P.normalized()
	var D := P.cross(axis) * hs
	var y := (D * cos(GRIP_BETA) + axis * sin(GRIP_BETA)).normalized()
	return _frame(y, -P)


func _set_g(n: String, xf: Transform3D) -> void:
	_g[n] = xf
	var par: String = _parent[n]
	var local: Transform3D = xf if par == "" else (_g[par] as Transform3D).affine_inverse() * xf
	var i: int = _bi[n]
	skel.set_bone_pose_position(i, local.origin)
	skel.set_bone_pose_rotation(i, local.basis.orthonormalized().get_rotation_quaternion())


## تحويل عالمي لعظمة من إطار جزء الجسم (هوية = منتصب ينظر للأمام)
func _part(n: String, b: Basis, origin: Vector3) -> Transform3D:
	return Transform3D(b * (_rest[n] as Transform3D).basis, origin)


## انقباض الأصابع: grip 0 مسترخية، 1 قبضة على المقبض
func _curl(side: String, amount: float, thumb_amount: float = -1.0) -> void:
	var key := snappedf(amount, 0.02) * 10.0 + snappedf(maxf(thumb_amount, 0.0), 0.02)
	if _curl_cache.get(side, -1.0) == key:
		return
	_curl_cache[side] = key
	var ta := amount if thumb_amount < 0.0 else thumb_amount
	var angs := [deg_to_rad(62.0), deg_to_rad(78.0), deg_to_rad(52.0)]
	for f in FINGERS:
		for k in 3:
			var n := "%s%d.%s" % [f, k + 1, side]
			if not _bi.has(n):
				continue
			var a: float = angs[k] * (ta if f == "Thumb" else amount)
			var axis := Vector3.RIGHT
			if f == "Thumb":
				a *= 0.8 if k > 0 else 0.5
				axis = Vector3(0.45, 0, 1).normalized() if k == 0 else Vector3(1, 0, 0.3).normalized()
			var r: Transform3D = _rest_local[n]
			skel.set_bone_pose_rotation(_bi[n], (r.basis.get_rotation_quaternion() * Quaternion(axis, -a)).normalized())


func _arm(s: String, chest: Transform3D, bc: Basis, wrist_target: Vector3, hand_b: Basis, pole: Vector3, use_hand_b: bool) -> Vector3:
	# الترقوة: ترتفع وتتقدم عندما ترتفع الذراع
	var cl_rest: Transform3D = _rest["Clavicle." + s]
	var cl_o := chest.origin + bc * (cl_rest.origin - _o("Chest"))
	var sh_rest := _o("UpperArm." + s)
	var sh0 := cl_o + bc * (sh_rest - cl_rest.origin)
	var reach := (wrist_target - sh0)
	var up_amt := clampf(reach.normalized().dot(bc.y) * 1.25, 0.0, 1.0) if reach.length() > 0.01 else 0.0
	var fwd_amt := clampf(reach.normalized().dot(-bc.z), 0.0, 1.0) if reach.length() > 0.01 else 0.0
	var sgn := -1.0 if s == "L" else 1.0
	var elev := Basis(bc.z, deg_to_rad(16.0) * up_amt * sgn) * Basis(bc.y, deg_to_rad(10.0) * fwd_amt * sgn)
	var cb := elev * bc
	_set_g("Clavicle." + s, _part("Clavicle." + s, cb, cl_o))
	var sh := cl_o + cb * (sh_rest - cl_rest.origin)
	# IK
	var wt := wrist_target
	var max_r := UPPER_ARM + FOREARM - 0.004
	if (wt - sh).length() > max_r:
		wt = sh + (wt - sh).normalized() * max_r
	var el := _ik(sh, wt, UPPER_ARM, FOREARM, pole)
	var line := (wt - sh).normalized()
	var off := (el - sh) - line * (el - sh).dot(line)
	var ep := off if off.length() > 0.01 else pole
	var y_ua := (el - sh).normalized()
	var b_ua := _frame(y_ua, ep)
	_set_g("UpperArm." + s, Transform3D(b_ua, sh))
	var l_ua1 := _o("UpperArmTwist." + s).distance_to(sh_rest)
	_set_g("UpperArmTwist." + s, Transform3D(b_ua, sh + y_ua * l_ua1))
	var y_fa := (wt - el).normalized()
	var b_fa := _frame(y_fa, ep)
	_set_g("ForeArm." + s, Transform3D(b_fa, el))
	var hb: Basis = hand_b if use_hand_b else b_fa * (_fa_hand_rel[s] as Basis)
	# توزيع التفاف الساعد (كب/بسط) على عظمة الالتواء
	var rel := b_fa.inverse() * hb
	var rel0: Basis = _fa_hand_rel[s]
	var dq := (rel * rel0.inverse()).get_rotation_quaternion()
	var tw := 2.0 * atan2(dq.y, dq.w)
	if tw > PI:
		tw -= TAU
	elif tw < -PI:
		tw += TAU
	var l_fa1 := _o("ForeArmTwist." + s).distance_to(_o("ForeArm." + s))
	_set_g("ForeArmTwist." + s, Transform3D(b_fa * Basis(Vector3.UP, tw * 0.5), el + y_fa * l_fa1))
	_set_g("Hand." + s, Transform3D(hb, wt))
	return wt


## تنعيم بنابض حرج التخميد (حركة ذات قصور طبيعي بلا ارتداد)
func _damp(cur: float, target: float, vel: float, smooth: float, max_speed: float, dt: float) -> Vector2:
	if dt <= 0.0:
		return Vector2(target, 0.0)
	var om := 2.0 / maxf(smooth, 0.0001)
	var x := om * dt
	var ex := 1.0 / (1.0 + x + 0.48 * x * x + 0.235 * x * x * x)
	var change := clampf(cur - target, -max_speed * smooth, max_speed * smooth)
	var tgt := cur - change
	var tmp := (vel + om * change) * dt
	var nv := (vel - om * tmp) * ex
	var out := tgt + (change + tmp) * ex
	if (target - cur > 0.0) == (out > target):
		out = target
		nv = 0.0
	return Vector2(out, nv)


## مواضع القدمين التحليلية (للوحات الوضعيات الثابتة فقط)
func _feet_static(p: Pose, yaw_h: float, speed: float, gait_w: float, run: float) -> Array:
	var v2 := Vector2(move_vel.x, move_vel.z)
	var dir2 := v2 / speed if speed > 0.01 else Vector2.ZERO
	var step_len := 0.30 + 0.135 * speed
	var duty := lerpf(0.62, 0.36, clampf(speed / 7.5, 0.0, 1.0))
	var stride := 2.0 * step_len * duty
	var lift_h := 0.05 + 0.032 * speed
	var stance_feet := [p.foot_l, p.foot_r]
	var out := []
	for i in 2:
		var sgn := -1.0 if i == 0 else 1.0
		var sf: Vector2 = stance_feet[i]
		var stand := Vector3(sf.x + p.sway.x * 0.5, ANKLE_H, sf.y + p.sway.z * 0.5)
		var c := fposmod(_gait + 0.5 * i, 1.0)
		var along := 0.0
		var lift := 0.0
		var pitch := 0.0
		if c < duty:
			along = stride * (0.5 - c / duty)
			var toe := smoothstep(0.6, 1.0, c / duty) * gait_w
			pitch = -0.55 * toe
			lift = 0.07 * toe
		else:
			var sw := (c - duty) / (1.0 - duty)
			var e := sw * sw * (3.0 - 2.0 * sw)
			along = stride * (-0.5 + e)
			lift = lift_h * sin(PI * sw) + 0.10 * run * sin(PI * minf(sw * 1.6, 1.0))
			pitch = -0.9 * sin(PI * minf(sw * 1.4, 1.0)) * gait_w * clampf(speed / 5.0, 0.3, 1.0)
		var base := Vector2(0.11 * sgn, 0.0).rotated(-yaw_h)
		var run_t := Vector3(base.x + dir2.x * along, ANKLE_H + lift, base.y + dir2.y * along)
		var tgt := stand.lerp(run_t, gait_w)
		out.append({"pos": tgt, "yaw": yaw_h * 0.7 + 0.10 * sgn * (1.0 - gait_w), "pitch": pitch})
	return out


## نظام الخطوات: كل قدم تبقى مثبّتة في مكانها على الأرض (بإحداثيات العالم) حتى تبتعد عن موضعها المطلوب
## فتخطو خطوة حقيقية نحوه. لا انزلاق للقدمين، وخطوات تعديل صغيرة تلقائية عند التوقف وتغيير الوقفة.
func _feet_step(p: Pose, dt: float, yaw_h: float, speed: float, gait_w: float, run: float, hop: float) -> Array:
	var xf := global_transform
	var inv := xf.affine_inverse()
	var root_yaw := xf.basis.get_euler().y
	var v2 := Vector2(move_vel.x, move_vel.z)
	var dir := v2 / speed if speed > 0.05 else Vector2.ZERO
	var step_len := 0.30 + 0.135 * speed
	var duty := lerpf(0.62, 0.36, clampf(speed / 7.5, 0.0, 1.0))
	var cyc := 2.0 * step_len / maxf(speed, 0.5)
	var t_sw := clampf((1.0 - duty) * cyc, 0.15, 0.25)
	var need := minf(1.0, 0.5 / (1.0 - duty)) - 0.03
	# الحركة الجانبية بالنسبة للحوض: خطوات جانبية (شَفل) لا تتقاطع فيها القدمان
	var dh := dir.rotated(yaw_h)
	var lat := dh.x * dh.x
	var half := lerpf(0.07, step_len * duty, smoothstep(0.5, 2.2, speed))
	var w_run := lerpf(0.11, 0.22, lat)
	half = lerpf(half, minf(half, w_run - 0.05), lat)
	var moving := speed > 0.45
	var airborne := p.jp > 0.03 or hop > 0.012
	var stance_feet := [p.foot_l, p.foot_r]
	var homes := [Vector2.ZERO, Vector2.ZERO]
	var locs := [Vector2.ZERO, Vector2.ZERO]
	var reset := not _feet_init
	for i in 2:
		var sgn := -1.0 if i == 0 else 1.0
		var sf: Vector2 = stance_feet[i]
		var stand := Vector2(sf.x + p.sway.x * 0.5, sf.y + p.sway.z * 0.5)
		var base := Vector2(w_run * sgn, 0.0).rotated(-yaw_h)
		homes[i] = stand.lerp(base, gait_w)
		var l3: Vector3 = inv * (_fw[i] as Vector3)
		locs[i] = Vector2(l3.x, l3.z)
		if ((locs[i] as Vector2) - (homes[i] as Vector2)).length() > 1.8:
			reset = true      # انتقال فجائي (تبديل الملعب مثلاً)
	if reset:
		for i in 2:
			var h: Vector2 = homes[i]
			_fw[i] = xf * Vector3(h.x, 0.0, h.y)
			_fyaw[i] = root_yaw + yaw_h * 0.7
			_fs[i] = 1.0
			_plant_t[i] = 1.0
			locs[i] = h
		_feet_init = true
	for i in 2:
		_plant_t[i] = (float(_plant_t[i]) + dt) if float(_fs[i]) >= 1.0 else 0.0

	# --- قرار بدء الخطوة ---
	if not airborne:
		var standing: bool = float(_plant_t[0]) > 0.10 and float(_plant_t[1]) > 0.10
		var lead_i := -1
		if moving and standing:
			var dd := ((homes[0] as Vector2) - (homes[1] as Vector2)).dot(dir)
			lead_i = 0 if dd > 0.02 else (1 if dd < -0.02 else 1 - _last_step)
		for i in 2:
			if float(_fs[i]) < 1.0:
				continue
			var o := 1 - i
			var e: Vector2 = (locs[i] as Vector2) - (homes[i] as Vector2)
			var go := false
			var quick := false
			if moving:
				var thr := half
				if i == lead_i:
					thr = 0.03          # أول خطوة من الوقوف: القدم القائدة تنطلق فوراً
				go = -e.dot(dir) > thr
				var perp := e - dir * e.dot(dir)
				if perp.length() > 0.2:
					go = true
			else:
				var ly := angle_difference(root_yaw + yaw_h * 0.7, float(_fyaw[i]))
				go = e.length() > 0.085 or absf(ly) > 0.7
				quick = true
			var force := e.length() > 0.6
			if (go and float(_fs[o]) >= need) or (force and float(_fs[o]) >= 0.5) or e.length() > 0.85:
				_fs[i] = 0.0
				_ffrom[i] = _fw[i]
				_fyaw_from[i] = _fyaw[i]
				var dist := e.length()
				_fdur[i] = clampf(0.13 + dist * 0.22, 0.15, 0.24) if quick else t_sw
				_flift[i] = (0.03 + dist * 0.10) if quick else (0.045 + 0.03 * speed)
				_last_step = i

	# --- تحديث القدمين ---
	var out := []
	var lifts := [0.0, 0.0]
	for i in 2:
		var sgn := -1.0 if i == 0 else 1.0
		var home: Vector2 = homes[i]
		var yaw_t := root_yaw + yaw_h * 0.7 + 0.10 * sgn * (1.0 - gait_w)
		var pos := Vector3.ZERO
		var pitch := 0.0
		if airborne:
			var l: Vector2 = (locs[i] as Vector2).lerp(home, clampf(dt * 12.0, 0.0, 1.0))
			locs[i] = l
			_fw[i] = xf * Vector3(l.x, 0.0, l.y)
			_fs[i] = 1.0
			_fyaw[i] = lerp_angle(float(_fyaw[i]), yaw_t, clampf(dt * 10.0, 0.0, 1.0))
			pos = Vector3(l.x, ANKLE_H, l.y)
			pitch = -0.6 * clampf(maxf(p.jp, hop * 3.0) / 0.1, 0.0, 1.0)
		elif float(_fs[i]) < 1.0:
			_fs[i] = minf(float(_fs[i]) + dt / float(_fdur[i]), 1.0)
			var u: float = _fs[i]
			var e := u * u * (3.0 - 2.0 * u)
			var land := home + (dir * half if moving else Vector2.ZERO)
			var tw := xf * Vector3(land.x, 0.0, land.y)
			var w3 := (_ffrom[i] as Vector3).lerp(tw, e)
			_fyaw[i] = lerp_angle(float(_fyaw_from[i]), yaw_t, e)
			var lift := float(_flift[i]) * sin(PI * u) + 0.10 * run * sin(PI * minf(u * 1.6, 1.0))
			lifts[i] = sin(PI * u)
			pitch = -0.9 * sin(PI * minf(u * 1.4, 1.0)) * clampf(speed / 5.0, 0.22, 1.0)
			pitch += 0.28 * smoothstep(0.7, 1.0, u) * (1.0 - run) * clampf(speed / 1.5, 0.0, 1.0)   # الهبوط على الكعب عند المشي
			if u >= 1.0:
				w3 = tw
				lift = 0.0
			_fw[i] = w3
			var l3c: Vector3 = inv * w3
			locs[i] = Vector2(l3c.x, l3c.z)
			pos = Vector3(l3c.x, ANKLE_H + lift, l3c.z)
		else:
			var l2: Vector2 = locs[i]
			var lift2 := 0.0
			if moving:
				# رفع الكعب قبل إقلاع القدم
				var toe := smoothstep(0.45, 1.0, -(l2 - home).dot(dir) / maxf(half, 0.05)) * gait_w
				pitch = -0.6 * toe
				lift2 = 0.08 * toe
			# دوران الحوض بعيداً عن اتجاه القدم: تدور القدم على مشطها ويرتفع الكعب
			var ly2 := angle_difference(root_yaw + yaw_h, float(_fyaw[i]))
			if absf(ly2) > 0.75:
				var over := absf(ly2) - 0.75
				_fyaw[i] = float(_fyaw[i]) - signf(ly2) * over
				pitch = minf(pitch, -0.45 * clampf(over * 30.0, 0.0, 1.0))
				lift2 = maxf(lift2, 0.05 * clampf(over * 30.0, 0.0, 1.0))
			pos = Vector3(l2.x, ANKLE_H + lift2, l2.y)
		out.append({"pos": pos, "yaw": angle_difference(root_yaw, float(_fyaw[i])), "pitch": pitch})
	# إشارة الخطوة (لتأرجح الذراعين ودوران الحوض) وانتقال الوزن
	var sig := 0.0
	if moving:
		sig = clampf((((locs[0] as Vector2) - (homes[0] as Vector2)) - ((locs[1] as Vector2) - (homes[1] as Vector2))).dot(dir) / maxf(2.0 * half, 0.12), -1.0, 1.0)
	_stride_sig = lerpf(_stride_sig, sig, clampf(dt * 16.0, 0.0, 1.0))
	_lat_shift = lerpf(_lat_shift, 0.03 * (float(lifts[0]) - float(lifts[1])) * (1.0 - 0.6 * run), clampf(dt * 12.0, 0.0, 1.0))
	return out


func _apply(p: Pose, dt: float) -> void:
	if skel == null:
		return
	var speed := Vector2(move_vel.x, move_vel.z).length()
	var gait_w := smoothstep(0.25, 1.3, speed) * (1.0 - 0.75 * p.stance * (1.0 - smoothstep(2.5, 5.0, speed)))
	var run := smoothstep(2.6, 5.2, speed)

	var split_y := 0.0
	var split_cr := 0.0
	if _split_t >= 0.0:
		if _split_t < 0.24:
			split_y = 0.055 * sin(PI * _split_t / 0.24)
		else:
			split_cr = 0.22 * sin(PI * (_split_t - 0.24) / 0.18)
	if dt <= 0.0:
		_stride_sig = cos(_gait * TAU) * gait_w

	# --- الجذع ---
	var sg := _stride_sig
	var breath := sin(_time * lerpf(1.6, 3.4, fatigue)) * lerpf(0.004, 0.012, fatigue)
	# اهتزاز المشي: الأدنى عند تباعد القدمين (مشي) والأعلى في طور الطيران (جري)
	var bob_t := gait_w * (0.016 * (1.0 - 2.0 * absf(sg)) * (1.0 - run) + 0.026 * (2.0 * absf(sg) - 1.0) * run)
	_bob = bob_t if dt <= 0.0 else lerpf(_bob, bob_t, clampf(dt * 14.0, 0.0, 1.0))
	var bob := _bob + 0.010 * sin(_time * 9.0) * alert * (1.0 - gait_w) * (1.0 - p.stance)
	# الميل مع التسارع (للأمام عند الانطلاق، للخلف عند الكبح) وانخفاض الورك عند التوقف المفاجئ
	var lean_run_f := clampf(-move_vel.z / 7.0, -0.6, 1.0) * 9.0 * (1.0 - p.stance * 0.5) + balance.y * 14.0 + clampf(-_acc.z, -12.0, 12.0) * 0.9
	var lean_run_s := clampf(move_vel.x / 7.0, -1.0, 1.0) * 8.0 * (1.0 - p.stance * 0.5) + balance.x * 16.0 + clampf(_acc.x, -12.0, 12.0) * 0.6
	var pc := p.blend(p, 0.0)
	pc.cr += split_cr + 0.16 * _brake
	# دوران الحوض مع الخطوة ودوران الصدر المعاكس له
	pc.hip += sg * 7.0 * hand * gait_w
	pc.turn -= sg * 6.0 * hand * gait_w
	pc.sway.x += _lat_shift
	var T := _torso(pc, bob + split_y, lean_run_f, lean_run_s)
	var bp: Basis = T["bp"]
	var ba: Basis = T["ba"]
	var bc: Basis = T["bc"]
	var pp: Vector3 = T["pp"]
	var yaw_h: float = T["yaw_h"]

	# --- القدمان (قبل تثبيت ارتفاع الحوض) ---
	var feet: Array = _feet_static(p, yaw_h, speed, gait_w, run) if (dt <= 0.0 or not is_inside_tree()) else _feet_step(p, dt, yaw_h, speed, gait_w, run, split_y)
	var fpos := [Vector3.ZERO, Vector3.ZERO]
	var leg_max := (THIGH + SHIN) * 0.992
	var drop := 0.0
	for i in 2:
		var s0 := "L" if i == 0 else "R"
		var f0: Dictionary = feet[i]
		var fp0: Vector3 = f0["pos"]
		fp0.y += split_y * 0.9
		if p.jp > 0.02:
			fp0.y += p.jp * (1.25 if i == 0 else 1.05)
			if p.jp > 0.1 and p.stance > 0.5:
				fp0.z += (-0.2 if i == 0 else 0.22) * clampf(p.jp / 0.25, 0.0, 1.0)   # ركلة مقصية
		fpos[i] = fp0
		var hj0 := pp + bp * (_o("UpLeg." + s0) - _o("Hips"))
		var d2 := Vector2(fp0.x - hj0.x, fp0.z - hj0.z).length_squared()
		var max_y := fp0.y + sqrt(maxf(leg_max * leg_max - d2, 0.09))
		drop = maxf(drop, hj0.y - max_y)
	# الحوض ينخفض بقدر ما يلزم كي لا تُشدّ الساقان (خطوات واسعة، اندفاع جانبي)
	drop = clampf(drop, 0.0, 0.38)
	_hip_drop = drop if dt <= 0.0 else lerpf(_hip_drop, drop, clampf(dt * 22.0, 0.0, 1.0))
	var dv := Vector3(0, -_hip_drop, 0)
	pp += dv
	_set_g("Hips", _part("Hips", bp, pp))
	_set_g("Spine", _part("Spine", ba, (T["ps"] as Vector3) + dv))
	var chest := _part("Chest", bc, (T["pc"] as Vector3) + dv + bc.y * breath)
	_set_g("Chest", chest)

	# --- الرأس والرقبة ---
	# الزوايا تُحسب بالنسبة للصدر وتُحدّ بمدى الرقبة الطبيعي، مع قصور ذاتي ناعم،
	# ويبقى الرأس مستوياً (العينان أفقيتان) مهما مال الجذع، وتثبت العين على نقطة التلامس لحظة الضرب.
	var neck_o := chest.origin + bc * (_o("Neck") - _o("Chest"))
	var head_o0 := neck_o + bc * (_o("Head") - _o("Neck"))
	var tgt_pt := look_target
	if (mode == Mode.SWING or mode == Mode.SERVE_SWING) and clip_t > -0.14 and clip_t < 0.17:
		tgt_pt = contact
	var ldir := bc.inverse() * (tgt_pt - (head_o0 + bc.y * 0.09))
	var yaw_t := 0.0
	var pitch_t := 0.0
	if ldir.length_squared() > 0.04:
		ldir = ldir.normalized()
		yaw_t = atan2(-ldir.x, -ldir.z)
		pitch_t = asin(clampf(ldir.y, -1.0, 1.0))
		if absf(yaw_t) > 2.1:
			# الهدف خلف الجسم: يبقى الرأس على الجهة التي كان ينظر إليها
			yaw_t = (signf(_head_yaw) if absf(_head_yaw) > 0.2 else signf(yaw_t)) * 1.15
		yaw_t = clampf(yaw_t, -1.15, 1.15)
		pitch_t = clampf(pitch_t, -0.55, 0.85)
	yaw_t *= p.look_w
	pitch_t = pitch_t * p.look_w - deg_to_rad(p.head_pitch)
	var hy := _damp(_head_yaw, yaw_t, _head_vy, 0.085, 7.5, dt)
	var hp := _damp(_head_pitch, pitch_t, _head_vp, 0.085, 6.0, dt)
	_head_yaw = hy.x
	_head_vy = hy.y
	_head_pitch = hp.x
	_head_vp = hp.y
	var bh := bc * Basis(Vector3.UP, _head_yaw) * Basis(Vector3.RIGHT, _head_pitch)
	var hf := -bh.z
	var hup := bh.y.lerp(Vector3.UP, 0.7).normalized()
	if absf(hf.dot(hup)) < 0.97:
		bh = Basis.looking_at(hf, hup)
	# الرقبة تتحمل نحو 40% من الدوران، والرأس يتقدم قليلاً مع الانحناء كما في فقرات الرقبة
	var bn := Basis(bc.get_rotation_quaternion().slerp(bh.get_rotation_quaternion(), 0.4))
	_set_g("Neck", _part("Neck", bn, neck_o))
	var head_o := neck_o + bn * (_o("Head") - _o("Neck"))
	_set_g("Head", _part("Head", bh, head_o))

	# --- الذراع الضاربة والمضرب ---
	var hs_dom := 1.0 if _dom == "R" else -1.0
	var palm := p.nrm * (1.0 if p.dom_ps >= 0.0 else -1.0)
	var hb_dom := _hand_frame(p.axis, palm, hs_dom)
	var grip := p.grip + dv
	var wrist_t := grip - hb_dom.y * GRIP_A + hb_dom.z * GRIP_B
	var wrist := _arm(_dom, chest, bc, wrist_t, hb_dom, bc * p.pole, true)
	var grip_real := wrist + hb_dom.y * GRIP_A - hb_dom.z * GRIP_B
	var ry := p.axis.normalized()
	var rz := p.nrm - ry * p.nrm.dot(ry)
	if rz.length_squared() < 0.0001:
		rz = Vector3.BACK - ry * Vector3.BACK.dot(ry)
	rz = rz.normalized()
	_racket.transform = Transform3D(Basis(ry.cross(rz), ry, rz), grip_real)
	_curl(_dom, 0.86, 0.75)

	# --- اليد الحرة ---
	var hs_off := -hs_dom
	var off_t := p.lhand + dv
	var hb_off: Basis
	var use_hb := p.offgrip > 0.5
	if use_hb:
		var ps_off := p.nrm * (1.0 if p.off_ps >= 0.0 else -1.0)
		hb_off = _hand_frame(p.axis, ps_off, hs_off)
		off_t = grip_real + (p.lhand - p.grip) - hb_off.y * GRIP_A + hb_off.z * GRIP_B
	if catch_w > 0.01 and not use_hb:
		off_t = off_t.lerp(catch_pt, catch_w)
	var off_pole := bc * p.off_pole
	var wrist_off := _arm(_off, chest, bc, off_t, hb_off, off_pole, use_hb)
	var hb_off_real: Basis = (_g["Hand." + _off] as Transform3D).basis
	_curl(_off, 0.82 if use_hb else lerpf(p.off_curl, 0.12, catch_w))
	_lhand_world_cache = wrist_off + hb_off_real.y * GRIP_A - hb_off_real.z * GRIP_B * 1.6
	_ball_hand = _lhand_world_cache

	# --- الساقان ---
	for i in 2:
		var s := "L" if i == 0 else "R"
		var sgn := -1.0 if i == 0 else 1.0
		var f: Dictionary = feet[i]
		var hipj := pp + bp * (_o("UpLeg." + s) - _o("Hips"))
		var fp: Vector3 = fpos[i]
		var fyaw: float = f["yaw"]
		var pitch: float = f["pitch"]
		if p.jp > 0.03:
			pitch = -0.6
		var by := Basis(Vector3.UP, fyaw)
		# الركبة تتبع اتجاه القدم (لا تلتوي الساق)
		var knee_pole := (bp * Vector3(0.22 * sgn, 0.0, -1.0)).lerp(by * Vector3(0.10 * sgn, 0.0, -1.0), 0.55)
		var dl := fp - hipj
		if dl.length() > THIGH + SHIN - 0.004:
			fp = hipj + dl.normalized() * (THIGH + SHIN - 0.004)
		var knee := _ik(hipj, fp, THIGH, SHIN, knee_pole)
		var fwd_hint := bp * Vector3.FORWARD
		_set_g("UpLeg." + s, Transform3D(_frame(knee - hipj, fwd_hint), hipj))
		_set_g("Leg." + s, Transform3D(_frame(fp - knee, fwd_hint.lerp(by * Vector3.FORWARD, 0.5)), knee))
		var fb := by * Basis(Vector3.RIGHT, pitch) * (_rest["Foot." + s] as Transform3D).basis
		_set_g("Foot." + s, Transform3D(fb, fp))
		var toe_rel := (_rest["Foot." + s] as Transform3D).basis.inverse() * (_o("Toes." + s) - _o("Foot." + s))
		var toe_o := fp + fb * toe_rel
		var flat := pitch < -0.05 and fp.y < ANKLE_H + 0.16
		# عند رفع الكعب تبقى الأصابع مسطّحة على الأرض
		var tb := by * (_rest["Toes." + s] as Transform3D).basis if (flat or fp.y < ANKLE_H + 0.03) else fb * ((_rest["Foot." + s] as Transform3D).basis.inverse() * (_rest["Toes." + s] as Transform3D).basis)
		_set_g("Toes." + s, Transform3D(tb, toe_o))
		if i < _foot_blobs.size():
			var blob: MeshInstance3D = _foot_blobs[i]
			var fwd := by * Vector3(0, 0, -0.07)
			blob.transform = Transform3D(by, Vector3(fp.x + fwd.x, 0.012, fp.z + fwd.z))
			(blob.material_override as ShaderMaterial).set_shader_parameter("strength", 0.42 * clampf(1.0 - (fp.y - ANKLE_H) / 0.22, 0.0, 1.0))
