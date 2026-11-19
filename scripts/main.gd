extends Node
## Game flow: loading -> main menu (orbit camera) -> free roam / races.

var world: World
var player: Car
var cam: ChaseCamera
var traffic: TrafficManager
var race: RaceManager
var hud: HUD
var menus: Menus
var touch: TouchControls
var touch_layer: CanvasLayer
var fx_layer: CanvasLayer
var speed_fx: ColorRect
var input := PlayerInput.new()
var in_game := false
var _flip_t := 0.0
var _speed_amt := 0.0


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if _dev(args):
		return
	Game.main = self
	menus = Menus.new()
	add_child(menus)
	menus.show_loading()
	await get_tree().process_frame
	world = World.new()
	add_child(world)
	Game.world = world
	world.progress.connect(func(f, _l): menus.set_loading(f))
	await world.build_async()
	add_child(SkidMarks.new())
	traffic = TrafficManager.new()
	add_child(traffic)
	traffic.setup(world)
	race = RaceManager.new()
	add_child(race)
	race.setup(world)
	Game.race = race
	cam = ChaseCamera.new()
	add_child(cam)
	cam.current = true
	cam.mode = int(Game.settings.camera_mode) % 4
	Game.camera = cam
	_spawn_player(Game.selected_car, Game.selected_color, true)
	# HUD + touch
	hud = HUD.new()
	add_child(hud)
	hud.start_event_pressed.connect(_start_event)
	fx_layer = CanvasLayer.new()
	fx_layer.layer = 4
	add_child(fx_layer)
	speed_fx = ColorRect.new()
	speed_fx.set_anchors_preset(Control.PRESET_FULL_RECT)
	speed_fx.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sm := ShaderMaterial.new()
	sm.shader = load("res://shaders/speedlines.gdshader")
	speed_fx.material = sm
	fx_layer.add_child(speed_fx)
	touch_layer = CanvasLayer.new()
	touch_layer.layer = 6
	add_child(touch_layer)
	touch = TouchControls.new()
	touch_layer.add_child(touch)
	touch.action.connect(_on_touch_action)
	input.touch = touch
	menus.touch = touch
	race.message.connect(hud.show_message)
	race.finished.connect(_on_race_finished)
	_connect_menus()
	_to_menu()


func _dev(args: PackedStringArray) -> bool:
	if args.has("--game-test"):
		get_tree().create_timer(900.0).timeout.connect(func(): get_tree().quit(3))
		add_child(load("res://scripts/dev/game_test.gd").new())
		return false
	var tests := {"--terrain-test": "terrain_test", "--car-test": "car_test", "--col-test": "col_test", "--fx-test": "fx_test"}
	for a in tests:
		if args.has(a):
			get_tree().create_timer(420.0).timeout.connect(func(): get_tree().quit(3))
			add_child(load("res://scripts/dev/%s.gd" % tests[a]).new())
			return true
	return false


func _connect_menus() -> void:
	menus.free_roam.connect(_start_free_roam)
	menus.start_event.connect(_start_event)
	menus.travel_event.connect(_travel_event)
	menus.resume.connect(_resume)
	menus.restart.connect(func():
		_resume()
		race.restart())
	menus.quit_race.connect(func():
		_resume()
		race.end_event())
	menus.to_main_menu.connect(func():
		race.end_event()
		_to_menu())
	menus.car_changed.connect(func(id, c): _spawn_player(id, c, false))
	menus.layout_editing.connect(func(on):
		touch.visible = on or (in_game and _touch_wanted())
		if on:
			hud.visible = false)
	menus.settings_applied.connect(func(reload): if reload: _reload_world())


func _touch_wanted() -> bool:
	return Game.is_mobile or DisplayServer.is_touchscreen_available() or OS.get_cmdline_user_args().has("--touch")


# --------------------------------------------------------------------------- player
func _spawn_player(id: String, color_idx: int, initial: bool) -> void:
	var pos: Vector3
	var yaw := 0.0
	if player and is_instance_valid(player):
		pos = player.global_position
		yaw = player.global_rotation.y
		world.unregister_vehicle(player)
		traffic.physics_cars.erase(player)
		player.queue_free()
	else:
		var sp: Dictionary = world.data.json.spawn
		pos = Vector3(sp.pos[0], sp.pos[1], sp.pos[2])
		yaw = float(sp.yaw)
	var cols: Array = Game.CARS[id].colors
	player = Car.new()
	add_child(player)
	player.setup(id, cols[clampi(color_idx, 0, cols.size() - 1)], world, true)
	player.controller = input
	player.set_meta("near_player", true)
	player.place(pos + Vector3(0, 0.4, 0), yaw)
	Game.player = player
	player.crashed.connect(func(imp: float, _p: Vector3, _o: Object):
		var sev := clampf(imp / (player.mass * 10.0), 0.0, 1.0)
		cam.add_shake(sev * 0.8)
		if imp > player.mass * 16.0 and in_game:
			cam.slowmo(0.4, 0.5))
	world.register_vehicle(player)
	traffic.physics_cars.append(player)
	cam.set_target(player)


