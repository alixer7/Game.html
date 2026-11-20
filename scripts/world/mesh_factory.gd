class_name MeshFactory
extends RefCounted
## مصنع المجسمات والمواد المشتركة. كل مجسم يُبنى مرة واحدة ويُخزّن.

static var _meshes := {}
static var _mats := {}
static var detail_tex: NoiseTexture2D = null
static var normal_tex: NoiseTexture2D = null
static var normal_tex2: NoiseTexture2D = null
static var cloud_tex: NoiseTexture2D = null
static var nature_mats: Array = []

static func init_textures() -> void:
	if detail_tex != null:
		return
	detail_tex = _noise_tex(256, 0.012, 5, 11, false)
	normal_tex = _noise_tex(256, 0.03, 4, 23, true, 6.0)
	normal_tex2 = _noise_tex(256, 0.018, 4, 37, true, 4.0)
	cloud_tex = _noise_tex(512, 0.006, 5, 51, false)

static func _noise_tex(size: int, freq: float, oct: int, s: int, as_normal: bool, bump := 4.0) -> NoiseTexture2D:
	var nz := FastNoiseLite.new()
	nz.seed = s
	nz.frequency = freq
	nz.fractal_octaves = oct
	nz.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	var t := NoiseTexture2D.new()
	t.width = size
	t.height = size
	t.seamless = true
	t.noise = nz
	t.generate_mipmaps = true
	if as_normal:
		t.as_normal_map = true
		t.bump_strength = bump
	return t

static func mat(name: String) -> Material:
	if _mats.has(name):
		return _mats[name]
	init_textures()
	var m: Material
	match name:
		"grass":
			var sm := ShaderMaterial.new()
			sm.shader = load("res://shaders/grass.gdshader")
			m = sm
		"terrain":
			var tm := ShaderMaterial.new()
			tm.shader = load("res://shaders/terrain.gdshader")
			tm.set_shader_parameter("detail_tex", detail_tex)
			tm.set_shader_parameter("normal_tex", normal_tex)
			m = tm
		"water":
			var wm := ShaderMaterial.new()
			wm.shader = load("res://shaders/water.gdshader")
			wm.set_shader_parameter("normal_a", normal_tex)
			wm.set_shader_parameter("normal_b", normal_tex2)
			wm.render_priority = 1
			m = wm
		"lava":
			var lm := ShaderMaterial.new()
			lm.shader = load("res://shaders/lava.gdshader")
			lm.set_shader_parameter("noise_tex", detail_tex)
			m = lm
		"ghost_ok", "ghost_bad":
			var gm := StandardMaterial3D.new()
			gm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			gm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			gm.albedo_color = Color(0.3, 1.0, 0.45, 0.38) if name == "ghost_ok" else Color(1.0, 0.25, 0.2, 0.38)
			gm.no_depth_test = false
			m = gm
		"flame":
			var fm := StandardMaterial3D.new()
			fm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			fm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			fm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
			fm.vertex_color_use_as_albedo = true
			fm.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
			fm.albedo_color = Color(1.0, 0.55, 0.15, 0.9)
			m = fm
		"rain":
			var rm := StandardMaterial3D.new()
			rm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			rm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			rm.albedo_color = Color(0.75, 0.82, 0.92, 0.35)
			rm.billboard_mode = BaseMaterial3D.BILLBOARD_FIXED_Y
			m = rm
		"snowflake":
			var snm := StandardMaterial3D.new()
			snm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			snm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			snm.albedo_color = Color(1, 1, 1, 0.85)
			snm.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
			m = snm
		"smoke":
			var smm := StandardMaterial3D.new()
			smm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			smm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			smm.vertex_color_use_as_albedo = true
			smm.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
			smm.albedo_color = Color(0.5, 0.5, 0.5, 0.25)
			m = smm
		"hit_fx":
			var hm := StandardMaterial3D.new()
			hm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			hm.vertex_color_use_as_albedo = true
			hm.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
			m = hm
		_:
			m = _nature(name)
	_mats[name] = m
	return m

static func _nature(name: String) -> ShaderMaterial:
	var sm := ShaderMaterial.new()
	sm.shader = load("res://shaders/nature.gdshader")
	sm.set_shader_parameter("detail_tex", detail_tex)
	var p := {}
	match name:
		"bark": p = {"detail_strength": 0.4, "detail_scale": 2.2, "roughness_val": 0.95, "wind_strength": 0.12}
		"leaves": p = {"detail_strength": 0.35, "detail_scale": 1.6, "roughness_val": 0.8, "wind_strength": 1.0, "backlight_val": 0.3, "hue_var": 0.28, "specular_val": 0.25}
		"plant": p = {"detail_strength": 0.2, "detail_scale": 3.0, "roughness_val": 0.8, "wind_strength": 0.6, "backlight_val": 0.25, "hue_var": 0.2}
		"rock": p = {"detail_strength": 0.5, "detail_scale": 0.9, "roughness_val": 0.9, "specular_val": 0.25}
		"glossy": p = {"detail_strength": 0.25, "detail_scale": 1.5, "roughness_val": 0.18, "specular_val": 0.7}
		"crystal": p = {"detail_strength": 0.1, "roughness_val": 0.08, "specular_val": 0.9, "metallic_val": 0.25, "emission_val": 0.7}
		"ice": p = {"detail_strength": 0.2, "roughness_val": 0.1, "specular_val": 0.85, "emission_val": 0.1}
		"cloth": p = {"detail_strength": 0.25, "detail_scale": 5.0, "roughness_val": 0.88, "specular_val": 0.15}
		"thatch": p = {"detail_strength": 0.55, "detail_scale": 3.5, "roughness_val": 0.95, "specular_val": 0.1}
		"metal": p = {"detail_strength": 0.15, "detail_scale": 3.0, "roughness_val": 0.35, "specular_val": 0.6, "metallic_val": 0.75}
		"wood": p = {"detail_strength": 0.4, "detail_scale": 3.0, "roughness_val": 0.85, "specular_val": 0.2}
		"skin": p = {"detail_strength": 0.05, "roughness_val": 0.6, "specular_val": 0.3, "backlight_val": 0.15}
		"plain": p = {"detail_strength": 0.15, "roughness_val": 0.85}
		_: p = {"detail_strength": 0.2}
	if name in ["skin", "metal", "wood", "cloth"]:
		p["cold_z0"] = 99999.0
		p["cold_z1"] = 100000.0
	for k in p:
		sm.set_shader_parameter(k, p[k])
	nature_mats.append(sm)
	return sm

