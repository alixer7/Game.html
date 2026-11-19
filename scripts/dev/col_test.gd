extends Node3D
var world: World
var done := false
var start := -1
func _ready():
	world = World.new()
	add_child(world)
	await world.build_async()
	var probe := Node3D.new()
	add_child(probe)
	probe.global_position = Vector3(-1755, 40, 230)
	world.register_vehicle(probe)
	start = Engine.get_physics_frames()
func _physics_process(_d):
	if world == null or world.terrain == null or done:
		return
	if start < 0 or Engine.get_physics_frames() < start + 10:
		return
	done = true
	var space := get_world_3d().direct_space_state
	print("[col] tiles=", world.terrain.collision.size(), " keys=", world.terrain.collision.keys().slice(0, 4))
	for key in world.terrain.collision:
		var b: StaticBody3D = world.terrain.collision[key].body
		print("[col] tile ", key, " pos=", b.global_position, " scale=", b.global_transform.basis.get_scale(), " shape=", (b.get_child(0) as CollisionShape3D).shape)
		break
	for p in [Vector3(-1755, 0, 230), Vector3(-1757, 0, 231), Vector3(-1740, 0, 230), Vector3(-1770, 0, 215), Vector3(-1730, 0, 250), Vector3(-1780, 0, 240)]:
		var q := PhysicsRayQueryParameters3D.create(p + Vector3(0, 200, 0), p - Vector3(0, 200, 0))
		var hits := []
		var excl := []
		for k in 4:
			q.exclude = excl
			var h := space.intersect_ray(q)
			if h.is_empty():
				break
			hits.append("%s y=%.2f surf=%s" % [h.collider.get_class(), h.position.y, h.collider.get_meta("surface", "?")])
			excl.append(h.rid)
		print("[col] ", p, " terrain=", world.data.height(p.x, p.z), " ground=", world.data.ground_height(p), " hits: ", hits)
	get_tree().quit()
