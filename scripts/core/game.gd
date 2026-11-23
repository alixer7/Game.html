extends Node
## Global game state: settings, race configuration, records, input map and
## the touch input bridge.

const SETTINGS_PATH := "user://settings.cfg"
const RECORDS_PATH := "user://records.cfg"

const CHARACTERS := [
	{"id": "rusk", "name": "Rusk", "species": "fox", "fur": Color(0.95, 0.48, 0.15), "accent": Color(1, 0.96, 0.9), "kart": Color(0.92, 0.18, 0.12), "chassis": "balanced"},
	{"id": "bandit", "name": "Bandit", "species": "raccoon", "fur": Color(0.55, 0.55, 0.58), "accent": Color(0.15, 0.15, 0.17), "kart": Color(0.2, 0.45, 0.95), "chassis": "accel"},
	{"id": "ribbo", "name": "Ribbo", "species": "frog", "fur": Color(0.35, 0.78, 0.25), "accent": Color(0.95, 0.95, 0.6), "kart": Color(0.98, 0.82, 0.1), "chassis": "turning"},
	{"id": "bramble", "name": "Bramble", "species": "bear", "fur": Color(0.5, 0.32, 0.18), "accent": Color(0.85, 0.7, 0.5), "kart": Color(0.15, 0.6, 0.3), "chassis": "speed"},
	{"id": "hoots", "name": "Hoots", "species": "owl", "fur": Color(0.62, 0.48, 0.32), "accent": Color(1.0, 0.85, 0.45), "kart": Color(0.55, 0.25, 0.75), "chassis": "turning"},
	{"id": "clover", "name": "Clover", "species": "rabbit", "fur": Color(0.95, 0.92, 0.88), "accent": Color(1.0, 0.6, 0.7), "kart": Color(1.0, 0.45, 0.65), "chassis": "accel"},
	{"id": "tusker", "name": "Tusker", "species": "boar", "fur": Color(0.45, 0.3, 0.25), "accent": Color(0.95, 0.9, 0.8), "kart": Color(0.9, 0.5, 0.1), "chassis": "speed"},
	{"id": "splash", "name": "Splash", "species": "otter", "fur": Color(0.42, 0.28, 0.18), "accent": Color(0.9, 0.82, 0.7), "kart": Color(0.1, 0.75, 0.8), "chassis": "balanced"},
]

const TRACKS := [
	{"id": "timberfall", "name": "Timberfall Rapids", "data": "res://data/timberfall.json", "laps": 3},
	{"id": "proving", "name": "Proving Grounds (practice)", "data": "", "laps": 3},
]

const DIFFICULTIES := ["Easy", "Normal", "Hard", "Expert"]

var settings := {
	"quality": 2,
	"render_scale": 1.0,
	"fps_cap": 60,
	"shadows": true,
	"vol_master": 0.9,
	"vol_music": 0.6,
	"vol_sfx": 0.9,
	"auto_accel": true,
	"steer_sensitivity": 1.0,
	"steer_mode": "stick",     # stick | buttons
	"touch_scale": 1.0,
	"touch_opacity": 0.55,
	"touch_layout": {},        # button id -> [x_frac, y_frac, scale]
	"haptics": true,
	"show_fps": false,
	"screen_margin": 0.02,     # extra inset (fraction of width) for rounded/curved screens
	"rubber_band": 1,          # 0 off, 1 light, 2 classic
}

var race := {
	"track": "timberfall",
	"mode": "race",            # race | time_trial | practice
	"laps": 3,
	"difficulty": 1,
	"racers": 8,
	"character": 0,
	"chassis": "",             # empty = character default
}

var last_results: Array = []
var records := {}

# Touch bridge (written by TouchControls, read by PlayerDriver)
var touch := {
	"active": false,
	"steer": 0.0,
	"stick_y": 0.0,
	"accel": false,
	"brake": false,
	"drift": false,
	"boost_pressed": false,
	"item_pressed": false,
	"look_back": false,
}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_setup_inputs()
	load_settings()
	load_records()
	apply_settings()


