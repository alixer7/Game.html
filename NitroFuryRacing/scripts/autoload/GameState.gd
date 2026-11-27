extends Node

## Central Game State, CTR Character/Track Catalog, Save/Load, and EN/AR Localization.

signal language_changed(lang: String)
signal settings_changed()

const SAVE_PATH := "user://nitro_fury_save.json"
const GHOST_DIR := "user://ghosts/"

enum GameMode {
	ARCADE_RACE,
	GRAND_PRIX,
	TIME_TRIAL,
	PRACTICE_ACADEMY
}

# Language: "ar" or "en" (defaults to Arabic since requested in Arabic, switchable in 1 tap!)
var language: String = "ar"

# Selection State
var selected_mode: GameMode = GameMode.ARCADE_RACE
var selected_track_index: int = 0
var selected_racer_index: int = 0
var ai_difficulty: int = 1 # 0=Easy, 1=Normal, 2=Hard/CTR Pro
var mirror_mode: bool = false # Classic CTR Mirror Mode (flips track left-right!)

# Grand Prix Cup State
var gp_active: bool = false
var gp_track_index: int = 0
var gp_standings: Array = [] # Array of {racer_id, name, points, is_player}

# Mobile / Gameplay Settings
var auto_accelerate: bool = true
var use_joystick: bool = false # false = Precision Left/Right Buttons (CTR D-pad feel), true = Virtual Stick
var show_ctr_telemetry: bool = true # Shows Reserves Bar + Fire Tier + Hang-Time + Drift Timing hints
var controls_opacity: float = 0.85
var sfx_volume: float = 0.85
var music_volume: float = 0.55
var graphics_high: bool = true

# Saved Progression
var best_race_times: Dictionary = {}   # track_id -> float seconds
var best_lap_times: Dictionary = {}    # track_id -> float seconds
var discovered_shortcuts: Dictionary = {} # shortcut_id -> true
var cups_won: int = 0

# Last race summary (for Results / Podium screen)
var last_results: Dictionary = {}

# 4 Iconic CTR-Archetype Racers
const RACERS := [
	{
		"id": "blaze",
		"name_en": "BLAZE",
		"name_ar": "بليز",
		"class_en": "BALANCED",
		"class_ar": "متوازن",
		"desc_en": "Classic all-rounder. Crisp drifts, strong reserves & versatile cornering.",
		"desc_ar": "متسابق شامل! انزلاق دقيق وتوازن مثالي بين السرعة والتحكم.",
		"body_color": Color(0.98, 0.34, 0.08),
		"accent_color": Color(1.0, 0.82, 0.12),
		"driver_color": Color(0.95, 0.45, 0.12),
		"ear_style": "fox",
		"stat_speed": 0.78,
		"stat_accel": 0.78,
		"stat_turn": 0.78,
		"top_speed_mult": 1.00,
		"accel_mult": 1.00,
		"turn_mult": 1.00,
		"drift_tightness": 1.00,
	},
	{
		"id": "apex",
		"name_en": "APEX",
		"name_ar": "أبيكس",
		"class_en": "SPEED",
		"class_ar": "سرعة قصوى",
		"desc_en": "Blistering top speed & terrifying Blue Fire pace. Master U-Turns to tame him!",
		"desc_ar": "سرعة قصوى خارقة مع اللهب الأزرق! يتطلب إتقان الالتفاف الهوائي U-Turn.",
		"body_color": Color(0.82, 0.08, 0.18),
		"accent_color": Color(1.0, 0.78, 0.08),
		"driver_color": Color(0.24, 0.68, 0.28),
		"ear_style": "dino",
		"stat_speed": 0.98,
		"stat_accel": 0.65,
		"stat_turn": 0.62,
		"top_speed_mult": 1.06,
		"accel_mult": 0.92,
		"turn_mult": 0.88,
		"drift_tightness": 0.90,
	},
	{
		"id": "zippy",
		"name_en": "ZIPPY",
		"name_ar": "زيبي",
		"class_en": "DRIFT / TURN",
		"class_ar": "تحكم وانزلاق",
		"desc_en": "Razor-sharp cornering & effortless aerial shortcut lines.",
		"desc_ar": "تحكم حاد كالموس ومنعطفات ضيقة مثالية لاقتناص الاختصارات الهوائية!",
		"body_color": Color(0.06, 0.68, 0.96),
		"accent_color": Color(0.94, 0.98, 1.0),
		"driver_color": Color(0.86, 0.94, 1.0),
		"ear_style": "polar",
		"stat_speed": 0.68,
		"stat_accel": 0.82,
		"stat_turn": 0.98,
		"top_speed_mult": 0.95,
		"accel_mult": 1.05,
		"turn_mult": 1.16,
		"drift_tightness": 1.15,
	},
	{
		"id": "turbox",
		"name_en": "TURBO-X",
		"name_ar": "تيربو إكس",
		"class_en": "ACCELERATION",
		"class_ar": "تسارع فائق",
		"desc_en": "Explosive boost recovery & rapid power-slide meter charging.",
		"desc_ar": "تسارع فوري واستعادة سريعة للسرعة مع شحن متفجر لمقياس التيربو!",
		"body_color": Color(0.52, 0.14, 0.88),
		"accent_color": Color(0.45, 1.0, 0.16),
		"driver_color": Color(0.32, 0.86, 0.42),
		"ear_style": "alien",
		"stat_speed": 0.74,
		"stat_accel": 0.98,
		"stat_turn": 0.82,
		"top_speed_mult": 0.98,
		"accel_mult": 1.14,
		"turn_mult": 1.04,
		"drift_tightness": 1.04,
	}
]

