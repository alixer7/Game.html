class_name KartParams
extends Resource
## Tunable handling model for one kart chassis. All units are SI (m, s, rad).
## The four chassis classes trade these off in small, readable amounts so that
## skill matters far more than stats.

@export var display_name := "Balanced"

@export_group("Engine")
@export var max_speed := 26.0            ## base top speed on ROAD (m/s)
@export var accel := 17.0                ## launch acceleration at 0 m/s (m/s^2)
@export var accel_falloff := 1.7         ## exponent: how acceleration tapers near top speed
@export var reverse_speed := 8.0
@export var reverse_accel := 12.0
@export var brake_decel := 32.0
@export var coast_decel := 3.5           ## no throttle, no brake
@export var overspeed_decel := 4.5       ## how fast excess speed above the current cap bleeds off
@export var slope_factor := 0.55         ## fraction of gravity applied along slopes

@export_group("Steering")
@export var turn_rate_max := 2.35        ## yaw rate at turn_full_speed (rad/s)
@export var turn_full_speed := 9.0       ## speed where steering reaches full authority
@export var turn_rate_top := 1.45        ## yaw rate at top speed (rad/s)
@export var steer_response := 9.0        ## digital steering smoothing (1/s)
@export var grip := 11.0                 ## lateral grip rate (1/s)
@export var turn_scrub := 0.16           ## speed lost per m/s of lateral slip absorbed

@export_group("Power slide")
@export var drift_min_speed := 9.0
@export var drift_base_rate := 1.45      ## yaw rate with neutral stick during slide
@export var drift_steer_range := 0.95    ## +/- yaw rate added by steering into/out of the slide
@export var drift_grip := 2.6            ## lateral grip while sliding (lower = wider slide)
@export var drift_scrub := 0.07          ## slides keep momentum far better than scrubbing turns
@export var drift_recover_time := 0.28   ## grip blend-back after releasing a slide
@export var charge_times := PackedFloat32Array([0.95, 0.82, 0.72])  ## meter fill time per stage
@export var hot_zone := 0.70             ## meter value where a boost tap becomes valid
@export var perfect_zone := 0.90         ## meter value for a perfect tap
@export var overheat_grace := 0.06       ## meter can overshoot 1.0 by this much before backfiring
@export var spark_reserve := PackedFloat32Array([0.55, 0.75, 1.0])  ## seconds of reserve per stage (perfect)
@export var spark_kick := PackedFloat32Array([1.4, 1.9, 2.5])       ## instant m/s per stage (perfect)
@export var hook_rate := 3.3             ## yaw rate during a hook-turn (slide + pull back)
@export var hook_decel := 9.0            ## speed bled per second while hooking
@export var hook_boost_window := 0.4     ## seconds after a hook where a spark gives a bonus
@export var hook_boost_bonus := 0.45

@export_group("Boost")
@export var boost_bonus := 0.24          ## +top speed fraction in tier 1 (Boost)
@export var overdrive_bonus := 0.40      ## +top speed fraction in tier 2 (Overdrive)
@export var boost_accel := 34.0          ## acceleration toward boosted top speed
@export var reserve_cap := 4.5
@export var overdrive_threshold := 3.6   ## chained reserve that upgrades Boost into Overdrive
@export var overdrive_drain := 1.15      ## Overdrive burns reserve slightly faster

@export_group("Air")
@export var hop_velocity := 4.6
@export var air_turn_rate := 1.25
@export var air_steer_vel := 0.22        ## rad/s the velocity vector can be nudged in the air
@export var air_boost_min_time := 0.5    ## hang time needed for a landing boost
@export var air_boost_rate := 0.9        ## reserve per second of hang time above the minimum
@export var air_boost_max := 1.2

@export_group("Impacts")
@export var graze_threshold := 0.26      ## sin(impact angle) below this is a graze
@export var head_on_threshold := 0.62
@export var mass := 1.0                  ## kart-vs-kart bump weight

@export_group("Feel")
@export var bounce_damping := 0.35


static func make_class(kind: String) -> KartParams:
	var p := KartParams.new()
	match kind:
		"speed":
			p.display_name = "Speed"
			p.max_speed = 26.9
			p.accel = 15.2
			p.turn_rate_top = 1.36
			p.drift_base_rate = 1.38
			p.mass = 1.15
		"accel":
			p.display_name = "Acceleration"
			p.max_speed = 25.6
			p.accel = 20.0
			p.accel_falloff = 1.5
			p.mass = 0.9
		"turning":
			p.display_name = "Turning"
			p.max_speed = 25.5
			p.accel = 16.4
			p.turn_rate_top = 1.6
			p.turn_rate_max = 2.5
			p.drift_base_rate = 1.56
			p.drift_steer_range = 1.05
			p.mass = 0.85
		_:
			p.display_name = "Balanced"
	return p
