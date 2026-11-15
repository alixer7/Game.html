class_name TennisMatch
extends Node3D
## إدارة المباراة: تدفق النقاط، قرارات الحكم (داخل/خارج/شبكة/خطأ/إعادة)، تبديل الملعب، الضغط النفسي، والإحصاءات.

signal call_made(kind: String, data: Dictionary)
signal score_changed
signal serve_speed(kmh: float, player: int)
signal point_started(server: int, second: bool)
signal ball_hit(info: Dictionary)
signal bounce_mark(pos: Vector3, good: bool)
signal match_finished(winner: int)
signal changeover(info: Dictionary)
signal sides_changed

enum Phase { IDLE, PRE_POINT, SERVE_WAIT, IN_PLAY, POINT_OVER, MATCH_OVER }

var rules := MatchRules.new()
var players: Array[TennisPlayer] = []
var ball: TennisBall
var phase: int = Phase.IDLE
var surface_id := 0
var wind_mode := 0                # 0 بلا رياح، 1 خفيفة، 2 قوية
var fault_count := 0
var last_hitter := -1
var bounces := 0
var serve_in_flight := false
var serve_net := false
var serve_good := false
var rally_hits := 0
var stats: Array = [{}, {}]
var fast := false                 # وضع الاختبار السريع (بلا انتظار)
var _phase_t := 0.0
var _live_t := 0.0
var _next_action := ""
var _pending_ev := {}
var _last_info: Array = [{}, {}]
var _first_point := true
var _change_pending := false
var _wind_dir := 0.0
var _rng := RandomNumberGenerator.new()
var _fed := true


func setup(p_ball: TennisBall, p0: TennisPlayer, p1: TennisPlayer, p_surface: int) -> void:
	ball = p_ball
	players = [p0, p1]
	surface_id = p_surface
	_rng.randomize()
	_wind_dir = _rng.randf() * TAU
	ball.bounced.connect(_on_bounced)
	ball.net_touched.connect(_on_net)
	for p in players:
		p.ball_struck.connect(_on_struck)


func start_match(sets_to_win: int, games_per_set: int, first_server: int = 0) -> void:
	rules.sets_to_win = sets_to_win
	rules.games_per_set = games_per_set
	rules.final_tb10 = sets_to_win >= 3
	rules.reset(first_server)
	for i in 2:
		stats[i] = {"points": 0, "aces": 0, "double_faults": 0, "winners": 0, "unforced": 0, "forced": 0,
			"first_in": 0, "first_total": 0, "first_won": 0, "second_total": 0, "second_won": 0,
			"max_serve": 0.0, "serve_sum": 0.0, "serve_n": 0, "serve_points": 0, "serve_points_won": 0,
			"rally_sum": 0, "net_points": 0, "net_won": 0, "bp_total": 0, "bp_won": 0, "games_won": 0}
		players[i].stamina = 1.0
		players[i].set_side(1 if i == 0 else -1)
	fault_count = 0
	_first_point = true
	_change_pending = false
	score_changed.emit()
	_begin_point()


func server() -> int:
	return rules.current_server()


func can_hit(idx: int) -> bool:
	return phase == Phase.IN_PLAY and last_hitter >= 0 and last_hitter != idx and ball.in_play and bounces < 2


func must_bounce(idx: int) -> bool:
	return serve_in_flight and idx != last_hitter


func returning_serve(idx: int) -> bool:
	return serve_in_flight and idx != last_hitter


func start_pos(idx: int) -> Vector3:
	var srv := server()
	var deuce := rules.deuce_court()
	var s := players[idx].side
	if idx == srv:
		return Vector3(s * (0.9 if deuce else -0.9), 0.0, s * (Court.HALF_LENGTH + 0.38))
	var back := 0.95 if fault_count == 0 else 0.25
	return Vector3(s * (3.05 if deuce else -3.05), 0.0, s * (Court.HALF_LENGTH + back))


func _begin_point() -> void:
	phase = Phase.PRE_POINT
	_phase_t = 0.0
	last_hitter = -1
	bounces = 0
	serve_in_flight = false
	serve_net = false
	serve_good = false
	rally_hits = 0
	ball.in_play = false
	if _change_pending:
		_change_pending = false
		for p in players:
			p.set_side(-p.side)
		_first_point = true
		sides_changed.emit()
	for i in 2:
		players[i].lock()
		if _first_point or fast:
			players[i].place(start_pos(i))
		else:
			players[i].walk_to(start_pos(i))
	_fed = _first_point or fast or fault_count > 0
	_first_point = false
	if _fed:
		ball.hold(players[server()])
	else:
		ball.hold(null)
		ball.st.pos = _kid_pos()
	_update_pressure()
	_update_wind()


