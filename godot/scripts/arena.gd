extends RefCounted
## "The Ossuary Throne": a ruined gothic cathedral of bones.

const Geo = preload("res://scripts/geo.gd")
const Rig = preload("res://scripts/rig.gd")
const PZ = preload("res://scripts/pose.gd")
const U = preload("res://scripts/util.gd")

var root: Node3D
var braziers := []
var cages := []
var banners := []
var rune_mat: ShaderMaterial
var glass_mat: ShaderMaterial
var moon: DirectionalLight3D
var key: DirectionalLight3D
var env: Environment
var t := 0.0
var next_bolt := 6.0
var bolt := -1.0
var flash := 0.0

func build(parent: Node3D) -> void:
	root = Node3D.new()
	root.name = "Arena"
	parent.add_child(root)
	_environment()
	var T: Dictionary = Mats.T
	var stone: Material = Mats.M.stone
	# ---- floor (+ physics floor for gibs)
	var floor_mat := Mats.std({map = T.stone_c, nmap = T.stone_n, ns = 1.3, rmap = T.stone_r, r = 1.0, uv = Vector3(9, 6, 1), color = Color(0.85, 0.8, 0.8)})
	floor_mat.detail_enabled = true
	floor_mat.detail_albedo = T.stone_detail
	floor_mat.detail_blend_mode = BaseMaterial3D.BLEND_MODE_MUL
	_mi(_plane(56, 36), floor_mat, Vector3(0, 0, -6), Vector3.ZERO, false)
	var body := StaticBody3D.new()
	body.collision_layer = 1
	for pl in [[Plane(Vector3.UP, 0.0)], [Plane(Vector3.BACK, -4.8)], [Plane(Vector3.LEFT, -9.0)], [Plane(Vector3.RIGHT, -9.0)]]:
		var cs := CollisionShape3D.new()
		var wb := WorldBoundaryShape3D.new()
		wb.plane = pl[0]
		cs.shape = wb
		body.add_child(cs)
	root.add_child(body)
	rune_mat = Mats.smat("rune")
	_mi(_plane(7.5, 7.5), rune_mat, Vector3(0, 0.012, -0.3), Vector3.ZERO, false)
	# ---- walls, windows, shafts
	var wall_mat := Mats.std({map = T.wall_c, nmap = T.wall_n, r = 0.95, uv = Vector3(10, 4, 1), color = Color(0.8, 0.75, 0.75)})
	_mi(_plane(64, 26), wall_mat, Vector3(0, 13, -17), Vector3(PI / 2, 0, 0), false)
	for x in [-1.0, 1.0]:
		_mi(_plane(40, 26), wall_mat, Vector3(x * 22, 13, -2), Vector3(PI / 2, 0, x * PI / 2) if false else Vector3(0, 0, 0), false).transform = Transform3D(Basis(Vector3.UP, -x * PI / 2) * Basis(Vector3.RIGHT, PI / 2), Vector3(x * 22, 13, -2))
	glass_mat = Mats.smat("glass", {energy = 2.4})
	var q := QuadMesh.new()
	q.size = Vector2(7.2, 7.2)
	_mi(q, glass_mat, Vector3(0, 10.5, -16.9), Vector3.ZERO, false)
	var mb := Geo.MB.new()
	mb.add(Geo.torus(3.75, 0.32, 40, 8), U.xf(Vector3(0, 10.5, -16.85), Vector3(PI / 2, 0, 0)), stone)
	for x in [-8.5, 8.5]:
		var q2 := QuadMesh.new()
		q2.size = Vector2(1.6, 6)
		_mi(q2, Mats.smat("glass", {energy = 1.3}), Vector3(x, 7, -16.9), Vector3.ZERO, false)
	for s in [[0.0, 10.5, 0.0, -1.5, 2.8, 4.5], [-8.5, 7.5, -5.0, -4.0, 0.7, 1.8], [8.5, 7.5, 5.0, -4.0, 0.7, 1.8]]:
		_shaft(Vector3(s[0], s[1], -16.5), Vector3(s[2], 0, s[3]), s[4], s[5])
	# ---- pillars & arches
	for x in [-14.0, -9.2, -4.6, 4.6, 9.2, 14.0]: _pillar(mb, Vector3(x, 0, -5.2), 11.0, stone)
	for x in [-12.0, -6.5, 6.5, 12.0]: _pillar(mb, Vector3(x, 0, -11), 11.0, stone)
	for x in [-10.5, 10.5]: _pillar(mb, Vector3(x, 0, 5.8), 11.0, stone)
	for pr in [[-14.0, -9.2], [-9.2, -4.6], [4.6, 9.2], [9.2, 14.0], [-4.6, 4.6]]:
		var cx: float = (pr[0] + pr[1]) / 2.0
		var r: float = (pr[1] - pr[0]) / 2.0
		var hk := 0.55 if r > 4.5 else 1.0
		var pts := []
		for k in 13:
			var a := PI * k / 12.0
			pts.append([cx + cos(a) * r, 12.2 + sin(a) * r * hk, -5.2])
		mb.add(Geo.taper(pts, 0.35, 0.35, 6, 24), Transform3D(), stone)
	# ---- braziers
	var coal := Mats.std({color = Color(0.07, 0.02, 0.0), r = 1.0, emit = Color(1, 0.23, 0), ee = 2.5})
	for p in [Vector3(-3.4, 0, -3.4), Vector3(3.4, 0, -3.4), Vector3(-8, 0, -1.5), Vector3(8, 0, -1.5)]:
		for i in 3:
			var a := i / 3.0 * TAU
			mb.add(Geo.cyl(0.03, 0.04, 1.25, 6), U.xf(p + Vector3(cos(a) * 0.22, 0.62, sin(a) * 0.22), Vector3(sin(a) * 0.18, 0, -cos(a) * 0.18)), Mats.M.iron)
		mb.add(Geo.cyl(0.55, 0.25, 0.4, 16), U.xf(p + Vector3(0, 1.35, 0)), Mats.M.iron)
		mb.add(Geo.ell(0.45, 0.08, 0.45, 12, 4), U.xf(p + Vector3(0, 1.52, 0)), coal)
		var L := OmniLight3D.new()
		L.light_color = Color(1, 0.42, 0.16)
		L.light_energy = 2.2
		L.omni_range = 9.0
		L.omni_attenuation = 1.6
		L.position = p + Vector3(0, 2.1, 0)
		root.add_child(L)
		braziers.append({p = p + Vector3(0, 1.55, 0), L = L, base = 2.2, seed = randf() * 100.0, acc = 0.0})
	# ---- chains, cages, hooks
	var links := []
	var flesh: Material = Mats.M.flesh
	for c in [[-2.6, -7.5, 6.2], [3.1, -8.4, 5.4]]:
		var y: float = c[2]
		for yy in range(0, int((16.0 - (y + 1.5)) / 0.12)):
			links.append([Vector3(c[0], 16.0 - yy * 0.12, c[1]), yy])
		var g := Node3D.new()
		g.position = Vector3(c[0], y + 1.5, c[1])
		root.add_child(g)
		var cm := Geo.MB.new()
		for i in 12:
			var a := i / 12.0 * TAU
			cm.add(Geo.cyl(0.02, 0.02, 1.9, 4), U.xf(Vector3(cos(a) * 0.55, -1.5, sin(a) * 0.55)), Mats.M.iron)
		for yy in [-2.45, -0.55]:
			cm.add(Geo.torus(0.55, 0.035, 20, 4), U.xf(Vector3(0, yy, 0)), Mats.M.iron)
		cm.add(Geo.cone(0.6, 0.5, 12), U.xf(Vector3(0, -0.3, 0)), Mats.M.iron)
		cm.add(Rig.skull_geo(), U.xf(Vector3(0.1, -2.32, 0.1), Vector3(0.4, 0.6, 0.9), Vector3.ONE * 1.1), Mats.M.bone_v)
		for i in 4:
			cm.add(Geo.cyl(0.02, 0.025, 0.45, 5), U.xf(Vector3(randf_range(-0.3, 0.3), -2.4, randf_range(-0.3, 0.3)), Vector3(PI / 2, randf() * TAU, randf_range(-0.3, 0.3))), Mats.M.bone)
		var cmi := MeshInstance3D.new()
		cmi.mesh = cm.build()
		g.add_child(cmi)
		cages.append({g = g, ph = randf() * 6.0})
	for c in [[-5.5, -6.2, 7.5], [6.2, -6.5, 8.2], [0.8, -9.5, 7.0]]:
		for yy in range(0, int((16.0 - c[2]) / 0.12)):
			links.append([Vector3(c[0], 16.0 - yy * 0.12, c[1]), yy])
		mb.add(Geo.torus(0.14, 0.025, 12, 4), U.xf(Vector3(c[0], c[2] - 0.15, c[1]), Vector3(PI / 2, 0, PI * 0.8)), Mats.M.iron)
		mb.add(Geo.ell(0.25, 0.38, 0.22, 10, 8), U.xf(Vector3(c[0] + 0.05, c[2] - 0.55, c[1]), Vector3(randf() * 3, randf() * 3, 0)), flesh)
	var lmm := MultiMesh.new()
	lmm.transform_format = MultiMesh.TRANSFORM_3D
	var tm := TorusMesh.new()
	tm.inner_radius = 0.052; tm.outer_radius = 0.088; tm.rings = 10; tm.ring_segments = 5
	lmm.mesh = tm
	lmm.instance_count = links.size()
	for i in links.size():
		var l = links[i]
		lmm.set_instance_transform(i, Transform3D(Basis(Vector3.UP, PI / 2 if l[1] % 2 == 1 else 0.0) * Basis(Vector3.BACK, PI / 2) * Basis(Vector3.RIGHT, PI / 2), l[0]))
	var lmi := MultiMeshInstance3D.new()
	lmi.multimesh = lmm
	lmi.material_override = Mats.M.iron
	root.add_child(lmi)
	# ---- skull piles
	var smb := Geo.MB.new()
	smb.add(Rig.skull_geo(), Transform3D(), Mats.M.bone_v)
	var smm := MultiMesh.new()
	smm.transform_format = MultiMesh.TRANSFORM_3D
	smm.mesh = smb.build()
	var spots := [[-4.6, -5.2], [4.6, -5.2], [-9.2, -5.2], [9.2, -5.2], [0.0, -10.8], [-3.0, -12.5], [3.0, -12.5], [-14.0, -5.2], [14.0, -5.2]]
	var rng := RandomNumberGenerator.new()
	rng.seed = 55
	smm.instance_count = 220
	for i in 220:
		var s: Array = spots[i % spots.size()]
		var a := rng.randf() * TAU
		var r := 0.7 + rng.randf() * 1.4
		var hgt := maxf(0.0, 0.9 - r * 0.45) * rng.randf()
		smm.set_instance_transform(i, Transform3D(U.rot_xyz(Vector3((rng.randf() - 0.5) * 1.2, rng.randf() * TAU, (rng.randf() - 0.5) * 1.2)).scaled(Vector3.ONE * (0.7 + rng.randf() * 0.4)), Vector3(s[0] + cos(a) * r, 0.1 + hgt, s[1] + sin(a) * r * 0.8)))
	var smi := MultiMeshInstance3D.new()
	smi.multimesh = smm
	root.add_child(smi)
	# ---- candles
	var cpos := []
	for i in 46:
		var a := rng.randf() * PI - PI
		var r := 3.6 + rng.randf() * 2.2
		cpos.append(Vector3(cos(a) * r * 1.3, 0.12 + rng.randf() * 0.35, -12.5 + sin(a) * r * 0.5 + 1.6))
	for x in [-4.6, 4.6]:
		for i in 6: cpos.append(Vector3(x + rng.randf_range(-1, 1), 0.1 + rng.randf() * 0.3, -4.2 + rng.randf_range(-0.5, 0.4)))
	var wax := Mats.std({color = Color(0.74, 0.68, 0.56), r = 0.55, emit = Color(0.17, 0.06, 0.0), ee = 0.4})
	var cmm := MultiMesh.new()
	cmm.transform_format = MultiMesh.TRANSFORM_3D
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.035; cyl.bottom_radius = 0.04; cyl.height = 1.0; cyl.radial_segments = 8; cyl.rings = 1
	cmm.mesh = cyl
	cmm.instance_count = cpos.size()
	var fmm := MultiMesh.new()
	fmm.transform_format = MultiMesh.TRANSFORM_3D
	var fq := QuadMesh.new()
	fq.size = Vector2(0.07, 0.11)
	fmm.mesh = fq
	fmm.instance_count = cpos.size()
	for i in cpos.size():
		var c: Vector3 = cpos[i]
		cmm.set_instance_transform(i, Transform3D(Basis().scaled(Vector3(1, c.y, 1)), Vector3(c.x, c.y / 2.0, c.z)))
		fmm.set_instance_transform(i, Transform3D(Basis(), Vector3(c.x, c.y + 0.05, c.z)))
	var cmi2 := MultiMeshInstance3D.new()
	cmi2.multimesh = cmm
	cmi2.material_override = wax
	root.add_child(cmi2)
	var fmi := MultiMeshInstance3D.new()
	fmi.multimesh = fmm
	fmi.material_override = Mats.smat("flame_quad", {tex = T.flame})
	fmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(fmi)
	# ---- banners
	var ban_mat := Mats.std({map = _banner_tex(), r = 0.9, double = true})
	ban_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	ban_mat.alpha_scissor_threshold = 0.5
	for x in [-6.9, 6.9, -11.6, 11.6]:
		var bq := QuadMesh.new()
		bq.size = Vector2(1.7, 3.6)
		var bmi := _mi(bq, ban_mat, Vector3(x, 8.6, -5.0), Vector3.ZERO, true)
		banners.append(bmi)
	# ---- merged static geometry
	var smi2 := MeshInstance3D.new()
	smi2.mesh = mb.build()
	root.add_child(smi2)
	_statue()
	_lights()

func _plane(w: float, h: float) -> PlaneMesh:
	var p := PlaneMesh.new()
	p.size = Vector2(w, h)
	return p

func _mi(mesh: Mesh, mat: Material, p: Vector3, r: Vector3, shadow: bool) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	m.mesh = mesh
	m.material_override = mat
	m.position = p
	m.rotation = r
	m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadow else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(m)
	return m

func _shaft(a: Vector3, b: Vector3, r0: float, r1: float) -> void:
	var cm := CylinderMesh.new()
	cm.top_radius = r0
	cm.bottom_radius = r1
	cm.height = a.distance_to(b)
	cm.cap_top = false
	cm.cap_bottom = false
	cm.radial_segments = 20
	var m := MeshInstance3D.new()
	m.mesh = cm
	m.material_override = Mats.smat("shaft")
	m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var y := (a - b).normalized()
	var x := y.cross(Vector3.BACK).normalized()
	if x.length_squared() < 0.01: x = Vector3.RIGHT
	m.transform = Transform3D(Basis(x, y, x.cross(y)), (a + b) * 0.5)
	root.add_child(m)

func _pillar(mb, p: Vector3, h: float, mat: Material) -> void:
	mb.add(Geo.box(1.7, 0.7, 1.7), U.xf(p + Vector3(0, 0.35, 0)), mat)
	mb.add(Geo.box(1.45, 0.3, 1.45), U.xf(p + Vector3(0, 0.85, 0)), mat)
	mb.add(Geo.cyl(0.52, 0.6, h, 16), U.xf(p + Vector3(0, h / 2.0 + 1.0, 0)), mat)
	for i in 6:
		var a := i / 6.0 * TAU
		mb.add(Geo.cyl(0.13, 0.15, h, 6), U.xf(p + Vector3(cos(a) * 0.55, h / 2.0 + 1.0, sin(a) * 0.55)), mat)
	mb.add(Geo.box(1.5, 0.5, 1.5), U.xf(p + Vector3(0, h + 1.2, 0)), mat)
	mb.add(Geo.torus(0.62, 0.1, 16, 4), U.xf(p + Vector3(0, 2.2, 0)), mat)

