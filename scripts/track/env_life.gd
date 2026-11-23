class_name EnvLife
extends RefCounted
## Environmental life: things that move so the world feels alive, without
## stealing readability from the racing line.

static var _soft_tex: GradientTexture2D


static func soft_texture() -> GradientTexture2D:
	if _soft_tex == null:
		var g := Gradient.new()
		g.set_color(0, Color(1, 1, 1, 1))
		g.set_color(1, Color(1, 1, 1, 0))
		_soft_tex = GradientTexture2D.new()
		_soft_tex.gradient = g
		_soft_tex.fill = GradientTexture2D.FILL_RADIAL
		_soft_tex.fill_from = Vector2(0.5, 0.5)
		_soft_tex.fill_to = Vector2(1.0, 0.5)
		_soft_tex.width = 64
		_soft_tex.height = 64
	return _soft_tex


static func _billboard_mat(color: Color, additive := false, tex: Texture2D = null) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD if additive else BaseMaterial3D.BLEND_MODE_MIX
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.albedo_color = color
	m.albedo_texture = tex if tex else soft_texture()
	m.vertex_color_use_as_albedo = true
	m.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	return m


static func _particles(amount: int, lifetime: float, size: float, mat: Material) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = amount
	p.lifetime = lifetime
	p.preprocess = lifetime
	var qm := QuadMesh.new()
	qm.size = Vector2(size, size)
	qm.material = mat
	p.draw_pass_1 = qm
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return p


static func mist(parent: Node3D, pos: Vector3, width: float) -> void:
	var p := _particles(36, 3.2, 4.0, _billboard_mat(Color(1, 1, 1, 0.35)))
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(width * 0.5, 0.5, 2.0)
	pm.direction = Vector3(0, 1, 0)
	pm.spread = 35.0
	pm.initial_velocity_min = 0.8
	pm.initial_velocity_max = 2.0
	pm.gravity = Vector3(0, 0.15, 0)
	pm.scale_min = 0.8
	pm.scale_max = 1.8
	var curve := Curve.new()
	curve.add_point(Vector2(0, 0.3))
	curve.add_point(Vector2(1, 1.4))
	var ct := CurveTexture.new()
	ct.curve = curve
	pm.scale_curve = ct
	var grad := Gradient.new()
	grad.set_color(0, Color(1, 1, 1, 0.0))
	grad.add_point(0.25, Color(1, 1, 1, 0.5))
	grad.set_color(grad.get_point_count() - 1, Color(1, 1, 1, 0.0))
	var gt := GradientTexture1D.new()
	gt.gradient = grad
	pm.color_ramp = gt
	p.process_material = pm
	p.position = pos
	p.visibility_aabb = AABB(Vector3(-width, -2, -6), Vector3(width * 2, 10, 12))
	p.name = "Mist"
	parent.add_child(p)


static func chimney_smoke(parent: Node3D, pos: Vector3) -> void:
	var p := _particles(18, 5.0, 2.2, _billboard_mat(Color(0.8, 0.8, 0.82, 0.45)))
	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3(0.2, 1, 0)
	pm.spread = 12.0
	pm.initial_velocity_min = 1.0
	pm.initial_velocity_max = 1.6
	pm.gravity = Vector3(0.4, 0.2, 0.1)
	pm.scale_min = 0.7
	pm.scale_max = 1.2
	var curve := Curve.new()
	curve.add_point(Vector2(0, 0.4))
	curve.add_point(Vector2(1, 2.4))
	var ct := CurveTexture.new()
	ct.curve = curve
	pm.scale_curve = ct
	var grad := Gradient.new()
	grad.set_color(0, Color(1, 1, 1, 0.6))
	grad.set_color(1, Color(1, 1, 1, 0.0))
	var gt := GradientTexture1D.new()
	gt.gradient = grad
	pm.color_ramp = gt
	p.process_material = pm
	p.position = pos
	p.visibility_aabb = AABB(Vector3(-6, -1, -6), Vector3(12, 20, 12))
	p.name = "ChimneySmoke"
	parent.add_child(p)


static func fireflies(parent: Node3D, pos: Vector3, radius: float, amount: int) -> void:
	var p := _particles(amount, 4.0, 0.16, _billboard_mat(Color(0.85, 1.0, 0.45, 1.0), true))
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = radius
	pm.gravity = Vector3.ZERO
	pm.initial_velocity_min = 0.1
	pm.initial_velocity_max = 0.4
	pm.spread = 180.0
	pm.turbulence_enabled = true
	pm.turbulence_noise_strength = 1.5
	pm.turbulence_noise_scale = 3.0
	var grad := Gradient.new()
	grad.set_color(0, Color(1, 1, 1, 0.0))
	grad.add_point(0.3, Color(1, 1, 1, 1.0))
	grad.add_point(0.6, Color(1, 1, 1, 0.2))
	grad.set_color(grad.get_point_count() - 1, Color(1, 1, 1, 0.0))
	var gt := GradientTexture1D.new()
	gt.gradient = grad
	pm.color_ramp = gt
	p.process_material = pm
	p.position = pos
	p.visibility_aabb = AABB(Vector3.ONE * -radius * 1.5, Vector3.ONE * radius * 3.0)
	p.name = "Fireflies"
	parent.add_child(p)


