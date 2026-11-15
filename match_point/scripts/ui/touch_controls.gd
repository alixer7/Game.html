class_name TouchControls
extends Control
## التحكم اللمسي: عصا تحكم عائمة يساراً + أزرار ضربات يميناً.
## الضغط على زر = بدء التحضير وشحن القوة، السحب = التصويب، الإفلات = تنفيذ الضربة.

signal shot_pressed(index: int)
signal shot_aim(aim: Vector2)
signal shot_released(index: int)

const STICK_R := 86.0
const AIM_R := 105.0

var move := Vector2.ZERO          # x يمين ، y للأسفل (خلف)
var serve_mode := false
var charge := 0.0                 # 0..1 لعرض حلقة القوة
var ring := -1.0                  # حلقة التوقيت: 1 = اللحظة المثالية ، <0 مخفية
var active_button := -1
var aim := Vector2.ZERO
var enabled := true
var opacity := 0.9

var _stick_id := -1
var _stick_origin := Vector2.ZERO
var _stick_pos := Vector2.ZERO
var _btn_id := -1
var _btn_origin := Vector2.ZERO
var _font: Font
var _keys := {}

const LABELS := ["لولبية", "مسطّحة", "مقطوعة", "عالية"]
const SERVE_LABELS := ["كيك", "مسطّح", "سلايس", ""]
const COLORS := [Color(0.84, 0.93, 0.22), Color(0.95, 0.45, 0.25), Color(0.35, 0.75, 0.95), Color(0.80, 0.55, 0.95)]


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layout_direction = Control.LAYOUT_DIRECTION_LTR
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_font = UiKit.font_bold()
	resized.connect(queue_redraw)


func button_center(i: int) -> Vector2:
	var w := size.x
	var h := size.y
	match i:
		0: return Vector2(w - 158, h - 150)
		1: return Vector2(w - 305, h - 104)
		2: return Vector2(w - 104, h - 300)
		3: return Vector2(w - 276, h - 262)
	return Vector2.ZERO


func button_radius(i: int) -> float:
	return [66.0, 54.0, 54.0, 48.0][i]


func reset() -> void:
	_stick_id = -1
	_btn_id = -1
	move = Vector2.ZERO
	if active_button >= 0:
		active_button = -1
	aim = Vector2.ZERO
	queue_redraw()


func _input(event: InputEvent) -> void:
	if not enabled or not is_visible_in_tree():
		return
	if event is InputEventScreenTouch:
		var e := event as InputEventScreenTouch
		var p := _to_local(e.position)
		if e.pressed:
			var b := _hit_button(p)
			if b >= 0 and _btn_id == -1:
				_btn_id = e.index
				_btn_origin = p
				active_button = b
				aim = Vector2.ZERO
				shot_pressed.emit(b)
			elif _stick_id == -1 and p.x < size.x * 0.5 and p.y > size.y * 0.16:
				_stick_id = e.index
				_stick_origin = p
				_stick_pos = p
				move = Vector2.ZERO
		else:
			if e.index == _stick_id:
				_stick_id = -1
				move = Vector2.ZERO
			elif e.index == _btn_id:
				_btn_id = -1
				var b2 := active_button
				active_button = -1
				shot_released.emit(b2)
		queue_redraw()
	elif event is InputEventScreenDrag:
		var d := event as InputEventScreenDrag
		var p2 := _to_local(d.position)
		if d.index == _stick_id:
			_stick_pos = p2
			var v := (p2 - _stick_origin)
			# العصا تتبع الإصبع إن ابتعد كثيراً (لا تفقد التحكم)
			if v.length() > STICK_R * 1.25:
				_stick_origin = p2 - v.normalized() * STICK_R * 1.25
				v = p2 - _stick_origin
			var m := v / STICK_R
			var l := m.length()
			if l < 0.12:
				move = Vector2.ZERO
			else:
				move = m.normalized() * clampf((l - 0.12) / 0.78, 0.0, 1.0)
		elif d.index == _btn_id:
			var a := (p2 - _btn_origin) / AIM_R
			aim = Vector2(clampf(a.x, -1.0, 1.0), clampf(-a.y, -1.0, 1.0))
			shot_aim.emit(aim)
		queue_redraw()


func _to_local(p: Vector2) -> Vector2:
	return get_global_transform_with_canvas().affine_inverse() * p


func _hit_button(p: Vector2) -> int:
	var best := -1
	var best_d := 1e9
	var n := 3 if serve_mode else 4
	for i in n:
		var d := p.distance_to(button_center(i))
		if d < button_radius(i) * 1.3 and d < best_d:
			best_d = d
			best = i
	return best


