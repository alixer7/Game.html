class_name Terrain
extends Node3D
## Streams terrain chunks with distance-based LOD (built on worker threads) and
## keeps height-field collision tiles around every physics vehicle.

const CHUNK := 128            # cells per chunk (256 m)
const COL_CELLS := 32         # cells per collision tile (64 m)

var wd: WorldData
var material: ShaderMaterial
var base_step := 1
var lod_dist := [380.0, 820.0, 1600.0]
var chunks := {}              # Vector2i -> {mi, step, want, task}
var _done := []
var _mutex := Mutex.new()
var _tasks := {}              # task id -> true
var collision := {}           # Vector2i -> {body, t}
var bodies: Array = []        # Node3D list that need collision
var caps_body: StaticBody3D


func setup(data: WorldData, quality: int, view: float) -> void:
	wd = data
	base_step = 1 if quality >= 2 else 2
	var vd := lerpf(0.75, 1.35, view)
	lod_dist = [380.0 * vd, 820.0 * vd, 1600.0 * vd]
	material = ShaderMaterial.new()
	material.shader = load("res://shaders/terrain.gdshader")
	material.set_shader_parameter("splat", load("res://assets/world/splat.png"))
	material.set_shader_parameter("albedo_tex", load("res://assets/textures/terrain_albedo.png"))
	material.set_shader_parameter("normal_tex", load("res://assets/textures/terrain_normal.png"))
	material.set_shader_parameter("quality", mini(quality, 2))
	var nc := (wd.n - 1) / CHUNK
	for cz in nc:
		for cx in nc:
			var key := Vector2i(cx, cz)
			var mi := MeshInstance3D.new()
			mi.material_override = material
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
			add_child(mi)
			var step := 16
			mi.mesh = _arrays_to_mesh(_build_arrays(cx, cz, step))
			chunks[key] = {"mi": mi, "step": step, "task": -1}
	_build_tunnel_caps()


func _exit_tree() -> void:
	for id in _tasks.keys():
		WorkerThreadPool.wait_for_task_completion(id)
	_tasks.clear()


func _process(_delta: float) -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var cp := cam.global_position
	var started := 0
	for key in chunks:
		var c: Dictionary = chunks[key]
		var center := Vector3((key.x + 0.5) * CHUNK * wd.cell - wd.half, 0.0, (key.y + 0.5) * CHUNK * wd.cell - wd.half)
		var d := Vector2(center.x - cp.x, center.z - cp.z).length() - CHUNK * wd.cell * 0.5
		var want := base_step
		if d > lod_dist[2]:
			want = base_step * 8
		elif d > lod_dist[1]:
			want = base_step * 4
		elif d > lod_dist[0]:
			want = base_step * 2
		want = mini(want, 16)
		if want != c.step and c.task < 0 and started < 3:
			var id := WorkerThreadPool.add_task(_task.bind(key, want))
			c.task = id
			_tasks[id] = true
			started += 1
	# apply finished builds
	_mutex.lock()
	var ready := _done.duplicate()
	_done.clear()
	_mutex.unlock()
	for r in ready:
		var c: Dictionary = chunks[r[0]]
		if _tasks.has(c.task):
			WorkerThreadPool.wait_for_task_completion(c.task)
			_tasks.erase(c.task)
		c.task = -1
		c.step = r[1]
		c.mi.mesh = _arrays_to_mesh(r[2])


func _task(key: Vector2i, step: int) -> void:
	var arr := _build_arrays(key.x, key.y, step)
	_mutex.lock()
	_done.append([key, step, arr])
	_mutex.unlock()


func _arrays_to_mesh(arr: Array) -> ArrayMesh:
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return m


func _build_arrays(cx: int, cz: int, step: int) -> Array:
	var n := wd.n
	var hs := wd.heights
	var cell := wd.cell
	var half := wd.half
	var m := CHUNK / step + 1
	var i0 := cx * CHUNK
	var j0 := cz * CHUNK
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	verts.resize(m * m + 4 * m)
	norms.resize(m * m + 4 * m)
	var e := 2.0 * step * cell
	for jj in m:
		var j := j0 + jj * step
		var z := j * cell - half
		var jm := maxi(j - step, 0) * n
		var jp := mini(j + step, n - 1) * n
		var jr := j * n
		for ii in m:
			var i := i0 + ii * step
			var h := hs[jr + i]
			var hl := hs[jr + maxi(i - step, 0)]
			var hr := hs[jr + mini(i + step, n - 1)]
			var hd := hs[jm + i]
			var hu := hs[jp + i]
			var k := jj * m + ii
			verts[k] = Vector3(i * cell - half, h, z)
			norms[k] = Vector3(hl - hr, e, hd - hu).normalized()
	var idx := PackedInt32Array()
	idx.resize((m - 1) * (m - 1) * 6 + 4 * (m - 1) * 6)
	var q := 0
	for jj in m - 1:
		for ii in m - 1:
			var a := jj * m + ii
			var b := a + 1
			var c := a + m
			var d := c + 1
			idx[q] = a; idx[q + 1] = b; idx[q + 2] = d
			idx[q + 3] = a; idx[q + 4] = d; idx[q + 5] = c
			q += 6
	# skirts hide cracks between neighbouring LODs
	var skirt := 2.0 + step * 1.5
	var base := m * m
	var edges := [[], [], [], []]
	for t in m:
		edges[0].append(t)                    # north row
		edges[1].append((m - 1) * m + t)      # south row
		edges[2].append(t * m)                # west col
		edges[3].append(t * m + m - 1)        # east col
	var vi := base
	for ei in 4:
		var row: Array = edges[ei]
		var start := vi
		for t in m:
			var src: int = row[t]
			verts[vi] = verts[src] - Vector3(0, skirt, 0)
			norms[vi] = norms[src]
			vi += 1
		for t in m - 1:
			var a0: int = row[t]
			var a1: int = row[t + 1]
			var b0 := start + t
			var b1 := start + t + 1
			if ei == 0 or ei == 3:
				idx[q] = a0; idx[q + 1] = b0; idx[q + 2] = a1
				idx[q + 3] = a1; idx[q + 4] = b0; idx[q + 5] = b1
			else:
				idx[q] = a0; idx[q + 1] = a1; idx[q + 2] = b0
				idx[q + 3] = a1; idx[q + 4] = b1; idx[q + 5] = b0
			q += 6
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_NORMAL] = norms
	arr[Mesh.ARRAY_INDEX] = idx
	return arr


