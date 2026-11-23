class_name HomingHornet
extends Node3D
## Homing projectile: hugs the ground and chases the racer one place ahead.

var owner_kart: Kart
var target: Kart
var race: RaceManager
var dir := Vector3.FORWARD
var charged := false
var speed := 38.0
var _t := 0.0
var _ray := PhysicsRayQueryParameters3D.new()


static func make(is_charged: bool) -> HomingHornet:
	var h := HomingHornet.new()
	h.charged = is_charged
	h.speed = 44.0 if is_charged else 38.0
	var mb := MeshBuilder.new()
	MeshLib.blob(mb, Vector3(0, 0, 0.15), Vector3(0.18, 0.16, 0.32), 1, null, 0.0, Color(0.95, 0.75, 0.1), Color(1.0, 0.9, 0.2))
	MeshLib.blob(mb, Vector3(0, 0, -0.22), Vector3(0.14, 0.13, 0.16), 1, null, 0.0, Color(0.1, 0.1, 0.1), Color(0.2, 0.2, 0.2))
	for s: float in [-1.0, 1.0]:
		MeshLib.blob(mb, Vector3(0.22 * s, 0.14, 0.05), Vector3(0.2, 0.02, 0.1), 0, null, 0.0, Color(0.8, 0.9, 1.0), Color(0.9, 0.95, 1.0))
	var mi := MeshInstance3D.new()
	mi.mesh = mb.commit(null, Mats.vcol(0.4))
	h.add_child(mi)
	return h


func _ready() -> void:
	_ray.collision_mask = 1


func _physics_process(dt: float) -> void:
	_t += dt
	if _t > 8.0:
		queue_free()
		return
	var want := dir
	if target and is_instance_valid(target):
		var to := target.global_position + Vector3.UP * 0.6 - global_position
		if to.length() < 35.0 or race == null:
			want = to.normalized()
		else:
			# follow the track spine toward the target
			var sp := race.spine
			var i := sp.nearest_index(global_position, 30.0)
			if i >= 0:
				var j := (i + 8) % sp.size()
				want = (sp.pos[j] + Vector3.UP * 1.0 - global_position).normalized()
	dir = dir.slerp(want, clampf(dt * 4.0, 0.0, 1.0)).normalized()
	var p := global_position + dir * speed * dt
	_ray.from = p + Vector3.UP * 2.0
	_ray.to = p + Vector3.DOWN * 4.0
	var hit := get_world_3d().direct_space_state.intersect_ray(_ray)
	if not hit.is_empty():
		p.y = lerpf(p.y, (hit.position as Vector3).y + 0.9, clampf(dt * 10.0, 0.0, 1.0))
	global_position = p
	if dir.length() > 0.1:
		look_at(global_position + dir, Vector3.UP)
	for k in get_tree().get_nodes_in_group("karts"):
		var kk := k as Kart
		if kk == owner_kart and _t < 0.8:
			continue
		if kk.global_position.distance_to(global_position) < 1.6:
			ItemSystem.hit_kart(kk, 1.3)
			ItemSystem.break_nearby(get_tree(), global_position, 2.0)
			var fx := Explosion.make(2.5)
			get_parent().add_child(fx)
			fx.global_position = global_position
			queue_free()
			return
	for g in get_tree().get_nodes_in_group("breakables"):
		if (g as Node3D).global_position.distance_to(global_position) < 3.0 and not g.get("broken"):
			g.call("hit", global_position)
