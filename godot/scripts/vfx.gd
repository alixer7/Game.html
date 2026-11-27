extends Node
## GPU-driven visual effects (autoload "VFX").
## Particles and blood drops store their launch data in MultiMesh instance slots;
## shaders evaluate motion from a single time uniform, so per-frame CPU cost is ~zero.

const Geo = preload("res://scripts/geo.gd")

const PART_SHADER := """shader_type spatial;
render_mode unshaded, %s, depth_draw_never, cull_disabled, skip_vertex_transform, shadows_disabled;
uniform sampler2D tex : source_color, filter_linear_mipmap;
uniform float now;
varying vec4 col;
void vertex(){
	vec3 p0 = MODEL_MATRIX[3].xyz; vec3 v0 = MODEL_MATRIX[0].xyz;
	float g = MODEL_MATRIX[1].x; float k = MODEL_MATRIX[1].y; float t0 = MODEL_MATRIX[1].z;
	float life = MODEL_MATRIX[2].x; float s0 = MODEL_MATRIX[2].y; float s1 = MODEL_MATRIX[2].z;
	float age = now - t0; float u = age / max(life, 0.001);
	float alive = step(0.0, age) * step(u, 1.0);
	float dk = k > 0.001 ? (1.0 - exp(-k * age)) / k : age;
	vec3 wp = p0 + v0 * dk; wp.y -= 0.5 * g * age * age;
	float sz = mix(s0, s1, u) * alive;
	float h1 = fract(sin(float(INSTANCE_ID) * 12.9898) * 43758.5453);
	float h2 = fract(sin(float(INSTANCE_ID) * 78.233) * 12345.678);
	float rot = h1 * 6.2832 + (h2 - 0.5) * 2.0 * age;
	vec2 c = VERTEX.xy; c = vec2(cos(rot) * c.x - sin(rot) * c.y, sin(rot) * c.x + cos(rot) * c.y);
	vec4 vp = VIEW_MATRIX * vec4(wp, 1.0);
	vp.xy += c * sz;
	VERTEX = vp.xyz;
	col = mix(COLOR, INSTANCE_CUSTOM, clamp(u, 0.0, 1.0));
	col.a *= min(1.0, u * 8.0) * alive;
}
void fragment(){ float a = texture(tex, UV).a * col.a; if (a < 0.004) { discard; } ALBEDO = col.rgb; ALPHA = a; }
"""

const DROP_SHADER := """shader_type spatial;
render_mode skip_vertex_transform, specular_schlick_ggx;
uniform float now;
void vertex(){
	vec3 p0 = MODEL_MATRIX[3].xyz; vec3 v0 = MODEL_MATRIX[0].xyz; float t0 = MODEL_MATRIX[1].z;
	float life = MODEL_MATRIX[2].x; float r = MODEL_MATRIX[2].y;
	float age = now - t0; float alive = step(0.0, age) * step(age, life);
	vec3 vel = v0 - vec3(0.0, 9.8 * age, 0.0);
	vec3 wp = p0 + v0 * age - vec3(0.0, 4.9 * age * age, 0.0);
	float sp = length(vel); vec3 d = sp > 0.001 ? vel / sp : vec3(0.0, 1.0, 0.0);
	vec3 ax = normalize(cross(d, abs(d.y) < 0.9 ? vec3(0.0, 1.0, 0.0) : vec3(1.0, 0.0, 0.0))); vec3 az = cross(ax, d);
	vec3 lp = (ax * VERTEX.x * r + d * VERTEX.y * r * (1.0 + sp * 0.12) + az * VERTEX.z * r) * alive;
	VERTEX = (VIEW_MATRIX * vec4(wp + lp, 1.0)).xyz;
	NORMAL = normalize((VIEW_MATRIX * vec4(ax * NORMAL.x + d * NORMAL.y + az * NORMAL.z, 0.0)).xyz);
}
void fragment(){ ALBEDO = vec3(0.16, 0.0, 0.01); ROUGHNESS = 0.12; SPECULAR = 0.75; }
"""

