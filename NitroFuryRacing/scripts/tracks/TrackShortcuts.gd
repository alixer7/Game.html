class_name TrackShortcuts
extends RefCounted

## v8 jump-only shortcuts (CTR:NF philosophy): there is NO side road and NO bridge. Each shortcut is a jump decision:
##  - "corner_leap"   : kicker before a hairpin/corner -> fly straight over a void / chasm -> land after the corner
##                      (often needs a mid-air brake U-turn to line up with the exit road)
##  - "platforms"     : kicker -> floating platform(s) -> hop again -> land further along the track
##  - "wall_vault"    : hop a low wall / barrier separating two parts of the track
##  - "drop_down"     : launch off an upper deck and drop onto a later, lower part of the track
##  - "pipe_launch"   : ride up a half-pipe wall and launch over its rim into the next section
## Kicker ramps sit flush on the road surface (bank & crown aware), collide only with their top face (no snag),
## and the discovery trigger lives in mid-air on the flight line so normal racers never set it off.

static func build(b: TrackBuilder, sc: Dictionary, mx: float) -> Dictionary:
	var sp := b.spline
	var launch_t := sp.t_of_dist(float(sc["launch_d"]))
	var target_t := sp.t_of_dist(float(sc["target_d"]))
	var launch_lat := float(sc["launch_lat"]) * mx
	var target_lat := float(sc["target_lat"]) * mx
	var s_l := sp.sample_at_t(launch_t)
	var lp := sp.surface_point(launch_t, launch_lat)
	var tp := sp.surface_point(target_t, target_lat)
	var kind := str(sc.get("kind", "corner_leap"))
	var pitch := deg_to_rad(float(sc.get("pitch", 18.0)))
	var kw := float(sc.get("kw", 7.0))
	var kl := float(sc.get("kl", 8.0))
	var h0 := float(sc.get("kicker_h0", 0.0))

	# kicker frame: up = road up at launch, forward = toward target projected on the road plane
	var up: Vector3 = s_l["up"]
	var to_t := tp - lp
	if sc.has("aim_x"):
		to_t = Vector3(float(sc["aim_x"]) * mx, 0.0, float(sc["aim_z"])) - lp
	var fwd := (to_t - up * to_t.dot(up)).normalized()
	var right := fwd.cross(up).normalized()
	var basis := Basis(right, up, -fwd).orthonormalized()
	var origin := lp + up * h0
	var kicker := Node3D.new()
	kicker.position = origin
	kicker.basis = basis
	b.add_child(kicker)

	var ramp_h := tan(pitch) * kl
	var hw := kw * 0.5
	var p_bl := Vector3(-hw, 0.02, 0.0)
	var p_br := Vector3(hw, 0.02, 0.0)
	var p_fl := Vector3(-hw, ramp_h, -kl)
	var p_fr := Vector3(hw, ramp_h, -kl)
	var depth := ramp_h + 3.0
	var style := str(sc.get("hidden", "rock"))
	var mat: Material
	match style:
		"wood": mat = TrackMats.wall_mat("wood")
		"metal": mat = TrackMats.wall_mat("metal")
		"ice": mat = TrackMats.wall_mat("ice")
		"neon": mat = TrackMats.wall_mat("space")
		"temple": mat = TrackMats.wall_mat("temple")
		"basalt": mat = TrackMats.wall_mat("volcano")
		_: mat = TrackMats.pbr("cliff_rock_tiki", Color(0.92, 0.88, 0.8), 0.9)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n_top := (p_fl - p_bl).cross(p_br - p_bl).normalized()
	if n_top.y < 0.0:
		n_top = -n_top
	TrackBuilder.quad_flat(st, p_bl, p_br, p_fl, p_fr, n_top, 0.0, kw / 4.0, 0.0, kl / 4.0)
	TrackBuilder.quad_flat(st, p_fl, p_fr, p_fl - Vector3(0, depth, 0), p_fr - Vector3(0, depth, 0), Vector3.FORWARD, 0.0, kw / 4.0, 0.0, depth / 4.0)
	for sx in [-1.0, 1.0]:
		var b0 := Vector3(sx * hw, 0.02, 0.0)
		var f0 := Vector3(sx * hw, ramp_h, -kl)
		var f1 := Vector3(sx * hw, ramp_h - depth, -kl)
		var b1 := Vector3(sx * hw, -1.0, 0.0)
		TrackBuilder.tri(st, b0, f0, f1, Vector3(sx, 0, 0), Vector3(sx, 0, 0), Vector3(sx, 0, 0), Vector2(0, 0), Vector2(kl / 4.0, 0), Vector2(kl / 4.0, depth / 4.0))
		TrackBuilder.tri(st, b0, f1, b1, Vector3(sx, 0, 0), Vector3(sx, 0, 0), Vector3(sx, 0, 0), Vector2(0, 0), Vector2(kl / 4.0, depth / 4.0), Vector2(0, 0.25))
	st.generate_tangents()
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = mat
	kicker.add_child(mi)
	# chevron hint painted on the ramp (subtle: dark, visible only up close)
	var hint := MeshInstance3D.new()
	var hb := BoxMesh.new()
	hb.size = Vector3(kw * 0.5, 0.04, 0.5)
	hint.mesh = hb
	hint.material_override = TrackMats.flat(Color(0.95, 0.78, 0.2), 0.6, 0.0, 0.6)
	hint.position = Vector3(0.0, ramp_h * 0.82 + 0.05, -kl * 0.82)
	hint.rotation.x = -pitch
	kicker.add_child(hint)

	var faces := PackedVector3Array()
	var wl := func(p: Vector3) -> Vector3: return kicker.position + kicker.basis * p
	TrackBuilder.col_quad(faces, wl.call(p_bl), wl.call(p_br), wl.call(p_fl), wl.call(p_fr), basis * n_top)
	var ksb := StaticBody3D.new()
	ksb.collision_layer = TrackBuilder.TRACK_LAYER
	ksb.set_meta("surface_type", "kicker")
	var kcs := CollisionShape3D.new()
	var kshape := ConcavePolygonShape3D.new()
	kshape.set_faces(faces)
	kcs.shape = kshape
	ksb.add_child(kcs)
	b.add_child(ksb)
	var lip: Vector3 = wl.call(Vector3(0.0, ramp_h, -kl))

	# floating platforms (each with a small re-launch ramp at its far edge)
	var plat_out: Array = []
	for pl in sc.get("plats", []):
		var c := Vector3(float(pl["x"]) * mx, float(pl["y"]), float(pl["z"]))
		var r := float(pl.get("r", 7.0))
		var root := Node3D.new()
		root.position = c
		var flat_dir := Vector3(fwd.x, 0.0, fwd.z).normalized()
		root.rotation.y = atan2(-flat_dir.x, -flat_dir.z)
		b.add_child(root)
		var pk := str(pl.get("kind", "stone"))
		var vis: Node3D = null
		if pk in ["stone", "asteroid"]:
			vis = TrackBuilder._inst_glb("res://assets/models/prop_floating_pad.glb")
			if vis:
				vis.scale = Vector3(r / 7.25, 1.0, r / 7.25)
		if vis == null:
			var pm := MeshInstance3D.new()
			pm.mesh = TrackProps._cyl(r, r * 0.6, 2.2, 14)
			pm.material_override = TrackMats.wall_mat("ice" if pk == "ice" else ("space" if pk == "neon" else "rock"))
			pm.position = Vector3(0, -1.1, 0)
			vis = pm
		root.add_child(vis)
		var psb := StaticBody3D.new()
		psb.collision_layer = TrackBuilder.TRACK_LAYER
		psb.set_meta("surface_type", "kicker")
		var pcs := CollisionShape3D.new()
		var pcy := CylinderShape3D.new()
		pcy.radius = r
		pcy.height = 1.0
		pcs.shape = pcy
		pcs.position = Vector3(0, -0.5, 0)
		psb.add_child(pcs)
		root.add_child(psb)
		# small re-launch ramp on the far half of the pad (aligned with the flight line)
		var p2 := deg_to_rad(float(pl.get("ramp", 0.0)))
		var pad_lip := c + flat_dir * r
		if p2 > 0.0:
			var rh := tan(p2) * r
			var rw := r * 0.62
			var rst := SurfaceTool.new()
			rst.begin(Mesh.PRIMITIVE_TRIANGLES)
			var q_bl := Vector3(-rw, 0.02, 0.0)
			var q_br := Vector3(rw, 0.02, 0.0)
			var q_fl := Vector3(-rw, rh, -r)
			var q_fr := Vector3(rw, rh, -r)
			var nq := (q_fl - q_bl).cross(q_br - q_bl).normalized()
			if nq.y < 0.0:
				nq = -nq
			TrackBuilder.quad_flat(rst, q_bl, q_br, q_fl, q_fr, nq, 0.0, 1.0, 0.0, 1.0)
			TrackBuilder.quad_flat(rst, q_fl, q_fr, q_fl - Vector3(0, rh + 1.0, 0), q_fr - Vector3(0, rh + 1.0, 0), Vector3.FORWARD, 0.0, 1.0, 0.0, 0.3)
			var rmi := MeshInstance3D.new()
			rmi.mesh = rst.commit()
			rmi.material_override = mat
			root.add_child(rmi)
			var rfaces := PackedVector3Array()
			var rx := root.transform
			TrackBuilder.col_quad(rfaces, rx * q_bl, rx * q_br, rx * q_fl, rx * q_fr, rx.basis * nq)
			var rsb := StaticBody3D.new()
			rsb.collision_layer = TrackBuilder.TRACK_LAYER
			rsb.set_meta("surface_type", "kicker")
			var rcs := CollisionShape3D.new()
			var rshape := ConcavePolygonShape3D.new()
			rshape.set_faces(rfaces)
			rcs.shape = rshape
			rsb.add_child(rcs)
			b.add_child(rsb)
			pad_lip = c + flat_dir * r + Vector3(0, rh, 0)
		# fruit reward resting on the platform (also a discovery hint)
		for k in [-1, 0]:
			b.fruit_spawn_points.append(c + flat_dir * (float(k) * 2.6) + Vector3(0, 1.3, 0))
		plat_out.append({"pos": c, "r": r, "lip": pad_lip})

	# mid-air discovery trigger on the flight line (only jumpers pass through it)
	var trig_pos := lip.lerp(tp, 0.5) + Vector3(0, 3.0, 0)
	if not plat_out.is_empty():
		trig_pos = (plat_out[plat_out.size() - 1]["pos"] as Vector3) + Vector3(0, 2.0, 0)
	var area := Area3D.new()
	area.collision_layer = 32
	area.collision_mask = 16
	area.position = trig_pos
	var acs := CollisionShape3D.new()
	var sph := SphereShape3D.new()
	sph.radius = 7.5
	acs.shape = sph
	area.add_child(acs)
	var sc_id := str(sc["id"])
	var sc_name := str(sc.get("name_en", sc_id))
	area.body_entered.connect(func(body):
		if body is KartPhysics and not body.is_grounded:
			body.notify_shortcut(sc_id, sc_name)
	)
	b.add_child(area)
	b.spawned_prop_bounds.append({"pos": origin, "radius": kw})

	return {
		"id": sc_id,
		"name_en": sc_name,
		"name_ar": str(sc.get("name_ar", sc_name)),
		"jump_type": kind,
		"kind": kind,
		"required_fire": int(sc.get("required_fire", 3)),
		"launch_base": origin,
		"launch_tip": lip,
		"launch_fwd": fwd,
		"launch_pitch_deg": float(sc.get("pitch", 18.0)),
		"launch_t": launch_t,
		"launch_lat": launch_lat,
		"target_t": target_t,
		"target_lat": target_lat,
		"rejoin_pos": tp,
		"landing_entry": tp,
		"landing_center": tp,
		"platforms": plat_out,
		"gap_horizontal": Vector2(lip.x - tp.x, lip.z - tp.z).length(),
		"total_chord": Vector2(lip.x - tp.x, lip.z - tp.z).length(),
		"gap_delta_y": tp.y - lip.y,
		"has_side_bridge": false,
		"skip_m": fposmod(target_t - launch_t, 1.0) * sp.total_length,
	}
