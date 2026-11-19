class_name Platforms
extends RefCounted
## Static and animated platforms. Each inner class has `world` and `setup(o: Dictionary)`.
## Level JSON: p = TOP-CENTRE of the platform, s = [width, thickness, depth], ry = yaw in degrees.


static func add_box(body: Node3D, s: Vector3, c: int, mat: Material = null) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bevel: float = clampf(minf(s.y, minf(s.x, s.z)) * 0.22, 0.03, 0.16)
	var surf: bool = mat == null or (mat is ShaderMaterial and (mat as ShaderMaterial).shader == Mats.shader("res://shaders/surface.gdshader"))
	mi.mesh = Geo.rounded_box(s, bevel, 2) if surf else Geo.box(s)
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
	var b: float = clampf(th * 0.22, 0.03, 0.15)
	var h: float = th * 0.5
	var prof := PackedVector2Array([Vector2(0.0, -h), Vector2(r - b, -h), Vector2(r - b * 0.3, -h + b * 0.3), Vector2(r, -h + b), Vector2(r, h - b), Vector2(r - b * 0.3, h - b * 0.3), Vector2(r - b, h), Vector2(0.0, h)])
	mi.mesh = Geo.lathe(prof, clampi(int(r * 10.0), 24, 64), "disc%.2f_%.2f" % [r, th])
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


## Hover thrusters under a moving platform (two glowing pods + a soft downward beam).
static func thrusters(body: Node3D, th: float, c: int) -> void:
	if Game.quality() == 0:
		return
	var col: Color = Mats.accent(c)
	for sx in [-0.6, 0.6]:
		var pod := Node3D.new()
		pod.position = Vector3(float(sx), -th * 0.5 - 0.15, 0.0)
		body.add_child(pod)
		Geo.put(pod, Geo.cyl(0.32, 0.42, 0.35, 14), Mats.metal(Color(0.25, 0.27, 0.32), 0.35, 0.8))
		Geo.put(pod, Geo.cyl(0.26, 0.26, 0.04, 14), Mats.glow(col, 3.0), Vector3(0.0, -0.18, 0.0), Vector3.ZERO, Vector3.ONE, false)
		var beam := MeshInstance3D.new()
		beam.mesh = Geo.cyl(0.1, 0.3, 1.6, 12)
		beam.material_override = Mats.beam(col, 1.6, 1.6, false, 0.7)
		beam.rotation_degrees = Vector3(180.0, 0.0, 0.0)
		beam.position = Vector3(0.0, -1.0, 0.0)
		beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		pod.add_child(beam)


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
		var ice: bool = bool(o.get("ice", false))
		if ice:
			set_meta("ice", true)
		if str(o.get("t", "box")) == "cyl":
			var r: float = float(o.get("r", 3.0))
			var th: float = float(o.get("th", 0.8))
			Platforms.add_cyl(self, r, th, c, Mats.platform(Vector3(r, th * 0.5, r), c, true, 0.0, true) if ice else null)
			position = top - Vector3(0.0, th * 0.5, 0.0)
		else:
			var s: Vector3 = LevelLoader.vec(o.get("s"), Vector3(4.0, 0.8, 4.0))
			Platforms.add_box(self, s, c, Mats.platform(s * 0.5, c, false, 0.0, true) if ice else null)
			position = top - Vector3(0.0, s.y * 0.5, 0.0)
			rotation_degrees.y = float(o.get("ry", 0.0))


