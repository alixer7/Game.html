class_name Hud
extends CanvasLayer
## In-game overlay: counters, hints, toasts, boss bar, level title, pause menu and result screen.

signal resume_pressed
signal restart_pressed
signal menu_pressed
signal next_pressed

var _root: Control
var _stats: Stats
var _timer_label: Label
var _fps_label: Label
var _hint_panel: Panel
var _hint_label: Label
var _hint_ttl: float = 0.0
var _hint_text: String = ""
var _toast_panel: Panel
var _toast_label: Label
var _toast_tw: Tween
var _boss_bar: BossBar
var _battery: BatteryGauge
var _reserve_label: Label
var _vig_mat: ShaderMaterial
var _flash_amt: float = 0.0
var _flash_col: Color = Color(1.0, 0.1, 0.1)
var _fade: ColorRect
var _title_box: Control
var _pause_layer: Control
var _pause_menu: Control
var _settings: SettingsPanel
var _result_layer: Control
var _hp: int = 3
var _max_hp: int = 3
var _t: float = 0.0
var _last_time_text: String = ""


func _ready() -> void:
	layer = 10
	process_mode = Node.PROCESS_MODE_ALWAYS
	_root = Control.new()
	UIKit.fill(_root)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.layout_direction = Control.LAYOUT_DIRECTION_LTR
	add_child(_root)
	_build_vignette()
	_build_stats()
	_build_toasts()
	_build_boss()
	_fade = ColorRect.new()
	UIKit.fill(_fade)
	_fade.color = Color(0.0, 0.0, 0.0, 0.0)
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_fade)


# ------------------------------------------------------------- building
func _build_vignette() -> void:
	var v := ColorRect.new()
	UIKit.fill(v)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_vig_mat = ShaderMaterial.new()
	_vig_mat.shader = Mats.shader("res://shaders/vignette.gdshader")
	v.material = _vig_mat
	_root.add_child(v)


func _build_stats() -> void:
	var mar: Vector4 = UIKit.safe_margins(get_viewport())
	_stats = Stats.new()
	UIKit.place(_stats, Vector2.ZERO, Vector2(28.0 + mar.x, 22.0 + mar.y), Vector2(400.0, 196.0))
	_root.add_child(_stats)
	_timer_label = UIKit.label_ltr("0:00.0", 40, UIKit.COL_TEXT, HORIZONTAL_ALIGNMENT_CENTER, 8)
	UIKit.place(_timer_label, Vector2(0.5, 0.0), Vector2(-150.0, 18.0 + mar.y), Vector2(300.0, 56.0))
	_root.add_child(_timer_label)
	_fps_label = UIKit.label_ltr("", 26, UIKit.COL_DIM, HORIZONTAL_ALIGNMENT_RIGHT, 5)
	UIKit.place(_fps_label, Vector2(1.0, 0.0), Vector2(-260.0 - mar.z, 140.0 + mar.y), Vector2(200.0, 36.0))
	_root.add_child(_fps_label)
	_battery = BatteryGauge.new()
	UIKit.place(_battery, Vector2.ZERO, Vector2(28.0 + mar.x + 416.0, 22.0 + mar.y), Vector2(360.0, 96.0))
	_root.add_child(_battery)
	_reserve_label = UIKit.label("", 52, Color(1.0, 0.4, 0.35), HORIZONTAL_ALIGNMENT_CENTER, 10)
	UIKit.place(_reserve_label, Vector2(0.5, 0.0), Vector2(-500.0, 250.0), Vector2(1000.0, 80.0))
	_reserve_label.modulate.a = 0.0
	_root.add_child(_reserve_label)


