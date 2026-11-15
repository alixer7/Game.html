extends Node
## المشهد الرئيسي: يبني العالم ويدير القوائم والمباراة.
## أوضاع الاختبار (بعد "--"):
##   --autotest [--l0=2 --l1=2 --matches=4 --surface=0 --log]   مباريات آلية سريعة بلا رسوم
##   --shots=60,300 --shotdir=/tmp/x [--human --surface=1 --cam=0 --ui]   لقطات شاشة
##   --poses=fh|bh|serve|toss|run|ready                          لوحة وضعيات الأنيميشن

var world: Node3D
var arena: Arena
var cam_rig: CameraRig
var game: TennisMatch
var ball: TennisBall
var players: Array[TennisPlayer] = []
var controllers: Array = []
var hud: Hud
var menus: Menus
var human_ctrl: HumanController
var names: Array = ["اللاعب", "الخصم"]
var _arena_key := ""
var _autotest := false
var _log_points := false
var _shot_frames: Array = []
var _shot_dir := ""
var _frame := 0
var _pose_name := ""
var _pose_prof := "samer"
var _shot_ui := false


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if "--autotest" in args:
		_autotest = true
		_run_autotest(args)
		return
	for a in args:
		if a.begins_with("--shots="):
			for f in a.split("=")[1].split(","):
				_shot_frames.append(int(f))
		if a.begins_with("--shotdir="):
			_shot_dir = a.split("=")[1]
	for a in args:
		if a.begins_with("--poses="):
			_run_poses(a.split("=")[1])
			return
	for a in args:
		if a.begins_with("--anim="):
			_run_anim(a.split("=")[1])
			return
	if "--play" in args:
		# المسار الحقيقي كاملاً (قائمة ← مباراة) بإصبع آلي — للاختبار
		for a in args:
			if a.begins_with("--surface="): Settings.data["surface"] = int(a.split("=")[1])
			if a.begins_with("--level="): Settings.data["difficulty"] = int(a.split("=")[1])
			if a.begins_with("--cam="): Settings.data["camera"] = int(a.split("=")[1])
			if a.begins_with("--camh="): Settings.data["cam_height"] = int(a.split("=")[1])
			if a.begins_with("--camz="): Settings.data["cam_zoom"] = int(a.split("=")[1])
			if a.begins_with("--quality="): Settings.data["quality"] = int(a.split("=")[1])
			if a.begins_with("--fbskill="): _fb_sigma = float(a.split("=")[1])
			if a.begins_with("--p0="): Settings.data["player_id"] = a.split("=")[1]
			if a.begins_with("--p1="): Settings.data["opponent_id"] = a.split("=")[1]
			if a.begins_with("--wind="): Settings.data["wind"] = int(a.split("=")[1])
		Settings.data["assist"] = 2
		Settings.data["games"] = 3
		_boot()
		_fingerbot_on = true
		_start_match()
		return
	if not _shot_frames.is_empty():
		_run_shots(args)
		return
	_boot()


# =====================================================================
#  التشغيل العادي
# =====================================================================
func _boot() -> void:
	menus = Menus.new()
	add_child(menus)
	menus.start_requested.connect(_start_match)
	menus.resume_requested.connect(_resume)
	menus.restart_requested.connect(_restart)
	menus.quit_requested.connect(_quit_to_menu)
	menus.settings_changed.connect(_apply_settings)
	_ensure_arena(int(Settings.get_v("surface")), int(Settings.get_v("quality")))
	cam_rig.mode = CameraRig.Mode.ORBIT
	menus.show_main()
	Sfx.ambience(true)


func _ensure_arena(surface: int, quality: int) -> void:
	var key := "%d_%d" % [surface, quality]
	if key == _arena_key and arena != null:
		arena.clear_marks()
		return
	if arena != null:
		arena.queue_free()
	if cam_rig != null:
		cam_rig.queue_free()
	_arena_key = key
	build_world(surface, quality)


func build_world(surface: int, quality: int) -> void:
	arena = Arena.new()
	add_child(arena)
	arena.build(surface, quality)
	cam_rig = CameraRig.new()
	add_child(cam_rig)
	cam_rig.arena = arena
	var scale3d := [0.7, 0.85, 1.0][clampi(quality, 0, 2)] as float
	get_viewport().scaling_3d_scale = scale3d
	get_viewport().msaa_3d = Viewport.MSAA_DISABLED if quality == 0 else Viewport.MSAA_2X


