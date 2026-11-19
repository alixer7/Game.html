class_name Collectibles
extends RefCounted
## Spark gems (one MultiMesh for the whole level), rescue bots and breakable crates.

const BOT_COLORS := [Color(0.25, 0.9, 1.0), Color(1.0, 0.4, 0.8), Color(1.0, 0.82, 0.3)]


## Hexagonal gem with flat-shaded facets; winding is fixed per triangle (Godot front faces are clockwise).
static func gem_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var r: float = 0.25
	var yh: float = 0.1
	var tip: float = 0.36
	var top := Vector3(0.0, tip, 0.0)
	var bot := Vector3(0.0, -tip, 0.0)
	var up: Array = []
	var lo: Array = []
	for i in range(6):
		var a: float = TAU * i / 6.0
		up.append(Vector3(cos(a) * r, yh, sin(a) * r))
		lo.append(Vector3(cos(a) * r, -yh, sin(a) * r))
	for i in range(6):
		var j: int = (i + 1) % 6
		var u0: Vector3 = up[i]
		var u1: Vector3 = up[j]
		var l0: Vector3 = lo[i]
		var l1: Vector3 = lo[j]
		_tri(st, top, u1, u0)
		_tri(st, u0, u1, l1)
		_tri(st, u0, l1, l0)
		_tri(st, bot, l0, l1)
	return st.commit()


static func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3) -> void:
	var ctr: Vector3 = (a + b + c) / 3.0
	var n: Vector3 = (b - a).cross(c - a)
	var bb: Vector3 = b
	var cc: Vector3 = c
	if n.dot(ctr) > 0.0:
		bb = c
		cc = b
		n = -n
	var outward: Vector3 = (-n).normalized()
	st.set_normal(outward)
	st.add_vertex(a)
	st.set_normal(outward)
	st.add_vertex(bb)
	st.set_normal(outward)
	st.add_vertex(cc)


# ------------------------------------------------------------- coin field
class CoinField extends MultiMeshInstance3D:
	var world: Node = null
	var _pts := PackedVector3Array()
	var _taken := PackedByteArray()
	var _mm: MultiMesh
	var _combo: int = 0
	var _combo_t: float = 0.0

	func setup(points: Array) -> void:
		for p in points:
			_pts.append(LevelLoader.vec(p))
		_taken.resize(_pts.size())
		_mm = MultiMesh.new()
		_mm.transform_format = MultiMesh.TRANSFORM_3D
		_mm.mesh = Collectibles.gem_mesh()
		_mm.instance_count = _pts.size()
		for i in range(_pts.size()):
			_mm.set_instance_transform(i, Transform3D(Basis.IDENTITY, _pts[i]))
		multimesh = _mm
		custom_aabb = AABB(Vector3(-400.0, -200.0, -400.0), Vector3(800.0, 400.0, 800.0))
		var m := ShaderMaterial.new()
		m.shader = Mats.shader("res://shaders/coin.gdshader")
		material_override = m
		cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	func _physics_process(delta: float) -> void:
		if world == null or _pts.size() == 0:
			return
		var pl: Player = world.player
		if pl == null or not is_instance_valid(pl) or not pl.alive:
			return
		_combo_t -= delta
		if _combo_t <= 0.0:
			_combo = 0
		var c: Vector3 = pl.global_position + Vector3(0.0, 0.55, 0.0)
		for i in range(_pts.size()):
			if _taken[i] == 1:
				continue
			var d: Vector3 = _pts[i] - c
			if absf(d.y) > 1.6 or d.length_squared() > 1.69:
				continue
			_taken[i] = 1
			_mm.set_instance_transform(i, Transform3D(Basis.IDENTITY.scaled(Vector3.ZERO), _pts[i]))
			_combo += 1
			_combo_t = 0.7
			Sfx.play("coin", -6.0, minf(1.0 + _combo * 0.05, 1.6))
			Fx.burst(self, _pts[i], Color(1.0, 0.85, 0.3, 0.9), 5, 3.0, 0.25, 0.35, 0.0, 180.0)
			world.add_coins(1, _pts[i])


