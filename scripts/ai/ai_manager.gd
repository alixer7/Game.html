class_name AIManager
extends Node3D
## مدير الذكاء الاصطناعي: المستوطنات، الشخصيات، شبكة العلاقات، النميمة، السرقة، الحوار، تفعيل/إخفاء الكائنات حسب المسافة.

const ACTIVE_R := 105.0
const DESPAWN_R := 140.0

const MALE := ["أحمد", "محمد", "سالم", "خالد", "عمر", "يوسف", "علي", "حسن", "كريم", "طارق", "ماجد", "فهد", "سامي", "رامي", "نادر", "زياد", "هاني", "وليد", "بشير", "جمال", "منصور", "راشد", "صالح", "عادل", "فارس", "ياسر", "حمزة", "إبراهيم", "مالك", "سعيد", "قاسم", "عيسى", "مراد", "جابر"]
const FEMALE := ["فاطمة", "مريم", "ليلى", "سارة", "نور", "هدى", "سلمى", "رنا", "دينا", "أمل", "ريم", "لينا", "جميلة", "زينب", "خديجة", "سعاد", "هالة", "منى", "رشا", "يارا", "شهد", "وفاء", "نادية", "سهى"]
const ROLE_NAMES := {"farmer": "مزارع", "hunter": "صياد", "woodcutter": "حطّاب", "miner": "عامل منجم", "trader": "تاجر", "guard": "حارس", "bandit": "قاطع طريق", "thief": "لص", "wanderer": "رحّالة", "healer": "معالج أعشاب", "elder": "شيخ", "smith": "حدّاد"}
const ROLE_NAMES_F := {"farmer": "مزارعة", "hunter": "صيادة", "woodcutter": "حطّابة", "miner": "عاملة منجم", "trader": "تاجرة", "guard": "حارسة", "bandit": "قاطعة طريق", "thief": "لصّة", "wanderer": "رحّالة", "healer": "معالجة أعشاب", "elder": "شيخة", "smith": "حدّادة"}
const TRAIT_NAMES := {"kind": ["قاسٍ", "طيب القلب"], "aggr": ["مسالم", "عدواني"], "greed": ["كريم", "جشع"], "honest": ["مخادع", "أمين"], "brave": ["جبان", "شجاع"], "social": ["انطوائي", "اجتماعي"]}

var world: Node
var npcs := {}
var active_npcs: Array = []
var animals: Array = []
var settlements: Array = []
var rel := {}
var known_rel := {}
var journal: Array = []
var markers: Array = []
var _next_id := 0
var _social_t := 0.0
var _sim_t := 0.0
var _spawn_t := 0.0
var _daily_day := -1
var _animal_t := 0.0
var max_animals := 18
var rng := RandomNumberGenerator.new()
var _npc_script = preload("res://scripts/ai/npc.gd")

func setup(w: Node, quality: int) -> void:
	world = w
	max_animals = [10, 16, 22][quality]
	rng.seed = w.seed_value * 13 + 5

# ------------------------------------------------------------------
# إنشاء العالم الاجتماعي
func generate() -> void:
	var gen: WorldGen = world.gen
	var defs := [
		{"name": "قرية الوادي الأخضر", "type": "village", "biomes": [WorldGen.PLAINS, WorldGen.FOREST], "roles": ["elder", "farmer", "farmer", "guard", "healer", "woodcutter"], "attitude": 8.0, "min": 120.0, "max": 380.0},
		{"name": "مخيم صيادي الغابة", "type": "camp", "biomes": [WorldGen.FOREST], "roles": ["hunter", "hunter", "woodcutter", "healer", "wanderer"], "attitude": 0.0, "min": 200.0, "max": 700.0},
		{"name": "واحة التجار", "type": "oasis", "biomes": [WorldGen.DESERT], "roles": ["trader", "trader", "guard", "healer", "elder"], "attitude": 4.0, "min": 200.0, "max": 950.0},
		{"name": "عشيرة الشمال", "type": "north", "biomes": [WorldGen.TAIGA, WorldGen.TUNDRA], "roles": ["elder", "hunter", "hunter", "woodcutter", "guard"], "attitude": -6.0, "min": 250.0, "max": 950.0},
		{"name": "معسكر المنقّبين", "type": "mine", "biomes": [WorldGen.MOUNTAIN], "roles": ["miner", "miner", "smith", "guard"], "attitude": -2.0, "min": 150.0, "max": 950.0},
		{"name": "وكر الذئاب السود", "type": "bandit", "biomes": [WorldGen.FOREST, WorldGen.PLAINS, WorldGen.SWAMP, WorldGen.TAIGA], "roles": ["bandit", "bandit", "bandit", "bandit", "bandit"], "attitude": -70.0, "min": 380.0, "max": 950.0, "hostile": true},
	]
	var avoid := [world.spawn_point]
	for i in range(defs.size()):
		var d: Dictionary = defs[i]
		var p := gen.find_site(d["biomes"], avoid, 260.0 if i > 0 else 200.0, rng, d["min"], d["max"])
		if p == Vector3.INF:
			p = gen.find_site([WorldGen.PLAINS, WorldGen.FOREST, WorldGen.TAIGA, WorldGen.DESERT], avoid, 200.0, rng, 150.0, 950.0)
		if p == Vector3.INF:
			continue
		avoid.append(p)
		var s := {"id": "s%d" % i, "name": d["name"], "type": d["type"], "pos": p, "radius": 24.0, "hostile": d.get("hostile", false), "discovered": false, "attitude": d["attitude"]}
		settlements.append(s)
		gen.clear_zones.append(Vector3(p.x, p.z, 30.0))
		for r in d["roles"]:
			_create_npc(r, s)
	# رحالة بلا مستوطنة
	for r in ["thief", "wanderer", "trader", "thief"]:
		_create_npc(r, {})
	_init_relationships()

