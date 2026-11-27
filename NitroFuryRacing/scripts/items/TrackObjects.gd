class_name TrackObjects
extends Node3D

## Manages CTR-Style ? Item Crates (with 3D Wooden Splinter Smash Burst!),
## Golden Nitro Fruits, Dropped TNT Crates, Sculpted Homing Shark-Rockets,
## Sculpted Riveted Bowling Bombs, 3D Fireball + Shockwave Explosions, Shields & Spirit Mask Ramming!

var _crates: Array[Dictionary] = []
var _fruits: Array[Dictionary] = []
var _projectiles: Array[Dictionary] = []
var _hazards: Array[Dictionary] = []
var _explosions: Array[Dictionary] = []
var _splinters: Array[Dictionary] = []
var _pool_missiles: Array[Node3D] = []
var _pool_bombs: Array[Node3D] = []
var _pool_tnts: Array[Node3D] = []
var _prewarm_frames: int = 3
var _karts: Array[KartPhysics] = []
var _spline: TrackSpline
var _time: float = 0.0

var _crate_mesh: BoxMesh
var _crate_mat: StandardMaterial3D
var _tnt_mat: StandardMaterial3D
var _fruit_mesh: SphereMesh
var _fruit_mat: StandardMaterial3D
var _rocket_mat: StandardMaterial3D
var _bomb_mat: StandardMaterial3D

static var _obj_glb_cache: Dictionary = {}

static func _inst_glb(path: String) -> Node3D:
	if not _obj_glb_cache.has(path):
		var res = load(path)
		if res is PackedScene:
			_obj_glb_cache[path] = res
		else:
			return null
	return (_obj_glb_cache[path] as PackedScene).instantiate() as Node3D

func setup(spline: TrackSpline, karts: Array[KartPhysics], crate_pts: Array[Vector3], fruit_pts: Array[Vector3]) -> void:
	for c in get_children():
		c.queue_free()
	_crates.clear()
	_fruits.clear()
	_projectiles.clear()
	_hazards.clear()
	_explosions.clear()
	_splinters.clear()
	_pool_missiles.clear()
	_pool_bombs.clear()
	_pool_tnts.clear()
	_prewarm_frames = 3
	_spline = spline
	_karts = karts
	_init_shared_assets()
	_init_fx_pools()

	for pt in crate_pts:
		var node := _inst_glb("res://assets/models/prop_crate_item.glb")
		if node == null:
			var mi := MeshInstance3D.new()
			mi.mesh = _crate_mesh; mi.material_override = _crate_mat
			node = mi
		node.scale = Vector3(1.05, 1.05, 1.05)
		node.position = pt
		add_child(node)
		_crates.append({"node": node, "base_pos": pt, "active": true, "respawn": 0.0, "phase": randf() * TAU})

	for idx in range(fruit_pts.size()):
		var pt: Vector3 = fruit_pts[idx]
		# Alternate Radiant Floating Diamond Crystals & Nitro Fruits (matching reference aesthetic!)
		var is_crystal := (idx % 2 == 0)
		var glb_p := "res://assets/models/prop_crystal_pickup.glb" if is_crystal else "res://assets/models/prop_nitro_fruit.glb"
		var root := _inst_glb(glb_p)
		if root == null:
			root = Node3D.new()
			var body := MeshInstance3D.new()
			body.mesh = _fruit_mesh; body.material_override = _fruit_mat
			root.add_child(body)
		var sc_f := 1.02 if is_crystal else 1.22
		root.scale = Vector3(sc_f, sc_f, sc_f)
		root.position = pt + Vector3(0.0, 0.38 if is_crystal else 0.0, 0.0)
		if is_crystal:
			_style_crystal_materials(root)
		add_child(root)
		_fruits.append({"node": root, "base_pos": root.position, "active": true, "respawn": 0.0, "phase": randf() * TAU, "is_crystal": is_crystal})

