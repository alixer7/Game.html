class_name ArenaGeo
extends RefCounted
## Procedural arena geometry: an octagonal stadium (chamfered corners) whose
## floor, walls and ceiling are joined by smooth quarter-pipe curves, with two
## goals cut into the end walls. The same triangles are used for rendering and
## for the collision trimesh, and an exact analytic SDF of the shell (without
## the goal cut-outs) is used as a cheap broad-phase.

const SQ2 := 1.4142135623730951
const R := Phys.CURVE_R
const X1 := Phys.HALF_W - Phys.CURVE_R
const Z1 := Phys.HALF_L - Phys.CURVE_R
const KP := Phys.HALF_W + Phys.HALF_L - Phys.CHAMFER - Phys.CURVE_R * SQ2
const ZA := KP - X1
const XB := KP - Z1
const YC := Phys.HEIGHT * 0.5
const YH := Phys.HEIGHT * 0.5 - Phys.CURVE_R

const N_BOTTOM := 14
const N_TOP := 8
const N_CORNER := 8


class Surf:
	var v := PackedVector3Array()
	var n := PackedVector3Array()
	var uv := PackedVector2Array()

	## Adds a triangle facing the direction of the supplied normals.
	func tri(a: Vector3, b: Vector3, c: Vector3, na: Vector3, nb: Vector3, nc: Vector3,
			ua: Vector2, ub: Vector2, uc: Vector2) -> void:
		var cr := (b - a).cross(c - a)
		if cr.length_squared() < 1e-12:
			return
		# Godot treats clockwise triangles as front faces, so the right-handed
		# normal of a front face points away from the viewer.
		if cr.dot(na + nb + nc) > 0.0:
			v.append(a); v.append(c); v.append(b)
			n.append(na); n.append(nc); n.append(nb)
			uv.append(ua); uv.append(uc); uv.append(ub)
		else:
			v.append(a); v.append(b); v.append(c)
			n.append(na); n.append(nb); n.append(nc)
			uv.append(ua); uv.append(ub); uv.append(uc)

	func quad(a: Vector3, b: Vector3, c: Vector3, d: Vector3, na: Vector3, nb: Vector3,
			nc: Vector3, nd: Vector3, ua: Vector2, ub: Vector2, uc: Vector2, ud: Vector2) -> void:
		tri(a, b, c, na, nb, nc, ua, ub, uc)
		tri(a, c, d, na, nc, nd, ua, uc, ud)

	func flat_quad(a: Vector3, b: Vector3, c: Vector3, d: Vector3, nrm: Vector3, uv_scale: float = 1.0) -> void:
		var ua := _planar_uv(a, nrm) * uv_scale
		var ub := _planar_uv(b, nrm) * uv_scale
		var uc := _planar_uv(c, nrm) * uv_scale
		var ud := _planar_uv(d, nrm) * uv_scale
		quad(a, b, c, d, nrm, nrm, nrm, nrm, ua, ub, uc, ud)

	func _planar_uv(p: Vector3, nrm: Vector3) -> Vector2:
		if absf(nrm.y) > 0.7:
			return Vector2(p.x, p.z)
		if absf(nrm.x) > 0.7:
			return Vector2(p.z, p.y)
		return Vector2(p.x, p.y)


# ------------------------------------------------------------------ SDF

## Signed distance from a 2D point (first quadrant) to the inset octagon.
static func octagon_sdf(ax: float, az: float) -> float:
	var s1 := ax - X1
	var s3 := az - Z1
	var s2 := (ax + az - KP) / SQ2
	var m := maxf(s1, maxf(s2, s3))
	if m <= 0.0:
		return m
	var d := Vector2(ax - X1, az - clampf(az, 0.0, ZA)).length()
	d = minf(d, Vector2(ax - clampf(ax, 0.0, XB), az - Z1).length())
	var ab := Vector2(XB - X1, Z1 - ZA)
	var ap := Vector2(ax - X1, az - ZA)
	var t := clampf(ap.dot(ab) / ab.length_squared(), 0.0, 1.0)
	return minf(d, (ap - ab * t).length())


## Distance from p to the arena shell, positive inside the playable volume.
## Goals are not carved out, so this never over-estimates free space.
static func sdf(p: Vector3) -> float:
	var d2 := octagon_sdf(absf(p.x), absf(p.z))
	var dy := absf(p.y - YC) - YH
	var ox := maxf(d2, 0.0)
	var oy := maxf(dy, 0.0)
	return R - (sqrt(ox * ox + oy * oy) + minf(maxf(d2, dy), 0.0))


