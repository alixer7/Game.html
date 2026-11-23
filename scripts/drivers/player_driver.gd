class_name PlayerDriver
extends Node
## Maps keyboard / gamepad / touch into the kart's input fields every physics tick.

var kart: Kart
var camera: ChaseCamera
var _prev_boost := false
var _prev_item := false
var enabled := true


func _physics_process(_dt: float) -> void:
	if kart == null or not enabled:
		return
	var t: Dictionary = Game.touch
	var s := Input.get_axis("steer_left", "steer_right")
	var throttle := Input.get_action_strength("accelerate")
	var brake := Input.get_action_strength("brake")
	var drift := Input.is_action_pressed("drift")
	var boost := Input.is_action_pressed("boost")
	var item := Input.is_action_pressed("item")
	var look_back := Input.is_action_pressed("look_back")
	if t.active:
		var sens: float = Game.settings["steer_sensitivity"]
		var ts: float = t.steer
		ts = signf(ts) * pow(absf(ts), lerpf(1.6, 0.8, clampf(sens - 0.5, 0.0, 1.0)))
		if absf(ts) > absf(s):
			s = ts
		if t.accel or Game.settings["auto_accel"]:
			throttle = maxf(throttle, 1.0)
		if t.brake or float(t.stick_y) < -0.6:
			brake = maxf(brake, 1.0)
			if Game.settings["auto_accel"] and not t.accel:
				throttle = 0.0
		drift = drift or t.drift
		if t.boost_pressed:
			boost = true
			t.boost_pressed = false
		if t.item_pressed:
			item = true
			t.item_pressed = false
		look_back = look_back or t.look_back
	kart.in_steer = clampf(s, -1.0, 1.0)
	kart.in_throttle = throttle
	kart.in_brake = brake
	kart.in_drift = drift
	if boost and not _prev_boost:
		kart.in_boost = true
	_prev_boost = boost and not t.active
	if item and not _prev_item:
		kart.in_item = true
	_prev_item = item and not t.active
	if camera:
		camera.look_back = look_back
