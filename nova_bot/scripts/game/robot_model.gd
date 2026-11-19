class_name RobotModel
extends Node3D
## "Nova": chibi explorer robot built from bevelled procedural meshes and animated in code.
## Every joint is driven by a damped spring toward a target pose, so motion has weight, overshoot and
## follow-through (punches snap and settle, the antenna wobbles, the head lags, landings squash).
## The owner (Player / menu / rescue bot) only sets the public state below; the model figures out the pose.
## Forward is -Z. Origin is at the feet.

# ------------------------------------------------------------------ public state
var speed_ratio: float = 0.0
var grounded: bool = true
var vy: float = 0.0
var velocity := Vector3.ZERO
var spinning: bool = false
var spin_big: bool = false
var hovering: bool = false
var dashing: bool = false
var charging: float = 0.0
var punch: int = 0
var punch_t: float = 0.0
var flicker: bool = false
var wave: bool = false
var shown: bool = true
var low_power: float = 0.0
var battery_level: float = 1.0
var battery_blink: bool = false
var celebrate: bool = false
var pose_override: String = ""
var accent: Color = Color(0.25, 0.9, 1.0)
var look_yaw: float = 0.0

# ------------------------------------------------------------------ parts
var _flip: Node3D
var _root: Node3D
var _pelvis: Node3D
var _chest: Node3D
var _head: Node3D
var _ant: Node3D
var _sh: Array = []
var _el: Array = []
var _hip: Array = []
var _kn: Array = []
var _fist: Array = []
var _boot: Array = []
var _jets: Array = []
var _jet_ps: Array = []
var _spin_ring: MeshInstance3D
var _face: ShaderMaterial
var _bat_holder: Node3D
var _bat: MeshInstance3D = null
var _bat_mat: ShaderMaterial = null
var _clamps: Array = []
var _chest_light: StandardMaterial3D
var _trails: Array = []
var _built: bool = false

# ------------------------------------------------------------------ springs
var _s_pel_pos := Spring.new()
var _s_pel_rot := Spring.new()
var _s_chest := Spring.new()
var _s_head := Spring.new()
var _s_ant := Spring.new()
var _s_sh: Array = [Spring.new(), Spring.new()]
var _s_el: Array = [Spring.new(), Spring.new()]
var _s_hip: Array = [Spring.new(), Spring.new()]
var _s_kn: Array = [Spring.new(), Spring.new()]
var _sq: float = 0.0
var _sq_v: float = 0.0
var _clamp_open: float = 0.0
var _clamp_target: float = 0.0

# targets (written by _pose)
var _t_pel_pos := Vector3(0.0, 0.4, 0.0)
var _t_pel_rot := Vector3.ZERO
var _t_chest := Vector3.ZERO
var _t_head := Vector3.ZERO
var _t_sh: Array = [Vector3.ZERO, Vector3.ZERO]
var _t_el: Array = [Vector3.ZERO, Vector3.ZERO]
var _t_hip: Array = [Vector3.ZERO, Vector3.ZERO]
var _t_kn: Array = [Vector3.ZERO, Vector3.ZERO]
var _k_body: float = 220.0
var _k_arm: float = 260.0
var _k_leg: float = 320.0
var _z_arm: float = 0.55

var _t: float = 0.0
var _phase: float = 0.0
var _blink: float = 2.5
var _blink_k: float = 1.0
var _flip_t: float = -1.0
var _flip_dir: float = 1.0
var _spin_angle: float = 0.0
var _hurt: float = 0.0
var _mood_t: float = 0.0
var _mood: int = -1
var _prev_vel := Vector3.ZERO
var _acc_local := Vector3.ZERO
var _prev_yaw: float = 0.0
var _turn_rate: float = 0.0
var _idle_t: float = 0.0
var _look_t: float = 2.0
var _look_target := Vector2.ZERO
var _was_grounded: bool = true
var _air_vy: float = 0.0

const PELVIS_Y := 0.4


class Spring:
	var x := Vector3.ZERO
	var v := Vector3.ZERO

	func step(target: Vector3, k: float, zeta: float, dt: float) -> Vector3:
		var c: float = 2.0 * sqrt(k) * zeta
		v += ((target - x) * k - v * c) * dt
		x += v * dt
		return x

	func snap(target: Vector3) -> void:
		x = target
		v = Vector3.ZERO


static func make(col: Color = Color(0.25, 0.9, 1.0)) -> RobotModel:
	var m := RobotModel.new()
	m.accent = col
	m._build()
	return m


func _ready() -> void:
	if not _built:
		_build()