# Extra AI-only rival palettes so 6-kart races have 6 visually distinct rivals!
const EXTRA_AI_RACERS := [
	{
		"id": "tiki_rex",
		"name_en": "TIKI REX",
		"name_ar": "تيكي ريكس",
		"body_color": Color(0.14, 0.58, 0.34),
		"accent_color": Color(1.0, 0.66, 0.08),
		"driver_color": Color(0.66, 0.38, 0.18),
		"ear_style": "dino",
		"top_speed_mult": 1.01,
		"accel_mult": 0.98,
		"turn_mult": 0.98,
		"drift_tightness": 1.00,
	},
	{
		"id": "nova_volt",
		"name_en": "NOVA VOLT",
		"name_ar": "نوفا فولت",
		"body_color": Color(0.95, 0.16, 0.62),
		"accent_color": Color(0.10, 0.95, 1.0),
		"driver_color": Color(0.98, 0.82, 0.25),
		"ear_style": "fox",
		"top_speed_mult": 1.02,
		"accel_mult": 1.02,
		"turn_mult": 1.00,
		"drift_tightness": 1.02,
	}
]

const TRACKS := [
	{
		"id": "tiki_cove",
		"name_en": "EMERALD TEMPLE CIRCUIT",
		"name_ar": "حلبة المعبد الزمردي",
		"subtitle_en": "2.54 km • Jungle Village • River Gorge Jump • Inside the Pyramid • Canopy Trestle • Waterfall Cave • Lagoon • Ruins",
		"subtitle_ar": "2.54 كم • قرية الغابة • قفزة الوادي • داخل الهرم • جسر الأشجار • كهف الشلال • البحيرة • الأطلال",
		"difficulty": 1,
		"peak_fire_en": "SACRED FIRE",
		"peak_fire_ar": "اللهب المقدس",
		"peak_fire_color": Color(1.0, 0.58, 0.10),
		"laps": 3,
		"medals": {"bronze": 232.0, "silver": 205.0, "gold": 182.0},
		"shortcuts": [
			{"id": "emerald_summit_leap", "name_en": "Summit Corner Leap", "name_ar": "قفزة كسر منعطف القمة"},
			{"id": "emerald_lagoon_stones", "name_en": "Lagoon Stepping Stone", "name_ar": "حجر البحيرة العائم"},
			{"id": "emerald_ruin_vault", "name_en": "Ruin Wall Vault", "name_ar": "قفزة جدار الأطلال"}
		],
		"card_color_a": Color(0.14, 0.44, 0.22),
		"card_color_b": Color(0.98, 0.66, 0.14),
	},
	{
		"id": "glacier_peak",
		"name_en": "BIO-LAB HYDRO SPEEDWAY",
		"name_ar": "حلبة المختبر الحيوي المائي",
		"subtitle_en": "2.36 km • Reactor Atrium • Crusher Hall • Acid Catwalks • Hydro Tubes • Snow Switchbacks • Frozen Lake • Ice Cave",
		"subtitle_ar": "2.36 كم • قاعة المفاعل • قاعة المكابس • جسور الحمض • أنابيب الماء • منعطفات الثلج • البحيرة المتجمدة • كهف الجليد",
		"difficulty": 2,
		"peak_fire_en": "BLUE FIRE",
		"peak_fire_ar": "اللهب الأزرق",
		"peak_fire_color": Color(0.12, 0.85, 1.0),
		"laps": 3,
		"medals": {"bronze": 238.0, "silver": 212.0, "gold": 190.0},
		"shortcuts": [
			{"id": "biolab_acid_leap", "name_en": "Acid Pool Leap", "name_ar": "قفزة بركة الحمض"},
			{"id": "biolab_switchback_drop", "name_en": "Switchback Sky Drop", "name_ar": "قفزة المنعطفات الثلجية"},
			{"id": "biolab_ice_floe", "name_en": "Ice Floe Hop", "name_ar": "قفزة الجليد العائم"}
		],
		"card_color_a": Color(0.06, 0.42, 0.56),
		"card_color_b": Color(0.20, 0.94, 0.62),
	},
	{
		"id": "volcano_sky",
		"name_en": "COSMIC CITADEL STARWAY",
		"name_ar": "طريق القلعة الكونية",
		"subtitle_en": "2.42 km • Neon City • Skyline Highway • Launch Tube • Orbital Ring in Space • Asteroid Mine • Lava Causeway • Plasma Tube",
		"subtitle_ar": "2.42 كم • المدينة المضيئة • الطريق المعلق • نفق الإطلاق • الحلقة المدارية • منجم الكويكب • جسر الحمم • أنبوب البلازما",
		"difficulty": 3,
		"peak_fire_en": "ULTRA BLUE FIRE",
		"peak_fire_ar": "اللهب الأزرق الفائق",
		"peak_fire_color": Color(0.32, 0.65, 1.0),
		"laps": 3,
		"medals": {"bronze": 226.0, "silver": 200.0, "gold": 176.0},
		"shortcuts": [
			{"id": "cosmic_rooftop_hop", "name_en": "Citadel Rooftop Hop", "name_ar": "قفزة سطح البرج"},
			{"id": "cosmic_void_leap", "name_en": "Orbital Void Leap", "name_ar": "قفزة الفراغ المداري"},
			{"id": "cosmic_lava_leap", "name_en": "Lava Lake Leap", "name_ar": "قفزة بحيرة الحمم"}
		],
		"card_color_a": Color(0.28, 0.10, 0.52),
		"card_color_b": Color(1.0, 0.46, 0.10),
	}
]

