class_name CarModel
extends Node3D
## Procedural car body: a loft of smooth cross-sections driven by side-profile,
## plan-view and greenhouse curves, with wheel arches, glass, pillars, light
## clusters, grille, mirrors, spoiler and detailed wheels. Supports crash damage.

enum { M_PAINT, M_GLASS, M_TRIM, M_HEAD, M_TAIL, M_GRILLE, M_CHROME }

# L, W, H: size; wb: wheelbase; wr: wheel radius; cl: ground clearance
# profile: nose, hood_f, hood_r, roof, deck, tail heights; u_ws, u_rf, u_rr, u_rw positions
const STYLES := {
	"supercar": {"L": 4.55, "W": 1.98, "H": 1.15, "wb": 2.68, "wr": 0.345, "tw": 0.29, "cl": 0.11,
		"nose": 0.40, "hood_f": 0.66, "hood_r": 0.90, "roof": 1.15, "deck": 1.0, "tail": 0.94,
		"u_ws": 0.29, "u_rf": 0.43, "u_rr": 0.56, "u_rw": 0.83, "roof_w": 0.70, "doors": 2,
		"spoiler": 0.22, "front_off": -0.02, "flat_n": [3.6, 6.0], "intake": true},
	"hyper": {"L": 4.72, "W": 2.04, "H": 1.12, "wb": 2.75, "wr": 0.35, "tw": 0.31, "cl": 0.1,
		"nose": 0.36, "hood_f": 0.6, "hood_r": 0.86, "roof": 1.12, "deck": 1.02, "tail": 0.98,
		"u_ws": 0.28, "u_rf": 0.42, "u_rr": 0.55, "u_rw": 0.86, "roof_w": 0.66, "doors": 2,
		"spoiler": 0.32, "front_off": -0.03, "flat_n": [3.2, 7.0], "intake": true},
	"coupe": {"L": 4.52, "W": 1.9, "H": 1.3, "wb": 2.72, "wr": 0.335, "tw": 0.27, "cl": 0.12,
		"nose": 0.5, "hood_f": 0.76, "hood_r": 0.97, "roof": 1.3, "deck": 1.02, "tail": 0.98,
		"u_ws": 0.35, "u_rf": 0.48, "u_rr": 0.63, "u_rw": 0.85, "roof_w": 0.74, "doors": 2,
		"spoiler": 0.08, "front_off": 0.0, "flat_n": [4.0, 6.0], "intake": false},
	"muscle": {"L": 4.84, "W": 1.96, "H": 1.34, "wb": 2.86, "wr": 0.35, "tw": 0.28, "cl": 0.13,
		"nose": 0.8, "hood_f": 0.9, "hood_r": 1.0, "roof": 1.34, "deck": 1.05, "tail": 1.0,
		"u_ws": 0.42, "u_rf": 0.53, "u_rr": 0.67, "u_rw": 0.84, "roof_w": 0.76, "doors": 2,
		"spoiler": 0.06, "front_off": 0.02, "flat_n": [7.0, 8.0], "intake": false, "stripe": true},
	"hatch": {"L": 4.3, "W": 1.82, "H": 1.46, "wb": 2.62, "wr": 0.33, "tw": 0.25, "cl": 0.14,
		"nose": 0.6, "hood_f": 0.8, "hood_r": 1.0, "roof": 1.46, "deck": 1.18, "tail": 1.06,
		"u_ws": 0.27, "u_rf": 0.41, "u_rr": 0.86, "u_rw": 0.96, "roof_w": 0.78, "doors": 4,
		"spoiler": 0.04, "front_off": 0.03, "flat_n": [4.5, 8.0], "intake": true},
	"sedan": {"L": 4.95, "W": 1.9, "H": 1.44, "wb": 2.96, "wr": 0.345, "tw": 0.26, "cl": 0.13,
		"nose": 0.62, "hood_f": 0.82, "hood_r": 1.0, "roof": 1.44, "deck": 1.08, "tail": 1.04,
		"u_ws": 0.3, "u_rf": 0.43, "u_rr": 0.7, "u_rw": 0.83, "roof_w": 0.78, "doors": 4,
		"spoiler": 0.0, "front_off": 0.0, "flat_n": [4.5, 7.0], "intake": false},
	"police": {"L": 4.98, "W": 1.92, "H": 1.46, "wb": 2.96, "wr": 0.345, "tw": 0.26, "cl": 0.14,
		"nose": 0.64, "hood_f": 0.84, "hood_r": 1.01, "roof": 1.46, "deck": 1.1, "tail": 1.05,
		"u_ws": 0.3, "u_rf": 0.43, "u_rr": 0.7, "u_rw": 0.83, "roof_w": 0.78, "doors": 4,
		"spoiler": 0.0, "front_off": 0.0, "flat_n": [4.5, 7.0], "intake": false, "lightbar": true},
	"sedan_t": {"L": 4.75, "W": 1.82, "H": 1.48, "wb": 2.8, "wr": 0.32, "tw": 0.22, "cl": 0.15,
		"nose": 0.64, "hood_f": 0.84, "hood_r": 1.02, "roof": 1.48, "deck": 1.1, "tail": 1.06,
		"u_ws": 0.29, "u_rf": 0.42, "u_rr": 0.71, "u_rw": 0.84, "roof_w": 0.8, "doors": 4,
		"spoiler": 0.0, "front_off": 0.02, "flat_n": [4.0, 6.0], "intake": false},
	"hatch_t": {"L": 4.05, "W": 1.76, "H": 1.5, "wb": 2.55, "wr": 0.31, "tw": 0.2, "cl": 0.15,
		"nose": 0.62, "hood_f": 0.82, "hood_r": 1.02, "roof": 1.5, "deck": 1.2, "tail": 1.08,
		"u_ws": 0.25, "u_rf": 0.4, "u_rr": 0.87, "u_rw": 0.96, "roof_w": 0.8, "doors": 4,
		"spoiler": 0.0, "front_off": 0.03, "flat_n": [4.0, 8.0], "intake": false},
	"suv": {"L": 4.82, "W": 1.98, "H": 1.76, "wb": 2.9, "wr": 0.38, "tw": 0.27, "cl": 0.21,
		"nose": 0.86, "hood_f": 1.05, "hood_r": 1.16, "roof": 1.76, "deck": 1.5, "tail": 1.22,
		"u_ws": 0.27, "u_rf": 0.38, "u_rr": 0.89, "u_rw": 0.97, "roof_w": 0.84, "doors": 4,
		"spoiler": 0.0, "front_off": 0.03, "flat_n": [6.0, 10.0], "intake": false, "rails": true},
	"van": {"L": 5.25, "W": 2.02, "H": 2.2, "wb": 3.25, "wr": 0.36, "tw": 0.24, "cl": 0.18,
		"nose": 0.8, "hood_f": 1.0, "hood_r": 1.22, "roof": 2.2, "deck": 2.15, "tail": 1.6,
		"u_ws": 0.12, "u_rf": 0.22, "u_rr": 0.97, "u_rw": 0.99, "roof_w": 0.9, "doors": 4,
		"spoiler": 0.0, "front_off": 0.18, "flat_n": [6.0, 12.0], "intake": false, "no_rear_glass": true},
	"pickup": {"L": 5.35, "W": 1.98, "H": 1.82, "wb": 3.3, "wr": 0.38, "tw": 0.26, "cl": 0.22,
		"nose": 0.95, "hood_f": 1.12, "hood_r": 1.22, "roof": 1.82, "deck": 1.18, "tail": 1.15,
		"u_ws": 0.29, "u_rf": 0.38, "u_rr": 0.54, "u_rw": 0.58, "roof_w": 0.84, "doors": 4,
		"spoiler": 0.0, "front_off": 0.0, "flat_n": [7.0, 12.0], "intake": false},
	"truck": {"L": 7.4, "W": 2.35, "H": 3.25, "wb": 4.4, "wr": 0.48, "tw": 0.3, "cl": 0.28,
		"nose": 1.0, "hood_f": 1.25, "hood_r": 1.4, "roof": 2.6, "deck": 3.25, "tail": 3.25,
		"u_ws": 0.04, "u_rf": 0.11, "u_rr": 0.23, "u_rw": 0.25, "roof_w": 0.9, "doors": 2,
		"spoiler": 0.0, "front_off": 1.1, "flat_n": [8.0, 14.0], "intake": false, "box": true},
}