var root: Node3D
var now := 0.0
var pools := {}
var drop_mm: MultiMesh
var drop_mat: ShaderMaterial
var drop_i := 0
const DROP_N := 700
var decal_mm: MultiMesh
var decal_mat: ShaderMaterial
var decal_i := 0
const DECAL_N := 260
var events := []
var gibs := []
var fountains := []
var rings := []
var spikes := []
var mfx := []
var fl: OmniLight3D
var light_decay := 6.0
var gib_meshes := []
var quality := 1.0

class Pool extends RefCounted:
	var mm: MultiMesh
	var mat: ShaderMaterial
	var n: int
	var i := 0
	func _init(parent: Node, count: int, tex: Texture2D, additive: bool) -> void:
		var sh := Shader.new()
		sh.code = PART_SHADER % ("blend_add" if additive else "blend_mix")
		mat = ShaderMaterial.new()
		mat.shader = sh
		mat.set_shader_parameter("tex", tex)
		mm = MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = true
		mm.use_custom_data = true
		var q := QuadMesh.new()
		q.size = Vector2(1, 1)
		mm.mesh = q
		mm.instance_count = count
		mm.custom_aabb = AABB(Vector3(-60, -20, -60), Vector3(120, 60, 120))
		n = count
		var dead := Transform3D(Basis(Vector3.ZERO, Vector3(0, 0, -9999), Vector3(0.001, 0, 0)), Vector3.ZERO)
		for k in count:
			mm.set_instance_transform(k, dead)
			mm.set_instance_color(k, Color(0, 0, 0, 0))
			mm.set_instance_custom_data(k, Color(0, 0, 0, 0))
		var mi := MultiMeshInstance3D.new()
		mi.multimesh = mm
		mi.material_override = mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		parent.add_child(mi)

	func spawn(p: Vector3, v: Vector3, g: float, drag: float, life: float, s0: float, s1: float, c0: Color, c1: Color, t: float) -> void:
		mm.set_instance_transform(i, Transform3D(Basis(v, Vector3(g, drag, t), Vector3(life, s0, s1)), p))
		mm.set_instance_color(i, c0)
		mm.set_instance_custom_data(i, c1)
		i = (i + 1) % n

func setup(parent: Node3D) -> void:
	root = Node3D.new()
	root.name = "VFX"
	parent.add_child(root)
	pools.glow = Pool.new(root, 700, Mats.T.glow, true)
	pools.flame = Pool.new(root, 900, Mats.T.flame, true)
	pools.spark = Pool.new(root, 700, Mats.T.spark, true)
	pools.smoke = Pool.new(root, 600, Mats.T.smoke, false)
	pools.dot = Pool.new(root, 600, Mats.T.spark, false)
	# blood drops
	var dsh := Shader.new()
	dsh.code = DROP_SHADER
	drop_mat = ShaderMaterial.new()
	drop_mat.shader = dsh
	drop_mm = MultiMesh.new()
	drop_mm.transform_format = MultiMesh.TRANSFORM_3D
	var sm := SphereMesh.new()
	sm.radius = 1.0; sm.height = 2.0; sm.radial_segments = 6; sm.rings = 3
	drop_mm.mesh = sm
	drop_mm.instance_count = DROP_N
	drop_mm.custom_aabb = AABB(Vector3(-60, -20, -60), Vector3(120, 60, 120))
	for k in DROP_N: drop_mm.set_instance_transform(k, Transform3D(Basis(Vector3.ZERO, Vector3(0, 0, -9999), Vector3.ZERO), Vector3.ZERO))
	var dmi := MultiMeshInstance3D.new()
	dmi.multimesh = drop_mm
	dmi.material_override = drop_mat
	dmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(dmi)
	# floor decals
	decal_mat = ShaderMaterial.new()
	var dc := Shader.new()
	dc.code = Mats.S.decal.code.replace("void vertex(){ seed = INSTANCE_CUSTOM.x * 10.0; }", "uniform float now;\nvoid vertex(){ seed = INSTANCE_CUSTOM.x * 10.0; float g = clamp((now - INSTANCE_CUSTOM.y) / max(INSTANCE_CUSTOM.z, 0.01), 0.0, 1.0); g = 1.0 - pow(1.0 - g, 3.0); VERTEX.xz *= g; }")
	decal_mat.shader = dc
	decal_mm = MultiMesh.new()
	decal_mm.transform_format = MultiMesh.TRANSFORM_3D
	decal_mm.use_custom_data = true
	var pm := PlaneMesh.new()
	pm.size = Vector2(1, 1)
	decal_mm.mesh = pm
	decal_mm.instance_count = DECAL_N
	decal_mm.custom_aabb = AABB(Vector3(-60, -2, -60), Vector3(120, 4, 120))
	for k in DECAL_N: decal_mm.set_instance_transform(k, Transform3D(Basis().scaled(Vector3.ONE * 0.0001), Vector3(0, -5, 0)))
	var cmi := MultiMeshInstance3D.new()
	cmi.multimesh = decal_mm
	cmi.material_override = decal_mat
	cmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(cmi)
	# shockwave rings
	for k in 12:
		var mi := MeshInstance3D.new()
		var qm := QuadMesh.new()
		qm.size = Vector2(1, 1)
		mi.mesh = qm
		mi.material_override = Mats.smat("ring")
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.visible = false
		root.add_child(mi)
		rings.append({mi = mi, t = 1.0, d = 1.0, size = 1.0, mode = "face", a = 1.0})
	fl = OmniLight3D.new()
	fl.light_energy = 0.0
	fl.omni_range = 9.0
	root.add_child(fl)
	for k in 4:
		var g := Geo.ell(1, 1, 1, 7, 5)
		var vv: PackedVector3Array = g.v
		for i in vv.size(): vv[i] *= randf_range(0.7, 1.3) * Vector3(1, 2.2 if k == 3 else 1.0, 1)
		g.v = vv
		var mb := Geo.MB.new()
		mb.add(g, Transform3D(), Mats.M.flesh)
		gib_meshes.append(mb.build())

