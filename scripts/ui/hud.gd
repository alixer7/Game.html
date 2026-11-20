class_name HUD
extends CanvasLayer
## الواجهة الرئيسية أثناء اللعب: المؤشرات، الخريطة المصغرة، شريط الأدوات، أزرار اللمس، شريط البناء، الإشعارات، والنوافذ.

var world: Node
var player: Player
var root: Control
var touch: TouchControls
var btns := {}
var bars := {}
var lbl_clock: Label
var lbl_env: Label
var lbl_weight: Label
var lbl_prompt: Label
var prompt_bg: PanelContainer
var lbl_status: Label
var lbl_build: Label
var notif_box: VBoxContainer
var craft_bar: ProgressBar
var craft_lbl: Label
var hotbar: Array = []
var hot_icons: Array = []
var panels := {}
var dmg_flash: ColorRect
var underwater: ColorRect
var night_tint: ColorRect
var sleep_overlay: Control
var sleep_lbl: Label
var death_overlay: Control
var death_lbl: Label
var minimap: Control
var build_bar: PanelContainer
var build_list: HBoxContainer
var build_mats: Control
var build_cat := "structure"
var build_mat := "wood"
var fps_lbl: Label
var crosshair: Control
var _upd_t := 0.0
var _last_size := Vector2.ZERO
var _hot_dirty := true

func setup(w: Node) -> void:
	world = w
	player = w.player
	layer = 10
	root = Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = UIKit.theme()
	add_child(root)
	underwater = _overlay(Color(0.05, 0.22, 0.3, 0.5))
	night_tint = _overlay(Color(0.0, 0.02, 0.06, 0.0))
	dmg_flash = _overlay(Color(0.7, 0.0, 0.0, 0.0))
	touch = TouchControls.new()
	root.add_child(touch)
	touch.button_pressed.connect(_on_btn_down)
	touch.button_released.connect(_on_btn_up)
	_build_stats()
	_build_info()
	_build_center()
	_build_hotbar()
	_build_buttons()
	_build_buildbar()
	_build_notifs()
	_build_overlays()
	fps_lbl = UIKit.label("", 16, Color(1, 1, 0.6), HORIZONTAL_ALIGNMENT_LEFT)
	fps_lbl.position = Vector2(10, 4)
	root.add_child(fps_lbl)
	for pn in ["inventory", "crafting", "storage", "dialog", "trade", "map", "character", "pause"]:
		var sc = load("res://scripts/ui/%s_panel.gd" % pn)
		var p: Control = sc.new()
		p.hud = self
		root.add_child(p)
		p.build()
		panels[pn] = p
	Game.notified.connect(_on_notify)
	player.inventory.changed.connect(func(): _hot_dirty = true)
	_layout()

func _overlay(c: Color) -> ColorRect:
	var r := ColorRect.new()
	r.color = c
	r.set_anchors_preset(Control.PRESET_FULL_RECT)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	r.visible = c.a > 0.0 or true
	root.add_child(r)
	return r

func _btn(id: String, text: String, sz := Vector2(96, 96), is_round := true) -> TouchBtn:
	var b := TouchBtn.new(id, text, sz, is_round)
	root.add_child(b)
	touch.register(b)
	btns[id] = b
	return b

# ------------------------------------------------------------------
class StatBar extends Control:
	var title := ""
	var value := 100.0
	var col := Color.WHITE
	var warn := false
	var extra := ""
	func _draw() -> void:
		var font := get_theme_default_font()
		var w := size.x
		var h := size.y
		draw_style_box(UIKit.sb(Color(0, 0, 0, 0.45), 8, 0, Color(0, 0, 0, 0), 0), Rect2(0, h - 12, w, 12))
		var k := clampf(value / 100.0, 0.0, 1.0)
		var c := col
		if warn and int(Time.get_ticks_msec() / 300) % 2 == 0:
			c = c.lightened(0.4)
		draw_style_box(UIKit.sb(c, 8, 0, Color(0, 0, 0, 0), 0), Rect2(w * (1.0 - k), h - 12, w * k, 12))
		var t := "%s %s" % [title, extra if extra != "" else str(int(value))]
		var tw := font.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, 17).x
		draw_string_outline(font, Vector2(w - tw, h - 16), t, HORIZONTAL_ALIGNMENT_LEFT, -1, 17, 4, Color(0, 0, 0, 0.85))
		draw_string(font, Vector2(w - tw, h - 16), t, HORIZONTAL_ALIGNMENT_LEFT, -1, 17, Color(1, 1, 1, 0.95))

