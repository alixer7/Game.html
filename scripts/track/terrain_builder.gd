class_name TerrainBuilder
extends RefCounted
## Heightfield terrain sculpted around the track.
##
##  height = base noise (rolling hills) + authored features (hills / basins)
##           + periphery rise (distance from any road -> forested hills that
##             enclose the world)  blended with road stamps (roads conform,
##             river carves its channel, aqueduct footprint is cut out).

var origin := Vector2.ZERO      # world x/z of cell (0,0)
var cell := 2.5
var nx := 0
var nz := 0
var h := PackedFloat32Array()
var road_w := PackedFloat32Array()      # max stamp weight (1 = under a road)
var road_sum_h := PackedFloat32Array()
var road_sum_k := PackedFloat32Array()
var dist := PackedFloat32Array()        # metres to the nearest road footprint (any road)
var occ := PackedByteArray()            # 1 = inside a road footprint (any road, incl. elevated)
var water := PackedByteArray()          # 1 = river/pond water cell
var surf := PackedByteArray()
var splat := PackedColorArray()
var hole := PackedByteArray()
var features: Array = []                # {"type","x","z","r","h"}

var _n1 := FastNoiseLite.new()
var _n2 := FastNoiseLite.new()
var _n3 := FastNoiseLite.new()


func setup(bounds: Rect2, cell_size := 2.5, seed := 1234) -> void:
	cell = cell_size
	origin = bounds.position
	nx = int(ceil(bounds.size.x / cell)) + 1
	nz = int(ceil(bounds.size.y / cell)) + 1
	var n := nx * nz
	h.resize(n)
	road_w.resize(n)
	road_sum_h.resize(n)
	road_sum_k.resize(n)
	dist.resize(n)
	occ.resize(n)
	water.resize(n)
	surf.resize(n)
	splat.resize(n)
	hole.resize(n)
	road_w.fill(0.0)
	road_sum_h.fill(0.0)
	road_sum_k.fill(0.0)
	occ.fill(0)
	water.fill(0)
	hole.fill(0)
	surf.fill(Surfaces.GRASS)
	_n1.seed = seed
	_n1.frequency = 0.0055
	_n1.fractal_octaves = 4
	_n1.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_n2.seed = seed + 1
	_n2.frequency = 0.035
	_n2.fractal_octaves = 2
	_n3.seed = seed + 2
	_n3.frequency = 0.012
	_n3.fractal_octaves = 3
	_n3.fractal_type = FastNoiseLite.FRACTAL_RIDGED


func idx(ix: int, iz: int) -> int:
	return iz * nx + ix


func cell_pos(ix: int, iz: int) -> Vector2:
	return origin + Vector2(ix * cell, iz * cell)


func add_feature(type: String, x: float, z: float, r: float, height: float, extra := {}) -> void:
	var f := {"type": type, "x": x, "z": z, "r": r, "h": height}
	f.merge(extra)
	features.append(f)


