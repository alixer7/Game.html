extends RefCounted
## Cinematic timelines: round flow, intros, Wrath supers, executions.

const PZ = preload("res://scripts/pose.gd")
const CD = preload("res://scripts/chardata.gd")
const Rig = preload("res://scripts/rig.gd")
const Geo = preload("res://scripts/geo.gd")
const U = preload("res://scripts/util.gd")

var cur = null       # {t, ev, i, end, lock, on_end, upd, hold}
var tweens := []
const AR_NUM := ["", "الأولى", "الثانية", "الثالثة", "الرابعة", "الخامسة"]

func reset() -> void:
	cur = null
	tweens.clear()

func active() -> bool:
	return cur != null

func holding() -> bool:
	return cur != null and cur.hold > 0

func run(ev: Array, end: int, o := {}) -> void:
	ev.sort_custom(func(a, b): return a[0] < b[0])
	cur = {t = 0, ev = ev, i = 0, end = end, lock = o.get("lock", true), on_end = o.get("on_end", null), upd = o.get("upd", null), hold = 0}

## returns true when the timeline locks normal fighter logic this tick
func tick() -> bool:
	_tweens()
	var c = cur
	if c == null: return false
	if c.hold > 0:
		c.hold -= 1
		return c.lock
	while cur == c and c.i < c.ev.size() and c.ev[c.i][0] <= c.t:
		var e = c.ev[c.i]
		c.i += 1
		e[1].call()
	if cur != c: return c.lock
	if c.upd != null: c.upd.call(c.t)
	c.t += 1
	if c.t > c.end:
		cur = null
		if c.on_end != null: c.on_end.call()
	return c.lock

func tw(o, k: String, to: float, d: int, ease := "io") -> void:
	tweens = tweens.filter(func(x): return not (x.o == o and x.k == k))
	tweens.append({o = o, k = k, a = o.get(k), b = to, d = maxi(1, d), t = 0, ease = ease})

func _tweens() -> void:
	for i in range(tweens.size() - 1, -1, -1):
		var w = tweens[i]
		w.t += 1
		w.o.set(w.k, lerpf(w.a, w.b, U.ease_f(w.ease, float(w.t) / w.d)))
		if w.t >= w.d: tweens.remove_at(i)

# ------------------------------------------------------------------ helpers
func pose(F, m: Dictionary) -> PackedFloat32Array:
	return PZ.P(F.def.S.guard, m)

func pl(F, keys: Array, blend := 4.0) -> void:
	F.play_clip(PZ.clip(keys), blend)

func hold(F, p: PackedFloat32Array, blend := 6.0) -> void:
	F.play_clip(PZ.clip([[0, p]]), blend)

func set_pos(F, x: float, y := 0.0, z := 0.0) -> void:
	F.x = x; F.px = x; F.y = y; F.py = y; F.z = z

func hurt(F, n: int) -> void:
	F.hp = maxi(0, F.hp - n)
	if G.stats: G.stats.dmg[1 - F.idx] += n

func Lp(F, x: float, y: float, z: float) -> Vector3:
	return G.Lp(F, x, y, z)

func jw(F, k: String) -> Vector3:
	return F.rig.joint_world(k)

func impact(at, power := 1.0, o := {}) -> void:
	if cur != null: cur.hold = o.get("hold", roundi(4 + power * 4))
	G.impact = o.get("frames", 3.0 if power > 1.0 else 2.0)
	G.cam_shake(0.3 + power * 0.35)
	if at != null:
		var c: Color = o.get("col", Color(3, 1.4, 1))
		VFX.blood(at, o.get("dir", 0.0), roundi(30 + power * 40), {speed = 3.0 + power * 2.0, size = 0.02, up = 1.2})
		VFX.flash(at, Color(c.r * 0.6, c.g * 0.6, c.b * 0.6), 0.5 + power * 0.35, 0.1)
		VFX.ring(at, o.get("rcol", Color(2, 0.4, 0.2)), 1.2 + power * 0.6, 0.3, "face", 0.6)
		VFX.light_at(at + Vector3(0, 0, 0.5), Color(1, 0.3, 0.2), 6.0 * power)
	SFX.play("heavy", power)
	SFX.play("splat", power)
	if o.get("crack", false): SFX.play("crack", 1.2)

func cine_start(A, B) -> void:
	for F in [A, B]:
		F.set_state("cine"); F.move = null; F.vx = 0.0; F.vy = 0.0; F.kbx = 0.0; F.trail_on = false; F.vanish = false; F.z = 0.0
	for p in G.projs: p.die(false)
	G.projs.clear()
	G.thr = null

func cine_end(A, B, vs := "down") -> void:
	A.y = 0.0
	A.to_neutral()
	A.inv = 10
	if vs == "down":
		B.y = 0.0; B.state = "down"; B.sf = 0; B.down_t = 38; B.play("down", 5.0)
	elif vs == "juggle":
		B.state = "juggle"; B.sf = 0; B.no_juggle = true; B.play("air", 3.0)
	B.combo_hits = 0; B.combo_dmg = 0
	G.cam_fight()
	G.grade_desat = 0.0
	if B.hp <= 0 and G.training == null:
		B.hp = 0
		var ph: String = G.phase
		G.phase = "fight"
		G.on_ko(A, B)
		if G.phase == "fight": G.phase = ph
	if G.training != null and B.hp <= 0: B.hp = 1

func stump(F, sg: String, y: float) -> void:
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.05; sm.height = 0.04; sm.radial_segments = 8; sm.rings = 4
	mi.mesh = sm
	mi.material_override = Mats.M.flesh
	mi.position = Vector3(0, y, 0)
	F.rig.seg[sg].add_child(mi)
	F.rig.wounds.append(mi)

func detach(F, segs: Array, v: Vector3, w: Vector3, r := 0.07, bleed := 3.0) -> RigidBody3D:
	var nodes := []
	for n in segs:
		F.rig.det[n] = true
		nodes.append(F.rig.seg[n])
	return VFX.sever(nodes, v, w, r, bleed)

func burn_mats(F, k: float) -> void:
	for m in F.rig.mats:
		if m is StandardMaterial3D:
			if m.shading_mode == BaseMaterial3D.SHADING_MODE_UNSHADED: continue
			m.albedo_color = (m.get_meta("c0") as Color).lerp(Color(0.02, 0.014, 0.012), minf(1.0, k * 1.3))
			m.emission_enabled = true
			var e := sin(minf(1.0, k) * PI) * 0.5 + 0.12 * k
			m.emission = (m.get_meta("e0") as Color).lerp(Color(0.6, 0.1, 0.01), minf(1.0, k * 2.0)) * e
			m.emission_energy_multiplier = 1.0
		elif m is ShaderMaterial and m.has_meta("c0"):
			var c: Vector3 = m.get_meta("c0")
			m.set_shader_parameter("albedo", c.lerp(Vector3(0.02, 0.014, 0.012), minf(1.0, k * 1.3)))

func tint_mats(F, col: Color, k: float, em := Color.BLACK) -> void:
	for m in F.rig.mats:
		if m is StandardMaterial3D:
			if m.shading_mode == BaseMaterial3D.SHADING_MODE_UNSHADED: continue
			m.albedo_color = (m.get_meta("c0") as Color).lerp(col, k)
			if em != Color.BLACK:
				m.emission_enabled = true
				m.emission = (m.get_meta("e0") as Color).lerp(em, k)
				m.emission_energy_multiplier = 1.0
		elif m is ShaderMaterial and m.has_meta("c0"):
			var c: Vector3 = m.get_meta("c0")
			m.set_shader_parameter("albedo", c.lerp(Vector3(col.r, col.g, col.b), k))

