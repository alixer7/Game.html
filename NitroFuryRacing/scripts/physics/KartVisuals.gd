extends Node3D

## Studio-Grade Reference-Matched v5.0 60FPS Crafted Wood/Brass Kart & Sculpted Character Rig.
## - Independent 4-Wheel Grounded Suspension Rig: all 4 chunky treaded rubber tires stay 100% glued
##   to the cobblestones via real 4-corner wheel contact offsets while the heavy chassis pitches, rolls,
##   and compresses independently above them!
## - Exact geometric tire rolling spin (`speed / wheel_radius`), drift tire camber & lateral sidewall squash!
## - Reference-Matched Dual-Color Electric-Blue + Golden-Orange Drift Friction Sparks erupting right at
##   the tire-to-road contact patch + thick swirling billowy dust clouds!
## - Twin Low Plasma-Core (electric blue) + Fiery Orange Exhaust Jets + 3D Expanding Sonic Shockwave Ring!

var _body_pivot: Node3D
var _wheels_root: Node3D
var _driver_pivot: Node3D
var _shadow_mesh: MeshInstance3D
var _exhaust_light: OmniLight3D
var _wheel_fl: Node3D
var _wheel_fr: Node3D
var _wheel_rl: Node3D
var _wheel_rr: Node3D
var _flame_l: MeshInstance3D
var _flame_r: MeshInstance3D
var _flame_core_l: MeshInstance3D
var _flame_core_r: MeshInstance3D
var _flame_mat: StandardMaterial3D
var _flame_core_mat: StandardMaterial3D
var _sonic_ring: MeshInstance3D
var _sonic_mat: StandardMaterial3D
var _collision_spark: MeshInstance3D
var _collision_spark_mat: StandardMaterial3D
# Dual-layer Tire Contact Drift Friction Sparks (Electric-Blue Arc + Golden-Orange Embers!)
var _spark_blue_l: MeshInstance3D
var _spark_blue_r: MeshInstance3D
var _spark_blue_mat: StandardMaterial3D
var _spark_gold_l: MeshInstance3D
var _spark_gold_r: MeshInstance3D
var _spark_gold_mat: StandardMaterial3D
var _tire_glow_l: MeshInstance3D
var _tire_glow_r: MeshInstance3D
var _tire_glow_mat: StandardMaterial3D
var _uturn_ring: MeshInstance3D
var _shield_mesh: MeshInstance3D
var _shield_mat: StandardMaterial3D
var _mask_orbit: Node3D
var _tnt_node: Node3D

# Zero-Allocation World-Space 3D Tire Skidmark MultiMesh Ring Buffer (Zero ImmediateMesh VBO stalls on Adreno GPUs!)
var _skid_mmi: MultiMeshInstance3D
var _skid_mm: MultiMesh
var _skid_cursor: int = 0
var _last_skid_l: Vector3 = Vector3.ZERO
var _last_skid_r: Vector3 = Vector3.ZERO
var _had_skid: bool = false
const SKID_POOL_SIZE := 48
var _dust_puffs: Array[Dictionary] = []
var _dust_timer: float = 0.0
var _is_ghost_kart: bool = false
var _is_player_kart: bool = false
var _racer_id: String = "blaze"

const WHEEL_RAD_FRONT := 0.43
const WHEEL_RAD_REAR := 0.56

var _wheel_spin_f: float = 0.0
var _wheel_spin_r: float = 0.0
var _visual_drift_yaw: float = 0.0
var _visual_roll: float = 0.0
var _visual_pitch: float = 0.0
var _boost_flash: float = 0.0
var _sonic_timer: float = 0.0
var _weapon_anim_timer: float = 0.0
var _impact_roll: float = 0.0
var _impact_pitch: float = 0.0
var _impact_spark_timer: float = 0.0
var _spinout_angle: float = 0.0
var _time: float = 0.0

static var _scene_cache: Dictionary = {}
static var _shadow_tex: ImageTexture = null
static var _smoke_tex: ImageTexture = null
static var _puff_mesh_shared: QuadMesh = null

static func _load_glb(path: String) -> Node3D:
	if not _scene_cache.has(path):
		var res = load(path)
		if res is PackedScene:
			_scene_cache[path] = res
		else:
			return null
	var ps: PackedScene = _scene_cache[path]
	return ps.instantiate() as Node3D

static func _get_shadow_texture() -> ImageTexture:
	if _shadow_tex != null:
		return _shadow_tex
	var img := Image.create(64, 64, false, Image.FORMAT_RGBA8)
	for y in range(64):
		for x in range(64):
			var u := (float(x) / 63.0) * 2.0 - 1.0
			var v := (float(y) / 63.0) * 2.0 - 1.0
			var d := sqrt(u * u * 1.08 + v * v * 0.85)
			var a := clampf(1.0 - smoothstep(0.28, 0.96, d), 0.0, 1.0) * 0.72
			img.set_pixel(x, y, Color(0.03, 0.02, 0.04, a))
	_shadow_tex = ImageTexture.create_from_image(img)
	return _shadow_tex

