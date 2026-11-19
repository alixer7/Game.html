class_name NeonToggle
extends Control
## On/off switch with an animated knob.

signal toggled(on: bool)

var on: bool = false
var accent: Color = Color(0.25, 0.9, 1.0)

var _k: float = 0.0
var _st_off: StyleBoxFlat
var _st_on: StyleBoxFlat


static func make(state: bool, col: Color = Color(0.25, 0.9, 1.0), sz: Vector2 = Vector2(124, 62)) -> NeonToggle:
	var t := NeonToggle.new()
	t.on = state
	t._k = 1.0 if state else 0.0
	t.accent = col
	t.custom_minimum_size = sz
	t.size = sz
	var r: int = int(sz.y * 0.5)
	t._st_off = UIKit.panel_style(Color(0.06, 0.09, 0.2, 0.95), Color(0.4, 0.5, 0.7, 0.7), r, 2)
	t._st_on = UIKit.panel_style(Color(col.r * 0.45, col.g * 0.45, col.b * 0.45, 0.98), col, r, 2, 10, Color(col.r, col.g, col.b, 0.4))
	return t


func _process(delta: float) -> void:
	var target: float = 1.0 if on else 0.0
	if _k != target:
		_k = move_toward(_k, target, delta * 9.0)
		queue_redraw()


func _draw() -> void:
	var rect := Rect2(Vector2.ZERO, size)
	draw_style_box(_st_on if on else _st_off, rect)
	var r: float = size.y * 0.5
	var kx: float = lerpf(r, size.x - r, _k)
	var kc: Color = Color(0.7, 0.78, 0.9).lerp(Color(1, 1, 1), _k)
	draw_circle(Vector2(kx, r), r - 8.0, kc)
	if on:
		draw_circle(Vector2(kx, r), r - 16.0, accent)


func set_on(v: bool) -> void:
	on = v
	queue_redraw()


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		on = not on
		Sfx.play("ui_click")
		queue_redraw()
		toggled.emit(on)
		accept_event()
