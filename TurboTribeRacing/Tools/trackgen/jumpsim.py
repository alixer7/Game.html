#!/usr/bin/env python3
"""2-D model of KartController's vertical physics (v0.3): ground snap, takeoff predictor, natural crest launch,
timed pre-takeoff 'lip jump', hang-time turbo. Used to tune constants and size shortcut jumps.
Mirrors the C# constants - keep them in sync.   usage: python3 jumpsim.py"""
import math

G = 31.0; FALL = 1.2; HOP = 4.6
LIP_WINDOW = 0.32; LIP_BONUS = 6.6; LIP_MIN_SEP = 0.35; NATURAL_SEP = 0.5
PROBE_DT = 0.045; PROBE_N = 8; DT = 1 / 90


def predict(x, y, v, ground, snap=0.6):
    """'glued' predictor (mirrors KartController.PredictTakeoff): probe the ground ahead every v*PROBE_DT metres,
    find the first node where the road falls away faster than gravity can bend the kart's path (or an edge / gap),
    then measure how far the road drops below that launch arc. returns (seconds to takeoff or -1, separation)."""
    d = max(0.8, v * PROBE_DT)
    ys = []
    for k in range(PROBE_N + 3):
        g = ground(x + k * d)
        ys.append(None if g is None else g)
    ys[0] = y
    for k in range(1, PROBE_N + 1):
        if ys[k] is None or ys[k - 1] is None: 
            if ys[k - 1] is None: return -1.0, 0.0
            k0 = k - 1; m0 = (ys[k0] - ys[k0 - 1]) / d if k0 > 0 else 0.0
            return k0 * d / v, 9.0
        m_prev = (ys[k] - ys[k - 1]) / d
        if k + 1 >= len(ys) or ys[k + 1] is None:
            return k * d / v, 9.0
        m_next = (ys[k + 1] - ys[k]) / d
        edge = ys[k + 1] < ys[k] + m_prev * d - snap
        if v * v * (m_prev - m_next) / d > G or edge:
            best = 0.0
            for j in range(k + 1, len(ys)):
                tt = (j - k) * d / v
                arc = ys[k] + m_prev * (j - k) * d - 0.5 * G * tt * tt
                gy = ys[j] if ys[j] is not None else arc - 9.0
                if arc - gy < -0.05: break        # road comes back up to the arc: a kink, not a lip
                best = max(best, arc - gy)
            if best >= LIP_MIN_SEP: return k * d / v, best
    return -1.0, 0.0


def slope(ground, x):
    """slope under the kart (backward difference: at a kicker lip the kart still sits on the ramp face)."""
    a, b = ground(x - 0.6), ground(x)
    if a is None or b is None: return 0.0
    return (b - a) / 0.6


def run(ground, speed=30.0, press_time=None, x0=-40.0, tmax=4.0):
    """press_time: absolute sim time to press hop (None = never). returns dict incl. 'launch_t' (takeoff time)."""
    x = x0; y = ground(x); v = speed; grounded = True
    vx = v; vy = 0.0; t = 0.0; air = 0.0; maxair = 0.0; loaded = False; load_t = 0.0; q_out = None
    takeoff_x = None; launch_t = None; maxh = -99; land_x = None; nosnap = 0.0; fell = False; pressed = False
    while t < tmax:
        if grounded:
            s = slope(ground, x); n = math.hypot(1, s)
            vx, vy = v / n, v * s / n
            tin, sep = predict(x, y, v, ground)
            # precise trigger: is the road falling away from the kart's own arc right now? (one ray, every sub-step)
            tau = 2 * DT
            gl = ground(x + vx * tau)
            lifting = gl is None or (y + vy * tau - 0.5 * G * tau * tau) - gl > 0.01
            imminent = 0 <= tin <= 0.1 and lifting
            if press_time is not None and not pressed and t >= press_time:
                pressed = True
                if 0 <= tin <= LIP_WINDOW: loaded = True; load_t = 0.0
                else:                              # ordinary hop
                    vy += HOP; grounded = False; nosnap = 0.12; takeoff_x = x; launch_t = t; q_out = -1
            if grounded and loaded:
                load_t += DT
                if imminent or load_t > LIP_WINDOW + 0.15:
                    q = max(0.0, 1 - load_t / LIP_WINDOW) if imminent else 0.0
                    up = HOP + LIP_BONUS * q * q
                    vy += up                       # straight up (world): no speed lost on a launch
                    grounded = False; nosnap = 0.15; loaded = False; q_out = q; takeoff_x = x; launch_t = t
            elif grounded and imminent and sep >= NATURAL_SEP:
                grounded = False; nosnap = 0.08; takeoff_x = x; launch_t = t
        if grounded:
            x += vx * DT; y += vy * DT
            g = ground(x)
            snap = 0.42 + 0.006 * v
            if g is None or y - g > snap or y - g < -1.0:
                grounded = False
                if takeoff_x is None: takeoff_x = x; launch_t = t
                if loaded:                         # left the lip before the trigger: launch now
                    q = max(0.0, 1 - load_t / LIP_WINDOW)
                    up = HOP + LIP_BONUS * q * q
                    vy += up; loaded = False; q_out = q; nosnap = 0.15
            else:
                y = g
        else:
            nosnap -= DT
            vy -= G * (FALL if vy < 0 else 1.0) * DT
            x += vx * DT; y += vy * DT; air += DT
            g = ground(x)
            maxh = max(maxh, y - (g if g is not None else y))
            if g is not None and y <= g and nosnap <= 0 and vy <= 0.5:
                y = g; grounded = True; maxair = max(maxair, air); land_x = x; air = 0.0
                if maxair > 0.05: break
            if g is None and y < -15: fell = True; break
        t += DT
    return dict(air=maxair, q=q_out, takeoff=takeoff_x, land=land_x, maxh=maxh, fell=fell, launch_t=launch_t)


