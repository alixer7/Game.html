extends Node3D
## Main menu with a 3D garage turntable, race setup and character select.

var _ui: Control
var _pivot: Node3D
var _preview: Node3D
var _page: Control
var _stats: VBoxContainer
var _name_label: Label


func _ready() -> void:
	_build_stage()
	_ui = Control.new()
	_ui.set_anchors_preset(Control.PRESET_FULL_RECT)
	_ui.theme = UIKit.theme()
	var cl := CanvasLayer.new()
	add_child(cl)
	cl.add_child(_ui)
	_show_main()
	Sfx.play_music("music_race")
	# smoke test of an exported package: `godot --main-pack x.pck -- --smoke-race`
	if "--smoke-race" in OS.get_cmdline_user_args():
		_start.call_deferred()


func _build_stage() -> void:
	var we := WorldEnvironment.new()
	var e := Environment.new()
	var sky := Sky.new()
	var sm := ShaderMaterial.new()
	sm.shader = load("res://shaders/sky.gdshader")
	sm.set_shader_parameter("cloud_tex", Mats.tex("clouds"))
	sky.sky_material = sm
	e.background_mode = Environment.BG_SKY
	e.sky = sky
	e.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	e.ambient_light_energy = 0.9
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	e.glow_enabled = true
	e.glow_intensity = 0.5
	we.environment = e
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(deg_to_rad(-40), deg_to_rad(-30), 0)
	sun.light_energy = 1.3
	sun.shadow_enabled = true
	add_child(sun)
	# grassy platform with a few props so the turntable sits in the world
	var ground := MeshBuilder.new()
	var segs := 48
	var ci := ground.add_vertex(Vector3.ZERO, Vector3.UP, Vector2.ZERO, Color(0, 0, 0, 0))
	for s in segs:
		var a := TAU * float(s) / segs
		ground.add_vertex(Vector3(cos(a) * 9.0, 0, sin(a) * 9.0), Vector3.UP, Vector2(cos(a), sin(a)) * 9.0, Color(0.3, 0, 0, 0))
	for s in segs:
		ground.tri(ci, 1 + (s + 1) % segs, 1 + s)
	var gmi := MeshInstance3D.new()
	gmi.mesh = ground.commit(null, Mats.terrain())
	add_child(gmi)
	var deco := MeshBuilder.new()
	for i in 7:
		var a := TAU * float(i) / 7.0 + 0.4
		var p := Vector3(cos(a) * 7.0, 0, sin(a) * 7.0)
		if p.z > 2.0:
			continue
		deco.append_builder(MeshLib.rock(i * 3, i % 3), Transform3D(Basis(Vector3.UP, a).scaled(Vector3.ONE * 0.9), p))
	var dmi := MeshInstance3D.new()
	dmi.mesh = deco.commit(null, Mats.triplanar("rock"))
	add_child(dmi)
	var tree := MeshLib.broadleaf_tree(77, 0, 0)
	var tmi := MeshInstance3D.new()
	tmi.mesh = Scatter._variant([tree.bark, tree.leaves, tree.cards], [Mats.triplanar("bark"), Mats.foliage(Color.WHITE, "trees"), Mats.cards(Color.WHITE, "trees")])
	tmi.position = Vector3(-6.5, 0, -6)
	add_child(tmi)
	_pivot = Node3D.new()
	add_child(_pivot)
	var cam := Camera3D.new()
	cam.position = Vector3(2.4, 1.6, 4.2)
	cam.fov = 50
	add_child(cam)
	cam.look_at(Vector3(-0.4, 0.55, 0), Vector3.UP)
	cam.current = true
	_refresh_preview()


func _refresh_preview() -> void:
	if _preview:
		_preview.queue_free()
	var ch := Game.character(int(Game.race.character))
	_preview = KartModel.build(ch)
	_pivot.add_child(_preview)


func _process(dt: float) -> void:
	if _pivot:
		_pivot.rotate_y(dt * 0.45)


func _clear() -> void:
	if _page:
		_page.queue_free()
	_page = Control.new()
	_page.set_anchors_preset(Control.PRESET_FULL_RECT)
	_ui.add_child(_page)
	UIKit.safe_margins(_page)


func _show_main() -> void:
	_clear()
	var title := UIKit.label("WILDSPARK", 96, UIKit.ORANGE, 18)
	title.position = Vector2(60, 18)
	_page.add_child(title)
	var sub := UIKit.label("KART", 60, UIKit.TEAL, 14)
	sub.position = Vector2(68, 122)
	_page.add_child(sub)
	var v := VBoxContainer.new()
	v.position = Vector2(60, 212)
	v.add_theme_constant_override("separation", 10)
	_page.add_child(v)
	v.add_child(UIKit.button("Race", func() -> void: _show_setup("race")))
	v.add_child(UIKit.button("Time Trial", func() -> void: _show_setup("time_trial")))
	v.add_child(UIKit.button("Practice", func() -> void: _show_setup("practice")))
	v.add_child(UIKit.button("Garage", _show_garage))
	v.add_child(UIKit.button("Settings", _settings))
	if not OS.has_feature("web"):
		v.add_child(UIKit.button("Quit", func() -> void: get_tree().quit()))
	for b in v.get_children():
		(b as Control).custom_minimum_size.y = 64   # six buttons fit a 720 px tall screen
	var ver := UIKit.label("v%s" % ProjectSettings.get_setting("application/config/version", "0.1"), 18, Color(1, 1, 1, 0.5), 4)
	ver.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	ver.position = Vector2(-120, -40)
	_page.add_child(ver)


