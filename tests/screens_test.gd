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
		[1.5, "menu", func(): pass],
		[1.2, "marker", func(): main._start_freeplay(); _marker()],
		[0.8, "settings_controls", func(): main._pause(); main.menus._settings_tab = 1; main.menus.rebuild(); main.menus.show_page("settings")],
		[0.8, "layout_editor", func(): main.menus._open_controls_editor()],
	]

func _setup_goal() -> void:
	var w: SimWorld = main.world
	w.ball.pos = Vector3(2, 2.5, -40)
	w.ball.vel = Vector3(0, 2, -22)
	w.ball_frozen = false
	w.ball.touched = true
	w.ball.last_touch_car = 0
	main.match_ctrl.touch_log.append([0, 0, w.tick])

func _marker() -> void:
	var w: SimWorld = main.world
	var c: CarSim = main.match_ctrl.player_car
	c.place(Vector3(0, 0.17, 20), 0.0)
	w.ball.reset(Vector3(-3, 9, 6))
	w.ball.vel = Vector3(0, 0, 0)
	w.ball_frozen = true

func _pickup() -> void:
	var w: SimWorld = main.world
	var c: CarSim = main.match_ctrl.player_car
	c.boost = 20.0
	w.unlimited_boost = false
	c.place(Vector3(32.0, 0.17, 4.0), 0.0)
	c.vel = Vector3(0, 0, -6)

func _air() -> void:
	var c: CarSim = main.match_ctrl.player_car
	c.pos = Vector3(0, 6, 10)
	c.vel = Vector3(0, 3, -10)
	c.basis = Basis(Vector3.RIGHT, 0.5)
	main.touch.boost_held = true

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
