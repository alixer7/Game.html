class_name Puzzles
extends RefCounted
## Puzzle pieces. They all talk through GameWorld's switch ids (activate_switch / is_switch_on), so a
## puzzle can open a gate, raise a hologram bridge (ghost mode "switch") or anything else listening.
##   pylons  - memory sequence: watch the pylons light up, then hit them in the same order
##   block   - heavy physics crate you punch around (slides, falls, respawns)
##   plate   - pressure plate held down by the block (or the robot)
##   gate    - energy door, open while its switch is on
##   targets - hit every target before the timer runs out
##   wall    - breakable wall (crystal / ice / metal) hiding secrets


# ----------------------------------------------------------------- pylons
class Pylons extends Node3D:
	var world: Node = null
	var id: String = "P"
	var _pts: Array = []
	var _seq: Array = []
	var _pylons: Array = []
	var _state: int = 0
	var _t: float = 0.0
	var _show_i: int = 0
	var _input_i: int = 0
	var _r: float = 7.0
	var _done: bool = false
	const TONES := [0.8, 1.0, 1.2, 1.4, 1.6, 1.8]
	const COLS := [Color(1.0, 0.35, 0.5), Color(0.3, 0.9, 1.0), Color(1.0, 0.85, 0.3), Color(0.5, 1.0, 0.5), Color(0.8, 0.5, 1.0), Color(1.0, 0.6, 0.25)]

	func setup(o: Dictionary) -> void:
		position = LevelLoader.vec(o.get("p"))
		id = str(o.get("id", "P"))
		_r = float(o.get("r", 7.0))
		var pts: Array = o.get("pts", [])
		for p in pts:
			_pts.append(LevelLoader.vec(p))
		var seq: Array = o.get("seq", [])
		for s in seq:
			_seq.append(int(s))
		if _seq.is_empty():
			for i in range(_pts.size()):
				_seq.append(i)
		for i in range(_pts.size()):
			var py := Pylon.new()
			py.owner_puzzle = self
			py.idx = i
			py.col = COLS[i % COLS.size()]
			add_child(py)
			py.position = (_pts[i] as Vector3) - position
			_pylons.append(py)
		var orb := Geo.put(self, Geo.sphere(0.5, 18), Mats.neon(Color(0.7, 0.9, 1.0), 2.0, 1.2, 0.5), Vector3(0.0, 2.5, 0.0), Vector3.ZERO, Vector3.ONE, false)
		orb.name = "orb"
		add_to_group("pylon_puzzle")

	func _physics_process(delta: float) -> void:
		if world == null or _done:
			return
		_t += delta
		var orb: Node3D = get_node("orb")
		orb.position.y = 2.5 + sin(_t * 2.0) * 0.15
		var pl: Player = Zones.player_of(world)
		var near: bool = pl != null and pl.global_position.distance_to(global_position) < _r
		if _state == 0:
			if near:
				_state = 1
				_t = -0.6
				_show_i = 0
				world.hint("راقب ترتيب الأعمدة المضيئة ثم اضربها بنفس الترتيب")
		elif _state == 1:
			# playing the sequence
			if _t >= 0.8:
				_t = 0.0
				if _show_i < _seq.size():
					var py: Pylon = _pylons[int(_seq[_show_i])]
					py.flash(0.55)
					Sfx.play("pylon", -2.0, float(TONES[int(_seq[_show_i]) % TONES.size()]))
					_show_i += 1
				else:
					_state = 2
					_input_i = 0
					for p in _pylons:
						(p as Pylon).armed = true
		elif _state == 2:
			if not near and pl != null and pl.global_position.distance_to(global_position) > _r + 8.0:
				_reset(false)
		elif _state == 3:
			if _t > 1.2:
				_state = 1
				_t = 0.0
				_show_i = 0

	func on_hit(i: int) -> void:
		if _state != 2:
			return
		var py: Pylon = _pylons[i]
		if int(_seq[_input_i]) == i:
			py.set_lit(true)
			Sfx.play("pylon", 0.0, float(TONES[i % TONES.size()]))
			_input_i += 1
			if _input_i >= _seq.size():
				_solve()
		else:
			Sfx.play("wrong", 0.0)
			world.toast("ترتيب خاطئ! راقب مرة أخرى", Color(1.0, 0.4, 0.4))
			for p in _pylons:
				(p as Pylon).fail()
			_reset(true)

	func _reset(replay: bool) -> void:
		for p in _pylons:
			var pp: Pylon = p
			pp.armed = false
			pp.set_lit(false)
		_state = 3 if replay else 0
		_t = 0.0

	func _solve() -> void:
		_done = true
		_state = 4
		for p in _pylons:
			(p as Pylon).armed = false
		world.activate_switch(id, 0.0)
		Sfx.play("puzzle_solved", 0.0)
		world.toast("أحسنت! تم حل اللغز", Color(0.4, 1.0, 0.6))
		Fx.ring(get_parent(), global_position, Color(0.5, 1.0, 0.7), 14.0, 0.8, 3.0)
		var orb: Node3D = get_node("orb")
		Fx.burst(get_parent(), orb.global_position, Color(0.6, 1.0, 0.7), 30, 8.0, 0.4, 0.8, -3.0)
		orb.visible = false
		Debris.spray(get_parent(), world, orb.global_position, 6, "gem", 1.0, 5.0)


