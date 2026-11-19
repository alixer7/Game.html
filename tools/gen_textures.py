#!/usr/bin/env python3
"""Procedural PBR texture generator for Velocity Rush.

Every texture in the game is generated here from math (no third-party assets),
so the project is fully self-contained and license-free.
Outputs tileable albedo(+roughness in alpha) and normal maps, stacked into
vertical strips that Godot imports as Texture2DArray.

usage: python3 tools/gen_textures.py
"""
import os
import numpy as np
from PIL import Image

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
OUT = os.path.join(ROOT, "assets", "textures")
S = 1024


# --------------------------------------------------------------------------- noise
def _perm(seed):
    rng = np.random.RandomState(seed)
    p = rng.permutation(256)
    ang = rng.rand(256) * 2 * np.pi
    return np.concatenate([p, p]), np.stack([np.cos(ang), np.sin(ang)], -1)


def pnoise(x, y, period, seed):
    """Tileable 2D gradient noise. x, y are lattice coordinates in [0, period)."""
    perm, g = _perm(seed)
    xi = np.floor(x).astype(np.int64)
    yi = np.floor(y).astype(np.int64)
    xf = x - xi
    yf = y - yi
    x0 = xi % period
    y0 = yi % period
    x1 = (xi + 1) % period
    y1 = (yi + 1) % period

    def gdot(ix, iy, dx, dy):
        h = perm[(perm[ix & 255] + iy) & 511] & 255
        gg = g[h]
        return gg[..., 0] * dx + gg[..., 1] * dy

    n00 = gdot(x0, y0, xf, yf)
    n10 = gdot(x1, y0, xf - 1, yf)
    n01 = gdot(x0, y1, xf, yf - 1)
    n11 = gdot(x1, y1, xf - 1, yf - 1)
    u = xf * xf * xf * (xf * (xf * 6 - 15) + 10)
    v = yf * yf * yf * (yf * (yf * 6 - 15) + 10)
    a = n00 + (n10 - n00) * u
    b = n01 + (n11 - n01) * u
    return (a + (b - a) * v) * 1.41


UV = np.mgrid[0:S, 0:S].astype(np.float64) / S  # [0]=row(y) [1]=col(x)
YY, XX = UV[0], UV[1]


def fbm(base, octaves, seed, gain=0.5, warp=None):
    x, y = XX, YY
    if warp is not None:
        x = (x + warp[0]) % 1.0
        y = (y + warp[1]) % 1.0
    tot = np.zeros((S, S))
    amp, norm = 1.0, 0.0
    for o in range(octaves):
        p = base * (2 ** o)
        tot += amp * pnoise(x * p, y * p, p, seed + o * 17)
        norm += amp
        amp *= gain
    return tot / norm


def ridged(base, octaves, seed):
    tot = np.zeros((S, S))
    amp, norm = 1.0, 0.0
    for o in range(octaves):
        p = base * (2 ** o)
        n = 1.0 - np.abs(pnoise(XX * p, YY * p, p, seed + o * 31))
        tot += amp * n * n
        norm += amp
        amp *= 0.5
    return tot / norm


def voronoi(cells, seed, jitter=0.85):
    """Tileable Worley noise: returns F1, F2 (in cell units) and cell id."""
    rng = np.random.RandomState(seed)
    pts = (rng.rand(cells, cells, 2) - 0.5) * jitter + 0.5
    ids = rng.rand(cells, cells)
    x = XX * cells
    y = YY * cells
    cx = np.floor(x).astype(int)
    cy = np.floor(y).astype(int)
    f1 = np.full((S, S), 9.0)
    f2 = np.full((S, S), 9.0)
    cid = np.zeros((S, S))
    for oy in (-1, 0, 1):
        for ox in (-1, 0, 1):
            nx = cx + ox
            ny = cy + oy
            px = pts[ny % cells, nx % cells, 0] + nx
            py = pts[ny % cells, nx % cells, 1] + ny
            d = np.sqrt((px - x) ** 2 + (py - y) ** 2)
            closer = d < f1
            f2 = np.where(closer, f1, np.minimum(f2, d))
            cid = np.where(closer, ids[ny % cells, nx % cells], cid)
            f1 = np.where(closer, d, f1)
    return f1, f2, cid


