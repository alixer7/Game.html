class_name TouchControls
extends Control
## Floating joystick, action buttons and a camera-drag zone for phones, drawn from code.
## It drives the InputMap actions (move_*, jump, spin, dash), so the Player is identical for
## touch, keyboard and gamepad. Every finger keeps the role it started with.

signal pause_pressed
signal camera_drag(delta: Vector2)

const STICK_R := 104.0
const DEADZONE := 0.10
const BUTTONS := ["jump", "spin", "dash"]

var hover_ratio: float = 1.0   # hover fuel left (0..1), shown as an arc around the jump button
var dash_ratio: float = 1.0    # 1 = dash ready
var active: bool = true

var _roles: Dictionary = {}    # finger index -> role
var _stick_id: int = -1
var _stick_origin := Vector2.ZERO
var _stick_off := Vector2.ZERO
var _cam_id: int = -1
var _cam_last := Vector2.ZERO
var _pause_id: int = -1
var _down: Dictionary = {"jump": false, "spin": false, "dash": false}
var _finger: Dictionary = {"jump": -1, "spin": -1, "dash": -1}
var _glow: Dictionary = {"jump": 0.0, "spin": 0.0, "dash": 0.0}
var _mar := Vector4.ZERO


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	layout_direction = Control.LAYOUT_DIRECTION_LTR
	UIKit.fill(self)


func _ready() -> void:
	_mar = UIKit.safe_margins(get_viewport())


func set_active(v: bool) -> void:
	active = v
	visible = v
	if not v:
		release_all()


# ------------------------------------------------------------- layout
func _stick_scale() -> float:
	return clampf(float(Game.settings.get("stick_scale", 1.0)), 0.6, 1.6)


func _btn_scale() -> float:
	return clampf(float(Game.settings.get("btn_scale", 1.0)), 0.6, 1.6)


func btn_center(b: String) -> Vector2:
	var sc: float = _btn_scale()
	var j := Vector2(size.x - 70.0 - _mar.z - 100.0 * sc, size.y - 60.0 - _mar.w - 100.0 * sc)
	if b == "spin":
		return j + Vector2(-196.0, 40.0) * sc
	if b == "dash":
		return j + Vector2(-130.0, -168.0) * sc
	return j


func btn_radius(b: String) -> float:
	var sc: float = _btn_scale()
	if b == "jump":
		return 100.0 * sc
	if b == "spin":
		return 72.0 * sc
	return 66.0 * sc


func _btn_color(b: String) -> Color:
	if b == "jump":
		return UIKit.COL_CYAN
	if b == "spin":
		return UIKit.COL_PINK
	return UIKit.COL_GOLD


func _pause_center() -> Vector2:
	return Vector2(size.x - 76.0 - _mar.z, 76.0 + _mar.y)


func _rest_center() -> Vector2:
	var r: float = STICK_R * _stick_scale()
	return Vector2(90.0 + _mar.x + r * 1.3, size.y - 80.0 - _mar.w - r * 1.3)


func _in_stick_zone(pos: Vector2) -> bool:
	if bool(Game.settings.get("fixed_stick", false)):
		return pos.distance_to(_rest_center()) <= STICK_R * _stick_scale() * 1.7
	return pos.x < size.x * 0.42 and pos.y > 140.0


# -------------------------------------------------------------- input
func _input(event: InputEvent) -> void:
	if not active:
		return
	if event is InputEventScreenTouch:
		var te := event as InputEventScreenTouch
		if te.pressed:
			_on_down(te.index, te.position)
		else:
			_on_up(te.index, te.position)
	elif event is InputEventScreenDrag:
		var de := event as InputEventScreenDrag
		_on_drag(de.index, de.position)


