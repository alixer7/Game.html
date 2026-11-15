class_name TennisPlayer
extends Node3D
## لاعب التنس: الحركة، التحضير، توقيت الضربة (شريط QTE)، فيزياء الاصطدام بالمضرب، جودة التنفيذ، والإرسال.
## نفس المنطق يُستخدم للاعب البشري والآلي — الفرق في من يعطي الأوامر فقط.
## كل التقييمات تؤثر فعلياً عبر PlayerProfile.derive().

signal ball_struck(info: Dictionary)
signal swing_feedback(kind: String, q: float)
signal serve_reset
signal slid(from: Vector3, to: Vector3)

enum St { LOCKED, FREE, PREP, SWING, RECOVER, SERVE_READY, SERVE_TOSS, SERVE_SWING }

const SWING_TIME := 0.24          # زمن التأرجح الأمامي حتى التلامس
const CHARGE_TIME := 0.9
const REACH_FWD := 1.9
const REACH_BACK := 0.9
const REACH_HIGH := 3.05
const TOSS_ARM := 0.45
const TOSS_FLIGHT := 0.85
const SERVE_SWING := 0.26
const SERVE_IDEAL := TOSS_FLIGHT - SERVE_SWING
const SERVE_CATCH := 1.25
const FH_IDEAL := Vector2(0.72, -0.42)
const BH_IDEAL := Vector2(-0.62, -0.50)
const BOUNCE_CYCLE := 0.62
const SWEET_EA := 0.42            # معامل الارتداد الظاهري عند النقطة المثالية من الأوتار

## عوامل سرعة رأس المضرب الفعالة حسب نوع الضربة (المسار الصاعد للدوران يقلل المركبة الأمامية)
const STROKE_FACTOR := {Shot.Type.FLAT: 1.0, Shot.Type.TOPSPIN: 0.86, Shot.Type.SLICE: 0.72, Shot.Type.LOB: 0.70,
	Shot.Type.DROP: 0.5, Shot.Type.VOLLEY: 0.45, Shot.Type.SMASH: 1.05}

var idx := 0
var side := 1
var hand := 1
var is_human := false
var display_name := ""
var profile := {}
var r := {}          # التقييمات الفعلية
var d := {}          # المعاملات المشتقة
var ball: TennisBall
var game: Node
var rig: PlayerRig
var state: int = St.LOCKED
var vel := Vector3.ZERO
var want := Vector3.ZERO
var stamina := 1.0
var assist := 2
var rng := RandomNumberGenerator.new()
var pressure := 1.0               # مضاعف الضغط في النقطة الحالية (يضبطه المباراة)

# --- الضربة ---
var prep_type: int = Shot.Type.TOPSPIN
var charge := 0.0
var aim := Vector2.ZERO
var ai_target := Vector3.ZERO
var ai_power := 0.7
var ai_drop := false
var use_ai_target := false
var stroke_side := 1
var contact_t := -1.0
var contact_pos := Vector3.ZERO
var has_contact := false
var timing_q := 1.0               # جودة التوقيت من شريط QTE
var timing_dir := 0.0             # -1 مبكر جداً ... +1 متأخر
var last_shot_info := {}
var _state_t := 0.0
var _recover_until := 0.0
var _volley := false
var _overhead := false
var _assist_plan := {}
var _assist_plan_t := -1.0
var _prep_start := 0.0

# --- الإرسال ---
var serve_type: int = Shot.Type.SERVE_FLAT
var serve_deuce := true
var serve_aim := {true: Vector2.ZERO, false: Vector2.ZERO}
var tossed := false
var toss_t := 0.0
var _serve_contact_t := 0.0
var _auto_release_t := -1.0
var _bounces_left := 0
var _bounce_t := 0.0
var _bounce_phase_prev := 0.0

# --- المشي بين النقاط ---
var _walk_target := Vector3.ZERO
var _walking := false
# --- التقاط الكرة من الأرض بين النقاط ---
var _pickup_state := 0            # 0 لا شيء، 1 يمشي نحوها، 2 ينحني، 3 يمسكها
var _pickup_t := 0.0
var _pickup_keep := false
var _pickup_throw := Vector3.ZERO


func setup(p_idx: int, p_side: int, p_profile: Dictionary, rating_offset: float, p_ball: TennisBall, p_game: Node, human: bool) -> void:
	idx = p_idx
	ball = p_ball
	game = p_game
	is_human = human
	profile = p_profile
	r = PlayerProfile.adjusted(profile["r"], rating_offset)
	d = PlayerProfile.derive(r)
	hand = int(profile["hand"])
	display_name = profile["name"]
	set_side(p_side)
	rng.randomize()
	rig = PlayerRig.new()
	add_child(rig)
	rig.setup(profile["look"], hand, profile["body"], bool(profile["two_handed"]))
	# أسلوب الإرسال: الأجسام الانفجارية تستخدم وقفة pinpoint، والكلاسيكية platform
	rig.pinpoint = String(profile["body"]) in ["athlete", "power"]
	ball.prediction_changed.connect(_on_prediction_changed)


func set_side(s: int) -> void:
	side = s
	rotation.y = 0.0 if side == 1 else PI


func to_local_pt(w: Vector3) -> Vector3:
	return Vector3((w.x - position.x) * side, w.y, (w.z - position.z) * side)


func to_world_pt(l: Vector3) -> Vector3:
	return Vector3(position.x + l.x * side, l.y, position.z + l.z * side)


func ball_hand_pos() -> Vector3:
	var hp := rig.off_hand_world()
	if state == St.SERVE_READY and _bounces_left > 0:
		var ph := fmod(_bounce_t, BOUNCE_CYCLE) / BOUNCE_CYCLE
		var y := BallPhysics.R + (hp.y - BallPhysics.R) * absf(cos(PI * ph))
		return Vector3(hp.x, y, hp.z)
	return hp


func now() -> float:
	return ball.clock


func reach_lat() -> float:
	return float(d["reach"]) * lerpf(0.9, 1.0, fit())


# =====================================================================
#  أوامر الحالة (من إدارة المباراة)
# =====================================================================
func place(p: Vector3) -> void:
	position = Vector3(p.x, 0.0, p.z)
	vel = Vector3.ZERO
	_walking = false


## التقاط الكرة: keep = يحتفظ بها (المرسل التالي)، وإلا يرميها لجامع الكرات عند throw_target
func start_pickup(keep: bool, throw_target: Vector3) -> void:
	_pickup_state = 1
	_pickup_t = 0.0
	_pickup_keep = keep
	_pickup_throw = throw_target
	_walking = false


func pickup_active() -> bool:
	return _pickup_state == 1 or _pickup_state == 2 or (_pickup_state == 3 and not _pickup_keep)


func cancel_pickup() -> void:
	if _pickup_state == 3 and not _pickup_keep and ball.holder == self:
		ball.throw_to(_pickup_throw, 0.8)
	_pickup_state = 0


func _update_pickup(dt: float) -> bool:
	if _pickup_state == 0:
		return false
	_pickup_t += dt
	match _pickup_state:
		1:
			# الوقوف بحيث تصل اليد الحرة إلى الكرة أمامه قليلاً
			var off := Vector3(-0.22 * hand * side, 0.0, -0.34 * side)
			var stand := Vector3(ball.st.pos.x, 0.0, ball.st.pos.z) - off
			var dw := stand - position
			dw.y = 0.0
			if dw.length() < 0.10 or _pickup_t > 2.4:
				_pickup_state = 2
				_pickup_t = 0.0
				want = Vector3.ZERO
				rig.pickup_pt = to_local_pt(Vector3(ball.st.pos.x, BallPhysics.R, ball.st.pos.z))
				rig.react(PlayerRig.React.PICKUP)
			else:
				want = (dw / 0.8).limit_length(0.85)
			_move(dt, 0.32)
		2:
			want = Vector3.ZERO
			_move(dt, 0.3)
			if _pickup_t >= 0.52:
				ball.hold(self)
				_pickup_state = 3
				_pickup_t = 0.0
		3:
			want = Vector3.ZERO
			_move(dt, 0.3)
			if _pickup_keep:
				_pickup_state = 0
			elif _pickup_t >= 0.75:
				ball.throw_to(_pickup_throw, 0.85)
				_pickup_state = 0
	return true