func _setup_inputs() -> void:
	var defs := {
		"accelerate": [KEY_W, KEY_UP, JOY_BUTTON_A, -1, JOY_AXIS_TRIGGER_RIGHT],
		"brake": [KEY_S, KEY_DOWN, JOY_BUTTON_B, -1, JOY_AXIS_TRIGGER_LEFT],
		"steer_left": [KEY_A, KEY_LEFT, -1, -1, -1],
		"steer_right": [KEY_D, KEY_RIGHT, -1, -1, -1],
		"drift": [KEY_SPACE, KEY_J, JOY_BUTTON_RIGHT_SHOULDER, -1, -1],
		"boost": [KEY_SHIFT, KEY_K, JOY_BUTTON_LEFT_SHOULDER, -1, -1],
		"item": [KEY_F, KEY_L, JOY_BUTTON_X, -1, -1],
		"look_back": [KEY_C, -1, JOY_BUTTON_Y, -1, -1],
		"pause": [KEY_ESCAPE, KEY_P, JOY_BUTTON_START, -1, -1],
	}
	for action in defs:
		if not InputMap.has_action(action):
			InputMap.add_action(action, 0.2)
		var d: Array = defs[action]
		for i in 2:
			if int(d[i]) >= 0:
				var ev := InputEventKey.new()
				ev.physical_keycode = int(d[i])
				InputMap.action_add_event(action, ev)
		if int(d[2]) >= 0:
			var jb := InputEventJoypadButton.new()
			jb.button_index = int(d[2])
			InputMap.action_add_event(action, jb)
		if int(d[4]) >= 0:
			var ja := InputEventJoypadMotion.new()
			ja.axis = int(d[4])
			ja.axis_value = 1.0
			InputMap.action_add_event(action, ja)
	# analog steering on the left stick
	for pair in [["steer_left", -1.0], ["steer_right", 1.0]]:
		var jm := InputEventJoypadMotion.new()
		jm.axis = JOY_AXIS_LEFT_X
		jm.axis_value = pair[1]
		InputMap.action_add_event(pair[0], jm)
	var down := InputEventJoypadMotion.new()
	down.axis = JOY_AXIS_LEFT_Y
	down.axis_value = 1.0
	InputMap.action_add_event("brake", down)


const SETTINGS_VERSION := 2


func load_settings() -> void:
	# phones start on the Medium preset (High is for tablets / desktop)
	if OS.has_feature("mobile"):
		settings["quality"] = 1
	var cf := ConfigFile.new()
	if cf.load(SETTINGS_PATH) != OK:
		if OS.has_feature("pc"):
			settings["auto_accel"] = false
		return
	# settings saved by 0.1.x used full-resolution High graphics on phones: those
	# performance values are reset once to the new defaults
	var old_version := int(cf.get_value("settings", "settings_version", 1)) < SETTINGS_VERSION
	for k in settings.keys():
		if old_version and k in ["quality", "render_scale", "fps_cap", "shadows"]:
			continue
		if cf.has_section_key("settings", k):
			settings[k] = cf.get_value("settings", k)
	for k in race.keys():
		if cf.has_section_key("race", k):
			race[k] = cf.get_value("race", k)


func save_settings() -> void:
	var cf := ConfigFile.new()
	for k in settings:
		cf.set_value("settings", k, settings[k])
	cf.set_value("settings", "settings_version", SETTINGS_VERSION)
	for k in race:
		cf.set_value("race", k, race[k])
	cf.save(SETTINGS_PATH)


## 3D render height per quality preset (Low/Medium/High). Phones have 1080-1440
## pixel tall screens; drawing the 3D scene at full resolution is the single
## biggest GPU cost, so it is rendered at this height and upscaled (FSR).
const RENDER_HEIGHT := [600.0, 720.0, 900.0]


func render_scale_for(window_h: float) -> float:
	var q := clampi(int(settings["quality"]), 0, 2)
	var auto := clampf(RENDER_HEIGHT[q] / maxf(window_h, 1.0), 0.4, 1.0)
	return clampf(auto * float(settings["render_scale"]), 0.35, 1.0)


func apply_settings() -> void:
	Engine.max_fps = int(settings["fps_cap"])
	var vp := get_viewport()
	if vp:
		var q := int(settings["quality"])
		var sc := render_scale_for(float(DisplayServer.window_get_size().y))
		vp.scaling_3d_scale = sc
		vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_FSR if sc < 0.97 and q >= 1 else Viewport.SCALING_3D_MODE_BILINEAR
		vp.msaa_3d = Viewport.MSAA_2X if q >= 2 else Viewport.MSAA_DISABLED
		if not vp.size_changed.is_connected(apply_settings):
			vp.size_changed.connect(apply_settings)
	var bus_master := AudioServer.get_bus_index("Master")
	AudioServer.set_bus_volume_db(bus_master, linear_to_db(maxf(float(settings["vol_master"]), 0.0001)))
	if has_node("/root/Sfx"):
		get_node("/root/Sfx").apply_volumes()


func load_records() -> void:
	var cf := ConfigFile.new()
	if cf.load(RECORDS_PATH) == OK:
		for k in cf.get_section_keys("records"):
			records[k] = cf.get_value("records", k)


func submit_record(key: String, time: float) -> bool:
	var best: float = records.get(key, INF)
	if time < best:
		records[key] = time
		var cf := ConfigFile.new()
		for k in records:
			cf.set_value("records", k, records[k])
		cf.save(RECORDS_PATH)
		return true
	return false


func character(i: int) -> Dictionary:
	return CHARACTERS[clampi(i, 0, CHARACTERS.size() - 1)]


func track_def(id: String) -> Dictionary:
	for t in TRACKS:
		if t.id == id:
			return t
	return TRACKS[0]


func goto_scene(path: String) -> void:
	get_tree().paused = false
	get_tree().change_scene_to_file(path)


static func format_time(t: float) -> String:
	if t >= INF or t < 0.0:
		return "--:--.---"
	var m := int(t / 60.0)
	var s := fmod(t, 60.0)
	return "%d:%06.3f" % [m, s]


func haptic(ms: int) -> void:
	if settings["haptics"] and OS.has_feature("mobile"):
		Input.vibrate_handheld(ms)
