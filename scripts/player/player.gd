class_name Player
extends CharacterBody3D
## اللاعب: الحركة، الكاميرا (منظور ثالث/أول)، التفاعل، القتال، الحصاد، الأكل والشرب، السباحة، النوم، الحمولة، وضع البناء.

const WALK := 3.6
const RUN := 6.6
const CROUCH := 1.7
const SWIM := 2.2
const JUMP := 5.2
const GRAVITY := 17.0
const REACH := 3.4

var world: Node
var stats := SurvivalStats.new()
var inventory := Inventory.new(30)
var equipment := {"head": null, "body": null, "legs": null, "feet": null, "back": null}
var sel := 0
var model: HumanModel
var cam_yaw: Node3D
var cam_pitch: Node3D
var spring: SpringArm3D
var camera: Camera3D
var fp_item: Node3D
var torch_light: OmniLight3D
var first_person := false
var input_move := Vector2.ZERO
var attack_held := false
var sprint_on := false
var crouching := false
var swimming := false
var sleeping := false
var bed = null
var spawn_point := Vector3.ZERO
var last_attacker = null
var last_attacked_t := 99.0
var last_target = null
var last_target_t := 99.0
var focus = null
var focus_text := ""
var focus_water := false
var _focus_t := 0.0
var _swing_cd := 0.0
var _pending_hit := -1.0
var _shake := 0.0
var _step_t := 0.0
var _fall_vel := 0.0
var _last_pos := Vector3.ZERO
var _env_t := 0.0
var eff_temp := 20.0
var ambient_temp := 20.0
var shelter := 0.0
var heat := 0.0
var fishing_t := -1.0
var craft_queue: Array = []
var build_mode := false
var build_id := "wood_foundation"
var build_rot := 0
var demolish_mode := false
var build_plan := {}
var ghost: MeshInstance3D
var _ghost_id := ""
var demolish_target = null
var _was_on_floor := true
var _interior := false

func setup(w: Node, pos: Vector3) -> void:
	world = w
	position = pos
	spawn_point = pos
	collision_layer = 2
	collision_mask = 1 | 4 | 8 | 32
	floor_max_angle = deg_to_rad(50.0)
	floor_snap_length = 0.45
	var cs := CollisionShape3D.new()
	var sh := CapsuleShape3D.new()
	sh.radius = 0.33
	sh.height = 1.78
	cs.shape = sh
	cs.position = Vector3(0, 0.89, 0)
	add_child(cs)
	model = HumanModel.new()
	add_child(model)
	var app := {"skin": Color(0.76, 0.56, 0.4), "hair": Color(0.18, 0.12, 0.08), "shirt": Color(0.55, 0.5, 0.42), "pants": Color(0.32, 0.28, 0.22),
		"shoes": Color(0.25, 0.17, 0.1), "female": false, "hair_style": 0, "beard": true, "height": 1.0, "build": 1.05}
	model.build(app)
	cam_yaw = Node3D.new()
	cam_yaw.top_level = true
	add_child(cam_yaw)
	cam_pitch = Node3D.new()
	cam_yaw.add_child(cam_pitch)
	spring = SpringArm3D.new()
	spring.spring_length = 3.2
	spring.collision_mask = 1 | 8 | 32
	spring.margin = 0.2
	var sph := SphereShape3D.new()
	sph.radius = 0.2
	spring.shape = sph
	cam_pitch.add_child(spring)
	camera = Camera3D.new()
	camera.fov = 70.0
	camera.near = 0.06
	camera.far = 1400.0
	spring.add_child(camera)
	camera.position = Vector3(0.45, 0, 0)
	camera.current = true
	fp_item = Node3D.new()
	camera.add_child(fp_item)
	fp_item.position = Vector3(0.28, -0.32, -0.55)
	torch_light = OmniLight3D.new()
	torch_light.light_color = Color(1.0, 0.62, 0.3)
	torch_light.omni_range = 11.0
	torch_light.light_energy = 1.5
	torch_light.position = Vector3(0.3, 1.7, -0.3)
	torch_light.visible = false
	torch_light.shadow_enabled = false
	add_child(torch_light)
	ghost = MeshInstance3D.new()
	ghost.top_level = true
	ghost.visible = false
	ghost.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(ghost)
	stats.died.connect(_on_died)
	stats.skill_up.connect(_on_skill_up)
	stats.fitness_up.connect(_on_fitness_up)
	inventory.changed.connect(_on_inv_changed)
	set_first_person(Game.settings.get("first_person", false))
	_last_pos = position

func _on_skill_up(s: String, l: int) -> void:
	Game.notify("ارتفعت مهارة %s إلى المستوى %d" % [SurvivalStats.SKILL_NAMES[s], l], Color(0.6, 1, 0.8))
	Sfx.play("levelup")

func _on_fitness_up(l: int) -> void:
	Game.notify("لياقتك تحسنت! المستوى %d: تحمّل وسعة حمل أكبر" % l, Color(0.6, 1, 0.8))
	Sfx.play("levelup")

