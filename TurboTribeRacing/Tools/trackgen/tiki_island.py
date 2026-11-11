#!/usr/bin/env python3
"""TIKI ISLAND (v0.3)  -  beach -> jungle -> temple hall -> volcano -> lava flank -> sea cliffs.
Clockwise round the island with a climbing 360-degree loop round the volcano that crosses OVER its own approach on a
stone arch (total turning 720).

Three hidden skill shortcuts (no minimap line, no signs, CPUs rarely use them):
  BAY LEAP        - a half-road dune hump on the bay entry launches you across the lagoon channel onto a sand spit.
                    Needs speed and a timed lip jump; short = splash.
  TEMPLE TERRACE  - a hump on the left of the courtyard entry; a well-timed launch clears the knee-high temple
                    wall on the OUTSIDE of the corner and lands on the priests' walkway that skips the sunken court.
  LAVA STEPS      - straight down the volcano flank instead of the switchback: two consecutive jumps over lava
                    channels via a rock island. Two launches in a row, both have to be good.
"""
import sys, os
sys.path.insert(0, os.path.dirname(__file__))
from trackgen import Track
import trackgen

t = Track('tiki_island', 'TIKI ISLAND', 'beach', subtitle='BEACH - JUNGLE - TEMPLE - VOLCANO - CLIFFS', difficulty=1, water=-1.5)
t.start(0, 0, h=270, y=1.5, w=26)

# ---------------------------------------------------------------- BEACH (west-bound along the south shore, open)
t.M('start')
t.S(75)
t.M('bay_in')
t.T(-62, 44, w=24)                  # the road swings round the lagoon bay ...
t.S(26)
t.M('bay_apex')
t.T(+124, 28, y=1.8, bank=6)        # ... tight right round the bay head (3-turbo slide) ...
t.S(26)
t.T(-62, 44, y=2.2)                 # ... and back onto the shore line
t.M('bay_out')
t.S(30, w=22)
t.T(+90, 44, y=3.5, bank=4)         # right into the jungle, north-bound
t.M('jungle')
# ---------------------------------------------------------------- JUNGLE (north-bound, narrow, closed bamboo)
t.S(32, y=8.5, prof='steep', w=17)  # SHORT SHARP RISE
t.T(+35, 44)                        # esses
t.T(-70, 32)
t.T(+35, 44, y=9.5)
t.M('creek')
t.S(36, y=4.5, prof='steep', w=16)  # SHARP DROP into the creek (compression)
t.M('creek_bottom')
t.S(34, y=9.5, prof='steep')        # rise out - crest launches
t.T(+40, 70, y=10.5, w=18)
t.M('canopy')
t.FREE(y=11)                        # climbing canopy straight (north-east)
t.M('temple_turn')
t.T(+50, 38, y=11.5, bank=5, w=24)  # right into the temple, east-bound
t.M('temple')
# ---------------------------------------------------------------- TEMPLE (indoor hall + sunken courtyard)
t.S(14, w=26)
t.M('hall_in')
t.S(84, y=12.5, w=26)               # INDOOR: the great hall (pillars, swinging censers)
t.M('hall_out')
t.S(24, w=22)
t.M('court')
t.T(+90, 25, y=11.5, bank=5)        # down into the sunken court: right ...
t.S(12, y=10.5)
t.M('court_u')
t.T(-180, 23, y=10.5, bank=6)       # ... left U round the sacred pool ...
t.S(12, y=11.5)
t.T(+90, 25, y=12.5, bank=5)        # ... right back up, east-bound
t.M('court_out')
t.S(26, y=13, w=24)
t.T(+90, 40, y=14.5, bank=4)        # south-bound towards the volcano
t.M('volcano')
# ---------------------------------------------------------------- VOLCANO (climbing loop over its own approach)
t.S(88, y=17, w=24)                 # approach (passes UNDER the arch)
t.M('loop_in')
t.T(+180, 34, y=22, bank=5)         # climbing right U round the cone
t.S(40, y=24.5)
t.T(+90, 30, y=26.5, bank=4)
t.M('arch')
t.S(62, y=27, w=20)                 # STONE ARCH over the approach road
t.T(+90, 30, y=27.5, bank=4)        # south-bound on the crater rim
t.M('rim')
t.S(26, y=27.5, w=22)
t.M('flank')
# ---------------------------------------------------------------- LAVA FLANK (descending switchback, open lava edges)
t.T(-90, 26, y=26, bank=5)          # left out onto the flank ...
t.S(14, y=24)
t.M('switch_u')
t.T(+180, 22, y=19, bank=6)         # ... right hairpin DOWN round the lava pit ...
t.S(14, y=17.5)
t.T(-90, 26, y=16.5, bank=5)        # ... left, south-bound again
t.M('flank_out')
t.S(30, y=12, prof='early', w=24)   # SUDDEN DROP off the flank
t.M('cliffs')
# ---------------------------------------------------------------- SEA CLIFFS (descending, sea drop on the left)
t.T(+25, 120, y=8)
t.T(-25, 120, y=5.5, w=26)
t.S(20, y=4)
t.M('final')
t.T(+90, 48, y=2, bank=4)           # final sweeper onto the beach
t.FREE(y=1.5, w=26)