static func set_weather_params(wet: float, snow: float, wind: float) -> void:
	for m in nature_mats:
		m.set_shader_parameter("wetness", wet)
		m.set_shader_parameter("snow", snow)
		m.set_shader_parameter("wind_mult", wind)
	var g: ShaderMaterial = mat("grass")
	g.set_shader_parameter("wind_mult", wind)
	g.set_shader_parameter("snow", snow)
	var t: ShaderMaterial = mat("terrain")
	t.set_shader_parameter("wetness", wet)
	t.set_shader_parameter("snow", snow)

static func get_mesh(key: String) -> Mesh:
	if _meshes.has(key):
		return _meshes[key]
	var m: Mesh = _build(key)
	_meshes[key] = m
	return m

# ------------------------------------------------------------------
static func _build(key: String) -> Mesh:
	match key:
		"oak": return _oak(1.0, 1)
		"big_oak": return _oak(1.65, 7)
		"birch": return _birch()
		"pine": return _pine()
		"palm": return _palm()
		"dead_tree": return _dead_tree()
		"bush": return _bush(false)
		"berry_bush": return _bush(true)
		"tall_grass": return _tall_grass()
		"cotton": return _small_plant(Color(0.3, 0.45, 0.2), Color(0.97, 0.97, 0.94), 0.85, 0.075)
		"potato_plant": return _small_plant(Color(0.2, 0.36, 0.14), Color(0.92, 0.9, 0.95), 0.4, 0.04)
		"herb": return _small_plant(Color(0.34, 0.6, 0.3), Color(0.6, 0.35, 0.8), 0.45, 0.035)
		"mushroom": return _mushrooms(Color(0.66, 0.5, 0.33), Color(0.66, 0.5, 0.33), 0)
		"toadstool": return _mushrooms(Color(0.8, 0.1, 0.08), Color(0.97, 0.95, 0.9), 4)
		"reeds": return _reeds()
		"cactus": return _cactus()
		"rock_small": return _rock_cluster(Color(0.5, 0.49, 0.47), "rock", 0.3)
		"flint_stone": return _rock_cluster(Color(0.24, 0.26, 0.32), "glossy", 0.24)
		"sticks": return _sticks()
		"boulder": return _boulder(Color(0.5, 0.49, 0.46), 2, Color(0.3, 0.4, 0.18), 0.12)
		"copper": return _boulder(Color(0.45, 0.44, 0.42), 3, Color(0.82, 0.46, 0.2), 0.13, Color(0.2, 0.6, 0.45))
		"tin": return _boulder(Color(0.47, 0.47, 0.47), 3, Color(0.85, 0.87, 0.9), 0.12)
		"coal": return _boulder(Color(0.42, 0.41, 0.4), 3, Color(0.05, 0.05, 0.06), 0.16)
		"iron": return _boulder(Color(0.44, 0.4, 0.37), 3, Color(0.62, 0.26, 0.15), 0.14)
		"gold": return _boulder(Color(0.46, 0.43, 0.38), 3, Color(1.0, 0.78, 0.2), 0.1)
		"sulfur": return _boulder(Color(0.48, 0.46, 0.4), 3, Color(0.95, 0.86, 0.15), 0.3)
		"crystal": return _crystal(Color(0.62, 0.42, 1.0))
		"gem": return _gem()
		"obsidian": return _obsidian()
		"salt": return _salt()
		"ice_block": return _ice()
		"clay_pit": return _mound(Color(0.6, 0.38, 0.26), "glossy", 0.25)
		"sand_pile": return _mound(Color(0.86, 0.78, 0.55), "rock", 0.4)
		"beehive": return _beehive()
		"grass_clump": return _grass_clump()
		"loot_bag": return _loot_bag()
		"carcass_meat": return _loot_bag()
	if key.begins_with("tool_"):
		return _tool(key.substr(5))
	if key.begins_with("struct_"):
		return _structure(key.substr(7))
	return _rock_cluster(Color(1, 0, 1), "plain", 0.3)

static func _rng(s: int) -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = s
	return r

static func _vary(c: Color, r: RandomNumberGenerator, amt: float) -> Color:
	var k := 1.0 + r.randf_range(-amt, amt)
	return Color(clampf(c.r * k, 0, 1), clampf(c.g * k * (1.0 + r.randf_range(-amt, amt) * 0.5), 0, 1), clampf(c.b * k, 0, 1))

static func _oak(k: float, s: int) -> Mesh:
	var bark := MeshBuilder.new()
	var leaf := MeshBuilder.new()
	var r := _rng(s)
	var bc := Color(0.33, 0.24, 0.16)
	var H := 3.0 * k
	bark.tube(Vector3(0, -0.4, 0), Vector3(0.12 * k, H, 0.06 * k), 0.4 * k, 0.24 * k, bc.darkened(0.2), bc, 10, 5, 0.1, Vector3(0.14, 0, 0.08) * k, 6)
	bark.tube(Vector3(0, -0.4, 0), Vector3(0, 0.6 * k, 0), 0.62 * k, 0.36 * k, bc.darkened(0.25), bc, 10, 2, 0.28, Vector3.ZERO, 6)
	var tops := []
	for i in range(5):
		var ang := TAU * i / 5.0 + r.randf() * 0.5
		var st := Vector3(0.1 * k, H * (0.72 + r.randf() * 0.25), 0.05 * k)
		var en := st + Vector3(cos(ang) * 1.5 * k, (1.1 + r.randf() * 0.7) * k, sin(ang) * 1.5 * k)
		bark.tube(st, en, 0.16 * k, 0.07 * k, bc, bc, 6, 2, 0.0, Vector3(0, 0.25 * k, 0), 6)
		tops.append(en)
	tops.append(Vector3(0.1 * k, H + 1.4 * k, 0))
	var lc := Color(0.2, 0.36, 0.11)
	var lc2 := Color(0.34, 0.45, 0.13)
	for t in tops:
		var rr := (1.25 + r.randf() * 0.45) * k
		leaf.blob(t + Vector3(0, 0.2 * k, 0), Vector3(rr, rr * 0.78, rr), _vary(lc, r, 0.12), 0.3, 1.1, 7, 11, r.randf() * 100.0, 1, lc2)
	leaf.blob(Vector3(0.1 * k, H + 0.9 * k, 0), Vector3(2.1, 1.5, 2.1) * k, lc, 0.25, 0.9, 7, 12, r.randf() * 100.0, 1, lc2)
	return MeshBuilder.commit([bark, leaf], [mat("bark"), mat("leaves")])

