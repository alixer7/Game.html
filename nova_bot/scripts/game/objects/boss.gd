class_name Boss
extends Node3D
## "Guardian": the final boss. Floats above a round arena, fires energy bolts, dives to slam the floor
## (an expanding shock-wave you must jump over), then sits stunned with its core exposed.
## Hit the core (spin / dash / land on it) three times to win; the goal portal unlocks.
## Level JSON: {"t":"boss","p":[x,y,z] = centre of the arena floor surface,"r": arena radius}

const MAX_HP := 3
const ST_WAIT := 0
const ST_INTRO := 1
const ST_FLOAT := 2
const ST_VOLLEY := 3
const ST_AIM := 4
const ST_DIVE := 5
const ST_SLAM := 6
const ST_STUN := 7
const ST_RECOVER := 8
const ST_DEAD := 9

const VIOLET := Color(0.78, 0.4, 1.0)
const GOLD := Color(1.0, 0.8, 0.3)

var world: Node = null
var hit_radius: float = 2.7

var _floor := Vector3.ZERO
var _arena_r: float = 16.0
var _hp: int = MAX_HP
var _state: int = ST_WAIT
var _st: float = 0.0
var _t: float = 0.0
var _orbit: float = 0.0
var _vy: float = 0.0
var _target := Vector3.ZERO
var _volley_left: int = 0
var _volley_t: float = 0.0
var _rings_left: int = 0
var _ring_t: float = 0.0
var _inv: float = 0.0
var _away: float = 0.0
var _open: float = 0.0
var _open_target: float = 0.0
var _flash: float = 0.0
var _dead_fx: float = 0.0

var _core_mat: StandardMaterial3D
var _shell: MeshInstance3D
var _armor: Node3D
var _shards: Array[Node3D] = []
var _marker: Node3D
var _shadow: MeshInstance3D
var _shadow_mat: ShaderMaterial
var _light: OmniLight3D


func setup(o: Dictionary) -> void:
	_floor = LevelLoader.vec(o.get("p"))
	_arena_r = float(o.get("r", 16.0))
	position = _floor + Vector3(0.0, _hover_y(), 0.0)
	_build()
	add_to_group("hittable")


func _hover_y() -> float:
	return 6.5


func _phase() -> int:
	return MAX_HP - _hp   # 0, 1, 2 as the boss gets angrier


# ------------------------------------------------------------------ build
func _build() -> void:
	var core := MeshInstance3D.new()
	var cm := SphereMesh.new()
	cm.radius = 1.15
	cm.height = 2.3
	cm.radial_segments = 24
	cm.rings = 12
	core.mesh = cm
	_core_mat = StandardMaterial3D.new()
	_core_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_core_mat.albedo_color = Zones.hdr(VIOLET, 1.6)
	core.material_override = _core_mat
	core.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(core)

	_shell = MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 2.0
	sm.height = 4.0
	sm.radial_segments = 28
	sm.rings = 14
	_shell.mesh = sm
	_shell.material_override = Mats.neon(VIOLET, 1.8, 2.0, 0.12)
	_shell.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_shell)

	var ring_defs: Array = [[2.55, Vector3(0.25, 1.0, 0.0), 1.3], [3.05, Vector3(1.0, 0.2, 0.3), -0.9]]
	for rd in ring_defs:
		var def: Array = rd
		var rr: float = float(def[0])
		var ax: Vector3 = def[1]
		var sp := Fx.Spin.new()
		sp.axis = ax.normalized()
		sp.speed = float(def[2])
		add_child(sp)
		var tm := TorusMesh.new()
		tm.inner_radius = rr - 0.07
		tm.outer_radius = rr + 0.07
		tm.rings = 48
		tm.ring_segments = 6
		var ring := MeshInstance3D.new()
		ring.mesh = tm
		ring.material_override = Mats.neon(VIOLET, 2.4, 1.2, 0.8)
		ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		sp.add_child(ring)

	_armor = Node3D.new()
	add_child(_armor)
	var shard_mat: StandardMaterial3D = Mats.std(Color(0.1, 0.08, 0.16), 0.9, 0.28, VIOLET, 0.5)
	for i in range(6):
		var shard := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(1.0, 2.1, 0.4)
		shard.mesh = bm
		shard.material_override = shard_mat
		_armor.add_child(shard)
		_shards.append(shard)

	_light = OmniLight3D.new()
	_light.light_color = VIOLET
	_light.light_energy = 1.8
	_light.omni_range = 16.0
	_light.shadow_enabled = false
	add_child(_light)

	_marker = Node3D.new()
	_marker.top_level = true
	_marker.visible = false
	add_child(_marker)
	for i in range(2):
		var mt := TorusMesh.new()
		mt.inner_radius = 1.75 + 1.0 * i
		mt.outer_radius = 1.95 + 1.0 * i
		mt.rings = 40
		mt.ring_segments = 4
		var mi := MeshInstance3D.new()
		mi.mesh = mt
		mi.material_override = Mats.neon(Hazards.RED, 2.6, 1.0, 0.85)
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_marker.add_child(mi)

	_shadow = MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(7.0, 7.0)
	_shadow.mesh = pm
	_shadow_mat = ShaderMaterial.new()
	_shadow_mat.shader = Mats.shader("res://shaders/blob_shadow.gdshader")
	_shadow.material_override = _shadow_mat
	_shadow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_shadow.top_level = true
	add_child(_shadow)
	_layout_shards()


