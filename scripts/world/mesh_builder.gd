class_name MeshBuilder
extends RefCounted
## أداة لبناء المجسمات الإجرائية: كرات مشوهة، أنابيب، مخاريط، صناديق، أوراق.
## الوجوه الأمامية في Godot باتجاه عقارب الساعة؛ كل الدوال هنا تحترم ذلك.

var v := PackedVector3Array()
var n := PackedVector3Array()
var c := PackedColorArray()
var idx := PackedInt32Array()

static var _nz: FastNoiseLite = null

static func noise3(p: Vector3) -> float:
	if _nz == null:
		_nz = FastNoiseLite.new()
		_nz.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
		_nz.frequency = 1.0
		_nz.fractal_type = FastNoiseLite.FRACTAL_FBM
		_nz.fractal_octaves = 2
		_nz.seed = 4242
	return _nz.get_noise_3dv(p)

func vertex_count() -> int:
	return v.size()

## شبكة بارامترية: rows صفوف (من الأسفل للأعلى على المحور) × cols أعمدة (زاوية متزايدة)
func add_grid(pts: PackedVector3Array, cl: PackedColorArray, rows: int, cols: int, wrap: bool, avg_poles := false) -> void:
	var base := v.size()
	var acc := PackedVector3Array()
	acc.resize(pts.size())
	var qc := cols if wrap else cols - 1
	for r in range(rows - 1):
		for q in range(qc):
			var q1 := (q + 1) % cols
			var a := r * cols + q
			var b := r * cols + q1
			var cc := (r + 1) * cols + q
			var d := (r + 1) * cols + q1
			idx.append(base + a)
			idx.append(base + b)
			idx.append(base + cc)
			idx.append(base + b)
			idx.append(base + d)
			idx.append(base + cc)
			var f1 := (pts[cc] - pts[a]).cross(pts[b] - pts[a])
			var f2 := (pts[cc] - pts[b]).cross(pts[d] - pts[b])
			acc[a] += f1
			acc[b] += f1 + f2
			acc[cc] += f1 + f2
			acc[d] += f2
	if avg_poles:
		for row in [0, rows - 1]:
			var s := Vector3.ZERO
			for q in range(cols):
				s += acc[row * cols + q]
			for q in range(cols):
				acc[row * cols + q] = s
	for i in range(pts.size()):
		v.append(pts[i])
		var nn := acc[i]
		n.append(nn.normalized() if nn.length_squared() > 1e-14 else Vector3.UP)
		c.append(cl[i])

func _shade(mode: int, p: Vector3, dir: Vector3, col: Color, col2: Color, param: float) -> Color:
	match mode:
		1: # أوراق: أغمق في الأسفل وتباين لوني
			var k := 0.58 + 0.42 * (dir.y * 0.5 + 0.5)
			var t := clampf(noise3(p * 0.9) * 1.5 + 0.5, 0.0, 1.0)
			var r := col.lerp(col2, t * 0.4)
			return Color(r.r * k, r.g * k, r.b * k)
		2: # صخر مع طحلب
			var nn := noise3(p * 1.7)
			var r2 := Color(col.r * (0.8 + nn * 0.35), col.g * (0.8 + nn * 0.35), col.b * (0.8 + nn * 0.35))
			if dir.y > 0.5:
				var m := clampf((dir.y - 0.5) * 2.0 * clampf(noise3(p * 0.9 + Vector3(7, 0, 3)) + 0.55, 0.0, 1.0), 0.0, 1.0)
				r2 = r2.lerp(col2, m * 0.85)
			return r2
		3: # عروق معدنية
			var nn2 := noise3(p * 1.5)
			var base := Color(col.r * (0.8 + nn2 * 0.3), col.g * (0.8 + nn2 * 0.3), col.b * (0.8 + nn2 * 0.3))
			var vein := absf(noise3(p * 3.2 + Vector3(11, 5, 2)))
			if vein < param:
				var k2 := 1.0 + (param - vein) * 3.0
				return Color(col2.r * k2, col2.g * k2, col2.b * k2)
			return base
		4: # نقاط بيضاء (فطر سام)
			if noise3(p * 18.0) > 0.25 and dir.y > 0.2:
				return col2
			return col
		5: # لحاء البتولا
			if noise3(Vector3(p.x * 5.0, p.y * 14.0, p.z * 5.0)) > 0.28:
				return col2
			return col
		6: # لحاء عادي بخطوط عمودية
			var s := 0.78 + noise3(Vector3(p.x * 7.0, p.y * 1.2, p.z * 7.0)) * 0.35
			return Color(col.r * s, col.g * s, col.b * s)
		7: # خطوط أفقية (خلية نحل، أسقف قش)
			var s2 := 0.75 + 0.25 * sin(p.y * param)
			return Color(col.r * s2, col.g * s2, col.b * s2).lerp(col2, clampf(noise3(p * 4.0), 0.0, 1.0) * 0.3)
	return col

