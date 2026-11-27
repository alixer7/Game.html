class_name TrackMats
extends RefCounted

## v8 shared material cache: road surfaces, shoulders, walls, decks, terrain, props.
## Uses the PBR texture sets in res://assets/textures/<name>_{albedo,normal,rough}.png (world-scaled UVs).

static var _cache: Dictionary = {}
static var _tex_cache: Dictionary = {}

# surface id -> [texture set, metres per texture repeat, tint, roughness, metallic]
const SURF_TEX := {
	"stone": ["road_tiki", 7.0, Color(1, 1, 1), 0.88, 0.0],
	"cobble": ["road_cobble", 6.0, Color(1, 1, 1), 0.9, 0.0],
	"dirt": ["road_dirt", 9.0, Color(1, 1, 1), 0.95, 0.0],
	"wood": ["wood_bridge", 6.0, Color(1, 1, 1), 0.84, 0.0],
	"wet_stone": ["road_wetstone", 7.0, Color(1, 1, 1), 0.35, 0.0],
	"metal": ["road_metal", 8.0, Color(1, 1, 1), 0.45, 0.55],
	"grating": ["road_grating", 4.0, Color(1, 1, 1), 0.5, 0.6],
	"asphalt": ["road_asphalt", 10.0, Color(1, 1, 1), 0.7, 0.0],
	"neon": ["road_space", 14.0, Color(1, 1, 1), 0.4, 0.45],
	"basalt": ["road_volcano", 7.0, Color(1, 1, 1), 0.86, 0.0],
	"packed_snow": ["road_snowpack", 8.0, Color(1, 1, 1), 0.75, 0.0],
	"ice": ["ice_surface", 9.0, Color(1, 1, 1), 0.12, 0.05],
	"glass": ["road_space", 14.0, Color(0.6, 0.9, 1.0), 0.1, 0.2],
	"grass": ["terrain_grass", 8.0, Color(1, 1, 1), 0.95, 0.0],
	"sand": ["terrain_sand", 8.0, Color(1, 1, 1), 0.95, 0.0],
	"mud": ["terrain_mud", 7.0, Color(1, 1, 1), 0.6, 0.0],
	"gravel": ["terrain_gravel", 6.0, Color(1, 1, 1), 0.95, 0.0],
	"snow": ["offroad_snow", 10.0, Color(1, 1, 1), 0.85, 0.0],
	"shallow_water": ["terrain_sand", 8.0, Color(0.7, 0.85, 0.9), 0.3, 0.0],
	"ash": ["offroad_volcano", 9.0, Color(0.7, 0.62, 0.6), 0.95, 0.0],
	"rock": ["cliff_rock_tiki", 10.0, Color(1, 1, 1), 0.92, 0.0],
	"regolith": ["offroad_space", 10.0, Color(1, 1, 1), 0.9, 0.0],
	"kicker": ["cliff_rock_tiki", 6.0, Color(1, 1, 1), 0.9, 0.0],
}

# wall style -> [texture set, metres per repeat, tint, roughness, metallic]
const WALL_TEX := {
	"temple": ["wall_tiki", 6.0, Color(1, 1, 1), 0.9, 0.0],
	"hut": ["wood_bridge", 4.0, Color(0.9, 0.78, 0.62), 0.9, 0.0],
	"rock": ["cliff_rock_tiki", 10.0, Color(1, 1, 1), 0.92, 0.0],
	"cave": ["cliff_rock_tiki", 9.0, Color(0.62, 0.66, 0.70), 0.7, 0.0],
	"lab": ["wall_biolab", 6.0, Color(1, 1, 1), 0.5, 0.35],
	"space": ["wall_space", 6.0, Color(1, 1, 1), 0.42, 0.45],
	"ice": ["wall_glacier", 8.0, Color(1, 1, 1), 0.3, 0.0],
	"volcano": ["wall_volcano", 7.0, Color(1, 1, 1), 0.86, 0.0],
	"wood": ["wood_bridge", 4.0, Color(1, 1, 1), 0.84, 0.0],
	"metal": ["road_metal", 6.0, Color(0.9, 0.92, 0.95), 0.45, 0.6],
	"concrete": ["road_asphalt", 8.0, Color(1.25, 1.22, 1.18), 0.85, 0.0],
}

