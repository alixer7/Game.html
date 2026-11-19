class_name UITheme
extends RefCounted
## Shared look for every menu / HUD element.

const ACCENT := Color(1.0, 0.42, 0.12)
const ACCENT2 := Color(0.2, 0.75, 1.0)
const BG := Color(0.05, 0.06, 0.08, 0.86)
const PANEL := Color(0.08, 0.09, 0.12, 0.92)
const TEXT := Color(0.95, 0.96, 0.98)
const DIM := Color(0.65, 0.68, 0.74)

static var _theme: Theme
static var _fonts := {}


static func font(weight := 600) -> Font:
	if _fonts.has(weight):
		return _fonts[weight]
	var base: FontFile = load("res://assets/fonts/Cairo.ttf")
	var fv := FontVariation.new()
	fv.base_font = base
	fv.variation_opentype = {"wght": weight}
	_fonts[weight] = fv
	return fv


static func theme() -> Theme:
	if _theme:
		return _theme
	var t := Theme.new()
	t.default_font = font(600)
	t.default_font_size = 22
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.13, 0.15, 0.19, 0.95)
	sb.set_corner_radius_all(14)
	sb.content_margin_left = 18
	sb.content_margin_right = 18
	sb.content_margin_top = 8
	sb.content_margin_bottom = 8
	sb.border_color = Color(1, 1, 1, 0.08)
	sb.set_border_width_all(1)
	var hover := sb.duplicate() as StyleBoxFlat
	hover.bg_color = Color(0.2, 0.22, 0.28, 0.98)
	hover.border_color = ACCENT
	var pressed := sb.duplicate() as StyleBoxFlat
	pressed.bg_color = ACCENT.darkened(0.25)
	var focus := sb.duplicate() as StyleBoxFlat
	focus.draw_center = false
	focus.border_color = ACCENT
	focus.set_border_width_all(2)
	for cls in ["Button", "OptionButton", "CheckButton"]:
		t.set_stylebox("normal", cls, sb)
		t.set_stylebox("hover", cls, hover)
		t.set_stylebox("pressed", cls, pressed)
		t.set_stylebox("focus", cls, focus)
		t.set_color("font_color", cls, TEXT)
		t.set_color("font_hover_color", cls, Color.WHITE)
		t.set_color("font_pressed_color", cls, Color.WHITE)
	var panel := StyleBoxFlat.new()
	panel.bg_color = PANEL
	panel.set_corner_radius_all(18)
	panel.content_margin_left = 22
	panel.content_margin_right = 22
	panel.content_margin_top = 16
	panel.content_margin_bottom = 16
	panel.shadow_color = Color(0, 0, 0, 0.4)
	panel.shadow_size = 12
	t.set_stylebox("panel", "PanelContainer", panel)
	t.set_stylebox("panel", "Panel", panel)
	t.set_color("font_color", "Label", TEXT)
	var grabber := StyleBoxFlat.new()
	grabber.bg_color = ACCENT
	grabber.set_corner_radius_all(8)
	var track := StyleBoxFlat.new()
	track.bg_color = Color(1, 1, 1, 0.15)
	track.set_corner_radius_all(6)
	track.content_margin_top = 6
	track.content_margin_bottom = 6
	t.set_stylebox("slider", "HSlider", track)
	t.set_stylebox("grabber_area", "HSlider", grabber)
	t.set_stylebox("grabber_area_highlight", "HSlider", grabber)
	var sc := StyleBoxFlat.new()
	sc.bg_color = Color(1, 1, 1, 0.12)
	sc.set_corner_radius_all(4)
	t.set_stylebox("scroll", "VScrollBar", sc)
	_theme = t
	return t


static func label(text: String, size := 22, weight := 600, color := TEXT) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", font(weight))
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.6))
	l.add_theme_constant_override("shadow_offset_x", 1)
	l.add_theme_constant_override("shadow_offset_y", 2)
	return l


static func button(text: String, size := 24, min_w := 260.0) -> Button:
	var b := Button.new()
	b.text = text
	b.add_theme_font_size_override("font_size", size)
	b.custom_minimum_size = Vector2(min_w, 58)
	b.focus_mode = Control.FOCUS_NONE
	return b
