extends SceneTree
## عرض نموذج في وضع الراحة للفحص: godot --path . --script tools/view_model.gd -- athlete
func _init() -> void:
	var id := "athlete"
	var args := OS.get_cmdline_user_args()
	if args.size() > 0: id = args[0]
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.25, 0.27, 0.3)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.6, 0.65, 0.75)
	e.ambient_light_energy = 0.4
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.environment = e
	root.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.light_energy = 0.95
	sun.shadow_enabled = true
	root.add_child(sun)
	sun.look_at_from_position(Vector3(2, 4, -3), Vector3.ZERO, Vector3.UP)
	var xs := [-0.6, 0.6]
	for k in 2:
		var inst: Node3D = load("res://assets/characters/body_%s.glb" % id).instantiate()
		root.add_child(inst)
		inst.position = Vector3(xs[k], 0, 0)
		inst.rotation.y = 0.0 if k == 0 else PI * 0.5
		HumanLook.apply(inst, HumanLook.default_look())
	var cam := Camera3D.new()
	root.add_child(cam)
	cam.fov = 30
	cam.look_at_from_position(Vector3(0, 1.0, -4.6), Vector3(0, 0.95, 0), Vector3.UP)
	cam.current = true
	for i in 8:
		await process_frame
	root.get_texture().get_image().save_png("/tmp/shots/model_%s.png" % id)
	# لقطة قريبة للوجه
	var hy := 1.62
	var sk := root.find_child("Skeleton3D", true, false) as Skeleton3D
	if sk != null and sk.find_bone("Head") >= 0:
		hy = sk.get_bone_global_rest(sk.find_bone("Head")).origin.y + 0.09
	cam.fov = 9
	cam.look_at_from_position(Vector3(-0.6 - 0.5, hy + 0.02, -2.2), Vector3(-0.6, hy, 0), Vector3.UP)
	for i in 4:
		await process_frame
	root.get_texture().get_image().save_png("/tmp/shots/face_%s.png" % id)
	quit()
