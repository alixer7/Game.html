extends Node
## Headless test runner (a scene, so project autoloads exist).
##   godot --headless --path . --fixed-fps 60 res://tests/test_main.tscn -- [physics] [track] [ai] [routes]
## Writes tests/results/<suite>.json and prints a summary. Exit code = number of failures.

var failures := 0
var report := {}
var _suites: PackedStringArray


func _ready() -> void:
	_suites = OS.get_cmdline_user_args()
	if _suites.is_empty():
		_suites = PackedStringArray(["physics", "track", "ai", "routes"])
	_run.call_deferred()


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://tests/results"))
	for s in _suites:
		print("\n==== suite: %s ====" % s)
		var t0 := Time.get_ticks_msec()
		match s:
			"physics":
				await PhysicsTests.new().run(self)
			"track":
				await TrackTests.new().run(self)
			"ai":
				await AITests.new().run(self, false)
			"routes":
				await AITests.new().run(self, true)
			"jumps":
				await JumpTests.new().run(self)
		print("suite %s took %.1f s" % [s, (Time.get_ticks_msec() - t0) / 1000.0])
	var f := FileAccess.open("res://tests/results/summary.json", FileAccess.WRITE)
	f.store_string(JSON.stringify(report, "  "))
	print("\n==== %d failure(s) ====" % failures)
	get_tree().quit(failures)


func check(suite: String, name: String, ok: bool, detail: Variant = null) -> void:
	if not report.has(suite):
		report[suite] = []
	report[suite].append({"test": name, "ok": ok, "detail": detail})
	print("[%s] %s  %s" % ["PASS" if ok else "FAIL", name, "" if detail == null else str(detail)])
	if not ok:
		failures += 1


func frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame
