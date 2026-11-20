class_name Animal
extends CharacterBody3D
## ذكاء الحيوانات: رعي، تجول، هروب جماعي، صيد الفرائس، دفاع عن المنطقة، كمائن، أكل الجيف.

const SPECIES := {
	"rabbit": {"name": "أرنب", "hp": 12.0, "walk": 1.4, "run": 7.5, "dmg": 0.0, "aggro": 0.0, "detect": 14.0, "len": 0.32, "r": 0.11, "leg": 0.12, "neck": 0.04, "head": 0.085, "ears": 0.16, "tail": 0.05, "tail_r": 0.04, "hop": true,
		"col": Color(0.55, 0.45, 0.35), "belly": Color(0.85, 0.8, 0.74), "drops": [["raw_meat", 1, 1], ["fur", 0, 1]], "group": [1, 2], "prey": true},
	"snow_rabbit": {"name": "أرنب ثلجي", "hp": 12.0, "walk": 1.4, "run": 7.5, "dmg": 0.0, "aggro": 0.0, "detect": 14.0, "len": 0.32, "r": 0.11, "leg": 0.12, "neck": 0.04, "head": 0.085, "ears": 0.16, "tail": 0.05, "tail_r": 0.04, "hop": true,
		"col": Color(0.92, 0.92, 0.94), "belly": Color(0.97, 0.97, 0.97), "drops": [["raw_meat", 1, 1], ["fur", 1, 1]], "group": [1, 2], "prey": true},
	"deer": {"name": "غزال", "hp": 45.0, "walk": 1.7, "run": 9.0, "dmg": 0.0, "aggro": 0.0, "detect": 28.0, "len": 1.0, "r": 0.24, "leg": 0.75, "neck": 0.45, "head": 0.15, "ears": 0.14, "tail": 0.1, "antlers": true, "light_snout": true,
		"col": Color(0.56, 0.38, 0.23), "belly": Color(0.86, 0.78, 0.64), "drops": [["raw_meat", 2, 4], ["hide", 1, 2], ["bone", 1, 2]], "group": [2, 5], "prey": true},
	"goat": {"name": "ماعز جبلي", "hp": 40.0, "walk": 1.5, "run": 8.0, "dmg": 6.0, "aggro": 0.0, "detect": 22.0, "len": 0.75, "r": 0.22, "leg": 0.5, "neck": 0.25, "head": 0.13, "ears": 0.1, "tail": 0.08, "horns": true,
		"col": Color(0.78, 0.74, 0.66), "belly": Color(0.9, 0.88, 0.82), "drops": [["raw_meat", 2, 3], ["hide", 1, 1], ["bone", 1, 1]], "group": [2, 4], "prey": true},
	"chicken": {"name": "دجاج بري", "hp": 8.0, "walk": 1.0, "run": 4.5, "dmg": 0.0, "aggro": 0.0, "detect": 10.0, "len": 0.3, "r": 0.15, "leg": 0.16, "neck": 0.12, "head": 0.07, "snout": 0.02, "ears": 0.0, "tail": 0.14, "tail_r": 0.06, "biped": true, "comb": true,
		"col": Color(0.62, 0.36, 0.2), "belly": Color(0.75, 0.55, 0.35), "leg_col": Color(0.9, 0.7, 0.25), "drops": [["raw_meat", 1, 1], ["feather", 2, 5]], "group": [2, 4], "prey": true},
	"camel": {"name": "جمل", "hp": 120.0, "walk": 1.4, "run": 6.0, "dmg": 0.0, "aggro": 0.0, "detect": 16.0, "len": 1.4, "r": 0.34, "leg": 1.1, "neck": 0.8, "head": 0.17, "ears": 0.08, "tail": 0.3, "hump": true, "light_snout": true,
		"col": Color(0.78, 0.62, 0.4), "belly": Color(0.85, 0.72, 0.52), "drops": [["raw_meat", 4, 6], ["hide", 2, 3], ["fat", 1, 2], ["bone", 2, 2]], "group": [1, 3], "prey": true},
	"boar": {"name": "خنزير بري", "hp": 70.0, "walk": 1.3, "run": 7.0, "dmg": 12.0, "aggro": 0.35, "detect": 14.0, "len": 0.95, "r": 0.3, "leg": 0.32, "neck": 0.08, "head": 0.21, "snout": 0.2, "ears": 0.1, "tail": 0.12, "tusks": true, "mane": true,
		"col": Color(0.3, 0.24, 0.19), "belly": Color(0.38, 0.3, 0.24), "drops": [["raw_meat", 3, 4], ["hide", 1, 2], ["fat", 1, 2], ["bone", 1, 1]], "group": [1, 3]},
	"wolf": {"name": "ذئب", "hp": 60.0, "walk": 2.0, "run": 9.5, "dmg": 8.5, "aggro": 0.75, "detect": 30.0, "len": 0.95, "r": 0.2, "leg": 0.52, "neck": 0.28, "head": 0.16, "snout": 0.17, "ears": 0.13, "tail": 0.45, "tail_r": 0.06,
		"col": Color(0.46, 0.44, 0.41), "belly": Color(0.72, 0.7, 0.66), "drops": [["raw_meat", 2, 3], ["fur", 1, 2], ["bone", 1, 2]], "group": [2, 4], "pred": true},
	"bear": {"name": "دب بني", "hp": 220.0, "walk": 1.5, "run": 8.0, "dmg": 24.0, "aggro": 0.55, "detect": 18.0, "len": 1.55, "r": 0.48, "leg": 0.55, "neck": 0.22, "head": 0.28, "snout": 0.16, "ears": 0.07, "round_ears": true, "tail": 0.08, "leg_r": 0.13,
		"col": Color(0.33, 0.22, 0.14), "belly": Color(0.36, 0.25, 0.16), "drops": [["raw_meat", 5, 7], ["fur", 2, 3], ["fat", 2, 3], ["bone", 2, 3]], "group": [1, 1], "pred": true, "territorial": true},
	"polar_bear": {"name": "دب قطبي", "hp": 260.0, "walk": 1.5, "run": 8.0, "dmg": 32.0, "aggro": 0.7, "detect": 22.0, "len": 1.7, "r": 0.5, "leg": 0.58, "neck": 0.3, "head": 0.27, "snout": 0.2, "ears": 0.06, "round_ears": true, "tail": 0.07, "leg_r": 0.13,
		"col": Color(0.92, 0.92, 0.88), "belly": Color(0.9, 0.9, 0.86), "drops": [["raw_meat", 5, 7], ["fur", 3, 4], ["fat", 3, 4], ["bone", 2, 3]], "group": [1, 1], "pred": true, "territorial": true},
	"croc": {"name": "تمساح", "hp": 160.0, "walk": 0.9, "run": 6.5, "dmg": 30.0, "aggro": 0.9, "detect": 9.0, "len": 2.2, "r": 0.28, "leg": 0.16, "neck": 0.05, "head": 0.18, "snout": 0.55, "flat_snout": true, "ears": 0.0, "tail": 1.5, "tail_r": 0.16, "flat_tail": true, "splay": 1.5,
		"col": Color(0.22, 0.28, 0.16), "belly": Color(0.6, 0.6, 0.45), "drops": [["raw_meat", 4, 5], ["hide", 2, 3], ["bone", 1, 2]], "group": [1, 1], "pred": true, "ambush": true, "swims": true},
}