func walk_to(p: Vector3) -> void:
	_walk_target = Vector3(p.x, 0.0, p.z)
	_walking = true


func lock() -> void:
	state = St.LOCKED
	has_contact = false
	if rig.mode != PlayerRig.Mode.REACT:
		rig.set_ready(0.3)


func react_point(won: bool, kind: String, big: bool, rally: int = 1) -> void:
	var clay: bool = game != null and game.surface_id == Court.Surface.CLAY
	var spent := stamina < 0.42 or breath > 0.62
	if big and won:
		rig.react(PlayerRig.React.ARMS_UP)
		return
	# بعد تبادل طويل مرهق: اليدان على الركبتين (فوزاً أو خسارة) أحياناً
	if spent and rng.randf() < 0.65:
		rig.react(PlayerRig.React.TIRED)
		return
	var x := rng.randf()
	if won:
		if rally >= 12 and x < 0.4:
			rig.react(PlayerRig.React.RACKET_UP)
		elif kind == "ace" or kind == "winner" or kind == "body":
			if x < 0.45:
				rig.react(PlayerRig.React.FIST)
			elif x < 0.75 and rally >= 4:
				rig.react(PlayerRig.React.COME_ON)
			elif x < 0.88:
				rig.react(PlayerRig.React.STRINGS)
		elif x < 0.30:
			rig.react(PlayerRig.React.FIST)
		elif x < 0.55:
			rig.react(PlayerRig.React.STRINGS)
		elif x < 0.68 and clay:
			rig.react(PlayerRig.React.SHOE_TAP)
	else:
		if x < 0.22:
			rig.react(PlayerRig.React.DEJECT)
		elif x < 0.38:
			rig.react(PlayerRig.React.HEAD_SHAKE)
		elif x < 0.52:
			rig.react(PlayerRig.React.HANDS_HIPS)
		elif x < 0.62:
			rig.react(PlayerRig.React.LOOK_UP)
		elif x < 0.78:
			rig.react(PlayerRig.React.STRINGS)
		elif x < 0.88 and clay:
			rig.react(PlayerRig.React.SHOE_TAP)
		else:
			rig.react(PlayerRig.React.WIPE)


func set_free() -> void:
	state = St.FREE
	_walking = false
	rig.set_ready(0.25)


func enter_serve(deuce: bool, bounces: int) -> void:
	state = St.SERVE_READY
	serve_deuce = deuce
	tossed = false
	_walking = false
	_auto_release_t = -1.0
	use_ai_target = false
	aim = Vector2.ZERO
	ball.hold(self)
	_bounces_left = bounces
	_bounce_t = 0.0
	_bounce_phase_prev = 0.0
	if bounces > 0:
		rig.react(PlayerRig.React.BOUNCE)
	else:
		rig.serve_stance()


func serve_ready_to_toss() -> bool:
	return state == St.SERVE_READY and _bounces_left <= 0


func on_opponent_hit() -> void:
	if state == St.FREE and vel.length() < 3.2:
		rig.split_step()
		_split_boost_t = 0.55       # قفزة الانقسام في وقتها = انطلاقة أسرع


# =====================================================================
#  أوامر الضربة
# =====================================================================
func can_prep() -> bool:
	return state == St.FREE or (state == St.RECOVER and now() >= _recover_until - 0.08)


func begin_prep(type: int) -> bool:
	if not can_prep():
		return false
	state = St.PREP
	_state_t = now()
	_prep_start = _state_t
	prep_type = type
	charge = 0.15
	use_ai_target = false
	ai_drop = false
	_var_roll = rng.randf()
	_refresh_prep_side(true)
	return true


var _var_roll := 0.5
var swing_variant := 0


## اختيار شكل الضربة حسب الموقف (كما يختار المحترف حركته): بُعد الكرة، ارتفاعها، سرعة الجري،
## الوقت المتاح، ونوع الضربة الخلفية — مع تنويع عشوائي ثابت لكل ضربة بين الوقفة المفتوحة والمحايدة
func _pick_variant(c: Dictionary, dtc: float) -> int:
	if c.is_empty():
		return PlayerRig.Var.NORMAL
	var cp: Vector3 = c["pos"]
	var lat := absf(float(c["lat"]))
	var h := cp.y
	var spd := Vector2(vel.x, vel.z).length()
	var volley := int(c["bounces"]) == 0
	var reach := reach_lat()
	var fh := float(c["lat"]) >= -0.05
	var two := bool(profile.get("two_handed", false))
	if h > 2.05 and prep_type != Shot.Type.LOB:
		return PlayerRig.Var.NORMAL
	if volley:
		if h < 0.62:
			return PlayerRig.Var.LOW
		if lat > reach * 0.78:
			return PlayerRig.Var.STRETCH
		return PlayerRig.Var.NORMAL
	if lat > reach * 0.80:
		return PlayerRig.Var.STRETCH
	if h > 1.42 and (fh or two) and prep_type != Shot.Type.SLICE:
		return PlayerRig.Var.JUMP
	if h < 0.48:
		return PlayerRig.Var.LOW
	if spd > 3.6:
		return PlayerRig.Var.RUN
	if game.returning_serve(idx) and dtc < 0.55 and ball.st.vel.length() > 28.0:
		return PlayerRig.Var.BLOCK
	var p_open := 0.55 if fh else (0.3 if two else 0.08)
	if dtc < 0.45:
		p_open += 0.25
	if lat > 1.0:
		p_open += 0.2
	return PlayerRig.Var.OPEN if _var_roll < p_open else PlayerRig.Var.NORMAL


func cancel_prep() -> void:
	if state == St.PREP:
		state = St.FREE
		rig.set_ready(0.25)


## إفلات زر الضربة: q جودة التوقيت (من منطقة الشريط)، tdir اتجاه خطأ التوقيت
func release_shot(q: float, tdir: float) -> bool:
	if state != St.PREP:
		return false
	var c := find_contact(0.02, 1.6)
	if c.is_empty():
		_whiff()
		return false
	var t_now := now()
	var dtc: float = float(c["t"]) - t_now
	has_contact = true
	contact_t = c["t"]
	contact_pos = c["pos"]
	timing_q = q
	timing_dir = tdir
	stroke_side = 1 if float(c["lat"]) >= -0.05 else -1
	_volley = int(c["bounces"]) == 0
	_overhead = contact_pos.y > 2.05 and prep_type != Shot.Type.LOB
	state = St.SWING
	_state_t = t_now
	swing_variant = _pick_variant(c, dtc)
	rig.start_swing(stroke_side, prep_type, _volley and not _overhead, _overhead, maxf(dtc, 0.06), to_local_pt(contact_pos), Vector3(0, 0, -1), swing_variant)
	if is_human:
		swing_feedback.emit(_zone_name(q), q)
	return true


static func _zone_name(q: float) -> String:
	if q >= 0.95:
		return "perfect"
	if q >= 0.6:
		return "good"
	if q >= 0.0:
		return "poor"
	return "late"


func _whiff() -> void:
	has_contact = false
	state = St.SWING
	_state_t = now()
	var nc := Vector3((0.75 if stroke_side > 0 else -0.6) * hand, 0.95, -0.45)
	rig.start_swing(stroke_side, prep_type, false, false, SWING_TIME, nc, Vector3(0, 0, -1))
	if is_human:
		swing_feedback.emit("miss", 0.0)


## زمن التلامس «الملتزم به» (يضبطه شريط التوقيت عند ظهوره) كي لا يقفز موعد الضربة أثناء اقتراب اللاعب
var contact_pref_t := -1.0