func _banner_tex() -> ImageTexture:
	var W := 128
	var H := 256
	var img := Image.create(W, H, false, Image.FORMAT_RGBA8)
	var n := Mats.noise(FastNoiseLite.TYPE_SIMPLEX_SMOOTH, 0.05, 4, 77)
	for y in H:
		for x in W:
			var u := float(x) / W
			var v := float(y) / H
			var nv := n.get_noise_2d(x, y * 2) * 0.5 + 0.5
			var fray := v + (n.get_noise_2d(x * 4, 900) * 0.07) + absf(u - 0.5) * 0.12
			var hole := n.get_noise_2d(x * 3 + 500, y * 3) > 0.45
			var a := 0.0 if (fray > 0.93 or hole) else 1.0
			var c := Color(0.28 * (0.6 + nv * 0.7), 0.025 * (0.6 + nv), 0.03 * (0.6 + nv), a)
			var dx := x - 64.0
			var dy := y - 100.0
			var rr := sqrt(dx * dx + dy * dy)
			if a > 0.0 and (absf(rr - 35.0) < 2.2 or (y > 14 and y < 18) or (y > 165 and y < 168)): c = Color(0.78, 0.62, 0.31, 1)
			img.set_pixel(x, y, c)
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)

func _statue() -> void:
	var stone := Mats.std({map = Mats.T.wall_c, nmap = Mats.T.wall_n, color = Color(0.55, 0.5, 0.47), r = 0.9, uv = Vector3(2, 2, 1)})
	var rig = Rig.new({id = "vorgath", scale = 4.3}, stone)
	var p := PZ.P(PZ.guard(), {root = [0, 0.55, 0], hip = [0.15, 0, 0], spine = [0.12, 0, 0], chest = [0.15, 0, 0], neck = [0.35, 0, 0], free = 1, head = [0.25, 0, 0], lf = [0.42, 0.08, -0.2], rf = [-0.42, 0.06, 0.2], lk = [1, 0.3, -0.2], rk = [0, -1, 0.2], lfa = [0, 0, 0], rfa = [0, 0.7, 0], L = [0.6, 1.0, -0.05], R = [0.6, 1.06, 0.05], LE = [0, -1, -1], RE = [0, -1, 1]})
	rig.update(p)
	rig.root.scale = Vector3.ONE * 4.3
	rig.root.position = Vector3(0, 0, -13.2)
	rig.root.rotation = Vector3(0, -PI / 2, 0)
	root.add_child(rig.root)
	for n in Rig.SEGS:
		var mi: MeshInstance3D = rig.seg[n]
		for i in (mi.mesh.get_surface_count() if mi.mesh else 0):
			var m = mi.mesh.surface_get_material(i)
			if m is StandardMaterial3D and m.shading_mode == BaseMaterial3D.SHADING_MODE_UNSHADED:
				mi.set_surface_override_material(i, Mats.glow(Color(1, 0.08, 0.02), 4.0))
	var sw := Geo.MB.new()
	sw.add(Geo.box(0.5, 4.2, 0.1), U.xf(Vector3(0, 2.05, -10.6)), Mats.M.iron)
	sw.add(Geo.box(2.2, 0.22, 0.3), U.xf(Vector3(0, 4.2, -10.6)), Mats.M.iron)
	sw.add(Geo.cyl(0.09, 0.09, 1.0, 8), U.xf(Vector3(0, 4.8, -10.6)), Mats.M.iron)
	sw.add(Geo.ell(0.2, 0.2, 0.2), U.xf(Vector3(0, 5.35, -10.6)), Mats.M.iron)
	var swm := MeshInstance3D.new()
	swm.mesh = sw.build()
	root.add_child(swm)
	var L := OmniLight3D.new()
	L.light_color = Color(1, 0.12, 0.06)
	L.light_energy = 2.0
	L.omni_range = 9.0
	L.position = Vector3(0, 7.6, -11.4)
	root.add_child(L)