var species := ""
var sp := {}
var hp := 10.0
var model: AnimalModel
var world: Node
var state := "idle"
var target: Node3D = null
var flee_from := Vector3.ZERO
var dest := Vector3.ZERO
var home := Vector3.ZERO
var think_t := 0.0
var state_t := 0.0
var attack_cd := 0.0
var hunger := 0.0
var leader: Animal = null
var dead := false
var harvested := false
var dead_time := 0.0
var provoked := 0.0
var _gravity := 18.0
var _stuck := 0.0
var _last_pos := Vector3.ZERO
var warned := false

func setup(w: Node, sp_id: String, pos: Vector3) -> void:
	world = w
	species = sp_id
	sp = SPECIES[sp_id]
	hp = sp["hp"]
	home = pos
	position = pos
	collision_layer = 4
	collision_mask = 1 | 2 | 8 | 32
	var cs := CollisionShape3D.new()
	var sh := CapsuleShape3D.new()
	var L: float = sp["len"]
	sh.radius = clampf(sp["r"] * 1.1, 0.12, 0.55)
	sh.height = maxf(sh.radius * 2.0 + 0.01, sp["leg"] + sp["r"] * 2.0)
	cs.shape = sh
	cs.position = Vector3(0, sh.height * 0.5, 0)
	add_child(cs)
	model = AnimalModel.new()
	model.build(sp)
	add_child(model)
	hunger = randf_range(0.0, 1.0)
	floor_snap_length = 0.6
	rotation.y = randf() * TAU
	_pick_wander()

func get_interact_text(_player) -> String:
	if dead and not harvested:
		return "اسلخ %s" % sp["name"]
	return ""

func interact(player) -> void:
	if not dead or harvested:
		return
	harvested = true
	var has_knife: bool = player.has_tool_kind("knife")
	var out := []
	for d in sp["drops"]:
		var it: String = d[0]
		if not has_knife and (it == "hide" or it == "fur"):
			continue
		var n := randi_range(d[1], d[2])
		if it == "raw_meat":
			n = int(round(n * player.stats.skill_yield_mult("hunting")))
		if n > 0:
			out.append([it, n])
	if not has_knife:
		Game.notify("بدون سكين لا يمكنك أخذ الجلد أو الفرو", Color(1, 0.8, 0.5))
	player.receive_items(out, global_position)
	player.stats.add_skill_xp("hunting", 3.0)
	Sfx.play("chop", global_position, -3.0)
	queue_free()

func on_hit(dmg: float, _kind: String, _tier: int, attacker, hit_pos: Vector3) -> void:
	if dead:
		return
	var mult := 1.0
	if attacker and attacker.get("stats") != null:
		mult = attacker.stats.skill_power_mult("hunting")
	take_damage(dmg * mult, attacker)
	world.fx_burst(hit_pos, Color(0.6, 0.05, 0.05))

func take_damage(dmg: float, attacker) -> void:
	if dead:
		return
	hp -= dmg
	Sfx.play("hit", global_position)
	provoked = 12.0
	if hp <= 0.0:
		_die(attacker)
		return
	if sp.get("prey", false) or hp < sp["hp"] * 0.25:
		_flee(attacker.global_position if attacker else global_position)
		_alert_herd(attacker.global_position if attacker else global_position)
	elif attacker:
		target = attacker
		state = "chase"
		state_t = 0.0
		if species == "wolf":
			_alert_pack(attacker)

func _die(attacker) -> void:
	dead = true
	state = "dead"
	model.state = "dead"
	velocity = Vector3.ZERO
	collision_layer = 64
	collision_mask = 1
	if attacker == world.player:
		world.player.stats.add_skill_xp("hunting", 6.0)
		Game.notify("قتلت %s. اقترب واسلخه" % sp["name"], Color(0.9, 0.9, 0.7))
	world.ai.on_animal_killed(self, attacker)