func _on_down(idx: int, pos: Vector2) -> void:
	if _roles.has(idx):
		_on_up(idx, pos)
	var role := ""
	for b in BUTTONS:
		var bn: String = b
		if int(_finger[bn]) == -1 and pos.distance_to(btn_center(bn)) <= btn_radius(bn) * 1.2 + 6.0:
			role = bn
			break
	if role == "" and _pause_id == -1 and pos.distance_to(_pause_center()) <= 62.0:
		role = "pause"
	if role == "":
		if _stick_id == -1 and _in_stick_zone(pos):
			role = "stick"
		elif _cam_id == -1:
			role = "cam"
	if role == "":
		return
	_roles[idx] = role
	if role == "stick":
		_start_stick(idx, pos)
	elif role == "cam":
		_cam_id = idx
		_cam_last = pos
	elif role == "pause":
		_pause_id = idx
	else:
		_press(role, idx)


func _on_up(idx: int, pos: Vector2) -> void:
	if not _roles.has(idx):
		return
	var role: String = _roles[idx]
	_roles.erase(idx)
	if role == "stick":
		_stick_id = -1
		_stick_off = Vector2.ZERO
		_apply_move(Vector2.ZERO)
	elif role == "cam":
		_cam_id = -1
	elif role == "pause":
		_pause_id = -1
		if pos.distance_to(_pause_center()) <= 84.0:
			Sfx.play("ui_click")
			pause_pressed.emit()
	else:
		_release(role)


func _on_drag(idx: int, pos: Vector2) -> void:
	if not _roles.has(idx):
		return
	var role: String = _roles[idx]
	if role == "stick":
		_update_stick(pos)
	elif role == "cam":
		var d: Vector2 = pos - _cam_last
		_cam_last = pos
		camera_drag.emit(d)


func _start_stick(idx: int, pos: Vector2) -> void:
	_stick_id = idx
	var r: float = STICK_R * _stick_scale()
	if bool(Game.settings.get("fixed_stick", false)):
		_stick_origin = _rest_center()
	else:
		var min_x: float = r + 36.0 + _mar.x
		var max_x: float = maxf(size.x * 0.42, min_x)
		_stick_origin = Vector2(clampf(pos.x, min_x, max_x), clampf(pos.y, r + 36.0, size.y - r - 36.0))
	_update_stick(pos)


func _update_stick(pos: Vector2) -> void:
	var r: float = STICK_R * _stick_scale()
	var d: Vector2 = pos - _stick_origin
	var l: float = d.length()
	if l > r:
		if not bool(Game.settings.get("fixed_stick", false)):
			_stick_origin += d / l * (l - r)   # the base follows the thumb
		d = d / l * r
	_stick_off = d
	var m: float = clampf(d.length() / r, 0.0, 1.0)
	var v := Vector2.ZERO
	if m > DEADZONE:
		var k: float = (m - DEADZONE) / (1.0 - DEADZONE)
		k = clampf(pow(k, 1.25) * 1.06, 0.0, 1.0)
		v = d.normalized() * k
	_apply_move(v)


func _apply_move(v: Vector2) -> void:
	_set_act("move_left", maxf(-v.x, 0.0))
	_set_act("move_right", maxf(v.x, 0.0))
	_set_act("move_forward", maxf(-v.y, 0.0))
	_set_act("move_back", maxf(v.y, 0.0))


func _set_act(a: String, s: float) -> void:
	if s > 0.001:
		Input.action_press(a, s)
	else:
		Input.action_release(a)


func _press(b: String, idx: int) -> void:
	_finger[b] = idx
	_down[b] = true
	_glow[b] = 1.0
	Input.action_press(b)
	Game.vibrate(10)


func _release(b: String) -> void:
	_finger[b] = -1
	_down[b] = false
	Input.action_release(b)


func release_all() -> void:
	_roles.clear()
	_stick_id = -1
	_cam_id = -1
	_pause_id = -1
	_stick_off = Vector2.ZERO
	_apply_move(Vector2.ZERO)
	for b in BUTTONS:
		var bn: String = b
		_release(bn)


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT or what == NOTIFICATION_WM_WINDOW_FOCUS_OUT:
		release_all()


func _exit_tree() -> void:
	release_all()


# ------------------------------------------------------------ drawing
func _process(delta: float) -> void:
	for b in BUTTONS:
		var bn: String = b
		_glow[bn] = move_toward(float(_glow[bn]), 0.0, delta * 3.0)
	if active:
		queue_redraw()


