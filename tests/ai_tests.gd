class_name AITests
extends RefCounted
## AI lap test (full field) and route timing comparison (one kart per route).

var R: Object
var T: SceneTree


func run(runner: Object, routes: bool) -> void:
	R = runner
	T = (runner as Node).get_tree()
	if routes:
		await _routes()
	else:
		await _field()


func _world() -> Dictionary:
	var root := Node3D.new()
	T.root.add_child(root)
	var tb := TrackBuilder.new()
	tb.load_track("res://data/timberfall.json")
	tb.build(root, 0)
	var race := RaceManager.new()
	root.add_child(race)
	race.setup(tb, 1)
	race.rubber = 0
	var items := ItemSystem.new()
	items.race = race
	items.world = root
	root.add_child(items)
	var lanes: Dictionary = load("res://scripts/race/race_scene.gd").build_lane_graph(tb)
	return {"root": root, "tb": tb, "race": race, "items": items, "lanes": lanes}


func _add_ai(w: Dictionary, slot: int, diff: int, ch: int, forced := {}) -> Kart:
	var tb: TrackBuilder = w.tb
	var k := Kart.new()
	var c := Game.character(ch)
	k.params = KartParams.make_class(c.chassis)
	k.display_name = c.name
	k.racer_index = slot
	(w.root as Node3D).add_child(k)
	k.add_to_group("karts")
	k.teleport(tb.spawn_grid[slot])
	(w.race as RaceManager).add_kart(k)
	(w.items as ItemSystem).register(k)
	var ai := AIDriver.new()
	(w.root as Node3D).add_child(ai)
	ai.setup(k, w.lanes, diff, tb.obstacles, 1000 + slot)
	ai.race = w.race
	ai.items = w.items
	ai.forced_route = forced
	k.set_meta("ai", ai)
	return k


func _field() -> void:
	for diff: int in [1, 3]:
		var w := _world()
		var race: RaceManager = w.race
		var karts: Array = []
		for s in 8:
			karts.append(_add_ai(w, s, diff, s))
		race.player = karts[0]
		race.start_countdown()
		var limit := 60 * 150
		var done := false
		for i in limit:
			await T.physics_frame
			for k in karts:
				(k as Kart).in_throttle = 1.0 if race.state == "countdown" else (k as Kart).in_throttle
			var all := true
			for k in karts:
				if not race.progress_of(k).finished:
					all = false
			if all:
				done = true
				break
		var times := []
		var stuck := 0
		for k in karts:
			var pr := race.progress_of(k)
			times.append([k.display_name, snappedf(float(pr.finish_time), 0.01) if pr.finished else -1.0, k.stat_sparks, k.stat_perfect, k.stat_impacts])
			if not pr.finished:
				stuck += 1
		R.check("ai", "%s field: all 8 AI finish a lap" % AIDriver.PROFILES[diff].name, done, times)
		var f := FileAccess.open("res://tests/results/ai_field_%d.json" % diff, FileAccess.WRITE)
		f.store_string(JSON.stringify(times, "  "))
		(w.root as Node3D).queue_free()
		await R.frames(3)


func _routes() -> void:
	## Same Expert driver, forced through each route; compares lap times.
	var cases := {
		"baseline (river lane)": {"left_bank": false, "right_bank": false, "giants_log": false, "shelf_rock": false, "millrace_flume": false, "rootway_cave": false, "gate_lane": false},
		"left bank": {"left_bank": true, "right_bank": false, "giants_log": false, "shelf_rock": false, "millrace_flume": false, "rootway_cave": false, "gate_lane": false},
		"right bank": {"left_bank": false, "right_bank": true, "giants_log": false, "shelf_rock": false, "millrace_flume": false, "rootway_cave": false, "gate_lane": false},
		"giants log": {"left_bank": false, "right_bank": false, "giants_log": true, "shelf_rock": false, "millrace_flume": false, "rootway_cave": false, "gate_lane": false},
		"log + shelf": {"left_bank": true, "right_bank": false, "giants_log": true, "shelf_rock": true, "millrace_flume": false, "rootway_cave": false, "gate_lane": false},
		"cave": {"left_bank": false, "right_bank": false, "giants_log": false, "shelf_rock": false, "millrace_flume": false, "rootway_cave": true, "gate_lane": false},
		"flume": {"left_bank": false, "right_bank": false, "giants_log": false, "shelf_rock": false, "millrace_flume": true, "rootway_cave": false, "gate_lane": false},
		"all shortcuts": {"left_bank": true, "right_bank": false, "giants_log": true, "shelf_rock": true, "millrace_flume": true, "rootway_cave": true, "gate_lane": false},
	}
	var out := {}
	for name in cases:
		var w := _world()
		var race: RaceManager = w.race
		var k := _add_ai(w, 0, 3, 0, cases[name])
		race.player = k
		race.laps = 2
		race.start_countdown()
		var lanes_seen := {}
		for i in 60 * 200:
			await T.physics_frame
			if race.state == "countdown":
				k.in_throttle = 1.0
			var ai: AIDriver = k.get_meta("ai")
			lanes_seen[ai.lane] = true
			if race.progress_of(k).finished:
				break
		var pr := race.progress_of(k)
		var lap2: float = (pr.times as Array)[1] if (pr.times as Array).size() > 1 else -1.0
		out[name] = {"lap2": snappedf(lap2, 0.01), "lanes": lanes_seen.keys(), "sparks": k.stat_sparks, "perfect": k.stat_perfect,
			"impacts": k.stat_impacts, "boost_time": snappedf(k.stat_boost_time, 0.1), "od_time": snappedf(k.stat_overdrive_time, 0.1)}
		R.check("routes", "route '%s' completes" % name, pr.finished, out[name])
		(w.root as Node3D).queue_free()
		await R.frames(3)
	var f := FileAccess.open("res://tests/results/routes.json", FileAccess.WRITE)
	f.store_string(JSON.stringify(out, "  "))
