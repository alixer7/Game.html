class_name MainMenu
extends Node3D
## Title screen: a 3D diorama (robot on a floating platform, drifting islands, orbiting gems) behind
## three UI pages: main, level select and settings. Everything is built from code.

const CARD_W := 332.0
const CARD_H := 660.0

var start_page: String = "main"

var _cam: Camera3D
var _hero: Node3D
var _robot: RobotModel
var _abyss: MeshInstance3D
var _floaters: Array = []
var _ui: Control
var _page: Control = null
var _page_name: String = ""
var _toast_label: Label
var _toast_tw: Tween
var _quit_until: int = 0
var _t: float = 0.0
var _busy: bool = false


func _ready() -> void:
	Mats.clear()
	Mats.theme = EnvBuilder.theme("launch")
	var env: Dictionary = EnvBuilder.build(self, "launch", Vector3(0.0, 0.0, -8.0), -50.0, 40.0)
	_abyss = env["abyss"]
	_build_diorama()
	_cam = Camera3D.new()
	_cam.fov = 48.0
	_cam.far = 700.0
	_cam.current = true
	add_child(_cam)
	_cam.position = Vector3(0.9, 1.7, 7.2)
	_cam.look_at(Vector3(2.6, 1.15, 0.0), Vector3.UP)
	_cam.add_child(EnvBuilder.make_motes("launch"))
	_build_ui()
	Sfx.play_music("music_menu")
	_show_page(start_page, true)


func _process(delta: float) -> void:
	_t += delta
	_robot.rotation.y = PI + 0.5 + sin(_t * 0.6) * 0.25
	_hero.position.y = sin(_t * 0.9) * 0.12
	for f in _floaters:
		var d: Dictionary = f
		var n: Node3D = d["n"]
		n.position.y = float(d["y"]) + sin(_t * float(d["sp"]) + float(d["ph"])) * 0.38
		n.rotation.y += delta * float(d["rot"])
	_cam.position = Vector3(0.9 + sin(_t * 0.27) * 0.45, 1.7 + sin(_t * 0.21) * 0.18, 7.2)
	_cam.look_at(Vector3(2.6, 1.15, 0.0), Vector3.UP)
	EnvBuilder.follow_abyss(_abyss, _cam.global_position)


