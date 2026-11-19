class_name Platforms
extends RefCounted
## Static and animated platforms. Each inner class has `world` and `setup(o: Dictionary)`.
## Level JSON: p = TOP-CENTRE of the platform, s = [width, thickness, depth], ry = yaw in degrees.


static func add_box(body: Node3D, s: Vector3, c: int, mat: Material = null) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = s
	mi.mesh = bm
	if mat != null:
		mi.material_override = mat
	else:
		mi.material_override = Mats.platform(s * 0.5, c, false)
	body.add_child(mi)
	var cs := CollisionShape3D.new()
	var shp := BoxShape3D.new()
	shp.size = s
	cs.shape = shp
	body.add_child(cs)
	return mi


static func add_cyl(body: Node3D, r: float, th: float, c: int, mat: Material = null) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = r
	cm.bottom_radius = r
	cm.height = th
	cm.radial_segments = 40
	cm.rings = 1
	mi.mesh = cm
	if mat != null:
		mi.material_override = mat
	else:
		mi.material_override = Mats.platform(Vector3(r, th * 0.5, r), c, true)
	body.add_child(mi)
	var cs := CollisionShape3D.new()
	var shp := CylinderShape3D.new()
	shp.radius = r
	shp.height = th
	cs.shape = shp
	body.add_child(cs)
	return mi


## Thin glowing bar between two points (moving-platform tracks, rails). The level root sits at the
## origin, so local == world. Added deferred so it is safe to call from a child's _ready().
static func make_line(parent: Node, a: Vector3, b: Vector3, width: float, mat: Material) -> void:
	var length: float = a.distance_to(b)
	if length < 0.2 or parent == null:
		return
	var dir: Vector3 = (b - a) / length
	var up: Vector3 = Vector3.UP
	if absf(dir.dot(up)) > 0.95:
		up = Vector3.RIGHT
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(width, width, length)
	mi.mesh = bm
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.transform = Transform3D(Basis.looking_at(dir, up), (a + b) * 0.5)
	parent.add_child.call_deferred(mi)


## Basis whose Y axis points along `dir` (for cylinders / capsules laid between two points).
static func basis_y(dir: Vector3) -> Basis:
	var y: Vector3 = dir.normalized()
	var x: Vector3 = Vector3.RIGHT
	if absf(y.dot(x)) > 0.95:
		x = Vector3.FORWARD
	var z: Vector3 = x.cross(y).normalized()
	x = y.cross(z).normalized()
	return Basis(x, y, z)


## True if the player's capsule overlaps the slab (so it must not turn solid yet).
static func player_inside(body: Node3D, half: Vector3, pl: Player) -> bool:
	var lp: Vector3 = body.to_local(pl.global_position)
	return absf(lp.x) <= half.x + 0.4 and absf(lp.z) <= half.z + 0.4 and lp.y < half.y - 0.05 and lp.y + 1.05 > -half.y


# ---------------------------------------------------------------- solid
class Solid extends StaticBody3D:
	var world: Node = null

	func setup(o: Dictionary) -> void:
		collision_layer = 1
		collision_mask = 0
		var c: int = int(o.get("c", 0))
		var top: Vector3 = LevelLoader.vec(o.get("p"))
		if str(o.get("t", "box")) == "cyl":
			var r: float = float(o.get("r", 3.0))
			var th: float = float(o.get("th", 0.8))
			Platforms.add_cyl(self, r, th, c)
			position = top - Vector3(0.0, th * 0.5, 0.0)
		else:
			var s: Vector3 = LevelLoader.vec(o.get("s"), Vector3(4.0, 0.8, 4.0))
			Platforms.add_box(self, s, c)
			position = top - Vector3(0.0, s.y * 0.5, 0.0)
			rotation_degrees.y = float(o.get("ry", 0.0))