static func _birch() -> Mesh:
	var bark := MeshBuilder.new()
	var leaf := MeshBuilder.new()
	var r := _rng(3)
	var H := 5.5
	bark.tube(Vector3(0, -0.3, 0), Vector3(0.15, H, 0.05), 0.22, 0.1, Color(0.88, 0.87, 0.82), Color(0.9, 0.9, 0.86), 8, 6, 0.05, Vector3(0.1, 0, 0), 5, Color(0.12, 0.12, 0.12))
	var lc := Color(0.38, 0.52, 0.18)
	for i in range(6):
		var ang := TAU * i / 6.0 + r.randf()
		var y := 3.2 + r.randf() * 3.0
		var rad := 0.9 + r.randf() * 0.5
		var p := Vector3(cos(ang) * 0.7, y, sin(ang) * 0.7)
		bark.tube(Vector3(0.1, y - 0.8, 0), p, 0.06, 0.03, Color(0.86, 0.86, 0.82), Color(0.8, 0.8, 0.76), 5, 1)
		leaf.blob(p, Vector3(rad, rad * 1.35, rad), _vary(lc, r, 0.1), 0.3, 1.3, 7, 10, r.randf() * 100.0, 1, Color(0.5, 0.58, 0.16))
	leaf.blob(Vector3(0.15, H + 0.8, 0), Vector3(1.1, 1.6, 1.1), lc, 0.25, 1.2, 7, 10, 5.0, 1, Color(0.5, 0.58, 0.16))
	return MeshBuilder.commit([bark, leaf], [mat("bark"), mat("leaves")])

static func _pine() -> Mesh:
	var bark := MeshBuilder.new()
	var leaf := MeshBuilder.new()
	var r := _rng(5)
	bark.tube(Vector3(0, -0.4, 0), Vector3(0, 8.2, 0), 0.34, 0.05, Color(0.32, 0.2, 0.13), Color(0.36, 0.24, 0.15), 8, 6, 0.06, Vector3.ZERO, 6)
	var tiers := 6
	for t in range(tiers):
		var k := float(t) / (tiers - 1)
		var y := 1.7 + t * 1.15
		var rad := lerpf(2.5, 0.6, k) * (0.92 + r.randf() * 0.16)
		var col := _vary(Color(0.1, 0.22, 0.13), r, 0.1)
		leaf.cone(Vector3(0, y, 0), 2.3 - k * 0.6, rad, col, Color(0.16, 0.3, 0.16), 14, 0.16, 7, 0.35)
	leaf.cone(Vector3(0, 8.4, 0), 1.3, 0.45, Color(0.12, 0.25, 0.14), Color(0.18, 0.32, 0.18), 10, 0.1, 5, 0.1)
	return MeshBuilder.commit([bark, leaf], [mat("bark"), mat("leaves")])

static func _palm() -> Mesh:
	var bark := MeshBuilder.new()
	var leaf := MeshBuilder.new()
	var r := _rng(9)
	var pts := []
	for i in range(7):
		var t := i / 6.0
		pts.append(Vector3(sin(t * 1.3) * 1.3 * t, t * 6.4 - 0.3, 0))
	for i in range(6):
		var c := Color(0.45, 0.36, 0.24) if i % 2 == 0 else Color(0.38, 0.3, 0.2)
		bark.tube(pts[i], pts[i + 1], lerpf(0.3, 0.2, i / 6.0) * 1.08, lerpf(0.3, 0.2, (i + 1) / 6.0), c, c.darkened(0.1), 8, 2, 0.04, Vector3.ZERO, 6)
	var top: Vector3 = pts[6]
	for i in range(9):
		var ang := TAU * i / 9.0 + r.randf() * 0.3
		var dir := Vector3(cos(ang), 0, sin(ang))
		leaf.leaf_strip(top, dir, 3.2 + r.randf() * 0.6, 0.85, 1.25, Color(0.24, 0.42, 0.14), Color(0.42, 0.55, 0.2), 7, 0.5, 0.25)
	for i in range(4):
		var a2 := TAU * i / 4.0
		leaf.blob(top + Vector3(cos(a2) * 0.25, -0.25, sin(a2) * 0.25), Vector3(0.16, 0.18, 0.16), Color(0.36, 0.25, 0.13), 0.1, 2.0, 4, 6)
	return MeshBuilder.commit([bark, leaf], [mat("bark"), mat("leaves")])

static func _dead_tree() -> Mesh:
	var bark := MeshBuilder.new()
	var r := _rng(13)
	var bc := Color(0.36, 0.31, 0.26)
	bark.tube(Vector3(0, -0.3, 0), Vector3(0.2, 4.2, 0.1), 0.3, 0.08, bc.darkened(0.2), bc, 8, 5, 0.12, Vector3(0.25, 0, 0), 6)
	for i in range(6):
		var ang := TAU * i / 6.0 + r.randf()
		var y := 1.6 + r.randf() * 2.4
		var st := Vector3(0.1, y, 0.05)
		var en := st + Vector3(cos(ang) * (1.0 + r.randf()), 0.8 + r.randf() * 0.9, sin(ang) * (1.0 + r.randf()))
		bark.tube(st, en, 0.09, 0.02, bc, bc.lightened(0.1), 5, 2, 0.0, Vector3(0, 0.2, 0), 6)
		var en2 := en + Vector3(cos(ang + 0.8) * 0.6, 0.5, sin(ang + 0.8) * 0.6)
		bark.tube(en, en2, 0.03, 0.01, bc, bc, 4, 1)
	return MeshBuilder.commit([bark], [mat("bark")])