func _create_npc(role: String, s: Dictionary) -> Dictionary:
	var female := rng.randf() < (0.15 if role in ["bandit", "guard", "miner"] else 0.45)
	var nm: String = FEMALE[rng.randi() % FEMALE.size()] if female else MALE[rng.randi() % MALE.size()]
	var t := {"kind": rng.randf(), "aggr": rng.randf() * 0.7, "greed": rng.randf(), "honest": rng.randf_range(0.3, 1.0), "brave": rng.randf(), "social": rng.randf()}
	match role:
		"bandit":
			t["aggr"] = rng.randf_range(0.6, 1.0); t["kind"] = rng.randf_range(0.0, 0.4); t["honest"] = rng.randf_range(0.0, 0.4); t["brave"] = rng.randf_range(0.5, 1.0)
		"thief":
			t["greed"] = rng.randf_range(0.7, 1.0); t["honest"] = rng.randf_range(0.0, 0.25); t["brave"] = rng.randf_range(0.1, 0.5); t["social"] = rng.randf_range(0.5, 1.0)
		"guard":
			t["brave"] = rng.randf_range(0.65, 1.0); t["honest"] = rng.randf_range(0.5, 1.0)
		"trader":
			t["greed"] = rng.randf_range(0.4, 0.9); t["social"] = rng.randf_range(0.6, 1.0)
		"healer", "elder":
			t["kind"] = rng.randf_range(0.5, 1.0); t["aggr"] = rng.randf_range(0.0, 0.3)
	var home: Vector3 = s.get("pos", world.spawn_point + Vector3(rng.randf_range(-300, 300), 0, rng.randf_range(-300, 300)))
	home += Vector3(rng.randf_range(-12, 12), 0, rng.randf_range(-12, 12))
	home.y = world.gen.height_at(home.x, home.z)
	if home.y < 0.5 and s.is_empty():
		home = world.spawn_point + Vector3(rng.randf_range(-80, 80), 0, rng.randf_range(-80, 80))
		home.y = world.gen.height_at(home.x, home.z)
	var id := "n%d" % _next_id
	_next_id += 1
	var inv := Inventory.new(12)
	_stock(inv, role, true)
	var weapon := {"bandit": "bronze_sword", "guard": "iron_sword", "hunter": "wooden_spear", "woodcutter": "stone_axe", "miner": "stone_pickaxe", "smith": "bronze_axe", "thief": "flint_knife"}.get(role, "")
	if role == "bandit" and rng.randf() < 0.5:
		weapon = "wooden_club" if rng.randf() < 0.5 else "obsidian_spear"
	var d := {
		"id": id, "name": nm, "female": female, "role": role, "faction": s.get("id", ""),
		"traits": t, "home": home, "pos": home, "hp": 100.0, "max_hp": 100.0 + (30.0 if role in ["guard", "bandit"] else 0.0),
		"inv": inv, "app": HumanModel.random_appearance(rng, female), "alive": true,
		"companion": false, "order": "follow", "guard_pos": Vector3.ZERO, "met": false, "talks_day": -1, "talks": 0,
		"known_traits": [], "memory": [], "stolen": [], "weapon": weapon, "exposed": false,
		"sleep_at": rng.randf_range(20.5, 23.0), "wake_at": rng.randf_range(5.2, 7.0), "gifts_day": -1, "gifts": 0,
		"travel_to": Vector3.INF, "info_given": 0,
	}
	if role == "bandit":
		d["app"]["shirt"] = Color(0.18, 0.16, 0.15)
		d["app"]["pants"] = Color(0.15, 0.13, 0.12)
	if role == "guard":
		d["app"]["shirt"] = Color(0.45, 0.4, 0.3)
	npcs[id] = d
	rel[id] = {}
	return d

func _stock(inv: Inventory, role: String, initial: bool) -> void:
	var table := {
		"farmer": [["wheat", 4, 10], ["potato", 3, 8], ["bread", 1, 3], ["wheat_seed", 3, 8], ["cotton_seed", 1, 4], ["berries", 2, 6]],
		"hunter": [["raw_meat", 2, 5], ["hide", 1, 3], ["fur", 0, 2], ["arrow", 5, 15], ["bone", 1, 3], ["feather", 3, 8]],
		"woodcutter": [["wood", 8, 20], ["plank", 2, 8], ["stick", 5, 15], ["resin", 1, 3]],
		"miner": [["stone", 8, 20], ["copper_ore", 2, 6], ["tin_ore", 1, 4], ["iron_ore", 1, 4], ["coal", 2, 6]],
		"smith": [["copper_ingot", 1, 4], ["iron_ingot", 1, 3], ["nails", 10, 30], ["bronze_axe", 0, 1], ["bronze_pickaxe", 0, 1], ["iron_lock", 0, 1]],
		"trader": [["gold_coin", 10, 40], ["cloth", 2, 6], ["salt", 2, 6], ["glass", 1, 4], ["leather", 1, 4], ["rope", 3, 8], ["iron_ingot", 0, 2], ["waterskin", 0, 1], ["gemstone", 0, 1], ["crystal", 0, 1], ["fishing_rod", 0, 1], ["bow", 0, 1]],
		"healer": [["herbs", 3, 8], ["bandage", 2, 5], ["herbal_medicine", 1, 3], ["herbal_tea", 0, 2], ["antiseptic", 0, 1], ["honey", 0, 2]],
		"elder": [["gold_coin", 5, 20], ["salted_meat", 1, 3], ["cloth", 1, 3], ["honey", 0, 2]],
		"guard": [["cooked_meat", 1, 3], ["bandage", 1, 3], ["gold_coin", 2, 10]],
		"bandit": [["gold_coin", 5, 25], ["cooked_meat", 1, 2], ["iron_ingot", 0, 2], ["bandage", 0, 2], ["leather", 0, 2], ["gemstone", 0, 1]],
		"thief": [["gold_coin", 3, 15], ["berries", 1, 4], ["gemstone", 0, 1]],
		"wanderer": [["salted_meat", 1, 2], ["rope", 1, 3], ["waterskin_clean", 0, 1], ["gold_coin", 2, 8], ["crystal", 0, 1]],
	}
	for e in table.get(role, []):
		if not ItemDB.exists(e[0]):
			continue
		var n := rng.randi_range(e[1], e[2])
		if not initial:
			n = int(n * 0.5)
		if n > 0 and inv.count(e[0]) < e[2]:
			inv.add(e[0], n)

func _init_relationships() -> void:
	var ids := npcs.keys()
	for a in ids:
		var da: Dictionary = npcs[a]
		for b in ids:
			if a == b:
				continue
			var db: Dictionary = npcs[b]
			var v := rng.randf_range(-10.0, 15.0)
			if da["faction"] != "" and da["faction"] == db["faction"]:
				v = rng.randf_range(15.0, 60.0) if rng.randf() > 0.2 else rng.randf_range(-45.0, -10.0)
			if da["role"] == "bandit" and db["role"] != "bandit":
				v = rng.randf_range(-60.0, -25.0)
			if db["role"] == "bandit" and da["role"] != "bandit":
				v = rng.randf_range(-70.0, -35.0)
			v += (_compat(da, db) - 0.5) * 20.0
			rel[a][b] = clampf(v, -100.0, 100.0)
		var att := 0.0
		for s in settlements:
			if s["id"] == da["faction"]:
				att = s["attitude"]
		rel[a]["player"] = clampf(att + (da["traits"]["kind"] - 0.5) * 24.0 + rng.randf_range(-6, 6), -100.0, 100.0)

