class_name HudMinimap
extends Control
## North-up minimap of every drivable route with racer dots.

var tb: TrackBuilder
var race: RaceManager
var player: Kart
var _lines: Array = []      # PackedVector2Array per route (normalised)
var _bounds := Rect2()


func setup(builder: TrackBuilder, r: RaceManager, k: Kart) -> void:
	tb = builder
	race = r
	player = k
	var mn := Vector2(INF, INF)
	var mx := Vector2(-INF, -INF)
	for p in tb.main.pos:
		mn = mn.min(Vector2(p.x, p.z))
		mx = mx.max(Vector2(p.x, p.z))
	_bounds = Rect2(mn, mx - mn)
	_lines.append([_poly(tb.main, true), true])
	for id in tb.branches:
		if id == "river_upstream":
			continue
		_lines.append([_poly(tb.branches[id], false), false])


func _poly(sp: SplinePath, closed: bool) -> PackedVector2Array:
	var out := PackedVector2Array()
	for i in range(0, sp.size(), 3):
		if sp.style[i] == "gap" and not closed:
			continue
		out.append(Vector2(sp.pos[i].x, sp.pos[i].z))
	if closed and out.size() > 0:
		out.append(out[0])
	return out


func _map(p: Vector2) -> Vector2:
	var s := minf(size.x / _bounds.size.x, size.y / _bounds.size.y) * 0.92
	var off := (size - _bounds.size * s) * 0.5
	return (p - _bounds.position) * s + off


func _draw() -> void:
	if tb == null:
		return
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.05, 0.07, 0.12, 0.35), true)
	for entry in _lines:
		var pts: PackedVector2Array = entry[0]
		var mapped := PackedVector2Array()
		for p in pts:
			mapped.append(_map(p))
		if mapped.size() >= 2:
			draw_polyline(mapped, Color(0, 0, 0, 0.6), 7.0 if entry[1] else 5.0, true)
			draw_polyline(mapped, Color(1, 0.95, 0.85, 0.95) if entry[1] else Color(1, 0.8, 0.5, 0.7), 4.0 if entry[1] else 2.5, true)
	var s := tb.main.pos[tb.mark_index("start_line")]
	var sp := _map(Vector2(s.x, s.z))
	draw_rect(Rect2(sp - Vector2(5, 5), Vector2(10, 10)), Color(1, 1, 1))
	if race == null:
		return
	for k in race.karts:
		var kp := _map(Vector2(k.global_position.x, k.global_position.z))
		if k == player:
			continue
		var col: Color = k.get_meta("color", Color(0.9, 0.3, 0.3))
		draw_circle(kp, 6.0, Color(0, 0, 0, 0.7))
		draw_circle(kp, 4.5, col)
	var pp := _map(Vector2(player.global_position.x, player.global_position.z))
	var h := player.heading()
	var d := Vector2(h.x, h.z).normalized()
	var r := Vector2(-d.y, d.x)
	var tri := PackedVector2Array([pp + d * 11.0, pp - d * 7.0 + r * 7.0, pp - d * 7.0 - r * 7.0])
	draw_colored_polygon(tri, Color(1, 0.85, 0.2))
	draw_polyline(PackedVector2Array([tri[0], tri[1], tri[2], tri[0]]), Color(0, 0, 0, 0.8), 2.0)
