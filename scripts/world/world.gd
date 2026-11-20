class_name World
extends Node3D
## Owns every world system and builds them in stages.

signal progress(fraction: float, label: String)

var data: WorldData
var env: GameEnv
var terrain: Terrain
var roads: RoadBuilder
var water: Water
var veg: Vegetation
var city: City
var ruins: Ruins
var ramps_node: Node3D
var quality := 1
var _veg_timer := 0.0


func build_async() -> void:
	quality = int(Game.settings.quality)
	var view: float = Game.settings.view_distance
	progress.emit(0.02, "data")
	await get_tree().process_frame
	data = WorldData.new()
	data.load_all()
	progress.emit(0.12, "env")
	await get_tree().process_frame
	env = GameEnv.new()
	add_child(env)
	env.setup(quality, int(Game.settings.time_of_day), view)
	progress.emit(0.18, "terrain")
	await get_tree().process_frame
	terrain = Terrain.new()
	add_child(terrain)
	terrain.setup(data, quality, view)
	progress.emit(0.35, "roads")
	await get_tree().process_frame
	roads = RoadBuilder.new()
	add_child(roads)
	roads.build(data, quality)
	progress.emit(0.55, "water")
	await get_tree().process_frame
	water = Water.new()
	add_child(water)
	water.build(data, quality)
	progress.emit(0.62, "vegetation")
	await get_tree().process_frame
	veg = Vegetation.new()
	add_child(veg)
	veg.build(data, quality, view)
	progress.emit(0.8, "city")
	await get_tree().process_frame
	city = City.new()
	add_child(city)
	city.build(data, quality)
	city.set_night(0.0 if int(Game.settings.time_of_day) != 3 else 0.4)
	progress.emit(0.9, "ruins")
	await get_tree().process_frame
	ruins = Ruins.new()
	add_child(ruins)
	ruins.build(data)
	_build_ramps()
	progress.emit(1.0, "done")


func _build_ramps() -> void:
	ramps_node = Node3D.new()
	add_child(ramps_node)
	var mat := Mats.triplanar(3, 0.3, Color(0.9, 0.85, 0.75), "ramp")
	for r in data.json.ramps:
		var L: float = r.length
		var W: float = r.width
		var H: float = r.height
		var p := Vector3(r.pos[0], r.pos[1], r.pos[2])
		var yaw := float(r.yaw)
		var fwd := Vector3(sin(yaw), 0, cos(yaw))
		var right := fwd.cross(Vector3.UP).normalized()
		var lo := p - fwd * L * 0.5
		var hi := p + fwd * L * 0.5
		# follow the ground at both ends so there is never a lip to hit
		var y_lo := data.ground_height(lo) - 0.03
		var y_hi := data.ground_height(hi)
		var top_hi := y_hi + H
		var bottom := minf(y_lo, y_hi) - 2.5
		var c := [lo - right * W * 0.5, lo + right * W * 0.5, hi + right * W * 0.5, hi - right * W * 0.5]
		var top := [Vector3(c[0].x, y_lo, c[0].z), Vector3(c[1].x, y_lo, c[1].z), Vector3(c[2].x, top_hi, c[2].z), Vector3(c[3].x, top_hi, c[3].z)]
		var bot := [Vector3(c[0].x, bottom, c[0].z), Vector3(c[1].x, bottom, c[1].z), Vector3(c[2].x, bottom, c[2].z), Vector3(c[3].x, bottom, c[3].z)]
		var m := MeshAcc.new()
		var up: Vector3 = (top[1] - top[0]).cross(top[3] - top[0]).normalized()
		if up.y < 0.0:
			up = -up
		var ids := []
		for q in top:
			ids.append(m.v(q, up, Vector2(q.x, q.z)))
		m.quad(ids[0], ids[1], ids[2], ids[3], up)
		# back face (drop) and the two sides
		var faces := [[top[3], top[2], bot[2], bot[3], fwd], [top[0], top[3], bot[3], bot[0], -right], [top[1], top[2], bot[2], bot[1], right]]
		for f in faces:
			var nn: Vector3 = f[4]
			var a0 := m.v(f[0], nn, Vector2(0, 0)); var a1 := m.v(f[1], nn, Vector2(1, 0))
			var a2 := m.v(f[2], nn, Vector2(1, 1)); var a3 := m.v(f[3], nn, Vector2(0, 1))
			m.quad(a0, a1, a2, a3, nn)
		var body := StaticBody3D.new()
		body.set_meta("surface", "concrete")
		ramps_node.add_child(body)
		var mi := MeshInstance3D.new()
		mi.mesh = m.to_mesh(mat)
		body.add_child(mi)
		var cs := CollisionShape3D.new()
		var sh := ConvexPolygonShape3D.new()
		var allp := PackedVector3Array()
		for q in top:
			allp.append(q)
		for q in bot:
			allp.append(q)
		sh.points = allp
		cs.shape = sh
		body.add_child(cs)


func register_vehicle(b: Node3D) -> void:
	terrain.register_body(b)


func unregister_vehicle(b: Node3D) -> void:
	terrain.unregister_body(b)


func _physics_process(delta: float) -> void:
	if veg == null:
		return
	_veg_timer -= delta
	if _veg_timer <= 0.0:
		_veg_timer = 0.15
		var pts := []
		for b in terrain.bodies:
			if is_instance_valid(b) and b is RigidBody3D and b.get_meta("near_player", true):
				pts.append(b.global_position + b.linear_velocity * 0.4)
		veg.update_colliders(pts)


## height of the drivable surface (terrain or road deck) at a point
func ground_y(p: Vector3) -> float:
	return data.ground_height(p)