func _compat(a: Dictionary, b: Dictionary) -> float:
	var ta: Dictionary = a["traits"]
	var tb: Dictionary = b["traits"]
	return clampf(1.0 - absf(ta["kind"] - tb["kind"]) * 0.5 - absf(ta["aggr"] - tb["aggr"]) * 0.35 - absf(ta["honest"] - tb["honest"]) * 0.3 + 0.15, 0.0, 1.0)

# ------------------------------------------------------------------
# العلاقات
func get_rel(a: String, b: String) -> float:
	if a == "player":
		return 0.0
	return rel.get(a, {}).get(b, 0.0)

func add_rel(a: String, b: String, d: float) -> void:
	if a == "player" or not rel.has(a):
		return
	var v: float = rel[a].get(b, 0.0)
	rel[a][b] = clampf(v + d, -100.0, 100.0)
	if b == "player" and npcs.has(a):
		var n = npcs[a]
		if n["companion"] and rel[a]["player"] < 15.0:
			n["companion"] = false
			log_event("%s تخلّى عنك ولم يعد رفيقك" % n["name"])
			Game.notify("%s غاضب منك وترك صحبتك" % n["name"], Color(1, 0.5, 0.4))

static func rel_label(v: float) -> String:
	if v <= -60: return "عدو لدود"
	if v <= -25: return "عدو"
	if v <= -6: return "غير ودود"
	if v < 15: return "محايد"
	if v < 40: return "ودود"
	if v < 70: return "صديق"
	return "صديق مقرّب"

static func rel_color(v: float) -> Color:
	if v <= -25: return Color(1.0, 0.35, 0.3)
	if v <= -6: return Color(1.0, 0.65, 0.4)
	if v < 15: return Color(0.9, 0.9, 0.85)
	if v < 40: return Color(0.6, 0.9, 0.55)
	return Color(0.4, 1.0, 0.6)

func role_name(d: Dictionary, as_known := true) -> String:
	var r: String = d["role"]
	if r == "thief" and as_known and not d.get("exposed", false):
		r = "wanderer"
	return (ROLE_NAMES_F if d["female"] else ROLE_NAMES).get(r, r)

func display_name(d: Dictionary) -> String:
	return "%s (%s)" % [d["name"], role_name(d)]

func settlement_of(d: Dictionary) -> Dictionary:
	for s in settlements:
		if s["id"] == d["faction"]:
			return s
	return {}

func remember(id: String, what: String, who: String) -> void:
	if not npcs.has(id):
		return
	var m: Array = npcs[id]["memory"]
	m.append({"t": world.total_hours(), "what": what, "who": who})
	if m.size() > 12:
		m.pop_front()

func log_event(text: String) -> void:
	journal.append("[%s] %s" % [world.sky.clock_text(), text])
	if journal.size() > 80:
		journal.pop_front()

func reputation(sid: String) -> float:
	var total := 0.0
	var n := 0
	for id in npcs:
		var d: Dictionary = npcs[id]
		if d["alive"] and d["faction"] == sid:
			total += get_rel(id, "player")
			n += 1
	return total / n if n > 0 else 0.0

## شهود على حدث قريب: يغيرون رأيهم في الفاعل
func witness(pos: Vector3, actor: String, victim: String, severity: float, what: String, radius := 30.0) -> Array:
	var seen := []
	for n in active_npcs:
		if not is_instance_valid(n) or n.dead or n.npc_id == actor or n.npc_id == victim:
			continue
		if n.global_position.distance_to(pos) > radius:
			continue
		if n.state == "sleep" and randf() < 0.7:
			continue
		var d: Dictionary = n.data
		var care := 0.5
		if victim != "" and victim != "player":
			care = clampf(0.4 + get_rel(n.npc_id, victim) / 100.0, 0.0, 1.0)
		elif victim == "player":
			care = clampf(0.3 + get_rel(n.npc_id, "player") / 100.0, 0.0, 1.0)
		add_rel(n.npc_id, actor, -severity * (0.4 + care) * (0.5 + d["traits"]["honest"] * 0.6))
		remember(n.npc_id, what, actor)
		seen.append(n)
	return seen

# ------------------------------------------------------------------
# الحلقة الرئيسية
func tick(dt: float) -> void:
	var p: Node3D = world.player
	if p == null:
		return
	_spawn_t -= dt
	if _spawn_t <= 0.0:
		_spawn_t = 1.0
		_update_npc_presence(p.global_position)
		_discover(p.global_position)
	_animal_t -= dt
	if _animal_t <= 0.0:
		_animal_t = 2.0
		_update_animals(p.global_position)
	_sim_t -= dt
	if _sim_t <= 0.0:
		_sim_t = 6.0
		_far_sim(6.0)
	_social_t -= dt
	if _social_t <= 0.0:
		_social_t = 12.0
		_far_social()
	var dd: int = world.sky.day()
	if dd != _daily_day:
		if _daily_day != -1:
			_daily(dd)
		_daily_day = dd

func _update_npc_presence(ppos: Vector3) -> void:
	for id in npcs:
		var d: Dictionary = npcs[id]
		if not d["alive"]:
			continue
		var pos: Vector3 = d["pos"]
		var node = d.get("_node")
		var dist := Vector2(pos.x - ppos.x, pos.z - ppos.z).length()
		if node == null or not is_instance_valid(node):
			if dist < ACTIVE_R and world.terrain.chunks.has(world.terrain.chunk_of(pos)):
				_spawn_npc(d)
		else:
			d["pos"] = node.global_position
			if Vector2(node.global_position.x - ppos.x, node.global_position.z - ppos.z).length() > DESPAWN_R and not d["companion"]:
				d["hp"] = node.hp
				active_npcs.erase(node)
				node.queue_free()
				d.erase("_node")

func _spawn_npc(d: Dictionary) -> void:
	var n: CharacterBody3D = _npc_script.new()
	add_child(n)
	var pos: Vector3 = d["pos"]
	pos.y = world.gen.height_at(pos.x, pos.z) + 0.3
	n.setup(world, d, pos)
	d["_node"] = n
	active_npcs.append(n)

