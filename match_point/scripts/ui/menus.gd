class_name Menus
extends CanvasLayer
## القوائم: الرئيسية، إعداد المباراة، طريقة اللعب، الإعدادات، الإيقاف المؤقت، ونتيجة المباراة.

signal start_requested
signal resume_requested
signal restart_requested
signal quit_requested
signal settings_changed

var _root: Control
var _dim: ColorRect
var _panel: PanelContainer
var _box: VBoxContainer
var _back_to := ""
var current := ""


func _ready() -> void:
	layer = 10
	process_mode = Node.PROCESS_MODE_ALWAYS
	_root = Control.new()
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.layout_direction = Control.LAYOUT_DIRECTION_LTR
	add_child(_root)
	_dim = ColorRect.new()
	_dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_dim.color = Color(0.01, 0.03, 0.07, 0.55)
	_root.add_child(_dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.add_child(center)
	_panel = UiKit.panel(UiKit.PANEL_SOLID, 22)
	center.add_child(_panel)
	var margin := MarginContainer.new()
	for m in ["margin_left", "margin_right"]:
		margin.add_theme_constant_override(m, 22)
	for m in ["margin_top", "margin_bottom"]:
		margin.add_theme_constant_override(m, 12)
	_panel.add_child(margin)
	_box = VBoxContainer.new()
	_box.add_theme_constant_override("separation", 10)
	margin.add_child(_box)
	hide_all()


func hide_all() -> void:
	_root.visible = false
	current = ""


func _open(id: String, min_w: float = 560.0) -> void:
	for c in _box.get_children():
		_box.remove_child(c)
		c.queue_free()
	_root.visible = true
	_panel.custom_minimum_size = Vector2(min_w, 0)
	current = id


func _title(text: String, size: int = 34) -> void:
	_box.add_child(UiKit.label(text, size, UiKit.TEXT))


func _btn(text: String, cb: Callable, primary: bool = false) -> Button:
	var b := UiKit.button(text, 24, primary)
	b.pressed.connect(cb)
	_box.add_child(b)
	return b


func _row_buttons(items: Array) -> void:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 10)
	for it in items:
		var b := UiKit.button(it[0], 22, it.size() > 2 and it[2])
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.pressed.connect(it[1])
		h.add_child(b)
	_box.add_child(h)


## صف خيارات: عنوان + أزرار اختيار
func _option(title: String, key: String, labels: Array, values: Array, reopen: Callable) -> void:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 6)
	var cur: Variant = Settings.get_v(key)
	for i in labels.size():
		var sel: bool = typeof(cur) == typeof(values[i]) and cur == values[i]
		if typeof(cur) == TYPE_FLOAT:
			sel = is_equal_approx(float(cur), float(values[i]))
		var b := UiKit.button(labels[i], 19, sel)
		b.custom_minimum_size = Vector2(0, 46)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var v: Variant = values[i]
		b.pressed.connect(func() -> void:
			Settings.set_v(key, v)
			settings_changed.emit()
			reopen.call())
		h.add_child(b)
	var l := UiKit.label(title, 19, UiKit.MUTED)
	l.custom_minimum_size = Vector2(190, 0)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	h.add_child(l)
	_box.add_child(h)


