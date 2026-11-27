extends Node
## Game controller (autoload "G"): world, loop, camera, rounds, input, settings.

const Fighter = preload("res://scripts/fighter.gd")
const AIC = preload("res://scripts/ai.gd")
const Proj = preload("res://scripts/proj.gd")
const CD = preload("res://scripts/chardata.gd")
const Arena = preload("res://scripts/arena.gd")
const Rig = preload("res://scripts/rig.gd")
const UIScript = preload("res://scripts/ui.gd")
const CineScript = preload("res://scripts/cine.gd")
const combat = preload("res://scripts/combat.gd")
const U = preload("res://scripts/util.gd")

const STAGE := 7.3
const BTNS := ["U", "D", "L", "R", "1", "2", "3", "4", "BL", "TH", "SP", "ST"]

var world: Node3D
var camera: Camera3D
var arena
var ui
var cine
var settings := {quality = "high", music = 0.55, sfx = 0.9, voice = true, haptics = true}
var f := []
var view := []
var cache := [{}, {}]
var projs := []
var frame := 0
var phase := "boot"
var mode := "cpu"
var cpu_lvl := 1
var hitstop := 0
var freeze := 0
var freeze_f = null
var impact := 0.0
var paused := false
var training = null
var stats = null
var thr = null
var round_n := 1
var wins := [0, 0]
var timer := 0
var end_t := 0
var end_a = null
var end_b = null
var end_hit := false
var slow_t := 0.0
var grade_desat := 0.0
var touch := {}
var cam := {pos = Vector3(2, 2.2, 6), look = Vector3(0, 3, -11), fov = 42.0, roll = 0.0, shake = 0.0, mode = "menu", shot = null, t = 0.0}
var args := {}
var booted := false
var _shot_frames := 0

# ======================================================================= boot
func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for a in OS.get_cmdline_user_args():
		var kv: PackedStringArray = a.trim_prefix("--").split("=")
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	_load_settings()
	_setup_input()
	world = Node3D.new()
	world.name = "World"
	add_child(world)
	camera = Camera3D.new()
	camera.fov = 42.0
	camera.near = 0.05
	camera.far = 200.0
	world.add_child(camera)
	camera.current = true
	VFX.setup(world)
	ui = UIScript.new()
	add_child(ui)
	cine = CineScript.new()
	call_deferred("_boot")

func _boot() -> void:
	ui.show_loading(0.05, "تُشيَّد كاتدرائية العظام...")
	await get_tree().process_frame
	arena = Arena.new()
	arena.build(world)
	apply_quality()
	var i := 0
	for id in CD.ROSTER:
		ui.show_loading(0.2 + i * 0.15, "تُستحضر الأرواح الملعونة...")
		await get_tree().process_frame
		CD.get_def(id)
		Rig.template(id)
		i += 1
	ui.show_loading(0.85, "تُرسم الوجوه...")
	await get_tree().process_frame
	if not args.has("noportraits"):
		await ui.make_portraits()
	ui.show_loading(1.0, "تُشحذ الشفرات...")
	await get_tree().process_frame
	booted = true
	ui.hide_loading()
	if args.has("dumptex"):
		for k in ["lava", "metal_c", "muscle_c", "stone_c", "skin_n", "mottle", "wall_c"]:
			var img: Image = Mats.T[k].get_image()
			if img: img.save_png(args.dumptex + "/tex_%s.png" % k)
			print(k, " ", img.get_size() if img else "null")
		get_tree().quit()
		return
	if args.has("soak"):
		_soak()
		return
	if args.has("quick"):
		start_match(args.get("p1", "kharos"), args.get("p2", "vorgath"), args.quick, int(args.get("lvl", "1")))
		if args.has("test"): cine.run_test(args.test)
	elif args.has("menu"):
		match str(args.menu):
			"main": ui.show_main()
			"select": ui.show_select("cpu")
			"select2":
				ui.show_select("2p")
				ui.cs.cur[1] = 2
				ui._refresh_select()
			"moves": ui.show_moves(ui.show_main, args.get("p1", "kharos"))
			"controls": ui.show_controls(ui.show_main)
			"settings": ui.show_settings(ui.show_main)
			"diff":
				ui.show_select("cpu")
				ui.show_difficulty()
			"pause":
				start_match("kharos", "ossirah", "training")
				toggle_pause()
			_: ui.show_title()
	else:
		ui.show_title()

