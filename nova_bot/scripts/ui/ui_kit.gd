class_name UIKit
extends RefCounted
## Static helpers for building the neon / glass UI from code (fonts, labels, panels, layout).

const COL_BG := Color(0.03, 0.05, 0.13, 0.86)
const COL_PANEL := Color(0.05, 0.08, 0.19, 0.92)
const COL_CYAN := Color(0.25, 0.9, 1.0)
const COL_BLUE := Color(0.3, 0.55, 1.0)
const COL_VIOLET := Color(0.66, 0.42, 1.0)
const COL_PINK := Color(1.0, 0.36, 0.78)
const COL_GOLD := Color(1.0, 0.82, 0.28)
const COL_GREEN := Color(0.35, 1.0, 0.62)
const COL_RED := Color(1.0, 0.32, 0.38)
const COL_TEXT := Color(0.94, 0.97, 1.0)
const COL_DIM := Color(0.62, 0.72, 0.88)

static var _font: Font = null


static func font() -> Font:
	if _font == null:
		_font = load("res://assets/fonts/DejaVuSans-Bold.ttf")
	return _font


static func label(text: String, size: int = 32, color: Color = COL_TEXT, align: HorizontalAlignment = HORIZONTAL_ALIGNMENT_CENTER, outline: int = 0) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = align
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.text_direction = Control.TEXT_DIRECTION_AUTO
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.add_theme_font_override("font", font())
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	if outline > 0:
		l.add_theme_constant_override("outline_size", outline)
		l.add_theme_color_override("font_outline_color", Color(0.02, 0.04, 0.12, 0.95))
	return l


## Label for numbers / times / Latin text: always left-to-right, even on Arabic-locale devices.
static func label_ltr(text: String, size: int = 32, color: Color = COL_TEXT, align: HorizontalAlignment = HORIZONTAL_ALIGNMENT_CENTER, outline: int = 0) -> Label:
	var l := label(text, size, color, align, outline)
	l.text_direction = Control.TEXT_DIRECTION_LTR
	return l


## Notch / gesture-bar margins converted to virtual canvas pixels: x=left, y=top, z=right, w=bottom.
static func safe_margins(vp: Viewport) -> Vector4:
	var m := Vector4.ZERO
	if not OS.has_feature("mobile"):
		return m
	var sa: Rect2i = DisplayServer.get_display_safe_area()
	var scr: Vector2i = DisplayServer.screen_get_size()
	if scr.x <= 0 or scr.y <= 0:
		return m
	var vs: Vector2 = vp.get_visible_rect().size
	var kx: float = vs.x / float(scr.x)
	var ky: float = vs.y / float(scr.y)
	m.x = maxf(float(sa.position.x) * kx, 0.0)
	m.y = maxf(float(sa.position.y) * ky, 0.0)
	m.z = maxf(float(scr.x - sa.end.x) * kx, 0.0)
	m.w = maxf(float(scr.y - sa.end.y) * ky, 0.0)
	return m


static func wrap_label(text: String, size: int, color: Color, width: float, align: HorizontalAlignment = HORIZONTAL_ALIGNMENT_CENTER) -> Label:
	var l := label(text, size, color, align)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(width, 0)
	return l


static func panel_style(bg: Color, border: Color = Color(0, 0, 0, 0), radius: int = 24, border_w: int = 0, shadow: int = 0, shadow_col: Color = Color(0, 0, 0, 0.45)) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.set_corner_radius_all(radius)
	s.border_color = border
	s.set_border_width_all(border_w)
	s.shadow_size = shadow
	s.shadow_color = shadow_col
	s.anti_aliasing = true
	return s


static func panel(bg: Color, border: Color = Color(0, 0, 0, 0), radius: int = 24, border_w: int = 0, shadow: int = 0) -> Panel:
	var p := Panel.new()
	p.add_theme_stylebox_override("panel", panel_style(bg, border, radius, border_w, shadow))
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return p


static func fill(c: Control) -> void:
	c.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


## Absolute placement: anchor point (0..1), offset of the top-left corner from that point, and size.
static func place(c: Control, anchor: Vector2, pos: Vector2, sz: Vector2) -> void:
	c.anchor_left = anchor.x
	c.anchor_right = anchor.x
	c.anchor_top = anchor.y
	c.anchor_bottom = anchor.y
	c.offset_left = pos.x
	c.offset_top = pos.y
	c.offset_right = pos.x + sz.x
	c.offset_bottom = pos.y + sz.y


static func vbox(sep: int = 14) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", sep)
	return v


static func hbox(sep: int = 14) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", sep)
	return h


static func spacer(w: float, h: float) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(w, h)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c


## Pop-in animation (fade + scale with overshoot).
static func pop_in(node: Control, delay: float = 0.0, dur: float = 0.45) -> void:
	var sz: Vector2 = node.size
	if sz.length() < 1.0:
		sz = node.custom_minimum_size
	node.pivot_offset = sz / 2.0
	node.modulate.a = 0.0
	node.scale = Vector2(0.86, 0.86)
	var tw := node.create_tween()
	tw.set_parallel(true)
	tw.tween_property(node, "modulate:a", 1.0, dur * 0.7).set_delay(delay)
	tw.tween_property(node, "scale", Vector2.ONE, dur).set_delay(delay).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


static func fade_in(node: CanvasItem, delay: float = 0.0, dur: float = 0.4) -> void:
	node.modulate.a = 0.0
	var tw := node.create_tween()
	tw.tween_property(node, "modulate:a", 1.0, dur).set_delay(delay)
