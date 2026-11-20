class_name Terrain
extends Node3D
## مدير التضاريس: تحميل القطع حول اللاعب بخيوط خلفية، الموارد، الحصاد، إعادة النمو، العشب، الماء والتضاريس البعيدة.

const CHUNK := 64.0
const L_WORLD := 1
const L_RES_BLOCK := 8
const L_RES_SOFT := 16

var gen: WorldGen
var world: Node
var chunks := {}
var pending: Array = []
var view_radius := 3
var body_radius := 2
var grass_radius := 1
var grass_mult := 0.6
var depleted := {}
var res_hp := {}
var center := Vector2i(99999, 99999)
var terrain_mat: ShaderMaterial
var far_mat: ShaderMaterial
var _task := -1
var _task_key := Vector2i.ZERO
var _result = null
var _mutex := Mutex.new()
var _regrow_timer := 0.0
var _shapes := {}
var far_mi: MeshInstance3D
var water: MeshInstance3D
var lava: MeshInstance3D
var lava_y := -100.0
var _far_task := -1
var _far_arrays = null
var _grass_mesh: Mesh

func setup(g: WorldGen, w: Node, quality: int) -> void:
	gen = g
	world = w
	view_radius = [2, 3, 4][quality]
	grass_mult = [0.25, 0.55, 1.0][quality]
	grass_radius = 1
	body_radius = 2
	terrain_mat = MeshFactory.mat("terrain")
	_grass_mesh = MeshFactory.get_mesh("grass_clump")
	# الماء
	water = MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(1600, 1600)
	pm.subdivide_width = 48
	pm.subdivide_depth = 48
	water.mesh = pm
	water.material_override = MeshFactory.mat("water")
	water.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(water)
	# الحمم في فوهة البركان
	lava = MeshInstance3D.new()
	var lm := PlaneMesh.new()
	lm.size = Vector2(80, 80)
	lava.mesh = lm
	lava.material_override = MeshFactory.mat("lava")
	lava_y = gen.height_at(gen.volcano.x, gen.volcano.y) + 4.0
	lava.position = Vector3(gen.volcano.x, lava_y, gen.volcano.y)
	lava.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(lava)
	var ll := OmniLight3D.new()
	ll.light_color = Color(1.0, 0.45, 0.15)
	ll.omni_range = 60.0
	ll.light_energy = 3.0
	ll.position = lava.position + Vector3(0, 6, 0)
	add_child(ll)
	# تضاريس بعيدة
	far_mi = MeshInstance3D.new()
	far_mat = terrain_mat.duplicate()
	far_mi.material_override = far_mat
	far_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(far_mi)
	_far_task = WorkerThreadPool.add_task(_far_build, false, "far_terrain")

func _far_build() -> void:
	var arr := gen.build_far_mesh_arrays(96)
	_mutex.lock()
	_far_arrays = arr
	_mutex.unlock()

func is_busy() -> bool:
	return _task != -1 or not pending.is_empty()

func chunk_of(p: Vector3) -> Vector2i:
	return Vector2i(int(floor(p.x / CHUNK)), int(floor(p.z / CHUNK)))

## توليد متزامن للقطع القريبة (عند التحميل)
func generate_now(p: Vector3, radius: int) -> void:
	var c := chunk_of(p)
	for dz in range(-radius, radius + 1):
		for dx in range(-radius, radius + 1):
			var k := c + Vector2i(dx, dz)
			if not chunks.has(k):
				_apply_chunk(gen.build_chunk(k.x, k.y, grass_mult, true))
	center = Vector2i(99999, 99999)
	update_view(p)

