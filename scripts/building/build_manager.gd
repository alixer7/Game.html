class_name BuildManager
extends Node3D
## نظام البناء: شبكة المباني الحرة الاتجاه، التحقق من الدعم الإنشائي، الانهيار، القطع الحرة، المستوطنات، الحقول.

const C := 3.0

var world: Node
var buildings: Array = []
var pieces: Array = []
var _mesh_cache := {}
var _shape_cache := {}
var _tick_t := 0.0
var _spike_t := 0.0
var settlement_chests := {}
var settlement_fires := {}
var _last_hours := -1.0

func setup(w: Node) -> void:
	world = w

# ------------------------------------------------------------------
# الهندسة
func _geo(def_id: String) -> Dictionary:
	if _mesh_cache.has(def_id):
		return _mesh_cache[def_id]
	var d := BuildDB.get_piece(def_id)
	var part: String = d.get("part", "")
	var mat: String = d.get("mat", "wood")
	var a := MeshBuilder.new()
	var b := MeshBuilder.new()
	var shapes := []
	var m1: Material = null
	var m2: Material = MeshFactory.mat("wood")
	var W := Color(1, 1, 1)
	var tint := {"thatch": Color(1, 1, 1), "wood": Color(1, 1, 1), "stone": Color(0.95, 0.95, 0.95), "brick": Color(1, 1, 1)}.get(mat, W)
	if d.get("kind", "") == "grid":
		var tmat := mat
		if part == "foundation" and mat == "wood":
			tmat = "log"
		if part == "roof" and mat == "stone":
			tmat = "stone"
		m1 = TexGen.building_mat(tmat)
		match part:
			"foundation":
				_box(a, shapes, Vector3(0, -1.6, 0), Vector3(C, 3.2, C), tint)
				a.box(Vector3(0, -0.06, 0), Vector3(C + 0.06, 0.12, C + 0.06), tint * 0.85)
			"floor":
				_box(a, shapes, Vector3(0, -0.1, 0), Vector3(C, 0.2, C), tint)
			"wall":
				_box(a, shapes, Vector3(0, 1.5, 0), Vector3(C, 3.0, 0.24), tint)
			"doorway":
				_box(a, shapes, Vector3(-1.0, 1.5, 0), Vector3(1.0, 3.0, 0.24), tint)
				_box(a, shapes, Vector3(1.0, 1.5, 0), Vector3(1.0, 3.0, 0.24), tint)
				_box(a, shapes, Vector3(0, 2.6, 0), Vector3(1.0, 0.8, 0.24), tint)
			"window":
				_box(a, shapes, Vector3(0, 0.5, 0), Vector3(C, 1.0, 0.24), tint)
				_box(a, shapes, Vector3(0, 2.6, 0), Vector3(C, 0.8, 0.24), tint)
				_box(a, shapes, Vector3(-1.0, 1.6, 0), Vector3(1.0, 1.2, 0.24), tint)
				_box(a, shapes, Vector3(1.0, 1.6, 0), Vector3(1.0, 1.2, 0.24), tint)
				b.box(Vector3(0, 1.6, 0), Vector3(0.06, 1.2, 0.08), Color(0.35, 0.25, 0.15))
				b.box(Vector3(0, 1.6, 0), Vector3(1.0, 0.06, 0.08), Color(0.35, 0.25, 0.15))
			"roof":
				var ang := atan2(1.5, 3.0)
				var bs := Basis(Vector3.RIGHT, ang)
				a.box(Vector3(0, 1.5 * 0.5 + 0.08, 0), Vector3(C + 0.3, 0.16, sqrt(9.0 + 2.25) + 0.3), tint, bs)
				shapes.append([_box_shape(Vector3(C + 0.3, 0.2, sqrt(9.0 + 2.25) + 0.3)), Transform3D(bs, Vector3(0, 0.83, 0))])
				for sx in [-1.5, 1.5]:
					a.tri(Vector3(sx, 0, 1.5), Vector3(sx, 0, -1.5), Vector3(sx, 1.5, -1.5), tint * 0.9)
			"stairs":
				for i in range(6):
					a.box(Vector3(0, (i + 1) * 0.25, 1.25 - i * 0.5), Vector3(2.8, (i + 1) * 0.5, 0.5), tint)
				var bs2 := Basis(Vector3.RIGHT, PI / 4.0)
				shapes.append([_box_shape(Vector3(2.8, 0.2, 4.3)), Transform3D(bs2, Vector3(0, 1.45, 0))])
			"door":
				m1 = TexGen.building_mat("wood")
				var dc := Color(0.85, 0.75, 0.65) if mat == "wood" else Color(0.7, 0.68, 0.66)
				a.box(Vector3(0.48, 1.08, 0), Vector3(0.95, 2.15, 0.07), dc)
				b.box(Vector3(0.85, 1.05, -0.06), Vector3(0.06, 0.06, 0.06), Color(0.2, 0.2, 0.2))
				if mat != "wood":
					b.box(Vector3(0.48, 0.5, -0.04), Vector3(0.9, 0.08, 0.02), Color(0.35, 0.35, 0.38))
					b.box(Vector3(0.48, 1.7, -0.04), Vector3(0.9, 0.08, 0.02), Color(0.35, 0.35, 0.38))
				shapes.append([_box_shape(Vector3(0.95, 2.15, 0.1)), Transform3D(Basis(), Vector3(0.48, 1.08, 0))])
		m2 = MeshFactory.mat("wood") if part != "door" else MeshFactory.mat("metal")
	else:
		m1 = MeshFactory.mat("wood")
		var sz: Vector3 = d.get("size", Vector3.ONE)
		shapes.append([_box_shape(sz), Transform3D(Basis(), Vector3(0, sz.y * 0.5, 0))])
		var wd := Color(0.55, 0.38, 0.22)
		match def_id:
			"campfire":
				m1 = MeshFactory.mat("rock")
				m2 = MeshFactory.mat("bark")
				for i in range(9):
					var ang2 := TAU * i / 9.0
					a.blob(Vector3(cos(ang2) * 0.55, 0.08, sin(ang2) * 0.55), Vector3(0.17, 0.12, 0.15), Color(0.45, 0.44, 0.42), 0.3, 2.0, 4, 6, i * 3.0, 2, Color(0.4, 0.4, 0.4))
				for i in range(4):
					var ang3 := TAU * i / 4.0 + 0.4
					b.tube(Vector3(cos(ang3) * 0.4, 0.02, sin(ang3) * 0.4), Vector3(0, 0.45, 0), 0.06, 0.04, Color(0.3, 0.2, 0.12), Color(0.12, 0.08, 0.06), 6, 1)
				var emb := MeshBuilder.new()
				emb.blob(Vector3(0, 0.05, 0), Vector3(0.3, 0.06, 0.3), Color(1.0, 0.35, 0.08), 0.3, 3.0, 4, 8)
				var mm := MeshBuilder.commit([a, b, emb], [m1, m2, MeshFactory.mat("crystal")])
				var res := {"mesh": mm, "shapes": [[_box_shape(Vector3(1.3, 0.4, 1.3)), Transform3D(Basis(), Vector3(0, 0.2, 0))]]}
				_mesh_cache[def_id] = res
				return res
			"workbench":
				a.box(Vector3(0, 0.88, 0), Vector3(2.0, 0.12, 1.0), wd)
				for x in [-0.9, 0.9]:
					for z in [-0.4, 0.4]:
						a.box(Vector3(x, 0.41, z), Vector3(0.1, 0.82, 0.1), wd.darkened(0.2))
				a.box(Vector3(0, 0.25, 0), Vector3(1.8, 0.06, 0.8), wd.darkened(0.1))
				b.box(Vector3(-0.6, 1.0, 0.1), Vector3(0.3, 0.12, 0.15), Color(0.4, 0.4, 0.42))
				b.box(Vector3(0.4, 0.96, -0.2), Vector3(0.5, 0.04, 0.08), Color(0.5, 0.5, 0.52))
				m2 = MeshFactory.mat("metal")
			"furnace":
				m1 = MeshFactory.mat("rock")
				a.blob(Vector3(0, 0.85, 0), Vector3(0.8, 0.95, 0.8), Color(0.5, 0.47, 0.44), 0.12, 2.5, 7, 10, 3.0, 2, Color(0.35, 0.3, 0.28), 0.1, 0.9)
				a.tube(Vector3(0, 1.6, 0.2), Vector3(0, 2.4, 0.2), 0.2, 0.17, Color(0.45, 0.42, 0.4), Color(0.4, 0.38, 0.36), 8, 2)
				var glow := MeshBuilder.new()
				glow.box(Vector3(0, 0.55, -0.72), Vector3(0.5, 0.4, 0.1), Color(1.0, 0.45, 0.1))
				var mf := MeshBuilder.commit([a, glow], [m1, MeshFactory.mat("crystal")])
				var resf := {"mesh": mf, "shapes": shapes}
				_mesh_cache[def_id] = resf
				return resf
			"anvil":
				m1 = MeshFactory.mat("wood")
				a.tube(Vector3(0, 0, 0), Vector3(0, 0.55, 0), 0.3, 0.28, Color(0.42, 0.3, 0.2), Color(0.45, 0.32, 0.2), 9, 1, 0.05, Vector3.ZERO, 6)
				b.box(Vector3(0, 0.68, 0), Vector3(0.75, 0.22, 0.3), Color(0.32, 0.32, 0.35))
				b.box(Vector3(0, 0.84, 0), Vector3(0.95, 0.12, 0.34), Color(0.4, 0.4, 0.44))
				b.tube(Vector3(0.47, 0.84, 0), Vector3(0.72, 0.86, 0), 0.08, 0.01, Color(0.4, 0.4, 0.44), Color(0.45, 0.45, 0.5), 6, 1)
				m2 = MeshFactory.mat("metal")
			"loom":
				for x in [-0.7, 0.7]:
					a.tube(Vector3(x, 0, -0.4), Vector3(x, 1.6, -0.4), 0.05, 0.05, wd, wd, 6, 1)
					a.tube(Vector3(x, 0, 0.4), Vector3(x, 1.2, 0.4), 0.05, 0.05, wd, wd, 6, 1)
				a.tube(Vector3(-0.75, 1.55, -0.4), Vector3(0.75, 1.55, -0.4), 0.05, 0.05, wd, wd, 6, 1)
				a.tube(Vector3(-0.75, 0.9, 0.4), Vector3(0.75, 0.9, 0.4), 0.06, 0.06, wd, wd, 6, 1)
				b.box(Vector3(0, 1.15, 0.0), Vector3(1.3, 0.04, 0.82), Color(0.92, 0.9, 0.82), Basis(Vector3.RIGHT, -0.55))
				m2 = MeshFactory.mat("cloth")
			"tanning_rack":
				for x in [-0.85, 0.85]:
					a.tube(Vector3(x, 0, 0), Vector3(x, 1.8, 0), 0.05, 0.04, wd, wd, 6, 1)
				a.tube(Vector3(-0.9, 1.7, 0), Vector3(0.9, 1.7, 0), 0.04, 0.04, wd, wd, 6, 1)
				a.tube(Vector3(-0.9, 0.3, 0), Vector3(0.9, 0.3, 0), 0.04, 0.04, wd, wd, 6, 1)
				b.box(Vector3(0, 1.0, 0), Vector3(1.4, 1.25, 0.03), Color(0.62, 0.44, 0.3))
				m2 = MeshFactory.mat("cloth")
			"cooking_pot":
				for i in range(3):
					var ang4 := TAU * i / 3.0
					a.tube(Vector3(cos(ang4) * 0.55, 0, sin(ang4) * 0.55), Vector3(0, 1.2, 0), 0.03, 0.03, wd, wd, 5, 1)
				b.blob(Vector3(0, 0.6, 0), Vector3(0.34, 0.3, 0.34), Color(0.25, 0.22, 0.2), 0.03, 2.0, 7, 10, 0.0, 0, Color.BLACK, 0.1, 0.7)
				b.tube(Vector3(0, 0.8, 0), Vector3(0, 1.2, 0), 0.01, 0.01, Color(0.2, 0.2, 0.2), Color(0.2, 0.2, 0.2), 3, 1)
				m2 = MeshFactory.mat("metal")
			"wooden_chest", "large_chest":
				var s2: Vector3 = sz
				a.box(Vector3(0, s2.y * 0.4, 0), Vector3(s2.x, s2.y * 0.8, s2.z), wd)
				a.box(Vector3(0, s2.y * 0.88, 0), Vector3(s2.x + 0.04, s2.y * 0.2, s2.z + 0.04), wd.lightened(0.08))
				for x in [-s2.x * 0.35, s2.x * 0.35]:
					b.box(Vector3(x, s2.y * 0.5, 0), Vector3(0.07, s2.y + 0.02, s2.z + 0.03), Color(0.3, 0.3, 0.32))
				b.box(Vector3(0, s2.y * 0.75, -s2.z * 0.5 - 0.02), Vector3(0.12, 0.14, 0.04), Color(0.6, 0.5, 0.2))
				m1 = TexGen.building_mat("wood")
				m2 = MeshFactory.mat("metal")
			"strongbox":
				m1 = MeshFactory.mat("metal")
				a.box(Vector3(0, 0.42, 0), Vector3(1.0, 0.84, 0.8), Color(0.38, 0.39, 0.42))
				a.box(Vector3(0, 0.86, 0), Vector3(1.04, 0.06, 0.84), Color(0.3, 0.3, 0.33))
				b.box(Vector3(0, 0.55, -0.41), Vector3(0.18, 0.22, 0.04), Color(0.75, 0.62, 0.25))
				m2 = MeshFactory.mat("metal")
			"bed_straw":
				m1 = MeshFactory.mat("thatch")
				a.blob(Vector3(0, 0.08, 0), Vector3(0.5, 0.14, 1.05), Color(0.8, 0.68, 0.38), 0.15, 2.0, 5, 10, 2.0, 0, Color.BLACK, 0.1, 0.4)
				b.blob(Vector3(0, 0.2, 0.78), Vector3(0.32, 0.08, 0.16), Color(0.85, 0.8, 0.7), 0.1, 2.0, 4, 8)
				m2 = MeshFactory.mat("cloth")
			"bed_wood":
				a.box(Vector3(0, 0.2, 0), Vector3(1.2, 0.3, 2.2), wd)
				a.box(Vector3(0, 0.5, 1.05), Vector3(1.2, 0.8, 0.1), wd.darkened(0.15))
				b.box(Vector3(0, 0.42, 0), Vector3(1.1, 0.16, 2.0), Color(0.85, 0.82, 0.75))
				b.box(Vector3(0, 0.52, -0.3), Vector3(1.14, 0.06, 1.3), Color(0.5, 0.2, 0.18))
				b.box(Vector3(0, 0.54, 0.75), Vector3(0.7, 0.1, 0.3), Color(0.92, 0.9, 0.85))
				m2 = MeshFactory.mat("cloth")
			"torch_stand":
				a.tube(Vector3(0, 0, 0), Vector3(0, 1.6, 0), 0.05, 0.04, wd, wd, 6, 1)
				a.blob(Vector3(0, 1.62, 0), Vector3(0.1, 0.1, 0.1), Color(0.2, 0.14, 0.1), 0.2, 3.0, 4, 6)
			"crystal_lamp":
				m1 = MeshFactory.mat("metal")
				a.tube(Vector3(0, 0, 0), Vector3(0, 1.3, 0), 0.04, 0.03, Color(0.3, 0.3, 0.32), Color(0.35, 0.35, 0.38), 6, 1)
				a.disc(Vector3(0, 0.01, 0), Vector3.UP, 0.2, Color(0.3, 0.3, 0.32), 8)
				b.tube(Vector3(0, 1.3, 0), Vector3(0, 1.55, 0), 0.08, 0.08, Color(0.6, 0.45, 1.0), Color(0.7, 0.55, 1.0), 6, 1)
				b.tube(Vector3(0, 1.55, 0), Vector3(0, 1.7, 0), 0.08, 0.005, Color(0.7, 0.55, 1.0), Color(0.85, 0.75, 1.0), 6, 1)
				m2 = MeshFactory.mat("crystal")
			"wooden_table":
				a.box(Vector3(0, 0.8, 0), Vector3(1.6, 0.08, 1.0), wd)
				for x in [-0.7, 0.7]:
					for z in [-0.4, 0.4]:
						a.box(Vector3(x, 0.38, z), Vector3(0.08, 0.76, 0.08), wd.darkened(0.2))
			"wooden_chair":
				a.box(Vector3(0, 0.45, 0), Vector3(0.5, 0.06, 0.5), wd)
				for x in [-0.21, 0.21]:
					for z in [-0.21, 0.21]:
						a.box(Vector3(x, 0.22, z), Vector3(0.05, 0.44, 0.05), wd.darkened(0.2))
				a.box(Vector3(0, 0.75, 0.23), Vector3(0.5, 0.55, 0.05), wd)
			"rug":
				m1 = MeshFactory.mat("cloth")
				a.box(Vector3(0, 0.02, 0), Vector3(2.0, 0.03, 1.4), Color(0.55, 0.15, 0.12))
				a.box(Vector3(0, 0.025, 0), Vector3(1.6, 0.03, 1.0), Color(0.75, 0.55, 0.2))
				a.box(Vector3(0, 0.03, 0), Vector3(1.0, 0.03, 0.5), Color(0.2, 0.25, 0.45))
			"farm_plot":
				m1 = MeshFactory.mat("rock")
				a.box(Vector3(0, 0.1, 0), Vector3(2.0, 0.2, 2.0), Color(0.3, 0.2, 0.13))
				for i in range(4):
					a.box(Vector3(-0.75 + i * 0.5, 0.22, 0), Vector3(0.22, 0.08, 1.9), Color(0.25, 0.17, 0.1))
				for sx in [-1.0, 1.0]:
					b.box(Vector3(sx, 0.12, 0), Vector3(0.08, 0.24, 2.08), wd)
					b.box(Vector3(0, 0.12, sx), Vector3(2.08, 0.24, 0.08), wd)
			"water_collector":
				a.tube(Vector3(0, 0, 0), Vector3(0, 0.9, 0), 0.42, 0.45, wd, wd.lightened(0.1), 12, 3, 0.0, Vector3(0, 0, 0), 6)
				a.disc(Vector3(0, 0.9, 0), Vector3.UP, 0.44, Color(0.2, 0.35, 0.45), 12)
				b.tube(Vector3(0, 0.9, 0), Vector3(0, 1.2, 0), 0.2, 0.6, Color(0.85, 0.82, 0.72), Color(0.85, 0.82, 0.72), 12, 1)
				m2 = MeshFactory.mat("cloth")
			"wood_fence":
				for x in [-1.4, 0.0, 1.4]:
					a.tube(Vector3(x, -0.2, 0), Vector3(x, 1.35, 0), 0.07, 0.06, wd, wd, 6, 1)
				a.box(Vector3(0, 0.5, 0), Vector3(3.0, 0.1, 0.06), wd.lightened(0.05))
				a.box(Vector3(0, 1.05, 0), Vector3(3.0, 0.1, 0.06), wd.lightened(0.05))
			"spikes":
				a.tube(Vector3(-1.2, 0.15, 0.2), Vector3(1.2, 0.15, 0.2), 0.12, 0.12, wd, wd, 6, 1)
				for i in range(6):
					var x2 := -1.0 + i * 0.4
					a.tube(Vector3(x2, 0.0, 0.25), Vector3(x2, 1.0, -0.35), 0.06, 0.005, wd, wd.lightened(0.2), 6, 1)
			"claim_flag":
				a.tube(Vector3(0, -0.2, 0), Vector3(0, 3.2, 0), 0.05, 0.04, wd, wd, 6, 1)
				a.blob(Vector3(0, 3.22, 0), Vector3(0.07, 0.07, 0.07), Color(0.8, 0.65, 0.2), 0.0, 1.0, 3, 6)
				b.quad(Vector3(0.55, 2.7, 0), Vector3(0, 0, -1), Vector3.UP, 1.0, 0.7, Color(0.7, 0.15, 0.15))
				b.quad(Vector3(0.55, 2.7, 0.005), Vector3(0, 0, 1), Vector3.UP, 1.0, 0.7, Color(0.6, 0.12, 0.12))
				m2 = MeshFactory.mat("cloth")
	var mesh := MeshBuilder.commit([a, b], [m1, m2])
	var r := {"mesh": mesh, "shapes": shapes}
	_mesh_cache[def_id] = r
	return r

