class_name HumanLook
extends RefCounted
## مظهر الإنسان: يطبق المواد (جلد، قماش، حذاء، شعر، عين) حسب اسم مادة السطح في النموذج المستورد.

static var _tex := {}


static func default_look() -> Dictionary:
	return {"skin": Color(0.80, 0.60, 0.48), "hair": Color(0.10, 0.07, 0.05), "iris": Color(0.32, 0.2, 0.1),
		"shirt": Color(0.94, 0.94, 0.95), "shirt_back": Color(0.94, 0.94, 0.95), "shirt_trim": Color(0.12, 0.2, 0.45),
		"shorts": Color(0.10, 0.14, 0.30), "shorts_stripe": Color(0.94, 0.94, 0.95), "shoes": Color(0.96, 0.96, 0.96),
		"shoes_accent": Color(0.12, 0.25, 0.6), "sock": Color(0.94, 0.94, 0.93), "stubble": 0.45, "lips": Color(0.62, 0.36, 0.33)}


static func _noise(key: String, freq: float, normal: bool, size: int = 256, oct: int = 3, cell: bool = false) -> Texture2D:
	if _tex.has(key):
		return _tex[key]
	var n := FastNoiseLite.new()
	n.noise_type = FastNoiseLite.TYPE_CELLULAR if cell else FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	n.frequency = freq
	n.fractal_octaves = oct
	var t := NoiseTexture2D.new()
	t.width = size
	t.height = size
	t.seamless = true
	t.generate_mipmaps = true
	t.as_normal_map = normal
	t.bump_strength = 3.0
	t.noise = n
	_tex[key] = t
	return t


static func _shader(name: String) -> Shader:
	var k := "sh_" + name
	if not _tex.has(k):
		_tex[k] = load("res://shaders/human/%s.gdshader" % name)
	return _tex[k]


static func apply(root: Node, p_look: Dictionary) -> Dictionary:
	var look := default_look()
	look.merge(p_look, true)
	var mats := {}
	var skin := ShaderMaterial.new()
	skin.shader = _shader("skin")
	skin.set_shader_parameter("skin", look["skin"])
	skin.set_shader_parameter("lips", look.get("lips", (look["skin"] as Color).lerp(Color(0.6, 0.25, 0.25), 0.35)))
	skin.set_shader_parameter("hair", look["hair"])
	skin.set_shader_parameter("sock", look["sock"])
	skin.set_shader_parameter("stubble", look.get("stubble", 0.4))
	skin.set_shader_parameter("pores", _noise("pores", 0.12, true, 256, 2, true))
	skin.set_shader_parameter("mottle", _noise("mottle", 0.02, false))
	if not _tex.has("detail"):
		_tex["detail"] = load("res://assets/characters/skin_detail.png")
	skin.set_shader_parameter("detail", _tex["detail"])
	mats["skin"] = skin
	var shirt := ShaderMaterial.new()
	shirt.shader = _shader("cloth")
	shirt.set_shader_parameter("base_color", look["shirt"])
	shirt.set_shader_parameter("back_color", look.get("shirt_back", look["shirt"]))
	shirt.set_shader_parameter("use_back", 1.0)
	shirt.set_shader_parameter("trim_color", look["shirt_trim"])
	shirt.set_shader_parameter("weave", _noise("weave", 0.35, true, 128, 1))
	shirt.set_shader_parameter("folds", _noise("folds", 0.018, true, 256, 3))
	mats["shirt"] = shirt
	var shorts := ShaderMaterial.new()
	shorts.shader = _shader("cloth")
	shorts.set_shader_parameter("base_color", look["shorts"])
	shorts.set_shader_parameter("trim_color", (look["shorts"] as Color).darkened(0.25))
	shorts.set_shader_parameter("stripe_color", look["shorts_stripe"])
	shorts.set_shader_parameter("use_stripe", 1.0)
	shorts.set_shader_parameter("weave", _noise("weave", 0.35, true, 128, 1))
	shorts.set_shader_parameter("folds", _noise("folds", 0.018, true, 256, 3))
	mats["shorts"] = shorts
	var shoes := ShaderMaterial.new()
	shoes.shader = _shader("shoe")
	shoes.set_shader_parameter("upper_color", look["shoes"])
	shoes.set_shader_parameter("accent_color", look["shoes_accent"])
	shoes.set_shader_parameter("mesh_tex", _noise("weave", 0.35, true, 128, 1))
	mats["shoes"] = shoes
	var hair := ShaderMaterial.new()
	hair.shader = _shader("hair")
	hair.set_shader_parameter("hair_color", look["hair"])
	hair.set_shader_parameter("strands", _noise("strands", 0.09, false, 256, 2))
	mats["hair"] = hair
	var eye := ShaderMaterial.new()
	eye.shader = _shader("eye")
	eye.set_shader_parameter("iris_color", look["iris"])
	mats["eye"] = eye
	_apply_rec(root, mats)
	return mats


static func _apply_rec(n: Node, mats: Dictionary) -> void:
	if n is MeshInstance3D:
		var mi := n as MeshInstance3D
		for i in mi.mesh.get_surface_count():
			var m := mi.mesh.surface_get_material(i)
			var key := m.resource_name if m != null else ""
			if mats.has(key):
				mi.set_surface_override_material(i, mats[key])
	for c in n.get_children():
		_apply_rec(c, mats)
