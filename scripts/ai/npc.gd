class_name NPC
extends CharacterBody3D
## شخصية بشرية بذكاء اصطناعي: روتين يومي (عمل، أكل، نوم)، تواصل اجتماعي، صداقات وعداوات، شجار،
## سرقة، صيد، حراسة، ومرافقة اللاعب.

var world: Node
var ai: Node
var data: Dictionary
var npc_id := ""
var model: HumanModel
var label: Label3D
var bubble: Label3D
var bubble_t := 0.0
var hp := 100.0
var dead := false
var state := "idle"
var state_t := 0.0
var think_t := 0.0
var dest := Vector3.ZERO
var target: Node3D = null
var brawl := false
var partner: NPC = null
var work_res := []
var steal_target = null
var attack_cd := 0.0
var in_dialog := false
var flee_from := Vector3.ZERO
var hostile_to_player := false
var last_attacker = null
var dead_t := 0.0
var social_cd := 20.0
var greet_cd := 5.0
var pickpocket_cd := 40.0
var steal_cd := 90.0
var crouching := false
var _stuck := 0.0
var _steer := 0.0
var _gravity := 18.0
var _chat_lines := []
var _said_reply := false
var _carry_back := []

func setup(w: Node, d: Dictionary, pos: Vector3) -> void:
	world = w
	ai = w.ai
	data = d
	npc_id = d["id"]
	hp = d["hp"]
	position = pos
	collision_layer = 4
	collision_mask = 1 | 2 | 8 | 32
	var cs := CollisionShape3D.new()
	var sh := CapsuleShape3D.new()
	sh.radius = 0.3
	sh.height = 1.75
	cs.shape = sh
	cs.position = Vector3(0, 0.875, 0)
	add_child(cs)
	model = HumanModel.new()
	add_child(model)
	model.build(d["app"])
	if d["role"] in ["guard", "bandit"]:
		model.set_held(d["weapon"])
	label = Label3D.new()
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.pixel_size = 0.0035
	label.font_size = 36
	label.outline_size = 10
	label.position = Vector3(0, 2.15 * float(d["app"].get("height", 1.0)), 0)
	label.visibility_range_end = 22.0
	label.no_depth_test = false
	add_child(label)
	bubble = Label3D.new()
	bubble.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	bubble.pixel_size = 0.0032
	bubble.font_size = 34
	bubble.outline_size = 12
	bubble.modulate = Color(1, 1, 0.92)
	bubble.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	bubble.width = 620.0
	bubble.position = Vector3(0, 2.55, 0)
	bubble.visibility_range_end = 28.0
	bubble.visible = false
	add_child(bubble)
	floor_snap_length = 0.5
	_update_label()
	dest = pos
	if d["companion"]:
		state = "follow"

func _update_label() -> void:
	var r: float = ai.get_rel(npc_id, "player")
	var t: String = data["name"]
	if data["met"]:
		t += "\n" + ai.role_name(data)
	if data["companion"]:
		t = "[رفيق] " + t
	label.text = t
	label.modulate = AIManager.rel_color(r) if data["met"] else Color(0.85, 0.85, 0.85)

func say(text: String, dur := 4.0) -> void:
	bubble.text = text
	bubble.visible = true
	bubble_t = dur

func traits() -> Dictionary:
	return data["traits"]

func is_busy() -> bool:
	return dead or in_dialog or target != null or state in ["sleep", "socialize", "chatting", "chatting_passive", "steal", "stealing", "flee", "escape", "wait_social", "talk"]

# ------------------------------------------------------------------
func _physics_process(dt: float) -> void:
	if world == null:
		return
	if bubble_t > 0.0:
		bubble_t -= dt
		if bubble_t <= 0.0:
			bubble.visible = false
	if dead:
		dead_t += dt
		if not is_on_floor():
			velocity.y -= _gravity * dt
			velocity.x = 0
			velocity.z = 0
			move_and_slide()
		if dead_t > 200.0:
			queue_free()
		return
	think_t -= dt
	state_t += dt
	attack_cd -= dt
	social_cd -= dt
	greet_cd -= dt
	pickpocket_cd -= dt
	steal_cd -= dt
	if think_t <= 0.0:
		think_t = randf_range(0.35, 0.6)
		_think()
	_act(dt)

func _move(dt: float, to: Vector3, spd: float, stop_dist := 1.0) -> bool:
	var d := to - global_position
	d.y = 0
	var vel := Vector3.ZERO
	var arrived := d.length() < stop_dist
	if not arrived:
		var dir := d.normalized().rotated(Vector3.UP, _steer)
		vel = dir * spd
		_face(global_position + dir, dt * 7.0)
	velocity.x = lerpf(velocity.x, vel.x, dt * 8.0)
	velocity.z = lerpf(velocity.z, vel.z, dt * 8.0)
	return arrived

