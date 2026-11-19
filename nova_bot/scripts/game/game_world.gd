class_name GameWorld
extends Node3D
## Gameplay screen. Loads a level JSON, spawns player / camera / HUD / touch controls and runs the rules
## (coins, rescue bots, checkpoints, respawn, pause, level result).
## Level objects call into this node dynamically (`world.add_coins(...)`, `world.time`, ...), so every
## public member below is part of the contract used by scripts/game/objects/*.gd and player.gd.

var level_id: int = 1

# --- public state read by level objects
var player: Player
var rig: CameraRig
var goal: Node = null           # GoalPortal registers itself here
var time: float = 0.0           # world clock for animated objects (keeps running at the result screen)

var _meta: Dictionary = {}
var _data: Dictionary = {}
var _level_root: Node3D
var _hud: Hud
var _touch: TouchControls
var _abyss: MeshInstance3D
var _kill_y: float = -40.0
var _cp_pos := Vector3.ZERO
var _cp_yaw: float = 0.0
var _coins: int = 0
var _coin_total: int = 0
var _bots: Array = [false, false, false]
var _run_time: float = 0.0
var _switches: Dictionary = {}
var _finished: bool = false
var _respawning: bool = false
var _boss_on: bool = false
var _base_music: String = "music_world1"
var _hitstop_until: int = 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE
	_meta = Game.level_meta(level_id)
	var theme_id: String = str(_meta.get("theme", "launch"))
	Mats.clear()
	Mats.theme = EnvBuilder.theme(theme_id)

	_level_root = Node3D.new()
	_level_root.name = "Level"
	add_child(_level_root)
	_data = LevelLoader.load_level(self, _level_root, str(_meta.get("file", "")))
	if _data.is_empty():
		_data = _fallback_level()

	_kill_y = float(_data.get("kill_y", -40.0))
	var spawn: Vector3 = LevelLoader.vec(_data.get("spawn"), Vector3(0.0, 2.0, 0.0))
	var yaw: float = -deg_to_rad(float(_data.get("yaw", 0.0)))
	_cp_pos = spawn
	_cp_yaw = yaw
	_coin_total = int(_data.get("_coin_total", 0))

	var center: Vector3 = _data.get("_center", Vector3.ZERO)
	var extent: float = float(_data.get("_extent", 60.0))
	var env: Dictionary = EnvBuilder.build(self, theme_id, center, _kill_y, extent)
	_abyss = env["abyss"]

	player = Player.new()
	player.world = self
	add_child(player)
	player.respawn(spawn, yaw)

	rig = CameraRig.new()
	rig.player = player
	rig.yaw = yaw
	var cdef: Variant = _data.get("cam")
	if cdef is Dictionary:
		var cd: Dictionary = cdef
		rig.dist = float(cd.get("dist", rig.dist))
		rig.pitch = float(cd.get("pitch", rig.pitch))
	add_child(rig)
	rig.snap()
	var motes: CPUParticles3D = EnvBuilder.make_motes(theme_id)
	rig.cam.add_child(motes)

	_hud = Hud.new()
	add_child(_hud)
	_hud.resume_pressed.connect(_resume)
	_hud.restart_pressed.connect(_restart)
	_hud.menu_pressed.connect(_to_menu)
	_hud.next_pressed.connect(_next)
	_hud.set_coins(0, _coin_total)
	_hud.set_bots(_bots)
	_hud.set_hp(player.hp, player.max_hp)
	player.hp_changed.connect(_hud.set_hp)
	player.died.connect(_on_died)

	var touch_layer := CanvasLayer.new()
	touch_layer.layer = 5
	add_child(touch_layer)
	_touch = TouchControls.new()
	touch_layer.add_child(_touch)
	_touch.pause_pressed.connect(_pause)
	_touch.camera_drag.connect(rig.add_drag)

	_base_music = str(_meta.get("music", "music_world1"))
	if bool(_meta.get("boss", false)):
		_base_music = "music_world3"
	Sfx.play_music(_base_music)
	_hud.show_title(str(_meta.get("name", "")), str(_meta.get("desc", "")))


func _fallback_level() -> Dictionary:
	var slab := Platforms.Solid.new()
	slab.world = self
	slab.setup({"t": "box", "p": [0, 0, 0], "s": [24, 1, 24], "c": 0})
	_level_root.add_child(slab)
	return {"spawn": [0, 1, 0], "yaw": 0, "kill_y": -30}


func _exit_tree() -> void:
	Engine.time_scale = 1.0


# ------------------------------------------------------------------ frame
func _physics_process(delta: float) -> void:
	time += delta
	if player == null or rig == null:
		return
	if not _finished:
		_run_time += delta
	player.cam_yaw = rig.yaw
	for k in _switches.keys():
		_switches[k] = float(_switches[k]) - delta
	if player.alive and not _finished and player.global_position.y < _kill_y:
		player.kill()


func _process(_delta: float) -> void:
	if player == null or _hud == null:
		return
	_hud.set_time(_run_time)
	_touch.hover_ratio = player.hover_ratio()
	_touch.dash_ratio = player.dash_ratio()
	EnvBuilder.follow_abyss(_abyss, rig.cam.global_position)
	if Engine.time_scale < 1.0 and Time.get_ticks_msec() >= _hitstop_until:
		Engine.time_scale = 1.0


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_PAUSED or what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		if _hud != null and not _finished:
			_pause()


