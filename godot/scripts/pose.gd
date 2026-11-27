extends RefCounted
## Pose / animation system.
## A pose is a PackedFloat32Array of 18 vec3 keys (character faces +X, +Z = right side).
## Hands are stored in chest space but authored in root space via "L"/"R"; feet in root space.

const U = preload("res://scripts/util.gd")
const Rig = preload("res://scripts/rig.gd")

const KEYS := ["root", "hip", "spine", "chest", "neck", "head", "lh", "rh", "le", "re", "lf", "rf", "lk", "rk", "lw", "rw", "lfa", "rfa"]
const HK := ["L", "R", "LE", "RE", "+L", "+R", "free", "look", "nod"]

static var _guard: PackedFloat32Array = PackedFloat32Array()

static func idx(k: String) -> int:
	return KEYS.find(k) * 3

static func vget(p: PackedFloat32Array, o: int) -> Vector3:
	return Vector3(p[o], p[o + 1], p[o + 2])

static func vset(p: PackedFloat32Array, o: int, v: Vector3) -> PackedFloat32Array:
	p[o] = v.x; p[o + 1] = v.y; p[o + 2] = v.z
	return p

static func new_pose() -> PackedFloat32Array:
	var p := PackedFloat32Array()
	p.resize(54)
	return p

static func lerp_pose(a: PackedFloat32Array, b: PackedFloat32Array, t: float) -> PackedFloat32Array:
	var o := PackedFloat32Array()
	o.resize(54)
	for i in 54:
		o[i] = a[i] + (b[i] - a[i]) * t
	return o

static func chest_xf(p: PackedFloat32Array) -> Transform3D:
	return Transform3D(Rig.qrot(p, 3), vget(p, 0)) * Transform3D(Rig.qrot(p, 6), Vector3(0, Rig.PELVIS_UP, 0)) * Transform3D(Rig.qrot(p, 9), Vector3(0, Rig.SPINE_LEN, 0))

static func hand_root(p: PackedFloat32Array, o: int) -> Vector3:
	return chest_xf(p) * vget(p, o)

## Build a pose from a base + modifications ('+key' additive, L/R root-space hands, LE/RE root-space elbow poles)
static func P(base: PackedFloat32Array, m := {}) -> PackedFloat32Array:
	var p := base.duplicate()
	var hk := {}
	var bm := chest_xf(base)
	var keepL = bm * vget(base, 18) if m.has("+L") else null
	var keepR = bm * vget(base, 21) if m.has("+R") else null
	var keepLe: Vector3 = (bm.basis * vget(base, 24)).normalized()
	var keepRe: Vector3 = (bm.basis * vget(base, 27)).normalized()
	for k in m:
		if k in HK:
			hk[k] = m[k]
			continue
		var val: Array = m[k]
		var z: float = val[2] if val.size() > 2 else 0.0
		if k.begins_with("+"):
			var o := idx(k.substr(1))
			p[o] += val[0]; p[o + 1] += val[1]; p[o + 2] += z
		else:
			var o := idx(k)
			p[o] = val[0]; p[o + 1] = val[1]; p[o + 2] = z
	if not hk.has("free"):
		var yaw := p[4] + p[7] + p[10] + p[13]
		p[16] = hk.get("look", 0.0) - yaw
		var pitch := p[3] + p[6] + p[9] + p[12]
		p[15] = hk.get("nod", -0.02) - pitch * 0.85
		var side := p[5] + p[8] + p[11] + p[14]
		p[17] = -side * 0.7
	var inv := chest_xf(p).affine_inverse()
	if hk.has("L"): vset(p, 18, inv * U.v3(hk.L))
	elif keepL != null: vset(p, 18, inv * (keepL + U.v3(hk["+L"])))
	if hk.has("R"): vset(p, 21, inv * U.v3(hk.R))
	elif keepR != null: vset(p, 21, inv * (keepR + U.v3(hk["+R"])))
	var le: Vector3 = U.v3(hk.LE) if hk.has("LE") else keepLe
	var re: Vector3 = U.v3(hk.RE) if hk.has("RE") else keepRe
	vset(p, 24, (inv.basis * le).normalized())
	vset(p, 27, (inv.basis * re).normalized())
	return p

