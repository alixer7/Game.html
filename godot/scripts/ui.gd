extends Node
## All 2D UI: loading, HUD, announcer, screen blood, menus, move list, touch controls.

const CD = preload("res://scripts/chardata.gd")
const PZ = preload("res://scripts/pose.gd")
const Rig = preload("res://scripts/rig.gd")

const GOLD := Color(0.79, 0.64, 0.36)
const BONE := Color(0.91, 0.86, 0.77)
const BLOOD := Color(0.82, 0.08, 0.1)

var theme: Theme
var post_mat: ShaderMaterial
var blood_root: Control
var hud: Control
var bars := []
var meters := []
var names := []
var combo := []
var combo_t := [0.0, 0.0]
var tags := []
var timer_lbl: Label
var ann_big: Label
var ann_small: Label
var ann_tween: Tween
var super_lbl: Label
var train_lbl: Label
var exec_lbl: Label
var card_node: Control
var menu: Control
var back_fn = null
var custom_key = null
var touch_pad: Control
var loading: Control
var load_bar: ColorRect
var load_txt: Label
var portraits := {}
var last_timer := -1
var trail := [1.0, 1.0]
var cs := {}
var post_desat := 0.08

func _ready() -> void:
	theme = Theme.new()
	theme.default_font = Mats.font_ar
	theme.default_font_size = 22
	var bn := StyleBoxFlat.new()
	bn.bg_color = Color(0.2, 0.0, 0.0, 0.55)
	bn.border_color = Color(GOLD, 0.3)
	bn.border_width_top = 1
	bn.border_width_bottom = 1
	bn.content_margin_left = 30; bn.content_margin_right = 30; bn.content_margin_top = 4; bn.content_margin_bottom = 18
	var bh := bn.duplicate()
	bh.bg_color = Color(0.6, 0.03, 0.03, 0.85)
	bh.border_color = Color(1, 0.3, 0.2, 0.8)
	theme.set_stylebox("normal", "Button", bn)
	theme.set_stylebox("hover", "Button", bh)
	theme.set_stylebox("focus", "Button", bh)
	theme.set_stylebox("pressed", "Button", bh)
	theme.set_color("font_color", "Button", BONE)
	theme.set_color("font_hover_color", "Button", Color.WHITE)
	theme.set_color("font_focus_color", "Button", Color.WHITE)
	theme.set_color("font_color", "Label", BONE)
	var post := CanvasLayer.new()
	post.layer = 1
	add_child(post)
	var pr := ColorRect.new()
	pr.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	pr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	post_mat = Mats.smat("post")
	pr.material = post_mat
	post.add_child(pr)
	var bl := CanvasLayer.new()
	bl.layer = 2
	add_child(bl)
	blood_root = _full(bl)
	var hl := CanvasLayer.new()
	hl.layer = 3
	add_child(hl)
	hud = _full(hl)
	hud.theme = theme
	_build_hud()
	var al := CanvasLayer.new()
	al.layer = 4
	add_child(al)
	var aroot := _full(al)
	aroot.theme = theme
	ann_big = _label(aroot, "", Mats.font_title, 120, Color(1, 0.3, 0.2))
	ann_big.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ann_big.offset_top = -60
	ann_big.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ann_big.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_outline(ann_big, Color(0.15, 0, 0), 14)
	ann_small = _label(aroot, "", Mats.font_ar, 38, GOLD)
	ann_small.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ann_small.offset_top = 150
	ann_small.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ann_small.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_outline(ann_small, Color.BLACK, 8)
	super_lbl = _label(aroot, "", Mats.font_title, 56, Color(1, 0.8, 0.6))
	super_lbl.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	super_lbl.offset_top = 330
	super_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	super_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_outline(super_lbl, Color(0.4, 0.05, 0), 12)
	super_lbl.modulate.a = 0.0
	exec_lbl = _label(aroot, "", Mats.font_ar, 22, Color.WHITE)
	exec_lbl.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	exec_lbl.position = Vector2(-500, -150)
	exec_lbl.size = Vector2(1000, 50)
	exec_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_outline(exec_lbl, Color.BLACK, 6)
	var ml := CanvasLayer.new()
	ml.layer = 6
	add_child(ml)
	menu = _full(ml)
	menu.theme = theme
	menu.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var tl := CanvasLayer.new()
	tl.layer = 5
	add_child(tl)
	touch_pad = TouchPad.new()
	touch_pad.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	touch_pad.mouse_filter = Control.MOUSE_FILTER_IGNORE
	touch_pad.visible = false
	tl.add_child(touch_pad)
	var ll := CanvasLayer.new()
	ll.layer = 10
	add_child(ll)
	loading = _full(ll)
	loading.theme = theme
	var bg := ColorRect.new()
	bg.color = Color(0.03, 0.0, 0.0)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	loading.add_child(bg)
	var lg := _logo(loading, 120)
	lg.offset_top = -80
	var sub := _label(loading, "طقوس الدم", Mats.font_ar, 36, GOLD)
	sub.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	sub.offset_top = 70
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	var bb := ColorRect.new()
	bb.color = Color(0.15, 0, 0)
	bb.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	bb.position = Vector2(-220, 140)
	bb.size = Vector2(440, 5)
	loading.add_child(bb)
	load_bar = ColorRect.new()
	load_bar.color = Color(1, 0.15, 0.1)
	load_bar.size = Vector2(0, 5)
	bb.add_child(load_bar)
	load_txt = _label(loading, "", Mats.font_ar, 18, Color(0.7, 0.55, 0.55))
	load_txt.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	load_txt.offset_top = 330
	load_txt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	load_txt.vertical_alignment = VERTICAL_ALIGNMENT_CENTER

# ================================================================= helpers
func _full(parent: Node) -> Control:
	var c := Control.new()
	c.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(c)
	return c

