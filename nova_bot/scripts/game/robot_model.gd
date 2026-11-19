class_name RobotModel
extends Node3D
## Cartoon robot built from primitives and animated from code: run cycle, squash & stretch,
## hover jets, spin ring, blinking eyes. The Player (or the menu) just sets the public state vars.

var speed_ratio: float = 0.0    # horizontal speed / run speed
var grounded: bool = true
var vy: float = 0.0
var spinning: bool = false
var hovering: bool = false
var dashing: bool = false
var flicker: bool = false       # invulnerability blink
var wave: bool = false          # friendly waving (menu, rescue bots)
var shown: bool = true          # owner switch (hidden while dead)
var accent: Color = Color(0.25, 0.9, 1.0)

var _body: Node3D
var _spin_pivot: Node3D
var _legs: Array = []
var _arms: Array = []
var _eyes: Node3D
var _flames: Array = []
var _spin_ring: MeshInstance3D
var _head: Node3D
var _phase: float = 0.0
var _squash: float = 0.0
var _lean: float = 0.0
var _t: float = 0.0
var _was_grounded: bool = true
var _prev_vy: float = 0.0
var _blink: float = 3.0
var _spin_angle: float = 0.0


static func make(col: Color = Color(0.25, 0.9, 1.0)) -> RobotModel:
	var m := RobotModel.new()
	m.accent = col
	m._build()
	return m


func _ready() -> void:
	if _body == null:
		_build()


func _build() -> void:
	scale = Vector3.ONE * 0.86
	var white: Material = Mats.std(Color(0.93, 0.96, 1.0), 0.15, 0.28)
	var steel: Material = Mats.std(Color(0.45, 0.52, 0.68), 0.7, 0.35)
	var dark: Material = Mats.std(Color(0.02, 0.03, 0.08), 0.6, 0.12)
	var glow: Material = Mats.std(Color(0.02, 0.1, 0.12), 0.0, 0.5, accent, 3.4)
	var glow2: Material = Mats.std(Color(0.1, 0.02, 0.08), 0.0, 0.5, Color(1.0, 0.4, 0.75), 3.0)

	_body = Node3D.new()
	add_child(_body)
	_spin_pivot = Node3D.new()
	_body.add_child(_spin_pivot)

	# torso + chest light
	_mesh(_spin_pivot, _sphere(0.25), white, Vector3(0.0, 0.5, 0.0), Vector3(1.0, 1.1, 0.9))
	_mesh(_spin_pivot, _sphere(0.06), glow, Vector3(0.0, 0.52, -0.21), Vector3(1.0, 1.0, 0.5))
	_mesh(_spin_pivot, _cyl(0.07, 0.07, 0.1), steel, Vector3(0.0, 0.72, 0.0))

	# head
	_head = Node3D.new()
	_head.position = Vector3(0.0, 0.94, 0.0)
	_spin_pivot.add_child(_head)
	_mesh(_head, _sphere(0.29), white, Vector3.ZERO, Vector3(1.05, 0.92, 1.0))
	_mesh(_head, _sphere(0.24), dark, Vector3(0.0, 0.01, -0.16), Vector3(1.0, 0.7, 0.55))
	_eyes = Node3D.new()
	_eyes.position = Vector3(0.0, 0.02, -0.265)
	_head.add_child(_eyes)
	_mesh(_eyes, _capsule(0.035, 0.13), glow, Vector3(-0.095, 0.0, 0.0))
	_mesh(_eyes, _capsule(0.035, 0.13), glow, Vector3(0.095, 0.0, 0.0))
	for sx in [-1.0, 1.0]:
		var s: float = sx
		_mesh(_head, _cyl(0.075, 0.075, 0.06), steel, Vector3(0.3 * s, 0.0, 0.0), Vector3.ONE, Vector3(0.0, 0.0, 90.0))
		_mesh(_head, _cyl(0.045, 0.045, 0.075), glow2, Vector3(0.3 * s, 0.0, 0.0), Vector3.ONE, Vector3(0.0, 0.0, 90.0))
	_mesh(_head, _cyl(0.012, 0.012, 0.2), steel, Vector3(0.0, 0.34, 0.0))
	_mesh(_head, _sphere(0.05), glow2, Vector3(0.0, 0.46, 0.0))

	# arms (pivot at the shoulder, swing around X, spread around Z)
	for sx in [-1.0, 1.0]:
		var s2: float = sx
		var pivot := Node3D.new()
		pivot.position = Vector3(0.29 * s2, 0.6, 0.0)
		_spin_pivot.add_child(pivot)
		_mesh(pivot, _capsule(0.055, 0.28), steel, Vector3(0.0, -0.11, 0.0))
		_mesh(pivot, _sphere(0.075), white, Vector3(0.0, -0.26, 0.0))
		_arms.append(pivot)

	# legs (pivot at the hip)
	for sx in [-1.0, 1.0]:
		var s3: float = sx
		var hip := Node3D.new()
		hip.position = Vector3(0.13 * s3, 0.3, 0.0)
		_body.add_child(hip)
		_mesh(hip, _capsule(0.05, 0.22), steel, Vector3(0.0, -0.12, 0.0))
		_mesh(hip, _sphere(0.11), white, Vector3(0.0, -0.23, -0.03), Vector3(1.0, 0.65, 1.45))
		_legs.append(hip)

	# jet flames under the feet
	for sx in [-1.0, 1.0]:
		var s4: float = sx
		var cone := CylinderMesh.new()
		cone.top_radius = 0.1
		cone.bottom_radius = 0.0
		cone.height = 0.55
		cone.radial_segments = 10
		var fm := _mesh(_body, cone, Mats.neon_unique(Color(0.45, 0.9, 1.0), 3.2, 1.0, 0.35), Vector3(0.13 * s4, -0.17, 0.0))
		fm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		fm.visible = false
		_flames.append(fm)

	# spin ring
	var tm := TorusMesh.new()
	tm.inner_radius = 0.56
	tm.outer_radius = 0.64
	tm.rings = 28
	tm.ring_segments = 8
	_spin_ring = _mesh(_body, tm, Mats.neon(accent, 2.6, 1.4, 0.55), Vector3(0.0, 0.55, 0.0))
	_spin_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_spin_ring.visible = false


