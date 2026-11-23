class_name BreakableGate
extends Node3D
## Woodcutter's Gate: a rope-tied log barricade across the Fernway cut-through.
## Breaks when rammed in Overdrive or hit by any projectile; reforms after a
## while. Opening it helps everyone behind you - a real racing decision.

const REFORM := 18.0

var broken := false
var _body: StaticBody3D
var _logs: Array[Node3D] = []
var _rest: Array[Transform3D] = []


func _ready() -> void:
	add_to_group("breakables")
	_body = get_node("Body")
	var sense: Area3D = get_node("Sense")
	sense.body_entered.connect(_on_sense)
	for c in get_node("Logs").get_children():
		_logs.append(c)
		_rest.append(c.transform)


func _on_sense(b: Node) -> void:
	if broken:
		return
	if b is Kart and (b as Kart).tier >= 2:
		hit(b.global_position)


func hit(from: Vector3) -> void:
	if broken:
		return
	broken = true
	_body.process_mode = Node.PROCESS_MODE_DISABLED
	(_body.get_child(0) as CollisionShape3D).set_deferred("disabled", true)
	Sfx.play("crash_wood", global_position)
	for i in _logs.size():
		var l := _logs[i]
		var dir := (l.global_position - from).normalized()
		var tw := create_tween().set_parallel(true)
		tw.tween_property(l, "position", l.position + Vector3(dir.x, 0.0, dir.z) * 5.0 + Vector3.DOWN * 1.0, 0.7).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tw.tween_property(l, "rotation", l.rotation + Vector3(randf_range(-1.5, 1.5), randf_range(-1, 1), randf_range(-1.5, 1.5)), 0.7)
	get_tree().create_timer(REFORM).timeout.connect(_reform)


func _reform() -> void:
	broken = false
	(_body.get_child(0) as CollisionShape3D).set_deferred("disabled", false)
	_body.process_mode = Node.PROCESS_MODE_INHERIT
	for i in _logs.size():
		var tw := create_tween()
		tw.tween_property(_logs[i], "transform", _rest[i], 0.8).set_trans(Tween.TRANS_BACK)


static func make(width: float) -> Node3D:
	var n: Node3D = load("res://scripts/env/breakable_gate.gd").new()
	var logs := Node3D.new()
	logs.name = "Logs"
	n.add_child(logs)
	for i in 4:
		var lm := MeshLib.log_mesh(width + 1.2, 0.32, 100 + i, false)
		var mi := MeshInstance3D.new()
		mi.mesh = lm.commit(null, Mats.triplanar("bark"))
		mi.position = Vector3(0, 0.35 + i * 0.62, 0)
		mi.rotation = Vector3(0, PI * 0.5, (i % 2) * 0.06 - 0.03)
		logs.add_child(mi)
	var ropes := MeshBuilder.new()
	for side in [-1.0, 1.0]:
		MeshLib.box(ropes, Transform3D(Basis(), Vector3(side * (width * 0.5 + 0.2), 1.3, 0)), Vector3(0.5, 2.8, 0.5), Color(0.5, 0.36, 0.24))
		for j in 3:
			MeshLib.box(ropes, Transform3D(Basis(), Vector3(side * (width * 0.5), 0.6 + j * 0.8, 0)), Vector3(0.6, 0.12, 0.62), Color(0.85, 0.75, 0.5))
	var rm := MeshInstance3D.new()
	rm.mesh = ropes.commit(null, Mats.vcol(0.9))
	n.add_child(rm)
	var body := StaticBody3D.new()
	body.name = "Body"
	body.collision_layer = 1
	body.set_meta("surface", Surfaces.WOOD)
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(width + 1.0, 2.8, 0.9)
	cs.shape = bs
	cs.position = Vector3(0, 1.4, 0)
	body.add_child(cs)
	n.add_child(body)
	var sense := Area3D.new()
	sense.name = "Sense"
	sense.collision_layer = 0
	sense.collision_mask = 2
	var scs := CollisionShape3D.new()
	var sbs := BoxShape3D.new()
	sbs.size = Vector3(width + 1.0, 2.5, 3.0)
	scs.shape = sbs
	scs.position = Vector3(0, 1.2, 0)
	sense.add_child(scs)
	n.add_child(sense)
	return n
