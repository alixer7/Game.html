extends Node
## Global game state: settings, save data, car catalogue, translations and input map.

signal settings_changed

const SAVE_PATH := "user://velocity_rush_save.cfg"
const IS_MOBILE_DEFAULT := true

var settings := {
	"quality": 1,               # 0 low, 1 medium, 2 high, 3 ultra
	"render_scale": 1.0,
	"view_distance": 0.7,
	"traffic_density": 0.7,
	"police": true,
	"difficulty": 1,            # 0 easy, 1 normal, 2 hard
	"steer_assist": 0.5,
	"traction_control": true,
	"abs": true,
	"stability": true,
	"units": "kmh",
	"lang": "ar",
	"vol_master": 0.9,
	"vol_sfx": 1.0,
	"slowmo_jumps": true,
	"camera_mode": 0,
	"time_of_day": 1,           # 0 morning, 1 golden hour, 2 noon, 3 sunset
	"vibration": true,
	"show_fps": false,
}

var controls := {
	"steer_mode": "buttons",    # buttons | wheel | slider | tilt
	"auto_accel": false,
	"sensitivity": 1.0,
	"tilt_sensitivity": 1.0,
	"opacity": 0.75,
	"scale": 1.0,
	"layout": {},
}

## Default touch layout: name -> [x (0..1 of screen width), y (0..1 of height), size multiplier]
const DEFAULT_LAYOUT := {
	"left": [0.075, 0.80, 1.0],
	"right": [0.205, 0.80, 1.0],
	"wheel": [0.15, 0.74, 1.0],
	"slider": [0.17, 0.84, 1.0],
	"gas": [0.925, 0.76, 1.15],
	"brake": [0.80, 0.84, 0.95],
	"handbrake": [0.80, 0.62, 0.85],
	"nitro": [0.925, 0.52, 0.9],
	"camera": [0.955, 0.08, 0.6],
	"reset": [0.885, 0.08, 0.6],
	"pause": [0.045, 0.08, 0.6],
	"lookback": [0.665, 0.86, 0.7],
}

var selected_car := "falcon"
var selected_color := 0
var best_times := {}            # event_id -> seconds (or score)
var stats := {"races_won": 0, "races": 0, "distance_km": 0.0, "busted": 0}

# runtime references
var world: Node = null
var player: Node = null
var race: Node = null
var hud: Node = null
var camera: Node = null
var main: Node = null
var sfx: Sfx = null
var paused_by_menu := false
var is_mobile := false