func clear() -> void:
	now += 100.0  # every GPU particle/drop/decal becomes dead
	for k in DECAL_N: decal_mm.set_instance_transform(k, Transform3D(Basis().scaled(Vector3.ONE * 0.0001), Vector3(0, -5, 0)))
	events.clear()
	for gb in gibs:
		if is_instance_valid(gb.node): gb.node.queue_free()
	gibs.clear()
	fountains.clear()
	for s in spikes:
		if is_instance_valid(s.mi): s.mi.queue_free()
	spikes.clear()
	for m in mfx:
		if is_instance_valid(m.node): m.node.queue_free()
	mfx.clear()
	for r in rings: r.mi.visible = false
	fl.light_energy = 0.0

# ----------------------------------------------------------------- particle API
func _p(pool: String, p: Vector3, v: Vector3, g: float, drag: float, life: float, s0: float, s1: float, c0: Color, c1: Color) -> void:
	pools[pool].spawn(p, v, g, drag, life, s0, s1, c0, c1, now)

func fire(p: Vector3, s := 1.0, vel := Vector3.ZERO, life := 1.0) -> void:
	_p("flame", p, vel + Vector3(randf_range(-0.15, 0.15), randf_range(0.6, 1.4) * s, randf_range(-0.15, 0.15)), -1.2, 1.8, randf_range(0.35, 0.7) * life, randf_range(0.15, 0.3) * s, 0.04 * s, Color(4, 1.5, 0.35, 1), Color(1.6, 0.2, 0.02, 0))
	if randf() < 0.2:
		_p("smoke", p + Vector3(0, 0.3 * s, 0), Vector3(randf_range(-0.1, 0.1), randf_range(0.4, 0.9), randf_range(-0.1, 0.1)), 0.0, 1.0, randf_range(0.8, 1.6), 0.2 * s, 0.7 * s, Color(0.05, 0.03, 0.03, 0.35), Color(0.02, 0.02, 0.02, 0))

func ember(p: Vector3) -> void:
	_p("spark", p, Vector3(randf_range(-0.3, 0.3), randf_range(0.3, 1.2), randf_range(-0.3, 0.3)), -0.08, 0.3, randf_range(1.5, 4.0), randf_range(0.012, 0.03), 0.004, Color(5, 1.6, 0.3, 1), Color(2, 0.3, 0, 1))

