class_name EnvBuilder
extends RefCounted
## Per-world look: procedural sky, lights, glow/fog, endless neon abyss grid, floating scenery and drifting motes.


## Colour / lighting recipe for a theme id ("launch", "crystal", "foundry", "core").
static func theme(id: String) -> Dictionary:
	var t: Dictionary = {}
	if id == "crystal":
		t = {
			"sky": {
				"top_color": Color(0.05, 0.02, 0.15), "mid_color": Color(0.26, 0.07, 0.42), "horizon_color": Color(0.95, 0.35, 0.75),
				"bottom_color": Color(0.03, 0.01, 0.07), "nebula_a": Color(0.9, 0.25, 0.8), "nebula_b": Color(0.3, 0.5, 1.0),
				"nebula_amount": 1.1, "star_amount": 1.0, "sun_dir": Vector3(0.5, 0.45, -0.7), "sun_color": Color(1.0, 0.75, 0.9),
				"planet_dir": Vector3(0.6, 0.3, -0.75), "planet_size": 0.15, "planet_color": Color(0.95, 0.4, 0.8),
				"planet_color2": Color(0.4, 0.3, 1.0), "seed": 7.0,
			},
			"accents": [Color(1.0, 0.3, 0.8), Color(0.65, 0.4, 1.0), Color(0.3, 0.9, 1.0), Color(1.0, 0.55, 0.85)],
			"base": Color(0.08, 0.05, 0.14), "top": Color(0.14, 0.09, 0.25),
			"fog": Color(0.2, 0.06, 0.28), "fog_density": 0.0032,
			"ambient": Color(0.75, 0.6, 0.95), "ambient_energy": 0.75,
			"sun_color": Color(1.0, 0.85, 0.95), "sun_energy": 1.1, "sun_rot": Vector3(-46.0, 150.0, 0.0),
			"abyss_line": Color(0.95, 0.3, 0.85), "abyss_fill": Color(0.04, 0.01, 0.09),
			"mote_color": Color(1.0, 0.6, 0.95, 0.55), "mote_gravity": 0.0,
		}
	elif id == "foundry":
		t = {
			"sky": {
				"top_color": Color(0.08, 0.02, 0.04), "mid_color": Color(0.34, 0.08, 0.06), "horizon_color": Color(1.0, 0.5, 0.15),
				"bottom_color": Color(0.04, 0.01, 0.01), "nebula_a": Color(1.0, 0.4, 0.1), "nebula_b": Color(0.8, 0.1, 0.25),
				"nebula_amount": 0.9, "star_amount": 0.7, "sun_dir": Vector3(-0.4, 0.4, -0.8), "sun_color": Color(1.0, 0.7, 0.4),
				"planet_dir": Vector3(-0.7, 0.2, -0.7), "planet_size": 0.2, "planet_color": Color(1.0, 0.5, 0.15),
				"planet_color2": Color(0.7, 0.15, 0.1), "seed": 13.0,
			},
			"accents": [Color(1.0, 0.55, 0.15), Color(1.0, 0.8, 0.25), Color(1.0, 0.3, 0.3), Color(0.25, 0.9, 0.9)],
			"base": Color(0.09, 0.06, 0.06), "top": Color(0.17, 0.11, 0.1),
			"fog": Color(0.3, 0.1, 0.04), "fog_density": 0.0045,
			"ambient": Color(1.0, 0.75, 0.6), "ambient_energy": 0.7,
			"sun_color": Color(1.0, 0.8, 0.6), "sun_energy": 1.15, "sun_rot": Vector3(-42.0, -35.0, 0.0),
			"abyss_line": Color(1.0, 0.45, 0.1), "abyss_fill": Color(0.09, 0.02, 0.01),
			"mote_color": Color(1.0, 0.55, 0.2, 0.7), "mote_gravity": 1.3,
		}
	elif id == "core":
		t = {
			"sky": {
				"top_color": Color(0.01, 0.01, 0.06), "mid_color": Color(0.12, 0.05, 0.36), "horizon_color": Color(0.5, 0.4, 1.0),
				"bottom_color": Color(0.0, 0.0, 0.03), "nebula_a": Color(0.45, 0.3, 1.0), "nebula_b": Color(0.1, 0.9, 0.9),
				"nebula_amount": 1.3, "star_amount": 1.3, "sun_dir": Vector3(0.2, 0.6, -0.8), "sun_color": Color(0.9, 0.85, 1.0),
				"planet_dir": Vector3(0.0, 0.18, -1.0), "planet_size": 0.26, "planet_color": Color(0.6, 0.5, 1.0),
				"planet_color2": Color(0.2, 0.9, 0.9), "seed": 21.0,
			},
			"accents": [Color(0.6, 0.45, 1.0), Color(0.2, 0.95, 1.0), Color(1.0, 0.4, 0.85), Color(1.0, 0.85, 0.3)],
			"base": Color(0.05, 0.04, 0.12), "top": Color(0.1, 0.08, 0.22),
			"fog": Color(0.1, 0.05, 0.25), "fog_density": 0.003,
			"ambient": Color(0.7, 0.65, 1.0), "ambient_energy": 0.8,
			"sun_color": Color(0.9, 0.88, 1.0), "sun_energy": 1.05, "sun_rot": Vector3(-50.0, 20.0, 0.0),
			"abyss_line": Color(0.5, 0.4, 1.0), "abyss_fill": Color(0.02, 0.01, 0.07),
			"mote_color": Color(0.7, 0.8, 1.0, 0.6), "mote_gravity": 0.0,
		}
	else:
		t = {
			"sky": {
				"top_color": Color(0.015, 0.025, 0.12), "mid_color": Color(0.04, 0.14, 0.4), "horizon_color": Color(0.18, 0.62, 0.95),
				"bottom_color": Color(0.01, 0.02, 0.07), "nebula_a": Color(0.1, 0.5, 1.0), "nebula_b": Color(0.6, 0.25, 0.95),
				"nebula_amount": 1.0, "star_amount": 1.0, "sun_dir": Vector3(0.45, 0.5, -0.75), "sun_color": Color(1.0, 0.92, 0.75),
				"planet_dir": Vector3(-0.55, 0.28, -0.8), "planet_size": 0.17, "planet_color": Color(0.2, 0.6, 1.0),
				"planet_color2": Color(0.8, 0.3, 0.9), "seed": 1.0,
			},
			"accents": [Color(0.2, 0.9, 1.0), Color(0.35, 0.55, 1.0), Color(0.3, 1.0, 0.8), Color(0.7, 0.5, 1.0)],
			"base": Color(0.05, 0.07, 0.14), "top": Color(0.09, 0.13, 0.23),
			"fog": Color(0.06, 0.14, 0.32), "fog_density": 0.0035,
			"ambient": Color(0.6, 0.72, 1.0), "ambient_energy": 0.75,
			"sun_color": Color(1.0, 0.93, 0.82), "sun_energy": 1.15, "sun_rot": Vector3(-48.0, 35.0, 0.0),
			"abyss_line": Color(0.2, 0.8, 1.0), "abyss_fill": Color(0.01, 0.03, 0.1),
			"mote_color": Color(0.6, 0.9, 1.0, 0.55), "mote_gravity": 0.0,
		}
	return t