# --------------------------------------------------------------------------- car catalogue
# body: model style; colors: paint presets. Physics values are SI units.
const CARS := {
	"falcon": {
		"name_ar": "فالكون جي تي", "name_en": "Falcon GT", "class": "S",
		"body": "supercar", "mass": 1420.0, "drive": "rwd",
		"torque": 640.0, "peak_rpm": 6200.0, "redline": 8400.0, "idle": 950.0,
		"gears": [3.15, 2.18, 1.66, 1.32, 1.08, 0.88, 0.74], "final": 3.55,
		"grip": 1.12, "brake": 13500.0, "steer_lock": 34.0, "drag": 0.30, "downforce": 0.95,
		"susp_k": 52000.0, "susp_c": 4300.0, "arb": 9000.0, "wheel_r": 0.345, "cyl": 8,
		"colors": [Color(0.75, 0.04, 0.03), Color(0.95, 0.65, 0.05), Color(0.06, 0.07, 0.08), Color(0.9, 0.92, 0.95), Color(0.05, 0.25, 0.75)],
		"stats": [0.92, 0.88, 0.85, 0.6],
	},
	"raptor": {
		"name_ar": "رابتور آر إس", "name_en": "Raptor RS", "class": "A",
		"body": "coupe", "mass": 1480.0, "drive": "rwd",
		"torque": 540.0, "peak_rpm": 5600.0, "redline": 7600.0, "idle": 900.0,
		"gears": [3.36, 2.27, 1.69, 1.32, 1.06, 0.86], "final": 3.62,
		"grip": 1.05, "brake": 12500.0, "steer_lock": 36.0, "drag": 0.33, "downforce": 0.6,
		"susp_k": 48000.0, "susp_c": 4000.0, "arb": 8000.0, "wheel_r": 0.335, "cyl": 6,
		"colors": [Color(0.08, 0.32, 0.62), Color(0.85, 0.85, 0.88), Color(0.55, 0.0, 0.06), Color(0.12, 0.45, 0.2), Color(0.98, 0.45, 0.02)],
		"stats": [0.8, 0.8, 0.86, 0.6],
	},
	"stallion": {
		"name_ar": "ستاليون في 8", "name_en": "Stallion V8", "class": "A",
		"body": "muscle", "mass": 1700.0, "drive": "rwd",
		"torque": 760.0, "peak_rpm": 4600.0, "redline": 6800.0, "idle": 800.0,
		"gears": [2.97, 2.07, 1.43, 1.0, 0.84, 0.69], "final": 3.73,
		"grip": 1.0, "brake": 12500.0, "steer_lock": 35.0, "drag": 0.36, "downforce": 0.3,
		"susp_k": 46000.0, "susp_c": 3900.0, "arb": 7000.0, "wheel_r": 0.35, "cyl": 8,
		"colors": [Color(0.1, 0.1, 0.11), Color(0.82, 0.15, 0.05), Color(0.95, 0.8, 0.1), Color(0.2, 0.4, 0.25), Color(0.9, 0.9, 0.92)],
		"stats": [0.85, 0.82, 0.7, 0.55],
	},
	"tempest": {
		"name_ar": "تمبست إيفو", "name_en": "Tempest Evo", "class": "B",
		"body": "hatch", "mass": 1360.0, "drive": "awd",
		"torque": 450.0, "peak_rpm": 5200.0, "redline": 7400.0, "idle": 950.0,
		"gears": [3.4, 2.32, 1.72, 1.35, 1.09, 0.89], "final": 4.1,
		"grip": 1.06, "brake": 11500.0, "steer_lock": 38.0, "drag": 0.34, "downforce": 0.45,
		"susp_k": 40000.0, "susp_c": 3600.0, "arb": 6000.0, "wheel_r": 0.33, "cyl": 4,
		"colors": [Color(0.92, 0.92, 0.95), Color(0.04, 0.2, 0.55), Color(0.85, 0.1, 0.1), Color(0.95, 0.55, 0.0), Color(0.1, 0.1, 0.1)],
		"stats": [0.72, 0.84, 0.9, 0.95],
	},
	"kaiser": {
		"name_ar": "كايزر إس", "name_en": "Kaiser S", "class": "A",
		"body": "sedan", "mass": 1660.0, "drive": "rwd",
		"torque": 650.0, "peak_rpm": 5800.0, "redline": 7400.0, "idle": 850.0,
		"gears": [4.17, 2.34, 1.52, 1.14, 0.87, 0.69], "final": 3.15,
		"grip": 1.04, "brake": 13000.0, "steer_lock": 36.0, "drag": 0.31, "downforce": 0.35,
		"susp_k": 50000.0, "susp_c": 4200.0, "arb": 8500.0, "wheel_r": 0.345, "cyl": 8,
		"colors": [Color(0.25, 0.27, 0.3), Color(0.02, 0.02, 0.03), Color(0.85, 0.85, 0.87), Color(0.05, 0.18, 0.4), Color(0.45, 0.05, 0.08)],
		"stats": [0.82, 0.78, 0.8, 0.65],
	},
	"phantom": {
		"name_ar": "فانتوم إكس", "name_en": "Phantom X", "class": "S+",
		"body": "hyper", "mass": 1520.0, "drive": "awd",
		"torque": 950.0, "peak_rpm": 6500.0, "redline": 8800.0, "idle": 1000.0,
		"gears": [3.0, 2.15, 1.65, 1.32, 1.08, 0.9, 0.76], "final": 3.4,
		"grip": 1.18, "brake": 15000.0, "steer_lock": 33.0, "drag": 0.29, "downforce": 1.35,
		"susp_k": 56000.0, "susp_c": 4600.0, "arb": 10000.0, "wheel_r": 0.35, "cyl": 12,
		"colors": [Color(0.12, 0.13, 0.15), Color(0.6, 0.62, 0.65), Color(0.0, 0.45, 0.4), Color(0.7, 0.05, 0.25), Color(0.95, 0.95, 0.97)],
		"stats": [1.0, 0.98, 0.9, 0.7],
	},
	"police": {
		"name_ar": "دورية الشرطة", "name_en": "Interceptor", "class": "P",
		"body": "police", "mass": 1750.0, "drive": "awd",
		"torque": 700.0, "peak_rpm": 5600.0, "redline": 7200.0, "idle": 850.0,
		"gears": [3.2, 2.2, 1.6, 1.25, 1.0, 0.8, 0.68], "final": 3.4,
		"grip": 1.08, "brake": 13500.0, "steer_lock": 36.0, "drag": 0.31, "downforce": 0.5,
		"susp_k": 52000.0, "susp_c": 4400.0, "arb": 8500.0, "wheel_r": 0.345, "cyl": 8,
		"colors": [Color(0.05, 0.05, 0.06)],
		"stats": [0.85, 0.85, 0.85, 0.7],
	},
}

