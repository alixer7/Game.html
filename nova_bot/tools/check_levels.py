#!/usr/bin/env python3
"""Extra level sanity checks, used by build_levels.py:
  * plan-view overlaps between platforms that are less than 2.2 m apart vertically (they would intersect or
    leave no room to stand), sampled at the start / middle / end of every moving platform's travel;
  * coins that float inside a platform;
  * rescue bots, crates, checkpoints and the goal that do not rest on a platform.
"""
import math

import numpy as np


def inside(s, k, x, z, margin=0.0):
    cx, _, cz = s.at(k)
    if s.kind == "circle":
        return math.hypot(x - cx, z - cz) <= s.r + margin
    th = math.radians(s.ry)
    c, sn = math.cos(th), math.sin(th)
    dx, dz = x - cx, z - cz
    lx = dx * c - dz * sn
    lz = dx * sn + dz * c
    return abs(lx) <= s.hw + margin and abs(lz) <= s.hl + margin


def overlap(a, ka, b, kb):
    pa = a.boundary(ka, 0.25)
    pb = b.boundary(kb, 0.25)
    for x, z in pa:
        if inside(b, kb, x, z):
            return True
    for x, z in pb:
        if inside(a, ka, x, z):
            return True
    ax, _, az = a.at(ka)
    bx, _, bz = b.at(kb)
    return inside(b, kb, ax, az) or inside(a, ka, bx, bz)


def check(L):
    errs = []
    S = L.surfs
    ks = (0.0, 0.5, 1.0)
    for i in range(len(S)):
        for j in range(i + 1, len(S)):
            a, b = S[i], S[j]
            if a.tag == "ride" or b.tag == "ride":
                continue
            for ka in (ks if a.moving else (0.0,)):
                done = False
                for kb in (ks if b.moving else (0.0,)):
                    ya = a.at(ka)[1]
                    yb = b.at(kb)[1]
                    if abs(ya - yb) >= 2.2:
                        continue
                    if overlap(a, ka, b, kb):
                        errs.append("L%d: %s and %s overlap in plan (dy %.1f)" % (L.id, a.name or a.id, b.name or b.id, abs(ya - yb)))
                        done = True
                        break
                if done:
                    break
    # resting objects
    def rests(p, tol=0.25):
        for s in S:
            if s.moving:
                continue
            if inside(s, 0.0, p[0], p[2], 0.1) and abs(s.y - p[1]) <= tol:
                return True
        return False

    for o in L.objs:
        t = o["t"]
        if t in ("bot", "crate", "check", "goal", "battery", "block", "plate", "hopper", "spider", "snowbot", "turret"):
            floating = t == "bot" and any(
                z["t"] == "zerog" and math.dist(z["p"], o["p"]) <= z["r"] for z in L.objs)
            if not floating and not rests(o["p"]):
                errs.append("L%d: %s at %s is not resting on a static platform" % (L.id, t, o["p"]))
        elif t == "coins":
            for p in o["pts"]:
                for s in S:
                    for k in ((0.0, 0.5, 1.0) if s.moving else (0.0,)):
                        sy = s.at(k)[1]
                        if sy - 0.9 < p[1] < sy + 0.05 and inside(s, k, p[0], p[2], 0.2):
                            errs.append("L%d: coin %s is inside platform %s" % (L.id, p, s.name or s.id))
                            break
    return errs