func give_starting_items() -> void:
	inventory.add("torch", 1)
	inventory.add("berries", 6)
	inventory.add("waterskin_clean", 1)
	inventory.add("bandage", 1)
	equipment["body"] = {"id": "cloth_shirt", "n": 1, "d": -1.0, "a": 0.0}
	equipment["legs"] = {"id": "cloth_pants", "n": 1, "d": -1.0, "a": 0.0}
	_refresh_equipment()

func set_first_person(v: bool) -> void:
	first_person = v
	spring.spring_length = 0.0 if v else 3.2
	camera.position = Vector3(0, 0, 0) if v else Vector3(0.45, 0, 0)
	model.visible = not v
	fp_item.visible = v
	_update_held_visual()

# ------------------------------------------------------------------
# مساعدات العناصر
func held_item_id() -> String:
	var s = inventory.slots[sel]
	return s["id"] if s != null else ""

func held_index() -> int:
	return sel

func held_tool_kind() -> String:
	var id := held_item_id()
	return ItemDB.tool_of(id).get("kind", "") if id != "" else ""

func held_tool_tier() -> int:
	return int(ItemDB.tool_of(held_item_id()).get("tier", 0))

func has_tool_kind(k: String) -> bool:
	for s in inventory.slots:
		if s != null and ItemDB.tool_of(s["id"]).get("kind", "") == k:
			return true
	return false

func inventory_index_of(id: String) -> int:
	for i in range(inventory.size()):
		if inventory.slots[i] != null and inventory.slots[i]["id"] == id:
			return i
	return -1

func carry_weight() -> float:
	var w := inventory.total_weight()
	for k in equipment:
		if equipment[k] != null:
			w += ItemDB.weight(equipment[k]["id"])
	return w

func carry_ratio() -> float:
	return carry_weight() / stats.carry_capacity()

func insulation() -> Vector2:
	var ins := 0.0
	var hp := 0.0
	for k in equipment:
		if equipment[k] != null:
			var wr: Dictionary = ItemDB.get_item(equipment[k]["id"]).get("wear", {})
			ins += wr.get("insul", 0.0)
			hp += wr.get("heat", 0.0)
	return Vector2(ins, hp)

func armor() -> float:
	var a := 0.0
	for k in equipment:
		if equipment[k] != null:
			a += ItemDB.get_item(equipment[k]["id"]).get("wear", {}).get("armor", 0.0)
	return a

func receive_items(list: Array, pos: Vector3) -> void:
	var dropped := []
	for e in list:
		var left := inventory.add(e[0], e[1])
		var got: int = e[1] - left
		if got > 0:
			Game.notify("+%d %s" % [got, ItemDB.name_of(e[0])], Color(0.85, 1, 0.75))
		if left > 0:
			dropped.append({"id": e[0], "n": left, "d": -1.0, "a": 0.0})
	if not dropped.is_empty():
		world.spawn_loot(global_position + Vector3(0, 0.2, 0), dropped, "أغراض على الأرض")
		Game.notify("حقيبتك ممتلئة! سقطت بعض الأغراض على الأرض", Color(1, 0.7, 0.4))

func _on_inv_changed() -> void:
	_update_held_visual()

func select_slot(i: int) -> void:
	sel = clampi(i, 0, 5)
	_update_held_visual()
	Sfx.play("click")

func _update_held_visual() -> void:
	var id := held_item_id()
	model.set_held(id)
	for c in fp_item.get_children():
		c.queue_free()
	if id != "" and first_person:
		var key := MeshFactory.held_key(id)
		if key != "":
			var mi := MeshInstance3D.new()
			mi.mesh = MeshFactory.get_mesh(key)
			mi.rotation = Vector3(-0.3, 0.2, -0.25)
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			fp_item.add_child(mi)
	torch_light.visible = held_tool_kind() == "torch"

func equip_from_slot(i: int) -> void:
	var s = inventory.slots[i]
	if s == null:
		return
	var wr: Dictionary = ItemDB.get_item(s["id"]).get("wear", {})
	if wr.is_empty():
		return
	var slot: String = wr["slot"]
	var old = equipment[slot]
	equipment[slot] = inventory.take_slot(i, 1)
	if old != null:
		inventory.add_stack(old)
	_refresh_equipment()
	Sfx.play("pickup")

func unequip(slot: String) -> void:
	var it = equipment.get(slot)
	if it == null:
		return
	if inventory.add_stack(it) > 0:
		Game.notify("لا مكان في الحقيبة", Color(1, 0.7, 0.4))
		return
	equipment[slot] = null
	_refresh_equipment()

func _refresh_equipment() -> void:
	var cb := 0.0
	for k in equipment:
		if equipment[k] != null:
			cb += ItemDB.get_item(equipment[k]["id"]).get("wear", {}).get("carry", 0.0)
	stats.carry_bonus = cb
	model.set_equipment(equipment)

