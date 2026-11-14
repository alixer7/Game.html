class_name MenuSystem
extends Control
## All menu screens, built in code: main, match setup, garage, settings,
## pause, end-of-match and tutorial.

signal start_match(cfg: Dictionary)
signal start_freeplay
signal resume_requested
signal restart_requested
signal main_menu_requested
signal tutorial_closed

var pages := {}
var current := ""
var _settings_return := "main"
var _preview: CarPreview
var _end_results := {}
var _settings_tab := 0


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	theme = UiTheme.theme()
	process_mode = Node.PROCESS_MODE_ALWAYS
	rebuild()


func rebuild() -> void:
	var keep := current
	for c in get_children():
		c.queue_free()
	pages.clear()
	layout_direction = Control.LAYOUT_DIRECTION_RTL if Loc.is_rtl() else Control.LAYOUT_DIRECTION_LTR
	_build_main()
	_build_play()
	_build_garage()
	_build_settings()
	_build_pause()
	_build_end()
	_build_tutorial()
	current = ""
	show_page(keep if keep != "" else "main")


func show_page(nm: String) -> void:
	current = nm
	for k in pages:
		var p: Control = pages[k]
		p.visible = k == nm
	visible = nm != ""
	if nm != "" and pages.has(nm):
		var p: Control = pages[nm]
		p.modulate.a = 0.0
		var tw := create_tween()
		tw.tween_property(p, "modulate:a", 1.0, 0.18)
	if nm == "end" and not _end_results.is_empty():
		_fill_end(_end_results)


func hide_all() -> void:
	show_page("")


# ------------------------------------------------------------------ helpers

func _page(nm: String) -> Control:
	var c := Control.new()
	c.name = nm
	c.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	c.mouse_filter = Control.MOUSE_FILTER_STOP if nm != "main" else Control.MOUSE_FILTER_IGNORE
	add_child(c)
	pages[nm] = c
	return c


func _btn(text: String, cb: Callable, size: int = 26, min_w: float = 0.0, accent: bool = false) -> Button:
	var b := Button.new()
	b.text = text
	b.add_theme_font_size_override("font_size", size)
	b.custom_minimum_size = Vector2(min_w, size * 2.1)
	b.focus_mode = Control.FOCUS_NONE
	if accent:
		b.add_theme_stylebox_override("normal", UiTheme.box(Color(0.1, 0.45, 0.85, 0.95), 14, Color(0.6, 0.85, 1.0, 0.6), 2))
		b.add_theme_stylebox_override("hover", UiTheme.box(Color(0.15, 0.55, 0.95, 1.0), 14, Color(0.7, 0.9, 1.0, 0.9), 2))
		b.add_theme_stylebox_override("pressed", UiTheme.box(Color(0.08, 0.35, 0.7, 1.0), 14, Color(0.7, 0.9, 1.0, 0.9), 2))
	b.pressed.connect(func():
		Sfx.play("click", -6.0)
		cb.call())
	return b


func _panel(parent: Control, min_size: Vector2) -> VBoxContainer:
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	parent.add_child(center)
	var p := PanelContainer.new()
	p.custom_minimum_size = min_size
	var sb := UiTheme.box(UiTheme.PANEL, 24, Color(1, 1, 1, 0.08), 2)
	sb.content_margin_left = 34
	sb.content_margin_right = 34
	sb.content_margin_top = 24
	sb.content_margin_bottom = 24
	sb.shadow_color = Color(0, 0, 0, 0.45)
	sb.shadow_size = 24
	p.add_theme_stylebox_override("panel", sb)
	center.add_child(p)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 14)
	p.add_child(v)
	return v


func _dim(parent: Control, alpha: float = 0.55) -> void:
	var r := ColorRect.new()
	r.color = Color(0.0, 0.01, 0.04, alpha)
	r.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	r.mouse_filter = Control.MOUSE_FILTER_STOP
	parent.add_child(r)


func _title(parent: Control, text: String, size: int = 44) -> Label:
	var l := UiTheme.label(text, size, Color.WHITE, true)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	parent.add_child(l)
	return l


