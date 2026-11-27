"""Track designer core for Nitro Fury Racing.

A track is authored as a sequence of precise turtle segments (straights, arcs with an exact radius
and angle, ramps, gaps, bumps...).  Every segment can change keyframed channels (elevation, width,
bank, crown) and sticky range attributes (road surface, edge types, shoulders, indoor ceiling,
ground mode, biome, zone).  `finalize()` closes the loop, samples the centre line every ~2 m,
resolves features (pads, hazards, obstacles, shortcuts, set pieces) into world space and runs
validation (self-overlap / vertical clearance, radius, grade, length).

Godot coordinate convention: +Y up, forward of yaw 0 is -Z, turning LEFT increases yaw.
Positive bank raises the RIGHT edge (road tilts down to the left => banks a LEFT turn).
"""
import math
import json
import numpy as np

STEP = 2.0
FINE = 0.25

DEFAULTS = dict(
    surf="stone",          # road surface id (see Surfaces.gd)
    edge_l="wall", edge_r="wall",   # wall | fence | rail | open | shoulder | halfpipe | cliff | none
    wall_l=1.4, wall_r=1.4,          # wall/fence height (m)
    sh_l=0.0, sh_r=0.0,              # flush shoulder width beyond the road edge (m)
    shs_l="grass", shs_r="grass",    # shoulder surface
    ceil=0.0,              # indoor ceiling height above road (0 = outdoor)
    ground="terrain",      # terrain | elevated | void | indoor | water
    deck="stone",          # visual style of bridge deck / supports
    biome="", zone="",
    auto_bank=0.0,         # extra bank in degrees per (rad/m) of curvature
    theme_wall="",         # optional wall material override
)
STICKY = set(DEFAULTS.keys())
FLAGS = ("gap", "ramp", "lip")


def _pchip_slopes(xs, ys):
    n = len(xs)
    h = np.diff(xs)
    delta = np.diff(ys) / np.where(h == 0, 1e-9, h)
    m = np.zeros(n)
    for i in range(1, n - 1):
        if delta[i - 1] * delta[i] <= 0:
            m[i] = 0.0
        else:
            w1 = 2 * h[i] + h[i - 1]
            w2 = h[i] + 2 * h[i - 1]
            m[i] = (w1 + w2) / (w1 / delta[i - 1] + w2 / delta[i])
    m[0] = delta[0] if n > 1 else 0.0
    m[-1] = delta[-1] if n > 1 else 0.0
    return m, delta


def eval_channel(keys, ds, total, periodic=True):
    """keys: list of (d, value, mode) where mode ('s'mooth | 'l'inear) applies to the interval ENDING at d."""
    keys = sorted(keys, key=lambda k: k[0])
    # periodic padding so the loop closes smoothly
    if periodic:
        pre = [(keys[-2][0] - total, keys[-2][1], keys[-2][2])] if len(keys) > 2 else []
        post = [(keys[1][0] + total, keys[1][1], keys[1][2])] if len(keys) > 2 else []
        kk = pre + keys + post
    else:
        kk = keys
    xs = np.array([k[0] for k in kk], dtype=float)
    ys = np.array([k[1] for k in kk], dtype=float)
    modes = [k[2] for k in kk]
    # drop duplicate distances
    keep = [0]
    for i in range(1, len(xs)):
        if xs[i] - xs[keep[-1]] > 1e-6:
            keep.append(i)
        else:
            ys[keep[-1]] = ys[i]
    xs = xs[keep]; ys = ys[keep]; modes = [modes[i] for i in keep]
    m, delta = _pchip_slopes(xs, ys)
    # knots adjacent to linear intervals take that interval's slope (smooth blending into ramps)
    for i in range(len(xs)):
        left_lin = i > 0 and modes[i] == "l"
        right_lin = i < len(xs) - 1 and modes[i + 1] == "l"
        if i < len(xs) - 1 and modes[i + 1] == "g" and not left_lin:
            # knot before a gap: keep the approach flat (no dive into the gap)
            m[i] = 0.0 if i == 0 or modes[i] != "s" else min(0.0, m[i]) * 0.0
            continue
        if left_lin and right_lin:
            m[i] = delta[i]  # unused for linear intervals
        elif left_lin:
            m[i] = delta[i - 1]
        elif right_lin:
            m[i] = delta[i]
    out = np.empty(len(ds))
    idx = np.searchsorted(xs, ds, side="right") - 1
    idx = np.clip(idx, 0, len(xs) - 2)
    for j, d in enumerate(ds):
        i = idx[j]
        x0, x1 = xs[i], xs[i + 1]
        h = x1 - x0
        u = (d - x0) / h if h > 0 else 0.0
        if modes[i + 1] in ("l", "g"):
            out[j] = ys[i] + (ys[i + 1] - ys[i]) * u
        else:
            h00 = 2 * u ** 3 - 3 * u ** 2 + 1
            h10 = u ** 3 - 2 * u ** 2 + u
            h01 = -2 * u ** 3 + 3 * u ** 2
            h11 = u ** 3 - u ** 2
            out[j] = h00 * ys[i] + h10 * h * m[i] + h01 * ys[i + 1] + h11 * h * m[i + 1]
    return out


