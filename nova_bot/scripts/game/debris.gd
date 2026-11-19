class_name Debris
extends RefCounted
## Physics destruction: everything that breaks turns into real rigid bodies (Jolt) that tumble, bounce,
## pile up and get kicked around by the player, then shrink away. Also: physical gem / energy bursts and
## the "wreck" sequence used for enemy deaths (knocked flying -> smoke -> explodes into its parts).
## Layer 5 (value 16) = debris; it collides with the world and with other debris, never with the player.

const LAYER := 16
const MASK := 1 | 16

static var _live: Array = []
static var _pmat: PhysicsMaterial = null
static var _shapes: Dictionary = {}


static func max_count() -> int:
	var a: Array = [36, 80, 140]
	return int(a[Game.quality()])


static func phys_mat() -> PhysicsMaterial:
	if _pmat == null:
		_pmat = PhysicsMaterial.new()
		_pmat.bounce = 0.28
		_pmat.friction = 0.75
	return _pmat


static func _register(rb: Node) -> void:
	var keep: Array = []
	for n in _live:
		if is_instance_valid(n) and not (n as Node).is_queued_for_deletion():
			keep.append(n)
	_live = keep
	_live.append(rb)
	while _live.size() > max_count():
		var old: Node = _live.pop_front()
		if is_instance_valid(old):
			old.queue_free()


static func box_shape(s: Vector3) -> BoxShape3D:
	var key: String = "%.2f_%.2f_%.2f" % [s.x, s.y, s.z]
	if _shapes.has(key):
		return _shapes[key]
	var b := BoxShape3D.new()
	b.size = Vector3(maxf(s.x, 0.04), maxf(s.y, 0.04), maxf(s.z, 0.04))
	_shapes[key] = b
	return b


# ------------------------------------------------------------------ chunk
class Chunk extends RigidBody3D:
	var life: float = 5.0
	var _t: float = 0.0
	var _vis: Node3D
	var _s0 := Vector3.ONE

	func setup_visual(v: Node3D) -> void:
		_vis = v
		_s0 = v.scale

	func _ready() -> void:
		add_to_group("debris")

	func _physics_process(delta: float) -> void:
		_t += delta
		if _vis != null and _t > life - 0.6:
			var k: float = clampf((life - _t) / 0.6, 0.0, 1.0)
			_vis.scale = _s0 * maxf(k, 0.001)
		if _t >= life:
			queue_free()


## Generic debris piece. `xform` = world transform of the piece centre; the mesh is drawn with `mesh_off` local offset.
static func piece(parent: Node, mesh: Mesh, mat: Material, xform: Transform3D, shape: Shape3D, lin: Vector3, ang: Vector3, life: float = 4.5, mass: float = 1.0, mesh_off: Transform3D = Transform3D.IDENTITY) -> Chunk:
	if parent == null or not parent.is_inside_tree():
		return null
	var rb := Chunk.new()
	rb.collision_layer = LAYER
	rb.collision_mask = MASK
	rb.mass = mass
	rb.physics_material_override = phys_mat()
	rb.life = life * randf_range(0.85, 1.15)
	rb.linear_damp = 0.15
	rb.angular_damp = 0.4
	rb.continuous_cd = lin.length() > 12.0
	var cs := CollisionShape3D.new()
	cs.shape = shape
	rb.add_child(cs)
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.transform = mesh_off
	rb.add_child(mi)
	rb.setup_visual(mi)
	parent.add_child(rb)
	rb.global_transform = xform
	rb.linear_velocity = lin
	rb.angular_velocity = ang
	_register(rb)
	return rb


static func _rand_ang(k: float) -> Vector3:
	return Vector3(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)) * k


## Splits a box (size, world transform `xf`) into `count` irregular chunks and blasts them away from `from`.
static func box_shatter(parent: Node, xf: Transform3D, size: Vector3, mat: Material, from: Vector3, force: float = 6.0, count: int = 8, life: float = 4.5) -> void:
	var boxes: Array = [[Vector3.ZERO, size]]
	var guard: int = 0
	while boxes.size() < count and guard < 64:
		guard += 1
		var bi: int = 0
		var best: float = 0.0
		for i in range(boxes.size()):
			var bs: Vector3 = boxes[i][1]
			var vol: float = bs.x * bs.y * bs.z
			if vol > best:
				best = vol
				bi = i
		var b: Array = boxes[bi]
		boxes.remove_at(bi)
		var c: Vector3 = b[0]
		var s: Vector3 = b[1]
		var ax: int = 0
		if s.y > s[ax]:
			ax = 1
		if s.z > s[ax]:
			ax = 2
		var f: float = randf_range(0.3, 0.7)
		var s1: Vector3 = s
		var s2: Vector3 = s
		s1[ax] = s[ax] * f
		s2[ax] = s[ax] * (1.0 - f)
		var c1: Vector3 = c
		var c2: Vector3 = c
		c1[ax] = c[ax] - s[ax] * 0.5 + s1[ax] * 0.5
		c2[ax] = c[ax] + s[ax] * 0.5 - s2[ax] * 0.5
		boxes.append([c1, s1])
		boxes.append([c2, s2])
	var mul: float = Game.particle_scale()
	var n_keep: int = maxi(3, int(float(boxes.size()) * mul))
	for i in range(mini(n_keep, boxes.size())):
		var c3: Vector3 = boxes[i][0]
		var s3: Vector3 = boxes[i][1] * 0.97
		var wp: Vector3 = xf * c3
		var away: Vector3 = (wp - from)
		away.y = maxf(away.y, 0.0)
		away = away.normalized() if away.length() > 0.01 else Vector3.UP
		var lin: Vector3 = away * force * randf_range(0.6, 1.2) + Vector3(0.0, force * 0.55, 0.0)
		var m: float = clampf(s3.x * s3.y * s3.z * 6.0, 0.15, 6.0)
		piece(parent, Geo.box(s3), mat, Transform3D(xf.basis, wp), box_shape(s3), lin, _rand_ang(8.0), life, m)


## Breaks a tech crate into its 12 frame bars and 6 panels.
static func crate_break(parent: Node, xf: Transform3D, edge: float, frame_mat: Material, panel_mat: Material, from: Vector3, force: float = 7.0) -> void:
	var h: float = edge * 0.5
	var bar: float = edge * 0.14
	var parts: Array = []
	for ax in range(3):
		for sa in [-1.0, 1.0]:
			for sb in [-1.0, 1.0]:
				var p := Vector3.ZERO
				var s := Vector3(bar, bar, bar)
				s[ax] = edge
				p[(ax + 1) % 3] = float(sa) * (h - bar * 0.5)
				p[(ax + 2) % 3] = float(sb) * (h - bar * 0.5)
				parts.append([p, s, frame_mat])
	var pt: float = edge * 0.09
	for ax2 in range(3):
		for sg in [-1.0, 1.0]:
			var p2 := Vector3.ZERO
			p2[ax2] = float(sg) * (h - pt * 0.5)
			var s2 := Vector3(edge - bar * 1.6, edge - bar * 1.6, edge - bar * 1.6)
			s2[ax2] = pt
			parts.append([p2, s2, panel_mat])
	var keep: float = Game.particle_scale()
	for it in parts:
		if randf() > keep + 0.15:
			continue
		var lp: Vector3 = it[0]
		var sz: Vector3 = it[1]
		var mt: Material = it[2]
		var wp: Vector3 = xf * lp
		var away: Vector3 = wp - from
		away.y = absf(away.y) + 0.3
		away = away.normalized()
		var lin: Vector3 = away * force * randf_range(0.7, 1.3) + Vector3(0.0, force * 0.6, 0.0)
		piece(parent, Geo.box(sz), mt, Transform3D(xf.basis, wp), box_shape(sz), lin, _rand_ang(12.0), 4.0, 0.4)


## Sharp shards (crystal, ice, glass). `mat` should be the material of the thing that broke.
static func shards(parent: Node, center: Vector3, radius: float, mat: Material, from: Vector3, force: float = 7.0, count: int = 10, size: float = 0.25, life: float = 4.0) -> void:
	var n: int = maxi(3, int(float(count) * Game.particle_scale()))
	for i in range(n):
		var sd: int = (i * 7 + int(size * 100.0)) % 8
		var sh: Array = Geo.shard(size * randf_range(0.7, 1.3), sd)
		var mesh: ArrayMesh = sh[0]
		var pts: PackedVector3Array = sh[1]
		var key: String = "shard_%d_%.2f" % [sd, size]
		var shape: ConvexPolygonShape3D
		if _shapes.has(key):
			shape = _shapes[key]
		else:
			shape = ConvexPolygonShape3D.new()
			shape.points = pts
			_shapes[key] = shape
		var off := Vector3(randf_range(-1.0, 1.0), randf_range(-0.6, 1.0), randf_range(-1.0, 1.0)) * radius
		var wp: Vector3 = center + off
		var away: Vector3 = (wp - from)
		away.y = absf(away.y) + 0.2
		away = away.normalized()
		var basis := Basis.from_euler(Vector3(randf() * TAU, randf() * TAU, randf() * TAU))
		var lin: Vector3 = away * force * randf_range(0.5, 1.2) + Vector3(0.0, force * 0.5, 0.0)
		piece(parent, mesh, mat, Transform3D(basis, wp), shape, lin, _rand_ang(14.0), life, 0.2)


## Turns every mesh under `root` into its own debris piece (keeps look and world transform).
static func parts(parent: Node, root: Node3D, from: Vector3, force: float = 8.0, inherit: Vector3 = Vector3.ZERO, life: float = 4.0) -> void:
	var list: Array = []
	_collect_meshes(root, list)
	var keep: float = Game.particle_scale()
	for m in list:
		var mi: MeshInstance3D = m
		if mi.mesh == null or not mi.is_visible_in_tree():
			continue
		if randf() > keep + 0.2:
			continue
		var aabb: AABB = mi.mesh.get_aabb()
		var gt: Transform3D = mi.global_transform
		var sc: Vector3 = gt.basis.get_scale()
		var size: Vector3 = aabb.size * sc
		if size.length() < 0.05:
			continue
		var ctr_local: Vector3 = aabb.get_center()
		var wp: Vector3 = gt * ctr_local
		var away: Vector3 = wp - from
		away.y = absf(away.y) + 0.4
		away = away.normalized()
		var lin: Vector3 = inherit + away * force * randf_range(0.6, 1.3) + Vector3(0.0, force * 0.45, 0.0)
		var basis: Basis = gt.basis.orthonormalized()
		var mesh_off := Transform3D(Basis.from_scale(sc), -(Basis.from_scale(sc) * ctr_local))
		var mat: Material = mi.material_override
		if mat == null and mi.mesh.get_surface_count() > 0:
			mat = mi.mesh.surface_get_material(0)
		var mass: float = clampf(size.x * size.y * size.z * 8.0, 0.1, 4.0)
		piece(parent, mi.mesh, mat, Transform3D(basis, wp), box_shape(size * 0.9), lin, _rand_ang(10.0), life, mass, mesh_off)


static func _collect_meshes(n: Node, out: Array) -> void:
	if n is MeshInstance3D:
		out.append(n)
	for c in n.get_children():
		if c is Node3D and not (c is CPUParticles3D):
			_collect_meshes(c, out)


## The player's robot falls apart (death).
static func robot_parts(parent: Node, pos: Vector3, vel: Vector3) -> void:
	var white: Material = Mats.plastic(Color(0.94, 0.95, 0.97), 0.26)
	var dark: Material = Mats.metal(Color(0.16, 0.18, 0.24), 0.32, 0.6)
	var defs: Array = [
		[Geo.rounded_box(Vector3(0.58, 0.45, 0.5), 0.18, 3), white, Vector3(0.0, 1.0, 0.0), Vector3(0.58, 0.45, 0.5)],
		[Geo.rounded_box(Vector3(0.37, 0.3, 0.29), 0.11, 3), white, Vector3(0.0, 0.55, 0.0), Vector3(0.37, 0.3, 0.29)],
		[Geo.sphere(0.074, 12), white, Vector3(-0.3, 0.45, 0.0), Vector3(0.15, 0.15, 0.15)],
		[Geo.sphere(0.074, 12), white, Vector3(0.3, 0.45, 0.0), Vector3(0.15, 0.15, 0.15)],
		[Geo.rounded_box(Vector3(0.15, 0.1, 0.22), 0.045, 2), white, Vector3(-0.1, 0.06, 0.0), Vector3(0.15, 0.1, 0.22)],
		[Geo.rounded_box(Vector3(0.15, 0.1, 0.22), 0.045, 2), white, Vector3(0.1, 0.06, 0.0), Vector3(0.15, 0.1, 0.22)],
		[Geo.rounded_box(Vector3(0.26, 0.11, 0.2), 0.05, 2), dark, Vector3(0.0, 0.33, 0.0), Vector3(0.26, 0.11, 0.2)],
	]
	for d in defs:
		var lp: Vector3 = d[2]
		var away: Vector3 = Vector3(lp.x, 0.6, lp.z + randf_range(-0.3, 0.3)).normalized()
		var lin: Vector3 = vel * 0.3 + away * randf_range(4.0, 7.5) + Vector3(0.0, 3.0, 0.0)
		piece(parent, d[0], d[1], Transform3D(Basis.IDENTITY, pos + lp), box_shape(d[3]), lin, _rand_ang(9.0), 3.2, 0.6)


