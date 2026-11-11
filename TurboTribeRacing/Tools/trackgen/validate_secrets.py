#!/usr/bin/env python3
"""Checks that every hidden shortcut is makeable WITH skill and fails WITHOUT it.
Builds the real road profile of each secret branch from the exported JSON (same spline sampling as the game),
adds its kickers / humps / gaps, and runs the 2-D kart model (jumpsim.py) at cruise and boosted speed with no
input and with lip jumps pressed at several lead times.   usage: validate_secrets.py track.json"""
import json, math, sys
import numpy as np
import preview as pv
import jumpsim as js


def kicker_h(e, d, lip):
    L = e.get('len', 8); h = e.get('h', 1.5)
    if lip - L <= d <= lip: return h * (1 - math.cos((d - (lip - L)) / L * math.pi / 2))
    return 0.0


def hump_h(e, d, crest):
    L = max(4.0, e.get('len', 8)); H = max(0.3, e.get('h', 1.0))
    u = (d - (crest - 0.62 * L)) / L
    if u < 0 or u > 1: return 0.0
    return H * (1 - math.cos(u / 0.62 * math.pi / 2)) if u < 0.62 else H * (0.5 + 0.5 * math.cos((u - 0.62) / 0.38 * math.pi))


def branch_profile(data, rd, main_s):
    ia = main_s.idx(rd['from']['t']); ib = main_s.idx(rd['to']['t'])
    def mp(i, w):
        p = main_s.pos[main_s.wrap(i)]
        return dict(x=p[0], y=p[1], z=p[2], w=w)
    w0 = rd['points'][0]['w']; w1 = rd['points'][-1]['w']
    pts = ([] if rd.get('detachStart') else [mp(ia - 12, w0), mp(ia, w0)]) + rd['points'] + ([] if rd.get('detachEnd') else [mp(ib, w1), mp(ib + 12, w1)])
    b = pv.build(pts, False, 1.0, mods=pv.mods_for(data, rd['id']))
    n = b.count
    ys = b.pos[:, 1].copy()
    gap = np.array([pv.in_range(data, rd['id'], 'gap', b.param[i]) for i in range(n)])
    feats = [e for e in data['events'] if e.get('road') == rd['id'] and e['type'] in ('ramp', 'hump')]
    # main-road launchers just before the junction (humps / ramps on main within 40 m)
    pre = []
    for e in data['events']:
        if e.get('road', 'main') != 'main' or e['type'] not in ('ramp', 'hump'): continue
        k = main_s.idx(e['t'])
        dd = ((ia - k) % main_s.count) * main_s.step     # metres before the junction anchor
        if 0 <= dd <= 40: pre.append((e, -dd + (0 if rd.get('detachStart') else 12)))
    # where the branch lies on top of the main road, the main surface (and its kickers / humps) is the ground
    main_feats = [(e, main_s.idx(e['t'])) for e in data['events'] if e.get('road', 'main') == 'main' and e['type'] in ('ramp', 'hump')]
    on_main = np.zeros(n, bool); main_y = np.zeros(n); main_k = np.zeros(n, int)
    hint = ia
    for i in range(n):
        best = None
        for k in range(hint - 30, hint + 31):
            kk = main_s.wrap(k); dd = np.sum((main_s.pos[kk][[0, 2]] - b.pos[i][[0, 2]]) ** 2)
            if best is None or dd < best[0]: best = (dd, kk)
        kk = best[1]; hint = kk
        lat = abs(np.dot(b.pos[i] - main_s.pos[kk], main_s.right[kk]))
        if lat < main_s.hw[kk] - 1.0 and abs(b.pos[i][1] - main_s.pos[kk][1]) < 12:
            on_main[i] = True; main_y[i] = main_s.pos[kk][1]; main_k[i] = kk
    def ground(d):
        if d < 0:
            g = ys[0]
        else:
            i = int(min(n - 1, max(0, round(d / b.step))))
            if on_main[i] and (gap[i] or ys[i] < main_y[i] - 0.5):
                g = main_y[i]
                for e, c in main_feats:
                    dk = ((main_k[i] - c + main_s.count // 2) % main_s.count - main_s.count // 2) * main_s.step
                    g += kicker_h(e, dk, 0.0) if e['type'] == 'ramp' else hump_h(e, dk, 0.0)
                return g
            if gap[i]: return None
            g = ys[i]
        for e in feats:
            c = b.idx(e['t']) * b.step
            g += kicker_h(e, d, c) if e['type'] == 'ramp' else hump_h(e, d, c)
        for e, c in pre:
            g += kicker_h(e, d, c) if e['type'] == 'ramp' else hump_h(e, d, c)
        return g
    ground.on_main = lambda d: bool(on_main[int(min(n - 1, max(0, round(d / b.step))))]) if d >= 0 else True
    gaps = []
    i = 0
    while i < n:
        if gap[i]:
            j = i
            while j < n and gap[j]: j += 1
            gaps.append((i * b.step, j * b.step)); i = j
        else: i += 1
    return ground, gaps, b.length


def fly(ground, speed, presses, x0=-40.0, tmax=None, gap_end=None, gap_start=0.0):
    """drive the whole branch: presses = lead seconds before EACH predicted takeoff (None = never press)."""
    x = x0; y = ground(x); v = speed; grounded = True; vy = 0.0; t = 0.0; air = 0.0
    loaded = False; load_t = 0.0; nosnap = 0.0; jumps = []; pi = 0; armed = True; fell = False; land_bonk = False
    landed_main_in_gap = False
    if tmax is None: tmax = ((gap_end or 200.0) + 80.0) / speed + 1.0
    while t < tmax and x < 400:
        g0 = ground(x)
        if grounded:
            s = js.slope(ground, x); nrm = math.hypot(1, s)
            vx, vy = v / nrm, v * s / nrm
            tin, sep = js.predict(x, y, v, ground)
            tau = 2 * js.DT; gl = ground(x + vx * tau)
            lifting = gl is None or (y + vy * tau - 0.5 * js.G * tau * tau) - gl > 0.01
            imminent = 0 <= tin <= 0.1 and lifting
            lead = presses[pi] if pi < len(presses) else None
            if lead is not None and armed and not loaded and 0 <= tin <= lead + 1e-9 and tin <= js.LIP_WINDOW:
                loaded = True; load_t = 0.0; armed = False
            if lead is not None and armed and not loaded and imminent:
                loaded = True; load_t = lead; armed = False     # pressed 'lead' s before a takeoff the predictor saw late
            if loaded:
                load_t += js.DT
                if imminent:
                    q = max(0.0, 1 - load_t / js.LIP_WINDOW)
                    vy += js.HOP + js.LIP_BONUS * q * q; grounded = False; nosnap = 0.15; loaded = False
                    jumps.append(('lip', x, q)); pi += 1
            elif imminent and sep >= js.NATURAL_SEP:
                grounded = False; nosnap = 0.08; jumps.append(('natural', x, None)); pi += 1
        if grounded:
            x += vx * js.DT; y += vy * js.DT
            g = ground(x); snap = 0.42 + 0.006 * v
            if g is None or y - g > snap or y - g < -1.0:
                grounded = False
                if loaded:
                    q = max(0.0, 1 - load_t / js.LIP_WINDOW); vy += js.HOP + js.LIP_BONUS * q * q; loaded = False; nosnap = 0.15
                    jumps.append(('lip', x, q))
                else: jumps.append(('edge', x, None))
                pi += 1
            else: y = g
        else:
            nosnap -= js.DT
            vy -= js.G * (js.FALL if vy < 0 else 1.0) * js.DT
            x += vx * js.DT; y += vy * js.DT; air += js.DT
            g = ground(x)
            if g is not None and y <= g and nosnap <= 0 and vy <= 0.5:
                if y < g - 0.8: fell = True; break          # came up under the far edge: hit the cliff face
                if gap_end is not None and gap_start <= x < gap_end and getattr(ground, 'on_main', None) and ground.on_main(x): landed_main_in_gap = True
                y = g; grounded = True; armed = True; air = 0.0
            if g is None and y < (ground_min(ground) - 6): fell = True; break
        t += js.DT
    return dict(fell=fell, x=x, jumps=jumps, short=landed_main_in_gap)


_gm = {}
def ground_min(ground):
    if id(ground) not in _gm:
        vals = [ground(d) for d in np.arange(-40, 300, 1.0)]
        _gm[id(ground)] = min(v for v in vals if v is not None)
    return _gm[id(ground)]


SKIP = {'bay_leap': 1}     # optional first hump that a smart player does not big-jump


def main():
    data = json.load(open(sys.argv[1]))
    main_s = pv.build(data['roads'][0]['points'], True, 1.0, mods=pv.mods_for(data, 'main'))
    for rd in data['roads'][1:]:
        if not rd.get('hidden'): continue
        rd['_skip_first'] = SKIP.get(rd['id'], 0)
        ground, gaps, L = branch_profile(data, rd, main_s)
        print(f"{rd['id']}: {L:.0f} m, gaps " + ", ".join(f"{a:.0f}-{b:.0f} m ({b-a:.0f} m)" for a, b in gaps))
        if not gaps:
            print('   (no gap: low-wall hop - checked by the geometry test)'); continue
        skip = rd.get('_skip_first', 0)
        for spd in (27.0, 30.0, 34.0):
            row = []
            for lead in (None, 0.30, 0.15, 0.06):
                presses = ([None] * skip + [lead] * 4) if lead is not None else []
                r = fly(ground, spd, presses, gap_end=gaps[-1][1], gap_start=gaps[0][0])
                qs = ','.join(f"{j[2]:.1f}" if j[2] is not None else j[0][0] for j in r['jumps'][:3])
                res = 'FALL' if r['fell'] else ('main' if r['short'] else 'ok  ')
                row.append(f"{'none' if lead is None else lead:>4}: {res} [{qs}]")
            print(f"   {spd:.0f} m/s  " + '   '.join(row))


if __name__ == '__main__':
    main()


# ---------------------------------------------------------------------------------------------- low-wall hops
def wall_hop(data, rd, main_s, hump_mark_t, lane_sign):
    """Horizontal geometry of a detached-start branch reached over a low wall: where the straight line from the
    launcher hump crosses main's walled edge and where it first lies on the branch surface; then the vertical model
    says at which launch qualities the kart is above the wall there and lands on the branch."""
    k = main_s.idx(hump_mark_t)
    hw = main_s.hw[k]
    p0 = main_s.pos[k] + main_s.right[k] * hw * 0.5 * lane_sign
    f = main_s.fwd[k]; f = np.array([f[0], 0, f[2]]); f /= np.linalg.norm(f)
    pts = rd['points']
    bp = np.array([[p['x'], p['z']] for p in pts]); bw = np.array([p['w'] for p in pts]) * 0.5
    x_wall = x_land = None
    hint = k
    for dist in np.arange(0, 80, 0.25):
        q = p0 + f * dist
        hint = int(min(range(hint - 3, hint + 12), key=lambda i: np.sum((main_s.pos[main_s.wrap(i)][[0, 2]] - q[[0, 2]]) ** 2)))
        j = main_s.wrap(hint)
        lat = np.dot(q - main_s.pos[j], main_s.right[j])
        if x_wall is None and abs(lat) > main_s.hw[j] + 0.35: x_wall = dist
        dd = np.sqrt(np.sum((bp - q[[0, 2]]) ** 2, axis=1)); i = int(np.argmin(dd))
        if x_land is None and x_wall is not None and dd[i] < bw[i] - 0.5: x_land = dist
        if x_wall is not None and x_land is not None: break
    return x_wall, x_land


def hop_heights(h, L, speed, lead):
    g = js.hump(h, L)
    def ground(x): return g(x + 0.62 * L)       # crest at x = 0
    traj = []
    r = fly_traj(ground, speed, lead, traj)
    return traj


def fly_traj(ground, speed, lead, traj):
    presses = [lead] if lead is not None else []
    x = -30.0; y = ground(x); v = speed; grounded = True; vy = 0.0; t = 0.0; loaded = False; load_t = 0.0; nosnap = 0.0; armed = True; pi = 0
    launched = False
    while t < 3.0:
        if grounded:
            s = js.slope(ground, x); nrm = math.hypot(1, s); vx, vy = v / nrm, v * s / nrm
            tin, sep = js.predict(x, y, v, ground)
            tau = 2 * js.DT; gl = ground(x + vx * tau)
            lifting = gl is None or (y + vy * tau - 0.5 * js.G * tau * tau) - gl > 0.01
            imminent = 0 <= tin <= 0.1 and lifting
            ld = presses[0] if presses and armed else None
            if ld is not None and not loaded and 0 <= tin <= ld: loaded = True; load_t = 0.0; armed = False
            if ld is not None and not loaded and imminent: loaded = True; load_t = ld; armed = False
            if loaded:
                load_t += js.DT
                if imminent:
                    q = max(0.0, 1 - load_t / js.LIP_WINDOW); vy += js.HOP + js.LIP_BONUS * q * q; grounded = False; nosnap = 0.15; loaded = False; launched = True
            elif imminent and sep >= js.NATURAL_SEP and not launched:
                grounded = False; nosnap = 0.08; launched = True
        if grounded:
            x += vx * js.DT; y = ground(x)
        else:
            nosnap -= js.DT; vy -= js.G * (js.FALL if vy < 0 else 1.0) * js.DT; x += vx * js.DT; y += vy * js.DT
            traj.append((x, y))
            if y <= ground(x) and nosnap <= 0 and vy <= 0.5: traj.append((x, ground(x))); break
        t += js.DT
    return traj


def check_hops(path, hops):
    data = json.load(open(path))
    main_s = pv.build(data['roads'][0]['points'], True, 1.0, mods=pv.mods_for(data, 'main'))
    for rid, hump_t, lane, h, L, block, land_dy in hops:
        rd = [r for r in data['roads'] if r['id'] == rid][0]
        xw, xl = wall_hop(data, rd, main_s, hump_t, lane)
        print(f"{rid}: wall crossed {xw:.1f} m after the hump crest, branch surface from {xl:.1f} m")
        for spd in (27.0, 30.0, 34.0):
            row = []
            for lead in (None, 0.30, 0.15, 0.06):
                tr = hop_heights(h, L, spd, lead)
                hw_ = next((yy for xx, yy in tr if xx >= xw), 0.0)
                land = tr[-1][0] if tr else 0
                clear = hw_ > block
                ok = clear and land >= xl
                row.append(f"{'none' if lead is None else lead:>4}: {'OK  ' if ok else ('wall' if not clear else 'shrt')} h{hw_:.1f} land {land:.0f}")
            print(f"   {spd:.0f} m/s  " + '   '.join(row))