class Pylon extends Node3D:
	var owner_puzzle: Pylons
	var idx: int = 0
	var col := Color.WHITE
	var armed: bool = false
	var hit_radius: float = 0.8
	var hit_offset := Vector3(0.0, 1.2, 0.0)
	var _mat: StandardMaterial3D
	var _lit: bool = false
	var _flash: float = 0.0
	var _fail: float = 0.0
	var _cd: float = 0.0
	var _cap: Node3D

	func _ready() -> void:
		Geo.put(self, Geo.lathe(PackedVector2Array([Vector2(0.0, 0.0), Vector2(0.65, 0.0), Vector2(0.6, 0.25), Vector2(0.38, 0.4), Vector2(0.34, 1.7), Vector2(0.0, 1.7)]), 16, "pylon_body"), Mats.metal(Color(0.2, 0.2, 0.26), 0.35, 0.8))
		_mat = StandardMaterial3D.new()
		_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_mat.albedo_color = col * 0.35
		_cap = Node3D.new()
		_cap.position = Vector3(0.0, 2.05, 0.0)
		add_child(_cap)
		Geo.put(_cap, Geo.crystal(0.32, 0.4, 0.35, 6), _mat, Vector3(0.0, -0.25, 0.0), Vector3.ZERO, Vector3.ONE, false)
		Geo.put(_cap, Geo.crystal(0.32, 0.25, 0.3, 6), _mat, Vector3(0.0, -0.2, 0.0), Vector3(180.0, 0.0, 0.0), Vector3.ONE, false)
		Geo.put(self, Geo.torus(0.42, 0.5, 20, 4), _mat, Vector3(0.0, 1.0, 0.0), Vector3.ZERO, Vector3.ONE, false)
		add_to_group("hittable")

	func _process(delta: float) -> void:
		_flash = maxf(_flash - delta, 0.0)
		_fail = maxf(_fail - delta, 0.0)
		_cd = maxf(_cd - delta, 0.0)
		_cap.rotation.y += delta * (3.0 if _lit or _flash > 0.0 else 0.6)
		var k: float = 0.35
		var c: Color = col
		if _lit:
			k = 2.6
		if _flash > 0.0:
			k = 3.2
		if _fail > 0.0:
			c = Color(1.0, 0.15, 0.15)
			k = 2.5 if int(_fail * 12.0) % 2 == 0 else 0.3
		if armed and not _lit and _flash <= 0.0 and _fail <= 0.0:
			k = 0.6 + 0.25 * sin(Time.get_ticks_msec() * 0.006 + float(idx))
		_mat.albedo_color = c * k
		_cap.scale = Vector3.ONE * (1.0 + (0.25 if _flash > 0.0 else 0.0))

	func flash(d: float) -> void:
		_flash = d

	func fail() -> void:
		_fail = 0.8

	func set_lit(v: bool) -> void:
		_lit = v
		if v:
			Fx.burst(get_parent(), global_position + Vector3(0.0, 2.0, 0.0), col, 10, 4.0, 0.3, 0.4)

	func hit(_by: Node, _kind: String) -> bool:
		if not armed or _lit or _cd > 0.0:
			return false
		_cd = 0.3
		owner_puzzle.on_hit(idx)
		return true


