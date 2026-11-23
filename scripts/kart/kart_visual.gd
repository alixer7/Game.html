class_name KartVisual
extends Node3D
## Presentation layer for a Kart: model, body motion, wheels, particles, audio.
## Reads Kart state only; never feeds back into physics.

var kart: Kart
var character := {}
var model: Node3D
var _tilt: Node3D
var _wheels := {}
var _steer_wheel: Node3D
var _head: Node3D
var _scarf: Node3D
var _wheel_angle := 0.0
var _pitch_vel := 0.0
var _pitch := 0.0
var _squash := 0.0
var _squash_vel := 0.0
var _roll := 0.0
var _extra_yaw := 0.0
var _spin_vis := 0.0
var _sparks: Array[GPUParticles3D] = []
var _dust: Array[GPUParticles3D] = []
var _flames: Array[MeshInstance3D] = []
var _flame_mat: StandardMaterial3D
var _burst: GPUParticles3D
var _impact_fx: GPUParticles3D
var _shield: MeshInstance3D
var _engine: AudioStreamPlayer3D
var _spark_mat: StandardMaterial3D
var _dust_mat: StandardMaterial3D
var _t := 0.0


func setup(k: Kart, ch: Dictionary) -> void:
	kart = k
	character = ch
	_tilt = Node3D.new()
	_tilt.name = "Tilt"
	add_child(_tilt)
	model = KartModel.build(ch)
	_tilt.add_child(model)
	for n in ["WheelFL", "WheelFR", "WheelRL", "WheelRR"]:
		_wheels[n] = model.get_node(n)
	_steer_wheel = model.get_node("SteeringWheel")
	_head = model.get_node("Driver/Head")
	_scarf = model.get_node("Driver/Scarf")
	_build_fx()
	kart.spark.connect(_on_spark)
	kart.impact.connect(_on_impact)
	kart.landed.connect(_on_landed)
	kart.hopped.connect(_on_hop)
	kart.fizzle.connect(_on_fizzle)
	kart.tier_changed.connect(_on_tier)
	_engine = Sfx.make_engine_voice(self, kart.is_player)
	if _engine.stream is AudioStreamWAV:
		var w := _engine.stream as AudioStreamWAV
		w.loop_mode = AudioStreamWAV.LOOP_FORWARD
		w.loop_begin = 0
		w.loop_end = int(w.get_length() * w.mix_rate)


func _build_fx() -> void:
	_spark_mat = StandardMaterial3D.new()
	_spark_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_spark_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_spark_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_spark_mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	_spark_mat.vertex_color_use_as_albedo = true
	_spark_mat.albedo_texture = EnvLife.soft_texture()
	_dust_mat = StandardMaterial3D.new()
	_dust_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_dust_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_dust_mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	_dust_mat.vertex_color_use_as_albedo = true
	_dust_mat.albedo_texture = EnvLife.soft_texture()
	_dust_mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	for s in [-1.0, 1.0]:
		var sp := _make_particles(26, 0.35, 0.12, _spark_mat)
		var pm := ParticleProcessMaterial.new()
		pm.direction = Vector3(-s * 0.6, 0.6, 1.0)
		pm.spread = 25.0
		pm.initial_velocity_min = 3.0
		pm.initial_velocity_max = 6.0
		pm.gravity = Vector3(0, -12, 0)
		pm.scale_min = 0.6
		pm.scale_max = 1.3
		pm.color = Color(0.6, 0.85, 1.0)
		sp.process_material = pm
		sp.position = Vector3(0.6 * s, 0.08, 0.6)
		sp.emitting = false
		sp.local_coords = false
		_tilt.add_child(sp)
		_sparks.append(sp)
		var du := _make_particles(16, 0.9, 0.7, _dust_mat)
		var dm := ParticleProcessMaterial.new()
		dm.direction = Vector3(0, 0.5, 1.0)
		dm.spread = 30.0
		dm.initial_velocity_min = 1.0
		dm.initial_velocity_max = 2.5
		dm.gravity = Vector3(0, 0.5, 0)
		dm.scale_min = 0.6
		dm.scale_max = 1.4
		var curve := Curve.new()
		curve.add_point(Vector2(0, 0.5))
		curve.add_point(Vector2(1, 1.6))
		var ct := CurveTexture.new()
		ct.curve = curve
		dm.scale_curve = ct
		var grad := Gradient.new()
		grad.set_color(0, Color(1, 1, 1, 0.55))
		grad.set_color(1, Color(1, 1, 1, 0.0))
		var gt := GradientTexture1D.new()
		gt.gradient = grad
		dm.color_ramp = gt
		dm.color = Color(0.75, 0.62, 0.45)
		du.process_material = dm
		du.position = Vector3(0.6 * s, 0.1, 0.65)
		du.emitting = false
		du.local_coords = false
		_tilt.add_child(du)
		_dust.append(du)
	# exhaust flames
	_flame_mat = StandardMaterial3D.new()
	_flame_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_flame_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_flame_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_flame_mat.vertex_color_use_as_albedo = true
	_flame_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	var fmb := MeshBuilder.new()
	MeshLib.tube(fmb, PackedVector3Array([Vector3(0, 0, 0), Vector3(0, 0.02, 0.35), Vector3(0, 0.05, 0.8)]), PackedFloat32Array([0.09, 0.11, 0.0]), 7,
		func(t: float, _a: float, _p: Vector3) -> Color: return Color(1, 1, 0.9, 1).lerp(Color(1, 0.4, 0.1, 0.0), t), 1.0, false)
	var fmesh := fmb.commit()
	for n in ["ExhaustL", "ExhaustR"]:
		var m := model.get_node(n) as Marker3D
		var fi := MeshInstance3D.new()
		fi.mesh = fmesh
		fi.material_override = _flame_mat
		fi.visible = false
		fi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		fi.rotation = Vector3(0.35, 0, 0)
		m.add_child(fi)
		_flames.append(fi)
	_burst = _make_particles(40, 0.5, 0.18, _spark_mat)
	var bm := ParticleProcessMaterial.new()
	bm.direction = Vector3(0, 0.5, 1)
	bm.spread = 70.0
	bm.initial_velocity_min = 4.0
	bm.initial_velocity_max = 9.0
	bm.gravity = Vector3(0, -6, 0)
	_burst.process_material = bm
	_burst.one_shot = true
	_burst.emitting = false
	_burst.explosiveness = 0.95
	_burst.position = Vector3(0, 0.6, 1.0)
	_burst.local_coords = false
	_tilt.add_child(_burst)
	_impact_fx = _make_particles(30, 0.45, 0.14, _spark_mat)
	var im := ParticleProcessMaterial.new()
	im.direction = Vector3(0, 1, 0)
	im.spread = 80.0
	im.initial_velocity_min = 3.0
	im.initial_velocity_max = 8.0
	im.gravity = Vector3(0, -14, 0)
	im.color = Color(1.0, 0.8, 0.4)
	_impact_fx.process_material = im
	_impact_fx.one_shot = true
	_impact_fx.emitting = false
	_impact_fx.explosiveness = 1.0
	_impact_fx.local_coords = false
	add_child(_impact_fx)
	_shield = MeshInstance3D.new()
	var sph := SphereMesh.new()
	sph.radius = 1.25
	sph.height = 2.0
	_shield.mesh = sph
	var shm := StandardMaterial3D.new()
	shm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	shm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	shm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	shm.albedo_color = Color(0.3, 0.7, 1.0, 0.35)
	shm.rim_enabled = true
	_shield.material_override = shm
	_shield.position = Vector3(0, 0.7, 0)
	_shield.visible = false
	_shield.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_tilt.add_child(_shield)


func _make_particles(amount: int, lifetime: float, size: float, mat: Material) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = amount
	p.lifetime = lifetime
	var q := QuadMesh.new()
	q.size = Vector2(size, size)
	q.material = mat
	p.draw_pass_1 = q
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.visibility_aabb = AABB(Vector3(-6, -3, -6), Vector3(12, 8, 12))
	return p