## استهلاك عنصر (أكل/شرب/علاج)
func use_slot(i: int) -> void:
	var s = inventory.slots[i]
	if s == null:
		return
	var it := ItemDB.get_item(s["id"])
	if it.has("wear"):
		equip_from_slot(i)
		return
	if it.has("food"):
		var f: Dictionary = it["food"]
		inventory.take_slot(i, 1)
		if it.has("returns"):
			inventory.add(it["returns"], 1)
		var msg := stats.consume_food(f)
		Sfx.play("drink" if f.get("t", 0) > f.get("h", 0) else "eat")
		Game.notify("%s %s" % ["شربت" if f.get("t", 0) > f.get("h", 0) else "أكلت", it["name"]], Color(0.9, 1, 0.8))
		if msg != "":
			Game.notify(msg, Color(1, 0.8, 0.4))
		return
	if it.has("med"):
		var md: Dictionary = it["med"]
		inventory.take_slot(i, 1)
		stats.heal(md.get("hp", 0.0))
		for c in md.get("cure", []):
			var m := stats.cure(c)
			if m != "":
				Game.notify(m, Color(0.7, 1, 0.7))
		Sfx.play("pickup")
		Game.notify("استخدمت %s" % it["name"], Color(0.8, 1, 0.8))

func drop_slot(i: int, n := -1) -> void:
	var st := inventory.take_slot(i, n)
	if st.is_empty():
		return
	world.spawn_loot(global_position + -global_transform.basis.z * 0.8 + Vector3(0, 0.2, 0), [st], "أغراض على الأرض")

# ------------------------------------------------------------------
func add_look(d: Vector2) -> void:
	var sens: float = Game.settings.get("sensitivity", 1.0)
	cam_yaw.rotation.y -= d.x * 0.0045 * sens
	var inv := -1.0 if Game.settings.get("invert_y", false) else 1.0
	cam_pitch.rotation.x = clampf(cam_pitch.rotation.x - d.y * 0.0045 * sens * inv, -1.35, 1.15)

func _unhandled_input(e: InputEvent) -> void:
	if Game.ui_open:
		return
	if e is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		add_look(e.relative * 0.6)
	if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_WHEEL_UP:
		select_slot((sel + 5) % 6)
	if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_WHEEL_DOWN:
		select_slot((sel + 1) % 6)
	if e.is_action_pressed("jump"):
		press("jump")
	if e.is_action_pressed("interact"):
		press("interact")
	if e.is_action_pressed("crouch"):
		press("crouch")
	if e.is_action_pressed("sprint"):
		sprint_on = true
	if e.is_action_released("sprint"):
		sprint_on = false
	if e.is_action_pressed("rotate"):
		press("rotate")
	if e.is_action_pressed("camera"):
		press("camera")
	for i in range(6):
		if e.is_action_pressed("slot_%d" % (i + 1)):
			select_slot(i)

func press(action: String) -> void:
	if stats.dead:
		return
	if sleeping:
		wake_up()
		return
	match action:
		"jump":
			if swimming:
				velocity.y = 3.0
			elif is_on_floor() and carry_ratio() < 1.5:
				if stats.use_stamina(9.0):
					velocity.y = JUMP
					stats.add_fitness_xp(0.3)
					crouching = false
		"interact":
			if build_mode:
				return
			_do_interact()
		"crouch":
			crouching = not crouching
		"sprint":
			sprint_on = not sprint_on
		"attack":
			if build_mode:
				_build_action()
			else:
				try_attack()
		"rotate":
			build_rot = (build_rot + 1) % 24
		"camera":
			set_first_person(not first_person)
			Game.set_setting("first_person", first_person)

func _do_interact() -> void:
	if focus != null and is_instance_valid(focus) and focus.has_method("interact"):
		focus.interact(self)
		return
	if focus_water:
		_water_interact()

func _water_interact() -> void:
	var i := inventory_index_of("waterskin")
	if held_item_id() == "waterskin" or (i >= 0 and held_tool_kind() != "rod"):
		if held_item_id() == "waterskin":
			i = sel
		inventory.take_slot(i, 1)
		inventory.add("waterskin_dirty", 1)
		Sfx.play("splash", global_position, -4.0)
		Game.notify("ملأت القربة بماء عكِر. اغلِه على النار قبل شربه", Color(0.7, 0.85, 1))
		return
	if held_tool_kind() == "rod":
		_start_fishing()
		return
	stats.thirst = minf(100.0, stats.thirst + 22.0)
	Sfx.play("drink")
	if randf() < 0.22:
		stats.sick = maxf(stats.sick, randf_range(4.0, 8.0))
		Game.notify("الماء كان ملوثاً... تشعر بالغثيان", Color(1, 0.75, 0.4))
	else:
		Game.notify("شربت من الماء", Color(0.6, 0.85, 1))

func _start_fishing() -> void:
	if fishing_t >= 0.0:
		return
	fishing_t = randf_range(4.0, 10.0) / (1.0 + stats.skill_level("gathering") * 0.05)
	Game.notify("ألقيت الصنارة... انتظر", Color(0.7, 0.85, 1))

