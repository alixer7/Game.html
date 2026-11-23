#!/usr/bin/env python3
"""Authoring script for the track "Timberfall Rapids".

The track is authored as driving geometry first (straights, constant / spiral
arcs with explicit radii, elevation changes, banking, surfaces) using a turtle,
then exported to data/timberfall.json which the game's TrackBuilder consumes.
It also renders docs/track_map.png and docs/track_profile.png for TRACK_DESIGN.md.

Coordinates: X east, Y up, Z south (Godot). Heading 0 = east, +90 = south.
Positive bank raises the RIGHT edge (use on left-handers).

Surfaces (must match scripts/kart/surfaces.gd):
"""
import json
import math
import os
import sys

ROAD, DIRT, GRASS, SAND, MUD, ICE, ROCK, WOOD, METAL, SHALLOW, CURRENT, MOSS = range(12)
ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")


def lerp(a, b, t):
    return a + (b - a) * t


def smooth(t):
    return t * t * (3 - 2 * t)


class Turtle:
    def __init__(self, x, y, z, heading_deg, w, bank=0.0):
        self.x, self.y, self.z = x, y, z
        self.h = math.radians(heading_deg)
        self.w = w
        self.bank = bank
        self.pts = []
        self.dist = 0.0
        self.marks = {}
        self.zones = []
        self.emit({})

    # ------------------------------------------------------------------ core
    def emit(self, attrs=None):
        p = [round(self.x, 3), round(self.y, 3), round(self.z, 3), round(self.w, 3), round(self.bank, 2), dict(attrs or {})]
        self.pts.append(p)

    def set(self, **attrs):
        """Attributes from the current point onward (surface s, walls wl/wr, style, tm, tag)."""
        self.pts[-1][5].update(attrs)
        return self

    def mark(self, name, **extra):
        d = {"dist": round(self.dist, 2), "pos": [round(self.x, 3), round(self.y, 3), round(self.z, 3)],
             "heading": round(math.degrees(self.h), 2), "w": self.w}
        d.update(extra)
        self.marks[name] = d
        return self

    def zone(self, name, label):
        self.zones.append({"id": name, "label": label, "start": round(self.dist, 2)})
        return self

    def _step(self, ds, dh, y, w, bank):
        self.h += dh * 0.5
        self.x += math.cos(self.h) * ds
        self.z += math.sin(self.h) * ds
        self.h += dh * 0.5
        self.y = y
        self.w = w
        self.bank = bank
        self.dist += ds

    def straight(self, L, dy=0.0, w=None, bank=None, step=9.0, ease=False, wave=None):
        if wave:
            step = min(step, wave[1] / 4.0)
        n = max(1, round(L / step))
        y0, w0, b0 = self.y, self.w, self.bank
        w1 = self.w if w is None else w
        b1 = self.bank if bank is None else bank
        for i in range(1, n + 1):
            t = i / n
            k = smooth(t) if ease else t
            yy = y0 + dy * k
            if wave:
                # rollers: whole wavelengths so the end height is unchanged
                yy += wave[0] * math.sin(t * L / wave[1] * math.pi * 2) * math.sin(t * math.pi)
            self._step(L / n, 0.0, yy, lerp(w0, w1, smooth(t)), lerp(b0, b1, smooth(t)))
            self.emit()
        return self

    def turn(self, r, deg, left, dy=0.0, r_end=None, w=None, bank=None, step=8.0):
        r_end = r if r_end is None else r_end
        ang = math.radians(deg)
        length = (r + r_end) * 0.5 * ang
        n = max(2, round(length / step))
        y0, w0, b0 = self.y, self.w, self.bank
        w1 = self.w if w is None else w
        b1 = self.bank if bank is None else bank
        sgn = -1.0 if left else 1.0
        for i in range(1, n + 1):
            t = i / n
            ri = lerp(r, r_end, (i - 0.5) / n)
            dth = ang / n
            self._step(ri * dth, sgn * dth, y0 + dy * t, lerp(w0, w1, smooth(t)), lerp(b0, b1, smooth(t)))
            self.emit()
        return self

    def L(self, r, deg, **kw):
        return self.turn(r, deg, True, **kw)

    def R(self, r, deg, **kw):
        return self.turn(r, deg, False, **kw)

    def goto(self, x, y, z, heading_deg, w=None, bank=0.0, tension=0.45, step=9.0):
        """Cubic Hermite connection to an absolute pose."""
        p0 = (self.x, self.y, self.z)
        p1 = (x, y, z)
        chord = math.dist((p0[0], p0[2]), (p1[0], p1[2]))
        m0 = (math.cos(self.h) * chord * tension * 2, math.sin(self.h) * chord * tension * 2)
        h1 = math.radians(heading_deg)
        m1 = (math.cos(h1) * chord * tension * 2, math.sin(h1) * chord * tension * 2)
        n = max(3, round(chord * 1.2 / step))
        w0, b0 = self.w, self.bank
        w1 = self.w if w is None else w
        px, pz = p0[0], p0[2]
        for i in range(1, n + 1):
            t = i / n
            h00 = 2 * t ** 3 - 3 * t ** 2 + 1
            h10 = t ** 3 - 2 * t ** 2 + t
            h01 = -2 * t ** 3 + 3 * t ** 2
            h11 = t ** 3 - t ** 2
            nx = h00 * p0[0] + h10 * m0[0] + h01 * p1[0] + h11 * m1[0]
            nz = h00 * p0[2] + h10 * m0[1] + h01 * p1[2] + h11 * m1[1]
            ds = math.dist((px, pz), (nx, nz))
            self.h = math.atan2(nz - pz, nx - px)
            self.x, self.z = nx, nz
            self.y = lerp(p0[1], p1[1], smooth(t))
            self.w = lerp(w0, w1, smooth(t))
            self.bank = lerp(b0, bank, smooth(t))
            self.dist += ds
            px, pz = nx, nz
            self.emit()
        self.h = h1
        return self

    def pose(self):
        return (self.x, self.y, self.z, math.degrees(self.h))


