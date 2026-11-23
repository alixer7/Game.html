class_name BrambleBomb
extends Node3D
## Thrown thorn-bomb: arcs forward, bounces, explodes on contact or after a fuse.

var velocity := Vector3.ZERO
var owner_kart: Kart
var charged := false
var _t := 0.0
var _ray := PhysicsRayQueryParameters3D.new()
var _done := false


static func make(is_charged: bool) -> BrambleBomb:
	var b := BrambleBomb.new()
	b.charged = is_charged
	var mb := MeshBuilder.new()
	MeshLib.blob(mb, Vector3.ZERO, Vector3.ONE * (0.42 if is_charged else 0.32), 1, null, 0.0, Color(0.25, 0.15, 0.3), Color(0.55, 0.3, 0.6))
	for i in 10:
		var d := Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)).normalized()
		MeshLib.tube(mb, PackedVector3Array([d * 0.28, d * 0.55]), PackedFloat32Array([0.06, 0.0]), 4, func(_a: float, _b: float, _c: Vector3) -> Color: return Color(0.9, 0.85, 0.6))
	var mi := MeshInstance3D.new()
	mi.mesh = mb.commit(null, Mats.vcol(0.5))
	b.add_child(mi)
	return b


func _ready() -> void:
	_ray.collision_mask = 1


func _physics_process(dt: float) -> void:
	if _done:
		return
	_t += dt
	velocity.y -= 22.0 * dt
	var from := global_position
	var to := from + velocity * dt
	_ray.from = from
	_ray.to = to + Vector3.DOWN * 0.3
	var hit := get_world_3d().direct_space_state.intersect_ray(_ray)
	if not hit.is_empty():
		var n: Vector3 = hit.normal
		global_position = (hit.position as Vector3) + n * 0.35
		velocity = velocity.bounce(n) * 0.45
		if velocity.length() < 3.0:
			velocity = Vector3.ZERO
	else:
		global_position = to
	rotation += Vector3(6, 4, 0) * dt
	if _t > 2.4:
		_explode()
		return
	for k in get_tree().get_nodes_in_group("karts"):
		var kk := k as Kart
		if kk == owner_kart and _t < 0.6:
			continue
		if kk.global_position.distance_to(global_position) < 1.5:
			_explode()
			return


func _explode() -> void:
	_done = true
	var radius := 6.0 if charged else 4.2
	for k in get_tree().get_nodes_in_group("karts"):
		var kk := k as Kart
		if kk.global_position.distance_to(global_position) < radius:
			ItemSystem.hit_kart(kk, 1.2 if charged else 1.0)
	ItemSystem.break_nearby(get_tree(), global_position, radius)
	Sfx.play("explode", global_position, 1.0, -2.0)
	var fx := Explosion.make(radius)
	get_parent().add_child(fx)
	fx.global_position = global_position
	queue_free()
