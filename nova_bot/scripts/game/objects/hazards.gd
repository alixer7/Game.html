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


# ----------------------------------------------------------- sweep laser
## Laser arms rotating around a pylon, low enough to jump over. p = floor centre, len = arm length,
## h = beam height above the floor, speed (rad/s), arms = 1..4, ph = start angle (turns).
class SweepLaser extends Node3D:
	var world: Node = null
	var _len: float = 6.0
	var _h: float = 0.55
	var _speed: float = 1.2
	var _arms: int = 1
	var _ph: float = 0.0
	var _rot: Node3D
	var _cool: float = 0.0

	func setup(o: Dictionary) -> void:
		position = LevelLoader.vec(o.get("p"))
		_len = float(o.get("len", 6.0))
		_h = float(o.get("h", 0.55))
		_speed = float(o.get("speed", 1.2))
		_arms = clampi(int(o.get("arms", 1)), 1, 4)
		_ph = float(o.get("ph", 0.0))
		Geo.put(self, Geo.lathe(PackedVector2Array([Vector2(0.0, 0.0), Vector2(0.75, 0.0), Vector2(0.6, 0.3), Vector2(0.45, _h + 0.3), Vector2(0.0, _h + 0.4)]), 20, "sweep_pylon%.2f" % _h), Mats.metal(Color(0.2, 0.18, 0.22), 0.35, 0.8))
		_rot = Node3D.new()
		_rot.position = Vector3(0.0, _h, 0.0)
		add_child(_rot)
		Geo.put(_rot, Geo.cyl(0.5, 0.5, 0.25, 16), Mats.glow(Hazards.RED, 2.4), Vector3.ZERO, Vector3.ZERO, Vector3.ONE, false)
		for i in range(_arms):
			var a: float = TAU * float(i) / float(_arms)
			var arm := Node3D.new()
			arm.rotation.y = a
			_rot.add_child(arm)
			Geo.put(arm, Geo.cyl(0.09, 0.09, _len, 10), Mats.neon(Hazards.RED, 3.4, 0.8, 0.95), Vector3(0.0, 0.0, -_len * 0.5), Vector3(90.0, 0.0, 0.0), Vector3.ONE, false)
			Geo.put(arm, Geo.cyl(0.22, 0.22, _len, 10), Mats.neon(Hazards.RED, 1.2, 1.5, 0.2, 0.6), Vector3(0.0, 0.0, -_len * 0.5), Vector3(90.0, 0.0, 0.0), Vector3.ONE, false)
			Geo.put(arm, Geo.sphere(0.25, 10), Mats.std(Color(0.2, 0.15, 0.18), 0.8, 0.3, Hazards.RED, 1.5), Vector3(0.0, 0.0, -_len))

	func _physics_process(delta: float) -> void:
		if world == null:
			return
		var ang: float = _ph * TAU + float(world.time) * _speed
		_rot.rotation.y = ang
		_cool = maxf(_cool - delta, 0.0)
		var pl: Player = Zones.player_of(world)
		if pl == null or _cool > 0.0:
			return
		var lp: Vector3 = pl.global_position - global_position
		if lp.y > _h + 0.15 or lp.y + 1.0 < _h - 0.1:
			return
		var r: float = Vector2(lp.x, lp.z).length()
		if r > _len + 0.4 or r < 0.3:
			return
		var pa: float = atan2(-lp.x, -lp.z)
		for i in range(_arms):
			var arm_a: float = ang + TAU * float(i) / float(_arms)
			var d: float = absf(wrapf(pa - arm_a, -PI, PI)) * r
			if d < 0.45:
				_cool = 0.4
				pl.hurt(global_position + Vector3(0.0, _h, 0.0), 1)
				return


