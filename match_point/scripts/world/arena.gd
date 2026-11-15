class_name Arena
extends Node3D
## يبني العالم المرئي: الملعب، الشبكة، الاستاد، الجمهور، الإضاءة والسماء.

const SUN_DIR := Vector3(0.38, 0.82, 0.42)      # الاتجاه نحو الشمس

const PALETTES := {
	Court.Surface.HARD: {"court": Color(0.15, 0.29, 0.50), "outer": Color(0.20, 0.38, 0.30), "wall": Color(0.06, 0.12, 0.26)},
	Court.Surface.CLAY: {"court": Color(0.70, 0.33, 0.17), "outer": Color(0.70, 0.33, 0.17), "wall": Color(0.07, 0.25, 0.16)},
	Court.Surface.GRASS: {"court": Color(0.17, 0.33, 0.10), "outer": Color(0.17, 0.33, 0.10), "wall": Color(0.05, 0.17, 0.10)},
}

var surface: int = Court.Surface.HARD
var quality := 1
var sun: DirectionalLight3D
var env: WorldEnvironment
var court_mat: ShaderMaterial
var crowd_mat: ShaderMaterial
var stands_mat: ShaderMaterial
var staff_mat: ShaderMaterial
var _marks: Array = []
var _excite := 0.0
var _excite_target := 0.0
var _end_nodes := {1: [], -1: []}       # عناصر المدرج خلف كل خط قاعدة (تُخفى إن وقعت الكاميرا داخلها)
var _end_hidden := {1: false, -1: false}
var _speed_labels: Array = []
var _st_z_in := 19.75
var _st_base_h := 1.3
var _st_far_z := 33.4
var _st_top_y := 8.3
const ROW_D := 0.85
const ROW_H := 0.44


func build(p_surface: int, p_quality: int) -> void:
	surface = p_surface
	quality = p_quality
	_build_environment()
	_build_court()
	_build_net()
	_build_stadium()
	_build_props()


func sun_dir() -> Vector3:
	return SUN_DIR.normalized()


# ---------------------------------------------------------------------
func _build_environment() -> void:
	env = WorldEnvironment.new()
	var e := Environment.new()
	var sky := Sky.new()
	var sm := ShaderMaterial.new()
	sm.shader = load("res://shaders/sky.gdshader")
	sm.set_shader_parameter("sun_dir", sun_dir())
	sm.set_shader_parameter("cloud_tex", _noise_tex(0.007, 256, 77, 5))
	sm.set_shader_parameter("cloud_cover", [0.46, 0.30, 0.58][clampi(surface, 0, 2)])
	sky.sky_material = sm
	sky.radiance_size = Sky.RADIANCE_SIZE_64
	sky.process_mode = Sky.PROCESS_MODE_INCREMENTAL
	e.background_mode = Environment.BG_SKY
	e.sky = sky
	# إضاءة محيطة ثابتة اللون (ضوء السماء المنتشر) لنتيجة متطابقة على كل الأجهزة
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.60, 0.70, 0.86)
	e.ambient_light_energy = 0.58
	e.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	e.tonemap_white = 5.0
	e.tonemap_exposure = 0.95
	# ضباب مسافة خفيف يعطي عمقاً جوياً للمدرجات البعيدة + تدرّج لوني تلفزيوني
	e.fog_enabled = true
	e.fog_light_color = Color(0.66, 0.76, 0.90)
	e.fog_density = 0.0022
	e.fog_sky_affect = 0.0
	e.adjustment_enabled = true
	e.adjustment_contrast = 1.07
	e.adjustment_saturation = 1.06
	if quality >= 1:
		e.glow_enabled = true
		e.glow_intensity = 0.25
		e.glow_bloom = 0.02
		e.glow_hdr_threshold = 1.1
	env.environment = e
	add_child(env)

	sun = DirectionalLight3D.new()
	sun.light_color = Color(1.0, 0.95, 0.86)
	sun.light_energy = 1.25
	sun.shadow_enabled = quality >= 0
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS if quality >= 1 else DirectionalLight3D.SHADOW_ORTHOGONAL
	sun.directional_shadow_max_distance = 62.0
	sun.directional_shadow_split_1 = 0.35
	sun.shadow_blur = 1.2
	sun.shadow_bias = 0.04
	sun.shadow_normal_bias = 1.2
	add_child(sun)
	# الضوء يتجه عكس اتجاه الشمس
	sun.look_at_from_position(sun_dir() * 30.0, Vector3.ZERO, Vector3.UP)


func _noise_tex(freq: float, size: int, seed_v: int, octaves: int = 4) -> NoiseTexture2D:
	var n := FastNoiseLite.new()
	n.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	n.frequency = freq
	n.fractal_octaves = octaves
	n.seed = seed_v
	var t := NoiseTexture2D.new()
	t.width = size
	t.height = size
	t.seamless = true
	t.generate_mipmaps = true
	t.noise = n
	return t


func _build_court() -> void:
	var pal: Dictionary = PALETTES[surface]
	var pm := PlaneMesh.new()
	pm.size = Vector2(Court.ARENA_HALF_W * 2.0 + 0.6, Court.ARENA_HALF_L * 2.0 + 0.6)
	var mi := MeshInstance3D.new()
	mi.mesh = pm
	court_mat = ShaderMaterial.new()
	court_mat.shader = load("res://shaders/court.gdshader")
	court_mat.set_shader_parameter("surface", surface)
	court_mat.set_shader_parameter("court_color", pal["court"])
	court_mat.set_shader_parameter("outer_color", pal["outer"])
	court_mat.set_shader_parameter("noise_tex", _noise_tex(0.012, 256, 11))
	court_mat.set_shader_parameter("grain_tex", _noise_tex(0.11, 256, 23, 3))
	var gn := _noise_tex(0.16, 256, 41, 2)
	gn.as_normal_map = true
	gn.bump_strength = 5.0
	court_mat.set_shader_parameter("grain_nrm", gn)
	court_mat.set_shader_parameter("arena_half", Vector2(Court.ARENA_HALF_W + 0.3, Court.ARENA_HALF_L + 0.3))
	court_mat.set_shader_parameter("sun_dir", sun_dir())
	court_mat.set_shader_parameter("mark_count", 0)
	mi.material_override = court_mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	# أرضية خرسانية واسعة تحت الاستاد كله (تظهر فقط إن أُخفي مدرج خلفي للكاميرا المسطحة)
	var gp := PlaneMesh.new()
	gp.size = Vector2(120.0, 140.0)
	var gmi := MeshInstance3D.new()
	gmi.mesh = gp
	gmi.position.y = -0.03
	var gmat := StandardMaterial3D.new()
	gmat.albedo_color = (pal["outer"] as Color).lerp(Color(0.3, 0.32, 0.35), 0.55)
	gmat.roughness = 0.9
	gmi.material_override = gmat
	gmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(gmi)