func _mesh(parent: Node3D, mesh: Mesh, mat: Material, pos: Vector3, scl: Vector3 = Vector3.ONE, rot: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	mi.scale = scl
	mi.rotation_degrees = rot
	parent.add_child(mi)
	return mi


func _sphere(r: float) -> SphereMesh:
	var m := SphereMesh.new()
	m.radius = r
	m.height = r * 2.0
	m.radial_segments = 20
	m.rings = 10
	return m


func _capsule(r: float, h: float) -> CapsuleMesh:
	var m := CapsuleMesh.new()
	m.radius = r
	m.height = h
	m.radial_segments = 12
	m.rings = 4
	return m


func _cyl(rt: float, rb: float, h: float) -> CylinderMesh:
	var m := CylinderMesh.new()
	m.top_radius = rt
	m.bottom_radius = rb
	m.height = h
	m.radial_segments = 14
	return m


func _process(delta: float) -> void:
	if _body == null:
		return
	_t += delta
	var run: float = clampf(speed_ratio, 0.0, 1.4)

	# landing squash / jump stretch
	if not grounded:
		_prev_vy = vy
	if grounded and not _was_grounded:
		_squash = clampf(-_prev_vy / 22.0, 0.2, 1.0)
	elif _was_grounded and not grounded and vy > 2.0:
		_squash = -0.55
	_was_grounded = grounded
	_squash = lerpf(_squash, 0.0, 1.0 - exp(-9.0 * delta))
	var air_stretch: float = 0.0
	if not grounded:
		air_stretch = clampf(vy / 20.0, -0.25, 0.4)
	var sq: float = _squash - air_stretch * 0.6
	_body.scale = Vector3(1.0 + 0.18 * sq, 1.0 - 0.3 * sq, 1.0 + 0.18 * sq)

	# run cycle
	var swing: float = 0.0
	if grounded and run > 0.05:
		_phase += delta * (7.0 + run * 9.0)
		swing = sin(_phase) * 0.95 * minf(run, 1.0)
	var k: float = 1.0 - exp(-18.0 * delta)
	var leg_l: float = swing
	var leg_r: float = -swing
	var arm_lx: float = -swing * 0.8
	var arm_rx: float = swing * 0.8
	var arm_lz: float = 0.08
	var arm_rz: float = -0.08
	if not grounded:
		leg_l = -0.5 + clampf(vy * 0.02, -0.3, 0.3)
		leg_r = -0.2
		arm_lz = 0.9
		arm_rz = -0.9
		arm_lx = 0.0
		arm_rx = 0.0
	if hovering:
		leg_l = 0.1
		leg_r = 0.1
		arm_lz = 0.5
		arm_rz = -0.5
	if spinning:
		arm_lz = 1.45
		arm_rz = -1.45
		arm_lx = 0.0
		arm_rx = 0.0
	if wave and grounded and run < 0.1:
		arm_rz = -(2.5 + sin(_t * 8.0) * 0.35)
	var l0: Node3D = _legs[0]
	var l1: Node3D = _legs[1]
	var a0: Node3D = _arms[0]
	var a1: Node3D = _arms[1]
	l0.rotation.x = lerpf(l0.rotation.x, leg_l, k)
	l1.rotation.x = lerpf(l1.rotation.x, leg_r, k)
	a0.rotation.x = lerpf(a0.rotation.x, arm_lx, k)
	a1.rotation.x = lerpf(a1.rotation.x, arm_rx, k)
	a0.rotation.z = lerpf(a0.rotation.z, -arm_lz, k)
	a1.rotation.z = lerpf(a1.rotation.z, -arm_rz, k)

	# bob, lean, idle breathing
	var bob: float = absf(sin(_phase)) * 0.045 * minf(run, 1.0) if grounded else 0.0
	bob += sin(_t * 2.2) * 0.008
	_body.position.y = lerpf(_body.position.y, bob, k)
	var lean_t: float = -0.22 * minf(run, 1.0)
	if dashing:
		lean_t = -0.95
	elif not grounded:
		lean_t = -0.12
	_lean = lerpf(_lean, lean_t, 1.0 - exp(-10.0 * delta))
	_body.rotation.x = _lean
	_head.rotation.y = sin(_t * 1.3) * 0.12 * (1.0 - minf(run, 1.0))

	# spin
	if spinning:
		_spin_angle += delta * 30.0
		_spin_pivot.rotation.y = _spin_angle
		_spin_ring.visible = true
		_spin_ring.rotation.y = -_spin_angle * 0.6
	else:
		_spin_angle = 0.0
		_spin_pivot.rotation.y = 0.0
		_spin_ring.visible = false

	# jets
	var fire: bool = hovering or dashing
	for f in _flames:
		var fl: MeshInstance3D = f
		fl.visible = fire
		if fire:
			var s: float = 0.8 + 0.4 * sin(_t * 55.0 + fl.position.x * 20.0)
			fl.scale = Vector3(s, 0.9 + 0.5 * absf(sin(_t * 40.0)), s)

	# blink
	_blink -= delta
	var open: float = 1.0
	if _blink < 0.0:
		open = 0.1
		if _blink < -0.12:
			_blink = randf_range(2.0, 5.0)
	_eyes.scale = Vector3(1.0, lerpf(_eyes.scale.y, open, 1.0 - exp(-40.0 * delta)), 1.0)

	visible = shown and ((not flicker) or (int(_t * 14.0) % 2 == 0))