## Traffic vehicles: purely visual bodies with simple kinematics (until hit).
const TRAFFIC := {
	"t_sedan": {"body": "sedan_t", "mass": 1400.0, "colors": [Color(0.7, 0.7, 0.72), Color(0.15, 0.2, 0.35), Color(0.5, 0.05, 0.05), Color(0.9, 0.9, 0.9), Color(0.1, 0.1, 0.1), Color(0.35, 0.3, 0.25)]},
	"t_hatch": {"body": "hatch_t", "mass": 1150.0, "colors": [Color(0.85, 0.1, 0.1), Color(0.95, 0.95, 0.95), Color(0.2, 0.5, 0.3), Color(0.25, 0.25, 0.3), Color(0.9, 0.7, 0.1)]},
	"t_suv": {"body": "suv", "mass": 2100.0, "colors": [Color(0.05, 0.05, 0.06), Color(0.8, 0.8, 0.82), Color(0.3, 0.3, 0.33), Color(0.1, 0.18, 0.12)]},
	"t_van": {"body": "van", "mass": 2600.0, "colors": [Color(0.95, 0.95, 0.95), Color(0.8, 0.8, 0.8), Color(0.15, 0.25, 0.5)]},
	"t_pickup": {"body": "pickup", "mass": 2200.0, "colors": [Color(0.6, 0.1, 0.08), Color(0.2, 0.22, 0.25), Color(0.9, 0.9, 0.9), Color(0.25, 0.35, 0.2)]},
	"t_taxi": {"body": "sedan_t", "mass": 1400.0, "colors": [Color(0.98, 0.78, 0.05)]},
	"t_truck": {"body": "truck", "mass": 7000.0, "colors": [Color(0.9, 0.9, 0.9), Color(0.12, 0.3, 0.6), Color(0.7, 0.15, 0.1)]},
}

const PLAYER_CARS := ["falcon", "raptor", "stallion", "tempest", "kaiser", "phantom"]

