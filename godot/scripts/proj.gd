extends RefCounted
## Projectiles: skull fireball, blood lance, spectral shade, locust swarm,
## ground fire wave, blood geyser, poison cloud.

const Geo = preload("res://scripts/geo.gd")
const Rig = preload("res://scripts/rig.gd")
const STAGE := 7.3

static var _mesh := {}
static var _mats := {}

var F
var type := ""
var dir := 1
var t := 0
var dead := false
var x := 0.0
var y := 1.3
var vx := 0.0
var life := 150
var hits_left := 1
var cd := 0
var cd_t := 0
var big := false
var h := {}
var w := 0.22
var hh := 0.2
var solid := true
var tick_dmg := 0
var node: MeshInstance3D = null

func _init(f, o: Dictionary) -> void:
	F = f
	type = o.type
	dir = F.facing
	x = o.get("x", F.x + F.facing * o.get("x0", 0.75) * F.s)
	y = o.get("y", 1.38) * F.s
	vx = o.get("vx", 0.0) * F.facing
	life = o.get("life", 150)
	hits_left = o.get("hits", 1)
	cd = o.get("cd", 0)
	big = o.get("big", false)
	h = {lvl = o.get("lvl", "mid"), dmg = o.get("dmg", 30), hs = o.get("hs", 18), bs = o.get("bs", 12), push = 0.06, power = 1.2 if big else 0.9, fire = type == "skull" or type == "wave"}
	if o.has("launch"): h.launch = o.launch
	if o.get("kd", false): h.kd = true
	if o.has("poison"): h.poison = o.poison
	match type:
		"skull":
			node = _make("skull")
			node.scale = Vector3.ONE * (1.6 if big else 1.15)
		"lance":
			node = _make("lance")
			w = 0.4; hh = 0.12
		"shade":
			w = 0.3; hh = 0.25
		"swarm":
			w = 0.45 if big else 0.35; hh = w; y = 1.2 * F.s
		"wave":
			y = 0.25; hh = 0.25; w = 0.35; solid = false
		"geyser":
			y = 1.1; hh = 1.1; w = 0.5; solid = false; life = 8
			erupt()
		"cloud":
			y = 0.9; hh = 0.9; w = o.get("r", 0.85); solid = false; hits_left = 999; cd = 18
			tick_dmg = o.get("dmg", 9)
			h.lvl = "unblockable"; h.hs = 0

static func _material(k: String) -> Material:
	if not _mats.has(k):
		match k:
			"skull": _mats[k] = Mats.std({map = Mats.T.bone_c, color = Color(0.2, 0.1, 0.05), emit = Color(1, 0.35, 0.05), ee = 2.5})
			"lance": _mats[k] = Mats.std({color = Color(0.3, 0.0, 0.01), r = 0.15, cc = 1.0, emit = Color(0.5, 0, 0.01), ee = 1.0})
	return _mats[k]

func _make(k: String) -> MeshInstance3D:
	if not _mesh.has(k):
		var mb := Geo.MB.new()
		if k == "skull": mb.add(Rig.skull_geo(), Transform3D(), _material(k))
		else: mb.add(Geo.taper([[-0.55, 0, 0], [-0.1, 0, 0], [0.35, 0, 0], [0.62, 0, 0]], 0.045, 0.002, 8, 10), Transform3D(), _material(k))
		_mesh[k] = mb.build()
	var mi := MeshInstance3D.new()
	mi.mesh = _mesh[k]
	G.world.add_child(mi)
	return mi

func erupt() -> void:
	for i in 5:
		VFX.spike(x + randf_range(-0.35, 0.35), randf_range(-0.25, 0.25), randf_range(1.2, 2.2), {r = randf_range(0.08, 0.14), grow = 0.1, life = 0.8, mat = _material("lance")})
	var px := x
	VFX.fountain(func(): return Vector3(px, 0.2, 0), func(): return Vector3.UP, 0.6, 200, {speed = 6.0, size = 0.02})
	G.cam_shake(0.35)
	SFX.play("splat", 1.2); SFX.play("boom", 0.4)
	VFX.light_at(Vector3(x, 1, 0.5), Color(1, 0.05, 0.02), 8.0)

