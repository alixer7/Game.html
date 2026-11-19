class_name Fx
extends RefCounted
## Visual-effect helpers: particle bursts, shock rings, floating text, ribbon trails.

static var _soft: Texture2D = null
static var _mat_add: StandardMaterial3D = null
static var _quad: QuadMesh = null
static var _ramp: Gradient = null
static var _curve: Curve = null


static func soft_tex() -> Texture2D:
	if _soft == null:
		var gt := GradientTexture2D.new()
		var g := Gradient.new()
		g.set_color(0, Color(1, 1, 1, 1))
		g.set_color(1, Color(1, 1, 1, 0))
		g.add_point(0.4, Color(1, 1, 1, 0.55))
		gt.gradient = g
		gt.fill = GradientTexture2D.FILL_RADIAL
		gt.fill_from = Vector2(0.5, 0.5)
		gt.fill_to = Vector2(1.0, 0.5)
		gt.width = 64
		gt.height = 64
		_soft = gt
	return _soft


static func additive_mat() -> StandardMaterial3D:
	if _mat_add == null:
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		m.vertex_color_use_as_albedo = true
		m.albedo_texture = soft_tex()
		m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
		m.billboard_keep_scale = true
		m.disable_receive_shadows = true
		_mat_add = m
	return _mat_add


static func quad() -> QuadMesh:
	if _quad == null:
		_quad = QuadMesh.new()
		_quad.size = Vector2(1, 1)
		_quad.material = additive_mat()
	return _quad


static func fade_ramp() -> Gradient:
	if _ramp == null:
		_ramp = Gradient.new()
		_ramp.set_color(0, Color(1, 1, 1, 1))
		_ramp.set_color(1, Color(1, 1, 1, 0))
		_ramp.add_point(0.55, Color(1, 1, 1, 0.8))
	return _ramp


static func shrink_curve() -> Curve:
	if _curve == null:
		_curve = Curve.new()
		_curve.add_point(Vector2(0.0, 1.0))
		_curve.add_point(Vector2(1.0, 0.0))
	return _curve


## One-shot particle burst at a world position.
static func burst(parent: Node, pos: Vector3, color: Color, count: int = 14, speed: float = 5.0, size: float = 0.3, life: float = 0.6, grav: float = -8.0, spread: float = 180.0, dir: Vector3 = Vector3.UP) -> CPUParticles3D:
	if parent == null or not parent.is_inside_tree():
		return null
	var p := CPUParticles3D.new()
	p.mesh = quad()
	p.amount = maxi(3, int(float(count) * Game.particle_scale()))
	p.lifetime = life
	p.one_shot = true
	p.explosiveness = 1.0
	p.local_coords = false
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = 0.12
	p.direction = dir
	p.spread = spread
	p.initial_velocity_min = speed * 0.45
	p.initial_velocity_max = speed
	p.gravity = Vector3(0.0, grav, 0.0)
	p.scale_amount_min = size * 0.6
	p.scale_amount_max = size
	p.scale_amount_curve = shrink_curve()
	p.color = color
	p.color_ramp = fade_ramp()
	parent.add_child(p)
	p.global_position = pos
	p.emitting = true
	p.finished.connect(p.queue_free)
	return p


## Expanding flat shock-wave ring.
static func ring(parent: Node, pos: Vector3, color: Color, size: float = 3.0, dur: float = 0.5, energy: float = 3.0) -> void:
	if parent == null or not parent.is_inside_tree():
		return
	var r := RingFx.new()
	r.setup(color, size, dur, energy)
	parent.add_child(r)
	r.global_position = pos + Vector3(0.0, 0.06, 0.0)


