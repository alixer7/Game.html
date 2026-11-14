class_name MatchController
extends Node
## Runs one match: spawning, kickoffs, clock, goals, overtime, stats,
## replays and end of match. Drives the simulation step.

signal ended(results: Dictionary)
signal state_changed(state: int)

enum State { COUNTDOWN, PLAYING, GOAL, REPLAY, ENDED }

const REC_RATE := 2          # record every N ticks (60 Hz)
const REC_SECONDS := 6.0

var main: Node
var world: SimWorld
var pred: BallPredictor
var coord: BotCoordinator
var cfg := {}
var state := State.COUNTDOWN
var state_time := 0.0
var time_left := 300.0
var overtime := false
var ot_time := 0.0
var score := [0, 0]
var waiting_for_ground := false
var player_car: CarSim
var player_ctrl: PlayerController
var views: Array[CarView] = []
var stats := {}
var touch_log: Array = []
var _last_count := -1
var _threat_before := [false, false]
var _threat_time := [9.0, 9.0]
var _pending_check := {}
var _audio := {}
var _rng := RandomNumberGenerator.new()

# replay
var _rec: Array = []
var _rec_head := 0
var _replay: Array = []
var _replay_t := 0.0
var _replay_len := 0.0
var _goal_frame := 0
var last_goal := {}


func setup(m: Node, w: SimWorld, c: Dictionary) -> void:
	main = m
	world = w
	cfg = c
	_rng.randomize()
	pred = BallPredictor.new(world)
	coord = BotCoordinator.new(world, pred)
	world.running = false
	world.clear_cars()
	world.reset_pads()
	world.unlimited_boost = cfg.get("freeplay", false)
	world.demolitions_enabled = not cfg.get("freeplay", false)
	world.goal_scored.connect(_on_goal)
	world.ball_touched.connect(_on_touch)
	world.car_demolished.connect(_on_demo)
	world.ball_bounced.connect(_on_bounce)
	world.pad_collected.connect(_on_pad)
	world.car_bumped.connect(_on_bump)
	_spawn_cars()
	time_left = float(cfg.get("minutes", 5)) * 60.0
	score = [0, 0]
	kickoff()


func teardown() -> void:
	for sig in [world.goal_scored, world.ball_touched, world.car_demolished, world.ball_bounced, world.pad_collected, world.car_bumped]:
		for conn in sig.get_connections():
			if conn["callable"].get_object() == self:
				sig.disconnect(conn["callable"])
	for v in views:
		v.queue_free()
	views.clear()
	world.clear_cars()


func is_demo() -> bool:
	return cfg.get("demo", false)


func is_freeplay() -> bool:
	return cfg.get("freeplay", false)


func unlimited_time() -> bool:
	return is_freeplay() or is_demo() or int(cfg.get("minutes", 5)) <= 0


# ------------------------------------------------------------------ spawning

func _spawn_cars() -> void:
	var size: int = cfg.get("size", 2)
	var my_team: int = cfg.get("team", 0)
	var names := Loc.BOT_NAMES.duplicate()
	names.shuffle()
	var ni := 0
	var order: Array = []
	if is_freeplay():
		order = [[my_team, true]]
		if cfg.get("freeplay_bots", false):
			order.append([1 - my_team, false])
	else:
		for team in [0, 1]:
			for k in range(size):
				order.append([team, team == my_team and k == 0 and not is_demo()])
	for entry in order:
		var team: int = entry[0]
		var is_player: bool = entry[1]
		var car := CarSim.new()
		car.team = team
		car.is_player = is_player
		var body := int(Settings.get_value("car_body", 0)) if is_player else _rng.randi_range(0, 2)
		car.setup(body)
		var ctrl: Object
		if is_player:
			player_car = car
			player_ctrl = PlayerController.new()
			player_ctrl.car = car
			player_ctrl.touch = main.touch
			ctrl = player_ctrl
			car.display_name = str(Settings.get_value("player_name", "PLAYER"))
		else:
			var lvl: int = cfg.get("difficulty", 1)
			ctrl = BotController.new(car, world, pred, coord, lvl)
			car.display_name = names[ni % names.size()]
			ni += 1
		world.add_car(car, ctrl)
		var view := CarView.new()
		main.stage.add_child(view)
		var paint := Phys.team_color(team)
		var accent: Color = Settings.accent_color() if is_player else Settings.ACCENTS[_rng.randi_range(0, 2)]
		var trail: Color = Settings.boost_color() if is_player else Settings.BOOST_COLORS[0]
		view.setup(car, paint, accent, trail, car.display_name)
		view.show_label = not is_player
		views.append(view)
		stats[car.id] = {"name": car.display_name, "team": team, "player": is_player, "score": 0,
			"goals": 0, "assists": 0, "saves": 0, "shots": 0, "demos": 0}
		_make_audio(car, view)


