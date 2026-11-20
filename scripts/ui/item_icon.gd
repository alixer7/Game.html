class_name ItemIcon
extends Control
## أيقونة عنصر مرسومة برمجياً (بدون صور) مع العدد وشريط المتانة.

var item_id := ""
var count := 0
var dur := -1.0
var show_count := true

func set_item(id: String, n := 1, d := -1.0) -> void:
	item_id = id
	count = n
	dur = d
	queue_redraw()

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func _poly(pts: Array, c: Color, outline := true) -> void:
	var p := PackedVector2Array(pts)
	draw_colored_polygon(p, c)
	if outline:
		var q := p.duplicate()
		q.append(p[0])
		draw_polyline(q, c.darkened(0.5), 2.0, true)

func _draw() -> void:
	if item_id == "":
		return
	var it := ItemDB.get_item(item_id)
	if it.is_empty():
		return
	var s: float = minf(size.x, size.y) / 64.0
	var off := (size - Vector2(64, 64) * s) * 0.5
	draw_set_transform(off, 0.0, Vector2(s, s))
	var c: Color = it["color"]
	var d := c.darkened(0.4)
	var l := c.lightened(0.3)
	var brown := Color(0.5, 0.34, 0.2)
	match it["icon"]:
		"log":
			_poly([Vector2(8, 24), Vector2(50, 20), Vector2(52, 42), Vector2(10, 46)], c)
			draw_circle(Vector2(51, 31), 11, l)
			draw_arc(Vector2(51, 31), 7, 0, TAU, 16, d, 2.0)
			draw_arc(Vector2(51, 31), 3, 0, TAU, 12, d, 2.0)
		"stick":
			draw_line(Vector2(12, 52), Vector2(52, 12), c, 6.0, true)
			draw_line(Vector2(20, 54), Vector2(54, 22), c.darkened(0.15), 5.0, true)
			draw_line(Vector2(36, 28), Vector2(44, 16), c, 3.0, true)
		"fiber":
			for i in range(5):
				var x := 14.0 + i * 9.0
				draw_polyline(PackedVector2Array([Vector2(x, 56), Vector2(x + 4, 36), Vector2(x - 2, 14)]), c.darkened(i * 0.06), 3.0, true)
		"leaf":
			_poly([Vector2(10, 52), Vector2(22, 22), Vector2(50, 10), Vector2(44, 40)], c)
			draw_line(Vector2(12, 50), Vector2(48, 12), d, 2.0, true)
		"stone":
			_poly([Vector2(12, 44), Vector2(18, 22), Vector2(36, 14), Vector2(54, 26), Vector2(52, 48), Vector2(30, 54)], c)
			_poly([Vector2(22, 24), Vector2(36, 18), Vector2(44, 26), Vector2(28, 30)], l, false)
		"ore":
			_poly([Vector2(12, 44), Vector2(18, 22), Vector2(36, 14), Vector2(54, 26), Vector2(52, 48), Vector2(30, 54)], Color(0.45, 0.44, 0.42))
			for p in [Vector2(24, 30), Vector2(38, 26), Vector2(30, 42), Vector2(44, 40), Vector2(20, 42)]:
				draw_circle(p, 4.0, c)
				draw_circle(p - Vector2(1, 1), 1.5, l)
		"ingot":
			_poly([Vector2(8, 44), Vector2(16, 28), Vector2(48, 28), Vector2(56, 44)], c)
			_poly([Vector2(16, 28), Vector2(22, 20), Vector2(44, 20), Vector2(48, 28)], l)
		"gem":
			_poly([Vector2(32, 8), Vector2(52, 24), Vector2(32, 56), Vector2(12, 24)], c)
			_poly([Vector2(32, 8), Vector2(42, 24), Vector2(32, 30), Vector2(22, 24)], l, false)
			draw_line(Vector2(12, 24), Vector2(52, 24), d, 1.5)
		"heap":
			_poly([Vector2(6, 52), Vector2(18, 30), Vector2(32, 20), Vector2(46, 30), Vector2(58, 52)], c)
			for p in [Vector2(24, 40), Vector2(34, 32), Vector2(42, 44), Vector2(30, 46)]:
				draw_circle(p, 2.0, d)
		"drop":
			_poly([Vector2(32, 8), Vector2(46, 34), Vector2(44, 48), Vector2(32, 56), Vector2(20, 48), Vector2(18, 34)], c)
			draw_circle(Vector2(27, 40), 4.0, l)
		"cotton":
			draw_line(Vector2(32, 58), Vector2(32, 34), Color(0.4, 0.5, 0.25), 3.0)
			for p in [Vector2(24, 26), Vector2(40, 26), Vector2(32, 18), Vector2(32, 32)]:
				draw_circle(p, 10.0, c)
		"herb", "wheat":
			draw_line(Vector2(32, 58), Vector2(32, 10), Color(0.35, 0.5, 0.2) if it["icon"] == "herb" else c.darkened(0.2), 3.0)
			for i in range(4):
				var y := 18.0 + i * 9.0
				if it["icon"] == "herb":
					_poly([Vector2(32, y), Vector2(46, y - 6), Vector2(40, y + 4)], c)
					_poly([Vector2(32, y + 3), Vector2(18, y - 3), Vector2(24, y + 7)], c)
				else:
					draw_circle(Vector2(27, y), 4.0, c)
					draw_circle(Vector2(37, y), 4.0, c)
			if it["icon"] == "herb":
				draw_circle(Vector2(32, 10), 4.0, Color(0.7, 0.4, 0.9))
		"seed":
			for p in [Vector2(22, 34), Vector2(36, 26), Vector2(40, 42), Vector2(26, 46)]:
				draw_circle(p, 5.0, c)
				draw_circle(p - Vector2(1.5, 1.5), 1.5, l)
		"feather":
			_poly([Vector2(16, 54), Vector2(24, 30), Vector2(44, 10), Vector2(42, 28), Vector2(26, 46)], c)
			draw_line(Vector2(14, 56), Vector2(42, 14), d, 2.0)
		"hide":
			_poly([Vector2(10, 18), Vector2(24, 12), Vector2(40, 14), Vector2(54, 10), Vector2(52, 30), Vector2(56, 50), Vector2(40, 54), Vector2(22, 52), Vector2(8, 54), Vector2(12, 34)], c)
		"bone":
			draw_line(Vector2(16, 48), Vector2(48, 16), c, 7.0, true)
			for p in [Vector2(12, 46), Vector2(18, 52), Vector2(46, 12), Vector2(52, 18)]:
				draw_circle(p, 6.0, c)
		"meat":
			_poly([Vector2(10, 34), Vector2(20, 16), Vector2(42, 14), Vector2(52, 30), Vector2(44, 48), Vector2(22, 50)], c)
			draw_circle(Vector2(50, 46), 5.0, Color(0.95, 0.92, 0.85))
			draw_line(Vector2(40, 38), Vector2(50, 46), Color(0.95, 0.92, 0.85), 4.0)
			draw_arc(Vector2(28, 30), 8, 0.5, 3.5, 10, l, 2.0)
		"fish":
			_poly([Vector2(8, 32), Vector2(22, 20), Vector2(40, 20), Vector2(48, 32), Vector2(40, 44), Vector2(22, 44)], c)
			_poly([Vector2(46, 32), Vector2(58, 20), Vector2(58, 44)], c.darkened(0.15))
			draw_circle(Vector2(18, 29), 2.5, Color(0.05, 0.05, 0.05))
		"berry":
			_poly([Vector2(30, 14), Vector2(44, 8), Vector2(38, 20)], Color(0.3, 0.55, 0.2))
			for p in [Vector2(24, 30), Vector2(38, 28), Vector2(30, 40), Vector2(44, 42), Vector2(20, 44)]:
				draw_circle(p, 8.0, c)
				draw_circle(p - Vector2(2, 2), 2.0, l)
		"mushroom":
			draw_rect(Rect2(26, 30, 12, 24), Color(0.92, 0.88, 0.78))
			_poly([Vector2(8, 34), Vector2(14, 18), Vector2(32, 10), Vector2(50, 18), Vector2(56, 34)], c)
			if item_id == "toadstool":
				for p in [Vector2(22, 22), Vector2(36, 18), Vector2(44, 28)]:
					draw_circle(p, 3.0, Color.WHITE)
		"fruit":
			draw_circle(Vector2(32, 36), 18, c)
			draw_circle(Vector2(26, 30), 5, l)
			_poly([Vector2(32, 18), Vector2(44, 10), Vector2(40, 20)], Color(0.3, 0.55, 0.2))
		"jar":
			_poly([Vector2(18, 20), Vector2(46, 20), Vector2(50, 52), Vector2(14, 52)], c)
			draw_rect(Rect2(20, 12, 24, 8), brown)
		"bowl":
			_poly([Vector2(8, 32), Vector2(56, 32), Vector2(48, 50), Vector2(16, 50)], Color(0.45, 0.32, 0.2))
			draw_rect(Rect2(10, 28, 44, 6), c)
			for x in [24.0, 32.0, 40.0]:
				draw_polyline(PackedVector2Array([Vector2(x, 24), Vector2(x - 3, 16), Vector2(x + 2, 8)]), Color(1, 1, 1, 0.5), 2.0)
		"bread":
			_poly([Vector2(8, 40), Vector2(14, 24), Vector2(32, 18), Vector2(50, 24), Vector2(56, 40), Vector2(32, 48)], c)
			for x in [22.0, 32.0, 42.0]:
				draw_line(Vector2(x - 4, 26), Vector2(x + 4, 34), d, 2.0)
		"waterskin":
			_poly([Vector2(20, 14), Vector2(44, 14), Vector2(52, 40), Vector2(40, 56), Vector2(24, 56), Vector2(12, 40)], Color(0.5, 0.36, 0.22))
			draw_rect(Rect2(26, 6, 12, 9), brown.darkened(0.2))
			if item_id != "waterskin":
				_poly([Vector2(32, 26), Vector2(40, 40), Vector2(32, 48), Vector2(24, 40)], c)
		"plank":
			for i in range(3):
				draw_rect(Rect2(8, 16 + i * 12, 48, 10), c.darkened(i * 0.08))
				draw_rect(Rect2(8, 16 + i * 12, 48, 10), d, false, 1.5)
		"rope":
			for r in [20.0, 14.0, 8.0]:
				draw_arc(Vector2(32, 32), r, 0, TAU, 24, c, 4.0)
		"cloth":
			_poly([Vector2(10, 16), Vector2(54, 12), Vector2(52, 48), Vector2(12, 52)], c)
			draw_line(Vector2(12, 34), Vector2(52, 30), d, 2.0)
		"brick":
			draw_rect(Rect2(8, 20, 48, 24), c)
			draw_line(Vector2(8, 32), Vector2(56, 32), Color(0.8, 0.75, 0.65), 2.0)
			draw_line(Vector2(32, 20), Vector2(32, 32), Color(0.8, 0.75, 0.65), 2.0)
			draw_line(Vector2(20, 32), Vector2(20, 44), Color(0.8, 0.75, 0.65), 2.0)
			draw_line(Vector2(44, 32), Vector2(44, 44), Color(0.8, 0.75, 0.65), 2.0)
		"nails":
			for x in [18.0, 32.0, 46.0]:
				draw_line(Vector2(x, 14), Vector2(x, 52), c, 3.0)
				draw_rect(Rect2(x - 5, 12, 10, 4), c.lightened(0.2))
		"lock":
			draw_arc(Vector2(32, 26), 12, PI, TAU, 16, Color(0.6, 0.6, 0.65), 5.0)
			draw_rect(Rect2(16, 26, 32, 26), c)
			draw_circle(Vector2(32, 38), 4, d)
		"coin":
			draw_circle(Vector2(32, 32), 20, c)
			draw_arc(Vector2(32, 32), 15, 0, TAU, 24, d, 2.0)
			draw_circle(Vector2(25, 25), 4, Color(1, 1, 0.9))
		"axe", "pickaxe", "knife", "hammer", "sword", "spear", "club", "bow", "arrow", "torch", "rod":
			_tool_icon(it["icon"], c, brown)
		"hat":
			_poly([Vector2(6, 42), Vector2(58, 42), Vector2(54, 48), Vector2(10, 48)], c.darkened(0.1))
			_poly([Vector2(18, 42), Vector2(22, 22), Vector2(42, 22), Vector2(46, 42)], c)
		"shirt", "coat", "armor":
			var bottom := 54.0 if it["icon"] == "coat" else 46.0
			_poly([Vector2(20, 12), Vector2(44, 12), Vector2(58, 24), Vector2(50, 30), Vector2(46, 26), Vector2(46, bottom), Vector2(18, bottom), Vector2(18, 26), Vector2(14, 30), Vector2(6, 24)], c)
			if it["icon"] == "armor":
				draw_line(Vector2(32, 16), Vector2(32, bottom), l, 2.0)
				draw_arc(Vector2(32, 26), 10, 0.2, PI - 0.2, 10, l, 2.0)
		"pants":
			_poly([Vector2(18, 10), Vector2(46, 10), Vector2(48, 56), Vector2(36, 56), Vector2(32, 26), Vector2(28, 56), Vector2(16, 56)], c)
		"boots":
			_poly([Vector2(18, 10), Vector2(32, 10), Vector2(32, 40), Vector2(54, 44), Vector2(54, 54), Vector2(16, 54)], c)
		"bag":
			_poly([Vector2(14, 18), Vector2(50, 18), Vector2(52, 56), Vector2(12, 56)], c)
			_poly([Vector2(14, 18), Vector2(50, 18), Vector2(48, 32), Vector2(16, 32)], c.lightened(0.15))
			draw_arc(Vector2(32, 18), 9, PI, TAU, 12, d, 3.0)
		"bandage":
			draw_rect(Rect2(10, 22, 44, 20), c)
			draw_rect(Rect2(28, 26, 8, 12), Color(0.9, 0.2, 0.2))
			draw_rect(Rect2(26, 28, 12, 8), Color(0.9, 0.2, 0.2))
		"potion":
			_poly([Vector2(26, 10), Vector2(38, 10), Vector2(38, 22), Vector2(50, 36), Vector2(46, 56), Vector2(18, 56), Vector2(14, 36), Vector2(26, 22)], Color(0.8, 0.9, 0.95, 0.5))
			_poly([Vector2(16, 38), Vector2(48, 38), Vector2(45, 54), Vector2(19, 54)], c, false)
			draw_rect(Rect2(25, 6, 14, 6), brown)
		_:
			draw_circle(Vector2(32, 32), 18, c)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	var font := get_theme_default_font()
	if show_count and count > 1:
		var t := str(count)
		var fs := int(maxf(13.0, size.y * 0.26))
		draw_string_outline(font, Vector2(4, size.y - 5), t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 5, Color(0, 0, 0, 0.9))
		draw_string(font, Vector2(4, size.y - 5), t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(1, 1, 1))
	if dur >= 0.0:
		var md := ItemDB.max_dur(item_id)
		if md > 0.0:
			var k := clampf(dur / md, 0.0, 1.0)
			draw_rect(Rect2(4, size.y - 7, size.x - 8, 4), Color(0, 0, 0, 0.6))
			draw_rect(Rect2(4, size.y - 7, (size.x - 8) * k, 4), Color(1.0 - k, 0.3 + k * 0.6, 0.2))

