class_name BatterySwap
extends Node
## Cinematic battery change (about 2.3 s). The camera swings behind the robot, the robot looks over its
## shoulder, the back clamps open, the drained cell is kicked out as a real rigid body (it bounces away,
## smoking), the new cell flies in and clicks into the socket, the clamps shut and a charge wave runs up the
## body while the gauge fills, then a fist pump. Driven by a tiny timeline in _process.

var world: Node = null
var player: Player = null
var cell: MeshInstance3D = null      # the new cell (taken from the pickup, already in the level)
var _t: float = 0.0
var _events: Array = []
var _from_xf := Transform3D.IDENTITY
var _old_level: float = 0.0
var _rig: CameraRig
var _done: bool = false
var _fly_t: float = -1.0
var _ins_t: float = -1.0
var _ins_from := Transform3D.IDENTITY
var _charge_t: float = -1.0
var _start_bat: float = 0.0


static func begin(w: Node, pl: Player, new_cell: MeshInstance3D) -> BatterySwap:
	var s := BatterySwap.new()
	s.world = w
	s.player = pl
	s.cell = new_cell
	w.add_child(s)
	return s


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE
	_rig = world.get("rig")
	_old_level = player.battery_ratio()
	_start_bat = player.battery
	player.frozen = true
	player.controls_enabled = false
	player.model.pose_override = "swap_look"
	player.model.set_mood(5, 0.5)
	_from_xf = cell.global_transform
	var back: Vector3 = _back_dir()
	var side: Vector3 = back.cross(Vector3.UP).normalized()
	var focus: Vector3 = player.global_position + Vector3(0.0, 0.75, 0.0)
	var cam_pos: Vector3 = focus + back * 2.6 + side * 1.6 + Vector3(0.0, 0.7, 0.0)
	_rig.cinematic(cam_pos, focus + back * 0.2, 0.45)
	Sfx.play("battery_grab", -2.0)
	_fly_t = 0.0
	_events = [
		[0.32, "open"], [0.55, "eject"], [0.78, "insert"], [1.08, "close"], [1.18, "charge"],
		[1.75, "flex"], [2.35, "end"],
	]


func _back_dir() -> Vector3:
	var y: float = player.face_yaw()
	return Vector3(sin(y), 0.0, cos(y))


func _socket_xf() -> Transform3D:
	var sock: Node3D = player.model.battery_socket()
	return sock.global_transform * Transform3D(Basis.IDENTITY, Vector3(0.0, -0.135, 0.0))


func _process(delta: float) -> void:
	if _done:
		return
	_t += delta
	while _events.size() > 0 and _t >= float(_events[0][0]):
		var ev: String = _events[0][1]
		_events.pop_front()
		call("_ev_" + ev)
	# new cell flies to a hover point behind the robot's back
	if _fly_t >= 0.0 and cell != null:
		_fly_t += delta
		var k: float = clampf(_fly_t / 0.55, 0.0, 1.0)
		var e: float = 1.0 - pow(1.0 - k, 3.0)
		var sock: Transform3D = _socket_xf()
		var hover_pos: Vector3 = sock.origin + _back_dir() * 0.55 + Vector3(0.0, 0.45, 0.0)
		var p: Vector3 = _from_xf.origin.lerp(hover_pos, e) + Vector3(0.0, sin(e * PI) * 0.8, 0.0)
		var sc: float = lerpf(_from_xf.basis.get_scale().x, 0.8, e)
		var b := Basis.from_euler(Vector3(0.0, (1.0 - e) * TAU * 1.5, 0.0)).scaled(Vector3(sc, sc, sc))
		cell.global_transform = Transform3D(sock.basis.orthonormalized() * b, p)
		if k >= 1.0:
			_fly_t = -1.0
	# insertion slide
	if _ins_t >= 0.0 and cell != null:
		_ins_t += delta
		var k2: float = clampf(_ins_t / 0.22, 0.0, 1.0)
		var e2: float = k2 * k2 * (3.0 - 2.0 * k2)
		var target: Transform3D = _socket_xf()
		cell.global_transform = _ins_from.interpolate_with(target, e2)
		if k2 >= 1.0:
			_ins_t = -1.0
			player.model.attach_battery(cell)
			var m: ShaderMaterial = cell.get_meta("mat")
			m.set_shader_parameter("level", _old_level)
			Sfx.play("battery_insert", 0.0)
			Fx.burst(world.get("_level_root"), target.origin, Color(1.0, 0.9, 0.6), 10, 4.0, 0.2, 0.25, -6.0)
			world.shake(0.15)
			Game.vibrate(30)
	# charge fill
	if _charge_t >= 0.0:
		_charge_t += delta
		var k3: float = clampf(_charge_t / 0.6, 0.0, 1.0)
		player.set_battery(lerpf(_start_bat, Player.BAT_MAX, k3 * k3 * (3.0 - 2.0 * k3)))
		if k3 >= 1.0:
			_charge_t = -1.0