def speckles(count, rmin, rmax, seed):
    """Tileable field of small round stones; returns height field 0..1 and id field."""
    rng = np.random.RandomState(seed)
    h = np.zeros((S, S))
    tone = np.zeros((S, S))
    for _ in range(count):
        cx, cy = rng.rand(2) * S
        r = rng.uniform(rmin, rmax)
        t = rng.rand()
        x0, x1 = int(cx - r - 1), int(cx + r + 2)
        y0, y1 = int(cy - r - 1), int(cy + r + 2)
        ys = np.arange(y0, y1)
        xs = np.arange(x0, x1)
        gy, gx = np.meshgrid(ys, xs, indexing="ij")
        d = np.sqrt((gx - cx) ** 2 + (gy - cy) ** 2) / r
        bump = np.clip(1 - d * d, 0, 1)
        sl = (gy % S, gx % S)
        h[sl] = np.maximum(h[sl], bump)
        tone[sl] = np.where(bump > 0.05, t, tone[sl])
    return h, tone


def blur(a, r=1):
    out = a.copy()
    for _ in range(r):
        out = (out + np.roll(out, 1, 0) + np.roll(out, -1, 0) + np.roll(out, 1, 1) + np.roll(out, -1, 1)) / 5.0
    return out


def normal_from_height(h, strength):
    dx = (np.roll(h, -1, 1) - np.roll(h, 1, 1)) * 0.5 * strength * S / 1024.0
    dy = (np.roll(h, -1, 0) - np.roll(h, 1, 0)) * 0.5 * strength * S / 1024.0
    n = np.stack([-dx, dy, np.ones_like(h)], -1)
    n /= np.linalg.norm(n, axis=-1, keepdims=True)
    return n * 0.5 + 0.5


def mix(a, b, t):
    t = t[..., None] if np.ndim(t) == 2 else t
    return np.asarray(a) * (1 - t) + np.asarray(b) * t


def col(r, g, b):
    return np.array([r, g, b], dtype=np.float64)


def ss(e0, e1, x):
    t = np.clip((x - e0) / (e1 - e0), 0, 1)
    return t * t * (3 - 2 * t)


def pack_albedo(rgb, rough):
    rgb = np.clip(rgb, 0, 1)
    rough = np.broadcast_to(np.asarray(rough, dtype=np.float64), rgb.shape[:2])
    a = np.concatenate([rgb, np.clip(rough, 0, 1)[..., None]], -1)
    return (a * 255 + 0.5).astype(np.uint8)


def pack_normal(n):
    return (np.clip(n, 0, 1) * 255 + 0.5).astype(np.uint8)


# --------------------------------------------------------------------------- materials
def grass():
    w = (fbm(4, 3, 900) * 0.08, fbm(4, 3, 901) * 0.08)
    macro = fbm(3, 4, 1, warp=w)
    mid = fbm(16, 4, 2)
    fine = fbm(128, 2, 3)
    blades = pnoise(XX * 256, YY * 64, 64, 4) * 0.5 + pnoise(XX * 64, YY * 256, 64, 5) * 0.5
    base = mix(col(0.20, 0.30, 0.09), col(0.30, 0.38, 0.12), ss(-0.4, 0.4, macro))
    base = mix(base, col(0.38, 0.38, 0.16), ss(0.25, 0.6, mid) * 0.6)  # dry patches
    base = mix(base, col(0.12, 0.20, 0.06), ss(0.0, 0.5, -mid) * 0.5)  # lush dark
    v = 1.0 + fine * 0.25 + blades * 0.18
    rgb = base * v[..., None]
    h = blades * 0.6 + fine * 0.4 + mid * 0.3
    return pack_albedo(rgb, 0.92 - fine * 0.05), pack_normal(normal_from_height(h, 2.2))


