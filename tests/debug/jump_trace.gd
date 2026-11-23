extends Node
## Debug: trace one jump attempt.  -- <branch_id|main> <lip_tag> <speed> <hop 0/1>

func _ready() -> void:
	var a := OS.get_cmdline_user_args()
	var root := Node3D.new()
	add_child(root)
	var tb := TrackBuilder.new()
	tb.load_track("res://data/timberfall.json")
	tb.build(root, 0)
	await get_tree().physics_frame
	var sp: SplinePath = tb.main if a[0] == "main" else tb.branches[a[0]]
	var lip := -1
	for i in sp.size():
		if sp.tags[i] == a[1]:
			lip = i
			break
	var v := float(a[2])
	var hop := a[3] == "1"
	var start := maxi(lip - int(30.0 / sp.spacing), 0)
	print("lip idx=%d start=%d lip_pos=%s styles: %s" % [lip, start, sp.pos[lip], [sp.style[lip], sp.style[mini(lip + 3, sp.size() - 1)]]])
	for i in range(start, mini(lip + 20, sp.size()), 2):
		print("  path %d %s y=%.2f w=%.1f style=%s tag=%s" % [i, Vector2(sp.pos[i].x, sp.pos[i].z).snapped(Vector2.ONE * 0.1), sp.pos[i].y, sp.width[i], sp.style[i], sp.tags[i]])
	var k := Kart.new()
	k.params = KartParams.new()
	k.params.max_speed = v
	k.params.accel = 40.0
	root.add_child(k)
	var t := sp.tan[start]
	var yaw := atan2(-t.x, -t.z)
	k.teleport(Transform3D(Basis(Vector3.UP, yaw), sp.pos[start] + sp.up[start] * 0.3))
	await get_tree().physics_frame
	await get_tree().physics_frame
	k.velocity = Vector3(-sin(yaw), 0, -cos(yaw)) * v
	var hopped := false
	for f in 150:
		var i := sp.nearest_index(k.global_position, 30.0)
		var tgt := sp.pos[mini(i + 4, sp.size() - 1)]
		var to := tgt - k.global_position
		to.y = 0
		var ang := k.heading().signed_angle_to(to.normalized(), Vector3.UP) if to.length() > 0.5 else 0.0
		k.in_steer = clampf(-ang * 2.0, -1.0, 1.0) if k.grounded else 0.0
		k.in_throttle = 1.0
		k.in_drift = false
		if hop and not hopped and k.grounded and i >= lip - 1 and i <= lip + 2:
			k.in_drift = true
			hopped = true
		await get_tree().physics_frame
		if f % 4 == 0:
			var lat := sp.lateral_offset(i, k.global_position) if i >= 0 else 0.0
			var col := ""
			if k.get_slide_collision_count() > 0:
				col = String((k.get_slide_collision(0).get_collider() as Node).name)
			print("f=%3d i=%3d lat=%5.1f y=%6.2f path_y=%6.2f v=%5.1f grounded=%s surf=%s col=%s" % [f, i, lat, k.global_position.y, sp.pos[i].y if i >= 0 else 0.0, k.speed, k.grounded, Surfaces.NAMES[k.surface], col])
	get_tree().quit()
