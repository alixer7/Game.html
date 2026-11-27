extends RefCounted
## A fighter: frame-based state machine, physics, and rendering of its rig.

const Rig = preload("res://scripts/rig.gd")
const Anim = preload("res://scripts/anim.gd")
const PZ = preload("res://scripts/pose.gd")
const InputBuf = preload("res://scripts/input_buf.gd")
const CD = preload("res://scripts/chardata.gd")

const GRAV := 0.0095
const STAGE := 7.3

var idx := 0
var def: Dictionary
var s := 1.0
var mv: Dictionary
var rig
var anim
var input
var ai = null
var trail_pts := []
var trail_mi: MeshInstance3D
var trail_im: ImmediateMesh
var trail_on := false
var store := {}

var x := 0.0
var y := 0.0
var z := 0.0
var px := 0.0
var py := 0.0
var vx := 0.0
var vy := 0.0
var kbx := 0.0
var facing := 1
var hp := 1000
var max_hp := 1000
var state := "stand"
var sf := 0
var stun := 0
var move = null
var mf := 0
var hit_done := []
var contact := false
var contact_f := 0
var chain_buf = null
var armor_left := 0
var inv := 0
var juggle_n := 0
var combo_hits := 0
var combo_dmg := 0
var poison := 0
var land_lag := 0
var jdir := 0
var air_atk := false
var down_t := 40
var bounced := false
var block_low := false
var hit_crouch := false
var vanish := false
var walk_ph := 0.0
var flinch := 0.0
var flinch_v := 0.0
var no_juggle := false
var dead := false
var vis_scale := 1.0
var meter := 0.0
var dash_used := -1
var bdash_used := -1
var last_x := 0.0
var st_edge := false
var drip_acc := 0.0
var _lx := 0.0

func _init(i: int, id: String) -> void:
	idx = i
	def = CD.get_def(id)
	s = def.scale
	mv = def.mv
	rig = Rig.new(def)
	anim = Anim.new(def.S.guard)
	input = InputBuf.new()
	trail_im = ImmediateMesh.new()
	trail_mi = MeshInstance3D.new()
	trail_mi.mesh = trail_im
	trail_mi.top_level = true
	trail_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var tm := StandardMaterial3D.new()
	tm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	tm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	tm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	tm.cull_mode = BaseMaterial3D.CULL_DISABLED
	tm.vertex_color_use_as_albedo = true
	tm.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	trail_mi.material_override = tm
	trail_mi.extra_cull_margin = 8.0
	rig.root.add_child(trail_mi)
	for e in rig.emit:
		e[3] = randf()
	reset(1.6 if i == 1 else -1.6, -1 if i == 1 else 1)

func add_to(parent: Node) -> void:
	if rig.root.get_parent() != parent:
		if rig.root.get_parent(): rig.root.get_parent().remove_child(rig.root)
		parent.add_child(rig.root)
	rig.reset_ropes()

func remove() -> void:
	if rig.root.get_parent(): rig.root.get_parent().remove_child(rig.root)

func opp():
	return G.f[1 - idx]

func reset(nx: float, nf: int) -> void:
	x = nx; px = nx; y = 0.0; py = 0.0; z = 0.0; vx = 0.0; vy = 0.0; kbx = 0.0; facing = nf
	hp = def.hp; max_hp = def.hp; state = "stand"; sf = 0; stun = 0; move = null; mf = 0; hit_done = []
	contact = false; chain_buf = null; armor_left = 0; inv = 0; juggle_n = 0; combo_hits = 0; combo_dmg = 0; poison = 0
	land_lag = 0; jdir = 0; air_atk = false; down_t = 40; bounced = false; block_low = false; hit_crouch = false; vanish = false
	flinch = 0.0; flinch_v = 0.0; no_juggle = false; dead = false; vis_scale = 1.0; store = {}
	input.clear()
	restore_body()
	anim = Anim.new(def.S.guard)
	play("idle", 0.0)
	trail_pts.clear()
	rig.reset_ropes()

