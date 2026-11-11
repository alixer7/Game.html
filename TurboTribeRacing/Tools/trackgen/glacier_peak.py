#!/usr/bin/env python3
"""GLACIER PEAK (v0.3)  -  village -> frozen lake -> ice cave -> alpine curl -> west face -> summit -> ski jump -> slalom.
Clockwise with a climbing curl that crosses OVER the ice-cave road on a timber trestle (total turning 720).

Three hidden skill shortcuts:
  ROOFTOP RUN   - launch off the snowdrift on the left of the square entry, clear the low snow wall on the outside of
                  the bend and land in the back alley that skips the church square.
  CRACKED ICE   - straight across the frozen lake on glare ice (no grip) - with an open-water crack in the middle.
                  Launch off the snow mound before it or swim.
  SKI JUMP SKIP - everybody flies off the ski jump; only a PERFECT launch with turbo carries you past the slalom loop
                  onto the lower piste. Short = you land in the slalom (no harm) or in the gully (respawn).
"""
import sys, os
sys.path.insert(0, os.path.dirname(__file__))
from trackgen import Track
import trackgen

t = Track('glacier_peak', 'GLACIER PEAK', 'snow', subtitle='VILLAGE - FROZEN LAKE - ICE CAVE - SUMMIT', difficulty=3, water=-2.0)
t.start(0, 0, h=90, y=4, w=26)

# ---------------------------------------------------------------- VILLAGE (east-bound main street + church square)
t.M('start')
t.S(46)
t.T(-28, 64, w=22)                  # chicane between the cabins
t.T(+28, 64)
t.S(10)
t.M('square')
t.T(+90, 24, y=3.8, bank=5)         # right round the church square ...
t.S(8)
t.M('square_u')
t.T(-180, 20, y=3.4, bank=6)        # ... tight left U past the church ...
t.S(8)
t.T(+90, 24, y=3.6, bank=5)         # ... right, east-bound again
t.M('square_out')
t.S(12, w=22)
t.T(+90, 56, w=24, bank=4)          # out of the village, south
t.M('downhill')
t.S(64, y=1.2, prof='smooth')       # GRADUAL DROP to the lake
t.M('lake')
# ---------------------------------------------------------------- FROZEN LAKE (shore road)
t.T(+40, 110, y=0.8, w=24)          # the shore road bulges round the lake ...
t.S(30)
t.T(+100, 55)                       # ... tight right at the far shore ...
t.T(-50, 100)                       # ... and back
t.M('lake_exit')
t.S(30)
t.M('cave')
# ---------------------------------------------------------------- ICE CAVE (west-bound, indoor)
t.S(15, w=16)
t.M('cave_in')
t.T(-22, 120, y=2.0)                # curving ice cave (icicles)
t.S(40)
t.T(+22, 120, y=2.5)
t.M('cave_out')
t.FREE(y=3)
t.T(+90, 36, y=5, bank=5, w=20)     # north out of the cave into the curl
t.M('helix')
# ---------------------------------------------------------------- ALPINE CURL (climbing loop over the cave road)
t.S(25, y=8)
t.T(+180, 52, y=16, bank=4)         # long climbing right U
t.M('trestle')
t.S(70, y=18, w=16)                 # TIMBER TRESTLE over the ice-cave road
t.T(+90, 45, y=20, w=20)
t.S(70, y=21)
t.T(+90, 40, y=22, bank=5)          # north-bound up the west face
t.M('climb')
t.T(-24, 110, y=24)                 # GRADUAL RISE up the west face
t.T(+24, 110, y=26)
t.FREE(y=27)
t.M('summit')
# ---------------------------------------------------------------- SUMMIT (cliff ledge, ski jump, slalom loop)
t.T(+90, 45, y=28, w=20, bank=4)    # summit turn east on the cliff edge
t.S(26, y=28)
t.M('ski_jump')
t.S(18, y=28.5, prof='crest')       # run-in to the kicker
t.M('kicker')
t.S(24, y=21, prof='early', w=24)   # landing slope
t.M('jump_bottom')
t.T(-90, 22, y=19, bank=5, w=20)    # SLALOM LOOP: left ...
t.S(20, y=16)
t.M('slalom_u')
t.T(+180, 20, y=11.5, bank=6)       # ... right U down the piste ...
t.S(20, y=8.5)
t.T(-90, 22, y=7, bank=5)           # ... left, east-bound below the jump
t.M('slalom_out')
t.S(20, y=6, w=24)
t.T(-25, 120, y=5, w=26)            # GRADUAL DROP into the village
t.T(+25, 120, y=4)
t.S(40, y=4)

if len(sys.argv) > 1 and sys.argv[1] == "sketch":
    trackgen.sketch(t, "/tmp/claude-0/-home-claude/d88b25c4-563d-5247-a90f-bac6329343eb/scratchpad/sketch.png"); sys.exit()
t.build()
print('free', [round(x, 1) for x in t.free_lengths], 'total', round(t.total))