# --------------------------------------------------------------------------- translations
const STR := {
	"title": ["اندفاع السرعة", "VELOCITY RUSH"],
	"subtitle": ["سباقات الشوارع في عالم مفتوح", "Open World Street Racing"],
	"free_roam": ["القيادة الحرة", "Free Roam"],
	"events": ["السباقات والتحديات", "Races & Challenges"],
	"garage": ["المرآب", "Garage"],
	"settings": ["الإعدادات", "Settings"],
	"controls": ["التحكم", "Controls"],
	"quit": ["خروج", "Quit"],
	"resume": ["متابعة", "Resume"],
	"restart": ["إعادة السباق", "Restart"],
	"quit_race": ["إنهاء السباق", "Quit Race"],
	"main_menu": ["القائمة الرئيسية", "Main Menu"],
	"back": ["رجوع", "Back"],
	"start": ["ابدأ", "Start"],
	"travel": ["انتقال", "Travel"],
	"loading": ["جاري تحميل العالم...", "Loading world..."],
	"position": ["المركز", "POS"],
	"lap": ["اللفة", "LAP"],
	"time": ["الوقت", "TIME"],
	"best": ["الأفضل", "BEST"],
	"checkpoint": ["نقطة تفتيش", "Checkpoint"],
	"missed_cp": ["فاتتك نقطة التفتيش! ارجع إليها", "Missed checkpoint! Go back"],
	"wrong_way": ["اتجاه خاطئ", "WRONG WAY"],
	"final_lap": ["اللفة الأخيرة", "FINAL LAP"],
	"go": ["انطلق!", "GO!"],
	"finished": ["انتهى السباق", "FINISHED"],
	"busted": ["تم القبض عليك!", "BUSTED!"],
	"evaded": ["هربت من الشرطة", "Police evaded"],
	"heat": ["المطاردة", "HEAT"],
	"pursuit": ["مطاردة الشرطة!", "Police pursuit!"],
	"nitro_empty": ["نفد النيترو", "Nitro empty"],
	"racer_busted": ["قبضت الشرطة على متسابق", "A racer got busted"],
	"results": ["النتائج", "Results"],
	"continue": ["متابعة", "Continue"],
	"race_here": ["اضغط للبدء", "Tap to start"],
	"sprint": ["سباق سرعة", "Sprint"],
	"circuit": ["سباق حلبة", "Circuit"],
	"speedtrap": ["رادار السرعة", "Speed Trap"],
	"drift": ["انجراف", "Drift"],
	"jump": ["قفز", "Jump"],
	"laps": ["لفات", "laps"],
	"length": ["المسافة", "Length"],
	"police_on": ["الشرطة: نعم", "Police: Yes"],
	"police_off": ["الشرطة: لا", "Police: No"],
	"quality": ["جودة الرسومات", "Graphics quality"],
	"q_low": ["منخفضة", "Low"],
	"q_med": ["متوسطة", "Medium"],
	"q_high": ["عالية", "High"],
	"q_ultra": ["فائقة", "Ultra"],
	"render_scale": ["دقة العرض", "Render scale"],
	"view_distance": ["مدى الرؤية", "View distance"],
	"traffic": ["كثافة المرور", "Traffic density"],
	"police": ["الشرطة في السباقات", "Police in races"],
	"difficulty": ["صعوبة المنافسين", "Opponent difficulty"],
	"easy": ["سهل", "Easy"],
	"normal": ["عادي", "Normal"],
	"hard": ["صعب", "Hard"],
	"steer_assist": ["مساعدة التوجيه", "Steering assist"],
	"tcs": ["التحكم بالجر", "Traction control"],
	"abs": ["مانع انغلاق المكابح", "ABS"],
	"stability": ["التحكم بالثبات", "Stability control"],
	"units": ["وحدة السرعة", "Speed units"],
	"language": ["اللغة", "Language"],
	"volume": ["مستوى الصوت", "Volume"],
	"slowmo": ["تصوير بطيء عند القفز", "Slow-motion on jumps"],
	"time_of_day": ["وقت اليوم", "Time of day"],
	"tod_morning": ["صباح", "Morning"],
	"tod_golden": ["ساعة ذهبية", "Golden hour"],
	"tod_noon": ["ظهيرة", "Noon"],
	"tod_sunset": ["غروب", "Sunset"],
	"vibration": ["الاهتزاز", "Vibration"],
	"show_fps": ["عرض عدد الإطارات", "Show FPS"],
	"steer_mode": ["طريقة التوجيه", "Steering mode"],
	"sm_buttons": ["أزرار", "Buttons"],
	"sm_wheel": ["مقود", "Wheel"],
	"sm_slider": ["سحب", "Slider"],
	"sm_tilt": ["إمالة الهاتف", "Tilt"],
	"auto_accel": ["تسارع تلقائي", "Auto accelerate"],
	"sensitivity": ["حساسية التوجيه", "Steering sensitivity"],
	"tilt_sens": ["حساسية الإمالة", "Tilt sensitivity"],
	"opacity": ["شفافية الأزرار", "Button opacity"],
	"btn_scale": ["حجم الأزرار", "Button size"],
	"edit_layout": ["تخصيص أماكن الأزرار", "Customize layout"],
	"reset_layout": ["استعادة الافتراضي", "Reset layout"],
	"done": ["تم", "Done"],
	"layout_hint": ["اسحب الأزرار لتغيير أماكنها، واستخدم الشريط لتغيير حجم الزر المحدد", "Drag buttons to move them. Use the slider to resize the selected button"],
	"selected_size": ["حجم الزر المحدد", "Selected button size"],
	"speed": ["السرعة", "Speed"],
	"handling": ["التحكم", "Handling"],
	"accel": ["التسارع", "Acceleration"],
	"offroad": ["الطرق الوعرة", "Off-road"],
	"color": ["اللون", "Color"],
	"select": ["اختيار", "Select"],
	"score": ["النقاط", "SCORE"],
	"drift_combo": ["انجراف", "DRIFT"],
	"jump_dist": ["مسافة القفزة", "Jump distance"],
	"top_speed": ["السرعة القصوى", "Top speed"],
	"challenge_done": ["انتهى التحدي", "Challenge complete"],
	"new_record": ["رقم قياسي جديد!", "NEW RECORD!"],
	"target": ["الهدف", "Target"],
	"place_1": ["الأول", "1st"],
	"place_n": ["المركز", "Place"],
	"you": ["أنت", "You"],
	"dnf": ["لم يكمل", "DNF"],
	"world_map": ["خريطة العالم", "World Map"],
	"tap_event": ["اختر حدثاً من الخريطة", "Pick an event on the map"],
	"fps": ["إطار/ث", "FPS"],
	"countdown_ready": ["استعد", "READY"],
	"respawn": ["إعادة السيارة للطريق", "Reset car"],
	"camera": ["الكاميرا", "Camera"],
	"region_city": ["وسط المدينة", "Downtown"],
	"region_mountain": ["الجبال الثلجية", "Snow Mountains"],
	"region_forest": ["غابة الصنوبر", "Pine Forest"],
	"region_desert": ["الصحراء", "Desert"],
	"region_ruins": ["المدينة الأثرية", "Ancient City"],
	"region_coast": ["الساحل", "The Coast"],
	"region_valley": ["وادي النهر", "River Valley"],
	"region_circuit": ["الحلبة الكبرى", "Grand Circuit"],
	"region_countryside": ["الريف", "Countryside"],
	"open_race_tip": ["سباق مفتوح: اختر طريقك بحرية بين نقاط التفتيش", "Open race: choose your own path between checkpoints"],
	"shortcut_tip": ["تلميح: توجد طرق مختصرة، لكن عليك عبور كل نقاط التفتيش", "Tip: shortcuts exist, but you must cross every checkpoint"],
	"opponents": ["المنافسون", "Opponents"],
}


