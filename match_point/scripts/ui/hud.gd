class_name Hud
extends CanvasLayer
## واجهة المباراة: لوحة نتيجة بأسلوب البث التلفزيوني، نداءات الحكم، سرعة الإرسال، شريط التوقيت،
## لوحة تبديل الملعب مع الإحصاءات، مؤشر الرياح، وأزرار اللمس.

signal pause_pressed

var game: TennisMatch
var human: TennisPlayer
var pad: TouchControls
var qte: QteBar
var names := ["اللاعب", "الخصم"]
var colors := [Color.WHITE, Color.RED]

var _root: Control
var _board: Control
var _call: Label
var _sub: Label
var _feedback: Label
var _speed: Label
var _pressure: Label
var _hint: Label
var _stamina: Control
var _wind: Control
var _change: PanelContainer
var _change_box: VBoxContainer
var _call_t := 0.0
var _feedback_t := 0.0
var _speed_t := 0.0
var _hint_t := 0.0
var _change_t := 0.0
var _serve_hints := 0
var _font: Font
var _font_r: Font
var _clock := 0.0
var _clock_shown := -1
var _strip_base := ""
var _strip_base_col := Color(0.86, 0.30, 0.16)
var _strip_speed := ""
var _strip_a := 0.0


func _ready() -> void:
	layer = 5
	_font = UiKit.font_bold()
	_font_r = UiKit.font_reg()
	_root = Control.new()
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.layout_direction = Control.LAYOUT_DIRECTION_LTR
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)

	pad = TouchControls.new()
	_root.add_child(pad)

	qte = QteBar.new()
	_root.add_child(qte)

	_board = Control.new()
	_board.position = Vector2(14, 10)
	_board.size = Vector2(580, 116)
	_board.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_board.draw.connect(_draw_board)
	_root.add_child(_board)

	_stamina = Control.new()
	_stamina.position = Vector2(16, 128)
	_stamina.size = Vector2(260, 14)
	_stamina.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_stamina.draw.connect(_draw_stamina)
	_root.add_child(_stamina)

	_wind = Control.new()
	_wind.anchor_left = 1.0
	_wind.anchor_right = 1.0
	_wind.offset_left = -190
	_wind.offset_right = -96
	_wind.offset_top = 64
	_wind.offset_bottom = 128
	_wind.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_wind.draw.connect(_draw_wind)
	_root.add_child(_wind)

	_call = _centered(UiKit.label("", 54, Color(1, 1, 1)), 0.20)
	_outline(_call, 10)
	_sub = _centered(UiKit.label("", 30, UiKit.ACCENT), 0.31)
	_outline(_sub, 8)
	_pressure = _centered(UiKit.label("", 26, Color(1.0, 0.55, 0.35)), 0.105)
	_outline(_pressure, 8)
	_feedback = _centered(UiKit.label("", 28, Color(1, 1, 1)), 0.62)
	_outline(_feedback, 8)
	_hint = _centered(UiKit.label("", 21, Color(1, 1, 1, 0.92), false), 0.93)
	_outline(_hint, 6)

	_speed = UiKit.label("", 26, UiKit.ACCENT)
	_speed.anchor_left = 1.0
	_speed.anchor_right = 1.0
	_speed.offset_left = -330
	_speed.offset_right = -96
	_speed.offset_top = 16
	_speed.offset_bottom = 60
	_speed.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_outline(_speed, 8)
	_root.add_child(_speed)

	var pb := UiKit.button("II", 24)
	pb.anchor_left = 1.0
	pb.anchor_right = 1.0
	pb.offset_left = -78
	pb.offset_right = -16
	pb.offset_top = 14
	pb.offset_bottom = 72
	pb.pressed.connect(func() -> void: pause_pressed.emit())
	_root.add_child(pb)

	var cc := CenterContainer.new()
	cc.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	cc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(cc)
	_change = UiKit.panel(Color(0.03, 0.06, 0.12, 0.92), 18)
	_change.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_change.visible = false
	cc.add_child(_change)
	var m := MarginContainer.new()
	for k in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		m.add_theme_constant_override(k, 16)
	_change.add_child(m)
	_change_box = VBoxContainer.new()
	_change_box.add_theme_constant_override("separation", 4)
	m.add_child(_change_box)


func _outline(l: Label, s: int) -> void:
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	l.add_theme_constant_override("outline_size", s)


