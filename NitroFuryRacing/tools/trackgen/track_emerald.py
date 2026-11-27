"""Track 1 - EMERALD TEMPLE CIRCUIT (id tiki_cove)

Clockwise loop around the jungle valley. Pyramid in the east, river gorge in the north, lagoon in the
north-west, ruins in the west. The canopy trestle crosses ~14 m OVER the gorge run-in.

 Zones (rhythm):  free start plaza -> quick-decision market chicane -> downhill gorge JUMP (hang time)
 -> drift sweepers with cuttable grass -> steep stepped climb -> INDOOR pyramid: 90R / pillar slalom / 90L /
 boulder / inner ramp -> open sky terrace U-TURN -> narrow elevated trestle (moguls + broken-bridge JUMP)
 -> INDOOR wet cave S-bends with stalagmites + ledge DROP -> wide lagoon sweeper (sand) -> narrow ruins with
 pendulums and a 90 L -> village return.
"""
from core import Track, build_poly

J = dict  # shorthand


def build():
    T = Track("tiki_cove", "EMERALD TEMPLE CIRCUIT", "حلبة المعبد الزمردي", start=(0, 6, 0), yaw_deg=0, w=30,
              surf="stone", edge_l="fence", edge_r="fence", wall_l=1.1, wall_r=1.1, sh_l=3, sh_r=3,
              shs_l="grass", shs_r="grass", biome="jungle_village", zone="Village Plaza", deck="wood")

    def f_start(T):
        T.crates(at=48)
        T.fruit(8, 56, lat=-5, n=6)

    def f_chicane(T):
        d = T.here()
        T.obstacle("market_stall", at=d - 30, lat=-3.8, r=2.2, strength="medium")
        T.obstacle("market_stall", at=d + 12, lat=4.2, r=2.2, strength="medium")

    def f_gorge_pad(T):
        T.pad(lat=0.0, at=T.here() - 16)

    def f_sweep(T):
        d = T.here()
        T.fruit(d - 80, d - 10, lat=8, lat1=6, n=8)
        T.crates(at=d + 60)

    def f_sweep_pad(T):
        T.pad(lat=5.5, at=T.here() - 6)

    def f_stairs(T):
        T.obstacle("obelisk", at=T.here() - 26, lat=0.0, r=1.7, strength="heavy")

    def f_pillars(T):
        d = T.here()
        for k, lat in enumerate((-4.4, 4.4, -4.4)):
            T.obstacle("temple_pillar", at=d + 10 + k * 16, lat=lat, r=1.3, strength="heavy")

    def f_hall(T):
        d = T.here()
        T.hazard("boulder", at=d + 24, span=6.0, speed=1.45, phase=0.2)
        T.hazard("chomper", at=d + 44, lat=-8.4, speed=2.2, phase=0.5)
        T.pad(lat=0.0, at=d + 66)

    def f_trestle(T):
        d = T.here()
        T.pad(lat=0.0, at=d + 40)
        T.fruit(d + 50, d + 80, lat=0, n=5)

    def f_cave(T):
        d = T.here()
        T.obstacle("stalagmite", at=d + 22, lat=-2.5, r=2.0, strength="heavy")
        T.obstacle("stalagmite", at=d + 48, lat=5.0, r=1.7, strength="heavy")

    def f_lagoon(T):
        T.crates(at=T.here() + 30)

    def f_ruins(T):
        d = T.here()
        T.hazard("pendulum", at=d + 40, speed=1.5, phase=0.0)
        T.hazard("pendulum", at=d + 120, speed=1.6, phase=1.7)
        T.pad(lat=-4.5, at=d + 170)

    V = [
        J(name="start", p=(0, 0), ops=[("call", f_start), ("s", 90, {"y": 6, "w": 28})]),
        # ---- Z2 MARKET CHICANE (closed edges, stalls) ----
        J(name="chic_a", p=(0, -100), r=30, attrs=J(zone="Market Chicane", surf="cobble", edge_l="wall",
          edge_r="wall", wall_l=1.6, wall_r=1.6, sh_l=0, sh_r=0, theme_wall="hut"), keys=J(w=21, bank=-7)),
        J(name="chic_b", p=(28, -140), r=30, keys=J(w=22, bank=0),
          ops=[("call", f_chicane), ("s", 40, {"w": 24, "y": 6}),
               # ---- Z3 RIVER GORGE: downhill run under the trestle, real gap over the river ----
               ("call", lambda T: T.zone("River Gorge Jump", surf="dirt", edge_l="open", edge_r="open",
                                         sh_l=2.5, sh_r=2.5, biome="jungle_river", theme_wall="")),
               ("s", 70, {"y": 3.0}), ("call", f_gorge_pad),
               ("jump", J(ramp_len=16, rise=2.8, gap=8, drop=3.8, land_len=30, land_slope=0.18, surf="wood")),
               ("call", lambda T: T.zone("Gorge Landing", surf="dirt")), ("fill", {"y": 1.6})]),
        # ---- Z4 JUNGLE SWEEPERS (drift chain, cuttable grass shoulders, moguls) ----
        J(name="sweep_nw", p=(58, -462), r=72, ease=0.32, keys=J(y=1.6, w=25),
          attrs=J(zone="Jungle Sweepers", surf="dirt", edge_l="shoulder", edge_r="shoulder", sh_l=7, sh_r=7,
                  shs_l="grass", shs_r="grass", auto_bank=360, biome="jungle_forest"),
          ops=[("call", f_sweep), ("bumps", 50, 0.9, 15, {"w": 24, "y": 4.0})]),
        J(name="sweep_mid", p=(196, -528), r=120, ease=0.35, keys=J(y=7.0, w=26)),
        J(name="sweep_ne", p=(344, -448), r=58, ease=0.32, keys=J(y=8.0, w=25),
          ops=[("call", f_sweep_pad),
               # ---- Z5 TEMPLE STAIRS (steep stepped climb, obelisk splits lanes) ----
               ("call", lambda T: T.zone("Temple Stairs", surf="stone", edge_l="wall", edge_r="wall", wall_l=1.8,
                                         wall_r=1.8, sh_l=0, sh_r=0, auto_bank=0, biome="temple_outer")),
               ("s", 26, {"w": 22, "y": 8.5}), ("bumps", 86, 0.35, 8, {"w": 19, "y": 17}), ("call", f_stairs),
               # ---- Z6 PYRAMID HALL (INDOOR) ----
               ("call", lambda T: T.zone("Pyramid Hall", surf="stone", ceil=9.5, ground="indoor", edge_l="wall",
                                         edge_r="wall", wall_l=9.5, wall_r=9.5, biome="temple_inner")),
               ("fill", {"y": 17.5, "w": 18})]),
        J(name="hall_r", p=(308, -262), r=17, ease=0.12, keys=J(y=17.8), ops=[("call", f_pillars), ("fill", {"y": 18})]),
        J(name="hall_l", p=(222, -262), r=17, ease=0.12, keys=J(y=18.2),
          ops=[("call", f_hall), ("s", 56, {"y": 19, "w": 19}), ("s", 36, {"y": 26, "w": 19}),
               # ---- Z7 SKY TERRACE (open sided) ----
               ("call", lambda T: T.zone("Sky Terrace", surf="stone", ceil=0, ground="elevated", edge_l="rail",
                                         edge_r="open", wall_l=1.0, biome="temple_summit", deck="stone")),
               ("fill", {"y": 27, "w": 22})]),
        J(name="hp_a", p=(222, -70), r=27, ease=0.18, keys=J(y=26.5, bank=-9), mark_in="u_start", mark="hairpin_in"),
        J(name="hp_b", p=(168, -70), r=27, ease=0.18, keys=J(y=26.0, bank=0), mark="hairpin_out",
          ops=[("call", lambda T: T.edges("open", "open"))]),
        # ---- Z8 CANOPY TRESTLE (narrow, elevated, crosses over the gorge run-in) ----
        J(name="trestle_w", p=(168, -168), r=30, keys=J(y=25, w=20), mark_in="tw_in", mark="tw_out",
          attrs=J(zone="Canopy Trestle", surf="wood", edge_l="rail", edge_r="rail", wall_l=0.9, wall_r=0.9,
                  ground="elevated", biome="jungle_canopy", deck="wood"),
          ops=[("call", f_trestle), ("bumps", 70, 0.7, 16, {"w": 17, "y": 23}),
               ("jump", J(ramp_len=14, rise=2.0, gap=7, drop=3.4, land_len=26, land_slope=0.16)), ("fill", {"y": 16, "w": 17})]),
        J(name="trestle_sw", p=(-104, -136), r=40, keys=J(y=15, w=18), mark="cave_in"),
        # ---- Z9 WATERFALL CAVE (INDOOR, wet stone, stalagmites, ledge drop) ----
        J(name="cave_n", p=(-140, -300), r=30, keys=J(y=13, w=20),
          attrs=J(zone="Waterfall Cave", surf="wet_stone", ceil=11.0, ground="indoor", edge_l="wall",
                  edge_r="wall", wall_l=11, wall_r=11, biome="cave", deck="stone"),
          ops=[("call", f_cave), ("s", 18, {"y": 11.5}),
               ("ledge", J(gap=7, drop=3.5, land_len=18, ceil=0, ground="terrain")),
               ("call", lambda T: T.zone("Lagoon Beach", surf="cobble", ceil=0, ground="terrain",
                                         edge_l="shoulder", edge_r="shoulder", sh_l=8, sh_r=7, shs_l="sand",
                                         shs_r="sand", biome="lagoon", auto_bank=300)),
               ("call", f_lagoon), ("fill", {"y": 6.5, "w": 28})]),
        # ---- Z10 LAGOON BEACH (wide sweeper around the lagoon) ----
        J(name="lagoon", p=(-306, -278), r=66, ease=0.28, keys=J(y=5.5, w=28), mark_in="lagoon_start", mark="lagoon_corner",
          ops=[("s", 60, {"y": 5.0}),
               # ---- Z11 RUINS GAUNTLET ----
               ("call", lambda T: T.zone("Ruins Gauntlet", surf="cobble", edge_l="wall", edge_r="wall",
                                         wall_l=1.5, wall_r=1.5, sh_l=0, sh_r=0, auto_bank=0, biome="ruins")),
               ("call", f_ruins), ("fill", {"y": 5.5, "w": 19})]),
        J(name="ruins_l", p=(-250, 26), r=22, ease=0.12, keys=J(y=5.5, w=19), mark_in="ruins_in", mark="ruins_corner"),
        J(name="ruins_e", p=(-150, 44), r=60, keys=J(y=6, w=22),
          attrs=J(zone="Village Return", surf="stone", edge_l="fence", edge_r="fence", wall_l=1.1, wall_r=1.1,
                  sh_l=3, sh_r=3, biome="jungle_village"),
          ops=[("s", 10), ("crest", 36, 2.3, {"w": 24}), ("call", lambda T: T.crates(at=T.here() + 6))]),
        J(name="village_s", p=(-64, 78), r=50, keys=J(y=6, w=26)),
        J(name="finish_turn", p=(0, 70), r=45, keys=J(y=6, w=30)),
    ]
    T.plan = build_poly(T, V, verbose=False)
    M = T.marks
    # ===================== JUMP-ONLY SHORTCUTS (solved by the ballistic designer) =====================
    # S1 CORNER-CUT over the void: the hairpin exit climbs to a 90-degree left onto the trestle. A broken railing and a
    # stone ramp on the inner edge let a Sacred-Fire kart leap straight across the corner onto the trestle.
    T.shortcut_auto("emerald_summit_leap", "Summit Corner Leap", "قفزة كسر منعطف القمة", "corner_leap",
                    launch_d=M["tw_in"] - 12, side="l", yaw_off=44, target_range=(M["tw_out"] - 10, M["tw_out"] + 130),
                    required_fire=3, hidden="temple", kw=6.5, kl=8.0)
    T.pad(lat=-6.5, at=M["tw_in"] - 34)
    # S2 FLOATING STEPPING STONE across the lagoon: kicker on the beach -> floating pad (with its own ramp) -> road
    T.shortcut_auto("emerald_lagoon_stones", "Lagoon Stepping Stone", "حجر البحيرة العائم", "platforms",
                    launch_d=M["lagoon_start"] - 8, side="l", yaw_off=28, target_range=(M["lagoon_corner"] - 20, M["lagoon_corner"] + 160),
                    required_fire=3, n_plats=1, hidden="wood", kw=7.0, kl=8.0, plat_r=7.5, edge_in=-1.0)
    T.pad(lat=-9.0, at=M["lagoon_start"] - 34)
    # S3 RUIN WALL VAULT: crumbled ramp on the inside of the ruins 90-degree left -> over the ruin wall -> exit straight
    T.shortcut_auto("emerald_ruin_vault", "Ruin Wall Vault", "قفزة جدار الأطلال", "wall_vault",
                    launch_d=M["ruins_in"] - 26, side="l", yaw_off=24, target_range=(M["ruins_corner"] + 22, M["ruins_corner"] + 130),
                    required_fire=3, hidden="rock", kw=6.0, kl=7.5)
    T.finalize()
    _world(T)
    return T


