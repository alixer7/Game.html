#!/usr/bin/env python3
"""Offline world baker for Velocity Rush.

Builds a 4 x 4 km open world: terrain heightmap, material splat map, road
network (highway, avenues, streets, country roads, mountain pass, dirt rally
tracks, cobblestone ruins roads, race circuit), bridges, tunnels, river with a
lake and waterfall, city lots, ancient ruins, vegetation placements, jump
ramps, race routes with long-spaced checkpoints and shortcut spans, and a
minimap image.

Outputs into assets/world/:
  heightmap.bin   zlib-compressed float32 grid (N x N, 2 m spacing)
  splat.png       RGBA material weights (R rock, G sand, B dirt/forest, A snow)
  map.png         stylised top-down map used by the minimap / world map
  world.json      roads, junctions, water, city, ruins, events ...
  objects.bin     zlib float32 records (type, x, y, z, yaw, scale)

usage: python3 tools/world_builder.py
"""
import heapq
import json
import math
import os
import zlib

import numpy as np
from PIL import Image, ImageDraw, ImageFilter
from scipy import ndimage
from scipy.ndimage import gaussian_filter1d, map_coordinates
from scipy.spatial import cKDTree

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
OUT = os.path.join(ROOT, "assets", "world")
N = 2049
CELL = 2.0
HALF = 2048.0
SEA = 0.0
CITY_H = 30.0
CIRCUIT_H = 52.0
LAKE_H = 206.0
STEP = 4.0  # road sample spacing (m)

xs = np.linspace(-HALF, HALF, N)
X, Z = np.meshgrid(xs, xs)  # X[j, i] = xs[i]; Z[j, i] = xs[j]


def log(*a):
    print("[world]", *a, flush=True)


# =========================================================================== noise
class Perlin:
    def __init__(self, seed):
        rng = np.random.RandomState(seed)
        p = rng.permutation(256)
        self.perm = np.concatenate([p, p, p])
        ang = rng.rand(256) * 2 * np.pi
        self.g = np.stack([np.cos(ang), np.sin(ang)], -1)

    def __call__(self, x, y):
        xi = np.floor(x).astype(np.int64)
        yi = np.floor(y).astype(np.int64)
        xf = x - xi
        yf = y - yi
        xi &= 255
        yi &= 255
        p = self.perm
        g = self.g

        def gd(h, dx, dy):
            gg = g[h & 255]
            return gg[..., 0] * dx + gg[..., 1] * dy

        a = p[xi] + yi
        b = p[xi + 1] + yi
        n00 = gd(p[a], xf, yf)
        n10 = gd(p[b], xf - 1, yf)
        n01 = gd(p[a + 1], xf, yf - 1)
        n11 = gd(p[b + 1], xf - 1, yf - 1)
        u = xf * xf * xf * (xf * (xf * 6 - 15) + 10)
        v = yf * yf * yf * (yf * (yf * 6 - 15) + 10)
        r0 = n00 + (n10 - n00) * u
        r1 = n01 + (n11 - n01) * u
        return (r0 + (r1 - r0) * v) * 1.41


_NOISES = {}


def noise(seed):
    if seed not in _NOISES:
        _NOISES[seed] = Perlin(seed)
    return _NOISES[seed]


def fbm(x, y, octaves, seed, gain=0.5, lac=2.0):
    tot = 0.0
    amp = 1.0
    norm = 0.0
    f = 1.0
    for o in range(octaves):
        tot = tot + amp * noise(seed + o)(x * f + o * 17.3, y * f - o * 9.1)
        norm += amp
        amp *= gain
        f *= lac
    return tot / norm


def ridged(x, y, octaves, seed):
    tot = 0.0
    amp = 1.0
    norm = 0.0
    f = 1.0
    prev = 1.0
    for o in range(octaves):
        n = 1.0 - np.abs(noise(seed + o)(x * f + o * 5.7, y * f + o * 3.3))
        n = n * n
        tot = tot + amp * n * prev
        prev = np.clip(n * 1.2, 0, 1)
        norm += amp
        amp *= 0.5
        f *= 2.0
    return tot / norm


def ss(e0, e1, x):
    t = np.clip((x - e0) / (e1 - e0), 0.0, 1.0)
    return t * t * (3 - 2 * t)


def lerp(a, b, t):
    return a + (b - a) * t


# =========================================================================== splines
def catmull_rom(pts, closed, density=1.0):
    P = np.asarray(pts, dtype=np.float64)
    if closed:
        P = np.vstack([P[-1], P, P[0], P[1]])
    else:
        P = np.vstack([2 * P[0] - P[1], P, 2 * P[-1] - P[-2]])
    out = []
    for i in range(1, len(P) - 2):
        p0, p1, p2, p3 = P[i - 1], P[i], P[i + 1], P[i + 2]
        seg = np.linalg.norm(p2 - p1)
        n = max(4, int(seg * density))

        def tj(ti, a, b):
            return ti + max(np.linalg.norm(b - a), 1e-3) ** 0.5

        t0 = 0.0
        t1 = tj(t0, p0, p1)
        t2 = tj(t1, p1, p2)
        t3 = tj(t2, p2, p3)
        t = np.linspace(t1, t2, n, endpoint=False)[:, None]
        A1 = (t1 - t) / (t1 - t0) * p0 + (t - t0) / (t1 - t0) * p1
        A2 = (t2 - t) / (t2 - t1) * p1 + (t - t1) / (t2 - t1) * p2
        A3 = (t3 - t) / (t3 - t2) * p2 + (t - t2) / (t3 - t2) * p3
        B1 = (t2 - t) / (t2 - t0) * A1 + (t - t0) / (t2 - t0) * A2
        B2 = (t3 - t) / (t3 - t1) * A2 + (t - t1) / (t3 - t1) * A3
        C = (t2 - t) / (t2 - t1) * B1 + (t - t1) / (t2 - t1) * B2
        out.append(C)
    out = np.vstack(out)
    if not closed:
        out = np.vstack([out, P[-2]])
    return out


def resample(poly, step, closed):
    P = np.asarray(poly)
    if closed:
        P = np.vstack([P, P[:1]])
    seg = np.linalg.norm(np.diff(P, axis=0), axis=1)
    s = np.concatenate([[0], np.cumsum(seg)])
    L = s[-1]
    n = max(2, int(round(L / step)))
    if closed:
        t = np.linspace(0, L, n, endpoint=False)
    else:
        t = np.linspace(0, L, n + 1)
    out = np.stack([np.interp(t, s, P[:, k]) for k in range(P.shape[1])], -1)
    return out


def sample_grid(H, x, z, order=1):
    scalar = np.ndim(x) == 0
    gi = (np.atleast_1d(np.asarray(x, dtype=np.float64)) + HALF) / CELL
    gj = (np.atleast_1d(np.asarray(z, dtype=np.float64)) + HALF) / CELL
    out = map_coordinates(H, [gj, gi], order=order, mode="nearest")
    return float(out[0]) if scalar else out


def polyline_distance_field(points, attr=None):
    """Rasterise dense polyline points; returns distance (m) and nearest index per cell."""
    pts = np.asarray(points)
    gi = np.clip(np.round((pts[:, 0] + HALF) / CELL).astype(int), 0, N - 1)
    gj = np.clip(np.round((pts[:, 1] + HALF) / CELL).astype(int), 0, N - 1)
    owner = -np.ones((N, N), dtype=np.int64)
    owner[gj, gi] = np.arange(len(pts))
    dist, ind = ndimage.distance_transform_edt(owner < 0, return_indices=True)
    nearest = owner[ind[0], ind[1]]
    return dist * CELL, nearest


# =========================================================================== layout
RIVER = [  # x, z, bed height, half width, valley half width
    (300, -1185, 203.5, 7, 60),
    (300, -1085, 202.0, 7, 50),
    (300, -1050, 128.0, 9, 70),
    (285, -930, 108.0, 10, 120),
    (250, -780, 88.0, 12, 170),
    (120, -450, 58.0, 13, 220),
    (60, -100, 36.0, 15, 240),
    (110, 250, 24.0, 16, 240),
    (95, 600, 14.0, 17, 240),
    (180, 950, 6.0, 19, 220),
    (228, 1250, 1.0, 22, 200),
    (262, 1560, -4.0, 26, 200),
    (290, 1900, -8.0, 30, 200),
]
PASS_CORRIDOR = [(150, -1215, 207), (150, -1310, 212), (225, -1430, 220), (100, -1530, 236),
                 (-150, -1610, 254), (-400, -1665, 266), (-650, -1600, 248), (-800, -1480, 224),
                 (-690, -1375, 206), (-950, -1300, 176), (-1100, -1150, 146), (-1150, -950, 112)]
PASS_TUNNEL = (-400.0, -1665.0, 120.0)
DESERT_LOOP = [(-1560, 960), (-1800, 1060), (-1830, 1300), (-1600, 1380), (-1300, 1350), (-1000, 1320),
               (-800, 1290), (-950, 1230), (-1250, 1150), (-1420, 1060)]
