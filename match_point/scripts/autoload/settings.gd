extends Node
## الإعدادات المحفوظة على الجهاز (user://settings.cfg)

signal changed

const PATH := "user://settings.cfg"

var data := {
	"difficulty": 1,          # 0 مبتدئ، 1 هاوٍ، 2 محترف، 3 أسطورة
	"sets": 1,                # المجموعات اللازمة للفوز: 1 مجموعة، 2 أفضل 3، 3 أفضل 5
	"games": 6,               # أشواط المجموعة: 6 رسمي، 4 قصير
	"surface": 0,             # Court.Surface
	"assist": 2,              # 0 بدون، 1 محاذاة خفيفة، 2 جري تلقائي (الافتراضي)
	"aim_marker": true,
	"player_id": "samer",
	"opponent_id": "karim",
	"wind": 0,
	"qte_dist": 1,           # مسافة ظهور شريط التوقيت: 0 قريبة، 1 متوسطة، 2 بعيدة
	"quality": 1,             # 0 منخفض، 1 متوسط، 2 عالٍ
	"sfx": 0.9,
	"crowd": 0.7,
	"ball_scale": 1.25,
	"camera": 0,
	"cam_height": 50,         # ارتفاع الكاميرا 0..100 (أقل = مسطحة، أكثر = مرتفعة)
	"cam_zoom": 50,           # تقريب الكاميرا 0..100 (أقل = بعيدة، أكثر = قريبة من الملعب)
	"tutorial_seen": false,
	"matches": 0,
	"wins": 0,
}


func _ready() -> void:
	load_settings()


func get_v(key: String) -> Variant:
	return data.get(key)


func set_v(key: String, value: Variant) -> void:
	data[key] = value
	save_settings()
	changed.emit()


func load_settings() -> void:
	var cf := ConfigFile.new()
	if cf.load(PATH) != OK:
		return
	for k in data.keys():
		if cf.has_section_key("s", k):
			var v: Variant = cf.get_value("s", k)
			if typeof(v) == typeof(data[k]):
				data[k] = v


func save_settings() -> void:
	if "--play" in OS.get_cmdline_user_args():
		return
	var cf := ConfigFile.new()
	for k in data.keys():
		cf.set_value("s", k, data[k])
	cf.save(PATH)
