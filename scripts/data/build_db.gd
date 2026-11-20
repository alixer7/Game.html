extends Node
## قطع البناء. قطع "grid" تلتصق بشبكة المبنى (أساسات، جدران، أسقف...)، وقطع "free" توضع بحرية (محطات، صناديق، أثاث).

const CELL := 3.0
const WALL_H := 3.0

const CATS := ["structure", "station", "storage", "furniture", "farming", "defense"]
const CAT_NAMES := {"structure": "هياكل", "station": "محطات صناعة", "storage": "تخزين", "furniture": "أثاث وإضاءة", "farming": "زراعة ومياه", "defense": "دفاع وملكية"}
const MAT_NAMES := {"thatch": "قش", "wood": "خشب", "stone": "حجر", "brick": "طوب"}
const MAT_HP := {"thatch": 150.0, "wood": 320.0, "stone": 700.0, "brick": 900.0}
const MAT_INSUL := {"thatch": 0.45, "wood": 0.7, "stone": 0.85, "brick": 1.0}

var pieces := {}
var order: Array = []

func _init() -> void:
	_define()

func _p(id: String, nm: String, cat: String, kind: String, cost: Dictionary, extra := {}) -> void:
	var p := {"id": id, "name": nm, "cat": cat, "kind": kind, "cost": cost, "hp": 200.0, "slot": "", "mat": "", "station": "", "desc": ""}
	for k in extra:
		p[k] = extra[k]
	pieces[id] = p
	order.append(id)

func get_piece(id: String) -> Dictionary:
	return pieces.get(id, {})

func cost_text(id: String) -> String:
	var p := get_piece(id)
	var parts := []
	for k in p.get("cost", {}):
		parts.append("%s ×%d" % [ItemDB.name_of(k), p["cost"][k]])
	return "، ".join(parts)