func _style_crystal_materials(node: Node) -> void:
	if node is MeshInstance3D:
		var mi := node as MeshInstance3D
		if mi.mesh:
			for si in range(mi.mesh.get_surface_count()):
				var sm := mi.get_active_material(si)
				if sm is StandardMaterial3D:
					var m := StandardMaterial3D.new()
					m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
					m.roughness = 0.08
					m.metallic = 0.22
					if sm.resource_name.begins_with("CrystalHalo"):
						m.albedo_color = Color(0.68, 0.44, 1.0, 0.62)
						m.emission_enabled = true
						m.emission = Color(0.62, 0.36, 1.0)
						m.emission_energy_multiplier = 0.85
					else:
						m.albedo_color = Color(0.28, 0.82, 1.0, 0.84)
						m.emission_enabled = true
						m.emission = Color(0.18, 0.72, 1.0)
						m.emission_energy_multiplier = 0.90
					mi.set_surface_override_material(si, m)
	for c in node.get_children():
		_style_crystal_materials(c)

func _init_shared_assets() -> void:
	_crate_mesh = BoxMesh.new()
	_crate_mesh.size = Vector3(1.65, 1.65, 1.65)
	_crate_mat = StandardMaterial3D.new()
	if ProceduralTextures:
		_crate_mat.albedo_texture = ProceduralTextures.get_texture("crate_item")
	_crate_mat.roughness = 0.65

	_tnt_mat = StandardMaterial3D.new()
	if ProceduralTextures:
		_tnt_mat.albedo_texture = ProceduralTextures.get_texture("crate_tnt")
	_tnt_mat.roughness = 0.55

	_fruit_mesh = SphereMesh.new()
	_fruit_mesh.radius = 0.52
	_fruit_mesh.height = 1.04
	_fruit_mesh.radial_segments = 10
	_fruit_mesh.rings = 6
	_fruit_mat = StandardMaterial3D.new()
	_fruit_mat.albedo_color = Color(1.0, 0.68, 0.08)
	_fruit_mat.emission_enabled = true
	_fruit_mat.emission = Color(0.95, 0.45, 0.04)
	_fruit_mat.emission_energy_multiplier = 0.45
	_fruit_mat.roughness = 0.28

	_rocket_mat = StandardMaterial3D.new()
	_rocket_mat.albedo_color = Color(0.96, 0.15, 0.10)
	_rocket_mat.emission_enabled = true
	_rocket_mat.emission = Color(1.0, 0.42, 0.06)
	_rocket_mat.emission_energy_multiplier = 1.2

	_bomb_mat = StandardMaterial3D.new()
	_bomb_mat.albedo_color = Color(0.10, 0.12, 0.16)
	_bomb_mat.roughness = 0.25
	_bomb_mat.metallic = 0.55