# ================================================================== build
func _build() -> void:
	_built = true
	scale = Vector3.ONE * 0.8
	var white: Material = Mats.plastic(Color(0.94, 0.95, 0.97), 0.26)
	var shade: Material = Mats.plastic(Color(0.8, 0.84, 0.9), 0.32)
	var joint: Material = Mats.metal(Color(0.16, 0.18, 0.24), 0.32, 0.6)
	var dark: Material = Mats.metal(Color(0.07, 0.08, 0.11), 0.3, 0.5)
	var glow: Material = Mats.glow(accent, 2.8)
	var orange: Material = Mats.plastic(Color(1.0, 0.52, 0.12), 0.3, Color(1.0, 0.45, 0.1), 0.35)

	_flip = Node3D.new()
	_flip.position = Vector3(0.0, 0.72, 0.0)
	add_child(_flip)
	_root = Node3D.new()
	_root.position = Vector3(0.0, -0.72, 0.0)
	_flip.add_child(_root)

	_pelvis = Node3D.new()
	_pelvis.position = Vector3(0.0, PELVIS_Y, 0.0)
	_root.add_child(_pelvis)
	Geo.put(_pelvis, Geo.rounded_box(Vector3(0.32, 0.14, 0.26), 0.06, 2), joint, Vector3(0.0, 0.0, 0.0))

	_chest = Node3D.new()
	_chest.position = Vector3(0.0, 0.05, 0.0)
	_pelvis.add_child(_chest)
	Geo.put(_chest, Geo.rounded_box(Vector3(0.46, 0.38, 0.36), 0.14, 3), white, Vector3(0.0, 0.2, 0.0))
	Geo.put(_chest, Geo.rounded_box(Vector3(0.48, 0.05, 0.38), 0.025, 2), dark, Vector3(0.0, 0.04, 0.0))
	# chest emblem: glowing core in a dark bezel + orange chevron
	Geo.put(_chest, Geo.cyl(0.085, 0.085, 0.03, 24), dark, Vector3(0.0, 0.22, -0.178), Vector3(90.0, 0.0, 0.0))
	_chest_light = StandardMaterial3D.new()
	_chest_light.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_chest_light.albedo_color = Color(accent.r * 2.6, accent.g * 2.6, accent.b * 2.6)
	Geo.put(_chest, Geo.cyl(0.058, 0.058, 0.035, 24), _chest_light, Vector3(0.0, 0.22, -0.186), Vector3(90.0, 0.0, 0.0), Vector3.ONE, false)
	Geo.put(_chest, Geo.rounded_box(Vector3(0.2, 0.035, 0.03), 0.012, 2), orange, Vector3(-0.1, 0.33, -0.168), Vector3(0.0, 0.0, -18.0))
	Geo.put(_chest, Geo.rounded_box(Vector3(0.2, 0.035, 0.03), 0.012, 2), orange, Vector3(0.1, 0.33, -0.168), Vector3(0.0, 0.0, 18.0))
	Geo.put(_chest, Geo.cyl(0.1, 0.12, 0.06, 20), joint, Vector3(0.0, 0.41, 0.0))
	_build_backpack(dark, joint)

	# ---- head
	_head = Node3D.new()
	_head.position = Vector3(0.0, 0.43, 0.0)
	_chest.add_child(_head)
	Geo.put(_head, Geo.rounded_box(Vector3(0.72, 0.56, 0.62), 0.22, 4), white, Vector3(0.0, 0.27, 0.0))
	Geo.put(_head, Geo.rounded_box(Vector3(0.62, 0.4, 0.06), 0.06, 3), dark, Vector3(0.0, 0.26, -0.29))
	_face = Mats.face()
	_face.set_shader_parameter("eye_color", accent.lerp(Color(1, 1, 1), 0.15))
	_face.set_shader_parameter("aspect", 1.62)
	Geo.put(_head, Geo.curved_panel(0.58, 0.36, 0.035, 0.02, 14), _face, Vector3(0.0, 0.26, -0.318))
	for s in [-1.0, 1.0]:
		var sx: float = s
		var ear := Node3D.new()
		ear.position = Vector3(0.365 * sx, 0.26, 0.02)
		ear.rotation_degrees = Vector3(0.0, 0.0, -90.0 * sx)
		_head.add_child(ear)
		Geo.put(ear, Geo.cyl(0.13, 0.145, 0.07, 28), shade, Vector3(0.0, 0.0, 0.0))
		Geo.put(ear, Geo.torus(0.075, 0.1, 28, 6), glow, Vector3(0.0, 0.04, 0.0), Vector3.ZERO, Vector3.ONE, false)
		Geo.put(ear, Geo.cyl(0.06, 0.07, 0.04, 20), joint, Vector3(0.0, 0.045, 0.0))
	# antenna (springy)
	_ant = Node3D.new()
	_ant.position = Vector3(0.14, 0.54, 0.06)
	_head.add_child(_ant)
	Geo.put(_ant, Geo.cyl(0.03, 0.04, 0.03, 12), joint, Vector3(0.0, 0.0, 0.0))
	Geo.put(_ant, Geo.cyl(0.011, 0.014, 0.24, 8), joint, Vector3(0.0, 0.12, 0.0))
	Geo.put(_ant, Geo.sphere(0.045, 14), Mats.glow(Color(1.0, 0.6, 0.2), 3.0), Vector3(0.0, 0.26, 0.0), Vector3.ZERO, Vector3.ONE, false)

	# ---- arms
	for i in range(2):
		var sx2: float = -1.0 if i == 0 else 1.0
		var sh := Node3D.new()
		sh.position = Vector3(0.275 * sx2, 0.29, 0.0)
		_chest.add_child(sh)
		Geo.put(sh, Geo.sphere(0.08, 16), joint)
		Geo.put(sh, Geo.lathe(Geo.pill_profile(0.064, 0.2, 0.06), 16, "upperarm"), white, Vector3(0.0, -0.2, 0.0))
		var el := Node3D.new()
		el.position = Vector3(0.0, -0.18, 0.0)
		sh.add_child(el)
		Geo.put(el, Geo.sphere(0.055, 12), joint)
		Geo.put(el, Geo.lathe(Geo.pill_profile(0.068, 0.15, 0.06), 16, "forearm"), white, Vector3(0.0, -0.15, 0.0))
		var hand := Node3D.new()
		hand.position = Vector3(0.0, -0.19, 0.0)
		el.add_child(hand)
		Geo.put(hand, Geo.sphere(0.092, 16), white, Vector3.ZERO, Vector3.ZERO, Vector3(1.0, 0.92, 1.08))
		Geo.put(hand, Geo.sphere(0.04, 10), white, Vector3(-0.07 * sx2, 0.02, -0.05))
		Geo.put(hand, Geo.torus(0.07, 0.085, 20, 5), glow, Vector3(0.0, 0.07, 0.0), Vector3.ZERO, Vector3.ONE, false)
		var fist := Node3D.new()
		fist.position = Vector3(0.0, -0.04, 0.0)
		hand.add_child(fist)
		_sh.append(sh)
		_el.append(el)
		_fist.append(fist)

	# ---- legs
	for i in range(2):
		var sx3: float = -1.0 if i == 0 else 1.0
		var hip := Node3D.new()
		hip.position = Vector3(0.11 * sx3, -0.03, 0.0)
		_pelvis.add_child(hip)
		Geo.put(hip, Geo.sphere(0.065, 12), joint)
		Geo.put(hip, Geo.lathe(Geo.pill_profile(0.055, 0.15, 0.05), 12, "thigh"), joint, Vector3(0.0, -0.15, 0.0))
		var kn := Node3D.new()
		kn.position = Vector3(0.0, -0.14, 0.0)
		hip.add_child(kn)
		Geo.put(kn, Geo.lathe(Geo.pill_profile(0.07, 0.14, 0.06), 14, "shin"), white, Vector3(0.0, -0.14, 0.0))
		var boot := Node3D.new()
		boot.position = Vector3(0.0, -0.17, -0.02)
		kn.add_child(boot)
		Geo.put(boot, Geo.rounded_box(Vector3(0.19, 0.12, 0.27), 0.055, 3), white, Vector3(0.0, -0.02, -0.02))
		Geo.put(boot, Geo.rounded_box(Vector3(0.2, 0.04, 0.28), 0.018, 2), dark, Vector3(0.0, -0.075, -0.02))
		Geo.put(boot, Geo.rounded_box(Vector3(0.12, 0.03, 0.05), 0.012, 2), orange, Vector3(0.0, 0.02, -0.15))
		Geo.put(boot, Geo.torus(0.045, 0.065, 18, 5), glow, Vector3(0.0, -0.098, 0.0), Vector3.ZERO, Vector3.ONE, false)
		var jet := MeshInstance3D.new()
		jet.mesh = Geo.cyl(0.05, 0.16, 1.7, 14)
		var jm: ShaderMaterial = Mats.beam(accent.lerp(Color(1, 1, 1), 0.25), 1.7, 2.4, false, 1.0)
		jet.material_override = jm
		jet.rotation_degrees = Vector3(180.0, 0.0, 0.0)
		jet.position = Vector3(0.0, -0.95, 0.0)
		jet.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		jet.visible = false
		boot.add_child(jet)
		var ps := CPUParticles3D.new()
		ps.mesh = Fx.quad()
		ps.amount = 10
		ps.lifetime = 0.35
		ps.local_coords = false
		ps.emitting = false
		ps.direction = Vector3.DOWN
		ps.spread = 14.0
		ps.initial_velocity_min = 3.0
		ps.initial_velocity_max = 6.0
		ps.gravity = Vector3.ZERO
		ps.scale_amount_min = 0.06
		ps.scale_amount_max = 0.14
		ps.scale_amount_curve = Fx.shrink_curve()
		ps.color = Color(accent.r, accent.g, accent.b, 0.9)
		ps.position = Vector3(0.0, -0.1, 0.0)
		boot.add_child(ps)
		_hip.append(hip)
		_kn.append(kn)
		_boot.append(boot)
		_jets.append(jet)
		_jet_ps.append(ps)

	# spin ring
	_spin_ring = Geo.put(_root, Geo.torus(0.62, 0.7, 40, 6), Mats.neon(accent, 2.6, 1.4, 0.55), Vector3(0.0, 0.62, 0.0), Vector3.ZERO, Vector3.ONE, false)
	_spin_ring.visible = false

	for i in range(2):
		var tr := Fx.Trail3D.new()
		tr.target = _fist[i]
		tr.width = 0.32
		tr.life = 0.16
		tr.color_a = Color(1.0, 0.95, 0.75)
		tr.color_b = accent
		add_child(tr)
		_trails.append(tr)
	_snap_springs()


