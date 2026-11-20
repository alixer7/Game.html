class_name UIKit
extends RefCounted
## أدوات الواجهة: السمة (الألوان والخطوط والحواف) ودوال إنشاء العناصر بسرعة.

const GOLD := Color(0.93, 0.76, 0.42)
const TEXT := Color(0.95, 0.92, 0.85)
const DIM := Color(0.7, 0.68, 0.62)
const BG := Color(0.07, 0.075, 0.085, 0.92)
const GOOD := Color(0.55, 0.95, 0.55)
const BAD := Color(1.0, 0.45, 0.4)

static var _theme: Theme = null

static func sb(bg: Color, radius := 12, border := 0, bc := Color(0, 0, 0, 0), margin := 10) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.set_corner_radius_all(radius)
	s.set_border_width_all(border)
	s.border_color = bc
	s.content_margin_left = margin
	s.content_margin_right = margin
	s.content_margin_top = margin * 0.7
	s.content_margin_bottom = margin * 0.7
	s.anti_aliasing = true
	return s

static func theme() -> Theme:
	if _theme != null:
		return _theme
	var t := Theme.new()
	t.default_font_size = 22
	t.set_stylebox("panel", "PanelContainer", sb(BG, 16, 2, Color(0.85, 0.68, 0.38, 0.35), 14))
	t.set_stylebox("panel", "Panel", sb(BG, 16, 2, Color(0.85, 0.68, 0.38, 0.35), 14))
	t.set_stylebox("normal", "Button", sb(Color(0.2, 0.18, 0.15, 0.95), 10, 1, Color(1, 1, 1, 0.08), 12))
	t.set_stylebox("hover", "Button", sb(Color(0.27, 0.24, 0.19, 0.98), 10, 1, Color(1, 0.85, 0.5, 0.25), 12))
	t.set_stylebox("pressed", "Button", sb(Color(0.45, 0.34, 0.18, 1.0), 10, 2, GOLD, 12))
	t.set_stylebox("disabled", "Button", sb(Color(0.13, 0.13, 0.13, 0.75), 10, 0, Color(0, 0, 0, 0), 12))
	t.set_stylebox("focus", "Button", sb(Color(0, 0, 0, 0), 10, 2, Color(1, 0.85, 0.5, 0.4), 12))
	t.set_color("font_color", "Button", TEXT)
	t.set_color("font_hover_color", "Button", Color(1, 0.95, 0.85))
	t.set_color("font_pressed_color", "Button", Color(1, 0.95, 0.8))
	t.set_color("font_disabled_color", "Button", Color(0.5, 0.5, 0.5))
	t.set_color("font_color", "Label", TEXT)
	t.set_color("font_outline_color", "Label", Color(0, 0, 0, 0.85))
	t.set_constant("outline_size", "Label", 4)
	t.set_color("default_color", "RichTextLabel", TEXT)
	t.set_stylebox("background", "ProgressBar", sb(Color(0, 0, 0, 0.55), 6, 0, Color(0, 0, 0, 0), 0))
	t.set_stylebox("fill", "ProgressBar", sb(GOLD, 6, 0, Color(0, 0, 0, 0), 0))
	var grab := sb(Color(0.85, 0.7, 0.4, 0.8), 8, 0, Color(0, 0, 0, 0), 0)
	grab.content_margin_left = 10
	grab.content_margin_right = 10
	t.set_stylebox("grabber", "VScrollBar", grab)
	t.set_stylebox("grabber_highlight", "VScrollBar", grab)
	t.set_stylebox("grabber_pressed", "VScrollBar", grab)
	t.set_stylebox("scroll", "VScrollBar", sb(Color(0, 0, 0, 0.3), 8, 0, Color(0, 0, 0, 0), 6))
	t.set_stylebox("grabber", "HScrollBar", grab)
	t.set_stylebox("grabber_highlight", "HScrollBar", grab)
	t.set_stylebox("scroll", "HScrollBar", sb(Color(0, 0, 0, 0.3), 8, 0, Color(0, 0, 0, 0), 6))
	t.set_stylebox("slider", "HSlider", sb(Color(0, 0, 0, 0.5), 6, 0, Color(0, 0, 0, 0), 4))
	t.set_stylebox("grabber_area", "HSlider", sb(GOLD, 6, 0, Color(0, 0, 0, 0), 4))
	t.set_stylebox("grabber_area_highlight", "HSlider", sb(GOLD, 6, 0, Color(0, 0, 0, 0), 4))
	_theme = t
	return t

static func label(text: String, size := 22, col := TEXT, align := HORIZONTAL_ALIGNMENT_RIGHT) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	l.horizontal_alignment = align
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l

static func button(text: String, cb: Callable, size := 22, min_h := 56) -> Button:
	var b := Button.new()
	b.text = text
	b.add_theme_font_size_override("font_size", size)
	b.custom_minimum_size = Vector2(0, min_h)
	b.mouse_filter = Control.MOUSE_FILTER_PASS
	b.focus_mode = Control.FOCUS_NONE
	if cb.is_valid():
		b.pressed.connect(cb)
		b.pressed.connect(func(): Sfx.play("click"))
	return b

static func hbox(sep := 10) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", sep)
	return h

static func vbox(sep := 8) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", sep)
	return v

static func scroll() -> ScrollContainer:
	var s := ScrollContainer.new()
	s.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	s.size_flags_vertical = Control.SIZE_EXPAND_FILL
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.scroll_deadzone = 12
	return s

static func bar(col: Color, h := 14) -> ProgressBar:
	var p := ProgressBar.new()
	p.show_percentage = false
	p.custom_minimum_size = Vector2(80, h)
	p.max_value = 100.0
	p.add_theme_stylebox_override("fill", sb(col, 6, 0, Color(0, 0, 0, 0), 0))
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return p

static func sep() -> HSeparator:
	var s := HSeparator.new()
	s.add_theme_constant_override("separation", 10)
	return s
