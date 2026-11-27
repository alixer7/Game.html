"""World generator: terrain heightmap that conforms to the road (flush shoulders, cliffs, drop-offs, ravines under
gaps, hills over tunnels), surface ids + splat weights, rivers / lakes / lava, instanced scatter with honest
colliders, voxel massifs (stepped pyramid with carved corridors), gates and a horizon ring.
Outputs (next to the track JSON):  <id>_h.bin (float32 heights), <id>_s.bin (u8 surface id), <id>_w.bin (RGBA u8 splat)
"""
import math
import os
import numpy as np
from scipy.spatial import cKDTree

SURF_IDS = ["grass", "rock", "sand", "dirt", "snow", "gravel", "mud", "ash", "regolith", "shallow_water", "ice",
            "packed_snow", "stone", "basalt", "metal"]
SURF_CHANNEL = {"grass": 0, "snow": 0, "ash": 0, "regolith": 0, "rock": 1, "basalt": 1, "ice": 1, "sand": 2,
                "gravel": 2, "shallow_water": 2, "dirt": 3, "mud": 3, "packed_snow": 3, "stone": 3, "metal": 3}


def value_noise2(xs, zs, scale, seed):
    """Smooth value noise sampled at world coords (arrays), lattice spacing `scale` metres."""
    rng = np.random.default_rng(seed)
    G = 64
    grid = rng.random((G, G))
    fx = xs / scale
    fz = zs / scale
    ix = np.floor(fx).astype(int)
    iz = np.floor(fz).astype(int)
    ux = fx - ix
    uz = fz - iz
    ux = ux * ux * (3 - 2 * ux)
    uz = uz * uz * (3 - 2 * uz)
    a = grid[iz % G, ix % G]
    b = grid[iz % G, (ix + 1) % G]
    c = grid[(iz + 1) % G, ix % G]
    d = grid[(iz + 1) % G, (ix + 1) % G]
    return (a * (1 - ux) + b * ux) * (1 - uz) + (c * (1 - ux) + d * ux) * uz


def fbm2(xs, zs, scale, octaves, seed):
    out = np.zeros_like(xs, dtype=float)
    amp, tot = 1.0, 0.0
    for o in range(octaves):
        out += (value_noise2(xs, zs, scale / (2 ** o), seed + o * 17) - 0.5) * 2 * amp
        tot += amp
        amp *= 0.5
    return out / tot


def smoothstep(e0, e1, x):
    t = np.clip((x - e0) / (e1 - e0), 0.0, 1.0)
    return t * t * (3 - 2 * t)


def seg_dist(px, pz, poly):
    """Distance from points to a polyline + index of nearest segment param."""
    best = np.full(px.shape, 1e9)
    for (x0, z0), (x1, z1) in zip(poly[:-1], poly[1:]):
        dx, dz = x1 - x0, z1 - z0
        L2 = dx * dx + dz * dz
        t = np.clip(((px - x0) * dx + (pz - z0) * dz) / max(L2, 1e-9), 0, 1)
        d = np.hypot(px - (x0 + t * dx), pz - (z0 + t * dz))
        best = np.minimum(best, d)
    return best


def build_world(T, out_dir):
    W = getattr(T, "world", None)
    if not W:
        return {"env": T.env}, None, None
    S = T.S
    n = len(S["d"])
    pos = S["pos"]
    cell = float(W.get("cell", 4.0))
    margin = float(W.get("margin", 240.0))
    xmin, xmax = pos[:, 0].min() - margin, pos[:, 0].max() + margin
    zmin, zmax = pos[:, 2].min() - margin, pos[:, 2].max() + margin
    nx = int(math.ceil((xmax - xmin) / cell)) + 1
    nz = int(math.ceil((zmax - zmin) / cell)) + 1
    ox, oz = float(xmin), float(zmin)
    gx = ox + np.arange(nx) * cell
    gz = oz + np.arange(nz) * cell
    X, Z = np.meshgrid(gx, gz)          # shape (nz, nx)
    seed = abs(hash(T.tid)) % 10000

    # ------------------------------------------------------------------ natural terrain
    base_y = float(W.get("base_y", 0.0))
    nat = base_y + fbm2(X, Z, W.get("hills_scale", 160.0), 4, seed) * W.get("hills_amp", 8.0)
    nat += np.abs(fbm2(X, Z, 60.0, 3, seed + 5)) * W.get("rough_amp", 2.0)
    bw = W.get("border_width", 150.0)
    edge_d = np.minimum.reduce([X - xmin, xmax - X, Z - zmin, zmax - Z])
    nat += smoothstep(bw, 0.0, edge_d) * W.get("border_rise", 60.0) * (0.75 + 0.5 * value_noise2(X, Z, 90.0, seed + 9))
    for r in W.get("raises", []):
        d = np.hypot(X - r["x"], Z - r["z"])
        nat += smoothstep(r["r"], r["r"] * 0.25, d) * r["h"] * (0.8 + 0.4 * value_noise2(X, Z, 40.0, seed + 11))
    for c in W.get("carves", []):
        if c["type"] == "river":
            d = seg_dist(X, Z, c["poly"])
            depth_t = c["level"] - c["depth"]
            bank = c.get("bank", 20.0)
            target = depth_t + smoothstep(c["width"] * 0.5, c["width"] * 0.5 + bank, d) * 0  # bed
            k = smoothstep(c["width"] * 0.5 + bank, c["width"] * 0.5, d)
            nat = nat * (1 - k) + np.minimum(nat, depth_t + (d / (c["width"] * 0.5 + bank)) ** 2 * (c["depth"] + 2)) * k
        elif c["type"] == "basin":
            d = np.hypot(X - c["x"], Z - c["z"])
            k = smoothstep(c["r"] + c.get("bank", 25.0), c["r"], d)
            bed = c["level"] - c["depth"] + (d / c["r"]) ** 2 * c["depth"] * 0.6
            nat = nat * (1 - k) + np.minimum(nat, bed) * k
        elif c["type"] == "island":
            # floating asteroid island: everything outside the radius is the void of space (holes below -400)
            d = np.hypot(X - c["x"], Z - c["z"]) * (1.0 + 0.18 * (value_noise2(X, Z, 70.0, seed + 41) - 0.5))
            rim = smoothstep(c["r"] - 30.0, c["r"], d)
            nat = nat - rim * 25.0
            nat = np.where(d > c["r"], -600.0, nat)
        elif c["type"] == "plateau":
            d = np.hypot(X - c["x"], Z - c["z"])
            k = smoothstep(c["r"] + c.get("bank", 25.0), c["r"], d)
            nat = nat * (1 - k) + c["y"] * k

    # ------------------------------------------------------------------ road conformance
    flat_r = S["right"][:, [0, 2]].copy()
    flat_r /= np.maximum(1e-6, np.linalg.norm(flat_r, axis=1, keepdims=True))
    flat_f = S["fwd"][:, [0, 2]].copy()
    flat_f /= np.maximum(1e-6, np.linalg.norm(flat_f, axis=1, keepdims=True))
    hw = S["w"] * 0.5
    A = S["attrs"]
    ground = np.array([a["ground"] for a in A])
    gap = np.array([a["gap"] for a in A])
    shl = np.array([a["sh_l"] for a in A])
    shr = np.array([a["sh_r"] for a in A])
    ceil = np.array([a["ceil"] for a in A])
    el = np.array([a["edge_l"] for a in A])
    er = np.array([a["edge_r"] for a in A])
    xz = pos[:, [0, 2]]
    tree = cKDTree(xz)
    P = np.stack([X.ravel(), Z.ravel()], 1)
    K = 14
    dist, idx = tree.query(P, k=K, distance_upper_bound=140.0)
    H = nat.ravel().copy()
    nat_flat = nat.ravel()
    clamp = np.full(H.shape, 1e9)
    shaped = np.zeros(H.shape, dtype=bool)
    surf = np.full(H.shape, SURF_IDS.index(W.get("default_surf", "grass")), dtype=np.uint8)
    blend_w = float(W.get("road_blend", 28.0))
    valid_any = np.isfinite(dist)
    idx_c = np.where(valid_any, idx, 0)
    rel = P[:, None, :] - xz[idx_c]                               # (N,K,2)
    lat = (rel * flat_r[idx_c]).sum(-1)
    along = (rel * flat_f[idx_c]).sum(-1)
    perp = valid_any & (np.abs(along) <= T.step * 0.8)
    alat = np.abs(lat)
    side_l = lat < 0
    sh = np.where(side_l, shl[idx_c], shr[idx_c])
    edge = np.where(side_l, el[idx_c], er[idx_c])
    foot = hw[idx_c] + sh
    excess = alat - foot
    yc = pos[idx_c, 1]
    # road surface height at that lateral (bank via right.y)
    ry = S["right"][idx_c, 1]
    y_at = yc + ry * lat
    gnd = ground[idx_c]
    is_gap = gap[idx_c]
    # ---- clamps from every nearby cross-section (terrain must stay under any road / deck / gap)
    clr = np.where(gnd == "elevated", 5.5, np.where(gnd == "void", 8.0, 0.55))
    clr = np.where(is_gap, 12.0, clr)
    margin_lat = np.where(gnd == "elevated", 4.0, np.where(is_gap, 7.0, 0.4))
    margin_lat = np.where(ceil[idx_c] > 0, 2.5, margin_lat)
    inside = perp & (excess <= margin_lat)
    roof_top = y_at + ceil[idx_c] + 1.6
    # NOTE: a heightmap cannot represent a tunnel through a hill (the slope between an "above the roof" cell and a
    # trimmed cell would cut through the corridor), so indoor corridors always sit in a trimmed trench; their rock
    # roof caps the trench.
    underground = np.zeros_like(inside)
    cval = np.where(inside & ~underground, y_at - clr, 1e9)
    clamp = np.minimum(clamp, cval.min(1))
    keep_ground = (inside & underground).any(1)
    # ---- shaping by the nearest grounded/indoor cross-section
    shape_ok = perp & np.isin(gnd, ["terrain", "indoor"]) & (~is_gap)
    score = np.where(shape_ok, alat, 1e9)
    best = np.argmin(score, 1)
    rows = np.arange(len(P))
    has = score[rows, best] < 1e8
    b_exc = excess[rows, best]
    b_edge = edge[rows, best]
    b_yat = y_at[rows, best]
    b_sh = sh[rows, best]
    b_i = idx_c[rows, best]
    b_ceil = ceil[b_i]
    b_foot = foot[rows, best]
    y_edge = b_yat - 0.12 * (b_sh > 0.1)
    near = has & (b_exc <= blend_w)
    t = smoothstep(0.0, blend_w, np.maximum(0.0, b_exc))
    flush = y_edge - 0.5
    newH = H.copy()
    under = has & (b_exc <= 0) & ~keep_ground
    newH[under] = (b_yat[under] - 0.45)
    # flush shoulders / walls / fences -> blend to nature
    m = near & ~under & np.isin(b_edge, ["shoulder", "wall", "fence", "rail", "none"]) & (b_ceil <= 0)
    newH[m] = flush[m] * (1 - t[m]) + H[m] * t[m]
    # cliff edges rise
    m = near & ~under & (b_edge == "cliff")
    newH[m] = np.maximum(H[m], y_edge[m] + 7.0 + smoothstep(0, 10, b_exc[m]) * 10.0)
    # half-pipes: terrain wraps behind the pipe
    m = near & ~under & (b_edge == "halfpipe")
    newH[m] = np.maximum(H[m] * t[m] + (y_edge[m] + 9.0) * (1 - t[m]), y_edge[m] + 7.0 * (1 - t[m]))
    # open edges on grounded roads: honest drop-off
    m = near & ~under & (b_edge == "open") & (b_ceil <= 0)
    drop = y_edge - 2.5 - np.maximum(0.0, b_exc) * 0.9
    newH[m] = np.minimum(H[m], drop[m] * (1 - t[m]) + H[m] * t[m])
    # indoor: hill / mass over the hall (outside the walls)
    m = near & ~under & (b_ceil > 0) & ~keep_ground
    hill = b_yat + b_ceil + 2.0 + smoothstep(0, 6, b_exc) * 3.0
    k_in = smoothstep(blend_w * 1.2, 2.0, b_exc)
    newH[m] = np.maximum(H[m], hill[m] * k_in[m] + H[m] * (1 - k_in[m]))
    H = newH
    # shoulder / road-side surfaces
    shs = np.array([[a["shs_l"], a["shs_r"]] for a in A])
    road_surf = np.array([a["surf"] for a in A])
    for name in set(list(shs.ravel()) + list(road_surf)):
        if name not in SURF_IDS:
            continue
        sid = SURF_IDS.index(name)
        side_shs = np.where(lat[rows, best] < 0, shs[b_i, 0], shs[b_i, 1])
        mm = has & (b_exc <= 6.0) & (b_sh > 0.1) & (side_shs == name)
        surf[mm] = sid
    # ------------------------------------------------------------------ shortcut flight corridors
    for sc in T.shortcuts_world:
        poly = [(sc["lx"], sc["lz"])] + [(p["x"], p["z"]) for p in sc["plats"]] + [(sc["tx"], sc["tz"])]
        d = seg_dist(P[:, 0], P[:, 1], poly)
        lo = min(sc["ly"], sc["ty"]) - sc.get("corridor_drop", 7.0)
        clamp = np.where(d < 11.0, np.minimum(clamp, lo), clamp)
    H = np.minimum(H, clamp)
    # ------------------------------------------------------------------ water bodies
    waters = []
    for wd in W.get("waters", []):
        if "poly" in wd:
            pts = wd["poly"]
            for (x0, z0), (x1, z1) in zip(pts[:-1], pts[1:]):
                L = math.hypot(x1 - x0, z1 - z0)
                rot = math.atan2(-(x1 - x0), -(z1 - z0))
                waters.append(dict(kind=wd.get("kind", "water"), x=(x0 + x1) / 2, z=(z0 + z1) / 2,
                                   sx=wd["width"], sz=L + wd["width"] * 0.6, rot=rot, y=wd["level"],
                                   deep=wd.get("deep", 1.6)))
        else:
            waters.append(dict(kind=wd.get("kind", "water"), x=wd["x"], z=wd["z"], sx=wd["sx"], sz=wd["sz"],
                               rot=wd.get("rot", 0.0), y=wd["level"], deep=wd.get("deep", 1.6)))
    Hg = H.reshape(nz, nx)
    # ------------------------------------------------------------------ surfaces & splat
    slope = np.hypot(np.gradient(Hg, cell, axis=1), np.gradient(Hg, cell, axis=0)).ravel()
    rock_id = SURF_IDS.index(W.get("rock_surf", "rock"))
    surf = np.where((slope > 0.85) & (surf != SURF_IDS.index("sand")), rock_id, surf).astype(np.uint8)
    for w in waters:
        lvl = w["y"]
        shore = (H < lvl + 0.9) & (H > lvl - 6.0)
        c, s_ = math.cos(-w["rot"]), math.sin(-w["rot"])
        rx = (P[:, 0] - w["x"]) * c - (P[:, 1] - w["z"]) * s_
        rz = (P[:, 0] - w["x"]) * s_ + (P[:, 1] - w["z"]) * c
        inside_w = (np.abs(rx) <= w["sx"] / 2 + 8) & (np.abs(rz) <= w["sz"] / 2 + 8)
        bank_id = SURF_IDS.index(W.get("shore_surf", "sand"))
        surf = np.where(shore & inside_w & (slope < 0.85), bank_id, surf).astype(np.uint8)
    for rule in W.get("surf_patches", []):
        d = np.hypot(P[:, 0] - rule["x"], P[:, 1] - rule["z"])
        noise = value_noise2(P[:, 0], P[:, 1], 18.0, seed + 23)
        surf = np.where((d < rule["r"] * (0.7 + 0.5 * noise)) & (slope < 0.8), SURF_IDS.index(rule["surf"]), surf).astype(np.uint8)
    chan = np.array([SURF_CHANNEL.get(sname, 0) for sname in SURF_IDS])[surf]
    wts = np.zeros((len(P), 4))
    wts[np.arange(len(P)), chan] = 1.0
    wts = wts.reshape(nz, nx, 4)
    # soften transitions (3x3 box blur twice) + noise breakup
    for _ in range(2):
        pad = np.pad(wts, ((1, 1), (1, 1), (0, 0)), mode="edge")
        wts = sum(pad[dy:dy + nz, dx:dx + nx] for dy in range(3) for dx in range(3)) / 9.0
    nz_noise = value_noise2(X, Z, 14.0, seed + 31)
    wts[..., 3] += np.clip(nz_noise - 0.72, 0, 1) * 0.6 * (wts[..., 0] > 0.5)
    wts /= np.maximum(1e-6, wts.sum(-1, keepdims=True))
    splat = (wts * 255).astype(np.uint8)

    # ------------------------------------------------------------------ write terrain
    base = T.tid
    Hg.astype("<f4").tofile(os.path.join(out_dir, base + "_h.bin"))
    surf.astype(np.uint8).tofile(os.path.join(out_dir, base + "_s.bin"))
    splat.reshape(-1).tofile(os.path.join(out_dir, base + "_w.bin"))
    terrain_meta = dict(height_file=base + "_h.bin", surf_file=base + "_s.bin", splat_file=base + "_w.bin",
                        nx=nx, nz=nz, cell=cell, ox=ox, oz=oz, surf_names=SURF_IDS,
                        textures=W.get("textures"), tints=W.get("tints", []))

    def h_at(x, z):
        fx = (x - ox) / cell
        fz = (z - oz) / cell
        ix = int(np.clip(math.floor(fx), 0, nx - 2))
        iz = int(np.clip(math.floor(fz), 0, nz - 2))
        ux, uz = fx - ix, fz - iz
        h00, h10 = Hg[iz, ix], Hg[iz, ix + 1]
        h01, h11 = Hg[iz + 1, ix], Hg[iz + 1, ix + 1]
        return float((h00 * (1 - ux) + h10 * ux) * (1 - uz) + (h01 * (1 - ux) + h11 * ux) * uz)

    def in_water(x, z):
        for w in waters:
            c, s_ = math.cos(-w["rot"]), math.sin(-w["rot"])
            rx = (x - w["x"]) * c - (z - w["z"]) * s_
            rz = (x - w["x"]) * s_ + (z - w["z"]) * c
            if abs(rx) <= w["sx"] / 2 and abs(rz) <= w["sz"] / 2 and h_at(x, z) < w["y"] + 0.2:
                return True
        return False

    # ------------------------------------------------------------------ landmarks (voxel massifs, gates ...)
    landmarks = []
    reserved = []   # (x, z, r) areas where scatter must not go
    for pyr in W.get("massifs", []):
        lm, res = _massif(T, pyr, h_at)
        landmarks.append(lm)
        reserved += res
    for g in W.get("gates", []):
        p, f, r, u, i = T.frame_at(g["d"], 0.0)
        yaw = math.atan2(-f[0], -f[2])
        sc_ = (T.S["w"][i] * 0.5 + 3.0) / 17.8
        landmarks.append(dict(kind="glb", glb=g["glb"], x=float(p[0]), y=float(p[1]), z=float(p[2]), rot=yaw,
                              scale=float(sc_), sy=float(max(1.0, sc_)), col_r=0.0))
        for sd in (-1, 1):
            q = p + r * sd * 17.8 * sc_
            landmarks.append(dict(kind="pillar_col", x=float(q[0]), y=float(q[1]), z=float(q[2]), r=2.2))
    for lmk in W.get("landmarks", []):
        landmarks.append(dict(lmk))
        reserved.append((lmk["x"], lmk["z"], lmk.get("reserve", 10.0)))

    # ------------------------------------------------------------------ scatter
    scatter = {}
    rng = np.random.default_rng(seed + 77)
    sc_lines = []
    for sc in T.shortcuts_world:
        sc_lines.append([(sc["lx"], sc["lz"])] + [(p["x"], p["z"]) for p in sc["plats"]] + [(sc["tx"], sc["tz"])])
    elevated_mask = np.isin(ground, ["elevated", "void"])
    for rule in W.get("scatter", []):
        spacing = rule["spacing"]
        jx = np.arange(xmin, xmax, spacing)
        jz = np.arange(zmin, zmax, spacing)
        CX, CZ = np.meshgrid(jx, jz)
        CX = CX.ravel() + (rng.random(CX.size) - 0.5) * spacing * 0.9
        CZ = CZ.ravel() + (rng.random(CZ.size) - 0.5) * spacing * 0.9
        keep = rng.random(CX.size) < rule.get("prob", 1.0)
        CX, CZ = CX[keep], CZ[keep]
        dd, ii = tree.query(np.stack([CX, CZ], 1), k=6)
        out = []
        for j in range(len(CX)):
            x, z = float(CX[j]), float(CZ[j])
            ok = True
            dmin_edge = 1e9
            biome = None
            for kk in range(6):
                si = ii[j, kk]
                relx, relz = x - xz[si, 0], z - xz[si, 1]
                la = relx * flat_r[si, 0] + relz * flat_r[si, 1]
                ext = hw[si] + max(shl[si], shr[si]) + (3.5 if ground[si] in ("terrain", "indoor") else 2.0)
                e = abs(la) - ext
                hy = h_at(x, z)
                if ground[si] in ("elevated", "void") and pos[si, 1] - hy > rule.get("max_h", 12.0) + 2.0:
                    # prop fits under the deck height-wise: only keep it out of the deck's shadow footprint
                    e2 = abs(la) - hw[si] - 3.0 - rule.get("crown", 0.0)
                    if e2 < 0:
                        ok = False
                    dmin_edge = min(dmin_edge, e)
                    if biome is None:
                        biome = A[si]["biome"]
                    continue
                if ceil[si] > 0 and abs(la) < hw[si] + 3.0:
                    ok = False
                dmin_edge = min(dmin_edge, e)
                if biome is None:
                    biome = A[si]["biome"]
            if not ok or dmin_edge < rule.get("dmin", 2.0) or dmin_edge > rule.get("dmax", 1e9):
                continue
            if rule.get("biomes") and biome not in rule["biomes"]:
                continue
            y = h_at(x, z)
            if in_water(x, z) != rule.get("in_water", False):
                continue
            if "ymin" in rule and y < rule["ymin"]:
                continue
            if "ymax" in rule and y > rule["ymax"]:
                continue
            fx_ = (x - ox) / cell
            fz_ = (z - oz) / cell
            gi = int(np.clip(round(fz_), 0, nz - 1)) * nx + int(np.clip(round(fx_), 0, nx - 1))
            if slope[gi] > rule.get("max_slope", 0.7):
                continue
            if any(seg_dist(np.array([x]), np.array([z]), ln)[0] < rule.get("sc_clear", 12.0) for ln in sc_lines):
                continue
            if any(math.hypot(x - rx_, z - rz_) < rr for rx_, rz_, rr in reserved):
                continue
            s = float(rng.uniform(*rule.get("scale", (1.0, 1.0))))
            sy = s * float(rng.uniform(*rule.get("yscale", (1.0, 1.0))))
            rot = float(rng.uniform(0, 2 * math.pi))
            if rule.get("face_road"):
                si = ii[j, 0]
                rot = math.atan2(flat_r[si, 0] * (1 if (x - xz[si, 0]) * flat_r[si, 0] + (z - xz[si, 1]) * flat_r[si, 1] < 0 else -1),
                                 flat_r[si, 1] * (1 if (x - xz[si, 0]) * flat_r[si, 0] + (z - xz[si, 1]) * flat_r[si, 1] < 0 else -1))
                rot = math.atan2(-((xz[si, 0] - x)), -((xz[si, 1] - z)))
            col = 1 if dmin_edge < rule.get("col_within", 30.0) else 0
            out.append([round(x, 2), round(y + rule.get("dy", 0.0), 2), round(z, 2), round(rot, 3), round(s, 3), round(sy, 3), col])
        if out:
            scatter.setdefault(rule["kind"], []).extend(out)
    for kind, lst in W.get("placed", {}).items():
        for it in lst:
            x, z = it[0], it[1]
            y = h_at(x, z) if len(it) < 6 or it[5] is None else it[5]
            scatter.setdefault(kind, []).append([x, round(y, 2), z, it[2], it[3], it[4], 1])

    # ------------------------------------------------------------------ horizon
    hz = W.get("horizon")
    horizon = {}
    if hz:
        items = []
        cxm, czm = (xmin + xmax) / 2, (zmin + zmax) / 2
        R = max(xmax - xmin, zmax - zmin) * 0.5 + hz.get("extra", 120.0)
        for k in range(hz.get("count", 26)):
            ang = k / hz.get("count", 26) * 2 * math.pi + rng.uniform(-0.08, 0.08)
            rr = R * rng.uniform(0.95, 1.15)
            w_ = rng.uniform(*hz.get("w", (90, 150)))
            h_ = rng.uniform(*hz.get("h", (90, 180)))
            items.append([round(cxm + math.cos(ang) * rr, 1), base_y - 6.0, round(czm + math.sin(ang) * rr, 1),
                          round(rng.uniform(0, 6.28), 2), round(w_, 1), round(h_, 1), round(rng.uniform(0.8, 1.2), 2)])
        horizon = dict(glb=hz["glb"], items=items)

    extra = dict(env=T.env, terrain=terrain_meta, waters=waters, scatter=scatter, landmarks_world=landmarks,
                 horizon=horizon)
    return extra, (Hg, ox, oz, cell), {k: [[v[0], v[1], v[2]] for v in vals] for k, vals in scatter.items()}