static func _bush(berries: bool) -> Mesh:
	var leaf := MeshBuilder.new()
	var r := _rng(17 if berries else 19)
	var lc := Color(0.2, 0.36, 0.13) if not berries else Color(0.17, 0.32, 0.14)
	var centers := []
	for i in range(4):
		var ang := TAU * i / 4.0 + r.randf()
		var c := Vector3(cos(ang) * 0.4, 0.4 + r.randf() * 0.3, sin(ang) * 0.4)
		var rad := 0.5 + r.randf() * 0.3
		centers.append([c, rad])
		leaf.blob(c, Vector3(rad, rad * 0.8, rad), _vary(lc, r, 0.12), 0.32, 1.6, 6, 9, r.randf() * 50.0, 1, Color(0.32, 0.44, 0.15), 0.12, 0.5)
	if berries:
		for i in range(18):
			var e: Array = centers[i % centers.size()]
			var d := Vector3(r.randf_range(-1, 1), r.randf_range(-0.2, 1), r.randf_range(-1, 1)).normalized()
			leaf.blob(e[0] + d * e[1] * 0.92, Vector3(0.06, 0.06, 0.06), Color(0.55, 0.05, 0.2) if i % 3 else Color(0.25, 0.08, 0.35), 0.0, 1.0, 3, 5)
	return MeshBuilder.commit([leaf], [mat("plant")])

static func _tall_grass() -> Mesh:
	var g := MeshBuilder.new()
	var r := _rng(23)
	for i in range(16):
		var a := r.randf() * TAU
		var base := Vector3(cos(a), 0, sin(a)) * r.randf() * 0.35
		var h := r.randf_range(0.6, 1.15)
		var bend := Vector3(cos(a), 0, sin(a)) * r.randf_range(0.1, 0.35)
		g.blade(base, h, 0.07, bend, Color(0.36, 0.42, 0.16), Color(0.72, 0.7, 0.36))
		if i % 3 == 0:
			g.blob(base + bend + Vector3(0, h + 0.05, 0), Vector3(0.03, 0.09, 0.03), Color(0.8, 0.7, 0.4), 0.0, 1.0, 3, 4)
	return MeshBuilder.commit([g], [mat("grass")])

static func _grass_clump() -> Mesh:
	var g := MeshBuilder.new()
	var r := _rng(29)
	for i in range(6):
		var a := r.randf() * TAU
		var base := Vector3(cos(a), 0, sin(a)) * r.randf() * 0.18
		var h := r.randf_range(0.28, 0.5)
		var bend := Vector3(cos(a), 0, sin(a)) * r.randf_range(0.05, 0.16)
		g.blade(base, h, 0.06, bend, Color(0.5, 0.5, 0.5), Color(1.0, 1.0, 0.95))
	return MeshBuilder.commit([g], [mat("grass")])

static func _small_plant(stem: Color, flower: Color, h: float, fr: float) -> Mesh:
	var p := MeshBuilder.new()
	var r := _rng(int(h * 1000))
	for i in range(6):
		var a := TAU * i / 6.0 + r.randf()
		var base := Vector3(cos(a) * 0.12, 0, sin(a) * 0.12)
		var top := base + Vector3(cos(a) * 0.15, h * r.randf_range(0.75, 1.1), sin(a) * 0.15)
		p.tube(base, top, 0.012, 0.008, stem, stem.lightened(0.1), 4, 1)
		p.blob(base.lerp(top, 0.5), Vector3(0.09, 0.04, 0.07), stem.lightened(0.05), 0.2, 2.0, 3, 6)
		p.blob(top, Vector3(fr, fr, fr), flower, 0.25, 3.0, 4, 6)
	p.blob(Vector3(0, 0.08, 0), Vector3(0.22, 0.1, 0.22), stem, 0.3, 2.0, 4, 7, 0.0, 1, stem.lightened(0.2))
	return MeshBuilder.commit([p], [mat("plant")])

static func _mushrooms(cap: Color, dots: Color, shade: int) -> Mesh:
	var m := MeshBuilder.new()
	var r := _rng(31 + shade)
	for i in range(3):
		var off := Vector3(r.randf_range(-0.2, 0.2), 0, r.randf_range(-0.2, 0.2))
		var s := r.randf_range(0.7, 1.2)
		m.tube(off, off + Vector3(0, 0.18 * s, 0), 0.045 * s, 0.035 * s, Color(0.92, 0.88, 0.78), Color(0.95, 0.92, 0.85), 6, 1)
		m.blob(off + Vector3(0, 0.19 * s, 0), Vector3(0.13, 0.08, 0.13) * s, cap, 0.1, 2.0, 5, 9, r.randf() * 10.0, shade, dots, 0.12, 0.1)
	return MeshBuilder.commit([m], [mat("glossy" if shade == 4 else "plain")])

static func _reeds() -> Mesh:
	var p := MeshBuilder.new()
	var r := _rng(37)
	for i in range(16):
		var a := r.randf() * TAU
		var base := Vector3(cos(a), 0, sin(a)) * r.randf() * 0.45
		var h := r.randf_range(1.3, 2.2)
		var top := base + Vector3(cos(a) * 0.15, h, sin(a) * 0.15)
		p.tube(base, top, 0.02, 0.01, Color(0.3, 0.45, 0.2), Color(0.6, 0.62, 0.32), 4, 2)
		if i % 2 == 0:
			p.tube(top - Vector3(0, 0.35, 0), top - Vector3(0, 0.08, 0), 0.04, 0.04, Color(0.4, 0.26, 0.14), Color(0.36, 0.22, 0.12), 6, 1)
	return MeshBuilder.commit([p], [mat("plant")])

