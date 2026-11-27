class_name MainMenu
extends Node3D

## Bulletproof Mobile-First CTR Main Menu with LIVE 3D Spinning Kart Showcase Diorama.
## Explicitly enforces LTR coordinate layout (preventing Godot 4 Arabic OS RTL mirroring bugs)
## while preserving native HarfBuzz Arabic text shaping & RTL reading inside labels/buttons!
## Fully responsive across 16:9, 19.5:9, 20:9, 21:9 phones & tablets with Display Safe Area support.

signal start_race_requested()

enum Screen {
	HOME,
	RACER_SELECT,
	TRACK_SELECT,
	GUIDE,
	SETTINGS
}

var _current_screen: Screen = Screen.HOME
var _turntable: Node3D
var _showcase_kart: Node3D
var _showcase_cam: Camera3D
var _ui_layer: CanvasLayer
var _ui_root: Control
var _time: float = 0.0

func _ready() -> void:
	_build_3d_diorama()

	_ui_layer = CanvasLayer.new()
	_ui_layer.layer = 5
	add_child(_ui_layer)

	_ui_root = Control.new()
	# CRITICAL: Lock coordinate system to LTR so Arabic Android OS locale NEVER mirrors
	# anchored panels or pushes menu columns off-screen! Arabic strings still shape RTL natively.
	_ui_root.layout_direction = Control.LAYOUT_DIRECTION_LTR
	_ui_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_ui_layer.add_child(_ui_root)

	get_viewport().size_changed.connect(_on_viewport_resized)
	GameState.language_changed.connect(func(_l): _render_screen())
	if AudioSynth:
		AudioSynth.set_engine_active(false)
		AudioSynth.start_music(true)
	_rebuild_showcase_kart()
	_render_screen()

func _notification(what: int) -> void:
	# Android hardware back button navigates menus gracefully instead of quitting unexpectedly
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		if _current_screen == Screen.TRACK_SELECT:
			_current_screen = Screen.RACER_SELECT
			_render_screen()
		elif _current_screen != Screen.HOME:
			_current_screen = Screen.HOME
			_render_screen()

func _on_viewport_resized() -> void:
	if _ui_root and is_instance_valid(_ui_root):
		_ui_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		_render_screen()

func _get_safe_margins() -> Dictionary:
	# Respect Android punch-hole camera notches, rounded corners, and gesture nav bars!
	var vp := get_viewport().get_visible_rect().size
	var left_m := 30
	var right_m := 30
	var top_m := 18
	var bot_m := 18
	var win_sz := DisplayServer.window_get_size()
	var safe := DisplayServer.get_display_safe_area()
	if win_sz.x > 0 and win_sz.y > 0 and safe.size.x > 0 and safe.size.y > 0:
		var sx := vp.x / float(win_sz.x)
		var sy := vp.y / float(win_sz.y)
		left_m = maxi(left_m, int(ceilf(float(safe.position.x) * sx)) + 16)
		right_m = maxi(right_m, int(ceilf(float(win_sz.x - safe.end.x) * sx)) + 16)
		top_m = maxi(top_m, int(ceilf(float(safe.position.y) * sy)) + 12)
		bot_m = maxi(bot_m, int(ceilf(float(win_sz.y - safe.end.y) * sy)) + 12)
	return {"left": left_m, "right": right_m, "top": top_m, "bottom": bot_m}