func _clear_match() -> void:
	if hud != null:
		hud.queue_free()
		hud = null
	if world != null:
		world.queue_free()
		world = null
	players = []
	controllers = []
	human_ctrl = null
	game = null
	ball = null


func build_match(human: bool, p0_id: String, p1_id: String, level0: int, level1: int, surface: int) -> void:
	world = Node3D.new()
	add_child(world)
	ball = TennisBall.new()
	ball.surf = Court.SURFACES[surface]
	if arena != null:
		ball.sun_dir = arena.sun_dir()
	world.add_child(ball)
	game = TennisMatch.new()
	world.add_child(game)
	for i in 2:
		var p := TennisPlayer.new()
		world.add_child(p)
		var prof: Dictionary = PlayerProfile.get_profile(p0_id if i == 0 else p1_id)
		var lvl: int = level0 if i == 0 else level1
		var off: float = 0.0 if (human and i == 0) else float(AIController.LEVELS[lvl]["offset"])
		p.setup(i, 1 if i == 0 else -1, prof, off, ball, game, human and i == 0)
		players.append(p)
	game.setup(ball, players[0], players[1], surface)
	game.wind_mode = int(Settings.get_v("wind"))
	names = [players[0].display_name, players[1].display_name]
	for i in 2:
		if human and i == 0:
			continue
		var ai := AIController.new()
		world.add_child(ai)
		ai.setup(players[i], players[1 - i], game, level0 if i == 0 else level1)
		controllers.append(ai)


func _start_match() -> void:
	get_tree().paused = false
	menus.hide_all()
	_clear_match()
	var surface := int(Settings.get_v("surface"))
	var level := int(Settings.get_v("difficulty"))
	_ensure_arena(surface, int(Settings.get_v("quality")))
	build_match(true, str(Settings.get_v("player_id")), str(Settings.get_v("opponent_id")), 0, level, surface)
	hud = Hud.new()
	add_child(hud)
	hud.bind(game, players[0], names)
	hud.pause_pressed.connect(_pause)
	human_ctrl = HumanController.new()
	world.add_child(human_ctrl)
	human_ctrl.setup(players[0], game, hud.pad, hud.qte, world)
	_wire_feedback()
	_apply_settings()
	cam_rig.player = players[0]
	cam_rig.ball = ball
	cam_rig.snap()
	game.match_finished.connect(_on_match_finished)
	game.start_match(int(Settings.get_v("sets")), int(Settings.get_v("games")), randi() % 2)
	if not bool(Settings.get_v("tutorial_seen")):
		Settings.set_v("tutorial_seen", true)
		hud.show_hint("اسحب يساراً للحركة • اضغط زر الضربة مطوّلاً لشحن القوة ووجّه بالعصا • أفلِت عندما يكون مؤشر التوقيت فوق اللاعب في الأخضر", 7.0)


func _refresh_board() -> void:
	if arena != null and game != null:
		arena.update_scoreboard(names, game.rules, game.server())


func _wire_feedback() -> void:
	game.score_changed.connect(_refresh_board)
	game.point_started.connect(func(_s: int, _sec: bool) -> void: _refresh_board())
	game.sides_changed.connect(func() -> void:
		arena.clear_marks()
		if cam_rig != null:
			cam_rig.snap())
	game.ball_hit.connect(_on_ball_hit)
	game.serve_speed.connect(arena.show_serve_speed)
	game.call_made.connect(_on_call_fx)
	game.bounce_mark.connect(func(pos: Vector3, _good: bool) -> void: arena.add_mark(pos, ball.st.bounce_speed))


func _apply_settings() -> void:
	Sfx.refresh_volume()
	if players.size() > 0 and players[0] != null and players[0].is_human:
		players[0].assist = int(Settings.get_v("assist"))
	if ball != null:
		ball.set_visual_scale(float(Settings.get_v("ball_scale")))
	if cam_rig != null and game != null:
		cam_rig.mode = CameraRig.Mode.BROADCAST
	if cam_rig != null:
		cam_rig.height_k = clampf(float(Settings.get_v("cam_height")) / 100.0, 0.0, 1.0)
		cam_rig.zoom_k = clampf(float(Settings.get_v("cam_zoom")) / 100.0, 0.0, 1.0)


