class_name Surfaces
extends RefCounted

## v8 Ground surface physics table. Every road, shoulder and terrain material maps to one of these ids.
##  speed : top-speed multiplier            grip  : lateral tire friction multiplier (normal & drift)
##  accel : acceleration multiplier          steer : steering multiplier
##  drain : Reserves drain rate (1 = normal; off-road bleeds boost fast, hop across it to keep Reserves!)
##  cls   : "road" | "offroad" | "ice" (visual/audio class)   deadly: touching it = respawn (lava/acid/deep water)
##  dust  : particle colour, rumble: suspension buzz amplitude (bumpy planks / cobbles / grating)

const DATA := {
	# ---------------- paved / driving surfaces ----------------
	"stone":     {"speed": 1.00, "grip": 1.00, "accel": 1.00, "steer": 1.00, "drain": 1.0, "cls": "road",    "dust": Color(0.90, 0.84, 0.74), "rumble": 0.00},
	"cobble":    {"speed": 0.99, "grip": 0.97, "accel": 0.98, "steer": 1.00, "drain": 1.0, "cls": "road",    "dust": Color(0.86, 0.78, 0.64), "rumble": 0.35},
	"dirt":      {"speed": 0.97, "grip": 0.86, "accel": 0.95, "steer": 0.97, "drain": 1.2, "cls": "road",    "dust": Color(0.74, 0.56, 0.36), "rumble": 0.15},
	"wood":      {"speed": 1.00, "grip": 0.95, "accel": 1.00, "steer": 1.00, "drain": 1.0, "cls": "road",    "dust": Color(0.70, 0.56, 0.40), "rumble": 0.45},
	"wet_stone": {"speed": 0.98, "grip": 0.66, "accel": 0.92, "steer": 0.92, "drain": 1.0, "cls": "road",    "dust": Color(0.70, 0.86, 0.92), "rumble": 0.10},
	"metal":     {"speed": 1.02, "grip": 1.05, "accel": 1.02, "steer": 1.00, "drain": 1.0, "cls": "road",    "dust": Color(0.80, 0.86, 0.90), "rumble": 0.05},
	"grating":   {"speed": 1.00, "grip": 0.98, "accel": 1.00, "steer": 1.00, "drain": 1.0, "cls": "road",    "dust": Color(0.78, 0.84, 0.86), "rumble": 0.55},
	"asphalt":   {"speed": 1.03, "grip": 1.08, "accel": 1.03, "steer": 1.02, "drain": 1.0, "cls": "road",    "dust": Color(0.66, 0.66, 0.74), "rumble": 0.00},
	"neon":      {"speed": 1.04, "grip": 1.04, "accel": 1.04, "steer": 1.00, "drain": 0.9, "cls": "road",    "dust": Color(0.70, 0.50, 1.00), "rumble": 0.00},
	"basalt":    {"speed": 1.00, "grip": 0.96, "accel": 1.00, "steer": 1.00, "drain": 1.0, "cls": "road",    "dust": Color(0.50, 0.40, 0.36), "rumble": 0.20},
	"packed_snow": {"speed": 0.97, "grip": 0.78, "accel": 0.94, "steer": 0.95, "drain": 1.1, "cls": "road",  "dust": Color(0.94, 0.97, 1.00), "rumble": 0.10},
	"ice":       {"speed": 1.02, "grip": 0.30, "accel": 0.80, "steer": 0.74, "drain": 0.8, "cls": "ice",     "dust": Color(0.88, 0.96, 1.00), "rumble": 0.00},
	"glass":     {"speed": 1.03, "grip": 0.88, "accel": 1.00, "steer": 1.00, "drain": 1.0, "cls": "road",    "dust": Color(0.70, 0.95, 1.00), "rumble": 0.00},
	"kicker":    {"speed": 1.00, "grip": 1.00, "accel": 1.00, "steer": 1.00, "drain": 1.0, "cls": "road",    "dust": Color(0.86, 0.80, 0.70), "rumble": 0.00},
	# ---------------- off-road (slow, bleeds Reserves: hop across to save boost) ----------------
	"grass":     {"speed": 0.70, "grip": 0.80, "accel": 0.78, "steer": 0.95, "drain": 4.6, "cls": "offroad", "dust": Color(0.52, 0.66, 0.30), "rumble": 0.30},
	"sand":      {"speed": 0.62, "grip": 0.72, "accel": 0.70, "steer": 0.92, "drain": 5.4, "cls": "offroad", "dust": Color(0.92, 0.80, 0.56), "rumble": 0.20},
	"mud":       {"speed": 0.55, "grip": 0.62, "accel": 0.62, "steer": 0.88, "drain": 6.0, "cls": "offroad", "dust": Color(0.44, 0.32, 0.20), "rumble": 0.40},
	"gravel":    {"speed": 0.80, "grip": 0.76, "accel": 0.86, "steer": 0.94, "drain": 3.2, "cls": "offroad", "dust": Color(0.66, 0.62, 0.56), "rumble": 0.60},
	"snow":      {"speed": 0.64, "grip": 0.70, "accel": 0.72, "steer": 0.90, "drain": 5.0, "cls": "offroad", "dust": Color(0.96, 0.98, 1.00), "rumble": 0.15},
	"shallow_water": {"speed": 0.68, "grip": 0.70, "accel": 0.74, "steer": 0.90, "drain": 4.0, "cls": "offroad", "dust": Color(0.70, 0.90, 1.00), "rumble": 0.10},
	"ash":       {"speed": 0.66, "grip": 0.74, "accel": 0.74, "steer": 0.92, "drain": 5.0, "cls": "offroad", "dust": Color(0.40, 0.36, 0.36), "rumble": 0.20},
	"rock":      {"speed": 0.74, "grip": 0.82, "accel": 0.80, "steer": 0.95, "drain": 4.0, "cls": "offroad", "dust": Color(0.62, 0.58, 0.52), "rumble": 0.50},
	"regolith":  {"speed": 0.68, "grip": 0.74, "accel": 0.74, "steer": 0.92, "drain": 5.0, "cls": "offroad", "dust": Color(0.66, 0.56, 0.80), "rumble": 0.25},
	# ---------------- deadly ----------------
	"lava":      {"speed": 0.50, "grip": 0.50, "accel": 0.50, "steer": 0.80, "drain": 9.0, "cls": "offroad", "dust": Color(1.00, 0.50, 0.10), "rumble": 0.00, "deadly": true},
	"acid":      {"speed": 0.50, "grip": 0.50, "accel": 0.50, "steer": 0.80, "drain": 9.0, "cls": "offroad", "dust": Color(0.40, 1.00, 0.30), "rumble": 0.00, "deadly": true},
	"deep_water": {"speed": 0.50, "grip": 0.50, "accel": 0.50, "steer": 0.80, "drain": 9.0, "cls": "offroad", "dust": Color(0.70, 0.90, 1.00), "rumble": 0.00, "deadly": true},
}

const _DEFAULT := {"speed": 1.0, "grip": 1.0, "accel": 1.0, "steer": 1.0, "drain": 1.0, "cls": "road", "dust": Color(0.90, 0.84, 0.74), "rumble": 0.0}

static func info(id: String) -> Dictionary:
	if DATA.has(id):
		return DATA[id]
	if id == "road":
		return DATA["stone"]
	if id == "offroad":
		return DATA["grass"]
	return _DEFAULT

static func is_offroad(id: String) -> bool:
	return str(info(id)["cls"]) == "offroad"

static func is_deadly(id: String) -> bool:
	return bool(info(id).get("deadly", false))