func _make_audio(car: CarSim, view: CarView) -> void:
	var eng = Sfx.make_loop_player("engine_loop", view, true)
	var bst = Sfx.make_loop_player("boost_loop", view, true)
	if eng:
		eng.volume_db = -8.0 if car.is_player else -14.0
		eng.play()
	if bst:
		bst.volume_db = -60.0
		bst.play()
	_audio[car.id] = {"engine": eng, "boost": bst}


func kickoff() -> void:
	world.ball.reset(Vector3(0, Phys.BALL_R, 0))
	world.ball.basis = Basis.IDENTITY
	world.goal_enabled = true
	world.ball_frozen = true
	main.ball_view.visible = true
	var per_team := {0: [], 1: []}
	for car in world.cars:
		per_team[car.team].append(car)
	var n: int = maxi(per_team[0].size(), per_team[1].size())
	var sets: Array
	match n:
		1:
			var k := _rng.randi_range(0, 4)
			sets = [[k]]
		2:
			sets = [[0, 1], [2, 3], [0, 4], [1, 4]]
		_:
			sets = [[0, 1, 4], [2, 3, 4], [0, 1, 2], [0, 1, 3]]
	var spots: Array = sets[_rng.randi_range(0, sets.size() - 1)]
	if is_freeplay():
		spots = [4]
	for team in [0, 1]:
		var members: Array = per_team[team]
		var sp := spots.duplicate()
		sp.shuffle()
		for i in range(members.size()):
			var car: CarSim = members[i]
			var tf := SimWorld.kickoff_transform(team, sp[i % sp.size()])
			car.place(tf[0], tf[1])
			car.boost = 100.0 if is_freeplay() else Phys.BOOST_KICKOFF
			car.demolished = false
	world.cars_frozen = true
	waiting_for_ground = false
	touch_log.clear()
	_pending_check.clear()
	_set_state(State.COUNTDOWN)
	if player_car:
		main.camera.snap_behind(player_car.pos, player_car.basis)
	if main.touch:
		main.touch.reset_state()


func _set_state(s: int) -> void:
	state = s
	state_time = 0.0
	_last_count = -1
	state_changed.emit(s)


# ------------------------------------------------------------------ tick

func _physics_process(_delta: float) -> void:
	var dt := Phys.DT
	state_time += dt
	match state:
		State.COUNTDOWN:
			_tick_countdown()
			_step(dt)
		State.PLAYING:
			if not unlimited_time():
				if overtime:
					ot_time += dt
				elif time_left > 0.0:
					time_left = maxf(0.0, time_left - dt)
					if time_left <= 0.0:
						waiting_for_ground = true
				if waiting_for_ground and (world.ball.pos.y < Phys.BALL_R + 0.25 or world.ball.vel.length() < 0.5):
					_time_up()
			_step(dt)
		State.GOAL:
			_step(dt)
			if state_time > 2.6:
				if is_demo() or is_freeplay() or not Settings.get_value("replays", true):
					_after_goal()
				else:
					_start_replay()
		State.REPLAY:
			_replay_t += dt * _replay_speed()
			if _replay_t >= _replay_len:
				_end_replay()
		State.ENDED:
			_step(dt)


