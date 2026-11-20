class_name Menus
extends CanvasLayer
## All menu screens (main, garage, events map, settings, controls & layout
## editor, pause, results, loading). Emits intents for main.gd to handle.

signal free_roam
signal start_event(e: Dictionary)
signal travel_event(e: Dictionary)
signal resume
signal restart
signal quit_race
signal to_main_menu
signal car_changed(id: String, color_idx: int)
signal layout_editing(on: bool)
signal settings_applied(need_reload: bool)

var root: Control
var screen: Control
var current := ""
var touch: TouchControls
var edit_panel: PanelContainer
var size_slider: HSlider
var _garage_idx := 0
var _garage_color := 0
var _loading_bar: ProgressBar
var _loading_label: Label
var _sel_event: Dictionary = {}
var _event_panel: VBoxContainer


func _ready() -> void:
	layer = 10
	process_mode = Node.PROCESS_MODE_ALWAYS
	root = Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.theme = UITheme.theme()
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)


func _rtl() -> void:
	root.layout_direction = Control.LAYOUT_DIRECTION_RTL if Game.is_rtl() else Control.LAYOUT_DIRECTION_LTR


func clear() -> void:
	if screen:
		screen.queue_free()
		screen = null
	current = ""
	if edit_panel:
		edit_panel.queue_free()
		edit_panel = null


func is_open() -> bool:
	return screen != null


func _new_screen(name: String, dim := 0.55) -> Control:
	clear()
	_rtl()
	current = name
	screen = Control.new()
	screen.set_anchors_preset(Control.PRESET_FULL_RECT)
	screen.mouse_filter = Control.MOUSE_FILTER_STOP
	root.add_child(screen)
	if dim > 0.0:
		var bg := ColorRect.new()
		bg.set_anchors_preset(Control.PRESET_FULL_RECT)
		bg.color = Color(0.02, 0.03, 0.05, dim)
		bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
		screen.add_child(bg)
	return screen


func _panel(parent: Control, anchor: int, size: Vector2, pos := Vector2.ZERO) -> PanelContainer:
	var p := PanelContainer.new()
	p.set_anchors_preset(anchor)
	p.custom_minimum_size = size
	p.position = pos
	parent.add_child(p)
	return p


func _click() -> void:
	Game.sfx.play_ui("click", -10.0)


func _btn(parent: Control, text: String, cb: Callable, size := 24, w := 300.0) -> Button:
	var b := UITheme.button(text, size, w)
	b.pressed.connect(func():
		_click()
		cb.call())
	parent.add_child(b)
	return b


# --------------------------------------------------------------------------- loading
func show_loading() -> void:
	var s := _new_screen("loading", 1.0)
	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_CENTER)
	box.position = Vector2(-300, -80)
	box.custom_minimum_size = Vector2(600, 160)
	box.add_theme_constant_override("separation", 14)
	s.add_child(box)
	var title := UITheme.label(Game.t("title"), 64, 800, UITheme.ACCENT)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)
	_loading_label = UITheme.label(Game.t("loading"), 22, 600, UITheme.DIM)
	_loading_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_loading_label)
	_loading_bar = ProgressBar.new()
	_loading_bar.custom_minimum_size = Vector2(600, 12)
	_loading_bar.show_percentage = false
	_loading_bar.max_value = 1.0
	var fill := StyleBoxFlat.new()
	fill.bg_color = UITheme.ACCENT
	fill.set_corner_radius_all(6)
	_loading_bar.add_theme_stylebox_override("fill", fill)
	box.add_child(_loading_bar)


func set_loading(f: float) -> void:
	if _loading_bar:
		_loading_bar.value = f


