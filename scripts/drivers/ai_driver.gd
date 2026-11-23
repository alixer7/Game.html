class_name AIDriver
extends Node
## AI racer: follows racing lines over a lane graph, chooses routes per lap
## according to skill and kart state, power-slides with spark taps whose
## accuracy depends on skill, hops at lips, hook-turns hairpins, avoids
## obstacles, recovers when stuck, and uses items.

const PROFILES := [
	{"name": "Easy", "drift_use": 0.35, "tap_skill": 0.45, "perfect": 0.08, "steer_noise": 0.12, "line_noise": 1.6, "margin": 0.84,
		"short": {"left_bank": 0.35, "right_bank": 0.35, "giants_log": 0.0, "shelf_rock": 0.0, "millrace_flume": 0.0, "rootway_cave": 0.05, "gate_lane": 0.5}, "react": 0.35, "item_iq": 0.3, "hook": false, "lip_hop": false},
	{"name": "Normal", "drift_use": 0.75, "tap_skill": 0.78, "perfect": 0.3, "steer_noise": 0.07, "line_noise": 1.0, "margin": 0.92,
		"short": {"left_bank": 0.45, "right_bank": 0.25, "giants_log": 0.35, "shelf_rock": 0.0, "millrace_flume": 0.15, "rootway_cave": 0.25, "gate_lane": 0.8}, "react": 0.22, "item_iq": 0.6, "hook": false, "lip_hop": false},
	{"name": "Hard", "drift_use": 0.92, "tap_skill": 0.93, "perfect": 0.55, "steer_noise": 0.04, "line_noise": 0.55, "margin": 0.97,
		"short": {"left_bank": 0.55, "right_bank": 0.15, "giants_log": 0.75, "shelf_rock": 0.35, "millrace_flume": 0.55, "rootway_cave": 0.5, "gate_lane": 0.9}, "react": 0.15, "item_iq": 0.8, "hook": true, "lip_hop": true},
	{"name": "Expert", "drift_use": 1.0, "tap_skill": 0.98, "perfect": 0.82, "steer_noise": 0.02, "line_noise": 0.3, "margin": 1.0,
		"short": {"left_bank": 0.65, "right_bank": 0.05, "giants_log": 0.95, "shelf_rock": 0.7, "millrace_flume": 0.85, "rootway_cave": 0.7, "gate_lane": 1.0}, "react": 0.1, "item_iq": 0.95, "hook": true, "lip_hop": true},
]

var kart: Kart
var lanes: Dictionary          # id -> {line, entry_lane, entry_i, exit_lane, exit_i}
var profile: Dictionary
var obstacles: Array = []
var items: Node
var race: Node
var forced_route := {}         # tests: branch id -> bool
var catchup := 0.0             # set by race manager (0..1)

var lane := "main"
var idx := 0
var _decided := {}             # branch -> bool for this lap
var _decided_lap := -1
var _rng := RandomNumberGenerator.new()
var _noise_t := 0.0
var _line_off := 0.0
var _line_off_target := 0.0
var _drift_plan := false
var _drift_decided := false
var _drift_cool := 0.0
var _stuck_sample_t := 0.0
var _lost_t := 0.0
var _best_prog := -1
var _best_prog_lane := ""
var _prog_t := 0.0
var _stuck_last_pos := Vector3.ZERO
var _tap_target := 0.8
var _stuck_t := 0.0
var _reverse_t := 0.0
var _hop_cool := 0.0
var _item_think := 0.0
var _base_speed := 0.0
var lap := 0
var dbg := {}


func setup(k: Kart, lane_graph: Dictionary, prof_index: int, obs: Array, seed: int) -> void:
	kart = k
	lanes = lane_graph
	profile = PROFILES[clampi(prof_index, 0, PROFILES.size() - 1)]
	obstacles = obs
	_rng.seed = seed
	_base_speed = kart.params.max_speed
	_new_tap_target()
	idx = _nearest_on(lane, kart.global_position, 0, true)


