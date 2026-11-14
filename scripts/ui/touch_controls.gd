class_name TouchControls
extends Control
## Multi-touch game controls: floating analog stick on one side and an arc of
## action buttons on the other (jump, boost with meter, drift/air-roll,
## ball-cam) plus a pause button. Everything is vector-drawn.

signal pause_pressed
signal ballcam_toggled
signal reset_pressed

enum Btn { NONE = -1, JUMP, BOOST, DRIFT, CAM, PAUSE, RESET }

var stick := Vector2.ZERO          # x right, y up
var jump_held := false
var boost_held := false
var drift_held := false
var boost_amount := 33.0
var ball_cam := true
var show_reset := false
var enabled := true
var touch_seen := false

var _stick_touch := -1
var _stick_base := Vector2.ZERO
var _stick_pos := Vector2.ZERO
var _stick_alpha := 0.0
var _btn_touch := {}   # touch index -> Btn
var _btn_pressed := [false, false, false, false, false, false]
var _btn_anim := [0.0, 0.0, 0.0, 0.0, 0.0, 0.0]
var _centers: Array[Vector2] = []
var _radii: Array[float] = []
var _font: Font
var _pulse := 0.0
var _mouse_touch := false


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_font = UiTheme.font_black()
	for i in range(6):
		_centers.append(Vector2.ZERO)
		_radii.append(10.0)
	resized.connect(_layout)
	Settings.changed.connect(_layout)
	_layout()


func _safe_margins() -> Rect2:
	var vp := get_viewport_rect().size
	var win := Vector2(DisplayServer.window_get_size())
	var safe := Rect2(DisplayServer.get_display_safe_area())
	if win.x <= 0 or safe.size.x <= 0 or not OS.has_feature("mobile"):
		return Rect2(Vector2.ZERO, vp)
	var sc := vp / win
	return Rect2(safe.position * sc, safe.size * sc)


func _layout() -> void:
	var r := _safe_margins()
	var bs: float = Settings.get_value("button_size", 1.0)
	var left: bool = Settings.get_value("left_handed", false)
	var right_edge := r.position.x + r.size.x
	var bottom := r.position.y + r.size.y
	var pts := {
		Btn.JUMP: Vector2(-150, -140), Btn.BOOST: Vector2(-330, -100),
		Btn.DRIFT: Vector2(-118, -318), Btn.CAM: Vector2(-292, -282),
	}
	var radii := {Btn.JUMP: 80.0, Btn.BOOST: 68.0, Btn.DRIFT: 52.0, Btn.CAM: 40.0}
	for b in pts:
		var off: Vector2 = pts[b] * Vector2(1.0, 1.0) * lerpf(1.0, bs, 0.8)
		var c := Vector2(right_edge + off.x, bottom + off.y)
		if left:
			c.x = r.position.x - off.x
		_centers[b] = c
		_radii[b] = radii[b] * bs
	_centers[Btn.PAUSE] = Vector2(r.position.x + 56, r.position.y + 50)
	if left:
		_centers[Btn.PAUSE].x = right_edge - 56
	_radii[Btn.PAUSE] = 30.0
	_centers[Btn.RESET] = Vector2(right_edge - 60, r.position.y + 50)
	if left:
		_centers[Btn.RESET].x = r.position.x + 60
	_radii[Btn.RESET] = 34.0
	queue_redraw()


func reset_state() -> void:
	_stick_touch = -1
	stick = Vector2.ZERO
	_btn_touch.clear()
	for i in range(_btn_pressed.size()):
		_btn_pressed[i] = false
	jump_held = false
	boost_held = false
	drift_held = false


func _stick_zone(p: Vector2) -> bool:
	var vp := get_viewport_rect().size
	var left: bool = Settings.get_value("left_handed", false)
	if p.y < vp.y * 0.18:
		return false
	return p.x > vp.x * 0.55 if left else p.x < vp.x * 0.45


func _hit_button(p: Vector2) -> int:
	var best := -1
	var best_d := 1e9
	for b in [Btn.JUMP, Btn.BOOST, Btn.DRIFT, Btn.CAM, Btn.PAUSE, Btn.RESET]:
		if b == Btn.RESET and not show_reset:
			continue
		var d := p.distance_to(_centers[b])
		var reach := _radii[b] * (1.3 if b != Btn.PAUSE else 1.6)
		if d < reach and d / reach < best_d:
			best_d = d / reach
			best = b
	return best


func _input(event: InputEvent) -> void:
	if not enabled or not is_visible_in_tree():
		return
	if event is InputEventScreenTouch:
		touch_seen = true
		var e := event as InputEventScreenTouch
		if e.pressed:
			_on_press(e.index, e.position)
		else:
			_on_release(e.index)
	elif event is InputEventScreenDrag:
		var d := event as InputEventScreenDrag
		if d.index == _stick_touch:
			_move_stick(d.position)