func _physics_process(dt: float) -> void:
	if world == null:
		return
	if dead:
		dead_time += dt
		if not is_on_floor():
			velocity.y -= _gravity * dt
			move_and_slide()
		return
	think_t -= dt
	state_t += dt
	attack_cd -= dt
	provoked = maxf(0.0, provoked - dt)
	hunger = minf(1.0, hunger + dt / 400.0)
	if think_t <= 0.0:
		think_t = randf_range(0.3, 0.6)
		_think()
	var spd := 0.0
	var move_to := Vector3.ZERO
	match state:
		"wander":
			move_to = dest
			spd = sp["walk"]
			if Vector2(global_position.x - dest.x, global_position.z - dest.z).length() < 1.2:
				state = "graze" if randf() < 0.6 else "idle"
				state_t = 0.0
		"flee":
			var away := global_position - flee_from
			away.y = 0
			if away.length() < 0.1:
				away = Vector3(randf_range(-1, 1), 0, randf_range(-1, 1))
			move_to = global_position + away.normalized() * 10.0
			spd = sp["run"]
		"chase":
			if is_instance_valid(target):
				move_to = target.global_position
				spd = sp["run"] * (0.85 if species == "bear" else 1.0)
				var reach: float = sp["len"] * 0.6 + 0.9
				if global_position.distance_to(target.global_position) < reach:
					spd = 0.0
					_face(target.global_position, dt * 8.0)
					if attack_cd <= 0.0:
						_attack(target)
			else:
				state = "idle"
		"eat":
			spd = 0.0
	var vel := Vector3.ZERO
	if spd > 0.0:
		var dir := move_to - global_position
		dir.y = 0
		if dir.length() > 0.2:
			dir = dir.normalized()
			dir = _avoid(dir)
			vel = dir * spd
			_face(global_position + dir, dt * 6.0)
	velocity.x = lerpf(velocity.x, vel.x, dt * 6.0)
	velocity.z = lerpf(velocity.z, vel.z, dt * 6.0)
	var float_y: float = -sp["leg"] - sp["r"] * 0.5
	if global_position.y < float_y - 0.2:
		velocity.y = lerpf(velocity.y, (float_y - global_position.y) * 3.0, dt * 3.0)
		velocity.x *= 0.65
		velocity.z *= 0.65
	elif is_on_floor():
		velocity.y = -1.0
	else:
		velocity.y -= _gravity * dt
	move_and_slide()
	var hv := Vector2(velocity.x, velocity.z).length()
	model.speed = hv
	model.state = "graze" if state == "graze" else "move"
	if spd > 0.5 and hv < spd * 0.2:
		_stuck += dt
		if _stuck > 1.0:
			_stuck = 0.0
			rotation.y += randf_range(1.5, 3.0)
			if state == "wander":
				_pick_wander()
	else:
		_stuck = 0.0
	if global_position.y < -30.0:
		queue_free()

func _avoid(dir: Vector3) -> Vector3:
	var ahead := global_position + dir * 2.0
	var h: float = world.gen.height_at(ahead.x, ahead.z)
	var limit := -7.0 if state in ["flee", "chase"] else -0.4
	if h < limit and not sp.get("swims", false):
		var alt := dir.rotated(Vector3.UP, 1.6)
		ahead = global_position + alt * 2.0
		if world.gen.height_at(ahead.x, ahead.z) > limit:
			return alt
		return -dir
	return dir

func _face(p: Vector3, k: float) -> void:
	var d := p - global_position
	if Vector2(d.x, d.z).length() < 0.01:
		return
	var yaw := atan2(-d.x, -d.z)
	rotation.y = lerp_angle(rotation.y, yaw, clampf(k, 0.0, 1.0))

func _pick_wander() -> void:
	var c := home if leader == null or not is_instance_valid(leader) else leader.global_position
	dest = c + Vector3(randf_range(-14, 14), 0, randf_range(-14, 14))
	state = "wander"
	state_t = 0.0

func _flee(from: Vector3) -> void:
	flee_from = from
	state = "flee"
	state_t = 0.0

func _alert_herd(from: Vector3) -> void:
	for a in world.ai.animals:
		if a != self and is_instance_valid(a) and not a.dead and a.species == species and a.global_position.distance_to(global_position) < 25.0:
			if a.sp.get("prey", false):
				a._flee(from)

func _alert_pack(t: Node3D) -> void:
	for a in world.ai.animals:
		if a != self and is_instance_valid(a) and not a.dead and a.species == species and a.global_position.distance_to(global_position) < 35.0:
			a.target = t
			a.state = "chase"
			a.state_t = 0.0

func _attack(t: Node3D) -> void:
	attack_cd = 1.3 if species != "croc" else 2.0
	model.play_attack()
	Sfx.play("growl", global_position, -2.0)
	if t.has_method("take_damage"):
		t.take_damage(sp["dmg"] * randf_range(0.8, 1.2), self)
	if t is Animal and t.dead:
		state = "eat"
		state_t = 0.0
		hunger = 0.0
		target = t

