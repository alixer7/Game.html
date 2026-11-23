class_name AmberPickup
extends Area3D
## Amber drop: collect 10 to empower items ("Charged" items).

var _visual: MeshInstance3D
var _t := 0.0
var _active := true

static var _mesh: ArrayMesh
static var _mat: StandardMaterial3D


func _ready() -> void:
	collision_layer = 0
	collision_mask = 2
	body_entered.connect(_on_body)
	_t = randf() * 6.0


func _process(dt: float) -> void:
	_t += dt
	if _visual:
		_visual.rotation.y = _t * 2.5
		_visual.position.y = 0.9 + sin(_t * 3.0) * 0.08


func _on_body(b: Node) -> void:
	if not _active or not (b is Kart):
		return
	var k := b as Kart
	if k.amber >= 10:
		return
	k.amber += 1
	_active = false
	_visual.visible = false
	if k.is_player:
		Sfx.play("amber", global_position)
	get_tree().create_timer(12.0).timeout.connect(func() -> void:
		_active = true
		_visual.visible = true)


static func make() -> Area3D:
	var a: Area3D = load("res://scripts/env/amber_pickup.gd").new()
	var cs := CollisionShape3D.new()
	var sh := SphereShape3D.new()
	sh.radius = 0.7
	cs.shape = sh
	cs.position = Vector3(0, 0.9, 0)
	a.add_child(cs)
	if _mesh == null:
		var mb := MeshBuilder.new()
		MeshLib.blob(mb, Vector3.ZERO, Vector3(0.22, 0.32, 0.22), 0, null, 0.0, Color(0.95, 0.45, 0.05), Color(1.0, 0.85, 0.35))
		_mesh = mb.commit()
		_mat = StandardMaterial3D.new()
		_mat.vertex_color_use_as_albedo = true
		_mat.emission_enabled = true
		_mat.emission = Color(1.0, 0.55, 0.1)
		_mat.emission_energy_multiplier = 1.4
		_mat.roughness = 0.15
	var mi := MeshInstance3D.new()
	mi.mesh = _mesh
	mi.material_override = _mat
	mi.position = Vector3(0, 0.9, 0)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	a.add_child(mi)
	a.set("_visual", mi)
	return a
