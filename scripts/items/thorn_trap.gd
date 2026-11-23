class_name ThornTrap
extends Node3D
## Dropped thorn patch: spins out whoever drives over it.

var owner_kart: Kart
var charged := false
var _t := 0.0
var _ray := PhysicsRayQueryParameters3D.new()
var _settled := false


static func make(is_charged: bool) -> ThornTrap:
	var t := ThornTrap.new()
	t.charged = is_charged
	var mb := MeshBuilder.new()
	var s := 1.4 if is_charged else 1.0
	MeshLib.blob(mb, Vector3(0, 0.1, 0), Vector3(0.7, 0.18, 0.7) * s, 1, null, 0.0, Color(0.25, 0.4, 0.12), Color(0.4, 0.6, 0.2))
	for i in 14:
		var a := TAU * float(i) / 14.0
		var base := Vector3(cos(a) * 0.5, 0.15, sin(a) * 0.5) * s
		MeshLib.tube(mb, PackedVector3Array([base, base + Vector3(cos(a) * 0.2, 0.4, sin(a) * 0.2) * s]), PackedFloat32Array([0.07, 0.0]), 4,
			func(_a: float, _b: float, _c: Vector3) -> Color: return Color(0.85, 0.2, 0.3))
	var mi := MeshInstance3D.new()
	mi.mesh = mb.commit(null, Mats.vcol(0.7))
	t.add_child(mi)
	return t


func _ready() -> void:
	_ray.collision_mask = 1


func _physics_process(dt: float) -> void:
	_t += dt
	if not _settled:
		_ray.from = global_position + Vector3.UP * 1.0
		_ray.to = global_position + Vector3.DOWN * 6.0
		var hit := get_world_3d().direct_space_state.intersect_ray(_ray)
		if not hit.is_empty():
			global_position = hit.position
		_settled = true
	if _t > 40.0:
		queue_free()
		return
	var r := 1.6 if charged else 1.2
	for k in get_tree().get_nodes_in_group("karts"):
		var kk := k as Kart
		if kk == owner_kart and _t < 1.0:
			continue
		if kk.global_position.distance_to(global_position) < r:
			ItemSystem.hit_kart(kk, 1.0)
			queue_free()
			return