# --------------------------------------------------------------- moving
class Moving extends AnimatableBody3D:
	var world: Node = null
	var _th: float = 0.8
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
		_th = th
		if o.has("r"):
			var r: float = float(o.get("r", 2.0))
			th = float(o.get("th", 0.8))
			Platforms.add_cyl(self, r, th, _c)
		else:
			var s: Vector3 = LevelLoader.vec(o.get("s"), Vector3(4.0, 0.8, 4.0))
			th = s.y
			Platforms.add_box(self, s, _c)
			rotation_degrees.y = float(o.get("ry", 0.0))
		_th = th
		_start = top - Vector3(0.0, th * 0.5, 0.0)
		position = _start
		_off = LevelLoader.vec(o.get("off"))
		_per = maxf(0.5, float(o.get("per", 4.0)))
		_ph = float(o.get("ph", 0.0))

	func _ready() -> void:
		var parent: Node = get_parent()
		if parent != null and _off.length() > 0.3:
			Platforms.make_line(parent, _start, _start + _off, 0.06, Mats.neon(Mats.accent(_c), 1.4, 1.0, 0.55, 0.5))
		Platforms.thrusters(self, _th, _c)

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
	var _size := Vector3.ONE

	func setup(o: Dictionary) -> void:
		collision_layer = 1
		collision_mask = 0
		var c: int = int(o.get("c", 3))
		var top: Vector3 = LevelLoader.vec(o.get("p"))
		var s: Vector3 = LevelLoader.vec(o.get("s"), Vector3(4.0, 0.7, 4.0))
		_half = s * 0.5
		_delay = float(o.get("delay", 0.6))
		_respawn = float(o.get("respawn", 3.0))
		_mi = Platforms.add_box(self, s, c, Mats.platform(s * 0.5, c, false, 1.0))
		_size = s
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
				Fx.burst(get_parent(), global_position + Vector3(0.0, 0.3, 0.0), Color(0.9, 0.8, 0.7, 0.9), 12, 4.0, 0.35, 0.8, -9.0)
				Debris.box_shatter(get_parent(), _mi.global_transform, _size, _mi.material_override, global_position + Vector3(0.0, 2.0, 0.0), 2.0, 7, 2.5)
				_mi.visible = false
		else:
			_timer -= delta
			if _timer <= 0.0 and not Platforms.player_inside(self, _half, pl):
				_state = 0
				_mi.position = Vector3.ZERO
				_mi.visible = true
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


# ------------------------------------------------------------- turntable
## Rotating disc (carries the player round). p = top centre, r, th, speed (rad/s, sign = direction).
## Optional "spokes": number of glowing radial stripes (shows the motion), "hole": inner gap radius (ring).
class Turntable extends AnimatableBody3D:
	var world: Node = null
	var _speed: float = 0.6
	var _ph: float = 0.0

	func setup(o: Dictionary) -> void:
		collision_layer = 1
		collision_mask = 0
		sync_to_physics = true
		var c: int = int(o.get("c", 1))
		var top: Vector3 = LevelLoader.vec(o.get("p"))
		var r: float = float(o.get("r", 4.0))
		var th: float = float(o.get("th", 0.8))
		_speed = float(o.get("speed", 0.6))
		_ph = float(o.get("ph", 0.0))
		Platforms.add_cyl(self, r, th, c)
		position = top - Vector3(0.0, th * 0.5, 0.0)
		var col: Color = Mats.accent(c)
		var n: int = int(o.get("spokes", 4))
		for i in range(n):
			var a: float = TAU * float(i) / float(n)
			Geo.put(self, Geo.box(Vector3(r * 0.8, 0.02, 0.18)), Mats.glow(col, 1.6), Vector3(cos(a) * r * 0.5, th * 0.5 + 0.012, sin(a) * r * 0.5), Vector3(0.0, -rad_to_deg(a), 0.0), Vector3.ONE, false)
		Geo.put(self, Geo.cyl(0.6, 0.6, 0.06, 20), Mats.glow(col, 2.2), Vector3(0.0, th * 0.5 + 0.02, 0.0), Vector3.ZERO, Vector3.ONE, false)
		var hub := Node3D.new()
		hub.position = Vector3(0.0, -th * 0.5, 0.0)
		add_child(hub)
		Geo.put(hub, Geo.cyl(r * 0.25, r * 0.12, 1.6, 20), Mats.metal(Color(0.25, 0.27, 0.32), 0.35, 0.8), Vector3(0.0, -0.8, 0.0))
		Geo.put(hub, Geo.torus(r * 0.2, r * 0.26, 24, 5), Mats.glow(col, 2.4), Vector3(0.0, -1.4, 0.0), Vector3.ZERO, Vector3.ONE, false)

	func _physics_process(_delta: float) -> void:
		if world == null:
			return
		rotation.y = _ph + float(world.time) * _speed