func _init_fx_pools() -> void:
	# 1. Pool of 4 3D Weapon Explosion Fireballs + Expanding Shockwave Rings!
	var sph := SphereMesh.new()
	sph.radius = 1.0; sph.height = 2.0; sph.radial_segments = 12; sph.rings = 6
	var tor := TorusMesh.new()
	tor.inner_radius = 0.85; tor.outer_radius = 1.15; tor.rings = 14; tor.ring_segments = 8
	for _i in range(4):
		var root := Node3D.new()
		root.visible = false
		add_child(root)
		var ball := MeshInstance3D.new()
		ball.mesh = sph
		ball.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var bmat := StandardMaterial3D.new()
		bmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		bmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		bmat.albedo_color = Color(1.0, 0.55, 0.08, 0.9)
		ball.material_override = bmat
		root.add_child(ball)

		var ring := MeshInstance3D.new()
		ring.mesh = tor
		ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var rmat := StandardMaterial3D.new()
		rmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		rmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		rmat.albedo_color = Color(1.0, 0.88, 0.24, 0.9)
		ring.material_override = rmat
		root.add_child(ring)
		_explosions.append({"root": root, "ball": ball, "bmat": bmat, "ring": ring, "rmat": rmat, "life": 0.0, "max_life": 0.48, "juiced": false})

	# 2. Pool of 12 3D Flying Wooden Crate Smash Splinters!
	var plank := BoxMesh.new()
	plank.size = Vector3(0.68, 0.16, 0.22)
	var pmat := StandardMaterial3D.new()
	pmat.albedo_color = Color(0.76, 0.46, 0.16)
	pmat.roughness = 0.75
	for _i in range(12):
		var mi := MeshInstance3D.new()
		mi.mesh = plank
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.material_override = pmat
		mi.visible = false
		add_child(mi)
		_splinters.append({"node": mi, "vel": Vector3.ZERO, "rot_vel": Vector3.ZERO, "life": 0.0})

	# 3. Pre-warmed 3D Weapon Pools (ZERO mid-race add_child / GLES3 shader-compile stutters on Android!)
	var warm_pos := Vector3(0.0, -40.0, 0.0)
	if _spline != null and _spline.samples.size() > 0:
		warm_pos = _spline.samples[0]["pos"] + Vector3(0.0, -8.0, 0.0)
	for _i in range(4):
		var m_nd := _inst_glb("res://assets/models/prop_weapon_missile.glb")
		if m_nd == null:
			var mi := MeshInstance3D.new()
			var cm := CylinderMesh.new()
			cm.top_radius = 0.08; cm.bottom_radius = 0.36; cm.height = 1.9
			mi.mesh = cm; mi.material_override = _rocket_mat
			m_nd = mi
		m_nd.position = warm_pos
		m_nd.scale = Vector3(0.001, 0.001, 0.001)
		m_nd.visible = true # Visible at tiny scale for 3 countdown frames so GLES3 compiles shader BEFORE GO!
		add_child(m_nd)
		_pool_missiles.append(m_nd)

		var b_nd := _inst_glb("res://assets/models/prop_weapon_bomb.glb")
		if b_nd == null:
			var mi := MeshInstance3D.new()
			var sm := SphereMesh.new()
			sm.radius = 0.65; sm.height = 1.3
			mi.mesh = sm; mi.material_override = _bomb_mat
			b_nd = mi
		b_nd.position = warm_pos
		b_nd.scale = Vector3(0.001, 0.001, 0.001)
		b_nd.visible = true
		add_child(b_nd)
		_pool_bombs.append(b_nd)

	for _i in range(6):
		var t_nd := _inst_glb("res://assets/models/prop_crate_tnt.glb")
		if t_nd == null:
			var mi := MeshInstance3D.new()
			mi.mesh = _crate_mesh; mi.material_override = _tnt_mat
			t_nd = mi
		t_nd.position = warm_pos
		t_nd.scale = Vector3(0.001, 0.001, 0.001)
		t_nd.visible = true
		add_child(t_nd)
		_pool_tnts.append(t_nd)

func _borrow_pool_node(pool: Array[Node3D]) -> Node3D:
	for nd in pool:
		if not nd.visible:
			nd.visible = true
			return nd
	if pool.size() > 0:
		pool[0].visible = true
		return pool[0]
	return null

func _return_pool_node(nd: Node3D) -> void:
	if nd and is_instance_valid(nd):
		nd.visible = false
		nd.position = Vector3(0.0, -500.0, 0.0)

func _trigger_3d_explosion(pos: Vector3, juiced: bool = false) -> void:
	for ex in _explosions:
		if float(ex["life"]) <= 0.0:
			ex["life"] = float(ex["max_life"])
			ex["juiced"] = juiced
			var root: Node3D = ex["root"]
			root.position = pos + Vector3(0.0, 0.8, 0.0)
			root.visible = true
			var bcol := Color(0.18, 0.92, 1.0, 0.95) if juiced else Color(1.0, 0.48, 0.06, 0.95)
			(ex["bmat"] as StandardMaterial3D).albedo_color = bcol
			(ex["rmat"] as StandardMaterial3D).albedo_color = Color(1.0, 0.92, 0.28, 0.95)
			break

func _trigger_crate_splinters(pos: Vector3) -> void:
	var spawned := 0
	for sp in _splinters:
		if float(sp["life"]) <= 0.0:
			sp["life"] = 0.52
			var nd: MeshInstance3D = sp["node"]
			nd.position = pos + Vector3(randf_range(-0.4, 0.4), randf_range(-0.2, 0.4), randf_range(-0.4, 0.4))
			nd.scale = Vector3.ONE
			nd.visible = true
			var ang := float(spawned) / 6.0 * TAU + randf_range(-0.3, 0.3)
			sp["vel"] = Vector3(cos(ang) * randf_range(5.5, 9.5), randf_range(6.5, 11.5), sin(ang) * randf_range(5.5, 9.5))
			sp["rot_vel"] = Vector3(randf_range(-14.0, 14.0), randf_range(-14.0, 14.0), randf_range(-14.0, 14.0))
			spawned += 1
			if spawned >= 6:
				break