const RING_V := [0.0, 0.03, 0.06, 0.12, 0.2, 0.25, 0.27, 0.32, 0.38, 0.43, 0.47, 0.5]
const STATIONS := 56

var style := {}
var style_name := ""
var length := 4.5
var width := 1.9
var height := 1.3
var wheelbase := 2.7
var wheel_radius := 0.34
var track := 1.6
var wheel_rest: Array[Vector3] = []   # FL, FR, RL, RR (local)
var wheel_pivots: Array[Node3D] = []
var wheel_spins: Array[Node3D] = []
var hull_points := PackedVector3Array()
var body_mi: MeshInstance3D
var body_mesh: ArrayMesh
var mats := []
var surf := []        # per material: {v: PackedVector3Array, n, uv, i}
var orig := []        # original vertex positions per material
var paint_mat: ShaderMaterial
var head_mat: StandardMaterial3D
var tail_mat: StandardMaterial3D
var lightbar_red: StandardMaterial3D
var lightbar_blue: StandardMaterial3D
var damage := 0.0
var _rng := RandomNumberGenerator.new()


func build(sname: String, color: Color, seed := 1) -> void:
	style_name = sname
	style = STYLES.get(sname, STYLES["sedan"])
	_rng.seed = seed
	length = style.L
	width = style.W
	height = style.H
	wheelbase = style.wb
	wheel_radius = style.wr
	track = width - style.tw - 0.08
	_make_materials(color)
	_build_body()
	_build_details()
	_build_wheels()


