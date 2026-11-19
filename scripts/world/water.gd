class_name Water
extends Node3D
## Sea, river, mountain lake and the waterfall (with mist).

var wd: WorldData
var quality := 1


func build(data: WorldData, q: int) -> void:
	wd = data
	quality = q
	var sea_mat := _mat(Color(0.10, 0.40, 0.44), Color(0.02, 0.11, 0.2), 1.0, 0.0, 9.0)
	var river_mat := _mat(Color(0.20, 0.38, 0.32), Color(0.05, 0.16, 0.16), 0.8, 1.3, 3.0)
	var lake_mat := _mat(Color(0.10, 0.36, 0.42), Color(0.02, 0.09, 0.16), 0.6, 0.0, 6.0)
	_sea(sea_mat)
	_river(river_mat)
	_lake(lake_mat)
	_waterfall()


func _mat(shallow: Color, deep: Color, waves: float, flow: float, clarity: float) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = load("res://shaders/water.gdshader")
	m.set_shader_parameter("shallow_color", Color(shallow.r, shallow.g, shallow.b))
	m.set_shader_parameter("deep_color", Color(deep.r, deep.g, deep.b))
	m.set_shader_parameter("wave_scale", waves)
	m.set_shader_parameter("flow_speed", flow)
	m.set_shader_parameter("clarity", clarity)
	m.set_shader_parameter("quality", mini(quality, 1))
	return m


func _sea(mat: Material) -> void:
	# fine grid near the coast, coarse further out (keeps vertex count small)
	var m := MeshAcc.new()
	var x0 := -6000.0
	var x1 := 6000.0
	var z0 := 900.0
	var z1 := 8000.0
	var nx := 60
	var nz := 30
	var rows := []
	for j in nz + 1:
		var tz := pow(float(j) / nz, 1.6)
		var z := lerpf(z0, z1, tz)
		var row := []
		for i in nx + 1:
			var x := lerpf(x0, x1, float(i) / nx)
			row.append(m.v(Vector3(x, 0.0, z), Vector3.UP, Vector2(x, z)))
		rows.append(row)
	for j in nz:
		for i in nx:
			m.quad(rows[j][i], rows[j][i + 1], rows[j + 1][i + 1], rows[j + 1][i], Vector3.UP)
	var mi := MeshInstance3D.new()
	mi.mesh = m.to_mesh(mat)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)


func _river(mat: Material) -> void:
	var r: Dictionary = wd.json.river
	var pts: Array = r.pts
	var hw: Array = r.hw
	var n := pts.size() / 3
	var m := MeshAcc.new()
	var rows := []
	var dist := 0.0
	var prev := Vector3.ZERO
	for k in n:
		var p := Vector3(pts[k * 3], pts[k * 3 + 1], pts[k * 3 + 2])
		if p.z < -1060.0:
			continue  # above the falls: part of the lake outlet, handled by the lake
		if k > 0 and rows.size() > 0:
			dist += p.distance_to(prev)
		prev = p
		var a := Vector3(pts[maxi(k - 1, 0) * 3], 0, pts[maxi(k - 1, 0) * 3 + 2])
		var b := Vector3(pts[mini(k + 1, n - 1) * 3], 0, pts[mini(k + 1, n - 1) * 3 + 2])
		var t := (b - a).normalized()
		var rt := t.cross(Vector3.UP).normalized()
		var w: float = float(hw[k]) + 4.0
		var y := p.y
		if p.z > 1250.0:
			y = minf(y, 0.0)
		var l := m.v(Vector3(p.x, y, p.z) - rt * w, Vector3.UP, Vector2(0.0, dist / 6.0))
		var rr := m.v(Vector3(p.x, y, p.z) + rt * w, Vector3.UP, Vector2(w * 2.0 / 6.0, dist / 6.0))
		rows.append([l, rr])
	for i in rows.size() - 1:
		m.quad(rows[i][0], rows[i][1], rows[i + 1][1], rows[i + 1][0], Vector3.UP)
	var mi := MeshInstance3D.new()
	mi.mesh = m.to_mesh(mat)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)