static func def0() -> PackedFloat32Array:
	var p := new_pose()
	vset(p, 0, Vector3(0, 0.97, 0))
	vset(p, 30, Vector3(0.05, 0.08, -0.11)); vset(p, 33, Vector3(0.05, 0.08, 0.11))
	vset(p, 36, Vector3(1, 0, -0.1)); vset(p, 39, Vector3(1, 0, 0.1))
	vset(p, 18, Vector3(0.05, -0.1, -0.24)); vset(p, 21, Vector3(0.05, -0.1, 0.24))
	vset(p, 24, Vector3(-0.3, -1, -0.3)); vset(p, 27, Vector3(-0.3, -1, 0.3))
	return p

static func guard() -> PackedFloat32Array:
	if _guard.size() == 0:
		_guard = P(def0(), {root = [0, 0.93, 0], hip = [0.05, -0.5, 0], spine = [0.05, -0.08, 0], chest = [0.1, -0.12, 0], neck = [-0.05, 0.3, 0],
			L = [0.38, 1.5, -0.02], R = [0.2, 1.47, 0.11], LE = [-0.05, -1, -0.45], RE = [-0.25, -1, 0.55],
			lf = [0.3, 0.08, -0.13], rf = [-0.3, 0.08, 0.15], lk = [1, 0.1, -0.25], rk = [0.7, 0.1, 0.7], lw = [0.25, 0, 0], rw = [0.25, 0, 0], lfa = [-0.15, 0, 0], rfa = [-0.7, 0, 0]})
	return _guard

