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
	probe.global_position = Vector3(-420, 270, -1667)
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
	for p in [Vector3(-400, 0, -1666), Vector3(-380, 0, -1666), Vector3(-365, 0, -1665), Vector3(-357, 0, -1664), Vector3(-350, 0, -1662), Vector3(-330, 0, -1660)]:
		var gy := world.data.ground_height(p)
		var q := PhysicsRayQueryParameters3D.create(p + Vector3(0, gy + 3.0, 0), p + Vector3(0, gy - 20.0, 0))
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
	var errs := [0.0, 0.0, 0.0, 0.0]
	var cnt := 0
	var wd := world.data
	var rng := RandomNumberGenerator.new()
	for it in 400:
		var x := rng.randf_range(-440.0, -400.0)
		var z := rng.randf_range(-1700.0, -1640.0)
		var q := PhysicsRayQueryParameters3D.create(Vector3(x, 600, z), Vector3(x, 0, z))
		q.collision_mask = 1
		var excl := []
		var hy := -1.0
		for k in 6:
			q.exclude = excl
			var h := space.intersect_ray(q)
			if h.is_empty():
				break
			if h.collider.get_meta("surface", "") == "terrain" and h.collider.get_parent() == world.terrain and h.collider != world.terrain.caps_body:
				hy = h.position.y
				break
			excl.append(h.rid)
		if hy < 0:
			continue
		var gx := (x + wd.half) / wd.cell
		var gz := (z + wd.half) / wd.cell
		var i := floori(gx); var j := floori(gz)
		var fx := gx - i; var fz := gz - j
		var h00 := wd.h_at(i, j); var h10 := wd.h_at(i + 1, j); var h01 := wd.h_at(i, j + 1); var h11 := wd.h_at(i + 1, j + 1)
		var d1 := wd.height(x, z)
		var d2 := 0.0
		if fx + fz < 1.0:
			d2 = h00 + (h10 - h00) * fx + (h01 - h00) * fz
		else:
			d2 = h11 + (h01 - h11) * (1.0 - fx) + (h10 - h11) * (1.0 - fz)
		var tr := wd.h_at(j, i) # transposed sample (rough check)
		errs[0] += absf(hy - d1); errs[1] += absf(hy - d2); errs[2] += absf(hy - lerpf(lerpf(h00, h10, fx), lerpf(h01, h11, fx), fz)); errs[3] += absf(hy - tr)
		cnt += 1
	print("[col] samples=", cnt, " mean |err| diag_ad=", errs[0] / cnt, " diag_bc=", errs[1] / cnt, " bilinear=", errs[2] / cnt, " transposed=", errs[3] / cnt)
	get_tree().quit()