# --------------------------------------------------------------------------- main menu
func show_main() -> void:
	var s := _new_screen("main", 0.0)
	var grad := TextureRect.new()
	grad.set_anchors_preset(Control.PRESET_FULL_RECT)
	var g := Gradient.new()
	g.set_color(0, Color(0.02, 0.03, 0.05, 0.92))
	g.set_color(1, Color(0.02, 0.03, 0.05, 0.0))
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.fill_from = Vector2(0, 0)
	gt.fill_to = Vector2(0.65, 0)
	grad.texture = gt
	grad.mouse_filter = Control.MOUSE_FILTER_IGNORE
	s.add_child(grad)
	var box := VBoxContainer.new()
	box.position = Vector2(70, maxf(s.get_viewport_rect().size.y * 0.5 - 300.0, 16.0))
	box.add_theme_constant_override("separation", 10)
	s.add_child(box)
	var title := UITheme.label(Game.t("title"), 76, 800, UITheme.ACCENT)
	box.add_child(title)
	box.add_child(UITheme.label(Game.t("subtitle"), 26, 600, UITheme.DIM))
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 16)
	box.add_child(spacer)
	_btn(box, Game.t("free_roam"), func(): free_roam.emit(), 28, 360)
	_btn(box, Game.t("events"), show_events, 28, 360)
	_btn(box, Game.t("garage"), show_garage, 28, 360)
	_btn(box, Game.t("settings"), func(): show_settings("main"), 28, 360)
	_btn(box, Game.t("controls"), func(): show_controls("main"), 28, 360)
	if not Game.is_mobile:
		_btn(box, Game.t("quit"), func(): get_tree().quit(), 28, 360)
	var st := UITheme.label("%d / %d" % [int(Game.stats.races_won), int(Game.stats.races)], 20, 600, UITheme.DIM)
	box.add_child(st)


# --------------------------------------------------------------------------- garage
func show_garage() -> void:
	var s := _new_screen("garage", 0.0)
	_garage_idx = maxi(Game.PLAYER_CARS.find(Game.selected_car), 0)
	_garage_color = Game.selected_color
	var panel := _panel(s, Control.PRESET_TOP_LEFT, Vector2(420, 0))
	panel.position = Vector2(30, 24)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	panel.add_child(box)
	_garage_fill(box)


func _garage_fill(box: VBoxContainer) -> void:
	for c in box.get_children():
		c.queue_free()
	var id: String = Game.PLAYER_CARS[_garage_idx]
	var spec: Dictionary = Game.CARS[id]
	var nav := HBoxContainer.new()
	nav.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_child(nav)
	_btn(nav, "◀", func():
		_garage_idx = (_garage_idx - 1 + Game.PLAYER_CARS.size()) % Game.PLAYER_CARS.size()
		_garage_color = 0
		car_changed.emit(Game.PLAYER_CARS[_garage_idx], 0)
		_garage_fill(box), 26, 60)
	var name_l := UITheme.label(Game.car_name(id), 32, 800)
	name_l.custom_minimum_size = Vector2(240, 0)
	name_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	nav.add_child(name_l)
	_btn(nav, "▶", func():
		_garage_idx = (_garage_idx + 1) % Game.PLAYER_CARS.size()
		_garage_color = 0
		car_changed.emit(Game.PLAYER_CARS[_garage_idx], 0)
		_garage_fill(box), 26, 60)
	var cls := UITheme.label("%s  •  %s  •  %d Nm" % [spec["class"], str(spec.drive).to_upper(), int(spec.torque)], 20, 600, UITheme.DIM)
	cls.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(cls)
	var stat_names := ["speed", "accel", "handling", "offroad"]
	for i in 4:
		var row := HBoxContainer.new()
		box.add_child(row)
		var l := UITheme.label(Game.t(stat_names[i]), 20, 600)
		l.custom_minimum_size = Vector2(150, 0)
		row.add_child(l)
		var bar := ProgressBar.new()
		bar.custom_minimum_size = Vector2(200, 14)
		bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		bar.show_percentage = false
		bar.max_value = 1.0
		bar.value = spec.stats[i]
		var fill := StyleBoxFlat.new()
		fill.bg_color = UITheme.ACCENT
		fill.set_corner_radius_all(6)
		bar.add_theme_stylebox_override("fill", fill)
		row.add_child(bar)
	box.add_child(UITheme.label(Game.t("color"), 20, 600, UITheme.DIM))
	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 10)
	box.add_child(cols)
	var colors: Array = spec.colors
	for ci in colors.size():
		var b := Button.new()
		b.custom_minimum_size = Vector2(54, 54)
		var sb := StyleBoxFlat.new()
		sb.bg_color = colors[ci]
		sb.set_corner_radius_all(27)
		sb.border_color = Color.WHITE if ci == _garage_color else Color(1, 1, 1, 0.2)
		sb.set_border_width_all(3)
		b.add_theme_stylebox_override("normal", sb)
		b.add_theme_stylebox_override("hover", sb)
		b.add_theme_stylebox_override("pressed", sb)
		b.focus_mode = Control.FOCUS_NONE
		var idx := ci
		b.pressed.connect(func():
			_garage_color = idx
			car_changed.emit(id, idx)
			_garage_fill(box))
		cols.add_child(b)
	var sp := Control.new()
	sp.custom_minimum_size = Vector2(0, 10)
	box.add_child(sp)
	_btn(box, Game.t("select"), func():
		Game.selected_car = id
		Game.selected_color = _garage_color
		Game.save_game()
		show_main(), 26, 360)
	_btn(box, Game.t("back"), func():
		car_changed.emit(Game.selected_car, Game.selected_color)
		show_main(), 22, 360)


