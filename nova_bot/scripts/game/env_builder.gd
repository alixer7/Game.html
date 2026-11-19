class_name EnvBuilder
extends RefCounted
## World look per theme: procedural sky (planets, nebula, aurora, black hole), lighting + fog + post FX,
## an animated sea far below (clouds / lava / icy mist / galactic void), big distant landmarks (rocket and
## gantry, ring station, crystal spires, smokestacks and gears, ice peaks, accretion disk) and dressing for
## every platform (floating-island undersides, hanging crystals / icicles / thrusters, breakable props).

const THEMES := ["launch", "crystal", "foundry", "ice", "core"]


## Colour / lighting recipe for a theme id.
static func theme(id: String) -> Dictionary:
	if id == "crystal":
		return {
			"sky": {
				"top_color": Color(0.04, 0.01, 0.12), "mid_color": Color(0.22, 0.06, 0.36), "horizon_color": Color(0.85, 0.35, 0.62),
				"bottom_color": Color(0.12, 0.04, 0.2), "nebula_a": Color(0.95, 0.3, 0.8), "nebula_b": Color(0.35, 0.55, 1.0),
				"nebula_amount": 1.0, "star_amount": 1.0, "sun_dir": Vector3(0.5, 0.35, -0.7), "sun_color": Color(1.0, 0.8, 0.9),
				"planet_dir": Vector3(0.65, 0.32, -0.7), "planet_size": 0.16, "planet_color": Color(0.95, 0.45, 0.8),
				"planet_color2": Color(0.45, 0.3, 1.0), "seed": 7.0,
			},
			"accents": [Color(1.0, 0.35, 0.85), Color(0.65, 0.45, 1.0), Color(0.3, 0.9, 1.0), Color(1.0, 0.6, 0.3)],
			"surf": {"style": 1, "base": Color(0.36, 0.3, 0.44), "top": Color(0.6, 0.54, 0.68), "trim": Color(1.0, 0.7, 0.9)},
			"rock": {"style": 1, "a": Color(0.36, 0.28, 0.44), "b": Color(0.16, 0.11, 0.22), "vein": Color(1.0, 0.35, 0.9), "amount": 0.8},
			"sea": {"mode": 0, "a": Color(0.62, 0.38, 0.72), "b": Color(0.16, 0.06, 0.26), "glow": Color(1.0, 0.6, 0.9)},
			"fog": Color(0.38, 0.2, 0.48), "fog_density": 0.0014, "fog_height_density": 0.05,
			"ambient": Color(0.75, 0.62, 0.92), "ambient_energy": 0.5,
			"sun_color": Color(1.0, 0.88, 0.95), "sun_energy": 1.25, "sun_rot": Vector3(-42.0, 150.0, 0.0),
			"mote": "pollen", "mote_color": Color(1.0, 0.65, 0.95, 0.6),
		}
	if id == "foundry":
		return {
			"sky": {
				"top_color": Color(0.08, 0.03, 0.04), "mid_color": Color(0.36, 0.1, 0.06), "horizon_color": Color(1.0, 0.52, 0.2),
				"bottom_color": Color(0.2, 0.05, 0.02), "nebula_a": Color(1.0, 0.45, 0.12), "nebula_b": Color(0.85, 0.12, 0.25),
				"nebula_amount": 0.8, "star_amount": 0.6, "sun_dir": Vector3(-0.4, 0.3, -0.8), "sun_color": Color(1.0, 0.7, 0.4),
				"planet_dir": Vector3(-0.7, 0.22, -0.7), "planet_size": 0.22, "planet_color": Color(1.0, 0.5, 0.15),
				"planet_color2": Color(0.7, 0.15, 0.1), "seed": 13.0,
			},
			"accents": [Color(1.0, 0.55, 0.15), Color(1.0, 0.82, 0.25), Color(1.0, 0.3, 0.3), Color(0.25, 0.9, 0.9)],
			"surf": {"style": 2, "base": Color(0.24, 0.22, 0.22), "top": Color(0.48, 0.46, 0.45), "trim": Color(1.0, 0.45, 0.1)},
			"rock": {"style": 2, "a": Color(0.25, 0.2, 0.19), "b": Color(0.1, 0.08, 0.08), "vein": Color(1.0, 0.4, 0.08), "amount": 1.4},
			"sea": {"mode": 1, "a": Color(0.9, 0.25, 0.04), "b": Color(0.12, 0.03, 0.02), "glow": Color(1.0, 0.55, 0.15)},
			"fog": Color(0.42, 0.16, 0.07), "fog_density": 0.0018, "fog_height_density": 0.05,
			"ambient": Color(1.0, 0.72, 0.55), "ambient_energy": 0.5,
			"sun_color": Color(1.0, 0.82, 0.62), "sun_energy": 1.3, "sun_rot": Vector3(-40.0, -35.0, 0.0),
			"mote": "embers", "mote_color": Color(1.0, 0.55, 0.2, 0.85),
		}
	if id == "ice":
		return {
			"sky": {
				"top_color": Color(0.01, 0.03, 0.1), "mid_color": Color(0.05, 0.14, 0.3), "horizon_color": Color(0.45, 0.75, 0.95),
				"bottom_color": Color(0.1, 0.18, 0.3), "nebula_a": Color(0.3, 0.7, 1.0), "nebula_b": Color(0.4, 0.3, 0.9),
				"nebula_amount": 0.6, "star_amount": 1.2, "sun_dir": Vector3(0.3, 0.25, -0.9), "sun_color": Color(0.9, 0.95, 1.0),
				"planet_dir": Vector3(-0.6, 0.35, -0.7), "planet_size": 0.12, "planet_color": Color(0.7, 0.85, 1.0),
				"planet_color2": Color(0.35, 0.5, 0.9), "seed": 31.0, "aurora": 1.0,
				"aurora_a": Color(0.2, 1.0, 0.65), "aurora_b": Color(0.55, 0.3, 1.0),
			},
			"accents": [Color(0.35, 0.85, 1.0), Color(0.55, 0.6, 1.0), Color(0.35, 1.0, 0.75), Color(1.0, 0.55, 0.75)],
			"surf": {"style": 3, "base": Color(0.25, 0.5, 0.75), "top": Color(0.84, 0.88, 0.94), "trim": Color(0.8, 0.95, 1.0)},
			"rock": {"style": 3, "a": Color(0.5, 0.6, 0.72), "b": Color(0.22, 0.3, 0.42), "vein": Color(0.5, 0.9, 1.0), "amount": 0.9},
			"sea": {"mode": 2, "a": Color(0.7, 0.82, 0.95), "b": Color(0.16, 0.26, 0.45), "glow": Color(0.8, 0.95, 1.0)},
			"fog": Color(0.4, 0.55, 0.75), "fog_density": 0.0015, "fog_height_density": 0.05,
			"ambient": Color(0.7, 0.82, 1.0), "ambient_energy": 0.6,
			"sun_color": Color(0.95, 0.97, 1.0), "sun_energy": 1.2, "sun_rot": Vector3(-35.0, 20.0, 0.0),
			"mote": "snow", "mote_color": Color(0.95, 0.98, 1.0, 0.85),
		}
	if id == "core":
		return {
			"sky": {
				"top_color": Color(0.01, 0.0, 0.04), "mid_color": Color(0.08, 0.03, 0.22), "horizon_color": Color(0.35, 0.22, 0.75),
				"bottom_color": Color(0.03, 0.01, 0.08), "nebula_a": Color(0.5, 0.3, 1.0), "nebula_b": Color(0.1, 0.85, 0.95),
				"nebula_amount": 1.3, "star_amount": 1.4, "sun_dir": Vector3(0.2, 0.6, -0.8), "sun_color": Color(0.9, 0.85, 1.0),
				"planet_dir": Vector3(-0.7, 0.3, 0.6), "planet_size": 0.06, "planet_color": Color(0.6, 0.5, 1.0),
				"planet_color2": Color(0.2, 0.9, 0.9), "seed": 21.0,
				"hole": 1.0, "hole_dir": Vector3(0.15, 0.22, -1.0), "hole_size": 0.09,
				"disk_a": Color(1.0, 0.75, 0.4), "disk_b": Color(0.6, 0.3, 1.0),
			},
			"accents": [Color(0.65, 0.45, 1.0), Color(0.2, 0.95, 1.0), Color(1.0, 0.4, 0.85), Color(1.0, 0.85, 0.3)],
			"surf": {"style": 4, "base": Color(0.05, 0.05, 0.09), "top": Color(0.12, 0.1, 0.2), "trim": Color(1.0, 0.78, 0.35)},
			"rock": {"style": 4, "a": Color(0.16, 0.12, 0.24), "b": Color(0.05, 0.04, 0.09), "vein": Color(0.6, 0.4, 1.0), "amount": 1.4},
			"sea": {"mode": 3, "a": Color(0.5, 0.3, 1.0), "b": Color(0.02, 0.01, 0.06), "glow": Color(0.9, 0.7, 1.0)},
			"fog": Color(0.18, 0.1, 0.38), "fog_density": 0.0018, "fog_height_density": 0.05,
			"ambient": Color(0.72, 0.66, 1.0), "ambient_energy": 0.6,
			"sun_color": Color(0.92, 0.88, 1.0), "sun_energy": 1.15, "sun_rot": Vector3(-50.0, 20.0, 0.0),
			"mote": "stars", "mote_color": Color(0.8, 0.85, 1.0, 0.7),
		}
	return {
		"sky": {
			"top_color": Color(0.01, 0.03, 0.14), "mid_color": Color(0.06, 0.18, 0.46), "horizon_color": Color(0.4, 0.66, 0.95),
			"bottom_color": Color(0.1, 0.2, 0.42), "nebula_a": Color(0.15, 0.5, 1.0), "nebula_b": Color(0.6, 0.3, 0.95),
			"nebula_amount": 0.8, "star_amount": 1.0, "sun_dir": Vector3(0.45, 0.45, -0.75), "sun_color": Color(1.0, 0.92, 0.75),
			"planet_dir": Vector3(-0.55, 0.3, -0.8), "planet_size": 0.2, "planet_color": Color(0.25, 0.6, 1.0),
			"planet_color2": Color(0.35, 0.85, 0.6), "seed": 1.0,
		},
		"accents": [Color(0.2, 0.9, 1.0), Color(0.35, 0.6, 1.0), Color(0.3, 1.0, 0.75), Color(1.0, 0.6, 0.25)],
		"surf": {"style": 0, "base": Color(0.36, 0.4, 0.48), "top": Color(0.7, 0.74, 0.8), "trim": Color(1.0, 0.72, 0.12)},
		"rock": {"style": 0, "a": Color(0.55, 0.58, 0.65), "b": Color(0.3, 0.33, 0.4), "vein": Color(0.4, 0.9, 1.0), "amount": 1.0},
		"sea": {"mode": 0, "a": Color(0.72, 0.8, 0.94), "b": Color(0.2, 0.3, 0.55), "glow": Color(1.0, 0.92, 0.8)},
		"fog": Color(0.4, 0.55, 0.82), "fog_density": 0.0013, "fog_height_density": 0.045,
		"ambient": Color(0.65, 0.75, 1.0), "ambient_energy": 0.55,
		"sun_color": Color(1.0, 0.94, 0.84), "sun_energy": 1.3, "sun_rot": Vector3(-48.0, 35.0, 0.0),
		"mote": "dust", "mote_color": Color(0.8, 0.92, 1.0, 0.45),
	}