func _discover(ppos: Vector3) -> void:
	for s in settlements:
		if not s["discovered"] and ppos.distance_to(s["pos"]) < 70.0:
			s["discovered"] = true
			Game.notify("اكتشفت: %s" % s["name"], Color(1, 0.9, 0.5))
			log_event("اكتشفت %s" % s["name"])
			if s["hostile"]:
				Game.notify("احذر! هذا وكر لقطاع الطرق", Color(1, 0.4, 0.3))

func _update_animals(ppos: Vector3) -> void:
	var alive := []
	for a in animals:
		if is_instance_valid(a):
			var d := Vector2(a.global_position.x - ppos.x, a.global_position.z - ppos.z).length()
			if d > 170.0 or (a.dead and (a.dead_time > 240.0 or d > 90.0)):
				a.queue_free()
			else:
				alive.append(a)
	animals = alive
	var living := 0
	for a in animals:
		if not a.dead:
			living += 1
	if living >= max_animals:
		return
	# أنواع حسب البيئة
	var ang := randf() * TAU
	var dist := randf_range(50.0, 110.0)
	var sp := ppos + Vector3(cos(ang), 0, sin(ang)) * dist
	var h: float = world.gen.height_at(sp.x, sp.z)
	var b: int = world.gen.biome_at(sp.x, sp.z)
	if h < 0.3 and b != WorldGen.SWAMP:
		return
	for s in settlements:
		if sp.distance_to(s["pos"]) < 50.0:
			return
	var night: bool = world.sky.is_night()
	var opts := []
	match b:
		WorldGen.PLAINS: opts = [["rabbit", 4], ["deer", 3], ["chicken", 3], ["boar", 1], ["wolf", 2.0 if night else 0.4]]
		WorldGen.FOREST: opts = [["deer", 4], ["rabbit", 2], ["boar", 3], ["wolf", 3.0 if night else 1.0], ["bear", 0.8], ["chicken", 1]]
		WorldGen.TAIGA: opts = [["deer", 3], ["wolf", 3.5], ["bear", 1.2], ["rabbit", 2], ["goat", 1]]
		WorldGen.TUNDRA: opts = [["snow_rabbit", 4], ["wolf", 2.5], ["polar_bear", 0.8], ["goat", 1.5]]
		WorldGen.SNOW: opts = [["goat", 3], ["polar_bear", 1], ["snow_rabbit", 2]]
		WorldGen.MOUNTAIN: opts = [["goat", 5], ["wolf", 1.5], ["bear", 0.6]]
		WorldGen.DESERT: opts = [["camel", 3], ["rabbit", 2]]
		WorldGen.SWAMP: opts = [["croc", 1.5], ["boar", 2], ["chicken", 1], ["deer", 1]]
		WorldGen.BEACH: opts = [["chicken", 2], ["rabbit", 1]]
		_: return
	var total := 0.0
	for o in opts:
		total += o[1]
	var x := randf() * total
	var pick: String = opts[0][0]
	for o in opts:
		x -= o[1]
		if x <= 0.0:
			pick = o[0]
			break
	var spd: Dictionary = Animal.SPECIES[pick]
	var count := randi_range(spd["group"][0], spd["group"][1])
	var leader: Animal = null
	for i in range(count):
		var p2 := sp + Vector3(randf_range(-4, 4), 0, randf_range(-4, 4))
		p2.y = world.gen.height_at(p2.x, p2.z) + 0.4
		var a := Animal.new()
		add_child(a)
		a.setup(world, pick, p2)
		if leader == null:
			leader = a
		else:
			a.leader = leader
		animals.append(a)

func on_animal_killed(a: Animal, killer) -> void:
	if killer != null and killer.get("npc_id") != null:
		var n = killer
		n.data["inv"].add("raw_meat", randi_range(1, 3))
		if randi() % 2 == 0:
			n.data["inv"].add("hide", 1)

# محاكاة الشخصيات البعيدة
func _far_sim(dt: float) -> void:
	for id in npcs:
		var d: Dictionary = npcs[id]
		if not d["alive"] or (d.get("_node") != null and is_instance_valid(d["_node"])):
			continue
		var home: Vector3 = d["home"]
		var pos: Vector3 = d["pos"]
		if d["role"] in ["wanderer", "thief"] or (d["role"] == "trader" and d["faction"] == ""):
			if d["travel_to"] == Vector3.INF or pos.distance_to(d["travel_to"]) < 8.0:
				if settlements.size() > 0 and randf() < 0.3:
					var s: Dictionary = settlements[randi() % settlements.size()]
					if not s["hostile"]:
						d["travel_to"] = s["pos"] + Vector3(randf_range(-20, 20), 0, randf_range(-20, 20))
				elif d["role"] == "thief" and randf() < 0.5:
					var st = world.build.random_player_storage()
					if st != null:
						d["travel_to"] = st.global_position + Vector3(randf_range(-30, 30), 0, randf_range(-30, 30))
			if d["travel_to"] != Vector3.INF:
				var dir: Vector3 = (d["travel_to"] - pos)
				dir.y = 0
				var step := minf(dir.length(), 1.6 * dt)
				if dir.length() > 0.1:
					pos += dir.normalized() * step
				pos.y = world.gen.height_at(pos.x, pos.z)
				if pos.y > 0.3:
					d["pos"] = pos
				else:
					d["travel_to"] = Vector3.INF
		else:
			if pos.distance_to(home) > 30.0:
				var dir2: Vector3 = home - pos
				dir2.y = 0
				pos += dir2.normalized() * minf(dir2.length(), 1.5 * dt)
				pos.y = world.gen.height_at(pos.x, pos.z)
				d["pos"] = pos
		if d["hp"] < d["max_hp"]:
			d["hp"] = minf(d["max_hp"], d["hp"] + dt * 0.1)

func _far_social() -> void:
	var ids := []
	for id in npcs:
		var d: Dictionary = npcs[id]
		if d["alive"] and (d.get("_node") == null or not is_instance_valid(d["_node"])):
			ids.append(id)
	if ids.size() < 2:
		return
	for k in range(3):
		var a: String = ids[randi() % ids.size()]
		var best := ""
		var bd := 40.0
		for b in ids:
			if b == a:
				continue
			var dd: float = npcs[a]["pos"].distance_to(npcs[b]["pos"])
			if dd < bd:
				bd = dd
				best = b
		if best != "":
			converse(a, best)