func _box(mb: MeshBuilder, shapes: Array, center: Vector3, size: Vector3, col: Color) -> void:
	mb.box(center, size, col)
	shapes.append([_box_shape(size), Transform3D(Basis(), center)])

func _box_shape(size: Vector3) -> BoxShape3D:
	var k := "%.2f_%.2f_%.2f" % [size.x, size.y, size.z]
	if _shape_cache.has(k):
		return _shape_cache[k]
	var s := BoxShape3D.new()
	s.size = size
	_shape_cache[k] = s
	return s

func piece_mesh(def_id: String) -> Mesh:
	return _geo(def_id)["mesh"]

func build_visual(p: BuildPiece) -> void:
	var g := _geo(p.def_id)
	var d: Dictionary = p.def
	var mi := MeshInstance3D.new()
	mi.mesh = g["mesh"]
	mi.visibility_range_end = 260.0 if d.get("kind", "") == "grid" else 120.0
	if d.get("slot", "") == "door":
		var pivot := Node3D.new()
		pivot.position = Vector3(-0.48, 0, 0)
		p.add_child(pivot)
		pivot.add_child(mi)
		p.door_pivot = pivot
		var cs := CollisionShape3D.new()
		cs.shape = g["shapes"][0][0]
		cs.position = Vector3(0.0, 1.08, 0)
		p.add_child(cs)
		p.door_cs = cs
	else:
		p.add_child(mi)
		for s in g["shapes"]:
			var cs2 := CollisionShape3D.new()
			cs2.shape = s[0]
			cs2.transform = s[1]
			p.add_child(cs2)
	# مؤثرات
	if d.get("station", "") == "campfire" or p.def_id == "torch_stand":
		p.fire_fx = _make_fire(0.6 if p.def_id == "campfire" else 0.25)
		p.fire_fx.position = Vector3(0, 0.15 if p.def_id == "campfire" else 1.7, 0)
		p.add_child(p.fire_fx)
		p.light = OmniLight3D.new()
		p.light.light_color = Color(1.0, 0.6, 0.28)
		p.light.omni_range = 10.0 if p.def_id == "campfire" else 8.0
		p.light.light_energy = 1.6
		p.light.position = Vector3(0, 0.8 if p.def_id == "campfire" else 1.9, 0)
		p.light.shadow_enabled = false
		p.add_child(p.light)
		p.set_process(true)
	if d.has("light") and p.def_id == "crystal_lamp":
		p.light = OmniLight3D.new()
		p.light.light_color = d["light"]
		p.light.omni_range = d.get("light_range", 12.0)
		p.light.light_energy = 1.4
		p.light.position = Vector3(0, 1.6, 0)
		p.add_child(p.light)
		p.set_process(true)

