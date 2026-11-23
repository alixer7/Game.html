#!/usr/bin/env python3
"""Generates the stylized, tileable texture library for Wildspark Kart.

Everything is procedural and deterministic (fixed seeds) so the art is original
and reproducible:  python3 tools/gen_textures.py  (writes into textures/)

Techniques: FFT-filtered fractal noise (perfectly tileable), wrap-around Worley
cells, colour ramps tuned for a bright painterly look, Sobel normal maps.
"""
import os
import math
import numpy as np
from PIL import Image, ImageDraw, ImageFilter

OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "textures")
os.makedirs(OUT, exist_ok=True)


# ----------------------------------------------------------------------------- noise
def fractal(n, beta=2.0, seed=0, aniso=(1.0, 1.0)):
    """Tileable 1/f^beta noise in [0,1]. aniso stretches frequencies (x, y)."""
    rng = np.random.default_rng(seed)
    w = rng.standard_normal((n, n))
    f = np.fft.fft2(w)
    fy = np.fft.fftfreq(n)[:, None] * aniso[1]
    fx = np.fft.fftfreq(n)[None, :] * aniso[0]
    r = np.sqrt(fx * fx + fy * fy)
    r[0, 0] = 1.0
    f = f / (r ** (beta * 0.5))
    f[0, 0] = 0
    out = np.real(np.fft.ifft2(f))
    out -= out.min()
    out /= out.max() + 1e-9
    return out


def band(n, lo, hi, seed=0):
    """Tileable band-limited noise (frequencies lo..hi cycles per tile)."""
    rng = np.random.default_rng(seed)
    w = rng.standard_normal((n, n))
    f = np.fft.fft2(w)
    fy = np.fft.fftfreq(n)[:, None] * n
    fx = np.fft.fftfreq(n)[None, :] * n
    r = np.sqrt(fx * fx + fy * fy)
    mask = np.exp(-((np.log(r + 1e-6) - math.log((lo * hi) ** 0.5)) ** 2) / (2 * (math.log(hi / lo) / 2 + 1e-3) ** 2))
    out = np.real(np.fft.ifft2(f * mask))
    out -= out.min()
    out /= out.max() + 1e-9
    return out


def worley(n, cells, seed=0, jitter=0.9):
    """Wrap-around Worley noise. Returns F1, F2 distances (in cell units) and cell id."""
    rng = np.random.default_rng(seed)
    pts = (np.stack(np.meshgrid(np.arange(cells), np.arange(cells), indexing="xy"), -1).reshape(-1, 2)
           + 0.5 + (rng.random((cells * cells, 2)) - 0.5) * jitter)
    ids = np.arange(cells * cells)
    yy, xx = np.mgrid[0:n, 0:n] / n * cells
    f1 = np.full((n, n), 1e9)
    f2 = np.full((n, n), 1e9)
    cid = np.zeros((n, n), dtype=np.int32)
    for ox in (-cells, 0, cells):
        for oy in (-cells, 0, cells):
            for i, (px, py) in enumerate(pts):
                d = np.sqrt((xx - (px + ox)) ** 2 + (yy - (py + oy)) ** 2)
                closer = d < f1
                f2 = np.where(closer, f1, np.minimum(f2, d))
                cid = np.where(closer, ids[i], cid)
                f1 = np.where(closer, d, f1)
    return f1, f2, cid


def ramp(t, stops):
    """stops: list of (pos, (r,g,b)) with rgb 0..1 -> image float array"""
    t = np.clip(t, 0, 1)
    out = np.zeros(t.shape + (3,))
    for i in range(len(stops) - 1):
        p0, c0 = stops[i]
        p1, c1 = stops[i + 1]
        m = (t >= p0) & (t <= p1)
        k = ((t - p0) / max(p1 - p0, 1e-6))[m]
        k = k * k * (3 - 2 * k)
        for ch in range(3):
            out[..., ch][m] = c0[ch] + (c1[ch] - c0[ch]) * k
    return out


def normal_from_height(h, strength=4.0):
    dx = (np.roll(h, -1, 1) - np.roll(h, 1, 1)) * 0.5
    dy = (np.roll(h, -1, 0) - np.roll(h, 1, 0)) * 0.5
    nx = -dx * strength
    ny = dy * strength  # OpenGL style (+Y up) as Godot expects
    nz = np.ones_like(h)
    l = np.sqrt(nx * nx + ny * ny + nz * nz)
    n = np.stack([nx / l, ny / l, nz / l], -1)
    return (n * 0.5 + 0.5)