func _label(parent: Node, text: String, font: Font, size: int, col: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", font)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(l)
	return l

func _outline(l: Label, c: Color, s: int) -> void:
	l.add_theme_color_override("font_outline_color", c)
	l.add_theme_constant_override("outline_size", s)
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	l.add_theme_constant_override("shadow_offset_y", 4)

func _logo(parent: Node, size: int) -> Label:
	var l := _label(parent, "BLOODRITE", Mats.font_title, size, Color(0.85, 0.05, 0.08))
	l.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_outline(l, Color(0.2, 0.0, 0.02), 16)
	return l

## Tween that runs at real-time speed regardless of Engine.time_scale (set at creation).
func _rt_tween() -> Tween:
	return create_tween().set_speed_scale(1.0 / maxf(0.05, Engine.time_scale))

func show_loading(p: float, txt: String) -> void:
	load_bar.size.x = 440.0 * p
	load_txt.text = txt

func hide_loading() -> void:
	var t := create_tween()
	t.tween_property(loading, "modulate:a", 0.0, 0.6)
	t.tween_callback(func(): loading.visible = false)

func set_post(impact: bool, desat: float, shake: float, red: float) -> void:
	post_mat.set_shader_parameter("impact", 1.0 if impact else 0.0)
	post_desat = lerpf(post_desat, 0.08 + desat, 0.15)
	post_mat.set_shader_parameter("desat", post_desat)
	post_mat.set_shader_parameter("ca", 0.0012 + shake * 0.006)
	post_mat.set_shader_parameter("red", red)

# ================================================================= HUD
class Bar extends Control:
	var ratio := 1.0
	var trail := 1.0
	var side := 0
	var poison := false
	var wins := 0
	func _draw() -> void:
		var w := size.x
		var h := size.y
		var sk := h * 0.35
		var fr := [Vector2(sk, 0), Vector2(w, 0), Vector2(w - sk, h), Vector2(0, h)] if side == 0 else [Vector2(0, 0), Vector2(w - sk, 0), Vector2(w, h), Vector2(sk, h)]
		draw_colored_polygon(PackedVector2Array(fr), Color(0.07, 0.01, 0.015, 0.95))
		var seg := func(r: float, c1: Color, c2: Color):
			if r <= 0.0: return
			var x0 := 0.0 if side == 0 else w * (1.0 - r)
			var x1 := w * r if side == 0 else w
			var pts := PackedVector2Array([Vector2(x0 + sk, 2), Vector2(x1, 2), Vector2(x1 - sk, h - 2), Vector2(x0, h - 2)]) if side == 0 else PackedVector2Array([Vector2(x0, 2), Vector2(x1 - sk, 2), Vector2(x1, h - 2), Vector2(x0 + sk, h - 2)])
			draw_polygon(pts, PackedColorArray([c1, c1, c2, c2]))
		seg.call(trail, Color(1, 0.95, 0.75), Color(0.85, 0.68, 0.38))
		if poison: seg.call(ratio, Color(0.72, 1, 0.48), Color(0.09, 0.25, 0.03))
		else: seg.call(ratio, Color(1, 0.48, 0.33), Color(0.43, 0.02, 0.05))
		draw_polyline(PackedVector2Array(fr + [fr[0]]), Color(0.48, 0.39, 0.25), 2.0, true)
		for i in 2:
			var cx := w - 20.0 - i * 26.0 if side == 0 else 20.0 + i * 26.0
			var cy := h + 22.0
			var d := PackedVector2Array([Vector2(cx, cy - 9), Vector2(cx + 9, cy), Vector2(cx, cy + 9), Vector2(cx - 9, cy)])
			draw_colored_polygon(d, Color(1, 0.22, 0.12) if i < wins else Color(0.1, 0.01, 0.01))
			draw_polyline(PackedVector2Array([d[0], d[1], d[2], d[3], d[0]]), Color(0.48, 0.39, 0.25), 2.0)

class Meter extends Control:
	var v := 0.0
	var side := 0
	func _draw() -> void:
		var w := size.x / 3.0 - 6.0
		var h := size.y
		var full := v >= 300.0
		for i in 3:
			var k := clampf((v - i * 100.0) / 100.0, 0.0, 1.0)
			var x := (i * (w + 6.0)) if side == 0 else (size.x - (i + 1) * (w + 6.0))
			var sk := 6.0
			var fr := PackedVector2Array([Vector2(x + sk, 0), Vector2(x + w + sk, 0), Vector2(x + w, h), Vector2(x, h)])
			draw_colored_polygon(fr, Color(0.08, 0.01, 0.01, 0.9))
			if k > 0.0:
				var fx := x + w * k if side == 0 else x + w
				var sx := x if side == 0 else x + w * (1.0 - k)
				var g := 0.5 + 0.5 * sin(Time.get_ticks_msec() / 90.0) if full else 0.0
				draw_polygon(PackedVector2Array([Vector2(sx + sk, 1), Vector2(fx + sk, 1), Vector2(fx, h - 1), Vector2(sx, h - 1)]), PackedColorArray([Color(1, 0.82, 0.48), Color(1, 0.82, 0.48), Color(0.6 + g * 0.4, 0.05, 0), Color(0.6 + g * 0.4, 0.05, 0)]))
			draw_polyline(PackedVector2Array([fr[0], fr[1], fr[2], fr[3], fr[0]]), Color(0.42, 0.29, 0.16) if not full else Color(1, 0.4, 0.2), 1.5)

func _build_hud() -> void:
	hud.visible = false
	for s in 2:
		var b := Bar.new()
		b.side = s
		b.anchor_left = 0.03 if s == 0 else 0.57
		b.anchor_right = 0.43 if s == 0 else 0.97
		b.offset_top = 16
		b.offset_bottom = 44
		hud.add_child(b)
		bars.append(b)
		var nm := _label(hud, "", Mats.font_latin, 22, BONE)
		nm.anchor_left = b.anchor_left
		nm.anchor_right = b.anchor_right
		nm.offset_top = 48
		nm.offset_left = 8
		nm.offset_right = -8
		nm.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT if s == 0 else HORIZONTAL_ALIGNMENT_RIGHT
		_outline(nm, Color.BLACK, 6)
		names.append(nm)
		var m := Meter.new()
		m.side = s
		m.anchor_left = 0.03 if s == 0 else 0.67
		m.anchor_right = 0.33 if s == 0 else 0.97
		m.anchor_top = 1.0
		m.anchor_bottom = 1.0
		m.offset_top = -34
		m.offset_bottom = -20
		hud.add_child(m)
		meters.append(m)
		var cb := _label(hud, "", Mats.font_latin, 54, Color.WHITE)
		cb.anchor_left = 0.035 if s == 0 else 0.6
		cb.anchor_right = 0.4 if s == 0 else 0.965
		cb.anchor_top = 0.27
		cb.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT if s == 0 else HORIZONTAL_ALIGNMENT_RIGHT
		_outline(cb, Color(0.5, 0, 0), 10)
		cb.modulate.a = 0.0
		combo.append(cb)
		var tg := _label(hud, "", Mats.font_latin, 30, Color(1, 0.82, 0.5))
		tg.anchor_left = cb.anchor_left
		tg.anchor_right = cb.anchor_right
		tg.anchor_top = 0.43
		tg.horizontal_alignment = cb.horizontal_alignment
		_outline(tg, Color(0.6, 0.15, 0), 10)
		tg.modulate.a = 0.0
		tags.append(tg)
	timer_lbl = _label(hud, "99", Mats.font_latin, 44, BONE)
	timer_lbl.anchor_left = 0.5
	timer_lbl.anchor_right = 0.5
	timer_lbl.offset_left = -50
	timer_lbl.offset_right = 50
	timer_lbl.offset_top = 6
	timer_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_outline(timer_lbl, Color(0.55, 0, 0), 10)
	train_lbl = _label(hud, "", Mats.font_ar, 15, BONE)
	train_lbl.position = Vector2(14, 96)
	train_lbl.size = Vector2(420, 120)
	_outline(train_lbl, Color.BLACK, 5)

func show_hud(A, B, m: String) -> void:
	hud.visible = true
	names[0].text = A.def.name
	names[1].text = B.def.name
	timer_lbl.visible = m != "training"
	train_lbl.visible = m == "training"
	train_lbl.text = "نفّذ أي حركة لعرض بيانات الإطارات" if m == "training" else ""
	touch_pad.visible = DisplayServer.is_touchscreen_available() or G.args.has("touch")
	trail = [1.0, 1.0]
	last_timer = -1

func hide_hud() -> void:
	hud.visible = false
	touch_pad.visible = false
	G.touch.clear()

func update_wins(w: Array) -> void:
	for i in 2:
		bars[i].wins = w[i]
		bars[i].queue_redraw()

func update_hud(dt: float) -> void:
	if not hud.visible or G.f.size() != 2: return
	for i in 2:
		var F = G.f[i]
		var r := clampf(float(F.hp) / F.max_hp, 0.0, 1.0)
		var fast: bool = not (F.state in ["hit", "juggle", "cine"])
		if trail[i] > r: trail[i] = maxf(r, trail[i] - dt * (0.35 if fast else 0.02))
		else: trail[i] = r
		var b: Bar = bars[i]
		if b.ratio != r or b.trail != trail[i] or b.poison != (F.poison > 0):
			b.ratio = r; b.trail = trail[i]; b.poison = F.poison > 0
			b.queue_redraw()
		meters[i].v = F.meter
		meters[i].queue_redraw()
		var O = F.opp()
		var cb: Label = combo[i]
		if O.combo_hits >= 2:
			cb.text = "%d HITS\n%d%%" % [O.combo_hits, roundi(float(O.combo_dmg) / O.max_hp * 100.0)]
			cb.modulate.a = 1.0
			combo_t[i] = 1.4
		else:
			combo_t[i] -= dt
			if combo_t[i] <= 0.0: cb.modulate.a = maxf(0.0, cb.modulate.a - dt * 4.0)
	var t := maxi(0, ceili(G.timer / 60.0))
	if t != last_timer:
		timer_lbl.text = str(t)
		last_timer = t

func show_tag(idx: int, text: String) -> void:
	var tg: Label = tags[idx]
	tg.text = text
	tg.modulate.a = 1.0
	tg.pivot_offset = tg.size / 2.0
	tg.scale = Vector2(1.6, 1.6)
	var tw := create_tween()
	tw.tween_property(tg, "scale", Vector2.ONE, 0.25)
	tw.tween_interval(0.6)
	tw.tween_property(tg, "modulate:a", 0.0, 0.25)

func announce(big: String, small: String, dur := 1.2, bone := false) -> void:
	if ann_tween: ann_tween.kill()
	ann_big.text = big
	ann_small.text = small
	ann_big.add_theme_color_override("font_color", BONE if bone else Color(1, 0.25, 0.15))
	ann_big.modulate.a = 1.0
	ann_small.modulate.a = 1.0
	ann_big.pivot_offset = get_viewport().get_visible_rect().size / 2.0
	ann_big.scale = Vector2(2.2, 2.2)
	ann_tween = _rt_tween()
	ann_tween.tween_property(ann_big, "scale", Vector2.ONE, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	ann_tween.tween_interval(dur)
	ann_tween.tween_property(ann_big, "modulate:a", 0.0, 0.35)
	ann_tween.parallel().tween_property(ann_small, "modulate:a", 0.0, 0.35)

func show_super_name(n: String, ar: String) -> void:
	super_lbl.text = n + "\n" + ar
	super_lbl.modulate.a = 0.0
	super_lbl.position.x = -300
	var tw := _rt_tween()
	tw.tween_property(super_lbl, "modulate:a", 1.0, 0.2)
	tw.parallel().tween_property(super_lbl, "position:x", 0.0, 0.25)
	tw.tween_interval(1.0)
	tw.tween_property(super_lbl, "modulate:a", 0.0, 0.3)

func show_exec_hint(A) -> void:
	var E: Dictionary = A.def.exec
	exec_lbl.text = "الإعدام «%s»:  %s  — المسافة: %s" % [E.ar, E.cmd, {close = "قريب", mid = "متوسط", far = "بعيد"}[E.range]]
	exec_lbl.visible = true

func hide_exec_hint() -> void:
	exec_lbl.visible = false

func name_card(F) -> void:
	clear_name_card()
	card_node = Control.new()
	card_node.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	card_node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.add_child(card_node)
	var al := HORIZONTAL_ALIGNMENT_LEFT if F.idx == 0 else HORIZONTAL_ALIGNMENT_RIGHT
	var y := 0.66
	for row in [[F.def.name, Mats.font_title, 76, Color.WHITE], [F.def.title, Mats.font_latin, 20, F.def.color], [F.def.title_ar, Mats.font_ar, 28, GOLD]]:
		var l := _label(card_node, row[0], row[1], row[2], row[3])
		l.anchor_left = 0.05
		l.anchor_right = 0.95
		l.anchor_top = y
		l.horizontal_alignment = al
		_outline(l, Color(0.3, 0, 0) if row[2] > 50 else Color.BLACK, 10)
		y += 0.11 if row[2] > 50 else 0.05
	card_node.modulate.a = 0.0
	create_tween().tween_property(card_node, "modulate:a", 1.0, 0.4)

func clear_name_card() -> void:
	if card_node and is_instance_valid(card_node): card_node.queue_free()
	card_node = null

func train_panel() -> void:
	var T = G.training
	var m = T.last
	if m == null: return
	var fmt := func(v): return "—" if v == null else ("إسقاط" if typeof(v) == TYPE_STRING else ("+" if v > 0 else "") + str(v))
	var dmg := 0
	for h in m.hits: dmg += h.dmg
	var dm: String = {stand = "واقف", block = "يصد كل شيء", crouch = "منحنٍ ويصد", jump = "يقفز", cpu = "ذكاء اصطناعي"}[T.dummy]
	train_lbl.text = "%s  %s\nالانطلاق: %d إطار · الضرر: %d\nعند الصد: %s · عند الإصابة: %s\nآخر كومبو: %d ضرر · الدمية: %s" % [m.get("ar", m.name), m.get("cmd", ""), m.firstActive, dmg, fmt.call(CD.adv_of(m, "block")), fmt.call(CD.adv_of(m, "hit")), T.cd, dm]

func clear_overlays() -> void:
	for c in blood_root.get_children(): c.queue_free()
	clear_name_card()
	hide_exec_hint()
	ann_big.modulate.a = 0.0
	ann_small.modulate.a = 0.0

func screen_blood(n: int, big: float) -> void:
	var vs := get_viewport().get_visible_rect().size
	for i in n:
		var s := (60.0 + randf() * 260.0) * big * (vs.x / 1400.0)
		var tr := TextureRect.new()
		tr.texture = Mats.T.splats[randi() % 4]
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.size = Vector2(s, s)
		tr.position = Vector2(randf() * vs.x - s / 2.0, randf() * vs.y * 0.85 - s / 2.0)
		tr.modulate = Color(1, 1, 1, 0.8 + randf() * 0.2)
		tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		blood_root.add_child(tr)
		var dr := ColorRect.new()
		dr.color = Color(0.35, 0, 0, 0.9)
		dr.size = Vector2(2.0 + randf() * 6.0 * big, 1)
		dr.position = tr.position + Vector2(s / 2.0 + randf_range(-s * 0.15, s * 0.15), s * 0.6)
		dr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		blood_root.add_child(dr)
		var tw := _rt_tween()
		tw.tween_property(dr, "size:y", randf_range(40, 160) * big, randf_range(1.5, 3.5))
		var tw2 := _rt_tween()
		tw2.tween_interval(2.5 + randf() * 2.0)
		tw2.tween_property(tr, "modulate:a", 0.0, 2.5)
		tw2.parallel().tween_property(dr, "modulate:a", 0.0, 2.5)
		tw2.tween_callback(func():
			tr.queue_free()
			dr.queue_free())

# ================================================================= portraits
func make_portraits() -> void:
	for id in CD.ROSTER:
		var vp := SubViewport.new()
		vp.size = Vector2i(240, 320)
		vp.own_world_3d = true
		vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		add_child(vp)
		var we := WorldEnvironment.new()
		var env := Environment.new()
		env.background_mode = Environment.BG_COLOR
		env.background_color = Color(0.06, 0.008, 0.012)
		env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		env.ambient_light_color = Color(0.35, 0.28, 0.32)
		env.ambient_light_energy = 0.6
		env.tonemap_mode = Environment.TONE_MAPPER_ACES
		we.environment = env
		vp.add_child(we)
		var k := DirectionalLight3D.new()
		k.light_energy = 1.6
		k.light_color = Color(1, 0.85, 0.75)
		vp.add_child(k)
		k.look_at_from_position(Vector3(3, 3, 2), Vector3.ZERO)
		var r := DirectionalLight3D.new()
		r.light_energy = 2.2
		r.light_color = Color(1, 0.17, 0.06)
		vp.add_child(r)
		r.look_at_from_position(Vector3(-3, 1, -2), Vector3.ZERO)
		var D = CD.get_def(id)
		var rig = Rig.new(D)
		vp.add_child(rig.root)
		rig.root.scale = Vector3.ONE * D.scale
		rig.update(D.S.guard)
		var cam := Camera3D.new()
		cam.fov = 28.0
		vp.add_child(cam)
		await get_tree().process_frame
		for i in 30: rig.secondary(1.0 / 60.0)
		var h: Vector3 = rig.joint_world("head")
		var sc: float = D.scale
		cam.look_at_from_position(h + Vector3(1.0, 0.1, 0.6) * sc, h + Vector3(0.0, 0.0, 0.0), Vector3.UP)
		await RenderingServer.frame_post_draw
		await RenderingServer.frame_post_draw
		var img := vp.get_texture().get_image()
		portraits[id] = ImageTexture.create_from_image(img)
		vp.queue_free()

# ================================================================= menus
func hide_menu() -> void:
	for c in menu.get_children(): c.queue_free()
	menu.mouse_filter = Control.MOUSE_FILTER_IGNORE
	back_fn = null
	custom_key = null

func _screen(dim := 0.55) -> Control:
	hide_menu()
	menu.mouse_filter = Control.MOUSE_FILTER_STOP
	var s := Control.new()
	s.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	menu.add_child(s)
	if dim > 0.0:
		var bg := ColorRect.new()
		bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		bg.color = Color(0, 0, 0, dim)
		bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
		s.add_child(bg)
	return s

func _vlist(parent: Control, items: Array, top := 0.4) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.anchor_left = 0.5
	v.anchor_right = 0.5
	v.anchor_top = top
	v.offset_left = -230
	v.offset_right = 230
	v.add_theme_constant_override("separation", 8)
	parent.add_child(v)
	for it in items:
		var b := Button.new()
		b.text = it[0]
		b.add_theme_font_size_override("font_size", 24)
		b.custom_minimum_size = Vector2(0, 62)
		b.focus_mode = Control.FOCUS_ALL
		var en := _label(b, it[1], Mats.font_latin, 11, Color(0.63, 0.54, 0.38))
		en.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
		en.offset_top = -17
		en.offset_bottom = -3
		en.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		var fn: Callable = it[2]
		b.pressed.connect(func():
			SFX.play("block", 0.25)
			fn.call())
		v.add_child(b)
	if v.get_child_count() > 0:
		(v.get_child(0) as Button).call_deferred("grab_focus")
	return v

func _unhandled_input(event: InputEvent) -> void:
	if custom_key != null and event.is_pressed() and not event.is_echo():
		if custom_key.call(event): get_viewport().set_input_as_handled()
		return
	if back_fn != null and event.is_action_pressed("ui_cancel"):
		back_fn.call()
		get_viewport().set_input_as_handled()

func show_title() -> void:
	G.f = []
	G.set_view([])
	G.phase = "menu"
	G.cam.mode = "menu"
	hide_hud()
	SFX.start_music("menu")
	var s := _screen(0.2)
	var lg := _logo(s, 130)
	lg.offset_top = -90
	var sub := _label(s, "طقوس الدم", Mats.font_ar, 40, GOLD)
	sub.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	sub.offset_top = 40
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_outline(sub, Color.BLACK, 6)
	var pr := _label(s, "المس الشاشة أو اضغط أي زر", Mats.font_ar, 28, Color.WHITE)
	pr.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	pr.offset_top = 260
	pr.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	pr.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_outline(pr, Color(0.5, 0, 0), 8)
	var tw := pr.create_tween().set_loops()
	tw.tween_property(pr, "modulate:a", 0.25, 0.6)
	tw.tween_property(pr, "modulate:a", 1.0, 0.6)
	var ft := _label(s, "جميع الشخصيات والعالم من تصميم أصلي", Mats.font_ar, 14, Color(0.6, 0.5, 0.45))
	ft.anchor_top = 1.0; ft.anchor_bottom = 1.0; ft.anchor_left = 0.0; ft.anchor_right = 1.0
	ft.offset_top = -34
	ft.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	custom_key = func(e):
		if e is InputEventKey or e is InputEventJoypadButton or e is InputEventMouseButton or e is InputEventScreenTouch:
			SFX.play("bell", 0.7)
			show_main()
			return true
		return false

func show_main() -> void:
	G.f = []
	G.set_view([])
	G.phase = "menu"
	G.cam.mode = "menu"
	hide_hud()
	SFX.start_music("menu")
	var s := _screen(0.35)
	var lg := _logo(s, 84)
	lg.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	lg.offset_top = 30
	lg.offset_bottom = 140
	_vlist(s, [
		["قتال ضد الحاسوب", "ARCADE · VS CPU", func(): show_select("cpu")],
		["التدريب", "TRAINING", func(): show_select("training")],
		["لاعب ضد لاعب", "VERSUS · KEYBOARD / GAMEPADS", func(): show_select("2p")],
		["قائمة الحركات", "MOVE LIST", func(): show_moves(show_main, "kharos")],
		["التحكم وآليات القتال", "CONTROLS", func(): show_controls(show_main)],
		["الإعدادات", "SETTINGS", func(): show_settings(show_main)],
	], 0.27)
	back_fn = show_title

# ---------------------------------------------------------------- character select
func show_select(mode: String) -> void:
	G.cam.mode = "select"
	G.f = []
	cs = {mode = mode, cur = [0, 3], lock = [false, false], step = 0}
	var s := _screen(0.0)
	var grad := ColorRect.new()
	grad.anchor_top = 0.62; grad.anchor_bottom = 1.0; grad.anchor_right = 1.0
	grad.color = Color(0, 0, 0, 0.6)
	grad.mouse_filter = Control.MOUSE_FILTER_IGNORE
	s.add_child(grad)
	var ttl := _label(s, "اختر محاربك", Mats.font_ar, 34, GOLD)
	ttl.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	ttl.offset_top = 10
	ttl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_outline(ttl, Color.BLACK, 8)
	ttl.name = "ttl"
	var hb := HBoxContainer.new()
	hb.name = "cards"
	hb.anchor_left = 0.5; hb.anchor_right = 0.5; hb.anchor_top = 1.0; hb.anchor_bottom = 1.0
	hb.offset_left = -330; hb.offset_right = 330; hb.offset_top = -200; hb.offset_bottom = -24
	hb.add_theme_constant_override("separation", 14)
	hb.layout_direction = Control.LAYOUT_DIRECTION_LTR
	s.add_child(hb)
	for i in CD.ROSTER.size():
		var id: String = CD.ROSTER[i]
		var card := TextureButton.new()
		card.texture_normal = portraits.get(id)
		card.ignore_texture_size = true
		card.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_COVERED
		card.custom_minimum_size = Vector2(150, 176)
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var nm := _label(card, D_name(id), Mats.font_latin, 16, BONE)
		nm.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
		nm.offset_top = -26
		nm.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_outline(nm, Color.BLACK, 6)
		var idx = i
		card.pressed.connect(func(): _card_tap(idx))
		hb.add_child(card)
	for side in 2:
		var inf := Control.new()
		inf.name = "info%d" % side
		inf.anchor_left = 0.015 if side == 0 else 0.705
		inf.anchor_right = 0.295 if side == 0 else 0.985
		inf.anchor_top = 0.1
		inf.anchor_bottom = 0.62
		inf.mouse_filter = Control.MOUSE_FILTER_IGNORE
		s.add_child(inf)
	custom_key = func(e): return _select_key(e)
	back_fn = show_main
	_refresh_select()

func D_name(id: String) -> String:
	return CD.get_def(id).name

func _card_tap(i: int) -> void:
	var side := 0
	if cs.mode != "2p" and cs.step == 1: side = 1
	if cs.mode == "2p" and cs.lock[0]: side = 1
	if cs.cur[side] == i: _confirm(side)
	else:
		cs.cur[side] = i
		_refresh_select()

func _select_key(e: InputEvent) -> bool:
	var two: bool = cs.mode == "2p"
	var act := 1 if (not two and cs.step == 1) else 0
	var mv := func(side: int, d: int):
		if cs.lock[side]: return
		cs.cur[side] = (cs.cur[side] + d + 4) % 4
		SFX.play("whoosh", 0.2)
		_refresh_select()
	if two:
		if e.is_action_pressed("p1_L"): mv.call(0, -1)
		elif e.is_action_pressed("p1_R"): mv.call(0, 1)
		elif e.is_action_pressed("p2_L"): mv.call(1, -1)
		elif e.is_action_pressed("p2_R"): mv.call(1, 1)
		elif e.is_action_pressed("p1_1") or e.is_action_pressed("p1_3"): _confirm(0)
		elif e.is_action_pressed("p2_1") or e.is_action_pressed("p2_ST"): _confirm(1)
		elif e.is_action_pressed("ui_cancel"): show_main()
		else: return false
		return true
	if e.is_action_pressed("ui_left") or e.is_action_pressed("p1_L"): mv.call(act, -1)
	elif e.is_action_pressed("ui_right") or e.is_action_pressed("p1_R"): mv.call(act, 1)
	elif e.is_action_pressed("ui_accept") or e.is_action_pressed("p1_1"): _confirm(act)
	elif e.is_action_pressed("ui_cancel"):
		if cs.step == 1:
			cs.step = 0; cs.lock[0] = false
			_refresh_select()
		else: show_main()
	else: return false
	return true

func _confirm(side: int) -> void:
	if cs.lock[side]: return
	cs.lock[side] = true
	SFX.play("boom", 0.5)
	for F in G.view:
		if F.idx == side:
			VFX.ring(F.rig.joint_world("chest"), Color(0.3, 0.8, 2) if side == 1 else Color(2, 0.3, 0.2), 2.5, 0.4)
			SFX.voice(F.def.id, "atk", 1.0)
			F.play_clip(PZ.clip([[0, F.def.S.guard], [12, CD.victory(F.def.id, F.def.S), "out"], [50, CD.victory(F.def.id, F.def.S)], [70, F.def.S.guard]]), 6.0)
	if cs.mode == "2p":
		_refresh_select()
		if cs.lock[0] and cs.lock[1]: _later(0.9, func(): G.start_match(CD.ROSTER[cs.cur[0]], CD.ROSTER[cs.cur[1]], "2p"))
		return
	if cs.step == 0:
		cs.step = 1
		cs.lock[1] = false
		_refresh_select()
		return
	_refresh_select()
	if cs.mode == "training": _later(0.7, func(): G.start_match(CD.ROSTER[cs.cur[0]], CD.ROSTER[cs.cur[1]], "training"))
	else: _later(0.6, show_difficulty)

func _later(t: float, fn: Callable) -> void:
	get_tree().create_timer(t).timeout.connect(fn)

func _refresh_select() -> void:
	if menu.get_child_count() == 0: return
	var s: Control = menu.get_child(0)
	if not s.has_node("cards"): return
	var cards: HBoxContainer = s.get_node("cards")
	var show2: bool = cs.mode == "2p" or cs.step >= 1
	for i in cards.get_child_count():
		var c: TextureButton = cards.get_child(i)
		var sel1: bool = cs.cur[0] == i
		var sel2: bool = show2 and cs.cur[1] == i
		c.modulate = Color(1, 1, 1) if (sel1 or sel2) else Color(0.55, 0.5, 0.5)
		c.self_modulate = Color(1.15, 0.85, 0.85) if sel1 and not sel2 else (Color(0.85, 0.95, 1.2) if sel2 and not sel1 else Color.WHITE)
		c.scale = Vector2(1.06, 1.06) if (sel1 or sel2) else Vector2.ONE
		c.pivot_offset = c.size / 2.0
	var ttl: Label = s.get_node("ttl")
	ttl.text = ("اختر الدمية" if cs.mode == "training" else "اختر خصمك") if (cs.mode != "2p" and cs.step == 1) else "اختر محاربك"
	var want := [CD.ROSTER[cs.cur[0]], CD.ROSTER[cs.cur[1]] if show2 else ""]
	var nv := []
	for side in 2:
		var inf: Control = s.get_node("info%d" % side)
		for c in inf.get_children(): c.queue_free()
		var id: String = want[side]
		if id == "": continue
		var F = null
		for v in G.view:
			if v.idx == side and v.def.id == id and G.cache[side].get(id) == v: F = v
		if F == null:
			F = G.get_fighter(side, id)
			F.reset(1.25 if side == 1 else -1.25, -1 if side == 1 else 1)
			for i in 16: VFX.fire(Vector3(F.x + randf_range(-0.5, 0.5), 0, randf_range(-0.3, 0.3)), 1.4, Vector3(0, randf_range(1, 3), 0))
		nv.append(F)
		var D = CD.get_def(id)
		var al := HORIZONTAL_ALIGNMENT_LEFT if side == 0 else HORIZONTAL_ALIGNMENT_RIGHT
		var y := 0.0
		for row in [[D.name, Mats.font_title, 50, Color.WHITE], [D.title_ar + " · " + D.title, Mats.font_ar, 19, GOLD]]:
			var l := _label(inf, row[0], row[1], row[2], row[3])
			l.anchor_right = 1.0
			l.offset_top = y
			l.horizontal_alignment = al
			_outline(l, Color(0.4, 0, 0) if row[2] > 40 else Color.BLACK, 8)
			y += 64.0 if row[2] > 40 else 34.0
		var d := _label(inf, D.desc + "\n" + D.style, Mats.font_ar, 15, Color(0.88, 0.85, 0.82))
		d.anchor_right = 1.0
		d.offset_top = y
		d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		d.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		_outline(d, Color.BLACK, 5)
		var st: Dictionary = D.stats
		var yy := y + 110.0
		for row in [["القوة", st.power], ["السرعة", st.speed], ["المدى", st.range], ["الصعوبة", st.diff]]:
			var l := _label(inf, row[0], Mats.font_ar, 14, Color(0.75, 0.7, 0.65))
			l.offset_top = yy
			l.anchor_left = 0.75 if side == 0 else 0.0
			l.anchor_right = 1.0 if side == 0 else 0.25
			l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
			var bb := ColorRect.new()
			bb.color = Color(0.15, 0, 0)
			bb.anchor_left = 0.0 if side == 0 else 0.27
			bb.anchor_right = 0.73 if side == 0 else 1.0
			bb.offset_top = yy + 10
			bb.offset_bottom = yy + 16
			inf.add_child(bb)
			var fl := ColorRect.new()
			fl.color = Color(1, 0.25, 0.12)
			fl.anchor_bottom = 1.0
			fl.anchor_right = row[1] / 10.0
			bb.add_child(fl)
			yy += 24.0
		if cs.lock[side]:
			var r := _label(inf, "READY", Mats.font_latin, 22, Color(1, 0.33, 0.2))
			r.offset_top = yy + 6
			r.anchor_right = 1.0
			r.horizontal_alignment = al
	G.set_view(nv)

func show_difficulty() -> void:
	var s := _screen(0.5)
	var t := _label(s, "مستوى الصعوبة", Mats.font_ar, 40, GOLD)
	t.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	t.offset_top = 90
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var go := func(l: int): G.start_match(CD.ROSTER[cs.cur[0]], CD.ROSTER[cs.cur[1]], "cpu", l)
	var v := _vlist(s, [["مبتدئ", "NOVICE", func(): go.call(0)], ["محارب", "WARRIOR", func(): go.call(1)], ["جلّاد", "EXECUTIONER", func(): go.call(2)], ["كابوس", "NIGHTMARE", func(): go.call(3)]], 0.32)
	(v.get_child(clampi(G.cpu_lvl, 0, 3)) as Button).call_deferred("grab_focus")
	back_fn = func(): show_select("cpu")

func show_settings(back: Callable) -> void:
	var s := _screen(0.6)
	var t := _label(s, "الإعدادات", Mats.font_ar, 40, GOLD)
	t.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	t.offset_top = 70
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var st: Dictionary = G.settings
	var q: String = {low = "منخفضة", mid = "متوسطة", high = "عالية"}[st.quality]
	_vlist(s, [
		["جودة الرسوميات: " + q, "GRAPHICS", func():
			st.quality = {low = "mid", mid = "high", high = "low"}[st.quality]
			G.save_settings(); G.apply_quality(); show_settings(back)],
		["الموسيقى: %d%%" % roundi(st.music * 100), "MUSIC", func():
			st.music = 0.0 if st.music >= 0.95 else minf(1.0, st.music + 0.2)
			G.save_settings(); show_settings(back)],
		["المؤثرات: %d%%" % roundi(st.sfx * 100), "SOUND FX", func():
			st.sfx = 0.0 if st.sfx >= 0.95 else minf(1.0, st.sfx + 0.2)
			G.save_settings(); show_settings(back)],
		["صوت المعلّق: " + ("مفعّل" if st.voice else "معطّل"), "ANNOUNCER", func():
			st.voice = not st.voice
			G.save_settings(); show_settings(back)],
		["الاهتزاز: " + ("مفعّل" if st.haptics else "معطّل"), "HAPTICS", func():
			st.haptics = not st.haptics
			G.save_settings(); show_settings(back)],
		["رجوع", "BACK", back],
	], 0.2)
	back_fn = back

func _panel(s: Control) -> VBoxContainer:
	var p := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.03, 0.008, 0.008, 0.94)
	sb.border_color = Color(0.35, 0.23, 0.13)
	sb.set_border_width_all(1)
	sb.set_content_margin_all(18)
	p.add_theme_stylebox_override("panel", sb)
	p.anchor_left = 0.04; p.anchor_right = 0.96; p.anchor_top = 0.06; p.anchor_bottom = 0.94
	s.add_child(p)
	var sc := ScrollContainer.new()
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	p.add_child(sc)
	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.layout_direction = Control.LAYOUT_DIRECTION_RTL
	v.add_theme_constant_override("separation", 6)
	sc.add_child(v)
	var close := Button.new()
	close.text = "✕  رجوع"
	close.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	close.pressed.connect(func(): back_fn.call())
	v.add_child(close)
	close.call_deferred("grab_focus")
	return v

func _txt(v: Control, t: String, size := 17, col := BONE, font: Font = null) -> Label:
	var l := _label(v, t, font if font else Mats.font_ar, size, col)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	l.custom_minimum_size.x = 200
	return l

func show_controls(back: Callable) -> void:
	var s := _screen(0.6)
	back_fn = back
	var v := _panel(s)
	_txt(v, "التحكم", 30, GOLD)
	_txt(v, "اللمس (الهاتف): العصا الافتراضية يساراً للحركة. الأزرار يميناً: 1 لكمة أمامية · 2 لكمة خلفية · 3 ركلة أمامية · 4 ركلة خلفية · BL صد · TH مسكة · ✦ الغضب · II إيقاف.")
	_txt(v, "لوحة المفاتيح: W A S D للحركة · U / I / J / K = 1 / 2 / 3 / 4 · L أو Shift صد · O مسكة · Space الغضب · Esc أو P إيقاف. (اللاعب 2: الأسهم + Num4 Num5 Num1 Num2، Num6 صد، Num3 مسكة، Num0 غضب)")
	_txt(v, "يد التحكم: X / Y / A / B = 1 / 2 / 3 / 4 · RB أو LT صد · LB مسكة · RT الغضب · Start إيقاف.")
	_txt(v, "آليات القتال", 26, Color(1, 0.4, 0.3))
	for line in [
		"الصد: استمر على BL. الصد الواقف يوقف العالية والمتوسطة والعلوية، والصد المنخفض (↓ + BL) يوقف المنخفضة والمتوسطة. الحركات الخاصة تسبب ضرراً طفيفاً عند صدها.",
		"الاندفاع والتراجع: → → للاندفاع، ← ← للتراجع السريع (محصّن لحظياً ضد الضربات).",
		"المراوغة الجانبية: BL + ↑ تتفادى الضربات والمقذوفات، لكن يمكن مسكك أثناءها.",
		"الكومبوهات: اضغط أزرار السلسلة بالتتابع أثناء الحركة (مثل 1، 1، 2). السلاسل «القابلة للإلغاء» تُلغى بحركة خاصة عند الإصابة أو الصد.",
		"الحركات المعززة EX: نفّذ الحركة الخاصة مع الاستمرار على BL لاستهلاك شريط طاقة واحد ونسخة أقوى (دروع، تحصين، ضرر أكبر).",
		"الكاسر: أثناء تلقي كومبو اضغط → + BL لاستهلاك شريطين وكسر الكومبو.",
		"الغضب: عند امتلاء العداد بالكامل اضغط ✦: ضربة مدرعة تتحول إلى مشهد سينمائي مدمر عند الإصابة.",
		"الإفلات من المسكة: اضغط TH مباشرة عند الإمساك بك.",
		"COUNTER: إصابة الخصم أثناء انطلاق حركته (+15% ضرر). PUNISH: إصابته أثناء استرجاعه.",
		"الإعدام: بعد الفوز بالجولة الحاسمة يترنح الخصم: أدخل أمر الإعدام من المسافة الصحيحة.",
	]:
		_txt(v, "• " + line, 16)

func show_moves(back: Callable, cur: String) -> void:
	var s := _screen(0.6)
	back_fn = back
	var v := _panel(s)
	var tabs := HBoxContainer.new()
	tabs.layout_direction = Control.LAYOUT_DIRECTION_RTL
	v.add_child(tabs)
	for id in CD.ROSTER:
		var b := Button.new()
		b.text = CD.get_def(id).name
		b.add_theme_font_override("font", Mats.font_latin)
		b.add_theme_font_size_override("font_size", 16)
		if id == cur: b.add_theme_color_override("font_color", Color(1, 0.35, 0.25))
		var cid: String = id
		b.pressed.connect(func(): show_moves(back, cid))
		tabs.add_child(b)
	var D = CD.get_def(cur)
	var mv: Dictionary = D.mv
	_txt(v, "%s · %s · الصحة: %d" % [D.title_ar, D.style, D.hp], 15, Color(0.75, 0.7, 0.65))
	var fmt := func(x): return "—" if x == null else ("إسقاط" if typeof(x) == TYPE_STRING else ("+" if x > 0 else "") + str(x))
	var table := func(title: String, ids: Array, pros_override = null):
		_txt(v, title, 22, Color(1, 0.42, 0.31))
		var g := GridContainer.new()
		g.columns = 7
		g.layout_direction = Control.LAYOUT_DIRECTION_RTL
		g.add_theme_constant_override("h_separation", 14)
		v.add_child(g)
		for h in ["الحركة", "الأمر", "المستوى", "الضرر", "الانطلاق", "عند الصد", "المزايا / العيوب"]:
			_label(g, h, Mats.font_ar, 14, GOLD)
		for id in ids:
			if not mv.has(id): continue
			var m: Dictionary = mv[id]
			var dmg := 0
			for h in m.hits: dmg += h.dmg
			var lvl = "مقذوف" if m.get("proj", false) else (CD.LVL_AR.get(m.hits[0].lvl, "") if m.hits.size() > 0 else "")
			var cells := [m.get("ar", m.name), m.get("cmd", ""), lvl, ("سينمائي" if m.type == "super" else str(dmg)) if not m.get("proj", false) else "مقذوف", str(m.firstActive), fmt.call(CD.adv_of(m, "block"))]
			for c in cells:
				var l := _label(g, c, Mats.font_ar, 14, BONE)
				l.custom_minimum_size.x = 70
			var pc := _label(g, ("✔ " + m.get("pros", "") + "\n✘ " + m.get("cons", "")) if m.has("pros") else (pros_override if pros_override else ""), Mats.font_ar, 13, Color(0.75, 0.9, 0.65))
			pc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			pc.custom_minimum_size.x = 330
	table.call("الحركات الأساسية", ["1", "2", "3", "4", "d1", "d2", "d3", "d4", "f2", "b1", "b2", "b3", "f4", "j1", "j2", "j3", "j4", "throw", "bthrow"])
	var strings := []
	for k in mv:
		if mv[k].type == "string": strings.append(k)
	table.call("الكومبوهات (السلاسل)", strings)
	var sp := []
	for s2 in D.specials:
		sp.append(s2[0])
		sp.append(s2[0] + "EX")
	table.call("الحركات الخاصة (EX: + BL، تستهلك شريط طاقة واحداً)", sp, "✔ نسخة معززة: دروع/تحصين/ضرر أعلى\n✘ تستهلك شريط طاقة")
	table.call("الغضب · ضربة سينمائية", ["super"])
	_txt(v, "الإعدام", 22, Color(1, 0.42, 0.31))
	_txt(v, "«%s» (%s):   %s   — المسافة: %s. يُنفّذ عندما يترنح الخصم بعد عبارة END THEM." % [D.exec.ar, D.exec.name, D.exec.cmd, {close = "قريب", mid = "متوسط", far = "بعيد"}[D.exec.range]], 17)

func show_pause() -> void:
	var s := _screen(0.6)
	var t := _label(s, "إيقاف مؤقت", Mats.font_ar, 36, GOLD)
	t.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	t.offset_top = 14
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var me: String = G.f[0].def.id
	var resume := func(): G.toggle_pause()
	var items := [["استئناف", "RESUME", resume]]
	if G.training != null:
		var T: Dictionary = G.training
		var names := {stand = "واقف", block = "يصد كل شيء", crouch = "منحنٍ ويصد", jump = "يقفز", cpu = "ذكاء اصطناعي"}
		items.append(["الدمية: " + names[T.dummy], "TRAINING DUMMY", func():
			var order := ["stand", "block", "crouch", "jump", "cpu"]
			T.dummy = order[(order.find(T.dummy) + 1) % order.size()]
			G.f[1].ai.mode = T.dummy
			show_pause()])
	_vlist(s, items + [

		["قائمة الحركات", "MOVE LIST", func(): show_moves(func(): show_pause(), me)],
		["التحكم", "CONTROLS", func(): show_controls(func(): show_pause())],
		["إعادة المباراة", "RESTART", func():
			G.paused = false
			PhysicsServer3D.set_active(true)
			G.start_match(G.f[0].def.id, G.f[1].def.id, G.mode, G.cpu_lvl)],
		["اختيار الشخصيات", "CHARACTER SELECT", func():
			var m: String = G.mode
			G.quit_match()
			show_select(m)],
		["القائمة الرئيسية", "MAIN MENU", func():
			G.quit_match()
			show_main()],
	], 0.14)
	back_fn = resume

func show_post_match(_W) -> void:
	var s := _screen(0.0)
	var a: String = G.f[0].def.id
	var b: String = G.f[1].def.id
	var m: String = G.mode
	var l: int = G.cpu_lvl
	_vlist(s, [
		["إعادة المباراة", "REMATCH", func(): G.start_match(a, b, m, l)],
		["اختيار الشخصيات", "CHARACTER SELECT", func():
			G.quit_match()
			show_select(m)],
		["القائمة الرئيسية", "MAIN MENU", func():
			G.quit_match()
			show_main()],
	], 0.6)

# ================================================================= touch controls
class TouchPad extends Control:
	var stick_id := -1
	var stick_c := Vector2.ZERO
	var stick_p := Vector2.ZERO
	var btn_ids := {}
	const BTN := [["1", "لكمة"], ["2", "ثقيلة"], ["BL", "صد"], ["SP", "غضب"], ["3", "ركلة"], ["4", "ثقيلة"], ["TH", "مسكة"], ["ST", "إيقاف"]]

	func _layout() -> Array:
		var vs := get_viewport_rect().size
		var r := minf(vs.y * 0.085, 52.0)
		var out := []
		for i in BTN.size():
			if BTN[i][0] == "ST":
				out.append(["ST", Vector2(vs.x * 0.5, 104.0), 26.0, BTN[i][1]])
				continue
			var col := i % 4
			var row := i / 4
			out.append([BTN[i][0], Vector2(vs.x - (4 - col) * r * 2.25 + r * 0.2, vs.y - (2 - row) * r * 2.25 - r * 0.2), r, BTN[i][1]])
		return out

	func _input(e: InputEvent) -> void:
		if not visible: return
		var vs := get_viewport_rect().size
		if e is InputEventScreenTouch:
			if e.pressed:
				if e.position.x < vs.x * 0.4 and stick_id == -1:
					stick_id = e.index
					stick_c = e.position
					stick_p = e.position
					_stick()
				else:
					for b in _layout():
						if e.position.distance_to(b[1]) < b[2] * 1.15:
							if b[0] == "ST":
								G.toggle_pause()
							else:
								btn_ids[e.index] = b[0]
								G.touch[b[0]] = true
							break
			else:
				if e.index == stick_id:
					stick_id = -1
					for k in ["L", "R", "U", "D"]: G.touch[k] = false
				if btn_ids.has(e.index):
					G.touch[btn_ids[e.index]] = false
					btn_ids.erase(e.index)
			queue_redraw()
		elif e is InputEventScreenDrag and e.index == stick_id:
			stick_p = e.position
			_stick()
			queue_redraw()

	func _stick() -> void:
		var d := stick_p - stick_c
		var r := 60.0
		if d.length() > r:
			d = d.normalized() * r
		var n := d / r
		G.touch.L = n.x < -0.38
		G.touch.R = n.x > 0.38
		G.touch.U = n.y < -0.45
		G.touch.D = n.y > 0.45

	func _draw() -> void:
		var vs := get_viewport_rect().size
		var c := stick_c if stick_id != -1 else Vector2(vs.x * 0.12, vs.y * 0.74)
		draw_circle(c, 78.0, Color(0.3, 0.0, 0.0, 0.22))
		draw_arc(c, 78.0, 0, TAU, 40, Color(0.79, 0.64, 0.36, 0.35), 2.0)
		var kp := c + ((stick_p - stick_c).limit_length(60.0) if stick_id != -1 else Vector2.ZERO)
		draw_circle(kp, 30.0, Color(0.8, 0.15, 0.1, 0.5))
		var font: Font = Mats.font_latin
		var fa: Font = Mats.font_ar
		for b in _layout():
			var on: bool = G.touch.get(b[0], false)
			var col := Color(0.8, 0.12, 0.08, 0.75) if on else (Color(0.5, 0.15, 0.0, 0.5) if b[0] == "SP" else Color(0.18, 0.02, 0.02, 0.5))
			draw_circle(b[1], b[2], col)
			draw_arc(b[1], b[2], 0, TAU, 32, Color(0.79, 0.64, 0.36, 0.55), 2.0)
			var label: String = "II" if b[0] == "ST" else ("✦" if b[0] == "SP" else b[0])
			draw_string(font, b[1] + Vector2(-b[2], 2), label, HORIZONTAL_ALIGNMENT_CENTER, b[2] * 2.0, 22, Color.WHITE)
			if b[0] != "ST": draw_string(fa, b[1] + Vector2(-b[2], b[2] * 0.55), b[3], HORIZONTAL_ALIGNMENT_CENTER, b[2] * 2.0, 12, Color(0.86, 0.8, 0.75))

	func _process(_d: float) -> void:
		if visible: queue_redraw()