## محادثة بين شخصيتين: تغيّر العلاقة وتنقل الآراء (نميمة). تعيد [نص المتكلم، نص المستمع، نتيجة]
func converse(a: String, b: String) -> Array:
	var da: Dictionary = npcs[a]
	var db: Dictionary = npcs[b]
	var comp := _compat(da, db)
	var delta = (comp - 0.45) * 9.0 + randf_range(-3.5, 3.5) + da["traits"]["social"] * 2.0
	if (da["role"] == "bandit") != (db["role"] == "bandit"):
		delta -= 6.0
	for m in db["memory"]:
		if m["who"] == a and m["what"] in ["steal", "attack", "kill"]:
			delta -= 5.0
	add_rel(a, b, delta)
	add_rel(b, a, delta * randf_range(0.6, 1.1))
	# النميمة: نقل رأي في طرف ثالث
	var trust := clampf(get_rel(b, a) / 100.0, 0.0, 1.0)
	var opinions: Dictionary = rel[a]
	var topic := ""
	var strongest := 25.0
	for x in opinions:
		if x == b:
			continue
		if absf(opinions[x]) > strongest and randf() < 0.6:
			strongest = absf(opinions[x])
			topic = x
	if topic != "" and trust > 0.05:
		var cur := get_rel(b, topic)
		var target: float = opinions[topic]
		add_rel(b, topic, (target - cur) * 0.18 * trust)
	var r := get_rel(a, b)
	var line_a := _social_line(da, db, r, topic)
	var line_b := _reply_line(db, get_rel(b, a))
	var outcome := "ok"
	if r < -45.0 and da["traits"]["aggr"] > 0.55 and randf() < 0.35:
		outcome = "fight"
	return [line_a, line_b, outcome]

func _social_line(da: Dictionary, db: Dictionary, r: float, topic: String) -> String:
	var nm: String = db["name"]
	if r < -40.0:
		return ["ابتعد عن وجهي يا %s!" % nm, "لا أريد رؤيتك هنا.", "أنت لا تستحق الثقة يا %s." % nm, "سأريك عاقبة تصرفاتك!"][randi() % 4]
	if r < -5.0:
		return ["همم... مرحباً يا %s." % nm, "ماذا تريد؟", "لست في مزاج للحديث."][randi() % 3]
	if topic == "player":
		var pv := get_rel(da["id"], "player")
		if pv > 30.0:
			return "هل قابلت الغريب؟ إنه شخص طيب."
		if pv < -30.0:
			return "احذر من ذلك الغريب، لا أثق به."
	if topic != "" and npcs.has(topic):
		var tv := get_rel(da["id"], topic)
		if tv < -30.0:
			return "%s يثير غضبي دائماً..." % npcs[topic]["name"]
		if tv > 40.0:
			return "%s شخص رائع، أليس كذلك؟" % npcs[topic]["name"]
	if r > 45.0:
		return ["صديقي العزيز %s! كيف حالك؟" % nm, "سعيد برؤيتك يا %s." % nm, "تعال، لنجلس قليلاً.", "هل تذكر رحلتنا الأخيرة؟ هاها!"][randi() % 4]
	return ["الطقس متقلب هذه الأيام.", "سمعت عويل الذئاب ليلة أمس.", "الصيد قليل هذا الموسم.", "يجب أن نخزن المؤن قبل الشتاء.", "كيف حال العمل؟"][randi() % 5]

func _reply_line(db: Dictionary, r: float) -> String:
	if r < -40.0:
		return ["اغرب عن وجهي!", "إياك أن تقترب مني!"][randi() % 2]
	if r < 0.0:
		return ["ربما.", "إن كان لا بد...", "همم."][randi() % 3]
	if r > 45.0:
		return ["بأفضل حال يا صديقي!", "معك حق تماماً!", "هاها، أحسنت!"][randi() % 3]
	return ["نعم، صحيح.", "أتفق معك.", "سنرى."][randi() % 3]

func _daily(d: int) -> void:
	for id in npcs:
		var n: Dictionary = npcs[id]
		if not n["alive"]:
			continue
		_stock(n["inv"], n["role"], false)
		n["talks"] = 0
		n["gifts"] = 0
	# مهاجرون جدد يعوضون الموتى
	for s in settlements:
		var alive := 0
		for id in npcs:
			if npcs[id]["faction"] == s["id"] and npcs[id]["alive"]:
				alive += 1
		if alive < 3 and randf() < 0.5:
			var role: String = "bandit" if s["hostile"] else ["farmer", "hunter", "woodcutter", "guard"][randi() % 4]
			var nd := _create_npc(role, s)
			for other in npcs:
				if other != nd["id"]:
					rel[nd["id"]][other] = randf_range(-5, 20) if npcs[other]["faction"] == s["id"] else randf_range(-10, 10)
					rel[other][nd["id"]] = randf_range(0, 20) if npcs[other]["faction"] == s["id"] else 0.0
			rel[nd["id"]]["player"] = clampf(reputation(s["id"]) * 0.6, -100.0, 100.0)
			log_event("وصل وافد جديد إلى %s: %s" % [s["name"], nd["name"]])
	# ملء صناديق المستوطنات
	world.build.restock_settlements()

func on_npc_killed(victim: Node, killer) -> void:
	var vid: String = victim.npc_id
	var vd: Dictionary = npcs[vid]
	vd["alive"] = false
	active_npcs.erase(victim)
	var kid := ""
	if killer == world.player:
		kid = "player"
	elif killer != null and killer.get("npc_id") != null:
		kid = killer.npc_id
	if kid == "":
		log_event("مات %s" % vd["name"])
		return
	var was_hostile: bool = vd["role"] == "bandit" or get_rel(vid, "player") < -50.0
	for id in npcs:
		var d: Dictionary = npcs[id]
		if not d["alive"] or id == kid:
			continue
		var r := get_rel(id, vid)
		if r > 20.0:
			add_rel(id, kid, -(20.0 + r * 0.6))
			remember(id, "kill", kid)
		elif r < -40.0:
			add_rel(id, kid, 8.0)
		if d["faction"] != "" and d["faction"] == vd["faction"] and not was_hostile:
			add_rel(id, kid, -25.0)
	if kid == "player":
		if vd["role"] == "bandit":
			log_event("قتلت قاطع الطريق %s" % vd["name"])
			for s in settlements:
				if not s["hostile"]:
					for id in npcs:
						if npcs[id]["faction"] == s["id"]:
							add_rel(id, "player", 3.0)
		else:
			log_event("قتلت %s! سينتشر الخبر..." % vd["name"])
			Game.notify("قتلت %s. سيكرهك أصدقاؤه وأهل قريته" % vd["name"], Color(1, 0.4, 0.3))
	else:
		log_event("%s قتل %s" % [npcs[kid]["name"], vd["name"]])

