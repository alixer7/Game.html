#!/usr/bin/env python3
"""DUSTBOWL CANYON (v0.3)  -  desert -> slot canyon -> mine -> open-pit -> mesa -> cliff loop -> river -> desert.
Clockwise. West: desert flats, sharp drop into a narrow walled canyon that loops round a rock fin. North: the mine
(indoor) with an open-air ore pit between two tunnels. East: switchbacks up the mesa, open cliff-edge mesa top, then a
descending loop down the mesa face. South: river bank, timber bridge, wide desert sweepers.

Three hidden skill shortcuts:
  FIN HOP        - hug the left of the fin bend, launch off the rubble hump and clear the knee-high canyon ledge:
                   you land on the dry gully that runs straight past the rock fin.
  BROKEN TRESTLE - behind the rope curtain at the ore pit, an old rail trestle crosses the pit - with a missing span.
                   Kicker + timed launch, or a long fall into the pit.
  MESA DIVE      - instead of the descending loop, launch off the mesa lip straight down onto the road below.
                   Needs a launch AND speed: short = the canyon floor.
"""
import sys, os
sys.path.insert(0, os.path.dirname(__file__))
from trackgen import Track
import trackgen

t = Track('dustbowl_canyon', 'DUSTBOWL CANYON', 'canyon', subtitle='DESERT - CANYON - MINE - MESA - RIVER', difficulty=2, water=-1.0)
t.start(0, 0, h=0, y=6, w=28)

# ---------------------------------------------------------------- DESERT (north-bound, wide, open)
t.M('start')
t.S(70)
t.T(+22, 170, w=26)                 # fast right kink
t.M('washboard')
t.S(40)
t.T(-44, 80)                        # obtuse left sweeper
t.M('crest')
t.S(20, w=24)
t.T(+22, 120)
t.M('canyon')
# ---------------------------------------------------------------- SLOT CANYON (narrow, walled) with the fin loop
t.S(36, y=1.5, prof='steep', w=17)  # SHARP DROP into the canyon
t.M('canyon_floor')
t.S(30)
t.M('fin')
t.T(+90, 22, bank=6, w=18)          # right round the rock fin ...
t.S(8)
t.M('fin_u')
t.T(-180, 18, bank=6)               # ... tight left U ...
t.S(8)
t.T(+90, 22, bank=6)                # ... right, north again
t.M('fin_out')
t.S(24, w=17)
t.M('arch')
t.S(24)                             # natural rock arch
t.T(+90, 34, bank=6)                # right into the mine
t.M('mine')
# ---------------------------------------------------------------- MINE (east-bound: tunnel - open ore pit - tunnel)
t.S(8, w=18)
t.M('mine_tunnel')
t.S(46, y=0.5)                      # INDOOR: mine tunnel (swinging ore buckets)
t.M('pit')
t.S(10, w=22)
t.T(-90, 22, y=0.0, bank=5)         # the road skirts the open ore pit: left ...
t.S(10)
t.M('pit_u')
t.T(+180, 20, y=-0.5, bank=6)       # ... right U round the far side ...
t.S(10)
t.T(-90, 22, y=0.0, bank=5)         # ... left, east-bound again
t.M('pit_out')
t.S(12, w=18)
t.M('mine_exit')
t.S(46, y=8, prof='smooth', w=20)   # INDOOR: SHARP RISE up the haulage incline
t.M('incline_out')
t.FREE(y=9)
t.T(+180, 30, y=14, bank=6)         # switchback 1 (right U) climbing the mesa
t.M('mesa_climb')
t.S(45, y=18)
t.T(-180, 30, y=22, bank=6)         # switchback 2 (left U)
t.M('mesa')
# ---------------------------------------------------------------- MESA TOP (east-bound, open cliff edges)
t.S(26, y=22, w=24)
t.M('hoodoos')
t.T(+60, 80)                        # cliff-edge sweeper
t.S(30)
t.M('mesa_edge')
t.T(+30, 100)                       # south-bound to the lip
t.S(6)
t.M('dive')
# ---------------------------------------------------------------- CLIFF LOOP (descending loop down the mesa face)
t.T(-90, 18, y=20.5, bank=5, w=18)  # left off the lip ...
t.S(20, y=18)
t.M('loop_u')
t.T(+180, 16, y=14, bank=6)         # ... right U down the face ...
t.S(20, y=11.5)
t.T(-90, 18, y=10, bank=5)          # ... left, south-bound below the lip
t.M('dive_out')
t.S(16, y=5, prof='smooth', w=22)   # gradual drop to the river
t.M('river')
# ---------------------------------------------------------------- RIVER (south-bound bank, bridge)
t.T(+15, 150, y=4, w=22)
t.M('ford_in')
t.FREE(y=3)
t.M('bridge_in')
t.T(-40, 60, w=14)                  # detour to the narrow timber bridge ...
t.S(40)                             # ... over the river
t.T(+80, 45)
t.S(20, w=22)
t.T(-40, 60)
t.M('bridge_out')
t.T(+75, 60, y=3, bank=5)           # right onto the delta
t.M('delta')
# ---------------------------------------------------------------- back across the desert (west-bound)
t.S(36, y=4, w=26)
t.T(-30, 120)
t.T(+30, 120, y=5)
t.S(30)
t.T(+90, 55, y=6, w=28, bank=4)     # final turn onto the start straight
t.S(60)

