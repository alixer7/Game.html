class_name TouchControls
extends Control
## Multi-touch driving controls drawn in code. Supports four steering modes
## (buttons, wheel, slider, tilt), and an edit mode to drag / resize buttons.

signal action(name: String)          # camera, reset, pause
signal selected_changed(name: String)

var steer := 0.0
var steer_digital := false
var gas := 0.0
var brake := 0.0
var handbrake := false
var nitro := false
var look_back := false
var editing := false
var selected := ""
var nitro_level := 1.0

var _touch := {}        # touch index -> control name
var _wheel_angle := 0.0
var _wheel_start := 0.0
var _wheel_touch_ang := 0.0
var _slider_origin := Vector2.ZERO
var _slider_touch := Vector2.ZERO
var _drag_offset := Vector2.ZERO


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	process_mode = Node.PROCESS_MODE_ALWAYS


func names() -> Array:
	var mode: String = Game.controls.steer_mode
	var n := ["gas", "brake", "handbrake", "nitro", "camera", "reset", "pause", "lookback"]
	match mode:
		"buttons":
			n.append_array(["left", "right"])
		"wheel":
			n.append("wheel")
		"slider":
			n.append("slider")
	return n


func base_radius() -> float:
	return size.y * 0.083 * float(Game.controls.scale)


func info(name: String) -> Array:
	var l: Array = Game.layout_of(name)
	var center := Vector2(float(l[0]) * size.x, float(l[1]) * size.y)
	var r := base_radius() * float(l[2])
	if name == "wheel":
		r *= 1.55
	elif name == "slider":
		r *= 1.0
	elif name in ["camera", "reset", "pause"]:
		r *= 0.9
	return [center, r]


func _hit(p: Vector2) -> String:
	var best := ""
	var bd := 1e9
	for n in names():
		var inf := info(n)
		var c: Vector2 = inf[0]
		var r: float = inf[1]
		var d := p.distance_to(c)
		var hit_r := r * 1.15
		if n == "slider":
			if absf(p.x - c.x) < r * 2.6 and absf(p.y - c.y) < r * 1.1:
				d = 0.0
			else:
				continue
		if d < hit_r and d < bd:
			bd = d
			best = n
	return best


func _input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventScreenTouch:
		var e := event as InputEventScreenTouch
		if e.pressed:
			var n := _hit(e.position)
			if n == "":
				return
			_touch[e.index] = n
			if editing:
				selected = n
				selected_changed.emit(n)
				_drag_offset = info(n)[0] - e.position
			else:
				_press(n, e.position)
			get_viewport().set_input_as_handled()
			queue_redraw()
		else:
			if _touch.has(e.index):
				var n: String = _touch[e.index]
				_touch.erase(e.index)
				if not editing:
					_release(n)
				queue_redraw()
	elif event is InputEventScreenDrag:
		var e := event as InputEventScreenDrag
		if not _touch.has(e.index):
			return
		var n: String = _touch[e.index]
		if editing:
			var p := e.position + _drag_offset
			var l: Array = Game.layout_of(n).duplicate()
			l[0] = clampf(p.x / size.x, 0.03, 0.97)
			l[1] = clampf(p.y / size.y, 0.05, 0.96)
			Game.controls.layout[n] = l
			queue_redraw()
		else:
			_drag(n, e.position)
		get_viewport().set_input_as_handled()


func _press(n: String, p: Vector2) -> void:
	match n:
		"gas":
			gas = 1.0
		"brake":
			brake = 1.0
		"handbrake":
			handbrake = true
		"nitro":
			nitro = true
		"left":
			steer = -1.0
			steer_digital = true
		"right":
			steer = 1.0
			steer_digital = true
		"lookback":
			look_back = true
		"wheel":
			var c: Vector2 = info("wheel")[0]
			_wheel_touch_ang = (p - c).angle()
			_wheel_start = _wheel_angle
		"slider":
			_slider_origin = p
			_slider_touch = p
		"camera", "reset", "pause":
			action.emit(n)
	Game.vibrate(8)


