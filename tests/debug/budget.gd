extends Node
## Debug: triangle/instance budget per scatter variant and per top-level group.

func _tris(m: Mesh) -> int:
	var t := 0
	for s in m.get_surface_count():
		var arr := m.surface_get_arrays(s)
		var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
		t += idx.size() / 3 if idx.size() > 0 else (arr[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() / 3
	return t

func _ready() -> void:
	var q := int(OS.get_cmdline_user_args()[0]) if OS.get_cmdline_user_args().size() > 0 else 2
	var root := Node3D.new()
	add_child(root)
	var tb := TrackBuilder.new()
	tb.load_track("res://data/timberfall.json")
	tb.build(root, q)
	var per := {}
	for n in root.find_children("*", "MultiMeshInstance3D", true, false):
		var mmi := n as MultiMeshInstance3D
		var key := String(mmi.name).split("_")[0] + ("_L1" if String(mmi.name).ends_with("L1") else "_L0")
		var mm := mmi.multimesh
		if not per.has(key):
			per[key] = {"inst": 0, "tris_each": _tris(mm.mesh), "cells": 0, "range": [mmi.visibility_range_begin, mmi.visibility_range_end]}
		per[key].inst += mm.instance_count
		per[key].cells += 1
	var keys := per.keys()
	keys.sort_custom(func(a, b): return per[a].inst * per[a].tris_each > per[b].inst * per[b].tris_each)
	for k in keys:
		print("%-14s inst=%6d tris_each=%5d total=%8d cells=%4d range=%s" % [k, per[k].inst, per[k].tris_each, per[k].inst * per[k].tris_each, per[k].cells, per[k].range])
	var groups := {}
	for n in root.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if mi.mesh == null:
			continue
		var g := String(mi.get_path()).split("/Track/")[1].split("/")[0] if String(mi.get_path()).contains("/Track/") else "other"
		groups[g] = groups.get(g, 0) + _tris(mi.mesh)
	print("static meshes by group: ", groups)
	get_tree().quit()