# --------------------------------------------------------------- moving
class Moving extends AnimatableBody3D:
	var world: Node = null
	var _start := Vector3.ZERO
	var _off := Vector3.ZERO
	var _per: float = 4.0
	var _ph: float = 0.0
	var _c: int = 0

	func setup(o: Dictionary) -> void:
		collision_layer = 1
		collision_mask = 0
		sync_to_physics = true
		_c = int(o.get("c", 0))
		var top: Vector3 = LevelLoader.vec(o.get("p"))
		var th: float = 0.8
		if o.has("r"):
			var r: float = float(o.get("r", 2.0))
			th = float(o.get("th", 0.8))
			Platforms.add_cyl(self, r, th, _c)
		else:
			var s: Vector3 = LevelLoader.vec(o.get("s"), Vector3(4.0, 0.8, 4.0))
			th = s.y
			Platforms.add_box(self, s, _c)
			rotation_degrees.y = float(o.get("ry", 0.0))
		_start = top - Vector3(0.0, th * 0.5, 0.0)
		position = _start
		_off = LevelLoader.vec(o.get("off"))
		_per = maxf(0.5, float(o.get("per", 4.0)))
		_ph = float(o.get("ph", 0.0))

	func _ready() -> void:
		var parent: Node = get_parent()
		if parent != null and _off.length() > 0.3:
			Platforms.make_line(parent, _start, _start + _off, 0.06, Mats.neon(Mats.accent(_c), 1.4, 1.0, 0.55, 0.5))

	func _physics_process(_delta: float) -> void:
		var t: float = 0.0
		if world != null:
			t = float(world.time)
		var k: float = 0.5 - 0.5 * cos(TAU * (t / _per + _ph))
		position = _start + _off * k


