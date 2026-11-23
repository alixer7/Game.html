class_name MeshBuilder
extends RefCounted
## Accumulates triangle geometry in packed arrays and commits it to an ArrayMesh.
## Supports optional smooth-normal generation, vertex colors, UV and UV2.

var verts := PackedVector3Array()
var norms := PackedVector3Array()
var uvs := PackedVector2Array()
var uv2s := PackedVector2Array()
var cols := PackedColorArray()
var idx := PackedInt32Array()
var use_uv2 := false


func vcount() -> int:
	return verts.size()


func add_vertex(p: Vector3, n: Vector3, uv := Vector2.ZERO, c := Color.WHITE, uv2 := Vector2.ZERO) -> int:
	verts.append(p)
	norms.append(n)
	uvs.append(uv)
	cols.append(c)
	if use_uv2:
		uv2s.append(uv2)
	return verts.size() - 1


func tri(a: int, b: int, c: int) -> void:
	## a-b-c counter-clockwise when seen from the front. Godot's front faces are
	## clockwise, so the stored order is reversed here (and only here).
	idx.append(a)
	idx.append(c)
	idx.append(b)


func quad(a: int, b: int, c: int, d: int) -> void:
	## a-b-c-d counter-clockwise when seen from the front
	idx.append(a)
	idx.append(c)
	idx.append(b)
	idx.append(a)
	idx.append(d)
	idx.append(c)


func add_flat_tri(a: Vector3, b: Vector3, c: Vector3, col := Color.WHITE) -> void:
	var n := (b - a).cross(c - a).normalized()
	var i := add_vertex(a, n, Vector2(a.x, a.z), col)
	add_vertex(b, n, Vector2(b.x, b.z), col)
	add_vertex(c, n, Vector2(c.x, c.z), col)
	tri(i, i + 1, i + 2)


func append_builder(other: MeshBuilder, xf := Transform3D.IDENTITY, tint := Color.WHITE) -> void:
	var base := verts.size()
	var nb := xf.basis.inverse().transposed()
	for i in other.verts.size():
		verts.append(xf * other.verts[i])
		norms.append((nb * other.norms[i]).normalized())
		uvs.append(other.uvs[i])
		cols.append(other.cols[i] * tint)
		if use_uv2:
			uv2s.append(other.uv2s[i] if other.use_uv2 else Vector2.ZERO)
	for i in other.idx:
		idx.append(base + i)


func recompute_normals() -> void:
	## Smooth normals accumulated per vertex index (does not weld seams).
	var acc := PackedVector3Array()
	acc.resize(verts.size())
	for i in range(0, idx.size(), 3):
		# stored order is (a, c, b) of a counter-clockwise triangle (a, b, c)
		var a := idx[i]
		var c := idx[i + 1]
		var b := idx[i + 2]
		var fn := (verts[b] - verts[a]).cross(verts[c] - verts[a])
		acc[a] += fn
		acc[b] += fn
		acc[c] += fn
	for i in verts.size():
		norms[i] = acc[i].normalized() if acc[i].length_squared() > 1e-12 else Vector3.UP


func flip_winding() -> void:
	for i in range(0, idx.size(), 3):
		var t := idx[i + 1]
		idx[i + 1] = idx[i + 2]
		idx[i + 2] = t


func commit(mesh: ArrayMesh = null, material: Material = null) -> ArrayMesh:
	if mesh == null:
		mesh = ArrayMesh.new()
	if verts.is_empty():
		return mesh
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = norms
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_COLOR] = cols
	if use_uv2:
		arrays[Mesh.ARRAY_TEX_UV2] = uv2s
	arrays[Mesh.ARRAY_INDEX] = idx
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	if material != null:
		mesh.surface_set_material(mesh.get_surface_count() - 1, material)
	return mesh


func to_collision_faces() -> PackedVector3Array:
	var faces := PackedVector3Array()
	faces.resize(idx.size())
	for i in idx.size():
		faces[i] = verts[idx[i]]
	return faces


func clear() -> void:
	verts.clear()
	norms.clear()
	uvs.clear()
	uv2s.clear()
	cols.clear()
	idx.clear()
