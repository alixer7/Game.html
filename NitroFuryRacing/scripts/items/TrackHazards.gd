class_name TrackHazards
extends Node3D

## Interactive Static & Moving CTR Track Hazards (v6.0 Legendary CTR Edition):
## - Papu's Pyramid: Snapping Giant Jungle Chomper Plants lunging across tight inner corners!
## - Sewer Speedway: Giant Rolling Iron-Banded Barrels patrolling wide half-pipe floors!
## - Dragon Mines: Roaring Steel Gem-Filled Mine Carts racing across railway tracks!
## - Plus Rolling Spiked Boulders, Swinging Temple Pendulums, Erupting Frost Geysers & Flame Vents!

var _hazards: Array[Dictionary] = []
var _karts: Array[KartPhysics] = []
var _time: float = 0.0

static var _glb_cache: Dictionary = {}

static func _inst_glb(path: String) -> Node3D:
	if not _glb_cache.has(path):
		var res = load(path)
		if res is PackedScene:
			_glb_cache[path] = res
		else:
			return null
	return (_glb_cache[path] as PackedScene).instantiate() as Node3D

func setup(spline: TrackSpline, karts: Array[KartPhysics], hazard_defs: Array) -> void:
	for c in get_children():
		c.queue_free()
	_hazards.clear()
	_karts = karts
	_time = 0.0

	for hd in hazard_defs:
		var kind: String = str(hd.get("kind", "boulder"))
		var t_val: float = float(hd.get("t", 0.5))
		var s := spline.sample_at_t(t_val)
		var base_pos: Vector3 = s["pos"]
		var right: Vector3 = s["right"]
		var up: Vector3 = s["up"]
		var fwd: Vector3 = s["forward"]

		match kind:
			"chomper":
				# PAPU'S PYRAMID ICONIC SNAPPING JUNGLE CHOMPER PLANT!
				var lat: float = float(hd.get("lateral", -10.5))
				var pos: Vector3 = base_pos + right * lat
				var inward_dir := -right if lat > 0.0 else right
				var root := Node3D.new()
				root.position = pos
				# Face inward across the racing lane (-Z of GLB points toward inward_dir!)
				var yaw := atan2(-inward_dir.x, -inward_dir.z)
				root.rotation.y = yaw
				add_child(root)
				var plant := _inst_glb("res://assets/models/prop_chomper_plant.glb")
				if plant:
					plant.scale = Vector3(1.18, 1.18, 1.18)
					root.add_child(plant)
				_hazards.append({
					"kind": "chomper",
					"root": root,
					"plant": plant,
					"base_pos": pos,
					"inward": inward_dir,
					"speed": float(hd.get("speed", 2.2)),
					"phase": float(hd.get("phase", 0.0))
				})

			"barrel":
				# SEWER SPEEDWAY GIANT ROLLING IRON-BANDED BARREL!
				var node := _inst_glb("res://assets/models/prop_sewer_barrel.glb")
				if node == null:
					node = Node3D.new()
				node.position = base_pos + up * 1.84
				node.basis = Basis(right, up, -fwd).orthonormalized()
				add_child(node)
				_hazards.append({
					"kind": "barrel",
					"node": node,
					"base_pos": base_pos + up * 1.84,
					"right": right,
					"span": float(hd.get("span", 10.5)),
					"speed": float(hd.get("speed", 1.55)),
					"phase": float(hd.get("phase", 0.0))
				})

			"mine_cart":
				# DRAGON MINES ROARING STEEL MINE CART ON GLOWING RAILWAY TRACKS!
				var span_mc: float = float(hd.get("span", 14.0))
				# Build visible steel railway tracks + timber sleepers right across the crossing!
				var track_root := Node3D.new()
				track_root.position = base_pos + up * 0.055
				track_root.basis = Basis(right, up, -fwd).orthonormalized()
				add_child(track_root)
				var rail_mat := StandardMaterial3D.new()
				rail_mat.albedo_color = Color(0.58, 0.62, 0.70)
				rail_mat.metallic = 0.88
				rail_mat.roughness = 0.28
				var tie_mat := StandardMaterial3D.new()
				tie_mat.albedo_color = Color(0.32, 0.20, 0.10)
				tie_mat.roughness = 0.88
				for rz in [-1.05, 1.05]:
					var rail := MeshInstance3D.new()
					var rb := BoxMesh.new()
					rb.size = Vector3(span_mc * 2.3, 0.12, 0.16)
					rail.mesh = rb; rail.material_override = rail_mat
					rail.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
					rail.position = Vector3(0.0, 0.08, rz)
					track_root.add_child(rail)
				for tx_i in range(-10, 11):
					var tie := MeshInstance3D.new()
					var tb := BoxMesh.new()
					tb.size = Vector3(0.35, 0.06, 2.75)
					tie.mesh = tb; tie.material_override = tie_mat
					tie.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
					tie.position = Vector3(float(tx_i) * (span_mc * 0.21), 0.03, 0.0)
					track_root.add_child(tie)

				var cart := _inst_glb("res://assets/models/prop_mine_cart.glb")
				if cart == null:
					cart = Node3D.new()
				cart.scale = Vector3(1.12, 1.12, 1.12)
				cart.position = base_pos + up * 0.14
				# Align cart length along the crossing track (right vector)
				cart.basis = Basis(fwd, up, right).orthonormalized()
				add_child(cart)
				_hazards.append({
					"kind": "mine_cart",
					"node": cart,
					"base_pos": base_pos + up * 0.14,
					"right": right,
					"span": span_mc,
					"speed": float(hd.get("speed", 1.75)),
					"phase": float(hd.get("phase", 0.0))
				})

			"boulder":
				var node := _inst_glb("res://assets/models/prop_boulder.glb")
				if node == null:
					node = Node3D.new()
				node.position = base_pos + up * 1.9
				add_child(node)
				_hazards.append({
					"kind": "boulder",
					"node": node,
					"base_pos": base_pos + up * 1.9,
					"right": right,
					"span": float(hd.get("span", 9.0)),
					"speed": float(hd.get("speed", 1.5)),
					"phase": float(hd.get("phase", 0.0))
				})

			"pendulum":
				var pivot := Node3D.new()
				pivot.position = base_pos + up * 11.4
				pivot.basis = Basis(right, up, -fwd).orthonormalized()
				add_child(pivot)
				var pend := _inst_glb("res://assets/models/prop_pendulum.glb")
				if pend:
					pivot.add_child(pend)
				var p_mat := StandardMaterial3D.new()
				p_mat.albedo_color = Color(0.24, 0.22, 0.28)
				p_mat.roughness = 0.85
				var frame := Node3D.new()
				frame.position = base_pos
				frame.basis = Basis(right, up, -fwd).orthonormalized()
				add_child(frame)
				var hw: float = float(s["half_width"]) + 1.2
				for side in [-1.0, 1.0]:
					var col := MeshInstance3D.new()
					var cm := CylinderMesh.new()
					cm.top_radius = 0.7; cm.bottom_radius = 0.95; cm.height = 12.2
					col.mesh = cm; col.material_override = p_mat
					col.position = Vector3(side * hw, 6.1, 0.0)
					frame.add_child(col)
					var sb := StaticBody3D.new()
					sb.collision_layer = 2
					sb.set_meta("surface_type", "prop_obstacle")
					sb.set_meta("collision_strength", "heavy")
					var cs := CollisionShape3D.new()
					var csh := CylinderShape3D.new()
					csh.radius = 0.95; csh.height = 12.2
					cs.shape = csh
					cs.position = Vector3(side * hw, 6.1, 0.0)
					sb.add_child(cs)
					frame.add_child(sb)
				var beam := MeshInstance3D.new()
				var bm := BoxMesh.new()
				bm.size = Vector3(hw * 2.0 + 2.0, 1.2, 1.6)
				beam.mesh = bm; beam.material_override = p_mat
				beam.position = Vector3(0.0, 12.0, 0.0)
				frame.add_child(beam)
				_hazards.append({
					"kind": "pendulum",
					"pivot": pivot,
					"base_pos": base_pos,
					"speed": float(hd.get("speed", 1.6)),
					"phase": float(hd.get("phase", 0.0)),
					"max_ang": deg_to_rad(52.0)
				})

			"frost_geyser", "flame_vent":
				var is_frost := (kind == "frost_geyser")
				var pos: Vector3 = base_pos + right * float(hd.get("lateral", 0.0))
				var root := Node3D.new()
				root.position = pos
				add_child(root)
				var ring := MeshInstance3D.new()
				var tm := TorusMesh.new()
				tm.inner_radius = 1.6; tm.outer_radius = 2.3
				ring.mesh = tm
				var rmat := StandardMaterial3D.new()
				rmat.albedo_color = Color(0.18, 0.78, 1.0) if is_frost else Color(1.0, 0.34, 0.06)
				rmat.emission_enabled = true
				rmat.emission = rmat.albedo_color
				rmat.emission_energy_multiplier = 1.4
				ring.material_override = rmat
				ring.position = Vector3(0.0, 0.14, 0.0)
				root.add_child(ring)
				var plume := MeshInstance3D.new()
				var cyl := CylinderMesh.new()
				cyl.top_radius = 1.5; cyl.bottom_radius = 2.0; cyl.height = 10.5
				plume.mesh = cyl
				var pmat := StandardMaterial3D.new()
				pmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
				pmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
				pmat.albedo_color = Color(0.28, 0.94, 1.0, 0.72) if is_frost else Color(1.0, 0.48, 0.06, 0.78)
				plume.material_override = pmat
				plume.position = Vector3(0.0, 5.2, 0.0)
				plume.visible = false
				root.add_child(plume)
				_hazards.append({
					"kind": kind,
					"pos": pos,
					"plume": plume,
					"ring_mat": rmat,
					"period": float(hd.get("period", 3.6)),
					"phase": float(hd.get("phase", 0.0)),
					"cooldowns": {}
				})