func ash(p: Vector3) -> void:
	_p("dot", p, Vector3(randf_range(-0.15, 0.15), randf_range(-0.25, -0.1), randf_range(-0.1, 0.1)), 0.0, 0.0, randf_range(4, 8), randf_range(0.012, 0.025), 0.01, Color(0.5, 0.48, 0.45, 0.7), Color(0.3, 0.3, 0.3, 0))

func smoke(p: Vector3, s := 1.0, c := Color(0.05, 0.04, 0.04, 0.5)) -> void:
	_p("smoke", p, Vector3(randf_range(-0.3, 0.3) * s, randf_range(0.1, 0.6) * s, randf_range(-0.3, 0.3) * s), 0.0, 2.4, randf_range(0.8, 1.8), 0.25 * s, 1.0 * s, c, Color(c.r * 0.5, c.g * 0.5, c.b * 0.5, 0))

func dust(p: Vector3, n := 8, s := 1.0) -> void:
	for i in n:
		var a := randf() * TAU
		_p("smoke", Vector3(p.x, 0.05, p.z), Vector3(cos(a) * randf_range(0.5, 2.0) * s, randf_range(0.1, 0.6), sin(a) * randf_range(0.3, 1.0) * s), 0.0, 5.0, randf_range(0.5, 1.1), 0.15 * s, 0.6 * s, Color(0.16, 0.13, 0.12, 0.45), Color(0.1, 0.08, 0.08, 0))

func wisp(p: Vector3, v := Vector3.ZERO, s := 1.0) -> void:
	_p("glow", p, v + Vector3(randf_range(-0.2, 0.2), randf_range(0.1, 0.5), randf_range(-0.2, 0.2)), 0.0, 1.8, randf_range(0.4, 1.0), randf_range(0.06, 0.12) * s, 0.01, Color(0.5, 1.3, 2, 0.8), Color(0.1, 0.2, 0.6, 0))

func glow(p: Vector3, c: Color, size: float, life := 0.06) -> void:
	_p("glow", p, Vector3.ZERO, 0.0, 0.0, life, size, size * 0.9, c, Color(c.r, c.g, c.b, 0))

func plague(p: Vector3, s := 1.0) -> void:
	_p("glow", p, Vector3(randf_range(-0.25, 0.25) * s, randf_range(-0.05, 0.4) * s, randf_range(-0.25, 0.25) * s), 0.0, 1.8, randf_range(0.6, 1.3), 0.1 * s, 0.35 * s, Color(0.5, 1.6, 0.2, 0.45), Color(0.1, 0.4, 0, 0))

func miasma(p: Vector3, s := 1.0) -> void:
	_p("smoke", p + Vector3(randf_range(-0.3, 0.3) * s, 0, randf_range(-0.3, 0.3) * s), Vector3(randf_range(-0.2, 0.2), randf_range(0.02, 0.2), randf_range(-0.2, 0.2)), 0.0, 1.2, randf_range(1.2, 2.4), 0.3 * s, 0.9 * s, Color(0.12, 0.22, 0.05, 0.3), Color(0.05, 0.1, 0.02, 0))

func fly(c: Vector3, r := 0.6) -> void:
	var p := c + Vector3(randf_range(-r, r), randf_range(-r, r) * 0.6, randf_range(-r, r) * 0.6)
	_p("dot", p, Vector3(randf_range(-3, 3), randf_range(-2, 2), randf_range(-3, 3)), 0.0, 4.0, randf_range(0.3, 0.7), 0.022, 0.018, Color(0.01, 0.01, 0.0, 1), Color(0.01, 0.01, 0, 1))

func spark(p: Vector3, n: int, c := Color(4, 2.4, 0.8), dirx := 0.0) -> void:
	for i in n:
		var a := randf() * TAU
		var sp := randf_range(2.0, 8.0)
		_p("spark", p, Vector3(cos(a) * sp + dirx * 3.0, sin(a) * sp + 1.0, randf_range(-3, 3)), 9.0, 3.5, randf_range(0.15, 0.45), randf_range(0.03, 0.07), 0.005, c, Color(c.r * 0.5, c.g * 0.2, 0, 1))