func _make_fire(size: float) -> GPUParticles3D:
	var f := GPUParticles3D.new()
	f.amount = 22
	f.lifetime = 0.8
	f.local_coords = false
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = size * 0.35
	pm.direction = Vector3(0, 1, 0)
	pm.spread = 12.0
	pm.initial_velocity_min = 0.6
	pm.initial_velocity_max = 1.4
	pm.gravity = Vector3(0, 0.8, 0)
	pm.scale_min = 0.7
	pm.scale_max = 1.3
	var grad := Gradient.new()
	grad.set_color(0, Color(1.0, 0.85, 0.4, 1.0))
	grad.set_color(1, Color(0.8, 0.15, 0.02, 0.0))
	var gt := GradientTexture1D.new()
	gt.gradient = grad
	pm.color_ramp = gt
	f.process_material = pm
	var q := QuadMesh.new()
	q.size = Vector2(size, size * 1.3)
	q.material = MeshFactory.mat("flame")
	f.draw_pass_1 = q
	return f

# ------------------------------------------------------------------
# التخطيط على الشبكة
func _gkey(slot: String, hx: int, j: int, hz: int) -> String:
	return "%s:%d:%d:%d" % [slot, hx, j, hz]

func _has(b: Dictionary, k: String) -> bool:
	return b["cells"].has(k) and is_instance_valid(b["cells"][k])

func _building_near(p: Vector3, r: float) -> Dictionary:
	var best := {}
	var bd := r
	for b in buildings:
		for k in b["cells"]:
			var pc = b["cells"][k]
			if not is_instance_valid(pc):
				continue
			var d := Vector2(pc.global_position.x - p.x, pc.global_position.z - p.z).length()
			if d < bd and absf(pc.global_position.y - p.y) < 14.0:
				bd = d
				best = b
	return best

func supported(b: Dictionary, slot: String, part: String, hx: int, j: int, hz: int) -> bool:
	match slot:
		"c":
			if part == "foundation":
				return true
			for e in [[hx - 1, hz], [hx + 1, hz], [hx, hz - 1], [hx, hz + 1]]:
				if _has(b, _gkey("e", e[0], j - 1, e[1])):
					return true
			for c in [[hx - 2, hz], [hx + 2, hz], [hx, hz - 2], [hx, hz + 2]]:
				if _has(b, _gkey("c", c[0], j, c[1])):
					return true
			return false
		"e":
			var cells := [[hx - 1, hz], [hx + 1, hz]] if hx % 2 != 0 else [[hx, hz - 1], [hx, hz + 1]]
			for c in cells:
				if _has(b, _gkey("c", c[0], j, c[1])):
					return true
			if j > 0 and _has(b, _gkey("e", hx, j - 1, hz)):
				return true
			return false
		"r":
			for e in [[hx - 1, hz], [hx + 1, hz], [hx, hz - 1], [hx, hz + 1]]:
				if _has(b, _gkey("e", e[0], j - 1, e[1])):
					return true
			for c in [[hx - 2, hz], [hx + 2, hz], [hx, hz - 2], [hx, hz + 2]]:
				if _has(b, _gkey("r", c[0], j, c[1])):
					return true
			return _has(b, _gkey("c", hx, j, hz))
		"s":
			return _has(b, _gkey("c", hx, j, hz))
		"d":
			var k := _gkey("e", hx, j, hz)
			return _has(b, k) and b["cells"][k].def.get("part", "") == "doorway"
	return false

