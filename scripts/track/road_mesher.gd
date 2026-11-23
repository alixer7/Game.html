class_name RoadMesher
extends RefCounted
## Extrudes road cross-sections along a SplinePath, per style run, and builds
## matching collision (grouped by surface id) and side walls.

const PROFILES := {
	# [side, extra_outward_m, height_offset, edge_factor, curb]
	"paved": [[-1, 1.3, -0.6, 1.0, 0], [-1, 0.0, 0.0, 0.62, 0], [-1, -1.4, 0.03, 0.12, 0], [0, 0, 0.06, 0.0, 0],
		[1, -1.4, 0.03, 0.12, 0], [1, 0.0, 0.0, 0.62, 0], [1, 1.3, -0.6, 1.0, 0]],
	"deck_curb": [[-1, 0.0, -0.7, 0.0, 1], [-1, 0.0, 0.12, 0.0, 1], [-1, -0.55, 0.12, 0.0, 1], [-1, -0.6, 0.0, 0.05, 0],
		[0, 0, 0.06, 0.0, 0], [1, -0.6, 0.0, 0.05, 0], [1, -0.55, 0.12, 0.0, 1], [1, 0.0, 0.12, 0.0, 1], [1, 0.0, -0.7, 0.0, 1]],
	"soft": [[-1, 1.7, -0.6, 1.0, 0], [-1, 0.35, -0.04, 0.8, 0], [-1, -0.9, 0.0, 0.42, 0], [-1, -2.6, 0.01, 0.12, 0],
		[0, 0, 0.035, 0.0, 0], [1, -2.6, 0.01, 0.12, 0], [1, -0.9, 0.0, 0.42, 0], [1, 0.35, -0.04, 0.8, 0], [1, 1.7, -0.6, 1.0, 0]],
	"riverbed": [[-1, 1.6, 1.0, 1.0, 0], [-1, 0.0, 0.08, 0.7, 0], [-1, -2.2, -0.08, 0.25, 0], [0, 0, -0.14, 0.0, 0],
		[1, -2.2, -0.08, 0.25, 0], [1, 0.0, 0.08, 0.7, 0], [1, 1.6, 1.0, 1.0, 0]],
	"deck": [[-1, 0.0, -0.4, 0.0, 0], [-1, 0.0, 0.0, 0.0, 0], [0, 0, 0.0, 0.0, 0], [1, 0.0, 0.0, 0.0, 0], [1, 0.0, -0.4, 0.0, 0]],
	"crown": [[-1, 0.0, -0.9, 0.0, 0], [-1, 0.0, -0.32, 0.0, 0], [-0.5, 0.0, -0.08, 0.0, 0], [0, 0, 0.0, 0.0, 0],
		[0.5, 0.0, -0.08, 0.0, 0], [1, 0.0, -0.32, 0.0, 0], [1, 0.0, -0.9, 0.0, 0]],
	"channel": [[-1, 0.18, -0.45, 0.0, 0], [-1, 0.18, 1.05, 0.0, 0], [-1, 0.0, 1.05, 0.0, 0], [-1, 0.0, 0.0, 0.0, 0],
		[0, 0, -0.02, 0.0, 0], [1, 0.0, 0.0, 0.0, 0], [1, 0.0, 1.05, 0.0, 0], [1, 0.18, 1.05, 0.0, 0], [1, 0.18, -0.45, 0.0, 0]],
}

# style -> [profile, material kind]
const STYLES := {
	"roof": ["deck_curb", "roof"],
	"cobble": ["paved", "cobble"],
	"mill": ["paved", "cobble"],
	"dirt": ["soft", "dirt"],
	"roots": ["soft", "roots"],
	"bank": ["soft", "dirt"],
	"lane": ["soft", "dirt"],
	"landing": ["soft", "dirt"],
	"ruins": ["soft", "ruins"],
	"river": ["riverbed", "riverbed"],
	"boardwalk": ["deck", "planks"],
	"kicker": ["deck", "planks"],
	"log_ramp": ["crown", "bark"],
	"ridge": ["soft", "rock"],
	"slab": ["deck", "rock"],
	"flume": ["channel", "planks"],
	"cave": ["soft", "rock"],
}


static func build(path: SplinePath, parent: Node3D, name_prefix: String, flow_speed := 0.0, style_list: PackedStringArray = PackedStringArray()) -> Node3D:
	var root := Node3D.new()
	root.name = name_prefix
	parent.add_child(root)
	var n := path.size()
	var styles: PackedStringArray = style_list
	# ---- runs of equal style -> meshes
	var i := 0
	while i < n:
		var st := styles[i]
		var j := i
		while j + 1 < n and styles[j + 1] == st:
			j += 1
		# include one sample of overlap so runs connect
		var j_end := mini(j + 1, n - 1) if not path.closed else j + 1
		if st != "gap" and STYLES.has(st):
			_build_run(path, root, name_prefix, st, i, j_end, flow_speed)
		i = j + 1
	# ---- walls
	_build_walls(path, root, styles)
	return root


static func _profile_point(path: SplinePath, k: int, pp: Array) -> Vector3:
	var hw := path.width[k] * 0.5
	var side: float = pp[0]
	var lat := side * hw + signf(side) * float(pp[1])
	return path.pos[k] + path.right[k] * lat + path.up[k] * float(pp[2])


static func _build_run(path: SplinePath, root: Node3D, name_prefix: String, style: String, i0: int, i1: int, flow_speed: float) -> void:
	var n := path.size()
	var def: Array = STYLES[style]
	var prof: Array = PROFILES[def[0]]
	var mat := Mats.road(def[1])
	var mb := MeshBuilder.new()
	var cols := prof.size()
	var count := i1 - i0 + 1
	for s in count:
		var k := (i0 + s) % n
		var hw := path.width[k] * 0.5
		for c in cols:
			var pp: Array = prof[c]
			var side: float = pp[0]
			var lat := side * hw + signf(side) * float(pp[1])
			var p := path.pos[k] + path.right[k] * lat + path.up[k] * float(pp[2])
			var wear := clampf(1.0 - absf(lat) / maxf(hw * 0.7, 1.0), 0.0, 1.0) * 0.8
			var col := Color(float(pp[3]), wear, 0.0, float(pp[4]))
			if style == "river":
				col.b = 1.0
			mb.add_vertex(p, path.up[k], Vector2(lat, path.dist[k]), col)
	for s in count - 1:
		for c in cols - 1:
			var a := s * cols + c
			var b := a + 1
			var d := a + cols
			var e := d + 1
			# profile listed left -> right, samples forward: a,b,e,d is CCW from above
			mb.quad(a, b, e, d)
	mb.recompute_normals()
	var mi := MeshInstance3D.new()
	mi.name = "%s_%s_%d" % [name_prefix, style, i0]
	mi.mesh = mb.commit(null, mat)
	root.add_child(mi)
	# Solid end faces where a run starts/ends at a jump gap: no paper-thin road
	# edges to drive under, and the landing reads as a rock face.
	var caps := MeshBuilder.new()
	var prev_gap := path.closed or i0 > 0
	if prev_gap and path.style[(i0 - 1 + n) % n] == "gap" or (not path.closed and i0 == 0 and style in ["ridge", "slab", "kicker", "log_ramp", "flume", "boardwalk"]):
		_end_cap(caps, path, i0, prof, -1.0)
	var nxt := (i1 + 1) % n
	if (path.closed or i1 + 1 < n) and path.style[nxt] == "gap":
		_end_cap(caps, path, i1, prof, 1.0)
	elif not path.closed and i1 == n - 1 and style in ["ridge", "slab", "kicker", "flume"]:
		_end_cap(caps, path, i1, prof, 1.0)
	if caps.vcount() > 0:
		caps.recompute_normals()
		var cmi := MeshInstance3D.new()
		cmi.name = "Cap_%s_%d" % [style, i0]
		cmi.mesh = caps.commit(null, Mats.triplanar("rock"))
		root.add_child(cmi)
		var cbody := StaticBody3D.new()
		cbody.collision_layer = 1
		cbody.set_meta("surface", Surfaces.ROCK)
		var csh := ConcavePolygonShape3D.new()
		csh.set_faces(caps.to_collision_faces())
		csh.backface_collision = true
		var ccs := CollisionShape3D.new()
		ccs.shape = csh
		cbody.add_child(ccs)
		root.add_child(cbody)
	# ---- collision grouped by surface id
	var s0 := 0
	while s0 < count - 1:
		var k0 := (i0 + s0) % n
		var sid := path.surface[k0]
		var s1 := s0
		while s1 + 1 < count - 1 and path.surface[(i0 + s1 + 1) % n] == sid:
			s1 += 1
		var faces := PackedVector3Array()
		for s in range(s0, s1 + 1):
			for c in cols - 1:
				var a := s * cols + c
				var b := a + 1
				var d := a + cols
				var e := d + 1
				# same triangles as the render mesh (stored clockwise)
				faces.append(mb.verts[a]); faces.append(mb.verts[e]); faces.append(mb.verts[d])
				faces.append(mb.verts[a]); faces.append(mb.verts[b]); faces.append(mb.verts[e])
		var body: StaticBody3D = load("res://scripts/track/road_body.gd").new()
		body.name = "Col_%s_%d" % [style, i0 + s0]
		body.collision_layer = 1
		body.collision_mask = 0
		body.set("surface", sid)
		if sid == Surfaces.CURRENT:
			body.set("path", path)
			body.set("flow_speed", flow_speed if flow_speed > 0.0 else 6.0)
		body.set_meta("surface", sid)
		var shape := ConcavePolygonShape3D.new()
		shape.set_faces(faces)
		shape.backface_collision = true
		var cs := CollisionShape3D.new()
		cs.shape = shape
		body.add_child(cs)
		root.add_child(body)
		s0 = s1 + 1