## Adds WorldEnvironment, lights, abyss grid and scenery under `parent`. Returns {"abyss": MeshInstance3D}.
static func build(parent: Node3D, theme_id: String, center: Vector3, kill_y: float, extent: float) -> Dictionary:
	var th: Dictionary = theme(theme_id)
	var q: int = Game.quality()

	var sm := ShaderMaterial.new()
	sm.shader = Mats.shader("res://shaders/sky_space.gdshader")
	var sp: Dictionary = th["sky"]
	for k in sp.keys():
		sm.set_shader_parameter(str(k), sp[k])
	var qs: Array = [0.35, 0.7, 1.0]
	sm.set_shader_parameter("quality", float(qs[q]))
	var sky := Sky.new()
	sky.sky_material = sm
	sky.radiance_size = Sky.RADIANCE_SIZE_64

	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = th["ambient"]
	env.ambient_light_energy = float(th["ambient_energy"])
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 1.0
	if q >= 1:
		env.glow_enabled = true
		env.glow_intensity = 0.85
		env.glow_strength = 1.0
		env.glow_bloom = 0.06
		env.glow_hdr_threshold = 0.9
		env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SCREEN
		env.adjustment_enabled = true
		env.adjustment_contrast = 1.06
		env.adjustment_saturation = 1.12
	env.fog_enabled = true
	env.fog_light_color = th["fog"]
	env.fog_density = float(th["fog_density"])
	env.fog_sky_affect = 0.0
	var we := WorldEnvironment.new()
	we.environment = env
	parent.add_child(we)

	var sun := DirectionalLight3D.new()
	sun.light_color = th["sun_color"]
	sun.light_energy = float(th["sun_energy"])
	sun.rotation_degrees = th["sun_rot"]
	sun.shadow_enabled = q >= 1
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	sun.directional_shadow_max_distance = 70.0
	sun.shadow_normal_bias = 1.0
	parent.add_child(sun)

	var accents: Array = th["accents"]
	var rim := DirectionalLight3D.new()
	var rc: Color = accents[0]
	rim.light_color = rc
	rim.light_energy = 0.35
	rim.rotation_degrees = Vector3(-22.0, 215.0, 0.0)
	rim.shadow_enabled = false
	parent.add_child(rim)

	var abyss := _make_abyss(th, kill_y + 9.0)
	parent.add_child(abyss)
	_make_scenery(parent, th, theme_id, center, extent, q)
	return {"abyss": abyss}


