extends StaticBody3D
## Drivable road collider. Carries its surface id and, for flowing water
## (river lane, flume), the flow vector along its spline.

var surface := Surfaces.ROAD
var path: SplinePath
var flow_speed := 0.0


func surface_at(_p: Vector3) -> int:
	return surface


func flow_at(p: Vector3) -> Vector3:
	if flow_speed <= 0.0 or path == null:
		return Vector3.ZERO
	var i := path.nearest_index(p, 24.0)
	if i < 0:
		return Vector3.ZERO
	return path.tan[i] * flow_speed