func _physics_process(delta: float) -> void:
	_time += delta
	for h in _hazards:
		var kind: String = h["kind"]
		if kind == "chomper":
			# Rhythmic Papu's Pyramid Plant Lunge & Snap!
			var phase_v := fposmod(_time * float(h["speed"]) * 0.36 + float(h["phase"]), 1.0)
			var lunge := 0.0
			if phase_v > 0.58 and phase_v < 0.88:
				lunge = sin((phase_v - 0.58) / 0.30 * PI)
			var plant: Node3D = h["plant"]
			if plant:
				plant.position = Vector3(0.0, 0.0, -lunge * 2.8)
				plant.rotation.x = -lunge * 0.42
				var sc_s := 1.18 * (1.0 + lunge * 0.16)
				plant.scale = Vector3(sc_s, sc_s, sc_s)
			var bite_world: Vector3 = (h["base_pos"] as Vector3) + (h["inward"] as Vector3) * (2.2 + lunge * 2.8) + Vector3(0.0, 2.2, 0.0)
			if lunge > 0.25:
				for k in _karts:
					if not is_instance_valid(k): continue
					if k.global_position.distance_squared_to(bite_world) < 2.9 * 2.9:
						k.apply_hit("chomper", false)

		elif kind == "barrel":
			var node: Node3D = h["node"]
			var s_val := sin(_time * float(h["speed"]) + float(h["phase"]))
			var pos: Vector3 = (h["base_pos"] as Vector3) + (h["right"] as Vector3) * (s_val * float(h["span"]))
			node.position = pos
			node.rotate_object_local(Vector3.FORWARD, cos(_time * float(h["speed"]) + float(h["phase"])) * delta * 3.8)
			for k in _karts:
				if not is_instance_valid(k): continue
				if k.global_position.distance_squared_to(pos) < 2.75 * 2.75:
					k.apply_hit("barrel", false)

		elif kind == "mine_cart":
			var node: Node3D = h["node"]
			var s_val := sin(_time * float(h["speed"]) + float(h["phase"]))
			var pos: Vector3 = (h["base_pos"] as Vector3) + (h["right"] as Vector3) * (s_val * float(h["span"]))
			pos.y += absf(sin(_time * 22.0)) * 0.06
			node.position = pos
			for k in _karts:
				if not is_instance_valid(k): continue
				if k.global_position.distance_squared_to(pos + Vector3(0.0, 1.2, 0.0)) < 2.85 * 2.85:
					k.apply_hit("mine_cart", false)

		elif kind == "boulder":
			var node: Node3D = h["node"]
			var s_val := sin(_time * float(h["speed"]) + float(h["phase"]))
			var pos: Vector3 = (h["base_pos"] as Vector3) + (h["right"] as Vector3) * (s_val * float(h["span"]))
			node.position = pos
			node.rotation.z = -s_val * float(h["span"]) * 0.55
			node.rotation.x += delta * 2.2
			for k in _karts:
				if not is_instance_valid(k): continue
				if k.global_position.distance_squared_to(pos) < 2.65 * 2.65:
					k.apply_hit("boulder", false)

		elif kind == "pendulum":
			var pivot: Node3D = h["pivot"]
			var ang := sin(_time * float(h["speed"]) + float(h["phase"])) * float(h["max_ang"])
			pivot.rotation.z = ang
			var head_world := pivot.to_global(Vector3(0.0, -9.2, 0.0))
			for k in _karts:
				if not is_instance_valid(k): continue
				if k.global_position.distance_squared_to(head_world) < 2.55 * 2.55:
					k.apply_hit("pendulum", false)

		elif kind == "frost_geyser" or kind == "flame_vent":
			var per: float = float(h["period"])
			var u := fposmod((_time + float(h["phase"])) / per, 1.0)
			var plume: MeshInstance3D = h["plume"]
			var rmat: StandardMaterial3D = h["ring_mat"]
			var active := u >= 0.58
			var warning := u >= 0.38 and u < 0.58
			plume.visible = active
			if active:
				var h_scale := sin((u - 0.58) / 0.42 * PI)
				plume.scale = Vector3(1.0, maxf(0.15, h_scale * 1.15), 1.0)
				rmat.emission_energy_multiplier = 2.8
			elif warning:
				rmat.emission_energy_multiplier = 1.5 + absf(sin(_time * 24.0)) * 1.8
			else:
				rmat.emission_energy_multiplier = 0.7

			var cds: Dictionary = h["cooldowns"]
			for kid in cds.keys():
				cds[kid] = float(cds[kid]) - delta
				if float(cds[kid]) <= 0.0:
					cds.erase(kid)

			if active:
				var hpos: Vector3 = h["pos"]
				for k in _karts:
					if not is_instance_valid(k): continue
					var key := k.get_instance_id()
					if cds.has(key): continue
					var flat_d := Vector2(k.global_position.x - hpos.x, k.global_position.z - hpos.z).length()
					if flat_d < 2.6 and absf(k.global_position.y - hpos.y) < 7.0:
						cds[key] = 1.2
						if kind == "frost_geyser":
							k.trigger_geyser_launch(22.5)
						else:
							k.apply_hit("flame_vent", false)
