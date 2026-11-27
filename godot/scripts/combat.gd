extends RefCounted
## Hit detection & resolution, throws, breakers, wounds. All static; state lives in G.

const PZ = preload("res://scripts/pose.gd")
const Geo = preload("res://scripts/geo.gd")
const STAGE := 7.3

static var _wound_mesh: Mesh
static var _wcache := {}

static func detect_hit(A, B):
	if A.state != "attack" or A.move == null: return null
	var m: Dictionary = A.move
	for i in m.hits.size():
		var h: Dictionary = m.hits[i]
		if A.hit_done[i] or A.mf < h.f or A.mf >= h.f + h.a: continue
		if B.invuln_to(h, false): continue
		var s: float = A.s
		var xa: float = A.x + A.facing * h.box[0] * s
		var xb: float = A.x + A.facing * h.box[1] * s
		var lo := minf(xa, xb)
		var hi := maxf(xa, xb)
		var y0: float = A.y + h.box[2] * s
		var y1: float = A.y + h.box[3] * s
		var hb: Array = B.hurt()
		if hi < hb[0] or lo > hb[1] or y1 < hb[2] or y0 > hb[3]: continue
		var px := clampf(B.x - A.facing * 0.2 * B.s, lo, hi)
		var py := clampf((maxf(y0, hb[2]) + minf(y1, hb[3])) / 2.0, hb[2] + 0.2, hb[3] - 0.1)
		return {i = i, h = h, p = Vector3(px, py, 0.05)}
	return null

static func hit_fx(A, B, h: Dictionary, p: Vector3, blocked: bool) -> void:
	var dir: float = A.facing
	var pw: float = h.get("power", 0.8)
	if blocked:
		VFX.spark(p, roundi(10 + pw * 10), Color(4, 2.6, 1.2), -dir * 0.3)
		VFX.flash(p, Color(3, 2.4, 1.6), 0.5 + pw * 0.4)
		VFX.ring(p, Color(1.5, 1.1, 0.7), 0.7 + pw * 0.5, 0.2)
		SFX.play("block", pw)
		G.cam_shake(0.08 + pw * 0.1)
		return
	var n := roundi(10 + pw * 24 * (1.5 if h.get("slash", false) else 1.0))
	VFX.blood(p, dir, n, {speed = 2.4 + pw * 2.2, size = 0.015 + pw * 0.006})
	if pw > 0.9: VFX.blood(p, -dir * 0.3, 10, {speed = 2.0, up = 1.6, size = 0.02})
	var fire: bool = h.get("fire", false)
	VFX.flash(p, Color(5, 1.8, 0.4) if fire else Color(3.2, 1.6, 1.4), 0.7 + pw * 0.7)
	VFX.ring(p, Color(2.5, 0.8, 0.2) if fire else Color(1.6, 0.3, 0.2), 0.9 + pw * 0.9, 0.25)
	if fire:
		for i in 10: VFX.fire(p + Vector3(randf_range(-0.2, 0.2), randf_range(-0.3, 0.3), randf_range(-0.2, 0.2)), 1.2)
		SFX.play("fire", 0.6)
	if h.get("slash", false): SFX.play("slice", pw)
	elif pw > 1.0: SFX.play("heavy", pw)
	else: SFX.play("hit", pw)
	SFX.play("splat", 0.4 + pw * 0.3)
	if randf() < 0.7: SFX.voice(B.def.id, "hurt" if pw > 1.0 else "grunt", 0.7)
	VFX.light_at(p + Vector3(0, 0, 1), Color(1, 0.5, 0.2) if fire else Color(1, 0.2, 0.15), 3.0 + pw * 5.0)
	G.cam_shake(0.12 + pw * 0.2)
	if pw >= 1.2: G.impact = 2.0
	if B.rig.wounds.size() < 40: add_wound(B, p.y)
	B.flinch_v += (-1.0 if h.lvl == "low" else 1.0) * (2.0 + pw * 4.0)

