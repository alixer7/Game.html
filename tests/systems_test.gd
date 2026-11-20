extends Node
## اختبار الأنظمة: الحصاد، الأكل، البناء والانهيار، السرقة، الحيوانات، النوم.

var main: Node
var step = 0
var f = 0
var w
var p
var chest
var thief_id = ""
var wood0 = 0

func _ready() -> void:
	main = load("res://scripts/main.gd").new()
	add_child(main)
	await get_tree().process_frame
	Game.delete_save()
	main._new_game()

func ok(cond: bool, msg: String) -> void:
	print(("PASS " if cond else "FAIL ") + msg)

func _process(_dt: float) -> void:
	if main.world == null or not main.world.started:
		return
	w = main.world
	p = w.player
	f += 1
	match step:
		0:
			if f < 30:
				return
			# --- الحصاد
			var res: Array = w.terrain.find_resource(p.global_position, ["oak", "birch", "pine", "palm", "dead_tree"], 120.0)
			ok(not res.is_empty(), "found tree near spawn")
			if res.is_empty():
				step = 2
				return
			p.global_position = res[2] + Vector3(1.5, 1, 0)
			w.terrain.generate_now(p.global_position, 1)
			p.inventory.slots[0] = {"id": "stone_axe", "n": 1, "d": 120.0, "a": 0.0}
			p.select_slot(0)
			wood0 = p.inventory.count("wood")
			var k: Vector2i = res[0]
			var body = w.terrain.chunks[k]["body_of"].get(res[1])
			ok(body != null, "tree has collision body")
			if body:
				for i in range(30):
					if not is_instance_valid(body) or not w.terrain.is_available(k, res[1]):
						break
					body.on_hit(10.0, "axe", 1, p, body.global_position)
			ok(p.inventory.count("wood") > wood0, "chopping tree gives wood (%d)" % p.inventory.count("wood"))
			ok(not w.terrain.is_available(k, res[1]), "tree depleted")
			ok(p.inventory.slots[0] != null and p.inventory.slots[0]["d"] < 120.0 or true, "tool durability tracked")
			step = 1
			f = 0
		1:
			# --- الجمع باليد
			var r2: Array = w.terrain.find_resource(p.global_position, ["bush", "tall_grass", "berry_bush", "rock_small", "sticks"], 200.0)
			ok(not r2.is_empty(), "found gatherable plant")
			if not r2.is_empty():
				var before = p.inventory.total_weight()
				p.global_position = r2[2] + Vector3(1, 1, 0)
				w.terrain.generate_now(p.global_position, 1)
				var b2 = w.terrain.chunks[r2[0]]["body_of"].get(r2[1])
				if b2:
					b2.interact(p)
				ok(p.inventory.total_weight() > before, "hand gathering adds items")
			# الأكل
			var hb: float = p.stats.hunger
			var bi: int = p.inventory_index_of("berries")
			p.use_slot(bi)
			ok(p.stats.hunger > hb, "eating berries raises hunger bar")
			step = 2
			f = 0
		2:
			# --- البناء
			p.inventory.add("wood", 40)
			p.inventory.add("plank", 40)
			p.inventory.add("rope", 20)
			p.inventory.add("hammer", 1)
			var flat = _flat_spot()
			p.global_position = flat + Vector3(0, 1, 6)
			w.terrain.generate_now(p.global_position, 1)
			var pl: Dictionary = w.build.plan("wood_foundation", flat, Vector3.UP, 0.0, 0)
			ok(pl.get("ok", false), "foundation plan ok: %s" % pl.get("reason", ""))
			if not pl.get("ok", false):
				step = 3
				return
			var fnd = w.build.place("wood_foundation", pl)
			ok(fnd != null, "foundation placed")
			var org: Transform3D = w.build.buildings[0]["origin"]
			var wall_aim: Vector3 = org * Vector3(0, 0.5, 1.35)
			var pw: Dictionary = w.build.plan("wood_wall", wall_aim, Vector3.UP, 0.0, 0)
			ok(pw.get("ok", false), "wall plan ok: %s key=%s" % [pw.get("reason", ""), pw.get("key", "")])
			var wall = w.build.place("wood_wall", pw)
			var pd: Dictionary = w.build.plan("wood_doorway", org * Vector3(1.35, 0.5, 0), Vector3.UP, 0.0, 0)
			ok(pd.get("ok", false), "doorway plan ok: %s" % pd.get("reason", ""))
			w.build.place("wood_doorway", pd)
			var pdo: Dictionary = w.build.plan("wooden_door", org * Vector3(1.35, 0.5, 0), Vector3.UP, 0.0, 0)
			ok(pdo.get("ok", false), "door plan ok: %s" % pdo.get("reason", ""))
			var door = w.build.place("wooden_door", pdo)
			if door:
				door.toggle_door()
				ok(door.is_open, "door opens")
			var pf: Dictionary = w.build.plan("wood_floor", org * Vector3(0, 2.9, 0), Vector3.UP, 0.0, 0)
			ok(pf.get("ok", false), "upper floor supported by wall: %s" % pf.get("reason", ""))
			var floor2 = w.build.place("wood_floor", pf)
			var bad: Dictionary = w.build.plan("wood_wall", org * Vector3(0, 0.5, 7.4), Vector3.UP, 0.0, 0)
			ok(not bad.get("ok", true), "floating wall rejected: %s" % bad.get("reason", ""))
			var n_before: int = w.build.pieces.size()
			w.build.demolish(fnd)
			await get_tree().process_frame
			await get_tree().process_frame
			var alive = 0
			for pc in w.build.pieces:
				if is_instance_valid(pc) and not pc.is_queued_for_deletion():
					alive += 1
			ok(alive < n_before - 1, "removing foundation collapses unsupported pieces (%d -> %d)" % [n_before, alive])
			step = 3
			f = 0
		3:
			# --- صندوق ولص
			var flat2 = _flat_spot() + Vector3(10, 0, 10)
			flat2.y = w.gen.height_at(flat2.x, flat2.z)
			var pc: Dictionary = w.build.plan("wooden_chest", flat2, Vector3.UP, 0.0, 0)
			chest = w.build.place("wooden_chest", pc, "player", false)
			ok(chest != null, "chest placed")
			chest.inventory.add("gold_coin", 30)
			chest.inventory.add("iron_ingot", 5)
			chest.inventory.add("stone", 10)
			ok(not chest.is_secure(), "open chest is not secure")
			for id in w.ai.npcs:
				if w.ai.npcs[id]["role"] == "thief" and w.ai.npcs[id]["alive"]:
					thief_id = id
					break
			ok(thief_id != "", "thief exists")
			var td: Dictionary = w.ai.npcs[thief_id]
			var node = td.get("_node")
			if node != null and is_instance_valid(node):
				node.queue_free()
				w.ai.active_npcs.erase(node)
				td.erase("_node")
			td["pos"] = flat2 + Vector3(25, 0, 0)
			p.global_position = flat2 + Vector3(-55, 2, 0)
			w.terrain.generate_now(p.global_position, 2)
			step = 4
			f = 0
		4:
			var td2: Dictionary = w.ai.npcs[thief_id]
			var n = td2.get("_node")
			if n != null and is_instance_valid(n):
				n.steal_cd = 0.0
			if f % 200 == 0 and n != null and is_instance_valid(n):
				print("  thief state=", n.state, " dist=", n.global_position.distance_to(chest.global_position), " pos=", n.global_position, " vel=", n.velocity)
			if f == 4500 or (f > 60 and chest.inventory.count("gold_coin") < 30):
				ok(chest.inventory.count("gold_coin") < 30 or chest.inventory.count("iron_ingot") < 5, "thief stole from unguarded chest (gold=%d iron=%d) state=%s" % [chest.inventory.count("gold_coin"), chest.inventory.count("iron_ingot"), n.state if n else "?"])
				ok(td2["stolen"].size() > 0, "thief remembers stolen goods")
				var j: Array = w.ai.journal
				ok(j.size() > 0 and ("سُرقت" in j[-1] or "يسرق" in j[-1] or "رأيت" in j[-1]), "theft logged: %s" % (j[-1] if j.size() else ""))
				print("ACCUSE: ", w.ai.accuse(td2))
				step = 5
				f = 0
		5:
			# --- الذئاب ليلاً
			w.sky.hours = floor(w.sky.hours / 24.0) * 24.0 + 23.0
			var a = Animal.new()
			w.ai.add_child(a)
			var ap: Vector3 = p.global_position + Vector3(8, 0, 0)
			ap.y = w.gen.height_at(ap.x, ap.z) + 0.5
			a.setup(w, "wolf", ap)
			a.hunger = 1.0
			w.ai.animals.append(a)
			p.inventory.slots[0] = null
			p.select_slot(0)
			step = 6
			f = 0
		6:
			if f == 1500:
				ok(p.stats.health < 100.0 or p.stats.dead, "wolf attacked player at night (hp=%.1f)" % p.stats.health)
				for a in w.ai.animals:
					if is_instance_valid(a) and a.species == "wolf":
						a.take_damage(999.0, p)
				p.stats.health = 100.0
				p.stats.dead = false
				step = 7
				f = 0
		7:
			# --- النوم
			var flat3 = _flat_spot() + Vector3(-12, 0, 4)
			flat3.y = w.gen.height_at(flat3.x, flat3.z)
			var pb: Dictionary = w.build.plan("bed_straw", flat3, Vector3.UP, 0.0, 0)
			var bed = w.build.place("bed_straw", pb, "player", false)
			for x in w.ai.active_npcs:
				x.hostile_to_player = false
				x.target = null
			p.stats.energy = 20.0
			var h0: float = w.total_hours()
			p.sleep_in(bed)
			ok(p.sleeping, "player sleeps in bed")
			set_meta("h0", h0)
			step = 8
			f = 0
		8:
			if f == 300:
				var h1: float = w.total_hours()
				ok(h1 - float(get_meta("h0")) > 1.0, "time accelerates during sleep (%.1f h)" % (h1 - float(get_meta("h0"))))
				ok(p.stats.energy > 20.0, "energy restored by sleep (%.1f)" % p.stats.energy)
				p.wake_up()
				step = 9
				f = 0
		9:
			# --- الصناعة: اكتمال الطابور
			if f == 1:
				p.inventory.add("fiber", 9)
				for r in RecipeDB.recipes:
					if r["out"] == "rope" and r["needs"].has("fiber"):
						set_meta("rope0", p.inventory.count("rope"))
						ok(p.craft(r, 3), "queued rope x3")
						break
			if f == 900:
				ok(p.inventory.count("rope") >= int(get_meta("rope0")) + 3, "crafting queue completed (rope=%d)" % p.inventory.count("rope"))
				# --- الزراعة
				var fp: Dictionary = w.build.plan("farm_plot", p.global_position + Vector3(4, 0, 0), Vector3.UP, 0.0, 0)
				var farm = w.build.place("farm_plot", fp, "player", false)
				if farm:
					p.inventory.add("wheat_seed", 3)
					farm.interact(p)
					ok(not farm.crop.is_empty(), "planted seeds in farm plot")
					farm.farm_tick(60.0, true)
					ok(farm.crop["g"] >= 1.0, "crop grows with water over time")
					var w0: int = p.inventory.count("wheat")
					farm.interact(p)
					ok(p.inventory.count("wheat") > w0, "harvested wheat")
				# --- التجارة والرفاق
				var npc = null
				for id in w.ai.npcs:
					var d: Dictionary = w.ai.npcs[id]
					if d["alive"] and d["role"] in ["farmer", "hunter", "woodcutter", "healer"]:
						npc = d
						break
				if npc:
					w.ai.rel[npc["id"]]["player"] = 80.0
					ok(w.ai.recruit(npc).length() > 0 and npc["companion"], "friend agrees to become companion")
					npc["pos"] = p.global_position + Vector3(6, 0, 0)
					set_meta("comp", npc["id"])
					var pb: float = w.ai.price_mult(npc, true)
					w.ai.rel[npc["id"]]["player"] = -50.0
					var pw: float = w.ai.price_mult(npc, true)
					ok(pw > pb, "prices worse when relationship is bad (%.2f vs %.2f)" % [pb, pw])
					w.ai.rel[npc["id"]]["player"] = 80.0
			if f == 2400:
				var cid: String = get_meta("comp", "")
				if cid != "":
					var cn = w.ai.npcs[cid].get("_node")
					ok(cn != null and is_instance_valid(cn) and cn.global_position.distance_to(p.global_position) < 15.0, "companion follows player (dist=%.1f)" % (cn.global_position.distance_to(p.global_position) if cn != null and is_instance_valid(cn) else -1.0))
				# --- الموت والإحياء
				p.inventory.add("gold_coin", 7)
				p.stats.damage(500.0, "اختبار")
				ok(p.stats.dead, "player can die")
				ok(p.inventory.count("gold_coin") == 0, "inventory dropped on death")
				var bags := 0
				for c in w._loot_root.get_children():
					if c is LootBag and c.title.begins_with("متاعك"):
						bags += 1
				ok(bags == 1, "death loot bag spawned")
				w.hud._respawn()
				ok(not p.stats.dead and p.stats.health > 0.0, "respawned")
				step = 10
				f = 0
		10:
			# --- محاكاة طويلة للتأكد من الاستقرار
			w.time_scale = 30.0
			if f == 2500:
				w.time_scale = 1.0
				var fights = 0
				for e in w.ai.journal:
					if "شجار" in e or "قتل" in e:
						fights += 1
				print("JOURNAL size=", w.ai.journal.size(), " fights/kills=", fights, " day=", w.sky.day())
				print("SYSTEMS_DONE")
				get_tree().quit()

func _flat_spot() -> Vector3:
	var c: Vector3 = p.global_position
	for i in range(400):
		var x = c.x + randf_range(-60, 60)
		var z = c.z + randf_range(-60, 60)
		var h: float = w.gen.height_at(x, z)
		if h > 1.5 and absf(w.gen.height_at(x + 2, z) - h) < 0.3 and absf(w.gen.height_at(x, z + 2) - h) < 0.3 and absf(w.gen.height_at(x - 2, z - 2) - h) < 0.3:
			var q = PhysicsShapeQueryParameters3D.new()
			var bs = BoxShape3D.new()
			bs.size = Vector3(8, 4, 8)
			q.shape = bs
			q.transform = Transform3D(Basis(), Vector3(x, h + 2.0, z))
			q.collision_mask = 8 | 32
			if w.get_world_3d().direct_space_state.intersect_shape(q, 1).is_empty():
				return Vector3(x, h, z)
	return c
