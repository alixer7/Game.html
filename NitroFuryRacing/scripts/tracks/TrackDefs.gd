class_name TrackDefs
extends RefCounted

## v7.0 CTR:NF True Philosophy Master Blueprints (ALL >= 2.18 km, Multi-Biome, Over-Under Figure-8,
## Crowned/Undulating/Ribbed Surfaces, Cuttable Flush Off-Road Corners, 0 Side Bridges, 9 Pure Jump Shortcuts!):
##
## 1. EMERALD TEMPLE CIRCUIT  (2,185 m) — Jungle Village -> Indoor Mayan Temple -> High Canopy Overpass (+28m!) -> Turquoise Lagoon
## 2. BIO-LAB HYDRO SPEEDWAY  (2,187 m) — Chemical Acid-Vat Bio-Lab -> Giant Half-Pipe Sewer Conduits -> Arctic Ice Exterior -> Reactor Overpass (+20m!)
## 3. COSMIC CITADEL STARWAY  (2,457 m) — Neon Spaceport Hangar -> Orbital Asteroid Nebula City -> Subterranean Magma Mine & 360° Spiral Overpass (+20m!) -> Plasma Half-Pipe

static func get_track_def(track_id: String, mirrored: bool = false) -> Dictionary:
	var def: Dictionary
	match track_id:
		"glacier_peak": def = _biolab_hydro_speedway()
		"volcano_sky": def = _cosmic_citadel_starway()
		_: def = _emerald_temple_circuit()
	if mirrored:
		def = _apply_mirror(def)
	return def

static func _apply_mirror(def: Dictionary) -> Dictionary:
	var m := def.duplicate(true)
	m["mirrored"] = true
	for cp in m["control_points"]:
		var p: Vector3 = cp["pos"]
		cp["pos"] = Vector3(-p.x, p.y, p.z)
		cp["bank"] = -float(cp.get("bank", 0.0))
		var wl := float(cp.get("wall_l", 2.0))
		var wr := float(cp.get("wall_r", 2.0))
		cp["wall_l"] = wr
		cp["wall_r"] = wl
		var ol := float(cp.get("off_l", 0.0))
		var or_w := float(cp.get("off_r", 0.0))
		cp["off_l"] = or_w
		cp["off_r"] = ol
		var hpl := bool(cp.get("halfpipe_l", false))
		var hpr := bool(cp.get("halfpipe_r", false))
		cp["halfpipe_l"] = hpr
		cp["halfpipe_r"] = hpl
	for pd in m.get("turbo_pads", []):
		pd["lateral"] = -float(pd.get("lateral", 0.0))
	for hz in m.get("hazards", []):
		if hz.has("lateral"):
			hz["lateral"] = -float(hz["lateral"])
	for sc in m.get("shortcuts", []):
		sc["launch_lateral"] = -float(sc["launch_lateral"])
		sc["target_lateral"] = -float(sc["target_lateral"])
	for ft in m.get("fruit_trails", []):
		ft["lat"] = -float(ft["lat"])
	for br in m.get("boost_rings", []):
		br["lateral"] = -float(br.get("lateral", 0.0))
	for lm in m.get("hero_landmarks", []):
		var lpos: Vector3 = lm["pos"]
		lm["pos"] = Vector3(-lpos.x, lpos.y, lpos.z)
		lm["rot_y"] = -float(lm.get("rot_y", 0.0))
	for wf in m.get("waterfalls", []):
		var wpos: Vector3 = wf["pos"]
		wf["pos"] = Vector3(-wpos.x, wpos.y, wpos.z)
		wf["rot_y"] = -float(wf.get("rot_y", 0.0))
	return m