# --------------------------------------------------------------------------- events map
func show_events() -> void:
	var s := _new_screen("events", 0.75)
	var vp := s.get_viewport_rect().size
	var map_size := minf(vp.y - 60.0, vp.x * 0.58)
	var map := TextureRect.new()
	map.texture = load("res://assets/world/map.png")
	map.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	map.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT
	map.size = Vector2(map_size, map_size)
	map.position = Vector2(30, 30)
	s.add_child(map)
	for e in Game.world.data.events:
		var p: Vector3
		if e.has("route"):
			p = Vector3(e.route[0], 0, e.route[2])
		else:
			p = Vector3(e.pos[0], 0, e.pos[2])
		var uv := Vector2((p.x + 2048.0) / 4096.0, (p.z + 2048.0) / 4096.0)
		var b := Button.new()
		b.custom_minimum_size = Vector2(34, 34)
		b.size = Vector2(34, 34)
		b.position = uv * map_size - Vector2(17, 17)
		var sb := StyleBoxFlat.new()
		var col := Color(1.0, 0.55, 0.1)
		if e.kind == "circuit":
			col = Color(0.2, 0.75, 1.0)
		elif not e.has("route"):
			col = Color(0.75, 0.3, 1.0)
		sb.bg_color = col
		sb.set_corner_radius_all(17)
		sb.border_color = Color.WHITE
		sb.set_border_width_all(2)
		b.add_theme_stylebox_override("normal", sb)
		b.add_theme_stylebox_override("hover", sb)
		b.add_theme_stylebox_override("pressed", sb)
		b.focus_mode = Control.FOCUS_NONE
		b.text = str(Game.world.data.events.find(e) + 1) if e.has("route") else "★"
		var ev: Dictionary = e
		b.pressed.connect(func():
			_click()
			_select_event(ev))
		map.add_child(b)
	var panel := _panel(s, Control.PRESET_TOP_LEFT, Vector2(vp.x - map_size - 100, map_size))
	panel.position = Vector2(map_size + 60, 30)
	_event_panel = VBoxContainer.new()
	_event_panel.add_theme_constant_override("separation", 10)
	panel.add_child(_event_panel)
	_select_event({})


