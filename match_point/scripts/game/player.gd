class_name TennisPlayer
extends Node3D
## لاعب التنس: الحركة، التحضير، توقيت الضربة (شريط QTE)، فيزياء الاصطدام بالمضرب، جودة التنفيذ، والإرسال.
## نفس المنطق يُستخدم للاعب البشري والآلي — الفرق في من يعطي الأوامر فقط.
## كل التقييمات تؤثر فعلياً عبر PlayerProfile.derive().

signal ball_struck(info: Dictionary)
signal swing_feedback(kind: String, q: float)
signal serve_reset

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
	return float(d["reach"])


# =====================================================================
#  أوامر الحالة (من إدارة المباراة)
# =====================================================================
func place(p: Vector3) -> void:
	position = Vector3(p.x, 0.0, p.z)
	vel = Vector3.ZERO
	_walking = false


func walk_to(p: Vector3) -> void:
	_walk_target = Vector3(p.x, 0.0, p.z)
	_walking = true


func lock() -> void:
	state = St.LOCKED
	has_contact = false
	if rig.mode != PlayerRig.Mode.REACT:
		rig.set_ready(0.3)


func react_point(won: bool, kind: String, big: bool) -> void:
	if big and won:
		rig.react(PlayerRig.React.ARMS_UP)
	elif won:
		if kind == "ace" or kind == "winner" or rng.randf() < 0.45:
			rig.react(PlayerRig.React.FIST)
		elif rng.randf() < 0.5:
			rig.react(PlayerRig.React.STRINGS)
	else:
		var x := rng.randf()
		if x < 0.34:
			rig.react(PlayerRig.React.DEJECT)
		elif x < 0.54:
			rig.react(PlayerRig.React.HANDS_HIPS)
		elif x < 0.80:
			rig.react(PlayerRig.React.STRINGS)
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
	prep_type = type
	charge = 0.15
	use_ai_target = false
	ai_drop = false
	_refresh_prep_side(true)
	return true


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
	rig.start_swing(stroke_side, prep_type, _volley and not _overhead, _overhead, maxf(dtc, 0.06), to_local_pt(contact_pos), Vector3(0, 0, -1))
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
	if not c.is_empty():
		s = 1 if float(c["lat"]) >= -0.05 else -1
		vol = int(c["bounces"]) == 0
		over = (c["pos"] as Vector3).y > 2.05 and prep_type != Shot.Type.LOB
	elif ball.mode == TennisBall.Mode.FREE:
		var l := to_local_pt(ball.st.pos)
		s = 1 if l.x * hand >= -0.1 else -1
	if force or s != stroke_side or vol != _volley or over != _overhead:
		stroke_side = s
		_volley = vol
		_overhead = over
		rig.set_prep(stroke_side, prep_type, _volley and not _overhead, _overhead)


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
	rig.serve_toss()


