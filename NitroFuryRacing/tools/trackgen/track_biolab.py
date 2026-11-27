"""Track 2 - BIO-LAB HYDRO SPEEDWAY (id glacier_peak)

A research facility on a frozen mountain: INDOOR reactor atrium -> INDOOR conveyor hall (90R / crushers /
columns / 90L) -> elevated catwalks over acid (squared S) -> half-pipe hydro tubes with a pipe-gap JUMP ->
big DROP out of the facility -> 3-leg snow switchbacks over an icy crevasse -> frozen lake (ice, geysers,
ice pillars) -> INDOOR ice cave -> INDOOR return tunnel climbing back to the atrium.
"""
import math
from core import Track, build_poly

J = dict


def build():
    T = Track("glacier_peak", "BIO-LAB HYDRO SPEEDWAY", "حلبة المختبر الحيوي المائي", start=(0, 40, 0), yaw_deg=0,
              w=28, surf="metal", edge_l="wall", edge_r="wall", wall_l=14, wall_r=14, ceil=14.0, ground="indoor",
              biome="lab_atrium", zone="Reactor Atrium", deck="metal", sh_l=0, sh_r=0)

    def f_atrium(T):
        T.crates(at=60)
        T.fruit(10, 70, lat=5, n=6)
        T.obstacle("tank", at=95, lat=0.0, r=2.6, strength="heavy")

    def f_hall(T):
        d = T.here()
        for k, lat in enumerate((-4.5, 4.5, 0.0)):
            T.obstacle("lab_column", at=d + 8 + k * 18, lat=lat, r=1.4, strength="heavy")
        T.hazard("crusher", at=d + 20, lat=-5.0, period=2.6, phase=0.0)
        T.hazard("crusher", at=d + 38, lat=5.0, period=2.6, phase=1.3)

    def f_catwalk(T):
        d = T.here()
        T.fruit(d + 5, d + 30, lat=0, n=5)

    def f_pipes(T):
        d = T.here()
        T.hazard("barrel", at=d + 40, span=6.5, speed=1.5, phase=0.0)
        T.hazard("barrel", at=d + 110, span=6.5, speed=1.7, phase=1.9)
        T.crates(at=d + 70)

    def f_legs(T):
        T.fruit(T.here() + 10, T.here() + 60, lat=-3, n=6)

    def f_lake(T):
        d = T.here()
        T.hazard("frost_geyser", at=d + 40, lat=-6.0, period=3.4, phase=0.0)
        T.hazard("frost_geyser", at=d + 70, lat=6.0, period=3.4, phase=1.7)
        T.obstacle("ice_pillar", at=d + 100, lat=-2.0, r=2.0, strength="heavy")
        T.obstacle("ice_pillar", at=d + 135, lat=7.0, r=2.0, strength="heavy")
        T.crates(at=d + 160)

    def f_cave(T):
        d = T.here()
        T.obstacle("crystal", at=d + 30, lat=4.0, r=1.6, strength="heavy")
        T.obstacle("crystal", at=d + 70, lat=-4.5, r=1.6, strength="heavy")

    def f_tunnel(T):
        d = T.here()
        T.hazard("crusher", at=d + 60, lat=0.0, period=3.0, phase=0.6)
        T.pad(lat=0.0, at=d + 20)

    V = [
        J(name="start", p=(0, 0), ops=[("call", f_atrium), ("s", 60, {"y": 40, "w": 28})]),
        # ---- INDOOR conveyor hall: 90 R / columns + crushers / 90 L ----
        J(name="hall_r", p=(0, -124), r=18, ease=0.12, keys=J(y=40, w=20),
          attrs=J(zone="Conveyor Hall", surf="grating", ceil=10.0, wall_l=10, wall_r=10, biome="lab_hall"),
          ops=[("call", f_hall)]),
        J(name="hall_l", p=(124, -124), r=18, ease=0.12, keys=J(y=40, w=20),
          ops=[("s", 16),
               # ---- elevated catwalks: a square detour around the acid pool (four quick 90s) ----
               ("call", lambda T: T.zone("Acid Catwalks", surf="metal", ceil=0, ground="elevated", edge_l="rail",
                                         edge_r="rail", wall_l=1.0, wall_r=1.0, biome="lab_yard", deck="metal")),
               ("call", f_catwalk), ("fill", {"y": 40, "w": 16})]),
        J(name="cat_a", p=(124, -200), r=13, ease=0.12, keys=J(y=40, w=16), mark_in="cat_a_in"),
        J(name="cat_b", p=(164, -200), r=13, ease=0.12, keys=J(y=40, w=16)),
        J(name="cat_c", p=(164, -240), r=13, ease=0.12, keys=J(y=40, w=16)),
        J(name="cat_d", p=(124, -240), r=13, ease=0.12, keys=J(y=40, w=16), mark="cat_d_out",
          ops=[("s", 26), ("call", lambda T: T.pad(lat=0.0, at=T.here() - 8)),
               # ---- half-pipe hydro tubes on stilts ----
               ("call", lambda T: T.zone("Hydro Tubes", surf="metal", ground="elevated", edge_l="halfpipe",
                                         edge_r="halfpipe", biome="sewer", deck="metal")),
               ("call", f_pipes), ("fill", {"y": 37, "w": 22})]),
        J(name="pipe_a", p=(110, -350), r=60, ease=0.3, keys=J(y=36, w=22)),
        J(name="pipe_b", p=(196, -420), r=55, ease=0.3, keys=J(y=35, w=22),
          ops=[("s", 30), ("jump", J(ramp_len=14, rise=2.8, gap=7, drop=4.0, land_len=30, land_slope=0.2)),
               ("fill", {"y": 31})]),
        # ---- facility exit: big drop onto the snow road (leg A of the switchbacks) ----
        J(name="exit", p=(226, -572), r=34, keys=J(y=31, w=20),
          ops=[("s", 10), ("call", lambda T: T.zone("Facility Exit Drop", surf="packed_snow", ground="terrain",
                                                     edge_l="wall", edge_r="open", wall_l=1.6, biome="arctic", sh_l=0, sh_r=0)),
               ("ledge", J(gap=9, drop=7.5, land_len=26)),
               ("call", lambda T: T.zone("Switchback A", surf="packed_snow", edge_l="cliff", edge_r="rail", wall_l=6, wall_r=1.0,
                                         biome="arctic")),
               ("call", f_legs), ("fill", {"y": 24, "w": 18})]),
        J(name="hp1a", p=(420, -572), r=14, ease=0.15, keys=J(y=22, w=18, bank=-8), mark_in="hp1_in",
          attrs=J(edge_l="rail", edge_r="open")),
        J(name="hp1b", p=(420, -544), r=14, ease=0.15, keys=J(y=17, w=18, bank=0), mark="hp1_out",
          ops=[("s", 8), ("call", lambda T: T.zone("Avalanche Gallery", ceil=8.0, ground="indoor", edge_l="wall", edge_r="wall",
                                                   wall_l=8, wall_r=8, biome="avalanche_shed", theme_wall="concrete")),
               ("fill", {"y": 14})]),
        J(name="hp2a", p=(250, -544), r=14, ease=0.15, keys=J(y=12, w=18, bank=8),
          attrs=J(zone="Switchback Hairpin 2", ceil=0.0, ground="terrain", edge_l="open", edge_r="rail", wall_r=1.0, theme_wall="")),
        J(name="hp2b", p=(250, -516), r=14, ease=0.15, keys=J(y=10, w=18, bank=0), mark="hp2_out",
          ops=[("call", lambda T: T.zone("Switchback C", edge_l="open", edge_r="cliff", wall_r=5)), ("fill", {"y": 8})]),
        # ---- descent to the frozen lake ----
        J(name="descent", p=(450, -516), r=40, keys=J(y=7, w=22),
          attrs=J(zone="Glacier Descent", surf="packed_snow", edge_l="shoulder", edge_r="shoulder", sh_l=6, sh_r=6,
                  shs_l="snow", shs_r="snow", auto_bank=300),
          ops=[("bumps", 80, 0.8, 16, {"y": 6}), ("fill", {"y": 5})]),
        # ---- frozen lake: wide ice, geysers, ice pillars ----
        J(name="lake_e", p=(440, -200), r=48, ease=0.3, keys=J(y=4, w=30), mark_in="lake_in", mark="lake_e_out",
          attrs=J(zone="Frozen Lake", surf="ice", edge_l="wall", edge_r="shoulder", sh_l=6, sh_r=8, wall_l=1.4,
                  shs_l="snow", shs_r="snow", biome="frozen_lake", auto_bank=0, theme_wall="ice"),
          ops=[("call", f_lake)]),
        J(name="lake_s", p=(250, -190), r=60, ease=0.3, keys=J(y=5, w=28), mark="lake_out",
          attrs=J(edge_l="shoulder", edge_r="wall", wall_r=1.4),
          ops=[("s", 40), ("call", lambda T: T.zone("Ice Cave", surf="ice", ceil=11.0, ground="indoor", edge_l="wall",
                                                     edge_r="wall", wall_l=11, wall_r=11, sh_l=0, sh_r=0, biome="ice_cave", deck="ice")),
               ("call", f_cave), ("fill", {"y": 7, "w": 20})]),
        J(name="cave_w", p=(150, -40), r=32, keys=J(y=11, w=20)),
        J(name="cave_s", p=(110, 96), r=32, keys=J(y=19, w=20),
          ops=[("call", lambda T: T.zone("Return Tunnel", surf="metal", ceil=11.0, edge_l="wall", edge_r="wall", wall_l=11, wall_r=11,
                                         biome="lab_tunnel", deck="metal")),
               ("call", f_tunnel), ("fill", {"y": 27, "w": 22})]),
        J(name="finish", p=(0, 96), r=40, keys=J(y=35, w=26),
          attrs=J(zone="Reactor Atrium", surf="metal", ceil=14.0, wall_l=14, wall_r=14, biome="lab_atrium"),
          ops=[("fill", {"y": 40, "w": 28})], keys2=None),
    ]
    T.plan = build_poly(T, V, verbose=False)
    M = T.marks
    # S1 ACID POOL LEAP: the catwalk detours around the acid pool in a square; jump STRAIGHT across instead
    T.shortcut_auto("biolab_acid_leap", "Acid Pool Leap", "قفزة بركة الحمض", "corner_leap",
                    launch_d=M["cat_a_in"] - 10, side="l", yaw_off=0, target_range=(M["cat_d_out"] - 18, M["cat_d_out"] + 70),
                    required_fire=3, hidden="metal", kw=6.0, kl=7.5, edge_in=1.2)
    T.pad(lat=-4.4, at=M["cat_a_in"] - 34)
    # S2 SWITCHBACK SKY DROP: from leg A over the crevasse, over leg B, down onto leg C (needs BLUE FIRE)
    T.shortcut_auto("biolab_switchback_drop", "Switchback Sky Drop", "قفزة المنعطفات الثلجية", "drop_down",
                    launch_d=M["hp1_in"] - 54, side="r", yaw_off=48, target_range=(M["hp2_out"] + 10, M["hp2_out"] + 150),
                    required_fire=3, hidden="ice", kw=6.0, kl=8.0, max_pitch=26.0, min_pitch=14.0, fail_fruit=False)
    T.pad(lat=3.0, at=M["hp1_in"] - 80)
    # S3 ICE FLOE HOP: kicker on the lake shore -> floating ice floe -> far side of the lake curve
    T.shortcut_auto("biolab_ice_floe", "Ice Floe Hop", "قفزة الجليد العائم", "platforms",
                    launch_d=M["lake_in"] - 4, side="r", yaw_off=45, target_range=(M["lake_e_out"] - 6, M["lake_e_out"] + 110),
                    required_fire=3, n_plats=1, hidden="ice", kw=7.0, kl=8.0, plat_r=7.5, edge_in=-1.0, plat_kind="ice")
    T.finalize()
    _world(T)
    return T