func _process(dt: float) -> void:
	if kart == null:
		return
	_t += dt
	# ---- base orientation: ground normal + chassis yaw (+ exaggerated slide angle)
	var target_extra := 0.0
	if kart.drifting:
		target_extra = float(kart.drift_dir) * -0.16
	_extra_yaw = lerpf(_extra_yaw, target_extra, clampf(dt * 8.0, 0.0, 1.0))
	if kart.spin_time > 0.0:
		_spin_vis += dt * 14.0
	else:
		_spin_vis = lerpf(_spin_vis, round(_spin_vis / TAU) * TAU, clampf(dt * 10.0, 0, 1))
	var up := kart.smooth_normal
	var yaw_basis := Basis(Vector3.UP, kart.yaw + _extra_yaw + _spin_vis)
	var fwd := -(yaw_basis.z)
	fwd = (fwd - up * fwd.dot(up)).normalized()
	var right := fwd.cross(up).normalized()
	var b := Basis(right, up, -fwd).orthonormalized()
	# ---- body dynamics: roll into slides, pitch with accel/landings, squash
	var lean_target := -kart.steer_smoothed * clampf(kart.speed / 20.0, 0.0, 1.0) * 0.07
	if kart.drifting:
		lean_target = float(kart.drift_dir) * 0.1
	_roll = lerpf(_roll, lean_target, clampf(dt * 6.0, 0.0, 1.0))
	var accel_pitch := -0.04 * kart.in_throttle + 0.05 * kart.in_brake
	_pitch_vel += ((accel_pitch - _pitch) * 60.0 - _pitch_vel * 8.0) * dt
	_pitch += _pitch_vel * dt
	_squash_vel += (-_squash * 180.0 - _squash_vel * 12.0) * dt
	_squash += _squash_vel * dt
	if not kart.grounded:
		var vy := kart.velocity.y
		_pitch = lerpf(_pitch, clampf(-vy * 0.02, -0.25, 0.25), clampf(dt * 3.0, 0.0, 1.0))
	var tilt := Basis(Vector3.FORWARD, _roll) * Basis(Vector3.RIGHT, _pitch)
	global_transform = Transform3D(b, kart.global_position)
	_tilt.transform = Transform3D(tilt.scaled(Vector3(1.0 + _squash * 0.5, 1.0 - _squash, 1.0 + _squash * 0.5)), Vector3.ZERO)
	# ---- wheels
	_wheel_angle += kart.forward_speed / KartModel.REAR_R * dt
	var steer_vis := kart.steer_smoothed * 0.42
	if kart.drifting:
		steer_vis = -float(kart.drift_dir) * 0.35 + kart.steer_smoothed * 0.2
	for n in _wheels:
		var w: Node3D = _wheels[n]
		var spin := w.get_node("Spin") as Node3D
		spin.rotation = Vector3(_wheel_angle * (KartModel.REAR_R / (KartModel.FRONT_R if n.begins_with("WheelF") else KartModel.REAR_R)), 0, 0)
		if n.begins_with("WheelF"):
			w.rotation = Vector3(0, -steer_vis, 0)
	(_steer_wheel.get_child(0) as Node3D).rotation = Vector3(0, -steer_vis * 2.4, 0)
	_head.rotation = Vector3(0, -kart.steer_smoothed * 0.25, kart.steer_smoothed * 0.08)
	_scarf.rotation = Vector3(0.2 + clampf(kart.speed / 30.0, 0.0, 1.0) * 0.5 + sin(_t * 18.0) * 0.06, sin(_t * 11.0) * 0.12, 0)
	# ---- particles
	var sliding := kart.drifting and kart.grounded
	var col := Color(0.55, 0.8, 1.0)
	var p := kart.params
	if kart.drift_stage >= 3:
		col = Color(0.5, 0.5, 0.55)
	elif kart.drift_charge >= p.perfect_zone:
		col = Color(1.0, 0.25, 0.35)
	elif kart.drift_charge >= p.hot_zone:
		col = Color(1.0, 0.72, 0.15)
	for i in _sparks.size():
		var s := _sparks[i]
		s.emitting = sliding
		(s.process_material as ParticleProcessMaterial).color = col
		s.amount_ratio = 0.5 + 0.5 * kart.drift_charge
	var info := Surfaces.get_info(kart.surface)
	var fx: int = info.fx
	var dusty := kart.grounded and kart.speed > 6.0 and (fx in [1, 2, 3, 4] and (Surfaces.is_offroad(kart.surface) or kart.drifting or Surfaces.is_water(kart.surface)))
	for d in _dust:
		d.emitting = dusty
		var dm := d.process_material as ParticleProcessMaterial
		match fx:
			2:
				dm.color = Color(0.45, 0.65, 0.25)
			3:
				dm.color = Color(0.85, 0.95, 1.0)
			4:
				dm.color = Color(0.35, 0.25, 0.15)
			_:
				dm.color = Color(0.78, 0.66, 0.5)
	# ---- boost flames
	var flame_on := kart.tier > 0
	for f in _flames:
		f.visible = flame_on
		if flame_on:
			var flick := 0.85 + 0.3 * sin(_t * 47.0 + f.get_instance_id())
			var l := (1.0 + clampf(kart.reserve / 3.0, 0.0, 1.0)) * flick
			f.scale = Vector3(1.0, 1.0, l * (1.5 if kart.tier == 2 else 1.0))
	_flame_mat.albedo_color = Color(1.0, 0.65, 0.2) if kart.tier == 1 else Color(0.3, 0.95, 1.0)
	_shield.visible = kart.shielded
	if _shield.visible:
		_shield.rotation.y += dt * 2.0
	# ---- engine voice
	if _engine and _engine.stream:
		var sp := absf(kart.forward_speed) / kart.params.max_speed
		_engine.pitch_scale = clampf(0.55 + sp * 1.05 + (0.15 if kart.tier > 0 else 0.0) + (0.1 if not kart.grounded else 0.0), 0.4, 2.4)
		if kart.frozen:
			_engine.pitch_scale = 0.5 + kart.in_throttle * 0.6