func _layout_shards() -> void:
	for i in range(_shards.size()):
		var a: float = TAU * float(i) / float(_shards.size())
		var r: float = lerpf(2.55, 4.4, _open)
		var s: Node3D = _shards[i]
		s.position = Vector3(cos(a) * r, lerpf(0.0, 0.7, _open), sin(a) * r)
		s.rotation = Vector3(0.55 * _open, PI * 0.5 - a, 0.0)


# ------------------------------------------------------------------ hits
func hit(_by: Node, kind: String) -> bool:
	if _state != ST_STUN or _inv > 0.0:
		return false
	_damage(kind)
	return true


func _damage(_kind: String) -> void:
	_hp -= 1
	_inv = 1.3
	_flash = 1.0
	Sfx.play("boss_hit")
	Game.vibrate(60)
	world.hitstop(0.12)
	world.shake(0.8)
	var par: Node = get_parent()
	Fx.burst(par, global_position, Color(1.0, 0.9, 0.6), 26, 9.0, 0.45, 0.8, -4.0)
	Fx.ring(par, global_position, Color(1.0, 0.85, 0.5), 8.0, 0.5, 3.0)
	if _hp <= 0:
		_set_state(ST_DEAD)
		world.boss_hud(0.0, true)
	else:
		world.boss_hud(float(_hp) / float(MAX_HP), true)
		world.toast("أصبته!", Color(1.0, 0.85, 0.4))
		_set_state(ST_RECOVER)


func _set_state(s: int) -> void:
	_state = s
	_st = 0.0
	if s == ST_STUN:
		_open_target = 1.0
		_vy = 0.0
	elif s == ST_RECOVER or s == ST_FLOAT or s == ST_WAIT:
		_open_target = 0.0
	if s == ST_DEAD:
		_open_target = 1.0
		remove_from_group("hittable")
		_marker.visible = false