## صف منزلق: عنوان + منزلق + قيمة مئوية (يُطبَّق مباشرة أثناء السحب ويُحفظ عند الإفلات)
func _slider(title: String, key: String, lo_text: String, hi_text: String) -> void:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 8)
	var val := UiKit.label("%d%%" % int(Settings.get_v(key)), 19, UiKit.ACCENT)
	val.custom_minimum_size = Vector2(62, 46)
	h.add_child(val)
	var lo := UiKit.label(lo_text, 15, UiKit.MUTED, false)
	lo.custom_minimum_size = Vector2(64, 0)
	h.add_child(lo)
	var sl := HSlider.new()
	sl.min_value = 0
	sl.max_value = 100
	sl.step = 5
	sl.value = int(Settings.get_v(key))
	sl.focus_mode = Control.FOCUS_NONE
	sl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	sl.custom_minimum_size = Vector2(0, 46)
	var track := StyleBoxFlat.new()
	track.bg_color = Color(1, 1, 1, 0.16)
	track.set_corner_radius_all(5)
	track.content_margin_top = 5
	track.content_margin_bottom = 5
	var fill := StyleBoxFlat.new()
	fill.bg_color = UiKit.ACCENT
	fill.set_corner_radius_all(5)
	fill.content_margin_top = 5
	fill.content_margin_bottom = 5
	sl.add_theme_stylebox_override("slider", track)
	sl.add_theme_stylebox_override("grabber_area", fill)
	sl.add_theme_stylebox_override("grabber_area_highlight", fill)
	var knob := _knob_tex()
	sl.add_theme_icon_override("grabber", knob)
	sl.add_theme_icon_override("grabber_highlight", knob)
	sl.value_changed.connect(func(v: float) -> void:
		Settings.data[key] = int(v)
		val.text = "%d%%" % int(v)
		settings_changed.emit())
	sl.drag_ended.connect(func(_c: bool) -> void: Settings.set_v(key, int(sl.value)))
	h.add_child(sl)
	var hi := UiKit.label(hi_text, 15, UiKit.MUTED, false)
	hi.custom_minimum_size = Vector2(64, 0)
	h.add_child(hi)
	var l := UiKit.label(title, 19, UiKit.MUTED)
	l.custom_minimum_size = Vector2(190, 0)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	h.add_child(l)
	_box.add_child(h)


var _knob: Texture2D
func _knob_tex() -> Texture2D:
	if _knob == null:
		var n := 36
		var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
		for y in n:
			for x in n:
				var d := Vector2(x + 0.5 - n * 0.5, y + 0.5 - n * 0.5).length()
				var a := clampf(n * 0.5 - 1.0 - d, 0.0, 1.0)
				var c := Color(1, 1, 1) if d < n * 0.5 - 5.0 else Color(0.84, 0.93, 0.22)
				img.set_pixel(x, y, Color(c.r, c.g, c.b, a))
		_knob = ImageTexture.create_from_image(img)
	return _knob


# ---------------------------------------------------------------------
func show_main() -> void:
	_open("main", 460)
	_dim.color = Color(0.01, 0.03, 0.07, 0.35)
	_title("نقطة المباراة", 52)
	var sub := UiKit.label("محاكاة تنس واقعية", 22, UiKit.ACCENT, false)
	_box.add_child(sub)
	_box.add_child(_spacer(6))
	_btn("مباراة جديدة", show_setup, true)
	_btn("طريقة اللعب", func() -> void: show_help("main"))
	_btn("الإعدادات", func() -> void: show_settings("main"))
	var st := UiKit.label("المباريات: %d   |   الانتصارات: %d" % [int(Settings.get_v("matches")), int(Settings.get_v("wins"))], 17, UiKit.MUTED, false)
	_box.add_child(st)
	var v := UiKit.label("الإصدار 0.4", 14, Color(1, 1, 1, 0.35), false)
	_box.add_child(v)


func _spacer(h: float) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, h)
	return c


func show_setup() -> void:
	_open("setup", 900)
	_box.add_theme_constant_override("separation", 7)
	_title("إعداد المباراة", 30)
	_player_row("لاعبك", "player_id")
	_player_row("الخصم", "opponent_id")
	_option("أرضية الملعب", "surface", ["صلبة", "ترابية", "عشبية"], [0, 1, 2], show_setup)
	_option("ذكاء الخصم", "difficulty", ["مبتدئ", "هاوٍ", "محترف", "أسطورة"], [0, 1, 2, 3], show_setup)
	_option("طول المباراة", "sets", ["مجموعة", "أفضل 3", "أفضل 5"], [1, 2, 3], show_setup)
	_option("أشواط المجموعة", "games", ["4 (قصيرة)", "6 (رسمية)"], [4, 6], show_setup)
	_option("الرياح", "wind", ["بلا رياح", "خفيفة", "قوية"], [0, 1, 2], show_setup)
	_row_buttons([["رجوع", show_main], ["ابدأ المباراة", func() -> void: start_requested.emit(), true]])