func update() -> void:
	t += 1
	x += vx
	if cd_t > 0: cd_t -= 1
	match type:
		"skull":
			node.position = Vector3(x, y + sin(t * 0.3) * 0.03, 0)
			node.rotation = Vector3(sin(t * 0.2) * 0.2, 0.0 if dir > 0 else PI, sin(t * 0.37) * 0.2)
			for i in 2: VFX.fire(Vector3(x - dir * 0.1, y + randf_range(-0.08, 0.08), randf_range(-0.08, 0.08)), 1.6 if big else 1.1, Vector3(-dir * 1.6, 0.2, 0))
			VFX.light_at(Vector3(x, y, 0.4), Color(1, 0.45, 0.15), 3.0)
		"lance":
			node.position = Vector3(x, y, 0)
			node.rotation = Vector3(t * 0.4, 0.0 if dir > 0 else PI, 0)
			if t % 2 == 1: VFX.drop(Vector3(x - dir * 0.3, y, 0), Vector3(-dir * 0.5, 0, randf_range(-0.2, 0.2)), 0.01)
			VFX.glow(Vector3(x - dir * 0.2, y, 0), Color(1.2, 0.02, 0.02, 0.6), 0.25)
		"shade":
			for i in 3: VFX.wisp(Vector3(x + randf_range(-0.1, 0.1), y + randf_range(-0.12, 0.12), randf_range(-0.1, 0.1)), Vector3(-dir * randf_range(1, 3), 0, 0), 2.0)
			VFX.glow(Vector3(x, y, 0), Color(1.2, 2.5, 3.5, 0.8), 0.55)
		"swarm":
			for i in 3: VFX.fly(Vector3(x, y, 0), w)
			if t % 2 == 1: VFX.plague(Vector3(x + randf_range(-0.2, 0.2), y + randf_range(-0.2, 0.2), randf_range(-0.2, 0.2)), 1.4 if big else 1.0)
		"wave":
			for i in 2: VFX.fire(Vector3(x + randf_range(-0.25, 0.25), 0.05, randf_range(-0.3, 0.3)), 2.0 if big else 1.5, Vector3(0, 1.5, 0))
			if t % 3 == 0: VFX.decal(x, randf_range(-0.2, 0.2), 0.25)
		"cloud":
			if t % 2 == 1: VFX.miasma(Vector3(x + randf_range(-w, w), randf_range(0.1, 1.4), randf_range(-0.4, 0.4)), 1.1 + w * 0.4)
			if t % 6 == 0: VFX.fly(Vector3(x, 0.9, 0), w)
	if t > life or absf(x) > STAGE + 2.0: die(false)

func overlaps(B) -> bool:
	var hb: Array = B.hurt()
	return not (x + w < hb[0] or x - w > hb[1] or y + hh < hb[2] or y - hh > hb[3])

func collide() -> void:
	if dead or cd_t > 0: return
	var B = F.opp()
	if type == "geyser" and t > 8: return
	if not overlaps(B) or B.invuln_to(h, true): return
	if type == "cloud":
		if B.state == "juggle" or B.state == "down": return
		cd_t = cd
		B.hp = maxi(1 if G.training else 0, B.hp - tick_dmg)
		B.poison = maxi(B.poison, h.get("poison", 60))
		B.flinch_v += 3.0
		SFX.voice(B.def.id, "grunt", 0.4)
		if B.hp <= 0 and not G.training: G.on_ko(F, B)
		return
	var saved: bool = F.contact
	var hb: Array = B.hurt()
	var res: String = G.combat.resolve_hit(F, B, h, Vector3(x, clampf(y, hb[2] + 0.1, hb[3] - 0.1), 0.05), self)
	F.contact = saved
	hits_left -= 1
	cd_t = cd
	if hits_left <= 0 or (res == "block" and type != "swarm"): die(true)

func die(hit: bool) -> void:
	if dead: return
	dead = true
	if node:
		node.queue_free()
		node = null
	var p := Vector3(x, y, 0)
	match type:
		"skull":
			for i in 18: VFX.fire(p, 1.6, Vector3(randf_range(-2, 2), randf_range(-1, 2), 0))
			VFX.ring(p, Color(2.5, 0.8, 0.2), 1.6, 0.3)
			if hit: SFX.play("fire", 0.8)
		"shade":
			for i in 14: VFX.wisp(p + Vector3(randf_range(-0.2, 0.2), randf_range(-0.2, 0.2), randf_range(-0.2, 0.2)))
		"lance":
			VFX.blood(p, -dir, 20, {speed = 2.5})

static func clash(P: Array) -> void:
	for i in P.size():
		for j in range(i + 1, P.size()):
			var a = P[i]
			var b = P[j]
			if a.dead or b.dead or a.F == b.F or not a.solid or not b.solid: continue
			if absf(a.x - b.x) < a.w + b.w and absf(a.y - b.y) < a.hh + b.hh + 0.3:
				a.die(true); b.die(true)
				var p := Vector3((a.x + b.x) / 2.0, a.y, 0)
				VFX.flash(p, Color(4, 3, 2.5), 2.2)
				VFX.spark(p, 30, Color(4, 2.4, 1.2))
				VFX.ring(p, Color(2, 1.4, 1), 2.4, 0.35)
				SFX.play("boom", 0.6)
				G.cam_shake(0.3)
