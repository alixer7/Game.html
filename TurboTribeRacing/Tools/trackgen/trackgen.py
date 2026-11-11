#!/usr/bin/env python3
"""Turbo Tribe track authoring DSL (v2 schema).

A track is written as a 'turtle' sequence of segments (straights + constant-radius arcs) with
per-segment elevation targets/profiles and widths. Two 'free' straights are solved automatically so
the loop closes exactly. Markers name points along the lap; events, ranges, zones, obstacles and
branch roads are placed relative to markers in metres, then converted to control-point params
(the unit TrackData uses).

Conventions (Unity): x right, z forward, y up. heading 0 = +z, positive turn angle = RIGHT turn.
"""
import json, math
import numpy as np

# ----------------------------------------------------------------------------- elevation profiles
def _smooth(u): return u * u * (3 - 2 * u)

PROFILES = {
    'smooth': _smooth,                                  # gradual: eases in and out
    'linear': lambda u: u,
    'steep': lambda u: _smooth(_smooth(u)),             # short sharp change in the middle
    'early': lambda u: _smooth(min(1.0, u / 0.45)),     # changes in the first 45% then levels
    'late': lambda u: _smooth(max(0.0, (u - 0.55) / 0.45)),  # level, then changes in the last 45%
    'crest': lambda u: _smooth(min(1.0, u / 0.3)),      # quick change at the start (kicks off a crest/lip)
}


class Seg:
    def __init__(self, kind, length=0.0, angle=0.0, radius=0.0, y=None, prof='smooth', w=None, bank=0.0, sp=None, free=False):
        self.kind, self.length, self.angle, self.radius = kind, length, angle, radius
        self.y, self.prof, self.w, self.bank, self.sp, self.free = y, prof, w, bank, sp, free

    def arc_len(self):
        return self.length if self.kind == 'S' else abs(math.radians(self.angle)) * self.radius


def _dir(h):
    r = math.radians(h)
    return np.array([math.sin(r), math.cos(r)])