func _centered(l: Label, y: float) -> Label:
	l.anchor_left = 0.0
	l.anchor_right = 1.0
	l.anchor_top = y
	l.anchor_bottom = y
	l.offset_top = -40
	l.offset_bottom = 40
	l.modulate.a = 0.0
	_root.add_child(l)
	return l


func bind(p_game: TennisMatch, p_human: TennisPlayer, p_names: Array) -> void:
	game = p_game
	human = p_human
	names = p_names
	for i in 2:
		colors[i] = (game.players[i].profile["look"] as Dictionary).get("shirt", Color.WHITE)
	game.score_changed.connect(func() -> void: _board.queue_redraw())
	game.call_made.connect(_on_call)
	game.serve_speed.connect(_on_serve_speed)
	game.point_started.connect(_on_point_started)
	game.changeover.connect(_on_changeover)
	if human != null:
		human.swing_feedback.connect(_on_feedback)
	_board.queue_redraw()


func show_hint(text: String, secs: float = 4.0) -> void:
	_hint.text = text
	_hint.modulate.a = 1.0
	_hint_t = secs


func _on_point_started(srv: int, second: bool) -> void:
	_board.queue_redraw()
	_wind.queue_redraw()
	var pr := game.rules.pressure()
	var txt := ""
	match pr:
		"match": txt = "نقطة المباراة"
		"set": txt = "نقطة المجموعة"
		"break": txt = "نقطة كسر الإرسال"
	_strip_base = txt
	_strip_base_col = Color(0.86, 0.30, 0.16) if pr != "" else Color(0.16, 0.22, 0.36)
	if second:
		_strip_base = "الإرسال الثاني" if txt == "" else txt + "  •  الإرسال الثاني"
		txt = "الإرسال الثاني" if txt == "" else txt + " — الإرسال الثاني"
	_strip_speed = ""
	_pressure.text = txt
	_pressure.modulate.a = 1.0 if txt != "" else 0.0
	if human != null and srv == human.idx and human.is_human and _serve_hints < 3:
		_serve_hints += 1
		show_hint("حرّك العصا لتغيير موقفك • اضغط زر الإرسال ثم وجّه مؤشر السقوط بالعصا وأفلِت عند الأخضر", 5.0)


func _on_serve_speed(kmh: float, _p: int) -> void:
	_strip_speed = "سرعة الإرسال  %d كم/س" % int(round(kmh))
	_speed_t = 3.4
	_board.queue_redraw()


func _on_feedback(kind: String, _q: float) -> void:
	var map := {"perfect": ["توقيت مثالي!", Color(0.35, 1.0, 0.5)], "good": ["توقيت جيد", Color(0.95, 0.88, 0.3)],
		"poor": ["توقيت ضعيف", Color(1.0, 0.55, 0.35)], "late": ["متأخر جداً!", Color(1.0, 0.4, 0.35)],
		"miss": ["لم تُصب الكرة", Color(1.0, 0.4, 0.4)], "too_early": ["أفلَتَّ قبل اقتراب الكرة", Color(1.0, 0.7, 0.4)]}
	if not map.has(kind) or kind in ["perfect", "good", "poor", "late"]:
		return     # جودة التوقيت تظهر الآن فوق اللاعب على شريط التوقيت نفسه
	_feedback.text = map[kind][0]
	_feedback.add_theme_color_override("font_color", map[kind][1])
	_feedback.modulate.a = 1.0
	_feedback_t = 0.9


## إعلان النتيجة بطريقة حكم الكرسي (نتيجة المرسل أولاً)
func _score_call(ev: Dictionary, w: int) -> String:
	var r := game.rules
	if ev["match"]:
		return "شوط ومجموعة ومباراة — " + names[w]
	if ev["set"]:
		var h: Array = r.set_history[r.set_history.size() - 1]
		return "شوط ومجموعة — %s  (%d–%d)" % [names[w], h[w], h[1 - w]]
	if ev["game"]:
		var g := "شوط — %s   %d–%d" % [names[w], r.games[w], r.games[1 - w]]
		if ev["tiebreak_start"]:
			g += "   • شوط فاصل"
		return g
	if r.tiebreak:
		var s := r.current_server()
		return "%d–%d" % [r.points[s], r.points[1 - s]]
	if r.is_deuce():
		return "تعادل"
	if r.advantage() >= 0:
		return "أفضلية — " + names[r.advantage()]
	var s2 := r.current_server()
	var a := r.point_label(s2)
	var b := r.point_label(1 - s2)
	if a == b:
		return "%s للجميع" % a
	return "%s–%s" % [a, b]