# --------------------------------------------------------------------------- profiles
func _cr(keys: Array, u: float) -> float:
	# non-uniform Catmull-Rom (cubic Hermite) through [u, y] keys
	var n := keys.size()
	if u <= keys[0][0]:
		return keys[0][1]
	if u >= keys[n - 1][0]:
		return keys[n - 1][1]
	var k := 0
	while k < n - 2 and u > keys[k + 1][0]:
		k += 1
	var u0: float = keys[k][0]
	var u1: float = keys[k + 1][0]
	var y0: float = keys[k][1]
	var y1: float = keys[k + 1][1]
	var m0 := (y1 - y0) / (u1 - u0)
	var m1 := m0
	if k > 0:
		m0 = (y1 - float(keys[k - 1][1])) / (u1 - float(keys[k - 1][0]))
	if k < n - 2:
		m1 = (float(keys[k + 2][1]) - y0) / (float(keys[k + 2][0]) - u0)
	var t := (u - u0) / (u1 - u0)
	var h := u1 - u0
	var t2 := t * t
	var t3 := t2 * t
	return (2 * t3 - 3 * t2 + 1) * y0 + (t3 - 2 * t2 + t) * h * m0 + (-2 * t3 + 3 * t2) * y1 + (t3 - t2) * h * m1


func _top_keys() -> Array:
	var s := style
	var keys := [[0.0, s.nose], [0.025, lerpf(s.nose, s.hood_f, 0.75)], [0.07, s.hood_f]]
	if s.get("box", false):
		keys = [[0.0, s.nose], [0.02, s.hood_f], [s.u_ws, s.hood_r], [s.u_rf, s.roof], [s.u_rr, s.roof],
			[s.u_rr + 0.008, s.deck - 0.05], [s.u_rw, s.deck], [0.995, s.tail], [1.0, s.tail - 0.1]]
		return keys
	keys.append([s.u_ws, s.hood_r])
	keys.append([s.u_rf, s.roof])
	keys.append([lerpf(s.u_rf, s.u_rr, 0.5), s.roof + 0.012])
	keys.append([s.u_rr, s.roof - 0.01])
	keys.append([s.u_rw, s.deck])
	keys.append([0.955, s.tail + 0.01])
	keys.append([1.0, s.tail - 0.08])
	return keys


func _belt(u: float, ytop: float) -> float:
	var s := style
	var keys := [[0.0, s.nose - 0.02], [0.07, s.hood_f - 0.03], [s.u_ws, s.hood_r - 0.02],
		[s.u_rw, s.deck - 0.02 + (0.03 if s.u_rw < 0.9 else 0.0)], [1.0, s.tail - 0.05]]
	if s.get("box", false):
		keys = [[0.0, s.nose - 0.02], [s.u_ws, s.hood_r - 0.02], [s.u_rr, s.hood_r + 0.1], [s.u_rw, s.deck - 0.05], [1.0, s.tail - 0.05]]
	return minf(_cr(keys, u), ytop - 0.004)


func _bottom(u: float) -> float:
	var c: float = style.cl
	return _cr([[0.0, c + 0.24], [0.05, c + 0.05], [0.5, c], [0.93, c + 0.05], [1.0, c + 0.26]], u)


func _plan(u: float) -> float:
	var n: Array = style.flat_n
	var t := (u - 0.5) / 0.5
	var nn: float = n[0] if t < 0.0 else n[1]
	return pow(maxf(1.0 - pow(absf(t), nn), 0.0), 1.0 / nn)


func _in_cabin(u: float) -> bool:
	return u > style.u_ws and u < style.u_rw


