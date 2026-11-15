class_name BallView
extends Node3D
## Ball presentation: patterned sphere, speed trail, ground indicator ring.

const BALL_SHADER := preload("res://shaders/ball.gdshader")

var sim: BallSim
var mesh_inst: MeshInstance3D
var mat: ShaderMaterial
var trail: Trail3D
var marker: MeshInstance3D
var marker_mat: StandardMaterial3D
var pulse: MeshInstance3D
var pulse_mat: StandardMaterial3D
var line: MeshInstance3D
var line_mesh: ImmediateMesh
var _marker_a := 0.0
var flash_color := Color(1, 1, 1)


func setup(ball: BallSim) -> void:
	sim = ball
	mesh_inst = MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = Phys.BALL_R
	sm.height = Phys.BALL_R * 2.0
	sm.radial_segments = 40
	sm.rings = 20
	mesh_inst.mesh = sm
	mat = ShaderMaterial.new()
	mat.shader = BALL_SHADER
	mesh_inst.material_override = mat
	add_child(mesh_inst)

	trail = Trail3D.new()
	trail.width = 0.55
	trail.lifetime = 0.35
	trail.max_points = 24
	trail.color = Color(0.6, 0.85, 1.0, 0.45)
	add_child(trail)

	# Ground marker that shows where the ball is while it is in the air
	marker = MeshInstance3D.new()
	var qm := QuadMesh.new()
	qm.size = Vector2(3.4, 3.4)
	qm.orientation = PlaneMesh.FACE_Y
	marker.mesh = qm
	marker_mat = StandardMaterial3D.new()
	marker_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	marker_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	marker_mat.albedo_texture = _ring_tex()
	marker_mat.albedo_color = Color(0.8, 0.95, 1.0, 0.8)
	marker_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	marker_mat.render_priority = 2
	marker.material_override = marker_mat
	marker.top_level = true
	marker.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(marker)
	pulse = MeshInstance3D.new()
	var pq := QuadMesh.new()
	pq.size = Vector2(3.4, 3.4)
	pq.orientation = PlaneMesh.FACE_Y
	pulse.mesh = pq
	pulse_mat = StandardMaterial3D.new()
	pulse_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	pulse_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	pulse_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	pulse_mat.albedo_texture = _pulse_tex()
	pulse_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	pulse.material_override = pulse_mat
	pulse.top_level = true
	pulse.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(pulse)
	line = MeshInstance3D.new()
	line_mesh = ImmediateMesh.new()
	line.mesh = line_mesh
	var lm := StandardMaterial3D.new()
	lm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	lm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	lm.vertex_color_use_as_albedo = true
	line.material_override = lm
	line.top_level = true
	line.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(line)


static func _ring_tex() -> Texture2D:
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.13, 0.18, 0.5, 0.58, 0.82, 0.9, 1.0])
	g.colors = PackedColorArray([Color(1, 1, 1, 1), Color(1, 1, 1, 0.95), Color(1, 1, 1, 0.0), Color(1, 1, 1, 0.12),
		Color(1, 1, 1, 1.0), Color(1, 1, 1, 1.0), Color(1, 1, 1, 0.0), Color(1, 1, 1, 0.0)])
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.fill = GradientTexture2D.FILL_RADIAL
	gt.fill_from = Vector2(0.5, 0.5)
	gt.fill_to = Vector2(1.0, 0.5)
	gt.width = 128
	gt.height = 128
	return gt


static func _pulse_tex() -> Texture2D:
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.8, 0.9, 1.0])
	g.colors = PackedColorArray([Color(1, 1, 1, 0), Color(1, 1, 1, 0), Color(1, 1, 1, 1), Color(1, 1, 1, 0)])
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.fill = GradientTexture2D.FILL_RADIAL
	gt.fill_from = Vector2(0.5, 0.5)
	gt.fill_to = Vector2(1.0, 0.5)
	gt.width = 128
	gt.height = 128
	return gt


## Called each frame with the surface point below the ball (from SimWorld).
func set_marker(ok: bool, p: Vector3, n: Vector3, ball_p: Vector3, now: float) -> void:
	var enabled_marker: bool = Settings.get_value("ball_marker", true)
	var h := ball_p.distance_to(p) - Phys.BALL_R
	var show := ok and enabled_marker and visible and h > 0.9
	_marker_a = move_toward(_marker_a, 1.0 if show else 0.0, 0.08)
	marker.visible = _marker_a > 0.01
	pulse.visible = marker.visible
	line.visible = marker.visible and h > 2.5
	if not marker.visible:
		line_mesh.clear_surfaces()
		return
	if n.y > 0.98:
		p = Vector3(ball_p.x, p.y, ball_p.z)
	var up := n.normalized()
	var ref := Vector3.FORWARD if absf(up.dot(Vector3.FORWARD)) < 0.9 else Vector3.RIGHT
	var x := ref.cross(up).normalized()
	var z := x.cross(up).normalized()
	var b := Basis(x, up, z)
	var a := clampf((h - 0.9) / 1.5, 0.0, 1.0) * _marker_a
	marker.global_transform = Transform3D(b, p + up * 0.06)
	marker_mat.albedo_color = Color(0.75, 1.0, 1.25, 0.95 * a)
	var ph := fmod(now * 1.3, 1.0)
	pulse.global_transform = Transform3D(b.scaled(Vector3.ONE * (0.6 + ph * 0.9)), p + up * 0.07)
	pulse_mat.albedo_color = Color(0.4, 0.85, 1.0, 0.7 * (1.0 - ph) * a)
	line_mesh.clear_surfaces()
	if line.visible:
		line_mesh.surface_begin(Mesh.PRIMITIVE_LINES)
		var top := ball_p - up * Phys.BALL_R
		var segs := 12
		for i in range(segs):
			if i % 2 == 1:
				continue
			var t0 := float(i) / segs
			var t1 := float(i + 1) / segs
			line_mesh.surface_set_color(Color(0.8, 0.95, 1.0, 0.5 * a))
			line_mesh.surface_add_vertex(top.lerp(p, t0))
			line_mesh.surface_set_color(Color(0.8, 0.95, 1.0, 0.5 * a))
			line_mesh.surface_add_vertex(top.lerp(p, t1))
		line_mesh.surface_end()


func update_visual(alpha: float, cam: Camera3D, _delta: float, now: float) -> void:
	var p := sim.prev_pos.lerp(sim.pos, alpha)
	var q := sim.prev_quat.slerp(sim.basis.get_rotation_quaternion(), alpha)
	apply_pose(p, q, sim.vel.length(), sim.hit_flash, cam, now)


func apply_pose(p: Vector3, q: Quaternion, spd: float, flash: float, cam: Camera3D, now: float) -> void:
	global_transform = Transform3D(Basis(q), p)
	mat.set_shader_parameter("flash", flash)
	mat.set_shader_parameter("flash_color", Vector3(flash_color.r, flash_color.g, flash_color.b))
	trail.emitting = spd > 22.0
	trail.color.a = clampf((spd - 18.0) / 25.0, 0.0, 0.6)
	trail.update_trail(p, cam.global_position if cam else Vector3.ZERO, now)