func fire_item(kart: KartPhysics, rank_map: Dictionary) -> void:
	if kart.held_item == "" or kart.item_roulette_timer > 0.0:
		return
	var item_id := kart.held_item
	var juiced := kart.is_juiced()
	kart.held_item = ""
	kart.item_changed.emit("")
	if kart.visuals:
		kart.visuals.trigger_weapon_launch(item_id)

	match item_id:
		"turbo":
			var tier := KartPhysics.FireTier.SACRED if juiced else KartPhysics.FireTier.ORANGE
			kart.add_boost(tier, 3.0 if juiced else 2.0, 14.0 if juiced else 10.0, true)
			if kart.is_player and AudioSynth:
				AudioSynth.play_sfx("sacred_fire" if juiced else "boost_3")
		"shield":
			kart.shield_active = true
			kart.shield_juiced = juiced
			kart.shield_timer = 999.0 if juiced else 9.0
			if kart.is_player and AudioSynth:
				AudioSynth.play_sfx("shield")
		"mask":
			kart.mask_timer = 7.8 if juiced else 6.0
			kart.add_boost(KartPhysics.FireTier.SACRED, 2.5, 11.0, false)
			if kart.is_player and AudioSynth:
				AudioSynth.play_sfx("mask")
		"tnt":
			_spawn_tnt_hazard(kart)
			if kart.is_player and AudioSynth:
				AudioSynth.play_sfx("crate", 0.85)
		"bomb":
			_spawn_projectile(kart, "bomb", juiced)
			if kart.is_player and AudioSynth:
				AudioSynth.play_sfx("missile", 0.82)
		"missile":
			_spawn_projectile(kart, "missile", juiced, rank_map)
			if kart.is_player and AudioSynth:
				AudioSynth.play_sfx("missile", 1.15)

func _spawn_tnt_hazard(owner_kart: KartPhysics) -> void:
	var fwd := Vector3(-sin(owner_kart.heading_yaw), 0.0, -cos(owner_kart.heading_yaw))
	var pos := owner_kart.global_position - fwd * 3.0 + Vector3(0.0, 0.85, 0.0)
	var node := _borrow_pool_node(_pool_tnts)
	if node == null:
		return
	node.scale = Vector3(0.90, 0.90, 0.90)
	node.position = pos
	# Drop-in bounce animation (`drop_t`)!
	_hazards.append({"node": node, "pos": pos, "owner": owner_kart, "grace": 0.65, "life": 22.0, "drop_t": 0.28})

func _spawn_projectile(owner_kart: KartPhysics, kind: String, juiced: bool, _rank_map: Dictionary = {}) -> void:
	var fwd := Vector3(-sin(owner_kart.heading_yaw), 0.0, -cos(owner_kart.heading_yaw))
	var start_pos := owner_kart.global_position + fwd * 3.2 + Vector3(0.0, 1.0, 0.0)
	var node := _borrow_pool_node(_pool_missiles if kind == "missile" else _pool_bombs)
	if node == null:
		return
	var sc := (1.35 if juiced else 1.15)
	node.scale = Vector3(sc, sc, sc)
	node.position = start_pos

	var target: KartPhysics = null
	if kind == "missile":
		var best_delta := 999.0
		for k in _karts:
			if k == owner_kart or not is_instance_valid(k):
				continue
			var prog_diff := k.total_progress - owner_kart.total_progress
			if prog_diff > 0.005 and prog_diff < best_delta:
				best_delta = prog_diff
				target = k

	_projectiles.append({
		"node": node,
		"kind": kind,
		"owner": owner_kart,
		"target": target,
		"pos": start_pos,
		"dir": fwd,
		"speed": (84.0 if juiced else 72.0) if kind == "missile" else (68.0 if juiced else 58.0),
		"radius": 2.6 if juiced else 2.0,
		"juiced": juiced,
		"spline_t": owner_kart.spline_t,
		"life": 5.5
	})

