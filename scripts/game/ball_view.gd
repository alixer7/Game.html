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

	# Floor marker that helps judge the ball's position in the air
	marker = MeshInstance3D.new()
	var qm := QuadMesh.new()
	qm.size = Vector2(2.4, 2.4)
	qm.orientation = PlaneMesh.FACE_Y
	marker.mesh = qm
	marker_mat = StandardMaterial3D.new()
	marker_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	marker_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	marker_mat.albedo_texture = _ring_tex()
	marker_mat.albedo_color = Color(0.0, 0.0, 0.0, 0.5)
	marker.material_override = marker_mat
	marker.top_level = true
	marker.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(marker)


static func _ring_tex() -> Texture2D:
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 0.9))
	g.set_color(1, Color(1, 1, 1, 0.0))
	g.add_point(0.55, Color(1, 1, 1, 0.55))
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.fill = GradientTexture2D.FILL_RADIAL
	gt.fill_from = Vector2(0.5, 0.5)
	gt.fill_to = Vector2(1.0, 0.5)
	gt.width = 64
	gt.height = 64
	return gt


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
	var h := p.y - Phys.BALL_R
	marker.visible = visible and h > 0.6 and absf(p.z) < Phys.HALF_L
	marker.global_position = Vector3(p.x, 0.06, p.z)
	var s := clampf(1.0 - h / 18.0, 0.35, 1.0)
	marker.scale = Vector3(s, 1, s)
	marker_mat.albedo_color = Color(0.0, 0.0, 0.0, 0.45 * s)