class MiniMap extends Control:
	var world: Node
	var span := 320.0
	func _draw() -> void:
		var r := Rect2(Vector2.ZERO, size)
		draw_style_box(UIKit.sb(Color(0, 0, 0, 0.5), 10, 2, Color(0.9, 0.75, 0.45, 0.5), 0), r)
		if world == null or world.player == null:
			return
		var p: Vector3 = world.player.global_position
		var inner := r.grow(-4)
		if world.map_texture != null:
			var px := 256.0 / (WorldGen.HALF * 2.0)
			var src := Rect2((p.x + WorldGen.HALF - span * 0.5) * px, (p.z + WorldGen.HALF - span * 0.5) * px, span * px, span * px)
			draw_texture_rect_region(world.map_texture, inner, src, Color(1, 1, 1, 0.9))
			var ex := float(World.EXPLORE_RES) / (WorldGen.HALF * 2.0)
			var src2 := Rect2((p.x + WorldGen.HALF - span * 0.5) * ex, (p.z + WorldGen.HALF - span * 0.5) * ex, span * ex, span * ex)
			draw_texture_rect_region(world.explored_tex, inner, src2, Color(0.05, 0.05, 0.07, 0.82))
		var to_px := inner.size.x / span
		var c := inner.get_center()
		for m in world.ai.markers:
			var d: Vector3 = m["pos"] - p
			var mp := c + Vector2(d.x, d.z) * to_px
			if inner.has_point(mp):
				draw_circle(mp, 4.0, m["col"])
		for s in world.ai.settlements:
			if s["discovered"]:
				var d2: Vector3 = s["pos"] - p
				var sp := c + Vector2(d2.x, d2.z) * to_px
				if inner.has_point(sp):
					draw_circle(sp, 5.0, Color(1, 0.3, 0.25) if s["hostile"] else Color(1, 0.9, 0.4))
		for n in world.ai.active_npcs:
			if is_instance_valid(n) and not n.dead:
				var d3: Vector3 = n.global_position - p
				var np := c + Vector2(d3.x, d3.z) * to_px
				if inner.has_point(np):
					var col := Color(0.4, 1, 0.5) if n.data["companion"] else (Color(1, 0.3, 0.3) if n.hostile_to_player else Color(0.9, 0.9, 0.9))
					draw_circle(np, 3.0, col)
		var bed = world.player.bed
		if bed != null and is_instance_valid(bed):
			var d4: Vector3 = bed.global_position - p
			var bp := c + Vector2(d4.x, d4.z) * to_px
			if inner.has_point(bp):
				draw_rect(Rect2(bp - Vector2(4, 4), Vector2(8, 8)), Color(0.5, 0.8, 1))
		var yaw: float = world.player.cam_yaw.rotation.y
		var fwd := Vector2(-sin(yaw), -cos(yaw))
		var right := Vector2(fwd.y, -fwd.x)
		draw_colored_polygon(PackedVector2Array([c + fwd * 10, c - fwd * 6 + right * 6, c - fwd * 6 - right * 6]), Color(1, 1, 1))
		var font := get_theme_default_font()
		draw_string_outline(font, Vector2(c.x - 6, 22), "ش", HORIZONTAL_ALIGNMENT_LEFT, -1, 18, 4, Color(0, 0, 0))
		draw_string(font, Vector2(c.x - 6, 22), "ش", HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color(1, 0.85, 0.5))

func _build_stats() -> void:
	var defs := [["health", "الصحة", Color(0.85, 0.22, 0.2)], ["stamina", "التحمل", Color(0.85, 0.82, 0.25)], ["hunger", "الشبع", Color(0.9, 0.55, 0.2)],
		["thirst", "الارتواء", Color(0.25, 0.6, 0.95)], ["warmth", "الدفء", Color(0.4, 0.85, 0.5)], ["energy", "الطاقة", Color(0.65, 0.45, 0.95)]]
	for d in defs:
		var b := StatBar.new()
		b.title = d[1]
		b.col = d[2]
		b.size = Vector2(190, 34)
		b.mouse_filter = Control.MOUSE_FILTER_IGNORE
		root.add_child(b)
		bars[d[0]] = b
	lbl_status = UIKit.label("", 17, Color(1, 0.85, 0.6))
	lbl_status.size = Vector2(380, 60)
	root.add_child(lbl_status)

