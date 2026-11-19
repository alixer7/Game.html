class_name Mats
extends RefCounted
## Shared material cache.

static var _cache := {}


static func surf_tex() -> Array:
	if not _cache.has("surf_tex"):
		_cache["surf_tex"] = [load("res://assets/textures/surface_albedo.png"), load("res://assets/textures/surface_normal.png")]
	return _cache["surf_tex"]


static func triplanar(layer: int, scale := 0.25, tint := Color.WHITE, key := "") -> ShaderMaterial:
	var k := "tri_%d_%.3f_%s_%s" % [layer, scale, tint.to_html(), key]
	if _cache.has(k):
		return _cache[k]
	var m := ShaderMaterial.new()
	m.shader = load("res://shaders/triplanar.gdshader")
	var t := surf_tex()
	m.set_shader_parameter("surf_albedo", t[0])
	m.set_shader_parameter("surf_normal", t[1])
	m.set_shader_parameter("layer", float(layer))
	m.set_shader_parameter("scale", scale)
	m.set_shader_parameter("tint", Color(tint.r, tint.g, tint.b))
	_cache[k] = m
	return m


static func concrete() -> ShaderMaterial:
	return triplanar(3, 0.22)


static func masonry() -> ShaderMaterial:
	return triplanar(5, 0.3)


static func road(style: int, layer: int, width: float, wear := -1.0) -> ShaderMaterial:
	var k := "road_%d_%d_%.1f_%.1f" % [style, layer, width, wear]
	if _cache.has(k):
		return _cache[k]
	var m := ShaderMaterial.new()
	m.shader = load("res://shaders/road.gdshader")
	var t := surf_tex()
	m.set_shader_parameter("surf_albedo", t[0])
	m.set_shader_parameter("surf_normal", t[1])
	m.set_shader_parameter("layer", float(layer))
	m.set_shader_parameter("style", style)
	m.set_shader_parameter("width", width)
	m.set_shader_parameter("tile", 0.2 if layer == 0 else 0.28)
	m.set_shader_parameter("tint", Color(1.25, 1.25, 1.25) if layer == 0 else Color(1, 1, 1))
	m.set_shader_parameter("wear", wear if wear >= 0.0 else (1.0 if layer == 0 else 0.0))
	_cache[k] = m
	return m


static func std(key: String, color: Color, metallic := 0.0, roughness := 0.6, emission := Color.BLACK, emission_energy := 0.0) -> StandardMaterial3D:
	if _cache.has(key):
		return _cache[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.metallic = metallic
	m.roughness = roughness
	if emission_energy > 0.0:
		m.emission_enabled = true
		m.emission = emission
		m.emission_energy_multiplier = emission_energy
	_cache[key] = m
	return m


static func metal() -> StandardMaterial3D:
	return std("metal", Color(0.62, 0.64, 0.66), 0.85, 0.38)


static func dark_metal() -> StandardMaterial3D:
	return std("dark_metal", Color(0.18, 0.19, 0.2), 0.7, 0.45)


static func lamp_glow() -> StandardMaterial3D:
	return std("lamp_glow", Color(1, 0.95, 0.85), 0.0, 0.3, Color(1.0, 0.85, 0.6), 2.5)


static func set_night(on: bool) -> void:
	var m := lamp_glow()
	m.emission_energy_multiplier = 6.0 if on else 1.2