# ============================================================================ main loop
START = (-150.0, 12.0, -22.0, 10.0)
ROLL = 98.0
APPROACH = 50.0


def build_main():
    t = Turtle(START[0], START[1], START[2], START[3], 18.0)
    # ---------------------------------------------------------------- Z1 Aqueduct Roof
    t.zone("Z1", "Aqueduct Roof")
    t.set(s=ROAD, style="roof", wl="parapet", wr="parapet", tm="aqueduct", tag="roof")
    t.straight(30)
    t.mark("start_line")
    t.straight(22, w=17)
    t.L(150, 14, w=16, bank=2)                    # gentle left sweeper: sets up the drift
    t.R(78, 44, w=15, bank=-4)                    # long right sweeper: 1-2 spark drift before the lip
    t.mark("roof_pad")
    t.straight(14, w=14, bank=0)
    t.mark("lip")
    t.set(tag="lip")
    t.straight(4, dy=0.7)                         # kicker: rewards a lip-hop with extra hang time
    # ---------------------------------------------------------------- Drop
    t.set(style="gap", tm="none", wl="none", wr="none", tag="drop")
    t.straight(36, dy=-12.9, step=6)
    # ---------------------------------------------------------------- Z2 Rapids (river lane)
    t.zone("Z2", "Rapids")
    t.mark("river_land")
    t.set(s=CURRENT, style="river", wl="none", wr="none", tm="river", tag="river")
    t.straight(14, dy=-0.3, w=15)
    t.mark("bank_split")
    t.L(80, 24, dy=-0.4)                          # river straightens out east
    t.mark("rock_garden_1")
    t.straight(24, dy=-0.3)
    t.mark("gravel_bar")
    t.straight(14, dy=-0.2, w=13)
    t.L(88, 50, dy=-0.6, w=14)                    # big left bend, 1st half
    t.mark("rock_garden_2")
    t.L(78, 42, dy=-0.6, r_end=66)                # tightening exit of the bend
    t.mark("rapids_steps")
    t.straight(30, dy=-1.2, w=12)                 # narrowing chute toward the falls
    t.mark("falls_lip")
    t.set(tag="falls_lip")
    t.straight(3, dy=0.35)
    # ---------------------------------------------------------------- Falls drop
    t.set(style="gap", tm="none", tag="falls")
    t.straight(26, dy=-6.5, step=6)
    # ---------------------------------------------------------------- Z3 Fernway
    t.zone("Z3", "Fernway")
    t.mark("falls_land")
    t.set(s=DIRT, style="dirt", wl="none", wr="none", tm="conform", tag="")
    t.straight(16, w=14)
    t.mark("bank_merge")
    t.straight(30, dy=2.2, w=12)                  # rising crest
    t.mark("crest_1")
    t.straight(26, dy=-1.4)                       # crest hop: speed launches you a little
    t.L(64, 50, dy=0.8, r_end=36, bank=5)        # decreasing-radius left: brake / early drift
    t.mark("gate_lane_in")
    t.L(36, 40, dy=0.4, r_end=30, bank=6, w=11)
    t.mark("drs_apex")
    t.straight(18, bank=0)
    t.R(52, 34, dy=0.6, bank=-4)                  # compound: right kink sets the angle into the hollow
    t.mark("gate_lane_out")
    t.straight(20, dy=0.4, w=13, bank=0)
    # ---------------------------------------------------------------- Z4 Hollow (log shortcut)
    t.zone("Z4", "Giant's Hollow")
    t.mark("log_entry")
    t.straight(14)
    t.R(46, 62, dy=1.0, bank=-5, w=12)            # around the hollow's rim (right)
    t.L(40, 150, dy=1.6, bank=7, w=12)            # long multi-apex left around the hollow
    t.mark("hollow_exit")
    t.R(60, 36, dy=0.8, bank=-3)
    t.mark("ridge_merge")
    t.straight(22, w=11, bank=0)
    # ---------------------------------------------------------------- Z5 Rootwork (technical)
    t.zone("Z5", "Rootwork")
    t.set(s=DIRT, style="roots", tag="tech")
    t.mark("chicane")
    t.R(19, 48, w=10, bank=-3)
    t.L(19, 48, w=10, bank=3)
    t.straight(10, bank=0)
    t.mark("root_hops")
    t.straight(16, w=10)
    t.set(s=MOSS, style="ruins", wl="ruin", wr="ruin")
    t.mark("swing_log")
    t.straight(26, w=9)                           # narrow ruin corridor: swinging log
    t.mark("flytraps")
    t.straight(22, w=9.5)                         # flytraps snap over alternating halves
    t.set(s=DIRT, style="roots", wl="none", wr="none")
    t.straight(8, w=11)
    t.L(46, 84, r_end=21, w=11, bank=7, dy=-0.4)  # decreasing-radius left: exit quality feeds the pad
    t.mark("od_pad")
    t.straight(16, w=12, bank=0)
    # ---------------------------------------------------------------- Z6 Millrace (climax)
    t.zone("Z6", "Millrace")
    t.set(s=ROAD, style="mill", tag="mill")
    t.mark("rollers")
    t.straight(ROLL, dy=-1.5, w=13, ease=True, wave=(0.9, 24.5))  # rollers: each crest launches at speed
    t.mark("flume_kicker")
    t.straight(10, w=14)
    t.R(58, 46, dy=1.4, bank=-6, w=14)            # long right around the mill pond...
    t.mark("mill_apex")
    t.R(58, 44, dy=1.6, bank=-6)                  # ...two apexes: inside line vs. carried speed
    t.mark("pond_exit")
    t.straight(APPROACH, dy=0.8, bank=0, w=13)
    # ---------------------------------------------------------------- Z7 Hillside Climb
    t.zone("Z7", "Hillside Climb")
    t.set(s=ROAD, style="cobble", tag="climb", tm="conform")
    t.mark("cave_entry")
    t.straight(12, dy=0.6, w=12)
    t.mark("hairpin")
    t.L(17, 178, dy=4.0, bank=9, w=12)            # climbing hairpin: hook-turn territory
    t.mark("hairpin_exit")
    t.straight(10, dy=1.8, w=13, bank=0)
    t.R(60, 22, dy=3.2, bank=-4, w=14)            # climbing S: overtaking / drift-chain
    t.mark("climb_s")
    t.L(60, 16, dy=2.6, bank=4, w=15)
    t.mark("final_approach")
    x, y, z, h = t.pose()
    print("before close: pose", [round(v, 1) for v in (x, y, z, h)], "dist", round(t.dist, 1))
    t.set(style="cobble", wl="parapet", wr="parapet", tm="conform", tag="approach")
    t.goto(START[0], START[1], START[2], START[3], w=18, bank=0, tension=0.42)
    t.pts.pop()   # closed loop: the last point duplicates the first
    return t