# ------------------------------------------------------------------ block
## Heavy crate you can punch around (slides with friction; falls off edges and comes back). p = floor pos.
class PushBlock extends RigidBody3D:
	var world: Node = null
	var hit_radius: float = 1.0
	var hit_offset := Vector3.ZERO
	var _home := Vector3.ZERO
	var _size: float = 1.6

	func setup(o: Dictionary) -> void:
		_size = float(o.get("size", 1.6))
		_home = LevelLoader.vec(o.get("p")) + Vector3(0.0, _size * 0.5 + 0.02, 0.0)
		position = _home
		collision_layer = 1
		collision_mask = 1 | 16
		mass = 30.0
		axis_lock_angular_x = true
		axis_lock_angular_z = true
		axis_lock_angular_y = true
		linear_damp = 0.5
		var pm := PhysicsMaterial.new()
		pm.friction = 0.3
		pm.bounce = 0.0
		physics_material_override = pm
		var cs := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = Vector3(_size, _size, _size)
		cs.shape = bs
		add_child(cs)
		var steel: Material = Mats.metal(Color(0.35, 0.37, 0.42), 0.4, 0.85)
		Geo.put(self, Geo.rounded_box(Vector3(_size, _size, _size), 0.12, 2), steel)
		var acc: Material = Mats.glow(Color(1.0, 0.75, 0.25), 2.2)
		for ax in range(3):
			for sg in [-1.0, 1.0]:
				var rot := Vector3.ZERO
				var pp := Vector3.ZERO
				pp[ax] = float(sg) * (_size * 0.5 + 0.005)
				if ax == 0:
					rot = Vector3(0.0, 0.0, 90.0)
				elif ax == 2:
					rot = Vector3(90.0, 0.0, 0.0)
				Geo.put(self, Geo.cyl(_size * 0.3, _size * 0.3, 0.01, 4), acc, pp, rot + Vector3(0.0, 45.0, 0.0), Vector3.ONE, false)
		add_to_group("hittable")
		add_to_group("push_block")

	func _physics_process(_delta: float) -> void:
		if world == null:
			return
		if global_position.y < float(world.get("_kill_y")) + 5.0:
			_respawn()

	func _respawn() -> void:
		linear_velocity = Vector3.ZERO
		global_position = _home + Vector3(0.0, 2.0, 0.0)
		Fx.ring(get_parent(), _home, Color(1.0, 0.75, 0.3), 3.0, 0.5, 3.0)
		Sfx.play("warp", -6.0)

	func hit(by: Node, kind: String) -> bool:
		if not (by is Node3D):
			return false
		var d: Vector3 = global_position - (by as Node3D).global_position
		d.y = 0.0
		if d.length() < 0.01:
			return false
		# snap the shove to the dominant axis so the block lines up with plates
		var ax := Vector3(signf(d.x), 0.0, 0.0) if absf(d.x) > absf(d.z) else Vector3(0.0, 0.0, signf(d.z))
		var power: float = 9.0 if kind == "punch3" or kind == "spin_big" else 6.5
		apply_central_impulse(ax * power * mass)
		Sfx.play("block_push", -2.0, randf_range(0.9, 1.05))
		Fx.burst(get_parent(), global_position - ax * _size * 0.5, Color(1.0, 0.85, 0.5), 8, 4.0, 0.25, 0.3)
		return true


