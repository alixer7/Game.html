extends Node
## Car/arena edge cases: full-speed wall climbs, corners, goal entry.
var world: SimWorld
var car: CarSim
var t := 0
var scen := 0
var s0 := 0
var scrape := 0
var max_pen := 0.0
var max_y := 0.0
var log_every := 30
class Ctl:
	var car: CarSim
	var thr := 1.0
	var boost := true
	var steer := 0.0
	func update_controls(_dt: float) -> void:
		car.controls.throttle = thr
		car.controls.boost = boost
		car.controls.steer = steer
var ctl := Ctl.new()
var scenarios := [
	["side wall perpendicular", Vector3(10, 0.17, 0), -PI * 0.5, 0.0, 360],
	["end wall beside goal", Vector3(20, 0.17, 20), 0.0, 0.0, 300],
	["corner diagonal", Vector3(10, 0.17, -20), PI * 0.75 - PI, 0.0, 300],
	["into goal", Vector3(0, 0.17, 20), PI, 0.0, 240],
	["along wall curve", Vector3(35, 0.17, 30), 0.0, -0.15, 400],
]
func _ready() -> void:
	world = SimWorld.new(); world.running = false; add_child(world)
	car = CarSim.new(); car.setup(0); ctl.car = car
	world.add_car(car, ctl)
	world.ball.reset(Vector3(0, -50, 0))
	world.ball_frozen = true
	world.goal_enabled = false
	_start(0)
func _start(i: int) -> void:
	scen = i; s0 = t; scrape = 0; max_y = 0.0
	var sc: Array = scenarios[i]
	car.place(sc[1], sc[2])
	car.boost = 100
	car.vel = -car.basis.z * 14.0
	ctl.steer = sc[3]
	print("=== ", sc[0])
func _physics_process(_d: float) -> void:
	t += 1
	if t < 3: return
	world.step(Phys.DT)
	car.boost = 100
	var k := t - s0
	if car.body_touching and car.num_contacts >= 2: scrape += 1
	max_y = maxf(max_y, car.pos.y)
	if scen == 2 and k > 170 and k < 215 and k % 2 == 0:
		print("    k=%d pos=%s v=%s up=%s wheels=%d body=%s bn=%s cn=%s" % [k, car.pos.snapped(Vector3.ONE * 0.01), car.vel.snapped(Vector3.ONE * 0.1), car.basis.y.snapped(Vector3.ONE * 0.01), car.num_contacts, car.body_touching, car.body_normal.snapped(Vector3.ONE*0.01), car.contact_normal.snapped(Vector3.ONE*0.01)])
	if k % log_every == 0:
		print("  t=%.2f pos=%s v=%.1f up=%s wheels=%d body=%s sdf=%.2f" % [k / 120.0, car.pos.snapped(Vector3.ONE * 0.1), car.vel.length(), car.basis.y.snapped(Vector3.ONE * 0.01), car.num_contacts, car.body_touching, ArenaGeo.sdf(car.pos)])
	if k >= scenarios[scen][4]:
		print("  scrape ticks=%d max_y=%.1f final pos=%s" % [scrape, max_y, car.pos.snapped(Vector3.ONE * 0.1)])
		if scen + 1 < scenarios.size():
			_start(scen + 1)
		else:
			get_tree().quit()
