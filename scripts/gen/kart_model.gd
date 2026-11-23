class_name KartModel
extends RefCounted
## Procedural kart + driver models. Kart faces -Z, origin on the ground between
## the axles. Returns a Node3D with named parts the KartVisual animates.

const FRONT_Z := -0.62
const REAR_Z := 0.56
const TRACK_X := 0.58
const FRONT_R := 0.25
const REAR_R := 0.31


static func _c(col: Color, a := 1.0) -> Callable:
	return func(_t: float, _a: float, _p: Vector3) -> Color: return Color(col.r, col.g, col.b, a)


static func build(ch: Dictionary) -> Node3D:
	var root := Node3D.new()
	root.name = "KartModel"
	var paint: Color = ch.get("kart", Color(0.9, 0.2, 0.1))
	var accent: Color = ch.get("accent", Color(1, 1, 1))
	var dark := Color(0.13, 0.13, 0.15)
	var metal := Color(0.75, 0.76, 0.8)
	var body := MeshBuilder.new()
	var mech := MeshBuilder.new()
	var nz := MeshLib.make_noise(3, 1.0)
	# ---- chassis
	MeshLib.box(mech, Transform3D(Basis(), Vector3(0, 0.17, -0.02)), Vector3(0.95, 0.08, 1.7), dark, 0.08)
	MeshLib.blob(body, Vector3(0, 0.34, -0.72), Vector3(0.43, 0.19, 0.5), 2, null, 0.0, paint * 0.75, paint)
	MeshLib.blob(body, Vector3(0, 0.42, -0.42), Vector3(0.34, 0.16, 0.34), 2, null, 0.0, paint * 0.8, paint * 1.08)
	for s: float in [-1.0, 1.0]:
		MeshLib.blob(body, Vector3(0.44 * s, 0.33, 0.02), Vector3(0.18, 0.15, 0.52), 2, null, 0.0, paint * 0.7, paint)
		MeshLib.blob(body, Vector3(0.47 * s, 0.4, 0.05), Vector3(0.1, 0.05, 0.4), 1, null, 0.0, accent * 0.9, accent)
	# number badge
	MeshLib.blob(body, Vector3(0, 0.5, -0.83), Vector3(0.14, 0.05, 0.12), 1, null, 0.0, Color(0.95, 0.95, 0.92), Color(1, 1, 1))
	# seat
	MeshLib.blob(body, Vector3(0, 0.42, 0.24), Vector3(0.27, 0.12, 0.22), 1, null, 0.0, dark, dark * 1.4)
	MeshLib.blob(body, Vector3(0, 0.66, 0.38), Vector3(0.26, 0.26, 0.08), 1, null, 0.0, dark, dark * 1.5)
	# bumpers
	var fb := PackedVector3Array([Vector3(-0.6, 0.24, -0.92), Vector3(-0.3, 0.24, -1.06), Vector3(0.3, 0.24, -1.06), Vector3(0.6, 0.24, -0.92)])
	MeshLib.tube(mech, fb, PackedFloat32Array([0.05, 0.05, 0.05, 0.05]), 6, _c(metal), 1.0, true)
	var rb := PackedVector3Array([Vector3(-0.7, 0.26, 0.86), Vector3(-0.3, 0.26, 0.98), Vector3(0.3, 0.26, 0.98), Vector3(0.7, 0.26, 0.86)])
	MeshLib.tube(mech, rb, PackedFloat32Array([0.05, 0.05, 0.05, 0.05]), 6, _c(metal), 1.0, true)
	# engine + exhausts
	MeshLib.box(mech, Transform3D(Basis(), Vector3(0, 0.46, 0.64)), Vector3(0.52, 0.28, 0.34), Color(0.35, 0.35, 0.38), 0.05)
	MeshLib.box(mech, Transform3D(Basis(), Vector3(0, 0.63, 0.64)), Vector3(0.42, 0.08, 0.26), Color(0.8, 0.25, 0.15))
	for s: float in [-1.0, 1.0]:
		var ex := PackedVector3Array([Vector3(0.2 * s, 0.5, 0.74), Vector3(0.25 * s, 0.56, 0.92), Vector3(0.27 * s, 0.68, 1.04)])
		MeshLib.tube(mech, ex, PackedFloat32Array([0.05, 0.055, 0.07]), 7, _c(metal), 1.0, false)
	# rear wing
	for s: float in [-1.0, 1.0]:
		MeshLib.box(mech, Transform3D(Basis(), Vector3(0.32 * s, 0.82, 0.9)), Vector3(0.05, 0.36, 0.12), dark)
	MeshLib.box(body, Transform3D(Basis(Vector3.RIGHT, -0.12), Vector3(0, 1.0, 0.94)), Vector3(1.05, 0.05, 0.32), accent, 0.0)
	for s: float in [-1.0, 1.0]:
		MeshLib.box(body, Transform3D(Basis(), Vector3(0.54 * s, 0.98, 0.94)), Vector3(0.04, 0.2, 0.38), paint)
	# steering column + wheel
	MeshLib.tube(mech, PackedVector3Array([Vector3(0, 0.42, -0.42), Vector3(0, 0.62, -0.14)]), PackedFloat32Array([0.025, 0.025]), 5, _c(dark), 1.0, false)
	var bmi := MeshInstance3D.new()
	bmi.name = "Body"
	bmi.mesh = body.commit(null, Mats.kart_paint(paint))
	root.add_child(bmi)
	var mmi := MeshInstance3D.new()
	mmi.name = "Mech"
	mmi.mesh = mech.commit(null, Mats.vcol(0.35, 0.6, "kartmetal"))
	root.add_child(mmi)
	# steering wheel (animated)
	var sw := Node3D.new()
	sw.name = "SteeringWheel"
	sw.position = Vector3(0, 0.65, -0.12)
	sw.rotation = Vector3(-0.9, 0, 0)
	root.add_child(sw)
	var swm := MeshBuilder.new()
	var ring := PackedVector3Array()
	var rr := PackedFloat32Array()
	for i in 17:
		var a := TAU * float(i) / 16.0
		ring.append(Vector3(cos(a) * 0.15, 0, sin(a) * 0.15))
		rr.append(0.022)
	MeshLib.tube(swm, ring, rr, 5, _c(dark), 1.0, false)
	MeshLib.box(swm, Transform3D(), Vector3(0.28, 0.03, 0.04), dark)
	var swmi := MeshInstance3D.new()
	swmi.mesh = swm.commit(null, Mats.vcol(0.5))
	sw.add_child(swmi)
	# wheels
	for w in [["WheelFL", -TRACK_X, FRONT_Z, FRONT_R, 0.2], ["WheelFR", TRACK_X, FRONT_Z, FRONT_R, 0.2],
			["WheelRL", -TRACK_X - 0.04, REAR_Z, REAR_R, 0.28], ["WheelRR", TRACK_X + 0.04, REAR_Z, REAR_R, 0.28]]:
		var pivot := Node3D.new()
		pivot.name = w[0]
		pivot.position = Vector3(w[1], w[3], w[2])
		root.add_child(pivot)
		var spin := Node3D.new()
		spin.name = "Spin"
		pivot.add_child(spin)
		var mi := MeshInstance3D.new()
		mi.mesh = _wheel_mesh(w[3], w[4], accent)
		mi.rotation = Vector3(0, 0, PI * 0.5)
		spin.add_child(mi)
	# exhaust anchor points for flames
	for s: float in [-1.0, 1.0]:
		var ex := Marker3D.new()
		ex.name = "ExhaustL" if s < 0 else "ExhaustR"
		ex.position = Vector3(0.27 * s, 0.7, 1.08)
		root.add_child(ex)
	var drv := build_driver(ch)
	drv.position = Vector3(0, 0.38, 0.2)
	root.add_child(drv)
	return root