def rock():
    w = (fbm(3, 4, 10) * 0.18, fbm(3, 4, 11) * 0.18)
    r = ridged(3, 6, 12)
    warp = fbm(2, 3, 13) * 0.15
    strata = np.sin((YY + warp + r * 0.05) * np.pi * 2 * 11) * 0.5 + 0.5
    f1, f2, cid = voronoi(7, 14, 1.0)
    cracks = ss(0.0, 0.035, f2 - f1) * 0.6 + 0.4
    fine = fbm(48, 4, 15)
    grit = fbm(160, 2, 17)
    macro = fbm(2, 4, 16, warp=w)
    lichen = ss(0.25, 0.55, fbm(10, 4, 18))
    base = mix(col(0.33, 0.31, 0.29), col(0.52, 0.49, 0.45), ss(-0.45, 0.45, macro + r * 0.3))
    base = mix(base, col(0.47, 0.40, 0.32), (strata * 0.35)[..., None] * ss(0.2, 0.8, r)[..., None])
    base = base * (0.8 + 0.2 * cracks)[..., None] * (0.94 + cid * 0.12)[..., None]
    base = base * (1 + fine * 0.22 + grit * 0.1)[..., None]
    base = mix(base, base * col(0.85, 0.95, 0.75), lichen * 0.35)
    h = r * 1.0 + strata * 0.1 + cracks * 0.08 + fine * 0.45 + grit * 0.12 + macro * 0.6
    return pack_albedo(base, 0.8 + fine * 0.1), pack_normal(normal_from_height(h, 4.0))


def sand():
    warp = fbm(3, 3, 20) * 0.6
    ripples = np.sin((XX * 0.6 + YY + warp) * np.pi * 2 * 26) * 0.5 + 0.5
    grain = fbm(200, 2, 21)
    macro = fbm(3, 4, 22)
    base = mix(col(0.72, 0.60, 0.42), col(0.82, 0.71, 0.52), ss(-0.4, 0.4, macro))
    base = base * (1 + grain * 0.12 + (ripples - 0.5) * 0.06)[..., None]
    h = ripples * 0.6 + grain * 0.3
    return pack_albedo(base, 0.95), pack_normal(normal_from_height(h, 1.6))


def dirt():
    macro = fbm(3, 4, 30)
    mid = fbm(12, 4, 31)
    peb, tone = speckles(1700, 2.0, 7.0, 32)
    fine = fbm(128, 2, 33)
    base = mix(col(0.30, 0.22, 0.15), col(0.42, 0.33, 0.23), ss(-0.4, 0.4, macro))
    base = mix(base, col(0.24, 0.18, 0.12), ss(0.1, 0.5, mid) * 0.5)
    pcol = mix(col(0.40, 0.37, 0.33), col(0.55, 0.50, 0.44), tone)
    base = mix(base, pcol, ss(0.1, 0.5, peb))
    base = base * (1 + fine * 0.15)[..., None]
    h = peb * 1.0 + mid * 0.3 + fine * 0.2
    return pack_albedo(base, 0.9 - peb * 0.15), pack_normal(normal_from_height(h, 4.0))


def snow():
    macro = fbm(3, 4, 40)
    fine = fbm(64, 3, 41)
    spark = (np.random.RandomState(42).rand(S, S) > 0.997).astype(float)
    base = mix(col(0.80, 0.85, 0.93), col(0.95, 0.96, 0.98), ss(-0.5, 0.4, macro))
    base = base * (1 + fine * 0.05)[..., None] + spark[..., None] * 0.05
    h = macro * 0.6 + fine * 0.3
    return pack_albedo(base, 0.55 - spark * 0.4 + fine * 0.05), pack_normal(normal_from_height(h, 2.0))


