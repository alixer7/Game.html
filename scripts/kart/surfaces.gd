class_name Surfaces
extends RefCounted
## Surface table. Every drivable collider carries meta "surface" (int id below).
## Values are multipliers relative to the kart's base parameters, tuned so each
## surface creates a strategic trade-off rather than a cosmetic difference.

enum {
	ROAD,          # packed stone / cobbles: the reference surface
	DIRT,          # forest dirt: slightly slower, drifts a little looser
	GRASS,         # off-road grass: noticeably slower, drains reserve
	SAND,          # river sand bars: slow, drains reserve hard
	MUD,           # creek mud: very slow, punishes mistakes
	ICE,           # (future tracks) almost no grip, no drag
	ROCK,          # bare stone: grippy, a touch bumpy
	WOOD,          # logs / boardwalks / flume floor: fast & grippy
	METAL,         # (future tracks) fast, slippery drifts
	SHALLOW_WATER, # still shallow water: slow, sprays
	CURRENT,       # flowing water: pushes you along the flow direction
	MOSS,          # mossy stone: grippy but slows a little
	COUNT,
}

const NAMES := ["road", "dirt", "grass", "sand", "mud", "ice", "rock", "wood", "metal",
	"shallow_water", "current", "moss"]

# grip: lateral grip multiplier (normal driving)
# drift_grip: lateral grip multiplier while power-sliding
# speed: top-speed multiplier
# accel: engine acceleration multiplier
# drag: extra constant deceleration (m/s^2)
# drain: boost-reserve consumption multiplier
# charge: drift-charge rate multiplier
# flow: strength of flowing-water push (m/s added toward flow)
# fx: particle style id (0 none, 1 dust, 2 grass, 3 splash, 4 mud, 5 sparks, 6 wood chips)
const TABLE := [
	{"grip": 1.00, "drift_grip": 1.00, "speed": 1.00, "accel": 1.00, "drag": 0.0, "drain": 1.0, "charge": 1.00, "flow": 0.0, "fx": 1, "bump": 0.0},
	{"grip": 0.92, "drift_grip": 0.88, "speed": 0.97, "accel": 0.95, "drag": 0.4, "drain": 1.0, "charge": 1.05, "flow": 0.0, "fx": 1, "bump": 0.02},
	{"grip": 0.82, "drift_grip": 0.85, "speed": 0.80, "accel": 0.80, "drag": 2.5, "drain": 1.8, "charge": 0.80, "flow": 0.0, "fx": 2, "bump": 0.05},
	{"grip": 0.72, "drift_grip": 0.80, "speed": 0.76, "accel": 0.70, "drag": 3.5, "drain": 2.2, "charge": 0.75, "flow": 0.0, "fx": 1, "bump": 0.03},
	{"grip": 0.60, "drift_grip": 0.70, "speed": 0.62, "accel": 0.60, "drag": 5.0, "drain": 3.0, "charge": 0.55, "flow": 0.0, "fx": 4, "bump": 0.04},
	{"grip": 0.22, "drift_grip": 0.55, "speed": 1.00, "accel": 0.70, "drag": 0.0, "drain": 0.8, "charge": 1.10, "flow": 0.0, "fx": 0, "bump": 0.0},
	{"grip": 1.05, "drift_grip": 1.00, "speed": 1.00, "accel": 1.00, "drag": 0.2, "drain": 1.0, "charge": 1.00, "flow": 0.0, "fx": 5, "bump": 0.04},
	{"grip": 1.02, "drift_grip": 0.98, "speed": 1.02, "accel": 1.00, "drag": 0.0, "drain": 1.0, "charge": 1.00, "flow": 0.0, "fx": 6, "bump": 0.01},
	{"grip": 0.95, "drift_grip": 0.80, "speed": 1.03, "accel": 1.00, "drag": 0.0, "drain": 0.9, "charge": 1.10, "flow": 0.0, "fx": 5, "bump": 0.0},
	{"grip": 0.75, "drift_grip": 0.80, "speed": 0.84, "accel": 0.80, "drag": 2.0, "drain": 1.4, "charge": 0.60, "flow": 0.0, "fx": 3, "bump": 0.0},
	{"grip": 0.68, "drift_grip": 0.78, "speed": 0.92, "accel": 0.85, "drag": 0.6, "drain": 1.2, "charge": 0.60, "flow": 1.0, "fx": 3, "bump": 0.02},
	{"grip": 0.98, "drift_grip": 0.95, "speed": 0.95, "accel": 0.95, "drag": 0.8, "drain": 1.1, "charge": 0.95, "flow": 0.0, "fx": 2, "bump": 0.01},
]


static func get_info(id: int) -> Dictionary:
	if id < 0 or id >= TABLE.size():
		return TABLE[ROAD]
	return TABLE[id]


static func is_offroad(id: int) -> bool:
	return id == GRASS or id == SAND or id == MUD or id == SHALLOW_WATER


static func is_water(id: int) -> bool:
	return id == SHALLOW_WATER or id == CURRENT