static func _cactus() -> Mesh:
	var p := MeshBuilder.new()
	var c := Color(0.22, 0.43, 0.2)
	p.tube(Vector3(0, -0.2, 0), Vector3(0, 3.0, 0), 0.32, 0.27, c.darkened(0.15), c, 12, 5, 0.0, Vector3.ZERO, 0, Color.BLACK, 0.1, 10)
	p.blob(Vector3(0, 3.0, 0), Vector3(0.27, 0.22, 0.27), c, 0.0, 1.0, 4, 12)
	for side in [-1.0, 1.0]:
		var y: float = 1.2 + (0.4 if side > 0 else 0.0)
		var a := Vector3(0.2 * side, y, 0)
		var b := Vector3(0.75 * side, y + 0.15, 0)
		p.tube(a, b, 0.16, 0.15, c, c, 10, 2, 0.0, Vector3.ZERO, 0, Color.BLACK, 0.08, 8)
		p.tube(b - Vector3(0, 0.1, 0), b + Vector3(0, 1.0, 0), 0.15, 0.13, c, c, 10, 2, 0.0, Vector3.ZERO, 0, Color.BLACK, 0.08, 8)
		p.blob(b + Vector3(0, 1.0, 0), Vector3(0.13, 0.11, 0.13), c, 0.0, 1.0, 3, 10)
	p.blob(Vector3(0.1, 3.18, 0.05), Vector3(0.08, 0.07, 0.08), Color(0.85, 0.25, 0.42), 0.0, 1.0, 3, 6)
	return MeshBuilder.commit([p], [mat("plain")])

static func _rock_cluster(col: Color, m: String, size: float) -> Mesh:
	var b := MeshBuilder.new()
	var r := _rng(int(size * 100) + col.r8)
	for i in range(3):
		var off := Vector3(r.randf_range(-0.25, 0.25), 0, r.randf_range(-0.25, 0.25))
		var s := size * r.randf_range(0.5, 1.0)
		b.blob(off + Vector3(0, s * 0.3, 0), Vector3(s, s * 0.65, s * 0.9), _vary(col, r, 0.1), 0.35, 2.2, 5, 7, r.randf() * 30.0, 2, Color(0.35, 0.42, 0.2), 0.12, 0.4)
	return MeshBuilder.commit([b], [mat(m)])

static func _sticks() -> Mesh:
	var b := MeshBuilder.new()
	var r := _rng(41)
	for i in range(6):
		var a := r.randf() * TAU
		var c := Vector3(r.randf_range(-0.3, 0.3), 0.05, r.randf_range(-0.3, 0.3))
		var d := Vector3(cos(a), 0.05, sin(a)) * r.randf_range(0.35, 0.6)
		b.tube(c - d, c + d, 0.03, 0.02, Color(0.42, 0.3, 0.18), Color(0.5, 0.36, 0.22), 5, 1)
	return MeshBuilder.commit([b], [mat("bark")])

static func _boulder(col: Color, shade: int, col2: Color, param: float, col3 := Color(-1, 0, 0)) -> Mesh:
	var b := MeshBuilder.new()
	var r := _rng(int(col2.r8 * 7 + col2.g8 * 3 + shade))
	b.blob(Vector3(0, 0.35, 0), Vector3(1.15, 0.85, 1.0), col, 0.36, 1.25, 9, 14, r.randf() * 100.0, shade, col2, param, 0.55)
	b.blob(Vector3(0.75, 0.2, 0.45), Vector3(0.55, 0.45, 0.5), col.darkened(0.05), 0.3, 1.8, 6, 9, r.randf() * 100.0, shade, col2 if col3.r < 0 else col3, param, 0.4)
	return MeshBuilder.commit([b], [mat("rock")])

static func _crystal(col: Color) -> Mesh:
	var base := MeshBuilder.new()
	var cr := MeshBuilder.new()
	var r := _rng(43)
	base.blob(Vector3(0, 0.15, 0), Vector3(0.8, 0.4, 0.7), Color(0.4, 0.4, 0.42), 0.3, 1.5, 6, 10, 3.0, 2, Color(0.4, 0.4, 0.42), 0.1, 0.5)
	for i in range(8):
		var d := Vector3(r.randf_range(-0.6, 0.6), 1.0, r.randf_range(-0.6, 0.6)).normalized()
		var st := Vector3(r.randf_range(-0.35, 0.35), 0.2, r.randf_range(-0.3, 0.3))
		var L := r.randf_range(0.5, 1.4)
		var rad := r.randf_range(0.08, 0.17)
		var cc := _vary(col, r, 0.15)
		cr.tube(st, st + d * L, rad, rad * 0.95, cc.darkened(0.2), cc, 6, 1)
		cr.tube(st + d * L, st + d * (L + rad * 2.2), rad * 0.95, 0.005, cc, cc.lightened(0.3), 6, 1)
	return MeshBuilder.commit([base, cr], [mat("rock"), mat("crystal")])

static func _gem() -> Mesh:
	var base := MeshBuilder.new()
	var cr := MeshBuilder.new()
	var r := _rng(47)
	base.blob(Vector3(0, 0.35, 0), Vector3(1.1, 0.85, 1.0), Color(0.36, 0.35, 0.36), 0.36, 1.3, 8, 12, 9.0, 2, Color(0.42, 0.42, 0.45), 0.12, 0.55)
	for i in range(6):
		var d := Vector3(r.randf_range(-1, 1), r.randf_range(0.3, 1.0), r.randf_range(-1, 1)).normalized()
		var st := Vector3(0, 0.35, 0) + d * 0.75
		cr.tube(st, st + d * 0.35, 0.09, 0.08, Color(0.75, 0.05, 0.15), Color(0.95, 0.15, 0.3), 6, 1)
		cr.tube(st + d * 0.35, st + d * 0.5, 0.08, 0.005, Color(0.95, 0.15, 0.3), Color(1.0, 0.4, 0.5), 6, 1)
	return MeshBuilder.commit([base, cr], [mat("rock"), mat("crystal")])

static func _obsidian() -> Mesh:
	var b := MeshBuilder.new()
	b.blob(Vector3(0, 0.4, 0), Vector3(0.95, 0.9, 0.85), Color(0.09, 0.07, 0.12), 0.5, 2.4, 7, 9, 21.0, 0, Color.BLACK, 0.1, 0.5)
	b.blob(Vector3(0.6, 0.25, -0.4), Vector3(0.45, 0.5, 0.4), Color(0.12, 0.08, 0.15), 0.55, 2.8, 5, 7, 4.0, 0, Color.BLACK, 0.1, 0.5)
	return MeshBuilder.commit([b], [mat("glossy")])