func _toggle_row(parent: Control, caption: String, options: Array, current_value: Variant, cb: Callable) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	parent.add_child(row)
	var l := UiTheme.label(caption, 22, UiTheme.TEXT_DIM)
	l.custom_minimum_size = Vector2(170, 0)
	row.add_child(l)
	var group := ButtonGroup.new()
	for opt in options:
		var b := Button.new()
		b.text = opt[0]
		b.toggle_mode = true
		b.button_group = group
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(118, 54)
		b.add_theme_font_size_override("font_size", 22)
		b.add_theme_stylebox_override("pressed", UiTheme.box(Color(0.1, 0.45, 0.85, 0.95), 12, Color(0.6, 0.85, 1.0, 0.8), 2))
		b.button_pressed = opt[1] == current_value
		var val: Variant = opt[1]
		b.toggled.connect(func(on: bool):
			if on:
				Sfx.play("click", -8.0)
				cb.call(val))
		row.add_child(b)


func _slider_row(parent: Control, caption: String, key: String, lo: float, hi: float, step: float, fmt: String = "%.2f") -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	parent.add_child(row)
	var l := UiTheme.label(caption, 22, UiTheme.TEXT)
	l.custom_minimum_size = Vector2(260, 0)
	row.add_child(l)
	var s := HSlider.new()
	s.min_value = lo
	s.max_value = hi
	s.step = step
	s.value = float(Settings.get_value(key, lo))
	s.custom_minimum_size = Vector2(300, 40)
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.focus_mode = Control.FOCUS_NONE
	row.add_child(s)
	var vl := UiTheme.label(fmt % s.value, 22, UiTheme.ACCENT)
	vl.custom_minimum_size = Vector2(80, 0)
	row.add_child(vl)
	s.value_changed.connect(func(v: float):
		vl.text = fmt % v
		Settings.set_value(key, v))


func _check_row(parent: Control, caption: String, key: String) -> void:
	var c := CheckButton.new()
	c.text = caption
	c.button_pressed = bool(Settings.get_value(key, false))
	c.focus_mode = Control.FOCUS_NONE
	c.add_theme_font_size_override("font_size", 22)
	c.toggled.connect(func(on: bool):
		Sfx.play("click", -8.0)
		Settings.set_value(key, on))
	parent.add_child(c)


# ------------------------------------------------------------------ main

func _build_main() -> void:
	var p := _page("main")
	p.layout_direction = Control.LAYOUT_DIRECTION_LTR
	var grad := TextureRect.new()
	var g := Gradient.new()
	g.set_color(0, Color(0.0, 0.02, 0.06, 0.92))
	g.set_color(1, Color(0.0, 0.02, 0.06, 0.0))
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.fill_from = Vector2(0, 0)
	gt.fill_to = Vector2(1, 0)
	grad.texture = gt
	grad.stretch_mode = TextureRect.STRETCH_SCALE
	grad.set_anchors_and_offsets_preset(Control.PRESET_LEFT_WIDE)
	grad.offset_right = 760
	grad.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(grad)

	var col := VBoxContainer.new()
	col.set_anchors_and_offsets_preset(Control.PRESET_LEFT_WIDE)
	col.offset_left = 70
	col.offset_right = 520
	col.offset_top = 24
	col.offset_bottom = -24
	col.add_theme_constant_override("separation", 10)
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	p.add_child(col)

	var logo_box := VBoxContainer.new()
	logo_box.add_theme_constant_override("separation", -46)
	col.add_child(logo_box)
	var logo := UiTheme.label("NITRO", 84, Color(0.35, 0.8, 1.0), true)
	logo.add_theme_constant_override("outline_size", 10)
	logo.add_theme_color_override("font_outline_color", Color(0.0, 0.2, 0.5, 0.8))
	logo_box.add_child(logo)
	var logo2 := UiTheme.label("STRIKERS", 58, Color(1.0, 0.6, 0.2), true)
	logo2.add_theme_constant_override("outline_size", 8)
	logo2.add_theme_color_override("font_outline_color", Color(0.4, 0.1, 0.0, 0.8))
	logo_box.add_child(logo2)
	var sub := UiTheme.label(Loc.t("subtitle"), 22, UiTheme.TEXT_DIM)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	col.add_child(sub)
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 8)
	col.add_child(spacer)
	col.add_child(_btn(Loc.t("play"), func(): show_page("play"), 32, 380, true))
	col.add_child(_btn(Loc.t("free_play"), func(): start_freeplay.emit(), 24, 380))
	col.add_child(_btn(Loc.t("garage"), func(): show_page("garage"), 24, 380))
	col.add_child(_btn(Loc.t("settings"), func():
		_settings_return = "main"
		show_page("settings"), 24, 380))
	if not OS.has_feature("mobile") and not OS.has_feature("web"):
		col.add_child(_btn(Loc.t("quit"), func(): get_tree().quit(), 20, 380))

	var lang := _btn("English" if Loc.is_rtl() else "العربية", func():
		Settings.set_value("language", "en" if Loc.is_rtl() else "ar")
		rebuild(), 20, 150)
	lang.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	lang.offset_left = -190
	lang.offset_right = -30
	lang.offset_top = -80
	lang.offset_bottom = -26
	p.add_child(lang)
	var ver := UiTheme.label("v1.0", 16, Color(1, 1, 1, 0.35))
	ver.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	ver.offset_top = -34
	ver.offset_left = 24
	p.add_child(ver)