# --------------------------------------------------------------- retract
## Bridge slab that slides sideways into its housing on a timer. p = top centre when extended, s = size,
## ry = yaw, on / off = seconds extended / retracted, ph = phase 0..1, side = +1 / -1 (housing to the
## right / left of the path).
class Retract extends AnimatableBody3D:
	var world: Node = null
	var _on: float = 2.5
	var _off: float = 1.5
	var _ph: float = 0.0
	var _ext := Vector3.ZERO
	var _dir := Vector3.ZERO
	var _len: float = 4.0
	var _k: float = 1.0
	var _mi: MeshInstance3D
	var _mat: ShaderMaterial
	var _warn_mat: StandardMaterial3D
	var _lamp: MeshInstance3D
	var _was_out: bool = true
	var _sz := Vector3.ONE

	func setup(o: Dictionary) -> void:
		collision_layer = 1
		collision_mask = 0
		sync_to_physics = true
		var c: int = int(o.get("c", 2))
		var top: Vector3 = LevelLoader.vec(o.get("p"))
		var s: Vector3 = LevelLoader.vec(o.get("s"), Vector3(3.0, 0.5, 4.0))
		_on = float(o.get("on", 2.5))
		_off = float(o.get("off", 1.5))
		_ph = float(o.get("ph", 0.0))
		_len = s.x + 0.3
		_sz = s
		var ry: float = float(o.get("ry", 0.0))
		rotation_degrees.y = ry
		_mi = Platforms.add_box(self, s, c)
		_ext = top - Vector3(0.0, s.y * 0.5, 0.0)
		position = _ext
		_dir = Basis(Vector3.UP, deg_to_rad(ry)) * Vector3(float(o.get("side", 1.0)), 0.0, 0.0)
		_warn_mat = StandardMaterial3D.new()
		_warn_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_warn_mat.albedo_color = Color(0.3, 2.0, 1.0)
		_lamp = Geo.put(self, Geo.box(Vector3(0.2, 0.04, s.z * 0.8)), _warn_mat, Vector3(0.0, s.y * 0.5 + 0.02, 0.0), Vector3.ZERO, Vector3.ONE, false)

	func _ready() -> void:
		# housing at the +Z end (static)
		var parent: Node = get_parent()
		if parent == null:
			return
		var house := MeshInstance3D.new()
		var sz := Vector3(_sz.x + 0.6, 1.2, _sz.z + 0.4)
		house.mesh = Geo.rounded_box(sz, 0.2, 2)
		house.material_override = Mats.metal(Color(0.22, 0.24, 0.3), 0.35, 0.8)
		house.transform = Transform3D(Basis(Vector3.UP, rotation.y), _ext + _dir * (_len + 0.15) + Vector3(0.0, -_sz.y * 0.5 - 0.66, 0.0))
		parent.add_child.call_deferred(house)

	func _physics_process(delta: float) -> void:
		if world == null:
			return
		var cyc: float = maxf(_on + _off, 0.1)
		var t: float = fposmod(float(world.time) + _ph * cyc, cyc)
		var out: bool = t < _on
		var warn: bool = out and t > _on - 0.8
		var target: float = 1.0 if out else 0.0
		_k = move_toward(_k, target, delta * (5.0 if out else 4.0))
		position = _ext + _dir * _len * (1.0 - _k)
		var blink: bool = warn and int(t * 10.0) % 2 == 0
		_warn_mat.albedo_color = Color(2.4, 0.4, 0.3) if blink else (Color(0.3, 2.0, 1.0) if out else Color(0.6, 0.2, 0.2))
		if out != _was_out:
			_was_out = out
			Sfx.play("retract", -10.0, 1.1 if out else 0.9)


