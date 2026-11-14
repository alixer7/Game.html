class_name BallPredictor
extends RefCounted
## Simulates the ball ahead of time (ignoring cars) with the real ball physics.

const STEP := 1.0 / 30.0
const HORIZON := 4.0

var world: SimWorld
var pos := PackedVector3Array()
var vel := PackedVector3Array()
var goal_time := -1.0
var goal_side := 0          # +1 = ball enters +Z goal (blue's), -1 = -Z goal
var updated_tick := -1000
var _sim := BallSim.new()
var _last_vel := Vector3.ZERO


func _init(w: SimWorld) -> void:
	world = w


## Refreshes the prediction every `interval` ticks or after the ball changed course.
func maybe_update(interval: int = 6) -> void:
	var b := world.ball
	var dv := b.vel.distance_to(_last_vel)
	if world.tick - updated_tick >= interval or dv > 2.5 or b.last_touch_tick == world.tick:
		update()


func update() -> void:
	updated_tick = world.tick
	_last_vel = world.ball.vel
	_sim.copy_from(world.ball)
	pos.clear()
	vel.clear()
	goal_time = -1.0
	goal_side = 0
	var steps := int(HORIZON / STEP)
	pos.append(_sim.pos)
	vel.append(_sim.vel)
	var done := false
	for i in range(steps):
		if not done:
			var sub := maxi(1, ceili(_sim.vel.length() * STEP / 0.7))
			var h := STEP / sub
			for k in range(sub):
				_sim.integrate(h)
				world.ball_arena_collide(_sim)
			if absf(_sim.pos.z) > Phys.HALF_L + Phys.BALL_R:
				goal_time = (i + 1) * STEP
				goal_side = 1 if _sim.pos.z > 0.0 else -1
				done = true
		pos.append(_sim.pos)
		vel.append(_sim.vel)


func count() -> int:
	return pos.size()


func time_of(i: int) -> float:
	return i * STEP


func pos_at_time(t: float) -> Vector3:
	var i := clampi(int(t / STEP), 0, pos.size() - 1)
	var j := mini(i + 1, pos.size() - 1)
	var f := clampf(t / STEP - i, 0.0, 1.0)
	return pos[i].lerp(pos[j], f)


## True if the ball is predicted to enter the goal defended by `team` within t_max.
func threatens(team: int, t_max: float = 3.0) -> bool:
	if goal_time < 0.0 or goal_time > t_max:
		return false
	var own_side := 1 if team == 0 else -1
	return goal_side == own_side