def forest_floor():
    macro = fbm(3, 4, 50)
    mid = fbm(20, 4, 51)
    leaves_h, leaves_t = speckles(2600, 2.5, 6.0, 52)
    fine = fbm(128, 2, 53)
    base = mix(col(0.20, 0.15, 0.09), col(0.30, 0.23, 0.13), ss(-0.4, 0.4, macro))
    lcol = mix(col(0.40, 0.25, 0.10), col(0.30, 0.32, 0.12), leaves_t)
    base = mix(base, lcol, ss(0.2, 0.6, leaves_h) * 0.7)
    base = mix(base, col(0.16, 0.22, 0.08), ss(0.2, 0.6, mid) * 0.5)  # moss
    base = base * (1 + fine * 0.15)[..., None]
    h = leaves_h * 0.5 + mid * 0.3 + fine * 0.3
    return pack_albedo(base, 0.93), pack_normal(normal_from_height(h, 3.0))


def asphalt():
    macro = fbm(2, 4, 60)
    mid = fbm(10, 4, 61)
    rng = np.random.RandomState(62)
    agg = rng.rand(S, S)
    agg = blur(agg, 1)
    stones = ss(0.56, 0.66, agg)
    pits = ss(0.40, 0.33, agg)
    fine = fbm(256, 1, 63)
    f1, f2, _ = voronoi(5, 64, 1.0)
    crack = 1 - ss(0.0, 0.015, f2 - f1)
    crack *= ss(0.25, 0.45, fbm(4, 3, 65))
    base = mix(col(0.11, 0.11, 0.115), col(0.17, 0.17, 0.17), ss(-0.5, 0.5, macro))
    base = base * (1 + mid * 0.15)[..., None]
    base = base + stones[..., None] * 0.07 - pits[..., None] * 0.04
    base = base * (1 - crack * 0.5)[..., None]
    h = stones * 0.5 - pits * 0.4 + fine * 0.15 - crack * 0.8
    return pack_albedo(base, 0.86 - stones * 0.1 + pits * 0.05), pack_normal(normal_from_height(h, 3.0))


def cobble():
    f1, f2, cid = voronoi(14, 70, 0.7)
    edge = f2 - f1
    stone = ss(0.04, 0.22, edge)
    dome = np.clip(1 - f1 * 1.4, 0, 1)
    fine = fbm(96, 3, 71)
    macro = fbm(3, 3, 72)
    scol = mix(col(0.40, 0.37, 0.33), col(0.58, 0.53, 0.46), cid)
    scol = scol * (1 + macro * 0.15)[..., None]
    mortar = col(0.22, 0.20, 0.17)
    base = mix(mortar, scol, stone) * (1 + fine * 0.12)[..., None]
    h = stone * 0.7 + dome * 0.4 + fine * 0.1
    return pack_albedo(base, 0.7 + (1 - stone) * 0.25 - dome * 0.1), pack_normal(normal_from_height(h, 6.0))


def gravel():
    peb, tone = speckles(5500, 1.5, 4.5, 80)
    fine = fbm(128, 2, 81)
    macro = fbm(3, 4, 82)
    base = mix(col(0.36, 0.32, 0.27), col(0.46, 0.41, 0.34), ss(-0.4, 0.4, macro))
    pcol = mix(col(0.45, 0.43, 0.40), col(0.62, 0.58, 0.52), tone)
    base = mix(base, pcol, ss(0.15, 0.45, peb))
    base = base * (1 + fine * 0.1)[..., None]
    h = peb + fine * 0.2
    return pack_albedo(base, 0.92), pack_normal(normal_from_height(h, 4.5))


def concrete():
    macro = fbm(2, 4, 90)
    mid = fbm(16, 4, 91)
    fine = fbm(256, 1, 92)
    pores = ss(0.45, 0.35, blur(np.random.RandomState(93).rand(S, S), 1))
    stains = ss(0.2, 0.6, fbm(4, 4, 94))
    base = mix(col(0.52, 0.51, 0.49), col(0.62, 0.61, 0.58), ss(-0.5, 0.5, macro))
    base = base * (1 + mid * 0.08 + fine * 0.05)[..., None] * (1 - pores * 0.15)[..., None]
    base = mix(base, base * col(0.8, 0.78, 0.74), stains * 0.5)
    h = mid * 0.2 + fine * 0.15 - pores * 0.4
    return pack_albedo(base, 0.88), pack_normal(normal_from_height(h, 2.0))