# ------------------------------------------------------------------ loop
func _physics_process(delta: float) -> void:
	if world == null:
		return
	_t += delta
	_st += delta
	_inv = maxf(_inv - delta, 0.0)
	_flash = move_toward(_flash, 0.0, delta * 3.0)
	_open = move_toward(_open, _open_target, delta * 2.2)
	_layout_shards()
	_armor.rotate_y(delta * (0.5 + _open * 0.8))
	_update_visuals()

	var pl: Player = Zones.player_of(world)
	var in_arena: bool = false
	if pl != null:
		var d := Vector2(pl.global_position.x - _floor.x, pl.global_position.z - _floor.z)
		in_arena = d.length() < _arena_r - 0.5 and pl.global_position.y > _floor.y - 2.0

	if _state == ST_DEAD:
		_tick_dead(delta)
		return

	if _state == ST_WAIT:
		_hover(delta, 0.0, 0.25)
		if pl != null and in_arena:
			_set_state(ST_INTRO)
			world.boss_hud(float(_hp) / float(MAX_HP), true)
			Sfx.play("boss_roar")
			world.shake(0.6)
			world.toast("الحارس يستيقظ!", VIOLET)
		return

	# player left the arena or died: stand down (damage is kept)
	if in_arena:
		_away = 0.0
	else:
		_away += delta
		if _away > 1.2:
			_away = 0.0
			world.boss_hud(float(_hp) / float(MAX_HP), false)
			_marker.visible = false
			_set_state(ST_WAIT)
			return

	if _state == ST_INTRO:
		_hover(delta, 1.5, 0.4)
		if _st > 1.6:
			_set_state(ST_FLOAT)
	elif _state == ST_FLOAT:
		_hover(delta, 0.0, 0.7)
		if _st > 2.4 - 0.45 * float(_phase()):
			_volley_left = 3 + _phase()
			_volley_t = 0.4
			_set_state(ST_VOLLEY)
	elif _state == ST_VOLLEY:
		_hover(delta, 0.0, 0.4)
		_volley_t -= delta
		if _volley_left > 0 and _volley_t <= 0.0 and pl != null:
			_fire_bolt(pl)
			_volley_left -= 1
			_volley_t = 0.55 - 0.08 * float(_phase())
		if _volley_left <= 0 and _volley_t <= 0.0:
			_set_state(ST_AIM)
			_marker.visible = true
	elif _state == ST_AIM:
		_tick_aim(delta, pl)
	elif _state == ST_DIVE:
		_tick_dive(delta, pl)
	elif _state == ST_SLAM:
		if _st > 0.25:
			_set_state(ST_STUN)
	elif _state == ST_STUN:
		_tick_stun(delta, pl)
	elif _state == ST_RECOVER:
		_hover(delta, 0.0, 1.0)
		if _st > 1.1:
			_set_state(ST_FLOAT)

	# touching the boss while it is dangerous
	if pl != null and (_state == ST_FLOAT or _state == ST_VOLLEY or _state == ST_AIM or _state == ST_DIVE or _state == ST_SLAM):
		var c: Vector3 = pl.global_position + Vector3(0.0, 0.6, 0.0)
		if c.distance_to(global_position) < 2.4:
			pl.hurt(global_position, 1)


## Smooth orbit around the arena centre at hover height (+ extra).
func _hover(delta: float, extra: float, bob: float) -> void:
	_orbit += delta * (0.45 + 0.12 * float(_phase()))
	var rad: float = _arena_r * 0.28
	var want := Vector3(_floor.x + cos(_orbit) * rad, _floor.y + _hover_y() + extra + sin(_t * 1.7) * bob, _floor.z + sin(_orbit) * rad)
	position = position.lerp(want, 1.0 - exp(-3.0 * delta))


func _tick_aim(delta: float, pl: Player) -> void:
	var aim_time: float = 1.35 - 0.15 * float(_phase())
	var want := Vector3(position.x, _floor.y + _hover_y() + 2.5, position.z)
	if pl != null:
		var px: float = clampf(pl.global_position.x - _floor.x, -_arena_r * 0.8, _arena_r * 0.8)
		var pz: float = clampf(pl.global_position.z - _floor.z, -_arena_r * 0.8, _arena_r * 0.8)
		want.x = _floor.x + px
		want.z = _floor.z + pz
	position = position.lerp(want, 1.0 - exp(-4.5 * delta))
	_marker.global_position = Vector3(position.x, _floor.y + 0.1, position.z)
	var pulse: float = 1.0 + 0.08 * sin(_t * 18.0)
	_marker.scale = Vector3(pulse, 1.0, pulse)
	if _st >= aim_time:
		_target = Vector3(position.x, _floor.y, position.z)
		_vy = 0.0
		_set_state(ST_DIVE)
		Sfx.play("whoosh", -2.0, 0.6)