WATERFALL_TOP = (300.0, -1085.0)
WATERFALL_BOTTOM = (300.0, -1050.0)
LAKE = (300.0, -1265.0, 135.0)  # x, z, radius

CITY_RECT = (470.0, -590.0, 1660.0, 700.0)
CIRCUIT_RECT = (1060.0, -1760.0, 1960.0, -880.0)
ACROPOLIS = (-200.0, 1440.0)

AVENUES = [560, 720, 880, 1040, 1200, 1360, 1520]
STREETS = [-500, -340, -180, -20, 140, 300, 460, 620]
WIDE_AVENUE = 1040
WIDE_STREET = -20

# road types: width, lanes per direction, smoothing sigma (m), material, max grade
RTYPES = {
    "highway": dict(width=20.0, lanes=2, sigma=110, mat=0, grade=0.07, rail=True, light=60),
    "avenue": dict(width=18.0, lanes=2, sigma=40, mat=0, grade=0.10, rail=False, light=36),
    "street": dict(width=12.0, lanes=1, sigma=40, mat=0, grade=0.10, rail=False, light=36),
    "country": dict(width=10.0, lanes=1, sigma=38, mat=0, grade=0.12, rail=False, light=0),
    "mountain": dict(width=9.5, lanes=1, sigma=16, mat=0, grade=0.13, rail=True, light=0),
    "dirt": dict(width=9.0, lanes=0, sigma=10, mat=2, grade=0.26, rail=False, light=0),
    "track": dict(width=16.0, lanes=0, sigma=60, mat=0, grade=0.06, rail=False, light=0),
    "cobble": dict(width=8.0, lanes=1, sigma=14, mat=1, grade=0.14, rail=False, light=0),
    "alley": dict(width=8.0, lanes=0, sigma=20, mat=2, grade=0.20, rail=False, light=0),
}


def roads_layout():
    R = []

    def add(name, kind, pts, closed=False, **kw):
        d = dict(name=name, type=kind, ctrl=pts, closed=closed)
        d.update(kw)
        R.append(d)

    add("H1", "highway", [
        (1300, 830), (1630, 780), (1785, 560), (1805, 150), (1795, -250), (1730, -640),
        (1500, -805), (1100, -770), (750, -800), (420, -865), (100, -885), (-250, -865),
        (-600, -845), (-950, -805), (-1350, -655), (-1650, -350), (-1765, 50), (-1705, 450),
        (-1500, 820), (-1150, 1120), (-700, 1205), (-300, 1155), (50, 1185), (330, 1235),
        (650, 1150), (960, 985)], closed=True,
        tunnel_zones=[(-480, -850, 260)], label_ar="الطريق السريع", label_en="Ring Highway")

    # city grid: every block edge is its own segment so junctions are endpoints
    for x in AVENUES:
        for a, b in zip(STREETS[:-1], STREETS[1:]):
            add("AV%d_%d" % (x, a), "avenue" if x == WIDE_AVENUE else "street",
                [(x, a), (x, (a + b) / 2), (x, b)], city=True)
    for z in STREETS:
        for a, b in zip(AVENUES[:-1], AVENUES[1:]):
            add("ST%d_%d" % (z, a), "avenue" if z == WIDE_STREET else "street",
                [(a, z), ((a + b) / 2, z), (b, z)], city=True)
    # city connectors to the highway
    add("CE", "avenue", [(1520, -20), (1650, -20), (1800, -20)])
    add("CN", "avenue", [(1040, -500), (1040, -640), (1045, -772)])
    add("CS", "avenue", [(1040, 620), (1040, 760), (1060, 905)])
    add("CW", "street", [(560, 620), (480, 700), (420, 900), (480, 1110), (560, 1170)])

    add("C1", "country", [
        (560, -20), (420, -40), (270, 5), (70, 0), (-150, -45), (-400, 60), (-650, 15),
        (-900, -120), (-1150, -60), (-1400, 85), (-1600, 30), (-1763, 20)],
        label_ar="طريق الريف", label_en="Country Road")
    add("V1", "country", [(300, 2), (350, -230), (320, -480), (385, -700), (352, -885)],
        label_ar="طريق الوادي والشلال", label_en="Waterfall Valley Road")
    add("TA", "country", [(1350, -790), (1350, -900), (1350, -985)])
    add("T1", "track", [
        (1150, -985), (1500, -985), (1790, -995), (1880, -1060), (1830, -1140), (1600, -1155),
        (1470, -1235), (1555, -1335), (1720, -1380), (1860, -1490), (1830, -1650), (1600, -1690),
        (1350, -1610), (1240, -1460), (1300, -1310), (1190, -1190), (1100, -1090)], closed=True,
        label_ar="حلبة السباق الكبرى", label_en="Grand Prix Circuit")
    add("M1", "mountain", [
        (100, -885), (40, -965), (130, -1010), (-20, -1065), (140, -1110), (-10, -1165),
        (150, -1210), (150, -1310), (225, -1430), (100, -1530), (-150, -1610), (-400, -1665),
        (-650, -1600), (-800, -1480), (-690, -1375), (-950, -1300), (-1100, -1150),
        (-1150, -950), (-1155, -733)], tunnel_zones=[(-400, -1665, 110)],
        label_ar="الممر الجبلي", label_en="Mountain Pass")
    add("D1", "dirt", [
        (-1100, -1150), (-1350, -1210), (-1550, -1400), (-1760, -1300), (-1810, -1000),
        (-1600, -880), (-1400, -960), (-1250, -1060), (-1150, -952)],
        label_ar="مسار الغابة الترابي", label_en="Forest Rally Trail")
    add("C2", "country", [
        (-400, 60), (-460, 350), (-300, 600), (-390, 850), (-250, 1050), (-262, 1160)],
        label_ar="طريق الآثار", label_en="Heritage Road")
    add("R1", "cobble", [
        (-262, 1160), (-225, 1290), (-70, 1380), (-95, 1535), (-255, 1585), (-375, 1480),
        (-345, 1330), (-238, 1306)], label_ar="شوارع المدينة القديمة", label_en="Old Town Streets")
    add("D2", "dirt", [
        (-1572, 700), (-1420, 570), (-1160, 540), (-900, 610), (-770, 790), (-860, 950),
        (-1060, 930), (-1190, 900), (-1253, 1036)],
        label_ar="مسار الصحراء", label_en="Desert Trail")
    # shortcuts (gravel / alley), they only connect points of other roads
    add("S1", "alley", [(-1647, -340), (-1610, -100), (-1640, 150), (-1700, 420)], shortcut=True)
    add("S2", "alley", [(1200, -180), (1280, -100), (1360, -20)], shortcut=True)
    add("S4", "alley", [(-1150, 1120), (-1000, 1010), (-860, 1060), (-700, 1203)], shortcut=True)
    return R


RUINS = [
    # type, x, z, yaw(deg), scale
    ("temple", -200, 1440, 10, 1.0),
    ("amphitheater", -330, 1560, 200, 1.0),
    ("colonnade", -150, 1330, 35, 1.0),
    ("colonnade", -40, 1470, 95, 0.9),
    ("arch", -228, 1235, 15, 1.0),
    ("ziggurat", -420, 1380, 0, 1.0),
    ("obelisk", -120, 1550, 0, 1.0),
    ("obelisk", -300, 1350, 0, 0.8),
    ("wall", -380, 1260, 70, 1.0),
    ("wall", -50, 1600, 150, 1.0),
    ("broken", -260, 1500, 0, 1.0),
    ("broken", -110, 1400, 0, 1.0),
    ("broken", -350, 1440, 0, 1.0),
    ("aqueduct", -560, 980, 0, 1.0),
    ("lighthouse", 30, 1690, 0, 1.0),
    ("castle", -1500, -1650, 30, 1.0),
    ("windmill", -1250, 250, 0, 1.0),
    ("windmill", -1320, 340, 0, 1.0),
]