# -------------------------------------------------------------- rescue bot
## p = floor position under the bot, i = slot 0..2 (HUD order).
class RescueBot extends Area3D:
	var world: Node = null
	var idx: int = 0
	var _model: RobotModel
	var _cage: MeshInstance3D
	var _t: float = 0.0
	var _taken: bool = false

	func setup(o: Dictionary) -> void:
		position = LevelLoader.vec(o.get("p"))
		idx = clampi(int(o.get("i", 0)), 0, 2)
		collision_layer = 0
		collision_mask = 2
		var cs := CollisionShape3D.new()
		var sp := SphereShape3D.new()
		sp.radius = 1.3
		cs.shape = sp
		cs.position = Vector3(0.0, 0.9, 0.0)
		add_child(cs)
		var col: Color = Collectibles.BOT_COLORS[idx]
		_model = RobotModel.make(col)
		_model.wave = true
		_model.position = Vector3(0.0, 0.3, 0.0)
		add_child(_model)
		var sm := SphereMesh.new()
		sm.radius = 0.95
		sm.height = 1.9
		sm.radial_segments = 24
		sm.rings = 12
		_cage = MeshInstance3D.new()
		_cage.mesh = sm
		_cage.material_override = Mats.neon(col, 1.6, 2.2, 0.08)
		_cage.position = Vector3(0.0, 0.75, 0.0)
		_cage.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(_cage)
		var bh: float = 16.0
		var bm := CylinderMesh.new()
		bm.top_radius = 0.4
		bm.bottom_radius = 0.4
		bm.height = bh
		bm.cap_top = false
		bm.cap_bottom = false
		bm.radial_segments = 16
		var beam := MeshInstance3D.new()
		beam.mesh = bm
		beam.material_override = Mats.beam(col, bh, 1.3, false, 0.8)
		beam.position = Vector3(0.0, bh * 0.5 + 0.2, 0.0)
		beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(beam)

	func _physics_process(delta: float) -> void:
		_t += delta
		if _taken or world == null:
			return
		_model.position.y = 0.3 + sin(_t * 2.2) * 0.12
		_cage.scale = Vector3.ONE * (1.0 + sin(_t * 3.0) * 0.03)
		var pl: Player = world.player
		if pl != null and is_instance_valid(pl) and pl.alive and overlaps_body(pl):
			_collect()

	func _collect() -> void:
		_taken = true
		Sfx.play("bot_rescue")
		Game.vibrate(60)
		var p: Vector3 = global_position + Vector3(0.0, 0.9, 0.0)
		var col: Color = Collectibles.BOT_COLORS[idx]
		var par: Node = get_parent()
		Fx.ring(par, global_position, col, 5.0, 0.7, 3.0)
		Fx.burst(par, p, col, 26, 7.0, 0.4, 0.9, -3.0)
		world.collect_bot(idx, p)
		var tw := create_tween()
		tw.set_parallel(true)
		tw.tween_property(_cage, "scale", Vector3.ONE * 1.8, 0.35)
		tw.tween_property(_model, "position:y", 3.0, 0.7).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tw.tween_property(_model, "scale", Vector3.ZERO, 0.35).set_delay(0.45)
		tw.chain().tween_callback(queue_free)


