#!/usr/bin/env python3
"""TIKI ISLAND (v0.4)  -  beach -> jungle -> temple -> volcano -> lava flank -> sea cliffs.

Design (CTR school): almost no "dead" straight - the lap is a chain of linked corner COMBOS where the line you take
out of one corner decides how you enter the next, and every tempting bonus (a hump, a pad, a lip) sits on the line
that costs you something later.  Clockwise round the island with a climbing loop round the volcano that crosses
OVER its own approach on a stone arch (total turning 720).

COMBOS (what the perfect lap has to balance)
  1 LAGOON BEND   the shore road swings out round the lagoon: left -> tight right -> left flick.
                  The left's natural track-out (right edge) carries a dune hump: taking it pays an air turbo but you
                  land on the INSIDE of the right-hander, late, and only get 1-2 slide turbos there. Staying left
                  (sacrificing the first exit) sets up the full 3-turbo right.  The dune at the very start of the bend,
                  on the right edge where everybody turns left, is the launcher of BAY LEAP.
  2 ROOT RUN      steep climb with a crest straight into narrow esses (R-L-R). A lip jump off the crest pays a turbo
                  but you land in the first right with no time to slide it; skipping the jump lets you slide-chain
                  the esses.  Then a dive into the creek (mud in the middle - pass it on the outside of the next bend)
                  and a launching crest straight into a right/left flick.
  3 TEMPLE        pillared hall (weave line: left of pillar 1, right of pillar 2 sets up the court entry on the left),
                  then the trombone court: right, LEFT U round the sacred pool, right.  The pad on the right of the
                  court exit is only reachable from a tight U exit.
  4 VOLCANO LOOP  approach under the arch (geyser on the left - the pad is on the left too: time it), climbing U
                  through a lava tube, the arch, crater rim.
  5 LAVA FLANK    descending left - right hairpin round the lava pit - left, then a sudden drop with a kicker on the
                  left (lip jump = turbo, but you land on the outside of the cliff sweeper).
  6 SEA CLIFFS    two long sweepers with the sea drop on the left, final right onto the beach.

HIDDEN SHORTCUTS (no minimap line, no signs, half-hidden; every one needs a timed lip jump - see Tools/trackgen and
SimRunner.ShortcutTest, which drives them with the real kart code)
  BAY LEAP        stay on the right after the sweeper, hit the dune hump and lip-jump across the lagoon channel onto
                  the sand spit that cuts the hook.
  TEMPLE TERRACE  hug the LEFT of the court entry, launch off the low hump and clear the knee-high temple wall onto the
                  priests' terrace that skips the sunken court (behind the temple banners).
  LAVA STEPS      on the crater rim keep to the middle, launch off the rock lip and hop two lava channels straight down
                  the flank instead of the switchback.
"""
import sys, os
sys.path.insert(0, os.path.dirname(__file__))
from trackgen import Track
import trackgen

t = Track('tiki_island', 'TIKI ISLAND', 'beach', subtitle='BEACH - JUNGLE - TEMPLE - VOLCANO - CLIFFS', difficulty=1, water=-1.5)
t.start(0, 0, h=270, y=1.5, w=24)