func on_audio_ready() -> void:
	if phase == "menu" or phase == "boot": SFX.start_music("menu")

# ======================================================================= settings / quality
func _load_settings() -> void:
	var c := ConfigFile.new()
	if DisplayServer.is_touchscreen_available() or OS.has_feature("mobile"):
		settings.quality = "mid"
	if c.load("user://settings.cfg") == OK:
		for k in settings: settings[k] = c.get_value("s", k, settings[k])

func save_settings() -> void:
	var c := ConfigFile.new()
	for k in settings: c.set_value("s", k, settings[k])
	c.save("user://settings.cfg")
	SFX.set_volumes(settings.sfx, settings.music)

func apply_quality() -> void:
	var q: String = settings.quality
	var vp := get_viewport()
	vp.msaa_3d = Viewport.MSAA_DISABLED if q == "low" else (Viewport.MSAA_2X if q == "mid" else Viewport.MSAA_4X)
	vp.scaling_3d_scale = 0.7 if q == "low" else (0.85 if q == "mid" else 1.0)
	VFX.quality = 0.5 if q == "low" else (0.8 if q == "mid" else 1.0)
	if arena:
		arena.key.shadow_enabled = q != "low"
		arena.env.glow_enabled = true
	SFX.set_volumes(settings.sfx, settings.music)

# ======================================================================= input
func _setup_input() -> void:
	var kb := [
		{"U": KEY_W, "D": KEY_S, "L": KEY_A, "R": KEY_D, "1": KEY_U, "2": KEY_I, "3": KEY_J, "4": KEY_K, "BL": KEY_L, "TH": KEY_O, "SP": KEY_SPACE, "ST": KEY_ESCAPE},
		{"U": KEY_UP, "D": KEY_DOWN, "L": KEY_LEFT, "R": KEY_RIGHT, "1": KEY_KP_4, "2": KEY_KP_5, "3": KEY_KP_1, "4": KEY_KP_2, "BL": KEY_KP_6, "TH": KEY_KP_3, "SP": KEY_KP_0, "ST": KEY_ENTER},
	]
	var pad := {"U": JOY_BUTTON_DPAD_UP, "D": JOY_BUTTON_DPAD_DOWN, "L": JOY_BUTTON_DPAD_LEFT, "R": JOY_BUTTON_DPAD_RIGHT, "1": JOY_BUTTON_X, "2": JOY_BUTTON_Y, "3": JOY_BUTTON_A, "4": JOY_BUTTON_B, "BL": JOY_BUTTON_RIGHT_SHOULDER, "TH": JOY_BUTTON_LEFT_SHOULDER, "ST": JOY_BUTTON_START}
	for p in 2:
		for b in BTNS:
			var an := "p%d_%s" % [p + 1, b]
			if not InputMap.has_action(an): InputMap.add_action(an, 0.4)
			var ev := InputEventKey.new()
			ev.physical_keycode = kb[p][b]
			InputMap.action_add_event(an, ev)
			if p == 0 and b == "BL":
				var e2 := InputEventKey.new()
				e2.physical_keycode = KEY_SHIFT
				InputMap.action_add_event(an, e2)
			if p == 0 and b == "ST":
				var e3 := InputEventKey.new()
				e3.physical_keycode = KEY_P
				InputMap.action_add_event(an, e3)
			if pad.has(b):
				var jb := InputEventJoypadButton.new()
				jb.button_index = pad[b]
				jb.device = p
				InputMap.action_add_event(an, jb)
		var axes := {L = [JOY_AXIS_LEFT_X, -1.0], R = [JOY_AXIS_LEFT_X, 1.0], U = [JOY_AXIS_LEFT_Y, -1.0], D = [JOY_AXIS_LEFT_Y, 1.0], SP = [JOY_AXIS_TRIGGER_RIGHT, 1.0], BL = [JOY_AXIS_TRIGGER_LEFT, 1.0]}
		for b in axes:
			var jm := InputEventJoypadMotion.new()
			jm.axis = axes[b][0]
			jm.axis_value = axes[b][1]
			jm.device = p
			InputMap.action_add_event("p%d_%s" % [p + 1, b], jm)

