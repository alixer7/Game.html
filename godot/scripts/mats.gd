extends Node
## Procedural textures, materials, shaders and fonts (autoload "Mats").

var T := {}      # textures
var M := {}      # shared materials
var S := {}      # shaders
var font_title: FontFile
var font_latin: FontFile
var font_ar: FontFile

func _ready() -> void:
	_fonts()
	_textures()
	_shaders()
	_shared()

# ---------------------------------------------------------------- fonts
func _load_font(path: String) -> FontFile:
	# Imported resource works in exported builds (APK); raw file is a fallback for un-imported runs.
	if ResourceLoader.exists(path):
		var r = load(path)
		if r is FontFile: return r
	var f := FontFile.new()
	if f.load_dynamic_font(path) != OK:
		push_warning("font load failed: " + path)
	return f

func _fonts() -> void:
	font_title = _load_font("res://fonts/CinzelDecorative-Black.ttf")
	font_latin = _load_font("res://fonts/Cinzel.ttf")
	font_ar = _load_font("res://fonts/Cairo.ttf")
	var dv := _load_font("res://fonts/DejaVuSans-Bold.ttf")
	# Arabic face first; DejaVu supplies arrows/symbols; display fonts fall back to both
	font_ar.fallbacks = [dv]
	font_title.fallbacks = [font_ar, dv]
	font_latin.fallbacks = [font_ar, dv]

# ---------------------------------------------------------------- noise helpers
func noise(type: int, freq: float, oct := 4, seed := 1, cell_ret := FastNoiseLite.RETURN_DISTANCE2_SUB) -> FastNoiseLite:
	var n := FastNoiseLite.new()
	n.noise_type = type
	n.frequency = freq
	n.seed = seed
	n.fractal_octaves = oct
	if type == FastNoiseLite.TYPE_CELLULAR:
		n.cellular_return_type = cell_ret
		n.fractal_type = FastNoiseLite.FRACTAL_NONE
	return n

func grad(stops: Array) -> Gradient:
	var g := Gradient.new()
	var o := PackedFloat32Array()
	var c := PackedColorArray()
	for s in stops:
		o.append(s[0])
		c.append(s[1])
	g.offsets = o
	g.colors = c
	return g

func ntex(n: FastNoiseLite, size := 256, ramp: Gradient = null, normal := false, bump := 8.0) -> NoiseTexture2D:
	var t := NoiseTexture2D.new()
	t.width = size
	t.height = size
	t.seamless = true
	t.noise = n
	t.generate_mipmaps = true
	if ramp:
		t.color_ramp = ramp
	if normal:
		t.as_normal_map = true
		t.bump_strength = bump
	return t

func _img_tex(img: Image) -> ImageTexture:
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)