func _face(p: Vector3, k: float) -> void:
	var d := p - global_position
	if Vector2(d.x, d.z).length() < 0.01:
		return
	rotation.y = lerp_angle(rotation.y, atan2(-d.x, -d.z), clampf(k, 0.0, 1.0))

func _act(dt: float) -> void:
	var walk := 1.5
	var run := 4.6
	var mstate := "idle"
	var p: Node3D = world.player
	match state:
		"idle", "wait_social", "chatting_passive":
			_move(dt, global_position, 0.0)
			if state != "idle" and is_instance_valid(partner):
				_face(partner.global_position, dt * 5.0)
			if state == "chatting_passive":
				mstate = "talk"
				if state_t > 12.0:
					state = "idle"
		"talk":
			_move(dt, global_position, 0.0)
			_face(p.global_position, dt * 6.0)
			mstate = "talk"
		"wander", "patrol", "travel", "go_home", "go_eat", "go_work", "deposit", "greet":
			var spd := walk * (1.25 if state == "travel" else 1.0)
			if _move(dt, dest, spd, 1.3 if state != "greet" else 2.6):
				_arrive()
		"working":
			_move(dt, global_position, 0.0)
			if work_res.size() > 2:
				_face(work_res[2], dt * 5.0)
			mstate = "work"
			if state_t > 1.0 and model.swing_t < 0.0 and data["role"] in ["woodcutter", "miner"]:
				model.play_swing()
				Sfx.play("chop" if data["role"] == "woodcutter" else "mine", global_position, -6.0)
			if state_t > 7.0:
				_finish_work()
		"farming":
			_move(dt, global_position, 0.0)
			mstate = "work"
			if state_t > 9.0:
				data["inv"].add(["wheat", "potato", "cotton"][randi() % 3], randi_range(1, 2))
				_go_deposit()
		"sit":
			_move(dt, global_position, 0.0)
			mstate = "sit"
			if state_t > 25.0:
				state = "idle"
				state_t = 0.0
		"sleep":
			_move(dt, global_position, 0.0)
			mstate = "sleep"
		"socialize":
			if not is_instance_valid(partner) or partner.dead:
				state = "idle"
			elif _move(dt, partner.global_position, walk, 1.9):
				_start_chat()
		"chatting":
			_move(dt, global_position, 0.0)
			mstate = "talk"
			if is_instance_valid(partner):
				_face(partner.global_position, dt * 5.0)
			if state_t > 2.6 and not _said_reply and is_instance_valid(partner) and _chat_lines.size() > 1:
				_said_reply = true
				partner.say(_chat_lines[1], 3.5)
			if state_t > 6.0:
				_end_chat()
		"follow":
			var pd := global_position.distance_to(p.global_position)
			if pd > 60.0:
				global_position = p.global_position + Vector3(randf_range(-3, 3), 1.0, randf_range(-3, 3))
			var behind: Vector3 = p.global_position + p.global_transform.basis.z * 2.5 + p.global_transform.basis.x * 1.2
			if pd > 3.5:
				_move(dt, behind, run if pd > 9.0 else walk * 1.4, 1.0)
			else:
				_move(dt, global_position, 0.0)
				_face(p.global_position, dt * 3.0)
		"guarding":
			var gp: Vector3 = data["guard_pos"]
			if global_position.distance_to(gp) > 4.0:
				_move(dt, gp, walk, 1.5)
			elif _move(dt, dest, walk * 0.8, 1.2):
				dest = gp + Vector3(randf_range(-8, 8), 0, randf_range(-8, 8))
		"attack":
			if not is_instance_valid(target):
				target = null
				state = "idle"
			else:
				var reach := 1.9 if data["weapon"] != "" and ItemDB.tool_of(data["weapon"]).get("kind", "") == "spear" else 1.6
				if _move(dt, target.global_position, run, reach):
					_face(target.global_position, dt * 10.0)
					if attack_cd <= 0.0:
						_do_attack()
		"flee", "escape":
			var away := global_position - flee_from
			away.y = 0
			if away.length() < 0.1:
				away = Vector3(1, 0, 0)
			_move(dt, global_position + away.normalized() * 10.0, run)
			if state_t > (9.0 if state == "flee" else 20.0):
				state = "wander" if state == "flee" else "travel"
				_pick_wander()
		"steal":
			if steal_target == null or not is_instance_valid(steal_target):
				state = "idle"
			elif _move(dt, steal_target.global_position, walk * 1.2, 1.9):
				state = "stealing"
				state_t = 0.0
		"stealing":
			_move(dt, global_position, 0.0)
			mstate = "work"
			if state_t > 4.0:
				_do_steal()
		"skin":
			if work_res.is_empty() or not is_instance_valid(work_res[0]):
				state = "idle"
			elif _move(dt, work_res[0].global_position, walk, 1.5):
				mstate = "work"
				if state_t > 12.0:
					var an = work_res[0]
					if an is Animal and an.dead and not an.harvested:
						an.harvested = true
						for dr in an.sp["drops"]:
							data["inv"].add(dr[0], randi_range(dr[1], dr[2]))
						an.queue_free()
					work_res = []
					_go_deposit()
	# الجاذبية والحركة والسباحة
	var swimming := global_position.y < -1.15
	if swimming:
		velocity.y = lerpf(velocity.y, (-global_position.y - 1.3) * 3.0, dt * 3.0)
		velocity.x *= 0.6
		velocity.z *= 0.6
	elif is_on_floor():
		velocity.y = -1.0
	else:
		velocity.y -= _gravity * dt
	move_and_slide()
	var hv := Vector2(velocity.x, velocity.z).length()
	model.speed = hv
	model.state = mstate if hv < 0.3 or mstate == "idle" else "idle"
	if swimming:
		model.state = "swim"
	if state in ["sleep", "sit"]:
		model.state = mstate
	if hv < 0.2 and state in ["wander", "patrol", "travel", "go_home", "go_eat", "go_work", "deposit", "socialize", "steal", "greet"]:
		_stuck += dt
		if _stuck > 2.0:
			_stuck = 0.0
			_steer = randf_range(-1.6, 1.6)
			if state_t > 25.0:
				state = "idle"
				state_t = 0.0
	else:
		_stuck = 0.0
		_steer = move_toward(_steer, 0.0, dt * 0.5)