func restore_body() -> void:
	for n in Rig.SEGS:
		var sg: Node3D = rig.seg[n]
		if sg.get_parent() != rig.root:
			if sg.get_parent(): sg.get_parent().remove_child(sg)
			rig.root.add_child(sg)
		sg.visible = true
	for w in rig.wounds:
		if is_instance_valid(w) and w.get_parent(): w.get_parent().remove_child(w); w.queue_free()
	rig.wounds.clear()
	rig.det = {}
	rig.inflate = 0.0
	for m in rig.mats:
		if m is BaseMaterial3D:
			m.albedo_color = m.get_meta("c0")
			m.emission_enabled = m.get_meta("em0")
			m.emission = m.get_meta("e0")
			m.emission_energy_multiplier = m.get_meta("ee0")
		elif m is ShaderMaterial and m.has_meta("c0"):
			m.set_shader_parameter("albedo", m.get_meta("c0"))
	for rb in rig.ribbons: rb[0].visible = true
	for lk in rig.links: lk[0].visible = true
	rig.root.visible = true

func play(name: String, blend := 4.0) -> void:
	if def.clips.has(name): anim.play(def.clips[name], blend, name)

func play_clip(c: Dictionary, blend := 4.0, nm := "custom") -> void:
	anim.play(c, blend, nm)

func set_state(st: String) -> void:
	state = st
	sf = 0

func airborne() -> bool:
	return state == "air" or state == "juggle" or (state == "attack" and move != null and move.get("air", false))

func crouching() -> bool:
	return state == "crouch" or state == "cblock" or (state == "bstun" and block_low) or (state == "hit" and hit_crouch) or (state == "attack" and move != null and move.get("crouch", false) and mf < move.startup + move.active)

func hurt() -> Array:
	var w := 0.27 * s
	var y0 := y
	var y1 := y + 1.86 * s
	if crouching(): y1 = y + 1.12 * s
	if state == "juggle":
		y0 = y + 0.05; y1 = y + 1.0 * s; w = 0.5 * s
	elif state == "air" or (state == "attack" and move != null and move.get("air", false)):
		y0 = y + 0.3 * s; y1 = y + 1.8 * s
	if state == "attack" and move != null and move.has("lowHurt") and mf >= move.lowHurt[0] and mf <= move.lowHurt[1]:
		y1 = y + 0.62 * s
	if state == "down":
		y0 = 0.0; y1 = 0.35; w = 0.8 * s
	return [x - w, x + w, y0, y1]

func invuln_to(h: Dictionary, proj: bool) -> bool:
	var st := state
	var th: bool = h.lvl == "throw" or h.get("grab", false)
	if st in ["down", "getup", "dead", "cine", "win", "intro", "throwing", "thrown"]: return true
	if st == "juggle" and (no_juggle or juggle_n > 10): return true
	if inv > 0: return true
	if th:
		return airborne() or st == "hit" or st == "bstun" or st == "jsquat"
	if st == "attack" and move != null and move.has("inv") and mf >= move.inv[0] and mf <= move.inv[1]: return true
	if st == "side" and sf >= 2 and sf <= 16: return true
	if st == "bdash" and sf >= 2 and sf <= 10 and not proj: return true
	return false

func blocking(lvl: String) -> bool:
	if lvl == "unblockable" or lvl == "throw": return false
	if state != "block" and state != "cblock" and state != "bstun": return false
	var low := state == "cblock" or (state == "bstun" and block_low)
	if lvl == "low": return low
	if lvl == "overhead": return not low
	return true

func face_opp() -> void:
	var d: float = opp().x - x
	if absf(d) > 0.05:
		facing = 1 if d > 0.0 else -1

func to_neutral() -> void:
	move = null; trail_on = false; vanish = false
	combo_hits = 0; combo_dmg = 0; juggle_n = 0; no_juggle = false
	var d: int = input.dir
	if input.held("BL"):
		set_state("cblock" if d <= 3 else "block"); play(state, 4.0)
	elif d <= 3:
		set_state("crouch"); play("crouch", 5.0)
	else:
		set_state("stand"); play("idle", 7.0)
	face_opp()