func _physics_process(delta: float) -> void:
	_time += delta
	if _prewarm_frames > 0:
		_prewarm_frames -= 1
		if _prewarm_frames == 0:
			for nd in _pool_missiles: _return_pool_node(nd)
			for nd in _pool_bombs: _return_pool_node(nd)
			for nd in _pool_tnts: _return_pool_node(nd)
	_update_crates(delta)
	_update_fruits(delta)
	_update_hazards(delta)
	_update_projectiles(delta)
	_update_fx_pools(delta)
	_update_mask_ramming()

func _update_fx_pools(delta: float) -> void:
	for ex in _explosions:
		var life := float(ex["life"])
		if life > 0.0:
			life -= delta
			ex["life"] = life
			var root: Node3D = ex["root"]
			if life <= 0.0:
				root.visible = false
			else:
				var u := 1.0 - (life / float(ex["max_life"]))
				var max_sc := 5.6 if bool(ex["juiced"]) else 4.2
				var b_sc := lerpf(0.6, max_sc, pow(u, 0.55))
				var r_sc := lerpf(0.8, max_sc * 1.45, u)
				(ex["ball"] as MeshInstance3D).scale = Vector3.ONE * b_sc
				(ex["ring"] as MeshInstance3D).scale = Vector3(r_sc, 1.0, r_sc)
				(ex["bmat"] as StandardMaterial3D).albedo_color.a = (1.0 - u) * 0.88
				(ex["rmat"] as StandardMaterial3D).albedo_color.a = (1.0 - u) * 0.92

	for sp in _splinters:
		var life := float(sp["life"])
		if life > 0.0:
			life -= delta
			sp["life"] = life
			var nd: MeshInstance3D = sp["node"]
			if life <= 0.0:
				nd.visible = false
			else:
				var v: Vector3 = sp["vel"]
				v.y -= 34.0 * delta
				sp["vel"] = v
				nd.position += v * delta
				nd.rotation += (sp["rot_vel"] as Vector3) * delta
				nd.scale = Vector3.ONE * clampf(life / 0.52, 0.2, 1.0)

func _update_crates(delta: float) -> void:
	for c in _crates:
		var mi: Node3D = c["node"]
		if not c["active"]:
			c["respawn"] = float(c["respawn"]) - delta
			if float(c["respawn"]) <= 0.0:
				c["active"] = true
				mi.visible = true
			continue
		var bp: Vector3 = c["base_pos"]
		mi.position = bp + Vector3(0.0, sin(_time * 3.0 + float(c["phase"])) * 0.25, 0.0)
		mi.rotation.y += delta * 1.9
		for k in _karts:
			if not is_instance_valid(k): continue
			if k.global_position.distance_squared_to(bp) < 2.4 * 2.4:
				c["active"] = false
				c["respawn"] = 4.2
				mi.visible = false
				_trigger_crate_splinters(bp)
				if k.is_player and AudioSynth:
					AudioSynth.play_sfx("crate", randf_range(0.92, 1.08))
				var rank := 1
				for other in _karts:
					if is_instance_valid(other) and other.total_progress > k.total_progress:
						rank += 1
				k.grant_random_item(rank)
				break

func _update_fruits(delta: float) -> void:
	for f in _fruits:
		var node: Node3D = f["node"]
		if not f["active"]:
			f["respawn"] = float(f["respawn"]) - delta
			if float(f["respawn"]) <= 0.0:
				f["active"] = true
				node.visible = true
			continue
		var bp: Vector3 = f["base_pos"]
		node.position = bp + Vector3(0.0, sin(_time * 4.2 + float(f["phase"])) * 0.28, 0.0)
		node.rotation.y += delta * 2.8
		for k in _karts:
			if not is_instance_valid(k): continue
			if k.global_position.distance_squared_to(bp) < 2.5 * 2.5:
				f["active"] = false
				f["respawn"] = 8.0
				node.visible = false
				k.add_fruit(2 if bool(f.get("is_crystal", false)) else 1)
				break