# --------------------------------------------------------------------------- body
func _make_materials(color: Color) -> void:
	paint_mat = ShaderMaterial.new()
	paint_mat.shader = load("res://shaders/car_paint.gdshader")
	paint_mat.set_shader_parameter("paint", Color(color.r, color.g, color.b))
	var s := style
	var doors: int = s.doors
	var seams := Vector4(s.u_ws + 0.01, (s.u_rf + s.u_rr) * 0.5 + 0.02 if doors == 4 else s.u_rr + 0.03,
		s.u_rr + 0.03 if doors == 4 else -1.0, -1.0)
	paint_mat.set_shader_parameter("seams_u", seams)
	if s.get("lightbar", false):
		paint_mat.set_shader_parameter("panel", Vector4(s.u_rf - 0.03, s.u_rr + 0.03, 0.06, 0.235))
		paint_mat.set_shader_parameter("panel_color", Color(0.93, 0.94, 0.96))
	if s.get("stripe", false):
		paint_mat.set_shader_parameter("stripe", Vector2(0.035, 1.0))
		paint_mat.set_shader_parameter("stripe_color", Color(0.95, 0.95, 0.95) if color.get_luminance() < 0.6 else Color(0.05, 0.05, 0.05))
	var glass := StandardMaterial3D.new()
	glass.albedo_color = Color(0.03, 0.04, 0.05)
	glass.metallic = 0.4
	glass.roughness = 0.03
	glass.metallic_specular = 0.9
	var trim := StandardMaterial3D.new()
	trim.albedo_color = Color(0.035, 0.035, 0.04)
	trim.roughness = 0.55
	head_mat = StandardMaterial3D.new()
	head_mat.albedo_color = Color(0.85, 0.88, 0.9)
	head_mat.metallic = 0.6
	head_mat.roughness = 0.1
	head_mat.emission_enabled = true
	head_mat.emission = Color(1.0, 0.97, 0.9)
	head_mat.emission_energy_multiplier = 0.6
	tail_mat = StandardMaterial3D.new()
	tail_mat.albedo_color = Color(0.45, 0.02, 0.02)
	tail_mat.roughness = 0.15
	tail_mat.emission_enabled = true
	tail_mat.emission = Color(1.0, 0.05, 0.02)
	tail_mat.emission_energy_multiplier = 0.6
	var grille := StandardMaterial3D.new()
	grille.albedo_color = Color(0.02, 0.02, 0.025)
	grille.roughness = 0.4
	grille.metallic = 0.5
	var chrome := StandardMaterial3D.new()
	chrome.albedo_color = Color(0.8, 0.8, 0.82)
	chrome.metallic = 1.0
	chrome.roughness = 0.15
	mats = [paint_mat, glass, trim, head_mat, tail_mat, grille, chrome]


func _classify(u: float, q: int, xfrac: float, raised: bool) -> int:
	var s := style
	if raised:
		return M_TRIM
	if q <= 1:
		return M_TRIM
	if u < 0.05 and (q == 4 or q == 5) and xfrac > 0.42:
		return M_HEAD
	if u < 0.04 and (q == 2 or q == 3) and xfrac < 0.68:
		return M_GRILLE
	if s.get("box", false):
		if u > 0.985 and q == 2 and xfrac > 0.6:
			return M_TAIL
	elif u > 0.962 and (q == 4 or q == 5) and xfrac > 0.3:
		return M_TAIL
	if u > 0.965 and q == 2:
		return M_TRIM
	var u_ws: float = s.u_ws
	var u_rf: float = s.u_rf
	var u_rr: float = s.u_rr
	var u_rw: float = s.u_rw
	if s.get("box", false) and u > u_rr:
		return M_PAINT
	# windscreen
	if u > u_ws + 0.008 and u < u_rf - 0.004 and q >= 8:
		return M_GLASS
	# rear window
	if not s.get("no_rear_glass", false) and u > u_rr + 0.008 and u < u_rw - 0.006 and q >= 8:
		return M_GLASS
	# side glass
	if q >= 6 and q <= 8 and u > u_rf + 0.02 and u < u_rr - 0.01:
		if s.doors == 4:
			var ub := (u_rf + u_rr) * 0.5 + 0.02
			if absf(u - ub) < 0.012:
				return M_TRIM
		return M_GLASS
	if q >= 6 and q <= 8 and _in_cabin(u):
		return M_TRIM if (u > u_ws and u < u_rf + 0.02) else M_PAINT
	return M_PAINT


