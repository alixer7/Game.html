extends Node
## Feeds synthetic touch events into TouchControls and checks the outputs.
var tc: TouchControls
var f := 0
func _ready() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	tc = TouchControls.new()
	layer.add_child(tc)
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
func _process(_d: float) -> void:
	f += 1
	var vp := get_viewport().get_visible_rect().size
	match f:
		3:
			_touch(0, Vector2(250, 500), true)
		5:
			_drag(0, Vector2(250, 400))
		7:
			print("stick up: ", tc.stick)
			_drag(0, Vector2(400, 430))
		9:
			print("stick right-up (beyond radius, base follows): ", tc.stick)
			_touch(1, tc._centers[TouchControls.Btn.JUMP] + Vector2(10, 5), true)
			_touch(2, tc._centers[TouchControls.Btn.BOOST], true)
		11:
			print("jump=", tc.jump_held, " boost=", tc.boost_held, " drift=", tc.drift_held)
			_touch(1, Vector2.ZERO, false)
			_touch(0, Vector2.ZERO, false)
		13:
			print("after release: stick=", tc.stick, " jump=", tc.jump_held, " boost=", tc.boost_held)
			_touch(2, Vector2.ZERO, false)
			_touch(3, tc._centers[TouchControls.Btn.CAM], true)
		15:
			print("ballcam toggled -> ", tc.ball_cam, " boost=", tc.boost_held, " vp=", vp)
			get_tree().quit()
