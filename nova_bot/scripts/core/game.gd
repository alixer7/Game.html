extends Node
## Autoload "Game": settings, save data, level catalogue, quality presets and small helpers.

signal settings_changed

const SAVE_PATH := "user://nova_bot_save.json"
const VERSION := "0.1.0"

var main = null                  # the Main node (set by Main)
var settings: Dictionary = {}
var progress: Dictionary = {}
var current_level: int = 1
var LEVELS: Array = []


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_catalogue()
	_default_settings()
	load_all()
	_setup_input()


# ------------------------------------------------------------ catalogue
func _build_catalogue() -> void:
	LEVELS = [
		{"id": 1, "file": "res://levels/level_1.json", "theme": "launch", "boss": false,
			"name": "محطة الانطلاق", "desc": "تعلّم الحركات واكتشف أول الأصدقاء",
			"a": Color(0.2, 0.85, 1.0), "b": Color(0.15, 0.3, 0.9), "atmo": Color(0.5, 0.95, 1.0),
			"ring": 0.0, "seed": 1.3, "music": "music_world1"},
		{"id": 2, "file": "res://levels/level_2.json", "theme": "crystal", "boss": false,
			"name": "حدائق الكريستال", "desc": "كريستالات متهاوية ومنصات أشباح ومفاتيح",
			"a": Color(1.0, 0.35, 0.85), "b": Color(0.45, 0.2, 0.9), "atmo": Color(1.0, 0.6, 0.95),
			"ring": 1.0, "seed": 4.1, "music": "music_world2"},
		{"id": 3, "file": "res://levels/level_3.json", "theme": "foundry", "boss": false,
			"name": "مصنع الجاذبية", "desc": "تيارات هوائية وليزر وسيور متحركة",
			"a": Color(1.0, 0.55, 0.15), "b": Color(0.8, 0.15, 0.2), "atmo": Color(1.0, 0.75, 0.4),
			"ring": 0.0, "seed": 7.7, "music": "music_world3"},
		{"id": 4, "file": "res://levels/level_4.json", "theme": "core", "boss": true,
			"name": "قلب المجرة", "desc": "واجه الحارس العملاق وأنقذ المجرة",
			"a": Color(1.0, 0.85, 0.3), "b": Color(0.55, 0.3, 1.0), "atmo": Color(1.0, 0.95, 0.6),
			"ring": 1.0, "seed": 2.6, "music": "music_boss"},
	]


func level_count() -> int:
	return LEVELS.size()


func level_meta(id: int) -> Dictionary:
	return LEVELS[clampi(id - 1, 0, LEVELS.size() - 1)]


# -------------------------------------------------------------- settings
func _default_settings() -> void:
	settings = {
		"music": 0.7, "sfx": 1.0, "quality": 1, "stick_scale": 1.0, "btn_scale": 1.0,
		"ui_opacity": 0.85, "cam_sens": 1.0, "invert_y": false, "cam_assist": 1,
		"vibration": true, "fixed_stick": false, "show_fps": false,
	}
	if OS.has_feature("pc") or OS.has_feature("web"):
		settings["quality"] = 2


func set_setting(key: String, value) -> void:
	settings[key] = value
	save_all()
	settings_changed.emit()


func quality() -> int:
	return clampi(int(settings.get("quality", 1)), 0, 2)


func apply_display(vp: Viewport) -> void:
	var q: int = quality()
	var scales: Array = [0.67, 0.85, 1.0]
	vp.scaling_3d_scale = float(scales[q])
	var ms: Array = [Viewport.MSAA_DISABLED, Viewport.MSAA_2X, Viewport.MSAA_4X]
	vp.msaa_3d = ms[q]


func particle_scale() -> float:
	var s: Array = [0.5, 0.8, 1.0]
	return float(s[quality()])


func vibrate(ms: int = 20) -> void:
	if bool(settings.get("vibration", true)) and OS.has_feature("mobile"):
		Input.vibrate_handheld(ms)


# --------------------------------------------------------------- progress
func level_record(id: int) -> Dictionary:
	var k: String = str(id)
	var lv: Dictionary = progress["levels"]
	if not lv.has(k):
		lv[k] = {"bots": [false, false, false], "coins": 0, "time": 0.0, "done": false}
	return lv[k]