## البحث عن أفضل لحظة تلامس في المسار المتوقع ضمن النافذة الزمنية
func find_contact(t_min: float, t_max: float) -> Dictionary:
	if ball.mode != TennisBall.Mode.FREE or not game.can_hit(idx):
		return {}
	var n := ball.pred_pos.size()
	if n == 0:
		return {}
	var t_now := now()
	var i0 := maxi(int((t_now + t_min - ball.pred_t0) / TennisBall.DT) - 1, 0)
	var i1 := mini(int((t_now + t_max - ball.pred_t0) / TennisBall.DT), n - 1)
	var need_bounce: bool = game.must_bounce(idx)
	var px := position.x + vel.x * 0.10
	var pz := position.z + vel.z * 0.10
	var best := -1
	var best_cost := 1e9
	var best_lat := 0.0
	var best_lz := 0.0
	for i in range(i0, i1 + 1):
		var bc := ball.pred_bounces[i]
		if bc >= 2:
			break
		if need_bounce and bc < 1:
			continue
		var bp := ball.pred_pos[i]
		if bp.z * side < 0.25 or bp.y > REACH_HIGH:
			continue
		var lx := (bp.x - px) * side * hand
		var lz := (bp.z - pz) * side
		var cf := Vector2(lx - FH_IDEAL.x, lz - FH_IDEAL.y).length()
		var cb := Vector2(lx - BH_IDEAL.x, lz - BH_IDEAL.y).length() + 0.12
		var c := minf(cf, cb) + absf(bp.y - 1.0) * 0.22
		if contact_pref_t > 0.0:
			c += absf(ball.pred_time(i) - contact_pref_t) * 2.5
		if c < best_cost:
			best_cost = c
			best = i
			best_lat = lx
			best_lz = lz
	if best < 0:
		return {}
	if absf(best_lat) > reach_lat() or best_lz < -REACH_FWD or best_lz > REACH_BACK:
		return {}
	return {"i": best, "t": ball.pred_time(best), "pos": ball.pred_pos[best], "lat": best_lat, "lz": best_lz,
		"bounces": ball.pred_bounces[best], "cost": best_cost}


## طول مسار الكرة المتبقي حتى نقطة التلامس (لشريط التوقيت)
func path_to_contact(c: Dictionary) -> float:
	var i_now := maxi(ball.pred_index(now()), 0)
	var i_c: int = c["i"]
	if i_c <= i_now:
		return 0.0
	var dist := ball.st.pos.distance_to(ball.pred_pos[i_now])
	var i := i_now
	while i < i_c:
		var j := mini(i + 3, i_c)
		dist += ball.pred_pos[i].distance_to(ball.pred_pos[j])
		i = j
	return dist


func _refresh_prep_side(force: bool) -> void:
	var c := find_contact(0.02, 1.6)
	var s := stroke_side
	var vol := false
	var over := false
	var vr := swing_variant
	if not c.is_empty():
		s = 1 if float(c["lat"]) >= -0.05 else -1
		vol = int(c["bounces"]) == 0
		over = (c["pos"] as Vector3).y > 2.05 and prep_type != Shot.Type.LOB
		vr = _pick_variant(c, float(c["t"]) - now())
	elif ball.mode == TennisBall.Mode.FREE:
		var l := to_local_pt(ball.st.pos)
		s = 1 if l.x * hand >= -0.1 else -1
	if force or s != stroke_side or vol != _volley or over != _overhead or vr != swing_variant:
		stroke_side = s
		_volley = vol
		_overhead = over
		swing_variant = vr
		rig.set_prep(stroke_side, prep_type, _volley and not _overhead, _overhead, swing_variant)


func _on_prediction_changed() -> void:
	if state == St.SWING and has_contact:
		var rel := contact_t - now()
		var c := find_contact(maxf(rel - 0.12, 0.0), rel + 0.16)
		if c.is_empty():
			has_contact = false
		else:
			contact_t = c["t"]
			contact_pos = c["pos"]


# =====================================================================
#  الإرسال
# =====================================================================
func start_serve(type: int) -> void:
	if state != St.SERVE_READY:
		return
	_bounces_left = 0
	state = St.SERVE_TOSS
	_state_t = now()
	serve_type = type
	tossed = false
	_auto_release_t = -1.0
	charge = 0.2
	rig.serve_toss(_serve_style())


## تقدم شريط توقيت الإرسال: 0 عند الرمي، 1 آخر لحظة ممكنة
func _serve_style() -> int:
	match serve_type:
		Shot.Type.SERVE_KICK:
			return PlayerRig.ServeStyle.KICK
		Shot.Type.SERVE_SLICE:
			return PlayerRig.ServeStyle.SLICE
	return PlayerRig.ServeStyle.FLAT


func serve_bar_progress() -> float:
	if state != St.SERVE_TOSS or not tossed:
		return -1.0
	return (now() - toss_t) / (SERVE_IDEAL + 0.06)


func release_serve(q: float, tdir: float) -> void:
	if state != St.SERVE_TOSS or not tossed:
		return
	var t_now := now()
	timing_q = q
	timing_dir = tdir
	_serve_contact_t = t_now + SERVE_SWING
	state = St.SERVE_SWING
	var cw := ball.toss_pos_at(_serve_contact_t)
	cw.y = clampf(cw.y, 2.15, 2.95)
	rig.serve_swing(SERVE_SWING, to_local_pt(cw), Vector3(0, 0, -1))
	if is_human:
		swing_feedback.emit(_zone_name(q), q)


## للآلي: إفلات بعد زمن محدد من الرمي بجودة محددة
func schedule_auto_serve(delay_after_toss: float, q: float, tdir: float) -> void:
	_auto_release_t = delay_after_toss
	timing_q = q
	timing_dir = tdir


func _serve_aim_target() -> Vector3:
	var a: Vector2 = serve_aim[serve_deuce]
	var box_sign := -side if serve_deuce else side
	var x := box_sign * 2.06 + a.x * 1.95 * side
	x = clampf(x * box_sign, 0.18, Court.SINGLES_HALF_W - 0.15) * box_sign
	var depth := clampf(5.35 + a.y * 1.15, 3.3, 6.25)
	return Vector3(x, 0.0, -side * depth)


func _do_serve() -> void:
	var b := ball.st.pos
	b.y = clampf(b.y, 2.15, 2.95)
	var q := timing_q
	var qc := clampf(q, 0.0, 1.0)
	var tq := 1.0 - qc
	var f := fit()
	var power := ai_power if use_ai_target else charge
	var factor: float = {Shot.Type.SERVE_FLAT: 1.0, Shot.Type.SERVE_SLICE: 0.88, Shot.Type.SERVE_KICK: 0.76}[serve_type]
	var prm := Shot.params(serve_type, power, hand)
	var vmax: float = float(d["serve_max"]) * factor
	var speed := vmax * lerpf(0.76, 1.0, power) * lerpf(0.86, 1.0, qc) * lerpf(0.88, 1.0, f)
	var target := ai_target if use_ai_target else _serve_aim_target()
	var plan := ShotSolver.plan(b, target, speed, float(prm["top"]) * float(d["spin"]), prm["side"], prm["gyro"], prm["clear"], -1.0, 0.5)
	if not plan.get("ok", false):
		plan = ShotSolver.solve_arc(b, target, deg_to_rad(8.0), prm["top"], prm["side"], prm["gyro"])
	var effort := lerpf(0.55, 1.0, power)
	# حد القوة المريحة في الإرسال: يرتفع مع قوة الإرسال ودقته، وينخفض مع التعب
	var comfort := 0.70 + 0.22 * PlayerProfile.t(r, "serve_pow") + 0.06 * (PlayerProfile.t(r, "serve_acc") - 0.6) - 0.15 * (1.0 - f)
	var over := maxf(effort - comfort, 0.0)
	var acc: float = d["acc_sv"]
	var sig := acc * pressure * (0.24 + 0.55 * pow(tq, 1.2) + 1.4 * over * float(d["pow_ctrl"]) + 0.45 * pow(1.0 - f, 1.5))
	# منهجي: التأخر = منخفضة للشبكة، التبكير والقوة الزائدة = طويلة، التعب = منخفضة
	var az := deg_to_rad(rng.randfn(0.0, float(prm["sig_az"]) * sig)) - deg_to_rad(2.0) * tq * timing_dir * hand * sqrt(acc)
	var el := deg_to_rad(rng.randfn(0.0, float(prm["sig_el"]) * sig)) - deg_to_rad(1.9) * timing_dir * tq * sqrt(acc)
	el += deg_to_rad(2.6) * over * acc - deg_to_rad(1.2) * pow(1.0 - f, 1.3)
	var sv := 1.0 + rng.randfn(0.0, float(prm["sig_v"]) * sig)
	var v := ShotSolver.perturb(plan["vel"], az, el, sv)
	ball.launch(b, v, plan["spin"])
	shot_cost(effort * 0.95)
	state = St.RECOVER
	_recover_until = now() + 0.42
	vel = Vector3(0, 0, -side) * 2.3      # الهبوط داخل الملعب بعد الإرسال
	last_shot_info = {"player": idx, "type": serve_type, "serve": true, "speed": v.length(), "D": sig, "forced": false,
		"q": q, "frame": false, "target": target, "volley": false, "effort": effort}
	ball_struck.emit(last_shot_info)