func _line(id: String) -> RacingLine:
	return lanes[id]["line"]


func _nearest_on(id: String, p: Vector3, from: int, full := false) -> int:
	var rl := _line(id)
	var n := rl.size()
	var best := from
	var best_d := INF
	if full:
		for i in n:
			var d := rl.pts[i].distance_squared_to(p)
			if d < best_d:
				best_d = d
				best = i
		return best
	for k in range(-6, 40):
		var i := from + k
		if rl.closed:
			i = (i + n) % n
		elif i < 0 or i >= n:
			continue
		var q := rl.pts[i]
		var d := Vector2(q.x - p.x, q.z - p.z).length_squared() + pow(q.y - p.y, 2.0) * 0.3
		if d < best_d:
			best_d = d
			best = i
	return best


func _new_tap_target() -> void:
	var p := kart.params
	if _rng.randf() < profile.perfect:
		_tap_target = _rng.randf_range(p.perfect_zone + 0.01, 0.99)
	elif _rng.randf() < profile.tap_skill:
		_tap_target = _rng.randf_range(p.hot_zone + 0.02, p.perfect_zone)
	elif _rng.randf() < 0.5:
		_tap_target = _rng.randf_range(0.45, p.hot_zone - 0.05)   # too early: fizzle
	else:
		_tap_target = 9.0   # never taps: backfire


func _decide_branches() -> void:
	_decided.clear()
	_decided_lap = lap
	var short: Dictionary = profile.short
	for id in lanes:
		if id == "main":
			continue
		var pr: float = short.get(id, 0.0)
		if forced_route.has(id):
			_decided[id] = forced_route[id]
		else:
			_decided[id] = _rng.randf() < pr
	# never commit to both river banks
	if _decided.get("left_bank", false) and _decided.get("right_bank", false):
		_decided["right_bank"] = false


func _branch_conditions_ok(id: String) -> bool:
	match id:
		"giants_log":
			return kart.speed > 23.5 or kart.reserve > 0.4 or profile.lip_hop
		"shelf_rock":
			return kart.tier >= 2 or kart.speed > 29.0
		"millrace_flume":
			return kart.tier >= 2 or kart.speed > 30.5
		"gate_lane":
			for g in get_tree().get_nodes_in_group("breakables"):
				if g.get("broken"):
					return true
			return false
	return true


