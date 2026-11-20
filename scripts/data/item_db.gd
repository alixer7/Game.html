extends Node
## قاعدة بيانات العناصر: كل الموارد والمواد والأدوات والطعام والملابس.
## الوزن بالكيلوغرام، والقيمة تستخدم في المقايضة مع الشخصيات.

const CAT_NAMES := {
	"res": "موارد خام", "mat": "مواد مصنّعة", "food": "طعام وشراب", "tool": "أدوات",
	"weapon": "أسلحة", "ammo": "ذخيرة", "wear": "ملابس ودروع", "med": "طب", "misc": "متفرقات",
}
const SLOT_NAMES := {"head": "الرأس", "body": "الجسم", "legs": "الساقان", "feet": "القدمان", "back": "الظهر"}

var items := {}

func _init() -> void:
	_define()

func _d(id: String, nm: String, cat: String, w: float, stack: int, icon: String, col: Color, value: float, extra := {}) -> void:
	var it := {"id": id, "name": nm, "cat": cat, "w": w, "stack": stack, "icon": icon, "color": col, "value": value, "desc": "", "tags": []}
	for k in extra:
		it[k] = extra[k]
	items[id] = it

func get_item(id: String) -> Dictionary:
	return items.get(id, {})

func exists(id: String) -> bool:
	return items.has(id)

func name_of(id: String) -> String:
	return items[id]["name"] if items.has(id) else id

func weight(id: String) -> float:
	return items[id]["w"] if items.has(id) else 0.0

func stack_of(id: String) -> int:
	return items[id]["stack"] if items.has(id) else 1

func value_of(id: String) -> float:
	return items[id]["value"] if items.has(id) else 0.0

func has_tag(id: String, tag: String) -> bool:
	return items.has(id) and tag in items[id]["tags"]

func with_tag(tag: String) -> Array:
	var out := []
	for id in items:
		if tag in items[id]["tags"]:
			out.append(id)
	return out

func tool_of(id: String) -> Dictionary:
	return items[id].get("tool", {}) if items.has(id) else {}

func max_dur(id: String) -> float:
	var t := tool_of(id)
	if t.has("dur"):
		return t["dur"]
	return -1.0

func describe(id: String) -> String:
	var it := get_item(id)
	if it.is_empty():
		return ""
	var lines := []
	if it["desc"] != "":
		lines.append(it["desc"])
	lines.append("الوزن: %.2f كغ  |  القيمة: %s" % [it["w"], str(snappedf(it["value"], 0.1))])
	if it.has("food"):
		var f: Dictionary = it["food"]
		var s := []
		if f.get("h", 0) != 0: s.append("شبع %+d" % f["h"])
		if f.get("t", 0) != 0: s.append("ارتواء %+d" % f["t"])
		if f.get("hp", 0) != 0: s.append("صحة %+d" % f["hp"])
		if f.get("warm", 0) != 0: s.append("دفء %+d" % f["warm"])
		if f.get("sick", 0.0) > 0.0: s.append("خطر مرض %d٪" % int(f["sick"] * 100))
		lines.append("  ".join(s))
	if it.has("spoil"):
		lines.append("يفسد خلال %d ساعة لعب تقريباً" % int(it["spoil"]))
	if it.has("tool"):
		var t: Dictionary = it["tool"]
		var s2 := "النوع: %s" % tool_kind_name(t.get("kind", ""))
		if t.has("tier"): s2 += "  |  المستوى: %d" % t["tier"]
		if t.has("dmg"): s2 += "  |  الضرر: %d" % t["dmg"]
		lines.append(s2)
	if it.has("wear"):
		var wr: Dictionary = it["wear"]
		var s3 := ["الموضع: %s" % SLOT_NAMES.get(wr["slot"], wr["slot"])]
		if wr.get("insul", 0) != 0: s3.append("عزل البرد %+d" % wr["insul"])
		if wr.get("heat", 0) != 0: s3.append("حماية الحر %+d" % wr["heat"])
		if wr.get("armor", 0) != 0: s3.append("دروع %+d" % wr["armor"])
		if wr.get("carry", 0) != 0: s3.append("سعة حمل %+d كغ" % wr["carry"])
		lines.append("  ".join(s3))
	if it.has("med"):
		lines.append("علاج: +%d صحة" % it["med"].get("hp", 0))
	if "fuel" in it["tags"]:
		lines.append("وقود")
	return "\n".join(lines)

