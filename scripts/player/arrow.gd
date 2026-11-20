class_name Arrow
extends Node3D
## سهم مقذوف بفيزياء بسيطة (جاذبية) واصطدام بالأشعة.

var vel := Vector3.ZERO
var dmg := 12.0
var shooter: Node = null
var life := 0.0
var stuck := false

func launch(from: Vector3, dir: Vector3, speed: float, damage: float, who: Node) -> void:
	global_position = from
	vel = dir * speed
	dmg = damage
	shooter = who
	var mi := MeshInstance3D.new()
	var m := CylinderMesh.new()
	m.top_radius = 0.012
	m.bottom_radius = 0.012
	m.height = 0.7
	mi.mesh = m
	mi.material_override = HumanModel.cmat(Color(0.55, 0.4, 0.25), 0.8)
	mi.rotation.x = PI / 2.0
	add_child(mi)
	var tip := MeshInstance3D.new()
	var tm := CylinderMesh.new()
	tm.top_radius = 0.0
	tm.bottom_radius = 0.03
	tm.height = 0.08
	tip.mesh = tm
	tip.material_override = HumanModel.cmat(Color(0.3, 0.3, 0.32), 0.4)
	tip.rotation.x = -PI / 2.0
	tip.position = Vector3(0, 0, -0.38)
	add_child(tip)
	look_at(global_position + vel, Vector3.UP)

func _physics_process(dt: float) -> void:
	life += dt
	if stuck:
		if life > 25.0:
			queue_free()
		return
	if life > 8.0:
		queue_free()
		return
	vel.y -= 9.8 * dt
	var from := global_position
	var to := from + vel * dt
	var q := PhysicsRayQueryParameters3D.create(from, to, 1 | 4 | 8 | 32)
	if shooter is CollisionObject3D:
		q.exclude = [shooter.get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if not hit.is_empty():
		global_position = hit["position"]
		stuck = true
		life = 0.0
		var c = hit["collider"]
		if c != null and c.has_method("on_hit") and not (c is ResourceBody) and not (c is BuildPiece):
			c.on_hit(dmg, "arrow", 1, shooter, hit["position"])
			queue_free()
		return
	global_position = to
	if vel.length() > 0.1:
		look_at(global_position + vel, Vector3.UP)