static func _get_smoke_texture() -> ImageTexture:
	if _smoke_tex != null:
		return _smoke_tex
	var img := Image.create(64, 64, false, Image.FORMAT_RGBA8)
	for y in range(64):
		for x in range(64):
			var u := (float(x) / 63.0) * 2.0 - 1.0
			var v := (float(y) / 63.0) * 2.0 - 1.0
			var d := sqrt(u * u + v * v)
			# Soft cloudy wisp falloff with zero harsh circle border!
			var ang := atan2(v, u)
			var wisp := 1.0 + 0.14 * sin(ang * 3.0) + 0.10 * cos(ang * 5.0 + 1.2)
			var a := pow(clampf(1.0 - smoothstep(0.12, 0.94 * wisp, d), 0.0, 1.0), 1.65)
			var shade := lerpf(0.84, 1.0, clampf(1.0 - d * 0.65, 0.0, 1.0))
			img.set_pixel(x, y, Color(shade, shade * 0.97, shade * 0.92, a))
	_smoke_tex = ImageTexture.create_from_image(img)
	return _smoke_tex

static func _get_puff_mesh() -> QuadMesh:
	if _puff_mesh_shared == null:
		_puff_mesh_shared = QuadMesh.new()
		_puff_mesh_shared.size = Vector2(0.85, 0.85)
	return _puff_mesh_shared

