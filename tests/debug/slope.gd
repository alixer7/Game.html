extends Node
## Debug: kart behaviour on a plain slope.  -- <slope_deg> (positive = downhill in the driving direction)

func _ready() -> void:
	var deg := float(OS.get_cmdline_user_args()[0]) if OS.get_cmdline_user_args().size() > 0 else 10.0
	var b := StaticBody3D.new()
	b.set_meta("surface", Surfaces.DIRT)
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(40, 1, 2000)
	cs.shape = bs
	b.add_child(cs)
	b.rotation = Vector3(deg_to_rad(deg), 0, 0)   # +X rotation tilts -Z end down
	add_child(b)
	var k := Kart.new()
	k.params = KartParams.new()
	add_child(k)
	k.teleport(Transform3D(Basis(), Vector3(0, 0.6 + 300.0 * tan(deg_to_rad(deg)) * 0.0, 0)))
	k.global_position = Vector3(0, 0.6 + 0.0, 0) + Vector3(0, tan(deg_to_rad(deg)) * 0.0, 0)
	for f in 600:
		k.in_throttle = 1.0
		await get_tree().physics_frame
		if f % 30 == 0:
			print("t=%.1f v=%.2f vf=%.2f y=%.2f grounded=%s n=%s" % [f / 60.0, k.speed, k.forward_speed, k.global_position.y, k.grounded, k.ground_normal.snapped(Vector3.ONE * 0.01)])
	get_tree().quit()