# ---------------------------------------------------------------- textures
func _textures() -> void:
	var CELL := FastNoiseLite.TYPE_CELLULAR
	var SIMP := FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	# stone floor: cellular flagstones
	var cell := noise(CELL, 0.018, 1, 7)
	T.stone_c = ntex(cell, 512, grad([[0.0, Color(0.04, 0.035, 0.035)], [0.05, Color(0.13, 0.115, 0.11)], [0.3, Color(0.19, 0.17, 0.16)], [1.0, Color(0.25, 0.22, 0.2)]]))
	T.stone_n = ntex(cell, 512, null, true, 10.0)
	T.stone_r = ntex(noise(SIMP, 0.01, 5, 3), 256, grad([[0.0, Color(0.25, 0.25, 0.25)], [0.5, Color(0.8, 0.8, 0.8)], [1.0, Color(0.95, 0.95, 0.95)]]))
	T.stone_detail = ntex(noise(SIMP, 0.04, 5, 11), 256, grad([[0.0, Color(0.55, 0.5, 0.5)], [0.6, Color(1, 1, 1)], [1.0, Color(1, 0.95, 0.92)]]))
	# walls / pillars
	var wc := noise(CELL, 0.03, 1, 21)
	T.wall_c = ntex(wc, 256, grad([[0.0, Color(0.05, 0.045, 0.045)], [0.08, Color(0.16, 0.14, 0.135)], [1.0, Color(0.24, 0.21, 0.2)]]))
	T.wall_n = ntex(wc, 256, null, true, 6.0)
	# skin pores / wrinkles
	T.skin_n = ntex(noise(SIMP, 0.12, 4, 5), 256, null, true, 3.0)
	T.mottle = ntex(noise(SIMP, 0.02, 5, 9), 256, grad([[0.0, Color(0.78, 0.76, 0.8)], [1.0, Color(1, 1, 1)]]))
	# muscle fibres (material uses stretched UVs)
	var mf := noise(SIMP, 0.06, 4, 13)
	T.muscle_c = ntex(mf, 256, grad([[0.0, Color(0.2, 0.0, 0.01)], [0.45, Color(0.45, 0.03, 0.04)], [0.75, Color(0.62, 0.08, 0.07)], [0.92, Color(0.78, 0.5, 0.45)], [1.0, Color(0.85, 0.75, 0.62)]]))
	T.muscle_n = ntex(mf, 256, null, true, 9.0)
	# veins (detail layer)
	T.veins = ntex(noise(CELL, 0.03, 1, 17), 256, grad([[0.0, Color(0.32, 0.18, 0.4)], [0.06, Color(0.75, 0.7, 0.8)], [0.12, Color(1, 1, 1)], [1.0, Color(1, 1, 1)]]))
	# metal + lava cracks
	var mn := noise(SIMP, 0.03, 5, 23)
	T.metal_c = ntex(mn, 256, grad([[0.0, Color(0.12, 0.11, 0.1)], [0.6, Color(0.22, 0.21, 0.2)], [0.85, Color(0.3, 0.16, 0.1)], [1.0, Color(0.35, 0.15, 0.08)]]))
	T.metal_n = ntex(noise(CELL, 0.05, 1, 25, FastNoiseLite.RETURN_DISTANCE), 256, null, true, 4.0)
	T.metal_r = ntex(mn, 256, grad([[0.0, Color(0.3, 0.3, 0.3)], [1.0, Color(0.8, 0.8, 0.8)]]))
	T.lava = ntex(noise(CELL, 0.022, 1, 29), 256, grad([[0.0, Color(1.0, 0.5, 0.1)], [0.022, Color(0.85, 0.18, 0.02)], [0.05, Color(0, 0, 0)], [1.0, Color(0, 0, 0)]]))
	# leather / cloth / bone
	var ln := noise(CELL, 0.06, 1, 31)
	T.leather_c = ntex(ln, 256, grad([[0.0, Color(0.06, 0.04, 0.03)], [0.1, Color(0.16, 0.11, 0.08)], [1.0, Color(0.24, 0.17, 0.12)]]))
	T.leather_n = ntex(ln, 256, null, true, 5.0)
	T.cloth_noise = ntex(noise(SIMP, 0.03, 4, 37), 256)
	T.bone_c = ntex(noise(SIMP, 0.05, 5, 41), 256, grad([[0.0, Color(0.55, 0.5, 0.4)], [0.5, Color(0.82, 0.76, 0.62)], [1.0, Color(0.9, 0.86, 0.74)]]))
	T.bone_n = ntex(noise(SIMP, 0.1, 4, 43), 256, null, true, 3.0)
	# particle sprites
	T.glow = _img_tex(_radial(64, 2.0))
	T.smoke = _img_tex(_smoke(64))
	T.flame = _img_tex(_flame(64))
	T.spark = _img_tex(_radial(32, 6.0))
	T.splats = []
	for k in 4:
		T.splats.append(_img_tex(_splat(128, 400 + k * 31)))

