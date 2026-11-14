class_name CarModel
extends RefCounted
## Builds stylised car bodies by lofting cross-sections. Vertex colours carry
## material masks (R accent, G glass, B dark trim) for car.gdshader.

const CAR_SHADER := preload("res://shaders/car.gdshader")

## Sections: [z, half_width_bottom, half_width_top, y_bottom, y_top, cabin]
const DESIGNS := [
	{ # Striker - balanced sports coupe
		"sections": [
			[-0.77, 0.24, 0.18, 0.05, 0.13, 0], [-0.69, 0.38, 0.30, 0.02, 0.18, 0],
			[-0.50, 0.42, 0.36, 0.02, 0.215, 0], [-0.25, 0.42, 0.35, 0.02, 0.25, 0],
			[-0.05, 0.42, 0.27, 0.02, 0.41, 1], [0.17, 0.43, 0.28, 0.02, 0.42, 1],
			[0.33, 0.44, 0.36, 0.03, 0.30, 0], [0.48, 0.42, 0.35, 0.05, 0.28, 0]],
		"wing": [Vector3(0, 0.40, 0.43), Vector3(0.86, 0.03, 0.15)],
		"tire_w": 0.17,
	},
	{ # Bulldog - tall, short, rugged
		"sections": [
			[-0.70, 0.36, 0.30, 0.04, 0.24, 0], [-0.62, 0.43, 0.38, 0.02, 0.27, 0],
			[-0.40, 0.43, 0.38, 0.02, 0.29, 0], [-0.22, 0.43, 0.36, 0.02, 0.31, 0],
			[-0.08, 0.43, 0.33, 0.02, 0.45, 1], [0.24, 0.44, 0.34, 0.02, 0.46, 1],
			[0.36, 0.44, 0.38, 0.03, 0.38, 0], [0.46, 0.43, 0.37, 0.05, 0.36, 0]],
		"wing": [Vector3(0, 0.47, 0.20), Vector3(0.70, 0.05, 0.10)],
		"tire_w": 0.2,
	},
	{ # Viper - long, low wedge
		"sections": [
			[-0.81, 0.22, 0.16, 0.05, 0.10, 0], [-0.72, 0.40, 0.32, 0.02, 0.14, 0],
			[-0.48, 0.43, 0.36, 0.02, 0.18, 0], [-0.20, 0.43, 0.34, 0.02, 0.22, 0],
			[0.00, 0.43, 0.26, 0.02, 0.35, 1], [0.20, 0.44, 0.27, 0.02, 0.355, 1],
			[0.36, 0.45, 0.38, 0.03, 0.26, 0], [0.52, 0.44, 0.38, 0.05, 0.25, 0]],
		"wing": [Vector3(0, 0.42, 0.49), Vector3(0.92, 0.025, 0.2)],
		"tire_w": 0.17,
	},
]


static func _ring(sec: Array) -> Array:
	var wb: float = sec[1]
	var wt: float = sec[2]
	var yb: float = sec[3]
	var yt: float = sec[4]
	var hh := yt - yb
	var right := [
		Vector2(0.0, yb), Vector2(wb * 0.85, yb), Vector2(wb, yb + 0.035),
		Vector2(wb, yb + hh * 0.42), Vector2(lerpf(wb, wt, 0.55), yb + hh * 0.6),
		Vector2(wt, yt - 0.045), Vector2(wt * 0.72, yt - 0.005), Vector2(wt * 0.22, yt), Vector2(0.0, yt)]
	var pts: Array = []
	for p in right:
		pts.append(p)
	for i in range(right.size() - 2, 0, -1):
		var q: Vector2 = right[i]
		pts.append(Vector2(-q.x, q.y))
	return pts  # 16 points, closed loop


## Mask colour for ring segment k (between ring points k and k+1) of a body
## segment between two sections.
static func _seg_mask(k: int, cabin_a: int, cabin_b: int) -> Color:
	var kk := k if k < 8 else 15 - k
	if kk <= 1:
		return Color(0, 0, 1)            # underside / skirt trim
	if kk == 3:
		return Color(1, 0, 0)            # shoulder accent stripe
	var cabin := cabin_a + cabin_b
	if kk == 4 and cabin >= 1:
		return Color(0, 1, 0)            # side windows
	if kk >= 5 and cabin == 1:
		return Color(0, 1, 0)            # windshield / rear window
	if kk == 7 and cabin != 1:
		return Color(1, 0, 0)            # racing stripe
	return Color(0, 0, 0)


