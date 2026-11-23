class_name RaceManager
extends Node
## Race flow: countdown + start boosts, spine-based progress with sector gates,
## positions, laps/timing, respawns, kart-to-kart bumps, mild catch-up, results.

signal countdown_tick(n: int)            # 3, 2, 1, 0 (= GO)
signal lap_completed(kart: Kart, lap: int, lap_time: float)
signal kart_finished(kart: Kart, position: int, time: float)
signal race_finished(results: Array)
signal notify(kart: Kart, text: String, color: Color)

const SECTORS := 4

var tb: TrackBuilder
var spine: SplinePath
var karts: Array[Kart] = []
var player: Kart
var laps := 3
var state := "intro"          # intro, countdown, racing, finished
var race_time := 0.0
var count_t := 0.0
var rubber := 1
var start_dist := 0.0
var finish_order: Array[Kart] = []
var _prog := {}               # kart -> Dictionary
var _first_press := {}        # kart -> countdown time of first throttle press
var _stall := {}
var _respawning := {}
var _after_finish := 0.0


func setup(builder: TrackBuilder, lap_count: int) -> void:
	tb = builder
	spine = tb.main
	laps = lap_count
	start_dist = spine.dist[tb.mark_index("start_line")]


func add_kart(k: Kart) -> void:
	karts.append(k)
	var i := spine.nearest_index(k.global_position, 40.0)
	_prog[k] = {"lap": 0, "idx": i, "rel": _rel(i), "sector": SECTORS - 1, "lap_start": 0.0, "best": INF,
		"times": [], "finished": false, "finish_time": 0.0, "wrong_t": 0.0, "pos": karts.size(), "total": 0.0}
	_update_total(k)


func _rel(i: int) -> float:
	return fposmod(spine.dist[i] - start_dist, spine.length)


func start_countdown() -> void:
	state = "countdown"
	count_t = 0.0
	for k in karts:
		k.frozen = true


func _physics_process(dt: float) -> void:
	match state:
		"countdown":
			_countdown(dt)
		"racing", "finished":
			race_time += dt
			for k in karts:
				_track(k, dt)
			_positions()
			_bumps(dt)
			_catchup()
			if state == "finished":
				_after_finish += dt


func _countdown(dt: float) -> void:
	var prev := count_t
	count_t += dt
	for n: int in [3, 2, 1]:
		var t := float(3 - n)
		if prev < t and count_t >= t:
			countdown_tick.emit(n)
	for k in karts:
		if k.in_throttle > 0.5 and not _first_press.has(k):
			_first_press[k] = count_t
	if count_t >= 3.0:
		state = "racing"
		countdown_tick.emit(0)
		for k in karts:
			k.frozen = false
			var press: float = _first_press.get(k, 99.0)
			# start boost window: pressed within 0.4 s before GO and held
			if press > 2.6 and press <= 3.05 and k.in_throttle > 0.5:
				k.add_reserve(1.3, &"start")
				notify.emit(k, "START BOOST!", Color(1.0, 0.8, 0.2))
			elif press < 2.0 and k.in_throttle > 0.5:
				_stall[k] = 0.7   # revved too early: engine stalls briefly
				notify.emit(k, "STALLED", Color(0.8, 0.8, 0.8))
		for k in _stall:
			k.stun_time = _stall[k]


func ai_start_press(k: Kart, skill: float) -> void:
	## AI decides when to "press" during the countdown.
	var t := 3.0 - randf_range(0.05, 0.38) if randf() < skill else randf_range(1.0, 3.4)
	get_tree().create_timer(maxf(t - count_t, 0.0), false, true).timeout.connect(func() -> void:
		if state == "countdown":
			_first_press[k] = count_t
			k.in_throttle = 1.0)


