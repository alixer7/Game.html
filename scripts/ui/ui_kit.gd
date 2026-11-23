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


static func safe_insets(vp: Viewport) -> Rect2:
	## Insets (left, top, right, bottom packed as position=(l,t), size=(r,b)) in
	## canvas units that keep UI clear of notches, punch-hole cameras, rounded
	## corners and system bars. Re-read on every resize (Android rotates the
	## window to landscape after start-up). WK_SAFE_INSET="l,t,r,b" (window px)
	## simulates a device cut-out on desktop for tests.
	var vs := vp.get_visible_rect().size
	var win := Vector2(DisplayServer.window_get_size())
	if win.x <= 0.0 or win.y <= 0.0:
		win = vs
	var sx := vs.x / win.x
	var sy := vs.y / win.y
	var l := 0.0
	var t := 0.0
	var r := 0.0
	var b := 0.0
	var env := OS.get_environment("WK_SAFE_INSET")
	if env != "":
		var parts := env.split(",")
		if parts.size() == 4:
			l = float(parts[0]); t = float(parts[1]); r = float(parts[2]); b = float(parts[3])
	elif OS.has_feature("mobile"):
		var safe := Rect2(DisplayServer.get_display_safe_area())
		if safe.size.x > 0.0 and safe.size.y > 0.0:
			l = safe.position.x
			t = safe.position.y
			r = maxf(win.x - safe.end.x, 0.0)
			b = maxf(win.y - safe.end.y, 0.0)
	# user "screen margin" (rounded corners / curved edges) + a small minimum
	var user := float(Game.settings.get("screen_margin", 0.02)) * vs.x
	var minx := maxf(16.0, user)
	var miny := maxf(10.0, user * 0.5)
	return Rect2(maxf(l * sx, minx), maxf(t * sy, miny), maxf(r * sx, minx), maxf(b * sy, miny))


static func safe_rect(vp: Viewport) -> Rect2:
	var ins := safe_insets(vp)
	var vs := vp.get_visible_rect().size
	return Rect2(ins.position, vs - ins.position - ins.size)


static func safe_margins(ctrl: Control) -> void:
	## Full-rect control inset by the safe area; follows resizes/rotation.
	var apply := func() -> void:
		if not is_instance_valid(ctrl) or not ctrl.is_inside_tree():
			return
		var ins := safe_insets(ctrl.get_viewport())
		ctrl.anchor_left = 0.0
		ctrl.anchor_top = 0.0
		ctrl.anchor_right = 1.0
		ctrl.anchor_bottom = 1.0
		ctrl.offset_left = ins.position.x
		ctrl.offset_top = ins.position.y
		ctrl.offset_right = -ins.size.x
		ctrl.offset_bottom = -ins.size.y
	var hook := func() -> void:
		apply.call()
		var vp := ctrl.get_viewport()
		if not vp.size_changed.is_connected(apply):
			vp.size_changed.connect(apply)
	if ctrl.is_inside_tree():
		hook.call()
	else:
		ctrl.tree_entered.connect(hook, CONNECT_ONE_SHOT)


static func side_panel(parent: Node, panel: Control) -> Control:
	## Panel on the left of the safe area, vertically centred, scrolling if it is
	## taller than the screen (the right side stays free for the 3D preview).
	return centered(parent, panel, Vector2(0.6, 1.0), true, false)


static func centered(parent: Node, panel: Control, max_frac := Vector2(0.94, 0.94), left := false, inset := true) -> Control:
	## Puts panel in the middle of the safe area, scrolling if it is taller than
	## the screen. Works for any parent (CanvasLayer or Control) and any size.
	var area := Control.new()
	area.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(area)
	if inset:
		safe_margins(area)
	else:
		area.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var cc: Container
	if left:
		var col := VBoxContainer.new()
		col.alignment = BoxContainer.ALIGNMENT_CENTER
		cc = col
	else:
		cc = CenterContainer.new()
	cc.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	cc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	area.add_child(cc)
	var sc := ScrollContainer.new()
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	sc.scroll_deadzone = 28
	sc.mouse_filter = Control.MOUSE_FILTER_PASS
	cc.add_child(sc)
	if left:
		sc.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	sc.add_child(panel)
	var fit := func() -> void:
		if not is_instance_valid(sc) or not area.is_inside_tree():
			return
		var avail := area.size
		var want := panel.get_combined_minimum_size()
		sc.custom_minimum_size = Vector2(minf(want.x, avail.x * max_frac.x), minf(want.y, avail.y * max_frac.y))
	area.resized.connect(fit)
	panel.minimum_size_changed.connect(fit)
	fit.call_deferred()
	return area