# Bilingual UI Dictionary
const TR := {
	"title": {"en": "NITRO FURY RACING", "ar": "نيترو فيوري ريسينغ"},
	"subtitle": {"en": "CTR-INSPIRED HIGH-SKILL KART RACING", "ar": "سباق الكارتنج المستوحى من Crash Team Racing"},
	"arcade_race": {"en": "ARCADE RACE", "ar": "سباق سريع"},
	"grand_prix": {"en": "NITRO CUP (3 TRACKS)", "ar": "كأس النيترو (3 مسارات)"},
	"time_trial": {"en": "TIME TRIAL + GHOST", "ar": "تحدي الزمن + الشبح"},
	"practice_mode": {"en": "FREE PRACTICE / SHORTCUTS", "ar": "تدريب حر واكتشاف الاختصارات"},
	"academy": {"en": "CTR PRO GUIDE", "ar": "دليل مهارات CTR"},
	"settings": {"en": "SETTINGS", "ar": "الإعدادات"},
	"btn_opacity": {"en": "BUTTONS OPACITY", "ar": "شفافية الأزرار"},
	"graphics_mode": {"en": "SHADOWS / GFX", "ar": "الرسوميات والظلال"},
	"gfx_high": {"en": "HIGH", "ar": "عالية"},
	"gfx_fast": {"en": "PERFORMANCE (60FPS)", "ar": "أداء سريع 60FPS"},
	"look_back": {"en": "REAR", "ar": "خلف"},
	"respawn_track": {"en": "RESET TO TRACK", "ar": "العودة للمسار"},
	"btn_rescue": {"en": "FIX", "ar": "إنقاذ"},
	"btn_retry": {"en": "RETRY", "ar": "إعادة"},
	"sound_on": {"en": "SFX ON", "ar": "الصوت"},
	"sound_off": {"en": "MUTED", "ar": "صامت"},
	"cups_label": {"en": "CUPS", "ar": "الكؤوس"},
	"mirror_on": {"en": "MIRROR: ON", "ar": "وضع المرآة: مفعل"},
	"mirror_off": {"en": "MIRROR: OFF", "ar": "وضع المرآة: عادي"},
	"select_track": {"en": "SELECT TRACK", "ar": "اختر المسار"},
	"select_racer": {"en": "SELECT RACER", "ar": "اختر المتسابق"},
	"start_race": {"en": "START RACE!", "ar": "ابدأ السباق!"},
	"back": {"en": "BACK", "ar": "رجوع"},
	"next": {"en": "NEXT", "ar": "التالي"},
	"speed": {"en": "SPEED", "ar": "السرعة"},
	"accel": {"en": "ACCEL", "ar": "التسارع"},
	"turn": {"en": "TURN", "ar": "التحكم"},
	"difficulty": {"en": "AI LEVEL", "ar": "مستوى الذكاء"},
	"diff_0": {"en": "ROOKIE", "ar": "مبتدئ"},
	"diff_1": {"en": "NITRO", "ar": "محترف"},
	"diff_2": {"en": "CTR LEGEND", "ar": "أسطورة CTR"},
	"lap": {"en": "LAP", "ar": "اللفة"},
	"pos": {"en": "POS", "ar": "المركز"},
	"reserves": {"en": "RESERVES", "ar": "مخزون التيربو"},
	"juiced": {"en": "JUICED!", "ar": "قوة قصوى!"},
	"hop_drift": {"en": "HOP\nDRIFT", "ar": "قفز\nانزلاق"},
	"boost": {"en": "BOOST!", "ar": "تيربو!"},
	"uturn": {"en": "U-TURN\nBRAKE", "ar": "التفاف\nفرامل"},
	"gas": {"en": "GAS", "ar": "بنزين"},
	"item": {"en": "ITEM", "ar": "أداة"},
	"paused": {"en": "PAUSED", "ar": "إيقاف مؤقت"},
	"resume": {"en": "RESUME", "ar": "متابعة"},
	"restart": {"en": "RESTART", "ar": "إعادة السباق"},
	"main_menu": {"en": "MAIN MENU", "ar": "القائمة الرئيسية"},
	"next_track": {"en": "NEXT TRACK", "ar": "المسار التالي"},
	"race_finish": {"en": "FINISH!", "ar": "النهاية!"},
	"new_record": {"en": "NEW RECORD!", "ar": "رقم قياسي جديد!"},
	"shortcut_found": {"en": "AERIAL SHORTCUT!", "ar": "اختصار هوائي بارع!"},
	"sacred_fire": {"en": "SACRED FIRE!", "ar": "اللهب المقدس!"},
	"blue_fire": {"en": "BLUE FIRE!!", "ar": "اللهب الأزرق!!"},
	"perfect": {"en": "PERFECT!", "ar": "مثالي!"},
	"good": {"en": "GOOD!", "ar": "ممتاز!"},
	"backfire": {"en": "OVERCOOKED!", "ar": "احترق التيربو!"},
	"hang_boost": {"en": "HANG-TIME BOOST!", "ar": "تيربو القفز الهوائي!"},
	"wrong_way": {"en": "WRONG WAY!", "ar": "اتجاه خاطئ!"},
	"final_lap": {"en": "FINAL LAP!", "ar": "اللفة الأخيرة!"},
	"tnt_warn": {"en": "TNT! TAP HOP TO SHAKE OFF!", "ar": "قنبلة TNT! اضغط قفز للتخلص منها!"},
	"start_boost_hint": {"en": "PUMP BOOST INTO GOLD ZONE ON GO!", "ar": "اضغط تيربو داخل المنطقة الذهبية عند الإشارة!"},
	"start_bar_hint": {"en": "PUMP BOOST -> GOLD SWEET SPOT!", "ar": "اضغط تيربو للوصول للمنطقة الذهبية!"},
	"start_bar_sweet": {"en": "GOLD SWEET SPOT! HOLD ON GO!", "ar": "المنطقة الذهبية المثالية! انطلاقة نارية!"},
	"start_bar_overheat": {"en": "OVERHEAT! RELEASE!", "ar": "حرارة عالية! اترك الزر!"},
	"start_perfect": {"en": "PERFECT START BOOST!", "ar": "انطلاقة مثالية نارية!"},
	"start_good": {"en": "GOOD START BOOST!", "ar": "انطلاقة سريعة ممتازة!"},
	"wumpa_lost_all": {"en": "FELL IN ABYSS — ALL WUMPA LOST!", "ar": "سقطت في الهاوية — فقدت كل الوامبا!"},
	"item_turbo": {"en": "TURBO", "ar": "تيربو"},
	"item_missile": {"en": "ROCKET", "ar": "صاروخ"},
	"item_bomb": {"en": "BOMB", "ar": "قنبلة"},
	"item_shield": {"en": "SHIELD", "ar": "درع"},
	"item_tnt": {"en": "TNT", "ar": "TNT"},
	"item_mask": {"en": "MASK", "ar": "قناع"},
	"best_time": {"en": "BEST", "ar": "الأفضل"},
	"shortcuts_label": {"en": "SECRET SHORTCUTS", "ar": "اختصارات مخفية"},
	"lang_label": {"en": "LANGUAGE / اللغة", "ar": "اللغة / LANGUAGE"},
	"steer_mode": {"en": "STEERING", "ar": "أسلوب التوجيه"},
	"steer_buttons": {"en": "PRECISION BUTTONS", "ar": "أزرار دقيقة (موصى به)"},
	"steer_stick": {"en": "VIRTUAL JOYSTICK", "ar": "عصا تحكم لمسية"},
	"auto_gas": {"en": "AUTO ACCELERATE", "ar": "تسارع تلقائي"},
	"telemetry": {"en": "RESERVES HUD", "ar": "مقياس مخزون التيربو"},
	"on": {"en": "ON", "ar": "مفعل"},
	"off": {"en": "OFF", "ar": "معطل"},
	"sfx_vol": {"en": "SFX VOLUME", "ar": "صوت المؤثرات"},
	"music_vol": {"en": "MUSIC VOLUME", "ar": "صوت الموسيقى"},
	"cup_champion": {"en": "NITRO CUP CHAMPION!", "ar": "بطل كأس النيترو!"},
	"gp_standings": {"en": "CUP STANDINGS", "ar": "ترتيب الكأس"},
	"pts": {"en": "PTS", "ar": "نقطة"},
	"guide_body": {
		"en": "• WUMPA ECONOMY (+18% BASE SPEED): Collect up to 10 Wumpa Fruits to dramatically raise your kart's true base speed! Watch out: falling into an abyss wipes ALL Wumpa, and hard wall crashes drop 2–3 Wumpa!\n• START-LINE TIMING BAR: During 3-2-1, pump BOOST/GAS so the needle sits inside the Glowing Gold Sweet Spot (76%–94%) when GO! flashes for an explosive Perfect Launch!\n• POWER-SLIDE & RESERVES: Hold HOP/DRIFT while turning, then tap BOOST up to 3x in the glowing zone to stack Reserves and sustain controlled Sacred/Blue Fire!\n• JUMP-BASED CTR SHORTCUTS: No side-bridges! Look for corner-break chasm leaps, mid-air floating stepping-stone double-hops, and high crest vaults—carry speed + time your HOP!\n• AIR-BRAKE & U-TURN: Tap HOP then hold U-TURN + Left/Right in mid-air to snap cleanly around 90° and 180° turns without losing Reserves!\n• TNT CRATES: Tap HOP 5 times rapidly to shake off attached TNT before detonation!",
		"ar": "• اقتصاد فاكهة الوامبا (+18% للسرعة الأساسية): اجمع حتى 10 فواكه وامبا لرفع سرعتك الأساسية بشكل حاسم للفوز! انتبه: السقوط في الهاوية يفقدك جميع فواكه الوامبا، والاصطدام القوي بالجدران يفقدك 2 إلى 3 وامبا!\n• شريط التوقيت الدقيق للبداية: أثناء العد التنازلي 3-2-1 اضغط (تيربو/بنزين) لإبقاء المؤشر داخل المنطقة الذهبية (76%–94%) لحظة GO! لانطلاقة نارية!\n• الانزلاق الثلاثي والمخزون (Reserves): اضغط (قفز/انزلاق) مع التوجيه ثم اضغط (تيربو!) حتى 3 مرات متتالية للحفاظ على اللهب المقدس والأزرق بتحكم دقيق!\n• اختصارات القفز على طريقة CTR:NF: لا توجد طرق جانبية سهلة — ابحث عن قفزات كسر المنعطفات، والمنصات العائمة للوثب المزدوج، وقفزات القمم المرتفعة بتوقيت وسرعة مثاليين!\n• الالتفاف الهوائي (U-Turn): اقفز ثم اضغط (التفاف/فرامل) مع يمين/يسار في الهواء لتجاوز منعطفات 90° و 180° دون فقدان المخزون!\n• صناديق TNT: اضغط (قفز) بسرعة 5 مرات لنفضها قبل الانفجار!"
	}
}

