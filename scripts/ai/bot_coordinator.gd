class_name BotCoordinator
extends RefCounted
## Assigns team roles (attacker / support / defender) and kickoff takers.

enum Role { ATTACK, SUPPORT, DEFEND }

var world: SimWorld
var pred: BallPredictor
var roles := {}
var kicker := {0: -1, 1: -1}
var kick_support := {0: -1, 1: -1}
var _last := -1000


func _init(w: SimWorld, p: BallPredictor) -> void:
	world = w
	pred = p


func is_kickoff() -> bool:
	var b := world.ball
	return not b.touched and Vector2(b.pos.x, b.pos.z).length() < 0.6 and b.vel.length() < 0.5


func refresh() -> void:
	if world.tick - _last < 10:
		return
	_last = world.tick
	var b := world.ball.pos
	for team in [0, 1]:
		var members: Array = []
		for car in world.cars:
			if car.team == team and not car.demolished:
				members.append(car)
		var scored: Array = []
		for car in members:
			scored.append([_score(car, b), car])
		scored.sort_custom(func(x, y): return x[0] < y[0])
		for i in range(scored.size()):
			var car: CarSim = scored[i][1]
			if i == 0:
				roles[car.id] = Role.ATTACK
			elif i == scored.size() - 1 and scored.size() >= 2:
				roles[car.id] = Role.DEFEND if scored.size() >= 3 or _behind_needed(team) else Role.SUPPORT
			else:
				roles[car.id] = Role.SUPPORT
		if is_kickoff():
			var best := -1
			var best_d := 1e9
			var second := -1
			var second_d := 1e9
			for car in members:
				var d: float = Vector2(car.pos.x, car.pos.z).length() + (0.01 if car.pos.x * (1.0 if team == 0 else -1.0) < 0.0 else 0.0)
				if d < best_d:
					second = best
					second_d = best_d
					best_d = d
					best = car.id
				elif d < second_d:
					second_d = d
					second = car.id
			kicker[team] = best
			kick_support[team] = second


func _behind_needed(team: int) -> bool:
	# In 2v2 keep the second player back when the ball is in our half.
	var own_z := Phys.own_goal_z(team)
	return world.ball.pos.z * signf(own_z) > -5.0


func _score(car: CarSim, b: Vector3) -> float:
	var to := Vector3(b.x - car.pos.x, 0, b.z - car.pos.z)
	var d := to.length()
	var f := car.forward()
	var ff := Vector3(f.x, 0, f.z).normalized()
	var facing := ff.dot(to / maxf(d, 0.01))
	var t := d / maxf(12.0, car.vel.length()) + (1.0 - facing) * 0.45
	# offside: car is between the ball and the opponent goal
	var ad := Phys.attack_dir(car.team)
	if (car.pos.z - b.z) * ad > 3.0:
		t += 1.8
	if car.demolished:
		t += 100.0
	return t


func role_of(car: CarSim) -> int:
	return roles.get(car.id, Role.ATTACK)
