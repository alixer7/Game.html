class_name AIController
extends Node
## الخصم الآلي: يقرأ مسار الكرة بعد زمن رد فعل، يتمركز، يختار الضربة تكتيكياً،
## ويضرب بنفس نظام التوقيت والخطأ الذي يخضع له اللاعب البشري.

## مستوى الصعوبة = ذكاء الخصم (قراءة الكرة، التوقيت، التكتيك) + تعديل خفيف على تقييماته
const LEVELS := [
	{"name": "مبتدئ", "offset": -14.0, "react": 0.10, "pg": 0.26, "py": 0.40, "margin": 1.5, "aggr": 0.25, "judge": 0.55},
	{"name": "هاوٍ", "offset": -6.0, "react": 0.05, "pg": 0.42, "py": 0.38, "margin": 1.15, "aggr": 0.45, "judge": 0.75},
	{"name": "محترف", "offset": 0.0, "react": 0.02, "pg": 0.58, "py": 0.31, "margin": 0.85, "aggr": 0.65, "judge": 0.9},
	{"name": "أسطورة", "offset": 4.0, "react": 0.0, "pg": 0.72, "py": 0.23, "margin": 0.6, "aggr": 0.8, "judge": 0.97},
]

var player: TennisPlayer
var opp: TennisPlayer
var game: TennisMatch
var cfg: Dictionary = LEVELS[1]
var rng := RandomNumberGenerator.new()

var _plan := {}
var _plan_t := -1.0
var _react_at := -1.0
var _decided := false
var _leave := false
var _shot := {}
var _serve_wait := 0.0
var _recover_pos := Vector3.ZERO
var _approach := false


func setup(p: TennisPlayer, o: TennisPlayer, g: TennisMatch, level: int) -> void:
	player = p
	opp = o
	game = g
	cfg = LEVELS[clampi(level, 0, LEVELS.size() - 1)]
	rng.randomize()
	game.ball_hit.connect(_on_ball_hit)
	game.point_started.connect(_on_point_started)
	_recover_pos = player.position


func _on_point_started(srv: int, second: bool) -> void:
	_recover_pos = game.start_pos(player.idx)
	_approach = false
	_plan = {}
	_decided = false
	_leave = false
	if srv == player.idx:
		_serve_wait = rng.randf_range(0.4, 1.0) if not game.fast else 0.05
		if second and not game.fast:
			_serve_wait *= 0.8


func _on_ball_hit(info: Dictionary) -> void:
	if int(info["player"]) != player.idx:
		_react_at = player.now() + (float(player.d["react"]) + float(cfg["react"])) * rng.randf_range(0.85, 1.2) + (0.07 if bool(info["serve"]) else 0.0)
		_decided = false
		_leave = false
		_plan = {}
		_plan_t = -1.0
	else:
		_set_recovery(info)


func _set_recovery(info: Dictionary) -> void:
	var s := player.side
	var t: Vector3 = info.get("target", Vector3.ZERO)
	if _approach and not bool(info["serve"]):
		_recover_pos = Vector3(clampf(t.x * 0.45, -2.2, 2.2), 0.0, s * 3.3)
	else:
		_recover_pos = Vector3(-0.08 * t.x, 0.0, s * (Court.HALF_LENGTH + 0.75))


func _physics_process(dt: float) -> void:
	if player == null:
		return
	match player.state:
		TennisPlayer.St.SERVE_READY:
			if player.serve_ready_to_toss():
				_serve_wait -= dt
				if _serve_wait <= 0.0:
					_serve()
		TennisPlayer.St.FREE, TennisPlayer.St.PREP, TennisPlayer.St.RECOVER:
			if game.phase == TennisMatch.Phase.IN_PLAY and game.can_hit(player.idx):
				_track_ball()
			else:
				if player.state == TennisPlayer.St.PREP:
					player.cancel_prep()
				# العودة للتمركز بخطوات جانبية (أبطأ من العدو الكامل)
				_go_to(_recover_pos, 0.52)


func _go_to(p: Vector3, max_w: float) -> void:
	var d := p - player.position
	d.y = 0.0
	if d.length() < 0.2:
		player.want = Vector3.ZERO
	else:
		player.want = (d / 0.9).limit_length(max_w)