func _tick_countdown() -> void:
	var t := state_time
	var count := 3 - int(floor(t))
	if count != _last_count and count >= 1:
		_last_count = count
		if not is_demo():
			main.hud.show_big(str(count), "", Color.WHITE, 0.7)
			Sfx.play("beep", -4.0)
	if t >= 3.0:
		world.cars_frozen = false
		world.ball_frozen = false
		if not is_demo():
			main.hud.show_big(Loc.t("go"), "", Color(0.4, 1.0, 0.6), 0.6)
			Sfx.play("beep_go", -3.0)
		_set_state(State.PLAYING)


func _step(dt: float) -> void:
	for team in [0, 1]:
		_threat_before[team] = pred.threatens(team, 2.5)
		_threat_time[team] = pred.goal_time if _threat_before[team] else 9.0
	world.step(dt)
	pred.maybe_update(6)
	_check_pending()
	if world.tick % REC_RATE == 0 and state != State.REPLAY:
		_record()


func _time_up() -> void:
	waiting_for_ground = false
	if score[0] == score[1]:
		overtime = true
		ot_time = 0.0
		main.hud.show_big(Loc.t("overtime"), "", Color(1, 0.85, 0.3), 1.8)
		Sfx.play("horn", -4.0)
		kickoff()
	else:
		_end_match()


func _end_match() -> void:
	_set_state(State.ENDED)
	Sfx.play("horn", -2.0)
	Sfx.play("cheer", -6.0)
	var winner := 0 if score[0] > score[1] else 1
	var res := {"score": score.duplicate(), "winner": winner, "stats": stats.duplicate(true),
		"player_team": player_car.team if player_car else -1}
	ended.emit(res)


# ------------------------------------------------------------------ events

func _add_points(car_id: int, key: String, pts: int, label: String, color: Color) -> void:
	if not stats.has(car_id):
		return
	stats[car_id]["score"] += pts
	if key != "":
		stats[car_id][key] += 1
	var car := world.get_car(car_id)
	if car and car.is_player and not is_demo():
		main.hud.popup("%s  +%d" % [label, pts], color)


func _on_touch(car_id: int, strength: float) -> void:
	var car := world.get_car(car_id)
	if car == null:
		return
	touch_log.append([car_id, car.team, world.tick])
	if touch_log.size() > 16:
		touch_log.pop_front()
	var bp := world.ball.pos
	if strength > 14.0:
		Sfx.play_at("hit_hard", bp, clampf((strength - 14.0) * 0.3, -4.0, 4.0), _rng.randf_range(0.92, 1.08))
		main.fx.hit_spark(bp, strength, Phys.team_color(car.team).lerp(Color.WHITE, 0.4))
		if car.is_player:
			main.camera.shake(clampf(strength / 50.0, 0.1, 0.5))
			Settings.vibrate(25, 0.6)
	else:
		Sfx.play_at("hit_soft", bp, -6.0 + strength * 0.4, _rng.randf_range(0.95, 1.1))
		if car.is_player:
			Settings.vibrate(10, 0.3)
	main.ball_view.flash_color = Phys.team_color(car.team).lerp(Color.WHITE, 0.3)
	# shot / save bookkeeping happens after the prediction refresh
	_pending_check[car_id] = {"tick": world.tick, "threat_own": _threat_before[car.team], "threat_t": _threat_time[car.team]}
	pred.update()


func _check_pending() -> void:
	if _pending_check.is_empty():
		return
	for car_id in _pending_check.keys():
		var info: Dictionary = _pending_check[car_id]
		var car := world.get_car(car_id)
		if car == null:
			continue
		if pred.threatens(1 - car.team, 3.5):
			_add_points(car_id, "shots", 20, Loc.t("shot"), Color(0.6, 0.9, 1.0))
		if info["threat_own"] and not pred.threatens(car.team, 3.0):
			var epic: bool = info["threat_t"] < 0.6
			_add_points(car_id, "saves", 75 if epic else 50, Loc.t("epic_save") if epic else Loc.t("save"), Color(0.5, 1.0, 0.6))
			if not is_demo():
				main.hud.add_feed("%s — %s" % [car.display_name, Loc.t("epic_save") if epic else Loc.t("save")], Phys.team_color(car.team).lerp(Color.WHITE, 0.4))
				if car.is_player or epic:
					main.hud.show_big(Loc.t("epic_save") if epic else Loc.t("save"), "", Color(0.5, 1.0, 0.6), 1.0)
	_pending_check.clear()


