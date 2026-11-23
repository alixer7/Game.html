extends Node
## Debug: CPU cost of a full race. Loads the race scene (8 karts, the player
## driven by an Expert AI), runs it and reports per-frame process / physics time.
##   godot --headless --path . res://tests/debug/perf_probe.tscn -- <seconds> [quality]

var scene: Node3D
var samples_proc := PackedFloat32Array()
var samples_phys := PackedFloat32Array()
var samples_frame := PackedFloat32Array()


func _ready() -> void:
	var a := OS.get_cmdline_user_args()
	Game.race.mode = "race"
	Game.race.racers = 8
	Game.settings["quality"] = int(a[1]) if a.size() > 1 else 1
	scene = load("res://scenes/race.tscn").instantiate()
	add_child(scene)
	_run.call_deferred(float(a[0]) if a.size() > 0 else 30.0)


func _run(secs: float) -> void:
	while scene.get("tb") == null or scene.get("race") == null or scene.get("player") == null:
		await get_tree().process_frame
	for i in 10:
		await get_tree().process_frame
	var race: RaceManager = scene.get("race")
	scene.set("_state", "countdown")
	race.start_countdown()
	var player: Kart = scene.get("player")
	(scene.get_node("PlayerDriver") as PlayerDriver).enabled = false
	var ai := AIDriver.new()
	scene.add_child(ai)
	ai.setup(player, scene.get("lanes"), 3, (scene.get("tb") as TrackBuilder).obstacles, 99)
	ai.race = race
	player.set_meta("ai", ai)
	var t_end := Time.get_ticks_msec() + int(secs * 1000.0)
	var last := Time.get_ticks_usec()
	var frames := 0
	while frames < int(secs * 60.0):
		await get_tree().process_frame
		var now := Time.get_ticks_usec()
		samples_frame.append((now - last) / 1000.0)
		last = now
		samples_proc.append(Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0)
		samples_phys.append(Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0)
		frames += 1
	print("PERF frames=%d" % frames)
	_report("process_ms", samples_proc)
	_report("physics_ms", samples_phys)
	_report("frame_ms", samples_frame)
	print("PERF objects=%d nodes=%d" % [Performance.get_monitor(Performance.OBJECT_COUNT), Performance.get_monitor(Performance.OBJECT_NODE_COUNT)])
	get_tree().quit()


func _report(name: String, s: PackedFloat32Array) -> void:
	var arr := Array(s)
	arr.sort()
	var sum := 0.0
	for v in arr:
		sum += v
	var n := arr.size()
	print("PERF %s avg=%.2f p50=%.2f p95=%.2f p99=%.2f max=%.2f" % [name, sum / n, arr[n / 2], arr[int(n * 0.95)], arr[int(n * 0.99)], arr[n - 1]])