func _environment() -> void:
	var we := WorldEnvironment.new()
	env = Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.015, 0.004, 0.008)
	var sky := Sky.new()
	var sm := ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = """shader_type sky;
void sky(){ float y = EYEDIR.y; vec3 top = vec3(0.03, 0.035, 0.06); vec3 hor = vec3(0.22, 0.05, 0.035); vec3 bot = vec3(0.02, 0.01, 0.01);
vec3 c = y > 0.0 ? mix(hor, top, pow(y, 0.5)) : mix(hor, bot, pow(-y, 0.4));
c += vec3(3.0, 1.1, 0.4) * pow(max(0.0, dot(EYEDIR, normalize(vec3(1.0, 0.2, -0.5)))), 40.0);
c += vec3(2.5, 0.8, 0.3) * pow(max(0.0, dot(EYEDIR, normalize(vec3(-1.0, 0.15, -0.3)))), 40.0);
c += vec3(0.25, 0.32, 0.6) * pow(max(0.0, dot(EYEDIR, normalize(vec3(0.0, 1.0, 0.4)))), 12.0);
c += vec3(0.22, 0.12, 0.1) * pow(max(0.0, dot(EYEDIR, normalize(vec3(0.3, 0.3, 1.0)))), 20.0);
COLOR = c; }"""
	sm.shader = sh
	sky.sky_material = sm
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.32
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = 0.95
	env.glow_enabled = true
	env.glow_intensity = 0.9
	env.glow_bloom = 0.08
	env.glow_hdr_threshold = 1.0
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SOFTLIGHT
	env.fog_enabled = true
	env.fog_light_color = Color(0.07, 0.03, 0.035)
	env.fog_density = 0.028
	env.fog_sky_affect = 0.0
	we.environment = env
	root.add_child(we)