# ---------------------------------------------------------------- diorama
func _build_diorama() -> void:
	_hero = Node3D.new()
	add_child(_hero)
	var pm := CylinderMesh.new()
	pm.top_radius = 3.3
	pm.bottom_radius = 3.3
	pm.height = 1.0
	pm.radial_segments = 48
	pm.rings = 1
	var plat := MeshInstance3D.new()
	plat.mesh = pm
	plat.material_override = Mats.platform(Vector3(3.3, 0.5, 3.3), 0, true)
	plat.position = Vector3(0.0, -0.5, 0.0)
	_hero.add_child(plat)
	var cone := CylinderMesh.new()
	cone.top_radius = 3.2
	cone.bottom_radius = 0.5
	cone.height = 3.2
	cone.radial_segments = 6
	cone.rings = 1
	var spire := MeshInstance3D.new()
	spire.mesh = cone
	spire.material_override = Mats.std(Color(0.07, 0.09, 0.17), 0.85, 0.35, Mats.accent(0), 0.25)
	spire.position = Vector3(0.0, -2.6, 0.0)
	_hero.add_child(spire)
	var tm := TorusMesh.new()
	tm.inner_radius = 3.0
	tm.outer_radius = 3.18
	tm.rings = 56
	tm.ring_segments = 6
	var ring := MeshInstance3D.new()
	ring.mesh = tm
	ring.material_override = Mats.neon(Mats.accent(0), 2.6, 1.2, 0.85)
	ring.position = Vector3(0.0, 0.03, 0.0)
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_hero.add_child(ring)
	_robot = RobotModel.make(Color(0.25, 0.9, 1.0))
	_robot.wave = true
	_robot.grounded = true
	_hero.add_child(_robot)

	var orbit := Fx.Spin.new()
	orbit.axis = Vector3.UP
	orbit.speed = 0.55
	orbit.position = Vector3(0.0, 1.3, 0.0)
	_hero.add_child(orbit)
	var gem: ArrayMesh = Collectibles.gem_mesh()
	var gem_mat := ShaderMaterial.new()
	gem_mat.shader = Mats.shader("res://shaders/coin.gdshader")
	for i in range(9):
		var a: float = TAU * float(i) / 9.0
		var g := MeshInstance3D.new()
		g.mesh = gem
		g.material_override = gem_mat
		g.scale = Vector3.ONE * 1.5
		g.position = Vector3(cos(a) * 4.7, sin(a * 3.0) * 0.55, sin(a) * 4.7)
		g.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		orbit.add_child(g)

	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	for i in range(11):
		var x: float = rng.randf_range(-17.0, 17.0)
		var z: float = rng.randf_range(-24.0, -5.0)
		if i < 2:
			x = -7.5 if i == 0 else 8.5
			z = 1.5
		if absf(x) < 4.2 and z > -9.0:
			x += 8.0 * signf(x if x != 0.0 else 1.0)
		var y: float = rng.randf_range(-4.5, 5.5)
		var is_cyl: bool = rng.randf() < 0.45
		var node := MeshInstance3D.new()
		var c: int = i % 4
		if is_cyl:
			var r: float = rng.randf_range(1.2, 2.6)
			var cm := CylinderMesh.new()
			cm.top_radius = r
			cm.bottom_radius = r
			cm.height = 0.7
			cm.radial_segments = 32
			cm.rings = 1
			node.mesh = cm
			node.material_override = Mats.platform(Vector3(r, 0.35, r), c, true)
		else:
			var sx: float = rng.randf_range(1.8, 3.8)
			var sz: float = rng.randf_range(1.8, 3.8)
			var bm := BoxMesh.new()
			bm.size = Vector3(sx, 0.7, sz)
			node.mesh = bm
			node.material_override = Mats.platform(Vector3(sx * 0.5, 0.35, sz * 0.5), c, false)
		node.position = Vector3(x, y, z)
		add_child(node)
		_floaters.append({"n": node, "y": y, "ph": rng.randf_range(0.0, TAU), "sp": rng.randf_range(0.5, 1.1), "rot": rng.randf_range(-0.12, 0.12)})


# --------------------------------------------------------------------- UI
func _build_ui() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 1
	add_child(layer)
	_ui = Control.new()
	UIKit.fill(_ui)
	_ui.layout_direction = Control.LAYOUT_DIRECTION_LTR
	_ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(_ui)
	_toast_label = UIKit.label("", 34, UIKit.COL_TEXT, HORIZONTAL_ALIGNMENT_CENTER, 6)
	UIKit.place(_toast_label, Vector2(0.5, 1.0), Vector2(-500.0, -150.0), Vector2(1000.0, 60.0))
	_toast_label.modulate.a = 0.0
	layer.add_child(_toast_label)
	_toast_label.layout_direction = Control.LAYOUT_DIRECTION_LTR


func _toast(txt: String) -> void:
	_toast_label.text = txt
	if _toast_tw != null and _toast_tw.is_valid():
		_toast_tw.kill()
	_toast_label.modulate.a = 1.0
	_toast_tw = create_tween()
	_toast_tw.tween_interval(1.6)
	_toast_tw.tween_property(_toast_label, "modulate:a", 0.0, 0.4)


func _show_page(which: String, instant: bool = false) -> void:
	if _page != null:
		_page.queue_free()
		_page = null
	_page_name = which
	if which == "levels":
		_page = _build_levels()
	elif which == "settings":
		_page = _build_settings()
	else:
		_page_name = "main"
		_page = _build_main()
	_ui.add_child(_page)
	if not instant:
		UIKit.fade_in(_page, 0.0, 0.3)


func on_back() -> void:
	if _page_name == "main":
		var now: int = Time.get_ticks_msec()
		if now < _quit_until:
			get_tree().quit()
		else:
			_quit_until = now + 2000
			_toast("اضغط مرة أخرى للخروج")
	else:
		Sfx.play("ui_back")
		_show_page("main")