func add_mark(pos: Vector3, speed: float) -> void:
	var strength := 1.0 if surface == Court.Surface.CLAY else 0.5
	_marks.append(Vector4(pos.x, pos.z, clampf(0.045 + speed * 0.0022, 0.05, 0.14), strength))
	if _marks.size() > 24:
		_marks.pop_front()
	var arr: Array = _marks.duplicate()
	while arr.size() < 24:
		arr.append(Vector4(0, 0, 0.01, 0))
	court_mat.set_shader_parameter("marks", arr)
	court_mat.set_shader_parameter("mark_count", _marks.size())


func clear_marks() -> void:
	_marks.clear()
	court_mat.set_shader_parameter("mark_count", 0)


# ---------------------------------------------------------------------
func _build_net() -> void:
	# نسيج الشبكة: خيوط سوداء على خلفية شفافة مع mipmaps (تبدو رمادية شفافة من بعيد كالحقيقة)
	var size := 64
	var img := Image.create(size, size, true, Image.FORMAT_RGBA8)
	img.fill(Color(0.02, 0.02, 0.02, 0.0))
	for y in size:
		for x in size:
			if x < 6 or y < 6:
				img.set_pixel(x, y, Color(0.03, 0.03, 0.03, 1.0))
	img.generate_mipmaps()
	var tex := ImageTexture.create_from_image(img)

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var segs := 32
	var cell := 0.045
	for i in segs:
		var x0 := lerpf(-Court.POST_X, Court.POST_X, float(i) / segs)
		var x1 := lerpf(-Court.POST_X, Court.POST_X, float(i + 1) / segs)
		var h0 := Court.net_height(x0) - 0.045
		var h1 := Court.net_height(x1) - 0.045
		var b := 0.03
		var v := [Vector3(x0, b, 0), Vector3(x1, b, 0), Vector3(x1, h1, 0), Vector3(x0, h0, 0)]
		var uv := [Vector2(x0 / cell, b / cell), Vector2(x1 / cell, b / cell), Vector2(x1 / cell, h1 / cell), Vector2(x0 / cell, h0 / cell)]
		for k in [0, 1, 2, 0, 2, 3]:
			st.set_normal(Vector3(0, 0, 1))
			st.set_uv(uv[k])
			st.add_vertex(v[k])
	var net := MeshInstance3D.new()
	net.mesh = st.commit()
	var nm := StandardMaterial3D.new()
	nm.albedo_texture = tex
	nm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	nm.cull_mode = BaseMaterial3D.CULL_DISABLED
	nm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	nm.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	net.material_override = nm
	net.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(net)

	# الشريط الأبيض العلوي + حزام المنتصف + الأشرطة الجانبية + الأعمدة وعصوا الفردي
	var st2 := MeshKit.begin()
	var white := Color(0.95, 0.95, 0.93)
	var white2 := Color(0.86, 0.86, 0.84)
	for i in segs:
		var x0 := lerpf(-Court.POST_X, Court.POST_X, float(i) / segs)
		var x1 := lerpf(-Court.POST_X, Court.POST_X, float(i + 1) / segs)
		var xm := (x0 + x1) * 0.5
		var hm := Court.net_height(xm) - 0.030
		var slope := atan2(Court.net_height(x1) - Court.net_height(x0), x1 - x0)
		var xf := Transform3D(Basis(Vector3(0, 0, 1), slope), Vector3(xm, hm, 0))
		# شريط مزدوج الطيّة: جسم أبيض + حافة سفلية مخيطة أغمق قليلاً
		MeshKit.add_box(st2, Vector3.ZERO, Vector3((x1 - x0) * 1.02, 0.062, 0.018), white, xf)
		MeshKit.add_box(st2, Vector3(0, -0.034, 0), Vector3((x1 - x0) * 1.02, 0.008, 0.012), white2, xf)
	# حزام المنتصف ومثبّته الأرضي
	MeshKit.add_box(st2, Vector3(0, 0.455, 0), Vector3(0.05, 0.89, 0.020), white)
	MeshKit.add_box(st2, Vector3(0, 0.012, 0), Vector3(0.09, 0.024, 0.06), Color(0.55, 0.57, 0.60))
	# الحبل السفلي للشبكة
	MeshKit.add_box(st2, Vector3(0, 0.03, 0), Vector3(Court.POST_X * 2.0, 0.012, 0.012), Color(0.05, 0.05, 0.05))
	var post_c := Color(0.05, 0.16, 0.11)
	var metal_c := Color(0.62, 0.64, 0.67)
	for sx in [-1.0, 1.0]:
		var px: float = sx * (Court.POST_X + 0.045)
		# شريط جانبي أبيض يربط الشبكة بالعمود
		MeshKit.add_box(st2, Vector3(sx * (Court.POST_X - 0.02), 0.54, 0), Vector3(0.045, 1.0, 0.016), white)
		MeshKit.add_tube(st2, [[0.0, 0.050, 0.050, post_c], [0.03, 0.050, 0.050, post_c], [0.03, 0.040, 0.040, post_c], [1.07, 0.040, 0.040, post_c], [1.085, 0.044, 0.044, metal_c], [1.10, 0.030, 0.030, metal_c]], 12,
			Transform3D(Basis.IDENTITY, Vector3(px, 0, 0)))
		MeshKit.add_box(st2, Vector3(px, 0.008, 0), Vector3(0.24, 0.016, 0.24), Color(0.30, 0.32, 0.34))
		# رافعة شدّ الحبل على العمود
		MeshKit.add_box(st2, Vector3(px + sx * 0.055, 0.78, 0), Vector3(0.05, 0.11, 0.09), metal_c)
		MeshKit.add_tube(st2, [[0.0, 0.008, 0.008, metal_c], [0.12, 0.008, 0.008, metal_c]], 6,
			Transform3D(Basis(Vector3(1, 0, 0), PI * 0.5), Vector3(px + sx * 0.06, 0.78, 0.04)))
		# عصا الفردي
		var sxp: float = sx * (Court.SINGLES_HALF_W + 0.914)
		var sh := Court.net_height(sxp) + 0.012
		MeshKit.add_tube(st2, [[0.0, 0.016, 0.016, metal_c], [sh - 0.02, 0.014, 0.014, metal_c], [sh, 0.018, 0.018, white]], 8,
			Transform3D(Basis.IDENTITY, Vector3(sxp, 0, 0.03)))
	var tape := MeshInstance3D.new()
	tape.mesh = MeshKit.finish(st2)
	tape.material_override = MeshKit.vcol_material(0.62)
	add_child(tape)


