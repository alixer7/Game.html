class_name Explosion
extends Node3D
## Short-lived explosion flash + debris burst.

static func make(radius: float) -> Explosion:
	var e := Explosion.new()
	var flash := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = radius * 0.5
	sm.height = radius
	flash.mesh = sm
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.albedo_color = Color(1.0, 0.6, 0.25, 0.9)
	flash.material_override = m
	flash.name = "Flash"
	e.add_child(flash)
	var p := GPUParticles3D.new()
	p.amount = 40
	p.lifetime = 0.8
	p.one_shot = true
	p.explosiveness = 1.0
	var q := QuadMesh.new()
	q.size = Vector2(0.4, 0.4)
	var pm := StandardMaterial3D.new()
	pm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	pm.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	pm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	pm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	pm.vertex_color_use_as_albedo = true
	pm.albedo_texture = EnvLife.soft_texture()
	q.material = pm
	p.draw_pass_1 = q
	var ppm := ParticleProcessMaterial.new()
	ppm.direction = Vector3.UP
	ppm.spread = 180.0
	ppm.initial_velocity_min = radius * 1.5
	ppm.initial_velocity_max = radius * 3.0
	ppm.gravity = Vector3(0, -9, 0)
	ppm.color = Color(1.0, 0.7, 0.3)
	p.process_material = ppm
	e.add_child(p)
	return e


func _ready() -> void:
	var flash := get_node("Flash") as MeshInstance3D
	flash.scale = Vector3.ONE * 0.3
	var tw := create_tween()
	tw.tween_property(flash, "scale", Vector3.ONE * 1.3, 0.18).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(flash, "scale", Vector3.ONE * 0.01, 0.25)
	get_tree().create_timer(1.2).timeout.connect(queue_free)