# ------------------------------------------------------------- pickups
## Physical gem / energy drop: bursts out, bounces, then flies to the player when close.
class Pickup extends RigidBody3D:
	var world: Node = null
	var kind: String = "gem"
	var value: float = 1.0
	var _t: float = 0.0
	var _homing: bool = false
	var _mi: MeshInstance3D
	var _done: bool = false

	func _ready() -> void:
		collision_layer = Debris.LAYER
		collision_mask = 1
		mass = 0.3
		physics_material_override = Debris.phys_mat()
		continuous_cd = true
		var cs := CollisionShape3D.new()
		var sp := SphereShape3D.new()
		sp.radius = 0.2
		cs.shape = sp
		add_child(cs)
		_mi = MeshInstance3D.new()
		if kind == "energy":
			_mi.mesh = Geo.lathe(Geo.pill_profile(0.11, 0.34, 0.08), 12, "energy_orb")
			_mi.material_override = Mats.glow(Color(0.35, 1.0, 0.5), 3.0)
			_mi.position = Vector3(0.0, -0.17, 0.0)
		else:
			_mi.mesh = Collectibles.gem_mesh()
			var m := ShaderMaterial.new()
			m.shader = Mats.shader("res://shaders/coin.gdshader")
			_mi.material_override = m
			_mi.scale = Vector3.ONE * 0.8
		_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(_mi)

	func _physics_process(delta: float) -> void:
		_t += delta
		if _done:
			return
		var pl: Player = Zones.player_of(world)
		if _t > 11.0:
			queue_free()
			return
		if _t > 9.0:
			_mi.visible = int(_t * 12.0) % 2 == 0
		if pl == null:
			return
		var target: Vector3 = pl.global_position + Vector3(0.0, 0.6, 0.0)
		var d: Vector3 = target - global_position
		if not _homing and _t > 0.45 and d.length() < 6.5:
			_homing = true
			freeze = true
			freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
		if _homing:
			var spd: float = 6.0 + _t * 10.0
			global_position += d.normalized() * minf(spd * delta, d.length())
			_mi.rotation.y += delta * 12.0
		if d.length() < 0.75:
			_collect()

	func _collect() -> void:
		_done = true
		var p: Vector3 = global_position
		if kind == "energy":
			var pl: Player = Zones.player_of(world)
			if pl != null:
				pl.set_battery(pl.battery + value)
			Sfx.play("energy", -6.0, randf_range(0.95, 1.1))
			Fx.burst(get_parent(), p, Color(0.4, 1.0, 0.55, 0.9), 6, 3.0, 0.25, 0.35, 0.0)
		else:
			Sfx.play("coin", -6.0, randf_range(1.0, 1.25))
			Fx.burst(get_parent(), p, Color(1.0, 0.85, 0.3, 0.9), 5, 3.0, 0.25, 0.35, 0.0)
			world.add_coins(int(value), p)
		queue_free()


static func spray(parent: Node, world: Node, pos: Vector3, n: int, kind: String = "gem", value: float = 1.0, force: float = 5.0) -> void:
	if parent == null or not parent.is_inside_tree():
		return
	for i in range(n):
		var pk := Pickup.new()
		pk.world = world
		pk.kind = kind
		pk.value = value
		parent.add_child(pk)
		pk.global_position = pos + Vector3(randf_range(-0.2, 0.2), 0.2, randf_range(-0.2, 0.2))
		var a: float = TAU * float(i) / float(maxi(n, 1)) + randf() * 0.6
		pk.linear_velocity = Vector3(cos(a) * force * randf_range(0.4, 0.8), force * randf_range(1.0, 1.5), sin(a) * force * randf_range(0.4, 0.8))
		pk.angular_velocity = _rand_ang(6.0)