func _radial(sz: int, k: float) -> Image:
	var img := Image.create(sz, sz, false, Image.FORMAT_RGBA8)
	var h := sz * 0.5
	for y in sz:
		for x in sz:
			var d := Vector2(x - h + 0.5, y - h + 0.5).length() / h
			var a := clampf(exp(-d * d * k) - 0.02, 0.0, 1.0)
			img.set_pixel(x, y, Color(1, 1, 1, a))
	return img

func _smoke(sz: int) -> Image:
	var img := Image.create(sz, sz, false, Image.FORMAT_RGBA8)
	var n := noise(FastNoiseLite.TYPE_SIMPLEX_SMOOTH, 0.08, 4, 3)
	var h := sz * 0.5
	for y in sz:
		for x in sz:
			var d := Vector2(x - h, y - h).length() / h
			var v := (n.get_noise_2d(x, y) * 0.5 + 0.5)
			var a := clampf((1.0 - d) * 1.4, 0.0, 1.0) * smoothstep(0.2, 0.75, v + (1.0 - d) * 0.3)
			img.set_pixel(x, y, Color(1, 1, 1, a))
	return img

func _flame(sz: int) -> Image:
	var img := Image.create(sz, sz, false, Image.FORMAT_RGBA8)
	var n := noise(FastNoiseLite.TYPE_SIMPLEX_SMOOTH, 0.09, 3, 5)
	for y in sz:
		for x in sz:
			var u := float(x) / sz
			var v := float(y) / sz
			var dx := (u - 0.5) * 2.0
			var dy := (v - 0.62) * 2.0
			var shape := dx * dx * (1.5 + (1.0 - v) * 2.5) + (dy * dy * 3.0 if dy > 0.0 else dy * dy * 0.55)
			var a := clampf(1.0 - shape - n.get_noise_2d(x, y) * 0.45, 0.0, 1.0)
			img.set_pixel(x, y, Color(1, 1, 1, pow(a, 1.4)))
	return img