## Approximate inward surface normal of the shell at p (finite differences).
static func sdf_normal(p: Vector3) -> Vector3:
	var e := 0.05
	var nx := sdf(p + Vector3(e, 0, 0)) - sdf(p - Vector3(e, 0, 0))
	var ny := sdf(p + Vector3(0, e, 0)) - sdf(p - Vector3(0, e, 0))
	var nz := sdf(p + Vector3(0, 0, e)) - sdf(p - Vector3(0, 0, e))
	var g := Vector3(nx, ny, nz)
	if g.length_squared() < 1e-12:
		return Vector3.UP
	return g.normalized()


static func is_in_goal_mouth(p: Vector3, margin: float = 0.0) -> bool:
	return absf(p.x) < Phys.GOAL_HALF_W + margin and p.y < Phys.GOAL_H + margin


# ------------------------------------------------------------------ Mesh

static func octagon_vertices() -> PackedVector2Array:
	return PackedVector2Array([
		Vector2(X1, -ZA), Vector2(X1, ZA), Vector2(XB, Z1), Vector2(-XB, Z1),
		Vector2(-X1, ZA), Vector2(-X1, -ZA), Vector2(-XB, -Z1), Vector2(XB, -Z1)])


static func _edge_normal(a: Vector2, b: Vector2) -> Vector2:
	var d := (b - a).normalized()
	return Vector2(d.y, -d.x)


## Profile points [h, y, nh, ny, kind]: h = outward offset from the inset
## octagon, (nh, ny) the inward normal, kind 0 = ramp, 1 = wall, 2 = top.
static func _profile(y_start: float) -> Array:
	var pts: Array = []
	if y_start <= 0.0:
		for i in range(N_BOTTOM + 1):
			var th := float(i) / N_BOTTOM * PI * 0.5
			pts.append([R * sin(th), R - R * cos(th), -sin(th), cos(th), 0])
	else:
		pts.append([R, y_start, -1.0, 0.0, 1])
	pts.append([R, Phys.HEIGHT - R, -1.0, 0.0, 1])
	for i in range(1, N_TOP + 1):
		var ph := float(i) / N_TOP * PI * 0.5
		pts.append([R * cos(ph), Phys.HEIGHT - R + R * sin(ph), -cos(ph), -sin(ph), 2])
	return pts


static func _sweep(surfs: Dictionary, samples: Array, prof: Array) -> void:
	# samples: [base: Vector2, n2: Vector2, perim: float]
	for si in range(samples.size() - 1):
		var s0: Array = samples[si]
		var s1: Array = samples[si + 1]
		var b0: Vector2 = s0[0]
		var b1: Vector2 = s1[0]
		var m0: Vector2 = s0[1]
		var m1: Vector2 = s1[1]
		var u0: float = s0[2]
		var u1: float = s1[2]
		for j in range(prof.size() - 1):
			var p0: Array = prof[j]
			var p1: Array = prof[j + 1]
			var kind: int = p1[4]
			if kind == 1 and int(p0[4]) == 0:
				kind = 1
			var key := "ramp"
			if kind == 1:
				key = "wall"
			elif kind == 2:
				key = "top"
			var surf: Surf = surfs[key]
			var a := Vector3(b0.x + m0.x * p0[0], p0[1], b0.y + m0.y * p0[0])
			var b := Vector3(b1.x + m1.x * p0[0], p0[1], b1.y + m1.y * p0[0])
			var c := Vector3(b1.x + m1.x * p1[0], p1[1], b1.y + m1.y * p1[0])
			var d := Vector3(b0.x + m0.x * p1[0], p1[1], b0.y + m0.y * p1[0])
			var na := Vector3(m0.x * p0[2], p0[3], m0.y * p0[2])
			var nb := Vector3(m1.x * p0[2], p0[3], m1.y * p0[2])
			var nc := Vector3(m1.x * p1[2], p1[3], m1.y * p1[2])
			var nd := Vector3(m0.x * p1[2], p1[3], m0.y * p1[2])
			# v = arc-length-ish coordinate up the profile
			var v0: float = float(p0[1])
			var v1: float = float(p1[1])
			surf.quad(a, b, c, d, na, nb, nc, nd,
				Vector2(u0, v0), Vector2(u1, v0), Vector2(u1, v1), Vector2(u0, v1))


