class_name RaceManager
extends Node3D
## Runs races (8 cars), checkpoints, laps, positions, police and challenges.

signal message(text: String, color: Color, big: bool)
signal finished(results: Array, busted: bool)
signal state_changed(state: int)

enum { IDLE, COUNTDOWN, RACING, DONE }
const AI_NAMES_AR := ["ليث", "ريم", "سامر", "نور", "زياد", "هالة", "كريم", "مايا", "عمر", "لينا", "فارس", "جود"]
const AI_NAMES_EN := ["Laith", "Reem", "Samer", "Nour", "Ziad", "Hala", "Karim", "Maya", "Omar", "Lina", "Fares", "Jude"]
const PLAYER_SLOT := 5

var world: World
var state := IDLE
var event: Dictionary = {}
var route: RaceRoute
var cps: Array = []
var laps := 1
var racers: Array = []        # dicts
var time := 0.0
var countdown := 0.0
var _last_count := -1
var pursuit: Pursuit
var gates: Array[Node3D] = []
var markers := []             # [{node, event, pos}]
var player_entry: Dictionary = {}
var missed := false
var wrong_way_t := 0.0
var results_timer := -1.0
var busted := false
# challenges
var challenge := ""
var ch_time := 0.0
var ch_score := 0.0
var ch_combo := 1.0
var ch_drift_t := 0.0
var ch_best_jump := 0.0
var _jump_start := Vector3.ZERO
var _was_air := false
var speedtraps := []          # [{pos, dir, best}]
var _trap_prev := Vector3.ZERO
var gate_mat: ShaderMaterial
var finish_mat: ShaderMaterial


func setup(w: World) -> void:
	world = w
	pursuit = Pursuit.new()
	add_child(pursuit)
	pursuit.player_busted.connect(_on_busted)
	pursuit.racer_busted.connect(func(_c): message.emit(Game.t("racer_busted"), Color(0.5, 0.7, 1.0), false))
	pursuit.heat_changed.connect(func(h): if h == 1: message.emit(Game.t("pursuit"), Color(1, 0.3, 0.3), true))
	pursuit.evaded.connect(func(): message.emit(Game.t("evaded"), Color(0.4, 1, 0.5), true))
	gate_mat = ShaderMaterial.new()
	gate_mat.shader = load("res://shaders/gate.gdshader")
	finish_mat = ShaderMaterial.new()
	finish_mat.shader = load("res://shaders/gate.gdshader")
	finish_mat.set_shader_parameter("checker", true)
	_build_markers()


# --------------------------------------------------------------------------- markers
func _build_markers() -> void:
	var beam_mat := ShaderMaterial.new()
	beam_mat.shader = load("res://shaders/beam.gdshader")
	for e in world.data.events:
		var pos: Vector3
		var dir: Vector3
		var col := Color(1.0, 0.55, 0.1)
		if e.has("route"):
			var r := RaceRoute.from_event(e)
			var slot := _grid_slot(r, e, PLAYER_SLOT)
			pos = slot[0]
			dir = slot[1]
			if e.get("open", false):
				col = Color(1.0, 0.85, 0.2)
			elif e.kind == "circuit":
				col = Color(0.2, 0.75, 1.0)
		else:
			pos = Vector3(e.pos[0], e.pos[1], e.pos[2])
			dir = Vector3(e.dir[0], 0, e.dir[1])
			col = Color(0.75, 0.3, 1.0)
			if e.kind == "speedtrap":
				speedtraps.append({"pos": pos, "dir": dir.normalized(), "id": e.id})
				_trap_gantry(pos, dir.normalized())
				col = Color(1.0, 0.2, 0.3)
		var m := MeshInstance3D.new()
		var cyl := CylinderMesh.new()
		cyl.top_radius = 2.6
		cyl.bottom_radius = 2.6
		cyl.height = 60.0
		cyl.cap_top = false
		cyl.cap_bottom = false
		cyl.radial_segments = 24
		m.mesh = cyl
		var mat := beam_mat.duplicate() as ShaderMaterial
		mat.set_shader_parameter("color", col)
		m.material_override = mat
		m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(m)
		m.global_position = pos + Vector3(0, 30.0, 0)
		markers.append({"node": m, "event": e, "pos": pos, "dir": dir, "color": col})