func _build_info() -> void:
	minimap = MiniMap.new()
	minimap.world = world
	minimap.size = Vector2(170, 170)
	minimap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(minimap)
	lbl_clock = UIKit.label("", 19, UIKit.TEXT, HORIZONTAL_ALIGNMENT_LEFT)
	lbl_env = UIKit.label("", 16, UIKit.DIM, HORIZONTAL_ALIGNMENT_LEFT)
	lbl_weight = UIKit.label("", 17, UIKit.TEXT, HORIZONTAL_ALIGNMENT_LEFT)
	for l in [lbl_clock, lbl_env, lbl_weight]:
		l.size = Vector2(300, 28)
		l.autowrap_mode = TextServer.AUTOWRAP_OFF
		root.add_child(l)
	craft_lbl = UIKit.label("", 16, UIKit.TEXT, HORIZONTAL_ALIGNMENT_CENTER)
	craft_lbl.size = Vector2(300, 24)
	root.add_child(craft_lbl)
	craft_bar = UIKit.bar(UIKit.GOLD, 10)
	craft_bar.size = Vector2(220, 10)
	root.add_child(craft_bar)

func _build_center() -> void:
	crosshair = Control.new()
	crosshair.mouse_filter = Control.MOUSE_FILTER_IGNORE
	crosshair.size = Vector2(16, 16)
	crosshair.draw.connect(_draw_crosshair)
	root.add_child(crosshair)
	prompt_bg = PanelContainer.new()
	prompt_bg.add_theme_stylebox_override("panel", UIKit.sb(Color(0, 0, 0, 0.55), 12, 0, Color(0, 0, 0, 0), 12))
	prompt_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lbl_prompt = UIKit.label("", 21, Color(1, 0.96, 0.85), HORIZONTAL_ALIGNMENT_CENTER)
	lbl_prompt.autowrap_mode = TextServer.AUTOWRAP_OFF
	prompt_bg.add_child(lbl_prompt)
	root.add_child(prompt_bg)
	lbl_build = UIKit.label("", 19, Color(1, 0.95, 0.8), HORIZONTAL_ALIGNMENT_CENTER)
	lbl_build.size = Vector2(700, 60)
	root.add_child(lbl_build)

func _draw_crosshair() -> void:
	crosshair.draw_circle(Vector2(8, 8), 3.0, Color(1, 1, 1, 0.85))
	crosshair.draw_arc(Vector2(8, 8), 6.0, 0, TAU, 16, Color(0, 0, 0, 0.5), 1.5)

func _build_hotbar() -> void:
	for i in range(6):
		var b := _btn("hb%d" % i, "", Vector2(78, 78), false)
		var ic := ItemIcon.new()
		ic.size = Vector2(66, 66)
		ic.position = Vector2(6, 6)
		b.add_child(ic)
		b.sub = str(i + 1)
		hotbar.append(b)
		hot_icons.append(ic)

func _build_buttons() -> void:
	_btn("attack", "اضرب", Vector2(128, 128)).font_size = 24
	_btn("jump", "قفز", Vector2(88, 88))
	_btn("interact", "تفاعل", Vector2(96, 96)).tint = Color(0.6, 1, 0.7)
	_btn("sprint", "جري", Vector2(80, 80))
	_btn("crouch", "انحناء", Vector2(80, 80))
	for d in [["inv", "الحقيبة"], ["craft", "صناعة"], ["build", "بناء"], ["map", "خريطة"], ["char", "شخصيتي"], ["cam", "كاميرا"], ["pause", "قائمة"]]:
		var b := _btn(d[0], d[1], Vector2(76, 48), false)
		b.font_size = 17
	_btn("rotate", "تدوير", Vector2(88, 88))
	_btn("demolish", "هدم", Vector2(80, 80)).tint = Color(1, 0.5, 0.4)
	_btn("build_exit", "خروج", Vector2(80, 80))