func update_view(p: Vector3) -> void:
	var c := chunk_of(p)
	if c != center:
		center = c
		_refresh()
	if _task == -1 and not pending.is_empty():
		pending.sort_custom(func(a, b): return (a - center).length_squared() < (b - center).length_squared())
		_task_key = pending.pop_front()
		_task = WorkerThreadPool.add_task(_thread_build.bind(_task_key, grass_mult), false, "chunk")
	elif _task != -1 and WorkerThreadPool.is_task_completed(_task):
		WorkerThreadPool.wait_for_task_completion(_task)
		_task = -1
		_mutex.lock()
		var d = _result
		_result = null
		_mutex.unlock()
		if d != null and _wanted(Vector2i(d["cx"], d["cz"])) and not chunks.has(Vector2i(d["cx"], d["cz"])):
			_apply_chunk(d)
			_update_lod(Vector2i(d["cx"], d["cz"]))
	if _far_task != -1 and WorkerThreadPool.is_task_completed(_far_task):
		WorkerThreadPool.wait_for_task_completion(_far_task)
		_far_task = -1
		var am := ArrayMesh.new()
		am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, _far_arrays)
		far_mi.mesh = am
		_far_arrays = null
	# الماء يتبع اللاعب
	water.global_position = Vector3(snappedf(p.x, 32.0), 0.0, snappedf(p.z, 32.0))
	far_mat.set_shader_parameter("hole_center", Vector2(p.x, p.z))
	far_mat.set_shader_parameter("hole_radius", (view_radius - 0.25) * CHUNK)
	far_mat.set_shader_parameter("wetness", terrain_mat.get_shader_parameter("wetness"))
	far_mat.set_shader_parameter("snow", terrain_mat.get_shader_parameter("snow"))

func _wanted(k: Vector2i) -> bool:
	return absi(k.x - center.x) <= view_radius and absi(k.y - center.y) <= view_radius

func _thread_build(k: Vector2i, gm: float) -> void:
	var d := gen.build_chunk(k.x, k.y, gm, true)
	_mutex.lock()
	_result = d
	_mutex.unlock()

func _refresh() -> void:
	for k in chunks.keys():
		if absi(k.x - center.x) > view_radius + 1 or absi(k.y - center.y) > view_radius + 1:
			chunks[k]["node"].queue_free()
			chunks.erase(k)
	var np := []
	for k in pending:
		if _wanted(k):
			np.append(k)
	pending = np
	for dz in range(-view_radius, view_radius + 1):
		for dx in range(-view_radius, view_radius + 1):
			var k := center + Vector2i(dx, dz)
			if absi(k.x) * CHUNK > WorldGen.HALF + 300.0 or absi(k.y) * CHUNK > WorldGen.HALF + 300.0:
				continue
			if not chunks.has(k) and not k in pending and not (_task != -1 and _task_key == k):
				pending.append(k)
	for k in chunks:
		_update_lod(k)

func _update_lod(k: Vector2i) -> void:
	var ch: Dictionary = chunks[k]
	var ring := maxi(absi(k.x - center.x), absi(k.y - center.y))
	if ring <= body_radius and ch["bodies"] == null:
		_build_bodies(k)
	elif ring > body_radius + 1 and ch["bodies"] != null:
		ch["bodies"].queue_free()
		ch["bodies"] = null
		ch["body_of"] = {}
	if ring <= grass_radius and ch["grass"] == null:
		_build_grass(k)
	elif ring > grass_radius + 1 and ch["grass"] != null:
		ch["grass"].queue_free()
		ch["grass"] = null

