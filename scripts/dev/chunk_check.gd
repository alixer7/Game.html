extends SceneTree
func _init():
	var wd := WorldData.new(); wd.load_all()
	var t := Terrain.new(); t.wd = wd
	for step in [16, 2]:
		var arr: Array = t._build_arrays(8, 3, step)
		var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
		var mx := -1
		for k in idx: mx = maxi(mx, k)
		print("step ", step, " verts ", v.size(), " idx ", idx.size(), " maxidx ", mx, " v0 ", v[0], " vlast-grid ", v[(128/step+1)*(128/step+1)-1])
	quit()