func _physics_process(dt: float) -> void:
	if kart == null or kart.frozen:
		if kart:
			kart.in_throttle = 0.0
		return
	if _decided_lap != lap:
		_decide_branches()
	_noise_t += dt
	_hop_cool = maxf(_hop_cool - dt, 0.0)
	var p := kart.global_position
	idx = _nearest_on(lane, p, idx)
	var rl := _line(lane)
	var n := rl.size()
	# ---- lane transitions
	if lane == "main" or lanes.has(lane):
		for id in lanes:
			if id == lane or id == "main":
				continue
			var ln: Dictionary = lanes[id]
			if ln.entry_lane != lane:
				continue
			var ei: int = ln.entry_i
			var ahead := _index_dist(lane, idx, ei)
			if ahead >= 0 and ahead < int(24.0 / rl.path.spacing) and _decided.get(id, false) and _branch_conditions_ok(id):
				lane = id
				idx = 0
				rl = _line(lane)
				n = rl.size()
				break
	if lane != "main" and idx < 4 and not rl.closed:
		var entry_pt := rl.pts[mini(4, n - 1)]
		var to_entry := entry_pt - p
		to_entry.y = 0
		if to_entry.length() > 5.0 and to_entry.dot(kart.heading()) < 0.0:
			lane = String(lanes[lane].entry_lane)   # missed the entrance: carry on
			idx = _nearest_on(lane, p, 0, true)
			rl = _line(lane)
			n = rl.size()
	if lane != "main" and not rl.closed and idx >= n - 3:
		var ln2: Dictionary = lanes[lane]
		lane = ln2.exit_lane
		idx = ln2.exit_i
		rl = _line(lane)
		n = rl.size()
	# ---- lookahead target
	var spd := kart.speed
	var look_m := 5.0 + spd * 0.42
	var li := _advance(lane, idx, int(look_m / rl.path.spacing))
	var target := _point(li)
	# smooth lateral wander (line noise) + obstacle / kart avoidance
	if _rng.randf() < dt * 0.4:
		_line_off_target = _rng.randf_range(-1.0, 1.0) * float(profile.line_noise)
	_line_off = lerpf(_line_off, _line_off_target, dt * 0.8)
	var right_at := _right_at(li)
	var avoid := _avoidance(p, target)
	target += right_at * (_line_off * 0.5 + avoid)
	# ---- steering (pure pursuit)
	var h := kart.heading()
	var to := target - p
	to.y = 0.0
	var ang := h.signed_angle_to(to.normalized(), Vector3.UP) if to.length() > 0.5 else 0.0
	var steer := clampf(-ang * 2.4, -1.0, 1.0)
	steer += sin(_noise_t * 3.1 + float(kart.racer_index)) * float(profile.steer_noise)
	# ---- corner analysis ahead
	var near_i := _advance(lane, idx, int(10.0 / rl.path.spacing))
	var r_near := _radius(near_i)
	# ---- speed control
	var v_target := minf(_speed(near_i), _speed(_advance(lane, idx, int((spd * 0.6) / rl.path.spacing)))) * float(profile.margin)
	if kart.tier > 0:
		v_target *= 1.15
	var throttle := 1.0
	var brake := 0.0
	if spd > v_target + 2.5 and not kart.drifting:
		throttle = 0.0
		if spd > v_target + 6.0:
			brake = 0.6
	# ---- power slides: decided from the total turn ahead, like a player reads a corner
	var turn_ahead := _turn_ahead(lane, idx, 50.0)     # signed radians, + = left
	var turn_near := _turn_ahead(lane, idx, 16.0)
	# rotation rate the corner asks for; a slide can't rotate slower than ~0.5 rad/s
	var need_start := absf(turn_ahead) / (50.0 / maxf(spd, 10.0))
	var corner_dir := 0
	if absf(turn_ahead) > deg_to_rad(24.0) and need_start >= 0.36:
		corner_dir = -1 if turn_ahead > 0.0 else 1
	_drift_cool = maxf(_drift_cool - dt, 0.0)
	var drift := false
	if not kart.drifting:
		if corner_dir == 0:
			_drift_decided = false
		elif spd > 15.0 and _drift_cool <= 0.0 and (kart.grounded or kart.in_drift):
			if not _drift_decided:
				_drift_decided = true
				_drift_plan = _rng.randf() < float(profile.drift_use)
				_new_tap_target()
			if _drift_plan:
				drift = true
				steer = float(corner_dir)   # commit the slide direction through the hop
	else:
		drift = true
		var dd := float(kart.drift_dir)
		var t_near := maxf(16.0 / maxf(spd, 5.0), 0.2)
		var need := absf(turn_near) / t_near
		var into := clampf((need - kart.params.drift_base_rate) / kart.params.drift_steer_range, -1.0, 1.0)
		# steer on the travel direction: a sliding chassis points ~30 deg inside it
		var hv := Vector3(kart.velocity.x, 0, kart.velocity.z)
		var ang_v := hv.signed_angle_to(to.normalized(), Vector3.UP) if hv.length() > 1.0 and to.length() > 0.5 else ang
		var err := clampf(-ang_v * 2.5 * dd, -0.8, 0.8)
		into = clampf(into + err, -1.0, 1.0)
		steer = into * dd
		dbg = {"turn_near": rad_to_deg(turn_near), "need": need, "into": into, "ang_v": rad_to_deg(ang_v), "err": err}
		# end the slide when the corner runs out, reverses, or the nose gets ahead of it
		var remaining := turn_near * -dd    # >0 while still turning the slide's way
		var over_rotating := ang_v * dd > deg_to_rad(22.0)
		if (remaining < deg_to_rad(5.0) and absf(ang_v) < 0.3) or over_rotating or (need < 0.3 and kart.drift_time > 0.5):
			drift = false
			_drift_cool = 0.35
			_drift_decided = false
		# hook turn when even a full slide can't rotate fast enough
		if profile.hook and need > kart.params.drift_base_rate + kart.params.drift_steer_range * 0.95 and spd > 14.0:
			brake = 1.0
			steer = dd
		if kart.drift_stage < 3 and kart.drift_charge >= _tap_target:
			kart.in_boost = true
			_new_tap_target()
	# ---- lip hops (gain hang time for air boosts / clear gaps)
	if profile.lip_hop and _hop_cool <= 0.0 and kart.grounded and not kart.drifting:
		var lip_i := _advance(lane, idx, maxi(int((spd * 0.09) / rl.path.spacing), 1))
		var tag := _tag(lip_i)
		if tag.ends_with("lip"):
			drift = true
			steer = 0.0 if absf(steer) < 0.35 else steer
			_hop_cool = 1.0
	# ---- stuck recovery (measured by real displacement, not reported speed)
	_stuck_sample_t += dt
	if _stuck_sample_t >= 1.0:
		_stuck_sample_t = 0.0
		var moved := p.distance_to(_stuck_last_pos)
		_stuck_last_pos = p
		if moved < 1.2 and kart.spin_time <= 0.0:
			_stuck_t += 1.0
		else:
			_stuck_t = 0.0
	if _stuck_t >= 2.0 and _reverse_t <= 0.0 and _stuck_t < 4.0:
		_reverse_t = 1.1
	# lost: far from the lane for a while (fell off a shortcut, spun into the forest)
	var line_pt := _line(lane).pts[idx]
	if Vector2(line_pt.x - p.x, line_pt.z - p.z).length() > 9.0 or absf(line_pt.y - p.y) > 4.0:
		_lost_t += dt
	else:
		_lost_t = maxf(_lost_t - dt, 0.0)
	if _lost_t > 4.0:
		_stuck_t = 4.0
		_lost_t = 0.0
	# progress watchdog: the furthest lane index must keep advancing
	if lane != _best_prog_lane:
		_best_prog_lane = lane
		_best_prog = idx
		_prog_t = 0.0
	elif idx > _best_prog or (rl.closed and idx < _best_prog - n / 2):
		_best_prog = idx
		_prog_t = 0.0
	else:
		_prog_t += dt
	if _prog_t > 5.0:
		_prog_t = 0.0
		_stuck_t = 4.0
	if _stuck_t >= 4.0 and race:
		race.call("respawn_kart", kart)
		_stuck_t = 0.0
		_reverse_t = 0.0
		lane = "main"
		idx = _nearest_on("main", kart.global_position, 0, true)
	if _reverse_t > 0.0:
		_reverse_t -= dt
		throttle = 0.0
		brake = 1.0
		steer = -steer
		drift = false
	# ---- gentle catch-up (bounded, see DESIGN_BIBLE "Rubber banding")
	kart.params.max_speed = _base_speed * (1.0 + catchup * 0.03)
	kart.in_steer = clampf(steer, -1.0, 1.0)
	kart.in_throttle = throttle
	kart.in_brake = brake
	kart.in_drift = drift
	_items(dt)