func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(GHOST_DIR)
	load_save()

func t(key: String) -> String:
	if TR.has(key):
		var entry: Dictionary = TR[key]
		return entry.get(language, entry.get("en", key))
	return key

func is_rtl() -> bool:
	return language == "ar"

func toggle_language() -> void:
	language = "en" if language == "ar" else "ar"
	save_data()
	language_changed.emit(language)

func get_selected_racer() -> Dictionary:
	return RACERS[clampi(selected_racer_index, 0, RACERS.size() - 1)]

func get_selected_track() -> Dictionary:
	return TRACKS[clampi(selected_track_index, 0, TRACKS.size() - 1)]

func get_racer_name(racer: Dictionary) -> String:
	return racer.get("name_" + language, racer.get("name_en", "RACER"))

func get_track_name(track: Dictionary) -> String:
	return track.get("name_" + language, track.get("name_en", "TRACK"))

func format_time(sec: float) -> String:
	if sec < 0.0 or sec > 9999.0:
		return "--:--.--"
	var mins := int(sec) / 60
	var rem := sec - float(mins * 60)
	var secs := int(rem)
	var hundredths := int(round((rem - float(secs)) * 100.0)) % 100
	return "%02d:%02d.%02d" % [mins, secs, hundredths]

func record_shortcut(shortcut_id: String) -> bool:
	var is_new := not discovered_shortcuts.has(shortcut_id)
	discovered_shortcuts[shortcut_id] = true
	if is_new:
		save_data()
	return is_new