static func _end_cap(mb: MeshBuilder, path: SplinePath, k: int, prof: Array, dir: float) -> void:
	## Vertical face from the road cross-section down 9 m, facing along `dir` * tangent.
	var t := path.tan[k] * dir
	var top: Array[Vector3] = []
	for pp in prof:
		top.append(_profile_point(path, k, pp))
	var c := Color(0.85, 0.82, 0.78, 0.4)
	for i in top.size() - 1:
		var a := top[i]
		var b := top[i + 1]
		var a2 := a + Vector3.DOWN * 9.0
		var b2 := b + Vector3.DOWN * 9.0
		var i0 := mb.add_vertex(a, t, Vector2.ZERO, c)
		mb.add_vertex(b, t, Vector2.ZERO, c)
		mb.add_vertex(b2, t, Vector2.ZERO, c)
		mb.add_vertex(a2, t, Vector2.ZERO, c)
		var fn := (b - a).cross(a2 - a)
		if fn.dot(t) > 0.0:
			mb.quad(i0, i0 + 1, i0 + 2, i0 + 3)
		else:
			mb.quad(i0, i0 + 3, i0 + 2, i0 + 1)


static func _build_walls(path: SplinePath, root: Node3D, styles: PackedStringArray) -> void:
	for side: int in [-1, 1]:
		var arr: PackedStringArray = path.wall_l if side == -1 else path.wall_r
		var n := path.size()
		var i := 0
		while i < n:
			var wt := arr[i]
			if wt == "none" or styles[i] == "gap":
				i += 1
				continue
			var j := i
			while j + 1 < n and arr[j + 1] == wt and styles[j + 1] != "gap":
				j += 1
			_wall_run(path, root, side, wt, i, mini(j + 1, n - 1))
			i = j + 1