func _on_ball_hit(info: Dictionary) -> void:
	var sp: float = info["speed"]
	var vol := clampf(0.45 + sp / 60.0, 0.4, 1.3)
	var t: int = info["type"]
	if info["serve"]:
		Sfx.play("hit_serve", vol, randf_range(0.96, 1.04))
	elif bool(info.get("frame", false)):
		Sfx.play("hit_frame", 0.9, randf_range(0.95, 1.05))
	elif t == Shot.Type.SLICE or t == Shot.Type.DROP:
		Sfx.play("hit_slice", vol, randf_range(0.95, 1.05))
	elif t == Shot.Type.TOPSPIN or t == Shot.Type.LOB:
		Sfx.play("hit_topspin", vol, randf_range(0.95, 1.05))
	else:
		Sfx.play("hit_flat", vol, randf_range(0.95, 1.05))


func _on_call_fx(kind: String, data: Dictionary) -> void:
	match kind:
		"bounce":
			var sp: float = data["speed"]
			var key: String = ["bounce_hard", "bounce_clay", "bounce_grass"][int(Settings.get_v("surface"))]
			Sfx.play(key, clampf(0.25 + sp / 45.0, 0.2, 1.0), randf_range(0.94, 1.06))
		"net_touch":
			Sfx.play("net", 0.9)
		"ace", "winner":
			Sfx.play_crowd("applause_big", 1.0)
			arena.cheer(1.0)
		"out", "net", "double_fault":
			var long_rally: bool = int(data.get("rally", 0)) >= 7
			Sfx.play_crowd("applause_big" if long_rally else "applause", 0.9 if long_rally else 0.7)
			arena.cheer(0.9 if long_rally else 0.55)
			if kind != "net":
				Sfx.play("call_out", 0.8)
		"fault":
			Sfx.play("call_out", 0.8)
			Sfx.play_crowd("ooh", 0.5)
		"let":
			Sfx.play("call_out", 0.6)


func _on_match_finished(winner: int) -> void:
	if _fingerbot_on:
		var s0: Dictionary = game.stats[0]
		var s1: Dictionary = game.stats[1]
		print("PLAY RESULT winner=", winner, " sets=", game.rules.set_history, " pts=", s0["points"], "-", s1["points"], " human: aces=", s0["aces"], " df=", s0["double_faults"], " win=", s0["winners"], " ue=", s0["unforced"], " fe=", s0["forced"],
			" 1st%=", int(100.0 * s0["first_in"] / maxf(s0["first_total"], 1)), " | ai: aces=", s1["aces"], " df=", s1["double_faults"], " win=", s1["winners"], " ue=", s1["unforced"], " fe=", s1["forced"], " rally=", snappedf(float(s0["rally_sum"]) / maxf(s0["points"] + s1["points"], 1), 0.1))
		if DisplayServer.get_name() == "headless":
			get_tree().quit()
			return
	Settings.set_v("matches", int(Settings.get_v("matches")) + 1)
	if winner == 0:
		Settings.set_v("wins", int(Settings.get_v("wins")) + 1)
	Sfx.play_crowd("applause_big", 1.0)
	arena.cheer(1.0)
	if hud != null:
		hud.pad.enabled = false
		hud.pad.queue_redraw()
	await get_tree().create_timer(2.2).timeout
	if game != null:
		menus.show_result(game, names, 0)


func _pause() -> void:
	if game == null or game.phase == TennisMatch.Phase.MATCH_OVER:
		return
	get_tree().paused = true
	if hud != null:
		hud.pad.reset()
	menus.show_pause()


func _resume() -> void:
	menus.hide_all()
	get_tree().paused = false


func _restart() -> void:
	get_tree().paused = false
	_start_match()


func _quit_to_menu() -> void:
	get_tree().paused = false
	_clear_match()
	cam_rig.player = null
	cam_rig.mode = CameraRig.Mode.ORBIT
	menus.show_main()


func _notification(what: int) -> void:
	# إيقاف مؤقت تلقائي عند خروج التطبيق للخلفية
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT or what == NOTIFICATION_WM_GO_BACK_REQUEST:
		if game != null and menus != null and menus.current == "" and not get_tree().paused:
			_pause()


