class_name TrafficManager
extends Node3D
## Keeps a population of civilian cars on the roads around the player
## (and biased ahead of the player along the race route during races).

var world: World
var cars: Array[TrafficCar] = []
var pool: Array[TrafficCar] = []
var max_cars := 26
var enabled := true
var route_points: PackedVector3Array = PackedVector3Array()   # race route bias
var physics_cars: Array = []                                   # racers / police / player
var horn: AudioStreamPlayer3D
var _spawn_cd := 0.0
var _kinds := ["t_sedan", "t_sedan", "t_hatch", "t_hatch", "t_suv", "t_van", "t_pickup", "t_taxi", "t_truck"]


func setup(w: World) -> void:
	world = w
	horn = AudioStreamPlayer3D.new()
	horn.stream = Game.sfx.get_sound("horn")
	horn.unit_size = 14.0
	add_child(horn)
	apply_density()


func apply_density() -> void:
	var dens: float = Game.settings.traffic_density
	var q: int = Game.settings.quality
	max_cars = int(round(lerpf(0.0, 34.0 if q >= 2 else 24.0, dens)))
	if Game.race and Game.race.state != RaceManager.IDLE:
		max_cars = int(max_cars * 0.75)


func lane_offset(rd: Dictionary, lane_idx: int) -> float:
	match rd.type:
		"highway":
			return 3.4 if lane_idx == 0 else 6.9
		"avenue":
			return 1.95 if lane_idx == 0 else 5.4
		"street":
			return 3.0
		"country":
			return 2.5
		"mountain":
			return 2.4
		"cobble":
			return 2.0
	return 2.5


func road_speed(rd: Dictionary) -> float:
	match rd.type:
		"highway":
			return 27.0
		"avenue":
			return 15.0
		"street":
			return 12.0
		"country":
			return 19.0
		"mountain":
			return 13.0
		"cobble":
			return 8.0
	return 12.0


func honk(c: TrafficCar) -> void:
	if horn.playing:
		return
	horn.global_position = c.global_position
	horn.pitch_scale = randf_range(0.9, 1.15)
	horn.play()


func clear_all() -> void:
	for c in cars:
		_recycle(c)
	cars.clear()


func clear_near(p: Vector3, radius: float) -> void:
	for c in cars.duplicate():
		if c.global_position.distance_to(p) < radius:
			cars.erase(c)
			_recycle(c)


func _recycle(c: TrafficCar) -> void:
	if world:
		world.unregister_vehicle(c)
	c.visible = false
	c.freeze = true
	c.global_position = Vector3(0, -2000, 0)
	if not pool.has(c):
		pool.append(c)


func _get_car() -> TrafficCar:
	var kind: String = _kinds[randi() % _kinds.size()]
	# reuse a pooled car of any kind (keeps allocations low)
	if pool.size() > 0 and pool.size() > 6:
		return pool.pop_back()
	if pool.size() > 0 and randf() < 0.7:
		return pool.pop_back()
	var c := TrafficCar.new()
	add_child(c)
	var spec: Dictionary = Game.TRAFFIC[kind]
	var cols: Array = spec.colors
	c.setup(self, kind, cols[randi() % cols.size()])
	c.contact_monitor = false
	return c


func _physics_process(dt: float) -> void:
	if world == null:
		return
	var player: Node3D = Game.player
	if player == null or not is_instance_valid(player):
		return
	var obstacles: Array = []
	obstacles.append_array(cars)
	for pc in physics_cars:
		if is_instance_valid(pc):
			obstacles.append(pc)
	var pp := player.global_position
	for c in cars.duplicate():
		c.step(dt, obstacles)
		var d: float = c.global_position.distance_to(pp)
		if d > 520.0 or (c.crashed and c.crash_time > 14.0 and d > 60.0) or c.global_position.y < -50.0:
			cars.erase(c)
			_recycle(c)
	# collisions with racers knock cars loose
	for pc in physics_cars:
		if not is_instance_valid(pc) or not (pc is RigidBody3D):
			continue
		var pv: Vector3 = pc.linear_velocity
		for c in cars:
			if c.crashed:
				continue
			var rel: Vector3 = c.global_position - pc.global_position
			if rel.length() < (c.length * 0.5 + 2.4) and absf(rel.y) < 2.0:
				var closing: float = (pv - c._heading * c.speed).dot(-rel.normalized())
				if closing > 3.0:
					c.knock(pv * c.mass * 0.25, pc.global_position)
	_spawn_cd -= dt
	if enabled and cars.size() < max_cars and _spawn_cd <= 0.0:
		_spawn_cd = 0.12
		_try_spawn(pp, player)


func _try_spawn(pp: Vector3, player: Node3D) -> void:
	var wd := world.data
	var base := pp
	var vel := Vector3.ZERO
	if player is RigidBody3D:
		vel = player.linear_velocity
	# prefer spawning ahead of the player (and along the race route)
	var ahead := vel.normalized() if vel.length() > 3.0 else Vector3.ZERO
	var cand := Vector3.ZERO
	if route_points.size() > 0 and randf() < 0.65:
		var best := 0
		var bd := 1e9
		for i in range(0, route_points.size(), 4):
			var d := route_points[i].distance_squared_to(pp)
			if d < bd:
				bd = d
				best = i
		var off := randi_range(40, 110)
		cand = route_points[mini(best + off, route_points.size() - 1)]
	else:
		var ang := randf() * TAU
		var r := randf_range(140.0, 420.0)
		cand = pp + Vector3(cos(ang), 0, sin(ang)) * r + ahead * 120.0
	var nr := wd.nearest_road(cand, 70.0)
	if nr.is_empty():
		return
	var rd: Dictionary = wd.roads[nr.road]
	if int(rd.lanes) <= 0 or rd.tunnel[nr.idx] == 1:
		return
	var p: Vector3 = nr.pos
	var dist := p.distance_to(pp)
	if dist < 90.0 or dist > 480.0:
		return
	for c in cars:
		if c.global_position.distance_squared_to(p) < 30.0 * 30.0:
			return
	for pc in physics_cars:
		if is_instance_valid(pc) and pc.global_position.distance_squared_to(p) < 60.0 * 60.0:
			return
	var c := _get_car()
	var d := 1 if randf() < 0.5 else -1
	var lane := lane_offset(rd, randi() % maxi(int(rd.lanes), 1))
	var v := road_speed(rd) * randf_range(0.8, 1.1)
	c.spawn(nr.road, d, float(nr.idx), lane, v)
	cars.append(c)