func is_unlocked(id: int) -> bool:
	if id <= 1:
		return true
	return bool(level_record(id - 1).get("done", false))


func bots_found(id: int) -> int:
	var n: int = 0
	for b in level_record(id)["bots"]:
		if b:
			n += 1
	return n


func total_bots() -> int:
	var n: int = 0
	for i in range(1, LEVELS.size() + 1):
		n += bots_found(i)
	return n


func total_coins() -> int:
	var n: int = 0
	for i in range(1, LEVELS.size() + 1):
		n += int(level_record(i).get("coins", 0))
	return n


func record_result(id: int, bots: Array, coins: int, time: float) -> void:
	var r: Dictionary = level_record(id)
	for i in range(3):
		if i < bots.size() and bots[i]:
			r["bots"][i] = true
	r["coins"] = maxi(int(r.get("coins", 0)), coins)
	if not bool(r.get("done", false)) or time < float(r.get("time", 0.0)):
		r["time"] = time
	r["done"] = true
	save_all()


func format_time(t: float) -> String:
	var m: int = int(t / 60.0)
	var s: int = int(t) % 60
	return "%d:%02d" % [m, s]


# ---------------------------------------------------------------- saving
func save_all() -> void:
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f == null:
		return
	f.store_string(JSON.stringify({"settings": settings, "progress": progress, "version": VERSION}))
	f.close()


func load_all() -> void:
	progress = {"levels": {}}
	if not FileAccess.file_exists(SAVE_PATH):
		return
	var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if f == null:
		return
	var txt: String = f.get_as_text()
	f.close()
	var data = JSON.parse_string(txt)
	if typeof(data) != TYPE_DICTIONARY:
		return
	if data.has("settings") and typeof(data["settings"]) == TYPE_DICTIONARY:
		for k in data["settings"]:
			if settings.has(k):
				settings[k] = data["settings"][k]
	if data.has("progress") and typeof(data["progress"]) == TYPE_DICTIONARY:
		progress = data["progress"]
		if not progress.has("levels"):
			progress["levels"] = {}


# ----------------------------------------------------------------- input
func _setup_input() -> void:
	_act("move_left", [KEY_A, KEY_LEFT], [], [[JOY_AXIS_LEFT_X, -1.0]])
	_act("move_right", [KEY_D, KEY_RIGHT], [], [[JOY_AXIS_LEFT_X, 1.0]])
	_act("move_forward", [KEY_W, KEY_UP], [], [[JOY_AXIS_LEFT_Y, -1.0]])
	_act("move_back", [KEY_S, KEY_DOWN], [], [[JOY_AXIS_LEFT_Y, 1.0]])
	_act("jump", [KEY_SPACE], [JOY_BUTTON_A], [])
	_act("spin", [KEY_J, KEY_X], [JOY_BUTTON_X], [])
	_act("dash", [KEY_K, KEY_C, KEY_SHIFT], [JOY_BUTTON_B, JOY_BUTTON_RIGHT_SHOULDER], [])
	_act("pause", [KEY_ESCAPE, KEY_P], [JOY_BUTTON_START], [])
	_act("cam_left", [KEY_Q], [], [[JOY_AXIS_RIGHT_X, -1.0]])
	_act("cam_right", [KEY_E], [], [[JOY_AXIS_RIGHT_X, 1.0]])
	_act("cam_up", [KEY_R], [], [[JOY_AXIS_RIGHT_Y, -1.0]])
	_act("cam_down", [KEY_F], [], [[JOY_AXIS_RIGHT_Y, 1.0]])


func _act(action: String, keys: Array, buttons: Array, axes: Array) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action, 0.2)
	for k in keys:
		var ek := InputEventKey.new()
		ek.physical_keycode = k
		InputMap.action_add_event(action, ek)
	for b in buttons:
		var eb := InputEventJoypadButton.new()
		eb.button_index = b
		InputMap.action_add_event(action, eb)
	for a in axes:
		var ea := InputEventJoypadMotion.new()
		ea.axis = a[0]
		ea.axis_value = a[1]
		InputMap.action_add_event(action, ea)
