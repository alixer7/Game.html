class_name Enemies
extends RefCounted
## Enemies and their projectiles. Every enemy sits in group "hittable" and dies physically: it is knocked
## flying as a tumbling, smoking carcass (Debris.wreck) that bursts into its own parts and drops gems +
## an energy cell. Punching a projectile sends it back at the shooter.
##   drone   - patrols, chases inside a leash          turret  - tracks and fires bolts (optionally leads)
##   hopper  - telegraphs then leaps at you            shield  - blocks hits from the front; spin, stomp or flank it
##   spider  - crystal crawler with stepping legs      snowbot - lobs arcing snowballs at where you will be

const COL := Color(1.0, 0.28, 0.36)
const GLOW := Color(1.0, 0.22, 0.3)


static func body_mat() -> Material:
	return Mats.metal(Color(0.2, 0.17, 0.24), 0.32, 0.75)


static func shell_mat() -> Material:
	return Mats.plastic(Color(0.32, 0.27, 0.38), 0.35)


static func knock_power(kind: String) -> float:
	match kind:
		"punch3":
			return 14.0
		"spin_big", "dash":
			return 13.0
		"spin":
			return 10.0
		"stomp":
			return 4.0
		"laser":
			return 5.0
		"reflect":
			return 8.0
	return 9.0


## Shared death: wreck the visuals, drop rewards, free the enemy node.
static func kill(enemy: Node3D, world: Node, gfx: Node3D, by: Node, kind: String, gems: int, radius: float = 0.6) -> void:
	var par: Node = enemy.get_parent()
	var from: Vector3 = enemy.global_position - Vector3(0.0, 0.0, 1.0)
	if by is Node3D:
		from = (by as Node3D).global_position
	if kind == "stomp":
		from = enemy.global_position + Vector3(randf_range(-0.2, 0.2), 2.0, randf_range(-0.2, 0.2))
	Sfx.play("enemy_pop", 0.0, randf_range(0.9, 1.1))
	Game.vibrate(30)
	Fx.burst(par, enemy.global_position, COL, 10, 6.0, 0.3, 0.4, -6.0)
	var drop := Callable(Enemies, "_drop").bind(par, world, gems)
	var up: float = 1.1 if kind == "punch3" else 0.55
	if kind == "stomp":
		up = 0.2
	Debris.wreck(par, gfx, from, knock_power(kind), radius, drop, up, 0.55 if kind != "stomp" else 0.25)
	enemy.queue_free()


static func _drop(pos: Vector3, par: Node, world: Node, gems: int) -> void:
	Debris.spray(par, world, pos, gems, "gem", 1.0, 5.0)
	Debris.spray(par, world, pos, 1, "energy", 4.0, 4.0)


## Spawn a projectile. `parent` should be the level root so it outlives its shooter.
static func fire(parent: Node, world: Node, from: Vector3, vel: Vector3, col: Color = Color(1.0, 0.35, 0.42), life: float = 4.5, size: float = 0.3, grav: float = 0.0, kind: String = "bolt", shooter: Node3D = null) -> void:
	if parent == null or not parent.is_inside_tree():
		return
	var p := Projectile.new()
	p.world = world
	p.vel = vel
	p.life = life
	p.col = col
	p.size = size
	p.grav = grav
	p.kind = kind
	p.shooter = shooter
	parent.add_child(p)
	p.global_position = from


## Lead-free ballistic launch velocity reaching `to` from `from` in `t` seconds under gravity g (down).
static func lob(from: Vector3, to: Vector3, t: float, g: float) -> Vector3:
	var d: Vector3 = to - from
	return Vector3(d.x / t, d.y / t + 0.5 * g * t, d.z / t)


static func eye(parent: Node3D, r: float, pos: Vector3) -> MeshInstance3D:
	var mi := Geo.put(parent, Geo.sphere(r, 16), Mats.glow(GLOW, 2.6), pos, Vector3.ZERO, Vector3(1.0, 1.0, 0.6), false)
	return mi


# ------------------------------------------------------------ projectile
class Projectile extends Node3D:
	var world: Node = null
	var vel := Vector3.ZERO
	var life: float = 4.5
	var col := Color(1.0, 0.35, 0.42)
	var size: float = 0.3
	var grav: float = 0.0
	var kind: String = "bolt"
	var shooter: Node3D = null
	var _dead: bool = false
	var _reflected: bool = false
	var _vis: Node3D

	func _ready() -> void:
		_vis = Node3D.new()
		add_child(_vis)
		if kind == "snow":
			Geo.put(_vis, Geo.rock(size, 3, 1, 0.12), Mats.std(Color(0.92, 0.96, 1.0), 0.0, 0.8))
		else:
			Geo.put(_vis, Geo.sphere(size * 0.7, 12), Mats.glow(Color(1.0, 0.9, 0.9), 2.4), Vector3.ZERO, Vector3.ZERO, Vector3.ONE, false)
			Geo.put(_vis, Geo.sphere(size * 1.5, 14), Mats.neon(col, 2.6, 1.4, 0.55), Vector3.ZERO, Vector3.ZERO, Vector3.ONE, false)

	func _physics_process(delta: float) -> void:
		if _dead:
			return
		life -= delta
		if life <= 0.0:
			_pop(false)
			return
		vel.y -= grav * delta
		var from: Vector3 = global_position
		var to: Vector3 = from + vel * delta
		var q := PhysicsRayQueryParameters3D.create(from, to, 1)
		var res: Dictionary = get_world_3d().direct_space_state.intersect_ray(q)
		if not res.is_empty():
			global_position = res["position"]
			_pop(false)
			return
		global_position = to
		_vis.rotate_x(delta * 6.0)
		if _reflected:
			for n in get_tree().get_nodes_in_group("hittable"):
				var e: Node3D = n as Node3D
				if e == null or not is_instance_valid(e) or e is Collectibles.Crate:
					continue
				if e.global_position.distance_to(global_position) < 1.3:
					e.call("hit", self, "reflect")
					_pop(false)
					return
			return
		var pl: Player = Zones.player_of(world)
		if pl == null:
			return
		var c: Vector3 = pl.global_position + Vector3(0.0, 0.6, 0.0)
		var d: float = c.distance_to(global_position)
		var dr: float = pl.deflect_radius()
		if dr > 0.0 and d < dr:
			_deflect(pl)
			return
		if d < size * 1.4 + 0.45:
			pl.hurt(global_position, 1)
			_pop(false)

	func _deflect(pl: Player) -> void:
		var back: Vector3
		if shooter != null and is_instance_valid(shooter):
			back = (shooter.global_position + Vector3(0.0, 1.0, 0.0) - global_position).normalized() * maxf(vel.length() * 1.6, 14.0)
		else:
			back = (global_position - pl.global_position).normalized() * 14.0
		vel = back
		grav = 0.0
		life = 3.0
		_reflected = true
		col = Color(0.4, 0.95, 1.0)
		Sfx.play("deflect", -2.0, randf_range(0.95, 1.1))
		Fx.burst(get_parent(), global_position, Color(0.6, 0.95, 1.0), 10, 5.0, 0.3, 0.3)
		Fx.ring(get_parent(), global_position, Color(0.6, 0.95, 1.0), 2.0, 0.25, 3.0)
		if world != null:
			world.hitstop(0.05)

	func _pop(_quiet: bool) -> void:
		if _dead:
			return
		_dead = true
		var par: Node = get_parent()
		var p: Vector3 = global_position
		if kind == "snow":
			Debris.shards(par, p, 0.25, Mats.std(Color(0.92, 0.96, 1.0), 0.0, 0.8), p - vel.normalized(), 3.0, 5, 0.12, 1.5)
			Fx.burst(par, p, Color(0.95, 0.98, 1.0, 0.9), 10, 4.0, 0.35, 0.5, -6.0)
			Sfx.play("snow_hit", -6.0, randf_range(0.9, 1.1))
		else:
			Fx.burst(par, p, col, 8, 4.0, 0.25, 0.4, -2.0)
			Sfx.play("zap", -12.0, 1.3)
		queue_free()