func _on_press(idx: int, p: Vector2) -> void:
	var b := _hit_button(p)
	if b != -1:
		_btn_touch[idx] = b
		_btn_pressed[b] = true
		_btn_anim[b] = 1.0
		match b:
			Btn.JUMP:
				jump_held = true
				Settings.vibrate(12, 0.35)
			Btn.BOOST:
				boost_held = true
				Settings.vibrate(8, 0.25)
			Btn.DRIFT:
				drift_held = true
			Btn.CAM:
				ball_cam = not ball_cam
				ballcam_toggled.emit()
				Sfx.play("click", -8.0)
			Btn.PAUSE:
				pause_pressed.emit()
			Btn.RESET:
				reset_pressed.emit()
		get_viewport().set_input_as_handled()
		queue_redraw()
		return
	if _stick_touch == -1 and _stick_zone(p):
		_stick_touch = idx
		var rj := _stick_radius()
		var vp := get_viewport_rect().size
		_stick_base = Vector2(clampf(p.x, rj + 16, vp.x - rj - 16), clampf(p.y, rj + 16, vp.y - rj - 16))
		_move_stick(p)
		get_viewport().set_input_as_handled()


func _on_release(idx: int) -> void:
	if idx == _stick_touch:
		_stick_touch = -1
		stick = Vector2.ZERO
	if _btn_touch.has(idx):
		var b: int = _btn_touch[idx]
		_btn_touch.erase(idx)
		var still := false
		for k in _btn_touch:
			if _btn_touch[k] == b:
				still = true
		if not still:
			_btn_pressed[b] = false
			match b:
				Btn.JUMP:
					jump_held = false
				Btn.BOOST:
					boost_held = false
				Btn.DRIFT:
					drift_held = false
	queue_redraw()


func _stick_radius() -> float:
	return 92.0 * float(Settings.get_value("joystick_size", 1.0))


func _move_stick(p: Vector2) -> void:
	var rj := _stick_radius()
	var off := p - _stick_base
	if off.length() > rj:
		# floating stick: drag the base along with the thumb
		_stick_base = p - off.normalized() * rj
		off = p - _stick_base
	_stick_pos = p
	var v := off / rj
	v.y = -v.y
	var m := v.length()
	var dead := 0.09
	if m < dead:
		stick = Vector2.ZERO
		return
	var dir := v / m
	var mag := clampf((m - dead) / (1.0 - dead), 0.0, 1.0)
	var sens: float = Settings.get_value("steer_sensitivity", 1.0)
	mag = pow(mag, 1.0 / maxf(0.4, sens))
	# map circle to square so diagonals reach full throttle and full steer
	var sq := 1.0 / maxf(absf(dir.x), absf(dir.y))
	var s := dir * mag * lerpf(1.0, sq, 0.85)
	stick = Vector2(clampf(s.x, -1, 1), clampf(s.y, -1, 1))


func _process(delta: float) -> void:
	_pulse += delta
	var target := 1.0 if _stick_touch != -1 else 0.0
	_stick_alpha = move_toward(_stick_alpha, target, delta * 8.0)
	for i in range(_btn_anim.size()):
		_btn_anim[i] = move_toward(_btn_anim[i], 0.0, delta * 5.0)
	queue_redraw()


# ------------------------------------------------------------------ drawing

func _draw() -> void:
	if not enabled:
		return
	var op: float = Settings.get_value("controls_opacity", 0.85)
	var rj := _stick_radius()
	var vp := get_viewport_rect().size
	var left: bool = Settings.get_value("left_handed", false)
	# stick
	var base := _stick_base
	var knob := _stick_pos
	var a := lerpf(0.35, 1.0, _stick_alpha) * op
	if _stick_touch == -1:
		base = Vector2(vp.x - 230.0 if left else 230.0, vp.y - 200.0)
		knob = base
	draw_circle(base, rj, Color(0.05, 0.08, 0.14, 0.28 * a))
	draw_arc(base, rj, 0, TAU, 64, Color(1, 1, 1, 0.35 * a), 3.0, true)
	draw_arc(base, rj * 0.55, 0, TAU, 48, Color(1, 1, 1, 0.08 * a), 2.0, true)
	for k in range(4):
		var ang := k * PI * 0.5
		var tip := base + Vector2(cos(ang), sin(ang)) * (rj - 14)
		var side := Vector2(-sin(ang), cos(ang)) * 7.0
		var back := base + Vector2(cos(ang), sin(ang)) * (rj - 26)
		draw_colored_polygon(PackedVector2Array([tip, back + side, back - side]), Color(1, 1, 1, 0.3 * a))
	var kr := 44.0 * float(Settings.get_value("joystick_size", 1.0))
	draw_circle(knob, kr, Color(0.85, 0.92, 1.0, 0.55 * a))
	draw_circle(knob, kr * 0.72, Color(1, 1, 1, 0.75 * a))
	draw_arc(knob, kr, 0, TAU, 48, Color(UiTheme.ACCENT, 0.9 * a), 3.0, true)

	_draw_button(Btn.JUMP, op, Color(0.25, 0.85, 1.0))
	_draw_button(Btn.BOOST, op, Color(1.0, 0.55, 0.12))
	_draw_button(Btn.DRIFT, op, Color(0.75, 0.55, 1.0))
	_draw_button(Btn.CAM, op, Color(0.4, 1.0, 0.6) if ball_cam else Color(0.7, 0.7, 0.75))
	_draw_button(Btn.PAUSE, op, Color(0.9, 0.9, 0.95))
	if show_reset:
		_draw_button(Btn.RESET, op, Color(1.0, 0.85, 0.3))