func _respawn_player() -> void:
	if race.state != RaceManager.IDLE and race.route:
		var r := race.route
		var i := r.nearest(player.global_position, race.player_entry.get("idx", 0), 30, 30)
		var t := r.tangents[i]
		player.place(r.pts[i] + Vector3(0, 0.8, 0), atan2(-t.x, -t.z))
	else:
		player.respawn_on_road()
	cam.set_target(player)


# --------------------------------------------------------------------------- flow
func _to_menu() -> void:
	in_game = false
	get_tree().paused = false
	hud.visible = false
	touch.visible = false
	player.controls_locked = true
	cam.orbit = true
	menus.show_main()


func _start_free_roam() -> void:
	menus.clear()
	in_game = true
	cam.orbit = false
	cam.set_target(player)
	player.controls_locked = false
	hud.visible = true
	touch.visible = _touch_wanted()
	touch.release_all()


func _start_event(e: Dictionary) -> void:
	_start_free_roam()
	if e.has("route"):
		race.start_event(e)
	else:
		# challenge: move to its start first
		var p := Vector3(e.pos[0], e.pos[1], e.pos[2])
		var d := Vector3(e.dir[0], 0, e.dir[1])
		player.place(p + Vector3(0, 0.6, 0), atan2(-d.x, -d.z))
		race.start_event(e)
	cam.set_target(player)


func _travel_event(e: Dictionary) -> void:
	_start_free_roam()
	race.end_event()
	var p: Vector3
	var d: Vector3
	if e.has("route"):
		var r := RaceRoute.from_event(e)
		var sl := race._grid_slot(r, e, RaceManager.PLAYER_SLOT)
		p = sl[0]
		d = sl[1]
	else:
		p = Vector3(e.pos[0], e.pos[1], e.pos[2])
		d = Vector3(e.dir[0], 0, e.dir[1])
	traffic.clear_all()
	player.place(p + Vector3(0, 0.6, 0) - d * 12.0, atan2(-d.x, -d.z))
	cam.set_target(player)


func _pause() -> void:
	if not in_game or menus.is_open():
		return
	get_tree().paused = true
	Engine.time_scale = 1.0
	touch.release_all()
	touch.visible = false
	hud.visible = false
	menus.show_pause()


func _resume() -> void:
	menus.clear()
	get_tree().paused = false
	hud.visible = true
	touch.visible = _touch_wanted()
	touch.release_all()


func _on_race_finished(results: Array, busted: bool) -> void:
	touch.release_all()
	touch.visible = false
	menus.show_results(results, busted)


func _on_touch_action(n: String) -> void:
	match n:
		"pause":
			_pause()
		"camera":
			cam.cycle_mode()
		"reset":
			_respawn_player()


func _reload_world() -> void:
	# graphics changes that need a rebuild: simplest robust path is a scene reload
	Game.save_game()
	get_tree().paused = false
	Engine.time_scale = 1.0
	get_tree().reload_current_scene()


# --------------------------------------------------------------------------- per frame
func _unhandled_input(event: InputEvent) -> void:
	if not in_game:
		return
	if event.is_action_pressed("pause"):
		if get_tree().paused:
			_resume()
		else:
			_pause()
	elif event.is_action_pressed("camera"):
		cam.cycle_mode()
	elif event.is_action_pressed("reset_car"):
		_respawn_player()


func _process(_delta: float) -> void:
	if player == null or cam == null:
		return
	cam.look_back = (Input.is_action_pressed("look_back") or (touch and touch.look_back)) and in_game
	var amt := 0.0
	if in_game:
		amt = clampf((player.speed_abs - 55.0) / 30.0, 0.0, 0.6) + (0.7 if player.nitro_active else 0.0)
	var m := speed_fx.material as ShaderMaterial
	_speed_amt = lerpf(_speed_amt, amt, 0.08)
	m.set_shader_parameter("amount", _speed_amt)
	speed_fx.visible = _speed_amt > 0.01 and Game.settings.quality > 0


func _physics_process(dt: float) -> void:
	if not in_game or player == null:
		return
	# auto-recover when flipped or drowned
	if player.upside_timer > 2.5 or player.in_water:
		_flip_t += dt
		if _flip_t > 1.5:
			_flip_t = 0.0
			_respawn_player()
	else:
		_flip_t = 0.0
	# camera shake from crashes
	if player.damage > 0.0 and Engine.get_physics_frames() % 2 == 0:
		pass