if len(sys.argv) > 1 and sys.argv[1] == "sketch":
    trackgen.sketch(t, "/tmp/claude-0/-home-claude/d88b25c4-563d-5247-a90f-bac6329343eb/scratchpad/sketch.png"); sys.exit()
t.build()
print('free', [round(x, 1) for x in t.free_lengths], 'total', round(t.total))

# ---------------------------------------------------------------- environments
t.zone(('delta', 20), 'canyon', 'desert')
t.zone('canyon', 'mine', 'mesa')
t.zone('mine', ('mesa', -40), 'mine')
t.zone(('mesa', -40), 'dive_out', 'mesa')
t.zone('dive_out', ('delta', 20), 'river')

# ---------------------------------------------------------------- sides
t.rng('open', ('start', -75), 'canyon')                 # open desert flats
t.rng('lowL', ('fin', -2), ('fin', 26))                 # knee-high ledge on the OUTSIDE of the fin bend
t.rng('tunnel', ('arch', 2), ('arch', 22))              # natural rock arch
t.rng('tunnel', ('mine', 4), 'pit')                     # INDOOR: mine tunnel
t.rng('cliffR', ('pit_u', 4), ('pit_u', 58))            # the ore pit inside the U
t.rng('tunnel', ('pit_out', 6), 'incline_out')          # INDOOR: haulage incline
t.rng('cliffR', ('mesa_climb', 50), 'mesa')             # 2nd switchback: drop on the outside
t.rng('cliffL', 'mesa', 'mesa_edge')                    # mesa top: sheer drop on the outside of the sweepers
t.rng('openR', 'mesa', 'mesa_edge')
t.rng('cliffR', 'mesa_edge', 'dive')
t.rng('cliffR', ('dive', 2), ('loop_u', 4))             # the loop down the face: drop on the right ...
t.rng('cliffL', ('loop_u', 50), 'dive_out')             # ... and on the left coming back
t.rng('openR', 'river', 'bridge_in')                    # river side
t.rng('open', ('bridge_out', 10), ('start', -75))       # open delta + desert

# ---------------------------------------------------------------- road features
t.ev('hump', ('start', 38), lane=-1, h=1.15, len=11)                # left-half dune on the start straight
t.ev('rumble', ('washboard', 22), h=0.15, len=3.0, count=10)       # LOW desert washboard
t.ev('bump', ('crest', 8), h=1.35, len=14)                          # HIGH desert crest: natural air, big lip jump
t.ev('bump', ('canyon_floor', 14), h=0.55, len=7)
t.ev('bump', ('fin_out', 12), h=0.6, len=7)
t.ev('dip', ('mine_tunnel', 30), h=0.9, len=12)                     # rail dip in the tunnel
t.ev('hump', ('pit_out', 4), lane=+1, h=1.1, len=10)                # spoil heap: right half out of the pit
t.ev('rumble', ('hoodoos', 70), h=0.14, len=3.0, count=6)
t.ev('hump', ('mesa', 14), lane=+1, h=1.25, len=12)                 # mesa top: right-half hump (cliff on the left!)
t.ev('bump', ('river', 4), h=0.9, len=12)
t.ev('hump', ('delta', 70), lane=-1, h=1.2, len=11)
t.ev('bump', ('delta', 120), h=0.7, len=10)

t.ev('pad', ('crest', -10), lane=0.45)
t.ev('pad', ('fin_out', 2), lane=-0.3)
t.ev('pad', ('incline_out', -10), lane=0.0)
t.ev('pad', ('mesa_climb', 8), lane=-0.4)
t.ev('pad', ('mesa_edge', 40), lane=0.4)                             # boost before the dive / loop
t.ev('pad', ('delta', 40), lane=0.4)

for at, n in ((('start', 50), 4), (('canyon_floor', 6), 3), (('mine_tunnel', 10), 3), (('pit_out', 16), 4), (('mesa', 30), 4),
              (('dive_out', 8), 4), (('delta', 10), 4)):
    t.ev('crates', at, count=n)

# ---------------------------------------------------------------- hazards
t.ob('boulder', ('canyon_floor', 24), lane=0, period=4.6)
t.ob('boulder', ('arch', -8), lane=0, period=5.2, phase=0.5)
t.ob('pendulum', ('mine_tunnel', 12), lane=0, count=2, spread=18, period=2.8)
t.ob('pusher', ('pit_u', 20), lane=1.0, period=3.6)                  # mine carts on the pit road
t.ob('pusher', ('pit_u', 44), lane=-1.0, period=3.6, phase=0.5)
t.ob('pillar', ('hoodoos', 20), lane=0.35, size=1.1)
t.ob('pillar', ('hoodoos', 46), lane=-0.3, size=1.2)
t.ob('pillar', ('hoodoos', 74), lane=-0.12, size=1.0)
t.ob('boulder', ('loop_u', 40), lane=0, period=5.0)
t.ob('geyser', ('ford_in', 10), lane=-0.4, period=4.4)
t.ob('geyser', ('ford_in', 30), lane=0.4, period=4.4, phase=0.5)

