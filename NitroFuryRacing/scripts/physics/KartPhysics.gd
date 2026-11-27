class_name KartPhysics
extends CharacterBody3D

## Authentic Heavy-Weighted Crash Team Racing (CTR) Physics Controller v2.0.
## Upgraded for:
## - Grounded, weighty kart feel & real spring-damper 4-wheel suspension WITHOUT sacrificing top speed!
## - Obtuse sweeping Power-Slide arc (0.14..0.78..1.56 rad/s) — never overly sharp or twitchy!
## - Realistic longitudinal + lateral tire friction, with INCREASED planted tire grip/bite during drifts!
## - Full CTR Reserves, 5 Fire Tiers (None/Red/Orange/Sacred/Blue Fire), Hang-Time Turbo,
##   Air-Brake U-Turn (Reserves-preserving), Road Bump Suspension, and 5-Hop TNT Shake-Off!

signal boost_triggered(tier: int, quality: String, stage: int)
signal fire_tier_changed(new_tier: int)
signal shortcut_triggered(shortcut_id: String, shortcut_name: String)
signal fruit_changed(count: int)
signal item_changed(item_id: String)
signal hit_taken(reason: String)
signal landing_impact(strength: float)
signal collision_impact(strength: float)
signal lap_completed(lap_num: int, lap_time: float)
signal race_finished(total_time: float)
signal status_banner(key: String, color: Color)

enum FireTier {
	NONE = 0,
	RED = 1,
	ORANGE = 2,
	SACRED = 3,
	BLUE = 4
}

# --- v7.0 Calibrated CTR:NF Speed & Wumpa Economy ---
# Base speed + 10 Wumpa (+18%!) is the true foundation of winning; boost tiers stay exhilarating & controllable!
const BASE_TOP_SPEED := 34.0
const TIER_SPEEDS := {
	FireTier.NONE: 34.0,
	FireTier.RED: 38.0,
	FireTier.ORANGE: 42.0,
	FireTier.SACRED: 47.5,
	FireTier.BLUE: 54.0
}

const GRAVITY := 58.0
const HOP_IMPULSE := 14.8
const MAX_RESERVES := 12.0
const FRUIT_MAX := 10
const FRUIT_SPEED_BONUS := 0.18

# Start-Line Precision Sweet Spot Constants (shared with StartBoostBarDrawer HUD!)
const START_GOOD_MIN := 0.50
const START_PERFECT_MIN := 0.76
const START_PERFECT_MAX := 0.94
const START_OVERHEAT_AT := 0.98

# --- Racer Stats & Identity ---
var racer_id: String = "blaze"
var racer_data: Dictionary = {}
var is_player: bool = false
var top_speed_mult: float = 1.0
var accel_mult: float = 1.0
var turn_mult: float = 1.0
var drift_tightness: float = 1.0

# --- Input State ---
var input_steer: float = 0.0
var input_accel: bool = false
var input_brake_uturn: bool = false
var input_hop_held: bool = false
var input_hop_just_pressed: bool = false
var input_boost_just_pressed: bool = false
var input_item_just_pressed: bool = false

# --- Weighted Chassis, Tire Friction & Suspension Physics State ---
var heading_yaw: float = 0.0
var angular_yaw_vel: float = 0.0     # Gives authentic weighty chassis steering inertia!
var forward_speed: float = 0.0
var lateral_slip_speed: float = 0.0  # Real lateral tire velocity for realistic tire-to-road friction!
var vertical_speed: float = 0.0
var ground_normal: Vector3 = Vector3.UP
var prev_ground_y: float = 0.0
var surface_type: String = "road"
var is_grounded: bool = true
var coyote_timer: float = 0.0
var air_time: float = 0.0
var air_uturn_active: bool = false
var uturn_ground_grace: float = 0.0
var was_hopping_for_uturn: bool = false

# Real Spring-Damper 4-Wheel Suspension, Independent Wheel Grounding & Weight Transfer!
var susp_offset: float = 0.0
var susp_vel: float = 0.0
var weight_pitch: float = 0.0
var weight_roll: float = 0.0
var wheel_y_offsets: Array[float] = [0.0, 0.0, 0.0, 0.0] # [FL, FR, RL, RR] exact ground contact offsets
var wheel_ground_contact: Array[bool] = [true, true, true, true]
var current_tire_friction: float = 9.0 # Exposed for verification & HUD/audio feedback!

# --- CTR Obtuse-Arc Power-Slide / Drift State ---
var is_drifting: bool = false
var drift_dir: int = 0
var pending_drift_dir: int = 0
var drift_charge: float = 0.0
var drift_boost_count: int = 0
var drift_backfire_cooldown: float = 0.0

# --- CTR Reserves & Fire State ---
var fire_tier: int = FireTier.NONE
var reserves: float = 0.0
var boost_kick_timer: float = 0.0
var boost_surge_timer: float = 0.0
var last_pad_cooldown: float = 0.0
var wall_bump_cooldown: float = 0.0

# --- Start-Line Revving ---
var race_started: bool = false
var race_finished_flag: bool = false
var start_rev_meter: float = 0.0
var start_rev_overheated: bool = false
var start_stall_timer: float = 0.0
var last_collision_strength: String = ""

# --- Combat / Items / Fruits / Hazards ---
var fruit_count: int = 0
var held_item: String = ""
var item_roulette_timer: float = 0.0
var shield_active: bool = false
var shield_juiced: bool = false
var shield_timer: float = 0.0
var mask_timer: float = 0.0
var spinout_timer: float = 0.0
var tnt_attached: bool = false
var tnt_timer: float = 0.0
var tnt_hops_left: int = 0
var tnt_tick_accum: float = 0.0

# --- Race Progress & Track Spline Tracking ---
var track_spline = null
var current_lap: int = 1
var total_laps: int = 3
var spline_t: float = 0.0
var prev_spline_t: float = 0.0
var checkpoint_mask: int = 0
var lap_start_time: float = 0.0
var best_lap_time: float = 9999.0
var race_elapsed: float = 0.0
var total_progress: float = 0.0
var wrong_way: bool = false
var safe_respawn_pos: Vector3 = Vector3.ZERO
var safe_respawn_yaw: float = 0.0
var respawn_timer: float = 0.0
var shortcut_cooldowns: Dictionary = {}

var visuals: Node3D = null
var _col_shape: CollisionShape3D = null

# --- v8 world / surface awareness ---
var world_ref = null                 # TrackBuilder (terrain surface lookup, liquids, gaps)
var surf_info: Dictionary = Surfaces.info("stone")
var surface_class: String = "road"
var _oob_timer: float = 0.0
var _pinned_t: float = 0.0

func _ready() -> void:
	collision_layer = 16
	collision_mask = 1 | 2 | 4 | 8
	floor_max_angle = deg_to_rad(56.0)
	floor_snap_length = 0.50
	wall_min_slide_angle = deg_to_rad(10.0)
	max_slides = 4
	up_direction = Vector3.UP

	_col_shape = CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = 0.96
	_col_shape.shape = sphere
	_col_shape.position = Vector3(0.0, 0.96, 0.0)
	add_child(_col_shape)

