extends Node
## Headless bot match: reports touches, goals and performance.
var world: SimWorld
var pred: BallPredictor
var coord: BotCoordinator
var t := 0
var goals := [0, 0]
var touches := {}
var aerials := 0
var max_ball_speed := 0.0
var sim_seconds := 120.0
var level := 2
var team_size := 2
var elapsed_us := 0
var solo := false
var goal_times: Array = []
var last_goal_t := 0.0
var rng := RandomNumberGenerator.new()

func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	for a in args:
		if a.begins_with("level="): level = int(a.split("=")[1])
		if a.begins_with("size="): team_size = int(a.split("=")[1])
		if a.begins_with("secs="): sim_seconds = float(a.split("=")[1])
		if a == "solo": solo = true
	world = SimWorld.new()
	world.running = false
	add_child(world)
	pred = BallPredictor.new(world)
	coord = BotCoordinator.new(world, pred)
	var n := 1 if solo else team_size * 2
	for i in range(n):
		var c := CarSim.new()
		c.setup(i % 3)
		c.team = i % 2
		var bot := BotController.new(c, world, pred, coord, level)
		world.add_car(c, bot)
	world.goal_scored.connect(func(team, scorer):
		goals[team] += 1
		goal_times.append(world.tick * Phys.DT - last_goal_t)
		last_goal_t = world.tick * Phys.DT
		print("GOAL team %d at %.1fs by car %d  score %d-%d" % [team, world.tick * Phys.DT, scorer, goals[0], goals[1]])
		_kickoff())
	world.ball_touched.connect(func(id, s):
		touches[id] = touches.get(id, 0) + 1
		if solo:
			var bc: BotController = world.controllers[id]
			var c0 := world.cars[id]
			var bv := world.ball.vel
			var to_goal := (Vector3(0, 0, -52) - world.ball.pos).normalized()
			print("TOUCH %.2f str=%.1f car=%s ball=%s bvel=%s spd=%.1f shot=%s goaldot=%.2f man=%d" % [world.tick * Phys.DT, s, c0.pos.snapped(Vector3.ONE*0.1), world.ball.pos.snapped(Vector3.ONE*0.1), bv.snapped(Vector3.ONE*0.1), bv.length(), bc.shot_dir.snapped(Vector3.ONE*0.01), Vector3(bv.x,0,bv.z).normalized().dot(Vector3(to_goal.x,0,to_goal.z).normalized()), bc.man]))
	_kickoff()

func _kickoff() -> void:
	world.ball.reset(Vector3(0, Phys.BALL_R, 0))
	if solo:
		world.ball.reset(Vector3(rng.randf_range(-30, 30), Phys.BALL_R + rng.randf_range(0, 6), rng.randf_range(-30, 30)))
		world.ball.vel = Vector3(rng.randf_range(-8, 8), rng.randf_range(0, 6), rng.randf_range(-8, 8))
		world.ball.touched = true
	world.reset_pads()
	var spots := [[0, 1], [0, 1], [2, 3]]
	var per_team := {0: 0, 1: 0}
	for c in world.cars:
		var k: int = per_team[c.team]
		per_team[c.team] += 1
		var spot_list := [0, 1, 4] if team_size == 3 else ([0, 1] if team_size == 2 else [4])
		var tf := SimWorld.kickoff_transform(c.team, spot_list[k % spot_list.size()])
		c.place(tf[0], tf[1])
		c.boost = Phys.BOOST_KICKOFF
	world.goal_enabled = true

func _physics_process(_d: float) -> void:
	t += 1
	if t < 3: return
	var t0 := Time.get_ticks_usec()
	world.step(Phys.DT)
	elapsed_us += Time.get_ticks_usec() - t0
	max_ball_speed = maxf(max_ball_speed, world.ball.vel.length())
	for c in world.cars:
		var bot: BotController = world.controllers[c.id]
		if bot.man == BotController.Man.AERIAL and bot.m_time < Phys.DT * 1.5:
			aerials += 1
	if false:
		var c0 := world.cars[0]
		var b0: BotController = world.controllers[0]
		print("%.2f car=%s v=%.1f ball=%s bv=%.1f tgt=%s ht=%.2f man=%d ground=%s thr=%.1f st=%.1f boost=%s" % [world.tick * Phys.DT, c0.pos.snapped(Vector3.ONE*0.1), c0.vel.length(), world.ball.pos.snapped(Vector3.ONE*0.1), world.ball.vel.length(), b0.target.snapped(Vector3.ONE*0.1), b0.hit_time - b0.now, b0.man, c0.on_ground, c0.controls.throttle, c0.controls.steer, c0.controls.boost])
	if (t - 3) % 1200 == 0:
		var s := ""
		for c in world.cars:
			s += "[c%d t%d %s b%.0f r%d] " % [c.id, c.team, c.pos.snapped(Vector3.ONE * 0.1), c.boost, coord.role_of(c)]
		print("t=%.0f ball=%s %s" % [world.tick * Phys.DT, world.ball.pos.snapped(Vector3.ONE * 0.1), s])
	if world.tick * Phys.DT >= sim_seconds:
		print("goal times: ", goal_times)
		print("RESULT goals=%s touches=%s aerials=%d max_ball=%.1f avg_step=%.3fms" % [goals, touches, aerials, max_ball_speed, elapsed_us / 1000.0 / world.tick])
		get_tree().quit()
