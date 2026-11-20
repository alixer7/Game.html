extends Node
## الحالة العامة للعبة: الإعدادات، الإشعارات، المراجع، إعداد أزرار لوحة المفاتيح.

signal notified(text: String, color: Color)
signal settings_changed

const SAVE_PATH := "user://savegame.json"
const SETTINGS_PATH := "user://settings.cfg"

var world: Node = null
var player: Node = null
var hud: Node = null
var main: Node = null
var ui_open := false

var settings := {
	"quality": 1,          # 0 منخفض، 1 متوسط، 2 عالٍ
	"sensitivity": 1.0,
	"invert_y": false,
	"first_person": false,
	"show_fps": false,
	"volume": 0.8,
	"day_minutes": 24.0,   # طول اليوم بالدقائق الحقيقية
	"ui_scale": 1.0,
}

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_setup_input()
	load_settings()

func notify(text: String, color := Color(1, 1, 1)) -> void:
	notified.emit(text, color)

func has_save() -> bool:
	return FileAccess.file_exists(SAVE_PATH)

func write_save(data: Dictionary) -> bool:
	var f := FileAccess.open(SAVE_PATH + ".tmp", FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(JSON.stringify(data))
	f.close()
	var d := DirAccess.open("user://")
	if d:
		if d.file_exists("savegame.json"):
			d.remove("savegame.json")
		d.rename("savegame.json.tmp", "savegame.json")
	return true

func read_save() -> Dictionary:
	if not has_save():
		return {}
	var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if f == null:
		return {}
	var txt := f.get_as_text()
	f.close()
	var parsed = JSON.parse_string(txt)
	if parsed is Dictionary:
		return parsed
	return {}

func delete_save() -> void:
	if has_save():
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))

func save_settings() -> void:
	var cfg := ConfigFile.new()
	for k in settings:
		cfg.set_value("settings", k, settings[k])
	cfg.save(SETTINGS_PATH)

func load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_PATH) == OK:
		for k in settings:
			settings[k] = cfg.get_value("settings", k, settings[k])
	else:
		# اختيار جودة افتراضية مناسبة للجهاز
		if OS.has_feature("mobile"):
			settings["quality"] = 1
		else:
			settings["quality"] = 2
	AudioServer.set_bus_volume_db(0, linear_to_db(max(0.0001, float(settings["volume"]))))

func set_setting(k: String, v) -> void:
	settings[k] = v
	if k == "volume":
		AudioServer.set_bus_volume_db(0, linear_to_db(max(0.0001, float(v))))
	save_settings()
	settings_changed.emit()

static func v3(a) -> Vector3:
	if a is Array and a.size() >= 3:
		return Vector3(a[0], a[1], a[2])
	return Vector3.ZERO

static func arr3(v: Vector3) -> Array:
	return [snappedf(v.x, 0.01), snappedf(v.y, 0.01), snappedf(v.z, 0.01)]

func _add_key(action: String, keys: Array) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)
	for k in keys:
		var ev := InputEventKey.new()
		ev.physical_keycode = k
		InputMap.action_add_event(action, ev)

func _add_mouse(action: String, button: int) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)
	var ev := InputEventMouseButton.new()
	ev.button_index = button
	InputMap.action_add_event(action, ev)

func _setup_input() -> void:
	_add_key("move_forward", [KEY_W, KEY_UP])
	_add_key("move_back", [KEY_S, KEY_DOWN])
	_add_key("move_left", [KEY_A, KEY_LEFT])
	_add_key("move_right", [KEY_D, KEY_RIGHT])
	_add_key("jump", [KEY_SPACE])
	_add_key("sprint", [KEY_SHIFT])
	_add_key("crouch", [KEY_CTRL, KEY_C])
	_add_key("interact", [KEY_E, KEY_F])
	_add_mouse("attack", MOUSE_BUTTON_LEFT)
	_add_key("inventory", [KEY_TAB, KEY_I])
	_add_key("craft", [KEY_R])
	_add_key("build", [KEY_B])
	_add_key("map", [KEY_M])
	_add_key("character", [KEY_J])
	_add_key("pause", [KEY_ESCAPE, KEY_P])
	_add_key("rotate", [KEY_Q])
	_add_key("camera", [KEY_V])
	for i in range(6):
		_add_key("slot_%d" % (i + 1), [KEY_1 + i])