func setup_racer(data: Dictionary, player_controlled: bool, spline_ref, laps: int = 3) -> void:
	racer_data = data
	racer_id = str(data.get("id", "blaze"))
	is_player = player_controlled
	top_speed_mult = float(data.get("top_speed_mult", 1.0))
	accel_mult = float(data.get("accel_mult", 1.0))
	turn_mult = float(data.get("turn_mult", 1.0))
	drift_tightness = float(data.get("drift_tightness", 1.0))
	track_spline = spline_ref
	total_laps = laps

	if visuals and is_instance_valid(visuals):
		visuals.queue_free()
	var vis_script := load("res://scripts/physics/KartVisuals.gd")
	visuals = vis_script.new()
	add_child(visuals)
	visuals.build_kart(data, false, is_player)

func place_at_start(pos: Vector3, yaw: float, initial_t: float = 0.0) -> void:
	global_position = pos
	heading_yaw = yaw
	angular_yaw_vel = 0.0
	rotation = Vector3(0.0, yaw, 0.0)
	velocity = Vector3.ZERO
	forward_speed = 0.0
	lateral_slip_speed = 0.0
	vertical_speed = 0.0
	ground_normal = Vector3.UP
	prev_ground_y = pos.y
	is_grounded = true
	reserves = 0.0
	fire_tier = FireTier.NONE
	is_drifting = false
	drift_charge = 0.0
	drift_boost_count = 0
	susp_offset = 0.0
	susp_vel = 0.0
	spline_t = initial_t
	prev_spline_t = initial_t
	checkpoint_mask = 0
	current_lap = 1
	lap_start_time = 0.0
	race_elapsed = 0.0
	total_progress = initial_t
	safe_respawn_pos = pos + Vector3(0.0, 0.45, 0.0)
	safe_respawn_yaw = yaw

func is_juiced() -> bool:
	return fruit_count >= FRUIT_MAX

func get_current_top_speed() -> float:
	var base := float(TIER_SPEEDS[fire_tier])
	var fruit_mult := 1.0 + (float(fruit_count) / float(FRUIT_MAX)) * FRUIT_SPEED_BONUS
	var mask_mult := 1.15 if mask_timer > 0.0 else 1.0
	var surf_mult := 1.0
	if is_grounded and mask_timer <= 0.0:
		surf_mult = float(surf_info["speed"])
	elif is_grounded:
		surf_mult = maxf(1.0, float(surf_info["speed"]))
	return base * top_speed_mult * fruit_mult * mask_mult * surf_mult

func get_speed_kmh() -> int:
	return int(round(absf(forward_speed) * 3.4))

func add_boost(min_tier: int, reserve_add: float, kick_speed: float = 5.0, play_sound: bool = true) -> void:
	var prev_tier := fire_tier
	if min_tier > fire_tier:
		fire_tier = min_tier
	reserves = minf(MAX_RESERVES, reserves + reserve_add)
	boost_kick_timer = 0.30
	boost_surge_timer = 0.36
	var target := get_current_top_speed()
	forward_speed = maxf(forward_speed + kick_speed, minf(target, forward_speed + kick_speed * 1.32))
	# Heavy rear suspension squat + nose-up mini-wheelie impulse when turbo fires!
	susp_vel -= 1.65
	weight_pitch = clampf(weight_pitch + 0.095, -0.15, 0.16)
	if visuals:
		visuals.trigger_boost_flash(fire_tier)
	if fire_tier != prev_tier:
		fire_tier_changed.emit(fire_tier)
		if is_player:
			if fire_tier == FireTier.SACRED:
				status_banner.emit("sacred_fire", Color(1.0, 0.62, 0.08))
				if play_sound and AudioSynth: AudioSynth.play_sfx("sacred_fire", 1.0, 1.1)
			elif fire_tier == FireTier.BLUE:
				status_banner.emit("blue_fire", Color(0.18, 0.90, 1.0))
				if play_sound and AudioSynth: AudioSynth.play_sfx("blue_fire", 1.0, 1.2)

func trigger_turbo_pad(is_super_blue_fire: bool) -> void:
	if last_pad_cooldown > 0.0:
		return
	last_pad_cooldown = 0.22
	if is_super_blue_fire:
		add_boost(FireTier.BLUE, 4.4, 12.5, true)
	else:
		add_boost(FireTier.SACRED, 3.3, 9.0, true)
	if visuals:
		visuals.trigger_boost_flash(fire_tier)

func trigger_geyser_launch(impulse_y: float = 22.0) -> void:
	vertical_speed = maxf(vertical_speed, impulse_y)
	is_grounded = false
	coyote_timer = 0.0
	if is_player and AudioSynth:
		AudioSynth.play_sfx("hop", 0.72, 1.1)

func trigger_start_go() -> void:
	race_started = true
	if start_rev_overheated or start_rev_meter > START_PERFECT_MAX:
		start_stall_timer = 0.42
		if is_player:
			status_banner.emit("backfire", Color(1.0, 0.30, 0.20))
			if AudioSynth: AudioSynth.play_sfx("backfire", 0.95, 1.0)
		start_rev_meter = 0.0
		start_rev_overheated = false
		return
	if start_rev_meter >= START_PERFECT_MIN and start_rev_meter <= START_PERFECT_MAX:
		add_boost(FireTier.ORANGE, 2.2, 16.5, false)
		if is_player:
			status_banner.emit("start_perfect", Color(1.0, 0.88, 0.12))
			if AudioSynth: AudioSynth.play_drift_boost(3, true)
	elif start_rev_meter >= START_GOOD_MIN:
		add_boost(FireTier.RED, 1.2, 10.5, false)
		if is_player:
			status_banner.emit("start_good", Color(0.36, 1.0, 0.42))
			if AudioSynth: AudioSynth.play_drift_boost(1, false)
	start_rev_meter = 0.0
	start_rev_overheated = false

func add_fruit(amount: int = 1) -> void:
	var old := fruit_count
	fruit_count = clampi(fruit_count + amount, 0, FRUIT_MAX)
	if fruit_count != old:
		fruit_changed.emit(fruit_count)
		if is_player and AudioSynth:
			AudioSynth.play_fruit()

func lose_fruits(amount: int, lost_all_abyss: bool = false) -> void:
	if fruit_count <= 0:
		return
	var old := fruit_count
	if lost_all_abyss:
		fruit_count = 0
	else:
		fruit_count = maxi(0, fruit_count - amount)
	if fruit_count != old:
		fruit_changed.emit(fruit_count)
		if is_player and lost_all_abyss:
			status_banner.emit("wumpa_lost_all", Color(1.0, 0.26, 0.20))