if len(sys.argv) > 1 and sys.argv[1] == "sketch":
    trackgen.sketch(t, "/tmp/claude-0/-home-claude/d88b25c4-563d-5247-a90f-bac6329343eb/scratchpad/sketch.png", free=(80, 80)); sys.exit()
t.build()
print('free', [round(x, 1) for x in t.free_lengths], 'total', round(t.total))

# ---------------------------------------------------------------- environments
t.zone(('final', 30), 'jungle', 'beach')
t.zone('jungle', 'temple', 'jungle')
t.zone('temple', 'volcano', 'temple')
t.zone('volcano', ('cliffs', 40), 'volcano')
t.zone(('cliffs', 40), ('final', 30), 'beach')

# ---------------------------------------------------------------- sides (open / walled / cliff / indoor)
t.rng('openL', ('start', -60), 'bay_in')                 # sea side of the start straight
t.rng('open', 'bay_in', ('bay_out', 10))                 # open sand round the bay
t.rng('open', ('creek_bottom', -12), ('creek_bottom', 14))
t.rng('tunnel', 'hall_in', 'hall_out')                    # INDOOR: temple great hall
t.rng('lowL', ('court', -2), ('court', 30))              # knee-high temple wall on the OUTSIDE of the court entry
t.rng('cliffR', ('court_u', 4), ('court_u', 64))          # the sacred pool inside the U (drop)
t.rng('tunnel', ('loop_in', 60), ('loop_in', 110))        # INDOOR: lava tube on the climbing U
t.rng('cliffL', ('arch', 4), ('arch', 58))                # arch parapets: open drop on the outside
t.rng('cliffR', ('arch', 4), ('arch', 58))
t.rng('cliffL', 'rim', ('flank', 4))                      # crater rim
t.rng('cliffR', ('switch_u', 6), ('switch_u', 64))        # lava pit inside the switchback hairpin
t.rng('open', 'flank_out', 'cliffs')
t.rng('cliffL', 'cliffs', 'final')                        # SEA CLIFFS on the left
t.rng('openR', 'cliffs', 'final')

# ---------------------------------------------------------------- road features (humps on ONE side, bumps, kickers)
t.ev('hump', ('start', 30), lane=+1, h=1.1, len=11)                 # first air of the lap: right half of the straight
t.ev('rumble', ('bay_out', 12), h=0.14, len=3.0, count=8)
t.ev('bump', ('jungle', 70), h=0.55, len=7)                          # roots in the esses
t.ev('bump', ('creek_bottom', 30), h=0.9, len=10)                    # crest out of the creek: lip-jump spot
t.ev('hump', ('canopy', 60), lane=-1, h=1.3, len=12)                 # canopy straight: left-side hump
t.ev('mud', ('creek_bottom', 0), lane=0.0, len=16, width=10)
t.ev('rumble', ('hall_in', 40), h=0.1, len=2.4, count=10)           # temple flagstones
t.ev('hump', ('volcano', 40), lane=+1, h=1.2, len=11)                # approach: right half (under the arch)
t.ev('bump', ('rim', 12), h=0.6, len=8)
t.ev('ramp', ('flank_out', 8), lane=-0.45, h=1.1, len=7, width=7)   # kicker off the flank drop: pro line
t.ev('hump', ('cliffs', 70), lane=-1, h=1.2, len=12)                 # cliff road: left (sea) side hump - brave
t.ev('bump', ('final', -40), h=1.0, len=14)

t.ev('pad', ('bay_out', 4), lane=0.45)
t.ev('pad', ('creek_bottom', 18), lane=-0.35)
t.ev('pad', ('hall_out', 2), lane=0.0)
t.ev('pad', ('loop_in', -20), lane=-0.4)
t.ev('pad', ('flank_out', -2), lane=0.4)
t.ev('pad', ('final', 60), lane=-0.4)

for at, n in ((('start', 55), 4), (('jungle', 20), 3), (('canopy', 100), 4), (('hall_in', 60), 5), (('court_out', 14), 4),
              (('arch', 30), 3), (('flank_out', 22), 4)):
    t.ev('crates', at, count=n)

# ---------------------------------------------------------------- hazards
t.ob('crab', ('bay_apex', 20), lane=0.0, count=3, spread=16, size=1.3, period=3.2)
t.ob('pillar', ('hall_in', 22), lane=0.4, size=1.3)                 # hall columns: weave between them
t.ob('pillar', ('hall_in', 44), lane=-0.4, size=1.3)
t.ob('pendulum', ('hall_in', 66), lane=0.0, count=1, spread=20, period=2.9)   # swinging censer
t.ob('pusher', ('court_u', 30), lane=1.0, period=3.4)
t.ob('geyser', ('volcano', 70), lane=-0.35, period=4.0)
t.ob('boulder', ('arch', 20), lane=0.0, period=5.2)
t.ob('geyser', ('switch_u', 20), lane=0.3, period=4.2, phase=0.5)
t.ob('geyser', ('flank', 10), lane=0.45, period=4.0, phase=0.25)    # vents beside the LAVA STEPS entrance
t.ob('crab', ('cliffs', 30), lane=0.0, count=2, spread=18, size=1.2, period=3.6)

# ---------------------------------------------------------------- scenery
t.lm('lagoon', 'bay_apex', along=10, lat=55, r=26)                   # the lagoon inside the bay
t.lm('pyramid', ('court_u', 30), along=0, lat=-48, r=20)             # temple pyramid east of the court
t.lm('stonehead', ('hall_out', 6), along=0, lat=-18, r=3.6, yaw=200)
t.lm('stonehead', ('temple', 4), along=0, lat=18, r=3.4, yaw=20)
t.lm('volcano', ('loop_in', 40), along=0, lat=40, r=26)               # the cone the loop climbs round
t.lm('lava', ('switch_u', 34), along=0, lat=22, r=10, dy=-6)         # lava pit inside the switchback
t.lm('rock', ('cliffs', 60), along=0, lat=-40, r=10)

# ---------------------------------------------------------------- SECRET 1: BAY LEAP (gap over the lagoon channel)
bay = 'bay_leap'
BAY = dict(hump=0.36, g0=0.385, g1=0.50)
t.branch(bay, 'shortcut', ('bay_in', -4), ('bay_out', 6),
         via=[dict(rel=('bay_in', 34, 3), y=2.3, w=13), dict(rel=('bay_in', 70, 2), y=1.2, w=13), dict(rel=('bay_in', 104, 1), y=1.6, w=13)],
         w=13, sp=5, flat=16, hidden=True)
t.ev('hump', ('bay_in', -14), lane=+1, h=1.3, len=12)                # dune hump on the right of the bay entry: first air + turbo
t.ev('hump', 'f%.3f' % BAY['hump'], road=bay, lane=0.0, h=1.25, len=10, width=9)   # the launcher, right at the channel lip
t.rng('gap', 'f%.3f' % BAY['g0'], 'f%.3f' % BAY['g1'], road=bay)    # lagoon channel
t.rng('open', 'f0.1', 'f0.9', road=bay)
t.rng('trail', 'f0.06', 'f0.94', road=bay)
t.ev('crates', 'f0.75', road=bay, count=2)