## يعيد خطة الوضع: {ok, xf, reason, b, key, g}
func plan(def_id: String, hit_pos: Vector3, hit_normal: Vector3, yaw: float, rot_idx: int) -> Dictionary:
	var d := BuildDB.get_piece(def_id)
	if d.is_empty():
		return {"ok": false, "reason": "?"}
	var res: Dictionary
	if d["kind"] == "grid":
		res = _plan_grid(d, hit_pos, yaw, rot_idx)
	else:
		res = _plan_free(d, hit_pos, hit_normal, yaw + rot_idx * deg_to_rad(15.0))
	if res.get("ok", false):
		var p: Node = world.player
		if not p.inventory.has_all(d["cost"]):
			res["ok"] = false
			res["reason"] = "تنقصك المواد: " + BuildDB.cost_text(def_id)
		elif p.inventory.count("hammer") == 0:
			res["ok"] = false
			res["reason"] = "تحتاج مطرقة البناء في حقيبتك"
	return res

func _plan_grid(d: Dictionary, aim: Vector3, yaw: float, rot_idx: int) -> Dictionary:
	var slot_map := {"cell": "c", "edge": "e", "roof": "r", "stairs": "s", "door": "d"}
	var slot: String = slot_map.get(d["slot"], "c")
	var part: String = d.get("part", "")
	var b := _building_near(aim, 5.5)
	if b.is_empty():
		if part != "foundation":
			return {"ok": false, "reason": "ابدأ بوضع أساس، ثم ابنِ الجدران عليه"}
		var gy: float = world.gen.height_at(aim.x, aim.z)
		var snapped_yaw := snappedf(yaw, deg_to_rad(15.0))
		var org := Transform3D(Basis(Vector3.UP, snapped_yaw), Vector3(aim.x, gy + 0.3, aim.z))
		var chk := _check_foundation(org)
		if chk != "":
			return {"ok": false, "reason": chk, "xf": org}
		return {"ok": true, "xf": org, "b": -1, "key": _gkey("c", 0, 0, 0), "g": ["c", part, 0, 0, 0], "origin": org}
	var org2: Transform3D = b["origin"]
	var lp := org2.affine_inverse() * aim
	var cx := int(round(lp.x / C))
	var cz := int(round(lp.z / C))
	var hx := cx * 2
	var hz := cz * 2
	var j := 0
	var basis := Basis()
	match slot:
		"c":
			j = 0 if part == "foundation" else maxi(1, int(round((lp.y + 0.6) / 3.0)))
		"e", "d":
			var fx := lp.x / C - cx
			var fz := lp.z / C - cz
			if absf(fx) > absf(fz):
				hx = cx * 2 + (1 if fx > 0.0 else -1)
				basis = Basis(Vector3.UP, PI / 2.0)
			else:
				hz = cz * 2 + (1 if fz > 0.0 else -1)
			j = maxi(0, int(floor((lp.y + 0.4) / 3.0)))
		"r":
			j = maxi(1, int(round((lp.y + 0.4) / 3.0)))
			basis = Basis(Vector3.UP, rot_idx * PI / 2.0)
		"s":
			j = maxi(0, int(floor((lp.y + 0.4) / 3.0)))
			basis = Basis(Vector3.UP, rot_idx * PI / 2.0)
	var local := Transform3D(basis, Vector3(hx * C * 0.5, j * 3.0, hz * C * 0.5))
	var xf := org2 * local
	var key := _gkey(slot, hx, j, hz)
	var res := {"ok": false, "xf": xf, "b": b["id"], "key": key, "g": [slot, part, hx, j, hz]}
	if _has(b, key):
		res["reason"] = "المكان مشغول"
		return res
	if not supported(b, slot, part, hx, j, hz):
		res["reason"] = "لا يوجد دعم إنشائي هنا (تحتاج أساساً أو جداراً أسفلها)"
		return res
	if part == "foundation":
		var chk := _check_foundation(xf)
		if chk != "":
			res["reason"] = chk
			return res
	elif slot == "e" or slot == "c":
		if _overlaps_resources(xf, Vector3(2.8, 2.6, 0.3) if slot == "e" else Vector3(2.8, 0.3, 2.8), Vector3(0, 1.5, 0) if slot == "e" else Vector3(0, -0.1, 0)):
			res["reason"] = "يوجد عائق (شجرة أو صخرة)"
			return res
	res["ok"] = true
	return res

func _check_foundation(xf: Transform3D) -> String:
	var top := xf.origin.y
	for o in [Vector3(0, 0, 0), Vector3(1.4, 0, 1.4), Vector3(-1.4, 0, 1.4), Vector3(1.4, 0, -1.4), Vector3(-1.4, 0, -1.4)]:
		var wp = xf * o
		var h: float = world.gen.height_at(wp.x, wp.z)
		if h > top + 0.5:
			return "الأرض مرتفعة جداً هنا"
		if h < top - 3.3:
			return "الأرض منخفضة جداً هنا"
		if h < -0.2:
			return "لا يمكن البناء في الماء"
	if _overlaps_resources(xf, Vector3(2.8, 2.0, 2.8), Vector3(0, -0.8, 0)):
		return "يوجد عائق (شجرة أو صخرة)"
	return ""