func grant_random_item(position_rank: int) -> void:
	if held_item != "" or item_roulette_timer > 0.0:
		return
	item_roulette_timer = 0.95
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var r := rng.randf()
	if position_rank <= 1:
		if r < 0.35: held_item = "tnt"
		elif r < 0.65: held_item = "shield"
		elif r < 0.88: held_item = "bomb"
		else: held_item = "turbo"
	elif position_rank <= 3:
		if r < 0.26: held_item = "missile"
		elif r < 0.50: held_item = "turbo"
		elif r < 0.70: held_item = "shield"
		elif r < 0.86: held_item = "bomb"
		else: held_item = "tnt"
	else:
		if r < 0.32: held_item = "mask"
		elif r < 0.64: held_item = "turbo"
		elif r < 0.86: held_item = "missile"
		else: held_item = "shield"
	item_changed.emit(held_item)

func apply_hit(reason: String, is_tnt_stick: bool = false) -> void:
	if mask_timer > 0.0 or spinout_timer > 0.0 or respawn_timer > 0.0:
		return
	if shield_active:
		shield_active = false
		shield_juiced = false
		shield_timer = 0.0
		if is_player and AudioSynth:
			AudioSynth.play_sfx("crate", 1.2)
		return
	if is_tnt_stick and not tnt_attached:
		tnt_attached = true
		tnt_timer = 3.0
		tnt_hops_left = 5
		tnt_tick_accum = 0.0
		if is_player:
			status_banner.emit("tnt_warn", Color(1.0, 0.25, 0.18))
			if AudioSynth: AudioSynth.play_sfx("tnt_tick")
		return
	spinout_timer = 1.05
	reserves = 0.0
	_set_fire_tier(FireTier.NONE)
	_end_drift(false)
	forward_speed *= 0.28
	vertical_speed = 8.0
	last_collision_strength = "massive"
	lose_fruits(3, false)
	hit_taken.emit(reason)
	if is_player and AudioSynth:
		AudioSynth.play_sfx("explosion", 1.0, 1.0)

func force_respawn(fell_into_abyss: bool = true) -> void:
	if respawn_timer > 0.0:
		return
	respawn_timer = 0.65
	reserves = 0.0
	_set_fire_tier(FireTier.NONE)
	_end_drift(false)
	tnt_attached = false
	velocity = Vector3.ZERO
	forward_speed = 0.0
	lateral_slip_speed = 0.0
	vertical_speed = 0.0
	angular_yaw_vel = 0.0
	if fell_into_abyss:
		# Authentic CTR:NF high stakes — falling into the abyss loses ALL collected Wumpa Fruits!
		lose_fruits(FRUIT_MAX, true)

func _set_fire_tier(new_tier: int) -> void:
	if fire_tier != new_tier:
		fire_tier = new_tier
		fire_tier_changed.emit(fire_tier)

func _physics_process(delta: float) -> void:
	# Guard against extreme delta spikes or corrupted physics coordinates on mobile!
	delta = minf(delta, 0.05)
	if not is_finite(global_position.x) or not is_finite(global_position.y) or not is_finite(global_position.z):
		global_position = safe_respawn_pos + Vector3(0.0, 1.5, 0.0)
		velocity = Vector3.ZERO
		forward_speed = 0.0
		vertical_speed = 0.0
	if last_pad_cooldown > 0.0: last_pad_cooldown -= delta
	if boost_kick_timer > 0.0: boost_kick_timer -= delta
	if boost_surge_timer > 0.0: boost_surge_timer -= delta
	if wall_bump_cooldown > 0.0: wall_bump_cooldown -= delta
	if start_stall_timer > 0.0: start_stall_timer -= delta
	if drift_backfire_cooldown > 0.0: drift_backfire_cooldown -= delta
	if item_roulette_timer > 0.0: item_roulette_timer = maxf(0.0, item_roulette_timer - delta)
	if shield_active and not shield_juiced:
		shield_timer -= delta
		if shield_timer <= 0.0:
			shield_active = false
	if mask_timer > 0.0:
		mask_timer = maxf(0.0, mask_timer - delta)
	for sc_id in shortcut_cooldowns.keys():
		shortcut_cooldowns[sc_id] = float(shortcut_cooldowns[sc_id]) - delta
		if float(shortcut_cooldowns[sc_id]) <= 0.0:
			shortcut_cooldowns.erase(sc_id)

	if not race_started:
		_process_countdown_rev(delta)
		_probe_4_wheels(delta)
		_step_suspension(delta, 0.0)
		_update_visuals(delta)
		_clear_one_shot_inputs()
		return

	if not race_finished_flag:
		race_elapsed += delta

	if respawn_timer > 0.0:
		respawn_timer -= delta
		if respawn_timer <= 0.0:
			global_position = safe_respawn_pos + Vector3(0.0, 2.2, 0.0)
			heading_yaw = safe_respawn_yaw
			forward_speed = 8.0
			lateral_slip_speed = 0.0
			vertical_speed = 0.0
			velocity = Vector3.ZERO
		_update_visuals(delta)
		_clear_one_shot_inputs()
		return

	if tnt_attached:
		_process_tnt(delta)

	if spinout_timer > 0.0:
		spinout_timer -= delta
		forward_speed = lerpf(forward_speed, 0.0, delta * 3.2)
		vertical_speed -= GRAVITY * delta
		var fwd_spin := Vector3(-sin(heading_yaw), 0.0, -cos(heading_yaw))
		velocity = fwd_spin * forward_speed + Vector3(0.0, vertical_speed, 0.0)
		move_and_slide()
		if is_on_floor() and vertical_speed < 0.0:
			vertical_speed = 0.0
		_update_visuals(delta)
		_clear_one_shot_inputs()
		return

	var prev_speed := forward_speed
	var was_grounded := is_grounded
	var impact_vy := vertical_speed
	_probe_ground(delta)
	_probe_4_wheels(delta)
	if is_grounded and not was_grounded:
		_handle_landing(impact_vy)

	_process_hop_and_drift(delta)
	_process_reserves(delta)
	_process_steering_and_velocity(delta)
	_execute_move_and_walls(delta)
	_step_suspension(delta, (forward_speed - prev_speed) / maxf(0.001, delta))
	_check_fall_and_progress()
	_update_visuals(delta)
	_clear_one_shot_inputs()