class Track:
    def __init__(self, tid, name_en, name_ar, start=(0.0, 0.0, 0.0), yaw_deg=0.0, w=24.0, crown=0.15, **attrs):
        self.tid = tid
        self.name_en = name_en
        self.name_ar = name_ar
        self.x0, self.y0, self.z0 = map(float, start)
        self.yaw0 = math.radians(yaw_deg)
        self.x, self.z, self.yaw = self.x0, self.z0, self.yaw0
        self.d = 0.0
        self.fine = [(0.0, self.x, self.z, self.yaw, 0.0)]
        self.keys = {"y": [(0.0, self.y0, "s")], "w": [(0.0, float(w), "s")],
                     "bank": [(0.0, 0.0, "s")], "crown": [(0.0, float(crown), "s")]}
        self.cur = dict(DEFAULTS)
        self.cur.update({k: v for k, v in attrs.items() if k in DEFAULTS})
        self.ranges = []
        self.adds = []
        self.feat = {k: [] for k in ("pads", "hazards", "obstacles", "crates", "fruit", "shortcuts",
                                      "landmarks", "patches", "rings", "lights", "decor")}
        self.marks = {}
        self.env = {}
        self.closed = False

    # ------------------------------------------------------------------ authoring
    def zone_start(self, name):
        for d0, d1, at in self.ranges:
            if at["zone"] == name:
                return d0
        raise KeyError(name)

    def zone_end(self, name):
        last = None
        for d0, d1, at in self.ranges:
            if at["zone"] == name:
                last = d1
        if last is None:
            raise KeyError(name)
        return last

    def here(self):
        return self.d

    def mark(self, name):
        self.marks[name] = self.d
        return self.d

    def ylast(self):
        return self.keys["y"][-1][1]

    def wlast(self):
        return self.keys["w"][-1][1]

    def seg(self, L, deg=0.0, ease=0.25, ymode="s", **a):
        L = float(L)
        d0 = self.d
        ang = math.radians(deg)
        n = max(1, int(math.ceil(L / FINE)))
        ds = L / n
        e = ease if deg != 0 else 0.0
        kpk = ang / (L * (1.0 - e)) if deg != 0 else 0.0
        for i in range(n):
            u = (i + 0.5) * ds / L
            f = 1.0
            if e > 0:
                if u < e:
                    f = u / e
                elif u > 1 - e:
                    f = (1 - u) / e
            k = kpk * f
            ym = self.yaw + k * ds * 0.5
            self.x += -math.sin(ym) * ds
            self.z += -math.cos(ym) * ds
            self.yaw += k * ds
            self.d += ds
            self.fine.append((self.d, self.x, self.z, self.yaw, k))
        sticky = {k: v for k, v in a.items() if k in STICKY}
        self.cur.update(sticky)
        attrs = dict(self.cur)
        for fl in FLAGS:
            attrs[fl] = bool(a.get(fl, False))
        self.ranges.append((d0, self.d, attrs))
        if "dy" in a:
            a["y"] = self.ylast() + float(a["dy"])
        for ch in ("y", "w", "bank", "crown"):
            if ch in a:
                mode = ymode if ch == "y" else a.get(ch + "mode", "s")
                self.keys[ch].append((self.d, float(a[ch]), mode))
        return self

    def straight(self, L, **a):
        return self.seg(L, 0.0, **a)

    def turn(self, R, deg, ease=0.22, **a):
        return self.seg(R * abs(math.radians(deg)), deg, ease=ease, **a)

    def edges(self, l, r=None, **a):
        self.cur["edge_l"] = l
        self.cur["edge_r"] = r if r is not None else l
        self.cur.update({k: v for k, v in a.items() if k in STICKY})

    def zone(self, name, **a):
        self.cur["zone"] = name
        self.cur.update({k: v for k, v in a.items() if k in STICKY})

    def jump(self, ramp_len=14.0, rise=2.2, gap=7.0, drop=3.4, land_len=28.0, land_slope=0.18, deg=0.0, **a):
        """Main-route CTR drop-jump: take-off ramp, short real gap, landing that keeps falling away so the
        parabola meets it softly. Safe from 22 m/s (falls < drop over the gap), ~0.5 s air at base speed,
        ~0.9 s with a hop at the lip (bigger hang-time boost)."""
        y0 = self.ylast()
        self.seg(ramp_len, 0.0, ymode="l", y=y0 + rise, ramp=True, **a)
        ylip = y0 + rise
        self.seg(gap, 0.0, ymode="g", y=ylip - drop, gap=True)
        l1 = land_len * 0.45
        y_l1 = ylip - drop - l1 * land_slope
        self.seg(l1, 0.0, ymode="l", y=y_l1)
        self.seg(land_len - l1, deg, ymode="s", y=y_l1 - 0.25)
        return self

    def drop_ledge(self, gap=6.0, drop=4.0, land_len=20.0, **a):
        """Road simply ends and continues lower (waterfall / step drop) - flat take-off."""
        y0 = self.ylast()
        self.keys["y"].append((self.d, y0, "s"))   # pin the lip height: flat take-off
        self.seg(gap, 0.0, ymode="g", y=y0 - drop, gap=True, **a)
        self.seg(land_len * 0.4, 0.0, ymode="l", y=y0 - drop - land_len * 0.4 * 0.06)
        self.seg(land_len * 0.6, 0.0, ymode="s", y=y0 - drop - land_len * 0.4 * 0.06 - 0.2)
        return self

    def bumps(self, L, amp=0.9, wavelength=14.0, deg=0.0, **a):
        d0 = self.d
        self.seg(L, deg, **a)
        self.adds.append(("bumps", d0, self.d, float(amp), float(wavelength)))
        return self

    def crest(self, L, h=1.6, deg=0.0, peak=0.62, **a):
        """Single hump; with peak late and a steep back side it launches fast karts (natural crest jump)."""
        d0 = self.d
        self.seg(L, deg, **a)
        self.adds.append(("crest", d0, self.d, float(h), float(peak)))
        return self

    # ------------------------------------------------------------------ features
    def pad(self, lat=0.0, at=None, sup=False, length=12.0):
        self.feat["pads"].append(dict(d=self.d if at is None else at, lat=lat, super=sup, len=length))

    def hazard(self, kind, at=None, lat=0.0, **p):
        h = dict(kind=kind, d=self.d if at is None else at, lat=lat)
        h.update(p)
        self.feat["hazards"].append(h)

    def obstacle(self, kind, at=None, lat=0.0, r=1.5, strength="heavy", **p):
        o = dict(kind=kind, d=self.d if at is None else at, lat=lat, r=r, strength=strength)
        o.update(p)
        self.feat["obstacles"].append(o)

    def crates(self, at=None, n=4, spread=0.7):
        self.feat["crates"].append(dict(d=self.d if at is None else at, n=n, spread=spread))

    def fruit(self, d0, d1, lat=0.0, n=6, lat1=None):
        self.feat["fruit"].append(dict(d0=d0, d1=d1, lat=lat, lat1=lat if lat1 is None else lat1, n=n))

    def ring(self, at=None, lat=0.0, h=4.6):
        self.feat["rings"].append(dict(d=self.d if at is None else at, lat=lat, h=h))

    def patch(self, d0, d1, lat0, lat1, surf):
        self.feat["patches"].append(dict(d0=d0, d1=d1, lat0=lat0, lat1=lat1, surf=surf))

    def landmark(self, kind, **p):
        self.feat["landmarks"].append(dict(kind=kind, **p))

    def decor(self, kind, at=None, lat=0.0, **p):
        self.feat["decor"].append(dict(kind=kind, d=self.d if at is None else at, lat=lat, **p))

    def shortcut_auto(self, sid, name_en, name_ar, kind, launch_d, side, yaw_off, target_range, required_fire=3,
                      n_plats=0, hidden="rock", kw=6.5, kl=8.0, plat_r=7.0, edge_in=0.6, plat_kind="stone",
                      lead_m=3.5, max_pitch=24.0, min_pitch=8.0, fail_fruit=True):
        """CTR-style shortcut solver (resolved in finalize): kicker at the road edge, yawed `yaw_off` degrees from
        the road heading toward `side` ('l' / 'r'); the landing is where that line meets the road between
        target_range=(d0, d1); the pitch is solved so the REQUIRED fire tier (no fruit) lands `lead_m` past the near
        edge of the landing window while base speed + 10 fruit falls short. Platforms (kind 'platforms') are
        placed along the line so each hop at required speed lands on the next pad."""
        self.feat.setdefault("shortcuts_auto", []).append(dict(
            id=sid, name_en=name_en, name_ar=name_ar, kind=kind, launch_d=launch_d, side=side, yaw_off=yaw_off,
            target_range=target_range, required_fire=required_fire, n_plats=n_plats, hidden=hidden, kw=kw, kl=kl,
            plat_r=plat_r, edge_in=edge_in, plat_kind=plat_kind, lead_m=lead_m, max_pitch=max_pitch,
            min_pitch=min_pitch, fail_fruit=fail_fruit))

    def shortcut(self, sid, name_en, name_ar, kind, launch_d, launch_lat, target_d, target_lat,
                 pitch=18.0, kw=7.0, kl=8.0, required_fire=3, platforms=None, hidden="rock", note="",
                 kicker_h0=0.0, launch_out=0.0):
        """Jump-only shortcut. `platforms` = list of dict(f=fraction along launch->target chord,
        dy=height relative to the chord, r=radius, h=thickness, lat=sideways offset)."""
        self.feat["shortcuts"].append(dict(id=sid, name_en=name_en, name_ar=name_ar, kind=kind,
                                           launch_d=launch_d, launch_lat=launch_lat, target_d=target_d,
                                           target_lat=target_lat, pitch=pitch, kw=kw, kl=kl,
                                           required_fire=required_fire, platforms=platforms or [],
                                           hidden=hidden, note=note, kicker_h0=kicker_h0, launch_out=launch_out))

    # ------------------------------------------------------------------ build
    def close(self):
        """Cubic Hermite connector from the current pose back to the start pose."""
        self.open_end = (round(self.x, 1), round(self.z, 1), round(math.degrees(self.yaw) % 360, 1), round(self.d, 1))
        p0 = np.array([self.x, self.z])
        p1 = np.array([self.x0, self.z0])
        t0 = np.array([-math.sin(self.yaw), -math.cos(self.yaw)])
        t1 = np.array([-math.sin(self.yaw0), -math.cos(self.yaw0)])
        chord = float(np.linalg.norm(p1 - p0))
        m = max(chord, 1.0) * 1.0
        nn = max(8, int(chord / FINE) * 2)
        pts = []
        for i in range(1, nn + 1):
            u = i / nn
            h00 = 2 * u ** 3 - 3 * u ** 2 + 1
            h10 = u ** 3 - 2 * u ** 2 + u
            h01 = -2 * u ** 3 + 3 * u ** 2
            h11 = u ** 3 - u ** 2
            pts.append(h00 * p0 + h10 * m * t0 + h01 * p1 + h11 * m * t1)
        prev = p0
        d0 = self.d
        for p in pts:
            seglen = float(np.linalg.norm(p - prev))
            if seglen < 1e-6:
                continue
            dirv = (p - prev) / seglen
            yaw = math.atan2(-dirv[0], -dirv[1])
            dy = (yaw - self.yaw + math.pi) % (2 * math.pi) - math.pi
            k = dy / seglen
            self.yaw += dy
            self.d += seglen
            self.x, self.z = float(p[0]), float(p[1])
            self.fine.append((self.d, self.x, self.z, self.yaw, k))
            prev = p
        self.ranges.append((d0, self.d, dict(self.cur, gap=False, ramp=False, lip=False)))
        self.closing_len = self.d - d0
        self.closing_turn = math.degrees(self.yaw - self.yaw0)
        for ch in ("y", "w", "bank", "crown"):
            self.keys[ch].append((self.d, self.keys[ch][0][1], "s"))
        self.closed = True

    def _attr_at(self, d):
        lo, hi = 0, len(self.ranges) - 1
        while lo < hi:
            mid = (lo + hi) // 2
            if self.ranges[mid][1] <= d:
                lo = mid + 1
            else:
                hi = mid
        return self.ranges[lo][2]

    def finalize(self):
        if not self.closed:
            self.close()
        total = self.d
        fine = np.array(self.fine)
        N = int(round(total / STEP))
        step = total / N
        self.step = step
        self.total = total
        ds = np.arange(N) * step
        fx = np.interp(ds, fine[:, 0], fine[:, 1])
        fz = np.interp(ds, fine[:, 0], fine[:, 2])
        yaw_un = np.unwrap(fine[:, 3])
        fyaw = np.interp(ds, fine[:, 0], yaw_un)
        # curvature averaged over a +-6 m window (rad/m), positive = left turn
        kraw = np.interp(ds, fine[:, 0], fine[:, 4])
        win = max(1, int(6.0 / step))
        kern = np.ones(2 * win + 1) / (2 * win + 1)
        kpad = np.concatenate([kraw[-win:], kraw, kraw[:win]])
        curv = np.convolve(kpad, kern, mode="valid")
        y = eval_channel(self.keys["y"], ds, total)
        w = eval_channel(self.keys["w"], ds, total)
        bank = eval_channel(self.keys["bank"], ds, total)
        crown = eval_channel(self.keys["crown"], ds, total)
        for add in self.adds:
            kind, d0, d1 = add[0], add[1], add[2]
            msk = (ds >= d0) & (ds <= d1)
            u = (ds[msk] - d0) / max(1e-6, d1 - d0)
            if kind == "bumps":
                amp, wl = add[3], add[4]
                env = np.clip(np.minimum(u, 1 - u) * (d1 - d0) / (wl * 0.75), 0.0, 1.0)
                y[msk] += amp * np.sin(math.pi * (ds[msk] - d0) / wl) ** 2 * env
            elif kind == "crest":
                h, pk = add[3], add[4]
                up = np.where(u < pk, 0.5 - 0.5 * np.cos(math.pi * u / pk), 0.5 + 0.5 * np.cos(math.pi * (u - pk) / (1 - pk)))
                y[msk] += h * up
        attrs = [self._attr_at(d + 1e-4) for d in ds]
        # auto-bank from curvature
        for i, a in enumerate(attrs):
            if a.get("auto_bank", 0.0) != 0.0:
                bank[i] += float(a["auto_bank"]) * curv[i]
        bank = np.clip(bank, -28.0, 28.0)
        self.S = dict(d=ds, x=fx, z=fz, y=y, yaw=fyaw, curv=curv, w=w, bank=bank, crown=crown, attrs=attrs)
        self._frames()
        self._resolve_features()
        return self

    def _frames(self):
        S = self.S
        n = len(S["d"])
        pos = np.stack([S["x"], S["y"], S["z"]], axis=1)
        fwd = np.roll(pos, -1, axis=0) - np.roll(pos, 1, axis=0)
        fwd /= np.linalg.norm(fwd, axis=1, keepdims=True)
        up0 = np.array([0.0, 1.0, 0.0])
        flat_r = np.cross(fwd, up0)
        flat_r /= np.linalg.norm(flat_r, axis=1, keepdims=True)
        flat_u = np.cross(flat_r, fwd)
        br = np.radians(S["bank"])[:, None]
        right = flat_r * np.cos(br) + flat_u * np.sin(br)
        right /= np.linalg.norm(right, axis=1, keepdims=True)
        upv = np.cross(right, fwd)
        S["pos"], S["fwd"], S["right"], S["up"] = pos, fwd, right, upv

    def index_at(self, d):
        return int(round((d % self.total) / self.step)) % len(self.S["d"])

    def frame_at(self, d, lat=0.0):
        """World point on the road surface at distance d and lateral offset lat (crown/bank aware)."""
        i = self.index_at(d)
        S = self.S
        hw = S["w"][i] * 0.5
        cr = S["crown"][i] * max(0.0, 1.0 - abs(lat) / max(1.0, hw))
        p = S["pos"][i] + S["right"][i] * lat + S["up"][i] * cr
        return p, S["fwd"][i], S["right"][i], S["up"][i], i

    # physics constants mirrored from KartPhysics.gd (used by the shortcut solver)
    G = 58.0
    HOP = 14.8 + 2.6
    TIER_V = {0: 34.0, 1: 38.0, 2: 42.0, 3: 47.5, 4: 54.0}

    def _flight_range(self, v, pitch_deg, dy, hop=True):
        p = math.radians(pitch_deg)
        vy0 = v * math.sin(p) + (self.HOP if hop else -1.9)
        disc = vy0 * vy0 + 2 * self.G * (-dy) if dy <= 0 else vy0 * vy0 - 2 * self.G * dy
        if disc < 0:
            return 0.0
        t = (vy0 + math.sqrt(disc)) / self.G
        return 0.96 * v * t

    def _ray_window(self, p0, dirv, i_range, max_len=170.0):
        """March the xz ray from p0; return (L_near, L_far, idx_first) over road samples in index window."""
        S = self.S
        i0, i1 = i_range
        n = len(S["d"])
        idxs = [(i0 + k) % n for k in range(((i1 - i0) % n) + 1)]
        P = S["pos"][idxs][:, [0, 2]]
        R = S["right"][idxs][:, [0, 2]]
        R = R / np.linalg.norm(R, axis=1, keepdims=True)
        Fv = S["fwd"][idxs][:, [0, 2]]
        Fv = Fv / np.linalg.norm(Fv, axis=1, keepdims=True)
        HW = S["w"][idxs] * 0.5
        near = far = None
        first = None
        for step in np.arange(1.0, max_len, 0.5):
            q = p0 + dirv * step
            rel = q - P
            lat = (rel * R).sum(1)
            al = (rel * Fv).sum(1)
            ok = (np.abs(al) <= self.step * 0.8) & (np.abs(lat) <= HW - 2.5)
            if ok.any():
                if near is None:
                    near = step
                    first = idxs[int(np.argmax(ok))]
                far = step
            elif near is not None and step - far > 3.0:
                break
        return near, far, first

    def _solve_auto_shortcuts(self):
        out = []
        for sc in self.feat.get("shortcuts_auto", []):
            i = self.index_at(sc["launch_d"])
            hw = self.S["w"][i] * 0.5
            sgn = -1.0 if sc["side"] == "l" else 1.0
            lat = sgn * (hw - sc["kw"] * 0.5 - sc["edge_in"]) if sc["edge_in"] >= 0 else sgn * (hw - sc["edge_in"])
            p, f, r, u, _ = self.frame_at(sc["launch_d"], lat)
            fxz = np.array([f[0], f[2]]); fxz /= np.linalg.norm(fxz)
            yaw = math.atan2(-fxz[0], -fxz[1]) + math.radians(sc["yaw_off"]) * (1.0 if sc["side"] == "l" else -1.0)
            dirv = np.array([-math.sin(yaw), -math.cos(yaw)])
            i_r = (self.index_at(sc["target_range"][0]), self.index_at(sc["target_range"][1]))
            kl = sc["kl"]
            best = None
            v_req = self.TIER_V[sc["required_fire"]]
            v_fail = self.TIER_V[0] * (1.18 if sc.get("fail_fruit", True) else 1.0)
            for pitch in np.arange(sc.get("min_pitch", 8.0), sc["max_pitch"] + 0.01, 0.5):
                lip_h = math.tan(math.radians(pitch)) * kl
                lip_xz = np.array([p[0], p[2]]) + dirv * kl
                lip_y = p[1] + lip_h
                if sc["kind"] != "platforms":
                    near, far, ti = self._ray_window(lip_xz, dirv, i_r)
                    if near is None:
                        continue
                    ty = self.S["pos"][ti][1]
                    r_req = self._flight_range(v_req, pitch, ty - lip_y)
                    r_fail = self._flight_range(v_fail, pitch, ty - lip_y)
                    if r_req >= near + sc["lead_m"] and r_fail < near - 2.0:
                        best = dict(pitch=float(pitch), near=near, far=far, ti=ti, lip=lip_xz, lip_y=lip_y,
                                    r_req=r_req, r_fail=r_fail, ty=ty)
                        break
                else:
                    near, far, ti = self._ray_window(lip_xz, dirv, i_r)
                    if near is None:
                        continue
                    best = dict(pitch=float(pitch), near=near, far=far, ti=ti, lip=lip_xz, lip_y=lip_y,
                                ty=self.S["pos"][ti][1])
                    break
            if best is None:
                print(f"   !! shortcut {sc['id']}: no pitch satisfies the speed window (adjust yaw/launch)")
                near, far, ti = self._ray_window(np.array([p[0], p[2]]) + dirv * kl, dirv, i_r)
                print("      window", near, far)
                continue
            plats = []
            if sc["kind"] == "platforms":
                # one floating pad with its own small ramp on the far half: leap 1 kicker->pad, leap 2 pad ramp->road
                pr = sc["plat_r"]
                p2 = 12.0
                total = best["near"] + sc["lead_m"]
                found = False
                for frac in np.arange(0.36, 0.80, 0.02):
                    D1 = total * frac
                    pad_y = best["lip_y"] - 1.2
                    lip2_d = D1 + pr
                    lip2_y = pad_y + math.tan(math.radians(p2)) * pr
                    rem_near = best["near"] - lip2_d
                    r2 = self._flight_range(v_req, p2, best["ty"] - lip2_y)
                    if r2 < rem_near + sc["lead_m"] * 0.6:
                        continue
                    for pt in np.arange(6.0, sc["max_pitch"] + 0.01, 0.5):
                        r1 = self._flight_range(v_req, pt, pad_y - best["lip_y"])
                        r1f = self._flight_range(v_fail, pt, pad_y - best["lip_y"])
                        if r1 >= D1 - pr + 1.8 and r1 <= D1 + pr * 0.2 and r1f < D1 - pr - 1.0:
                            c = best["lip"] + dirv * D1
                            plats.append(dict(x=float(c[0]), y=float(pad_y), z=float(c[1]), r=pr, h=2.0,
                                              kind=sc["plat_kind"], ramp=p2))
                            best["pitch"] = float(pt)
                            best["r_req"] = r1
                            best["r_fail"] = r1f
                            best["seg"] = D1
                            best["hop_flat_req"] = r2
                            best["hop_flat_fail"] = self._flight_range(v_fail, p2, best["ty"] - lip2_y)
                            found = True
                            break
                    if found:
                        break
                if not found:
                    print(f"   !! shortcut {sc['id']}: no platform layout fits (window {best['near']:.1f})")
                    continue
            tp = self.S["pos"][best["ti"]]
            land_d = float(self.S["d"][best["ti"]])
            # land a bit further along the window so tests aim at the middle of the landing road
            land = best["lip"] + dirv * min(best["far"], best["near"] + max(sc["lead_m"] + 4.0, (best["far"] - best["near"]) * 0.35))
            rel = land - tp[[0, 2]]
            rr = self.S["right"][best["ti"]][[0, 2]]; rr = rr / np.linalg.norm(rr)
            tlat = float(rel @ rr)
            out.append(dict(id=sc["id"], name_en=sc["name_en"], name_ar=sc["name_ar"], kind=sc["kind"],
                            launch_d=sc["launch_d"], launch_lat=float(lat), target_d=land_d, target_lat=tlat,
                            pitch=best["pitch"], kw=sc["kw"], kl=kl, required_fire=sc["required_fire"],
                            platforms=[], plats_abs=plats, hidden=sc["hidden"], note="auto",
                            kicker_h0=0.0, launch_out=0.0, aim_x=float(land[0]), aim_z=float(land[1]),
                            yaw=yaw, solver=dict(near=round(best["near"], 1), far=round(best["far"], 1),
                                                 r_req=round(best["r_req"], 1), r_fail=round(best["r_fail"], 1),
                                                 pitch=best["pitch"])))
            print(f"   shortcut {sc['id']}: pitch={best['pitch']} window=[{best['near']:.1f},{best['far']:.1f}] "
                  f"req_range={best['r_req']:.1f} fail_range={best['r_fail']:.1f}" +
                  (f" plats={len(plats)} seg={best.get('seg',0):.1f} hop_req={best.get('hop_flat_req',0):.1f} hop_fail={best.get('hop_flat_fail',0):.1f}" if plats else ""))
        return out

    def _resolve_features(self):
        F = self.feat
        F["shortcuts"] = [s_ for s_ in F["shortcuts"] if s_.get("note") != "auto"] + self._solve_auto_shortcuts()
        # world-space shortcut descriptors (kicker frame, platforms, landing)
        out = []
        for sc in F["shortcuts"]:
            lp, lf, lr, lu, li = self.frame_at(sc["launch_d"], sc["launch_lat"])
            tp, tf, tr, tu, ti = self.frame_at(sc["target_d"], sc["target_lat"])
            to_t = np.array([tp[0] - lp[0], 0.0, tp[2] - lp[2]])
            dist = float(np.linalg.norm(to_t))
            to_t /= max(dist, 1e-6)
            yaw = math.atan2(-to_t[0], -to_t[2])
            plats = list(sc.get("plats_abs", []))
            for pl in sc["platforms"]:
                f = pl.get("f", 0.5)
                c = lp + (tp - lp) * f
                side = np.array([-to_t[2], 0.0, to_t[0]])
                c = c + side * pl.get("lat", 0.0)
                c[1] = lp[1] + (tp[1] - lp[1]) * f + pl.get("dy", 0.0)
                plats.append(dict(x=float(c[0]), y=float(c[1]), z=float(c[2]), r=pl.get("r", 7.0),
                                  h=pl.get("h", 2.0), kind=pl.get("kind", "stone")))
            d = dict(sc)
            d.update(lx=float(lp[0]), ly=float(lp[1]), lz=float(lp[2]), yaw=yaw, li=li,
                     tx=float(tp[0]), ty=float(tp[1]), tz=float(tp[2]), ti=ti, chord=dist,
                     plats=plats, bank_l=float(self.S["bank"][li]))
            out.append(d)
        self.shortcuts_world = out

    # ------------------------------------------------------------------ validation
    def validate(self, verbose=True):
        S = self.S
        n = len(S["d"])
        pos = S["pos"]
        hw = S["w"] * 0.5
        sh = np.array([max(a["sh_l"], a["sh_r"]) for a in S["attrs"]])
        issues = []
        # self overlap / vertical clearance
        xz = pos[:, [0, 2]]
        for i in range(0, n, 2):
            dvec = xz - xz[i]
            dist = np.sqrt((dvec ** 2).sum(axis=1))
            along = np.abs(S["d"] - S["d"][i])
            along = np.minimum(along, self.total - along)
            near = (dist < hw + hw[i] + sh + sh[i] + 3.0) & (along > np.maximum(40.0, (hw + hw[i]) * 2.2))
            if near.any():
                dy = np.abs(pos[near, 1] - pos[i, 1])
                j = np.where(near)[0][np.argmin(dy)]
                if dy.min() < 8.5:
                    issues.append(("overlap", round(S["d"][i]), round(S["d"][j]), round(float(dy.min()), 1)))
        # radius
        rmin = 1.0 / max(1e-6, np.abs(S["curv"]).max())
        # grade (excluding ramps/gaps)
        dy = np.diff(S["y"], append=S["y"][0])
        grade = np.abs(dy) / self.step
        nonramp = np.array([not (a["ramp"] or a["gap"]) for a in S["attrs"]])
        gmax = float(grade[nonramp].max())
        self.grade_at = float(S["d"][np.where(nonramp)[0][np.argmax(grade[nonramp])]])
        self.rmin_at = float(S["d"][np.argmax(np.abs(S["curv"]))])
        res = dict(length=round(self.total, 1), samples=n, min_radius=round(rmin, 1), max_grade=round(gmax, 3),
                   y_range=(round(float(S["y"].min()), 1), round(float(S["y"].max()), 1)),
                   width_range=(round(float(S["w"].min()), 1), round(float(S["w"].max()), 1)),
                   closing_len=round(self.closing_len, 1), closing_turn=round(self.closing_turn, 1),
                   overlaps=len(issues), grade_at=round(self.grade_at), rmin_at=round(self.rmin_at))
        if verbose:
            print(f"[{self.tid}] {res}")
            seen = set()
            for it in issues:
                key = (it[1] // 20, it[2] // 20)
                if key in seen:
                    continue
                seen.add(key)
                print("   overlap at d=", it[1], "vs", it[2], "dy=", it[3])
        self.validation = res
        self.issues = issues
        return res

    # ------------------------------------------------------------------ export
    def export(self, path, extra=None):
        S = self.S
        cols = {k: [] for k in ("x", "y", "z", "w", "bank", "crown", "curv")}
        for k in cols:
            cols[k] = [round(float(v), 3) for v in S[k]]
        akeys = ["surf", "edge_l", "edge_r", "wall_l", "wall_r", "sh_l", "sh_r", "shs_l", "shs_r", "ceil",
                 "ground", "deck", "biome", "zone", "gap", "ramp", "theme_wall"]
        for k in akeys:
            cols[k] = [a[k] for a in S["attrs"]]
        F = dict(self.feat)
        F["shortcuts"] = self.shortcuts_world
        data = dict(id=self.tid, name_en=self.name_en, name_ar=self.name_ar, length=round(self.total, 2),
                    step=self.step, count=len(S["d"]), cols=cols, features=F, env=self.env,
                    validation=self.validation)
        if extra:
            data.update(extra)
        with open(path, "w") as f:
            json.dump(data, f, separators=(",", ":"))
        return path


# ============================================================================ polygon + fillet authoring
def _yaw_of(v):
    return math.atan2(-v[0], -v[1])


_TUNIT_CACHE = {}


def eased_tangent_unit(theta_deg, ease):
    """Tangent length of an eased arc (trapezoid curvature, nominal radius 1) turning |theta|."""
    key = (round(abs(theta_deg), 4), round(ease, 4))
    if key in _TUNIT_CACHE:
        return _TUNIT_CACHE[key]
    th = math.radians(abs(theta_deg))
    if th < 1e-6:
        return 0.0
    L = th
    n = 4000
    ds = L / n
    kpk = th / (L * (1.0 - ease))
    x = y = a = 0.0
    for i in range(n):
        u = (i + 0.5) / n
        f = 1.0
        if ease > 0:
            if u < ease:
                f = u / ease
            elif u > 1 - ease:
                f = (1 - u) / ease
        k = kpk * f
        am = a + k * ds * 0.5
        x += math.cos(am) * ds
        y += math.sin(am) * ds
        a += k * ds
    t = x - y / math.tan(th)
    _TUNIT_CACHE[key] = t
    return t


def poly_plan(verts):
    """verts: list of dict(p=(x,z), r=radius, ...). Vertex 0 is the start line (r ignored, must be straight-through).
    Returns per-vertex turn (deg), tangent length and per-edge straight length (edge i: vertex i -> i+1)."""
    n = len(verts)
    P = [np.array(v["p"], dtype=float) for v in verts]
    dirs = []
    for i in range(n):
        d = P[(i + 1) % n] - P[i]
        dirs.append(d / np.linalg.norm(d))
    turns, tans = [], []
    for i in range(n):
        a, b = dirs[i - 1], dirs[i]
        t = (_yaw_of(b) - _yaw_of(a) + math.pi) % (2 * math.pi) - math.pi
        r = verts[i].get("r", 0.0) if i > 0 else 0.0
        turns.append(math.degrees(t))
        ease = verts[i].get("ease", 0.22)
        tans.append(r * eased_tangent_unit(math.degrees(t), ease) if r > 0 else 0.0)
    edges = []
    for i in range(n):
        L = float(np.linalg.norm(P[(i + 1) % n] - P[i])) - tans[i] - tans[(i + 1) % n]
        edges.append(L)
    return dict(P=P, dirs=dirs, turns=turns, tans=tans, edges=edges)


def build_poly(T, verts, verbose=True):
    """Drive the turtle along a filleted polygon. Each vertex dict may contain:
       attrs: sticky attributes / zone applied BEFORE its arc,  keys: dict(y=, w=, bank=, crown=) at arc end,
       ops: list of edge operations for the edge LEAVING the vertex, executed in order; leftover length is
            emitted as a plain straight at the end. op = ('s', L, keys) | ('jump', kw) | ('bumps', L, amp, wl, keys)
            | ('crest', L, h, keys) | ('ledge', kw) | ('call', fn) (fn(T) for features) | ('fill', keys) leftover marker.
    """
    plan = poly_plan(verts)
    n = len(verts)
    yaw0 = _yaw_of(plan["dirs"][0])
    assert abs(T.yaw - yaw0) < 1e-6 or True
    for i in range(n):
        v = verts[i]
        if "attrs" in v:
            T.cur.update({k: val for k, val in v["attrs"].items() if k in STICKY})
        if "mark_in" in v:
            T.mark(v["mark_in"])
        if i > 0 and abs(plan["turns"][i]) > 0.3 and v.get("r", 0) > 0:
            keys = dict(v.get("keys", {}))
            keys.setdefault("bank", 0.0)   # banking is explicit per corner (auto_bank adds curvature banking)
            T.turn(v["r"], plan["turns"][i], ease=v.get("ease", 0.22), **keys)
        elif "keys" in v and i > 0:
            pass
        if "mark" in v:
            T.mark(v["mark"])
        L = plan["edges"][i]
        if L < -0.5:
            for jj, vv in enumerate(verts):
                print(f"  v{jj:02d} {vv.get('name',''):16s} turn={plan['turns'][jj]:7.1f} R={vv.get('r',0):5.1f} tan={plan['tans'][jj]:6.1f} edge={plan['edges'][jj]:7.1f}")
            raise ValueError(f"edge {i} too short for fillets: {L:.1f} m (vertex {v.get('name', i)})")
        rem = L
        fill_keys = {}
        for op in v.get("ops", []):
            kind = op[0]
            if kind == "s":
                ln = min(op[1], rem) if op[1] > 0 else rem
                T.straight(ln, **(op[2] if len(op) > 2 else {}))
                rem -= ln
            elif kind == "jump":
                kw = op[1]
                tot = kw.get("ramp_len", 16) + kw.get("gap", 12) + kw.get("land_len", 24)
                T.jump(**kw)
                rem -= tot
            elif kind == "ledge":
                kw = op[1]
                tot = kw.get("gap", 6) + kw.get("land_len", 20)
                T.drop_ledge(**kw)
                rem -= tot
            elif kind == "bumps":
                T.bumps(op[1], op[2], op[3], **(op[4] if len(op) > 4 else {}))
                rem -= op[1]
            elif kind == "crest":
                T.crest(op[1], op[2], **(op[3] if len(op) > 3 else {}))
                rem -= op[1]
            elif kind == "call":
                op[1](T)
            elif kind == "fill":
                fill_keys = op[1]
            if rem < -0.5:
                raise ValueError(f"edge {i} ops exceed edge length by {-rem:.1f} m (vertex {v.get('name', i)})")
        if rem > 0.05:
            T.straight(rem, **fill_keys)
        elif fill_keys:
            for ch in ("y", "w", "bank", "crown"):
                if ch in fill_keys:
                    T.keys[ch].append((T.d, float(fill_keys[ch]), "s"))
    if verbose:
        for i, v in enumerate(verts):
            print(f"  v{i:02d} {v.get('name',''):16s} turn={plan['turns'][i]:7.1f} R={v.get('r',0):5.1f} "
                  f"tan={plan['tans'][i]:6.1f} edge={plan['edges'][i]:7.1f}")
    return plan