## تقدم شريط توقيت الإرسال: 0 عند الرمي، 1 آخر لحظة ممكنة
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
	var power := ai_power if use_ai_target else charge
	var factor: float = {Shot.Type.SERVE_FLAT: 1.0, Shot.Type.SERVE_SLICE: 0.88, Shot.Type.SERVE_KICK: 0.76}[serve_type]
	var prm := Shot.params(serve_type, power, hand)
	var vmax: float = float(d["serve_max"]) * factor
	var speed := vmax * lerpf(0.76, 1.0, power) * lerpf(0.86, 1.0, clampf(q, 0.0, 1.0))
	var target := ai_target if use_ai_target else _serve_aim_target()
	var plan := ShotSolver.plan(b, target, speed, float(prm["top"]) * float(d["spin"]), prm["side"], prm["gyro"], prm["clear"], -1.0, 0.5)
	if not plan.get("ok", false):
		plan = ShotSolver.solve_arc(b, target, deg_to_rad(8.0), prm["top"], prm["side"], prm["gyro"])
	var effort := lerpf(0.55, 1.0, power)
	var m_q := 1.0 + 1.1 * pow(1.0 - clampf(q, -0.3, 1.0), 1.3)
	var sig: float = float(d["acc_sv"]) * (1.0 + 0.7 * float(d["pow_ctrl"]) * effort * effort) * m_q
	sig *= (1.0 + 1.5 * pow(1.0 - stamina, 2.0)) * pressure * 0.5
	var tq := 1.0 - clampf(q, 0.0, 1.0)
	var over := maxf(effort - (0.72 + 0.2 * PlayerProfile.t(r, "serve_pow")), 0.0)
	var az := deg_to_rad(rng.randfn(0.0, float(prm["sig_az"]) * sig)) - deg_to_rad(2.0) * tq * timing_dir * hand
	# منهجي: التأخر = منخفضة للشبكة، التبكير والقوة الزائدة = طويلة، التعب = منخفضة
	var el := deg_to_rad(rng.randfn(0.0, float(prm["sig_el"]) * sig)) - deg_to_rad(1.9) * timing_dir * tq
	el += deg_to_rad(2.4) * over * float(d["acc_sv"]) - deg_to_rad(1.3) * maxf(0.5 - stamina, 0.0)
	var sv := 1.0 + rng.randfn(0.0, float(prm["sig_v"]) * sig)
	var v := ShotSolver.perturb(plan["vel"], az, el, sv)
	ball.launch(b, v, plan["spin"])
	shot_cost(effort * 0.9)
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

	# ---- صعوبة الموقف ----
	var alat := absf(lat)
	var reach := reach_lat()
	var stretch := smoothstep(reach * 0.55, reach, alat)
	var jam := 1.0 - smoothstep(0.12, 0.45, alat)
	if eff == Shot.Type.SMASH:
		stretch = smoothstep(0.9, 1.8, alat)
		jam = 0.0
	var run := clampf(vel.length() / 7.0, 0.0, 1.0)
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
	var ret_k: float = float(d["ret"]) if game.returning_serve(idx) else 1.0
	var bal: float = d["bal"]
	var rushk: float = float(d["rush"]) * 0.5 * ret_k
	var D := 1.0 + bal * (1.5 * stretch + 0.7 * run) + 0.8 * jam + 0.7 * hpen + rushk * (0.45 * pace + 0.9 * rush) + 0.9 * behind + 1.2 * (1.0 - stamina)
	var forced := D >= 1.65 or stretch > 0.3 or run > 0.6 or hpen > 0.6 or rush > 0.4

	# ---- فيزياء الاصطدام: قدرة الضرب ----
	var prm := Shot.params(eff, power, hand)
	var pow_t := PlayerProfile.t(r, "power")
	var v_target: float = float(prm["speed"]) * lerpf(0.86, 1.04, pow_t)
	var pos_f := (1.0 - 0.35 * stretch) * (1.0 - 0.25 * jam) * (1.0 - 0.2 * behind) * (0.85 + 0.15 * stamina) * (1.0 - 0.25 * hpen)
	var v_rmax: float = float(d["racket"]) * float(STROKE_FACTOR.get(eff, 0.9)) * pos_f
	var v_in_n := v_in * 0.85
	var v_cap := SWEET_EA * v_in_n + (1.0 + SWEET_EA) * v_rmax
	var v_plan := v_target
	if eff != Shot.Type.LOB and eff != Shot.Type.DROP:
		v_plan = minf(v_target, v_cap)
	var effort := clampf((v_plan - SWEET_EA * v_in_n) / maxf((1.0 + SWEET_EA) * v_rmax, 1.0), 0.0, 1.1)
	if eff == Shot.Type.LOB or eff == Shot.Type.DROP:
		effort = 0.35 + 0.3 * power

	var target := ai_target if use_ai_target else aim_target(eff)
	var top: float = float(prm["top"]) * float(d["spin"]) * (0.75 + 0.25 * clampf(q, 0.0, 1.0))
	# ---- الخطأ المنهجي: يُحسب من العوامل (توقيت، قوة، وضع الجسم، زخم، لياقة) فيمكن فهمه وتعلّمه ----
	var m_skill: float = d[_acc_key(eff, volley)]
	var qc := clampf(q, 0.0, 1.0)
	var tq := 1.0 - qc
	var tdir := timing_dir + 0.35 * rush * tq
	var fwd := Vector3(0, 0, -side)
	var rgt := Vector3(side, 0, 0)
	var over := maxf(effort - (0.6 + 0.25 * pow_t), 0.0)
	var depth_off := over * 7.5                                   # الضرب فوق حدود القدرة = كرة طويلة
	depth_off += 0.9 * tq * maxf(-tdir, 0.0) - 1.6 * tq * maxf(tdir, 0.0)   # مبكر = أطول، متأخر = أقصر/للشبكة
	depth_off += -1.7 * stretch * bal - 1.3 * jam - 1.0 * behind
	depth_off += clampf(vel.dot(fwd), -5.0, 5.0) * 0.28           # الزخم للأمام يضيف عمقاً، للخلف ينقصه
	var high := clampf((h - 1.45) / 0.6, 0.0, 1.0) if (eff != Shot.Type.SMASH and eff != Shot.Type.LOB) else 0.0
	var low := clampf((0.45 - h) / 0.35, 0.0, 1.0)
	depth_off += high * (0.4 if eff == Shot.Type.TOPSPIN else 1.0) - 1.1 * low * (0.4 if eff == Shot.Type.SLICE else 1.0)
	depth_off -= maxf(0.55 - stamina, 0.0) * 3.2                  # التعب: الكرة تقصر وتلامس الشبكة
	depth_off *= m_skill * (0.35 if eff == Shot.Type.DROP else 1.0)
	var bias := deg_to_rad(7.0) * -tdir * tq * hand * (-1.0 if stroke_side > 0 else 1.0)   # المبكر يسحب، المتأخر يدفع
	bias += deg_to_rad(0.7) * clampf(vel.dot(rgt), -6.0, 6.0)     # الجري الجانبي يجرّ الكرة باتجاهه
	bias *= m_skill
	var plan := ShotSolver.plan(b, target + fwd * depth_off, v_plan, top, prm["side"], prm["gyro"], prm["clear"], prm["arc"], 0.5)
	if not plan.get("ok", false):
		plan = ShotSolver.solve_arc(b, Vector3(0, 0, -side * 8.5), deg_to_rad(34.0), 60.0, 0.0, 0.0)
	if not plan.get("ok", false):
		has_contact = false
		state = St.RECOVER
		_recover_until = now() + 0.3
		return

	# ---- العشوائية المتبقية: صغيرة في الظروف الجيدة وتكبر مع الصعوبة والتعب والضغط ----
	var m_power := 1.0 + 0.9 * float(d["pow_ctrl"]) * effort * effort
	var m_q := 1.0 + 1.2 * pow(1.0 - clampf(q, -0.3, 1.0), 1.3)
	var tired := 1.0 + 1.8 * pow(1.0 - stamina, 2.0)
	var sig := m_skill * m_power * m_q * (0.55 + 0.45 * D * D) * pressure * tired * 0.42
	var az := deg_to_rad(rng.randfn(0.0, float(prm["sig_az"]) * sig)) + bias
	var el := deg_to_rad(rng.randfn(0.0, float(prm["sig_el"]) * sig))
	var sv := 1.0 + rng.randfn(0.0, float(prm["sig_v"]) * sig)
	# نقطة الاصطدام على الأوتار: البعد عن المنطقة المثالية يُفقد السرعة وقد يصيب الإطار
	var off := 0.05 * pow(1.0 - clampf(q, -0.3, 1.0), 1.4) + 0.012 * (D - 1.0) + absf(rng.randfn(0.0, 0.008 * m_skill))
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
	rig.balance = Vector2(signf(lat) * stretch * 0.9 + vel.x * side * 0.05, run * 0.6) * bal
	state = St.RECOVER
	_recover_until = now() + 0.24 + 0.22 * stretch * bal + 0.1 * run * bal
	last_shot_info = {"player": idx, "type": eff, "serve": false, "speed": v.length(), "D": D, "forced": forced,
		"q": q, "frame": frame, "target": target, "volley": volley, "side": stroke_side, "effort": effort}
	ball_struck.emit(last_shot_info)


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
	var vmax: float = float(d["speed"]) * lerpf(0.84, 1.0, stamina) * 0.94
	var t_acc: float = vmax / float(d["accel"]) * 0.5
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
				var t_need := dist / vmax + (t_acc if dist > 0.6 else 0.0) + 0.06
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
			if _walking:
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
				var c := to_world_pt(Vector3(0.20 * hand, 2.70, -0.42))
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
	_update_stamina(dt)
	_update_catch()