# =========================================================================== terrain
def build_base_terrain():
    log("base terrain")
    wx = fbm(X / 1100.0, Z / 1100.0, 3, 11) * 220
    wz = fbm(X / 1100.0 + 5.2, Z / 1100.0 - 1.7, 3, 12) * 220
    Xw = X + wx
    Zw = Z + wz

    # regional base elevation, high in the north, falling to the sea in the south
    base = np.interp(Z, [-2048, -1300, -800, -300, 300, 900, 1300, 1700],
                     [170, 120, 62, 42, 34, 24, 12, 0])
    hills = fbm(Xw / 650.0, Zw / 650.0, 6, 1)
    amp = 32 + 30 * ss(-200, -1400, X)  # rolling hills, rougher in the west
    h = base + hills * amp

    # northern mountain range (lower in the far west where the pine forest is)
    mnt = ss(-950, -1500, Z) * (1 - 0.62 * ss(-500, -1250, X)) * (1 - 0.45 * ss(1000, 1500, X))
    r = ridged(Xw / 620.0, Zw / 620.0, 7, 2)
    h += mnt * (r * 330 + 40)
    # forest highlands in the north-west
    fh = ss(-650, -1150, Z) * ss(-600, -1100, X)
    h += fh * (fbm(Xw / 380.0, Zw / 380.0, 5, 3) * 35 + 40)

    # spur ridge that the highway tunnels through
    spur = np.exp(-((X + 480) / 150.0) ** 2) * ss(-480, -980, Z)
    h += spur * (130 + 30 * r)

    # world edge walls (north, east, west) -- keep the playable area enclosed
    e = np.minimum.reduce([X + HALF, HALF - X, Z + HALF])
    h += (1 - ss(0, 320, e)) ** 2 * 260 * (1 - ss(1200, 1600, Z))

    # lake plateau + lake basin (hanging valley feeding the waterfall)
    lx, lz, lr = LAKE
    dl = np.sqrt((X - lx) ** 2 + (Z - lz) ** 2)
    plateau = 1 - ss(lr + 45, lr + 190, dl)
    h = lerp(h, LAKE_H + 6 + fbm(X / 120.0, Z / 120.0, 3, 4) * 6 + ss(lr, lr + 190, dl) * 12, plateau)
    basin = 1 - ss(lr * 0.75, lr * 1.08, dl)
    h = lerp(h, LAKE_H - 7.0 + 5.0 * (dl / lr) ** 2, basin)

    # city plateau
    x0, z0, x1, z1 = CITY_RECT
    dx = np.maximum(np.maximum(x0 - X, X - x1), 0)
    dz = np.maximum(np.maximum(z0 - Z, Z - z1), 0)
    dc = np.sqrt(dx * dx + dz * dz)
    city = 1 - ss(0, 220, dc)
    h = lerp(h, CITY_H + fbm(X / 300.0, Z / 300.0, 2, 5) * 0.0, city)

    # race circuit plateau
    x0, z0, x1, z1 = CIRCUIT_RECT
    dx = np.maximum(np.maximum(x0 - X, X - x1), 0)
    dz = np.maximum(np.maximum(z0 - Z, Z - z1), 0)
    dc = np.sqrt(dx * dx + dz * dz)
    circ = 1 - ss(0, 260, dc)
    h = lerp(h, CIRCUIT_H, circ)

    # desert (south-west): flat sandy basin with dunes and mesas
    des = ss(-500, -900, X) * ss(380, 650, Z) * (1 - ss(1350, 1550, Z))
    dune_dir = (X * 0.8 + Z * 0.6) / 55.0 + fbm(X / 300.0, Z / 300.0, 3, 6) * 3
    dunes = (np.abs(np.sin(dune_dir)) ** 1.6) * (6 + 6 * fbm(X / 500.0, Z / 500.0, 2, 7))
    dh = 26 + dunes + fbm(X / 400.0, Z / 400.0, 4, 8) * 6
    h = lerp(h, dh, des)
    rng = np.random.RandomState(9)
    for (mx, mz, mr, mh) in [(-1180, 780, 62, 42), (-960, 770, 42, 34), (-1880, 860, 70, 48),
                             (-1640, 1170, 68, 52)]:
        dm = np.sqrt((X - mx) ** 2 + (Z - mz) ** 2) + fbm(X / 60.0, Z / 60.0, 3, 10 + mx % 7) * 25
        top = 1 - ss(mr * 0.85, mr * 1.05, dm)
        h = np.maximum(h, lerp(h, dh + mh + rng.rand() * 5, top))

    # acropolis hill on the ruins peninsula
    ax, az = ACROPOLIS
    da = np.sqrt((X - ax) ** 2 + (Z - az) ** 2)
    hill = (1 - ss(60, 330, da))
    h = np.maximum(h, lerp(h, 38.0 + 6 * (1 - ss(0, 70, da)), hill))

    # coastline
    shore = (1420 + 110 * np.sin(X / 340.0) + 50 * np.sin(X / 150.0 + 1.0)
             - 300 * np.exp(-((X - 1380) / 260.0) ** 2)
             + 380 * np.exp(-((X + 200) / 260.0) ** 2)
             + fbm(X / 200.0, np.zeros_like(X), 3, 13) * 40)
    cliff = np.exp(-((X - 620) / 220.0) ** 2) + np.exp(-((X + 900) / 260.0) ** 2) * 0.8
    blend_w = 260 - 200 * np.clip(cliff, 0, 1)
    land = 1 - ss(shore - blend_w, shore - 10, Z)
    beach_h = np.clip((shore - Z) * 0.03, 0, 6) + 0.6
    h = lerp(beach_h, h, land)
    under = Z > shore
    depth = -np.minimum(34.0, (Z - shore) * 0.07) - 0.6
    h = np.where(under, np.minimum(h, depth + fbm(X / 90.0, Z / 90.0, 3, 14) * 1.5), h)

    # harbour quay (flat, low)
    hq = ss(980, 1080, X) * (1 - ss(1700, 1820, X)) * ss(700, 800, Z) * (1 - ss(1010, 1060, Z))
    h = lerp(h, 3.6, hq)

    # mountain pass corridor: carve a saddle valley for the pass road (keeps the ridge at the tunnel)
    ctrl = np.array([c[:2] for c in PASS_CORRIDOR], float)
    dense = resample(catmull_rom(ctrl, False, 1.0), 1.0, False)
    seg = np.linalg.norm(np.diff(ctrl, axis=0), axis=1)
    sc = np.concatenate([[0], np.cumsum(seg)])
    sd = np.concatenate([[0], np.cumsum(np.linalg.norm(np.diff(dense, axis=0), axis=1))])
    sd = sd / sd[-1] * sc[-1]
    hp = np.interp(sd, sc, [c[2] for c in PASS_CORRIDOR])
    dist, near = polyline_distance_field(dense)
    target = hp[near] + (np.clip(dist - 22, 0, None) / 130.0) ** 1.5 * 170
    tx, tz, tr = PASS_TUNNEL
    keep_ridge = 1 - ss(tr * 0.45, tr * 1.15, np.sqrt((X - tx) ** 2 + (Z - tz) ** 2))
    carve = np.minimum(h, target)
    fill = 1 - ss(18, 60, dist)
    carve = np.maximum(carve, lerp(carve, hp[near] - 0.5, fill))
    h = lerp(carve, h, keep_ridge)

    return h, dict(mountain=mnt, desert=des, city=city, circuit=circ, shore=shore, lake_d=dl,
                   forest_hi=fh)


river_info = {}


def carve_river(H):
    log("river")
    pts = np.array([(p[0], p[1]) for p in RIVER], float)
    dense = catmull_rom(pts, False, 1.0)
    dense = resample(dense, 1.0, False)
    # attributes per dense sample via arc length interpolation of control attrs
    seg = np.linalg.norm(np.diff(pts, axis=0), axis=1)
    s_ctrl = np.concatenate([[0], np.cumsum(seg)])
    seg_d = np.linalg.norm(np.diff(dense, axis=0), axis=1)
    s_d = np.concatenate([[0], np.cumsum(seg_d)])
    s_d = s_d / s_d[-1] * s_ctrl[-1]
    hw = np.interp(s_d, s_ctrl, [p[3] for p in RIVER])
    # bed: lake outlet level until the waterfall lip, then follow the (smoothed) terrain
    # downhill as a monotonic profile cut well below the surroundings
    s_lip = s_ctrl[1]
    s_base = s_ctrl[2]
    terr = gaussian_filter1d(sample_grid(H, dense[:, 0], dense[:, 1]), 60)
    bed = np.empty(len(dense))
    lower = terr - 16.0
    run = LAKE_H - 62.0
    for k in range(len(dense)):
        if s_d[k] <= s_lip:
            bed[k] = LAKE_H - 2.6
        elif s_d[k] < s_base:
            t = (s_d[k] - s_lip) / (s_base - s_lip)
            bed[k] = LAKE_H - 2.6 + (run - (LAKE_H - 2.6)) * t
        else:
            run = min(run - 0.004, lower[k])
            bed[k] = run
    sea_t = ss(1200, 1560, dense[:, 1])
    bed = lerp(bed, np.minimum(bed, -4.0 + (1 - sea_t) * 4), sea_t)
    river_info["base_h"] = float(bed[np.searchsorted(s_d, s_base)])
    vw = np.interp(s_d, s_ctrl, [p[4] for p in RIVER])
    dist, near = polyline_distance_field(dense)
    b = bed[near]
    w = hw[near]
    v = vw[near]
    water = b + 1.8
    channel = b - 1.2 * (1 - np.clip(dist / w, 0, 1) ** 2) + 0.3
    valley = water + 0.8 + ((np.clip(dist - w, 0, None)) / v) ** 1.6 * v * 0.55
    target = np.where(dist < w, channel, valley)
    newH = np.minimum(H, target)
    # raise low banks so the river never floods
    bank = (dist >= w) & (dist < w + 30)
    newH = np.where(bank, np.maximum(newH, water + 0.6 + (dist - w) * 0.04), newH)
    newH = np.where(H < SEA + 0.5, np.minimum(newH, H), newH)
    river = dict(pts=dense[::6], bed=bed[::6], hw=hw[::6], water=(bed + 1.8)[::6])
    return newH, river, dist