# ------------------------------------------------------------------ plate
## Pressure plate. Held down by a push block (or the robot when `robot` is true). mode "hold" / "latch".
class Plate extends Area3D:
	var world: Node = null
	var _id: String = "A"
	var _robot: bool = false
	var _latch: bool = false
	var _on: bool = false
	var _btn: MeshInstance3D
	var _mat: StandardMaterial3D
	var _done: bool = false

	func setup(o: Dictionary) -> void:
		position = LevelLoader.vec(o.get("p"))
		_id = str(o.get("id", "A"))
		_robot = bool(o.get("robot", false))
		_latch = str(o.get("mode", "hold")) == "latch"
		collision_layer = 0
		collision_mask = 1 | 2
		var cs := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = Vector3(1.6, 0.8, 1.6)
		cs.shape = bs
		cs.position = Vector3(0.0, 0.4, 0.0)
		add_child(cs)
		Geo.put(self, Geo.rounded_box(Vector3(2.2, 0.12, 2.2), 0.04, 2), Mats.metal(Color(0.2, 0.2, 0.25), 0.4, 0.8), Vector3(0.0, 0.06, 0.0))
		_mat = StandardMaterial3D.new()
		_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_mat.albedo_color = Color(1.0, 0.6, 0.2) * 1.6
		_btn = Geo.put(self, Geo.rounded_box(Vector3(1.7, 0.12, 1.7), 0.04, 2), _mat, Vector3(0.0, 0.16, 0.0), Vector3.ZERO, Vector3.ONE, false)
		var mark := Geo.put(self, Geo.box(Vector3(2.4, 0.02, 2.4)), Mats.chevron(Color(1.0, 0.7, 0.3), 0.8, 2.0), Vector3(0.0, 0.02, 0.0), Vector3.ZERO, Vector3.ONE, false)
		mark.name = "mark"

	func _physics_process(_delta: float) -> void:
		if world == null:
			return
		var pressed: bool = false
		for b in get_overlapping_bodies():
			if b is PushBlock:
				pressed = true
				break
			if _robot and b is Player:
				pressed = true
				break
		if _done:
			pressed = true
		if pressed:
			world.activate_switch(_id, 0.25)
			if _latch:
				_done = true
				world.activate_switch(_id, 0.0)
		if pressed != _on:
			_on = pressed
			Sfx.play("switch", -2.0, 1.0 if pressed else 0.8)
			if pressed:
				Fx.ring(self, global_position, Color(0.4, 1.0, 0.6), 4.0, 0.5, 3.0)
		_btn.position.y = 0.09 if _on else 0.16
		_mat.albedo_color = (Color(0.3, 1.0, 0.5) if _on else Color(1.0, 0.6, 0.2)) * 1.6


# ------------------------------------------------------------------- gate
## Energy door: solid until its switch id is on. p = floor centre, w = width, h = height, ry = yaw.
class Gate extends StaticBody3D:
	var world: Node = null
	var _id: String = "A"
	var _open: float = 0.0
	var _curtain: MeshInstance3D
	var _mat: ShaderMaterial
	var _cs: CollisionShape3D
	var _was: bool = false

	func setup(o: Dictionary) -> void:
		position = LevelLoader.vec(o.get("p"))
		rotation_degrees.y = float(o.get("ry", 0.0))
		_id = str(o.get("id", "A"))
		var w: float = float(o.get("w", 5.0))
		var h: float = float(o.get("h", 4.0))
		collision_layer = 1
		collision_mask = 0
		_cs = CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = Vector3(w, h, 0.5)
		_cs.shape = bs
		_cs.position = Vector3(0.0, h * 0.5, 0.0)
		add_child(_cs)
		var post: Material = Mats.metal(Color(0.22, 0.22, 0.28), 0.35, 0.8)
		for sx in [-1.0, 1.0]:
			Geo.put(self, Geo.rounded_box(Vector3(0.6, h + 0.6, 0.8), 0.12, 2), post, Vector3(float(sx) * (w * 0.5 + 0.3), (h + 0.6) * 0.5, 0.0))
			Geo.put(self, Geo.box(Vector3(0.1, h, 0.12)), Mats.glow(Color(1.0, 0.4, 0.3), 2.0), Vector3(float(sx) * (w * 0.5), h * 0.5, 0.0), Vector3.ZERO, Vector3.ONE, false)
		Geo.put(self, Geo.rounded_box(Vector3(w + 1.2, 0.5, 0.9), 0.1, 2), post, Vector3(0.0, h + 0.35, 0.0))
		_mat = ShaderMaterial.new()
		_mat.shader = Mats.shader("res://shaders/ghost.gdshader")
		_mat.set_shader_parameter("half_size", Vector3(w * 0.5, h * 0.5, 0.05))
		_mat.set_shader_parameter("edge_color", Color(1.0, 0.35, 0.3))
		_curtain = Geo.put(self, Geo.box(Vector3(w, h, 0.1)), _mat, Vector3(0.0, h * 0.5, 0.0), Vector3.ZERO, Vector3.ONE, false)

	func _physics_process(delta: float) -> void:
		if world == null:
			return
		var on: bool = bool(world.is_switch_on(_id))
		_open = move_toward(_open, 1.0 if on else 0.0, delta * 2.5)
		_mat.set_shader_parameter("fade", 1.0 - _open)
		_curtain.visible = _open < 0.99
		_cs.disabled = _open > 0.5
		if on != _was:
			_was = on
			Sfx.play("gate", -2.0, 1.0 if on else 0.8)


