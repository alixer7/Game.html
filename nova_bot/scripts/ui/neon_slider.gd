class_name NeonSlider
extends Control
## Horizontal glowing slider (value 0..1).

signal value_changed(v: float)

var value: float = 0.5
var accent: Color = Color(0.25, 0.9, 1.0)

var _drag: bool = false
var _track: StyleBoxFlat
var _fill: StyleBoxFlat
const PAD := 30.0


static func make(v: float, col: Color = Color(0.25, 0.9, 1.0), sz: Vector2 = Vector2(520, 60)) -> NeonSlider:
	var s := NeonSlider.new()
	s.value = v
	s.accent = col
	s.custom_minimum_size = sz
	s.size = sz
	s._track = UIKit.panel_style(Color(0.06, 0.1, 0.22, 0.95), Color(col.r, col.g, col.b, 0.4), 8, 2)
	s._fill = UIKit.panel_style(col, Color(0, 0, 0, 0), 8, 0, 8, Color(col.r, col.g, col.b, 0.5))
	return s


func _draw() -> void:
	var h: float = 16.0
	var y: float = size.y * 0.5
	var track := Rect2(PAD, y - h * 0.5, size.x - PAD * 2.0, h)
	draw_style_box(_track, track)
	var fw: float = track.size.x * value
	if fw > 2.0:
		draw_style_box(_fill, Rect2(track.position, Vector2(fw, h)))
	var kx: float = track.position.x + fw
	draw_circle(Vector2(kx, y), 27.0, Color(accent.r, accent.g, accent.b, 0.22))
	draw_circle(Vector2(kx, y), 20.0, Color(1, 1, 1, 1))
	draw_circle(Vector2(kx, y), 12.0, accent)


func _set_x(x: float) -> void:
	var v: float = clampf((x - PAD) / maxf(1.0, size.x - PAD * 2.0), 0.0, 1.0)
	v = snappedf(v, 0.01)
	if absf(v - value) > 0.0001:
		value = v
		queue_redraw()
		value_changed.emit(value)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		_drag = event.pressed
		if event.pressed:
			_set_x(event.position.x)
		else:
			Sfx.play("ui_click", -6.0)
		accept_event()
	elif event is InputEventMouseMotion and _drag:
		_set_x(event.position.x)
		accept_event()