# ----------------------------------------------------------------- icicle
## Hanging icicle above the path: shakes when you pass under it, falls, shatters on the floor (hurts on
## contact) and grows back. p = tip position, trigger = horizontal trigger radius, size = length.
class Icicle extends Node3D:
	var world: Node = null
	var _home := Vector3.ZERO
	var _size: float = 1.6
	var _trig: float = 1.8
	var _state: int = 0
	var _t: float = 0.0
	var _vy: float = 0.0
	var _vis: Node3D
	var _mat: Material
	var _floor_y: float = -1000.0

	func setup(o: Dictionary) -> void:
		_home = LevelLoader.vec(o.get("p"))
		position = _home
		_size = float(o.get("size", 1.6))
		_trig = float(o.get("trigger", 1.8))
		_vis = Node3D.new()
		add_child(_vis)
		_mat = Mats.plastic(Color(0.75, 0.9, 1.0), 0.05, Color(0.35, 0.65, 1.0), 0.45, 0.6)
		Geo.put(_vis, Geo.crystal(0.32 * _size / 1.6, _size * 0.7, _size * 0.4, 6), _mat, Vector3(0.0, _size * 1.1, 0.0), Vector3(180.0, 0.0, 0.0))
		Geo.put(_vis, Geo.crystal(0.16 * _size / 1.6, _size * 0.4, _size * 0.25, 5), _mat, Vector3(0.22, _size * 1.05, 0.1), Vector3(180.0, 30.0, 8.0))
		Geo.put(_vis, Geo.rock(0.6, 9, 1, 0.2), Mats.std(Color(0.9, 0.95, 1.0), 0.0, 0.7), Vector3(0.0, _size * 1.15, 0.0), Vector3.ZERO, Vector3(1.0, 0.4, 1.0))

	func _ready() -> void:
		var q := PhysicsRayQueryParameters3D.create(_home + Vector3(0.0, 0.2, 0.0), _home + Vector3(0.0, -40.0, 0.0), 1)
		await get_tree().physics_frame
		var res: Dictionary = get_world_3d().direct_space_state.intersect_ray(q)
		if not res.is_empty():
			var hp: Vector3 = res["position"]
			_floor_y = hp.y

	func _physics_process(delta: float) -> void:
		if world == null:
			return
		_t += delta
		var pl: Player = Zones.player_of(world)
		if _state == 0:
			if pl != null:
				var d: Vector3 = pl.global_position - _home
				if Vector2(d.x, d.z).length() < _trig and d.y < 0.5 and d.y > -12.0:
					_state = 1
					_t = 0.0
					Sfx.play("ice_crack", -4.0, randf_range(0.9, 1.1))
		elif _state == 1:
			_vis.position = Vector3(randf_range(-1.0, 1.0), 0.0, randf_range(-1.0, 1.0)) * 0.05
			if _t > 0.42:
				_state = 2
				_vy = 0.0
				_vis.position = Vector3.ZERO
		elif _state == 2:
			_vy -= 30.0 * delta
			position.y += _vy * delta
			if pl != null:
				var c: Vector3 = pl.global_position + Vector3(0.0, 0.6, 0.0)
				var tip: Vector3 = global_position + Vector3(0.0, _size * 0.4, 0.0)
				if Vector2(c.x - tip.x, c.z - tip.z).length() < 0.7 and absf(c.y - tip.y) < 1.0:
					pl.hurt(tip, 1)
			if position.y <= _floor_y + 0.05 or position.y < _home.y - 40.0:
				_shatter()
		elif _state == 3:
			if _t > 3.5:
				_state = 4
				_t = 0.0
				position = _home
				_vis.scale = Vector3(0.01, 0.01, 0.01)
				_vis.visible = true
		elif _state == 4:
			var k: float = minf(_t / 0.8, 1.0)
			_vis.scale = Vector3.ONE * maxf(k, 0.01)
			if k >= 1.0:
				_state = 0

	func _shatter() -> void:
		_state = 3
		_t = 0.0
		var par: Node = get_parent()
		var p: Vector3 = global_position + Vector3(0.0, 0.4, 0.0)
		Debris.shards(par, p, 0.35, _mat, p + Vector3(0.0, 1.0, 0.0), 4.5, 9, 0.2, 2.5)
		Fx.burst(par, p, Color(0.85, 0.95, 1.0, 0.9), 14, 5.0, 0.3, 0.5, -8.0)
		Sfx.play("shatter", -3.0, randf_range(0.9, 1.1))
		_vis.visible = false