## صف اختيار لاعب: سهمان + الاسم والتقييم العام + زر البطاقة
func _player_row(title: String, key: String) -> void:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 6)
	var cur := PlayerProfile.index_of(str(Settings.get_v(key)))
	var prof: Dictionary = PlayerProfile.ROSTER[cur]
	var n := PlayerProfile.ROSTER.size()
	var prev := UiKit.button("◀", 22)
	prev.custom_minimum_size = Vector2(58, 52)
	prev.pressed.connect(func() -> void:
		Settings.set_v(key, PlayerProfile.ROSTER[(cur - 1 + n) % n]["id"])
		show_setup())
	var next := UiKit.button("▶", 22)
	next.custom_minimum_size = Vector2(58, 52)
	next.pressed.connect(func() -> void:
		Settings.set_v(key, PlayerProfile.ROSTER[(cur + 1) % n]["id"])
		show_setup())
	var card := UiKit.button("%s   %d   •   %s" % [prof["name"], PlayerProfile.overall(prof["r"]), prof["style"]], 20)
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.custom_minimum_size = Vector2(0, 52)
	card.pressed.connect(func() -> void: show_card(str(prof["id"]), "setup"))
	h.add_child(next)
	h.add_child(card)
	h.add_child(prev)
	var l := UiKit.label(title, 19, UiKit.MUTED)
	l.custom_minimum_size = Vector2(150, 0)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	h.add_child(l)
	_box.add_child(h)


## بطاقة اللاعب: كل التقييمات مقسمة إلى مجموعات بأشرطة ملونة
func show_card(id: String, back: String) -> void:
	_back_to = back
	_open("card", 1000)
	var prof: Dictionary = PlayerProfile.get_profile(id)
	var r: Dictionary = prof["r"]
	_title("%s  —  %d" % [prof["name"], PlayerProfile.overall(r)], 30)
	var hand_txt := "أعسر" if int(prof["hand"]) < 0 else "أيمن"
	var bh_txt := "خلفية بيدين" if prof["two_handed"] else "خلفية بيد واحدة"
	_box.add_child(UiKit.label("%s   •   %s   •   %s" % [prof["style"], hand_txt, bh_txt], 18, UiKit.ACCENT, false))
	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 26)
	var left := VBoxContainer.new()
	var right := VBoxContainer.new()
	for c in [left, right]:
		c.add_theme_constant_override("separation", 3)
		c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cols.add_child(left)
	cols.add_child(right)
	var gi := 0
	for g in PlayerProfile.GROUPS:
		var col: VBoxContainer = right if gi < 2 else left
		gi += 1
		var gl := UiKit.label(g[0], 17, UiKit.MUTED)
		gl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		col.add_child(gl)
		for k in g[1]:
			col.add_child(_rating_bar(PlayerProfile.NAMES[k], int(r[k])))
	_box.add_child(cols)
	_btn("رجوع", _go_back)


