class_name CarFX
extends Node3D
## Tyre smoke / dust, skid marks, sparks, debris, nitro flames and landing dust.

var car: Car
var smoke: Array[CPUParticles3D] = []
var dust: Array[CPUParticles3D] = []
var spark_p: CPUParticles3D
var debris_p: CPUParticles3D
var land_p: CPUParticles3D
var flames: Array[MeshInstance3D] = []
var flame_mat: StandardMaterial3D
var last_mark := [null, null, null, null]
var detail := 1.0
var _t := 0.0

static var _soft: Texture2D


static func soft_tex() -> Texture2D:
	if _soft == null:
		var s := 64
		var img := Image.create(s, s, false, Image.FORMAT_RGBA8)
		for y in s:
			for x in s:
				var d := Vector2(x - s * 0.5 + 0.5, y - s * 0.5 + 0.5).length() / (s * 0.5)
				var a := clampf(1.0 - d, 0.0, 1.0)
				img.set_pixel(x, y, Color(1, 1, 1, a * a * (0.8 + 0.2 * sin(x * 0.7) * cos(y * 0.6))))
		_soft = ImageTexture.create_from_image(img)
	return _soft


func setup(c: Car) -> void:
	car = c
	detail = 1.0 if c.is_player else 0.5
	for i in 4:
		var sm := _particles(Color(0.82, 0.82, 0.84, 0.35), 24 if i >= 2 else 10, 1.8, 0.8, 3.2)
		sm.position = c.model.wheel_rest[i] - Vector3(0, c.model.wheel_radius * 0.8, 0)
		add_child(sm)
		smoke.append(sm)
		var du := _particles(Color(0.6, 0.5, 0.38, 0.4), 18, 1.4, 0.7, 2.8)
		du.position = sm.position
		add_child(du)
		dust.append(du)
	spark_p = CPUParticles3D.new()
	spark_p.emitting = false
	spark_p.one_shot = true
	spark_p.amount = 40
	spark_p.lifetime = 0.5
	spark_p.explosiveness = 0.9
	spark_p.direction = Vector3(0, 1, 0)
	spark_p.spread = 70.0
	spark_p.initial_velocity_min = 4.0
	spark_p.initial_velocity_max = 11.0
	spark_p.gravity = Vector3(0, -12, 0)
	spark_p.scale_amount_min = 1.0
	spark_p.scale_amount_max = 1.0
	var sq := QuadMesh.new()
	sq.size = Vector2(0.04, 0.16)
	var smat := StandardMaterial3D.new()
	smat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	smat.albedo_color = Color(1.0, 0.75, 0.3)
	smat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	smat.emission_enabled = true
	smat.emission = Color(1.0, 0.6, 0.2)
	smat.emission_energy_multiplier = 3.0
	sq.material = smat
	spark_p.mesh = sq
	spark_p.local_coords = false
	add_child(spark_p)
	debris_p = CPUParticles3D.new()
	debris_p.emitting = false
	debris_p.one_shot = true
	debris_p.amount = 14
	debris_p.lifetime = 1.6
	debris_p.explosiveness = 1.0
	debris_p.spread = 80.0
	debris_p.initial_velocity_min = 2.0
	debris_p.initial_velocity_max = 7.0
	debris_p.gravity = Vector3(0, -9.8, 0)
	debris_p.angular_velocity_min = -400
	debris_p.angular_velocity_max = 400
	debris_p.scale_amount_min = 1.0
	debris_p.scale_amount_max = 1.0
	var dbm := BoxMesh.new()
	dbm.size = Vector3(0.09, 0.03, 0.06)
	dbm.material = Mats.std("debris", Color(0.1, 0.1, 0.11), 0.5, 0.4)
	debris_p.mesh = dbm
	debris_p.local_coords = false
	add_child(debris_p)
	land_p = _particles(Color(0.7, 0.62, 0.5, 0.5), 30, 1.8, 1.5, 5.0)
	land_p.one_shot = true
	land_p.explosiveness = 0.9
	land_p.emitting = false
	add_child(land_p)
	# nitro flames from the exhausts
	flame_mat = StandardMaterial3D.new()
	flame_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	flame_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	flame_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	flame_mat.albedo_color = Color(0.35, 0.55, 1.0, 0.9)
	flame_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	var cone := CylinderMesh.new()
	cone.top_radius = 0.0
	cone.bottom_radius = 0.09
	cone.height = 0.8
	cone.radial_segments = 10
	cone.material = flame_mat
	var m := c.model
	for ex: float in [-0.35, 0.35]:
		var f := MeshInstance3D.new()
		f.mesh = cone
		f.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		f.rotation_degrees = Vector3(90, 0, 0)
		f.position = Vector3(ex * m.width * 0.5, m.style.cl + 0.32, m.length * 0.5 + 0.38 + float(m.style.get("front_off", 0.0)))
		f.visible = false
		add_child(f)
		flames.append(f)