func _lake(mat: Material) -> void:
	var L: Dictionary = wd.json.lake
	var c := Vector3(L.x, L.h, L.z)
	var rad: float = L.r * 1.25
	var m := MeshAcc.new()
	var center := m.v(c, Vector3.UP)
	var ring := []
	var segs := 48
	for i in segs + 1:
		var a := TAU * i / segs
		ring.append(m.v(c + Vector3(cos(a) * rad, 0, sin(a) * rad), Vector3.UP))
	for i in segs:
		m.tri(center, ring[i], ring[i + 1], Vector3.UP)
	# outlet channel to the fall lip
	var wf: Dictionary = wd.json.waterfall
	var top := Vector3(wf.top[0], L.h, wf.top[2])
	var w := 13.0
	var a0 := m.v(Vector3(top.x - w, L.h, c.z + rad * 0.7), Vector3.UP)
	var a1 := m.v(Vector3(top.x + w, L.h, c.z + rad * 0.7), Vector3.UP)
	var b0 := m.v(Vector3(top.x - w * 0.7, L.h, top.z + 1.0), Vector3.UP)
	var b1 := m.v(Vector3(top.x + w * 0.7, L.h, top.z + 1.0), Vector3.UP)
	m.quad(a0, a1, b1, b0, Vector3.UP)
	var mi := MeshInstance3D.new()
	mi.mesh = m.to_mesh(mat)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)


func _waterfall() -> void:
	var wf: Dictionary = wd.json.waterfall
	var top := Vector3(wf.top[0], wf.top[1], wf.top[2])
	var bot := Vector3(wf.bottom[0], wf.bottom[1], wf.bottom[2])
	var width: float = wf.width
	var horiz := Vector3(bot.x - top.x, 0, bot.z - top.z)
	var dir := horiz.normalized()
	var rt := dir.cross(Vector3.UP).normalized()
	var drop := top.y - bot.y
	var m := MeshAcc.new()
	var rows := []
	var steps := 24
	for i in steps + 1:
		var t := float(i) / steps
		# ballistic arc: leaves the lip horizontally then falls
		var p := top + dir * horiz.length() * (0.25 * t + 0.75 * t * t) - Vector3(0, drop * t * t, 0)
		var hwid := width * 0.5 * (1.0 + t * 0.35)
		var tn := (dir * (0.25 + 1.5 * t) * horiz.length() - Vector3(0, 2.0 * drop * t, 0)).normalized()
		var nn := tn.cross(rt).normalized()
		if nn.dot(-dir) < 0:
			nn = -nn
		rows.append([m.v(p - rt * hwid, nn, Vector2(0, t)), m.v(p + rt * hwid, nn, Vector2(1, t))])
	for i in steps:
		m.quad(rows[i][0], rows[i][1], rows[i + 1][1], rows[i + 1][0], -dir)
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/waterfall.gdshader")
	var mi := MeshInstance3D.new()
	mi.mesh = m.to_mesh(mat)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	# mist at the plunge pool
	var mist := CPUParticles3D.new()
	mist.amount = 40 if quality > 0 else 16
	mist.lifetime = 4.0
	mist.preprocess = 4.0
	mist.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	mist.emission_box_extents = Vector3(width * 0.6, 1.0, 6.0)
	mist.direction = Vector3(0, 1, 0)
	mist.spread = 60.0
	mist.initial_velocity_min = 1.5
	mist.initial_velocity_max = 4.0
	mist.gravity = Vector3(0, 0.3, 0)
	mist.scale_amount_min = 6.0
	mist.scale_amount_max = 14.0
	var curve := Curve.new()
	curve.add_point(Vector2(0, 0.3))
	curve.add_point(Vector2(0.5, 1.0))
	curve.add_point(Vector2(1, 0.0))
	mist.scale_amount_curve = curve
	var qm := QuadMesh.new()
	qm.size = Vector2(1, 1)
	var pm := StandardMaterial3D.new()
	pm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	pm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	pm.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	pm.albedo_color = Color(1, 1, 1, 0.12)
	pm.albedo_texture = _soft_tex()
	pm.vertex_color_use_as_albedo = true
	qm.material = pm
	mist.mesh = qm
	mist.position = bot + dir * 2.0
	add_child(mist)


static var _soft: ImageTexture


static func _soft_tex() -> ImageTexture:
	if _soft:
		return _soft
	var s := 64
	var img := Image.create(s, s, false, Image.FORMAT_RGBA8)
	for y in s:
		for x in s:
			var d := Vector2(x - s * 0.5 + 0.5, y - s * 0.5 + 0.5).length() / (s * 0.5)
			var a := clampf(1.0 - d, 0.0, 1.0)
			img.set_pixel(x, y, Color(1, 1, 1, a * a))
	_soft = ImageTexture.create_from_image(img)
	return _soft
