class_name TouchControls
extends Control
## Multi-touch game controls: analog stick (floating or fixed) and action
## buttons (jump, boost with animated meter, brake/reverse, drift/air-roll,
## ball-cam, pause). Every element can be repositioned, resized and faded via
## the layout editor (edit_mode), and is always kept fully on screen.

signal pause_pressed
signal ballcam_toggled
signal reset_pressed
signal selection_changed(element: String)

const ELEMENTS := ["stick", "jump", "boost", "brake", "drift", "cam", "pause", "reset"]
## Default placement: [anchor (0/1 per axis), offset from anchor, base radius]
const DEFAULTS := {
	"stick": [Vector2(0, 1), Vector2(235, -205), 92.0],
	"jump": [Vector2(1, 1), Vector2(-150, -150), 80.0],
	"boost": [Vector2(1, 1), Vector2(-338, -100), 64.0],
	"brake": [Vector2(1, 1), Vector2(-490, -78), 46.0],
	"drift": [Vector2(1, 1), Vector2(-122, -338), 52.0],
	"cam": [Vector2(1, 1), Vector2(-304, -292), 40.0],
	"pause": [Vector2(0, 0), Vector2(58, 52), 30.0],
	"reset": [Vector2(1, 0), Vector2(-62, 52), 34.0],
}
const COLORS := {
	"jump": Color(0.25, 0.85, 1.0), "boost": Color(1.0, 0.55, 0.12), "brake": Color(1.0, 0.32, 0.3),
	"drift": Color(0.75, 0.55, 1.0), "cam": Color(0.4, 1.0, 0.6), "pause": Color(0.9, 0.9, 0.95),
	"reset": Color(1.0, 0.85, 0.3), "stick": Color(0.25, 0.85, 1.0),
}

var stick := Vector2.ZERO          # x right, y up
var jump_held := false
var boost_held := false
var drift_held := false
var brake_held := false
var boost_amount := 33.0
var ball_cam := true
var show_reset := false
var enabled := true
var edit_mode := false
var selected := ""

var _centers := {}
var _radii := {}
var _opacity := {}
var _layout_data := {}
var _stick_touch := -1
var _stick_base := Vector2.ZERO
var _stick_pos := Vector2.ZERO
var _stick_alpha := 0.0
var _btn_touch := {}        # touch index -> element name
var _pressed := {}
var _anim := {}
var _font: Font
var _boost_disp := 33.0
var _boost_flash := 0.0
var _pickup_txt := ""
var _pickup_t := 0.0
var _dragging := false
var _drag_off := Vector2.ZERO


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP if edit_mode else Control.MOUSE_FILTER_IGNORE
	_font = UiTheme.font_black()
	for e in ELEMENTS:
		_pressed[e] = false
		_anim[e] = 0.0
	_layout_data = (Settings.get_value("touch_layout", {}) as Dictionary).duplicate(true)
	if not edit_mode:
		add_to_group("touch_hud")
	resized.connect(_layout)
	Settings.changed.connect(_on_settings_changed)
	_layout()


func _on_settings_changed() -> void:
	if not edit_mode:
		_layout_data = (Settings.get_value("touch_layout", {}) as Dictionary).duplicate(true)
	_layout()


# ------------------------------------------------------------------ layout

func safe_rect() -> Rect2:
	var vp := get_viewport_rect().size
	var win := Vector2(DisplayServer.window_get_size())
	var safe := Rect2(DisplayServer.get_display_safe_area())
	var r := Rect2(Vector2.ZERO, vp)
	if win.x > 0 and safe.size.x > 0 and OS.has_feature("mobile"):
		var sc := vp / win
		r = Rect2(safe.position * sc, safe.size * sc).intersection(Rect2(Vector2.ZERO, vp))
		if r.size.x < vp.x * 0.5:
			r = Rect2(Vector2.ZERO, vp)
	# small comfort margin so rounded screen corners never clip a control
	return r.grow(-10.0)


func _global_scale(e: String) -> float:
	if e == "stick":
		return float(Settings.get_value("joystick_size", 1.0))
	if e == "pause" or e == "reset":
		return 1.0
	return float(Settings.get_value("button_size", 1.0))


func _extra(e: String) -> float:
	# space needed around the element's radius (meter ring, knob, glow)
	match e:
		"boost":
			return 18.0
		"stick":
			return 6.0
	return 8.0