func _arrive() -> void:
	match state:
		"go_home":
			if _is_sleep_time():
				state = "sleep"
				say("تصبحون على خير...", 2.5)
			else:
				state = "idle"
		"go_eat":
			state = "sit"
			if randf() < 0.3:
				say(["حان وقت الطعام!", "رائحة الطعام شهية.", "يوم طويل..."][randi() % 3], 3.0)
		"go_work":
			state = "working" if data["role"] != "farmer" else "farming"
		"deposit":
			_deposit()
			state = "idle"
		"greet":
			if world.player.global_position.distance_to(global_position) < 4.0:
				say(ai.greeting(data) if not data["met"] else _ambient_line(), 4.0)
				data["met"] = true
				_update_label()
			state = "idle"
		_:
			state = "idle"
	state_t = 0.0

func _ambient_line() -> String:
	var r: float = ai.get_rel(npc_id, "player")
	if r > 50.0:
		return ["أهلاً يا صديقي!", "سعيد برؤيتك!", "تعال زرنا قريباً!"][randi() % 3]
	if r > 10.0:
		return ["مرحباً!", "يوم جميل، أليس كذلك؟", "كيف حالك؟"][randi() % 3]
	return ["...", "همم.", "نعم؟"][randi() % 3]

# ------------------------------------------------------------------
func _is_sleep_time() -> bool:
	var h: float = world.sky.hour_of_day()
	var sa: float = data["sleep_at"]
	var wa: float = data["wake_at"]
	if data["role"] == "bandit":
		sa = 3.0
		wa = 10.0
		return h >= sa and h < wa
	if data["role"] == "thief":
		return h >= 9.0 and h < 14.0
	return h >= sa or h < wa

