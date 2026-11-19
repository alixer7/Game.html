class_name Zones
extends RefCounted
## Trigger-style level objects: pads, air columns, gravity bubbles, conveyors, hints, checkpoints,
## the goal portal and ghost-platform switches. Each inner class has `world` and `setup(o)`.
## Headings are degrees; direction vector = (sin h, 0, -cos h); node yaw = -h.


static func heading_vec(deg: float) -> Vector3:
	var h: float = deg_to_rad(deg)
	return Vector3(sin(h), 0.0, -cos(h))


static func player_of(world: Node) -> Player:
	if world == null:
		return null
	var pl: Player = world.player
	if pl == null or not is_instance_valid(pl) or not pl.alive:
		return null
	return pl


static func hdr(c: Color, k: float) -> Color:
	return Color(c.r * k, c.g * k, c.b * k, 1.0)


# ------------------------------------------------------------ bounce pad
class BouncePad extends Area3D:
	var world: Node = null
	var power: float = 22.0
	var _r: float = 1.2
	var _ring: MeshInstance3D
	var _cool: float = 0.0
	var _squash: float = 0.0
	var _t: float = 0.0
	var _col := Color.WHITE

	func setup(o: Dictionary) -> void:
		position = LevelLoader.vec(o.get("p"))
		power = float(o.get("pow", 22.0))
		_r = float(o.get("r", 1.2))
		_col = Mats.accent(int(o.get("c", 1)))
		collision_layer = 0
		collision_mask = 2
		var cs := CollisionShape3D.new()
		var cy := CylinderShape3D.new()
		cy.radius = _r
		cy.height = 0.7
		cs.shape = cy
		cs.position = Vector3(0.0, 0.35, 0.0)
		add_child(cs)
		var base := MeshInstance3D.new()
		var bm := CylinderMesh.new()
		bm.top_radius = _r
		bm.bottom_radius = _r * 1.12
		bm.height = 0.3
		bm.radial_segments = 32
		base.mesh = bm
		base.material_override = Mats.std(Color(0.1, 0.12, 0.2), 0.7, 0.3)
		base.position = Vector3(0.0, 0.15, 0.0)
		add_child(base)
		var disc := MeshInstance3D.new()
		var dm := CylinderMesh.new()
		dm.top_radius = _r * 0.82
		dm.bottom_radius = _r * 0.82
		dm.height = 0.05
		dm.radial_segments = 32
		disc.mesh = dm
		disc.material_override = Mats.flat(Zones.hdr(_col, 2.2))
		disc.position = Vector3(0.0, 0.31, 0.0)
		disc.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(disc)
		_ring = MeshInstance3D.new()
		var tm := TorusMesh.new()
		tm.inner_radius = _r * 0.92
		tm.outer_radius = _r * 1.04
		tm.rings = 32
		tm.ring_segments = 6
		_ring.mesh = tm
		_ring.material_override = Mats.neon(_col, 2.4, 1.2, 0.8)
		_ring.position = Vector3(0.0, 0.32, 0.0)
		_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(_ring)

	func _physics_process(delta: float) -> void:
		_t += delta
		_cool = maxf(_cool - delta, 0.0)
		_squash = move_toward(_squash, 0.0, delta * 4.0)
		_ring.scale = Vector3.ONE * (1.0 + 0.05 * sin(_t * 3.0) + 0.3 * _squash)
		if _cool > 0.0:
			return
		var pl: Player = Zones.player_of(world)
		if pl == null:
			return
		if overlaps_body(pl) and pl.velocity.y <= 2.0 and pl.global_position.y >= global_position.y - 0.05:
			pl.bounce(power)
			_cool = 0.3
			_squash = 1.0
			Sfx.play("bounce", -2.0)
			Game.vibrate(25)
			Fx.ring(self, global_position, _col, _r * 3.0, 0.45, 2.5)
			Fx.burst(self, global_position + Vector3(0.0, 0.4, 0.0), _col, 12, 5.0, 0.3, 0.6, -2.0, 40.0)