# ---------------------------------------------------------------------
func _plain(c: Color, kind: float = 0.0) -> Color:
	return Color(c.r, c.g, c.b, kind)


func _build_stadium() -> void:
	var pal: Dictionary = PALETTES[surface]
	var wall_c: Color = pal["wall"]
	var hw := Court.ARENA_HALF_W + 0.3
	var hl := Court.ARENA_HALF_L + 0.3
	var wall_h := 1.15
	var th := 0.25
	var rows := 16
	var row_d := ROW_D
	var row_h := ROW_H
	var base_h := wall_h + 0.15
	var x_in := hw + th
	var z_in := hl + th
	var full_w := (x_in + rows * row_d) * 2.0
	var top_y := base_h + rows * row_h
	var far_x := x_in + rows * row_d
	var far_z := z_in + rows * row_d
	_st_z_in = z_in
	_st_base_h = base_h
	_st_far_z = far_z
	_st_top_y = top_y

	stands_mat = ShaderMaterial.new()
	stands_mat.shader = load("res://shaders/stands.gdshader")
	var seat_cols: Array = [[Color(0.06, 0.14, 0.36), Color(0.10, 0.22, 0.50)], [Color(0.05, 0.24, 0.16), Color(0.08, 0.32, 0.22)], [Color(0.07, 0.22, 0.12), Color(0.24, 0.10, 0.32)]][clampi(surface, 0, 2)]
	stands_mat.set_shader_parameter("seat_a", seat_cols[0])
	stands_mat.set_shader_parameter("seat_b", seat_cols[1])
	stands_mat.set_shader_parameter("noise_tex", _noise_tex(0.03, 128, 5, 3))
	stands_mat.set_shader_parameter("x_in", x_in)
	stands_mat.set_shader_parameter("z_in", z_in)
	stands_mat.set_shader_parameter("base_h", base_h)
	stands_mat.set_shader_parameter("row_h", row_h)
	stands_mat.set_shader_parameter("row_d", row_d)
	stands_mat.set_shader_parameter("u0_end", -full_w * 0.5 + 0.3)
	stands_mat.set_shader_parameter("u0_side", -z_in + 0.3)

	var st_side := MeshKit.begin()
	var st_end := {1: MeshKit.begin(), -1: MeshKit.begin()}
	var st_roof := MeshKit.begin()
	var st_led := MeshKit.begin()
	var st_glow := MeshKit.begin()
	var st_rail := {0: MeshKit.begin(), 1: MeshKit.begin(), -1: MeshKit.begin()}
	var wall_p := _plain(wall_c, 0.2)
	var trim := _plain(Color(0.85, 0.86, 0.88))
	var conc := Color(0.50, 0.51, 0.54, 1.0)
	var facade := _plain(Color(0.20, 0.22, 0.26), 0.2)
	var steel := _plain(Color(0.78, 0.80, 0.83))
	var rail := _plain(Color(0.72, 0.74, 0.77))

	# الحواجز المحيطة بالملعب + شريطها العلوي
	for sgn in [-1.0, 1.0]:
		var se: SurfaceTool = st_end[int(sgn)]
		MeshKit.add_box(se, Vector3(0, wall_h * 0.5, sgn * (hl + th * 0.5)), Vector3(hw * 2 + th * 2, wall_h, th), wall_p)
		MeshKit.add_box(se, Vector3(0, wall_h + 0.02, sgn * (hl + th * 0.5)), Vector3(hw * 2 + th * 2, 0.04, th + 0.04), trim)
		MeshKit.add_box(st_side, Vector3(sgn * (hw + th * 0.5), wall_h * 0.5, 0), Vector3(th, wall_h, hl * 2), wall_p)
		MeshKit.add_box(st_side, Vector3(sgn * (hw + th * 0.5), wall_h + 0.02, 0), Vector3(th + 0.04, 0.04, hl * 2), trim)

	# المدرجات (المقاعد والممرات تُرسم في الشيدر) + قائمة مواضع الجمهور
	var seats: Array = []     # [pos, yaw, stand]
	for r in rows:
		var y := base_h + r * row_h
		var off := r * row_d
		for sgn in [-1.0, 1.0]:
			MeshKit.add_box(st_end[int(sgn)], Vector3(0, y * 0.5, sgn * (z_in + off + row_d * 0.5)), Vector3(full_w, y, row_d), conc)
			MeshKit.add_box(st_side, Vector3(sgn * (x_in + off + row_d * 0.5), y * 0.5, 0), Vector3(row_d, y, z_in * 2.0), conc)
		var nx := int(full_w / 0.56)
		for i in nx:
			if (i + 5) % 16 < 2:
				continue          # ممر/سلم
			var x := -full_w * 0.5 + 0.3 + i * 0.56
			if absf(x) > x_in + off + row_d:
				continue
			seats.append([Vector3(x, y, z_in + off + row_d * 0.45), PI, 0])
			seats.append([Vector3(x, y, -(z_in + off + row_d * 0.45)), 0.0, 1])
		var nz := int(z_in * 2.0 / 0.56)
		for i in nz:
			if (i + 14) % 16 < 2:
				continue
			var z := -z_in + 0.3 + i * 0.56
			seats.append([Vector3(x_in + off + row_d * 0.45, y, z), -PI * 0.5, 2])
			seats.append([Vector3(-(x_in + off + row_d * 0.45), y, z), PI * 0.5, 3])

	# درابزين معدني أمام الصف الأول (شبكة مستقلة لا تلقي ظلالاً)
	for sgn in [-1.0, 1.0]:
		var se2: SurfaceTool = st_rail[int(sgn)]
		var sr: SurfaceTool = st_rail[0]
		MeshKit.add_box(se2, Vector3(0, base_h + 0.62, sgn * (z_in + 0.04)), Vector3(x_in * 2.0, 0.035, 0.035), rail)
		MeshKit.add_box(se2, Vector3(0, base_h + 0.32, sgn * (z_in + 0.04)), Vector3(x_in * 2.0, 0.02, 0.02), rail)
		MeshKit.add_box(sr, Vector3(sgn * (x_in + 0.04), base_h + 0.62, 0), Vector3(0.035, 0.035, z_in * 2.0), rail)
		MeshKit.add_box(sr, Vector3(sgn * (x_in + 0.04), base_h + 0.32, 0), Vector3(0.02, 0.02, z_in * 2.0), rail)
		var k := -x_in
		while k <= x_in + 0.01:
			MeshKit.add_box(se2, Vector3(k, base_h + 0.31, sgn * (z_in + 0.04)), Vector3(0.03, 0.62, 0.03), rail)
			k += x_in * 2.0 / 12.0
		k = -z_in
		while k <= z_in + 0.01:
			MeshKit.add_box(sr, Vector3(sgn * (x_in + 0.04), base_h + 0.31, k), Vector3(0.03, 0.62, 0.03), rail)
			k += z_in * 2.0 / 20.0

	# --- خلف خطي القاعدة: جدار علوي + منصة كاميرات البث ---
	for sgn in [-1.0, 1.0]:
		var se3: SurfaceTool = st_end[int(sgn)]
		MeshKit.add_box(se3, Vector3(0, (top_y + 1.3) * 0.5, sgn * (far_z + 0.35)), Vector3(far_x * 2 + 1.4, top_y + 1.3, 0.7), facade)
		MeshKit.add_box(se3, Vector3(0, top_y + 1.36, sgn * (far_z + 0.35)), Vector3(far_x * 2 + 1.6, 0.12, 0.9), trim)
		# أعمدة تحمل لوحة النتائج
		for dx in [-5.6, 5.6]:
			MeshKit.add_box(se3, Vector3(dx, top_y + 2.3, sgn * (far_z + 0.35)), Vector3(0.35, 2.0, 0.35), steel)

	# --- المدرجان الجانبيان: جدار، مقصورات زجاجية، شريط LED، سقف معلّق بعوارض وكشافات ---
	var suite_y0 := top_y + 1.1
	var suite_h := 2.6
	var roof_y := top_y + 6.2
	var roof_in := 7.5
	var glass := Color(0.5, 0.6, 0.7, 0.5)
	var roof_c := Color(0.86, 0.87, 0.89, 0.75)
	for sgn in [-1.0, 1.0]:
		MeshKit.add_box(st_side, Vector3(sgn * (far_x + 0.3), suite_y0 * 0.5, 0), Vector3(0.6, suite_y0, far_z * 2.0), facade)
		MeshKit.add_box(st_side, Vector3(sgn * (far_x + 1.3), suite_y0 + suite_h * 0.5, 0), Vector3(2.0, suite_h, far_z * 2.0 + 0.6), glass)
		MeshKit.add_box(st_side, Vector3(sgn * (far_x + 0.3), suite_y0 + 0.06, 0), Vector3(0.9, 0.12, far_z * 2.0 + 0.8), trim)
		# واجهة علوية تحمل شريط LED
		MeshKit.add_box(st_side, Vector3(sgn * (far_x + 1.25), suite_y0 + suite_h + 0.55, 0), Vector3(2.3, 1.1, far_z * 2.0 + 0.8), facade)
		MeshKit.add_box(st_led, Vector3(sgn * (far_x + 0.08), suite_y0 + suite_h + 0.55, 0), Vector3(0.06, 0.7, far_z * 2.0 - 1.0), Color(1, 1, 1))
		# السقف
		var rx0 := far_x + 2.6
		var rx1 := far_x - roof_in
		MeshKit.add_box(st_roof, Vector3(sgn * (rx0 + rx1) * 0.5, roof_y, 0), Vector3(rx0 - rx1, 0.30, far_z * 2.0 + 3.0), roof_c)
		MeshKit.add_box(st_roof, Vector3(sgn * (rx1 + 0.2), roof_y - 0.25, 0), Vector3(0.4, 0.5, far_z * 2.0 + 3.0), _plain(Color(0.90, 0.91, 0.93)))
		var zc := -far_z
		while zc <= far_z + 0.01:
			# عمود خلفي + عارضة مائلة تحمل السقف
			MeshKit.add_box(st_roof, Vector3(sgn * (far_x + 2.1), (roof_y + suite_y0 + suite_h + 1.1) * 0.5, zc), Vector3(0.45, roof_y - (suite_y0 + suite_h + 1.1), 0.45), steel)
			MeshKit.add_box(st_roof, Vector3(sgn * (rx0 + rx1) * 0.5, roof_y - 0.42, zc), Vector3(rx0 - rx1 - 0.3, 0.5, 0.28), steel)
			# كشافات على الحافة الداخلية
			MeshKit.add_box(st_glow, Vector3(sgn * (rx1 + 0.55), roof_y - 0.62, zc + 2.2), Vector3(0.5, 0.22, 2.6), Color(1.0, 0.98, 0.92))
			zc += far_z * 2.0 / 10.0
	# أبراج الإضاءة في الزوايا
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			var bp := Vector3(sx * (far_x + 1.4), 0, sz * (far_z + 1.4))
			MeshKit.add_box(st_side, bp + Vector3(0, (top_y + 11.0) * 0.5, 0), Vector3(0.55, top_y + 11.0, 0.55), steel)
			var txf := Transform3D(Basis(Vector3.UP, atan2(sx, sz)), bp + Vector3(-sx * 0.6, top_y + 11.4, -sz * 0.6))
			MeshKit.add_box(st_side, Vector3.ZERO, Vector3(3.6, 2.2, 0.35), _plain(Color(0.25, 0.26, 0.28)), txf)
			for ry in 3:
				for rxx in 5:
					MeshKit.add_box(st_glow, Vector3((rxx - 2) * 0.66, (ry - 1) * 0.62, -0.20), Vector3(0.48, 0.44, 0.08), Color(1.0, 0.98, 0.92), txf)

	var parts: Array = [[st_side, null], [st_end[1], 1], [st_end[-1], -1]]
	for pr in parts:
		var mi := MeshInstance3D.new()
		mi.mesh = MeshKit.finish(pr[0])
		mi.material_override = stands_mat
		add_child(mi)
		if pr[1] != null:
			(_end_nodes[int(pr[1])] as Array).append(mi)
	for rk in [0, 1, -1]:
		var rmi := MeshInstance3D.new()
		rmi.mesh = MeshKit.finish(st_rail[rk])
		rmi.material_override = MeshKit.vcol_material(0.4, 0.6)
		rmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(rmi)
		if rk != 0:
			(_end_nodes[rk] as Array).append(rmi)
	var roof := MeshInstance3D.new()
	roof.mesh = MeshKit.finish(st_roof)
	roof.material_override = stands_mat
	add_child(roof)
	var led := MeshInstance3D.new()
	led.mesh = MeshKit.finish(st_led)
	var lm := ShaderMaterial.new()
	lm.shader = load("res://shaders/led.gdshader")
	led.material_override = lm
	led.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(led)
	var glow := MeshInstance3D.new()
	glow.mesh = MeshKit.finish(st_glow)
	var gm := StandardMaterial3D.new()
	gm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	gm.albedo_color = Color(1.0, 0.98, 0.93)
	glow.material_override = gm
	glow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(glow)
	_build_crowd(seats)
	_build_scoreboards(far_z, top_y)
	_build_signage(hw, hl, wall_h, wall_c)