func body_fire(F, n := 4, s := 1.0) -> void:
	var ks := ["head", "chest", "pelvis", "elL", "elR", "wrL", "wrR", "knL", "knR", "anL", "anR"]
	for i in n:
		VFX.fire(jw(F, ks[randi() % ks.size()]) + Vector3(randf_range(-0.08, 0.08), randf_range(-0.1, 0.1), randf_range(-0.08, 0.08)), s)

func later(sec: float, fn: Callable) -> void:
	G.get_tree().create_timer(sec, true, false, true).timeout.connect(fn)

# ------------------------------------------------------------------ round flow
func ready_seq() -> void:
	G.phase = "ready"
	G.cam_fight()
	run([
		[10, func():
			G.ui.announce("ROUND %d" % G.round_n, "الجولة " + AR_NUM[mini(G.round_n, 5)], 1.1)
			SFX.say("Round " + ["one", "two", "three", "four", "five"][mini(G.round_n, 5) - 1])
			SFX.play("bell", 0.8)],
		[82, func():
			G.ui.announce("FIGHT!", "قاتِل!", 0.8)
			SFX.say("Fight!")
			SFX.play("boom", 0.8)
			G.cam_shake(0.3)],
		[100, func(): G.phase = "fight"],
	], 100, {lock = false})

func intro_seq() -> void:
	G.phase = "intro"
	var A = G.f[0]
	var B = G.f[1]
	var ev := []
	for pr in [[A, 0], [B, 116]]:
		var F = pr[0]
		var t0: int = pr[1]
		ev.append([t0, func():
			F.set_state("intro")
			G.cam_shot(Lp(F, 1.6, 1.3, 2.2), Lp(F, 0.1, 1.35 * F.s, 0), 32.0, 0.0)
			G.cam_shot(Lp(F, 2.1, 1.5, 2.6), Lp(F, 0.0, 1.3 * F.s, 0), 34.0, 110.0, "sine")
			_intro(F)
			G.ui.name_card(F)])
		ev.append([t0 + 110, func():
			F.set_state("stand")
			F.play("idle", 10.0)])
	ev.append([228, func():
		G.ui.clear_name_card()
		ready_seq()])
	run(ev, 230, {lock = false})

func _intro(F) -> void:
	var S: Dictionary = F.def.S
	match F.def.id:
		"vorgath":
			pl(F, [[0, S.kneel], [50, S.kneel], [75, pose(F, {"+chest": [-0.3, 0.4, 0], "L": [0.3, 1.3, -0.8], "R": [0.2, 1.3, 0.8], "nod": -0.5}), "out"], [105, S.guard]], 0.0)
			var x: float = F.x
			VFX.fountain(func(): return Vector3(x, 0.05, 0), func(): return Vector3.UP, 1.2, 160, {speed = 3.0})
			VFX.decal(F.x, 0, 2.0, 1.5)
			later(1.1, func(): SFX.voice("vorgath", "roar", 1.2); G.cam_shake(0.4))
		"nyxara":
			F.vanish = true
			later(0.4, func():
				F.vanish = false
				var p: Vector3 = jw(F, "chest")
				for i in 40: VFX.wisp(p + Vector3(randf_range(-0.5, 0.5), randf_range(-1, 1), randf_range(-0.3, 0.3)))
				SFX.play("spectral", 1.0))
			pl(F, [[0, S.crouch], [30, S.crouch], [60, PZ.P(S.dizzy, {"+root": [0, 0.05, 0]})], [90, pose(F, {L = [0.4, 1.6, 0.15], R = [0.42, 1.65, -0.15], LE = [0, -1, -1], RE = [0, -1, 1]}), "out"], [108, S.guard]], 0.0)
			later(1.2, func(): SFX.voice("nyxara", "laugh", 1.0))
		"kharos":
			pl(F, [[0, S.crouch], [25, PZ.P(S.crouch, {R = [0.5, 0.12, 0.1]})], [60, pose(F, {"R": [0.35, 1.5, 0.0], "L": [0.35, 1.48, -0.02], "+chest": [0.1, 0.2, 0]}), "out"], [80, pose(F, {"R": [0.3, 2.15, 0.1], "+chest": [-0.2, 0, 0]})], [108, S.guard]], 0.0)
			var x2: float = F.x
			later(0.45, func():
				for i in 60: VFX.fire(Vector3(x2 + randf_range(-0.8, 0.8), 0, randf_range(-0.5, 0.5)), 2.2, Vector3(0, randf_range(1, 4), 0))
				VFX.ring(Vector3(x2, 0.05, 0), Color(3, 0.8, 0.2), 4.0, 0.5, "ground")
				SFX.play("fire", 1.2); SFX.play("boom", 0.6); G.cam_shake(0.3))
		"ossirah":
			var bow := pose(F, {"+hip": [0.25, 0, 0], "+chest": [0.45, 0.2, 0], "L": [0.35, 1.2, 0.05], "R": [-0.35, 1.1, 0.35], "nod": 0.3})
			pl(F, [[0, S.guard], [40, bow, "io"], [80, bow], [108, S.guard]], 0.0)
			var p: Vector3 = jw(F, "chest")
			for i in 90: VFX.fly(p, randf_range(0.3, 1.4))
			SFX.play("swarm", 1.0)
			later(0.9, func(): SFX.voice("ossirah", "laugh", 1.0))

func round_ko(A, B, time_over: bool) -> void:
	G.phase = "ko"
	var final: bool = G.wins[A.idx] + 1 >= 2
	B.dead = not final
	G.slowmo(0.3, 1.4)
	SFX.voice(B.def.id, "die", 1.1)
	VFX.screen_blood(2, 0.5)
	G.arena.flash = 1.0
	G.cam_shake(0.6)
	if time_over: G.ui.announce("TIME", "انتهى الوقت", 1.2)
	G.cam_shot(func(): return Lp(B, -1.2, 1.1 + B.y * 0.5, 2.3), func(): return Vector3(B.x, 0.9 + B.y * 0.6, 0), 34.0, 40.0, "out")
	run([
		[100, func():
			G.wins[A.idx] += 1
			G.ui.update_wins(G.wins)
			if final:
				end_them(A, B)
				return
			G.cam_fight()
			if A.state != "attack":
				A.set_state("win")
				A.play_clip(PZ.clip([[0, A.def.S.guard], [14, CD.victory(A.def.id, A.def.S), "out"], [80, CD.victory(A.def.id, A.def.S)]]), 8.0)
			SFX.voice(A.def.id, "laugh", 0.8)],
		[220, func():
			if not final:
				G.round_n += 1
				G.start_round(false)],
	], 222, {lock = false})

func end_them(A, B) -> void:
	G.phase = "endthem"
	G.end_t = 8 * 60
	G.end_a = A
	G.end_b = B
	B.hp = 0
	B.dead = false
	G.cam_fight()
	G.slowmo(1.0, 0.0)
	G.ui.announce("END THEM", "أجهِز على خصمك!", 1.8)
	SFX.say("End them!")
	SFX.play("boom", 1.0)
	if B.state != "down" and B.state != "juggle":
		B.set_state("dizzy"); B.play("dizzy", 12.0)
	if A.state == "win": A.to_neutral()
	if A.ai == null: G.ui.show_exec_hint(A)