func _on_call(kind: String, data: Dictionary) -> void:
	var main_txt := ""
	var sub_txt := ""
	match kind:
		"fault":
			main_txt = "خطأ"
			sub_txt = "في الشبكة" if data.get("net", false) else "الإرسال خارج المربع"
		"let":
			main_txt = "إعادة"
			sub_txt = "الكرة لمست الشبكة"
		"double_fault": main_txt = "خطأ مزدوج"
		"out": main_txt = "خارج!"
		"net": main_txt = "في الشبكة"
		"ace": main_txt = "إرسال ساحق!"
		"winner": main_txt = "ضربة فائزة!"
		"body": main_txt = "لمست اللاعب!"
		_: return
	if data.has("ev"):
		var ev: Dictionary = data["ev"]
		var w: int = data["winner"]
		sub_txt = _score_call(ev, w)
		# بعد نهاية الشوط ينتقل الإرسال، فمرسل الشوط المنتهي هو "الآخر" بالنسبة للمرسل الحالي
		var tb_set: bool = ev["set"] and int((game.rules.set_history[game.rules.set_history.size() - 1] as Array)[2]) >= 0
		if ev["game"] and not ev["match"] and not tb_set and w == game.rules.server:
			main_txt += "  • كسر إرسال!"
	_call.text = main_txt
	_sub.text = sub_txt
	_call.modulate.a = 1.0
	_sub.modulate.a = 1.0
	_call_t = 2.3
	_pressure.modulate.a = 0.0


func _on_changeover(info: Dictionary) -> void:
	for c in _change_box.get_children():
		c.queue_free()
	var r: MatchRules = info["rules"]
	var st: Array = info["stats"]
	_change_box.add_child(UiKit.label("تبديل الملعب", 26, UiKit.ACCENT))
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 26)
	var sets_txt := ["", ""]
	for h in r.set_history:
		for i in 2:
			sets_txt[i] += str(h[i]) + "  "
	var rows := [[names[0], "", names[1]],
		[sets_txt[0] + "[" + str(r.games[0]) + "]", "النتيجة", sets_txt[1] + "[" + str(r.games[1]) + "]"],
		[str(st[0]["aces"]), "إرسالات ساحقة", str(st[1]["aces"])],
		[str(st[0]["double_faults"]), "أخطاء مزدوجة", str(st[1]["double_faults"])],
		[str(st[0]["winners"]), "ضربات فائزة", str(st[1]["winners"])],
		[str(st[0]["unforced"]), "أخطاء غير مجبرة", str(st[1]["unforced"])],
		["%d%%" % int(100.0 * st[0]["first_in"] / maxf(st[0]["first_total"], 1)), "الإرسال الأول", "%d%%" % int(100.0 * st[1]["first_in"] / maxf(st[1]["first_total"], 1))],
		["%d/%d" % [st[0]["bp_won"], st[0]["bp_total"]], "نقاط كسر الإرسال", "%d/%d" % [st[1]["bp_won"], st[1]["bp_total"]]]]
	for i in rows.size():
		for j in 3:
			var l := UiKit.label(rows[i][j], 20 if i == 0 else 18, UiKit.ACCENT if i == 0 else (UiKit.MUTED if j == 1 else UiKit.TEXT), j != 1 or i == 0)
			l.custom_minimum_size = Vector2(180 if j != 1 else 200, 0)
			grid.add_child(l)
	_change_box.add_child(grid)
	_change.visible = true
	_change.modulate.a = 1.0
	_change_t = 4.2