func build_kart(data: Dictionary, is_ghost: bool = false, is_player_controlled: bool = false) -> void:
	for c in get_children():
		c.queue_free()
	_skid_mmi = null
	_skid_mm = null
	_skid_cursor = 0
	_dust_puffs.clear()
	_had_skid = false
	_is_ghost_kart = is_ghost
	_is_player_kart = is_player_controlled
	_racer_id = str(data.get("id", "blaze"))

	var col_body: Color = data.get("body_color", Color(0.95, 0.35, 0.08))
	var col_accent: Color = data.get("accent_color", Color(0.14, 0.72, 0.66))
	var ear_style: String = str(data.get("ear_style", "fox"))

	# 0. Grounded Soft Radial Contact Shadow (Strict Layer Order: Road=0.00, Shadow=0.032, Skids=0.048!)
	if not is_ghost:
		_shadow_mesh = MeshInstance3D.new()
		var sp := PlaneMesh.new()
		sp.size = Vector2(2.85, 3.85)
		_shadow_mesh.mesh = sp
		_shadow_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var sh_m := StandardMaterial3D.new()
		sh_m.albedo_texture = _get_shadow_texture()
		sh_m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		sh_m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		sh_m.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
		_shadow_mesh.material_override = sh_m
		_shadow_mesh.position = Vector3(0.0, 0.032, 0.02)
		add_child(_shadow_mesh)

	# 1. INDEPENDENT 4-WHEEL GROUNDED SUSPENSION ROOT (Sibling of _body_pivot so tires STAY GLUED to road!)
	_wheels_root = Node3D.new()
	add_child(_wheels_root)
	_wheel_fl = _make_wheel_node(Vector3(-0.98, WHEEL_RAD_FRONT, -0.94), 0.86, col_accent, is_ghost)
	_wheel_fr = _make_wheel_node(Vector3(0.98, WHEEL_RAD_FRONT, -0.94), 0.86, col_accent, is_ghost)
	_wheel_rl = _make_wheel_node(Vector3(-1.04, WHEEL_RAD_REAR, 0.86), 1.12, col_accent, is_ghost)
	_wheel_rr = _make_wheel_node(Vector3(1.04, WHEEL_RAD_REAR, 0.86), 1.12, col_accent, is_ghost)
	_wheels_root.add_child(_wheel_fl)
	_wheels_root.add_child(_wheel_fr)
	_wheels_root.add_child(_wheel_rl)
	_wheels_root.add_child(_wheel_rr)

	# 2. HEAVY SUSPENDED WOOD/BRASS CHASSIS BODY PIVOT (Pitches, Rolls & Squats Above Wheels!)
	_body_pivot = Node3D.new()
	add_child(_body_pivot)

	var chassis := _load_glb("res://assets/models/kart_chassis.glb")
	if chassis:
		_body_pivot.add_child(chassis)
		_tint_kart_materials(chassis, col_body, col_accent, is_ghost)

	# 3. Expressive Sculpted Driver Rig (Red-Panda in Black Leather, Dino, Lynx, Retro Chrome Robot!)
	_driver_pivot = Node3D.new()
	_driver_pivot.position = Vector3(0.0, 0.02, 0.0)
	_body_pivot.add_child(_driver_pivot)
	var char_glb_path := "res://assets/models/char_blaze.glb"
	match ear_style:
		"dino": char_glb_path = "res://assets/models/char_apex.glb"
		"polar": char_glb_path = "res://assets/models/char_zippy.glb"
		"alien": char_glb_path = "res://assets/models/char_turbox.glb"
	var char_node := _load_glb(char_glb_path)
	if char_node:
		_driver_pivot.add_child(char_node)
		if is_ghost:
			_apply_ghost_material(char_node)

	# 4. Reference-Matched Low Twin Exhaust Plasma Flames (Electric-Blue Inner Core + Fiery Orange Tail!)
	_flame_mat = StandardMaterial3D.new()
	_flame_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_flame_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_flame_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_flame_mat.albedo_color = Color(1.0, 0.48, 0.08, 0.0)

	_flame_core_mat = StandardMaterial3D.new()
	_flame_core_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_flame_core_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_flame_core_mat.albedo_color = Color(0.28, 0.80, 1.0, 0.96)

	# Positioned directly at v5 low dual brushed-steel exhaust outlets: (±0.36, 0.46, +1.52)!
	_flame_l = _add_flame_cone(_body_pivot, Vector3(-0.36, 0.46, 2.02), 0.19, 1.18, _flame_mat)
	_flame_r = _add_flame_cone(_body_pivot, Vector3(0.36, 0.46, 2.02), 0.19, 1.18, _flame_mat)
	_flame_core_l = _add_flame_cone(_body_pivot, Vector3(-0.36, 0.46, 1.76), 0.125, 0.72, _flame_core_mat)
	_flame_core_r = _add_flame_cone(_body_pivot, Vector3(0.36, 0.46, 1.76), 0.125, 0.72, _flame_core_mat)

	# 3D Sonic Boom Shockwave Ring on Turbo Activation!
	_sonic_ring = MeshInstance3D.new()
	var s_torus := TorusMesh.new()
	s_torus.inner_radius = 0.50
	s_torus.outer_radius = 0.70
	s_torus.rings = 14
	s_torus.ring_segments = 8
	_sonic_ring.mesh = s_torus
	_sonic_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_sonic_mat = StandardMaterial3D.new()
	_sonic_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_sonic_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_sonic_mat.albedo_color = Color(1.0, 0.72, 0.14, 0.0)
	_sonic_ring.material_override = _sonic_mat
	_sonic_ring.position = Vector3(0.0, 0.48, 1.62)
	_sonic_ring.rotation_degrees.x = 90.0
	_sonic_ring.visible = false
	_body_pivot.add_child(_sonic_ring)

	# 3D Collision Spark Burst Star!
	_collision_spark = MeshInstance3D.new()
	var sp_m := SphereMesh.new()
	sp_m.radius = 0.45; sp_m.height = 0.90; sp_m.radial_segments = 8; sp_m.rings = 4
	_collision_spark.mesh = sp_m
	_collision_spark.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_collision_spark_mat = StandardMaterial3D.new()
	_collision_spark_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_collision_spark_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_collision_spark_mat.albedo_color = Color(1.0, 0.85, 0.20, 0.9)
	_collision_spark.material_override = _collision_spark_mat
	_collision_spark.visible = false
	_body_pivot.add_child(_collision_spark)

	if _is_player_kart and not is_ghost:
		_exhaust_light = OmniLight3D.new()
		_exhaust_light.position = Vector3(0.0, 0.55, 2.25)
		_exhaust_light.omni_range = 8.0
		_exhaust_light.light_energy = 0.0
		_exhaust_light.shadow_enabled = false
		_body_pivot.add_child(_exhaust_light)

	# 5. Reference-Matched Dual-Color Tire-to-Road Contact Friction Sparks (Mounted in _wheels_root at y=0.11m!)
	_spark_blue_mat = StandardMaterial3D.new()
	_spark_blue_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_spark_blue_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_spark_blue_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_spark_blue_mat.albedo_color = Color(0.28, 0.82, 1.0, 0.94)
	_spark_blue_l = _add_flame_cone(_wheels_root, Vector3(-1.08, 0.14, 1.38), 0.28, 0.96, _spark_blue_mat)
	_spark_blue_r = _add_flame_cone(_wheels_root, Vector3(1.08, 0.14, 1.38), 0.28, 0.96, _spark_blue_mat)

	_spark_gold_mat = StandardMaterial3D.new()
	_spark_gold_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_spark_gold_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_spark_gold_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_spark_gold_mat.albedo_color = Color(1.0, 0.72, 0.12, 0.94)
	_spark_gold_l = _add_flame_cone(_wheels_root, Vector3(-1.14, 0.19, 1.48), 0.22, 1.15, _spark_gold_mat)
	_spark_gold_r = _add_flame_cone(_wheels_root, Vector3(1.14, 0.19, 1.48), 0.22, 1.15, _spark_gold_mat)

	# Subtle electric-blue friction glow halo around rear tires during drift (matches reference!)
	_tire_glow_mat = StandardMaterial3D.new()
	_tire_glow_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_tire_glow_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_tire_glow_mat.albedo_color = Color(0.22, 0.76, 1.0, 0.42)
	var tg_torus := TorusMesh.new()
	tg_torus.inner_radius = 0.42
	tg_torus.outer_radius = 0.62
	tg_torus.rings = 14
	tg_torus.ring_segments = 6
	for side_x in [-1.14, 1.14]:
		var tg := MeshInstance3D.new()
		tg.mesh = tg_torus
		tg.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		tg.material_override = _tire_glow_mat
		tg.position = Vector3(side_x, WHEEL_RAD_REAR, 0.86)
		tg.rotation_degrees.z = 90.0
		tg.visible = false
		_wheels_root.add_child(tg)
		if side_x < 0.0:
			_tire_glow_l = tg
		else:
			_tire_glow_r = tg

	# 6. Zero-Allocation World-Space 3D Tire Skidmark MultiMesh Ring Buffer (Zero Adreno GLES3 VBO stalls!)
	if not is_ghost:
		if _is_player_kart:
			_skid_mmi = MultiMeshInstance3D.new()
			_skid_mmi.top_level = true
			_skid_mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			_skid_mm = MultiMesh.new()
			_skid_mm.transform_format = MultiMesh.TRANSFORM_3D
			var sq := PlaneMesh.new()
			sq.size = Vector2(0.54, 1.35)
			var sk_mat := StandardMaterial3D.new()
			sk_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			sk_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			sk_mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
			sk_mat.albedo_color = Color(0.08, 0.06, 0.05, 0.48)
			sq.material = sk_mat
			_skid_mm.mesh = sq
			_skid_mm.instance_count = SKID_POOL_SIZE
			var hidden_xf := Transform3D(Basis.from_scale(Vector3(0.0001, 0.0001, 0.0001)), Vector3(0.0, -900.0, 0.0))
			for sk_i in range(SKID_POOL_SIZE):
				_skid_mm.set_instance_transform(sk_i, hidden_xf)
			_skid_mmi.multimesh = _skid_mm
			add_child(_skid_mmi)

		var puff_count := 18 if _is_player_kart else 6
		var puff_mesh := _get_puff_mesh()
		var smoke_t := _get_smoke_texture()
		for _i in range(puff_count):
			var pm := MeshInstance3D.new()
			pm.top_level = true
			pm.mesh = puff_mesh
			pm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			var mat := StandardMaterial3D.new()
			mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
			mat.billboard_keep_scale = true
			mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
			mat.albedo_texture = smoke_t
			mat.albedo_color = Color(0.96, 0.88, 0.74, 0.0)
			pm.material_override = mat
			pm.visible = false
			add_child(pm)
			_dust_puffs.append({
				"node": pm, "mat": mat, "life": 0.0, "max_life": 0.58 if _is_player_kart else 0.44,
				"vel": Vector3.ZERO, "base_col": Color(0.96, 0.88, 0.74)
			})

	# 7. Special Power-Up Overlays
	_uturn_ring = MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 1.36
	torus.outer_radius = 1.62
	_uturn_ring.mesh = torus
	_uturn_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var ut_mat := StandardMaterial3D.new()
	ut_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ut_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	ut_mat.albedo_color = Color(0.18, 0.95, 1.0, 0.70)
	_uturn_ring.material_override = ut_mat
	_uturn_ring.position = Vector3(0.0, 0.65, 0.0)
	_uturn_ring.visible = false
	add_child(_uturn_ring)

	_shield_mesh = MeshInstance3D.new()
	var sh_s := SphereMesh.new()
	sh_s.radius = 1.95
	sh_s.height = 3.9
	_shield_mesh.mesh = sh_s
	_shield_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_shield_mat = StandardMaterial3D.new()
	_shield_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_shield_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_shield_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_shield_mat.albedo_color = Color(0.15, 0.92, 0.55, 0.30)
	_shield_mesh.material_override = _shield_mat
	_shield_mesh.position = Vector3(0.0, 1.0, 0.0)
	_shield_mesh.visible = false
	add_child(_shield_mesh)

	_mask_orbit = Node3D.new()
	_mask_orbit.position = Vector3(0.0, 1.52, 0.0)
	var tiki_mini := _load_glb("res://assets/models/prop_tiki_statue.glb")
	if tiki_mini:
		tiki_mini.scale = Vector3(0.15, 0.15, 0.15)
		tiki_mini.position = Vector3(1.72, -0.25, 0.0)
		_mask_orbit.add_child(tiki_mini)
	_mask_orbit.visible = false
	add_child(_mask_orbit)

	_tnt_node = _load_glb("res://assets/models/prop_crate_tnt.glb")
	if _tnt_node == null:
		_tnt_node = Node3D.new()
	_tnt_node.scale = Vector3(0.46, 0.46, 0.46)
	_tnt_node.position = Vector3(0.0, 2.38, 0.10)
	_tnt_node.visible = false
	_body_pivot.add_child(_tnt_node)

