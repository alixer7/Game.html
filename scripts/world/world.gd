class_name World
extends Node3D
## العالم: يربط كل الأنظمة (التضاريس، السماء، الذكاء الاصطناعي، البناء، اللاعب، الواجهة) والحفظ والتحميل.

var seed_value := 0
var gen: WorldGen
var terrain: Terrain
var sky: SkyWeather
var ai: AIManager
var build: BuildManager
var player: Player
var hud: Node
var spawn_point := Vector3.ZERO
var time_scale := 1.0
var quality := 1
var map_texture: ImageTexture = null
var explored: Image
var explored_tex: ImageTexture
var _explored_dirty := false
var _map_task := -1
var _map_img: Image = null
var _fx_pool: Array = []
var _fx_i := 0
var _autosave_t := 180.0
var _claim_t := 0.0
var _claim_seen := {}
var _amb_t := 0.0
var _loot_root: Node3D
var started := false
var playtime := 0.0

const EXPLORE_RES := 128

func total_hours() -> float:
	return sky.total_hours() if sky else 0.0

## درجة حرارة الهواء بالمئوية في موقع معين (تشمل الوقت والطقس والارتفاع)
func temperature_at(p: Vector3) -> float:
	var bt := gen.base_temperature(p.x, p.z)
	var h := sky.hour_of_day()
	var tod := -cos((h - 3.0) / 24.0 * TAU)
	var t := bt.x + bt.y * tod
	t -= sky.cloud * 2.0 + sky.rain * 4.0 + sky.storm * 2.0
	if sky.snowing:
		t -= 2.0
	if p.y < -0.5:
		t = minf(t, 16.0 + bt.x * 0.2)
	return t