# ------------------------------------------------------------- speed pad
## p = centre on the floor, dir = heading in degrees, len / w = size, spd = boost speed.
class SpeedPad extends Area3D:
	var world: Node = null
	var _dir := Vector3(0.0, 0.0, -1.0)
	var _spd: float = 22.0

	func setup(o: Dictionary) -> void:
		position = LevelLoader.vec(o.get("p"))
		var deg: float = float(o.get("dir", 0.0))
		_dir = Zones.heading_vec(deg)
		_spd = float(o.get("spd", 22.0))
		var length: float = float(o.get("len", 4.0))
		var w: float = float(o.get("w", 2.6))
		rotation.y = -deg_to_rad(deg)
		collision_layer = 0
		collision_mask = 2
		var cs := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = Vector3(w, 0.7, length)
		cs.shape = bs
		cs.position = Vector3(0.0, 0.35, 0.0)
		add_child(cs)
		var plate := MeshInstance3D.new()
		var pb := BoxMesh.new()
		pb.size = Vector3(w, 0.06, length)
		plate.mesh = pb
		plate.material_override = Mats.std(Color(0.08, 0.1, 0.16), 0.5, 0.4)
		plate.position = Vector3(0.0, 0.03, 0.0)
		add_child(plate)
		var arrows := MeshInstance3D.new()
		var pm := PlaneMesh.new()
		pm.size = Vector2(w, length)
		arrows.mesh = pm
		arrows.material_override = Mats.chevron(Mats.accent(int(o.get("c", 3))), 2.6, maxf(length * 0.75, 2.0))
		arrows.position = Vector3(0.0, 0.075, 0.0)
		arrows.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(arrows)

	func _physics_process(_delta: float) -> void:
		var pl: Player = Zones.player_of(world)
		if pl != null and overlaps_body(pl):
			pl.boost(_dir, _spd, 0.9)


# --------------------------------------------------------------- updraft
## p = base centre, r = radius, h = height, spd = max rise speed.
class Updraft extends Area3D:
	var world: Node = null
	var _spd: float = 14.0

	func setup(o: Dictionary) -> void:
		position = LevelLoader.vec(o.get("p"))
		var r: float = float(o.get("r", 2.2))
		var h: float = float(o.get("h", 9.0))
		_spd = float(o.get("spd", 14.0))
		var col: Color = Mats.accent(int(o.get("c", 0)))
		collision_layer = 0
		collision_mask = 2
		var cs := CollisionShape3D.new()
		var cy := CylinderShape3D.new()
		cy.radius = r
		cy.height = h
		cs.shape = cy
		cs.position = Vector3(0.0, h * 0.5, 0.0)
		add_child(cs)
		var bm := CylinderMesh.new()
		bm.top_radius = r * 0.95
		bm.bottom_radius = r * 0.95
		bm.height = h
		bm.cap_top = false
		bm.cap_bottom = false
		bm.radial_segments = 24
		var beam := MeshInstance3D.new()
		beam.mesh = bm
		beam.material_override = Mats.beam(col, h, 1.5, false, 1.0)
		beam.position = Vector3(0.0, h * 0.5, 0.0)
		beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(beam)
		var fan := MeshInstance3D.new()
		var dm := CylinderMesh.new()
		dm.top_radius = r
		dm.bottom_radius = r * 1.1
		dm.height = 0.25
		dm.radial_segments = 28
		fan.mesh = dm
		fan.material_override = Mats.std(Color(0.08, 0.1, 0.18), 0.6, 0.3, col, 0.6)
		fan.position = Vector3(0.0, 0.12, 0.0)
		add_child(fan)
		var ring := MeshInstance3D.new()
		var tm := TorusMesh.new()
		tm.inner_radius = r * 0.88
		tm.outer_radius = r * 1.0
		tm.rings = 28
		tm.ring_segments = 6
		ring.mesh = tm
		ring.material_override = Mats.neon(col, 2.4, 1.2, 0.8)
		ring.position = Vector3(0.0, 0.27, 0.0)
		ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(ring)
		var ps := CPUParticles3D.new()
		ps.mesh = Fx.quad()
		ps.amount = maxi(6, int(20.0 * Game.particle_scale()))
		ps.lifetime = h / maxf(_spd * 0.7, 1.0)
		ps.local_coords = true
		ps.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
		ps.emission_box_extents = Vector3(r * 0.8, 0.1, r * 0.8)
		ps.direction = Vector3.UP
		ps.spread = 6.0
		ps.initial_velocity_min = _spd * 0.55
		ps.initial_velocity_max = _spd * 0.8
		ps.gravity = Vector3.ZERO
		ps.scale_amount_min = 0.15
		ps.scale_amount_max = 0.35
		ps.color = Color(col.r, col.g, col.b, 0.7)
		ps.color_ramp = Fx.fade_ramp()
		ps.position = Vector3(0.0, 0.3, 0.0)
		add_child(ps)

	func _physics_process(_delta: float) -> void:
		var pl: Player = Zones.player_of(world)
		if pl != null and overlaps_body(pl):
			pl.mark_lift(_spd)