static func _make_abyss(th: Dictionary, y: float) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(1200.0, 1200.0)
	mi.mesh = pm
	var m := ShaderMaterial.new()
	m.shader = Mats.shader("res://shaders/abyss.gdshader")
	m.set_shader_parameter("line_color", th["abyss_line"])
	m.set_shader_parameter("fill_color", th["abyss_fill"])
	m.set_shader_parameter("cell", 8.0)
	m.set_shader_parameter("fade_dist", 420.0)
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.position = Vector3(0.0, y, 0.0)
	return mi


## Keeps the abyss plane under the camera (the grid itself is anchored in world space).
static func follow_abyss(abyss: MeshInstance3D, cam_pos: Vector3) -> void:
	if abyss == null:
		return
	abyss.position.x = cam_pos.x
	abyss.position.z = cam_pos.z
	var m := abyss.material_override as ShaderMaterial
	if m != null:
		m.set_shader_parameter("center_xz", Vector2(cam_pos.x, cam_pos.z))


static func _make_scenery(parent: Node3D, th: Dictionary, theme_id: String, center: Vector3, extent: float, q: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 4242 + theme_id.hash() % 1000
	var counts: Array = [10, 20, 32]
	var n: int = int(counts[q])
	var accents: Array = th["accents"]
	for i in range(n):
		var ang: float = rng.randf() * TAU
		var dist: float = extent * 0.5 + 30.0 + rng.randf() * 110.0
		var pos := center + Vector3(cos(ang) * dist, rng.randf_range(-35.0, 45.0), sin(ang) * dist)
		var kind: int = rng.randi() % 3
		var mesh: Mesh
		var sc: float = rng.randf_range(3.0, 12.0)
		if kind == 0:
			var sm := SphereMesh.new()
			sm.radius = 1.0
			sm.height = 2.0
			sm.radial_segments = 14
			sm.rings = 7
			mesh = sm
		elif kind == 1:
			var cm := CylinderMesh.new()
			cm.top_radius = 0.6
			cm.bottom_radius = 1.0
			cm.height = 3.2
			cm.radial_segments = 6
			mesh = cm
		else:
			var pr := PrismMesh.new()
			pr.size = Vector3(2.0, 3.0, 2.0)
			mesh = pr
		var mat := ShaderMaterial.new()
		mat.shader = Mats.shader("res://shaders/deco.gdshader")
		var bc: Color = th["base"]
		mat.set_shader_parameter("base", bc.lightened(0.15))
		mat.set_shader_parameter("rim_color", accents[i % accents.size()])
		mat.set_shader_parameter("rim_energy", rng.randf_range(1.0, 2.2))
		mat.set_shader_parameter("glow", rng.randf_range(0.0, 0.25))
		var holder := Fx.Spin.new()
		holder.axis = Vector3(rng.randf_range(-1.0, 1.0), rng.randf_range(0.2, 1.0), rng.randf_range(-1.0, 1.0)).normalized()
		holder.speed = rng.randf_range(0.03, 0.18)
		parent.add_child(holder)
		holder.position = pos
		var mi := MeshInstance3D.new()
		mi.mesh = mesh
		mi.material_override = mat
		mi.scale = Vector3(sc, sc * rng.randf_range(0.6, 1.5), sc)
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		holder.add_child(mi)


## Soft drifting sparks around the camera. Parent the result to the Camera3D.
static func make_motes(theme_id: String) -> CPUParticles3D:
	var th: Dictionary = theme(theme_id)
	var q: int = Game.quality()
	var amounts: Array = [36, 70, 120]
	var p := CPUParticles3D.new()
	p.mesh = Fx.quad()
	p.amount = int(amounts[q])
	p.lifetime = 8.0
	p.preprocess = 6.0
	p.local_coords = false
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	p.emission_box_extents = Vector3(28.0, 14.0, 28.0)
	p.direction = Vector3.UP
	p.spread = 180.0
	p.initial_velocity_min = 0.2
	p.initial_velocity_max = 0.7
	p.gravity = Vector3(0.0, float(th["mote_gravity"]), 0.0)
	p.scale_amount_min = 0.1
	p.scale_amount_max = 0.26
	p.color = th["mote_color"]
	p.position = Vector3(0.0, 0.0, -8.0)
	return p
