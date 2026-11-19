class_name Hazards
extends RefCounted
## Things that hurt: spike plates, saw blades, laser gates, plus the harmless pinball bumper.
## Every hazard polls its overlap each physics frame and calls player.hurt(from, 1).

const RED := Color(1.0, 0.25, 0.32)


# ---------------------------------------------------------------- spikes
## Floor plate of spikes. p = centre of the plate surface, s = [width, depth],
## per = cycle length in seconds (<= 0 means always out), ph = phase 0..1, out = fraction of the cycle spikes are out.
class Spikes extends Area3D:
	var world: Node = null
	var _per: float = 3.0
	var _ph: float = 0.0
	var _frac: float = 0.55
	var _ext: float = 0.0
	var _blades: MultiMeshInstance3D
	var _glow_mat: StandardMaterial3D
	var _glow: MeshInstance3D

	func setup(o: Dictionary) -> void:
		position = LevelLoader.vec(o.get("p"))
		rotation_degrees.y = float(o.get("ry", 0.0))
		var sz: Array = o.get("s", [3.0, 3.0])
		var w: float = float(sz[0])
		var d: float = float(sz[sz.size() - 1])
		_per = float(o.get("per", 3.0))
		_ph = float(o.get("ph", 0.0))
		_frac = float(o.get("out", 0.55))
		collision_layer = 0
		collision_mask = 2
		var cs := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = Vector3(w, 1.0, d)
		cs.shape = bs
		cs.position = Vector3(0.0, 0.5, 0.0)
		add_child(cs)

		var plate := MeshInstance3D.new()
		var pb := BoxMesh.new()
		pb.size = Vector3(w, 0.1, d)
		plate.mesh = pb
		plate.material_override = Mats.std(Color(0.1, 0.06, 0.09), 0.6, 0.4)
		plate.position = Vector3(0.0, 0.0, 0.0)
		add_child(plate)

		_glow_mat = StandardMaterial3D.new()
		_glow_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_glow_mat.albedo_color = Zones.hdr(Hazards.RED, 0.8)
		var pm := PlaneMesh.new()
		pm.size = Vector2(w * 0.94, d * 0.94)
		_glow = MeshInstance3D.new()
		_glow.mesh = pm
		_glow.material_override = _glow_mat
		_glow.position = Vector3(0.0, 0.06, 0.0)
		_glow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(_glow)

		var nx: int = maxi(2, int(round(w / 0.8)))
		var nz: int = maxi(2, int(round(d / 0.8)))
		var cone := CylinderMesh.new()
		cone.top_radius = 0.0
		cone.bottom_radius = 0.24
		cone.height = 0.9
		cone.radial_segments = 8
		cone.rings = 1
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = cone
		mm.instance_count = nx * nz
		var k: int = 0
		for ix in range(nx):
			for iz in range(nz):
				var x: float = (float(ix) + 0.5) / float(nx) * w - w * 0.5
				var z: float = (float(iz) + 0.5) / float(nz) * d - d * 0.5
				mm.set_instance_transform(k, Transform3D(Basis.IDENTITY, Vector3(x, 0.45, z)))
				k += 1
		_blades = MultiMeshInstance3D.new()
		_blades.multimesh = mm
		_blades.material_override = Mats.std(Color(0.78, 0.8, 0.88), 0.9, 0.25, Hazards.RED, 0.5)
		_blades.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_blades.position = Vector3(0.0, 0.05, 0.0)
		_blades.scale = Vector3(1.0, 0.001, 1.0)
		_blades.visible = false
		add_child(_blades)

	func _physics_process(delta: float) -> void:
		if world == null:
			return
		var target: float = 1.0
		var warn: bool = false
		if _per > 0.01:
			var t: float = fposmod(float(world.time) + _ph * _per, _per)
			var out_len: float = _per * _frac
			if t >= out_len:
				target = 0.0
				if t > _per - 0.45 and (_per - out_len) > 0.8:
					target = 0.14
					warn = true
		_ext = move_toward(_ext, target, delta * (16.0 if target > _ext else 5.0))
		_blades.visible = _ext > 0.02
		_blades.scale = Vector3(1.0, maxf(_ext, 0.001), 1.0)
		var glow: float = 0.7
		if _ext > 0.45:
			glow = 2.6
		elif warn:
			glow = 1.8 + sin(float(world.time) * 40.0) * 0.8
		_glow_mat.albedo_color = Zones.hdr(Hazards.RED, glow)
		if _ext < 0.45:
			return
		var pl: Player = Zones.player_of(world)
		if pl != null and pl.global_position.y < global_position.y + 0.8 and overlaps_body(pl):
			pl.hurt(global_position, 1)