# ----------------------------------------------------------------- drone
## Hovering patrol bot. p = start, off = patrol offset, per = seconds per round trip. Chases inside a leash.
class Drone extends Area3D:
	var world: Node = null
	var hit_radius: float = 0.8
	var _start := Vector3.ZERO
	var _off := Vector3.ZERO
	var _per: float = 4.0
	var _ph: float = 0.0
	var _gfx: Node3D
	var _rotors: Array = []
	var _dead: bool = false
	var _yaw: float = 0.0
	var _seed: float = 0.0
	var _chase := Vector3.ZERO
	var _leash: float = 5.0

	func setup(o: Dictionary) -> void:
		_start = LevelLoader.vec(o.get("p"))
		position = _start
		_off = LevelLoader.vec(o.get("off"))
		_per = maxf(0.5, float(o.get("per", 4.0)))
		_ph = float(o.get("ph", 0.0))
		_leash = float(o.get("leash", 5.0))
		_seed = _start.x * 0.37 + _start.z * 0.21
		collision_layer = 0
		collision_mask = 2
		var cs := CollisionShape3D.new()
		var sp := SphereShape3D.new()
		sp.radius = 0.75
		cs.shape = sp
		add_child(cs)
		_gfx = Node3D.new()
		add_child(_gfx)
		Geo.put(_gfx, Geo.sphere(0.5, 22), Enemies.shell_mat(), Vector3.ZERO, Vector3.ZERO, Vector3(1.0, 0.82, 1.0))
		Geo.put(_gfx, Geo.rounded_box(Vector3(0.66, 0.2, 0.3), 0.09, 2), Mats.metal(Color(0.04, 0.04, 0.06), 0.1, 0.3), Vector3(0.0, 0.05, -0.33))
		Geo.put(_gfx, Geo.rounded_box(Vector3(0.44, 0.07, 0.06), 0.03, 2), Mats.glow(Enemies.GLOW, 3.0), Vector3(0.0, 0.05, -0.48), Vector3.ZERO, Vector3.ONE, false)
		Geo.put(_gfx, Geo.torus(0.48, 0.56, 32, 6), Enemies.body_mat(), Vector3(0.0, -0.05, 0.0))
		for sx in [-1.0, 1.0]:
			var s: float = sx
			var pod := Node3D.new()
			pod.position = Vector3(0.62 * s, 0.12, 0.0)
			_gfx.add_child(pod)
			Geo.put(pod, Geo.cyl(0.12, 0.14, 0.22, 14), Enemies.body_mat())
			var rotor := Node3D.new()
			rotor.position = Vector3(0.0, 0.16, 0.0)
			pod.add_child(rotor)
			Geo.put(rotor, Geo.box(Vector3(0.75, 0.02, 0.09)), Mats.metal(Color(0.6, 0.62, 0.7), 0.3, 0.8))
			Geo.put(rotor, Geo.cyl(0.38, 0.38, 0.01, 24), Mats.neon(Enemies.COL, 0.6, 1.0, 0.12, 0.6), Vector3.ZERO, Vector3.ZERO, Vector3.ONE, false)
			_rotors.append(rotor)
		Geo.put(_gfx, Geo.cyl(0.06, 0.14, 0.3, 12), Enemies.body_mat(), Vector3(0.0, -0.5, 0.0))
		Geo.put(_gfx, Geo.sphere(0.08, 10), Mats.glow(Color(1.0, 0.55, 0.3), 3.0), Vector3(0.0, -0.66, 0.0), Vector3.ZERO, Vector3.ONE, false)
		add_to_group("hittable")

	func _physics_process(delta: float) -> void:
		if _dead or world == null:
			return
		var t: float = float(world.time)
		var k: float = 0.5 - 0.5 * cos(TAU * (t / _per + _ph))
		var home: Vector3 = _start + _off * k
		var pl: Player = Zones.player_of(world)
		var want_chase := Vector3.ZERO
		if pl != null:
			var to: Vector3 = pl.global_position + Vector3(0.0, 0.8, 0.0) - home
			if to.length() < _leash + 3.0 and absf(to.y) < 4.0:
				want_chase = to.limit_length(_leash)
		_chase = _chase.move_toward(want_chase, delta * 3.2)
		var p: Vector3 = home + _chase
		p.y += sin(t * 2.6 + _seed) * 0.16
		var mv: Vector3 = p - position
		position = p
		for r in _rotors:
			(r as Node3D).rotate_y(delta * 30.0)
		var want: float = _yaw
		if pl != null and pl.global_position.distance_to(global_position) < 12.0:
			var d: Vector3 = pl.global_position - global_position
			want = atan2(-d.x, -d.z)
		elif Vector2(mv.x, mv.z).length() > 0.001:
			want = atan2(-mv.x, -mv.z)
		_yaw = lerp_angle(_yaw, want, 1.0 - exp(-6.0 * delta))
		_gfx.rotation = Vector3(clampf(-mv.length() * 2.0, -0.3, 0.3), _yaw, 0.0)
		if pl == null or not overlaps_body(pl):
			return
		if pl.is_attacking() or pl.is_dashing():
			return
		if pl.global_position.y > global_position.y + 0.15 and pl.velocity.y < 2.0:
			pl.stomp_bounce()
			_die(pl, "stomp")
		else:
			pl.hurt(global_position, 1)

	func hit(by: Node, kind: String) -> bool:
		if _dead:
			return false
		_die(by, kind)
		return true

	func _die(by: Node, kind: String) -> void:
		_dead = true
		remove_from_group("hittable")
		Enemies.kill(self, world, _gfx, by, kind, 2, 0.55)