func _on_goal(scoring_team: int, _last_id: int) -> void:
	var bp := world.ball.pos
	main.fx.goal_explosion(bp, Phys.team_color(scoring_team))
	main.arena.flash_goal(1 - scoring_team)
	main.arena.excite(1.0)
	main.ball_view.visible = false
	world.ball_frozen = true
	main.camera.shake(0.8)
	Sfx.play("goal", 0.0)
	Sfx.play("cheer", -3.0)
	Sfx.crowd_swell(10.0, 3.0)
	Settings.vibrate(120, 1.0)
	# push nearby cars away from the explosion
	for car in world.cars:
		var d := car.pos - bp
		var dist := d.length()
		if dist < 18.0 and not car.demolished:
			var f := (1.0 - dist / 18.0)
			car.vel += d.normalized() * f * 14.0 + Vector3.UP * f * 5.0
			car.ang_vel += Vector3(_rng.randf_range(-1, 1), _rng.randf_range(-1, 1), _rng.randf_range(-1, 1)) * f * 3.0
	if is_freeplay():
		_set_state(State.GOAL)
		main.hud.show_big(Loc.t("goal"), "", Phys.team_color(scoring_team).lerp(Color.WHITE, 0.3), 1.4)
		return
	score[scoring_team] += 1
	# scorer = last toucher from the scoring team
	var scorer := -1
	var scorer_tick := -1
	for i in range(touch_log.size() - 1, -1, -1):
		if touch_log[i][1] == scoring_team:
			scorer = touch_log[i][0]
			scorer_tick = touch_log[i][2]
			break
	var own_goal: bool = touch_log.size() > 0 and touch_log[touch_log.size() - 1][1] != scoring_team
	var assister := -1
	if scorer != -1:
		for i in range(touch_log.size() - 1, -1, -1):
			var e: Array = touch_log[i]
			if e[1] == scoring_team and e[0] != scorer and scorer_tick - e[2] < 5 * Phys.TICK_RATE:
				assister = e[0]
				break
	var title := Loc.t("goal")
	var sub := ""
	if scorer != -1 and not own_goal:
		_add_points(scorer, "goals", 100, Loc.t("goal"), Color(1, 0.9, 0.4))
		sub = Loc.t("scored") % stats[scorer]["name"]
		if assister != -1:
			_add_points(assister, "assists", 50, Loc.t("assist_by") % "", Color(1, 0.9, 0.4))
			sub += "   •   " + Loc.t("assist_by") % stats[assister]["name"]
	else:
		sub = Loc.t("own_goal")
	last_goal = {"team": scoring_team, "scorer": scorer, "assist": assister, "pos": bp}
	if not is_demo():
		main.hud.set_scores(score[0], score[1])
		main.hud.show_big(title, sub, Phys.team_color(scoring_team).lerp(Color.WHITE, 0.25), 2.2)
	_goal_frame = _rec.size()
	_set_state(State.GOAL)


func _after_goal() -> void:
	if is_freeplay():
		_freeplay_reset_ball()
		world.goal_enabled = true
		main.ball_view.visible = true
		_set_state(State.PLAYING)
		return
	if overtime or (waiting_for_ground or (time_left <= 0.0 and not unlimited_time())):
		if score[0] != score[1]:
			_end_match()
			return
	kickoff()


