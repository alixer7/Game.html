class_name SwingingLog
extends Node3D
## Battering-ram log hung from a gantry, sweeping across the ruin corridor.
## A pure timing test: it is fully visible from 60 m away, the gantry shadow and
## chain creak telegraph it, and at each extreme half the road is clear.

@export var period := 3.4
@export var amplitude := 1.05      # radians
@export var phase := 0.0

var _pivot: Node3D
var _body: AnimatableBody3D
var _hit: Area3D
var _t := 0.0
var _prev_angle := 0.0


func _ready() -> void:
	_pivot = get_node("Pivot")
	_body = get_node("Pivot/Body")
	_hit = get_node("Pivot/Body/Hit")
	_hit.body_entered.connect(_on_hit)
	_t = phase


func _physics_process(dt: float) -> void:
	_t += dt
	var a := sin(_t / period * TAU) * amplitude
	_pivot.rotation = Vector3(0, 0, a)
	_prev_angle = a


func angular_speed() -> float:
	return cos(_t / period * TAU) * amplitude * TAU / period


func _on_hit(b: Node) -> void:
	if b is Kart:
		var k := b as Kart
		if absf(angular_speed()) < 0.25:
			return
		k.spin_out(0.7)
		var push := global_transform.basis.x * signf(angular_speed()) * 9.0
		k.velocity += Vector3(push.x, 4.0, push.z)
		if k.is_player:
			Sfx.play("thud", k.global_position)


static func make(width: float, tb_rng: RandomNumberGenerator) -> Node3D:
	var n: Node3D = load("res://scripts/env/swinging_log.gd").new()
	n.set("phase", tb_rng.randf() * 3.0)
	var height := 8.5
	var frame := MeshBuilder.new()
	var wood := Color(0.6, 0.45, 0.32, 0.3)
	for side in [-1.0, 1.0]:
		MeshLib.box(frame, Transform3D(Basis(), Vector3(side * (width * 0.5 + 0.9), height * 0.5, 0)), Vector3(0.8, height + 0.4, 0.8), wood, 0.1)
	MeshLib.box(frame, Transform3D(Basis(), Vector3(0, height + 0.2, 0)), Vector3(width + 2.8, 0.8, 0.9), wood, 0.1)
	var fm := MeshInstance3D.new()
	fm.mesh = frame.commit(null, Mats.triplanar("wood"))
	n.add_child(fm)
	for side in [-1.0, 1.0]:
		var post := StaticBody3D.new()
		post.collision_layer = 1
		var cs := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = Vector3(0.8, height, 0.8)
		cs.shape = bs
		post.position = Vector3(side * (width * 0.5 + 0.9), height * 0.5, 0)
		post.add_child(cs)
		n.add_child(post)
	var pivot := Node3D.new()
	pivot.name = "Pivot"
	pivot.position = Vector3(0, height, 0)
	n.add_child(pivot)
	var body := AnimatableBody3D.new()
	body.name = "Body"
	body.sync_to_physics = true
	body.collision_layer = 1
	pivot.add_child(body)
	var log_len := 2.6
	var log_r := 0.75
	var ram := MeshLib.log_mesh(log_len, log_r, 991, false)
	var rm := MeshInstance3D.new()
	rm.mesh = ram.commit(null, Mats.triplanar("bark"))
	rm.position = Vector3(0, -6.2, 0)
	rm.rotation = Vector3(0, 0, 0)
	body.add_child(rm)
	var chains := MeshBuilder.new()
	for side in [-1.0, 1.0]:
		MeshLib.tube(chains, PackedVector3Array([Vector3(side * 0.5, 0, 0), Vector3(side * 0.5, -5.6, 0)]), PackedFloat32Array([0.06, 0.06]), 4,
			func(_t: float, _a: float, _p: Vector3) -> Color: return Color(0.3, 0.3, 0.32))
	var cm := MeshInstance3D.new()
	cm.mesh = chains.commit(null, Mats.vcol(0.4, 0.8))
	body.add_child(cm)
	var cs2 := CollisionShape3D.new()
	var cyl := CylinderShape3D.new()
	cyl.radius = log_r
	cyl.height = log_len
	cs2.shape = cyl
	cs2.position = Vector3(0, -6.2, 0)
	cs2.rotation = Vector3(PI * 0.5, 0, 0)
	body.add_child(cs2)
	var hit := Area3D.new()
	hit.name = "Hit"
	hit.collision_layer = 0
	hit.collision_mask = 2
	var hcs := CollisionShape3D.new()
	var hcyl := CylinderShape3D.new()
	hcyl.radius = log_r + 0.45
	hcyl.height = log_len + 0.6
	hcs.shape = hcyl
	hcs.position = Vector3(0, -6.2, 0)
	hcs.rotation = Vector3(PI * 0.5, 0, 0)
	hit.add_child(hcs)
	body.add_child(hit)
	return n
