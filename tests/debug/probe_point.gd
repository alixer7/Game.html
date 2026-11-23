extends Node
## Debug: terrain/road facts around a path sample.  -- <path_id> <index> [lateral...]

func _ready() -> void:
	var a := OS.get_cmdline_user_args()
	var root := Node3D.new()
	add_child(root)
	var tb := TrackBuilder.new()
	tb.load_track("res://data/timberfall.json")
	tb.build(root, 1)
	await get_tree().physics_frame
	var sp: SplinePath = tb.main if a[0] == "main" else tb.branches[a[0]]
	var i := int(a[1])
	var t := tb.terrain
	print("sample %d pos=%s w=%.1f style=%s tm=%s tag=%s" % [i, sp.pos[i], sp.width[i], sp.style[i], sp.terrain_mode[i], sp.tags[i]])
	for lat: float in [-9.0, -8.0, -7.0, -6.0, -5.5, -5.0, -4.0, 0.0, 4.0, 5.0, 6.0, 7.0, 8.0]:
		var p := sp.pos[i] + sp.right[i] * lat
		var ix := clampi(int(round((p.x - t.origin.x) / t.cell)), 0, t.nx - 1)
		var iz := clampi(int(round((p.z - t.origin.y) / t.cell)), 0, t.nz - 1)
		var id := t.idx(ix, iz)
		var q := PhysicsRayQueryParameters3D.create(p + Vector3.UP * 3.0, p + Vector3.DOWN * 5.0)
		var hit := root.get_world_3d().direct_space_state.intersect_ray(q)
		print("  lat %5.1f terrain=%.2f road_w=%.2f carve=%.2f dist=%.1f hit=%s %s" % [lat, t.height_at(p.x, p.z), t.road_w[id], t.carve[id], t.dist[id], (hit.position as Vector3).y if not hit.is_empty() else -99.0, (hit.collider as Node).name if not hit.is_empty() else ""])
	get_tree().quit()