func _tick_dive(delta: float, pl: Player) -> void:
	_vy -= 95.0 * delta
	position.y += _vy * delta
	position.x = lerpf(position.x, _target.x, 1.0 - exp(-12.0 * delta))
	position.z = lerpf(position.z, _target.z, 1.0 - exp(-12.0 * delta))
	if position.y <= _floor.y + 1.3:
		position.y = _floor.y + 1.3
		_slam(pl)


func _slam(pl: Player) -> void:
	_marker.visible = false
	_set_state(ST_SLAM)
	var par: Node = get_parent()
	var impact := Vector3(position.x, _floor.y, position.z)
	Sfx.play("boss_slam")
	Game.vibrate(90)
	world.shake(1.0)
	world.hitstop(0.07)
	Fx.burst(par, impact + Vector3(0.0, 0.3, 0.0), Color(0.9, 0.8, 1.0, 0.9), 30, 10.0, 0.5, 0.9, -6.0, 80.0)
	Fx.ring(par, impact, VIOLET, 9.0, 0.5, 3.0)
	_spawn_shock(impact)
	_rings_left = 0 if _hp >= MAX_HP else 1
	_ring_t = 0.85
	if pl != null:
		var d := Vector2(pl.global_position.x - impact.x, pl.global_position.z - impact.z)
		if d.length() < 2.6 and pl.global_position.y < _floor.y + 2.0:
			pl.hurt(impact, 1)


func _spawn_shock(impact: Vector3) -> void:
	var sh := Shock.new()
	sh.world = world
	sh.center = impact
	sh.floor_y = _floor.y
	sh.speed = 10.0 + 1.6 * float(_phase())
	sh.max_r = _arena_r + Vector2(impact.x - _floor.x, impact.z - _floor.z).length() + 1.0
	get_parent().add_child(sh)
	sh.global_position = Vector3(impact.x, _floor.y + 0.08, impact.z)


func _tick_stun(delta: float, pl: Player) -> void:
	position.y = lerpf(position.y, _floor.y + 1.3, 1.0 - exp(-10.0 * delta))
	if _rings_left > 0:
		_ring_t -= delta
		if _ring_t <= 0.0:
			_rings_left -= 1
			_spawn_shock(Vector3(position.x, _floor.y, position.z))
	if pl != null and _inv <= 0.0 and pl.velocity.y < -1.0:
		var d := Vector2(pl.global_position.x - position.x, pl.global_position.z - position.z)
		var dy: float = pl.global_position.y - position.y
		if d.length() < 2.4 and dy > -0.6 and dy < 3.0:
			pl.stomp_bounce()
			_damage("stomp")
			return
	if _st > 6.5:
		world.toast("الحارس استعاد قوته!", VIOLET)
		_set_state(ST_RECOVER)


func _fire_bolt(pl: Player) -> void:
	var from: Vector3 = global_position + Vector3(0.0, -0.4, 0.0)
	var aim: Vector3 = pl.global_position + Vector3(0.0, 0.6, 0.0) - from
	var spread: float = 0.0
	if _phase() >= 1:
		spread = randf_range(-0.12, 0.12)
	aim = aim.rotated(Vector3.UP, spread)
	var spd: float = 9.0 + 1.5 * float(_phase())
	Sfx.play("shoot", -3.0, 0.8)
	Fx.burst(get_parent(), from, Color(1.0, 0.5, 0.9), 8, 4.0, 0.3, 0.3, 0.0)
	Enemies.fire(get_parent(), world, from, aim.normalized() * spd, Color(0.95, 0.4, 1.0), 5.0, 0.36)