# ---------------------------------------------------------------- targets
## Punch targets: hit them all within `time` seconds of the first hit to fire switch `id` (permanent).
class Targets extends Node3D:
	var world: Node = null
	var _id: String = "T"
	var _time: float = 6.0
	var _left: float = 0.0
	var _items: Array = []
	var _done: bool = false

	func setup(o: Dictionary) -> void:
		position = LevelLoader.vec(o.get("p", [0, 0, 0]))
		_id = str(o.get("id", "T"))
		_time = float(o.get("time", 6.0))
		var pts: Array = o.get("pts", [])
		for i in range(pts.size()):
			var t := Target.new()
			t.owner_set = self
			add_child(t)
			t.position = LevelLoader.vec(pts[i]) - position
			_items.append(t)

	func _physics_process(delta: float) -> void:
		if _done or world == null:
			return
		if _left > 0.0:
			_left -= delta
			world.hint("الأهداف: %d / %d   الوقت: %.1f" % [_count(), _items.size(), maxf(_left, 0.0)])
			if _left <= 0.0:
				for t in _items:
					(t as Target).reset()
				Sfx.play("wrong", -2.0)
				world.toast("انتهى الوقت! أعد المحاولة", Color(1.0, 0.45, 0.4))

	func _count() -> int:
		var n: int = 0
		for t in _items:
			if (t as Target).down:
				n += 1
		return n

	func on_hit() -> void:
		if _left <= 0.0:
			_left = _time
		if _count() >= _items.size():
			_done = true
			_left = 0.0
			world.activate_switch(_id, 0.0)
			Sfx.play("puzzle_solved", 0.0)
			world.toast("رائع! أصبت كل الأهداف", Color(0.4, 1.0, 0.6))
			Debris.spray(get_parent(), world, global_position + Vector3(0.0, 2.0, 0.0), 5, "gem", 1.0, 5.0)


class Target extends Node3D:
	var owner_set: Targets
	var down: bool = false
	var hit_radius: float = 0.75
	var hit_offset := Vector3(0.0, 1.3, 0.0)
	var _disc: Node3D
	var _spin: float = 0.0

	func _ready() -> void:
		Geo.put(self, Geo.cyl(0.08, 0.1, 1.0, 8), Mats.metal(Color(0.3, 0.3, 0.35), 0.35, 0.8), Vector3(0.0, 0.5, 0.0))
		_disc = Node3D.new()
		_disc.position = Vector3(0.0, 1.35, 0.0)
		add_child(_disc)
		var cols: Array = [Color(1.0, 0.3, 0.3), Color(1.0, 1.0, 1.0), Color(1.0, 0.3, 0.3), Color(1.0, 0.85, 0.3)]
		for i in range(4):
			var r: float = 0.6 - float(i) * 0.14
			Geo.put(_disc, Geo.cyl(r, r, 0.08 + float(i) * 0.02, 24), Mats.plastic(cols[i], 0.35, cols[i], 0.4), Vector3.ZERO, Vector3(90.0, 0.0, 0.0))
		add_to_group("hittable")

	func _process(delta: float) -> void:
		if down:
			_disc.rotation.x = move_toward(_disc.rotation.x, -1.45, delta * 8.0)
		else:
			_spin += delta
			_disc.rotation = Vector3(0.0, _spin * 1.5, 0.0)

	func reset() -> void:
		down = false
		add_to_group("hittable")

	func hit(_by: Node, _kind: String) -> bool:
		if down:
			return false
		down = true
		remove_from_group("hittable")
		_disc.rotation.y = 0.0
		Sfx.play("target", 0.0, randf_range(0.95, 1.1))
		Fx.burst(get_parent(), _disc.global_position, Color(1.0, 0.85, 0.4), 12, 5.0, 0.3, 0.35)
		owner_set.on_hit()
		return true