def _world(T):
    T.env = dict(theme="glacier", sky_top="#1f3f8a", sky_horizon="#bfe8ff", ground="#9db8cf", fog="#bcd8ea",
                 fog_density=0.0007, sun="#f4f8ff", sun_energy=1.1, sun_pitch=-36, sun_yaw=-40, ambient=0.65,
                 exposure=0.92)
    T.world = dict(
        cell=4.0, margin=240, base_y=-2.0, hills_amp=9.0, hills_scale=170.0, rough_amp=2.5,
        border_rise=110, border_width=200, road_blend=26.0, default_surf="snow", shore_surf="gravel",
        rock_surf="rock",
        textures=["offroad_snow", "wall_glacier", "terrain_gravel", "road_snowpack"],
        tints=["#ffffff", "#c8d8e8", "#d8dde4", "#ffffff"],
        raises=[dict(x=60, z=-90, r=170, h=42), dict(x=330, z=-560, r=120, h=40)],
        carves=[dict(type="basin", x=392, z=-250, r=34, depth=5.0, level=0.5, bank=22)],
        waters=[dict(kind="ice_water", x=392, z=-250, sx=76, sz=76, level=0.5, deep=1.2),
                dict(kind="ice_water", x=335, z=-530, sx=170, sz=12, level=2.0, deep=1.0),
                dict(kind="ice_water", x=335, z=-558, sx=170, sz=12, level=7.0, deep=1.0),
                dict(kind="acid", x=144, z=-220, sx=60, sz=60, level=31.0, deep=0.5)],
        massifs=[dict(biomes=["lab_atrium", "lab_hall", "lab_tunnel"], margin=10, cell=8.0, tier=40.0, top_extra=4,
                      tex="wall_biolab", top_tex="road_metal", tint="#ffffff", top_tint="#c0c8cc", rep=8.0)],
        gates=[],
        landmarks=[],
        scatter=[
            dict(kind="pine", crown=3.5, spacing=15, prob=0.7, dmin=8, dmax=170, scale=(0.9, 1.8), yscale=(0.9, 1.3), max_slope=0.8, ymax=60, col_within=40),
            dict(kind="snow_rock", spacing=18, prob=0.5, dmin=4, dmax=160, scale=(0.6, 2.2), max_slope=1.4),
            dict(kind="snowdrift", spacing=10, prob=0.5, dmin=2.5, dmax=24, scale=(0.7, 1.4), max_slope=0.7),
            dict(kind="crystal", spacing=22, prob=0.55, dmin=4, dmax=60, scale=(0.8, 2.0), biomes=["frozen_lake", "arctic", "ice_cave"]),
            dict(kind="lodge", spacing=60, prob=0.6, dmin=14, dmax=60, scale=(0.9, 1.2), biomes=["frozen_lake", "arctic"], face_road=True, max_slope=0.4),
            dict(kind="tank", spacing=18, prob=0.8, dmin=5, dmax=45, scale=(0.9, 1.6), biomes=["lab_yard", "sewer"], max_h=60),
            dict(kind="pipes", spacing=16, prob=0.7, dmin=4, dmax=34, scale=(0.9, 1.2), biomes=["lab_yard", "sewer"], face_road=True, max_h=60),
            dict(kind="crate_stack", spacing=14, prob=0.5, dmin=3, dmax=24, scale=(0.9, 1.2), biomes=["lab_yard", "sewer"], max_h=60),
            dict(kind="lamp", spacing=9, prob=0.85, dmin=1.0, dmax=4.0, scale=(1.0, 1.0), biomes=["arctic", "frozen_lake", "lab_yard"], face_road=True, max_h=60),
            dict(kind="barrel", spacing=14, prob=0.6, dmin=3, dmax=26, scale=(0.8, 1.1), biomes=["lab_yard", "sewer"], max_h=60),
        ],
        horizon=dict(glb="res://assets/models/prop_mountain_glacier.glb", count=30, w=(130, 220), h=(150, 260), extra=90),
    )