# ------------------------------------------------------------------ tick
func tick() -> void:
	sf += 1
	if inv > 0: inv -= 1
	if poison > 0:
		poison -= 1
		if poison % 12 == 0 and hp > 1 and G.phase == "fight": hp -= 2
		if poison % 5 == 0: VFX.plague(rig.joint_world("chest"), 0.5)
	match state:
		"stand", "walkf", "walkb", "crouch", "block", "cblock": neutral()
		"jsquat":
			if sf >= 4:
				set_state("air")
				vy = def.jumpV
				vx = jdir * (0.066 if jdir > 0 else 0.058) * facing
				play("flip" if jdir != 0 else "jump", 3.0)
				air_atk = false
				SFX.play("whoosh", 0.35)
		"air": try_air()
		"land":
			if sf >= land_lag: to_neutral()
		"attack": attack_tick()
		"hit":
			check_breaker()
			stun -= 1
			if stun <= 0: to_neutral()
		"bstun":
			block_low = input.dir <= 3
			stun -= 1
			if stun <= 0: to_neutral()
		"juggle": check_breaker()
		"down":
			if sf >= down_t and not dead:
				if G.phase == "endthem" and hp <= 0:
					set_state("dizzy"); play("dizzy", 18.0); SFX.voice(def.id, "hurt", 0.6)
				else:
					set_state("getup"); play("getup", 3.0)
		"getup":
			if sf >= 22:
				inv = 4
				to_neutral()
		"dash":
			var k := 1.0 - sf / 16.0
			vx = def.dashV * facing * maxf(0.0, k * 1.2)
			if sf > 8 and try_action(false): return
			if sf >= 16: to_neutral()
		"bdash":
			var k := 1.0 - sf / 20.0
			vx = -0.135 * facing * maxf(0.0, k * 1.25)
			if sf >= 20: to_neutral()
		"side":
			z = -sin(minf(1.0, sf / 24.0) * PI) * 0.75
			if sf >= 24:
				z = 0.0
				to_neutral()
		"stagger":
			stun -= 1
			if stun <= 0: to_neutral()

func check_breaker() -> void:
	if meter >= 200 and combo_hits >= 1 and input.recent("BL", 3) >= 0 and input.dir == 6 and G.phase == "fight":
		input.consume("BL")
		G.combat.do_breaker(self)

func neutral() -> void:
	var I = input
	var d: int = I.dir
	face_opp()
	if G.phase != "fight" and G.phase != "endthem" and not G.training:
		if state != "stand":
			set_state("stand"); play("idle", 8.0)
		vx = 0.0
		return
	if try_action(false): return
	var bl: bool = I.held("BL")
	if bl and I.recent("U", 4) >= 0:
		I.consume("U")
		set_state("side"); play("side", 3.0); vx = 0.0; SFX.play("whoosh", 0.4)
		return
	if d >= 7 and not bl:
		jdir = 1 if d == 9 else (-1 if d == 7 else 0)
		set_state("jsquat"); play("jsquat", 3.0); vx = 0.0
		return
	if bl:
		var ns := "cblock" if d <= 3 else "block"
		if state != ns:
			set_state(ns); play(ns, 4.0)
		vx = 0.0
		return
	if d <= 3:
		if state != "crouch":
			set_state("crouch"); play("crouch", 5.0)
		vx = 0.0
		return
	if I.dash >= G.frame - 2 and I.dash > dash_used:
		dash_used = I.dash
		set_state("dash"); play("dash", 3.0); SFX.play("whoosh", 0.3); VFX.dust(Vector3(x, 0, 0), 4, 0.6)
		return
	if I.bdash >= G.frame - 2 and I.bdash > bdash_used:
		bdash_used = I.bdash
		set_state("bdash"); play("bdash", 3.0); SFX.play("whoosh", 0.3)
		return
	if d == 6:
		vx = def.walkF * facing
		if state != "walkf":
			set_state("walkf"); play("walk", 6.0)
	elif d == 4:
		vx = -def.walkB * facing
		if state != "walkb":
			set_state("walkb"); play("walk", 6.0)
	else:
		vx = 0.0
		if state != "stand":
			set_state("stand"); play("idle", 8.0)