func _build_3d_diorama() -> void:
	var env := Environment.new()
	var sky := Sky.new()
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.28, 0.24, 0.44)
	sky_mat.sky_horizon_color = Color(1.0, 0.72, 0.40)
	sky_mat.ground_bottom_color = Color(0.14, 0.26, 0.28)
	sky_mat.ground_horizon_color = Color(0.95, 0.70, 0.44)
	sky_mat.sun_angle_max = 26.0
	sky.sky_material = sky_mat
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.46
	env.fog_enabled = true
	env.fog_light_color = Color(0.95, 0.76, 0.56)
	env.fog_density = 0.0045
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = 0.96
	env.glow_enabled = false
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

	var sun := DirectionalLight3D.new()
	sun.light_energy = 1.12
	sun.light_color = Color(1.0, 0.86, 0.62)
	sun.shadow_enabled = GameState.graphics_high if GameState else true
	sun.rotation_degrees = Vector3(-22.0, 24.0, 0.0)
	add_child(sun)

	var rim := DirectionalLight3D.new()
	rim.light_energy = 0.34
	rim.light_color = Color(1.0, 0.72, 0.44)
	rim.rotation_degrees = Vector3(-16.0, -148.0, 0.0)
	add_child(rim)

	var sea := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(360, 360)
	pm.subdivide_width = 24; pm.subdivide_depth = 24
	sea.mesh = pm
	var sea_sm := ShaderMaterial.new()
	sea_sm.shader = load("res://assets/shaders/water_ocean.gdshader")
	sea.material_override = sea_sm
	sea.position = Vector3(0.0, -2.0, 0.0)
	add_child(sea)

	# Checkered Nitro Turntable framed cleanly on the right side of the screen!
	_turntable = Node3D.new()
	_turntable.position = Vector3(2.2, 0.0, 0.0)
	add_child(_turntable)

	var disc := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 2.65
	cm.bottom_radius = 3.0
	cm.height = 0.65
	cm.radial_segments = 24
	disc.mesh = cm
	var disc_m := StandardMaterial3D.new()
	if ProceduralTextures:
		disc_m.albedo_texture = ProceduralTextures.get_texture("checkerboard")
	disc_m.roughness = 0.38
	disc.material_override = disc_m
	disc.position = Vector3(0.0, -0.32, 0.0)
	_turntable.add_child(disc)

	var ring := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 2.65
	tm.outer_radius = 2.95
	ring.mesh = tm
	var rm := StandardMaterial3D.new()
	rm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	rm.albedo_color = Color(0.18, 0.88, 1.0)
	ring.material_override = rm
	ring.position = Vector3(0.0, 0.04, 0.0)
	_turntable.add_child(ring)

	# Golden-Hour Canyon Showcase Diorama: Canopy Trees, Exotic Tropical Ferns, Carved Runestone & Aqueduct Arch!
	var crate_ps = load("res://assets/models/prop_crate_item.glb")
	if crate_ps is PackedScene:
		for p in [Vector3(5.6, 0.5, -4.2), Vector3(7.1, 0.5, -3.2), Vector3(6.3, 1.9, -3.7)]:
			var c: Node3D = crate_ps.instantiate()
			c.position = p
			c.scale = Vector3(0.85, 0.85, 0.85)
			c.rotation_degrees.y = 24.0
			add_child(c)
	var canopy_ps = load("res://assets/models/prop_canopy_tree.glb")
	if canopy_ps is PackedScene:
		var ct: Node3D = canopy_ps.instantiate()
		ct.position = Vector3(11.0, -2.2, -13.5)
		ct.scale = Vector3(1.15, 1.15, 1.15)
		add_child(ct)
		var ct2: Node3D = canopy_ps.instantiate()
		ct2.position = Vector3(-11.5, -2.2, -18.5)
		ct2.rotation_degrees.y = 125.0
		ct2.scale = Vector3(1.05, 1.05, 1.05)
		add_child(ct2)
	var bush_ps = load("res://assets/models/prop_jungle_bush.glb")
	if bush_ps is PackedScene:
		for bp in [Vector3(6.4, -1.6, -6.2), Vector3(-2.6, -1.6, -7.8), Vector3(8.8, -1.6, -2.5)]:
			var b: Node3D = bush_ps.instantiate()
			b.position = bp
			b.scale = Vector3(0.82, 0.82, 0.82)
			b.rotation_degrees.y = bp.x * 22.0
			add_child(b)
	var rune_ps = load("res://assets/models/prop_runestone.glb")
	if rune_ps is PackedScene:
		var rn: Node3D = rune_ps.instantiate()
		rn.position = Vector3(10.2, -2.2, -9.2)
		rn.rotation_degrees.y = -32.0
		rn.scale = Vector3(0.75, 0.75, 0.75)
		add_child(rn)
	var arch_ps = load("res://assets/models/prop_canyon_arch.glb")
	if arch_ps is PackedScene:
		var aq: Node3D = arch_ps.instantiate()
		aq.position = Vector3(-6.0, -4.5, -46.0)
		aq.rotation_degrees.y = 18.0
		aq.scale = Vector3(0.95, 0.95, 0.95)
		add_child(aq)
	var cry_ps = load("res://assets/models/prop_crystal_pickup.glb")
	if cry_ps is PackedScene:
		var cry: Node3D = cry_ps.instantiate()
		cry.position = Vector3(-1.4, 1.85, -3.4)
		cry.scale = Vector3(1.15, 1.15, 1.15)
		add_child(cry)
	var isl_ps = load("res://assets/models/prop_mountain_tiki.glb")
	if isl_ps is PackedScene:
		var isl_r: Node3D = isl_ps.instantiate()
		isl_r.position = Vector3(32.0, -2.6, -58.0)
		isl_r.rotation_degrees.y = 42.0
		isl_r.scale = Vector3(24.0, 22.0, 22.0)
		add_child(isl_r)
		var isl_l: Node3D = isl_ps.instantiate()
		isl_l.position = Vector3(-42.0, -2.6, -78.0)
		isl_l.rotation_degrees.y = 160.0
		isl_l.scale = Vector3(30.0, 28.0, 26.0)
		add_child(isl_l)

	_showcase_cam = Camera3D.new()
	_showcase_cam.position = Vector3(0.15, 2.55, 7.6)
	_showcase_cam.fov = 48.0
	add_child(_showcase_cam)
	_showcase_cam.make_current()
	_showcase_cam.look_at(Vector3(0.75, 0.95, 0.0), Vector3.UP)