# ------------------------------------------------------------------- wind
## Gusting wind zone: pushes the robot (also in the air). p = floor centre, s = [w, h, d] box, dir = heading
## (deg) the wind blows toward, spd = push speed, on / off = gust timing (off = 0 -> constant), ph.
class Wind extends Area3D:
	var world: Node = null
	var _dir := Vector3.FORWARD
	var _spd: float = 6.0
	var _on: float = 2.0
	var _off: float = 2.0
	var _ph: float = 0.0
	var _ps: CPUParticles3D
	var _fans: Array = []
	var _was: bool = false

	func setup(o: Dictionary) -> void:
		position = LevelLoader.vec(o.get("p"))
		var sz: Vector3 = LevelLoader.vec(o.get("s"), Vector3(6.0, 4.0, 10.0))
		var deg: float = float(o.get("dir", 90.0))
		_dir = Zones.heading_vec(deg)
		_spd = float(o.get("spd", 6.0))
		_on = float(o.get("on", 2.0))
		_off = float(o.get("off", 2.0))
		_ph = float(o.get("ph", 0.0))
		rotation.y = -deg_to_rad(deg)
		collision_layer = 0
		collision_mask = 2
		var cs := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = Vector3(sz.x, sz.y, sz.z)
		cs.shape = bs
		cs.position = Vector3(0.0, sz.y * 0.5, 0.0)
		add_child(cs)
		_ps = CPUParticles3D.new()
		_ps.mesh = Geo.box(Vector3(0.04, 0.04, 1.2))
		var pm := StandardMaterial3D.new()
		pm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		pm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		pm.albedo_color = Color(0.9, 0.95, 1.0, 0.45)
		pm.vertex_color_use_as_albedo = true
		_ps.material_override = pm
		_ps.amount = maxi(12, int(sz.x * sz.y * 0.8 * Game.particle_scale()))
		_ps.lifetime = sz.z / maxf(_spd * 2.2, 1.0)
		_ps.local_coords = true
		_ps.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
		_ps.emission_box_extents = Vector3(sz.x * 0.5, sz.y * 0.45, 0.2)
		_ps.position = Vector3(0.0, sz.y * 0.5, sz.z * 0.5)
		_ps.direction = Vector3(0.0, 0.0, -1.0)
		_ps.spread = 3.0
		_ps.gravity = Vector3.ZERO
		_ps.initial_velocity_min = _spd * 2.0
		_ps.initial_velocity_max = _spd * 2.6
		_ps.particle_flag_align_y = false
		_ps.emitting = false
		add_child(_ps)
		var fan_n: int = clampi(int(sz.x / 3.0), 1, 4)
		for i in range(fan_n):
			var fx: float = (float(i) + 0.5) / float(fan_n) * sz.x - sz.x * 0.5
			var hold := Node3D.new()
			hold.position = Vector3(fx, 1.4, sz.z * 0.5 + 0.6)
			add_child(hold)
			Geo.put(hold, Geo.torus(1.0, 1.25, 28, 6), Mats.metal(Color(0.3, 0.32, 0.38), 0.35, 0.8), Vector3.ZERO, Vector3(90.0, 0.0, 0.0))
			Geo.put(hold, Geo.cyl(0.12, 0.12, 1.5, 6), Mats.metal(Color(0.3, 0.32, 0.38), 0.35, 0.8), Vector3(0.0, -1.0, 0.0))
			var blades := Node3D.new()
			hold.add_child(blades)
			for b in range(3):
				Geo.put(blades, Geo.box(Vector3(0.25, 1.8, 0.05)), Mats.metal(Color(0.7, 0.72, 0.78), 0.3, 0.8), Vector3.ZERO, Vector3(0.0, 0.0, float(b) * 60.0))
			_fans.append(blades)

	func _physics_process(delta: float) -> void:
		if world == null:
			return
		var on: bool = true
		var warn: bool = false
		if _off > 0.01:
			var cyc: float = _on + _off
			var t: float = fposmod(float(world.time) + _ph * cyc, cyc)
			on = t < _on
			warn = (not on) and t > cyc - 0.7
		_ps.emitting = on or warn
		for f in _fans:
			(f as Node3D).rotate_z(delta * (16.0 if on else (5.0 if warn else 1.0)))
		if on != _was:
			_was = on
			if on:
				Sfx.play("wind", -6.0, randf_range(0.9, 1.1))
		if not on:
			return
		var pl: Player = Zones.player_of(world)
		if pl != null and overlaps_body(pl):
			pl.mark_wind(_dir * _spd)