# ------------------------------------------------------------------ stamping
func stamp_path(path: SplinePath, is_main_river_level := false) -> void:
	for i in path.size():
		var mode := path.terrain_mode[i]
		var p := path.pos[i]
		var hw := path.width[i] * 0.5
		# occupancy (any road, also elevated ones) for scatter exclusion & distance field
		_mark_occ(p, hw + 0.8)
		if mode == "none":
			continue
		var inner := hw + 0.4
		var shoulder := 10.0
		var drop := 0.14
		if mode == "river":
			shoulder = 3.0
			drop = 0.3
			inner = hw - 0.2
		elif mode == "aqueduct":
			shoulder = 0.6
			drop = 13.0
			inner = hw + 1.5
		var r_total := inner + shoulder
		var rx := path.right[i]
		var ix0 := maxi(int(floor((p.x - r_total - origin.x) / cell)), 0)
		var ix1 := mini(int(ceil((p.x + r_total - origin.x) / cell)), nx - 1)
		var iz0 := maxi(int(floor((p.z - r_total - origin.y) / cell)), 0)
		var iz1 := mini(int(ceil((p.z + r_total - origin.y) / cell)), nz - 1)
		for iz in range(iz0, iz1 + 1):
			for ix in range(ix0, ix1 + 1):
				var c := cell_pos(ix, iz)
				var dx := c.x - p.x
				var dz := c.y - p.z
				var d := sqrt(dx * dx + dz * dz)
				if d > r_total:
					continue
				var wt := 1.0
				if d > inner:
					wt = 1.0 - smoothstep(0.0, shoulder, d - inner)
				var lat := clampf(dx * rx.x + dz * rx.z, -hw, hw)
				var target := p.y + rx.y * lat - drop
				if mode == "river" and d > inner:
					# banks rise out of the channel
					target = p.y + minf((d - inner) * 0.55, 1.4) - drop
				var k := wt * wt / (0.35 + d)
				var id := idx(ix, iz)
				road_sum_h[id] += target * k
				road_sum_k[id] += k
				if wt > road_w[id]:
					road_w[id] = wt
				if mode == "river" and d < hw + 1.0:
					water[id] = 1
					surf[id] = Surfaces.SAND


func _mark_occ(p: Vector3, r: float) -> void:
	var ix0 := maxi(int(floor((p.x - r - origin.x) / cell)), 0)
	var ix1 := mini(int(ceil((p.x + r - origin.x) / cell)), nx - 1)
	var iz0 := maxi(int(floor((p.z - r - origin.y) / cell)), 0)
	var iz1 := mini(int(ceil((p.z + r - origin.y) / cell)), nz - 1)
	for iz in range(iz0, iz1 + 1):
		for ix in range(ix0, ix1 + 1):
			var c := cell_pos(ix, iz)
			if Vector2(c.x - p.x, c.y - p.z).length() <= r:
				occ[idx(ix, iz)] = 1


func mark_water_disc(x: float, z: float, r: float) -> void:
	for iz in nz:
		for ix in nx:
			var c := cell_pos(ix, iz)
			if Vector2(c.x - x, c.y - z).length() <= r:
				water[idx(ix, iz)] = 1


# ------------------------------------------------------------------ height field
func base_height(x: float, z: float) -> float:
	var y := _n1.get_noise_2d(x, z) * 4.5 + _n2.get_noise_2d(x, z) * 0.6
	for f in features:
		var d := Vector2(x - float(f.x), z - float(f.z)).length()
		var r: float = f.r
		if d >= r:
			continue
		var t := 1.0 - d / r
		match String(f.type):
			"hill":
				y += float(f.h) * smoothstep(0.0, 1.0, t)
			"mesa":
				y += float(f.h) * smoothstep(0.0, 0.35, t)
			"basin":
				y -= float(f.h) * smoothstep(0.0, 0.7, t)
			"flatten":
				y = lerpf(y, float(f.h), smoothstep(0.0, 0.4, t))
	return y


func compute_distance_field() -> void:
	# two-pass chamfer distance transform from occupied cells
	var big := 1e9
	for i in occ.size():
		dist[i] = 0.0 if occ[i] == 1 else big
	var d1 := cell
	var d2 := cell * 1.41421
	for iz in nz:
		for ix in nx:
			var id := idx(ix, iz)
			var v := dist[id]
			if ix > 0:
				v = minf(v, dist[id - 1] + d1)
			if iz > 0:
				v = minf(v, dist[id - nx] + d1)
				if ix > 0:
					v = minf(v, dist[id - nx - 1] + d2)
				if ix < nx - 1:
					v = minf(v, dist[id - nx + 1] + d2)
			dist[id] = v
	for iz in range(nz - 1, -1, -1):
		for ix in range(nx - 1, -1, -1):
			var id := idx(ix, iz)
			var v := dist[id]
			if ix < nx - 1:
				v = minf(v, dist[id + 1] + d1)
			if iz < nz - 1:
				v = minf(v, dist[id + nx] + d1)
				if ix < nx - 1:
					v = minf(v, dist[id + nx + 1] + d2)
				if ix > 0:
					v = minf(v, dist[id + nx - 1] + d2)
			dist[id] = v