def _world(T):
    T.env = dict(theme="tiki", sky_top="#2f5fc0", sky_horizon="#bfe0f0", ground="#3d6b3a", fog="#9fc3c8",
                 fog_density=0.0006, sun="#fff0d2", sun_energy=1.15, sun_pitch=-46, sun_yaw=32, ambient=0.55,
                 exposure=0.95)
    gap_pts = [T.S["pos"][i] for i in range(len(T.S["d"])) if T.S["attrs"][i]["gap"] and T.S["attrs"][i]["zone"] == "River Gorge Jump"]
    gx = float(sum(p[0] for p in gap_pts) / len(gap_pts))
    gz = float(sum(p[2] for p in gap_pts) / len(gap_pts))
    river = [(gx + 420, gz + 30), (gx + 200, gz - 10), (gx, gz), (gx - 120, gz + 40), (gx - 230, gz + 120)]
    lag = (-206.0, -196.0)
    cave_p, *_ = T.frame_at(T.zone_start("Waterfall Cave") + 30)
    T.world = dict(
        cell=4.0, margin=230, base_y=-0.5, hills_amp=6.5, hills_scale=150.0, rough_amp=1.5,
        border_rise=85, border_width=180, road_blend=30.0, default_surf="grass", shore_surf="sand",
        textures=["terrain_grass", "cliff_rock_tiki", "terrain_sand", "road_dirt"],
        tints=["#ffffff", "#ffffff", "#ffffff", "#e8dccb"],
        raises=[dict(x=float(cave_p[0]) - 40, z=float(cave_p[2]) - 10, r=95, h=34),
                dict(x=320, z=-120, r=110, h=26), dict(x=-330, z=90, r=120, h=30)],
        carves=[dict(type="river", poly=river, width=30, depth=5.0, level=-1.5, bank=16),
                dict(type="basin", x=lag[0], z=lag[1], r=62, depth=6.0, level=-0.6, bank=26)],
        waters=[dict(kind="water", poly=river, width=30, level=-1.5, deep=1.6),
                dict(kind="water", x=lag[0], z=lag[1], sx=150, sz=150, level=-0.6, deep=1.6)],
        surf_patches=[dict(x=-60, z=60, r=40, surf="dirt"), dict(x=150, z=-480, r=50, surf="mud")],
        massifs=[dict(biomes=["temple_inner"], margin=18, cell=6.0, tier=4.6, top_extra=13, tex="wall_tiki",
                      top_tex="cliff_rock_tiki", tint="#f2e6cf", top_tint="#a8b890")],
        gates=[dict(d=T.zone_start("Temple Stairs") + 4, glb="res://assets/models/prop_tiki_arch.glb"),
               dict(d=T.zone_start("Ruins Gauntlet") + 6, glb="res://assets/models/prop_tiki_arch.glb"),
               dict(d=T.zone_start("Market Chicane") - 4, glb="res://assets/models/prop_tiki_arch.glb")],
        landmarks=[],
        scatter=[
            dict(kind="canopy_tree", crown=9.0, spacing=15, prob=0.75, dmin=9, dmax=170, scale=(0.9, 1.7), yscale=(0.9, 1.3), max_slope=0.7, col_within=40),
            dict(kind="palm", crown=5.0, spacing=17, prob=0.8, dmin=5, dmax=70, scale=(0.8, 1.3), biomes=["lagoon", "jungle_village", "jungle_river", "ruins"], col_within=40),
            dict(kind="bush", spacing=8, prob=0.5, dmin=3, dmax=35, scale=(0.7, 1.4), max_slope=0.8),
            dict(kind="fern", spacing=5.5, prob=0.45, dmin=1.5, dmax=28, scale=(0.8, 1.7), max_slope=0.9),
            dict(kind="rock", spacing=20, prob=0.45, dmin=4, dmax=150, scale=(0.6, 2.4), max_slope=1.4),
            dict(kind="boulder", spacing=42, prob=0.6, dmin=10, dmax=160, scale=(1.0, 2.8), max_slope=1.2),
            dict(kind="ruin", spacing=34, prob=0.7, dmin=10, dmax=75, scale=(0.8, 1.35), biomes=["ruins", "temple_outer", "jungle_forest", "temple_summit"]),
            dict(kind="runestone", spacing=26, prob=0.6, dmin=4, dmax=26, scale=(0.7, 1.1), biomes=["ruins", "temple_outer"]),
            dict(kind="tiki_statue", spacing=26, prob=0.7, dmin=3, dmax=12, scale=(0.9, 1.3), biomes=["jungle_village", "temple_outer", "jungle_river"], face_road=True),
            dict(kind="brazier", spacing=24, prob=0.7, dmin=2.2, dmax=5.5, scale=(0.8, 1.0), biomes=["jungle_village", "temple_outer", "ruins"]),
            dict(kind="hut", spacing=19, prob=0.9, dmin=6, dmax=42, scale=(0.9, 1.25), biomes=["jungle_village"], face_road=True, max_slope=0.5),
            dict(kind="log", spacing=46, prob=0.5, dmin=6, dmax=60, scale=(0.8, 1.3)),
            dict(kind="reeds", spacing=7, prob=0.5, dmin=2, dmax=200, scale=(0.8, 1.4), ymax=0.6, ymin=-2.5),
        ],
        horizon=dict(glb="res://assets/models/prop_mountain_tiki.glb", count=30, w=(120, 200), h=(110, 210), extra=90),
    )
    # waterfall curtain across the cave mouth (drive through it) + falls into the lagoon
    p, f, r, u, i = T.frame_at(T.zone_start("Waterfall Cave") + 3)
    import math
    T.world["landmarks"] += [
        dict(kind="waterfall", x=float(p[0]), y=float(p[1]) + 6.5, z=float(p[2]), w=float(T.S["w"][i] + 5), h=13.0,
             rot=math.atan2(-f[0], -f[2]), reserve=4.0),
        dict(kind="waterfall", x=lag[0] - 70, y=24.0, z=lag[1] + 10, w=30.0, h=50.0, rot=1.2, reserve=20.0),
        dict(kind="glb", glb="res://assets/models/prop_pirate_ship.glb", x=lag[0] + 10, y=-2.0, z=lag[1] + 30,
             rot=0.6, scale=1.1, reserve=22.0),
    ]
