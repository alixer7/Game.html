extends Control

## Precision Multi-Touch Mobile Racing Controls (CTR-Ergonomic Thumb Layout).
## - Enforces LTR coordinate space so Arabic Android phones NEVER mirror touch hitboxes.
## - Prevents emulated-mouse double firing on Android touchscreens!
## - Respects Android Display Safe Area (notches, punch-holes, gesture nav bars).
## - Full CTR Control Suite: Left/Right Buttons OR Virtual Joystick, Hop/Drift, Boost!,
##   Air-Brake U-Turn, Item, Look-Back Rear Camera, and optional Manual Gas!

var steer_value: float = 0.0
var gas_held: bool = false
var hop_held: bool = false
var uturn_held: bool = false
var look_back_held: bool = false

var _hop_just_pressed: bool = false
var _boost_just_pressed: bool = false
var _item_just_pressed: bool = false

var _touches: Dictionary = {}
var _stick_touch_idx: int = -1
var _stick_center: Vector2 = Vector2.ZERO
var _stick_knob: Vector2 = Vector2.ZERO
var _mouse_action: String = ""
var _seen_real_touch: bool = false

var _drift_active: bool = false
var _drift_charge: float = 0.0
var _is_airborne: bool = false
var _held_item: String = ""
var _juiced: bool = false
var _fire_tier: int = 0
var _tnt_active: bool = false
var _pulse_time: float = 0.0

var _rect_left: Rect2
var _rect_right: Rect2
var _stick_radius: float = 96.0
var _center_hop: Vector2
var _rad_hop: float = 66.0
var _center_boost: Vector2
var _rad_boost: float = 56.0
var _center_uturn: Vector2
var _rad_uturn: float = 48.0
var _center_item: Vector2
var _rad_item: float = 46.0
var _center_gas: Vector2
var _rad_gas: float = 46.0
var _center_rear: Vector2
var _rad_rear: float = 38.0

func _ready() -> void:
	layout_direction = Control.LAYOUT_DIRECTION_LTR
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_compute_layout()
	get_viewport().size_changed.connect(_compute_layout)

func _get_safe_insets(vp: Vector2) -> Dictionary:
	var l := 28.0
	var r := 28.0
	var b := 24.0
	var win_sz := DisplayServer.window_get_size()
	var safe := DisplayServer.get_display_safe_area()
	if win_sz.x > 0 and win_sz.y > 0 and safe.size.x > 0 and safe.size.y > 0:
		var sx := vp.x / float(win_sz.x)
		var sy := vp.y / float(win_sz.y)
		l = maxf(l, float(safe.position.x) * sx + 14.0)
		r = maxf(r, float(win_sz.x - safe.end.x) * sx + 14.0)
		b = maxf(b, float(win_sz.y - safe.end.y) * sy + 14.0)
	return {"left": l, "right": r, "bottom": b}

func _compute_layout() -> void:
	var vp := get_viewport_rect().size
	if vp.x < 10.0:
		vp = Vector2(1280.0, 720.0)
	var ins := _get_safe_insets(vp)
	var s := clampf(minf(vp.x / 1280.0, vp.y / 720.0), 0.72, 1.25)
	var pad_l: float = ins["left"]
	var pad_r: float = ins["right"]
	var pad_b: float = ins["bottom"]

	# Left Steering Cluster (Precision CTR Left/Right Buttons OR Virtual Stick)
	var btn_w := 126.0 * s
	var btn_h := 114.0 * s
	var gap := 18.0 * s
	_rect_left = Rect2(pad_l, vp.y - pad_b - btn_h, btn_w, btn_h)
	_rect_right = Rect2(pad_l + btn_w + gap, vp.y - pad_b - btn_h, btn_w, btn_h)
	_stick_radius = 94.0 * s
	_stick_center = Vector2(pad_l + btn_w + gap * 0.5, vp.y - pad_b - btn_h * 0.55)
	if _stick_touch_idx == -1:
		_stick_knob = _stick_center

	# Look-Back Rear-View Button tucked cleanly above Left Steering
	_rad_rear = 38.0 * s
	_center_rear = Vector2(pad_l + _rad_rear + 6.0 * s, _rect_left.position.y - _rad_rear - 18.0 * s)

	# Right Ergonomic Thumb Arc (generous non-overlapping spacing + safe-area inset!)
	_rad_hop = 66.0 * s
	_rad_boost = 56.0 * s
	_rad_uturn = 48.0 * s
	_rad_item = 46.0 * s
	_rad_gas = 46.0 * s

	_center_hop = Vector2(vp.x - pad_r - _rad_hop - 8.0 * s, vp.y - pad_b - _rad_hop - 6.0 * s)
	_center_boost = _center_hop + Vector2(-146.0 * s, -94.0 * s)
	_center_uturn = _center_hop + Vector2(-156.0 * s, 22.0 * s)
	_center_uturn.y = minf(_center_uturn.y, vp.y - pad_b - _rad_uturn)
	_center_item = _center_hop + Vector2(2.0 * s, -154.0 * s)
	_center_gas = _center_hop + Vector2(-280.0 * s, 12.0 * s)
	queue_redraw()

func get_debug_buttons() -> Array[Dictionary]:
	# Used by automated layout verifier to guarantee 0 clipping and 0 overlaps!
	var out: Array[Dictionary] = [
		{"name": "left", "rect": _rect_left},
		{"name": "right", "rect": _rect_right},
		{"name": "rear", "rect": Rect2(_center_rear - Vector2(_rad_rear, _rad_rear), Vector2(_rad_rear * 2.0, _rad_rear * 2.0))},
		{"name": "hop", "rect": Rect2(_center_hop - Vector2(_rad_hop, _rad_hop), Vector2(_rad_hop * 2.0, _rad_hop * 2.0))},
		{"name": "boost", "rect": Rect2(_center_boost - Vector2(_rad_boost, _rad_boost), Vector2(_rad_boost * 2.0, _rad_boost * 2.0))},
		{"name": "uturn", "rect": Rect2(_center_uturn - Vector2(_rad_uturn, _rad_uturn), Vector2(_rad_uturn * 2.0, _rad_uturn * 2.0))},
		{"name": "item", "rect": Rect2(_center_item - Vector2(_rad_item, _rad_item), Vector2(_rad_item * 2.0, _rad_item * 2.0))}
	]
	if not GameState.auto_accelerate:
		out.append({"name": "gas", "rect": Rect2(_center_gas - Vector2(_rad_gas, _rad_gas), Vector2(_rad_gas * 2.0, _rad_gas * 2.0))})
	return out

func consume_hop_just_pressed() -> bool:
	var v := _hop_just_pressed
	_hop_just_pressed = false
	return v

func consume_boost_just_pressed() -> bool:
	var v := _boost_just_pressed
	_boost_just_pressed = false
	return v

func consume_item_just_pressed() -> bool:
	var v := _item_just_pressed
	_item_just_pressed = false
	return v

func update_visual_state(kart: KartPhysics) -> void:
	if not kart:
		return
	_drift_active = kart.is_drifting
	_drift_charge = kart.drift_charge
	_is_airborne = not kart.is_grounded
	_held_item = kart.held_item if kart.item_roulette_timer <= 0.0 else ""
	_juiced = kart.is_juiced()
	_fire_tier = kart.fire_tier
	_tnt_active = kart.tnt_attached

func _process(delta: float) -> void:
	_pulse_time += delta
	_recompute_outputs()
	queue_redraw()

func _input(event: InputEvent) -> void:
	if get_tree().paused:
		_touches.clear()
		_stick_touch_idx = -1
		_mouse_action = ""
		return

	if event is InputEventScreenTouch:
		_seen_real_touch = true
		var te := event as InputEventScreenTouch
		var p := _to_local_pos(te.position)
		if te.pressed:
			var act := _hit_test(p)
			if act != "":
				_touches[te.index] = act
				_on_action_down(act, te.index, p)
		else:
			if _touches.has(te.index):
				if te.index == _stick_touch_idx:
					_stick_touch_idx = -1
					_stick_knob = _stick_center
				_touches.erase(te.index)
	elif event is InputEventScreenDrag:
		_seen_real_touch = true
		var de := event as InputEventScreenDrag
		var p := _to_local_pos(de.position)
		if de.index == _stick_touch_idx:
			var delta_v := p - _stick_center
			if delta_v.length() > _stick_radius:
				delta_v = delta_v.normalized() * _stick_radius
			_stick_knob = _stick_center + delta_v
		elif _touches.has(de.index):
			# Smooth seamless Left <-> Right thumb slide without lifting finger!
			var cur_act: String = _touches[de.index]
			if cur_act == "left" or cur_act == "right":
				if _rect_left.grow(26.0).has_point(p):
					_touches[de.index] = "left"
				elif _rect_right.grow(26.0).has_point(p):
					_touches[de.index] = "right"
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		# Prevent double-firing emulated touch-as-mouse events on Android!
		if _seen_real_touch or OS.has_feature("mobile"):
			return
		var me := event as InputEventMouseButton
		var p := _to_local_pos(me.position)
		if me.pressed:
			var act := _hit_test(p)
			if act != "":
				_mouse_action = act
				_on_action_down(act, -99, p)
		else:
			if _mouse_action == "stick":
				_stick_touch_idx = -1
				_stick_knob = _stick_center
			_mouse_action = ""