func _probe_4_wheels(delta: float) -> void:
	## Independent 4-Corner Wheel-to-Road Contact Probe (keeps all 4 fat tires glued to cobblestones!).
	if not is_grounded:
		for i in range(4):
			# Coilover springs extend downward slightly while airborne!
			wheel_y_offsets[i] = lerpf(wheel_y_offsets[i], -0.14, minf(1.0, delta * 9.0))
			wheel_ground_contact[i] = false
		return

	if not is_player:
		# Fast analytic grounding for AI karts (zero raycast cost for locked 60FPS!)
		for i in range(4):
			wheel_y_offsets[i] = lerpf(wheel_y_offsets[i], 0.0, minf(1.0, delta * 14.0))
			wheel_ground_contact[i] = true
		return

	var space := get_world_3d().direct_space_state
	var local_corners: Array[Vector3] = [
		Vector3(-0.98, 0.0, -0.94), # FL
		Vector3(0.98, 0.0, -0.94),  # FR
		Vector3(-1.04, 0.0, 0.86),  # RL
		Vector3(1.04, 0.0, 0.86),   # RR
	]
	var up_v := basis.y.normalized()
	for i in range(4):
		var world_corner := global_transform * local_corners[i]
		var ray_from := world_corner + up_v * 0.88
		var ray_to := world_corner - up_v * 0.48
		var q := PhysicsRayQueryParameters3D.create(ray_from, ray_to, 1 | 4 | 8)
		q.exclude = [get_rid()]
		var hit := space.intersect_ray(q)
		if hit.size() > 0:
			var hit_p: Vector3 = hit["position"]
			var local_dy := (hit_p - world_corner).dot(up_v)
			wheel_y_offsets[i] = lerpf(wheel_y_offsets[i], clampf(local_dy, -0.22, 0.20), minf(1.0, delta * 24.0))
			wheel_ground_contact[i] = true
		else:
			wheel_y_offsets[i] = lerpf(wheel_y_offsets[i], -0.10, minf(1.0, delta * 12.0))
			wheel_ground_contact[i] = false

func _step_suspension(delta: float, long_accel: float) -> void:
	# Authentic Heavy 4-Wheel Spring-Damper Suspension & Chassis Weight Transfer!
	var spring_k := 82.0
	var damper_c := 9.4
	# Tactile road bump / mogul excitation from road elevation ripples & differential wheel contact!
	if is_grounded:
		var dy := global_position.y - prev_ground_y
		susp_vel -= clampf(dy * 7.2, -4.8, 4.8) * delta * 28.0
	prev_ground_y = global_position.y

	var spring_f := -spring_k * susp_offset - damper_c * susp_vel
	susp_vel += spring_f * delta
	susp_offset = clampf(susp_offset + susp_vel * delta, -0.26, 0.18)

	# Terrain-driven chassis pitch & roll from 4-wheel differential height!
	var wheel_diff_pitch := ((wheel_y_offsets[0] + wheel_y_offsets[1]) - (wheel_y_offsets[2] + wheel_y_offsets[3])) * 0.18
	var wheel_diff_roll := ((wheel_y_offsets[1] + wheel_y_offsets[3]) - (wheel_y_offsets[0] + wheel_y_offsets[2])) * 0.20

	# Heavy longitudinal weight transfer (squat back on boost/accel, dive nose on brake!)
	var target_pitch := clampf(long_accel * 0.0044 + wheel_diff_pitch, -0.14, 0.16)
	if not is_grounded:
		target_pitch = clampf(vertical_speed * 0.011, -0.20, 0.22)
	weight_pitch = lerpf(weight_pitch, target_pitch, minf(1.0, delta * 8.5))

	# Heavy lateral chassis roll onto outer tires (clearly conveys vehicle mass in corners!)
	var target_roll := clampf(angular_yaw_vel * 0.125 + (float(drift_dir) * -0.12 if is_drifting else 0.0) + wheel_diff_roll, -0.26, 0.26)
	weight_roll = lerpf(weight_roll, target_roll, minf(1.0, delta * 9.0))

func _process_countdown_rev(delta: float) -> void:
	# CTR:NF Precision Start-Line Revving Bar:
	# Pump/feather BOOST or GAS to hold needle inside the Golden Sweet Spot (76%-94%) on GO!
	if input_boost_just_pressed or input_accel:
		if not start_rev_overheated:
			if input_boost_just_pressed:
				start_rev_meter += 0.21
			elif input_accel:
				start_rev_meter += delta * 0.62
			if start_rev_meter >= START_OVERHEAT_AT:
				start_rev_overheated = true
				start_rev_meter = 1.0
				if is_player and AudioSynth:
					AudioSynth.play_sfx("backfire", 1.12, 0.72)
	else:
		start_rev_meter = maxf(0.0, start_rev_meter - delta * 0.42)
		if start_rev_meter < 0.52:
			start_rev_overheated = false
	if is_player and AudioSynth:
		AudioSynth.update_kart_audio(0.15 + start_rev_meter * 0.45, 0, false, false, start_rev_meter)

func _process_tnt(delta: float) -> void:
	if input_hop_just_pressed:
		tnt_hops_left -= 1
		if tnt_hops_left <= 0:
			tnt_attached = false
			if is_player and AudioSynth:
				AudioSynth.play_sfx("ui_confirm", 1.35)
			return
	tnt_timer -= delta
	tnt_tick_accum += delta
	var tick_interval := 0.55 if tnt_timer > 1.5 else 0.24
	if tnt_tick_accum >= tick_interval:
		tnt_tick_accum = 0.0
		if is_player and AudioSynth:
			AudioSynth.play_sfx("tnt_tick", 1.0 + (3.0 - tnt_timer) * 0.2)
	if tnt_timer <= 0.0:
		tnt_attached = false
		apply_hit("tnt_boom", false)

func _probe_ground(delta: float) -> void:
	var space := get_world_3d().direct_space_state
	var ray_origin := global_position + Vector3(0.0, 1.0, 0.0)
	var ray_end := global_position + Vector3(0.0, -1.42, 0.0)
	var q := PhysicsRayQueryParameters3D.create(ray_origin, ray_end, 1 | 4 | 8)
	q.exclude = [get_rid()]
	var hit := space.intersect_ray(q)

	var floor_hit := is_on_floor()
	if hit.size() > 0:
		var hit_pos: Vector3 = hit["position"]
		var dist := ray_origin.distance_to(hit_pos)
		var hit_normal: Vector3 = hit["normal"]
		if dist <= 1.34 and vertical_speed <= 2.6 and hit_normal.y > 0.45:
			is_grounded = true
			coyote_timer = 0.09
			ground_normal = ground_normal.lerp(hit_normal, minf(1.0, delta * 13.0)).normalized()
			var col = hit["collider"]
			_resolve_surface(col, hit_pos)
			return

	var floor_is_wall := false
	if floor_hit:
		var fc0 := get_last_slide_collision()
		if fc0 and fc0.get_collider() is CollisionObject3D and ((fc0.get_collider() as CollisionObject3D).collision_layer & 2) != 0 and ((fc0.get_collider() as CollisionObject3D).collision_layer & (1 | 4 | 8)) == 0:
			floor_is_wall = true  # top edge of a wall / rail / prop is never ground: slide off it
	if floor_hit and vertical_speed <= 1.6 and not floor_is_wall:
		is_grounded = true
		coyote_timer = 0.09
		ground_normal = ground_normal.lerp(get_floor_normal(), minf(1.0, delta * 13.0)).normalized()
		var fc := get_last_slide_collision()
		if fc:
			_resolve_surface(fc.get_collider(), fc.get_position())
	else:
		is_grounded = false
		coyote_timer = maxf(0.0, coyote_timer - delta)
		air_time += delta
		ground_normal = ground_normal.lerp(Vector3.UP, minf(1.0, delta * 3.5)).normalized()