func finish_match(A, B, executed: bool) -> void:
	if G.phase == "over": return
	G.phase = "over"
	G.ui.hide_exec_hint()
	G.grade_desat = 0.0
	var flawless: bool = G.stats != null and G.stats.dmg[B.idx] == 0
	A.to_neutral()
	A.set_state("win")
	A.play_clip(PZ.clip([[0, A.def.S.guard], [16, CD.victory(A.def.id, A.def.S), "out"], [200, CD.victory(A.def.id, A.def.S)]]), 8.0)
	G.cam_shot(Lp(A, 1.5, 1.35 * A.s, 2.6), Lp(A, 0, 1.3 * A.s, 0), 32.0, 50.0, "io", A.facing * 0.03)
	later(0.3, func():
		G.ui.announce(A.def.name + " WINS", "انتصر " + A.def.title_ar, 2.4, true)
		SFX.say(A.def.name + " wins")
		SFX.voice(A.def.id, "laugh", 1.0))
	if flawless:
		later(2.9, func():
			G.ui.announce("UNTOUCHED", "دون خدش", 1.6)
			SFX.say("Untouched"))
	later(4.7 if flawless else 3.2, func(): G.ui.show_post_match(A))

# ------------------------------------------------------------------ WRATH
func super_flash(F) -> void:
	G.freeze = 32
	G.freeze_f = F
	G.grade_desat = 0.65
	G.ui.show_super_name(F.def.sup.name, F.def.sup.ar)
	var p: Vector3 = jw(F, "chest")
	VFX.ring(p, Color(2.5, 0.6, 0.2), 4.5, 0.6)
	VFX.flash(p, Color(4, 2, 1), 3.0, 0.3)
	for i in 36: VFX.fire(p + Vector3(randf_range(-0.6, 0.6), randf_range(-1.2, 0.8), randf_range(-0.4, 0.4)), 1.4, Vector3(0, randf_range(0.5, 2.0), 0))
	SFX.play("boom", 0.9)
	SFX.voice(F.def.id, "roar", 1.0)
	G.cam_shake(0.4)
	G.cam_shot(Lp(F, 1.1, 1.45 * F.s, 2.4), Lp(F, 0, 1.35 * F.s, 0), 30.0, 10.0, "out", F.facing * -0.05)

func end_super_flash() -> void:
	G.grade_desat = 0.0
	if G.cam.mode == "shot" and cur == null: G.cam_fight()

func start_super_cine(A, B) -> void:
	cine_start(A, B)
	G.grade_desat = 0.15
	if G.stats: G.stats.supers[A.idx] += 1
	match A.def.id:
		"kharos": _super_kharos(A, B)
		"vorgath": _super_vorgath(A, B)
		"nyxara": _super_nyxara(A, B)
		"ossirah": _super_ossirah(A, B)

func _super_kharos(A, B) -> void:
	var f: int = A.facing
	set_pos(B, A.x + f * 0.72 * A.s)
	B.facing = -f
	var SB: Dictionary = B.def.S
	var SA: Dictionary = A.def.S
	var upd := func(t):
		if t > 26 and t < 88:
			body_fire(B, 4, 1.4)
			if t % 6 == 0:
				hurt(B, 1)
				B.flinch_v += randf_range(-3, 3)
	run([
		[0, func():
			hold(A, pose(A, {"+root": [0.15, -0.08, 0], "+hip": [0.2, 0.35, 0], "+chest": [0.25, 0.5, 0], "R": [0.68, 1.12, 0], "RE": [0, -1, 0.3], "L": [0.25, 1.45, -0.2]}), 3.0)
			hold(B, PZ.P(SB.hitMid, {"+root": [-0.05, -0.08, 0], "+spine": [0.2, 0, 0]}), 3.0)
			G.cam_shot(Lp(A, 0.5, 1.0, 2.8), Lp(A, 0.55, 1.2, 0), 34.0)],
		[4, func():
			var p: Vector3 = jw(B, "chest")
			impact(p, 1.2, {dir = f, col = Color(5, 1.6, 0.3)})
			for i in 24: VFX.fire(p, 1.6, Vector3(f * randf_range(1, 4), randf_range(-1, 2), 0))
			hurt(B, 70)
			SFX.voice(B.def.id, "hurt", 1.0)],
		[26, func():
			hold(A, pose(A, {"+root": [0.05, 0.05, 0], "+chest": [-0.15, 0.3, 0], "R": [0.6, 2.1, 0.02], "RE": [0, -1, 0.6], "L": [0.2, 1.5, -0.25]}), 10.0)
			hold(B, SB.lifted, 10.0)
			tw(B, "y", 0.6, 14, "out")
			tw(B, "x", A.x + f * 0.6 * A.s, 14)
			G.cam_shot(Lp(A, 2.2, 0.45, 2.8), Lp(A, 0.55, 1.7, 0), 38.0, 16.0, "io", f * 0.06)
			SFX.voice(A.def.id, "roar", 1.0)],
		[40, func():
			SFX.play("fire", 1.2)
			SFX.voice(B.def.id, "scream", 1.0)],
		[86, func():
			hold(A, pose(A, {"root": [0.2, 0.62, 0], "+hip": [0.5, 0.3, 0], "+spine": [0.3, 0, 0], "+chest": [0.35, 0.3, 0], "R": [0.85, 0.35, 0.02], "L": [0.3, 1.0, -0.3], "lf": [0.5, 0.08, -0.2], "rf": [-0.35, 0.08, 0.22], "nod": 0.4}), 5.0)
			hold(B, SB.down, 5.0)
			tw(B, "y", 0.0, 6, "in")
			tw(B, "x", A.x + f * 0.95 * A.s, 6)
			G.cam_shot(Lp(A, 0.8, 3.4, 2.75), Lp(A, 0.9, 0, 0), 40.0, 0.0, "io", f * 0.2)],
		[92, func():
			var p := Vector3(B.x, 0.3, 0)
			impact(p, 1.6, {col = Color(5, 1.6, 0.3), crack = true})
			VFX.ring(Vector3(B.x, 0.05, 0), Color(3, 0.8, 0.2), 5.0, 0.6, "ground")
			for i in 70: VFX.fire(Vector3(B.x + randf_range(-0.6, 0.6), randf_range(0, 0.4), randf_range(-0.4, 0.4)), 2.2, Vector3(0, randf_range(2, 6), 0))
			SFX.play("boom", 1.2)
			hurt(B, 190)
			VFX.screen_blood(3, 0.7)],
		[120, func():
			hold(A, SA.guard, 12.0)
			G.cam_shot(Lp(A, 0.5, 1.4, 4.5), Lp(A, 0.5, 1.0, 0), 36.0, 20.0)],
	], 140, {upd = upd, on_end = func(): cine_end(A, B)})

