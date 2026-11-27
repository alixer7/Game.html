"""Tileable stylized-realistic PBR texture generator (albedo / normal / roughness, 512x512).
python3 tools/texgen.py   -> assets/textures/<name>_{albedo,normal,rough}.png
"""
import os
import numpy as np
from PIL import Image

N = 512
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "assets", "textures")
rng = np.random.default_rng(7)


def value_noise(cells, seed, n=N):
    r = np.random.default_rng(seed)
    g = r.random((cells, cells))
    x = np.linspace(0, cells, n, endpoint=False)
    xi = np.floor(x).astype(int)
    xf = x - xi
    xf = xf * xf * (3 - 2 * xf)
    x0, x1 = xi % cells, (xi + 1) % cells
    a = g[np.ix_(x0, x0)]
    b = g[np.ix_(x0, x1)]
    c = g[np.ix_(x1, x0)]
    d = g[np.ix_(x1, x1)]
    fy = xf[:, None]
    fx = xf[None, :]
    return (a * (1 - fx) + b * fx) * (1 - fy) + (c * (1 - fx) + d * fx) * fy


def fbm(base_cells, octaves, seed, gain=0.5):
    out = np.zeros((N, N))
    amp, tot = 1.0, 0.0
    for o in range(octaves):
        out += value_noise(base_cells * (2 ** o), seed + o * 31) * amp
        tot += amp
        amp *= gain
    return out / tot


def voronoi(cells, seed, jitter=0.85):
    """Periodic voronoi: returns F1 distance, F2-F1 edge distance, cell id."""
    r = np.random.default_rng(seed)
    pts = (np.stack(np.meshgrid(np.arange(cells), np.arange(cells), indexing="ij"), -1).reshape(-1, 2)
           + 0.5 + (r.random((cells * cells, 2)) - 0.5) * jitter) / cells
    ids = np.arange(len(pts))
    yy, xx = np.mgrid[0:N, 0:N] / N
    f1 = np.full((N, N), 9.0)
    f2 = np.full((N, N), 9.0)
    cid = np.zeros((N, N), dtype=int)
    for ox in (-1, 0, 1):
        for oy in (-1, 0, 1):
            for k, p in enumerate(pts):
                d = np.sqrt((yy - p[0] - oy) ** 2 + (xx - p[1] - ox) ** 2)
                m1 = d < f1
                f2 = np.where(m1, f1, np.minimum(f2, d))
                cid = np.where(m1, ids[k], cid)
                f1 = np.where(m1, d, f1)
    return f1 * cells, (f2 - f1) * cells, cid


def normal_from_height(h, strength):
    dx = (np.roll(h, -1, 1) - np.roll(h, 1, 1)) * 0.5 * strength
    dy = (np.roll(h, -1, 0) - np.roll(h, 1, 0)) * 0.5 * strength
    nz = np.ones_like(h)
    n = np.stack([-dx, -dy, nz], -1)
    n /= np.linalg.norm(n, axis=-1, keepdims=True)
    return ((n * 0.5 + 0.5) * 255).astype(np.uint8)


def save(name, alb, h, rough, nstrength=6.0):
    alb = np.clip(alb, 0, 1)
    Image.fromarray((alb * 255).astype(np.uint8)).save(os.path.join(OUT, f"{name}_albedo.png"))
    Image.fromarray(normal_from_height(h, nstrength * N / 256)).save(os.path.join(OUT, f"{name}_normal.png"))
    rough = np.broadcast_to(np.asarray(rough, dtype=float), (N, N))
    Image.fromarray((np.clip(rough, 0, 1) * 255).astype(np.uint8)).save(os.path.join(OUT, f"{name}_rough.png"))
    print("wrote", name)


def col(c):
    return np.array(c, dtype=float)[None, None, :]


def lerp(a, b, t):
    return a + (b - a) * t[..., None]