func _build_body() -> void:
	var s := style
	var L := length
	var hw_full := width * 0.5
	var top_keys := _top_keys()
	var front_off: float = s.get("front_off", 0.0)
	# wheel centres (local): front axle at -wb/2, rear at +wb/2, shifted by front_off
	var zf := -wheelbase * 0.5 + front_off * 0.0
	var zr := wheelbase * 0.5
	var shift := front_off   # moves the body relative to the axles (cab-forward vans etc)
	wheel_rest = [Vector3(-track * 0.5, wheel_radius, zf), Vector3(track * 0.5, wheel_radius, zf),
		Vector3(-track * 0.5, wheel_radius, zr), Vector3(track * 0.5, wheel_radius, zr)]
	var arch_r := wheel_radius + 0.055
	var rings := []
	var raised_rows := []
	for si in STATIONS + 1:
		var t := float(si) / STATIONS
		# denser stations at the ends
		var u := 0.5 - 0.5 * cos(t * PI) * 0.35 + (t - 0.5) * 0.65
		u = clampf(u, 0.0, 1.0)
		var z := -L * 0.5 + u * L + shift
		var ytop := _cr(top_keys, u)
		var ybelt := _belt(u, ytop)
		var ybot := _bottom(u)
		var pl := _plan(u)
		var hwl := hw_full * pl
		var hwb := hwl * 0.975
		var cab := smoothstep(0.02, 0.16, ytop - ybelt)
		var hwt := lerpf(hwb * 0.86, hwb * float(s.roof_w), cab)
		var crown := lerpf(0.035, 0.02, cab) * pl
		var pts := [
			Vector2(0.0, ybot),
			Vector2(hwl * 0.72, ybot),
			Vector2(hwl * 0.95, ybot + 0.05),
			Vector2(hwl * 1.0, ybot + (ybelt - ybot) * 0.32),
			Vector2(hwl * 1.0, ybot + (ybelt - ybot) * 0.7),
			Vector2(hwb, ybelt - 0.035),
			Vector2(hwb * 0.965, ybelt),
			Vector2(lerpf(hwb * 0.95, hwt, 0.35), lerpf(ybelt, ytop, 0.38)),
			Vector2(lerpf(hwb * 0.95, hwt, 0.78), lerpf(ybelt, ytop, 0.8)),
			Vector2(hwt, ytop - 0.012),
			Vector2(hwt * 0.55, ytop + crown * 0.8),
			Vector2(0.0, ytop + crown),
		]
		# wheel arches: lift lower points into an arch around each axle
		var raised := []
		for i in pts.size():
			var p: Vector2 = pts[i]
			var flag := false
			if i <= 5:
				for wz in [zf, zr]:
					var dz: float = z - wz
					if absf(dz) < arch_r:
						var ay: float = wheel_radius + sqrt(arch_r * arch_r - dz * dz)
						if p.y < ay:
							p.y = ay
							flag = true
			pts[i] = p
			raised.append(flag)
		rings.append([u, z, pts])
		raised_rows.append(raised)
	# build quads per material, both sides
	var accs := []
	for m in mats.size():
		accs.append(MeshAcc.new())
	for si in STATIONS:
		var A: Array = rings[si]
		var B: Array = rings[si + 1]
		var um: float = (A[0] + B[0]) * 0.5
		var pa: Array = A[2]
		var pb: Array = B[2]
		for q in 11:
			var raised: bool = raised_rows[si][q] and raised_rows[si][q + 1] and raised_rows[si + 1][q] and raised_rows[si + 1][q + 1]
			var xm: float = (pa[q].x + pa[q + 1].x) * 0.5
			var hwm: float = maxf(hw_full * _plan(um), 0.01)
			var mi := _classify(um, q, xm / hwm, raised and q <= 5)
			var acc: MeshAcc = accs[mi]
			for side: float in [1.0, -1.0]:
				var v0 := Vector3(pa[q].x * side, pa[q].y, A[1])
				var v1 := Vector3(pa[q + 1].x * side, pa[q + 1].y, A[1])
				var v2 := Vector3(pb[q + 1].x * side, pb[q + 1].y, B[1])
				var v3 := Vector3(pb[q].x * side, pb[q].y, B[1])
				var vv0: float = RING_V[q] if side > 0 else 1.0 - RING_V[q]
				var vv1: float = RING_V[q + 1] if side > 0 else 1.0 - RING_V[q + 1]
				var centre := Vector3(0, (pa[q].y + pb[q].y) * 0.5 * 0.0 + 0.55 * height, (A[1] + B[1]) * 0.5)
				var face := ((v0 + v1 + v2 + v3) * 0.25 - centre)
				if face.length() < 0.001:
					face = Vector3(side, 0, 0)
				var i0 := acc.v(v0, Vector3.ZERO, Vector2(A[0], vv0))
				var i1 := acc.v(v1, Vector3.ZERO, Vector2(A[0], vv1))
				var i2 := acc.v(v2, Vector3.ZERO, Vector2(B[0], vv1))
				var i3 := acc.v(v3, Vector3.ZERO, Vector2(B[0], vv0))
				acc.quad(i0, i1, i2, i3, face)
		if si % 4 == 0:
			for q in [0, 2, 4, 6, 9, 11]:
				hull_points.append(Vector3(pa[q].x, pa[q].y, A[1]))
				hull_points.append(Vector3(-pa[q].x, pa[q].y, A[1]))
	var last: Array = rings[STATIONS][2]
	for q in [0, 2, 4, 6, 9, 11]:
		hull_points.append(Vector3(last[q].x, last[q].y, rings[STATIONS][1]))
	surf.clear()
	orig.clear()
	for m in mats.size():
		var acc: MeshAcc = accs[m]
		_weld_normals(acc)
		surf.append(acc)
		orig.append(acc.verts.duplicate())
	_commit_body()