func _think() -> void:
	var p: Node3D = world.player
	var pd := global_position.distance_to(p.global_position)
	var r: float = ai.get_rel(npc_id, "player")
	var t := traits()
	_update_label()
	_check_obstacle()
	if in_dialog:
		state = "talk"
		return
	if state == "talk":
		state = "idle"
	# ---- القتال
	if target != null:
		if not is_instance_valid(target) or (target.get("dead") == true) or (target == p and p.stats.dead):
			_end_combat()
		elif brawl and target is NPC and target.hp < target.data["max_hp"] * 0.3:
			say(["كفى! لقد تعلمت الدرس.", "هذا يكفي!", "لا تعترض طريقي مرة أخرى!"][randi() % 3])
			target.say("حسناً... أستسلم!", 3.0)
			target.target = null
			target.state = "flee"
			target.flee_from = global_position
			_end_combat()
		elif hp < data["max_hp"] * 0.28 and not (t["brave"] > 0.8):
			flee_from = target.global_position
			say(["النجدة!", "سأهرب!", "لا تقتلني!"][randi() % 3], 2.5)
			_end_combat()
			state = "flee"
			state_t = 0.0
		elif global_position.distance_to(target.global_position) > 45.0:
			_end_combat()
		else:
			state = "attack"
			return
	if state == "flee" or state == "escape":
		return
	# ---- تهديدات من الحيوانات
	var threat := _nearest_threat(14.0)
	if threat != null:
		var fighter: bool = data["role"] in ["guard", "hunter", "bandit"] or t["brave"] > 0.55
		if fighter and hp > data["max_hp"] * 0.4:
			_engage(threat, false)
		else:
			flee_from = threat.global_position
			state = "flee"
			state_t = 0.0
			say("حيوان مفترس! اهربوا!", 2.5)
		return
	# ---- العداء للاعب
	if not p.stats.dead:
		var bandit_range := 30.0 if data["role"] == "bandit" else 20.0
		if pd < bandit_range:
			var hostile = hostile_to_player or (r < -55.0 and t["aggr"] > 0.3) or (data["role"] == "bandit" and r < 15.0 and not data["companion"])
			if hostile:
				become_hostile_to(p, false)
				return
	if hostile_to_player and r > -20.0:
		hostile_to_player = false
	# ---- الرفيق
	if data["companion"]:
		_companion_think(p, pd)
		return
	# ---- الحراس يطاردون قطاع الطرق
	if data["role"] == "guard":
		for n in ai.active_npcs:
			if is_instance_valid(n) and n != self and not n.dead and n.data["role"] == "bandit" and n.global_position.distance_to(global_position) < 28.0 and not n.data["companion"]:
				say("قاطع طريق! أوقفوه!", 2.5)
				_engage(n, false)
				return
	# ---- النوم
	if _is_sleep_time():
		if state != "sleep" and state != "go_home":
			state = "go_home"
			dest = data["home"]
			state_t = 0.0
		return
	if state == "sleep":
		state = "idle"
		state_t = 0.0
	# ---- اللص، أو قاطع طريق في غارة
	if data["role"] == "thief" and _thief_think(p, pd):
		return
	if data.get("raid", Vector3.INF) != Vector3.INF:
		var rp: Vector3 = data["raid"]
		if state in ["steal", "stealing", "escape"]:
			return
		if global_position.distance_to(rp) > 12.0:
			state = "travel"
			dest = rp
			return
		var loot = null
		for st in world.build.player_storages():
			if is_instance_valid(st) and st.global_position.distance_to(rp) < 30.0 and not st.inventory.is_empty():
				loot = st
				break
		if loot != null and steal_cd <= 0.0:
			steal_target = loot
			state = "steal"
			state_t = 0.0
			steal_cd = 60.0
			say("فتشوا المكان!", 2.5)
			return
		data["raid"] = Vector3.INF
		data["travel_to"] = data["home"]
		dest = data["home"]
		state = "travel"
		return
	if state in ["socialize", "chatting", "chatting_passive", "wait_social", "working", "farming", "go_work", "deposit", "steal", "stealing", "skin"]:
		if state_t < 40.0:
			return
		state = "idle"
	# ---- الترحيب باللاعب
	if greet_cd <= 0.0 and pd < 13.0 and r > -12.0 and data["role"] != "bandit":
		greet_cd = randf_range(90.0, 200.0)
		if not data["met"] or t["social"] > 0.45:
			state = "greet"
			dest = p.global_position
			state_t = 0.0
			return
	var h: float = world.sky.hour_of_day()
	var s: Dictionary = ai.settlement_of(data)
	# ---- الوجبات
	if not s.is_empty() and ((h > 12.0 and h < 13.0) or (h > 18.5 and h < 19.6)) and state not in ["sit", "go_eat"]:
		if randf() < 0.5:
			state = "go_eat"
			dest = s["pos"] + Vector3(randf_range(-3.5, 3.5), 0, randf_range(-3.5, 3.5))
			state_t = 0.0
			return
	if state in ["sit", "go_eat", "greet", "go_home"] and state_t < 30.0:
		return
	# ---- التواصل الاجتماعي
	if social_cd <= 0.0 and randf() < 0.15 + t["social"] * 0.35:
		social_cd = randf_range(25.0, 70.0)
		var best: NPC = null
		var bd := 28.0
		for n in ai.active_npcs:
			if n == self or not is_instance_valid(n) or n.is_busy() or n.data["companion"]:
				continue
			var dd := global_position.distance_to(n.global_position)
			if dd < bd:
				bd = dd
				best = n
		if best != null:
			partner = best
			best.partner = self
			best.state = "wait_social"
			best.state_t = 0.0
			state = "socialize"
			state_t = 0.0
			return
	# ---- العمل
	if state in ["idle", "wander", "patrol"] and state_t > randf_range(4.0, 10.0):
		if randf() < 0.6:
			_start_work()
		else:
			_pick_wander()

