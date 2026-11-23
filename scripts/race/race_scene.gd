extends Node3D
## Race scene controller: environment, track build, karts, AI, UI, flow.

var tb: TrackBuilder
var race: RaceManager
var items: ItemSystem
var hud: HUD
var touch: TouchControls
var cam: ChaseCamera
var player: Kart
var karts: Array[Kart] = []
var lanes := {}
var sun: DirectionalLight3D
var env: WorldEnvironment

var _loading: CanvasLayer
var _overlay: CanvasLayer
var _state := "loading"
var _intro_t := 0.0
var _intro_from := Transform3D()
var build_ms := 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE
	_show_loading()
	await get_tree().process_frame
	await get_tree().process_frame
	var t0 := Time.get_ticks_msec()
	_setup_environment()
	_build_track()
	_spawn_karts()
	_setup_ai()
	_setup_ui()
	build_ms = Time.get_ticks_msec() - t0
	print("[race] world built in %d ms  %s" % [build_ms, tb.timings])
	if "--smoke-race" in OS.get_cmdline_user_args():
		# exported-package smoke test: run the race for a while, report, quit
		get_tree().create_timer(25.0).timeout.connect(func() -> void:
			print("[smoke] state=%s race_time=%.1f karts=%d player_pos=%s" % [race.state, race.race_time, get_tree().get_nodes_in_group("karts").size(), player.global_position.snapped(Vector3.ONE)])
			get_tree().quit())
	_loading.queue_free()
	_state = "intro"
	_intro_t = 0.0
	Sfx.play_music("music_race")


# ------------------------------------------------------------------ setup
func _show_loading() -> void:
	_loading = CanvasLayer.new()
	_loading.layer = 50
	add_child(_loading)
	var bg := ColorRect.new()
	bg.color = Color(0.06, 0.08, 0.12)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	_loading.add_child(bg)
	var tdef := Game.track_def(Game.race.track)
	var l := UIKit.label(tdef.name.to_upper(), 64, UIKit.ORANGE, 12)
	l.set_anchors_preset(Control.PRESET_CENTER)
	l.position = Vector2(-500, -90)
	l.size = Vector2(1000, 90)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_loading.add_child(l)
	var l2 := UIKit.label("Growing the forest...", 30, UIKit.CREAM, 6)
	l2.set_anchors_preset(Control.PRESET_CENTER)
	l2.position = Vector2(-500, 10)
	l2.size = Vector2(1000, 60)
	l2.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_loading.add_child(l2)


func _setup_environment() -> void:
	var q: int = Game.settings["quality"]
	env = WorldEnvironment.new()
	var e := Environment.new()
	var sky := Sky.new()
	var sm := ShaderMaterial.new()
	sm.shader = load("res://shaders/sky.gdshader")
	sm.set_shader_parameter("cloud_tex", Mats.tex("clouds"))
	sky.sky_material = sm
	sky.radiance_size = Sky.RADIANCE_SIZE_128
	sky.process_mode = Sky.PROCESS_MODE_QUALITY if q >= 2 else Sky.PROCESS_MODE_INCREMENTAL
	e.background_mode = Environment.BG_SKY
	e.sky = sky
	e.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	e.ambient_light_energy = 0.85
	e.ambient_light_sky_contribution = 0.85
	e.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	e.tonemap_exposure = 1.05
	e.tonemap_white = 6.0
	e.glow_enabled = q >= 1
	e.glow_intensity = 0.55
	e.glow_bloom = 0.06
	e.glow_hdr_threshold = 1.1
	e.glow_blend_mode = Environment.GLOW_BLEND_MODE_SOFTLIGHT
	e.fog_enabled = true
	e.fog_mode = Environment.FOG_MODE_EXPONENTIAL
	e.fog_density = 0.0011
	e.fog_light_color = Color(0.72, 0.82, 0.92)
	e.fog_sun_scatter = 0.18
	e.fog_aerial_perspective = 0.35
	e.fog_sky_affect = 0.15
	e.adjustment_enabled = true
	e.adjustment_saturation = 1.12
	e.adjustment_contrast = 1.05
	env.environment = e
	add_child(env)
	sun = DirectionalLight3D.new()
	sun.light_color = Color(1.0, 0.95, 0.84)
	sun.light_energy = 1.3
	sun.rotation = Vector3(deg_to_rad(-42.0), deg_to_rad(-142.0), 0)
	sun.shadow_enabled = Game.settings["shadows"] and q >= 1
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	sun.directional_shadow_max_distance = 95.0 if q >= 2 else 60.0
	sun.directional_shadow_blend_splits = q >= 2
	sun.shadow_bias = 0.04
	sun.shadow_normal_bias = 1.2
	sun.light_angular_distance = 0.6
	add_child(sun)