## smooth normals across coincident vertices (same position) inside one surface
func _weld_normals(acc: MeshAcc) -> void:
	var nsum := {}
	for t in range(0, acc.idx.size(), 3):
		var a := acc.verts[acc.idx[t]]
		var b := acc.verts[acc.idx[t + 1]]
		var c := acc.verts[acc.idx[t + 2]]
		var n := (b - a).cross(c - a)
		# front faces follow Godot's winding: flip to outward
		n = -n
		for k in 3:
			var key := (acc.verts[acc.idx[t + k]] * 1000.0).round()
			nsum[key] = nsum.get(key, Vector3.ZERO) + n
	for i in acc.verts.size():
		var key := (acc.verts[i] * 1000.0).round()
		var n: Vector3 = nsum.get(key, Vector3.UP)
		acc.norms[i] = n.normalized() if n.length() > 1e-6 else Vector3.UP


func _commit_body() -> void:
	if body_mesh == null:
		body_mesh = ArrayMesh.new()
	else:
		body_mesh.clear_surfaces()
	for m in surf.size():
		var acc: MeshAcc = surf[m]
		if acc.is_empty():
			continue
		acc.to_mesh(mats[m], body_mesh)
	if body_mi == null:
		body_mi = MeshInstance3D.new()
		body_mi.name = "Body"
		add_child(body_mi)
	body_mi.mesh = body_mesh


# --------------------------------------------------------------------------- details
func _build_details() -> void:
	var s := style
	var d := MeshAcc.new()      # trim/black details
	var p := MeshAcc.new()      # painted details
	var c := MeshAcc.new()      # chrome
	var g := MeshAcc.new()      # glass-like
	var hw := width * 0.5
	var shift: float = s.get("front_off", 0.0)
	var z_of := func(u: float) -> float: return -length * 0.5 + u * length + shift
	# mirrors
	var mu: float = float(s.u_rf) + 0.015
	var my := _belt(mu, _cr(_top_keys(), mu)) + 0.08
	for side: float in [-1.0, 1.0]:
		var mz: float = z_of.call(mu)
		p.box(Transform3D(Basis(), Vector3(side * (hw * _plan(mu) + 0.08), my, mz)), Vector3(0.16, 0.12, 0.22))
		d.box(Transform3D(Basis(), Vector3(side * (hw * _plan(mu) + 0.02), my - 0.04, mz + 0.03)), Vector3(0.1, 0.05, 0.08))
	# spoiler
	var sp: float = s.spoiler
	if sp > 0.0:
		var su := 0.95
		var sz: float = z_of.call(su)
		var sy := _cr(_top_keys(), su) + sp
		for side: float in [-0.32, 0.32]:
			d.box(Transform3D(Basis(), Vector3(side * width, sy - sp * 0.5, sz)), Vector3(0.05, sp, 0.18))
		var wing := Transform3D(Basis(Vector3.RIGHT, -0.12), Vector3(0, sy, sz + 0.02))
		(d if sp > 0.15 else p).box(wing, Vector3(width * 0.88, 0.035, 0.32))
		if sp > 0.15:
			for side: float in [-1.0, 1.0]:
				d.box(Transform3D(Basis(), Vector3(side * width * 0.44, sy + 0.02, sz)), Vector3(0.02, 0.12, 0.36))
	# exhausts
	var ez: float = z_of.call(0.995)
	var ey: float = _bottom(0.99) + 0.08
	var pipes := [-0.35, 0.35] if s.get("spoiler", 0.0) > 0.0 or style_name == "muscle" else [0.45]
	for ex: float in pipes:
		c.cylinder(Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(ex * hw, ey, ez)), 0.05, 0.05, -0.12, 0.08, 10, false)
	# number plates
	var plate := MeshAcc.new()
	plate.box(Transform3D(Basis(), Vector3(0, _bottom(0.0) + 0.16, z_of.call(0.0) - 0.0)), Vector3(0.5, 0.11, 0.02))
	plate.box(Transform3D(Basis(), Vector3(0, _bottom(1.0) + 0.2, z_of.call(1.0) + 0.0)), Vector3(0.5, 0.11, 0.02))
	# roof rails
	if s.get("rails", false):
		for side: float in [-1.0, 1.0]:
			d.box(Transform3D(Basis(), Vector3(side * hw * 0.62, float(s.roof) + 0.05, z_of.call((s.u_rf + s.u_rr) * 0.5))), Vector3(0.05, 0.05, (s.u_rr - s.u_rf) * length * 0.9))
	var mesh := ArrayMesh.new()
	if not d.is_empty():
		d.to_mesh(mats[M_TRIM], mesh)
	if not p.is_empty():
		p.to_mesh(mats[M_PAINT], mesh)
	if not c.is_empty():
		c.to_mesh(mats[M_CHROME], mesh)
	plate.to_mesh(Mats.std("plate", Color(0.92, 0.92, 0.88), 0.0, 0.5), mesh)
	var mi := MeshInstance3D.new()
	mi.name = "Details"
	mi.mesh = mesh
	add_child(mi)
	if s.get("lightbar", false):
		_lightbar()