func _build_toasts() -> void:
	var cy: Color = UIKit.COL_CYAN
	_hint_panel = UIKit.panel(Color(0.03, 0.06, 0.16, 0.82), Color(cy.r, cy.g, cy.b, 0.7), 30, 2, 12)
	UIKit.place(_hint_panel, Vector2(0.5, 1.0), Vector2(-420.0, -300.0), Vector2(840.0, 120.0))
	_hint_panel.modulate.a = 0.0
	_root.add_child(_hint_panel)
	_hint_label = UIKit.wrap_label("", 36, UIKit.COL_TEXT, 700.0)
	UIKit.fill(_hint_label)
	_hint_label.offset_left = 30.0
	_hint_label.offset_right = -30.0
	_hint_panel.add_child(_hint_label)

	_toast_panel = UIKit.panel(Color(0.03, 0.06, 0.16, 0.88), Color(1, 1, 1, 0.5), 28, 2, 10)
	UIKit.place(_toast_panel, Vector2(0.5, 0.0), Vector2(-330.0, 92.0), Vector2(660.0, 84.0))
	_toast_panel.modulate.a = 0.0
	_root.add_child(_toast_panel)
	_toast_label = UIKit.label("", 38, UIKit.COL_TEXT, HORIZONTAL_ALIGNMENT_CENTER, 4)
	UIKit.fill(_toast_label)
	_toast_panel.add_child(_toast_label)


func _build_boss() -> void:
	_boss_bar = BossBar.new()
	UIKit.place(_boss_bar, Vector2(0.5, 0.0), Vector2(-380.0, 186.0), Vector2(760.0, 76.0))
	_boss_bar.visible = false
	_root.add_child(_boss_bar)


# ------------------------------------------------------------------ API
func set_coins(n: int, total: int) -> void:
	if n != _stats.coins:
		_stats.pop = 1.0
	_stats.coins = n
	_stats.coin_total = total
	_stats.queue_redraw()


func set_bots(b: Array) -> void:
	for i in range(3):
		var v: bool = false
		if i < b.size():
			v = bool(b[i])
		if v and not bool(_stats.bots[i]):
			_stats.bot_pop[i] = 1.0
		_stats.bots[i] = v
	_stats.queue_redraw()


func set_hp(n: int, mx: int = 3) -> void:
	if n < _hp:
		flash(Color(1.0, 0.15, 0.2), 0.55)
	_hp = n
	_max_hp = mx
	_stats.hp = n
	_stats.max_hp = mx
	_stats.queue_redraw()


func set_battery(v: float, mx: float = 100.0) -> void:
	var r: float = clampf(v / maxf(mx, 0.001), 0.0, 1.0)
	if r > _battery.ratio + 0.05:
		_battery.charge_fx = 1.0
	_battery.ratio = r


func set_reserve(active: bool, left: float) -> void:
	_battery.reserve = active
	if active:
		_reserve_label.text = "طاقة احتياطية: %d" % int(ceil(left))
		_reserve_label.modulate.a = 0.75 + 0.25 * sin(_t * 10.0)
	else:
		_reserve_label.modulate.a = 0.0


func set_time(t: float) -> void:
	var s: String = Game.format_time(t)
	if s != _last_time_text:
		_last_time_text = s
		_timer_label.text = s


func show_hint(txt: String) -> void:
	_hint_ttl = 0.25
	if txt != _hint_text:
		_hint_text = txt
		_hint_label.text = txt


