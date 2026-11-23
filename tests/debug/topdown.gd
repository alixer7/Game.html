extends Node3D
## Debug: orthographic top-down render around a mark.  -- <mark> <size_m> <out.png>

func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	Game.settings["quality"] = 0
	var tb := TrackBuilder.new()
	tb.load_track("res://data/timberfall.json")
	tb.build(self, 0)
	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(deg_to_rad(-60), deg_to_rad(-30), 0)
	add_child(sun)
	var we := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.2, 0.2, 0.25)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.6, 0.6, 0.6)
	we.environment = e
	add_child(we)
	var p := tb.mark_pos(args[0])
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = float(args[1])
	cam.far = 400.0
	add_child(cam)
	cam.global_position = p + Vector3.UP * 150.0
	cam.rotation = Vector3(-PI * 0.5, 0, 0)
	cam.current = true
	# hide canopies so the roads read
	for n in find_children("*", "MultiMeshInstance3D", true, false):
		var nm := String(n.name)
		if nm.begins_with("oak") or nm.begins_with("pine") or nm.begins_with("birch") or nm.begins_with("autumn") or nm.begins_with("bush"):
			(n as Node3D).visible = false
	for i in 8:
		await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png(args[2])
	get_tree().quit()
