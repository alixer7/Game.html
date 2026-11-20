extends Node
## أنواع الموارد الطبيعية في العالم وتوزيعها حسب البيئة.

# أرقام البيئات (مطابقة لـ WorldGen)
const OCEAN := 0
const BEACH := 1
const PLAINS := 2
const FOREST := 3
const SWAMP := 4
const DESERT := 5
const TAIGA := 6
const TUNDRA := 7
const MOUNTAIN := 8
const SNOW := 9
const VOLCANIC := 10

var types := {}
var scatter := {}
## كثافة العشب لكل بيئة (0..1)
var grass_density := {OCEAN: 0.0, BEACH: 0.08, PLAINS: 1.0, FOREST: 0.7, SWAMP: 0.8, DESERT: 0.03, TAIGA: 0.45, TUNDRA: 0.12, MOUNTAIN: 0.2, SNOW: 0.0, VOLCANIC: 0.02}

func _init() -> void:
	_define()

func _t(id: String, nm: String, extra: Dictionary) -> void:
	var t := {"id": id, "name": nm, "mesh": id, "hp": 1.0, "tool": "", "tier": 0, "yields": [], "regrow": 48.0,
		"block": false, "col_r": 0.4, "col_h": 1.0, "scale": [0.85, 1.15], "verb": "اجمع", "hurt": 0.0, "fall": false, "sfx": "gather", "skill": "gathering"}
	for k in extra:
		t[k] = extra[k]
	types[id] = t

func get_type(id: String) -> Dictionary:
	return types.get(id, {})