## ارتفاع سطح المدرج الخلفي عند بُعد z عن المنتصف
func stand_height(az: float) -> float:
	if az < _st_z_in:
		return 0.0
	if az > _st_far_z + 0.7:
		return 0.0
	if az > _st_far_z:
		return _st_top_y + 1.4
	return _st_base_h + floorf((az - _st_z_in) / ROW_D) * ROW_H


## يُستدعى كل إطار بموضع الكاميرا: إن كان خط النظر من الكاميرا إلى خط القاعدة القريب يمرّ عبر مدرج خلفي
## (كاميرا مسطحة/بعيدة) يُخفى ذلك المدرج حتى لا يحجب الملعب — وهو أصلاً خلف مجال الرؤية.
func set_camera_view(cam_pos: Vector3) -> void:
	for sgn in [1, -1]:
		var az: float = cam_pos.z * float(sgn)
		var hide := false
		if az > _st_z_in - 1.0:
			var z0 := Court.HALF_LENGTH
			for i in 9:
				var z := lerpf(_st_z_in - 0.6, minf(az, _st_far_z + 0.7), float(i) / 8.0)
				var sight := lerpf(0.6, cam_pos.y, clampf((z - z0) / maxf(az - z0, 0.1), 0.0, 1.0))
				var sh := stand_height(z) if z >= _st_z_in else 1.25
				if sh + 0.55 > sight:
					hide = true
					break
		if hide != bool(_end_hidden[sgn]):
			_end_hidden[sgn] = hide
			for n in (_end_nodes[sgn] as Array):
				(n as Node3D).visible = not hide