func raw_for(pi: int) -> Dictionary:
	var o := {}
	var sets := [pi + 1] if mode == "2p" else ([1, 2] if pi == 0 else [])
	for s in sets:
		for b in BTNS:
			if Input.is_action_pressed("p%d_%s" % [s, b]): o[b] = true
	if pi == 0:
		for k in touch:
			if touch[k]: o[k] = true
	return o

# ======================================================================= match flow
func get_fighter(side: int, id: String):
	var F = cache[side].get(id)
	if F == null:
		F = Fighter.new(side, id)
		cache[side][id] = F
	F.idx = side
	F.add_to(world)
	return F

func set_view(list: Array) -> void:
	for F in view:
		if not list.has(F): F.remove()
	view = list

func start_match(c1: String, c2: String, m: String, lvl := 1) -> void:
	ui.hide_menu()
	VFX.clear()
	ui.clear_overlays()
	mode = m
	cpu_lvl = lvl
	training = {dummy = "stand", meter = true, last = null, idle = 0, aidle = 0, cd = 0} if m == "training" else null
	var A = get_fighter(0, c1)
	var B = get_fighter(1, c2)
	set_view([A, B])
	f = [A, B]
	A.ai = null
	B.ai = AIC.new(B, lvl) if m == "cpu" else (AIC.new(B, 2, "stand") if m == "training" else null)
	if args.has("cpuvcpu"): A.ai = AIC.new(A, lvl)
	A.meter = 300.0 if m == "training" else 0.0
	B.meter = A.meter
	wins = [0, 0]
	round_n = 1
	stats = {dmg = [0, 0], supers = [0, 0]}
	paused = false
	ui.show_hud(A, B, m)
	SFX.start_music("fight")
	start_round(m != "training" and not args.has("nointro"))

func start_round(intro: bool) -> void:
	var A = f[0]
	var B = f[1]
	for gb in VFX.gibs:
		if is_instance_valid(gb.node): gb.node.queue_free()
	VFX.gibs.clear()
	VFX.fountains.clear()
	for p in projs: p.die(false)
	projs.clear()
	cine.reset()
	var ma: float = A.meter
	var mb_: float = B.meter
	A.reset(-1.6, 1)
	B.reset(1.6, -1)
	A.meter = ma
	B.meter = mb_
	thr = null
	timer = 99 * 60
	end_hit = false
	hitstop = 0
	freeze = 0
	slowmo(1.0, 0.0)
	for F in f:
		if F.ai: F.ai.tried = false
	if mode == "training":
		phase = "fight"
		cam_fight()
		return
	ui.update_wins(wins)
	if intro: cine.intro_seq()
	else: cine.ready_seq()

func quit_match() -> void:
	cine.reset()
	phase = "menu"
	for p in projs: p.die(false)
	projs.clear()
	f = []
	VFX.clear()
	slowmo(1.0, 0.0)
	paused = false
	PhysicsServer3D.set_active(true)
	ui.clear_overlays()
	ui.hide_hud()

func on_ko(A, B) -> void:
	if phase != "fight": return
	B.dead = wins[A.idx] + 1 < 2
	cine.round_ko(A, B, false)

func slowmo(scale: float, sec: float) -> void:
	Engine.time_scale = scale
	slow_t = sec
	AudioServer.playback_speed_scale = lerpf(1.0, scale, 0.5) if sec > 0.0 else 1.0

func cam_shake(a: float) -> void:
	cam.shake = minf(1.3, cam.shake + a)
	if a >= 0.25 and settings.get("haptics", true) and OS.has_feature("mobile"):
		Input.vibrate_handheld(int(clampf(a * 90.0, 25.0, 140.0)))

func spawn_proj(F, o: Dictionary):
	var p = Proj.new(F, o)
	projs.append(p)
	return p

func Lp(F, x: float, y: float, z: float) -> Vector3:
	return Vector3(F.x + F.facing * x * F.s, y, z)

