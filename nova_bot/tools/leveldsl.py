"""Tiny DSL for authoring NOVA BOT levels + a jump-feasibility validator + map renderer.

Heading convention (same as the game): heading h in degrees, 0 = -Z (north), 90 = +X (east).
direction = (sin h, 0, -cos h); right-hand side = (cos h, 0, sin h); Godot rotation.y = -h.
A platform is placed from the cursor's ENTRY edge forward, and the cursor ends on its far edge centre.
"""
import math
import numpy as np

GRAV = 34.0
FALL_MULT = 1.35
G_DN = GRAV * FALL_MULT
RUN = 9.0
JUMP_V = 12.8
DJUMP_V = 11.2
SAFETY = 0.85          # fraction of the theoretical reach that a level is allowed to ask for


def hv(h):
    r = math.radians(h)
    return (math.sin(r), -math.cos(r))


def rv(h):
    r = math.radians(h)
    return (math.cos(r), math.sin(r))


def r2(v):
    return round(float(v), 2)


def r3(x, y, z):
    return [r2(x), r2(y), r2(z)]


# ------------------------------------------------------------------ physics
def _land_t(apex, dy):
    return math.sqrt(max(2.0 * (apex - dy), 0.0) / G_DN)


def reach_single(dy):
    apex = JUMP_V ** 2 / (2 * GRAV)
    if dy >= apex - 0.25:
        return 0.0
    return RUN * (JUMP_V / GRAV + _land_t(apex, dy))


def reach_double(dy):
    apex = JUMP_V ** 2 / (2 * GRAV) + DJUMP_V ** 2 / (2 * GRAV)
    if dy >= apex - 0.3:
        return 0.0
    return RUN * (JUMP_V / GRAV + DJUMP_V / GRAV + _land_t(apex, dy))


def reach_bounce(power, dy):
    apex = power ** 2 / (2 * GRAV)
    if dy >= apex - 0.3:
        return 0.0
    return RUN * (power / GRAV + _land_t(apex, dy))


def allowed_gap(ability, dy):
    """Largest edge-to-edge gap (metres) a level may ask for with this ability, at height difference dy."""
    parts = ability.split(":")
    kind = parts[0]
    if kind == "walk":
        return 0.6 if abs(dy) <= 0.35 else 0.0
    if kind == "jump":
        return SAFETY * reach_single(dy)
    if kind == "double":
        return SAFETY * reach_double(dy)
    if kind == "dash":
        return SAFETY * (reach_single(dy) + 4.0)
    if kind == "hover":
        if dy > 3.0:
            return 0.0
        return 11.5 if dy <= 1.5 else 9.5
    if kind == "bounce":
        power = float(parts[1])
        back = float(parts[2]) if len(parts) > 2 else 0.0
        return SAFETY * reach_bounce(power, dy) - back
    if kind == "pad":
        # speed pad: ~22 m/s for roughly half the flight; capped because the boost fades
        spd = float(parts[1]) if len(parts) > 1 else 22.0
        dbl = len(parts) > 2 and parts[2] == "d"
        apex = JUMP_V ** 2 / (2 * GRAV)
        t = JUMP_V / GRAV + _land_t(apex, dy)
        if dbl:
            t += DJUMP_V / GRAV + 0.12
        return min(0.8 * spd * t * 0.85, 14.5 if not dbl else 20.0)
    if kind == "updraft":
        h = float(parts[1])
        takeoff = 0.85 * h          # leave the column at ~85 % of its height
        rel = dy - takeoff
        if rel > 1.0:
            return 0.0
        return 11.0
    if kind == "zerog":
        return 17.0 if dy <= 6.0 else 0.0
    raise ValueError("unknown ability " + ability)


