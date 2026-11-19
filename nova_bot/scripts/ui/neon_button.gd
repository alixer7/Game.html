class_name NeonButton
extends Control
## Glass / neon pill button drawn from code. Emits `pressed` on release inside the button.

signal pressed

var text: String = ""
var accent: Color = Color(0.25, 0.9, 1.0)
var primary: bool = false
var disabled: bool = false
var icon_kind: String = ""
var font_size: int = 40

var _label: Label
var _style: StyleBoxFlat
var _style_down: StyleBoxFlat
var _gloss: StyleBoxFlat
var _down: bool = false
var _tw: Tween


static func make(txt: String, col: Color = Color(0.25, 0.9, 1.0), is_primary: bool = false, sz: Vector2 = Vector2(380, 96), fsize: int = 40, icon: String = "") -> NeonButton:
	var b := NeonButton.new()
	b.text = txt
	b.accent = col
	b.primary = is_primary
	b.custom_minimum_size = sz
	b.size = sz
	b.font_size = fsize
	b.icon_kind = icon
	b._rebuild()
	return b


func _ready() -> void:
	resized.connect(_on_resized)
	pivot_offset = size / 2.0


func _on_resized() -> void:
	pivot_offset = size / 2.0
	queue_redraw()


func _text_color() -> Color:
	if primary:
		return Color(0.02, 0.05, 0.14) if accent.get_luminance() > 0.42 else Color(1, 1, 1)
	return UIKit.COL_TEXT


func _rebuild() -> void:
	var r: int = int(minf(size.y * 0.5, 48.0))
	var ga := Color(accent.r, accent.g, accent.b, 0.5)
	if primary:
		_style = UIKit.panel_style(accent, accent.lightened(0.4), r, 3, 18, ga)
		_style_down = UIKit.panel_style(accent.darkened(0.28), accent, r, 3, 6, Color(accent.r, accent.g, accent.b, 0.3))
	else:
		_style = UIKit.panel_style(Color(0.04, 0.07, 0.17, 0.82), accent, r, 3, 14, Color(accent.r, accent.g, accent.b, 0.28))
		_style_down = UIKit.panel_style(Color(accent.r * 0.28, accent.g * 0.28, accent.b * 0.28, 0.92), accent.lightened(0.3), r, 3, 6, Color(accent.r, accent.g, accent.b, 0.4))
	_gloss = UIKit.panel_style(Color(1, 1, 1, 0.22), Color(0, 0, 0, 0), r, 0)
	_gloss.corner_radius_bottom_left = 0
	_gloss.corner_radius_bottom_right = 0
	if _label == null:
		_label = UIKit.label(text, font_size, _text_color())
		add_child(_label)
	_label.text = text
	_label.add_theme_font_size_override("font_size", font_size)
	_label.add_theme_color_override("font_color", _text_color())
	UIKit.fill(_label)
	if icon_kind != "":
		_label.offset_right = -size.y * 0.9
	queue_redraw()


func set_text(t: String) -> void:
	text = t
	if _label != null:
		_label.text = t


func set_disabled(v: bool) -> void:
	disabled = v
	modulate = Color(1, 1, 1, 0.45) if v else Color(1, 1, 1, 1)


func _draw() -> void:
	if _style == null:
		return
	var rect := Rect2(Vector2.ZERO, size)
	draw_style_box(_style_down if _down else _style, rect)
	if primary and not _down:
		draw_style_box(_gloss, Rect2(Vector2(size.y * 0.3, 5.0), Vector2(size.x - size.y * 0.6, size.y * 0.4)))
	if icon_kind != "":
		UIIcons.draw(self, icon_kind, Vector2(size.x - size.y * 0.5, size.y * 0.5), size.y * 0.24, _text_color())


func _press_anim(down: bool) -> void:
	if _tw != null and _tw.is_valid():
		_tw.kill()
	_tw = create_tween()
	var target: Vector2 = Vector2(0.95, 0.95) if down else Vector2.ONE
	if down:
		_tw.tween_property(self, "scale", target, 0.06)
	else:
		_tw.tween_property(self, "scale", target, 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _gui_input(event: InputEvent) -> void:
	if disabled:
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_down = true
			_press_anim(true)
			queue_redraw()
		else:
			var was: bool = _down
			_down = false
			_press_anim(false)
			queue_redraw()
			if was and Rect2(Vector2.ZERO, size).has_point(event.position):
				Sfx.play("ui_click")
				Game.vibrate(12)
				pressed.emit()
		accept_event()