# ---------------------------------------------------------------- turret
## Fixed gun that tracks the player and fires bolts (burst, optional lead). p = floor position.
class Turret extends StaticBody3D:
	var world: Node = null
	var hit_radius: float = 0.9
	var hit_offset := Vector3(0.0, 1.1, 0.0)
	var _range: float = 16.0
	var _every: float = 2.4
	var _lead: float = 0.0
	var _burst: int = 1
	var _burst_left: int = 0
	var _burst_t: float = 0.0
	var _t: float = 1.0
	var _charge: float = -1.0
	var _gfx: Node3D
	var _head: Node3D
	var _barrel: Node3D
	var _eye_mat: StandardMaterial3D
	var _area: Area3D
	var _dead: bool = false
	var _yaw: float = 0.0
	var _pitch: float = 0.0

	func setup(o: Dictionary) -> void:
		position = LevelLoader.vec(o.get("p"))
		_range = float(o.get("range", 16.0))
		_every = maxf(0.8, float(o.get("every", 2.4)))
		_lead = float(o.get("lead", 0.0))
		_burst = maxi(1, int(o.get("burst", 1)))
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
		_gfx = Node3D.new()
		add_child(_gfx)
		Geo.put(_gfx, Geo.lathe(PackedVector2Array([Vector2(0.0, 0.0), Vector2(0.82, 0.0), Vector2(0.84, 0.12), Vector2(0.7, 0.2), Vector2(0.56, 0.5), Vector2(0.5, 0.75), Vector2(0.0, 0.75)]), 24, "turret_base"), Enemies.body_mat())
		for i in range(6):
			var a: float = TAU * float(i) / 6.0
			Geo.put(_gfx, Geo.sphere(0.05, 8), Mats.metal(Color(0.6, 0.6, 0.66), 0.3, 0.9), Vector3(cos(a) * 0.74, 0.14, sin(a) * 0.74))
		Geo.put(_gfx, Geo.torus(0.5, 0.58, 28, 5), Mats.glow(Enemies.GLOW, 1.6), Vector3(0.0, 0.62, 0.0), Vector3.ZERO, Vector3.ONE, false)
		_head = Node3D.new()
		_head.position = Vector3(0.0, 1.15, 0.0)
		_gfx.add_child(_head)
		Geo.put(_head, Geo.sphere(0.52, 22), Enemies.shell_mat(), Vector3.ZERO, Vector3.ZERO, Vector3(1.0, 0.85, 1.0))
		Geo.put(_head, Geo.rounded_box(Vector3(0.7, 0.16, 0.5), 0.06, 2), Enemies.body_mat(), Vector3(0.0, -0.12, 0.0))
		_barrel = Node3D.new()
		_barrel.position = Vector3(0.0, 0.0, -0.35)
		_head.add_child(_barrel)
		Geo.put(_barrel, Geo.cyl(0.13, 0.17, 0.8, 14), Mats.metal(Color(0.12, 0.12, 0.15), 0.3, 0.9), Vector3(0.0, 0.0, -0.3), Vector3(90.0, 0.0, 0.0))
		Geo.put(_barrel, Geo.torus(0.12, 0.18, 16, 5), Enemies.body_mat(), Vector3(0.0, 0.0, -0.7), Vector3(90.0, 0.0, 0.0))
		_eye_mat = StandardMaterial3D.new()
		_eye_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_eye_mat.albedo_color = Zones.hdr(Enemies.COL, 1.0)
		Geo.put(_head, Geo.sphere(0.15, 12), _eye_mat, Vector3(0.0, 0.2, -0.4), Vector3.ZERO, Vector3.ONE, false)
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
		var muzzle: Vector3 = global_position + Vector3(0.0, 1.15, 0.0)
		if pl != null:
			var tp: Vector3 = pl.global_position + Vector3(0.0, 0.6, 0.0)
			if _lead > 0.0:
				var tof: float = tp.distance_to(muzzle) / 11.0
				tp += Vector3(pl.velocity.x, 0.0, pl.velocity.z) * tof * _lead
			aim = tp - muzzle
			in_range = aim.length() < _range
			if pl.velocity.y < -2.0 and _area.overlaps_body(pl):
				pl.stomp_bounce()
				_die(pl, "stomp")
				return
		if in_range:
			var want: float = atan2(-aim.x, -aim.z)
			_yaw = lerp_angle(_yaw, want, 1.0 - exp(-7.0 * delta))
			_pitch = lerpf(_pitch, atan2(aim.y, Vector2(aim.x, aim.z).length()), 1.0 - exp(-7.0 * delta))
			_head.rotation.y = _yaw
			_barrel.rotation.x = clampf(_pitch, -0.6, 0.8)
			_t -= delta
			if _burst_left > 0:
				_burst_t -= delta
				if _burst_t <= 0.0:
					_burst_left -= 1
					_burst_t = 0.22
					_fire(aim)
			elif _charge < 0.0 and _t <= 0.0:
				_charge = 0.55
				Sfx.play("zap", -8.0, 1.5)
			if _charge >= 0.0:
				_charge -= delta
				var f: float = 1.0 - clampf(_charge / 0.55, 0.0, 1.0)
				_eye_mat.albedo_color = Zones.hdr(Enemies.COL, 1.0 + f * 3.5)
				if _charge < 0.0:
					_fire(aim)
					_burst_left = _burst - 1
					_burst_t = 0.22
					_t = _every
					_eye_mat.albedo_color = Zones.hdr(Enemies.COL, 1.0)
		else:
			_charge = -1.0
			_eye_mat.albedo_color = Zones.hdr(Enemies.COL, 1.0)

	func _fire(aim: Vector3) -> void:
		var dir: Vector3 = aim.normalized()
		var from: Vector3 = global_position + Vector3(0.0, 1.15, 0.0) + dir * 1.1
		Sfx.play("shoot", -4.0)
		Fx.burst(get_parent(), from, Enemies.COL, 5, 3.0, 0.25, 0.2, 0.0)
		_barrel.position.z = -0.15
		var tw := create_tween()
		tw.tween_property(_barrel, "position:z", -0.35, 0.2)
		Enemies.fire(get_parent(), world, from, dir * 11.0, Color(1.0, 0.35, 0.42), 4.5, 0.3, 0.0, "bolt", self)

	func hit(by: Node, kind: String) -> bool:
		if _dead:
			return false
		_die(by, kind)
		return true

	func _die(by: Node, kind: String) -> void:
		_dead = true
		remove_from_group("hittable")
		collision_layer = 0
		Enemies.kill(self, world, _gfx, by, kind, 3, 0.7)


# ---------------------------------------------------------------- hopper
## Spring-legged bouncer. Idles with little hops; when you come close it crouches (tell) and leaps at you.
class Hopper extends Area3D:
	var world: Node = null
	var hit_radius: float = 0.75
	var hit_offset := Vector3(0.0, 0.7, 0.0)
	var _home := Vector3.ZERO
	var _range: float = 9.0
	var _leash: float = 6.0
	var _gfx: Node3D
	var _body: Node3D
	var _spring: Node3D
	var _vel := Vector3.ZERO
	var _state: int = 0
	var _st: float = 0.0
	var _dead: bool = false
	var _ground_y: float = 0.0
	var _squash: float = 0.0
	var _yaw: float = 0.0

	func setup(o: Dictionary) -> void:
		_home = LevelLoader.vec(o.get("p"))
		_ground_y = _home.y
		position = _home
		_range = float(o.get("range", 9.0))
		_leash = float(o.get("leash", 6.0))
		_st = float(o.get("ph", 0.0)) * 1.5
		collision_layer = 0
		collision_mask = 2
		var cs := CollisionShape3D.new()
		var sp := SphereShape3D.new()
		sp.radius = 0.7
		cs.shape = sp
		cs.position = Vector3(0.0, 0.8, 0.0)
		add_child(cs)
		_gfx = Node3D.new()
		add_child(_gfx)
		Geo.put(_gfx, Geo.cyl(0.42, 0.5, 0.14, 20), Enemies.body_mat(), Vector3(0.0, 0.07, 0.0))
		_spring = Node3D.new()
		_spring.position = Vector3(0.0, 0.14, 0.0)
		_gfx.add_child(_spring)
		var coil := PackedVector3Array()
		for i in range(49):
			var a: float = float(i) / 48.0 * TAU * 4.0
			coil.append(Vector3(cos(a) * 0.22, float(i) / 48.0 * 0.5, sin(a) * 0.22))
		Geo.put(_spring, Geo.tube(coil, 0.04, 6), Mats.metal(Color(0.75, 0.75, 0.8), 0.25, 0.9))
		_body = Node3D.new()
		_body.position = Vector3(0.0, 1.0, 0.0)
		_gfx.add_child(_body)
		Geo.put(_body, Geo.sphere(0.48, 22), Enemies.shell_mat(), Vector3.ZERO, Vector3.ZERO, Vector3(1.0, 0.9, 1.0))
		Geo.put(_body, Geo.cyl(0.3, 0.3, 0.12, 20), Mats.metal(Color(0.04, 0.04, 0.06), 0.1, 0.3), Vector3(0.0, 0.05, -0.38), Vector3(90.0, 0.0, 0.0))
		Enemies.eye(_body, 0.17, Vector3(0.0, 0.05, -0.45))
		for sx in [-1.0, 1.0]:
			Geo.put(_body, Geo.cyl(0.03, 0.05, 0.3, 8), Enemies.body_mat(), Vector3(0.18 * float(sx), 0.5, 0.0), Vector3(0.0, 0.0, -20.0 * float(sx)))
			Geo.put(_body, Geo.sphere(0.06, 10), Mats.glow(Enemies.GLOW, 2.0), Vector3(0.24 * float(sx), 0.66, 0.0), Vector3.ZERO, Vector3.ONE, false)
		add_to_group("hittable")

	func _physics_process(delta: float) -> void:
		if _dead or world == null:
			return
		_st += delta
		var pl: Player = Zones.player_of(world)
		var to := Vector3.ZERO
		var near: bool = false
		if pl != null:
			to = pl.global_position - global_position
			near = Vector2(to.x, to.z).length() < _range and absf(to.y) < 3.5
			_yaw = lerp_angle(_yaw, atan2(-to.x, -to.z), 1.0 - exp(-5.0 * delta))
			_gfx.rotation.y = _yaw
		if _state == 0:
			# idle: small hops in place
			var k: float = fposmod(_st, 1.1)
			position.y = _ground_y + maxf(sin(k / 1.1 * PI), 0.0) * 0.35
			_squash = 0.15 * sin(_st * 11.0)
			if near and _st > 1.2:
				_state = 1
				_st = 0.0
				Sfx.play("hopper_charge", -6.0)
		elif _state == 1:
			# tell: deep crouch with a shake
			position.y = _ground_y
			_squash = minf(_st / 0.5, 1.0) * 0.55
			_gfx.position.x = sin(_st * 70.0) * 0.03
			if _st >= 0.55:
				_gfx.position.x = 0.0
				var target: Vector3 = global_position + Vector3(to.x, 0.0, to.z)
				var off: Vector3 = target - _home
				off.y = 0.0
				off = off.limit_length(_leash)
				target = _home + off
				target.y = _ground_y
				_vel = Enemies.lob(global_position, target, 0.75, 30.0)
				_state = 2
				_st = 0.0
				Sfx.play("bounce", -4.0, 0.7)
		elif _state == 2:
			_vel.y -= 30.0 * delta
			position += _vel * delta
			_squash = -0.25
			if position.y <= _ground_y and _vel.y < 0.0:
				position.y = _ground_y
				_state = 3
				_st = 0.0
				Fx.ring(get_parent(), global_position, Enemies.COL, 3.0, 0.3, 2.5)
				Fx.burst(get_parent(), global_position + Vector3(0.0, 0.1, 0.0), Color(0.8, 0.8, 0.9, 0.6), 8, 3.0, 0.4, 0.4, 0.0, 80.0)
				Sfx.play("land", -6.0, 0.8)
		else:
			_squash = 0.4 * maxf(1.0 - _st * 3.0, 0.0)
			if _st > 1.0:
				_state = 0 if not near else 1
				_st = 0.0
				if _state == 1:
					Sfx.play("hopper_charge", -6.0)
		_spring.scale = Vector3(1.0, clampf(1.0 - _squash, 0.4, 1.4), 1.0)
		_body.position.y = 0.14 + 0.5 * _spring.scale.y + 0.36
		_body.scale = Vector3(1.0 + _squash * 0.25, 1.0 - _squash * 0.2, 1.0 + _squash * 0.25)
		if pl == null or not overlaps_body(pl):
			return
		if pl.is_attacking() or pl.is_dashing():
			return
		if pl.global_position.y > global_position.y + 0.9 and pl.velocity.y < 1.0:
			pl.stomp_bounce()
			_die(pl, "stomp")
		else:
			pl.hurt(global_position, 1)

	func hit(by: Node, kind: String) -> bool:
		if _dead:
			return false
		_die(by, kind)
		return true

	func _die(by: Node, kind: String) -> void:
		_dead = true
		remove_from_group("hittable")
		Enemies.kill(self, world, _gfx, by, kind, 2, 0.6)


# ---------------------------------------------------------------- shield
## Walker with an energy shield. Hits from the front are blocked (punch, dash). Spin shatters the shield
## and stuns it; stomp or any hit from behind destroys it. a / b = patrol end points (floor).
class ShieldBot extends Area3D:
	var world: Node = null
	var hit_radius: float = 0.9
	var hit_offset := Vector3(0.0, 0.8, 0.0)
	var _a := Vector3.ZERO
	var _b := Vector3.ZERO
	var _u: float = 0.0
	var _dirs: float = 1.0
	var _gfx: Node3D
	var _shield: Node3D
	var _shield_mat: ShaderMaterial
	var _legs: Array = []
	var _has_shield: bool = true
	var _stun: float = 0.0
	var _yaw: float = 0.0
	var _walk: float = 0.0
	var _bash: float = 0.0
	var _block_cd: float = 0.0
	var _dead: bool = false
	var _chase: bool = false

	func setup(o: Dictionary) -> void:
		_a = LevelLoader.vec(o.get("a", o.get("p")))
		_b = LevelLoader.vec(o.get("b", o.get("p")))
		position = _a
		collision_layer = 0
		collision_mask = 2
		var cs := CollisionShape3D.new()
		var cap := CapsuleShape3D.new()
		cap.radius = 0.6
		cap.height = 1.7
		cs.shape = cap
		cs.position = Vector3(0.0, 0.85, 0.0)
		add_child(cs)
		_gfx = Node3D.new()
		add_child(_gfx)
		Geo.put(_gfx, Geo.rounded_box(Vector3(0.95, 0.85, 0.75), 0.24, 3), Enemies.shell_mat(), Vector3(0.0, 1.0, 0.0))
		Geo.put(_gfx, Geo.rounded_box(Vector3(0.7, 0.24, 0.1), 0.05, 2), Mats.metal(Color(0.04, 0.04, 0.06), 0.1, 0.3), Vector3(0.0, 1.15, -0.37))
		Geo.put(_gfx, Geo.rounded_box(Vector3(0.5, 0.06, 0.04), 0.02, 2), Mats.glow(Enemies.GLOW, 3.0), Vector3(0.0, 1.15, -0.43), Vector3.ZERO, Vector3.ONE, false)
		Geo.put(_gfx, Geo.rounded_box(Vector3(0.6, 0.12, 0.5), 0.05, 2), Enemies.body_mat(), Vector3(0.0, 1.47, 0.0))
		for sx in [-1.0, 1.0]:
			var leg := Node3D.new()
			leg.position = Vector3(0.28 * float(sx), 0.6, 0.0)
			_gfx.add_child(leg)
			Geo.put(leg, Geo.cyl(0.11, 0.13, 0.45, 12), Enemies.body_mat(), Vector3(0.0, -0.25, 0.0))
			Geo.put(leg, Geo.rounded_box(Vector3(0.3, 0.14, 0.42), 0.05, 2), Enemies.shell_mat(), Vector3(0.0, -0.52, -0.06))
			_legs.append(leg)
		_shield = Node3D.new()
		_shield.position = Vector3(0.0, 1.0, -0.85)
		_gfx.add_child(_shield)
		var hexm := CylinderMesh.new()
		hexm.top_radius = 0.95
		hexm.bottom_radius = 0.95
		hexm.height = 0.06
		hexm.radial_segments = 6
		hexm.rings = 1
		_shield_mat = Mats.neon_unique(Color(1.0, 0.45, 0.25), 1.6, 1.5, 0.28)
		Geo.put(_shield, hexm, _shield_mat, Vector3.ZERO, Vector3(90.0, 0.0, 30.0), Vector3.ONE, false)
		Geo.put(_shield, Geo.torus(0.88, 0.98, 6, 4), Mats.glow(Color(1.0, 0.5, 0.25), 2.2), Vector3.ZERO, Vector3(90.0, 0.0, 30.0), Vector3.ONE, false)
		add_to_group("hittable")

	func _forward() -> Vector3:
		return Vector3(-sin(_yaw), 0.0, -cos(_yaw))

	func _physics_process(delta: float) -> void:
		if _dead or world == null:
			return
		_stun = maxf(_stun - delta, 0.0)
		_block_cd = maxf(_block_cd - delta, 0.0)
		var pl: Player = Zones.player_of(world)
		var spd: float = 0.0
		var want_yaw: float = _yaw
		_chase = false
		if pl != null and _stun <= 0.0:
			var to: Vector3 = pl.global_position - global_position
			if Vector2(to.x, to.z).length() < 9.0 and absf(to.y) < 2.5:
				_chase = true
				want_yaw = atan2(-to.x, -to.z)
		if _stun <= 0.0:
			var ab: Vector3 = _b - _a
			var seg: float = ab.length()
			if _chase and pl != null and seg > 0.1:
				var proj: float = clampf((pl.global_position - _a).dot(ab / seg), 0.0, seg)
				var cur: float = _u * seg
				var stepv: float = clampf(proj - cur, -2.2 * delta, 2.2 * delta)
				_u = clampf((cur + stepv) / seg, 0.0, 1.0)
				spd = absf(stepv) / maxf(delta, 0.001)
			elif seg > 0.1:
				_u += _dirs * 1.6 * delta / seg
				if _u >= 1.0 or _u <= 0.0:
					_u = clampf(_u, 0.0, 1.0)
					_dirs = -_dirs
				want_yaw = atan2(-ab.x * _dirs, -ab.z * _dirs)
				spd = 1.6
			position = _a.lerp(_b, _u)
			# turn rate is limited: circle around it to reach its back
			_yaw = rotate_toward(_yaw, want_yaw, 1.7 * delta)
		_walk += delta * spd * 3.0
		for i in range(_legs.size()):
			var lg: Node3D = _legs[i]
			lg.rotation.x = sin(_walk + PI * float(i)) * 0.5 * minf(spd, 1.0)
		_gfx.rotation.y = _yaw
		_gfx.position.y = absf(sin(_walk)) * 0.05
		if _stun > 0.0:
			_gfx.rotation.z = sin(_stun * 20.0) * 0.12
		else:
			_gfx.rotation.z = 0.0
		if _shield.visible:
			_shield_mat.set_shader_parameter("energy", 1.6 + 0.4 * sin(float(world.time) * 6.0))
		# shield bash when close and facing the player
		_bash = maxf(_bash - delta, 0.0)
		if pl == null or not overlaps_body(pl):
			return
		if pl.is_dashing() or pl.is_spinning():
			return
		if pl.global_position.y > global_position.y + 1.3 and pl.velocity.y < 1.0:
			pl.stomp_bounce()
			_die(pl, "stomp")
			return
		pl.hurt(global_position, 1)

	func hit(by: Node, kind: String) -> bool:
		if _dead:
			return false
		var from: Vector3 = (by as Node3D).global_position if by is Node3D else global_position
		var to_hitter: Vector3 = from - global_position
		to_hitter.y = 0.0
		var front: bool = to_hitter.length() > 0.05 and to_hitter.normalized().dot(_forward()) > 0.25
		if kind == "stomp" or not front or not _has_shield or _stun > 0.0:
			_die(by, kind)
			return true
		if kind == "spin" or kind == "spin_big" or kind == "punch3":
			_break_shield()
			return true
		# blocked
		if _block_cd <= 0.0:
			_block_cd = 0.25
			Sfx.play("clang", -2.0, randf_range(0.9, 1.1))
			Fx.burst(get_parent(), _shield.global_position, Color(1.0, 0.7, 0.3), 12, 6.0, 0.25, 0.3, -6.0)
			Fx.ring(get_parent(), _shield.global_position, Color(1.0, 0.6, 0.3), 2.0, 0.2, 3.0)
			if by is Player:
				var p: Player = by
				var away: Vector3 = (p.global_position - global_position)
				away.y = 0.0
				p.launch(away.normalized() * 8.0 + Vector3(0.0, 4.0, 0.0))
			if world != null:
				world.toast("الدرع يصدّ الضربات من الأمام! التفّ حوله أو استخدم الدوران", Color(1.0, 0.6, 0.3))
		return false

	func _break_shield() -> void:
		_has_shield = false
		_stun = 2.2
		Sfx.play("shatter", 0.0)
		Debris.shards(get_parent(), _shield.global_position, 0.6, Mats.glow(Color(1.0, 0.5, 0.25), 1.6), global_position, 5.0, 10, 0.22, 2.5)
		_shield.visible = false
		if world != null:
			world.hitstop(0.08)

	func _die(by: Node, kind: String) -> void:
		_dead = true
		remove_from_group("hittable")
		if _shield.visible:
			_shield.visible = false
		Enemies.kill(self, world, _gfx, by, kind, 4, 0.8)