func _resolve_surface(col, hit_pos: Vector3) -> void:
	## v8: road / shoulder surfaces come from the track description, terrain from the world surface map.
	var meta := "stone"
	if col and col is Object and col.has_meta("surface_type"):
		meta = str(col.get_meta("surface_type"))
	var sid := meta
	if meta == "track" and track_spline != null:
		sid = track_spline.surface_at(hit_pos, spline_t)
	elif meta == "terrain" and world_ref != null and world_ref.world != null:
		sid = world_ref.world.terrain_surface_at(hit_pos)
	elif meta == "turbo_pad":
		trigger_turbo_pad(false)
		sid = "stone"
	elif meta == "super_turbo_pad":
		trigger_turbo_pad(true)
		sid = "stone"
	elif meta in ["road", "prop_obstacle", "wall"]:
		sid = "stone"
	surface_type = sid
	surf_info = Surfaces.info(sid)
	surface_class = str(surf_info["cls"])
	if col and col is Object and col.has_meta("oob"):
		_oob_timer += get_physics_process_delta_time()
	else:
		_oob_timer = 0.0
	if bool(surf_info.get("deadly", false)) and respawn_timer <= 0.0:
		force_respawn(true)

func _handle_landing(impact_vy: float) -> void:
	# Heavy realistic suspension compression & tactile landing thud on touchdown!
	susp_vel += clampf(impact_vy * 0.20, -5.2, -1.1)
	var impact_strength := clampf(absf(impact_vy) / 36.0, 0.0, 1.0)
	if air_time >= 0.15:
		landing_impact.emit(impact_strength)
		if is_player and AudioSynth:
			AudioSynth.play_sfx("land", clampf(1.08 - air_time * 0.18, 0.68, 1.08), 0.92)

	if air_time >= 1.00:
		add_boost(FireTier.ORANGE, 1.85, 10.0, false)
		if is_player:
			status_banner.emit("hang_boost", Color(1.0, 0.80, 0.14))
			if AudioSynth: AudioSynth.play_drift_boost(3, true)
	elif air_time >= 0.60:
		add_boost(FireTier.ORANGE, 1.15, 7.0, false)
		if is_player:
			status_banner.emit("hang_boost", Color(1.0, 0.64, 0.12))
			if AudioSynth: AudioSynth.play_drift_boost(2, false)
	elif air_time >= 0.34:
		add_boost(FireTier.RED, 0.58, 4.5, false)
		if is_player and AudioSynth:
			AudioSynth.play_drift_boost(1, false)

	air_time = 0.0
	if was_hopping_for_uturn:
		uturn_ground_grace = 0.12
		was_hopping_for_uturn = false

	if input_hop_held and not input_brake_uturn and forward_speed > 14.0 and drift_backfire_cooldown <= 0.0:
		var chosen_dir := pending_drift_dir
		if chosen_dir == 0 and absf(input_steer) > 0.15:
			chosen_dir = 1 if input_steer > 0.0 else -1
		if chosen_dir != 0:
			is_drifting = true
			drift_dir = chosen_dir
			drift_charge = 0.0
			drift_boost_count = 0
	pending_drift_dir = 0

func _process_hop_and_drift(delta: float) -> void:
	if uturn_ground_grace > 0.0:
		uturn_ground_grace -= delta

	if input_hop_just_pressed and (is_grounded or coyote_timer > 0.0):
		var fwd := Vector3(-sin(heading_yaw), 0.0, -cos(heading_yaw))
		var slope_vec := fwd - ground_normal * fwd.dot(ground_normal)
		var slope_lift := maxf(0.0, slope_vec.normalized().y * forward_speed)
		var kicker_bonus := 2.6 if surface_type == "kicker" else 0.0
		# v8: launch keeps the ramp's own vertical velocity (once) + the hop impulse -> predictable jump arcs
		vertical_speed = maxf(maxf(vertical_speed, 0.0), slope_lift) + HOP_IMPULSE + kicker_bonus
		susp_vel += 2.6 # Spring extension on launch!
		is_grounded = false
		coyote_timer = 0.0
		if absf(input_steer) > 0.15:
			pending_drift_dir = 1 if input_steer > 0.0 else -1
		else:
			pending_drift_dir = 0
		if is_drifting:
			_end_drift(false)
		if is_player and AudioSynth:
			AudioSynth.play_sfx("hop", 0.96 + randf_range(-0.04, 0.04), 0.85)

	if not is_grounded and input_hop_held and pending_drift_dir == 0 and absf(input_steer) > 0.2:
		pending_drift_dir = 1 if input_steer > 0.0 else -1

	if is_drifting:
		if not input_hop_held or forward_speed < 11.0 or input_brake_uturn:
			_end_drift(false)
			return
		var charge_rate := 1.06 * (0.94 + 0.06 * accel_mult)
		drift_charge += delta * charge_rate

		if input_boost_just_pressed:
			if drift_charge >= 0.48 and drift_charge <= 1.00:
				var is_perfect := drift_charge >= 0.76
				drift_boost_count += 1
				var res_add := (1.45 if is_perfect else 0.88) + (0.35 if drift_boost_count == 3 else 0.0)
				var kick := 6.2 if is_perfect else 4.0
				add_boost(FireTier.ORANGE, res_add, kick, false)
				boost_triggered.emit(fire_tier, "perfect" if is_perfect else "good", drift_boost_count)
				if visuals:
					visuals.trigger_boost_flash(fire_tier)
				if is_player:
					status_banner.emit("perfect" if is_perfect else "good", Color(1.0, 0.86, 0.12) if is_perfect else Color(0.42, 0.96, 0.36))
					if AudioSynth:
						AudioSynth.play_drift_boost(drift_boost_count, is_perfect)
				drift_charge = 0.0
				if drift_boost_count >= 3:
					_end_drift(true)

		if drift_charge > 1.05:
			_end_drift(false)
			drift_backfire_cooldown = 0.35
			if is_player:
				status_banner.emit("backfire", Color(0.75, 0.75, 0.82))
				if AudioSynth:
					AudioSynth.play_sfx("backfire", 1.0, 0.85)

func _end_drift(_completed_triple: bool) -> void:
	is_drifting = false
	drift_dir = 0
	drift_charge = 0.0
	drift_boost_count = 0

func _process_reserves(delta: float) -> void:
	if reserves > 0.0:
		var drain := 1.0
		if is_grounded and mask_timer <= 0.0:
			drain = float(surf_info["drain"])
		reserves -= delta * drain
		if reserves <= 0.0:
			reserves = 0.0
			_set_fire_tier(FireTier.NONE)