func flash(p: Vector3, c: Color, size := 1.2, life := 0.14) -> void:
	_p("glow", p, Vector3.ZERO, 0.0, 0.0, life, size * 0.4, size, Color(c.r, c.g, c.b, 1), Color(c.r * 0.3, c.g * 0.1, 0, 0))

func ring(p: Vector3, c: Color, size := 2.0, dur := 0.35, mode := "face", a := 1.0) -> void:
	var r: Dictionary = rings[0]
	for x in rings:
		if x.t >= x.d:
			r = x
			break
	r.t = 0.0; r.d = dur; r.size = size; r.mode = mode; r.a = a
	r.mi.visible = true
	r.mi.position = p
	r.mi.material_override.set_shader_parameter("col", Color(c.r, c.g, c.b, a))
	if mode == "ground": r.mi.rotation = Vector3(-PI / 2, 0, 0)
	elif mode == "side": r.mi.rotation = Vector3(0, PI / 2, 0)

func light_at(p: Vector3, c: Color, energy: float, decay := 6.0) -> void:
	fl.position = p
	fl.light_color = c
	fl.light_energy = maxf(fl.light_energy, energy)
	light_decay = decay


# ----------------------------------------------------------------- blood
func drop(p: Vector3, v: Vector3, r: float, dec := 0.55) -> void:
	var g := 9.8
	var t_land := (v.y + sqrt(maxf(0.0, v.y * v.y + 2.0 * g * maxf(0.0, p.y - r * 0.5)))) / g
	drop_mm.set_instance_transform(drop_i, Transform3D(Basis(v, Vector3(0, 0, now), Vector3(t_land, r, 0)), p))
	drop_i = (drop_i + 1) % DROP_N
	var lx := p.x + v.x * t_land
	var lz := p.z + v.z * t_land
	if absf(lx) < 25.0 and lz > -4.8 and lz < 8.0:
		events.append([now + t_land, "land", Vector3(lx, 0, lz), r, dec])

func blood(p: Vector3, dirx: float, n: int, o := {}) -> void:
	var sp: float = o.get("speed", 3.2)
	var spread: float = o.get("spread", 0.6)
	var up: float = o.get("up", 1.1)
	var size: float = o.get("size", 0.016)
	var dec: float = o.get("dec", 0.55)
	var add: Vector3 = o.get("vel", Vector3.ZERO)
	n = roundi(n * quality)
	for i in n:
		var v := sp * (0.35 + randf() * 0.9)
		drop(p + Vector3(randf_range(-0.04, 0.04), randf_range(-0.04, 0.04), randf_range(-0.04, 0.04)), Vector3(dirx * v + randf_range(-spread, spread) * v * 0.5, up * v * (0.3 + randf() * 0.9), randf_range(-spread, spread) * v * 0.7) + add, size * (0.4 + randf() * 1.2), dec)
	if o.get("mist", true):
		for i in mini(12, n / 3):
			_p("smoke", p, Vector3(dirx * randf_range(0.3, 1.6) + randf_range(-0.4, 0.4), randf_range(-0.2, 0.9), randf_range(-0.5, 0.5)), 0.6, 1.5, randf_range(0.4, 0.9), randf_range(0.06, 0.14), randf_range(0.3, 0.6), Color(0.22, 0.0, 0.01, 0.65), Color(0.12, 0, 0, 0))

func decal(x: float, z: float, s: float, grow := -1.0) -> void:
	var y := 0.004 + (decal_i % 40) * 0.0004
	decal_mm.set_instance_transform(decal_i, Transform3D(Basis(Vector3.UP, randf() * TAU).scaled(Vector3(s, 1, s)), Vector3(x, y, z)))
	decal_mm.set_instance_custom_data(decal_i, Color(randf(), now, grow if grow > 0.0 else (2.0 if s > 1.0 else 0.28), 0))
	decal_i = (decal_i + 1) % DECAL_N