# ---------------------------------------------------------------- spider
## Crystal crawler: six procedurally stepping legs; wanders around its home, chases and lunges at you.
class Spider extends Area3D:
	var world: Node = null
	var hit_radius: float = 0.8
	var hit_offset := Vector3(0.0, 0.5, 0.0)
	var _home := Vector3.ZERO
	var _r: float = 4.0
	var _gfx: Node3D
	var _body: Node3D
	var _legs: Array = []
	var _yaw: float = 0.0
	var _target := Vector3.ZERO
	var _retarget: float = 0.0
	var _lunge: float = 0.0
	var _lunge_cd: float = 0.0
	var _vel := Vector3.ZERO
	var _dead: bool = false
	var _t: float = 0.0

	func setup(o: Dictionary) -> void:
		_home = LevelLoader.vec(o.get("p"))
		_r = float(o.get("r", 4.0))
		position = _home
		_target = _home
		collision_layer = 0
		collision_mask = 2
		var cs := CollisionShape3D.new()
		var sp := SphereShape3D.new()
		sp.radius = 0.75
		cs.shape = sp
		cs.position = Vector3(0.0, 0.55, 0.0)
		add_child(cs)
		_gfx = Node3D.new()
		add_child(_gfx)
		_body = Node3D.new()
		_body.position = Vector3(0.0, 0.62, 0.0)
		_gfx.add_child(_body)
		var crystal: Material = Mats.plastic(Color(0.85, 0.3, 0.75), 0.15, Color(1.0, 0.3, 0.85), 0.8)
		Geo.put(_body, Geo.sphere(0.45, 18), Enemies.shell_mat(), Vector3(0.0, 0.0, 0.15), Vector3.ZERO, Vector3(1.0, 0.75, 1.25))
		Geo.put(_body, Geo.sphere(0.27, 14), Enemies.body_mat(), Vector3(0.0, 0.0, -0.42))
		Enemies.eye(_body, 0.08, Vector3(-0.1, 0.06, -0.64))
		Enemies.eye(_body, 0.08, Vector3(0.1, 0.06, -0.64))
		Enemies.eye(_body, 0.05, Vector3(0.0, 0.16, -0.6))
		for i in range(4):
			var a: float = float(i) * 1.4
			Geo.put(_body, Geo.crystal(0.1, 0.3, 0.2, 5), crystal, Vector3(sin(a) * 0.18, 0.25, 0.2 + cos(a) * 0.15), Vector3(-20.0 + float(i) * 12.0, a * 50.0, 15.0 * sin(a)))
		var leg_mat: Material = Enemies.body_mat()
		for i in range(6):
			var side: float = -1.0 if i < 3 else 1.0
			var k: int = i % 3
			var root := Vector3(0.32 * side, 0.6, -0.15 + float(k) * 0.3)
			var rest := Vector3(1.05 * side, 0.0, -0.55 + float(k) * 0.55)
			var up := MeshInstance3D.new()
			up.mesh = Geo.cyl(0.05, 0.07, 1.0, 8)
			up.material_override = leg_mat
			_gfx.add_child(up)
			var lo := MeshInstance3D.new()
			lo.mesh = Geo.cyl(0.02, 0.05, 1.0, 8)
			lo.material_override = leg_mat
			_gfx.add_child(lo)
			_legs.append({"root": root, "rest": rest, "foot": Vector3.ZERO, "from": Vector3.ZERO, "t": 1.0, "up": up, "lo": lo, "grp": (i + k) % 2})
		add_to_group("hittable")

	func _ready() -> void:
		for l in _legs:
			var d: Dictionary = l
			d["foot"] = global_transform * (d["rest"] as Vector3)

	func _physics_process(delta: float) -> void:
		if _dead or world == null:
			return
		_t += delta
		_lunge_cd = maxf(_lunge_cd - delta, 0.0)
		var pl: Player = Zones.player_of(world)
		var spd: float = 1.6
		_retarget -= delta
		var chasing: bool = false
		if pl != null:
			var to: Vector3 = pl.global_position - _home
			if Vector2(to.x, to.z).length() < _r + 5.0 and absf(pl.global_position.y - _home.y) < 2.5:
				chasing = true
				var off: Vector3 = Vector3(to.x, 0.0, to.z).limit_length(_r)
				_target = _home + off
				spd = 4.6
				var dd: Vector3 = pl.global_position - global_position
				if _lunge_cd <= 0.0 and Vector2(dd.x, dd.z).length() < 2.6:
					_lunge = 0.35
					_lunge_cd = 1.6
					_vel = Vector3(dd.x, 0.0, dd.z).normalized() * 9.0 + Vector3(0.0, 5.5, 0.0)
					Sfx.play("spider_hiss", -4.0)
		if not chasing and _retarget <= 0.0:
			_retarget = randf_range(1.2, 2.6)
			var a: float = randf() * TAU
			_target = _home + Vector3(cos(a), 0.0, sin(a)) * randf_range(0.0, _r)
		var cur := Vector3(position.x, _home.y, position.z)
		if _lunge > 0.0:
			_lunge -= delta
			_vel.y -= 28.0 * delta
			var np: Vector3 = position + _vel * delta
			var off2: Vector3 = Vector3(np.x, 0.0, np.z) - Vector3(_home.x, 0.0, _home.z)
			if off2.length() > _r + 0.5:
				_vel.x = 0.0
				_vel.z = 0.0
				np = position + Vector3(0.0, _vel.y * delta, 0.0)
			position = np
			if position.y <= _home.y:
				position.y = _home.y
			if _lunge <= 0.0:
				position.y = _home.y
		else:
			var to_t: Vector3 = _target - cur
			to_t.y = 0.0
			if to_t.length() > 0.2:
				var mv: Vector3 = to_t.normalized() * minf(spd * delta, to_t.length())
				position += mv
				_yaw = rotate_toward(_yaw, atan2(-mv.x, -mv.z), 6.0 * delta)
			position.y = _home.y
		_gfx.rotation.y = _yaw
		_body.position.y = 0.62 + sin(_t * 9.0) * 0.03
		_update_legs(delta, spd)
		if pl == null or not overlaps_body(pl):
			return
		if pl.is_attacking() or pl.is_dashing():
			return
		if pl.global_position.y > global_position.y + 0.65 and pl.velocity.y < 1.0:
			pl.stomp_bounce()
			_die(pl, "stomp")
		else:
			pl.hurt(global_position, 1)

	func _update_legs(delta: float, spd: float) -> void:
		var xf: Transform3D = _gfx.global_transform
		var groups_moving: Array = [false, false]
		for l in _legs:
			var d: Dictionary = l
			if float(d["t"]) < 1.0:
				groups_moving[int(d["grp"])] = true
		for l in _legs:
			var d2: Dictionary = l
			var rest_w: Vector3 = xf * (d2["rest"] as Vector3)
			rest_w.y = global_position.y
			var foot: Vector3 = d2["foot"]
			var t: float = float(d2["t"])
			if t >= 1.0 and foot.distance_to(rest_w) > 0.55 and not groups_moving[1 - int(d2["grp"])]:
				d2["from"] = foot
				d2["t"] = 0.0
				t = 0.0
			if t < 1.0:
				t = minf(t + delta * (5.0 + spd * 1.5), 1.0)
				d2["t"] = t
				var p: Vector3 = (d2["from"] as Vector3).lerp(rest_w + (rest_w - (d2["from"] as Vector3)) * 0.25, t)
				p.y += sin(t * PI) * 0.3
				d2["foot"] = p
			_place_leg(d2, xf * (d2["root"] as Vector3) + Vector3(0.0, _body.position.y - 0.62, 0.0), d2["foot"])

	func _place_leg(d: Dictionary, hip: Vector3, foot: Vector3) -> void:
		var l1: float = 0.75
		var l2: float = 0.85
		var to: Vector3 = foot - hip
		var dist: float = clampf(to.length(), 0.1, l1 + l2 - 0.01)
		var dirv: Vector3 = to.normalized()
		var a: float = acos(clampf((l1 * l1 + dist * dist - l2 * l2) / (2.0 * l1 * dist), -1.0, 1.0))
		var side: Vector3 = dirv.cross(Vector3.UP).normalized()
		if side.length() < 0.1:
			side = Vector3.RIGHT
		var bend: Vector3 = side.cross(dirv).normalized()
		if bend.y < 0.0:
			bend = -bend
		var knee: Vector3 = hip + dirv * cos(a) * l1 + bend * sin(a) * l1
		_seg(d["up"], hip, knee)
		_seg(d["lo"], knee, foot)

	func _seg(mi: MeshInstance3D, a: Vector3, b: Vector3) -> void:
		var len: float = maxf(a.distance_to(b), 0.01)
		mi.global_transform = Transform3D(Platforms.basis_y(b - a) * Basis.from_scale(Vector3(1.0, len, 1.0)), (a + b) * 0.5)

	func hit(by: Node, kind: String) -> bool:
		if _dead:
			return false
		_die(by, kind)
		return true

	func _die(by: Node, kind: String) -> void:
		_dead = true
		remove_from_group("hittable")
		Enemies.kill(self, world, _gfx, by, kind, 3, 0.6)


