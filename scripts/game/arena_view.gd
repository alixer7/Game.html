class_name ArenaView
extends Node3D
## Renders the arena shell, goals, boost pads, stands, sky and lights.

const FLOOR_SHADER := preload("res://shaders/floor.gdshader")
const RAMP_SHADER := preload("res://shaders/ramp.gdshader")
const WALL_SHADER := preload("res://shaders/wall.gdshader")
const NET_SHADER := preload("res://shaders/goal_net.gdshader")
const CROWD_SHADER := preload("res://shaders/crowd.gdshader")
const PAD_SHADER := preload("res://shaders/pad.gdshader")

var world: SimWorld
var crowd_mat: ShaderMaterial
var net_mats: Array[ShaderMaterial] = []
var goal_lights: Array[StandardMaterial3D] = []
var pad_nodes: Array = []
var sun: DirectionalLight3D
var env: Environment
var _excite := 0.0
var _goal_flash := [0.0, 0.0]


func build(w: SimWorld) -> void:
	world = w
	var surfs: Dictionary = w.arena_surfaces()
	_add_surface(surfs["floor"], _shader_mat(FLOOR_SHADER), "Floor")
	_add_surface(surfs["ramp"], _shader_mat(RAMP_SHADER), "Ramps")
	var wall_mat := _shader_mat(WALL_SHADER)
	_add_surface(surfs["wall"], wall_mat, "Walls")
	var top_mat := _shader_mat(WALL_SHADER)
	top_mat.set_shader_parameter("is_top", 1.0)
	_add_surface(surfs["top"], top_mat, "Top")
	_build_goals(surfs["goal"])
	_build_pads()
	_build_stands()
	_build_environment()


func _shader_mat(sh: Shader) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = sh
	return m


func _add_surface(s: ArenaGeo.Surf, mat: Material, nm: String) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = nm
	mi.mesh = ArenaGeo.to_array_mesh(s)
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	return mi


func _build_goals(goal_surf: ArenaGeo.Surf) -> void:
	# Split goal triangles per end so each net gets its own team colour.
	for team in range(2):
		var sgn := 1.0 if team == 0 else -1.0
		var s := ArenaGeo.Surf.new()
		for i in range(0, goal_surf.v.size(), 3):
			var cz := (goal_surf.v[i].z + goal_surf.v[i + 1].z + goal_surf.v[i + 2].z) / 3.0
			if cz * sgn > 0.0:
				for k in range(3):
					s.v.append(goal_surf.v[i + k])
					s.n.append(goal_surf.n[i + k])
					s.uv.append(goal_surf.uv[i + k])
		var m := _shader_mat(NET_SHADER)
		m.set_shader_parameter("team_color", Phys.team_color(team))
		net_mats.append(m)
		_add_surface(s, m, "GoalNet%d" % team)
		# Glowing frame
		var frame_mat := StandardMaterial3D.new()
		frame_mat.albedo_color = Phys.team_color(team)
		frame_mat.emission_enabled = true
		frame_mat.emission = Phys.team_color(team)
		frame_mat.emission_energy_multiplier = 2.5
		frame_mat.roughness = 0.3
		goal_lights.append(frame_mat)
		var g := Phys.GOAL_HALF_W
		var h := Phys.GOAL_H
		var z := sgn * Phys.HALF_L
		var t := 0.32
		for sx in [-1.0, 1.0]:
			_box(Vector3(sx * (g + t * 0.5), h * 0.5, z + sgn * t * 0.5), Vector3(t, h + t, t), frame_mat)
		_box(Vector3(0, h + t * 0.5, z + sgn * t * 0.5), Vector3(2.0 * g + 2.0 * t, t, t), frame_mat)
		# light strip framing the back of the goal
		_box(Vector3(0, h - 0.05, sgn * (Phys.HALF_L + Phys.GOAL_DEPTH - 0.05)), Vector3(2.0 * g, 0.1, 0.1), frame_mat)
		# Big team banner above the goal
		var banner := MeshInstance3D.new()
		var qm := QuadMesh.new()
		qm.size = Vector2(2.0 * g + 4.0, 2.2)
		banner.mesh = qm
		var bm := StandardMaterial3D.new()
		bm.albedo_color = Phys.team_color(team) * 0.6
		bm.emission_enabled = true
		bm.emission = Phys.team_color(team)
		bm.emission_energy_multiplier = 1.2
		banner.material_override = bm
		banner.position = Vector3(0, h + 2.4, z - sgn * 0.02)
		banner.rotation.y = 0.0 if sgn < 0.0 else PI
		add_child(banner)