class Track:
    def __init__(self, id, name, theme, subtitle='', difficulty=1, water=-2.0, spacing=6.0):
        self.meta = dict(id=id, name=name, theme=theme, subtitle=subtitle, difficulty=difficulty, waterLevel=water)
        self.segs = []          # list of Seg or ('mark', name)
        self.spacing = spacing
        self.x0 = np.array([0.0, 0.0]); self.h0 = 0.0; self.y0 = 0.0; self.w0 = 22.0
        self.zones, self.ranges, self.events, self.obstacles, self.branches = [], [], [], [], []
        self.marks = {}
        self.vars = {}

    # ---------------------------------------------------------------- authoring
    def start(self, x=0.0, z=0.0, h=0.0, y=0.0, w=22.0):
        self.x0 = np.array([x, z], float); self.h0 = h; self.y0 = y; self.w0 = w
        return self

    def S(self, length, y=None, prof='smooth', w=None, bank=0.0, sp=None):
        self.segs.append(Seg('S', length=length, y=y, prof=prof, w=w, bank=bank, sp=sp)); return self

    def T(self, angle, radius, y=None, prof='smooth', w=None, bank=0.0, sp=None):
        self.segs.append(Seg('T', angle=angle, radius=radius, y=y, prof=prof, w=w, bank=bank, sp=sp)); return self

    def FREE(self, y=None, prof='smooth', w=None):
        self.segs.append(Seg('S', length=0.0, y=y, prof=prof, w=w, free=True)); return self

    def V(self, name, y=None, prof='smooth', w=None, bank=0.0):
        """variable-length straight, solved by constrain()."""
        sg = Seg('S', length=0.0, y=y, prof=prof, w=w, bank=bank); sg.var = name
        self.segs.append(sg); return self

    def constrain(self, a, b, dx, dz, vars):
        """solve two V() straights so that mark b - mark a == (dx, dz)."""
        self.constraints = getattr(self, 'constraints', []) + [(a, b, dx, dz, vars)]
        return self

    def M(self, name):
        self.segs.append(('mark', name)); return self

    # ---------------------------------------------------------------- geometry
    def _walk(self, lengths=None, emit=False):
        p = self.x0.copy(); h = self.h0; y = self.y0; w = self.w0; d = 0.0
        pts = []; marks = {}; fi = 0
        for sg in self.segs:
            if isinstance(sg, tuple):
                marks[sg[1]] = dict(d=d, p=p.copy(), h=h, y=y, w=w); continue
            L = sg.arc_len()
            if getattr(sg, 'var', None):
                L = self.vars.get(sg.var, 0.0)
            if sg.free:
                L = lengths[fi] if lengths is not None else 0.0; fi += 1
            y1 = y if sg.y is None else sg.y
            w1 = w if sg.w is None else sg.w
            prof = PROFILES[sg.prof]
            sp = sg.sp or self.spacing
            n = max(1, int(math.ceil(L / sp - 1e-6))) if L > 0 else 0
            for k in range(n):
                u = k / n
                if sg.kind == 'S':
                    q = p + _dir(h) * (L * u); hh = h
                else:
                    a = sg.angle * u
                    # arc: centre to the right for positive angles
                    c = p + _dir(h + (90 if sg.angle > 0 else -90)) * sg.radius
                    hh = h + a
                    q = c + _dir(hh - (90 if sg.angle > 0 else -90)) * sg.radius
                if emit:
                    pts.append(dict(x=q[0], z=q[1], y=y + (y1 - y) * prof(u), w=w + (w1 - w) * _smooth(u), bank=sg.bank, d=d + L * u, h=hh))
            # advance
            if sg.kind == 'S':
                p = p + _dir(h) * L
            else:
                c = p + _dir(h + (90 if sg.angle > 0 else -90)) * sg.radius
                h = h + sg.angle
                p = c + _dir(h - (90 if sg.angle > 0 else -90)) * sg.radius
            d += L; y = y1; w = w1
        return p, h, y, d, pts, marks

    def solve_vars(self):
        self.vars = {}
        for (a, b, dx, dz, vs) in getattr(self, 'constraints', []):
            for v in vs: self.vars[v] = 0.0
            _, _, _, _, _, mk = self._walk([0.0, 0.0])
            E = (mk[b]['p'] - mk[a]['p']) - np.array([dx, dz])
            # heading at each variable straight
            h = self.h0; heads = {}
            for sg in self.segs:
                if isinstance(sg, tuple): continue
                if getattr(sg, 'var', None) in vs: heads[sg.var] = h
                if sg.kind == 'T': h += sg.angle
            A = np.column_stack([_dir(heads[vs[0]]), _dir(heads[vs[1]])])
            L = np.linalg.solve(A, -E)
            for v, l in zip(vs, L): self.vars[v] = float(l)
            print(f"constraint {a}->{b}: " + ", ".join(f"{v}={l:.1f} m" for v, l in zip(vs, L)))
            if min(L) < 5: print('WARNING: variable straight below 5 m')

    def build(self):
        self.solve_vars()
        frees = [s for s in self.segs if isinstance(s, Seg) and s.free]
        assert len(frees) == 2, 'need exactly two FREE straights to close the loop'
        # headings at the free segments
        heads = []; h = self.h0
        for sg in self.segs:
            if isinstance(sg, tuple): continue
            if sg.free: heads.append(h)
            if sg.kind == 'T': h += sg.angle
        turn_total = h - self.h0
        assert min(abs(abs(turn_total) - 360), abs(turn_total), abs(abs(turn_total) - 720)) < 1e-6, f'total turning must be +-360 (0 figure-8, 720 with a loop), got {turn_total}'
        end0, _, yend, _, _, _ = self._walk([0.0, 0.0])
        E = end0 - self.x0
        A = np.column_stack([_dir(heads[0]), _dir(heads[1])])
        L = np.linalg.solve(A, -E)
        self.free_lengths = L
        if min(L) < 5:
            print(f'WARNING: free straights solved to {L[0]:.1f} / {L[1]:.1f} m (need >= 5)')
        end, _, yend, total, pts, marks = self._walk(list(L), emit=True)
        assert np.linalg.norm(end - self.x0) < 1e-6
        if abs(yend - self.y0) > 1e-6:
            print(f'WARNING: loop height mismatch {yend - self.y0:.2f} m')
        self.total = total; self.pts = pts; self.marks = marks
        self.d_arr = np.array([p['d'] for p in pts])
        return self

    # distance helpers ------------------------------------------------
    def D(self, at):
        """at: float metres | 'mark' | ('mark', offset)"""
        if isinstance(at, (int, float)): return float(at) % self.total
        if isinstance(at, str): return self.marks[at]['d'] % self.total
        return (self.marks[at[0]]['d'] + at[1]) % self.total

    def P(self, at):
        d = self.D(at)
        n = len(self.pts)
        dd = np.append(self.d_arr, self.total)
        return float(np.interp(d, dd, np.arange(n + 1)))

    def frame(self, at):
        """position, heading, y, width at a main distance (from the turtle samples)."""
        d = self.D(at)
        i = int(np.searchsorted(self.d_arr, d, side='right') - 1)
        a = self.pts[i]; b = self.pts[(i + 1) % len(self.pts)]
        db = b['d'] if i + 1 < len(self.pts) else self.total
        f = (d - a['d']) / max(db - a['d'], 1e-6)
        x = a['x'] + (b['x'] - a['x']) * f; z = a['z'] + (b['z'] - a['z']) * f
        y = a['y'] + (b['y'] - a['y']) * f; w = a['w'] + (b['w'] - a['w']) * f
        hb = b['h']
        while hb - a['h'] > 180: hb -= 360
        while hb - a['h'] < -180: hb += 360
        return np.array([x, z]), a['h'] + (hb - a['h']) * f, y, w

    # ---------------------------------------------------------------- content
    def zone(self, a, b, style):
        self.zones.append(dict(a=a, b=b, style=style)); return self

    def rng(self, type, a, b, road='main'):
        self.ranges.append(dict(road=road, type=type, a=a, b=b)); return self

    def ev(self, type, at, road='main', **kw):
        if type == 'hump': kw.setdefault('width', 0.0)      # 0 = half the road (the C# default would be 6 m)
        self.events.append(dict(road=road, type=type, at=at, **kw)); return self

    def ob(self, type, at, road='main', **kw):
        self.obstacles.append(dict(road=road, type=type, at=at, **kw)); return self

    def lm(self, type, at=None, along=0.0, lat=0.0, pos=None, r=20.0, y=None, yaw=0.0, dy=0.0):
        """landmark at a main frame offset (along/lat metres) or absolute pos (x, z). y=None -> auto;
        dy -> y relative to the main road height at 'at'."""
        self.landmarks = getattr(self, 'landmarks', []) + [dict(type=type, at=at, along=along, lat=lat, pos=pos, r=r, y=y, yaw=yaw, dy=dy)]
        return self

    def branch(self, id, kind, frm, to, via, w=14.0, w_end=None, sp=6.0, flat=22.0, hidden=False, detach_start=False, detach_end=False):
        """via: list of dicts {rel:(mark_or_at, along, lateral)} or {pos:(x,z)}, optional y, w, h (heading).
        hidden: secret shortcut (no minimap line / signs). detach_start/_end: that end does NOT overlap the main road
        (the branch begins beside main beyond a low wall / ends in the air) - the first/last 'via' key is the end."""
        self.branches.append(dict(id=id, kind=kind, frm=frm, to=to, via=via, w=w, w_end=w_end if w_end else w, sp=sp, flat=flat,
                                  hidden=hidden, detach_start=detach_start, detach_end=detach_end))
        return self

    # ---------------------------------------------------------------- branches
    def _rel(self, spec):
        at, along, lat = spec
        p, h, y, w = self.frame(at)
        right = _dir(h + 90)
        return p + _dir(h) * along + right * lat, y

    def _build_branch(self, b):
        pa, ha, ya, wa = self.frame(b['frm'])
        pb, hb, yb, wb = self.frame(b['to'])
        keys = [] if b['detach_start'] else [dict(p=pa, y=ya, w=b['w'], h=ha)]
        for v in b['via']:
            if 'rel' in v:
                p, ym = self._rel(v['rel'])
            else:
                p = np.array(v['pos'], float); ym = None
            h = v.get('h', None)
            if h is None and 'rel' in v and v.get('follow', False):
                h = self.frame(v['rel'][0])[1]
            keys.append(dict(p=p, y=v.get('y', None), w=v.get('w', None), h=h))
        if b['detach_start']:
            if keys[0]['w'] is None: keys[0]['w'] = b['w']
            if keys[0]['h'] is None: keys[0]['h'] = ha
        if b['detach_end']:
            if keys[-1]['w'] is None: keys[-1]['w'] = b['w_end']
            if keys[-1]['h'] is None: keys[-1]['h'] = hb
        else:
            keys.append(dict(p=pb, y=yb, w=b['w_end'], h=hb))
        # tangents (Catmull-Rom for interior keys)
        n = len(keys)
        for i in range(n):
            k = keys[i]
            if k['h'] is not None:
                k['t'] = _dir(k['h'])
            else:
                dv = keys[i + 1]['p'] - keys[i - 1]['p']
                k['t'] = dv / np.linalg.norm(dv)
        # dense hermite sampling
        dense = []
        for i in range(n - 1):
            a, c = keys[i], keys[i + 1]
            L = np.linalg.norm(c['p'] - a['p'])
            m0 = a['t'] * L; m1 = c['t'] * L
            for k in range(200):
                t = k / 200
                h00 = 2 * t ** 3 - 3 * t ** 2 + 1; h10 = t ** 3 - 2 * t ** 2 + t; h01 = -2 * t ** 3 + 3 * t ** 2; h11 = t ** 3 - t ** 2
                dense.append((a['p'] * h00 + m0 * h10 + c['p'] * h01 + m1 * h11, i + t))
        dense.append((keys[-1]['p'], n - 1.0))
        P = np.array([q[0] for q in dense]); KP = np.array([q[1] for q in dense])
        seg = np.linalg.norm(np.diff(P, axis=0), axis=1)
        cum = np.concatenate([[0], np.cumsum(seg)])
        total = cum[-1]
        # key distances
        kd = [float(np.interp(i, KP, cum)) for i in range(n)]
        # y + w interpolation along distance (keys with None are skipped)
        yk = [(kd[i], keys[i]['y']) for i in range(n) if keys[i]['y'] is not None]
        wk = [(kd[i], keys[i]['w']) for i in range(n) if keys[i]['w'] is not None]

        def interp_keys(kk, d):
            for j in range(len(kk) - 1):
                if kk[j][0] <= d <= kk[j + 1][0]:
                    u = (d - kk[j][0]) / max(kk[j + 1][0] - kk[j][0], 1e-6)
                    return kk[j][1] + (kk[j + 1][1] - kk[j][1]) * _smooth(u)
            return kk[-1][1] if d > kk[-1][0] else kk[0][1]
        cnt = max(2, int(round(total / b['sp'])))
        pts = []
        k0 = 0 if b['detach_start'] else 1
        k1 = cnt if b['detach_end'] else cnt - 1
        for k in range(k0, k1 + 1):
            d = total * k / cnt
            q = np.array([np.interp(d, cum, P[:, 0]), np.interp(d, cum, P[:, 1])])
            y = interp_keys(yk, d)
            # near ATTACHED junctions the branch must stay level with the main road it overlaps
            e = min(d if not b['detach_start'] else 1e9, (total - d) if not b['detach_end'] else 1e9)
            wmain = 1.0 - _smooth(min(1.0, max(0.0, (e - b.get('flat', 22.0)) / 18.0)))
            if wmain > 0:
                mp = np.array([[p_['x'], p_['z']] for p_ in self.pts])
                j = int(np.argmin(np.sum((mp - q) ** 2, axis=1)))
                y = y + (self.pts[j]['y'] - y) * wmain
            pts.append(dict(x=q[0], z=q[1], y=y, w=interp_keys(wk, d), bank=0.0, d=d))
        b['pts'] = pts; b['total'] = total
        arr = ([] if b['detach_start'] else [0.0]) + [p['d'] for p in pts] + ([] if b['detach_end'] else [total])
        b['d_arr'] = np.array(arr)
        b['p_off'] = 0.0 if b['detach_start'] else 1.0
        return b

    def BP(self, b, d):
        """branch-local param (C# control-point units) for a distance along the branch (0 = its start)."""
        if isinstance(d, str) and d.startswith('f'): d = float(d[1:]) * b['total']
        arr = b['d_arr']
        return b['p_off'] + float(np.interp(d, arr, np.arange(len(arr))))

    def edge_clearance(self, q, skip=None, y=None, dy=4.0):
        """metres from point q (x, z) to the nearest main-road outer wall face (negative = on the road).
        With y: main samples more than dy metres above / below are ignored (a crossing on another level)."""
        P = np.array([[p['x'], p['z']] for p in self.pts]); W = np.array([p['w'] for p in self.pts]) * 0.5
        Y = np.array([p['y'] for p in self.pts])
        # densify (turtle samples are ~6 m apart)
        Q = []; WW = []; YY = []
        for i in range(len(P)):
            j = (i + 1) % len(P)
            for u in np.linspace(0, 1, 6, endpoint=False):
                Q.append(P[i] + (P[j] - P[i]) * u); WW.append(W[i] + (W[j] - W[i]) * u); YY.append(Y[i] + (Y[j] - Y[i]) * u)
        Q = np.array(Q); WW = np.array(WW); YY = np.array(YY)
        d = np.sqrt(np.sum((Q - np.asarray(q)[None, :]) ** 2, axis=1)) - WW - 0.7
        if y is not None:
            d = np.where(np.abs(YY - y) > dy, 1e9, d)
        return float(d.min())

    def hop_line(self, at, lat, ahead):
        """point 'ahead' metres along the straight line leaving main at 'at' with lateral offset 'lat' (heading = main's)."""
        p, h, y, w = self.frame(at)
        return p + _dir(h + 90) * lat + _dir(h) * ahead, h

    def clear_from(self, bid, margin=1.5, start=0.0):
        """distance along branch 'bid' (built on demand) from which its whole width stays clear of the main road
        (edge to main's outer wall face >= margin) - where a gap / pit may begin."""
        if not hasattr(self, 'pts'): self.build()
        b = next(x for x in self.branches if x['id'] == bid)
        if 'pts' not in b: self._build_branch(b)
        first = None
        for p in b['pts']:
            if p['d'] < start: continue
            ok = self.edge_clearance(np.array([p['x'], p['z']]), y=p['y']) - p['w'] * 0.5 >= margin
            if ok and first is None: first = p['d']
            if not ok: first = None
            if first is not None and p['d'] - first > 25: break
        return first, b['total']

    def curtain_spot(self, bid, width, lo=0.3, hi=0.95, margin=1.2):
        """first fraction along branch 'bid' where a curtain of 'width' has both posts (at +-(width/2 + 1.2) m)
        clear of the main road surface + walls - or None."""
        b = next(x for x in self.branches if x['id'] == bid)
        if 'pts' not in b: self._build_branch(b)
        pts = b['pts']
        for k in range(1, len(pts) - 1):
            f = pts[k]['d'] / b['total']
            if f < lo or f > hi: continue
            a, c = pts[k - 1], pts[k + 1]
            tg = np.array([c['x'] - a['x'], c['z'] - a['z']]); tg /= np.linalg.norm(tg)
            rt = np.array([tg[1], -tg[0]])
            q = np.array([pts[k]['x'], pts[k]['z']])
            if all(self.edge_clearance(q + rt * sd * (width * 0.5 + 1.2)) >= margin for sd in (-1, 1)):
                return round(f, 3)
        return None

    def saving(self, b):
        """metres of main road skipped minus branch length (positive = a real shortcut)."""
        span = (self.D(b['to']) - self.D(b['frm'])) % self.total
        return span - b['total']

    # ---------------------------------------------------------------- export
    def export(self, path):
        self.build()
        for b in self.branches: self._build_branch(b)
        bmap = {b['id']: b for b in self.branches}

        def par(road, at):
            return self.P(at) if road == 'main' else self.BP(bmap[road], at)
        r2 = lambda v: round(float(v), 2)
        roads = [dict(id='main', closed=True, points=[dict(x=r2(p['x']), y=r2(p['y']), z=r2(p['z']), w=r2(p['w']), bank=r2(p['bank'])) for p in self.pts])]
        for b in self.branches:
            roads.append(dict(id=b['id'], closed=False, kind=b['kind'], hidden=b['hidden'], detachStart=b['detach_start'], detachEnd=b['detach_end'],
                              points=[dict(x=r2(p['x']), y=r2(p['y']), z=r2(p['z']), w=r2(p['w']), bank=0) for p in b['pts']],
                              **{'from': dict(road='main', t=r2(self.P(b['frm']))), 'to': dict(road='main', t=r2(self.P(b['to'])))}))
        zones = [dict(a=r2(self.P(z['a'])), b=r2(self.P(z['b'])), style=z['style']) for z in self.zones]
        ranges = [dict(road=r['road'], type=r['type'], a=r2(par(r['road'], r['a'])), b=r2(par(r['road'], r['b']))) for r in self.ranges]
        events = []
        for e in self.events:
            e2 = {k: v for k, v in e.items() if k != 'at'}; e2['t'] = r2(par(e['road'], e['at'])); events.append(e2)
        obstacles = []
        for o in self.obstacles:
            o2 = {k: v for k, v in o.items() if k != 'at'}; o2['t'] = r2(par(o['road'], o['at'])); obstacles.append(o2)
        lms = []
        for l in getattr(self, 'landmarks', []):
            if l['pos'] is not None: x, z = l['pos']; yb = None
            else:
                (x, z), yb = self._rel((l['at'], l['along'], l['lat']))
            y = l['y'] if l['y'] is not None else (yb + l['dy'] if (yb is not None and l['dy'] != 0.0) else -999.0)
            lms.append(dict(type=l['type'], x=r2(x), z=r2(z), r=r2(l['r']), y=r2(y), yaw=r2(l['yaw'])))
        data = dict(self.meta, roads=roads, zones=zones, ranges=ranges, events=events, obstacles=obstacles, landmarks=lms)
        with open(path, 'w') as f: json.dump(data, f, indent=1)
        print(f"{self.meta['id']}: main {self.total:.0f} m, {len(self.pts)} pts, free straights {self.free_lengths[0]:.1f}/{self.free_lengths[1]:.1f} m, "
              f"branches " + ", ".join(f"{b['id']}{'*' if b['hidden'] else ''} {b['total']:.0f} m (saves {self.saving(b):.0f} m)" for b in self.branches))
        return data


