extends Node
## Verifies the chase camera keeps the car on screen in ball-cam (run with a display).
var main: Node
var t := 0.0
var phase := -1
var phase_t := 0.0
var worst := {}
var out := "res://tests/shots/"
var shots_taken := {}

class Drive:
	var car: CarSim
	var thr := 0.0
	var boost := false
	func update_controls(_dt: float) -> void:
		car.controls.reset()
		car.controls.throttle = thr
		car.controls.boost = boost

var drv := Drive.new()
var phases := [
	["ball_high_front", 3.0],
	["ball_overhead", 3.0],
	["wall_drive", 4.0],
	["wall_drive_ball_far", 4.0],
]

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out))
	Settings.data["tutorial_seen"] = true
	Settings.data["ball_cam"] = true
	main = load("res://scenes/main.tscn").instantiate()
	add_child(main)

func _start_phase(i: int) -> void:
	phase = i
	phase_t = 0.0
	worst[i] = 1e9
	var m: MatchController = main.match_ctrl
	var w: SimWorld = m.world
	var car := m.player_car
	drv.car = car
	w.controllers[car.id] = drv
	main.touch.ball_cam = true
	main.camera.ball_cam = true
	match phases[i][0]:
		"ball_high_front":
			car.place(Vector3(0, 0.17, 20), 0.0)
			drv.thr = 0.0
			drv.boost = false
			w.ball.reset(Vector3(0, 14, 12))
			w.ball_frozen = true
		"ball_overhead":
			car.place(Vector3(5, 0.17, 0), 0.0)
			w.ball.reset(Vector3(5, 11, -0.5))
			w.ball_frozen = true
		"wall_drive":
			car.place(Vector3(15, 0.17, 5), -PI * 0.5)
			drv.thr = 1.0
			drv.boost = true
			w.ball.reset(Vector3(0, 12, 0))
			w.ball_frozen = true
		"wall_drive_ball_far":
			car.place(Vector3(-15, 0.17, -10), PI * 0.5)
			drv.thr = 1.0
			drv.boost = true
			w.ball.reset(Vector3(20, 3, 40))
			w.ball_frozen = true
	main.camera._initialized = false

func _process(delta: float) -> void:
	t += delta
	if phase == -1:
		if t > 1.0:
			main._start_freeplay()
			_start_phase(0)
		return
	phase_t += delta
	var m: MatchController = main.match_ctrl
	var car := m.player_car
	var cam: Camera3D = main.camera
	if phase_t > 0.6:
		var vp := get_viewport().get_visible_rect().size
		var p := car.pos + car.up() * 0.3
		var margin := -1000.0
		if not cam.is_position_behind(p):
			var sp := cam.unproject_position(p)
			margin = minf(minf(sp.x, vp.x - sp.x), minf(sp.y, vp.y - sp.y))
		worst[phase] = minf(worst[phase], margin)
		if margin < 20:
			print("   t=%.2f car=%s up=%s cam=%s dist=%.2f margin=%.0f grounded=%s" % [phase_t, car.pos.snapped(Vector3.ONE*0.1), car.up().snapped(Vector3.ONE*0.01), cam.global_position.snapped(Vector3.ONE*0.1), cam.global_position.distance_to(car.pos), margin, car.num_contacts])
		var nm: String = phases[phase][0]
		if phase_t > phases[phase][1] * 0.6 and not shots_taken.has(nm):
			shots_taken[nm] = true
			get_viewport().get_texture().get_image().save_png(ProjectSettings.globalize_path(out + "cam_" + nm + ".png"))
	if phase_t >= phases[phase][1]:
		print("%s: worst car margin to screen edge = %.0f px %s" % [phases[phase][0], worst[phase], "OK" if worst[phase] > 20 else "CAR LEFT VIEW"])
		if phase + 1 < phases.size():
			_start_phase(phase + 1)
		else:
			get_tree().quit()