func _index_dist(id: String, from: int, to: int) -> int:
	var rl := _line(id)
	if rl.closed:
		var n := rl.size()
		var d := (to - from + n) % n
		return d if d < n / 2 else -1
	return to - from


func _advance(id: String, from: int, steps: int) -> Dictionary:
	## Returns {"lane", "i"} following exits onto the next lane.
	var cur := id
	var i := from + steps
	var guard := 0
	while guard < 4:
		guard += 1
		var rl := _line(cur)
		var n := rl.size()
		if rl.closed:
			return {"lane": cur, "i": (i % n + n) % n}
		if i < n:
			return {"lane": cur, "i": maxi(i, 0)}
		var over := i - (n - 1)
		var ln: Dictionary = lanes[cur]
		cur = ln.exit_lane
		i = int(ln.exit_i) + over
	return {"lane": cur, "i": 0}


func _point(li: Dictionary) -> Vector3:
	return _line(li.lane).pts[li.i]


func _right_at(li: Dictionary) -> Vector3:
	return _line(li.lane).path.right[li.i]


func _dir_at(li: Dictionary) -> Vector3:
	var rl := _line(li.lane)
	var i: int = li.i
	var n := rl.size()
	var j := (i + 2) % n if rl.closed else mini(i + 2, n - 1)
	var k := i if j != i else maxi(i - 2, 0)
	var d := rl.pts[j] - rl.pts[k]
	d.y = 0.0
	return d.normalized() if d.length_squared() > 1e-6 else Vector3.FORWARD