## كرة/مجسم بيضاوي مشوه بالضوضاء
func blob(center: Vector3, rad: Vector3, col: Color, noise_amt := 0.2, nfreq := 1.2, rings := 8, segs := 12, seed_off := 0.0, shade := 0, col2 := Color.WHITE, param := 0.12, flat := -1.0) -> void:
	var pts := PackedVector3Array()
	var cl := PackedColorArray()
	var so := Vector3(seed_off, seed_off * 0.7, seed_off * 1.3)
	for r in range(rings + 1):
		var t := float(r) / rings
		var phi := PI * (t - 0.5)
		var y := sin(phi)
		var rr := cos(phi)
		for q in range(segs):
			var th := TAU * q / segs
			var dir := Vector3(cos(th) * rr, y, sin(th) * rr)
			var disp := 1.0 + noise3(dir * nfreq + so) * noise_amt
			var p := center + dir * rad * disp
			if flat >= 0.0 and p.y < center.y - rad.y * flat:
				p.y = center.y - rad.y * flat
			pts.append(p)
			cl.append(_shade(shade, p, dir, col, col2, param))
	add_grid(pts, cl, rings + 1, segs, true, true)

func _frame(D: Vector3) -> Array:
	var helper := Vector3(0, 0, 1)
	if absf(D.dot(helper)) > 0.95:
		helper = Vector3(1, 0, 0)
	var X := D.cross(helper).normalized()
	var Z := X.cross(D).normalized()
	return [X, Z]

## أنبوب مخروطي بين نقطتين (جذوع وأغصان وسيقان)
func tube(a: Vector3, b: Vector3, r0: float, r1: float, col0: Color, col1: Color, segs := 8, rings := 2, noise_amt := 0.0, bend := Vector3.ZERO, shade := 0, col2 := Color.BLACK, rib := 0.0, ribs := 0, cap_top := false) -> void:
	var axis := b - a
	var L := axis.length()
	if L < 0.0001:
		return
	var D := axis / L
	var fr := _frame(D)
	var X: Vector3 = fr[0]
	var Z: Vector3 = fr[1]
	var pts := PackedVector3Array()
	var cl := PackedColorArray()
	for r in range(rings + 1):
		var t := float(r) / rings
		var cen := a.lerp(b, t) + bend * sin(t * PI)
		var rad := lerpf(r0, r1, t)
		var cc := col0.lerp(col1, t)
		for q in range(segs):
			var th := TAU * q / segs
			var dir := X * cos(th) + Z * sin(th)
			var m := 1.0
			if ribs > 0:
				m += rib * cos(th * ribs)
			if noise_amt > 0.0:
				m += noise3(cen * 2.0 + dir * 1.5) * noise_amt
			var p := cen + dir * rad * m
			pts.append(p)
			cl.append(_shade(shade, p, dir, cc, col2, 0.0))
	add_grid(pts, cl, rings + 1, segs, true)
	if cap_top:
		disc(b + bend * 0.0, D, r1, col1, segs, true)

## قرص (غطاء) باتجاه normal
func disc(center: Vector3, normal: Vector3, radius: float, col: Color, segs := 8, facing_out := true) -> void:
	var fr := _frame(normal)
	var X: Vector3 = fr[0]
	var Z: Vector3 = fr[1]
	var pts := PackedVector3Array()
	var cl := PackedColorArray()
	var ring := PackedVector3Array()
	for q in range(segs):
		var th := TAU * q / segs
		ring.append(center + (X * cos(th) + Z * sin(th)) * radius)
	if facing_out:
		for q in range(segs):
			pts.append(ring[q])
			cl.append(col)
		for q in range(segs):
			pts.append(center)
			cl.append(col)
	else:
		for q in range(segs):
			pts.append(center)
			cl.append(col)
		for q in range(segs):
			pts.append(ring[q])
			cl.append(col)
	add_grid(pts, cl, 2, segs, true)

## مخروط بقاعدة (طبقات الصنوبر)
func cone(base: Vector3, height: float, radius: float, col: Color, col_tip: Color, segs := 12, rib := 0.0, ribs := 0, droop := 0.0) -> void:
	var tip := base + Vector3(0, height, 0)
	tube(base + Vector3(0, -droop, 0), tip, radius, 0.02, col, col_tip, segs, 3, 0.08, Vector3(0, droop * 0.6, 0), 1, col_tip, rib, ribs)
	disc(base + Vector3(0, -droop, 0), Vector3.UP, radius * 0.9, Color(col.r * 0.6, col.g * 0.6, col.b * 0.6), segs, false)

## وجه رباعي يواجه normal (right × up = normal)
func quad(center: Vector3, normal: Vector3, up: Vector3, w: float, h: float, col: Color) -> void:
	var right := up.cross(normal).normalized() * w * 0.5
	var u := up.normalized() * h * 0.5
	var tl := center - right + u
	var tr := center + right + u
	var br := center + right - u
	var bl := center - right - u
	var base := v.size()
	for p in [tl, tr, br, bl]:
		v.append(p)
		n.append(normal.normalized())
		c.append(col)
	idx.append_array([base, base + 1, base + 2, base, base + 2, base + 3])