func t(key: String) -> String:
	var row = STR.get(key)
	if row == null:
		return key
	return row[0] if settings.lang == "ar" else row[1]


func is_rtl() -> bool:
	return settings.lang == "ar"


func car_name(id: String) -> String:
	var c: Dictionary = CARS.get(id, {})
	return c.get("name_ar", id) if settings.lang == "ar" else c.get("name_en", id)


# --------------------------------------------------------------------------- lifecycle
func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	is_mobile = OS.has_feature("mobile") or OS.has_feature("web_android") or OS.has_feature("web_ios")
	if not is_mobile:
		settings.quality = 2
	_setup_input()
	load_game()
	sfx = Sfx.new()
	add_child(sfx)
	apply_audio()


func _setup_input() -> void:
	var map := {
		"accelerate": [KEY_W, KEY_UP],
		"brake": [KEY_S, KEY_DOWN],
		"steer_left": [KEY_A, KEY_LEFT],
		"steer_right": [KEY_D, KEY_RIGHT],
		"handbrake": [KEY_SPACE],
		"nitro": [KEY_SHIFT, KEY_N],
		"camera": [KEY_C],
		"reset_car": [KEY_R],
		"pause": [KEY_ESCAPE, KEY_P],
		"look_back": [KEY_B],
	}
	for action in map:
		if not InputMap.has_action(action):
			InputMap.add_action(action, 0.2)
		for k in map[action]:
			var ev := InputEventKey.new()
			ev.physical_keycode = k
			InputMap.action_add_event(action, ev)
	var pads := {
		"accelerate": [JOY_AXIS_TRIGGER_RIGHT, 1.0],
		"brake": [JOY_AXIS_TRIGGER_LEFT, 1.0],
		"steer_left": [JOY_AXIS_LEFT_X, -1.0],
		"steer_right": [JOY_AXIS_LEFT_X, 1.0],
	}
	for action in pads:
		var jm := InputEventJoypadMotion.new()
		jm.axis = pads[action][0]
		jm.axis_value = pads[action][1]
		InputMap.action_add_event(action, jm)
	var btns := {"handbrake": JOY_BUTTON_A, "nitro": JOY_BUTTON_B, "camera": JOY_BUTTON_Y, "reset_car": JOY_BUTTON_BACK, "pause": JOY_BUTTON_START}
	for action in btns:
		var jb := InputEventJoypadButton.new()
		jb.button_index = btns[action]
		InputMap.action_add_event(action, jb)