func _apply_chunk(d: Dictionary) -> void:
	var k := Vector2i(d["cx"], d["cz"])
	var node := Node3D.new()
	node.name = "C_%d_%d" % [k.x, k.y]
	node.position = Vector3(k.x * CHUNK, 0, k.y * CHUNK)
	add_child(node)
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = d["verts"]
	arr[Mesh.ARRAY_NORMAL] = d["norms"]
	arr[Mesh.ARRAY_COLOR] = d["cols"]
	arr[Mesh.ARRAY_INDEX] = d["idx"]
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	mesh.surface_set_material(0, terrain_mat)
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	node.add_child(mi)
	var body := StaticBody3D.new()
	body.collision_layer = L_WORLD
	body.collision_mask = 0
	body.set_meta("terrain", true)
	var shape := ConcavePolygonShape3D.new()
	shape.backface_collision = true
	shape.set_faces(d["faces"])
	var cs := CollisionShape3D.new()
	cs.shape = shape
	body.add_child(cs)
	node.add_child(body)
	var by_type := {}
	var slot_of := {}
	var scatter: Array = d["scatter"]
	for si in range(scatter.size()):
		var tp: String = scatter[si][0]
		if not by_type.has(tp):
			by_type[tp] = []
		slot_of[si] = [tp, by_type[tp].size()]
		by_type[tp].append(si)
	var types := {}
	for tp in by_type:
		var td := ResDB.get_type(tp)
		var list: Array = by_type[tp]
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = MeshFactory.get_mesh(td["mesh"])
		mm.instance_count = list.size()
		for j in range(list.size()):
			var si: int = list[j]
			mm.set_instance_transform(j, _xf(scatter[si], _is_depleted(k, scatter[si][4])))
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		var big: bool = td["block"]
		mmi.visibility_range_end = 400.0 if td["fall"] else (220.0 if big else 70.0)
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if big else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		node.add_child(mmi)
		types[tp] = {"mm": mm, "list": list}
	chunks[k] = {"node": node, "scatter": scatter, "types": types, "slot_of": slot_of, "bodies": null, "body_of": {}, "grass": null, "grass_data": d["grass"]}

func _xf(e: Array, hidden: bool) -> Transform3D:
	var b := Basis(Vector3.UP, e[2]).scaled(Vector3.ONE * (0.001 if hidden else e[3]))
	return Transform3D(b, e[1] - (Vector3(0, 50, 0) if hidden else Vector3.ZERO))

func rid_of(k: Vector2i, kk: int) -> String:
	return "%d_%d_%d" % [k.x, k.y, kk]

func _is_depleted(k: Vector2i, kk: int) -> bool:
	return depleted.has(rid_of(k, kk))

func _shape_for(tp: String) -> Array:
	if _shapes.has(tp):
		return _shapes[tp]
	var td := ResDB.get_type(tp)
	var sh: Shape3D
	var off := Vector3.ZERO
	if td["fall"] or tp == "cactus" or tp == "beehive":
		var cy := CylinderShape3D.new()
		cy.radius = td["col_r"]
		cy.height = td["col_h"]
		sh = cy
		off = Vector3(0, td["col_h"] * 0.5, 0)
	else:
		var sp := SphereShape3D.new()
		sp.radius = td["col_r"]
		sh = sp
		off = Vector3(0, td["col_h"] * 0.35, 0)
	_shapes[tp] = [sh, off]
	return _shapes[tp]

func _build_bodies(k: Vector2i) -> void:
	var ch: Dictionary = chunks[k]
	var holder := Node3D.new()
	ch["node"].add_child(holder)
	ch["bodies"] = holder
	ch["body_of"] = {}
	var scatter: Array = ch["scatter"]
	for si in range(scatter.size()):
		if not _is_depleted(k, scatter[si][4]):
			_make_body(k, si)

func _make_body(k: Vector2i, si: int) -> void:
	var ch: Dictionary = chunks[k]
	if ch["bodies"] == null:
		return
	var e: Array = ch["scatter"][si]
	var td := ResDB.get_type(e[0])
	var b := ResourceBody.new()
	b.terrain = self
	b.chunk_key = k
	b.sidx = si
	b.rtype = e[0]
	b.collision_layer = L_RES_BLOCK if td["block"] else L_RES_SOFT
	b.collision_mask = 0
	var sh: Array = _shape_for(e[0])
	var cs := CollisionShape3D.new()
	cs.shape = sh[0]
	cs.position = sh[1] * (e[3] if td["fall"] else 1.0)
	b.add_child(cs)
	b.position = e[1]
	ch["bodies"].add_child(b)
	ch["body_of"][si] = b

