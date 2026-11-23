class_name AmberPickup
extends Area3D
## Amber drop: collect 10 to empower items ("Charged" items).
## Visuals for every pickup live in one shared MultiMesh (AmberPickup.field):
## a single draw call, animated in the shader; a pickup hides its instance by
## scaling it to zero while collected.

const RESPAWN := 12.0

var index := -1
var field: MultiMesh
var _active := true

static var _mesh: ArrayMesh


func _ready() -> void:
	collision_layer = 0
	collision_mask = 2
	body_entered.connect(_on_body)


func _on_body(b: Node) -> void:
	if not _active or not (b is Kart):
		return
	var k := b as Kart
	if k.amber >= 10:
		return
	k.amber += 1
	_set_shown(false)
	if k.is_player:
		Sfx.play("amber", global_position)
	get_tree().create_timer(RESPAWN).timeout.connect(func() -> void:
		if is_instance_valid(self):
			_set_shown(true))


func _set_shown(on: bool) -> void:
	_active = on
	if field and index >= 0:
		var s := 1.0 if on else 0.0
		field.set_instance_transform(index, Transform3D(Basis().scaled(Vector3.ONE * maxf(s, 0.0001)), global_position))


static func make() -> Area3D:
	var a: Area3D = load("res://scripts/env/amber_pickup.gd").new()
	var cs := CollisionShape3D.new()
	var sh := SphereShape3D.new()
	sh.radius = 0.7
	cs.shape = sh
	cs.position = Vector3(0, 0.9, 0)
	a.add_child(cs)
	return a


## One MultiMeshInstance for all pickups under root (call after placing them).
static func build_field(root: Node3D, pickups: Array) -> MultiMeshInstance3D:
	if _mesh == null:
		var mb := MeshBuilder.new()
		MeshLib.blob(mb, Vector3.ZERO, Vector3(0.22, 0.32, 0.22), 0, null, 0.0, Color(0.95, 0.45, 0.05), Color(1.0, 0.85, 0.35))
		_mesh = mb.commit()
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = _mesh
	mm.instance_count = pickups.size()
	for i in pickups.size():
		var p: AmberPickup = pickups[i]
		p.index = i
		p.field = mm
		mm.set_instance_transform(i, Transform3D(Basis(), p.position))
	var mmi := MultiMeshInstance3D.new()
	mmi.name = "AmberField"
	mmi.multimesh = mm
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/amber.gdshader")
	mmi.material_override = mat
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mmi.visibility_range_end = 160.0
	root.add_child(mmi)
	return mmi