def tex_cobble():
    f1, edge, cid = voronoi(9, 11, 0.7)
    per = np.random.default_rng(3).random(cid.max() + 1)[cid]
    n = fbm(8, 4, 5)
    mortar = np.clip(edge / 0.09, 0, 1)
    stone_h = np.clip(1 - (f1 / 0.75) ** 2, 0, 1) * 0.6 + n * 0.4
    h = mortar * (0.6 + stone_h * 0.4)
    base = lerp(col((0.46, 0.42, 0.36)), col((0.68, 0.60, 0.48)), per * 0.7 + n * 0.3)
    moss = np.clip((fbm(4, 3, 9) - 0.55) * 4, 0, 1) * (1 - mortar)
    base = lerp(base, col((0.36, 0.44, 0.22)), moss * 0.6)
    alb = lerp(col((0.22, 0.20, 0.17)) * np.ones_like(base), base, mortar)
    save("road_cobble", alb, h, 0.75 + (1 - mortar) * 0.2)


def tex_dirt():
    n = fbm(6, 5, 21)
    ruts = 0.5 + 0.5 * np.sin(np.linspace(0, 2 * np.pi * 2, N))[None, :] * np.ones((N, 1))
    pebbles = np.clip((fbm(64, 2, 33) - 0.62) * 6, 0, 1)
    h = n * 0.7 + pebbles * 0.5 - ruts * 0.1
    alb = lerp(col((0.46, 0.33, 0.21)), col((0.66, 0.50, 0.33)), n)
    alb = lerp(alb, col((0.78, 0.72, 0.62)), pebbles * 0.6)
    alb = lerp(alb, col((0.36, 0.26, 0.17)), (ruts - 0.5).clip(0, 1) * 0.35)
    save("road_dirt", alb, h, 0.95 - pebbles * 0.1, 5)


def tex_wetstone():
    f1, edge, cid = voronoi(7, 41, 0.9)
    per = np.random.default_rng(4).random(cid.max() + 1)[cid]
    n = fbm(8, 4, 45)
    crack = np.clip(edge / 0.06, 0, 1)
    h = crack * (0.5 + n * 0.5)
    alb = lerp(col((0.22, 0.27, 0.28)), col((0.36, 0.42, 0.42)), per * 0.6 + n * 0.4)
    alb = lerp(col((0.12, 0.15, 0.16)) * np.ones_like(alb), alb, crack)
    puddle = np.clip((fbm(3, 3, 47) - 0.6) * 5, 0, 1)
    alb = lerp(alb, col((0.20, 0.30, 0.34)), puddle * 0.5)
    save("road_wetstone", alb, h * (1 - puddle * 0.8), 0.45 - puddle * 0.35 + (1 - crack) * 0.1)


