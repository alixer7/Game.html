extends Node
## Headless physics checks. Run:
## godot --headless --path . res://tests/physics_test.tscn

var world: SimWorld
var car: CarSim
var t := 0
var phase := 0
var log_lines: Array[String] = []
var max_h := 0.0
var data := {}

class Scripted:
	var car: CarSim
	var fn: Callable
	func update_controls(dt: float) -> void:
		fn.call(car, dt)

var script_fn: Callable = func(_c, _d): pass

func _ready() -> void:
	world = SimWorld.new()
	world.running = false
	add_child(world)
	car = CarSim.new()
	car.setup(0)
	var ctrl := Scripted.new()
	ctrl.car = car
	ctrl.fn = func(c, d): script_fn.call(c, d)
	world.add_car(car, ctrl)
	car.place(Vector3(0, 0.5, 20), 0.0)
	world.ball.reset(Vector3(10, 5, 0))

func _physics_process(_d: float) -> void:
	t += 1
	if t < 3:
		return
	world.step(Phys.DT)
	var s := t - 3
	match phase:
		0: # settle
			if s == 1:
				print("ball sdf ", ArenaGeo.sdf(Vector3(0,1,0)), " corner ", ArenaGeo.sdf(Vector3(40,1,0)))
			if s == 240:
				print("REST car y=%.3f contacts=%d up=%s ball y=%.3f vy=%.3f" % [car.pos.y, car.num_contacts, car.basis.y, world.ball.pos.y, world.ball.vel.y])
				_next(func(c, d): c.controls.throttle = 1.0)
		1: # throttle only
			if s == 1 + 600:
				print("THROTTLE 5s speed=%.2f (expect ~14.1)" % car.vel.length())
				_next(func(c, d): c.controls.throttle = 1.0; c.controls.boost = true)
		2:
			if s == 1 + 1200 + 240:
				print("BOOST speed=%.2f (expect 23) boost=%.1f supersonic=%s pos=%s" % [car.vel.length(), car.boost, car.supersonic, car.pos])
				car.place(Vector3(0, 0.5, 0), 0.0)
				_next(func(c, d): c.controls.reset())
		3:
			if s == 1440 + 120:
				var y0 := car.pos.y
				data["y0"] = y0
				max_h = 0.0
				_next(func(c, d): c.controls.jump = true)
		4:
			max_h = maxf(max_h, car.pos.y - data["y0"])
			if s == 1560 + 240:
				print("JUMP max height=%.3f (expect ~2.3)" % max_h)
				max_h = 0.0
				var seq := [0]
				_next(func(c, d):
					seq[0] += 1
					c.controls.jump = seq[0] < 10 or (seq[0] > 30 and seq[0] < 40))
		5:
			max_h = maxf(max_h, car.pos.y - data["y0"])
			if s == 1800 + 300:
				print("DOUBLE JUMP max height=%.3f (expect ~4.6)" % max_h)
				data["fz"] = car.pos.z
				var seq := [0]
				_next(func(c, d):
					seq[0] += 1
					c.controls.pitch = 1.0
					c.controls.jump = seq[0] < 8 or (seq[0] > 20 and seq[0] < 25))
		6:
			if s == 2100 + 30:
				print("FLIP started flipping=%s vel=%s" % [car.is_flipping, car.vel])
			if s == 2100 + 200:
				print("FLIP after: on_ground=%s up=%s speed=%.2f dz=%.2f" % [car.on_ground, car.basis.y, car.vel.length(), car.pos.z - data["fz"]])
				# drive into side wall
				car.place(Vector3(20, 0.3, 0), -PI * 0.5)
				_next(func(c, d): c.controls.throttle = 1.0; c.controls.boost = true)
		7:
			if (s - 2300) % 60 == 0:
				print("WALL t=%.2f pos=%s up=%s contacts=%d speed=%.1f" % [(s - 2300) / 120.0, car.pos, car.basis.y.snapped(Vector3.ONE*0.01), car.num_contacts, car.vel.length()])
			if s == 2300 + 300:
				var bb := world.ball
				bb.reset(Vector3(0, 10, -20))
				bb.vel = Vector3(5, 0, 0)
				max_h = 0.0
				car.place(Vector3(0, 0.3, 30), 0.0)
				_next(func(c, d): c.controls.reset())
		8:
			if (s - 2600) % 60 == 0:
				print("BALL t=%.1f pos=%s vel=%s spin=%s" % [(s - 2600) / 120.0, world.ball.pos.snapped(Vector3.ONE*0.01), world.ball.vel.snapped(Vector3.ONE*0.01), world.ball.ang_vel.snapped(Vector3.ONE*0.01)])
			if s == 2600 + 600:
				# car hits ball at full speed
				world.ball.reset(Vector3(0, Phys.BALL_R, -10))
				car.place(Vector3(0, 0.17, 20), 0.0)
				car.vel = Vector3(0, 0, -23)
				_next(func(c, d): c.controls.throttle = 1.0; c.controls.boost = true)
		9:
			if world.ball.touched and not data.has("hit"):
				data["hit"] = true
				print("HIT ball speed after=%.2f vel=%s" % [world.ball.vel.length(), world.ball.vel])
			if s == 3200 + 240:
				print("after hit ball pos=%s" % world.ball.pos)
				var t0 := Time.get_ticks_usec()
				for i in 200:
					world.step(Phys.DT)
				print("PERF 200 steps 1 car: %.3f ms/step" % ((Time.get_ticks_usec() - t0) / 200000.0))
				get_tree().quit()

func _next(fn: Callable) -> void:
	script_fn = fn
	phase += 1
