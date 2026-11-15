extends Node
var main: Node
var f := 0
func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	process_priority = 100
	Settings.data["tutorial_seen"] = true
	main = load("res://scenes/main.tscn").instantiate()
	add_child(main)
func _process(_d: float) -> void:
	f += 1
	if f == 20:
		main._start_freeplay()
		main.world.ball.reset(Vector3(-3, 9, 6))
		main.world.ball_frozen = true
	if f > 20:
		main.camera.global_position = Vector3(-3, 14, 14)
		main.camera.look_at(Vector3(-3, 0, 6))
	if f == 60:
		var bv: BallView = main.ball_view
		print("marker vis=", bv.marker.visible, " pos=", bv.marker.global_position, " col=", bv.marker_mat.albedo_color, " ok=", main.world.ball_marker_ok, " p=", main.world.ball_marker_pos)
		get_viewport().get_texture().get_image().save_png(ProjectSettings.globalize_path("res://tests/shots/marker_top.png"))
		get_tree().quit()