func _on_spark(stage: int, _q: float, perfect: bool, hooked: bool) -> void:
	var bm := _burst.process_material as ParticleProcessMaterial
	bm.color = Color(1.0, 0.3, 0.4) if perfect else Color(1.0, 0.75, 0.25)
	if hooked:
		bm.color = Color(0.7, 0.4, 1.0)
	_burst.restart()
	_squash = -0.06
	if kart.is_player:
		Sfx.play("spark_perfect" if perfect else "spark%d" % (stage + 1))
		Game.haptic(18 if perfect else 10)


func _on_fizzle(reason: StringName) -> void:
	if kart.is_player:
		Sfx.play("backfire" if reason == &"late" else "fizzle")


func _on_tier(t: int) -> void:
	if kart.is_player and t == 2:
		Sfx.play("overdrive")
	elif kart.is_player and t == 1:
		Sfx.play("boost", null, 1.0, -4.0)


func _on_hop() -> void:
	_squash = 0.08
	if kart.is_player:
		Sfx.play("hop", null, 1.0, -6.0)


func _on_landed(airtime: float, _good: bool, impact_speed: float) -> void:
	_squash = clampf(impact_speed * 0.012, 0.0, 0.16)
	if kart.is_player and airtime > 0.25:
		Sfx.play("land", null, 1.0, -3.0 if airtime > 0.6 else -8.0)
		if Surfaces.is_water(kart.surface):
			Sfx.play("splash")


func _on_impact(sev: int, strength: float, point: Vector3) -> void:
	_impact_fx.global_position = point
	(_impact_fx.process_material as ParticleProcessMaterial).initial_velocity_max = 4.0 + strength * 0.4
	_impact_fx.restart()
	if kart.is_player:
		Sfx.play("scrape" if sev == 0 else "thud", null, 1.0, -6.0 if sev == 0 else 0.0)
		Game.haptic(15 + sev * 25)