# ============================================================================ branches
class Main:
    """Resampled main path, to build parallel branches relative to it."""

    def __init__(self, t):
        self.t = t
        pts = t.pts
        self.P = [(p[0], p[1], p[2]) for p in pts]
        self.W = [p[3] for p in pts]
        self.D = [0.0]
        for i in range(1, len(self.P)):
            self.D.append(self.D[-1] + math.dist((self.P[i][0], self.P[i][2]), (self.P[i - 1][0], self.P[i - 1][2])))

    def at(self, d):
        D = self.D
        for i in range(1, len(D)):
            if D[i] >= d:
                f = (d - D[i - 1]) / max(D[i] - D[i - 1], 1e-6)
                a, b = self.P[i - 1], self.P[i]
                p = tuple(lerp(a[k], b[k], f) for k in range(3))
                tx, tz = b[0] - a[0], b[2] - a[2]
                L = math.hypot(tx, tz)
                tx, tz = tx / L, tz / L
                rx, rz = -tz, tx     # right vector in XZ for heading (tx,tz) with Z south
                return p, (tx, tz), (rx, rz), lerp(self.W[i - 1], self.W[i], f)
        a = self.P[-1]
        return a, (1, 0), (0, 1), self.W[-1]


def offset_branch(main, d0, d1, offset_fn, y_fn, w_fn, step=8.0, attrs=None):
    pts = []
    n = max(2, round((d1 - d0) / step))
    for i in range(n + 1):
        u = i / n
        d = lerp(d0, d1, u)
        p, tng, rgt, w = main.at(d)
        off = offset_fn(u)
        y = y_fn(u, p[1])
        pt = [round(p[0] + rgt[0] * off, 3), round(y, 3), round(p[2] + rgt[1] * off, 3), round(w_fn(u), 3), 0.0, {}]
        pts.append(pt)
    if attrs:
        pts[0][5].update(attrs)
    return pts