func _build_track() -> void:
	var tdef := Game.track_def(Game.race.track)
	tb = TrackBuilder.new()
	tb.load_track(tdef.data)
	tb.build(self, int(Game.settings["quality"]))
	race = RaceManager.new()
	race.name = "Race"
	add_child(race)
	race.setup(tb, int(Game.race.laps) if Game.race.mode != "practice" else 99)
	race.rubber = int(Game.settings["rubber_band"])
	items = ItemSystem.new()
	items.name = "Items"
	items.race = race
	items.world = self
	add_child(items)
	race.race_finished.connect(_on_finished)


func _spawn_karts() -> void:
	var mode: String = Game.race.mode
	var count: int = 1 if mode != "race" else clampi(int(Game.race.racers), 2, 8)
	var player_slot := 0 if count == 1 else mini(count - 1, 5)
	var pc: int = Game.race.character
	var order: Array = []
	for i in Game.CHARACTERS.size():
		if i != pc:
			order.append(i)
	var ai_i := 0
	for slot in count:
		var is_player := slot == player_slot
		var ci: int = pc if is_player else order[ai_i % order.size()]
		if not is_player:
			ai_i += 1
		var ch := Game.character(ci)
		var chassis: String = Game.race.chassis if is_player and Game.race.chassis != "" else ch.chassis
		var k := Kart.new()
		k.params = KartParams.make_class(chassis)
		k.name = "Kart_%s" % ch.id
		k.display_name = ch.name
		k.racer_index = slot
		k.is_player = is_player
		k.set_meta("color", ch.kart)
		add_child(k)
		k.add_to_group("karts")
		k.teleport(tb.spawn_grid[slot])
		var vis := KartVisual.new()
		vis.name = "Visual"
		k.add_child(vis)
		vis.setup(k, ch)
		karts.append(k)
		race.add_kart(k)
		items.register(k)
		if is_player:
			player = k
	race.player = player
	cam = ChaseCamera.new()
	add_child(cam)
	cam.attach(player)
	cam.add_child(EnvLife.falling_leaves())
	var pd := PlayerDriver.new()
	pd.name = "PlayerDriver"
	pd.kart = player
	pd.camera = cam
	add_child(pd)


func _setup_ai() -> void:
	lanes = build_lane_graph(tb)
	var diff: int = Game.race.difficulty
	var seed := 100
	for k in karts:
		if k.is_player:
			continue
		var ai := AIDriver.new()
		ai.name = "AI_" + k.display_name
		add_child(ai)
		# a little spread of skill inside a difficulty so the field strings out naturally
		var d := clampi(diff + (1 if k.racer_index < 2 and diff < 3 else 0) - (1 if k.racer_index >= 6 and diff > 0 else 0), 0, 3)
		ai.setup(k, lanes, d, tb.obstacles, seed)
		ai.items = items
		ai.race = race
		k.set_meta("ai", ai)
		seed += 17
		race.ai_start_press(k, [0.2, 0.45, 0.7, 0.9][d])


static func build_lane_graph(builder: TrackBuilder) -> Dictionary:
	var g := {}
	g["main"] = {"line": RacingLine.build(builder.main, builder.obstacles, 1.6), "entry_lane": "", "entry_i": 0, "exit_lane": "main", "exit_i": 0}
	for id in builder.branches:
		if id == "river_upstream":
			continue
		g[id] = {"line": RacingLine.build(builder.branches[id], builder.obstacles, 1.2), "entry_lane": "main", "entry_i": 0, "exit_lane": "main", "exit_i": 0}
	for id in g:
		if id == "main":
			continue
		var sp: SplinePath = builder.branches[id]
		var entry_lane := "giants_log" if id == "shelf_rock" and g.has("giants_log") else "main"
		g[id].entry_lane = entry_lane
		g[id].entry_i = _nearest_line_index(g[entry_lane].line, sp.pos[0])
		g[id].exit_lane = "main"
		g[id].exit_i = _nearest_line_index(g["main"].line, sp.pos[sp.size() - 1])
	return g


static func _nearest_line_index(rl: RacingLine, p: Vector3) -> int:
	var best := 0
	var best_d := INF
	for i in rl.size():
		var q := rl.pts[i]
		var d := Vector2(q.x - p.x, q.z - p.z).length_squared() + pow(q.y - p.y, 2.0)
		if d < best_d:
			best_d = d
			best = i
	return best