func _super_vorgath(A, B) -> void:
	var f: int = A.facing
	var SB: Dictionary = B.def.S
	set_pos(B, A.x + f * 0.62 * A.s)
	B.facing = -f
	var lance: Material = Mats.std({color = Color(0.3, 0.0, 0.01), r = 0.15, cc = 1.0, emit = Color(0.5, 0, 0.01), ee = 1.0})
	run([
		[0, func():
			hold(A, pose(A, {"+root": [0.05, 0.05, 0], "+chest": [-0.1, 0.2, 0], "L": [0.62, 1.75, -0.12], "R": [0.6, 1.72, 0.12], "LE": [0, -1, -0.8], "RE": [0, -1, 0.8]}), 3.0)
			hold(B, SB.grabbed, 3.0)
			G.cam_shot(Lp(A, 0.34, 1.6, 2.75), Lp(A, 0.4, 1.6, 0), 32.0)],
		[8, func(): hold(A, pose(A, {"+root": [0.12, 0, 0], "+chest": [0.3, 0.2, 0], "+neck": [0.4, 0, 0], "L": [0.62, 1.7, -0.12], "R": [0.6, 1.68, 0.12]}), 3.0)],
		[12, func():
			impact(jw(B, "head"), 1.2, {dir = f, crack = true})
			hurt(B, 60)
			SFX.voice(B.def.id, "hurt", 1.0)],
		[34, func():
			hold(A, pose(A, {"+root": [0, 0.05, 0], "+chest": [-0.25, 0.2, 0], "L": [0.15, 2.3, -0.18], "R": [0.12, 2.28, 0.18], "LE": [0, 0, -1], "RE": [0, 0, 1], "nod": -0.4}), 14.0)
			hold(B, PZ.P(SB.down, {root = [0, 0.14, 0]}), 14.0)
			tw(B, "y", 2.1, 16, "out")
			tw(B, "x", A.x + f * 0.1, 16)
			G.cam_shot(Lp(A, 2.53, 0.3, 3.24), Lp(A, 0.2, 1.8, 0), 40.0, 18.0, "io", f * 0.08)
			SFX.voice(A.def.id, "roar", 1.1)],
		[66, func():
			hold(A, pose(A, {"root": [0, 0.6, 0], "+hip": [0.15, 0, 0], "+chest": [0.2, 0.3, 0], "lf": [0.45, 0.08, -0.2], "rf": [-0.45, 0.05, 0.2], "lk": [1, 0.4, -0.2], "rk": [0, -1, 0.2], "rfa": [0, 0.6, 0], "L": [0.45, 1.25, -0.15], "R": [0.42, 1.2, 0.2]}), 5.0)
			hold(B, PZ.P(SB.down, {root = [0, 0.14, 0], hip = [-1.4, 0, 0], spine = [-0.7, 0, 0], chest = [-0.5, 0, 0], neck = [-0.4, 0, 0], free = 1, head = [-0.4, 0, 0], lf = [0.55, -0.4, -0.15], rf = [0.5, -0.35, 0.18]}), 5.0)
			tw(B, "y", 0.62, 6, "in")
			tw(B, "x", A.x + f * 0.4, 6)
			G.cam_shot(Lp(A, 1.03, 0.7, 2.75), Lp(A, 0.35, 0.9, 0), 30.0, 0.0, "io", f * -0.12)],
		[72, func():
			impact(jw(B, "chest"), 1.6, {crack = true})
			SFX.play("crack", 1.5)
			hurt(B, 120)
			VFX.fountain(func(): return jw(B, "head"), func(): return Vector3.UP, 0.8, 90, {speed = 2.2})
			SFX.voice(B.def.id, "scream", 1.0)
			VFX.screen_blood(2, 0.6)],
		[108, func():
			hold(A, pose(A, {"+chest": [0.2, 0.6, 0], "L": [0.85, 1.3, -0.1], "R": [0.8, 1.25, 0.2]}), 6.0)
			hold(B, SB.airHit, 6.0)
			tw(B, "x", B.x + f * 1.7, 14, "out")
			tw(B, "y", 1.1, 8, "out")
			G.cam_shot(Lp(A, 1.2, 1.2, 4.6), Lp(A, 1.4, 1.0, 0), 38.0, 14.0)],
		[118, func():
			for i in 6: VFX.spike(B.x + randf_range(-0.35, 0.35), randf_range(-0.25, 0.25), randf_range(1.4, 2.3), {r = 0.12, grow = 0.08, life = 1.1, mat = lance})
			impact(jw(B, "chest"), 1.4, {hold = 10})
			hurt(B, 100)
			SFX.voice(B.def.id, "scream", 1.0)
			tw(B, "y", 1.4, 4, "out")],
		[150, func():
			tw(B, "y", 0.0, 10, "in")
			hold(B, SB.down, 8.0)],
	], 172, {on_end = func(): cine_end(A, B)})

func _super_nyxara(A, B) -> void:
	var f: int = A.facing
	var SA: Dictionary = A.def.S
	var SB: Dictionary = B.def.S
	set_pos(B, A.x + f * 0.75 * A.s)
	B.facing = -f
	var ev := []
	var slashes := [[1, "hitHi"], [-1, "hitHi2"], [1, "hitMid"], [-1, "hitHi"], [1, "hitHi2"], [-1, "hitMid"]]
	var angs := [[0.9, 1.6, 2.6], [-0.9, 1.2, 2.6], [0.5, 2.3, 2.0], [-1.6, 1.3, 1.8], [1.4, 0.9, 2.2], [0.0, 1.4, 3.0]]
	for k in 6:
		var side: int = slashes[k][0]
		var hp: String = slashes[k][1]
		var ang: Array = angs[k]
		ev.append([k * 9, func():
			var sx: int = side * f
			set_pos(A, B.x - sx * 0.8 * A.s)
			A.facing = sx
			hold(A, pose(A, {"+root": [0.12, -0.08, 0], "+hip": [0.1, 0.9 if k % 2 == 1 else -0.9, 0], "+chest": [0.1, 0.6 if k % 2 == 1 else -0.6, 0], "L": [0.75, 1.0, 0.35] if k % 2 == 1 else [0.8, 1.8, -0.3], "R": [0.6, 1.9, -0.2] if k % 2 == 1 else [0.7, 1.1, 0.4]}), 2.0)
			hold(B, SB[hp], 2.0)
			A.trail_on = true
			later(0.09, func(): A.trail_on = false)
			var p: Vector3 = jw(B, "chest")
			VFX.blood(p + Vector3(0, randf_range(-0.3, 0.3), 0), -sx, 26, {speed = 3.5, size = 0.016})
			SFX.play("slice", 1.0)
			hurt(B, 20)
			G.impact = 1.0
			G.cam_shot(Lp(B, ang[0], ang[1], ang[2]), Lp(B, 0, 1.3, 0), 32.0, 0.0, "io", 0.1 if k % 2 == 1 else -0.1)])
	ev.append([56, func():
		set_pos(A, B.x + f * -0.62 * A.s)
		A.facing = f
		B.facing = -f
		hold(A, pose(A, {"+root": [0.15, -0.04, 0], "+chest": [0.2, 0, 0], "L": [0.55, 1.38, -0.04], "R": [0.55, 1.32, 0.06], "LE": [0, -1, -0.9], "RE": [0, -1, 0.9], "lw": [-0.3, 0, 0], "rw": [-0.3, 0, 0]}), 3.0)
		hold(B, PZ.P(SB.hitMid, {"+chest": [0.1, 0, 0], "L": [0.1, 0.9, -0.3], "R": [0.05, 0.85, 0.3]}), 3.0)
		G.cam_shot(Lp(A, 0.57, 1.3, 2.75), Lp(A, 0.5, 1.3, 0), 30.0)])
	ev.append([60, func():
		impact(jw(B, "chest"), 1.4, {dir = f, hold = 9})
		VFX.fountain(func(): return jw(B, "chest") + Vector3(f * 0.2, 0, 0), func(): return Vector3(f, 0.3, 0), 1.2, 160, {speed = 3.0})
		hurt(B, 70)
		SFX.voice(B.def.id, "scream", 1.0)])
	ev.append([90, func():
		tw(B, "y", 0.35, 12, "out")
		hold(A, pose(A, {"+chest": [-0.15, 0, 0], "L": [0.5, 1.7, -0.04], "R": [0.5, 1.65, 0.06]}), 10.0)
		G.cam_shot(Lp(A, 1.84, 0.5, 2.7), Lp(A, 0.5, 1.5, 0), 36.0, 14.0)])
	ev.append([110, func():
		hold(A, pose(A, {"+chest": [-0.1, 0, 0], "L": [0.35, 1.6, -0.85], "R": [0.35, 1.55, 0.85], "LE": [0, 0, -1], "RE": [0, 0, 1]}), 3.0)
		var p: Vector3 = jw(B, "chest")
		impact(p, 1.6, {hold = 8})
		VFX.blood(p, 0.0, 70, {speed = 5.0, spread = 1.4, vel = Vector3(0, 0, 2)})
		VFX.blood(p, 0.0, 70, {speed = 5.0, spread = 1.4, vel = Vector3(0, 0, -2)})
		hurt(B, 50)
		VFX.screen_blood(3, 0.8)])
	ev.append([128, func():
		pl(A, PZ.fkick(SA.guard, {startup = 5, active = 4, recovery = 14}), 2.0)
		hold(B, SB.airHit, 3.0)
		tw(B, "x", B.x + f * 2.2, 18, "out")
		tw(B, "y", 1.0, 10, "out")
		impact(jw(B, "chest"), 1.0, {hold = 4})
		hurt(B, 40)
		G.cam_shot(Lp(A, 1.3, 1.3, 5.0), Lp(A, 1.4, 1.0, 0), 38.0, 16.0)])
	ev.append([148, func(): tw(B, "y", 0.0, 10, "in")])
	run(ev, 162, {on_end = func(): cine_end(A, B)})

