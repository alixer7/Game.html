class_name HudItem
extends Control
## Held item icon (drawn) + amber counter. Shows a short roulette when granted.

var items: ItemSystem
var player: Kart
var _roll := 0.0
var _shown := ""


func setup(it: ItemSystem, k: Kart) -> void:
	items = it
	player = k
	items.item_changed.connect(func(kk: Kart, item: String) -> void:
		if kk == player and item != "":
			_roll = 0.7)


func _process(dt: float) -> void:
	if _roll > 0.0:
		_roll -= dt
		if int(_roll * 20.0) % 2 == 0:
			Sfx.play("item_roll", null, 1.0, -10.0)


func _draw() -> void:
	if items == null:
		return
	var c := size * 0.5
	draw_circle(c, 54, Color(0.05, 0.07, 0.12, 0.6))
	draw_arc(c, 54, 0, TAU, 40, Color(1, 1, 1, 0.5), 3.0, true)
	var it := items.item_of(player)
	if _roll > 0.0:
		it = ["bomb", "hornet", "trap", "shield", "spark"][int(_roll * 14.0) % 5]
	var charged := player.amber >= 10
	match it:
		"bomb":
			draw_circle(c, 26, Color(0.45, 0.25, 0.55))
			for i in 8:
				var a := TAU * i / 8.0
				draw_line(c + Vector2(cos(a), sin(a)) * 22, c + Vector2(cos(a), sin(a)) * 36, Color(0.95, 0.9, 0.6), 4.0)
		"hornet":
			draw_circle(c + Vector2(6, 0), 18, Color(1.0, 0.82, 0.15))
			draw_circle(c + Vector2(-16, 0), 12, Color(0.12, 0.12, 0.12))
			draw_line(c + Vector2(0, -16), c + Vector2(8, 16), Color(0.1, 0.1, 0.1), 5.0)
			draw_circle(c + Vector2(4, -22), 10, Color(0.85, 0.95, 1.0, 0.8))
		"trap":
			draw_circle(c, 24, Color(0.3, 0.5, 0.15))
			for i in 10:
				var a := TAU * i / 10.0
				draw_line(c + Vector2(cos(a), sin(a)) * 18, c + Vector2(cos(a), sin(a)) * 32, Color(0.9, 0.25, 0.3), 4.0)
		"shield":
			draw_circle(c, 30, Color(0.3, 0.7, 1.0, 0.5))
			draw_arc(c, 30, 0, TAU, 32, Color(0.75, 0.95, 1.0), 4.0, true)
		"spark":
			var pts := PackedVector2Array([c + Vector2(-8, -34), c + Vector2(14, -6), c + Vector2(2, -4), c + Vector2(10, 32), c + Vector2(-14, 2), c + Vector2(-2, 0)])
			draw_colored_polygon(pts, Color(1.0, 0.75, 0.15))
	if charged and it != "":
		draw_arc(c, 46, 0, TAU, 40, Color(1.0, 0.6, 0.1), 5.0, true)
	var font := get_theme_default_font()
	var txt := "%d" % player.amber
	draw_circle(c + Vector2(48, 44), 16, Color(0.95, 0.5, 0.05))
	draw_string(font, c + Vector2(40, 52), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color.WHITE)