func _trap_gantry(p: Vector3, d: Vector3) -> void:
	var m := MeshAcc.new()
	var r := d.cross(Vector3.UP).normalized()
	var basis := Basis.looking_at(d, Vector3.UP)
	for side: float in [-1.0, 1.0]:
		m.box(Transform3D(basis, p + r * side * 11.0 + Vector3(0, 3.5, 0)), Vector3(0.5, 7.0, 0.5))
	m.box(Transform3D(basis, p + Vector3(0, 7.0, 0)), Vector3(23.0, 0.6, 0.6))
	m.box(Transform3D(basis, p + Vector3(0, 6.4, 0)), Vector3(0.8, 0.6, 0.9))
	var mi := MeshInstance3D.new()
	mi.mesh = m.to_mesh(Mats.dark_metal())
	add_child(mi)


func marker_near(p: Vector3, radius := 10.0) -> Dictionary:
	for mk in markers:
		if mk.pos.distance_to(p) < radius and mk.event.kind != "speedtrap":
			return mk
	return {}


func set_markers_visible(v: bool) -> void:
	for mk in markers:
		mk.node.visible = v


# --------------------------------------------------------------------------- grid
func _grid_slot(r: RaceRoute, e: Dictionary, slot: int) -> Array:
	var front := 30.0
	if e.closed:
		front = r.length - 16.0
	var row := slot / 2
	var side := -1.0 if slot % 2 == 0 else 1.0
	var d := front - row * 9.0 - (4.0 if slot % 2 == 1 else 0.0)
	if not e.closed:
		d = maxf(d, 2.0)
	var i := r.index_at_distance(d)
	var w := r.widths[i]
	var lat := side * minf(w * 0.25, 3.2) if not r.is_open else side * 3.5
	return [r.pts[i] + r.rights[i] * lat, r.tangents[i]]