# ------------------------------------------------------------------- saw
## Spinning blade, optionally patrolling along `off` (period `per`). p = blade centre, r = radius.
class Saw extends Area3D:
	var world: Node = null
	var _a := Vector3.ZERO
	var _off := Vector3.ZERO
	var _per: float = 4.0
	var _ph: float = 0.0
	var _disc: Node3D

	func setup(o: Dictionary) -> void:
		_a = LevelLoader.vec(o.get("p"))
		position = _a
		_off = LevelLoader.vec(o.get("off"))
		_per = maxf(0.5, float(o.get("per", 4.0)))
		_ph = float(o.get("ph", 0.0))
		var r: float = float(o.get("r", 1.1))
		collision_layer = 0
		collision_mask = 2
		var cs := CollisionShape3D.new()
		var sp := SphereShape3D.new()
		sp.radius = r * 0.92
		cs.shape = sp
		add_child(cs)

		var horiz := Vector3(_off.x, 0.0, _off.z)
		var axis: Vector3 = Vector3.UP.cross(horiz)
		if axis.length() < 0.1:
			axis = Vector3.RIGHT
		_disc = Node3D.new()
		_disc.basis = Platforms.basis_y(axis)
		add_child(_disc)
		var body := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = r
		cm.bottom_radius = r
		cm.height = 0.14
		cm.radial_segments = 36
		cm.rings = 1
		body.mesh = cm
		body.material_override = Mats.std(Color(0.72, 0.76, 0.86), 0.95, 0.22)
		_disc.add_child(body)
		var rim := MeshInstance3D.new()
		var tm := TorusMesh.new()
		tm.inner_radius = r * 0.78
		tm.outer_radius = r * 0.9
		tm.rings = 36
		tm.ring_segments = 6
		rim.mesh = tm
		rim.material_override = Mats.neon(Hazards.RED, 2.4, 1.0, 0.8)
		rim.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_disc.add_child(rim)
		var tooth_mat: StandardMaterial3D = Mats.std(Color(0.85, 0.87, 0.95), 0.95, 0.2, Hazards.RED, 0.6)
		for i in range(10):
			var a: float = TAU * float(i) / 10.0
			var tooth := MeshInstance3D.new()
			var tb := BoxMesh.new()
			tb.size = Vector3(0.3, 0.13, 0.36)
			tooth.mesh = tb
			tooth.material_override = tooth_mat
			tooth.position = Vector3(cos(a) * r, 0.0, sin(a) * r)
			tooth.rotation.y = -a + 0.5
			_disc.add_child(tooth)
		for i in range(2):
			var spoke := MeshInstance3D.new()
			var sb := BoxMesh.new()
			sb.size = Vector3(r * 1.7, 0.2, 0.14)
			spoke.mesh = sb
			spoke.material_override = Mats.std(Color(0.2, 0.08, 0.1), 0.5, 0.4, Hazards.RED, 1.2)
			spoke.rotation.y = PI * 0.5 * float(i)
			_disc.add_child(spoke)

	func _ready() -> void:
		var parent: Node = get_parent()
		if parent != null and _off.length() > 0.3:
			Platforms.make_line(parent, _a, _a + _off, 0.05, Mats.neon(Hazards.RED, 1.4, 1.0, 0.55, 0.5))

	func _physics_process(delta: float) -> void:
		if world == null:
			return
		var t: float = float(world.time)
		if _off.length() > 0.01:
			var k: float = 0.5 - 0.5 * cos(TAU * (t / _per + _ph))
			position = _a + _off * k
		_disc.rotate_object_local(Vector3.UP, delta * 9.0)
		var pl: Player = Zones.player_of(world)
		if pl != null and overlaps_body(pl):
			pl.hurt(global_position, 1)


# ----------------------------------------------------------------- laser
## Laser gate between two emitters a and b (world points). Cycles on/off; phase `ph` in 0..1.
class Laser extends Node3D:
	var world: Node = null
	var _a := Vector3.ZERO
	var _b := Vector3.ZERO
	var _on: float = 2.0
	var _off: float = 1.5
	var _ph: float = 0.0
	var _beam: MeshInstance3D
	var _mat_on: ShaderMaterial
	var _mat_warn: ShaderMaterial
	var _level: float = 0.0
	var _hum: bool = false

	func setup(o: Dictionary) -> void:
		_a = LevelLoader.vec(o.get("a"))
		_b = LevelLoader.vec(o.get("b"))
		_on = maxf(0.2, float(o.get("on", 2.0)))
		_off = maxf(0.0, float(o.get("off", 1.5)))
		_ph = float(o.get("ph", 0.0))
		var length: float = maxf(_a.distance_to(_b), 0.5)
		var cm := CylinderMesh.new()
		cm.top_radius = 0.11
		cm.bottom_radius = 0.11
		cm.height = length
		cm.radial_segments = 10
		cm.rings = 1
		_mat_on = Mats.neon(Hazards.RED, 3.4, 0.8, 0.95)
		_mat_warn = Mats.neon(Hazards.RED, 1.3, 1.0, 0.3, 0.6)
		_beam = MeshInstance3D.new()
		_beam.mesh = cm
		_beam.material_override = _mat_warn
		_beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_beam.transform = Transform3D(Platforms.basis_y(_b - _a), (_a + _b) * 0.5)
		add_child(_beam)
		for end in [_a, _b]:
			var e: Vector3 = end
			var em := MeshInstance3D.new()
			var sm := SphereMesh.new()
			sm.radius = 0.32
			sm.height = 0.64
			em.mesh = sm
			em.material_override = Mats.std(Color(0.14, 0.1, 0.14), 0.8, 0.3, Hazards.RED, 1.0)
			em.position = e
			add_child(em)

	func _physics_process(delta: float) -> void:
		if world == null:
			return
		var cyc: float = _on + _off
		var is_on: bool = true
		var warn: bool = false
		if _off > 0.01:
			var t: float = fposmod(float(world.time) + _ph * cyc, cyc)
			is_on = t < _on
			warn = (not is_on) and t > cyc - 0.6
		if is_on:
			_beam.visible = true
			_beam.material_override = _mat_on
			_level = move_toward(_level, 1.0, delta * 8.0)
			_beam.scale = Vector3(_level, 1.0, _level)
		elif warn:
			_beam.visible = true
			_beam.material_override = _mat_warn
			_level = 0.25
			_beam.scale = Vector3(_level, 1.0, _level)
		else:
			_beam.visible = false
			_level = 0.0
		if is_on != _hum:
			_hum = is_on
			if is_on:
				Sfx.play("zap", -10.0, 0.7)
		if not is_on or _level < 0.7:
			return
		var pl: Player = Zones.player_of(world)
		if pl == null:
			return
		var feet: Vector3 = pl.global_position + Vector3(0.0, 0.25, 0.0)
		var head: Vector3 = pl.global_position + Vector3(0.0, 0.85, 0.0)
		var d: float = minf(Hazards.seg_dist(feet, _a, _b), Hazards.seg_dist(head, _a, _b))
		if d < 0.5:
			pl.hurt(Hazards.closest_on_seg(head, _a, _b), 1)


