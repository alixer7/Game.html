extends Node
## Entry point: builds the stadium, UI and handles game flow
## (menu demo match -> real match / free play -> results).

var stage: Node3D
var world: SimWorld
var arena: ArenaView
var ball_view: BallView
var camera: CameraRig
var fx: FxLayer
var hud: Hud
var touch: TouchControls
var menus: MenuSystem
var hud_layer: CanvasLayer
var menu_layer: CanvasLayer
var match_ctrl: MatchController
var in_menu := true
var _last_cfg := {}
var _orbit := false


func _ready() -> void:
	PlayerController.setup_input_map()
	process_mode = Node.PROCESS_MODE_ALWAYS

	stage = Node3D.new()
	stage.name = "Stage"
	stage.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(stage)
	world = SimWorld.new()
	world.name = "SimWorld"
	stage.add_child(world)
	arena = ArenaView.new()
	arena.name = "Arena"
	stage.add_child(arena)
	arena.build(world)
	ball_view = BallView.new()
	stage.add_child(ball_view)
	ball_view.setup(world.ball)
	fx = FxLayer.new()
	stage.add_child(fx)
	camera = CameraRig.new()
	stage.add_child(camera)

	hud_layer = CanvasLayer.new()
	hud_layer.layer = 1
	hud_layer.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(hud_layer)
	hud = Hud.new()
	hud_layer.add_child(hud)
	touch = TouchControls.new()
	hud_layer.add_child(touch)
	touch.pause_pressed.connect(_pause)
	touch.ballcam_toggled.connect(func(): camera.ball_cam = touch.ball_cam)
	touch.reset_pressed.connect(func():
		if match_ctrl:
			match_ctrl.reset_ball_freeplay())

	menu_layer = CanvasLayer.new()
	menu_layer.layer = 5
	add_child(menu_layer)
	menus = MenuSystem.new()
	menu_layer.add_child(menus)
	menus.start_match.connect(_start_match)
	menus.start_freeplay.connect(_start_freeplay)
	menus.resume_requested.connect(_resume)
	menus.restart_requested.connect(_restart)
	menus.main_menu_requested.connect(_to_menu)
	menus.tutorial_closed.connect(func():
		menus.hide_all()
		get_tree().paused = false)

	Settings.changed.connect(_apply_settings)
	_apply_settings()
	_to_menu()


func _apply_settings() -> void:
	camera.apply_settings(Settings.data)
	arena.set_quality(int(Settings.get_value("quality", 2)))
	var q := int(Settings.get_value("quality", 2))
	get_viewport().msaa_3d = Viewport.MSAA_2X if q >= 2 else Viewport.MSAA_DISABLED
	get_viewport().scaling_3d_scale = 1.0 if q >= 1 else 0.75
	Settings.apply_runtime()


# ------------------------------------------------------------------ flow

func _clear_match() -> void:
	if match_ctrl:
		match_ctrl.teardown()
		match_ctrl.queue_free()
		match_ctrl = null
	world.goal_enabled = true


func _new_match(cfg: Dictionary) -> void:
	_clear_match()
	match_ctrl = MatchController.new()
	match_ctrl.name = "Match"
	match_ctrl.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(match_ctrl)
	match_ctrl.setup(self, world, cfg)
	match_ctrl.ended.connect(_on_match_ended)
	hud.set_scores(0, 0)
	hud.hide_big()
	hud.set_replay(false)


func _to_menu() -> void:
	get_tree().paused = false
	in_menu = true
	_new_match({"demo": true, "size": 2, "difficulty": 1, "minutes": 0})
	hud.visible = false
	touch.visible = false
	touch.enabled = false
	menus.show_page("main")
	Sfx.play_music(true)
	Sfx.crowd(true, -22.0)


func _start_match(cfg: Dictionary) -> void:
	in_menu = false
	_last_cfg = cfg
	_new_match(cfg)
	_enter_play()


func _start_freeplay() -> void:
	in_menu = false
	_last_cfg = {"freeplay": true, "size": 1, "minutes": 0, "team": 0}
	_new_match(_last_cfg)
	_enter_play()


func _enter_play() -> void:
	menus.hide_all()
	hud.visible = true
	hud.score_box.get_parent().visible = not match_ctrl.is_freeplay()
	touch.visible = true
	touch.enabled = true
	touch.show_reset = match_ctrl.is_freeplay()
	touch.ball_cam = bool(Settings.get_value("ball_cam", true))
	camera.ball_cam = touch.ball_cam
	camera.mode = CameraRig.Mode.CAR
	Sfx.play_music(false)
	Sfx.crowd(true, -14.0)
	if not Settings.get_value("tutorial_seen", false):
		menus.show_page("tutorial")
		get_tree().paused = true


