class_name MeshKit
extends RefCounted
## أدوات بناء المجسمات الإجرائية (أنابيب بمقاطع متغيرة، مجسمات بيضاوية، صناديق) بألوان الرؤوس.


## يضيف أنبوباً على المحور Y إلى SurfaceTool.
## rings: مصفوفة من [y, rx, rz, Color] وقد تحتوي إزاحة اختيارية [.., ox, oz]
## الطرفان يُغلقان تلقائياً بقبة صغيرة.
static func add_tube(st: SurfaceTool, rings: Array, seg: int = 12, xf: Transform3D = Transform3D.IDENTITY,
		cap_start: bool = true, cap_end: bool = true) -> void:
	var rr: Array = []
	if cap_start:
		var f: Array = rings[0]
		var dir0: float = signf(float(rings[0][0]) - float(rings[1][0]))
		var cap_h: float = minf(float(f[1]), float(f[2])) * 0.55
		rr.append([float(f[0]) + dir0 * cap_h, 0.001, 0.001, f[3], _o(f, 4), _o(f, 5)])
		rr.append([float(f[0]) + dir0 * cap_h * 0.75, float(f[1]) * 0.6, float(f[2]) * 0.6, f[3], _o(f, 4), _o(f, 5)])
	for r in rings:
		rr.append([r[0], r[1], r[2], r[3], _o(r, 4), _o(r, 5)])
	if cap_end:
		var l: Array = rings[rings.size() - 1]
		var dir1: float = signf(float(l[0]) - float(rings[rings.size() - 2][0]))
		var cap_h2: float = minf(float(l[1]), float(l[2])) * 0.55
		rr.append([float(l[0]) + dir1 * cap_h2 * 0.75, float(l[1]) * 0.6, float(l[2]) * 0.6, l[3], _o(l, 4), _o(l, 5)])
		rr.append([float(l[0]) + dir1 * cap_h2, 0.001, 0.001, l[3], _o(l, 4), _o(l, 5)])
	var n := rr.size()
	# هل الأنبوب يتجه للأسفل أم للأعلى؟ (لتحديد اتجاه الأوجه)
	var down: bool = float(rr[n - 1][0]) < float(rr[0][0])
	var verts: Array = []
	var cols: Array = []
	for i in n:
		var r: Array = rr[i]
		for j in seg:
			var a := TAU * j / seg
			verts.append(xf * Vector3(cos(a) * float(r[1]) + float(r[4]), float(r[0]), sin(a) * float(r[2]) + float(r[5])))
			cols.append(r[3])
	for i in n - 1:
		for j in seg:
			var j2 := (j + 1) % seg
			var a0 := i * seg + j
			var a1 := i * seg + j2
			var b0 := (i + 1) * seg + j
			var b1 := (i + 1) * seg + j2
			# ترتيب عقارب الساعة = الوجه الأمامي في Godot
			if down:
				_tri(st, verts, cols, a0, b0, a1)
				_tri(st, verts, cols, a1, b0, b1)
			else:
				_tri(st, verts, cols, a0, a1, b0)
				_tri(st, verts, cols, a1, b1, b0)


static func _o(r: Array, i: int) -> float:
	return float(r[i]) if r.size() > i else 0.0


static func _tri(st: SurfaceTool, verts: Array, cols: Array, a: int, b: int, c: int) -> void:
	st.set_smooth_group(0)
	st.set_color(cols[a])
	st.add_vertex(verts[a])
	st.set_color(cols[b])
	st.add_vertex(verts[b])
	st.set_color(cols[c])
	st.add_vertex(verts[c])


## مجسم بيضاوي بلون واحد أو بدالة لون (n: الاتجاه الطبيعي للنقطة)
static func add_ellipsoid(st: SurfaceTool, center: Vector3, radii: Vector3, color: Color, seg: int = 10,
		rings: int = 7, xf: Transform3D = Transform3D.IDENTITY, color_fn: Callable = Callable()) -> void:
	var verts: Array = []
	var cols: Array = []
	for i in rings + 1:
		var v := PI * i / rings
		for j in seg:
			var a := TAU * j / seg
			var nrm := Vector3(sin(v) * cos(a), cos(v), sin(v) * sin(a))
			verts.append(xf * (center + nrm * radii))
			cols.append(color_fn.call(nrm) if color_fn.is_valid() else color)
	for i in rings:
		for j in seg:
			var j2 := (j + 1) % seg
			var a0 := i * seg + j
			var a1 := i * seg + j2
			var b0 := (i + 1) * seg + j
			var b1 := (i + 1) * seg + j2
			if i > 0:
				_tri(st, verts, cols, a0, b0, a1)
			if i < rings - 1:
				_tri(st, verts, cols, a1, b0, b1)


## صندوق بلون واحد (أوجه حادة)
static func add_box(st: SurfaceTool, center: Vector3, size: Vector3, color: Color, xf: Transform3D = Transform3D.IDENTITY) -> void:
	var h := size * 0.5
	var c := [
		Vector3(-h.x, -h.y, -h.z), Vector3(h.x, -h.y, -h.z), Vector3(h.x, h.y, -h.z), Vector3(-h.x, h.y, -h.z),
		Vector3(-h.x, -h.y, h.z), Vector3(h.x, -h.y, h.z), Vector3(h.x, h.y, h.z), Vector3(-h.x, h.y, h.z)]
	var faces := [[0, 3, 2, 1], [4, 5, 6, 7], [0, 4, 7, 3], [1, 2, 6, 5], [3, 7, 6, 2], [0, 1, 5, 4]]
	var g := 1
	for f in faces:
		g += 1
		for t in [[0, 2, 1], [0, 3, 2]]:
			for k in t:
				st.set_smooth_group(g)
				st.set_color(color)
				st.add_vertex(xf * (center + c[f[k]]))


static func begin() -> SurfaceTool:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	return st


static func finish(st: SurfaceTool) -> ArrayMesh:
	st.index()
	st.generate_normals()
	return st.commit()


static func vcol_material(roughness: float = 0.75, metallic: float = 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.roughness = roughness
	m.metallic = metallic
	return m