func finalize() -> void:
	compute_distance_field()
	for iz in nz:
		for ix in nx:
			var id := idx(ix, iz)
			var c := cell_pos(ix, iz)
			var base := base_height(c.x, c.y)
			# enclosing forested hills: rise with distance from the drivable network
			var dd := dist[id]
			var rise := smoothstep(28.0, 110.0, dd) * (16.0 + 26.0 * (_n3.get_noise_2d(c.x, c.y) * 0.5 + 0.5))
			base += rise
			var y := base
			if road_sum_k[id] > 0.0:
				var rh := road_sum_h[id] / road_sum_k[id]
				y = lerpf(base, rh, road_w[id])
			h[id] = y
	_paint()


func _paint() -> void:
	for iz in nz:
		for ix in nx:
			var id := idx(ix, iz)
			var c := cell_pos(ix, iz)
			var dd := dist[id]
			var dirt := 0.0
			# worn shoulders next to roads + random dirt patches
			dirt = (1.0 - smoothstep(0.0, 3.5, dd)) * 0.75
			dirt = maxf(dirt, smoothstep(0.55, 0.8, _n2.get_noise_2d(c.x * 0.6, c.y * 0.6) * 0.5 + 0.5) * 0.8)
			var sand := 0.0
			if water[id] == 1:
				sand = 1.0
			else:
				# wet banks around water
				for o: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1), Vector2i(2, 0), Vector2i(-2, 0), Vector2i(0, 2), Vector2i(0, -2)]:
					var jx: int = ix + o.x
					var jz: int = iz + o.y
					if jx >= 0 and jx < nx and jz >= 0 and jz < nz and water[idx(jx, jz)] == 1:
						sand = maxf(sand, 0.8 if absi(o.x) + absi(o.y) == 1 else 0.45)
			var moss := smoothstep(0.6, 0.85, _n1.get_noise_2d(c.x * 3.0, c.y * 3.0) * 0.5 + 0.5) * smoothstep(6.0, 20.0, dd)
			splat[id] = Color(dirt, 0.0, sand, moss)
			if sand > 0.6 and water[id] == 0:
				surf[id] = Surfaces.SAND
			elif dirt > 0.5 and surf[id] == Surfaces.GRASS:
				surf[id] = Surfaces.DIRT


func height_at(x: float, z: float) -> float:
	var fx := clampf((x - origin.x) / cell, 0.0, nx - 1.001)
	var fz := clampf((z - origin.y) / cell, 0.0, nz - 1.001)
	var ix := int(fx)
	var iz := int(fz)
	var tx := fx - ix
	var tz := fz - iz
	var a := h[idx(ix, iz)]
	var b := h[idx(ix + 1, iz)]
	var c := h[idx(ix, iz + 1)]
	var d := h[idx(ix + 1, iz + 1)]
	return lerpf(lerpf(a, b, tx), lerpf(c, d, tx), tz)


func normal_at(x: float, z: float) -> Vector3:
	var e := cell
	var hl := height_at(x - e, z)
	var hr := height_at(x + e, z)
	var hd := height_at(x, z - e)
	var hu := height_at(x, z + e)
	return Vector3(hl - hr, 2.0 * e, hd - hu).normalized()


func dist_at(x: float, z: float) -> float:
	var ix := clampi(int(round((x - origin.x) / cell)), 0, nx - 1)
	var iz := clampi(int(round((z - origin.y) / cell)), 0, nz - 1)
	return dist[idx(ix, iz)]


func water_at(x: float, z: float) -> bool:
	var ix := clampi(int(round((x - origin.x) / cell)), 0, nx - 1)
	var iz := clampi(int(round((z - origin.y) / cell)), 0, nz - 1)
	return water[idx(ix, iz)] == 1