func _rebuild_showcase_kart() -> void:
	if _showcase_kart and is_instance_valid(_showcase_kart):
		_showcase_kart.queue_free()
	var vis_script := load("res://scripts/physics/KartVisuals.gd")
	_showcase_kart = vis_script.new()
	_turntable.add_child(_showcase_kart)
	_showcase_kart.build_kart(GameState.get_selected_racer(), false)

func _process(delta: float) -> void:
	_time += delta
	if _turntable:
		_turntable.rotation.y = 2.45 + _time * 0.55
	if _showcase_kart and is_instance_valid(_showcase_kart):
		var demo_tier := 4 if (int(_time / 2.2) % 2 == 0) else 3
		_showcase_kart.update_anim(delta, {
			"speed": 26.0,
			"steer": sin(_time * 1.4) * 0.6,
			"fire_tier": demo_tier,
			"is_drifting": false,
			"is_grounded": true
		})

func _clear_ui() -> void:
	for c in _ui_root.get_children():
		c.queue_free()

func _make_root_margin() -> MarginContainer:
	var mc := MarginContainer.new()
	mc.layout_direction = Control.LAYOUT_DIRECTION_LTR
	mc.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var m := _get_safe_margins()
	mc.add_theme_constant_override("margin_left", m["left"])
	mc.add_theme_constant_override("margin_right", m["right"])
	mc.add_theme_constant_override("margin_top", m["top"])
	mc.add_theme_constant_override("margin_bottom", m["bottom"])
	_ui_root.add_child(mc)
	return mc

func _render_screen() -> void:
	_clear_ui()
	match _current_screen:
		Screen.HOME: _build_home_ui()
		Screen.RACER_SELECT: _build_racer_select_ui()
		Screen.TRACK_SELECT: _build_track_select_ui()
		Screen.GUIDE: _build_guide_ui()
		Screen.SETTINGS: _build_settings_ui()

func _make_top_bar(show_back: bool, title_txt: String) -> HBoxContainer:
	var bar := HBoxContainer.new()
	bar.layout_direction = Control.LAYOUT_DIRECTION_LTR
	bar.add_theme_constant_override("separation", 14)
	bar.custom_minimum_size = Vector2(0, 62)

	if show_back:
		var back := Button.new()
		back.text = "◀  " + GameState.t("back")
		back.custom_minimum_size = Vector2(148, 56)
		UITheme.style_button(back, Color(0.78, 0.20, 0.14), Color.WHITE, 20, 14)
		back.pressed.connect(func():
			if AudioSynth: AudioSynth.play_sfx("ui_click")
			if _current_screen == Screen.TRACK_SELECT:
				_current_screen = Screen.RACER_SELECT
			else:
				_current_screen = Screen.HOME
			_render_screen()
		)
		bar.add_child(back)

	var lbl := UITheme.make_label(title_txt, 32, Color(1.0, 0.88, 0.16), HORIZONTAL_ALIGNMENT_CENTER if not show_back else HORIZONTAL_ALIGNMENT_LEFT, 7)
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.add_child(lbl)

	# Quick Mute/Audio Button (crisp localized text — zero missing emoji glyphs on any Android font!)
	var muted := (GameState.sfx_volume <= 0.01 and GameState.music_volume <= 0.01)
	var mute_btn := Button.new()
	mute_btn.text = GameState.t("sound_off") if muted else GameState.t("sound_on")
	mute_btn.custom_minimum_size = Vector2(114, 56)
	UITheme.style_button(mute_btn, Color(0.42, 0.18, 0.22) if muted else Color(0.16, 0.56, 0.44), Color.WHITE, 18, 14)
	mute_btn.pressed.connect(func():
		if GameState.sfx_volume <= 0.01 and GameState.music_volume <= 0.01:
			GameState.sfx_volume = 0.85
			GameState.music_volume = 0.55
		else:
			GameState.sfx_volume = 0.0
			GameState.music_volume = 0.0
		GameState.save_data()
		GameState.settings_changed.emit()
		_render_screen()
	)
	bar.add_child(mute_btn)

	# 1-Tap Bilingual EN / عربي Toggle Pill!
	var lang_btn := Button.new()
	lang_btn.text = "EN / عربي"
	lang_btn.custom_minimum_size = Vector2(150, 56)
	UITheme.style_button(lang_btn, Color(0.14, 0.44, 0.84), Color.WHITE, 19, 14)
	lang_btn.pressed.connect(func():
		if AudioSynth: AudioSynth.play_sfx("ui_click")
		GameState.toggle_language()
	)
	bar.add_child(lang_btn)
	return bar

