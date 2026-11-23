class_name ItemSystem
extends Node
## Items: Bramble Bomb, Homing Hornet, Thorn Trap, Bubble Shield, Spark Canister.
## Drops are weighted by race position; 10 amber "charges" items.

signal item_changed(kart: Kart, item: String)

const NAMES := {"bomb": "Bramble Bomb", "hornet": "Homing Hornet", "trap": "Thorn Trap", "shield": "Bubble Shield", "spark": "Spark Canister"}

var race: RaceManager
var _held := {}
var world: Node3D


func _ready() -> void:
	add_to_group("item_system")


func register(k: Kart) -> void:
	_held[k] = ""
	k.item_requested.connect(func() -> void: use(k))


func item_of(k: Kart) -> String:
	return _held.get(k, "")


func grant_item(k: Kart) -> void:
	if _held.get(k, "") != "":
		return
	var pos := race.position_of(k) if race else 1
	var n := race.karts.size() if race else 8
	var w: Dictionary
	if pos == 1:
		w = {"trap": 40, "shield": 30, "bomb": 20, "spark": 10}
	elif pos >= n - 1:
		w = {"spark": 40, "hornet": 35, "bomb": 15, "shield": 10}
	else:
		w = {"bomb": 30, "hornet": 25, "spark": 20, "trap": 15, "shield": 10}
	var total := 0
	for key in w:
		total += int(w[key])
	var r := randi() % total
	var pick := "spark"
	for key in w:
		r -= int(w[key])
		if r < 0:
			pick = key
			break
	_held[k] = pick
	item_changed.emit(k, pick)


func use(k: Kart) -> void:
	var it: String = _held.get(k, "")
	if it == "" or k.frozen or k.spin_time > 0.0:
		return
	var charged := k.amber >= 10
	_held[k] = ""
	item_changed.emit(k, "")
	match it:
		"spark":
			k.add_reserve(3.0 if charged else 2.0, &"item", 2 if charged else 1)
			if k.is_player:
				Sfx.play("boost")
		"shield":
			k.shielded = true
			if k.is_player:
				Sfx.play("shield")
			if not charged:
				get_tree().create_timer(10.0, false).timeout.connect(func() -> void: k.shielded = false)
		"trap":
			var tr := ThornTrap.make(charged)
			world.add_child(tr)
			tr.global_position = k.global_position - k.heading() * 2.4
			tr.owner_kart = k
		"bomb":
			var b := BrambleBomb.make(charged)
			world.add_child(b)
			b.global_position = k.global_position + Vector3.UP * 1.0 + k.heading() * 1.5
			b.velocity = k.velocity + k.heading() * 18.0 + Vector3.UP * 6.5
			b.owner_kart = k
			if k.is_player:
				Sfx.play("fire")
		"hornet":
			var h := HomingHornet.make(charged)
			world.add_child(h)
			h.global_position = k.global_position + Vector3.UP * 1.2 + k.heading() * 1.6
			h.owner_kart = k
			h.race = race
			h.target = _hornet_target(k)
			h.dir = k.heading()
			if k.is_player:
				Sfx.play("fire", null, 1.3)


func _hornet_target(k: Kart) -> Kart:
	if race == null:
		return null
	var pos := race.position_of(k)
	if pos > 1:
		return race.kart_at_position(pos - 1)
	return null


static func hit_kart(k: Kart, strength := 1.0) -> void:
	if k.shielded:
		k.shielded = false
		if k.is_player:
			Sfx.play("shield", null, 0.7)
		return
	k.spin_out(1.0 * strength)
	if k.is_player:
		Sfx.play("hit")
		Game.haptic(60)


static func break_nearby(tree: SceneTree, pos: Vector3, radius: float) -> void:
	for g in tree.get_nodes_in_group("breakables"):
		if (g as Node3D).global_position.distance_to(pos) < radius + 3.0:
			g.call("hit", pos)
