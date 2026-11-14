class_name Phys
extends RefCounted
## Shared physical constants (meters, seconds, radians).
## Y is up. Team 0 (blue) defends +Z and attacks toward -Z.

const TICK_RATE := 120
const DT := 1.0 / 120.0
const GRAVITY := 6.5

# ---------------------------------------------------------------- Arena
const HALF_W := 41.0          # half width (x)
const HALF_L := 52.0          # half length (z), goal line
const HEIGHT := 20.5          # ceiling height
const CHAMFER := 11.5         # corner cut along each axis
const CURVE_R := 6.4          # floor/wall/ceiling transition radius
const GOAL_HALF_W := 8.9
const GOAL_H := 6.45
const GOAL_DEPTH := 8.8

# ---------------------------------------------------------------- Ball
const BALL_R := 0.92
const BALL_MASS := 30.0
const BALL_MAX_SPEED := 60.0
const BALL_MAX_ANG := 6.0
const BALL_DRAG := 0.03
const BALL_RESTITUTION := 0.6
const BALL_MU := 0.285
const BALL_Y := 2.0
const BALL_A := 3.0           # spin coupling (1/m^2)

# ---------------------------------------------------------------- Car
const CAR_MASS := 180.0
const CAR_MAX_SPEED := 23.0
const SUPERSONIC_START := 22.0
const SUPERSONIC_MAINTAIN := 21.0
const SUPERSONIC_MAINTAIN_TIME := 1.0
const THROTTLE_TOP_SPEED := 14.1
const BOOST_ACCEL_GROUND := 9.9167
const BOOST_ACCEL_AIR := 10.583
const BOOST_USE := 33.333
const BOOST_MIN_TIME := 0.1
const BOOST_KICKOFF := 33.333
const BRAKE_ACCEL := 35.0
const COAST_ACCEL := 5.25
const AIR_THROTTLE_ACCEL := 0.6667

const JUMP_IMPULSE := 2.9167
const JUMP_HOLD_ACCEL := 14.583
const JUMP_HOLD_TIME := 0.2
const JUMP_MIN_TIME := 0.025
const DOUBLE_JUMP_WINDOW := 1.25
const DODGE_DEADZONE := 0.5
const FLIP_IMPULSE := 5.0
const FLIP_SIDE_MAX_SCALE := 1.9
const FLIP_BACK_MAX_SCALE := 2.5
const FLIP_TORQUE_TIME := 0.65
const FLIP_ANG_ACCEL := 62.0
const FLIP_ZDAMP_START := 0.15
const FLIP_ZDAMP_END := 0.21
const FLIP_ZDAMP := 0.35

const MAX_ANG_SPEED := 5.5
# Air control (angular acceleration rad/s^2 and damping 1/s)
const T_PITCH := 12.146
const T_YAW := 8.92
const T_ROLL := 36.08
const D_PITCH := 2.798
const D_YAW := 1.886
const D_ROLL := 4.472

# Suspension (per unit mass)
const SUSP_K := 200.0
const SUSP_C := 8.0
const SUSP_CONN_Y := 0.12
const SUSP_REST := 0.302
const SUSP_MAX := 0.37
const SUSP_BOTTOM := 0.13     # min ray distance before hard stop

const LAT_FRICTION := 26.0
const LAT_FRICTION_DRIFT := 2.6
const LAT_MAX_ACCEL := 46.0
const LAT_MAX_ACCEL_DRIFT := 9.0

const DEMO_RESPAWN := 3.0
const BIG_PAD_AMOUNT := 100.0
const SMALL_PAD_AMOUNT := 12.0
const BIG_PAD_RESPAWN := 10.0
const SMALL_PAD_RESPAWN := 4.0

const STEER_SPEEDS := [0.0, 5.0, 10.0, 15.0, 17.5, 25.0]
const STEER_CURV := [0.69, 0.398, 0.235, 0.1375, 0.11, 0.088]


static func throttle_accel(speed: float) -> float:
	var s := absf(speed)
	if s < 14.0:
		return lerpf(16.0, 1.6, s / 14.0)
	if s < THROTTLE_TOP_SPEED:
		return lerpf(1.6, 0.0, (s - 14.0) / 0.1)
	return 0.0


static func steer_curvature(speed: float) -> float:
	var s := absf(speed)
	for i in range(1, STEER_SPEEDS.size()):
		var s1: float = STEER_SPEEDS[i]
		if s <= s1:
			var s0: float = STEER_SPEEDS[i - 1]
			var t := (s - s0) / (s1 - s0)
			return lerpf(STEER_CURV[i - 1], STEER_CURV[i], t)
	return STEER_CURV[STEER_CURV.size() - 1]


## Extra ball impulse factor, keyed by relative speed (m/s).
static func hit_factor(rel_speed: float) -> float:
	if rel_speed <= 5.0:
		return 0.65
	if rel_speed <= 23.0:
		return lerpf(0.65, 0.55, (rel_speed - 5.0) / 18.0)
	if rel_speed <= 46.0:
		return lerpf(0.55, 0.30, (rel_speed - 23.0) / 23.0)
	return 0.30


static func own_goal_z(team: int) -> float:
	return HALF_L if team == 0 else -HALF_L


static func attack_dir(team: int) -> float:
	return -1.0 if team == 0 else 1.0


static func team_color(team: int) -> Color:
	return Color(0.1, 0.45, 1.0) if team == 0 else Color(1.0, 0.45, 0.05)