func _build_buildbar() -> void:
	build_bar = PanelContainer.new()
	build_bar.add_theme_stylebox_override("panel", UIKit.sb(Color(0.05, 0.05, 0.06, 0.85), 12, 1, Color(0.9, 0.75, 0.45, 0.3), 6))
	build_bar.clip_contents = true
	var v := UIKit.vbox(5)
	build_bar.add_child(v)
	var cats := UIKit.hbox(5)
	cats.alignment = BoxContainer.ALIGNMENT_END
	v.add_child(cats)
	for c in BuildDB.CATS:
		var cb := UIKit.button(BuildDB.CAT_NAMES[c], func(): build_cat = c; _fill_build_list(), 15, 38)
		cb.custom_minimum_size = Vector2(0, 38)
		cats.add_child(cb)
	var row2 := UIKit.hbox(6)
	v.add_child(row2)
	var sc := ScrollContainer.new()
	sc.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	sc.custom_minimum_size = Vector2(0, 70)
	sc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.scroll_deadzone = 12
	row2.add_child(sc)
	build_list = UIKit.hbox(6)
	sc.add_child(build_list)
	build_mats = UIKit.vbox(2)
	var mg := GridContainer.new()
	mg.columns = 2
	mg.add_theme_constant_override("h_separation", 3)
	mg.add_theme_constant_override("v_separation", 3)
	build_mats.add_child(mg)
	for m in ["wood", "thatch", "brick", "stone"]:
		var mb := UIKit.button(BuildDB.MAT_NAMES[m], func(): build_mat = m; build_cat = "structure"; _fill_build_list(), 14, 32)
		mb.custom_minimum_size = Vector2(56, 32)
		mb.modulate = Color(1, 0.9, 0.7)
		mg.add_child(mb)
	row2.add_child(build_mats)
	root.add_child(build_bar)
	build_bar.visible = false
	touch.blockers.append(build_bar)
	_fill_build_list()

func _fill_build_list() -> void:
	build_mats.visible = build_cat == "structure"
	for c in build_list.get_children():
		c.queue_free()
	for id in BuildDB.order:
		var d := BuildDB.get_piece(id)
		if d["cat"] != build_cat:
			continue
		if build_cat == "structure" and d.get("mat", "") != build_mat and d.get("slot", "") != "door":
			continue
		var can: bool = player.inventory.has_all(d["cost"])
		var b := UIKit.button(d["name"], func(): player.build_id = id; player.build_rot = 0; _fill_build_list(), 15, 66)
		b.custom_minimum_size = Vector2(112, 66)
		b.tooltip_text = BuildDB.cost_text(id)
		b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		if not can:
			b.modulate = Color(1, 0.6, 0.55)
		if player.build_id == id:
			b.add_theme_stylebox_override("normal", UIKit.sb(Color(0.45, 0.34, 0.15, 1.0), 10, 2, UIKit.GOLD, 10))
		build_list.add_child(b)

func _build_notifs() -> void:
	notif_box = UIKit.vbox(4)
	notif_box.size = Vector2(640, 200)
	notif_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(notif_box)

func _build_overlays() -> void:
	sleep_overlay = ColorRect.new()
	(sleep_overlay as ColorRect).color = Color(0, 0, 0.02, 0.82)
	sleep_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	sleep_overlay.visible = false
	root.add_child(sleep_overlay)
	var sv := UIKit.vbox(16)
	sv.set_anchors_preset(Control.PRESET_CENTER)
	sv.position = Vector2(-200, -80)
	sv.size = Vector2(400, 160)
	sleep_overlay.add_child(sv)
	sleep_lbl = UIKit.label("نائم...", 30, UIKit.TEXT, HORIZONTAL_ALIGNMENT_CENTER)
	sv.add_child(sleep_lbl)
	sv.add_child(UIKit.button("استيقظ", func(): player.wake_up(), 24, 64))
	death_overlay = ColorRect.new()
	(death_overlay as ColorRect).color = Color(0.15, 0, 0, 0.85)
	death_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	death_overlay.visible = false
	root.add_child(death_overlay)
	var dv := UIKit.vbox(18)
	dv.set_anchors_preset(Control.PRESET_CENTER)
	dv.position = Vector2(-300, -140)
	dv.size = Vector2(600, 280)
	death_overlay.add_child(dv)
	dv.add_child(UIKit.label("لقد متّ", 48, Color(1, 0.5, 0.45), HORIZONTAL_ALIGNMENT_CENTER))
	death_lbl = UIKit.label("", 22, UIKit.TEXT, HORIZONTAL_ALIGNMENT_CENTER)
	dv.add_child(death_lbl)
	dv.add_child(UIKit.button("انهض من جديد", _respawn, 26, 70))

func _respawn() -> void:
	death_overlay.visible = false
	Game.ui_open = false
	player.respawn()