func _rating_bar(title: String, v: int) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(440, 27)
	var font := UiKit.font_bold()
	c.draw.connect(func() -> void:
		var w := c.size.x
		var bar_w := w * 0.46
		var col := Color(0.85, 0.3, 0.25).lerp(Color(0.95, 0.85, 0.25), clampf((v - 55.0) / 20.0, 0.0, 1.0))
		if v >= 80:
			col = Color(0.3, 0.85, 0.4)
		if v >= 90:
			col = Color(0.35, 0.8, 1.0)
		c.draw_rect(Rect2(0, 8, bar_w, 12), Color(1, 1, 1, 0.10))
		c.draw_rect(Rect2(bar_w * (1.0 - v / 100.0), 8, bar_w * v / 100.0, 12), col)
		c.draw_string(font, Vector2(bar_w + 10, 21), str(v), HORIZONTAL_ALIGNMENT_LEFT, -1, 17, col)
		c.draw_string(font, Vector2(bar_w + 48, 21), title, HORIZONTAL_ALIGNMENT_RIGHT, w - bar_w - 52, 16, Color(0.92, 0.94, 0.97)))
	return c


func show_help(back: String) -> void:
	_back_to = back
	_open("help", 900)
	_title("طريقة اللعب")
	var lines := [
		"الحركة: اسحب في النصف الأيسر من الشاشة لتظهر عصا التحكم.",
		"الضربة: اضغط زر الضربة مطوّلاً لشحن القوة. عند اقتراب الكرة يظهر شريط التوقيت ويتحرك مؤشره بسرعة الكرة القادمة.",
		"أفلِت الزر والمؤشر في المنطقة الخضراء لأفضل ضربة، الصفراء جيدة، الحمراء ضعيفة، ووصول المؤشر للنهاية = أسوأ ضربة.",
		"التصويب: أثناء الضغط على زر الضربة تصبح العصا للتصويب (يمين/يسار للاتجاه، أعلى للعمق، أسفل لكرة قصيرة بزاوية) واللاعب يتحرك للكرة تلقائياً.",
		"الأنواع: لولبية (آمنة) • مسطّحة (سريعة وخطرة) • مقطوعة (منخفضة، ومع العصا للأسفل = ساقطة) • عالية (لوب).",
		"الإرسال: حرّك العصا لتغيير موقفك على خط القاعدة، ثم اضغط زر الإرسال: يظهر مؤشر مكان السقوط وتحركه العصا حتى تُفلت الزر.",
		"فوق اللاعب يظهر شريط التوقيت، وبجانبه دائرة شحن القوة، وتحت قدميه شريط اللياقة: الجري المتواصل والضربات القوية تستنزفها، وتعود عند الراحة.",
		"اللياقة المنخفضة تبطئ الجري وتضيّق المنطقة الخضراء وتُقصّر الضربات وتزيد الأخطاء.",
		"الأخطاء منطقية لا عشوائية: القوة فوق قدرة اللاعب تُطيل الكرة، التأخر يرسلها للشبكة، المبكر يسحبها، والضرب ممدوداً أو أثناء الجري يُقصرها أو يحرفها.",
		"التقييمات (16 تقييماً) تؤثر فعلياً: السرعة والرشاقة في الجري، الدقة في الأخطاء، القوة في سرعة الكرة، والثبات في النقاط الحاسمة.",
	]
	for t in lines:
		var l := UiKit.label(t, 18, UiKit.TEXT, false)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		l.custom_minimum_size = Vector2(840, 0)
		_box.add_child(l)
	_btn("رجوع", _go_back)


