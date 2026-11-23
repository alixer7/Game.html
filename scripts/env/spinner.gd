extends Node
## Rotates a sibling node continuously (water wheels, gears, fans).

@export var axis := Vector3.UP
@export var speed := 1.0   # rad/s
@export var target_path: NodePath

var _target: Node3D


func _ready() -> void:
	_target = get_node_or_null(target_path) as Node3D


func _process(dt: float) -> void:
	if _target:
		_target.rotate_object_local(axis.normalized(), speed * dt)