func _build_home_ui() -> void:
	var mc := _make_root_margin()
	var outer_h := HBoxContainer.new()
	outer_h.layout_direction = Control.LAYOUT_DIRECTION_LTR
	outer_h.add_theme_constant_override("separation", 24)
	mc.add_child(outer_h)

	# LEFT SIDE (Responsive 48% width, capped cleanly between 480 and 600px): Logo + ALL Mode Buttons!
	var left_col := VBoxContainer.new()
	left_col.layout_direction = Control.LAYOUT_DIRECTION_LTR
	left_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left_col.size_flags_stretch_ratio = 0.92
	left_col.alignment = BoxContainer.ALIGNMENT_CENTER
	left_col.add_theme_constant_override("separation", 11)
	outer_h.add_child(left_col)

	var logo_panel := PanelContainer.new()
	logo_panel.add_theme_stylebox_override("panel", UITheme.panel_box(Color(0.88, 0.24, 0.05, 0.94), Color(1.0, 0.88, 0.16), 20, 5, 10))
	left_col.add_child(logo_panel)
	var lv := VBoxContainer.new()
	lv.add_theme_constant_override("separation", 3)
	logo_panel.add_child(lv)
	lv.add_child(UITheme.make_label(GameState.t("title"), 36, Color(1.0, 0.92, 0.18), HORIZONTAL_ALIGNMENT_CENTER, 8))
	lv.add_child(UITheme.make_label(GameState.t("subtitle"), 15, Color(0.88, 0.98, 1.0), HORIZONTAL_ALIGNMENT_CENTER, 4))

	var modes := [
		{"key": "arcade_race", "mode": GameState.GameMode.ARCADE_RACE, "col": Color(0.96, 0.44, 0.06)},
		{"key": "grand_prix", "mode": GameState.GameMode.GRAND_PRIX, "col": Color(0.92, 0.66, 0.06)},
		{"key": "time_trial", "mode": GameState.GameMode.TIME_TRIAL, "col": Color(0.10, 0.60, 0.94)},
		{"key": "practice_mode", "mode": GameState.GameMode.PRACTICE_ACADEMY, "col": Color(0.10, 0.72, 0.62)},
	]
	for m in modes:
		var b := Button.new()
		b.text = GameState.t(m["key"])
		b.custom_minimum_size = Vector2(0, 62)
		UITheme.style_button(b, m["col"], Color.WHITE, 23, 16)
		var mode_val: GameState.GameMode = m["mode"]
		b.pressed.connect(func():
			if AudioSynth: AudioSynth.play_sfx("ui_confirm")
			GameState.selected_mode = mode_val
			_current_screen = Screen.RACER_SELECT
			_render_screen()
		)
		left_col.add_child(b)

	var bottom_row := HBoxContainer.new()
	bottom_row.layout_direction = Control.LAYOUT_DIRECTION_LTR
	bottom_row.add_theme_constant_override("separation", 12)
	left_col.add_child(bottom_row)

	var b_guide := Button.new()
	b_guide.text = GameState.t("academy")
	b_guide.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b_guide.custom_minimum_size = Vector2(0, 58)
	UITheme.style_button(b_guide, Color(0.14, 0.68, 0.36), Color.WHITE, 19, 14)
	b_guide.pressed.connect(func():
		if AudioSynth: AudioSynth.play_sfx("ui_click")
		_current_screen = Screen.GUIDE
		_render_screen()
	)
	bottom_row.add_child(b_guide)

	var b_set := Button.new()
	b_set.text = GameState.t("settings")
	b_set.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b_set.custom_minimum_size = Vector2(0, 58)
	UITheme.style_button(b_set, Color(0.36, 0.22, 0.70), Color.WHITE, 19, 14)
	b_set.pressed.connect(func():
		if AudioSynth: AudioSynth.play_sfx("ui_click")
		_current_screen = Screen.SETTINGS
		_render_screen()
	)
	bottom_row.add_child(b_set)

	# RIGHT SIDE (Open space for 3D Spinning Kart + Top Controls + Bottom Racer Status Badge!)
	var right_col := VBoxContainer.new()
	right_col.layout_direction = Control.LAYOUT_DIRECTION_LTR
	right_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right_col.size_flags_stretch_ratio = 1.08
	outer_h.add_child(right_col)

	right_col.add_child(_make_top_bar(false, ""))

	var open_spacer := Control.new()
	open_spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	open_spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	right_col.add_child(open_spacer)

	var badge_align := HBoxContainer.new()
	badge_align.alignment = BoxContainer.ALIGNMENT_END
	right_col.add_child(badge_align)

	var badge := PanelContainer.new()
	badge.custom_minimum_size = Vector2(360, 82)
	badge.add_theme_stylebox_override("panel", UITheme.panel_box(Color(0.08, 0.12, 0.22, 0.88), Color(0.20, 0.88, 1.0), 16, 3, 6))
	badge_align.add_child(badge)
	var bv := VBoxContainer.new()
	badge.add_child(bv)
	var r := GameState.get_selected_racer()
	bv.add_child(UITheme.make_label("%s  •  %s" % [GameState.get_racer_name(r), r.get("class_" + GameState.language, "")], 21, Color(1.0, 0.88, 0.18), HORIZONTAL_ALIGNMENT_CENTER, 5))
	bv.add_child(UITheme.make_label("%s: %d / 9   |   %s: %d" % [GameState.t("shortcuts_label"), GameState.discovered_shortcuts.size(), GameState.t("cups_label"), GameState.cups_won], 15, Color(0.45, 0.96, 0.88), HORIZONTAL_ALIGNMENT_CENTER, 4))