func _select_event(e: Dictionary) -> void:
	_sel_event = e
	for c in _event_panel.get_children():
		c.queue_free()
	if e.is_empty():
		_event_panel.add_child(UITheme.label(Game.t("world_map"), 34, 800, UITheme.ACCENT))
		var hint := UITheme.label(Game.t("tap_event"), 22, 600, UITheme.DIM)
		hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_event_panel.add_child(hint)
		# list
		var scroll := ScrollContainer.new()
		scroll.custom_minimum_size = Vector2(0, 360)
		scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
		_event_panel.add_child(scroll)
		var list := VBoxContainer.new()
		list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		scroll.add_child(list)
		for ev in Game.world.data.events:
			var nm: String = ev.name_ar if Game.settings.lang == "ar" else ev.name_en
			var evd: Dictionary = ev
			_btn(list, nm, func(): _select_event(evd), 20, 300)
	else:
		var nm: String = e.name_ar if Game.settings.lang == "ar" else e.name_en
		_event_panel.add_child(UITheme.label(nm, 32, 800, UITheme.ACCENT))
		var kind := Game.t(e.kind)
		var info := kind
		if e.has("route"):
			info += "  •  %s %.1f km" % [Game.t("length"), float(e.length) * float(e.get("laps", 1)) / 1000.0]
			if int(e.get("laps", 1)) > 1:
				info += "  •  %d %s" % [int(e.laps), Game.t("laps")]
			info += "\n" + (Game.t("police_on") if e.get("police", true) else Game.t("police_off"))
			info += "  •  %s: 7" % Game.t("opponents")
		_event_panel.add_child(UITheme.label(info, 20, 600, UITheme.DIM))
		var d := UITheme.label(e.desc_ar if Game.settings.lang == "ar" else e.desc_en, 22, 600)
		d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		d.custom_minimum_size = Vector2(300, 0)
		_event_panel.add_child(d)
		var best: float = Game.best_times.get(e.id, -1.0)
		if best > 0.0:
			var bt := Game.format_time(best) if e.has("route") else str(int(best))
			_event_panel.add_child(UITheme.label("%s: %s" % [Game.t("best"), bt], 22, 700, Color(0.5, 1.0, 0.6)))
		var sp := Control.new()
		sp.size_flags_vertical = Control.SIZE_EXPAND_FILL
		_event_panel.add_child(sp)
		_btn(_event_panel, Game.t("start"), func(): start_event.emit(e), 26, 320)
		_btn(_event_panel, Game.t("travel"), func(): travel_event.emit(e), 22, 320)
	_btn(_event_panel, Game.t("back"), func():
		if _sel_event.is_empty():
			if Game.main.in_game:
				show_pause()
			else:
				show_main()
		else:
			_select_event({}), 22, 320)


# --------------------------------------------------------------------------- settings
func _option(parent: Control, label: String, items: Array, value: int, cb: Callable) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	parent.add_child(row)
	var l := UITheme.label(label, 22, 600)
	l.custom_minimum_size = Vector2(300, 0)
	row.add_child(l)
	var ob := OptionButton.new()
	ob.custom_minimum_size = Vector2(260, 50)
	ob.focus_mode = Control.FOCUS_NONE
	for it in items:
		ob.add_item(it)
	ob.selected = value
	ob.item_selected.connect(func(i):
		_click()
		cb.call(i))
	row.add_child(ob)


func _slider(parent: Control, label: String, minv: float, maxv: float, value: float, cb: Callable, step := 0.05) -> HSlider:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	parent.add_child(row)
	var l := UITheme.label(label, 22, 600)
	l.custom_minimum_size = Vector2(300, 0)
	row.add_child(l)
	var s := HSlider.new()
	s.min_value = minv
	s.max_value = maxv
	s.step = step
	s.value = value
	s.custom_minimum_size = Vector2(260, 40)
	s.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	s.value_changed.connect(cb)
	row.add_child(s)
	return s


func _toggle(parent: Control, label: String, value: bool, cb: Callable) -> void:
	var row := HBoxContainer.new()
	parent.add_child(row)
	var l := UITheme.label(label, 22, 600)
	l.custom_minimum_size = Vector2(300, 0)
	row.add_child(l)
	var c := CheckButton.new()
	c.button_pressed = value
	c.focus_mode = Control.FOCUS_NONE
	c.toggled.connect(func(v):
		_click()
		cb.call(v))
	row.add_child(c)


func _scroll_panel(s: Control, title: String) -> VBoxContainer:
	var vp := s.get_viewport_rect().size
	var psize := Vector2(minf(720, vp.x - 40), vp.y - 50)
	var panel := PanelContainer.new()
	panel.position = (vp - psize) * 0.5
	panel.size = psize
	panel.custom_minimum_size = psize
	s.add_child(panel)
	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 10)
	panel.add_child(outer)
	outer.add_child(UITheme.label(title, 34, 800, UITheme.ACCENT))
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.custom_minimum_size = Vector2(psize.x - 50, psize.y - 110)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	outer.add_child(scroll)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(box)
	return box


