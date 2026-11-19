class_name TrafficCar
extends RigidBody3D
## Civilian vehicle that follows lanes kinematically and becomes a real physics
## body once it is hit.

var mgr: Node
var model: CarModel
var road := 0
var dir := 1
var s := 0.0
var lane := 3.0
var speed := 12.0
var target_speed := 12.0
var crashed := false
var crash_time := 0.0
var spin := 0.0
var _pos := Vector3.ZERO
var _heading := Vector3.FORWARD
var _inited := false
var honk_cd := 0.0
var length := 4.5


func setup(manager: Node, kind: String, color: Color) -> void:
	mgr = manager
	var spec: Dictionary = Game.TRAFFIC[kind]
	model = CarModel.new()
	add_child(model)
	model.build(spec.body, color, randi())
	length = model.length
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(model.width * 0.95, model.height * 0.8, model.length * 0.96)
	cs.shape = box
	cs.position = Vector3(0, model.style.cl + model.height * 0.42, float(model.style.get("front_off", 0.0)))
	add_child(cs)
	mass = spec.mass
	collision_layer = 2
	collision_mask = 1 | 2
	freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
	freeze = true
	var pm := PhysicsMaterial.new()
	pm.friction = 0.9
	physics_material_override = pm
	linear_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
	linear_damp = 0.4
	angular_damp = 1.0
	set_meta("traffic", true)


func spawn(r: int, d: int, s0: float, lane_off: float, v: float) -> void:
	road = r
	dir = d
	s = s0
	lane = lane_off
	target_speed = v
	speed = v
	crashed = false
	freeze = true
	_inited = false
	visible = true
	_place(0.0)
	reset_physics_interpolation()


func knock(impulse: Vector3, at: Vector3) -> void:
	if crashed:
		return
	crashed = true
	crash_time = 0.0
	var v := _heading * speed
	freeze = false
	linear_velocity = v
	apply_impulse(impulse, at - global_position)
	if mgr and mgr.world:
		mgr.world.register_vehicle(self)


func _lane_point(r: int, sf: float, d: int, off: float) -> Array:
	var rd: Dictionary = mgr.world.data.roads[r]
	var pv: PackedVector3Array = rd.pv
	var n := pv.size()
	var closed: bool = rd.closed
	if closed:
		sf = fposmod(sf, float(n))
	else:
		sf = clampf(sf, 0.0, n - 1.001)
	var i := int(sf)
	var f := sf - i
	var i2 := (i + 1) % n if closed else mini(i + 1, n - 1)
	var p := pv[i].lerp(pv[i2], f)
	var t := (pv[i2] - pv[i])
	t.y = 0.0
	t = t.normalized() * d
	var right := t.cross(Vector3.UP).normalized()
	return [p + right * off, t]


func _place(dt: float) -> void:
	var lp := _lane_point(road, s, dir, lane)
	var p: Vector3 = lp[0]
	var t: Vector3 = lp[1]
	if not _inited or dt <= 0.0:
		_pos = p
		_heading = t
		_inited = true
	else:
		var k := clampf(dt * 5.0, 0.0, 1.0)
		_pos = _pos.lerp(p, k)
		if _heading.dot(t) < -0.5:
			_heading = t
		else:
			var hh := _heading.lerp(t, clampf(dt * 4.0, 0.0, 1.0))
			hh.y = 0.0
			if hh.length() > 0.01:
				_heading = hh.normalized()
	var basis := Basis.looking_at(_heading, Vector3.UP)
	global_transform = Transform3D(basis, _pos + Vector3(0, 0.02, 0))


func step(dt: float, obstacles: Array) -> void:
	if crashed:
		crash_time += dt
		return
	honk_cd = maxf(honk_cd - dt, 0.0)
	var rd: Dictionary = mgr.world.data.roads[road]
	var pv: PackedVector3Array = rd.pv
	var n := pv.size()
	# car following
	var want := target_speed
	var fwd := _heading
	var me := global_position
	for o in obstacles:
		if o == self:
			continue
		var op: Vector3 = o.global_position
		var d := op - me
		var dist := d.length()
		if dist > 34.0 or dist < 0.1:
			continue
		var along := d.dot(fwd)
		if along <= 0.0:
			continue
		var lateral := (d - fwd * along).length()
		if lateral > 2.4:
			continue
		var gap := along - 6.0
		var ov := 0.0
		if o is TrafficCar:
			ov = (o as TrafficCar).speed if not o.crashed else 0.0
		elif o is RigidBody3D:
			ov = maxf((o as RigidBody3D).linear_velocity.dot(fwd), 0.0)
		var safe := ov + gap * 0.9
		want = minf(want, maxf(safe, 0.0))
		if o is Car and o.is_player and along < 12.0 and honk_cd <= 0.0 and speed > 3.0:
			honk_cd = 6.0
			mgr.honk(self)
	speed = move_toward(speed, want, (6.0 if want < speed else 2.5) * dt)
	var seg_len := pv[mini(int(s) + 1, n - 1)].distance_to(pv[int(s) % n]) if not rd.closed else 4.0
	seg_len = maxf(seg_len, 1.0)
	s += dir * speed * dt / seg_len
	# road ends -> choose the next road at the junction
	if not rd.closed:
		if dir > 0 and s >= n - 1.0:
			_next_road(int(rd.j_end), n - 1)
		elif dir < 0 and s <= 0.0:
			_next_road(int(rd.j_start), 0)
	_place(dt)
	spin += speed * dt / 0.33
	for i in 4:
		model.set_wheel(i, 0.0, spin, model.wheel_rest[i])


func _next_road(jid: int, at_k: int) -> void:
	var options := []
	if jid >= 0:
		var j: Dictionary = mgr.world.data.json.junctions[jid]
		for l in j.links:
			var r := int(l[0])
			var k := int(l[1])
			if r == road:
				continue
			var rd: Dictionary = mgr.world.data.roads[r]
			if int(rd.lanes) <= 0:
				continue
			var m: int = rd.pv.size()
			if k == 0:
				options.append([r, 1, 0.0])
			elif k == m - 1:
				options.append([r, -1, float(m - 1)])
			else:
				options.append([r, 1, float(k)])
				options.append([r, -1, float(k)])
	if options.is_empty():
		# dead end: U-turn
		dir = -dir
		s = float(at_k)
		return
	var o: Array = options[randi() % options.size()]
	road = o[0]
	dir = o[1]
	s = o[2]
	var rd2: Dictionary = mgr.world.data.roads[road]
	lane = mgr.lane_offset(rd2, randi() % maxi(int(rd2.lanes), 1))
	target_speed = mgr.road_speed(rd2) * randf_range(0.85, 1.1)