# ======================================================================== environment
## Adds WorldEnvironment, lights, the sea and landmarks under `parent`. Returns {"abyss": MeshInstance3D}.
static func build(parent: Node3D, theme_id: String, center: Vector3, kill_y: float, extent: float, mn: Vector3 = Vector3.ZERO, mx: Vector3 = Vector3.ZERO) -> Dictionary:
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
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_color = th["ambient"]
	env.ambient_light_sky_contribution = 0.55
	env.ambient_light_energy = float(th["ambient_energy"]) * 1.15
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = 0.95
	env.tonemap_white = 6.0
	if q >= 1:
		env.glow_enabled = true
		env.glow_intensity = 0.55
		env.glow_strength = 0.95
		env.glow_bloom = 0.03
		env.glow_hdr_threshold = 1.1
		env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SOFTLIGHT
		env.set_glow_level(0, 0.0)
		env.set_glow_level(1, 0.6)
		env.set_glow_level(2, 1.0)
		env.set_glow_level(3, 0.6)
		env.set_glow_level(4, 0.3)
		env.adjustment_enabled = true
		env.adjustment_contrast = 1.08
		env.adjustment_saturation = 1.12
	if q >= 2 and RenderingServer.get_current_rendering_method() == "forward_plus":
		env.ssao_enabled = true
		env.ssao_radius = 1.4
		env.ssao_intensity = 1.6
		env.ssao_power = 1.3
	env.fog_enabled = true
	env.fog_light_color = th["fog"]
	env.fog_light_energy = 1.0
	env.fog_density = float(th["fog_density"])
	env.fog_aerial_perspective = 0.2
	env.fog_sky_affect = 0.0
	env.fog_height = kill_y + 18.0
	env.fog_height_density = float(th["fog_height_density"])
	var we := WorldEnvironment.new()
	we.environment = env
	parent.add_child(we)

	var sun := DirectionalLight3D.new()
	sun.light_color = th["sun_color"]
	sun.light_energy = float(th["sun_energy"])
	sun.rotation_degrees = th["sun_rot"]
	sun.shadow_enabled = q >= 1
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS if q >= 2 else DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	sun.directional_shadow_max_distance = 80.0
	sun.shadow_normal_bias = 1.0
	sun.shadow_blur = 1.5
	parent.add_child(sun)

	var accents: Array = th["accents"]
	var rim := DirectionalLight3D.new()
	var rc: Color = accents[0]
	rim.light_color = rc
	rim.light_energy = 0.4
	rim.rotation_degrees = Vector3(-18.0, float((th["sun_rot"] as Vector3).y) + 180.0, 0.0)
	rim.shadow_enabled = false
	parent.add_child(rim)

	var abyss := _make_sea(th, kill_y + 6.0)
	parent.add_child(abyss)
	if mx == mn:
		mn = center - Vector3(extent, 10.0, extent)
		mx = center + Vector3(extent, 10.0, extent)
	var land := Node3D.new()
	land.name = "Landmarks"
	parent.add_child(land)
	_landmarks(land, theme_id, th, mn, mx, kill_y, q)
	return {"abyss": abyss}


static func _make_sea(th: Dictionary, y: float) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(1600.0, 1600.0)
	mi.mesh = pm
	var sea: Dictionary = th["sea"]
	var m := ShaderMaterial.new()
	m.shader = Mats.shader("res://shaders/clouds.gdshader")
	m.set_shader_parameter("mode", int(sea["mode"]))
	m.set_shader_parameter("col_a", sea["a"])
	m.set_shader_parameter("col_b", sea["b"])
	m.set_shader_parameter("glow", sea["glow"])
	m.set_shader_parameter("fade_dist", 650.0)
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.position = Vector3(0.0, y, 0.0)
	return mi