# ---------------------------------------------------------------- SECRET 2: TEMPLE TERRACE (low-wall hop)
ter = 'temple_terrace'
TER = dict(hump=-3.0, line=-8.5, hw=6.0, shift=3.0)
# the walkway starts where the straight launch line (from the hump, hugging the left) is clear of the court road
for ahead in range(8, 60):
    q, hh = t.hop_line(('court', TER['hump']), TER['line'] - TER['shift'], ahead)     # walkway centre (shifted outward)
    edge = q + trackgen._dir(hh + 90) * TER['hw']                                      # its edge nearest the court
    if t.edge_clearance(edge) >= 1.3 and t.edge_clearance(q) > TER['hw'] + 1.3: break
TER['start'] = ahead
q0, hh = t.hop_line(('court', TER['hump']), TER['line'] - TER['shift'], ahead)
q1, _ = t.hop_line(('court', TER['hump']), TER['line'] - TER['shift'], ahead + 26)
print(f"temple terrace: walkway starts {ahead} m past the hump crest")
t.branch(ter, 'shortcut', ('court', TER['hump'] + ahead), ('court_out', 14),
         via=[dict(pos=tuple(q0), y=13.2, w=TER['hw'] * 2, h=hh), dict(pos=tuple(q1), y=13.6, w=TER['hw'] * 2, h=hh),
              dict(rel=('court', 96, -8.0), y=13.2, w=14)],
         w=TER['hw'] * 2, sp=5, flat=10, hidden=True, detach_start=True)
t.ev('hump', ('court', TER['hump']), lane=-0.62, h=1.35, len=12, width=9)   # the launcher, hugging the LEFT edge of the entry
t.rng('bareR', 0.0, 'f0.45', road=ter)                               # the side facing the court wall: open landing
t.rng('lowL', 0.0, 'f0.5', road=ter)
t.ev('crates', 'f0.6', road=ter, count=2)
t.ev('curtain', 'f0.5', road=ter, width=12, h=6.5)                  # temple banners half-hide the walkway

# ---------------------------------------------------------------- SECRET 3: LAVA STEPS (double jump down the flank)
lav = 'lava_steps'
LAV = dict(lip1=0.24, g1a=0.255, g1b=0.465, lip2=0.575, g2a=0.59, g2b=0.79, y_lip1=26.6, y_isl=25.2, y_land=23.4)
t.branch(lav, 'shortcut', ('flank', 2), ('flank_out', 10),
         via=[dict(rel=('flank', 22, 0), y=LAV['y_lip1'], w=11), dict(rel=('flank', 54, 0), y=LAV['y_isl'], w=10), dict(rel=('flank', 62, 0), y=LAV['y_isl'], w=10),
              dict(rel=('flank', 88, 0), y=LAV['y_land'], w=12)],
         w=11, sp=4, flat=10, hidden=True)
t.ev('ramp', 'f%.3f' % LAV['lip1'], road=lav, lane=0.0, h=1.0, len=6, width=8)     # lip 1
t.rng('gap', 'f%.3f' % LAV['g1a'], 'f%.3f' % LAV['g1b'], road=lav)                 # lava channel 1
t.ev('ramp', 'f%.3f' % LAV['lip2'], road=lav, lane=0.0, h=1.0, len=6, width=8)     # lip 2 on the rock island
t.rng('gap', 'f%.3f' % LAV['g2a'], 'f%.3f' % LAV['g2b'], road=lav)                 # lava channel 2
t.rng('cliff', 'f0.12', 'f0.9', road=lav)
t.rng('trail', 'f0.1', 'f0.9', road=lav)
t.lm('lava', ('flank', 38), along=0, lat=-2, r=10, dy=-8)
t.lm('lava', ('flank', 76), along=0, lat=-2, r=10, dy=-10)

out = os.path.join(os.path.dirname(__file__), '../../Assets/Resources/TurboTribe/Tracks/tiki_island.json')
t.export(out)