def build_branches(t):
    m = Main(t)
    mk = t.marks
    br = []

    # ------------------------------------------------ river banks
    d0 = mk["bank_split"]["dist"] - 6
    d1 = mk["falls_lip"]["dist"] - 2
    # Right bank: narrow, safe, hugs the river on the outside of the big bend.
    right = offset_branch(m, d0, d1,
                          lambda u: 12.5 + 1.5 * math.sin(u * math.pi * 3),
                          lambda u, y: y + 1.0 + 0.4 * math.sin(u * math.pi * 5),
                          lambda u: 6.5 if 0.2 < u < 0.85 else 7.5,
                          attrs={"s": DIRT, "style": "bank", "tm": "conform", "tag": "right_bank"})
    # descend beside the falls on a rocky switch-path
    p, tng, rgt, w = m.at(mk["falls_land"]["dist"] + 14)
    right += [[round(p[0] + rgt[0] * 13, 3), round(p[1] + 0.4, 3), round(p[2] + rgt[1] * 13, 3), 7.0, 0.0, {"s": ROCK, "tag": "right_descent"}]]
    p, tng, rgt, w = m.at(mk["bank_merge"]["dist"] + 8)
    right += [[round(p[0] + rgt[0] * 3, 3), round(p[1] + 0.1, 3), round(p[2] + rgt[1] * 3, 3), 8.0, 0.0, {}]]
    br.append({"id": "right_bank", "style": "bank", "points": right, "spawn_items": False})

    # Left bank: the meadow trail. Wider, weaves away from the river through sweeping
    # S-bends (drift-chain heaven, item boxes) -> longer, but builds reserve.
    def left_off(u):
        base = -15.0
        weave = -14.0 * math.sin(u * math.pi) * (0.55 + 0.45 * math.sin(u * math.pi * 4.0 - 0.6))
        return base + weave

    left = offset_branch(m, d0, d1, left_off,
                         lambda u, y: y + 1.1 + 1.2 * math.sin(u * math.pi * 2),
                         lambda u: 9.5,
                         attrs={"s": DIRT, "style": "bank", "tm": "conform", "tag": "left_bank"})
    p, tng, rgt, w = m.at(mk["falls_land"]["dist"] + 10)
    left += [[round(p[0] - rgt[0] * 14, 3), round(p[1] + 0.6, 3), round(p[2] - rgt[1] * 14, 3), 8.0, 0.0, {"s": WOOD, "style": "boardwalk", "tag": "left_descent"}]]
    p, tng, rgt, w = m.at(mk["bank_merge"]["dist"] + 8)
    left += [[round(p[0] - rgt[0] * 3, 3), round(p[1] + 0.1, 3), round(p[2] - rgt[1] * 3, 3), 8.0, 0.0, {"s": DIRT, "style": "bank"}]]
    br.append({"id": "left_bank", "style": "bank", "points": left, "spawn_items": True})

    # ------------------------------------------------ gate lane (interaction shortcut)
    a = mk["gate_lane_in"]
    b = mk["gate_lane_out"]
    pa, ta, ra, wa = m.at(a["dist"] - 4)
    pb, tb, rb, wb = m.at(b["dist"] + 2)
    mid = ((pa[0] + pb[0]) / 2, (pa[1] + pb[1]) / 2, (pa[2] + pb[2]) / 2)
    ea = wa / 2 + 3.0
    eb = wb / 2 + 3.0
    gate = [
        [round(pa[0] - ra[0] * ea, 3), round(pa[1], 3), round(pa[2] - ra[1] * ea, 3), 7.0, 0.0, {"s": DIRT, "style": "lane", "tm": "conform", "tag": "gate_lane"}],
        [round(lerp(pa[0], mid[0], 0.5) - ra[0] * 14, 3), round(lerp(pa[1], mid[1], 0.5) + 0.2, 3), round(lerp(pa[2], mid[2], 0.5) - ra[1] * 14, 3), 6.0, 0.0, {"tag": "gate"}],
        [round(mid[0] - ra[0] * 13, 3), round(mid[1] + 0.3, 3), round(mid[2] - ra[1] * 13, 3), 6.0, 0.0, {}],
        [round(pb[0] - rb[0] * eb, 3), round(pb[1], 3), round(pb[2] - rb[1] * eb, 3), 7.0, 0.0, {}],
    ]
    br.append({"id": "gate_lane", "style": "lane", "points": gate})

    # ------------------------------------------------ Giant's Log + Ridge (+ Shelf Rock jump)
    a = mk["log_entry"]
    pe0, te, re_, we = m.at(a["dist"] + 4)
    off = we / 2 + 3.0
    pe = (pe0[0] - re_[0] * off, pe0[1], pe0[2] - re_[1] * off)
    ex = mk["ridge_merge"]
    px, tx_, rx_, wx = m.at(ex["dist"] + 6)
    # direction from log entry toward ridge merge
    dx, dz = px[0] - pe[0], px[2] - pe[2]
    L = math.hypot(dx, dz)
    ux, uz = dx / L, dz / L
    def along(s, side=0.0, y=0.0, w=4.6, attrs=None):
        return [round(pe[0] + ux * s - uz * side, 3), round(pe[1] + y, 3), round(pe[2] + uz * s + ux * side, 3), w, 0.0, attrs or {}]
    log = [
        along(0, 0, 0.0, 6.0, {"s": WOOD, "style": "log_ramp", "tm": "none", "tag": "log"}),
        along(10, 0, 1.6, 4.8),
        along(22, 0, 3.6, 4.4),
        along(30, 0, 4.4, 4.2, {"tag": "log_lip"}),
        along(33, 0, 4.5, 4.2, {"style": "gap", "tag": "log_gap"}),
        along(50, 0, 1.3, 10.0, {"s": ROCK, "style": "ridge", "tag": "ridge"}),
        along(64, 0, 1.0, 9.0, {"tag": "shelf_split"}),
    ]
    # rest of ridge descends to the merge point on the main road
    for k in range(1, 4):
        f = k / 3
        q = (lerp(pe[0] + ux * 68, px[0], f), lerp(pe[1] + 1.0, px[1], smooth(f)), lerp(pe[2] + uz * 68, px[2], f))
        log.append([round(q[0], 3), round(q[1], 3), round(q[2], 3), 9.0, 0.0, {}])
    br.append({"id": "giants_log", "style": "ridge", "points": log})

    # Shelf Rock: stage-2 jump off the ridge's left edge over the chicane into the hairpin exit
    hp = mk["root_hops"]
    ph, th, rh, wh = m.at(hp["dist"] + 6)
    sx = pe[0] + ux * 60
    sz = pe[2] + uz * 60
    shelf = [
        [round(sx, 3), round(pe[1] + 1.0, 3), round(sz, 3), 6.0, 0.0, {"s": ROCK, "style": "slab", "tm": "none", "tag": "shelf"}],
        [round(lerp(sx, ph[0], 0.12), 3), round(pe[1] + 2.6, 3), round(lerp(sz, ph[2], 0.12), 3), 5.5, 0.0, {"tag": "shelf_lip"}],
        [round(lerp(sx, ph[0], 0.16), 3), round(pe[1] + 2.8, 3), round(lerp(sz, ph[2], 0.16), 3), 5.5, 0.0, {"style": "gap", "tag": "shelf_gap"}],
        [round(lerp(sx, ph[0], 0.75), 3), round(ph[1] + 0.2, 3), round(lerp(sz, ph[2], 0.75), 3), 9.0, 0.0, {"s": DIRT, "style": "landing", "tm": "conform", "tag": "shelf_land"}],
        [round(ph[0], 3), round(ph[1], 3), round(ph[2], 3), 9.0, 0.0, {}],
    ]
    br.append({"id": "shelf_rock", "style": "slab", "points": shelf})

    # ------------------------------------------------ Millrace Flume (momentum shortcut)
    k = mk["flume_kicker"]
    pk, tk, rk, wk = m.at(k["dist"] + 2)
    kick_off = wk / 2 + 3.5
    ce = mk["cave_entry"]
    pw, tw, rw, ww = m.at(ce["dist"] - 2)
    fx, fz = pw[0] - pk[0], pw[2] - pk[2]
    FL = math.hypot(fx, fz)
    fux, fuz = fx / FL, fz / FL
    y0 = pk[1]
    def fl(s_, y, w, attrs=None):
        return [round(pk[0] + fux * s_ + rk[0] * kick_off, 3), round(y, 3), round(pk[2] + fuz * s_ + rk[1] * kick_off, 3), w, 0.0, attrs or {}]
    flume = [
        fl(0, y0, 6.0, {"s": WOOD, "style": "kicker", "tm": "none", "tag": "flume_kicker"}),
        fl(8, y0 + 2.0, 5.5, {"tag": "flume_kick_lip"}),
        fl(10, y0 + 2.4, 5.5, {"style": "gap", "tag": "flume_gap"}),
        fl(24, y0 + 5.2, 6.0, {"s": CURRENT, "style": "flume", "tag": "flume"}),
    ]
    steps = 4
    for i in range(1, steps + 1):
        s_ = lerp(24, FL - 26, i / steps)
        flume.append(fl(s_, y0 + 5.2 - lerp(0, 1.0, i / steps), 6.0))
    flume.append(fl(FL - 22, y0 + 4.2, 6.0, {"tag": "flume_lip"}))
    flume.append(fl(FL - 19, y0 + 4.2, 6.0, {"style": "gap", "s": ROAD, "tag": "flume_drop"}))
    pl, tl, rl, wl = m.at(ce["dist"] + 2)
    flume.append([round(pl[0] + rl[0] * 2, 3), round(pl[1] + 0.1, 3), round(pl[2] + rl[1] * 2, 3), 11.0, 0.0, {"style": "landing", "tm": "conform", "tag": "flume_land"}])
    pl2, _, _, _ = m.at(ce["dist"] + 10)
    flume.append([round(pl2[0], 3), round(pl2[1], 3), round(pl2[2], 3), 11.0, 0.0, {}])
    br.append({"id": "millrace_flume", "style": "flume", "points": flume})

    # ------------------------------------------------ Rootway Cave (hidden shortcut)
    # Through the hill inside the climbing hairpin: entrance hidden behind vines on the
    # left wall of the hairpin approach, exit on the climb after the hairpin.
    ce = mk["cave_entry"]
    pc, tc, rc, wc = m.at(ce["dist"] + 2)
    hx = mk["hairpin_exit"]
    pf, tf, rf, wf = m.at(hx["dist"] + 12)
    co = wc / 2 + 4.0
    start = (pc[0] - rc[0] * co, pc[1] + 0.2, pc[2] - rc[1] * co)
    cave = [[round(start[0], 3), round(start[1], 3), round(start[2], 3), 6.0, 0.0, {"s": ROCK, "style": "cave", "tm": "none", "tag": "cave"}]]
    exit_pt = (pf[0] - rf[0] * (wf / 2 + 4.0), pf[1], pf[2] - rf[1] * (wf / 2 + 4.0))
    for i in range(1, 5):
        f = i / 5
        q = (lerp(start[0], exit_pt[0], f), lerp(start[1], exit_pt[1], smooth(f)), lerp(start[2], exit_pt[2], f))
        wob = math.sin(f * math.pi) * 5.0
        cave.append([round(q[0] - tc[0] * wob, 3), round(q[1], 3), round(q[2] - tc[1] * wob, 3), 5.5, 0.0, {}])
    eo = wf / 2 + 4.0
    cave.append([round(pf[0] - rf[0] * eo, 3), round(pf[1] + 0.2, 3), round(pf[2] - rf[1] * eo, 3), 6.5, 0.0, {"tag": "cave_exit"}])
    pf2, _, rf2, wf2 = m.at(hx["dist"] + 30)
    cave.append([round(pf2[0] - rf2[0] * 2.0, 3), round(pf2[1], 3), round(pf2[2] - rf2[1] * 2.0, 3), 8.0, 0.0, {"style": "dirt", "s": DIRT, "tm": "conform", "tag": "cave_merge"}])
    br.append({"id": "rootway_cave", "style": "cave", "points": cave})
    return br