func _side_gradient() -> TextureRect:
	var g := Gradient.new()
	g.set_color(0, Color(0.01, 0.02, 0.07, 0.0))
	g.set_color(1, Color(0.01, 0.02, 0.07, 0.78))
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.fill_from = Vector2(0.0, 0.0)
	gt.fill_to = Vector2(1.0, 0.0)
	gt.width = 256
	gt.height = 8
	var tr := TextureRect.new()
	tr.texture = gt
	tr.stretch_mode = TextureRect.STRETCH_SCALE
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	UIKit.place(tr, Vector2(0.45, 0.0), Vector2.ZERO, Vector2.ZERO)
	tr.anchor_right = 1.0
	tr.anchor_bottom = 1.0
	tr.offset_right = 0.0
	tr.offset_bottom = 0.0
	return tr


# -------------------------------------------------------------- main page
func _build_main() -> Control:
	var page := Control.new()
	UIKit.fill(page)
	page.mouse_filter = Control.MOUSE_FILTER_IGNORE
	page.add_child(_side_gradient())
	var m: Vector4 = UIKit.safe_margins(get_viewport())
	var colw: float = 760.0
	var left: float = -(m.z + 90.0 + colw)

	var logo := UIKit.label_ltr("NOVA BOT", 118, UIKit.COL_TEXT, HORIZONTAL_ALIGNMENT_CENTER, 14)
	UIKit.place(logo, Vector2(1.0, 0.0), Vector2(left, 90.0 + m.y), Vector2(colw, 150.0))
	page.add_child(logo)
	var bar := ColorRect.new()
	bar.color = UIKit.COL_CYAN
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	UIKit.place(bar, Vector2(1.0, 0.0), Vector2(left + colw * 0.5 - 150.0, 244.0 + m.y), Vector2(300.0, 5.0))
	page.add_child(bar)
	var sub := UIKit.label("مغامرة روبوت في أعماق المجرة", 38, UIKit.COL_CYAN, HORIZONTAL_ALIGNMENT_CENTER, 6)
	UIKit.place(sub, Vector2(1.0, 0.0), Vector2(left, 262.0 + m.y), Vector2(colw, 60.0))
	page.add_child(sub)

	var play := NeonButton.make("ابدأ اللعب", UIKit.COL_CYAN, true, Vector2(560.0, 132.0), 56, "play")
	UIKit.place(play, Vector2(1.0, 0.5), Vector2(left + (colw - 560.0) * 0.5, -6.0), Vector2(560.0, 132.0))
	play.pressed.connect(_on_play)
	page.add_child(play)
	var levels := NeonButton.make("المراحل", UIKit.COL_VIOLET, false, Vector2(460.0, 100.0), 44, "hex")
	UIKit.place(levels, Vector2(1.0, 0.5), Vector2(left + (colw - 460.0) * 0.5, 154.0), Vector2(460.0, 100.0))
	levels.pressed.connect(_on_levels)
	page.add_child(levels)
	var sets := NeonButton.make("الإعدادات", UIKit.COL_BLUE, false, Vector2(460.0, 100.0), 44, "gear")
	UIKit.place(sets, Vector2(1.0, 0.5), Vector2(left + (colw - 460.0) * 0.5, 272.0), Vector2(460.0, 100.0))
	sets.pressed.connect(_on_settings)
	page.add_child(sets)
	UIKit.pop_in(play, 0.05)
	UIKit.pop_in(levels, 0.12)
	UIKit.pop_in(sets, 0.19)

	var coins := StatPill.new()
	coins.kind = "gem"
	coins.col = UIKit.COL_GOLD
	coins.text = str(Game.total_coins())
	coins.custom_minimum_size = Vector2(230.0, 78.0)
	UIKit.place(coins, Vector2.ZERO, Vector2(m.x + 50.0, m.y + 40.0), Vector2(230.0, 78.0))
	page.add_child(coins)
	var bots := StatPill.new()
	bots.kind = "bot"
	bots.col = UIKit.COL_CYAN
	bots.text = str(Game.total_bots()) + " / " + str(Game.level_count() * 3)
	bots.custom_minimum_size = Vector2(250.0, 78.0)
	UIKit.place(bots, Vector2.ZERO, Vector2(m.x + 300.0, m.y + 40.0), Vector2(250.0, 78.0))
	page.add_child(bots)
	return page