func try_attack() -> void:
	if _swing_cd > 0.0 or sleeping or stats.dead:
		return
	var id := held_item_id()
	var it := ItemDB.get_item(id) if id != "" else {}
	if it.has("food") or it.has("med"):
		_swing_cd = 0.6
		use_slot(sel)
		return
	if focus_water and (id == "waterskin" or held_tool_kind() == "rod"):
		_swing_cd = 0.5
		_water_interact()
		return
	var kind := held_tool_kind()
	if kind == "bow":
		_shoot_bow()
		return
	if kind == "rod":
		Game.notify("انظر إلى الماء لتصطاد", Color(0.8, 0.9, 1))
		_swing_cd = 0.5
		return
	var td := ItemDB.tool_of(id)
	var spd: float = td.get("speed", 0.75)
	if not stats.use_stamina(5.0 + ItemDB.weight(id) * 1.5):
		Game.notify("أنت منهك! انتظر لتستعيد قدرتك", Color(1, 0.7, 0.4))
		_swing_cd = 0.6
		return
	_swing_cd = spd
	model.play_swing("thrust" if kind == "spear" else "chop")
	_pending_hit = 0.24
	if first_person and fp_item.get_child_count() > 0:
		var tw := create_tween()
		tw.tween_property(fp_item, "rotation:x", -0.9, 0.12)
		tw.tween_property(fp_item, "rotation:x", 0.0, 0.2)

func _apply_hit() -> void:
	var id := held_item_id()
	var td := ItemDB.tool_of(id)
	var kind: String = td.get("kind", "hand") if id != "" else "hand"
	var dmg: float = td.get("dmg", 3.0) if id != "" else 3.0
	var power: float = td.get("power", dmg * 0.5) if id != "" else 1.0
	var tier: int = int(td.get("tier", 0))
	var reach: float = td.get("range", 2.4) + 0.4
	var target = null
	var hp := Vector3.ZERO
	var res := _ray_from_camera(reach + spring.get_hit_length() + 0.5, 4 | 8 | 16 | 32 | 64)
	if not res.is_empty() and res["position"].distance_to(global_position + Vector3(0, 1.0, 0)) < reach + 0.6:
		target = res["collider"]
		hp = res["position"]
	if target == null or not target.has_method("on_hit"):
		target = null
		var best := reach + 0.3
		var fwd := -camera.global_transform.basis.z
		fwd.y = 0
		fwd = fwd.normalized()
		var cands: Array = world.ai.active_npcs + world.ai.animals
		for c in cands:
			if not is_instance_valid(c) or c.dead:
				continue
			var to: Vector3 = c.global_position - global_position
			to.y = 0
			var d := to.length()
			if d < best and d > 0.01 and fwd.dot(to / d) > 0.55:
				best = d
				target = c
				hp = c.global_position + Vector3(0, 0.8, 0)
	if target == null:
		return
	if target is ResourceBody:
		target.on_hit(power, kind, tier, self, hp)
		_wear_tool(1.0)
		return
	if target.has_method("take_damage") or target is NPC or target is Animal:
		var final := dmg * (1.0 + stats.skill_level("hunting") * 0.03)
		target.on_hit(final, kind, tier, self, hp)
		last_target = target
		last_target_t = 0.0
		stats.add_skill_xp("hunting", 1.0)
		stats.add_fitness_xp(0.3)
		_wear_tool(1.0)
		return
	target.on_hit(power, kind, tier, self, hp)

func _wear_tool(a: float) -> void:
	var id := held_item_id()
	if id == "" or ItemDB.max_dur(id) < 0.0:
		return
	if inventory.damage_slot(sel, a):
		Game.notify("انكسرت %s!" % ItemDB.name_of(id), Color(1, 0.5, 0.3))
		Sfx.play("mine", global_position, 0.0, 0.3)

func _shoot_bow() -> void:
	var ai_ := ""
	for a in ["obsidian_arrow", "arrow"]:
		if inventory.count(a) > 0:
			ai_ = a
			break
	if ai_ == "":
		Game.notify("ليس لديك سهام", Color(1, 0.7, 0.4))
		_swing_cd = 0.5
		return
	if not stats.use_stamina(6.0):
		return
	inventory.remove(ai_, 1)
	_swing_cd = 1.0
	var ar := Arrow.new()
	world.add_child(ar)
	var dir := -camera.global_transform.basis.z
	var from := global_position + Vector3(0, 1.5, 0) + dir * 0.6
	var dmg: float = ItemDB.get_item(ai_).get("dmg", 12.0) + ItemDB.tool_of("bow").get("dmg", 8.0)
	dmg *= 1.0 + stats.skill_level("hunting") * 0.04
	ar.launch(from, dir, 45.0, dmg, self)
	Sfx.play("bow", global_position)
	model.play_swing("thrust")
	_wear_tool(1.0)

func _ray_from_camera(dist: float, mask: int) -> Dictionary:
	var from := camera.global_position
	var to := from - camera.global_transform.basis.z * dist
	var q := PhysicsRayQueryParameters3D.create(from, to, mask)
	q.exclude = [get_rid()]
	q.collide_with_areas = false
	return get_world_3d().direct_space_state.intersect_ray(q)