static var _wheel_cache := {}


static func _wheel_mesh(r: float, w: float, rim_col: Color) -> ArrayMesh:
	var key := "%s_%s_%s" % [r, w, rim_col.to_html()]
	if _wheel_cache.has(key):
		return _wheel_cache[key]
	var tire := MeshBuilder.new()
	var hw := w * 0.5
	var prof := PackedVector2Array([Vector2(r * 0.62, -hw), Vector2(r * 0.9, -hw), Vector2(r, -hw * 0.6), Vector2(r * 1.02, 0), Vector2(r, hw * 0.6), Vector2(r * 0.9, hw), Vector2(r * 0.62, hw)])
	MeshLib.lathe(tire, prof, 18, Transform3D(), func(t: float, a: float, _p: Vector3) -> Color:
		var tread := 0.8 if int(a / TAU * 24.0) % 2 == 0 else 1.0
		var k := 0.14 * (tread if t > 0.25 and t < 0.75 else 1.0)
		return Color(k, k, k * 1.05))
	var rim := MeshBuilder.new()
	var rp := PackedVector2Array([Vector2(0.0, hw * 0.9), Vector2(r * 0.25, hw * 0.95), Vector2(r * 0.6, hw * 0.7), Vector2(r * 0.64, -hw * 0.7), Vector2(r * 0.25, -hw * 0.95), Vector2(0.0, -hw * 0.9)])
	MeshLib.lathe(rim, rp, 10, Transform3D(), func(t: float, _a: float, _p: Vector3) -> Color:
		return rim_col.lerp(Color(0.85, 0.85, 0.9), 0.3) if t < 0.5 else Color(0.8, 0.8, 0.85))
	# tire + rim in one surface: one draw per wheel instead of two
	tire.append_builder(rim, Transform3D())
	var am := ArrayMesh.new()
	tire.commit(am, Mats.vcol(0.6, 0.2, "wheel"))
	_wheel_cache[key] = am
	return am