func cam_shot(pos, look, fov := 34.0, dur := 0.0, ease := "io", roll := 0.0) -> void:
	cam.mode = "shot"
	if dur <= 0.0:
		cam.pos = pos.call() if pos is Callable else pos
		cam.look = look.call() if look is Callable else look
		cam.fov = fov
		cam.roll = roll
	cam.shot = {p0 = cam.pos, l0 = cam.look, f0 = cam.fov, r0 = cam.roll, p1 = pos, l1 = look, f1 = fov, r1 = roll, t = 0.0, d = dur, ease = ease}

func cam_fight() -> void:
	cam.mode = "fight"
	cam.shot = null

func toggle_pause() -> void:
	if f.size() != 2 or phase == "over": return
	for F in f: F.st_edge = true
	if paused:
		paused = false
		PhysicsServer3D.set_active(true)
		ui.hide_menu()
		for F in f: F.input.clear()
		return
	paused = true
	PhysicsServer3D.set_active(false)
	DisplayServer.tts_stop()
	ui.show_pause()

# ======================================================================= tick
func _physics_process(_delta: float) -> void:
	if f.size() != 2: return
	if paused:
		for F in f:
			if F.ai == null:
				var raw := raw_for(F.idx)
				var st: bool = raw.get("ST", false)
				if st and not F.st_edge: toggle_pause()
				F.st_edge = st
		return
	game_tick()

func game_tick() -> void:
	frame += 1
	for F in f:
		F.px = F.x
		F.py = F.y
		var raw: Dictionary = F.ai.raw() if F.ai else raw_for(F.idx)
		F.input.sample(raw, F.facing, frame)
		if F.ai == null:
			var st: bool = raw.get("ST", false)
			if st and not F.st_edge:
				F.st_edge = st
				toggle_pause()
				return
			F.st_edge = st
	if hitstop > 0:
		hitstop -= 1
		return
	if freeze > 0:
		freeze -= 1
		if freeze == 0: cine.end_super_flash()
		return
	var locked: bool = cine.tick()
	if locked: return
	if thr != null: combat.throw_tick()
	for F in f:
		if F.state != "cine" and F.state != "intro": F.tick()
	for F in f:
		if not F.state in ["cine", "throwing", "thrown", "intro"]: F.physics()
	push_apart()
	var A = f[0]
	var B = f[1]
	var h0 = combat.detect_hit(A, B)
	var h1 = combat.detect_hit(B, A)
	if h0 != null:
		A.hit_done[h0.i] = true
		combat.resolve_hit(A, B, h0.h, h0.p)
	if h1 != null and B.state == "attack" and B.move != null:
		B.hit_done[h1.i] = true
		combat.resolve_hit(B, A, h1.h, h1.p)
	for p in projs: p.update()
	Proj.clash(projs)
	for p in projs: p.collide()
	projs = projs.filter(func(p): return not p.dead)
	round_logic()

func push_apart() -> void:
	var A = f[0]
	var B = f[1]
	if A.state == "cine" or B.state == "cine" or thr != null: return
	if (A.y > 0.85 * A.s and B.y < 0.3) or (B.y > 0.85 * B.s and A.y < 0.3): return
	var wa: float = 0.3 * A.s
	var wb: float = 0.3 * B.s
	var d: float = B.x - A.x
	var ov: float = wa + wb - absf(d)
	if ov > 0.0:
		var sgn := 1.0 if d >= 0.0 else -1.0
		var ma := ov / 2.0
		var mb := ov / 2.0
		if absf(A.x) >= STAGE - 0.02:
			ma = 0.0; mb = ov
		if absf(B.x) >= STAGE - 0.02:
			mb = 0.0; ma = ov
		A.x = clampf(A.x - sgn * ma, -STAGE, STAGE)
		B.x = clampf(B.x + sgn * mb, -STAGE, STAGE)