func _build_grass(k: Vector2i) -> void:
	var ch: Dictionary = chunks[k]
	var gdata: Array = ch["grass_data"]
	if gdata.is_empty():
		ch["grass"] = Node3D.new()
		ch["node"].add_child(ch["grass"])
		return
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = _grass_mesh
	mm.instance_count = gdata.size()
	for i in range(gdata.size()):
		var g: Array = gdata[i]
		var bs := Basis(Vector3.UP, g[1]).scaled(Vector3(g[2], g[2] * randf_range(0.8, 1.25), g[2]))
		mm.set_instance_transform(i, Transform3D(bs, g[0]))
		var gc: Color = g[3]
		mm.set_instance_color(i, Color(minf(gc.r * 1.15, 1.0), minf(gc.g * 1.2, 1.0), minf(gc.b * 1.05, 1.0)))
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mmi.visibility_range_end = 60.0
	ch["node"].add_child(mmi)
	ch["grass"] = mmi

func world_pos(k: Vector2i, si: int) -> Vector3:
	return Vector3(k.x * CHUNK, 0, k.y * CHUNK) + chunks[k]["scatter"][si][1]

func _set_hidden(k: Vector2i, si: int, hidden: bool) -> void:
	var ch: Dictionary = chunks[k]
	var slot: Array = ch["slot_of"][si]
	var t: Dictionary = ch["types"][slot[0]]
	t["mm"].set_instance_transform(slot[1], _xf(ch["scatter"][si], hidden))
	if hidden:
		if ch["body_of"].has(si):
			ch["body_of"][si].queue_free()
			ch["body_of"].erase(si)
	else:
		if not ch["body_of"].has(si):
			_make_body(k, si)

func get_progress(k: Vector2i, si: int) -> float:
	if not chunks.has(k):
		return 0.0
	var e: Array = chunks[k]["scatter"][si]
	var rid := rid_of(k, e[4])
	if not res_hp.has(rid):
		return 0.0
	var td := ResDB.get_type(e[0])
	return 1.0 - res_hp[rid] / (td["hp"] * e[3])

## يستنفد المورد ويعيد قائمة الغلة [[id, n], ...]
func deplete(k: Vector2i, si: int, yield_mult := 1.0, fall := true) -> Array:
	var ch: Dictionary = chunks[k]
	var e: Array = ch["scatter"][si]
	var rid := rid_of(k, e[4])
	if depleted.has(rid):
		return []
	var td := ResDB.get_type(e[0])
	depleted[rid] = world.total_hours() + td["regrow"] * randf_range(0.8, 1.25)
	res_hp.erase(rid)
	var out := []
	for y in td["yields"]:
		if randf() <= y[3]:
			var n := int(round(randi_range(y[1], y[2]) * yield_mult * (e[3] if td["fall"] else 1.0)))
			if n > 0:
				out.append([y[0], n])
	if td["fall"] and fall:
		_tree_fall(e, world_pos(k, si), td["mesh"])
	_set_hidden(k, si, true)
	return out

func _tree_fall(e: Array, pos: Vector3, mesh_key: String) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = MeshFactory.get_mesh(mesh_key)
	add_child(mi)
	mi.global_position = pos
	mi.rotation.y = e[2]
	mi.scale = Vector3.ONE * e[3]
	var pivot_axis := Vector3(randf_range(-1, 1), 0, randf_range(-1, 1)).normalized()
	var tw := create_tween()
	var b0 := mi.basis
	tw.tween_method(func(t: float): mi.basis = Basis(pivot_axis, t * t * 1.45) * b0, 0.0, 1.0, 1.6)
	tw.tween_interval(0.6)
	tw.tween_property(mi, "position:y", pos.y - 3.0, 1.5)
	tw.tween_callback(mi.queue_free)
	Sfx.play("fall", pos, 2.0)

func player_interact(b: ResourceBody, player) -> void:
	var td := ResDB.get_type(b.rtype)
	if td["tool"] != "":
		player.try_attack()
		return
	var pos := b.global_position
	if td["hurt"] > 0.0:
		if b.rtype == "beehive" and player.held_tool_kind() == "torch":
			Game.notify("الدخان أبعد النحل عنك", Color(0.8, 1, 0.8))
		else:
			player.stats.damage(td["hurt"], "النحل" if b.rtype == "beehive" else "الأشواك")
			if b.rtype == "beehive":
				Game.notify("لسعك النحل! استخدم شعلة لإبعاده", Color(1, 0.6, 0.3))
	var mult: float = player.stats.skill_yield_mult("gathering")
	var yields := deplete(b.chunk_key, b.sidx, mult)
	player.receive_items(yields, pos)
	player.stats.add_skill_xp("gathering", 2.0)
	Sfx.play("pickup", pos)

