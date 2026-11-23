class_name TouchControls
extends Control
## Multi-touch racing controls.
##  * Left: floating analog stick (steer; pull back while sliding = hook turn / brake).
##  * Right: DRIFT (hold) - re-tapping it within a short window while sliding
##    triggers a spark BOOST, so one thumb can drift and boost. A separate BOOST
##    button exists for claw-grip players. ITEM, BRAKE, optional ACCEL, LOOK BACK.
##  * Layout, size and opacity are user-configurable (edit mode drags buttons).

signal pause_requested()

const RETAP_WINDOW := 0.16

const DEFAULT := {
	"drift": [0.885, 0.70, 1.25],
	"boost": [0.745, 0.83, 0.85],
	"item": [0.80, 0.47, 0.8],
	"brake": [0.94, 0.42, 0.65],
	"accel": [0.95, 0.92, 0.75],
	"look": [0.68, 0.62, 0.55],
	"stick": [0.14, 0.70, 1.2],
}

var edit_mode := false
var _touches := {}        # index -> {"btn": id, "start": Vector2, "pos": Vector2}
var _stick_center := Vector2.ZERO
var _stick_pos := Vector2.ZERO
var _stick_touch := -1
var _drift_release_t := -1.0
var _drift_down := false
var _t := 0.0
var _dragging := ""
var _pressed := {}


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	Game.touch.active = DisplayServer.is_touchscreen_available() or OS.has_feature("mobile")
	visible = Game.touch.active or edit_mode


func _layout(id: String) -> Array:
	var lay: Dictionary = Game.settings.get("touch_layout", {})
	if lay.has(id):
		return lay[id]
	return DEFAULT[id]


func _btn_center(id: String) -> Vector2:
	var l := _layout(id)
	var r := get_rect().size
	return Vector2(float(l[0]) * r.x, float(l[1]) * r.y)


func _btn_radius(id: String) -> float:
	var l := _layout(id)
	return get_rect().size.y * 0.075 * float(l[2]) * float(Game.settings["touch_scale"])


func _buttons() -> Array:
	var b := ["drift", "boost", "item", "brake", "look"]
	if not Game.settings["auto_accel"]:
		b.append("accel")
	return b


func _hit(p: Vector2) -> String:
	var best := ""
	var best_d := INF
	for id in _buttons():
		var d := p.distance_to(_btn_center(id))
		if d < _btn_radius(id) * 1.25 and d < best_d:
			best_d = d
			best = id
	return best


func _input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventScreenTouch:
		var e := event as InputEventScreenTouch
		if e.pressed:
			Game.touch.active = true
			_on_down(e.index, e.position)
		else:
			_on_up(e.index, e.position)
	elif event is InputEventScreenDrag:
		var d := event as InputEventScreenDrag
		_on_move(d.index, d.position)


func _on_down(i: int, p: Vector2) -> void:
	var r := get_rect().size
	if p.y < r.y * 0.12 and absf(p.x - r.x * 0.5) < r.x * 0.08:
		pause_requested.emit()
		return
	if edit_mode:
		var hit := _hit(p)
		if hit == "" and p.distance_to(_btn_center("stick")) < _btn_radius("stick") * 1.3:
			hit = "stick"
		_dragging = hit
		_touches[i] = {"btn": "edit", "pos": p}
		return
	var b := _hit(p)
	if b != "":
		_touches[i] = {"btn": b, "pos": p}
		_press(b, true)
	elif p.x < r.x * 0.48:
		_stick_touch = i
		_stick_center = p
		_stick_pos = p
		_touches[i] = {"btn": "stick", "pos": p}
	queue_redraw()


func _on_up(i: int, _p: Vector2) -> void:
	if not _touches.has(i):
		return
	var b: String = _touches[i].btn
	_touches.erase(i)
	if b == "edit":
		_dragging = ""
		Game.save_settings()
		return
	if b == "stick":
		_stick_touch = -1
		Game.touch.steer = 0.0
		Game.touch.stick_y = 0.0
	else:
		_press(b, false)
	queue_redraw()


