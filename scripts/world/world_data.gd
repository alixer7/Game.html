class_name WorldData
extends RefCounted
## Loads the baked world (heightmap, splat, roads, events...) and answers spatial queries.

const DIR := "res://assets/world/"

var n := 2049
var cell := 2.0
var half := 2048.0
var heights := PackedFloat32Array()
var json: Dictionary = {}
var splat: Image
var objects := PackedFloat32Array()   # records of 6 floats: type x y z yaw scale
var object_count := 0
var obj_grid := {}                    # Vector2i(64 m cell) -> PackedInt32Array of object indices
var roads: Array = []
var events: Array = []
var road_grid := {}                   # Vector2i(32 m cell) -> Array of [road_idx, sample_idx]
var river_pts := PackedVector3Array()
var river_hw := PackedFloat32Array()
var river_grid := {}


func load_all() -> void:
	var t0 := Time.get_ticks_msec()
	json = JSON.parse_string(FileAccess.get_file_as_string(DIR + "world.json"))
	n = int(json.n)
	cell = float(json.cell)
	half = float(json.half)
	var comp := FileAccess.get_file_as_bytes(DIR + "heightmap.bin")
	var raw := comp.decompress(n * n * 4, FileAccess.COMPRESSION_DEFLATE)
	heights = raw.to_float32_array()
	var tex: Texture2D = load(DIR + "splat.png")
	splat = tex.get_image()
	if splat.is_compressed():
		splat.decompress()
	var ob := FileAccess.get_file_as_bytes(DIR + "objects.bin")
	# objects.bin is zlib-compressed float32 data; size unknown -> dynamic decompress
	objects = ob.decompress_dynamic(64 * 1024 * 1024, FileAccess.COMPRESSION_DEFLATE).to_float32_array()
	object_count = objects.size() / 6
	for i in object_count:
		var key := Vector2i(floori(objects[i * 6 + 1] / 64.0), floori(objects[i * 6 + 3] / 64.0))
		if not obj_grid.has(key):
			obj_grid[key] = PackedInt32Array()
		obj_grid[key].append(i)
	roads = json.roads
	events = json.events
	for ri in roads.size():
		var r: Dictionary = roads[ri]
		var pts: Array = r.pts
		var pv := PackedVector3Array()
		pv.resize(pts.size() / 3)
		for k in pv.size():
			pv[k] = Vector3(pts[k * 3], pts[k * 3 + 1], pts[k * 3 + 2])
		r["pv"] = pv
		for k in pv.size():
			var key := Vector2i(floori(pv[k].x / 32.0), floori(pv[k].z / 32.0))
			if not road_grid.has(key):
				road_grid[key] = []
			road_grid[key].append(Vector2i(ri, k))
	var rp: Array = json.river.pts
	for k in rp.size() / 3:
		river_pts.append(Vector3(rp[k * 3], rp[k * 3 + 1], rp[k * 3 + 2]))
		river_hw.append(float(json.river.hw[k]))
		var key := Vector2i(floori(rp[k * 3] / 64.0), floori(rp[k * 3 + 2] / 64.0))
		if not river_grid.has(key):
			river_grid[key] = PackedInt32Array()
		river_grid[key].append(k)
	print("[world] data loaded in %d ms (%d objects, %d roads)" % [Time.get_ticks_msec() - t0, object_count, roads.size()])


func h_at(i: int, j: int) -> float:
	i = clampi(i, 0, n - 1)
	j = clampi(j, 0, n - 1)
	return heights[j * n + i]


func height(x: float, z: float) -> float:
	var gx := (x + half) / cell
	var gz := (z + half) / cell
	var i := floori(gx)
	var j := floori(gz)
	var fx := gx - i
	var fz := gz - j
	var h00 := h_at(i, j)
	var h10 := h_at(i + 1, j)
	var h01 := h_at(i, j + 1)
	var h11 := h_at(i + 1, j + 1)
	# match the mesh / physics triangulation (diagonal from (i+1,j) to (i,j+1))
	if fx + fz < 1.0:
		return h00 + (h10 - h00) * fx + (h01 - h00) * fz
	return h11 + (h01 - h11) * (1.0 - fx) + (h10 - h11) * (1.0 - fz)


