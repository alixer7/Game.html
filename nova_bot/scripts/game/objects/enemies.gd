class_name Enemies
extends RefCounted
## Patrolling drones, stationary turrets and the energy bolts they (and the boss) fire.
## Drones and turrets sit in group "hittable": spin / dash destroy them, landing on top does too.

const COL := Color(1.0, 0.3, 0.38)


## Spawn an energy bolt. `parent` should be the level root so the bolt outlives its shooter.
static func fire(parent: Node, world: Node, from: Vector3, vel: Vector3, col: Color = Color(1.0, 0.35, 0.42), life: float = 4.5, size: float = 0.3) -> void:
	if parent == null or not parent.is_inside_tree():
		return
	var p := Projectile.new()
	p.world = world
	p.vel = vel
	p.life = life
	p.col = col
	p.size = size
	parent.add_child(p)
	p.global_position = from


# ------------------------------------------------------------ projectile
class Projectile extends Node3D:
	var world: Node = null
	var vel := Vector3.ZERO
	var life: float = 4.5
	var col := Color(1.0, 0.35, 0.42)
	var size: float = 0.3
	var _dead: bool = false

	func _ready() -> void:
		var core := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = size * 0.7
		sm.height = size * 1.4
		sm.radial_segments = 12
		sm.rings = 6
		core.mesh = sm
		core.material_override = Mats.flat(Zones.hdr(Color(1.0, 0.85, 0.85), 2.4))
		core.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(core)
		var glow := MeshInstance3D.new()
		var gm := SphereMesh.new()
		gm.radius = size * 1.5
		gm.height = size * 3.0
		gm.radial_segments = 14
		gm.rings = 7
		glow.mesh = gm
		glow.material_override = Mats.neon(col, 2.6, 1.4, 0.55)
		glow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(glow)

	func _physics_process(delta: float) -> void:
		if _dead:
			return
		life -= delta
		if life <= 0.0:
			_pop(false)
			return
		var from: Vector3 = global_position
		var to: Vector3 = from + vel * delta
		var space: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
		var q := PhysicsRayQueryParameters3D.create(from, to, 1)
		var res: Dictionary = space.intersect_ray(q)
		if not res.is_empty():
			var hp: Vector3 = res["position"]
			global_position = hp
			_pop(false)
			return
		global_position = to
		var pl: Player = Zones.player_of(world)
		if pl == null:
			return
		var c: Vector3 = pl.global_position + Vector3(0.0, 0.6, 0.0)
		var d: float = c.distance_to(global_position)
		if pl.is_spinning() and d < 2.3:
			_pop(true)
			return
		if d < size * 1.5 + 0.5:
			pl.hurt(global_position, 1)
			_pop(false)

	func _pop(deflected: bool) -> void:
		if _dead:
			return
		_dead = true
		var par: Node = get_parent()
		var p: Vector3 = global_position
		Fx.burst(par, p, col, 8, 4.0, 0.25, 0.4, -2.0)
		if deflected:
			Sfx.play("coin", -4.0, 1.4)
			world.add_coins(1, p)
		else:
			Sfx.play("zap", -12.0, 1.3)
		queue_free()