func start(new_game: bool, s: int, save: Dictionary, progress: Callable) -> void:
	seed_value = s
	quality = int(Game.settings.get("quality", 1))
	Game.world = self
	progress.call(0.05, "توليد العالم...")
	await get_tree().process_frame
	gen = WorldGen.new(seed_value)
	MeshFactory.init_textures()
	sky = SkyWeather.new()
	add_child(sky)
	sky.setup(self, quality)
	ai = AIManager.new()
	add_child(ai)
	ai.setup(self, quality)
	progress.call(0.15, "إنشاء المستوطنات والشخصيات...")
	await get_tree().process_frame
	if new_game:
		spawn_point = gen.find_spawn()
		ai.generate()
	else:
		ai.from_data(save.get("ai", {}))
		spawn_point = Game.v3(save.get("spawn", [0, 0, 0]))
		seed_value = int(save.get("seed", s))
	terrain = Terrain.new()
	add_child(terrain)
	terrain.setup(gen, self, quality)
	build = BuildManager.new()
	add_child(build)
	build.setup(self)
	_loot_root = Node3D.new()
	add_child(_loot_root)
	progress.call(0.25, "تحضير المجسمات...")
	await get_tree().process_frame
	var keys := ResDB.types.keys()
	for i in range(keys.size()):
		MeshFactory.get_mesh(ResDB.types[keys[i]]["mesh"])
		if i % 6 == 0:
			progress.call(0.25 + 0.25 * float(i) / keys.size(), "تحضير المجسمات...")
			await get_tree().process_frame
	MeshFactory.get_mesh("grass_clump")
	progress.call(0.5, "بناء المستوطنات...")
	await get_tree().process_frame
	for st in ai.settlements:
		build.spawn_settlement(st)
	if not new_game:
		build.load_settlement_chests(save.get("build", {}))
	player = Player.new()
	add_child(player)
	player.setup(self, spawn_point + Vector3(0, 1.0, 0))
	if new_game:
		player.give_starting_items()
		sky.set_weather("clear")
	else:
		sky.from_data(save.get("sky", {}))
		terrain.from_data(save.get("terrain", {}))
		build.from_data(save.get("build", {}))
		player.from_data(save.get("player", {}))
		for lb in save.get("loot", []):
			var items := []
			for it in lb.get("inv", []):
				if it is Dictionary:
					items.append(it)
			var bag := spawn_loot(Game.v3(lb["pos"]), items, str(lb.get("title", "أغراض")))
			if bag:
				bag.age = float(lb.get("age", 0.0))
		playtime = float(save.get("playtime", 0.0))
	Game.player = player
	explored = Image.create(EXPLORE_RES, EXPLORE_RES, false, Image.FORMAT_LA8)
	explored.fill(Color(0, 0, 0, 1))
	if save.has("explored"):
		var raw: PackedByteArray = Marshalls.base64_to_raw(save["explored"])
		if raw.size() == EXPLORE_RES * EXPLORE_RES * 2:
			explored = Image.create_from_data(EXPLORE_RES, EXPLORE_RES, false, Image.FORMAT_LA8, raw)
	explored_tex = ImageTexture.create_from_image(explored)
	progress.call(0.6, "تشكيل التضاريس...")
	await get_tree().process_frame
	terrain.generate_now(player.global_position, 1)
	if new_game:
		var py := gen.height_at(player.global_position.x, player.global_position.z)
		player.global_position.y = py + 0.3
	progress.call(0.85, "إعداد الواجهة...")
	await get_tree().process_frame
	for i in range(4):
		var f := GPUParticles3D.new()
		f.one_shot = true
		f.emitting = false
		f.amount = 14
		f.lifetime = 0.7
		f.explosiveness = 0.95
		var pm := ParticleProcessMaterial.new()
		pm.direction = Vector3(0, 1, 0)
		pm.spread = 70.0
		pm.initial_velocity_min = 1.5
		pm.initial_velocity_max = 4.0
		pm.gravity = Vector3(0, -9.0, 0)
		pm.scale_min = 0.5
		pm.scale_max = 1.2
		f.process_material = pm
		var bm := BoxMesh.new()
		bm.size = Vector3(0.06, 0.06, 0.06)
		bm.material = MeshFactory.mat("hit_fx")
		f.draw_pass_1 = bm
		add_child(f)
		_fx_pool.append(f)
	var hud_script = load("res://scripts/ui/hud.gd")
	hud = hud_script.new()
	add_child(hud)
	hud.setup(self)
	Game.hud = hud
	_map_task = WorkerThreadPool.add_task(_build_map, false, "map")
	progress.call(1.0, "جاهز!")
	started = true
	if new_game:
		Game.notify("استيقظت وحيداً في أرض مجهولة... ابحث عن الماء والطعام وابنِ مأوى قبل الليل", Color(1, 0.95, 0.8))
		Game.notify("اجمع العيدان والحجارة والألياف لصنع فأس حجري", Color(0.9, 0.95, 1))
		ai.log_event("بداية رحلتك في أرض البقاء")

func _build_map() -> void:
	var img := gen.build_map_image(256)
	_map_img = img

func spawn_loot(pos: Vector3, items: Array, nm: String) -> LootBag:
	if items.is_empty():
		return null
	for c in _loot_root.get_children():
		if c is LootBag and c.global_position.distance_to(pos) < 1.5 and c.title == nm and not c.is_queued_for_deletion():
			for it in items:
				c.inventory.add_stack(it)
			return c
	var b := LootBag.new()
	_loot_root.add_child(b)
	var y := maxf(pos.y, gen.height_at(pos.x, pos.z))
	b.global_position = Vector3(pos.x, y, pos.z)
	b.setup(items, nm)
	return b

func fx_burst(pos: Vector3, col: Color) -> void:
	if _fx_pool.is_empty():
		return
	var f: GPUParticles3D = _fx_pool[_fx_i]
	_fx_i = (_fx_i + 1) % _fx_pool.size()
	f.global_position = pos
	(f.process_material as ParticleProcessMaterial).color = col
	f.restart()
	f.emitting = true