func _think() -> void:
	var player: Node3D = world.player
	var pd := global_position.distance_to(player.global_position) if player else 999.0
	var night: bool = world.sky.is_night()
	var detect: float = sp["detect"] * (0.55 if player and player.crouching else 1.0) * (0.75 if night else 1.0)
	var torch: bool = player != null and player.held_tool_kind() == "torch"
	var player_alive: bool = player != null and not player.stats.dead
	match state:
		"flee":
			if state_t > 6.0 and global_position.distance_to(flee_from) > detect * 1.5:
				_pick_wander()
			return
		"eat":
			if state_t > 18.0:
				_pick_wander()
			return
		"chase":
			if not is_instance_valid(target) or (target is Animal and target.dead):
				if is_instance_valid(target) and target is Animal and target.dead:
					state = "eat"
					state_t = 0.0
				else:
					_pick_wander()
				return
			var td := global_position.distance_to(target.global_position)
			var give_up: float = 45.0 if not sp.get("territorial", false) else 26.0
			if td > give_up or state_t > 40.0 or (target == player and not player_alive):
				target = null
				_pick_wander()
				return
			if hp < sp["hp"] * 0.25:
				_flee(target.global_position)
				return
			if torch and target == player and pd < 6.0 and species == "wolf" and randf() < 0.3:
				_flee(player.global_position)
				return
	# الفرائس تهرب من التهديدات
	if sp.get("prey", false):
		if player_alive and pd < detect:
			_flee(player.global_position)
			_alert_herd(player.global_position)
			return
		for a in world.ai.animals:
			if is_instance_valid(a) and not a.dead and a.sp.get("pred", false) and a.global_position.distance_to(global_position) < detect * 0.8:
				_flee(a.global_position)
				return
		for n in world.ai.active_npcs:
			if is_instance_valid(n) and n.global_position.distance_to(global_position) < detect * 0.5:
				_flee(n.global_position)
				return
	# المفترسات
	if sp.get("pred", false) or species == "boar":
		if player_alive and pd < detect:
			var aggressive := false
			if sp.get("ambush", false):
				aggressive = pd < 8.0
			elif sp.get("territorial", false):
				if pd < detect * 0.75 and not warned:
					warned = true
					Sfx.play("growl", global_position, 3.0)
					Game.notify("%s يزمجر محذراً! ابتعد" % sp["name"], Color(1, 0.55, 0.3))
				aggressive = pd < detect * 0.45 or provoked > 0.0
			elif species == "boar":
				aggressive = pd < 5.0 or provoked > 0.0
			else:
				aggressive = night or hunger > 0.6 or randf() < sp["aggro"] * 0.25
				if torch and pd > 4.0:
					aggressive = aggressive and randf() < 0.3
			if aggressive:
				target = player
				state = "chase"
				state_t = 0.0
				if species == "wolf":
					_alert_pack(player)
					if randf() < 0.3:
						Sfx.play("howl", global_position, 4.0)
				return
		if species == "wolf" and hunger > 0.5:
			for a in world.ai.animals:
				if is_instance_valid(a) and not a.dead and a.sp.get("prey", false) and a.global_position.distance_to(global_position) < detect:
					target = a
					state = "chase"
					state_t = 0.0
					_alert_pack(a)
					return
		if sp["dmg"] > 15.0 or species == "wolf":
			for n in world.ai.active_npcs:
				if is_instance_valid(n) and not n.dead and n.global_position.distance_to(global_position) < detect * 0.6 and (night or provoked > 0.0 or hunger > 0.8):
					target = n
					state = "chase"
					state_t = 0.0
					return
	if state == "idle" or state == "graze":
		if state_t > randf_range(3.0, 9.0):
			_pick_wander()
	if species == "wolf" and night and randf() < 0.004:
		Sfx.play("howl", global_position, 6.0)

func to_data() -> Dictionary:
	return {}