## generic pose library derived from a character guard
static func std_poses(g: PackedFloat32Array) -> Dictionary:
	var S := {guard = g}
	S.idleB = P(g, {"+root": [0, -0.02, 0], "+chest": [0.04, 0, 0], "+L": [0, -0.03, 0], "+R": [0, -0.025, 0]})
	S.crouch = P(g, {"root": [-0.02, 0.56, 0], "+hip": [0.32, 0.1, 0], "+spine": [0.12, 0, 0], "+chest": [0.06, 0, 0], "lf": [0.33, 0.08, -0.2], "rf": [-0.26, 0.08, 0.22], "lk": [1, 0.25, -0.45], "rk": [1, 0.25, 0.65], "L": [0.44, 1.04, -0.02], "R": [0.28, 1.0, 0.12], "LE": [0, -1, -0.5], "RE": [-0.2, -1, 0.5], "rfa": [-0.5, 0, 0], "nod": 0.1})
	S.block = P(g, {"+root": [-0.04, -0.02, 0], "+hip": [0.04, 0.2, 0], "+chest": [0.12, 0.25, 0], "L": [0.32, 1.64, -0.05], "R": [0.28, 1.58, 0.08], "LE": [1, -0.5, -0.6], "RE": [1, -0.5, 0.6], "lw": [0.6, 0, 0], "rw": [0.6, 0, 0], "nod": 0.25})
	S.blockHit = P(S.block, {"+root": [-0.08, -0.03, 0], "+chest": [-0.08, 0, 0], "+L": [-0.05, 0.02, 0], "+R": [-0.05, 0.02, 0]})
	S.cblock = P(S.crouch, {"+chest": [0.15, 0.25, 0], "L": [0.38, 1.18, -0.05], "R": [0.33, 1.12, 0.08], "LE": [1, -0.5, -0.6], "RE": [1, -0.5, 0.6], "lw": [0.6, 0, 0], "rw": [0.6, 0, 0], "nod": 0.3})
	S.cblockHit = P(S.cblock, {"+root": [-0.06, -0.02, 0], "+L": [-0.05, 0, 0], "+R": [-0.05, 0, 0]})
	S.jsquat = P(g, {"+root": [0, -0.17, 0], "+hip": [0.25, 0, 0], "+chest": [0.08, 0, 0], "+L": [0, -0.12, 0], "+R": [0, -0.12, 0]})
	S.jump = P(g, {"root": [0, 1, 0], "+hip": [0.25, 0.2, 0], "+chest": [0.12, 0, 0], "lf": [0.25, 0.55, -0.12], "rf": [-0.02, 0.42, 0.12], "lk": [1, 0.3, 0], "rk": [1, 0.3, 0], "lfa": [0, 0.6, 0], "rfa": [0, 0.6, 0], "L": [0.4, 1.62, -0.05], "R": [0.25, 1.6, 0.12]})
	S.fall = P(g, {"root": [0, 1, 0], "lf": [0.2, 0.22, -0.12], "rf": [-0.18, 0.28, 0.12], "lfa": [0, 0.4, 0], "rfa": [0, 0.4, 0], "+L": [0, 0.08, 0], "+R": [0, 0.08, 0]})
	S.land = P(g, {"+root": [0, -0.2, 0], "+hip": [0.3, 0, 0], "+L": [0, -0.15, 0], "+R": [0, -0.12, 0]})
	S.dash = P(g, {"+root": [0.12, -0.08, 0], "+hip": [0.25, 0, 0], "+chest": [0.15, 0, 0], "lf": [0.6, 0.14, -0.12], "rf": [-0.45, 0.15, 0.15], "rfa": [-0.6, 0.5, 0]})
	S.bdash = P(g, {"+root": [-0.15, -0.05, 0], "+hip": [-0.18, 0, 0], "+chest": [-0.15, 0, 0], "lf": [0.45, 0.2, -0.12], "rf": [-0.25, 0.08, 0.15], "lfa": [-0.15, 0.4, 0]})
	S.side1 = P(g, {"+root": [0, -0.12, 0], "+hip": [0.1, 0.5, 0.25], "+chest": [0.15, 0.3, 0.2], "lf": [0.25, 0.1, -0.35], "rf": [-0.25, 0.08, 0.1], "+L": [0, -0.05, 0], "+R": [0, -0.05, 0]})
	S.hitHi = P(g, {"+root": [-0.1, -0.02, 0], "+hip": [-0.12, 0.15, 0], "+spine": [-0.15, 0, 0], "+chest": [-0.28, 0.25, 0.1], "+neck": [-0.25, 0, 0], "free": 1, "+head": [-0.25, 0.3, 0.2], "+L": [-0.22, 0.08, -0.12], "+R": [-0.18, -0.06, 0.18]})
	S.hitHi2 = P(g, {"+root": [-0.08, -0.04, 0], "+hip": [-0.05, -0.3, 0], "+chest": [-0.2, -0.35, -0.15], "+neck": [-0.2, 0, 0], "free": 1, "+head": [-0.2, -0.4, -0.25], "+L": [-0.2, -0.1, -0.2], "+R": [-0.15, 0.05, 0.1]})
	S.hitMid = P(g, {"+root": [-0.12, -0.1, 0], "+hip": [0.3, 0, 0], "+spine": [0.38, 0, 0], "+chest": [0.3, 0.1, 0], "L": [0.22, 1.02, -0.1], "R": [0.16, 0.98, 0.1], "nod": -0.4})
	S.hitLo = P(g, {"+root": [-0.06, -0.16, 0], "+hip": [0.18, 0, 0.1], "+chest": [0.2, 0, 0], "lf": [0.22, 0.2, -0.15], "lfa": [0, 0.4, 0], "nod": 0.1})
	S.hitHeavy = P(g, {"+root": [-0.18, -0.06, 0], "+hip": [-0.3, 0.3, 0.1], "+spine": [-0.25, 0, 0], "+chest": [-0.3, 0.3, 0.1], "+neck": [-0.3, 0, 0], "free": 1, "+head": [-0.4, 0.3, 0.25], "L": [0.0, 1.8, -0.45], "R": [-0.1, 1.7, 0.45], "LE": [0, -1, -1], "RE": [0, -1, 1]})
	S.airHit = P(g, {root = [0, 0.85, 0], hip = [-0.75, -0.3, 0], spine = [-0.25, 0, 0], chest = [-0.25, 0.1, 0], neck = [-0.3, 0, 0], free = 1, head = [-0.3, 0.3, 0], lf = [0.5, 0.45, -0.18], rf = [0.35, 0.25, 0.2], lk = [0, 1, 0], rk = [0, 1, 0], L = [-0.4, 1.85, -0.45], R = [-0.55, 1.6, 0.45], LE = [0, -1, -1], RE = [0, -1, 1], lfa = [0, 0.8, 0], rfa = [0, 0.8, 0]})
	S.airHit2 = P(S.airHit, {hip = [-1.2, -0.2, 0.2], spine = [-0.3, 0, 0], lf = [0.6, 0.7, -0.18], rf = [0.45, 0.5, 0.2], free = 1, L = [-0.7, 1.4, -0.6], R = [-0.8, 1.1, 0.5]})
	S.down = P(g, {root = [0.05, 0.14, 0], hip = [-1.52, 0.1, 0], spine = [0.04, 0, 0], chest = [0.02, 0, 0], neck = [0.25, 0, 0], free = 1, head = [0.1, 0.45, 0], lf = [0.88, 0.09, -0.17], rf = [0.8, 0.1, 0.2], lk = [0, 1, -0.3], rk = [0, 1, 0.4], lfa = [0.3, 0, 1.2], rfa = [-0.3, 0, 1.2], L = [-0.35, 0.09, -0.55], R = [-0.55, 0.09, 0.5], LE = [0, 1, -0.3], RE = [0, 1, 0.3]})
	S.downB = P(S.down, {root = [0.05, 0.16, 0], hip = [-1.45, 0.2, 0.1], neck = [0.1, 0, 0], free = 1, head = [-0.1, 0.2, 0], lf = [0.6, 0.25, -0.2], lk = [0.3, 1, -0.4]})
	S.getup1 = P(g, {root = [-0.1, 0.42, 0], hip = [-0.35, 0.2, 0], spine = [0.2, 0, 0], chest = [0.2, 0, 0], lf = [0.35, 0.08, -0.18], rf = [-0.32, 0.1, 0.2], lk = [1, 0.4, -0.5], rk = [0, 0.3, 1], L = [-0.25, 0.12, -0.35], R = [0.35, 0.55, 0.25], nod = 0.2})
	S.getup2 = P(g, {"+root": [0, -0.18, 0], "+hip": [0.35, 0, 0], "+chest": [0.15, 0, 0], "+L": [0, -0.25, 0], "+R": [0, -0.2, 0]})
	S.dizzy = P(g, {root = [-0.05, 0.88, 0], hip = [0.1, -0.2, 0.08], spine = [0.15, 0, 0.05], chest = [0.18, 0, 0.08], neck = [0.3, 0, 0], free = 1, head = [0.35, 0.25, 0.3], L = [0.08, 0.95, -0.3], R = [0.02, 0.9, 0.3], LE = [0, -1, -0.3], RE = [0, -1, 0.3], lf = [0.12, 0.08, -0.14], rf = [-0.12, 0.08, 0.16], lw = [-0.2, 0, 0], rw = [-0.2, 0, 0]})
	S.dizzy2 = P(S.dizzy, {root = [0.03, 0.86, 0], hip = [0.12, -0.15, -0.1], chest = [0.22, 0, -0.1], free = 1, head = [0.4, -0.2, -0.35], L = [0.12, 0.92, -0.28], R = [0.0, 0.88, 0.32]})
	S.kneel = P(g, {root = [-0.05, 0.5, 0], hip = [0.1, -0.2, 0], spine = [0.15, 0, 0], chest = [0.2, 0, 0], neck = [0.2, 0, 0], free = 1, head = [0.3, 0.2, 0.1], lf = [0.35, 0.08, -0.15], rf = [-0.35, 0.05, 0.15], lk = [1, 0.2, -0.2], rk = [0, -1, 0.3], rfa = [0, 0.6, 0], L = [0.25, 0.75, -0.25], R = [0.1, 0.7, 0.25]})
	S.grabbed = P(g, {"+root": [-0.05, -0.03, 0], "+hip": [-0.15, 0.3, 0], "+chest": [-0.2, 0.4, 0], "+neck": [-0.2, 0, 0], "free": 1, "head": [-0.2, 0.1, 0], "L": [0.35, 1.35, -0.15], "R": [0.32, 1.3, 0.15], "LE": [0, -1, -0.6], "RE": [0, -1, 0.6]})
	S.lifted = P(g, {root = [0, 0.95, 0], hip = [-0.08, 0.2, 0], spine = [-0.05, 0, 0], chest = [-0.1, 0.2, 0], neck = [-0.3, 0, 0], free = 1, head = [-0.35, -0.1, 0], lf = [0.1, 0.02, -0.12], rf = [-0.08, 0.06, 0.12], lk = [1, 0, 0], rk = [1, 0, 0], lfa = [0, 0.9, 0], rfa = [0, 0.9, 0], L = [0.32, 1.62, -0.06], R = [0.3, 1.58, 0.07], LE = [0, -1, -0.8], RE = [0, -1, 0.8]})
	S.limp = P(S.lifted, {neck = [0.3, 0, 0], head = [0.4, 0.2, 0.3], L = [0.05, 0.95, -0.25], R = [0, 0.9, 0.25], LE = [0, -1, -0.3], RE = [0, -1, 0.3], free = 1})
	S.taunt = P(g, {"+root": [0, 0.02, 0], "+chest": [-0.15, 0.2, 0], "L": [0.25, 1.15, -0.3], "R": [0.6, 1.7, 0.25], "RE": [0, -1, 1]})
	return S