func _process_steering_and_velocity(delta: float) -> void:
	var target_top := get_current_top_speed()
	var on_ice := is_grounded and surface_class == "ice"
	var s_grip: float = float(surf_info["grip"]) if is_grounded else 1.0
	var s_steer: float = float(surf_info["steer"]) if is_grounded else 1.0

	air_uturn_active = input_brake_uturn and (not is_grounded or uturn_ground_grace > 0.0)
	if not is_grounded and input_brake_uturn:
		was_hopping_for_uturn = true

	# --- 1. HEAVY WEIGHTED YAW STEERING WITH WIDE OBTUSE CTR DRIFT ARC ---
	var target_yaw_rate := 0.0
	var yaw_responsiveness := 6.8 # Real heavy chassis rotational inertia — deliberate, planted, never twitchy!

	if air_uturn_active:
		# Crisp CTR Mid-Air U-Turn (preserves 100% of Sacred/Blue Fire reserves!)
		target_yaw_rate = -input_steer * (4.10 * turn_mult)
		yaw_responsiveness = 17.5
	elif is_drifting:
		# GENUINELY OBTUSE, SILKY WIDE-ARC CTR POWER-SLIDE!
		# Base arc = 0.58 rad/s (~33 deg/s); counter-steer = 0.10 rad/s (straight-line snaking!);
		# Full inner carve = 1.22 rad/s (~70 deg/s — sweeping, controllable, never overly sharp!)
		var inward := input_steer * float(drift_dir)
		var base_arc := 0.58 * drift_tightness
		var arc_turn := clampf(base_arc + inward * (0.64 * turn_mult), 0.10, 1.26)
		if on_ice:
			arc_turn *= 0.88
		target_yaw_rate = -float(drift_dir) * arc_turn
		yaw_responsiveness = 8.4
	else:
		var speed_factor := clampf(absf(forward_speed) / 16.0, 0.0, 1.0)
		var base_steer := 1.65 * turn_mult * s_steer
		if not is_grounded:
			base_steer = 1.38 * turn_mult
		elif fire_tier >= FireTier.SACRED:
			base_steer *= 0.84 if fire_tier == FireTier.BLUE else 0.92
		var dir_sign := 1.0 if forward_speed >= -0.5 else -1.0
		target_yaw_rate = -input_steer * base_steer * speed_factor * dir_sign
		yaw_responsiveness = 6.8 # Heavy planted kart steering mass!

	angular_yaw_vel = lerpf(angular_yaw_vel, target_yaw_rate, minf(1.0, delta * yaw_responsiveness))
	heading_yaw = wrapf(heading_yaw + angular_yaw_vel * delta, -PI, PI)

	var fwd := Vector3(-sin(heading_yaw), 0.0, -cos(heading_yaw))
	var right := Vector3(cos(heading_yaw), 0.0, -sin(heading_yaw))

	# --- 2. LONGITUDINAL ENGINE THRUST, SLOPE GRAVITY & WEIGHTY ACCELERATION ---
	var slope_dir := (fwd - ground_normal * fwd.dot(ground_normal)).normalized() if is_grounded else fwd
	var slope_gravity_pull := -slope_dir.y * 9.5 if is_grounded else 0.0

	if air_uturn_active:
		forward_speed = maxf(forward_speed * (1.0 - delta * 0.38), 16.0)
	elif input_brake_uturn and is_grounded:
		if reserves > 0.0:
			reserves = 0.0
			_set_fire_tier(FireTier.NONE)
		forward_speed = move_toward(forward_speed, -13.5, 54.0 * delta)
	elif input_accel and start_stall_timer <= 0.0:
		if forward_speed < target_top:
			# Strong heavy torque curve — brisk climb up to full top speed with zero sluggishness!
			var accel_rate := 28.0 * accel_mult * (float(surf_info["accel"]) if is_grounded else 1.0) + maxf(-4.0, slope_gravity_pull * 0.45)
			if fire_tier >= FireTier.SACRED:
				accel_rate *= 1.52
			elif fire_tier >= FireTier.RED:
				accel_rate *= 1.28
			if boost_surge_timer > 0.0:
				accel_rate += 16.0
			forward_speed = move_toward(forward_speed, target_top, maxf(14.0, accel_rate) * delta)
		else:
			var bleed := 26.0 if (is_grounded and surface_class == "offroad" and mask_timer <= 0.0) else 11.5
			forward_speed = move_toward(forward_speed, target_top, bleed * delta)
	else:
		# Realistic rolling tire resistance + slope pull when coasting!
		var coast := 14.5 if is_grounded else 2.5
		forward_speed = move_toward(forward_speed, 0.0, coast * delta)
		if is_grounded:
			forward_speed += slope_gravity_pull * delta * 0.55

	# --- 3. REALISTIC TIRE-TO-ROAD FRICTION (DRAMATICALLY INCREASES DURING DRIFT!) ---
	var horiz_vel := Vector3(velocity.x, 0.0, velocity.z)
	if is_grounded:
		# Real centrifugal cornering load pushes rear tires laterally when turning fast!
		var cur_lat := horiz_vel.dot(right)
		cur_lat += angular_yaw_vel * forward_speed * 0.085 * delta
		# Banked road lateral gravity assist (helps hold high-speed banked corner bowls!)
		cur_lat += ground_normal.dot(right) * 14.0 * delta

		# Authentic Tire-to-Surface Friction Coefficients:
		# - Normal road driving: 7.2 (tangible tire sidewall flex & heavy weight transfer!)
		# - Ice: 2.2 (genuinely slippery frozen lake surface!)
		# - Offroad sand/snow/ash: 5.0 (loose surface)
		# - POWER-SLIDE DRIFT: 21.0 road / 9.5 ice (~3x-4.3x INCREASED TIRE BITE!)
		#   Rear racing slicks dig hard into the tarmac during Power-Slide, eliminating sloppy
		#   outward slide and locking the kart onto a planted, weighty obtuse drift arc!
		var tire_lat_friction := 7.6 * s_grip
		if is_drifting:
			tire_lat_friction = 10.0 if on_ice else 22.5 * clampf(s_grip * 1.1, 0.55, 1.1)
		elif on_ice:
			tire_lat_friction = 2.2
		current_tire_friction = tire_lat_friction

		# Exponential lateral tire friction damping!
		lateral_slip_speed = cur_lat * exp(-tire_lat_friction * delta)
		horiz_vel = fwd * forward_speed + right * lateral_slip_speed

		# Follow undulating road slopes & rollers crisply (heavy downforce keeps wheels hugging crests until you hop!)
		var slope_vy := slope_dir.y * forward_speed
		if vertical_speed <= slope_vy + 2.2:
			vertical_speed = lerpf(vertical_speed, slope_vy - 1.9, minf(1.0, delta * 18.0))
	else:
		current_tire_friction = 0.0
		var desired_horiz := fwd * forward_speed
		if air_uturn_active:
			horiz_vel = horiz_vel.lerp(desired_horiz, minf(1.0, delta * 11.5))
		else:
			horiz_vel = horiz_vel.lerp(desired_horiz, minf(1.0, delta * 2.2))
		vertical_speed -= GRAVITY * delta
		vertical_speed = maxf(vertical_speed, -74.0)

	velocity = Vector3(horiz_vel.x, vertical_speed, horiz_vel.z)

