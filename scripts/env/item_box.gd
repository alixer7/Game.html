class_name ItemBox
extends Area3D
## "Spark Crate": floating crystal crate that grants a random item weighted by
## race position. Respawns after a short delay.

const RESPAWN := 2.8

var _active := true
var _t := 0.0
var _visual: Node3D
var _base_y := 0.0


func _ready() -> void:
	collision_layer = 0
	collision_mask = 2
	monitoring = true
	body_entered.connect(_on_body)
	_visual = get_node_or_null("Visual")
	if _visual:
		_base_y = _visual.position.y
	_t = randf() * 10.0


func _process(dt: float) -> void:
	_t += dt
	if _visual:
		_visual.rotation.y = _t * 1.4
		_visual.position.y = _base_y + sin(_t * 2.2) * 0.12


func _on_body(b: Node) -> void:
	if not _active or not (b is Kart):
		return
	var k := b as Kart
	var items := get_tree().get_first_node_in_group("item_system")
	if items and items.has_method("grant_item"):
		items.grant_item(k)
	_active = false
	if _visual:
		_visual.visible = false
	set_deferred("monitoring", false)
	if k.is_player:
		Sfx.play("crate", global_position)
	get_tree().create_timer(RESPAWN).timeout.connect(_respawn)


func _respawn() -> void:
	_active = true
	monitoring = true
	if _visual:
		_visual.visible = true
		_visual.scale = Vector3.ONE * 0.2
		create_tween().tween_property(_visual, "scale", Vector3.ONE, 0.35).set_trans(Tween.TRANS_BACK)


static var _mesh: ArrayMesh


static func make() -> Area3D:
	var a: Area3D = load("res://scripts/env/item_box.gd").new()
	var cs := CollisionShape3D.new()
	var sh := SphereShape3D.new()
	sh.radius = 1.0
	cs.shape = sh
	cs.position = Vector3(0, 1.0, 0)
	a.add_child(cs)
	var vis := Node3D.new()
	vis.name = "Visual"
	vis.position = Vector3(0, 1.15, 0)
	a.add_child(vis)
	if _mesh == null:
		var mb := MeshBuilder.new()
		# faceted crystal: two pyramids (octahedron) with a band
		var top := Vector3(0, 0.75, 0)
		var bot := Vector3(0, -0.75, 0)
		var ring: Array[Vector3] = []
		for i in 6:
			var ang := TAU * float(i) / 6.0
			ring.append(Vector3(cos(ang) * 0.62, 0, sin(ang) * 0.62))
		for i in 6:
			var r0 := ring[i]
			var r1 := ring[(i + 1) % 6]
			var c := Color(0.55, 0.95, 1.0) if i % 2 == 0 else Color(1.0, 0.75, 0.3)
			mb.add_flat_tri(top, r1, r0, c)
			mb.add_flat_tri(bot, r0, r1, c * 0.85)
		_mesh = mb.commit()
	var mi := MeshInstance3D.new()
	mi.mesh = _mesh
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = Color(1, 1, 1, 0.82)
	m.emission_enabled = true
	m.emission = Color(0.45, 0.75, 0.9)
	m.emission_energy_multiplier = 0.9
	m.roughness = 0.1
	m.metallic = 0.3
	m.rim_enabled = true
	m.rim = 1.0
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	vis.add_child(mi)
	var q := Label3D.new()
	q.text = "?"
	q.font_size = 96
	q.pixel_size = 0.008
	q.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	q.modulate = Color(1, 1, 0.85)
	q.outline_size = 16
	q.outline_modulate = Color(0.1, 0.2, 0.35)
	q.no_depth_test = false
	vis.add_child(q)
	return a