func _overlaps_resources(xf: Transform3D, size: Vector3, off: Vector3) -> bool:
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = _box_shape(size)
	q.transform = xf * Transform3D(Basis(), off)
	q.collision_mask = 8
	return not get_world_3d().direct_space_state.intersect_shape(q, 1).is_empty()

func _plan_free(d: Dictionary, pos: Vector3, normal: Vector3, yaw: float) -> Dictionary:
	var xf := Transform3D(Basis(Vector3.UP, yaw), pos)
	var res := {"ok": false, "xf": xf, "b": -2, "key": ""}
	if normal.y < 0.72:
		res["reason"] = "السطح مائل جداً"
		return res
	if pos.y < 0.05 and world.gen.height_at(pos.x, pos.z) < 0.05:
		res["reason"] = "لا يمكن البناء في الماء"
		return res
	var sz: Vector3 = d.get("size", Vector3.ONE)
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = _box_shape(sz * 0.92)
	q.transform = xf * Transform3D(Basis(), Vector3(0, sz.y * 0.5 + 0.08, 0))
	q.collision_mask = 4 | 8 | 32 | 2
	if not get_world_3d().direct_space_state.intersect_shape(q, 1).is_empty():
		res["reason"] = "يوجد عائق في المكان"
		return res
	res["ok"] = true
	return res

func place(def_id: String, pl: Dictionary, owner := "player", pay := true) -> BuildPiece:
	var d := BuildDB.get_piece(def_id)
	if pay:
		var p: Node = world.player
		if not p.inventory.remove_needs(d["cost"]):
			return null
		p.stats.add_skill_xp("building", 2.0)
	var piece := BuildPiece.new()
	add_child(piece)
	piece.global_transform = pl["xf"]
	piece.setup(self, def_id, owner)
	if d["kind"] == "grid":
		var b: Dictionary
		if int(pl["b"]) == -1:
			b = {"id": _next_building_id(), "origin": pl["origin"], "cells": {}}
			buildings.append(b)
		else:
			b = _building_by_id(int(pl["b"]))
		if b.is_empty():
			piece.queue_free()
			return null
		piece.b_id = b["id"]
		piece.key = pl["key"]
		piece.set_meta("g", pl["g"])
		b["cells"][pl["key"]] = piece
		if d.get("slot", "") == "door":
			var k: String = pl["key"]
			var ek := "e" + k.substr(1)
			if _has(b, ek):
				b["cells"][ek].set_meta("door", piece)
	if owner == "player":
		pieces.append(piece)
		if pay:
			Sfx.play("build", piece.global_position)
			world.fx_burst(piece.global_position + Vector3(0, 0.5, 0), Color(0.7, 0.6, 0.45))
	return piece

func _next_building_id() -> int:
	var m := 0
	for b in buildings:
		m = maxi(m, b["id"] + 1)
	return m

func _building_by_id(id: int) -> Dictionary:
	for b in buildings:
		if b["id"] == id:
			return b
	return {}

func demolish(piece: BuildPiece, refund := true) -> void:
	if not is_instance_valid(piece) or piece.owner_id != "player":
		return
	if refund:
		var out := []
		for k in piece.def["cost"]:
			var n := int(floor(piece.def["cost"][k] * 0.5))
			if n > 0:
				out.append([k, n])
		world.player.receive_items(out, piece.global_position)
	if piece.inventory != null and not piece.inventory.is_empty():
		var items := []
		for s in piece.inventory.slots:
			if s != null:
				items.append(s.duplicate())
		world.spawn_loot(piece.global_position + Vector3(0, 0.3, 0), items, "محتويات " + piece.display_name())
	var b := _building_by_id(piece.b_id)
	pieces.erase(piece)
	Sfx.play("chop", piece.global_position)
	world.fx_burst(piece.global_position + Vector3(0, 0.8, 0), Color(0.6, 0.5, 0.4))
	if not b.is_empty():
		b["cells"].erase(piece.key)
		piece.queue_free()
		_collapse(b)
		if b["cells"].is_empty():
			buildings.erase(b)
	else:
		piece.queue_free()

func _collapse(b: Dictionary) -> void:
	var changed := true
	var guard := 0
	while changed and guard < 50:
		guard += 1
		changed = false
		for k in b["cells"].keys():
			var pc = b["cells"][k]
			if not is_instance_valid(pc) or pc.is_queued_for_deletion():
				b["cells"].erase(k)
				continue
			var g: Array = pc.get_meta("g", [])
			if g.is_empty():
				continue
			if not supported(b, g[0], g[1], g[2], g[3], g[4]):
				b["cells"].erase(k)
				pieces.erase(pc)
				world.fx_burst(pc.global_position + Vector3(0, 1, 0), Color(0.6, 0.5, 0.4))
				pc.queue_free()
				changed = true
	if guard > 1:
		Game.notify("انهارت أجزاء غير مدعومة من المبنى", Color(1, 0.7, 0.4))

# ------------------------------------------------------------------
func player_storages() -> Array:
	var out := []
	for p in pieces:
		if is_instance_valid(p) and p.inventory != null and p.owner_id == "player":
			out.append(p)
	return out

func random_player_storage():
	var s := player_storages()
	return s[randi() % s.size()] if not s.is_empty() else null

func settlement_chest(faction: String):
	var c = settlement_chests.get(faction)
	return c if c != null and is_instance_valid(c) else null

func settlement_chest_near(pos: Vector3, r: float, exclude: String):
	for f in settlement_chests:
		if f == exclude:
			continue
		var c = settlement_chests[f]
		if is_instance_valid(c) and c.global_position.distance_to(pos) < r and not c.inventory.is_empty():
			return c
	return null

func owner_name(id: String) -> String:
	if id == "player":
		return "أنت"
	for s in world.ai.settlements:
		if s["id"] == id:
			return s["name"]
	return id

func station_near(pos: Vector3, kind: String, r := 4.5) -> bool:
	if kind == "hand":
		return true
	for p in get_children():
		if p is BuildPiece and p.is_station(kind) and p.global_position.distance_to(pos) < r:
			return true
	return false

func heat_at(pos: Vector3) -> float:
	var h := 0.0
	for p in get_children():
		if p is BuildPiece:
			var hv: float = p.provides_heat()
			if hv > 0.0:
				var d: float = p.global_position.distance_to(pos)
				if d < 6.0:
					h += hv * (1.0 - d / 6.0)
	return h

