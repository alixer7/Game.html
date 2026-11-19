extends Node
# Dev harness: drives the real game flow automatically and saves screenshots.
# env: SHOT_DIR, GT_EVENT (event id), GT_TIME (seconds of racing)
var main
var t := 0.0
var stage := 0
var shots := 0
var autopilot: RacerAI
var ev_id := ""
var race_time := 40.0
var headless := false

func _ready():
	main = get_parent()
	ev_id = OS.get_environment("GT_EVENT")
	if ev_id == "":
		ev_id = "city_sprint"
	if OS.get_environment("GT_TIME") != "":
		race_time = float(OS.get_environment("GT_TIME"))
	headless = DisplayServer.get_name() == "headless"
	process_mode = Node.PROCESS_MODE_ALWAYS

func _shot(name: String):
	if headless:
		return
	var img := get_viewport().get_texture().get_image()
	img.save_png(OS.get_environment("SHOT_DIR") + "/g_%02d_%s.png" % [shots, name])
	shots += 1

func _process(dt):
	if main.race == null or main.player == null:
		return
	t += dt / maxf(Engine.time_scale, 0.05)
	match stage:
		0:
			if t > 3.0:
				_shot("menu")
				main.menus.show_garage()
				stage = 1
				t = 0.0
		1:
			if t > 1.5:
				_shot("garage")
				main.menus.show_events()
				stage = 2
				t = 0.0
		2:
			if t > 1.5:
				_shot("events")
				for e in main.world.data.events:
					if e.id == ev_id:
						main.menus._select_event(e)
				stage = 3
				t = 0.0
		3:
			if t > 1.0:
				_shot("event_info")
				for e in main.world.data.events:
					if e.id == ev_id:
						main._start_event(e)
						if e.has("route"):
							autopilot = RacerAI.new(main.race.route, 0.0, 0.95)
							autopilot.idx = main.race.route.nearest_global(main.player.global_position)
							main.player.controller = autopilot
				stage = 4
				t = 0.0
		4:
			if autopilot and main.race.state == RaceManager.RACING:
				var obs := []
				for r in main.race.racers:
					if not r.is_player:
						obs.append(r.car)
				obs.append_array(main.traffic.cars)
				autopilot.obstacles = obs
			if fmod(t, float(OS.get_environment("GT_SHOT_EVERY") if OS.get_environment("GT_SHOT_EVERY") != "" else "6")) < dt / maxf(Engine.time_scale, 0.05) and t > 1.0:
				_shot("race_%d" % int(t))
				var pe: Dictionary = main.race.player_entry
				print("[gt] t=%.0f state=%d pos=%s cp=%s lap=%s kmh=%.0f heat=%d units=%d traffic=%d" % [t, main.race.state, str(pe.get("pos", 0)), str(pe.get("cp", 0)), str(pe.get("lap", 0)), main.player.kmh(), main.race.pursuit.heat, main.race.pursuit.units.size(), main.traffic.cars.size()])
				for r in main.race.racers:
					var extra := ""
					if r.car.controller is RacerAI:
						var ai: RacerAI = r.car.controller
						var rt: RaceRoute = ai.route
						extra = " idx=%d d=%.0f vallow=%.0f off=%.1f stuck=%.1f sc=%s pos=%s" % [ai.idx, rt.dist[ai.idx], rt.v_allow[ai.idx] * 3.6, Vector2(rt.pts[ai.idx].x - r.car.global_position.x, rt.pts[ai.idx].z - r.car.global_position.z).length(), ai.stuck_t, str(not ai.shortcut.is_empty()), str(r.car.global_position.round())]
					print("[gt]    ", r.name, " cp=", r.cp, " lap=", r.lap, " kmh=", int(r.car.kmh()), " done=", r.done, extra)
			if t > race_time or main.menus.current == "results":
				_shot("end")
				print("[gt] finished state=", main.race.state, " results=", main.menus.current)
				get_tree().quit()