func _process(dt: float) -> void:
	_call_t -= dt
	if _call_t < 0.0:
		_call.modulate.a = maxf(_call.modulate.a - dt * 3.0, 0.0)
		_sub.modulate.a = _call.modulate.a
	_feedback_t -= dt
	if _feedback_t < 0.0:
		_feedback.modulate.a = maxf(_feedback.modulate.a - dt * 4.0, 0.0)
	_speed_t -= dt
	if _speed_t < 0.0 and _strip_speed != "":
		_strip_speed = ""
		_board.queue_redraw()
	# ساعة المباراة وشريط المعلومات أسفل لوحة النتيجة
	if game != null and game.phase != TennisMatch.Phase.IDLE and game.phase != TennisMatch.Phase.MATCH_OVER:
		_clock += dt
		if int(_clock / 60.0) != _clock_shown:
			_clock_shown = int(_clock / 60.0)
			_board.queue_redraw()
		if game.phase == TennisMatch.Phase.POINT_OVER and _strip_base != "":
			_strip_base = ""
			_board.queue_redraw()
	var want_a := 1.0 if (_strip_speed != "" or _strip_base != "") else 0.0
	if not is_equal_approx(_strip_a, want_a):
		_strip_a = move_toward(_strip_a, want_a, dt * 5.0)
		_board.queue_redraw()
	_hint_t -= dt
	if _hint_t < 0.0:
		_hint.modulate.a = maxf(_hint.modulate.a - dt * 2.0, 0.0)
	if _change_t > 0.0:
		_change_t -= dt
		if _change_t < 0.5:
			_change.modulate.a = maxf(_change_t / 0.5, 0.0)
		if _change_t <= 0.0:
			_change.visible = false
	_update_gauges()


## ربط المؤشرات بجسم اللاعب على الشاشة
func _update_gauges() -> void:
	if human == null or game == null:
		return
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var hp := human.global_position
	if cam.is_position_behind(hp):
		return
	qte.anchor_head = cam.unproject_position(hp + Vector3(0, 2.25, 0))
	qte.anchor_feet = cam.unproject_position(hp)
	qte.anchor_side = cam.unproject_position(hp + Vector3(0, 1.1, 0)) + Vector2(52.0, 0.0)
	qte.stamina = human.stamina
	qte.show_stamina = game.phase != TennisMatch.Phase.MATCH_OVER
	var st := human.state
	qte.charging = st == TennisPlayer.St.PREP or (st == TennisPlayer.St.SERVE_TOSS)
	qte.charge = human.charge


func _draw_stamina() -> void:
	if true:
		return     # اللياقة تُعرض الآن تحت قدمي اللاعب
	var w := 200.0
	_stamina.draw_string(_font_r, Vector2(w + 8, 11), "اللياقة", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(1, 1, 1, 0.7))
	_stamina.draw_rect(Rect2(0, 2, w, 7), Color(0, 0, 0, 0.45))
	var s := human.stamina
	var c := Color(0.35, 0.9, 0.5).lerp(Color(1.0, 0.4, 0.3), 1.0 - s)
	_stamina.draw_rect(Rect2(0, 2, w * s, 7), c)


func _draw_wind() -> void:
	var w := BallPhysics.wind
	if w.length() < 0.1 or human == null:
		return
	var s := float(human.side)
	var dir := Vector2(w.x * s, w.z * s).normalized()
	var c := Vector2(30, 28)
	_wind.draw_circle(c, 26, Color(0.03, 0.06, 0.12, 0.75))
	var tip := c + dir * 19.0
	var tail := c - dir * 15.0
	_wind.draw_line(tail, tip, Color(0.75, 0.9, 1.0), 4.0, true)
	var nrm := Vector2(-dir.y, dir.x)
	_wind.draw_colored_polygon(PackedVector2Array([tip + dir * 4.0, tip - dir * 8.0 + nrm * 7.0, tip - dir * 8.0 - nrm * 7.0]), Color(0.75, 0.9, 1.0))
	_wind.draw_string(_font, Vector2(0, 74), "رياح %d كم/س" % int(round(w.length() * 3.6)), HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(0.85, 0.93, 1.0))


