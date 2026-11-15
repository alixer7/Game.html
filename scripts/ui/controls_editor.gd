class_name ControlsEditor
extends Control
## Full-screen editor for the touch layout: drag any control to move it, then
## adjust its size and opacity. Saved to Settings "touch_layout".

signal closed

var tc: TouchControls
var sel_lbl: Label
var size_slider: HSlider
var op_slider: HSlider
var size_val: Label
var op_val: Label
var _updating := false


var _hidden: Array = []


func _ready() -> void:
	# hide the in-game controls while editing so they don't overlap
	for n in get_tree().get_nodes_in_group("touch_hud"):
		if (n as CanvasItem).visible:
			(n as CanvasItem).visible = false
			_hidden.append(n)
	tree_exiting.connect(_restore)
	visibility_changed.connect(func():
		if not is_visible_in_tree():
			_restore())
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layout_direction = Control.LAYOUT_DIRECTION_LTR
	theme = UiTheme.theme()
	var bg := ColorRect.new()
	bg.color = Color(0.02, 0.03, 0.06, 0.6)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	tc = TouchControls.new()
	tc.edit_mode = true
	tc.show_reset = true
	add_child(tc)
	tc.selection_changed.connect(_on_select)

	var holder := CenterContainer.new()
	holder.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	holder.offset_top = 12
	holder.offset_left = -330
	holder.offset_right = 330
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(holder)
	var panel := PanelContainer.new()
	var sb := UiTheme.box(UiTheme.PANEL, 18, Color(1, 1, 1, 0.1), 2)
	sb.content_margin_left = 22
	sb.content_margin_right = 22
	sb.content_margin_top = 12
	sb.content_margin_bottom = 12
	panel.add_theme_stylebox_override("panel", sb)
	holder.add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	panel.add_child(v)
	var title := UiTheme.label(Loc.t("customize_controls"), 28, Color.WHITE, true)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(title)
	var hint := UiTheme.label(Loc.t("drag_hint"), 18, UiTheme.TEXT_DIM)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(hint)
	sel_lbl = UiTheme.label("—", 22, UiTheme.ACCENT, true)
	sel_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(sel_lbl)
	var r1 := _slider_row(v, Loc.t("size"), 0.6, 1.7)
	size_slider = r1[0]
	size_val = r1[1]
	var r2 := _slider_row(v, Loc.t("opacity_short"), 0.2, 1.0)
	op_slider = r2[0]
	op_val = r2[1]
	size_slider.value_changed.connect(func(x: float):
		size_val.text = "%d%%" % int(round(x * 100.0))
		if not _updating and tc.selected != "":
			tc.set_element(tc.selected, tc.element_center(tc.selected), x, tc.element_opacity(tc.selected)))
	op_slider.value_changed.connect(func(x: float):
		op_val.text = "%d%%" % int(round(x * 100.0))
		if not _updating and tc.selected != "":
			tc.set_element(tc.selected, tc.element_center(tc.selected), tc.element_scale(tc.selected), x))
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 12)
	v.add_child(row)
	row.add_child(_button(Loc.t("reset_layout"), func():
		tc.reset_layout()
		_on_select(tc.selected if tc.selected != "" else "jump"), false))
	row.add_child(_button(Loc.t("done"), func():
		Settings.set_value("touch_layout", tc.layout_data())
		closed.emit(), true))
	_set_enabled(false)
	_on_select("jump")


func _restore() -> void:
	for n in _hidden:
		if is_instance_valid(n):
			(n as CanvasItem).visible = true
	_hidden.clear()


func _slider_row(parent: Control, caption: String, lo: float, hi: float) -> Array:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	parent.add_child(row)
	var l := UiTheme.label(caption, 20, UiTheme.TEXT)
	l.custom_minimum_size = Vector2(120, 0)
	row.add_child(l)
	var s := HSlider.new()
	s.min_value = lo
	s.max_value = hi
	s.step = 0.05
	s.custom_minimum_size = Vector2(330, 36)
	s.focus_mode = Control.FOCUS_NONE
	row.add_child(s)
	var val := UiTheme.label("", 20, UiTheme.ACCENT)
	val.custom_minimum_size = Vector2(70, 0)
	row.add_child(val)
	return [s, val]


func _button(text: String, cb: Callable, accent: bool) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(190, 50)
	b.add_theme_font_size_override("font_size", 22)
	if accent:
		b.add_theme_stylebox_override("normal", UiTheme.box(Color(0.1, 0.45, 0.85, 0.95), 12, Color(0.6, 0.85, 1.0, 0.6), 2))
	b.pressed.connect(func():
		Sfx.play("click", -6.0)
		cb.call())
	return b


func _set_enabled(on: bool) -> void:
	size_slider.editable = on
	op_slider.editable = on


func _on_select(e: String) -> void:
	tc.selected = e
	sel_lbl.text = Loc.t("ctl_" + e)
	_updating = true
	size_slider.value = tc.element_scale(e)
	op_slider.value = tc.element_opacity(e)
	size_val.text = "%d%%" % int(round(size_slider.value * 100.0))
	op_val.text = "%d%%" % int(round(op_slider.value * 100.0))
	_updating = false
	_set_enabled(true)
