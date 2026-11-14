extends Node
## Drives the real main scene and captures screenshots of key screens.
var main: Node
var step := 0
var t := 0.0
var out := "res://tests/shots/"
var plan: Array = []

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out))
	Settings.data["tutorial_seen"] = true
	Settings.data["language"] = OS.get_environment("SHOT_LANG") if OS.get_environment("SHOT_LANG") != "" else "ar"
	main = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	plan = [
		[2.5, "menu", func(): pass],
		[0.6, "play_setup", func(): main.menus.show_page("play")],
		[1.0, "garage", func(): main.menus.show_page("garage")],
		[0.8, "settings", func(): main.menus.show_page("settings")],
		[1.2, "countdown", func(): main.menus.hide_all(); main._start_match({"size": 2, "difficulty": 1, "minutes": 5, "team": 0})],
		[4.0, "gameplay", func(): _hold_input(true)],
		[2.0, "gameplay2", func(): pass],
		[0.5, "pause", func(): _hold_input(false); main._pause()],
		[0.5, "end", func(): main._resume(); main.match_ctrl.score = [3, 1]; main.match_ctrl._end_match()],
		[3.0, "end2", func(): pass],
		[1.5, "freeplay", func(): main._start_freeplay()],
	]

func _hold_input(on: bool) -> void:
	main.touch.stick = Vector2(0.3, 1.0) if on else Vector2.ZERO
	main.touch.boost_held = on

func _process(delta: float) -> void:
	t += delta
	if step < plan.size() and t >= plan[step][0]:
		var img := get_viewport().get_texture().get_image()
		img.save_png(ProjectSettings.globalize_path(out + "s_%02d_%s.png" % [step, plan[step][1]]))
		print("shot ", plan[step][1])
		t = 0.0
		step += 1
		if step < plan.size():
			plan[step][2].call()
	if step >= plan.size():
		get_tree().quit()
