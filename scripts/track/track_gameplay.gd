class_name TrackGameplay
extends RefCounted
## Gameplay layer of a track: obstacles, pads, crates, collectibles, hazards,
## readability signage and the start grid. Placement encodes the design intent
## documented in TRACK_DESIGN.md.


static func at(sp: SplinePath, i: int, lat: float, lift := 0.0) -> Vector3:
	i = clampi(i, 0, sp.size() - 1)
	return sp.pos[i] + sp.right[i] * lat + sp.up[i] * lift


static func idx_u(sp: SplinePath, u: float) -> int:
	return clampi(int(round(u * float(sp.size() - 1))), 0, sp.size() - 1)


static func basis_along(sp: SplinePath, i: int) -> Basis:
	var t := sp.tan[i]
	t.y = 0.0
	return Basis.looking_at(t.normalized(), Vector3.UP)


# ------------------------------------------------------------------ planning
static func plan(tb: TrackBuilder) -> void:
	var sp := tb.main
	var per_row := int(9.0 / sp.spacing)
	var gardens := {
		"rock_garden_1": [[-4.6, 2.0], [-1.0, 4.8], [-5.2, 0.8], [2.6], [-3.0, 4.5]],
		"rock_garden_2": [[-2.0, 3.5], [-5.0, 0.5, 5.2], [-2.5, 2.8], [-4.8, 1.0], [-1.5, 4.6]],
		"rapids_steps": [[-5.0, 5.0], [-5.4, 4.6]],
	}
	for g in gardens:
		var k0 := tb.mark_index(g)
		var rows: Array = gardens[g]
		for j in rows.size():
			var k := (k0 + j * per_row) % sp.size()
			for lat in rows[j]:
				var r := tb.rng.randf_range(0.95, 1.45)
				if g == "rapids_steps":
					r = tb.rng.randf_range(0.8, 1.1)
				var p := at(sp, k, float(lat), -0.1)
				tb.river_rocks.append([p, r])
				tb.obstacles.append([p, r, "rock"])
	var cave: SplinePath = tb.branches.get("rootway_cave")
	if cave:
		var side := 1.0
		for k in range(8, cave.size() - 8, 7):
			var p := at(cave, k, side * 1.1)
			tb.obstacles.append([p, 0.55, "stalagmite"])
			side = -side


# ------------------------------------------------------------------ build
static func build_all(tb: TrackBuilder) -> void:
	var root := Node3D.new()
	root.name = "Gameplay"
	tb.root.add_child(root)
	_rocks_and_stalagmites(tb, root)
	_pads(tb, root)
	_item_boxes(tb, root)
	_amber(tb, root)
	_ruin_hazards(tb, root)
	_gate(tb, root)
	_chevrons(tb, root)
	_spawn_grid(tb)


static func _rocks_and_stalagmites(tb: TrackBuilder, root: Node3D) -> void:
	var mb := MeshBuilder.new()
	var stal := MeshBuilder.new()
	for o in tb.obstacles:
		var p: Vector3 = o[0]
		var r: float = o[1]
		match String(o[2]):
			"rock":
				var rm := MeshLib.rock(int(p.x * 13.0 + p.z * 7.0), 3)
				var s := r * 0.95
				mb.append_builder(rm, Transform3D(Basis(Vector3.UP, tb.rng.randf() * TAU).scaled(Vector3(s, s * 1.15, s)), p + Vector3.DOWN * 0.35))
				tb.add_cylinder_collider(root, p + Vector3.DOWN * 0.5, r * 0.88, 2.6, Surfaces.ROCK)
			"stalagmite":
				var h := tb.rng.randf_range(2.0, 3.2)
				MeshLib.tube(stal, PackedVector3Array([p + Vector3.DOWN * 0.2, p + Vector3.UP * h * 0.5, p + Vector3.UP * h]),
					PackedFloat32Array([r * 1.3, r * 0.75, 0.04]), 7, func(_t: float, _a: float, _p: Vector3) -> Color: return Color(0.85, 0.8, 0.86, 0.2), 1.0, false, MeshLib.make_noise(int(p.x), 1.2), 0.2)
				tb.add_cylinder_collider(root, p, r, h, Surfaces.ROCK)
	tb.add_static_mesh(root, mb, Mats.triplanar("rock"), "RiverRocks")
	if stal.vcount() > 0:
		tb.add_static_mesh(root, stal, Mats.triplanar("rock"), "Stalagmites")