# --------------------------------------------------------------------------- collision
func register_body(b: Node3D) -> void:
	if not bodies.has(b):
		bodies.append(b)


func unregister_body(b: Node3D) -> void:
	bodies.erase(b)


func _physics_process(_delta: float) -> void:
	var now := Time.get_ticks_msec() * 0.001
	var tile_size := COL_CELLS * wd.cell
	for b in bodies:
		if not is_instance_valid(b):
			continue
		var p: Vector3 = b.global_position
		var v := Vector3.ZERO
		if b is RigidBody3D:
			v = b.linear_velocity
		for probe: Vector3 in [p, p + v * 0.6]:
			var tx := floori((probe.x + wd.half) / tile_size)
			var tz := floori((probe.z + wd.half) / tile_size)
			for dz in range(-1, 2):
				for dx in range(-1, 2):
					_ensure_tile(Vector2i(tx + dx, tz + dz), now)
	if Engine.get_physics_frames() % 120 == 0:
		var drop := []
		for key in collision:
			if now - collision[key].t > 6.0:
				drop.append(key)
		for key in drop:
			collision[key].body.queue_free()
			collision.erase(key)


func _ensure_tile(key: Vector2i, now: float) -> void:
	var tiles := (wd.n - 1) / COL_CELLS
	if key.x < 0 or key.y < 0 or key.x >= tiles or key.y >= tiles:
		return
	if collision.has(key):
		collision[key].t = now
		return
	var w := COL_CELLS + 1
	var data := PackedFloat32Array()
	data.resize(w * w)
	var i0 := key.x * COL_CELLS
	var j0 := key.y * COL_CELLS
	var scale := wd.cell
	for jj in w:
		var row := (j0 + jj) * wd.n + i0
		for ii in w:
			data[jj * w + ii] = wd.heights[row + ii] / scale
	var shape := HeightMapShape3D.new()
	shape.map_width = w
	shape.map_depth = w
	shape.map_data = data
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	body.set_meta("surface", "terrain")
	var cs := CollisionShape3D.new()
	cs.shape = shape
	body.add_child(cs)
	add_child(body)
	var cx := (i0 + COL_CELLS * 0.5) * wd.cell - wd.half
	var cz := (j0 + COL_CELLS * 0.5) * wd.cell - wd.half
	body.global_transform = Transform3D(Basis().scaled(Vector3(scale, scale, scale)), Vector3(cx, 0.0, cz))
	collision[key] = {"body": body, "t": now}


# --------------------------------------------------------------------------- tunnel caps
## Rock "lids" that restore the mountain surface above tunnels (the heightmap is cut there).
func _build_tunnel_caps() -> void:
	var c = wd.json.get("tunnel_caps")
	if c == null:
		return
	var w := int(c.w)
	var h := int(c.h)
	var data: Array = c.data
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var idx := PackedInt32Array()
	var faces := PackedVector3Array()
	var index_of := {}
	for j in h:
		for i in w:
			var v: float = data[j * w + i]
			if v < -9000.0:
				continue
			var gi := int(c.i0) + i
			var gj := int(c.j0) + j
			index_of[Vector2i(i, j)] = verts.size()
			verts.append(Vector3(gi * wd.cell - wd.half, v, gj * wd.cell - wd.half))
			norms.append(Vector3.UP)
	for j in h - 1:
		for i in w - 1:
			var a = index_of.get(Vector2i(i, j))
			var b = index_of.get(Vector2i(i + 1, j))
			var cc = index_of.get(Vector2i(i, j + 1))
			var d = index_of.get(Vector2i(i + 1, j + 1))
			if a != null and b != null and d != null:
				idx.append_array([a, b, d])
				faces.append_array([verts[a], verts[b], verts[d]])
			if a != null and d != null and cc != null:
				idx.append_array([a, d, cc])
				faces.append_array([verts[a], verts[d], verts[cc]])
	if idx.is_empty():
		return
	# smooth normals
	var acc := PackedVector3Array()
	acc.resize(verts.size())
	for t in range(0, idx.size(), 3):
		var nrm := (verts[idx[t + 1]] - verts[idx[t]]).cross(verts[idx[t + 2]] - verts[idx[t]])
		for k in 3:
			acc[idx[t + k]] += nrm
	for k in acc.size():
		norms[k] = -acc[k].normalized() if acc[k].y < 0 else acc[k].normalized()
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_NORMAL] = norms
	arr[Mesh.ARRAY_INDEX] = idx
	var mi := MeshInstance3D.new()
	mi.mesh = _arrays_to_mesh(arr)
	mi.material_override = material
	add_child(mi)
	caps_body = StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var sh := ConcavePolygonShape3D.new()
	sh.backface_collision = true
	sh.set_faces(faces)
	cs.shape = sh
	caps_body.add_child(cs)
	caps_body.set_meta("surface", "terrain")
	add_child(caps_body)