func _ev_open() -> void:
	player.model.set_clamps(1.0)
	Sfx.play("hatch", -2.0)
	var par: Node = world.get("_level_root")
	Fx.burst(par, _socket_xf().origin + _back_dir() * 0.2, Color(0.85, 0.9, 1.0, 0.55), 10, 2.5, 0.45, 0.6, 1.5, 50.0, _back_dir())


func _ev_eject() -> void:
	var par: Node = world.get("_level_root")
	var old: MeshInstance3D = player.model.detach_battery(par)
	if old == null:
		return
	var m: ShaderMaterial = old.get_meta("mat")
	m.set_shader_parameter("level", 0.02)
	m.set_shader_parameter("blink", 0.0)
	m.set_shader_parameter("energy", 0.6)
	var gt: Transform3D = old.global_transform
	par.remove_child(old)
	var shape := CapsuleShape3D.new()
	shape.radius = 0.07
	shape.height = 0.24
	var lin: Vector3 = _back_dir() * 3.5 + Vector3(0.0, 5.5, 0.0) + _back_dir().cross(Vector3.UP) * randf_range(-1.0, 1.0)
	var rb: Debris.Chunk = Debris.piece(par, old.mesh, old.material_override, Transform3D(gt.basis.orthonormalized(), gt * Vector3(0.0, 0.135, 0.0)), shape, lin, Vector3(randf_range(6.0, 10.0), randf_range(-2.0, 2.0), randf_range(-4.0, 4.0)), 7.0, 0.5, Transform3D(Basis.from_scale(gt.basis.get_scale()), Vector3(0.0, -0.108, 0.0)))
	if rb != null:
		for c in old.get_children():
			var cap: MeshInstance3D = c.duplicate() as MeshInstance3D
			if cap != null:
				var vis: MeshInstance3D = rb.get_child(1) as MeshInstance3D
				vis.add_child(cap)
		var smoke := CPUParticles3D.new()
		smoke.mesh = Fx.quad()
		smoke.amount = 14
		smoke.lifetime = 0.9
		smoke.local_coords = false
		smoke.gravity = Vector3(0.0, 1.2, 0.0)
		smoke.initial_velocity_min = 0.2
		smoke.initial_velocity_max = 0.6
		smoke.scale_amount_min = 0.15
		smoke.scale_amount_max = 0.35
		smoke.color = Color(0.4, 0.4, 0.45, 0.45)
		smoke.color_ramp = Fx.fade_ramp()
		rb.add_child(smoke)
	old.queue_free()
	Sfx.play("battery_eject", 0.0)
	Fx.burst(par, gt.origin, Color(1.0, 0.6, 0.3), 12, 5.0, 0.2, 0.35, -8.0, 60.0, _back_dir())
	world.shake(0.2)
	Game.vibrate(40)


func _ev_insert() -> void:
	if cell == null:
		return
	_fly_t = -1.0
	_ins_from = cell.global_transform
	_ins_t = 0.0


func _ev_close() -> void:
	player.model.set_clamps(0.0)
	Sfx.play("clamp", -2.0)


func _ev_charge() -> void:
	player.model.set_mood(1, 1.6)
	player.model.set_face_scan(true)
	if cell != null:
		var m: ShaderMaterial = cell.get_meta("mat")
		m.set_shader_parameter("charge_wave", 1.0)
	_charge_t = 0.0
	Sfx.play("charge_up", 0.0)
	var par: Node = world.get("_level_root")
	var p: Vector3 = player.global_position
	for i in range(4):
		var tw := create_tween()
		tw.tween_interval(0.12 * float(i))
		tw.tween_callback(Fx.ring.bind(par, p + Vector3(0.0, 0.2 + 0.32 * float(i), 0.0), Color(0.4, 1.0, 0.6), 2.2 - 0.25 * float(i), 0.35, 3.2))
	Fx.burst(par, p + Vector3(0.0, 0.6, 0.0), Color(0.45, 1.0, 0.6, 0.9), 26, 5.0, 0.25, 0.7, 1.5, 180.0)
	Fx.flash(par, p + Vector3(0.0, 1.0, 0.0), Color(0.5, 1.0, 0.7), 7.0, 0.6, 3.0)
	world.call("hud_flash", Color(0.4, 1.0, 0.6), 0.25)


func _ev_flex() -> void:
	player.model.pose_override = "swap_flex"
	player.model.set_face_scan(false)
	if cell != null and is_instance_valid(cell) and cell.has_meta("mat"):
		var m: ShaderMaterial = cell.get_meta("mat")
		m.set_shader_parameter("charge_wave", 0.0)
	Sfx.play("powerup", -2.0)
	world.call("toast", "تم شحن البطارية بالكامل!", Color(0.4, 1.0, 0.6))
	Game.vibrate(50)


func _ev_end() -> void:
	_done = true
	player.model.pose_override = ""
	player.frozen = false
	player.controls_enabled = true
	player.set_battery(Player.BAT_MAX)
	_rig.cinematic_off(0.5)
	queue_free()