static func _salt() -> Mesh:
	var b := MeshBuilder.new()
	var r := _rng(53)
	for i in range(7):
		var off := Vector3(r.randf_range(-0.6, 0.6), 0, r.randf_range(-0.5, 0.5))
		var s := r.randf_range(0.2, 0.45)
		b.blob(off + Vector3(0, s * 0.5, 0), Vector3(s, s * 1.2, s), _vary(Color(0.93, 0.93, 0.92), r, 0.05), 0.15, 1.0, 3, 4, r.randf() * 10.0)
	return MeshBuilder.commit([b], [mat("ice")])

static func _ice() -> Mesh:
	var b := MeshBuilder.new()
	b.blob(Vector3(0, 0.45, 0), Vector3(1.0, 0.95, 0.9), Color(0.72, 0.86, 0.96), 0.18, 1.0, 4, 6, 3.0)
	b.blob(Vector3(0.7, 0.3, 0.3), Vector3(0.5, 0.6, 0.5), Color(0.78, 0.9, 0.98), 0.2, 1.0, 3, 5, 9.0)
	return MeshBuilder.commit([b], [mat("ice")])

static func _mound(col: Color, m: String, hgt: float) -> Mesh:
	var b := MeshBuilder.new()
	b.blob(Vector3(0, 0.0, 0), Vector3(1.2, hgt, 1.0), col, 0.25, 1.5, 6, 12, 5.0, 2, col.darkened(0.1), 0.12, 0.0)
	return MeshBuilder.commit([b], [mat(m)])

static func _beehive() -> Mesh:
	var b := MeshBuilder.new()
	b.tube(Vector3(0, -0.2, 0), Vector3(0, 0.9, 0), 0.38, 0.33, Color(0.32, 0.24, 0.16), Color(0.36, 0.27, 0.18), 9, 2, 0.08, Vector3.ZERO, 6)
	b.disc(Vector3(0, 0.9, 0), Vector3.UP, 0.33, Color(0.55, 0.42, 0.28), 9)
	b.blob(Vector3(0, 1.32, 0), Vector3(0.36, 0.46, 0.36), Color(0.78, 0.6, 0.26), 0.08, 1.5, 9, 10, 0.0, 7, Color(0.55, 0.4, 0.18), 40.0)
	b.blob(Vector3(0.0, 1.2, 0.33), Vector3(0.07, 0.06, 0.04), Color(0.08, 0.06, 0.04), 0.0, 1.0, 3, 6)
	return MeshBuilder.commit([b], [mat("plain")])

static func _loot_bag() -> Mesh:
	var b := MeshBuilder.new()
	b.blob(Vector3(0, 0.25, 0), Vector3(0.32, 0.27, 0.3), Color(0.5, 0.38, 0.24), 0.18, 2.0, 6, 9, 3.0, 0, Color.BLACK, 0.1, 0.9)
	b.tube(Vector3(0, 0.48, 0), Vector3(0, 0.62, 0), 0.08, 0.12, Color(0.45, 0.33, 0.2), Color(0.5, 0.38, 0.24), 7, 1)
	b.tube(Vector3(0, 0.5, 0), Vector3(0, 0.54, 0), 0.085, 0.085, Color(0.75, 0.6, 0.3), Color(0.75, 0.6, 0.3), 7, 1)
	return MeshBuilder.commit([b], [mat("cloth")])

# ------------------------------------------------------------------
# أدوات تُمسك في اليد (المقبض عند الأصل، ممتدة على +Y)
static func _tool(kind_and_col: String) -> Mesh:
	var parts := kind_and_col.split(":")
	var kind := parts[0]
	var col := Color(0.55, 0.55, 0.55)
	if parts.size() > 1:
		col = Color.html(parts[1])
	var wood := MeshBuilder.new()
	var head := MeshBuilder.new()
	var hc := Color(0.45, 0.32, 0.2)
	match kind:
		"axe":
			wood.tube(Vector3(0, -0.1, 0), Vector3(0, 0.62, 0), 0.022, 0.02, hc, hc, 6, 1)
			head.box(Vector3(0.07, 0.55, 0), Vector3(0.16, 0.12, 0.03), col)
			head.box(Vector3(0.155, 0.55, 0), Vector3(0.02, 0.16, 0.012), col.lightened(0.2))
		"pickaxe":
			wood.tube(Vector3(0, -0.1, 0), Vector3(0, 0.62, 0), 0.022, 0.02, hc, hc, 6, 1)
			head.tube(Vector3(-0.24, 0.53, 0), Vector3(0, 0.62, 0), 0.008, 0.03, col, col, 5, 1)
			head.tube(Vector3(0, 0.62, 0), Vector3(0.24, 0.53, 0), 0.03, 0.008, col, col, 5, 1)
		"sword":
			wood.tube(Vector3(0, -0.08, 0), Vector3(0, 0.12, 0), 0.022, 0.022, Color(0.3, 0.2, 0.12), Color(0.3, 0.2, 0.12), 6, 1)
			head.box(Vector3(0, 0.14, 0), Vector3(0.16, 0.025, 0.04), col.darkened(0.2))
			head.box(Vector3(0, 0.5, 0), Vector3(0.05, 0.7, 0.012), col.lightened(0.15))
			head.tube(Vector3(0, 0.85, 0), Vector3(0, 0.93, 0), 0.025, 0.002, col.lightened(0.15), col.lightened(0.2), 4, 1)
		"spear":
			wood.tube(Vector3(0, -0.6, 0), Vector3(0, 1.0, 0), 0.02, 0.018, hc, hc, 6, 1)
			head.tube(Vector3(0, 1.0, 0), Vector3(0, 1.22, 0), 0.04, 0.002, col, col.lightened(0.2), 5, 1)
		"knife":
			wood.tube(Vector3(0, -0.06, 0), Vector3(0, 0.08, 0), 0.02, 0.02, hc, hc, 6, 1)
			head.box(Vector3(0, 0.2, 0), Vector3(0.035, 0.24, 0.01), col)
		"hammer":
			wood.tube(Vector3(0, -0.1, 0), Vector3(0, 0.45, 0), 0.02, 0.02, hc, hc, 6, 1)
			head.box(Vector3(0, 0.46, 0), Vector3(0.08, 0.08, 0.2), col)
		"club":
			wood.tube(Vector3(0, -0.1, 0), Vector3(0, 0.62, 0), 0.025, 0.065, hc, hc.lightened(0.1), 7, 2, 0.15)
		"bow":
			for i in range(6):
				var a0 := -0.9 + i * 0.3
				var a1 := a0 + 0.3
				wood.tube(Vector3(cos(a0) * 0.45 - 0.45, sin(a0) * 0.6, 0), Vector3(cos(a1) * 0.45 - 0.45, sin(a1) * 0.6, 0), 0.016, 0.016, hc, hc, 5, 1)
			head.tube(Vector3(cos(-0.9) * 0.45 - 0.45, sin(-0.9) * 0.6, 0), Vector3(cos(0.9) * 0.45 - 0.45, sin(0.9) * 0.6, 0), 0.003, 0.003, Color(0.9, 0.9, 0.85), Color(0.9, 0.9, 0.85), 3, 1)
		"torch":
			wood.tube(Vector3(0, -0.1, 0), Vector3(0, 0.5, 0), 0.022, 0.028, hc, hc, 6, 1)
			head.blob(Vector3(0, 0.52, 0), Vector3(0.05, 0.08, 0.05), Color(0.2, 0.14, 0.1), 0.2, 3.0, 4, 6)
		"rod":
			wood.tube(Vector3(0, -0.2, 0), Vector3(0.1, 1.5, 0), 0.02, 0.008, hc, hc, 5, 3, 0.0, Vector3(0.1, 0, 0))
		_:
			head.blob(Vector3(0, 0.12, 0), Vector3(0.12, 0.12, 0.12), col, 0.2, 2.0, 5, 7)
	var hm := "rock"
	if parts.size() > 2:
		hm = parts[2]
	return MeshBuilder.commit([wood, head], [mat("wood"), mat(hm)])