func show_death(cause: String) -> void:
	for p in panels.values():
		p.visible = false
	death_lbl.text = "السبب: %s\nستُبعث عند سريرك أو نقطة البداية.\nأغراضك بقيت في كيس عند مكان موتك (معلّم على الخريطة)." % cause
	death_overlay.visible = true
	Game.ui_open = true
	touch.reset()

func show_sleep(on: bool) -> void:
	sleep_overlay.visible = on
	touch.reset()

func flash_damage() -> void:
	dmg_flash.color.a = 0.35

# ------------------------------------------------------------------
func _layout() -> void:
	var s := root.size
	_last_size = s
	var m := 16.0
	var y := m
	for k in ["health", "stamina", "hunger", "thirst", "warmth", "energy"]:
		bars[k].position = Vector2(s.x - 190 - m, y)
		y += 36
	lbl_status.position = Vector2(s.x - 380 - m, y + 2)
	minimap.position = Vector2(m, m + 6)
	lbl_clock.position = Vector2(m + 180, m)
	lbl_env.position = Vector2(m + 180, m + 30)
	lbl_weight.position = Vector2(m + 180, m + 56)
	craft_lbl.position = Vector2(s.x * 0.5 - 150, 8)
	craft_bar.position = Vector2(s.x * 0.5 - 110, 34)
	crosshair.position = s * 0.5 - Vector2(8, 8)
	notif_box.position = Vector2(s.x * 0.5 - 320, 52)
	lbl_build.position = Vector2(s.x * 0.5 - 350, 96)
	var hb_w := 6 * 84.0
	for i in range(6):
		hotbar[i].position = Vector2(s.x * 0.5 - hb_w * 0.5 + i * 84, s.y - 86)
	var bx := s.x - m
	var by := s.y - m
	btns["attack"].position = Vector2(bx - 128 - 20, by - 128 - 40)
	btns["jump"].position = Vector2(bx - 88, by - 300)
	btns["interact"].position = Vector2(bx - 128 - 140, by - 128 - 10)
	btns["sprint"].position = Vector2(bx - 128 - 130, by - 290)
	btns["crouch"].position = Vector2(bx - 90, by - 400)
	btns["rotate"].position = Vector2(bx - 128 - 140, by - 128 - 10)
	btns["demolish"].position = Vector2(bx - 90, by - 300)
	btns["build_exit"].position = Vector2(bx - 128 - 130, by - 290)
	var mx := m
	for id in ["inv", "craft", "build", "map", "char", "cam", "pause"]:
		btns[id].position = Vector2(mx, 200)
		mx += 82
	build_bar.position = Vector2(s.x * 0.5 - 350, s.y - 86 - 140)
	build_bar.size = Vector2(700, 130)

func on_panel_open(p: Control) -> void:
	for k in panels:
		if panels[k] != p:
			panels[k].visible = false
	Game.ui_open = true
	touch.reset()
	player.input_move = Vector2.ZERO
	player.attack_held = false
	if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func on_panel_close(_p: Control) -> void:
	for k in panels:
		if panels[k].visible:
			return
	Game.ui_open = death_overlay.visible
	_hot_dirty = true

func open_panel(name: String) -> void:
	var p = panels[name]
	if p.visible:
		p.close()
	else:
		p.open()

func open_dialog(npc) -> void:
	panels["dialog"].open_for(npc)

func open_trade(npc) -> void:
	panels["trade"].open_for(npc)

func open_storage(c) -> void:
	panels["storage"].open_for(c)

func open_crafting(station: String) -> void:
	panels["crafting"].open_for(station)

func _on_btn_down(id: String) -> void:
	match id:
		"attack":
			player.attack_held = true
			player.press("attack")
		"jump": player.press("jump")
		"interact": player.press("interact")
		"sprint":
			player.sprint_on = not player.sprint_on
			btns["sprint"].toggled = player.sprint_on
		"crouch":
			player.press("crouch")
		"inv": open_panel("inventory")
		"craft": open_crafting("")
		"build":
			player.set_build_mode(not player.build_mode)
			player.demolish_mode = false
			_fill_build_list()
		"build_exit":
			player.set_build_mode(false)
		"rotate": player.press("rotate")
		"demolish":
			player.demolish_mode = not player.demolish_mode
		"map": open_panel("map")
		"char": open_panel("character")
		"cam": player.press("camera")
		"pause": open_panel("pause")
		_:
			if id.begins_with("hb"):
				player.select_slot(int(id.substr(2)))
				_hot_dirty = true