func npc_by_id(id: String) -> Dictionary:
	return npcs.get(id, {})

# ------------------------------------------------------------------
# الحوار مع اللاعب
func greeting(d: Dictionary) -> String:
	var r := get_rel(d["id"], "player")
	var first: bool = not d["met"]
	d["met"] = true
	if d["companion"]:
		return ["أنا معك. ماذا تريد أن نفعل؟", "جاهز لأي شيء يا رفيقي.", "الطريق طويل، لكننا معاً."][randi() % 3]
	if r <= -60.0:
		return ["أنت! كيف تجرؤ على الاقتراب مني؟", "لن أنسى ما فعلته. ارحل!"][randi() % 2]
	if r <= -25.0:
		return ["ماذا تريد؟ لا أحب وجودك هنا.", "قل ما عندك بسرعة."][randi() % 2]
	if first:
		var s := settlement_of(d)
		var place := ("من %s" % s["name"]) if not s.is_empty() else "رحّال لا أستقر في مكان"
		if d["role"] == "bandit":
			return "من أنت؟ هذه أرضنا... ادفع أو ارحل."
		return "مرحباً أيها الغريب. أنا %s، %s، %s." % [d["name"], role_name(d), place]
	if r >= 60.0:
		return ["صديقي! سعيد جداً برؤيتك!", "أهلاً بك! كنت أفكر فيك للتو."][randi() % 2]
	if r >= 20.0:
		return ["أهلاً بك مجدداً.", "مرحباً! كيف تجري أمورك؟"][randi() % 2]
	return ["مرحباً.", "نعم؟", "أهلاً."][randi() % 3]

func _social_gain(base: float) -> float:
	return base * world.player.stats.skill_power_mult("social")

func chat(d: Dictionary) -> String:
	var day: int = world.sky.day()
	if d["talks_day"] != day:
		d["talks_day"] = day
		d["talks"] = 0
	d["talks"] += 1
	var t: Dictionary = d["traits"]
	var gain = (2.0 + t["social"] * 5.0) * maxf(0.0, 1.0 - (d["talks"] - 1) * 0.35)
	var r := get_rel(d["id"], "player")
	if r < -40.0:
		gain *= 0.3
	add_rel(d["id"], "player", _social_gain(gain))
	world.player.stats.add_skill_xp("social", 1.5)
	# كشف صفة
	var reveal := ""
	if randf() < 0.55:
		var keys := t.keys()
		keys.shuffle()
		for k in keys:
			if not k in d["known_traits"]:
				d["known_traits"].append(k)
				var v: float = t[k]
				if v > 0.62 or v < 0.38:
					reveal = "\n(تلاحظ أنه %s)" % TRAIT_NAMES[k][1 if v > 0.5 else 0]
				break
	if d["talks"] > 3:
		return "لقد تحدثنا كثيراً اليوم، لدي أعمال أقوم بها." + reveal
	var lines := []
	match d["role"]:
		"farmer": lines = ["المحصول هذا العام يعتمد على المطر.", "القمح ينمو أسرع إن سمّدت الأرض.", "الخنازير البرية تخرّب حقولنا!"]
		"hunter": lines = ["الغزلان تهرب إن اقتربت منها واقفاً، انحنِ وتقدّم ببطء.", "الذئاب تصطاد في جماعات، خاصة ليلاً.", "اسلخ الحيوان بسكين لتحصل على جلده."]
		"woodcutter": lines = ["البلوط المعمّر يحتاج فأساً برونزياً، لكن خشبه ممتاز.", "الصنوبر يعطي راتنجاً جيداً للمشاعل."]
		"miner": lines = ["الحديد يحتاج معولاً برونزياً على الأقل.", "يقال إن الكريستال يلمع في القمم الثلجية.", "الفحم الحجري وقود أقوى من الخشب."]
		"trader", "smith": lines = ["كل شيء له ثمن يا صديقي.", "الذهب والجواهر تفتح كل الأبواب.", "إن احتجت أدوات معدنية، فأنا هنا."]
		"guard": lines = ["أبقِ عينيك مفتوحتين، قطاع الطرق يجوبون المنطقة.", "لا تثق بالغرباء بسهولة."]
		"healer": lines = ["لا تأكل اللحم نيئاً، ولا تشرب الماء دون غليه.", "الأعشاب الطبية تنمو في الغابات والمستنقعات.", "الضمادات توقف النزيف."]
		"elder": lines = ["رأيت شتاءات كثيرة... احترم الطبيعة تحترمك.", "قريتنا تقدّر من يساعدها."]
		"bandit": lines = ["لا تنظر إليّ هكذا.", "الطريق ليس آمناً... لأمثالك.", "معك شيء ثمين؟"]
		"thief": lines = ["أتجول من مكان لآخر... أبحث عن فرص.", "صناديق الناس مليئة بأشياء لا يحتاجونها، أليس كذلك؟", "أين تسكن بالمناسبة؟"]
		_: lines = ["رأيت أماكن كثيرة في رحلاتي.", "البركان في الجنوب خطير لكنه غني بالسبج والكبريت."]
	return lines[randi() % lines.size()] + reveal

func ask_people(d: Dictionary) -> String:
	var id: String = d["id"]
	var out := []
	# شهادات سرقة
	for m in d["memory"]:
		if m["what"] == "steal_player" and npcs.has(m["who"]):
			var thief: Dictionary = npcs[m["who"]]
			thief["exposed"] = true
			out.append("رأيت %s يسرق من صندوقك! إنه لص." % thief["name"])
			log_event("علمت أن %s لص سرق أغراضك" % thief["name"])
	var opinions: Dictionary = rel[id]
	var keys := []
	for k in opinions:
		if k != "player" and npcs.has(k) and npcs[k]["alive"]:
			keys.append(k)
	keys.sort_custom(func(a, b): return absf(opinions[a]) > absf(opinions[b]))
	var shown := 0
	var r := get_rel(id, "player")
	if r < -10.0:
		return "ولماذا أخبرك بشيء عن الناس؟"
	for k in keys:
		if shown >= 3:
			break
		var v: float = opinions[k]
		var nm: String = npcs[k]["name"]
		known_rel["%s|%s" % [id, k]] = true
		if v > 55.0:
			out.append("%s صديقي المقرب، أثق به كثيراً." % nm)
		elif v > 25.0:
			out.append("علاقتي جيدة مع %s." % nm)
		elif v < -45.0:
			out.append("أكره %s! لا تثق به أبداً." % nm)
		elif v < -15.0:
			out.append("لا أرتاح لـ%s." % nm)
		else:
			continue
		shown += 1
	if out.is_empty():
		return "لا أعرف الكثير عن الآخرين."
	return "\n".join(out)

