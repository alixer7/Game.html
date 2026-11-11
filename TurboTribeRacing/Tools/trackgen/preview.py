#!/usr/bin/env python3
"""v2 track preview / validation. Mirrors TrackSpline sampling (centripetal Catmull-Rom on XZ, 1 m resample)
and TrackBuilder branch anchoring. Renders a top view (zones, sides, events, obstacles, branches) and an
elevation profile, and prints corner / slope / overlap diagnostics.
usage: preview.py track.json out.png"""
import json, math, sys
import numpy as np
import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt
from matplotlib.collections import PolyCollection, LineCollection

def cr(p0, p1, p2, p3, t):
    def tj(ti, a, b):
        return ti + max(math.hypot(b[0] - a[0], b[2] - a[2]), 1e-3) ** 0.5
    t0 = 0.0; t1 = tj(t0, p0, p1); t2 = tj(t1, p1, p2); t3 = tj(t2, p2, p3)
    tt = t1 + (t2 - t1) * t
    a1 = (t1 - tt) / (t1 - t0) * p0 + (tt - t0) / (t1 - t0) * p1
    a2 = (t2 - tt) / (t2 - t1) * p1 + (tt - t1) / (t2 - t1) * p2
    a3 = (t3 - tt) / (t3 - t2) * p2 + (tt - t2) / (t3 - t2) * p3
    b1 = (t2 - tt) / (t2 - t0) * a1 + (tt - t0) / (t2 - t0) * a2
    b2 = (t3 - tt) / (t3 - t1) * a2 + (tt - t1) / (t3 - t1) * a3
    return (t2 - tt) / (t2 - t1) * b1 + (tt - t1) / (t2 - t1) * b2

class Spl:
    pass