func fountain(pos_fn: Callable, dir_fn: Callable, dur: float, rate := 120.0, o := {}) -> void:
	fountains.append({pos = pos_fn, dir = dir_fn, t = 0.0, dur = dur, rate = rate * quality, acc = 0.0, o = o})

func gib(p: Vector3, v: Vector3, size := 0.06, mat: Material = null) -> void:
	var b := RigidBody3D.new()
	var mi := MeshInstance3D.new()
	mi.mesh = gib_meshes[randi() % gib_meshes.size()]
	if mat: mi.material_override = mat
	mi.scale = Vector3.ONE * size
	b.add_child(mi)
	var cs := CollisionShape3D.new()
	var sh := SphereShape3D.new()
	sh.radius = size
	cs.shape = sh
	b.add_child(cs)
	b.mass = 0.3
	b.linear_velocity = v
	b.angular_velocity = Vector3(randf_range(-12, 12), randf_range(-12, 12), randf_range(-12, 12))
	b.collision_layer = 2
	b.collision_mask = 1
	root.add_child(b)
	b.global_position = p
	gibs.append({node = b, life = 14.0, bleed = 1.0})
	if gibs.size() > 70:
		var old = gibs.pop_front()
		if is_instance_valid(old.node): old.node.queue_free()

## turn already-detached body part nodes into a physics body
func sever(nodes: Array, v: Vector3, w: Vector3, r := 0.07, bleed := 3.0) -> RigidBody3D:
	var c := Vector3.ZERO
	for n in nodes: c += n.global_position
	c /= nodes.size()
	var b := RigidBody3D.new()
	root.add_child(b)
	b.global_position = c
	for n in nodes:
		var gt: Transform3D = n.global_transform
		n.get_parent().remove_child(n)
		b.add_child(n)
		n.global_transform = gt
	var cs := CollisionShape3D.new()
	var sh := CapsuleShape3D.new()
	sh.radius = r
	sh.height = maxf(r * 2.0, 0.25)
	cs.shape = sh
	b.add_child(cs)
	b.mass = 2.0
	b.linear_velocity = v
	b.angular_velocity = w
	b.collision_layer = 2
	b.collision_mask = 1
	gibs.append({node = b, life = 1e9, bleed = bleed})
	return b

func spike(x: float, z: float, h: float, o := {}) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.0
	cm.bottom_radius = o.get("r", 0.12)
	cm.height = 1.0
	cm.radial_segments = 7
	cm.rings = 2
	mi.mesh = cm
	mi.material_override = o.get("mat", Mats.M.flesh)
	root.add_child(mi)
	var rx: float = o.get("rx", randf_range(-0.15, 0.15))
	var rz: float = o.get("rz", randf_range(-0.15, 0.15))
	mi.rotation = Vector3(rx, randf() * TAU, rz)
	mi.position = Vector3(x, -0.05, z)
	spikes.append({mi = mi, h = h, t = 0.0, grow = o.get("grow", 0.12), life = o.get("life", 1.2), sink = 0.4, x = x, z = z})
	for i in 8: blood(Vector3(x, 0.1, z), randf_range(-1, 1), 3, {speed = 4.0, up = 1.6, mist = i < 2})
	return mi

func mesh_fx(node: Node3D, life: float, fn: Callable) -> void:
	root.add_child(node)
	mfx.append({node = node, t = 0.0, life = life, fn = fn})

func screen_blood(n := 6, big := 1.0) -> void:
	if G.ui: G.ui.screen_blood(n, big)