# --- لوحة المفاتيح للتجربة على الحاسوب: WASD للحركة، J/K/L/I للضربات، الأسهم للتصويب ---
func _unhandled_key_input(event: InputEvent) -> void:
	if not enabled or not is_visible_in_tree():
		return
	var k := event as InputEventKey
	if k == null or k.echo:
		return
	_keys[k.keycode] = k.pressed
	var map := {KEY_J: 0, KEY_K: 1, KEY_L: 2, KEY_I: 3}
	if map.has(k.keycode):
		var b: int = map[k.keycode]
		if k.pressed and active_button == -1 and _btn_id == -1:
			active_button = b
			aim = Vector2.ZERO
			shot_pressed.emit(b)
		elif not k.pressed and active_button == b and _btn_id == -1:
			active_button = -1
			shot_released.emit(b)
	queue_redraw()


func _process(_dt: float) -> void:
	if _stick_id == -1:
		var kv := Vector2.ZERO
		if _keys.get(KEY_A, false): kv.x -= 1.0
		if _keys.get(KEY_D, false): kv.x += 1.0
		if _keys.get(KEY_W, false): kv.y -= 1.0
		if _keys.get(KEY_S, false): kv.y += 1.0
		move = kv.normalized() if kv != Vector2.ZERO else Vector2.ZERO
	if active_button >= 0 and _btn_id == -1:
		var av := Vector2.ZERO
		if _keys.get(KEY_LEFT, false): av.x -= 1.0
		if _keys.get(KEY_RIGHT, false): av.x += 1.0
		if _keys.get(KEY_UP, false): av.y += 1.0
		if _keys.get(KEY_DOWN, false): av.y -= 1.0
		if av != aim:
			aim = av
			shot_aim.emit(aim)
	if active_button >= 0 or _stick_id != -1 or ring >= 0.0:
		queue_redraw()


func _draw() -> void:
	if not enabled:
		return
	var a := opacity
	# ---- العصا ----
	var base := _stick_origin if _stick_id != -1 else Vector2(178, size.y - 172)
	var idle := _stick_id == -1
	draw_circle(base, STICK_R + 8.0, Color(0.02, 0.04, 0.08, (0.18 if idle else 0.32) * a))
	draw_arc(base, STICK_R + 8.0, 0, TAU, 64, Color(1, 1, 1, (0.22 if idle else 0.5) * a), 2.5, true)
	var knob := base + move * STICK_R
	draw_circle(knob, 36.0, Color(1, 1, 1, (0.22 if idle else 0.55) * a))
	draw_arc(knob, 36.0, 0, TAU, 40, Color(1, 1, 1, 0.7 * a), 2.0, true)

	# ---- الأزرار ----
	var n := 3 if serve_mode else 4
	for i in n:
		var c := button_center(i)
		var r := button_radius(i)
		var col: Color = COLORS[i]
		var act := i == active_button
		draw_circle(c, r, Color(0.03, 0.05, 0.10, (0.62 if act else 0.42) * a))
		draw_arc(c, r, 0, TAU, 64, Color(col.r, col.g, col.b, (1.0 if act else 0.75) * a), 4.0 if act else 3.0, true)
		if act:
			draw_circle(c, r - 5.0, Color(col.r, col.g, col.b, 0.22 * a))
			# حلقة القوة
			if charge > 0.0 and not serve_mode:
				draw_arc(c, r + 9.0, -PI * 0.5, -PI * 0.5 + TAU * charge, 48, Color(1, 1, 1, 0.95 * a), 5.0, true)
			# حلقة التوقيت: تنكمش نحو حافة الزر — أفلِت عند التطابق
			if ring >= 0.0:
				var off := (1.0 - ring)
				var rr := r + 12.0 + clampf(off, -0.25, 1.4) * 120.0
				var good := absf(off) < 0.07
				var rc := Color(0.3, 1.0, 0.45) if good else Color(1, 1, 1)
				draw_arc(c, maxf(rr, r - 14.0), 0, TAU, 72, Color(rc.r, rc.g, rc.b, 0.9 * a), 4.5 if good else 3.0, true)
			# مؤشر التصويب
			var tip := c + Vector2(aim.x, -aim.y) * (r + 34.0)
			draw_line(c, tip, Color(1, 1, 1, 0.55 * a), 3.0, true)
			draw_circle(tip, 11.0, Color(col.r, col.g, col.b, 0.95 * a))
		var txt: String = SERVE_LABELS[i] if serve_mode else LABELS[i]
		var fs := 23 if i == 0 else 19
		var ts := _font.get_string_size(txt, HORIZONTAL_ALIGNMENT_CENTER, -1, fs)
		draw_string(_font, c + Vector2(-ts.x * 0.5, fs * 0.36), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(1, 1, 1, 0.96 * a))