func _tool_icon(kind: String, c: Color, brown: Color) -> void:
	match kind:
		"axe":
			draw_line(Vector2(18, 56), Vector2(40, 10), brown, 5.0, true)
			_poly([Vector2(34, 14), Vector2(54, 8), Vector2(56, 30), Vector2(40, 26)], c)
		"pickaxe":
			draw_line(Vector2(20, 56), Vector2(38, 14), brown, 5.0, true)
			draw_polyline(PackedVector2Array([Vector2(12, 22), Vector2(26, 12), Vector2(40, 12), Vector2(56, 24)]), c, 6.0, true)
		"knife":
			draw_line(Vector2(14, 54), Vector2(26, 40), brown, 6.0, true)
			_poly([Vector2(24, 38), Vector2(50, 10), Vector2(30, 44)], c)
		"hammer":
			draw_line(Vector2(20, 56), Vector2(36, 20), brown, 5.0, true)
			_poly([Vector2(24, 14), Vector2(48, 24), Vector2(44, 32), Vector2(20, 22)], c)
		"sword":
			_poly([Vector2(50, 8), Vector2(56, 14), Vector2(24, 46), Vector2(18, 40)], c.lightened(0.2))
			draw_line(Vector2(14, 36), Vector2(28, 50), c.darkened(0.3), 5.0)
			draw_line(Vector2(20, 44), Vector2(10, 54), Color(0.3, 0.2, 0.12), 5.0)
		"spear":
			draw_line(Vector2(8, 56), Vector2(46, 18), brown, 4.0, true)
			_poly([Vector2(44, 14), Vector2(58, 6), Vector2(50, 20)], c)
		"club":
			_poly([Vector2(12, 54), Vector2(16, 50), Vector2(52, 10), Vector2(56, 22), Vector2(20, 58)], brown)
		"bow":
			draw_arc(Vector2(16, 32), 26, -1.2, 1.2, 16, brown, 4.0)
			draw_line(Vector2(16 + cos(-1.2) * 26, 32 + sin(-1.2) * 26), Vector2(16 + cos(1.2) * 26, 32 + sin(1.2) * 26), Color(0.9, 0.9, 0.85), 1.5)
		"arrow":
			draw_line(Vector2(10, 54), Vector2(50, 14), brown, 3.0, true)
			_poly([Vector2(48, 10), Vector2(56, 8), Vector2(54, 16)], c)
			_poly([Vector2(10, 54), Vector2(8, 44), Vector2(16, 50)], Color(0.95, 0.95, 0.9))
		"torch":
			draw_line(Vector2(24, 58), Vector2(36, 26), brown, 5.0, true)
			_poly([Vector2(30, 26), Vector2(34, 6), Vector2(46, 18), Vector2(42, 28)], Color(1.0, 0.55, 0.1), false)
			_poly([Vector2(34, 24), Vector2(37, 12), Vector2(42, 22)], Color(1.0, 0.9, 0.4), false)
		"rod":
			draw_polyline(PackedVector2Array([Vector2(8, 58), Vector2(30, 30), Vector2(56, 8)]), brown, 3.0, true)
			draw_line(Vector2(56, 8), Vector2(56, 40), Color(0.85, 0.85, 0.85), 1.0)
			draw_arc(Vector2(53, 42), 3, 0, PI, 6, Color(0.6, 0.6, 0.6), 1.5)