func _draw() -> void:
	if not active:
		return
	var a: float = clampf(float(Game.settings.get("ui_opacity", 0.85)), 0.2, 1.0)
	_draw_stick(a)
	for b in BUTTONS:
		var bn: String = b
		_draw_button(bn, a)
	_draw_pause(a)


func _draw_stick(a: float) -> void:
	var r: float = STICK_R * _stick_scale()
	var on: bool = _stick_id != -1
	var c: Vector2 = _stick_origin if on else _rest_center()
	var al: float = a * (1.0 if on else 0.4)
	var col: Color = UIKit.COL_CYAN
	draw_circle(c, r * 1.25, Color(0.03, 0.07, 0.17, 0.4 * al))
	draw_arc(c, r * 1.25, 0.0, TAU, 64, Color(col.r, col.g, col.b, 0.55 * al), 3.0, true)
	draw_arc(c, r * 0.8, 0.0, TAU, 48, Color(col.r, col.g, col.b, 0.16 * al), 2.0, true)
	for i in range(8):
		var ang: float = i * TAU / 8.0
		var dir := Vector2(cos(ang), sin(ang))
		draw_line(c + dir * r * 1.34, c + dir * r * 1.44, Color(col.r, col.g, col.b, 0.5 * al), 3.0, true)
	var k: Vector2 = c + _stick_off
	var m: float = _stick_off.length() / r
	draw_circle(k, r * 0.52, Color(col.r, col.g, col.b, (0.10 + 0.14 * m) * al))
	draw_circle(k, r * 0.42, Color(0.05, 0.1, 0.24, 0.92 * al))
	draw_arc(k, r * 0.42, 0.0, TAU, 40, Color(col.r, col.g, col.b, 0.95 * al), 4.0, true)
	draw_circle(k, r * 0.15, Color(col.r, col.g, col.b, al))
	if on and m > 0.2:
		var dn: Vector2 = _stick_off.normalized()
		draw_circle(c + dn * r * 1.25, 9.0, Color(col.r, col.g, col.b, 0.9 * al))


func _draw_button(b: String, a: float) -> void:
	var c: Vector2 = btn_center(b)
	var r: float = btn_radius(b)
	var down: bool = bool(_down[b])
	var g: float = float(_glow[b])
	var col: Color = _btn_color(b)
	if down:
		r *= 0.93
	draw_circle(c, r * 1.16, Color(col.r, col.g, col.b, (0.08 + 0.2 * g + (0.1 if down else 0.0)) * a))
	draw_circle(c, r, Color(0.03, 0.07, 0.17, (0.84 if down else 0.6) * a))
	if down:
		draw_circle(c, r * 0.96, Color(col.r, col.g, col.b, 0.3 * a))
	draw_arc(c, r, 0.0, TAU, 56, Color(col.r, col.g, col.b, 0.95 * a), 5.0 if b == "jump" else 4.0, true)
	UIIcons.draw(self, b, c, r * 0.4, Color(1.0, 1.0, 1.0, 0.96 * a))
	if b == "jump" and hover_ratio < 0.995:
		draw_arc(c, r * 1.2, -PI * 0.5, -PI * 0.5 + TAU * clampf(hover_ratio, 0.0, 1.0), 40, Color(0.45, 1.0, 0.7, 0.95 * a), 6.0, true)
	if b == "dash" and dash_ratio < 0.995:
		draw_circle(c, r * 0.98, Color(0.0, 0.0, 0.0, 0.35 * a))
		draw_arc(c, r * 1.2, -PI * 0.5, -PI * 0.5 + TAU * clampf(dash_ratio, 0.0, 1.0), 40, Color(col.r, col.g, col.b, 0.95 * a), 6.0, true)


func _draw_pause(a: float) -> void:
	var c: Vector2 = _pause_center()
	var down: bool = _pause_id != -1
	draw_circle(c, 42.0, Color(0.03, 0.07, 0.17, (0.8 if down else 0.55) * a))
	draw_arc(c, 42.0, 0.0, TAU, 40, Color(1.0, 1.0, 1.0, 0.55 * a), 3.0, true)
	UIIcons.draw(self, "pause", c, 15.0, Color(1.0, 1.0, 1.0, 0.92 * a))