func _track(k: Kart, dt: float) -> void:
	var pr: Dictionary = _prog[k]
	if pr.finished and k == player:
		pass
	# --- spine index: local window search
	var n := spine.size()
	var best := int(pr.idx)
	var best_d := INF
	var p := k.global_position
	for o in range(-20, 160, 2):
		var i := (int(pr.idx) + o + n) % n
		var q := spine.pos[i]
		var d := Vector2(q.x - p.x, q.z - p.z).length_squared() + pow((q.y - p.y) * 0.5, 2.0)
		if d < best_d:
			best_d = d
			best = i
	# refine
	for o in range(-2, 3):
		var i := (best + o + n) % n
		var q := spine.pos[i]
		var d := Vector2(q.x - p.x, q.z - p.z).length_squared() + pow((q.y - p.y) * 0.5, 2.0)
		if d < best_d:
			best_d = d
			best = i
	var old_rel: float = pr.rel
	var rel := _rel(best)
	pr.idx = best
	pr.rel = rel
	var L := spine.length
	var sector := int(rel / L * SECTORS)
	if sector == (int(pr.sector) + 1) % SECTORS:
		pr.sector = sector
	# lap crossing: wrapped from the end of the lap to its start, all sectors seen
	if old_rel > L * 0.8 and rel < L * 0.2 and int(pr.sector) == 0 and not pr.finished:
		_complete_lap(k, pr)
	elif old_rel < L * 0.2 and rel > L * 0.8:
		# crossed the line backwards
		pr.sector = SECTORS - 1 if int(pr.lap) > 0 else pr.sector
		if int(pr.lap) > 0 and int(pr.sector) == SECTORS - 1:
			pr.lap = int(pr.lap) - 1
	_update_total(k)
	# wrong way
	var t := spine.tan[best]
	var hv := Vector3(k.velocity.x, 0, k.velocity.z)
	if hv.length() > 5.0 and hv.normalized().dot(Vector3(t.x, 0, t.z).normalized()) < -0.5:
		pr.wrong_t = float(pr.wrong_t) + dt
		if float(pr.wrong_t) > 1.5 and k == player:
			notify.emit(k, "WRONG WAY", Color(1, 0.3, 0.2))
			pr.wrong_t = -2.0
	else:
		pr.wrong_t = maxf(float(pr.wrong_t) - dt, 0.0)
	# respawn checks
	if not _respawning.has(k):
		var oob := k.global_position.y < Kart.KILL_Y
		if not oob and tb.terrain.dist_at(p.x, p.z) > 46.0:
			oob = true
		if oob:
			_respawn(k)


func _complete_lap(k: Kart, pr: Dictionary) -> void:
	pr.sector = 0
	var lap := int(pr.lap)
	if lap >= 1:
		var lt := race_time - float(pr.lap_start)
		(pr.times as Array).append(lt)
		pr.best = minf(float(pr.best), lt)
		lap_completed.emit(k, lap, lt)
	pr.lap = lap + 1
	pr.lap_start = race_time
	if k.get_meta("ai", null) != null:
		k.get_meta("ai").set("lap", pr.lap)
	if int(pr.lap) > laps:
		pr.finished = true
		pr.finish_time = race_time
		finish_order.append(k)
		kart_finished.emit(k, finish_order.size(), race_time)
		if k == player:
			_finish_race()
	elif int(pr.lap) == laps and lap >= 1:
		notify.emit(k, "FINAL LAP", Color(1, 0.85, 0.3))
	elif lap >= 1:
		notify.emit(k, "LAP %d" % int(pr.lap), Color(1, 1, 1))


func _finish_race() -> void:
	state = "finished"
	get_tree().create_timer(4.0, false).timeout.connect(func() -> void:
		race_finished.emit(results()))


func _update_total(k: Kart) -> void:
	var pr: Dictionary = _prog[k]
	pr.total = float(pr.lap) * spine.length + float(pr.rel) if int(pr.lap) > 0 else float(pr.rel) - spine.length


func _positions() -> void:
	var order := karts.duplicate()
	order.sort_custom(func(a: Kart, b: Kart) -> bool:
		var pa: Dictionary = _prog[a]
		var pb: Dictionary = _prog[b]
		if pa.finished and pb.finished:
			return float(pa.finish_time) < float(pb.finish_time)
		if pa.finished != pb.finished:
			return pa.finished
		return float(pa.total) > float(pb.total))
	for i in order.size():
		_prog[order[i]].pos = i + 1


func position_of(k: Kart) -> int:
	return int(_prog[k].pos)


