class_name Flytrap
extends Node3D
## Giant snapping flytrap. Cycle: idle -> telegraph (rears back, jaws glow) ->
## snap over its half of the road -> hold -> retract. Phase offsets between the
## plants guarantee a clear line at all times; learning the rhythm lets experts
## keep full speed.

enum { IDLE, TELL, SNAP, HOLD, BACK }

@export var phase := 0.0
@export var reach := 4.5

const T_IDLE := 1.9
const T_TELL := 0.85
const T_SNAP := 0.28
const T_HOLD := 0.45
const T_BACK := 0.6

var state := IDLE
var _t := 0.0
var _stalk: Node3D
var _upper: Node3D
var _lower: Node3D
var _zone: Area3D
var _glow_mat: StandardMaterial3D


func _ready() -> void:
	_stalk = get_node("Stalk")
	_upper = get_node("Stalk/Head/Upper")
	_lower = get_node("Stalk/Head/Lower")
	_zone = get_node("Zone")
	_zone.body_entered.connect(_on_zone)
	_t = phase
	_glow_mat = (get_node("Stalk/Head/Upper/Mesh") as MeshInstance3D).material_override as StandardMaterial3D


func _cycle() -> float:
	return T_IDLE + T_TELL + T_SNAP + T_HOLD + T_BACK


func _physics_process(dt: float) -> void:
	_t = fmod(_t + dt, _cycle())
	var t := _t
	var lean := 0.0
	var open := 0.15
	var glow := 0.0
	if t < T_IDLE:
		state = IDLE
		lean = sin(t * 2.0) * 0.05
		open = 0.2 + sin(t * 3.0) * 0.05
	elif t < T_IDLE + T_TELL:
		state = TELL
		var u := (t - T_IDLE) / T_TELL
		lean = -0.35 * smoothstep(0.0, 1.0, u)
		open = lerpf(0.2, 0.95, u)
		glow = u
	elif t < T_IDLE + T_TELL + T_SNAP:
		state = SNAP
		var u := (t - T_IDLE - T_TELL) / T_SNAP
		lean = lerpf(-0.35, 1.25, u)
		open = lerpf(0.95, 0.0, u)
		glow = 1.0
	elif t < T_IDLE + T_TELL + T_SNAP + T_HOLD:
		state = HOLD
		lean = 1.25
		open = 0.0
		glow = 0.6
	else:
		state = BACK
		var u := (t - T_IDLE - T_TELL - T_SNAP - T_HOLD) / T_BACK
		lean = lerpf(1.25, 0.0, smoothstep(0.0, 1.0, u))
		open = lerpf(0.0, 0.2, u)
	_stalk.rotation = Vector3(lean, 0, 0)
	_upper.rotation = Vector3(-open * 0.9, 0, 0)
	_lower.rotation = Vector3(open * 0.5, 0, 0)
	if _glow_mat:
		_glow_mat.emission_energy_multiplier = glow * 2.5
	_zone.monitoring = state == SNAP or state == HOLD
	if _zone.monitoring:
		for b in _zone.get_overlapping_bodies():
			_on_zone(b)


func _on_zone(b: Node) -> void:
	if (state == SNAP or state == HOLD) and b is Kart:
		var k := b as Kart
		if k.spin_time <= 0.0:
			k.spin_out(1.0)
			if k.is_player:
				Sfx.play("snap", k.global_position)


