extends RefCounted
## Small math / easing helpers shared by all modules.

static func ease_f(name: String, t: float) -> float:
	t = clampf(t, 0.0, 1.0)
	match name:
		"lin": return t
		"out": return 1.0 - pow(1.0 - t, 3.0)
		"snap": return 1.0 - pow(1.0 - t, 5.0)
		"in": return t * t * t
		"io":
			if t < 0.5: return 4.0 * t * t * t
			return 1.0 - pow(-2.0 * t + 2.0, 3.0) / 2.0
		"sine": return 0.5 - 0.5 * cos(PI * t)
		"back":
			var c1 := 1.70158
			var c3 := c1 + 1.0
			return 1.0 + c3 * pow(t - 1.0, 3.0) + c1 * pow(t - 1.0, 2.0)
	return t

static func pick(a: Array):
	return a[randi() % a.size()]

static func rot_xyz(r: Vector3) -> Basis:
	# same convention as three.js Euler 'XYZ': R = Rx * Ry * Rz
	return Basis(Vector3.RIGHT, r.x) * Basis(Vector3.UP, r.y) * Basis(Vector3.BACK, r.z)

static func xf(p := Vector3.ZERO, r := Vector3.ZERO, s := Vector3.ONE) -> Transform3D:
	return Transform3D(rot_xyz(r) * Basis.from_scale(s), p)

static func v3(a) -> Vector3:
	return Vector3(a[0], a[1], a[2] if a.size() > 2 else 0.0)