# ---------------------------------------------------------------- 1 LAGOON BEND (west-bound along the south shore)
t.M('start')
t.S(40)
t.M('bay_in')
t.T(-80, 34, w=24)                  # left: the shore road swings out round the lagoon ...
t.M('sweep_out')
t.S(12)
t.M('bay_turn')
t.T(+160, 25, y=1.8, bank=6, w=22)  # ... tight right round the far shore (3-turbo slide from the LEFT) ...
t.S(10)
t.T(-80, 34, y=2.2)                 # ... left flick back onto the shore line
t.M('bay_out')
t.S(20, w=22)
t.T(+90, 40, y=3.5, bank=4)         # right into the jungle, north-bound
t.M('jungle')
# ---------------------------------------------------------------- 2 ROOT RUN (north-bound, narrow, closed bamboo)
t.S(26, y=8.5, prof='steep', w=17)  # SHORT SHARP CLIMB - crest at the top
t.M('esses')
t.T(+42, 34)                        # esses R ...
t.S(3)
t.T(-84, 26, y=9)                   # ... L ...
t.S(3)
t.T(+42, 34, y=9.5)                 # ... R
t.M('creek')
t.S(30, y=4.5, prof='steep', w=16)  # SHARP DROP into the creek (compression)
t.M('creek_bottom')
t.S(26, y=10, prof='steep')         # rise out - crest launches
t.M('crest')
t.T(+64, 30, y=10.5, w=18)          # right flick just past the crest ...
t.S(4)
t.T(-64, 38, y=11)                  # ... and left
t.M('canopy')
t.FREE(y=11.5)                      # short canopy run (north)
t.M('temple_turn')
t.T(+90, 34, y=12, bank=5, w=24)    # right into the temple, east-bound
t.M('temple')
# ---------------------------------------------------------------- 3 TEMPLE (indoor hall + trombone court)
t.S(10, w=26)
t.M('hall_in')
t.S(66, y=12.5, w=26)               # INDOOR: the great hall (pillars, swinging censer)
t.M('hall_out')
t.S(16, w=22)
t.M('court')
t.T(+90, 24, y=10.7, bank=2)        # down into the sunken court: right ...
t.S(8, y=10.5)
t.M('court_u')
t.T(-180, 25, y=10.5, bank=3, w=20) # ... LEFT U round the sacred pool ...
t.S(8, y=10.7)
t.T(+90, 24, y=12.5, bank=2)        # ... right back up, east-bound
t.M('court_out')
t.S(18, y=13, w=24)
t.T(+90, 38, y=14.5, bank=4)        # south-bound towards the volcano
t.M('volcano')
# ---------------------------------------------------------------- 4 VOLCANO LOOP (climbing loop over its own approach)
t.S(76, y=17, w=24)                 # approach (passes UNDER the arch)
t.M('loop_in')
t.T(+180, 33, y=22, bank=5)         # climbing right U round the cone (lava tube)
t.S(30, y=24.5)
t.T(+90, 30, y=26.5, bank=4)
t.M('arch')
t.S(60, y=27, w=20)                 # STONE ARCH over the approach road
t.T(+90, 30, y=27.5, bank=4)        # south-bound on the crater rim
t.M('rim')
t.S(22, y=27.5, w=22)
t.M('flank')
# ---------------------------------------------------------------- 5 LAVA FLANK (descending switchback, open lava edges)
t.T(-90, 25, y=26, bank=2)          # left out onto the flank ...
t.S(10, y=24)
t.M('switch_u')
t.T(+180, 21, y=19, bank=3)         # ... right hairpin DOWN round the lava pit ...
t.S(10, y=17.5)
t.T(-90, 25, y=16.5, bank=2)        # ... left, south-bound again
t.M('flank_out')
t.S(28, y=12, prof='early', w=24)   # SUDDEN DROP off the flank
t.M('cliffs')
# ---------------------------------------------------------------- 6 SEA CLIFFS (descending, sea drop on the left)
t.T(+28, 100, y=8)
t.T(-28, 100, y=5.5, w=26)
t.S(12, y=4)
t.M('final')
t.T(+90, 46, y=2, bank=4)           # final sweeper onto the beach
t.FREE(y=1.5, w=24)

if len(sys.argv) > 1 and sys.argv[1] == "sketch":
    trackgen.sketch(t, sys.argv[2] if len(sys.argv) > 2 else "/tmp/sketch.png", free=(60, 60)); sys.exit()
t.build()
print('free', [round(x, 1) for x in t.free_lengths], 'total', round(t.total))