func default_center(e: String, r: Rect2) -> Vector2:
	var d: Array = DEFAULTS[e]
	var anchor: Vector2 = d[0]
	var off: Vector2 = d[1]
	var gs := _global_scale(e)
	off *= lerpf(1.0, gs, 0.8)
	if Settings.get_value("left_handed", false):
		anchor.x = 1.0 - anchor.x
		off.x = -off.x
	return r.position + r.size * anchor + off


func _layout() -> void:
	var r := safe_rect()
	for e in ELEMENTS:
		var base_r: float = DEFAULTS[e][2]
		var c := default_center(e, r)
		var s := 1.0
		var o := 1.0
		if _layout_data.has(e):
			var v: Array = _layout_data[e]
			c = r.position + Vector2(float(v[0]), float(v[1])) * r.size
			s = float(v[2])
			o = float(v[3])
		var rad := base_r * s * _global_scale(e)
		_radii[e] = rad
		_opacity[e] = o
		_centers[e] = _clamp_center(e, c, rad, r)
	queue_redraw()


func _clamp_center(e: String, c: Vector2, rad: float, r: Rect2) -> Vector2:
	var m := rad + _extra(e)
	var lo := r.position + Vector2(m, m)
	var hi := r.position + r.size - Vector2(m, m)
	if hi.x < lo.x:
		hi.x = lo.x
	if hi.y < lo.y:
		hi.y = lo.y
	return Vector2(clampf(c.x, lo.x, hi.x), clampf(c.y, lo.y, hi.y))


func element_center(e: String) -> Vector2:
	return _centers.get(e, Vector2.ZERO)


func element_scale(e: String) -> float:
	if _layout_data.has(e):
		return float(_layout_data[e][2])
	return 1.0


func element_opacity(e: String) -> float:
	if _layout_data.has(e):
		return float(_layout_data[e][3])
	return 1.0


## Edit-mode helpers used by the layout editor.
func set_element(e: String, center: Vector2, scale_v: float, opacity_v: float) -> void:
	var r := safe_rect()
	var rel := (center - r.position) / r.size
	_layout_data[e] = [clampf(rel.x, 0.0, 1.0), clampf(rel.y, 0.0, 1.0), scale_v, opacity_v]
	_layout()


func layout_data() -> Dictionary:
	return _layout_data.duplicate(true)


func reset_layout() -> void:
	_layout_data.clear()
	_layout()


func reset_state() -> void:
	_stick_touch = -1
	stick = Vector2.ZERO
	_btn_touch.clear()
	for e in ELEMENTS:
		_pressed[e] = false
	jump_held = false
	boost_held = false
	drift_held = false
	brake_held = false


# ------------------------------------------------------------------ boost feedback

func notify_pickup(big: bool, gained: float) -> void:
	_boost_flash = 1.0 if big else 0.7
	_pickup_txt = "+%d" % int(round(gained))
	_pickup_t = 1.0
	_anim["boost"] = 1.0


# ------------------------------------------------------------------ input

func _visible_buttons() -> Array:
	var out := ["jump", "boost", "brake", "drift", "cam", "pause"]
	if show_reset or edit_mode:
		out.append("reset")
	return out


func _hit_button(p: Vector2) -> String:
	var best := ""
	var best_d := 1e9
	for e in _visible_buttons():
		var d := p.distance_to(_centers[e])
		var reach: float = _radii[e] * (1.25 if e != "pause" else 1.6)
		if d < reach and d / reach < best_d:
			best_d = d / reach
			best = e
	return best


func _fixed_stick() -> bool:
	return bool(Settings.get_value("joystick_fixed", false))


func _stick_zone(p: Vector2) -> bool:
	var vp := get_viewport_rect().size
	var sc: Vector2 = _centers["stick"]
	if _fixed_stick():
		return p.distance_to(sc) < _radii["stick"] * 2.6
	if p.y < vp.y * 0.16:
		return false
	return p.x < vp.x * 0.47 if sc.x < vp.x * 0.5 else p.x > vp.x * 0.53