# -------------------------------------------------------------- pendulum
## Platform hanging from a pivot, swinging in a vertical plane. p = top centre at rest (lowest point),
## len = rope length, amp = swing angle (deg), per, ph, dir = heading of the swing plane (deg), s = slab size.
class Pendulum extends AnimatableBody3D:
	var world: Node = null
	var _pivot := Vector3.ZERO
	var _len: float = 6.0
	var _amp: float = 0.6
	var _per: float = 3.0
	var _ph: float = 0.0
	var _axis := Vector3.RIGHT
	var _th: float = 0.6
	var _rope: MeshInstance3D

	func setup(o: Dictionary) -> void:
		collision_layer = 1
		collision_mask = 0
		sync_to_physics = true
		var c: int = int(o.get("c", 1))
		var top: Vector3 = LevelLoader.vec(o.get("p"))
		var s: Vector3 = LevelLoader.vec(o.get("s"), Vector3(3.0, 0.6, 3.0))
		_th = s.y
		_len = float(o.get("len", 6.0))
		_amp = deg_to_rad(float(o.get("amp", 35.0)))
		_per = maxf(0.5, float(o.get("per", 3.0)))
		_ph = float(o.get("ph", 0.0))
		_axis = Zones.heading_vec(float(o.get("dir", 90.0)))
		_pivot = top + Vector3(0.0, _len, 0.0)
		var ice: bool = bool(o.get("ice", false))
		if ice:
			set_meta("ice", true)
		Platforms.add_box(self, s, c, Mats.platform(s * 0.5, c, false, 0.0, true) if ice else null)
		position = top - Vector3(0.0, _th * 0.5, 0.0)
		for sx in [-1.0, 1.0]:
			Geo.put(self, Geo.cyl(0.12, 0.12, 0.3, 8), Mats.metal(Color(0.3, 0.3, 0.35), 0.35, 0.9), Vector3(float(sx) * s.x * 0.3, _th * 0.5 + 0.15, 0.0))

	func _ready() -> void:
		var parent: Node = get_parent()
		if parent == null:
			return
		_rope = MeshInstance3D.new()
		_rope.mesh = Geo.cyl(0.06, 0.06, 1.0, 8)
		_rope.material_override = Mats.metal(Color(0.5, 0.52, 0.58), 0.3, 0.9)
		_rope.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		parent.add_child.call_deferred(_rope)
		var hub := MeshInstance3D.new()
		hub.mesh = Geo.sphere(0.45, 14)
		hub.material_override = Mats.metal(Color(0.25, 0.27, 0.32), 0.35, 0.8)
		hub.position = _pivot
		parent.add_child.call_deferred(hub)

	func _physics_process(_delta: float) -> void:
		if world == null:
			return
		var a: float = _amp * sin(TAU * (float(world.time) / _per + _ph))
		var off: Vector3 = _axis * sin(a) * _len + Vector3(0.0, -cos(a) * _len, 0.0)
		position = _pivot + off - Vector3(0.0, _th * 0.5, 0.0)
		if _rope != null and _rope.is_inside_tree():
			var top_pt: Vector3 = position + Vector3(0.0, _th * 0.5, 0.0)
			var l: float = maxf(_pivot.distance_to(top_pt), 0.1)
			_rope.global_transform = Transform3D(Platforms.basis_y(_pivot - top_pt) * Basis.from_scale(Vector3(1.0, l, 1.0)), (_pivot + top_pt) * 0.5)