func try_action(cancel: bool) -> bool:
	var I = input
	if not cancel and I.recent("SP", 5) >= 0 and meter >= 300 and (G.phase == "fight" or G.training):
		I.consume("SP")
		start_move(mv["super"])
		return true
	for b in ["1", "2", "3", "4", "TH"]:
		var pf: int = I.recent(b, 8 if cancel else 5)
		if pf < 0: continue
		if not cancel and G.phase == "endthem" and hp > 0 and opp().state == "dizzy" and try_exec(b, pf):
			I.consume(b)
			return true
		for sp in def.spec:
			if sp.btn != b or not I.motion(sp.seq, pf): continue
			var ex: bool = I.held("BL") and meter >= 100 and mv.has(sp.id + "EX")
			var m: Dictionary = mv[sp.id + "EX"] if ex else mv[sp.id]
			if ex: meter -= 100
			I.consume(b)
			start_move(m)
			return true
		if cancel: continue
		var d: int = I.dir
		if b == "TH":
			I.consume(b)
			start_move(mv.bthrow if d == 4 or d == 1 or d == 7 else mv.throw)
			return true
		var m = null
		if d <= 3: m = mv.get("d" + b)
		elif d == 6 or d == 9: m = mv.get("f" + b, mv.get(b))
		elif d == 4 or d == 7: m = mv.get("b" + b, mv.get(b))
		else: m = mv.get(b)
		if m != null:
			I.consume(b)
			start_move(m)
			return true
	return false

func try_exec(b: String, pf: int) -> bool:
	var E: Dictionary = def.exec
	if b != E.btn or not input.motion(E.seq, pf, 34): return false
	var dist: float = absf(opp().x - x)
	var ok := false
	match E.range:
		"close": ok = dist < 1.9
		"mid": ok = dist >= 1.4 and dist < 3.8
		_: ok = dist >= 2.3
	if not ok:
		G.ui.show_tag(idx, {close = "اقترب أكثر", mid = "المسافة: متوسطة", far = "ابتعد أكثر"}[E.range])
		return false
	G.cine.start_execution(self, opp())
	return true

func try_air() -> void:
	if air_atk: return
	for b in ["1", "2", "3", "4"]:
		if input.recent(b, 4) >= 0:
			input.consume(b)
			air_atk = true
			start_move(mv["j" + b])
			return

func start_move(m: Dictionary) -> void:
	set_state("attack")
	move = m
	mf = 0
	hit_done = []
	for h in m.hits: hit_done.append(false)
	contact = false
	chain_buf = null
	armor_left = m.armor[2] if m.has("armor") else 0
	if not m.get("air", false): vx = 0.0
	trail_on = false
	play_clip(m.clip, 2.0 if m.get("air", false) else clampf(roundf(m.startup * 0.35), 2.0, 4.0), m.id)
	if m.type == "super":
		meter = 0.0
		G.cine.super_flash(self)
	if m.type == "ex":
		G.ui.show_tag(idx, "EX")
		VFX.ring(Vector3(x, 1.2 * s, 0), Color(2, 0.7, 0.2), 1.8, 0.3)
		SFX.play("fire", 0.4)

func attack_tick() -> void:
	var m = move
	mf += 1
	if m == null:
		to_neutral()
		return
	var f := mf
	if m.has("motion"): vx = m.motion.call(f, self) * facing
	elif not m.get("air", false): vx *= 0.6
	if m.has("rise"):
		var a: int = m.rise[0]
		var b: int = m.rise[1]
		y = sin(float(f - a) / (b - a) * PI) * 0.45 if f >= a and f <= b else 0.0
	if m.has("tick"): m.tick.call(self, f)
	if m.has("ev"):
		for e in m.ev:
			if e[0] == f: e[1].call(self)
	if m.has("vanish"):
		vanish = f >= m.vanish[0] and f <= m.vanish[1]
		if f == m.vanish[0]:
			var p: Vector3 = rig.joint_world("chest")
			for i in 18: VFX.wisp(p + Vector3(randf_range(-0.3, 0.3), randf_range(-0.8, 0.6), randf_range(-0.2, 0.2)))
			SFX.play("spectral", 0.7)
	if m.has("tele") and f == m.tele:
		var o = opp()
		var nx: float = o.x - o.facing * 0.95 * s
		if absf(nx) > STAGE - 0.3: nx = o.x + o.facing * 0.95 * s
		x = nx; px = nx
		facing = 1 if o.x > x else -1
		rig.reset_ropes()
		for i in 18: VFX.wisp(Vector3(x + randf_range(-0.3, 0.3), randf_range(0.3, 1.8), randf_range(-0.2, 0.2)))
	if f == maxi(1, m.startup - 3):
		SFX.play("whoosh", clampf(m.hits[0].power if m.hits.size() > 0 else 0.5, 0.3, 1.2))
	if f == maxi(1, m.startup - 2) and m.has("voice") and randf() < 0.75:
		SFX.voice(def.id, m.voice, 0.8)
	if m.has("trail"): trail_on = f >= m.trail[1] and f <= m.trail[2]
	if m.has("chain") and chain_buf == null and f <= m.chainEnd:
		for b in m.chain:
			if input.recent(b, 7) >= 0:
				input.consume(b)
				chain_buf = m.chain[b]
				break
	if chain_buf != null and f >= m.chainAt:
		if mv.has(chain_buf):
			start_move(mv[chain_buf])
			return
	if m.get("cancel", false) and contact and f > contact_f and f <= m.total - 3:
		if try_action(true): return
	if m.get("air", false) and y <= 0.0 and f > 2:
		y = 0.0; vy = 0.0; vx = 0.0
		set_state("land"); land_lag = 5; play("land", 2.0); move = null; trail_on = false
		return
	if f >= m.total:
		if m.get("air", false):
			state = "air"; move = null; trail_on = false; play("jump", 6.0); anim.t = 25.0
			return
		to_neutral()

