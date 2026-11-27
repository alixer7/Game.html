class_name KartAI
extends Node

## Competitive CTR-Style AI Controller.
## Follows track spline with curvature lookahead, targets Turbo Pads, executes genuine
## Power-Slide drift boosts around turns, shakes off TNT crates, and uses items intelligently.

var kart: KartPhysics
var spline: TrackSpline
var turbo_pads: Array = []
var obstacles: Array = []
var difficulty: int = 1 # 0=Rookie, 1=Nitro, 2=CTR Legend
var preferred_lane: float = 0.0
var _lane_timer: float = 0.0
var _item_delay: float = 0.0
var _stuck_timer: float = 0.0
var _drift_hold_timer: float = 0.0
var _tnt_hop_timer: float = 0.0
var _rng := RandomNumberGenerator.new()

# Player reference for subtle fair competitive pacing
var player_kart: KartPhysics = null
var skill_factor: float = 1.0
var on_use_item: Callable

func setup(k: KartPhysics, sp: TrackSpline, pads: Array, diff: int, seed_val: int, player_ref: KartPhysics, skill: float = 1.0) -> void:
	kart = k
	spline = sp
	turbo_pads = pads
	difficulty = diff
	player_kart = player_ref
	skill_factor = skill
	_rng.seed = seed_val
	preferred_lane = _rng.randf_range(-3.6, 3.6)