def masonry():
    """Ancient sandstone ashlar blocks for ruins."""
    rows = 8
    y = YY * rows
    row = np.floor(y)
    off = (row % 2) * 0.5 + np.sin(row * 7.1) * 0.13
    x = XX * 4 + off
    colid = np.floor(x)
    fx = x - colid
    fy = y - row
    e = np.minimum(np.minimum(fx, 1 - fx) * 2.2, np.minimum(fy, 1 - fy))
    block = ss(0.015, 0.06, e)
    bid = (np.sin(colid * 12.9898 + row * 78.233) * 43758.5453) % 1.0
    macro = fbm(3, 4, 100)
    fine = fbm(96, 3, 101)
    erosion = ss(0.1, 0.5, fbm(12, 4, 102))
    scol = mix(col(0.62, 0.52, 0.38), col(0.76, 0.66, 0.50), bid)
    scol = scol * (1 + macro * 0.12 + fine * 0.12)[..., None]
    scol = mix(scol, scol * 0.75, erosion * 0.6)
    base = mix(col(0.32, 0.27, 0.20), scol, block)
    h = block * 0.8 + fine * 0.2 - erosion * 0.3 + ss(0.06, 0.3, e) * 0.2
    return pack_albedo(base, 0.86), pack_normal(normal_from_height(h, 6.0))


def bark():
    x = XX * 6
    stripes = pnoise(x * 3, YY * 0.5 * 6, 18, 110) + 0.5 * pnoise(x * 9, YY * 2 * 6, 54, 111)
    fine = fbm(64, 3, 112)
    base = mix(col(0.20, 0.15, 0.11), col(0.36, 0.29, 0.22), ss(-0.6, 0.6, stripes))
    base = base * (1 + fine * 0.15)[..., None]
    h = stripes * 0.8 + fine * 0.2
    return pack_albedo(base, 0.9), pack_normal(normal_from_height(h, 8.0))


def sidewalk():
    tiles = 8
    fx = (XX * tiles) % 1
    fy = (YY * tiles) % 1
    tid = np.floor(XX * tiles) * 7 + np.floor(YY * tiles) * 13
    e = np.minimum(np.minimum(fx, 1 - fx), np.minimum(fy, 1 - fy))
    gap = ss(0.0, 0.03, e)
    var = (np.sin(tid * 12.9898) * 43758.5453) % 1.0
    fine = fbm(128, 2, 120)
    macro = fbm(3, 3, 121)
    base = mix(col(0.48, 0.47, 0.45), col(0.60, 0.59, 0.56), var * 0.6 + ss(-0.4, 0.4, macro) * 0.4)
    base = base * (1 + fine * 0.08)[..., None]
    base = mix(col(0.25, 0.25, 0.24), base, gap)
    h = gap * 0.5 + fine * 0.1
    return pack_albedo(base, 0.8), pack_normal(normal_from_height(h, 3.0))