func physics() -> void:
	var st := state
	var air: bool = st == "air" or st == "juggle" or (st == "attack" and move != null and move.get("air", false))
	if air:
		vy -= GRAV * (1.0 + juggle_n * 0.065 if st == "juggle" else 1.0)
		y += vy
		if y <= 0.0 and vy < 0.0:
			y = 0.0
			land()
	x += vx + kbx
	kbx *= 0.985 if air else 0.86
	if absf(kbx) < 0.001: kbx = 0.0
	if st == "juggle" or st == "down": vx *= 0.99 if air else 0.8
	if x < -STAGE:
		x = -STAGE; kbx = 0.0
	if x > STAGE:
		x = STAGE; kbx = 0.0

func land() -> void:
	if state == "air":
		vx = 0.0
		set_state("land"); land_lag = 3; play("land", 2.0)
		VFX.dust(Vector3(x, 0, 0), 4, 0.5)
		face_opp()
		return
	if state == "juggle":
		if not bounced and vy < -0.07:
			bounced = true; vy = 0.055; y = 0.01
			G.cam_shake(0.25)
			VFX.dust(Vector3(x, 0, 0), 10, 1.2)
			SFX.play("hit", 0.6)
			VFX.blood(Vector3(x, 0.3, 0), 0.0, 8, {speed = 1.5})
			VFX.decal(x + randf_range(-0.3, 0.3), randf_range(-0.2, 0.2), randf_range(0.3, 0.6))
			return
		vy = 0.0; vx = 0.0
		set_state("down"); down_t = 9999 if dead else 34; play("down", 4.0)
		VFX.dust(Vector3(x, 0, 0), 8, 1.0)
		SFX.play("hit", 0.4)
		combo_hits = 0; combo_dmg = 0; juggle_n = 0

# ------------------------------------------------------------------ render
func render(dt: float, alpha: float, adv: float) -> void:
	var root: Node3D = rig.root
	var rx := lerpf(px, x, alpha)
	var ry := lerpf(py, y, alpha)
	root.position = Vector3(rx, ry, z)
	root.scale = Vector3(facing * s * vis_scale, s * vis_scale, s * vis_scale)
	root.visible = not vanish
	anim.advance(adv)
	var p: PackedFloat32Array = anim.eval().duplicate()
	if state == "walkf" or state == "walkb":
		walk_ph += (x - _lx) * facing / 0.78
		PZ.walk(p, walk_ph, 1.0)
	_lx = x
	var t := Time.get_ticks_msec() / 1000.0 + idx * 3.0
	if state in ["stand", "walkf", "walkb", "block", "crouch"]:
		p[9] += sin(t * 2.2) * 0.012
		p[1] += sin(t * 2.2) * 0.006
	flinch_v += (-flinch * 180.0 - flinch_v * 14.0) * dt
	flinch += flinch_v * dt
	if absf(flinch) > 0.0005:
		p[9] -= flinch * 0.6; p[12] -= flinch * 0.5; p[15] -= flinch * 0.8; p[0] -= flinch * 0.1
	if G.hitstop > 0 and state in ["hit", "juggle", "bstun"]:
		var k := 0.012 * minf(1.0, G.hitstop / 4.0)
		p[0] += randf_range(-k, k); p[2] += randf_range(-k, k)
	rig.update(p)
	if root.is_inside_tree():
		rig.secondary(dt * Engine.time_scale)
	_trail(dt)
	# body emitters (fire, embers, wisps, plague, drips)
	if not vanish and dt > 0.0 and root.is_inside_tree():
		for e in rig.emit:
			e[3] += e[2] * dt * VFX.quality
			while e[3] >= 1.0:
				e[3] -= 1.0
				_emit(e[1], e[0].global_position)

