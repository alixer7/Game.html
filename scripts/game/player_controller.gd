class_name PlayerController
extends RefCounted
## Maps touch controls, keyboard and gamepad onto a car's controls.

var car: CarSim
var touch: TouchControls
var _air_roll_dir := 0.0

const ACTIONS := {
	"p_throttle": [KEY_W, KEY_UP],
	"p_reverse": [KEY_S, KEY_DOWN],
	"p_left": [KEY_A, KEY_LEFT],
	"p_right": [KEY_D, KEY_RIGHT],
	"p_jump": [KEY_SPACE, KEY_J],
	"p_boost": [KEY_SHIFT, KEY_K],
	"p_drift": [KEY_CTRL, KEY_L],
	"p_roll_left": [KEY_Q],
	"p_roll_right": [KEY_E],
	"p_ballcam": [KEY_C, KEY_TAB],
	"p_pause": [KEY_ESCAPE, KEY_P],
}


static func setup_input_map() -> void:
	for action in ACTIONS:
		if InputMap.has_action(action):
			continue
		InputMap.add_action(action, 0.2)
		for k in ACTIONS[action]:
			var ev := InputEventKey.new()
			ev.physical_keycode = k
			InputMap.action_add_event(action, ev)
	var pad := {
		"p_jump": JOY_BUTTON_A, "p_boost": JOY_BUTTON_B, "p_drift": JOY_BUTTON_X,
		"p_ballcam": JOY_BUTTON_Y, "p_pause": JOY_BUTTON_START,
		"p_roll_left": JOY_BUTTON_LEFT_SHOULDER, "p_roll_right": JOY_BUTTON_RIGHT_SHOULDER,
	}
	for action in pad:
		var jb := InputEventJoypadButton.new()
		jb.button_index = pad[action]
		InputMap.action_add_event(action, jb)
	var axes := [["p_throttle", JOY_AXIS_TRIGGER_RIGHT, 1.0], ["p_reverse", JOY_AXIS_TRIGGER_LEFT, 1.0],
		["p_left", JOY_AXIS_LEFT_X, -1.0], ["p_right", JOY_AXIS_LEFT_X, 1.0]]
	for a in axes:
		var jm := InputEventJoypadMotion.new()
		jm.axis = a[1]
		jm.axis_value = a[2]
		InputMap.action_add_event(a[0], jm)


func update_controls(_dt: float) -> void:
	var c := car.controls
	var sx := 0.0
	var sy := 0.0
	var jump := false
	var boost := false
	var drift := false
	var thr := 0.0
	var has_stick := false
	if touch and touch.enabled:
		sx = touch.stick.x
		sy = touch.stick.y
		has_stick = touch.stick.length_squared() > 0.0
		jump = touch.jump_held
		boost = touch.boost_held
		drift = touch.drift_held
		# stick forward accelerates; pulling it back does not reverse on the ground
		# (it still pitches the car in the air) - reverse is the brake button.
		thr = maxf(0.0, sy)
		if Settings.get_value("auto_throttle", false):
			thr = 1.0
		if touch.brake_held:
			thr = -1.0
	# keyboard / gamepad
	var kx := Input.get_action_strength("p_right") - Input.get_action_strength("p_left")
	var kf := Input.get_action_strength("p_throttle") - Input.get_action_strength("p_reverse")
	var jy := Input.get_joy_axis(0, JOY_AXIS_LEFT_Y) if Input.get_connected_joypads().size() > 0 else 0.0
	if absf(kx) > 0.05:
		sx = kx
	var pitch := sy
	if absf(jy) > 0.2:
		pitch = -jy
	elif absf(kf) > 0.05 and not has_stick:
		pitch = kf
	if absf(kf) > 0.05:
		thr = kf
	jump = jump or Input.is_action_pressed("p_jump")
	boost = boost or Input.is_action_pressed("p_boost")
	drift = drift or Input.is_action_pressed("p_drift")
	var roll_btn := Input.get_action_strength("p_roll_right") - Input.get_action_strength("p_roll_left")

	c.throttle = clampf(thr, -1.0, 1.0)
	c.steer = clampf(sx, -1.0, 1.0)
	c.pitch = clampf(pitch, -1.0, 1.0)
	c.jump = jump
	c.boost = boost
	c.handbrake = drift
	if absf(roll_btn) > 0.1:
		c.roll = roll_btn
		c.yaw = sx
	elif drift and car.num_contacts == 0:
		# air roll: horizontal stick input rolls instead of yawing
		c.roll = sx
		c.yaw = 0.0
	else:
		c.roll = 0.0
		c.yaw = sx