func toast(txt: String, col: Color = Color(0.25, 0.9, 1.0)) -> void:
	_toast_label.text = txt
	_toast_label.add_theme_color_override("font_color", col.lightened(0.4))
	_toast_panel.add_theme_stylebox_override("panel", UIKit.panel_style(Color(0.03, 0.06, 0.16, 0.9), Color(col.r, col.g, col.b, 0.85), 28, 3, 14, Color(col.r, col.g, col.b, 0.35)))
	if _toast_tw != null and _toast_tw.is_valid():
		_toast_tw.kill()
	_toast_panel.pivot_offset = Vector2(330.0, 42.0)
	_toast_panel.scale = Vector2(0.85, 0.85)
	_toast_panel.modulate.a = 0.0
	var pop := create_tween()
	pop.tween_property(_toast_panel, "scale", Vector2.ONE, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_toast_tw = create_tween()
	_toast_tw.tween_property(_toast_panel, "modulate:a", 1.0, 0.16)
	_toast_tw.tween_interval(1.9)
	_toast_tw.tween_property(_toast_panel, "modulate:a", 0.0, 0.4)


func flash(col: Color, amount: float = 0.5) -> void:
	_flash_col = col
	_flash_amt = maxf(_flash_amt, amount)


func set_boss(ratio: float, vis: bool) -> void:
	_boss_bar.visible = vis
	_boss_bar.ratio = clampf(ratio, 0.0, 1.0)


func fade(to: float, dur: float = 0.35) -> void:
	var tw := create_tween()
	tw.tween_property(_fade, "color:a", to, dur)


func show_title(title: String, sub: String = "") -> void:
	if _title_box != null and is_instance_valid(_title_box):
		_title_box.queue_free()
	var box := Control.new()
	UIKit.fill(box)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(box)
	_title_box = box
	var t1 := UIKit.label(title, 96, UIKit.COL_TEXT, HORIZONTAL_ALIGNMENT_CENTER, 12)
	UIKit.place(t1, Vector2(0.5, 0.34), Vector2(-700.0, -70.0), Vector2(1400.0, 140.0))
	box.add_child(t1)
	if sub != "":
		var t2 := UIKit.label(sub, 42, UIKit.COL_CYAN, HORIZONTAL_ALIGNMENT_CENTER, 6)
		UIKit.place(t2, Vector2(0.5, 0.34), Vector2(-600.0, 74.0), Vector2(1200.0, 64.0))
		box.add_child(t2)
	box.modulate.a = 0.0
	var tw := box.create_tween()
	tw.tween_property(box, "modulate:a", 1.0, 0.5)
	tw.tween_interval(1.7)
	tw.tween_property(box, "modulate:a", 0.0, 0.6)
	tw.tween_callback(box.queue_free)


# ------------------------------------------------------------ per frame
func _process(delta: float) -> void:
	_t += delta
	_flash_amt = move_toward(_flash_amt, 0.0, delta * 1.5)
	var amt: float = _flash_amt
	var col: Color = _flash_col
	if _hp == 1 and _max_hp > 1:
		var pulse: float = 0.1 + 0.07 * sin(_t * 6.0)
		if pulse > amt:
			amt = pulse
			col = Color(1.0, 0.1, 0.15)
	_vig_mat.set_shader_parameter("flash_color", col)
	_vig_mat.set_shader_parameter("flash", amt)
	_hint_ttl -= delta
	var target: float = 1.0 if _hint_ttl > 0.0 else 0.0
	_hint_panel.modulate.a = move_toward(_hint_panel.modulate.a, target, delta * 5.0)
	if bool(Game.settings.get("show_fps", false)):
		_fps_label.text = "%d FPS" % int(Engine.get_frames_per_second())
	elif _fps_label.text != "":
		_fps_label.text = ""


# ------------------------------------------------------------ pause menu
func show_pause() -> void:
	if _pause_layer != null:
		return
	_pause_layer = Control.new()
	UIKit.fill(_pause_layer)
	_pause_layer.layout_direction = Control.LAYOUT_DIRECTION_LTR
	_root.add_child(_pause_layer)
	var dim := ColorRect.new()
	UIKit.fill(dim)
	dim.color = Color(0.01, 0.02, 0.06, 0.66)
	_pause_layer.add_child(dim)
	UIKit.fade_in(dim, 0.0, 0.2)
	_pause_menu = _build_pause_menu()
	_pause_layer.add_child(_pause_menu)
	UIKit.pop_in(_pause_menu)
	Sfx.play("ui_confirm")


func hide_pause() -> void:
	if _pause_layer != null:
		_pause_layer.queue_free()
		_pause_layer = null
		_pause_menu = null
		_settings = null


func is_pause_open() -> bool:
	return _pause_layer != null


func close_settings_if_open() -> bool:
	if _settings != null:
		_close_settings()
		return true
	return false


func _build_pause_menu() -> Control:
	var cy: Color = UIKit.COL_CYAN
	var p := UIKit.panel(UIKit.COL_PANEL, Color(cy.r, cy.g, cy.b, 0.6), 40, 3, 30)
	UIKit.place(p, Vector2(0.5, 0.5), Vector2(-330.0, -330.0), Vector2(660.0, 660.0))
	var title := UIKit.label("إيقاف مؤقت", 58, UIKit.COL_TEXT, HORIZONTAL_ALIGNMENT_CENTER, 6)
	UIKit.place(title, Vector2.ZERO, Vector2(0.0, 30.0), Vector2(660.0, 80.0))
	p.add_child(title)
	var items: Array = [
		["متابعة", UIKit.COL_CYAN, true, "play", "resume"],
		["إعادة المحاولة", UIKit.COL_GOLD, false, "restart", "restart"],
		["الإعدادات", UIKit.COL_VIOLET, false, "gear", "settings"],
		["القائمة الرئيسية", UIKit.COL_PINK, false, "home", "menu"],
	]
	for i in range(items.size()):
		var it: Array = items[i]
		var b := NeonButton.make(str(it[0]), it[1], bool(it[2]), Vector2(520, 96), 38, str(it[3]))
		UIKit.place(b, Vector2.ZERO, Vector2(70.0, 140.0 + i * 120.0), Vector2(520.0, 96.0))
		b.pressed.connect(_on_pause_item.bind(str(it[4])))
		p.add_child(b)
	return p


func _on_pause_item(which: String) -> void:
	if which == "resume":
		resume_pressed.emit()
	elif which == "restart":
		restart_pressed.emit()
	elif which == "menu":
		menu_pressed.emit()
	elif which == "settings":
		_open_settings()


func _open_settings() -> void:
	if _pause_layer == null or _settings != null:
		return
	_pause_menu.visible = false
	_settings = SettingsPanel.new()
	UIKit.place(_settings, Vector2(0.5, 0.5), Vector2(-780.0, -400.0), Vector2(1560.0, 800.0))
	_settings.closed.connect(_close_settings)
	_pause_layer.add_child(_settings)
	UIKit.pop_in(_settings)


func _close_settings() -> void:
	if _settings != null:
		_settings.queue_free()
		_settings = null
	if _pause_menu != null:
		_pause_menu.visible = true
		UIKit.pop_in(_pause_menu, 0.0, 0.3)


# ----------------------------------------------------------- result screen
## info: name, bots (Array of bool), coins, coin_total, time, record (bool), has_next (bool)
func show_result(info: Dictionary) -> void:
	if _result_layer != null:
		return
	hide_pause()
	_result_layer = Control.new()
	UIKit.fill(_result_layer)
	_result_layer.layout_direction = Control.LAYOUT_DIRECTION_LTR
	_root.add_child(_result_layer)
	var dim := ColorRect.new()
	UIKit.fill(dim)
	dim.color = Color(0.01, 0.02, 0.06, 0.7)
	_result_layer.add_child(dim)
	UIKit.fade_in(dim, 0.0, 0.4)

	var gold: Color = UIKit.COL_GOLD
	var p := UIKit.panel(UIKit.COL_PANEL, Color(gold.r, gold.g, gold.b, 0.75), 44, 3, 36)
	UIKit.place(p, Vector2(0.5, 0.5), Vector2(-460.0, -370.0), Vector2(920.0, 740.0))
	_result_layer.add_child(p)
	var title := UIKit.label("اكتملت المرحلة!", 70, gold, HORIZONTAL_ALIGNMENT_CENTER, 8)
	UIKit.place(title, Vector2.ZERO, Vector2(0.0, 28.0), Vector2(920.0, 90.0))
	p.add_child(title)
	var nm := UIKit.label(str(info.get("name", "")), 36, UIKit.COL_DIM, HORIZONTAL_ALIGNMENT_CENTER)
	UIKit.place(nm, Vector2.ZERO, Vector2(0.0, 118.0), Vector2(920.0, 50.0))
	p.add_child(nm)

	var row := BotRow.new()
	row.bots = info.get("bots", [false, false, false])
	UIKit.place(row, Vector2.ZERO, Vector2(0.0, 178.0), Vector2(920.0, 110.0))
	p.add_child(row)

	_result_row(p, 310.0, "الجواهر", "%d / %d" % [int(info.get("coins", 0)), int(info.get("coin_total", 0))], UIKit.COL_GOLD)
	_result_row(p, 388.0, "الوقت", Game.format_time(float(info.get("time", 0.0))), UIKit.COL_CYAN)
	if bool(info.get("record", false)):
		var rec := UIKit.label("رقم قياسي جديد!", 40, UIKit.COL_GREEN, HORIZONTAL_ALIGNMENT_CENTER, 5)
		UIKit.place(rec, Vector2.ZERO, Vector2(0.0, 466.0), Vector2(920.0, 56.0))
		p.add_child(rec)
		UIKit.pop_in(rec, 0.9)

	var has_next: bool = bool(info.get("has_next", false))
	var defs: Array = []
	if has_next:
		defs.append(["المرحلة التالية", UIKit.COL_CYAN, true, "arrow_right", "next", 330.0])
	defs.append(["إعادة", UIKit.COL_GOLD, false, "restart", "restart", 240.0])
	defs.append(["القائمة", UIKit.COL_PINK, false, "home", "menu", 240.0])
	var total_w: float = 0.0
	for d in defs:
		var dd: Array = d
		total_w += float(dd[5])
	total_w += 20.0 * (defs.size() - 1)
	var x: float = (920.0 - total_w) * 0.5
	for d in defs:
		var dd: Array = d
		var w: float = float(dd[5])
		var b := NeonButton.make(str(dd[0]), dd[1], bool(dd[2]), Vector2(w, 92), 32, str(dd[3]))
		UIKit.place(b, Vector2.ZERO, Vector2(x, 596.0), Vector2(w, 92.0))
		b.pressed.connect(_on_result_item.bind(str(dd[4])))
		p.add_child(b)
		UIKit.pop_in(b, 0.5)
		x += w + 20.0
	UIKit.pop_in(p)


func _result_row(parent: Control, y: float, label: String, value: String, col: Color) -> void:
	var l := UIKit.label(label, 42, UIKit.COL_TEXT, HORIZONTAL_ALIGNMENT_RIGHT)
	UIKit.place(l, Vector2.ZERO, Vector2(480.0, y), Vector2(380.0, 64.0))
	parent.add_child(l)
	var v := UIKit.label_ltr(value, 46, col, HORIZONTAL_ALIGNMENT_LEFT, 4)
	UIKit.place(v, Vector2.ZERO, Vector2(60.0, y), Vector2(380.0, 64.0))
	parent.add_child(v)


func _on_result_item(which: String) -> void:
	if which == "next":
		next_pressed.emit()
	elif which == "restart":
		restart_pressed.emit()
	else:
		menu_pressed.emit()


# ----------------------------------------------------------- inner classes
class Stats extends Control:
	var coins: int = 0
	var coin_total: int = 0
	var bots: Array = [false, false, false]
	var bot_pop: Array = [0.0, 0.0, 0.0]
	var hp: int = 3
	var max_hp: int = 3
	var pop: float = 0.0
	var _box: StyleBoxFlat

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		size = Vector2(400.0, 196.0)
		_box = UIKit.panel_style(Color(0.03, 0.06, 0.16, 0.62), Color(0.3, 0.9, 1.0, 0.45), 28, 2, 10)

	func _process(delta: float) -> void:
		var any: bool = false
		if pop > 0.0:
			pop = maxf(pop - delta * 4.0, 0.0)
			any = true
		for i in range(bot_pop.size()):
			var bp: float = float(bot_pop[i])
			if bp > 0.0:
				bot_pop[i] = maxf(bp - delta * 2.0, 0.0)
				any = true
		if any:
			queue_redraw()

	func _draw() -> void:
		var f: Font = UIKit.font()
		draw_style_box(_box, Rect2(Vector2.ZERO, size))
		var gold: Color = UIKit.COL_GOLD
		draw_circle(Vector2(54.0, 56.0), 30.0, Color(gold.r, gold.g, gold.b, 0.16))
		UIIcons.draw(self, "gem", Vector2(54.0, 56.0), 24.0, gold)
		var fs: int = 52 + int(pop * 16.0)
		var txt: String = str(coins)
		var base := Vector2(100.0, 56.0 + fs * 0.34)
		draw_string_outline(f, base, txt, HORIZONTAL_ALIGNMENT_LEFT, -1.0, fs, 8, Color(0.02, 0.04, 0.12, 0.9))
		draw_string(f, base, txt, HORIZONTAL_ALIGNMENT_LEFT, -1.0, fs, Color(1, 1, 1))
		var w: float = f.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1.0, fs).x
		if coin_total > 0:
			draw_string(f, Vector2(100.0 + w + 12.0, 66.0), "/ " + str(coin_total), HORIZONTAL_ALIGNMENT_LEFT, -1.0, 28, UIKit.COL_DIM)
		for i in range(3):
			var c := Vector2(54.0 + i * 84.0, 118.0)
			if bool(bots[i]):
				var k: float = 1.0 + float(bot_pop[i]) * 0.55
				draw_circle(c, 32.0 * k, Color(0.3, 0.95, 1.0, 0.18))
				UIIcons.draw(self, "bot", c, 26.0 * k, UIKit.COL_CYAN)
			else:
				UIIcons.draw(self, "bot", c, 26.0, Color(0.35, 0.42, 0.55, 0.55))
		for i in range(max_hp):
			var c2 := Vector2(54.0 + i * 62.0, 168.0)
			if i < hp:
				draw_circle(c2, 22.0, Color(0.3, 1.0, 0.6, 0.2))
				UIIcons.draw(self, "hex", c2, 17.0, UIKit.COL_GREEN)
			else:
				UIIcons.draw(self, "hex", c2, 17.0, Color(0.25, 0.3, 0.42, 0.7))


