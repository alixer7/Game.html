class_name SettingsPanel
extends Control
## Two-column settings sheet (sound, graphics, camera, touch layout). Emits `closed`.

signal closed

const PW := 1560.0
const PH := 800.0
const COL_L := 70.0
const COL_R := 800.0


func _init() -> void:
	layout_direction = Control.LAYOUT_DIRECTION_LTR
	custom_minimum_size = Vector2(PW, PH)
	size = Vector2(PW, PH)
	_build()


func _exit_tree() -> void:
	Game.save_all()


func _build() -> void:
	var cy: Color = UIKit.COL_CYAN
	var bg := UIKit.panel(UIKit.COL_PANEL, Color(cy.r, cy.g, cy.b, 0.7), 36, 3, 28)
	UIKit.fill(bg)
	add_child(bg)
	var title := UIKit.label("الإعدادات", 58, UIKit.COL_TEXT, HORIZONTAL_ALIGNMENT_CENTER, 6)
	UIKit.place(title, Vector2.ZERO, Vector2(0.0, 26.0), Vector2(PW, 80.0))
	add_child(title)
	var close := NeonButton.make("", UIKit.COL_PINK, false, Vector2(84, 84), 30, "close")
	UIKit.place(close, Vector2.ZERO, Vector2(PW - 120.0, 22.0), Vector2(84, 84))
	close.pressed.connect(_on_close)
	add_child(close)

	_add_slider(COL_L, 0, "الموسيقى", "music", 0.0, 1.0, UIKit.COL_VIOLET)
	_add_slider(COL_L, 1, "المؤثرات الصوتية", "sfx", 0.0, 1.0, UIKit.COL_VIOLET)
	_add_segment(COL_L, 2, "جودة الرسوم", "quality", ["منخفضة", "متوسطة", "عالية"], UIKit.COL_GREEN)
	_add_slider(COL_L, 3, "حساسية الكاميرا", "cam_sens", 0.4, 2.0, UIKit.COL_CYAN)
	_add_segment(COL_L, 4, "مساعد الكاميرا", "cam_assist", ["إيقاف", "عادي", "قوي"], UIKit.COL_CYAN)
	_add_toggle(COL_L, 5, "عكس المحور الرأسي", "invert_y", UIKit.COL_CYAN)

	_add_slider(COL_R, 0, "حجم عصا التحكم", "stick_scale", 0.7, 1.4, UIKit.COL_GOLD)
	_add_slider(COL_R, 1, "حجم الأزرار", "btn_scale", 0.7, 1.4, UIKit.COL_GOLD)
	_add_slider(COL_R, 2, "شفافية الواجهة", "ui_opacity", 0.3, 1.0, UIKit.COL_GOLD)
	_add_toggle(COL_R, 3, "عصا تحكم ثابتة", "fixed_stick", UIKit.COL_GOLD)
	_add_toggle(COL_R, 4, "الاهتزاز", "vibration", UIKit.COL_PINK)
	_add_toggle(COL_R, 5, "عرض الإطارات FPS", "show_fps", UIKit.COL_PINK)


func _row_y(row: int) -> float:
	return 134.0 + row * 108.0


func _row_label(text: String, col_x: float, y: float) -> void:
	var l := UIKit.label(text, 34, UIKit.COL_TEXT, HORIZONTAL_ALIGNMENT_RIGHT)
	UIKit.place(l, Vector2.ZERO, Vector2(col_x + 370.0, y), Vector2(320.0, 70.0))
	add_child(l)


func _add_slider(col_x: float, row: int, text: String, key: String, lo: float, hi: float, col: Color) -> void:
	var y: float = _row_y(row)
	_row_label(text, col_x, y)
	var cur: float = float(Game.settings.get(key, lo))
	var s := NeonSlider.make(inverse_lerp(lo, hi, cur), col, Vector2(360, 70))
	UIKit.place(s, Vector2.ZERO, Vector2(col_x, y), Vector2(360.0, 70.0))
	s.value_changed.connect(_on_slider.bind(key, lo, hi))
	add_child(s)


func _add_toggle(col_x: float, row: int, text: String, key: String, col: Color) -> void:
	var y: float = _row_y(row)
	_row_label(text, col_x, y)
	var t := NeonToggle.make(bool(Game.settings.get(key, false)), col)
	UIKit.place(t, Vector2.ZERO, Vector2(col_x + 236.0, y + 4.0), Vector2(124.0, 62.0))
	t.toggled.connect(_on_toggle.bind(key))
	add_child(t)


func _add_segment(col_x: float, row: int, text: String, key: String, opts: Array, col: Color) -> void:
	var y: float = _row_y(row)
	_row_label(text, col_x, y)
	var s := NeonSegment.make(opts, int(Game.settings.get(key, 0)), col, Vector2(360, 64), 24)
	UIKit.place(s, Vector2.ZERO, Vector2(col_x, y + 3.0), Vector2(360.0, 64.0))
	s.changed.connect(_on_segment.bind(key))
	add_child(s)


func _on_slider(v: float, key: String, lo: float, hi: float) -> void:
	Game.settings[key] = snappedf(lerpf(lo, hi, v), 0.01)
	Game.settings_changed.emit()


func _on_toggle(on: bool, key: String) -> void:
	Game.set_setting(key, on)
	if key == "vibration" and on:
		Game.vibrate(40)


func _on_segment(idx: int, key: String) -> void:
	Game.set_setting(key, idx)


func _on_close() -> void:
	Game.save_all()
	Sfx.play("ui_back")
	closed.emit()