func _build_crowd(seats: Array) -> void:
	var fill: float = [0.34, 0.68, 0.9][clampi(quality, 0, 2)]
	var suf := "" if quality >= 2 else "_lo"
	var meshes := [_glb_mesh("res://assets/characters/crowd_m%s.glb" % suf), _glb_mesh("res://assets/characters/crowd_f%s.glb" % suf)]
	var rng := RandomNumberGenerator.new()
	rng.seed = 2026
	# مجموعة لكل مدرج: المدرج خارج مجال الرؤية يُستبعد كاملاً من الرسم
	var groups: Array = [[], [], [], [], [], [], [], []]
	for s in seats:
		var p: Vector3 = s[0]
		# ممر الكاميرا خلف اللاعب القريب يبقى خالياً
		if absf(p.x) < 3.4 and p.y > 4.2 and absf(p.z) > Court.ARENA_HALF_L:
			continue
		if rng.randf() < fill:
			groups[int(s[2]) * 2 + (1 if rng.randf() < 0.42 else 0)].append(s)
	var shirts := [Color(0.9, 0.9, 0.92), Color(0.85, 0.2, 0.2), Color(0.15, 0.3, 0.7), Color(0.95, 0.8, 0.25), Color(0.2, 0.55, 0.3),
		Color(0.1, 0.1, 0.12), Color(0.95, 0.55, 0.2), Color(0.6, 0.75, 0.9), Color(0.75, 0.3, 0.6), Color(0.9, 0.9, 0.92), Color(0.55, 0.57, 0.6)]
	crowd_mat = ShaderMaterial.new()
	crowd_mat.shader = load("res://shaders/crowd.gdshader")
	for gi in groups.size():
		var chosen: Array = groups[gi]
		if chosen.is_empty():
			continue
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_custom_data = true
		mm.mesh = meshes[gi % 2]
		mm.instance_count = chosen.size()
		for i in chosen.size():
			var s: Array = chosen[i]
			var sc := rng.randf_range(0.88, 1.08)
			var b := Basis(Vector3.UP, float(s[1]) + PI + rng.randf_range(-0.25, 0.25)).scaled(Vector3(sc, sc * rng.randf_range(0.94, 1.05), sc))
			mm.set_instance_transform(i, Transform3D(b, (s[0] as Vector3) + Vector3(0, 0.02, 0)))
			var c: Color = shirts[rng.randi() % shirts.size()]
			c = c.lerp(Color(rng.randf(), rng.randf(), rng.randf()), 0.18)
			# اللون المخصص: rgb قميص، a يحمل درجتي البشرة والشعر معاً
			var packed := float(rng.randi_range(0, 9)) * 0.1 + rng.randf() * 0.09
			mm.set_instance_custom_data(i, Color(c.r, c.g, c.b, packed))
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.material_override = crowd_mat
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mmi)
		var stand_i := gi / 2
		if stand_i == 0:
			(_end_nodes[1] as Array).append(mmi)
		elif stand_i == 1:
			(_end_nodes[-1] as Array).append(mmi)