func _build_backpack(dark: Material, joint: Material) -> void:
	Geo.put(_chest, Geo.rounded_box(Vector3(0.3, 0.32, 0.06), 0.03, 2), joint, Vector3(0.0, 0.2, 0.18))
	_bat_holder = Node3D.new()
	_bat_holder.position = Vector3(0.0, 0.2, 0.25)
	_chest.add_child(_bat_holder)
	for k in range(2):
		var cl := Node3D.new()
		cl.position = Vector3(0.0, 0.11 if k == 0 else -0.11, -0.04)
		_bat_holder.add_child(cl)
		Geo.put(cl, Geo.rounded_box(Vector3(0.22, 0.04, 0.05), 0.015, 2), dark, Vector3(0.0, 0.0, 0.05))
		_clamps.append(cl)
	attach_battery(make_battery_mesh(battery_level))


## A fresh battery cell mesh (lathe pill + caps) with its own material. Origin at its centre.
static func make_battery_mesh(level: float) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = Geo.lathe(Geo.pill_profile(0.085, 0.27, 0.05, 4), 20, "battery_cell")
	var m: ShaderMaterial = Mats.battery(level)
	m.set_shader_parameter("y0", 0.12)
	m.set_shader_parameter("y1", 0.88)
	mi.material_override = m
	mi.set_meta("mat", m)
	var cap_mat: Material = Mats.metal(Color(0.7, 0.74, 0.8), 0.25, 0.9)
	var top := MeshInstance3D.new()
	top.mesh = Geo.cyl(0.06, 0.07, 0.04, 16)
	top.material_override = cap_mat
	top.position = Vector3(0.0, 0.285, 0.0)
	mi.add_child(top)
	var bot := MeshInstance3D.new()
	bot.mesh = Geo.cyl(0.07, 0.06, 0.03, 16)
	bot.material_override = cap_mat
	bot.position = Vector3(0.0, -0.01, 0.0)
	mi.add_child(bot)
	return mi