func _check_obstacle() -> void:
	if state in ["idle", "sleep", "sit", "talk", "chatting", "working"]:
		return
	var fwd := -global_transform.basis.z
	var from := global_position + Vector3(0, 0.6, 0)
	var q := PhysicsRayQueryParameters3D.create(from, from + fwd * 1.4, 8 | 32)
	q.exclude = [get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if not hit.is_empty():
		_steer = 0.9 if randf() < 0.5 else -0.9
	var ahead := global_position + fwd * 3.0
	if world.gen.height_at(ahead.x, ahead.z) < -7.0:
		_steer = PI * 0.6

func _nearest_threat(radius: float) -> Node3D:
	for a in ai.animals:
		if not is_instance_valid(a) or a.dead:
			continue
		if a.state == "chase" and a.target == self:
			return a
		if a.sp.get("pred", false) and a.state == "chase" and a.global_position.distance_to(global_position) < radius * 0.6:
			return a
	return null

func _engage(t: Node3D, is_brawl: bool) -> void:
	target = t
	brawl = is_brawl
	state = "attack"
	state_t = 0.0
	if data["weapon"] != "":
		model.set_held(data["weapon"])

func _end_combat() -> void:
	target = null
	brawl = false
	state = "idle"
	state_t = 0.0
	if not data["role"] in ["guard", "bandit"]:
		model.set_held("")

func become_hostile_to(t: Node3D, is_brawl: bool) -> void:
	if dead or data["companion"] and t == world.player and ai.get_rel(npc_id, "player") > 15.0:
		return
	if t == world.player:
		hostile_to_player = not is_brawl
		if target != t:
			say(["ستندم على هذا!", "سأقضي عليك!", "هجوم!", "لن تفلت مني!"][randi() % 4], 2.5)
	_engage(t, is_brawl)

func _do_attack() -> void:
	var w: String = data["weapon"]
	var dmg := 5.0
	var kind := "club"
	if w != "":
		var td := ItemDB.tool_of(w)
		dmg = td.get("dmg", 5.0)
		kind = td.get("kind", "club")
	attack_cd = randf_range(1.0, 1.5)
	model.play_swing("thrust" if kind == "spear" else "chop")
	if brawl:
		dmg *= 0.45
	var d2 := global_position.distance_to(target.global_position)
	if d2 > 2.4:
		return
	if target.has_method("take_damage"):
		target.take_damage(dmg * randf_range(0.8, 1.2), self)

func take_damage(dmg: float, attacker) -> void:
	if dead:
		return
	hp -= dmg
	model.flash_hit()
	Sfx.play("hurt", global_position, -3.0)
	world.fx_burst(global_position + Vector3(0, 1.2, 0), Color(0.6, 0.05, 0.05))
	last_attacker = attacker
	var p: Node3D = world.player
	if attacker == p:
		ai.add_rel(npc_id, "player", -(10.0 + dmg * 0.6))
		ai.remember(npc_id, "attack", "player")
		if not hostile_to_player and data["role"] != "bandit":
			ai.witness(global_position, "player", npc_id, 12.0, "attack", 25.0)
		for n in ai.active_npcs:
			if n == self or not is_instance_valid(n) or n.dead or n.data["companion"]:
				continue
			if n.global_position.distance_to(global_position) < 25.0:
				var friend: bool = ai.get_rel(n.npc_id, npc_id) > 25.0 or (n.data["faction"] != "" and n.data["faction"] == data["faction"])
				if friend and (n.traits()["brave"] > 0.4 or n.data["role"] == "guard") and data["role"] != "bandit" or (n.data["role"] == "bandit" and data["role"] == "bandit"):
					n.become_hostile_to(p, false)
	elif attacker is NPC:
		ai.add_rel(npc_id, attacker.npc_id, -12.0)
		if not brawl:
			for n in ai.active_npcs:
				if n == self or n == attacker or not is_instance_valid(n) or n.dead:
					continue
				if n.global_position.distance_to(global_position) < 20.0 and ai.get_rel(n.npc_id, npc_id) > 35.0 and n.traits()["brave"] > 0.5 and n.target == null:
					n._engage(attacker, false)
	if hp <= 0.0:
		if brawl and attacker is NPC:
			hp = 8.0
		else:
			_die(attacker)
			return
	if attacker != null and is_instance_valid(attacker) and target != attacker:
		var fighter: bool = traits()["brave"] > 0.35 or data["role"] in ["guard", "bandit", "hunter"]
		if fighter and hp > data["max_hp"] * 0.3:
			var is_brawl: bool = attacker is NPC and attacker.brawl
			if attacker == p:
				become_hostile_to(p, false)
			else:
				_engage(attacker, is_brawl)
		else:
			flee_from = attacker.global_position
			state = "flee"
			state_t = 0.0
			say("النجدة!", 2.0)

func _die(killer) -> void:
	dead = true
	data["alive"] = false
	data["hp"] = 0.0
	state = "dead"
	model.state = "dead"
	model.set_held("")
	label.visible = false
	bubble.visible = false
	collision_layer = 0
	collision_mask = 1
	var items := []
	var inv: Inventory = data["inv"]
	for s in inv.slots:
		if s != null:
			items.append(s.duplicate())
	if data["weapon"] != "" and randf() < 0.6:
		items.append({"id": data["weapon"], "n": 1, "d": ItemDB.max_dur(data["weapon"]) * 0.5, "a": 0.0})
	if not items.is_empty():
		world.spawn_loot(global_position + Vector3(0, 0.3, 0), items, "متاع %s" % data["name"])
	Sfx.play("hurt", global_position, 2.0, 0.3)
	ai.on_npc_killed(self, killer)

# ------------------------------------------------------------------
func _companion_think(p: Node3D, pd: float) -> void:
	# الدفاع عن اللاعب
	var la = p.last_attacker
	if la != null and is_instance_valid(la) and la != self and la.get("dead") != true and la.global_position.distance_to(p.global_position) < 25.0 and p.last_attacked_t < 8.0:
		_engage(la, false)
		say("لن أسمح لك بإيذائه!", 2.0)
		return
	var lt = p.last_target
	if lt != null and is_instance_valid(lt) and lt != self and lt.get("dead") != true and p.last_target_t < 5.0 and lt.global_position.distance_to(global_position) < 30.0:
		if not (lt is NPC and ai.get_rel(npc_id, lt.npc_id) > 50.0):
			_engage(lt, false)
			return
	match data["order"]:
		"follow":
			state = "follow"
		"stay":
			state = "idle"
		"guard":
			if state != "guarding":
				state = "guarding"
				dest = data["guard_pos"]
			for n in ai.active_npcs:
				if is_instance_valid(n) and n != self and not n.dead and n.global_position.distance_to(data["guard_pos"]) < 22.0:
					if n.state in ["steal", "stealing"] or n.hostile_to_player:
						say("أمسكتك يا لص!" if n.state in ["steal", "stealing"] else "عدو!", 2.5)
						_engage(n, false)
						return
			for a in ai.animals:
				if is_instance_valid(a) and not a.dead and a.sp.get("pred", false) and a.global_position.distance_to(data["guard_pos"]) < 20.0:
					_engage(a, false)
					return

func _thief_think(p: Node3D, pd: float) -> bool:
	if state in ["steal", "stealing", "escape"]:
		return true
	if pd < 2.4 and pickpocket_cd <= 0.0 and randf() < traits()["greed"] * 0.25:
		pickpocket_cd = randf_range(200.0, 400.0)
		_pickpocket(p)
		return true
	if steal_cd > 0.0:
		return false
	var best = null
	var bd := 220.0
	for st in world.build.player_storages():
		if not is_instance_valid(st):
			continue
		var d2 := global_position.distance_to(st.global_position)
		if d2 < bd and st.global_position.distance_to(p.global_position) > 40.0:
			bd = d2
			best = st
	if best == null:
		best = world.build.settlement_chest_near(global_position, 120.0, data["faction"])
	if best != null:
		steal_target = best
		state = "steal"
		state_t = 0.0
		steal_cd = randf_range(300.0, 600.0)
		return true
	return false

func _pickpocket(p: Node3D) -> void:
	var inv: Inventory = p.inventory
	var cands := []
	for i in range(6, inv.size()):
		if inv.slots[i] != null:
			cands.append(i)
	if cands.is_empty():
		return
	var i: int = cands[randi() % cands.size()]
	var s: Dictionary = inv.slots[i]
	var take := maxi(1, int(s["n"] / 2))
	var st := inv.take_slot(i, take)
	data["inv"].add_stack(st)
	data["stolen"].append([st["id"], st["n"]])
	var caught = randf() < 0.55 + p.stats.skill_level("social") * 0.02
	if caught:
		data["exposed"] = true
		ai.add_rel(npc_id, "player", -10.0)
		Game.notify("%s سرق منك %s ×%d! أمسك به!" % [data["name"], ItemDB.name_of(st["id"]), st["n"]], Color(1, 0.4, 0.3))
		ai.log_event("%s نشل %s من حقيبتك" % [data["name"], ItemDB.name_of(st["id"])])
		flee_from = p.global_position
		state = "escape"
	else:
		Game.notify("تشعر أن حقيبتك أصبحت أخف قليلاً...", Color(1, 0.8, 0.5))
		ai.log_event("فقدت %s من حقيبتك بطريقة غامضة" % ItemDB.name_of(st["id"]))
		state = "wander"
		_pick_wander()
	state_t = 0.0

func _do_steal() -> void:
	var st = steal_target
	steal_target = null
	if st == null or not is_instance_valid(st):
		state = "idle"
		return
	var is_player: bool = st.owner_id == "player"
	if st.is_secure():
		if randf() > 0.12:
			state = "travel"
			_pick_wander()
			if is_player and world.player.global_position.distance_to(st.global_position) < 50.0:
				Game.notify("أحدهم حاول فتح خزنتك وفشل!", Color(1, 0.7, 0.4))
			return
	var inv: Inventory = st.inventory
	var taken := []
	for i in inv.most_valuable(randi_range(1, 3)):
		var s = inv.slots[i]
		if s == null:
			continue
		var n: int = mini(s["n"], maxi(1, data["inv"].room_for(s["id"])))
		if n <= 0:
			continue
		var part := inv.take_slot(i, n)
		data["inv"].add_stack(part)
		taken.append([part["id"], part["n"]])
	if taken.is_empty():
		state = "travel"
		_pick_wander()
		return
	if is_player and data.get("raid", Vector3.INF) != Vector3.INF:
		ai.log_event("قطاع الطرق نهبوا %s!" % st.display_name())
		Game.notify("قطاع الطرق ينهبون %s!" % st.display_name(), Color(1, 0.35, 0.3))
	if is_player:
		for e in taken:
			data["stolen"].append(e)
		st.mark_tampered()
		var witnesses: Array = ai.witness(st.global_position, npc_id, "player", 25.0, "steal_player", 28.0)
		var names := []
		for e in taken:
			names.append("%s ×%d" % [ItemDB.name_of(e[0]), e[1]])
		if world.player.global_position.distance_to(st.global_position) < 38.0:
			data["exposed"] = true
			Game.notify("%s يسرق من %s! (%s)" % [data["name"], st.display_name(), "، ".join(names)], Color(1, 0.35, 0.3))
			ai.log_event("رأيت %s يسرق من %s" % [data["name"], st.display_name()])
		else:
			ai.log_event("سُرقت أغراض من %s (%s)" % [st.display_name(), "، ".join(names)])
		for w in witnesses:
			if w.data["companion"]:
				w.say("لص!", 2.0)
				w._engage(self, false)
	else:
		ai.witness(st.global_position, npc_id, "", 20.0, "steal", 22.0)
	flee_from = st.global_position
	state = "escape"
	state_t = 0.0

# ------------------------------------------------------------------
func _start_chat() -> void:
	if not is_instance_valid(partner):
		state = "idle"
		return
	_chat_lines = ai.converse(npc_id, partner.npc_id)
	say(_chat_lines[0], 3.5)
	_said_reply = false
	state = "chatting"
	state_t = 0.0
	partner.state = "chatting_passive"
	partner.state_t = 0.0

func _end_chat() -> void:
	var pr := partner
	partner = null
	state = "idle"
	state_t = 0.0
	if is_instance_valid(pr):
		pr.partner = null
		pr.state = "idle"
		pr.state_t = 0.0
		if _chat_lines.size() > 2 and _chat_lines[2] == "fight":
			say("سأريك!", 2.5)
			pr.say("هل تريد قتالاً؟!", 2.5)
			_engage(pr, true)
			pr._engage(self, true)
			if world.player.global_position.distance_to(global_position) < 40.0:
				ai.log_event("شجار بين %s و%s" % [data["name"], pr.data["name"]])

func _pick_wander() -> void:
	var s: Dictionary = ai.settlement_of(data)
	var c: Vector3 = data["home"]
	var rad := 14.0
	if data["role"] in ["wanderer", "thief"] or (data["role"] == "trader" and s.is_empty()):
		if data["travel_to"] != Vector3.INF and global_position.distance_to(data["travel_to"]) > 6.0:
			dest = data["travel_to"]
			state = "travel"
			state_t = 0.0
			return
		if ai.settlements.size() > 0 and randf() < 0.35:
			var ss: Dictionary = ai.settlements[randi() % ai.settlements.size()]
			if not ss["hostile"]:
				data["travel_to"] = ss["pos"] + Vector3(randf_range(-15, 15), 0, randf_range(-15, 15))
				dest = data["travel_to"]
				state = "travel"
				state_t = 0.0
				return
		c = global_position
		rad = 25.0
	if data["role"] == "guard" and not s.is_empty():
		c = s["pos"]
		rad = 22.0
		state = "patrol"
	else:
		state = "wander"
	dest = c + Vector3(randf_range(-rad, rad), 0, randf_range(-rad, rad))
	state_t = 0.0

func _start_work() -> void:
	var kinds := []
	match data["role"]:
		"woodcutter": kinds = ["oak", "birch", "pine", "dead_tree", "palm"]
		"miner": kinds = ["boulder", "copper", "tin", "coal", "iron", "rock_small"]
		"healer": kinds = ["herb", "berry_bush", "mushroom"]
		"farmer":
			state = "go_work"
			dest = data["home"] + Vector3(randf_range(-10, 10), 0, randf_range(-10, 10))
			state_t = 0.0
			return
		"hunter":
			for a in ai.animals:
				if is_instance_valid(a) and not a.dead and a.sp.get("prey", false) and a.global_position.distance_to(global_position) < 55.0:
					_engage(a, false)
					model.set_held(data["weapon"])
					return
				if is_instance_valid(a) and a.dead and not a.harvested and a.global_position.distance_to(global_position) < 40.0:
					work_res = [a]
					state = "skin"
					state_t = 0.0
					return
		"elder", "trader", "smith":
			var s: Dictionary = ai.settlement_of(data)
			if not s.is_empty() and randf() < 0.5:
				state = "go_eat"
				dest = s["pos"] + Vector3(randf_range(-3.5, 3.5), 0, randf_range(-3.5, 3.5))
				state_t = 0.0
				return
	if kinds.is_empty():
		_pick_wander()
		return
	var res: Array = world.terrain.find_resource(data["home"], kinds, 48.0)
	if res.is_empty():
		_pick_wander()
		return
	work_res = res
	dest = res[2]
	state = "go_work"
	state_t = 0.0
	if data["role"] in ["woodcutter", "miner"]:
		model.set_held("stone_axe" if data["role"] == "woodcutter" else "stone_pickaxe")

func _finish_work() -> void:
	if work_res.size() >= 2 and world.terrain.is_available(work_res[0], work_res[1]):
		var y: Array = world.terrain.deplete(work_res[0], work_res[1], 0.7)
		for e in y:
			data["inv"].add(e[0], e[1])
	work_res = []
	_go_deposit()

func _go_deposit() -> void:
	var chest = world.build.settlement_chest(data["faction"])
	if chest != null:
		state = "deposit"
		dest = chest.global_position
	else:
		state = "idle"
	state_t = 0.0
	if not data["role"] in ["guard", "bandit"]:
		model.set_held("")

func _deposit() -> void:
	var chest = world.build.settlement_chest(data["faction"])
	if chest == null:
		return
	var inv: Inventory = data["inv"]
	for i in range(inv.size()):
		var s = inv.slots[i]
		if s == null:
			continue
		if s["id"] in ["wood", "stone", "wheat", "potato", "cotton", "herbs", "berries", "raw_meat", "hide", "copper_ore", "tin_ore", "iron_ore", "coal", "mushroom", "stick", "fiber", "resin", "bone", "fur"]:
			if inv.count(s["id"]) > 4:
				var part := inv.take_slot(i, s["n"] - 2)
				var left: int = chest.inventory.add_stack(part)
				if left > 0:
					inv.add(part["id"], left)

# ------------------------------------------------------------------
func get_interact_text(_p) -> String:
	if dead:
		return ""
	return "تحدث مع %s" % data["name"]

func interact(p) -> void:
	if dead:
		return
	if hostile_to_player or (target == p):
		say("لا حديث بيننا!", 2.0)
		return
	world.hud.open_dialog(self)

func on_hit(dmg: float, _kind: String, _tier: int, attacker, _pos: Vector3) -> void:
	var mult := 1.0
	if attacker != null and attacker.get("stats") != null:
		mult = attacker.stats.skill_power_mult("hunting")
	take_damage(dmg * mult, attacker)
