class_name BuildPiece
extends StaticBody3D
## قطعة بناء: جدار، أساس، باب، محطة صناعة، صندوق تخزين، سرير، حقل، مشعل...

var manager: Node
var def_id := ""
var def := {}
var hp := 100.0
var owner_id := "player"
var b_id := -1
var key := ""
var inventory: Inventory = null
var locked := false
var fuel := 0.0
var infinite_fuel := false
var is_open := false
var crop := {}
var water := 0.0
var tampered := false
var door_pivot: Node3D = null
var door_cs: CollisionShape3D = null
var fire_fx: GPUParticles3D = null
var light: OmniLight3D = null
var crop_node: Node3D = null
var _secure_cache := -1.0
var _secure_val := false
var _flicker := 0.0
var label: Label3D = null

func setup(m: Node, id: String, owner := "player") -> void:
	manager = m
	def_id = id
	def = BuildDB.get_piece(id)
	owner_id = owner
	hp = def.get("hp", 100.0)
	collision_layer = 32
	collision_mask = 0
	if def.has("slots"):
		inventory = Inventory.new(def["slots"], def.get("max_w", INF))
	locked = def.get("locked", false)
	if def.get("station", "") == "campfire":
		fuel = 240.0
	m.build_visual(self)

func display_name() -> String:
	return def.get("name", def_id)

func is_station(kind: String) -> bool:
	if def.get("station", "") != kind:
		return false
	if kind == "campfire":
		return fuel > 0.0 or infinite_fuel
	return true

func provides_heat() -> float:
	if def.get("station", "") == "campfire" and (fuel > 0.0 or infinite_fuel):
		return 1.0
	if def.get("station", "") == "furnace":
		return 0.5
	if def_id == "torch_stand":
		return 0.25
	return 0.0

func mark_tampered() -> void:
	tampered = true

## هل الصندوق آمن من اللصوص؟ (مقفل، أو داخل غرفة مغلقة بأبواب مقفلة)
func is_secure() -> bool:
	if locked:
		return true
	var now := Time.get_ticks_msec() / 1000.0
	if now - _secure_cache < 8.0:
		return _secure_val
	_secure_cache = now
	_secure_val = _check_enclosed()
	return _secure_val

func enclosure_report() -> String:
	if locked:
		return "مقفل: آمن من معظم اللصوص"
	if is_secure():
		return "داخل غرفة مغلقة بأبواب مقفلة: آمن"
	return "غير آمن: ضع قفلاً، أو ضعه في غرفة مغلقة بباب مقفل"

func _check_enclosed() -> bool:
	var space := get_world_3d().direct_space_state
	var base := global_position
	for hgt in [0.5, 1.7]:
		var from := base + Vector3(0, hgt, 0)
		for i in range(8):
			var a := TAU * i / 8.0
			var dir := Vector3(cos(a), 0, sin(a))
			var q := PhysicsRayQueryParameters3D.create(from, from + dir * 14.0, 32)
			q.exclude = [get_rid()]
			var hit := space.intersect_ray(q)
			if hit.is_empty():
				return false
			var col = hit["collider"]
			var p := col as BuildPiece
			if p == null:
				return false
			if p.def.get("slot", "") == "door" and (not p.locked or p.is_open):
				return false
			if p.def.get("kind", "") == "free" and not p.def_id in ["wood_fence"]:
				# أثاث وسط الطريق: استمر خلفه
				var q2 := PhysicsRayQueryParameters3D.create(hit["position"] + dir * 0.05, from + dir * 14.0, 32)
				q2.exclude = [get_rid(), p.get_rid()]
				var hit2 := space.intersect_ray(q2)
				if hit2.is_empty() or not (hit2["collider"] is BuildPiece) or hit2["collider"].def.get("kind", "") == "free":
					return false
	var up := PhysicsRayQueryParameters3D.create(base + Vector3(0, 1.0, 0), base + Vector3(0, 12, 0), 32)
	up.exclude = [get_rid()]
	return not space.intersect_ray(up).is_empty()