# ---------------------------------------------------------------- environments
t.zone(('slalom_out', 30), 'downhill', 'village')
t.zone('downhill', ('cave', -10), 'lake')
t.zone(('cave', -10), 'helix', 'icecave')
t.zone('helix', ('slalom_out', 30), 'alpine')

# ---------------------------------------------------------------- sides / surfaces
t.rng('lowL', ('square', -2), ('square', 26))          # low snow wall on the OUTSIDE of the square entry
t.rng('cliffR', ('square_u', 4), ('square_u', 58))     # the frozen church pond inside the U
t.rng('open', ('downhill', 20), 'lake')                # snowy slope down to the lake
t.rng('openR', 'lake', 'lake_exit')                    # lake side (inside): snow shoulder then ice
t.rng('ice', ('lake', 60), ('lake_exit', -10))         # glazed shore road at the far side
t.rng('tunnel', 'cave_in', 'cave_out')                 # INDOOR: the ice cave
t.rng('cliffL', ('helix', 30), 'trestle')              # outside of the climbing U: drop
t.rng('cliff', ('trestle', 4), ('trestle', 66))        # the trestle: open both sides
t.rng('cliffL', 'climb', 'summit')                     # west face: sheer drop on the left
t.rng('cliff', 'summit', 'kicker')                     # summit ledge: both sides
t.rng('cliffR', 'kicker', ('slalom_u', 4))             # right of the landing slope: the gully
t.rng('openL', 'kicker', 'jump_bottom')
t.rng('open', ('slalom_u', 50), ('slalom_out', 40))    # open piste

# ---------------------------------------------------------------- road features
t.ev('rumble', ('start', 30), h=0.12, len=2.5, count=8)            # LOW cobbles
t.ev('hump', ('square_out', 8), lane=+1, h=1.1, len=10)             # snowdrift: right half out of the square
t.ev('bump', ('downhill', 35), h=0.9, len=10)                       # MEDIUM snow mound: lip-jump spot
t.ev('dip', ('lake_exit', 20), h=0.7, len=10)
t.ev('bump', ('helix', 10), h=0.5, len=7)
t.ev('rumble', ('trestle', 20), h=0.1, len=2.0, count=12)          # trestle planks
t.ev('hump', ('climb', 30), lane=-1, h=1.25, len=12)                # west face: left (cliff side!) hump - brave
t.ev('bump', ('climb', 90), h=1.3, len=14)                          # HIGH crest on the west face
t.ev('ramp', 'kicker', lane=0.0, h=1.4, len=8, width=14)            # the SKI JUMP kicker (everyone flies)
t.ev('hump', ('slalom_out', 30), lane=-1, h=1.1, len=10)
t.ev('bump', ('slalom_out', 120), h=0.6, len=8)

t.ev('pad', ('downhill', 10), lane=0.4)
t.ev('pad', ('cave_out', 5), lane=-0.35)
t.ev('pad', ('trestle', 5), lane=0.0)
t.ev('pad', ('ski_jump', 4), lane=0.0)                               # speed for the jump
t.ev('pad', ('slalom_out', 10), lane=-0.4)

for at, n in ((('start', 20), 4), (('lake', 20), 4), (('cave_in', 30), 3), (('helix', 30), 3), (('climb', 20), 4),
              (('slalom_u', 30), 3), (('slalom_out', 60), 4)):
    t.ev('crates', at, count=n)

# ---------------------------------------------------------------- hazards
t.ob('penguin', ('square_u', 26), lane=0, count=3, spread=10, period=6.0)    # church square penguins
t.ob('penguin', ('lake', 70), lane=0, count=2, spread=14, period=7.0)
t.ob('pillar', ('cave_in', 20), lane=0.3, size=1.0)                       # ice stalagmites
t.ob('pillar', ('cave_in', 58), lane=-0.3, size=1.0)
t.ob('pendulum', ('cave_in', 85), lane=0.0, count=2, spread=20, period=3.2)   # swinging icicle chandeliers
t.ob('boulder', ('trestle', 105), lane=0.0, period=5.4)                    # rolling snowballs
t.ob('boulder', ('climb', 120), lane=0.0, period=4.8, phase=0.5)
t.ob('penguin', ('slalom_u', 40), lane=0, count=2, spread=10, period=5.5)

# ---------------------------------------------------------------- scenery
t.lm('crystal', ('cave_in', 50), along=0, lat=-30, r=4)
t.lm('crystal', ('helix', 60), along=0, lat=52, r=5)                      # inside the curl
t.lm('rock', ('climb', 80), along=0, lat=40, r=12)
t.lm('rock', ('slalom_u', 20), along=0, lat=26, r=8)
import numpy as np
lake_c = (t.frame(('lake', 60))[0] + t.frame(('lake_exit', -40))[0] + t.frame(('lake', 5))[0] + t.frame(('lake_exit', 5))[0]) / 4
t.lm('ice', pos=tuple(lake_c), r=46, y=0.2)                               # the frozen lake
t.lm('ice', ('square_u', 30), along=0, lat=-22, r=8, y=3.0)               # frozen church pond