def sketch(track, png, free=(60.0, 60.0)):
    """Plot the open turtle path (before closure) with marks + headings, for layout iteration."""
    import matplotlib
    matplotlib.use('Agg')
    import matplotlib.pyplot as plt
    track.solve_vars()
    end, h, y, d, pts, marks = track._walk(list(free), emit=True)
    turn = h - track.h0
    fig, ax = plt.subplots(figsize=(11, 11))
    xs = [p['x'] for p in pts]; zs = [p['z'] for p in pts]
    sc = ax.scatter(xs, zs, c=[p['y'] for p in pts], s=[p['w'] * 1.2 for p in pts], cmap='terrain')
    plt.colorbar(sc, ax=ax, shrink=0.6)
    for k, m in marks.items():
        ax.annotate(f"{k} ({m['h'] % 360:.0f}°)", (m['p'][0], m['p'][1]), fontsize=8)
    ax.plot([track.x0[0], end[0]], [track.x0[1], end[1]], 'r--')
    ax.set_aspect('equal'); ax.grid(alpha=0.3)
    ax.set_title(f"turn {turn:.0f}  open end gap {np.linalg.norm(end - track.x0):.0f} m  length {d:.0f}")
    fig.savefig(png, dpi=60)
    print(f"sketch: turn {turn:.0f}, end {end}, length {d:.0f}")