# ---------------------------------------------------------------- zero-g
class ZeroG extends Area3D:
	var world: Node = null

	func setup(o: Dictionary) -> void:
		position = LevelLoader.vec(o.get("p"))
		var r: float = float(o.get("r", 6.0))
		var col: Color = Mats.accent(int(o.get("c", 3)))
		collision_layer = 0
		collision_mask = 2
		var cs := CollisionShape3D.new()
		var sp := SphereShape3D.new()
		sp.radius = r
		cs.shape = sp
		add_child(cs)
		var sm := SphereMesh.new()
		sm.radius = r
		sm.height = r * 2.0
		sm.radial_segments = 32
		sm.rings = 16
		var bubble := MeshInstance3D.new()
		bubble.mesh = sm
		bubble.material_override = Mats.neon(col, 1.2, 2.5, 0.03, 0.8)
		bubble.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(bubble)
		var ps := CPUParticles3D.new()
		ps.mesh = Fx.quad()
		ps.amount = maxi(8, int(26.0 * Game.particle_scale()))
		ps.lifetime = 5.0
		ps.preprocess = 4.0
		ps.local_coords = true
		ps.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
		ps.emission_sphere_radius = r * 0.85
		ps.direction = Vector3.UP
		ps.spread = 180.0
		ps.initial_velocity_min = 0.2
		ps.initial_velocity_max = 0.6
		ps.gravity = Vector3.ZERO
		ps.scale_amount_min = 0.12
		ps.scale_amount_max = 0.3
		ps.color = Color(col.r, col.g, col.b, 0.8)
		ps.color_ramp = Fx.fade_ramp()
		add_child(ps)

	func _physics_process(_delta: float) -> void:
		var pl: Player = Zones.player_of(world)
		if pl != null and overlaps_body(pl):
			pl.mark_low_g()


# -------------------------------------------------------------- conveyor
## Solid belt. p = top centre, s = size, dir = heading in degrees, spd = belt speed (m/s).
class Conveyor extends StaticBody3D:
	var world: Node = null
	var _vel := Vector3.ZERO
	var _area: Area3D

	func setup(o: Dictionary) -> void:
		collision_layer = 1
		collision_mask = 0
		var c: int = int(o.get("c", 0))
		var top: Vector3 = LevelLoader.vec(o.get("p"))
		var s: Vector3 = LevelLoader.vec(o.get("s"), Vector3(3.0, 0.6, 8.0))
		var ry: float = float(o.get("ry", 0.0))
		var deg: float = float(o.get("dir", 0.0))
		_vel = Zones.heading_vec(deg) * float(o.get("spd", 4.0))
		Platforms.add_box(self, s, c)
		position = top - Vector3(0.0, s.y * 0.5, 0.0)
		rotation_degrees.y = ry
		var belt := MeshInstance3D.new()
		var pm := PlaneMesh.new()
		pm.size = Vector2(s.x * 0.92, s.z * 0.96)
		belt.mesh = pm
		belt.material_override = Mats.chevron(Mats.accent(c + 1), absf(float(o.get("spd", 4.0))) * 0.35, maxf(s.z * 0.5, 2.0))
		belt.position = Vector3(0.0, s.y * 0.5 + 0.03, 0.0)
		belt.rotation.y = -deg_to_rad(deg) - deg_to_rad(ry)
		belt.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(belt)
		_area = Area3D.new()
		_area.collision_layer = 0
		_area.collision_mask = 2
		var cs := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = Vector3(s.x, 0.5, s.z)
		cs.shape = bs
		cs.position = Vector3(0.0, s.y * 0.5 + 0.25, 0.0)
		_area.add_child(cs)
		add_child(_area)

	func _physics_process(_delta: float) -> void:
		var pl: Player = Zones.player_of(world)
		if pl != null and _area.overlaps_body(pl):
			pl.mark_conveyor(_vel)