# ------------------------------------------------------------------ drum
## Rolling log: a horizontal cylinder whose top surface moves (keep running or be carried off).
## p = top line centre, r = radius, len = length along its axis, ry = yaw of the axis, spd = surface speed
## (m/s, positive = moves toward heading ry - 90).
class Drum extends StaticBody3D:
	var world: Node = null
	var _vel := Vector3.ZERO
	var _spin: Node3D
	var _r: float = 1.5
	var _spd: float = 3.0
	var _area: Area3D

	func setup(o: Dictionary) -> void:
		collision_layer = 1
		collision_mask = 0
		var c: int = int(o.get("c", 0))
		var top: Vector3 = LevelLoader.vec(o.get("p"))
		_r = float(o.get("r", 1.5))
		var length: float = float(o.get("len", 6.0))
		_spd = float(o.get("spd", 3.0))
		var ry: float = float(o.get("ry", 0.0))
		rotation_degrees.y = ry
		position = top - Vector3(0.0, _r, 0.0)
		var cs := CollisionShape3D.new()
		var cy := CylinderShape3D.new()
		cy.radius = _r
		cy.height = length
		cs.shape = cy
		cs.rotation_degrees = Vector3(0.0, 0.0, 90.0)
		add_child(cs)
		_spin = Node3D.new()
		add_child(_spin)
		var ice: bool = bool(o.get("ice", false))
		if ice:
			set_meta("ice", true)
		var log_mat: Material = Mats.platform(Vector3(_r, length * 0.5, _r), c, true, 0.0, ice)
		Geo.put(_spin, Geo.cyl(_r, _r, length, 40), log_mat, Vector3.ZERO, Vector3(0.0, 0.0, 90.0))
		for i in range(8):
			var a: float = TAU * float(i) / 8.0
			Geo.put(_spin, Geo.box(Vector3(length * 0.98, 0.08, 0.25)), Mats.glow(Mats.accent(c), 1.4), Vector3(0.0, cos(a) * (_r + 0.01), sin(a) * (_r + 0.01)), Vector3(rad_to_deg(a), 0.0, 0.0), Vector3.ONE, false)
		for sx in [-1.0, 1.0]:
			Geo.put(self, Geo.cyl(_r * 0.5, _r * 0.5, 0.6, 20), Mats.metal(Color(0.25, 0.27, 0.32), 0.35, 0.8), Vector3(float(sx) * (length * 0.5 + 0.3), 0.0, 0.0), Vector3(0.0, 0.0, 90.0))
		var fwd: Vector3 = Basis(Vector3.UP, deg_to_rad(ry)) * Vector3(0.0, 0.0, -1.0)
		_vel = fwd * _spd
		_area = Area3D.new()
		_area.collision_layer = 0
		_area.collision_mask = 2
		var acs := CollisionShape3D.new()
		var abs_ := BoxShape3D.new()
		abs_.size = Vector3(length, 0.6, _r * 1.4)
		acs.shape = abs_
		acs.position = Vector3(0.0, _r + 0.2, 0.0)
		_area.add_child(acs)
		add_child(_area)

	func _physics_process(delta: float) -> void:
		_spin.rotate_x(-_spd / _r * delta)
		var pl: Player = Zones.player_of(world)
		if pl != null and pl.is_on_floor() and _area.overlaps_body(pl):
			pl.mark_conveyor(_vel)