func show_settings(back_to: String) -> void:
	var s := _new_screen("settings", 0.6)
	var box := _scroll_panel(s, Game.t("settings"))
	var st: Dictionary = Game.settings
	var reload := [false]
	_option(box, Game.t("language"), ["العربية", "English"], 0 if st.lang == "ar" else 1, func(i):
		Game.set_setting("lang", "ar" if i == 0 else "en")
		show_settings(back_to))
	_option(box, Game.t("quality"), [Game.t("q_low"), Game.t("q_med"), Game.t("q_high"), Game.t("q_ultra")], int(st.quality), func(i):
		Game.set_setting("quality", i)
		reload[0] = true)
	_slider(box, Game.t("render_scale"), 0.5, 1.0, float(st.render_scale), func(v):
		Game.set_setting("render_scale", v)
		get_viewport().scaling_3d_scale = v)
	_slider(box, Game.t("view_distance"), 0.0, 1.0, float(st.view_distance), func(v):
		Game.settings.view_distance = v
		reload[0] = true)
	_option(box, Game.t("time_of_day"), [Game.t("tod_morning"), Game.t("tod_golden"), Game.t("tod_noon"), Game.t("tod_sunset")], int(st.time_of_day), func(i):
		Game.set_setting("time_of_day", i)
		reload[0] = true)
	_slider(box, Game.t("traffic"), 0.0, 1.0, float(st.traffic_density), func(v):
		Game.set_setting("traffic_density", v)
		if Game.main and Game.main.traffic:
			Game.main.traffic.apply_density())
	_toggle(box, Game.t("police"), st.police, func(v): Game.set_setting("police", v))
	_option(box, Game.t("difficulty"), [Game.t("easy"), Game.t("normal"), Game.t("hard")], int(st.difficulty), func(i): Game.set_setting("difficulty", i))
	_slider(box, Game.t("steer_assist"), 0.0, 1.0, float(st.steer_assist), func(v): Game.set_setting("steer_assist", v))
	_toggle(box, Game.t("tcs"), st.traction_control, func(v): Game.set_setting("traction_control", v))
	_toggle(box, Game.t("abs"), st.abs, func(v): Game.set_setting("abs", v))
	_toggle(box, Game.t("stability"), st.stability, func(v): Game.set_setting("stability", v))
	_toggle(box, Game.t("slowmo"), st.slowmo_jumps, func(v): Game.set_setting("slowmo_jumps", v))
	_option(box, Game.t("units"), ["km/h", "mph"], 0 if st.units == "kmh" else 1, func(i): Game.set_setting("units", "kmh" if i == 0 else "mph"))
	_slider(box, Game.t("volume"), 0.0, 1.0, float(st.vol_master), func(v): Game.set_setting("vol_master", v))
	_toggle(box, Game.t("vibration"), st.vibration, func(v): Game.set_setting("vibration", v))
	_toggle(box, Game.t("show_fps"), st.show_fps, func(v): Game.set_setting("show_fps", v))
	_btn(box, Game.t("back"), func():
		Game.save_game()
		settings_applied.emit(reload[0])
		if back_to == "pause":
			show_pause()
		else:
			show_main(), 24, 300)


# --------------------------------------------------------------------------- controls
func show_controls(back_to: String) -> void:
	var s := _new_screen("controls", 0.6)
	var box := _scroll_panel(s, Game.t("controls"))
	var c: Dictionary = Game.controls
	var modes := ["buttons", "wheel", "slider", "tilt"]
	_option(box, Game.t("steer_mode"), [Game.t("sm_buttons"), Game.t("sm_wheel"), Game.t("sm_slider"), Game.t("sm_tilt")], maxi(modes.find(c.steer_mode), 0), func(i):
		Game.controls.steer_mode = modes[i]
		Game.save_game())
	_toggle(box, Game.t("auto_accel"), c.auto_accel, func(v):
		Game.controls.auto_accel = v
		Game.save_game())
	_slider(box, Game.t("sensitivity"), 0.4, 1.8, float(c.sensitivity), func(v): Game.controls.sensitivity = v)
	_slider(box, Game.t("tilt_sens"), 0.4, 2.0, float(c.tilt_sensitivity), func(v): Game.controls.tilt_sensitivity = v)
	_slider(box, Game.t("opacity"), 0.15, 1.0, float(c.opacity), func(v): Game.controls.opacity = v)
	_slider(box, Game.t("btn_scale"), 0.6, 1.6, float(c.scale), func(v): Game.controls.scale = v)
	_btn(box, Game.t("edit_layout"), func(): open_layout_editor(back_to), 24, 360)
	_btn(box, Game.t("reset_layout"), func():
		Game.controls.layout = {}
		Game.save_game(), 22, 360)
	_btn(box, Game.t("back"), func():
		Game.save_game()
		if back_to == "pause":
			show_pause()
		else:
			show_main(), 24, 300)