func apply_kart_bump(push_vec: Vector3, side_sign: float, strength: float = 0.75) -> void:
	var right := Vector3(cos(heading_yaw), 0.0, -sin(heading_yaw))
	velocity += push_vec
	lateral_slip_speed += push_vec.dot(right) * 0.92
	susp_vel -= 1.6 * strength
	if visuals:
		visuals.trigger_collision_jolt(side_sign, strength)
	if wall_bump_cooldown <= 0.0:
		wall_bump_cooldown = 0.22
		collision_impact.emit(strength * 0.65)
		if is_player and AudioSynth:
			AudioSynth.play_sfx("bump", randf_range(0.92, 1.08), 0.85)

func _execute_move_and_walls(_delta: float) -> void:
	move_and_slide()
	var fwd := Vector3(-sin(heading_yaw), 0.0, -cos(heading_yaw))
	var right := Vector3(cos(heading_yaw), 0.0, -sin(heading_yaw))
	# v8: when a solid object really blocks the kart, the engine speed follows the real motion
	# (no more "spinning at 12 m/s" while pinned against a pillar or wall)
	if get_slide_collision_count() > 0 and is_grounded:
		var real_fwd := Vector3(velocity.x, 0.0, velocity.z).dot(fwd)
		var blocked := false
		for ci in range(get_slide_collision_count()):
			var cc := get_slide_collision(ci)
			var co = cc.get_collider()
			var nrm := cc.get_normal()
			var flat_n := Vector3(nrm.x, 0.0, nrm.z)
			if co is CollisionObject3D and ((co as CollisionObject3D).collision_layer & 2) != 0 and nrm.y < 0.55 and flat_n.length_squared() > 0.01:
				# only a (near) head-on block counts; scraping along a wall keeps its speed
				if -fwd.dot(flat_n.normalized()) > 0.75:
					blocked = true
		if blocked and forward_speed > 0.0 and real_fwd < forward_speed * 0.5:
			_pinned_t += _delta
			if _pinned_t > 0.25:
				forward_speed = maxf(real_fwd, 0.0)
		else:
			_pinned_t = 0.0
	else:
		_pinned_t = 0.0

	for i in range(get_slide_collision_count()):
		var col := get_slide_collision(i)
		var collider = col.get_collider()
		if collider == null:
			continue
		var col_normal := col.get_normal()
		if col_normal.y > 0.55:
			continue
		# v7.0 CRITICAL FLOOR-SEAM FIX:
		# ONLY Layer 2 (TrackWall / solid trackside obstacles) can ever trigger wall impacts!
		# Road/Offroad/Ramp floor layers (1 | 4 | 8) MUST NEVER block or bounce the kart!
		var is_wall: bool = (collider is CollisionObject3D) and (((collider as CollisionObject3D).collision_layer & 2) != 0)
		if not is_wall:
			continue

		var flat_n := Vector3(col_normal.x, 0.0, col_normal.z)
		if flat_n.length_squared() < 0.001:
			continue
		flat_n = flat_n.normalized()
		var head_on := -fwd.dot(flat_n)
		var side_sign := signf(flat_n.dot(right))
		var strength: String = str(collider.get_meta("collision_strength", "heavy"))
		last_collision_strength = strength

		if strength == "soft":
			# Soft foliage/bushes/snow drifts: mild speed brush, preserves reserves & 0 Wumpa lost!
			if head_on > 0.10:
				forward_speed = maxf(6.0, forward_speed * 0.94)
				lateral_slip_speed += flat_n.dot(right) * 2.6
				if visuals:
					visuals.trigger_collision_jolt(side_sign, 0.28)
				if wall_bump_cooldown <= 0.0:
					wall_bump_cooldown = 0.24
					collision_impact.emit(0.22)
					if is_player and AudioSynth:
						AudioSynth.play_sfx("bump", 1.32, 0.42)
		elif strength == "medium":
			# Wooden fences, signposts, timber rails: moderate impact, loses 1 Wumpa on direct hit!
			if head_on > 0.46 and forward_speed > 13.0:
				reserves *= 0.55
				if reserves < 0.2:
					reserves = 0.0
					_set_fire_tier(FireTier.NONE)
				var rebound_med := maxf(5.5, forward_speed * 0.24)
				forward_speed = maxf(9.0, forward_speed * 0.66)
				velocity += flat_n * rebound_med
				lateral_slip_speed += flat_n.dot(right) * 7.5
				susp_vel -= 1.8
				if visuals:
					visuals.trigger_collision_jolt(side_sign, 0.62)
				if wall_bump_cooldown <= 0.0:
					wall_bump_cooldown = 0.28
					lose_fruits(1, false)
					collision_impact.emit(0.62)
					if is_player and AudioSynth:
						AudioSynth.play_sfx("bump", 1.02, 0.78)
			elif head_on > 0.12:
				forward_speed *= 0.96
				lateral_slip_speed += flat_n.dot(right) * 4.2
				var tang_m := fwd - flat_n * fwd.dot(flat_n)
				if tang_m.length_squared() > 0.01:
					heading_yaw = lerp_angle(heading_yaw, atan2(-tang_m.x, -tang_m.z), 0.25)
				if visuals:
					visuals.trigger_collision_jolt(side_sign, 0.34)
				if wall_bump_cooldown <= 0.0 and forward_speed > 16.0:
					wall_bump_cooldown = 0.24
					collision_impact.emit(0.30)
					if is_player and AudioSynth:
						AudioSynth.play_sfx("bump", 1.20, 0.55)
		else:
			# Heavy solid rock/stone/steel/lab vats/obelisks: hard rebound, kills reserves, loses 2-3 Wumpa!
			if head_on > 0.48 and forward_speed > 13.5:
				var impact_spd := forward_speed
				reserves = 0.0
				_set_fire_tier(FireTier.NONE)
				_end_drift(false)
				var rebound_spd := maxf(8.2, impact_spd * 0.36)
				forward_speed = maxf(5.5, impact_spd * 0.36)
				velocity += flat_n * rebound_spd
				lateral_slip_speed += flat_n.dot(right) * 11.2
				susp_vel -= 2.8
				if visuals:
					visuals.trigger_collision_jolt(side_sign, 1.0)
				if wall_bump_cooldown <= 0.0:
					wall_bump_cooldown = 0.32
					var wumpa_loss := 3 if impact_spd > 36.0 else 2
					lose_fruits(wumpa_loss, false)
					collision_impact.emit(0.95)
					if is_player and AudioSynth:
						AudioSynth.play_sfx("bump", 0.76, 1.0)
			elif head_on > 0.12:
				forward_speed *= 0.94
				lateral_slip_speed += flat_n.dot(right) * 5.2
				var tangent := fwd - flat_n * fwd.dot(flat_n)
				if tangent.length_squared() > 0.01:
					var tang_yaw := atan2(-tangent.x, -tangent.z)
					heading_yaw = lerp_angle(heading_yaw, tang_yaw, 0.30)
				if visuals:
					visuals.trigger_collision_jolt(side_sign, 0.48)
				if wall_bump_cooldown <= 0.0 and forward_speed > 17.0:
					wall_bump_cooldown = 0.24
					collision_impact.emit(0.42)
					if is_player and AudioSynth:
						AudioSynth.play_sfx("bump", 1.12, 0.68)