func _setup_ui() -> void:
	hud = HUD.new()
	add_child(hud)
	hud.setup(race, player, items, tb)
	var tl := CanvasLayer.new()
	tl.layer = 6
	add_child(tl)
	touch = TouchControls.new()
	tl.add_child(touch)
	touch.pause_requested.connect(_pause)


# ------------------------------------------------------------------ flow
func _process(dt: float) -> void:
	match _state:
		"intro":
			_intro(dt)
	if Input.is_action_just_pressed("pause") and _state != "loading":
		_pause()


func _intro(dt: float) -> void:
	_intro_t += dt
	var dur := 3.2
	var k := player
	var u := clampf(_intro_t / dur, 0.0, 1.0)
	var e := u * u * (3.0 - 2.0 * u)
	var centre := k.global_position
	var ang := lerpf(2.4, 0.0, e) + k.yaw
	var dist := lerpf(26.0, 5.6, e)
	var h := lerpf(12.0, 2.1, e)
	var pos := centre + Vector3(sin(ang) * dist, h, cos(ang) * dist)
	cam.global_position = pos
	cam.look_at(centre + Vector3.UP * 0.8, Vector3.UP)
	if _intro_t >= dur or Input.is_action_just_pressed("drift") or Input.is_action_just_pressed("accelerate"):
		_state = "countdown"
		cam.snap()
		race.start_countdown()


func _pause() -> void:
	if get_tree().paused or _overlay != null:
		return
	get_tree().paused = true
	_overlay = _menu_overlay("PAUSED", [
		["Resume", _resume],
		["Restart", func() -> void: Game.goto_scene("res://scenes/race.tscn")],
		["Settings", func() -> void: _open_settings()],
		["Quit to menu", func() -> void: Game.goto_scene("res://scenes/main.tscn")],
	])


func _resume() -> void:
	get_tree().paused = false
	if _overlay:
		_overlay.queue_free()
		_overlay = null


func _open_settings() -> void:
	var sp := SettingsPanel.new()
	sp.process_mode = Node.PROCESS_MODE_ALWAYS
	var layer := CanvasLayer.new()
	layer.layer = 40
	layer.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(layer)
	layer.add_child(sp)
	sp.closed.connect(func() -> void:
		layer.queue_free()
		Game.apply_settings()
		touch.queue_redraw())


func _menu_overlay(title: String, entries: Array, extra: Control = null) -> CanvasLayer:
	var layer := CanvasLayer.new()
	layer.layer = 30
	layer.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(layer)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.add_child(dim)
	var panel := PanelContainer.new()
	panel.theme = UIKit.theme()
	panel.set_anchors_preset(Control.PRESET_CENTER)
	layer.add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 14)
	panel.add_child(v)
	var t := UIKit.label(title, 54, UIKit.ORANGE, 10)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(t)
	if extra:
		v.add_child(extra)
	for en in entries:
		v.add_child(UIKit.button(en[0], en[1], 420))
	panel.reset_size()
	panel.position = -panel.size * 0.5
	return layer


func _on_finished(results: Array) -> void:
	Game.last_results = results
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 40)
	for r in results:
		var col := UIKit.ORANGE if r.player else UIKit.CREAM
		grid.add_child(UIKit.label("%d" % int(r.pos), 30, col, 6))
		grid.add_child(UIKit.label(String(r.name), 30, col, 6))
		grid.add_child(UIKit.label(Game.format_time(float(r.time)) + ("" if r.finished else "*"), 30, col, 6))
		grid.add_child(UIKit.label("best " + Game.format_time(float(r.best)), 24, col, 6))
	var pr := race.progress_of(player)
	var key := "%s_%s" % [Game.race.track, Game.race.mode]
	var record := Game.submit_record(key + "_lap", float(pr.best))
	if Game.race.mode != "practice":
		record = Game.submit_record(key + "_total", float(pr.finish_time)) or record
	if record:
		grid.add_child(UIKit.label("NEW RECORD!", 30, UIKit.TEAL, 6))
	Sfx.play("finish")
	get_tree().paused = true
	_overlay = _menu_overlay("RESULTS", [
		["Race again", func() -> void: Game.goto_scene("res://scenes/race.tscn")],
		["Main menu", func() -> void: Game.goto_scene("res://scenes/main.tscn")],
	], grid)