func _on_btn_up(id: String) -> void:
	if id == "attack":
		player.attack_held = false

func _unhandled_input(e: InputEvent) -> void:
	if e.is_action_pressed("inventory"):
		open_panel("inventory")
	elif e.is_action_pressed("craft"):
		open_crafting("")
	elif e.is_action_pressed("map"):
		open_panel("map")
	elif e.is_action_pressed("character"):
		open_panel("character")
	elif e.is_action_pressed("build") and not Game.ui_open:
		player.set_build_mode(not player.build_mode)
		_fill_build_list()
	elif e.is_action_pressed("pause"):
		var any := false
		for p in panels.values():
			if p.visible:
				p.close()
				any = true
		if not any:
			if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
				Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
			else:
				open_panel("pause")

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		var any := false
		for p in panels.values():
			if p.visible:
				p.close()
				any = true
		if not any:
			open_panel("pause")

func _on_notify(text: String, col: Color) -> void:
	var l := UIKit.label(text, 19, col, HORIZONTAL_ALIGNMENT_CENTER)
	l.custom_minimum_size = Vector2(640, 0)
	var pc := PanelContainer.new()
	pc.add_theme_stylebox_override("panel", UIKit.sb(Color(0, 0, 0, 0.5), 10, 0, Color(0, 0, 0, 0), 8))
	pc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pc.add_child(l)
	notif_box.add_child(pc)
	while notif_box.get_child_count() > 5:
		var c := notif_box.get_child(0)
		notif_box.remove_child(c)
		c.queue_free()
	var tw := pc.create_tween()
	tw.tween_interval(4.5)
	tw.tween_property(pc, "modulate:a", 0.0, 0.8)
	tw.tween_callback(pc.queue_free)