func _kid_pos() -> Vector3:
	var sp := players[server()]
	var sx := start_pos(server()).x
	return Vector3(9.0 * (signf(sx) if absf(sx) > 0.1 else 1.0), 1.3, sp.side * (Court.HALF_LENGTH + 5.6))


func _update_pressure() -> void:
	var pr := rules.pressure()
	var k := {"match": 1.0, "set": 0.75, "break": 0.55}.get(pr, 0.0) as float
	if not rules.tiebreak and rules.is_deuce():
		k = maxf(k, 0.3)
	if rules.tiebreak:
		k = maxf(k, 0.35)
	for p in players:
		p.pressure = 1.0 + (float(p.d["mental"]) - 1.0) * k
	if pr == "break":
		var recv := 1 - server()
		stats[recv]["bp_total"] += 1


func _update_wind() -> void:
	if wind_mode == 0:
		BallPhysics.wind = Vector3.ZERO
		return
	var lo := 0.4 if wind_mode == 1 else 2.5
	var hi := 2.6 if wind_mode == 1 else 6.0
	_wind_dir += _rng.randf_range(-0.5, 0.5)
	var spd := _rng.randf_range(lo, hi)
	BallPhysics.wind = Vector3(cos(_wind_dir), 0.0, sin(_wind_dir)) * spd


func _start_serve_phase() -> void:
	var srv := server()
	for i in 2:
		if (players[i].position - start_pos(i)).length() > 0.6:
			players[i].place(start_pos(i))
	var nb := 0 if fast else (2 if players[srv].is_human else _rng.randi_range(2, 4))
	if fault_count > 0 and not fast:
		nb = maxi(nb - 1, 1)
	players[srv].enter_serve(rules.deuce_court(), nb)
	players[1 - srv].set_free()
	phase = Phase.SERVE_WAIT
	_phase_t = 0.0
	point_started.emit(srv, fault_count > 0)


func _physics_process(dt: float) -> void:
	_phase_t += dt
	match phase:
		Phase.PRE_POINT:
			# جامع الكرات يرمي الكرة للمرسل فيلتقطها
			if not _fed and _phase_t > 0.5:
				_fed = true
				ball.feed(_kid_pos(), players[server()], 1.15)
			var wait := 0.05 if fast else (2.6 if fault_count == 0 else 1.3)
			if _phase_t >= wait:
				_start_serve_phase()
		Phase.IN_PLAY:
			_live_t += dt
			if ball.st.rolling and bounces >= 1:
				_end_point(last_hitter, "ace" if serve_in_flight else "winner")
			elif _live_t > 14.0:
				_end_point(1 - last_hitter, "out")
		Phase.POINT_OVER:
			var wait2 := 0.05 if fast else (3.4 if (_pending_ev.get("game", false)) else 2.6)
			if _change_pending and not fast:
				wait2 = 5.0
			if _next_action == "second" or _next_action == "let":
				wait2 = 0.05 if fast else 1.5
			if _phase_t >= wait2:
				if _next_action == "match":
					phase = Phase.MATCH_OVER
					match_finished.emit(rules.winner)
				else:
					_begin_point()


func _on_struck(info: Dictionary) -> void:
	var p: int = info["player"]
	if OS.has_environment("MP_QTE"):
		print("  struck p", p, " serve=", info["serve"], " type=", info["type"], " v=", int(float(info["speed"]) * 3.6), " q=", snappedf(float(info.get("q", 1.0)), 0.01), " eff=", snappedf(float(info.get("effort", 0.0)), 0.01), " D=", snappedf(float(info["D"]), 0.01))
	_last_info[p] = info
	if info["serve"]:
		serve_in_flight = true
		serve_net = false
		serve_good = false
		rally_hits = 0
		phase = Phase.IN_PLAY
		_live_t = 0.0
		var kmh: float = float(info["speed"]) * 3.6
		var st: Dictionary = stats[p]
		if fault_count == 0:
			st["first_total"] += 1
		else:
			st["second_total"] += 1
		st["max_serve"] = maxf(st["max_serve"], kmh)
		st["serve_sum"] += kmh
		st["serve_n"] += 1
		serve_speed.emit(kmh, p)
	else:
		serve_in_flight = false
		rally_hits += 1
	last_hitter = p
	bounces = 0
	_live_t = 0.0
	players[1 - p].on_opponent_hit()
	ball_hit.emit(info)