func shelter_quality(pos: Vector3) -> float:
	var space := get_world_3d().direct_space_state
	var up := PhysicsRayQueryParameters3D.create(pos + Vector3(0, 1.0, 0), pos + Vector3(0, 10.0, 0), 32)
	var hit := space.intersect_ray(up)
	if hit.is_empty():
		return 0.0
	var roof_insul := 0.5
	if hit["collider"] is BuildPiece:
		roof_insul = hit["collider"].def.get("insul", 0.5)
	var walls := 0
	var insul_sum := 0.0
	for i in range(4):
		var a := TAU * i / 4.0
		var q := PhysicsRayQueryParameters3D.create(pos + Vector3(0, 1.2, 0), pos + Vector3(cos(a), 0, sin(a)) * 6.0 + Vector3(0, 1.2, 0), 32)
		var h2 := space.intersect_ray(q)
		if not h2.is_empty():
			walls += 1
			if h2["collider"] is BuildPiece:
				insul_sum += h2["collider"].def.get("insul", 0.5)
	return clampf(0.35 * roof_insul + 0.65 * (insul_sum / 4.0), 0.0, 1.0)

func in_claim(pos: Vector3) -> bool:
	for p in pieces:
		if is_instance_valid(p) and p.def.has("claim") and p.global_position.distance_to(pos) < p.def["claim"]:
			return true
	return false

func update_crop_visual(p: BuildPiece) -> void:
	if p.crop_node:
		p.crop_node.queue_free()
		p.crop_node = null
	if p.crop.is_empty():
		return
	var n := Node3D.new()
	p.add_child(n)
	p.crop_node = n
	var mk := {"wheat": "tall_grass", "potato": "potato_plant", "cotton": "cotton"}.get(p.crop["t"], "tall_grass")
	var g: float = clampf(p.crop["g"], 0.08, 1.0)
	for i in range(4):
		for jj in range(2):
			var mi := MeshInstance3D.new()
			mi.mesh = MeshFactory.get_mesh(mk)
			mi.position = Vector3(-0.75 + i * 0.5, 0.25, -0.45 + jj * 0.9)
			mi.scale = Vector3.ONE * (0.35 + g * 0.55)
			mi.rotation.y = i * 1.3 + jj
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			n.add_child(mi)
	p.set_meta("crop_g", g)

func tick(dt: float) -> void:
	_tick_t += dt
	_spike_t += dt
	if _spike_t > 0.5:
		_spike_t = 0.0
		for p in pieces:
			if is_instance_valid(p) and p.def.get("spikes", false):
				for a in world.ai.animals:
					if is_instance_valid(a) and not a.dead and a.sp.get("pred", false) and a.global_position.distance_to(p.global_position) < 1.8:
						a.take_damage(6.0, null)
				for n in world.ai.active_npcs:
					if is_instance_valid(n) and not n.dead and n.hostile_to_player and n.global_position.distance_to(p.global_position) < 1.8:
						n.take_damage(5.0, null)
	if _tick_t < 4.0:
		return
	_tick_t = 0.0
	var now: float = world.total_hours()
	if _last_hours < 0.0:
		_last_hours = now
	var dh := now - _last_hours
	_last_hours = now
	var raining: bool = world.sky.rain > 0.3 and not world.sky.snowing
	for p in get_children():
		if not (p is BuildPiece):
			continue
		if p.def.get("farm", false):
			var before: float = p.get_meta("crop_g", 0.0)
			p.farm_tick(dh, raining)
			if not p.crop.is_empty() and absf(p.crop["g"] - before) > 0.08:
				update_crop_visual(p)
		elif p.def.get("collector", false) and raining:
			p.water = minf(10.0, p.water + dh * 1.5 * world.sky.rain)

# ------------------------------------------------------------------
# المستوطنات
func spawn_settlement(s: Dictionary) -> void:
	var c: Vector3 = s["pos"]
	var kinds := []
	var stations := []
	match s["type"]:
		"village":
			kinds = ["hut", "hut", "hut", "stall", "log_seat", "log_seat"]
			stations = ["farm_plot", "farm_plot", "farm_plot", "workbench", "loom"]
		"camp":
			kinds = ["tent", "tent", "tent", "log_seat"]
			stations = ["tanning_rack", "workbench"]
		"oasis":
			kinds = ["mudhouse", "mudhouse", "mudhouse", "stall", "stall"]
			stations = ["cooking_pot", "loom"]
		"north":
			kinds = ["cabin", "cabin", "totem", "log_seat"]
			stations = ["tanning_rack", "cooking_pot"]
		"mine":
			kinds = ["tent", "cabin", "log_seat"]
			stations = ["furnace", "anvil", "workbench"]
		"bandit":
			kinds = ["tent_dark", "tent_dark", "tent_dark", "totem"]
			stations = ["spikes", "spikes", "spikes"]
	var n := kinds.size()
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(s["id"]) + world.seed_value
	for i in range(n):
		var ang := TAU * i / n + rng.randf_range(-0.2, 0.2)
		var rad := rng.randf_range(10.0, 13.0) if kinds[i] != "log_seat" else 3.2
		var p := c + Vector3(cos(ang), 0, sin(ang)) * rad
		p.y = world.gen.height_at(p.x, p.z) - 0.1
		var yaw := atan2(-(c.x - p.x), -(c.z - p.z)) + PI
		_static_struct(kinds[i], p, yaw)
	var fire := BuildPiece.new()
	add_child(fire)
	fire.global_position = Vector3(c.x, world.gen.height_at(c.x, c.z), c.z)
	fire.setup(self, "campfire", s["id"])
	fire.infinite_fuel = true
	settlement_fires[s["id"]] = fire
	var chest := BuildPiece.new()
	add_child(chest)
	var cp := c + Vector3(3.5, 0, 2.0)
	chest.global_position = Vector3(cp.x, world.gen.height_at(cp.x, cp.z), cp.z)
	chest.rotation.y = rng.randf() * TAU
	chest.setup(self, "large_chest" if s["type"] in ["oasis", "bandit"] else "wooden_chest", s["id"])
	settlement_chests[s["id"]] = chest
	_fill_chest(chest, s["type"], true)
	for i in range(stations.size()):
		var ang2 := TAU * (i + 0.5) / stations.size() + 0.3
		var p2 := c + Vector3(cos(ang2), 0, sin(ang2)) * 6.5
		var st := BuildPiece.new()
		add_child(st)
		st.global_position = Vector3(p2.x, world.gen.height_at(p2.x, p2.z), p2.z)
		st.rotation.y = ang2 + PI / 2.0
		st.setup(self, stations[i], s["id"])
		if stations[i] == "farm_plot":
			st.crop = {"t": ["wheat", "potato", "cotton"][i % 3], "g": rng.randf_range(0.2, 1.0), "w": 1.0, "f": false}
			update_crop_visual(st)