func _input(event: InputEvent) -> void:
	if edit_mode or not enabled or not is_visible_in_tree():
		return
	if event is InputEventScreenTouch:
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
	if b != "":
		_btn_touch[idx] = b
		_pressed[b] = true
		_anim[b] = 1.0
		match b:
			"jump":
				jump_held = true
				Settings.vibrate(12, 0.35)
			"boost":
				boost_held = true
				Settings.vibrate(8, 0.25)
			"brake":
				brake_held = true
			"drift":
				drift_held = true
			"cam":
				ball_cam = not ball_cam
				ballcam_toggled.emit()
				Sfx.play("click", -8.0)
			"pause":
				pause_pressed.emit()
			"reset":
				reset_pressed.emit()
		get_viewport().set_input_as_handled()
		queue_redraw()
		return
	if _stick_touch == -1 and _stick_zone(p):
		_stick_touch = idx
		var rj: float = _radii["stick"]
		if _fixed_stick():
			_stick_base = _centers["stick"]
		else:
			var vp := get_viewport_rect().size
			_stick_base = Vector2(clampf(p.x, rj + 16, vp.x - rj - 16), clampf(p.y, rj + 16, vp.y - rj - 16))
		_move_stick(p)
		get_viewport().set_input_as_handled()


func _on_release(idx: int) -> void:
	if idx == _stick_touch:
		_stick_touch = -1
		stick = Vector2.ZERO
	if _btn_touch.has(idx):
		var b: String = _btn_touch[idx]
		_btn_touch.erase(idx)
		if not (b in _btn_touch.values()):
			_pressed[b] = false
			match b:
				"jump":
					jump_held = false
				"boost":
					boost_held = false
				"brake":
					brake_held = false
				"drift":
					drift_held = false
	queue_redraw()


func _move_stick(p: Vector2) -> void:
	var rj: float = _radii["stick"]
	var off := p - _stick_base
	if off.length() > rj:
		if _fixed_stick():
			off = off.normalized() * rj
		else:
			# floating stick: drag the base along with the thumb
			_stick_base = p - off.normalized() * rj
			off = p - _stick_base
	_stick_pos = _stick_base + off
	var v := off / rj
	v.y = -v.y
	var m := v.length()
	var dead := 0.08
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


## Layout editor: drag elements with a single pointer (mouse or emulated touch).
func _gui_input(event: InputEvent) -> void:
	if not edit_mode:
		return
	if event is InputEventMouseButton and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		var mb := event as InputEventMouseButton
		if mb.pressed:
			var hit := ""
			var best := 1e9
			for e in ELEMENTS:
				var d := mb.position.distance_to(_centers[e])
				var reach: float = maxf(_radii[e] * 1.2, 44.0)
				if d < reach and d < best:
					best = d
					hit = e
			if hit != "":
				selected = hit
				_dragging = true
				_drag_off = _centers[hit] - mb.position
				selection_changed.emit(hit)
		else:
			_dragging = false
		queue_redraw()
		accept_event()
	elif event is InputEventMouseMotion and _dragging and selected != "":
		var mm := event as InputEventMouseMotion
		set_element(selected, mm.position + _drag_off, element_scale(selected), element_opacity(selected))
		accept_event()


func _process(delta: float) -> void:
	var target := 1.0 if _stick_touch != -1 else 0.0
	_stick_alpha = move_toward(_stick_alpha, target, delta * 8.0)
	for e in ELEMENTS:
		_anim[e] = move_toward(_anim[e], 0.0, delta * 4.0)
	# animated boost meter: fills smoothly, drains quickly
	if boost_amount > _boost_disp:
		_boost_disp = move_toward(_boost_disp, boost_amount, delta * 170.0)
	else:
		_boost_disp = move_toward(_boost_disp, boost_amount, delta * 400.0)
	_boost_flash = move_toward(_boost_flash, 0.0, delta * 1.6)
	_pickup_t = move_toward(_pickup_t, 0.0, delta * 1.1)
	if edit_mode:
		mouse_filter = Control.MOUSE_FILTER_STOP
	queue_redraw()


# ------------------------------------------------------------------ drawing

func _alpha(e: String) -> float:
	return float(Settings.get_value("controls_opacity", 0.85)) * float(_opacity.get(e, 1.0))