func _track_ball() -> void:
	var t_now := player.now()
	var ball := player.ball
	if t_now < _react_at:
		_go_to(_recover_pos, 0.6)
		return
	if not _decided:
		_decided = true
		_leave = false
		# الحكم على الكرة: هل ستخرج؟ (غير متاح على الإرسال — يحسمه الارتداد)
		if not game.serve_in_flight and ball.pred_has_bounce and ball.bounces_since_hit == 0:
			var out_d := Court.out_distance(ball.pred_first_bounce, player.side)
			var noise := rng.randfn(0.0, 0.35 * (1.0 - float(cfg["judge"])) + 0.05)
			if out_d + noise > 0.22 and rng.randf() < float(cfg["judge"]):
				_leave = true
	if _leave:
		# الكرة ما زالت قد تُلعب طائرةً بالخطأ: ابتعد عنها
		_go_to(_recover_pos, 0.4)
		return
	if t_now - _plan_t > 0.1 or _plan.is_empty():
		var near_net := player.position.z * player.side < 6.2
		_plan = player.plan_intercept(0.95 if not _approach else 1.2, near_net)
		_plan_t = t_now
	if _plan.is_empty():
		_go_to(_recover_pos, 0.7)
		return
	var stand: Vector3 = _plan["stand"]
	var d := stand - player.position
	d.y = 0.0
	player.want = (d / 0.5).limit_length(1.0)
	var t_left: float = float(_plan["t"]) - t_now
	if player.state != TennisPlayer.St.PREP and t_left < 0.8 and player.can_prep():
		_choose_shot()
		if player.begin_prep(_shot["type"]):
			player.charge = 0.6
	if player.state == TennisPlayer.St.PREP:
		player.use_ai_target = true
		player.ai_target = _shot["target"]
		player.ai_power = _shot["power"]
		player.ai_drop = _shot["drop"]
		var c := player.find_contact(0.02, 1.0)
		if not c.is_empty():
			if float(c["t"]) - t_now <= TennisPlayer.SWING_TIME + 0.005:
				var stroke := "forehand" if float(c["lat"]) >= -0.05 else "backhand"
				if int(c["bounces"]) == 0:
					stroke = "volley"
				var qt := _sample_quality(stroke)
				player.release_shot(qt[0], qt[1])
		elif t_left < -0.1:
			player.cancel_prep()


func _choose_shot() -> void:
	var s := player.side
	var o := opp.position
	var cp: Vector3 = _plan["pos"]
	var slack: float = _plan["slack"]
	var my_depth := cp.z * s
	var opp_depth := -o.z * s
	var margin: float = cfg["margin"]
	var aggr: float = cfg["aggr"]
	var hw := Court.SINGLES_HALF_W
	var type: int = Shot.Type.TOPSPIN
	var power := 0.6
	var drop := false
	var tx := 0.0
	var depth := 9.0
	var away := -signf(o.x) if absf(o.x) > 0.8 else (1.0 if rng.randf() < 0.5 else -1.0)
	var cross := -signf(cp.x) if absf(cp.x) > 0.5 else away
	_approach = false
	var returning := game.serve_in_flight
	if returning:
		# رد الإرسال: عميق وآمن، أكثر هجوماً على الإرسال الثاني
		var second := game.fault_count > 0
		type = Shot.Type.TOPSPIN if rng.randf() < 0.7 else Shot.Type.SLICE
		power = rng.randf_range(0.5, 0.75) if second else rng.randf_range(0.35, 0.6)
		tx = cross * rng.randf_range(0.3, hw - margin - 0.6) if rng.randf() < 0.6 else away * rng.randf_range(0.5, hw - margin - 0.4)
		depth = rng.randf_range(8.0, 10.2)
	elif slack < 0.03:
		# تحت الضغط: دفاع
		if opp_depth < 5.0 and rng.randf() < 0.55:
			type = Shot.Type.LOB
			power = 0.25
			tx = cross * rng.randf_range(0.5, 2.0)
			depth = 10.2
		else:
			type = Shot.Type.SLICE if (int(_plan["side"]) < 0 or rng.randf() < 0.4) else Shot.Type.TOPSPIN
			power = rng.randf_range(0.3, 0.5)
			tx = cross * rng.randf_range(0.3, 2.2)
			depth = rng.randf_range(8.0, 10.0)
	elif opp_depth < 5.0:
		# الخصم عند الشبكة: تمريرة أو لوب
		if rng.randf() < 0.3 and opp_depth < 3.9:
			type = Shot.Type.LOB
			power = 0.75
			tx = away * rng.randf_range(1.0, 2.8)
			depth = 10.4
		else:
			type = Shot.Type.TOPSPIN if rng.randf() < 0.6 else Shot.Type.FLAT
			power = rng.randf_range(0.7, 0.92)
			tx = away * (hw - margin * 0.9)
			depth = rng.randf_range(7.0, 10.0)
	elif my_depth < 8.2 and cp.y > 0.8:
		# كرة قصيرة: هجوم
		var r := rng.randf()
		if r < 0.14 * aggr and opp_depth > 12.6:
			type = Shot.Type.SLICE
			drop = true
			tx = away * rng.randf_range(1.5, 3.0)
			depth = 2.3
			power = 0.5
		else:
			type = Shot.Type.FLAT if r < 0.5 else Shot.Type.TOPSPIN
			power = rng.randf_range(0.75, 0.97)
			tx = away * (hw - margin * 0.75 - rng.randf_range(0.0, 0.4))
			depth = rng.randf_range(8.6, 10.8)
			_approach = rng.randf() < aggr * 0.55
	else:
		# تبادل محايد
		var r2 := rng.randf()
		if r2 < 0.07 * aggr and opp_depth > 13.2 and my_depth < 11.6:
			type = Shot.Type.SLICE
			drop = true
			tx = away * rng.randf_range(1.2, 3.0)
			depth = 2.4
			power = 0.5
		else:
			if r2 < 0.2 and int(_plan["side"]) < 0:
				type = Shot.Type.SLICE
				power = rng.randf_range(0.5, 0.75)
			elif r2 < 0.2 + 0.28 * aggr:
				type = Shot.Type.FLAT
				power = rng.randf_range(0.72, 1.0)
			else:
				type = Shot.Type.TOPSPIN
				power = rng.randf_range(0.72, 1.0)
			var dir := cross if rng.randf() < (0.62 - 0.2 * aggr) else away
			tx = dir * rng.randf_range(2.0, hw - margin * 0.7)
			depth = rng.randf_range(8.4, Court.HALF_LENGTH - margin - 0.2)
			# الخصم خارج موضعه والوقت متاح: اضرب بقوة نحو المساحة المفتوحة
			if absf(o.x) > 2.3 and slack > 0.18 and rng.randf() < 0.35 + 0.55 * aggr:
				tx = -signf(o.x) * (hw - margin - rng.randf_range(0.0, 0.5))
				depth = rng.randf_range(8.6, Court.HALF_LENGTH - margin - 0.3)
				power = minf(power + rng.randf_range(0.12, 0.25), 1.0)
				if type == Shot.Type.SLICE:
					type = Shot.Type.TOPSPIN
	var lim := hw - margin * 0.5
	_shot = {"type": type, "power": power, "drop": drop,
		"target": Vector3(clampf(tx, -lim, lim), 0.0, -s * depth)}


