class_name LootBag
extends StaticBody3D
## كيس أغراض على الأرض (فائض الحمولة، متاع الموتى، محتويات الصناديق المهدومة).

var inventory: Inventory
var title := "أغراض"
var age := 0.0
var owner_id := "loot"
var def := {"name": "كيس"}

func setup(items: Array, nm: String) -> void:
	title = nm
	inventory = Inventory.new(36)
	for s in items:
		inventory.add_stack(s)
	collision_layer = 64
	collision_mask = 0
	var cs := CollisionShape3D.new()
	var sh := SphereShape3D.new()
	sh.radius = 0.45
	cs.shape = sh
	cs.position = Vector3(0, 0.3, 0)
	add_child(cs)
	var mi := MeshInstance3D.new()
	mi.mesh = MeshFactory.get_mesh("loot_bag")
	add_child(mi)
	inventory.changed.connect(_on_changed)

func display_name() -> String:
	return title

func is_secure() -> bool:
	return false

func mark_tampered() -> void:
	pass

func _on_changed() -> void:
	if inventory.is_empty():
		queue_free()

func get_interact_text(_p) -> String:
	return "افتح: %s" % title

func interact(_p) -> void:
	Game.hud.open_storage(self)

func on_hit(_a, _b, _c, _d, _e) -> void:
	pass

func _process(dt: float) -> void:
	age += dt
	if age > 2400.0:
		queue_free()

func to_data() -> Dictionary:
	return {"pos": Game.arr3(global_position), "title": title, "inv": inventory.to_data(), "age": age}