# ================================================================== API
func attach_battery(mi: MeshInstance3D) -> void:
	if mi.get_parent() != null:
		mi.get_parent().remove_child(mi)
	_bat_holder.add_child(mi)
	mi.transform = Transform3D(Basis.IDENTITY, Vector3(0.0, -0.135, 0.0))
	_bat = mi
	_bat_mat = mi.get_meta("mat") as ShaderMaterial


## Takes the battery off the back and re-parents it to `new_parent`, keeping its world transform.
func detach_battery(new_parent: Node) -> MeshInstance3D:
	var mi: MeshInstance3D = _bat
	if mi == null:
		return null
	var gt: Transform3D = mi.global_transform
	_bat_holder.remove_child(mi)
	new_parent.add_child(mi)
	mi.global_transform = gt
	_bat = null
	_bat_mat = null
	return mi


func battery_socket() -> Node3D:
	return _bat_holder


func set_clamps(open: float) -> void:
	_clamp_target = open


func fist_global(side: int) -> Vector3:
	var f: Node3D = _fist[clampi(side, 0, 1)]
	return f.global_position


func trigger_flip(dir: float = 1.0) -> void:
	_flip_t = 0.0
	_flip_dir = dir


func on_land(impact: float) -> void:
	_sq_v -= clampf(impact, 0.0, 30.0) * 0.32
	_s_ant.v += Vector3(-impact * 0.4, 0.0, 0.0)


func on_jump() -> void:
	_sq_v += 3.2


func on_hurt() -> void:
	_hurt = 1.0
	set_mood(2, 0.8)


func set_mood(m: int, dur: float) -> void:
	_mood = m
	_mood_t = dur


func set_trails(on: bool) -> void:
	for tr in _trails:
		var t3: Fx.Trail3D = tr
		t3.emitting = on


# ================================================================== frame
func _process(delta: float) -> void:
	if not _built:
		return
	var dt: float = minf(delta, 0.05)
	_t += dt
	_mood_t -= dt
	_hurt = maxf(_hurt - dt * 2.2, 0.0)
	_track_motion(dt)
	_pose(dt)
	var steps: int = maxi(1, int(ceil(dt / 0.0084)))
	var h: float = dt / float(steps)
	for _i in range(steps):
		_integrate(h)
	_apply()
	_effects(dt)
	_face_update(dt)
	visible = shown and ((not flicker) or (int(_t * 14.0) % 2 == 0))


func _track_motion(dt: float) -> void:
	var acc: Vector3 = (velocity - _prev_vel) / maxf(dt, 0.001)
	_prev_vel = velocity
	var inv: Basis = global_transform.basis.orthonormalized().inverse()
	var al: Vector3 = inv * acc
	_acc_local = _acc_local.lerp(al, 1.0 - exp(-10.0 * dt))
	var yaw: float = global_rotation.y
	var dy: float = wrapf(yaw - _prev_yaw, -PI, PI)
	_prev_yaw = yaw
	_turn_rate = lerpf(_turn_rate, dy / maxf(dt, 0.001), 1.0 - exp(-12.0 * dt))
	if grounded and not _was_grounded:
		on_land(-_air_vy)
	elif _was_grounded and not grounded and vy > 2.0:
		on_jump()
	if not grounded:
		_air_vy = vy
	_was_grounded = grounded


