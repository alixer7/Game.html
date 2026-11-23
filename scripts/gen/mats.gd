class_name Mats
extends RefCounted
## Shared material factory. One material per look, cached, so the renderer can
## batch draws (important on mobile).

static var _cache := {}
static var _tex := {}


static func tex(name: String) -> Texture2D:
	if not _tex.has(name):
		_tex[name] = load("res://textures/%s.png" % name)
	return _tex[name]


static func _shader(path: String) -> Shader:
	var key := "shader:" + path
	if not _cache.has(key):
		_cache[key] = load(path)
	return _cache[key]


static func _common(m: ShaderMaterial) -> void:
	m.set_shader_parameter("g_grass_tex", tex("grass_albedo"))
	m.set_shader_parameter("g_noise_tex", tex("noise_rgba"))


static func terrain() -> ShaderMaterial:
	if _cache.has("terrain"):
		return _cache["terrain"]
	var m := ShaderMaterial.new()
	m.shader = _shader("res://shaders/terrain.gdshader")
	_common(m)
	m.set_shader_parameter("dirt_tex", tex("dirt_albedo"))
	m.set_shader_parameter("rock_tex", tex("rock_albedo"))
	m.set_shader_parameter("rock_normal_tex", tex("rock_normal"))
	m.set_shader_parameter("sand_tex", tex("sand_albedo"))
	m.set_shader_parameter("moss_tex", tex("moss_albedo"))
	_cache["terrain"] = m
	return m


static func road(kind: String) -> ShaderMaterial:
	var key := "road:" + kind
	if _cache.has(key):
		return _cache[key]
	var m := ShaderMaterial.new()
	m.shader = _shader("res://shaders/road.gdshader")
	_common(m)
	match kind:
		"cobble":
			m.set_shader_parameter("albedo_tex", tex("cobble_albedo"))
			m.set_shader_parameter("normal_tex", tex("cobble_normal"))
			m.set_shader_parameter("uv_scale", 0.2)
			m.set_shader_parameter("edge_to_grass", 0.85)
		"roof":
			m.set_shader_parameter("albedo_tex", tex("cobble_albedo"))
			m.set_shader_parameter("normal_tex", tex("cobble_normal"))
			m.set_shader_parameter("uv_scale", 0.2)
			m.set_shader_parameter("tint", Color(1.04, 1.0, 0.94))
			m.set_shader_parameter("edge_to_grass", 0.0)
		"dirt":
			m.set_shader_parameter("albedo_tex", tex("dirt_albedo"))
			m.set_shader_parameter("normal_tex", tex("dirt_normal"))
			m.set_shader_parameter("uv_scale", 0.16)
			m.set_shader_parameter("edge_to_grass", 1.0)
		"roots":
			m.set_shader_parameter("albedo_tex", tex("dirt_albedo"))
			m.set_shader_parameter("normal_tex", tex("dirt_normal"))
			m.set_shader_parameter("uv_scale", 0.16)
			m.set_shader_parameter("tint", Color(0.85, 0.8, 0.76))
		"ruins":
			m.set_shader_parameter("albedo_tex", tex("cobble_albedo"))
			m.set_shader_parameter("normal_tex", tex("cobble_normal"))
			m.set_shader_parameter("uv_scale", 0.3)
			m.set_shader_parameter("tint", Color(0.8, 0.9, 0.72))
		"planks":
			m.set_shader_parameter("albedo_tex", tex("planks_albedo"))
			m.set_shader_parameter("normal_tex", tex("planks_normal"))
			m.set_shader_parameter("uv_scale", 0.33)
			m.set_shader_parameter("edge_to_grass", 0.0)
			m.set_shader_parameter("roughness", 0.75)
		"riverbed":
			m.set_shader_parameter("albedo_tex", tex("sand_albedo"))
			m.set_shader_parameter("normal_tex", tex("sand_normal"))
			m.set_shader_parameter("uv_scale", 0.14)
			m.set_shader_parameter("tint", Color(0.62, 0.62, 0.55))
			m.set_shader_parameter("edge_to_grass", 0.0)
		"rock":
			m.set_shader_parameter("albedo_tex", tex("rock_albedo"))
			m.set_shader_parameter("normal_tex", tex("rock_normal"))
			m.set_shader_parameter("uv_scale", 0.12)
			m.set_shader_parameter("edge_to_grass", 0.4)
		"bark":
			m.set_shader_parameter("albedo_tex", tex("bark_albedo"))
			m.set_shader_parameter("normal_tex", tex("bark_normal"))
			m.set_shader_parameter("uv_scale", 0.25)
			m.set_shader_parameter("edge_to_grass", 0.0)
	_cache[key] = m
	return m


static func water(kind := "river") -> ShaderMaterial:
	var key := "water:" + kind
	if _cache.has(key):
		return _cache[key]
	var m := ShaderMaterial.new()
	m.shader = _shader("res://shaders/water.gdshader")
	m.set_shader_parameter("normal_tex", tex("water_normal"))
	m.set_shader_parameter("foam_tex", tex("foam"))
	match kind:
		"pond":
			m.set_shader_parameter("flow_speed", 0.25)
			m.set_shader_parameter("deep_color", Color(0.06, 0.28, 0.32))
			m.set_shader_parameter("shallow_color", Color(0.28, 0.6, 0.5))
			m.set_shader_parameter("wave_height", 0.02)
		"falls":
			m.set_shader_parameter("flow_speed", 7.0)
			m.set_shader_parameter("alpha_center", 0.92)
			m.set_shader_parameter("wave_height", 0.0)
		"flume":
			m.set_shader_parameter("flow_speed", 5.0)
			m.set_shader_parameter("wave_height", 0.02)
		_:
			pass
	m.render_priority = 1
	_cache[key] = m
	return m