func _show_setup(mode: String) -> void:
	Game.race.mode = mode
	_clear()
	var panel := PanelContainer.new()
	panel.position = Vector2(60, 60)
	_page.add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 16)
	panel.add_child(v)
	var titles := {"race": "GRAND PRIX RACE", "time_trial": "TIME TRIAL", "practice": "PRACTICE"}
	v.add_child(UIKit.label(titles[mode], 46, UIKit.ORANGE, 10))
	var names := []
	for t in Game.TRACKS:
		if t.data != "":
			names.append(t.name)
	v.add_child(UIKit.row("Track", UIKit.options(names, 0, func(i: int) -> void: Game.race.track = Game.TRACKS[i].id)))
	if mode != "practice":
		v.add_child(UIKit.row("Laps", UIKit.options(["1", "2", "3", "4", "5"], int(Game.race.laps) - 1, func(i: int) -> void: Game.race.laps = i + 1)))
	if mode == "race":
		v.add_child(UIKit.row("Difficulty", UIKit.options(Game.DIFFICULTIES, int(Game.race.difficulty), func(i: int) -> void: Game.race.difficulty = i)))
		v.add_child(UIKit.row("Racers", UIKit.options(["4", "6", "8"], [4, 6, 8].find(int(Game.race.racers)), func(i: int) -> void: Game.race.racers = [4, 6, 8][i])))
	var key := "%s_%s" % [Game.race.track, mode]
	var best_lap: float = Game.records.get(key + "_lap", INF)
	v.add_child(UIKit.label("Best lap: " + Game.format_time(best_lap), 24, UIKit.TEAL, 6))
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 16)
	h.add_child(UIKit.button("Back", _show_main, 200))
	h.add_child(UIKit.button("START", _start, 280))
	v.add_child(h)


func _start() -> void:
	Game.save_settings()
	Game.goto_scene("res://scenes/race.tscn")


func _show_garage() -> void:
	_clear()
	var panel := PanelContainer.new()
	panel.position = Vector2(40, 40)
	_page.add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	panel.add_child(v)
	v.add_child(UIKit.label("GARAGE", 46, UIKit.ORANGE, 10))
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
	v.add_child(grid)
	for i in Game.CHARACTERS.size():
		var ch: Dictionary = Game.CHARACTERS[i]
		var b := UIKit.button(ch.name, func() -> void:
			Game.race.character = i
			Game.race.chassis = ""
			_refresh_preview()
			_update_stats(), 170)
		b.add_theme_color_override("font_color", (ch.kart as Color).lightened(0.3))
		grid.add_child(b)
	v.add_child(UIKit.row("Chassis", UIKit.options(["Character default", "Balanced", "Speed", "Acceleration", "Turning"], 0, func(i: int) -> void:
		Game.race.chassis = ["", "balanced", "speed", "accel", "turning"][i]
		_update_stats())))
	_name_label = UIKit.label("", 34, UIKit.TEAL, 8)
	v.add_child(_name_label)
	_stats = VBoxContainer.new()
	v.add_child(_stats)
	v.add_child(UIKit.button("Back", func() -> void:
		Game.save_settings()
		_show_main(), 200))
	_update_stats()


func _update_stats() -> void:
	var ch := Game.character(int(Game.race.character))
	var chassis: String = Game.race.chassis if Game.race.chassis != "" else ch.chassis
	var p := KartParams.make_class(chassis)
	_name_label.text = "%s the %s  -  %s chassis" % [ch.name, ch.species, p.display_name]
	for c in _stats.get_children():
		c.queue_free()
	var stats := [["Top speed", inverse_lerp(25.0, 27.2, p.max_speed)], ["Acceleration", inverse_lerp(14.5, 20.5, p.accel)],
		["Turning", inverse_lerp(0.9, 1.2, p.turn_rate_top)], ["Weight", inverse_lerp(0.8, 1.2, p.mass)]]
	for s in stats:
		var h := HBoxContainer.new()
		var l := UIKit.label(s[0], 24, UIKit.CREAM, 6)
		l.custom_minimum_size = Vector2(200, 0)
		h.add_child(l)
		var bar := ProgressBar.new()
		bar.min_value = 0.0
		bar.max_value = 1.0
		bar.value = clampf(float(s[1]) * 0.8 + 0.15, 0.05, 1.0)
		bar.show_percentage = false
		bar.custom_minimum_size = Vector2(300, 22)
		var fill := StyleBoxFlat.new()
		fill.bg_color = UIKit.TEAL
		fill.set_corner_radius_all(6)
		var bg := StyleBoxFlat.new()
		bg.bg_color = Color(1, 1, 1, 0.12)
		bg.set_corner_radius_all(6)
		bar.add_theme_stylebox_override("fill", fill)
		bar.add_theme_stylebox_override("background", bg)
		h.add_child(bar)
		_stats.add_child(h)


func _settings() -> void:
	var sp := SettingsPanel.new()
	_ui.add_child(sp)