# --------------------------------------------------------------------------- race lifecycle
func start_event(e: Dictionary) -> void:
	end_event(false)
	event = e
	if not e.has("route"):
		_start_challenge(e)
		return
	route = RaceRoute.from_event(e)
	laps = int(e.get("laps", 1))
	cps = []
	for c in e.checkpoints:
		cps.append({"pos": Vector3(c.pos[0], c.pos[1], c.pos[2]), "dir": Vector3(c.dir[0], 0, c.dir[1]).normalized(),
			"width": float(c.width), "d": float(c.d)})
	var player: Car = Game.player
	var main = Game.main
	main.traffic.clear_all()
	main.traffic.enabled = e.get("traffic", true)
	main.traffic.route_points = route.pts
	SkidMarks.instance.clear_all()
	# racers
	racers.clear()
	var pool: Array = Game.PLAYER_CARS.duplicate()
	pool.erase(Game.selected_car)
	var names := AI_NAMES_AR if Game.settings.lang == "ar" else AI_NAMES_EN
	var order := range(names.size())
	order.shuffle()
	var diff: int = Game.settings.difficulty
	var base_skill: float = [0.84, 0.93, 1.0][diff]
	var ai_i := 0
	for slot in 8:
		var sl := _grid_slot(route, e, slot)
		var pos: Vector3 = sl[0]
		var dir: Vector3 = sl[1]
		var yaw := atan2(-dir.x, -dir.z)
		var car: Car
		var entry := {}
		if slot == PLAYER_SLOT:
			car = player
			entry = {"name": Game.t("you"), "is_player": true}
		else:
			var id: String = pool[randi() % pool.size()]
			var cols: Array = Game.CARS[id].colors
			car = Car.new()
			add_child(car)
			car.setup(id, cols[randi() % cols.size()], world, false)
			var lat_off := (route.rights[route.nearest_global(pos)]).dot(pos - route.pts[route.nearest_global(pos)])
			var ai := RacerAI.new(route, lat_off * 0.6, base_skill * randf_range(0.95, 1.04))
			ai.idx = route.nearest_global(pos)
			car.controller = ai
			car.set_meta("near_player", true)
			world.register_vehicle(car)
			main.traffic.physics_cars.append(car)
			entry = {"name": names[order[ai_i % names.size()]], "is_player": false}
			ai_i += 1
		car.place(pos, yaw)
		car.model.repair()
		car.damage = 0.0
		car.nitro = 1.0
		car.nitro_regen = false
		car.controls_locked = true
		entry["car"] = car
		entry["cp"] = 0
		entry["lap"] = 0
		entry["done"] = false
		entry["time"] = -1.0
		entry["prev"] = pos
		entry["progress"] = 0.0
		entry["idx"] = route.nearest_global(pos)
		entry["lap_start"] = 0.0
		entry["best_lap"] = -1.0
		racers.append(entry)
		if slot == PLAYER_SLOT:
			player_entry = entry
	# AI obstacle lists
	for r in racers:
		if not r.is_player:
			var obs := []
			for r2 in racers:
				if r2 != r:
					obs.append(r2.car)
			r.car.controller.obstacles = obs
	_refresh_ai_obstacles()
	time = 0.0
	countdown = 3.9
	_last_count = -1
	state = COUNTDOWN
	busted = false
	missed = false
	results_timer = -1.0
	set_markers_visible(false)
	_update_gates()
	state_changed.emit(state)
	if Game.camera:
		Game.camera.set_target(player)
	if e.get("open", false):
		message.emit(Game.t("open_race_tip"), Color(1, 0.9, 0.5), false)
	elif e.get("shortcuts", []).size() > 0:
		message.emit(Game.t("shortcut_tip"), Color(1, 0.9, 0.5), false)


func _refresh_ai_obstacles() -> void:
	var tm = Game.main.traffic
	for r in racers:
		if r.is_player:
			continue
		var obs: Array = []
		for r2 in racers:
			if r2 != r:
				obs.append(r2.car)
		obs.append_array(tm.cars)
		obs.append_array(pursuit.units)
		r.car.controller.obstacles = obs


func end_event(show := false) -> void:
	pursuit.stop()
	var main = Game.main
	for r in racers:
		if not r.is_player and is_instance_valid(r.car):
			world.unregister_vehicle(r.car)
			if main:
				main.traffic.physics_cars.erase(r.car)
			r.car.queue_free()
	racers.clear()
	for g in gates:
		g.queue_free()
	gates.clear()
	if Game.player:
		Game.player.controls_locked = false
		Game.player.nitro_regen = true
	if main:
		main.traffic.enabled = true
		main.traffic.route_points = PackedVector3Array()
	challenge = ""
	state = IDLE
	set_markers_visible(true)
	state_changed.emit(state)


func restart() -> void:
	var e := event
	if e.is_empty():
		return
	end_event()
	start_event(e)


# --------------------------------------------------------------------------- gates
func _update_gates() -> void:
	for g in gates:
		g.queue_free()
	gates.clear()
	if player_entry.is_empty() or player_entry.done:
		return
	var nxt: int = player_entry.cp
	var final_lap: bool = player_entry.lap >= laps - 1
	for k in 2:
		var i := nxt + k
		if i >= cps.size():
			if final_lap or route.closed == false:
				break
			i -= cps.size()
		var is_finish := i == cps.size() - 1 and final_lap
		gates.append(_make_gate(cps[i], is_finish, k == 0))