func _super_ossirah(A, B) -> void:
	var f: int = A.facing
	var SA: Dictionary = A.def.S
	var SB: Dictionary = B.def.S
	set_pos(B, A.x + f * 0.78 * A.s)
	B.facing = -f
	var upd := func(t):
		if t > 38 and t < 80:
			tint_mats(B, Color(0.35, 0.55, 0.2), minf(1.0, (t - 38) / 40.0) * 0.6, Color(0.1, 0.4, 0.0))
			B.flinch_v += randf_range(-6, 6)
			if t % 4 == 0: VFX.plague(jw(B, "head"), 0.8)
		if t == 150: tint_mats(B, Color.WHITE, 0.0)
	var fin := func():
		tint_mats(B, Color.WHITE, 0.0)
		cine_end(A, B)
	run([
		[0, func():
			hold(A, pose(A, {"+root": [0.1, -0.04, 0], "+chest": [0.2, 0.4, 0], "R": [0.7, 1.7, 0.1], "RE": [0, 0.5, 1]}), 3.0)
			hold(B, SB.hitHi, 3.0)
			G.cam_shot(Lp(A, 0.46, 1.6, 2.75), Lp(A, 0.6, 1.5, 0), 32.0)],
		[5, func():
			impact(jw(B, "shL"), 1.1, {dir = -f})
			hurt(B, 60)
			SFX.play("slice", 1.2)
			SFX.voice(B.def.id, "hurt", 1.0)],
		[20, func():
			tw(B, "x", A.x + f * 0.55 * A.s, 10)
			hold(B, SB.grabbed, 8.0)
			hold(A, pose(A, {"+chest": [-0.1, 0.2, 0], "R": [0.5, 1.6, 0.15], "L": [0.25, 1.4, -0.2]}), 8.0)],
		[34, func():
			hold(A, pose(A, {"+root": [0.05, 0, 0], "+chest": [0.15, -0.3, 0], "L": [0.55, 1.62, -0.02], "LE": [0, -0.5, -1], "R": [0.45, 1.55, 0.15]}), 3.0)
			G.cam_shot(Lp(A, 1.03, 1.7, 2.75), Lp(A, 0.5, 1.6, 0), 30.0, 0.0, "io", f * 0.1)],
		[38, func():
			var p: Vector3 = jw(B, "neck")
			VFX.flash(p, Color(1, 4, 0.6), 1.2)
			for i in 30: VFX.plague(p, 1.0)
			hurt(B, 50)
			SFX.voice(B.def.id, "scream", 1.0)
			G.impact = 2.0],
		[44, func():
			hold(A, SA.taunt, 10.0)
			tw(A, "x", A.x - f * 0.4, 12)],
		[78, func():
			hold(B, pose(B, {"+chest": [-0.4, 0, 0], "+spine": [-0.2, 0, 0], "L": [-0.1, 1.7, -0.7], "R": [-0.1, 1.7, 0.7], "LE": [0, -1, -1], "RE": [0, -1, 1], "nod": -0.6}), 6.0)
			var p: Vector3 = jw(B, "chest")
			for i in 140: VFX.fly(p, randf_range(0.3, 1.6))
			for i in 50: VFX.plague(p + Vector3(0, randf_range(-0.6, 0.6), 0), 2.2)
			VFX.blood(p + Vector3(0, 0.3, 0), 0.0, 70, {speed = 4.0, spread = 1.2})
			SFX.play("swarm", 1.6)
			SFX.play("boom", 0.7)
			impact(p, 1.4, {rcol = Color(1, 3, 0.4)})
			hurt(B, 80)
			G.cam_shot(Lp(B, 1.84, 1.2, 2.97), Lp(B, 0, 1.3, 0), 38.0, 40.0, "io", -0.08)],
		[126, func():
			tw(A, "x", B.x - f * 0.9 * B.s, 6)
			pl(A, PZ.fkick(SA.guard, {startup = 5, active = 4, recovery = 14}), 2.0)],
		[131, func():
			impact(jw(B, "chest"), 1.2)
			hold(B, SB.airHit, 3.0)
			tw(B, "x", B.x + f * 2.2, 18, "out")
			tw(B, "y", 1.0, 10, "out")
			hurt(B, 90)
			B.poison = 300
			G.cam_shot(Lp(A, 1.3, 1.3, 5.0), Lp(A, 1.4, 1.0, 0), 38.0, 16.0)],
		[150, func(): tw(B, "y", 0.0, 10, "in")],
	], 164, {upd = upd, on_end = fin})

# ------------------------------------------------------------------ EXECUTIONS
func start_execution(A, B) -> void:
	G.phase = "execution"
	cine_start(A, B)
	G.ui.announce("", "", 0.1)
	G.ui.hide_exec_hint()
	SFX.stop_music()
	SFX.voice(A.def.id, "laugh", 1.0)
	G.slowmo(1.0, 0.0)
	G.grade_desat = 0.25
	G.arena.flash = 1.0
	match A.def.id:
		"vorgath": _exec_vorgath(A, B)
		"nyxara": _exec_nyxara(A, B)
		"kharos": _exec_kharos(A, B)
		"ossirah": _exec_ossirah(A, B)

func exec_done(A, B) -> void:
	G.grade_desat = 0.0
	G.ui.announce("EXECUTION", "إعدام", 2.6)
	SFX.say("Execution")
	SFX.play("boom", 1.0)
	G.cam_shake(0.4)
	later(2.6, func(): finish_match(A, B, true))

