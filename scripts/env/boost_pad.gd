class_name BoostPad
extends Area3D
## Boost pad. tier 1 = Boost (amber chevrons), tier 2 = Overdrive (teal chevrons).
## Pads top up the reserve; Overdrive pads force tier 2 - the only reliable way
## into Overdrive besides chaining perfect sparks.

@export var tier := 1
@export var amount := 2.2

var _cool := {}
var _mat: ShaderMaterial


func _ready() -> void:
	monitoring = true
	monitorable = false
	collision_layer = 0
	collision_mask = 2
	body_entered.connect(_on_body)
	var mi := get_node_or_null("Visual") as MeshInstance3D
	if mi:
		_mat = mi.material_override as ShaderMaterial


func _on_body(b: Node) -> void:
	if b is Kart:
		var k := b as Kart
		var now := Time.get_ticks_msec()
		if _cool.get(k, 0) > now:
			return
		_cool[k] = now + 600
		k.apply_pad(amount if tier == 1 else maxf(amount, 3.0), tier)
		if k.is_player:
			Sfx.play("pad_overdrive" if tier == 2 else "pad", k.global_position)


static func make(tier_: int, width: float, length: float) -> Area3D:
	var pad: Area3D = load("res://scripts/env/boost_pad.gd").new()
	pad.set("tier", tier_)
	pad.set("amount", 2.2 if tier_ == 1 else 3.4)
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(width, 1.6, length)
	cs.shape = bs
	cs.position = Vector3(0, 0.8, 0)
	pad.add_child(cs)
	var mi := MeshInstance3D.new()
	mi.name = "Visual"
	var pm := PlaneMesh.new()
	pm.size = Vector2(width, length)
	mi.mesh = pm
	mi.position = Vector3(0, 0.09, 0)
	var m := ShaderMaterial.new()
	m.shader = load("res://shaders/boost_pad.gdshader")
	m.set_shader_parameter("color_a", Color(1.0, 0.55, 0.1) if tier_ == 1 else Color(0.1, 0.95, 1.0))
	m.set_shader_parameter("color_b", Color(1.0, 0.92, 0.4) if tier_ == 1 else Color(0.75, 1.0, 1.0))
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	pad.add_child(mi)
	return pad