static func falling_leaves() -> GPUParticles3D:
	## World-space leaf fall that follows the camera rig (attach to the rig).
	var m := StandardMaterial3D.new()
	m.albedo_texture = Mats.tex("leaf_atlas")
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	m.alpha_scissor_threshold = 0.5
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.billboard_mode = BaseMaterial3D.BILLBOARD_DISABLED
	m.vertex_color_use_as_albedo = true
	m.uv1_scale = Vector3(0.5, 0.5, 1)
	var p := _particles(70, 7.0, 0.35, m)
	p.local_coords = false
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(28, 6, 28)
	pm.gravity = Vector3(0.4, -0.9, 0.2)
	pm.initial_velocity_min = 0.0
	pm.initial_velocity_max = 0.4
	pm.angular_velocity_min = -180.0
	pm.angular_velocity_max = 180.0
	pm.angle_min = 0.0
	pm.angle_max = 360.0
	pm.turbulence_enabled = true
	pm.turbulence_noise_strength = 0.8
	pm.color = Color(0.9, 0.95, 0.7)
	pm.hue_variation_min = -0.08
	pm.hue_variation_max = 0.08
	pm.particle_flag_rotate_y = true
	p.process_material = pm
	p.visibility_aabb = AABB(Vector3(-40, -20, -40), Vector3(80, 40, 80))
	p.position = Vector3(0, 9, 0)
	p.name = "FallingLeaves"
	return p


static func butterflies(parent: Node3D, pos: Vector3) -> void:
	var p := _particles(10, 6.0, 0.25, _billboard_mat(Color(1, 1, 1, 1)))
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = 6.0
	pm.gravity = Vector3.ZERO
	pm.turbulence_enabled = true
	pm.turbulence_noise_strength = 2.5
	pm.turbulence_noise_scale = 2.0
	pm.initial_velocity_min = 0.5
	pm.initial_velocity_max = 1.2
	pm.spread = 180.0
	pm.color = Color(1.0, 0.75, 0.3)
	pm.hue_variation_min = -0.5
	pm.hue_variation_max = 0.5
	p.process_material = pm
	p.position = pos + Vector3.UP * 1.5
	p.visibility_aabb = AABB(Vector3.ONE * -9.0, Vector3.ONE * 18.0)
	p.name = "Butterflies"
	parent.add_child(p)


static func build_all(tb: TrackBuilder) -> void:
	var root := Node3D.new()
	root.name = "Life"
	tb.root.add_child(root)
	# bird flocks circling over open spaces and landmarks
	var spots := [tb.mark_pos("gravel_bar") + Vector3.UP * 30.0, tb.mark_pos("hollow_exit") + Vector3.UP * 34.0,
		tb.mark_pos("mill_apex") + Vector3.UP * 28.0, tb.mark_pos("start_line") + Vector3(40, 38, 60)]
	for i in spots.size():
		var flock: Node3D = load("res://scripts/env/bird_flock.gd").new()
		flock.set("count", 5 + i % 3)
		flock.set("radius", 26.0 + i * 6.0)
		flock.position = spots[i]
		root.add_child(flock)
	# butterflies over flower-rich road edges
	for name: String in ["bank_split", "crest_1", "rollers", "hairpin_exit"]:
		var k := tb.mark_index(name)
		var p := tb.main.pos[k] + tb.main.right[k] * (tb.main.width[k] * 0.5 + 5.0)
		butterflies(root, p)
	# leaping fish in the river and the mill pond
	for name: String in ["rock_garden_1", "rock_garden_2"]:
		var fish: Node3D = load("res://scripts/env/fish_jumper.gd").new()
		var k := tb.mark_index(name)
		fish.position = tb.main.pos[k] + Vector3.UP * 0.4
		fish.set("flow_dir", tb.main.tan[k])
		root.add_child(fish)
	for lm in tb.landmarks:
		if lm.name == "pond":
			var fish: Node3D = load("res://scripts/env/fish_jumper.gd").new()
			fish.position = lm.pos + Vector3.UP * (tb.ground_y(lm.pos.x, lm.pos.z) - lm.pos.y + 3.0)
			root.add_child(fish)
	# fireflies in the hollow and around the ruins
	var h := tb.mark_pos("log_entry")
	fireflies(root, h + Vector3(-15, -2, -12), 12.0, 30)
	fireflies(root, tb.mark_pos("flytraps") + Vector3.UP * 2.0, 10.0, 20)