# ----------------------------------------------------------------- drone
## Hovering patrol bot. p = start (centre), off = patrol offset, per = seconds per round trip.
class Drone extends Area3D:
	var world: Node = null
	var hit_radius: float = 0.8
	var _start := Vector3.ZERO
	var _off := Vector3.ZERO
	var _per: float = 4.0
	var _ph: float = 0.0
	var _gfx: Node3D
	var _ring: Node3D
	var _dead: bool = false
	var _yaw: float = 0.0
	var _seed: float = 0.0

	func setup(o: Dictionary) -> void:
		_start = LevelLoader.vec(o.get("p"))
		position = _start
		_off = LevelLoader.vec(o.get("off"))
		_per = maxf(0.5, float(o.get("per", 4.0)))
		_ph = float(o.get("ph", 0.0))
		_seed = _start.x * 0.37 + _start.z * 0.21
		collision_layer = 0
		collision_mask = 2
		var cs := CollisionShape3D.new()
		var sp := SphereShape3D.new()
		sp.radius = 0.72
		cs.shape = sp
		add_child(cs)
		_gfx = Node3D.new()
		add_child(_gfx)
		var body := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 0.55
		sm.height = 1.1
		sm.radial_segments = 20
		sm.rings = 10
		body.mesh = sm
		body.material_override = Mats.std(Color(0.16, 0.12, 0.2), 0.85, 0.3, Enemies.COL, 0.25)
		_gfx.add_child(body)
		var eye := MeshInstance3D.new()
		var em := SphereMesh.new()
		em.radius = 0.24
		em.height = 0.48
		eye.mesh = em
		eye.material_override = Mats.flat(Zones.hdr(Enemies.COL, 2.6))
		eye.position = Vector3(0.0, 0.05, -0.42)
		eye.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_gfx.add_child(eye)
		_ring = Node3D.new()
		_gfx.add_child(_ring)
		var tm := TorusMesh.new()
		tm.inner_radius = 0.74
		tm.outer_radius = 0.82
		tm.rings = 28
		tm.ring_segments = 6
		var ring := MeshInstance3D.new()
		ring.mesh = tm
		ring.material_override = Mats.neon(Enemies.COL, 2.2, 1.2, 0.7)
		ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_ring.add_child(ring)
		var cone := CylinderMesh.new()
		cone.top_radius = 0.2
		cone.bottom_radius = 0.0
		cone.height = 0.5
		cone.radial_segments = 10
		cone.rings = 1
		var thr := MeshInstance3D.new()
		thr.mesh = cone
		thr.material_override = Mats.neon(Color(1.0, 0.55, 0.3), 2.2, 1.0, 0.6)
		thr.position = Vector3(0.0, -0.78, 0.0)
		thr.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_gfx.add_child(thr)
		add_to_group("hittable")

	func _physics_process(delta: float) -> void:
		if _dead or world == null:
			return
		var t: float = float(world.time)
		var k: float = 0.5 - 0.5 * cos(TAU * (t / _per + _ph))
		var p: Vector3 = _start + _off * k
		p.y += sin(t * 2.6 + _seed) * 0.16
		var mv: Vector3 = p - position
		position = p
		_ring.rotate_y(delta * 5.0)
		var pl: Player = Zones.player_of(world)
		var want: float = _yaw
		if pl != null:
			var d: Vector3 = pl.global_position - global_position
			if Vector2(d.x, d.z).length() < 12.0:
				want = atan2(-d.x, -d.z)
			elif Vector2(mv.x, mv.z).length() > 0.001:
				want = atan2(-mv.x, -mv.z)
		_yaw = lerp_angle(_yaw, want, 1.0 - exp(-6.0 * delta))
		_gfx.rotation.y = _yaw
		if pl == null or not overlaps_body(pl):
			return
		if pl.is_spinning() or pl.is_dashing():
			_pop()
		elif pl.global_position.y > global_position.y + 0.2 and pl.velocity.y < 2.0:
			pl.stomp_bounce()
			_pop()
		else:
			pl.hurt(global_position, 1)

	func hit(_by: Node, _kind: String) -> bool:
		if _dead:
			return false
		_pop()
		return true

	func _pop() -> void:
		if _dead:
			return
		_dead = true
		remove_from_group("hittable")
		var par: Node = get_parent()
		var p: Vector3 = global_position
		Sfx.play("enemy_pop")
		Game.vibrate(30)
		Fx.burst(par, p, Enemies.COL, 18, 7.0, 0.35, 0.7, -8.0)
		Fx.burst(par, p, Color(1.0, 0.85, 0.4), 8, 5.0, 0.3, 0.5, -4.0)
		Fx.ring(par, p, Enemies.COL, 3.5, 0.45, 3.0)
		world.add_coins(2, p)
		queue_free()