func _particles(col: Color, amount: int, life: float, size_min: float, size_max: float) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.emitting = false
	p.amount = amount
	p.lifetime = life
	p.local_coords = false
	p.direction = Vector3(0, 1, 0)
	p.spread = 45.0
	p.initial_velocity_min = 0.6
	p.initial_velocity_max = 2.2
	p.gravity = Vector3(0, 0.6, 0)
	p.damping_min = 0.6
	p.damping_max = 1.5
	p.scale_amount_min = size_min
	p.scale_amount_max = size_max
	var curve := Curve.new()
	curve.add_point(Vector2(0, 0.25))
	curve.add_point(Vector2(0.4, 0.8))
	curve.add_point(Vector2(1, 1.0))
	p.scale_amount_curve = curve
	var grad := Gradient.new()
	grad.set_color(0, Color(col.r, col.g, col.b, col.a))
	grad.set_color(1, Color(col.r, col.g, col.b, 0.0))
	p.color_ramp = grad
	var q := QuadMesh.new()
	q.size = Vector2(1, 1)
	var m := StandardMaterial3D.new()
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.vertex_color_use_as_albedo = true
	m.albedo_texture = soft_tex()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_PER_VERTEX
	m.disable_receive_shadows = true
	m.distance_fade_mode = BaseMaterial3D.DISTANCE_FADE_PIXEL_ALPHA
	m.distance_fade_min_distance = 1.5
	m.distance_fade_max_distance = 6.0
	q.material = m
	p.mesh = q
	return p


func _process(delta: float) -> void:
	if car == null:
		return
	_t += delta
	var cam := get_viewport().get_camera_3d()
	var near := cam != null and cam.global_position.distance_to(car.global_position) < 140.0
	for i in 4:
		var w: Dictionary = car.wheels[i]
		var slipping: bool = w.contact and (w.slip_lat > 0.7 or absf(w.slip_long) > 0.5) and car.speed_abs > 5.0
		var surf: String = w.surface
		var paved: bool = surf in ["asphalt", "concrete", "cobble", "stone"]
		var loose: bool = surf in ["dirt", "gravel", "sand", "grass", "snow"]
		var dusty: bool = w.contact and loose and car.speed_abs > 6.0
		smoke[i].emitting = near and slipping and paved and (detail > 0.6 or i >= 2)
		dust[i].emitting = near and (dusty or (slipping and loose))
		if dusty:
			var dc := Color(0.62, 0.52, 0.38, 0.5)
			if surf == "sand":
				dc = Color(0.85, 0.75, 0.55, 0.5)
			elif surf == "snow":
				dc = Color(0.95, 0.97, 1.0, 0.6)
			elif surf == "grass":
				dc = Color(0.45, 0.42, 0.3, 0.35)
			dust[i].color_ramp.set_color(0, dc)
		# skid marks
		if SkidMarks.instance and w.contact and (slipping or (loose and car.speed_abs > 4.0)):
			var p: Vector3 = w.point
			var prev = last_mark[i]
			if prev != null and (prev as Vector3).distance_to(p) > 0.35 and (prev as Vector3).distance_to(p) < 3.0:
				var dir: Vector3 = (p - prev).normalized()
				var right: Vector3 = dir.cross(Vector3.UP).normalized()
				var col := Color(0.03, 0.03, 0.03, 0.55) if paved else Color(0.2, 0.15, 0.1, 0.45)
				if not slipping:
					col.a *= 0.4
				SkidMarks.instance.add_segment(prev, p, right, 0.24, col)
				last_mark[i] = p
			elif prev == null or (prev as Vector3).distance_to(p) >= 3.0:
				last_mark[i] = p
		else:
			last_mark[i] = null
	# nitro flames flicker
	var on := car.nitro_active
	for f in flames:
		f.visible = on
		if on:
			var s := 0.8 + 0.4 * sin(_t * 60.0 + f.position.x * 10.0) + randf() * 0.3
			f.scale = Vector3(1.0, s * 1.6, 1.0)
	flame_mat.albedo_color = Color(0.35 + 0.2 * randf(), 0.55, 1.0, 0.9)


func sparks(point: Vector3, normal: Vector3, _strength: float) -> void:
	if spark_p.emitting:
		return
	spark_p.global_position = point
	spark_p.direction = normal
	spark_p.restart()
	spark_p.emitting = true


func debris(point: Vector3, strength: float) -> void:
	if strength < 0.4:
		return
	debris_p.global_position = point
	debris_p.restart()
	debris_p.emitting = true


func landed(air: float) -> void:
	land_p.global_position = car.global_position - Vector3(0, 0.3, 0)
	land_p.amount = int(clampf(air * 30.0, 10, 40))
	land_p.restart()
	land_p.emitting = true
	if car.audio:
		car.audio.thud(clampf(air, 0.3, 1.5))


func shifted() -> void:
	pass