# ------------------------------------------------------------------ crate
## p = floor position under the crate, n = gems inside. Break it with punch / spin / dash / by landing on it.
## It bursts into its frame bars and panels (real rigid bodies) and the gems spray out physically.
class Crate extends StaticBody3D:
	var world: Node = null
	var coins: int = 5
	var hit_radius: float = 0.9
	var _area: Area3D
	var _broken: bool = false
	var _vis: Node3D
	var _wob: float = 0.0
	var _frame_mat: Material
	var _panel_mat: Material

	func setup(o: Dictionary) -> void:
		collision_layer = 1
		collision_mask = 0
		coins = int(o.get("n", 5))
		position = LevelLoader.vec(o.get("p")) + Vector3(0.0, 0.5, 0.0)
		rotation_degrees.y = float(o.get("ry", 0.0))
		var cs := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = Vector3(1.0, 1.0, 1.0)
		cs.shape = bs
		add_child(cs)
		_vis = Node3D.new()
		add_child(_vis)
		var acc: Color = Mats.accent(1)
		_frame_mat = Mats.metal(Color(0.85, 0.55, 0.15), 0.4, 0.6)
		_panel_mat = Mats.plastic(Color(0.14, 0.17, 0.26), 0.35, acc, 0.25)
		var e: float = 1.0
		var bar: float = 0.14
		var h: float = 0.5
		for ax in range(3):
			for sa in [-1.0, 1.0]:
				for sb in [-1.0, 1.0]:
					var p := Vector3.ZERO
					var sz := Vector3(bar, bar, bar)
					sz[ax] = e
					p[(ax + 1) % 3] = float(sa) * (h - bar * 0.5)
					p[(ax + 2) % 3] = float(sb) * (h - bar * 0.5)
					Geo.put(_vis, Geo.box(sz), _frame_mat, p)
		Geo.put(_vis, Geo.box(Vector3(e - 0.06, e - 0.06, e - 0.06)), _panel_mat)
		for ax2 in range(3):
			for sg in [-1.0, 1.0]:
				var rot := Vector3.ZERO
				var pp := Vector3.ZERO
				pp[ax2] = float(sg) * 0.475
				if ax2 == 0:
					rot = Vector3(0.0, 0.0, 90.0)
				elif ax2 == 2:
					rot = Vector3(90.0, 0.0, 0.0)
				Geo.put(_vis, Geo.cyl(0.13, 0.13, 0.02, 6), Mats.glow(Color(1.0, 0.8, 0.3), 1.8), pp, rot, Vector3.ONE, false)
		add_to_group("hittable")
		_area = Area3D.new()
		_area.collision_layer = 0
		_area.collision_mask = 2
		var acs := CollisionShape3D.new()
		var abs_ := BoxShape3D.new()
		abs_.size = Vector3(1.0, 0.5, 1.0)
		acs.shape = abs_
		acs.position = Vector3(0.0, 0.8, 0.0)
		_area.add_child(acs)
		add_child(_area)

	func _physics_process(delta: float) -> void:
		if _broken or world == null:
			return
		_wob = move_toward(_wob, 0.0, delta * 3.0)
		_vis.rotation = Vector3(sin(_wob * 30.0) * _wob * 0.15, 0.0, cos(_wob * 26.0) * _wob * 0.15)
		var pl: Player = world.player
		if pl != null and is_instance_valid(pl) and pl.alive and pl.velocity.y < -2.0 and _area.overlaps_body(pl):
			pl.stomp_bounce()
			_break(pl.global_position + Vector3(0.0, 1.5, 0.0))

	func hit(by: Node, _kind: String) -> bool:
		if _broken:
			return false
		var from: Vector3 = global_position + Vector3(0.0, 0.0, 1.0)
		if by is Node3D:
			from = (by as Node3D).global_position + Vector3(0.0, 0.5, 0.0)
		_break(from)
		return true

	func _break(from: Vector3) -> void:
		_broken = true
		remove_from_group("hittable")
		var p: Vector3 = global_position
		Sfx.play("crate")
		Game.vibrate(30)
		var parent: Node = get_parent()
		Debris.crate_break(parent, global_transform, 1.0, _frame_mat, _panel_mat, from, 6.5)
		Fx.burst(parent, p, Color(1.0, 0.8, 0.4), 10, 5.0, 0.35, 0.5, -8.0)
		Fx.burst(parent, p, Color(0.6, 0.6, 0.7, 0.5), 6, 2.0, 0.7, 0.8, 1.0)
		Debris.spray(parent, world, p, coins, "gem", 1.0, 5.5)
		queue_free()