func _release(n: String) -> void:
	match n:
		"gas":
			gas = 0.0
		"brake":
			brake = 0.0
		"handbrake":
			handbrake = false
		"nitro":
			nitro = false
		"left", "right":
			# keep the other direction if still held
			steer = 0.0
			for k in _touch:
				if _touch[k] == "left":
					steer = -1.0
				elif _touch[k] == "right":
					steer = 1.0
			steer_digital = steer != 0.0
		"lookback":
			look_back = false
		"wheel":
			_wheel_angle = 0.0
			steer = 0.0
		"slider":
			steer = 0.0


func _drag(n: String, p: Vector2) -> void:
	if n == "wheel":
		var c: Vector2 = info("wheel")[0]
		var a := (p - c).angle()
		var da := wrapf(a - _wheel_touch_ang, -PI, PI)
		_wheel_angle = clampf(_wheel_start + da, -deg_to_rad(120.0), deg_to_rad(120.0))
		steer = _wheel_angle / deg_to_rad(120.0)
		steer_digital = false
	elif n == "slider":
		var r: float = info("slider")[1]
		var dx := p.x - _slider_origin.x
		steer = clampf(dx / (r * 1.6), -1.0, 1.0)
		steer_digital = false


func _process(_d: float) -> void:
	if Game.controls.steer_mode == "tilt" and not editing and visible:
		var acc := Input.get_accelerometer()
		var orient := DisplayServer.screen_get_orientation()
		var v := acc.y
		if orient == DisplayServer.SCREEN_REVERSE_LANDSCAPE:
			v = -v
		elif orient == DisplayServer.SCREEN_PORTRAIT:
			v = acc.x
		steer = clampf(v / 5.5 * float(Game.controls.tilt_sensitivity), -1.0, 1.0)
		steer = sign(steer) * pow(absf(steer), 1.3)
		steer_digital = false
	if Game.player:
		nitro_level = Game.player.nitro
	queue_redraw()


func release_all() -> void:
	_touch.clear()
	gas = 0.0
	brake = 0.0
	handbrake = false
	nitro = false
	steer = 0.0
	look_back = false


# --------------------------------------------------------------------------- drawing
func _pressed(n: String) -> bool:
	return _touch.values().has(n)