func _draw_button(b: int, op: float, col: Color) -> void:
	var c := _centers[b]
	var r := _radii[b]
	var pressed: bool = _btn_pressed[b]
	var sc := 0.93 if pressed else 1.0
	r *= sc
	var fill := Color(col.r * 0.25, col.g * 0.25, col.b * 0.3, 0.42 * op)
	if pressed:
		fill = Color(col.r, col.g, col.b, 0.55 * op)
	draw_circle(c, r, fill)
	draw_arc(c, r, 0, TAU, 64, Color(col, 0.85 * op), 3.0 if b != Btn.PAUSE else 2.0, true)
	if _btn_anim[b] > 0.0:
		var t: float = 1.0 - _btn_anim[b]
		draw_arc(c, r + t * 24.0, 0, TAU, 64, Color(col, 0.6 * _btn_anim[b] * op), 3.0, true)
	var ic := Color(1, 1, 1, 0.95 * op)
	match b:
		Btn.JUMP:
			for k in range(2):
				var y := c.y + r * (0.12 - 0.3 * k)
				var w := r * 0.42
				draw_polyline(PackedVector2Array([Vector2(c.x - w, y + w * 0.55), Vector2(c.x, y - w * 0.15),
					Vector2(c.x + w, y + w * 0.55)]), ic, 7.0 * sc, true)
		Btn.BOOST:
			# meter ring
			var frac := clampf(boost_amount / 100.0, 0.0, 1.0)
			draw_arc(c, r + 10.0, -PI * 0.5, -PI * 0.5 + TAU, 64, Color(1, 1, 1, 0.12 * op), 9.0, true)
			if frac > 0.001:
				var mc := Color(1.0, 0.6, 0.1).lerp(Color(1.0, 0.25, 0.1), 1.0 - frac)
				draw_arc(c, r + 10.0, -PI * 0.5, -PI * 0.5 + TAU * frac, 64, Color(mc, 0.95 * op), 9.0, true)
			var txt := str(int(round(boost_amount)))
			var fs := int(r * 0.62)
			var ts := _font.get_string_size(txt, HORIZONTAL_ALIGNMENT_CENTER, -1, fs)
			draw_string(_font, Vector2(c.x - ts.x * 0.5, c.y + fs * 0.42), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, ic)
			_draw_flame(Vector2(c.x, c.y - r * 0.52), r * 0.2, Color(1.0, 0.7, 0.2, 0.95 * op))
		Btn.DRIFT:
			draw_arc(c, r * 0.42, PI * 0.15, PI * 1.6, 24, ic, 5.0 * sc, true)
			var tip := c + Vector2(cos(PI * 0.15), sin(PI * 0.15)) * r * 0.42
			draw_colored_polygon(PackedVector2Array([tip + Vector2(-2, -14) * sc, tip + Vector2(12, 4) * sc,
				tip + Vector2(-12, 6) * sc]), ic)
		Btn.CAM:
			draw_arc(c, r * 0.42, 0, TAU, 24, ic, 3.5, true)
			draw_circle(c, r * 0.14, ic)
			if not ball_cam:
				draw_line(c + Vector2(-r * 0.5, r * 0.5), c + Vector2(r * 0.5, -r * 0.5), ic, 3.5, true)
		Btn.PAUSE:
			draw_rect(Rect2(c.x - r * 0.32, c.y - r * 0.38, r * 0.2, r * 0.76), ic)
			draw_rect(Rect2(c.x + r * 0.12, c.y - r * 0.38, r * 0.2, r * 0.76), ic)
		Btn.RESET:
			draw_arc(c, r * 0.42, PI * 0.2, PI * 1.8, 24, ic, 4.0, true)
			var tp := c + Vector2(cos(PI * 0.2), sin(PI * 0.2)) * r * 0.42
			draw_colored_polygon(PackedVector2Array([tp + Vector2(-8, -10), tp + Vector2(9, -3), tp + Vector2(-2, 9)]), ic)


func _draw_flame(c: Vector2, s: float, col: Color) -> void:
	var pts := PackedVector2Array()
	for i in range(13):
		var a := float(i) / 12.0 * TAU
		var rr := s * (0.75 + 0.25 * cos(a))
		var p := Vector2(sin(a) * rr * 0.8, -cos(a) * rr * (1.5 if cos(a) > 0.0 else 0.9))
		pts.append(c + p)
	draw_colored_polygon(pts, col)
