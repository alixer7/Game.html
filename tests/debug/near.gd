extends Node
## Debug: list meshes whose AABB is near a track mark.  -- <mark> <ahead_m> <radius>

func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var root := Node3D.new()
	add_child(root)
	var tb := TrackBuilder.new()
	tb.load_track("res://data/timberfall.json")
	tb.build(root, 0)
	var m: String = args[0]
	var ahead := float(args[1])
	var rad := float(args[2])
	var p := tb.mark_pos(m) + tb.heading_dir(m) * ahead
	print("probe ", p)
	for n in root.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		var aabb := mi.global_transform * mi.get_aabb()
		if aabb.grow(rad).has_point(p):
			print(mi.get_path(), "  aabb=", aabb.position.snapped(Vector3.ONE * 0.1), " size=", aabb.size.snapped(Vector3.ONE * 0.1))
	get_tree().quit()