## Battery gauge: cell outline with 10 segments, percentage and a bolt icon. Blinks red when low.
class BatteryGauge extends Control:
	var ratio: float = 1.0
	var shown: float = 1.0
	var reserve: bool = false
	var charge_fx: float = 0.0
	var _t: float = 0.0
	var _box: StyleBoxFlat

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		_box = UIKit.panel_style(Color(0.03, 0.06, 0.16, 0.62), Color(0.35, 1.0, 0.6, 0.45), 26, 2, 10)

	func _process(delta: float) -> void:
		_t += delta
		shown = move_toward(shown, ratio, delta * (0.8 if ratio > shown else 2.5))
		charge_fx = maxf(charge_fx - delta * 0.8, 0.0)
		queue_redraw()

	func _col() -> Color:
		if reserve or shown < 0.2:
			return Color(1.0, 0.3, 0.25)
		if shown < 0.45:
			return Color(1.0, 0.8, 0.25)
		return Color(0.35, 1.0, 0.6)

	func _draw() -> void:
		var col: Color = _col()
		var blink: bool = (reserve or shown < 0.2) and int(_t * 4.0) % 2 == 0
		_box.border_color = Color(col.r, col.g, col.b, 0.75 if blink else 0.45)
		draw_style_box(_box, Rect2(Vector2.ZERO, size))
		UIIcons.draw(self, "bolt", Vector2(44.0, size.y * 0.5), 24.0, col if not blink else col.darkened(0.5))
		var bx := Rect2(Vector2(82.0, 24.0), Vector2(190.0, size.y - 48.0))
		draw_rect(bx, Color(0.0, 0.0, 0.0, 0.35))
		draw_rect(bx, Color(col.r, col.g, col.b, 0.85), false, 3.0)
		draw_rect(Rect2(bx.position + Vector2(bx.size.x, bx.size.y * 0.3), Vector2(8.0, bx.size.y * 0.4)), Color(col.r, col.g, col.b, 0.85))
		var segs: int = 10
		var gap: float = 3.0
		var sw: float = (bx.size.x - 8.0 - gap * float(segs - 1)) / float(segs)
		for i in range(segs):
			var f: float = clampf(shown * float(segs) - float(i), 0.0, 1.0)
			if f <= 0.0:
				continue
			var r := Rect2(bx.position + Vector2(4.0 + float(i) * (sw + gap), 4.0), Vector2(sw * f, bx.size.y - 8.0))
			var c: Color = col
			if charge_fx > 0.0:
				var w: float = fposmod(_t * 3.0, 1.4) * float(segs)
				c = c.lerp(Color(1, 1, 1), clampf(1.0 - absf(float(i) - w) * 0.5, 0.0, 1.0) * charge_fx)
			draw_rect(r, c)
		var txt: String = str(int(round(shown * 100.0))) + "%"
		var f2: Font = UIKit.font()
		draw_string_outline(f2, Vector2(288.0, size.y * 0.5 + 13.0), txt, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 36, 6, Color(0.02, 0.04, 0.12, 0.9))
		draw_string(f2, Vector2(288.0, size.y * 0.5 + 13.0), txt, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 36, col.lightened(0.3))