func open_layout_editor(back_to: String) -> void:
	clear()
	_rtl()
	touch.editing = true
	touch.visible = true
	touch.selected = ""
	layout_editing.emit(true)
	edit_panel = PanelContainer.new()
	edit_panel.custom_minimum_size = Vector2(560, 0)
	edit_panel.position = Vector2(root.get_viewport_rect().size.x * 0.5 - 280, 60)
	root.add_child(edit_panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	edit_panel.add_child(box)
	var hint := UITheme.label(Game.t("layout_hint"), 20, 600, UITheme.DIM)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.custom_minimum_size = Vector2(500, 0)
	box.add_child(hint)
	size_slider = _slider(box, Game.t("selected_size"), 0.5, 2.0, 1.0, func(v):
		if touch.selected != "":
			var l: Array = Game.layout_of(touch.selected).duplicate()
			l[2] = v
			Game.controls.layout[touch.selected] = l
			touch.queue_redraw())
	touch.selected_changed.connect(func(n):
		size_slider.set_value_no_signal(float(Game.layout_of(n)[2])))
	_slider(box, Game.t("opacity"), 0.15, 1.0, float(Game.controls.opacity), func(v): Game.controls.opacity = v)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 12)
	box.add_child(row)
	_btn(row, Game.t("reset_layout"), func():
		Game.controls.layout = {}
		touch.queue_redraw(), 20, 220)
	_btn(row, Game.t("done"), func():
		touch.editing = false
		touch.release_all()
		Game.save_game()
		layout_editing.emit(false)
		show_controls(back_to), 22, 220)


# --------------------------------------------------------------------------- pause / results
func show_pause() -> void:
	var s := _new_screen("pause", 0.6)
	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_CENTER)
	box.position = Vector2(-180, -250)
	box.add_theme_constant_override("separation", 12)
	s.add_child(box)
	var t := UITheme.label(Game.t("title"), 46, 800, UITheme.ACCENT)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(t)
	_btn(box, Game.t("resume"), func(): resume.emit(), 26, 360)
	if Game.race and (Game.race.state != RaceManager.IDLE or Game.race.challenge != ""):
		_btn(box, Game.t("restart"), func(): restart.emit(), 24, 360)
		_btn(box, Game.t("quit_race"), func(): quit_race.emit(), 24, 360)
	_btn(box, Game.t("events"), show_events, 24, 360)
	_btn(box, Game.t("settings"), func(): show_settings("pause"), 24, 360)
	_btn(box, Game.t("controls"), func(): show_controls("pause"), 24, 360)
	_btn(box, Game.t("main_menu"), func(): to_main_menu.emit(), 24, 360)


func show_results(list: Array, busted: bool) -> void:
	var s := _new_screen("results", 0.65)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(640, 0)
	panel.position = Vector2(s.get_viewport_rect().size.x * 0.5 - 320, 40)
	s.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	panel.add_child(box)
	var title := UITheme.label(Game.t("busted") if busted else Game.t("results"), 40, 800, Color(1, 0.3, 0.3) if busted else UITheme.ACCENT)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)
	for i in list.size():
		var r: Dictionary = list[i]
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 12)
		box.add_child(row)
		var col := Color(1, 0.85, 0.3) if r.player else UITheme.TEXT
		var a := UITheme.label("%d" % (i + 1), 24, 800, col)
		a.custom_minimum_size = Vector2(40, 0)
		row.add_child(a)
		var n := UITheme.label(r.name, 24, 700, col)
		n.custom_minimum_size = Vector2(170, 0)
		row.add_child(n)
		var c := UITheme.label(r.car, 20, 600, UITheme.DIM)
		c.custom_minimum_size = Vector2(200, 0)
		row.add_child(c)
		row.add_child(UITheme.label(Game.t("dnf") if r.dnf else Game.format_time(r.time), 22, 700, col))
	var btns := HBoxContainer.new()
	btns.alignment = BoxContainer.ALIGNMENT_CENTER
	btns.add_theme_constant_override("separation", 12)
	box.add_child(btns)
	_btn(btns, Game.t("restart"), func(): restart.emit(), 22, 200)
	_btn(btns, Game.t("continue"), func(): quit_race.emit(), 22, 200)
