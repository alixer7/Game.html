extends Node
## وصفات التصنيع. المفتاح الذي يبدأ بـ # يعني أي عنصر يحمل هذه العلامة (مثال: #fuel = أي وقود).

const STATION_NAMES := {
	"hand": "يدوي", "workbench": "طاولة العمل", "campfire": "نار المخيم", "furnace": "الفرن",
	"anvil": "السندان", "loom": "النول", "tanning_rack": "رف الدباغة", "cooking_pot": "قدر الطهي",
}
const CATS := ["tools", "weapons", "wear", "food", "materials", "medical"]
const CAT_NAMES := {"tools": "أدوات", "weapons": "أسلحة", "wear": "ملابس", "food": "طعام", "materials": "مواد", "medical": "طب"}
const TAG_NAMES := {"#fuel": "أي وقود", "#hotfuel": "فحم (حجري أو نباتي)"}

var recipes: Array = []

func _init() -> void:
	_define()

func _r(out: String, n: int, needs: Dictionary, station: String, time: float, cat: String, extra := {}) -> void:
	var r := {"id": "%s_%d" % [out, recipes.size()], "out": out, "n": n, "needs": needs, "station": station, "time": time, "cat": cat}
	for k in extra:
		r[k] = extra[k]
	recipes.append(r)

func need_name(key: String) -> String:
	if key.begins_with("#"):
		return TAG_NAMES.get(key, key)
	return ItemDB.name_of(key)