func _freeplay_reset_ball() -> void:
	var p := player_car
	var f := p.forward() if p else Vector3(0, 0, -1)
	var flat := Vector3(f.x, 0, f.z).normalized()
	var pos := (p.pos if p else Vector3.ZERO) + flat * 14.0
	pos.x = clampf(pos.x, -30, 30)
	pos.z = clampf(pos.z, -42, 42)
	pos.y = 3.0
	world.ball.reset(pos)
	world.ball.vel = Vector3(_rng.randf_range(-3, 3), _rng.randf_range(4, 9), _rng.randf_range(-3, 3))
	world.ball.touched = true
	world.ball_frozen = false


func reset_ball_freeplay() -> void:
	if is_freeplay():
		_freeplay_reset_ball()
		main.ball_view.visible = true
		world.goal_enabled = true
		if state != State.PLAYING:
			_set_state(State.PLAYING)


func _on_demo(attacker: int, victim: int) -> void:
	var v := world.get_car(victim)
	var a := world.get_car(attacker)
	if v == null or a == null:
		return
	main.fx.demo_explosion(v.pos, Phys.team_color(v.team))
	Sfx.play_at("demo", v.pos, 2.0)
	stats[attacker]["demos"] += 1
	_add_points(attacker, "", 25, Loc.t("demolition"), Color(1, 0.6, 0.3))
	if not is_demo():
		main.hud.add_feed("%s  ✖  %s" % [a.display_name, v.display_name], Phys.team_color(a.team).lerp(Color.WHITE, 0.4))
	if v.is_player:
		main.hud.show_big(Loc.t("demolished"), "", Color(1, 0.4, 0.3), 1.2, false)
		Settings.vibrate(150, 1.0)
	if a.is_player:
		main.hud.show_big(Loc.t("demolition"), "", Color(1, 0.6, 0.3), 0.8)
		main.camera.shake(0.4)


func _on_bounce(strength: float, pos: Vector3) -> void:
	if strength > 4.0:
		Sfx.play_at("bounce", pos, clampf(-12.0 + strength * 0.6, -14.0, 2.0), _rng.randf_range(0.9, 1.1))


func _on_pad(idx: int, car_id: int) -> void:
	var car := world.get_car(car_id)
	var pad := world.pads[idx]
	if car and car.is_player:
		Sfx.play("pad_big" if pad.big else "pad_small", -8.0 if pad.big else -12.0)
	if pad.big:
		main.fx.pad_pickup(pad.pos, true)


func _on_bump(a_id: int, b_id: int, strength: float) -> void:
	var a := world.get_car(a_id)
	var b := world.get_car(b_id)
	if a == null or b == null:
		return
	Sfx.play_at("bump", (a.pos + b.pos) * 0.5, clampf(-10.0 + strength * 0.5, -10.0, 3.0))
	if a.is_player or b.is_player:
		main.camera.shake(clampf(strength / 30.0, 0.1, 0.4))
		Settings.vibrate(30, 0.6)


# ------------------------------------------------------------------ replay

func _record() -> void:
	var cars_data: Array = []
	for car in world.cars:
		cars_data.append([car.pos, car.basis.get_rotation_quaternion(), car.boosting, car.supersonic,
			car.controls.steer, car.wheel_dist.duplicate(), car.wheel_contact.duplicate(), car.demolished, car.wheel_spin])
	var frame := [world.ball.pos, world.ball.basis.get_rotation_quaternion(), world.ball.vel.length(),
		world.ball.hit_flash, main.ball_view.visible, cars_data]
	var max_frames := int(REC_SECONDS * Phys.TICK_RATE / REC_RATE)
	_rec.append(frame)
	if _rec.size() > max_frames:
		_rec.pop_front()
		_goal_frame -= 1


func _start_replay() -> void:
	# play from ~4.5 s before the goal to ~0.6 s after
	var frames_per_s := float(Phys.TICK_RATE) / REC_RATE
	var end_i := clampi(_goal_frame + int(0.6 * frames_per_s), 0, _rec.size())
	var start_i := clampi(end_i - int(5.0 * frames_per_s), 0, end_i)
	_replay = _rec.slice(start_i, end_i)
	if _replay.size() < 10:
		_after_goal()
		return
	_replay_t = 0.0
	_replay_len = (_replay.size() - 1) / frames_per_s
	main.hud.set_replay(true)
	main.hud.hide_big()
	_set_state(State.REPLAY)


