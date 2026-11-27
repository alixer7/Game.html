class_name KartAI
extends Node

## Competitive CTR-Style AI Controller.
## Follows track spline with curvature lookahead, targets Turbo Pads, executes genuine
## Power-Slide drift boosts around turns, shakes off TNT crates, and uses items intelligently.

var kart: KartPhysics
var spline: TrackSpline
var turbo_pads: Array = []
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
		preferred_lane = _rng.randf_range(-3.8, 3.8)

	# Scale lookahead to real meters so 2.2km+ tracks have razor-sharp AI cornering!
	var len_scale := 1100.0 / maxf(950.0, spline.total_length)

	# Check if a Turbo Pad is right ahead — steer onto it!
	var target_lane := preferred_lane
	for pad in turbo_pads:
		var dt := fposmod(float(pad["t"]) - kart.spline_t, 1.0)
		if dt > 0.003 * len_scale and dt < 0.048 * len_scale:
			target_lane = float(pad["lateral"])
			break

	# Lookahead scales with current speed so AI anticipates Blue Fire corners cleanly!
	var look_dist := clampf((0.017 + kart.forward_speed * 0.00048) * len_scale, 0.008, 0.036)
	var steer_err := _steer_along_spline(delta, look_dist, target_lane)

	# Smart difficulty-scaled acceleration & gentle rubber-banding
	var pace_mult := 0.86 if difficulty == 0 else (0.98 if difficulty == 1 else 1.08)
	pace_mult *= skill_factor
	if player_kart and is_instance_valid(player_kart):
		var gap := player_kart.total_progress - kart.total_progress
		if gap > 0.14:
			pace_mult += clampf(gap * 0.45, 0.0, 0.18) # Catch up gracefully
		elif gap < -0.18 and difficulty < 2:
			pace_mult -= clampf(-gap * 0.35, 0.0, 0.16) # Don't runaway unfairly on Rookie/Normal
	kart.top_speed_mult = clampf(pace_mult, 0.76, 1.18)
	kart.input_accel = true
	kart.input_brake_uturn = false

	# Authentic AI Power-Slide Drifting & Boosting around sharp curves!
	var ahead_sample := spline.sample_at_t(kart.spline_t + 0.024 * len_scale)
	var curve_mag := absf(float(ahead_sample["curvature"]))
	var want_drift := (difficulty >= 1) and (curve_mag > 0.12 or absf(steer_err) > 0.44) and kart.forward_speed > 20.0

	if want_drift and not kart.is_drifting and kart.is_grounded and _drift_hold_timer <= 0.0:
		kart.input_hop_just_pressed = true
		kart.input_hop_held = true
		_drift_hold_timer = 2.4
	elif kart.is_drifting:
		_drift_hold_timer -= delta
		kart.input_hop_held = _drift_hold_timer > 0.0 and absf(steer_err) > 0.15
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

	# Anti-stuck safeguard
	if kart.forward_speed < 3.5 and kart.spinout_timer <= 0.0:
		_stuck_timer += delta
		if _stuck_timer > 2.8:
			_stuck_timer = 0.0
			kart.force_respawn()
	else:
		_stuck_timer = 0.0

func _steer_along_spline(_delta: float, look_t: float, lane_offset: float = 0.0) -> float:
	var target_s := spline.sample_at_t(kart.spline_t + look_t)
	var clamp_lane := clampf(lane_offset, -float(target_s["half_width"]) * 0.65, float(target_s["half_width"]) * 0.65)
	var target_pos: Vector3 = target_s["pos"] + target_s["right"] * clamp_lane
	var to_target := target_pos - kart.global_position
	var desired_yaw := atan2(-to_target.x, -to_target.z)
	var err := wrapf(desired_yaw - kart.heading_yaw, -PI, PI)
	# Positive input_steer turns RIGHT (-yaw in Godot), negative turns LEFT (+yaw)
	kart.input_steer = clampf(-err * 2.15, -1.0, 1.0)
	return err