# ---------------------------------------------------------------- environments
t.zone(('final', 30), 'jungle', 'beach')
t.zone('jungle', 'temple', 'jungle')
t.zone('temple', 'volcano', 'temple')
t.zone('volcano', ('cliffs', 40), 'volcano')
t.zone(('cliffs', 40), ('final', 30), 'beach')

# ---------------------------------------------------------------- sides (open / walled / cliff / indoor)
t.rng('openL', ('start', -50), 'bay_in')                 # sea side of the start straight
t.rng('openL', 'bay_in', 'sweep_out')                    # beach on the outside of the first left
t.rng('open', ('creek_bottom', -10), ('creek_bottom', 12))
t.rng('tunnel', 'hall_in', 'hall_out')                    # INDOOR: temple great hall
t.rng('lowL', ('court', -4), ('court', 30))              # knee-high temple wall on the OUTSIDE of the court entry
t.rng('cliffL', ('court_u', 6), ('court_u', 58))          # the sacred pool inside the U (cut the apex = splash)
t.rng('tunnel', ('loop_in', 56), ('loop_in', 104))        # INDOOR: lava tube on the climbing U
t.rng('cliffL', ('arch', 4), ('arch', 56))                # arch parapets: open drop on the outside
t.rng('cliffR', ('arch', 4), ('arch', 56))
t.rng('cliffL', 'rim', ('flank', 4))                      # crater rim
t.rng('cliffR', ('switch_u', 6), ('switch_u', 60))        # lava pit inside the switchback hairpin
t.rng('open', 'flank_out', 'cliffs')
t.rng('cliffL', 'cliffs', 'final')                        # SEA CLIFFS on the left
t.rng('openR', 'cliffs', 'final')

# ---------------------------------------------------------------- road features (each one sits on a line that costs something)
t.ev('hump', ('start', 14), lane=-1, h=1.0, len=11)                 # first air of the lap - LEFT half (off the BAY LEAP line)
t.ev('rumble', ('bay_out', 8), h=0.14, len=3.0, count=6)
t.ev('bump', ('jungle', 22), h=0.8, len=8)                           # the crest into the esses (lip jump = late esses)
t.ev('bump', ('creek_bottom', 24), h=0.9, len=10)                    # crest out of the creek: lip-jump spot
t.ev('mud', ('creek_bottom', 0), lane=0.15, len=16, width=11)        # mud in the creek bed (pass it on the left)
t.ev('hump', ('canopy', 14), lane=-1, h=1.1, len=10)                 # canopy: left-side hump (wrong side for the temple turn)
t.ev('rumble', ('hall_in', 34), h=0.1, len=2.4, count=8)            # temple flagstones
t.ev('hump', ('volcano', 34), lane=+1, h=1.15, len=11)               # approach: right half (under the arch)
t.ev('bump', ('rim', 10), h=0.6, len=8)
t.ev('ramp', ('flank_out', 6), lane=-0.45, h=1.1, len=7, width=7)   # kicker off the flank drop: the pro line ...
t.ev('hump', ('cliffs', 66), lane=-1, h=1.15, len=12)                # ... cliff road: sea-side hump - brave
t.ev('bump', ('final', -30), h=0.9, len=12)

t.ev('pad', ('bay_out', 2), lane=0.45)                               # pad on the OUTSIDE of the flick exit
t.ev('pad', ('creek_bottom', 14), lane=-0.35)
t.ev('pad', ('hall_out', 2), lane=-0.3)                              # left: sets up the court entry (and the terrace)
t.ev('pad', ('court_out', 4), lane=0.45)                             # only from a tight U exit
t.ev('pad', ('volcano', 56), lane=-0.4)                              # beside the geyser - time it
t.ev('pad', ('flank_out', -2), lane=0.4)
t.ev('pad', ('final', 50), lane=-0.4)

for at, n in ((('start', 34), 4), (('jungle', 12), 3), (('canopy', 30), 4), (('hall_in', 50), 5), (('court_out', 12), 4),
              (('arch', 28), 3), (('flank_out', 20), 4), (('cliffs', 110), 4)):
    t.ev('crates', at, count=n)