func _box(pos: Vector3, size: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = mat
	mi.position = pos
	add_child(mi)
	return mi


func _build_pads() -> void:
	var base_mat := StandardMaterial3D.new()
	base_mat.albedo_color = Color(0.12, 0.13, 0.16)
	base_mat.metallic = 0.7
	base_mat.roughness = 0.35
	var orb_mat := StandardMaterial3D.new()
	orb_mat.albedo_color = Color(1.0, 0.6, 0.1)
	orb_mat.emission_enabled = true
	orb_mat.emission = Color(1.0, 0.55, 0.08)
	orb_mat.emission_energy_multiplier = 3.0
	for pad in world.pads:
		var root := Node3D.new()
		root.position = pad.pos
		add_child(root)
		var size := 3.8 if pad.big else 2.3
		var base := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = size * 0.42
		cm.bottom_radius = size * 0.46
		cm.height = 0.06
		cm.radial_segments = 24
		base.mesh = cm
		base.material_override = base_mat
		base.position.y = 0.02
		root.add_child(base)
		var glow := MeshInstance3D.new()
		var qm := QuadMesh.new()
		qm.size = Vector2(size, size)
		qm.orientation = PlaneMesh.FACE_Y
		glow.mesh = qm
		var gm := _shader_mat(PAD_SHADER)
		gm.set_shader_parameter("big", 1.0 if pad.big else 0.0)
		glow.material_override = gm
		glow.position.y = 0.07
		glow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(glow)
		var orb: MeshInstance3D = null
		if pad.big:
			orb = MeshInstance3D.new()
			var sm := SphereMesh.new()
			sm.radius = 0.5
			sm.height = 1.0
			sm.radial_segments = 16
			sm.rings = 8
			orb.mesh = sm
			orb.material_override = orb_mat
			orb.position.y = 1.1
			orb.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			root.add_child(orb)
		pad_nodes.append({"root": root, "mat": gm, "orb": orb, "on": 1.0})


func _offset_poly(pts: PackedVector2Array, d: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	var n := pts.size()
	for i in range(n):
		var a := pts[(i + n - 1) % n]
		var b := pts[i]
		var c := pts[(i + 1) % n]
		var e1 := (b - a).normalized()
		var e2 := (c - b).normalized()
		var n1 := Vector2(e1.y, -e1.x)
		var n2 := Vector2(e2.y, -e2.x)
		out.append(b + (n1 + n2) * d / (1.0 + n1.dot(n2)))
	return out


func _build_stands() -> void:
	var W := Phys.HALF_W
	var L := Phys.HALF_L
	var C := Phys.CHAMFER
	var outer := PackedVector2Array([Vector2(W, -(L - C)), Vector2(W, L - C), Vector2(W - C, L),
		Vector2(-(W - C), L), Vector2(-W, L - C), Vector2(-W, -(L - C)), Vector2(-(W - C), -L), Vector2(W - C, -L)])
	var tiers := [[11.0, 1.5], [44.0, 30.0]]
	var inner := _offset_poly(outer, tiers[0][0])
	var outr := _offset_poly(outer, tiers[1][0])
	var y0: float = tiers[0][1]
	var y1: float = tiers[1][1]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var u := 0.0
	for i in range(8):
		var a := inner[i]
		var b := inner[(i + 1) % 8]
		var c := outr[(i + 1) % 8]
		var d := outr[i]
		var len_in := a.distance_to(b)
		var slope := Vector2((a + b) * 0.5).distance_to((c + d) * 0.5)
		var vlen := sqrt(slope * slope + (y1 - y0) * (y1 - y0))
		var len_out := c.distance_to(d)
		var pa := Vector3(a.x, y0, a.y)
		var pb := Vector3(b.x, y0, b.y)
		var pc := Vector3(c.x, y1, c.y)
		var pd := Vector3(d.x, y1, d.y)
		var ua := Vector2(u, 0)
		var ub := Vector2(u + len_in, 0)
		var uc := Vector2(u + len_in * 0.5 + len_out * 0.5, vlen)
		var ud := Vector2(u + len_in * 0.5 - len_out * 0.5, vlen)
		var nrm := (pb - pa).cross(pd - pa).normalized()
		if nrm.y < 0.0:
			nrm = -nrm
		for v in [[pa, ua], [pb, ub], [pc, uc], [pa, ua], [pc, uc], [pd, ud]]:
			st.set_normal(nrm)
			st.set_uv(v[1])
			st.add_vertex(v[0])
		u += len_in
	var stands := MeshInstance3D.new()
	stands.mesh = st.commit()
	crowd_mat = _shader_mat(CROWD_SHADER)
	stands.material_override = crowd_mat
	stands.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	stands.name = "Stands"
	add_child(stands)

	# Dark concrete ground and front barrier
	var ground := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(320, 320)
	ground.mesh = pm
	var gmat := StandardMaterial3D.new()
	gmat.albedo_color = Color(0.035, 0.04, 0.05)
	gmat.roughness = 0.95
	ground.material_override = gmat
	ground.position.y = -0.6
	add_child(ground)

	var barrier_mat := StandardMaterial3D.new()
	barrier_mat.albedo_color = Color(0.05, 0.06, 0.09)
	barrier_mat.emission_enabled = true
	barrier_mat.emission = Color(0.2, 0.5, 1.0)
	barrier_mat.emission_energy_multiplier = 0.25
	# Roof ring with light strips
	var roof_in := _offset_poly(outer, 26.0)
	var roof_out := _offset_poly(outer, 50.0)
	var rst := SurfaceTool.new()
	rst.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in range(8):
		var a := roof_in[i]
		var b := roof_in[(i + 1) % 8]
		var c := roof_out[(i + 1) % 8]
		var d := roof_out[i]
		var yy := 40.0
		for p in [a, b, c, a, c, d]:
			rst.set_normal(Vector3.DOWN)
			rst.add_vertex(Vector3(p.x, yy, p.y))
	var roof := MeshInstance3D.new()
	roof.mesh = rst.commit()
	var roof_mat := StandardMaterial3D.new()
	roof_mat.albedo_color = Color(0.03, 0.035, 0.05)
	roof_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	roof.material_override = roof_mat
	add_child(roof)
	# Floodlight rigs hanging under the roof
	var lamp_mat := StandardMaterial3D.new()
	lamp_mat.albedo_color = Color(1, 1, 1)
	lamp_mat.emission_enabled = true
	lamp_mat.emission = Color(1.0, 0.95, 0.85)
	lamp_mat.emission_energy_multiplier = 6.0
	for i in range(8):
		var a := roof_in[i]
		var b := roof_in[(i + 1) % 8]
		for k in range(3):
			var p := a.lerp(b, (k + 1) / 4.0)
			var lamp := _box(Vector3(p.x, 39.4, p.y), Vector3(3.2, 0.5, 1.2), lamp_mat)
			lamp.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Front barrier below the stands
	var bst := SurfaceTool.new()
	bst.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in range(8):
		var a := inner[i]
		var b := inner[(i + 1) % 8]
		var nn := Vector3(-(b - a).normalized().y, 0, (b - a).normalized().x)
		for p in [[a, -0.6], [b, -0.6], [b, y0], [a, -0.6], [b, y0], [a, y0]]:
			bst.set_normal(nn)
			var pp: Vector2 = p[0]
			bst.add_vertex(Vector3(pp.x, p[1], pp.y))
	var barrier := MeshInstance3D.new()
	barrier.mesh = bst.commit()
	barrier_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	barrier.material_override = barrier_mat
	add_child(barrier)


func _build_environment() -> void:
	var we := WorldEnvironment.new()
	env = Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var sm := ProceduralSkyMaterial.new()
	sm.sky_top_color = Color(0.05, 0.08, 0.22)
	sm.sky_horizon_color = Color(0.55, 0.32, 0.45)
	sm.sky_curve = 0.12
	sm.ground_bottom_color = Color(0.02, 0.02, 0.04)
	sm.ground_horizon_color = Color(0.35, 0.22, 0.32)
	sm.sun_angle_max = 20.0
	sky.sky_material = sm
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.9
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 1.05
	env.tonemap_white = 6.0
	env.glow_enabled = true
	env.glow_intensity = 0.55
	env.glow_strength = 0.9
	env.glow_bloom = 0.04
	env.glow_hdr_threshold = 1.0
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_ADDITIVE
	env.set_glow_level(0, 0.0)
	env.set_glow_level(1, 1.0)
	env.set_glow_level(2, 0.6)
	env.set_glow_level(3, 0.4)
	env.set_glow_level(4, 0.2)
	env.adjustment_enabled = true
	env.adjustment_saturation = 1.12
	env.adjustment_contrast = 1.05
	we.environment = env
	add_child(we)

	sun = DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-62.0, 28.0, 0.0)
	sun.light_color = Color(1.0, 0.95, 0.88)
	sun.light_energy = 1.15
	sun.shadow_enabled = true
	sun.shadow_bias = 0.04
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	sun.directional_shadow_max_distance = 70.0
	sun.directional_shadow_fade_start = 0.85
	add_child(sun)


func set_quality(level: int) -> void:
	if sun:
		sun.shadow_enabled = level >= 1
		sun.directional_shadow_max_distance = 45.0 if level == 1 else 75.0
	if env:
		env.glow_enabled = level >= 1


func excite(amount: float) -> void:
	_excite = maxf(_excite, amount)


func flash_goal(team: int) -> void:
	_goal_flash[team] = 1.0


func _process(delta: float) -> void:
	if world == null:
		return
	var t := Time.get_ticks_msec() / 1000.0
	for i in range(pad_nodes.size()):
		var pn: Dictionary = pad_nodes[i]
		var target := 1.0 if world.pads[i].active else 0.0
		pn["on"] = move_toward(pn["on"], target, delta * 4.0)
		var mat: ShaderMaterial = pn["mat"]
		mat.set_shader_parameter("active", pn["on"])
		var orb: MeshInstance3D = pn["orb"]
		if orb:
			orb.visible = pn["on"] > 0.05
			var s: float = maxf(0.01, pn["on"])
			orb.scale = Vector3.ONE * s
			orb.position.y = 1.1 + sin(t * 2.0 + i) * 0.12
			orb.rotation.y = t * 1.5
	_excite = move_toward(_excite, 0.0, delta * 0.12)
	if crowd_mat:
		crowd_mat.set_shader_parameter("excitement", _excite)
	for team in range(2):
		_goal_flash[team] = move_toward(_goal_flash[team], 0.0, delta * 0.5)
		var f: float = _goal_flash[team]
		if team < net_mats.size():
			net_mats[team].set_shader_parameter("pulse", f * (0.6 + 0.4 * sin(t * 18.0)))
		if team < goal_lights.size():
			goal_lights[team].emission_energy_multiplier = 2.5 + f * 8.0 * (0.5 + 0.5 * sin(t * 14.0))