# ------------------------------------------------------------------ hint
class Hint extends Area3D:
	var world: Node = null
	var _txt: String = ""
	var _gem: MeshInstance3D
	var _t: float = 0.0

	func setup(o: Dictionary) -> void:
		position = LevelLoader.vec(o.get("p"))
		_txt = str(o.get("txt", ""))
		var r: float = float(o.get("r", 4.0))
		collision_layer = 0
		collision_mask = 2
		var cs := CollisionShape3D.new()
		var cy := CylinderShape3D.new()
		cy.radius = r
		cy.height = 6.0
		cs.shape = cy
		cs.position = Vector3(0.0, 2.5, 0.0)
		add_child(cs)
		_gem = MeshInstance3D.new()
		_gem.mesh = Collectibles.gem_mesh()
		_gem.material_override = Mats.neon(Color(0.5, 0.9, 1.0), 2.4, 1.0, 0.7)
		_gem.scale = Vector3.ONE * 0.9
		_gem.position = Vector3(0.0, 1.9, 0.0)
		_gem.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(_gem)

	func _physics_process(delta: float) -> void:
		_t += delta
		_gem.position.y = 1.9 + sin(_t * 2.0) * 0.15
		_gem.rotation.y += delta * 1.4
		var pl: Player = Zones.player_of(world)
		if pl != null and overlaps_body(pl):
			world.hint(_txt)


# ------------------------------------------------------------ checkpoint
class Checkpoint extends Area3D:
	var world: Node = null
	var _yaw: float = 0.0
	var _on: bool = false
	var _orb_mat: ShaderMaterial
	var _ring: MeshInstance3D
	var _t: float = 0.0

	func setup(o: Dictionary) -> void:
		position = LevelLoader.vec(o.get("p"))
		_yaw = float(o.get("yaw", 0.0))
		collision_layer = 0
		collision_mask = 2
		var cs := CollisionShape3D.new()
		var cy := CylinderShape3D.new()
		cy.radius = 2.4
		cy.height = 4.0
		cs.shape = cy
		cs.position = Vector3(0.0, 2.0, 0.0)
		add_child(cs)
		var post := MeshInstance3D.new()
		var pm := CylinderMesh.new()
		pm.top_radius = 0.09
		pm.bottom_radius = 0.14
		pm.height = 2.2
		post.mesh = pm
		post.material_override = Mats.std(Color(0.14, 0.17, 0.26), 0.7, 0.3)
		post.position = Vector3(0.0, 1.1, 0.0)
		add_child(post)
		var sm := SphereMesh.new()
		sm.radius = 0.32
		sm.height = 0.64
		var orb := MeshInstance3D.new()
		orb.mesh = sm
		_orb_mat = Mats.neon_unique(Color(0.4, 0.5, 0.65), 1.2, 1.0, 0.5)
		orb.material_override = _orb_mat
		orb.position = Vector3(0.0, 2.45, 0.0)
		orb.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(orb)
		_ring = MeshInstance3D.new()
		var tm := TorusMesh.new()
		tm.inner_radius = 0.85
		tm.outer_radius = 0.95
		tm.rings = 28
		tm.ring_segments = 6
		_ring.mesh = tm
		_ring.material_override = _orb_mat
		_ring.position = Vector3(0.0, 0.08, 0.0)
		_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(_ring)

	func _physics_process(delta: float) -> void:
		_t += delta
		_ring.scale = Vector3.ONE * (1.0 + (0.05 * sin(_t * 3.0) if _on else 0.0))
		if _on:
			return
		var pl: Player = Zones.player_of(world)
		if pl != null and overlaps_body(pl):
			_on = true
			_orb_mat.set_shader_parameter("color", Color(0.35, 1.0, 0.6))
			_orb_mat.set_shader_parameter("energy", 3.0)
			world.set_checkpoint(global_position, _yaw)
			Sfx.play("checkpoint")
			Game.vibrate(30)
			Fx.ring(self, global_position, Color(0.35, 1.0, 0.6), 5.0, 0.6, 3.0)
			Fx.burst(self, global_position + Vector3(0.0, 2.2, 0.0), Color(0.5, 1.0, 0.7), 16, 5.0, 0.3, 0.8, -2.0)