func normal(x: float, z: float) -> Vector3:
	var e := cell
	var hl := height(x - e, z)
	var hr := height(x + e, z)
	var hd := height(x, z - e)
	var hu := height(x, z + e)
	return Vector3(hl - hr, 2.0 * e, hd - hu).normalized()


## material weights at a point: returns Color(rock, sand, dirt, snow); grass = 1 - sum
func splat_at(x: float, z: float) -> Color:
	var w := splat.get_width()
	var u := clampi(int((x + half) / (half * 2.0) * w), 0, w - 1)
	var v := clampi(int((z + half) / (half * 2.0) * w), 0, w - 1)
	return splat.get_pixel(u, v)


## nearest road sample around a position (within ~64 m). Returns {road, idx, dist, pos} or {}.
func nearest_road(p: Vector3, max_dist := 60.0, skip_types := []) -> Dictionary:
	var best := {}
	var bd := max_dist * max_dist
	var cx := floori(p.x / 32.0)
	var cz := floori(p.z / 32.0)
	var rad := int(ceil(max_dist / 32.0))
	for dx in range(-rad, rad + 1):
		for dz in range(-rad, rad + 1):
			var key := Vector2i(cx + dx, cz + dz)
			if not road_grid.has(key):
				continue
			for e in road_grid[key]:
				var r: Dictionary = roads[e.x]
				if skip_types.has(r.type):
					continue
				var q: Vector3 = r.pv[e.y]
				var d := Vector2(q.x - p.x, q.z - p.z).length_squared()
				if d < bd:
					bd = d
					best = {"road": e.x, "idx": e.y, "dist": sqrt(d), "pos": q}
	return best


func road_tangent(ri: int, k: int) -> Vector3:
	var pv: PackedVector3Array = roads[ri].pv
	var m := pv.size()
	var a: Vector3
	var b: Vector3
	if roads[ri].closed:
		a = pv[(k - 1 + m) % m]
		b = pv[(k + 1) % m]
	else:
		a = pv[maxi(k - 1, 0)]
		b = pv[mini(k + 1, m - 1)]
	var t := b - a
	t.y = 0.0
	return t.normalized() if t.length() > 0.001 else Vector3.FORWARD


## ground height including road decks (bridges)
func ground_height(p: Vector3) -> float:
	var h := height(p.x, p.z)
	var nr := nearest_road(p, 14.0)
	if not nr.is_empty():
		var r: Dictionary = roads[nr.road]
		if nr.dist < r.width * 0.5 + 0.5:
			h = maxf(h, nr.pos.y) if r.bridge[nr.idx] == 1 else nr.pos.y
	return h


func region_name(p: Vector3) -> String:
	var x := p.x
	var z := p.z
	if x > 470 and x < 1660 and z > -590 and z < 700:
		return "region_city"
	if x > 1060 and z < -880:
		return "region_circuit"
	if Vector2(x + 200, z - 1440).length() < 520:
		return "region_ruins"
	if z < -1100 and x > -700:
		return "region_mountain"
	if z < -650 and x < -700:
		return "region_forest"
	if x < -700 and z > 450:
		return "region_desert"
	if z > 1050:
		return "region_coast"
	if absf(x - 200) < 260:
		return "region_valley"
	return "region_countryside"


## water surface height at a position (or -1000 if dry land)
func water_level(p: Vector3) -> float:
	var lvl := -1000.0
	if height(p.x, p.z) < 0.0:
		lvl = 0.0
	var L: Dictionary = json.lake
	if Vector2(p.x - L.x, p.z - L.z).length() < float(L.r):
		lvl = maxf(lvl, float(L.h))
	var cx := floori(p.x / 64.0)
	var cz := floori(p.z / 64.0)
	for dz in range(-1, 2):
		for dx in range(-1, 2):
			var key := Vector2i(cx + dx, cz + dz)
			if not river_grid.has(key):
				continue
			for k in river_grid[key]:
				var q := river_pts[k]
				if Vector2(q.x - p.x, q.z - p.z).length() < river_hw[k] + 1.0:
					lvl = maxf(lvl, q.y)
	return lvl