func box(center: Vector3, size: Vector3, col: Color, basis := Basis(), shade_top := 1.0) -> void:
	var hs := size * 0.5
	var faces := [
		[Vector3(1, 0, 0), Vector3(0, 1, 0), size.z, size.y, hs.x],
		[Vector3(-1, 0, 0), Vector3(0, 1, 0), size.z, size.y, hs.x],
		[Vector3(0, 0, 1), Vector3(0, 1, 0), size.x, size.y, hs.z],
		[Vector3(0, 0, -1), Vector3(0, 1, 0), size.x, size.y, hs.z],
		[Vector3(0, 1, 0), Vector3(0, 0, -1), size.x, size.z, hs.y],
		[Vector3(0, -1, 0), Vector3(0, 0, 1), size.x, size.z, hs.y],
	]
	for f in faces:
		var nn: Vector3 = basis * f[0]
		var up: Vector3 = basis * f[1]
		var k := shade_top if f[0].y > 0.5 else (0.75 if f[0].y < -0.5 else 1.0)
		quad(center + nn * f[4], nn, up, f[2], f[3], Color(col.r * k, col.g * k, col.b * k))

## شريط ورقة مزدوج الوجه (سعف النخيل، أوراق العشب)
func leaf_strip(origin: Vector3, dir: Vector3, length: float, width: float, droop: float, col0: Color, col1: Color, segs := 6, lift := 0.6, fold := 0.15) -> void:
	var D := Vector3(dir.x, 0, dir.z).normalized()
	if D.length_squared() < 0.01:
		D = Vector3(1, 0, 0)
	var side := D.cross(Vector3.UP).normalized()
	var pts := PackedVector3Array()
	var cl := PackedColorArray()
	for s in range(segs + 1):
		var t := float(s) / segs
		var pos := origin + D * length * t + Vector3.UP * (lift * length * t - droop * length * t * t)
		var w := width * sin(clampf(t * 1.1, 0.0, 1.0) * PI) * 0.5 + 0.01
		var cc := col0.lerp(col1, t)
		pts.append(pos - side * w + Vector3.UP * (-fold * w))
		pts.append(pos + Vector3.UP * fold * w * 0.5)
		pts.append(pos + side * w + Vector3.UP * (-fold * w))
		cl.append(cc)
		cl.append(Color(cc.r * 1.1, cc.g * 1.1, cc.b * 1.1))
		cl.append(cc)
	add_grid(pts, cl, segs + 1, 3, false)
	# الوجه الخلفي بترتيب معكوس
	var pts2 := PackedVector3Array()
	var cl2 := PackedColorArray()
	for s in range(segs + 1):
		for k in [2, 1, 0]:
			pts2.append(pts[s * 3 + k] - Vector3.UP * 0.004)
			cl2.append(Color(cl[s * 3 + k].r * 0.8, cl[s * 3 + k].g * 0.8, cl[s * 3 + k].b * 0.8))
	add_grid(pts2, cl2, segs + 1, 3, false)

## مثلث (مزدوج الوجه اختيارياً)
func tri(a: Vector3, b: Vector3, c2: Vector3, col: Color, double := true) -> void:
	var nn := (c2 - a).cross(b - a).normalized()
	var base := v.size()
	v.append_array([a, b, c2])
	n.append_array([nn, nn, nn])
	c.append_array([col, col, col])
	idx.append_array([base, base + 1, base + 2])
	if double:
		base = v.size()
		v.append_array([a, c2, b])
		n.append_array([-nn, -nn, -nn])
		c.append_array([col, col, col])
		idx.append_array([base, base + 1, base + 2])

## نصل عشب (مثلث مستدق من شريحتين)
func blade(base: Vector3, height: float, width: float, bend: Vector3, col0: Color, col1: Color) -> void:
	var side := Vector3(bend.z, 0, -bend.x).normalized() if bend.length() > 0.01 else Vector3(1, 0, 0)
	var pts := PackedVector3Array()
	var cl := PackedColorArray()
	for s in range(4):
		var t := float(s) / 3.0
		var pos := base + Vector3.UP * height * t + bend * t * t
		var w := width * (1.0 - t) * 0.5 + 0.002
		pts.append(pos - side * w)
		pts.append(pos + side * w)
		var cc := col0.lerp(col1, t)
		cl.append(cc)
		cl.append(cc)
	add_grid(pts, cl, 4, 2, false)

static func commit(builders: Array, mats: Array) -> ArrayMesh:
	var m := ArrayMesh.new()
	for i in range(builders.size()):
		var b: MeshBuilder = builders[i]
		if b.v.is_empty():
			continue
		var arr := []
		arr.resize(Mesh.ARRAY_MAX)
		arr[Mesh.ARRAY_VERTEX] = b.v
		arr[Mesh.ARRAY_NORMAL] = b.n
		arr[Mesh.ARRAY_COLOR] = b.c
		arr[Mesh.ARRAY_INDEX] = b.idx
		m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
		m.surface_set_material(m.get_surface_count() - 1, mats[i])
	return m
