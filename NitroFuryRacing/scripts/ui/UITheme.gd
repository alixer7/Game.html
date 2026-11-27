class_name UITheme
extends RefCounted

## CTR-Inspired Vibrant Cartoon Mobile UI Styling Helpers.
## Bold dark ink borders, warm nitro gradients, punchy shadows, crisp Arabic+Latin typography.

static var _font_bold: Font = null
static var _font_black: Font = null

static func font_bold() -> Font:
	if _font_bold == null:
		_font_bold = load("res://assets/fonts/Cairo-Bold.ttf")
	return _font_bold

static func font_black() -> Font:
	if _font_black == null:
		_font_black = load("res://assets/fonts/Cairo-Black.ttf")
	return _font_black

static func panel_box(bg: Color, border: Color = Color(0.10, 0.05, 0.02), radius: int = 16, border_w: int = 4, shadow_sz: int = 6) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(border_w)
	sb.set_corner_radius_all(radius)
	sb.shadow_color = Color(0.0, 0.0, 0.0, 0.48)
	sb.shadow_size = shadow_sz
	sb.shadow_offset = Vector2(0, 4)
	sb.content_margin_left = 14
	sb.content_margin_right = 14
	sb.content_margin_top = 10
	sb.content_margin_bottom = 10
	return sb

static func style_button(btn: Button, fill: Color, text_col: Color = Color.WHITE, font_sz: int = 24, radius: int = 16) -> void:
	btn.add_theme_font_override("font", font_black())
	btn.add_theme_font_size_override("font_size", font_sz)
	btn.add_theme_color_override("font_color", text_col)
	btn.add_theme_color_override("font_hover_color", Color(1.0, 0.98, 0.78))
	btn.add_theme_color_override("font_pressed_color", Color(1.0, 0.92, 0.45))
	btn.add_theme_color_override("font_outline_color", Color(0.08, 0.04, 0.02))
	btn.add_theme_constant_override("outline_size", 6)

	var normal := panel_box(fill, Color(0.10, 0.04, 0.02), radius, 4, 6)
	normal.border_width_bottom = 8
	var hover := panel_box(fill.lightened(0.12), Color(1.0, 0.90, 0.35), radius, 4, 8)
	hover.border_width_bottom = 8
	var pressed := panel_box(fill.darkened(0.15), Color(1.0, 0.85, 0.20), radius, 4, 2)
	pressed.border_width_bottom = 4
	pressed.content_margin_top = 13
	btn.add_theme_stylebox_override("normal", normal)
	btn.add_theme_stylebox_override("hover", hover)
	btn.add_theme_stylebox_override("pressed", pressed)
	btn.add_theme_stylebox_override("focus", hover)

static func style_label(lbl: Label, sz: int = 24, col: Color = Color.WHITE, outline_sz: int = 6, use_black: bool = true) -> void:
	lbl.add_theme_font_override("font", font_black() if use_black else font_bold())
	lbl.add_theme_font_size_override("font_size", sz)
	lbl.add_theme_color_override("font_color", col)
	lbl.add_theme_color_override("font_outline_color", Color(0.06, 0.03, 0.01))
	lbl.add_theme_constant_override("outline_size", outline_sz)
	lbl.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.55))
	lbl.add_theme_constant_override("shadow_offset_x", 2)
	lbl.add_theme_constant_override("shadow_offset_y", 3)

static func make_label(text_str: String, sz: int = 24, col: Color = Color.WHITE, align: HorizontalAlignment = HORIZONTAL_ALIGNMENT_LEFT, outline_sz: int = 6) -> Label:
	var l := Label.new()
	l.text = text_str
	l.horizontal_alignment = align
	style_label(l, sz, col, outline_sz)
	return l