func _check_fall_and_progress() -> void:
	if track_spline == null:
		return
	var query: Dictionary = track_spline.project_point(global_position, spline_t)
	var new_t: float = query["t"]
	var track_pos: Vector3 = query["pos"]
	var track_fwd: Vector3 = query["forward"]
	var lateral_dist: float = query["lateral_dist"]
	var y_below: float = track_pos.y - global_position.y

	if is_grounded and surface_class != "offroad" and lateral_dist < float(query["half_width"]) + 2.5 and y_below < 3.5 and not bool(query.get("gap", false)) and _oob_timer <= 0.0:
		_store_safe_respawn(int(query["index"]))

	if y_below > 22.0 or global_position.y < -120.0:
		force_respawn(true)
		return
	# resting in a pit / ravine well below the road (missed jump): count as out of bounds
	if is_grounded and y_below > 7.0 and surface_type != "kicker":
		_oob_timer += get_physics_process_delta_time()
	if _oob_timer > 0.45:
		_oob_timer = 0.0
		force_respawn(false)
		return
	if world_ref != null and world_ref.world != null and respawn_timer <= 0.0:
		var liq: Dictionary = world_ref.world.liquid_at(global_position.x, global_position.z)
		if not liq.is_empty():
			var depth_below := float(liq["y"]) - global_position.y
			var kind := str(liq["kind"])
			if (kind in ["lava", "acid"] and depth_below > -0.2) or depth_below > float(liq.get("deep", 1.6)):
				force_respawn(true)
				return

	var kart_fwd := Vector3(-sin(heading_yaw), 0.0, -cos(heading_yaw))
	wrong_way = (kart_fwd.dot(track_fwd) < -0.45) and forward_speed > 8.0

	var quad := clampi(int(new_t * 4.0), 0, 3)
	if quad == 0:
		checkpoint_mask |= 1
	elif quad == 1 and (checkpoint_mask & 1) != 0:
		checkpoint_mask |= 2
	elif quad == 2 and ((checkpoint_mask & 2) != 0 or (checkpoint_mask & 1) != 0):
		checkpoint_mask |= 4
	elif quad == 3 and (checkpoint_mask & 4) != 0:
		checkpoint_mask |= 8

	if prev_spline_t > 0.78 and new_t < 0.22 and (checkpoint_mask & 12) == 12:
		var lap_dur := race_elapsed - lap_start_time
		lap_start_time = race_elapsed
		if lap_dur < best_lap_time:
			best_lap_time = lap_dur
		checkpoint_mask = 1
		lap_completed.emit(current_lap, lap_dur)
		if current_lap >= total_laps:
			race_finished_flag = true
			race_finished.emit(race_elapsed)
		else:
			current_lap += 1
			if is_player:
				if current_lap == total_laps:
					status_banner.emit("final_lap", Color(1.0, 0.35, 0.14))
				if AudioSynth:
					AudioSynth.play_sfx("lap_chime", 1.15 if current_lap == total_laps else 1.0)

	prev_spline_t = spline_t
	spline_t = new_t
	var adjusted_t := spline_t
	if current_lap == 1 and adjusted_t > 0.85 and checkpoint_mask == 0:
		adjusted_t -= 1.0
	total_progress = float(current_lap - 1) + adjusted_t

func _store_safe_respawn(idx: int) -> void:
	## Remember a safe on-track point; never right in front of a gap you cannot clear from a standing start.
	var S: Array = track_spline.samples
	var n := S.size()
	var j := idx
	for k in range(40):
		var probe := (idx + k) % n
		if bool(S[probe]["gap"]):
			j = probe
			while bool(S[j % n]["gap"]):
				j = (j + 1) % n
			j = (j + 6) % n
			break
	var s: Dictionary = S[j]
	safe_respawn_pos = (s["pos"] as Vector3) + (s["up"] as Vector3) * 0.65
	var f: Vector3 = s["forward"]
	safe_respawn_yaw = atan2(-f.x, -f.z)

func notify_shortcut(sc_id: String, sc_name: String) -> void:
	if shortcut_cooldowns.has(sc_id):
		return
	shortcut_cooldowns[sc_id] = 6.0
	add_boost(FireTier.ORANGE, 1.8, 9.0, false)
	shortcut_triggered.emit(sc_id, sc_name)
	if is_player:
		status_banner.emit("shortcut_found", Color(0.28, 1.0, 0.72))
		if AudioSynth:
			AudioSynth.play_sfx("shortcut", 1.0, 1.1)

func _update_visuals(delta: float) -> void:
	var fwd := Vector3(-sin(heading_yaw), 0.0, -cos(heading_yaw))
	var up := ground_normal if is_grounded else Vector3.UP
	var right := fwd.cross(up).normalized()
	if right.length_squared() < 0.01:
		right = Vector3.RIGHT
	var ortho_fwd := up.cross(right).normalized()
	var target_basis := Basis(right, up, -ortho_fwd).orthonormalized()
	basis = basis.slerp(target_basis, minf(1.0, delta * 12.5))

	if visuals:
		visuals.update_anim(delta, {
			"speed": forward_speed,
			"steer": input_steer,
			"is_drifting": is_drifting,
			"drift_dir": drift_dir,
			"drift_charge": drift_charge,
			"fire_tier": fire_tier,
			"is_grounded": is_grounded,
			"air_uturn": air_uturn_active,
			"susp_offset": susp_offset,
			"weight_pitch": weight_pitch,
			"weight_roll": weight_roll,
			"wheel_y_offsets": wheel_y_offsets,
			"wheel_contacts": wheel_ground_contact,
			"lateral_slip": lateral_slip_speed,
			"accelerating": input_accel and race_started,
			"spinout": spinout_timer > 0.0,
			"shield": shield_active,
			"shield_juiced": shield_juiced,
			"mask": mask_timer > 0.0,
			"tnt": tnt_attached,
			"tnt_timer": tnt_timer,
			"surface_type": surface_class,
			"dust_col": surf_info["dust"],
			"finished": race_finished_flag
		})

	if is_player and AudioSynth:
		AudioSynth.update_kart_audio(
			clampf(absf(forward_speed) / 56.0, 0.0, 1.4),
			fire_tier,
			is_drifting,
			not is_grounded,
			0.0
		)

func _clear_one_shot_inputs() -> void:
	input_hop_just_pressed = false
	input_boost_just_pressed = false
	input_item_just_pressed = false
