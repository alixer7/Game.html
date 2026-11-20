class_name AnimalModel
extends Node3D
## مجسم حيوان إجرائي رباعي أو ثنائي الأرجل مع حركة مشي/جري/هجوم/موت.

var sp := {}
var body: Node3D
var neck: Node3D
var head: Node3D
var tail: Node3D
var legs: Array = []
var phase := 0.0
var speed := 0.0
var state := "idle"
var attack_t := -1.0
var _body_y := 0.5

func build(s: Dictionary) -> void:
	sp = s
	for c in get_children():
		c.queue_free()
	legs = []
	var L: float = s["len"]
	var R: float = s["r"]
	var leg: float = s["leg"]
	var col: Color = s["col"]
	var belly: Color = s.get("belly", col.lightened(0.25))
	var m := HumanModel.cmat(col, 0.85)
	var mb := HumanModel.cmat(belly, 0.85)
	var dark := HumanModel.cmat(col.darkened(0.45), 0.6)
	_body_y = leg + R * 0.75
	body = Node3D.new()
	body.position = Vector3(0, _body_y, 0)
	add_child(body)
	if s.get("biped", false):
		_mi(body, HumanModel._sph(R), m, Vector3.ZERO, Vector3(1.0, 0.95, 1.25))
		_mi(body, HumanModel._sph(R * 0.6), m, Vector3(0, R * 0.2, R * 0.9), Vector3(0.6, 1.2, 1.0))
		for sx in [-1.0, 1.0]:
			_mi(body, HumanModel._sph(R * 0.55), HumanModel.cmat(col.darkened(0.15), 0.85), Vector3(sx * R * 0.85, 0.02, 0.05), Vector3(0.35, 0.8, 1.2))
	else:
		var bm := _mi(body, HumanModel._cap(R, L), m, Vector3.ZERO, Vector3(1.0, 1.0, 0.95))
		bm.rotation.x = PI / 2.0
		var bl := _mi(body, HumanModel._cap(R * 0.82, L * 0.8), mb, Vector3(0, -R * 0.28, 0), Vector3(0.95, 1.0, 0.9))
		bl.rotation.x = PI / 2.0
		if s.get("hump", false):
			_mi(body, HumanModel._sph(R * 0.75), m, Vector3(0, R * 0.95, 0.05), Vector3(1.0, 0.9, 1.3))
		if s.get("mane", false):
			_mi(body, HumanModel._sph(R * 0.9), HumanModel.cmat(col.darkened(0.2), 0.95), Vector3(0, R * 0.25, -L * 0.32), Vector3(1.1, 1.05, 1.0))
	# الرقبة والرأس
	neck = Node3D.new()
	var front := -L * 0.5 if not s.get("biped", false) else -R * 0.75
	neck.position = Vector3(0, R * 0.35, front)
	body.add_child(neck)
	var nl: float = s.get("neck", 0.2)
	if nl > 0.06:
		var nm := _mi(neck, HumanModel._cap(R * 0.42, nl + R * 0.6), m, Vector3(0, nl * 0.4, -nl * 0.35))
		nm.rotation.x = -0.6
	head = Node3D.new()
	head.position = Vector3(0, nl * 0.75, -nl * 0.65)
	neck.add_child(head)
	var hs: float = s["head"]
	_mi(head, HumanModel._sph(hs), m, Vector3(0, 0, -hs * 0.3), Vector3(0.85, 0.85, 1.15))
	var snout: float = s.get("snout", hs * 0.6)
	var sn := _mi(head, HumanModel._cap(hs * 0.45, snout + hs * 0.6), mb if s.get("light_snout", false) else m, Vector3(0, -hs * 0.2, -hs * 0.6 - snout * 0.5))
	sn.rotation.x = PI / 2.0
	if s.get("flat_snout", false):
		sn.scale = Vector3(1.3, 0.6, 1.0)
	_mi(head, HumanModel._sph(hs * 0.12), dark, Vector3(0, -hs * 0.15, -hs * 0.6 - snout - hs * 0.12))
	for sx in [-1.0, 1.0]:
		var eye := _mi(head, HumanModel._sph(hs * 0.12), HumanModel.cmat(Color(0.05, 0.04, 0.03), 0.2), Vector3(sx * hs * 0.5, hs * 0.25, -hs * 0.65))
		eye.visibility_range_end = 30.0
		var ears: float = s.get("ears", hs * 0.5)
		if ears > 0.0:
			var ear := _mi(head, HumanModel._cap(hs * 0.16, ears), m, Vector3(sx * hs * 0.45, hs * 0.7 + ears * 0.3, -hs * 0.1))
			ear.rotation.z = -sx * 0.35
			if s.get("round_ears", false):
				ear.scale = Vector3(1.5, 0.5, 0.8)
		if s.get("antlers", false):
			var antl := HumanModel.cmat(Color(0.75, 0.66, 0.5), 0.7)
			var a1 := _mi(head, HumanModel._cap(0.025, 0.55), antl, Vector3(sx * hs * 0.4, hs * 0.95 + 0.22, hs * 0.1))
			a1.rotation = Vector3(-0.3, 0, -sx * 0.45)
			var a2 := _mi(head, HumanModel._cap(0.02, 0.3), antl, Vector3(sx * hs * 0.75, hs * 0.95 + 0.38, -0.08))
			a2.rotation = Vector3(-0.9, 0, -sx * 0.2)
		if s.get("horns", false):
			var hm := _mi(head, HumanModel._cap(0.03, 0.3), HumanModel.cmat(Color(0.3, 0.27, 0.22), 0.5), Vector3(sx * hs * 0.35, hs * 0.85, hs * 0.2))
			hm.rotation = Vector3(0.7, 0, -sx * 0.25)
		if s.get("tusks", false):
			var tk := _mi(head, HumanModel._cap(0.018, 0.14), HumanModel.cmat(Color(0.95, 0.92, 0.82), 0.4), Vector3(sx * hs * 0.32, -hs * 0.2, -hs * 0.6 - snout * 0.7))
			tk.rotation = Vector3(-0.5, 0, sx * 0.3)
	if s.get("comb", false):
		_mi(head, HumanModel._box(Vector3(0.025, 0.06, 0.08)), HumanModel.cmat(Color(0.85, 0.1, 0.1), 0.6), Vector3(0, hs * 0.95, -hs * 0.2))
		_mi(head, HumanModel._box(Vector3(0.03, 0.03, 0.06)), HumanModel.cmat(Color(0.95, 0.7, 0.2), 0.5), Vector3(0, -hs * 0.1, -hs * 1.1))
	# الذيل
	tail = Node3D.new()
	var back := L * 0.5 if not s.get("biped", false) else R * 0.85
	tail.position = Vector3(0, R * 0.25, back)
	body.add_child(tail)
	var tl: float = s.get("tail", 0.15)
	if tl > 0.0:
		var tr: float = s.get("tail_r", 0.04)
		var tm := _mi(tail, HumanModel._cap(tr, tl), m, Vector3(0, -tl * 0.25, tl * 0.4))
		tm.rotation.x = 0.9 if not s.get("flat_tail", false) else PI / 2.0
	# الأرجل
	var lr: float = s.get("leg_r", R * 0.22)
	var pts: Array
	if s.get("biped", false):
		pts = [Vector3(-R * 0.35, -R * 0.6, 0.05), Vector3(R * 0.35, -R * 0.6, 0.05)]
	else:
		var sx2: float = R * 0.6 * s.get("splay", 1.0)
		pts = [Vector3(-sx2, -R * 0.4, -L * 0.38), Vector3(sx2, -R * 0.4, -L * 0.38), Vector3(-sx2, -R * 0.4, L * 0.38), Vector3(sx2, -R * 0.4, L * 0.38)]
	var lm := HumanModel.cmat(s.get("leg_col", col.darkened(0.1)), 0.85)
	for p in pts:
		var hip := Node3D.new()
		hip.position = p
		body.add_child(hip)
		var top_len: float = (leg - R * 0.4 + R * 0.6) * 0.5 + 0.02
		_mi(hip, HumanModel._cap(lr, top_len + lr), lm, Vector3(0, -top_len * 0.5, 0))
		var knee := Node3D.new()
		knee.position = Vector3(0, -top_len, 0)
		hip.add_child(knee)
		_mi(knee, HumanModel._cap(lr * 0.75, top_len + lr * 0.8), lm, Vector3(0, -top_len * 0.5, 0))
		_mi(knee, HumanModel._sph(lr * 0.9), dark, Vector3(0, -top_len, -lr * 0.3), Vector3(1.0, 0.6, 1.3))
		legs.append([hip, knee])