func tool_kind_name(k: String) -> String:
	return {"axe": "فأس", "pickaxe": "معول", "knife": "سكين", "hammer": "مطرقة", "sword": "سيف",
		"spear": "رمح", "club": "هراوة", "bow": "قوس", "torch": "إضاءة", "rod": "صيد سمك"}.get(k, k)

func _define() -> void:
	# ---------------- موارد خام ----------------
	_d("wood", "خشب", "res", 2.0, 40, "log", Color(0.55, 0.36, 0.2), 1, {"tags": ["fuel"], "fuel": 60.0, "desc": "خشب عادي من الأشجار."})
	_d("hardwood", "خشب صلب", "res", 2.5, 30, "log", Color(0.36, 0.2, 0.1), 5, {"tags": ["fuel"], "fuel": 120.0, "desc": "خشب كثيف من أشجار البلوط المعمّرة. يحتاج فأساً برونزياً."})
	_d("stick", "عيدان", "res", 0.3, 60, "stick", Color(0.62, 0.46, 0.28), 0.5, {"tags": ["fuel"], "fuel": 20.0})
	_d("fiber", "ألياف نباتية", "res", 0.1, 99, "fiber", Color(0.55, 0.72, 0.3), 0.5, {"desc": "تُجمع من الشجيرات والعشب الطويل."})
	_d("palm_leaf", "سعف النخيل", "res", 0.3, 50, "leaf", Color(0.42, 0.62, 0.25), 0.5)
	_d("reeds", "قصب", "res", 0.2, 60, "fiber", Color(0.7, 0.68, 0.38), 0.5)
	_d("resin", "راتنج الصنوبر", "res", 0.2, 50, "drop", Color(0.88, 0.6, 0.15), 2, {"tags": ["fuel"], "fuel": 40.0})
	_d("stone", "حجر", "res", 1.5, 40, "stone", Color(0.55, 0.55, 0.55), 0.5)
	_d("flint", "صوان", "res", 0.4, 40, "stone", Color(0.28, 0.3, 0.36), 1, {"desc": "حجر حاد لصنع الأدوات الأولى."})
	_d("clay", "طين", "res", 1.2, 40, "heap", Color(0.64, 0.42, 0.3), 1)
	_d("sand", "رمل", "res", 1.0, 50, "heap", Color(0.88, 0.8, 0.56), 0.5)
	_d("ice", "جليد", "res", 0.6, 40, "gem", Color(0.75, 0.9, 1.0), 1, {"desc": "يمكن إذابته على النار للحصول على ماء نظيف."})
	_d("salt", "ملح", "res", 0.3, 50, "heap", Color(0.96, 0.96, 0.96), 3, {"desc": "لحفظ اللحم ودباغة الجلود."})
	_d("copper_ore", "خام النحاس", "res", 2.2, 30, "ore", Color(0.88, 0.5, 0.25), 3)
	_d("tin_ore", "خام القصدير", "res", 2.2, 30, "ore", Color(0.78, 0.8, 0.84), 3)
	_d("iron_ore", "خام الحديد", "res", 2.6, 30, "ore", Color(0.62, 0.3, 0.22), 5, {"desc": "يحتاج معولاً برونزياً على الأقل."})
	_d("coal", "فحم حجري", "res", 1.0, 40, "stone", Color(0.12, 0.12, 0.13), 3, {"tags": ["fuel", "hotfuel"], "fuel": 200.0})
	_d("gold_ore", "خام الذهب", "res", 3.0, 20, "ore", Color(1.0, 0.8, 0.2), 20, {"desc": "نادر. يوجد في الجبال والصحراء."})
	_d("crystal", "كريستال", "res", 0.5, 20, "gem", Color(0.62, 0.42, 1.0), 30, {"desc": "نادر جداً في قمم الجبال المثلجة."})
	_d("gemstone", "حجر كريم", "res", 0.2, 20, "gem", Color(0.92, 0.1, 0.25), 60, {"desc": "من أندر الموارد. قيمة تجارية عالية."})
	_d("obsidian", "سبج", "res", 1.2, 30, "gem", Color(0.12, 0.08, 0.16), 12, {"desc": "زجاج بركاني حاد جداً."})
	_d("sulfur", "كبريت", "res", 0.5, 40, "heap", Color(0.95, 0.88, 0.2), 6)
	_d("cotton", "قطن", "res", 0.1, 80, "cotton", Color(0.96, 0.96, 0.92), 1)
	_d("herbs", "أعشاب طبية", "res", 0.1, 50, "herb", Color(0.32, 0.66, 0.36), 3)
	_d("wheat", "قمح", "res", 0.2, 60, "wheat", Color(0.92, 0.76, 0.36), 2)
	_d("feather", "ريش", "res", 0.05, 99, "feather", Color(0.95, 0.95, 0.9), 1)
	_d("hide", "جلد خام", "res", 1.0, 20, "hide", Color(0.62, 0.44, 0.3), 4)
	_d("fur", "فرو", "res", 1.0, 20, "hide", Color(0.46, 0.38, 0.32), 8)
	_d("bone", "عظم", "res", 0.3, 40, "bone", Color(0.93, 0.9, 0.8), 1)
	_d("fat", "دهن حيواني", "res", 0.3, 30, "heap", Color(0.96, 0.9, 0.72), 2, {"tags": ["fuel"], "fuel": 60.0, "spoil": 120.0, "spoil_to": "rotten_food"})
	_d("toadstool", "فطر سام", "res", 0.1, 40, "mushroom", Color(0.86, 0.15, 0.1), 2, {"food": {"h": 2, "sick": 1.0, "poison": true}, "desc": "لا تأكله!"})
	_d("rotten_food", "طعام فاسد", "misc", 0.3, 40, "meat", Color(0.42, 0.46, 0.2), 0, {"tags": ["fertilizer"], "food": {"h": 3, "sick": 0.9}, "desc": "يصلح سماداً للحقول."})
	# ---------------- بذور ----------------
	_d("wheat_seed", "بذور القمح", "misc", 0.05, 99, "seed", Color(0.82, 0.7, 0.4), 1, {"tags": ["seed"], "plant": "wheat"})
	_d("cotton_seed", "بذور القطن", "misc", 0.05, 99, "seed", Color(0.9, 0.9, 0.85), 1, {"tags": ["seed"], "plant": "cotton"})
	# ---------------- طعام ----------------
	_d("potato", "بطاطا", "food", 0.3, 40, "fruit", Color(0.72, 0.56, 0.3), 2, {"tags": ["seed"], "plant": "potato", "food": {"h": 6}, "spoil": 240.0, "spoil_to": "rotten_food"})
	_d("berries", "توت بري", "food", 0.1, 50, "berry", Color(0.6, 0.1, 0.28), 1, {"food": {"h": 6, "t": 3}, "spoil": 48.0, "spoil_to": "rotten_food"})
	_d("mushroom", "فطر صالح للأكل", "food", 0.1, 40, "mushroom", Color(0.82, 0.7, 0.55), 1, {"food": {"h": 6}, "spoil": 72.0, "spoil_to": "rotten_food"})
	_d("cactus_fruit", "ثمرة الصبار", "food", 0.3, 30, "fruit", Color(0.86, 0.25, 0.42), 2, {"food": {"h": 5, "t": 14}, "spoil": 96.0, "spoil_to": "rotten_food"})
	_d("coconut", "جوز الهند", "food", 0.8, 20, "fruit", Color(0.46, 0.3, 0.18), 3, {"food": {"h": 10, "t": 18}, "spoil": 240.0, "spoil_to": "rotten_food"})
	_d("honey", "عسل", "food", 0.5, 20, "jar", Color(0.96, 0.7, 0.1), 12, {"food": {"h": 15, "t": -2, "hp": 10}})
	_d("raw_meat", "لحم نيء", "food", 0.5, 20, "meat", Color(0.82, 0.25, 0.25), 2, {"tags": ["raw"], "food": {"h": 12, "sick": 0.45}, "spoil": 24.0, "spoil_to": "rotten_food", "desc": "اطبخه أولاً لتجنب التسمم."})
	_d("cooked_meat", "لحم مشوي", "food", 0.4, 20, "meat", Color(0.55, 0.3, 0.15), 5, {"food": {"h": 32, "hp": 4}, "spoil": 60.0, "spoil_to": "rotten_food"})
	_d("salted_meat", "لحم مملّح", "food", 0.4, 30, "meat", Color(0.72, 0.42, 0.36), 6, {"food": {"h": 26, "t": -8}, "spoil": 600.0, "spoil_to": "rotten_food", "desc": "يدوم طويلاً لكنه يُعطش."})
	_d("raw_fish", "سمك نيء", "food", 0.4, 20, "fish", Color(0.6, 0.7, 0.8), 2, {"tags": ["raw"], "food": {"h": 8, "sick": 0.35}, "spoil": 18.0, "spoil_to": "rotten_food"})
	_d("cooked_fish", "سمك مشوي", "food", 0.3, 20, "fish", Color(0.76, 0.55, 0.3), 5, {"food": {"h": 24, "hp": 3}, "spoil": 48.0, "spoil_to": "rotten_food"})
	_d("baked_potato", "بطاطا مشوية", "food", 0.3, 30, "fruit", Color(0.66, 0.45, 0.2), 3, {"food": {"h": 18}, "spoil": 72.0, "spoil_to": "rotten_food"})
	_d("bread", "خبز", "food", 0.3, 20, "bread", Color(0.86, 0.6, 0.3), 6, {"food": {"h": 30}, "spoil": 120.0, "spoil_to": "rotten_food"})
	_d("stew", "يخنة لحم", "food", 0.8, 10, "bowl", Color(0.6, 0.35, 0.2), 14, {"food": {"h": 55, "t": 25, "hp": 10, "warm": 6}, "spoil": 48.0, "spoil_to": "rotten_food", "desc": "وجبة دافئة ومغذية جداً."})
	_d("mushroom_soup", "حساء الفطر", "food", 0.7, 10, "bowl", Color(0.76, 0.66, 0.46), 8, {"food": {"h": 32, "t": 22, "warm": 4}, "spoil": 48.0, "spoil_to": "rotten_food"})
	_d("herbal_tea", "شاي أعشاب", "food", 0.5, 10, "bowl", Color(0.5, 0.72, 0.4), 6, {"food": {"t": 20, "warm": 8, "cure": ["sick"]}})
	# ---------------- ماء ----------------
	_d("waterskin", "قربة ماء فارغة", "misc", 0.3, 1, "waterskin", Color(0.56, 0.4, 0.25), 3, {"tags": ["container"], "desc": "املأها من نهر أو بحيرة أو مجمع مياه."})
	_d("waterskin_dirty", "قربة ماء عكِر", "food", 1.3, 1, "waterskin", Color(0.46, 0.52, 0.36), 3, {"food": {"t": 30, "sick": 0.35}, "returns": "waterskin", "desc": "اغلِها على النار قبل الشرب."})
	_d("waterskin_clean", "قربة ماء نظيف", "food", 1.3, 1, "waterskin", Color(0.35, 0.62, 0.88), 5, {"food": {"t": 38}, "returns": "waterskin"})
	# ---------------- مواد مصنعة ----------------
	_d("plank", "ألواح خشبية", "mat", 1.0, 40, "plank", Color(0.74, 0.54, 0.32), 2, {"tags": ["fuel"], "fuel": 40.0})
	_d("rope", "حبل", "mat", 0.2, 40, "rope", Color(0.76, 0.62, 0.4), 2)
	_d("cloth", "قماش", "mat", 0.3, 40, "cloth", Color(0.86, 0.82, 0.72), 3)
	_d("leather", "جلد مدبوغ", "mat", 0.8, 30, "hide", Color(0.5, 0.3, 0.15), 7)
	_d("charcoal", "فحم نباتي", "mat", 0.5, 50, "stone", Color(0.18, 0.16, 0.15), 2, {"tags": ["fuel", "hotfuel"], "fuel": 160.0})
	_d("copper_ingot", "سبيكة نحاس", "mat", 1.5, 30, "ingot", Color(0.86, 0.48, 0.25), 8)
	_d("tin_ingot", "سبيكة قصدير", "mat", 1.5, 30, "ingot", Color(0.8, 0.82, 0.84), 8)
	_d("bronze_ingot", "سبيكة برونز", "mat", 1.5, 30, "ingot", Color(0.76, 0.56, 0.26), 12)
	_d("iron_ingot", "سبيكة حديد", "mat", 1.8, 30, "ingot", Color(0.55, 0.56, 0.6), 15)
	_d("steel_ingot", "سبيكة فولاذ", "mat", 1.8, 30, "ingot", Color(0.72, 0.76, 0.84), 28)
	_d("gold_ingot", "سبيكة ذهب", "mat", 2.0, 20, "ingot", Color(1.0, 0.82, 0.25), 45)
	_d("glass", "زجاج", "mat", 0.8, 30, "gem", Color(0.72, 0.9, 0.95), 5)
	_d("brick", "طوب", "mat", 1.6, 40, "brick", Color(0.72, 0.32, 0.22), 2)
	_d("nails", "مسامير", "mat", 0.05, 99, "nails", Color(0.56, 0.56, 0.6), 1)
	_d("iron_lock", "قفل حديدي", "misc", 0.5, 10, "lock", Color(0.56, 0.56, 0.6), 18, {"desc": "يُركّب على الأبواب لمنع اللصوص."})
	_d("gold_coin", "عملة ذهبية", "misc", 0.01, 999, "coin", Color(1.0, 0.85, 0.3), 10, {"desc": "عملة مقبولة لدى كل التجار."})
	_d("gem_amulet", "قلادة الجواهر", "misc", 0.1, 5, "gem", Color(0.9, 0.3, 0.55), 120, {"desc": "هدية ثمينة جداً تكسب بها قلوب الناس."})
	# ---------------- أدوات ----------------
	_d("stone_axe", "فأس حجري", "tool", 1.5, 1, "axe", Color(0.55, 0.55, 0.55), 4, {"tool": {"kind": "axe", "tier": 1, "power": 10.0, "dmg": 9.0, "dur": 120.0, "speed": 0.9}})
	_d("stone_pickaxe", "معول حجري", "tool", 1.8, 1, "pickaxe", Color(0.55, 0.55, 0.55), 4, {"tool": {"kind": "pickaxe", "tier": 1, "power": 10.0, "dmg": 8.0, "dur": 120.0, "speed": 1.0}})
	_d("flint_knife", "سكين صوان", "tool", 0.3, 1, "knife", Color(0.3, 0.32, 0.38), 3, {"tool": {"kind": "knife", "tier": 1, "power": 6.0, "dmg": 7.0, "dur": 100.0, "speed": 0.55}, "desc": "ضرورية لسلخ الحيوانات والحصول على الجلد."})
	_d("hammer", "مطرقة البناء", "tool", 1.2, 1, "hammer", Color(0.6, 0.58, 0.55), 4, {"tool": {"kind": "hammer", "tier": 1, "power": 4.0, "dmg": 6.0, "dur": 400.0, "speed": 0.8}, "desc": "مطلوبة للبناء. احملها في حقيبتك."})
	_d("bronze_axe", "فأس برونزي", "tool", 2.0, 1, "axe", Color(0.76, 0.56, 0.26), 20, {"tool": {"kind": "axe", "tier": 2, "power": 18.0, "dmg": 14.0, "dur": 300.0, "speed": 0.85}})
	_d("bronze_pickaxe", "معول برونزي", "tool", 2.2, 1, "pickaxe", Color(0.76, 0.56, 0.26), 20, {"tool": {"kind": "pickaxe", "tier": 2, "power": 18.0, "dmg": 12.0, "dur": 300.0, "speed": 0.95}})
	_d("iron_axe", "فأس حديدي", "tool", 2.2, 1, "axe", Color(0.6, 0.62, 0.66), 35, {"tool": {"kind": "axe", "tier": 3, "power": 28.0, "dmg": 18.0, "dur": 500.0, "speed": 0.8}})
	_d("iron_pickaxe", "معول حديدي", "tool", 2.4, 1, "pickaxe", Color(0.6, 0.62, 0.66), 35, {"tool": {"kind": "pickaxe", "tier": 3, "power": 28.0, "dmg": 16.0, "dur": 500.0, "speed": 0.9}})
	_d("steel_pickaxe", "معول فولاذي", "tool", 2.4, 1, "pickaxe", Color(0.74, 0.78, 0.86), 60, {"tool": {"kind": "pickaxe", "tier": 4, "power": 40.0, "dmg": 20.0, "dur": 800.0, "speed": 0.85}})
	_d("obsidian_knife", "سكين السبج", "tool", 0.4, 1, "knife", Color(0.15, 0.1, 0.2), 20, {"tool": {"kind": "knife", "tier": 3, "power": 14.0, "dmg": 16.0, "dur": 150.0, "speed": 0.45}})
	_d("fishing_rod", "صنارة صيد", "tool", 0.8, 1, "rod", Color(0.6, 0.46, 0.28), 6, {"tool": {"kind": "rod", "tier": 1, "dur": 60.0}, "desc": "انظر إلى الماء واضغط زر الاستخدام."})
	_d("torch", "شعلة", "tool", 0.6, 1, "torch", Color(1.0, 0.6, 0.2), 2, {"tool": {"kind": "torch", "tier": 0, "dmg": 5.0, "dur": 420.0, "speed": 0.8}, "desc": "تضيء الظلام وتدفئك قليلاً وتُبعد الحيوانات. تحترق مع الوقت."})
	# ---------------- أسلحة ----------------
	_d("wooden_club", "هراوة خشبية", "weapon", 1.5, 1, "club", Color(0.5, 0.34, 0.2), 3, {"tool": {"kind": "club", "tier": 1, "dmg": 11.0, "dur": 150.0, "speed": 1.0}})
	_d("wooden_spear", "رمح خشبي", "weapon", 1.2, 1, "spear", Color(0.6, 0.45, 0.28), 4, {"tool": {"kind": "spear", "tier": 1, "dmg": 14.0, "dur": 90.0, "speed": 1.0, "range": 2.8}})
	_d("obsidian_spear", "رمح السبج", "weapon", 1.5, 1, "spear", Color(0.15, 0.1, 0.2), 30, {"tool": {"kind": "spear", "tier": 3, "dmg": 28.0, "dur": 160.0, "speed": 0.95, "range": 2.9}})
	_d("bronze_sword", "سيف برونزي", "weapon", 1.8, 1, "sword", Color(0.76, 0.56, 0.26), 30, {"tool": {"kind": "sword", "tier": 2, "dmg": 22.0, "dur": 300.0, "speed": 0.75}})
	_d("iron_sword", "سيف حديدي", "weapon", 2.0, 1, "sword", Color(0.6, 0.62, 0.66), 50, {"tool": {"kind": "sword", "tier": 3, "dmg": 30.0, "dur": 450.0, "speed": 0.72}})
	_d("steel_sword", "سيف فولاذي", "weapon", 2.0, 1, "sword", Color(0.74, 0.78, 0.86), 80, {"tool": {"kind": "sword", "tier": 4, "dmg": 40.0, "dur": 700.0, "speed": 0.7}})
	_d("bow", "قوس صيد", "weapon", 0.8, 1, "bow", Color(0.55, 0.38, 0.2), 10, {"tool": {"kind": "bow", "tier": 1, "dmg": 8.0, "dur": 200.0, "speed": 1.1}, "desc": "يحتاج سهاماً في الحقيبة."})
	_d("arrow", "سهم صوان", "ammo", 0.05, 50, "arrow", Color(0.6, 0.6, 0.6), 1, {"tags": ["arrow"], "dmg": 12.0})
	_d("obsidian_arrow", "سهم السبج", "ammo", 0.05, 50, "arrow", Color(0.2, 0.12, 0.25), 3, {"tags": ["arrow"], "dmg": 22.0})
	# ---------------- ملابس ----------------
	_d("straw_hat", "قبعة قش", "wear", 0.2, 1, "hat", Color(0.88, 0.76, 0.4), 3, {"wear": {"slot": "head", "heat": 6}})
	_d("fur_hat", "قبعة فرو", "wear", 0.5, 1, "hat", Color(0.46, 0.36, 0.26), 12, {"wear": {"slot": "head", "insul": 6}})
	_d("cloth_shirt", "قميص قماش", "wear", 0.4, 1, "shirt", Color(0.38, 0.45, 0.52), 10, {"wear": {"slot": "body", "insul": 3, "heat": 3}})
	_d("leather_jacket", "سترة جلدية", "wear", 1.5, 1, "shirt", Color(0.46, 0.28, 0.15), 30, {"wear": {"slot": "body", "insul": 7, "armor": 4}})
	_d("fur_coat", "معطف فرو", "wear", 2.5, 1, "coat", Color(0.52, 0.42, 0.32), 50, {"wear": {"slot": "body", "insul": 16, "heat": -8, "armor": 2}, "desc": "ضروري في الشمال المتجمد، خانق في الصحراء."})
	_d("desert_robe", "عباءة صحراوية", "wear", 0.8, 1, "coat", Color(0.92, 0.86, 0.7), 22, {"wear": {"slot": "body", "insul": 3, "heat": 12}})
	_d("bronze_armor", "درع برونزي", "wear", 7.0, 1, "armor", Color(0.76, 0.56, 0.26), 90, {"wear": {"slot": "body", "armor": 12, "insul": 1, "heat": -4}})
	_d("iron_armor", "درع حديدي", "wear", 9.0, 1, "armor", Color(0.56, 0.57, 0.62), 160, {"wear": {"slot": "body", "armor": 20, "insul": 1, "heat": -5}})
	_d("cloth_pants", "سروال قماش", "wear", 0.4, 1, "pants", Color(0.5, 0.45, 0.36), 8, {"wear": {"slot": "legs", "insul": 2, "heat": 2}})
	_d("leather_pants", "سروال جلدي", "wear", 1.2, 1, "pants", Color(0.4, 0.25, 0.12), 24, {"wear": {"slot": "legs", "insul": 5, "armor": 3}})
	_d("leather_boots", "حذاء جلدي", "wear", 0.8, 1, "boots", Color(0.36, 0.22, 0.12), 14, {"wear": {"slot": "feet", "insul": 2, "armor": 1}})
	_d("fur_boots", "حذاء فرو", "wear", 1.0, 1, "boots", Color(0.46, 0.38, 0.3), 18, {"wear": {"slot": "feet", "insul": 6}})
	_d("fiber_backpack", "حقيبة ألياف", "wear", 0.6, 1, "bag", Color(0.62, 0.62, 0.36), 8, {"wear": {"slot": "back", "carry": 10}})
	_d("leather_backpack", "حقيبة جلدية", "wear", 1.2, 1, "bag", Color(0.46, 0.28, 0.15), 40, {"wear": {"slot": "back", "carry": 25}})
	# ---------------- طب ----------------
	_d("bandage", "ضمادة", "med", 0.05, 20, "bandage", Color(0.95, 0.95, 0.9), 3, {"med": {"hp": 10, "cure": ["bleed"]}})
	_d("herbal_medicine", "دواء عشبي", "med", 0.2, 10, "potion", Color(0.36, 0.66, 0.3), 8, {"med": {"hp": 15, "cure": ["sick", "poison"]}})
	_d("antiseptic", "مطهّر الكبريت", "med", 0.2, 10, "potion", Color(0.92, 0.86, 0.3), 10, {"med": {"hp": 25, "cure": ["bleed", "sick", "poison"]}})