static func load_tex(path: String) -> Texture2D:
	if _tex_cache.has(path):
		return _tex_cache[path]
	var t: Texture2D = null
	if ResourceLoader.exists(path):
		var r = load(path)
		if r is Texture2D:
			t = r
	_tex_cache[path] = t
	return t

static func pbr(tex_name: String, tint: Color = Color.WHITE, rough: float = 0.85, metal: float = 0.0, normal_scale: float = 1.2) -> StandardMaterial3D:
	var key := "pbr|%s|%s|%.2f|%.2f" % [tex_name, tint.to_html(), rough, metal]
	if _cache.has(key):
		return _cache[key]
	var m := StandardMaterial3D.new()
	var alb := load_tex("res://assets/textures/%s_albedo.png" % tex_name)
	if alb == null and tex_name.begins_with("road_"):
		alb = load_tex("res://assets/textures/road_tiki_albedo.png")
	if alb:
		m.albedo_texture = alb
		var nrm := load_tex("res://assets/textures/%s_normal.png" % tex_name)
		if nrm:
			m.normal_enabled = true
			m.normal_texture = nrm
			m.normal_scale = normal_scale
		var rg := load_tex("res://assets/textures/%s_rough.png" % tex_name)
		if rg:
			m.roughness_texture = rg
	m.albedo_color = tint
	m.roughness = rough
	m.metallic = metal
	m.metallic_specular = 0.3
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	_cache[key] = m
	return m

static func surface_mat(surf: String, indoor: bool = false) -> StandardMaterial3D:
	var e: Array = SURF_TEX.get(surf, SURF_TEX["stone"])
	var tint: Color = e[2]
	if indoor:
		tint = tint * Color(0.72, 0.72, 0.76)
	return pbr(str(e[0]), tint, float(e[3]), float(e[4]))

static func surface_repeat(surf: String) -> float:
	var e: Array = SURF_TEX.get(surf, SURF_TEX["stone"])
	return float(e[1])

static func wall_mat(style: String, indoor: bool = false) -> StandardMaterial3D:
	var e: Array = WALL_TEX.get(style, WALL_TEX["temple"])
	var tint: Color = e[2]
	if indoor:
		tint = tint * Color(0.7, 0.7, 0.74)
	return pbr(str(e[0]), tint, float(e[3]), float(e[4]))

static func wall_repeat(style: String) -> float:
	var e: Array = WALL_TEX.get(style, WALL_TEX["temple"])
	return float(e[1])

static func flat(col: Color, rough: float = 0.8, metal: float = 0.0, emissive: float = 0.0) -> StandardMaterial3D:
	var key := "flat|%s|%.2f|%.2f|%.2f" % [col.to_html(), rough, metal, emissive]
	if _cache.has(key):
		return _cache[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.roughness = rough
	m.metallic = metal
	if emissive > 0.0:
		m.emission_enabled = true
		m.emission = col
		m.emission_energy_multiplier = emissive
	_cache[key] = m
	return m

static func unshaded(col: Color, alpha: bool = false) -> StandardMaterial3D:
	var key := "unshaded|%s|%s" % [col.to_html(), str(alpha)]
	if _cache.has(key):
		return _cache[key]
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = col
	if alpha:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_cache[key] = m
	return m

## Wall style for a sample (explicit theme_wall wins, otherwise derived from biome / indoor).
static func wall_style_for(s: Dictionary) -> String:
	var tw: String = str(s.get("theme_wall", ""))
	if tw != "":
		return tw
	var b: String = str(s.get("biome", ""))
	if b.begins_with("cave") or b == "ice_cave" or b == "asteroid_core":
		return "cave"
	if b.begins_with("lab") or b.begins_with("bio") or b == "reactor" or b == "sewer" or b == "coolant":
		return "lab"
	if b.begins_with("space") or b.begins_with("city") or b == "orbital" or b == "plasma":
		return "space"
	if b.begins_with("arctic") or b.begins_with("glacier") or b == "frozen_lake":
		return "ice"
	if b.begins_with("magma") or b.begins_with("volcan") or b == "mine":
		return "volcano"
	if b.begins_with("jungle") and str(s.get("ground", "")) == "elevated":
		return "wood"
	return "temple"