static func _wall_run(path: SplinePath, root: Node3D, side: int, wtype: String, i0: int, i1: int) -> void:
	var mb := MeshBuilder.new()
	var faces := PackedVector3Array()
	var height := 1.15
	var thick := 0.55
	var mat: Material = Mats.triplanar("stone")
	var noise := MeshLib.make_noise(i0 * 13 + side * 7, 0.25)
	match wtype:
		"ruin":
			mat = Mats.triplanar("stone")
		"rail":
			mat = Mats.triplanar("wood")
			height = 1.0
			thick = 0.15
	var prev_in_b := Vector3.ZERO
	for k in range(i0, i1 + 1):
		var hw := path.width[k] * 0.5
		var r := path.right[k] * float(side)
		var base_in := path.pos[k] + r * (hw + 0.02)
		var base_out := path.pos[k] + r * (hw + 0.02 + thick)
		var hh := height
		if wtype == "ruin":
			hh = 1.0 + (noise.get_noise_1d(float(k) * 3.0) * 0.5 + 0.5) * 1.3
		var top_in := base_in + Vector3.UP * hh
		var top_out := base_out + Vector3.UP * hh
		var down := Vector3.DOWN * 1.6
		var c := Color(1, 1, 1, 1)
		var v0 := mb.add_vertex(base_in + down, -r, Vector2.ZERO, c)
		var v1 := mb.add_vertex(top_in, -r, Vector2.ZERO, c)
		var v2 := mb.add_vertex(top_out, Vector3.UP, Vector2.ZERO, c)
		var v3 := mb.add_vertex(base_out + down, r, Vector2.ZERO, c)
		if k > i0:
			var p0 := v0 - 4
			var p1 := v1 - 4
			var p2 := v2 - 4
			var p3 := v3 - 4
			if side == -1:
				mb.quad(p0, v0, v1, p1)
				mb.quad(p1, v1, v2, p2)
				mb.quad(p2, v2, v3, p3)
			else:
				mb.quad(p0, p1, v1, v0)
				mb.quad(p1, p2, v2, v1)
				mb.quad(p2, p3, v3, v2)
			# collision: inner face up to the visible top (min 1.0 m)
			var a := mb.verts[p0]
			var b := mb.verts[v0]
			var ch_a := maxf(mb.verts[p1].y - a.y, 1.0 + 1.6)
			var ch_b := maxf(mb.verts[v1].y - b.y, 1.0 + 1.6)
			var at := a + Vector3.UP * ch_a
			var bt := b + Vector3.UP * ch_b
			faces.append(a); faces.append(b); faces.append(bt)
			faces.append(a); faces.append(bt); faces.append(at)
		prev_in_b = base_in
	mb.recompute_normals()
	var mi := MeshInstance3D.new()
	mi.name = "Wall_%s_%d_%d" % [wtype, side, i0]
	mi.mesh = mb.commit(null, mat)
	root.add_child(mi)
	if wtype == "rail":
		_rail_posts(path, root, side, i0, i1)
	var body := StaticBody3D.new()
	body.name = "WallCol_%d_%d" % [side, i0]
	body.collision_layer = 1
	body.collision_mask = 0
	body.set_meta("surface", Surfaces.ROCK)
	body.set_meta("wall", true)
	var shape := ConcavePolygonShape3D.new()
	shape.set_faces(faces)
	shape.backface_collision = true
	var cs := CollisionShape3D.new()
	cs.shape = shape
	body.add_child(cs)
	root.add_child(body)


static func _rail_posts(path: SplinePath, root: Node3D, side: int, i0: int, i1: int) -> void:
	var mb := MeshBuilder.new()
	var wood := Color(0.55, 0.38, 0.22)
	var step := maxi(int(3.0 / path.spacing), 1)
	for k in range(i0, i1 + 1, step):
		var hw := path.width[k] * 0.5
		var p := path.pos[k] + path.right[k] * float(side) * (hw + 0.1)
		var b := Basis.looking_at(path.tan[k], Vector3.UP)
		MeshLib.box(mb, Transform3D(b, p + Vector3.UP * 0.5), Vector3(0.16, 1.3, 0.16), wood)
	var mi := MeshInstance3D.new()
	mi.mesh = mb.commit(null, Mats.vcol(0.85))
	root.add_child(mi)


static func water_surface(path: SplinePath, parent: Node3D, i0: int, i1: int, half_extra: float, depth: float,
		foam_points: Array, speed := 1.0, kind := "river") -> MeshInstance3D:
	## Flowing water ribbon over a river/flume run. foam_points: Array of [Vector3, radius].
	var mb := MeshBuilder.new()
	var cols := 7
	var n := path.size()
	var count := i1 - i0 + 1
	for s in count:
		var k := (i0 + s) % n
		var hw := path.width[k] * 0.5 + half_extra
		for c in cols:
			var f := float(c) / float(cols - 1) * 2.0 - 1.0
			var lat := f * hw
			var p := path.pos[k] + path.right[k] * lat
			p.y = path.pos[k].y + depth + path.right[k].y * lat * 0.2
			var foam := 0.0
			for fp in foam_points:
				var q: Vector3 = fp[0]
				var rad: float = fp[1]
				var d := Vector2(q.x - p.x, q.z - p.z).length()
				foam = maxf(foam, 1.0 - smoothstep(rad * 0.6, rad * 1.8, d))
			mb.add_vertex(p, Vector3.UP, Vector2(lat, path.dist[k]), Color(absf(f), foam, speed, 1.0))
	for s in count - 1:
		for c in cols - 1:
			var a := s * cols + c
			mb.quad(a, a + 1, a + cols + 1, a + cols)
	var mi := MeshInstance3D.new()
	mi.name = "Water_%d" % i0
	mi.mesh = mb.commit(null, Mats.water(kind))
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi
