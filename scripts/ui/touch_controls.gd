class_name TouchControls
extends Control
## تحكم لمسي متعدد الأصابع: عصا تحكم عائمة يساراً، سحب للنظر يميناً، وأزرار تعمل مع لمسات متزامنة.

signal button_pressed(id: String)
signal button_released(id: String)

var buttons: Array = []
var blockers: Array = []
var joy_index := -1
var joy_base := Vector2.ZERO
var joy_pos := Vector2.ZERO
var joy_vec := Vector2.ZERO
var look_index := -1
var look_last := Vector2.ZERO
var look_accum := Vector2.ZERO
var held := {}
var enabled := true
var joy_radius := 80.0
var _mouse_btn: TouchBtn = null

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)

func register(b: TouchBtn) -> void:
	buttons.append(b)

func reset() -> void:
	joy_index = -1
	joy_vec = Vector2.ZERO
	look_index = -1
	for b in buttons:
		if b.held:
			b.held = false
			b.queue_redraw()
			button_released.emit(b.id)
	held.clear()

func _btn_at(p: Vector2) -> TouchBtn:
	for i in range(buttons.size() - 1, -1, -1):
		var b: TouchBtn = buttons[i]
		if b.is_visible_in_tree() and b.hit(p):
			return b
	return null

func _input(e: InputEvent) -> void:
	if not enabled or Game.ui_open:
		return
	if e is InputEventScreenTouch:
		var p: Vector2 = get_global_transform_with_canvas().affine_inverse() * e.position
		if e.pressed:
			var b := _btn_at(p)
			if b != null:
				held[e.index] = b
				b.held = true
				b.queue_redraw()
				button_pressed.emit(b.id)
				get_viewport().set_input_as_handled()
				return
			for bl in blockers:
				if is_instance_valid(bl) and bl.is_visible_in_tree() and bl.get_global_rect().has_point(p):
					return
			if p.x < size.x * 0.42 and joy_index == -1:
				joy_index = e.index
				joy_base = p
				joy_pos = p
				joy_vec = Vector2.ZERO
				queue_redraw()
			elif look_index == -1:
				look_index = e.index
				look_last = p
			get_viewport().set_input_as_handled()
		else:
			if held.has(e.index):
				var hb: TouchBtn = held[e.index]
				held.erase(e.index)
				hb.held = false
				hb.queue_redraw()
				button_released.emit(hb.id)
			if e.index == joy_index:
				joy_index = -1
				joy_vec = Vector2.ZERO
				queue_redraw()
			if e.index == look_index:
				look_index = -1
	elif e is InputEventScreenDrag:
		var p2: Vector2 = get_global_transform_with_canvas().affine_inverse() * e.position
		if e.index == joy_index:
			joy_pos = p2
			var d := joy_pos - joy_base
			if d.length() > joy_radius:
				joy_base += d - d.normalized() * joy_radius
				d = joy_pos - joy_base
			joy_vec = d / joy_radius
			queue_redraw()
			get_viewport().set_input_as_handled()
		elif e.index == look_index:
			look_accum += p2 - look_last
			look_last = p2
			get_viewport().set_input_as_handled()
		elif held.has(e.index) and held[e.index].id == "attack":
			look_accum += e.relative * 0.7
	elif e is InputEventMouseButton and e.device != InputEvent.DEVICE_ID_EMULATION and e.button_index == MOUSE_BUTTON_LEFT:
		if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			return
		var p3: Vector2 = get_global_transform_with_canvas().affine_inverse() * e.position
		if e.pressed:
			var b2 := _btn_at(p3)
			if b2 != null:
				_mouse_btn = b2
				b2.held = true
				b2.queue_redraw()
				button_pressed.emit(b2.id)
				get_viewport().set_input_as_handled()
			elif not DisplayServer.is_touchscreen_available():
				Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
				get_viewport().set_input_as_handled()
		elif _mouse_btn != null:
			_mouse_btn.held = false
			_mouse_btn.queue_redraw()
			button_released.emit(_mouse_btn.id)
			_mouse_btn = null

func take_look() -> Vector2:
	var v := look_accum
	look_accum = Vector2.ZERO
	return v

func _draw() -> void:
	if joy_index != -1:
		draw_circle(joy_base, joy_radius + 10, Color(0, 0, 0, 0.22))
		draw_arc(joy_base, joy_radius + 10, 0, TAU, 40, Color(1, 1, 1, 0.35), 3.0, true)
		draw_circle(joy_base + joy_vec * joy_radius, 38, Color(1, 1, 1, 0.4))
	else:
		var hint := Vector2(170, size.y - 170)
		draw_arc(hint, joy_radius, 0, TAU, 40, Color(1, 1, 1, 0.12), 3.0, true)
		draw_circle(hint, 30, Color(1, 1, 1, 0.08))