func _on_move(i: int, p: Vector2) -> void:
	if not _touches.has(i):
		return
	var b: String = _touches[i].btn
	if b == "edit" and _dragging != "":
		var r := get_rect().size
		var lay: Dictionary = Game.settings.get("touch_layout", {}).duplicate(true)
		var cur := _layout(_dragging).duplicate()
		cur[0] = clampf(p.x / r.x, 0.03, 0.97)
		cur[1] = clampf(p.y / r.y, 0.15, 0.97)
		lay[_dragging] = cur
		Game.settings["touch_layout"] = lay
		queue_redraw()
		return
	if b == "stick":
		_stick_pos = p
		var R := _btn_radius("stick")
		var v := (_stick_pos - _stick_center) / R
		if v.length() > 1.0:
			# drag the floating base along so the thumb never "falls off" the stick
			_stick_center = _stick_pos - v.normalized() * R
			v = v.normalized()
		var dead := 0.08
		var sx := 0.0 if absf(v.x) < dead else signf(v.x) * (absf(v.x) - dead) / (1.0 - dead)
		Game.touch.steer = clampf(sx, -1.0, 1.0)
		Game.touch.stick_y = clampf(-v.y, -1.0, 1.0)
		queue_redraw()
	elif b != "drift" and b != "stick":
		# sliding a thumb between buttons (e.g. drift <-> boost) is allowed
		var nb := _hit(p)
		if nb != "" and nb != b:
			_press(b, false)
			_press(nb, true)
			_touches[i].btn = nb


func _press(b: String, down: bool) -> void:
	_pressed[b] = down
	match b:
		"drift":
			if down:
				if _drift_release_t >= 0.0 and _t - _drift_release_t < RETAP_WINDOW:
					Game.touch.boost_pressed = true
				_drift_down = true
				Game.touch.drift = true
				_drift_release_t = -1.0
			else:
				_drift_down = false
				_drift_release_t = _t
		"boost":
			if down:
				Game.touch.boost_pressed = true
		"item":
			if down:
				Game.touch.item_pressed = true
		"brake":
			Game.touch.brake = down
		"accel":
			Game.touch.accel = down
		"look":
			Game.touch.look_back = down
	queue_redraw()


func _process(dt: float) -> void:
	_t += dt
	# drift stays held through the re-tap window so a boost tap doesn't end the slide
	if not _drift_down and _drift_release_t >= 0.0 and _t - _drift_release_t >= RETAP_WINDOW:
		Game.touch.drift = false
		_drift_release_t = -1.0


func _draw() -> void:
	var op: float = Game.settings["touch_opacity"]
	var labels := {"drift": "DRIFT", "boost": "BOOST", "item": "ITEM", "brake": "BRAKE", "accel": "GO", "look": "BACK"}
	var cols := {"drift": UIKit.ORANGE, "boost": UIKit.TEAL, "item": Color(0.95, 0.85, 0.3), "brake": Color(0.9, 0.35, 0.3),
		"accel": Color(0.4, 0.9, 0.4), "look": Color(0.8, 0.8, 0.9)}
	var font := get_theme_default_font()
	for id in _buttons():
		var c := _btn_center(id)
		var r := _btn_radius(id)
		var col: Color = cols[id]
		var down: bool = _pressed.get(id, false)
		draw_circle(c, r, Color(0.05, 0.07, 0.12, 0.45 * op))
		draw_circle(c, r * (0.92 if down else 0.86), Color(col.r, col.g, col.b, (0.75 if down else 0.38) * op))
		draw_arc(c, r, 0, TAU, 48, Color(1, 1, 1, 0.55 * op), 3.0, true)
		var txt: String = labels[id]
		var fs := int(r * 0.42)
		var sz := font.get_string_size(txt, HORIZONTAL_ALIGNMENT_CENTER, -1, fs)
		draw_string(font, c + Vector2(-sz.x * 0.5, fs * 0.35), txt, HORIZONTAL_ALIGNMENT_CENTER, -1, fs, Color(1, 1, 1, 0.95 * op))
	# stick
	var R := _btn_radius("stick")
	var base := _stick_center if _stick_touch >= 0 else _btn_center("stick")
	var knob := _stick_pos if _stick_touch >= 0 else base
	draw_circle(base, R, Color(0.05, 0.07, 0.12, 0.35 * op))
	draw_arc(base, R, 0, TAU, 64, Color(1, 1, 1, 0.45 * op), 3.0, true)
	draw_circle(knob, R * 0.42, Color(1, 1, 1, 0.55 * op))
	# pause tab
	var r2 := get_rect().size
	var pc := Vector2(r2.x * 0.5, r2.y * 0.06)
	draw_rect(Rect2(pc - Vector2(34, 22), Vector2(68, 44)), Color(0.05, 0.07, 0.12, 0.45 * op))
	draw_rect(Rect2(pc + Vector2(-14, -12), Vector2(9, 24)), Color(1, 1, 1, 0.8 * op))
	draw_rect(Rect2(pc + Vector2(5, -12), Vector2(9, 24)), Color(1, 1, 1, 0.8 * op))
	if edit_mode:
		draw_string(font, Vector2(r2.x * 0.3, r2.y * 0.2), "Drag controls to move them. Tap BACK in the menu to finish.", HORIZONTAL_ALIGNMENT_LEFT, -1, 26, Color(1, 1, 1, 0.9))