func _static_struct(kind: String, p: Vector3, yaw: float) -> void:
	var body := StaticBody3D.new()
	body.collision_layer = 32
	body.collision_mask = 0
	add_child(body)
	body.global_position = p
	body.rotation.y = yaw
	var mi := MeshInstance3D.new()
	mi.mesh = MeshFactory.get_mesh("struct_" + kind)
	mi.visibility_range_end = 320.0
	body.add_child(mi)
	var cs := CollisionShape3D.new()
	match kind:
		"hut":
			var cy := CylinderShape3D.new()
			cy.radius = 2.3
			cy.height = 4.0
			cs.shape = cy
			cs.position = Vector3(0, 2.0, 0)
		"tent", "tent_dark":
			cs.shape = _box_shape(Vector3(2.6, 2.0, 3.6))
			cs.position = Vector3(0, 1.0, 0)
		"mudhouse":
			cs.shape = _box_shape(Vector3(4.0, 3.0, 3.6))
			cs.position = Vector3(0, 1.5, 0)
		"cabin":
			cs.shape = _box_shape(Vector3(4.8, 3.2, 4.0))
			cs.position = Vector3(0, 1.6, 0)
		"stall":
			cs.shape = _box_shape(Vector3(2.6, 1.0, 1.0))
			cs.position = Vector3(0, 0.5, 0)
		"totem":
			var cy2 := CylinderShape3D.new()
			cy2.radius = 0.3
			cy2.height = 3.5
			cs.shape = cy2
			cs.position = Vector3(0, 1.7, 0)
		"log_seat":
			cs.shape = _box_shape(Vector3(1.8, 0.4, 0.45))
			cs.position = Vector3(0, 0.2, 0)
	body.add_child(cs)

func _fill_chest(chest: BuildPiece, type: String, initial: bool) -> void:
	var table := {
		"village": [["wheat", 5, 12], ["bread", 2, 5], ["potato", 4, 10], ["cloth", 1, 4], ["rope", 2, 6], ["wheat_seed", 3, 8], ["gold_coin", 3, 10]],
		"camp": [["raw_meat", 3, 6], ["hide", 2, 5], ["fur", 1, 3], ["arrow", 10, 20], ["leather", 1, 3], ["salted_meat", 1, 3]],
		"oasis": [["gold_coin", 10, 30], ["glass", 2, 6], ["salt", 4, 10], ["cloth", 3, 8], ["cactus_fruit", 3, 6], ["waterskin_clean", 1, 2], ["gemstone", 0, 1]],
		"north": [["fur", 2, 5], ["salted_meat", 2, 5], ["wood", 10, 20], ["leather", 1, 3], ["fur_hat", 0, 1]],
		"mine": [["iron_ore", 3, 8], ["copper_ore", 3, 8], ["coal", 5, 12], ["iron_ingot", 1, 4], ["copper_ingot", 1, 4], ["nails", 10, 30]],
		"bandit": [["gold_coin", 20, 60], ["iron_ingot", 2, 6], ["gemstone", 1, 2], ["steel_ingot", 0, 2], ["bandage", 2, 5], ["iron_sword", 0, 1], ["leather_jacket", 0, 1]],
	}
	for e in table.get(type, []):
		var n := randi_range(e[1], e[2])
		if not initial:
			n = int(ceil(n * 0.3))
		if n > 0 and chest.inventory.count(e[0]) < e[2]:
			chest.inventory.add(e[0], n)

func restock_settlements() -> void:
	for s in world.ai.settlements:
		var c = settlement_chest(s["id"])
		if c != null:
			_fill_chest(c, s["type"], false)

# ------------------------------------------------------------------
func to_data() -> Dictionary:
	var pl := []
	for p in pieces:
		if is_instance_valid(p) and p.owner_id == "player":
			pl.append(p.to_data())
	var bl := []
	for b in buildings:
		bl.append({"id": b["id"], "origin": BuildPiece._xf_arr(b["origin"])})
	var sc := {}
	for f in settlement_chests:
		var c = settlement_chests[f]
		if is_instance_valid(c):
			sc[f] = c.inventory.to_data()
	return {"pieces": pl, "buildings": bl, "schests": sc}

func from_data(d: Dictionary) -> void:
	buildings = []
	for b in d.get("buildings", []):
		buildings.append({"id": int(b["id"]), "origin": BuildPiece.arr_xf(b["origin"]), "cells": {}})
	for pd in d.get("pieces", []):
		var def_id: String = pd.get("def", "")
		if BuildDB.get_piece(def_id).is_empty():
			continue
		var piece := BuildPiece.new()
		add_child(piece)
		piece.global_transform = BuildPiece.arr_xf(pd["xf"])
		piece.setup(self, def_id, "player")
		piece.hp = float(pd.get("hp", piece.hp))
		piece.b_id = int(pd.get("b", -1))
		piece.key = str(pd.get("key", ""))
		piece.locked = bool(pd.get("lock", piece.locked))
		piece.fuel = float(pd.get("fuel", 0.0))
		piece.water = float(pd.get("water", 0.0))
		if pd.has("inv") and piece.inventory != null:
			piece.inventory.from_data(pd["inv"])
		if pd.has("crop"):
			var cr: Dictionary = pd["crop"]
			piece.crop = {"t": str(cr.get("t", "wheat")), "g": float(cr.get("g", 0.0)), "w": float(cr.get("w", 0.0)), "f": bool(cr.get("f", false))}
			update_crop_visual(piece)
		if bool(pd.get("open", false)):
			piece.toggle_door()
		pieces.append(piece)
		if piece.b_id >= 0 and piece.key != "":
			var b := _building_by_id(piece.b_id)
			if not b.is_empty():
				b["cells"][piece.key] = piece
				var parts := piece.key.split(":")
				piece.set_meta("g", [parts[0], piece.def.get("part", ""), int(parts[1]), int(parts[2]), int(parts[3])])

func load_settlement_chests(d: Dictionary) -> void:
	var sc: Dictionary = d.get("schests", {})
	for f in sc:
		var c = settlement_chest(f)
		if c != null:
			c.inventory.from_data(sc[f])