func _on_play() -> void:
	# continue with the first level that is not finished yet
	var id: int = 1
	for i in range(1, Game.level_count() + 1):
		id = i
		if not bool(Game.level_record(i).get("done", false)):
			break
	_start(id)


func _on_levels() -> void:
	_show_page("levels")


func _on_settings() -> void:
	_show_page("settings")


func _start(id: int) -> void:
	if _busy:
		return
	_busy = true
	Sfx.play("ui_confirm")
	Game.vibrate(25)
	Game.main.start_level(id)


# ------------------------------------------------------------ level page
func _build_levels() -> Control:
	var page := Control.new()
	UIKit.fill(page)
	page.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var dim := ColorRect.new()
	UIKit.fill(dim)
	dim.color = Color(0.01, 0.02, 0.07, 0.55)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	page.add_child(dim)
	var m: Vector4 = UIKit.safe_margins(get_viewport())
	var title := UIKit.label("اختر المرحلة", 66, UIKit.COL_TEXT, HORIZONTAL_ALIGNMENT_CENTER, 8)
	UIKit.place(title, Vector2(0.5, 0.0), Vector2(-500.0, 56.0 + m.y), Vector2(1000.0, 100.0))
	page.add_child(title)
	var back := NeonButton.make("", UIKit.COL_PINK, false, Vector2(96.0, 96.0), 30, "arrow_left")
	UIKit.place(back, Vector2.ZERO, Vector2(m.x + 50.0, m.y + 50.0), Vector2(96.0, 96.0))
	back.pressed.connect(_on_back_button)
	page.add_child(back)

	var n: int = Game.level_count()
	var gap: float = 26.0
	var total: float = float(n) * CARD_W + float(n - 1) * gap
	var x0: float = -total * 0.5
	for i in range(n):
		var id: int = i + 1
		var meta: Dictionary = Game.level_meta(id)
		var card := LevelCard.new()
		card.meta = meta
		card.locked = not Game.is_unlocked(id)
		var rec: Dictionary = Game.level_record(id)
		card.bots = rec.get("bots", [false, false, false])
		card.done = bool(rec.get("done", false))
		card.best_time = float(rec.get("time", 0.0))
		card.build()
		UIKit.place(card, Vector2(0.5, 0.5), Vector2(x0 + float(i) * (CARD_W + gap), -CARD_H * 0.5 + 50.0), Vector2(CARD_W, CARD_H))
		card.pressed.connect(_on_card.bind(id, card))
		page.add_child(card)
		UIKit.pop_in(card, 0.05 + 0.07 * float(i), 0.5)
	return page


func _on_back_button() -> void:
	Sfx.play("ui_back")
	_show_page("main")


func _on_card(id: int, card: LevelCard) -> void:
	if card.locked:
		Sfx.play("ui_back")
		Game.vibrate(40)
		_toast("أكمل المرحلة السابقة أولاً")
		card.shake()
		return
	_start(id)


# --------------------------------------------------------- settings page
func _build_settings() -> Control:
	var page := Control.new()
	UIKit.fill(page)
	page.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var dim := ColorRect.new()
	UIKit.fill(dim)
	dim.color = Color(0.01, 0.02, 0.07, 0.6)
	page.add_child(dim)
	var sp := SettingsPanel.new()
	UIKit.place(sp, Vector2(0.5, 0.5), Vector2(-780.0, -400.0), Vector2(1560.0, 800.0))
	sp.closed.connect(_on_settings_closed)
	page.add_child(sp)
	UIKit.pop_in(sp, 0.0, 0.4)
	return page


func _on_settings_closed() -> void:
	Sfx.play("ui_back")
	_show_page("main")