class BossBar extends Control:
	var ratio: float = 1.0
	var shown_ratio: float = 1.0
	var _back: StyleBoxFlat
	var _fill: StyleBoxFlat

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		_back = UIKit.panel_style(Color(0.05, 0.07, 0.17, 0.85), Color(1.0, 0.45, 0.65, 0.8), 17, 2, 8)
		_fill = UIKit.panel_style(Color(1.0, 0.32, 0.5), Color(0, 0, 0, 0), 11, 0, 8, Color(1.0, 0.3, 0.5, 0.5))

	func _process(delta: float) -> void:
		shown_ratio = move_toward(shown_ratio, ratio, delta * 0.9)
		if visible:
			queue_redraw()

	func _draw() -> void:
		var f: Font = UIKit.font()
		draw_string_outline(f, Vector2(0.0, 30.0), "حارس المجرة", HORIZONTAL_ALIGNMENT_CENTER, size.x, 32, 6, Color(0.02, 0.04, 0.12, 0.9))
		draw_string(f, Vector2(0.0, 30.0), "حارس المجرة", HORIZONTAL_ALIGNMENT_CENTER, size.x, 32, Color(1.0, 0.6, 0.75))
		draw_style_box(_back, Rect2(0.0, 40.0, size.x, 34.0))
		var w: float = (size.x - 12.0) * shown_ratio
		if w > 10.0:
			draw_style_box(_fill, Rect2(6.0, 46.0, w, 22.0))