# =====================================================================
#  أوضاع الاختبار
# =====================================================================
## لوحة وضعيات للفحص البصري: عدة لاعبين مجمّدين عند أزمنة مختلفة من الحركة
func _run_poses(which: String) -> void:
	build_world(0, 0)
	var times: Array = []
	var clip := -1
	if which.contains(":"):
		_pose_prof = which.split(":")[1]
		which = which.split(":")[0]
	match which:
		"fh": clip = PlayerRig.Clip.FH_DRIVE; times = [-0.24, -0.11, -0.04, 0.0, 0.10, 0.30]
		"bh": clip = PlayerRig.Clip.BH_DRIVE; times = [-0.24, -0.11, -0.04, 0.0, 0.10, 0.30]
		"bh2": clip = PlayerRig.Clip.BH2_DRIVE; times = [-0.24, -0.11, -0.04, 0.0, 0.10, 0.30]
		"react": times = [0.3, 0.6, 0.3, 0.6, 0.3, 0.6]
		"bhs": clip = PlayerRig.Clip.BH_SLICE; times = [-0.24, -0.10, 0.0, 0.06, 0.12, 0.30]
		"vol": clip = PlayerRig.Clip.FH_VOLLEY; times = [-0.16, 0.0, 0.12, -0.16, 0.0, 0.12]
		"serve": clip = PlayerRig.Clip.OVERHEAD; times = [-0.26, -0.13, -0.05, 0.0, 0.12, 0.34]
		"toss": times = [0.0, 0.25, 0.45, 0.62, 0.80, 0.80]
		"run": times = [0.0, 0.17, 0.33, 0.5, 0.67, 0.83]
		"ready": times = [0, 0, 0, 0, 0, 0]
	for i in times.size():
		var rig := PlayerRig.new()
		add_child(rig)
		var prof := PlayerProfile.get_profile(_pose_prof)
		rig.setup(prof["look"], int(prof["hand"]), prof["body"], bool(prof["two_handed"]))
		rig.set_process(false)
		rig.position = Vector3(4.5 - i * 1.8, 0, 8.0)
		rig.rotation.y = PI
		if which == "toss":
			rig._apply(rig._serve_toss_pose(times[i]), 0.0)
		elif which == "run":
			rig.move_vel = Vector3(6.5, 0, 0) if i < 3 else Vector3(0, 0, -6.5)
			rig._gait = times[i]
			rig._run_turn = 90.0 if i < 3 else 0.0
			rig.alert = 1.0
			rig._apply(rig._ready_pose(0.0), 0.0)
		elif which == "react":
			rig.react_id = [PlayerRig.React.FIST, PlayerRig.React.FIST, PlayerRig.React.ARMS_UP, PlayerRig.React.DEJECT, PlayerRig.React.HANDS_HIPS, PlayerRig.React.BOUNCE][i]
			rig._apply(rig._react_pose(times[i]), 0.0)
		elif which == "ready":
			rig.alert = 1.0 if i % 2 == 0 else 0.0
			rig.rotation.y = PI + i * PI / 3.0
			rig._apply(rig._ready_pose(0.0), 0.0)
		else:
			rig.clip_id = clip
			rig.lift = 0.6
			rig.clip_keys = rig._make_clip(clip)
			var nc := rig._nominal_contact(clip)
			if which == "vol" and i >= 3:
				rig.clip_id = PlayerRig.Clip.BH_VOLLEY
				rig.clip_keys = rig._make_clip(PlayerRig.Clip.BH_VOLLEY)
				nc = rig._nominal_contact(PlayerRig.Clip.BH_VOLLEY)
			rig.contact = nc
			rig.hit_dir = Vector3(0, 0, -1)
			rig._apply(rig._sample_clip(times[i]), 0.0)
	cam_rig.set_process(false)
	cam_rig.cam.fov = 26.0
	cam_rig.cam.look_at_from_position(Vector3(2.0, 1.9, 18.0), Vector3(0, 1.15, 8.0), Vector3.UP)
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--posecam="):
			var c := a.split("=")[1].split(",")
			cam_rig.cam.fov = float(c[6]) if c.size() > 6 else 20.0
			cam_rig.cam.look_at_from_position(Vector3(float(c[0]), float(c[1]), float(c[2])), Vector3(float(c[3]), float(c[4]), float(c[5])), Vector3.UP)
			_shot_frames = [6]
			_shot_dir = "/tmp/shots"
			_pose_name = which
			return
	if which == "ready":
		cam_rig.cam.fov = 30.0
		cam_rig.cam.look_at_from_position(Vector3(4.9, 1.75, 11.2), Vector3(4.5, 1.25, 8.0), Vector3.UP)
	_shot_frames = [6]
	_shot_dir = "/tmp/shots"
	_pose_name = which