static func make(phase_: float, road_half: float) -> Node3D:
	## Built facing +Z (the road is in front of it, along local +Z).
	var n: Node3D = load("res://scripts/env/flytrap.gd").new()
	n.set("phase", phase_)
	var base := MeshBuilder.new()
	var nz := MeshLib.make_noise(int(phase_ * 100.0), 0.8)
	for i in 6:
		var a := TAU * float(i) / 6.0
		var leaf := PackedVector3Array([Vector3(0, 0.1, 0), Vector3(cos(a) * 1.4, 0.5, sin(a) * 1.4), Vector3(cos(a) * 2.6, 0.2, sin(a) * 2.6)])
		MeshLib.tube(base, leaf, PackedFloat32Array([0.35, 0.4, 0.08]), 5, func(t: float, _a: float, _p: Vector3) -> Color: return Color(0.2, 0.5, 0.15).lerp(Color(0.55, 0.75, 0.2), t))
	var bm := MeshInstance3D.new()
	bm.mesh = base.commit(null, Mats.vcol(0.8))
	n.add_child(bm)
	var stalk := Node3D.new()
	stalk.name = "Stalk"
	n.add_child(stalk)
	var sm := MeshBuilder.new()
	var stalk_h := 3.2
	MeshLib.tube(sm, PackedVector3Array([Vector3(0, 0, 0), Vector3(0, stalk_h * 0.5, 0.4), Vector3(0, stalk_h, 0.9)]),
		PackedFloat32Array([0.45, 0.32, 0.3]), 7, func(t: float, _a: float, _p: Vector3) -> Color: return Color(0.25, 0.48, 0.15).lerp(Color(0.4, 0.62, 0.2), t))
	var smi := MeshInstance3D.new()
	smi.mesh = sm.commit(null, Mats.vcol(0.8))
	stalk.add_child(smi)
	var head := Node3D.new()
	head.name = "Head"
	head.position = Vector3(0, stalk_h, 0.9)
	stalk.add_child(head)
	for j in 2:
		var jaw := Node3D.new()
		jaw.name = "Upper" if j == 0 else "Lower"
		head.add_child(jaw)
		var jm := MeshBuilder.new()
		var sgn := 1.0 if j == 0 else -1.0
		MeshLib.blob(jm, Vector3(0, sgn * 0.35, 1.3), Vector3(1.3, 0.38, 1.4), 2, nz, 0.08,
			Color(0.75, 0.12, 0.1) if j == 0 else Color(0.35, 0.6, 0.15), Color(0.35, 0.62, 0.15) if j == 0 else Color(0.85, 0.2, 0.15))
		for t in 7:
			var a := lerpf(-1.1, 1.1, float(t) / 6.0)
			var tp := Vector3(sin(a) * 1.25, 0, 1.3 + cos(a) * 1.3)
			MeshLib.tube(jm, PackedVector3Array([tp, tp + Vector3(0, -sgn * 0.45, 0)]), PackedFloat32Array([0.08, 0.0]), 4,
				func(_t: float, _a: float, _p: Vector3) -> Color: return Color(1, 0.95, 0.8))
		var jmi := MeshInstance3D.new()
		jmi.name = "Mesh"
		jmi.mesh = jm.commit()
		var mat := StandardMaterial3D.new()
		mat.vertex_color_use_as_albedo = true
		mat.roughness = 0.6
		mat.emission_enabled = true
		mat.emission = Color(1.0, 0.3, 0.1)
		mat.emission_energy_multiplier = 0.0
		jmi.material_override = mat
		jaw.add_child(jmi)
	var zone := Area3D.new()
	zone.name = "Zone"
	zone.collision_layer = 0
	zone.collision_mask = 2
	zone.monitoring = false
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(3.6, 2.5, reach_for(road_half))
	cs.shape = bs
	cs.position = Vector3(0, 1.2, 1.2 + reach_for(road_half) * 0.5)
	zone.add_child(cs)
	n.add_child(zone)
	var body := StaticBody3D.new()
	body.collision_layer = 1
	var bcs := CollisionShape3D.new()
	var cyl := CylinderShape3D.new()
	cyl.radius = 1.0
	cyl.height = 3.0
	bcs.shape = cyl
	bcs.position = Vector3(0, 1.5, 0)
	body.add_child(bcs)
	n.add_child(body)
	return n


static func reach_for(road_half: float) -> float:
	return road_half + 0.5