# =====================================================================
#  تنفيذ الضربة: فيزياء الاصطدام + نموذج الخطأ
# =====================================================================
func _do_contact() -> void:
	var b := ball.st.pos
	var l := to_local_pt(b)
	var lat := l.x * hand
	var ok: bool = ball.mode == TennisBall.Mode.FREE and game.can_hit(idx)
	ok = ok and absf(lat) <= reach_lat() + 0.12 and l.z >= -(REACH_FWD + 0.2) and l.z <= REACH_BACK + 0.2
	ok = ok and b.y <= REACH_HIGH + 0.1 and b.z * side > 0.05
	if game.must_bounce(idx) and ball.bounces_since_hit < 1:
		ok = false
	if not ok:
		has_contact = false
		state = St.RECOVER
		_recover_until = now() + 0.30
		if is_human:
			swing_feedback.emit("miss", 0.0)
		return
	_execute_shot(b, lat, l.z)


## الهدف من التصويب: aim.x يمين/يسار، aim.y عمق (أعلى = أعمق، أسفل = قصيرة بزاوية)
func aim_target(eff: int) -> Vector3:
	var ax := clampf(aim.x, -1.0, 1.0)
	var ay := clampf(aim.y, -1.0, 1.0)
	var depth := 9.0
	var wide := 3.75
	match eff:
		Shot.Type.DROP:
			depth = 2.4 + (ay + 1.0) * 1.0
			wide = 3.4
		Shot.Type.LOB:
			depth = 10.1 + ay * 1.0
			wide = 3.3
		Shot.Type.SMASH, Shot.Type.VOLLEY:
			depth = 8.0 + ay * 3.0
		_:
			depth = 8.9 + (ay * 2.2 if ay > 0.0 else ay * 3.6)
	if depth < 7.0:
		wide = 3.9
	return Vector3(ax * wide * side, 0.0, -side * depth)


## النوع الفعلي للضربة حسب الموقف
func effective_type(type: int, h: float, volley: bool, wants_drop: bool) -> int:
	if h > 2.05 and type != Shot.Type.LOB:
		return Shot.Type.SMASH
	if volley:
		if type == Shot.Type.LOB:
			return Shot.Type.LOB
		if wants_drop:
			return Shot.Type.DROP
		return Shot.Type.VOLLEY
	if wants_drop:
		return Shot.Type.DROP
	return type


func _acc_key(eff: int, volley: bool) -> String:
	match eff:
		Shot.Type.SMASH:
			return "acc_sm"
		Shot.Type.DROP, Shot.Type.LOB:
			return "acc_to"
		Shot.Type.VOLLEY:
			return "acc_vo"
	if volley:
		return "acc_vo"
	return "acc_fh" if stroke_side > 0 else "acc_bh"