# ---------------------------------------------------------------- portal
## p = floor centre of the portal. locked = true until the boss is defeated.
class GoalPortal extends Area3D:
	var world: Node = null
	var locked: bool = false
	var _mat: ShaderMaterial
	var _bb: Node3D
	var _done: bool = false
	var _msg_cd: float = 0.0
	var _t: float = 0.0

	func setup(o: Dictionary) -> void:
		position = LevelLoader.vec(o.get("p"))
		locked = bool(o.get("locked", false))
		world.goal = self
		collision_layer = 0
		collision_mask = 2
		var cs := CollisionShape3D.new()
		var cy := CylinderShape3D.new()
		cy.radius = 1.9
		cy.height = 4.6
		cs.shape = cy
		cs.position = Vector3(0.0, 2.3, 0.0)
		add_child(cs)
		var pad := MeshInstance3D.new()
		var pm := CylinderMesh.new()
		pm.top_radius = 2.4
		pm.bottom_radius = 2.6
		pm.height = 0.3
		pm.radial_segments = 36
		pad.mesh = pm
		pad.material_override = Mats.std(Color(0.1, 0.12, 0.2), 0.7, 0.3)
		pad.position = Vector3(0.0, 0.15, 0.0)
		add_child(pad)
		var pr := MeshInstance3D.new()
		var tm := TorusMesh.new()
		tm.inner_radius = 2.2
		tm.outer_radius = 2.4
		tm.rings = 36
		tm.ring_segments = 6
		pr.mesh = tm
		pr.material_override = Mats.neon(Color(0.4, 0.9, 1.0), 2.4, 1.2, 0.8)
		pr.position = Vector3(0.0, 0.32, 0.0)
		pr.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(pr)
		_bb = Node3D.new()
		_bb.position = Vector3(0.0, 2.7, 0.0)
		add_child(_bb)
		var qm := QuadMesh.new()
		qm.size = Vector2(4.4, 4.4)
		var disc := MeshInstance3D.new()
		disc.mesh = qm
		_mat = ShaderMaterial.new()
		_mat.shader = Mats.shader("res://shaders/portal.gdshader")
		_mat.set_shader_parameter("locked", 1.0 if locked else 0.0)
		disc.material_override = _mat
		disc.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_bb.add_child(disc)
		var fm := TorusMesh.new()
		fm.inner_radius = 2.15
		fm.outer_radius = 2.35
		fm.rings = 40
		fm.ring_segments = 8
		var frame := MeshInstance3D.new()
		frame.mesh = fm
		frame.material_override = Mats.neon(Color(0.7, 0.5, 1.0), 2.2, 1.0, 0.7)
		frame.rotation_degrees.x = 90.0
		frame.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_bb.add_child(frame)
		var bh: float = 34.0
		var bm := CylinderMesh.new()
		bm.top_radius = 1.9
		bm.bottom_radius = 1.9
		bm.height = bh
		bm.cap_top = false
		bm.cap_bottom = false
		bm.radial_segments = 20
		var beam := MeshInstance3D.new()
		beam.mesh = bm
		beam.material_override = Mats.beam(Color(0.6, 0.6, 1.0), bh, 0.9, false, 0.55)
		beam.position = Vector3(0.0, bh * 0.5, 0.0)
		beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(beam)

	func unlock() -> void:
		if not locked:
			return
		locked = false
		_mat.set_shader_parameter("locked", 0.0)
		Sfx.play("powerup")
		Fx.ring(self, global_position, Color(0.6, 0.8, 1.0), 9.0, 0.9, 3.0)
		Fx.burst(self, global_position + Vector3(0.0, 2.6, 0.0), Color(0.7, 0.8, 1.0), 30, 8.0, 0.4, 1.0, -2.0)

	func _physics_process(delta: float) -> void:
		_t += delta
		_msg_cd = maxf(_msg_cd - delta, 0.0)
		var cam: Camera3D = get_viewport().get_camera_3d()
		if cam != null:
			var d: Vector3 = cam.global_position - global_position
			_bb.rotation.y = atan2(d.x, d.z)
		_bb.position.y = 2.7 + sin(_t * 1.6) * 0.1
		if _done:
			return
		var pl: Player = Zones.player_of(world)
		if pl != null and overlaps_body(pl):
			if locked:
				if _msg_cd <= 0.0:
					_msg_cd = 3.0
					world.toast("البوابة مقفلة! اهزم الحارس أولاً", Color(1.0, 0.45, 0.5))
					Sfx.play("zap", -4.0)
			else:
				_done = true
				world.complete()