# -------------------------------------------------------------- crumble
class Crumble extends StaticBody3D:
	var world: Node = null
	var _delay: float = 0.6
	var _respawn: float = 3.0
	var _state: int = 0
	var _timer: float = 0.0
	var _mi: MeshInstance3D
	var _area: Area3D
	var _half := Vector3.ONE

	func setup(o: Dictionary) -> void:
		collision_layer = 1
		collision_mask = 0
		var c: int = int(o.get("c", 3))
		var top: Vector3 = LevelLoader.vec(o.get("p"))
		var s: Vector3 = LevelLoader.vec(o.get("s"), Vector3(4.0, 0.7, 4.0))
		_half = s * 0.5
		_delay = float(o.get("delay", 0.6))
		_respawn = float(o.get("respawn", 3.0))
		_mi = Platforms.add_box(self, s, c)
		position = top - Vector3(0.0, s.y * 0.5, 0.0)
		rotation_degrees.y = float(o.get("ry", 0.0))
		_area = Area3D.new()
		_area.collision_layer = 0
		_area.collision_mask = 2
		var cs := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = Vector3(s.x * 0.96, 0.5, s.z * 0.96)
		cs.shape = bs
		cs.position = Vector3(0.0, s.y * 0.5 + 0.2, 0.0)
		_area.add_child(cs)
		add_child(_area)

	func _physics_process(delta: float) -> void:
		if world == null:
			return
		var pl: Player = world.player
		if pl == null or not is_instance_valid(pl):
			return
		if _state == 0:
			if pl.alive and _area.overlaps_body(pl):
				_state = 1
				_timer = _delay
				Sfx.play("crumble", -4.0)
		elif _state == 1:
			_timer -= delta
			_mi.position = Vector3(randf_range(-1.0, 1.0), randf_range(-0.5, 0.5), randf_range(-1.0, 1.0)) * 0.05
			if _timer <= 0.0:
				_state = 2
				_timer = _respawn
				collision_layer = 0
				Fx.burst(self, global_position + Vector3(0.0, 0.3, 0.0), Color(0.9, 0.7, 0.5, 0.9), 12, 4.0, 0.35, 0.8, -9.0)
				var tw := create_tween()
				tw.tween_property(_mi, "position:y", -14.0, 0.9).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		else:
			_timer -= delta
			if _timer <= 0.0 and not Platforms.player_inside(self, _half, pl):
				_state = 0
				_mi.position = Vector3.ZERO
				_mi.scale = Vector3(0.7, 0.7, 0.7)
				collision_layer = 1
				var tw2 := create_tween()
				tw2.tween_property(_mi, "scale", Vector3.ONE, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


# ---------------------------------------------------------------- ghost
class Ghost extends StaticBody3D:
	var world: Node = null
	var _on: float = 2.0
	var _off: float = 1.5
	var _ph: float = 0.0
	var _mode: String = "cycle"
	var _id: String = ""
	var _solid: bool = true
	var _fade: float = 1.0
	var _half := Vector3.ONE
	var _mat: ShaderMaterial

	func setup(o: Dictionary) -> void:
		collision_layer = 1
		collision_mask = 0
		var c: int = int(o.get("c", 2))
		var top: Vector3 = LevelLoader.vec(o.get("p"))
		var s: Vector3 = LevelLoader.vec(o.get("s"), Vector3(3.0, 0.5, 3.0))
		_half = s * 0.5
		_on = float(o.get("on", 2.0))
		_off = float(o.get("off", 1.5))
		_ph = float(o.get("ph", 0.0))
		_mode = str(o.get("mode", "cycle"))
		_id = str(o.get("id", ""))
		_mat = Mats.ghost(_half, c)
		Platforms.add_box(self, s, c, _mat)
		position = top - Vector3(0.0, s.y * 0.5, 0.0)
		rotation_degrees.y = float(o.get("ry", 0.0))
		if _mode == "switch":
			_solid = false
			_fade = 0.0
			collision_layer = 0

	func _physics_process(delta: float) -> void:
		if world == null:
			return
		var want: bool = true
		var warn: float = 0.0
		if _mode == "switch":
			want = bool(world.is_switch_on(_id))
			var left: float = float(world.switch_left(_id))
			if want and left < 1.3:
				warn = 1.0
		else:
			var cyc: float = maxf(_on + _off, 0.1)
			var t: float = fposmod(float(world.time) + _ph * cyc, cyc)
			want = t < _on
			if want and t > _on - 0.7:
				warn = 1.0
		if want and not _solid:
			var pl: Player = world.player
			if pl != null and is_instance_valid(pl) and Platforms.player_inside(self, _half, pl):
				want = false
		if want != _solid:
			_solid = want
			collision_layer = 1 if _solid else 0
		_fade = move_toward(_fade, 1.0 if _solid else 0.0, delta * 6.0)
		_mat.set_shader_parameter("fade", _fade)
		_mat.set_shader_parameter("warn", warn)


# -------------------------------------------------------------- sweeper
## Rotating bar ("jump rope"). p = bar centre top, len = bar length, speed in rad/s (sign = direction).
class Sweeper extends AnimatableBody3D:
	var world: Node = null
	var _speed: float = 1.2
	var _ph: float = 0.0
	var _area: Area3D
	var _cool: float = 0.0
	var _top_y: float = 0.0

	func setup(o: Dictionary) -> void:
		collision_layer = 1
		collision_mask = 0
		sync_to_physics = true
		var c: int = int(o.get("c", 2))
		var top: Vector3 = LevelLoader.vec(o.get("p"))
		var length: float = float(o.get("len", 8.0))
		var w: float = float(o.get("w", 0.7))
		var th: float = float(o.get("th", 0.5))
		_speed = float(o.get("speed", 1.2))
		_ph = float(o.get("ph", 0.0))
		Platforms.add_box(self, Vector3(length, th, w), c)
		var hub := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.55
		cm.bottom_radius = 0.55
		cm.height = th + 0.25
		hub.mesh = cm
		hub.material_override = Mats.neon(Mats.accent(c), 2.0, 1.5, 0.7)
		add_child(hub)
		position = top - Vector3(0.0, th * 0.5, 0.0)
		_top_y = top.y
		_area = Area3D.new()
		_area.collision_layer = 0
		_area.collision_mask = 2
		var cs := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = Vector3(length + 0.4, th + 0.3, w + 0.5)
		cs.shape = bs
		_area.add_child(cs)
		add_child(_area)

	func _physics_process(delta: float) -> void:
		if world == null:
			return
		rotation.y = _ph + float(world.time) * _speed
		_cool = maxf(_cool - delta, 0.0)
		var pl: Player = world.player
		if pl == null or not is_instance_valid(pl) or not pl.alive or _cool > 0.0:
			return
		if pl.global_position.y < _top_y - 0.15 and _area.overlaps_body(pl):
			var off: Vector3 = pl.global_position - global_position
			off.y = 0.0
			var tang: Vector3 = Vector3.UP.cross(off)
			if tang.length() < 0.01:
				tang = Vector3.RIGHT
			tang = tang.normalized() * signf(_speed)
			pl.launch(tang * 9.0 + off.normalized() * 2.0 + Vector3(0.0, 6.0, 0.0))
			_cool = 0.45
			Sfx.play("bounce", -4.0, 0.8)