static func add_wound(B, py: float) -> void:
	if _wound_mesh == null:
		var sm := SphereMesh.new()
		sm.radius = 1.0; sm.height = 2.0; sm.radial_segments = 8; sm.rings = 4
		_wound_mesh = sm
	var rel: float = (py - B.y) / B.s
	var sg = "head" if rel > 1.55 else ("chest" if rel > 1.2 else ("spine" if rel > 0.9 else (["thL", "thR"][randi() % 2] if rel > 0.5 else ["snL", "snR"][randi() % 2])))
	var node: MeshInstance3D = B.rig.seg[sg]
	if node.mesh == null: return
	if not _wcache.has(node.mesh):
		var arr := node.mesh.surface_get_arrays(0)
		_wcache[node.mesh] = [arr[Mesh.ARRAY_VERTEX], arr[Mesh.ARRAY_NORMAL]]
	var V: PackedVector3Array = _wcache[node.mesh][0]
	var N: PackedVector3Array = _wcache[node.mesh][1]
	if V.size() < 10: return
	var k := randi() % V.size()
	var w := MeshInstance3D.new()
	w.mesh = _wound_mesh
	w.material_override = Mats.M.blood
	w.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var n: Vector3 = N[k]
	var up := Vector3.UP if absf(n.y) < 0.95 else Vector3.RIGHT
	var xa := up.cross(n).normalized()
	var za := xa.cross(n)
	var r := randf_range(0.015, 0.04)
	w.transform = Transform3D(Basis(xa * r, n * 0.004, za * r * randf_range(0.8, 1.8)), V[k] + n * 0.002)
	node.add_child(w)
	B.rig.wounds.append(w)

static func resolve_hit(A, B, h: Dictionary, p: Vector3, proj = null) -> String:
	if G.phase == "endthem" and B.hp <= 0 and B.state == "dizzy":
		var r := _resolve(A, B, h, p, proj)
		B.dead = true
		G.end_hit = true
		if B.state != "juggle":
			B.set_state("juggle"); B.vy = 0.08; B.play("air", 3.0)
		G.ui.hide_exec_hint()
		return r
	return _resolve(A, B, h, p, proj)