static func build_driver(ch: Dictionary) -> Node3D:
	var root := Node3D.new()
	root.name = "Driver"
	var fur: Color = ch.get("fur", Color(0.8, 0.5, 0.2))
	var accent: Color = ch.get("accent", Color(1, 1, 1))
	var kart_col: Color = ch.get("kart", Color(0.9, 0.2, 0.1))
	var jacket := kart_col.lerp(Color(0.1, 0.1, 0.12), 0.35)
	var mb := MeshBuilder.new()
	# torso + arms + gloves
	MeshLib.blob(mb, Vector3(0, 0.36, 0.0), Vector3(0.25, 0.3, 0.2), 2, null, 0.0, jacket * 0.8, jacket)
	MeshLib.blob(mb, Vector3(0, 0.45, -0.17), Vector3(0.12, 0.08, 0.04), 1, null, 0.0, accent, accent)
	for s: float in [-1.0, 1.0]:
		var arm := PackedVector3Array([Vector3(0.22 * s, 0.52, 0.0), Vector3(0.27 * s, 0.38, -0.2), Vector3(0.14 * s, 0.32, -0.32)])
		MeshLib.tube(mb, arm, PackedFloat32Array([0.075, 0.065, 0.06]), 6, _c(jacket), 1.0, false)
		MeshLib.blob(mb, Vector3(0.13 * s, 0.32, -0.34), Vector3(0.065, 0.06, 0.07), 1, null, 0.0, Color(0.95, 0.95, 0.95), Color(1, 1, 1))
		MeshLib.blob(mb, Vector3(0.16 * s, 0.02, -0.38), Vector3(0.08, 0.07, 0.13), 1, null, 0.0, Color(0.2, 0.2, 0.22), Color(0.3, 0.3, 0.32))
	var bmi := MeshInstance3D.new()
	bmi.mesh = mb.commit(null, Mats.vcol(0.75, 0.0, "driver"))
	root.add_child(bmi)
	var head := Node3D.new()
	head.name = "Head"
	head.position = Vector3(0, 0.82, -0.02)
	root.add_child(head)
	var hm := MeshBuilder.new()
	var species: String = ch.get("species", "fox")
	_head(hm, species, fur, accent, kart_col)
	var hmi := MeshInstance3D.new()
	hmi.mesh = hm.commit(null, Mats.vcol(0.6, 0.0, "head"))
	head.add_child(hmi)
	# scarf trailing behind (animated by KartVisual via its pivot)
	var scarf := Node3D.new()
	scarf.name = "Scarf"
	scarf.position = Vector3(0, 0.62, 0.12)
	root.add_child(scarf)
	var sm := MeshBuilder.new()
	MeshLib.blob(sm, Vector3(0, 0, -0.05), Vector3(0.17, 0.05, 0.14), 1, null, 0.0, accent * 0.85, accent)
	for i in 4:
		MeshLib.box(sm, Transform3D(Basis(Vector3.RIGHT, 0.25 + i * 0.1), Vector3(0.06, -0.02 - i * 0.05, 0.12 + i * 0.13)), Vector3(0.1, 0.02, 0.14), accent * (1.0 - i * 0.06))
	var smi := MeshInstance3D.new()
	smi.mesh = sm.commit(null, Mats.vcol(0.9, 0.0, "scarf"))
	scarf.add_child(smi)
	return root