func _make_wheel_node(pos: Vector3, sc: float, rim_col: Color, is_ghost: bool) -> Node3D:
	var pivot := Node3D.new()
	pivot.position = pos
	var spin_node := Node3D.new()
	pivot.add_child(spin_node)
	var w_glb := _load_glb("res://assets/models/kart_wheel.glb")
	if w_glb:
		w_glb.scale = Vector3(sc, sc, sc)
		if pos.x < 0.0:
			w_glb.rotation.y = PI
		spin_node.add_child(w_glb)
		_tint_kart_materials(w_glb, rim_col, rim_col, is_ghost)
	return pivot

func _tint_kart_materials(root: Node, body_col: Color, accent_col: Color, is_ghost: bool) -> void:
	for child in root.get_children():
		if child is MeshInstance3D:
			var mi := child as MeshInstance3D
			var mesh := mi.mesh
			if mesh:
				for surf_idx in range(mesh.get_surface_count()):
					var src_mat := mi.get_active_material(surf_idx)
					if is_ghost:
						var gm := StandardMaterial3D.new()
						gm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
						gm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
						gm.albedo_color = Color(0.18, 0.90, 1.0, 0.36)
						mi.set_surface_override_material(surf_idx, gm)
					elif src_mat is StandardMaterial3D:
						var mname := src_mat.resource_name
						# Keep KartWood & KartBrass authentic carved walnut & hammered brass!
						if mname.begins_with("KartBody") or mname.begins_with("KartPaint"):
							var m := src_mat.duplicate() as StandardMaterial3D
							# Blaze stays authentic rich warm carved wood (matching reference!); rivals get rich enamel tint over wood grain!
							var blend_amt := 0.18 if _racer_id == "blaze" else 0.62
							m.albedo_color = Color(1.0, 0.98, 0.94).lerp(body_col, blend_amt)
							mi.set_surface_override_material(surf_idx, m)
						elif mname.begins_with("KartAccent"):
							var m2 := src_mat.duplicate() as StandardMaterial3D
							m2.albedo_color = Color(0.14, 0.72, 0.66) if _racer_id == "blaze" else accent_col
							mi.set_surface_override_material(surf_idx, m2)
						elif mname.begins_with("KartRim") or mname.begins_with("WheelRim"):
							if _racer_id != "blaze":
								var m3 := src_mat.duplicate() as StandardMaterial3D
								m3.albedo_color = Color(1.0, 0.96, 0.88).lerp(accent_col, 0.45)
								mi.set_surface_override_material(surf_idx, m3)
		_tint_kart_materials(child, body_col, accent_col, is_ghost)

