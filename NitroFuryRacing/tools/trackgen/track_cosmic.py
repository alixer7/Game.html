"""Track 3 - COSMIC CITADEL STARWAY (id volcano_sky)

A neon city built on a giant asteroid floating in space:
 Neon Boulevard (start, wide) -> Downtown 90R/90L between towers -> elevated Skyline Highway climbing around
 the Citadel Tower (rooftop shortcut) -> INDOOR Launch Tube (climb) + launch JUMP into space -> Orbital Ring:
 floating glass road over the void with gap JUMPS -> back to the asteroid: trench descent into the INDOOR
 Asteroid Mine (underground, mine carts) -> basalt causeways across the lava crater (flame vents, lava leap)
 -> Plasma Conduit half-pipe climbing back to the city.
"""
from core import Track, build_poly

J = dict


def build():
    T = Track("volcano_sky", "COSMIC CITADEL STARWAY", "طريق القلعة الكونية", start=(0, 10, 0), yaw_deg=0, w=30,
              surf="asphalt", edge_l="fence", edge_r="fence", wall_l=1.2, wall_r=1.2, sh_l=0, sh_r=0,
              biome="city_boulevard", zone="Neon Boulevard", deck="space", theme_wall="concrete")

    def f_start(T):
        T.crates(at=55)
        T.fruit(10, 60, lat=-6, n=6)

    def f_downtown(T):
        d = T.here()
        T.obstacle("neon_pylon", at=d + 20, lat=-4.5, r=1.2, strength="heavy")
        T.obstacle("neon_pylon", at=d + 36, lat=4.5, r=1.2, strength="heavy")

    def f_highway(T):
        d = T.here()
        T.fruit(d + 20, d + 70, lat=4, n=6)
        T.crates(at=d + 100)

    def f_tube(T):
        d = T.here()
        T.pad(lat=0.0, at=d + 30)
        T.hazard("crusher", at=d + 70, lat=-4.0, period=2.8, phase=0.3)

    def f_orbit(T):
        d = T.here()
        T.crates(at=d + 30)
        T.ring(at=d + 90, lat=0.0, h=4.8)

    def f_mine(T):
        d = T.here()
        T.hazard("mine_cart", at=d + 40, span=10.0, speed=1.7, phase=0.0)
        T.hazard("mine_cart", at=d + 110, span=10.0, speed=1.9, phase=2.1)
        T.obstacle("spire", at=d + 75, lat=3.5, r=1.6, strength="heavy")

    def f_causeway(T):
        d = T.here()
        T.hazard("flame_vent", at=d + 20, lat=-3.5, period=3.2, phase=0.0)
        T.hazard("flame_vent", at=d + 45, lat=3.5, period=3.2, phase=1.6)

    def f_conduit(T):
        d = T.here()
        T.hazard("barrel", at=d + 60, span=6.0, speed=1.6, phase=0.5)
        T.fruit(d + 90, d + 130, lat=0, n=6)

    V = [
        J(name="start", p=(0, 0), ops=[("call", f_start), ("s", 70, {"y": 10, "w": 30})]),
        # ---- DOWNTOWN: tight 90 R / 90 L between towers (closed facades) ----
        J(name="dt_r", p=(0, -130), r=18, ease=0.12, keys=J(y=10, w=20),
          attrs=J(zone="Downtown Block", surf="asphalt", edge_l="wall", edge_r="wall", wall_l=3.0, wall_r=3.0,
                  biome="city_downtown", theme_wall="space"),
          ops=[("call", f_downtown)]),
        J(name="dt_l", p=(64, -130), r=18, ease=0.12, keys=J(y=10, w=20),
          ops=[("s", 12),
               # ---- SKYLINE HIGHWAY: elevated, open, climbing sweepers ----
               ("call", lambda T: T.zone("Skyline Highway", surf="neon", ground="elevated", edge_l="rail",
                                         edge_r="rail", wall_l=1.1, wall_r=1.1, biome="city_highway", deck="space",
                                         theme_wall="", auto_bank=280)),
               ("call", f_highway), ("fill", {"y": 16, "w": 24})]),
        J(name="hw_a", p=(64, -250), r=60, ease=0.3, keys=J(y=22, w=24)),
        J(name="hw_b", p=(250, -300), r=78, ease=0.3, keys=J(y=30, w=24), mark_in="tower_in", mark="tower_out",
          ops=[("s", 20),
               # ---- LAUNCH TUBE (indoor, climbing) ----
               ("call", lambda T: T.zone("Launch Tube", surf="neon", ground="indoor", ceil=10.0, edge_l="wall",
                                         edge_r="wall", wall_l=10, wall_r=10, biome="space_tube", auto_bank=0)),
               ("call", f_tube), ("fill", {"y": 38, "w": 20})]),
        J(name="tube_e", p=(322, -96), r=40, keys=J(y=40, w=20),
          ops=[("s", 40, {"y": 41}),
               ("call", lambda T: T.zone("Orbital Launch", surf="glass", ground="void", ceil=0, edge_l="open",
                                         edge_r="open", biome="orbital", deck="space")),
               ("jump", J(ramp_len=16, rise=3.0, gap=8, drop=4.0, land_len=30, land_slope=0.2)),
               ("call", lambda T: T.zone("Orbital Ring", surf="glass")),
               ("call", f_orbit), ("fill", {"y": 34, "w": 22})]),
        # ---- ORBITAL RING: floating glass road over the void ----
        J(name="orb_ne", p=(570, -96), r=58, ease=0.28, keys=J(y=33, w=22), mark_in="orb_in", mark="orb_out",
          attrs=J(edge_l="rail", edge_r="open", wall_l=1.1),
          ops=[("s", 30, {"y": 32}), ("call", lambda T: T.edges("open", "open")), ("s", 30, {"y": 31}),
               ("jump", J(ramp_len=14, rise=2.4, gap=7, drop=3.6, land_len=28, land_slope=0.18)),
               ("fill", {"y": 26})]),
        J(name="orb_k", p=(570, 112), r=30, ease=0.2, keys=J(y=25, w=22), attrs=J(edge_l="open", edge_r="rail", wall_r=1.1)),
        J(name="orb_u1", p=(664, 112), r=26, ease=0.18, keys=J(y=24, w=22, bank=-8), mark_in="orb_u_in",
          attrs=J(edge_l="rail", edge_r="open", wall_l=1.1)),
        J(name="orb_u2", p=(664, 164), r=26, ease=0.18, keys=J(y=23, w=22, bank=0),
          ops=[("s", 70, {"y": 20}),
               # ---- back onto the asteroid: trench descent into the underground mine ----
               ("call", lambda T: T.zone("Mine Trench", surf="basalt", ground="terrain", edge_l="cliff",
                                         edge_r="cliff", wall_l=6, wall_r=6, biome="asteroid_trench", deck="basalt")),
               ("fill", {"y": 4, "w": 20})]),
        J(name="mine_w", p=(250, 164), r=34, keys=J(y=-4, w=20),
          attrs=J(zone="Asteroid Mine", surf="basalt", ground="indoor", ceil=10.0, edge_l="wall", edge_r="wall",
                  wall_l=10, wall_r=10, biome="mine", theme_wall="volcano"),
          ops=[("call", f_mine), ("fill", {"y": -12})]),
        # ---- LAVA CRATER: basalt causeways over the lava lake ----
        J(name="crater_a", p=(110, 164), r=24, ease=0.15, keys=J(y=-14, w=18), mark_in="cw1_in", mark="cw1_out",
          attrs=J(zone="Lava Causeway", ceil=0, ground="terrain", edge_l="open", edge_r="open", biome="magma_crater",
                  surf="basalt"),
          ops=[("call", f_causeway), ("fill", {"y": -15})]),
        J(name="crater_b", p=(110, 80), r=22, ease=0.15, keys=J(y=-15, w=18), mark_in="cw2_in", mark="cw2_out"),
        J(name="crater_c", p=(36, 80), r=24, ease=0.15, keys=J(y=-14, w=20),
          ops=[("s", 6),
               # ---- PLASMA CONDUIT: half-pipe climbing back up to the city ----
               ("call", lambda T: T.zone("Plasma Conduit", surf="neon", edge_l="halfpipe", edge_r="halfpipe",
                                         ground="terrain", biome="plasma", deck="space")),
               ("call", f_conduit), ("fill", {"y": 2, "w": 22})]),
        J(name="conduit_s", p=(70, 270), r=28, keys=J(y=6, w=22)),
        J(name="finish_n", p=(0, 270), r=28, keys=J(y=9, w=28),
          attrs=J(zone="Neon Boulevard", surf="asphalt", edge_l="fence", edge_r="fence", wall_l=1.2, wall_r=1.2,
                  biome="city_boulevard", theme_wall="concrete"),
          ops=[("s", 60, {"y": 10}), ("crest", 40, 2.4, {"w": 30}), ("call", lambda T: T.crates(at=T.here() + 20))]),
    ]
    T.plan = build_poly(T, V, verbose=False)
    M = T.marks
    # S1 ROOFTOP HOP: billboard ramp -> land on the Citadel tower rooftop pad -> leap back onto the highway
    T.shortcut_auto("cosmic_rooftop_hop", "Citadel Rooftop Hop", "قفزة سطح البرج", "platforms",
                    launch_d=M["tower_in"] - 12, side="r", yaw_off=34, target_range=(M["tower_out"] - 30, M["tower_out"] + 120),
                    required_fire=3, n_plats=1, hidden="neon", kw=6.5, kl=8.0, plat_r=8.0, edge_in=0.6, plat_kind="neon")
    T.pad(lat=5.0, at=M["tower_in"] - 40)
    # S2 VOID CORNER LEAP: cut the orbital corner straight across empty space (no platform, BLUE FIRE)
    T.shortcut_auto("cosmic_void_leap", "Orbital Void Leap", "قفزة الفراغ المداري", "corner_leap",
                    launch_d=M["orb_in"] - 12, side="r", yaw_off=36, target_range=(M["orb_out"] - 6, M["orb_out"] + 110),
                    required_fire=4, hidden="neon", kw=6.5, kl=8.0, edge_in=0.6)
    T.pad(lat=5.0, at=M["orb_in"] - 50, sup=True)
    # S3 LAVA LEAP: cut the causeway corner straight over the lava lake
    T.shortcut_auto("cosmic_lava_leap", "Lava Lake Leap", "قفزة بحيرة الحمم", "corner_leap",
                    launch_d=M["cw2_in"] - 30, side="l", yaw_off=34, target_range=(M["cw2_out"] - 4, M["cw2_out"] + 90),
                    required_fire=3, hidden="basalt", kw=6.0, kl=7.5, edge_in=0.6)
    T.finalize()
    _world(T)
    return T


def _world(T):
    T.env = dict(theme="volcano", sky_top="#05031a", sky_horizon="#3a1a6a", ground="#2a1830", fog="#2a1a48",
                 fog_density=0.0009, sun="#cfd8ff", sun_energy=0.85, sun_pitch=-50, sun_yaw=20, ambient=0.75,
                 exposure=1.1)
    T.world = dict(
        cell=4.0, margin=200, base_y=4.0, hills_amp=5.0, hills_scale=120.0, rough_amp=2.0,
        border_rise=0, border_width=120, road_blend=24.0, default_surf="regolith", shore_surf="ash",
        rock_surf="rock",
        textures=["offroad_space", "road_volcano", "terrain_gravel", "road_asphalt"],
        tints=["#c8b8e8", "#ffffff", "#b0a0c0", "#ffffff"],
        raises=[dict(x=250, z=-180, r=60, h=6)],
        carves=[dict(type="island", x=150, z=-30, r=330),
                dict(type="basin", x=150, z=120, r=62, depth=10.0, level=-20.0, bank=26)],
        waters=[dict(kind="lava", x=150, z=120, sx=150, sz=150, level=-20.0, deep=0.2)],
        surf_patches=[],
        massifs=[],
        gates=[],
        landmarks=[],
        scatter=[
            dict(kind="building", spacing=26, prob=0.8, dmin=10, dmax=120, scale=(0.7, 1.3), yscale=(0.6, 1.8), max_slope=0.6,
                 biomes=["city_boulevard", "city_downtown", "city_highway"], max_h=60),
            dict(kind="space_tower", spacing=60, prob=0.7, dmin=16, dmax=140, scale=(0.8, 1.2), biomes=["city_boulevard", "city_downtown", "city_highway"], max_h=70),
            dict(kind="lamp", spacing=7, prob=0.9, dmin=0.8, dmax=4.0, biomes=["city_boulevard", "city_downtown", "city_highway"], face_road=True, max_h=60),
            dict(kind="neon_sign", spacing=14, prob=0.8, dmin=3, dmax=16, biomes=["city_boulevard", "city_downtown", "city_highway"], face_road=True, max_h=60),
            dict(kind="hover_pad", spacing=48, prob=0.6, dmin=10, dmax=80, scale=(0.8, 1.3), biomes=["city_boulevard", "city_highway"], dy=1.0),
            dict(kind="spire", spacing=16, prob=0.6, dmin=4, dmax=60, scale=(0.8, 2.0), biomes=["magma_crater", "asteroid_trench", "mine", "plasma"]),
            dict(kind="crystal", spacing=24, prob=0.5, dmin=4, dmax=80, scale=(0.8, 2.2), biomes=["magma_crater", "asteroid_trench", "plasma", "orbital"]),
            dict(kind="rock", spacing=18, prob=0.5, dmin=4, dmax=150, scale=(0.6, 2.4), max_slope=1.4),
        ],
        horizon=None,
    )
    # floating asteroids around the orbital ring (in the void, no terrain there)
    import math
    import numpy as np
    rng = np.random.default_rng(31)
    ast = []
    for k in range(70):
        ang = rng.uniform(0, 2 * math.pi)
        r = rng.uniform(380, 720)
        x, z = 150 + math.cos(ang) * r, -30 + math.sin(ang) * r
        # keep clear of the orbital road
        dmin = np.min(np.hypot(T.S["x"] - x, T.S["z"] - z))
        if dmin < 40:
            continue
        ast.append([round(x, 1), round(float(rng.uniform(-40, 70)), 1), round(z, 1), round(float(rng.uniform(0, 6.28)), 2),
                    round(float(rng.uniform(0.8, 4.5)), 2), None])
    T.world["placed"] = {"asteroid": [[a[0], a[2], a[3], a[4], a[4], a[1]] for a in ast]}