## مفتاح مجسم العنصر المحمول في اليد
static func held_key(item_id: String) -> String:
	var it := ItemDB.get_item(item_id)
	if it.is_empty():
		return ""
	var kind: String = it.get("tool", {}).get("kind", "")
	if kind == "":
		return "tool_item:%s" % it["color"].to_html(false)
	var m := "rock"
	if item_id.begins_with("bronze") or item_id.begins_with("iron") or item_id.begins_with("steel"):
		m = "metal"
	elif item_id.begins_with("obsidian"):
		m = "glossy"
	return "tool_%s:%s:%s" % [kind, it["color"].to_html(false), m]

# ------------------------------------------------------------------
# مباني المستوطنات
static func _structure(kind: String) -> Mesh:
	var a := MeshBuilder.new()
	var b := MeshBuilder.new()
	var r := _rng(kind.hash())
	match kind:
		"hut":
			a.tube(Vector3(0, -0.4, 0), Vector3(0, 2.2, 0), 2.2, 2.15, Color(0.5, 0.38, 0.26), Color(0.55, 0.42, 0.28), 16, 3, 0.04, Vector3.ZERO, 6)
			b.tube(Vector3(0, 2.05, 0), Vector3(0, 4.4, 0), 2.9, 0.08, Color(0.72, 0.6, 0.32), Color(0.62, 0.5, 0.26), 16, 4, 0.08, Vector3.ZERO, 7, Color(0.5, 0.4, 0.2), 0.04, 16)
			b.disc(Vector3(0, 2.05, 0), Vector3.UP, 2.9, Color(0.4, 0.32, 0.18), 16, false)
			a.box(Vector3(0, 0.95, 2.18), Vector3(1.0, 1.9, 0.1), Color(0.22, 0.16, 0.1))
		"tent":
			var cc := Color(0.75, 0.66, 0.5)
			for s in [-1.0, 1.0]:
				var nrm := Vector3(s * 0.8, 0.6, 0).normalized()
				a.quad(Vector3(s * 1.0, 1.0, 0), nrm, Vector3(-s * 0.6, 0.8, 0).normalized(), 3.6, 2.5, cc)
				a.quad(Vector3(s * 1.0, 1.0, 0) - nrm * 0.02, -nrm, Vector3(-s * 0.6, 0.8, 0).normalized(), 3.6, 2.5, cc.darkened(0.3))
			a.box(Vector3(0, 1.0, -1.75), Vector3(2.6, 0.05, 0.05), Color(0.4, 0.3, 0.2))
			b.tube(Vector3(0, 0, 1.8), Vector3(0, 2.05, 1.8), 0.05, 0.05, Color(0.4, 0.3, 0.2), Color(0.4, 0.3, 0.2), 5, 1)
			b.tube(Vector3(0, 0, -1.8), Vector3(0, 2.05, -1.8), 0.05, 0.05, Color(0.4, 0.3, 0.2), Color(0.4, 0.3, 0.2), 5, 1)
			b.tube(Vector3(0, 2.0, -1.85), Vector3(0, 2.0, 1.85), 0.05, 0.05, Color(0.4, 0.3, 0.2), Color(0.4, 0.3, 0.2), 5, 1)
		"tent_dark":
			var dc := Color(0.35, 0.12, 0.1)
			for s in [-1.0, 1.0]:
				var nrm2 := Vector3(s * 0.8, 0.6, 0).normalized()
				a.quad(Vector3(s * 1.0, 1.0, 0), nrm2, Vector3(-s * 0.6, 0.8, 0).normalized(), 3.6, 2.5, dc)
				a.quad(Vector3(s * 1.0, 1.0, 0) - nrm2 * 0.02, -nrm2, Vector3(-s * 0.6, 0.8, 0).normalized(), 3.6, 2.5, dc.darkened(0.3))
			b.tube(Vector3(0, 2.0, -1.85), Vector3(0, 2.0, 1.85), 0.05, 0.05, Color(0.2, 0.15, 0.1), Color(0.2, 0.15, 0.1), 5, 1)
			b.tube(Vector3(0, 0, 1.8), Vector3(0, 2.6, 1.8), 0.05, 0.03, Color(0.2, 0.15, 0.1), Color(0.2, 0.15, 0.1), 5, 1)
			b.box(Vector3(0, 2.75, 1.8), Vector3(0.05, 0.3, 0.05), Color(0.9, 0.9, 0.85))
		"mudhouse":
			var mc := Color(0.78, 0.62, 0.42)
			a.box(Vector3(0, 1.2, 0), Vector3(4.0, 2.8, 3.6), mc, Basis(), 1.05)
			a.box(Vector3(0, 2.75, 0), Vector3(4.3, 0.3, 3.9), mc.darkened(0.08))
			a.box(Vector3(0, 0.9, 1.82), Vector3(1.0, 1.8, 0.06), Color(0.35, 0.22, 0.12))
			a.box(Vector3(1.3, 1.6, 1.82), Vector3(0.6, 0.5, 0.06), Color(0.1, 0.08, 0.06))
			for i in range(4):
				b.tube(Vector3(-1.8 + i * 1.2, 2.6, 1.9), Vector3(-1.8 + i * 1.2, 2.6, 2.3), 0.05, 0.05, Color(0.4, 0.3, 0.2), Color(0.4, 0.3, 0.2), 5, 1)
		"cabin":
			var wc := Color(0.45, 0.3, 0.18)
			for i in range(8):
				var y := 0.2 + i * 0.32
				a.tube(Vector3(-2.3, y, 1.8), Vector3(2.3, y, 1.8), 0.17, 0.17, wc, wc.darkened(0.1), 7, 1, 0.05)
				a.tube(Vector3(-2.3, y, -1.8), Vector3(2.3, y, -1.8), 0.17, 0.17, wc, wc.darkened(0.1), 7, 1, 0.05)
				a.tube(Vector3(-2.2, y + 0.16, -1.9), Vector3(-2.2, y + 0.16, 1.9), 0.17, 0.17, wc, wc.darkened(0.1), 7, 1, 0.05)
				a.tube(Vector3(2.2, y + 0.16, -1.9), Vector3(2.2, y + 0.16, 1.9), 0.17, 0.17, wc, wc.darkened(0.1), 7, 1, 0.05)
			var rc := Color(0.3, 0.22, 0.15)
			for s in [-1.0, 1.0]:
				var nn := Vector3(0, 0.7, s * 0.7).normalized()
				b.quad(Vector3(0, 3.3, s * 1.1), nn, Vector3(0, 0.7, -s * 0.7).normalized(), 5.4, 3.2, rc)
				b.quad(Vector3(0, 3.3, s * 1.1) - nn * 0.03, -nn, Vector3(0, 0.7, -s * 0.7).normalized(), 5.4, 3.2, rc.darkened(0.3))
			a.box(Vector3(0, 1.0, 1.98), Vector3(1.0, 2.0, 0.08), Color(0.25, 0.16, 0.1))
		"stall":
			a.box(Vector3(0, 0.5, 0), Vector3(2.6, 1.0, 1.0), Color(0.5, 0.35, 0.2))
			for x in [-1.25, 1.25]:
				a.tube(Vector3(x, 0, 0.45), Vector3(x, 2.4, 0.45), 0.05, 0.05, Color(0.4, 0.28, 0.16), Color(0.4, 0.28, 0.16), 5, 1)
				a.tube(Vector3(x, 0, -0.45), Vector3(x, 2.2, -0.45), 0.05, 0.05, Color(0.4, 0.28, 0.16), Color(0.4, 0.28, 0.16), 5, 1)
			var stripes := [Color(0.8, 0.2, 0.15), Color(0.95, 0.9, 0.8)]
			for i in range(6):
				var x2 := -1.3 + i * 0.52 + 0.26
				b.quad(Vector3(x2, 2.32, 0), Vector3(0, 0.98, 0.2).normalized(), Vector3(0, -0.2, 0.98).normalized(), 0.52, 1.3, stripes[i % 2])
				b.quad(Vector3(x2, 2.31, 0), Vector3(0, -0.98, -0.2).normalized(), Vector3(0, -0.2, 0.98).normalized(), 0.52, 1.3, stripes[i % 2].darkened(0.3))
			for i in range(5):
				b.blob(Vector3(-1.0 + i * 0.5, 1.08, 0), Vector3(0.15, 0.1, 0.15), Color(r.randf(), r.randf_range(0.3, 0.8), r.randf_range(0.1, 0.4)), 0.2, 2.0, 4, 6)
		"totem":
			a.tube(Vector3(0, -0.3, 0), Vector3(0, 3.2, 0), 0.25, 0.2, Color(0.4, 0.28, 0.17), Color(0.45, 0.3, 0.18), 8, 4, 0.1, Vector3.ZERO, 6)
			b.blob(Vector3(0, 3.35, 0), Vector3(0.28, 0.22, 0.25), Color(0.93, 0.9, 0.8), 0.15, 2.0, 5, 8)
			b.blob(Vector3(0.12, 3.38, 0.2), Vector3(0.05, 0.05, 0.03), Color(0.05, 0.05, 0.05), 0.0, 1.0, 3, 5)
			b.blob(Vector3(-0.12, 3.38, 0.2), Vector3(0.05, 0.05, 0.03), Color(0.05, 0.05, 0.05), 0.0, 1.0, 3, 5)
		"log_seat":
			a.tube(Vector3(-0.9, 0.22, 0), Vector3(0.9, 0.22, 0), 0.22, 0.22, Color(0.45, 0.32, 0.2), Color(0.42, 0.3, 0.18), 8, 1, 0.05, Vector3.ZERO, 6)
			a.disc(Vector3(0.9, 0.22, 0), Vector3(1, 0, 0), 0.22, Color(0.7, 0.55, 0.35), 8)
			a.disc(Vector3(-0.9, 0.22, 0), Vector3(-1, 0, 0), 0.22, Color(0.7, 0.55, 0.35), 8)
	var m1 := mat("wood")
	var m2 := mat("thatch")
	if kind in ["tent", "tent_dark", "stall"]:
		m1 = mat("cloth")
		m2 = mat("wood") if kind != "stall" else mat("cloth")
	if kind == "mudhouse":
		m1 = mat("rock")
		m2 = mat("wood")
	if kind == "totem":
		m2 = mat("rock")
	return MeshBuilder.commit([a, b], [m1, m2])
