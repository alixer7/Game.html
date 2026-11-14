class_name UiTheme
extends RefCounted
## Shared fonts, colours and style boxes for the UI.

const BLUE := Color(0.16, 0.5, 1.0)
const ORANGE := Color(1.0, 0.5, 0.1)
const PANEL := Color(0.04, 0.06, 0.11, 0.86)
const PANEL_LIGHT := Color(0.09, 0.12, 0.2, 0.92)
const ACCENT := Color(0.25, 0.85, 1.0)
const TEXT := Color(0.94, 0.96, 1.0)
const TEXT_DIM := Color(0.62, 0.68, 0.8)

static var _bold: FontFile
static var _black: FontFile
static var _theme: Theme


static func font_bold() -> Font:
	if _bold == null:
		_bold = load("res://assets/fonts/Cairo-Bold.ttf")
	return _bold


static func font_black() -> Font:
	if _black == null:
		_black = load("res://assets/fonts/Cairo-Black.ttf")
	return _black


static func box(bg: Color, radius: int = 14, border: Color = Color(0, 0, 0, 0), border_w: int = 0) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.set_corner_radius_all(radius)
	if border_w > 0:
		sb.border_color = border
		sb.set_border_width_all(border_w)
	sb.content_margin_left = 18
	sb.content_margin_right = 18
	sb.content_margin_top = 8
	sb.content_margin_bottom = 8
	sb.anti_aliasing = true
	return sb


static func theme() -> Theme:
	if _theme:
		return _theme
	var t := Theme.new()
	t.default_font = font_bold()
	t.default_font_size = 24
	t.set_color("font_color", "Label", TEXT)
	t.set_color("font_outline_color", "Label", Color(0, 0, 0, 0.6))
	t.set_constant("outline_size", "Label", 0)
	# Buttons
	t.set_stylebox("normal", "Button", box(PANEL_LIGHT, 14, Color(1, 1, 1, 0.08), 2))
	t.set_stylebox("hover", "Button", box(Color(0.14, 0.2, 0.32, 0.95), 14, ACCENT * Color(1, 1, 1, 0.6), 2))
	t.set_stylebox("pressed", "Button", box(Color(0.1, 0.35, 0.55, 0.95), 14, ACCENT, 2))
	t.set_stylebox("focus", "Button", box(Color(0, 0, 0, 0), 14, ACCENT * Color(1, 1, 1, 0.5), 2))
	t.set_stylebox("disabled", "Button", box(Color(0.06, 0.07, 0.1, 0.7), 14))
	t.set_color("font_color", "Button", TEXT)
	t.set_color("font_hover_color", "Button", Color.WHITE)
	t.set_color("font_pressed_color", "Button", Color.WHITE)
	t.set_color("font_focus_color", "Button", Color.WHITE)
	t.set_font_size("font_size", "Button", 26)
	t.set_stylebox("panel", "PanelContainer", box(PANEL, 22, Color(1, 1, 1, 0.07), 2))
	t.set_stylebox("panel", "Panel", box(PANEL, 22))
	# Sliders
	var track := box(Color(1, 1, 1, 0.12), 6)
	track.content_margin_top = 4
	track.content_margin_bottom = 4
	t.set_stylebox("slider", "HSlider", track)
	var fill := box(ACCENT * Color(1, 1, 1, 0.85), 6)
	fill.content_margin_top = 4
	fill.content_margin_bottom = 4
	t.set_stylebox("grabber_area", "HSlider", fill)
	t.set_stylebox("grabber_area_highlight", "HSlider", fill)
	t.set_icon("grabber", "HSlider", _circle_tex(26, Color.WHITE))
	t.set_icon("grabber_highlight", "HSlider", _circle_tex(30, Color.WHITE))
	# Check buttons
	t.set_color("font_color", "CheckButton", TEXT)
	t.set_font_size("font_size", "CheckButton", 22)
	var empty := StyleBoxEmpty.new()
	t.set_stylebox("normal", "CheckButton", empty)
	t.set_stylebox("hover", "CheckButton", empty)
	t.set_stylebox("pressed", "CheckButton", empty)
	t.set_stylebox("focus", "CheckButton", empty)
	t.set_stylebox("hover_pressed", "CheckButton", empty)
	var on_tex := _switch_tex(true)
	var off_tex := _switch_tex(false)
	for nm in ["checked", "checked_mirrored"]:
		t.set_icon(nm, "CheckButton", on_tex)
	for nm in ["unchecked", "unchecked_mirrored"]:
		t.set_icon(nm, "CheckButton", off_tex)
	t.set_constant("h_separation", "CheckButton", 16)
	# Scroll
	t.set_stylebox("panel", "ScrollContainer", StyleBoxEmpty.new())
	_theme = t
	return t


static func _switch_tex(on: bool) -> Texture2D:
	var w := 76
	var h := 40
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	var track := ACCENT if on else Color(0.3, 0.33, 0.4)
	var r := h * 0.5
	for y in range(h):
		for x in range(w):
			var cx := clampf(x, r, w - r)
			var d := Vector2(x - cx, y - r + 0.5).length()
			var a := clampf(r - d, 0.0, 1.0)
			var col := track
			var kx := (w - r) if on else r
			var kd := Vector2(x - kx, y - r + 0.5).length()
			var ka := clampf(r - 5.0 - kd, 0.0, 1.0)
			col = col.lerp(Color.WHITE, ka)
			img.set_pixel(x, y, Color(col.r, col.g, col.b, a))
	return ImageTexture.create_from_image(img)


static func _circle_tex(size: int, col: Color) -> Texture2D:
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var c := (size - 1) * 0.5
	for y in range(size):
		for x in range(size):
			var d := Vector2(x - c, y - c).length()
			var a := clampf(c - d + 0.5, 0.0, 1.0)
			img.set_pixel(x, y, Color(col.r, col.g, col.b, a))
	return ImageTexture.create_from_image(img)


static func label(text: String, size: int = 24, col: Color = TEXT, black: bool = false) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	if black:
		l.add_theme_font_override("font", font_black())
	return l