# ==============================================================================
# TRACK 1: EMERALD TEMPLE CIRCUIT (~2,185 m, Multi-Biome Over-Under CTR Masterpiece!)
# Zone 1: Golden Jungle Village (Cuttable sand corners, wooden fences, ruins)
# Zone 2: Indoor Mayan Pyramid Hall (Enclosed stone walls, Chomper Plants, 90° climbs, crowned steps)
# Zone 3: High Open-Sided Canopy Timber Trestle (+28m OVERPASS above Zone 1! Narrow & open-sided!)
# Zone 4: Turquoise Waterfall Lagoon & Ruin Hairpins (Moguls, Floating-Stone Double-Hop & Crest Vault!)
# ==============================================================================
static func _emerald_temple_circuit() -> Dictionary:
	return {
		"id": "tiki_cove",
		"theme": "tiki",
		"arch_style": "pyramid",
		"road_tex": "road_tiki",
		"wall_tex": "wall_tiki",
		"offroad_tex": "offroad_tiki",
		"sky_top": Color(0.24, 0.25, 0.48),
		"sky_horizon": Color(1.0, 0.72, 0.38),
		"ground_color": Color(0.12, 0.36, 0.38),
		"sun_color": Color(1.0, 0.88, 0.64),
		"sun_pitch": -20.0,
		"sun_yaw": 18.0,
		"fog_color": Color(0.94, 0.78, 0.56),
		"fog_density": 0.00105,
		"sea_level": -2.0,
		"archways": [
			{"t": 0.075, "glb": "res://assets/models/prop_tiki_arch.glb"},
			{"t": 0.145, "glb": "res://assets/models/prop_tiki_arch.glb"},
			{"t": 0.265, "glb": "res://assets/models/prop_tiki_arch.glb"},
			{"t": 0.605, "glb": "res://assets/models/prop_tiki_arch.glb"},
			{"t": 0.935, "glb": "res://assets/models/prop_tiki_arch.glb"},
		],
		"rope_bridges": [0.05, 0.34, 0.66],
		"canyon_arches": [0.12, 0.57, 0.82],
		"boost_rings": [
			{"t": 0.085, "lateral": 0.0, "height": 4.4},
			{"t": 0.390, "lateral": 0.0, "height": 4.5},
			{"t": 0.775, "lateral": 0.0, "height": 4.5},
		],
		"hero_landmarks": [
			{"glb": "res://assets/models/prop_mayan_pyramid.glb", "pos": Vector3(165, 2.0, -110), "rot_y": 15.0, "scale": 1.85, "radius": 34.0},
			{"glb": "res://assets/models/prop_jungle_ruin.glb", "pos": Vector3(-56, 6.0, 12), "rot_y": 65.0, "scale": 1.35, "radius": 14.0},
			{"glb": "res://assets/models/prop_jungle_ruin.glb", "pos": Vector3(68, 6.5, -14), "rot_y": -72.0, "scale": 1.30, "radius": 14.0},
			{"glb": "res://assets/models/prop_jungle_ruin.glb", "pos": Vector3(175, 11.0, 222), "rot_y": 140.0, "scale": 1.45, "radius": 15.0},
			{"glb": "res://assets/models/prop_pyramid_obelisk.glb", "pos": Vector3(-34, 5.5, -18), "rot_y": 75.0, "scale": 1.30, "radius": 4.5},
			{"glb": "res://assets/models/prop_pyramid_obelisk.glb", "pos": Vector3(34, 5.5, -18), "rot_y": -75.0, "scale": 1.30, "radius": 4.5},
			{"glb": "res://assets/models/prop_pirate_ship.glb", "pos": Vector3(-165, -2.0, 345), "rot_y": 38.0, "scale": 1.35, "radius": 18.0},
		],
		"waterfalls": [
			{"pos": Vector3(-84, 26.0, -136), "rot_y": 55.0, "width": 28.0, "height": 48.0, "lava": false, "multi_stream": true},
			{"pos": Vector3(335, 34.0, -95), "rot_y": -90.0, "width": 26.0, "height": 54.0, "lava": false, "multi_stream": true},
			{"pos": Vector3(-295, 24.0, 185), "rot_y": 76.0, "width": 24.0, "height": 46.0, "lava": false, "multi_stream": true},
		],
		"control_points": [
			# ZONE 1: Golden Jungle Village (Wide Free-Line & Recovery + Flush Cuttable Inner Corners!)
			{"pos": Vector3(0, 6.0, 42), "width": 28.0, "bank": 0.0, "crown": 0.25, "wall_l": 1.9, "wall_r": 1.9, "off_l": 4.5, "off_r": 4.5, "surface": "road", "biome": "jungle_village", "zone": "Jungle Village Plaza"},
			{"pos": Vector3(0, 6.0, -68), "width": 27.0, "bank": 0.0, "crown": 0.35, "wall_l": 1.9, "wall_r": 1.9, "off_l": 4.5, "off_r": 4.5, "surface": "road", "bump_amp": 1.1, "bump_freq": 1.5, "biome": "jungle_village", "zone": "Underpass Avenue"},
			{"pos": Vector3(38, 9.0, -172), "width": 26.0, "bank": -12.0, "crown": 0.30, "wall_l": 2.0, "wall_r": 2.0, "off_l": 3.0, "off_r": 7.5, "surface": "road", "biome": "jungle_village", "zone": "Emerald Cuttable Bend"},

			# ZONE 2: Indoor Mayan Pyramid Hall (Enclosed, Sharp 90° Climbs, Chompers, Crowned Stone Steps!)
			{"pos": Vector3(142, 14.0, -226), "width": 23.0, "bank": -14.0, "crown": 0.45, "wall_l": 3.4, "wall_r": 3.4, "off_l": 0.0, "off_r": 0.0, "surface": "road", "tunnel": true, "rib_amp": 0.22, "rib_freq": 6.0, "biome": "mayan_temple", "zone": "Mayan Temple Hall"},
			{"pos": Vector3(246, 20.0, -182), "width": 23.0, "bank": -16.0, "crown": 0.40, "wall_l": 3.4, "wall_r": 3.4, "off_l": 0.0, "off_r": 0.0, "surface": "road", "tunnel": true, "biome": "mayan_temple", "zone": "Inner Sanctum 90°"},
			{"pos": Vector3(272, 26.0, -74), "width": 22.0, "bank": -14.0, "crown": 0.50, "wall_l": 2.8, "wall_r": 3.2, "off_l": 0.0, "off_r": 0.0, "surface": "road", "bump_amp": 1.3, "bump_freq": 1.5, "biome": "mayan_temple", "zone": "Chomper Ascent"},
			{"pos": Vector3(186, 32.0, -16), "width": 21.0, "bank": 0.0, "crown": 0.35, "wall_l": 2.2, "wall_r": 2.6, "off_l": 0.0, "off_r": 0.0, "surface": "road", "biome": "mayan_temple", "zone": "Pyramid Summit Gate"},

			# ZONE 3: High Open-Sided Canopy Timber Trestle (+28m OVERPASS Crossing Zone 1! Narrow High-Risk!)
			{"pos": Vector3(96, 35.0, -56), "width": 19.0, "bank": 0.0, "crown": 0.0, "wall_l": 0.0, "wall_r": 0.0, "off_l": 0.0, "off_r": 0.0, "surface": "wood", "bridge": true, "biome": "canopy_trestle", "zone": "Sky Canopy Trestle"},
			{"pos": Vector3(0, 34.0, -52), "width": 18.5, "bank": 0.0, "crown": 0.0, "wall_l": 0.0, "wall_r": 0.0, "off_l": 0.0, "off_r": 0.0, "surface": "wood", "bridge": true, "rib_amp": 0.20, "rib_freq": 8.0, "biome": "canopy_trestle", "zone": "Village Overpass (+28m)"},
			{"pos": Vector3(-104, 29.0, -46), "width": 20.0, "bank": -8.0, "crown": 0.25, "wall_l": 0.0, "wall_r": 2.2, "off_l": 0.0, "off_r": 0.0, "surface": "wood", "bridge": true, "biome": "canopy_trestle", "zone": "Western Cliff Plunge"},
			{"pos": Vector3(-196, 22.0, -106), "width": 24.0, "bank": -16.0, "crown": 0.35, "wall_l": 0.0, "wall_r": 2.8, "off_l": 0.0, "off_r": 2.0, "surface": "road", "biome": "canopy_trestle", "zone": "Canopy Chasm Hairpin"},
			{"pos": Vector3(-248, 18.0, -62), "width": 24.0, "bank": -18.0, "crown": 0.40, "wall_l": 0.0, "wall_r": 2.8, "off_l": 0.0, "off_r": 0.0, "surface": "road", "biome": "canopy_trestle", "zone": "Cliffside 180° U-Turn"},
			{"pos": Vector3(-186, 16.0, -24), "width": 25.0, "bank": 10.0, "crown": 0.35, "wall_l": 0.0, "wall_r": 2.4, "off_l": 0.0, "off_r": 4.0, "surface": "road", "biome": "emerald_lagoon", "zone": "Waterfall Descent"},

			# ZONE 4: Turquoise Waterfall Lagoon & Ruin Ridge Hairpins (Cuttable Off-Road, Moguls, Floating Stone Bay!)
			{"pos": Vector3(-244, 12.0, 92), "width": 28.0, "bank": -12.0, "crown": 0.25, "wall_l": 2.0, "wall_r": 2.0, "off_l": 6.5, "off_r": 5.0, "surface": "road", "bump_amp": 1.6, "bump_freq": 2.0, "biome": "emerald_lagoon", "zone": "Lagoon Mogul Basin"},
			{"pos": Vector3(-228, 10.0, 212), "width": 26.0, "bank": -14.0, "crown": 0.20, "wall_l": 0.0, "wall_r": 2.2, "off_l": 0.0, "off_r": 4.0, "surface": "road", "biome": "emerald_lagoon", "zone": "Floating-Stone Bay"},
			{"pos": Vector3(-144, 9.0, 286), "width": 26.0, "bank": -16.0, "crown": 0.30, "wall_l": 0.0, "wall_r": 2.4, "off_l": 0.0, "off_r": 5.0, "surface": "road", "biome": "emerald_lagoon", "zone": "Pirate Cove U-Turn"},
			{"pos": Vector3(-104, 11.0, 198), "width": 26.0, "bank": 12.0, "crown": 0.30, "wall_l": 0.0, "wall_r": 2.2, "off_l": 0.0, "off_r": 4.5, "surface": "road", "biome": "emerald_lagoon", "zone": "Lagoon East Bank"},
			{"pos": Vector3(18, 15.0, 228), "width": 25.0, "bank": -10.0, "crown": 0.55, "wall_l": 2.0, "wall_r": 2.2, "off_l": 4.0, "off_r": 3.0, "surface": "road", "rib_amp": 0.22, "rib_freq": 6.0, "biome": "emerald_lagoon", "zone": "Crowned Ruin Causeway"},
			{"pos": Vector3(108, 17.0, 232), "width": 24.0, "bank": -17.0, "crown": 0.60, "wall_l": 0.0, "wall_r": 2.6, "off_l": 0.0, "off_r": 2.0, "surface": "road", "biome": "emerald_lagoon", "zone": "Temple Crest Hairpin"},
			{"pos": Vector3(84, 14.0, 162), "width": 25.0, "bank": 14.0, "crown": 0.45, "wall_l": 0.0, "wall_r": 2.2, "off_l": 0.0, "off_r": 5.5, "surface": "road", "biome": "jungle_village", "zone": "Ruin Crest Rejoin"},
			{"pos": Vector3(42, 8.5, 118), "width": 26.0, "bank": -10.0, "crown": 0.20, "wall_l": 2.0, "wall_r": 2.0, "off_l": 5.5, "off_r": 5.5, "surface": "road", "biome": "jungle_village", "zone": "Village Final Chicane"},
			{"pos": Vector3(2, 6.2, 112), "width": 28.0, "bank": 0.0, "crown": 0.20, "wall_l": 1.9, "wall_r": 1.9, "off_l": 4.5, "off_r": 4.5, "surface": "road", "biome": "jungle_village", "zone": "Temple Finish Straight"},
		],
		"turbo_pads": [
			{"t": 0.065, "lateral": -4.5, "super": false},
			{"t": 0.245, "lateral": 4.0, "super": false},
			{"t": 0.375, "lateral": 0.0, "super": false},  # On High Canopy Trestle!
			{"t": 0.470, "lateral": -4.5, "super": false}, # Fuels Canopy Chasm Corner-Cut 1A!
			{"t": 0.665, "lateral": -4.5, "super": false}, # Fuels Floating-Stone Double-Hop 1B!
			{"t": 0.835, "lateral": -4.0, "super": false}, # Fuels Pyramid Crest Parapet Vault 1C!
			{"t": 0.960, "lateral": 3.5, "super": false},
		],
		"hazards": [
			{"kind": "chomper", "t": 0.160, "lateral": 10.2, "speed": 2.1, "phase": 0.0},
			{"kind": "chomper", "t": 0.220, "lateral": -10.2, "speed": 2.3, "phase": 0.4},
			{"kind": "chomper", "t": 0.295, "lateral": 9.8, "speed": 2.2, "phase": 0.7},
			{"kind": "boulder", "t": 0.595, "span": 9.5, "speed": 1.45, "phase": 0.2},
			{"kind": "chomper", "t": 0.785, "lateral": 10.4, "speed": 2.1, "phase": 0.5},
			{"kind": "pendulum", "t": 0.915, "speed": 1.55, "phase": 0.0},
		],
		"shortcuts": [
			{
				# 1A: PURE CHASM LEAP (Road -> Void 41m -> Main Road! Saves 68m!)
				"id": "emerald_canopy_leap",
				"name_en": "Canopy Chasm Corner-Cut",
				"name_ar": "قفزة كسر منعطف الوادي",
				"jump_type": "chasm_leap",
				"required_fire": 3,
				"launch_t": 0.502,
				"launch_lateral": -10.5,
				"target_t": 0.552,
				"target_lateral": -10.0,
				"kicker_pitch_deg": 19.5,
				"kicker_width": 6.4,
				"kicker_length": 7.5
			},
			{
				# 1B: FLOATING STEPPING-STONE DOUBLE-HOP (Road -> 27.5m Void -> Floating Pad -> 27.5m Void -> Main Road!)
				"id": "emerald_island_doublehop",
				"name_en": "Lagoon Floating-Stone Double Hop",
				"name_ar": "الوثبة المزدوجة على الصخرة العائمة",
				"jump_type": "stepping_island",
				"required_fire": 3,
				"launch_t": 0.700,
				"launch_lateral": -10.5,
				"target_t": 0.767,
				"target_lateral": -10.0,
				"kicker_pitch_deg": 18.5,
				"kicker_width": 6.6,
				"kicker_length": 7.5
			},
			{
				# 1C: HIGH CREST VAULT (Road Crest -> 41.2m Aerial Cut -> Main Road!)
				"id": "emerald_pyramid_vault",
				"name_en": "Pyramid Crest Parapet Vault",
				"name_ar": "قفزة حافة قمة المعبد",
				"jump_type": "crest_vault",
				"required_fire": 2,
				"launch_t": 0.863,
				"launch_lateral": -10.5,
				"target_t": 0.905,
				"target_lateral": -10.0,
				"kicker_pitch_deg": 20.5,
				"kicker_width": 6.4,
				"kicker_length": 7.5
			}
		],
		"crate_rows": [0.05, 0.21, 0.36, 0.58, 0.79, 0.93],
		"fruit_trails": [
			{"t0": 0.02, "t1": 0.045, "lat": 3.5, "count": 5},
			{"t0": 0.17, "t1": 0.20, "lat": -3.5, "count": 5},
			{"t0": 0.38, "t1": 0.41, "lat": 0.0, "count": 5},
			{"t0": 0.61, "t1": 0.64, "lat": 4.0, "count": 5},
			{"t0": 0.80, "t1": 0.83, "lat": -3.5, "count": 5}
		]
	}

