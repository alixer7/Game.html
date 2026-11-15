extends Node
## Feeds synthetic touches into TouchControls + PlayerController (run with a display).
var tc: TouchControls
var pc: PlayerController
var car: CarSim
var f := 0
var fails := 0

func _ready() -> void:
	Settings.data["joystick_fixed"] = false
	Settings.data["touch_layout"] = {}
	Settings.data["auto_throttle"] = false
	var layer := CanvasLayer.new()
	add_child(layer)
	tc = TouchControls.new()
	layer.add_child(tc)
	car = CarSim.new()
	pc = PlayerController.new()
	pc.car = car
	pc.touch = tc

func _touch(idx: int, pos: Vector2, pressed: bool) -> void:
	var e := InputEventScreenTouch.new()
	e.index = idx
	e.position = pos
	e.pressed = pressed
	Input.parse_input_event(e)

func _drag(idx: int, pos: Vector2) -> void:
	var e := InputEventScreenDrag.new()
	e.index = idx
	e.position = pos
	Input.parse_input_event(e)

func check(cond: bool, msg: String) -> void:
	print(("PASS " if cond else "FAIL ") + msg)
	if not cond:
		fails += 1

func _process(_d: float) -> void:
	f += 1
	pc.update_controls(0.016)
	var c := car.controls
	match f:
		3:
			_touch(0, Vector2(250, 500), true)
		5:
			_drag(0, Vector2(250, 400))
		7:
			check(tc.stick.y > 0.95 and c.throttle > 0.95, "stick forward accelerates (thr=%.2f)" % c.throttle)
			_drag(0, Vector2(250, 600))
		9:
			check(tc.stick.y < -0.9 and absf(c.throttle) < 0.01 and c.pitch < -0.9, "stick back: no reverse, still pitches (thr=%.2f pitch=%.2f)" % [c.throttle, c.pitch])
			_drag(0, Vector2(400, 500))
		11:
			check(c.steer > 0.9 and c.throttle < 0.25, "stick right steers (thr=%.2f)" % c.throttle)
			_touch(1, tc.element_center("brake"), true)
		13:
			check(tc.brake_held and c.throttle < -0.99, "brake button reverses (thr=%.2f)" % c.throttle)
			_touch(1, Vector2.ZERO, false)
			_touch(0, Vector2.ZERO, false)
			Settings.data["joystick_fixed"] = true
		15:
			var base := tc.element_center("stick")
			_touch(2, base + Vector2(150, -40), true)
		17:
			check(tc._stick_base == tc.element_center("stick"), "fixed stick base does not move")
			check(tc.stick.x > 0.9, "touching around fixed stick steers (x=%.2f)" % tc.stick.x)
			_drag(2, tc.element_center("stick") + Vector2(0, -400))
		19:
			check(tc._stick_base == tc.element_center("stick") and tc.stick.y > 0.95, "fixed stick clamps, base stays")
			_touch(2, Vector2.ZERO, false)
			Settings.data["touch_layout"] = {"jump": [1.0, 1.0, 1.6, 0.5], "pause": [0.0, 0.0, 1.0, 1.0]}
			tc._on_settings_changed()
		21:
			var vp := get_viewport().get_visible_rect().size
			var ok := true
			for e in TouchControls.ELEMENTS:
				var cc: Vector2 = tc.element_center(e)
				var rr: float = tc._radii[e] + tc._extra(e)
				if cc.x - rr < 0 or cc.y - rr < 0 or cc.x + rr > vp.x or cc.y + rr > vp.y:
					ok = false
					print("  off-screen: ", e, " ", cc, " r=", rr)
			check(ok, "all controls fully on screen (incl. oversized jump at the corner)")
			print("RESULT fails=%d" % fails)
			get_tree().quit()
