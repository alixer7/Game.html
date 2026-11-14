class_name CarControls
extends RefCounted
## One frame of car input. Conventions:
##   throttle +1 forward, steer/yaw +1 right, pitch +1 = stick up (nose down),
##   roll +1 = roll right.

var throttle := 0.0
var steer := 0.0
var pitch := 0.0
var yaw := 0.0
var roll := 0.0
var jump := false
var boost := false
var handbrake := false


func reset() -> void:
	throttle = 0.0
	steer = 0.0
	pitch = 0.0
	yaw = 0.0
	roll = 0.0
	jump = false
	boost = false
	handbrake = false


func copy_from(o: CarControls) -> void:
	throttle = o.throttle
	steer = o.steer
	pitch = o.pitch
	yaw = o.yaw
	roll = o.roll
	jump = o.jump
	boost = o.boost
	handbrake = o.handbrake