# ---------------------------------------------------------------- hazards
t.ob('crab', ('bay_turn', 30), lane=0.0, count=3, spread=14, size=1.3, period=3.2)
t.ob('pillar', ('hall_in', 18), lane=0.35, size=1.3)                # hall columns: weave between them
t.ob('pillar', ('hall_in', 40), lane=-0.35, size=1.3)
t.ob('pendulum', ('hall_in', 58), lane=0.0, count=1, spread=20, period=2.9)   # swinging censer
t.ob('pusher', ('court_u', 30), lane=1.0, period=3.4)
t.ob('geyser', ('volcano', 56), lane=-0.05, period=4.0)
t.ob('boulder', ('arch', 20), lane=0.0, period=5.2)
t.ob('geyser', ('switch_u', 20), lane=0.3, period=4.2, phase=0.5)
t.ob('crab', ('cliffs', 30), lane=0.0, count=2, spread=18, size=1.2, period=3.6)

# ---------------------------------------------------------------- scenery
t.lm('lagoon', 'bay_turn', along=24, lat=16, r=15)                   # the lagoon inside the bend
t.lm('pyramid', ('court_u', 30), along=0, lat=-56, r=18)             # temple pyramid east of the court
t.lm('stonehead', ('hall_out', 6), along=0, lat=-18, r=3.6, yaw=200)
t.lm('stonehead', ('temple', 4), along=0, lat=18, r=3.4, yaw=20)
t.lm('volcano', ('loop_in', 36), along=0, lat=34, r=14)               # the cone the loop climbs round (tall + steep, inside the loop)
t.lm('lava', ('switch_u', 33), along=0, lat=21, r=9, dy=-6)          # lava pit inside the switchback
t.lm('rock', ('cliffs', 60), along=0, lat=-42, r=10)

# ---------------------------------------------------------------- SECRET 1: BAY LEAP (dune hump -> over the lagoon channel)
bay = 'bay_leap'
# the branch runs straight on from the bend entry (on main's right half) across the lagoon channel to the sand spit;
# the dune launcher sits where the branch has fully left the main road, the channel right after it
h_in = t.frame('bay_in')[1]
t.branch(bay, 'shortcut', ('bay_in', -8), ('bay_out', 8),
         via=[dict(pos=tuple(t.hop_line('bay_in', 7, a)[0]), y=y, w=11, h=h_in) for a, y in ((24, 1.9), (60, 1.6), (96, 1.8))],
         w=11, sp=5, flat=10, hidden=True)
c0, BL = t.clear_from(bay, margin=1.0)
BAY = dict(crest=c0 + 4.0, gap=float(os.environ.get('TT_BAY_GAP', 17)))
print(f"bay leap: clear of main at {c0:.0f} m of {BL:.0f} m, launcher crest {BAY['crest']:.0f} m, channel {BAY['gap']:.0f} m")
t.ev('hump', BAY['crest'], road=bay, lane=0.0, h=1.2, len=10, width=9)            # the dune launcher, at the channel lip
t.rng('gap', BAY['crest'] + 1.0, BAY['crest'] + 1.0 + BAY['gap'], road=bay)       # lagoon channel
t.rng('open', BAY['crest'] + 1.0 + BAY['gap'], 'f0.92', road=bay)                 # the sand spit
t.rng('trail', 'f0.04', 'f0.96', road=bay)
t.ev('crates', BAY['crest'] + BAY['gap'] + 20, road=bay, count=2)

# ---------------------------------------------------------------- SECRET 2: TEMPLE TERRACE (low-wall hop)
ter = 'temple_terrace'
TER = dict(hump=-4.0, line=-8.0, hw=6.0, shift=3.5)
for ahead in range(8, 60):
    q, hh = t.hop_line(('court', TER['hump']), TER['line'] - TER['shift'], ahead)
    edge = q + trackgen._dir(hh + 90) * TER['hw']
    if t.edge_clearance(edge) >= 1.3 and t.edge_clearance(q) > TER['hw'] + 1.3: break