# ------------------------------------------------------------ small parts
## Pill with an icon and a number (total gems / rescued bots).
class StatPill extends Control:
	var kind: String = "gem"
	var text: String = "0"
	var col: Color = Color(1.0, 0.82, 0.28)

	func _draw() -> void:
		var st: StyleBoxFlat = UIKit.panel_style(Color(0.03, 0.06, 0.16, 0.8), Color(col.r, col.g, col.b, 0.75), int(size.y * 0.5), 2, 10, Color(col.r, col.g, col.b, 0.25))
		draw_style_box(st, Rect2(Vector2.ZERO, size))
		UIIcons.draw(self, kind, Vector2(size.y * 0.52, size.y * 0.5), size.y * 0.28, col)
		draw_string(UIKit.font(), Vector2(size.y * 0.98, size.y * 0.5 + 14.0), text, HORIZONTAL_ALIGNMENT_LEFT, size.x - size.y - 16.0, 40, UIKit.COL_TEXT)


## Draws things that sit on top of a level card's planet and labels (bots row, best time, lock).
class CardFront extends Control:
	var card: Control

	func _draw() -> void:
		if card == null:
			return
		var meta: Dictionary = card.meta
		var accent: Color = meta.get("a", Color(0.3, 0.9, 1.0))
		var locked: bool = card.locked
		var w: float = size.x
		draw_line(Vector2(36.0, 548.0), Vector2(w - 36.0, 548.0), Color(accent.r, accent.g, accent.b, 0.35), 2.0)
		var bots: Array = card.bots
		for i in range(3):
			var found: bool = bool(bots[i]) if i < bots.size() else false
			var c: Color = UIKit.COL_CYAN if found else Color(0.4, 0.46, 0.6, 0.7)
			if locked:
				c = Color(0.3, 0.34, 0.45, 0.6)
			UIIcons.draw(self, "bot", Vector2(w * 0.5 + (float(i) - 1.0) * 70.0, 590.0), 24.0, c)
		if card.done and not locked:
			UIIcons.draw(self, "check", Vector2(w * 0.5 - 84.0, 628.0), 15.0, UIKit.COL_GREEN)
			draw_string(UIKit.font(), Vector2(w * 0.5 - 56.0, 640.0), Game.format_time(card.best_time), HORIZONTAL_ALIGNMENT_LEFT, 160.0, 34, UIKit.COL_TEXT)
		if locked:
			draw_rect(Rect2(Vector2.ZERO, size), Color(0.01, 0.02, 0.06, 0.45))
			UIIcons.draw(self, "lock", Vector2(w * 0.5, 60.0 + (w - 60.0) * 0.5 - 10.0), 50.0, Color(0.85, 0.9, 1.0, 0.95))


