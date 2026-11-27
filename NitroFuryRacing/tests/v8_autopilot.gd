class_name V8Autopilot
extends RefCounted

## Deterministic test driver for real-physics track verification (no drifting, no items).
## Pure-pursuit steering on a lane, curvature-based speed control, static-obstacle avoidance.

var kart: KartPhysics
var spline: TrackSpline
var obstacles: Array = []
var lane := 0.0
var speed_scale := 1.0
var stats := {"respawns": 0, "stuck_events": 0, "wall_hits": 0, "max_air": 0.0, "jumps": 0, "hits": 0, "min_speed_moving": 999.0}
var _stuck_t := 0.0
var _was_air := false
var _air_t := 0.0

func _init(k: KartPhysics, sp: TrackSpline, obs: Array) -> void:
	kart = k
	spline = sp
	obstacles = obs
	kart.collision_impact.connect(func(_s): stats["wall_hits"] += 1)
	kart.hit_taken.connect(func(_r): stats["hits"] += 1)

func step(delta: float) -> void:
	var t := kart.spline_t
	var v := absf(kart.forward_speed)
	# --- lane choice: dodge static obstacles in the next 45 m
	var target_lane := 0.0
	for ob in obstacles:
		var dt := fposmod(float(ob["t"]) - t, 1.0) * spline.total_length
		if dt > 2.0 and dt < 48.0:
			var olat := float(ob["lat"])
			var r := float(ob["r"])
			if absf(olat - target_lane) < r + 3.2:
				var s := spline.sample_at_t(float(ob["t"]))
				var hw: float = s["half_width"]
				var left_room := olat - r - (-hw)
				var right_room := hw - (olat + r)
				target_lane = (olat - r - 3.4) if left_room > right_room else (olat + r + 3.4)
				target_lane = clampf(target_lane, -hw + 2.5, hw - 2.5)
	lane = move_toward(lane, target_lane, delta * 9.0)
	# --- pure pursuit
	var look := clampf(v * 0.5, 9.0, 26.0)
	var tgt_t := t + look / spline.total_length
	var s2 := spline.sample_at_t(tgt_t)
	var hw2: float = s2["half_width"]
	var tgt: Vector3 = spline.surface_point(tgt_t, clampf(lane, -hw2 + 2.0, hw2 - 2.0))
	var to_t := tgt - kart.global_position
	var desired := atan2(-to_t.x, -to_t.z)
	var err := wrapf(desired - kart.heading_yaw, -PI, PI)
	kart.input_steer = clampf(-err * 2.4, -1.0, 1.0)
	# --- speed control from curvature ahead
	var kmax := 0.0
	for k in range(0, 50, 4):
		var sk := spline.sample_at_t(t + float(k) / spline.total_length)
		kmax = maxf(kmax, absf(float(sk["curvature"])))
	var vmax := 1.55 / maxf(kmax, 0.001) * speed_scale + 4.0
	kart.input_accel = v < vmax
	kart.input_brake_uturn = v > vmax + 9.0 and kart.is_grounded
	kart.input_hop_held = false
	# --- stats
	if kart.respawn_timer > 0.0 and not _was_resp:
		stats["respawns"] += 1
	_was_resp = kart.respawn_timer > 0.0
	if kart.is_grounded:
		if _was_air and _air_t > 0.3:
			stats["jumps"] += 1
		stats["max_air"] = maxf(float(stats["max_air"]), _air_t)
		_air_t = 0.0
	else:
		_air_t += delta
	_was_air = not kart.is_grounded
	var real_v := Vector2(kart.velocity.x, kart.velocity.z).length()
	if kart.race_started and (v < 3.0 or real_v < 3.0) and kart.spinout_timer <= 0.0 and kart.respawn_timer <= 0.0:
		_stuck_t += delta
		if _stuck_t > 1.2:
			stats["stuck_events"] += 1
			_stuck_t = -3.0
	else:
		_stuck_t = maxf(0.0, _stuck_t)

var _was_resp := false