func _build_racer_select_ui() -> void:
	var mc := _make_root_margin()
	var root_v := VBoxContainer.new()
	root_v.layout_direction = Control.LAYOUT_DIRECTION_LTR
	root_v.add_theme_constant_override("separation", 14)
	mc.add_child(root_v)

	root_v.add_child(_make_top_bar(true, GameState.t("select_racer")))

	var body_h := HBoxContainer.new()
	body_h.layout_direction = Control.LAYOUT_DIRECTION_LTR
	body_h.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body_h.add_theme_constant_override("separation", 24)
	root_v.add_child(body_h)

	# Left Panel: 4 Racers + Stats + Continue Button
	var left := VBoxContainer.new()
	left.layout_direction = Control.LAYOUT_DIRECTION_LTR
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.size_flags_stretch_ratio = 1.0
	left.add_theme_constant_override("separation", 12)
	body_h.add_child(left)

	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 12)
	left.add_child(grid)

	for i in range(GameState.RACERS.size()):
		var r: Dictionary = GameState.RACERS[i]
		var selected := (i == GameState.selected_racer_index)
		var btn := Button.new()
		btn.text = "%s\n[%s]" % [GameState.get_racer_name(r), r.get("class_" + GameState.language, "")]
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.custom_minimum_size = Vector2(0, 86)
		var fill: Color = r["body_color"] if selected else Color(0.14, 0.18, 0.28, 0.92)
		UITheme.style_button(btn, fill, Color(1.0, 0.98, 0.72) if selected else Color.WHITE, 20, 16)
		var idx := i
		btn.pressed.connect(func():
			if AudioSynth: AudioSynth.play_sfx("ui_click")
			GameState.selected_racer_index = idx
			GameState.save_data()
			_rebuild_showcase_kart()
			_render_screen()
		)
		grid.add_child(btn)

	var cur := GameState.get_selected_racer()
	var stat_panel := PanelContainer.new()
	stat_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	stat_panel.add_theme_stylebox_override("panel", UITheme.panel_box(Color(0.08, 0.11, 0.20, 0.92), Color(1.0, 0.72, 0.14), 18, 4, 8))
	left.add_child(stat_panel)
	var sv := VBoxContainer.new()
	sv.add_theme_constant_override("separation", 8)
	sv.alignment = BoxContainer.ALIGNMENT_CENTER
	stat_panel.add_child(sv)

	var desc := UITheme.make_label(cur.get("desc_" + GameState.language, ""), 16, Color(0.92, 0.96, 1.0), HORIZONTAL_ALIGNMENT_RIGHT if GameState.is_rtl() else HORIZONTAL_ALIGNMENT_LEFT, 4)
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	sv.add_child(desc)

	_add_stat_row(sv, GameState.t("speed"), float(cur["stat_speed"]), Color(1.0, 0.34, 0.12))
	_add_stat_row(sv, GameState.t("accel"), float(cur["stat_accel"]), Color(1.0, 0.80, 0.10))
	_add_stat_row(sv, GameState.t("turn"), float(cur["stat_turn"]), Color(0.14, 0.84, 1.0))

	var btn_next := Button.new()
	btn_next.text = GameState.t("start_race") if GameState.selected_mode == GameState.GameMode.GRAND_PRIX else (GameState.t("next") + "  ▶")
	btn_next.custom_minimum_size = Vector2(0, 70)
	UITheme.style_button(btn_next, Color(0.14, 0.78, 0.30), Color.WHITE, 26, 18)
	btn_next.pressed.connect(func():
		if AudioSynth: AudioSynth.play_sfx("ui_confirm")
		if GameState.selected_mode == GameState.GameMode.GRAND_PRIX:
			GameState.start_grand_prix()
			start_race_requested.emit()
		else:
			_current_screen = Screen.TRACK_SELECT
			_render_screen()
	)
	left.add_child(btn_next)

	# Right Open Spacer over 3D Turntable
	var right_sp := Control.new()
	right_sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right_sp.size_flags_stretch_ratio = 0.95
	right_sp.mouse_filter = Control.MOUSE_FILTER_IGNORE
	body_h.add_child(right_sp)

