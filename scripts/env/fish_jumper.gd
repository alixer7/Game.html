extends Node3D
## Occasionally a fish leaps out of the water in a little arc.

@export var flow_dir := Vector3.FORWARD
@export var area := 6.0

var _fish: MeshInstance3D
var _t := 0.0
var _next := 2.0
var _jumping := false
var _from := Vector3.ZERO
var _dir := Vector3.FORWARD
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.randomize()
	var mb := MeshBuilder.new()
	MeshLib.blob(mb, Vector3.ZERO, Vector3(0.12, 0.16, 0.42), 1, null, 0.0, Color(0.85, 0.85, 0.8), Color(0.35, 0.55, 0.6))
	MeshLib.tube(mb, PackedVector3Array([Vector3(0, 0, 0.35), Vector3(0, 0, 0.62)]), PackedFloat32Array([0.08, 0.2]), 4,
		func(_tt: float, _a: float, _p: Vector3) -> Color: return Color(0.4, 0.55, 0.6))
	_fish = MeshInstance3D.new()
	_fish.mesh = mb.commit(null, Mats.vcol(0.3, 0.3))
	_fish.visible = false
	add_child(_fish)
	_next = _rng.randf_range(1.5, 5.0)


func _process(dt: float) -> void:
	_t += dt
	if not _jumping:
		if _t > _next:
			_jumping = true
			_t = 0.0
			_from = Vector3(_rng.randf_range(-area, area), -0.3, _rng.randf_range(-area, area))
			var d := flow_dir if _rng.randf() < 0.6 else Vector3(_rng.randf_range(-1, 1), 0, _rng.randf_range(-1, 1))
			_dir = Vector3(d.x, 0, d.z).normalized()
			_fish.visible = true
		return
	var dur := 0.9
	var u := _t / dur
	if u >= 1.0:
		_jumping = false
		_fish.visible = false
		_t = 0.0
		_next = _rng.randf_range(2.5, 7.0)
		return
	var pos := _from + _dir * u * 2.2 + Vector3.UP * (sin(u * PI) * 1.3)
	_fish.position = pos
	var vel := _dir * 2.2 + Vector3.UP * cos(u * PI) * 1.3 * PI
	_fish.basis = Basis.looking_at(vel.normalized(), Vector3.UP)