func _lightbar() -> void:
	var s := style
	var u: float = (s.u_rf + s.u_rr) * 0.5 - 0.04
	var y: float = float(s.roof) + 0.06
	var z := -length * 0.5 + u * length
	lightbar_red = StandardMaterial3D.new()
	lightbar_red.albedo_color = Color(0.5, 0.0, 0.0)
	lightbar_red.emission_enabled = true
	lightbar_red.emission = Color(1.0, 0.05, 0.05)
	lightbar_red.emission_energy_multiplier = 0.2
	lightbar_blue = StandardMaterial3D.new()
	lightbar_blue.albedo_color = Color(0.0, 0.05, 0.5)
	lightbar_blue.emission_enabled = true
	lightbar_blue.emission = Color(0.1, 0.25, 1.0)
	lightbar_blue.emission_energy_multiplier = 0.2
	var base := MeshAcc.new()
	base.box(Transform3D(Basis(), Vector3(0, y, z)), Vector3(1.1, 0.06, 0.28))
	var r := MeshAcc.new()
	r.box(Transform3D(Basis(), Vector3(-0.3, y + 0.07, z)), Vector3(0.48, 0.09, 0.24))
	var b := MeshAcc.new()
	b.box(Transform3D(Basis(), Vector3(0.3, y + 0.07, z)), Vector3(0.48, 0.09, 0.24))
	var mesh := base.to_mesh(mats[M_TRIM])
	r.to_mesh(lightbar_red, mesh)
	b.to_mesh(lightbar_blue, mesh)
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	add_child(mi)


# --------------------------------------------------------------------------- wheels
static var _wheel_cache := {}


func _wheel_mesh(r: float, w: float, rim_style: int) -> ArrayMesh:
	var key := "%.3f_%.3f_%d" % [r, w, rim_style]
	if _wheel_cache.has(key):
		return _wheel_cache[key]
	var tire := MeshAcc.new()
	var rr := r * 0.68   # rim radius
	var segs := 28
	# tyre cross-section (radius, axial) going around: inner sidewall -> tread -> outer sidewall
	var prof := [Vector2(rr, -w * 0.45), Vector2(r * 0.9, -w * 0.5), Vector2(r * 0.985, -w * 0.46),
		Vector2(r, -w * 0.36), Vector2(r, w * 0.36), Vector2(r * 0.985, w * 0.46), Vector2(r * 0.9, w * 0.5), Vector2(rr, w * 0.45)]
	var rings := []
	for i in segs + 1:
		var a := TAU * i / segs
		var row := []
		for k in prof.size():
			var pr: Vector2 = prof[k]
			var pos := Vector3(pr.y, cos(a) * pr.x, sin(a) * pr.x)
			var nrm := Vector3(0, cos(a), sin(a))
			if k == 0 or k == 1:
				nrm = (nrm * 0.3 + Vector3(-1, 0, 0)).normalized()
			elif k >= 6:
				nrm = (nrm * 0.3 + Vector3(1, 0, 0)).normalized()
			row.append(tire.v(pos, nrm, Vector2(float(i) / segs * 8.0, float(k) / prof.size())))
		rings.append(row)
	for i in segs:
		for k in prof.size() - 1:
			var mid := Vector3((prof[k].y + prof[k + 1].y) * 0.5, cos(TAU * (i + 0.5) / segs), sin(TAU * (i + 0.5) / segs))
			var face := Vector3(0, mid.y, mid.z)
			if k == 0:
				face = Vector3(-1, 0, 0) + face * 0.2
			elif k == prof.size() - 2:
				face = Vector3(1, 0, 0) + face * 0.2
			tire.quad(rings[i][k], rings[i + 1][k], rings[i + 1][k + 1], rings[i][k + 1], face)
	var rim := MeshAcc.new()
	var face_x := w * 0.38
	# rim lip
	rim.cylinder(Transform3D(Basis(Vector3(0, 0, 1), PI * 0.5), Vector3.ZERO), rr, rr, -w * 0.45, w * 0.45, 24, false)
	# hub
	rim.cylinder(Transform3D(Basis(Vector3(0, 0, -1), PI * 0.5), Vector3(face_x - 0.02, 0, 0)), 0.09, 0.07, 0.0, 0.05, 12, true)
	# spokes
	var spokes := 5 + rim_style * 2
	for sidx in spokes:
		var a := TAU * sidx / spokes
		var mid := Vector3(face_x - 0.01, cos(a) * rr * 0.55, sin(a) * rr * 0.55)
		var basis := Basis(Vector3.RIGHT, a)
		rim.box(Transform3D(basis, mid), Vector3(0.035, rr * 0.92, 0.07 if rim_style == 0 else 0.045))
	var disc := MeshAcc.new()
	disc.cylinder(Transform3D(Basis(Vector3(0, 0, 1), PI * 0.5), Vector3(-0.02, 0, 0)), rr * 0.82, rr * 0.82, -0.015, 0.015, 20, true)
	var mesh := tire.to_mesh(Mats.std("tyre", Color(0.045, 0.045, 0.05), 0.0, 0.88))
	rim.to_mesh(Mats.std("rim_%d" % rim_style, Color(0.72, 0.73, 0.75) if rim_style != 1 else Color(0.12, 0.12, 0.13), 0.9, 0.22), mesh)
	disc.to_mesh(Mats.std("brake_disc", Color(0.35, 0.34, 0.33), 0.8, 0.45), mesh)
	_wheel_cache[key] = mesh
	return mesh


