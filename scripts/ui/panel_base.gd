class_name ModalPanel
extends Control
## نافذة كاملة الشاشة بخلفية معتمة وإطار وعنوان وزر إغلاق.

var hud: Node
var frame: PanelContainer
var body: VBoxContainer
var title_lbl: Label
var header: HBoxContainer

func _init() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false

func build() -> void:
	pass

func make_frame(title: String, margin := 0.03) -> void:
	var bg := ColorRect.new()
	bg.color = Color(0, 0, 0, 0.55)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	frame = PanelContainer.new()
	frame.anchor_left = margin
	frame.anchor_right = 1.0 - margin
	frame.anchor_top = margin
	frame.anchor_bottom = 1.0 - margin
	add_child(frame)
	var v := UIKit.vbox(8)
	frame.add_child(v)
	header = UIKit.hbox(10)
	v.add_child(header)
	var close_b := UIKit.button("إغلاق", close, 20, 52)
	close_b.custom_minimum_size = Vector2(120, 52)
	header.add_child(close_b)
	title_lbl = UIKit.label(title, 28, UIKit.GOLD)
	title_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title_lbl)
	v.add_child(UIKit.sep())
	body = UIKit.vbox(8)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(body)

func open() -> void:
	visible = true
	hud.on_panel_open(self)
	refresh()

func close() -> void:
	visible = false
	hud.on_panel_close(self)

func refresh() -> void:
	pass

func player() -> Player:
	return hud.player

func world() -> Node:
	return hud.world

func clear(c: Node) -> void:
	for ch in c.get_children():
		ch.queue_free()

## زر خانة عنصر
func slot_button(s, cb: Callable, sz := 82.0, selected := false) -> Button:
	var b := Button.new()
	b.custom_minimum_size = Vector2(sz, sz)
	b.mouse_filter = Control.MOUSE_FILTER_PASS
	b.focus_mode = Control.FOCUS_NONE
	if selected:
		b.add_theme_stylebox_override("normal", UIKit.sb(Color(0.45, 0.34, 0.15, 1.0), 10, 2, UIKit.GOLD, 4))
	var ic := ItemIcon.new()
	ic.position = Vector2(5, 5)
	ic.size = Vector2(sz - 10, sz - 10)
	b.add_child(ic)
	if s != null:
		ic.set_item(s["id"], s["n"], s.get("d", -1.0))
	b.pressed.connect(cb)
	return b