# ----------------------------------------------------------------- geyser
## Timed vent. kind "steam": launches the robot high while erupting (ride it up); kind "flame": hurts.
## p = floor centre, h = column height, pow = launch speed, per = cycle, dur = eruption time, ph.
class Geyser extends Area3D:
	var world: Node = null
	var _kind: String = "steam"
	var _h: float = 8.0
	var _pow: float = 24.0
	var _per: float = 4.0
	var _dur: float = 1.2
	var _ph: float = 0.0
	var _ps: CPUParticles3D
	var _beam: MeshInstance3D
	var _beam_mat: ShaderMaterial
	var _was: bool = false
	var _cool: float = 0.0
	var _col := Color.WHITE

	func setup(o: Dictionary) -> void:
		position = LevelLoader.vec(o.get("p"))
		_kind = str(o.get("kind", "steam"))
		_h = float(o.get("h", 8.0))
		_pow = float(o.get("pow", 24.0))
		_per = maxf(1.0, float(o.get("per", 4.0)))
		_dur = clampf(float(o.get("dur", 1.2)), 0.3, _per - 0.3)
		_ph = float(o.get("ph", 0.0))
		_col = Color(0.8, 0.95, 1.0) if _kind == "steam" else Color(1.0, 0.5, 0.12)
		collision_layer = 0
		collision_mask = 2
		var cs := CollisionShape3D.new()
		var cy := CylinderShape3D.new()
		cy.radius = 1.0
		cy.height = _h
		cs.shape = cy
		cs.position = Vector3(0.0, _h * 0.5, 0.0)
		add_child(cs)
		Geo.put(self, Geo.lathe(PackedVector2Array([Vector2(0.0, 0.0), Vector2(1.3, 0.0), Vector2(1.1, 0.3), Vector2(0.75, 0.38), Vector2(0.7, 0.2), Vector2(0.0, 0.2)]), 20, "vent"), Mats.metal(Color(0.25, 0.25, 0.28), 0.4, 0.8) if _kind == "flame" else Mats.rock())
		Geo.put(self, Geo.cyl(0.68, 0.68, 0.04, 16), Mats.glow(_col, 1.5), Vector3(0.0, 0.22, 0.0), Vector3.ZERO, Vector3.ONE, false)
		_beam = MeshInstance3D.new()
		_beam.mesh = Geo.cyl(0.9, 0.6, _h, 16)
		_beam_mat = Mats.beam(_col, _h, 2.0, false, 1.0)
		_beam.material_override = _beam_mat
		_beam.position = Vector3(0.0, _h * 0.5, 0.0)
		_beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_beam.visible = false
		add_child(_beam)
		_ps = CPUParticles3D.new()
		_ps.mesh = Fx.quad()
		_ps.amount = maxi(12, int(36.0 * Game.particle_scale()))
		_ps.lifetime = 0.9
		_ps.local_coords = false
		_ps.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
		_ps.emission_sphere_radius = 0.5
		_ps.direction = Vector3.UP
		_ps.spread = 8.0
		_ps.initial_velocity_min = _h * 0.9
		_ps.initial_velocity_max = _h * 1.3
		_ps.gravity = Vector3(0.0, -2.0, 0.0)
		_ps.scale_amount_min = 0.5
		_ps.scale_amount_max = 1.1
		_ps.scale_amount_curve = Fx.shrink_curve()
		_ps.color = Color(_col.r, _col.g, _col.b, 0.75)
		_ps.color_ramp = Fx.fade_ramp()
		_ps.position = Vector3(0.0, 0.3, 0.0)
		_ps.emitting = false
		add_child(_ps)

	func _physics_process(delta: float) -> void:
		if world == null:
			return
		_cool = maxf(_cool - delta, 0.0)
		var t: float = fposmod(float(world.time) + _ph * _per, _per)
		var erupt: bool = t < _dur
		var warn: bool = (not erupt) and t > _per - 0.7
		_beam.visible = erupt
		if erupt:
			_beam.scale = Vector3(1.0 + 0.08 * sin(t * 40.0), clampf(t / 0.15, 0.1, 1.0), 1.0 + 0.08 * sin(t * 40.0))
		_ps.emitting = erupt or (warn and randf() < 0.3)
		if erupt != _was:
			_was = erupt
			if erupt:
				Sfx.play("geyser" if _kind == "steam" else "flame", -4.0, randf_range(0.9, 1.1))
		if not erupt:
			return
		var pl: Player = Zones.player_of(world)
		if pl == null or not overlaps_body(pl):
			return
		if _kind == "flame":
			pl.hurt(global_position, 1)
		elif _cool <= 0.0:
			_cool = 0.25
			pl.bounce(_pow)
			Fx.ring(get_parent(), global_position + Vector3(0.0, 0.3, 0.0), _col, 3.0, 0.4, 2.5)


# ---------------------------------------------------------------- meteors
## Meteor shower over an area: a red target ring appears, then a burning rock slams down there.
## p = area centre (floor), r = radius, every = seconds between meteors, aim = 0..1 chance to target the robot.
class Meteors extends Node3D:
	var world: Node = null
	var _r: float = 10.0
	var _every: float = 1.4
	var _aim: float = 0.6
	var _t: float = 0.0
	var _drops: Array = []

	func setup(o: Dictionary) -> void:
		position = LevelLoader.vec(o.get("p"))
		_r = float(o.get("r", 10.0))
		_every = maxf(0.4, float(o.get("every", 1.4)))
		_aim = float(o.get("aim", 0.6))
		_t = float(o.get("ph", 0.0)) * _every

	func _physics_process(delta: float) -> void:
		if world == null:
			return
		var pl: Player = Zones.player_of(world)
		var active: bool = pl != null and Vector2(pl.global_position.x - global_position.x, pl.global_position.z - global_position.z).length() < _r + 14.0
		_t -= delta
		if active and _t <= 0.0:
			_t = _every * randf_range(0.8, 1.2)
			var target: Vector3
			if randf() < _aim:
				target = pl.global_position + Vector3(pl.velocity.x, 0.0, pl.velocity.z) * 0.9
			else:
				var a: float = randf() * TAU
				target = global_position + Vector3(cos(a), 0.0, sin(a)) * randf() * _r
			var off: Vector3 = target - global_position
			off.y = 0.0
			target = global_position + off.limit_length(_r)
			var q := PhysicsRayQueryParameters3D.create(target + Vector3(0.0, 10.0, 0.0), target + Vector3(0.0, -10.0, 0.0), 1)
			var res: Dictionary = get_world_3d().direct_space_state.intersect_ray(q)
			if res.is_empty():
				return
			var hit: Vector3 = res["position"]
			_spawn(hit)
		var keep: Array = []
		for d in _drops:
			var dd: Dictionary = d
			if _tick_drop(dd, delta):
				keep.append(dd)
		_drops = keep

	func _spawn(at: Vector3) -> void:
		var mark := MeshInstance3D.new()
		mark.mesh = Geo.torus(1.6, 1.9, 32, 4)
		mark.material_override = Mats.neon(Hazards.RED, 2.8, 1.0, 0.9)
		mark.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		get_parent().add_child(mark)
		mark.global_position = at + Vector3(0.0, 0.08, 0.0)
		var rock := Node3D.new()
		get_parent().add_child(rock)
		var start: Vector3 = at + Vector3(randf_range(-6.0, 6.0), 26.0, randf_range(-6.0, 6.0))
		rock.global_position = start
		Geo.put(rock, Geo.rock(0.7, randi() % 20, 1, 0.3), Mats.std(Color(0.2, 0.15, 0.14), 0.0, 0.9, Color(1.0, 0.4, 0.1), 0.8))
		Geo.put(rock, Geo.sphere(1.0, 12), Mats.neon(Color(1.0, 0.55, 0.2), 2.2, 1.2, 0.5))
		var trail := CPUParticles3D.new()
		trail.mesh = Fx.quad()
		trail.amount = 20
		trail.lifetime = 0.5
		trail.local_coords = false
		trail.gravity = Vector3.ZERO
		trail.scale_amount_min = 0.6
		trail.scale_amount_max = 1.1
		trail.scale_amount_curve = Fx.shrink_curve()
		trail.color = Color(1.0, 0.55, 0.2, 0.8)
		trail.color_ramp = Fx.fade_ramp()
		rock.add_child(trail)
		_drops.append({"mark": mark, "rock": rock, "from": start, "to": at, "t": 0.0, "dur": 1.15})
		Sfx.play("meteor_fall", -8.0, randf_range(0.9, 1.1))

	func _tick_drop(d: Dictionary, delta: float) -> bool:
		d["t"] = float(d["t"]) + delta
		var k: float = clampf(float(d["t"]) / float(d["dur"]), 0.0, 1.0)
		var mark: MeshInstance3D = d["mark"]
		var rock: Node3D = d["rock"]
		mark.scale = Vector3.ONE * (1.0 + 0.12 * sin(float(d["t"]) * 20.0)) * lerpf(1.3, 0.85, k)
		rock.global_position = (d["from"] as Vector3).lerp(d["to"], k * k)
		rock.rotate_x(delta * 6.0)
		if k < 1.0:
			return true
		var at: Vector3 = d["to"]
		var par: Node = get_parent()
		Sfx.play("explode", -2.0, randf_range(0.8, 1.0))
		Fx.burst(par, at + Vector3(0.0, 0.3, 0.0), Color(1.0, 0.6, 0.25), 20, 9.0, 0.5, 0.6, -8.0)
		Fx.ring(par, at, Color(1.0, 0.5, 0.2), 5.0, 0.4, 3.0)
		Fx.flash(par, at + Vector3(0.0, 1.0, 0.0), Color(1.0, 0.6, 0.3), 8.0, 0.3)
		Debris.box_shatter(par, Transform3D(Basis.IDENTITY, at + Vector3(0.0, 0.5, 0.0)), Vector3(1.0, 0.8, 1.0), Mats.std(Color(0.2, 0.15, 0.14), 0.0, 0.9, Color(1.0, 0.4, 0.1), 0.6), at - Vector3(0.0, 1.0, 0.0), 6.0, 6, 2.0)
		var pl: Player = Zones.player_of(world)
		if pl != null and pl.global_position.distance_to(at) < 2.2:
			pl.hurt(at, 1)
		if pl != null and pl.global_position.distance_to(at) < 12.0:
			world.shake(0.3)
		mark.queue_free()
		rock.queue_free()
		return false