func _draw() -> void:
	if not enabled and not edit_mode:
		return
	_draw_stick()
	for e in ["jump", "boost", "brake", "drift", "cam", "pause"]:
		_draw_button(e)
	if show_reset or edit_mode:
		_draw_button("reset")
	if edit_mode:
		for e in ELEMENTS:
			var c: Vector2 = _centers[e]
			var r: float = _radii[e]
			var col := UiTheme.ACCENT if e == selected else Color(1, 1, 1, 0.5)
			var segs := 28
			for k in range(segs):
				if k % 2 == 0:
					var a0 := TAU * k / segs
					draw_arc(c, r + _extra(e) + 6.0, a0, a0 + TAU / segs, 4, col, 2.5, true)


func _draw_stick() -> void:
	var a := lerpf(0.35, 1.0, _stick_alpha) * _alpha("stick")
	if edit_mode:
		a = _alpha("stick")
	var rj: float = _radii["stick"]
	var base := _stick_base
	var knob := _stick_pos
	if _stick_touch == -1 or edit_mode:
		base = _centers["stick"]
		knob = base
	draw_circle(base, rj, Color(0.05, 0.08, 0.14, 0.28 * a))
	draw_arc(base, rj, 0, TAU, 64, Color(1, 1, 1, 0.35 * a), 3.0, true)
	draw_arc(base, rj * 0.55, 0, TAU, 48, Color(1, 1, 1, 0.08 * a), 2.0, true)
	if _fixed_stick() and not edit_mode:
		draw_arc(base, rj * 2.6, 0, TAU, 64, Color(1, 1, 1, 0.05 * a), 2.0, true)
	for k in range(3):
		# arrows: up = accelerate, left/right = steer (down has no driving function)
		var ang: float = [-PI * 0.5, 0.0, PI][k]
		var tip := base + Vector2(cos(ang), sin(ang)) * (rj - 14)
		var side := Vector2(-sin(ang), cos(ang)) * 7.0
		var back := base + Vector2(cos(ang), sin(ang)) * (rj - 26)
		draw_colored_polygon(PackedVector2Array([tip, back + side, back - side]), Color(1, 1, 1, 0.3 * a))
	var kr := rj * 0.48
	draw_circle(knob, kr, Color(0.85, 0.92, 1.0, 0.55 * a))
	draw_circle(knob, kr * 0.72, Color(1, 1, 1, 0.75 * a))
	draw_arc(knob, kr, 0, TAU, 48, Color(UiTheme.ACCENT, 0.9 * a), 3.0, true)


func _draw_button(e: String) -> void:
	var c: Vector2 = _centers[e]
	var r: float = _radii[e]
	var op := _alpha(e)
	var col: Color = COLORS[e]
	if e == "cam" and not ball_cam:
		col = Color(0.7, 0.7, 0.75)
	var pressed: bool = _pressed[e]
	var sc := 0.93 if pressed else 1.0
	if e == "boost":
		sc *= 1.0 + 0.08 * _boost_flash
	r *= sc
	var fill := Color(col.r * 0.25, col.g * 0.25, col.b * 0.3, 0.42 * op)
	if pressed:
		fill = Color(col.r, col.g, col.b, 0.55 * op)
	draw_circle(c, r, fill)
	draw_arc(c, r, 0, TAU, 64, Color(col, 0.85 * op), 3.0 if e != "pause" else 2.0, true)
	if _anim[e] > 0.0 and not edit_mode:
		var t: float = 1.0 - _anim[e]
		draw_arc(c, r + t * 22.0, 0, TAU, 64, Color(col, 0.6 * _anim[e] * op), 3.0, true)
	var ic := Color(1, 1, 1, 0.95 * op)
	match e:
		"jump":
			for k in range(2):
				var y := c.y + r * (0.12 - 0.3 * k)
				var w := r * 0.42
				draw_polyline(PackedVector2Array([Vector2(c.x - w, y + w * 0.55), Vector2(c.x, y - w * 0.15),
					Vector2(c.x + w, y + w * 0.55)]), ic, 7.0 * sc, true)
		"boost":
			_draw_boost_meter(c, r, op, ic)
		"brake":
			# reverse / brake: downward chevron over a bar
			var w2 := r * 0.38
			draw_polyline(PackedVector2Array([Vector2(c.x - w2, c.y - w2 * 0.45), Vector2(c.x, c.y + w2 * 0.35),
				Vector2(c.x + w2, c.y - w2 * 0.45)]), ic, 6.0 * sc, true)
			draw_line(Vector2(c.x - w2, c.y + w2 * 0.85), Vector2(c.x + w2, c.y + w2 * 0.85), ic, 5.0 * sc, true)
		"drift":
			draw_arc(c, r * 0.42, PI * 0.15, PI * 1.6, 24, ic, 5.0 * sc, true)
			var tip := c + Vector2(cos(PI * 0.15), sin(PI * 0.15)) * r * 0.42
			draw_colored_polygon(PackedVector2Array([tip + Vector2(-2, -14) * sc, tip + Vector2(12, 4) * sc,
				tip + Vector2(-12, 6) * sc]), ic)
		"cam":
			draw_arc(c, r * 0.42, 0, TAU, 24, ic, 3.5, true)
			draw_circle(c, r * 0.14, ic)
			if not ball_cam:
				draw_line(c + Vector2(-r * 0.5, r * 0.5), c + Vector2(r * 0.5, -r * 0.5), ic, 3.5, true)
		"pause":
			draw_rect(Rect2(c.x - r * 0.32, c.y - r * 0.38, r * 0.2, r * 0.76), ic)
			draw_rect(Rect2(c.x + r * 0.12, c.y - r * 0.38, r * 0.2, r * 0.76), ic)
		"reset":
			draw_arc(c, r * 0.42, PI * 0.2, PI * 1.8, 24, ic, 4.0, true)
			var tp := c + Vector2(cos(PI * 0.2), sin(PI * 0.2)) * r * 0.42
			draw_colored_polygon(PackedVector2Array([tp + Vector2(-8, -10), tp + Vector2(9, -3), tp + Vector2(-2, 9)]), ic)