func _emit(type: String, p: Vector3) -> void:
	match type:
		"fire": VFX.fire(p + Vector3(randf_range(-0.04, 0.04), 0, 0), 0.5)
		"eyefire":
			for zz in [-0.03, 0.03]:
				VFX._p("flame", rig.seg.head.global_transform * Vector3(0.09, 0.12, zz), Vector3(-facing * randf_range(0.1, 0.4), randf_range(0.3, 0.7), 0), -1.0, 1.0, randf_range(0.2, 0.4), 0.07, 0.01, Color(5, 1.5, 0.3, 1), Color(2, 0.2, 0, 0))
		"ember": VFX.ember(p + Vector3(randf_range(-0.1, 0.1), randf_range(-0.1, 0.1), randf_range(-0.1, 0.1)))
		"drip": VFX.drop(p + Vector3(randf_range(-0.03, 0.03), 0, randf_range(-0.03, 0.03)), Vector3(0, -0.2, 0), 0.007 + randf() * 0.008, 0.5)
		"wisp": VFX.wisp(p)
		"plague": VFX.plague(p, 0.5)
		"miasma": VFX.miasma(Vector3(p.x, 0.1, p.z), 0.7)
		"fly": VFX.fly(p, 0.5 + randf() * 0.4)

func _trail(dt: float) -> void:
	var on: bool = trail_on and move != null and move.has("trail")
	if on:
		var sg: String = move.trail[0]
		var M: Transform3D = rig.seg[sg].global_transform
		var a: Vector3
		var b: Vector3
		if rig.extras.has("blades") and sg.begins_with("f"):
			a = M * Vector3(0.05, 0.3, 0); b = M * Vector3(-0.02, 0.7, 0)
		elif def.id == "ossirah" and sg == "hdR":
			a = M * Vector3(0.12, 0.12, 0.25); b = M * Vector3(0.31, -0.05, 0.12)
		elif sg.begins_with("s"):
			a = M * Vector3(0, 0.05, 0); b = M * Vector3(0, 0.52, 0)
		else:
			a = M * Vector3(0, 0.05, 0); b = M * Vector3(0, 0.38, 0)
		trail_pts.push_front([a, b, 1.0])
		if trail_pts.size() > 12: trail_pts.pop_back()
	else:
		for q in trail_pts: q[2] -= dt * 7.0
		while trail_pts.size() > 0 and trail_pts[trail_pts.size() - 1][2] <= 0.0: trail_pts.pop_back()
	trail_im.clear_surfaces()
	if trail_pts.size() < 2: return
	var col: Color = {vorgath = Color(1.4, 0.1, 0.08), nyxara = Color(0.7, 0.6, 1.6), kharos = Color(2.0, 0.6, 0.15), ossirah = Color(0.6, 1.4, 0.3)}[def.id]
	trail_im.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
	var n := trail_pts.size()
	for i in n:
		var q = trail_pts[i]
		var a: float = maxf(0.0, 1.0 - float(i) / (n - 1)) * q[2] * 0.55
		trail_im.surface_set_color(Color(col.r, col.g, col.b, a))
		trail_im.surface_add_vertex(q[0])
		trail_im.surface_set_color(Color(col.r, col.g, col.b, a * 0.15))
		trail_im.surface_add_vertex(q[1])
	trail_im.surface_end()
