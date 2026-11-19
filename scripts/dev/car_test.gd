extends Node3D
# Dev harness: (1) renders every car body in a studio, (2) runs a physics test on
# the highway (0-100, top speed, braking, drift) and prints the results.

var world: World
var cam: Camera3D
var mode := ""
var frame := 0
var car: Car
var t := 0.0
var phase := 0
var log_lines := []
var hit100 := -1.0
var vmax := 0.0
var brake_start := 0.0
var brake_v := 0.0


func _ready():
	mode = OS.get_environment("CAR_TEST")
	if mode == "studio":
		_studio()
	else:
		await _physics_test()


func _studio():
	var env := GameEnv.new()
	add_child(env)
	env.setup(2, 1, 1.0)
	var ground := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(200, 200)
	ground.mesh = pm
	ground.material_override = Mats.triplanar(0, 0.2, Color(1.2, 1.2, 1.2))
	add_child(ground)
	var styles := ["supercar", "hyper", "coupe", "muscle", "hatch", "sedan", "police", "suv", "van", "pickup", "truck", "sedan_t"]
	var cols := [Color(0.75, 0.04, 0.03), Color(0.1, 0.1, 0.12), Color(0.08, 0.32, 0.62), Color(0.95, 0.65, 0.05), Color(0.92, 0.92, 0.95), Color(0.25, 0.27, 0.3), Color(0.05, 0.05, 0.06), Color(0.3, 0.3, 0.33), Color(0.95, 0.95, 0.95), Color(0.6, 0.1, 0.08), Color(0.12, 0.3, 0.6), Color(0.98, 0.78, 0.05)]
	for i in styles.size():
		var m := CarModel.new()
		add_child(m)
		m.build(styles[i], cols[i], i)
		m.position = Vector3((i % 4) * 8.0 - 12.0, 0, (i / 4) * 9.0 - 9.0)
		m.rotation.y = deg_to_rad(-35.0)
	cam = Camera3D.new()
	add_child(cam)
	cam.position = Vector3(-4, 9, 22)
	cam.look_at(Vector3(-2, 0, 0))
	cam.fov = 55


func _process(_d):
	frame += 1
	if mode == "studio":
		if frame == 20:
			cam.position = Vector3(-4, 9, 22)
			cam.look_at(Vector3(-2, 0, 0))
		if frame == 30:
			get_viewport().get_texture().get_image().save_png(OS.get_environment("SHOT_DIR") + "/cars_all.png")
			cam.position = Vector3(-15.5, 1.5, -4.5)
			cam.look_at(Vector3(-12, 0.7, -9))
			cam.fov = 40
		if frame == 40:
			get_viewport().get_texture().get_image().save_png(OS.get_environment("SHOT_DIR") + "/cars_close.png")
			cam.position = Vector3(-6.5, 1.3, -12.5)
			cam.look_at(Vector3(-4, 0.6, -9))
		if frame == 50:
			get_viewport().get_texture().get_image().save_png(OS.get_environment("SHOT_DIR") + "/cars_close2.png")
			cam.position = Vector3(5.0, 1.8, 3.5)
			cam.look_at(Vector3(4, 0.7, 0))
		if frame == 60:
			get_viewport().get_texture().get_image().save_png(OS.get_environment("SHOT_DIR") + "/cars_close3.png")
			get_tree().quit()


func _physics_test():
	world = World.new()
	add_child(world)
	Game.world = world
	await world.build_async()
	var sm := SkidMarks.new()
	add_child(sm)
	car = Car.new()
	add_child(car)
	var id := OS.get_environment("CAR_ID")
	if id == "":
		id = "falcon"
	car.setup(id, Color(0.8, 0.1, 0.05), world, true)
	world.register_vehicle(car)
	# highway start: H1 sample near the west straight
	var r: Dictionary = world.data.roads[0]
	var k := int(r.pv.size() * 0.62)
	var p: Vector3 = r.pv[k]
	var tdir := world.data.road_tangent(0, k)
	car.place(p + tdir.cross(Vector3.UP).normalized() * -5.0 + Vector3(0, 0.3, 0), atan2(-tdir.x, -tdir.z))
	cam = ChaseCamera.new()
	add_child(cam)
	cam.current = true
	cam.set_target(car)
	Game.camera = cam
	phase = 1


func _physics_process(dt):
	if phase == 0 or car == null:
		return
	t += dt
	var kmh := car.kmh()
	if Engine.get_physics_frames() % 60 == 0:
		print("[cartest] phase=%d t=%.1f kmh=%.0f gear=%d rpm=%.0f grounded=%d surf=%s pos=%s up=%.2f thr=%.1f" % [phase, t, kmh, car.gear, car.rpm, car.grounded, car.surface, str(car.global_position.round()), car.global_transform.basis.y.y, car.throttle])
	vmax = maxf(vmax, kmh)
	match phase:
		1:
			# settle
			if t > 1.5:
				phase = 2
				t = 0.0
		2:
			car.throttle = 1.0
			car.steer_in = _keep_lane()
			if hit100 < 0.0 and kmh >= 100.0:
				hit100 = t
				log_lines.append("0-100 km/h: %.2f s" % t)
			if t > 32.0:
				log_lines.append("speed after 32 s: %.0f km/h (gear %d, rpm %.0f)" % [kmh, car.gear, car.rpm])
				phase = 3
				t = 0.0
				brake_v = kmh
		3:
			car.throttle = 0.0
			car.brake_in = 1.0
			car.steer_in = _keep_lane()
			if kmh < 2.0:
				log_lines.append("braking %.0f->0 in %.2f s" % [brake_v, t])
				phase = 4
				t = 0.0
		4:
			car.brake_in = 0.0
			car.throttle = 1.0
			car.steer_in = _keep_lane()
			if kmh > 90.0:
				phase = 5
				t = 0.0
		5:
			# handbrake turn-in then power-on drift
			car.steer_in = -1.0 if t < 0.6 else 0.35
			car.handbrake = t < 0.5
			car.throttle = 0.7
			if t > 0.3:
				log_lines.append("t=%.1f drift=%.1f deg speed=%.0f yaw_rate=%.2f" % [t, rad_to_deg(car.drift_angle), kmh, car.angular_velocity.y])
			if t > 3.0:
				phase = 6
		6:
			for l in log_lines:
				print("[cartest] ", l)
			if DisplayServer.get_name() != "headless":
				get_viewport().get_texture().get_image().save_png(OS.get_environment("SHOT_DIR") + "/drive_%s.png" % car.car_id)
			get_tree().quit()


func _keep_lane() -> float:
	var nr := world.data.nearest_road(car.global_position, 60.0)
	if nr.is_empty():
		return 0.0
	var tdir := world.data.road_tangent(nr.road, nr.idx)
	var fwd := -car.global_transform.basis.z
	if tdir.dot(fwd) < 0:
		tdir = -tdir
	var k2 := mini(nr.idx + 12, world.data.roads[nr.road].pv.size() - 1)
	var ahead: Vector3 = world.data.roads[nr.road].pv[k2] + tdir.cross(Vector3.UP).normalized() * -5.0
	var loc := car.to_local(ahead)
	return clampf(atan2(loc.x, -loc.z) * 2.5, -1.0, 1.0)