func _on_net(kind: int) -> void:
	if phase != Phase.IN_PLAY:
		return
	if serve_in_flight and bounces == 0:
		serve_net = true
	call_made.emit("net_touch", {"kind": kind})


func _on_bounced(pos: Vector3, speed: float) -> void:
	if phase != Phase.IN_PLAY:
		call_made.emit("bounce", {"pos": pos, "speed": speed, "live": false})
		return
	bounces += 1
	call_made.emit("bounce", {"pos": pos, "speed": speed, "live": true})
	var hitter := last_hitter
	var hs := players[hitter].side
	if bounces == 1:
		if serve_in_flight:
			var good := Court.in_service_box(pos, hs, rules.deuce_court())
			bounce_mark.emit(pos, good)
			if good and serve_net:
				_let()
			elif good:
				serve_good = true
				if fault_count == 0:
					stats[hitter]["first_in"] += 1
			else:
				_fault(pos, hs)
		else:
			var good2 := Court.in_singles(pos, -hs)
			bounce_mark.emit(pos, good2)
			if not good2:
				_end_point(1 - hitter, "net" if pos.z * hs > 0.0 else "out")
	else:
		_end_point(hitter, "ace" if serve_in_flight else "winner")


func _let() -> void:
	phase = Phase.POINT_OVER
	_phase_t = 0.0
	_next_action = "let"
	_pending_ev = {}
	ball.in_play = false
	for p in players:
		p.lock()
	call_made.emit("let", {})


func _fault(pos: Vector3, hs: int) -> void:
	fault_count += 1
	if fault_count >= 2:
		_end_point(1 - last_hitter, "double_fault")
		return
	phase = Phase.POINT_OVER
	_phase_t = 0.0
	_next_action = "second"
	_pending_ev = {}
	ball.in_play = false
	for p in players:
		p.lock()
	call_made.emit("fault", {"net": pos.z * hs > 0.0})


func _end_point(winner: int, reason: String) -> void:
	if phase != Phase.IN_PLAY:
		return
	phase = Phase.POINT_OVER
	_phase_t = 0.0
	ball.in_play = false
	var loser := 1 - winner
	var srv := server()
	var st: Dictionary = stats[winner]
	st["points"] += 1
	stats[srv]["serve_points"] += 1
	var second := fault_count > 0
	if winner == srv:
		stats[srv]["serve_points_won"] += 1
		stats[srv]["second_won" if second else "first_won"] += 1
	if rules.pressure() == "break" and winner != srv:
		stats[winner]["bp_won"] += 1
	stats[0]["rally_sum"] += rally_hits + 1
	for i in 2:
		if absf(players[i].position.z) < 6.0:
			stats[i]["net_points"] += 1
			if i == winner:
				stats[i]["net_won"] += 1
	match reason:
		"ace":
			if rally_hits == 0:
				st["aces"] += 1
			st["winners"] += 1
		"winner":
			st["winners"] += 1
		"double_fault":
			stats[loser]["double_faults"] += 1
		"out", "net":
			if bool(_last_info[loser].get("forced", false)):
				stats[loser]["forced"] += 1
			else:
				stats[loser]["unforced"] += 1
	var ev := rules.point_won(winner)
	if ev["game"]:
		stats[winner]["games_won"] += 1
	_pending_ev = ev
	_next_action = "match" if ev["match"] else "next"
	fault_count = 0
	for i in 2:
		players[i].lock()
		var rec: float = float(players[i].d["recover"]) * (2.5 if ev["change_ends"] else (1.6 if ev["game"] else 1.0))
		players[i].stamina = minf(players[i].stamina + rec, 1.0)
	if not fast:
		players[winner].react_point(true, reason, ev["match"])
		players[loser].react_point(false, reason, false)
	if OS.has_environment("MP_QTE"):
		print("POINT ", reason, " winner=", winner, " rally=", rally_hits + 1)
	call_made.emit(reason, {"winner": winner, "ev": ev, "rally": rally_hits + 1})
	score_changed.emit()
	if ev["change_ends"] and not ev["match"]:
		_change_pending = true
		if ev["game"] and not fast:
			changeover.emit({"stats": stats, "rules": rules})