## Floating billboard text ("+1", toasts in world space).
static func popup(parent: Node, pos: Vector3, text: String, color: Color = Color(1, 1, 1), size: int = 64) -> void:
	if parent == null or not parent.is_inside_tree():
		return
	var l := Label3D.new()
	l.text = text
	l.font = UIKit.font()
	l.font_size = size
	l.pixel_size = 0.01
	l.modulate = color
	l.outline_size = 14
	l.outline_modulate = Color(0.02, 0.04, 0.12, 0.9)
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.no_depth_test = true
	l.shaded = false
	parent.add_child(l)
	l.global_position = pos
	var tw := l.create_tween()
	tw.set_parallel(true)
	tw.tween_property(l, "position:y", l.position.y + 1.6, 0.9).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(l, "modulate:a", 0.0, 0.9).set_delay(0.35)
	tw.chain().tween_callback(l.queue_free)


# ------------------------------------------------------------ inner nodes
class RingFx extends MeshInstance3D:
	var dur: float = 0.5
	var _t: float = 0.0
	var _mat: ShaderMaterial

	func setup(col: Color, size: float, duration: float, energy: float) -> void:
		var pm := PlaneMesh.new()
		pm.size = Vector2(size, size)
		mesh = pm
		_mat = ShaderMaterial.new()
		_mat.shader = Mats.shader("res://shaders/ring_fx.gdshader")
		_mat.set_shader_parameter("color", col)
		_mat.set_shader_parameter("energy", energy)
		material_override = _mat
		cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		dur = maxf(0.05, duration)

	func _process(delta: float) -> void:
		_t += delta
		var p: float = clampf(_t / dur, 0.0, 1.0)
		_mat.set_shader_parameter("progress", p)
		if p >= 1.0:
			queue_free()


## Ribbon trail that follows a node (used for dash, spin and flying bots).
class Trail3D extends MeshInstance3D:
	var target: Node3D = null
	var offset: Vector3 = Vector3.ZERO
	var width: float = 0.5
	var life: float = 0.35
	var color_a: Color = Color(0.4, 0.95, 1.0)
	var color_b: Color = Color(0.5, 0.3, 1.0)
	var emitting: bool = false
	var _pts: Array = []
	var _im: ImmediateMesh

	func _ready() -> void:
		_im = ImmediateMesh.new()
		mesh = _im
		var m := ShaderMaterial.new()
		m.shader = Mats.shader("res://shaders/trail.gdshader")
		material_override = m
		top_level = true
		cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	func _process(delta: float) -> void:
		for p in _pts:
			p[1] += delta
		while _pts.size() > 0 and _pts[0][1] > life:
			_pts.pop_front()
		if emitting and target != null and is_instance_valid(target):
			var pos: Vector3 = target.global_position + offset
			if _pts.is_empty() or pos.distance_to(_pts[_pts.size() - 1][0]) > 0.07:
				_pts.append([pos, 0.0])
		_rebuild()

	func _rebuild() -> void:
		_im.clear_surfaces()
		if _pts.size() < 2:
			return
		var cam: Camera3D = get_viewport().get_camera_3d()
		if cam == null:
			return
		_im.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
		for i in range(_pts.size()):
			var p: Vector3 = _pts[i][0]
			var age: float = _pts[i][1]
			var t: float = clampf(1.0 - age / life, 0.0, 1.0)
			var dir: Vector3
			if i < _pts.size() - 1:
				dir = _pts[i + 1][0] - p
			else:
				dir = p - _pts[i - 1][0]
			var to_cam: Vector3 = (cam.global_position - p).normalized()
			var side: Vector3 = dir.cross(to_cam).normalized() * width * 0.5 * t
			var c: Color = color_a.lerp(color_b, 1.0 - t)
			c.a = t
			_im.surface_set_color(c)
			_im.surface_add_vertex(p + side)
			_im.surface_set_color(c)
			_im.surface_add_vertex(p - side)
		_im.surface_end()


## Simple constant rotation (rings, gears, decorations).
class Spin extends Node3D:
	var axis: Vector3 = Vector3.UP
	var speed: float = 0.5

	func _process(delta: float) -> void:
		rotate(axis, speed * delta)