# ==============================================================================
# TRACK 2: BIO-LAB HYDRO SPEEDWAY (~2,187 m, Multi-Biome Chemical Lab + Sewer + Arctic!)
# Zone 1: Chemical Research Bio-Lab (Enclosed hi-tech grating, glowing acid vats, Acid-Vat Leap 2A!)
# Zone 2: Giant Cylindrical Half-Pipe Hydro-Conduits (Curved wall riding, Rolling Iron Barrels!)
# Zone 3: Open Twilight Arctic Coolant Exterior (Slippery Ice lake, Cuttable Snow, Frost Geysers, Floating Pad 2B!)
# Zone 4: Elevated Steel Reactor Overpass (+20m OVER Bio-Lab! Narrow open-sided + Pendulums + Final Crest Vault 2C!)
# ==============================================================================
static func _biolab_hydro_speedway() -> Dictionary:
	return {
		"id": "glacier_peak",
		"theme": "glacier",
		"arch_style": "sewer",
		"road_tex": "road_glacier",
		"wall_tex": "wall_glacier",
		"offroad_tex": "offroad_snow",
		"sky_top": Color(0.05, 0.13, 0.30),
		"sky_horizon": Color(0.26, 0.74, 0.86),
		"ground_color": Color(0.14, 0.34, 0.48),
		"sun_color": Color(0.96, 0.92, 0.82),
		"sun_pitch": -24.0,
		"sun_yaw": 26.0,
		"fog_color": Color(0.42, 0.72, 0.86),
		"fog_density": 0.00095,
		"sea_level": 0.0,
		"archways": [
			{"t": 0.045, "glb": "res://assets/models/prop_lab_arch.glb"},
			{"t": 0.140, "glb": "res://assets/models/prop_lab_arch.glb"},
			{"t": 0.245, "glb": "res://assets/models/prop_sewer_arch.glb"},
			{"t": 0.310, "glb": "res://assets/models/prop_sewer_arch.glb"},
			{"t": 0.625, "glb": "res://assets/models/prop_ice_arch.glb"},
			{"t": 0.820, "glb": "res://assets/models/prop_lab_arch.glb"},
			{"t": 0.910, "glb": "res://assets/models/prop_sewer_arch.glb"},
		],
		"rope_bridges": [0.45, 0.68],
		"canyon_arches": [0.56],
		"boost_rings": [
			{"t": 0.080, "lateral": 0.0, "height": 4.6},
			{"t": 0.560, "lateral": 0.0, "height": 4.8},
			{"t": 0.875, "lateral": 0.0, "height": 4.6},
		],
		"hero_landmarks": [
			{"glb": "res://assets/models/prop_lab_vat.glb", "pos": Vector3(-34, 11.0, -34), "rot_y": 25.0, "scale": 2.2, "radius": 7.5},
			{"glb": "res://assets/models/prop_lab_vat.glb", "pos": Vector3(36, 11.0, -34), "rot_y": -25.0, "scale": 2.2, "radius": 7.5},
			{"glb": "res://assets/models/prop_lab_vat.glb", "pos": Vector3(-118, 9.0, -238), "rot_y": 80.0, "scale": 2.4, "radius": 8.0},
			{"glb": "res://assets/models/prop_alpine_lodge.glb", "pos": Vector3(-28, 12.0, 315), "rot_y": 170.0, "scale": 1.60, "radius": 12.5},
			{"glb": "res://assets/models/prop_alpine_lodge.glb", "pos": Vector3(95, 14.0, 295), "rot_y": -145.0, "scale": 1.55, "radius": 12.0},
		],
		"waterfalls": [
			{"pos": Vector3(-315, 28.0, 155), "rot_y": 84.0, "width": 26.0, "height": 48.0, "lava": false, "multi_stream": true},
			{"pos": Vector3(235, 32.0, 130), "rot_y": -92.0, "width": 24.0, "height": 48.0, "lava": false, "multi_stream": true},
		],
		"control_points": [
			# ZONE 1: Chemical Research Bio-Lab (Enclosed Indoor Metal Grating + Glowing Acid Vats!)
			{"pos": Vector3(0, 14.0, 42), "width": 27.0, "bank": 0.0, "crown": 0.20, "wall_l": 3.4, "wall_r": 3.4, "off_l": 0.0, "off_r": 0.0, "surface": "biolab", "tunnel": true, "biome": "bio_lab", "zone": "Bio-Lab Sector Alpha"},
			{"pos": Vector3(0, 11.0, -68), "width": 26.0, "bank": 0.0, "crown": 0.30, "wall_l": 3.4, "wall_r": 3.4, "off_l": 0.0, "off_r": 0.0, "surface": "biolab", "tunnel": true, "rib_amp": 0.20, "rib_freq": 6.0, "biome": "bio_lab", "zone": "Acid-Vat Underpass"},
			{"pos": Vector3(-62, 9.0, -158), "width": 25.0, "bank": -14.0, "crown": 0.35, "wall_l": 0.0, "wall_r": 3.4, "off_l": 0.0, "off_r": 0.0, "surface": "biolab", "biome": "bio_lab", "zone": "Containment Bend"},
			{"pos": Vector3(-146, 9.0, -192), "width": 24.0, "bank": -18.0, "crown": 0.35, "wall_l": 0.0, "wall_r": 3.4, "off_l": 0.0, "off_r": 0.0, "surface": "biolab", "biome": "bio_lab", "zone": "Vat 180° Hairpin"},
			{"pos": Vector3(-122, 11.0, -124), "width": 25.0, "bank": 10.0, "crown": 0.25, "wall_l": 0.0, "wall_r": 3.2, "off_l": 0.0, "off_r": 0.0, "surface": "biolab", "biome": "bio_lab", "zone": "Bio-Sluice Exit"},

			# ZONE 2: Giant Cylindrical Half-Pipe Hydro-Conduits (Curved Half-Pipe Walls + Rolling Iron Barrels!)
			{"pos": Vector3(-228, 12.0, -72), "width": 26.0, "bank": 0.0, "crown": 0.0, "wall_l": 0.0, "wall_r": 0.0, "off_l": 0.0, "off_r": 0.0, "surface": "road", "halfpipe_l": true, "halfpipe_r": true, "biome": "hydro_sewer", "zone": "Hydro Half-Pipe 1"},
			{"pos": Vector3(-268, 13.0, 46), "width": 27.0, "bank": 0.0, "crown": 0.0, "wall_l": 0.0, "wall_r": 0.0, "off_l": 0.0, "off_r": 0.0, "surface": "road", "halfpipe_l": true, "halfpipe_r": true, "bump_amp": 1.4, "bump_freq": 1.5, "biome": "hydro_sewer", "zone": "Rolling Barrel Conduit"},

			# ZONE 3: Open Twilight Arctic Coolant Exterior (Slippery Ice, Wide Cuttable Snow, Frost Geysers!)
			{"pos": Vector3(-206, 11.0, 148), "width": 28.0, "bank": -12.0, "crown": 0.25, "wall_l": 2.0, "wall_r": 2.0, "off_l": 7.0, "off_r": 5.5, "surface": "ice", "biome": "arctic_exterior", "zone": "Arctic Coolant Gate"},
			{"pos": Vector3(-242, 9.0, 254), "width": 28.0, "bank": -15.0, "crown": 0.20, "wall_l": 0.0, "wall_r": 2.2, "off_l": 0.0, "off_r": 6.0, "surface": "ice", "biome": "arctic_exterior", "zone": "Frozen Lake West"},
			{"pos": Vector3(-156, 8.0, 324), "width": 30.0, "bank": -14.0, "crown": 0.25, "wall_l": 0.0, "wall_r": 2.2, "off_l": 0.0, "off_r": 7.0, "surface": "ice", "bump_amp": 1.6, "bump_freq": 2.0, "biome": "arctic_exterior", "zone": "Geyser Cryo-Basin"},
			{"pos": Vector3(-114, 10.0, 234), "width": 27.0, "bank": 10.0, "crown": 0.25, "wall_l": 0.0, "wall_r": 2.2, "off_l": 0.0, "off_r": 5.0, "surface": "ice", "biome": "arctic_exterior", "zone": "Frozen Lake East"},
			{"pos": Vector3(16, 14.0, 246), "width": 26.0, "bank": -10.0, "crown": 0.45, "wall_l": 2.0, "wall_r": 2.0, "off_l": 6.0, "off_r": 6.0, "surface": "road", "biome": "arctic_exterior", "zone": "Research Station Village"},

			# ZONE 4: High Narrow Open-Sided Reactor Overpass (+20m OVER Bio-Lab!) -> Half-Pipe Finish Sprint!
			{"pos": Vector3(138, 22.0, 206), "width": 23.0, "bank": -14.0, "crown": 0.40, "wall_l": 2.4, "wall_r": 2.6, "off_l": 0.0, "off_r": 0.0, "surface": "biolab", "rib_amp": 0.24, "rib_freq": 6.0, "biome": "reactor_overpass", "zone": "Reactor Climb"},
			{"pos": Vector3(178, 30.0, 96), "width": 20.0, "bank": -12.0, "crown": 0.0, "wall_l": 0.0, "wall_r": 0.0, "off_l": 0.0, "off_r": 0.0, "surface": "biolab", "bridge": true, "biome": "reactor_overpass", "zone": "Elevated Reactor Deck"},
			{"pos": Vector3(96, 32.0, -46), "width": 19.0, "bank": 0.0, "crown": 0.0, "wall_l": 0.0, "wall_r": 0.0, "off_l": 0.0, "off_r": 0.0, "surface": "biolab", "bridge": true, "biome": "reactor_overpass", "zone": "Reactor Skyway"},
			{"pos": Vector3(0, 31.0, -56), "width": 19.0, "bank": 0.0, "crown": 0.0, "wall_l": 0.0, "wall_r": 0.0, "off_l": 0.0, "off_r": 0.0, "surface": "biolab", "bridge": true, "biome": "reactor_overpass", "zone": "Bio-Lab Overpass (+20m)"},
			{"pos": Vector3(-76, 25.0, 42), "width": 25.0, "bank": 12.0, "crown": 0.0, "wall_l": 0.0, "wall_r": 0.0, "off_l": 0.0, "off_r": 0.0, "surface": "road", "halfpipe_l": true, "halfpipe_r": true, "biome": "hydro_sewer", "zone": "Descent Half-Pipe"},
			{"pos": Vector3(-88, 20.0, 146), "width": 26.0, "bank": -16.0, "crown": 0.35, "wall_l": 0.0, "wall_r": 0.0, "off_l": 0.0, "off_r": 0.0, "surface": "ice", "halfpipe_l": true, "halfpipe_r": true, "biome": "hydro_sewer", "zone": "Cryo-Pipe Hairpin"},
			{"pos": Vector3(-14, 17.0, 134), "width": 26.0, "bank": 14.0, "crown": 0.45, "wall_l": 0.0, "wall_r": 2.4, "off_l": 0.0, "off_r": 2.0, "surface": "road", "biome": "hydro_sewer", "zone": "Final Conduit S-Turn"},
			{"pos": Vector3(36, 15.0, 76), "width": 26.0, "bank": -10.0, "crown": 0.25, "wall_l": 0.0, "wall_r": 2.4, "off_l": 0.0, "off_r": 2.0, "surface": "biolab", "biome": "bio_lab", "zone": "Lab Finish Approach"},
		],
		"turbo_pads": [
			{"t": 0.070, "lateral": -4.5, "super": false}, # Fuels Acid-Vat Containment Leap 2A!
			{"t": 0.265, "lateral": 5.0, "super": false},  # Half-Pipe Barrel Gauntlet Pad!
			{"t": 0.385, "lateral": -5.0, "super": true},  # BLUE FIRE SUPER PAD -> Fuels Floating Pad Double-Hop 2B!
			{"t": 0.610, "lateral": 0.0, "super": false},  # Research Village Climb Pad!
			{"t": 0.745, "lateral": 0.0, "super": true},   # BLUE FIRE SUPER PAD on High Reactor Overpass!
			{"t": 0.920, "lateral": -4.5, "super": false}, # Fuels Final Half-Pipe Ice Crest Vault 2C!
		],
		"hazards": [
			{"kind": "barrel", "t": 0.255, "span": 10.2, "speed": 1.50, "phase": 0.0},
			{"kind": "barrel", "t": 0.320, "span": 10.2, "speed": 1.70, "phase": 1.9},
			{"kind": "frost_geyser", "t": 0.445, "lateral": -4.2, "period": 3.4, "phase": 0.0},
			{"kind": "frost_geyser", "t": 0.475, "lateral": 4.2, "period": 3.4, "phase": 1.7},
			{"kind": "pendulum", "t": 0.695, "speed": 1.65, "phase": 0.4},
			{"kind": "barrel", "t": 0.840, "span": 10.0, "speed": 1.65, "phase": 0.8},
		],
		"shortcuts": [
			{
				# 2A: PURE CHASM LEAP over Acid-Vat Hairpin (41.5m gap, saves 112m!)
				"id": "biolab_vat_leap",
				"name_en": "Acid-Vat Containment Leap",
				"name_ar": "قفزة أحواض المختبر السرية",
				"jump_type": "chasm_leap",
				"required_fire": 3,
				"launch_t": 0.102,
				"launch_lateral": -10.5,
				"target_t": 0.172,
				"target_lateral": -10.0,
				"kicker_pitch_deg": 20.5,
				"kicker_width": 6.4,
				"kicker_length": 7.5
			},
			{
				# 2B: FLOATING STEPPING-STONE PAD DOUBLE-HOP across Frozen Lake (71.9m total -> ~28.5m + Island + ~28.5m!)
				"id": "biolab_floating_pad",
				"name_en": "Hydro-Core Floating Pad Double Hop",
				"name_ar": "الوثبة المزدوجة على المنصة العائمة",
				"jump_type": "stepping_island",
				"required_fire": 4,
				"launch_t": 0.415,
				"launch_lateral": -10.5,
				"target_t": 0.480,
				"target_lateral": -10.0,
				"kicker_pitch_deg": 19.5,
				"kicker_width": 6.6,
				"kicker_length": 7.5
			},
			{
				# 2C: HALF-PIPE ICE CREST VAULT straight onto Finish Approach (43.6m gap!)
				"id": "biolab_glacier_vault",
				"name_en": "Half-Pipe Ice Crest Vault",
				"name_ar": "قفزة قمة النفق الجليدي",
				"jump_type": "crest_vault",
				"required_fire": 3,
				"launch_t": 0.952,
				"launch_lateral": -10.5,
				"target_t": 0.990,
				"target_lateral": -10.0,
				"kicker_pitch_deg": 20.0,
				"kicker_width": 6.4,
				"kicker_length": 7.5
			}
		],
		"crate_rows": [0.05, 0.22, 0.39, 0.56, 0.77, 0.90],
		"fruit_trails": [
			{"t0": 0.02, "t1": 0.045, "lat": -4.0, "count": 5},
			{"t0": 0.27, "t1": 0.30, "lat": 4.5, "count": 5},
			{"t0": 0.50, "t1": 0.535, "lat": 0.0, "count": 5},
			{"t0": 0.72, "t1": 0.75, "lat": 0.0, "count": 5},
			{"t0": 0.87, "t1": 0.895, "lat": 4.0, "count": 5}
		]
	}