## Builds all arena surfaces. Returns { name: Surf } with keys
## floor, ramp, wall, top, ceiling, goal.
static func build() -> Dictionary:
	var surfs := {
		"floor": Surf.new(), "ramp": Surf.new(), "wall": Surf.new(),
		"top": Surf.new(), "ceiling": Surf.new(), "goal": Surf.new(),
	}
	var oct := octagon_vertices()
	var normals: Array = []
	for i in range(8):
		normals.append(_edge_normal(oct[i], oct[(i + 1) % 8]))

	var full := _profile(0.0)
	var above_goal := _profile(Phys.GOAL_H)
	var g := Phys.GOAL_HALF_W
	var perim := 0.0

	for i in range(8):
		var v: Vector2 = oct[i]
		var n_prev: Vector2 = normals[(i + 7) % 8]
		var n_next: Vector2 = normals[i]
		# Rounded vertical corner at vertex i
		var a0 := atan2(n_prev.y, n_prev.x)
		var a1 := atan2(n_next.y, n_next.x)
		var da := wrapf(a1 - a0, -PI, PI)
		var corner: Array = []
		for k in range(N_CORNER + 1):
			var ang := a0 + da * float(k) / N_CORNER
			corner.append([v, Vector2(cos(ang), sin(ang)), perim + absf(da) * R * float(k) / N_CORNER])
		perim += absf(da) * R
		_sweep(surfs, corner, full)

		# Straight edge from vertex i to i+1
		var w: Vector2 = oct[(i + 1) % 8]
		var len := v.distance_to(w)
		if absf(n_next.x) < 0.01:
			# End wall: split around the goal mouth
			var sgn := signf(v.x - w.x)  # +1 when walking from +x to -x
			var xa := sgn * g
			var pa := Vector2(xa, v.y)
			var pb := Vector2(-xa, v.y)
			var la := v.distance_to(pa)
			_sweep(surfs, [[v, n_next, perim], [pa, n_next, perim + la]], full)
			_sweep(surfs, [[pa, n_next, perim + la], [pb, n_next, perim + la + 2.0 * g]], above_goal)
			_sweep(surfs, [[pb, n_next, perim + la + 2.0 * g], [w, n_next, perim + len]], full)
		else:
			_sweep(surfs, [[v, n_next, perim], [w, n_next, perim + len]], full)
		perim += len

	# Floor and ceiling (convex fans)
	var floor_s: Surf = surfs["floor"]
	var ceil_s: Surf = surfs["ceiling"]
	for i in range(8):
		var p: Vector2 = oct[i]
		var q: Vector2 = oct[(i + 1) % 8]
		floor_s.tri(Vector3.ZERO, Vector3(p.x, 0, p.y), Vector3(q.x, 0, q.y),
			Vector3.UP, Vector3.UP, Vector3.UP, Vector2.ZERO, p, q)
		var hc := Phys.HEIGHT
		ceil_s.tri(Vector3(0, hc, 0), Vector3(p.x, hc, p.y), Vector3(q.x, hc, q.y),
			Vector3.DOWN, Vector3.DOWN, Vector3.DOWN, Vector2.ZERO, p, q)

	# Goals
	var L := Phys.HALF_L
	var D := Phys.GOAL_DEPTH
	var h := Phys.GOAL_H
	var goal_s: Surf = surfs["goal"]
	var ramp_s: Surf = surfs["ramp"]
	for sg: float in [1.0, -1.0]:
		var zf := sg * Z1
		var zl := sg * L
		var zb := sg * (L + D)
		# Floor of goal mouth and goal interior
		floor_s.flat_quad(Vector3(-g, 0, zf), Vector3(g, 0, zf), Vector3(g, 0, zb), Vector3(-g, 0, zb), Vector3.UP)
		# Side walls (inner faces) of the goal
		for sx: float in [1.0, -1.0]:
			var x: float = sx * g
			var nrm := Vector3(-sx, 0, 0)
			goal_s.flat_quad(Vector3(x, 0, zl), Vector3(x, 0, zb), Vector3(x, h, zb), Vector3(x, h, zl), nrm)
			# Cut face through the quarter-pipe next to the post
			var corner := Vector3(x, 0, zl)
			for k in range(N_BOTTOM):
				var t0 := float(k) / N_BOTTOM * PI * 0.5
				var t1 := float(k + 1) / N_BOTTOM * PI * 0.5
				var q0 := Vector3(x, R - R * cos(t0), zf + sg * R * sin(t0))
				var q1 := Vector3(x, R - R * cos(t1), zf + sg * R * sin(t1))
				ramp_s.tri(corner, q0, q1, nrm, nrm, nrm,
					Vector2(corner.z, corner.y), Vector2(q0.z, q0.y), Vector2(q1.z, q1.y))
		# Back wall and roof
		goal_s.flat_quad(Vector3(-g, 0, zb), Vector3(g, 0, zb), Vector3(g, h, zb), Vector3(-g, h, zb), Vector3(0, 0, -sg))
		goal_s.flat_quad(Vector3(-g, h, zl), Vector3(g, h, zl), Vector3(g, h, zb), Vector3(-g, h, zb), Vector3.DOWN)
	return surfs


static func collision_faces(surfs: Dictionary) -> PackedVector3Array:
	var faces := PackedVector3Array()
	for key in surfs:
		var s: Surf = surfs[key]
		faces.append_array(s.v)
	return faces


static func to_array_mesh(s: Surf) -> ArrayMesh:
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = s.v
	arrays[Mesh.ARRAY_NORMAL] = s.n
	arrays[Mesh.ARRAY_TEX_UV] = s.uv
	var m := ArrayMesh.new()
	if s.v.size() > 0:
		m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return m