# ---------------------------------------------------------------- toggle
## Jump-switch platform: two sets (0 / 1) swap solid <-> hologram every time the robot jumps.
class Toggle extends StaticBody3D:
	var world: Node = null
	var _set: int = 0
	var _solid: bool = true
	var _fade: float = 1.0
	var _half := Vector3.ONE
	var _mat: ShaderMaterial

	func setup(o: Dictionary) -> void:
		collision_layer = 1
		collision_mask = 0
		_set = int(o.get("set", 0))
		var top: Vector3 = LevelLoader.vec(o.get("p"))
		var s: Vector3 = LevelLoader.vec(o.get("s"), Vector3(3.0, 0.5, 3.0))
		_half = s * 0.5
		var col: Color = Color(1.0, 0.35, 0.75) if _set == 0 else Color(0.25, 0.85, 1.0)
		_mat = ShaderMaterial.new()
		_mat.shader = Mats.shader("res://shaders/ghost.gdshader")
		_mat.set_shader_parameter("half_size", _half)
		_mat.set_shader_parameter("edge_color", col)
		Platforms.add_box(self, s, 0, _mat)
		position = top - Vector3(0.0, s.y * 0.5, 0.0)
		rotation_degrees.y = float(o.get("ry", 0.0))
		var mark := Geo.put(self, Geo.cyl(0.45, 0.45, 0.04, 6 if _set == 0 else 24), Mats.glow(col, 2.2), Vector3(0.0, s.y * 0.5 + 0.03, 0.0), Vector3.ZERO, Vector3.ONE, false)
		mark.name = "mark"

	func _physics_process(delta: float) -> void:
		if world == null:
			return
		var want: bool = int(world.get("toggle_state")) == _set
		if want and not _solid:
			var pl: Player = world.player
			if pl != null and is_instance_valid(pl) and Platforms.player_inside(self, _half, pl):
				want = false
		if want != _solid:
			_solid = want
			collision_layer = 1 if _solid else 0
		_fade = move_toward(_fade, 1.0 if _solid else 0.18, delta * 8.0)
		_mat.set_shader_parameter("fade", _fade)


# ------------------------------------------------------------------ lift
## Elevator: waits for the robot to stand on it, then travels by `off` over `dur` seconds, waits and returns.
class Lift extends AnimatableBody3D:
	var world: Node = null
	var _start := Vector3.ZERO
	var _off := Vector3.ZERO
	var _dur: float = 3.0
	var _k: float = 0.0
	var _state: int = 0
	var _t: float = 0.0
	var _area: Area3D
	var _lamp: StandardMaterial3D

	func setup(o: Dictionary) -> void:
		collision_layer = 1
		collision_mask = 0
		sync_to_physics = true
		var c: int = int(o.get("c", 3))
		var top: Vector3 = LevelLoader.vec(o.get("p"))
		var s: Vector3 = LevelLoader.vec(o.get("s"), Vector3(4.0, 0.8, 4.0))
		_off = LevelLoader.vec(o.get("off"), Vector3(0.0, 10.0, 0.0))
		_dur = maxf(0.5, float(o.get("dur", 3.0)))
		Platforms.add_box(self, s, c)
		_start = top - Vector3(0.0, s.y * 0.5, 0.0)
		position = _start
		rotation_degrees.y = float(o.get("ry", 0.0))
		_lamp = StandardMaterial3D.new()
		_lamp.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_lamp.albedo_color = Color(1.0, 0.8, 0.2) * 2.0
		Geo.put(self, Geo.torus(0.5, 0.65, 24, 5), _lamp, Vector3(0.0, s.y * 0.5 + 0.02, 0.0), Vector3.ZERO, Vector3.ONE, false)
		Platforms.thrusters(self, s.y, c)
		_area = Area3D.new()
		_area.collision_layer = 0
		_area.collision_mask = 2
		var cs := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = Vector3(s.x * 0.9, 0.6, s.z * 0.9)
		cs.shape = bs
		cs.position = Vector3(0.0, s.y * 0.5 + 0.3, 0.0)
		_area.add_child(cs)
		add_child(_area)

	func _ready() -> void:
		var parent: Node = get_parent()
		if parent != null:
			Platforms.make_line(parent, _start, _start + _off, 0.07, Mats.neon(Color(1.0, 0.8, 0.3), 1.4, 1.0, 0.55, 0.5))

	func _physics_process(delta: float) -> void:
		var pl: Player = Zones.player_of(world)
		var on: bool = pl != null and _area.overlaps_body(pl)
		_t += delta
		if _state == 0:
			if on:
				_t += 0.0
				if _t > 0.35:
					_state = 1
					Sfx.play("lift", -6.0)
			else:
				_t = 0.0
		elif _state == 1:
			_k = minf(_k + delta / _dur, 1.0)
			if _k >= 1.0:
				_state = 2
				_t = 0.0
		elif _state == 2:
			if not on and _t > 1.5:
				_state = 3
		else:
			if on:
				_state = 1
			else:
				_k = maxf(_k - delta / (_dur * 1.3), 0.0)
				if _k <= 0.0:
					_state = 0
					_t = 0.0
		var e: float = _k * _k * (3.0 - 2.0 * _k)
		position = _start + _off * e
		_lamp.albedo_color = (Color(0.3, 1.0, 0.5) if _state == 1 else Color(1.0, 0.8, 0.2)) * 2.0