func _pose(dt: float) -> void:
	var run: float = clampf(speed_ratio, 0.0, 1.5)
	var amp: float = minf(run, 1.0)
	var lp: float = low_power
	var breathe: float = sin(_t * 2.1)
	_k_body = 220.0
	_k_arm = 240.0
	_k_leg = 320.0
	_z_arm = 0.5

	# ---------------- idle base
	_t_pel_pos = Vector3(0.0, PELVIS_Y + breathe * 0.004 - lp * 0.03, 0.0)
	_t_pel_rot = Vector3.ZERO
	_t_chest = Vector3(breathe * 0.025 - lp * 0.35, 0.0, 0.0)
	_t_sh[0] = Vector3(0.08, 0.0, -0.14 + breathe * 0.02)
	_t_sh[1] = Vector3(0.08, 0.0, 0.14 - breathe * 0.02)
	_t_el[0] = Vector3(0.3, 0.0, 0.0)
	_t_el[1] = Vector3(0.3, 0.0, 0.0)
	_t_hip[0] = Vector3(0.0, 0.0, -0.04)
	_t_hip[1] = Vector3(0.0, 0.0, 0.04)
	_t_kn[0] = Vector3.ZERO
	_t_kn[1] = Vector3.ZERO
	_look_t -= dt
	if _look_t <= 0.0:
		_look_t = randf_range(1.5, 4.0)
		_look_target = Vector2(randf_range(-0.45, 0.45), randf_range(-0.1, 0.2))
	var idle_look: float = 1.0 - amp
	_t_head = Vector3(_look_target.y * idle_look - lp * 0.25, _look_target.x * idle_look + clampf(_turn_rate * 0.09, -0.5, 0.5) + look_yaw, sin(_t * 0.7) * 0.04 * idle_look)
	if run < 0.05 and grounded:
		_idle_t += dt
	else:
		_idle_t = 0.0

	# ---------------- run cycle
	if grounded and run > 0.05:
		_phase += dt * (6.5 + run * 8.0) * (1.0 - lp * 0.35)
		var s: float = sin(_phase)
		var c: float = cos(_phase)
		var a: float = amp * (1.0 - lp * 0.4)
		_t_hip[0] = Vector3(s * 0.95 * a, 0.0, -0.04)
		_t_hip[1] = Vector3(-s * 0.95 * a, 0.0, 0.04)
		_t_kn[0] = Vector3(-maxf(c, 0.0) * 1.35 * a - 0.12 * a, 0.0, 0.0)
		_t_kn[1] = Vector3(-maxf(-c, 0.0) * 1.35 * a - 0.12 * a, 0.0, 0.0)
		_t_sh[0] = Vector3(-s * 0.9 * a + 0.1, 0.0, -0.2)
		_t_sh[1] = Vector3(s * 0.9 * a + 0.1, 0.0, 0.2)
		_t_el[0] = Vector3(0.6 + 0.6 * a, 0.0, 0.0)
		_t_el[1] = Vector3(0.6 + 0.6 * a, 0.0, 0.0)
		_t_pel_pos.y = PELVIS_Y - 0.035 * a + absf(s) * 0.045 * a - lp * 0.04
		_t_pel_rot = Vector3(0.0, s * 0.14 * a, 0.0)
		_t_chest = Vector3(-0.2 * a - clampf(-_acc_local.z * 0.012, -0.25, 0.25) - lp * 0.35, -s * 0.2 * a, clampf(_acc_local.x * 0.01, -0.2, 0.2))
		_t_head.x += 0.12 * a
		_k_leg = 520.0
		_k_arm = 320.0

	# ---------------- airborne
	if not grounded:
		var wob: float = sin(_t * 17.0)
		if vy > 1.0:
			_t_hip[0] = Vector3(1.0, 0.0, -0.08)
			_t_kn[0] = Vector3(-1.5, 0.0, 0.0)
			_t_hip[1] = Vector3(-0.25, 0.0, 0.08)
			_t_kn[1] = Vector3(-0.35, 0.0, 0.0)
			_t_sh[0] = Vector3(0.5, 0.0, -1.0)
			_t_sh[1] = Vector3(-0.3, 0.0, 1.1)
			_t_el[0] = Vector3(0.6, 0.0, 0.0)
			_t_el[1] = Vector3(0.4, 0.0, 0.0)
			_t_chest = Vector3(-0.1, 0.0, 0.0)
		else:
			var fall: float = clampf(-vy / 18.0, 0.0, 1.0)
			_t_hip[0] = Vector3(0.35 + wob * 0.08 * fall, 0.0, -0.1)
			_t_kn[0] = Vector3(-0.5, 0.0, 0.0)
			_t_hip[1] = Vector3(0.1 - wob * 0.08 * fall, 0.0, 0.1)
			_t_kn[1] = Vector3(-0.25, 0.0, 0.0)
			_t_sh[0] = Vector3(0.2, 0.0, -1.3 - fall * 0.6 + wob * 0.2 * fall)
			_t_sh[1] = Vector3(0.2, 0.0, 1.3 + fall * 0.6 + wob * 0.2 * fall)
			_t_el[0] = Vector3(0.5, 0.0, 0.0)
			_t_el[1] = Vector3(0.5, 0.0, 0.0)
			_t_chest = Vector3(0.05 * fall, 0.0, 0.0)
			_t_head.x = 0.15 * fall
		_k_leg = 260.0

	# ---------------- hover
	if hovering:
		var hw: float = sin(_t * 23.0)
		_t_hip[0] = Vector3(0.06, 0.0, -0.02)
		_t_hip[1] = Vector3(0.06, 0.0, 0.02)
		_t_kn[0] = Vector3(-0.05, 0.0, 0.0)
		_t_kn[1] = Vector3(-0.05, 0.0, 0.0)
		_t_sh[0] = Vector3(0.15, 0.0, -1.5 + hw * 0.08)
		_t_sh[1] = Vector3(0.15, 0.0, 1.5 - hw * 0.08)
		_t_el[0] = Vector3(0.15, 0.0, 0.0)
		_t_el[1] = Vector3(0.15, 0.0, 0.0)
		_t_chest = Vector3(-0.12 + sin(_t * 31.0) * 0.015, 0.0, sin(_t * 4.0) * 0.04)
		_t_head.x = -0.15

	# ---------------- dash
	if dashing:
		_t_pel_rot = Vector3(-1.1, 0.0, 0.0)
		_t_chest = Vector3(-0.15, 0.0, 0.0)
		_t_sh[0] = Vector3(-2.6, 0.0, -0.25)
		_t_sh[1] = Vector3(-2.6, 0.0, 0.25)
		_t_el[0] = Vector3(0.1, 0.0, 0.0)
		_t_el[1] = Vector3(0.1, 0.0, 0.0)
		_t_hip[0] = Vector3(-0.35, 0.0, -0.05)
		_t_hip[1] = Vector3(-0.15, 0.0, 0.05)
		_t_kn[0] = Vector3(-0.6, 0.0, 0.0)
		_t_kn[1] = Vector3(-0.2, 0.0, 0.0)
		_t_head.x = 0.6
		_k_body = 600.0
		_k_arm = 500.0

	# ---------------- charge (held attack)
	if charging > 0.0:
		var ch: float = clampf(charging, 0.0, 1.0)
		var shake: float = sin(_t * 70.0) * 0.03 * ch
		_t_pel_pos.y = PELVIS_Y - 0.07 * ch
		_t_chest = Vector3(-0.2 * ch + shake, 0.85 * ch, 0.0)
		_t_sh[0] = Vector3(0.9 * ch, 0.0, -0.6)
		_t_sh[1] = Vector3(-0.9 * ch, 0.0, 0.9)
		_t_el[0] = Vector3(1.2, 0.0, 0.0)
		_t_el[1] = Vector3(0.4, 0.0, 0.0)
		_t_hip[0] = Vector3(0.35 * ch, 0.0, -0.25 * ch)
		_t_hip[1] = Vector3(-0.3 * ch, 0.0, 0.25 * ch)
		_t_kn[0] = Vector3(-0.6 * ch, 0.0, 0.0)
		_t_kn[1] = Vector3(-0.4 * ch, 0.0, 0.0)
		_k_body = 400.0

	# ---------------- punches
	if punch > 0:
		_pose_punch(punch, clampf(punch_t, 0.0, 1.0))

	# ---------------- spin
	if spinning:
		_t_sh[0] = Vector3(0.0, 0.0, -1.55)
		_t_sh[1] = Vector3(0.0, 0.0, 1.55)
		_t_el[0] = Vector3(0.05, 0.0, 0.0)
		_t_el[1] = Vector3(0.05, 0.0, 0.0)
		_t_hip[0] = Vector3(0.25, 0.0, -0.3)
		_t_hip[1] = Vector3(0.25, 0.0, 0.3)
		_t_kn[0] = Vector3(-0.4, 0.0, 0.0)
		_t_kn[1] = Vector3(-0.4, 0.0, 0.0)
		_t_chest = Vector3(0.0, 0.0, 0.0)
		_k_arm = 600.0

	# ---------------- hurt reaction
	if _hurt > 0.0:
		var hk: float = _hurt
		_t_chest += Vector3(0.6 * hk, 0.0, 0.0)
		_t_head += Vector3(0.45 * hk, 0.0, 0.3 * hk)
		_t_sh[0] += Vector3(0.0, 0.0, -1.0 * hk)
		_t_sh[1] += Vector3(0.0, 0.0, 1.0 * hk)

	# ---------------- celebrate / wave
	if celebrate:
		var cw: float = sin(_t * 9.0)
		_t_sh[0] = Vector3(0.0, 0.0, -2.6 - cw * 0.25)
		_t_sh[1] = Vector3(0.0, 0.0, 2.6 + cw * 0.25)
		_t_el[0] = Vector3(0.3, 0.0, 0.0)
		_t_el[1] = Vector3(0.3, 0.0, 0.0)
		_t_head = Vector3(-0.25, 0.0, cw * 0.1)
	elif wave and grounded and run < 0.1:
		_t_sh[1] = Vector3(0.0, 0.0, 2.55 + sin(_t * 8.0) * 0.35)
		_t_el[1] = Vector3(0.0, 0.0, 0.5 + sin(_t * 8.0) * 0.3)
		_t_head = Vector3(-0.1, 0.25, 0.12)

	# ---------------- long idle: stretch / look at the camera
	if _idle_t > 7.0 and not wave and pose_override == "":
		var k2: float = fposmod(_idle_t, 10.0)
		if k2 < 2.2:
			var up: float = sin(k2 / 2.2 * PI)
			_t_sh[0] = Vector3(0.0, 0.0, -2.8 * up - 0.14)
			_t_sh[1] = Vector3(0.0, 0.0, 2.8 * up + 0.14)
			_t_chest.x += 0.15 * up
			_t_head.x += 0.3 * up

	# ---------------- scripted poses
	match pose_override:
		"swap_look":
			_t_head = Vector3(-0.15, 1.25, 0.15)
			_t_chest = Vector3(-0.05, 0.45, 0.0)
			_t_sh[1] = Vector3(-0.9, 0.0, 0.55)
			_t_el[1] = Vector3(1.6, 0.0, 0.0)
			_t_sh[0] = Vector3(0.3, 0.0, -0.4)
		"swap_flex":
			_t_sh[1] = Vector3(0.0, 0.0, 2.7)
			_t_el[1] = Vector3(0.0, 0.0, 1.7)
			_t_sh[0] = Vector3(0.6, 0.0, -0.3)
			_t_el[0] = Vector3(1.8, 0.0, 0.0)
			_t_chest = Vector3(0.12, -0.2, 0.0)
			_t_head = Vector3(-0.25, -0.2, 0.0)
			_t_pel_pos.y = PELVIS_Y + 0.02
		"shutdown":
			_t_pel_pos = Vector3(0.0, 0.16, 0.0)
			_t_hip[0] = Vector3(1.5, 0.0, -0.15)
			_t_hip[1] = Vector3(1.5, 0.0, 0.15)
			_t_kn[0] = Vector3(-0.1, 0.0, 0.0)
			_t_kn[1] = Vector3(-0.1, 0.0, 0.0)
			_t_chest = Vector3(-0.55, 0.0, 0.1)
			_t_head = Vector3(-0.55, 0.15, 0.25)
			_t_sh[0] = Vector3(0.25, 0.0, -0.08)
			_t_sh[1] = Vector3(0.25, 0.0, 0.08)
			_t_el[0] = Vector3(0.1, 0.0, 0.0)
			_t_el[1] = Vector3(0.1, 0.0, 0.0)
			_k_body = 90.0
			_k_arm = 90.0
			_k_leg = 120.0