def tex_metal():
    n = fbm(16, 4, 61)
    y, x = np.mgrid[0:N, 0:N]
    seams = ((x % 128) < 3) | ((y % 256) < 3)
    rivet = (((x % 128 - 10) ** 2 + (y % 64 - 32) ** 2) < 16) | (((x % 128 - 118) ** 2 + (y % 64 - 32) ** 2) < 16)
    tread = ((((x + y) // 12) % 2) == 0) * 0.15
    h = 0.5 + tread * 0.6 - seams * 0.5 + rivet * 0.4 + n * 0.1
    alb = lerp(col((0.40, 0.44, 0.47)), col((0.56, 0.60, 0.62)), n)
    alb = np.where(seams[..., None], col((0.2, 0.22, 0.24)), alb)
    alb = np.where(rivet[..., None], col((0.70, 0.72, 0.74)), alb)
    rust = np.clip((fbm(5, 4, 63) - 0.62) * 5, 0, 1)
    alb = lerp(alb, col((0.48, 0.30, 0.18)), rust * 0.5)
    save("road_metal", alb, h, 0.45 + rust * 0.4, 4)


def tex_grating():
    y, x = np.mgrid[0:N, 0:N]
    bars = ((x % 32) < 7) | ((y % 64) < 5)
    n = fbm(12, 3, 71)
    h = np.where(bars, 0.9, 0.1) + n * 0.05
    alb = np.where(bars[..., None], lerp(col((0.46, 0.52, 0.54)), col((0.62, 0.68, 0.70)), n), col((0.06, 0.08, 0.09)))
    stripe = (((x + y) // 40) % 2 == 0) & ((y % 512) < 30)
    save("road_grating", alb, h, np.where(bars, 0.4, 0.9), 5)


def tex_asphalt():
    n = fbm(32, 4, 81)
    grit = np.random.default_rng(5).random((N, N))
    h = n * 0.5 + grit * 0.3
    alb = lerp(col((0.13, 0.13, 0.16)), col((0.24, 0.24, 0.28)), n * 0.7 + grit * 0.3)
    patch = np.clip((fbm(3, 3, 83) - 0.6) * 6, 0, 1)
    alb = lerp(alb, col((0.09, 0.09, 0.11)), patch * 0.6)
    save("road_asphalt", alb, h, 0.72 + grit * 0.1, 3)


def tex_snowpack():
    n = fbm(8, 5, 91)
    tracks = (0.5 + 0.5 * np.cos(np.linspace(0, 2 * np.pi * 3, N)))[None, :] * np.ones((N, 1))
    h = n * 0.6 + tracks * 0.15
    alb = lerp(col((0.76, 0.82, 0.90)), col((0.96, 0.98, 1.0)), n)
    alb = lerp(alb, col((0.66, 0.74, 0.84)), tracks * 0.25)
    save("road_snowpack", alb, h, 0.7 + n * 0.1, 4)


def tex_grass():
    n = fbm(6, 5, 101)
    blades = fbm(128, 2, 103)
    h = n * 0.4 + blades * 0.6
    alb = lerp(col((0.23, 0.38, 0.12)), col((0.44, 0.58, 0.22)), n * 0.6 + blades * 0.4)
    dry = np.clip((fbm(3, 3, 105) - 0.58) * 4, 0, 1)
    alb = lerp(alb, col((0.62, 0.58, 0.30)), dry * 0.5)
    flowers = (np.random.default_rng(9).random((N, N)) > 0.9985)
    alb = np.where(flowers[..., None], col((0.95, 0.85, 0.30)), alb)
    save("terrain_grass", alb, h, 0.95, 4)


def tex_sand():
    n = fbm(6, 5, 111)
    y, x = np.mgrid[0:N, 0:N] / N
    ripples = 0.5 + 0.5 * np.sin((y * 14 + n * 1.6) * 2 * np.pi)
    h = ripples * 0.5 + n * 0.5
    alb = lerp(col((0.78, 0.66, 0.44)), col((0.94, 0.84, 0.62)), n * 0.6 + ripples * 0.4)
    shells = (np.random.default_rng(13).random((N, N)) > 0.999)
    alb = np.where(shells[..., None], col((0.98, 0.96, 0.92)), alb)
    save("terrain_sand", alb, h, 0.95, 3)


def tex_mud():
    n = fbm(5, 5, 121)
    puddle = np.clip((fbm(4, 3, 123) - 0.55) * 5, 0, 1)
    h = n * (1 - puddle)
    alb = lerp(col((0.24, 0.17, 0.10)), col((0.40, 0.29, 0.18)), n)
    alb = lerp(alb, col((0.20, 0.16, 0.12)), puddle * 0.7)
    save("terrain_mud", alb, h, 0.8 - puddle * 0.6, 5)


def tex_gravel():
    f1, edge, cid = voronoi(26, 131, 1.0)
    per = np.random.default_rng(6).random(cid.max() + 1)[cid]
    stone = np.clip(1 - f1 / 0.62, 0, 1)
    h = stone
    alb = lerp(col((0.30, 0.28, 0.26)), col((0.72, 0.68, 0.62)), per * stone)
    save("terrain_gravel", alb, h, 0.9, 6)


if __name__ == "__main__":
    os.makedirs(OUT, exist_ok=True)
    for f in (tex_cobble, tex_dirt, tex_wetstone, tex_metal, tex_grating, tex_asphalt, tex_snowpack,
              tex_grass, tex_sand, tex_mud, tex_gravel):
        f()