# ----------------------------------------------------------------- update
func update(dt: float) -> void:
	now += dt
	for k in pools: pools[k].mat.set_shader_parameter("now", now)
	drop_mat.set_shader_parameter("now", now)
	decal_mat.set_shader_parameter("now", now)
	# landing events (decals + splashes)
	if events.size() > 0:
		var keep := []
		for e in events:
			if e[0] <= now:
				var p: Vector3 = e[2]
				if randf() < e[4]: decal(p.x, p.z, e[3] * randf_range(5.0, 11.0))
				if e[3] > 0.012 and randf() < 0.25:
					for j in 2: _p("dot", p + Vector3(0, 0.02, 0), Vector3(randf_range(-0.6, 0.6), randf_range(0.5, 1.4), randf_range(-0.6, 0.6)), 9.0, 0.0, 0.35, 0.015, 0.006, Color(0.25, 0, 0.01, 1), Color(0.2, 0, 0, 1))
			else:
				keep.append(e)
		events = keep
	# gibs / severed parts
	for i in range(gibs.size() - 1, -1, -1):
		var gb: Dictionary = gibs[i]
		if not is_instance_valid(gb.node):
			gibs.remove_at(i)
			continue
		gb.life -= dt
		var b: RigidBody3D = gb.node
		if gb.life < 0.0:
			b.queue_free()
			gibs.remove_at(i)
			continue
		if gb.bleed > 0.0 and b.linear_velocity.length() > 1.0:
			gb.bleed -= dt * 0.3
			if randf() < 0.5: drop(b.global_position, b.linear_velocity * 0.2 + Vector3(randf_range(-0.3, 0.3), 0, randf_range(-0.3, 0.3)), 0.004 + randf() * 0.01, 0.8)
	# fountains
	for i in range(fountains.size() - 1, -1, -1):
		var f: Dictionary = fountains[i]
		f.t += dt
		if f.t > f.dur:
			fountains.remove_at(i)
			continue
		var k2: float = 1.0 - f.t / f.dur
		f.acc += f.rate * dt * (0.4 + 0.6 * k2) * (0.6 + 0.4 * absf(sin(f.t * 9.0)))
		var p: Vector3 = f.pos.call()
		var d: Vector3 = f.dir.call()
		while f.acc > 1.0:
			f.acc -= 1.0
			var v: float = f.o.get("speed", 3.5) * (0.5 + randf() * 0.7) * (0.5 + 0.5 * k2)
			drop(p, d * v + Vector3(randf_range(-0.4, 0.4), randf_range(-0.3, 0.3), randf_range(-0.4, 0.4)), f.o.get("size", 0.014) * (0.5 + randf()), 0.45)
	# rings
	for r in rings:
		if r.t >= r.d:
			r.mi.visible = false
			continue
		r.t += dt
		var u := minf(1.0, r.t / r.d)
		r.mi.scale = Vector3.ONE * r.size * (0.15 + (1.0 - pow(1.0 - u, 3.0)))
		var c: Color = r.mi.material_override.get_shader_parameter("col")
		c.a = (1.0 - u) * r.a
		r.mi.material_override.set_shader_parameter("col", c)
		if r.mode == "face" and G.camera:
			r.mi.global_transform.basis = G.camera.global_transform.basis.scaled(Vector3.ONE * r.size * (0.15 + (1.0 - pow(1.0 - u, 3.0))))
	# spikes
	for i in range(spikes.size() - 1, -1, -1):
		var s: Dictionary = spikes[i]
		s.t += dt
		var gk: float = minf(1.0, s.t / s.grow)
		var hh: float = s.h * (1.0 + 2.70158 * pow(gk - 1.0, 3.0) + 1.70158 * pow(gk - 1.0, 2.0))
		if s.t > s.life: hh *= maxf(0.0, 1.0 - (s.t - s.life) / s.sink)
		hh = maxf(0.01, hh)
		var bs: Basis = s.mi.transform.basis.orthonormalized()
		s.mi.transform = Transform3D(bs * Basis.from_scale(Vector3(1, hh, 1)), Vector3(s.x, 0, s.z) + bs.y * hh * 0.5 - Vector3(0, 0.05, 0))
		if s.t > s.life + s.sink:
			s.mi.queue_free()
			spikes.remove_at(i)
	for i in range(mfx.size() - 1, -1, -1):
		var m: Dictionary = mfx[i]
		m.t += dt
		if is_instance_valid(m.node): m.fn.call(m.node, m.t / m.life, dt)
		if m.t >= m.life:
			if is_instance_valid(m.node): m.node.queue_free()
			mfx.remove_at(i)
	if fl.light_energy > 0.0:
		fl.light_energy = maxf(0.0, fl.light_energy - fl.light_energy * light_decay * dt - dt * 2.0)