func take_damage(dmg: float, attacker) -> void:
	if stats.dead:
		return
	var a := armor()
	var final := dmg * (1.0 - a / (a + 30.0))
	var cause := "هجوم"
	if attacker is Animal:
		cause = attacker.sp["name"]
	elif attacker is NPC:
		cause = attacker.data["name"]
	stats.damage(final, cause, attacker is Animal or (attacker is NPC and attacker.data["weapon"] != ""))
	last_attacker = attacker
	last_attacked_t = 0.0
	_shake = 0.35
	model.flash_hit()
	Sfx.play("hurt")
	if world.hud:
		world.hud.flash_damage()
	if sleeping:
		wake_up()
		Game.notify("استيقظت على هجوم!", Color(1, 0.4, 0.3))
	if stats.bleeding > 0.0 and randf() < 0.3:
		Game.notify("أنت تنزف! استخدم ضمادة", Color(1, 0.3, 0.3))

func on_hit(dmg: float, _k, _t, attacker, _p) -> void:
	take_damage(dmg, attacker)

func _on_died(cause: String) -> void:
	sleeping = false
	world.time_scale = 1.0
	model.state = "dead"
	var items := []
	for i in range(inventory.size()):
		if inventory.slots[i] != null:
			items.append(inventory.slots[i].duplicate())
	inventory.clear()
	if not items.is_empty():
		world.spawn_loot(global_position + Vector3(0, 0.3, 0), items, "متاعك (مكان موتك)")
		world.ai.add_marker(global_position, "مكان موتك", Color(1, 0.3, 0.3))
	world.ai.log_event("متَّ بسبب: %s" % cause)
	world.hud.show_death(cause)

func respawn() -> void:
	stats.dead = false
	stats.health = 60.0
	stats.hunger = maxf(stats.hunger, 50.0)
	stats.thirst = maxf(stats.thirst, 50.0)
	stats.body_temp = 37.0
	stats.stamina = 60.0
	stats.bleeding = 0.0
	stats.poisoned = 0.0
	stats.energy = maxf(stats.energy, 50.0)
	var p := spawn_point
	if bed != null and is_instance_valid(bed):
		p = bed.global_position + Vector3(0, 0.5, 1.6)
	global_position = p + Vector3(0, 0.6, 0)
	velocity = Vector3.ZERO
	model.state = "idle"
	world.terrain.generate_now(global_position, 1)

func sleep_in(b) -> void:
	for n in world.ai.active_npcs:
		if is_instance_valid(n) and not n.dead and n.hostile_to_player and n.global_position.distance_to(global_position) < 30.0:
			Game.notify("لا يمكنك النوم والأعداء قريبون!", Color(1, 0.5, 0.4))
			return
	for a in world.ai.animals:
		if is_instance_valid(a) and not a.dead and a.state == "chase" and a.target == self:
			Game.notify("لا يمكنك النوم وأنت مطارد!", Color(1, 0.5, 0.4))
			return
	if b != null:
		bed = b
		spawn_point = b.global_position
		Game.notify("تم تحديد نقطة الإحياء عند هذا السرير", Color(0.8, 0.9, 1))
	sleeping = true
	set_meta("bed_q", b.def.get("bed", 0.5) if b != null else 0.35)
	if b != null:
		global_position = b.global_position + Vector3(0, 0.25, 0)
		rotation.y = b.rotation.y
	world.time_scale = 45.0
	model.state = "sleep"
	world.hud.show_sleep(true)

func wake_up() -> void:
	if not sleeping:
		return
	sleeping = false
	world.time_scale = 1.0
	model.state = "idle"
	if bed != null and is_instance_valid(bed):
		global_position = bed.global_position + Vector3(0, 0.6, 1.4).rotated(Vector3.UP, bed.rotation.y)
	world.hud.show_sleep(false)