static func _place_pad(tb: TrackBuilder, root: Node3D, sp: SplinePath, i: int, lat: float, tier: int, w := 4.0, l := 6.0) -> void:
	var pad := BoostPad.make(tier, w, l)
	var up := sp.up[i]
	var f := sp.tan[i].slide(up).normalized()
	pad.transform = Transform3D(Basis.looking_at(f, up), at(sp, i, lat, 0.0))
	root.add_child(pad)
	tb.pads.append({"pos": pad.position, "tier": tier, "path": sp, "index": i})


static func _pads(tb: TrackBuilder, root: Node3D) -> void:
	var sp := tb.main
	# Z1: reward for the inside line of the roof's right sweeper
	_place_pad(tb, root, sp, tb.mark_index("roof_pad"), 3.4, 1)
	# Z5 exit: Overdrive pad, slightly inside - a clean exit lines you up for it
	_place_pad(tb, root, sp, tb.mark_index("od_pad"), -1.2, 2, 5.0, 7.0)
	var lb: SplinePath = tb.branches.get("left_bank")
	if lb:
		_place_pad(tb, root, lb, idx_u(lb, 0.78), 0.0, 1)
	var cave: SplinePath = tb.branches.get("rootway_cave")
	if cave:
		_place_pad(tb, root, cave, cave.size() - 6, 0.0, 1, 3.5, 5.0)
	var shelf: SplinePath = tb.branches.get("shelf_rock")
	if shelf:
		var li := 0
		for i in shelf.size():
			if shelf.tags[i] == "shelf_land":
				li = i
				break
		_place_pad(tb, root, shelf, mini(li + 8, shelf.size() - 2), 0.0, 1)


static func _box_row(tb: TrackBuilder, root: Node3D, sp: SplinePath, i: int, lats: Array) -> void:
	for lat in lats:
		var box := ItemBox.make()
		box.position = at(sp, i, float(lat), 0.0)
		root.add_child(box)
		tb.item_boxes.append(box.position)


static func _item_boxes(tb: TrackBuilder, root: Node3D) -> void:
	var sp := tb.main
	var k := tb.mark_index("bank_split")
	_box_row(tb, root, sp, k + 10, [-3.5, 0.0, 3.5])
	var lb: SplinePath = tb.branches.get("left_bank")
	if lb:
		_box_row(tb, root, lb, idx_u(lb, 0.3), [-2.8, 0.0, 2.8])
		_box_row(tb, root, lb, idx_u(lb, 0.62), [-2.8, 0.0, 2.8])
	var rb: SplinePath = tb.branches.get("right_bank")
	if rb:
		_box_row(tb, root, rb, idx_u(rb, 0.5), [-1.4, 1.4])
	_box_row(tb, root, sp, tb.mark_index("crest_1") + 10, [-4.0, -1.3, 1.3, 4.0])
	_box_row(tb, root, sp, tb.mark_index("root_hops"), [-2.6, 0.0, 2.6])
	_box_row(tb, root, sp, tb.mark_index("rollers") + 22, [-4.5, -1.5, 1.5, 4.5])
	_box_row(tb, root, sp, tb.mark_index("hairpin_exit") + 8, [-4.0, -1.3, 1.3, 4.0])


static func _amber_line(tb: TrackBuilder, root: Node3D, sp: SplinePath, i0: int, i1: int, step: int, lat := 0.0, lift := 0.0) -> void:
	for i in range(i0, i1, step):
		var a := AmberPickup.make()
		a.position = at(sp, i, lat, lift)
		root.add_child(a)


static func _amber(tb: TrackBuilder, root: Node3D) -> void:
	var sp := tb.main
	var s := tb.mark_index("start_line")
	_amber_line(tb, root, sp, s + 20, s + 60, 5, -2.0)
	var lb: SplinePath = tb.branches.get("left_bank")
	if lb:
		_amber_line(tb, root, lb, idx_u(lb, 0.4), idx_u(lb, 0.55), 4)
	var lg: SplinePath = tb.branches.get("giants_log")
	if lg:
		_amber_line(tb, root, lg, 4, 20, 4)
	var cave: SplinePath = tb.branches.get("rootway_cave")
	if cave:
		_amber_line(tb, root, cave, 6, cave.size() - 6, 6)
	var fl: SplinePath = tb.branches.get("millrace_flume")
	if fl:
		var f0 := -1
		for i in fl.size():
			if fl.style[i] == "flume":
				f0 = i
				break
		if f0 >= 0:
			_amber_line(tb, root, fl, f0 + 6, mini(f0 + 50, fl.size() - 10), 6, 0.0, 0.1)