func _physics_process(delta: float) -> void:
	if not kart or not is_instance_valid(kart) or spline == null:
		return

	if not kart.race_started:
		# AI revs slightly on countdown on higher difficulty
		kart.input_accel = (difficulty >= 1 and _rng.randf() < 0.08)
		return

	if kart.race_finished_flag:
		# Cruise gently after crossing finish line
		kart.input_accel = true
		kart.input_hop_held = false
		kart.input_brake_uturn = false
		_steer_along_spline(delta, 0.025)
		return

	# Shake off attached TNT by hopping!
	if kart.tnt_attached:
		_tnt_hop_timer -= delta
		if _tnt_hop_timer <= 0.0:
			kart.input_hop_just_pressed = true
			_tnt_hop_timer = 0.36 if difficulty == 2 else (0.52 if difficulty == 1 else 0.78)

	# Periodically adjust racing lane & aim for nearby Turbo Pads!
	_lane_timer -= delta
	if _lane_timer <= 0.0:
		_lane_timer = _rng.randf_range(1.8, 3.8)
		preferred_lane = _rng.randf_range(-3.2, 3.2)
	var L := spline.total_length
	var v := absf(kart.forward_speed)
	var here := spline.sample_at_t(kart.spline_t)
	var hw_here: float = here["half_width"]

	# Lane: preferred, then turbo pads ahead, then dodge static obstacles / shortcut kickers ahead
	var target_lane := preferred_lane
	for pad in turbo_pads:
		var dpad := fposmod(float(pad["t"]) - kart.spline_t, 1.0) * L
		if dpad > 4.0 and dpad < 60.0 and absf(float(pad["lateral"])) < hw_here - 3.0:
			target_lane = float(pad["lateral"])
			break
	# only the NEAREST conflicting obstacle steers the lane (slaloms are taken one gate at a time)
	var best_d := 1e9
	var best_ob: Dictionary = {}
	for ob in obstacles:
		var dob := fposmod(float(ob["t"]) - kart.spline_t + 0.5, 1.0) * L - 0.5 * L
		if dob > -5.0 and dob < 40.0 and absf(dob) < best_d:
			var olat0 := float(ob["lat"])
			var r0 := float(ob["r"]) + 2.6
			var my_lat := float(spline.project_point(kart.global_position, kart.spline_t)["lateral"])
			if absf(olat0 - target_lane) < r0 or absf(olat0 - my_lat) < r0:
				best_d = absf(dob)
				best_ob = ob
	if not best_ob.is_empty():
		var olat := float(best_ob["lat"])
		var r := float(best_ob["r"]) + 2.8
		var s_ob := spline.sample_at_t(float(best_ob["t"]))
		var hw_o: float = s_ob["half_width"]
		var left_room := (olat - r) - (-hw_o)
		var right_room := hw_o - (olat + r)
		var my_side := float(spline.project_point(kart.global_position, kart.spline_t)["lateral"]) - olat
		# keep the side we are already on when there is room (no steering across the obstacle)
		if my_side < 0.0 and left_room > -0.6:
			target_lane = maxf(olat - r, -hw_o + 1.8)
		elif my_side >= 0.0 and right_room > -0.6:
			target_lane = minf(olat + r, hw_o - 1.8)
		else:
			target_lane = (olat - r) if left_room > right_room else (olat + r)
	# Lookahead shortens in tight corners so the AI never cuts across an open inner edge
	var kmax := 0.0
	for kk in range(0, 56, 6):
		var sk := spline.sample_at_t(kart.spline_t + float(kk) / L)
		kmax = maxf(kmax, absf(float(sk["curvature"])))
	var look_m := clampf(v * 0.45, 8.0, 24.0)
	if kmax > 0.02:
		look_m = minf(look_m, clampf(1.0 / kmax * 0.55, 7.0, 24.0))
	var steer_err := _steer_along_spline(delta, look_m / L, target_lane)

	# Edge safety: pull back toward the centre when drifting close to any edge (open edges especially)
	var q := spline.project_point(kart.global_position, kart.spline_t)
	var lat: float = q["lateral"]
	var hwq: float = q["half_width"]
	if absf(lat) > hwq - 3.0:
		var urgency := clampf((absf(lat) - (hwq - 3.0)) / 2.0, 0.3, 1.0)
		# positive steer turns RIGHT, so a kart near the right edge (lat > 0) must steer LEFT
		kart.input_steer = clampf(kart.input_steer - signf(lat) * (0.7 + urgency), -1.0, 1.0)
		if absf(lat) > hwq - 1.2 and kart.forward_speed > 22.0:
			kart.input_accel = false

	# Smart difficulty-scaled acceleration & gentle rubber-banding
	var pace_mult := 0.86 if difficulty == 0 else (0.98 if difficulty == 1 else 1.08)
	pace_mult *= skill_factor
	if player_kart and is_instance_valid(player_kart):
		var gap := player_kart.total_progress - kart.total_progress
		if gap > 0.14:
			pace_mult += clampf(gap * 0.45, 0.0, 0.18)
		elif gap < -0.18 and difficulty < 2:
			pace_mult -= clampf(-gap * 0.35, 0.0, 0.16)
	kart.top_speed_mult = clampf(pace_mult, 0.76, 1.18)
	# Corner speed: lift / brake for what is ahead (grip-aware)
	var grip: float = float(kart.surf_info.get("grip", 1.0))
	for kg in range(0, 61, 12):
		var sg := spline.sample_at_t(kart.spline_t + float(kg) / L)
		grip = minf(grip, float(Surfaces.info(str(sg["surface"]))["grip"]))
	var vmax := (1.6 / maxf(kmax, 0.001)) * lerpf(0.5, 1.0, clampf(grip, 0.0, 1.0)) + 5.0
	var corner_s := spline.sample_at_t(kart.spline_t + 30.0 / L)
	if kmax > 0.02 and (str(corner_s.get("edge_l", "")) == "open" or str(corner_s.get("edge_r", "")) == "open"):
		vmax = vmax * 0.82 - 2.0  # respect corners above a void / lava
	kart.input_accel = v < vmax
	kart.input_brake_uturn = v > vmax + 10.0 and kart.is_grounded and not kart.is_drifting

	# Authentic AI Power-Slide Drifting & Boosting around sharp curves - only where the outside edge is closed
	var ahead_sample := spline.sample_at_t(kart.spline_t + 24.0 / L)
	var curve_mag := absf(float(ahead_sample["curvature"]))
	var outer_key := "edge_r" if float(ahead_sample["curvature"]) > 0.0 else "edge_l"
	var outer_open: bool = str(ahead_sample.get(outer_key, "wall")) in ["open", "halfpipe"]
	var want_drift := (difficulty >= 1) and (curve_mag > 0.022 and curve_mag < 0.06) and kart.forward_speed > 22.0 and not outer_open and absf(lat) < hwq - 4.0

	if want_drift and not kart.is_drifting and kart.is_grounded and _drift_hold_timer <= 0.0:
		kart.input_hop_just_pressed = true
		kart.input_hop_held = true
		_drift_hold_timer = 1.8
	elif kart.is_drifting:
		_drift_hold_timer -= delta
		kart.input_hop_held = _drift_hold_timer > 0.0 and absf(steer_err) > 0.12 and absf(lat) < hwq - 2.5
		var trigger_threshold := 0.82 if difficulty == 2 else 0.70
		if kart.drift_charge >= trigger_threshold:
			kart.input_boost_just_pressed = true
	else:
		kart.input_hop_held = false
		_drift_hold_timer = maxf(0.0, _drift_hold_timer - delta)

	# AI Item Usage
	if kart.held_item != "" and kart.item_roulette_timer <= 0.0:
		_item_delay += delta
		if _item_delay >= _rng.randf_range(0.7, 2.0):
			_item_delay = 0.0
			if on_use_item.is_valid():
				on_use_item.call(kart)

	# Anti-stuck safeguard (uses the REAL motion, not the engine speed)
	var real_speed := Vector2(kart.velocity.x, kart.velocity.z).length()
	if (kart.forward_speed < 3.5 or real_speed < 3.0) and kart.spinout_timer <= 0.0 and kart.race_started:
		_stuck_timer += delta
		if _stuck_timer > 2.8:
			_stuck_timer = 0.0
			kart.force_respawn()
	else:
		_stuck_timer = 0.0

func _steer_along_spline(_delta: float, look_t: float, lane_offset: float = 0.0) -> float:
	var target_s := spline.sample_at_t(kart.spline_t + look_t)
	var hw_t: float = target_s["half_width"]
	var clamp_lane := clampf(lane_offset, -hw_t + 2.6, hw_t - 2.6)
	var target_pos: Vector3 = spline.surface_point(kart.spline_t + look_t, clamp_lane)
	var to_target := target_pos - kart.global_position
	var desired_yaw := atan2(-to_target.x, -to_target.z)
	var err := wrapf(desired_yaw - kart.heading_yaw, -PI, PI)
	# Positive input_steer turns RIGHT (-yaw in Godot), negative turns LEFT (+yaw)
	kart.input_steer = clampf(-err * 2.15, -1.0, 1.0)
	return err