func _turn_ahead(id: String, from: int, meters: float) -> float:
	var steps := maxi(int(meters / _line(id).path.spacing), 1)
	var a := _dir_at({"lane": id, "i": from})
	var b := _dir_at(_advance(id, from, steps))
	return a.signed_angle_to(b, Vector3.UP)


func _radius(li: Dictionary) -> float:
	return _line(li.lane).radius[li.i]


func _speed(li: Dictionary) -> float:
	return _line(li.lane).speed[li.i]


func _tag(li: Dictionary) -> String:
	return _line(li.lane).path.tags[li.i]


func _avoidance(p: Vector3, target: Vector3) -> float:
	var fwd := (target - p)
	fwd.y = 0
	var dist := fwd.length()
	if dist < 0.5:
		return 0.0
	fwd /= dist
	var right := fwd.cross(Vector3.UP)
	var shift := 0.0
	for o in obstacles:
		var c: Vector3 = o[0]
		var r: float = o[1]
		var rel := c - p
		rel.y = 0
		var along := rel.dot(fwd)
		if along < 1.0 or along > 22.0:
			continue
		var lat := rel.dot(right)
		var clear := r + 1.5
		if absf(lat) < clear:
			shift += (-1.0 if lat > 0.0 else 1.0) * (clear - absf(lat)) * (1.0 - along / 24.0)
	if race:
		for other in race.get("karts"):
			if other == kart:
				continue
			var rel := (other as Kart).global_position - p
			rel.y = 0
			var along := rel.dot(fwd)
			if along < 0.5 or along > 10.0:
				continue
			var lat := rel.dot(right)
			if absf(lat) < 1.8:
				shift += (-1.0 if lat > 0.0 else 1.0) * (1.8 - absf(lat)) * 0.8
	return clampf(shift, -4.0, 4.0)


func _items(dt: float) -> void:
	if items == null:
		return
	_item_think -= dt
	if _item_think > 0.0:
		return
	_item_think = float(profile.react) + _rng.randf() * 0.3
	var it: String = items.call("item_of", kart)
	if it == "":
		return
	if _rng.randf() > float(profile.item_iq) and _rng.randf() < 0.5:
		kart.in_item = true   # careless use
		return
	var pos: int = race.call("position_of", kart) if race else 1
	match it:
		"spark":
			if kart.grounded and kart.tier == 0:
				kart.in_item = true
		"shield":
			kart.in_item = true
		"trap":
			if pos == 1 or race.call("kart_behind_within", kart, 25.0):
				kart.in_item = true
		"bomb":
			if race.call("kart_ahead_within", kart, 30.0, 0.35):
				kart.in_item = true
		"hornet":
			if pos > 1:
				kart.in_item = true