func ask_place(d: Dictionary) -> String:
	var r := get_rel(d["id"], "player")
	if r < 0.0:
		return "اكتشف الأماكن بنفسك."
	if d["info_given"] >= 2 and r < 40.0:
		return "أخبرتك بما أعرف. ربما لاحقاً عندما نصبح أصدقاء أكثر."
	d["info_given"] += 1
	var opts := []
	for s in settlements:
		if not s["discovered"]:
			opts.append(["s", s])
	var rare := ["gold", "crystal", "gem", "iron", "obsidian", "sulfur"]
	var pick = null
	if not opts.is_empty() and randf() < 0.6:
		pick = opts[randi() % opts.size()]
		var s: Dictionary = pick[1]
		s["discovered"] = true
		add_marker(s["pos"], s["name"], Color(1, 0.9, 0.4))
		var warn := " لكن احذر، إنهم قطاع طرق!" if s["hostile"] else ""
		return "هناك مكان يسمى %s. وضعت لك علامة على الخريطة.%s" % [s["name"], warn]
	# مورد نادر
	var tries := 30
	while tries > 0:
		tries -= 1
		var rt: String = rare[randi() % rare.size()]
		var ang := randf() * TAU
		var dist := randf_range(100.0, 500.0)
		var p: Vector3 = d["pos"] + Vector3(cos(ang), 0, sin(ang)) * dist
		var b: int = world.gen.biome_at(p.x, p.z)
		var ok := false
		match rt:
			"gold": ok = b in [WorldGen.MOUNTAIN, WorldGen.DESERT]
			"crystal", "gem": ok = b == WorldGen.SNOW
			"iron": ok = b in [WorldGen.MOUNTAIN, WorldGen.TAIGA, WorldGen.TUNDRA]
			"obsidian", "sulfur": ok = b == WorldGen.VOLCANIC
		if ok:
			add_marker(p, "شائعة: %s" % ResDB.get_type(rt)["name"], Color(0.6, 0.9, 1.0))
			return "سمعت أن هناك %s في %s. وضعت لك علامة تقريبية." % [ResDB.get_type(rt)["name"], WorldGen.BIOME_NAMES[b]]
	return "الجبال الشمالية باردة جداً، احمل ملابس فرو إن ذهبت هناك. والصحراء الجنوبية تحتاج ماءً كثيراً."

func add_marker(p: Vector3, label: String, col: Color) -> void:
	markers.append({"pos": p, "label": label, "col": col})

func gift(d: Dictionary, item_id: String, n: int) -> String:
	var day: int = world.sky.day()
	if d["gifts_day"] != day:
		d["gifts_day"] = day
		d["gifts"] = 0
	d["gifts"] += 1
	var t: Dictionary = d["traits"]
	var val := ItemDB.value_of(item_id) * n
	var it := ItemDB.get_item(item_id)
	var mult = 0.6 + t["greed"] * 0.7
	if it.get("cat", "") == "food":
		mult += 0.4
	if item_id == "rotten_food" or item_id == "toadstool":
		add_rel(d["id"], "player", -8.0)
		return "هل تحاول تسميمي؟! هذا مقرف."
	var gain := clampf(sqrt(val) * 3.0 * mult, 1.0, 30.0) * maxf(0.2, 1.0 - (d["gifts"] - 1) * 0.3)
	add_rel(d["id"], "player", _social_gain(gain))
	d["inv"].add(item_id, n)
	remember(d["id"], "gift", "player")
	world.player.stats.add_skill_xp("social", 2.0)
	if gain > 18.0:
		return "يا إلهي! هذه هدية رائعة، لن أنساها أبداً!"
	if gain > 8.0:
		return "شكراً جزيلاً لك! هذا لطف كبير."
	return "شكراً... هذا لطيف منك."

func recruit(d: Dictionary) -> String:
	var r := get_rel(d["id"], "player")
	if d["role"] == "bandit":
		if r > 50.0:
			d["companion"] = true
			d["order"] = "follow"
			return "حسناً... الحياة مع العصابة مملة. سآتي معك."
		return "أنا؟ أتبعك؟ هاها! اغرب عن وجهي."
	var count := 0
	for id in npcs:
		if npcs[id]["companion"] and npcs[id]["alive"]:
			count += 1
	if count >= 3:
		return "لديك رفاق كثيرون بالفعل."
	var need = 55.0 - d["traits"]["brave"] * 10.0
	if r < need:
		return "لا أعرفك جيداً بعد لأترك كل شيء وأتبعك. (تحتاج علاقة أقوى)"
	d["companion"] = true
	d["order"] = "follow"
	log_event("%s انضم إليك كرفيق" % d["name"])
	return "سأكون إلى جانبك. لنذهب!"

func order(d: Dictionary, o: String) -> String:
	d["order"] = o
	match o:
		"follow": return "سأتبعك."
		"stay": return "سأنتظر هنا."
		"guard":
			d["guard_pos"] = world.player.global_position
			return "سأحرس هذا المكان من اللصوص والحيوانات."
		"dismiss":
			d["companion"] = false
			return "حسناً، سأعود إلى دياري. نادني إن احتجتني."
	return ""

func threaten(d: Dictionary) -> Array:
	var t: Dictionary = d["traits"]
	add_rel(d["id"], "player", -25.0)
	var node = d.get("_node")
	if node:
		witness(node.global_position, "player", d["id"], 15.0, "threat", 20.0)
	if t["brave"] < 0.4 and d["role"] != "guard":
		var taken := []
		var inv: Inventory = d["inv"]
		for i in inv.most_valuable(2):
			var st := inv.take_slot(i)
			if not st.is_empty():
				taken.append([st["id"], st["n"]])
		world.player.receive_items(taken, world.player.global_position)
		log_event("هددت %s وأخذت أغراضه" % d["name"])
		return ["خذ ما تريد! لكن لا تؤذني...", taken]
	if node:
		node.become_hostile_to(world.player, false)
	return ["تهددني أنا؟! سأعلمك درساً!", []]

