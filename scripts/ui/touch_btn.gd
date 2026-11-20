class_name TouchBtn
extends Control
## زر لمسي مخصص يدعم تعدد اللمسات (يُدار عبر TouchControls).

var id := ""
var text := ""
var sub := ""
var round_shape := true
var held := false
var toggled := false
var tint := Color(1, 1, 1)
var icon_item := ""
var font_size := 20
var enabled_look := true

func _init(bid := "", t := "", sz := Vector2(96, 96), is_round := true) -> void:
	id = bid
	text = t
	custom_minimum_size = sz
	size = sz
	round_shape = is_round
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func hit(p: Vector2) -> bool:
	var r := get_global_rect()
	if round_shape:
		return p.distance_to(r.get_center()) <= r.size.x * 0.56
	return r.grow(6).has_point(p)

func set_text(t: String) -> void:
	if t != text:
		text = t
		queue_redraw()

func _draw() -> void:
	var a := 0.55 if held else (0.4 if toggled else 0.28)
	var bg := Color(0.05, 0.05, 0.06, a)
	var border := Color(tint.r, tint.g, tint.b, 0.9 if held or toggled else 0.5)
	if toggled:
		bg = Color(0.5, 0.38, 0.15, 0.5)
	if round_shape:
		var c := size * 0.5
		var r := minf(size.x, size.y) * 0.5
		draw_circle(c, r, bg)
		draw_arc(c, r - 1.5, 0, TAU, 40, border, 3.0, true)
	else:
		var sbx := UIKit.sb(bg, 14, 3, border, 0)
		draw_style_box(sbx, Rect2(Vector2.ZERO, size))
	var font := get_theme_default_font()
	if text != "":
		var fs := font_size
		var lines := text.split("\n")
		var total_h := fs * 1.15 * lines.size()
		var y0 := size.y * 0.5 - total_h * 0.5 + fs * 0.9
		if icon_item != "":
			y0 = size.y - 8
		for i in range(lines.size()):
			var ln: String = lines[i]
			var w := font.get_string_size(ln, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
			var pos := Vector2(size.x * 0.5 - w * 0.5, y0 + i * fs * 1.15)
			draw_string_outline(font, pos, ln, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 4, Color(0, 0, 0, 0.8))
			draw_string(font, pos, ln, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(1, 1, 1, 0.95))
	if sub != "":
		var fs2 := 14
		var w2 := font.get_string_size(sub, HORIZONTAL_ALIGNMENT_LEFT, -1, fs2).x
		draw_string(font, Vector2(size.x * 0.5 - w2 * 0.5, size.y - 6), sub, HORIZONTAL_ALIGNMENT_LEFT, -1, fs2, Color(1, 1, 0.8, 0.9))