static func closest_on_seg(p: Vector3, a: Vector3, b: Vector3) -> Vector3:
	var ab: Vector3 = b - a
	var l2: float = ab.length_squared()
	if l2 < 0.0001:
		return a
	var t: float = clampf((p - a).dot(ab) / l2, 0.0, 1.0)
	return a + ab * t


static func seg_dist(p: Vector3, a: Vector3, b: Vector3) -> float:
	return p.distance_to(closest_on_seg(p, a, b))


# ---------------------------------------------------------------- bumper
## Pinball bumper: shoves the player away (harmless). p = base centre on the floor.
class Bumper extends Area3D:
	var world: Node = null
	var _pow: float = 15.0
	var _r: float = 0.9
	var _cool: float = 0.0
	var _squash: float = 0.0
	var _top: MeshInstance3D
	var _col := Color.WHITE

	func setup(o: Dictionary) -> void:
		position = LevelLoader.vec(o.get("p"))
		_pow = float(o.get("pow", 15.0))
		_r = float(o.get("r", 0.9))
		_col = Mats.accent(int(o.get("c", 2)))
		collision_layer = 0
		collision_mask = 2
		var cs := CollisionShape3D.new()
		var cy := CylinderShape3D.new()
		cy.radius = _r + 0.45
		cy.height = 1.8
		cs.shape = cy
		cs.position = Vector3(0.0, 0.9, 0.0)
		add_child(cs)
		var post := MeshInstance3D.new()
		var pm := CylinderMesh.new()
		pm.top_radius = _r * 0.9
		pm.bottom_radius = _r
		pm.height = 1.1
		pm.radial_segments = 28
		post.mesh = pm
		post.material_override = Mats.std(Color(0.1, 0.12, 0.2), 0.7, 0.3)
		post.position = Vector3(0.0, 0.55, 0.0)
		add_child(post)
		_top = MeshInstance3D.new()
		var tm := TorusMesh.new()
		tm.inner_radius = _r * 0.86
		tm.outer_radius = _r * 1.04
		tm.rings = 28
		tm.ring_segments = 8
		_top.mesh = tm
		_top.material_override = Mats.neon(_col, 2.6, 1.2, 0.85)
		_top.position = Vector3(0.0, 0.8, 0.0)
		_top.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(_top)
		var cap := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = _r * 0.62
		sm.height = _r * 1.24
		cap.mesh = sm
		cap.material_override = Mats.flat(Zones.hdr(_col, 2.0))
		cap.position = Vector3(0.0, 1.15, 0.0)
		cap.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(cap)

	func _physics_process(delta: float) -> void:
		_cool = maxf(_cool - delta, 0.0)
		_squash = move_toward(_squash, 0.0, delta * 4.0)
		_top.scale = Vector3.ONE * (1.0 + 0.25 * _squash)
		if _cool > 0.0:
			return
		var pl: Player = Zones.player_of(world)
		if pl == null or not overlaps_body(pl):
			return
		var away: Vector3 = pl.global_position - global_position
		away.y = 0.0
		if away.length() < 0.05:
			away = Vector3.FORWARD
		away = away.normalized()
		pl.launch(away * _pow + Vector3(0.0, 7.5, 0.0))
		_cool = 0.3
		_squash = 1.0
		Sfx.play("bounce", -3.0, 1.25)
		Game.vibrate(20)
		Fx.ring(self, global_position, _col, _r * 4.0, 0.4, 2.5)
		Fx.burst(self, global_position + Vector3(0.0, 1.0, 0.0), _col, 10, 5.0, 0.3, 0.5, -2.0)