# =========================================================================== roads
class Road:
    def __init__(self, d, idx):
        self.d = d
        self.id = idx
        self.name = d["name"]
        self.type = d["type"]
        self.t = RTYPES[self.type]
        self.width = self.t["width"]
        self.closed = d.get("closed", False)
        dense = catmull_rom(d["ctrl"], self.closed, 0.5)
        self.xz = resample(dense, STEP, self.closed)
        self.n = len(self.xz)
        self.h = None
        self.bridge = np.zeros(self.n, bool)
        self.tunnel = np.zeros(self.n, bool)
        self.j_start = -1
        self.j_end = -1

    def length(self):
        return self.n * STEP


def find_junctions(roads):
    """Snap open road endpoints onto other roads; returns list of junctions."""
    all_pts = []
    owner = []
    for r in roads:
        all_pts.append(r.xz)
        owner += [(r.id, i) for i in range(r.n)]
    tree = cKDTree(np.vstack(all_pts))
    junctions = []
    jmap = {}

    def get_j(key, pos):
        for j in junctions:
            if np.linalg.norm(np.array(j["pos"][:2]) - pos) < 3.0:
                return j
        j = dict(id=len(junctions), pos=[float(pos[0]), float(pos[1])], links=[])
        junctions.append(j)
        return j

    for r in roads:
        if r.closed:
            continue
        for end in (0, r.n - 1):
            p = r.xz[end]
            cand = tree.query_ball_point(p, 32.0)
            best = None
            for c in cand:
                rid, k = owner[c]
                if rid == r.id and abs(k - end) * STEP < 60:
                    continue
                dd = np.linalg.norm(tree.data[c] - p)
                if best is None or dd < best[0]:
                    best = (dd, rid, k)
            if best is None:
                continue
            dist_j, rid, k = best
            if dist_j > 6:
                log("  snap %s end %d -> %s (%.1fm)" % (r.name, end, roads[rid].name, dist_j))
            target = roads[rid].xz[k].copy()
            # snap endpoint (shift the last 10 samples progressively)
            delta = target - p
            m = min(max(10, int(dist_j * 1.5)), r.n - 1)
            for q in range(m + 1):
                idx = end + q if end == 0 else end - q
                r.xz[idx] += delta * (1 - q / (m + 1))
            j = get_j(None, target)
            if (rid, k) not in [tuple(l) for l in j["links"]]:
                j["links"].append([rid, k])
            j["links"].append([r.id, end])
            if end == 0:
                r.j_start = j["id"]
            else:
                r.j_end = j["id"]
    return junctions


def ramp_max(req, step, grade):
    """Spread minimum-height requirements along the road with a max grade."""
    out = req.copy()
    n = len(req)
    for i in range(1, n):
        out[i] = max(out[i], out[i - 1] - grade * step)
    for i in range(n - 2, -1, -1):
        out[i] = max(out[i], out[i + 1] - grade * step)
    return out


BRIDGE_CLEAR = {"highway": 7.5, "avenue": 6.0, "track": 6.0}


def grade_limit(h, grade, pins, req, closed, iters=60):
    h = h.copy()
    n = len(h)
    lim = grade * STEP
    for _ in range(iters):
        for idx, val in pins:
            h[idx] = val
        for i in range(1, n):
            h[i] = min(max(h[i], h[i - 1] - lim), h[i - 1] + lim)
        if closed:
            h[0] = min(max(h[0], h[-1] - lim), h[-1] + lim)
        for idx, val in pins:
            h[idx] = val
        for i in range(n - 2, -1, -1):
            h[i] = min(max(h[i], h[i + 1] - lim), h[i + 1] + lim)
        h = np.maximum(h, req)
    for idx, val in pins:
        h[idx] = val
    return h


def compute_profiles(roads, H, river_dist, junctions):
    log("road profiles")
    tree_pts = []
    tree_own = []
    for r in roads:
        x = r.xz[:, 0]
        z = r.xz[:, 1]
        g = sample_grid(H, x, z)
        rd = sample_grid(river_dist, x, z, order=0)
        zone = np.zeros(r.n, bool)
        g_use = g.copy()
        for (tx, tz, rad) in r.d.get("tunnel_zones", []):
            m = np.hypot(x - tx, z - tz) < rad
            if m.any():
                idx = np.where(m)[0]
                a, b = max(idx[0] - 1, 0), min(idx[-1] + 1, r.n - 1)
                zone[a:b + 1] = True
                g_use[a:b + 1] = np.linspace(g_use[a], g_use[b], b - a + 1)
        sigma = r.t["sigma"] / STEP
        mode = "wrap" if r.closed else "nearest"
        h = gaussian_filter1d(g_use, sigma, mode=mode)
        h = gaussian_filter1d(h, sigma * 0.5, mode=mode)
        # requirements: stay above water / sea, clear rivers and earlier roads
        req = np.full(r.n, -1e9)
        wl = river_water_at(x, z)
        req = np.where(rd < 24, wl + 6.0, req)
        req = np.maximum(req, np.where(g < 1.5, 2.4, -1e9))
        if tree_pts:
            tree = cKDTree(np.vstack(tree_pts))
            own = np.concatenate(tree_own, axis=0)
            dd, ii = tree.query(r.xz, distance_upper_bound=r.width * 0.5 + 14)
            for k in range(r.n):
                if not np.isfinite(dd[k]):
                    continue
                orid, ok = own[ii[k]]
                o = roads[orid]
                if k * STEP < 70 and r.j_start >= 0:
                    continue
                if (r.n - 1 - k) * STEP < 70 and r.j_end >= 0:
                    continue
                if ok * STEP < 45 and o.j_start >= 0:
                    continue
                if (o.n - 1 - ok) * STEP < 45 and o.j_end >= 0:
                    continue
                if o.tunnel[ok]:
                    continue
                oh = o.h[ok]
                if o.bridge[ok] and oh - h[k] > 8.5:
                    continue  # we pass underneath an existing bridge
                req[k] = max(req[k], oh + 8.5)
        req = ramp_max(req, STEP, r.t["grade"] * 0.85)
        h = np.maximum(h, req)
        pins = []
        for end, jid in ((0, r.j_start), (r.n - 1, r.j_end)):
            if jid < 0:
                continue
            j = junctions[jid]
            for (rid, k) in j["links"]:
                if rid != r.id and roads[rid].h is not None:
                    pins.append((end, float(roads[rid].h[k])))
                    break
        # blend towards pins first so the grade limiter has less work
        for end, val in pins:
            span = int(min(r.n * 0.5, 220 / STEP))
            w = np.zeros(r.n)
            if end == 0:
                w[:span] = 1 - np.linspace(0, 1, span)
            else:
                w[-span:] = np.linspace(0, 1, span)
            w = w * w * (3 - 2 * w)
            h = h + (val - h[end]) * w
        h = grade_limit(h, r.t["grade"], pins, req, r.closed)
        h = gaussian_filter1d(h, 1.5, mode=mode)
        for end, val in pins:
            h[end] = val
        r.h = h
        r.ground = g
        clear = h - g
        thr = BRIDGE_CLEAR.get(r.type, 4.5)
        over_water = (rd < 22) & (h > wl + 2)
        over_sea = g < 0.5
        r.bridge = (clear > thr) | over_water | over_sea
        r.bridge = ndimage.binary_closing(r.bridge, iterations=3)
        r.bridge = ndimage.binary_opening(r.bridge, iterations=2) | over_water | over_sea
        tt = np.zeros(r.n, bool)
        if zone.any():
            t = ((g - h) > 7.0) & zone
            t = ndimage.binary_closing(t, iterations=4)
            lab, nl = ndimage.label(t)
            for li in range(1, nl + 1):
                idx = np.where(lab == li)[0]
                if len(idx) * STEP < 40:
                    continue
                a, b = idx[0], idx[-1]
                while a > 0 and g[a - 1] - h[a - 1] > 3.5:
                    a -= 1
                while b < r.n - 1 and g[b + 1] - h[b + 1] > 3.5:
                    b += 1
                tt[a:b + 1] = True
        r.tunnel = tt
        r.bridge &= ~tt
        grade = np.abs(np.diff(h)) / STEP
        log("  %-10s %-8s len=%5.0fm  h=[%5.1f..%5.1f] maxgrade=%4.1f%% bridge=%4.0fm tunnel=%4.0fm" % (
            r.name, r.type, r.length(), h.min(), h.max(), grade.max() * 100,
            r.bridge.sum() * STEP, r.tunnel.sum() * STEP))
        tree_pts.append(r.xz)
        tree_own.append(np.stack([np.full(r.n, r.id), np.arange(r.n)], -1))


_river_cache = {}


def river_water_at(x, z):
    if "tree" not in _river_cache:
        rv = _river_cache["river"]
        _river_cache["tree"] = cKDTree(rv["pts"])
    d, i = _river_cache["tree"].query(np.stack([np.atleast_1d(x), np.atleast_1d(z)], -1))
    return _river_cache["river"]["water"][i]


def flatten_for_roads(H, roads, river_dist=None):
    log("flatten terrain along roads")
    pts = []
    hh = []
    hw = []
    tun = []
    for r in roads:
        # dense 1 m resampling of non-bridge samples
        P = np.column_stack([r.xz, r.h, r.bridge.astype(float), r.tunnel.astype(float)])
        if r.closed:
            P = np.vstack([P, P[:1]])
        d = resample(P, 1.0, False)
        keep = d[:, 3] < 0.5
        pts.append(d[keep, :2])
        hh.append(d[keep, 2])
        hw.append(np.full(keep.sum(), r.width * 0.5))
        tun.append(d[keep, 4] > 0.5)
    pts = np.vstack(pts)
    hh = np.concatenate(hh)
    hw = np.concatenate(hw)
    tun = np.concatenate(tun)
    dist, near = polyline_distance_field(pts)
    hr = hh[near]
    w = hw[near]
    t = tun[near]
    caps = {}
    inner = w + 1.2
    diff = np.abs(H - hr)
    blend = np.clip(diff * 1.7, 5.0, 55.0)
    k = ss(inner, inner + blend, dist)
    newH = lerp(hr - 0.14, H, k)
    tunnel_cut = t & (dist < w + 3.0)
    cap_mask = t & (dist < w + 7.0) & (H > hr + 6)
    newH = np.where(t, np.where(tunnel_cut, hr - 0.14, H), newH)
    # save original heights above tunnels for the "cap" mesh
    jj, ii = np.where(cap_mask)
    caps = None
    if len(jj):
        caps = dict(i0=int(ii.min()), j0=int(jj.min()), i1=int(ii.max()), j1=int(jj.max()))
        sub = H[caps["j0"]:caps["j1"] + 1, caps["i0"]:caps["i1"] + 1].copy()
        m = cap_mask[caps["j0"]:caps["j1"] + 1, caps["i0"]:caps["i1"] + 1]
        sub[~m] = np.nan
        caps["h"] = sub
    if river_dist is not None:
        keep = river_dist < 30.0
        newH = np.where(keep, np.minimum(newH, H), newH)
    road_dist = dist - w
    return newH, road_dist, caps


# =========================================================================== city
def city_layout(rng):
    log("city lots")
    lots = []
    parks = []
    blocks = []
    cx, cz = 1040.0, 60.0
    special = {(1040, 140): "park", (720, 300): "park", (1200, -180): "construction",
               (880, -500): "park", (1360, 460): "plaza", (560, -500): "parking"}

    def half(kind_wide):
        return (RTYPES["avenue"]["width"] if kind_wide else RTYPES["street"]["width"]) * 0.5

    for xa, xb in zip(AVENUES[:-1], AVENUES[1:]):
        for za, zb in zip(STREETS[:-1], STREETS[1:]):
            x0 = xa + half(xa == WIDE_AVENUE)
            x1 = xb - half(xb == WIDE_AVENUE)
            z0 = za + half(za == WIDE_STREET)
            z1 = zb - half(zb == WIDE_STREET)
            kind = special.get((xa, za), "build")
            blocks.append(dict(rect=[x0, z0, x1, z1], kind=kind))
            if kind != "build":
                parks.append(dict(rect=[x0, z0, x1, z1], kind=kind))
                continue
            # subdivide block into lots
            inset = 5.0
            bx0, bz0, bx1, bz1 = x0 + inset, z0 + inset, x1 - inset, z1 - inset
            nx = rng.randint(2, 4)
            nz = rng.randint(2, 4)
            xsplit = np.sort(rng.uniform(0.25, 0.75, nx - 1)) if nx > 1 else []
            zsplit = np.sort(rng.uniform(0.25, 0.75, nz - 1)) if nz > 1 else []
            xe = [bx0] + [bx0 + (bx1 - bx0) * s for s in xsplit] + [bx1]
            ze = [bz0] + [bz0 + (bz1 - bz0) * s for s in zsplit] + [bz1]
            for i in range(len(xe) - 1):
                for j in range(len(ze) - 1):
                    lx0, lx1 = xe[i] + 1.5, xe[i + 1] - 1.5
                    lz0, lz1 = ze[j] + 1.5, ze[j + 1] - 1.5
                    if lx1 - lx0 < 12 or lz1 - lz0 < 12:
                        continue
                    mx = (lx0 + lx1) * 0.5
                    mz = (lz0 + lz1) * 0.5
                    d = math.hypot(mx - cx, (mz - cz) * 1.1)
                    down = math.exp(-(d / 330.0) ** 2)
                    hgt = 14 + down * rng.uniform(70, 210) + rng.uniform(0, 26)
                    if rng.rand() < 0.12 * down:
                        hgt *= 1.35
                    if down > 0.55:
                        style = rng.choice([0, 0, 1, 3])
                    elif down > 0.2:
                        style = rng.choice([0, 1, 1, 3, 2])
                    else:
                        style = rng.choice([2, 2, 1, 3])
                    # some lots get a tower set back on a podium
                    lots.append([round(mx, 2), round(mz, 2), round(lx1 - lx0, 2), round(lz1 - lz0, 2),
                                 round(hgt, 1), int(style), int(rng.randint(0, 1 << 20))])
    return dict(lots=lots, parks=parks, blocks=blocks, height=CITY_H,
                avenues=AVENUES, streets=STREETS, wide_avenue=WIDE_AVENUE, wide_street=WIDE_STREET)


# =========================================================================== objects
def scatter(H, splat_info, road_dist, river_dist, shore_mask, regions, rng):
    log("vegetation & rocks")
    gy, gx = np.gradient(H, CELL)
    slope = np.sqrt(gx * gx + gy * gy)
    objs = []
    # types: 0 pine, 1 broadleaf, 2 birch, 3 palm, 4 bush, 5 cactus, 6 rock, 7 dead tree, 8 cypress
    def place(count, density_fn, types, scale_rng, min_road=6.0, sub=None):
        xs_ = rng.uniform(-HALF + 40, HALF - 40, count)
        zs_ = rng.uniform(-HALF + 40, HALF - 40, count)
        gi = np.clip(((xs_ + HALF) / CELL).astype(int), 0, N - 1)
        gj = np.clip(((zs_ + HALF) / CELL).astype(int), 0, N - 1)
        dens = density_fn(gj, gi, xs_, zs_)
        ok = rng.rand(count) < dens
        ok &= road_dist[gj, gi] > min_road + rng.rand(count) * 4
        ok &= river_dist[gj, gi] > 26
        ok &= H[gj, gi] > 1.2
        for k in np.where(ok)[0]:
            t = types[rng.randint(len(types))] if isinstance(types, list) else types(gj[k], gi[k])
            y = float(sample_grid(H, xs_[k], zs_[k]))
            objs.append([t, xs_[k], y, zs_[k], rng.uniform(0, 6.283), rng.uniform(*scale_rng)])

    mnt = regions["mountain"]
    des = regions["desert"]
    city = regions["city"]
    fh = regions["forest_hi"]
    X0 = X
    Z0 = Z

    def pine_density(j, i, x, z):
        d = 0.75 * fh[j, i] + 0.45 * mnt[j, i] * (H[j, i] < 280) + 0.25 * ss(120, 180, H[j, i]) * (H[j, i] < 280)
        d *= np.clip(1.2 - slope[j, i], 0, 1)
        d *= (1 - city[j, i])
        return np.clip(d, 0, 1)

    place(700000, pine_density, [0, 0, 0, 8], (0.8, 1.35))

    def broad_density(j, i, x, z):
        west = ss(-150, -700, X0[j, i]) * (1 - ss(250, 550, Z0[j, i])) * (1 - fh[j, i]) * (1 - mnt[j, i])
        valley = np.exp(-((river_dist[j, i] - 60) / 90.0) ** 2) * 0.5
        clumps = ss(-0.05, 0.35, fbm(X0[j, i] / 220.0, Z0[j, i] / 220.0, 3, 77))
        d = (west * 0.85 + valley) * clumps
        d *= np.clip(1.1 - slope[j, i], 0, 1) * (1 - city[j, i]) * (1 - des[j, i])
        return np.clip(d, 0, 1)

    place(450000, broad_density, [1, 1, 1, 2, 4, 4], (0.75, 1.3))

    def palm_density(j, i, x, z):
        coast = (H[j, i] < 9) * (H[j, i] > 1.4) * 0.25
        return coast * (1 - city[j, i] * 0.5)

    place(160000, palm_density, [3, 3, 4], (0.85, 1.25))

    def desert_density(j, i, x, z):
        return des[j, i] * 0.05 * np.clip(1 - slope[j, i], 0, 1)

    place(260000, desert_density, [5, 5, 4, 7], (0.7, 1.3))

    def ruins_density(j, i, x, z):
        d = np.hypot(X0[j, i] - ACROPOLIS[0], Z0[j, i] - ACROPOLIS[1])
        return (1 - ss(150, 520, d)) * 0.12 * (d > 90)

    place(90000, ruins_density, [8, 8, 4, 1], (0.8, 1.2))

    def rock_density(j, i, x, z):
        d = mnt[j, i] * 0.05 + des[j, i] * 0.03 + ss(0.5, 1.0, slope[j, i]) * 0.08
        return d * (1 - city[j, i])

    place(220000, rock_density, [6], (0.6, 3.2), min_road=4.0)

    def meadow_density(j, i, x, z):
        mid = (1 - mnt[j, i]) * (1 - des[j, i]) * (1 - city[j, i]) * (1 - fh[j, i])
        return mid * 0.035 * np.clip(1 - slope[j, i] * 2, 0, 1)

    place(320000, meadow_density, [1, 4, 4, 2], (0.7, 1.2))
    objs = np.array(objs, dtype=np.float32)
    log("  objects:", len(objs), "by type:", np.bincount(objs[:, 0].astype(int)))
    return objs