func count_track_shortcuts(track: Dictionary) -> int:
	var found := 0
	for sc in track.get("shortcuts", []):
		if discovered_shortcuts.has(sc["id"]):
			found += 1
	return found

func record_times(track_id: String, total_time: float, best_lap: float) -> bool:
	var is_new_record := false
	if total_time > 5.0:
		if not best_race_times.has(track_id) or total_time < float(best_race_times[track_id]):
			best_race_times[track_id] = total_time
			is_new_record = true
	if best_lap > 2.0:
		if not best_lap_times.has(track_id) or best_lap < float(best_lap_times[track_id]):
			best_lap_times[track_id] = best_lap
	save_data()
	return is_new_record

func start_grand_prix() -> void:
	gp_active = true
	gp_track_index = 0
	selected_track_index = 0
	selected_mode = GameMode.GRAND_PRIX
	gp_standings.clear()
	var player_racer := get_selected_racer()
	gp_standings.append({"id": player_racer["id"], "racer": player_racer, "points": 0, "is_player": true})
	var pool := []
	for r in RACERS:
		if r["id"] != player_racer["id"]:
			pool.append(r)
	for r in EXTRA_AI_RACERS:
		pool.append(r)
	for i in range(min(5, pool.size())):
		gp_standings.append({"id": pool[i]["id"], "racer": pool[i], "points": 0, "is_player": false})