# ------------------------------------------------------------------
func _physics_process(dt: float) -> void:
	if world == null:
		return
	var game_dt: float = dt * world.time_scale
	last_attacked_t += dt
	last_target_t += dt
	_swing_cd -= dt
	if _pending_hit >= 0.0:
		_pending_hit -= dt
		if _pending_hit < 0.0:
			_apply_hit()
	if stats.dead:
		velocity = Vector3(0, velocity.y - GRAVITY * dt, 0)
		move_and_slide()
		_update_camera(dt)
		return
	# --- المدخلات
	var mv := input_move
	if mv.length() < 0.05 and not Game.ui_open:
		mv = Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	if Game.ui_open or sleeping:
		mv = Vector2.ZERO
	if attack_held and not Game.ui_open and not build_mode:
		try_attack()
	if not Game.ui_open and Input.is_action_pressed("attack") and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED and not build_mode:
		try_attack()
	# --- الحمولة
	var ratio := carry_ratio()
	var load_mult := 1.0
	if ratio > 1.0:
		load_mult = lerpf(1.0, 0.5, clampf((ratio - 1.0) / 0.5, 0.0, 1.0))
		if ratio > 1.5:
			load_mult = lerpf(0.5, 0.15, clampf((ratio - 1.5) / 0.5, 0.0, 1.0))
		if ratio >= 2.0:
			load_mult = 0.0
	swimming = global_position.y < -1.15
	var can_sprint := sprint_on and not stats.exhausted and ratio <= 1.15 and not crouching and not swimming and stats.stamina > 1.0
	var speed := WALK
	if crouching:
		speed = CROUCH
	elif can_sprint and mv.length() > 0.1:
		speed = RUN * (1.0 + stats.fitness_level() * 0.008)
	if swimming:
		speed = SWIM
	if stats.energy < 10.0:
		speed *= 0.8
	if stats.health < 25.0:
		speed *= 0.85
	speed *= load_mult
	var basis_y := Basis(Vector3.UP, cam_yaw.rotation.y)
	var dir := basis_y * Vector3(mv.x, 0, mv.y)
	if dir.length() > 1.0:
		dir = dir.normalized()
	var target_v := dir * speed
	var accel := 10.0 if is_on_floor() or swimming else 3.0
	velocity.x = lerpf(velocity.x, target_v.x, clampf(accel * dt, 0.0, 1.0))
	velocity.z = lerpf(velocity.z, target_v.z, clampf(accel * dt, 0.0, 1.0))
	if swimming:
		var depth := -global_position.y
		velocity.y = lerpf(velocity.y, (depth - 1.3) * 3.0, dt * 3.0)
	elif not is_on_floor():
		velocity.y -= GRAVITY * dt
		_fall_vel = minf(_fall_vel, velocity.y)
	if sleeping:
		velocity = Vector3.ZERO
	move_and_slide()
	if is_on_floor() and not _was_on_floor:
		if _fall_vel < -13.0:
			var fd := (absf(_fall_vel) - 13.0) * 6.0
			stats.damage(fd, "السقوط")
			_shake = 0.3
			Sfx.play("hit")
			if fd > 10.0:
				Game.notify("سقطت من ارتفاع وتأذيت!", Color(1, 0.5, 0.4))
		_fall_vel = 0.0
	_was_on_floor = is_on_floor()
	if global_position.y < -40.0:
		global_position = Vector3(global_position.x, world.gen.height_at(global_position.x, global_position.z) + 2.0, global_position.z)
	# --- الدوران والتحريك
	var hv := Vector2(velocity.x, velocity.z).length()
	if not sleeping:
		if first_person or build_mode or (attack_held and _swing_cd > 0.0):
			rotation.y = lerp_angle(rotation.y, cam_yaw.rotation.y, clampf(dt * 14.0, 0.0, 1.0))
		elif hv > 0.3:
			rotation.y = lerp_angle(rotation.y, atan2(-velocity.x, -velocity.z), clampf(dt * 10.0, 0.0, 1.0))
	model.speed = hv
	if not sleeping:
		model.state = "swim" if swimming else ("crouch" if crouching else "idle")
	# --- اللياقة
	var moved := Vector2(global_position.x - _last_pos.x, global_position.z - _last_pos.z).length()
	_last_pos = global_position
	if moved < 2.0:
		if speed > WALK and hv > 4.0:
			stats.add_fitness_xp(moved * 0.05)
		elif ratio > 0.8 and hv > 1.0:
			stats.add_fitness_xp(moved * 0.035)
		if swimming:
			stats.add_fitness_xp(moved * 0.06)
	# خطوات
	if is_on_floor() and hv > 1.0:
		_step_t -= dt * hv * 0.55
		if _step_t <= 0.0:
			_step_t = 1.0
			Sfx.play("step", global_position, -12.0 + (4.0 if speed > WALK else 0.0))
	# --- البيئة والمؤشرات
	_env_t -= dt
	if _env_t <= 0.0:
		_env_t = 0.5
		_update_environment()
	var dh: float = game_dt * 24.0 / (float(Game.settings.get("day_minutes", 24.0)) * 60.0)
	var raining: bool = world.sky.rain > 0.2 and not world.sky.snowing and shelter < 0.2
	stats.update(dt, dh, {"sprint": speed > WALK + 0.5 and hv > 3.0, "moving": hv > 0.5, "swim": swimming, "sleep": sleeping,
		"eff_temp": eff_temp, "carry": ratio, "work": _swing_cd > 0.0, "getting_wet": swimming or raining, "near_fire": heat,
		"bed_quality": get_meta("bed_q", 0.35)})
	if sleeping:
		var h: float = world.sky.hour_of_day()
		if stats.energy >= 99.5 and (h > 5.5 and h < 11.0) or stats.energy >= 100.0 and h > 6.0 and h < 20.0:
			wake_up()
			Game.notify("استيقظت بنشاط", Color(0.9, 0.95, 1))
		elif stats.hunger < 8.0 or stats.thirst < 8.0:
			wake_up()
			Game.notify("استيقظت من شدة الجوع أو العطش", Color(1, 0.7, 0.4))
	# تقادم الطعام
	var spoiled := inventory.age_items(dh, 1.0 if eff_temp > 8.0 else 0.4)
	for nm in spoiled:
		Game.notify("فسد %s في حقيبتك" % nm, Color(0.8, 0.8, 0.5))
	# المشعل يحترق
	if held_tool_kind() == "torch":
		if inventory.damage_slot(sel, dt):
			Game.notify("انطفأت الشعلة", Color(1, 0.7, 0.4))
	# الصيد
	if fishing_t >= 0.0:
		if held_tool_kind() != "rod" or not focus_water or hv > 1.0:
			fishing_t = -1.0
			Game.notify("توقفت عن الصيد", Color(0.8, 0.8, 0.8))
		else:
			fishing_t -= dt
			if fishing_t < 0.0:
				if randf() < 0.65 + stats.skill_level("gathering") * 0.02:
					receive_items([["raw_fish", 1]], global_position)
					Sfx.play("splash", global_position)
					stats.add_skill_xp("gathering", 3.0)
				else:
					Game.notify("أفلتت السمكة!", Color(0.9, 0.9, 0.8))
				_wear_tool(1.0)
	# الحمم
	var vd := Vector2(global_position.x, global_position.z).distance_to(world.gen.volcano)
	if vd < 45.0 and global_position.y < world.terrain.lava_y + 1.2:
		stats.damage(40.0 * dt, "الحمم البركانية")
		_shake = 0.2
	# الصناعة
	_process_crafting(dt)
	# التركيز
	_focus_t -= dt
	if _focus_t <= 0.0:
		_focus_t = 0.1
		_update_focus()
	if build_mode:
		_update_build()
	_update_camera(dt)