TER['start'] = ahead
q0, hh = t.hop_line(('court', TER['hump']), TER['line'] - TER['shift'], ahead)
q1, _ = t.hop_line(('court', TER['hump']), TER['line'] - TER['shift'], ahead + 24)
print(f"temple terrace: walkway starts {ahead} m past the hump crest")
t.branch(ter, 'shortcut', ('court', TER['hump'] + ahead), ('court_out', 12),
         via=[dict(pos=tuple(q0), y=12.6, w=TER['hw'] * 2, h=hh), dict(pos=tuple(q1), y=13.0, w=TER['hw'] * 2, h=hh),
              dict(rel=('court', 92, -8.0), y=13.0, w=14)],
         w=TER['hw'] * 2, sp=5, flat=10, hidden=True, detach_start=True)
t.ev('hump', ('court', TER['hump']), lane=-0.6, h=1.3, len=12, width=9)   # the launcher, hugging the LEFT edge of the entry
t.rng('bareR', 0.0, 'f0.45', road=ter)
t.rng('lowL', 0.0, 'f0.5', road=ter)
t.ev('crates', 'f0.6', road=ter, count=2)
cf = t.curtain_spot(ter, TER['hw'] * 2 + 0.6, lo=0.3)
print('temple terrace curtain at', cf)
if cf: t.ev('curtain', 'f%.3f' % cf, road=ter, width=TER['hw'] * 2 + 0.6, h=6.5)    # temple banners half-hide the terrace

# ---------------------------------------------------------------- SECRET 3: LAVA STEPS (double jump down the flank)
lav = 'lava_steps'
import json as _json
LAV = dict(lip1=0.24, g1a=0.255, g1b=0.45, lip2=0.58, g2a=0.595, g2b=0.80, y_lip1=26.6, y_isl=25.0, y_land=23.0, h=0.7)
LAV.update(g1b=0.42, g2b=0.76)
LAV.update(_json.loads(os.environ.get('TT_LAV', '{}')))
t.branch(lav, 'shortcut', ('flank', 2), ('flank_out', 10),
         via=[dict(rel=('flank', 20, 0), y=LAV['y_lip1'], w=11), dict(rel=('flank', 50, 0), y=LAV['y_isl'], w=10), dict(rel=('flank', 58, 0), y=LAV['y_isl'], w=10),
              dict(rel=('flank', 82, 0), y=LAV['y_land'], w=12)],
         w=11, sp=4, flat=10, hidden=True)
t.ev('ramp', 'f%.3f' % LAV['lip1'], road=lav, lane=0.0, h=LAV['h'], len=6, width=8)     # lip 1
t.rng('gap', 'f%.3f' % LAV['g1a'], 'f%.3f' % LAV['g1b'], road=lav)                 # lava channel 1
t.ev('ramp', 'f%.3f' % LAV['lip2'], road=lav, lane=0.0, h=LAV['h'], len=6, width=8)     # lip 2 on the rock island
t.rng('gap', 'f%.3f' % LAV['g2a'], 'f%.3f' % LAV['g2b'], road=lav)                 # lava channel 2
t.rng('cliff', 'f0.12', 'f0.9', road=lav)
t.rng('trail', 'f0.1', 'f0.9', road=lav)
t.lm('lava', ('flank', 36), along=0, lat=-2, r=9, dy=-8)
t.lm('lava', ('flank', 70), along=0, lat=-2, r=9, dy=-10)

out = os.path.join(os.path.dirname(__file__), '../../Assets/Resources/TurboTribe/Tracks/tiki_island.json')
t.export(sys.argv[1] if len(sys.argv) > 1 else out)