def save_rgb(name, arr):
    img = Image.fromarray((np.clip(arr, 0, 1) * 255).astype(np.uint8), "RGB")
    img.save(os.path.join(OUT, name), optimize=True)
    print("wrote", name, img.size)


def save_rgba(name, arr):
    img = Image.fromarray((np.clip(arr, 0, 1) * 255).astype(np.uint8), "RGBA")
    img.save(os.path.join(OUT, name), optimize=True)
    print("wrote", name, img.size)


def save_gray(name, arr):
    img = Image.fromarray((np.clip(arr, 0, 1) * 255).astype(np.uint8), "L")
    img.save(os.path.join(OUT, name), optimize=True)
    print("wrote", name, img.size)


def wrap_draw(n, draw_fn):
    """Draw on a 3x tiled canvas and fold it back so strokes wrap seamlessly."""
    big = Image.new("RGBA", (n * 3, n * 3), (0, 0, 0, 0))
    d = ImageDraw.Draw(big)
    draw_fn(d, n)
    arr = np.asarray(big).astype(np.float32) / 255.0
    out = np.zeros((n, n, 4), np.float32)
    for i in range(3):
        for j in range(3):
            tile = arr[i * n:(i + 1) * n, j * n:(j + 1) * n]
            a = tile[..., 3:4]
            out[..., :3] = out[..., :3] * (1 - a) + tile[..., :3] * a
            out[..., 3:4] = np.maximum(out[..., 3:4], a)
    return out


def composite(base, layer):
    a = layer[..., 3:4]
    return base * (1 - a) + layer[..., :3] * a


# ----------------------------------------------------------------------------- textures
def grass(n=1024):
    macro = fractal(n, 2.6, 11)
    mid = band(n, 8, 32, 12)
    t = macro * 0.65 + mid * 0.35
    base = ramp(t, [(0.0, (0.13, 0.30, 0.09)), (0.35, (0.22, 0.45, 0.13)), (0.7, (0.36, 0.60, 0.18)), (1.0, (0.52, 0.70, 0.25))])
    rng = np.random.default_rng(13)

    def blades(d, n):
        for _ in range(26000):
            x = rng.uniform(n, 2 * n)
            y = rng.uniform(n, 2 * n)
            L = rng.uniform(5, 13)
            a = math.radians(rng.normal(-90, 22))
            lum = rng.uniform(-1, 1)
            if lum > 0:
                c = (int(90 + 70 * lum), int(150 + 60 * lum), int(45 + 25 * lum), int(110 + 80 * rng.random()))
            else:
                c = (int(25 + 20 * -lum), int(70 + 20 * -lum), int(20), int(90 + 70 * rng.random()))
            d.line([(x, y), (x + L * math.cos(a), y + L * math.sin(a))], fill=c, width=2)
        for _ in range(700):  # clover clumps
            x = rng.uniform(n, 2 * n)
            y = rng.uniform(n, 2 * n)
            r = rng.uniform(2.5, 4.5)
            for k in range(3):
                ang = k * 2.1 + rng.uniform(0, 1)
                cx, cy = x + math.cos(ang) * r, y + math.sin(ang) * r
                d.ellipse([cx - r, cy - r, cx + r, cy + r], fill=(70, 135, 50, 170))

    layer = wrap_draw(n, blades)
    img = composite(base, layer)
    img = np.clip(img * (0.92 + 0.16 * mid[..., None]), 0, 1)
    save_rgb("grass_albedo.png", img)