func _execute_shot(b: Vector3, lat: float, lz: float) -> void:
	var h := b.y
	var volley := ball.bounces_since_hit == 0
	var v_in := ball.st.vel.length()
	var wants_drop := ai_drop if use_ai_target else (prep_type == Shot.Type.SLICE and aim.y < -0.7)
	var eff := effective_type(prep_type, h, volley, wants_drop)
	var power := ai_power if use_ai_target else charge
	var q := timing_q
	var f := fit()

	# ---- وضع الجسم وصعوبة الموقف ----
	var alat := absf(lat)
	var reach := reach_lat()
	var stretch := smoothstep(reach * 0.55, reach, alat)
	var jam := 1.0 - smoothstep(0.12, 0.45, alat)
	if eff == Shot.Type.SMASH:
		stretch = smoothstep(0.9, 1.8, alat)
		jam = 0.0
	var run := clampf(Vector2(vel.x, vel.z).length() / 7.0, 0.0, 1.0)
	var hpen := 0.0
	if eff != Shot.Type.SMASH and eff != Shot.Type.LOB:
		if h < 0.45:
			hpen = (0.45 - h) / 0.35
		elif h > 1.45:
			hpen = (h - 1.45) / 0.6 * (0.6 if eff == Shot.Type.TOPSPIN else 1.0)
		hpen = clampf(hpen, 0.0, 1.0)
	var pace := clampf((v_in - 11.0) / 14.0, 0.0, 1.0)
	var behind := clampf((lz - 0.05) / 0.7, 0.0, 1.0)
	var flight := now() - ball.hit_clock
	var rush := clampf((0.95 - flight) / 0.5, 0.0, 1.0)
	if volley:
		rush *= 0.35
	# التحضير المبكر (لفّ الكتفين قبل وصول الكرة): أقل من ~0.4 ث يعني تأرجحاً مستعجلاً
	var prep_time := now() - _prep_start
	var hurried := clampf((0.42 - prep_time) / 0.32, 0.0, 1.0)
	# الدوران القادم الثقيل (توب سبين عالٍ أو قطع منخفض) أصعب في السيطرة
	var h_in := Vector3(ball.st.vel.x, 0.0, ball.st.vel.z)
	var top_in := 0.0
	if h_in.length() > 0.5:
		h_in = h_in.normalized()
		top_in = ball.st.spin.dot(Vector3(h_in.z, 0.0, -h_in.x))
	var heavy := clampf(absf(top_in) / 320.0, 0.0, 1.0)
	var ret_k: float = float(d["ret"]) if game.returning_serve(idx) else 1.0
	# التوازن: التقييم + التعب + ما تبقى من اختلال الضربة السابقة
	var bal: float = float(d["bal"]) * (1.0 + 0.45 * (1.0 - f)) * (1.0 + 0.6 * off_balance)
	var rushk: float = float(d["rush"]) * 0.5 * ret_k
	var target := ai_target if use_ai_target else aim_target(eff)
	# تغيير اتجاه الكرة (مثلاً موازية لخط الجانب من كرة قطرية) أصعب من إعادتها في نفس الاتجاه
	var redirect := 0.0
	if h_in.length() > 0.5:
		var out_d := Vector3(target.x - b.x, 0.0, target.z - b.z).normalized()
		redirect = clampf((rad_to_deg((-h_in).angle_to(out_d)) - 18.0) / 30.0, 0.0, 1.0)
	var D := 1.0 + bal * (1.5 * stretch + 0.7 * run) + 0.8 * jam + 0.7 * hpen + rushk * (0.45 * pace + 0.9 * rush) + 0.9 * behind
	D += 0.7 * hurried + 0.35 * heavy + 0.9 * off_balance + 0.25 * redirect * (0.5 + pace) + 1.1 * (1.0 - f)
	var forced := D >= 1.75 or stretch > 0.3 or run > 0.6 or hpen > 0.6 or rush > 0.4

	# ---- فيزياء الاصطدام: قدرة الضرب ----
	var prm := Shot.params(eff, power, hand)
	var pow_t := PlayerProfile.t(r, "power")
	var v_target: float = float(prm["speed"]) * lerpf(0.84, 1.06, pow_t)
	var pos_f := (1.0 - 0.35 * stretch) * (1.0 - 0.25 * jam) * (1.0 - 0.2 * behind) * (0.84 + 0.16 * f) * (1.0 - 0.25 * hpen) * (1.0 - 0.12 * hurried)
	var v_rmax: float = float(d["racket"]) * float(STROKE_FACTOR.get(eff, 0.9)) * pos_f
	var v_in_n := v_in * 0.85
	var v_cap := SWEET_EA * v_in_n + (1.0 + SWEET_EA) * v_rmax
	var v_plan := v_target
	if eff != Shot.Type.LOB and eff != Shot.Type.DROP:
		v_plan = minf(v_target, v_cap)
	var effort := clampf((v_plan - SWEET_EA * v_in_n) / maxf((1.0 + SWEET_EA) * v_rmax, 1.0), 0.0, 1.1)
	if eff == Shot.Type.LOB or eff == Shot.Type.DROP:
		effort = 0.35 + 0.3 * power

	# الدوران: يعتمد على التقييم وجودة التوقيت، وجزء من دوران الكرة القادمة ينعكس على الأوتار
	# (من الأسهل ردّ التوب سبين بتوب سبين، ومن الأصعب رفع كرة مقطوعة منخفضة)
	var top: float = float(prm["top"]) * float(d["spin"]) * (0.72 + 0.28 * clampf(q, 0.0, 1.0))
	if eff != Shot.Type.LOB and eff != Shot.Type.DROP and eff != Shot.Type.SMASH:
		top += 0.18 * top_in

	# ---- الخطأ المنهجي: مقادير محسوبة من العوامل (يمكن فهمها وتعلّمها، لا نرد) ----
	var m_skill: float = d[_acc_key(eff, volley)]
	var qc := clampf(q, 0.0, 1.0)
	var tq := 1.0 - qc
	var tdir := timing_dir + 0.35 * rush * tq
	var fwd := Vector3(0, 0, -side)
	var rgt := Vector3(side, 0, 0)
	var comfort := comfort_level(eff, volley)
	var over := maxf(effort - comfort, 0.0)
	var depth_off := over * 7.0 * (0.7 + 0.3 * float(d["pow_ctrl"]))   # الضرب فوق حدود القدرة = كرة طويلة
	depth_off += 0.9 * tq * maxf(-tdir, 0.0) - 1.6 * tq * maxf(tdir, 0.0)   # مبكر = أطول، متأخر = أقصر/للشبكة
	depth_off += -2.1 * stretch * bal - 1.3 * jam - 1.0 * behind - 0.6 * hurried
	depth_off += clampf(vel.dot(fwd), -5.0, 5.0) * 0.28           # الزخم للأمام يضيف عمقاً، للخلف ينقصه
	var high := clampf((h - 1.45) / 0.6, 0.0, 1.0) if (eff != Shot.Type.SMASH and eff != Shot.Type.LOB) else 0.0
	var low := clampf((0.45 - h) / 0.35, 0.0, 1.0)
	depth_off += high * (0.4 if eff == Shot.Type.TOPSPIN else 1.0) - 1.1 * low * (0.4 if eff == Shot.Type.SLICE else 1.0)
	depth_off += 0.5 * heavy * tq * signf(top_in)                  # التوب سبين القادم يطير عن الأوتار إن لم يُضبط
	depth_off -= 2.4 * pow(1.0 - f, 1.3) + 0.8 * off_balance       # التعب واختلال التوازن: الكرة تقصر وتلامس الشبكة
	depth_off *= m_skill * (0.35 if eff == Shot.Type.DROP else 1.0)
	var bias := deg_to_rad(7.0) * -tdir * tq * hand * (-1.0 if stroke_side > 0 else 1.0)   # المبكر يسحب، المتأخر يدفع
	bias += deg_to_rad(0.7) * clampf(vel.dot(rgt), -6.0, 6.0)     # الجري الجانبي يجرّ الكرة باتجاهه
	bias *= sqrt(m_skill)
	var plan := ShotSolver.plan(b, target + fwd * depth_off, v_plan, top, prm["side"], prm["gyro"], prm["clear"], prm["arc"], 0.5)
	if not plan.get("ok", false):
		plan = ShotSolver.solve_arc(b, Vector3(0, 0, -side * 8.5), deg_to_rad(34.0), 60.0, 0.0, 0.0)
	if not plan.get("ok", false):
		has_contact = false
		state = St.RECOVER
		_recover_until = now() + 0.3
		return

	# ---- العشوائية المتبقية: صغيرة جداً لضربة متقنة من وضع جيد، وتكبر مع الصعوبة والقوة الزائدة والتعب والضغط ----
	var settled := 0.85 if (run < 0.2 and off_balance < 0.1 and hurried < 0.1) else 1.0
	var sig := m_skill * pressure * settled * (0.23 + 0.42 * (D - 1.0) + 0.55 * pow(tq, 1.2) + 0.9 * over * float(d["pow_ctrl"]) + 0.45 * pow(1.0 - f, 1.5))
	var az := deg_to_rad(rng.randfn(0.0, float(prm["sig_az"]) * sig)) + bias
	var el := deg_to_rad(rng.randfn(0.0, float(prm["sig_el"]) * sig))
	var sv := 1.0 + rng.randfn(0.0, float(prm["sig_v"]) * sig)
	# نقطة الاصطدام على الأوتار: البعد عن المنطقة المثالية يُفقد السرعة وقد يصيب الإطار
	var off := 0.05 * pow(1.0 - clampf(q, -0.3, 1.0), 1.4) + 0.012 * (D - 1.0) + absf(rng.randfn(0.0, 0.005 * m_skill))
	var ea := SWEET_EA * clampf(1.0 - pow(off / 0.13, 2.0), 0.3, 1.0)
	sv *= lerpf(1.0, (ea * v_in_n + (1.0 + ea) * v_rmax) / maxf(v_cap, 1.0), clampf(effort, 0.3, 1.0))
	var frame := off > 0.105
	if frame:
		az += deg_to_rad(rng.randfn(0.0, 6.0))
		el += deg_to_rad(rng.randf_range(2.0, 13.0)) * (1.0 if rng.randf() < 0.7 else -0.5)
		sv *= rng.randf_range(0.45, 0.8)
	var v := ShotSolver.perturb(plan["vel"], az, el, clampf(sv, 0.3, 1.25))
	var spin: Vector3 = plan["spin"]
	if frame:
		spin *= 0.4
	ball.launch(b, v, spin)

	# ---- التوازن والتعافي ----
	shot_cost(effort)
	var unb := clampf(stretch * 0.9 + run * 0.5 + jam * 0.3 + hpen * 0.3, 0.0, 1.0) * clampf(bal / 1.2, 0.5, 1.5)
	off_balance = clampf(maxf(off_balance, unb), 0.0, 1.0)
	rig.balance = Vector2(signf(lat) * stretch * 0.9 + vel.x * side * 0.05, run * 0.6) * bal
	state = St.RECOVER
	_recover_until = now() + 0.24 + 0.22 * stretch * bal + 0.1 * run * bal + 0.15 * (1.0 - f)
	last_shot_info = {"player": idx, "type": eff, "serve": false, "speed": v.length(), "D": D, "forced": forced,
		"q": q, "frame": frame, "target": target, "volley": volley, "side": stroke_side, "effort": effort,
		"stretch": stretch, "run": run, "lat": lat, "height": h, "hurried": hurried,
		"over": over, "depth_off": depth_off, "bias": rad_to_deg(bias), "sig": sig, "fit": f, "power": power}
	ball_struck.emit(last_shot_info)


