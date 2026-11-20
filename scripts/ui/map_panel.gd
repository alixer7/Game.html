extends ModalPanel
## خريطة العالم: البيئات المكتشفة، المستوطنات، العلامات، موقعك، والسرير.

var view: Control
var zoom := 1.0
var legend: VBoxContainer

class MapView extends Control:
	var world: Node
	var zoom := 1.0
	func _draw() -> void:
		var r := Rect2(Vector2.ZERO, size)
		draw_rect(r, Color(0.04, 0.06, 0.09))
		if world == null:
			return
		var side := minf(size.x, size.y)
		var p: Vector3 = world.player.global_position
		var span := WorldGen.HALF * 2.0 / zoom
		var cx := p.x if zoom > 1.0 else 0.0
		var cz := p.z if zoom > 1.0 else 0.0
		cx = clampf(cx, -WorldGen.HALF + span * 0.5, WorldGen.HALF - span * 0.5)
		cz = clampf(cz, -WorldGen.HALF + span * 0.5, WorldGen.HALF - span * 0.5)
		var dst := Rect2((size.x - side) * 0.5, (size.y - side) * 0.5, side, side)
		if world.map_texture:
			var px := 256.0 / (WorldGen.HALF * 2.0)
			draw_texture_rect_region(world.map_texture, dst, Rect2((cx - span * 0.5 + WorldGen.HALF) * px, (cz - span * 0.5 + WorldGen.HALF) * px, span * px, span * px))
			var ex := float(World.EXPLORE_RES) / (WorldGen.HALF * 2.0)
			draw_texture_rect_region(world.explored_tex, dst, Rect2((cx - span * 0.5 + WorldGen.HALF) * ex, (cz - span * 0.5 + WorldGen.HALF) * ex, span * ex, span * ex), Color(0.03, 0.04, 0.06, 0.86))
		else:
			var font0 := get_theme_default_font()
			draw_string(font0, dst.get_center() - Vector2(80, 0), "جارِ رسم الخريطة...", HORIZONTAL_ALIGNMENT_LEFT, -1, 24)
		draw_rect(dst, Color(0.9, 0.75, 0.45, 0.6), false, 2.0)
		var font := get_theme_default_font()
		var to_px := side / span
		var origin := dst.get_center()
		var f := func(wp: Vector3) -> Vector2: return origin + Vector2(wp.x - cx, wp.z - cz) * to_px
		for s in world.ai.settlements:
			if not s["discovered"]:
				continue
			var sp: Vector2 = f.call(s["pos"])
			draw_circle(sp, 7.0, Color(1, 0.3, 0.25) if s["hostile"] else Color(1, 0.88, 0.35))
			draw_arc(sp, 7.0, 0, TAU, 16, Color(0, 0, 0), 2.0)
			draw_string_outline(font, sp + Vector2(10, 6), s["name"], HORIZONTAL_ALIGNMENT_LEFT, -1, 17, 4, Color(0, 0, 0))
			draw_string(font, sp + Vector2(10, 6), s["name"], HORIZONTAL_ALIGNMENT_LEFT, -1, 17, Color(1, 0.95, 0.8))
		for m in world.ai.markers:
			var mp: Vector2 = f.call(m["pos"])
			draw_circle(mp, 5.0, m["col"])
			draw_string_outline(font, mp + Vector2(8, 5), m["label"], HORIZONTAL_ALIGNMENT_LEFT, -1, 15, 4, Color(0, 0, 0))
			draw_string(font, mp + Vector2(8, 5), m["label"], HORIZONTAL_ALIGNMENT_LEFT, -1, 15, m["col"])
		var bed = world.player.bed
		if bed != null and is_instance_valid(bed):
			var bp: Vector2 = f.call(bed.global_position)
			draw_rect(Rect2(bp - Vector2(5, 5), Vector2(10, 10)), Color(0.5, 0.8, 1))
			draw_string(font, bp + Vector2(8, 5), "سريرك", HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(0.6, 0.85, 1))
		var pp: Vector2 = f.call(p)
		var yaw: float = world.player.cam_yaw.rotation.y
		var fwd := Vector2(-sin(yaw), -cos(yaw))
		var right := Vector2(fwd.y, -fwd.x)
		draw_colored_polygon(PackedVector2Array([pp + fwd * 14, pp - fwd * 8 + right * 8, pp - fwd * 8 - right * 8]), Color(1, 1, 1))
		draw_string_outline(font, Vector2(dst.position.x + side * 0.5 - 10, dst.position.y + 26), "شمال", HORIZONTAL_ALIGNMENT_LEFT, -1, 18, 4, Color(0, 0, 0))
		draw_string(font, Vector2(dst.position.x + side * 0.5 - 10, dst.position.y + 26), "شمال", HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color(1, 0.85, 0.5))

func build() -> void:
	make_frame("خريطة العالم", 0.02)
	var row := UIKit.hbox(12)
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(row)
	legend = UIKit.vbox(6)
	legend.custom_minimum_size = Vector2(260, 0)
	row.add_child(legend)
	view = MapView.new()
	view.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	view.size_flags_vertical = Control.SIZE_EXPAND_FILL
	view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(view)

func refresh() -> void:
	view.world = world()
	view.zoom = zoom
	view.queue_redraw()
	clear(legend)
	legend.add_child(UIKit.button("تكبير", func(): zoom = minf(zoom * 2.0, 8.0); refresh(), 20, 54))
	legend.add_child(UIKit.button("تصغير", func(): zoom = maxf(zoom / 2.0, 1.0); refresh(), 20, 54))
	legend.add_child(UIKit.button("ضع علامة هنا", func(): world().ai.add_marker(player().global_position, "علامتي", Color(0.4, 1, 0.6)); refresh(), 18, 54))
	legend.add_child(UIKit.button("امسح علاماتي", _clear_marks, 18, 54))
	var p := player().global_position
	legend.add_child(UIKit.label("موقعك: %d ، %d   الارتفاع: %d م" % [int(p.x), int(p.z), int(p.y)], 16, UIKit.DIM))
	legend.add_child(UIKit.sep())
	legend.add_child(UIKit.label("البيئات:", 18, UIKit.GOLD))
	var hints := ["الشاطئ: نخيل، رمل، ملح", "السهول: قطن، قمح، أرانب", "الغابة: خشب، توت، أعشاب، غزلان، ذئاب", "المستنقعات: طين، قصب، تماسيح", "الصحراء: صبار، ذهب، حر شديد", "الصنوبر: راتنج، حديد، دببة", "التندرا: جليد وبرد قارس", "الجبال: نحاس، قصدير، حديد، فحم", "القمم الثلجية: كريستال وجواهر", "البركان: سبج وكبريت وحمم"]
	for h in hints:
		legend.add_child(UIKit.label(h, 15, UIKit.DIM))

func _clear_marks() -> void:
	var ai: Node = world().ai
	var keep := []
	for m in ai.markers:
		if m["label"] != "علامتي":
			keep.append(m)
	ai.markers = keep
	refresh()

func _process(_dt: float) -> void:
	if visible and view:
		view.queue_redraw()
