extends Node
var main: Node
var step := 0
var wait := 0
var npc = null
func _ready() -> void:
	main = load("res://scripts/main.gd").new()
	add_child(main)
	await get_tree().process_frame
	Game.delete_save()
	main._new_game()
func _process(_dt: float) -> void:
	if main.world == null or not main.world.started:
		return
	var w = main.world
	var p = w.player
	wait += 1
	if wait < 45:
		return
	wait = 0
	match step:
		0:
			w.sky.set_weather("clear")
			w.sky.hours = 15.0
			p.global_position = w.ai.settlements[1]["pos"] + Vector3(3, 2, 3)
			w.terrain.generate_now(p.global_position, 2)
		1:
			var best := 999.0
			for n in w.ai.active_npcs:
				if is_instance_valid(n) and n.global_position.distance_to(p.global_position) < best:
					best = n.global_position.distance_to(p.global_position)
					npc = n
			if npc:
				npc.in_dialog = true
				npc.say("أهلاً بك يا غريب! هل تبحث عن عمل؟", 30.0)
				var fwd: Vector3 = -npc.global_transform.basis.z
				p.global_position = npc.global_position + fwd * 2.2
				var to: Vector3 = npc.global_position - p.global_position
				p.cam_yaw.rotation.y = atan2(-to.x, -to.z) + 0.35
				p.cam_pitch.rotation.x = -0.05
		3:
			get_viewport().get_texture().get_image().save_png(OS.get_environment("SHOT_DIR") + "/40_npc_face.png")
			print("SHOT 40")
			get_tree().quit()
	step += 1