## تقدير الجهد اللازم لضربة بقوة معينة (يستخدمه الآلي لاختيار القوة، وتُرسم منه علامة الحد المريح في دائرة الشحن)
func estimate_effort(type: int, power: float, v_in: float, pos_f: float = 1.0) -> float:
	if type == Shot.Type.LOB or type == Shot.Type.DROP:
		return 0.35 + 0.3 * power
	var prm := Shot.params(type, power, hand)
	var v_target: float = float(prm["speed"]) * lerpf(0.84, 1.06, PlayerProfile.t(r, "power"))
	var v_rmax: float = float(d["racket"]) * float(STROKE_FACTOR.get(type, 0.9)) * pos_f * (0.84 + 0.16 * fit())
	var v_in_n := v_in * 0.85
	var v_cap := SWEET_EA * v_in_n + (1.0 + SWEET_EA) * v_rmax
	var v_plan := minf(v_target, v_cap)
	return clampf((v_plan - SWEET_EA * v_in_n) / maxf((1.0 + SWEET_EA) * v_rmax, 1.0), 0.0, 1.1)


## حد الجهد المريح: يرتفع مع تقييم القوة ومهارة الضربة وينخفض مع التعب
func comfort_level(type: int, volley: bool) -> float:
	var stroke_t := PlayerProfile.t(r, _rating_key(type, volley))
	return float(d["comfort"]) + 0.10 * (stroke_t - 0.6) - 0.16 * (1.0 - fit())


## أعلى قوة (0..1) تبقى ضمن الجهد المريح + هامش مخاطرة
func comfort_power(type: int, v_in: float, risk: float = 0.0, volley: bool = false) -> float:
	var lim := comfort_level(type, volley) + risk
	if estimate_effort(type, 1.0, v_in) <= lim:
		return 1.0
	if estimate_effort(type, 0.0, v_in) > lim:
		return 0.0
	var lo := 0.0
	var hi := 1.0
	for i in 8:
		var m := (lo + hi) * 0.5
		if estimate_effort(type, m, v_in) <= lim:
			lo = m
		else:
			hi = m
	return lo


func _rating_key(eff: int, volley: bool) -> String:
	match eff:
		Shot.Type.SMASH:
			return "smash"
		Shot.Type.DROP, Shot.Type.LOB:
			return "touch"
		Shot.Type.VOLLEY:
			return "volley"
	if volley:
		return "volley"
	return "forehand" if stroke_side > 0 else "backhand"


# =====================================================================
#  خطة الاعتراض (للذكاء الاصطناعي ولمساعدة الجري التلقائي)
# =====================================================================
func plan_intercept(pref_h: float = 0.95, allow_volley: bool = false) -> Dictionary:
	if ball.mode != TennisBall.Mode.FREE or not game.can_hit(idx):
		return {}
	var n := ball.pred_pos.size()
	if n == 0:
		return {}
	var t_now := now()
	var i0 := maxi(int((t_now + 0.05 - ball.pred_t0) / TennisBall.DT) - 1, 0)
	var need_bounce: bool = game.must_bounce(idx)
	var vmax: float = top_speed() * 0.94
	var best := -1
	var best_score := -1e9
	var best_stand := Vector3.ZERO
	var best_side := 1
	var best_slack := 0.0
	var i := i0
	while i < n:
		var bc := ball.pred_bounces[i]
		if bc >= 2:
			break
		var bp := ball.pred_pos[i]
		var valid := bp.z * side > 0.5 and bp.y >= 0.22 and bp.y <= 2.75
		if bc == 0 and (need_bounce or not allow_volley):
			valid = false
		if valid:
			var t_i := ball.pred_time(i) - t_now
			for s in [1, -1]:
				var ideal: Vector2 = FH_IDEAL if s > 0 else BH_IDEAL
				var stand := Vector3(bp.x - ideal.x * hand * side, 0.0, bp.z - ideal.y * side)
				if stand.z * side < 0.9:
					continue
				var dist := Vector2(stand.x - position.x, stand.z - position.z).length()
				var t_need := time_to_cover(dist, vmax) + 0.06
				var slack := t_i - t_need
				var score := 0.0
				if slack >= 0.0:
					score = 10.0 - absf(bp.y - pref_h) * 2.2 - maxf(0.0, absf(stand.z) - 13.8) * 0.9
					score += minf(slack, 0.4) * 0.6
					if bc == 0:
						score -= 0.6 if bp.y < 0.9 else 0.0
					if s < 0:
						score -= 0.18
				else:
					score = slack * 6.0 - absf(bp.y - pref_h) * 0.5
				if score > best_score:
					best_score = score
					best = i
					best_stand = stand
					best_side = s
					best_slack = slack
		i += 2
	if best < 0:
		return {}
	return {"i": best, "t": ball.pred_time(best), "pos": ball.pred_pos[best], "stand": best_stand, "side": best_side,
		"slack": best_slack, "bounces": ball.pred_bounces[best]}


# =====================================================================
#  التحديث الفيزيائي
# =====================================================================
func _physics_process(dt: float) -> void:
	var t_now := now()
	match state:
		St.LOCKED:
			if _update_pickup(dt):
				pass
			elif _walking:
				var dw := _walk_target - position
				dw.y = 0.0
				if dw.length() < 0.12:
					_walking = false
					want = Vector3.ZERO
				else:
					want = (dw / 1.2).limit_length(1.0)
				_move(dt, 0.30)
			else:
				want = Vector3.ZERO
				_move(dt, 0.5)
		St.FREE:
			_apply_assist(false)
			_move(dt, 1.0)
		St.PREP:
			charge = minf(charge + dt / CHARGE_TIME, 1.0)
			_refresh_prep_side(false)
			_apply_assist(true)
			_move(dt, 0.8)
			if not is_human and not game.can_hit(idx):
				cancel_prep()
		St.SWING:
			if has_contact:
				var ideal: Vector2 = FH_IDEAL if stroke_side > 0 else BH_IDEAL
				if _overhead:
					ideal = Vector2(0.25, -0.30)
				var stand := Vector3(contact_pos.x - ideal.x * hand * side, 0.0, contact_pos.z - ideal.y * side)
				var ds := stand - position
				ds.y = 0.0
				want = (ds / 0.45).limit_length(1.0)
				_move(dt, 0.62)
				rig.update_contact(to_local_pt(contact_pos), contact_t - t_now)
				if t_now >= contact_t:
					_do_contact()
			else:
				_move(dt, 0.4)
				if t_now - _state_t > 0.5:
					state = St.FREE
		St.RECOVER:
			_move(dt, 0.35)
			if t_now >= _recover_until:
				state = St.FREE
		St.SERVE_READY:
			# التحرك على خط القاعدة قبل الضغط على زر الإرسال
			vel = Vector3(want.x * 1.7, 0.0, 0.0)
			if absf(vel.x) > 0.05:
				var lo := 0.2 if serve_deuce else -4.2
				var hi := 4.2 if serve_deuce else -0.2
				position.x = clampf((position.x + vel.x * dt) * side, lo, hi) * side
			if _bounces_left > 0:
				_bounce_t += dt
				var ph := fmod(_bounce_t, BOUNCE_CYCLE) / BOUNCE_CYCLE
				if _bounce_phase_prev < 0.5 and ph >= 0.5:
					Sfx.play("bounce_" + ["hard", "clay", "grass"][int(game.surface_id)], 0.35, randf_range(0.95, 1.05))
				if ph < _bounce_phase_prev:
					_bounces_left -= 1
					if _bounces_left <= 0:
						rig.serve_stance()
				_bounce_phase_prev = ph
		St.SERVE_TOSS:
			vel = Vector3.ZERO
			if not tossed and t_now - _state_t >= TOSS_ARM:
				tossed = true
				toss_t = t_now
				var pr := ball_hand_pos()
				var tt := PlayerRig.toss_target(_serve_style())
				var c := to_world_pt(Vector3(tt.x * hand, tt.y, tt.z))
				var v0 := (c - pr) / TOSS_FLIGHT + Vector3(0, 0.5 * BallPhysics.G * TOSS_FLIGHT, 0)
				ball.toss(pr, v0)
			if tossed:
				charge = minf(charge + dt / CHARGE_TIME, 1.0)
				if _auto_release_t > 0.0 and t_now - toss_t >= _auto_release_t:
					release_serve(timing_q, timing_dir)
				elif t_now - toss_t > SERVE_CATCH:
					ball.hold(self)
					state = St.SERVE_READY
					tossed = false
					rig.serve_stance()
					serve_reset.emit()
		St.SERVE_SWING:
			vel = Vector3.ZERO
			if t_now >= _serve_contact_t:
				_do_serve()
	# --- تغذية الأنيميشن ---
	rig.move_vel = Vector3(vel.x * side, 0.0, vel.z * side)
	rig.look_target = to_local_pt(ball.st.pos)
	# متأهب أثناء اللعب وعند انتظار الإرسال، ومسترخٍ بين النقاط
	var want_alert := 0.0
	if ball.in_play or state == St.PREP:
		want_alert = 1.0
	elif game != null and game.phase == TennisMatch.Phase.SERVE_WAIT:
		want_alert = 1.0
	rig.alert = move_toward(rig.alert, want_alert, dt * 2.6)
	rig.fatigue = 1.0 - stamina
	rig.exhaust = clampf(maxf(1.0 - fit(), breath * 0.8), 0.0, 1.0)
	rig.sliding = sliding
	_update_stamina(dt)
	_update_catch()


## =====================================================================
##  اللياقة (v0.5): نموذج من طبقتين
##   - stamina: الطاقة الآنية (الشريط) — تُستنزف بالجري المتواصل وتغيير الاتجاه والضربات القوية وطول التبادل.
##   - stamina_cap: سقف الطاقة — إرهاق المباراة المتراكم؛ كل جهد يُنقص جزءاً صغيراً منه بشكل شبه دائم،
##     ولا يُستعاد منه إلا القليل عند تبديل الملعب وبين المجموعات.
##  الاستعادة لا تبدأ فوراً: تنتظر نحو ثانية بعد آخر جهد، ثم تتسارع تدريجياً، وتتباطأ كلما اقتربت من السقف.
##  كل المعدلات مضروبة بمعاملات تقييم «التحمّل» (drain / recover / endure).
## =====================================================================
const RUN_COST := 0.027           # لكل ثانية عند العدو الكامل (قبل مضاعف التحمّل)
const BURST_COST := 0.0005        # لكل (م/ث²) فوق 4 — الانطلاق المفاجئ والكبح وتغيير الاتجاه
const POINT_COST := 0.0008        # لكل ثانية من النقطة الجارية، يتصاعد مع طولها
const SHOT_BASE := 0.0020
const SHOT_EFFORT := 0.009        # × الجهد² — الضربات القوية أغلى بكثير
const REST_RATE := 0.022          # أقصى معدل استعادة لكل ثانية بين النقاط
const REST_DELAY := 0.9           # ثوانٍ قبل أن تبدأ الاستعادة
const CAP_LOSS := 0.028           # نسبة ما يتحول من الجهد المبذول إلى إرهاق دائم

var stamina_cap := 1.0
var run_load := 0.0               # حِمل الجري المتواصل (ثوانٍ مكافئة من العدو الكامل)
var rally_shots := 0              # ضربات هذا اللاعب في التبادل الحالي
var point_time := 0.0
var rest_t := 0.0
var rest_boost := 1.0             # مضاعف الاستعادة (أكبر عند تبديل الملعب وبين المجموعات)
var breath := 0.0                 # شدة اللهاث الآنية (للأنيميشن) 0..1
var off_balance := 0.0            # اختلال التوازن المتبقي من الضربة السابقة 0..1
var spent_total := 0.0            # مجموع الطاقة المبذولة في المباراة (للإحصاءات)
var _prev_vel := Vector3.ZERO
var _acc_mag := 0.0
var dbg_cost := {}


## مستوى الأداء البدني 0..1 حسب الطاقة: كامل فوق ~78%، ويتراجع تدريجياً تحتها، وبشدة تحت 35%
func fit() -> float:
	return smoothstep(0.10, 0.78, stamina)


func _spend(x: float) -> void:
	if x <= 0.0:
		return
	stamina = maxf(stamina - x, 0.0)
	spent_total += x
	stamina_cap = maxf(stamina_cap - x * CAP_LOSS * float(d["endure"]), 0.45)


func _update_stamina(dt: float) -> void:
	if dt <= 0.0:
		return
	var spd := Vector2(vel.x, vel.z).length()
	var ratio := spd / maxf(float(d["speed"]), 1.0)
	_acc_mag = lerpf(_acc_mag, Vector2(vel.x - _prev_vel.x, vel.z - _prev_vel.z).length() / dt, clampf(dt * 12.0, 0.0, 1.0))
	_prev_vel = vel
	var live: bool = ball.in_play and game != null and game.phase == TennisMatch.Phase.IN_PLAY
	# --- الاستنزاف ---
	if ratio > 0.45:
		run_load = minf(run_load + dt * ratio * ratio, 8.0)
	else:
		run_load = maxf(run_load - dt * (0.6 if ratio < 0.2 else 0.3), 0.0)
	var c_run := RUN_COST * ratio * ratio * (1.0 + 1.0 * smoothstep(0.6, 4.5, run_load)) * dt
	var c_burst := BURST_COST * maxf(_acc_mag - 4.0, 0.0) * dt
	var c_pt := 0.0
	if live:
		point_time += dt
		c_pt = POINT_COST * (1.0 + point_time / 8.0) * dt
	dbg_cost["run"] = float(dbg_cost.get("run", 0.0)) + c_run
	dbg_cost["burst"] = float(dbg_cost.get("burst", 0.0)) + c_burst
	dbg_cost["point"] = float(dbg_cost.get("point", 0.0)) + c_pt
	_spend((c_run + c_burst + c_pt) * float(d["drain"]))
	# --- الاستعادة: متأخرة وتدريجية ---
	var exert := ratio > 0.32 or _acc_mag > 4.5 or state == St.SWING or state == St.SERVE_SWING
	rest_t = 0.0 if exert else rest_t + dt
	var rate := 0.0
	if not live:
		rate = REST_RATE * smoothstep(REST_DELAY, REST_DELAY + 2.2, rest_t) * (0.5 if ratio > 0.12 else 1.0)
	elif ratio < 0.12:
		rate = 0.004 * smoothstep(1.2, 2.5, rest_t)     # لحظات الوقوف داخل تبادل طويل
	if game != null and game.phase == TennisMatch.Phase.SERVE_WAIT and game._phase_t > 8.0:
		rate *= 0.3                                      # ساعة الإرسال: لا يمكن الانتظار بلا حدود
	var gap := maxf(stamina_cap - stamina, 0.0)
	rate *= clampf(0.3 + gap * 2.0, 0.3, 1.0)           # أبطأ كلما اقتربت من السقف
	rate *= float(d["recover"]) * rest_boost
	dbg_cost["rec"] = float(dbg_cost.get("rec", 0.0)) + minf(rate * dt, maxf(stamina_cap - stamina, 0.0))
	stamina = clampf(stamina + rate * dt, 0.0, maxf(stamina_cap, stamina))
	# --- مؤشرات للأنيميشن ---
	var want_breath := clampf((1.0 - stamina) * 0.8 + smoothstep(0.5, 3.5, run_load) * 0.5, 0.0, 1.0)
	breath = move_toward(breath, want_breath, dt * (0.6 if want_breath > breath else 0.12))
	off_balance = move_toward(off_balance, 0.0, dt / (0.45 * float(d["steady"]) * lerpf(1.6, 1.0, fit())))


func shot_cost(effort: float) -> void:
	rally_shots += 1
	var long_rally := 1.0 + minf(0.06 * rally_shots, 1.0)
	dbg_cost["shot"] = float(dbg_cost.get("shot", 0.0)) + (SHOT_BASE + SHOT_EFFORT * effort * effort) * long_rally
	_spend((SHOT_BASE + SHOT_EFFORT * effort * effort) * long_rally * float(d["drain"]))


## بداية نقطة جديدة
func begin_point_fatigue() -> void:
	rally_shots = 0
	point_time = 0.0
	rest_boost = 1.0


