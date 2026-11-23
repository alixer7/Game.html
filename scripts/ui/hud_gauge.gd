class_name HudGauge
extends Control
## Speedometer arc + boost reserve bar + power-slide charge meter.
## The meter shows the hot zone (valid tap) and the perfect zone, plus 3 pips
## for the stages of the current slide.

var kart: Kart


func _draw() -> void:
	if kart == null:
		return
	var font := get_theme_default_font()
	var c := Vector2(size.x * 0.5, size.y * 0.78)
	var R := 120.0
	var p := kart.params
	# --- speed arc
	var top := p.max_speed * (1.0 + p.overdrive_bonus) * 1.08
	var f := clampf(kart.speed / top, 0.0, 1.0)
	var a0 := PI * 1.05
	var a1 := PI * 1.95
	draw_arc(c, R, a0, a1, 48, Color(0.05, 0.07, 0.12, 0.6), 16.0, true)
	var col := UIKit.CREAM
	if kart.tier == 1:
		col = UIKit.ORANGE
	elif kart.tier == 2:
		col = UIKit.TEAL
	draw_arc(c, R, a0, lerpf(a0, a1, f), 48, col, 12.0, true)
	var kmh := int(kart.speed * 3.6)
	var txt := str(kmh)
	var sz := font.get_string_size(txt, HORIZONTAL_ALIGNMENT_CENTER, -1, 54)
	draw_string_outline(font, c + Vector2(-sz.x * 0.5, -22), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 54, 10, Color(0, 0, 0, 0.8))
	draw_string(font, c + Vector2(-sz.x * 0.5, -22), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 54, col)
	draw_string(font, c + Vector2(-22, 2), "km/h", HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color(1, 1, 1, 0.7))
	# --- reserve bar (segmented in seconds)
	var bw := 300.0
	var bx := c.x - bw * 0.5
	var by := c.y + 14.0
	draw_rect(Rect2(bx - 3, by - 3, bw + 6, 20), Color(0.05, 0.07, 0.12, 0.7))
	var rf := clampf(kart.reserve / p.reserve_cap, 0.0, 1.0)
	draw_rect(Rect2(bx, by, bw * rf, 14), col if kart.tier > 0 else Color(0.6, 0.6, 0.65))
	var od := p.overdrive_threshold / p.reserve_cap
	draw_line(Vector2(bx + bw * od, by - 4), Vector2(bx + bw * od, by + 18), UIKit.TEAL, 2.0)
	for s in range(1, int(p.reserve_cap)):
		var x := bx + bw * float(s) / p.reserve_cap
		draw_line(Vector2(x, by), Vector2(x, by + 14), Color(0, 0, 0, 0.5), 2.0)
	draw_string(font, Vector2(bx, by + 36), "RESERVE %.1fs" % kart.reserve, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color(1, 1, 1, 0.8))
	# --- drift meter (only while sliding)
	if kart.drifting:
		var mr := 70.0
		var mc := c + Vector2(0, -64)
		var m0 := PI * 1.15
		var m1 := PI * 1.85
		draw_arc(mc, mr, m0, m1, 32, Color(0.05, 0.07, 0.12, 0.7), 14.0, true)
		draw_arc(mc, mr, lerpf(m0, m1, p.hot_zone), m1, 16, Color(1.0, 0.7, 0.15, 0.6), 14.0, true)
		draw_arc(mc, mr, lerpf(m0, m1, p.perfect_zone), m1, 8, Color(1.0, 0.3, 0.35, 0.9), 14.0, true)
		var ch := clampf(kart.drift_charge, 0.0, 1.0)
		var na := lerpf(m0, m1, ch)
		draw_line(mc, mc + Vector2(cos(na), sin(na)) * (mr + 10.0), Color.WHITE, 4.0, true)
		for s in 3:
			var pc := mc + Vector2(-26 + s * 26, 18)
			var filled := s < kart.drift_stage
			draw_circle(pc, 8, UIKit.ORANGE if filled else Color(0.2, 0.22, 0.3, 0.8))
