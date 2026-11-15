class_name PlayerProfile
extends RefCounted
## ملفات اللاعبين: التقييمات (0-100) والمظهر وأسلوب اللعب، وتحويل التقييمات إلى معاملات لعب فعلية.

const KEYS := ["forehand", "backhand", "serve_acc", "serve_pow", "return", "volley", "smash", "touch",
	"power", "spin", "speed", "agility", "stamina", "reflexes", "balance", "mental"]

const NAMES := {
	"forehand": "دقة الضربة الأمامية", "backhand": "دقة الضربة الخلفية", "serve_acc": "دقة الإرسال",
	"serve_pow": "قوة الإرسال", "return": "استقبال الإرسال", "volley": "دقة الضربات الطائرة",
	"smash": "الضربة الساحقة", "touch": "اللمسة (الساقطة)", "power": "قوة الضرب", "spin": "الدوران",
	"speed": "السرعة", "agility": "دقة المناورة والرشاقة", "stamina": "التحمّل", "reflexes": "سرعة رد الفعل",
	"balance": "التوازن ومرونة الجسم", "mental": "الثبات تحت الضغط",
}

const GROUPS := [
	["الضربات", ["forehand", "backhand", "power", "spin", "touch"]],
	["الإرسال والاستقبال", ["serve_pow", "serve_acc", "return"]],
	["الشبكة", ["volley", "smash"]],
	["البدنية", ["speed", "agility", "stamina", "balance"]],
	["الذهنية", ["reflexes", "mental"]],
]