func _make_gate(cp: Dictionary, finish: bool, primary: bool) -> Node3D:
	var root := Node3D.new()
	add_child(root)
	var pos: Vector3 = cp.pos
	var dir: Vector3 = cp.dir
	var w: float = cp.width
	var basis := Basis.looking_at(dir, Vector3.UP)
	root.global_transform = Transform3D(basis, pos)
	var pillar := MeshAcc.new()
	for side: float in [-1.0, 1.0]:
		pillar.box(Transform3D(Basis(), Vector3(side * w * 0.5, 4.0, 0)), Vector3(0.6, 8.0, 0.6))
	var mi := MeshInstance3D.new()
	mi.mesh = pillar.to_mesh(Mats.std("gate_pillar", Color(0.1, 0.1, 0.12), 0.5, 0.4, Color(1.0, 0.45, 0.1), 1.5))
	root.add_child(mi)
	var banner := MeshInstance3D.new()
	var qm := QuadMesh.new()
	qm.size = Vector2(w, 7.0 if primary else 5.0)
	banner.mesh = qm
	banner.position = Vector3(0, 4.0, 0)
	banner.material_override = finish_mat if finish else gate_mat
	banner.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	banner.transparency = 0.0 if primary else 0.55
	root.add_child(banner)
	return root


# --------------------------------------------------------------------------- update
func _physics_process(dt: float) -> void:
	if challenge != "":
		_challenge_step(dt)
	_speedtraps()
	if state == IDLE:
		return
	if state == COUNTDOWN:
		countdown -= dt
		var c := int(ceil(countdown - 0.9))
		if c != _last_count and c >= 0 and c <= 3:
			_last_count = c
			if c > 0:
				message.emit(str(c), Color(1, 1, 1), true)
				Game.sfx.play_ui("beep:880", -4.0)
		if countdown <= 0.9:
			state = RACING
			state_changed.emit(state)
			message.emit(Game.t("go"), Color(0.4, 1.0, 0.4), true)
			Game.sfx.play_ui("beep:1320", -2.0)
			for r in racers:
				r.car.controls_locked = false
			if event.get("police", true) and Game.settings.police:
				var cars := []
				for r in racers:
					cars.append(r.car)
				pursuit.start(world, route, cars)
		return
	time += dt
	if Engine.get_physics_frames() % 30 == 0:
		_refresh_ai_obstacles()
	for r in racers:
		_track(r, dt)
	_rank()
	_player_warnings(dt)
	if results_timer >= 0.0:
		results_timer -= dt
		if results_timer < 0.0:
			_emit_results()


func _track(r: Dictionary, _dt: float) -> void:
	var car: Car = r.car
	if not is_instance_valid(car):
		return
	var cur := car.global_position
	r.idx = route.nearest(cur, r.idx, 8, 60)
	if r.done:
		r.prev = cur
		return
	var cp: Dictionary = cps[r.cp]
	var c: Vector3 = cp.pos
	var d: Vector3 = cp.dir
	var s0: float = (r.prev - c).dot(d)
	var s1: float = (cur - c).dot(d)
	if s0 < 0.0 and s1 >= 0.0:
		var mid: Vector3 = (r.prev + cur) * 0.5
		var right := d.cross(Vector3.UP)
		var lat := absf((mid - c).dot(right))
		if lat < float(cp.width) * 0.5 + 4.0 and absf(mid.y - c.y) < 16.0:
			_passed(r)
	r.prev = cur
	# progress estimate for ranking
	var to_next: float = cur.distance_to(cps[r.cp].pos)
	r.progress = (r.lap * cps.size() + r.cp) * 100000.0 - to_next


