extends ModalPanel
## قائمة الإيقاف: متابعة، حفظ، إعدادات الرسوميات والتحكم، دليل اللعب، العودة للقائمة الرئيسية.

var view := "main"
var content: VBoxContainer

func build() -> void:
	make_frame("القائمة", 0.08)
	var sc := UIKit.scroll()
	body.add_child(sc)
	content = UIKit.vbox(10)
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(content)

func open() -> void:
	view = "main"
	super.open()

func refresh() -> void:
	clear(content)
	match view:
		"main": _main()
		"settings": _settings()
		"help": _help()

func _big(t: String, cb: Callable) -> void:
	var b := UIKit.button(t, cb, 24, 68)
	content.add_child(b)

func _main() -> void:
	title_lbl.text = "القائمة"
	_big("متابعة اللعب", close)
	_big("حفظ اللعبة", _save_close)
	_big("الإعدادات", func(): view = "settings"; refresh())
	_big("دليل اللعب", func(): view = "help"; refresh())
	_big("حفظ والعودة للقائمة الرئيسية", _save_menu)

func _save_close() -> void:
	if world().save_game():
		Game.notify("تم حفظ اللعبة", Color(0.7, 1, 0.7))
	close()

func _save_menu() -> void:
	world().save_game()
	close()
	Game.main.back_to_menu()

func _settings() -> void:
	title_lbl.text = "الإعدادات"
	var s: Dictionary = Game.settings
	content.add_child(UIKit.label("جودة الرسوميات (تُطبق عند بدء/تحميل اللعبة):", 20, UIKit.GOLD))
	var qh := UIKit.hbox(8)
	qh.alignment = BoxContainer.ALIGNMENT_END
	content.add_child(qh)
	for q in [[2, "عالية"], [1, "متوسطة"], [0, "منخفضة"]]:
		var b := UIKit.button(q[1], func(): Game.set_setting("quality", q[0]); _apply_quality(); refresh(), 20, 56)
		b.custom_minimum_size = Vector2(150, 56)
		if int(s["quality"]) == q[0]:
			b.add_theme_stylebox_override("normal", UIKit.sb(Color(0.45, 0.34, 0.15, 1.0), 10, 2, UIKit.GOLD, 10))
		qh.add_child(b)
	_slider("حساسية النظر", 0.3, 2.5, float(s["sensitivity"]), func(v): Game.set_setting("sensitivity", v))
	_slider("مستوى الصوت", 0.0, 1.0, float(s["volume"]), func(v): Game.set_setting("volume", v))
	_slider("طول اليوم (دقائق حقيقية)", 10.0, 60.0, float(s["day_minutes"]), func(v): Game.set_setting("day_minutes", v))
	_toggle("عكس محور النظر العمودي", "invert_y")
	_toggle("منظور الشخص الأول", "first_person", func(): world().player.set_first_person(Game.settings["first_person"]))
	_toggle("إظهار عدد الإطارات", "show_fps")
	_big("رجوع", func(): view = "main"; refresh())

func _apply_quality() -> void:
	var q := int(Game.settings["quality"])
	get_viewport().scaling_3d_scale = [0.7, 0.85, 1.0][q]

func _slider(t: String, mn: float, mx: float, v: float, cb: Callable) -> void:
	var h := UIKit.hbox(10)
	var sl := HSlider.new()
	sl.min_value = mn
	sl.max_value = mx
	sl.step = (mx - mn) / 100.0
	sl.value = v
	sl.custom_minimum_size = Vector2(380, 44)
	var lbl := UIKit.label("%s: %.2f" % [t, v], 20)
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sl.value_changed.connect(func(nv): cb.call(nv); lbl.text = "%s: %.2f" % [t, nv])
	h.add_child(sl)
	h.add_child(lbl)
	content.add_child(h)

func _toggle(t: String, key: String, extra := Callable()) -> void:
	var on: bool = Game.settings.get(key, false)
	var b := UIKit.button("%s: %s" % [t, "مفعّل" if on else "معطّل"], _on_toggle.bind(key, extra), 20, 58)
	content.add_child(b)

func _on_toggle(key: String, extra: Callable) -> void:
	Game.set_setting(key, not Game.settings.get(key, false))
	if extra.is_valid():
		extra.call()
	refresh()

func _help() -> void:
	title_lbl.text = "دليل اللعب"
	var lines := [
		["التحكم", ""],
		["• العصا اليسرى: الحركة. اسحب في الجهة اليمنى من الشاشة لتدوير الكاميرا.", ""],
		["• زر الضرب: يقطع الأشجار ويكسر الصخور ويهاجم ويأكل ما في يدك. استمر بالضغط للضرب المتواصل.", ""],
		["• زر التفاعل: يظهر عند النظر لشيء قابل للتفاعل (التقاط، حديث، فتح صندوق، نوم، شرب...).", ""],
		["• اختر الأداة من الشريط السفلي. الحاسوب: WASD، الفأرة، E للتفاعل، Tab للحقيبة، R للصناعة، B للبناء، M للخريطة.", ""],
		["البداية", ""],
		["• اجمع العيدان والحجارة من الأرض، والألياف من الشجيرات والعشب الطويل.", ""],
		["• اصنع حبلاً ثم فأساً ومعولاً حجريين ومطرقة البناء. اقطع الأشجار واكسر الصخور.", ""],
		["• ابنِ نار مخيم للطبخ وغلي الماء والتدفئة، ثم مأوى وسريراً قبل حلول الليل.", ""],
		["البقاء", ""],
		["• راقب الشبع والارتواء والدفء والطاقة. الحمولة الزائدة تبطئك وتمنعك من الجري.", ""],
		["• اللياقة تتحسن بالجري وحمل الأوزان والسباحة. المهارات تتحسن بالممارسة.", ""],
		["• الحيوانات المفترسة أخطر ليلاً. الشعلة تبعد الذئاب. الدببة تحمي منطقتها.", ""],
		["البشر", ""],
		["• لكل شخص شخصية وذاكرة وعلاقات مع الآخرين. تحدث معهم وقدم الهدايا لتكسب صداقتهم.", ""],
		["• الأصدقاء يتاجرون بأسعار أفضل ويعطونك معلومات وقد ينضمون إليك كرفاق يقاتلون معك ويحرسون بيتك.", ""],
		["• الأخبار تنتشر: إن آذيت أحداً سيعرف أصدقاؤه. بعض الرحالة لصوص يسرقون صناديقك ويحاولون نشلك.", ""],
		["• اسأل الناس عن الآخرين لتعرف من رأى اللص، ثم واجهه واتهمه لتستعيد أغراضك.", ""],
		["البناء", ""],
		["• ابدأ بأساس، ثم جدران ومدخل بباب وأسقف. القطع غير المدعومة تنهار.", ""],
		["• الخزنة الحديدية والأقفال والغرف المغلقة تحمي ممتلكاتك. راية الملكية تنبهك بالغرباء.", ""],
	]
	for l in lines:
		var is_head: bool = not l[0].begins_with("•")
		content.add_child(UIKit.label(l[0], 22 if is_head else 18, UIKit.GOLD if is_head else UIKit.TEXT))
	_big("رجوع", func(): view = "main"; refresh())