# ----------------------------------------------------------------- geometry
class Surf:
    _n = 0

    def __init__(self, kind, cx, cz, y, hw=0.0, hl=0.0, ry=0.0, r=0.0, off=(0.0, 0.0, 0.0), tag="static", name=""):
        Surf._n += 1
        self.id = Surf._n
        self.kind, self.cx, self.cz, self.y = kind, cx, cz, y
        self.hw, self.hl, self.ry, self.r = hw, hl, ry, r
        self.off = off
        self.tag = tag
        self.name = name

    @property
    def moving(self):
        return any(abs(v) > 1e-6 for v in self.off)

    @property
    def heading(self):
        return -self.ry

    def at(self, k=0.0):
        return (self.cx + self.off[0] * k, self.y + self.off[1] * k, self.cz + self.off[2] * k)

    def boundary(self, k=0.0, step=0.3):
        cx, _, cz = self.at(k)
        pts = []
        if self.kind == "circle":
            n = max(32, int(2 * math.pi * self.r / step))
            for i in range(n):
                a = 2 * math.pi * i / n
                pts.append((cx + self.r * math.cos(a), cz + self.r * math.sin(a)))
        else:
            th = math.radians(self.ry)
            c, s = math.cos(th), math.sin(th)
            corners = [(-self.hw, -self.hl), (self.hw, -self.hl), (self.hw, self.hl), (-self.hw, self.hl)]
            for i in range(4):
                x0, z0 = corners[i]
                x1, z1 = corners[(i + 1) % 4]
                ln = math.hypot(x1 - x0, z1 - z0)
                n = max(2, int(ln / step))
                for j in range(n):
                    t = j / n
                    lx = x0 + (x1 - x0) * t
                    lz = z0 + (z1 - z0) * t
                    pts.append((cx + lx * c + lz * s, cz - lx * s + lz * c))
        return np.array(pts)

    def point(self, along=0.0, across=0.0, k=0.0):
        """World position on the top surface; along = metres from the centre toward the heading, across = to the right."""
        cx, y, cz = self.at(k)
        dx, dz = hv(self.heading)
        rx, rz = rv(self.heading)
        return (cx + dx * along + rx * across, y, cz + dz * along + rz * across)


def surf_gap(a, ka, b, kb):
    pa = a.boundary(ka)
    pb = b.boundary(kb)
    d = np.linalg.norm(pa[:, None, :] - pb[None, :, :], axis=2)
    return float(d.min())


class Cur:
    def __init__(self, x=0.0, y=0.0, z=0.0, h=0.0, last=None):
        self.x, self.y, self.z, self.h = x, y, z, h
        self.last = last
        self.pending = None
        self._hop_from = None

    def copy(self):
        c = Cur(self.x, self.y, self.z, self.h, self.last)
        c.pending = self.pending
        c._hop_from = self._hop_from
        return c

    def fwd(self, d):
        dx, dz = hv(self.h)
        self.x += dx * d
        self.z += dz * d
        return self

    def right(self, d):
        dx, dz = rv(self.h)
        self.x += dx * d
        self.z += dz * d
        return self

    def turn(self, dh):
        self.h = (self.h + dh) % 360.0
        return self

    def up(self, dy):
        self.y += dy
        return self

    @property
    def p(self):
        return (self.x, self.y, self.z)


