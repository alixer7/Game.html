class_name TrackTests
extends RefCounted
## Builds the full track headless and validates its geometry.

var R: Object
var T: SceneTree


func run(runner: Object) -> void:
	R = runner
	T = (runner as Node).get_tree()
	var root := Node3D.new()
	T.root.add_child(root)
	var t0 := Time.get_ticks_msec()
	var tb := TrackBuilder.new()
	tb.load_track("res://data/timberfall.json")
	tb.build(root, 2)
	var ms := Time.get_ticks_msec() - t0
	R.check("track", "track builds (quality high)", tb.root != null, "build ms=%d timings=%s" % [ms, tb.timings])
	R.check("track", "main loop length 1.3-1.7 km", tb.main.length > 1300.0 and tb.main.length < 1700.0, "L=%.0f m" % tb.main.length)
	await R.frames(3)
	var space := root.get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.new()
	q.collision_mask = 1
	# spawn grid on solid road
	var bad := 0
	for xf in tb.spawn_grid:
		q.from = (xf as Transform3D).origin + Vector3.UP * 2.0
		q.to = (xf as Transform3D).origin + Vector3.DOWN * 3.0
		var hit := space.intersect_ray(q)
		if hit.is_empty() or not hit.collider.has_method("surface_at"):
			bad += 1
	R.check("track", "all 8 grid slots on road collision", bad == 0 and tb.spawn_grid.size() == 8, "bad=%d" % bad)
	# every non-gap main sample has ground within 1.2 m below its centre line
	var holes := 0
	var checked := 0
	for i in range(0, tb.main.size(), 4):
		if tb.main.style[i] == "gap":
			continue
		checked += 1
		q.from = tb.main.pos[i] + Vector3.UP * 1.5
		q.to = tb.main.pos[i] + Vector3.DOWN * 1.2
		if space.intersect_ray(q).is_empty():
			holes += 1
	R.check("track", "drivable surface everywhere on the main line", holes == 0, "holes=%d of %d" % [holes, checked])
	for id in tb.branches:
		var sp: SplinePath = tb.branches[id]
		var h2 := 0
		for i in range(0, sp.size(), 4):
			if sp.style[i] == "gap":
				continue
			q.from = sp.pos[i] + Vector3.UP * 1.5
			q.to = sp.pos[i] + Vector3.DOWN * 1.2
			if space.intersect_ray(q).is_empty():
				h2 += 1
		R.check("track", "branch %s has continuous surface" % id, h2 == 0, "holes=%d" % h2)
	# variety metrics (design acceptance: widths/radii must vary)
	var wmin := 1e9
	var wmax := 0.0
	for w in tb.main.width:
		wmin = minf(wmin, w)
		wmax = maxf(wmax, w)
	R.check("track", "road width varies (>=5 m spread)", wmax - wmin >= 5.0, "%.1f..%.1f m" % [wmin, wmax])
	var rl := RacingLine.build(tb.main, tb.obstacles)
	var buckets := {"<20": 0, "20-40": 0, "40-80": 0, ">80": 0}
	for r in rl.radius:
		if r < 20.0:
			buckets["<20"] += 1
		elif r < 40.0:
			buckets["20-40"] += 1
		elif r < 80.0:
			buckets["40-80"] += 1
		else:
			buckets[">80"] += 1
	R.check("track", "corner radius distribution covers tight..sweeping", buckets["<20"] > 0 and buckets["20-40"] > 0 and buckets["40-80"] > 0, buckets)
	var f := FileAccess.open("res://tests/results/track.json", FileAccess.WRITE)
	f.store_string(JSON.stringify({"build_ms": ms, "timings": tb.timings, "length": tb.main.length, "radius_buckets": buckets,
		"obstacles": tb.obstacles.size(), "item_boxes": tb.item_boxes.size(), "pads": tb.pads.size()}, "  "))
	root.queue_free()
	await R.frames(2)