## اللياقة: الجري المتواصل يستنزفها أكثر، ثم الضربات القوية بدرجة أقل قليلاً، والخفيفة قليلاً؛
## وتعود تدريجياً عندما يخف النشاط (أسرع عند الوقوف، أبطأ عند المشي)
var exertion := 0.0


func _update_stamina(dt: float) -> void:
	var ratio := vel.length() / maxf(float(d["speed"]), 1.0)
	exertion = move_toward(exertion, ratio, dt * 2.0)
	if ratio > 0.2:
		stamina -= 0.062 * pow(ratio, 1.7) * float(d["drain"]) * dt
	var rec := 0.0
	if ratio < 0.12:
		rec = 0.040
	elif ratio < 0.35:
		rec = 0.020
	elif ratio < 0.55:
		rec = 0.006
	if state == St.LOCKED:
		rec *= 1.35
	elif state == St.SWING or state == St.SERVE_SWING or state == St.PREP:
		rec *= 0.3
	stamina = clampf(stamina + rec * lerpf(0.75, 1.3, PlayerProfile.t(r, "stamina")) * dt, 0.0, 1.0)


func shot_cost(effort: float) -> void:
	stamina = maxf(stamina - (0.004 + 0.024 * effort * effort) * float(d["drain"]), 0.0)


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
			want = (dd / 0.7).limit_length(1.0)
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


func _move(dt: float, k: float) -> void:
	var vmax: float = float(d["speed"]) * k * lerpf(0.76, 1.0, smoothstep(0.0, 0.6, stamina))
	var tv := want.limit_length(1.0) * vmax
	tv.y = 0.0
	if tv.z * side > 0.0:
		tv.z *= 0.82          # الرجوع للخلف أبطأ
	var dv := tv - vel
	var a: float = float(d["accel"])
	if vel.dot(tv) < 0.0 or tv.length() < vel.length():
		a *= float(d["brake"])
		if game.surface_id == Court.Surface.CLAY:
			a *= 0.8          # الانزلاق على التراب
	var step := a * dt
	if dv.length() > step:
		dv = dv.normalized() * step
	vel += dv
	position += vel * dt
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