# --------------------------------------------------------------- elec floor
## Electrified floor tiles cycling through a pattern. p = top centre of the area, s = [w, d], cell = tile
## size, per = seconds per step, pattern = "stripes" | "checker" | "wave", ry = yaw.
class ElecFloor extends Node3D:
	var world: Node = null
	var _w: float = 8.0
	var _d: float = 8.0
	var _cell: float = 2.0
	var _per: float = 1.2
	var _pattern: String = "stripes"
	var _nx: int = 4
	var _nz: int = 4
	var _mm: MultiMesh
	var _cool: float = 0.0
	var _hum: bool = false
	var _mats: Array = []

	func setup(o: Dictionary) -> void:
		position = LevelLoader.vec(o.get("p"))
		rotation_degrees.y = float(o.get("ry", 0.0))
		var sz: Array = o.get("s", [8.0, 8.0])
		_w = float(sz[0])
		_d = float(sz[sz.size() - 1])
		_cell = float(o.get("cell", 2.0))
		_per = maxf(0.4, float(o.get("per", 1.2)))
		_pattern = str(o.get("pattern", "stripes"))
		_nx = maxi(1, int(round(_w / _cell)))
		_nz = maxi(1, int(round(_d / _cell)))
		var tile: Vector3 = Vector3(_w / float(_nx) * 0.94, 0.06, _d / float(_nz) * 0.94)
		var base := MultiMesh.new()
		base.transform_format = MultiMesh.TRANSFORM_3D
		base.use_colors = true
		base.mesh = Geo.box(tile)
		base.instance_count = _nx * _nz
		for ix in range(_nx):
			for iz in range(_nz):
				var i: int = ix * _nz + iz
				var lp := Vector3((float(ix) + 0.5) / float(_nx) * _w - _w * 0.5, 0.03, (float(iz) + 0.5) / float(_nz) * _d - _d * 0.5)
				base.set_instance_transform(i, Transform3D(Basis.IDENTITY, lp))
				base.set_instance_color(i, Color(0.2, 0.2, 0.25))
		_mm = base
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = _mm
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.vertex_color_use_as_albedo = true
		mmi.material_override = m
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mmi)

	func _live(ix: int, iz: int, step: int) -> int:
		# returns 2 = live, 1 = about to go live (warning), 0 = safe
		var cur: bool = _on_at(ix, iz, step)
		if cur:
			return 2
		return 1 if _on_at(ix, iz, step + 1) else 0

	func _on_at(ix: int, iz: int, step: int) -> bool:
		if _pattern == "checker":
			return (ix + iz + step) % 2 == 0
		if _pattern == "wave":
			var n: int = maxi(_nz, 1)
			var k: int = step % (n + 1)
			return iz == k or iz == k - 1
		return (iz + step) % 3 == 0

	func _physics_process(delta: float) -> void:
		if world == null:
			return
		_cool = maxf(_cool - delta, 0.0)
		var tt: float = float(world.time) / _per
		var step: int = int(floor(tt))
		var frac: float = tt - float(step)
		for ix in range(_nx):
			for iz in range(_nz):
				var st: int = _live(ix, iz, step)
				var c: Color
				if st == 2:
					var fl: float = 0.75 + 0.25 * sin(float(world.time) * 50.0 + float(ix * 7 + iz * 3))
					c = Color(0.6, 0.9, 3.0) * fl
				elif st == 1 and frac > 0.6:
					c = Color(1.2, 0.8, 0.2) if int(frac * 16.0) % 2 == 0 else Color(0.3, 0.25, 0.2)
				else:
					c = Color(0.16, 0.17, 0.22)
				_mm.set_instance_color(ix * _nz + iz, c)
		var pl: Player = Zones.player_of(world)
		if pl == null or _cool > 0.0 or not pl.is_on_floor():
			return
		var lp: Vector3 = to_local(pl.global_position)
		if absf(lp.y) > 0.6 or absf(lp.x) > _w * 0.5 or absf(lp.z) > _d * 0.5:
			return
		var ix2: int = clampi(int((lp.x + _w * 0.5) / _w * float(_nx)), 0, _nx - 1)
		var iz2: int = clampi(int((lp.z + _d * 0.5) / _d * float(_nz)), 0, _nz - 1)
		if _live(ix2, iz2, step) == 2:
			_cool = 0.5
			Sfx.play("zap", -2.0, 0.8)
			Fx.burst(get_parent(), pl.global_position + Vector3(0.0, 0.5, 0.0), Color(0.5, 0.8, 1.0), 14, 6.0, 0.3, 0.3)
			pl.hurt(pl.global_position - Vector3(0.0, 0.0, 0.5), 1)