# --------------------------------------------------------------------------- foliage atlases
def leaf_atlas(seed, needle=False):
    """RGBA foliage card: clusters of leaves (or pine needles) with alpha."""
    n = 512
    img = np.zeros((n, n, 4))
    rng = np.random.RandomState(seed)
    yy, xx = np.mgrid[0:n, 0:n].astype(np.float64)
    if needle:
        # dense fir branches: twig with packed needles angled forward on both sides
        for b in range(8):
            cy = 32 + b * 62 + rng.uniform(-8, 8)
            x0 = rng.uniform(4, 30)
            length = rng.uniform(430, 500)
            nk = int(length / 1.6)
            for k in range(nk):
                t = k / nk
                px = x0 + k * 1.6
                py = cy + np.sin(t * 3.0) * 4
                for side in (-1, 1):
                    ln = rng.uniform(26, 38) * (1.0 - 0.55 * t)
                    ang = side * rng.uniform(0.55, 1.0)
                    ex = px + np.cos(ang) * ln * 0.75
                    ey = py + np.sin(ang) * ln
                    steps = int(ln)
                    shade = rng.uniform(0.7, 1.2)
                    for st in range(steps):
                        u = st / max(steps - 1, 1)
                        ix = int(px + (ex - px) * u)
                        iy = int(py + (ey - py) * u)
                        for dx in (0, 1):
                            if 0 <= ix + dx < n and 0 <= iy < n:
                                c = np.array([0.08, 0.17, 0.08]) * shade * (0.75 + 0.35 * u)
                                img[iy, ix + dx, :3] = c
                                img[iy, ix + dx, 3] = 1
            # twig
            for k in range(int(length)):
                ix = int(x0 + k)
                iy = int(cy + np.sin(k / length * 3.0) * 4)
                if 0 <= ix < n:
                    img[iy:iy + 2, ix, :3] = np.array([0.22, 0.15, 0.1])
                    img[iy:iy + 2, ix, 3] = 1
    else:
        for _ in range(900):
            cx, cy = rng.uniform(20, n - 20, 2)
            # keep leaves clustered in a rough blob
            if (cx - n / 2) ** 2 + (cy - n / 2) ** 2 > (n * 0.47) ** 2:
                continue
            a = rng.uniform(0, np.pi)
            L = rng.uniform(9, 16)
            W = L * rng.uniform(0.38, 0.55)
            x0, x1 = int(cx - L - 2), int(cx + L + 3)
            y0, y1 = int(cy - L - 2), int(cy + L + 3)
            sx = xx[y0:y1, x0:x1] - cx
            sy = yy[y0:y1, x0:x1] - cy
            u = sx * np.cos(a) + sy * np.sin(a)
            v = -sx * np.sin(a) + sy * np.cos(a)
            d = (u / L) ** 2 + (v / W) ** 2
            m = d < 1.0
            shade = rng.uniform(0.7, 1.25)
            hue = rng.rand()
            c = (np.array([0.16, 0.30, 0.07]) * (1 - hue) + np.array([0.27, 0.36, 0.09]) * hue) * shade
            vein = np.exp(-(v / (W * 0.12)) ** 2) * 0.15
            sub = img[y0:y1, x0:x1]
            light = (0.85 + 0.25 * (1 - d))[..., None]
            sub[m, :3] = (c * light[m] * (1 - vein[m][..., None]))
            sub[m, 3] = 1
    rgb = img[..., :3]
    # dilate colors into transparent area to avoid dark fringes when mipmapped
    a = img[..., 3]
    filled = rgb.copy()
    mask = a > 0.5
    for _ in range(8):
        acc = np.zeros_like(filled)
        cnt = np.zeros(mask.shape)
        for dy, dx in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            acc += np.roll(np.roll(filled * mask[..., None], dy, 0), dx, 1)
            cnt += np.roll(np.roll(mask, dy, 0), dx, 1)
        grow = (~mask) & (cnt > 0)
        filled[grow] = acc[grow] / cnt[grow][..., None]
        mask = mask | grow
    out = np.concatenate([np.clip(filled, 0, 1), a[..., None]], -1)
    return (out * 255 + 0.5).astype(np.uint8)


def save(name, arr):
    Image.fromarray(arr).save(os.path.join(OUT, name), optimize=True)
    print("wrote", name, arr.shape)


def strip(layers):
    return np.concatenate(layers, axis=0)


def main():
    os.makedirs(OUT, exist_ok=True)
    terr = [grass(), rock(), sand(), dirt(), snow(), forest_floor()]
    save("terrain_albedo.png", strip([t[0] for t in terr]))
    save("terrain_normal.png", strip([t[1][..., :3] for t in terr]))
    road = [asphalt(), cobble(), gravel(), concrete(), sidewalk(), masonry()]
    save("surface_albedo.png", strip([t[0] for t in road]))
    save("surface_normal.png", strip([t[1][..., :3] for t in road]))
    b = bark()
    save("bark_albedo.png", b[0])
    save("bark_normal.png", b[1])
    save("leaves_broad.png", leaf_atlas(7))
    save("leaves_pine.png", leaf_atlas(8, needle=True))


if __name__ == "__main__":
    main()
