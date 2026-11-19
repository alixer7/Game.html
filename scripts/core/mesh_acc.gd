class_name MeshAcc
extends RefCounted
## Small indexed-mesh accumulator with automatic triangle orientation and
## helpers for boxes, cylinders and swept profiles.

var verts := PackedVector3Array()
var norms := PackedVector3Array()
var uvs := PackedVector2Array()
var cols := PackedColorArray()
var idx := PackedInt32Array()
var use_colors := false
var color := Color.WHITE


func v(p: Vector3, n: Vector3, uv := Vector2.ZERO) -> int:
	verts.append(p)
	norms.append(n)
	uvs.append(uv)
	if use_colors:
		cols.append(color)
	return verts.size() - 1


## triangle facing the side given by `face` (front faces follow Godot's convention)
func tri(a: int, b: int, c: int, face: Vector3) -> void:
	var pa := verts[a]
	if (verts[b] - pa).cross(verts[c] - pa).dot(face) > 0.0:
		idx.append(a); idx.append(c); idx.append(b)
	else:
		idx.append(a); idx.append(b); idx.append(c)


func quad(a: int, b: int, c: int, d: int, face: Vector3) -> void:
	# a-b-c-d in ring order
	tri(a, b, c, face)
	tri(a, c, d, face)


func is_empty() -> bool:
	return idx.is_empty()


func arrays() -> Array:
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_NORMAL] = norms
	arr[Mesh.ARRAY_TEX_UV] = uvs
	if use_colors:
		arr[Mesh.ARRAY_COLOR] = cols
	arr[Mesh.ARRAY_INDEX] = idx
	return arr


func to_mesh(mat: Material = null, mesh: ArrayMesh = null) -> ArrayMesh:
	if mesh == null:
		mesh = ArrayMesh.new()
	if idx.is_empty():
		return mesh
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays())
	if mat:
		mesh.surface_set_material(mesh.get_surface_count() - 1, mat)
	return mesh


func faces() -> PackedVector3Array:
	var f := PackedVector3Array()
	f.resize(idx.size())
	for i in idx.size():
		f[i] = verts[idx[i]]
	return f


## axis-aligned box in the given transform; uv scaled in metres
func box(xf: Transform3D, size: Vector3, uv_scale := 1.0) -> void:
	var h := size * 0.5
	var b := xf.basis
	var dirs := [Vector3.RIGHT, Vector3.LEFT, Vector3.UP, Vector3.DOWN, Vector3.BACK, Vector3.FORWARD]
	for d in dirs:
		var n: Vector3 = d
		var u: Vector3 = Vector3.UP if absf(n.y) < 0.5 else Vector3.RIGHT
		var w := n.cross(u)
		var cs := []
		for s in [[-1, -1], [1, -1], [1, 1], [-1, 1]]:
			var lp: Vector3 = n * h + u * h * float(s[0]) + w * h * float(s[1])
			var uv := Vector2(lp.dot(w) if absf(n.y) < 0.5 else lp.x, lp.y if absf(n.y) < 0.5 else lp.z) * uv_scale
			cs.append(v(xf * lp, (b * n).normalized(), uv))
		quad(cs[0], cs[1], cs[2], cs[3], b * n)


## cylinder (or cone) along local +Y from y0 to y1
func cylinder(xf: Transform3D, r0: float, r1: float, y0: float, y1: float, sides := 8, caps := true, uv_scale := 1.0) -> void:
	var ring0 := []
	var ring1 := []
	var circ := TAU * maxf(r0, r1)
	for i in sides + 1:
		var a := TAU * i / sides
		var d := Vector3(cos(a), 0, sin(a))
		var slope := (r0 - r1) / maxf(y1 - y0, 0.001)
		var n := (xf.basis * (d + Vector3(0, slope, 0))).normalized()
		ring0.append(v(xf * (d * r0 + Vector3(0, y0, 0)), n, Vector2(float(i) / sides * circ, y0) * uv_scale))
		ring1.append(v(xf * (d * r1 + Vector3(0, y1, 0)), n, Vector2(float(i) / sides * circ, y1) * uv_scale))
	for i in sides:
		var mid := xf * (Vector3(cos(TAU * (i + 0.5) / sides), 0, sin(TAU * (i + 0.5) / sides)) * (r0 + r1) * 0.5 + Vector3(0, (y0 + y1) * 0.5, 0))
		var face := mid - xf * Vector3(0, (y0 + y1) * 0.5, 0)
		quad(ring0[i], ring0[i + 1], ring1[i + 1], ring1[i], face)
	if caps:
		var up := (xf.basis * Vector3.UP).normalized()
		if r1 > 0.001:
			var c1 := v(xf * Vector3(0, y1, 0), up, Vector2.ZERO)
			var top := []
			for i in sides + 1:
				var a := TAU * i / sides
				top.append(v(xf * (Vector3(cos(a), 0, sin(a)) * r1 + Vector3(0, y1, 0)), up, Vector2(cos(a), sin(a)) * r1 * uv_scale))
			for i in sides:
				tri(c1, top[i], top[i + 1], up)
		if r0 > 0.001:
			var c0 := v(xf * Vector3(0, y0, 0), -up, Vector2.ZERO)
			var bot := []
			for i in sides + 1:
				var a := TAU * i / sides
				bot.append(v(xf * (Vector3(cos(a), 0, sin(a)) * r0 + Vector3(0, y0, 0)), -up, Vector2(cos(a), sin(a)) * r0 * uv_scale))
			for i in sides:
				tri(c0, bot[i], bot[i + 1], -up)


## sweep a 2D profile (points in (lateral, height) and outward normals) along a path
## path: Array of Transform3D (basis.x = lateral, basis.y = up); v coordinate = distance
func sweep(path: Array, profile: PackedVector2Array, pnorm: PackedVector2Array, dist: PackedFloat32Array, uv_scale := 1.0, closed_profile := false) -> void:
	var m := profile.size()
	var rows := []
	var plen := PackedFloat32Array()
	plen.resize(m)
	var acc := 0.0
	for i in m:
		if i > 0:
			acc += profile[i].distance_to(profile[i - 1])
		plen[i] = acc
	for k in path.size():
		var t: Transform3D = path[k]
		var row := []
		for i in m:
			var lp := Vector3(profile[i].x, profile[i].y, 0)
			var ln := Vector3(pnorm[i].x, pnorm[i].y, 0)
			row.append(v(t * lp, (t.basis * ln).normalized(), Vector2(plen[i], dist[k]) * uv_scale))
		rows.append(row)
	var segs := m if closed_profile else m - 1
	for k in path.size() - 1:
		var t: Transform3D = path[k]
		for i in segs:
			var i2 := (i + 1) % m
			var nn := Vector3(pnorm[i].x + pnorm[i2].x, pnorm[i].y + pnorm[i2].y, 0)
			quad(rows[k][i], rows[k][i2], rows[k + 1][i2], rows[k + 1][i], t.basis * nn)