func _to_local_pos(screen_pos: Vector2) -> Vector2:
	return get_global_transform_with_canvas().affine_inverse() * screen_pos

func _hit_test(p: Vector2) -> String:
	if GameState.use_joystick:
		if p.distance_to(_stick_center) <= _stick_radius * 1.35:
			return "stick"
	else:
		if _rect_left.grow(16.0).has_point(p):
			return "left"
		if _rect_right.grow(16.0).has_point(p):
			return "right"

	if p.distance_to(_center_rear) <= _rad_rear * 1.25:
		return "rear"
	if p.distance_to(_center_hop) <= _rad_hop * 1.18:
		return "hop"
	if p.distance_to(_center_boost) <= _rad_boost * 1.22:
		return "boost"
	if p.distance_to(_center_uturn) <= _rad_uturn * 1.22:
		return "uturn"
	if p.distance_to(_center_item) <= _rad_item * 1.25:
		return "item"
	if not GameState.auto_accelerate and p.distance_to(_center_gas) <= _rad_gas * 1.22:
		return "gas"
	return ""

func _on_action_down(act: String, idx: int, p: Vector2) -> void:
	match act:
		"stick":
			_stick_touch_idx = idx
			var dv := p - _stick_center
			if dv.length() > _stick_radius:
				dv = dv.normalized() * _stick_radius
			_stick_knob = _stick_center + dv
		"hop":
			_hop_just_pressed = true
		"boost":
			_boost_just_pressed = true
		"item":
			_item_just_pressed = true

func _recompute_outputs() -> void:
	var left_on := false
	var right_on := false
	hop_held = false
	uturn_held = false
	gas_held = false
	look_back_held = false

	var active_acts: Array[String] = []
	for act in _touches.values():
		active_acts.append(str(act))
	if _mouse_action != "":
		active_acts.append(_mouse_action)

	for act in active_acts:
		match act:
			"left": left_on = true
			"right": right_on = true
			"hop": hop_held = true
			"uturn": uturn_held = true
			"gas": gas_held = true
			"rear": look_back_held = true

	if GameState.use_joystick:
		if _stick_touch_idx != -1 or _mouse_action == "stick":
			steer_value = clampf((_stick_knob.x - _stick_center.x) / (_stick_radius * 0.78), -1.0, 1.0)
		else:
			steer_value = 0.0
	else:
		steer_value = (1.0 if right_on else 0.0) - (1.0 if left_on else 0.0)

func _is_pressed(act_name: String) -> bool:
	if _mouse_action == act_name:
		return true
	for a in _touches.values():
		if str(a) == act_name:
			return true
	return false