# ------------------------------------------------------------------
func get_interact_text(player) -> String:
	var n := display_name()
	var held: String = player.held_item_id()
	if def.get("slot", "") == "door":
		if def.get("lockable", false) and not locked and held == "iron_lock" and owner_id == "player":
			return "ركّب القفل على %s" % n
		return ("أغلق " if is_open else "افتح ") + n + (" (مقفل)" if locked else "")
	if inventory != null:
		if def_id == "wooden_chest" or def_id == "large_chest":
			if not locked and held == "iron_lock" and owner_id == "player":
				return "ركّب القفل على %s" % n
		var own := "" if owner_id == "player" else "  (ملك %s)" % manager.owner_name(owner_id)
		return "افتح %s%s" % [n, own]
	var st: String = def.get("station", "")
	if st == "campfire":
		if held in ["wood", "stick", "hardwood", "charcoal", "coal", "plank", "resin", "fat"]:
			return "أضف %s للنار" % ItemDB.name_of(held)
		return "استخدم %s (%s)" % [n, ("مشتعلة %d ث" % int(fuel)) if fuel > 0.0 or infinite_fuel else "مطفأة - أضف حطباً"]
	if st != "":
		return "استخدم %s" % n
	if def.has("bed"):
		return "نم في %s" % n
	if def.get("farm", false):
		return _farm_text(player)
	if def.get("collector", false):
		return "%s (الماء: %d/10)%s" % [n, int(water), " - املأ القربة" if water >= 1.0 and player.inventory.count("waterskin") > 0 else ""]
	return n

func interact(player) -> void:
	var held: String = player.held_item_id()
	if def.get("slot", "") == "door":
		if def.get("lockable", false) and not locked and held == "iron_lock" and owner_id == "player":
			if player.inventory.remove("iron_lock", 1) > 0:
				locked = true
				Game.notify("تم تركيب القفل. الباب الآن آمن من اللصوص", Color(0.7, 1, 0.7))
				Sfx.play("craft", global_position)
			return
		if locked and owner_id != "player":
			Game.notify("الباب مقفل", Color(1, 0.7, 0.5))
			return
		toggle_door()
		return
	if inventory != null:
		if (def_id == "wooden_chest" or def_id == "large_chest") and not locked and held == "iron_lock" and owner_id == "player":
			if player.inventory.remove("iron_lock", 1) > 0:
				locked = true
				Game.notify("الصندوق مقفل الآن", Color(0.7, 1, 0.7))
				Sfx.play("craft", global_position)
			return
		if locked and owner_id != "player":
			Game.notify("مقفل بإحكام", Color(1, 0.7, 0.5))
			return
		Game.hud.open_storage(self)
		return
	var st: String = def.get("station", "")
	if st == "campfire" and held in ["wood", "stick", "hardwood", "charcoal", "coal", "plank", "resin", "fat"]:
		if player.inventory.remove(held, 1) > 0:
			fuel += ItemDB.get_item(held).get("fuel", 30.0) * 2.0
			Sfx.play("build", global_position, -4.0)
		return
	if st != "":
		Game.hud.open_crafting(st)
		return
	if def.has("bed"):
		player.sleep_in(self)
		return
	if def.get("farm", false):
		_farm_interact(player)
		return
	if def.get("collector", false):
		if water >= 1.0:
			var i: int = player.inventory_index_of("waterskin")
			if i >= 0:
				player.inventory.take_slot(i, 1)
				player.inventory.add("waterskin_clean", 1)
				water -= 1.0
				Sfx.play("drink", global_position)
				Game.notify("ملأت القربة بماء المطر النظيف", Color(0.6, 0.85, 1))
			else:
				Game.notify("تحتاج قربة ماء فارغة", Color(1, 0.8, 0.5))
		else:
			Game.notify("المجمع فارغ. انتظر المطر", Color(0.8, 0.85, 1))

func toggle_door() -> void:
	is_open = not is_open
	if door_pivot:
		var tw := create_tween()
		tw.tween_method(_set_door_angle, door_pivot.rotation.y, -1.6 if is_open else 0.0, 0.35)
	Sfx.play("build", global_position, -6.0)

# ------------------------------------------------------------------
func _set_door_angle(a: float) -> void:
	door_pivot.rotation.y = a
	if door_cs:
		door_cs.transform = Transform3D(Basis(Vector3.UP, a), door_pivot.position) * Transform3D(Basis(), Vector3(0.48, 1.08, 0))

func _farm_text(player) -> String:
	var held: String = player.held_item_id()
	if crop.is_empty():
		var seed := _seed_for(player)
		return "ازرع %s" % ItemDB.name_of(seed) if seed != "" else "حقل فارغ - تحتاج بذوراً"
	var g: float = crop["g"]
	var nm := {"wheat": "قمح", "potato": "بطاطا", "cotton": "قطن"}.get(crop["t"], crop["t"])
	if g >= 1.0:
		return "احصد %s" % nm
	var extra := ""
	if held.begins_with("waterskin_"):
		extra = " - اسقِ"
	elif held == "rotten_food" and not crop.get("f", false):
		extra = " - سمّد"
	return "%s ينمو %d٪ %s%s" % [nm, int(g * 100), "(مروي)" if crop["w"] > 0.0 else "(يحتاج ماء!)", extra]