# ---------------------------------------------------------------- turret
## Fixed gun that tracks the player and fires a slow bolt every `every` seconds when within `range`.
## p = floor position. Spin / dash / land on its head to destroy it.
class Turret extends StaticBody3D:
	var world: Node = null
	var hit_radius: float = 0.9
	var _range: float = 16.0
	var _every: float = 2.4
	var _t: float = 1.0
	var _charge: float = -1.0
	var _head: Node3D
	var _eye_mat: StandardMaterial3D
	var _area: Area3D
	var _dead: bool = false
	var _yaw: float = 0.0

	func setup(o: Dictionary) -> void:
		position = LevelLoader.vec(o.get("p"))
		_range = float(o.get("range", 16.0))
		_every = maxf(0.8, float(o.get("every", 2.4)))
		_t = 0.8 + float(o.get("ph", 0.0)) * _every
		collision_layer = 1
		collision_mask = 0
		var cs := CollisionShape3D.new()
		var cy := CylinderShape3D.new()
		cy.radius = 0.7
		cy.height = 1.7
		cs.shape = cy
		cs.position = Vector3(0.0, 0.85, 0.0)
		add_child(cs)
		var base := MeshInstance3D.new()
		var bm := CylinderMesh.new()
		bm.top_radius = 0.55
		bm.bottom_radius = 0.78
		bm.height = 0.75
		bm.radial_segments = 20
		base.mesh = bm
		base.material_override = Mats.std(Color(0.14, 0.12, 0.2), 0.8, 0.35)
		base.position = Vector3(0.0, 0.375, 0.0)
		add_child(base)
		_head = Node3D.new()
		_head.position = Vector3(0.0, 1.15, 0.0)
		add_child(_head)
		var sm := SphereMesh.new()
		sm.radius = 0.52
		sm.height = 1.04
		sm.radial_segments = 20
		sm.rings = 10
		var dome := MeshInstance3D.new()
		dome.mesh = sm
		dome.material_override = Mats.std(Color(0.2, 0.14, 0.24), 0.85, 0.3, Enemies.COL, 0.2)
		_head.add_child(dome)
		var bar := CylinderMesh.new()
		bar.top_radius = 0.13
		bar.bottom_radius = 0.17
		bar.height = 0.85
		bar.radial_segments = 12
		var barrel := MeshInstance3D.new()
		barrel.mesh = bar
		barrel.material_override = Mats.std(Color(0.1, 0.1, 0.14), 0.9, 0.3)
		barrel.rotation_degrees.x = 90.0
		barrel.position = Vector3(0.0, 0.0, -0.62)
		_head.add_child(barrel)
		_eye_mat = StandardMaterial3D.new()
		_eye_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_eye_mat.albedo_color = Zones.hdr(Enemies.COL, 1.0)
		var em := SphereMesh.new()
		em.radius = 0.17
		em.height = 0.34
		var eye := MeshInstance3D.new()
		eye.mesh = em
		eye.material_override = _eye_mat
		eye.position = Vector3(0.0, 0.2, -0.38)
		eye.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_head.add_child(eye)
		_area = Area3D.new()
		_area.collision_layer = 0
		_area.collision_mask = 2
		var acs := CollisionShape3D.new()
		var abs_ := BoxShape3D.new()
		abs_.size = Vector3(1.3, 0.6, 1.3)
		acs.shape = abs_
		acs.position = Vector3(0.0, 1.95, 0.0)
		_area.add_child(acs)
		add_child(_area)
		add_to_group("hittable")

	func _physics_process(delta: float) -> void:
		if _dead or world == null:
			return
		var pl: Player = Zones.player_of(world)
		var in_range: bool = false
		var aim := Vector3.ZERO
		if pl != null:
			aim = pl.global_position + Vector3(0.0, 0.6, 0.0) - (global_position + Vector3(0.0, 1.15, 0.0))
			in_range = aim.length() < _range
			if pl.velocity.y < -2.0 and _area.overlaps_body(pl):
				pl.stomp_bounce()
				_pop()
				return
		if in_range:
			var want: float = atan2(-aim.x, -aim.z)
			_yaw = lerp_angle(_yaw, want, 1.0 - exp(-7.0 * delta))
			_head.rotation.y = _yaw
			_t -= delta
			if _charge < 0.0 and _t <= 0.0:
				_charge = 0.5
				Sfx.play("zap", -8.0, 1.5)
			if _charge >= 0.0:
				_charge -= delta
				var f: float = 1.0 - clampf(_charge / 0.5, 0.0, 1.0)
				_eye_mat.albedo_color = Zones.hdr(Enemies.COL, 1.0 + f * 3.0)
				if _charge < 0.0:
					_fire(aim)
					_t = _every
					_eye_mat.albedo_color = Zones.hdr(Enemies.COL, 1.0)
		else:
			_charge = -1.0
			_eye_mat.albedo_color = Zones.hdr(Enemies.COL, 1.0)

	func _fire(aim: Vector3) -> void:
		var dir: Vector3 = aim.normalized()
		var from: Vector3 = global_position + Vector3(0.0, 1.15, 0.0) + dir * 0.9
		Sfx.play("shoot", -4.0)
		Enemies.fire(get_parent(), world, from, dir * 10.0)

	func hit(_by: Node, _kind: String) -> bool:
		if _dead:
			return false
		_pop()
		return true

	func _pop() -> void:
		if _dead:
			return
		_dead = true
		remove_from_group("hittable")
		var par: Node = get_parent()
		var p: Vector3 = global_position + Vector3(0.0, 1.1, 0.0)
		Sfx.play("enemy_pop")
		Game.vibrate(40)
		Fx.burst(par, p, Enemies.COL, 22, 8.0, 0.4, 0.8, -8.0)
		Fx.burst(par, p, Color(1.0, 0.85, 0.4), 10, 6.0, 0.3, 0.6, -4.0)
		Fx.ring(par, global_position, Enemies.COL, 4.0, 0.5, 3.0)
		world.add_coins(3, p)
		queue_free()