# ---------------------------------------------------------------- switch
## Floor button that makes switch-mode ghost platforms solid for `dur` seconds (0 = permanent).
class SwitchPad extends Area3D:
	var world: Node = null
	var _id: String = "A"
	var _dur: float = 6.0
	var _cool: float = 0.0
	var _press: float = 0.0
	var _btn: MeshInstance3D
	var _col := Color.WHITE

	func setup(o: Dictionary) -> void:
		position = LevelLoader.vec(o.get("p"))
		_id = str(o.get("id", "A"))
		_dur = float(o.get("dur", 6.0))
		_col = Mats.accent(int(o.get("c", 2)))
		collision_layer = 0
		collision_mask = 2
		var cs := CollisionShape3D.new()
		var cy := CylinderShape3D.new()
		cy.radius = 1.2
		cy.height = 0.8
		cs.shape = cy
		cs.position = Vector3(0.0, 0.4, 0.0)
		add_child(cs)
		var base := MeshInstance3D.new()
		var bm := CylinderMesh.new()
		bm.top_radius = 1.15
		bm.bottom_radius = 1.25
		bm.height = 0.25
		bm.radial_segments = 28
		base.mesh = bm
		base.material_override = Mats.std(Color(0.1, 0.12, 0.2), 0.7, 0.3)
		base.position = Vector3(0.0, 0.12, 0.0)
		add_child(base)
		_btn = MeshInstance3D.new()
		var tm := CylinderMesh.new()
		tm.top_radius = 0.8
		tm.bottom_radius = 0.85
		tm.height = 0.18
		tm.radial_segments = 28
		_btn.mesh = tm
		_btn.material_override = Mats.flat(Zones.hdr(_col, 2.0))
		_btn.position = Vector3(0.0, 0.3, 0.0)
		_btn.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(_btn)
		var ring := MeshInstance3D.new()
		var rm := TorusMesh.new()
		rm.inner_radius = 1.0
		rm.outer_radius = 1.12
		rm.rings = 28
		rm.ring_segments = 6
		ring.mesh = rm
		ring.material_override = Mats.neon(_col, 2.4, 1.2, 0.8)
		ring.position = Vector3(0.0, 0.27, 0.0)
		ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(ring)

	func _physics_process(delta: float) -> void:
		_cool = maxf(_cool - delta, 0.0)
		_press = move_toward(_press, 0.0, delta * 2.0)
		_btn.position.y = 0.3 - 0.1 * _press
		var pl: Player = Zones.player_of(world)
		if pl != null and _cool <= 0.0 and overlaps_body(pl):
			_cool = maxf(_dur, 1.0) + 0.5 if _dur > 0.0 else 2.0
			_press = 1.0
			world.activate_switch(_id, _dur)
			Sfx.play("switch")
			Game.vibrate(30)
			Fx.ring(self, global_position, _col, 6.0, 0.6, 3.0)
			Fx.burst(self, global_position + Vector3(0.0, 0.4, 0.0), _col, 14, 5.0, 0.3, 0.7, -2.0)
			world.toast("تم تفعيل الجسر", _col)