func lap_of(k: Kart) -> int:
	return clampi(int(_prog[k].lap), 1, laps)


func progress_of(k: Kart) -> Dictionary:
	return _prog[k]


func kart_ahead_within(k: Kart, dist: float, cone := 0.4) -> bool:
	var h := k.heading()
	for o in karts:
		if o == k:
			continue
		var rel := o.global_position - k.global_position
		if rel.length() < dist and rel.normalized().dot(h) > 1.0 - cone:
			return true
	return false


func kart_behind_within(k: Kart, dist: float) -> bool:
	var h := k.heading()
	for o in karts:
		if o == k:
			continue
		var rel := o.global_position - k.global_position
		if rel.length() < dist and rel.normalized().dot(h) < -0.5:
			return true
	return false


func kart_at_position(pos: int) -> Kart:
	for k in karts:
		if int(_prog[k].pos) == pos:
			return k
	return null


func respawn_kart(k: Kart) -> void:
	if not _respawning.has(k):
		_respawn(k)


func _respawn(k: Kart) -> void:
	_respawning[k] = true
	var pr: Dictionary = _prog[k]
	var n := spine.size()
	var i := (int(pr.idx) - 4 + n) % n
	# never respawn on a jump gap
	var guard := 0
	while spine.style[i] == "gap" and guard < 60:
		i = (i - 1 + n) % n
		guard += 1
	var xf := spine.transform_at(i)
	var t := spine.tan[i]
	var yaw := atan2(-t.x, -t.z)
	k.teleport(Transform3D(Basis(Vector3.UP, yaw), xf.origin + Vector3.UP * 0.8))
	k.frozen = true
	pr.idx = i
	notify.emit(k, "", Color.WHITE)
	get_tree().create_timer(0.9, false).timeout.connect(func() -> void:
		k.frozen = false
		_respawning.erase(k))


func _bumps(_dt: float) -> void:
	var n := karts.size()
	for a in n:
		var ka := karts[a]
		for b in range(a + 1, n):
			var kb := karts[b]
			var d := kb.global_position - ka.global_position
			if absf(d.y) > 1.3:
				continue
			d.y = 0
			var dist := d.length()
			if dist > 1.55 or dist < 0.001:
				continue
			var nrm := d / dist
			var push := (1.55 - dist)
			var ma := ka.params.mass
			var mb := kb.params.mass
			var wa := mb / (ma + mb)
			var wb := ma / (ma + mb)
			ka.global_position -= nrm * push * wa
			kb.global_position += nrm * push * wb
			var rel := (kb.velocity - ka.velocity).dot(nrm)
			if rel < 0.0:
				var j := -rel * 1.2
				ka.velocity -= nrm * j * wa
				kb.velocity += nrm * j * wb
				if ka.is_player or kb.is_player:
					Sfx.play("thud", null, 1.2, -8.0)


func _catchup() -> void:
	if rubber <= 0 or player == null:
		for k in karts:
			if k.has_meta("ai"):
				k.get_meta("ai").set("catchup", 0.0)
		return
	var leader_total := -INF
	for k in karts:
		leader_total = maxf(leader_total, float(_prog[k].total))
	var player_total := float(_prog[player].total)
	for k in karts:
		if not k.has_meta("ai"):
			continue
		var gap := player_total - float(_prog[k].total)   # >0: AI behind the player
		var c := clampf((gap - 90.0) / 260.0, 0.0, 1.0) * (0.6 if rubber == 1 else 1.0)
		k.get_meta("ai").set("catchup", c)


func results() -> Array:
	var out: Array = []
	var order := karts.duplicate()
	order.sort_custom(func(a: Kart, b: Kart) -> bool: return int(_prog[a].pos) < int(_prog[b].pos))
	for k in order:
		var pr: Dictionary = _prog[k]
		var t: float = pr.finish_time if pr.finished else race_time + maxf(float(laps) * spine.length - float(pr.total), 0.0) / maxf(k.speed, 18.0)
		out.append({"name": k.display_name, "player": k.is_player, "time": t, "best": pr.best, "finished": pr.finished,
			"pos": pr.pos, "sparks": k.stat_sparks, "perfect": k.stat_perfect})
	return out