func _exec_vorgath(A, B) -> void:
	var f: int = A.facing
	var SB: Dictionary = B.def.S
	var lance: Material = Mats.std({color = Color(0.3, 0.0, 0.01), r = 0.15, cc = 1.0, emit = Color(0.5, 0, 0.01), ee = 1.0})
	var upd := func(t):
		if t > 128 and t % 2 == 0: VFX.drop(A.rig.seg["hdL"].global_transform * Vector3(0, 0.1, 0), Vector3(0, -0.5, 0), 0.012, 0.9)
	run([
		[0, func():
			tw(A, "x", B.x - f * 0.7 * A.s, 18)
			A.play("walk", 4.0)
			G.cam_shot(Lp(A, 1, 1.6, 5), Lp(A, 0.5, 1.2, 0), 34.0, 20.0)],
		[18, func():
			hold(A, pose(A, {"+chest": [-0.05, 0.1, 0], "L": [0.64, 1.7, -0.05], "LE": [0, -1, -0.8]}), 6.0)
			hold(B, SB.lifted, 8.0)
			tw(B, "y", 0.55, 16, "out")
			tw(B, "x", A.x + f * 0.62 * A.s, 12)
			SFX.voice(B.def.id, "hurt", 1.0)],
		[26, func():
			hold(A, pose(A, {"+chest": [-0.12, 0.15, 0], "L": [0.62, 2.25, -0.04], "LE": [0, -1, -1], "R": [0.3, 1.3, 0.35]}), 14.0)
			G.cam_shot(Lp(A, 2.4, 0.3, 2.9), Lp(A, 0.5, 1.8, 0), 42.0, 30.0, "io", f * 0.06)
			SFX.voice(A.def.id, "roar", 1.2)],
		[58, func():
			G.slowmo(0.55, 1.6)
			for i in 6:
				var a := i / 6.0 * TAU
				VFX.spike(B.x + cos(a) * 0.32, sin(a) * 0.3, randf_range(2.0, 2.9), {r = randf_range(0.08, 0.13), grow = 0.07, life = 30.0, rx = sin(a) * -0.35, rz = cos(a) * 0.35 * f, mat = lance})
			tw(B, "y", 1.0, 6, "out")],
		[61, func():
			impact(jw(B, "chest"), 1.8, {hold = 12, crack = true})
			for k in ["chest", "pelvis", "neck"]:
				VFX.fountain(func(): return jw(B, k), func(): return Vector3(randf_range(-0.5, 0.5), 1, randf_range(-0.5, 0.5)), 2.5, 70, {speed = 2.6})
			SFX.voice(B.def.id, "scream", 1.2)
			VFX.screen_blood(5, 0.8)
			hold(B, PZ.P(SB.limp, {"+hip": [-0.2, 0, 0], "+chest": [-0.3, 0, 0], "neck": [-0.4, 0, 0], "free": 1, "head": [-0.5, 0, 0], "L": [0.1, 1.9, -0.6], "R": [0, 1.8, 0.6], "LE": [0, 0, -1], "RE": [0, 0, 1]}), 3.0)
			G.cam_shot(Lp(B, 1.5, 1.6, 2.75), Lp(B, 0, 1.6, 0), 34.0, 0.0, "io", -0.08)],
		[100, func():
			hold(A, pose(A, {"+chest": [0.1, 0.3, 0], "L": [0.6, 2.25, -0.06], "R": [0.62, 2.25, 0.08], "RE": [0, -1, 1]}), 8.0)
			G.cam_shot(Lp(A, 0.69, 2.1, 2.75), Lp(A, 0.6, 2.2, 0), 32.0, 14.0)],
		[118, func():
			var h: Node3D = B.rig.seg["head"]
			var gt := h.global_transform
			h.get_parent().remove_child(h)
			A.rig.seg["hdL"].add_child(h)
			h.global_transform = gt
			B.rig.det["head"] = true
			stump(B, "neck", Rig.NECK_LEN)
			impact(jw(B, "neck"), 2.0, {hold = 14, crack = true, frames = 4.0})
			SFX.play("crack", 1.8)
			VFX.fountain(func(): return jw(B, "neck") + Vector3(0, 0.06, 0), func(): return Vector3(randf_range(-0.2, 0.2), 1, randf_range(-0.2, 0.2)), 3.5, 200, {speed = 5.5, size = 0.018})
			hold(B, SB.limp, 6.0)
			VFX.screen_blood(7, 1.1)],
		[128, func():
			hold(A, pose(A, {"+chest": [-0.35, 0.2, 0], "L": [0.3, 2.4, -0.06], "LE": [0, -1, -1], "R": [0.2, 1.2, 0.5], "nod": -0.5}), 18.0)
			G.cam_shot(Lp(A, 1.61, 0.2, 2.75), Lp(A, 0.3, 2.0, 0), 44.0, 30.0, "io", f * 0.08)],
		[150, func():
			SFX.voice(A.def.id, "roar", 1.4)
			G.cam_shake(0.5)],
	], 240, {upd = upd, on_end = func(): exec_done(A, B)})

func _exec_nyxara(A, B) -> void:
	var f: int = A.facing
	var SA: Dictionary = A.def.S
	var SB: Dictionary = B.def.S
	var stiff := PZ.P(SB.guard, {"+root": [0, 0.03, 0], "+chest": [-0.08, 0, 0], "L": [0.05, 0.95, -0.3], "R": [0, 0.92, 0.3], "LE": [0, -1, -0.3], "RE": [0, -1, 0.3], "lf": [0.12, 0.08, -0.14], "rf": [-0.1, 0.08, 0.14]})
	var slash_mat := Mats.glow(Color(1, 1.12, 1.5), 4.0)
	slash_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	slash_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	var ev := [
		[0, func():
			hold(A, SA.crouch, 6.0)
			G.cam_shot(Lp(A, 1.2, 1.3, 4.8), Lp(A, 1.2, 1.2, 0), 34.0, 10.0)],
		[8, func():
			A.vanish = true
			var p: Vector3 = jw(A, "chest")
			for i in 36: VFX.wisp(p + Vector3(randf_range(-0.4, 0.4), randf_range(-0.9, 0.6), randf_range(-0.3, 0.3)))
			SFX.play("spectral", 1.0)
			hold(B, stiff, 10.0)],
	]
	for k in 9:
		ev.append([16 + k * 5, func():
			var p: Vector3 = jw(B, ["chest", "pelvis", "neck", "shL", "shR", "knL"][randi() % 6])
			var a := randf() * TAU
			var q := QuadMesh.new()
			q.size = Vector2(2.6, 0.025)
			var m := MeshInstance3D.new()
			m.mesh = q
			m.material_override = slash_mat
			m.position = p
			m.rotation = Vector3(0, 0, a)
			VFX.mesh_fx(m, 0.25, func(o, u, _dt): o.scale = Vector3(1.0 + u, 1.0 - u * 0.8, 1.0))
			VFX.blood(p, cos(a), 6, {speed = 1.5})
			SFX.play("slice", 0.8)
			G.impact = 1.0
			G.cam_shake(0.15)])
	ev.append([62, func():
		set_pos(A, B.x + B.facing * -1.5)
		A.facing = B.facing
		A.vanish = false
		hold(A, PZ.P(SA.guard, {"+root": [0, -0.05, 0], "+chest": [0.1, -0.2, 0], "L": [0.35, 1.25, 0.2], "R": [0.3, 1.3, -0.15], "LE": [0, -1, -1], "RE": [0, -1, 1], "nod": 0.2}), 4.0)
		G.cam_shot(Lp(B, -1.4, 1.2, 3.0), Lp(B, -0.6, 1.2, 0), 36.0)
		SFX.play("spectral", 0.6)])
	ev.append([96, func(): G.cam_shot(Lp(B, 1.3, 1.3, 2.8), Lp(B, 0, 1.2, 0), 34.0, 0.0, "io", -0.05)])
	ev.append([104, func():
		stump(B, "neck", Rig.NECK_LEN)
		detach(B, ["head"], Vector3(B.facing * 0.6, 0.5, randf_range(-0.3, 0.3)), Vector3(randf_range(-4, 4), randf_range(-4, 4), randf_range(-4, 4)), 0.09, 4.0)
		VFX.fountain(func(): return jw(B, "neck") + Vector3(0, 0.05, 0), func(): return Vector3(randf_range(-0.2, 0.2), 1, randf_range(-0.2, 0.2)), 4.0, 160, {speed = 4.5})
		SFX.play("splat", 1.2); SFX.play("crack", 1.0)
		G.impact = 1.0])
	ev.append([114, func():
		detach(B, ["uaL", "faL", "hdL"], Vector3(-B.facing * 0.5, 0.2, -0.6), Vector3(randf_range(-4, 4), randf_range(-4, 4), randf_range(-4, 4)))
		VFX.fountain(func(): return jw(B, "shL"), func(): return Vector3(0, 0.4, -1), 3.0, 90, {speed = 3.0})
		SFX.play("splat", 1.2)])
	ev.append([122, func():
		detach(B, ["uaR", "faR", "hdR"], Vector3(-B.facing * 0.4, 0.2, 0.7), Vector3(randf_range(-4, 4), randf_range(-4, 4), randf_range(-4, 4)))
		VFX.fountain(func(): return jw(B, "shR"), func(): return Vector3(0, 0.4, 1), 3.0, 90, {speed = 3.0})
		SFX.play("splat", 1.2)])
	ev.append([134, func():
		var p: Vector3 = jw(B, "chest") + Vector3(0, -0.3, 0)
		detach(B, ["chest", "neck"], Vector3(B.facing * 1.2, 0.9, 0.2), Vector3(randf_range(-3, 3), randf_range(-3, 3), randf_range(-3, 3)), 0.15)
		VFX.fountain(func(): return p, func(): return Vector3.UP, 4.0, 150, {speed = 4.0})
		G.slowmo(0.5, 1.2)
		VFX.screen_blood(5, 1.0)
		G.cam_shake(0.3)
		SFX.play("splat", 1.4)])
	ev.append([140, func():
		hold(B, PZ.P(SB.kneel, {L = [0, 0.6, -0.2], R = [0, 0.6, 0.2]}), 18.0)
		tw(B, "y", -0.1, 20, "in")])
	ev.append([162, func(): detach(B, ["pelvis", "spine", "thL", "snL", "ftL", "thR", "snR", "ftR"], Vector3(B.facing * 0.3, 0.3, 0), Vector3(randf_range(-2, 2), randf_range(-2, 2), randf_range(-2, 2)), 0.15, 2.0)])
	ev.append([170, func():
		VFX.decal(B.x, 0, 2.4, 1.5)
		VFX.decal(B.x + 0.4, 0.2, 1.6, 1.5)
		hold(A, PZ.P(SA.guard, {"+chest": [-0.15, 0.25, 0], "L": [0.4, 1.55, 0.15], "R": [0.42, 1.6, -0.15], "LE": [0, -1, -1], "RE": [0, -1, 1], "nod": -0.2}), 10.0)
		G.cam_shot(Lp(A, 1.61, 1.5, 2.97), Lp(A, 0, 1.4, 0), 32.0, 30.0, "io", 0.05)
		SFX.voice(A.def.id, "laugh", 1.0)])
	run(ev, 250, {on_end = func(): exec_done(A, B)})