# ------------------------------------------------------------------- wall
## Breakable wall. kind "crystal" / "ice" shatter into shards, "metal" breaks into plates. hp = hits needed
## (heavy hits count double). p = floor centre, s = size, ry = yaw.
class Wall extends StaticBody3D:
	var world: Node = null
	var hit_radius: float = 1.6
	var hit_offset := Vector3.ZERO
	var _kind: String = "crystal"
	var _hp: int = 2
	var _s := Vector3(4.0, 3.0, 0.8)
	var _vis: Node3D
	var _mat: Material
	var _shake: float = 0.0

	func setup(o: Dictionary) -> void:
		_s = LevelLoader.vec(o.get("s"), Vector3(4.0, 3.0, 0.8))
		position = LevelLoader.vec(o.get("p")) + Vector3(0.0, _s.y * 0.5, 0.0)
		rotation_degrees.y = float(o.get("ry", 0.0))
		_kind = str(o.get("kind", "crystal"))
		_hp = int(o.get("hp", 2))
		hit_radius = maxf(_s.x, _s.z) * 0.5
		collision_layer = 1
		collision_mask = 0
		var cs := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = _s
		cs.shape = bs
		add_child(cs)
		_vis = Node3D.new()
		add_child(_vis)
		var acc: Color = Mats.accent(0)
		if _kind == "ice":
			_mat = Mats.plastic(Color(0.7, 0.88, 1.0), 0.04, Color(0.35, 0.65, 1.0), 0.35, 0.6)
		elif _kind == "metal":
			_mat = Mats.metal(Color(0.4, 0.38, 0.4), 0.45, 0.8)
		else:
			_mat = Mats.plastic(acc.lerp(Color(1, 1, 1), 0.3), 0.08, acc, 0.9, 0.5)
		if _kind == "metal":
			Geo.put(_vis, Geo.rounded_box(_s, 0.08, 2), _mat)
			for i in range(int(_s.x / 1.2)):
				Geo.put(_vis, Geo.box(Vector3(0.08, _s.y * 0.95, _s.z + 0.04)), Mats.metal(Color(0.85, 0.6, 0.15), 0.4, 0.6), Vector3(-_s.x * 0.5 + 0.6 + float(i) * 1.2, 0.0, 0.0))
		else:
			var rng := RandomNumberGenerator.new()
			rng.seed = int(position.x * 13.0 + position.z * 7.0)
			Geo.put(_vis, Geo.box(_s * Vector3(1.0, 1.0, 0.6)), _mat)
			for i in range(int(_s.x * _s.y * 0.7)):
				var p := Vector3(rng.randf_range(-0.5, 0.5) * _s.x, rng.randf_range(-0.5, 0.45) * _s.y, rng.randf_range(-0.3, 0.3) * _s.z)
				Geo.put(_vis, Geo.crystal(rng.randf_range(0.15, 0.35), rng.randf_range(0.5, 1.2), 0.3, 6), _mat, p, Vector3(rng.randf_range(-60.0, 60.0), rng.randf() * 60.0, rng.randf_range(-60.0, 60.0)))
		add_to_group("hittable")

	func _process(delta: float) -> void:
		_shake = maxf(_shake - delta * 3.0, 0.0)
		_vis.position = Vector3(randf_range(-1.0, 1.0), 0.0, randf_range(-1.0, 1.0)) * 0.06 * _shake

	func hit(by: Node, kind: String) -> bool:
		var dmg: int = 2 if kind == "punch3" or kind == "spin_big" or kind == "dash" else 1
		_hp -= dmg
		_shake = 1.0
		var from: Vector3 = (by as Node3D).global_position if by is Node3D else global_position + Vector3(0.0, 0.0, 2.0)
		if _hp > 0:
			Sfx.play("ice_crack" if _kind != "metal" else "clang", -2.0)
			Fx.burst(get_parent(), global_position.lerp(from, 0.4), Color(1.0, 1.0, 1.0, 0.8), 8, 4.0, 0.25, 0.3)
			return true
		remove_from_group("hittable")
		collision_layer = 0
		var par: Node = get_parent()
		if _kind == "metal":
			Debris.box_shatter(par, global_transform, _s, _mat, from, 7.0, 10, 4.0)
			Sfx.play("explode", -3.0)
		else:
			Debris.shards(par, global_position, maxf(_s.x, _s.y) * 0.35, _mat, from, 7.0, 18, 0.32, 4.0)
			Debris.box_shatter(par, global_transform, _s * Vector3(1.0, 1.0, 0.6), _mat, from, 5.0, 6, 3.5)
			Sfx.play("shatter", 0.0)
		Fx.burst(par, global_position, Color(1.0, 1.0, 1.0, 0.8), 18, 7.0, 0.35, 0.5, -6.0)
		if world != null:
			world.shake(0.3)
			world.hitstop(0.06)
		queue_free()
		return true