## Punch choreography: anticipation -> snap -> hold -> recover. Side 1 = right hand.
func _pose_punch(n: int, u: float) -> void:
	var side: int = 1 if n != 2 else 0
	var other: int = 1 - side
	var sg: float = 1.0 if side == 1 else -1.0
	var wind: float = clampf(u / 0.18, 0.0, 1.0)
	var strike: float = clampf((u - 0.18) / 0.22, 0.0, 1.0)
	var rec: float = clampf((u - 0.65) / 0.35, 0.0, 1.0)
	var k: float = strike * (1.0 - rec)
	if n == 3:
		# rising uppercut
		var shx: float = lerpf(-0.9 * wind, 2.9, k)
		_t_sh[side] = Vector3(shx, 0.0, 0.25 * sg * (1.0 - k))
		_t_el[side] = Vector3(lerpf(1.5, 0.35, k), 0.0, 0.0)
		_t_sh[other] = Vector3(0.4, 0.0, -0.6 * sg)
		_t_el[other] = Vector3(1.4, 0.0, 0.0)
		_t_chest = Vector3(lerpf(-0.35 * wind, 0.25, k), lerpf(-0.4 * wind, 0.35, k) * sg, 0.0)
		_t_pel_pos.y = PELVIS_Y - 0.08 * wind * (1.0 - k) + 0.03 * k
		_t_head = Vector3(-0.3 * k, 0.0, 0.0)
		_t_hip[side] = Vector3(-0.2 * k, 0.0, 0.1 * sg)
		_t_hip[other] = Vector3(0.5 * k, 0.0, -0.1 * sg)
		_t_kn[other] = Vector3(-0.9 * k, 0.0, 0.0)
	else:
		var shx2: float = lerpf(-0.55 * wind, 1.62, k)
		_t_sh[side] = Vector3(shx2, 0.0, lerpf(0.35 * sg, -0.08 * sg, k))
		_t_el[side] = Vector3(lerpf(1.7, 0.0, k), 0.0, 0.0)
		_t_sh[other] = Vector3(0.75, 0.0, -0.3 * sg)
		_t_el[other] = Vector3(1.9, 0.0, 0.0)
		_t_chest = Vector3(-0.28 * k, lerpf(-0.35 * wind, 0.55, k) * sg, 0.0)
		_t_pel_rot = Vector3(0.0, 0.2 * k * sg, 0.0)
		_t_pel_pos.y = PELVIS_Y - 0.04 * k
		_t_hip[other] = Vector3(0.5 * k, 0.0, -0.05 * sg)
		_t_kn[other] = Vector3(-0.35 * k, 0.0, 0.0)
		_t_hip[side] = Vector3(-0.35 * k, 0.0, 0.05 * sg)
		_t_head.y -= 0.25 * k * sg
	_k_arm = 1100.0
	_z_arm = 0.42
	_k_body = 650.0