# ---------------------------------------------------------------- snowbot
## Squat artillery bot that lobs snowballs at where you are going to be. Punch the snowball back!
class SnowBot extends StaticBody3D:
	var world: Node = null
	var hit_radius: float = 0.9
	var hit_offset := Vector3(0.0, 0.9, 0.0)
	var _range: float = 22.0
	var _every: float = 2.6
	var _t: float = 1.0
	var _wind: float = -1.0
	var _gfx: Node3D
	var _arm: Node3D
	var _head: Node3D
	var _area: Area3D
	var _dead: bool = false
	var _yaw: float = 0.0

	func setup(o: Dictionary) -> void:
		position = LevelLoader.vec(o.get("p"))
		_range = float(o.get("range", 22.0))
		_every = maxf(1.2, float(o.get("every", 2.6)))
		_t = 1.0 + float(o.get("ph", 0.0)) * _every
		collision_layer = 1
		collision_mask = 0
		var cs := CollisionShape3D.new()
		var cy := CylinderShape3D.new()
		cy.radius = 0.8
		cy.height = 1.5
		cs.shape = cy
		cs.position = Vector3(0.0, 0.75, 0.0)
		add_child(cs)
		_gfx = Node3D.new()
		add_child(_gfx)
		var snow: Material = Mats.std(Color(0.9, 0.95, 1.0), 0.0, 0.75)
		Geo.put(_gfx, Geo.sphere(0.85, 20), Enemies.shell_mat(), Vector3(0.0, 0.55, 0.0), Vector3.ZERO, Vector3(1.0, 0.7, 1.0))
		Geo.put(_gfx, Geo.sphere(0.88, 20), snow, Vector3(0.0, 0.62, 0.0), Vector3.ZERO, Vector3(1.0, 0.32, 1.0))
		_head = Node3D.new()
		_head.position = Vector3(0.0, 1.1, 0.0)
		_gfx.add_child(_head)
		Geo.put(_head, Geo.sphere(0.45, 18), Enemies.body_mat(), Vector3.ZERO, Vector3.ZERO, Vector3(1.0, 0.8, 1.0))
		Geo.put(_head, Geo.rounded_box(Vector3(0.6, 0.14, 0.2), 0.05, 2), Mats.metal(Color(0.04, 0.04, 0.06), 0.1, 0.3), Vector3(0.0, 0.05, -0.32))
		Geo.put(_head, Geo.rounded_box(Vector3(0.4, 0.05, 0.04), 0.02, 2), Mats.glow(Color(0.4, 0.8, 1.0), 3.0), Vector3(0.0, 0.05, -0.43), Vector3.ZERO, Vector3.ONE, false)
		_arm = Node3D.new()
		_arm.position = Vector3(0.55, 0.85, 0.0)
		_gfx.add_child(_arm)
		Geo.put(_arm, Geo.cyl(0.09, 0.11, 0.7, 10), Enemies.body_mat(), Vector3(0.0, 0.35, 0.0))
		Geo.put(_arm, Geo.cyl(0.24, 0.18, 0.18, 14), Enemies.body_mat(), Vector3(0.0, 0.75, 0.0))
		Geo.put(_arm, Geo.rock(0.22, 5, 1, 0.12), snow, Vector3(0.0, 0.92, 0.0))
		_area = Area3D.new()
		_area.collision_layer = 0
		_area.collision_mask = 2
		var acs := CollisionShape3D.new()
		var abs_ := BoxShape3D.new()
		abs_.size = Vector3(1.5, 0.6, 1.5)
		acs.shape = abs_
		acs.position = Vector3(0.0, 1.75, 0.0)
		_area.add_child(acs)
		add_child(_area)
		add_to_group("hittable")

	func _physics_process(delta: float) -> void:
		if _dead or world == null:
			return
		var pl: Player = Zones.player_of(world)
		if pl == null:
			return
		if pl.velocity.y < -2.0 and _area.overlaps_body(pl):
			pl.stomp_bounce()
			_die(pl, "stomp")
			return
		var to: Vector3 = pl.global_position - global_position
		var in_range: bool = to.length() < _range
		if in_range:
			_yaw = lerp_angle(_yaw, atan2(-to.x, -to.z), 1.0 - exp(-5.0 * delta))
			_gfx.rotation.y = _yaw
		_t -= delta
		if _wind < 0.0 and _t <= 0.0 and in_range:
			_wind = 0.6
			Sfx.play("whoosh", -10.0, 0.7)
		if _wind >= 0.0:
			_wind -= delta
			var k: float = 1.0 - clampf(_wind / 0.6, 0.0, 1.0)
			_arm.rotation.x = lerpf(0.0, 1.6, k)
			if _wind < 0.0:
				_arm.rotation.x = -0.9
				var tw := create_tween()
				tw.tween_property(_arm, "rotation:x", 0.0, 0.4)
				_throw(pl)
				_t = _every

	func _throw(pl: Player) -> void:
		var from: Vector3 = _arm.global_position + Vector3(0.0, 1.0, 0.0)
		var target: Vector3 = pl.global_position + Vector3(0.0, 0.4, 0.0)
		var dist: float = Vector2(target.x - from.x, target.z - from.z).length()
		var tof: float = clampf(dist / 11.0, 0.7, 1.7)
		target += Vector3(pl.velocity.x, 0.0, pl.velocity.z) * tof * 0.8
		var v: Vector3 = Enemies.lob(from, target, tof, 20.0)
		Sfx.play("throw", -4.0)
		Enemies.fire(get_parent(), world, from, v, Color(0.9, 0.95, 1.0), 4.0, 0.32, 20.0, "snow", self)

	func hit(by: Node, kind: String) -> bool:
		if _dead:
			return false
		_die(by, kind)
		return true

	func _die(by: Node, kind: String) -> void:
		_dead = true
		remove_from_group("hittable")
		collision_layer = 0
		Enemies.kill(self, world, _gfx, by, kind, 3, 0.8)
