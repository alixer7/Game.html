class_name UIIcons
extends RefCounted
## Vector icons drawn directly with CanvasItem draw calls (call from inside _draw()).
## `c` = centre, `s` = half-size (icon fits inside a square of side 2*s).


static func _head(ci: CanvasItem, p: Vector2, d: Vector2, sz: float, col: Color) -> void:
	var n := Vector2(-d.y, d.x)
	ci.draw_colored_polygon(PackedVector2Array([p + d * sz, p + n * sz * 0.8, p - n * sz * 0.8]), col)


static func draw(ci: CanvasItem, kind: String, c: Vector2, s: float, col: Color) -> void:
	var w: float = maxf(2.0, s * 0.24)
	if kind == "pause":
		ci.draw_rect(Rect2(c + Vector2(-s * 0.7, -s * 0.8), Vector2(s * 0.5, s * 1.6)), col)
		ci.draw_rect(Rect2(c + Vector2(s * 0.2, -s * 0.8), Vector2(s * 0.5, s * 1.6)), col)
	elif kind == "play":
		ci.draw_colored_polygon(PackedVector2Array([c + Vector2(-s * 0.6, -s * 0.85), c + Vector2(s * 0.85, 0.0), c + Vector2(-s * 0.6, s * 0.85)]), col)
	elif kind == "restart":
		var a1: float = deg_to_rad(-40.0)
		var a2: float = deg_to_rad(240.0)
		ci.draw_arc(c, s * 0.68, a1, a2, 28, col, w, true)
		var p: Vector2 = c + Vector2(cos(a2), sin(a2)) * s * 0.68
		_head(ci, p, Vector2(-sin(a2), cos(a2)), s * 0.5, col)
	elif kind == "spin":
		var b1: float = deg_to_rad(-20.0)
		var b2: float = deg_to_rad(250.0)
		ci.draw_arc(c, s * 0.7, b1, b2, 28, col, w, true)
		var q: Vector2 = c + Vector2(cos(b2), sin(b2)) * s * 0.7
		_head(ci, q, Vector2(-sin(b2), cos(b2)), s * 0.52, col)
		ci.draw_circle(c, s * 0.14, col)
	elif kind == "home":
		ci.draw_colored_polygon(PackedVector2Array([c + Vector2(-s, -s * 0.05), c + Vector2(0.0, -s * 0.95), c + Vector2(s, -s * 0.05)]), col)
		ci.draw_rect(Rect2(c + Vector2(-s * 0.68, -s * 0.05), Vector2(s * 1.36, s * 0.95)), col)
		ci.draw_rect(Rect2(c + Vector2(-s * 0.18, s * 0.3), Vector2(s * 0.36, s * 0.6)), Color(0, 0, 0, 0.4))
	elif kind == "gear":
		ci.draw_arc(c, s * 0.56, 0.0, TAU, 28, col, s * 0.32, true)
		for i in range(8):
			var d := Vector2(cos(i * TAU / 8.0), sin(i * TAU / 8.0))
			ci.draw_line(c + d * s * 0.66, c + d * s * 0.98, col, s * 0.3)
	elif kind == "star":
		var pts := PackedVector2Array()
		for i in range(10):
			var r: float = s if i % 2 == 0 else s * 0.42
			var a: float = -PI * 0.5 + i * PI / 5.0
			pts.append(c + Vector2(cos(a), sin(a)) * r)
		ci.draw_colored_polygon(pts, col)
	elif kind == "gem":
		ci.draw_colored_polygon(PackedVector2Array([c + Vector2(-s * 0.72, -s * 0.2), c + Vector2(-s * 0.42, -s * 0.8), c + Vector2(s * 0.42, -s * 0.8), c + Vector2(s * 0.72, -s * 0.2), c + Vector2(0.0, s * 0.92)]), col)
		var dk: Color = col.darkened(0.4)
		ci.draw_line(c + Vector2(-s * 0.72, -s * 0.2), c + Vector2(s * 0.72, -s * 0.2), dk, maxf(1.5, s * 0.1))
		ci.draw_line(c + Vector2(-s * 0.25, -s * 0.2), c + Vector2(0.0, s * 0.92), dk, maxf(1.5, s * 0.1))
		ci.draw_line(c + Vector2(s * 0.25, -s * 0.2), c + Vector2(0.0, s * 0.92), dk, maxf(1.5, s * 0.1))
		ci.draw_line(c + Vector2(-s * 0.25, -s * 0.2), c + Vector2(-s * 0.42, -s * 0.8), dk, maxf(1.5, s * 0.1))
		ci.draw_line(c + Vector2(s * 0.25, -s * 0.2), c + Vector2(s * 0.42, -s * 0.8), dk, maxf(1.5, s * 0.1))
	elif kind == "bot":
		ci.draw_circle(c + Vector2(0.0, s * 0.12), s * 0.78, col)
		ci.draw_rect(Rect2(c + Vector2(-s * 0.55, -s * 0.18), Vector2(s * 1.1, s * 0.58)), Color(0.04, 0.07, 0.2))
		ci.draw_rect(Rect2(c + Vector2(-s * 0.38, -s * 0.06), Vector2(s * 0.24, s * 0.3)), Color(0.3, 0.95, 1.0))
		ci.draw_rect(Rect2(c + Vector2(s * 0.14, -s * 0.06), Vector2(s * 0.24, s * 0.3)), Color(0.3, 0.95, 1.0))
		ci.draw_line(c + Vector2(0.0, -s * 0.62), c + Vector2(0.0, -s * 0.95), col, maxf(1.5, s * 0.12))
		ci.draw_circle(c + Vector2(0.0, -s * 0.98), s * 0.14, col)
	elif kind == "check":
		ci.draw_polyline(PackedVector2Array([c + Vector2(-s * 0.7, s * 0.05), c + Vector2(-s * 0.2, s * 0.55), c + Vector2(s * 0.75, -s * 0.55)]), col, w, true)
	elif kind == "lock":
		ci.draw_rect(Rect2(c + Vector2(-s * 0.6, -s * 0.05), Vector2(s * 1.2, s * 0.95)), col)
		ci.draw_arc(c + Vector2(0.0, -s * 0.05), s * 0.4, PI, TAU, 16, col, w, true)
		ci.draw_line(c + Vector2(-s * 0.4, -s * 0.05), c + Vector2(-s * 0.4, s * 0.15), col, w)
		ci.draw_line(c + Vector2(s * 0.4, -s * 0.05), c + Vector2(s * 0.4, s * 0.15), col, w)
	elif kind == "jump":
		ci.draw_polyline(PackedVector2Array([c + Vector2(-s * 0.7, s * 0.0), c + Vector2(0.0, -s * 0.7), c + Vector2(s * 0.7, s * 0.0)]), col, w, true)
		ci.draw_polyline(PackedVector2Array([c + Vector2(-s * 0.7, s * 0.7), c + Vector2(0.0, 0.0), c + Vector2(s * 0.7, s * 0.7)]), col, w, true)
	elif kind == "dash":
		ci.draw_polyline(PackedVector2Array([c + Vector2(-s * 0.8, -s * 0.7), c + Vector2(-s * 0.1, 0.0), c + Vector2(-s * 0.8, s * 0.7)]), col, w, true)
		ci.draw_polyline(PackedVector2Array([c + Vector2(0.0, -s * 0.7), c + Vector2(s * 0.7, 0.0), c + Vector2(0.0, s * 0.7)]), col, w, true)
	elif kind == "close":
		ci.draw_line(c + Vector2(-s * 0.7, -s * 0.7), c + Vector2(s * 0.7, s * 0.7), col, w, true)
		ci.draw_line(c + Vector2(s * 0.7, -s * 0.7), c + Vector2(-s * 0.7, s * 0.7), col, w, true)
	elif kind == "arrow_right":
		ci.draw_line(c + Vector2(-s * 0.8, 0.0), c + Vector2(s * 0.7, 0.0), col, w, true)
		ci.draw_polyline(PackedVector2Array([c + Vector2(s * 0.1, -s * 0.6), c + Vector2(s * 0.8, 0.0), c + Vector2(s * 0.1, s * 0.6)]), col, w, true)
	elif kind == "arrow_left":
		ci.draw_line(c + Vector2(s * 0.8, 0.0), c + Vector2(-s * 0.7, 0.0), col, w, true)
		ci.draw_polyline(PackedVector2Array([c + Vector2(-s * 0.1, -s * 0.6), c + Vector2(-s * 0.8, 0.0), c + Vector2(-s * 0.1, s * 0.6)]), col, w, true)
	elif kind == "sound":
		ci.draw_colored_polygon(PackedVector2Array([c + Vector2(-s * 0.9, -s * 0.3), c + Vector2(-s * 0.4, -s * 0.3), c + Vector2(s * 0.1, -s * 0.8), c + Vector2(s * 0.1, s * 0.8), c + Vector2(-s * 0.4, s * 0.3), c + Vector2(-s * 0.9, s * 0.3)]), col)
		ci.draw_arc(c + Vector2(s * 0.1, 0.0), s * 0.5, -0.9, 0.9, 12, col, w * 0.8, true)
		ci.draw_arc(c + Vector2(s * 0.1, 0.0), s * 0.85, -0.9, 0.9, 12, col, w * 0.8, true)
	elif kind == "music":
		ci.draw_circle(c + Vector2(-s * 0.35, s * 0.6), s * 0.38, col)
		ci.draw_line(c + Vector2(-s * 0.0, s * 0.55), c + Vector2(s * 0.0, -s * 0.85), col, w * 0.9)
		ci.draw_polyline(PackedVector2Array([c + Vector2(0.0, -s * 0.85), c + Vector2(s * 0.75, -s * 0.45), c + Vector2(s * 0.75, -s * 0.05)]), col, w * 0.9, true)
	elif kind == "bolt":
		ci.draw_colored_polygon(PackedVector2Array([c + Vector2(s * 0.2, -s), c + Vector2(-s * 0.6, s * 0.15), c + Vector2(-s * 0.05, s * 0.15), c + Vector2(-s * 0.3, s), c + Vector2(s * 0.65, -s * 0.2), c + Vector2(s * 0.05, -s * 0.2)]), col)
	elif kind == "hex":
		var hp := PackedVector2Array()
		for i in range(6):
			var a: float = i * TAU / 6.0 + PI / 6.0
			hp.append(c + Vector2(cos(a), sin(a)) * s)
		ci.draw_colored_polygon(hp, col)
