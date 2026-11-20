extends ModalPanel
## نافذة الشخصية: الحالة الصحية، اللياقة والمهارات، شبكة العلاقات مع الشخصيات وبينها، سمعة المستوطنات، وسجل الأحداث.

var tab := "status"
var tabs: HBoxContainer
var content: VBoxContainer

func build() -> void:
	make_frame("شخصيتي")
	tabs = UIKit.hbox(8)
	tabs.alignment = BoxContainer.ALIGNMENT_END
	body.add_child(tabs)
	var sc := UIKit.scroll()
	body.add_child(sc)
	content = UIKit.vbox(8)
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(content)

func refresh() -> void:
	clear(tabs)
	for t in [["log", "السجل"], ["people", "العلاقات"], ["skills", "اللياقة والمهارات"], ["status", "الحالة"]]:
		var b := UIKit.button(t[1], func(): tab = t[0]; refresh(), 20, 52)
		if tab == t[0]:
			b.add_theme_stylebox_override("normal", UIKit.sb(Color(0.45, 0.34, 0.15, 1.0), 10, 2, UIKit.GOLD, 10))
		tabs.add_child(b)
	clear(content)
	match tab:
		"status": _status()
		"skills": _skills()
		"people": _people()
		"log": _log()

func _line(t: String, col := UIKit.TEXT, size := 20) -> void:
	content.add_child(UIKit.label(t, size, col))

func _barline(t: String, v: float, col: Color) -> void:
	var h := UIKit.hbox(10)
	var b := UIKit.bar(col, 16)
	b.value = v * 100.0
	b.custom_minimum_size = Vector2(300, 16)
	b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(b)
	var l := UIKit.label(t, 19)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(l)
	content.add_child(h)

func _status() -> void:
	var p := player()
	var st := p.stats
	_line("الصحة: %d / %d" % [int(st.health), int(st.max_health)])
	_line("الشبع: %d   |   الارتواء: %d   |   الطاقة: %d" % [int(st.hunger), int(st.thirst), int(st.energy)])
	_line("حرارة الجسم: %.1f°م   |   حرارة الجو: %d°م   |   الحرارة المحسوسة: %d°م" % [st.body_temp, int(p.ambient_temp), int(p.eff_temp)])
	var ins := p.insulation()
	_line("عزل البرد من ملابسك: %d   |   حماية من الحر: %d   |   الدروع: %d" % [int(ins.x), int(ins.y), int(p.armor())])
	_line("المأوى: %s   |   قرب مصدر حرارة: %s" % ["نعم (%d٪)" % int(p.shelter * 100) if p.shelter > 0.2 else "لا", "نعم" if p.heat > 0.1 else "لا"])
	_line("الحمولة: %.1f / %.0f كغ" % [p.carry_weight(), st.carry_capacity()])
	var sl := []
	for e in st.status_list():
		sl.append(e[0])
	_line("الحالات: %s" % ("، ".join(sl) if not sl.is_empty() else "بخير"), UIKit.GOLD)
	content.add_child(UIKit.sep())
	_line("نصائح البقاء:", UIKit.GOLD)
	_line("• اطبخ اللحم واغلِ الماء على نار المخيم لتجنب المرض.", UIKit.DIM, 17)
	_line("• الملابس والمأوى ونار المخيم تحميك من برد الليل والشمال. العباءة والقبعة تحميانك في الصحراء.", UIKit.DIM, 17)
	_line("• الطعام يفسد مع الوقت (أبطأ في البرد). الملح يحفظ اللحم طويلاً.", UIKit.DIM, 17)
	_line("• خزّن الفائض في صناديق داخل غرفة مغلقة بباب مقفل، أو في خزنة حديدية، فاللصوص يتجولون.", UIKit.DIM, 17)
	content.add_child(UIKit.sep())
	var b := UIKit.button("نم هنا على الأرض (أقل راحة وأمان)", func(): close(); p.sleep_in(null), 20, 60)
	content.add_child(b)