## اختبار الحركة: لاعب واحد يُحرَّك بسيناريو مكتوب ويُلتقط تسلسل إطارات (الزمن المحاكى مستقل عن سرعة الرسم)
##   --anim=walk|run|shuffle|fh|bh|serve|head|idle[:profile]  [--animcam=x,y,z,tx,ty,tz,fov] [--animn=12] [--animdt=0.1]
func _run_anim(which: String) -> void:
	build_world(0, 0)
	if which.contains(":"):
		_pose_prof = which.split(":")[1]
		which = which.split(":")[0]
	var n := 12
	var step := 0.1
	var camv := [0.0, 1.3, 16.5, 0.0, 0.9, 9.0, 24.0]
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--animn="): n = int(a.split("=")[1])
		if a.begins_with("--animdt="): step = float(a.split("=")[1])
		if a.begins_with("--animcam="):
			var c := a.split("=")[1].split(",")
			for i in mini(c.size(), 7):
				camv[i] = float(c[i])
	var holder := Node3D.new()
	add_child(holder)
	holder.position = Vector3(0, 0, 9.0)
	var rig := PlayerRig.new()
	holder.add_child(rig)
	var prof := PlayerProfile.get_profile(_pose_prof)
	rig.setup(prof["look"], int(prof["hand"]), prof["body"], bool(prof["two_handed"]))
	rig.set_process(false)
	cam_rig.set_process(false)
	cam_rig.cam.fov = camv[6]
	cam_rig.cam.look_at_from_position(Vector3(camv[0], camv[1], camv[2]), Vector3(camv[3], camv[4], camv[5]), Vector3.UP)
	var t := 0.0
	var dt := 1.0 / 60.0
	var vel := Vector3.ZERO
	var drift := 0.0
	var prev_fw := [Vector3.ZERO, Vector3.ZERO]
	var started := false
	var swung := false
	for k in n:
		while t < (k + 1) * step - 0.0001:
			var want := Vector3.ZERO
			rig.alert = 1.0
			rig.look_target = Vector3(0, 1.0, -12.0)
			match which:
				"walk":
					rig.alert = 0.0
					want = Vector3(1.5, 0, 0) if (t > 0.2 and t < 2.2) else Vector3.ZERO
				"run":
					want = Vector3(6.5, 0, 0) if (t > 0.1 and t < 0.9) else Vector3.ZERO
				"shuffle":
					want = Vector3(-2.0, 0, 0) if (t > 0.1 and t < 0.8) else Vector3.ZERO
				"fwd":
					want = Vector3(0, 0, -4.5) if (t > 0.1 and t < 0.8) else Vector3.ZERO
				"fh", "bh":
					var sd := 1 if which == "fh" else -1
					want = Vector3(2.5 * sd, 0, 0) if (t > 0.05 and t < 0.35) else Vector3.ZERO
					if t > 0.15 and not started:
						started = true
						rig.set_prep(sd, Shot.Type.TOPSPIN, false, false)
					if t > 0.50 and not swung:
						swung = true
						var nc := rig._nominal_contact(rig.clip_id)
						rig.start_swing(sd, Shot.Type.TOPSPIN, false, false, 0.24, Vector3(nc.x * rig.hand, nc.y, nc.z), Vector3(0, 0, -1))
					var bt := 0.74 - t
					rig.look_target = Vector3(0.75 * sd, 0.95, -0.42) + Vector3(-1.0 * sd, 0.5, -22.0) * bt if bt > 0.0 else Vector3(0.75 * sd, 1.2, -0.42 - 30.0 * (-bt))
				"serve":
					if not started:
						started = true
						rig.serve_stance()
					if t > 0.3 and not swung and rig.mode == PlayerRig.Mode.SERVE_STANCE:
						rig.serve_toss()
					if t > 0.3 + 0.80 and not swung:
						swung = true
						rig.serve_swing(0.26, Vector3(0.20 * rig.hand, 2.70, -0.42), Vector3(0, 0, -1))
					rig.look_target = Vector3(0.2, 2.7, -0.42) if t < 1.4 else Vector3(0, 1.0, -15.0)
				"head":
					# كرة تدور حول اللاعب: أمام ← يمين ← خلف ← يسار
					var ang := t * 2.6
					rig.look_target = Vector3(sin(ang) * 6.0, 1.0 + 1.5 * sin(t * 1.7), -cos(ang) * 6.0)
				"idle":
					rig.alert = 0.0
					if t > 0.1 and not started:
						started = true
						rig.react(PlayerRig.React.STRINGS if _pose_prof == "samer" else PlayerRig.React.WIPE)
			vel = vel.move_toward(want, 9.0 * dt)
			holder.position += vel * dt
			rig.move_vel = vel
			rig._process(dt)
			# قياس انزلاق القدم المثبّتة
			for i in 2:
				if t > 0.05 and float(rig._fs[i]) >= 1.0 and float(rig._plant_t[i]) > dt * 1.5:
					drift = maxf(drift, (rig._fw[i] as Vector3).distance_to(prev_fw[i]))
				prev_fw[i] = rig._fw[i]
			t += dt
		for i in 3:
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		if DisplayServer.get_name() != "headless":
			get_viewport().get_texture().get_image().save_png("/tmp/shots/anim_%s_%02d.png" % [which, k])
	print("ANIM %s done; max planted-foot drift per tick = %.4f m" % [which, drift])
	get_tree().quit()