# ==============================================================================
# TRACK 3: COSMIC CITADEL STARWAY (~2,457 m, Multi-Biome Spaceport + Asteroid Nebula + Magma Mine!)
# Zone 1: Neon Futuristic Spaceport Hangar (Indoor cyber-arches, glowing purple-cyan highway!)
# Zone 2: Open Cosmic Asteroid Nebula & Orbital City Skyline (Narrow zero-G starway, Floating Island 3A + Chasm Leap 3B!)
# Zone 3: Subterranean Volcanic Magma Mine & 360° Elevated Wooden Spiral (+20m OVER Lava Cavern! Roaring Mine Carts!)
# Zone 4: Plasma Half-Pipe & Spaceport Warp Return (Magma Crest Vault 3C!)
# ==============================================================================
static func _cosmic_citadel_starway() -> Dictionary:
	return {
		"id": "volcano_sky",
		"theme": "volcano",
		"arch_style": "space",
		"road_tex": "road_space",
		"wall_tex": "wall_space",
		"offroad_tex": "offroad_space",
		"sky_top": Color(0.05, 0.03, 0.16),
		"sky_horizon": Color(0.76, 0.24, 0.42),
		"ground_color": Color(0.84, 0.24, 0.06),
		"sun_color": Color(1.0, 0.82, 0.62),
		"sun_pitch": -20.0,
		"sun_yaw": 24.0,
		"fog_color": Color(0.32, 0.16, 0.38),
		"fog_density": 0.00085,
		"sea_level": -14.0,
		"archways": [
			{"t": 0.035, "glb": "res://assets/models/prop_space_arch.glb"},
			{"t": 0.095, "glb": "res://assets/models/prop_space_arch.glb"},
			{"t": 0.445, "glb": "res://assets/models/prop_mine_beam.glb"},
			{"t": 0.515, "glb": "res://assets/models/prop_mine_beam.glb"},
			{"t": 0.720, "glb": "res://assets/models/prop_volcano_arch.glb"},
			{"t": 0.865, "glb": "res://assets/models/prop_space_arch.glb"},
			{"t": 0.960, "glb": "res://assets/models/prop_space_arch.glb"},
		],
		"rope_bridges": [0.47, 0.67],
		"canyon_arches": [0.55],
		"boost_rings": [
			{"t": 0.075, "lateral": 0.0, "height": 4.6},
			{"t": 0.415, "lateral": 0.0, "height": 4.8},
			{"t": 0.775, "lateral": 0.0, "height": 4.8},
		],
		"hero_landmarks": [
			{"glb": "res://assets/models/prop_space_tower.glb", "pos": Vector3(-56, 4.0, -32), "rot_y": 25.0, "scale": 1.65, "radius": 11.0},
			{"glb": "res://assets/models/prop_space_tower.glb", "pos": Vector3(62, 4.0, -40), "rot_y": -30.0, "scale": 1.75, "radius": 11.5},
			{"glb": "res://assets/models/prop_space_tower.glb", "pos": Vector3(132, 8.0, -285), "rot_y": 15.0, "scale": 2.10, "radius": 13.0},
			{"glb": "res://assets/models/prop_space_tower.glb", "pos": Vector3(335, 10.0, -45), "rot_y": -85.0, "scale": 1.95, "radius": 12.5},
			{"glb": "res://assets/models/prop_asteroid.glb", "pos": Vector3(235, 48.0, -162), "rot_y": 40.0, "scale": 2.2, "radius": 14.0},
			{"glb": "res://assets/models/prop_asteroid.glb", "pos": Vector3(325, 42.0, 125), "rot_y": -55.0, "scale": 2.4, "radius": 15.0},
		],
		"waterfalls": [
			{"pos": Vector3(-55, 32.0, 325), "rot_y": 170.0, "width": 26.0, "height": 54.0, "lava": true, "multi_stream": true},
			{"pos": Vector3(-320, 34.0, 185), "rot_y": 82.0, "width": 24.0, "height": 52.0, "lava": true, "multi_stream": true},
		],
		"control_points": [
			# ZONE 1: Futuristic Neon Spaceport Hangar (Wide Enclosed Launchway -> Rapid Cyber S-Entry!)
			{"pos": Vector3(0, 24.0, 44), "width": 28.0, "bank": 0.0, "crown": 0.20, "wall_l": 3.4, "wall_r": 3.4, "off_l": 0.0, "off_r": 0.0, "surface": "space", "tunnel": true, "biome": "space_hangar", "zone": "Spaceport Hangar 01"},
			{"pos": Vector3(0, 24.0, -76), "width": 26.0, "bank": 0.0, "crown": 0.30, "wall_l": 3.4, "wall_r": 3.4, "off_l": 0.0, "off_r": 0.0, "surface": "space", "tunnel": true, "rib_amp": 0.20, "rib_freq": 6.0, "biome": "space_hangar", "zone": "Warp Launch Tube"},

			# ZONE 2: Open Cosmic Asteroid Nebula & Orbital City Skyline (Open-Sided Zero-G Ribbon + Floating Pad 3A + Chasm Leap 3B!)
			{"pos": Vector3(68, 28.0, -172), "width": 22.0, "bank": -14.0, "crown": 0.25, "wall_l": 0.0, "wall_r": 0.0, "off_l": 0.0, "off_r": 0.0, "surface": "space", "bridge": true, "biome": "asteroid_nebula", "zone": "Orbital City Starway"},
			{"pos": Vector3(184, 32.0, -212), "width": 21.0, "bank": -16.0, "crown": 0.25, "wall_l": 2.0, "wall_r": 0.0, "off_l": 0.0, "off_r": 0.0, "surface": "space", "bridge": true, "biome": "asteroid_nebula", "zone": "Asteroid Bay West"},
			{"pos": Vector3(272, 34.0, -152), "width": 22.0, "bank": -18.0, "crown": 0.30, "wall_l": 2.0, "wall_r": 0.0, "off_l": 0.0, "off_r": 0.0, "surface": "space", "bridge": true, "biome": "asteroid_nebula", "zone": "Nebula 180° Rim"},
			{"pos": Vector3(194, 32.0, -102), "width": 22.0, "bank": 12.0, "crown": 0.25, "wall_l": 2.0, "wall_r": 0.0, "off_l": 0.0, "off_r": 0.0, "surface": "space", "bridge": true, "biome": "asteroid_nebula", "zone": "Asteroid Bay Return"},
			{"pos": Vector3(266, 28.0, 16), "width": 19.5, "bank": -14.0, "crown": 0.30, "wall_l": 0.0, "wall_r": 0.0, "off_l": 0.0, "off_r": 0.0, "surface": "space", "bridge": true, "biome": "asteroid_nebula", "zone": "Zero-G Star Ribbon"},
			{"pos": Vector3(244, 24.0, 102), "width": 20.5, "bank": -18.0, "crown": 0.30, "wall_l": 2.2, "wall_r": 0.0, "off_l": 0.0, "off_r": 0.0, "surface": "space", "bridge": true, "biome": "asteroid_nebula", "zone": "Nebula Hairpin Apex"},
			{"pos": Vector3(178, 22.0, 62), "width": 22.0, "bank": 12.0, "crown": 0.25, "wall_l": 2.0, "wall_r": 0.0, "off_l": 0.0, "off_r": 0.0, "surface": "space", "bridge": true, "biome": "asteroid_nebula", "zone": "Crater Drop Gate"},

			# ZONE 3: Dramatic Plunge into Subterranean Volcanic Magma Mine & 360° Elevated Wooden Spiral (+20m OVERPASS!)
			{"pos": Vector3(124, 14.0, 186), "width": 26.0, "bank": -10.0, "crown": 0.40, "wall_l": 2.6, "wall_r": 2.6, "off_l": 4.0, "off_r": 4.0, "surface": "volcano", "bump_amp": 1.6, "bump_freq": 1.5, "biome": "magma_mine", "zone": "Magma Crater Plunge"},
			{"pos": Vector3(18, 6.0, 262), "width": 28.0, "bank": -12.0, "crown": 0.35, "wall_l": 2.8, "wall_r": 2.8, "off_l": 6.0, "off_r": 5.0, "surface": "volcano", "biome": "magma_mine", "zone": "Mine-Cart Crossing 1"},
			{"pos": Vector3(-98, 5.0, 228), "width": 27.0, "bank": 0.0, "crown": 0.35, "wall_l": 2.8, "wall_r": 2.8, "off_l": 4.0, "off_r": 4.0, "surface": "volcano", "biome": "magma_mine", "zone": "Lava Cavern Floor"},
			{"pos": Vector3(-196, 8.0, 272), "width": 24.0, "bank": -16.0, "crown": 0.20, "wall_l": 2.4, "wall_r": 0.0, "off_l": 0.0, "off_r": 0.0, "surface": "wood", "bridge": true, "biome": "magma_mine", "zone": "Wooden Spiral Base"},
			{"pos": Vector3(-274, 17.0, 184), "width": 20.5, "bank": -16.0, "crown": 0.0, "wall_l": 2.2, "wall_r": 0.0, "off_l": 0.0, "off_r": 0.0, "surface": "wood", "bridge": true, "rib_amp": 0.20, "rib_freq": 8.0, "biome": "magma_mine", "zone": "360° Spiral Climb"},
			{"pos": Vector3(-218, 25.0, 96), "width": 20.0, "bank": -14.0, "crown": 0.0, "wall_l": 0.0, "wall_r": 0.0, "off_l": 0.0, "off_r": 0.0, "surface": "wood", "bridge": true, "biome": "magma_mine", "zone": "Spiral Summit"},
			{"pos": Vector3(-98, 25.0, 228), "width": 19.5, "bank": 0.0, "crown": 0.0, "wall_l": 0.0, "wall_r": 0.0, "off_l": 0.0, "off_r": 0.0, "surface": "wood", "bridge": true, "biome": "magma_mine", "zone": "Magma Overpass (+20m)"},

			# ZONE 4: High-Speed Plasma Half-Pipe & Spaceport Docking Final Return (Crest Vault 3C!)
			{"pos": Vector3(-88, 23.0, 86), "width": 26.0, "bank": 0.0, "crown": 0.0, "wall_l": 0.0, "wall_r": 0.0, "off_l": 0.0, "off_r": 0.0, "surface": "space", "halfpipe_l": true, "halfpipe_r": true, "biome": "plasma_conduit", "zone": "Plasma Half-Pipe"},
			{"pos": Vector3(-188, 21.0, -24), "width": 25.0, "bank": 14.0, "crown": 0.45, "wall_l": 2.6, "wall_r": 0.0, "off_l": 0.0, "off_r": 0.0, "surface": "space", "biome": "plasma_conduit", "zone": "Plasma S-Chicane"},
			{"pos": Vector3(-144, 20.0, -112), "width": 25.0, "bank": 18.0, "crown": 0.50, "wall_l": 2.6, "wall_r": 0.0, "off_l": 0.0, "off_r": 0.0, "surface": "space", "biome": "plasma_conduit", "zone": "Warp Crest Hairpin"},
			{"pos": Vector3(-76, 22.0, -52), "width": 26.0, "bank": -12.0, "crown": 0.35, "wall_l": 2.4, "wall_r": 0.0, "off_l": 2.0, "off_r": 0.0, "surface": "space", "biome": "space_hangar", "zone": "Spaceport Docking"},
			{"pos": Vector3(-22, 24.0, 48), "width": 27.0, "bank": 0.0, "crown": 0.20, "wall_l": 2.8, "wall_r": 2.8, "off_l": 0.0, "off_r": 0.0, "surface": "space", "biome": "space_hangar", "zone": "Citadel Finish Gate"},
		],
		"turbo_pads": [
			{"t": 0.060, "lateral": 0.0, "super": false},  # Spaceport Launch Pad!
			{"t": 0.130, "lateral": 4.0, "super": true},   # BLUE FIRE SUPER PAD -> Fuels Asteroid Stepping-Pad 3A!
			{"t": 0.280, "lateral": 4.0, "super": true},   # BLUE FIRE SUPER PAD -> Fuels Zero-G Nebula Cut 3B!
			{"t": 0.490, "lateral": -4.0, "super": false}, # Lava Cavern Floor Pad!
			{"t": 0.700, "lateral": 0.0, "super": true},   # BLUE FIRE SUPER PAD on High Spiral Overpass!
			{"t": 0.855, "lateral": 4.5, "super": false},  # Fuels Magma/Warp Crest Vault 3C!
		],
		"hazards": [
			{"kind": "pendulum", "t": 0.105, "speed": 1.65, "phase": 0.0},
			{"kind": "mine_cart", "t": 0.480, "span": 13.5, "speed": 1.75, "phase": 0.0},
			{"kind": "mine_cart", "t": 0.530, "span": 13.0, "speed": 1.90, "phase": 2.1},
			{"kind": "flame_vent", "t": 0.575, "lateral": -3.8, "period": 3.2, "phase": 0.0},
			{"kind": "flame_vent", "t": 0.610, "lateral": 4.2, "period": 3.2, "phase": 1.6},
			{"kind": "barrel", "t": 0.790, "span": 10.5, "speed": 1.70, "phase": 0.6},
		],
		"shortcuts": [
			{
				# 3A: ASTEROID FLOATING STEPPING-STONE DOUBLE-HOP (71.7m total -> ~28.5m + Island + ~28.5m! Saves 100m!)
				"id": "cosmic_asteroid_island",
				"name_en": "Asteroid Stepping-Pad Double Hop",
				"name_ar": "وثبة الكويكب العائم المزدوجة",
				"jump_type": "stepping_island",
				"required_fire": 3,
				"launch_t": 0.152,
				"launch_lateral": 10.5,
				"target_t": 0.223,
				"target_lateral": 10.0,
				"kicker_pitch_deg": 19.5,
				"kicker_width": 6.6,
				"kicker_length": 7.5
			},
			{
				# 3B: ZERO-G NEBULA HAIRPIN CHASM LEAP (43.1m gap across open space! Saves 55m!)
				"id": "cosmic_nebula_cut",
				"name_en": "Zero-G Nebula Hairpin Cut",
				"name_ar": "قفزة كسر منعطف السديم",
				"jump_type": "chasm_leap",
				"required_fire": 4,
				"launch_t": 0.305,
				"launch_lateral": 10.5,
				"target_t": 0.345,
				"target_lateral": 10.0,
				"kicker_pitch_deg": 20.0,
				"kicker_width": 6.4,
				"kicker_length": 7.5
			},
			{
				# 3C: MAGMA/PLASMA CREST VAULT directly onto Spaceport Docking (43.3m gap!)
				"id": "cosmic_magma_vault",
				"name_en": "Magma Spiral Crest Vault",
				"name_ar": "قفزة قمة لولب الصهارة",
				"jump_type": "crest_vault",
				"required_fire": 3,
				"launch_t": 0.885,
				"launch_lateral": 10.5,
				"target_t": 0.915,
				"target_lateral": 10.0,
				"kicker_pitch_deg": 21.0,
				"kicker_width": 6.4,
				"kicker_length": 7.5
			}
		],
		"crate_rows": [0.05, 0.23, 0.42, 0.56, 0.74, 0.93],
		"fruit_trails": [
			{"t0": 0.02, "t1": 0.045, "lat": 4.0, "count": 5},
			{"t0": 0.24, "t1": 0.27, "lat": -3.5, "count": 5},
			{"t0": 0.45, "t1": 0.48, "lat": 0.0, "count": 5},
			{"t0": 0.65, "t1": 0.68, "lat": 0.0, "count": 5},
			{"t0": 0.80, "t1": 0.835, "lat": -4.0, "count": 5}
		]
	}