func layout_of(name: String) -> Array:
	var l: Dictionary = controls.layout
	if l.has(name):
		return l[name]
	return DEFAULT_LAYOUT.get(name, [0.5, 0.5, 1.0])


func save_game() -> void:
	var cf := ConfigFile.new()
	for k in settings:
		cf.set_value("settings", k, settings[k])
	for k in controls:
		cf.set_value("controls", k, controls[k])
	cf.set_value("player", "car", selected_car)
	cf.set_value("player", "color", selected_color)
	cf.set_value("player", "best", best_times)
	cf.set_value("player", "stats", stats)
	cf.save(SAVE_PATH)


func load_game() -> void:
	var cf := ConfigFile.new()
	if cf.load(SAVE_PATH) != OK:
		return
	for k in settings:
		settings[k] = cf.get_value("settings", k, settings[k])
	for k in controls:
		controls[k] = cf.get_value("controls", k, controls[k])
	selected_car = cf.get_value("player", "car", selected_car)
	if not CARS.has(selected_car):
		selected_car = "falcon"
	selected_color = cf.get_value("player", "color", selected_color)
	best_times = cf.get_value("player", "best", best_times)
	stats = cf.get_value("player", "stats", stats)


func set_setting(key: String, value) -> void:
	settings[key] = value
	save_game()
	if key.begins_with("vol"):
		apply_audio()
	settings_changed.emit()


func apply_audio() -> void:
	var bus := AudioServer.get_bus_index("Master")
	AudioServer.set_bus_volume_db(bus, linear_to_db(maxf(settings.vol_master, 0.0001)))


func speed_text(mps: float) -> String:
	if settings.units == "mph":
		return str(int(round(mps * 2.23694)))
	return str(int(round(mps * 3.6)))


func speed_unit() -> String:
	if settings.units == "mph":
		return "MPH" if settings.lang != "ar" else "ميل/س"
	return "KM/H" if settings.lang != "ar" else "كم/س"


func format_time(sec: float) -> String:
	if sec < 0.0 or sec > 35999.0:
		return "--:--.--"
	var m := int(sec / 60.0)
	var s := fmod(sec, 60.0)
	return "%d:%05.2f" % [m, s]


func vibrate(ms: int) -> void:
	if settings.vibration and is_mobile:
		Input.vibrate_handheld(ms)