func _integrate(h: float) -> void:
	_s_pel_pos.step(_t_pel_pos, _k_body * 1.4, 0.6, h)
	_s_pel_rot.step(_t_pel_rot, _k_body, 0.6, h)
	_s_chest.step(_t_chest, _k_body, 0.55, h)
	_s_head.step(_t_head, 150.0, 0.5, h)
	for i in range(2):
		var sa: Spring = _s_sh[i]
		sa.step(_t_sh[i], _k_arm, _z_arm, h)
		var se: Spring = _s_el[i]
		se.step(_t_el[i], _k_arm * 1.2, _z_arm, h)
		var sh: Spring = _s_hip[i]
		sh.step(_t_hip[i], _k_leg, 0.6, h)
		var sk: Spring = _s_kn[i]
		sk.step(_t_kn[i], _k_leg * 1.2, 0.6, h)
	# antenna: pendulum excited by body acceleration and turning
	var drive := Vector3(-_acc_local.z * 0.006 + _s_chest.v.x * 0.02, 0.0, _acc_local.x * 0.006 - _turn_rate * 0.05)
	drive = drive.clamp(Vector3(-0.7, 0.0, -0.7), Vector3(0.7, 0.0, 0.7))
	_s_ant.step(drive, 90.0, 0.12, h)
	# squash & stretch
	_sq_v += (-_sq * 260.0 - _sq_v * 2.0 * sqrt(260.0) * 0.35) * h
	_sq += _sq_v * h
	_sq = clampf(_sq, -0.35, 0.35)
	_clamp_open = move_toward(_clamp_open, _clamp_target, h * 5.0)