func _add_stat_row(parent: VBoxContainer, label_txt: String, val: float, bar_col: Color) -> void:
	var h := HBoxContainer.new()
	h.layout_direction = Control.LAYOUT_DIRECTION_LTR
	h.add_theme_constant_override("separation", 10)
	var l := UITheme.make_label(label_txt, 17, Color.WHITE, HORIZONTAL_ALIGNMENT_LEFT, 4)
	l.custom_minimum_size = Vector2(118, 0)
	h.add_child(l)
	var bar := ProgressBar.new()
	bar.min_value = 0.0
	bar.max_value = 100.0
	bar.value = val * 100.0
	bar.show_percentage = false
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.custom_minimum_size = Vector2(0, 22)
	var fill_sb := StyleBoxFlat.new()
	fill_sb.bg_color = bar_col
	fill_sb.set_corner_radius_all(8)
	bar.add_theme_stylebox_override("fill", fill_sb)
	var bg_sb := StyleBoxFlat.new()
	bg_sb.bg_color = Color(0.14, 0.16, 0.22)
	bg_sb.set_corner_radius_all(8)
	bar.add_theme_stylebox_override("background", bg_sb)
	h.add_child(bar)
	parent.add_child(h)

func _build_track_select_ui() -> void:
	var mc := _make_root_margin()
	var main_v := VBoxContainer.new()
	main_v.layout_direction = Control.LAYOUT_DIRECTION_LTR
	main_v.add_theme_constant_override("separation", 14)
	mc.add_child(main_v)

	main_v.add_child(_make_top_bar(true, GameState.t("select_track")))

	var cards_h := HBoxContainer.new()
	cards_h.layout_direction = Control.LAYOUT_DIRECTION_LTR
	cards_h.size_flags_vertical = Control.SIZE_EXPAND_FILL
	cards_h.add_theme_constant_override("separation", 16)
	main_v.add_child(cards_h)

	for i in range(GameState.TRACKS.size()):
		var tr: Dictionary = GameState.TRACKS[i]
		var sel := (i == GameState.selected_track_index)
		var card := PanelContainer.new()
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var bg: Color = tr["card_color_a"].darkened(0.28) if sel else Color(0.08, 0.11, 0.20, 0.90)
		var border: Color = Color(1.0, 0.88, 0.16) if sel else tr["card_color_b"]
		card.add_theme_stylebox_override("panel", UITheme.panel_box(bg, border, 20, 6 if sel else 3, 10))
		cards_h.add_child(card)

		var cv := VBoxContainer.new()
		cv.add_theme_constant_override("separation", 8)
		card.add_child(cv)

		var stars := "★".repeat(int(tr["difficulty"])) + "☆".repeat(3 - int(tr["difficulty"]))
		cv.add_child(UITheme.make_label("%s  •  %s" % [stars, tr.get("peak_fire_" + GameState.language, "")], 17, tr["peak_fire_color"], HORIZONTAL_ALIGNMENT_CENTER, 4))
		cv.add_child(UITheme.make_label(GameState.get_track_name(tr), 24, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER, 6))

		var sub := UITheme.make_label(tr.get("subtitle_" + GameState.language, ""), 15, Color(0.90, 0.95, 1.0), HORIZONTAL_ALIGNMENT_CENTER, 3)
		sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		cv.add_child(sub)

		var best_sec := float(GameState.best_race_times.get(tr["id"], -1.0))
		cv.add_child(UITheme.make_label("%s: %s" % [GameState.t("best_time"), GameState.format_time(best_sec)], 18, Color(1.0, 0.88, 0.30), HORIZONTAL_ALIGNMENT_CENTER, 4))

		var sc_found := GameState.count_track_shortcuts(tr)
		cv.add_child(UITheme.make_label("%s: %d / 3" % [GameState.t("shortcuts_label"), sc_found], 16, Color(0.32, 1.0, 0.74), HORIZONTAL_ALIGNMENT_CENTER, 4))

		var spacer := Control.new()
		spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
		cv.add_child(spacer)

		var pick_btn := Button.new()
		pick_btn.text = ("✓ " + GameState.get_track_name(tr)) if sel else GameState.t("select_track")
		pick_btn.custom_minimum_size = Vector2(0, 56)
		UITheme.style_button(pick_btn, tr["card_color_b"] if sel else Color(0.20, 0.32, 0.56), Color.WHITE, 18, 14)
		var tidx := i
		pick_btn.pressed.connect(func():
			if AudioSynth: AudioSynth.play_sfx("ui_click")
			GameState.selected_track_index = tidx
			_render_screen()
		)
		cv.add_child(pick_btn)

	var bot := HBoxContainer.new()
	bot.layout_direction = Control.LAYOUT_DIRECTION_LTR
	bot.add_theme_constant_override("separation", 16)
	main_v.add_child(bot)

	if GameState.selected_mode == GameState.GameMode.ARCADE_RACE:
		var diff_btn := Button.new()
		diff_btn.text = "%s: %s" % [GameState.t("difficulty"), GameState.t("diff_" + str(GameState.ai_difficulty))]
		diff_btn.custom_minimum_size = Vector2(260, 70)
		UITheme.style_button(diff_btn, Color(0.42, 0.22, 0.72), Color.WHITE, 19, 16)
		diff_btn.pressed.connect(func():
			if AudioSynth: AudioSynth.play_sfx("ui_click")
			GameState.ai_difficulty = (GameState.ai_difficulty + 1) % 3
			GameState.save_data()
			_render_screen()
		)
		bot.add_child(diff_btn)

	var mir_btn := Button.new()
	mir_btn.text = GameState.t("mirror_on") if GameState.mirror_mode else GameState.t("mirror_off")
	mir_btn.custom_minimum_size = Vector2(240, 70)
	UITheme.style_button(mir_btn, Color(0.08, 0.56, 0.76) if GameState.mirror_mode else Color(0.22, 0.28, 0.42), Color.WHITE, 19, 16)
	mir_btn.pressed.connect(func():
		if AudioSynth: AudioSynth.play_sfx("ui_click")
		GameState.mirror_mode = not GameState.mirror_mode
		_render_screen()
	)
	bot.add_child(mir_btn)

	var go_btn := Button.new()
	go_btn.text = GameState.t("start_race")
	go_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	go_btn.custom_minimum_size = Vector2(0, 70)
	UITheme.style_button(go_btn, Color(0.14, 0.80, 0.28), Color.WHITE, 28, 18)
	go_btn.pressed.connect(func():
		if AudioSynth: AudioSynth.play_sfx("countdown_go", 1.0, 0.9)
		start_race_requested.emit()
	)
	bot.add_child(go_btn)