func _define() -> void:
	var tree := {"tool": "axe", "tier": 1, "block": true, "col_r": 0.4, "col_h": 6.0, "verb": "اقطع", "fall": true, "sfx": "chop", "regrow": 96.0, "skill": "woodcutting"}
	var rock := {"tool": "pickaxe", "tier": 1, "block": true, "col_r": 1.0, "col_h": 1.6, "verb": "اكسر", "sfx": "mine", "regrow": 160.0, "skill": "mining"}
	_t("oak", "شجرة بلوط", _m(tree, {"hp": 60.0, "yields": [["wood", 4, 6, 1.0], ["stick", 1, 3, 1.0]], "scale": [0.8, 1.3]}))
	_t("big_oak", "بلوطة معمّرة", _m(tree, {"hp": 170.0, "tier": 2, "col_r": 0.8, "yields": [["hardwood", 3, 5, 1.0], ["wood", 4, 7, 1.0]], "scale": [1.0, 1.25]}))
	_t("birch", "شجرة بتولا", _m(tree, {"hp": 50.0, "col_r": 0.3, "yields": [["wood", 3, 5, 1.0], ["stick", 1, 2, 1.0]], "scale": [0.85, 1.25]}))
	_t("pine", "شجرة صنوبر", _m(tree, {"hp": 60.0, "col_r": 0.35, "yields": [["wood", 3, 5, 1.0], ["resin", 1, 2, 0.6]], "scale": [0.8, 1.35]}))
	_t("palm", "نخلة", _m(tree, {"hp": 45.0, "col_r": 0.3, "yields": [["wood", 2, 3, 1.0], ["palm_leaf", 2, 4, 1.0], ["coconut", 1, 2, 0.6]], "scale": [0.85, 1.2]}))
	_t("dead_tree", "شجرة يابسة", _m(tree, {"hp": 30.0, "col_r": 0.3, "yields": [["wood", 1, 3, 1.0], ["stick", 2, 4, 1.0]], "scale": [0.8, 1.2]}))
	_t("bush", "شجيرة", {"yields": [["fiber", 2, 4, 1.0], ["stick", 1, 2, 0.8]], "regrow": 30.0, "col_r": 0.6, "col_h": 1.0})
	_t("berry_bush", "شجيرة توت", {"yields": [["berries", 3, 6, 1.0], ["fiber", 1, 2, 0.6]], "regrow": 36.0, "col_r": 0.6, "col_h": 1.0, "verb": "اقطف"})
	_t("tall_grass", "عشب طويل", {"yields": [["fiber", 2, 3, 1.0], ["wheat_seed", 1, 2, 0.3]], "regrow": 24.0, "col_r": 0.4, "col_h": 0.8})
	_t("cotton", "نبتة قطن", {"yields": [["cotton", 2, 4, 1.0], ["cotton_seed", 1, 1, 0.35]], "regrow": 48.0, "col_r": 0.4, "col_h": 0.9, "verb": "اقطف"})
	_t("potato_plant", "بطاطا برية", {"yields": [["potato", 1, 3, 1.0]], "regrow": 60.0, "col_r": 0.4, "col_h": 0.5, "verb": "اقلع"})
	_t("herb", "أعشاب طبية", {"yields": [["herbs", 1, 3, 1.0]], "regrow": 40.0, "col_r": 0.35, "col_h": 0.5, "verb": "اقطف"})
	_t("mushroom", "فطر", {"yields": [["mushroom", 1, 2, 1.0]], "regrow": 36.0, "col_r": 0.3, "col_h": 0.4, "verb": "اقطف"})
	_t("toadstool", "فطر أحمر", {"yields": [["toadstool", 1, 2, 1.0]], "regrow": 36.0, "col_r": 0.3, "col_h": 0.4, "verb": "اقطف"})
	_t("reeds", "قصب", {"yields": [["reeds", 3, 5, 1.0], ["fiber", 1, 1, 0.5]], "regrow": 30.0, "col_r": 0.5, "col_h": 1.8})
	_t("cactus", "صبّار", {"yields": [["cactus_fruit", 1, 2, 1.0], ["fiber", 1, 2, 0.5]], "regrow": 48.0, "block": true, "col_r": 0.35, "col_h": 3.0, "hurt": 3.0, "verb": "اقطف"})
	_t("rock_small", "حجارة", {"yields": [["stone", 1, 2, 1.0], ["flint", 1, 1, 0.3]], "regrow": 72.0, "col_r": 0.35, "col_h": 0.4, "verb": "التقط"})
	_t("flint_stone", "حجر صوان", {"yields": [["flint", 1, 2, 1.0]], "regrow": 72.0, "col_r": 0.3, "col_h": 0.4, "verb": "التقط"})
	_t("sticks", "أغصان متساقطة", {"yields": [["stick", 2, 3, 1.0]], "regrow": 30.0, "col_r": 0.5, "col_h": 0.3, "verb": "التقط"})
	_t("boulder", "صخرة", _m(rock, {"hp": 80.0, "yields": [["stone", 4, 7, 1.0], ["flint", 1, 2, 0.5]]}))
	_t("copper", "عرق نحاس", _m(rock, {"hp": 100.0, "yields": [["copper_ore", 2, 4, 1.0], ["stone", 1, 2, 1.0]]}))
	_t("tin", "عرق قصدير", _m(rock, {"hp": 100.0, "yields": [["tin_ore", 2, 4, 1.0], ["stone", 1, 2, 1.0]]}))
	_t("coal", "عرق فحم", _m(rock, {"hp": 90.0, "yields": [["coal", 2, 4, 1.0], ["stone", 1, 1, 1.0]]}))
	_t("iron", "عرق حديد", _m(rock, {"hp": 140.0, "tier": 2, "yields": [["iron_ore", 2, 4, 1.0], ["stone", 1, 2, 1.0]]}))
	_t("gold", "عرق ذهب", _m(rock, {"hp": 160.0, "tier": 2, "yields": [["gold_ore", 1, 3, 1.0], ["stone", 1, 1, 1.0]], "regrow": 300.0}))
	_t("crystal", "بلّورات", _m(rock, {"hp": 120.0, "tier": 3, "col_r": 0.7, "yields": [["crystal", 1, 3, 1.0]], "regrow": 400.0}))
	_t("gem", "صخرة الجواهر", _m(rock, {"hp": 180.0, "tier": 3, "yields": [["gemstone", 1, 2, 1.0], ["stone", 2, 3, 1.0]], "regrow": 600.0}))
	_t("obsidian", "صخرة سبج", _m(rock, {"hp": 120.0, "tier": 2, "yields": [["obsidian", 2, 4, 1.0]]}))
	_t("sulfur", "رواسب كبريت", _m(rock, {"hp": 70.0, "yields": [["sulfur", 2, 4, 1.0], ["stone", 1, 1, 0.6]]}))
	_t("salt", "رواسب ملح", _m(rock, {"hp": 60.0, "col_r": 0.8, "col_h": 0.8, "yields": [["salt", 2, 4, 1.0]], "regrow": 120.0}))
	_t("ice_block", "كتلة جليد", _m(rock, {"hp": 40.0, "col_r": 0.8, "yields": [["ice", 2, 4, 1.0]], "regrow": 96.0}))
	_t("clay_pit", "طين", {"yields": [["clay", 2, 3, 1.0]], "regrow": 48.0, "col_r": 0.8, "col_h": 0.4})
	_t("sand_pile", "كومة رمل", {"yields": [["sand", 2, 4, 1.0]], "regrow": 48.0, "col_r": 0.8, "col_h": 0.4})
	_t("beehive", "خلية نحل", {"yields": [["honey", 1, 2, 1.0]], "regrow": 96.0, "block": true, "col_r": 0.5, "col_h": 1.6, "hurt": 8.0, "verb": "اجنِ العسل"})

	# جداول التوزيع: عدد المحاولات لكل قطعة أرض 64×64 م، والأوزان
	scatter[PLAINS] = {"n": 46, "w": [["oak", 6], ["bush", 6], ["berry_bush", 3], ["tall_grass", 12], ["rock_small", 5], ["cotton", 4], ["potato_plant", 2], ["flint_stone", 2], ["boulder", 2], ["sticks", 2], ["herb", 1]]}
	scatter[FOREST] = {"n": 72, "w": [["oak", 18], ["birch", 12], ["big_oak", 1.5], ["bush", 6], ["berry_bush", 4], ["mushroom", 4], ["toadstool", 1.5], ["herb", 3], ["rock_small", 3], ["boulder", 2], ["sticks", 5], ["beehive", 0.6], ["coal", 0.4]]}
	scatter[TAIGA] = {"n": 64, "w": [["pine", 30], ["bush", 3], ["rock_small", 3], ["boulder", 4], ["mushroom", 2], ["berry_bush", 1.5], ["sticks", 3], ["iron", 0.8], ["coal", 0.5]]}
	scatter[TUNDRA] = {"n": 28, "w": [["dead_tree", 3], ["pine", 4], ["ice_block", 4], ["rock_small", 4], ["boulder", 4], ["iron", 1], ["crystal", 0.2]]}
	scatter[SNOW] = {"n": 22, "w": [["ice_block", 5], ["boulder", 6], ["crystal", 0.9], ["iron", 1.2], ["gem", 0.12], ["pine", 1]]}
	scatter[MOUNTAIN] = {"n": 40, "w": [["boulder", 10], ["rock_small", 5], ["copper", 3], ["tin", 2], ["iron", 2.2], ["coal", 3], ["gold", 0.35], ["pine", 2.5], ["crystal", 0.25], ["flint_stone", 2]]}
	scatter[DESERT] = {"n": 28, "w": [["cactus", 8], ["dead_tree", 2], ["palm", 0.8], ["sand_pile", 4], ["rock_small", 4], ["boulder", 2], ["salt", 2], ["gold", 0.5], ["copper", 1]]}
	scatter[BEACH] = {"n": 24, "w": [["palm", 6], ["sand_pile", 5], ["rock_small", 3], ["salt", 1.2], ["flint_stone", 2], ["reeds", 1], ["sticks", 1]]}
	scatter[SWAMP] = {"n": 54, "w": [["dead_tree", 6], ["oak", 4], ["reeds", 10], ["clay_pit", 5], ["herb", 5], ["mushroom", 4], ["toadstool", 3], ["bush", 3], ["sticks", 2]]}
	scatter[VOLCANIC] = {"n": 30, "w": [["obsidian", 3], ["sulfur", 3], ["boulder", 5], ["dead_tree", 2], ["coal", 2], ["rock_small", 3]]}

func _m(a: Dictionary, b: Dictionary) -> Dictionary:
	var r := a.duplicate(true)
	for k in b:
		r[k] = b[k]
	return r

func pick(biome: int, roll: float) -> String:
	if not scatter.has(biome):
		return ""
	var list: Array = scatter[biome]["w"]
	var total := 0.0
	for e in list:
		total += e[1]
	var x := roll * total
	for e in list:
		x -= e[1]
		if x <= 0.0:
			return e[0]
	return list[list.size() - 1][0]