func _seed_for(player) -> String:
	var held: String = player.held_item_id()
	if ItemDB.has_tag(held, "seed"):
		return held
	for id in ["wheat_seed", "potato", "cotton_seed"]:
		if player.inventory.count(id) > 0:
			return id
	return ""

func _farm_interact(player) -> void:
	var held: String = player.held_item_id()
	if crop.is_empty():
		var seed := _seed_for(player)
		if seed == "":
			Game.notify("تحتاج بذور قمح أو قطن أو حبة بطاطا", Color(1, 0.8, 0.5))
			return
		player.inventory.remove(seed, 1)
		crop = {"t": ItemDB.get_item(seed).get("plant", "wheat"), "g": 0.0, "w": 0.5, "f": false}
		Sfx.play("pickup", global_position)
		manager.update_crop_visual(self)
		player.stats.add_skill_xp("gathering", 1.0)
		return
	if crop["g"] >= 1.0:
		var out := []
		match crop["t"]:
			"wheat": out = [["wheat", randi_range(3, 5)], ["wheat_seed", randi_range(1, 2)]]
			"potato": out = [["potato", randi_range(3, 5)]]
			"cotton": out = [["cotton", randi_range(4, 6)], ["cotton_seed", randi_range(1, 2)]]
		if crop.get("f", false):
			out[0][1] += 2
		player.receive_items(out, global_position)
		player.stats.add_skill_xp("gathering", 4.0)
		crop = {}
		manager.update_crop_visual(self)
		return
	if held.begins_with("waterskin_"):
		var i: int = player.held_index()
		player.inventory.take_slot(i, 1)
		player.inventory.add("waterskin", 1)
		crop["w"] = 1.0
		Sfx.play("splash", global_position, -6.0)
		Game.notify("سقيت المحصول", Color(0.6, 0.85, 1))
		return
	if held == "rotten_food" and not crop.get("f", false):
		player.inventory.remove("rotten_food", 1)
		crop["f"] = true
		Game.notify("سمّدت الحقل: سينمو أسرع ويعطي محصولاً أكبر", Color(0.7, 1, 0.6))
		return
	Game.notify("المحصول ينمو... اسقه بقربة ماء إن جفّ", Color(0.85, 0.95, 0.8))

func farm_tick(dh: float, raining: bool) -> void:
	if crop.is_empty():
		return
	if raining:
		crop["w"] = 1.0
	if crop["w"] > 0.0 and crop["g"] < 1.0:
		var rate := 1.0 / 44.0 * (1.5 if crop.get("f", false) else 1.0)
		if crop["t"] == "potato":
			rate *= 0.85
		crop["g"] = minf(1.0, crop["g"] + rate * dh)
	crop["w"] = maxf(0.0, crop["w"] - dh / 20.0)

func on_hit(_dmg: float, _kind: String, _tier: int, _attacker, _pos: Vector3) -> void:
	Sfx.play("build", global_position, -8.0)

func _process(dt: float) -> void:
	if fire_fx == null and light == null:
		set_process(false)
		return
	var lit := true
	if def.get("station", "") == "campfire":
		if not infinite_fuel and fuel > 0.0:
			fuel = maxf(0.0, fuel - dt)
		lit = fuel > 0.0 or infinite_fuel
	if fire_fx:
		fire_fx.emitting = lit
	if light:
		_flicker += dt * 9.0
		light.visible = lit
		if def.get("station", "") == "campfire" or def_id == "torch_stand":
			light.light_energy = 1.6 + sin(_flicker) * 0.15 + sin(_flicker * 2.7) * 0.1

func to_data() -> Dictionary:
	var d := {"def": def_id, "xf": _xf_arr(global_transform), "hp": hp, "own": owner_id, "b": b_id, "key": key, "lock": locked, "fuel": fuel, "open": is_open, "water": water}
	if inventory != null:
		d["inv"] = inventory.to_data()
	if not crop.is_empty():
		d["crop"] = crop.duplicate()
	return d

static func _xf_arr(t: Transform3D) -> Array:
	var b := t.basis
	return [b.x.x, b.x.y, b.x.z, b.y.x, b.y.y, b.y.z, b.z.x, b.z.y, b.z.z, t.origin.x, t.origin.y, t.origin.z]

static func arr_xf(a: Array) -> Transform3D:
	if a.size() < 12:
		return Transform3D.IDENTITY
	return Transform3D(Basis(Vector3(a[0], a[1], a[2]), Vector3(a[3], a[4], a[5]), Vector3(a[6], a[7], a[8])), Vector3(a[9], a[10], a[11]))