func _build_guide_ui() -> void:
	var mc := _make_root_margin()
	var v_root := VBoxContainer.new()
	v_root.layout_direction = Control.LAYOUT_DIRECTION_LTR
	v_root.add_theme_constant_override("separation", 14)
	mc.add_child(v_root)

	v_root.add_child(_make_top_bar(true, GameState.t("academy")))

	var panel := PanelContainer.new()
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel.add_theme_stylebox_override("panel", UITheme.panel_box(Color(0.07, 0.10, 0.18, 0.95), Color(0.18, 0.86, 1.0), 22, 4, 10))
	v_root.add_child(panel)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.add_child(scroll)

	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_theme_constant_override("separation", 14)
	scroll.add_child(v)

	var body := UITheme.make_label(GameState.t("guide_body"), 20, Color(0.96, 0.98, 1.0), HORIZONTAL_ALIGNMENT_RIGHT if GameState.is_rtl() else HORIZONTAL_ALIGNMENT_LEFT, 4)
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_child(body)

func _build_settings_ui() -> void:
	var mc := _make_root_margin()
	var v_root := VBoxContainer.new()
	v_root.layout_direction = Control.LAYOUT_DIRECTION_LTR
	v_root.add_theme_constant_override("separation", 14)
	mc.add_child(v_root)

	v_root.add_child(_make_top_bar(true, GameState.t("settings")))

	var panel := PanelContainer.new()
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel.add_theme_stylebox_override("panel", UITheme.panel_box(Color(0.08, 0.11, 0.20, 0.95), Color(1.0, 0.72, 0.14), 22, 4, 10))
	v_root.add_child(panel)

	var scroll := ScrollContainer.new()
	panel.add_child(scroll)

	var grid := GridContainer.new()
	grid.columns = 2
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 16)
	grid.add_theme_constant_override("v_separation", 14)
	scroll.add_child(grid)

	_add_toggle_btn(grid, "%s: %s" % [GameState.t("steer_mode"), GameState.t("steer_stick") if GameState.use_joystick else GameState.t("steer_buttons")], Color(0.16, 0.50, 0.88), func():
		GameState.use_joystick = not GameState.use_joystick
		GameState.save_data()
		_render_screen()
	)
	_add_toggle_btn(grid, "%s: %s" % [GameState.t("auto_gas"), GameState.t("on") if GameState.auto_accelerate else GameState.t("off")], Color(0.14, 0.68, 0.34), func():
		GameState.auto_accelerate = not GameState.auto_accelerate
		GameState.save_data()
		_render_screen()
	)
	_add_toggle_btn(grid, "%s: %s" % [GameState.t("telemetry"), GameState.t("on") if GameState.show_ctr_telemetry else GameState.t("off")], Color(0.92, 0.52, 0.08), func():
		GameState.show_ctr_telemetry = not GameState.show_ctr_telemetry
		GameState.save_data()
		_render_screen()
	)
	_add_toggle_btn(grid, "%s: %d%%" % [GameState.t("btn_opacity"), int(round(GameState.controls_opacity * 100.0))], Color(0.14, 0.56, 0.68), func():
		GameState.controls_opacity = 0.65 if GameState.controls_opacity > 0.95 else (0.85 if GameState.controls_opacity < 0.75 else 1.0)
		GameState.save_data()
		_render_screen()
	)
	_add_toggle_btn(grid, "%s: %d%%" % [GameState.t("sfx_vol"), int(round(GameState.sfx_volume * 100.0))], Color(0.56, 0.22, 0.78), func():
		GameState.sfx_volume = fmod(GameState.sfx_volume + 0.25, 1.25)
		if GameState.sfx_volume > 1.01: GameState.sfx_volume = 0.0
		GameState.save_data()
		GameState.settings_changed.emit()
		_render_screen()
	)
	_add_toggle_btn(grid, "%s: %d%%" % [GameState.t("music_vol"), int(round(GameState.music_volume * 100.0))], Color(0.46, 0.26, 0.72), func():
		GameState.music_volume = fmod(GameState.music_volume + 0.25, 1.25)
		if GameState.music_volume > 1.01: GameState.music_volume = 0.0
		GameState.save_data()
		GameState.settings_changed.emit()
		_render_screen()
	)
	_add_toggle_btn(grid, "%s: %s" % [GameState.t("graphics_mode"), GameState.t("gfx_high") if GameState.graphics_high else GameState.t("gfx_fast")], Color(0.78, 0.34, 0.14), func():
		GameState.graphics_high = not GameState.graphics_high
		GameState.save_data()
		_render_screen()
	)
	_add_toggle_btn(grid, "%s: %s" % [GameState.t("lang_label"), "العربية" if GameState.language == "ar" else "English"], Color(0.14, 0.44, 0.84), func():
		GameState.toggle_language()
	)

func _add_toggle_btn(parent: Control, txt: String, col: Color, cb: Callable) -> void:
	var b := Button.new()
	b.text = txt
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.custom_minimum_size = Vector2(0, 68)
	UITheme.style_button(b, col, Color.WHITE, 19, 16)
	b.pressed.connect(func():
		if AudioSynth: AudioSynth.play_sfx("ui_click")
		cb.call()
	)
	parent.add_child(b)