func _tick_dead(delta: float) -> void:
	_dead_fx -= delta
	position.y += sin(_t * 30.0) * 0.02
	if _dead_fx <= 0.0:
		_dead_fx = 0.11
		var par: Node = get_parent()
		var p: Vector3 = global_position + Vector3(randf_range(-2.0, 2.0), randf_range(-1.5, 1.5), randf_range(-2.0, 2.0))
		Fx.burst(par, p, Color(1.0, 0.7, 1.0), 12, 7.0, 0.4, 0.6, -3.0)
		Sfx.play("enemy_pop", -6.0, randf_range(0.7, 1.1))
	if _st > 1.8:
		var par2: Node = get_parent()
		Fx.burst(par2, global_position, Color(1.0, 0.85, 1.0), 60, 14.0, 0.7, 1.2, -4.0)
		Fx.burst(par2, global_position, GOLD, 40, 10.0, 0.5, 1.0, -6.0)
		Fx.ring(par2, global_position, VIOLET, 16.0, 0.9, 3.5)
		Fx.ring(par2, Vector3(global_position.x, _floor.y, global_position.z), GOLD, 22.0, 1.1, 3.0)
		Sfx.play("boss_slam")
		Sfx.play("fanfare")
		world.shake(1.0)
		world.hitstop(0.2)
		world.add_coins(25, global_position)
		world.toast("تم هزيمة الحارس!", GOLD)
		world.boss_hud(0.0, false)
		world.unlock_goal()
		queue_free()


func _update_visuals() -> void:
	var col: Color = VIOLET
	var k: float = 1.6
	if _state == ST_STUN:
		col = GOLD
		k = 2.4 + 0.8 * sin(_t * 9.0)
	elif _state == ST_AIM or _state == ST_DIVE:
		col = Hazards.RED
		k = 2.2
	elif _state == ST_VOLLEY:
		col = Color(1.0, 0.5, 0.9)
		k = 2.0
	if _flash > 0.0:
		col = col.lerp(Color(1, 1, 1), _flash)
		k += 2.0 * _flash
	_core_mat.albedo_color = Zones.hdr(col, k)
	_light.light_color = col
	_shell.visible = not (_inv > 0.0 and int(_t * 14.0) % 2 == 0)
	# soft shadow on the arena floor
	var h: float = maxf(position.y - _floor.y, 0.0)
	var s: float = clampf(1.15 - h / 18.0, 0.4, 1.0)
	_shadow.global_position = Vector3(position.x, _floor.y + 0.05, position.z)
	_shadow.scale = Vector3(s, 1.0, s)
	_shadow_mat.set_shader_parameter("strength", 0.55 * s)


# ------------------------------------------------------------- shock-wave
## Flat expanding ring on the floor: touch it while on the ground and it hurts. Jump over it.
class Shock extends MeshInstance3D:
	var world: Node = null
	var center := Vector3.ZERO
	var floor_y: float = 0.0
	var speed: float = 10.0
	var max_r: float = 30.0
	var radius: float = 0.0
	var _mat: ShaderMaterial

	func _ready() -> void:
		var pm := PlaneMesh.new()
		pm.size = Vector2(max_r * 2.0, max_r * 2.0)
		mesh = pm
		_mat = ShaderMaterial.new()
		_mat.shader = Mats.shader("res://shaders/ring_fx.gdshader")
		_mat.set_shader_parameter("color", Color(0.85, 0.5, 1.0))
		_mat.set_shader_parameter("energy", 3.2)
		_mat.set_shader_parameter("width", 0.05)
		material_override = _mat
		cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	func _physics_process(delta: float) -> void:
		radius += speed * delta
		if radius >= max_r:
			queue_free()
			return
		# invert the ring shader's easing so the visible ring moves at constant speed
		var x: float = clampf((radius / max_r - 0.08) / 0.92, 0.0, 0.999)
		var p: float = 1.0 - pow(1.0 - x, 1.0 / 2.5)
		_mat.set_shader_parameter("progress", p)
		var pl: Player = Zones.player_of(world)
		if pl == null:
			return
		var d := Vector2(pl.global_position.x - center.x, pl.global_position.z - center.z)
		if absf(d.length() - radius) < 0.65 and pl.global_position.y < floor_y + 0.9:
			pl.hurt(Vector3(center.x, pl.global_position.y, center.z), 1)