func surface_at_xz(x: float, z: float) -> int:
	var ix := clampi(int(round((x - origin.x) / cell)), 0, nx - 1)
	var iz := clampi(int(round((z - origin.y) / cell)), 0, nz - 1)
	return surf[idx(ix, iz)]


func punch_holes_along(path: SplinePath, from_i: int, to_i: int, radius: float, below_y_offset: float) -> void:
	## Removes terrain cells (render + collision) that would cover a tunnel mouth.
	for i in range(maxi(from_i, 0), mini(to_i, path.size())):
		var p := path.pos[i]
		var ix0 := maxi(int(floor((p.x - radius - origin.x) / cell)), 0)
		var ix1 := mini(int(ceil((p.x + radius - origin.x) / cell)), nx - 1)
		var iz0 := maxi(int(floor((p.z - radius - origin.y) / cell)), 0)
		var iz1 := mini(int(ceil((p.z + radius - origin.y) / cell)), nz - 1)
		for iz in range(iz0, iz1 + 1):
			for ix in range(ix0, ix1 + 1):
				var c := cell_pos(ix, iz)
				if Vector2(c.x - p.x, c.y - p.z).length() <= radius and h[idx(ix, iz)] > p.y - 1.0 and h[idx(ix, iz)] < p.y + below_y_offset:
					hole[idx(ix, iz)] = 1


# ------------------------------------------------------------------ meshes
func build_meshes(parent: Node3D, material: Material, chunk_cells := 32, collision_dist := 70.0) -> StaticBody3D:
	var body: StaticBody3D = load("res://scripts/track/terrain_body.gd").new()
	body.name = "TerrainBody"
	body.collision_layer = 1
	body.collision_mask = 0
	body.set("terrain", self)
	parent.add_child(body)
	var mesh_root := Node3D.new()
	mesh_root.name = "TerrainMeshes"
	parent.add_child(mesh_root)
	var cx := int(ceil(float(nx - 1) / chunk_cells))
	var cz := int(ceil(float(nz - 1) / chunk_cells))
	for jz in cz:
		for jx in cx:
			var x0 := jx * chunk_cells
			var z0 := jz * chunk_cells
			var x1 := mini(x0 + chunk_cells, nx - 1)
			var z1 := mini(z0 + chunk_cells, nz - 1)
			var near_road := false
			var min_d := INF
			for iz in range(z0, z1 + 1, 4):
				for ix in range(x0, x1 + 1, 4):
					min_d = minf(min_d, dist[idx(ix, iz)])
			near_road = min_d < collision_dist
			for lod in 2:
				var step := 1 if lod == 0 else 2
				var mb := _chunk_mesh(x0, z0, x1, z1, step)
				if mb.vcount() == 0:
					continue
				var cc := cell_pos((x0 + x1) / 2, (z0 + z1) / 2)
				var centre := Vector3(cc.x, h[idx((x0 + x1) / 2, (z0 + z1) / 2)], cc.y)
				for vi in mb.verts.size():
					mb.verts[vi] -= centre
				var mi := MeshInstance3D.new()
				mi.position = centre
				mi.name = "T_%d_%d_L%d" % [jx, jz, lod]
				mi.mesh = mb.commit(null, material)
				mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF if lod == 1 else GeometryInstance3D.SHADOW_CASTING_SETTING_ON
				if lod == 0:
					mi.visibility_range_end = 190.0
					mi.visibility_range_end_margin = 10.0
				else:
					mi.visibility_range_begin = 180.0
					mi.visibility_range_begin_margin = 10.0
				mesh_root.add_child(mi)
			if near_road:
				var faces := _chunk_faces(x0, z0, x1, z1)
				if faces.size() > 0:
					var shape := ConcavePolygonShape3D.new()
					shape.set_faces(faces)
					shape.backface_collision = true
					var cs := CollisionShape3D.new()
					cs.shape = shape
					body.add_child(cs)
	return body