static func _resolve(A, B, h: Dictionary, p: Vector3, proj) -> String:
	var blocked: bool = B.blocking(h.lvl)
	if h.lvl == "throw" or (h.get("grab", false) and not blocked):
		start_throw(A, B, h)
		return "throw"
	if not blocked and B.state == "attack" and B.move != null and B.move.has("armor") and B.armor_left > 0 and B.mf >= B.move.armor[0] and B.mf <= B.move.armor[1] and not h.get("cine", false):
		B.armor_left -= 1
		B.hp = maxi(1, B.hp - roundi(h.dmg * 0.45))
		A.contact = true; A.contact_f = A.mf
		VFX.spark(p, 18, Color(4, 3, 1.5))
		VFX.ring(Vector3(B.x, 1.2 * B.s, 0), Color(2.5, 1.6, 0.5), 1.6, 0.25)
		SFX.play("block", 1.2)
		G.hitstop = 7
		G.ui.show_tag(B.idx, "ARMOR")
		G.cam_shake(0.2)
		if proj: proj.dead = true
		return "armor"
	A.contact = true
	A.contact_f = A.mf
	var dir: int = A.facing
	if blocked:
		var low: bool = B.state == "cblock" or B.block_low
		B.set_state("bstun"); B.block_low = low; B.stun = h.bs
		B.play("cblockHit" if low else "blockHit", 2.0)
		if (A.move != null and (A.move.type == "special" or A.move.type == "ex")) or proj:
			B.hp = maxi(1 if G.training else 0, B.hp - roundi(h.dmg * 0.12))
		B.kbx = dir * (h.push + 0.03) * 1.1
		if absf(B.x) > STAGE - 0.35 and signf(B.x) == dir: A.kbx = -dir * (h.push + 0.02) * 0.9
		A.meter = minf(300, A.meter + h.dmg * 0.22)
		B.meter = minf(300, B.meter + h.dmg * 0.25)
		hit_fx(A, B, h, p, true)
		G.hitstop = roundi(5 + h.power * 3)
		if h.get("cine", false): G.ui.show_tag(A.idx, "BLOCKED")
		if B.hp <= 0 and not G.training: G.on_ko(A, B)
		return "block"
	var dmg: float = h.dmg
	var tag := ""
	if B.state == "attack" and B.move != null and B.mf < B.move.firstActive:
		dmg *= 1.15; tag = "COUNTER"
	elif B.state == "attack" and B.move != null and B.mf > B.move.lastActive:
		tag = "PUNISH"
	if h.get("cine", false):
		G.cine.start_super_cine(A, B)
		return "cine"
	var scale: float = maxf(0.33, 1.0 - 0.09 * B.combo_hits) if B.combo_hits > 0 else 1.0
	var d := maxi(1, roundi(dmg * scale))
	B.hp = maxi(0, B.hp - d)
	B.combo_hits += 1
	B.combo_dmg += d
	if h.has("poison"): B.poison = maxi(B.poison, h.poison)
	if h.has("heal"): A.hp = mini(A.max_hp, A.hp + h.heal)
	A.meter = minf(300, A.meter + d * 0.5)
	B.meter = minf(300, B.meter + d * 0.32)
	if G.stats: G.stats.dmg[A.idx] += d
	hit_fx(A, B, h, p, false)
	if tag != "": G.ui.show_tag(A.idx, tag)
	var was_air: bool = B.state == "juggle" or B.state == "air" or (B.state == "attack" and B.move != null and B.move.get("air", false))
	var was_crouch: bool = B.crouching()
	B.move = null; B.trail_on = false; B.vanish = false; B.z = 0.0
	var launch: float = h.get("launch", 0.0)
	var kd: bool = h.get("kd", false)
	if was_air or launch > 0.0 or kd or (h.has("airLaunch") and was_air) or B.hp <= 0:
		B.state = "juggle"; B.sf = 0; B.bounced = false
		var vy: float
		if launch > 0.0: vy = launch * (maxf(0.55, 1.0 - B.juggle_n * 0.08) if was_air else 1.0)
		elif kd: vy = 0.07 if was_air else 0.085
		else: vy = maxf(B.vy * 0.3, 0.065 - B.juggle_n * 0.003)
		if h.get("airKd", false) and was_air: vy = -0.05
		if B.hp <= 0: vy = maxf(vy, 0.1)
		B.vy = vy; B.y = maxf(B.y, 0.02)
		B.vx = dir * (0.05 if kd else 0.022) * (1.4 if h.power > 1.0 else 1.0); B.kbx = 0.0
		if was_air: B.juggle_n += 1
		B.play("air", 3.0)
	else:
		B.hit_crouch = was_crouch
		B.set_state("hit")
		B.stun = h.hs + (4 if tag == "COUNTER" else 0)
		var clipn := "hitMid"
		if was_crouch: clipn = "hitCr"
		elif h.power >= 1.0: clipn = "hitHeavy"
		elif h.lvl == "low": clipn = "hitLo"
		elif h.lvl == "high": clipn = "hitHi" if randf() < 0.5 else "hitHi2"
		B.play(clipn, 2.0)
		B.kbx = dir * h.push * 1.2
		if absf(B.x) > STAGE - 0.35 and signf(B.x) == dir: A.kbx = -dir * h.push * 0.9
	G.hitstop = roundi(6 + h.power * 5 + (3 if tag == "COUNTER" else 0))
	if B.hp <= 0 and not G.training: G.on_ko(A, B)
	if G.training and B.hp <= 0: B.hp = 1
	return "hit"

static func do_breaker(F) -> void:
	var O = F.opp()
	F.meter -= 200
	F.to_neutral(); F.inv = 24; F.y = 0.0; F.vy = 0.0
	O.move = null; O.state = "juggle"; O.sf = 0; O.vy = 0.1; O.y = 0.05; O.vx = -O.facing * 0.07; O.no_juggle = true; O.play("air", 3.0)
	var p: Vector3 = F.rig.joint_world("chest")
	VFX.ring(p, Color(2.5, 1.2, 0.4), 4.0, 0.5)
	VFX.spark(p, 40, Color(4, 2, 0.6))
	VFX.flash(p, Color(4, 3, 2), 3.0)
	SFX.play("boom", 0.8); SFX.play("block", 1.4)
	G.cam_shake(0.5); G.hitstop = 14; G.slowmo(0.35, 0.5)
	G.ui.show_tag(F.idx, "BREAKER")