func on_back() -> void:
	if _hud == null or _finished:
		return
	if _hud.close_settings_if_open():
		return
	if _hud.is_pause_open():
		_resume()
	else:
		_pause()


# -------------------------------------------------------------- pause etc.
func _pause() -> void:
	if _finished or _hud.is_pause_open():
		return
	Engine.time_scale = 1.0
	get_tree().paused = true
	Sfx.set_muffled(true)
	_touch.release_all()
	_touch.set_active(false)
	_hud.show_pause()


func _resume() -> void:
	_hud.hide_pause()
	get_tree().paused = false
	Sfx.set_muffled(false)
	_touch.set_active(true)


func _restart() -> void:
	Game.main.start_level(level_id)


func _to_menu() -> void:
	Game.main.go_menu("levels")


func _next() -> void:
	if level_id < Game.level_count():
		Game.main.start_level(level_id + 1)
	else:
		Game.main.go_menu("levels")


# ------------------------------------------------------- death / respawn
func _on_died() -> void:
	if _finished or _respawning:
		return
	_respawning = true
	_touch.release_all()
	var tw := create_tween()
	tw.tween_interval(0.85)
	tw.tween_callback(_hud.fade.bind(1.0, 0.3))
	tw.tween_interval(0.42)
	tw.tween_callback(_do_respawn)


func _do_respawn() -> void:
	player.respawn(_cp_pos, _cp_yaw)
	rig.yaw = _cp_yaw
	rig.snap()
	_hud.fade(0.0, 0.35)
	_respawning = false


# ----------------------------------------------------- API used by objects
func add_coins(n: int, at: Vector3) -> void:
	_coins += n
	_coin_total = maxi(_coin_total, _coins)
	_hud.set_coins(_coins, _coin_total)
	if n >= 2:
		Fx.popup(_level_root, at + Vector3(0.0, 0.8, 0.0), "+" + str(n), Color(1.0, 0.85, 0.35), 64)


func collect_bot(i: int, _at: Vector3) -> void:
	var idx: int = clampi(i, 0, 2)
	_bots[idx] = true
	_hud.set_bots(_bots)
	_hud.toast("تم إنقاذ صديق!", Collectibles.BOT_COLORS[idx])
	rig.shake(0.25)
	_hud.flash(Collectibles.BOT_COLORS[idx], 0.25)


func set_checkpoint(pos: Vector3, yaw_deg: float) -> void:
	_cp_pos = pos + Vector3(0.0, 0.15, 0.0)
	_cp_yaw = -deg_to_rad(yaw_deg)
	_hud.toast("تم حفظ التقدّم", Color(0.35, 1.0, 0.6))


func activate_switch(id: String, dur: float) -> void:
	_switches[id] = dur if dur > 0.0 else 1.0e9


func is_switch_on(id: String) -> bool:
	return float(_switches.get(id, 0.0)) > 0.0


func switch_left(id: String) -> float:
	return maxf(float(_switches.get(id, 0.0)), 0.0)


func unlock_goal() -> void:
	if goal != null and is_instance_valid(goal):
		goal.call("unlock")


func hint(txt: String) -> void:
	_hud.show_hint(txt)


func toast(txt: String, col: Color = Color(0.25, 0.9, 1.0)) -> void:
	_hud.toast(txt, col)


func shake(amount: float) -> void:
	if rig != null:
		rig.shake(amount)


func hitstop(sec: float) -> void:
	if get_tree().paused or _finished:
		return
	Engine.time_scale = 0.06
	_hitstop_until = maxi(_hitstop_until, Time.get_ticks_msec() + int(sec * 1000.0))


func boss_hud(ratio: float, vis: bool) -> void:
	_hud.set_boss(ratio, vis)
	if vis != _boss_on:
		_boss_on = vis
		Sfx.play_music("music_boss" if vis else _base_music)


# ----------------------------------------------------------- level end
func complete() -> void:
	if _finished:
		return
	_finished = true
	Engine.time_scale = 1.0
	_touch.release_all()
	_touch.set_active(false)
	player.celebrate()
	Sfx.play("goal")
	Game.vibrate(150)
	_hud.flash(Color(0.6, 0.9, 1.0), 0.55)
	rig.shake(0.3)
	var tw := create_tween()
	tw.tween_interval(0.35)
	tw.tween_callback(Sfx.play.bind("fanfare"))
	tw.tween_interval(1.5)
	tw.tween_callback(_show_result)


func _show_result() -> void:
	var prev: Dictionary = Game.level_record(level_id)
	var is_record: bool = (not bool(prev.get("done", false))) or _run_time < float(prev.get("time", 0.0))
	Game.record_result(level_id, _bots, _coins, _run_time)
	var info: Dictionary = {
		"name": str(_meta.get("name", "")),
		"bots": _bots,
		"coins": _coins,
		"coin_total": _coin_total,
		"time": _run_time,
		"record": is_record,
		"has_next": level_id < Game.level_count(),
	}
	_hud.show_result(info)