func add_gp_race_points(finish_order: Array) -> void:
	var pts_table := [9, 6, 4, 3, 2, 1]
	for idx in range(finish_order.size()):
		var entry: Dictionary = finish_order[idx]
		var pts: int = pts_table[idx] if idx < pts_table.size() else 1
		for s in gp_standings:
			if s["id"] == entry["id"] and s["is_player"] == entry["is_player"]:
				s["points"] += pts
				break
	gp_standings.sort_custom(func(a, b): return a["points"] > b["points"])

func save_ghost(track_id: String, ghost_data: Dictionary) -> void:
	DirAccess.make_dir_recursive_absolute(GHOST_DIR)
	var f := FileAccess.open(GHOST_DIR + track_id + ".json", FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(ghost_data))
		f.close()

func load_ghost(track_id: String) -> Dictionary:
	var path := GHOST_DIR + track_id + ".json"
	if not FileAccess.file_exists(path):
		return {}
	var f := FileAccess.open(path, FileAccess.READ)
	if not f:
		return {}
	var parsed = JSON.parse_string(f.get_as_text())
	f.close()
	return parsed if parsed is Dictionary else {}

func save_data() -> void:
	var payload := {
		"language": language,
		"auto_accelerate": auto_accelerate,
		"use_joystick": use_joystick,
		"show_ctr_telemetry": show_ctr_telemetry,
		"controls_opacity": controls_opacity,
		"sfx_volume": sfx_volume,
		"music_volume": music_volume,
		"graphics_high": graphics_high,
		"ai_difficulty": ai_difficulty,
		"selected_racer_index": selected_racer_index,
		"best_race_times": best_race_times,
		"best_lap_times": best_lap_times,
		"discovered_shortcuts": discovered_shortcuts,
		"cups_won": cups_won
	}
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(payload, "\t"))
		f.close()

func load_save() -> void:
	if not FileAccess.file_exists(SAVE_PATH):
		return
	var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if not f:
		return
	var data = JSON.parse_string(f.get_as_text())
	f.close()
	if not (data is Dictionary):
		return
	language = str(data.get("language", language))
	auto_accelerate = bool(data.get("auto_accelerate", auto_accelerate))
	use_joystick = bool(data.get("use_joystick", use_joystick))
	show_ctr_telemetry = bool(data.get("show_ctr_telemetry", show_ctr_telemetry))
	controls_opacity = float(data.get("controls_opacity", controls_opacity))
	sfx_volume = float(data.get("sfx_volume", sfx_volume))
	music_volume = float(data.get("music_volume", music_volume))
	graphics_high = bool(data.get("graphics_high", graphics_high))
	ai_difficulty = int(data.get("ai_difficulty", ai_difficulty))
	selected_racer_index = int(data.get("selected_racer_index", selected_racer_index))
	best_race_times = data.get("best_race_times", {})
	best_lap_times = data.get("best_lap_times", {})
	discovered_shortcuts = data.get("discovered_shortcuts", {})
	cups_won = int(data.get("cups_won", cups_won))