func _build_wheels() -> void:
	var rim_style := 0
	match style_name:
		"supercar", "hyper": rim_style = 1
		"coupe", "hatch": rim_style = 2
		_: rim_style = 0
	var mesh := _wheel_mesh(wheel_radius, float(style.tw), rim_style)
	var cal := MeshAcc.new()
	cal.box(Transform3D(Basis(), Vector3(-0.06, wheel_radius * 0.42, -0.02)), Vector3(0.06, 0.12, 0.2))
	var cal_mesh := cal.to_mesh(Mats.std("caliper", Color(0.8, 0.08, 0.05) if rim_style == 1 else Color(0.25, 0.25, 0.27), 0.3, 0.4))
	wheel_pivots.clear()
	wheel_spins.clear()
	for i in 4:
		var pivot := Node3D.new()
		pivot.position = wheel_rest[i]
		add_child(pivot)
		var holder := Node3D.new()
		# outside face points away from the car: mirror left wheels
		if i % 2 == 0:
			holder.rotation.y = PI
		pivot.add_child(holder)
		var spin := Node3D.new()
		holder.add_child(spin)
		var mi := MeshInstance3D.new()
		mi.mesh = mesh
		spin.add_child(mi)
		var cmi := MeshInstance3D.new()
		cmi.mesh = cal_mesh
		holder.add_child(cmi)
		wheel_pivots.append(pivot)
		wheel_spins.append(spin)


## spin: rotation angle (rad) about the axle, steer: rad, travel: suspension offset (m)
func set_wheel(i: int, steer: float, spin: float, center: Vector3) -> void:
	var p := wheel_pivots[i]
	p.position = center
	p.rotation.y = steer
	var s := wheel_spins[i]
	s.rotation.x = spin if i % 2 == 1 else -spin


func set_lights(brake: float, head_on: bool) -> void:
	tail_mat.emission_energy_multiplier = 0.6 + brake * 4.5
	head_mat.emission_energy_multiplier = 3.5 if head_on else 0.6


func set_siren(t: float, on: bool) -> void:
	if lightbar_red == null:
		return
	if not on:
		lightbar_red.emission_energy_multiplier = 0.2
		lightbar_blue.emission_energy_multiplier = 0.2
		return
	var phase := fmod(t * 2.5, 1.0)
	var flash := fmod(t * 14.0, 1.0) < 0.5
	lightbar_red.emission_energy_multiplier = 9.0 if (phase < 0.5 and flash) else 0.3
	lightbar_blue.emission_energy_multiplier = 9.0 if (phase >= 0.5 and flash) else 0.3


# --------------------------------------------------------------------------- damage
## dent the body around a local point, pushing along local direction
func deform(local_point: Vector3, local_dir: Vector3, amount: float) -> void:
	amount = minf(amount, 0.16)
	if amount < 0.01:
		return
	var radius := 0.55 + amount * 2.5
	var r2 := radius * radius
	var changed := false
	for m in surf.size():
		var acc: MeshAcc = surf[m]
		var o: PackedVector3Array = orig[m]
		for i in acc.verts.size():
			var v := acc.verts[i]
			var d2 := v.distance_squared_to(local_point)
			if d2 < r2:
				var f := 1.0 - sqrt(d2) / radius
				f = f * f
				# per-vertex noise for crumpled metal
				var nz := sin(v.x * 37.0 + v.y * 17.0 + v.z * 23.0) * 0.35 + 0.65
				var nv := v + local_dir * amount * f * nz
				# limit total deformation from the original shape
				if nv.distance_to(o[i]) < 0.32:
					acc.verts[i] = nv
					changed = true
	if changed:
		damage = minf(damage + amount * 0.8, 1.0)
		paint_mat.set_shader_parameter("damage", damage)
		for m in surf.size():
			_weld_normals(surf[m])
		_commit_body()


func repair() -> void:
	for m in surf.size():
		surf[m].verts = orig[m].duplicate()
		_weld_normals(surf[m])
	damage = 0.0
	paint_mat.set_shader_parameter("damage", 0.0)
	_commit_body()