## strike keyframes timed from frame data: guard -> chamber -> extension (first active frame) -> recovery
static func kstrike(g: PackedFloat32Array, mv: Dictionary, C, E: PackedFloat32Array, o := {}) -> Array:
	var s: int = mv.startup
	var a: int = mv.active
	var r: int = mv.recovery
	var k := [[0, o.get("from", g), "io"]]
	if C != null:
		k.append([maxi(1, roundi(s * o.get("cf", 0.55))), C, o.get("ce", "io")])
	k.append([s, E, o.get("ee", "out")])
	k.append([s + a, o.get("E2", E), "lin"])
	if o.has("R"):
		k.append([s + a + maxi(1, roundi(r * o.get("rf", 0.45))), o.R, "io"])
	k.append([s + a + r, o.get("end", g), "io"])
	return k

static func ex(base: Dictionary, o: Dictionary) -> Dictionary:
	var d := base.duplicate()
	if o.has("ex"): d.merge(o.ex, true)
	return d

# ---- generators (o.t = target override, o.ex = extra mods)
static func jab(g, mv, o := {}) -> Array:
	return kstrike(g, mv, P(g, {"+L": [-0.06, -0.02, 0], "+chest": [0, 0.05, 0]}), P(g, ex({"+root": [0.07, -0.01, 0], "+hip": [0.03, -0.1, 0], "+chest": [0.05, -0.15, 0], "L": o.get("t", [0.86, 1.52, -0.03]), "LE": [0, -1, -0.25], "lw": [0, 0, 0]}, o)), o)
static func jab2(g, mv, o := {}) -> Array:
	return kstrike(g, mv, P(g, {"+L": [-0.12, -0.03, 0]}), P(g, ex({"+root": [0.1, -0.02, 0], "+hip": [0.03, -0.12, 0], "+chest": [0.06, -0.18, 0], "L": o.get("t", [0.9, 1.47, -0.02]), "LE": [0, -1, -0.25], "lw": [0, 0, 0]}, o)), {cf = 0.4})
static func cross(g, mv, o := {}) -> Array:
	return kstrike(g, mv, P(g, {"+chest": [0, -0.1, 0], "+R": [-0.06, 0, 0.02]}), P(g, ex({"+root": [0.12, -0.03, 0], "+hip": [0.06, 0.32, 0], "+spine": [0.03, 0.2, 0], "+chest": [0.1, 0.45, 0], "R": o.get("t", [0.92, 1.5, 0.0]), "RE": [0, -1, 0.2], "L": [0.22, 1.48, -0.14], "rfa": [-0.2, 0.35, 0], "rw": [0, 0, 0]}, o)), o)
static func hook(g, mv, o := {}) -> Array:
	return kstrike(g, mv, P(g, {"+chest": [0, -0.25, 0], "+hip": [0, -0.1, 0], "R": [0.1, 1.45, 0.4], "RE": [0, 0.1, 1]}), P(g, ex({"+root": [0.1, -0.04, 0], "+hip": [0.05, 0.4, 0], "+spine": [0.05, 0.2, 0], "+chest": [0.12, 0.55, -0.05], "R": o.get("t", [0.78, 1.5, -0.15]), "RE": [-0.25, 0.35, 1], "L": [0.22, 1.48, -0.15], "rfa": [-0.1, 0.4, 0], "rw": [0.2, 0, 0]}, o)), o)
static func hookL(g, mv, o := {}) -> Array:
	return kstrike(g, mv, P(g, {"+chest": [0, 0.2, 0], "L": [0.25, 1.45, -0.45], "LE": [0, 0.1, -1]}), P(g, ex({"+root": [0.08, -0.03, 0], "+hip": [0.03, -0.35, 0], "+chest": [0.1, -0.45, 0.05], "L": o.get("t", [0.8, 1.52, 0.12]), "LE": [-0.25, 0.35, -1], "R": [0.2, 1.48, 0.14], "lfa": [0.3, 0.3, 0]}, o)), o)
static func upper(g, mv, o := {}) -> Array:
	var oo: Dictionary = o.duplicate()
	if not oo.has("R"): oo.R = P(g, {"+root": [0.05, 0, 0], "R": [0.4, 1.85, 0.1]})
	return kstrike(g, mv, P(g, {"+root": [0.02, -0.14, 0], "+hip": [0.2, 0.05, 0], "+chest": [0.22, -0.15, 0], "R": [0.22, 1.05, 0.22], "RE": [-0.3, -1, 0.3]}), P(g, ex({"+root": [0.12, 0.04, 0], "+hip": [-0.12, 0.3, 0], "+chest": [-0.18, 0.5, 0], "R": o.get("t", [0.55, 2.05, 0.02]), "RE": [-0.6, -1, 0.35], "L": [0.18, 1.42, -0.2], "rfa": [-0.2, 0.5, 0], "rw": [-0.2, 0, 0]}, o)), oo)
static func hammer(g, mv, o := {}) -> Array:
	var oo: Dictionary = o.duplicate()
	oo.cf = 0.6
	return kstrike(g, mv, P(g, {"+root": [-0.03, 0.05, 0], "+hip": [-0.15, 0.2, 0], "+chest": [-0.28, 0.3, 0], "R": [-0.02, 2.12, 0.1], "L": [0.05, 2.05, -0.1], "RE": [0, 0.3, 1], "LE": [0, 0.3, -1]}), P(g, ex({"+root": [0.17, -0.12, 0], "+hip": [0.25, 0.3, 0], "+spine": [0.28, 0, 0], "+chest": [0.38, 0.3, 0], "R": o.get("t", [0.82, 1.12, 0.02]), "L": [0.75, 1.18, -0.1], "RE": [-0.5, 1, 0.6], "LE": [-0.5, 1, -0.6], "nod": 0.3}, o)), oo)
static func elbow(g, mv, o := {}) -> Array:
	return kstrike(g, mv, P(g, {"+chest": [0, -0.15, 0]}), P(g, ex({"+root": [0.12, -0.03, 0], "+hip": [0.05, 0.35, 0], "+chest": [0.1, 0.55, 0], "R": [0.32, 1.55, 0.12], "RE": [1, 0.3, -0.2], "L": [0.22, 1.48, -0.14]}, o)), o)
static func cast(g, mv, o := {}) -> Array:
	return kstrike(g, mv, P(g, {"+root": [-0.05, 0, 0], "+hip": [-0.05, -0.2, 0], "+chest": [-0.12, -0.35, 0], "L": [-0.05, 1.3, -0.32], "R": [-0.1, 1.3, 0.3], "LE": [0, -1, -1], "RE": [0, -1, 1]}), P(g, ex({"+root": [0.14, -0.04, 0], "+hip": [0.1, 0.2, 0], "+chest": [0.2, 0.3, 0], "L": o.get("t", [0.8, 1.45, -0.07]), "R": o.get("t2", [0.78, 1.4, 0.08]), "LE": [0, -1, -0.5], "RE": [0, -1, 0.5], "lw": [-0.8, 0, 0], "rw": [-0.8, 0, 0]}, o)), {cf = 0.6})
static func fkick(g, mv, o := {}) -> Array:
	var oo: Dictionary = o.duplicate()
	if not oo.has("R"): oo.R = P(g, {rf = [0.3, 0.55, 0.08], rk = [1, 0.6, 0.2]})
	return kstrike(g, mv, P(g, {"+root": [-0.02, 0.01, 0], "+hip": [-0.1, 0.1, 0], "rf": [0.22, 0.62, 0.06], "rk": [1, 0.7, 0.2], "rfa": [0, 0.3, 0]}), P(g, ex({"+root": [-0.06, 0.04, 0], "+hip": [-0.28, 0.25, 0], "+chest": [-0.08, 0.05, 0], "rf": o.get("t", [0.88, 0.98, 0.03]), "rk": [1, 1, 0], "rfa": [0, 0.55, 0], "lfa": [-0.5, 0, 0]}, o)), oo)