# ---------------------------------------------------------------- SECRET 1: ROOFTOP RUN (low-wall hop into the back alley)
rf = 'rooftop_run'
RF = dict(hump=-4.0, line=-7.5, hw=6.0, shift=2.0)
for ahead in range(8, 60):
    q, hh = t.hop_line(('square', RF['hump']), RF['line'] - RF['shift'], ahead)
    edge = q + trackgen._dir(hh + 90) * RF['hw']
    if t.edge_clearance(edge) >= 1.3 and t.edge_clearance(q) > RF['hw'] + 1.3: break
q0, hh = t.hop_line(('square', RF['hump']), RF['line'] - RF['shift'], ahead)
q1, _ = t.hop_line(('square', RF['hump']), RF['line'] - RF['shift'], ahead + 26)
print(f"rooftop run: alley starts {ahead} m past the hump crest")
t.branch(rf, 'shortcut', ('square', RF['hump'] + ahead), ('square_out', 14),
         via=[dict(pos=tuple(q0), y=4.0, w=RF['hw'] * 2, h=hh), dict(pos=tuple(q1), y=4.2, w=RF['hw'] * 2, h=hh)],
         w=RF['hw'] * 2, sp=5, flat=10, hidden=True, detach_start=True)
t.ev('hump', ('square', RF['hump']), lane=-0.62, h=1.35, len=12, width=8)    # snowdrift hugging the LEFT wall
t.rng('bareR', 0.0, 'f0.45', road=rf)
t.rng('lowL', 0.0, 'f0.4', road=rf)
t.rng('trail', 'f0.0', 'f0.85', road=rf)
t.ev('curtain', 'f0.55', road=rf, width=12, h=6)                           # icicle-hung washing lines over the alley

# ---------------------------------------------------------------- SECRET 2: CRACKED ICE (glare ice + open-water crack)
ci = 'cracked_ice'
CI = dict(hump=0.36, g0=0.40, g1=0.50)
t.branch(ci, 'shortcut', ('lake', 4), ('lake_exit', -46), via=[], w=16, sp=6, hidden=True)
t.ev('hump', 'f%.3f' % CI['hump'], road=ci, lane=0.0, h=1.25, len=10, width=10)    # pressure ridge = the launcher
t.rng('gap', 'f%.3f' % CI['g0'], 'f%.3f' % CI['g1'], road=ci)                     # open-water crack
t.rng('ice', 'f0.12', 'f%.3f' % (CI['hump'] - 0.06), road=ci)
t.rng('ice', 'f%.3f' % CI['g1'], 'f0.88', road=ci)
t.rng('open', 'f0.1', 'f0.9', road=ci)
t.ob('penguin', 'f0.75', road=ci, lane=0, count=2, spread=10, period=5.0)

# ---------------------------------------------------------------- SECRET 3: SKI JUMP SKIP (perfect launch past the slalom)
sk = 'ski_jump_skip'
SK = dict(strip=26.0, y_strip=6.0)
jb, hjb, yjb, wjb = t.frame('jump_bottom')
t.branch(sk, 'shortcut', ('kicker', 0), ('slalom_out', 12),
         via=[dict(rel=('jump_bottom', SK['strip'] - 6, 0), y=SK['y_strip'] + 1.0, w=14), dict(rel=('jump_bottom', SK['strip'] + 4, 0), y=SK['y_strip'], w=14),
              dict(rel=('jump_bottom', SK['strip'] + 30, 0), y=8.0, w=14)],
         w=14, sp=4, flat=4, hidden=True)
L_sk = None
t.rng('gap', 'f0.02', 'f%.3f' % 0.0, road=sk)       # placeholder, replaced below once the branch length is known
t.rng('cliff', 'f0.1', 'f0.95', road=sk)
t.rng('trail', 'f0.4', 'f0.95', road=sk)

out = os.path.join(os.path.dirname(__file__), '../../Assets/Resources/TurboTribe/Tracks/glacier_peak.json')
# the gap runs from the kicker lip to the start of the landing strip (strip starts SK['strip'] m past jump_bottom)
b_sk = [b for b in t.branches if b['id'] == sk][0]
t._build_branch(b_sk)
d_strip = None
P = np.array([[p['x'], p['z']] for p in b_sk['pts']]); D = np.array([p['d'] for p in b_sk['pts']])
target = t._rel(('jump_bottom', SK['strip'], 0))[0]
d_strip = float(D[int(np.argmin(np.sum((P - target) ** 2, axis=1)))])
t.ranges = [r for r in t.ranges if not (r['road'] == sk and r['type'] == 'gap')]
t.rng('gap', 'f0.03', 'f%.3f' % (d_strip / b_sk['total']), road=sk)
print(f"ski jump skip: gap {d_strip:.0f} m of {b_sk['total']:.0f} m")
t.export(out)