func _glb_mesh(path: String) -> Mesh:
	var inst: Node = (load(path) as PackedScene).instantiate()
	var m: Mesh = _find_mesh(inst)
	inst.free()
	return m


func _find_mesh(n: Node) -> Mesh:
	if n is MeshInstance3D:
		return (n as MeshInstance3D).mesh
	for c in n.get_children():
		var m := _find_mesh(c)
		if m != null:
			return m
	return null


# ---------------------------------------------------------------------
#  لوحتا النتائج الكبيرتان في الاستاد (فوق المدرجين الخلفيين)
# ---------------------------------------------------------------------
var _boards: Array = []


func _build_scoreboards(far_z: float, top_y: float) -> void:
	var font: Font = UiKit.font_bold()
	for sgn in [-1.0, 1.0]:
		var root := Node3D.new()
		root.position = Vector3(0, top_y + 3.2, sgn * (far_z + 0.2))
		root.rotation.y = 0.0 if sgn < 0.0 else PI
		add_child(root)
		var back := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(10.5, 3.4, 0.4)
		back.mesh = bm
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.02, 0.03, 0.06)
		mat.roughness = 0.4
		back.material_override = mat
		root.add_child(back)
		var rows := []
		for i in 3:
			var l := Label3D.new()
			l.font = font
			l.font_size = 120
			l.pixel_size = 0.0068
			l.shaded = false
			l.double_sided = false
			l.position = Vector3(0, 1.05 - i * 1.05, 0.22)
			l.modulate = Color(1.0, 0.92, 0.45) if i == 0 else Color(0.95, 0.97, 1.0)
			l.outline_size = 0
			root.add_child(l)
			rows.append(l)
		_boards.append(rows)


func update_scoreboard(names: Array, r: MatchRules, srv: int) -> void:
	for rows in _boards:
		(rows[0] as Label3D).text = "شوط فاصل" if r.tiebreak else ("المجموعة %d" % (r.set_history.size() + 1))
		for i in 2:
			var sets := ""
			for h in r.set_history:
				sets += "  " + str(h[i])
			var pts := r.point_label(i) if not r.finished else ""
			var ball := "●  " if i == srv and not r.finished else "    "
			(rows[i + 1] as Label3D).text = "%s%s%s   %d   %s" % [ball, names[i], sets, r.games[i] if not r.finished else 0, pts]


func _build_signage(hw: float, hl: float, wall_h: float, wall_c: Color) -> void:
	var font: Font = UiKit.font_bold()
	var texts := ["نقطة المباراة", "MATCH POINT", "نقطة المباراة", "MATCH POINT"]
	var xs := [-6.5, -2.2, 2.2, 6.5]
	for sgn in [-1.0, 1.0]:
		for i in xs.size():
			var l := Label3D.new()
			l.text = texts[i]
			l.font = font
			l.font_size = 96
			l.pixel_size = 0.0042
			l.modulate = Color(0.92, 0.93, 0.95, 0.92)
			l.outline_size = 0
			l.shaded = false
			l.double_sided = false
			l.position = Vector3(xs[i] * sgn, wall_h * 0.52, sgn * (hl - 0.01))
			l.rotation.y = PI if sgn > 0.0 else 0.0
			add_child(l)
			(_end_nodes[int(sgn)] as Array).append(l)
	for sgn in [-1.0, 1.0]:
		for z in [-12.0, -4.0, 4.0, 12.0]:
			var l := Label3D.new()
			l.text = "MATCH POINT" if int(absf(z)) % 8 == 4 else "نقطة المباراة"
			l.font = font
			l.font_size = 96
			l.pixel_size = 0.0042
			l.modulate = Color(0.92, 0.93, 0.95, 0.92)
			l.outline_size = 0
			l.shaded = false
			l.position = Vector3(sgn * (hw - 0.01), wall_h * 0.52, z)
			l.rotation.y = -PI * 0.5 * sgn
			add_child(l)


func _strut(st: SurfaceTool, a: Vector3, b: Vector3, r: float, col: Color, seg: int = 6) -> void:
	var d := b - a
	var ln := d.length()
	if ln < 0.001:
		return
	var dn := d / ln
	var bas := Basis.IDENTITY
	if dn.dot(Vector3.UP) < -0.9999:
		bas = Basis(Vector3.RIGHT, PI)
	elif dn.dot(Vector3.UP) < 0.9999:
		bas = Basis(Quaternion(Vector3.UP, dn))
	MeshKit.add_tube(st, [[0.0, r, r, col], [ln, r, r, col]], seg, Transform3D(bas, a))