func _skills() -> void:
	var st := player().stats
	_line("اللياقة البدنية: المستوى %d" % st.fitness_level(), UIKit.GOLD, 22)
	_barline("التقدم للمستوى التالي", st.fitness_progress(), Color(0.5, 0.9, 0.6))
	_line("تزيد اللياقة بالجري وحمل الأوزان والسباحة والعمل. كل مستوى يزيد التحمل وسعة الحمل وسرعة الجري.", UIKit.DIM, 16)
	_line("التحمل الأقصى: %d   |   سعة الحمل: %.0f كغ" % [int(st.max_stamina()), st.carry_capacity()], UIKit.TEXT, 18)
	content.add_child(UIKit.sep())
	for s in SurvivalStats.SKILL_NAMES:
		_barline("%s: المستوى %d" % [SurvivalStats.SKILL_NAMES[s], st.skill_level(s)], st.skill_progress(s), UIKit.GOLD)
	_line("الاحتطاب والتعدين: ضرر أكبر وغلة أوفر. الجمع: محاصيل أكثر. القتال: ضرر أعلى. الصناعة: سرعة أكبر. الإقناع: أسعار أفضل وعلاقات أسرع.", UIKit.DIM, 16)

func _people() -> void:
	var ai: Node = world().ai
	_line("سمعتك في المستوطنات:", UIKit.GOLD, 22)
	for s in ai.settlements:
		if not s["discovered"]:
			continue
		var rp: float = ai.reputation(s["id"])
		content.add_child(UIKit.label("%s: %s (%d)" % [s["name"], AIManager.rel_label(rp), int(rp)], 19, AIManager.rel_color(rp)))
	content.add_child(UIKit.sep())
	_line("الأشخاص الذين قابلتهم:", UIKit.GOLD, 22)
	var any := false
	for id in ai.npcs:
		var d: Dictionary = ai.npcs[id]
		if not d["met"]:
			continue
		any = true
		var r: float = ai.get_rel(id, "player")
		var s2: Dictionary = ai.settlement_of(d)
		var status := "" if d["alive"] else "  (متوفى)"
		var comp := "  [رفيقك]" if d["companion"] and d["alive"] else ""
		content.add_child(UIKit.label("%s - %s - %s: %s (%d)%s%s" % [d["name"], ai.role_name(d), s2.get("name", "رحّال"), AIManager.rel_label(r), int(r), comp, status], 19, AIManager.rel_color(r) if d["alive"] else UIKit.DIM))
		var tr := []
		for k in d["known_traits"]:
			var v: float = d["traits"][k]
			if v > 0.62 or v < 0.38:
				tr.append(AIManager.trait_name(d, k))
		var rels := []
		for key in ai.known_rel:
			var parts: PackedStringArray = key.split("|")
			if parts[0] == id and ai.npcs.has(parts[1]):
				var v2: float = ai.get_rel(id, parts[1])
				rels.append("%s %s" % ["يحب" if v2 > 20 else ("يكره" if v2 < -20 else "محايد تجاه"), ai.npcs[parts[1]]["name"]])
		var extra := ""
		if not tr.is_empty():
			extra += "صفاته: " + "، ".join(tr)
		if not rels.is_empty():
			extra += ("   |   " if extra != "" else "") + "، ".join(rels)
		if extra != "":
			content.add_child(UIKit.label("    " + extra, 16, UIKit.DIM))
	if not any:
		_line("لم تقابل أحداً بعد. ابحث عن المستوطنات وتحدث مع الناس.", UIKit.DIM)

func _log() -> void:
	var ai: Node = world().ai
	var j: Array = ai.journal
	if j.is_empty():
		_line("لا أحداث بعد.", UIKit.DIM)
	for i in range(j.size() - 1, -1, -1):
		_line(j[i], UIKit.TEXT, 18)