func _define() -> void:
	# ------- هياكل الشبكة -------
	var mats := {
		"thatch": {"wall": {"stick": 6, "fiber": 10}, "doorway": {"stick": 5, "fiber": 8}, "window": {"stick": 5, "fiber": 8}, "floor": {"stick": 10, "rope": 2}, "roof": {"stick": 8, "fiber": 12}},
		"wood": {"foundation": {"wood": 8}, "wall": {"plank": 6, "rope": 1}, "doorway": {"plank": 5, "rope": 1}, "window": {"plank": 5, "rope": 1}, "floor": {"plank": 6}, "roof": {"plank": 6, "rope": 2}, "stairs": {"plank": 8}},
		"stone": {"foundation": {"stone": 12}, "wall": {"stone": 10, "clay": 2}, "doorway": {"stone": 8, "clay": 2}, "window": {"stone": 8, "clay": 2}, "floor": {"stone": 10, "wood": 2}, "roof": {"stone": 10, "plank": 2}, "stairs": {"stone": 12}},
		"brick": {"wall": {"brick": 10, "clay": 2}, "doorway": {"brick": 8, "clay": 2}, "window": {"brick": 8, "glass": 1}, "floor": {"brick": 10, "plank": 2}, "roof": {"brick": 10, "plank": 2}},
	}
	var names := {"foundation": "أساس", "wall": "جدار", "doorway": "جدار بمدخل", "window": "جدار بنافذة", "floor": "أرضية/سقف", "roof": "سقف مائل", "stairs": "درج"}
	var slots := {"foundation": "cell", "floor": "cell", "wall": "edge", "doorway": "edge", "window": "edge", "roof": "roof", "stairs": "stairs"}
	for m in mats:
		for part in mats[m]:
			var id: String = "%s_%s" % [m, part]
			var hp: float = MAT_HP[m] * (1.6 if part == "foundation" else 1.0)
			_p(id, "%s %s" % [names[part], MAT_NAMES[m]], "structure", "grid", mats[m][part],
				{"slot": slots[part], "mat": m, "part": part, "hp": hp, "insul": MAT_INSUL[m]})
	_p("wooden_door", "باب خشبي", "structure", "grid", {"plank": 4, "rope": 1}, {"slot": "door", "mat": "wood", "part": "door", "hp": 250.0, "lockable": true, "desc": "يُوضع في جدار بمدخل. يمكن قفله بقفل حديدي."})
	_p("reinforced_door", "باب مدعّم", "structure", "grid", {"plank": 4, "iron_ingot": 2, "nails": 6}, {"slot": "door", "mat": "stone", "part": "door", "hp": 800.0, "lockable": true})
	# ------- محطات -------
	_p("campfire", "نار المخيم", "station", "free", {"stone": 5, "wood": 3}, {"station": "campfire", "size": Vector3(1.4, 0.6, 1.4), "hp": 150.0, "desc": "للطهي والتدفئة والإضاءة. أضف الحطب لإبقائها مشتعلة."})
	_p("workbench", "طاولة العمل", "station", "free", {"wood": 8, "rope": 2}, {"station": "workbench", "size": Vector3(2.0, 1.0, 1.0), "hp": 300.0})
	_p("furnace", "الفرن", "station", "free", {"stone": 20, "clay": 8}, {"station": "furnace", "size": Vector3(1.6, 2.0, 1.6), "hp": 700.0, "desc": "لصهر الخامات وصنع الزجاج والطوب."})
	_p("anvil", "السندان", "station", "free", {"stone": 15, "copper_ingot": 3}, {"station": "anvil", "size": Vector3(1.2, 1.0, 0.7), "hp": 900.0, "desc": "لصنع الأدوات والأسلحة المعدنية."})
	_p("loom", "النول", "station", "free", {"plank": 8, "rope": 6, "stick": 6}, {"station": "loom", "size": Vector3(1.6, 1.6, 1.2), "hp": 250.0})
	_p("tanning_rack", "رف الدباغة", "station", "free", {"stick": 10, "rope": 4, "wood": 2}, {"station": "tanning_rack", "size": Vector3(1.8, 1.8, 0.6), "hp": 200.0})
	_p("cooking_pot", "قدر الطهي", "station", "free", {"clay": 8, "stick": 4, "stone": 4}, {"station": "cooking_pot", "size": Vector3(1.2, 1.2, 1.2), "hp": 250.0, "desc": "لطبخ الوجبات المركبة والأدوية."})
	# ------- تخزين -------
	_p("wooden_chest", "صندوق خشبي", "storage", "free", {"wood": 10, "rope": 2}, {"slots": 20, "max_w": 250.0, "size": Vector3(1.2, 0.8, 0.7), "hp": 250.0, "desc": "تخزين بسيط. غير مقفل: قد يسرقه اللصوص إن لم يكن في غرفة مغلقة."})
	_p("large_chest", "صندوق كبير", "storage", "free", {"plank": 16, "nails": 10}, {"slots": 32, "max_w": 450.0, "size": Vector3(1.8, 0.9, 0.9), "hp": 400.0})
	_p("strongbox", "خزنة حديدية", "storage", "free", {"iron_ingot": 6, "nails": 10, "iron_lock": 1}, {"slots": 16, "max_w": 300.0, "locked": true, "size": Vector3(1.0, 0.9, 0.8), "hp": 1500.0, "desc": "مقفلة دائماً. أكثر الأماكن أماناً لممتلكاتك."})
	# ------- أثاث -------
	_p("bed_straw", "فراش قش", "furniture", "free", {"fiber": 20, "stick": 6}, {"bed": 0.7, "size": Vector3(1.0, 0.4, 2.1), "hp": 100.0, "desc": "للنوم وتحديد نقطة الإحياء."})
	_p("bed_wood", "سرير خشبي", "furniture", "free", {"plank": 10, "cloth": 4, "fur": 2}, {"bed": 1.0, "size": Vector3(1.2, 0.7, 2.2), "hp": 300.0, "desc": "نوم مريح ودافئ يعيد الطاقة أسرع."})
	_p("torch_stand", "مشعل ثابت", "furniture", "free", {"stick": 4, "fiber": 4, "stone": 2}, {"light": Color(1.0, 0.62, 0.3), "light_range": 9.0, "size": Vector3(0.4, 1.8, 0.4), "hp": 80.0})
	_p("crystal_lamp", "مصباح الكريستال", "furniture", "free", {"crystal": 2, "iron_ingot": 1}, {"light": Color(0.7, 0.75, 1.0), "light_range": 14.0, "size": Vector3(0.5, 1.6, 0.5), "hp": 300.0})
	_p("wooden_table", "طاولة خشبية", "furniture", "free", {"plank": 6}, {"size": Vector3(1.6, 0.85, 1.0), "hp": 150.0})
	_p("wooden_chair", "كرسي خشبي", "furniture", "free", {"plank": 3}, {"size": Vector3(0.55, 1.0, 0.55), "hp": 100.0})
	_p("rug", "سجادة", "furniture", "free", {"cloth": 4}, {"size": Vector3(2.0, 0.05, 1.4), "hp": 60.0, "walkable": true})
	# ------- زراعة ومياه -------
	_p("farm_plot", "حقل زراعي", "farming", "free", {"wood": 4, "stick": 4}, {"farm": true, "size": Vector3(2.0, 0.3, 2.0), "hp": 120.0, "walkable": true, "desc": "ازرع البذور واسقها بالماء. السماد (طعام فاسد) يسرّع النمو."})
	_p("water_collector", "مجمّع مياه الأمطار", "farming", "free", {"plank": 6, "cloth": 2}, {"collector": true, "size": Vector3(1.2, 1.2, 1.2), "hp": 150.0, "desc": "يجمع ماءً نظيفاً عند هطول المطر."})
	# ------- دفاع -------
	_p("wood_fence", "سياج خشبي", "defense", "free", {"stick": 6, "rope": 1}, {"size": Vector3(3.0, 1.4, 0.2), "hp": 150.0})
	_p("spikes", "أوتاد دفاعية", "defense", "free", {"wood": 4}, {"spikes": true, "size": Vector3(2.4, 1.0, 0.8), "hp": 200.0, "desc": "تؤذي الأعداء والحيوانات المفترسة التي تقترب."})
	_p("claim_flag", "راية الملكية", "defense", "free", {"cloth": 3, "stick": 3}, {"claim": 30.0, "size": Vector3(0.4, 3.2, 0.4), "hp": 200.0, "desc": "تعلن أرضك: تنبهك عند دخول الغرباء ويحترمها الأصدقاء."})