def build(points, closed=True, step=1.0, sub=24, mods=()):
    P = np.array([[p['x'], p['y'], p['z']] for p in points], float)
    W = np.array([p.get('w', 18) for p in points], float)
    n = len(P)
    def get(k):
        if closed: return P[k % n]
        if k < 0: return P[0] * 2 - P[1]
        if k >= n: return P[n - 1] * 2 - P[n - 2]
        return P[k]
    segs = n if closed else n - 1
    dense = []; dW = []; dP = []
    for i in range(segs):
        j = (i + 1) % n if closed else i + 1
        for k in range(sub):
            t = k / sub
            dense.append(cr(get(i - 1), get(i), get(i + 1), get(i + 2), t))
            st = t * t * (3 - 2 * t)
            dW.append(W[i] + (W[j] - W[i]) * st); dP.append(i + t)
    if not closed:
        dense.append(P[n - 1]); dW.append(W[n - 1]); dP.append(n - 1)
    dense = np.array(dense); dW = np.array(dW); dP = np.array(dP)
    m = len(dense)
    nxt = np.roll(dense, -1, axis=0) if closed else np.vstack([dense[1:], dense[-1:]])
    seg = np.linalg.norm(nxt - dense, axis=1)
    if not closed: seg = seg[:-1]
    cum = np.concatenate([[0], np.cumsum(seg)])
    total = cum[-1]
    count = max(8, int(round(total / step)))
    if not closed: count += 1
    stp = total / count if closed else total / (count - 1)
    s = Spl(); s.closed = closed; s.count = count; s.step = stp; s.length = total; s.n = n
    pos = np.zeros((count, 3)); hw = np.zeros(count); par = np.zeros(count)
    jx = 0
    for i in range(count):
        dist = min(i * stp, total)
        while jx < len(seg) - 1 and cum[jx + 1] < dist: jx += 1
        f = np.clip((dist - cum[jx]) / max(cum[jx + 1] - cum[jx], 1e-5), 0, 1)
        jn = (jx + 1) % m if closed else min(jx + 1, m - 1)
        pos[i] = dense[jx] + (dense[jn] - dense[jx]) * f
        hw[i] = (dW[jx] + (dW[jn] - dW[jx]) * f) * 0.5
        pa = dP[jx]; pb = n if (closed and jn == 0) else dP[jn]
        par[i] = pa + (pb - pa) * f
    s.param = par
    for (t, h, ln, cnt) in mods:
        c = s.idx(t) if hasattr(s, 'idx') else None
    s.pos = pos; s.hw = hw
    s.wrap = (lambda i: i % count) if closed else (lambda i: min(max(i, 0), count - 1))
    s.idx = lambda p: int(np.searchsorted(par, (p % n) if closed else min(max(p, 0), n - 1)))
    for (t, h, ln, cnt) in mods:
        c = s.idx(t); L = max(2, int(round(ln / stp)))
        for rep in range(cnt):
            for k in range(L + 1):
                ii = s.wrap(c + rep * L + k - (cnt * L) // 2)
                s.pos[ii, 1] += h * (0.5 - 0.5 * math.cos(k / L * math.pi * 2))
    fw = np.array([s.pos[s.wrap(i + 1)] - s.pos[s.wrap(i - 1)] for i in range(count)])
    fw /= np.maximum(np.linalg.norm(fw, axis=1)[:, None], 1e-6)
    s.fwd = fw
    rt = np.stack([fw[:, 2], np.zeros(count), -fw[:, 0]], 1)
    rt /= np.maximum(np.linalg.norm(rt, axis=1)[:, None], 1e-6)
    s.right = rt
    # curvature (6-sample window, signed: + = right turn)
    cw = 6
    curv = np.zeros(count)
    for i in range(count):
        a = fw[s.wrap(i - cw)][[0, 2]]; b = fw[s.wrap(i + cw)][[0, 2]]
        ang = math.atan2(a[0] * b[1] - a[1] * b[0], a[0] * b[0] + a[1] * b[1])
        span = (s.wrap(i + cw) - s.wrap(i - cw)) if not closed else 2 * cw
        curv[i] = -ang / (span * stp) if span > 0 else 0
    s.curv = curv
    return s

def mods_for(data, road):
    out = []
    for e in data['events']:
        if e.get('road', 'main') != road: continue
        if e['type'] == 'bump': out.append((e['t'], e.get('h', 1.5), e.get('len', 8), 1))
        elif e['type'] == 'dip': out.append((e['t'], -abs(e.get('h', 1.5)), e.get('len', 8), 1))
        elif e['type'] == 'rumble': out.append((e['t'], e.get('h', 1.5), e.get('len', 8), e.get('count', 4)))
    return out

def in_range(data, road, typ, p):
    for r in data['ranges']:
        if r.get('road', 'main') != road or r['type'] != typ: continue
        if r['a'] <= r['b']:
            if r['a'] <= p <= r['b']: return True
        elif p >= r['a'] or p <= r['b']: return True
    return False

ZC = dict(beach='#f2d58a', jungle='#5fa04e', temple='#b8a77a', volcano='#8a3b2a', desert='#e0a35a', mine='#7b5b3c',
          mesa='#c46a3a', river='#5aa7c8', village='#c9b28f', icecave='#8fd3ff', lake='#bfe8ff', alpine='#e8eef5')

def main():
    data = json.load(open(sys.argv[1]))
    out = sys.argv[2]
    roads = data['roads']
    main_s = build(roads[0]['points'], True, 1.0, mods=mods_for(data, 'main'))
    spl = {'main': main_s}
    for rd in roads[1:]:
        ia = main_s.idx(rd['from']['t']); ib = main_s.idx(rd['to']['t'])
        def mp(i, w):
            p = main_s.pos[main_s.wrap(i)]
            return dict(x=p[0], y=p[1], z=p[2], w=w)
        w0 = rd['points'][0]['w']; w1 = rd['points'][-1]['w']
        pts = ([] if rd.get('detachStart') else [mp(ia - 12, w0), mp(ia, w0)]) + rd['points'] + ([] if rd.get('detachEnd') else [mp(ib, w1), mp(ib + 12, w1)])
        b = build(pts, False, 1.0, mods=mods_for(data, rd['id']))
        b.ia, b.ib = ia, ib
        b.hidden = rd.get('hidden', False)
        spl[rd['id']] = b
    zones = data['zones']
    def zone_at(p):
        for z in zones:
            if (z['a'] <= z['b'] and z['a'] <= p < z['b']) or (z['a'] > z['b'] and (p >= z['a'] or p < z['b'])):
                return z['style']
        return zones[0]['style'] if zones else 'beach'

    fig = plt.figure(figsize=(16, 13))
    ax = fig.add_axes([0.03, 0.27, 0.94, 0.71])
    ax2 = fig.add_axes([0.05, 0.04, 0.92, 0.19])
    ax.set_aspect('equal'); ax.set_facecolor('#2b5f86' if data['theme'] == 'beach' else '#3a3f4a')
    for name, s in spl.items():
        polys = []; cols = []
        for i in range(s.count - (0 if s.closed else 1)):
            j = s.wrap(i + 1)
            a = s.pos[i]; b = s.pos[j]
            ra = s.right[i] * s.hw[i]; rb = s.right[j] * s.hw[j]
            polys.append([(a[0] - ra[0], a[2] - ra[2]), (a[0] + ra[0], a[2] + ra[2]), (b[0] + rb[0], b[2] + rb[2]), (b[0] - rb[0], b[2] - rb[2])])
            mp_ = s.param[i] if name == 'main' else main_s.param[min(s.ia + i, main_s.count - 1)]
            c = ZC.get(zone_at(s.param[i] if name == 'main' else main_s.param[s.ia]), '#999')
            p = s.param[i]
            if in_range(data, name, 'gap', p): c = '#000000'
            elif in_range(data, name, 'ice', p): c = '#e8ffff'
            elif in_range(data, name, 'tunnel', p): c = '#555555'
            cols.append(c)
        ax.add_collection(PolyCollection(polys, facecolors=cols, edgecolors='none', alpha=0.95 if name == 'main' else 0.8, zorder=2 if name == 'main' else 3))
        # side markings: wall (dark), cliff (red), open (green dashes)
        for side in (-1, 1):
            segs = {'wall': [], 'cliff': [], 'open': [], 'low': [], 'bare': []}
            for i in range(s.count - 1):
                p = s.param[i]
                key = 'wall'
                if in_range(data, name, 'tunnel', p): key = 'wall'
                elif in_range(data, name, 'cliff', p) or in_range(data, name, 'cliffL' if side < 0 else 'cliffR', p): key = 'cliff'
                elif in_range(data, name, 'open', p) or in_range(data, name, 'openL' if side < 0 else 'openR', p): key = 'open'
                if in_range(data, name, 'low', p) or in_range(data, name, 'lowL' if side < 0 else 'lowR', p): key = 'low'
                if in_range(data, name, 'bareL' if side < 0 else 'bareR', p): key = 'bare'
                a = s.pos[i] + s.right[i] * s.hw[i] * side; b = s.pos[i + 1] + s.right[i + 1] * s.hw[i + 1] * side
                segs[key].append([(a[0], a[2]), (b[0], b[2])])
            ax.add_collection(LineCollection(segs['wall'], colors='#3b2a1a', linewidths=1.6, zorder=4))
            ax.add_collection(LineCollection(segs['cliff'], colors='#ff3030', linewidths=2.2, zorder=4))
            ax.add_collection(LineCollection(segs['open'], colors='#9cff6a', linewidths=0.8, zorder=4))
            ax.add_collection(LineCollection(segs['low'], colors='#ffd400', linewidths=2.6, zorder=4))
        ax.plot(s.pos[:, 0], s.pos[:, 2], color='white' if not getattr(s, 'hidden', False) else '#ff60ff', lw=0.4 if not getattr(s, 'hidden', False) else 1.2, ls='--', zorder=5)
        if name != 'main':
            m = s.pos[s.count // 2]
            ax.text(m[0], m[2], name + (' (SECRET)' if getattr(s, 'hidden', False) else ''), color='yellow' if not getattr(s, 'hidden', False) else '#ff9cff', fontsize=9, zorder=9, ha='center')
    # events / obstacles
    sym = dict(pad=('>', '#ffe600'), ramp=('^', '#ff8c00'), crates=('s', '#c08040'), bump=('o', '#ffffff'), dip=('v', '#88aaff'),
               rumble=('|', '#ffffff'), mud=('o', '#5a3a1a'), hump=('D', '#ff4fd8'), curtain=('P', '#40ff90'))
    for e in data['events']:
        s = spl[e.get('road', 'main')]; i = s.idx(e['t'])
        lane = e.get('lane', 0)
        if e['type'] == 'hump' and abs(lane) >= 0.99: lane = 0.5 * (1 if lane > 0 else -1)
        p = s.pos[i] + s.right[i] * s.hw[i] * lane
        mk, c = sym.get(e['type'], ('x', 'w'))
        ax.scatter([p[0]], [p[2]], marker=mk, c=c, s=40 if e['type'] != 'mud' else 160, zorder=8, edgecolors='k', linewidths=0.4)
    for o in data['obstacles']:
        s = spl[o.get('road', 'main')]; i = s.idx(o['t'])
        p = s.pos[i] + s.right[i] * s.hw[i] * o.get('lane', 0)
        ax.scatter([p[0]], [p[2]], marker='*', c='#ff00ff', s=120, zorder=9, edgecolors='k')
        ax.text(p[0] + 4, p[2] + 4, o['type'][:4], color='#ffb0ff', fontsize=7, zorder=9)
    # start + distance ticks
    for d in range(0, int(main_s.length), 100):
        i = int(d / main_s.step); p = main_s.pos[i]
        ax.text(p[0], p[2], str(d), color='white', fontsize=7, zorder=10, ha='center', va='center',
                bbox=dict(boxstyle='round,pad=0.1', fc='#00000088', ec='none'))
    xs = np.concatenate([s.pos[:, 0] for s in spl.values()]); zs = np.concatenate([s.pos[:, 2] for s in spl.values()])
    ax.set_xlim(xs.min() - 40, xs.max() + 40); ax.set_ylim(zs.min() - 40, zs.max() + 40)
    if len(sys.argv) > 3:      # zoom: x0,x1,z0,z1
        x0, x1, z0, z1 = [float(v) for v in sys.argv[3].split(',')]
        ax.set_xlim(x0, x1); ax.set_ylim(z0, z1)
    ax.set_title(f"{data['name']}  main {main_s.length:.0f} m", color='k')
    # elevation
    dd = np.arange(main_s.count) * main_s.step
    ax2.plot(dd, main_s.pos[:, 1], color='k', lw=1.2, label='main')
    for name, s in spl.items():
        if name == 'main': continue
        d0 = s.ia * main_s.step - 12
        ax2.plot(d0 + np.arange(s.count) * s.step, s.pos[:, 1], lw=1, label=name)
    for i in range(main_s.count):
        if in_range(data, 'main', 'gap', main_s.param[i]): ax2.axvspan(dd[i], dd[i] + 1, color='k', alpha=0.25, lw=0)
    ax2.axhline(data.get('waterLevel', 0), color='#2b5f86', lw=0.8)
    ax2.legend(fontsize=7, loc='upper right'); ax2.grid(alpha=0.3); ax2.set_xlim(0, main_s.length)
    fig.savefig(out, dpi=70)

    # ---------------- diagnostics
    print(f"main {main_s.length:.0f} m; widths {2*main_s.hw.min():.0f}-{2*main_s.hw.max():.0f} m; "
          f"tunnel {sum(1 for i in range(main_s.count) if in_range(data, 'main', 'tunnel', main_s.param[i])) * main_s.step:.0f} m indoor")
    for name, s in spl.items():
        slope = np.diff(s.pos[:, 1]) / s.step
        print(f"  {name:12s} len {s.length:6.0f}  max climb {slope.max()*100:5.1f}%  max drop {slope.min()*100:6.1f}%  "
              f"min radius {1/max(np.abs(s.curv).max(),1e-4):5.1f} m  y {s.pos[:,1].min():.1f}..{s.pos[:,1].max():.1f}")
    # corner list (main)
    c = main_s.curv; i = 0; corners = []
    N = main_s.count
    while i < N:
        if abs(c[i]) > 1 / 200:
            j = i; tot = 0
            while j < N and abs(c[j]) > 1 / 200 and np.sign(c[j]) == np.sign(c[i]): tot += c[j] * main_s.step; j += 1
            corners.append((i, j, math.degrees(tot), 1 / np.abs(c[i:j]).max()))
            i = j
        else: i += 1
    print('  corners: ' + '  '.join(f"{a}m:{ang:+.0f}°/r{r:.0f}" for a, b, ang, r in corners if abs(ang) > 15))
    # overlap check: samples of any roads closer than half widths sum with |dy| < 5 (excluding neighbours / junctions)
    allp = []
    for name, s in spl.items():
        for i in range(0, s.count, 3): allp.append((name, i, s.pos[i], s.hw[i]))
    warn = 0
    for a in range(len(allp)):
        na, ia_, pa, ha = allp[a]
        for b in range(a + 1, len(allp)):
            nb, ib_, pb, hb = allp[b]
            dxz = math.hypot(pa[0] - pb[0], pa[2] - pb[2])
            if dxz > ha + hb + 6: continue
            if na == nb:
                sp = spl[na]
                gap = abs(ia_ - ib_); gap = min(gap, sp.count - gap) if sp.closed else gap
                if gap * sp.step < 3 * (ha + hb) + 30: continue
            else:
                # junction neighbourhood: branch samples near either end legitimately overlap
                near = False
                for nm, ii in ((na, ia_), (nb, ib_)):
                    if nm != 'main':
                        sb = spl[nm]
                        if ii < 70 or ii > sb.count - 70: near = True
                if near: continue
            dy = abs(pa[1] - pb[1])
            if dy < 6.5:
                warn += 1
                if warn < 12: print(f"  OVERLAP {na}@{ia_} vs {nb}@{ib_}: dxz {dxz:.1f} dy {dy:.1f}")
    print(f"  overlap warnings: {warn}")

if __name__ == '__main__':
    main()