def dirt(n=1024):
    macro = fractal(n, 2.4, 21)
    fine = band(n, 40, 160, 22)
    t = macro * 0.7 + fine * 0.3
    base = ramp(t, [(0.0, (0.30, 0.19, 0.11)), (0.4, (0.46, 0.31, 0.18)), (0.75, (0.58, 0.42, 0.26)), (1.0, (0.68, 0.53, 0.35))])
    h = t * 0.5
    rng = np.random.default_rng(23)
    hmap = Image.new("L", (n * 3, n * 3), 0)
    hd = ImageDraw.Draw(hmap)

    def pebbles(d, n):
        for _ in range(1500):
            x = rng.uniform(n, 2 * n)
            y = rng.uniform(n, 2 * n)
            r = rng.gamma(2.0, 1.6) + 1.0
            e = rng.uniform(0.6, 1.0)
            g = rng.uniform(0.4, 0.7)
            col = (int(255 * g * 0.9), int(255 * g * 0.76), int(255 * g * 0.6), 230)
            d.ellipse([x - r - 1, y - r * e + 1, x + r + 1, y + r * e + 2], fill=(40, 26, 16, 150))
            d.ellipse([x - r, y - r * e, x + r, y + r * e], fill=col)
            d.ellipse([x - r * 0.5, y - r * e * 0.7, x, y - r * e * 0.2], fill=(255, 240, 215, 45))
            hd.ellipse([x - r, y - r * e, x + r, y + r * e], fill=int(160 + 90 * rng.random()))

    layer = wrap_draw(n, pebbles)
    img = composite(base, layer)
    harr = np.asarray(hmap).astype(np.float32) / 255.0
    hh = np.zeros((n, n))
    for i in range(3):
        for j in range(3):
            hh = np.maximum(hh, harr[i * n:(i + 1) * n, j * n:(j + 1) * n])
    hh = np.asarray(Image.fromarray((hh * 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(1.5))) / 255.0
    save_rgb("dirt_albedo.png", img)
    save_rgb("dirt_normal.png", normal_from_height(h + hh * 0.8, 6.0))


def cobble(n=1024, cells=9):
    f1, f2, cid = worley(n, cells, 31, 0.75)
    edge = f2 - f1
    rng = np.random.default_rng(32)
    tints = rng.random((cells * cells, 3))
    stone_lum = 0.55 + 0.3 * tints[cid, 0]
    warm = tints[cid, 1]
    noise = band(n, 30, 120, 33)
    macro = fractal(n, 2.2, 34)
    bevel = np.clip(edge / 0.22, 0, 1)
    bevel = np.sqrt(bevel)
    mortar = edge < 0.07
    col = np.zeros((n, n, 3))
    col[..., 0] = stone_lum * (0.78 + 0.16 * warm)
    col[..., 1] = stone_lum * (0.74 + 0.08 * warm)
    col[..., 2] = stone_lum * (0.70 - 0.06 * warm)
    col *= (0.82 + 0.3 * noise)[..., None] * (0.75 + 0.35 * bevel)[..., None]
    col *= (0.9 + 0.2 * macro)[..., None]
    moss = np.clip((macro - 0.45) * 3.0, 0, 1) * (1 - bevel)
    moss_col = np.array([0.28, 0.42, 0.14])
    col = col * (1 - moss[..., None] * 0.85) + moss_col * moss[..., None] * 0.85
    mortar_col = np.array([0.22, 0.20, 0.14])
    col[mortar] = mortar_col * (0.8 + 0.4 * noise[mortar][..., None])
    height = bevel * 0.8 + noise * 0.12
    height[mortar] = 0.0
    save_rgb("cobble_albedo.png", col)
    save_rgb("cobble_normal.png", normal_from_height(height, 7.0))


def rock(n=1024):
    f1, f2, cid = worley(n, 7, 41, 1.0)
    f1b, f2b, cidb = worley(n, 18, 42, 1.0)
    rng = np.random.default_rng(43)
    slope = rng.random((49, 2)) - 0.5
    yy, xx = np.mgrid[0:n, 0:n] / n
    facet = (slope[cid, 0] * xx + slope[cid, 1] * yy) * 3.0
    facet = facet - np.floor(facet)
    strata = (np.sin((yy * 22 + fractal(n, 2.0, 44) * 3.0) * math.pi * 2) * 0.5 + 0.5)
    fine = band(n, 40, 200, 45)
    t = np.clip(0.35 * facet + 0.25 * strata + 0.25 * fine + 0.25 * (f2b - f1b), 0, 1)
    base = ramp(t, [(0.0, (0.25, 0.24, 0.27)), (0.35, (0.42, 0.40, 0.41)), (0.7, (0.58, 0.55, 0.52)), (1.0, (0.74, 0.70, 0.64))])
    crack = np.clip(1 - (f2 - f1) / 0.05, 0, 1) ** 2
    crack2 = np.clip(1 - (f2b - f1b) / 0.04, 0, 1) ** 2 * 0.6
    base *= (1 - 0.55 * np.maximum(crack, crack2))[..., None]
    height = 0.5 * facet + 0.2 * strata + 0.15 * fine - 0.6 * np.maximum(crack, crack2)
    save_rgb("rock_albedo.png", base)
    save_rgb("rock_normal.png", normal_from_height(height, 5.0))


def sand(n=512):
    yy, xx = np.mgrid[0:n, 0:n] / n
    warp = fractal(n, 2.5, 51)
    ripple = np.sin((yy * 18 + xx * 4 + warp * 4) * math.pi * 2) * 0.5 + 0.5
    grain = band(n, 80, 250, 52)
    t = 0.5 * fractal(n, 2.2, 53) + 0.25 * ripple + 0.25 * grain
    base = ramp(t, [(0.0, (0.62, 0.52, 0.36)), (0.5, (0.80, 0.70, 0.50)), (1.0, (0.92, 0.85, 0.66))])
    save_rgb("sand_albedo.png", base)
    save_rgb("sand_normal.png", normal_from_height(ripple * 0.4 + grain * 0.2, 3.0))


def mud(n=512):
    t = 0.6 * fractal(n, 2.3, 61) + 0.4 * band(n, 20, 80, 62)
    f1, f2, _ = worley(n, 10, 63, 1.0)
    puddle = np.clip((t - 0.62) * 5, 0, 1)
    base = ramp(t, [(0.0, (0.17, 0.12, 0.07)), (0.5, (0.28, 0.20, 0.12)), (1.0, (0.38, 0.29, 0.18))])
    base = base * (1 - puddle[..., None] * 0.4) + np.array([0.20, 0.22, 0.18]) * puddle[..., None] * 0.4
    save_rgb("mud_albedo.png", base)


def planks(n=1024):
    rows = 8
    yy, xx = np.mgrid[0:n, 0:n] / n
    row = np.floor(yy * rows).astype(int)
    rng = np.random.default_rng(71)
    offs = rng.random(rows)
    lens = rng.uniform(0.35, 0.6, rows)
    u = (xx + offs[row]) / lens[row]
    plank_id = np.floor(u).astype(int) + row * 37
    fu = u - np.floor(u)
    fv = yy * rows - row
    gnoise = fractal(n, 2.0, 72, aniso=(1.0, 0.12))
    grain = np.sin((fv * 6 + gnoise * 10 + (plank_id % 7) * 0.7) * math.pi * 2) * 0.5 + 0.5
    tint = (np.sin(plank_id * 12.9898) * 43758.5453) % 1.0
    t = 0.45 * grain + 0.3 * tint + 0.25 * band(n, 30, 120, 73)
    base = ramp(t, [(0.0, (0.36, 0.22, 0.12)), (0.45, (0.55, 0.36, 0.20)), (0.8, (0.68, 0.48, 0.28)), (1.0, (0.78, 0.60, 0.38))])
    seam = (np.minimum(fv, 1 - fv) < 0.035) | (np.minimum(fu, 1 - fu) * lens[row] < 0.006)
    base[seam] *= 0.35
    edge = np.clip(np.minimum(fv, 1 - fv) / 0.08, 0, 1)
    base *= (0.8 + 0.2 * edge)[..., None]
    # nails
    nail = ((np.abs(fu * lens[row] - 0.02) < 0.006) | (np.abs((1 - fu) * lens[row] - 0.02) < 0.006)) & (np.abs(fv - 0.25) < 0.04) | \
           ((np.abs(fu * lens[row] - 0.02) < 0.006) | (np.abs((1 - fu) * lens[row] - 0.02) < 0.006)) & (np.abs(fv - 0.75) < 0.04)
    base[nail] = [0.25, 0.25, 0.27]
    height = edge * 0.7 + grain * 0.1
    height[seam] = 0
    save_rgb("planks_albedo.png", base)
    save_rgb("planks_normal.png", normal_from_height(height, 6.0))


def bark(n=512):
    ridges = fractal(n, 2.2, 81, aniso=(0.08, 1.0))
    fine = fractal(n, 1.6, 82, aniso=(0.3, 1.0))
    t = 0.7 * ridges + 0.3 * fine
    base = ramp(t, [(0.0, (0.18, 0.11, 0.07)), (0.35, (0.31, 0.20, 0.12)), (0.7, (0.45, 0.32, 0.21)), (1.0, (0.58, 0.47, 0.36))])
    lichen = np.clip((fractal(n, 2.6, 83) - 0.66) * 6, 0, 1)
    base = base * (1 - lichen[..., None] * 0.6) + np.array([0.46, 0.56, 0.30]) * lichen[..., None] * 0.6
    save_rgb("bark_albedo.png", base)
    save_rgb("bark_normal.png", normal_from_height(t, 8.0))


def stone_blocks(n=1024):
    rows = 6
    yy, xx = np.mgrid[0:n, 0:n] / n
    row = np.floor(yy * rows).astype(int)
    cols_per_row = 3
    u = xx * cols_per_row + (row % 2) * 0.5
    bid = np.floor(u).astype(int) + row * 13
    fu = u - np.floor(u)
    fv = yy * rows - row
    rng = np.random.default_rng(91)
    noise = band(n, 25, 140, 92)
    macro = fractal(n, 2.4, 93)
    chip = np.clip((fractal(n, 1.8, 94) - 0.72) * 4, 0, 1)
    d_edge = np.minimum(np.minimum(fu, 1 - fu) / cols_per_row * rows * 1.0, np.minimum(fv, 1 - fv))
    bevel = np.clip(d_edge / 0.1 + (noise - 0.5) * 0.3, 0, 1)
    tint = (np.sin(bid * 78.233) * 43758.5453) % 1.0
    t = 0.45 * tint + 0.35 * noise + 0.2 * macro
    base = ramp(t, [(0.0, (0.47, 0.42, 0.36)), (0.5, (0.64, 0.58, 0.48)), (1.0, (0.78, 0.72, 0.60))])
    base *= (0.7 + 0.3 * bevel)[..., None]
    base *= (1 - chip * 0.25)[..., None]
    mortar = d_edge < 0.025
    base[mortar] = [0.24, 0.22, 0.18]
    height = bevel * 0.8 + noise * 0.15 - chip * 0.2
    height[mortar] = 0
    save_rgb("stone_blocks_albedo.png", base)
    save_rgb("stone_blocks_normal.png", normal_from_height(height, 7.0))


def moss(n=512):
    t = 0.6 * fractal(n, 2.0, 101) + 0.4 * band(n, 40, 160, 102)
    base = ramp(t, [(0.0, (0.14, 0.28, 0.07)), (0.5, (0.27, 0.46, 0.12)), (1.0, (0.48, 0.64, 0.20))])
    save_rgb("moss_albedo.png", base)


def leaf_atlas(n=1024):
    """2x2 atlas of leaf clusters with alpha, for foliage cards."""
    img = Image.new("RGBA", (n, n), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    rng = np.random.default_rng(111)
    half = n // 2
    palettes = [
        [(52, 120, 40), (78, 150, 52), (110, 178, 64), (36, 92, 30)],
        [(70, 135, 38), (100, 165, 48), (140, 190, 66), (46, 100, 28)],
        [(40, 110, 58), (62, 140, 70), (98, 170, 86), (28, 80, 44)],
        [(140, 150, 40), (180, 170, 50), (200, 120, 40), (110, 110, 30)],
    ]
    for q in range(4):
        ox = (q % 2) * half
        oy = (q // 2) * half
        pal = palettes[q]
        cx, cy = ox + half / 2, oy + half / 2
        for k in range(110):
            ang = rng.uniform(0, math.pi * 2)
            rad = abs(rng.normal(0, half * 0.2))
            x = cx + math.cos(ang) * rad
            y = cy + math.sin(ang) * rad * 0.9
            L = rng.uniform(half * 0.08, half * 0.14)
            W = L * rng.uniform(0.38, 0.5)
            rot = ang + rng.normal(0, 0.6)
            col = pal[rng.integers(0, 4)]
            pts = []
            for s in np.linspace(0, 1, 12):
                pts.append((s, W * math.sin(math.pi * s) ** 0.8))
            poly = [(x + math.cos(rot) * L * s - math.sin(rot) * w, y + math.sin(rot) * L * s + math.cos(rot) * w) for s, w in pts]
            poly += [(x + math.cos(rot) * L * s + math.sin(rot) * w, y + math.sin(rot) * L * s - math.cos(rot) * w) for s, w in reversed(pts)]
            shade = 0.75 + 0.45 * (1 - rad / (half * 0.45))
            c = tuple(int(min(255, ch * shade)) for ch in col) + (255,)
            d.polygon(poly, fill=c)
            d.line([(x, y), (x + math.cos(rot) * L * 0.95, y + math.sin(rot) * L * 0.95)], fill=tuple(int(ch * 0.6) for ch in col) + (255,), width=2)
            # highlight
            d.line([(x + math.cos(rot) * L * 0.2 - math.sin(rot) * W * 0.3, y + math.sin(rot) * L * 0.2 + math.cos(rot) * W * 0.3),
                    (x + math.cos(rot) * L * 0.7 - math.sin(rot) * W * 0.35, y + math.sin(rot) * L * 0.7 + math.cos(rot) * W * 0.35)],
                   fill=(min(255, c[0] + 50), min(255, c[1] + 50), min(255, c[2] + 30), 160), width=2)
    arr = np.asarray(img).astype(np.float32) / 255.0
    # dilate colour under transparent pixels to avoid dark fringes with mipmaps
    rgb = arr[..., :3].copy()
    a = arr[..., 3]
    for _ in range(12):
        m = a > 0.01
        acc = np.zeros_like(rgb)
        cnt = np.zeros(a.shape)
        for dy, dx in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            acc += np.roll(np.roll(rgb * m[..., None], dy, 0), dx, 1)
            cnt += np.roll(np.roll(m, dy, 0), dx, 1)
        fill = (~m) & (cnt > 0)
        rgb[fill] = acc[fill] / cnt[fill][..., None]
        a = np.where(fill, 0.02, a)
    arr[..., :3] = rgb
    save_rgba("leaf_atlas.png", arr)


def noise_rgba(n=512):
    r = fractal(n, 2.6, 121)
    g = band(n, 6, 24, 122)
    f1, f2, _ = worley(n, 8, 123, 1.0)
    b = np.clip(f1 / 0.8, 0, 1)
    a = band(n, 32, 128, 124)
    save_rgba("noise_rgba.png", np.stack([r, g, b, a], -1))


def water(n=512):
    h = 0.5 * band(n, 4, 12, 131) + 0.35 * band(n, 10, 30, 132) + 0.15 * band(n, 30, 80, 133)
    save_rgb("water_normal.png", normal_from_height(h, 5.0))
    f1, f2, _ = worley(n, 14, 134, 1.0)
    foam = np.clip(1 - (f2 - f1) / 0.18, 0, 1) ** 1.5
    foam = np.clip(foam * 0.8 + band(n, 20, 80, 135) * 0.4 - 0.2, 0, 1)
    save_gray("foam.png", foam)


def clouds(n=1024):
    c = fractal(n, 2.8, 141, aniso=(1.0, 1.6))
    d = band(n, 8, 40, 142)
    v = np.clip((c * 0.8 + d * 0.3 - 0.45) * 2.2, 0, 1)
    save_gray("clouds.png", v)


def kart_paint(n=256):
    """Metallic-flake paint mask + carbon weave for kart parts (grey, tinted by shader)."""
    flakes = band(n, 60, 128, 151)
    yy, xx = np.mgrid[0:n, 0:n] / n
    weave = (np.sin(xx * math.pi * 2 * 16) * np.sin(yy * math.pi * 2 * 16)) * 0.5 + 0.5
    save_rgb("kart_detail.png", np.stack([flakes, weave, fractal(n, 2.0, 152)], -1))


import sys
if __name__ == "__main__" and len(sys.argv) > 1:
    for name in sys.argv[1:]:
        globals()[name]()
    sys.exit(0)

if __name__ == "__main__":
    grass()
    dirt()
    cobble()
    rock()
    sand()
    mud()
    planks()
    bark()
    stone_blocks()
    moss()
    leaf_atlas()
    noise_rgba()
    water()
    clouds()
    kart_paint()