# ------------------------------------------------------------------ swing
## Swinging hazard (wrecking ball / ice block / spiked mace) on a chain. pivot = p, len, amp (deg), per,
## ph, dir = swing plane heading, kind = "ball" | "ice" | "mace", r = head radius.
class SwingHazard extends Node3D:
	var world: Node = null
	var _len: float = 6.0
	var _amp: float = 0.9
	var _per: float = 2.6
	var _ph: float = 0.0
	var _axis := Vector3.RIGHT
	var _r: float = 1.0
	var _head: Node3D
	var _chain: MeshInstance3D
	var _cool: float = 0.0

	func setup(o: Dictionary) -> void:
		position = LevelLoader.vec(o.get("p"))
		_len = float(o.get("len", 6.0))
		_amp = deg_to_rad(float(o.get("amp", 55.0)))
		_per = maxf(0.8, float(o.get("per", 2.6)))
		_ph = float(o.get("ph", 0.0))
		_axis = Zones.heading_vec(float(o.get("dir", 90.0)))
		_r = float(o.get("r", 1.0))
		var kind: String = str(o.get("kind", "ball"))
		Geo.put(self, Geo.sphere(0.4, 12), Mats.metal(Color(0.25, 0.25, 0.3), 0.35, 0.8))
		_chain = Geo.put(self, Geo.cyl(0.07, 0.07, 1.0, 8), Mats.metal(Color(0.55, 0.55, 0.6), 0.3, 0.9))
		_head = Node3D.new()
		add_child(_head)
		if kind == "ice":
			var im: Material = Mats.plastic(Color(0.7, 0.88, 1.0), 0.05, Color(0.35, 0.65, 1.0), 0.4, 0.6)
			Geo.put(_head, Geo.rounded_box(Vector3(_r * 1.8, _r * 1.6, _r * 1.8), _r * 0.25, 2), im)
			for i in range(5):
				var a: float = TAU * float(i) / 5.0
				Geo.put(_head, Geo.crystal(_r * 0.2, _r * 0.6, _r * 0.4, 5), im, Vector3(cos(a) * _r * 0.6, -_r * 0.8, sin(a) * _r * 0.6), Vector3(180.0, 0.0, 0.0))
		else:
			Geo.put(_head, Geo.sphere(_r, 20), Mats.metal(Color(0.2, 0.2, 0.24), 0.3, 0.9))
			Geo.put(_head, Geo.torus(_r * 0.95, _r * 1.05, 28, 6), Mats.glow(Hazards.RED, 2.0), Vector3.ZERO, Vector3(90.0, 0.0, 0.0), Vector3.ONE, false)
			if kind == "mace":
				for i in range(8):
					var dv := Vector3(cos(float(i) * 0.785), 0.0, sin(float(i) * 0.785))
					if i % 2 == 1:
						dv.y = 0.6
					Geo.put(_head, Geo.cyl(0.0, _r * 0.25, _r * 0.6, 8), Mats.metal(Color(0.8, 0.8, 0.85), 0.25, 0.9), dv.normalized() * _r * 1.1, Vector3.ZERO).basis = Platforms.basis_y(dv)

	func _physics_process(delta: float) -> void:
		if world == null:
			return
		_cool = maxf(_cool - delta, 0.0)
		var a: float = _amp * sin(TAU * (float(world.time) / _per + _ph))
		var hp: Vector3 = _axis * sin(a) * _len + Vector3(0.0, -cos(a) * _len, 0.0)
		_head.position = hp
		_head.rotation = Vector3.ZERO
		_chain.transform = Transform3D(Platforms.basis_y(-hp) * Basis.from_scale(Vector3(1.0, _len, 1.0)), hp * 0.5)
		var pl: Player = Zones.player_of(world)
		if pl == null or _cool > 0.0:
			return
		var c: Vector3 = pl.global_position + Vector3(0.0, 0.55, 0.0)
		var hw: Vector3 = _head.global_position
		if c.distance_to(hw) < _r + 0.5:
			_cool = 0.6
			pl.hurt(hw, 1)
			var vel: Vector3 = _axis * cos(TAU * (float(world.time) / _per + _ph)) * signf(_amp)
			pl.launch((c - hw).normalized() * 8.0 + vel * 6.0 + Vector3(0.0, 5.0, 0.0))