func _draw() -> void:
	var alpha := GameState.controls_opacity if GameState else 0.85
	var font := UITheme.font_black()

	# 1. Left Side: Precision Left/Right Buttons OR Virtual Joystick + Rear-View Look-Back
	if GameState.use_joystick:
		draw_circle(_stick_center, _stick_radius, Color(0.08, 0.10, 0.16, 0.45 * alpha))
		draw_arc(_stick_center, _stick_radius, 0.0, TAU, 36, Color(1.0, 0.78, 0.22, 0.85 * alpha), 5.0, true)
		draw_circle(_stick_knob, _stick_radius * 0.42, Color(1.0, 0.56, 0.10, 0.90 * alpha))
		draw_arc(_stick_knob, _stick_radius * 0.42, 0.0, TAU, 24, Color(0.12, 0.05, 0.02, alpha), 4.0, true)
	else:
		_draw_steer_pad(_rect_left, true, _is_pressed("left"), alpha)
		_draw_steer_pad(_rect_right, false, _is_pressed("right"), alpha)

	_draw_round_btn(_center_rear, _rad_rear, Color(0.18, 0.28, 0.46), GameState.t("look_back"), _is_pressed("rear"), alpha * 0.9, font, 14)

	# 2. HOP / DRIFT Button
	var hop_col := Color(0.98, 0.48, 0.06)
	if _tnt_active and sin(_pulse_time * 22.0) > 0.0:
		hop_col = Color(1.0, 0.14, 0.10)
	elif _drift_active:
		hop_col = Color(1.0, 0.72, 0.10)
	_draw_round_btn(_center_hop, _rad_hop, hop_col, GameState.t("hop_drift"), _is_pressed("hop"), alpha, font, 19)

	# 3. BOOST! Button (Dynamic CTR Sweet-Spot Glow!)
	var boost_col := Color(0.32, 0.36, 0.46)
	var boost_scale := 1.0
	if _drift_active:
		if _drift_charge >= 0.76:
			boost_col = Color(1.0, 0.20, 0.08)
			boost_scale = 1.12 + sin(_pulse_time * 32.0) * 0.06
		elif _drift_charge >= 0.48:
			boost_col = Color(0.18, 0.88, 0.30)
			boost_scale = 1.06
		else:
			boost_col = Color(0.86, 0.56, 0.10)
	elif _fire_tier >= 4:
		boost_col = Color(0.10, 0.72, 1.0)
	_draw_round_btn(_center_boost, _rad_boost * boost_scale, boost_col, GameState.t("boost"), _is_pressed("boost"), alpha, font, 20)

	# 4. U-TURN / AIR-BRAKE Button (Glows Electric Cyan when Airborne!)
	var ut_col := Color(0.12, 0.84, 0.98) if _is_airborne else Color(0.22, 0.32, 0.52)
	_draw_round_btn(_center_uturn, _rad_uturn, ut_col, GameState.t("uturn"), _is_pressed("uturn"), alpha, font, 15)

	# 5. ITEM Button
	var item_col := Color(0.20, 0.24, 0.32, 0.65)
	var item_txt := GameState.t("item")
	if _held_item != "":
		item_col = Color(0.95, 0.74, 0.10) if _juiced else Color(0.58, 0.20, 0.88)
		item_txt = GameState.t("item_" + _held_item)
	_draw_round_btn(_center_item, _rad_item, item_col, item_txt, _is_pressed("item"), alpha, font, 16)

	# 6. Optional Manual GAS Button (when Auto-Accelerate is OFF)
	if not GameState.auto_accelerate:
		_draw_round_btn(_center_gas, _rad_gas, Color(0.14, 0.76, 0.28), GameState.t("gas"), _is_pressed("gas"), alpha, font, 18)

func _draw_steer_pad(rect: Rect2, is_left: bool, pressed: bool, alpha: float) -> void:
	var bg := Color(1.0, 0.62, 0.10, 0.90 * alpha) if pressed else Color(0.10, 0.14, 0.22, 0.68 * alpha)
	var border := Color(1.0, 0.92, 0.45, alpha) if pressed else Color(1.0, 0.70, 0.18, 0.88 * alpha)
	draw_rect(rect, bg, true)
	draw_rect(rect, border, false, 5.0)
	var c := rect.get_center()
	var s := rect.size.y * 0.28
	var pts := PackedVector2Array()
	if is_left:
		pts = PackedVector2Array([c + Vector2(-s, 0), c + Vector2(s * 0.75, -s), c + Vector2(s * 0.75, s)])
	else:
		pts = PackedVector2Array([c + Vector2(s, 0), c + Vector2(-s * 0.75, -s), c + Vector2(-s * 0.75, s)])
	draw_colored_polygon(pts, Color(0.12, 0.05, 0.02, alpha) if pressed else Color(1.0, 0.96, 0.88, 0.95 * alpha))

func _draw_round_btn(center: Vector2, rad: float, fill: Color, label: String, pressed: bool, alpha: float, font: Font, font_sz: int) -> void:
	var c := fill.lightened(0.22) if pressed else fill
	c.a *= alpha
	var r := rad * (0.93 if pressed else 1.0)
	draw_circle(center + Vector2(0, 5), r, Color(0.0, 0.0, 0.0, 0.42 * alpha))
	draw_circle(center, r, c)
	draw_circle(center + Vector2(0, -r * 0.18), r * 0.72, Color(1.0, 1.0, 1.0, 0.16 * alpha))
	draw_arc(center, r, 0.0, TAU, 32, Color(0.08, 0.04, 0.02, alpha), 5.5, true)
	draw_arc(center, r - 4.0, 0.0, TAU, 32, Color(1.0, 0.94, 0.75, 0.55 * alpha), 2.2, true)

	var lines := label.split("\n")
	var line_h := float(font_sz) * 1.12
	var start_y := center.y - (float(lines.size() - 1) * line_h * 0.5) + float(font_sz) * 0.34
	for i in range(lines.size()):
		var txt := lines[i]
		var sz := font.get_string_size(txt, HORIZONTAL_ALIGNMENT_CENTER, -1, font_sz)
		var pos := Vector2(center.x - sz.x * 0.5, start_y + float(i) * line_h)
		draw_string_outline(font, pos, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, font_sz, 5, Color(0.06, 0.03, 0.01, alpha))
		draw_string(font, pos, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, font_sz, Color(1.0, 1.0, 1.0, alpha))