func _exec_kharos(A, B) -> void:
	var f: int = A.facing
	var SB: Dictionary = B.def.S
	var st := {crumble = -1}
	var char_mat: Material = Mats.M.char
	var order := ["head", "neck", "uaL", "uaR", "faL", "faR", "hdL", "hdR", "chest", "spine", "pelvis", "thL", "thR", "snL", "snR", "ftL", "ftR"]
	var upd := func(t):
		if t > 26 and t < 110:
			burn_mats(B, minf(1.0, (t - 26) / 60.0))
			body_fire(B, 5, 1.6)
			B.flinch_v += randf_range(-5, 5)
			if t % 3 == 0: VFX.smoke(Vector3(B.x + randf_range(-0.2, 0.2), B.y + randf_range(0.6, 1.8), randf_range(-0.2, 0.2)), 1.2)
		if st.crumble >= 0:
			st.crumble += 1
			var i: int = st.crumble / 3
			if i < order.size() and st.crumble % 3 == 0:
				var sg: MeshInstance3D = B.rig.seg[order[i]]
				if sg.visible:
					var p := sg.global_position
					sg.visible = false
					for k in 22: VFX._p("smoke", p + Vector3(randf_range(-0.12, 0.12), randf_range(-0.12, 0.12), randf_range(-0.1, 0.1)), Vector3(f * randf_range(0.2, 2.0), randf_range(-0.5, 1.0), randf_range(-0.5, 0.5)), 2.0, 2.0, randf_range(1.0, 2.5), randf_range(0.03, 0.08), 0.1, Color(0.08, 0.07, 0.07, 0.9), Color(0.2, 0.2, 0.2, 0))
					for k in 3: VFX.gib(p, Vector3(f * randf_range(0.5, 2), randf_range(0, 2), randf_range(-1, 1)), randf_range(0.03, 0.06), char_mat)
					for k in 4: VFX.ember(p)
					SFX.play("crack", 0.4)
			if i == order.size():
				for rb in B.rig.ribbons: rb[0].visible = false
				for lk in B.rig.links: lk[0].visible = false
				for k in 14: VFX.smoke(Vector3(B.x + randf_range(-0.4, 0.4), 0.2, randf_range(-0.3, 0.3)), 1.5, Color(0.06, 0.05, 0.05, 0.6))
	run([
		[0, func():
			tw(A, "x", B.x - f * 0.7 * A.s, 16)
			A.play("walk", 4.0)
			G.cam_shot(Lp(A, 1, 1.5, 4.5), Lp(A, 0.5, 1.2, 0), 34.0, 16.0)],
		[16, func():
			hold(A, pose(A, {"+chest": [-0.1, 0.2, 0], "R": [0.62, 2.0, 0.04], "RE": [0, -1, 0.8], "L": [0.2, 1.4, -0.3]}), 8.0)
			hold(B, SB.lifted, 8.0)
			tw(B, "y", 0.45, 14, "out")
			tw(B, "x", A.x + f * 0.62 * A.s, 10)],
		[26, func():
			SFX.play("fire", 1.5)
			SFX.voice(B.def.id, "scream", 1.3)
			G.cam_shot(Lp(B, 1.84, 1.1, 2.7), Lp(B, 0, 1.6, 0), 38.0, 60.0, "io", -0.05)
			G.arena.flash = 1.0],
		[62, func():
			SFX.play("fire", 1.5)
			SFX.voice(B.def.id, "die", 1.2)],
		[100, func(): hold(A, pose(A, {"+root": [0.12, -0.06, 0], "+hip": [0.15, 0.35, 0], "+chest": [0.25, 0.6, 0], "R": [1.05, 1.5, 0.02], "RE": [0, -1, 0.3]}), 3.0)],
		[103, func():
			var p: Vector3 = jw(B, "chest")
			impact(p, 1.8, {col = Color(5, 1.5, 0.3), hold = 10})
			for i in 70: VFX.fire(p, 2.0, Vector3(f * randf_range(1, 6), randf_range(-1, 3), randf_range(-2, 2)))
			SFX.play("boom", 1.3)
			st.crumble = 0
			G.cam_shot(Lp(A, 1.2, 1.4, 2.6), Lp(A, 0.6, 1.2, 0), 36.0, 20.0)],
		[175, func():
			hold(A, pose(A, {"+chest": [-0.25, 0.2, 0], "R": [0.3, 2.25, 0.1], "RE": [0, -1, 1], "L": [0.3, 1.35, -0.3], "nod": -0.4}), 12.0)
			for i in 50: VFX.fire(Vector3(A.x - f * randf_range(0.2, 0.8), randf_range(0, 0.3), randf_range(-0.6, -0.2)), 2.5, Vector3(0, randf_range(2, 5), 0))
			SFX.play("fire", 1.2)
			SFX.voice(A.def.id, "roar", 1.3)
			G.cam_shot(Lp(A, 1.72, 0.4, 2.97), Lp(A, 0, 1.6, 0), 42.0, 30.0, "io", f * 0.06)],
	], 250, {upd = upd, on_end = func(): exec_done(A, B)})

