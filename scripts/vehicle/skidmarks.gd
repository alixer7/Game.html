class_name SkidMarks
extends Node3D
## Shared ring buffer of tyre-mark quads, split into chunks so only the active
## chunk is rebuilt each frame.

const CHUNK_QUADS := 96
const CHUNKS := 18

static var instance: SkidMarks

var chunks := []          # Array of {mi, verts, cols, count}
var current := 0
var mat: StandardMaterial3D
var dirty := false


func _init() -> void:
	instance = self


func _ready() -> void:
	mat = StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 0.9
	mat.albedo_color = Color(1, 1, 1, 1)
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.render_priority = -1
	for i in CHUNKS:
		var mi := MeshInstance3D.new()
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.material_override = mat
		add_child(mi)
		chunks.append({"mi": mi, "verts": PackedVector3Array(), "cols": PackedColorArray(), "count": 0})


func add_segment(a: Vector3, b: Vector3, right: Vector3, width: float, col: Color) -> void:
	var c: Dictionary = chunks[current]
	if c.count >= CHUNK_QUADS:
		_flush(current)
		current = (current + 1) % CHUNKS
		c = chunks[current]
		c.verts = PackedVector3Array()
		c.cols = PackedColorArray()
		c.count = 0
	var lift := Vector3(0, 0.03, 0)
	var h := right * width * 0.5
	var v: PackedVector3Array = c.verts
	var cl: PackedColorArray = c.cols
	# two triangles, both windings handled by CULL_DISABLED
	v.append(a - h + lift); v.append(a + h + lift); v.append(b + h + lift)
	v.append(a - h + lift); v.append(b + h + lift); v.append(b - h + lift)
	for i in 6:
		cl.append(col)
	c.verts = v
	c.cols = cl
	c.count += 1
	dirty = true


func _process(_d: float) -> void:
	if dirty:
		_flush(current)
		dirty = false


func _flush(i: int) -> void:
	var c: Dictionary = chunks[i]
	if c.verts.is_empty():
		return
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = c.verts
	arr[Mesh.ARRAY_COLOR] = c.cols
	var norms := PackedVector3Array()
	norms.resize(c.verts.size())
	norms.fill(Vector3.UP)
	arr[Mesh.ARRAY_NORMAL] = norms
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	c.mi.mesh = m


func clear_all() -> void:
	for c in chunks:
		c.verts = PackedVector3Array()
		c.cols = PackedColorArray()
		c.count = 0
		c.mi.mesh = null
