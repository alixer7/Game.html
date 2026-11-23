extends Node
## Rendered verification: builds the race scene, captures landmark views and
## gameplay views to tests/results/shots/*.png, logs draw calls / primitives /
## frame time per view to tests/results/render.json.
## Run with a real renderer (see tools/build.sh shots).

var scene: Node3D
var out := {}


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://tests/results/shots"))
	Game.race.mode = "race"
	Game.race.racers = 8
	Game.settings["quality"] = int(OS.get_environment("WK_QUALITY")) if OS.get_environment("WK_QUALITY") != "" else 2
	scene = load("res://scenes/race.tscn").instantiate()
	add_child(scene)
	_run.call_deferred()


func _wait(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _shot(name: String) -> void:
	await _wait(4)
	var t0 := Time.get_ticks_usec()
	await _wait(3)
	var ft := float(Time.get_ticks_usec() - t0) / 3.0 / 1000.0
	var img := get_viewport().get_texture().get_image()
	img.save_png("res://tests/results/shots/%s.png" % name)
	out[name] = {
		"draw_calls": RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME),
		"primitives": RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME),
		"objects": RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_OBJECTS_IN_FRAME),
		"frame_ms_software_renderer": snappedf(ft, 0.1),
		"video_mem_mb": snappedf(RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_VIDEO_MEM_USED) / 1048576.0, 0.1),
	}
	print("shot %s %s" % [name, out[name]])


func _run() -> void:
	while scene.get("tb") == null or scene.get("cam") == null:
		await _wait(5)
	await _wait(30)
	var tb: TrackBuilder = scene.get("tb")
	var cam: ChaseCamera = scene.get("cam")
	cam.set_physics_process(false)
	scene.set("_state", "screens")
	var views := [
		["start_grid", "start_line", Vector3(0, 6, 22), Vector3(0, 1, -20)],
		["roof_lip", "roof_pad", Vector3(-8, 5, 14), Vector3(10, -6, -30)],
		["portal_river", "river_land", Vector3(18, 7, 26), Vector3(-25, 2, -35)],
		["river_rocks", "rock_garden_1", Vector3(0, 4, 14), Vector3(0, 0, -25)],
		["moss_arch", "gravel_bar", Vector3(-30, 8, 30), Vector3(30, 6, -30)],
		["lower_falls", "falls_land", Vector3(10, 6, 18), Vector3(-10, 0, -30)],
		["fernway", "crest_1", Vector3(0, 3, 12), Vector3(0, 0, -30)],
		["giants_log", "log_entry", Vector3(-10, 6, 16), Vector3(10, 2, -30)],
		["ruins_owl", "flytraps", Vector3(-6, 4, 16), Vector3(8, 4, -30)],
		["millrace", "flume_kicker", Vector3(10, 8, 20), Vector3(-20, 0, -30)],
		["hairpin", "hairpin", Vector3(8, 10, 18), Vector3(-15, 0, -20)],
		["elder_tree", "crest_1", Vector3(-20, 25, 60), Vector3(-60, 18, -40)],
	]
	for v in views:
		var m: String = v[1]
		if not tb.marks.has(m):
			continue
		var p := tb.mark_pos(m)
		var h := tb.heading_dir(m)
		var r := Vector3(-h.z, 0, h.x)
		var off: Vector3 = v[2]
		var look: Vector3 = v[3]
		var eye := p - h * off.z + r * off.x + Vector3.UP * off.y
		var tgt := p - h * look.z + r * look.x + Vector3.UP * look.y
		cam.global_position = eye
		cam.look_at(tgt, Vector3.UP)
		await _shot(v[0])
	# gameplay views: race behind the player for a while
	cam.set_physics_process(true)
	scene.set("_state", "countdown")
	var race: RaceManager = scene.get("race")
	race.start_countdown()
	var player: Kart = scene.get("player")
	var race_frames := int(OS.get_environment("WK_RACE_FRAMES")) if OS.get_environment("WK_RACE_FRAMES") != "" else 40
	await _wait(race_frames)
	for i in 3:
		player.in_throttle = 1.0
		await _wait(race_frames)
		await _shot("race_%d" % i)
	var f := FileAccess.open("res://tests/results/render.json", FileAccess.WRITE)
	f.store_string(JSON.stringify({"views": out, "build_ms": scene.get("build_ms"), "timings": tb.timings, "adapter": RenderingServer.get_video_adapter_name(), "renderer": ProjectSettings.get_setting("rendering/renderer/rendering_method")}, "  "))
	get_tree().quit()