func _run_shots(args: PackedStringArray) -> void:
	var surface := 0
	var cam_mode := 0
	var human := false
	var quality := 2
	var menu := ""
	for a in args:
		if a.begins_with("--surface="): surface = int(a.split("=")[1])
		if a.begins_with("--cam="): cam_mode = int(a.split("=")[1])
		if a.begins_with("--quality="): quality = int(a.split("=")[1])
		if a.begins_with("--menu="): menu = a.split("=")[1]
		if a == "--human": human = true
		if a == "--ui": _shot_ui = true
		if a.begins_with("--fbskill="):
			_fb_sigma = float(a.split("=")[1])
		if a == "--fingerbot":
			_fingerbot_on = true
			human = true
			_shot_ui = true
			Settings.data["assist"] = 2
	if menu != "":
		_boot()
		match menu:
			"setup": menus.show_setup()
			"help": menus.show_help("main")
			"settings": menus.show_settings("main")
			"card": menus.show_card("tarek", "main")
		return
	build_world(surface, quality)
	build_match(human, "samer", "karim", 2, 2, surface)
	if _shot_ui:
		hud = Hud.new()
		add_child(hud)
		hud.bind(game, players[0], names)
		if human:
			human_ctrl = HumanController.new()
			world.add_child(human_ctrl)
			human_ctrl.setup(players[0], game, hud.pad, hud.qte, world)
	_wire_feedback()
	if human:
		players[0].assist = int(Settings.get_v("assist"))
	cam_rig.player = players[0]
	cam_rig.ball = ball
	cam_rig.mode = cam_mode
	for a in args:
		if a.begins_with("--camh="): cam_rig.height_k = float(a.split("=")[1]) / 100.0
		if a.begins_with("--camz="): cam_rig.zoom_k = float(a.split("=")[1]) / 100.0
	cam_rig.snap()
	game.fast = false
	game.start_match(1, 6, 0)


# --- إصبع آلي: يحاكي لمسات حقيقية على الأزرار لاختبار مسار التحكم البشري كاملاً ---
var _fingerbot_on := false
var _fb_down := false
var _fb_btn := 0
var _fb_wait := 0.0
var _fb_log := {"serves": 0, "swings": 0, "hits": 0}


func _fb_touch(pressed: bool, pos: Vector2) -> void:
	var e := InputEventScreenTouch.new()
	e.index = 4
	e.pressed = pressed
	e.position = get_viewport().get_final_transform() * pos
	Input.parse_input_event(e)


func _fb_drag(pos: Vector2) -> void:
	var e := InputEventScreenDrag.new()
	e.index = 4
	e.position = get_viewport().get_final_transform() * pos
	Input.parse_input_event(e)