# ------------------------------------------------------------ battery cell
## Spare battery on a holographic pedestal (usually somewhere hard to reach). Touch it to swap your drained
## cell for this one (full recharge, cinematic swap). One use. p = floor position under it.
class BatteryCell extends Area3D:
	var world: Node = null
	var _cell: MeshInstance3D
	var _holder: Node3D
	var _ring_mat: ShaderMaterial
	var _beam: MeshInstance3D
	var _t: float = 0.0
	var _used: bool = false
	var _msg_cd: float = 0.0

	func setup(o: Dictionary) -> void:
		position = LevelLoader.vec(o.get("p"))
		collision_layer = 0
		collision_mask = 2
		var cs := CollisionShape3D.new()
		var sp := SphereShape3D.new()
		sp.radius = 1.15
		cs.shape = sp
		cs.position = Vector3(0.0, 1.0, 0.0)
		add_child(cs)
		var green := Color(0.35, 1.0, 0.55)
		Geo.put(self, Geo.lathe(PackedVector2Array([Vector2(0.0, 0.0), Vector2(0.62, 0.0), Vector2(0.66, 0.08), Vector2(0.5, 0.16), Vector2(0.42, 0.22), Vector2(0.0, 0.22)]), 28, "bat_pedestal"), Mats.metal(Color(0.18, 0.2, 0.26), 0.3, 0.7))
		Geo.put(self, Geo.torus(0.48, 0.56, 32, 5), Mats.glow(green, 2.2), Vector3(0.0, 0.17, 0.0), Vector3.ZERO, Vector3.ONE, false)
		_holder = Node3D.new()
		_holder.position = Vector3(0.0, 1.05, 0.0)
		add_child(_holder)
		_ring_mat = Mats.neon_unique(green, 1.6, 1.2, 0.5)
		for i in range(2):
			var r := Geo.put(_holder, Geo.torus(0.5 + 0.12 * float(i), 0.55 + 0.12 * float(i), 36, 5), _ring_mat, Vector3.ZERO, Vector3(70.0 if i == 0 else -70.0, 0.0, 0.0), Vector3.ONE, false)
			r.name = "ring%d" % i
		_cell = RobotModel.make_battery_mesh(1.0)
		_cell.scale = Vector3.ONE * 2.2
		_cell.position = Vector3(0.0, -0.3, 0.0)
		_holder.add_child(_cell)
		var bh: float = 7.0
		var bm := CylinderMesh.new()
		bm.top_radius = 0.55
		bm.bottom_radius = 0.55
		bm.height = bh
		bm.cap_top = false
		bm.cap_bottom = false
		bm.radial_segments = 16
		_beam = MeshInstance3D.new()
		_beam.mesh = bm
		_beam.material_override = Mats.beam(green, bh, 1.2, false, 0.6)
		_beam.position = Vector3(0.0, bh * 0.5 + 0.2, 0.0)
		_beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(_beam)
		var l := OmniLight3D.new()
		l.light_color = green
		l.light_energy = 1.2
		l.omni_range = 4.0
		l.position = Vector3(0.0, 1.2, 0.0)
		add_child(l)

	func _physics_process(delta: float) -> void:
		_t += delta
		_msg_cd = maxf(_msg_cd - delta, 0.0)
		if _used:
			return
		_holder.position.y = 1.05 + sin(_t * 2.0) * 0.12
		_holder.rotation.y += delta * 1.2
		for c in _holder.get_children():
			if c.name.begins_with("ring"):
				(c as Node3D).rotate_object_local(Vector3.UP, delta * 2.5)
		var pl: Player = Zones.player_of(world)
		if pl == null or not overlaps_body(pl) or pl.frozen:
			return
		if pl.battery >= Player.BAT_MAX - 2.0:
			if _msg_cd <= 0.0:
				_msg_cd = 3.0
				world.toast("بطاريتك ممتلئة، عُد إليها لاحقاً", Color(0.4, 1.0, 0.6))
			return
		_take(pl)

	func _take(pl: Player) -> void:
		_used = true
		var gt: Transform3D = _cell.global_transform
		_holder.remove_child(_cell)
		get_parent().add_child(_cell)
		_cell.global_transform = gt
		_beam.visible = false
		_ring_mat.set_shader_parameter("energy", 0.3)
		BatterySwap.begin(world, pl, _cell)
		_cell = null