def summarize(t):
    pts = t.pts
    print("main loop control points:", len(pts), "length ~", round(t.dist, 1), "m")
    for z in t.zones:
        print("  zone", z["id"], z["label"], "starts at", z["start"])


def plot(t, branches, path_map, path_profile):
    import matplotlib
    matplotlib.use("Agg")
    import matplotlib.pyplot as plt
    from matplotlib.patches import Polygon

    def ribbon(points, closed):
        P = [(p[0], p[2]) for p in points]
        if closed:
            P = P + [P[0]]
        L, R = [], []
        for i in range(len(P)):
            a = P[max(i - 1, 0)]
            b = P[min(i + 1, len(P) - 1)]
            tx, tz = b[0] - a[0], b[1] - a[1]
            l = math.hypot(tx, tz) or 1
            rx, rz = -tz / l, tx / l
            w = points[i % len(points)][3] * 0.5
            L.append((P[i][0] - rx * w, P[i][1] - rz * w))
            R.append((P[i][0] + rx * w, P[i][1] + rz * w))
        return L + R[::-1]

    sty_col = {"roof": "#b9a58a", "gap": None, "river": "#3a9ad9", "dirt": "#a9764a", "roots": "#8d5d36",
               "ruins": "#7f8a6a", "mill": "#c2ad8f", "cobble": "#bba78e", "bank": "#c99a63", "boardwalk": "#8a5a2b",
               "lane": "#b07a4c", "log_ramp": "#6b4423", "ridge": "#8f8b84", "slab": "#9a9590", "landing": "#a9764a",
               "kicker": "#7a5130", "flume": "#5fb0d6", "cave": "#5a5250"}
    fig, ax = plt.subplots(figsize=(14, 12), dpi=110)
    ax.set_facecolor("#5f8f45")

    def draw_path(points, closed, base_style, lw_edge="#2c2c2c", z=2):
        n = len(points)
        style = base_style
        segs = []
        cur = []
        for i in range(n + (1 if closed else 0)):
            p = points[i % n]
            if "style" in p[5]:
                if cur:
                    cur.append(p)
                    segs.append((style, cur))
                style = p[5]["style"]
                cur = [p]
            else:
                cur.append(p)
        if cur:
            segs.append((style, cur))
        for st, sp in segs:
            if len(sp) < 2:
                continue
            col = sty_col.get(st, "#999999")
            if col is None:
                xs = [q[0] for q in sp]
                zs = [q[2] for q in sp]
                ax.plot(xs, zs, ls=":", color="white", lw=1.5, zorder=z + 1)
                continue
            poly = Polygon(ribbon(sp, False), closed=True, facecolor=col, edgecolor=lw_edge, lw=0.6, zorder=z)
            ax.add_patch(poly)

    draw_path(t.pts, True, "roof", z=3)
    for b in branches:
        draw_path(b["points"], False, b["style"], z=2)
    xs = [p[0] for p in t.pts] + [t.pts[0][0]]
    zs = [p[2] for p in t.pts] + [t.pts[0][2]]
    ax.plot(xs, zs, color="#ffffff", lw=0.6, alpha=0.6, zorder=4)
    for name, m in t.marks.items():
        ax.plot(m["pos"][0], m["pos"][2], "o", color="#ffef5a", ms=3, zorder=5)
        ax.annotate(name, (m["pos"][0], m["pos"][2]), fontsize=6.5, color="white", xytext=(3, 3), textcoords="offset points", zorder=6)
    for z in t.zones:
        # label zone near its start
        d = z["start"]
        best = min(t.marks.values(), key=lambda m: abs(m["dist"] - d))
        ax.annotate(z["id"] + " " + z["label"], (best["pos"][0], best["pos"][2]), fontsize=11, color="#fff6c8",
                    weight="bold", xytext=(-40, -22), textcoords="offset points", zorder=7,
                    bbox=dict(boxstyle="round", fc="#203020", alpha=0.6))
    for b in branches:
        p = b["points"][len(b["points"]) // 2]
        ax.annotate(b["id"], (p[0], p[2]), fontsize=8, color="#ffd0a0", xytext=(6, -10), textcoords="offset points", zorder=7)
    ax.set_aspect("equal")
    ax.invert_yaxis()   # north up (Z south)
    ax.set_title("Timberfall Rapids - top view (north up, race direction follows the white centre line)")
    ax.set_xlabel("x (m, east)")
    ax.set_ylabel("z (m, south)")
    ax.grid(alpha=0.25)
    fig.savefig(path_map, bbox_inches="tight")
    plt.close(fig)

    fig, ax = plt.subplots(figsize=(14, 4), dpi=110)
    d = [0.0]
    for i in range(1, len(t.pts)):
        a, b = t.pts[i - 1], t.pts[i]
        d.append(d[-1] + math.dist((a[0], a[2]), (b[0], b[2])))
    ax.plot(d, [p[1] for p in t.pts], color="#2b6cb0", lw=2)
    for z in t.zones:
        ax.axvline(z["start"], color="#999", lw=0.8)
        ax.text(z["start"] + 3, max(p[1] for p in t.pts) + 0.5, z["id"], fontsize=9)
    for name, m in t.marks.items():
        ax.plot(m["dist"], m["pos"][1], "o", color="#e53e3e", ms=3)
        ax.annotate(name, (m["dist"], m["pos"][1]), fontsize=6, rotation=60, xytext=(2, 4), textcoords="offset points")
    ax.set_xlabel("distance along main route (m)")
    ax.set_ylabel("height (m)")
    ax.set_title("Main route elevation profile")
    ax.grid(alpha=0.3)
    fig.savefig(path_profile, bbox_inches="tight")
    plt.close(fig)


def main():
    t = build_main()
    summarize(t)
    branches = build_branches(t)
    data = {
        "name": "Timberfall Rapids",
        "laps": 3,
        "main": {"closed": True, "points": t.pts},
        "branches": branches,
        "marks": t.marks,
        "zones": t.zones,
        "length": round(t.dist, 2),
    }
    os.makedirs(os.path.join(ROOT, "data"), exist_ok=True)
    with open(os.path.join(ROOT, "data", "timberfall.json"), "w") as f:
        json.dump(data, f, indent=1)
    print("wrote data/timberfall.json")
    if "--noplot" not in sys.argv:
        os.makedirs(os.path.join(ROOT, "docs"), exist_ok=True)
        plot(t, branches, os.path.join(ROOT, "docs", "track_map.png"), os.path.join(ROOT, "docs", "track_profile.png"))
        print("wrote docs/track_map.png, docs/track_profile.png")


if __name__ == "__main__":
    main()