func _define() -> void:
	# يدوي
	_r("stick", 3, {"wood": 1}, "hand", 1.5, "materials")
	_r("rope", 1, {"fiber": 3}, "hand", 2.0, "materials")
	_r("rope", 1, {"reeds": 4}, "hand", 2.0, "materials")
	_r("stone_axe", 1, {"stone": 2, "stick": 2, "rope": 1}, "hand", 4.0, "tools")
	_r("stone_pickaxe", 1, {"stone": 3, "stick": 2, "rope": 1}, "hand", 4.0, "tools")
	_r("flint_knife", 1, {"flint": 2, "stick": 1, "fiber": 2}, "hand", 3.0, "tools")
	_r("hammer", 1, {"stone": 2, "stick": 2, "rope": 1}, "hand", 3.0, "tools")
	_r("torch", 1, {"stick": 1, "fiber": 3}, "hand", 2.0, "tools")
	_r("torch", 2, {"stick": 2, "resin": 1, "fiber": 1}, "hand", 2.0, "tools")
	_r("wooden_club", 1, {"wood": 2, "fiber": 2}, "hand", 3.0, "weapons")
	_r("wooden_spear", 1, {"wood": 1, "flint": 1, "fiber": 2}, "hand", 4.0, "weapons")
	_r("bandage", 1, {"fiber": 6, "herbs": 1}, "hand", 3.0, "medical")
	_r("bandage", 2, {"cloth": 1}, "hand", 2.0, "medical")
	_r("straw_hat", 1, {"reeds": 6, "fiber": 2}, "hand", 4.0, "wear")
	_r("straw_hat", 1, {"palm_leaf": 4, "fiber": 2}, "hand", 4.0, "wear")
	_r("fiber_backpack", 1, {"fiber": 20, "rope": 4, "stick": 4}, "hand", 8.0, "wear")
	_r("waterskin", 1, {"hide": 2, "rope": 1}, "hand", 5.0, "tools")
	_r("salted_meat", 1, {"raw_meat": 1, "salt": 1}, "hand", 3.0, "food")
	# طاولة العمل
	_r("plank", 2, {"wood": 1}, "workbench", 2.0, "materials")
	_r("bow", 1, {"wood": 1, "rope": 3}, "workbench", 6.0, "weapons")
	_r("arrow", 5, {"stick": 2, "flint": 1, "feather": 2}, "workbench", 4.0, "weapons")
	_r("obsidian_arrow", 5, {"stick": 2, "obsidian": 1, "feather": 2}, "workbench", 4.0, "weapons")
	_r("fishing_rod", 1, {"stick": 3, "rope": 2, "bone": 1}, "workbench", 5.0, "tools")
	_r("obsidian_knife", 1, {"obsidian": 2, "stick": 1, "leather": 1}, "workbench", 6.0, "tools")
	_r("obsidian_spear", 1, {"obsidian": 3, "wood": 1, "rope": 2}, "workbench", 7.0, "weapons")
	_r("leather_backpack", 1, {"leather": 6, "rope": 4, "bone": 2}, "workbench", 10.0, "wear")
	_r("leather_jacket", 1, {"leather": 5, "rope": 2}, "workbench", 8.0, "wear")
	_r("leather_pants", 1, {"leather": 4, "rope": 1}, "workbench", 7.0, "wear")
	_r("leather_boots", 1, {"leather": 2, "fiber": 4}, "workbench", 5.0, "wear")
	_r("fur_hat", 1, {"fur": 2, "rope": 1}, "workbench", 5.0, "wear")
	_r("fur_coat", 1, {"fur": 6, "leather": 2, "rope": 2}, "workbench", 10.0, "wear")
	_r("fur_boots", 1, {"fur": 2, "leather": 1}, "workbench", 5.0, "wear")
	# النول
	_r("cloth", 1, {"cotton": 4}, "loom", 3.0, "materials")
	_r("cloth", 1, {"fiber": 8}, "loom", 4.0, "materials")
	_r("cloth_shirt", 1, {"cloth": 4, "rope": 1}, "loom", 6.0, "wear")
	_r("cloth_pants", 1, {"cloth": 3}, "loom", 5.0, "wear")
	_r("desert_robe", 1, {"cloth": 6, "rope": 1}, "loom", 8.0, "wear")
	# رف الدباغة
	_r("leather", 1, {"hide": 1, "salt": 1}, "tanning_rack", 6.0, "materials")
	_r("leather", 1, {"hide": 2}, "tanning_rack", 10.0, "materials")
	# نار المخيم
	_r("cooked_meat", 1, {"raw_meat": 1}, "campfire", 6.0, "food")
	_r("cooked_fish", 1, {"raw_fish": 1}, "campfire", 5.0, "food")
	_r("baked_potato", 1, {"potato": 1}, "campfire", 5.0, "food")
	_r("bread", 1, {"wheat": 3}, "campfire", 8.0, "food")
	_r("waterskin_clean", 1, {"waterskin_dirty": 1}, "campfire", 6.0, "food")
	_r("waterskin_clean", 1, {"waterskin": 1, "ice": 2}, "campfire", 8.0, "food")
	_r("herbal_tea", 1, {"herbs": 2, "waterskin_clean": 1}, "campfire", 5.0, "medical", {"extra_out": {"waterskin": 1}})
	_r("charcoal", 1, {"wood": 2}, "campfire", 10.0, "materials")
	# قدر الطهي
	_r("stew", 1, {"raw_meat": 2, "potato": 2, "waterskin_clean": 1}, "cooking_pot", 12.0, "food", {"extra_out": {"waterskin": 1}})
	_r("mushroom_soup", 1, {"mushroom": 3, "waterskin_clean": 1}, "cooking_pot", 10.0, "food", {"extra_out": {"waterskin": 1}})
	_r("herbal_medicine", 1, {"herbs": 4, "waterskin_clean": 1}, "cooking_pot", 10.0, "medical", {"extra_out": {"waterskin": 1}})
	_r("antiseptic", 1, {"sulfur": 2, "herbs": 2, "fat": 1}, "cooking_pot", 10.0, "medical")
	# الفرن
	_r("charcoal", 3, {"wood": 3}, "furnace", 8.0, "materials")
	_r("copper_ingot", 1, {"copper_ore": 2, "#fuel": 1}, "furnace", 8.0, "materials")
	_r("tin_ingot", 1, {"tin_ore": 2, "#fuel": 1}, "furnace", 8.0, "materials")
	_r("bronze_ingot", 3, {"copper_ingot": 2, "tin_ingot": 1, "#fuel": 1}, "furnace", 10.0, "materials")
	_r("iron_ingot", 1, {"iron_ore": 2, "#hotfuel": 1}, "furnace", 12.0, "materials")
	_r("steel_ingot", 1, {"iron_ingot": 2, "#hotfuel": 2}, "furnace", 16.0, "materials")
	_r("gold_ingot", 1, {"gold_ore": 2, "#hotfuel": 1}, "furnace", 12.0, "materials")
	_r("glass", 2, {"sand": 3, "#fuel": 1}, "furnace", 8.0, "materials")
	_r("brick", 3, {"clay": 3, "#fuel": 1}, "furnace", 8.0, "materials")
	# السندان
	_r("nails", 20, {"iron_ingot": 1}, "anvil", 5.0, "materials")
	_r("iron_lock", 1, {"iron_ingot": 2}, "anvil", 8.0, "tools")
	_r("bronze_axe", 1, {"bronze_ingot": 3, "wood": 1, "leather": 1}, "anvil", 10.0, "tools")
	_r("bronze_pickaxe", 1, {"bronze_ingot": 3, "wood": 1, "leather": 1}, "anvil", 10.0, "tools")
	_r("bronze_sword", 1, {"bronze_ingot": 4, "leather": 1}, "anvil", 12.0, "weapons")
	_r("bronze_armor", 1, {"bronze_ingot": 10, "leather": 4}, "anvil", 20.0, "wear")
	_r("iron_axe", 1, {"iron_ingot": 3, "hardwood": 1, "leather": 1}, "anvil", 12.0, "tools")
	_r("iron_pickaxe", 1, {"iron_ingot": 3, "hardwood": 1, "leather": 1}, "anvil", 12.0, "tools")
	_r("iron_sword", 1, {"iron_ingot": 4, "hardwood": 1, "leather": 1}, "anvil", 14.0, "weapons")
	_r("iron_armor", 1, {"iron_ingot": 12, "leather": 4}, "anvil", 24.0, "wear")
	_r("steel_sword", 1, {"steel_ingot": 4, "hardwood": 1, "leather": 2}, "anvil", 16.0, "weapons")
	_r("steel_pickaxe", 1, {"steel_ingot": 3, "hardwood": 1, "leather": 1}, "anvil", 16.0, "tools")
	_r("gold_coin", 15, {"gold_ingot": 1}, "anvil", 6.0, "materials")
	_r("gem_amulet", 1, {"gemstone": 2, "gold_ingot": 1}, "anvil", 14.0, "materials")