def j_slope(g, x):
    return slope(g, x)


def timed(ground, speed, lead):
    """press 'lead' seconds before the takeoff that happens with no input (or the predicted crest)."""
    base = run(ground, speed)
    t0 = base['launch_t']
    if t0 is None:
        # no natural takeoff: find when the predictor first reports an imminent takeoff
        x = -40.0; t = 0.0
        while t < 4.0:
            tin, sep = predict(x, ground(x), speed, ground)
            gl = ground(x + speed * 2 * DT)
            if 0 <= tin <= 0.1 and (gl is None or ground(x) + j_slope(ground, x) * speed * 2 * DT - 0.5 * G * (2 * DT) ** 2 - gl > 0.01): t0 = t; break
            x += speed * DT; t += DT
    if t0 is None: return None
    return run(ground, speed, t0 - lead)


# ---------------------------------------------------------------- profiles (x metres along the road)
def bump(h, L, c=0.0):
    def f(x):
        u = (x - c) / L + 0.5
        return h * (0.5 - 0.5 * math.cos(2 * math.pi * u)) if 0 <= u <= 1 else 0.0
    return f

def kicker(h, L):
    def f(x):
        if -L <= x <= 0: return h * (1 - math.cos((x + L) / L * math.pi / 2))
        return 0.0
    return f

def hump(h, L):
    """v0.3 half-road hump: steepening front (kicker-like) to a crest at 62 %, rounded back."""
    def f(x):
        u = x / L
        if u < 0 or u > 1: return 0.0
        if u < 0.62: return h * (1 - math.cos(u / 0.62 * math.pi / 2))
        w = (u - 0.62) / 0.38
        return h * (0.5 + 0.5 * math.cos(w * math.pi))
    return f

def rumble(h, L, n):
    def f(x):
        u = x / L
        if 0 <= u <= n: return h * (0.5 - 0.5 * math.cos(2 * math.pi * u))
        return 0.0
    return f

def gapf(base, a, b):
    def f(x):
        if a <= x <= b: return None
        return base(x)
    return f

def flat(x): return 0.0

def ledge(drop, at=0.0, sharp=6.0):
    def f(x):
        if x < at: return 0.0
        return -drop * min(1.0, (x - at) / sharp) ** 2 if x - at < sharp else -drop
    return f


if __name__ == '__main__':
    cases = [('rumble 0.15/3 x10', rumble(0.15, 3, 10)), ('roots bump 0.55/7', bump(0.55, 7)),
             ('crest bump 1.0/14', bump(1.0, 14)), ('crest bump 1.25/16', bump(1.25, 16)),
             ('kicker 1.1/7', kicker(1.1, 7)), ('kicker 1.4/8', kicker(1.4, 8)),
             ('hump 1.2/11', hump(1.2, 11)), ('hump 1.5/13', hump(1.5, 13)), ('ledge 6 m', ledge(6))]
    for spd in (28.0, 34.0):
        print(f'---- speed {spd} m/s   (air s / peak m / distance m, q)')
        for name, g in cases:
            row = [f'{name:19s}']
            r = run(g, spd)
            d = (r['land'] - r['takeoff']) if r['land'] is not None and r['takeoff'] is not None else 0
            row.append(f"none:{r['air']:.2f}/{max(r['maxh'],0):.1f}/{d:.0f}")
            for lead in (0.40, 0.30, 0.20, 0.10, 0.05, 0.02):
                r = timed(g, spd, lead)
                if r is None: row.append(f'{lead:.2f}:-'); continue
                d = (r['land'] - r['takeoff']) if r['land'] is not None and r['takeoff'] is not None else 0
                q = r['q'] if r['q'] is not None else -2
                row.append(f"{lead:.2f}:{r['air']:.2f}/{max(r['maxh'],0):.1f}/{d:.0f} q{q:.1f}")
            print('  '.join(row))
