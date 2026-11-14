class_name Trail3D
extends MeshInstance3D
## Camera-facing ribbon trail built with an ImmediateMesh.

var max_points := 28
var lifetime := 0.4
var width := 0.2
var color := Color(1, 1, 1, 0.8)
var emitting := false
var min_step := 0.12

var _pts: Array[Vector3] = []
var _times: Array[float] = []
var _im := ImmediateMesh.new()


func _init() -> void:
	top_level = true
	mesh = _im
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.vertex_color_use_as_albedo = true
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.no_depth_test = false
	material_override = m


func clear_points() -> void:
	_pts.clear()
	_times.clear()
	_im.clear_surfaces()


func update_trail(source: Vector3, cam_pos: Vector3, now: float) -> void:
	if emitting:
		if _pts.is_empty() or _pts[_pts.size() - 1].distance_to(source) > min_step:
			_pts.append(source)
			_times.append(now)
			if _pts.size() > max_points:
				_pts.pop_front()
				_times.pop_front()
		else:
			_pts[_pts.size() - 1] = source
			_times[_times.size() - 1] = now
	while not _times.is_empty() and now - _times[0] > lifetime:
		_pts.pop_front()
		_times.pop_front()
	_im.clear_surfaces()
	var n := _pts.size()
	if n < 2:
		return
	_im.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
	for i in range(n):
		var p := _pts[i]
		var dir: Vector3
		if i < n - 1:
			dir = _pts[i + 1] - p
		else:
			dir = p - _pts[i - 1]
		var to_cam := cam_pos - p
		var side := dir.cross(to_cam)
		if side.length_squared() < 1e-8:
			side = Vector3.UP
		side = side.normalized()
		var age := clampf((now - _times[i]) / lifetime, 0.0, 1.0)
		var f := float(i) / float(n - 1)
		var w := width * (0.25 + 0.75 * f) * (1.0 - age * 0.6)
		var c := color
		c.a *= f * (1.0 - age)
		_im.surface_set_color(c)
		_im.surface_add_vertex(p + side * w)
		_im.surface_set_color(c)
		_im.surface_add_vertex(p - side * w)
	_im.surface_end()