# =========================================================================== splat
def build_splat(H, regions, road_dist, river_dist):
    log("splat")
    gy, gx = np.gradient(H, CELL)
    slope = np.sqrt(gx * gx + gy * gy)
    n1 = fbm(X / 90.0, Z / 90.0, 4, 200)
    n2 = fbm(X / 40.0, Z / 40.0, 3, 201)
    rock = ss(0.55, 0.95, slope + n2 * 0.15) + regions["mountain"] * ss(170, 260, H + n1 * 40) * 0.8
    rock = np.clip(rock, 0, 1)
    snow = ss(285, 330, H + n1 * 30) * (1 - ss(0.8, 1.2, slope))
    beach = (1 - ss(2.5, 6.0, H + n2 * 1.5)) * (H > -30)
    sand = np.clip(np.maximum(beach, regions["desert"] * (1 - rock * 0.7)), 0, 1)
    forest = np.clip(regions["forest_hi"] * 0.9 + regions["mountain"] * 0.4 * (1 - ss(150, 220, H)), 0, 1)
    dirt = np.clip(forest * ss(-0.2, 0.3, n1) + (1 - ss(0, 3.0, road_dist)) * 0.55
                   + ss(0.3, 0.7, n2) * 0.25 * (1 - regions["city"]), 0, 1)
    dirt = np.where(river_dist < 30, np.maximum(dirt, (1 - ss(18, 30, river_dist)) * 0.6), dirt)
    city = regions["city"]
    dirt = dirt * (1 - city * 0.7)
    # normalise so that grass = 1 - sum
    w = np.stack([rock, sand * (1 - rock), dirt * (1 - rock) * (1 - sand), snow], -1)
    s = w.sum(-1, keepdims=True)
    w = np.where(s > 1, w / np.maximum(s, 1e-6), w)
    return w


# =========================================================================== events
def build_graph(roads, junctions):
    nodes = []
    index = {}
    for r in roads:
        for i in range(r.n):
            index[(r.id, i)] = len(nodes)
            nodes.append((r.id, i))
    adj = [[] for _ in nodes]

    def link(a, b, w):
        adj[a].append((b, w))
        adj[b].append((a, w))

    for r in roads:
        for i in range(r.n - 1):
            link(index[(r.id, i)], index[(r.id, i + 1)], STEP)
        if r.closed:
            link(index[(r.id, r.n - 1)], index[(r.id, 0)], STEP)
    for j in junctions:
        ls = [index[(a, b)] for a, b in j["links"]]
        for p in range(len(ls)):
            for q in range(p + 1, len(ls)):
                link(ls[p], ls[q], 1.0)
    pts = np.vstack([r.xz for r in roads])
    return nodes, index, adj, cKDTree(pts)


def shortest(adj, a, b, banned=None):
    dist = {a: 0.0}
    prev = {}
    pq = [(0.0, a)]
    while pq:
        d, u = heapq.heappop(pq)
        if u == b:
            break
        if d > dist.get(u, 1e18):
            continue
        for v, w in adj[u]:
            if banned is not None and v in banned:
                continue
            nd = d + w
            if nd < dist.get(v, 1e18):
                dist[v] = nd
                prev[v] = u
                heapq.heappush(pq, (nd, v))
    path = [b]
    while path[-1] != a:
        path.append(prev[path[-1]])
    return path[::-1]


def route_from_waypoints(roads, graph, wps, closed, avoid_types=("alley",)):
    nodes, index, adj, tree = graph
    banned = set(k for k, (rid, i) in enumerate(nodes) if roads[rid].type in avoid_types)
    seq = []
    targets = list(wps) + ([wps[0]] if closed else [])
    ids = []
    for w in targets:
        cand = tree.query(w, k=8)[1]
        best = None
        for c in cand:
            if c not in banned:
                best = c
                break
        ids.append(best)
    for a, b in zip(ids[:-1], ids[1:]):
        p = shortest(adj, a, b, banned)
        if seq:
            p = p[1:]
        seq += p
    pts = []
    hw_flag = []
    for k in seq:
        rid, i = nodes[k]
        r = roads[rid]
        pts.append([r.xz[i, 0], r.h[i], r.xz[i, 1], r.width])
        hw_flag.append(1.0 if r.type == "highway" else 0.0)
    pts = np.array(pts)
    # keep right on divided highways: shift the race line onto the travel carriageway
    hw_flag = gaussian_filter1d(np.array(hw_flag), 3.0)
    tang = np.gradient(pts[:, [0, 2]], axis=0)
    tang /= np.linalg.norm(tang, axis=1, keepdims=True) + 1e-9
    right = np.stack([-tang[:, 1], tang[:, 0]], -1)
    pts[:, 0] += right[:, 0] * 5.2 * hw_flag
    pts[:, 2] += right[:, 1] * 5.2 * hw_flag
    # remove duplicates / tiny steps
    keep = [0]
    for i in range(1, len(pts)):
        if np.linalg.norm(pts[i, [0, 2]] - pts[keep[-1], [0, 2]]) > 1.0:
            keep.append(i)
    pts = pts[keep]
    if closed and np.linalg.norm(pts[0, [0, 2]] - pts[-1, [0, 2]]) < 3:
        pts = pts[:-1]
    pts = resample(pts, STEP, closed)
    return pts


def route_open(H, wps, closed):
    dense = catmull_rom(wps, closed, 0.5)
    pts = resample(dense, STEP, closed)
    y = sample_grid(H, pts[:, 0], pts[:, 1])
    return np.column_stack([pts[:, 0], y, pts[:, 1], np.full(len(pts), 40.0)])


def place_checkpoints(route, closed, spacing, shortcuts_spans, length):
    cps = []
    d = spacing
    end = length if closed else length - 30
    while d < end - spacing * 0.45:
        moved = True
        while moved:
            moved = False
            for (a, b) in shortcuts_spans:
                if a - 30 <= d <= b + 30:
                    d = b + 45
                    moved = True
        if d >= end - spacing * 0.3:
            break
        cps.append(d)
        d += spacing
    cps.append(0.0 if closed else length - 25)
    return cps


