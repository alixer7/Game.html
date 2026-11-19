extends Node
func _ready():
	if OS.get_cmdline_user_args().has("--terrain-test"):
		get_tree().create_timer(240.0).timeout.connect(func(): get_tree().quit(3))
		add_child(load("res://scripts/dev/terrain_test.gd").new())
		return
