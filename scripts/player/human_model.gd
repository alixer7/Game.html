class_name HumanModel
extends Node3D
## مجسم بشري إجرائي بمفاصل وتحريك برمجي (مشي، جري، ضرب، سباحة، نوم، جلوس، حديث).
## الوجه باتجاه -Z.

static var _mat_cache := {}
static var _mesh_cache := {}

var app := {}
var rig: Node3D
var hips: Node3D
var torso: Node3D
var head: Node3D
var l_sh: Node3D
var r_sh: Node3D
var l_el: Node3D
var r_el: Node3D
var l_hip: Node3D
var r_hip: Node3D
var l_knee: Node3D
var r_knee: Node3D
var hand_r: Node3D
var held_node: Node3D = null
var held_id := ""
var parts := {}
var hat: MeshInstance3D = null
var pack: MeshInstance3D = null
var phase := 0.0
var swing_t := -1.0
var swing_kind := "chop"
var state := "idle"
var speed := 0.0
var talk_t := 0.0
var hit_flash := 0.0
var _hip_y := 0.95
var _h := 1.0
var _skin_mat: Material

static func cmat(c: Color, rough := 0.8, metal := 0.0) -> StandardMaterial3D:
	var key := "%s_%.2f_%.2f" % [c.to_html(true), rough, metal]
	if _mat_cache.has(key):
		return _mat_cache[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	m.metallic = metal
	_mat_cache[key] = m
	return m

static func _cap(r: float, h: float) -> CapsuleMesh:
	var key := "cap_%.3f_%.3f" % [r, h]
	if _mesh_cache.has(key):
		return _mesh_cache[key]
	var m := CapsuleMesh.new()
	m.radius = r
	m.height = h
	m.radial_segments = 10
	m.rings = 4
	_mesh_cache[key] = m
	return m

static func _sph(r: float, hemi := false) -> SphereMesh:
	var key := "sph_%.3f_%s" % [r, hemi]
	if _mesh_cache.has(key):
		return _mesh_cache[key]
	var m := SphereMesh.new()
	m.radius = r
	m.height = r * (1.0 if hemi else 2.0)
	m.is_hemisphere = hemi
	m.radial_segments = 12
	m.rings = 6
	_mesh_cache[key] = m
	return m

static func _cyl() -> CylinderMesh:
	if not _mesh_cache.has("cyl"):
		var m := CylinderMesh.new()
		m.radial_segments = 12
		m.rings = 1
		_mesh_cache["cyl"] = m
	return _mesh_cache["cyl"]

static func _box(s: Vector3) -> BoxMesh:
	var key := "box_%.3f_%.3f_%.3f" % [s.x, s.y, s.z]
	if _mesh_cache.has(key):
		return _mesh_cache[key]
	var m := BoxMesh.new()
	m.size = s
	_mesh_cache[key] = m
	return m

static func random_appearance(rng: RandomNumberGenerator, female: bool) -> Dictionary:
	var skins := [Color(0.98, 0.84, 0.72), Color(0.92, 0.74, 0.58), Color(0.8, 0.6, 0.44), Color(0.66, 0.47, 0.32), Color(0.5, 0.34, 0.22), Color(0.36, 0.24, 0.16)]
	var hairs := [Color(0.08, 0.06, 0.05), Color(0.2, 0.13, 0.08), Color(0.36, 0.22, 0.12), Color(0.6, 0.45, 0.25), Color(0.75, 0.62, 0.4), Color(0.5, 0.5, 0.5), Color(0.55, 0.22, 0.1)]
	var shirts := [Color(0.55, 0.45, 0.32), Color(0.35, 0.4, 0.3), Color(0.5, 0.22, 0.18), Color(0.25, 0.3, 0.42), Color(0.7, 0.65, 0.55), Color(0.4, 0.3, 0.45), Color(0.6, 0.5, 0.2)]
	var pants := [Color(0.3, 0.25, 0.2), Color(0.25, 0.22, 0.18), Color(0.35, 0.3, 0.22), Color(0.2, 0.22, 0.25), Color(0.4, 0.33, 0.25)]
	return {
		"skin": skins[rng.randi() % skins.size()], "hair": hairs[rng.randi() % hairs.size()],
		"shirt": shirts[rng.randi() % shirts.size()], "pants": pants[rng.randi() % pants.size()],
		"shoes": Color(0.22, 0.15, 0.1), "female": female,
		"hair_style": rng.randi() % (3 if female else 4), "beard": (not female) and rng.randf() < 0.45,
		"height": rng.randf_range(0.92, 1.07) * (0.96 if female else 1.0), "build": rng.randf_range(0.9, 1.15) * (0.92 if female else 1.0),
	}

func build(appearance: Dictionary) -> void:
	app = appearance
	for c in get_children():
		c.queue_free()
	parts = {}
	_h = app.get("height", 1.0)
	var bld: float = app.get("build", 1.0)
	var skin: Color = app.get("skin", Color(0.85, 0.68, 0.52))
	_skin_mat = cmat(skin, 0.6)
	var shirt_m := cmat(app.get("shirt", Color(0.5, 0.4, 0.3)), 0.9)
	var pants_m := cmat(app.get("pants", Color(0.3, 0.25, 0.2)), 0.9)
	var shoe_m := cmat(app.get("shoes", Color(0.2, 0.14, 0.1)), 0.7)
	var hair_m := cmat(app.get("hair", Color(0.15, 0.1, 0.06)), 0.75)
	rig = Node3D.new()
	add_child(rig)
	rig.scale = Vector3(_h, _h, _h)
	hips = _pivot(rig, Vector3(0, 0.95, 0))
	_hip_y = 0.95
	_part(hips, "pelvis", _sph(0.15), pants_m, Vector3(0, 0.0, 0), Vector3(1.15 * bld, 0.8, 0.8))
	torso = _pivot(hips, Vector3(0, 0.05, 0))
	_part(torso, "chest", _cap(0.16, 0.56), shirt_m, Vector3(0, 0.27, 0), Vector3(1.18 * bld, 1.0, 0.72))
	if app.get("female", false):
		_part(torso, "bust", _sph(0.075), shirt_m, Vector3(0, 0.36, -0.075), Vector3(2.1, 0.9, 0.9))
	_part(torso, "neck", _cap(0.05, 0.16), _skin_mat, Vector3(0, 0.58, 0))
	_part(torso, "collar", _cap(0.075, 0.16), shirt_m, Vector3(0, 0.52, 0), Vector3(1.2, 0.5, 1.0))
	var belt := _part(hips, "belt", _cyl(), cmat(Color(0.18, 0.12, 0.08), 0.6), Vector3(0, 0.07, 0), Vector3(0.36 * bld, 0.05, 0.26))
	belt.visibility_range_end = 30.0
	head = _pivot(torso, Vector3(0, 0.64, 0))
	_part(head, "head", _sph(0.115), _skin_mat, Vector3(0, 0.11, 0), Vector3(0.9, 1.05, 0.98))
	var eye_m := cmat(Color(0.06, 0.05, 0.05), 0.3)
	for sx in [-0.04, 0.04]:
		var e := _part(head, "eye", _sph(0.016), eye_m, Vector3(sx, 0.13, -0.098))
		e.visibility_range_end = 25.0
	var nose := _part(head, "nose", _box(Vector3(0.03, 0.045, 0.04)), _skin_mat, Vector3(0, 0.1, -0.11))
	nose.visibility_range_end = 25.0
	var brow_m := cmat(Color(app.get("hair", Color(0.15, 0.1, 0.06))).darkened(0.2), 0.8)
	for sx in [-0.042, 0.042]:
		var br := _part(head, "brow", _box(Vector3(0.038, 0.009, 0.012)), brow_m, Vector3(sx, 0.155, -0.1))
		br.rotation.z = -sx * 4.0
		br.visibility_range_end = 20.0
	var mouth := _part(head, "mouth", _box(Vector3(0.045, 0.008, 0.01)), cmat(Color(0.45, 0.22, 0.2), 0.6), Vector3(0, 0.055, -0.103))
	mouth.visibility_range_end = 20.0
	for sx in [-0.112, 0.112]:
		var ear := _part(head, "ear", _sph(0.025), _skin_mat, Vector3(sx, 0.11, 0.0), Vector3(0.5, 1.0, 0.8))
		ear.visibility_range_end = 25.0
	var hs: int = app.get("hair_style", 0)
	if hs != 3:
		_part(head, "hair", _sph(0.124, true), hair_m, Vector3(0, 0.13, 0.01), Vector3(0.95, 1.0, 1.02))
		if app.get("female", false) and hs >= 1:
			_part(head, "hair_long", _box(Vector3(0.2, 0.26, 0.06)), hair_m, Vector3(0, 0.02, 0.085))
		elif hs == 2:
			_part(head, "hair_tail", _cap(0.035, 0.18), hair_m, Vector3(0, 0.08, 0.13))
	if app.get("beard", false):
		var bd := _part(head, "beard", _box(Vector3(0.15, 0.08, 0.06)), hair_m, Vector3(0, 0.02, -0.075))
		bd.visibility_range_end = 30.0
	var sw := 0.215 * bld
	l_sh = _pivot(torso, Vector3(-sw, 0.5, 0))
	r_sh = _pivot(torso, Vector3(sw, 0.5, 0))
	for sh in [l_sh, r_sh]:
		_part(sh, "uarm", _cap(0.052, 0.32), shirt_m, Vector3(0, -0.14, 0))
	l_el = _pivot(l_sh, Vector3(0, -0.29, 0))
	r_el = _pivot(r_sh, Vector3(0, -0.29, 0))
	for el in [l_el, r_el]:
		_part(el, "farm", _cap(0.045, 0.28), _skin_mat, Vector3(0, -0.13, 0))
		_part(el, "hand", _sph(0.048), _skin_mat, Vector3(0, -0.29, 0), Vector3(0.9, 1.1, 0.8))
	hand_r = _pivot(r_el, Vector3(0, -0.3, -0.01))
	l_hip = _pivot(hips, Vector3(-0.09, -0.03, 0))
	r_hip = _pivot(hips, Vector3(0.09, -0.03, 0))
	for hp in [l_hip, r_hip]:
		_part(hp, "thigh", _cap(0.072, 0.47), pants_m, Vector3(0, -0.21, 0))
	l_knee = _pivot(l_hip, Vector3(0, -0.44, 0))
	r_knee = _pivot(r_hip, Vector3(0, -0.44, 0))
	for kn in [l_knee, r_knee]:
		_part(kn, "shin", _cap(0.058, 0.46), pants_m, Vector3(0, -0.21, 0))
		_part(kn, "foot", _box(Vector3(0.1, 0.07, 0.24)), shoe_m, Vector3(0, -0.45, -0.045))
	if held_id != "":
		var h := held_id
		held_id = ""
		set_held(h)

func _pivot(parent: Node3D, pos: Vector3) -> Node3D:
	var n := Node3D.new()
	n.position = pos
	parent.add_child(n)
	return n

func _part(parent: Node3D, pname: String, mesh: Mesh, m: Material, pos: Vector3, scl := Vector3.ONE) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = m
	mi.position = pos
	mi.scale = scl
	parent.add_child(mi)
	if not parts.has(pname):
		parts[pname] = []
	parts[pname].append(mi)
	return mi

func _recolor(pname: String, m: Material) -> void:
	for mi in parts.get(pname, []):
		mi.material_override = m

## تحديث الملابس الظاهرة حسب المعدات
func set_equipment(eq: Dictionary) -> void:
	var base_shirt: Color = app.get("shirt", Color(0.5, 0.4, 0.3))
	var base_pants: Color = app.get("pants", Color(0.3, 0.25, 0.2))
	var body = eq.get("body")
	var shirt_m := cmat(base_shirt, 0.9)
	if body != null:
		var c: Color = ItemDB.get_item(body["id"])["color"]
		shirt_m = cmat(c, 0.4 if "armor" in body["id"] else 0.85, 0.7 if "armor" in body["id"] else 0.0)
	for p in ["chest", "uarm", "bust", "collar"]:
		_recolor(p, shirt_m)
	var legs = eq.get("legs")
	var pm := cmat(ItemDB.get_item(legs["id"])["color"] if legs != null else base_pants, 0.85)
	for p in ["thigh", "shin", "pelvis"]:
		_recolor(p, pm)
	var feet = eq.get("feet")
	_recolor("foot", cmat(ItemDB.get_item(feet["id"])["color"] if feet != null else app.get("shoes", Color(0.2, 0.14, 0.1)), 0.7))
	if hat:
		hat.queue_free()
		hat = null
	var hd = eq.get("head")
	if hd != null:
		var hc: Color = ItemDB.get_item(hd["id"])["color"]
		hat = MeshInstance3D.new()
		if hd["id"] == "straw_hat":
			var cm := CylinderMesh.new()
			cm.top_radius = 0.09
			cm.bottom_radius = 0.24
			cm.height = 0.1
			hat.mesh = cm
			hat.position = Vector3(0, 0.25, 0)
		else:
			hat.mesh = _sph(0.135, true)
			hat.position = Vector3(0, 0.14, 0)
		hat.material_override = cmat(hc, 0.9)
		head.add_child(hat)
	if pack:
		pack.queue_free()
		pack = null
	var bk = eq.get("back")
	if bk != null:
		pack = MeshInstance3D.new()
		pack.mesh = _box(Vector3(0.3, 0.38, 0.16))
		pack.material_override = cmat(ItemDB.get_item(bk["id"])["color"], 0.9)
		pack.position = Vector3(0, 0.3, 0.17)
		torso.add_child(pack)

func set_held(item_id: String) -> void:
	if item_id == held_id:
		return
	held_id = item_id
	if held_node:
		held_node.queue_free()
		held_node = null
	if item_id == "" or hand_r == null:
		return
	var key := MeshFactory.held_key(item_id)
	if key == "":
		return
	held_node = Node3D.new()
	var mi := MeshInstance3D.new()
	mi.mesh = MeshFactory.get_mesh(key)
	held_node.add_child(mi)
	held_node.rotation = Vector3(-PI / 2.0, 0, 0)
	var kind: String = ItemDB.tool_of(item_id).get("kind", "")
	if kind == "":
		held_node.scale = Vector3(0.6, 0.6, 0.6)
	if kind == "torch":
		var fl := MeshInstance3D.new()
		fl.mesh = _sph(0.07)
		var fm := StandardMaterial3D.new()
		fm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		fm.albedo_color = Color(2.5, 1.2, 0.3)
		fl.material_override = fm
		fl.position = Vector3(0, 0.6, 0)
		fl.scale = Vector3(1, 1.6, 1)
		fl.name = "Flame"
		held_node.add_child(fl)
	hand_r.add_child(held_node)

func play_swing(kind := "chop") -> void:
	swing_t = 0.0
	swing_kind = kind

func flash_hit() -> void:
	hit_flash = 0.25

func _process(dt: float) -> void:
	if rig == null:
		return
	if not is_visible_in_tree():
		return
	var cam := get_viewport().get_camera_3d()
	if cam and cam.global_position.distance_squared_to(global_position) > 3600.0 and state != "dead" and state != "sleep":
		return
	_animate(dt)

func _animate(dt: float) -> void:
	var walk := clampf(speed / 3.5, 0.0, 1.0)
	var run := clampf((speed - 3.5) / 3.0, 0.0, 1.0)
	phase += dt * (2.0 + speed * 2.1)
	var amp := 0.5 * walk + 0.45 * run
	var s := sin(phase)
	var c := cos(phase)
	rig.rotation = Vector3.ZERO
	rig.position = Vector3.ZERO
	hips.position = Vector3(0, _hip_y, 0)
	torso.rotation = Vector3(0.06 * run, 0, 0)
	head.rotation = Vector3.ZERO
	var la := Vector3.ZERO
	var ra := Vector3.ZERO
	var le := Vector3(0.15, 0, 0)
	var re := Vector3(0.15, 0, 0)
	var lh := Vector3.ZERO
	var rh := Vector3.ZERO
	var lk := Vector3.ZERO
	var rk := Vector3.ZERO
	match state:
		"swim":
			rig.rotation.x = -1.35
			rig.position = Vector3(0, 0.95, 0.6)
			la = Vector3(PI + sin(phase * 0.7) * 1.4, 0, 0)
			ra = Vector3(PI - sin(phase * 0.7) * 1.4, 0, 0)
			lh = Vector3(s * 0.35, 0, 0)
			rh = Vector3(-s * 0.35, 0, 0)
		"sleep", "dead":
			rig.rotation.x = PI / 2.0 if state == "sleep" else -PI / 2.0
			rig.position = Vector3(0, 0.16, -0.85 if state == "sleep" else 0.85)
			la = Vector3(0.1, 0, -0.15)
			ra = Vector3(0.1, 0, 0.15)
			if state == "dead":
				la = Vector3(0.5, 0, -0.9)
				ra = Vector3(0.2, 0, 0.7)
				lh = Vector3(0.1, 0, -0.1)
				head.rotation = Vector3(0, 0.6, 0)
		"sit":
			hips.position.y = _hip_y - 0.45
			lh = Vector3(1.5, 0, -0.08)
			rh = Vector3(1.5, 0, 0.08)
			lk = Vector3(-1.5, 0, 0)
			rk = Vector3(-1.5, 0, 0)
			la = Vector3(0.5, 0, 0)
			ra = Vector3(0.5, 0, 0)
			le = Vector3(0.6, 0, 0)
			re = Vector3(0.6, 0, 0)
		"crouch":
			hips.position.y = _hip_y - 0.32 + absf(c) * 0.02 * walk
			torso.rotation.x = 0.35
			lh = Vector3(1.0 + s * amp * 0.6, 0, 0)
			rh = Vector3(1.0 - s * amp * 0.6, 0, 0)
			lk = Vector3(-1.5 + maxf(0.0, s) * 0.4, 0, 0)
			rk = Vector3(-1.5 + maxf(0.0, -s) * 0.4, 0, 0)
			la = Vector3(0.4, 0, 0)
			ra = Vector3(0.4, 0, 0)
		"work":
			torso.rotation.x = 0.55 + sin(phase * 0.8) * 0.05
			lh = Vector3(0.3, 0, 0)
			rh = Vector3(0.3, 0, 0)
			lk = Vector3(-0.5, 0, 0)
			rk = Vector3(-0.5, 0, 0)
			la = Vector3(0.9 + sin(phase * 1.6) * 0.3, 0, 0)
			ra = Vector3(0.9 - sin(phase * 1.6) * 0.3, 0, 0)
		_:
			hips.position.y = _hip_y + absf(c) * 0.035 * (walk + run) - 0.02 * run
			lh = Vector3(s * amp, 0, 0)
			rh = Vector3(-s * amp, 0, 0)
			lk = Vector3(-maxf(0.0, -s) * amp * 1.4 - 0.05, 0, 0)
			rk = Vector3(-maxf(0.0, s) * amp * 1.4 - 0.05, 0, 0)
			la = Vector3(-s * amp * 0.8, 0, -0.06)
			ra = Vector3(s * amp * 0.8, 0, 0.06)
			le = Vector3(0.2 + run * 0.9, 0, 0)
			re = Vector3(0.2 + run * 0.9, 0, 0)
			if speed < 0.2:
				var br := sin(Time.get_ticks_msec() * 0.002 + get_instance_id()) * 0.02
				torso.rotation.x = br
				la = Vector3(br, 0, -0.08)
				ra = Vector3(-br, 0, 0.08)
			if state == "talk":
				talk_t += dt
				head.rotation.x = sin(talk_t * 5.0) * 0.06
				ra = Vector3(0.6 + sin(talk_t * 3.0) * 0.25, 0, 0.2)
				re = Vector3(0.9, 0, 0)
	# حركة الضرب
	if swing_t >= 0.0:
		swing_t += dt * 2.6
		var t := swing_t
		var arm := 0.3
		if t < 0.4:
			arm = lerpf(0.3, 2.7, t / 0.4)
		elif t < 0.6:
			arm = lerpf(2.7, 0.7, (t - 0.4) / 0.2)
		else:
			arm = lerpf(0.7, 0.3, clampf((t - 0.6) / 0.4, 0.0, 1.0))
		if swing_kind == "thrust":
			arm = 1.4 + sin(clampf(t, 0.0, 1.0) * PI) * 0.3
			re = Vector3(lerpf(1.2, 0.0, sin(clampf(t, 0.0, 1.0) * PI)), 0, 0)
		else:
			re = Vector3(0.3, 0, 0)
		ra = Vector3(arm, 0, 0.1)
		torso.rotation.y = sin(clampf(t, 0.0, 1.0) * PI) * -0.3
		if swing_t >= 1.0:
			swing_t = -1.0
	l_sh.rotation = la
	r_sh.rotation = ra
	l_el.rotation = le
	r_el.rotation = re
	l_hip.rotation = lh
	r_hip.rotation = rh
	l_knee.rotation = lk
	r_knee.rotation = rk
	if hit_flash > 0.0:
		hit_flash -= dt
		var k := 1.0 if hit_flash > 0.0 else 0.0
		rig.position.x += sin(hit_flash * 60.0) * 0.03 * k
	if held_node:
		var fl := held_node.get_node_or_null("Flame")
		if fl:
			fl.scale = Vector3(1.0, 1.4 + sin(Time.get_ticks_msec() * 0.02) * 0.3, 1.0)

func set_head_visible(v: bool) -> void:
	if head:
		head.visible = v
