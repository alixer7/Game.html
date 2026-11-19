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
		var basis := Basis(Vector3.UP, float(r.yaw))
		var m := MeshAcc.new()
		# wedge: rises along +Z (direction of travel = basis.z)
		var pts := [Vector3(-W * 0.5, 0, -L * 0.5), Vector3(W * 0.5, 0, -L * 0.5), Vector3(W * 0.5, H, L * 0.5), Vector3(-W * 0.5, H, L * 0.5),
			Vector3(-W * 0.5, -0.6, L * 0.5), Vector3(W * 0.5, -0.6, L * 0.5), Vector3(-W * 0.5, -0.6, -L * 0.5), Vector3(W * 0.5, -0.6, -L * 0.5)]
		var up := Vector3(0, L, -H).normalized()
		var ids := []
		for q in pts:
			ids.append(m.v(q, up, Vector2(q.x, q.z)))
		m.quad(ids[0], ids[1], ids[2], ids[3], up)
		var back := Vector3.BACK
		var b0 := m.v(pts[3], back); var b1 := m.v(pts[2], back); var b2 := m.v(pts[5], back); var b3 := m.v(pts[4], back)
		m.quad(b0, b1, b2, b3, back)
		for s: float in [-1.0, 1.0]:
			var n := Vector3(s, 0, 0)
			var xs: float = W * 0.5 * s
			var a := m.v(Vector3(xs, -0.6, -L * 0.5), n); var b := m.v(Vector3(xs, 0, -L * 0.5), n)
			var c := m.v(Vector3(xs, H, L * 0.5), n); var d := m.v(Vector3(xs, -0.6, L * 0.5), n)
			m.quad(a, b, c, d, n)
		var body := StaticBody3D.new()
		body.set_meta("surface", "concrete")
		ramps_node.add_child(body)
		body.global_transform = Transform3D(basis, p + Vector3(0, 0.02, 0))
		var mi := MeshInstance3D.new()
		mi.mesh = m.to_mesh(mat)
		body.add_child(mi)
		var cs := CollisionShape3D.new()
		var sh := ConvexPolygonShape3D.new()
		sh.points = PackedVector3Array(pts)
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