def build_events(roads, junctions, H):
    log("events")
    graph = build_graph(roads, junctions)
    nodes, index, adj, _ = graph
    comp = -np.ones(len(nodes), int)
    nc = 0
    for st in range(len(nodes)):
        if comp[st] >= 0:
            continue
        stack = [st]
        comp[st] = nc
        while stack:
            u = stack.pop()
            for v, _w in adj[u]:
                if comp[v] < 0:
                    comp[v] = nc
                    stack.append(v)
        nc += 1
    if nc > 1:
        for c in range(nc):
            names = sorted(set(roads[nodes[k][0]].name for k in np.where(comp == c)[0]))
            log("  component", c, names[:12], "..." if len(names) > 12 else "")
    short = [r for r in roads if r.d.get("shortcut")]
    E = []

    def ev(eid, kind, name_ar, name_en, wps, closed=False, laps=1, spacing=1100.0, open_route=False,
           police=True, traffic=True, desc_ar="", desc_en="", cp_width=None):
        if open_route:
            route = route_open(H, wps, closed)
        else:
            route = route_from_waypoints(roads, graph, wps, closed)
        seg = np.linalg.norm(np.diff(route[:, [0, 2]], axis=0), axis=1)
        s = np.concatenate([[0], np.cumsum(seg)])
        length = s[-1] + (np.linalg.norm(route[0, [0, 2]] - route[-1, [0, 2]]) if closed else 0)
        rtree = cKDTree(route[:, [0, 2]])
        spans = []
        alts = []
        for r in short:
            d0, i0 = rtree.query(r.xz[0])
            d1, i1 = rtree.query(r.xz[-1])
            if d0 < 14 and d1 < 14 and abs(s[i1] - s[i0]) > 40:
                a, b = sorted((s[i0], s[i1]))
                spans.append((a, b))
                pts = r.xz if s[i0] < s[i1] else r.xz[::-1]
                hh = r.h if s[i0] < s[i1] else r.h[::-1]
                alts.append(dict(enter=float(a), exit=float(b),
                                 pts=np.round(np.column_stack([pts[:, 0], hh, pts[:, 1]]), 2).ravel().tolist()))
        cps_d = place_checkpoints(route, closed, spacing, spans, length)
        cps = []
        for d in cps_d:
            i = int(np.clip(np.searchsorted(s, d), 0, len(route) - 1))
            i2 = min(i + 1, len(route) - 1)
            i1 = max(i - 1, 0)
            tang = route[i2, [0, 2]] - route[i1, [0, 2]]
            tang /= np.linalg.norm(tang) + 1e-9
            w = cp_width if cp_width else route[i, 3] + 12
            cps.append(dict(d=round(float(s[i]), 1), pos=np.round(route[i, :3], 2).tolist(),
                            dir=np.round(tang, 4).tolist(), width=float(w)))
        E.append(dict(id=eid, kind=kind, name_ar=name_ar, name_en=name_en, desc_ar=desc_ar, desc_en=desc_en,
                      closed=closed, laps=laps, police=police, traffic=traffic, open=open_route,
                      length=round(float(length), 1),
                      route=np.round(route[:, :4], 2).ravel().tolist(), checkpoints=cps, shortcuts=alts))
        log("  %-18s %-8s len=%6.0fm cps=%d shortcuts=%d" % (eid, kind, length, len(cps), len(alts)))

    ev("city_sprint", "sprint", "سباق وسط المدينة", "Downtown Sprint",
       [(1040, 600), (1040, -180), (1200, -180), (1200, -20), (1360, -20), (1520, -20), (1800, -20),
        (1795, -250), (1700, -660), (1350, -800), (1350, -950)],
       spacing=950, desc_ar="انطلق بين ناطحات السحاب ثم اخرج إلى الطريق السريع نحو الحلبة",
       desc_en="Blast between skyscrapers, then hit the highway to the circuit")
    ev("grand_prix", "circuit", "الجائزة الكبرى", "Grand Prix",
       [(1300, -985), (1830, -1140), (1555, -1335), (1830, -1650), (1240, -1460)], closed=True, laps=3,
       spacing=1000, police=False, traffic=False,
       desc_ar="حلبة سباق مخصصة بثلاث لفات - بدون شرطة", desc_en="Dedicated race track, 3 laps, no police")
    ev("mountain_pass", "sprint", "نزول الممر الجبلي", "Mountain Pass Descent",
       [(-650, -1600), (-400, -1665), (-150, -1610), (225, -1430), (150, -1300), (-20, -1065), (100, -885),
        (420, -865), (750, -800)],
       spacing=1050, desc_ar="منعطفات حادة وجسور ونفق فوق الجبل", desc_en="Hairpins, a tunnel and the waterfall")
    ev("coastal_run", "sprint", "انطلاقة الساحل", "Coastal Run",
       [(-1500, 820), (-1150, 1120), (-700, 1205), (-300, 1155), (330, 1235), (960, 985), (1300, 830),
        (1630, 780), (1785, 560)],
       spacing=1250, desc_ar="الطريق السريع الساحلي مروراً بجسر النهر والميناء",
       desc_en="Coastal highway over the river mouth to the harbour")
    ev("desert_open", "circuit", "رالي الصحراء المفتوح", "Open Desert Rally",
       DESERT_LOOP, closed=True, laps=2,
       open_route=True, spacing=600, cp_width=70.0, traffic=False,
       desc_ar="لا يوجد طريق! اعبر الكثبان بين نقاط التفتيش بحرية كاملة",
       desc_en="No roads! Cross the dunes between wide checkpoints in total freedom")
    ev("forest_rally", "circuit", "رالي الغابة", "Forest Rally",
       [(-1350, -1210), (-1760, -1300), (-1600, -880), (-1150, -952), (-1100, -1150)], closed=True, laps=2,
       spacing=900, traffic=False, desc_ar="طريق ترابي ضيق بين أشجار الصنوبر مع قفزات",
       desc_en="Narrow dirt trail through the pines, with jumps")
    ev("ruins_circuit", "circuit", "حلبة المدينة الأثرية", "Ancient Ruins Circuit",
       [(-238, 1306), (-60, 1385), (-90, 1565), (-395, 1495), (-345, 1330)], closed=True, laps=3,
       spacing=600, desc_ar="شوارع حجرية ضيقة حول المعبد القديم", desc_en="Cobbled lanes around the old temple")
    ev("grand_tour", "sprint", "الجولة الكبرى", "Grand Tour",
       [(560, -20), (270, 5), (-400, 60), (-900, -120), (-1400, 85), (-1763, 20), (-1700, 450), (-1500, 820),
        (-1150, 1120), (-700, 1205), (-262, 1160), (-225, 1290), (-60, 1385)],
       spacing=1300, desc_ar="رحلة طويلة: الريف ثم الطريق السريع ثم المدينة الأثرية",
       desc_en="Epic run: countryside, highway and the ancient city")

    # challenges (solo)
    def chal(eid, kind, name_ar, name_en, pos, d, target, desc_ar, desc_en):
        E.append(dict(id=eid, kind=kind, name_ar=name_ar, name_en=name_en, pos=pos, dir=d, target=target,
                      desc_ar=desc_ar, desc_en=desc_en))

    def at_road(name, frac):
        r = [q for q in roads if q.name == name][0]
        i = int(r.n * frac)
        t = r.xz[min(i + 1, r.n - 1)] - r.xz[max(i - 1, 0)]
        t = t / np.linalg.norm(t)
        return [round(float(r.xz[i, 0]), 2), round(float(r.h[i]), 2), round(float(r.xz[i, 1]), 2)], \
            [round(float(t[0]), 4), round(float(t[1]), 4)]

    p, d = at_road("H1", 0.11)
    chal("speed_trap", "speedtrap", "رادار السرعة", "Speed Trap", p, d, 250,
         "اعبر الرادار بأعلى سرعة ممكنة", "Hit the speed camera as fast as you can")
    p, d = at_road("M1", 0.35)
    chal("drift_zone", "drift", "منطقة الانجراف", "Drift Zone", p, d, 25000,
         "اجمع نقاط الانجراف على المنعطفات الجبلية خلال 60 ثانية",
         "Score drift points on the mountain bends within 60 s")
    p, d = at_road("D2", 0.05)
    chal("jump_challenge", "jump", "تحدي القفز", "Jump Challenge", p, d, 60,
         "اقفز أطول مسافة ممكنة من منحدرات الصحراء", "Make the longest jump off the desert ramps")
    return E


def ramps(roads, H):
    out = []
    spec = [("D2", 0.12, 1.6), ("D2", 0.38, 2.0), ("D2", 0.62, 1.8), ("D2", 0.86, 2.2),
            ("D1", 0.18, 1.5), ("D1", 0.55, 1.7), ("S1", 0.5, 1.5), ("S2", 0.5, 1.4),
            ("S4", 0.45, 1.6)]
    for name, frac, hgt in spec:
        if hgt <= 0:
            continue
        r = [q for q in roads if q.name == name][0]
        i = int(r.n * frac)
        t = r.xz[min(i + 2, r.n - 1)] - r.xz[max(i - 2, 0)]
        yaw = math.atan2(t[0], t[1])
        out.append(dict(pos=[round(float(r.xz[i, 0]), 2), round(float(r.h[i]), 2), round(float(r.xz[i, 1]), 2)],
                        yaw=round(yaw, 4), length=hgt * 6.5, width=min(r.width - 1, 7.0), height=hgt))
    # free-standing ramps on the open desert rally line
    wps = np.array(DESERT_LOOP, float)
    line = resample(catmull_rom(wps, True, 0.5), STEP, True)
    for frac, hgt in ((0.22, 2.4), (0.47, 2.0), (0.66, 2.8), (0.85, 2.2)):
        i = int(len(line) * frac)
        t = line[i + 2] - line[i - 2]
        x, z = line[i]
        out.append(dict(pos=[round(float(x), 2), round(sample_grid(H, x, z), 2), round(float(z), 2)],
                        yaw=round(math.atan2(t[0], t[1]), 4), length=hgt * 6.5, width=8.0, height=hgt))
    return out


