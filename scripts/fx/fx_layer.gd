class_name FxLayer
extends Node3D
## One-shot visual effects: goal explosions, demolitions, impact sparks.

var _dot: Texture2D


func _ready() -> void:
	_dot = CarView._soft_dot()


func _additive(color: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.albedo_color = color
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m


func _burst(pos: Vector3, color: Color, amount: int, vmin: float, vmax: float, life: float,
		size: float, gravity: float = -9.0, damping: float = 4.0) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.one_shot = true
	p.explosiveness = 1.0
	p.amount = amount
	p.lifetime = life
	p.direction = Vector3.UP
	p.spread = 180.0
	p.initial_velocity_min = vmin
	p.initial_velocity_max = vmax
	p.gravity = Vector3(0, gravity, 0)
	p.damping_min = damping
	p.damping_max = damping * 1.5
	p.scale_amount_min = size * 0.6
	p.scale_amount_max = size * 1.4
	var sc := Curve.new()
	sc.add_point(Vector2(0, 1))
	sc.add_point(Vector2(1, 0))
	p.scale_amount_curve = sc
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 1))
	g.set_color(1, Color(color.r, color.g, color.b, 0))
	g.add_point(0.2, Color(color.r * 1.5, color.g * 1.5, color.b * 1.5, 1))
	p.color_ramp = g
	var qm := QuadMesh.new()
	var pm := StandardMaterial3D.new()
	pm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	pm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	pm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	pm.vertex_color_use_as_albedo = true
	pm.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	pm.albedo_texture = _dot
	qm.material = pm
	p.mesh = qm
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(p)
	p.global_position = pos
	p.emitting = true
	get_tree().create_timer(life + 0.5).timeout.connect(p.queue_free)
	return p


func _flash_sphere(pos: Vector3, color: Color, r0: float, r1: float, dur: float) -> void:
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 1.0
	sm.height = 2.0
	sm.radial_segments = 24
	sm.rings = 12
	mi.mesh = sm
	var m := _additive(color)
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	mi.global_position = pos
	mi.scale = Vector3.ONE * r0
	var tw := create_tween().set_parallel(true)
	tw.tween_property(mi, "scale", Vector3.ONE * r1, dur).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	tw.tween_property(m, "albedo_color:a", 0.0, dur).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.chain().tween_callback(mi.queue_free)


func _shock_ring(pos: Vector3, color: Color, r1: float, dur: float, normal: Vector3 = Vector3.UP) -> void:
	var mi := MeshInstance3D.new()
	var qm := QuadMesh.new()
	qm.size = Vector2(2, 2)
	mi.mesh = qm
	var m := _additive(color)
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.7, 0.86, 1.0])
	g.colors = PackedColorArray([Color(1, 1, 1, 0), Color(1, 1, 1, 0.0), Color(1, 1, 1, 1), Color(1, 1, 1, 0)])
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.fill = GradientTexture2D.FILL_RADIAL
	gt.fill_from = Vector2(0.5, 0.5)
	gt.fill_to = Vector2(1.0, 0.5)
	gt.width = 128
	gt.height = 128
	m.albedo_texture = gt
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	mi.global_position = pos
	var up_ref := Vector3.UP if absf(normal.dot(Vector3.UP)) < 0.95 else Vector3.FORWARD
	mi.look_at(pos + normal, up_ref)
	mi.scale = Vector3.ONE * 0.5
	var tw := create_tween().set_parallel(true)
	tw.tween_property(mi, "scale", Vector3.ONE * r1, dur).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(m, "albedo_color:a", 0.0, dur)
	tw.chain().tween_callback(mi.queue_free)


func _light_flash(pos: Vector3, color: Color, energy: float, rng: float, dur: float) -> void:
	var l := OmniLight3D.new()
	l.light_color = color
	l.light_energy = energy
	l.omni_range = rng
	l.shadow_enabled = false
	add_child(l)
	l.global_position = pos
	var tw := create_tween()
	tw.tween_property(l, "light_energy", 0.0, dur).set_ease(Tween.EASE_IN)
	tw.tween_callback(l.queue_free)


func goal_explosion(pos: Vector3, color: Color) -> void:
	_flash_sphere(pos, Color(1, 1, 1, 0.9), 0.5, 9.0, 0.45)
	_flash_sphere(pos, Color(color.r, color.g, color.b, 0.8), 1.0, 16.0, 1.1)
	_burst(pos, color, 140, 14.0, 34.0, 1.6, 0.9, -6.0, 2.5)
	_burst(pos, Color(1, 0.95, 0.8), 60, 20.0, 45.0, 0.8, 0.45, -3.0, 5.0)
	_shock_ring(pos, color, 26.0, 0.9, Vector3(0, 0, 1))
	_shock_ring(Vector3(pos.x, 0.15, pos.z), Color(1, 1, 1), 22.0, 0.8, Vector3.UP)
	_light_flash(pos, color, 16.0, 40.0, 1.2)


func demo_explosion(pos: Vector3, color: Color) -> void:
	_flash_sphere(pos, Color(1, 0.9, 0.7, 0.9), 0.3, 4.0, 0.35)
	_burst(pos, Color(1.0, 0.45, 0.1), 70, 6.0, 16.0, 1.0, 0.7, -6.0, 3.0)
	_burst(pos, color, 30, 4.0, 10.0, 1.2, 0.5, -9.0, 2.0)
	_shock_ring(pos, Color(1, 0.6, 0.2), 8.0, 0.5)
	_light_flash(pos, Color(1, 0.6, 0.25), 8.0, 15.0, 0.6)


func hit_spark(pos: Vector3, strength: float, color: Color = Color(0.6, 0.9, 1.0)) -> void:
	var s := clampf(strength / 30.0, 0.15, 1.0)
	_burst(pos, color, int(10 + 30 * s), 3.0 + 8.0 * s, 8.0 + 18.0 * s, 0.45, 0.22 + 0.25 * s, -8.0, 6.0)
	if s > 0.5:
		_flash_sphere(pos, Color(1, 1, 1, 0.5 * s), 0.6, 2.6 * s + 1.0, 0.25)


func pad_pickup(pos: Vector3, big: bool) -> void:
	_burst(pos + Vector3(0, 1.0 if big else 0.5, 0), Color(1.0, 0.6, 0.1), 26 if big else 10, 3.0, 8.0, 0.5,
		0.35 if big else 0.2, 4.0, 3.0)
	if big:
		_flash_sphere(pos + Vector3(0, 1.1, 0), Color(1.0, 0.7, 0.2, 0.7), 0.5, 2.6, 0.3)
