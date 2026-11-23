class_name UIKit
extends RefCounted
## Shared look & widget helpers for all menus / HUD.

const ORANGE := Color(1.0, 0.56, 0.16)
const TEAL := Color(0.1, 0.82, 0.86)
const CREAM := Color(1.0, 0.96, 0.86)
const INK := Color(0.07, 0.09, 0.14)
const PANEL := Color(0.08, 0.11, 0.17, 0.86)

static var _theme: Theme


static func theme() -> Theme:
	if _theme:
		return _theme
	var t := Theme.new()
	t.default_font_size = 26
	var normal := _box(Color(0.13, 0.17, 0.26, 0.95), Color(0.3, 0.38, 0.55), 18)
	var hover := _box(Color(0.2, 0.26, 0.4, 0.98), ORANGE, 18)
	var pressed := _box(ORANGE.darkened(0.2), CREAM, 18)
	var focus := _box(Color(0.2, 0.26, 0.4, 0.98), TEAL, 18)
	for cls: String in ["Button", "OptionButton", "CheckButton"]:
		t.set_stylebox("normal", cls, normal)
		t.set_stylebox("hover", cls, hover)
		t.set_stylebox("pressed", cls, pressed)
		t.set_stylebox("focus", cls, focus)
		t.set_color("font_color", cls, CREAM)
		t.set_color("font_hover_color", cls, Color.WHITE)
		t.set_color("font_pressed_color", cls, INK)
		t.set_font_size("font_size", cls, 28)
	t.set_stylebox("panel", "PanelContainer", _box(PANEL, Color(1, 1, 1, 0.08), 24))
	t.set_color("font_color", "Label", CREAM)
	var grab := StyleBoxFlat.new()
	grab.bg_color = ORANGE
	grab.set_corner_radius_all(12)
	t.set_stylebox("slider", "HSlider", _box(Color(0.2, 0.24, 0.32), Color(0, 0, 0, 0), 8, 6))
	t.set_stylebox("grabber_area", "HSlider", _box(ORANGE, Color(0, 0, 0, 0), 8, 6))
	t.set_stylebox("grabber_area_highlight", "HSlider", _box(ORANGE.lightened(0.2), Color(0, 0, 0, 0), 8, 6))
	_theme = t
	return t


static func _box(bg: Color, border: Color, radius: int, pad := 14) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(2 if border.a > 0.0 else 0)
	s.set_corner_radius_all(radius)
	s.content_margin_left = pad + 8
	s.content_margin_right = pad + 8
	s.content_margin_top = pad
	s.content_margin_bottom = pad
	s.shadow_color = Color(0, 0, 0, 0.25)
	s.shadow_size = 4
	return s


static func label(text: String, size := 28, color := CREAM, outline := 8) -> Label:
	var l := Label.new()
	l.text = text
	var ls := LabelSettings.new()
	ls.font_size = size
	ls.font_color = color
	ls.outline_size = outline
	ls.outline_color = Color(0.05, 0.06, 0.1, 0.9)
	ls.shadow_size = 0
	l.label_settings = ls
	return l


static func button(text: String, cb: Callable, min_w := 320) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(min_w, 72)
	b.pressed.connect(func() -> void:
		Sfx.play("click")
		cb.call())
	return b


static func slider(min_v: float, max_v: float, step: float, value: float, cb: Callable) -> HSlider:
	var s := HSlider.new()
	s.min_value = min_v
	s.max_value = max_v
	s.step = step
	s.value = value
	s.custom_minimum_size = Vector2(360, 48)
	s.value_changed.connect(cb)
	return s


static func row(title: String, control: Control) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 24)
	var l := label(title, 26)
	l.custom_minimum_size = Vector2(320, 0)
	h.add_child(l)
	control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(control)
	return h


static func toggle(value: bool, cb: Callable) -> CheckButton:
	var c := CheckButton.new()
	c.button_pressed = value
	c.toggled.connect(cb)
	return c


static func options(items: Array, selected: int, cb: Callable) -> OptionButton:
	var o := OptionButton.new()
	for it in items:
		o.add_item(str(it))
	o.select(selected)
	o.item_selected.connect(cb)
	o.custom_minimum_size = Vector2(300, 64)
	return o


static func safe_margins(ctrl: Control) -> void:
	## Inset a full-rect control by the device safe area (notches, rounded corners).
	var win := DisplayServer.window_get_size()
	var safe := DisplayServer.get_display_safe_area()
	if win.x <= 0 or safe.size.x <= 0:
		return
	var vp := ctrl.get_viewport_rect().size
	var sx := vp.x / float(win.x)
	var sy := vp.y / float(win.y)
	ctrl.offset_left = maxf(safe.position.x * sx, 12.0)
	ctrl.offset_top = maxf(safe.position.y * sy, 8.0)
	ctrl.offset_right = -maxf((win.x - safe.end.x) * sx, 12.0)
	ctrl.offset_bottom = -maxf((win.y - safe.end.y) * sy, 8.0)