static func round_k(g, mv, o := {}) -> Array:
	var oo: Dictionary = o.duplicate()
	oo.R = P(g, {"+hip": [-0.2, 0.6, -0.2], "rf": [0.2, 0.9, -0.05], "rk": [0.5, 0.5, -0.8], "lfa": [0.7, 0, 0]})
	return kstrike(g, mv, P(g, {"+root": [0, 0.03, 0], "+hip": [-0.15, 0.4, -0.1], "rf": [0.05, 0.8, 0.32], "rk": [0.6, 0.4, 0.8], "rfa": [0, 0.5, 0], "lfa": [0.4, 0, 0]}), P(g, ex({"+root": [-0.04, 0.06, 0], "+hip": [-0.5, 0.95, -0.45], "+spine": [0, 0.1, 0.05], "+chest": [-0.05, 0.1, 0.25], "rf": o.get("t", [0.78, 1.58, -0.08]), "rk": [0.2, 0.3, -1], "rfa": [0, 0.8, 0], "lfa": [1, 0, 0], "R": [-0.25, 1.25, 0.35], "L": [0.28, 1.5, -0.18]}, o)), oo)
static func lowkick(g, mv, o := {}) -> Array:
	return kstrike(g, mv, P(g, {"+root": [-0.02, -0.04, 0], "lf": [0.38, 0.25, -0.1], "lk": [1, 0.2, 0]}), P(g, ex({"+root": [-0.05, -0.06, 0], "+hip": [-0.1, -0.1, 0], "lf": o.get("t", [0.82, 0.2, -0.05]), "lk": [1, 0.4, 0], "lfa": [0, 0.4, 0]}, o)), o)
static func knee(g, mv, o := {}) -> Array:
	return kstrike(g, mv, P(g, {L = [0.5, 1.55, -0.1], R = [0.48, 1.5, 0.12], rf = [-0.1, 0.3, 0.1]}), P(g, ex({"+root": [0.12, 0.03, 0], "+hip": [-0.15, 0.3, 0], "+chest": [0.15, 0.3, 0], "rf": o.get("t", [0.22, 0.72, 0.04]), "rk": [1, 0.6, 0], "rfa": [0, 0.7, 0], "L": [0.5, 1.35, -0.1], "R": [0.48, 1.32, 0.12]}, o)), o)
static func sidekick(g, mv, o := {}) -> Array:
	return kstrike(g, mv, P(g, {"+hip": [-0.1, -0.5, 0], "lf": [0.28, 0.7, -0.15], "lk": [0.3, 1, -0.5]}), P(g, ex({"+root": [-0.12, 0.03, 0], "+hip": [-0.4, -0.9, -0.2], "+chest": [-0.2, -0.1, -0.1], "lf": o.get("t", [1.02, 0.82, -0.03]), "lk": [0, 1, -0.4], "lfa": [-PI / 2, 0.6, 0], "rfa": [-1.2, 0, 0], "L": [0.3, 1.35, -0.2]}, o)), o)
static func axe(g, mv, o := {}) -> Array:
	var oo: Dictionary = o.duplicate()
	oo.cf = 0.6
	return kstrike(g, mv, P(g, {"+root": [-0.06, 0.05, 0], "+hip": [-0.4, 0.25, 0], "rf": [0.5, 1.85, 0.05], "rk": [1, 0.3, 0], "rfa": [0, 0.6, 0]}), P(g, ex({"+root": [0.06, -0.02, 0], "+hip": [0.1, 0.25, 0], "rf": o.get("t", [0.8, 0.55, 0.03]), "rk": [1, 0.4, 0], "rfa": [0, 0.5, 0]}, o)), oo)
static func cjab(g, cr, mv, o := {}) -> Array:
	return kstrike(cr, mv, P(cr, {"+L": [-0.05, 0, 0]}), P(cr, ex({"+root": [0.06, 0.02, 0], "+chest": [0.03, -0.15, 0], "L": o.get("t", [0.82, 1.02, -0.02]), "LE": [0, -1, -0.3], "lw": [0, 0, 0]}, o)), o)
static func cupper(g, cr, mv, o := {}) -> Array:
	return kstrike(cr, mv, P(cr, {"+root": [0, -0.04, 0], "+chest": [0.1, -0.15, 0], "R": [0.28, 0.82, 0.2]}), P(g, ex({"+root": [0.1, 0.02, 0], "+hip": [-0.15, 0.35, 0], "+chest": [-0.22, 0.55, 0], "R": o.get("t", [0.5, 2.05, 0.02]), "RE": [-0.6, -1, 0.35], "L": [0.18, 1.42, -0.2], "rfa": [-0.2, 0.5, 0]}, o)), {end = cr, R = P(g, {R = [0.42, 1.9, 0.1]})})