def _massif(T, cfg, h_at):
    """Stepped voxel massif (pyramid) wrapped around the road samples of the given biomes; corridors carved."""
    S = T.S
    A = S["attrs"]
    pos = S["pos"]
    sel = np.array([a["biome"] in cfg["biomes"] for a in A])
    pts = pos[sel]
    cx = float((pts[:, 0].min() + pts[:, 0].max()) / 2) + cfg.get("dx", 0.0)
    cz = float((pts[:, 2].min() + pts[:, 2].max()) / 2) + cfg.get("dz", 0.0)
    hx = float((pts[:, 0].max() - pts[:, 0].min()) / 2 + cfg.get("margin", 14.0))
    hz = float((pts[:, 2].max() - pts[:, 2].min()) / 2 + cfg.get("margin", 14.0))
    hx = max(hx, cfg.get("min_half", 0.0))
    hz = max(hz, cfg.get("min_half", 0.0))
    cell = cfg.get("cell", 6.0)
    tier = cfg.get("tier", 4.6)
    base = h_at(cx, cz) - 2.0 if "base_y" not in cfg else cfg["base_y"]
    top = float((pts[:, 1] + np.array([a["ceil"] for a in A])[sel]).max()) + cfg.get("top_extra", 10.0)
    levels = max(1, int(math.ceil((top - base) / tier)))
    hw = S["w"] * 0.5
    flat_r = S["right"][:, [0, 2]]
    flat_r = flat_r / np.maximum(1e-6, np.linalg.norm(flat_r, axis=1, keepdims=True))
    tree = cKDTree(pos[:, [0, 2]])
    boxes = []
    reserved = [(cx, cz, max(hx, hz))]
    xs = np.arange(cx - hx + cell / 2, cx + hx, cell)
    zs = np.arange(cz - hz + cell / 2, cz + hz, cell)
    for x in xs:
        for z in zs:
            u = max(abs(x - cx) / hx, abs(z - cz) / hz)
            lvl = int(math.floor((1.0 - u) * levels * 1.0 + 0.999))
            if lvl <= 0:
                continue
            col_top = base + lvl * tier
            segs = [[base, col_top]]
            cand = tree.query_ball_point([x, z], r=cell * 0.75 + 16.0)
            for si in cand:
                rel = np.array([x - pos[si, 0], z - pos[si, 2]])
                la = abs(rel @ flat_r[si])
                if la > hw[si] + 2.2 + cell * 0.5:
                    continue
                fwd = S["fwd"][si, [0, 2]]
                fwd = fwd / max(1e-6, np.linalg.norm(fwd))
                if abs(rel @ fwd) > T.step * 1.5 + cell * 0.5:
                    continue
                ry = pos[si, 1]
                c = A[si]["ceil"]
                lo_top = ry - 0.8
                hi_bot = ry + c + 1.0 if c > 0 else 1e9
                new = []
                for a0, a1 in segs:
                    if a1 <= lo_top or a0 >= hi_bot:
                        new.append([a0, a1])
                        continue
                    if a0 < lo_top:
                        new.append([a0, lo_top])
                    if a1 > hi_bot:
                        new.append([hi_bot, a1])
                segs = new
            for a0, a1 in segs:
                if a1 - a0 > 0.3:
                    boxes.append([round(float(x), 2), round(float(z), 2), round(float(a0), 2), round(float(a1), 2), cell, cell])
    lm = dict(kind="blocks", tex=cfg.get("tex", "wall_tiki"), top_tex=cfg.get("top_tex", cfg.get("tex", "wall_tiki")),
              tint=cfg.get("tint", "#ffffff"), top_tint=cfg.get("top_tint", "#ffffff"), rep=cfg.get("rep", 6.0),
              boxes=boxes, shadow=True)
    return lm, reserved