# -------------------------------------------------------------------- level
class Level:
    def __init__(self, lid, name, theme, par=180):
        self.id = lid
        self.name = name
        self.theme = theme
        self.par = par
        self.objs = []
        self.surfs = []
        self.hops = []
        self.errors = []
        self.spawn = (0.0, 1.0, 0.0)
        self.yaw = 0.0
        self.cam = None
        self.bots = 0

    # ---- low level
    def add(self, **o):
        self.objs.append(o)

    def _reg(self, cur, s):
        self.surfs.append(s)
        if cur.pending is not None and cur.last is not None:
            self._validate(cur.last, s, cur.pending, cur._hop_from)
        cur.pending = None
        cur._hop_from = None
        cur.last = s

    def _validate(self, prev, nxt, ability, label):
        best = None
        kp_list = [0.0, 1.0] if prev.moving else [0.0]
        kn_list = [0.0, 1.0] if nxt.moving else [0.0]
        for kp in kp_list:
            for kn in kn_list:
                gap = surf_gap(prev, kp, nxt, kn)
                dy = nxt.at(kn)[1] - prev.at(kp)[1]
                allow = allowed_gap(ability, dy)
                margin = allow - gap
                if best is None or margin > best[0]:
                    best = (margin, gap, dy, allow, kp, kn)
        margin, gap, dy, allow, kp, kn = best
        rec = {"from": prev.name or prev.id, "to": nxt.name or nxt.id, "ability": ability, "gap": gap, "dy": dy,
               "allow": allow, "margin": margin}
        self.hops.append(rec)
        if margin < 0:
            self.errors.append("L%d hop %s -> %s [%s]: gap %.2f > allowed %.2f (dy %.2f)" % (
                self.id, rec["from"], rec["to"], ability, gap, allow, dy))
        if gap < 0.05 and ability != "walk":
            self.errors.append("L%d hop %s -> %s overlaps (gap %.2f)" % (self.id, rec["from"], rec["to"], gap))

    # ---- cursor-driven platforms
    def hop(self, cur, gap, dy=0.0, ability="jump", coins=0, coin_h=2.0):
        a = cur.p
        cur.fwd(gap)
        cur.up(dy)
        cur.pending = ability
        if coins > 0:
            self.coin_arc((a[0], a[1] + 1.2, a[2]), (cur.x, cur.y + 1.2, cur.z), coins, coin_h)
        return cur

    def plat(self, cur, length, width, th=0.8, c=0, name="", tag="static"):
        dx, dz = hv(cur.h)
        cx = cur.x + dx * length / 2
        cz = cur.z + dz * length / 2
        s = Surf("rect", cx, cz, cur.y, hw=width / 2, hl=length / 2, ry=-cur.h, tag=tag, name=name)
        self.add(t="box", p=r3(cx, cur.y, cz), s=[r2(width), r2(th), r2(length)], ry=r2(-cur.h), c=c)
        self._reg(cur, s)
        cur.fwd(length)
        return s

    def disc(self, cur, r, th=0.8, c=0, name=""):
        dx, dz = hv(cur.h)
        cx, cz = cur.x + dx * r, cur.z + dz * r
        s = Surf("circle", cx, cz, cur.y, r=r, name=name)
        self.add(t="cyl", p=r3(cx, cur.y, cz), r=r2(r), th=r2(th), c=c)
        self._reg(cur, s)
        cur.fwd(2 * r)
        return s

    def mover(self, cur, width, length, off, per, ph=0.0, th=0.8, c=0, name="", shift=0.0):
        """off = (across, dy, along) relative to the heading. shift moves the start sideways (so a lateral mover is symmetric)."""
        dx, dz = hv(cur.h)
        rx, rz = rv(cur.h)
        cx = cur.x + dx * length / 2 + rx * shift
        cz = cur.z + dz * length / 2 + rz * shift
        wo = (rx * off[0] + dx * off[2], off[1], rz * off[0] + dz * off[2])
        s = Surf("rect", cx, cz, cur.y, hw=width / 2, hl=length / 2, ry=-cur.h, off=wo, tag="move", name=name)
        self.add(t="move", p=r3(cx, cur.y, cz), s=[r2(width), r2(th), r2(length)], ry=r2(-cur.h),
                 off=[r2(wo[0]), r2(wo[1]), r2(wo[2])], per=per, ph=ph, c=c)
        self._reg(cur, s)
        cur.fwd(length + off[2])
        cur.up(off[1] if off[1] > 0 else 0.0)
        return s

    def crumble(self, cur, length, width, delay=0.6, respawn=3.5, th=0.7, c=3, name=""):
        dx, dz = hv(cur.h)
        cx, cz = cur.x + dx * length / 2, cur.z + dz * length / 2
        s = Surf("rect", cx, cz, cur.y, hw=width / 2, hl=length / 2, ry=-cur.h, tag="crumble", name=name)
        self.add(t="crumble", p=r3(cx, cur.y, cz), s=[r2(width), r2(th), r2(length)], ry=r2(-cur.h), delay=delay,
                 respawn=respawn, c=c)
        self._reg(cur, s)
        cur.fwd(length)
        return s

    def ghost(self, cur, length, width, on=2.2, off=1.6, ph=0.0, th=0.5, c=2, mode="cycle", sid="", name=""):
        dx, dz = hv(cur.h)
        cx, cz = cur.x + dx * length / 2, cur.z + dz * length / 2
        s = Surf("rect", cx, cz, cur.y, hw=width / 2, hl=length / 2, ry=-cur.h, tag="ghost", name=name)
        o = dict(t="ghost", p=r3(cx, cur.y, cz), s=[r2(width), r2(th), r2(length)], ry=r2(-cur.h), c=c)
        if mode == "switch":
            o["mode"] = "switch"
            o["id"] = sid
        else:
            o.update(on=on, off=off, ph=ph)
        self.add(**o)
        self._reg(cur, s)
        cur.fwd(length)
        return s

    def sweeper(self, surf, length, speed, along=0.0, across=0.0, height=0.6, c=2, w=0.7, ph=0.0):
        x, y, z = surf.point(along, across)
        self.add(t="spin", p=r3(x, y + height, z), len=r2(length), th=0.5, w=w, speed=speed, ph=ph, c=c)

    # ---- cursor helpers
    def side_cur(self, surf, sign, along=0.0, y=None):
        """Cursor on the side edge (at `along` metres from the centre) of a rect surface, heading turned 90 degrees
        (sign +1 = right, -1 = left)."""
        h = surf.heading
        x, cy, z = surf.point(along, surf.hw * sign)
        return Cur(x, cy if y is None else y, z, (h + 90.0 * sign) % 360.0, surf)

    def rel(self, heading, across=0.0, dy=0.0, along=0.0):
        """World-space offset vector from heading-relative components."""
        dx, dz = hv(heading)
        rx, rz = rv(heading)
        return (rx * across + dx * along, dy, rz * across + dz * along)

    def conveyor(self, cur, length, width, spd, reverse=False, th=0.6, c=0, name=""):
        """Solid belt along the cursor heading; belt moves forward (or backward when reverse=True) at spd m/s."""
        dx, dz = hv(cur.h)
        cx, cz = cur.x + dx * length / 2, cur.z + dz * length / 2
        s = Surf("rect", cx, cz, cur.y, hw=width / 2, hl=length / 2, ry=-cur.h, tag="conv", name=name)
        belt_h = (cur.h + (180.0 if reverse else 0.0)) % 360.0
        self.add(t="conv", p=r3(cx, cur.y, cz), s=[r2(width), r2(th), r2(length)], ry=r2(-cur.h), dir=r2(belt_h), spd=spd, c=c)
        self._reg(cur, s)
        cur.fwd(length)
        return s

    def exit_circle(self, surf, heading):
        dx, dz = hv(heading)
        cx, cy, cz = surf.at(0.0)
        return Cur(cx + dx * surf.r, cy, cz + dz * surf.r, heading % 360.0, surf)

    # ---- placed objects (world positions)
    def hint(self, p, r, txt):
        self.add(t="hint", p=r3(*p), r=r, txt=txt)

    def coins(self, pts):
        self.add(t="coins", pts=[r3(*p) for p in pts])

    def coin_arc(self, a, b, n, height):
        pts = []
        for i in range(n):
            t = (i + 1) / (n + 1)
            x = a[0] + (b[0] - a[0]) * t
            z = a[2] + (b[2] - a[2]) * t
            y = a[1] + (b[1] - a[1]) * t + height * 4 * t * (1 - t)
            pts.append((x, y, z))
        self.coins(pts)

    def coin_line(self, surf, n, height=1.0, along0=None, along1=None, across=0.0):
        if along0 is None:
            along0 = -surf.hl + 1.0 if surf.kind == "rect" else -surf.r + 1.0
        if along1 is None:
            along1 = surf.hl - 1.0 if surf.kind == "rect" else surf.r - 1.0
        pts = []
        for i in range(n):
            t = i / max(n - 1, 1)
            x, y, z = surf.point(along0 + (along1 - along0) * t, across)
            pts.append((x, y + height, z))
        self.coins(pts)

    def coin_ring(self, centre, radius, n, y_off=1.0):
        pts = []
        for i in range(n):
            a = 2 * math.pi * i / n
            pts.append((centre[0] + radius * math.cos(a), centre[1] + y_off, centre[2] + radius * math.sin(a)))
        self.coins(pts)

    def bot(self, p, i):
        self.bots += 1
        self.add(t="bot", p=r3(*p), i=i)

    def crate(self, p, n=5):
        self.add(t="crate", p=r3(*p), n=n)

    def check(self, p, yaw):
        self.add(t="check", p=r3(*p), yaw=r2(yaw))

    def goal(self, p, locked=False):
        self.add(t="goal", p=r3(*p), locked=locked)

    def bounce(self, p, power=22.0, r=1.2, c=1):
        self.add(t="bounce", p=r3(*p), **{"pow": power}, r=r, c=c)

    def spad(self, p, heading, length=4.0, w=3.0, spd=22.0, c=3):
        self.add(t="spad", p=r3(*p), dir=r2(heading), len=length, w=w, spd=spd, c=c)

    def updraft(self, p, r=2.2, h=9.0, spd=14.0, c=0):
        self.add(t="updraft", p=r3(*p), r=r, h=h, spd=spd, c=c)

    def zerog(self, p, r=8.0, c=3):
        self.add(t="zerog", p=r3(*p), r=r, c=c)

    def conv(self, surf_p, size, ry, heading, spd, c=0, name=""):
        self.add(t="conv", p=r3(*surf_p), s=[r2(size[0]), r2(size[1]), r2(size[2])], ry=r2(ry), dir=r2(heading), spd=spd, c=c)

    def drone(self, p, off, per, ph=0.0):
        self.add(t="drone", p=r3(*p), off=[r2(off[0]), r2(off[1]), r2(off[2])], per=per, ph=ph)

    def turret(self, p, rng=16.0, every=2.4, ph=0.0):
        self.add(t="turret", p=r3(*p), range=rng, every=every, ph=ph)

    def spikes(self, p, w, d, per=3.0, ph=0.0, out=0.55, ry=0.0):
        self.add(t="spikes", p=r3(*p), s=[r2(w), r2(d)], per=per, ph=ph, out=out, ry=r2(ry))

    def saw(self, p, off, per=4.0, ph=0.0, r=1.1):
        self.add(t="saw", p=r3(*p), off=[r2(off[0]), r2(off[1]), r2(off[2])], per=per, ph=ph, r=r)

    def laser(self, a, b, on=2.0, off=1.5, ph=0.0):
        self.add(t="laser", a=r3(*a), b=r3(*b), on=on, off=off, ph=ph)

    def bumper(self, p, r=0.9, power=15.0, c=2):
        self.add(t="bumper", p=r3(*p), r=r, **{"pow": power}, c=c)

    def switch(self, p, sid, dur=9.0, c=2):
        self.add(t="switch", p=r3(*p), id=sid, dur=dur, c=c)

    def boss(self, p, r):
        self.add(t="boss", p=r3(*p), r=r)

    # ---- output
    def to_json(self):
        ys = [s.y + min(s.off[1], 0.0) for s in self.surfs]
        kill_y = r2(min(ys) - 28.0)
        d = {
            "id": self.id, "name": self.name, "theme": self.theme,
            "spawn": r3(*self.spawn), "yaw": r2(self.yaw), "kill_y": kill_y,
            "par": self.par, "bots_total": self.bots,
            "objects": self.objs,
        }
        if self.cam:
            d["cam"] = self.cam
        return d

    def report(self):
        lines = ["Level %d (%s): %d objects, %d surfaces, %d hops, bots=%d" % (
            self.id, self.theme, len(self.objs), len(self.surfs), len(self.hops), self.bots)]
        tight = [h for h in self.hops if h["margin"] < 0.5]
        for h in self.hops:
            flag = "!!" if h["margin"] < 0 else ("~ " if h["margin"] < 0.5 else "  ")
            lines.append("  %s %-10s -> %-10s %-12s gap %5.2f dy %5.2f allow %5.2f margin %5.2f" % (
                flag, str(h["from"]), str(h["to"]), h["ability"], h["gap"], h["dy"], h["allow"], h["margin"]))
        if tight:
            lines.append("  (%d tight hops)" % len(tight))
        return "\n".join(lines)