# ------------------------------------------------------------------ play

func _build_play() -> void:
	var p := _page("play")
	_dim(p, 0.5)
	var v := _panel(p, Vector2(760, 0))
	_title(v, Loc.t("match_setup"))
	_toggle_row(v, Loc.t("mode"), [["1v1", 1], ["2v2", 2], ["3v3", 3]], int(Settings.get_value("mode", 2)),
		func(x): Settings.set_value("mode", x))
	_toggle_row(v, Loc.t("difficulty"), [[Loc.t("rookie"), 0], [Loc.t("pro"), 1], [Loc.t("allstar"), 2]],
		int(Settings.get_value("difficulty", 1)), func(x): Settings.set_value("difficulty", x))
	_toggle_row(v, Loc.t("duration"), [["3 " + Loc.t("min"), 3], ["5 " + Loc.t("min"), 5], ["7 " + Loc.t("min"), 7], [Loc.t("unlimited"), 0]],
		int(Settings.get_value("match_minutes", 5)), func(x): Settings.set_value("match_minutes", x))
	_toggle_row(v, Loc.t("team"), [[Loc.t("blue"), 0], [Loc.t("orange"), 1]], int(Settings.get_value("team", 0)),
		func(x): Settings.set_value("team", x))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_child(row)
	row.add_child(_btn(Loc.t("back"), func(): show_page("main"), 24, 200))
	row.add_child(_btn(Loc.t("start"), func():
		start_match.emit({"size": int(Settings.get_value("mode", 2)), "difficulty": int(Settings.get_value("difficulty", 1)),
			"minutes": int(Settings.get_value("match_minutes", 5)), "team": int(Settings.get_value("team", 0))}), 30, 300, true))


# ------------------------------------------------------------------ garage