func show_settings(back: String) -> void:
	_back_to = back
	_open("settings", 860)
	_title("الإعدادات", 28)
	_box.add_theme_constant_override("separation", 5)
	if back == "pause":
		_dim.color = Color(0.01, 0.03, 0.07, 0.25)     # خلفية أخف لمعاينة الكاميرا مباشرة
	var re := func() -> void: show_settings(_back_to)
	_option("مساعدة الحركة", "assist", ["بدون", "محاذاة خفيفة", "جري تلقائي"], [0, 1, 2], re)
	_option("ظهور شريط التوقيت", "qte_dist", ["قريب (أصعب)", "متوسط", "بعيد (أسهل)"], [0, 1, 2], re)
	_option("مؤشر التصويب", "aim_marker", ["إيقاف", "تشغيل"], [false, true], re)
	_option("مؤشر الكرة على الأرض", "ball_marker", ["إيقاف", "يتبع الكرة", "+ مكان السقوط"], [0, 1, 2], re)
	_slider("ارتفاع الكاميرا", "cam_height", "مسطحة", "مرتفعة")
	_slider("تقريب الكاميرا", "cam_zoom", "بعيدة", "قريبة")
	_option("جودة الرسوم", "quality", ["منخفضة", "متوسطة", "عالية"], [0, 1, 2], re)
	_option("حجم الكرة", "ball_scale", ["واقعي", "مكبّرة", "كبيرة"], [1.0, 1.25, 1.6], re)
	_option("المؤثرات الصوتية", "sfx", ["صامت", "متوسط", "عالٍ"], [0.0, 0.5, 0.9], re)
	_option("صوت الجمهور", "crowd", ["صامت", "متوسط", "عالٍ"], [0.0, 0.35, 0.7], re)
	_btn("رجوع", _go_back)


func _go_back() -> void:
	_box.add_theme_constant_override("separation", 10)
	match _back_to:
		"main": show_main()
		"setup": show_setup()
		"pause": show_pause()
		_: hide_all()


func show_pause() -> void:
	_open("pause", 440)
	_dim.color = Color(0.01, 0.03, 0.07, 0.6)
	_title("إيقاف مؤقت")
	_btn("متابعة", func() -> void: resume_requested.emit(), true)
	_btn("طريقة اللعب", func() -> void: show_help("pause"))
	_btn("الإعدادات", func() -> void: show_settings("pause"))
	_btn("إعادة المباراة", func() -> void: restart_requested.emit())
	_btn("القائمة الرئيسية", func() -> void: quit_requested.emit())


func show_result(game: TennisMatch, names: Array, human_idx: int) -> void:
	_open("result", 760)
	_dim.color = Color(0.01, 0.03, 0.07, 0.6)
	var w := game.rules.winner
	_title("فزت بالمباراة!" if w == human_idx else "خسرت المباراة", 38)
	var score := ""
	for h in game.rules.set_history:
		score += "%d–%d   " % [h[0], h[1]]
	_box.add_child(UiKit.label(score.strip_edges(), 30, UiKit.ACCENT))
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 30)
	grid.add_theme_constant_override("v_separation", 2)
	var s0: Dictionary = game.stats[0]
	var s1: Dictionary = game.stats[1]
	var rows := [
		[names[0], "", names[1]],
		[str(s0["points"]), "النقاط", str(s1["points"])],
		[str(s0["aces"]), "إرسالات ساحقة", str(s1["aces"])],
		[str(s0["double_faults"]), "أخطاء مزدوجة", str(s1["double_faults"])],
		[str(s0["winners"]), "ضربات فائزة", str(s1["winners"])],
		[str(s0["unforced"]), "أخطاء غير مجبرة", str(s1["unforced"])],
		["%d%%" % int(100.0 * s0["first_in"] / maxf(s0["first_total"], 1)), "نسبة الإرسال الأول", "%d%%" % int(100.0 * s1["first_in"] / maxf(s1["first_total"], 1))],
		["%d" % int(s0["max_serve"]), "أسرع إرسال (كم/س)", "%d" % int(s1["max_serve"])],
	]
	for i in rows.size():
		for j in 3:
			var head := i == 0
			var l := UiKit.label(rows[i][j], 22 if head else 20, UiKit.ACCENT if head else (UiKit.MUTED if j == 1 else UiKit.TEXT), j != 1 or head)
			l.custom_minimum_size = Vector2(200 if j != 1 else 240, 0)
			grid.add_child(l)
	var cc := CenterContainer.new()
	cc.add_child(grid)
	_box.add_child(cc)
	_box.add_child(_spacer(4))
	_row_buttons([["القائمة الرئيسية", func() -> void: quit_requested.emit()], ["مباراة أخرى", func() -> void: restart_requested.emit(), true]])
