extends Node
## Debug: what the frame is made of. Renders the race at a few views and, per
## view, hides one category at a time (grass, trees, bushes, terrain, roads ...)
## to measure its draw calls / primitives (incl. shadow passes).
##   xvfb + lavapipe:  godot --path . res://tests/debug/render_breakdown.tscn -- <quality>

var scene: Node3D


func _ready() -> void:
	var a := OS.get_cmdline_user_args()
	Game.race.mode = "race"
	Game.race.racers = 8
	Game.settings["quality"] = int(a[0]) if a.size() > 0 else 1
	scene = load("res://scenes/race.tscn").instantiate()
	add_child(scene)
	_run.call_deferred()


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _measure() -> Vector3:
	await _frames(3)
	return Vector3(RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME),
		RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME),
		RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_OBJECTS_IN_FRAME))


func _groups(tb: TrackBuilder) -> Dictionary:
	var g := {}
	var track := tb.root
	for c in track.get_node("Scatter").get_children():
		var nm := String(c.name)
		var key := "scatter:" + nm.get_slice("_", 0)
		if nm.begins_with("ScatterColliders"):
			continue
		if not g.has(key):
			g[key] = []
		g[key].append(c)
	for c in track.get_children():
		var nm := String(c.name)
		if nm in ["Scatter"]:
			continue
		if not g.has(nm):
			g[nm] = []
		g[nm].append(c)
	return g


func _run() -> void:
	while scene.get("tb") == null or scene.get("cam") == null:
		await _frames(5)
	await _frames(20)
	var tb: TrackBuilder = scene.get("tb")
	var cam: ChaseCamera = scene.get("cam")
	cam.set_physics_process(false)
	scene.set("_state", "screens")
	var views := [["start_grid", "start_line", Vector3(0, 3, 9), Vector3(0, 1, -30)], ["river", "rock_garden_1", Vector3(0, 3, 9), Vector3(0, 0, -30)],
		["fernway", "crest_1", Vector3(0, 3, 9), Vector3(0, 0, -30)], ["millrace", "flume_kicker", Vector3(0, 3, 9), Vector3(0, 0, -30)]]
	var groups := _groups(tb)
	var out := {}
	for v in views:
		var p := tb.mark_pos(v[1])
		var h := tb.heading_dir(v[1])
		var r := Vector3(-h.z, 0, h.x)
		var off: Vector3 = v[2]
		var look: Vector3 = v[3]
		cam.global_position = p - h * off.z + r * off.x + Vector3.UP * off.y
		cam.look_at(p - h * look.z + r * look.x + Vector3.UP * look.y, Vector3.UP)
		var base := await _measure()
		var row := {"total": [base.x, base.y, base.z]}
		for gname in groups:
			for n in groups[gname]:
				(n as Node3D).visible = false
			var m := await _measure()
			for n in groups[gname]:
				(n as Node3D).visible = true
			var d := base - m
			if d.y > 5000 or d.x > 10:
				row[gname] = [d.x, d.y, d.z]
		out[v[0]] = row
		print("VIEW ", v[0], " ", JSON.stringify(row))
	var sun: DirectionalLight3D = scene.get("sun")
	if sun:
		var with_sh := await _measure()
		sun.shadow_enabled = false
		var no_sh := await _measure()
		print("SHADOWS last view: with ", with_sh, " without ", no_sh)
	get_tree().quit()