func _apply() -> void:
	_pelvis.position = _s_pel_pos.x
	_pelvis.rotation = _s_pel_rot.x
	_chest.rotation = _s_chest.x
	_head.rotation = _s_head.x
	_ant.rotation = _s_ant.x
	for i in range(2):
		var sh: Node3D = _sh[i]
		var sp: Spring = _s_sh[i]
		sh.rotation = sp.x
		var el: Node3D = _el[i]
		var se: Spring = _s_el[i]
		el.rotation = Vector3(maxf(se.x.x, -0.1), se.x.y, se.x.z)
		var hp: Node3D = _hip[i]
		var shp: Spring = _s_hip[i]
		hp.rotation = shp.x
		var kn: Node3D = _kn[i]
		var sk: Spring = _s_kn[i]
		kn.rotation = Vector3(minf(sk.x.x, 0.05), 0.0, 0.0)
		var boot: Node3D = _boot[i]
		boot.rotation.x = -(shp.x.x + sk.x.x) * 0.45 if grounded else 0.0
	var air_stretch: float = 0.0
	if not grounded and not hovering:
		air_stretch = clampf(vy / 30.0, -0.12, 0.18)
	var s: float = _sq + air_stretch
	_root.scale = Vector3(1.0 - s * 0.55, 1.0 + s, 1.0 - s * 0.55)
	# flips (double jump)
	if _flip_t >= 0.0:
		_flip_t += get_process_delta_time()
		var f: float = clampf(_flip_t / 0.42, 0.0, 1.0)
		var e: float = 1.0 - pow(1.0 - f, 2.6)
		_flip.rotation.x = -TAU * e * _flip_dir
		if f >= 1.0:
			_flip_t = -1.0
			_flip.rotation.x = 0.0
	# whole-body spin
	if spinning:
		_spin_angle += get_process_delta_time() * (34.0 if spin_big else 28.0)
		_flip.rotation.y = _spin_angle
	else:
		_spin_angle = 0.0
		_flip.rotation.y = lerp_angle(_flip.rotation.y, 0.0, 0.4)
	for k in range(_clamps.size()):
		var cl: Node3D = _clamps[k]
		cl.rotation.x = (1.0 if k == 0 else -1.0) * _clamp_open * 1.1


func _effects(_dt: float) -> void:
	_spin_ring.visible = spinning
	if spinning:
		var sc: float = 1.7 if spin_big else 1.0
		_spin_ring.scale = Vector3(sc, 1.0, sc)
		_spin_ring.rotation.y = -_spin_angle * 0.5
	var jets: bool = hovering or dashing
	for i in range(2):
		var j: MeshInstance3D = _jets[i]
		j.visible = jets and shown
		if jets:
			var fl: float = 0.85 + 0.25 * sin(_t * 61.0 + float(i) * 2.0)
			j.scale = Vector3(fl, 0.9 + 0.2 * absf(sin(_t * 37.0)), fl)
		var ps: CPUParticles3D = _jet_ps[i]
		ps.emitting = jets and shown
	if _bat_mat != null:
		_bat_mat.set_shader_parameter("level", battery_level)
		_bat_mat.set_shader_parameter("blink", 1.0 if battery_blink else 0.0)
	var cl: Color = accent if low_power < 0.5 else Color(1.0, 0.3, 0.25)
	var pw: float = 2.6 * (1.0 - low_power * 0.6)
	if low_power > 0.5 and int(_t * 3.0) % 2 == 0:
		pw *= 0.3
	_chest_light.albedo_color = Color(cl.r * pw, cl.g * pw, cl.b * pw)


func _face_update(dt: float) -> void:
	_blink -= dt
	if _blink < 0.0:
		_blink_k = clampf(1.0 + _blink * 14.0, 0.0, 1.0) if _blink > -0.07 else clampf((-_blink - 0.07) * 14.0, 0.0, 1.0)
		if _blink < -0.15:
			_blink = randf_range(1.8, 4.5)
			_blink_k = 1.0
	var m: int = 0
	if _mood_t > 0.0 and _mood >= 0:
		m = _mood
	elif pose_override == "shutdown":
		m = 4
	elif _hurt > 0.0:
		m = 2
	elif low_power > 0.6:
		m = 4
	elif charging > 0.2 or punch > 0 or dashing:
		m = 3
	elif celebrate or (wave and speed_ratio < 0.1):
		m = 1
	_face.set_shader_parameter("mood", float(m))
	_face.set_shader_parameter("open", _blink_k)
	var lk := Vector2(clampf(-_s_head.x.y * 0.6 + _turn_rate * 0.05, -1.0, 1.0), clampf(_s_head.x.x * 0.8, -1.0, 1.0))
	_face.set_shader_parameter("look", lk)
	var pw: float = 1.0 - low_power * 0.55
	if pose_override == "shutdown":
		pw = 0.25 + 0.15 * sin(_t * 3.0)
	elif low_power > 0.6 and randf() < 0.04:
		pw *= 0.2
	_face.set_shader_parameter("power", pw)
	_face.set_shader_parameter("squint", 0.6 if charging > 0.3 else 0.0)


func set_face_scan(on: bool) -> void:
	_face.set_shader_parameter("scan", 1.0 if on else 0.0)


func _snap_springs() -> void:
	_s_pel_pos.snap(Vector3(0.0, PELVIS_Y, 0.0))
	_s_pel_rot.snap(Vector3.ZERO)
	_s_chest.snap(Vector3.ZERO)
	_s_head.snap(Vector3.ZERO)
	for i in range(2):
		var a: Spring = _s_sh[i]
		a.snap(Vector3(0.08, 0.0, -0.14 if i == 0 else 0.14))
		var e: Spring = _s_el[i]
		e.snap(Vector3(0.3, 0.0, 0.0))
		var hh: Spring = _s_hip[i]
		hh.snap(Vector3.ZERO)
		var k: Spring = _s_kn[i]
		k.snap(Vector3.ZERO)