func _physics_process(dt: float) -> void:
	if not _fingerbot_on or hud == null or game == null:
		return
	var p := players[0]
	var pad := hud.pad
	_fb_wait -= dt
	if OS.has_environment("MP_QTE2") and hud.qte.shown and Engine.get_physics_frames() % 6 == 0:
		print("bot st=", p.state, " down=", _fb_down, " stopped=", hud.qte.stopped, " prog=", snappedf(hud.qte.progress, 0.01), " tgt=", snappedf(_fb_tgt, 0.01), " wait=", snappedf(_fb_wait, 0.01))
	match p.state:
		TennisPlayer.St.SERVE_READY:
			if not _fb_down and _fb_wait <= 0.0 and p.serve_ready_to_toss():
				_fb_btn = 1 if game.fault_count == 0 else 0
				_fb_touch(true, pad.button_center(_fb_btn))
				_fb_down = true
				_fb_press_t = p.now()
				_fb_log["serves"] += 1
		TennisPlayer.St.SERVE_TOSS:
			if _fb_down:
				_fb_drag(pad.button_center(_fb_btn) + Vector2(-35, -20))
				if p.tossed and hud.qte.shown and hud.qte.progress >= _fb_target():
					_fb_touch(false, pad.button_center(_fb_btn))
					_fb_down = false
					_fb_wait = 0.5
					_fb_tgt = -1.0
		TennisPlayer.St.FREE:
			if _fb_down:
				if p.now() - _fb_press_t > 0.4:
					_fb_touch(false, pad.button_center(_fb_btn))
					_fb_down = false
			elif game.can_hit(0) and _fb_wait <= 0.0:
				var c := p.find_contact(0.02, 1.3)
				if not c.is_empty() and float(c["t"]) - p.now() < 0.8:
					_fb_btn = 0
					_fb_touch(true, pad.button_center(_fb_btn))
					_fb_down = true
					_fb_press_t = p.now()
					_fb_log["swings"] += 1
		TennisPlayer.St.PREP:
			if OS.has_environment("MP_QTE") and Engine.get_physics_frames() % 6 == 0:
				print("bot PREP down=", _fb_down, " shown=", hud.qte.shown, " stopped=", hud.qte.stopped, " prog=", snappedf(hud.qte.progress, 0.01), " tgt=", snappedf(_fb_tgt, 0.01))
			if _fb_down:
				var ax := -55.0 if players[1].position.x > 0.0 else 55.0
				_fb_drag(pad.button_center(_fb_btn) + Vector2(ax, -25))
				if (hud.qte.shown and not hud.qte.stopped and hud.qte.progress >= _fb_target()) or not game.can_hit(0):
					_fb_touch(false, pad.button_center(_fb_btn))
					_fb_down = false
					_fb_wait = 0.3
					_fb_tgt = -1.0
		_:
			if _fb_down and p.now() - _fb_press_t > 0.4 and p.state != TennisPlayer.St.SERVE_SWING and p.state != TennisPlayer.St.SWING:
				_fb_touch(false, pad.button_center(_fb_btn))
				_fb_down = false


var _fb_tgt := -1.0
var _fb_press_t := 0.0


## هدف الإفلات: مركز المنطقة الخضراء مع خطأ بشري (σ قابل للضبط بـ --fbskill)
func _fb_target() -> float:
	if hud.qte.progress < 0.03:
		_fb_tgt = -1.0
	if _fb_tgt < 0.0:
		var g := hud.qte.green_w
		_fb_tgt = clampf(1.0 - g * 0.5 + randfn(0.0, _fb_sigma), 0.05, 0.995)
	return _fb_tgt


var _fb_sigma := 0.07


func _process(_dt: float) -> void:
	if _shot_frames.is_empty():
		return
	_frame += 1
	if _frame in _shot_frames:
		if DisplayServer.get_name() != "headless":
			var img := get_viewport().get_texture().get_image()
			img.save_png(_shot_dir + ("/pose_" + _pose_name + ".png" if _pose_name != "" else "/shot_%04d.png" % _frame))
		print("saved frame ", _frame)
		if _fingerbot_on and game != null:
			print("fingerbot: ", _fb_log, " sets=", game.rules.sets, " games=", game.rules.games, " pts=", game.rules.points, " phase=", game.phase, " menu=", menus.current if menus != null else "-")
		if _frame >= _shot_frames.max():
			get_tree().quit()


func _run_autotest(args: PackedStringArray) -> void:
	var l0 := 2
	var l1 := 2
	var surface := 0
	for a in args:
		if a.begins_with("--l0="): l0 = int(a.split("=")[1])
		if a.begins_with("--l1="): l1 = int(a.split("=")[1])
		if a.begins_with("--surface="): surface = int(a.split("=")[1])
		if a.begins_with("--sets="): _sets = int(a.split("=")[1])
		if a.begins_with("--matches="): _matches_left = int(a.split("=")[1])
		if a.begins_with("--p0="): _p0 = a.split("=")[1]
		if a.begins_with("--p1="): _p1 = a.split("=")[1]
		if a.begins_with("--wind="): Settings.data["wind"] = int(a.split("=")[1])
		if a == "--log": _log_points = true
	build_match(false, _p0, _p1, l0, l1, surface)
	game.fast = true
	# تسريع الاختبار: دلتا الفيزياء = time_scale / ticks، فنحافظ على 1/120
	Engine.time_scale = 30.0
	Engine.physics_ticks_per_second = 3600
	Engine.max_physics_steps_per_frame = 3600
	game.call_made.connect(_on_call)
	game.match_finished.connect(_on_finished)
	game.ball_hit.connect(_on_hit_stat)
	game.start_match(_sets, 6, 0)