static func _head(mb: MeshBuilder, species: String, fur: Color, accent: Color, kart_col: Color) -> void:
	var white := Color(0.97, 0.97, 0.95)
	var black := Color(0.05, 0.05, 0.06)
	var head_r := Vector3(0.24, 0.22, 0.22)
	if species == "frog":
		head_r = Vector3(0.28, 0.18, 0.24)
	MeshLib.blob(mb, Vector3.ZERO, head_r, 2, null, 0.0, fur * 0.8, fur * 1.05)
	var eye_y := 0.04
	var eye_x := 0.095
	var eye_z := -0.19
	var eye_r := 0.06
	match species:
		"fox":
			MeshLib.blob(mb, Vector3(0, -0.06, -0.2), Vector3(0.11, 0.08, 0.15), 1, null, 0.0, accent * 0.9, accent)
			MeshLib.blob(mb, Vector3(0, -0.03, -0.35), Vector3(0.035, 0.03, 0.03), 0, null, 0.0, black, black)
			for s: float in [-1.0, 1.0]:
				MeshLib.tube(mb, PackedVector3Array([Vector3(0.13 * s, 0.14, 0.0), Vector3(0.2 * s, 0.38, 0.02)]), PackedFloat32Array([0.075, 0.0]), 5,
					func(t: float, _a: float, _p: Vector3) -> Color: return fur.lerp(black, smoothstep(0.6, 0.9, t)))
		"raccoon":
			MeshLib.blob(mb, Vector3(0, 0.03, -0.17), Vector3(0.21, 0.07, 0.08), 1, null, 0.0, accent, accent)
			MeshLib.blob(mb, Vector3(0, -0.07, -0.19), Vector3(0.09, 0.07, 0.1), 1, null, 0.0, white * 0.9, white)
			MeshLib.blob(mb, Vector3(0, -0.04, -0.3), Vector3(0.03, 0.025, 0.025), 0, null, 0.0, black, black)
			for s: float in [-1.0, 1.0]:
				MeshLib.blob(mb, Vector3(0.16 * s, 0.2, 0.03), Vector3(0.08, 0.08, 0.04), 1, null, 0.0, fur * 0.6, fur)
		"frog":
			eye_y = 0.16
			eye_x = 0.13
			eye_z = -0.1
			eye_r = 0.085
			for s: float in [-1.0, 1.0]:
				MeshLib.blob(mb, Vector3(eye_x * s, eye_y - 0.02, eye_z + 0.02), Vector3(0.1, 0.09, 0.1), 1, null, 0.0, fur * 0.9, fur)
			MeshLib.blob(mb, Vector3(0, -0.09, -0.2), Vector3(0.2, 0.025, 0.06), 1, null, 0.0, accent * 0.8, accent)
		"bear":
			MeshLib.blob(mb, Vector3(0, -0.07, -0.19), Vector3(0.11, 0.08, 0.11), 1, null, 0.0, accent * 0.9, accent)
			MeshLib.blob(mb, Vector3(0, -0.04, -0.3), Vector3(0.045, 0.035, 0.03), 0, null, 0.0, black, black)
			for s: float in [-1.0, 1.0]:
				MeshLib.blob(mb, Vector3(0.17 * s, 0.19, 0.02), Vector3(0.075, 0.075, 0.045), 1, null, 0.0, fur * 0.7, fur)
		"owl":
			eye_r = 0.075
			eye_x = 0.1
			MeshLib.blob(mb, Vector3(0, 0.02, -0.12), Vector3(0.22, 0.17, 0.12), 1, null, 0.0, accent * 0.9, accent)
			MeshLib.tube(mb, PackedVector3Array([Vector3(0, -0.02, -0.22), Vector3(0, -0.1, -0.3)]), PackedFloat32Array([0.04, 0.0]), 4, _c(Color(1.0, 0.75, 0.2)))
			for s: float in [-1.0, 1.0]:
				MeshLib.tube(mb, PackedVector3Array([Vector3(0.14 * s, 0.15, 0.0), Vector3(0.22 * s, 0.32, 0.05)]), PackedFloat32Array([0.05, 0.0]), 4, _c(fur * 0.8))
		"rabbit":
			MeshLib.blob(mb, Vector3(0, -0.07, -0.18), Vector3(0.09, 0.07, 0.09), 1, null, 0.0, white, white)
			MeshLib.blob(mb, Vector3(0, -0.04, -0.27), Vector3(0.03, 0.022, 0.02), 0, null, 0.0, Color(1, 0.5, 0.6), Color(1, 0.6, 0.7))
			for s: float in [-1.0, 1.0]:
				MeshLib.tube(mb, PackedVector3Array([Vector3(0.08 * s, 0.15, 0.03), Vector3(0.1 * s, 0.35, 0.06), Vector3(0.14 * s, 0.52, 0.12)]), PackedFloat32Array([0.05, 0.055, 0.02]), 6,
					func(_t: float, a: float, _p: Vector3) -> Color: return accent if absf(a - PI * 1.5) < 0.8 else fur)
		"boar":
			MeshLib.tube(mb, PackedVector3Array([Vector3(0, -0.04, -0.15), Vector3(0, -0.05, -0.32)]), PackedFloat32Array([0.1, 0.085]), 8, _c(fur.lerp(Color(0.9, 0.6, 0.55), 0.5)))
			for s: float in [-1.0, 1.0]:
				MeshLib.tube(mb, PackedVector3Array([Vector3(0.07 * s, -0.1, -0.28), Vector3(0.1 * s, -0.02, -0.34), Vector3(0.12 * s, 0.05, -0.33)]), PackedFloat32Array([0.022, 0.016, 0.0]), 4, _c(white))
				MeshLib.blob(mb, Vector3(0.16 * s, 0.18, 0.02), Vector3(0.06, 0.09, 0.03), 1, null, 0.0, fur * 0.7, fur)
		"otter":
			MeshLib.blob(mb, Vector3(0, -0.06, -0.18), Vector3(0.14, 0.08, 0.1), 1, null, 0.0, accent * 0.9, accent)
			MeshLib.blob(mb, Vector3(0, -0.03, -0.28), Vector3(0.04, 0.03, 0.025), 0, null, 0.0, black, black)
			for s: float in [-1.0, 1.0]:
				MeshLib.blob(mb, Vector3(0.19 * s, 0.1, 0.05), Vector3(0.045, 0.045, 0.03), 1, null, 0.0, fur * 0.7, fur)
				for w in 3:
					MeshLib.tube(mb, PackedVector3Array([Vector3(0.08 * s, -0.06 + w * 0.02, -0.25), Vector3(0.25 * s, -0.03 + w * 0.04, -0.22)]), PackedFloat32Array([0.006, 0.003]), 3, _c(white))
	# eyes
	for s: float in [-1.0, 1.0]:
		var ep := Vector3(eye_x * s, eye_y, eye_z)
		MeshLib.blob(mb, ep, Vector3.ONE * eye_r, 1, null, 0.0, white * 0.9, white)
		MeshLib.blob(mb, ep + Vector3(0.0, 0.0, -eye_r * 0.7), Vector3.ONE * eye_r * 0.55, 1, null, 0.0, black, black)
		MeshLib.blob(mb, ep + Vector3(0.012 * s, 0.018, -eye_r * 1.05), Vector3.ONE * eye_r * 0.18, 0, null, 0.0, white, white)
	# helmet shell + goggles (pushed up)
	if species != "frog":
		MeshLib.blob(mb, Vector3(0, 0.1, 0.04), Vector3(0.255, 0.16, 0.25), 2, null, 0.0, kart_col * 0.85, kart_col * 1.1)
		var band := PackedVector3Array()
		var br := PackedFloat32Array()
		for i in 13:
			var a := lerpf(-PI * 0.95, -PI * 0.05, float(i) / 12.0)
			band.append(Vector3(cos(a) * 0.255, 0.16, sin(a) * 0.24))
			br.append(0.02)
		MeshLib.tube(mb, band, br, 4, _c(Color(0.2, 0.2, 0.22)), 1.0, false)
		for s: float in [-1.0, 1.0]:
			MeshLib.blob(mb, Vector3(0.09 * s, 0.19, -0.2), Vector3(0.07, 0.055, 0.04), 1, null, 0.0, Color(0.3, 0.75, 0.95), Color(0.75, 0.95, 1.0))
	else:
		MeshLib.blob(mb, Vector3(0, 0.08, 0.08), Vector3(0.2, 0.1, 0.16), 1, null, 0.0, kart_col * 0.85, kart_col)
