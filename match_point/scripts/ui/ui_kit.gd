class_name UiKit
extends RefCounted
## أدوات الواجهة: الخطوط العربية والأنماط الموحّدة.

static var _bold: Font
static var _reg: Font

const ACCENT := Color(0.84, 0.93, 0.22)       # أصفر كرة التنس
const PANEL := Color(0.04, 0.07, 0.13, 0.86)
const PANEL_SOLID := Color(0.05, 0.08, 0.15, 0.97)
const TEXT := Color(0.95, 0.96, 0.98)
const MUTED := Color(0.66, 0.71, 0.80)


static func font_bold() -> Font:
	if _bold == null:
		var f: FontFile = load("res://assets/fonts/cairo_arabic_800.ttf")
		var l: FontFile = load("res://assets/fonts/cairo_latin_800.ttf")
		f.fallbacks = [l]
		_bold = f
	return _bold


static func font_reg() -> Font:
	if _reg == null:
		var f: FontFile = load("res://assets/fonts/cairo_arabic_600.ttf")
		var l: FontFile = load("res://assets/fonts/cairo_latin_600.ttf")
		f.fallbacks = [l]
		_reg = f
	return _reg


static func box(color: Color, radius: int = 14, border: Color = Color(0, 0, 0, 0), bw: int = 0) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = color
	s.set_corner_radius_all(radius)
	s.border_color = border
	s.set_border_width_all(bw)
	s.content_margin_left = 16
	s.content_margin_right = 16
	s.content_margin_top = 8
	s.content_margin_bottom = 8
	s.anti_aliasing = true
	return s


static func label(text: String, size: int = 22, color: Color = TEXT, bold: bool = true) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", font_bold() if bold else font_reg())
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


static func button(text: String, size: int = 24, primary: bool = false) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_override("font", font_bold())
	b.add_theme_font_size_override("font_size", size)
	var base := ACCENT if primary else Color(0.12, 0.17, 0.28, 0.96)
	var fg := Color(0.05, 0.08, 0.12) if primary else TEXT
	b.add_theme_stylebox_override("normal", box(base, 16, Color(1, 1, 1, 0.10), 1))
	b.add_theme_stylebox_override("hover", box(base.lightened(0.08), 16, Color(1, 1, 1, 0.18), 1))
	b.add_theme_stylebox_override("pressed", box(base.darkened(0.18), 16, Color(1, 1, 1, 0.18), 1))
	b.add_theme_stylebox_override("disabled", box(Color(0.1, 0.12, 0.16, 0.7), 16))
	for st in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		b.add_theme_color_override(st, fg)
	b.custom_minimum_size = Vector2(0, 58)
	return b


static func panel(color: Color = PANEL, radius: int = 18) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", box(color, radius, Color(1, 1, 1, 0.08), 1))
	return p