func _update_environment() -> void:
	var p := global_position
	ambient_temp = world.temperature_at(p)
	shelter = world.build.shelter_quality(p)
	heat = world.build.heat_at(p)
	var t := ambient_temp
	t = lerpf(t, 18.0, shelter * 0.75)
	t += heat * 20.0
	if held_tool_kind() == "torch":
		t += 3.0
	if shelter < 0.2:
		t -= world.sky.wind * 1.2
	t -= stats.wet * 7.0
	var ins := insulation()
	if t < 18.0:
		eff_temp = minf(t + ins.x * 1.25, maxf(t, 21.0))
	elif t > 26.0:
		eff_temp = t - ins.y * 0.8 + ins.x * 0.45
	else:
		eff_temp = t + ins.x * 0.15
	_interior = shelter > 0.5

func _update_focus() -> void:
	focus = null
	focus_text = ""
	focus_water = false
	if build_mode:
		return
	var res := _ray_from_camera(REACH + spring.get_hit_length() + 0.5, 1 | 4 | 8 | 16 | 32 | 64)
	var chest := global_position + Vector3(0, 1.1, 0)
	if not res.is_empty():
		var c = res["collider"]
		var hp: Vector3 = res["position"]
		if hp.distance_to(chest) < REACH + 0.4 and c != null and c.has_method("get_interact_text") and c != self:
			var t: String = c.get_interact_text(self)
			if t != "":
				focus = c
				focus_text = t
				return
	# الماء
	var from := camera.global_position
	var dir := -camera.global_transform.basis.z
	if dir.y < -0.05 or swimming:
		var t2 := -from.y / dir.y if absf(dir.y) > 0.001 else 0.0
		var wp := from + dir * t2
		if swimming:
			wp = global_position
		if (t2 > 0.0 and wp.distance_to(chest) < REACH + 1.0) or swimming:
			if world.gen.height_at(wp.x, wp.z) < -0.15 and (res.is_empty() or res["position"].y < 0.0 or swimming):
				focus_water = true
				if held_tool_kind() == "rod":
					focus_text = "اصطد سمكاً" if fishing_t < 0.0 else "الصنارة في الماء..."
				elif inventory.count("waterskin") > 0:
					focus_text = "املأ القربة من الماء"
				else:
					focus_text = "اشرب من الماء"

func _update_camera(dt: float) -> void:
	var head_h := 1.62 if not crouching else 1.15
	if swimming:
		head_h = 1.45
	if sleeping or stats.dead:
		head_h = 0.6
	var target := global_position + Vector3(0, head_h, 0)
	cam_yaw.global_position = cam_yaw.global_position.lerp(target, clampf(dt * 18.0, 0.0, 1.0)) if cam_yaw.global_position.distance_to(target) < 5.0 else target
	if _shake > 0.0:
		_shake -= dt
		camera.h_offset = randf_range(-0.05, 0.05) * _shake * 4.0
		camera.v_offset = randf_range(-0.05, 0.05) * _shake * 4.0
	else:
		camera.h_offset = 0.0
		camera.v_offset = 0.0
	if first_person and model.speed > 0.5 and is_on_floor():
		camera.v_offset += sin(Time.get_ticks_msec() * 0.012) * 0.025
	spring.spring_length = 0.0 if first_person else (2.4 if build_mode else 3.2)

# ------------------------------------------------------------------
# الصناعة
func can_craft(r: Dictionary, mult := 1) -> String:
	if not inventory.has_all(r["needs"], mult):
		return "تنقصك المكونات"
	if not world.build.station_near(global_position, r["station"]):
		return "تحتاج %s قريباً" % RecipeDB.STATION_NAMES.get(r["station"], r["station"])
	return ""

func craft(r: Dictionary, mult := 1) -> bool:
	if can_craft(r, mult) != "":
		return false
	for k in r["needs"]:
		inventory.remove_key(k, r["needs"][k] * mult)
	var t: float = r["time"] / (1.0 + stats.skill_level("crafting") * 0.06)
	craft_queue.append({"r": r, "t": t * mult, "total": t * mult, "m": mult})
	Sfx.play("click")
	return true