func _passed(r: Dictionary) -> void:
	r.cp += 1
	var last: bool = r.cp >= cps.size()
	if last:
		r.lap += 1
		var lt: float = time - r.lap_start
		r.lap_start = time
		if r.best_lap < 0.0 or lt < r.best_lap:
			r.best_lap = lt
		if r.lap >= laps:
			r.done = true
			r.time = time
			if r.is_player:
				_player_finished()
			else:
				r.car.controller.cruise = true
		else:
			r.cp = 0
			if r.is_player:
				message.emit(Game.t("final_lap") if r.lap == laps - 1 else "%s %d/%d" % [Game.t("lap"), r.lap + 1, laps], Color(1, 0.85, 0.3), true)
	if r.is_player:
		if not r.done:
			Game.sfx.play_ui("chime", -4.0)
			message.emit(Game.t("checkpoint") + "  " + Game.format_time(time), Color(0.5, 0.9, 1.0), false)
		missed = false
		_update_gates()


func _rank() -> void:
	var sorted := racers.duplicate()
	sorted.sort_custom(func(a, b):
		if a.done and b.done:
			return a.time < b.time
		if a.done != b.done:
			return a.done
		return a.progress > b.progress)
	for i in sorted.size():
		sorted[i]["pos"] = i + 1
	# rubber band (mild)
	for r in racers:
		if r.is_player or r.done:
			continue
		var ai: RacerAI = r.car.controller
		var diff: float = (r.progress - player_entry.progress) / 100000.0 * 1000.0
		ai.rubber = clampf(1.0 - diff / 4000.0, 0.94, 1.07)


func _player_warnings(dt: float) -> void:
	if player_entry.is_empty() or player_entry.done:
		return
	var car: Car = player_entry.car
	var pi: int = player_entry.idx
	var dproj := route.dist[pi]
	var cpd: float = cps[player_entry.cp].d
	var delta := dproj - cpd
	if route.closed:
		delta = wrapf(delta, -route.length * 0.5, route.length * 0.5)
	if delta > 90.0 and car.global_position.distance_to(cps[player_entry.cp].pos) > 60.0:
		if not missed:
			missed = true
			message.emit(Game.t("missed_cp"), Color(1, 0.35, 0.3), true)
	var t := route.tangents[pi]
	if car.speed_abs > 8.0 and car.linear_velocity.normalized().dot(t) < -0.5 and not route.is_open:
		wrong_way_t += dt
	else:
		wrong_way_t = 0.0


func is_wrong_way() -> bool:
	return wrong_way_t > 2.0


func _player_finished() -> void:
	state = DONE
	results_timer = 4.0
	message.emit(Game.t("finished"), Color(1, 0.85, 0.2), true)
	if Game.camera:
		Game.camera.slowmo(0.35, 1.2)
	pursuit.stop()
	for g in gates:
		g.queue_free()
	gates.clear()
	var pos: int = player_entry.get("pos", 8)
	Game.stats.races = int(Game.stats.races) + 1
	if pos == 1:
		Game.stats.races_won = int(Game.stats.races_won) + 1
	var best: float = Game.best_times.get(event.id, -1.0)
	if best < 0.0 or player_entry.time < best:
		Game.best_times[event.id] = player_entry.time
		message.emit(Game.t("new_record"), Color(0.4, 1.0, 0.5), false)
	Game.save_game()


func _on_busted() -> void:
	busted = true
	state = DONE
	Game.stats.busted = int(Game.stats.busted) + 1
	message.emit(Game.t("busted"), Color(1, 0.2, 0.2), true)
	player_entry.car.controls_locked = true
	results_timer = 3.0


func _emit_results() -> void:
	var list := []
	var sorted := racers.duplicate()
	sorted.sort_custom(func(a, b): return a.get("pos", 9) < b.get("pos", 9))
	for r in sorted:
		var t: float = r.time
		if not r.done and not r.is_player and r.car.controller and r.car.controller.active:
			# estimate a finish time from the remaining distance
			var remain := 0.0
			for k in range(r.cp, cps.size()):
				remain += 1.0
			remain += (laps - 1 - r.lap) * cps.size()
			t = time + remain * 1000.0 / maxf(r.car.speed_abs, 25.0)
		list.append({"name": r.name, "car": r.car.display_name, "time": t, "player": r.is_player,
			"dnf": (r.is_player and busted) or (not r.is_player and r.car.controller and not r.car.controller.active)})
	finished.emit(list, busted)