func _apply_ghost_material(root: Node) -> void:
	for child in root.get_children():
		if child is MeshInstance3D:
			var mi := child as MeshInstance3D
			var gm := StandardMaterial3D.new()
			gm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			gm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			gm.albedo_color = Color(0.22, 0.92, 1.0, 0.40)
			mi.material_override = gm
		_apply_ghost_material(child)

func trigger_boost_flash(tier: int) -> void:
	_boost_flash = 1.0
	_sonic_timer = 0.38
	if _sonic_ring and _sonic_mat:
		_sonic_ring.visible = true
		var s_col := Color(1.0, 0.65, 0.12, 0.92)
		if tier >= 4:
			s_col = Color(0.16, 0.92, 1.0, 0.96)
		elif tier == 3:
			s_col = Color(1.0, 0.88, 0.18, 0.95)
		_sonic_mat.albedo_color = s_col

func trigger_weapon_launch(_kind: String = "") -> void:
	_weapon_anim_timer = 0.36
	_visual_pitch -= 0.085

func trigger_collision_jolt(side_dir: float, strength: float = 0.8) -> void:
	var s := clampf(strength, 0.25, 1.2)
	_impact_roll = clampf(side_dir * 0.28 * s, -0.35, 0.35)
	_impact_pitch = -0.14 * s
	_impact_spark_timer = 0.22
	if _collision_spark:
		_collision_spark.visible = true
		_collision_spark.position = Vector3(-side_dir * 0.98, 0.55, -0.35)
		_collision_spark.scale = Vector3.ONE * (0.65 + s * 0.75)

var _dust_col: Color = Color(0.90, 0.84, 0.74)