# --------------------------------------------------------------- crusher
## Hydraulic press: a heavy block that rises slowly, shakes, then slams onto the floor below it. Its top is
## a moving platform. p = floor point under the block, s = block size, h = raised height of its bottom,
## per = cycle (s), ph = phase 0..1.
class Crusher extends AnimatableBody3D:
	var world: Node = null
	var _floor := Vector3.ZERO
	var _s := Vector3(3.0, 2.0, 3.0)
	var _h: float = 4.0
	var _per: float = 3.5
	var _ph: float = 0.0
	var _y: float = 0.0
	var _prev_phase: int = -1
	var _vis: Node3D
	var _warn: StandardMaterial3D
	var _hit_cd: float = 0.0

	func setup(o: Dictionary) -> void:
		collision_layer = 1
		collision_mask = 0
		sync_to_physics = true
		_floor = LevelLoader.vec(o.get("p"))
		_s = LevelLoader.vec(o.get("s"), Vector3(3.0, 2.0, 3.0))
		_h = float(o.get("h", 4.0))
		_per = maxf(1.5, float(o.get("per", 3.5)))
		_ph = float(o.get("ph", 0.0))
		rotation_degrees.y = float(o.get("ry", 0.0))
		var cs := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = _s
		cs.shape = bs
		add_child(cs)
		_vis = Node3D.new()
		add_child(_vis)
		Geo.put(_vis, Geo.rounded_box(_s, 0.12, 2), Mats.metal(Color(0.35, 0.33, 0.33), 0.45, 0.85))
		Geo.put(_vis, Geo.rounded_box(Vector3(_s.x + 0.06, 0.3, _s.z + 0.06), 0.05, 2), Mats.metal(Color(0.9, 0.62, 0.1), 0.4, 0.5), Vector3(0.0, _s.y * 0.5 - 0.25, 0.0))
		_warn = StandardMaterial3D.new()
		_warn.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_warn.albedo_color = Color(1.0, 0.3, 0.2)
		Geo.put(_vis, Geo.box(Vector3(_s.x * 0.95, 0.08, _s.z * 0.95)), _warn, Vector3(0.0, -_s.y * 0.5 - 0.03, 0.0), Vector3.ZERO, Vector3.ONE, false)
		for sx in [-1.0, 1.0]:
			for sz in [-1.0, 1.0]:
				Geo.put(_vis, Geo.cyl(0.12, 0.12, 0.4, 8), Mats.metal(Color(0.15, 0.15, 0.18), 0.3, 0.9), Vector3(float(sx) * _s.x * 0.4, -_s.y * 0.5 - 0.15, float(sz) * _s.z * 0.4))
		_y = _h
		position = _floor + Vector3(0.0, _y + _s.y * 0.5, 0.0)

	func _ready() -> void:
		var parent: Node = get_parent()
		if parent == null:
			return
		var piston := MeshInstance3D.new()
		var ph: float = 12.0
		piston.mesh = Geo.cyl(0.45, 0.45, ph, 14)
		piston.material_override = Mats.metal(Color(0.7, 0.72, 0.78), 0.2, 1.0)
		piston.position = _floor + Vector3(0.0, _h + _s.y + ph * 0.5, 0.0)
		parent.add_child.call_deferred(piston)
		var mark := MeshInstance3D.new()
		mark.mesh = Geo.box(Vector3(_s.x, 0.02, _s.z))
		mark.material_override = Mats.chevron(Color(1.0, 0.35, 0.2), 0.6, 2.0)
		mark.transform = Transform3D(Basis(Vector3.UP, rotation.y), _floor + Vector3(0.0, 0.03, 0.0))
		mark.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		parent.add_child.call_deferred(mark)

	func _physics_process(delta: float) -> void:
		if world == null:
			return
		_hit_cd = maxf(_hit_cd - delta, 0.0)
		var t: float = fposmod(float(world.time) / _per + _ph, 1.0)
		# 0..0.45 rest high, 0.45..0.6 shake, 0.6..0.66 slam, 0.66..0.8 down, 0.8..1 rise
		var phase: int = 0
		var y: float = _h
		if t < 0.45:
			y = _h
		elif t < 0.6:
			phase = 1
			y = _h
		elif t < 0.66:
			phase = 2
			var k: float = (t - 0.6) / 0.06
			y = _h * (1.0 - k * k)
		elif t < 0.8:
			phase = 3
			y = 0.0
		else:
			phase = 4
			var k2: float = (t - 0.8) / 0.2
			y = _h * k2 * k2 * (3.0 - 2.0 * k2)
		_vis.position = Vector3(randf_range(-1.0, 1.0), 0.0, randf_range(-1.0, 1.0)) * 0.04 if phase == 1 else Vector3.ZERO
		_warn.albedo_color = Color(3.0, 0.6, 0.3) if (phase == 1 and int(t * 60.0) % 2 == 0) or phase == 2 else Color(0.8, 0.2, 0.15)
		if phase == 3 and _prev_phase == 2:
			Sfx.play("crusher", -2.0, randf_range(0.9, 1.05))
			Fx.burst(get_parent(), _floor + Vector3(0.0, 0.2, 0.0), Color(0.8, 0.75, 0.7, 0.7), 16, 6.0, 0.6, 0.6, 0.0, 85.0)
			var pl0: Player = Zones.player_of(world)
			if pl0 != null and pl0.global_position.distance_to(_floor) < 9.0:
				world.shake(0.35)
		if phase == 1 and _prev_phase == 0:
			Sfx.play("crusher_warn", -10.0)
		_prev_phase = phase
		var prev_y: float = _y
		_y = y
		# squash check: robot under the block while it is coming down
		var pl: Player = Zones.player_of(world)
		if pl != null and _hit_cd <= 0.0 and _y < prev_y - 0.01:
			var lp: Vector3 = to_local(pl.global_position)
			var bottom_y: float = _floor.y + _y
			if absf(lp.x) < _s.x * 0.5 + 0.3 and absf(lp.z) < _s.z * 0.5 + 0.3 and pl.global_position.y < bottom_y and pl.global_position.y + 1.1 > bottom_y - 0.6:
				_hit_cd = 1.0
				pl.hurt(_floor, 1)
				var out: Vector3 = Vector3(lp.x, 0.0, lp.z)
				if out.length() < 0.1:
					out = Vector3(1.0, 0.0, 0.0)
				var ax: Vector3 = Vector3(signf(out.x), 0.0, 0.0) if absf(out.x) / _s.x > absf(out.z) / _s.z else Vector3(0.0, 0.0, signf(out.z))
				pl.launch(global_transform.basis * ax * 11.0 + Vector3(0.0, 6.0, 0.0))
		position = _floor + Vector3(0.0, _y + _s.y * 0.5, 0.0)