func player_position() -> int:
	return player_entry.get("pos", 0)


func next_checkpoint_pos() -> Vector3:
	if player_entry.is_empty() or player_entry.done:
		return Vector3.INF
	return cps[player_entry.cp].pos


# --------------------------------------------------------------------------- challenges
func _start_challenge(e: Dictionary) -> void:
	challenge = e.kind
	ch_time = 60.0 if e.kind == "drift" else 90.0
	ch_score = 0.0
	ch_combo = 1.0
	ch_best_jump = 0.0
	ch_drift_t = 0.0
	_was_air = false
	state = IDLE
	set_markers_visible(false)
	var desc: String = e.desc_ar if Game.settings.lang == "ar" else e.desc_en
	message.emit(desc, Color(0.85, 0.6, 1.0), false)
	Game.player.nitro = 1.0
	state_changed.emit(state)


func _challenge_step(dt: float) -> void:
	var car: Car = Game.player
	if car == null:
		return
	ch_time -= dt
	if challenge == "drift":
		var ang := absf(car.drift_angle)
		if ang > deg_to_rad(10.0) and car.speed_abs > 10.0 and car.grounded >= 2:
			ch_drift_t += dt
			ch_combo = minf(1.0 + ch_drift_t * 0.5, 5.0)
			ch_score += car.speed_abs * rad_to_deg(minf(ang, 1.2)) * dt * 1.5 * ch_combo
		else:
			ch_drift_t = maxf(ch_drift_t - dt * 2.0, 0.0)
			if ch_drift_t <= 0.0:
				ch_combo = 1.0
	elif challenge == "jump":
		var air := car.grounded == 0
		if air and not _was_air:
			_jump_start = car.global_position
		elif not air and _was_air and car.last_air_time > 0.4:
			var d := Vector2(car.global_position.x - _jump_start.x, car.global_position.z - _jump_start.z).length()
			if d > ch_best_jump:
				ch_best_jump = d
				message.emit("%s: %.1f m" % [Game.t("jump_dist"), d], Color(0.6, 1.0, 0.6), true)
		_was_air = air
		ch_score = ch_best_jump
	if ch_time <= 0.0:
		var id: String = event.id
		var best: float = Game.best_times.get(id, 0.0)
		var rec := ch_score > best
		if rec:
			Game.best_times[id] = ch_score
			Game.save_game()
		message.emit("%s  %s: %d%s" % [Game.t("challenge_done"), Game.t("score"), int(ch_score), ("  " + Game.t("new_record")) if rec else ""], Color(0.85, 0.6, 1.0), true)
		challenge = ""
		set_markers_visible(true)


func _speedtraps() -> void:
	var car: Car = Game.player
	if car == null:
		return
	var p := car.global_position
	for tr in speedtraps:
		var c: Vector3 = tr.pos
		if c.distance_to(p) > 30.0:
			continue
		var d: Vector3 = tr.dir
		var s0 := (_trap_prev - c).dot(d)
		var s1 := (p - c).dot(d)
		if signf(s0) != signf(s1) and absf((p - c).dot(d.cross(Vector3.UP))) < 12.0:
			var kmh := car.kmh()
			var best: float = Game.best_times.get(tr.id, 0.0)
			var rec := kmh > best
			if rec:
				Game.best_times[tr.id] = kmh
				Game.save_game()
			message.emit("%s: %s %s%s" % [Game.t("speedtrap"), Game.speed_text(car.speed_abs), Game.speed_unit(), ("  " + Game.t("new_record")) if rec else ""], Color(1, 0.4, 0.4), true)
	_trap_prev = p