# --------------------------------------------------------------------- maps
def render_map(level, path):
    import matplotlib
    matplotlib.use("Agg")
    import matplotlib.pyplot as plt
    from matplotlib.patches import Polygon, Circle

    fig, ax = plt.subplots(figsize=(14, 10), dpi=90)
    ax.set_aspect("equal")
    ax.set_facecolor("#0b1020")
    fig.patch.set_facecolor("#0b1020")
    tagcol = {"static": "#2b6cb0", "move": "#d69e2e", "crumble": "#dd6b20", "ghost": "#9f7aea"}
    ys = [s.y for s in level.surfs]
    for s in level.surfs:
        for k in ([0.0, 1.0] if s.moving else [0.0]):
            cx, y, cz = s.at(k)
            col = tagcol.get(s.tag, "#2b6cb0")
            alpha = 0.85 if k == 0.0 else 0.25
            if s.kind == "circle":
                ax.add_patch(Circle((cx, cz), s.r, facecolor=col, edgecolor="white", alpha=alpha, lw=0.8))
            else:
                th = math.radians(s.ry)
                c, sn = math.cos(th), math.sin(th)
                pts = []
                for lx, lz in [(-s.hw, -s.hl), (s.hw, -s.hl), (s.hw, s.hl), (-s.hw, s.hl)]:
                    pts.append((cx + lx * c + lz * sn, cz - lx * sn + lz * c))
                ax.add_patch(Polygon(pts, closed=True, facecolor=col, edgecolor="white", alpha=alpha, lw=0.8))
            if k == 0.0:
                ax.text(cx, cz, "%.1f" % y, color="white", fontsize=6, ha="center", va="center")
        if s.moving:
            a, b = s.at(0.0), s.at(1.0)
            ax.plot([a[0], b[0]], [a[2], b[2]], color="#f6e05e", lw=1, ls="--")
    mk = {
        "coins": ("o", "#f6e05e", 2), "bot": ("*", "#4fd1c5", 14), "crate": ("s", "#ed8936", 7), "check": ("P", "#68d391", 9),
        "goal": ("D", "#ffffff", 10), "bounce": ("^", "#f687b3", 8), "spad": (">", "#fbd38d", 8), "updraft": ("^", "#63b3ed", 9),
        "zerog": ("o", "#b794f4", 14), "drone": ("x", "#fc8181", 8), "turret": ("v", "#fc8181", 9), "spikes": ("s", "#e53e3e", 6),
        "saw": ("h", "#e53e3e", 9), "bumper": ("o", "#ed64a6", 8), "switch": ("s", "#76e4f7", 8), "boss": ("*", "#e53e3e", 18),
        "hint": (".", "#a0aec0", 4), "spin": ("+", "#e53e3e", 10),
    }
    for o in level.objs:
        t = o["t"]
        if t == "coins":
            for p in o["pts"]:
                ax.plot(p[0], p[2], "o", color="#f6e05e", ms=2)
        elif t == "laser":
            a, b = o["a"], o["b"]
            ax.plot([a[0], b[0]], [a[2], b[2]], color="#fc8181", lw=2)
        elif t in mk and "p" in o:
            m, col, ms = mk[t]
            ax.plot(o["p"][0], o["p"][2], m, color=col, ms=ms)
            if t == "boss":
                ax.add_patch(Circle((o["p"][0], o["p"][2]), o["r"], fill=False, edgecolor="#e53e3e", lw=1.5, ls=":"))
    ax.plot(level.spawn[0], level.spawn[2], "o", color="#00ff88", ms=12, mfc="none", mew=2)
    ax.invert_yaxis()   # -Z (north) is up on the plot
    ax.set_title("Level %d - %s (top view, north up; numbers = top height in metres)" % (level.id, level.theme), color="white")
    ax.tick_params(colors="#a0aec0")
    ax.grid(color="#1a2238", lw=0.5)
    xs = [s.at(k)[0] for s in level.surfs for k in (0.0, 1.0)]
    zs = [s.at(k)[2] for s in level.surfs for k in (0.0, 1.0)]
    ax.set_xlim(min(xs) - 12, max(xs) + 12)
    ax.set_ylim(max(zs) + 12, min(zs) - 12)
    fig.savefig(path)
    plt.close(fig)