func round_logic() -> void:
	var A = f[0]
	var B = f[1]
	if phase == "fight" and training == null:
		if not cine.active() and timer > 0: timer -= 1
		if timer == 0:
			var w = A if float(A.hp) / A.max_hp >= float(B.hp) / B.max_hp else B
			var l = B if w == A else A
			timer = -1
			l.hp = mini(l.hp, w.hp - 1)
			cine.round_ko(w, l, true)
			if l.state != "juggle":
				l.set_state("juggle"); l.vy = 0.06; l.play("air", 4.0)
	if phase == "endthem" and end_a != null:
		var L = end_b
		if L.state == "getup" or L.state == "stand":
			L.set_state("dizzy"); L.play("dizzy", 12.0)
		if end_hit and L.state == "down": cine.finish_match(end_a, L, false)
		end_t -= 1
		if end_t <= 0 and not end_hit:
			end_hit = true; L.dead = true; L.set_state("juggle"); L.vy = 0.03; L.y = 0.02; L.play("air", 10.0)
			SFX.voice(L.def.id, "die", 1.0)
	if training != null:
		var T: Dictionary = training
		for F in f:
			if T.meter: F.meter = 300.0
		if B.state in ["stand", "block", "crouch"]:
			T.idle += 1
			if T.idle > 50: B.hp = B.max_hp
		else: T.idle = 0
		if A.state in ["stand", "crouch"]:
			T.aidle += 1
			if T.aidle > 50: A.hp = A.max_hp
		else: T.aidle = 0
		if B.combo_dmg > 0: T.cd = B.combo_dmg
		if A.state == "attack" and A.move != null and A.mf == 1:
			T.last = A.move
			ui.train_panel()
	var lo := minf(float(A.hp) / A.max_hp, float(B.hp) / B.max_hp)
	SFX.music_int = clampf(1.0 - lo, 0.0, 1.0) * 0.9 + (0.3 if phase == "endthem" else 0.0)
	if phase == "fight" and lo < 0.2 and frame % 60 == 0: SFX.play("heartbeat", 0.8)

# ======================================================================= render
func _process(dt: float) -> void:
	if not booted: return
	if slow_t > 0.0:
		slow_t -= dt / maxf(Engine.time_scale, 0.01)
		if slow_t <= 0.0:
			Engine.time_scale = 1.0
			AudioServer.playback_speed_scale = 1.0
	var rdt := 0.0 if paused else dt
	var alpha := Engine.get_physics_interpolation_fraction() if f.size() == 2 else 1.0
	for F in view:
		if f.size() != 2:
			F.px = F.x; F.py = F.y
		var adv := rdt * 60.0
		var held: bool = cine.holding()
		if freeze > 0 and freeze_f == F: adv = rdt * 60.0 * 0.12
		elif (hitstop > 0 or freeze > 0) and F.state != "cine": adv = 0.0
		elif held: adv = 0.0
		F.render(rdt, alpha if f.size() == 2 else 1.0, adv)
	VFX.update(rdt * (0.1 if hitstop > 0 else 1.0))
	if arena: arena.update(rdt)
	update_camera(maxf(rdt, 0.0001))
	if f.size() == 2: ui.update_hud(dt)
	impact = maxf(0.0, impact - rdt * 60.0) if not paused else impact
	var low_hp := 1.0
	if f.size() == 2 and phase == "fight":
		for F in f:
			if F.ai == null: low_hp = minf(low_hp, float(F.hp) / F.max_hp)
	ui.set_post(impact > 0.0, grade_desat, cam.shake, (0.25 - low_hp) * 2.4 * (0.7 + 0.3 * sin(Time.get_ticks_msec() / 160.0)) if low_hp < 0.25 else 0.0)
	if args.has("shot") and booted:
		_shot_frames += 1
		var fl: PackedStringArray = str(args.get("frames", "120")).split(",")
		var fr := str(_shot_frames)
		if fr in fl:
			var path: String = args.shot if fl.size() == 1 else str(args.shot).replace(".png", "_%s.png" % fr)
			var img := get_viewport().get_texture().get_image()
			if img: img.save_png(path)
			for F in f: print("F%d %s x=%.2f y=%.2f state=%s hp=%d" % [F.idx, F.def.id, F.x, F.y, F.state, F.hp])
			print("shot ", path, " phase=", phase, " draws=", Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME), " objs=", Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME), " prims=", Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME))
			if fr == fl[fl.size() - 1]: get_tree().quit()