func player_hit(b: ResourceBody, dmg: float, kind: String, tier: int, attacker, hit_pos: Vector3) -> void:
	var td := ResDB.get_type(b.rtype)
	var k := b.chunk_key
	var si := b.sidx
	if not chunks.has(k):
		return
	var e: Array = chunks[k]["scatter"][si]
	if td["tool"] == "":
		player_interact(b, attacker)
		return
	if kind != td["tool"]:
		Game.notify("تحتاج %s لهذا" % ItemDB.tool_kind_name(td["tool"]), Color(1, 0.8, 0.5))
		Sfx.play("hit", hit_pos)
		return
	if tier < td["tier"]:
		Game.notify("أداتك ضعيفة جداً. تحتاج أداة من مستوى %d" % td["tier"], Color(1, 0.7, 0.4))
		Sfx.play("mine" if kind == "pickaxe" else "hit", hit_pos, -4.0)
		return
	var rid := rid_of(k, e[4])
	var max_hp: float = td["hp"] * e[3]
	var hp: float = res_hp.get(rid, max_hp)
	var skill: String = td["skill"]
	hp -= dmg * attacker.stats.skill_power_mult(skill)
	Sfx.play(td["sfx"], hit_pos)
	world.fx_burst(hit_pos, Color(0.55, 0.4, 0.25) if kind == "axe" else Color(0.6, 0.6, 0.6))
	attacker.stats.add_skill_xp(skill, 1.0)
	attacker.stats.add_fitness_xp(0.6)
	if hp > 0.0:
		res_hp[rid] = hp
		return
	var yields := deplete(k, si, attacker.stats.skill_yield_mult(skill))
	attacker.receive_items(yields, hit_pos)
	attacker.stats.add_skill_xp(skill, 4.0)

## للشخصيات: البحث عن أقرب مورد من أنواع معينة
func find_resource(pos: Vector3, kinds: Array, radius: float) -> Array:
	var best := []
	var bd := radius * radius
	var ck := chunk_of(pos)
	var cr := int(ceil(radius / CHUNK))
	for dz in range(-cr, cr + 1):
		for dx in range(-cr, cr + 1):
			var k := ck + Vector2i(dx, dz)
			if not chunks.has(k):
				continue
			var sc: Array = chunks[k]["scatter"]
			var base := Vector3(k.x * CHUNK, 0, k.y * CHUNK)
			for si in range(sc.size()):
				if not sc[si][0] in kinds:
					continue
				if _is_depleted(k, sc[si][4]):
					continue
				var wp: Vector3 = base + sc[si][1]
				var d2 := wp.distance_squared_to(pos)
				if d2 < bd:
					bd = d2
					best = [k, si, wp]
	return best

func is_available(k: Vector2i, si: int) -> bool:
	return chunks.has(k) and not _is_depleted(k, chunks[k]["scatter"][si][4])

func tick(dt: float, ppos: Vector3) -> void:
	update_view(ppos)
	_regrow_timer += dt
	if _regrow_timer > 8.0:
		_regrow_timer = 0.0
		var now: float = world.total_hours()
		var done := []
		for rid in depleted:
			if depleted[rid] <= now:
				done.append(rid)
		for rid in done:
			depleted.erase(rid)
			var parts: PackedStringArray = rid.split("_")
			var k := Vector2i(int(parts[0]), int(parts[1]))
			var kk := int(parts[2])
			if chunks.has(k):
				var sc: Array = chunks[k]["scatter"]
				for si in range(sc.size()):
					if sc[si][4] == kk:
						_set_hidden(k, si, false)
						break

func to_data() -> Dictionary:
	return {"depleted": depleted.duplicate()}

func from_data(d: Dictionary) -> void:
	depleted = {}
	var dep: Dictionary = d.get("depleted", {})
	for k in dep:
		depleted[str(k)] = float(dep[k])