class BotRow extends Control:
	var bots: Array = [false, false, false]
	var t: float = 0.0
	var played: Array = [false, false, false]

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _process(delta: float) -> void:
		t += delta
		for i in range(3):
			if i < bots.size() and bool(bots[i]) and not bool(played[i]) and t > 0.5 + i * 0.4:
				played[i] = true
				Sfx.play("powerup", -3.0, 1.0 + i * 0.12)
				Game.vibrate(15)
		queue_redraw()

	func _draw() -> void:
		var gap: float = 150.0
		var x0: float = size.x * 0.5 - gap
		for i in range(3):
			var c := Vector2(x0 + gap * i, size.y * 0.5)
			var t0: float = 0.5 + i * 0.4
			var found: bool = i < bots.size() and bool(bots[i])
			var k: float = clampf((t - t0) * 4.0, 0.0, 1.0)
			draw_circle(c, 52.0, Color(0.05, 0.1, 0.22, 0.8))
			draw_arc(c, 52.0, 0.0, TAU, 40, Color(0.35, 0.45, 0.6, 0.7), 3.0, true)
			if found and k > 0.0:
				var s: float = 40.0 * (1.0 + 0.4 * sin(k * PI))
				draw_circle(c, 60.0 * k, Color(0.3, 0.95, 1.0, 0.2))
				UIIcons.draw(self, "bot", c, s, UIKit.COL_CYAN)
			else:
				UIIcons.draw(self, "bot", c, 36.0, Color(0.3, 0.36, 0.5, 0.5))
