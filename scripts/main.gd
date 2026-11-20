extends Node
## نقطة البداية: القائمة الرئيسية، شاشة التحميل، إنشاء العالم الجديد أو تحميل الحفظ.

var menu: CanvasLayer
var loading: CanvasLayer
var load_bar: ProgressBar
var load_lbl: Label
var world: Node = null
var confirm_box: Control
var menu_vbox: VBoxContainer
var tip_lbl: Label

const TIPS := [
	"اغلِ الماء قبل شربه لتجنب المرض.",
	"الذئاب تصطاد في جماعات وتزداد جرأة في الليل.",
	"بعض الرحالة لصوص... اقفل صناديقك.",
	"الأصدقاء يتبادلون الأخبار، وكذلك الأعداء.",
	"معطف الفرو ينقذك في الشمال، لكنه يقتلك في الصحراء.",
	"اللياقة تتحسن بالجري وحمل الأثقال.",
	"الطعام يفسد مع الوقت، والملح يحفظه.",
	"الدببة تحذرك أولاً قبل أن تهاجم. ابتعد عنها.",
]

func _ready() -> void:
	Game.main = self
	get_tree().set_auto_accept_quit(false)
	_apply_quality()
	_build_menu()
	_build_loading()
	show_menu()

func _apply_quality() -> void:
	var q := int(Game.settings.get("quality", 1))
	var vp := get_viewport()
	vp.scaling_3d_scale = [0.7, 0.85, 1.0][q]
	vp.msaa_3d = Viewport.MSAA_DISABLED if q == 0 else Viewport.MSAA_2X
	vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED if q == 0 else Viewport.SCREEN_SPACE_AA_FXAA
	RenderingServer.directional_shadow_atlas_set_size(1024 if q == 0 else (2048 if q == 1 else 4096), true)

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		if world != null and world.started:
			world.save_game()
		get_tree().quit()

func _build_menu() -> void:
	menu = CanvasLayer.new()
	add_child(menu)
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.theme = UIKit.theme()
	menu.add_child(root)
	var bg := TextureRect.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.stretch_mode = TextureRect.STRETCH_SCALE
	bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	var grad := Gradient.new()
	grad.set_color(0, Color(0.95, 0.6, 0.3))
	grad.set_color(1, Color(0.12, 0.1, 0.16))
	grad.add_point(0.45, Color(0.55, 0.3, 0.25))
	var gt := GradientTexture2D.new()
	gt.gradient = grad
	gt.fill_from = Vector2(0.5, 0.0)
	gt.fill_to = Vector2(0.5, 1.0)
	bg.texture = gt
	root.add_child(bg)
	var deco := Control.new()
	deco.set_anchors_preset(Control.PRESET_FULL_RECT)
	deco.mouse_filter = Control.MOUSE_FILTER_IGNORE
	deco.draw.connect(func(): _draw_landscape(deco))
	deco.resized.connect(func(): deco.queue_redraw())
	root.add_child(deco)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(center)
	menu_vbox = UIKit.vbox(14)
	menu_vbox.custom_minimum_size = Vector2(520, 0)
	center.add_child(menu_vbox)
	var title := UIKit.label("أرض البقاء", 76, Color(1, 0.93, 0.75), HORIZONTAL_ALIGNMENT_CENTER)
	title.add_theme_constant_override("outline_size", 14)
	menu_vbox.add_child(title)
	menu_vbox.add_child(UIKit.label("ابقَ حياً. ابنِ. اكتشف. اختر أصدقاءك بحكمة.", 24, Color(1, 0.9, 0.8), HORIZONTAL_ALIGNMENT_CENTER))
	menu_vbox.add_child(Control.new())
	confirm_box = UIKit.vbox(10)
	confirm_box.visible = false
	confirm_box.add_child(UIKit.label("بدء لعبة جديدة سيحذف الحفظ الحالي. هل أنت متأكد؟", 22, Color(1, 0.8, 0.6), HORIZONTAL_ALIGNMENT_CENTER))
	var ch := UIKit.hbox(10)
	ch.alignment = BoxContainer.ALIGNMENT_CENTER
	confirm_box.add_child(ch)
	ch.add_child(UIKit.button("إلغاء", func(): confirm_box.visible = false, 22, 60))
	ch.add_child(UIKit.button("نعم، لعبة جديدة", func(): _new_game(), 22, 60))
	tip_lbl = UIKit.label("", 19, Color(0.95, 0.9, 0.8), HORIZONTAL_ALIGNMENT_CENTER)
	_refresh_menu()

