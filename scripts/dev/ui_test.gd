extends Node
# Dev harness: screenshots of touch controls, layout editor, settings and pause menu.
var main
var t := 0.0
var stage := 0
func _ready():
	main = get_parent()
	process_mode = Node.PROCESS_MODE_ALWAYS
func _shot(n: String):
	get_viewport().get_texture().get_image().save_png(OS.get_environment("SHOT_DIR") + "/ui_%s.png" % n)
func _process(dt):
	if main.race == null or main.player == null:
		return
	t += dt
	match stage:
		0:
			if t > 2.0:
				main._start_free_roam()
				main.touch.visible = true
				main.player.controller = null
				main.player.throttle = 0.6
				stage = 1; t = 0.0
		1:
			if t > 3.0:
				_shot("drive_buttons")
				Game.controls.steer_mode = "wheel"
				main.touch.queue_redraw()
				stage = 2; t = 0.0
		2:
			if t > 1.0:
				_shot("drive_wheel")
				main._pause()
				stage = 3; t = 0.0
		3:
			if t > 1.0:
				_shot("pause")
				main.menus.show_settings("pause")
				stage = 4; t = 0.0
		4:
			if t > 1.0:
				_shot("settings")
				main.menus.show_controls("pause")
				stage = 5; t = 0.0
		5:
			if t > 1.0:
				_shot("controls")
				main.menus.open_layout_editor("pause")
				main.touch.selected = "gas"
				stage = 6; t = 0.0
		6:
			if t > 1.0:
				_shot("layout_editor")
				Game.settings.lang = "en"
				main.menus.show_main()
				stage = 7; t = 0.0
		7:
			if t > 1.0:
				_shot("main_en")
				get_tree().quit()
