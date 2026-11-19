class_name NeonSegment
extends Control
## Segmented selector (e.g. quality: low / medium / high).

signal changed(index: int)

var options: Array = []
var selected: int = 0
var accent: Color = Color(0.25, 0.9, 1.0)
var font_size: int = 28

var _labels: Array = []
var _bg: StyleBoxFlat
var _hl: StyleBoxFlat


static func make(opts: Array, sel: int, col: Color = Color(0.25, 0.9, 1.0), sz: Vector2 = Vector2(560, 64), fs: int = 28) -> NeonSegment:
	var s := NeonSegment.new()
	s.options = opts
	s.selected = sel
	s.accent = col
	s.custom_minimum_size = sz
	s.size = sz
	s.font_size = fs
	s._build()
	return s


func _build() -> void:
	_bg = UIKit.panel_style(Color(0.04, 0.07, 0.17, 0.85), Color(accent.r, accent.g, accent.b, 0.55), 32, 2)
	_hl = UIKit.panel_style(accent, accent.lightened(0.3), 26, 0, 10, Color(accent.r, accent.g, accent.b, 0.45))
	for i in range(options.size()):
		var l := UIKit.label(str(options[i]), font_size)
		add_child(l)
		_labels.append(l)
	resized.connect(_layout)
	_layout()


func _layout() -> void:
	var n: int = maxi(1, options.size())
	var w: float = size.x / float(n)
	for i in range(_labels.size()):
		var l: Label = _labels[i]
		l.position = Vector2(i * w, 0.0)
		l.size = Vector2(w, size.y)
		var sel: bool = i == selected
		l.add_theme_color_override("font_color", Color(0.02, 0.05, 0.14) if sel else UIKit.COL_TEXT)
	queue_redraw()


func _draw() -> void:
	draw_style_box(_bg, Rect2(Vector2.ZERO, size))
	var n: int = maxi(1, options.size())
	var w: float = size.x / float(n)
	draw_style_box(_hl, Rect2(Vector2(selected * w + 5.0, 5.0), Vector2(w - 10.0, size.y - 10.0)))


func set_selected(i: int) -> void:
	selected = i
	_layout()


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		var n: int = maxi(1, options.size())
		var idx: int = clampi(int(event.position.x / (size.x / float(n))), 0, n - 1)
		if idx != selected:
			selected = idx
			_layout()
			Sfx.play("ui_click")
			changed.emit(idx)
		accept_event()