var _sets := 1
var _matches_left := 1
var _p0 := "samer"
var _p1 := "samer"
var _agg := {"calls": {}, "shots": 0, "serve_n": 0, "pts": [0, 0], "wins": [0, 0], "ue": [0, 0], "fe": [0, 0], "win": [0, 0], "ace": [0, 0], "df": [0, 0],
	"first_in": 0, "first_total": 0, "serve_sum": 0.0, "rally_sum": 0, "sp": [0, 0], "spw": [0, 0], "dsum": 0.0, "rally_hist": {}}


func _on_hit_stat(info: Dictionary) -> void:
	var pl: TennisPlayer = players[int(info["player"])]
	_agg["st_sum"] = float(_agg.get("st_sum", 0.0)) + pl.stamina
	_agg["st_n"] = int(_agg.get("st_n", 0)) + 1
	_agg["st_min"] = minf(float(_agg.get("st_min", 1.0)), pl.stamina)
	_agg["cap_min"] = minf(float(_agg.get("cap_min", 1.0)), pl.stamina_cap)
	if info["serve"]:
		_agg["serve_n"] += 1
	else:
		_agg["shots"] += 1
		_agg["dsum"] += float(info["D"])


func _on_call(kind: String, data: Dictionary) -> void:
	if kind == "bounce" or kind == "net_touch":
		return
	_agg["calls"][kind] = int(_agg["calls"].get(kind, 0)) + 1
	if data.has("rally"):
		var b := mini(int(data["rally"]), 12)
		_agg["rally_hist"][b] = int(_agg["rally_hist"].get(b, 0)) + 1
	if _log_points:
		var r := game.rules
		print(kind, " ", data.get("winner", "-"), " rally=", data.get("rally", 0), " | sets ", r.sets, " games ", r.games, " pts ", r.points)


func _on_finished(winner: int) -> void:
	print("MATCH winner=", winner, " history=", game.rules.set_history)
	_agg["wins"][winner] += 1
	for i in 2:
		var s: Dictionary = game.stats[i]
		_agg["pts"][i] += s["points"]
		_agg["ue"][i] += s["unforced"]
		_agg["fe"][i] += s["forced"]
		_agg["win"][i] += s["winners"]
		_agg["ace"][i] += s["aces"]
		_agg["df"][i] += s["double_faults"]
		_agg["first_in"] += s["first_in"]
		_agg["first_total"] += s["first_total"]
		_agg["serve_sum"] += s["serve_sum"]
		_agg["sp"][i] += s["serve_points"]
		_agg["spw"][i] += s["serve_points_won"]
	_agg["rally_sum"] += game.stats[0]["rally_sum"]
	_matches_left -= 1
	if _matches_left > 0:
		game.start_match(_sets, 6, _matches_left % 2)
		return
	var total: int = _agg["pts"][0] + _agg["pts"][1]
	print("=== AGG wins=", _agg["wins"], " pts=", _agg["pts"], " total=", total)
	print("UE=", _agg["ue"], " FE=", _agg["fe"], " winners=", _agg["win"], " aces=", _agg["ace"], " DF=", _agg["df"])
	print("1st serve %=", snappedf(100.0 * _agg["first_in"] / maxf(_agg["first_total"], 1), 0.1), " avg serve kmh=", snappedf(_agg["serve_sum"] / maxf(_agg["serve_n"], 1), 0.1),
		" serve pts won %=", snappedf(100.0 * (_agg["spw"][0] + _agg["spw"][1]) / maxf(_agg["sp"][0] + _agg["sp"][1], 1), 0.1))
	print("avg rally=", snappedf(float(_agg["rally_sum"]) / maxf(total, 1), 0.01), " avg D=", snappedf(_agg["dsum"] / maxf(_agg["shots"], 1), 0.01), " calls=", _agg["calls"])
	var hist := ""
	for k in range(1, 13):
		hist += str(k) + ":" + str(_agg["rally_hist"].get(k, 0)) + " "
	print("rally length hist: ", hist)
	for pl in players:
		print("cost ", pl.display_name, " ", pl.dbg_cost, " drain=", snappedf(float(pl.d["drain"]), 0.01), " rec=", snappedf(float(pl.d["recover"]), 0.01))
	print("stamina at hits: avg=", snappedf(float(_agg.get("st_sum", 0.0)) / maxf(float(_agg.get("st_n", 1)), 1.0), 0.01), " min=", snappedf(float(_agg.get("st_min", 1.0)), 0.01), " cap_min=", snappedf(float(_agg.get("cap_min", 1.0)), 0.01))
	get_tree().quit()