static func clow(g, cr, mv, o := {}) -> Array:
	return kstrike(cr, mv, P(cr, {lf = [0.4, 0.18, -0.18]}), P(cr, ex({"+root": [-0.05, 0, 0], "+hip": [-0.15, -0.1, 0], "lf": o.get("t", [0.88, 0.12, -0.06]), "lk": [1, 0.5, 0], "lfa": [0, 0.5, 0]}, o)), o)
static func sweep(g, cr, mv, o := {}) -> Array:
	return kstrike(cr, mv, P(cr, {"+root": [0, -0.1, 0], "+hip": [0.3, 0.4, 0], "rf": [-0.45, 0.1, 0.5], "L": [0.3, 0.14, -0.3], "LE": [0, -1, -0.5]}), P(cr, ex({"+root": [-0.08, -0.12, 0], "+hip": [0.25, -1.25, 0], "+chest": [0.15, -0.2, 0], "rf": o.get("t", [0.98, 0.1, -0.25]), "rk": [0, 1, 0], "rfa": [-1.2, 0.2, 0], "lf": [0.05, 0.08, -0.4], "L": [0.0, 0.12, -0.4], "R": [0.25, 0.3, 0.2], "LE": [0, -1, -0.5]}, o)), {cf = 0.45})
static func jpunch(g, j, mv, o := {}) -> Array:
	return kstrike(j, mv, null, P(j, ex({"+hip": [0.25, 0.3, 0], "+chest": [0.25, 0.4, 0], "R": o.get("t", [0.78, 1.2, 0.02]), "RE": [0, -1, 0.3]}, o)), {end = j})
static func jkick(g, j, mv, o := {}) -> Array:
	return kstrike(j, mv, null, P(j, ex({"+hip": [-0.25, 0.3, 0], "rf": o.get("t", [0.78, 0.32, 0.03]), "rk": [1, 0.4, 0], "rfa": [0, 0.7, 0], "lf": [0.05, 0.62, -0.12]}, o)), {end = j})

## keyframes -> clip
static func clip(keys: Array, loop := false) -> Dictionary:
	var k := []
	for x in keys:
		k.append([float(x[0]), x[1], x[2] if x.size() > 2 else "io"])
	k.sort_custom(func(a, b): return a[0] < b[0])
	return {keys = k, len = k[k.size() - 1][0], loop = loop}

static func sample(c: Dictionary, t: float) -> PackedFloat32Array:
	var k: Array = c.keys
	if c.loop and c.len > 0.0:
		t = fposmod(t, c.len)
	if t <= k[0][0]: return k[0][1]
	for i in range(1, k.size()):
		if t <= k[i][0]:
			var a: Array = k[i - 1]
			var b: Array = k[i]
			var u = (t - a[0]) / maxf(1e-6, b[0] - a[0])
			return lerp_pose(a[1], b[1], U.ease_f(b[2], u))
	return k[k.size() - 1][1]

## procedural stance walk: feet step with ground contact
static func walk(p: PackedFloat32Array, phase: float, amt: float) -> PackedFloat32Array:
	var D := 0.78
	var S := D / 2.0
	for s in 2:
		var ph := fposmod(phase + (0.5 if s == 1 else 0.0), 1.0)
		var x: float
		var y: float
		if ph < 0.5:
			x = S / 2.0 - ph / 0.5 * S
			y = 0.0
		else:
			var q := (ph - 0.5) / 0.5
			x = -S / 2.0 + U.ease_f("sine", q) * S
			y = sin(PI * q) * 0.11
		var fo := 33 if s == 1 else 30
		p[fo] += x * amt
		p[fo + 1] += y * amt
		var ao := 51 if s == 1 else 48
		if ph > 0.5: p[ao + 1] += sin(PI * (ph - 0.5) / 0.5) * 0.25 * amt
	p[1] -= (0.012 + 0.018 * absf(sin(phase * TAU * 2.0))) * amt
	p[5] += sin(phase * TAU) * 0.04 * amt
	p[11] -= sin(phase * TAU) * 0.03 * amt
	p[4] += sin(phase * TAU) * 0.06 * amt
	return p
