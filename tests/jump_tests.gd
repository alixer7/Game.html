class_name JumpTests
extends RefCounted
## Every jump on the track at several entry speeds, with and without a lip-hop.
## A scripted driver follows the jump's own path, holds the entry speed (no
## engine beyond it), hops on the lip sample if asked, and we record whether
## the kart landed on the far side of the gap or fell short.

var R: Object
var T: SceneTree
var out := {}


func run(runner: Object) -> void:
	R = runner
	T = (runner as Node).get_tree()
	var root := Node3D.new()
	T.root.add_child(root)
	var tb := TrackBuilder.new()
	tb.load_track("res://data/timberfall.json")
	tb.build(root, 0)
	await R.frames(3)
	var jumps := [
		["Tunnel Leap (roof lip)", tb.main, "lip"],
		["Lower Falls", tb.main, "falls_lip"],
		["Giant's Log gap", tb.branches.get("giants_log"), "log_lip"],
		["Shelf Rock", tb.branches.get("shelf_rock"), "shelf_lip"],
		["Flume kicker", tb.branches.get("millrace_flume"), "flume_kick_lip"],
	]
	for j in jumps:
		var sp: SplinePath = j[1]
		if sp == null:
			continue
		var lip := -1
		for i in sp.size():
			if sp.tags[i] == j[2]:
				lip = i
				break
		if lip < 0:
			R.check("jumps", "%s: lip tag found" % j[0], false)
			continue
		# far side = first non-gap sample after the gap
		var far := lip
		while far < sp.size() - 1 and (sp.style[far] != "gap"):
			far += 1
		while far < sp.size() - 1 and sp.style[far] == "gap":
			far += 1
		var res := {}
		for v: float in [22.0, 25.0, 26.0, 28.0, 31.0, 36.0]:
			for hop: bool in [false, true]:
				var ok := await _attempt(root, sp, lip, far, v, hop)
				res["%d%s" % [int(v), "+hop" if hop else ""]] = ok
		out[j[0]] = res
		print("  ", j[0], " ", res)
	var f := FileAccess.open("res://tests/results/jumps.json", FileAccess.WRITE)
	f.store_string(JSON.stringify(out, "  "))
	# design expectations (TRACK_DESIGN.md §6)
	R.check("jumps", "Tunnel Leap clears at base speed", bool(out["Tunnel Leap (roof lip)"]["26"]), out["Tunnel Leap (roof lip)"])
	R.check("jumps", "Giant's Log: base speed or hop clears, slow+no hop fails", bool(out["Giant's Log gap"]["26"]) and bool(out["Giant's Log gap"]["22+hop"]) and not bool(out["Giant's Log gap"]["22"]), out["Giant's Log gap"])
	R.check("jumps", "Flume needs Overdrive-level speed", bool(out["Flume kicker"]["36"]) and not bool(out["Flume kicker"]["26"]), out["Flume kicker"])
	R.check("jumps", "Shelf Rock needs high speed", bool(out["Shelf Rock"]["31"]) or bool(out["Shelf Rock"]["36"]), out["Shelf Rock"])
	root.queue_free()
	await R.frames(2)


func _attempt(root: Node3D, sp: SplinePath, lip: int, far: int, v: float, hop: bool) -> bool:
	var start := maxi(lip - int(30.0 / sp.spacing), 0)
	var k := Kart.new()
	k.params = KartParams.new()
	k.params.max_speed = v      # hold the entry speed: no free acceleration on the run-up
	k.params.accel = 40.0
	root.add_child(k)
	var t := sp.tan[start]
	var yaw := atan2(-t.x, -t.z)
	k.teleport(Transform3D(Basis(Vector3.UP, yaw), sp.pos[start] + sp.up[start] * 0.3))
	await R.frames(2)
	k.velocity = Vector3(-sin(yaw), 0, -cos(yaw)) * v
	var hopped := false
	var landed_far := false
	for f in 300:
		var i := sp.nearest_index(k.global_position, 30.0)
		if i < 0:
			i = start
		var tgt := sp.pos[mini(i + 4, sp.size() - 1)]
		var to := tgt - k.global_position
		to.y = 0
		var ang := k.heading().signed_angle_to(to.normalized(), Vector3.UP) if to.length() > 0.5 else 0.0
		k.in_steer = clampf(-ang * 2.0, -1.0, 1.0) if k.grounded else 0.0
		k.in_throttle = 1.0
		k.in_drift = false
		if hop and not hopped and k.grounded and i >= lip - 1 and i <= lip + 2:
			k.in_drift = true
			hopped = true
		await T.physics_frame
		if k.grounded and i >= far and absf(k.global_position.y - sp.pos[i].y) < 1.0 and f > 10:
			landed_far = true
			break
		if k.global_position.y < sp.pos[mini(far, sp.size() - 1)].y - 3.0 and not k.grounded and i < far:
			pass
		if k.grounded and i > lip + 1 and i < far and f > 10:
			break   # touched down inside the gap: fell short
	k.queue_free()
	return landed_far