func update_camera(dt: float) -> void:
	cam.t += dt
	var k := 1.0 - exp(-dt * 5.5)
	match cam.mode:
		"fight":
			if f.size() == 2:
				var A = f[0]
				var B = f[1]
				var mx := clampf((A.x + B.x) / 2.0, -5.4, 5.4)
				var sep: float = absf(A.x - B.x)
				var ay: float = (A.y + B.y) / 2.0
				var dist := clampf(3.7 + sep * 0.62, 4.5, 8.3)
				cam.pos = cam.pos.lerp(Vector3(mx + sin(cam.t * 0.21) * 0.08, 1.42 + ay * 0.3 + sin(cam.t * 0.3) * 0.03, dist), k)
				cam.look = cam.look.lerp(Vector3(mx, 1.12 + ay * 0.4, 0), k)
				cam.fov = lerpf(cam.fov, 36.0, k)
				cam.roll = lerpf(cam.roll, 0.0, k)
		"shot":
			var s = cam.shot
			if s != null:
				s.t += dt * 60.0
				var u := U.ease_f(s.ease, s.t / s.d) if s.d > 0.0 else 1.0
				var p1: Vector3 = s.p1.call() if s.p1 is Callable else s.p1
				var l1: Vector3 = s.l1.call() if s.l1 is Callable else s.l1
				cam.pos = s.p0.lerp(p1, u)
				cam.look = s.l0.lerp(l1, u)
				cam.fov = lerpf(s.f0, s.f1, u)
				cam.roll = lerpf(s.r0, s.r1, u)
		"menu":
			var t: float = cam.t * 0.06
			var k2 := 1.0 - exp(-dt * 1.5)
			cam.pos = cam.pos.lerp(Vector3(sin(t) * 7.5, 2.2 + sin(t * 1.7) * 0.6, -3.5 + cos(t) * 8.5), k2)
			cam.look = cam.look.lerp(Vector3(0, 3.2, -11), k2)
			cam.fov = lerpf(cam.fov, 42.0, k2)
		"select":
			var k3 := 1.0 - exp(-dt * 3.0)
			cam.pos = cam.pos.lerp(Vector3(0, 1.45, 5.4), k3)
			cam.look = cam.look.lerp(Vector3(0, 1.2, 0), k3)
			cam.fov = lerpf(cam.fov, 34.0, k3)
	var sh: float = cam.shake * cam.shake * 0.14
	var tt := Time.get_ticks_msec() / 1000.0
	var p: Vector3 = cam.pos + Vector3(sin(tt * 71.0) * sh, sin(tt * 53.0 + 1.0) * sh, sin(tt * 37.0) * sh * 0.5)
	if p.distance_squared_to(cam.look) > 1e-6:
		camera.look_at_from_position(p, cam.look, Vector3.UP)
	camera.rotate_object_local(Vector3.BACK, cam.roll + sin(tt * 61.0) * sh * 0.08)
	camera.fov = cam.fov
	cam.shake = maxf(0.0, cam.shake - dt * 2.4)

# ======================================================================= test harness
func _soak() -> void:
	var pairs := [["kharos", "vorgath"], ["nyxara", "ossirah"], ["vorgath", "nyxara"], ["ossirah", "kharos"], ["kharos", "kharos"]]
	args.cpuvcpu = "1"
	args.nointro = "1"
	var n := int(args.get("soak", "10800"))
	for pr in pairs:
		start_match(pr[0], pr[1], "cpu", 3)
		var phases := {}
		var last := phase
		var t0 := Time.get_ticks_msec()
		for i in n:
			game_tick()
			for F in f: F.anim.advance(1.0)
			if phase != last:
				phases[phase] = phases.get(phase, 0) + 1
				last = phase
			if phase == "over": break
		print("SOAK %s vs %s: phase=%s hp=%s wins=%s phases=%s dmg=%s ms=%d" % [pr[0], pr[1], phase, [f[0].hp, f[1].hp], wins, phases, stats.dmg, Time.get_ticks_msec() - t0])
		quit_match()
	get_tree().quit()