func _serve() -> void:
	var s := player.side
	var first := game.fault_count == 0
	var deuce := game.rules.deuce_court()
	var r := rng.randf()
	var type: int
	var power: float
	if first:
		type = Shot.Type.SERVE_FLAT if r < 0.62 else (Shot.Type.SERVE_SLICE if r < 0.88 else Shot.Type.SERVE_KICK)
		power = rng.randf_range(0.72, 1.0)
	else:
		type = Shot.Type.SERVE_KICK if r < 0.7 else Shot.Type.SERVE_SLICE
		power = rng.randf_range(0.3, 0.55)
	var box_sign := -s if deuce else s
	var m: float = float(cfg["margin"]) * 0.3 + (0.22 if first else 0.6)
	var choice := rng.randf()
	var bx := rng.randf_range(1.6, 2.4)
	if choice < 0.42:
		bx = m + 0.05
	elif choice < 0.84:
		bx = Court.SINGLES_HALF_W - m - 0.05
	var depth := Court.SERVICE_LINE - m - (rng.randf_range(0.0, 0.45) if first else rng.randf_range(0.5, 1.3))
	# موضع الوقوف
	var off := rng.randf_range(0.6, 1.8)
	player.position.x = s * (off if deuce else -off)
	player.start_serve(type)
	var qs := _sample_quality("serve_acc")
	var delay: float = TennisPlayer.SERVE_IDEAL - (1.0 - clampf(qs[0], 0.0, 1.0)) * 0.12 * (1.0 if qs[1] < 0.0 else -0.6)
	player.schedule_auto_serve(delay, qs[0], qs[1])
	player.use_ai_target = true
	player.ai_target = Vector3(box_sign * bx, 0.0, -s * depth)
	player.ai_power = power


## اختيار منطقة شريط التوقيت حسب الصعوبة وتقييم الضربة: [الجودة، اتجاه الخطأ]
func _sample_quality(stroke_key: String) -> Array:
	var tk := PlayerProfile.t(player.r, stroke_key)
	var pg := clampf((float(cfg["pg"]) + 0.18 * (tk - 0.6)) * lerpf(0.7, 1.0, player.stamina), 0.05, 0.92)
	var py := float(cfg["py"])
	var x := rng.randf()
	if x < pg:
		return [1.0, 0.0]
	if x < pg + py:
		return [rng.randf_range(0.62, 0.9), -rng.randf_range(0.2, 0.5)]
	if rng.randf() < 0.12:
		return [-0.2, 1.0]
	return [rng.randf_range(0.1, 0.5), -rng.randf_range(0.5, 1.0)]