func update_anim(delta: float, st: Dictionary) -> void:
	_time += delta
	var speed: float = float(st.get("speed", 0.0))
	var steer: float = float(st.get("steer", 0.0))
	var is_drifting: bool = bool(st.get("is_drifting", false))
	var drift_dir: int = int(st.get("drift_dir", 0))
	var drift_charge: float = float(st.get("drift_charge", 0.0))
	var fire_tier: int = int(st.get("fire_tier", 0))
	var is_grounded: bool = bool(st.get("is_grounded", true))
	var air_uturn: bool = bool(st.get("air_uturn", false))
	var susp_offset: float = float(st.get("susp_offset", 0.0))
	var weight_pitch: float = float(st.get("weight_pitch", 0.0))
	var weight_roll: float = float(st.get("weight_roll", 0.0))
	var spinout: bool = bool(st.get("spinout", false))
	var surf_type: String = str(st.get("surface_type", "road"))
	_dust_col = st.get("dust_col", Color(0.90, 0.84, 0.74))
	var accelerating: bool = bool(st.get("accelerating", false))
	var w_offsets: Array = st.get("wheel_y_offsets", [0.0, 0.0, 0.0, 0.0])

	if _boost_flash > 0.0:
		_boost_flash = maxf(0.0, _boost_flash - delta * 2.8)
	if _weapon_anim_timer > 0.0:
		_weapon_anim_timer = maxf(0.0, _weapon_anim_timer - delta * 2.8)
	_impact_roll = lerpf(_impact_roll, 0.0, minf(1.0, delta * 11.0))
	_impact_pitch = lerpf(_impact_pitch, 0.0, minf(1.0, delta * 11.0))

	# Animate 3D Expanding Sonic Shockwave Ring!
	if _sonic_timer > 0.0:
		_sonic_timer = maxf(0.0, _sonic_timer - delta)
		if _sonic_ring:
			var u := 1.0 - (_sonic_timer / 0.38)
			var r_sc := lerpf(0.42, 2.75, u)
			_sonic_ring.scale = Vector3(r_sc, 1.0, r_sc)
			_sonic_ring.position.z = lerpf(1.62, 3.65, u)
			_sonic_mat.albedo_color.a = (1.0 - u) * 0.88
			if _sonic_timer <= 0.0:
				_sonic_ring.visible = false

	# Animate 3D Collision Spark Starburst!
	if _impact_spark_timer > 0.0:
		_impact_spark_timer = maxf(0.0, _impact_spark_timer - delta)
		if _collision_spark:
			var su := 1.0 - (_impact_spark_timer / 0.22)
			_collision_spark.scale = Vector3.ONE * lerpf(0.6, 1.85, su)
			_collision_spark_mat.albedo_color.a = (1.0 - su) * 0.95
			if _impact_spark_timer <= 0.0:
				_collision_spark.visible = false

	if _shadow_mesh:
		_shadow_mesh.visible = is_grounded or absf(susp_offset) < 0.55
		_shadow_mesh.scale = Vector3(1.0, 1.0, 1.0) if is_grounded else Vector3(0.76, 1.0, 0.76)

	# 1. HEAVY WEIGHTED CHASSIS MOTION (Independent of Grounded Wheels!)
	var target_drift_yaw := 0.0
	if is_drifting:
		target_drift_yaw = -float(drift_dir) * (0.36 + steer * float(drift_dir) * 0.14)
	elif air_uturn:
		target_drift_yaw = -steer * 0.54
	_visual_drift_yaw = lerpf(_visual_drift_yaw, target_drift_yaw, minf(1.0, delta * 10.5))

	if spinout:
		_spinout_angle += delta * 15.0
	else:
		_spinout_angle = lerpf(_spinout_angle, 0.0, minf(1.0, delta * 10.0))

	var turbo_wheelie := sin(_boost_flash * PI) * 0.115
	_visual_roll = lerpf(_visual_roll, weight_roll + _impact_roll, minf(1.0, delta * 12.0))
	_visual_pitch = lerpf(_visual_pitch, weight_pitch + turbo_wheelie + _impact_pitch, minf(1.0, delta * 12.0))

	_body_pivot.position.y = clampf(susp_offset, -0.22, 0.18)
	_body_pivot.rotation.y = _visual_drift_yaw + _spinout_angle
	_body_pivot.rotation.z = _visual_roll
	_body_pivot.rotation.x = _visual_pitch

	# 2. REALISTIC GROUNDED 4-WHEEL ROLLING SPIN, CONTACT TRACKING & DRIFT TIRE CAMBER/SQUASH!
	_wheels_root.rotation.y = _visual_drift_yaw + _spinout_angle
	var rear_slip_mult := 1.32 if (is_drifting or fire_tier >= 2) else 1.0
	_wheel_spin_f += (speed / WHEEL_RAD_FRONT) * delta
	_wheel_spin_r += (speed / WHEEL_RAD_REAR) * rear_slip_mult * delta

	var front_yaw := -steer * 0.45
	var off_fl: float = float(w_offsets[0]) if w_offsets.size() >= 4 else 0.0
	var off_fr: float = float(w_offsets[1]) if w_offsets.size() >= 4 else 0.0
	var off_rl: float = float(w_offsets[2]) if w_offsets.size() >= 4 else 0.0
	var off_rr: float = float(w_offsets[3]) if w_offsets.size() >= 4 else 0.0

	_wheel_fl.position.y = WHEEL_RAD_FRONT + off_fl
	_wheel_fr.position.y = WHEEL_RAD_FRONT + off_fr
	_wheel_rl.position.y = WHEEL_RAD_REAR + off_rl
	_wheel_rr.position.y = WHEEL_RAD_REAR + off_rr

	for w in [_wheel_fl, _wheel_fr]:
		w.rotation.y = lerpf(w.rotation.y, front_yaw, minf(1.0, delta * 14.0))
		if w.get_child_count() > 0:
			w.get_child(0).rotation.x = -_wheel_spin_f

	# Rear tires: realistic drift camber & lateral rubber sidewall squash!
	var camber_target := float(drift_dir) * 0.14 if (is_drifting and is_grounded) else 0.0
	var squash_y := 0.93 if (is_drifting and is_grounded) else 1.0
	var bulge_x := 1.06 if (is_drifting and is_grounded) else 1.0
	for w in [_wheel_rl, _wheel_rr]:
		w.rotation.z = lerpf(w.rotation.z, camber_target, minf(1.0, delta * 14.0))
		w.scale = w.scale.lerp(Vector3(bulge_x, squash_y, 1.0), minf(1.0, delta * 14.0))
		if w.get_child_count() > 0:
			w.get_child(0).rotation.x = -_wheel_spin_r

	# 3. Expressive Animal Driver Animations: Corner Lean, Turbo G-Force Snap, Weapon Throw Punch & Victory Bounce!
	var driver_turbo_pitch := sin(_boost_flash * PI) * 0.25
	var driver_weapon_pitch := -sin(_weapon_anim_timer / 0.36 * PI) * 0.34
	_driver_pivot.rotation.z = lerpf(_driver_pivot.rotation.z, -steer * 0.28 + _visual_roll * 0.55, minf(1.0, delta * 10.5))
	_driver_pivot.rotation.y = lerpf(_driver_pivot.rotation.y, -steer * 0.24 + (_weapon_anim_timer * 0.45), minf(1.0, delta * 9.5))
	_driver_pivot.rotation.x = lerpf(_driver_pivot.rotation.x, driver_turbo_pitch + driver_weapon_pitch + _impact_pitch * 1.4, minf(1.0, delta * 14.0))
	if bool(st.get("finished", false)):
		_driver_pivot.position.y = 0.02 + absf(sin(_time * 10.0)) * 0.22
	else:
		_driver_pivot.position.y = 0.02 + sin(_time * 24.0) * (0.014 if speed > 10.0 else 0.005) + (_boost_flash * 0.06)

	# 4. Reference-Matched Twin Low Plasma Exhaust Jets (Electric-Blue Inner Core + Fiery Orange Outer Jet!)
	var show_cruise_flame := accelerating and speed > 22.0
	if fire_tier > 0 or _boost_flash > 0.05 or show_cruise_flame:
		var col_outer := Color(1.0, 0.48, 0.08, 0.88)
		var col_inner := Color(0.28, 0.82, 1.0, 0.96)
		var f_len := 0.72
		match fire_tier:
			0:
				col_outer = Color(1.0, 0.52, 0.10, 0.78)
				col_inner = Color(0.32, 0.82, 1.0, 0.90)
				f_len = 0.68
			1:
				col_outer = Color(1.0, 0.36, 0.06, 0.92)
				col_inner = Color(0.34, 0.84, 1.0, 0.96)
				f_len = 1.08
			2:
				col_outer = Color(1.0, 0.58, 0.08, 0.95)
				col_inner = Color(0.30, 0.86, 1.0, 0.98)
				f_len = 1.48
			3: # SACRED FIRE
				col_outer = Color(1.0, 0.84, 0.14, 0.98)
				col_inner = Color(0.45, 0.92, 1.0, 1.0)
				f_len = 2.02
			4: # SUPER BLUE FIRE!
				col_outer = Color(0.14, 0.88, 1.0, 1.0)
				col_inner = Color(0.95, 0.99, 1.0, 1.0)
				f_len = 2.68
		var pulse := 1.0 + sin(_time * 54.0) * 0.18 + _boost_flash * 0.60
		_flame_mat.albedo_color = col_outer
		_flame_core_mat.albedo_color = col_inner
		var rad_s := 0.72 + float(fire_tier) * 0.13 + _boost_flash * 0.28
		var sc := Vector3(rad_s, f_len * 0.74 * pulse, rad_s)
		for fl in [_flame_l, _flame_r]:
			fl.visible = true
			fl.scale = sc
		for fc in [_flame_core_l, _flame_core_r]:
			fc.visible = true
			fc.scale = sc * Vector3(0.84, 0.76, 0.84)
		if _exhaust_light:
			_exhaust_light.light_color = Color(col_outer.r, col_outer.g, col_outer.b)
			_exhaust_light.light_energy = (0.45 + float(fire_tier) * 0.72) * pulse
	else:
		_flame_l.visible = false
		_flame_r.visible = false
		_flame_core_l.visible = false
		_flame_core_r.visible = false
		if _exhaust_light:
			_exhaust_light.light_energy = 0.0

	# 5. Reference-Matched Dual-Color Electric-Blue + Golden-Orange Drift Tire Friction Sparks!
	if is_drifting and is_grounded:
		var flicker := 0.82 + absf(sin(_time * 48.0)) * 0.42
		var blue_s := (0.76 + drift_charge * 0.95) * flicker
		var gold_s := (0.65 + drift_charge * 1.25) * (0.85 + absf(cos(_time * 41.0)) * 0.38)
		_spark_blue_l.visible = true
		_spark_blue_r.visible = true
		_spark_gold_l.visible = true
		_spark_gold_r.visible = true
		_spark_blue_l.position.y = 0.12 + off_rl
		_spark_blue_r.position.y = 0.12 + off_rr
		_spark_gold_l.position.y = 0.18 + off_rl
		_spark_gold_r.position.y = 0.18 + off_rr
		_spark_blue_l.scale = Vector3(blue_s, blue_s * 1.15, blue_s)
		_spark_blue_r.scale = Vector3(blue_s, blue_s * 1.15, blue_s)
		_spark_gold_l.scale = Vector3(gold_s, gold_s * 1.28, gold_s)
		_spark_gold_r.scale = Vector3(gold_s, gold_s * 1.28, gold_s)

		if drift_charge >= 0.76:
			_spark_gold_mat.albedo_color = Color(1.0, 0.28, 0.06, 1.0)
			_spark_blue_mat.albedo_color = Color(0.24, 0.92, 1.0, 1.0)
		elif drift_charge >= 0.48:
			_spark_gold_mat.albedo_color = Color(1.0, 0.78, 0.14, 0.96)
			_spark_blue_mat.albedo_color = Color(0.26, 0.84, 1.0, 0.95)
		else:
			_spark_gold_mat.albedo_color = Color(1.0, 0.86, 0.34, 0.88)
			_spark_blue_mat.albedo_color = Color(0.32, 0.78, 1.0, 0.86)

		if _tire_glow_l and _tire_glow_r:
			_tire_glow_l.visible = true
			_tire_glow_r.visible = true
			_tire_glow_l.position.y = WHEEL_RAD_REAR + off_rl
			_tire_glow_r.position.y = WHEEL_RAD_REAR + off_rr
			_tire_glow_mat.albedo_color.a = clampf(0.24 + drift_charge * 0.40, 0.20, 0.62)
	else:
		_spark_blue_l.visible = false
		_spark_blue_r.visible = false
		_spark_gold_l.visible = false
		_spark_gold_r.visible = false
		if _tire_glow_l: _tire_glow_l.visible = false
		if _tire_glow_r: _tire_glow_r.visible = false

	# 6. Zero-Waste 3D Tire Skidmarks & Thick Swirling Dust/Smoke Plumes (Player + Rivals!)
	if not _is_ghost_kart and is_inside_tree():
		_update_skidmarks_and_dust(delta, speed, is_drifting, is_grounded, drift_charge, fire_tier, surf_type)

	# 7. Overlays
	_uturn_ring.visible = air_uturn
	if air_uturn:
		_uturn_ring.rotation.y += delta * 14.0

	_shield_mesh.visible = bool(st.get("shield", false))
	if _shield_mesh.visible:
		_shield_mat.albedo_color = Color(0.18, 0.65, 1.0, 0.34) if bool(st.get("shield_juiced", false)) else Color(0.18, 0.95, 0.45, 0.30)
		var sh_p := 1.0 + sin(_time * 8.0) * 0.04
		_shield_mesh.scale = Vector3(sh_p, sh_p, sh_p)

	_mask_orbit.visible = bool(st.get("mask", false))
	if _mask_orbit.visible:
		_mask_orbit.rotation.y += delta * 7.5

	_tnt_node.visible = bool(st.get("tnt", false))
	if _tnt_node.visible:
		var t_rem := float(st.get("tnt_timer", 2.0))
		var ts := 0.46 * (1.0 + absf(sin(_time * (10.0 + (3.0 - t_rem) * 12.0))) * 0.24)
		_tnt_node.scale = Vector3(ts, ts, ts)
		_tnt_node.rotation.y += delta * 4.5