func _build_props() -> void:
	var st := MeshKit.begin()
	var metal := Color(0.20, 0.22, 0.25)
	var alu := Color(0.74, 0.76, 0.79)
	var white := Color(0.93, 0.94, 0.95)
	var seat: Color = [Color(0.07, 0.20, 0.42), Color(0.06, 0.30, 0.20), Color(0.08, 0.28, 0.14)][clampi(surface, 0, 2)]
	var staff: Array = []       # [pos, yaw, scale, shirt, seated]

	# ---------------- كرسي الحكم ----------------
	var ux := -(Court.POST_X + 1.25)
	for dx in [-1.0, 1.0]:
		for dz in [-1.0, 1.0]:
			_strut(st, Vector3(ux + dx * 0.46, 0, dz * 0.44), Vector3(ux + dx * 0.30, 1.86, dz * 0.30), 0.026, alu, 8)
			MeshKit.add_box(st, Vector3(ux + dx * 0.46, 0.012, dz * 0.44), Vector3(0.12, 0.024, 0.12), metal)
	for y in [0.38, 0.76, 1.14, 1.50]:
		var k: float = 1.0 - float(y) / 1.86 * 0.35
		_strut(st, Vector3(ux - 0.46 * k - 0.0, y, -0.44 * k), Vector3(ux - 0.46 * k, y, 0.44 * k), 0.016, alu)       # درجات السلم
		_strut(st, Vector3(ux + 0.46 * k, y, -0.44 * k), Vector3(ux + 0.46 * k, y, 0.44 * k), 0.012, alu)
	_strut(st, Vector3(ux - 0.42, 0.9, -0.40), Vector3(ux + 0.42, 0.9, -0.40), 0.012, alu)
	_strut(st, Vector3(ux - 0.42, 0.9, 0.40), Vector3(ux + 0.42, 0.9, 0.40), 0.012, alu)
	MeshKit.add_box(st, Vector3(ux + 0.12, 1.42, 0), Vector3(0.50, 0.035, 0.62), metal)           # مسند القدمين
	MeshKit.add_box(st, Vector3(ux, 1.87, 0), Vector3(0.62, 0.06, 0.62), seat)                     # المقعد
	MeshKit.add_box(st, Vector3(ux - 0.29, 2.22, 0), Vector3(0.05, 0.66, 0.58), seat)              # المسند
	for dz in [-0.31, 0.31]:
		MeshKit.add_box(st, Vector3(ux + 0.02, 2.12, dz), Vector3(0.56, 0.035, 0.05), metal)       # مسندا الذراعين
		_strut(st, Vector3(ux + 0.26, 1.9, dz), Vector3(ux + 0.26, 2.12, dz), 0.012, alu)
		_strut(st, Vector3(ux - 0.29, 2.5, dz * 0.9), Vector3(ux - 0.20, 3.22, dz * 0.9), 0.012, alu)
	MeshKit.add_box(st, Vector3(ux + 0.40, 2.16, 0), Vector3(0.10, 0.02, 0.34), Color(0.06, 0.06, 0.08))   # لوح النتيجة
	_strut(st, Vector3(ux + 0.36, 2.12, 0.22), Vector3(ux + 0.44, 2.36, 0.22), 0.007, metal)        # الميكروفون
	MeshKit.add_box(st, Vector3(ux + 0.05, 3.24, 0), Vector3(1.15, 0.04, 1.05), seat)              # مظلة
	MeshKit.add_box(st, Vector3(ux + 0.05, 3.21, 0), Vector3(1.19, 0.02, 1.09), white)
	staff.append([Vector3(ux - 0.03, 1.87 - 0.44, 0), -PI * 0.5, 1.0, Color(0.10, 0.16, 0.36), true])

	# ---------------- مقاعد اللاعبين ----------------
	for zi in 2:
		var z: float = [-3.4, 3.4][zi]
		var bx := ux - 0.25
		MeshKit.add_box(st, Vector3(bx, 0.46, z), Vector3(0.48, 0.05, 1.9), white)
		MeshKit.add_box(st, Vector3(bx - 0.25, 0.80, z), Vector3(0.04, 0.50, 1.9), white)
		for dz in [-0.85, 0.0, 0.85]:
			_strut(st, Vector3(bx - 0.2, 0, z + dz), Vector3(bx - 0.2, 0.46, z + dz), 0.016, alu)
			_strut(st, Vector3(bx + 0.2, 0, z + dz), Vector3(bx + 0.2, 0.46, z + dz), 0.016, alu)
			_strut(st, Vector3(bx - 0.25, 0.46, z + dz), Vector3(bx - 0.27, 1.05, z + dz), 0.014, alu)
		# مظلة فوق المقعد
		_strut(st, Vector3(bx - 0.42, 0, z), Vector3(bx - 0.42, 2.25, z), 0.02, alu, 8)
		MeshKit.add_tube(st, [[0.0, 1.25, 1.25, seat], [0.10, 1.0, 1.0, white], [0.26, 0.5, 0.5, seat], [0.34, 0.03, 0.03, seat]], 12,
			Transform3D(Basis.IDENTITY, Vector3(bx - 0.25, 2.15, z)), false, true)
		# منشفة، قوارير، حقيبة مضارب، مبرّد
		MeshKit.add_box(st, Vector3(bx - 0.24, 0.92, z + 0.55), Vector3(0.05, 0.34, 0.42), Color(0.95, 0.95, 0.97))
		MeshKit.add_box(st, Vector3(bx + 0.02, 0.495, z + 0.55), Vector3(0.40, 0.02, 0.42), Color(0.95, 0.95, 0.97))
		for b in 3:
			var bc: Color = [Color(0.25, 0.55, 0.85), Color(0.95, 0.55, 0.15), Color(0.25, 0.55, 0.85)][b]
			MeshKit.add_tube(st, [[0.0, 0.032, 0.032, bc], [0.17, 0.032, 0.032, bc], [0.20, 0.014, 0.014, white], [0.23, 0.014, 0.014, white]], 8,
				Transform3D(Basis.IDENTITY, Vector3(bx + 0.48 + 0.02 * b, 0.0, z - 0.2 + 0.11 * b)))
		var bag: Color = [Color(0.75, 0.10, 0.12), Color(0.10, 0.12, 0.16)][zi]
		MeshKit.add_ellipsoid(st, Vector3(bx + 0.62, 0.17, z + 0.62), Vector3(0.19, 0.17, 0.40), bag, 10, 6)
		MeshKit.add_box(st, Vector3(bx + 0.62, 0.345, z + 0.62), Vector3(0.05, 0.02, 0.5), Color(0.9, 0.9, 0.9))
		MeshKit.add_box(st, Vector3(bx + 0.55, 0.2, z - 0.72), Vector3(0.42, 0.40, 0.40), Color(0.20, 0.42, 0.75))
		MeshKit.add_box(st, Vector3(bx + 0.55, 0.42, z - 0.72), Vector3(0.45, 0.05, 0.43), white)

	# ---------------- كاميرات البث الأرضية ----------------
	for cam_p in [Vector3(9.35, 0, -1.6), Vector3(-9.35, 0, 13.5)]:
		var cp: Vector3 = cam_p
		var face := -signf(cp.x)
		for a in 3:
			var ang := TAU * a / 3.0 + 0.3
			_strut(st, cp + Vector3(cos(ang) * 0.45, 0, sin(ang) * 0.45), cp + Vector3(0, 1.28, 0), 0.016, metal)
		MeshKit.add_box(st, cp + Vector3(0, 1.34, 0), Vector3(0.16, 0.10, 0.16), metal)
		MeshKit.add_box(st, cp + Vector3(face * 0.05, 1.52, 0), Vector3(0.52, 0.26, 0.24), Color(0.10, 0.10, 0.12))
		MeshKit.add_tube(st, [[0.0, 0.085, 0.085, Color(0.05, 0.05, 0.06)], [0.30, 0.075, 0.075, Color(0.05, 0.05, 0.06)], [0.31, 0.095, 0.095, Color(0.12, 0.12, 0.14)], [0.36, 0.095, 0.095, Color(0.12, 0.12, 0.14)]], 10,
			Transform3D(Basis(Vector3(0, 0, 1), -face * PI * 0.5), cp + Vector3(face * 0.30, 1.52, 0)))
		MeshKit.add_box(st, cp + Vector3(-face * 0.30, 1.60, 0), Vector3(0.10, 0.14, 0.18), Color(0.10, 0.10, 0.12))
		staff.append([cp + Vector3(-face * 0.62, 0, 0.05), -PI * 0.5 * face, 1.0, Color(0.08, 0.08, 0.10), false])

	# ---------------- لوحتا سرعة الإرسال (LED) خلف خطي القاعدة ----------------
	var hl := Court.ARENA_HALF_L + 0.3
	var font: Font = UiKit.font_bold()
	for sgn in [-1.0, 1.0]:
		var stb := MeshKit.begin()
		var bpos := Vector3(-sgn * 7.9, 1.72, sgn * (hl + 0.14))
		MeshKit.add_box(stb, bpos, Vector3(2.2, 0.95, 0.16), Color(0.03, 0.03, 0.04))
		MeshKit.add_box(stb, bpos + Vector3(0, 0.50, 0), Vector3(2.3, 0.05, 0.2), alu)
		var bmi := MeshInstance3D.new()
		bmi.mesh = MeshKit.finish(stb)
		bmi.material_override = MeshKit.vcol_material(0.5)
		add_child(bmi)
		(_end_nodes[int(sgn)] as Array).append(bmi)
		var l := Label3D.new()
		l.font = font
		l.font_size = 110
		l.pixel_size = 0.0052
		l.shaded = false
		l.double_sided = false
		l.outline_size = 0
		l.modulate = Color(1.0, 0.72, 0.18)
		l.text = "MATCH POINT"
		l.position = bpos + Vector3(0, -0.02, -sgn * 0.09)
		l.rotation.y = PI if sgn > 0.0 else 0.0
		add_child(l)
		(_end_nodes[int(sgn)] as Array).append(l)
		_speed_labels.append(l)

	var mi := MeshInstance3D.new()
	mi.mesh = MeshKit.finish(st)
	mi.material_override = MeshKit.vcol_material(0.62)
	add_child(mi)

	# ---------------- الحكام وجامعو الكرات (نماذج بشرية منخفضة المضلعات) ----------------
	var judge := Color(0.10, 0.14, 0.30)
	var kid := Color(0.92, 0.48, 0.10)
	for sp in [Vector3(-9.3, 0, -17.6), Vector3(9.3, 0, -17.6), Vector3(-9.3, 0, 17.6), Vector3(9.3, 0, 17.6), Vector3(9.5, 0, 0.9)]:
		var p: Vector3 = sp
		staff.append([p, atan2(p.x, p.z) , 0.86, kid, false])
	for sp in [Vector3(-9.5, 0, -6.4), Vector3(9.5, 0, 6.4), Vector3(4.3, 0, -18.6), Vector3(-4.3, 0, 18.6)]:
		var p2: Vector3 = sp
		staff.append([p2, atan2(p2.x, p2.z), 1.0, judge, false])
	staff_mat = ShaderMaterial.new()
	staff_mat.shader = load("res://shaders/crowd.gdshader")
	var rng := RandomNumberGenerator.new()
	rng.seed = 77
	for seated in [false, true]:
		var list: Array = staff.filter(func(e: Array) -> bool: return bool(e[4]) == seated)
		if list.is_empty():
			continue
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_custom_data = true
		mm.mesh = _glb_mesh("res://assets/characters/crowd_m.glb" if seated else "res://assets/characters/crowd_staff.glb")
		mm.instance_count = list.size()
		for i in list.size():
			var e: Array = list[i]
			var sc: float = e[2]
			mm.set_instance_transform(i, Transform3D(Basis(Vector3.UP, float(e[1])).scaled(Vector3(sc, sc, sc)), e[0]))
			var c: Color = e[3]
			mm.set_instance_custom_data(i, Color(c.r, c.g, c.b, float(rng.randi_range(2, 8)) * 0.1 + rng.randf() * 0.05))
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.material_override = staff_mat
		add_child(mmi)


## تعرض سرعة الإرسال على لوحتي LED في الملعب
func show_serve_speed(kmh: float, _p: int = 0) -> void:
	for l in _speed_labels:
		(l as Label3D).text = "%d km/h" % int(round(kmh))


func cheer(amount: float) -> void:
	_excite_target = amount


func _process(dt: float) -> void:
	if crowd_mat == null:
		return
	_excite_target = move_toward(_excite_target, 0.0, dt * 0.45)
	_excite = lerpf(_excite, _excite_target, clampf(dt * 5.0, 0.0, 1.0))
	crowd_mat.set_shader_parameter("excitement", _excite)
