extends Node
## Renders screenshots from several viewpoints (run with a display).
var world: SimWorld
var arena: ArenaView
var cam: CameraRig
var views: Array = []
var ball_view: BallView
var frame := 0
var shots := []
var shot_i := 0
var out_dir := "res://tests/shots/"

func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out_dir))
	world = SimWorld.new()
	add_child(world)
	arena = ArenaView.new()
	add_child(arena)
	arena.build(world)
	for i in range(4):
		var c := CarSim.new()
		c.setup(i % 3)
		c.team = i % 2
		world.add_car(c, null)
		var tf := SimWorld.kickoff_transform(c.team, i / 2)
		c.place(tf[0], tf[1])
		var v := CarView.new()
		add_child(v)
		var paint := Phys.team_color(c.team)
		v.setup(c, paint, Color(0.95, 0.95, 1.0), Color(1, 0.6, 0.15), "BOT %d" % i)
		views.append(v)
	world.cars[0].place(Vector3(0, 0.17, 6), 0.0)
	world.cars[0].boosting = true
	ball_view = BallView.new()
	add_child(ball_view)
	ball_view.setup(world.ball)
	world.ball.reset(Vector3(0, Phys.BALL_R, 0))
	cam = CameraRig.new()
	add_child(cam)
	var fx := FxLayer.new()
	add_child(fx)
	shots = [
		["car_cam", func(d): cam.ball_cam = true; cam.follow(world.cars[0].pos, world.cars[0].basis, Vector3.ZERO, true, world.ball.pos, false, false, d)],
		["overview", func(d): cam.global_transform = Transform3D().looking_at(Vector3(0, -14, 40), Vector3.UP); cam.global_position = Vector3(30, 18, -38); cam.look_at(Vector3(0, 0, 10))],
		["goal", func(d): cam.global_position = Vector3(6, 4, 30); cam.look_at(Vector3(0, 3, 52))],
		["car_close", func(d): cam.global_position = world.cars[0].pos + Vector3(2.2, 1.0, -2.6); cam.look_at(world.cars[0].pos + Vector3(0, 0.2, 0))],
		["car_close2", func(d): cam.global_position = world.cars[1].pos + Vector3(-2.0, 0.9, 2.0); cam.look_at(world.cars[1].pos + Vector3(0, 0.2, 0))],
	]

func _process(delta: float) -> void:
	frame += 1
	var now := Time.get_ticks_msec() / 1000.0
	for v in views:
		v.update_visual(1.0, cam, delta, now)
	ball_view.update_visual(1.0, cam, delta, now)
	if shot_i < shots.size():
		shots[shot_i][1].call(1.0 / 60.0)
	if frame > 10 and frame % 8 == 0 and shot_i < shots.size():
		var img := get_viewport().get_texture().get_image()
		img.save_png(ProjectSettings.globalize_path(out_dir + shots[shot_i][0] + ".png"))
		print("saved ", shots[shot_i][0])
		shot_i += 1
	if shot_i >= shots.size():
		get_tree().quit()
