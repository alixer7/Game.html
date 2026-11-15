extends Node
## Persistent user settings (user://settings.cfg).

signal changed

const PATH := "user://settings.cfg"

const ACCENTS := [Color(0.95, 0.95, 1.0), Color(0.08, 0.08, 0.1), Color(1.0, 0.82, 0.1),
	Color(0.2, 1.0, 0.55), Color(0.85, 0.2, 1.0), Color(1.0, 0.25, 0.35), Color(0.3, 0.95, 1.0)]
const BOOST_COLORS := [Color(1.0, 0.55, 0.1), Color(0.3, 0.8, 1.0), Color(0.6, 1.0, 0.3),
	Color(1.0, 0.3, 0.9), Color(1.0, 0.95, 0.5), Color(0.75, 0.45, 1.0)]

var data := {
	"language": "ar",
	"player_name": "",
	"sfx_volume": 0.8,
	"music_volume": 0.5,
	"quality": 2,
	"max_fps": 60,
	"vibration": true,
	"cam_fov": 100.0,
	"cam_distance": 2.9,
	"cam_height": 1.05,
	"cam_angle": -4.0,
	"cam_stiffness": 0.5,
	"ball_cam": true,
	"joystick_size": 1.0,
	"button_size": 1.0,
	"controls_opacity": 0.85,
	"steer_sensitivity": 1.0,
	"left_handed": false,
	"auto_throttle": false,
	"car_body": 0,
	"car_accent": 0,
	"boost_color": 0,
	"mode": 2,
	"difficulty": 1,
	"match_minutes": 5,
	"team": 0,
	"show_fps": false,
	"replays": true,
	"joystick_fixed": false,
	"ball_marker": true,
	"touch_layout": {},
	"tutorial_seen": false,
}


func _ready() -> void:
	load_settings()
	if str(data["player_name"]).is_empty():
		data["player_name"] = "PLAYER"
	apply_runtime()


func get_value(key: String, default: Variant = null) -> Variant:
	return data.get(key, default)


func set_value(key: String, value: Variant, save_now: bool = true) -> void:
	data[key] = value
	if save_now:
		save_settings()
	apply_runtime()
	changed.emit()


func load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(PATH) != OK:
		# first launch: phones start on balanced graphics
		if OS.has_feature("mobile"):
			data["quality"] = 1
		return
	for k in data.keys():
		if cfg.has_section_key("settings", k):
			var v: Variant = cfg.get_value("settings", k)
			if typeof(v) == typeof(data[k]) or (typeof(data[k]) == TYPE_FLOAT and typeof(v) == TYPE_INT):
				data[k] = v


func save_settings() -> void:
	var cfg := ConfigFile.new()
	for k in data.keys():
		cfg.set_value("settings", k, data[k])
	cfg.save(PATH)


func apply_runtime() -> void:
	Engine.max_fps = int(data["max_fps"])
	var sfx_bus := AudioServer.get_bus_index("SFX")
	if sfx_bus >= 0:
		AudioServer.set_bus_volume_db(sfx_bus, linear_to_db(maxf(0.0001, float(data["sfx_volume"]))))
	var mus_bus := AudioServer.get_bus_index("Music")
	if mus_bus >= 0:
		AudioServer.set_bus_volume_db(mus_bus, linear_to_db(maxf(0.0001, float(data["music_volume"]))))


func accent_color() -> Color:
	return ACCENTS[clampi(int(data["car_accent"]), 0, ACCENTS.size() - 1)]


func boost_color() -> Color:
	return BOOST_COLORS[clampi(int(data["boost_color"]), 0, BOOST_COLORS.size() - 1)]


func vibrate(ms: int, amplitude: float = 0.5) -> void:
	if data["vibration"] and OS.has_feature("mobile"):
		Input.vibrate_handheld(ms, amplitude)
