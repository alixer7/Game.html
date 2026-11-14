class_name CarView
extends Node3D
## Presentation of one CarSim: interpolated transform, wheels, boost flame,
## supersonic trails and name tag.

var sim: CarSim
var model: Node3D
var wheels: Array = []
var body_mat: ShaderMaterial
var tail_mat: StandardMaterial3D
var flame: CPUParticles3D
var flame_core: MeshInstance3D
var trails: Array[Trail3D] = []
var boost_trail: Trail3D
var label: Label3D
var boost_color := Color(1.0, 0.55, 0.1)
var _boost_vis := 0.0
var _steer_vis := 0.0
var show_label := true


func setup(car: CarSim, paint: Color, accent: Color, trail_color: Color, tag: String) -> void:
	sim = car
	boost_color = trail_color
	model = CarModel.build(car.body_type, paint, accent)
	add_child(model)
	wheels = model.get_meta("wheels")
	body_mat = model.get_meta("body_mat")
	tail_mat = model.get_meta("tail_mat")
	var ex: Vector3 = model.get_meta("exhaust")

	flame = CPUParticles3D.new()
	flame.amount = 36
	flame.lifetime = 0.28
	flame.local_coords = false
	flame.emitting = false
	flame.direction = Vector3(0, 0, 1)
	flame.spread = 9.0
	flame.initial_velocity_min = 7.0
	flame.initial_velocity_max = 11.0
	flame.gravity = Vector3.ZERO
	flame.scale_amount_min = 0.22
	flame.scale_amount_max = 0.34
	var sc := Curve.new()
	sc.add_point(Vector2(0, 1.0))
	sc.add_point(Vector2(1, 0.15))
	flame.scale_amount_curve = sc
	var grad := Gradient.new()
	grad.set_color(0, Color(1, 1, 0.9, 1))
	grad.set_color(1, Color(trail_color.r, trail_color.g, trail_color.b, 0.0))
	grad.add_point(0.25, Color(trail_color.r * 1.2, trail_color.g * 1.1, trail_color.b, 0.9))
	flame.color_ramp = grad
	var qm := QuadMesh.new()
	qm.size = Vector2(1, 1)
	var pm := StandardMaterial3D.new()
	pm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	pm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	pm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	pm.vertex_color_use_as_albedo = true
	pm.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	pm.albedo_texture = _soft_dot()
	qm.material = pm
	flame.mesh = qm
	flame.position = ex
	flame.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	model.add_child(flame)

	flame_core = MeshInstance3D.new()
	var cone := CylinderMesh.new()
	cone.top_radius = 0.075
	cone.bottom_radius = 0.0
	cone.height = 0.6
	cone.radial_segments = 10
	flame_core.mesh = cone
	var cm := StandardMaterial3D.new()
	cm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	cm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	cm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	cm.albedo_color = Color(trail_color.r, trail_color.g * 0.9 + 0.1, trail_color.b + 0.2, 0.9)
	flame_core.material_override = cm
	flame_core.rotation_degrees = Vector3(-90, 0, 0)
	flame_core.position = ex + Vector3(0, 0, 0.3)
	flame_core.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	flame_core.visible = false
	model.add_child(flame_core)

	for i in range(2):
		var t := Trail3D.new()
		t.width = 0.07
		t.lifetime = 0.45
		t.color = Color(1, 1, 1, 0.7)
		add_child(t)
		trails.append(t)
	boost_trail = Trail3D.new()
	boost_trail.width = 0.16
	boost_trail.lifetime = 0.3
	boost_trail.color = Color(trail_color.r, trail_color.g, trail_color.b, 0.55)
	add_child(boost_trail)

	label = Label3D.new()
	label.text = tag
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.fixed_size = true
	label.pixel_size = 0.0011
	label.font_size = 26
	label.outline_size = 8
	label.modulate = Phys.team_color(car.team).lerp(Color.WHITE, 0.55)
	label.no_depth_test = true
	label.position = Vector3(0, 1.15, 0)
	label.top_level = true
	label.font = UiTheme.font_bold()
	add_child(label)


static var _dot_tex: Texture2D


static func _soft_dot() -> Texture2D:
	if _dot_tex:
		return _dot_tex
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 1))
	g.set_color(1, Color(1, 1, 1, 0))
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.fill = GradientTexture2D.FILL_RADIAL
	gt.fill_from = Vector2(0.5, 0.5)
	gt.fill_to = Vector2(1.0, 0.5)
	gt.width = 64
	gt.height = 64
	_dot_tex = gt
	return gt


## Called every rendered frame with the physics interpolation fraction.
func update_visual(alpha: float, cam: Camera3D, delta: float, now: float) -> void:
	if sim == null:
		return
	visible = not sim.demolished
	if sim.demolished:
		flame.emitting = false
		for t in trails:
			t.emitting = false
			t.clear_points()
		boost_trail.clear_points()
		label.visible = false
		return
	var q := sim.prev_quat.slerp(sim.basis.get_rotation_quaternion(), alpha)
	var p := sim.prev_pos.lerp(sim.pos, alpha)
	global_transform = Transform3D(Basis(q), p)
	apply_pose(sim.wheel_dist, sim.wheel_contact, sim.controls.steer, sim.wheel_spin, sim.boosting,
		sim.supersonic, cam, delta, now)
	if show_label and cam:
		label.visible = true
		label.global_position = p + Vector3(0, 1.25, 0)
	else:
		label.visible = false


func apply_pose(wd: PackedFloat32Array, wc: Array[bool], steer: float, spin: float, boosting: bool,
		supersonic: bool, cam: Camera3D, delta: float, now: float) -> void:
	_steer_vis = lerpf(_steer_vis, steer, minf(1.0, delta * 12.0))
	for i in range(4):
		var pivot: Node3D = wheels[i]
		var r: float = CarSim.WHEEL_RADIUS[i]
		var conn: Vector3 = CarSim.WHEEL_CONN[i]
		var dist: float = wd[i] if wc[i] else Phys.SUSP_REST + 0.03
		var y := conn.y - dist + r
		pivot.position.y = lerpf(pivot.position.y, y, minf(1.0, delta * 30.0))
		if i < 2:
			pivot.rotation.y = -_steer_vis * 0.45
		var spin_node: Node3D = pivot.get_child(0)
		spin_node.rotation.x = -spin
	_boost_vis = move_toward(_boost_vis, 1.0 if boosting else 0.0, delta * 10.0)
	flame.emitting = boosting
	flame_core.visible = _boost_vis > 0.02
	flame_core.scale = Vector3(1.0 + 0.15 * sin(now * 50.0), _boost_vis * (0.8 + 0.3 * sin(now * 37.0)), 1.0 + 0.15 * sin(now * 43.0))
	if tail_mat:
		tail_mat.emission_energy_multiplier = 3.0
	var cam_pos := cam.global_position if cam else Vector3.ZERO
	var rgt := global_transform.basis.x
	var back := global_transform.basis.z
	var low := -global_transform.basis.y
	for k in range(2):
		var side := -1.0 if k == 0 else 1.0
		trails[k].emitting = supersonic
		trails[k].update_trail(global_position + rgt * side * 0.38 + back * 0.42 + low * 0.08, cam_pos, now)
	boost_trail.emitting = boosting
	var ex: Vector3 = model.get_meta("exhaust")
	boost_trail.update_trail(global_transform * (ex + Vector3(0, 0, 0.1)), cam_pos, now)