## Keeps the sea plane under the camera (its pattern is anchored in world space).
static func follow_abyss(abyss: MeshInstance3D, cam_pos: Vector3) -> void:
	if abyss == null:
		return
	abyss.position.x = cam_pos.x
	abyss.position.z = cam_pos.z
	var m := abyss.material_override as ShaderMaterial
	if m != null:
		m.set_shader_parameter("center_xz", Vector2(cam_pos.x, cam_pos.z))


# ======================================================================== landmarks
static func _ring_points(mn: Vector3, mx: Vector3, n: int, margin: float, rng: RandomNumberGenerator) -> Array:
	var out: Array = []
	var c: Vector3 = (mn + mx) * 0.5
	var hx: float = (mx.x - mn.x) * 0.5 + margin
	var hz: float = (mx.z - mn.z) * 0.5 + margin
	for i in range(n):
		var a: float = TAU * (float(i) + rng.randf_range(-0.25, 0.25)) / float(n)
		var dx: float = cos(a)
		var dz: float = sin(a)
		var k: float = 1.0 / maxf(absf(dx) / hx, absf(dz) / hz)
		out.append(Vector3(c.x + dx * k, c.y, c.z + dz * k))
	return out


static func _landmarks(parent: Node3D, id: String, th: Dictionary, mn: Vector3, mx: Vector3, kill_y: float, q: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 991 + id.hash() % 1000
	var n: int = [6, 10, 14][q]
	var pts: Array = _ring_points(mn, mx, n, rng.randf_range(55.0, 75.0), rng)
	var base_y: float = kill_y + 4.0
	var rock_mat: ShaderMaterial = Mats.rock()
	for i in range(pts.size()):
		var p: Vector3 = pts[i]
		var holder := Node3D.new()
		parent.add_child(holder)
		holder.position = Vector3(p.x, base_y, p.z)
		holder.rotation.y = rng.randf() * TAU
		var kind: int = i % 3
		match id:
			"launch":
				if kind == 0:
					_lm_rocket(holder, rng, th)
				elif kind == 1:
					_lm_dish_rock(holder, rng, rock_mat, th)
				else:
					_lm_tower(holder, rng, th)
			"crystal":
				_lm_crystal_spire(holder, rng, rock_mat, th, kind)
			"foundry":
				if kind == 0:
					_lm_stack(holder, rng, th, q)
				elif kind == 1:
					_lm_gear(holder, rng, th)
				else:
					_lm_refinery(holder, rng, th)
			"ice":
				_lm_ice_peak(holder, rng, rock_mat, th, kind)
			_:
				if kind == 0:
					_lm_obelisk(holder, rng, th)
				else:
					_lm_orbit_rings(holder, rng, th)
	# one hero piece in the sky per world
	var c: Vector3 = (mn + mx) * 0.5
	var far: float = maxf(mx.x - mn.x, mx.z - mn.z) * 0.5 + 220.0
	match id:
		"launch":
			_lm_ring_station(parent, c + Vector3(-far * 0.5, 90.0, -far), th)
		"core":
			_lm_accretion(parent, c + Vector3(far * 0.25, 70.0, -far * 1.1), th)
		"foundry":
			_lm_gear(parent, rng, th, c + Vector3(far * 0.6, 20.0, -far * 0.9), 60.0)
		_:
			pass


static func _vis(mi: GeometryInstance3D, far: float = 900.0) -> void:
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.visibility_range_end = far


static func _lm_rocket(h: Node3D, rng: RandomNumberGenerator, th: Dictionary) -> void:
	var s: float = rng.randf_range(0.8, 1.2)
	var rock: ShaderMaterial = Mats.rock()
	_vis(Geo.put(h, Geo.island(22.0 * s, 22.0 * s, 26.0 * s, rng.randi() % 50, true, 0.3), rock, Vector3.ZERO))
	_vis(Geo.put(h, Geo.cyl(22.0 * s, 22.0 * s, 2.0, 40), Mats.platform(Vector3(22.0 * s, 1.0, 22.0 * s), 0, true), Vector3(0.0, 1.0, 0.0)))
	var white: Material = Mats.plastic(Color(0.92, 0.93, 0.95), 0.35)
	var orange: Material = Mats.plastic(Color(1.0, 0.5, 0.12), 0.4)
	var dark: Material = Mats.metal(Color(0.15, 0.16, 0.2), 0.4, 0.7)
	var r: float = 4.2 * s
	var prof := PackedVector2Array([Vector2(0.0, 0.0), Vector2(r * 0.8, 0.0), Vector2(r, 3.0), Vector2(r, 42.0 * s), Vector2(r * 0.85, 50.0 * s), Vector2(r * 0.4, 58.0 * s), Vector2(0.0, 62.0 * s)])
	var rk := Node3D.new()
	rk.position = Vector3(0.0, 6.0, 0.0)
	h.add_child(rk)
	_vis(Geo.put(rk, Geo.lathe(prof, 32, "rocket%.2f" % s), white))
	for b in [12.0, 30.0, 44.0]:
		_vis(Geo.put(rk, Geo.cyl(r * 1.01, r * 1.01, 2.0 * s, 32), orange, Vector3(0.0, float(b) * s, 0.0)))
	for i in range(4):
		var a: float = TAU * float(i) / 4.0
		var fin := Geo.put(rk, Geo.rounded_box(Vector3(0.8 * s, 10.0 * s, 5.0 * s), 0.3, 2), orange, Vector3(cos(a) * r * 1.1, 6.0 * s, sin(a) * r * 1.1), Vector3(0.0, -rad_to_deg(a), 0.0))
		_vis(fin)
	_vis(Geo.put(rk, Geo.cyl(r * 0.5, r * 0.8, 4.0 * s, 20), dark, Vector3(0.0, -1.5, 0.0)))
	_vis(Geo.put(rk, Geo.sphere(r * 0.6, 16), Mats.glow(Color(0.4, 0.8, 1.0), 2.0), Vector3(0.0, -3.0, 0.0), Vector3.ZERO, Vector3(1.0, 0.4, 1.0)))
	_lm_truss(h, Vector3(r * 2.4, 2.0, 0.0), 58.0 * s, 4.0 * s, th)


static func _lm_truss(h: Node3D, at: Vector3, height: float, w: float, th: Dictionary) -> void:
	var steel: Material = Mats.metal(Color(0.55, 0.22, 0.12), 0.5, 0.6)
	var acc: Color = (th["accents"] as Array)[0]
	var n: int = int(height / w)
	for cx in [-1.0, 1.0]:
		for cz in [-1.0, 1.0]:
			_vis(Geo.put(h, Geo.box(Vector3(0.5, height, 0.5)), steel, at + Vector3(float(cx) * w * 0.5, height * 0.5, float(cz) * w * 0.5)))
	for i in range(n):
		var y: float = float(i) * w + w * 0.5
		_vis(Geo.put(h, Geo.box(Vector3(w, 0.35, 0.35)), steel, at + Vector3(0.0, y, w * 0.5)))
		_vis(Geo.put(h, Geo.box(Vector3(w, 0.35, 0.35)), steel, at + Vector3(0.0, y, -w * 0.5)))
		_vis(Geo.put(h, Geo.box(Vector3(0.35, 0.35, w)), steel, at + Vector3(w * 0.5, y, 0.0)))
		var diag := Geo.put(h, Geo.box(Vector3(0.25, w * 1.38, 0.25)), steel, at + Vector3(-w * 0.5, y, 0.0), Vector3(45.0, 0.0, 0.0))
		_vis(diag)
		if i % 3 == 0:
			_vis(Geo.put(h, Geo.sphere(0.4, 8), Mats.glow(Color(1.0, 0.25, 0.2) if i % 2 == 0 else acc, 3.0), at + Vector3(w * 0.5, y, w * 0.5)))


static func _lm_tower(h: Node3D, rng: RandomNumberGenerator, th: Dictionary) -> void:
	var rock: ShaderMaterial = Mats.rock()
	var s: float = rng.randf_range(0.7, 1.1)
	_vis(Geo.put(h, Geo.island(14.0 * s, 14.0 * s, 20.0 * s, rng.randi() % 50, false, 0.3), rock, Vector3.ZERO))
	var white: Material = Mats.plastic(Color(0.85, 0.88, 0.92), 0.35)
	var hcount: int = rng.randi_range(2, 4)
	var y: float = 0.0
	for i in range(hcount):
		var w: float = (12.0 - float(i) * 2.5) * s
		var hh: float = rng.randf_range(8.0, 14.0) * s
		_vis(Geo.put(h, Geo.rounded_box(Vector3(w, hh, w), 1.2, 2), white, Vector3(0.0, y + hh * 0.5, 0.0)))
		_vis(Geo.put(h, Geo.box(Vector3(w * 1.02, 0.6, w * 1.02)), Mats.glow((th["accents"] as Array)[i % 4], 2.0), Vector3(0.0, y + hh - 1.0, 0.0)))
		y += hh
	_vis(Geo.put(h, Geo.cyl(0.25, 0.4, 14.0 * s, 8), Mats.metal(Color(0.6, 0.62, 0.68), 0.3, 0.9), Vector3(0.0, y + 7.0 * s, 0.0)))
	_vis(Geo.put(h, Geo.sphere(0.9, 10), Mats.glow(Color(1.0, 0.3, 0.25), 4.0), Vector3(0.0, y + 14.0 * s, 0.0)))
	var dish := Geo.put(h, Geo.lathe(PackedVector2Array([Vector2(0.0, 0.0), Vector2(3.0, 0.6), Vector2(6.0, 2.4), Vector2(6.2, 2.6)]), 24, "dish"), white, Vector3(4.0 * s, y + 2.0, 0.0), Vector3(0.0, 0.0, 35.0))
	_vis(dish)


static func _lm_dish_rock(h: Node3D, rng: RandomNumberGenerator, rock: ShaderMaterial, th: Dictionary) -> void:
	var s: float = rng.randf_range(8.0, 15.0)
	var ry: float = rng.randf_range(10.0, 40.0)
	_vis(Geo.put(h, Geo.rock(1.0, rng.randi() % 30, 2, 0.28), rock, Vector3(0.0, ry, 0.0), Vector3.ZERO, Vector3(s, s * 0.7, s)))
	var white: Material = Mats.plastic(Color(0.9, 0.92, 0.95), 0.3)
	var top: float = ry + s * 0.55
	_vis(Geo.put(h, Geo.cyl(0.4, 0.6, 5.0, 10), white, Vector3(0.0, top + 2.0, 0.0)))
	_vis(Geo.put(h, Geo.lathe(PackedVector2Array([Vector2(0.0, 0.0), Vector2(2.0, 0.4), Vector2(4.5, 1.8), Vector2(4.6, 2.0)]), 24, "dish2"), white, Vector3(0.0, top + 4.5, 0.0), Vector3(40.0, rng.randf() * 360.0, 0.0)))
	_vis(Geo.put(h, Geo.sphere(0.5, 10), Mats.glow((th["accents"] as Array)[0], 3.0), Vector3(0.0, top + 6.5, 0.0)))


static func _lm_ring_station(parent: Node3D, at: Vector3, th: Dictionary) -> void:
	var sp := Fx.Spin.new()
	sp.axis = Vector3(0.15, 1.0, 0.1).normalized()
	sp.speed = 0.02
	parent.add_child(sp)
	sp.position = at
	sp.rotation_degrees = Vector3(70.0, 20.0, 0.0)
	var white: Material = Mats.plastic(Color(0.85, 0.87, 0.92), 0.4)
	_vis(Geo.put(sp, Geo.torus(70.0, 82.0, 96, 12), white), 2000.0)
	_vis(Geo.put(sp, Geo.torus(81.0, 82.5, 96, 6), Mats.glow((th["accents"] as Array)[0], 2.0)), 2000.0)
	for i in range(6):
		var a: float = TAU * float(i) / 6.0
		_vis(Geo.put(sp, Geo.box(Vector3(70.0, 3.0, 3.0)), white, Vector3(cos(a) * 36.0, 0.0, sin(a) * 36.0), Vector3(0.0, -rad_to_deg(a), 0.0)), 2000.0)
	_vis(Geo.put(sp, Geo.sphere(12.0, 24), white), 2000.0)
	_vis(Geo.put(sp, Geo.torus(12.0, 14.0, 40, 6), Mats.glow(Color(1.0, 0.7, 0.3), 2.0)), 2000.0)


static func _lm_crystal_spire(h: Node3D, rng: RandomNumberGenerator, rock: ShaderMaterial, th: Dictionary, kind: int) -> void:
	var s: float = rng.randf_range(0.7, 1.3) * (1.4 if kind == 0 else 1.0)
	var y: float = rng.randf_range(0.0, 30.0)
	_vis(Geo.put(h, Geo.island(12.0 * s, 10.0 * s, 24.0 * s, rng.randi() % 50, true, 0.4), rock, Vector3(0.0, y, 0.0)))
	var acc: Array = th["accents"]
	var cn: int = rng.randi_range(3, 6)
	for i in range(cn):
		var col: Color = acc[(i + kind) % 3]
		var mat: Material = Mats.plastic(col.lerp(Color(1, 1, 1), 0.2), 0.12, col, 1.4, 0.4)
		var hh: float = rng.randf_range(12.0, 34.0) * s
		var a: float = rng.randf() * TAU
		var d: float = rng.randf_range(0.0, 6.0) * s
		_vis(Geo.put(h, Geo.crystal(rng.randf_range(2.0, 4.0) * s, hh, hh * 0.25, 6), mat, Vector3(cos(a) * d, y - 1.0, sin(a) * d), Vector3(rng.randf_range(-18.0, 18.0), rng.randf() * 60.0, rng.randf_range(-18.0, 18.0))))
	for i in range(3):
		var a2: float = rng.randf() * TAU
		_vis(Geo.put(h, Geo.crystal(1.5 * s, 6.0 * s, 2.0 * s, 6), Mats.glow(acc[i % 3], 1.6), Vector3(cos(a2) * 6.0 * s, y - 10.0 * s, sin(a2) * 6.0 * s), Vector3(180.0, 0.0, rng.randf_range(-15.0, 15.0))))


static func _lm_stack(h: Node3D, rng: RandomNumberGenerator, th: Dictionary, q: int) -> void:
	var s: float = rng.randf_range(0.8, 1.3)
	var steel: Material = Mats.metal(Color(0.3, 0.27, 0.26), 0.6, 0.7)
	var rust: Material = Mats.metal(Color(0.45, 0.2, 0.1), 0.8, 0.3)
	var hh: float = 90.0 * s
	_vis(Geo.put(h, Geo.lathe(PackedVector2Array([Vector2(0.0, 0.0), Vector2(9.0 * s, 0.0), Vector2(7.0 * s, 10.0), Vector2(5.5 * s, hh), Vector2(6.2 * s, hh + 1.0), Vector2(6.2 * s, hh + 3.0), Vector2(5.0 * s, hh + 3.0)]), 24, "stack%.2f" % s), steel))
	for b in range(4):
		_vis(Geo.put(h, Geo.cyl(6.6 * s - float(b) * 0.3, 6.6 * s - float(b) * 0.3, 2.0, 24), rust, Vector3(0.0, 20.0 + float(b) * 18.0 * s, 0.0)))
	_vis(Geo.put(h, Geo.cyl(5.3 * s, 5.3 * s, 0.5, 24), Mats.glow(Color(1.0, 0.45, 0.1), 3.0), Vector3(0.0, hh + 2.6, 0.0)))
	if q >= 1:
		var smoke := CPUParticles3D.new()
		smoke.mesh = Fx.quad()
		smoke.amount = 16
		smoke.lifetime = 7.0
		smoke.preprocess = 7.0
		smoke.local_coords = false
		smoke.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
		smoke.emission_sphere_radius = 4.0 * s
		smoke.direction = Vector3(0.3, 1.0, 0.0)
		smoke.spread = 15.0
		smoke.initial_velocity_min = 4.0
		smoke.initial_velocity_max = 6.0
		smoke.gravity = Vector3(1.2, 0.5, 0.0)
		smoke.scale_amount_min = 10.0
		smoke.scale_amount_max = 22.0
		smoke.color = Color(0.25, 0.18, 0.16, 0.35)
		smoke.color_ramp = Fx.fade_ramp()
		smoke.position = Vector3(0.0, hh + 4.0, 0.0)
		h.add_child(smoke)


static func _lm_gear(parent: Node3D, rng: RandomNumberGenerator, th: Dictionary, at: Vector3 = Vector3.INF, size: float = 0.0) -> void:
	var r: float = size if size > 0.0 else rng.randf_range(14.0, 26.0)
	var sp := Fx.Spin.new()
	sp.axis = Vector3(0.0, 0.0, 1.0)
	sp.speed = (0.08 if size <= 0.0 else 0.03) * (1.0 if rng.randf() < 0.5 else -1.0)
	parent.add_child(sp)
	if at != Vector3.INF:
		sp.position = at
	else:
		sp.position = Vector3(0.0, rng.randf_range(20.0, 50.0), 0.0)
	sp.rotation_degrees.y = rng.randf() * 180.0
	var steel: Material = Mats.metal(Color(0.32, 0.29, 0.28), 0.5, 0.8)
	var g := Node3D.new()
	sp.add_child(g)
	g.rotation_degrees = Vector3(90.0, 0.0, 0.0)
	_vis(Geo.put(g, Geo.cyl(r * 0.88, r * 0.88, r * 0.18, 48), steel), 2000.0)
	_vis(Geo.put(g, Geo.cyl(r * 0.25, r * 0.25, r * 0.3, 24), Mats.metal(Color(0.5, 0.45, 0.4), 0.3, 0.9)), 2000.0)
	var teeth: int = int(r * 1.3)
	for i in range(teeth):
		var a: float = TAU * float(i) / float(teeth)
		_vis(Geo.put(g, Geo.box(Vector3(r * 0.16, r * 0.17, r * 0.2)), steel, Vector3(cos(a) * r * 0.95, 0.0, sin(a) * r * 0.95), Vector3(0.0, -rad_to_deg(a), 0.0)), 2000.0)
	for i in range(6):
		var a2: float = TAU * float(i) / 6.0
		_vis(Geo.put(g, Geo.cyl(r * 0.12, r * 0.12, r * 0.2, 16), Mats.glow(Color(1.0, 0.45, 0.1), 1.2), Vector3(cos(a2) * r * 0.55, 0.0, sin(a2) * r * 0.55)), 2000.0)


static func _lm_refinery(h: Node3D, rng: RandomNumberGenerator, th: Dictionary) -> void:
	var steel: Material = Mats.metal(Color(0.35, 0.3, 0.28), 0.55, 0.75)
	var y: float = rng.randf_range(0.0, 20.0)
	for i in range(rng.randi_range(2, 4)):
		var w: float = rng.randf_range(6.0, 12.0)
		var hh: float = rng.randf_range(15.0, 45.0)
		var p := Vector3(rng.randf_range(-12.0, 12.0), y + hh * 0.5, rng.randf_range(-12.0, 12.0))
		_vis(Geo.put(h, Geo.rounded_box(Vector3(w, hh, w), 0.6, 2), steel, p))
		for k in range(int(hh / 6.0)):
			_vis(Geo.put(h, Geo.box(Vector3(w * 1.01, 0.8, 1.2)), Mats.glow(Color(1.0, 0.55, 0.15), 1.6), p + Vector3(0.0, -hh * 0.5 + 3.0 + float(k) * 6.0, -w * 0.5)))
	var path := PackedVector3Array([Vector3(-15.0, y + 10.0, 0.0), Vector3(-5.0, y + 22.0, 3.0), Vector3(8.0, y + 22.0, -2.0), Vector3(16.0, y + 12.0, 0.0)])
	_vis(Geo.put(h, Geo.tube(path, 1.2, 10), Mats.metal(Color(0.6, 0.35, 0.15), 0.4, 0.8)))


static func _lm_ice_peak(h: Node3D, rng: RandomNumberGenerator, rock: ShaderMaterial, th: Dictionary, kind: int) -> void:
	var s: float = rng.randf_range(0.8, 1.4)
	var snow: Material = Mats.std(Color(0.92, 0.96, 1.0), 0.0, 0.7)
	var ice: Material = Mats.plastic(Color(0.55, 0.8, 1.0), 0.08, Color(0.3, 0.6, 1.0), 0.4, 0.6)
	if kind == 2:
		_vis(Geo.put(h, Geo.island(10.0 * s, 10.0 * s, 18.0 * s, rng.randi() % 50, true, 0.35), rock, Vector3(0.0, 20.0, 0.0)))
		for i in range(5):
			var a: float = rng.randf() * TAU
			_vis(Geo.put(h, Geo.crystal(rng.randf_range(1.5, 3.0) * s, rng.randf_range(10.0, 24.0) * s, 5.0 * s, 6), ice, Vector3(cos(a) * 4.0 * s, 19.0, sin(a) * 4.0 * s), Vector3(rng.randf_range(-15.0, 15.0), 0.0, rng.randf_range(-15.0, 15.0))))
		return
	var peak := Geo.put(h, Geo.rock(1.0, rng.randi() % 40, 2, 0.22), rock, Vector3(0.0, 10.0 * s, 0.0), Vector3.ZERO, Vector3(28.0 * s, 70.0 * s, 26.0 * s))
	_vis(peak)
	_vis(Geo.put(h, Geo.rock(1.0, rng.randi() % 40 + 7, 2, 0.15), snow, Vector3(0.0, 48.0 * s, 0.0), Vector3.ZERO, Vector3(17.0 * s, 30.0 * s, 16.0 * s)))
	for i in range(3):
		var a2: float = rng.randf() * TAU
		_vis(Geo.put(h, Geo.crystal(2.5 * s, 18.0 * s, 6.0 * s, 6), ice, Vector3(cos(a2) * 22.0 * s, 0.0, sin(a2) * 22.0 * s), Vector3(rng.randf_range(-10.0, 10.0), 0.0, rng.randf_range(-10.0, 10.0))))


static func _lm_obelisk(h: Node3D, rng: RandomNumberGenerator, th: Dictionary) -> void:
	var s: float = rng.randf_range(0.8, 1.3)
	var dark: Material = Mats.metal(Color(0.06, 0.05, 0.1), 0.2, 0.5)
	var gold: Material = Mats.metal(Color(1.0, 0.78, 0.35), 0.25, 1.0, Color(1.0, 0.7, 0.3), 0.4)
	var y: float = rng.randf_range(10.0, 40.0)
	var sp := Fx.Spin.new()
	sp.speed = 0.1
	h.add_child(sp)
	sp.position = Vector3(0.0, y, 0.0)
	_vis(Geo.put(sp, Geo.crystal(4.0 * s, 40.0 * s, 12.0 * s, 4), dark, Vector3(0.0, -20.0 * s, 0.0)))
	for i in range(4):
		_vis(Geo.put(sp, Geo.torus(6.0 * s, 6.6 * s, 4, 4), gold, Vector3(0.0, -10.0 * s + float(i) * 8.0 * s, 0.0)))
	_vis(Geo.put(sp, Geo.sphere(2.5 * s, 16), Mats.glow((th["accents"] as Array)[i_mod(rng.randi(), 3)], 3.0), Vector3(0.0, 28.0 * s, 0.0)))


static func i_mod(a: int, b: int) -> int:
	return absi(a) % b


static func _lm_orbit_rings(h: Node3D, rng: RandomNumberGenerator, th: Dictionary) -> void:
	var gold: Material = Mats.metal(Color(1.0, 0.8, 0.4), 0.25, 1.0, Color(1.0, 0.7, 0.3), 0.3)
	var y: float = rng.randf_range(15.0, 45.0)
	for i in range(3):
		var sp := Fx.Spin.new()
		sp.axis = Vector3(rng.randf_range(-1.0, 1.0), rng.randf_range(0.2, 1.0), rng.randf_range(-1.0, 1.0)).normalized()
		sp.speed = rng.randf_range(0.05, 0.2)
		h.add_child(sp)
		sp.position = Vector3(0.0, y, 0.0)
		var r: float = 10.0 + float(i) * 5.0
		_vis(Geo.put(sp, Geo.torus(r, r + 1.0, 64, 6), gold))
	_vis(Geo.put(h, Geo.sphere(4.0, 20), Mats.glow((th["accents"] as Array)[1], 2.5), Vector3(0.0, y, 0.0)))


static func _lm_accretion(parent: Node3D, at: Vector3, th: Dictionary) -> void:
	var h := Node3D.new()
	parent.add_child(h)
	h.position = at
	h.rotation_degrees = Vector3(72.0, 0.0, 12.0)
	var m := ShaderMaterial.new()
	m.shader = Mats.shader("res://shaders/disk.gdshader")
	m.set_shader_parameter("inner", Color(1.0, 0.85, 0.6))
	m.set_shader_parameter("outer", Color(0.55, 0.3, 1.0))
	m.set_shader_parameter("energy", 2.2)
	var disk := Geo.put(h, Geo.lathe(PackedVector2Array([Vector2(60.0, 0.0), Vector2(230.0, 0.0)]), 96, "accretion"), m)
	_vis(disk, 3000.0)
	_vis(Geo.put(h, Geo.sphere(55.0, 32), Mats.flat(Color(0.0, 0.0, 0.0))), 3000.0)
	var ring := Geo.put(h, Geo.torus(56.0, 61.0, 96, 8), Mats.neon(Color(1.0, 0.75, 0.45), 2.5, 1.5, 0.6))
	ring.rotation_degrees = Vector3(-72.0, 0.0, 0.0)
	_vis(ring, 3000.0)


# ======================================================================== platform dressing
## Floating-island undersides + small props for every static platform. `plats` = [{p, s, ry, cyl, r}],
## `avoid` = world points where gameplay objects sit (props keep clear of them).
static func dress(root: Node3D, theme_id: String, plats: Array, avoid: PackedVector3Array) -> void:
	var th: Dictionary = theme(theme_id)
	var q: int = Game.quality()
	var rng := RandomNumberGenerator.new()
	rng.seed = 77 + theme_id.hash() % 997
	var rock: ShaderMaterial = Mats.rock()
	var holder := Node3D.new()
	holder.name = "Dressing"
	root.add_child(holder)
	for pd in plats:
		var d: Dictionary = pd
		var top: Vector3 = d["p"]
		var is_cyl: bool = bool(d.get("cyl", false))
		var w: float
		var dep: float
		var th_: float
		if is_cyl:
			w = float(d["r"]) * 2.0
			dep = w
			th_ = float(d.get("th", 0.8))
		else:
			var s: Vector3 = d["s"]
			w = s.x
			dep = s.z
			th_ = s.y
		var ry: float = float(d.get("ry", 0.0))
		var minside: float = minf(w, dep)
		var depth: float = clampf(minside * 0.55 + 1.0, 1.6, 9.0)
		if minside < 2.6 and maxf(w, dep) > 8.0:
			depth = 1.4
		var under := Node3D.new()
		holder.add_child(under)
		under.position = top - Vector3(0.0, th_ - 0.05, 0.0)
		under.rotation_degrees.y = ry
		var isl := Geo.put(under, Geo.island(w * 0.48, dep * 0.48, depth, rng.randi() % 64, is_cyl, 0.3 if theme_id != "launch" else 0.12), rock)
		isl.visibility_range_end = 260.0
		if q >= 1:
			_hang(under, theme_id, th, rng, w, dep, depth)
		if q >= 1 and minside >= 5.5:
			_props(holder, theme_id, th, rng, top, w, dep, ry, is_cyl, avoid)


static func _hang(under: Node3D, id: String, th: Dictionary, rng: RandomNumberGenerator, w: float, dep: float, depth: float) -> void:
	var acc: Array = th["accents"]
	var n: int = clampi(int((w + dep) * 0.25), 1, 5)
	for i in range(n):
		var p := Vector3(rng.randf_range(-0.3, 0.3) * w, -depth * rng.randf_range(0.3, 0.6), rng.randf_range(-0.3, 0.3) * dep)
		var mi: MeshInstance3D = null
		match id:
			"crystal":
				var col: Color = acc[i % 3]
				mi = Geo.put(under, Geo.crystal(0.35, rng.randf_range(1.0, 2.5), 0.6, 6), Mats.plastic(col.lerp(Color(1, 1, 1), 0.2), 0.1, col, 1.6, 0.4), p, Vector3(180.0 + rng.randf_range(-20.0, 20.0), rng.randf() * 60.0, rng.randf_range(-20.0, 20.0)))
			"ice":
				mi = Geo.put(under, Geo.crystal(0.22, rng.randf_range(1.2, 3.0), 0.9, 5), Mats.plastic(Color(0.7, 0.88, 1.0), 0.05, Color(0.3, 0.6, 1.0), 0.3, 0.5), p + Vector3(0.0, 0.3, 0.0), Vector3(180.0, rng.randf() * 60.0, 0.0))
			"launch":
				if i < 2:
					var thr := Node3D.new()
					under.add_child(thr)
					thr.position = p * Vector3(1.0, 0.5, 1.0)
					_vis(Geo.put(thr, Geo.cyl(0.35, 0.5, 0.7, 14), Mats.metal(Color(0.25, 0.27, 0.32), 0.35, 0.8)), 220.0)
					mi = Geo.put(thr, Geo.cyl(0.32, 0.32, 0.05, 14), Mats.glow(acc[0], 3.0), Vector3(0.0, -0.37, 0.0), Vector3.ZERO, Vector3.ONE, false)
			"foundry":
				if i == 0:
					mi = Geo.put(under, Geo.sphere(0.5, 10), Mats.glow(Color(1.0, 0.45, 0.1), 2.5), Vector3(0.0, -depth * 0.95, 0.0))
				else:
					var path := PackedVector3Array([p * Vector3(1.0, 0.0, 1.0), p + Vector3(0.2, -0.5, 0.1), p + Vector3(0.6, -1.5, 0.0)])
					mi = Geo.put(under, Geo.tube(path, 0.12, 6), Mats.metal(Color(0.5, 0.3, 0.15), 0.5, 0.8), Vector3.ZERO)
			_:
				if i == 0:
					mi = Geo.put(under, Geo.crystal(0.5, 1.5, 1.0, 4), Mats.glow(acc[i % 4], 2.2), Vector3(0.0, -depth - 0.5, 0.0), Vector3(180.0, 0.0, 0.0))
		if mi != null:
			_vis(mi, 200.0)


static func _props(holder: Node3D, id: String, th: Dictionary, rng: RandomNumberGenerator, top: Vector3, w: float, dep: float, ry: float, is_cyl: bool, avoid: PackedVector3Array) -> void:
	var area: float = w * dep
	var want: int = clampi(int(area / 30.0), 1, 5)
	var basis := Basis(Vector3.UP, deg_to_rad(ry))
	var tries: int = 0
	var placed: int = 0
	while placed < want and tries < want * 6:
		tries += 1
		var lp: Vector3
		if is_cyl:
			var a: float = rng.randf() * TAU
			lp = Vector3(cos(a), 0.0, sin(a)) * (w * 0.5 - 0.9)
		else:
			var side: int = rng.randi() % 4
			var u: float = rng.randf_range(-0.42, 0.42)
			if side == 0:
				lp = Vector3(w * 0.5 - 0.85, 0.0, u * dep)
			elif side == 1:
				lp = Vector3(-w * 0.5 + 0.85, 0.0, u * dep)
			elif side == 2:
				lp = Vector3(u * w, 0.0, dep * 0.5 - 0.85)
			else:
				lp = Vector3(u * w, 0.0, -dep * 0.5 + 0.85)
		var wp: Vector3 = top + basis * lp
		var ok: bool = true
		for a2 in avoid:
			var av: Vector3 = a2
			if absf(av.y - wp.y) < 4.0 and Vector2(av.x - wp.x, av.z - wp.z).length() < 2.2:
				ok = false
				break
		if not ok:
			continue
		var pr := Prop.new()
		pr.kind = _prop_kind(id, rng)
		pr.th = th
		pr.seed_v = rng.randi()
		holder.add_child(pr)
		pr.position = wp
		pr.rotation.y = rng.randf() * TAU
		placed += 1


static func _prop_kind(id: String, rng: RandomNumberGenerator) -> String:
	var opts: Array
	match id:
		"crystal":
			opts = ["crystals", "crystals", "shroom", "shroom"]
		"foundry":
			opts = ["barrel", "barrel", "pipe", "cargo"]
		"ice":
			opts = ["icecrystal", "snowpine", "snowpine", "mound"]
		"core":
			opts = ["obelisk", "orb", "crystals"]
		_:
			opts = ["cargo", "cargo", "lamp", "antenna"]
	return opts[rng.randi() % opts.size()]


## Decorative, breakable prop. Wobbles when you brush past it, shatters (real physics) when you hit it.
class Prop extends Node3D:
	var kind: String = "cargo"
	var th: Dictionary = {}
	var seed_v: int = 0
	var hit_radius: float = 0.55
	var hit_offset := Vector3(0.0, 0.5, 0.0)
	var _vis: Node3D
	var _wob := Vector2.ZERO
	var _wob_v := Vector2.ZERO
	var _broken: bool = false
	var _mat: Material
	var _shatter: bool = false
	var _world: Node = null
	var _t: float = 0.0
	var _size := Vector3(0.8, 0.8, 0.8)

	func _ready() -> void:
		var rng := RandomNumberGenerator.new()
		rng.seed = seed_v
		_vis = Node3D.new()
		add_child(_vis)
		var acc: Array = th.get("accents", [Color(0.3, 0.9, 1.0)])
		match kind:
			"crystals":
				var col: Color = acc[rng.randi() % 3]
				_mat = Mats.plastic(col.lerp(Color(1, 1, 1), 0.25), 0.1, col, 1.3, 0.4)
				for i in range(rng.randi_range(3, 5)):
					var a: float = rng.randf() * TAU
					Geo.put(_vis, Geo.crystal(rng.randf_range(0.1, 0.18), rng.randf_range(0.35, 0.9), 0.2, 6), _mat, Vector3(cos(a) * 0.18, 0.0, sin(a) * 0.18), Vector3(rng.randf_range(-25.0, 25.0), rng.randf() * 60.0, rng.randf_range(-25.0, 25.0)))
				_shatter = true
			"icecrystal":
				_mat = Mats.plastic(Color(0.75, 0.9, 1.0), 0.05, Color(0.35, 0.65, 1.0), 0.5, 0.6)
				for i in range(rng.randi_range(3, 4)):
					var a2: float = rng.randf() * TAU
					Geo.put(_vis, Geo.crystal(rng.randf_range(0.12, 0.2), rng.randf_range(0.5, 1.1), 0.3, 5), _mat, Vector3(cos(a2) * 0.2, 0.0, sin(a2) * 0.2), Vector3(rng.randf_range(-20.0, 20.0), 0.0, rng.randf_range(-20.0, 20.0)))
				_shatter = true
			"shroom":
				var col2: Color = acc[rng.randi() % 3]
				_mat = Mats.plastic(col2, 0.3, col2, 0.9)
				var stem: Material = Mats.plastic(Color(0.9, 0.85, 0.95), 0.5)
				for i in range(rng.randi_range(1, 3)):
					var hh: float = rng.randf_range(0.4, 0.9)
					var o := Vector3(rng.randf_range(-0.25, 0.25), 0.0, rng.randf_range(-0.25, 0.25))
					Geo.put(_vis, Geo.cyl(0.05, 0.08, hh, 8), stem, o + Vector3(0.0, hh * 0.5, 0.0))
					Geo.put(_vis, Geo.sphere(0.25 + hh * 0.15, 14), _mat, o + Vector3(0.0, hh, 0.0), Vector3.ZERO, Vector3(1.0, 0.5, 1.0))
				_shatter = true
			"snowpine":
				_mat = Mats.std(Color(0.92, 0.96, 1.0), 0.0, 0.7)
				var ice: Material = Mats.plastic(Color(0.4, 0.7, 0.9), 0.2)
				Geo.put(_vis, Geo.cyl(0.06, 0.08, 0.4, 6), ice, Vector3(0.0, 0.2, 0.0))
				for k in range(3):
					Geo.put(_vis, Geo.cyl(0.0, 0.45 - float(k) * 0.11, 0.55, 8), _mat if k % 2 == 0 else ice, Vector3(0.0, 0.45 + float(k) * 0.32, 0.0))
				_size = Vector3(0.7, 1.4, 0.7)
				_shatter = true
			"mound":
				_mat = Mats.std(Color(0.92, 0.96, 1.0), 0.0, 0.8)
				Geo.put(_vis, Geo.sphere(0.6, 14), _mat, Vector3.ZERO, Vector3.ZERO, Vector3(1.0, 0.45, 0.8))
				_size = Vector3(1.0, 0.4, 0.8)
			"barrel":
				_mat = Mats.metal(Color(0.75, 0.25, 0.12) if rng.randf() < 0.6 else Color(0.2, 0.45, 0.6), 0.45, 0.6)
				Geo.put(_vis, Geo.lathe(PackedVector2Array([Vector2(0.0, 0.0), Vector2(0.3, 0.0), Vector2(0.34, 0.1), Vector2(0.36, 0.45), Vector2(0.34, 0.8), Vector2(0.3, 0.9), Vector2(0.0, 0.9)]), 16, "barrel"), _mat)
				Geo.put(_vis, Geo.cyl(0.365, 0.365, 0.05, 16), Mats.metal(Color(0.2, 0.2, 0.22), 0.4, 0.9), Vector3(0.0, 0.3, 0.0))
				Geo.put(_vis, Geo.cyl(0.365, 0.365, 0.05, 16), Mats.metal(Color(0.2, 0.2, 0.22), 0.4, 0.9), Vector3(0.0, 0.62, 0.0))
				_size = Vector3(0.7, 0.9, 0.7)
			"pipe":
				_mat = Mats.metal(Color(0.55, 0.38, 0.2), 0.4, 0.85)
				var path := PackedVector3Array([Vector3(-0.5, 0.0, 0.0), Vector3(-0.5, 0.6, 0.0), Vector3(-0.3, 0.85, 0.0), Vector3(0.3, 0.85, 0.0), Vector3(0.5, 0.6, 0.0), Vector3(0.5, 0.0, 0.0)])
				Geo.put(_vis, Geo.tube(path, 0.1, 8), _mat)
				Geo.put(_vis, Geo.cyl(0.15, 0.15, 0.08, 10), Mats.metal(Color(0.8, 0.15, 0.1), 0.4, 0.6), Vector3(0.0, 0.95, 0.0))
			"lamp":
				_mat = Mats.metal(Color(0.3, 0.33, 0.4), 0.35, 0.8)
				Geo.put(_vis, Geo.cyl(0.05, 0.07, 1.6, 8), _mat, Vector3(0.0, 0.8, 0.0))
				Geo.put(_vis, Geo.rounded_box(Vector3(0.35, 0.12, 0.2), 0.04, 2), _mat, Vector3(0.0, 1.62, 0.0))
				Geo.put(_vis, Geo.box(Vector3(0.28, 0.03, 0.14)), Mats.glow(Color(1.0, 0.9, 0.7), 3.0), Vector3(0.0, 1.55, 0.0))
				_size = Vector3(0.3, 1.7, 0.3)
			"antenna":
				_mat = Mats.metal(Color(0.6, 0.62, 0.68), 0.3, 0.9)
				Geo.put(_vis, Geo.cyl(0.15, 0.2, 0.2, 10), _mat, Vector3(0.0, 0.1, 0.0))
				Geo.put(_vis, Geo.cyl(0.02, 0.03, 1.4, 6), _mat, Vector3(0.0, 0.9, 0.0))
				Geo.put(_vis, Geo.sphere(0.07, 8), Mats.glow(Color(1.0, 0.25, 0.2), 4.0), Vector3(0.0, 1.62, 0.0))
				_size = Vector3(0.3, 1.6, 0.3)
			"obelisk":
				_mat = Mats.metal(Color(0.08, 0.07, 0.14), 0.2, 0.5)
				Geo.put(_vis, Geo.crystal(0.22, 1.1, 0.35, 4), _mat, Vector3(0.0, 0.0, 0.0))
				Geo.put(_vis, Geo.torus(0.26, 0.3, 16, 4), Mats.glow(Color(1.0, 0.8, 0.35), 2.0), Vector3(0.0, 0.55, 0.0))
				_size = Vector3(0.45, 1.4, 0.45)
			"orb":
				_mat = Mats.metal(Color(1.0, 0.8, 0.4), 0.25, 1.0)
				Geo.put(_vis, Geo.cyl(0.18, 0.28, 0.35, 12), _mat, Vector3(0.0, 0.17, 0.0))
				Geo.put(_vis, Geo.sphere(0.22, 14), Mats.glow(acc[1], 2.5), Vector3(0.0, 0.6, 0.0))
				_shatter = true
			_:
				var cols: Array = [Color(1.0, 0.55, 0.15), Color(0.85, 0.87, 0.9), Color(0.25, 0.55, 0.85)]
				_mat = Mats.plastic(cols[rng.randi() % 3], 0.45)
				var stack: int = rng.randi_range(1, 2)
				for k in range(stack):
					Geo.put(_vis, Geo.rounded_box(Vector3(0.9, 0.6, 0.6), 0.06, 2), _mat, Vector3(0.0, 0.3 + float(k) * 0.6, 0.0), Vector3(0.0, float(k) * 25.0, 0.0))
				_size = Vector3(0.9, 0.6 * float(stack), 0.6)
		for c in _vis.get_children():
			var gi: GeometryInstance3D = c as GeometryInstance3D
			if gi != null:
				gi.visibility_range_end = 120.0
		hit_offset = Vector3(0.0, _size.y * 0.5, 0.0)
		add_to_group("hittable")
		_world = get_tree().get_first_node_in_group("world")

	func _physics_process(delta: float) -> void:
		if _broken:
			return
		_t += delta
		if kind == "obelisk":
			_vis.position.y = 0.15 + sin(_t * 1.5 + float(seed_v % 7)) * 0.1
			_vis.rotation.y += delta * 0.5
		if _world == null:
			return
		var pl: Player = Zones.player_of(_world)
		if pl != null:
			var d: Vector3 = global_position - pl.global_position
			if absf(d.y) < 1.5 and Vector2(d.x, d.z).length() < 0.8:
				var hv := Vector2(pl.velocity.x, pl.velocity.z)
				if pl.is_dashing():
					hit(pl, "dash")
					return
				_wob_v += hv * delta * 1.2
		_wob_v += (-_wob * 90.0 - _wob_v * 6.0) * delta
		_wob += _wob_v * delta
		_vis.rotation.x = clampf(_wob.y, -0.6, 0.6)
		_vis.rotation.z = clampf(-_wob.x, -0.6, 0.6)

	func hit(by: Node, _kind: String) -> bool:
		if _broken:
			return false
		_broken = true
		remove_from_group("hittable")
		var from: Vector3 = global_position + Vector3(0.0, 0.5, 1.0)
		if by is Node3D:
			from = (by as Node3D).global_position + Vector3(0.0, 0.4, 0.0)
		var par: Node = get_parent()
		var c: Vector3 = global_position + Vector3(0.0, _size.y * 0.5, 0.0)
		if _shatter:
			Debris.shards(par, c, 0.35, _mat, from, 6.0, 9, 0.16, 3.0)
			Sfx.play("shatter", -4.0, randf_range(1.0, 1.25))
		elif kind == "mound":
			Fx.burst(par, c, Color(0.95, 0.98, 1.0, 0.9), 16, 4.0, 0.45, 0.6, -6.0)
			Sfx.play("snow_hit", -4.0)
		else:
			Debris.parts(par, _vis, from, 6.0, Vector3.ZERO, 3.0)
			Sfx.play("crate", -5.0, randf_range(0.9, 1.1))
		Fx.burst(par, c, Color(1.0, 0.9, 0.7, 0.8), 6, 3.0, 0.3, 0.3)
		if _world != null and randf() < 0.3:
			Debris.spray(par, _world, c, 1, "gem", 1.0, 3.0)
		queue_free()
		return true


# ======================================================================== motes
## Ambient particles around the camera: dust / pollen / embers / snow / star-dust. Parent to the Camera3D.
static func make_motes(theme_id: String) -> CPUParticles3D:
	var th: Dictionary = theme(theme_id)
	var q: int = Game.quality()
	var kind: String = str(th.get("mote", "dust"))
	var amounts: Array = [36, 80, 140]
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
	p.gravity = Vector3.ZERO
	p.scale_amount_min = 0.08
	p.scale_amount_max = 0.22
	p.color = th["mote_color"]
	p.color_ramp = Fx.fade_ramp()
	p.position = Vector3(0.0, 0.0, -8.0)
	if kind == "snow":
		p.amount = int(amounts[q]) * 2
		p.direction = Vector3(0.3, -1.0, 0.0)
		p.spread = 20.0
		p.gravity = Vector3(0.6, -1.2, 0.0)
		p.initial_velocity_min = 1.0
		p.initial_velocity_max = 2.0
		p.scale_amount_min = 0.1
		p.scale_amount_max = 0.25
		p.position = Vector3(0.0, 6.0, -8.0)
	elif kind == "embers":
		p.direction = Vector3.UP
		p.spread = 25.0
		p.gravity = Vector3(0.3, 1.6, 0.0)
		p.initial_velocity_min = 0.5
		p.initial_velocity_max = 1.6
		p.scale_amount_min = 0.06
		p.scale_amount_max = 0.16
	elif kind == "pollen":
		p.gravity = Vector3(0.0, 0.15, 0.0)
		p.scale_amount_max = 0.18
	return p