# ------------------------------------------------------------------
func _process(dt: float) -> void:
	if player == null:
		return
	if root.size != _last_size:
		_layout()
	var bb: Control = build_bar
	touch.enabled = not Game.ui_open
	if not Game.ui_open:
		var mv: Vector2 = touch.joy_vec
		if mv.length() < 0.12:
			mv = Vector2.ZERO
		player.input_move = mv
		var look := touch.take_look()
		if look != Vector2.ZERO:
			player.add_look(look * 1.3)
	if dmg_flash.color.a > 0.0:
		dmg_flash.color.a = maxf(0.0, dmg_flash.color.a - dt * 0.8)
	var low_hp := player.stats.health < 25.0 and not player.stats.dead
	if low_hp and dmg_flash.color.a < 0.12:
		dmg_flash.color.a = 0.08 + sin(Time.get_ticks_msec() * 0.006) * 0.05
	underwater.visible = player.camera.global_position.y < 0.0
	_upd_t -= dt
	if _upd_t > 0.0:
		return
	_upd_t = 0.1
	var st := player.stats
	bars["health"].value = st.health
	bars["health"].warn = st.health < 25.0
	bars["stamina"].value = st.stamina / st.max_stamina() * 100.0
	bars["stamina"].extra = str(int(st.stamina))
	bars["hunger"].value = st.hunger
	bars["hunger"].warn = st.hunger < 15.0
	bars["thirst"].value = st.thirst
	bars["thirst"].warn = st.thirst < 15.0
	var wv := st.warmth_value()
	bars["warmth"].value = wv
	bars["warmth"].extra = "%.1f°" % st.body_temp
	bars["warmth"].col = Color(0.35, 0.65, 1.0) if st.body_temp < 35.8 else (Color(1.0, 0.45, 0.2) if st.body_temp > 38.0 else Color(0.4, 0.85, 0.5))
	bars["warmth"].warn = st.body_temp < 34.8 or st.body_temp > 39.0
	bars["energy"].value = st.energy
	bars["energy"].warn = st.energy < 15.0
	for b in bars.values():
		b.queue_redraw()
	var sl := []
	for e in st.status_list():
		sl.append(e[0])
	var trend := st.temp_trend()
	if trend < -0.4:
		sl.append("حرارتك تنخفض")
	elif trend > 0.4:
		sl.append("حرارتك ترتفع")
	lbl_status.text = " • ".join(sl)
	lbl_clock.text = world.sky.clock_text()
	var pp := player.global_position
	var bio = world.gen.biome_at(pp.x, pp.z)
	lbl_env.text = "%s | %s | %d°م%s" % [WorldGen.BIOME_NAMES[bio], world.sky.weather_name(), int(round(player.ambient_temp)), " (داخل مأوى)" if player.shelter > 0.45 else ""]
	var w := player.carry_weight()
	var cap := st.carry_capacity()
	lbl_weight.text = "الحمولة: %.1f / %.0f كغ" % [w, cap]
	lbl_weight.add_theme_color_override("font_color", UIKit.TEXT if w <= cap else (Color(1, 0.75, 0.3) if w < cap * 1.5 else UIKit.BAD))
	minimap.queue_redraw()
	if Game.settings.get("show_fps", false):
		fps_lbl.text = "FPS %d" % Engine.get_frames_per_second()
	else:
		fps_lbl.text = ""
	# التركيز
	var ft: String = player.focus_text
	prompt_bg.visible = ft != "" and not player.build_mode
	if prompt_bg.visible:
		lbl_prompt.text = ft
		prompt_bg.reset_size()
		prompt_bg.position = Vector2(root.size.x * 0.5 - prompt_bg.size.x * 0.5, root.size.y * 0.5 + 34)
	# الصناعة
	if player.craft_queue.is_empty():
		craft_lbl.text = ""
		craft_bar.visible = false
	else:
		var q: Dictionary = player.craft_queue[0]
		craft_lbl.text = "جارِ صنع: %s%s" % [ItemDB.name_of(q["r"]["out"]), "  (+%d بالانتظار)" % (player.craft_queue.size() - 1) if player.craft_queue.size() > 1 else ""]
		craft_bar.visible = true
		craft_bar.value = (1.0 - q["t"] / maxf(q["total"], 0.01)) * 100.0
	# الأزرار حسب السياق
	var bm := player.build_mode
	for id in ["jump", "sprint", "crouch"]:
		btns[id].visible = not bm
	btns["interact"].visible = not bm and (player.focus != null or player.focus_water)
	btns["rotate"].visible = bm and not player.demolish_mode
	btns["demolish"].visible = bm
	btns["build_exit"].visible = bm
	btns["demolish"].toggled = player.demolish_mode
	btns["build"].toggled = bm
	btns["sprint"].toggled = player.sprint_on
	btns["crouch"].toggled = player.crouching
	bb.visible = bm and not player.demolish_mode
	lbl_build.visible = bm
	if bm:
		lbl_build.text = player.build_status()
	btns["attack"].set_text(_attack_label())
	if bm:
		btns["interact"].visible = false
	var night: float = world.sky.darkness()
	night_tint.color.a = night * 0.25
	if sleep_overlay.visible:
		sleep_lbl.text = "نائم...  %s\nالطاقة %d٪" % [world.sky.clock_text(), int(player.stats.energy)]
	if _hot_dirty:
		_hot_dirty = false
		for i in range(6):
			var s = player.inventory.slots[i]
			if s != null:
				hot_icons[i].set_item(s["id"], s["n"], s.get("d", -1.0))
			else:
				hot_icons[i].set_item("")
			hotbar[i].toggled = i == player.sel
			hotbar[i].queue_redraw()
	else:
		var s2 = player.inventory.slots[player.sel]
		if s2 != null and s2.get("d", -1.0) >= 0.0:
			hot_icons[player.sel].set_item(s2["id"], s2["n"], s2["d"])
	for k in btns:
		btns[k].queue_redraw()

func _attack_label() -> String:
	if player.build_mode:
		return "اهدم" if player.demolish_mode else "ضع"
	var id := player.held_item_id()
	var it := ItemDB.get_item(id) if id != "" else {}
	if it.has("food"):
		return "اشرب" if it["food"].get("t", 0) > it["food"].get("h", 0) else "كُل"
	if it.has("med"):
		return "عالج"
	var kind := player.held_tool_kind()
	if player.focus_water and kind == "rod":
		return "اصطد"
	if player.focus_water and id == "waterskin":
		return "املأ"
	if kind == "bow":
		return "ارمِ"
	if player.focus is ResourceBody:
		var td := ResDB.get_type(player.focus.rtype)
		if td.get("tool", "") == "axe":
			return "اقطع"
		if td.get("tool", "") == "pickaxe":
			return "اكسر"
	if id == "":
		return "لكم"
	return "اضرب"
