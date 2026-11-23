extends Node3D
## A small flock circling lazily with individual bobbing; wings flap in the
## vertex shader (COLOR.r marks wing vertices, sign of x picks the side).

@export var count := 6
@export var radius := 28.0
@export var speed := 0.22

var _birds: Array[Node3D] = []
var _phase: Array[float] = []
var _t := 0.0

static var _mesh: ArrayMesh


func _ready() -> void:
	if _mesh == null:
		_mesh = _build_mesh()
	var rng := RandomNumberGenerator.new()
	rng.seed = int(position.x * 10.0 + position.z)
	for i in count:
		var mi := MeshInstance3D.new()
		mi.mesh = _mesh
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var s := rng.randf_range(0.8, 1.2)
		mi.scale = Vector3(s, s, s)
		add_child(mi)
		_birds.append(mi)
		_phase.append(rng.randf() * TAU)


func _process(dt: float) -> void:
	_t += dt
	for i in _birds.size():
		var ph := _phase[i]
		var a := _t * speed + ph * 0.35
		var r := radius * (0.75 + 0.25 * sin(ph * 3.0 + _t * 0.3))
		var pos := Vector3(cos(a) * r, sin(_t * 0.8 + ph) * 2.5 + ph, sin(a) * r)
		var vel := Vector3(-sin(a), 0.0, cos(a))
		_birds[i].position = pos
		_birds[i].basis = Basis.looking_at(vel, Vector3.UP).scaled(_birds[i].basis.get_scale())


static func _build_mesh() -> ArrayMesh:
	var mb := MeshBuilder.new()
	MeshLib.blob(mb, Vector3.ZERO, Vector3(0.18, 0.16, 0.45), 1, null, 0.0, Color(0.2, 0.18, 0.2, 0.0), Color(0.35, 0.3, 0.32, 0.0))
	for side: float in [-1.0, 1.0]:
		var root := Vector3(side * 0.12, 0.05, 0.0)
		var tip := Vector3(side * 0.95, 0.1, 0.15)
		var back := Vector3(side * 0.3, 0.05, 0.28)
		var front := Vector3(side * 0.2, 0.06, -0.2)
		var i0 := mb.add_vertex(root, Vector3.UP, Vector2.ZERO, Color(0.3, 0.27, 0.3, 0.0))
		var i1 := mb.add_vertex(front, Vector3.UP, Vector2.ZERO, Color(0.3, 0.27, 0.3, 0.3))
		var i2 := mb.add_vertex(tip, Vector3.UP, Vector2.ZERO, Color(0.15, 0.14, 0.16, 1.0))
		var i3 := mb.add_vertex(back, Vector3.UP, Vector2.ZERO, Color(0.25, 0.22, 0.25, 0.6))
		mb.quad(i0, i1, i2, i3)
	var m := ShaderMaterial.new()
	m.shader = load("res://shaders/bird.gdshader")
	return mb.commit(null, m)