func _process(dt: float) -> void:
	if not started or player == null:
		return
	playtime += dt
	var pp := player.global_position
	var biome := gen.biome_at(pp.x, pp.z)
	sky.tick(dt, pp, player.ambient_temp, biome)
	terrain.tick(dt, pp)
	ai.tick(dt)
	build.tick(dt)
	if _map_task != -1 and WorkerThreadPool.is_task_completed(_map_task):
		WorkerThreadPool.wait_for_task_completion(_map_task)
		_map_task = -1
		if _map_img:
			map_texture = ImageTexture.create_from_image(_map_img)
			_map_img = null
	_explore(pp)
	_claim_t -= dt
	if _claim_t <= 0.0:
		_claim_t = 3.0
		_check_claims()
	_amb_t -= dt
	if _amb_t <= 0.0:
		_amb_t = 0.5
		_ambient_audio(pp, biome)
	_autosave_t -= dt
	if _autosave_t <= 0.0:
		_autosave_t = 180.0
		save_game()
		Game.notify("تم الحفظ التلقائي", Color(0.7, 0.8, 0.9))

func _explore(p: Vector3) -> void:
	var cell := WorldGen.HALF * 2.0 / EXPLORE_RES
	var cx := int((p.x + WorldGen.HALF) / cell)
	var cz := int((p.z + WorldGen.HALF) / cell)
	var r := 3
	for dz in range(-r, r + 1):
		for dx in range(-r, r + 1):
			var x := cx + dx
			var z := cz + dz
			if x < 0 or z < 0 or x >= EXPLORE_RES or z >= EXPLORE_RES:
				continue
			if dx * dx + dz * dz > r * r:
				continue
			if explored.get_pixel(x, z).a > 0.5:
				explored.set_pixel(x, z, Color(0, 0, 0, 0))
				_explored_dirty = true
	if _explored_dirty:
		_explored_dirty = false
		explored_tex.update(explored)

func _check_claims() -> void:
	var now := Time.get_ticks_msec() / 1000.0
	for n in ai.active_npcs:
		if not is_instance_valid(n) or n.dead or n.data["companion"]:
			continue
		if ai.get_rel(n.npc_id, "player") > 35.0:
			continue
		if build.in_claim(n.global_position):
			if now - float(_claim_seen.get(n.npc_id, -999.0)) > 150.0:
				_claim_seen[n.npc_id] = now
				var tag := " (لص!)" if n.data["exposed"] else ""
				Game.notify("تنبيه: %s دخل أرضك%s" % [n.data["name"], tag], Color(1, 0.75, 0.4))

func _ambient_audio(p: Vector3, biome: int) -> void:
	var night := sky.is_night()
	var sheltered := player.shelter > 0.4
	Sfx.set_loop("wind", clampf(0.15 + sky.wind * 0.18 + maxf(p.y - 30.0, 0.0) * 0.006, 0.0, 0.7) * (0.4 if sheltered else 1.0))
	Sfx.set_loop("rain", (sky.rain * 0.8 if not sky.snowing else 0.0) * (0.5 if sheltered else 1.0))
	var birds := 0.0
	if not night and sky.rain < 0.2 and biome in [WorldGen.FOREST, WorldGen.PLAINS, WorldGen.SWAMP, WorldGen.TAIGA, WorldGen.BEACH]:
		birds = 0.45
	Sfx.set_loop("birds", birds)
	var crick := 0.4 if night and sky.rain < 0.2 and player.ambient_temp > 8.0 and biome in [WorldGen.FOREST, WorldGen.PLAINS, WorldGen.SWAMP, WorldGen.DESERT] else 0.0
	Sfx.set_loop("crickets", crick)
	Sfx.set_loop("fire", clampf(player.heat * 1.4, 0.0, 0.8))

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_PAUSED or what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		if started and player and not player.stats.dead:
			save_game()

func save_game() -> bool:
	if not started:
		return false
	var loot := []
	for c in _loot_root.get_children():
		if c is LootBag and not c.is_queued_for_deletion():
			loot.append(c.to_data())
	var data := {
		"version": 1, "seed": seed_value, "spawn": Game.arr3(spawn_point), "playtime": playtime,
		"player": player.to_data(), "sky": sky.to_data(), "terrain": terrain.to_data(),
		"build": build.to_data(), "ai": ai.to_data(), "loot": loot,
		"explored": Marshalls.raw_to_base64(explored.get_data()),
	}
	return Game.write_save(data)