# ------------------------------------------------------------- wrecks
## Knock an enemy's visuals flying as a tumbling, smoking carcass that explodes into its parts.
## `gfx` is re-parented into the carcass; `on_boom` (optional) is called with the explosion position.
static func wreck(parent: Node, gfx: Node3D, from: Vector3, power: float, radius: float = 0.6, on_boom: Callable = Callable(), up: float = 0.6, fuse: float = 0.6) -> void:
	if parent == null or not parent.is_inside_tree() or gfx == null:
		return
	var c := Carcass.new()
	c.on_boom = on_boom
	c.fuse = fuse
	var gt: Transform3D = gfx.global_transform
	var cs := CollisionShape3D.new()
	var sp := SphereShape3D.new()
	sp.radius = radius
	cs.shape = sp
	c.add_child(cs)
	parent.add_child(c)
	c.global_transform = Transform3D(Basis.IDENTITY, gt.origin)
	gfx.get_parent().remove_child(gfx)
	c.add_child(gfx)
	gfx.global_transform = gt
	var dir: Vector3 = gt.origin - from
	dir.y = 0.0
	dir = dir.normalized() if dir.length() > 0.01 else Vector3(randf_range(-1.0, 1.0), 0.0, randf_range(-1.0, 1.0)).normalized()
	c.linear_velocity = dir * power + Vector3(0.0, power * up + 3.0, 0.0)
	c.angular_velocity = Vector3(randf_range(-1.0, 1.0), randf_range(-0.5, 0.5), randf_range(-1.0, 1.0)).normalized() * randf_range(8.0, 15.0)
	c.gfx = gfx


class Carcass extends RigidBody3D:
	var gfx: Node3D
	var on_boom: Callable
	var fuse: float = 0.6
	var _t: float = 0.0
	var _boomed: bool = false
	var _smoke: CPUParticles3D

	func _ready() -> void:
		collision_layer = Debris.LAYER
		collision_mask = 1
		mass = 2.0
		physics_material_override = Debris.phys_mat()
		continuous_cd = true
		contact_monitor = true
		max_contacts_reported = 2
		body_entered.connect(_on_hit)
		_smoke = CPUParticles3D.new()
		_smoke.mesh = Fx.quad()
		_smoke.amount = 26
		_smoke.lifetime = 0.7
		_smoke.local_coords = false
		_smoke.direction = Vector3.UP
		_smoke.spread = 40.0
		_smoke.initial_velocity_min = 0.5
		_smoke.initial_velocity_max = 1.5
		_smoke.gravity = Vector3(0.0, 1.5, 0.0)
		_smoke.scale_amount_min = 0.25
		_smoke.scale_amount_max = 0.55
		_smoke.color = Color(0.25, 0.25, 0.3, 0.55)
		_smoke.color_ramp = Fx.fade_ramp()
		add_child(_smoke)
		var sparks := CPUParticles3D.new()
		sparks.mesh = Fx.quad()
		sparks.amount = 16
		sparks.lifetime = 0.35
		sparks.local_coords = false
		sparks.spread = 180.0
		sparks.initial_velocity_min = 3.0
		sparks.initial_velocity_max = 7.0
		sparks.gravity = Vector3(0.0, -12.0, 0.0)
		sparks.scale_amount_min = 0.05
		sparks.scale_amount_max = 0.1
		sparks.color = Color(1.0, 0.8, 0.35, 1.0)
		add_child(sparks)

	func _physics_process(delta: float) -> void:
		_t += delta
		if _t >= fuse:
			boom()

	func _on_hit(_b: Node) -> void:
		if _t > 0.22:
			boom()

	func boom() -> void:
		if _boomed:
			return
		_boomed = true
		var p: Vector3 = global_position
		var par: Node = get_parent()
		Sfx.play("explode", -2.0, randf_range(0.9, 1.15))
		Fx.burst(par, p, Color(1.0, 0.75, 0.3, 1.0), 18, 8.0, 0.45, 0.45, -4.0)
		Fx.burst(par, p, Color(0.3, 0.3, 0.35, 0.7), 10, 3.0, 0.8, 0.9, 1.5)
		Fx.ring(par, p, Color(1.0, 0.6, 0.3), 4.0, 0.35, 3.0)
		Fx.flash(par, p, Color(1.0, 0.7, 0.35), 6.0, 0.25)
		if gfx != null and is_instance_valid(gfx):
			Debris.parts(par, gfx, p - linear_velocity.normalized() * 0.3, 6.5, linear_velocity * 0.3, 3.5)
		if on_boom.is_valid():
			on_boom.call(p)
		queue_free()