func _draw_boost_meter(c: Vector2, r: float, op: float, ic: Color) -> void:
	var frac := clampf(_boost_disp / 100.0, 0.0, 1.0)
	var ring_r := r + 10.0
	draw_arc(c, ring_r, -PI * 0.5, -PI * 0.5 + TAU, 64, Color(1, 1, 1, 0.12 * op), 9.0, true)
	if frac > 0.001:
		var mc := Color(1.0, 0.6, 0.1).lerp(Color(1.0, 0.25, 0.1), 1.0 - frac)
		mc = mc.lerp(Color(1.0, 0.95, 0.6), _boost_flash * 0.7)
		draw_arc(c, ring_r, -PI * 0.5, -PI * 0.5 + TAU * frac, 64, Color(mc, 0.95 * op), 9.0 + 5.0 * _boost_flash, true)
	if _boost_flash > 0.0:
		draw_arc(c, ring_r + 8.0 + (1.0 - _boost_flash) * 14.0, 0, TAU, 64,
			Color(1.0, 0.75, 0.3, 0.7 * _boost_flash * op), 4.0, true)
	var txt := str(int(round(_boost_disp)))
	var fs := int(r * 0.62)
	var ts := _font.get_string_size(txt, HORIZONTAL_ALIGNMENT_CENTER, -1, fs)
	draw_string(_font, Vector2(c.x - ts.x * 0.5, c.y + fs * 0.42), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, ic)
	_draw_flame(Vector2(c.x, c.y - r * 0.52), r * 0.2, Color(1.0, 0.7, 0.2, 0.95 * op))
	if _pickup_t > 0.0 and _pickup_txt != "":
		var pfs := 30
		var pts := _font.get_string_size(_pickup_txt, HORIZONTAL_ALIGNMENT_CENTER, -1, pfs)
		var rise := (1.0 - _pickup_t) * 40.0
		var pc := Color(1.0, 0.85, 0.35, clampf(_pickup_t * 1.6, 0.0, 1.0))
		var pos := Vector2(c.x - pts.x * 0.5, c.y - r - 30.0 - rise)
		draw_string_outline(_font, pos, _pickup_txt, HORIZONTAL_ALIGNMENT_LEFT, -1, pfs, 6, Color(0, 0, 0, pc.a * 0.7))
		draw_string(_font, pos, _pickup_txt, HORIZONTAL_ALIGNMENT_LEFT, -1, pfs, pc)


func _draw_flame(c: Vector2, s: float, col: Color) -> void:
	var pts := PackedVector2Array()
	for i in range(13):
		var a := float(i) / 12.0 * TAU
		var rr := s * (0.75 + 0.25 * cos(a))
		var p := Vector2(sin(a) * rr * 0.8, -cos(a) * rr * (1.5 if cos(a) > 0.0 else 0.9))
		pts.append(c + p)
	draw_colored_polygon(pts, col)
