extends Node
var main: Node
var f := 0
func _ready() -> void:
	main = load("res://scripts/main.gd").new()
	add_child(main)
	await get_tree().process_frame
	Game.settings["quality"] = int(OS.get_environment("Q"))
	Game.delete_save()
	main._new_game()
func _process(_dt: float) -> void:
	if main.world == null or not main.world.started:
		return
	f += 1
	if f == 300:
		var rs := RenderingServer
		print("Q=", Game.settings["quality"], " chunks=", main.world.terrain.chunks.size(),
			" draw_calls=", rs.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME),
			" objects=", rs.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_OBJECTS_IN_FRAME),
			" prims=", rs.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME),
			" vmem_MB=", rs.get_rendering_info(RenderingServer.RENDERING_INFO_VIDEO_MEM_USED) / 1048576)
		get_tree().quit()
