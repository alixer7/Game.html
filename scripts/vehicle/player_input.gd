class_name PlayerInput
extends RefCounted
## Merges keyboard, gamepad and touch controls into car inputs.

var touch: Node = null      # TouchControls
var _steer := 0.0


func drive(car: Car, dt: float) -> void:
	var kb := Input.get_axis("steer_left", "steer_right")
	var thr := Input.get_action_strength("accelerate")
	var brk := Input.get_action_strength("brake")
	var hb := Input.is_action_pressed("handbrake")
	var nit := Input.is_action_pressed("nitro")
	var steer_target := kb
	var digital := absf(kb) > 0.0 and absf(kb) >= 0.99
	if touch and touch.visible:
		if absf(touch.steer) > absf(steer_target):
			steer_target = touch.steer
			digital = touch.steer_digital
		thr = maxf(thr, touch.gas)
		brk = maxf(brk, touch.brake)
		hb = hb or touch.handbrake
		nit = nit or touch.nitro
		if Game.controls.auto_accel and touch.brake < 0.1:
			thr = maxf(thr, 1.0)
	var sens: float = Game.controls.sensitivity
	if digital:
		# ramp digital steering so taps give small corrections
		var rate := 2.4 * sens
		if signf(steer_target) != signf(_steer) and absf(_steer) > 0.05:
			rate *= 2.0
		_steer = move_toward(_steer, steer_target, rate * dt)
		if is_zero_approx(steer_target):
			_steer = move_toward(_steer, 0.0, 4.0 * dt)
	else:
		_steer = clampf(steer_target * sens, -1.0, 1.0)
	car.steer_in = _steer
	car.throttle = thr
	car.brake_in = brk
	car.handbrake = hb
	car.nitro_in = nit
	car.tcs = Game.settings.traction_control
	car.abs_on = Game.settings.abs
	car.stability = 0.7 if Game.settings.stability else 0.0
	car.steer_assist = Game.settings.steer_assist
