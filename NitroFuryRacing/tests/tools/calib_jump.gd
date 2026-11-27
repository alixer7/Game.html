extends Node
## Measures real hop-jump range off a kicker (same height landing) for pitch x speed.
func _ready() -> void:
	var root := Node3D.new()
	add_child(root)
	var floor_sb := StaticBody3D.new()
	floor_sb.collision_layer = 1
	floor_sb.set_meta("surface_type", "road")
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(60, 2, 1200)
	cs.shape = box
	floor_sb.position = Vector3(0, -1, -500)
	floor_sb.add_child(cs)
	root.add_child(floor_sb)
	var kart := KartPhysics.new()
	root.add_child(kart)
	kart.setup_racer(GameState.RACERS[0], false, null, 3)
	for pitch in [8.0, 12.0, 16.0, 20.0, 24.0]:
		var kl := 8.0
		var rh := tan(deg_to_rad(pitch)) * kl
		var k_sb := StaticBody3D.new()
		k_sb.collision_layer = 1
		k_sb.set_meta("surface_type", "kicker")
		var faces := PackedVector3Array([Vector3(-3, 0.02, 0), Vector3(-3, rh, -kl), Vector3(3, rh, -kl), Vector3(-3, 0.02, 0), Vector3(3, rh, -kl), Vector3(3, 0.02, 0)])
		var kcs := CollisionShape3D.new()
		var sh := ConcavePolygonShape3D.new()
		sh.set_faces(faces)
		kcs.shape = sh
		k_sb.add_child(kcs)
		k_sb.position = Vector3(0, 0, -100)
		root.add_child(k_sb)
		var line := "pitch %4.1f:" % pitch
		for spec in [[0, 0], [0, 10], [3, 0], [3, 10], [4, 10]]:
			for hop in [true, false]:
				kart.place_at_start(Vector3(0, 0.6, -40), 0.0)
				kart.race_started = true
				kart.fruit_count = spec[1]
				kart.reserves = 0.0
				kart.fire_tier = 0
				if spec[0] > 0:
					kart.add_boost(spec[0], 12.0, 0.0, false)
				kart.forward_speed = kart.get_current_top_speed()
				kart.velocity = Vector3(0, 0, -kart.forward_speed)
				var v0 := kart.forward_speed
				var hopped := false
				var launched := false
				var lip_z := -100.0 - kl
				var land_z := 0.0
				for f in range(400):
					kart.input_accel = true
					kart.input_steer = 0.0
					if spec[0] > 0:
						kart.reserves = 6.0
					if hop and not hopped and kart.is_grounded and kart.surface_type == "kicker" and kart.global_position.z < lip_z + 2.4:
						kart.input_hop_just_pressed = true
						hopped = true
					await get_tree().physics_frame
					if not kart.is_grounded and kart.global_position.z < lip_z + 1.0:
						launched = true
					if launched and kart.is_grounded:
						land_z = kart.global_position.z
						break
				line += "  v%.1f%s=%.1f" % [v0, "H" if hop else "", lip_z - land_z]
		print(line)
		k_sb.queue_free()
		await get_tree().physics_frame
	get_tree().quit()