func _process_crafting(dt: float) -> void:
	if craft_queue.is_empty():
		return
	var q: Dictionary = craft_queue[0]
	q["t"] -= dt
	if q["t"] <= 0.0:
		craft_queue.pop_front()
		var r: Dictionary = q["r"]
		var outs := [[r["out"], r["n"] * q["m"]]]
		for k in r.get("extra_out", {}):
			outs.append([k, r["extra_out"][k] * q["m"]])
		receive_items(outs, global_position)
		stats.add_skill_xp("crafting", 2.0 * q["m"])
		Sfx.play("craft")

# ------------------------------------------------------------------
# البناء
func set_build_mode(on: bool) -> void:
	build_mode = on
	ghost.visible = false
	demolish_target = null
	if on and inventory.count("hammer") == 0:
		Game.notify("تحتاج مطرقة البناء (اصنعها يدوياً من حجر وعيدان وحبل)", Color(1, 0.8, 0.5))

func _update_build() -> void:
	ghost.visible = false
	demolish_target = null
	var res := _ray_from_camera(14.0, 1 | 32)
	if demolish_mode:
		if not res.is_empty() and res["collider"] is BuildPiece and res["collider"].owner_id == "player":
			demolish_target = res["collider"]
			ghost.mesh = world.build.piece_mesh(demolish_target.def_id)
			ghost.global_transform = demolish_target.global_transform
			ghost.material_override = MeshFactory.mat("ghost_bad")
			ghost.visible = true
			_ghost_id = ""
		return
	var aim: Vector3
	var nrm := Vector3.UP
	if res.is_empty():
		aim = camera.global_position - camera.global_transform.basis.z * 6.0
		aim.y = world.gen.height_at(aim.x, aim.z)
	else:
		aim = res["position"]
		nrm = res["normal"]
	if aim.distance_to(global_position) > 9.0:
		var d := aim - global_position
		aim = global_position + d.normalized() * 9.0
		aim.y = world.gen.height_at(aim.x, aim.z)
	build_plan = world.build.plan(build_id, aim, nrm, cam_yaw.rotation.y + PI, build_rot)
	if _ghost_id != build_id:
		_ghost_id = build_id
		ghost.mesh = world.build.piece_mesh(build_id)
	if build_plan.has("xf"):
		ghost.global_transform = build_plan["xf"]
		ghost.material_override = MeshFactory.mat("ghost_ok" if build_plan.get("ok", false) else "ghost_bad")
		ghost.visible = true

func _build_action() -> void:
	if demolish_mode:
		if demolish_target != null and is_instance_valid(demolish_target):
			world.build.demolish(demolish_target)
			demolish_target = null
		return
	if build_plan.get("ok", false):
		var p = world.build.place(build_id, build_plan)
		if p != null:
			_wear_hammer()
	else:
		Game.notify(build_plan.get("reason", "لا يمكن البناء هنا"), Color(1, 0.6, 0.4))

func _wear_hammer() -> void:
	for i in range(inventory.size()):
		var s = inventory.slots[i]
		if s != null and s["id"] == "hammer":
			if inventory.damage_slot(i, 1.0):
				Game.notify("انكسرت مطرقة البناء!", Color(1, 0.5, 0.3))
			return

func build_status() -> String:
	if demolish_mode:
		return "وجّه نحو قطعة لهدمها (تسترجع 50٪)" if demolish_target == null else "اهدم: %s" % demolish_target.display_name()
	var d := BuildDB.get_piece(build_id)
	var t := "%s - %s" % [d.get("name", ""), BuildDB.cost_text(build_id)]
	if not build_plan.get("ok", false):
		t += "\n" + str(build_plan.get("reason", ""))
	return t

# ------------------------------------------------------------------
func to_data() -> Dictionary:
	var eq := {}
	for k in equipment:
		eq[k] = equipment[k].duplicate() if equipment[k] != null else null
	var cq := []
	for q in craft_queue:
		cq.append({"out": q["r"]["out"], "n": q["r"]["n"] * q["m"]})
	return {"pos": Game.arr3(global_position), "yaw": cam_yaw.rotation.y, "stats": stats.to_data(), "inv": inventory.to_data(), "eq": eq, "sel": sel, "spawn": Game.arr3(spawn_point), "queue": cq}

func from_data(d: Dictionary) -> void:
	global_position = Game.v3(d.get("pos", [0, 10, 0]))
	cam_yaw.rotation.y = float(d.get("yaw", 0.0))
	stats.from_data(d.get("stats", {}))
	inventory.from_data(d.get("inv", []))
	var eq: Dictionary = d.get("eq", {})
	for k in equipment:
		var e = eq.get(k)
		equipment[k] = {"id": str(e["id"]), "n": 1, "d": float(e.get("d", -1.0)), "a": 0.0} if e is Dictionary and ItemDB.exists(str(e.get("id", ""))) else null
	sel = int(d.get("sel", 0))
	spawn_point = Game.v3(d.get("spawn", Game.arr3(global_position)))
	for q in d.get("queue", []):
		inventory.add(str(q["out"]), int(q["n"]))
	_refresh_equipment()
	_update_held_visual()