func _vertex_normal(ix: int, iz: int) -> Vector3:
	var l := h[idx(maxi(ix - 1, 0), iz)]
	var r := h[idx(mini(ix + 1, nx - 1), iz)]
	var d := h[idx(ix, maxi(iz - 1, 0))]
	var u := h[idx(ix, mini(iz + 1, nz - 1))]
	return Vector3(l - r, 2.0 * cell, d - u).normalized()


func _chunk_mesh(x0: int, z0: int, x1: int, z1: int, step: int) -> MeshBuilder:
	var mb := MeshBuilder.new()
	var w := int(ceil(float(x1 - x0) / step)) + 1
	var d := int(ceil(float(z1 - z0) / step)) + 1
	var ids := PackedInt32Array()
	ids.resize(w * d)
	for jz in d:
		for jx in w:
			var ix := mini(x0 + jx * step, x1)
			var iz := mini(z0 + jz * step, z1)
			var c := cell_pos(ix, iz)
			var id := idx(ix, iz)
			ids[jz * w + jx] = mb.add_vertex(Vector3(c.x, h[id], c.y), _vertex_normal(ix, iz), Vector2(c.x, c.y), splat[id])
	for jz in d - 1:
		for jx in w - 1:
			var ix := mini(x0 + jx * step, x1)
			var iz := mini(z0 + jz * step, z1)
			if hole[idx(ix, iz)] == 1:
				continue
			var a := ids[jz * w + jx]
			var b := ids[jz * w + jx + 1]
			var c := ids[(jz + 1) * w + jx + 1]
			var e := ids[(jz + 1) * w + jx]
			# seen from above (+Y), x right and z down: a,e,c,b is counter-clockwise
			mb.quad(a, e, c, b)
	# skirts on chunk borders hide LOD cracks
	var skirt := 2.5
	var borders := [[0, 0, 1, 0, w], [0, d - 1, 1, 0, w], [0, 0, 0, 1, d], [w - 1, 0, 0, 1, d]]
	for bdef in borders:
		var sx: int = bdef[0]
		var sz: int = bdef[1]
		var ddx: int = bdef[2]
		var ddz: int = bdef[3]
		var cnt: int = bdef[4]
		for k in cnt - 1:
			var ia := ids[(sz + ddz * k) * w + sx + ddx * k]
			var ib := ids[(sz + ddz * (k + 1)) * w + sx + ddx * (k + 1)]
			var pa := mb.verts[ia]
			var pb := mb.verts[ib]
			var na := mb.add_vertex(pa + Vector3.DOWN * skirt, mb.norms[ia], mb.uvs[ia], mb.cols[ia])
			var nb := mb.add_vertex(pb + Vector3.DOWN * skirt, mb.norms[ib], mb.uvs[ib], mb.cols[ib])
			# double-sided skirt (cheap: two quads)
			mb.quad(ia, ib, nb, na)
			mb.quad(ia, na, nb, ib)
	return mb


func _chunk_faces(x0: int, z0: int, x1: int, z1: int) -> PackedVector3Array:
	var faces := PackedVector3Array()
	for iz in range(z0, z1):
		for ix in range(x0, x1):
			if hole[idx(ix, iz)] == 1:
				continue
			if dist[idx(ix, iz)] > 75.0:
				continue
			var c := cell_pos(ix, iz)
			var a := Vector3(c.x, h[idx(ix, iz)], c.y)
			var b := Vector3(c.x + cell, h[idx(ix + 1, iz)], c.y)
			var cc := Vector3(c.x + cell, h[idx(ix + 1, iz + 1)], c.y + cell)
			var e := Vector3(c.x, h[idx(ix, iz + 1)], c.y + cell)
			# clockwise when seen from above = front face in Godot
			faces.append(a)
			faces.append(b)
			faces.append(cc)
			faces.append(a)
			faces.append(cc)
			faces.append(e)
	return faces