static func _ruin_hazards(tb: TrackBuilder, root: Node3D) -> void:
	var sp := tb.main
	var k := tb.mark_index("swing_log") + int(8.0 / sp.spacing)
	var hw := sp.width[k] * 0.5
	var swing := SwingingLog.make(hw * 2.0, tb.rng)
	var t := sp.tan[k]
	t.y = 0
	t = t.normalized()
	var r := t.cross(Vector3.UP).normalized()
	swing.transform = Transform3D(Basis(r, Vector3.UP, -t), sp.pos[k] + Vector3.DOWN * 0.1)
	root.add_child(swing)
	tb.obstacles.append([sp.pos[k], 1.5, "swing"])
	var kf := tb.mark_index("flytraps")
	var side := -1.0
	var phase := 0.0
	for j in 3:
		var kk := kf + j * int(7.0 / sp.spacing)
		var hw2 := sp.width[kk] * 0.5
		var trap := Flytrap.make(phase, hw2)
		var pos := sp.pos[kk] + sp.right[kk] * side * (hw2 + 1.9)
		pos.y = sp.pos[kk].y - 0.1
		var face := (sp.right[kk] * side)
		face.y = 0
		trap.transform = Transform3D(Basis.looking_at(face.normalized(), Vector3.UP), pos)
		root.add_child(trap)
		tb.obstacles.append([sp.pos[kk] - sp.right[kk] * side * -hw2 * 0.5, hw2 * 0.5, "flytrap"])
		side = -side
		phase += 2.05


static func _gate(tb: TrackBuilder, root: Node3D) -> void:
	var gl: SplinePath = tb.branches.get("gate_lane")
	if gl == null:
		return
	var gi := -1
	for i in gl.size():
		if gl.tags[i] == "gate":
			gi = i
			break
	if gi < 0:
		gi = gl.size() / 2
	var gate := BreakableGate.make(gl.width[gi])
	var t := gl.tan[gi]
	t.y = 0
	t = t.normalized()
	var r := t.cross(Vector3.UP).normalized()
	gate.transform = Transform3D(Basis(r, Vector3.UP, -t), gl.pos[gi])
	root.add_child(gate)


static func _chevrons(tb: TrackBuilder, root: Node3D) -> void:
	var sp := tb.main
	var mb := MeshBuilder.new()
	var corners := ["drs_apex", "hollow_exit", "od_pad", "mill_apex", "hairpin", "gate_lane_in"]
	for name in corners:
		if not tb.marks.has(name):
			continue
		var k := tb.mark_index(name)
		var back := int(18.0 / sp.spacing)
		var kc := k - back if name == "od_pad" else k
		var curv := 0.0
		for j in range(kc - 6, kc + 6):
			curv += sp.curvature_at((j + sp.size()) % sp.size())
		var left_turn := curv > 0.0
		var outside := 1.0 if left_turn else -1.0
		for j in 3:
			var kk := (kc + j * int(6.0 / sp.spacing)) % sp.size()
			var hw := sp.width[kk] * 0.5
			var p := sp.pos[kk] + sp.right[kk] * outside * (hw + 2.6)
			p.y = tb.ground_y(p.x, p.z)
			var face := -sp.tan[kk]
			face.y = 0
			var sign := MeshLib.chevron_sign(left_turn)
			var b := Basis.looking_at(-face.normalized(), Vector3.UP)
			mb.append_builder(sign, Transform3D(b.scaled(Vector3(1.25, 1.25, 1.25)), p))
	tb.add_static_mesh(root, mb, Mats.vcol(0.8), "Chevrons")


static func _spawn_grid(tb: TrackBuilder) -> void:
	var sp := tb.main
	var k := tb.mark_index("start_line")
	var back := int(5.5 / sp.spacing)
	for slot in 8:
		var row := slot / 2
		var col := slot % 2
		var kk := (k - (row + 1) * back - (1 if col == 1 else 0) + sp.size()) % sp.size()
		var lat := -2.8 if col == 0 else 2.8
		var p := at(sp, kk, lat, 0.25)
		var t := sp.tan[kk]
		t.y = 0
		var yaw := atan2(-t.x, -t.z)
		tb.spawn_grid.append(Transform3D(Basis(Vector3.UP, yaw), p))