func _build_garage() -> void:
	var p := _page("garage")
	_dim(p, 0.75)
	var h := HBoxContainer.new()
	h.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	h.offset_left = 40
	h.offset_right = -40
	h.offset_top = 30
	h.offset_bottom = -30
	h.add_theme_constant_override("separation", 24)
	p.add_child(h)
	_preview = CarPreview.new()
	_preview.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_preview.size_flags_stretch_ratio = 1.4
	h.add_child(_preview)
	var side := VBoxContainer.new()
	side.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	side.add_theme_constant_override("separation", 16)
	side.alignment = BoxContainer.ALIGNMENT_CENTER
	h.add_child(side)
	_title(side, Loc.t("garage"), 48)
	# body selector
	var body_row := HBoxContainer.new()
	body_row.alignment = BoxContainer.ALIGNMENT_CENTER
	body_row.add_theme_constant_override("separation", 12)
	side.add_child(body_row)
	var body_lbl := UiTheme.label(CarSim.BODIES[int(Settings.get_value("car_body", 0))]["name"], 32, Color.WHITE, true)
	body_lbl.custom_minimum_size = Vector2(220, 0)
	body_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var change := func(d: int):
		var n := CarSim.BODIES.size()
		var b := (int(Settings.get_value("car_body", 0)) + d + n) % n
		Settings.set_value("car_body", b)
		body_lbl.text = CarSim.BODIES[b]["name"]
		_preview.refresh()
	body_row.add_child(_btn("‹" if not Loc.is_rtl() else "›", func(): change.call(-1), 30, 70))
	body_row.add_child(body_lbl)
	body_row.add_child(_btn("›" if not Loc.is_rtl() else "‹", func(): change.call(1), 30, 70))
	side.add_child(UiTheme.label(Loc.t("accent"), 22, UiTheme.TEXT_DIM))
	side.add_child(_swatches(Settings.ACCENTS, "car_accent"))
	side.add_child(UiTheme.label(Loc.t("boost_trail"), 22, UiTheme.TEXT_DIM))
	side.add_child(_swatches(Settings.BOOST_COLORS, "boost_color"))
	side.add_child(UiTheme.label(Loc.t("name"), 22, UiTheme.TEXT_DIM))
	var name_edit := LineEdit.new()
	name_edit.text = str(Settings.get_value("player_name", "PLAYER"))
	name_edit.max_length = 14
	name_edit.custom_minimum_size = Vector2(300, 54)
	name_edit.add_theme_font_size_override("font_size", 24)
	name_edit.add_theme_stylebox_override("normal", UiTheme.box(UiTheme.PANEL_LIGHT, 12, Color(1, 1, 1, 0.12), 2))
	name_edit.add_theme_stylebox_override("focus", UiTheme.box(UiTheme.PANEL_LIGHT, 12, UiTheme.ACCENT, 2))
	name_edit.text_changed.connect(func(t: String):
		Settings.set_value("player_name", t.strip_edges() if t.strip_edges() != "" else "PLAYER"))
	side.add_child(name_edit)
	side.add_child(_btn(Loc.t("back"), func(): show_page("main"), 24, 220))


func _swatches(colors: Array, key: String) -> HFlowContainer:
	var f := HFlowContainer.new()
	f.add_theme_constant_override("h_separation", 10)
	f.add_theme_constant_override("v_separation", 10)
	var buttons: Array = []
	for i in range(colors.size()):
		var b := Button.new()
		b.custom_minimum_size = Vector2(56, 56)
		b.focus_mode = Control.FOCUS_NONE
		var col: Color = colors[i]
		var sel := int(Settings.get_value(key, 0)) == i
		b.add_theme_stylebox_override("normal", UiTheme.box(col, 28, Color.WHITE if sel else Color(1, 1, 1, 0.15), 4 if sel else 2))
		b.add_theme_stylebox_override("hover", UiTheme.box(col.lightened(0.15), 28, Color(1, 1, 1, 0.6), 3))
		b.add_theme_stylebox_override("pressed", UiTheme.box(col, 28, Color.WHITE, 4))
		var idx := i
		b.pressed.connect(func():
			Sfx.play("click", -8.0)
			Settings.set_value(key, idx)
			for k in range(buttons.size()):
				var bb: Button = buttons[k]
				var c2: Color = colors[k]
				bb.add_theme_stylebox_override("normal", UiTheme.box(c2, 28, Color.WHITE if k == idx else Color(1, 1, 1, 0.15), 4 if k == idx else 2))
			_preview.refresh())
		buttons.append(b)
		f.add_child(b)
	return f


# ------------------------------------------------------------------ settings

func _build_settings() -> void:
	var p := _page("settings")
	_dim(p, 0.6)
	var v := _panel(p, Vector2(900, 560))
	_title(v, Loc.t("settings"), 40)
	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 8)
	tabs.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_child(tabs)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(820, 380)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	v.add_child(scroll)
	var content := VBoxContainer.new()
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 12)
	scroll.add_child(content)
	var names := [Loc.t("general"), Loc.t("controls"), Loc.t("camera"), Loc.t("graphics")]
	var group := ButtonGroup.new()
	for i in range(names.size()):
		var b := Button.new()
		b.text = names[i]
		b.toggle_mode = true
		b.button_group = group
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(170, 50)
		b.add_theme_font_size_override("font_size", 22)
		b.add_theme_stylebox_override("pressed", UiTheme.box(Color(0.1, 0.45, 0.85, 0.95), 12, Color(0.6, 0.85, 1.0, 0.8), 2))
		b.button_pressed = i == _settings_tab
		var idx := i
		b.toggled.connect(func(on: bool):
			if on:
				_settings_tab = idx
				_fill_settings(content, idx))
		tabs.add_child(b)
	_fill_settings(content, _settings_tab)
	var back := _btn(Loc.t("back"), func(): show_page(_settings_return), 24, 220)
	back.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	v.add_child(back)


func _fill_settings(content: VBoxContainer, tab: int) -> void:
	for c in content.get_children():
		c.queue_free()
	match tab:
		0:
			_toggle_row(content, Loc.t("language"), [["العربية", "ar"], ["English", "en"]], str(Settings.get_value("language", "ar")),
				func(x):
					Settings.set_value("language", x)
					rebuild())
			_check_row(content, Loc.t("vibration"), "vibration")
			_check_row(content, Loc.t("replay"), "replays")
			_check_row(content, Loc.t("show_fps"), "show_fps")
			_slider_row(content, Loc.t("sfx_volume"), "sfx_volume", 0.0, 1.0, 0.05)
			_slider_row(content, Loc.t("music_volume"), "music_volume", 0.0, 1.0, 0.05)
		1:
			_slider_row(content, Loc.t("joystick_size"), "joystick_size", 0.7, 1.5, 0.05)
			_slider_row(content, Loc.t("button_size"), "button_size", 0.7, 1.4, 0.05)
			_slider_row(content, Loc.t("opacity"), "controls_opacity", 0.3, 1.0, 0.05)
			_slider_row(content, Loc.t("sensitivity"), "steer_sensitivity", 0.6, 1.6, 0.05)
			_check_row(content, Loc.t("left_handed"), "left_handed")
			_check_row(content, Loc.t("auto_throttle"), "auto_throttle")
		2:
			_slider_row(content, Loc.t("fov"), "cam_fov", 80.0, 115.0, 1.0, "%.0f")
			_slider_row(content, Loc.t("cam_distance"), "cam_distance", 2.2, 4.2, 0.05)
			_slider_row(content, Loc.t("cam_height"), "cam_height", 0.6, 1.8, 0.05)
			_slider_row(content, Loc.t("cam_angle"), "cam_angle", -12.0, 2.0, 0.5, "%.1f")
			_slider_row(content, Loc.t("cam_stiffness"), "cam_stiffness", 0.0, 1.0, 0.05)
			_check_row(content, Loc.t("ball_cam_default"), "ball_cam")
		3:
			_toggle_row(content, Loc.t("quality"), [[Loc.t("low"), 0], [Loc.t("medium"), 1], [Loc.t("high"), 2]],
				int(Settings.get_value("quality", 2)), func(x): Settings.set_value("quality", x))
			_toggle_row(content, Loc.t("fps"), [["30", 30], ["60", 60], ["120", 120]], int(Settings.get_value("max_fps", 60)),
				func(x): Settings.set_value("max_fps", x))


func open_settings_from_pause() -> void:
	_settings_return = "pause"
	show_page("settings")


# ------------------------------------------------------------------ pause

func _build_pause() -> void:
	var p := _page("pause")
	_dim(p, 0.6)
	var v := _panel(p, Vector2(460, 0))
	_title(v, Loc.t("paused"), 46)
	v.add_child(_btn(Loc.t("resume"), func(): resume_requested.emit(), 28, 380, true))
	v.add_child(_btn(Loc.t("restart"), func(): restart_requested.emit(), 24, 380))
	v.add_child(_btn(Loc.t("settings"), func(): open_settings_from_pause(), 24, 380))
	v.add_child(_btn(Loc.t("main_menu"), func(): main_menu_requested.emit(), 24, 380))


# ------------------------------------------------------------------ end

func _build_end() -> void:
	var p := _page("end")
	_dim(p, 0.55)
	var v := _panel(p, Vector2(980, 0))
	v.name = "EndBox"


func show_end(results: Dictionary) -> void:
	_end_results = results
	show_page("end")


func _fill_end(res: Dictionary) -> void:
	var box: VBoxContainer = pages["end"].find_child("EndBox", true, false)
	if box == null:
		return
	for c in box.get_children():
		c.queue_free()
	var winner: int = res["winner"]
	var pt: int = res.get("player_team", -1)
	var title: String
	var col: Color
	if pt >= 0:
		title = Loc.t("victory") if pt == winner else Loc.t("defeat")
		col = Color(1.0, 0.85, 0.3) if pt == winner else Color(0.75, 0.8, 0.9)
	else:
		title = Loc.t("blue_wins") if winner == 0 else Loc.t("orange_wins")
		col = Phys.team_color(winner)
	var t := _title(box, title, 64)
	t.add_theme_color_override("font_color", col)
	var sc: Array = res["score"]
	var score_row := HBoxContainer.new()
	score_row.alignment = BoxContainer.ALIGNMENT_CENTER
	score_row.layout_direction = Control.LAYOUT_DIRECTION_LTR
	score_row.add_theme_constant_override("separation", 26)
	box.add_child(score_row)
	score_row.add_child(UiTheme.label(str(sc[0]), 56, UiTheme.BLUE, true))
	score_row.add_child(UiTheme.label("-", 48, UiTheme.TEXT_DIM, true))
	score_row.add_child(UiTheme.label(str(sc[1]), 56, UiTheme.ORANGE, true))
	# table
	var grid := GridContainer.new()
	grid.columns = 6
	grid.add_theme_constant_override("h_separation", 26)
	grid.add_theme_constant_override("v_separation", 6)
	box.add_child(grid)
	for h in [Loc.t("player"), Loc.t("score"), Loc.t("goals"), Loc.t("assists"), Loc.t("saves"), Loc.t("shots")]:
		grid.add_child(UiTheme.label(h, 20, UiTheme.TEXT_DIM))
	var stats: Dictionary = res["stats"]
	var mvp := -1
	var mvp_score := -1
	for id in stats:
		var s: Dictionary = stats[id]
		if s["team"] == winner and s["score"] > mvp_score:
			mvp_score = s["score"]
			mvp = id
	for team in [0, 1]:
		var ids: Array = []
		for id in stats:
			if stats[id]["team"] == team:
				ids.append(id)
		ids.sort_custom(func(a, b): return stats[a]["score"] > stats[b]["score"])
		for id in ids:
			var s: Dictionary = stats[id]
			var nm: String = s["name"]
			if s["player"]:
				nm += "  (" + Loc.t("you") + ")"
			if id == mvp:
				nm = "★ " + nm
			var tc := Phys.team_color(team).lerp(Color.WHITE, 0.35)
			grid.add_child(UiTheme.label(nm, 22, tc, true))
			for k in ["score", "goals", "assists", "saves", "shots"]:
				grid.add_child(UiTheme.label(str(s[k]), 22, Color.WHITE))
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 16)
	box.add_child(row)
	row.add_child(_btn(Loc.t("main_menu"), func(): main_menu_requested.emit(), 24, 260))
	row.add_child(_btn(Loc.t("rematch"), func(): restart_requested.emit(), 28, 300, true))


# ------------------------------------------------------------------ tutorial

func _build_tutorial() -> void:
	var p := _page("tutorial")
	_dim(p, 0.65)
	var v := _panel(p, Vector2(820, 0))
	_title(v, Loc.t("hint_title"), 40)
	for k in ["hint_joystick", "hint_jump", "hint_boost", "hint_drift", "hint_cam"]:
		var l := UiTheme.label("•  " + Loc.t(k), 22, UiTheme.TEXT)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.custom_minimum_size = Vector2(740, 0)
		v.add_child(l)
	var b := _btn(Loc.t("got_it"), func():
		Settings.set_value("tutorial_seen", true)
		tutorial_closed.emit(), 28, 260, true)
	b.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	v.add_child(b)
