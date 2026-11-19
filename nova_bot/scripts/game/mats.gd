class_name Mats
extends RefCounted
## Material factory with caching. `theme` is set by the level loader before anything is built.

static var _cache: Dictionary = {}
static var _shaders: Dictionary = {}
static var theme: Dictionary = {}


static func clear() -> void:
	_cache.clear()


static func shader(path: String) -> Shader:
	if not _shaders.has(path):
		_shaders[path] = load(path)
	return _shaders[path]


static func accent(i: int) -> Color:
	var a: Array = theme.get("accents", [Color(0.2, 0.9, 1.0)])
	return a[absi(i) % a.size()]


## Tech platform material. half = half extents (for cylinders: x = radius, y = half thickness).
static func platform(half: Vector3, c: int = 0, is_cyl: bool = false) -> ShaderMaterial:
	var key: String = "p%d_%d_%.2f_%.2f_%.2f" % [c, 1 if is_cyl else 0, half.x, half.y, half.z]
	if _cache.has(key):
		return _cache[key]
	var m := ShaderMaterial.new()
	m.shader = shader("res://shaders/platform.gdshader")
	m.set_shader_parameter("half_size", half)
	m.set_shader_parameter("base_color", theme.get("base", Color(0.05, 0.07, 0.13)))
	m.set_shader_parameter("top_color", theme.get("top", Color(0.09, 0.12, 0.21)))
	m.set_shader_parameter("edge_color", accent(c))
	m.set_shader_parameter("cyl", 1.0 if is_cyl else 0.0)
	_cache[key] = m
	return m


## Holographic platform material (unique per platform because `fade` / `warn` are animated).
static func ghost(half: Vector3, c: int = 0) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = shader("res://shaders/ghost.gdshader")
	m.set_shader_parameter("half_size", half)
	m.set_shader_parameter("edge_color", accent(c))
	return m


## Additive glow material (fresnel rim).
static func neon(color: Color, energy: float = 2.0, fres: float = 2.0, base_alpha: float = 0.15, alpha: float = 1.0) -> ShaderMaterial:
	var key: String = "n%s_%.2f_%.2f_%.2f_%.2f" % [color.to_html(false), energy, fres, base_alpha, alpha]
	if _cache.has(key):
		return _cache[key]
	var m := ShaderMaterial.new()
	m.shader = shader("res://shaders/neon.gdshader")
	m.set_shader_parameter("color", color)
	m.set_shader_parameter("energy", energy)
	m.set_shader_parameter("fresnel_pow", fres)
	m.set_shader_parameter("base_alpha", base_alpha)
	m.set_shader_parameter("alpha_mul", alpha)
	_cache[key] = m
	return m


## Fresh (non-cached) neon material, for things that animate their own parameters.
static func neon_unique(color: Color, energy: float = 2.0, fres: float = 2.0, base_alpha: float = 0.15) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = shader("res://shaders/neon.gdshader")
	m.set_shader_parameter("color", color)
	m.set_shader_parameter("energy", energy)
	m.set_shader_parameter("fresnel_pow", fres)
	m.set_shader_parameter("base_alpha", base_alpha)
	return m


static func beam(color: Color, height: float, energy: float = 1.6, bidir: bool = false, intensity: float = 1.0) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = shader("res://shaders/beam.gdshader")
	m.set_shader_parameter("color", color)
	m.set_shader_parameter("height", height)
	m.set_shader_parameter("energy", energy)
	m.set_shader_parameter("bidir", 1.0 if bidir else 0.0)
	m.set_shader_parameter("intensity", intensity)
	return m


static func chevron(color: Color, speed: float = 2.0, density: float = 3.0) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = shader("res://shaders/chevron.gdshader")
	m.set_shader_parameter("color", color)
	m.set_shader_parameter("speed", speed)
	m.set_shader_parameter("density", density)
	return m


## Standard PBR material with optional emission.
static func std(color: Color, metallic: float = 0.0, rough: float = 0.5, emis: Color = Color(0, 0, 0, 0), emis_energy: float = 1.0) -> StandardMaterial3D:
	var key: String = "s%s_%.2f_%.2f_%s_%.2f" % [color.to_html(true), metallic, rough, emis.to_html(true), emis_energy]
	if _cache.has(key):
		return _cache[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.metallic = metallic
	m.roughness = rough
	if emis.a > 0.0:
		m.emission_enabled = true
		m.emission = emis
		m.emission_energy_multiplier = emis_energy
	_cache[key] = m
	return m


## Unshaded flat colour (HDR allowed through the colour value).
static func flat(color: Color) -> StandardMaterial3D:
	var key: String = "f%s" % color.to_html(true)
	if _cache.has(key):
		return _cache[key]
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = color
	_cache[key] = m
	return m