func _lights() -> void:
	key = DirectionalLight3D.new()
	key.light_color = Color(1, 0.84, 0.72)
	key.light_energy = 1.05
	key.rotation = Vector3(-0.85, 0.22, 0)
	key.shadow_enabled = true
	key.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	key.directional_shadow_max_distance = 16.0
	key.shadow_bias = 0.05
	key.shadow_normal_bias = 1.5
	root.add_child(key)
	moon = DirectionalLight3D.new()
	moon.light_color = Color(0.6, 0.69, 1.0)
	moon.light_energy = 0.45
	moon.rotation = Vector3(-0.75, PI + 0.4, 0)
	root.add_child(moon)
	var rim := SpotLight3D.new()
	rim.light_color = Color(1, 0.19, 0.09)
	rim.light_energy = 6.0
	rim.spot_range = 30.0
	rim.spot_angle = 40.0
	rim.position = Vector3(-3, 6, -9)
	root.add_child(rim)
	rim.look_at_from_position(rim.position, Vector3(0, 1.2, 0))
	var fill := DirectionalLight3D.new()
	fill.light_color = Color(1, 0.35, 0.23)
	fill.light_energy = 0.25
	fill.rotation = Vector3(-0.3, 0.8, 0)
	root.add_child(fill)

func update(dt: float) -> void:
	t += dt
	for b in braziers:
		var f: float = 0.78 + 0.22 * sin(t * 11.0 + b.seed) * sin(t * 6.7 + b.seed * 2.0) + 0.08 * sin(t * 23.0 + b.seed)
		b.L.light_energy = b.base * f
		b.acc += dt * 22.0 * VFX.quality
		while b.acc > 1.0:
			b.acc -= 1.0
			VFX.fire(b.p + Vector3(randf_range(-0.25, 0.25), 0, randf_range(-0.25, 0.25)), 1.0)
		if randf() < dt * 5.0: VFX.ember(b.p + Vector3(0, 0.3, 0))
	if randf() < dt * 8.0 * VFX.quality: VFX.ember(Vector3(randf_range(-9, 9), randf_range(0, 1), randf_range(-6, 2)))
	if randf() < dt * 4.0 * VFX.quality: VFX.ash(Vector3(randf_range(-8, 8), randf_range(4, 7), randf_range(-5, 3)))
	for c in cages:
		c.g.rotation = Vector3(sin(t * 0.45 + c.ph * 2.0) * 0.03, sin(t * 0.2 + c.ph) * 0.3, sin(t * 0.6 + c.ph) * 0.04)
	for i in banners.size():
		banners[i].rotation = Vector3(sin(t * 0.8 + i) * 0.05, sin(t * 0.5 + i * 2) * 0.06, 0)
	rune_mat.set_shader_parameter("intensity", 0.22 + 0.07 * sin(t * 1.3) + flash * 0.35)
	next_bolt -= dt
	if next_bolt < 0.0:
		next_bolt = randf_range(9.0, 22.0)
		bolt = 0.0
		SFX.play("thunder", 0.7)
	if bolt >= 0.0:
		bolt += dt
		var k := 1.0 if bolt < 0.08 else (0.2 if bolt < 0.16 else (0.8 if bolt < 0.26 else maxf(0.0, 1.0 - (bolt - 0.26) * 3.0)))
		moon.light_energy = 0.45 + k * 4.0
		glass_mat.set_shader_parameter("energy", 2.4 + k * 3.0)
		if bolt > 1.0: bolt = -1.0
	flash = maxf(0.0, flash - dt * 2.0)