# =========================================================================== map image
def make_map(H, splat, roads, river, city):
    log("map image")
    M = 2048
    small = ndimage.zoom(H, M / N, order=1)[:M, :M]
    sp = ndimage.zoom(splat, (M / N, M / N, 1), order=1)[:M, :M]
    gy, gx = np.gradient(small, CELL * N / M)
    light = np.clip(0.75 + (-gx * 0.6 - gy * 0.8) * 0.9, 0.35, 1.25)
    grass = np.array([0.36, 0.48, 0.25])
    rockc = np.array([0.55, 0.53, 0.50])
    sandc = np.array([0.86, 0.77, 0.58])
    dirtc = np.array([0.45, 0.38, 0.26])
    snowc = np.array([0.95, 0.96, 0.98])
    w_g = np.clip(1 - sp.sum(-1), 0, 1)
    c = (grass * w_g[..., None] + rockc * sp[..., 0:1] + sandc * sp[..., 1:2] + dirtc * sp[..., 2:3] + snowc * sp[..., 3:4])
    c = c * light[..., None]
    water = small < SEA
    deep = np.clip(-small / 30.0, 0, 1)
    wc = np.array([0.20, 0.45, 0.62]) * (1 - deep[..., None] * 0.4)
    c = np.where(water[..., None], wc, c)
    img = Image.fromarray((np.clip(c, 0, 1) * 255).astype(np.uint8))
    d = ImageDraw.Draw(img)
    sc = M / (2 * HALF)

    def P(x, z):
        return ((x + HALF) * sc, (z + HALF) * sc)

    # city blocks
    for b in city["blocks"]:
        x0, z0, x1, z1 = b["rect"]
        colr = (96, 98, 104) if b["kind"] == "build" else (86, 132, 70)
        d.rectangle([P(x0, z0), P(x1, z1)], fill=colr)
    # river + lake
    rp = [P(p[0], p[1]) for p in river["pts"]]
    for k in range(len(rp) - 1):
        wpx = max(2, int(river["hw"][k] * 2 * sc))
        d.line([rp[k], rp[k + 1]], fill=(52, 115, 160), width=wpx)
    lx, lz, lr = LAKE
    d.ellipse([P(lx - lr * 0.95, lz - lr * 0.95), P(lx + lr * 0.95, lz + lr * 0.95)], fill=(52, 115, 160))
    order = ["dirt", "alley", "cobble", "mountain", "country", "street", "avenue", "track", "highway"]
    colors = {"highway": (255, 196, 64), "avenue": (240, 240, 240), "street": (225, 225, 225),
              "country": (250, 250, 245), "mountain": (250, 240, 220), "dirt": (176, 132, 84),
              "track": (230, 60, 60), "cobble": (205, 180, 140), "alley": (170, 140, 100)}
    for t in order:
        for r in roads:
            if r.type != t:
                continue
            pts = [P(x, z) for x, z in r.xz]
            if r.closed:
                pts.append(pts[0])
            wpx = max(3, int(r.width * sc * 1.6))
            d.line(pts, fill=(30, 30, 30), width=wpx + 3, joint="curve")
            d.line(pts, fill=colors[t], width=wpx, joint="curve")
    img = img.filter(ImageFilter.SMOOTH)
    img.save(os.path.join(OUT, "map.png"), optimize=True)


# =========================================================================== main
def main():
    os.makedirs(OUT, exist_ok=True)
    rng = np.random.RandomState(1234)
    H, regions = build_base_terrain()
    H, river, river_dist = carve_river(H)
    _river_cache["river"] = river
    layout = roads_layout()
    roads = [Road(d, i) for i, d in enumerate(layout)]
    junctions = find_junctions(roads)
    log("junctions:", len(junctions))
    compute_profiles(roads, H, river_dist, junctions)
    if os.environ.get("WB_DEBUG"):
        import pickle
        with open(os.environ["WB_DEBUG"], "wb") as f:
            pickle.dump(dict(H=H, roads=[dict(name=r.name, type=r.type, xz=r.xz, h=r.h, g=r.ground,
                                              bridge=r.bridge, tunnel=r.tunnel) for r in roads]), f)
    H, road_dist, caps = flatten_for_roads(H, roads, river_dist)
    # flatten pads for ruins structures
    for (t, x, z, yaw, s) in RUINS:
        rad = {"temple": 46, "amphitheater": 60, "ziggurat": 40, "castle": 50, "aqueduct": 0}.get(t, 14)
        if rad <= 0:
            continue
        d = np.sqrt((X - x) ** 2 + (Z - z) ** 2)
        hc = float(sample_grid(H, x, z))
        k = ss(rad, rad + 25, d)
        protect = road_dist < 3
        H = np.where(protect, H, lerp(hc, H, k))
    splat = build_splat(H, regions, road_dist, river_dist)
    city = city_layout(rng)
    objs = scatter(H, splat, road_dist, river_dist, None, regions, rng)
    # remove vegetation inside city blocks / on ruins pads
    keep = np.ones(len(objs), bool)
    for b in city["blocks"]:
        x0, z0, x1, z1 = b["rect"]
        inside = (objs[:, 1] > x0 - 6) & (objs[:, 1] < x1 + 6) & (objs[:, 3] > z0 - 6) & (objs[:, 3] < z1 + 6)
        keep &= ~inside
    for (t, x, z, yaw, s) in RUINS:
        rad = {"temple": 50, "amphitheater": 66, "ziggurat": 45, "castle": 56, "aqueduct": 0}.get(t, 16)
        keep &= np.hypot(objs[:, 1] - x, objs[:, 3] - z) > rad
    objs = objs[keep]
    # city park trees
    extra = []
    for p in city["parks"]:
        if p["kind"] not in ("park", "plaza"):
            continue
        x0, z0, x1, z1 = p["rect"]
        n = 70 if p["kind"] == "park" else 18
        for _ in range(n):
            x = rng.uniform(x0 + 6, x1 - 6)
            z = rng.uniform(z0 + 6, z1 - 6)
            extra.append([rng.choice([1, 1, 2, 4]), x, CITY_H + 0.3, z, rng.uniform(0, 6.28), rng.uniform(0.8, 1.2)])
    if extra:
        objs = np.vstack([objs, np.array(extra, np.float32)])

    events = build_events(roads, junctions, H)
    ramp_list = ramps(roads, H)
    ruins = []
    for (t, x, z, yaw, s) in RUINS:
        ruins.append(dict(type=t, pos=[x, round(float(sample_grid(H, x, z)), 2), z], yaw=math.radians(yaw), scale=s))
    # aqueduct follows a line
    for r in ruins:
        if r["type"] == "aqueduct":
            pts = []
            for k in range(26):
                x = -560 + k * 13.5
                z = 980 + k * 11.0
                pts.append([x, round(float(sample_grid(H, x, z)), 2), z])
            r["pts"] = pts

    # ---------------------------------------------------------- write files
    Hf = H.astype(np.float32)
    with open(os.path.join(OUT, "heightmap.bin"), "wb") as f:
        raw = Hf.tobytes()
        f.write(zlib.compress(raw, 9))
    log("heightmap raw bytes", len(raw), "min", float(H.min()), "max", float(H.max()))
    sp = np.concatenate([splat, np.zeros(splat.shape[:2] + (0,))], -1)
    chans = [Image.fromarray((np.clip(sp[..., c], 0, 1) * 255 + 0.5).astype(np.uint8), "L").resize((1024, 1024), Image.BILINEAR)
             for c in range(4)]
    Image.merge("RGBA", chans).save(os.path.join(OUT, "splat.png"))
    with open(os.path.join(OUT, "objects.bin"), "wb") as f:
        f.write(zlib.compress(objs.astype(np.float32).tobytes(), 9))
    make_map(H, splat, roads, river, city)

    road_out = []
    for r in roads:
        road_out.append(dict(
            id=r.id, name=r.name, type=r.type, width=r.width, lanes=r.t["lanes"], mat=r.t["mat"],
            rail=r.t["rail"], light=r.t["light"], closed=r.closed, city=bool(r.d.get("city", False)),
            shortcut=bool(r.d.get("shortcut", False)), j_start=r.j_start, j_end=r.j_end,
            label_ar=r.d.get("label_ar", ""), label_en=r.d.get("label_en", ""),
            pts=np.round(np.column_stack([r.xz[:, 0], r.h, r.xz[:, 1]]), 3).ravel().tolist(),
            bridge=r.bridge.astype(int).tolist(), tunnel=r.tunnel.astype(int).tolist(),
            ground=np.round(r.ground, 2).tolist()))
    for j in junctions:
        rid, k = j["links"][0]
        j["pos"] = [j["pos"][0], float(roads[rid].h[k]), j["pos"][1]]
    cap_out = None
    if caps is not None:
        hh = caps["h"]
        cap_out = dict(i0=caps["i0"], j0=caps["j0"], w=hh.shape[1], h=hh.shape[0],
                       data=np.where(np.isnan(hh), -9999, np.round(hh, 2)).ravel().tolist())
    world = dict(
        version=1, n=N, cell=CELL, half=HALF, sea=SEA,
        roads=road_out, junctions=junctions,
        river=dict(pts=np.round(np.column_stack([river["pts"][:, 0], river["water"], river["pts"][:, 1]]), 2).ravel().tolist(),
                   hw=np.round(river["hw"], 2).tolist()),
        lake=dict(x=LAKE[0], z=LAKE[1], r=LAKE[2], h=LAKE_H),
        waterfall=dict(top=[WATERFALL_TOP[0], LAKE_H - 0.8, WATERFALL_TOP[1]],
                       bottom=[WATERFALL_BOTTOM[0], river_info["base_h"] + 1.8, WATERFALL_BOTTOM[1]], width=16.0),
        city=city, ruins=ruins, ramps=ramp_list, events=events, tunnel_caps=cap_out,
        spawn=dict(pos=[1040.0, CITY_H + 1.0, 560.0], yaw=0.0),
    )
    with open(os.path.join(OUT, "world.json"), "w") as f:
        json.dump(world, f, separators=(",", ":"), ensure_ascii=False)
    log("done. world.json %.1f KB" % (os.path.getsize(os.path.join(OUT, "world.json")) / 1024))


if __name__ == "__main__":
    main()