func _draw_board() -> void:
	# لوحة نتيجة بأسلوب البث التلفزيوني: شريط علوي للبطولة والوقت، صفّان للاعبين
	# (علم اللون، الاسم، كرة الإرسال، المجموعات السابقة، أشواط المجموعة الحالية، نقاط الشوط)، وشريط معلومات سفلي.
	if game == null:
		return
	var r := game.rules
	var b := _board
	var hist: Array = r.set_history
	var tab_h := 21.0
	var row_h := 31.0
	var flag_w := 6.0
	var name_w := 170.0
	var srv_w := 20.0
	var col_w := 27.0
	var games_w := 31.0
	var pts_w := 46.0
	var x_sets := flag_w + name_w + srv_w
	var x_games := x_sets + col_w * hist.size()
	var x_pts := x_games + games_w
	var total_w := (x_pts + pts_w) if not r.finished else x_games
	var dark := Color(0.035, 0.045, 0.08, 0.95)
	var ink := Color(0.05, 0.08, 0.12)
	# --- الشريط العلوي ---
	b.draw_rect(Rect2(0, 0, total_w, tab_h), Color(0.07, 0.12, 0.27, 0.96))
	b.draw_rect(Rect2(0, 0, 30, tab_h), UiKit.ACCENT)
	b.draw_string(_font, Vector2(0, 16), "MP", HORIZONTAL_ALIGNMENT_CENTER, 30, 13, ink)
	var head := "شوط فاصل" if r.tiebreak else ("انتهت المباراة" if r.finished else "المجموعة %d" % (hist.size() + 1))
	b.draw_string(_font, Vector2(36, 16), head, HORIZONTAL_ALIGNMENT_LEFT, total_w - 96, 13, Color(1, 1, 1, 0.95))
	var mins := int(_clock / 60.0)
	b.draw_string(_font_r, Vector2(total_w - 60, 16), "%d:%02d" % [mins / 60, mins % 60], HORIZONTAL_ALIGNMENT_RIGHT, 54, 13, Color(1, 1, 1, 0.78))
	b.draw_rect(Rect2(0, tab_h - 2, total_w, 2), UiKit.ACCENT)
	# --- صفّا اللاعبين ---
	var srv := r.current_server()
	for i in 2:
		var y := tab_h + i * row_h
		b.draw_rect(Rect2(0, y, total_w, row_h), dark)
		b.draw_rect(Rect2(0, y, total_w, row_h * 0.5), Color(1, 1, 1, 0.035))
		if i == 1:
			b.draw_rect(Rect2(0, y, total_w, 1), Color(1, 1, 1, 0.14))
		b.draw_rect(Rect2(0, y, flag_w, row_h), colors[i])
		b.draw_string(_font, Vector2(flag_w + 6, y + 22), names[i], HORIZONTAL_ALIGNMENT_RIGHT, name_w - 12, 17, Color(1, 1, 1))
		if i == srv and not r.finished:
			var bc := Vector2(flag_w + name_w + srv_w * 0.5, y + row_h * 0.5)
			b.draw_circle(bc, 5.0, UiKit.ACCENT)
			b.draw_arc(bc + Vector2(-5.5, 0), 5.0, -0.7, 0.7, 6, Color(1, 1, 1, 0.75), 1.0, true)
		var x := x_sets
		for h in hist:
			var won: bool = int(h[i]) > int(h[1 - i])
			b.draw_string(_font, Vector2(x, y + 22), str(h[i]), HORIZONTAL_ALIGNMENT_CENTER, col_w, 17, Color(1, 1, 1, 1.0 if won else 0.48))
			if int(h[2]) >= 0 and not won:
				b.draw_string(_font_r, Vector2(x + col_w - 9, y + 12), str(h[2]), HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(1, 1, 1, 0.6))
			x += col_w
		if not r.finished:
			b.draw_rect(Rect2(x_games, y, games_w, row_h), Color(1, 1, 1, 0.13))
			b.draw_string(_font, Vector2(x_games, y + 22), str(r.games[i]), HORIZONTAL_ALIGNMENT_CENTER, games_w, 18, Color(1, 1, 1))
			b.draw_rect(Rect2(x_pts, y, pts_w, row_h), UiKit.ACCENT)
			if i == 1:
				b.draw_rect(Rect2(x_pts, y, pts_w, 1), Color(0, 0, 0, 0.22))
			b.draw_string(_font, Vector2(x_pts, y + 22), r.point_label(i), HORIZONTAL_ALIGNMENT_CENTER, pts_w, 17, ink)
	# --- شريط المعلومات السفلي (نقطة كسر/مجموعة/مباراة، الإرسال الثاني، سرعة الإرسال) ---
	if _strip_a > 0.01:
		var txt := _strip_speed if _strip_speed != "" else _strip_base
		if txt != "":
			var y2 := tab_h + row_h * 2.0
			var sc := Color(0.07, 0.12, 0.27) if _strip_speed != "" else _strip_base_col
			b.draw_rect(Rect2(0, y2, total_w, 21.0 * _strip_a), Color(sc.r, sc.g, sc.b, 0.96 * _strip_a))
			if _strip_a > 0.7:
				b.draw_string(_font, Vector2(6, y2 + 16), txt, HORIZONTAL_ALIGNMENT_CENTER, total_w - 12, 13, UiKit.ACCENT if _strip_speed != "" else Color(1, 1, 1))