func _restart() -> void:
	get_tree().paused = false
	if _last_cfg.is_empty():
		_to_menu()
		return
	if _last_cfg.get("freeplay", false):
		_start_freeplay()
	else:
		_start_match(_last_cfg)


func _pause() -> void:
	if in_menu or match_ctrl == null:
		return
	if match_ctrl.state == MatchController.State.ENDED:
		return
	get_tree().paused = true
	touch.reset_state()
	menus.show_page("pause")


func _resume() -> void:
	menus.hide_all()
	get_tree().paused = false


func _on_match_ended(results: Dictionary) -> void:
	touch.enabled = false
	await get_tree().create_timer(2.2).timeout
	if match_ctrl and match_ctrl.state == MatchController.State.ENDED:
		menus.show_end(results)


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT or what == NOTIFICATION_APPLICATION_PAUSED:
		if not in_menu and not get_tree().paused:
			_pause()
	elif what == NOTIFICATION_WM_GO_BACK_REQUEST:
		if in_menu:
			if menus.current != "main":
				menus.show_page("main")
		elif get_tree().paused:
			_resume()
		else:
			_pause()


func _input(event: InputEvent) -> void:
	# any tap or key skips a goal replay
	if match_ctrl and match_ctrl.state == MatchController.State.REPLAY and not get_tree().paused:
		if (event is InputEventScreenTouch and event.pressed) or (event is InputEventKey and event.pressed):
			match_ctrl.skip_replay()
			get_viewport().set_input_as_handled()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("p_pause"):
		if get_tree().paused and menus.current == "pause":
			_resume()
		else:
			_pause()
	elif event.is_action_pressed("p_ballcam") and not in_menu:
		touch.ball_cam = not touch.ball_cam
		camera.ball_cam = touch.ball_cam



# ------------------------------------------------------------------ frame

func _process(delta: float) -> void:
	if match_ctrl == null or get_tree().paused:
		return
	var now := Time.get_ticks_msec() / 1000.0
	var alpha := Engine.get_physics_interpolation_fraction()
	if get_tree().paused:
		alpha = 1.0
	var m := match_ctrl
	var ball_pos := world.ball.prev_pos.lerp(world.ball.pos, alpha)
	if m.state == MatchController.State.REPLAY:
		ball_pos = m.apply_replay(camera, delta, now)
		var bv := m.replay_ball_vel()
		var remaining := m._replay_len - m._replay_t
		if remaining < 1.5:
			camera.goal_view(Phys.own_goal_z(1 - int(m.last_goal.get("team", 0))), ball_pos, delta)
		else:
			camera.track(ball_pos, bv, delta, 1.0)
	else:
		for v in m.views:
			v.update_visual(alpha, camera, delta, now)
		ball_view.update_visual(alpha, camera, delta, now)
		_update_camera(delta, ball_pos)
	m.update_audio()
	# HUD
	if not in_menu:
		hud.camera = camera
		hud.ball_pos = ball_pos
		hud.show_ball_indicator = ball_view.visible and m.state != MatchController.State.REPLAY
		if m.player_car:
			touch.boost_amount = m.player_car.boost
		if m.overtime:
			hud.set_time(m.ot_time, true)
		else:
			hud.set_time(m.time_left, false, m.unlimited_time())


func _update_camera(delta: float, ball_pos: Vector3) -> void:
	var m := match_ctrl
	var car := m.player_car
	if in_menu or car == null:
		# cinematic coverage of the demo match
		camera.track(ball_pos, world.ball.vel, delta, 1.0)
		return
	if m.state == MatchController.State.ENDED:
		camera.orbit(car.pos + Vector3(0, 0.5, 0), 7.0, 2.5, 0.35, delta)
		return
	if car.demolished:
		camera.track(ball_pos, world.ball.vel, delta, -1.0)
		return
	var alpha := Engine.get_physics_interpolation_fraction()
	var p := car.prev_pos.lerp(car.pos, alpha)
	var q := car.prev_quat.slerp(car.basis.get_rotation_quaternion(), alpha)
	var target_ball := ball_pos
	if not ball_view.visible:
		target_ball = Vector3(0, 1, Phys.own_goal_z(1 - car.team))
	camera.follow(p, Basis(q), car.vel, car.num_contacts >= 3, target_ball, car.boosting, car.supersonic, delta)