func _mi(parent: Node3D, mesh: Mesh, m: Material, pos: Vector3, scl := Vector3.ONE) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = m
	mi.position = pos
	mi.scale = scl
	parent.add_child(mi)
	return mi

func play_attack() -> void:
	attack_t = 0.0

func _process(dt: float) -> void:
	if body == null:
		return
	var cam := get_viewport().get_camera_3d()
	if cam and cam.global_position.distance_squared_to(global_position) > 4900.0 and state != "dead":
		return
	if state == "dead":
		rotation.z = lerpf(rotation.z, PI / 2.0, dt * 4.0)
		position.y = 0.0
		body.position.y = _body_y * 0.5
		return
	rotation.z = 0.0
	var run := clampf(speed / maxf(sp.get("run", 6.0), 0.1), 0.0, 1.0)
	phase += dt * (2.0 + speed * 3.0 / maxf(sp.get("leg", 0.5) * 2.0, 0.4))
	var amp := clampf(speed * 0.25, 0.0, 0.75)
	var s := sin(phase)
	if sp.get("hop", false) and speed > 0.5:
		body.position.y = _body_y + absf(s) * 0.15
		for i in range(legs.size()):
			legs[i][0].rotation.x = s * 0.8 * (1.0 if i < 2 else -1.0)
	else:
		body.position.y = _body_y + absf(cos(phase)) * 0.03 * amp
		for i in range(legs.size()):
			var ph := s if (i == 0 or i == 3) else -s
			if legs.size() == 2:
				ph = s if i == 0 else -s
			legs[i][0].rotation.x = ph * amp
			legs[i][1].rotation.x = maxf(0.0, ph) * amp * 0.9
	body.rotation.x = 0.0
	if tail:
		tail.rotation.y = sin(phase * 0.7) * (0.25 + run * 0.2)
	if head:
		head.rotation.x = 0.0
		if state == "graze":
			neck.rotation.x = lerpf(neck.rotation.x, 0.9, dt * 3.0)
		else:
			neck.rotation.x = lerpf(neck.rotation.x, sin(phase * 0.5) * 0.05, dt * 4.0)
	if attack_t >= 0.0:
		attack_t += dt * 3.0
		var k := sin(clampf(attack_t, 0.0, 1.0) * PI)
		neck.rotation.x = -0.4 * k
		body.position.z = -k * 0.25
		if attack_t >= 1.0:
			attack_t = -1.0
			body.position.z = 0.0