func accuse(d: Dictionary) -> String:
	var stolen: Array = d["stolen"]
	if stolen.is_empty():
		add_rel(d["id"], "player", -10.0)
		return "أنا؟ لص؟ كيف تجرؤ!"
	d["exposed"] = true
	if d["traits"]["brave"] < 0.55:
		var back := []
		for e in stolen:
			var got: int = d["inv"].remove(e[0], e[1])
			if got > 0:
				back.append([e[0], got])
		d["stolen"] = []
		world.player.receive_items(back, world.player.global_position)
		add_rel(d["id"], "player", -10.0)
		log_event("استعدت أغراضك المسروقة من %s" % d["name"])
		return "حسناً، حسناً! خذ أغراضك... لم أقصد."
	var node = d.get("_node")
	if node:
		node.become_hostile_to(world.player, false)
	return "لن تستعيدها إلا على جثتي!"

## قيمة السعر في التجارة (مضاعف)
func price_mult(d: Dictionary, buying: bool) -> float:
	var r := get_rel(d["id"], "player")
	var g: float = d["traits"]["greed"]
	var social: float = world.player.stats.skill_level("social") * 0.01
	if buying:
		return maxf(0.6, (1.35 - r / 250.0 + g * 0.35) - social)
	return minf(1.1, (0.65 + r / 300.0 - g * 0.2) + social)

func can_trade(d: Dictionary) -> bool:
	return d["role"] != "bandit" or get_rel(d["id"], "player") > 20.0

# ------------------------------------------------------------------
func to_data() -> Dictionary:
	var nd := {}
	for id in npcs:
		var d: Dictionary = npcs[id]
		var node = d.get("_node")
		if node != null and is_instance_valid(node):
			d["pos"] = node.global_position
			d["hp"] = node.hp
		var app := {}
		for k in d["app"]:
			var v = d["app"][k]
			app[k] = v.to_html() if v is Color else v
		var mem := []
		for m in d["memory"]:
			mem.append(m.duplicate())
		nd[id] = {"name": d["name"], "female": d["female"], "role": d["role"], "faction": d["faction"], "traits": d["traits"].duplicate(),
			"home": Game.arr3(d["home"]), "pos": Game.arr3(d["pos"]), "hp": d["hp"], "max_hp": d["max_hp"], "inv": d["inv"].to_data(), "app": app,
			"alive": d["alive"], "companion": d["companion"], "order": d["order"], "guard_pos": Game.arr3(d["guard_pos"]), "met": d["met"],
			"known_traits": d["known_traits"].duplicate(), "memory": mem, "stolen": d["stolen"].duplicate(true), "weapon": d["weapon"],
			"exposed": d["exposed"], "sleep_at": d["sleep_at"], "wake_at": d["wake_at"], "info_given": d["info_given"]}
	var sd := []
	for s in settlements:
		sd.append({"id": s["id"], "name": s["name"], "type": s["type"], "pos": Game.arr3(s["pos"]), "radius": s["radius"], "hostile": s["hostile"], "discovered": s["discovered"], "attitude": s["attitude"]})
	var mk := []
	for m in markers:
		mk.append({"pos": Game.arr3(m["pos"]), "label": m["label"], "col": m["col"].to_html()})
	return {"npcs": nd, "rel": rel.duplicate(true), "known": known_rel.duplicate(), "journal": journal.duplicate(), "settlements": sd, "markers": mk, "next": _next_id, "day": _daily_day}

func from_data(data: Dictionary) -> void:
	npcs = {}
	settlements = []
	for s in data.get("settlements", []):
		var p := Game.v3(s["pos"])
		settlements.append({"id": s["id"], "name": s["name"], "type": s["type"], "pos": p, "radius": float(s["radius"]), "hostile": bool(s["hostile"]), "discovered": bool(s["discovered"]), "attitude": float(s.get("attitude", 0.0))})
		world.gen.clear_zones.append(Vector3(p.x, p.z, 30.0))
	var nd: Dictionary = data.get("npcs", {})
	for id in nd:
		var s: Dictionary = nd[id]
		var inv := Inventory.new(12)
		inv.from_data(s.get("inv", []))
		var app := {}
		for k in s.get("app", {}):
			var v = s["app"][k]
			app[k] = Color.html(v) if v is String and k in ["skin", "hair", "shirt", "pants", "shoes"] else v
		app["hair_style"] = int(app.get("hair_style", 0))
		var mem := []
		for m in s.get("memory", []):
			mem.append({"t": float(m.get("t", 0.0)), "what": str(m.get("what", "")), "who": str(m.get("who", ""))})
		npcs[id] = {"id": id, "name": s["name"], "female": bool(s["female"]), "role": s["role"], "faction": s["faction"], "traits": s["traits"],
			"home": Game.v3(s["home"]), "pos": Game.v3(s["pos"]), "hp": float(s["hp"]), "max_hp": float(s["max_hp"]), "inv": inv, "app": app,
			"alive": bool(s["alive"]), "companion": bool(s["companion"]), "order": str(s["order"]), "guard_pos": Game.v3(s.get("guard_pos", [0, 0, 0])),
			"met": bool(s["met"]), "talks_day": -1, "talks": 0, "known_traits": s.get("known_traits", []), "memory": mem, "stolen": s.get("stolen", []),
			"weapon": str(s.get("weapon", "")), "exposed": bool(s.get("exposed", false)), "sleep_at": float(s.get("sleep_at", 22.0)), "wake_at": float(s.get("wake_at", 6.0)),
			"gifts_day": -1, "gifts": 0, "travel_to": Vector3.INF, "info_given": int(s.get("info_given", 0))}
	rel = {}
	var rd: Dictionary = data.get("rel", {})
	for a in rd:
		rel[a] = {}
		for b in rd[a]:
			rel[a][b] = float(rd[a][b])
	for id in npcs:
		if not rel.has(id):
			rel[id] = {}
	known_rel = data.get("known", {})
	journal = data.get("journal", [])
	markers = []
	for m in data.get("markers", []):
		markers.append({"pos": Game.v3(m["pos"]), "label": m["label"], "col": Color.html(m["col"])})
	_next_id = int(data.get("next", npcs.size()))
	_daily_day = int(data.get("day", -1))