func _exec_ossirah(A, B) -> void:
	var f: int = A.facing
	var SA: Dictionary = A.def.S
	var SB: Dictionary = B.def.S
	var st := {bloat = -1}
	for n in Rig.SEGS: B.rig.infl[n] = randf_range(0.6, 1.5)
	var dart_mat := Mats.glow(Color(0.2, 1.0, 0.2), 3.0)
	var upd := func(t):
		if st.bloat >= 0:
			st.bloat += 1
			var k := minf(1.0, st.bloat / 92.0)
			B.rig.inflate = k * 0.85 + sin(st.bloat * 0.7) * 0.04 * k
			tint_mats(B, Color(0.2, 0.24, 0.1), k * 0.85, Color(0.05, 0.12, 0.01))
			B.flinch_v += randf_range(-6, 6) * k
			if st.bloat % 3 == 0: VFX.plague(jw(B, ["chest", "head", "pelvis"][randi() % 3]), 0.7)
			if st.bloat % 9 == 0: SFX.play("splat", 0.3)
	run([
		[0, func():
			pl(A, PZ.cast(SA.guard, {startup = 10, active = 2, recovery = 18}, {t = [0.9, 1.55, 0], t2 = [0.2, 1.4, 0.2]}), 3.0)
			G.cam_shot(Lp(A, -0.6, 1.6, 2.6), Lp(A, 1.5, 1.4, 0), 34.0, 8.0)],
		[10, func():
			var m := MeshInstance3D.new()
			var cm := CylinderMesh.new()
			cm.top_radius = 0.012; cm.bottom_radius = 0.004; cm.height = 0.25
			m.mesh = cm
			m.material_override = dart_mat
			m.rotation = Vector3(0, 0, -f * PI / 2)
			var x0: float = A.x + f * 0.9
			var x1: float = B.x
			var yy: float = 1.55 * B.s
			VFX.mesh_fx(m, 0.2, func(o, u, _dt):
				o.position = Vector3(lerpf(x0, x1, u), yy, 0)
				VFX.plague(o.position, 0.5))
			SFX.play("whoosh", 0.6)],
		[22, func():
			var p: Vector3 = jw(B, "neck")
			VFX.flash(p, Color(1, 4, 0.6), 1.0)
			for i in 30: VFX.plague(p, 1.0)
			hold(B, SB.hitHi, 3.0)
			SFX.voice(B.def.id, "hurt", 1.2)
			G.cam_shot(Lp(B, 1.5, 1.4, 2.0), Lp(B, 0, 1.3, 0), 36.0, 30.0)
			st.bloat = 0],
		[40, func():
			hold(B, pose(B, {"+chest": [-0.35, 0, 0], "+spine": [-0.15, 0, 0], "L": [-0.05, 1.55, -0.8], "R": [-0.05, 1.55, 0.8], "LE": [0, -1, -1], "RE": [0, -1, 1], "nod": -0.7}), 20.0)
			SFX.voice(B.def.id, "scream", 1.2)
			SFX.play("swarm", 0.8)],
		[84, func():
			SFX.voice(B.def.id, "die", 1.2)
			G.cam_shot(Lp(B, 2.6, 1.6, 3.6), Lp(B, 0, 1.2, 0), 40.0, 26.0, "io", 0.04)],
		[116, func():
			st.bloat = -1
			var c: Vector3 = jw(B, "chest")
			B.rig.inflate = 0.0
			B.rig.update(B.anim.out)
			for sg in Rig.SEGS: B.rig.seg[sg].visible = false
			for rb in B.rig.ribbons: rb[0].visible = false
			for lk in B.rig.links: lk[0].visible = false
			for segs in [["head"], ["uaL", "faL", "hdL"], ["uaR", "faR", "hdR"], ["thL", "snL", "ftL"]]:
				for n in segs: B.rig.seg[n].visible = true
				detach(B, segs, Vector3(randf_range(-6, 6), randf_range(3, 8), randf_range(-4, 4)), Vector3(randf_range(-12, 12), randf_range(-12, 12), randf_range(-12, 12)), 0.07, 5.0)
			for i in 40: VFX.gib(c + Vector3(randf_range(-0.3, 0.3), randf_range(-0.5, 0.5), randf_range(-0.2, 0.2)), Vector3(randf_range(-7, 7), randf_range(1, 9), randf_range(-5, 5)), randf_range(0.03, 0.09), Mats.M.bone if randf() < 0.2 else Mats.M.flesh)
			for i in 6: VFX.blood(c, randf_range(-1, 1), 70, {speed = 8.0, spread = 1.6, size = 0.022, vel = Vector3(0, 0, randf_range(-3, 3))})
			for i in 40: VFX.plague(c + Vector3(randf_range(-0.6, 0.6), randf_range(-0.8, 0.8), randf_range(-0.5, 0.5)), 3.0)
			VFX.decal(B.x, 0, 3.2, 2.0)
			VFX.decal(B.x - 1.0, 0.3, 2.0, 2.0)
			VFX.decal(B.x + 1.1, -0.2, 2.2, 2.0)
			VFX.flash(c, Color(2, 0.6, 0.4), 2.2, 0.18)
			VFX.ring(c, Color(1.6, 0.2, 0.1), 4.0, 0.45, "face", 0.7)
			VFX.light_at(c + Vector3(0, 0, 1), Color(1, 0.3, 0.2), 12.0)
			SFX.play("boom", 1.6); SFX.play("splat", 1.5); SFX.play("crack", 1.5)
			impact(null, 2.0, {hold = 6, frames = 4.0})
			G.slowmo(0.4, 1.6)
			VFX.screen_blood(12, 1.4)
			G.cam_shot(Lp(B, 3.4, 1.2, 4.4), Lp(B, 0, 0.8, 0), 44.0, 60.0, "io")],
		[175, func():
			hold(A, PZ.P(SA.guard, {"+root": [0, -0.05, 0], "+hip": [0.25, 0, 0], "+chest": [0.45, 0.2, 0], "L": [0.35, 1.2, 0.05], "R": [-0.35, 1.1, 0.35], "nod": 0.3}), 14.0)
			SFX.voice(A.def.id, "laugh", 1.1)
			G.cam_shot(Lp(A, 1.84, 1.3, 3.24), Lp(A, 0, 1.3, 0), 34.0, 30.0)],
	], 255, {upd = upd, on_end = func(): exec_done(A, B)})

# ------------------------------------------------------------------ test scenarios (--test=...)
func run_test(name: String) -> void:
	var A = G.f[0]
	var B = G.f[1]
	G.phase = "fight"
	cur = null
	A.reset(-0.7, 1)
	B.reset(0.7, -1)
	match name:
		"super": later(0.3, func(): start_super_cine(A, B))
		"exec":
			G.phase = "endthem"; G.end_a = A; G.end_b = B; G.end_t = 99999; B.hp = 0
			B.set_state("dizzy"); B.play("dizzy", 2.0)
			later(0.3, func(): start_execution(A, B))
		_:
			if name.begins_with("move:"):
				var id := name.substr(5)
				later(0.2, func(): A.start_move(A.mv[id]))
