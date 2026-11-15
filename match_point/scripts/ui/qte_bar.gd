class_name QteBar
extends Control
## مؤشرات مرتبطة بجسم اللاعب (بأسلوب TopSpin 2K25):
##  - شريط توقيت صغير فوق رأس اللاعب: أحمر (~60%) ← أصفر ← أخضر صغير أقصى اليمين
##  - دائرة شحن القوة بجانب اللاعب: تكتمل تدريجياً حتى دائرة كاملة عند أقصى قوة
##  - شريط اللياقة تحت قدمي اللاعب

var progress := 0.0
var green_w := 0.17
var yellow_w := 0.23
var stopped := false
var stop_p := 0.0
var charge := 0.0
var charging := false
var stamina := 1.0
var show_stamina := false
var label := ""
var label_col := Color.WHITE
var shown := false
var anchor_head := Vector2(-1000, -1000)
var anchor_side := Vector2(-1000, -1000)
var anchor_feet := Vector2(-1000, -1000)
var _alpha := 0.0
var _ring_a := 0.0
var _flash := 0.0
var _font: Font

const W := 92.0
const H := 6.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_font = UiKit.font_bold()


func red_end() -> float:
	return 1.0 - green_w - yellow_w


func zone_at(p: float) -> String:
	if p >= 1.0:
		return "end"
	if p >= 1.0 - green_w:
		return "green"
	if p >= red_end():
		return "yellow"
	return "red"


## الجودة واتجاه خطأ التوقيت عند نقطة التوقف
func quality_at(p: float) -> Array:
	var re := red_end()
	if p >= 1.0:
		return [-0.2, 1.0]
	if p >= 1.0 - green_w:
		# داخل الأخضر: المركز هو الإتقان التام، والأطراف أقل قليلاً (مبكر/متأخر خفيف)
		var off := clampf((p - (1.0 - green_w * 0.5)) / (green_w * 0.5), -1.0, 1.0)
		return [1.0 - 0.05 * absf(off), off * 0.12]
	if p >= re:
		var f := (p - re) / yellow_w
		return [0.62 + 0.28 * f, -(1.0 - f) * 0.5]
	var f2 := clampf(p / re, 0.0, 1.0)
	return [0.1 + 0.4 * f2, -(1.0 - 0.5 * f2)]


func start(gw: float) -> void:
	green_w = gw
	yellow_w = gw * 1.35
	progress = 0.0
	stopped = false
	label = ""
	shown = true


func stop(p: float, text: String, col: Color) -> void:
	stopped = true
	stop_p = clampf(p, 0.0, 1.0)
	label = text
	label_col = col
	_flash = 1.0


func hide_bar() -> void:
	shown = false


func _process(dt: float) -> void:
	_alpha = move_toward(_alpha, 1.0 if shown else 0.0, dt * (9.0 if shown else 3.0))
	_ring_a = move_toward(_ring_a, 1.0 if charging else 0.0, dt * (10.0 if charging else 4.0))
	_flash = maxf(_flash - dt * 3.0, 0.0)
	queue_redraw()


func _draw() -> void:
	_draw_stamina()
	_draw_ring()
	_draw_timing()


func _draw_timing() -> void:
	if _alpha <= 0.01:
		return
	var a := _alpha
	var x0 := anchor_head.x - W * 0.5
	var y0 := anchor_head.y - H
	var re := red_end()
	var ye := 1.0 - green_w
	draw_rect(Rect2(x0 - 2, y0 - 2, W + 4, H + 4), Color(0.02, 0.03, 0.06, 0.72 * a))
	draw_rect(Rect2(x0, y0, W * re, H), Color(0.82, 0.17, 0.14, 0.95 * a))
	draw_rect(Rect2(x0 + W * re, y0, W * (ye - re), H), Color(0.97, 0.80, 0.13, 0.97 * a))
	draw_rect(Rect2(x0 + W * ye, y0, W * green_w, H), Color(0.22, 0.88, 0.34, 0.98 * a))
	draw_rect(Rect2(x0, y0, W, H * 0.35), Color(1, 1, 1, 0.14 * a))
	var p := stop_p if stopped else clampf(progress, 0.0, 1.0)
	var px := x0 + W * p
	var col := Color(1, 1, 1, a)
	if stopped:
		col = label_col.lerp(Color.WHITE, _flash * 0.5)
		col.a = a
	draw_rect(Rect2(px - 2, y0 - 3, 4, H + 6), Color(0, 0, 0, 0.6 * a))
	draw_rect(Rect2(px - 1, y0 - 3, 2, H + 6), col)
	draw_colored_polygon(PackedVector2Array([Vector2(px - 4, y0 - 8), Vector2(px + 4, y0 - 8), Vector2(px, y0 - 3)]), col)
	if label != "":
		var fs := 13
		var ts := _font.get_string_size(label, HORIZONTAL_ALIGNMENT_CENTER, -1, fs)
		var lp := Vector2(anchor_head.x - ts.x * 0.5, y0 - 11)
		draw_string_outline(_font, lp, label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 5, Color(0, 0, 0, 0.85 * a))
		draw_string(_font, lp, label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(label_col.r, label_col.g, label_col.b, a))


func _draw_ring() -> void:
	if _ring_a <= 0.01:
		return
	var a := _ring_a
	var c := anchor_side
	var rad := 15.0
	draw_circle(c, rad + 4.0, Color(0.02, 0.03, 0.06, 0.6 * a))
	draw_arc(c, rad, 0.0, TAU, 40, Color(1, 1, 1, 0.18 * a), 5.0, true)
	var ch := clampf(charge, 0.0, 1.0)
	var col := Color(0.98, 0.9, 0.3).lerp(Color(1.0, 0.45, 0.15), smoothstep(0.5, 1.0, ch))
	if ch >= 0.999:
		col = Color(1.0, 0.25, 0.2)
	if ch > 0.0:
		draw_arc(c, rad, -PI * 0.5, -PI * 0.5 + TAU * ch, 48, Color(col.r, col.g, col.b, a), 5.0, true)
	var txt := str(int(round(ch * 100.0)))
	var ts := _font.get_string_size(txt, HORIZONTAL_ALIGNMENT_CENTER, -1, 13)
	draw_string(_font, c + Vector2(-ts.x * 0.5, 5), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(1, 1, 1, 0.95 * a))


func _draw_stamina() -> void:
	if not show_stamina:
		return
	var w := 64.0
	var x0 := anchor_feet.x - w * 0.5
	var y0 := anchor_feet.y + 8.0
	var s := clampf(stamina, 0.0, 1.0)
	var col := Color(0.30, 0.90, 0.45)
	if s < 0.6:
		col = Color(0.98, 0.82, 0.25).lerp(Color(0.30, 0.90, 0.45), (s - 0.3) / 0.3) if s > 0.3 else Color(0.95, 0.30, 0.22).lerp(Color(0.98, 0.82, 0.25), s / 0.3)
	draw_rect(Rect2(x0 - 2, y0 - 2, w + 4, 9), Color(0.02, 0.03, 0.06, 0.7))
	draw_rect(Rect2(x0, y0, w * s, 5), col)