func _update_hazards(delta: float) -> void:
	for i in range(_hazards.size() - 1, -1, -1):
		var h := _hazards[i]
		h["life"] = float(h["life"]) - delta
		h["grace"] = maxf(0.0, float(h["grace"]) - delta)
		if float(h["life"]) <= 0.0:
			_return_pool_node(h["node"])
			_hazards.remove_at(i)
			continue
		var pos: Vector3 = h["pos"]
		var drop_t := float(h.get("drop_t", 0.0))
		if drop_t > 0.0:
			drop_t = maxf(0.0, drop_t - delta)
			h["drop_t"] = drop_t
			var nd: Node3D = h["node"]
			nd.position.y = pos.y + sin((1.0 - drop_t / 0.28) * PI) * 1.15
		var hit_done := false
		for k in _karts:
			if not is_instance_valid(k): continue
			if k == h["owner"] and float(h["grace"]) > 0.0: continue
			if k.global_position.distance_squared_to(pos) < 2.2 * 2.2:
				k.apply_hit("tnt", true)
				_trigger_crate_splinters(pos)
				hit_done = true
				break
		if hit_done:
			_return_pool_node(h["node"])
			_hazards.remove_at(i)

func _update_projectiles(delta: float) -> void:
	for i in range(_projectiles.size() - 1, -1, -1):
		var p := _projectiles[i]
		p["life"] = float(p["life"]) - delta
		if float(p["life"]) <= 0.0:
			_trigger_3d_explosion(p["pos"], bool(p.get("juiced", false)))
			_return_pool_node(p["node"])
			_projectiles.remove_at(i)
			continue

		var pos: Vector3 = p["pos"]
		var dir: Vector3 = p["dir"]
		var spd: float = float(p["speed"])

		if p["kind"] == "missile":
			var target: KartPhysics = p["target"]
			if target and is_instance_valid(target) and pos.distance_to(target.global_position) < 46.0:
				var to_t := (target.global_position + Vector3(0.0, 0.9, 0.0) - pos).normalized()
				dir = dir.lerp(to_t, minf(1.0, delta * 9.5)).normalized()
			elif _spline != null:
				var proj := _spline.project_point(pos, float(p["spline_t"]))
				p["spline_t"] = proj["t"]
				var ahead := _spline.sample_at_t(float(proj["t"]) + 0.025)
				var to_a: Vector3 = (ahead["pos"] + Vector3(0.0, 1.0, 0.0) - pos).normalized()
				dir = dir.lerp(to_a, minf(1.0, delta * 7.8)).normalized()
		elif _spline != null:
			var proj := _spline.project_point(pos, float(p["spline_t"]))
			p["spline_t"] = proj["t"]
			pos.y = lerpf(pos.y, float(proj["pos"].y) + 0.72 + absf(sin(_time * 18.0)) * 0.22, minf(1.0, delta * 14.0))

		pos += dir * spd * delta
		p["pos"] = pos
		p["dir"] = dir
		var node: Node3D = p["node"]
		node.position = pos
		if p["kind"] == "missile":
			node.look_at(pos + dir, Vector3.UP)
			node.rotate_object_local(Vector3.FORWARD, delta * 10.0)
		else:
			node.look_at(pos + dir, Vector3.UP)
			node.rotate_object_local(Vector3.RIGHT, -_time * 16.0)

		var hit_r: float = float(p["radius"])
		var exploded := false
		for k in _karts:
			if not is_instance_valid(k) or k == p["owner"]: continue
			if k.global_position.distance_squared_to(pos) < hit_r * hit_r:
				k.apply_hit(str(p["kind"]), false)
				exploded = true
				break
		if exploded:
			_trigger_3d_explosion(pos, bool(p.get("juiced", false)))
			_return_pool_node(p["node"])
			_projectiles.remove_at(i)

func _update_mask_ramming() -> void:
	for k in _karts:
		if not is_instance_valid(k) or k.mask_timer <= 0.0: continue
		for other in _karts:
			if not is_instance_valid(other) or other == k: continue
			if k.global_position.distance_squared_to(other.global_position) < 2.5 * 2.5:
				other.apply_hit("mask_ram", false)