func _replay_speed() -> float:
	# slow motion in the final second before the goal
	var remaining := _replay_len - _replay_t
	return 0.45 if remaining < 1.4 and remaining > 0.4 else 1.0


func skip_replay() -> void:
	if state == State.REPLAY:
		_end_replay()


func _end_replay() -> void:
	main.hud.set_replay(false)
	_replay.clear()
	_after_goal()


## Applies the replay pose for the current replay time. Returns ball position.
func apply_replay(cam: Camera3D, delta: float, now: float) -> Vector3:
	var frames_per_s := float(Phys.TICK_RATE) / REC_RATE
	var f := _replay_t * frames_per_s
	var i := clampi(int(f), 0, _replay.size() - 1)
	var j := mini(i + 1, _replay.size() - 1)
	var a := clampf(f - i, 0.0, 1.0)
	var fa: Array = _replay[i]
	var fb: Array = _replay[j]
	var bp: Vector3 = (fa[0] as Vector3).lerp(fb[0], a)
	var bq: Quaternion = (fa[1] as Quaternion).slerp(fb[1], a)
	main.ball_view.visible = fa[4]
	main.ball_view.apply_pose(bp, bq, fa[2], fa[3], cam, now)
	var ca: Array = fa[5]
	var cb: Array = fb[5]
	for k in range(mini(views.size(), ca.size())):
		var da: Array = ca[k]
		var db: Array = cb[k] if k < cb.size() else da
		var v := views[k]
		v.visible = not da[7]
		var p: Vector3 = (da[0] as Vector3).lerp(db[0], a)
		var q: Quaternion = (da[1] as Quaternion).slerp(db[1], a)
		v.global_transform = Transform3D(Basis(q), p)
		v.apply_pose(da[5], da[6], da[4], lerpf(da[8], db[8], a), da[2], da[3], cam, delta, now)
		v.label.visible = false
	return bp


func replay_ball_vel() -> Vector3:
	if _replay.size() < 2:
		return Vector3.ZERO
	var frames_per_s := float(Phys.TICK_RATE) / REC_RATE
	var i := clampi(int(_replay_t * frames_per_s), 0, _replay.size() - 2)
	return ((_replay[i + 1][0] as Vector3) - (_replay[i][0] as Vector3)) * frames_per_s


# ------------------------------------------------------------------ per frame

func update_audio() -> void:
	for car in world.cars:
		if not _audio.has(car.id):
			continue
		var a: Dictionary = _audio[car.id]
		var eng = a["engine"]
		var bst = a["boost"]
		var sp := car.vel.length()
		if eng:
			eng.pitch_scale = 0.75 + sp / Phys.CAR_MAX_SPEED * 1.35 + (0.15 if car.boosting else 0.0)
			var base := -8.0 if car.is_player else -14.0
			eng.volume_db = base + (2.0 if absf(car.controls.throttle) > 0.1 else -2.0) if not car.demolished else -80.0
		if bst:
			var target := (-6.0 if car.is_player else -10.0) if car.boosting else -60.0
			bst.volume_db = move_toward(bst.volume_db, target, 6.0 if target > bst.volume_db else 3.0)
		if car.ev_jump > 0:
			Sfx.play_at("jump", car.pos, -6.0 if car.is_player else -10.0, _rng.randf_range(0.95, 1.05))
		if car.ev_flip > 0:
			Sfx.play_at("flip", car.pos, -6.0 if car.is_player else -10.0)
		if car.ev_land > 4.0:
			Sfx.play_at("land", car.pos, clampf(-16.0 + car.ev_land, -16.0, 0.0))
		car.ev_jump = 0
		car.ev_flip = 0
		car.ev_land = 0.0