func _draw() -> void:
	if size.y < 50.0:
		return
	var op: float = Game.controls.opacity
	for n in names():
		var inf := info(n)
		var c: Vector2 = inf[0]
		var r: float = inf[1]
		var pressed := _pressed(n)
		var accent := UITheme.ACCENT
		if n == "nitro":
			accent = Color(0.3, 0.6, 1.0)
		elif n == "brake" or n == "handbrake":
			accent = Color(1.0, 0.3, 0.25)
		elif n == "gas":
			accent = Color(0.35, 0.9, 0.45)
		var fill := Color(0.04, 0.05, 0.07, 0.42 * op)
		if pressed:
			fill = Color(accent.r, accent.g, accent.b, 0.45 * op)
		var line := Color(1, 1, 1, 0.55 * op)
		if editing and selected == n:
			line = UITheme.ACCENT
		if n == "slider":
			var rect := Rect2(c - Vector2(r * 2.6, r * 0.7), Vector2(r * 5.2, r * 1.4))
			draw_rect(rect, fill, true)
			draw_rect(rect, line, false, 2.0)
			var knob := c + Vector2(steer * r * 1.6, 0) if not editing else c
			draw_circle(knob, r * 0.55, Color(1, 1, 1, 0.35 * op))
			_icon_arrow(c - Vector2(r * 2.0, 0), r * 0.35, PI, line)
			_icon_arrow(c + Vector2(r * 2.0, 0), r * 0.35, 0.0, line)
			continue
		draw_circle(c, r, fill)
		draw_arc(c, r, 0, TAU, 48, line, 2.5, true)
		var ic := Color(1, 1, 1, 0.9 * op)
		match n:
			"gas":
				_pedal(c, r, ic, true)
			"brake":
				_pedal(c, r, ic, false)
			"handbrake":
				draw_string(UITheme.font(800), c + Vector2(-r * 0.32, r * 0.25), "H", HORIZONTAL_ALIGNMENT_CENTER, r * 0.64, int(r * 0.75), ic)
			"nitro":
				draw_arc(c, r * 0.82, -PI * 0.5, -PI * 0.5 + TAU * nitro_level, 40, Color(0.35, 0.65, 1.0, 0.95 * op), r * 0.12, true)
				draw_string(UITheme.font(800), c + Vector2(-r * 0.6, r * 0.2), "N₂O", HORIZONTAL_ALIGNMENT_CENTER, r * 1.2, int(r * 0.5), ic)
			"left":
				_icon_arrow(c, r * 0.45, PI, ic)
			"right":
				_icon_arrow(c, r * 0.45, 0.0, ic)
			"camera":
				draw_rect(Rect2(c - Vector2(r * 0.45, r * 0.3), Vector2(r * 0.7, r * 0.6)), ic, false, 2.5)
				draw_colored_polygon(PackedVector2Array([c + Vector2(r * 0.28, -r * 0.18), c + Vector2(r * 0.55, -r * 0.35), c + Vector2(r * 0.55, r * 0.35), c + Vector2(r * 0.28, r * 0.18)]), ic)
			"reset":
				draw_arc(c, r * 0.42, PI * 0.2, PI * 1.8, 24, ic, 3.0, true)
				_icon_arrow(c + Vector2(r * 0.34, -r * 0.27), r * 0.18, -PI * 0.35, ic)
			"pause":
				draw_rect(Rect2(c + Vector2(-r * 0.28, -r * 0.35), Vector2(r * 0.18, r * 0.7)), ic)
				draw_rect(Rect2(c + Vector2(r * 0.1, -r * 0.35), Vector2(r * 0.18, r * 0.7)), ic)
			"lookback":
				draw_arc(c, r * 0.35, PI * 1.1, PI * 1.9, 16, ic, 3.0, true)
				draw_arc(c, r * 0.35, PI * 0.1, PI * 0.9, 16, ic, 3.0, true)
				draw_circle(c, r * 0.12, ic)
			"wheel":
				_steering_wheel(c, r, ic)
		if editing:
			var l: Array = Game.layout_of(n)
			draw_string(UITheme.font(600), c + Vector2(-r, r + 22), "%d%%" % int(float(l[2]) * 100.0), HORIZONTAL_ALIGNMENT_CENTER, r * 2.0, 16, UITheme.DIM)


func _icon_arrow(c: Vector2, s: float, ang: float, col: Color) -> void:
	var pts := PackedVector2Array([Vector2(s, 0), Vector2(-s * 0.6, -s * 0.85), Vector2(-s * 0.6, s * 0.85)])
	for i in 3:
		pts[i] = c + pts[i].rotated(ang)
	draw_colored_polygon(pts, col)


func _pedal(c: Vector2, r: float, col: Color, gas_pedal: bool) -> void:
	var w := r * (0.55 if gas_pedal else 0.75)
	var h := r * (0.95 if gas_pedal else 0.6)
	var rect := Rect2(c - Vector2(w, h) * 0.5, Vector2(w, h))
	draw_rect(rect, col, false, 3.0)
	for i in 3:
		var y := rect.position.y + h * (0.25 + i * 0.25)
		draw_line(Vector2(rect.position.x + 5, y), Vector2(rect.end.x - 5, y), col, 2.0)


func _steering_wheel(c: Vector2, r: float, col: Color) -> void:
	var a := _wheel_angle if not editing else 0.0
	draw_arc(c, r * 0.8, 0, TAU, 48, col, r * 0.12, true)
	for k in 3:
		var ang := a + PI * 0.5 + k * TAU / 3.0
		draw_line(c, c + Vector2(cos(ang), sin(ang)) * r * 0.78, col, r * 0.09)
	draw_circle(c, r * 0.18, col)
	draw_circle(c + Vector2(cos(a - PI * 0.5), sin(a - PI * 0.5)) * r * 0.8, r * 0.08, UITheme.ACCENT)