# ------------------------------------------------------------------ throws
static func start_throw(A, B, h: Dictionary) -> void:
	var grab: bool = h.get("grab", false)
	A.set_state("throwing"); B.set_state("thrown"); A.move = null; B.move = null
	A.vx = 0.0; B.vx = 0.0; A.kbx = 0.0; B.kbx = 0.0; B.y = 0.0; B.vanish = false
	B.facing = -A.facing
	B.x = A.x + A.facing * 0.62 * A.s
	G.thr = {A = A, B = B, t = 0, grab = grab, back = h.get("back", false), dmg = h.dmg, heal = h.get("heal", 0), teched = false}
	var S: Dictionary = A.def.S
	var T: Dictionary = B.def.S
	var kneeP := PZ.P(S.guard, {"L": [0.58, 1.45, -0.1], "R": [0.56, 1.42, 0.1], "rf": [0.15, 0.75, 0.05], "rk": [1, 0.7, 0], "rfa": [0, 0.6, 0], "+hip": [-0.1, 0.3, 0]})
	var hold := PZ.P(S.guard, {"+root": [0.05, 0, 0], "L": [0.6, 1.5, -0.1], "R": [0.58, 1.48, 0.1]})
	A.play_clip(PZ.clip([[0, S.guard], [4, PZ.P(S.guard, {"+root": [0.05, 0, 0], "L": [0.62, 1.55, -0.1], "R": [0.6, 1.5, 0.1], "LE": [0, -1, -0.7], "RE": [0, -1, 0.7]}), "out"], [16, hold], [20, kneeP, "out"], [27, hold], [32, kneeP, "out"], [40, PZ.P(S.guard, {"+chest": [-0.2, -0.4, 0], "L": [0.2, 1.5, -0.2], "R": [0.2, 1.45, 0.2]})], [46, PZ.P(S.guard, {"+root": [0.15, -0.05, 0], "+chest": [0.2, 0.4, 0], "L": [0.85, 1.6, -0.1], "R": [0.82, 1.55, 0.1]}), "snap"], [62, S.guard]]), 3.0, "throw")
	B.play_clip(PZ.clip([[0, T.guard], [4, T.grabbed, "out"], [16, T.grabbed], [21, T.hitMid, "out"], [27, T.grabbed], [33, T.hitMid, "out"], [40, T.grabbed], [46, T.airHit]]), 3.0, "thrown")
	SFX.play("whoosh", 0.6)
	SFX.voice(A.def.id, "atk", 0.7)

static func throw_tick() -> void:
	var T = G.thr
	if T == null: return
	T.t += 1
	var A = T.A
	var B = T.B
	var t: int = T.t
	if not T.grab and t <= 10 and B.input.recent("TH", 10) >= 0 and not T.teched:
		T.teched = true
		B.input.consume("TH")
		G.thr = null
		A.set_state("stagger"); B.set_state("stagger"); A.stun = 18; B.stun = 18
		A.kbx = -A.facing * 0.09; B.kbx = -B.facing * 0.09
		A.play("blockHit", 2.0); B.play("blockHit", 2.0)
		var xm: float = (A.x + B.x) / 2.0
		VFX.spark(Vector3(xm, 1.4, 0.1), 30, Color(4, 2.4, 1.2))
		VFX.flash(Vector3(xm, 1.4, 0.1), Color(4, 3, 2), 1.5)
		SFX.play("block", 1.2)
		G.ui.show_tag(B.idx, "ESCAPE")
		return
	B.x = A.x + A.facing * 0.62 * A.s
	B.facing = -A.facing
	var part := roundi(T.dmg * 0.3)
	if t == 21 or t == 33: _throw_hit(A, B, part)
	if t == 46:
		_throw_hit(A, B, T.dmg - 2 * part)
		if T.heal > 0:
			A.hp = mini(A.max_hp, A.hp + T.heal)
			VFX.ring(Vector3(A.x, 1.2, 0), Color(1.5, 0.05, 0.02), 2.0, 0.5)
		if A.def.id == "ossirah": B.poison = 150
		G.thr = null
		A.set_state("land"); A.land_lag = 14
		B.state = "juggle"; B.sf = 0; B.no_juggle = true
		B.vy = 0.13; B.y = 0.3
		B.vx = (-1.0 if T.back else 1.0) * A.facing * 0.075
		if T.back: B.x = A.x - A.facing * 0.3
		B.play("air", 3.0)
		B.combo_hits = 0
		if B.hp <= 0 and not G.training: G.on_ko(A, B)
		if G.training and B.hp <= 0: B.hp = 1

static func _throw_hit(A, B, dmg: int) -> void:
	var p: Vector3 = B.rig.joint_world("chest")
	B.hp = maxi(0, B.hp - dmg)
	A.meter = minf(300, A.meter + dmg * 0.5)
	hit_fx(A, B, {power = 1.1, lvl = "mid", fire = A.def.id == "kharos", slash = A.def.id == "nyxara" or A.def.id == "ossirah"}, p, false)
	G.hitstop = 6
	if G.stats: G.stats.dmg[A.idx] += dmg