func _update_skidmarks_and_dust(delta: float, speed: float, is_drifting: bool, is_grounded: bool, drift_charge: float, fire_tier: int, surf_type: String) -> void:
	if _is_player_kart and _skid_mm != null:
		var leaving_marks := is_grounded and is_drifting and absf(speed) > 13.0
		if leaving_marks:
			var pos_l := _wheel_rl.global_position - global_basis.y * (WHEEL_RAD_REAR - 0.048)
			var pos_r := _wheel_rr.global_position - global_basis.y * (WHEEL_RAD_REAR - 0.048)
			if _had_skid and pos_l.distance_squared_to(_last_skid_l) > 0.72 and pos_l.distance_squared_to(_last_skid_l) < 64.0:
				var up_v := global_basis.y.normalized()
				for pair in [[_last_skid_l, pos_l], [_last_skid_r, pos_r]]:
					var p0: Vector3 = pair[0]
					var p1: Vector3 = pair[1]
					var seg_v := p1 - p0
					var seg_l := maxf(0.4, seg_v.length())
					var fwd_s := seg_v / seg_l
					var right_s := fwd_s.cross(up_v).normalized()
					if right_s.length_squared() < 0.01:
						right_s = global_basis.x.normalized()
					var ortho_f := up_v.cross(right_s).normalized()
					var b := Basis(right_s, up_v, -ortho_f).orthonormalized().scaled(Vector3(1.0, 1.0, clampf(seg_l / 1.25, 0.5, 2.2)))
					_skid_mm.set_instance_transform(_skid_cursor, Transform3D(b, p0.lerp(p1, 0.5)))
					_skid_cursor = (_skid_cursor + 1) % SKID_POOL_SIZE
				_last_skid_l = pos_l
				_last_skid_r = pos_r
			elif not _had_skid:
				_last_skid_l = pos_l
				_last_skid_r = pos_r
				_had_skid = true
		else:
			_had_skid = false

	# Swirling Billowy Road Dust & Tire Smoke Plumes (Drifting, Boosting, Off-Road, or High-Speed Rivals!)
	_dust_timer -= delta
	var emit_dust := is_grounded and absf(speed) > 16.0 and (is_drifting or surf_type == "offroad" or fire_tier >= 2 or (not _is_player_kart and absf(speed) > 28.0))
	if emit_dust and _dust_timer <= 0.0:
		_dust_timer = (0.042 if is_drifting else 0.085) if _is_player_kart else 0.14
		var wheels_to_emit := [_wheel_rl, _wheel_rr] if _is_player_kart else [_wheel_rr]
		for w_node in wheels_to_emit:
			for p in _dust_puffs:
				if float(p["life"]) <= 0.0:
					p["life"] = float(p["max_life"])
					var nd: MeshInstance3D = p["node"]
					nd.global_position = w_node.global_position + Vector3(randf_range(-0.24, 0.24), -0.34, randf_range(-0.24, 0.24))
					nd.visible = true
					p["vel"] = Vector3(randf_range(-2.2, 2.2), randf_range(1.4, 3.0), randf_range(-2.2, 2.2)) + global_basis.z * 3.4
					if is_drifting and drift_charge >= 0.72:
						p["base_col"] = Color(0.98, 0.82, 0.62)
					else:
						p["base_col"] = _dust_col
					break

	for p in _dust_puffs:
		var life := float(p["life"])
		if life > 0.0:
			life -= delta
			p["life"] = life
			var nd: MeshInstance3D = p["node"]
			if life <= 0.0:
				nd.visible = false
			else:
				var u := 1.0 - (life / float(p["max_life"]))
				nd.global_position += (p["vel"] as Vector3) * delta
				var s := lerpf(1.05, 3.65 if _is_player_kart else 2.85, u)
				nd.scale = Vector3(s, s * 0.90, s)
				var mat: StandardMaterial3D = p["mat"]
				var bc: Color = p["base_col"]
				mat.albedo_color = Color(bc.r, bc.g, bc.b, (1.0 - u) * (0.58 if _is_player_kart else 0.44))

func _add_flame_cone(parent: Node3D, pos: Vector3, rad: float, h: float, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var c := CylinderMesh.new()
	c.top_radius = 0.018
	c.bottom_radius = rad
	c.height = h
	c.radial_segments = 8
	mi.mesh = c
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.material_override = mat
	mi.position = pos
	mi.rotation_degrees.x = 88.0
	mi.visible = false
	parent.add_child(mi)
	return mi