static func build(design: int, paint: Color, accent: Color) -> Node3D:
	var d: Dictionary = DESIGNS[clampi(design, 0, DESIGNS.size() - 1)]
	var secs: Array = d["sections"]
	var root := Node3D.new()
	root.name = "CarModel"

	# --- loft grid
	var grid: Array = []
	for s in secs:
		var ring := _ring(s)
		var row: Array = []
		for p in ring:
			row.append(Vector3(p.x, p.y, s[0]))
		grid.append(row)
	var ns := grid.size()
	var nr: int = grid[0].size()
	var normals: Array = []
	for i in range(ns):
		var row: Array = []
		for k in range(nr):
			var a: Vector3 = grid[i][(k + 1) % nr] - grid[i][(k - 1 + nr) % nr]
			var b: Vector3 = grid[mini(i + 1, ns - 1)][k] - grid[maxi(i - 1, 0)][k]
			var n := a.cross(b).normalized()
			var center := Vector3(0, (secs[i][3] + secs[i][4]) * 0.5, secs[i][0])
			if n.dot(grid[i][k] - center) < 0.0:
				n = -n
			row.append(n)
		normals.append(row)

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in range(ns - 1):
		for k in range(nr):
			var k2 := (k + 1) % nr
			var col := _seg_mask(k, secs[i][5], secs[i + 1][5])
			var quad := [[i, k], [i + 1, k], [i + 1, k2], [i, k2]]
			var center: Vector3 = (grid[i][k] + grid[i + 1][k2]) * 0.5
			var mid_c := Vector3(0, center.y * 0.5 + 0.1, center.z)
			var face_n: Vector3 = (grid[i + 1][k] - grid[i][k]).cross(grid[i][k2] - grid[i][k])
			# Godot front faces are clockwise: the right-handed normal must point inward.
			var rh_outward := face_n.dot(center - mid_c) > 0.0
			var order := [0, 2, 1, 0, 3, 2] if rh_outward else [0, 1, 2, 0, 2, 3]
			for o in order:
				var ij: Array = quad[o]
				st.set_color(col)
				st.set_normal(normals[ij[0]][ij[1]])
				st.add_vertex(grid[ij[0]][ij[1]])
	# end caps (front grille and rear panel)
	for cap in [0, ns - 1]:
		var row: Array = grid[cap]
		var c := Vector3.ZERO
		for p in row:
			c += p
		c /= float(nr)
		var nrm := Vector3(0, 0, -1) if cap == 0 else Vector3(0, 0, 1)
		for k in range(nr):
			var a: Vector3 = row[k]
			var b: Vector3 = row[(k + 1) % nr]
			var tri := [c, a, b]
			var fn := (a - c).cross(b - c)
			if fn.dot(nrm) > 0.0:
				tri = [c, b, a]
			for p in tri:
				st.set_color(Color(0, 0, 1))
				st.set_normal(nrm)
				st.add_vertex(p)
	var body := MeshInstance3D.new()
	body.name = "Body"
	body.mesh = st.commit()
	var mat := ShaderMaterial.new()
	mat.shader = CAR_SHADER
	mat.set_shader_parameter("paint", Vector3(paint.r, paint.g, paint.b))
	mat.set_shader_parameter("accent", Vector3(accent.r, accent.g, accent.b))
	body.material_override = mat
	root.add_child(body)
	root.set_meta("body_mat", mat)

	# --- wing / roof bar
	var accent_mat := StandardMaterial3D.new()
	accent_mat.albedo_color = accent
	accent_mat.metallic = 0.5
	accent_mat.roughness = 0.3
	var dark := StandardMaterial3D.new()
	dark.albedo_color = Color(0.03, 0.03, 0.035)
	dark.roughness = 0.6
	var wing: Array = d["wing"]
	var wp: Vector3 = wing[0]
	var ws: Vector3 = wing[1]
	_mesh_box(root, wp, ws, accent_mat)
	var last: Array = secs[ns - 2]
	for sx in [-1.0, 1.0]:
		var top_y: float = last[4]
		var strut_h := wp.y - top_y + 0.02
		if strut_h > 0.02:
			_mesh_box(root, Vector3(sx * ws.x * 0.32, top_y + strut_h * 0.5 - 0.02, wp.z - 0.01), Vector3(0.03, strut_h, 0.08), dark)
	root.set_meta("accent_mat", accent_mat)

	# --- lights
	var head := StandardMaterial3D.new()
	head.albedo_color = Color(1, 1, 1)
	head.emission_enabled = true
	head.emission = Color(0.85, 0.92, 1.0)
	head.emission_energy_multiplier = 4.0
	var tail := StandardMaterial3D.new()
	tail.albedo_color = Color(1, 0.1, 0.1)
	tail.emission_enabled = true
	tail.emission = Color(1.0, 0.08, 0.05)
	tail.emission_energy_multiplier = 3.0
	var front: Array = secs[1]
	var back: Array = secs[ns - 1]
	for sx in [-1.0, 1.0]:
		_mesh_box(root, Vector3(sx * front[2] * 0.72, front[4] - 0.045, float(front[0]) - 0.012),
			Vector3(0.13, 0.035, 0.03), head)
		_mesh_box(root, Vector3(sx * back[2] * 0.65, back[4] - 0.06, float(back[0]) + 0.005),
			Vector3(0.2, 0.035, 0.02), tail)
	root.set_meta("tail_mat", tail)
	# exhaust nozzle
	var noz := MeshInstance3D.new()
	var nm := CylinderMesh.new()
	nm.top_radius = 0.075
	nm.bottom_radius = 0.09
	nm.height = 0.08
	nm.radial_segments = 12
	noz.mesh = nm
	noz.material_override = dark
	noz.rotation_degrees = Vector3(90, 0, 0)
	var ex_y: float = back[3] + (float(back[4]) - float(back[3])) * 0.35
	noz.position = Vector3(0, ex_y, float(back[0]) + 0.03)
	root.add_child(noz)
	root.set_meta("exhaust", Vector3(0, ex_y, float(back[0]) + 0.07))

	# --- wheels
	var tire_mat := StandardMaterial3D.new()
	tire_mat.albedo_color = Color(0.04, 0.04, 0.045)
	tire_mat.roughness = 0.85
	var rim_mat := StandardMaterial3D.new()
	rim_mat.albedo_color = accent.lerp(Color(0.8, 0.82, 0.86), 0.5)
	rim_mat.metallic = 0.9
	rim_mat.roughness = 0.25
	var tw: float = d["tire_w"]
	var wheels: Array = []
	for i in range(4):
		var r: float = CarSim.WHEEL_RADIUS[i]
		var pivot := Node3D.new()
		pivot.name = "Wheel%d" % i
		var conn: Vector3 = CarSim.WHEEL_CONN[i]
		pivot.position = Vector3(conn.x * 1.02, -0.17 + r, conn.z)
		root.add_child(pivot)
		var spin := Node3D.new()
		pivot.add_child(spin)
		var tire := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = r
		cm.bottom_radius = r
		cm.height = tw
		cm.radial_segments = 18
		tire.mesh = cm
		tire.material_override = tire_mat
		tire.rotation_degrees = Vector3(0, 0, 90)
		spin.add_child(tire)
		var rim := MeshInstance3D.new()
		var rm := CylinderMesh.new()
		rm.top_radius = r * 0.62
		rm.bottom_radius = r * 0.62
		rm.height = tw + 0.01
		rm.radial_segments = 6
		rim.mesh = rm
		rim.material_override = rim_mat
		rim.rotation_degrees = Vector3(0, 0, 90)
		spin.add_child(rim)
		wheels.append(pivot)
	root.set_meta("wheels", wheels)
	return root


static func _mesh_box(parent: Node3D, pos: Vector3, size: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = mat
	mi.position = pos
	parent.add_child(mi)
	return mi