const ROSTER := [
	{"id": "samer", "name": "سامر الحداد", "style": "لاعب شامل متوازن", "body": "athlete", "hand": 1, "two_handed": true,
		"r": {"forehand": 84, "backhand": 82, "serve_acc": 80, "serve_pow": 80, "return": 80, "volley": 76, "smash": 79, "touch": 75,
			"power": 81, "spin": 82, "speed": 81, "agility": 82, "stamina": 83, "reflexes": 80, "balance": 81, "mental": 80},
		"look": {"skin": Color(0.80, 0.60, 0.47), "hair": Color(0.09, 0.07, 0.05), "iris": Color(0.30, 0.19, 0.10),
			"shirt": Color(0.93, 0.94, 0.96), "shirt_back": Color(0.93, 0.94, 0.96), "shirt_trim": Color(0.10, 0.22, 0.52),
			"shorts": Color(0.08, 0.13, 0.30), "shorts_stripe": Color(0.93, 0.93, 0.95), "shoes": Color(0.95, 0.95, 0.96),
			"shoes_accent": Color(0.12, 0.30, 0.70), "sock": Color(0.94, 0.94, 0.93), "racket": Color(0.08, 0.08, 0.10), "stubble": 0.5}},
	{"id": "karim", "name": "كريم ناصر", "style": "ضارب قوي من الخط الخلفي", "body": "power", "hand": 1, "two_handed": true,
		"r": {"forehand": 88, "backhand": 80, "serve_acc": 74, "serve_pow": 87, "return": 78, "volley": 62, "smash": 80, "touch": 60,
			"power": 93, "spin": 86, "speed": 74, "agility": 72, "stamina": 80, "reflexes": 76, "balance": 78, "mental": 74},
		"look": {"skin": Color(0.43, 0.29, 0.21), "hair": Color(0.04, 0.03, 0.03), "iris": Color(0.18, 0.11, 0.06),
			"shirt": Color(0.78, 0.13, 0.12), "shirt_back": Color(0.78, 0.13, 0.12), "shirt_trim": Color(0.08, 0.08, 0.09),
			"shorts": Color(0.07, 0.07, 0.08), "shorts_stripe": Color(0.78, 0.13, 0.12), "shoes": Color(0.10, 0.10, 0.11),
			"shoes_accent": Color(0.85, 0.15, 0.12), "sock": Color(0.92, 0.92, 0.92), "racket": Color(0.75, 0.10, 0.10), "stubble": 0.7}},
	{"id": "yousef", "name": "يوسف العمري", "style": "إرسال وصعود للشبكة", "body": "classic", "hand": 1, "two_handed": false,
		"r": {"forehand": 79, "backhand": 76, "serve_acc": 85, "serve_pow": 86, "return": 71, "volley": 93, "smash": 89, "touch": 84,
			"power": 78, "spin": 70, "speed": 79, "agility": 85, "stamina": 74, "reflexes": 88, "balance": 82, "mental": 81},
		"look": {"skin": Color(0.72, 0.52, 0.39), "hair": Color(0.20, 0.13, 0.07), "iris": Color(0.25, 0.30, 0.18),
			"shirt": Color(0.95, 0.95, 0.93), "shirt_back": Color(0.95, 0.95, 0.93), "shirt_trim": Color(0.05, 0.38, 0.22),
			"shorts": Color(0.95, 0.95, 0.93), "shorts_stripe": Color(0.05, 0.38, 0.22), "shoes": Color(0.96, 0.96, 0.96),
			"shoes_accent": Color(0.05, 0.42, 0.25), "sock": Color(0.96, 0.96, 0.95), "racket": Color(0.12, 0.12, 0.13), "stubble": 0.35}},
	{"id": "tarek", "name": "طارق منصور", "style": "مدافع عنيد سريع", "body": "lean", "hand": 1, "two_handed": true,
		"r": {"forehand": 80, "backhand": 84, "serve_acc": 78, "serve_pow": 68, "return": 89, "volley": 66, "smash": 70, "touch": 78,
			"power": 70, "spin": 80, "speed": 93, "agility": 92, "stamina": 95, "reflexes": 90, "balance": 88, "mental": 86},
		"look": {"skin": Color(0.84, 0.66, 0.52), "hair": Color(0.06, 0.05, 0.05), "iris": Color(0.12, 0.08, 0.05),
			"shirt": Color(0.12, 0.50, 0.85), "shirt_back": Color(0.12, 0.50, 0.85), "shirt_trim": Color(0.95, 0.95, 0.95),
			"shorts": Color(0.06, 0.10, 0.22), "shorts_stripe": Color(0.12, 0.50, 0.85), "shoes": Color(0.95, 0.95, 0.96),
			"shoes_accent": Color(0.95, 0.55, 0.10), "sock": Color(0.94, 0.94, 0.93), "racket": Color(0.95, 0.55, 0.10), "stubble": 0.15}},
	{"id": "mazen", "name": "مازن فاروق", "style": "مدفعية الإرسال", "body": "athlete", "hand": 1, "two_handed": true,
		"r": {"forehand": 82, "backhand": 74, "serve_acc": 83, "serve_pow": 97, "return": 66, "volley": 75, "smash": 86, "touch": 64,
			"power": 88, "spin": 74, "speed": 67, "agility": 66, "stamina": 71, "reflexes": 74, "balance": 72, "mental": 79},
		"look": {"skin": Color(0.66, 0.47, 0.34), "hair": Color(0.03, 0.03, 0.03), "iris": Color(0.15, 0.09, 0.05),
			"shirt": Color(0.10, 0.10, 0.12), "shirt_back": Color(0.10, 0.10, 0.12), "shirt_trim": Color(0.92, 0.80, 0.20),
			"shorts": Color(0.10, 0.10, 0.12), "shorts_stripe": Color(0.92, 0.80, 0.20), "shoes": Color(0.12, 0.12, 0.13),
			"shoes_accent": Color(0.92, 0.80, 0.20), "sock": Color(0.12, 0.12, 0.13), "racket": Color(0.92, 0.80, 0.20), "stubble": 0.85}},
	{"id": "adel", "name": "عادل رشيد", "style": "فنان اللمسة (أعسر)", "body": "classic", "hand": -1, "two_handed": false,
		"r": {"forehand": 85, "backhand": 83, "serve_acc": 84, "serve_pow": 76, "return": 80, "volley": 84, "smash": 78, "touch": 95,
			"power": 72, "spin": 91, "speed": 79, "agility": 81, "stamina": 79, "reflexes": 82, "balance": 85, "mental": 89},
		"look": {"skin": Color(0.88, 0.70, 0.58), "hair": Color(0.30, 0.20, 0.10), "iris": Color(0.22, 0.32, 0.42),
			"shirt": Color(0.98, 0.84, 0.30), "shirt_back": Color(0.98, 0.84, 0.30), "shirt_trim": Color(0.10, 0.12, 0.20),
			"shorts": Color(0.10, 0.12, 0.20), "shorts_stripe": Color(0.98, 0.84, 0.30), "shoes": Color(0.95, 0.95, 0.96),
			"shoes_accent": Color(0.10, 0.12, 0.20), "sock": Color(0.94, 0.94, 0.93), "racket": Color(0.15, 0.15, 0.18), "stubble": 0.3}},
	{"id": "faisal", "name": "فيصل الأحمد", "style": "ناشئ صاعد", "body": "lean", "hand": 1, "two_handed": true,
		"r": {"forehand": 72, "backhand": 70, "serve_acc": 68, "serve_pow": 70, "return": 69, "volley": 62, "smash": 66, "touch": 64,
			"power": 72, "spin": 72, "speed": 76, "agility": 74, "stamina": 76, "reflexes": 70, "balance": 70, "mental": 62},
		"look": {"skin": Color(0.76, 0.56, 0.42), "hair": Color(0.07, 0.05, 0.04), "iris": Color(0.22, 0.14, 0.08),
			"shirt": Color(0.20, 0.62, 0.42), "shirt_back": Color(0.20, 0.62, 0.42), "shirt_trim": Color(0.96, 0.96, 0.96),
			"shorts": Color(0.95, 0.95, 0.95), "shorts_stripe": Color(0.20, 0.62, 0.42), "shoes": Color(0.95, 0.95, 0.96),
			"shoes_accent": Color(0.20, 0.62, 0.42), "sock": Color(0.94, 0.94, 0.93), "racket": Color(0.10, 0.45, 0.30), "stubble": 0.1}},
	{"id": "hamza", "name": "حمزة الشريف", "style": "النجم الأول عالمياً", "body": "power", "hand": 1, "two_handed": true,
		"r": {"forehand": 93, "backhand": 92, "serve_acc": 88, "serve_pow": 88, "return": 93, "volley": 82, "smash": 87, "touch": 85,
			"power": 89, "spin": 90, "speed": 89, "agility": 92, "stamina": 92, "reflexes": 92, "balance": 93, "mental": 94},
		"look": {"skin": Color(0.58, 0.41, 0.30), "hair": Color(0.05, 0.04, 0.03), "iris": Color(0.14, 0.09, 0.05),
			"shirt": Color(0.42, 0.18, 0.62), "shirt_back": Color(0.42, 0.18, 0.62), "shirt_trim": Color(0.96, 0.96, 0.96),
			"shorts": Color(0.96, 0.96, 0.96), "shorts_stripe": Color(0.42, 0.18, 0.62), "shoes": Color(0.96, 0.96, 0.96),
			"shoes_accent": Color(0.42, 0.18, 0.62), "sock": Color(0.94, 0.94, 0.93), "racket": Color(0.08, 0.08, 0.10), "stubble": 0.6}},
]


