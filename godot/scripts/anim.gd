extends RefCounted
## Plays pose clips with cross-fade blending.

const U = preload("res://scripts/util.gd")
const PoseL = preload("res://scripts/pose.gd")

var clip_d = null
var t := 0.0
var speed := 1.0
var from: PackedFloat32Array
var out: PackedFloat32Array
var blend := 1.0
var bd := 0.0
var name := ""

func _init(g: PackedFloat32Array) -> void:
	out = g.duplicate()
	from = g.duplicate()

func play(c: Dictionary, b := 4.0, nm := "") -> void:
	from = out.duplicate()
	clip_d = c
	t = 0.0
	bd = b
	blend = 0.0 if b > 0.0 else 1.0
	name = nm

func advance(df: float) -> void:
	t += df * speed
	if bd > 0.0: blend = minf(1.0, blend + df / bd)

func eval() -> PackedFloat32Array:
	if clip_d == null: return out
	var s: PackedFloat32Array = PoseL.sample(clip_d, t)
	if blend < 1.0:
		out = PoseL.lerp_pose(from, s, U.ease_f("sine", blend))
	else:
		out = s.duplicate()
	return out