class LevelCard extends Control:
	signal pressed

	var meta: Dictionary = {}
	var locked: bool = false
	var bots: Array = [false, false, false]
	var done: bool = false
	var best_time: float = 0.0

	var _down: bool = false
	var _tw: Tween

	func build() -> void:
		custom_minimum_size = Vector2(MainMenu.CARD_W, MainMenu.CARD_H)
		size = custom_minimum_size
		var accent: Color = meta.get("a", Color(0.3, 0.9, 1.0))
		var atmo: Color = meta.get("atmo", Color(0.6, 0.95, 1.0))
		var col_b: Color = meta.get("b", Color(0.3, 0.3, 0.9))
		var border: Color = Color(accent.r, accent.g, accent.b, 0.35 if locked else 0.9)

		var bg := Panel.new()
		bg.add_theme_stylebox_override("panel", UIKit.panel_style(Color(0.035, 0.06, 0.15, 0.93), border, 44, 4, 26, Color(accent.r, accent.g, accent.b, 0.22)))
		bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
		bg.clip_children = CanvasItem.CLIP_CHILDREN_AND_DRAW
		UIKit.fill(bg)
		add_child(bg)
		var shine := ColorRect.new()
		var sm := ShaderMaterial.new()
		sm.shader = Mats.shader("res://shaders/ui_shine.gdshader")
		sm.set_shader_parameter("tint", Color(atmo.r, atmo.g, atmo.b, 1.0))
		sm.set_shader_parameter("speed", 0.18)
		sm.set_shader_parameter("strength", 0.13)
		shine.material = sm
		shine.mouse_filter = Control.MOUSE_FILTER_IGNORE
		UIKit.fill(shine)
		bg.add_child(shine)

		var planet := ColorRect.new()
		var pm := ShaderMaterial.new()
		pm.shader = Mats.shader("res://shaders/ui_planet.gdshader")
		pm.set_shader_parameter("col_a", accent)
		pm.set_shader_parameter("col_b", col_b)
		pm.set_shader_parameter("atmo", atmo)
		pm.set_shader_parameter("seed", float(meta.get("seed", 1.0)))
		pm.set_shader_parameter("ring_amount", float(meta.get("ring", 0.0)))
		pm.set_shader_parameter("locked", 1.0 if locked else 0.0)
		planet.material = pm
		planet.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var psz: float = MainMenu.CARD_W - 60.0
		UIKit.place(planet, Vector2.ZERO, Vector2(30.0, 60.0), Vector2(psz, psz))
		add_child(planet)

		var num := UIKit.label_ltr(str(int(meta.get("id", 1))), 60, accent, HORIZONTAL_ALIGNMENT_LEFT, 8)
		UIKit.place(num, Vector2.ZERO, Vector2(30.0, 16.0), Vector2(120.0, 76.0))
		add_child(num)
		if bool(meta.get("boss", false)):
			var badge := UIKit.panel(Color(0.5, 0.08, 0.16, 0.92), UIKit.COL_RED, 22, 2, 6)
			UIKit.place(badge, Vector2.ZERO, Vector2(MainMenu.CARD_W - 140.0, 26.0), Vector2(110.0, 46.0))
			add_child(badge)
			var bl := UIKit.label("زعيم", 28, Color(1.0, 0.8, 0.82))
			UIKit.fill(bl)
			badge.add_child(bl)

		var name_y: float = 60.0 + psz + 8.0
		var name_l := UIKit.label(str(meta.get("name", "")), 35, UIKit.COL_TEXT, HORIZONTAL_ALIGNMENT_CENTER, 5)
		UIKit.place(name_l, Vector2.ZERO, Vector2(8.0, name_y), Vector2(MainMenu.CARD_W - 16.0, 62.0))
		add_child(name_l)
		var desc := UIKit.wrap_label(str(meta.get("desc", "")), 24, UIKit.COL_DIM, MainMenu.CARD_W - 40.0)
		UIKit.place(desc, Vector2.ZERO, Vector2(20.0, name_y + 62.0), Vector2(MainMenu.CARD_W - 40.0, 96.0))
		desc.vertical_alignment = VERTICAL_ALIGNMENT_TOP
		add_child(desc)

		var front := CardFront.new()
		front.card = self
		front.mouse_filter = Control.MOUSE_FILTER_IGNORE
		UIKit.fill(front)
		add_child(front)

		if locked:
			var lk := UIKit.label("مقفلة", 34, Color(0.85, 0.9, 1.0), HORIZONTAL_ALIGNMENT_CENTER, 6)
			UIKit.place(lk, Vector2.ZERO, Vector2(12.0, 60.0 + psz * 0.5 + 40.0), Vector2(MainMenu.CARD_W - 24.0, 56.0))
			add_child(lk)
		pivot_offset = size * 0.5

	func shake() -> void:
		if _tw != null and _tw.is_valid():
			_tw.kill()
		_tw = create_tween()
		for i in range(4):
			var dx: float = 14.0 if i % 2 == 0 else -14.0
			_tw.tween_property(self, "rotation", deg_to_rad(dx * 0.25), 0.05)
		_tw.tween_property(self, "rotation", 0.0, 0.06)

	func _press_anim(down: bool) -> void:
		if _tw != null and _tw.is_valid():
			_tw.kill()
		_tw = create_tween()
		if down:
			_tw.tween_property(self, "scale", Vector2(0.96, 0.96), 0.06)
		else:
			_tw.tween_property(self, "scale", Vector2.ONE, 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

	func _gui_input(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				_down = true
				_press_anim(true)
			else:
				var was: bool = _down
				_down = false
				_press_anim(false)
				if was and Rect2(Vector2.ZERO, size).has_point(event.position):
					pressed.emit()
			accept_event()