# ---------------------------------------------------------------- scenery
t.lm('rock', 'fin_u', along=0, lat=26, r=12)                         # the rock fin the canyon loops round
t.lm('mesa', ('mesa_climb', 20), along=0, lat=-60, r=26, dy=10)
t.lm('mesa', ('hoodoos', 60), along=0, lat=110, r=24, dy=8)
t.lm('lagoon', ('bridge_in', 60), along=0, lat=-18, r=16)
t.lm('lagoon', ('bridge_in', 110), along=0, lat=30, r=22)

# ---------------------------------------------------------------- SECRET 1: FIN HOP (low-ledge hop onto the dry gully)
fin = 'fin_hop'
FIN = dict(hump=-6.0, line=-7.0, hw=6.0, shift=2.0)
for ahead in range(8, 60):
    q, hh = t.hop_line(('fin', FIN['hump']), FIN['line'] - FIN['shift'], ahead)
    edge = q + trackgen._dir(hh + 90) * FIN['hw']
    if t.edge_clearance(edge) >= 1.3 and t.edge_clearance(q) > FIN['hw'] + 1.3: break
q0, hh = t.hop_line(('fin', FIN['hump']), FIN['line'] - FIN['shift'], ahead)
q1, _ = t.hop_line(('fin', FIN['hump']), FIN['line'] - FIN['shift'], ahead + 30)
print(f"fin hop: gully starts {ahead} m past the hump crest")
t.branch(fin, 'shortcut', ('fin', FIN['hump'] + ahead), ('fin_out', 16),
         via=[dict(pos=tuple(q0), y=1.6, w=FIN['hw'] * 2, h=hh), dict(pos=tuple(q1), y=1.9, w=FIN['hw'] * 2, h=hh)],
         w=FIN['hw'] * 2, sp=5, flat=10, hidden=True, detach_start=True)
t.ev('hump', ('fin', FIN['hump']), lane=-0.62, h=1.35, len=12, width=8)     # rubble heap hugging the LEFT wall
t.rng('bareR', 0.0, 'f0.45', road=fin)
t.rng('lowL', 0.0, 'f0.4', road=fin)
t.rng('trail', 'f0.0', 'f0.85', road=fin)
t.ev('crates', 'f0.55', road=fin, count=2)

# ---------------------------------------------------------------- SECRET 2: BROKEN TRESTLE (gap across the ore pit)
tre = 'broken_trestle'
TRE = dict(lip=0.40, g0=0.415, g1=0.655)
t.branch(tre, 'shortcut', ('pit', 2), ('pit_out', 6),
         via=[dict(rel=('pit', 24, 2), y=1.4, w=11), dict(rel=('pit', 48, 1), y=1.6, w=10), dict(rel=('pit', 72, 0), y=0.6, w=11)],
         w=11, sp=4, flat=10, hidden=True)
t.ev('curtain', 'f0.3', road=tre, width=11, h=6)                     # rope curtain hides the trestle
t.ev('ramp', 'f%.3f' % TRE['lip'], road=tre, lane=0.0, h=1.1, len=6, width=8)
t.rng('gap', 'f%.3f' % TRE['g0'], 'f%.3f' % TRE['g1'], road=tre)    # the missing span
t.rng('cliff', 'f0.18', 'f0.85', road=tre)
t.rng('trail', 'f0.1', 'f0.9', road=tre)

# ---------------------------------------------------------------- SECRET 3: MESA DIVE (drop off the lip onto the road below)
dv = 'mesa_dive'
DV = dict(lip=0.20, g0=0.215, g1=0.62, y_land=11.4)
t.branch(dv, 'shortcut', ('dive', 0), ('dive_out', 10),
         via=[dict(rel=('dive', 16, 0), y=22.0, w=12), dict(rel=('dive', 50, 0), y=15.0, w=12), dict(rel=('dive', 60, 0), y=DV['y_land'], w=13)],
         w=12, sp=4, flat=8, hidden=True)
t.ev('hump', 'f%.3f' % DV['lip'], road=dv, lane=0.0, h=1.0, len=8, width=10)     # the lip: a lump of caprock
t.rng('gap', 'f%.3f' % DV['g0'], 'f%.3f' % DV['g1'], road=dv)
t.rng('cliff', 'f0.08', 'f0.9', road=dv)
t.rng('trail', 'f0.05', 'f0.9', road=dv)

out = os.path.join(os.path.dirname(__file__), '../../Assets/Resources/TurboTribe/Tracks/dustbowl_canyon.json')
t.export(out)