func _splat(sz: int, sd: int) -> Image:
	var rng := RandomNumberGenerator.new()
	rng.seed = sd
	var img := Image.create(sz, sz, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var c := sz * 0.5
	var R := sz * (0.16 + rng.randf() * 0.06)
	var blobs := []
	for i in 14:
		var a := rng.randf() * TAU
		var l := R * (1.0 + rng.randf() * 1.6)
		blobs.append([c + cos(a) * l, c + sin(a) * l, 1.0 + rng.randf() * 4.0])
	for i in 30:
		var a := rng.randf() * TAU
		var l := R * (1.1 + rng.randf() * 2.0)
		blobs.append([c + cos(a) * l, c + sin(a) * l, 0.6 + rng.randf() * 2.2])
	var ph := rng.randf() * 6.0
	var col := Color(0.42, 0.0, 0.0, 0.92)
	var lim := int(R * 1.4)
	for y in range(maxi(0, int(c) - lim), mini(sz, int(c) + lim)):
		for x in range(maxi(0, int(c) - lim), mini(sz, int(c) + lim)):
			var dx := x - c
			var dy := y - c
			var ang := atan2(dy, dx)
			var rr := R * (0.82 + 0.18 * sin(ang * 3.0 + ph) + 0.1 * sin(ang * 7.0 + ph * 2.0))
			if sqrt(dx * dx + dy * dy) < rr:
				img.set_pixel(x, y, col)
	for b in blobs:
		var r: float = b[2]
		for y in range(maxi(0, int(b[1] - r)), mini(sz, int(b[1] + r) + 1)):
			for x in range(maxi(0, int(b[0] - r)), mini(sz, int(b[0] + r) + 1)):
				if Vector2(x - b[0], y - b[1]).length() < r:
					img.set_pixel(x, y, col)
	return img

# ---------------------------------------------------------------- shaders
func _shaders() -> void:
	S.decal = _sh("""shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, specular_schlick_ggx;
varying float seed;
float h(vec2 p){ return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float n2(vec2 p){ vec2 i = floor(p); vec2 f = fract(p); f = f * f * (3.0 - 2.0 * f); return mix(mix(h(i), h(i + vec2(1.0, 0.0)), f.x), mix(h(i + vec2(0.0, 1.0)), h(i + vec2(1.0, 1.0)), f.x), f.y); }
void vertex(){ seed = INSTANCE_CUSTOM.x * 10.0; }
void fragment(){
	vec2 p = (UV - 0.5) * 2.0; float r = length(p); float a = atan(p.y, p.x);
	float e = 0.5 + 0.12 * sin(a * 3.0 + seed * 7.0) + 0.07 * sin(a * 7.0 + seed * 3.0) + 0.16 * n2(vec2(a * 2.0, seed * 10.0));
	float m = smoothstep(e, e - 0.05, r);
	for (int i = 0; i < 7; i++) { float fi = float(i); vec2 c = vec2(cos(fi * 2.4 + seed * 6.0), sin(fi * 2.4 + seed * 6.0)) * (0.6 + 0.32 * h(vec2(fi, seed))); float rr = 0.04 + 0.07 * h(vec2(seed, fi)); m = max(m, smoothstep(rr, rr - 0.02, length(p - c))); }
	if (m < 0.05) { discard; }
	ALBEDO = vec3(0.16, 0.0, 0.008) * (0.65 + 0.35 * n2(p * 5.0 + seed));
	ROUGHNESS = 0.1; SPECULAR = 0.8; ALPHA = m * 0.94;
}""")
	S.ring = _sh("""shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled;
uniform vec4 col = vec4(1.0, 0.5, 0.3, 1.0);
void fragment(){ float r = length(UV - 0.5) * 2.0; float a = smoothstep(0.55, 0.92, r) * smoothstep(1.0, 0.93, r); ALBEDO = col.rgb * a * col.a; ALPHA = 1.0; }""")
	S.rune = _sh("""shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled;
uniform vec3 col = vec3(1.2, 0.07, 0.03);
uniform float intensity = 0.3;
float ring(float r, float c, float w){ return smoothstep(w, 0.0, abs(r - c)); }
float seg(vec2 p, vec2 a, vec2 b, float w){ vec2 pa = p - a; vec2 ba = b - a; float hh = clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0); return smoothstep(w, 0.0, length(pa - ba * hh)); }
void fragment(){
	vec2 p = (UV - 0.5) * 2.0; float r = length(p); float m = 0.0;
	m += ring(r, 0.96, 0.012) + ring(r, 0.9, 0.006) + ring(r, 0.7, 0.01) + ring(r, 0.66, 0.005) + ring(r, 0.25, 0.01);
	for (int i = 0; i < 7; i++) { float a0 = -1.5708 + float(i) * 6.2832 * 3.0 / 7.0; float a1 = -1.5708 + float(i + 1) * 6.2832 * 3.0 / 7.0; m += seg(p, vec2(cos(a0), sin(a0)) * 0.66, vec2(cos(a1), sin(a1)) * 0.66, 0.012); }
	float ang = atan(p.y, p.x); float t = fract(ang / 6.2832 * 28.0);
	m += step(0.74, r) * step(r, 0.86) * step(abs(t - 0.5), 0.07) * 0.8;
	ALBEDO = col * min(m, 1.0) * intensity; ALPHA = 1.0;
}""")
	S.glass = _sh("""shader_type spatial;
render_mode unshaded, cull_disabled;
uniform float energy = 2.2;
float h(vec2 p){ return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
void fragment(){
	vec2 p = (UV - 0.5) * 2.0; float r = length(p); if (r > 1.0) { discard; }
	float a = atan(p.y, p.x) / 6.2832 + 0.5;
	float ri = 3.0; if (r < 0.7) { ri = 2.0; } if (r < 0.42) { ri = 1.0; } if (r < 0.18) { ri = 0.0; }
	float N = 24.0; if (ri < 2.5) { N = 16.0; } if (ri < 1.5) { N = 8.0; } if (ri < 0.5) { N = 1.0; }
	float sa = a * N; float si = floor(sa); float fs = fract(sa);
	float lead = 0.0;
	for (int k = 0; k < 4; k++) { float c = 0.98; if (k == 0) { c = 0.18; } else if (k == 1) { c = 0.42; } else if (k == 2) { c = 0.7; } lead = max(lead, step(abs(r - c), 0.012)); }
	if (ri > 0.0) { lead = max(lead, step(min(fs, 1.0 - fs) * r * 6.2832 / N, 0.012)); }
	float s = h(vec2(si, ri));
	vec3 c = vec3(0.1, 0.07, 0.35); if (s < 0.85) { c = vec3(0.35, 0.03, 0.25); } if (s < 0.68) { c = vec3(0.95, 0.55, 0.1); } if (s < 0.5) { c = vec3(0.85, 0.16, 0.06); } if (s < 0.25) { c = vec3(0.6, 0.03, 0.04); }
	c *= 0.7 + 0.5 * h(floor(UV * 40.0));
	ALBEDO = mix(c * energy, vec3(0.01), lead);
}""")
	S.shaft = _sh("""shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled;
uniform vec3 col = vec3(1.0, 0.22, 0.1);
uniform float intensity = 0.18;
void fragment(){ float nd = abs(dot(NORMAL, VIEW)); float d = 0.7 + 0.3 * sin(UV.y * 30.0 + TIME * 0.6); ALBEDO = col * intensity * pow(nd, 2.5) * pow(UV.y, 1.2) * d; ALPHA = 1.0; }""")
	S.cloth = _sh("""shader_type spatial;
render_mode cull_disabled;
uniform vec3 albedo = vec3(0.1, 0.08, 0.09);
uniform float rough = 0.9;
uniform sampler2D noise_tex;
uniform float holes = 0.72;
void fragment(){
	float n = texture(noise_tex, UV * vec2(1.0, 3.0)).r;
	float fray = UV.y + (n - 0.5) * 0.3 + abs(UV.x - 0.5) * 0.1;
	if (n > holes || fray > 0.94) { discard; }
	ALBEDO = albedo * (0.65 + 0.7 * n); ROUGHNESS = rough;
}""")
	S.flame_quad = _sh("""shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled;
uniform sampler2D tex;
varying float iid;
void vertex(){ iid = float(INSTANCE_ID); MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]); }
void fragment(){ float f = 0.75 + 0.25 * sin(TIME * 13.0 + iid * 7.0) * sin(TIME * 7.3 + iid); float a = texture(tex, UV).a; ALBEDO = vec3(3.0, 1.3, 0.35) * a * f; ALPHA = 1.0; }""")
	S.post = _sh_ci("""shader_type canvas_item;
uniform sampler2D screen_tex : hint_screen_texture, filter_linear;
uniform float vig = 0.55;
uniform float grain = 0.035;
uniform float ca = 0.0012;
uniform float desat = 0.08;
uniform float impact = 0.0;
uniform float flash = 0.0;
uniform vec3 flash_col = vec3(1.0);
uniform float red = 0.0;
float rnd(vec2 c){ return fract(sin(dot(c, vec2(12.9898, 78.233))) * 43758.5453); }
void fragment(){
	vec2 uv = SCREEN_UV; vec2 d = uv - 0.5; float r2 = dot(d, d); vec2 off = d * ca * (1.0 + r2 * 6.0);
	vec3 c = vec3(texture(screen_tex, uv + off).r, texture(screen_tex, uv).g, texture(screen_tex, uv - off).b);
	float l = dot(c, vec3(0.299, 0.587, 0.114));
	c = mix(c, vec3(l), desat); c *= vec3(1.04, 0.97, 0.95);
	c += red * vec3(0.38, 0.0, 0.0) * smoothstep(0.04, 0.42, r2);
	c *= 1.0 - vig * smoothstep(0.1, 0.6, r2);
	c += (rnd(uv * vec2(1733.0, 977.0) + fract(TIME * 0.37)) - 0.5) * grain;
	if (impact > 0.0) { float k = step(0.15, l); vec3 imp = mix(vec3(0.95, 0.92, 0.88), vec3(0.015), k); float rd = step(0.1, c.r - max(c.g, c.b) * 1.7) * step(0.07, c.r); imp = mix(imp, vec3(0.78, 0.0, 0.02), rd); c = mix(c, imp, impact); }
	c = mix(c, flash_col, flash);
	COLOR = vec4(c, 1.0);
}""")

func _sh(code: String) -> Shader:
	var s := Shader.new()
	s.code = code
	return s

func _sh_ci(code: String) -> Shader:
	return _sh(code)

func smat(shader_name: String, params := {}) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = S[shader_name]
	for k in params:
		m.set_shader_parameter(k, params[k])
	return m

# ---------------------------------------------------------------- materials
func std(o := {}) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = o.get("color", Color.WHITE)
	if o.has("map"): m.albedo_texture = o.map
	if o.has("nmap"):
		m.normal_enabled = true
		m.normal_texture = o.nmap
		m.normal_scale = o.get("ns", 1.0)
	m.roughness = o.get("r", 0.7)
	if o.has("rmap"): m.roughness_texture = o.rmap
	m.metallic = o.get("metal", 0.0)
	m.metallic_specular = o.get("spec", 0.5)
	if o.has("uv"): m.uv1_scale = o.uv
	if o.get("rim", 0.0) > 0.0:
		m.rim_enabled = true
		m.rim = o.rim
		m.rim_tint = o.get("rim_tint", 0.4)
	if o.get("cc", 0.0) > 0.0:
		m.clearcoat_enabled = true
		m.clearcoat = o.cc
		m.clearcoat_roughness = o.get("ccr", 0.2)
	if o.has("emit"):
		m.emission_enabled = true
		m.emission = o.emit
		m.emission_energy_multiplier = o.get("ee", 1.0)
		if o.has("emap"):
			m.emission_texture = o.emap
			m.emission_operator = BaseMaterial3D.EMISSION_OP_MULTIPLY
	if o.has("detail"):
		m.detail_enabled = true
		m.detail_albedo = o.detail
		m.detail_blend_mode = BaseMaterial3D.BLEND_MODE_MUL
		m.detail_uv_layer = BaseMaterial3D.DETAIL_UV_1
	if o.get("double", false): m.cull_mode = BaseMaterial3D.CULL_DISABLED
	if o.get("vcol", false): m.vertex_color_use_as_albedo = true
	return m

func glow(c: Color, e := 4.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = c * e
	return m

func particle_mat(tex: Texture2D, additive: bool) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD if additive else BaseMaterial3D.BLEND_MODE_MIX
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.vertex_color_use_as_albedo = true
	m.albedo_texture = tex
	m.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	m.disable_receive_shadows = true
	return m

func _shared() -> void:
	M.stone = std({map = T.wall_c, nmap = T.wall_n, r = 0.92, uv = Vector3(3, 3, 1)})
	M.iron = std({map = T.metal_c, nmap = T.metal_n, rmap = T.metal_r, r = 1.0, metal = 0.85, uv = Vector3(2, 2, 1)})
	M.bone = std({map = T.bone_c, nmap = T.bone_n, r = 0.6})
	M.bone_v = std({map = T.bone_c, nmap = T.bone_n, r = 0.75, color = Color(0.62, 0.6, 0.56), vcol = true})
	M.flesh = std({map = T.muscle_c, nmap = T.muscle_n, r = 0.3, cc = 0.6, uv = Vector3(3, 1, 1)})
	M.blood = std({color = Color(0.2, 0.0, 0.01), r = 0.12, spec = 0.8, cc = 1.0})
	M.char = std({color = Color(0.03, 0.02, 0.02), r = 1.0, emit = Color(0.5, 0.1, 0.0), ee = 0.4})