static func foliage(tint := Color.WHITE, key_suffix := "") -> ShaderMaterial:
	var key := "foliage:" + key_suffix
	if _cache.has(key):
		return _cache[key]
	var m := ShaderMaterial.new()
	m.shader = _shader("res://shaders/foliage.gdshader")
	m.set_shader_parameter("tint", tint)
	m.set_shader_parameter("noise_tex", tex("noise_rgba"))
	_cache[key] = m
	return m


static func grass_blades() -> ShaderMaterial:
	if _cache.has("grass_blades"):
		return _cache["grass_blades"]
	var m := ShaderMaterial.new()
	m.shader = _shader("res://shaders/foliage.gdshader")
	m.set_shader_parameter("noise_tex", tex("noise_rgba"))
	m.set_shader_parameter("wind_strength", 0.09)
	m.set_shader_parameter("wind_speed", 1.8)
	m.set_shader_parameter("leafy_noise", 0.15)
	m.set_shader_parameter("backlight_color", Color(0.25, 0.35, 0.05))
	_cache["grass_blades"] = m
	return m


static func cards(tint := Color.WHITE, key_suffix := "") -> ShaderMaterial:
	var key := "cards:" + key_suffix
	if _cache.has(key):
		return _cache[key]
	var m := ShaderMaterial.new()
	m.shader = _shader("res://shaders/foliage_card.gdshader")
	m.set_shader_parameter("leaf_tex", tex("leaf_atlas"))
	m.set_shader_parameter("tint", tint)
	_cache[key] = m
	return m


static func triplanar(kind: String) -> ShaderMaterial:
	var key := "tri:" + kind
	if _cache.has(key):
		return _cache[key]
	var m := ShaderMaterial.new()
	m.shader = _shader("res://shaders/rock.gdshader")
	_common(m)
	m.set_shader_parameter("moss_tex", tex("moss_albedo"))
	match kind:
		"bark":
			m.set_shader_parameter("albedo_tex", tex("bark_albedo"))
			m.set_shader_parameter("normal_tex", tex("bark_normal"))
			m.set_shader_parameter("tex_scale", 0.45)
			m.set_shader_parameter("moss_amount", 0.5)
			m.set_shader_parameter("moss_height", 0.55)
		"bark_uv":
			m.set_shader_parameter("albedo_tex", tex("bark_albedo"))
			m.set_shader_parameter("normal_tex", tex("bark_normal"))
			m.set_shader_parameter("use_uv", true)
			m.set_shader_parameter("uv_scale", Vector2(2.0, 0.5))
			m.set_shader_parameter("moss_amount", 0.6)
		"rock":
			m.set_shader_parameter("albedo_tex", tex("rock_albedo"))
			m.set_shader_parameter("normal_tex", tex("rock_normal"))
			m.set_shader_parameter("tex_scale", 0.18)
			m.set_shader_parameter("moss_amount", 0.75)
		"stone":
			m.set_shader_parameter("albedo_tex", tex("stone_blocks_albedo"))
			m.set_shader_parameter("normal_tex", tex("stone_blocks_normal"))
			m.set_shader_parameter("tex_scale", 0.16)
			m.set_shader_parameter("moss_amount", 0.55)
		"wood":
			m.set_shader_parameter("albedo_tex", tex("planks_albedo"))
			m.set_shader_parameter("normal_tex", tex("planks_normal"))
			m.set_shader_parameter("tex_scale", 0.3)
			m.set_shader_parameter("moss_amount", 0.25)
			m.set_shader_parameter("roughness", 0.8)
		"cobble":
			m.set_shader_parameter("albedo_tex", tex("cobble_albedo"))
			m.set_shader_parameter("normal_tex", tex("cobble_normal"))
			m.set_shader_parameter("tex_scale", 0.2)
	_cache[key] = m
	return m


static func vcol(roughness := 0.8, metallic := 0.0, key_suffix := "") -> StandardMaterial3D:
	var key := "vcol:%s:%s:%s" % [roughness, metallic, key_suffix]
	if _cache.has(key):
		return _cache[key]
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.roughness = roughness
	m.metallic = metallic
	m.diffuse_mode = BaseMaterial3D.DIFFUSE_BURLEY
	_cache[key] = m
	return m


static func kart_paint(color: Color) -> StandardMaterial3D:
	var key := "kart:" + color.to_html()
	if _cache.has(key):
		return _cache[key]
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.albedo_color = Color.WHITE
	m.roughness = 0.32
	m.metallic = 0.15
	m.rim_enabled = true
	m.rim = 0.35
	m.rim_tint = 0.6
	m.clearcoat_enabled = true
	m.clearcoat = 0.5
	m.clearcoat_roughness = 0.2
	_cache[key] = m
	return m


static func glow(color: Color, energy := 2.0) -> StandardMaterial3D:
	var key := "glow:%s:%s" % [color.to_html(), energy]
	if _cache.has(key):
		return _cache[key]
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = color
	m.emission_enabled = true
	m.emission = color
	m.emission_energy_multiplier = energy
	_cache[key] = m
	return m


static func additive(color: Color, key_suffix := "") -> StandardMaterial3D:
	var key := "add:%s:%s" % [color.to_html(), key_suffix]
	if _cache.has(key):
		return _cache[key]
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.albedo_color = color
	m.vertex_color_use_as_albedo = true
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.no_depth_test = false
	m.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	_cache[key] = m
	return m
