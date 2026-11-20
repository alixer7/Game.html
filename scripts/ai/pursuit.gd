class_name Pursuit
extends Node
## Police pursuit during races: heat levels, spawning interceptors and roadblocks,
## busted / evaded logic (for the player and for AI racers).

signal player_busted
signal racer_busted(car: Car)
signal heat_changed(level: int)
signal evaded

var world: World
var route: RaceRoute
var units: Array[Car] = []
var heat := 0
var active := false
var time := 0.0
var bust_meter := 0.0         # 0..1 for the player
var evade_t := 0.0
var cooldown := 0.0
var racers: Array = []        # Car list including the player
var spawn_cd := 0.0
var roadblock_done := false
var racer_bust := {}


func start(w: World, r: RaceRoute, all_racers: Array) -> void:
	world = w
	route = r
	racers = all_racers
	active = true
	time = 0.0
	heat = 0
	bust_meter = 0.0
	evade_t = 0.0
	cooldown = 0.0
	spawn_cd = 30.0
	roadblock_done = false
	racer_bust.clear()


func stop() -> void:
	active = false
	for u in units:
		if is_instance_valid(u):
			world.unregister_vehicle(u)
			u.queue_free()
	units.clear()
	heat = 0
	bust_meter = 0.0


func max_units() -> int:
	return [0, 1, 2, 4][clampi(heat, 0, 3)]


func _physics_process(dt: float) -> void:
	if not active:
		return
	time += dt
	var player: Car = Game.player
	if player == null:
		return
	# heat escalates with time and when the player hits police cars
	var new_heat := 1
	if time > 70.0:
		new_heat = 2
	if time > 150.0:
		new_heat = 3
	if new_heat > heat:
		heat = new_heat
		heat_changed.emit(heat)
	cooldown = maxf(cooldown - dt, 0.0)
	spawn_cd -= dt
	units = units.filter(func(u): return is_instance_valid(u))
	if cooldown <= 0.0 and spawn_cd <= 0.0 and units.size() < max_units():
		spawn_cd = 9.0
		_spawn_unit(player)
	if heat >= 3 and not roadblock_done:
		roadblock_done = true
		_roadblock(player)
	# target selection: chase whoever is nearest (player preferred)
	for u in units:
		var ai: PoliceAI = u.controller
		if ai.roadblock:
			continue
		var best: Car = player
		var bd := u.global_position.distance_to(player.global_position) * 0.8
		for r in racers:
			if is_instance_valid(r) and r != player and r.controller and r.controller.active:
				var d := u.global_position.distance_to(r.global_position)
				if d < bd:
					bd = d
					best = r
		ai.target = best
		# despawn units left far behind
		if u.global_position.distance_to(player.global_position) > 650.0:
			_remove(u)
	# busted logic for the player
	var near := 0
	var closest := 1e9
	for u in units:
		var d := u.global_position.distance_to(player.global_position)
		closest = minf(closest, d)
		if d < 11.0:
			near += 1
	if near > 0 and player.speed_abs < 3.0:
		bust_meter = minf(bust_meter + dt / (4.0 if near == 1 else 2.5), 1.0)
	else:
		bust_meter = maxf(bust_meter - dt * 0.6, 0.0)
	if bust_meter >= 1.0:
		active = false
		player_busted.emit()
		return
	# racers can be busted too
	for r in racers:
		if not is_instance_valid(r) or r == player or r.controller == null or not r.controller.active:
			continue
		var close := false
		for u in units:
			if u.global_position.distance_to(r.global_position) < 10.0:
				close = true
		var v: float = racer_bust.get(r, 0.0)
		v = v + dt if close and r.speed_abs < 3.0 else maxf(v - dt, 0.0)
		racer_bust[r] = v
		if v > 4.0:
			r.controller.active = false
			racer_busted.emit(r)
	# evading
	if units.size() > 0 and closest > 320.0:
		evade_t += dt
		if evade_t > 10.0:
			evade_t = 0.0
			for u in units.duplicate():
				_remove(u)
			cooldown = 35.0
			evaded.emit()
	else:
		evade_t = 0.0


func _spawn_unit(player: Car) -> void:
	if route == null:
		return
	var pi := route.nearest_global(player.global_position)
	# spawn behind (chase) or ahead (intercept), out of immediate sight
	var ahead := randf() < 0.3
	var off := randf_range(170.0, 240.0) * (1.0 if ahead else -1.0)
	var si := route.advance(pi, off)
	var p := route.pts[si]
	var t := route.tangents[si]
	if ahead:
		t = -t   # face the oncoming racers
	var c := _make_car()
	var lane := randf_range(-2.5, 2.5)
	c.place(p + route.rights[si] * lane + Vector3(0, 0.6, 0), atan2(-t.x, -t.z))
	c.linear_velocity = t * (20.0 if not ahead else 5.0)
	var ai := PoliceAI.new(route, player)
	ai.idx = si
	ai.aggression = [0.6, 0.6, 0.85, 1.1][clampi(heat, 0, 3)]
	c.controller = ai
	units.append(c)


func _roadblock(player: Car) -> void:
	var pi := route.nearest_global(player.global_position)
	var si := route.advance(pi, 520.0)
	var p := route.pts[si]
	var t := route.tangents[si]
	var r := route.rights[si]
	var w := route.widths[si]
	for k in 2:
		var c := _make_car()
		var side := -1.0 if k == 0 else 1.0
		var pos := p + r * side * (w * 0.25) + Vector3(0, 0.5, 0)
		# parked across the road, leaving a gap in the middle
		c.place(pos, atan2(-r.x, -r.z) + (0.25 if k == 0 else -0.25))
		var ai := PoliceAI.new(route, player)
		ai.roadblock = true
		c.controller = ai
		units.append(c)


func _make_car() -> Car:
	var c := Car.new()
	add_child(c)
	c.setup("police", Color(0.05, 0.05, 0.06), world, false)
	c.nitro_regen = false
	c.set_meta("near_player", true)
	world.register_vehicle(c)
	if Game.main and Game.main.traffic:
		Game.main.traffic.physics_cars.append(c)
	return c


func _remove(u: Car) -> void:
	units.erase(u)
	if is_instance_valid(u):
		world.unregister_vehicle(u)
		if Game.main and Game.main.traffic:
			Game.main.traffic.physics_cars.erase(u)
		u.queue_free()


func _process(_d: float) -> void:
	var t := Time.get_ticks_msec() * 0.001
	for u in units:
		if is_instance_valid(u):
			u.model.set_siren(t + u.get_instance_id() % 7 * 0.13, true)