func _draw_landscape(c: Control) -> void:
	var s := c.size
	var r := RandomNumberGenerator.new()
	r.seed = 5
	c.draw_circle(Vector2(s.x * 0.78, s.y * 0.3), s.y * 0.08, Color(1, 0.9, 0.65, 0.9))
	var pts := PackedVector2Array([Vector2(0, s.y)])
	for i in range(13):
		pts.append(Vector2(s.x * i / 12.0, s.y * (0.55 + r.randf_range(-0.12, 0.08))))
	pts.append(Vector2(s.x, s.y))
	c.draw_colored_polygon(pts, Color(0.22, 0.17, 0.22, 0.9))
	var pts2 := PackedVector2Array([Vector2(0, s.y)])
	for i in range(25):
		pts2.append(Vector2(s.x * i / 24.0, s.y * (0.75 + sin(i * 0.7) * 0.03 + r.randf_range(-0.02, 0.02))))
	pts2.append(Vector2(s.x, s.y))
	c.draw_colored_polygon(pts2, Color(0.12, 0.16, 0.12, 0.95))
	for i in range(18):
		var x := r.randf() * s.x
		var y := s.y * (0.76 + r.randf() * 0.2)
		var h := r.randf_range(40, 110)
		c.draw_colored_polygon(PackedVector2Array([Vector2(x, y - h), Vector2(x - h * 0.28, y), Vector2(x + h * 0.28, y)]), Color(0.06, 0.1, 0.07))

func _refresh_menu() -> void:
	for i in range(menu_vbox.get_child_count() - 1, 2, -1):
		var ch := menu_vbox.get_child(i)
		menu_vbox.remove_child(ch)
		if ch != confirm_box and ch != tip_lbl:
			ch.queue_free()
	if Game.has_save():
		menu_vbox.add_child(UIKit.button("متابعة", _continue, 28, 74))
	menu_vbox.add_child(UIKit.button("لعبة جديدة", _ask_new, 28, 74))
	var qh := UIKit.hbox(8)
	qh.alignment = BoxContainer.ALIGNMENT_CENTER
	for q in [[2, "جودة عالية"], [1, "جودة متوسطة"], [0, "جودة منخفضة"]]:
		var b := UIKit.button(q[1], func(): Game.set_setting("quality", q[0]); _apply_quality(); _refresh_menu(), 18, 52)
		if int(Game.settings["quality"]) == q[0]:
			b.add_theme_stylebox_override("normal", UIKit.sb(Color(0.45, 0.34, 0.15, 1.0), 10, 2, UIKit.GOLD, 10))
		qh.add_child(b)
	menu_vbox.add_child(qh)
	if not OS.has_feature("mobile") and not OS.has_feature("web"):
		menu_vbox.add_child(UIKit.button("خروج", func(): get_tree().quit(), 22, 58))
	menu_vbox.add_child(confirm_box)
	tip_lbl.text = "نصيحة: " + TIPS[randi() % TIPS.size()]
	menu_vbox.add_child(tip_lbl)

func _build_loading() -> void:
	loading = CanvasLayer.new()
	loading.layer = 50
	add_child(loading)
	var root := ColorRect.new()
	root.color = Color(0.06, 0.06, 0.08)
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.theme = UIKit.theme()
	loading.add_child(root)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(center)
	var v := UIKit.vbox(16)
	v.custom_minimum_size = Vector2(620, 0)
	center.add_child(v)
	v.add_child(UIKit.label("أرض البقاء", 56, Color(1, 0.9, 0.7), HORIZONTAL_ALIGNMENT_CENTER))
	load_lbl = UIKit.label("", 24, UIKit.TEXT, HORIZONTAL_ALIGNMENT_CENTER)
	v.add_child(load_lbl)
	load_bar = UIKit.bar(UIKit.GOLD, 18)
	v.add_child(load_bar)
	var tip := UIKit.label("نصيحة: " + TIPS[randi() % TIPS.size()], 19, UIKit.DIM, HORIZONTAL_ALIGNMENT_CENTER)
	v.add_child(tip)
	loading.visible = false

func show_menu() -> void:
	menu.visible = true
	loading.visible = false
	_refresh_menu()

func _ask_new() -> void:
	if Game.has_save():
		confirm_box.visible = true
	else:
		_new_game()

func _new_game() -> void:
	confirm_box.visible = false
	Game.delete_save()
	_start(true, randi() % 1000000, {})

func _continue() -> void:
	var data := Game.read_save()
	if data.is_empty():
		Game.notify("تعذر قراءة الحفظ", Color(1, 0.5, 0.4))
		_new_game()
		return
	_start(false, int(data.get("seed", 1)), data)

func _progress(v: float, t: String) -> void:
	load_bar.value = v * 100.0
	load_lbl.text = t

func _start(new_game: bool, seed_v: int, data: Dictionary) -> void:
	menu.visible = false
	loading.visible = true
	_progress(0.0, "تحضير...")
	await get_tree().process_frame
	await get_tree().process_frame
	_apply_quality()
	var ws = load("res://scripts/world/world.gd")
	world = ws.new()
	add_child(world)
	await world.start(new_game, seed_v, data, _progress)
	await get_tree().process_frame
	loading.visible = false
	if new_game:
		world.save_game()

func back_to_menu() -> void:
	if world != null:
		Sfx.stop_all_loops()
		Game.world = null
		Game.player = null
		Game.hud = null
		Game.ui_open = false
		world.queue_free()
		world = null
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	show_menu()