## نهاية نقطة: تحدد سرعة الاستعادة القادمة (boost) وما يُستعاد من الإرهاق الدائم
func begin_rest(boost: float, cap_gain: float) -> void:
	rest_boost = boost
	stamina_cap = minf(stamina_cap + cap_gain, 1.0)


## محاكاة زمن راحة دفعة واحدة (وضع الاختبار السريع بلا انتظار بين النقاط)
func simulate_rest(seconds: float) -> void:
	var saved_vel := vel
	vel = Vector3.ZERO
	_prev_vel = Vector3.ZERO
	_acc_mag = 0.0
	var t := 0.0
	while t < seconds:
		_update_stamina(0.1)
		t += 0.1
	vel = saved_vel
	_prev_vel = saved_vel


## التقاط الكرة من جامع الكرات بين النقاط: اليد الحرة تمتد نحو الكرة
func _update_catch() -> void:
	if ball.mode == TennisBall.Mode.FEED and ball.holder == self:
		var left := ball.feed_time_left()
		rig.catch_w = clampf(1.0 - (left - 0.15) / 0.55, 0.0, 1.0)
		rig.catch_pt = to_local_pt(ball.st.pos)
		rig.look_target = rig.catch_pt
	else:
		rig.catch_w = move_toward(rig.catch_w, 0.0, 0.05)


func _apply_assist(preparing: bool) -> void:
	if not is_human:
		return
	if not preparing and (assist == 0 or want.length() > 0.2):
		return
	if ball.mode != TennisBall.Mode.FREE or not game.can_hit(idx):
		if assist >= 2 and state == St.FREE and ball.in_play and game.last_hitter == idx and want.length() < 0.2:
			var tgt: Vector3 = last_shot_info.get("target", Vector3.ZERO)
			var home := Vector3(-0.08 * tgt.x, 0.0, side * (Court.HALF_LENGTH + 0.7))
			var dh := home - position
			dh.y = 0.0
			if dh.length() > 0.3:
				want = (dh / 0.9).limit_length(0.52)
		return
	if assist >= 2 or (preparing and assist >= 1):
		var t_now := now()
		if t_now - _assist_plan_t > 0.12:
			_assist_plan = plan_intercept(0.95, position.z * side < 5.5)
			_assist_plan_t = t_now
		if not _assist_plan.is_empty():
			var dd: Vector3 = (_assist_plan["stand"] as Vector3) - position
			dd.y = 0.0
			want = (dd / 0.7).limit_length(economic_pace(dd.length(), float(_assist_plan["t"]) - t_now))
	else:
		var c := find_contact(0.02, 0.9)
		if not c.is_empty():
			var s := 1 if float(c["lat"]) >= -0.05 else -1
			var ideal: Vector2 = FH_IDEAL if s > 0 else BH_IDEAL
			var cp: Vector3 = c["pos"]
			var stand := Vector3(cp.x - ideal.x * hand * side, 0.0, cp.z - ideal.y * side)
			var dd := stand - position
			dd.y = 0.0
			if dd.length() < 2.4:
				want = (dd / 0.7).limit_length(0.75)


## الجري الاقتصادي: اللاعب المحترف لا يعدو بأقصى سرعته إلا عند الحاجة — يحسب السرعة اللازمة للوصول
## قبل الكرة بهامش صغير، فيوفّر لياقته في الكرات السهلة ويعدو في الصعبة
func economic_pace(dist: float, t_left: float) -> float:
	if dist < 0.3:
		return 1.0
	var need := dist / maxf(t_left - 0.22, 0.08)
	return clampf(need / maxf(top_speed(), 1.0) * 1.25 + 0.12, 0.38, 1.0)


## أقصى سرعة جري حالية (تتأثر باللياقة)
func top_speed() -> float:
	return float(d["speed"]) * lerpf(0.76, 1.0, fit())


## تسارع الانطلاقة الأولى الحالي (يتأثر باللياقة وبقفزة الانقسام الموقوتة جيداً)
func start_accel() -> float:
	var a: float = float(d["accel"]) * lerpf(0.62, 1.0, fit())
	if _split_boost_t > 0.0:
		a *= 1.18
	return a


## الزمن اللازم لقطع مسافة من الوقوف بنموذج تسارع يتناقص مع السرعة: x(t) = v·(t − τ(1 − e^(−t/τ)))
func time_to_cover(dist: float, vmax: float = -1.0) -> float:
	if dist <= 0.01:
		return 0.0
	var v := top_speed() if vmax <= 0.0 else vmax
	var tau := v / maxf(start_accel(), 0.1)
	var t := maxf(dist / v + tau, sqrt(2.0 * tau * dist / v))
	for i in 4:
		var e := exp(-t / tau)
		var f := v * (t - tau * (1.0 - e)) - dist
		var fp := v * (1.0 - e)
		if fp < 0.0001:
			break
		t = maxf(t - f / fp, 0.01)
	return t


var _split_boost_t := 0.0
var _slide_on := false
var _slide_from := Vector3.ZERO
var sliding := 0.0                # شدة الانزلاق الحالية على التراب (للأنيميشن والآثار)


## الحركة: تسارع يتناقص كلما اقتربت السرعة من أقصاها، كبح أقوى من التسارع، وتغيير الاتجاه أثناء العدو محدود
## (يجب الإبطاء أولاً)، والتراب يطيل مسافة التوقف (انزلاق). اللياقة تخفض السرعة والتسارع.
func _move(dt: float, k: float) -> void:
	_split_boost_t = maxf(_split_boost_t - dt, 0.0)
	var vtop := top_speed()
	var vmax := vtop * k
	var tv := want.limit_length(1.0) * vmax
	tv.y = 0.0
	if tv.z * side > 0.0:
		tv.z *= 0.82          # الرجوع للخلف أبطأ
	var a0 := start_accel()
	var clay: bool = game != null and game.surface_id == Court.Surface.CLAY
	var spd := Vector2(vel.x, vel.z).length()
	var dv := tv - vel
	dv.y = 0.0
	var slide_now := 0.0
	if spd > 0.4:
		var u := vel / spd
		var along := dv.dot(u)
		var perp := dv - u * along
		var a_al: float
		if along < 0.0:
			# كبح: قوي، لكنه على التراب ينزلق اللاعب عند السرعات العالية
			a_al = a0 * float(d["brake"])
			if clay and spd > 2.6:
				a_al *= 0.58
				slide_now = smoothstep(2.6, 5.0, spd) * clampf(-along / maxf(spd, 0.1), 0.0, 1.0)
		else:
			a_al = a0 * maxf(1.0 - spd / maxf(vtop * 1.04, 0.5), 0.12)
		# تغيير الاتجاه: قدرة الالتفاف تقل مع السرعة (القدم تحتاج احتكاكاً لتغيير المسار)
		var a_pp := a0 * float(d["turn"]) * lerpf(1.25, 0.55, clampf(spd / vtop, 0.0, 1.0))
		along = clampf(along, -a_al * dt, a_al * dt)
		perp = perp.limit_length(a_pp * dt)
		dv = u * along + perp
	else:
		dv = dv.limit_length(a0 * dt)
	vel += dv
	sliding = move_toward(sliding, slide_now, dt * (6.0 if slide_now > sliding else 2.5))
	position += vel * dt
	# تسجيل أثر الانزلاق على التراب
	if sliding > 0.35 and not _slide_on:
		_slide_on = true
		_slide_from = position
	elif sliding < 0.15 and _slide_on:
		_slide_on = false
		if (position - _slide_from).length() > 0.35:
			slid.emit(_slide_from, position)
	var zs := position.z * side
	if zs < 0.75:
		position.z = 0.75 * side
		if vel.z * side < 0.0:
			vel.z = 0.0
	elif zs > Court.ARENA_HALF_L - 1.0:
		position.z = (Court.ARENA_HALF_L - 1.0) * side
		vel.z = 0.0
	if absf(position.x) > Court.ARENA_HALF_W - 0.9:
		position.x = signf(position.x) * (Court.ARENA_HALF_W - 0.9)
		vel.x = 0.0