static func get_profile(id: String) -> Dictionary:
	for p in ROSTER:
		if p["id"] == id:
			return p
	return ROSTER[0]


static func index_of(id: String) -> int:
	for i in ROSTER.size():
		if ROSTER[i]["id"] == id:
			return i
	return 0


static func overall(r: Dictionary) -> int:
	var w := {"forehand": 1.3, "backhand": 1.2, "serve_acc": 1.0, "serve_pow": 1.0, "return": 1.0, "volley": 0.7, "smash": 0.5,
		"touch": 0.6, "power": 1.0, "spin": 0.7, "speed": 1.1, "agility": 1.0, "stamina": 0.8, "reflexes": 0.8, "balance": 0.8, "mental": 0.9}
	var s := 0.0
	var ws := 0.0
	for k in w:
		s += float(r.get(k, 70)) * float(w[k])
		ws += float(w[k])
	return int(round(s / ws))


## تقييم معدَّل (للخصم الآلي حسب مستوى الصعوبة)
static func adjusted(r: Dictionary, offset: float) -> Dictionary:
	var out := {}
	for k in KEYS:
		out[k] = clampf(float(r.get(k, 70)) + offset, 30.0, 99.0)
	return out


static func t(r: Dictionary, k: String) -> float:
	return clampf((float(r.get(k, 70)) - 40.0) / 60.0, 0.0, 1.0)


## تحويل التقييمات إلى معاملات اللعب الفعلية
static func derive(r: Dictionary) -> Dictionary:
	return {
		"speed": 5.3 + 1.7 * t(r, "speed"),                 # م/ث أقصى سرعة جري
		"accel": 5.6 + 3.6 * t(r, "agility"),               # م/ث² تسارع
		"brake": 1.25 + 0.35 * t(r, "agility"),             # مضاعف الكبح
		"reach": 1.62 + 0.30 * t(r, "balance"),             # أقصى مدّ جانبي
		"drain": 1.45 - 0.75 * t(r, "stamina"),             # معدل استنزاف اللياقة
		"recover": 0.07 + 0.07 * t(r, "stamina"),           # استعادة بين النقاط
		"react": 0.34 - 0.17 * t(r, "reflexes"),            # زمن رد الفعل (للآلي)
		"rush": 2.7 - 1.4 * t(r, "reflexes"),               # حساسية ضيق الوقت
		"ret": 1.35 - 0.6 * t(r, "return"),                 # صعوبة استقبال الإرسال
		"acc_fh": 1.6 - 0.9 * t(r, "forehand"),             # مضاعف الخطأ (أقل = أدق)
		"acc_bh": 1.6 - 0.9 * t(r, "backhand"),
		"acc_vo": 1.6 - 0.9 * t(r, "volley"),
		"acc_sm": 1.6 - 0.9 * t(r, "smash"),
		"acc_to": 1.6 - 0.9 * t(r, "touch"),
		"acc_sv": 1.55 - 0.85 * t(r, "serve_acc"),
		"racket": 22.5 + 9.0 * t(r, "power"),               # م/ث أقصى سرعة لرأس المضرب
		"serve_max": 46.5 + 15.5 * t(r, "serve_pow"),       # م/ث أقصى سرعة إرسال (167-223 كم/س)
		"spin": 0.78 + 0.42 * t(r, "spin"),
		"bal": 1.55 - 0.85 * t(r, "balance"),               # عقوبة الضرب دون توازن
		"mental": 1.0 + 0.5 * (1.0 - t(r, "mental")),       # تضخم الخطأ في النقاط الحاسمة
		"pow_ctrl": 1.35 - 0.55 * t(r, "power"),            # كلفة الدقة عند الضرب بأقصى قوة
	}


## عرض المنطقة الخضراء في شريط التوقيت حسب مهارة الضربة
static func green_width(r: Dictionary, stroke_key: String) -> float:
	return 0.13 + 0.07 * t(r, stroke_key)
