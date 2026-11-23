extends Node
## Debug: triangle counts of the procedural scatter meshes per LOD.

func _tris(m: Mesh) -> int:
	if m == null:
		return 0
	var t := 0
	for s in m.get_surface_count():
		var a := m.surface_get_arrays(s)
		var idx: PackedInt32Array = a[Mesh.ARRAY_INDEX]
		t += (idx.size() / 3) if idx.size() > 0 else (a[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() / 3
	return t


func _ready() -> void:
	for s in [0, 1, 2]:
		var row := []
		for lod in 3:
			var t := MeshLib.broadleaf_tree(100, lod, s)
			var tot := 0
			for mb: MeshBuilder in [t.bark, t.leaves, t.get("cards")]:
				if mb:
					tot += mb.idx.size() / 3
			row.append(tot)
		print("broadleaf shape %d lods: %s" % [s, row])
	var prow := []
	for lod in 3:
		var p := MeshLib.pine_tree(200, lod)
		prow.append((p.bark.idx.size() + p.leaves.idx.size()) / 3)
	print("pine lods: ", prow)
	var brow := []
	for lod in 3:
		var b := MeshLib.birch_tree(300, lod)
		var tot: int = b.bark.idx.size() + b.leaves.idx.size() + (b.cards.idx.size() if b.get("cards") else 0)
		brow.append(tot / 3)
	print("birch lods: ", brow)
	for lod in 2:
		var bu := MeshLib.bush(400, lod, false)
		print("bush lod%d: %d" % [lod, (bu.leaves.idx.size() + (bu.cards.idx.size() if bu.get("cards") else 0)) / 3])
	print("grass clump: ", MeshLib.grass_clump(600, 7, 0.55).idx.size() / 3, " (x4 per instance)")
	print("rock lod0/1: ", MeshLib.rock(900, 0, 0).idx.size() / 3, " / ", MeshLib.rock(900, 0, 1).idx.size() / 3)
	get_tree().quit()
