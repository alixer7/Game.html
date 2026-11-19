#!/usr/bin/env python3
"""Builds levels/level_1..4.json from the DSL in leveldsl.py, validates every jump against the player's
movement numbers and renders top-view maps to docs/level_maps/.

    python3 tools/build_levels.py          # write json + maps, print the hop report
    python3 tools/build_levels.py --quiet  # only print errors / summary
"""
import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from leveldsl import Level, Cur, render_map  # noqa: E402
import check_levels  # noqa: E402

ROOT = os.path.dirname(HERE)


def up(p, dy):
    return (p[0], p[1] + dy, p[2])


# ============================================================ LEVEL 1
def level1():
    L = Level(1, "محطة الانطلاق", "launch", par=170)
    cur = Cur(0, 0, 0, 0)
    sp = L.disc(cur, 5.5, c=0, name="spawn")
    L.spawn = (0.0, 0.6, -5.5)
    L.hint((0, 0, -5.5), 6.5, "حرّك العصا اليسرى للمشي")
    L.coin_ring((0, 0, -5.5), 3.2, 8)
    L.hint(sp.point(4.2), 4.0, "اضغط زر القفز")

    # 1. easy hops --------------------------------------------------------
    L.hop(cur, 2.6, 0, "jump", coins=3, coin_h=1.8)
    a = L.plat(cur, 6, 5, c=0, name="A")
    L.coin_line(a, 4)
    L.hop(cur, 3.4, 0, "jump", coins=3)
    b = L.plat(cur, 6, 4.5, c=1, name="B")
    # friend #1 on a little side island
    s1 = L.side_cur(b, +1)
    L.hop(s1, 3.2, 0, "jump", coins=2)
    bp = L.plat(s1, 4.5, 4.5, c=2, name="bot1")
    L.bot(bp.point(0, 0), 0)
    L.hop(cur, 3.8, 0.8, "jump", coins=3)
    c_ = L.plat(cur, 7, 4.5, c=0, name="C")
    L.coin_line(c_, 5)

    # 2. double jump + crates ---------------------------------------------
    L.hint(c_.point(2.4), 4.5, "اضغط القفز مرتين في الهواء")
    L.hop(cur, 6.2, 0, "double", coins=5, coin_h=3.2)
    d = L.plat(cur, 9, 8, c=3, name="D")
    L.hint(d.point(-3.2), 5.5, "اضغط زر الدوران لتحطيم الصناديق")
    L.crate(d.point(1.0, -2.5), 6)
    L.crate(d.point(1.0, 0.0), 6)
    L.crate(d.point(1.0, 2.5), 6)
    # friend #2 on a ledge reached with a double jump
    s2 = L.side_cur(d, -1)
    L.hop(s2, 2.8, 1.4, "jump", coins=2)
    st1 = L.plat(s2, 3.0, 3.0, c=2, name="step1")
    L.hop(s2, 5.5, 1.6, "double", coins=4, coin_h=3.0)
    ledge = L.plat(s2, 4.5, 4.5, c=1, name="ledge")
    L.bot(ledge.point(0, 0), 1)

    # 3. patrol plaza (the route turns east here) --------------------------------
    cur = L.side_cur(d, +1, along=2.0)
    L.hop(cur, 3.6, 0, "jump", coins=3)
    e = L.plat(cur, 15, 9, c=0, name="E")
    L.hint(e.point(-6.0), 5.0, "اقفز فوق الأعداء أو دُر لتحطيمهم")
    p = e.point(-1.0, -3.0)
    L.drone(up(p, 1.1), L.rel(e.heading, 6.0), 4.5)
    p = e.point(3.5, 3.0)
    L.drone(up(p, 1.1), L.rel(e.heading, -6.0), 4.5, 0.5)
    L.crate(e.point(6.0, 3.6), 5)
    L.check(e.point(6.3, -3.4), e.heading)
    L.coin_line(e, 6, across=-3.2)

    # 4. dash gap --------------------------------------------------------------
    L.hint(e.point(6.5), 3.8, "اضغط الاندفاع في الهواء لتطير أبعد")
    L.hop(cur, 7.8, 0, "dash", coins=5, coin_h=2.6)
    f = L.plat(cur, 6, 5, c=1, name="F")

    # 5. moving platforms ---------------------------------------------------
    L.hop(cur, 3.8, 0, "jump")
    L.mover(cur, 4, 4, (0, 0, 9), per=6.0, c=2, name="M1")
    L.hop(cur, 3.8, 0, "jump")
    g0 = L.plat(cur, 5, 5, c=0, name="G0")
    L.coin_line(g0, 3)
    L.hop(cur, 3.5, 0, "jump")
    L.mover(cur, 4, 4, (7, 0, 0), per=5.0, shift=-3.5, c=1, name="M2")
    L.hop(cur, 3.5, 0, "jump")
    L.mover(cur, 4, 4, (0, 3.0, 0), per=5.0, c=3, name="M3")
    L.hop(cur, 3.5, 0, "jump")

    # 6. bounce pad ---------------------------------------------------------
    g = L.plat(cur, 10, 5, c=0, name="G")
    L.hint(g.point(-3.0), 5.0, "النطّاطات ترفعك عالياً")
    L.bounce(g.point(3.4), 22, 1.2, 1)
    L.hop(cur, 3.2, 4.5, "bounce:22:1.6", coins=5, coin_h=3.5)
    h = L.plat(cur, 12, 6, c=3, name="H")
    L.check(h.point(-4.5, 2.2), h.heading)
    L.hint(h.point(-2.0), 5.0, "منصات السرعة تدفعك للأمام")
    L.spad(h.point(-3.0), h.heading, 4.0, 3.0, 22.0, 3)

    # 7. speed-pad leap ---------------------------------------------------
    L.hop(cur, 10.0, -1.0, "pad:22", coins=6, coin_h=3.5)
    i = L.plat(cur, 8, 6, c=2, name="I")
    L.coin_line(i, 4)

    # 8. finale (turn back north) -------------------------------------------
    cur = L.side_cur(i, -1, along=1.0)
    L.hop(cur, 4.0, 0.4, "jump", coins=3)
    d1 = L.disc(cur, 2.4, c=1, name="D1")
    L.hop(cur, 4.2, 0.4, "jump", coins=3)
    d2 = L.disc(cur, 2.4, c=2, name="D2")
    s3 = L.exit_circle(d2, cur.h + 90)
    L.hint(d2.point(0, 0), 4.0, "صديقك الأخير بعيد... حلّق بالقفز الطويل!")
    L.hop(s3, 9.4, 0.4, "hover", coins=3, coin_h=4.0)
    db = L.disc(s3, 2.0, c=3, name="bot3")
    L.bot(db.point(0, 0), 2)
    L.hop(cur, 4.2, 0.4, "jump", coins=3)
    d3 = L.disc(cur, 2.4, c=0, name="D3")
    L.hop(cur, 4.4, 0.0, "jump", coins=3)
    fin = L.plat(cur, 12, 10, c=3, name="FIN")
    L.goal(fin.point(2.0), False)
    L.coin_ring(fin.point(2.0), 3.8, 10)
    return L


# ============================================================ LEVEL 2
def level2():
    L = Level(2, "حدائق الكريستال", "crystal", par=210)
    cur = Cur(0, 0, 0, 0)
    sp = L.disc(cur, 5.5, c=0, name="spawn")
    L.spawn = (0.0, 0.6, -5.5)
    L.hint((0, 0, -9.0), 5.0, "المنصات المتوهّجة تنهار! تابع الركض")

    # 1. crumbling road --------------------------------------------------
    first = None
    last = None
    for k in range(6):
        L.hop(cur, 2.4 if k == 0 else 1.8, 0, "jump")
        t = L.crumble(cur, 3.2, 3.6, delay=0.6, respawn=3.5, c=3, name="CR%d" % k)
        if first is None:
            first = t
        last = t
    for k in range(10):
        x, y, z = first.point(-1.6 + k * 2.9, 0)
        L.coins([(x, y + 1.1, z)])

    # 2. plaza ---------------------------------------------------------------
    L.hop(cur, 2.0, 0, "jump")
    p1 = L.plat(cur, 8, 8, c=0, name="P1")
    L.check(p1.point(-2.0, 2.5), p1.heading)
    L.crate(p1.point(1.0, -2.5), 6)
    L.crate(p1.point(1.0, 2.5), 6)
    L.coin_line(p1, 4)

    # 3. ghost rhythm -------------------------------------------------------
    L.hint(p1.point(3.0), 4.5, "المنصات الشبحية تظهر وتختفي")
    for k in range(5):
        L.hop(cur, 3.4, 0, "jump", coins=2)
        gp = L.ghost(cur, 3.4, 3.4, on=2.0, off=1.4, ph=0.15 * k, c=2, name="GH%d" % k)
    L.hop(cur, 3.4, 0, "jump")
    p2 = L.plat(cur, 8, 8, c=1, name="P2")

    # 4. switch bridge ---------------------------------------------------------
    L.hint(p2.point(-1.0), 5.5, "اضغط على المفتاح لإظهار الجسر")
    ssw = L.side_cur(p2, +1)
    L.hop(ssw, 3.4, 0, "jump", coins=2)
    sw = L.plat(ssw, 4.5, 4.5, c=2, name="SW")
    L.switch(sw.point(0, 0), "A", 12.0, 2)
    L.hop(cur, 2.0, 0, "jump")
    for k in range(4):
        if k > 0:
            L.hop(cur, 2.4, 0, "jump")
        L.ghost(cur, 3.6, 3.6, mode="switch", sid="A", c=0, name="BR%d" % k)
        L.coins([up(L.surfs[-1].point(0, 0), 1.2)])
    L.hop(cur, 2.2, 0, "jump")
    p3 = L.plat(cur, 8, 8, c=3, name="P3")
    L.check(p3.point(2.5, -2.5), p3.heading)

    # 5. spiral tower --------------------------------------------------------
    L.hint(p3.point(3.0), 5.0, "اصعد البرج الحلزوني")
    rim = []
    for k in range(8):
        L.hop(cur, 3.3, 1.3, "jump", coins=1, coin_h=1.4)
        st = L.plat(cur, 3.6, 3.6, c=k % 4, name="SP%d" % k)
        rim.append(st)
        cur.turn(45)
    # tower top: sweeper platform
    L.hop(cur, 3.6, 1.3, "jump", coins=2)
    top = L.plat(cur, 11, 8, c=2, name="TOP")
    L.sweeper(top, 7.0, 1.1, along=-2.0, height=0.55, c=2)
    L.bot(top.point(4.0, 0), 0)
    L.coin_line(top, 3, across=-2.5)
    L.check(top.point(4.3, 3.0), top.heading)

    # 6. bumper arena (the route turns west at the top of the tower) -----------------
    cur = L.side_cur(top, -1, along=0.0)
    L.hop(cur, 4.0, -0.5, "jump", coins=3)
    arena = L.disc(cur, 7.5, c=1, name="ARENA")
    cx, cy, cz = arena.at(0)
    import math
    for k in range(3):
        a = math.radians(90 + 120 * k)
        L.bumper((cx + 3.6 * math.cos(a), cy, cz + 3.6 * math.sin(a)), 0.9, 15, 2)
    L.drone(up(arena.point(-2.0, -4.5), 1.1), L.rel(cur.h, 0, 0, 8.0), 4.0)
    L.drone(up(arena.point(2.0, 4.5), 1.1), L.rel(cur.h, 0, 0, -8.0), 4.0, 0.5)
    L.coin_ring((cx, cy, cz), 6.0, 12)
    L.crate(arena.point(-6.2, 0.0), 6)
    # friend #2: ghost-stair detour on the left
    sg = L.exit_circle(arena, cur.h - 90)
    for k in range(3):
        L.hop(sg, 3.5, 1.5, "jump", coins=1, coin_h=1.4)
        L.ghost(sg, 3.4, 3.4, on=2.4, off=1.2, ph=0.2 * k, c=3, name="GS%d" % k)
    L.hop(sg, 3.8, 1.5, "jump", coins=2)
    alc = L.plat(sg, 5.0, 5.0, c=2, name="ALCOVE")
    L.bot(alc.point(0, 0), 1)
    L.check(alc.point(-1.5, 0), alc.heading)

    # 7. spike corridor --------------------------------------------------------
    L.hop(cur, 4.2, 0, "jump", coins=3)
    sc = L.plat(cur, 22, 4.4, c=0, name="SPIKES")
    for k, al in enumerate([-6.0, 0.0, 6.0]):
        L.spikes(sc.point(al, 0), 4.0, 3.4, per=3.0, ph=0.34 * k, out=0.5)
        x, y, z = sc.point(al, 0)
        L.coins([(x, y + 2.2, z)])
    L.coin_line(sc, 4, height=1.1, along0=-9.5, along1=9.5)
    # friend #3: dead-end crumble path
    sb = L.side_cur(sc, +1, along=3.0)
    for k in range(3):
        L.hop(sb, 1.6 if k else 2.2, 0, "jump")
        L.crumble(sb, 3.2, 3.4, delay=0.7, respawn=3.0, c=3, name="BC%d" % k)
    L.hop(sb, 2.2, 0, "jump")
    bb = L.plat(sb, 5.0, 5.0, c=1, name="BOT3")
    L.bot(bb.point(0, 0), 2)

    # 8. finale: bounce islands -----------------------------------------------
    L.bounce(sc.point(9.0), 24, 1.2, 1)
    L.hop(cur, 5.0, 3.0, "bounce:24:1.6", coins=4, coin_h=3.5)
    i1 = L.disc(cur, 3.0, c=1, name="I1")
    L.bounce(i1.point(0, 0), 24, 1.2, 1)
    L.hop(cur, 5.0, 2.5, "bounce:24:3.0", coins=4, coin_h=3.5)
    i2 = L.disc(cur, 3.0, c=2, name="I2")
    L.bounce(i2.point(0, 0), 24, 1.2, 1)
    L.hop(cur, 5.0, 2.5, "bounce:24:3.0", coins=4, coin_h=3.5)
    fin = L.plat(cur, 12, 10, c=3, name="FIN")
    L.goal(fin.point(2.0), False)
    L.coin_ring(fin.point(2.0), 3.8, 10)
    L.check(fin.point(-4.0, 3.0), fin.heading)
    return L


# ============================================================ LEVEL 3
def level3():
    L = Level(3, "مصنع الجاذبية", "foundry", par=240)
    cur = Cur(0, 0, 0, 0)
    sp = L.disc(cur, 5.5, c=0, name="spawn")
    L.spawn = (0.0, 0.6, -5.5)
    L.hint((0, 0, -9.0), 5.0, "السيور تدفعك للخلف! لا تلمس المناشير")

    # 1. reverse conveyor + saws ---------------------------------------------
    L.hop(cur, 2.4, 0, "jump")
    a = L.plat(cur, 5, 5, c=0, name="A")
    L.hop(cur, 2.4, 0, "jump")
    cv = L.conveyor(cur, 22, 4.4, 4.0, reverse=True, c=1, name="CV1")
    for k, al in enumerate([-5.0, 2.0, 8.0]):
        x, y, z = cv.point(al, -2.0)
        L.saw((x, y + 0.8, z), L.rel(cv.heading, 4.0), per=3.2, ph=0.3 * k, r=0.8)
    L.coin_line(cv, 6, height=1.1, along0=-9.0, along1=9.0)
    L.hop(cur, 2.4, 0, "jump")
    b = L.plat(cur, 7, 6, c=2, name="B")
    L.check(b.point(-1.5, 2.0), b.heading)

    # 2. updraft elevator ---------------------------------------------------
    L.hint(b.point(-2.0), 5.0, "ادخل عمود الهواء لترتفع")
    L.updraft(b.point(0.5, 0), 2.2, 10.0, 14.0, 0)
    L.coin_ring(b.point(0.5, 0), 1.4, 8, y_off=4.5)
    L.hop(cur, 3.2, 9.0, "updraft:10", coins=3, coin_h=1.5)
    u1 = L.plat(cur, 26, 5.2, c=3, name="U1")

    # 3. laser corridor ------------------------------------------------------
    hw = u1.hw + 0.6
    for k, al in enumerate([-8.0, -1.0, 6.0]):
        ax, ay, az = u1.point(al, -hw)
        bx, by, bz = u1.point(al, hw)
        L.laser((ax, ay + 0.5, az), (bx, by + 0.5, bz), on=1.6, off=1.8, ph=0.33 * k)
    L.coin_line(u1, 8, height=1.2, along0=-10.0, along1=10.0)
    L.check(u1.point(10.5, 1.5), u1.heading)
    # friend #1: laser dead end
    sl = L.side_cur(u1, +1, along=-2.0)
    L.hop(sl, 2.6, 0, "jump", coins=2)
    lb = L.plat(sl, 14, 4.6, c=1, name="LB")
    for k, al in enumerate([-3.0, 3.0]):
        ax, ay, az = lb.point(al, -lb.hw - 0.6)
        bx, by, bz = lb.point(al, lb.hw + 0.6)
        L.laser((ax, ay + 0.5, az), (bx, by + 0.5, bz), on=1.4, off=1.6, ph=0.5 * k)
    L.bot(lb.point(5.0, 0), 0)

    # 4. zero-g crossing ----------------------------------------------------------
    L.hint(u1.point(11.5), 4.0, "فقاعة انعدام الجاذبية! اقفز بعيداً")
    gap_start = cur.p
    L.hop(cur, 16.0, 0, "zerog")
    zc = (gap_start[0], gap_start[1] + 3.0, gap_start[2] - 8.0)
    L.zerog(zc, 11.0, 3)
    L.coin_ring((zc[0], zc[1], zc[2]), 6.0, 10, y_off=0.5)
    L.bot((zc[0], zc[1] + 1.0, zc[2]), 1)
    z1 = L.plat(cur, 9, 8, c=0, name="Z1")
    L.check(z1.point(-2.0, 2.5), z1.heading)

    # 5. turret gallery ------------------------------------------------------
    L.hint(z1.point(2.0), 5.0, "المدافع تطلق النار! حطّمها بالدوران")
    L.hop(cur, 2.4, 0, "jump")
    tg = L.plat(cur, 32, 4.4, c=2, name="GAL")
    for k, (al, sg) in enumerate([(-10.0, +1), (0.0, -1), (10.0, +1)]):
        sc = L.side_cur(tg, sg, along=al)
        L.hop(sc, 2.4, 1.4, "jump", coins=1, coin_h=1.4)
        ped = L.plat(sc, 3.4, 3.4, c=3, name="PED%d" % k)
        L.turret(ped.point(0, 0), 26.0, 2.3, 0.3 * k)
    L.coin_line(tg, 8, height=1.1, along0=-14.0, along1=14.0)
    L.crate(tg.point(-13.0, 1.4), 5)
    L.crate(tg.point(13.0, -1.4), 5)
    L.check(tg.point(14.5, 0), tg.heading)

    # 6. sweeper room ---------------------------------------------------------
    L.hop(cur, 3.0, 0, "jump")
    sw = L.plat(cur, 15, 15, c=0, name="SWEEP")
    L.sweeper(sw, 13.0, 1.25, along=0.0, height=0.6, c=2)
    L.coin_ring(sw.point(0, 0), 5.0, 12, y_off=1.2)
    # friend #2: ride a second updraft to a high ledge on the right
    ub = L.side_cur(sw, -1, along=-3.0)
    L.hop(ub, 2.6, 0, "jump")
    uplat = L.plat(ub, 5.0, 5.0, c=1, name="UP2")
    L.updraft(uplat.point(0, 0), 2.2, 10.0, 14.0, 0)
    L.hop(ub, 3.2, 9.5, "updraft:10", coins=3, coin_h=1.5)
    ledge = L.plat(ub, 5.0, 5.0, c=3, name="UPLEDGE")
    L.bot(ledge.point(0, 0), 2)

    # 7. forward conveyors + saws (route turns east) -----------------------------
    cur = L.side_cur(sw, +1, along=3.0)
    L.hop(cur, 3.0, 0, "jump")
    c2 = L.conveyor(cur, 20, 4.2, 6.0, reverse=False, c=3, name="CV2")
    for k, al in enumerate([-4.0, 4.0]):
        x, y, z = c2.point(al, 2.0)
        L.saw((x, y + 0.8, z), L.rel(c2.heading, -4.0), per=2.8, ph=0.5 * k, r=0.8)
    L.coin_line(c2, 6, height=1.1, along0=-8.0, along1=8.0)
    L.hop(cur, 2.0, 0, "jump")
    mid = L.plat(cur, 6, 6, c=0, name="MID")
    L.check(mid.point(0, 0), mid.heading)

    # 8. finale: bounce ----------------------------------------------------------
    L.hop(cur, 3.0, 0, "jump")
    run = L.plat(cur, 12, 5, c=1, name="RUN")
    L.bounce(run.point(4.0), 26, 1.2, 1)
    L.hop(cur, 4.0, 4.0, "bounce:26:2.0", coins=5, coin_h=4.0)
    fin = L.plat(cur, 12, 10, c=3, name="FIN")
    L.goal(fin.point(2.0), False)
    L.coin_ring(fin.point(2.0), 3.8, 10)
    return L


# ============================================================ LEVEL 4
def level4():
    import math
    L = Level(4, "قلب المجرة", "core", par=260)
    L.cam = {"dist": 9.0, "pitch": 0.5}
    cur = Cur(0, 0, 0, 0)
    sp = L.disc(cur, 5.5, c=0, name="spawn")
    L.spawn = (0.0, 0.6, -5.5)
    L.hint((0, 0, -5.5), 6.5, "الحارس ينتظرك في قلب المجرة")

    # 1. speed run ---------------------------------------------------------
    L.hop(cur, 2.4, 0, "jump")
    a = L.plat(cur, 14, 5, c=0, name="A")
    L.hint(a.point(-5.0), 4.0, "اركض فوق منصة السرعة ثم اقفز")
    L.spad(a.point(-3.0), a.heading, 4.0, 3.0, 22.0, 3)
    L.hop(cur, 10.0, -1.0, "pad:22", coins=6, coin_h=3.5)
    b = L.plat(cur, 8, 6, c=1, name="B")
    L.check(b.point(2.0, 0), b.heading)

    # 2. movers over the void -------------------------------------------------
    L.hop(cur, 3.8, 0, "jump")
    L.mover(cur, 4, 4, (8, 0, 0), per=5.0, shift=-4.0, c=2, name="M1")
    L.hop(cur, 3.8, 0, "jump")
    L.mover(cur, 4, 4, (-8, 0, 0), per=5.0, shift=4.0, ph=0.5, c=3, name="M2")
    L.hop(cur, 3.8, 0, "jump")
    c_ = L.plat(cur, 6, 6, c=0, name="C")
    # friend #1: tough double-jump island
    s1 = L.side_cur(c_, -1)
    L.hop(s1, 6.6, 0.8, "double", coins=5, coin_h=3.4)
    d1 = L.disc(s1, 2.4, c=3, name="BOT1")
    L.bot(d1.point(0, 0), 0)

    # 3. ghost run --------------------------------------------------------------
    for k in range(4):
        L.hop(cur, 3.6, 0.4, "jump", coins=2, coin_h=1.6)
        L.ghost(cur, 3.4, 3.4, on=1.8, off=1.4, ph=0.18 * k, c=2, name="GH%d" % k)
    L.hop(cur, 3.6, 0.4, "jump")
    e = L.plat(cur, 8, 8, c=1, name="E")
    L.check(e.point(1.0, 2.5), e.heading)

    # 4. crumble + sweeper (the route turns east) -------------------------------
    cur = L.side_cur(e, +1, along=-1.0)
    for k in range(4):
        L.hop(cur, 1.8 if k else 2.6, 0, "jump")
        L.crumble(cur, 3.2, 3.6, delay=0.55, respawn=3.0, c=3, name="CR%d" % k)
    L.hop(cur, 2.2, 0, "jump")
    f = L.plat(cur, 14, 9, c=0, name="F")
    L.sweeper(f, 8.0, 1.2, along=0.0, height=0.55, c=3)
    L.drone(up(f.point(-4.0, -3.0), 1.1), L.rel(f.heading, 6.0), 4.2)
    L.coin_line(f, 5, across=3.2)
    # friend #2: updraft to a high ledge
    us = L.side_cur(f, +1, along=-3.0)
    L.hop(us, 2.6, 0, "jump")
    up1 = L.plat(us, 5.0, 5.0, c=1, name="UP")
    L.updraft(up1.point(0, 0), 2.2, 10.0, 14.0, 0)
    L.hop(us, 3.2, 9.5, "updraft:10", coins=3, coin_h=1.5)
    led = L.plat(us, 5.0, 5.0, c=3, name="UPLEDGE")
    L.bot(led.point(0, 0), 1)

    # 4b. reverse conveyor + laser gates ------------------------------------
    L.hop(cur, 3.0, 0, "jump")
    cvb = L.conveyor(cur, 20, 4.4, 5.0, reverse=True, c=2, name="CV")
    for k, al in enumerate([-4.0, 4.0]):
        ax, ay, az = cvb.point(al, -(cvb.hw + 0.6))
        bx, by, bz = cvb.point(al, cvb.hw + 0.6)
        L.laser((ax, ay + 0.5, az), (bx, by + 0.5, bz), on=1.5, off=1.7, ph=0.5 * k)
    L.coin_line(cvb, 6, height=1.1, along0=-8.0, along1=8.0)
    L.hop(cur, 2.4, 0, "jump")
    hh = L.plat(cur, 6, 6, c=1, name="H")
    L.check(hh.point(0, 0), hh.heading)

    # 4c. rising platforms + turret --------------------------------------------
    L.hop(cur, 3.6, 0, "jump")
    L.mover(cur, 4, 4, (0, 3.5, 0), per=5.0, c=3, name="V1")
    L.hop(cur, 3.6, 0, "jump")
    v2 = L.plat(cur, 6, 5, c=0, name="V2")
    L.coin_line(v2, 3)
    L.hop(cur, 3.6, 0, "jump")
    L.mover(cur, 4, 4, (0, 3.5, 0), per=5.0, ph=0.5, c=2, name="V3")
    L.hop(cur, 3.6, 0, "jump")
    w = L.plat(cur, 10, 7, c=1, name="W")
    tp = L.side_cur(w, +1, along=1.0)
    L.hop(tp, 2.4, 1.2, "jump")
    ped = L.plat(tp, 3.4, 3.4, c=3, name="PED")
    L.turret(ped.point(0, 0), 24.0, 2.3)
    L.coin_line(w, 4, across=-2.0)

    # 5. bridge to the arena (turn back north) -----------------------------------
    cur = L.side_cur(w, -1, along=-2.5)
    L.hop(cur, 3.0, 0, "jump")
    g = L.plat(cur, 10, 6, c=2, name="G")
    L.check(g.point(0, 0), g.heading)
    L.hint(g.point(2.0), 5.0, "اهزم الحارس: اضرب قلبه المتوهّج بعد أن يهبط")
    L.hop(cur, 3.0, 0, "jump")
    br = L.plat(cur, 14, 4.4, c=3, name="BRIDGE")
    L.check(br.point(2.0, 0), br.heading)
    L.coin_line(br, 5)

    # 6. arena ---------------------------------------------------------------------
    L.hop(cur, 0.0, 0, "walk")
    R = 16.0
    arena = L.disc(cur, R, th=1.2, c=1, name="ARENA")
    ax, ay, az = arena.at(0)
    L.boss((ax, ay, az), R)
    L.goal((ax, ay, az - 12.5), True)
    # friend #3: ledge just outside the arena (reachable any time)
    el = L.exit_circle(arena, cur.h - 90 + 25)
    L.hop(el, 4.6, 1.5, "double", coins=3, coin_h=3.0)
    d3 = L.disc(el, 2.4, c=2, name="BOT3")
    L.bot(d3.point(0, 0), 2)
    L.coin_ring((ax, ay, az), 10.5, 16, y_off=1.0)
    return L


def gd_literal(v, depth=0):
    """Python (JSON-like) value -> GDScript literal text."""
    if v is None:
        return "null"
    if v is True:
        return "true"
    if v is False:
        return "false"
    if isinstance(v, int):
        return str(v)
    if isinstance(v, float):
        r = repr(v)
        return r if ("." in r or "e" in r or "n" in r) else r + ".0"
    if isinstance(v, str):
        esc = v.replace("\\", "\\\\").replace('"', '\\"').replace("\n", "\\n")
        return '"' + esc + '"'
    if isinstance(v, (list, tuple)):
        return "[" + ", ".join(gd_literal(x, depth + 1) for x in v) + "]"
    if isinstance(v, dict):
        return "{" + ", ".join("%s: %s" % (gd_literal(k), gd_literal(x, depth + 1)) for k, x in v.items()) + "}"
    raise TypeError("cannot serialise %r" % (v,))


def write_level_data(levels):
    """scripts/game/level_data.gd: an embedded copy of every level, so the game still finds its levels in an
    export where `*.json` is not part of the export filter."""
    out = ["class_name LevelData", "extends RefCounted",
           "## AUTO-GENERATED by tools/build_levels.py - do not edit by hand.",
           "## Embedded copy of levels/*.json (LevelLoader falls back to it when the JSON file cannot be opened,",
           "## e.g. in an export that does not include non-resource files).", "", "const LEVELS: Dictionary = {"]
    items = list(levels.items())
    for n, (path, data) in enumerate(items):
        out.append("\t%s: {" % gd_literal(path))
        head = {k: v for k, v in data.items() if k != "objects"}
        for k, v in head.items():
            out.append("\t\t%s: %s," % (gd_literal(k), gd_literal(v)))
        out.append('\t\t"objects": [')
        objs = data["objects"]
        for i, o in enumerate(objs):
            out.append("\t\t\t%s%s" % (gd_literal(o), "," if i < len(objs) - 1 else ""))
        out.append("\t\t],")
        out.append("\t}%s" % ("," if n < len(items) - 1 else ""))
    out.append("}")
    out.append("")
    with open(os.path.join(ROOT, "scripts", "game", "level_data.gd"), "w", encoding="utf-8") as f:
        f.write("\n".join(out))


BUILDERS = [level1, level2, level3, level4]


def main():
    quiet = "--quiet" in sys.argv
    os.makedirs(os.path.join(ROOT, "levels"), exist_ok=True)
    os.makedirs(os.path.join(ROOT, "docs", "level_maps"), exist_ok=True)
    errors = []
    embedded = {}
    for fn in BUILDERS:
        L = fn()
        if not quiet:
            print(L.report())
        errors.extend(L.errors)
        errors.extend(check_levels.check(L))
        if L.bots != 3:
            errors.append("L%d has %d bots (expected 3)" % (L.id, L.bots))
        coins = sum(len(o["pts"]) for o in L.objs if o["t"] == "coins")
        crates = sum(o.get("n", 0) for o in L.objs if o["t"] == "crate")
        print("Level %d: coins=%d crates=%d objects=%d" % (L.id, coins, crates, len(L.objs)))
        path = os.path.join(ROOT, "levels", "level_%d.json" % L.id)
        data = L.to_json()
        embedded["res://levels/level_%d.json" % L.id] = data
        with open(path, "w", encoding="utf-8") as f:
            json.dump(data, f, ensure_ascii=False, separators=(",", ":"))
        try:
            render_map(L, os.path.join(ROOT, "docs", "level_maps", "level_%d.png" % L.id))
        except Exception as ex:  # maps are optional
            print("  (map skipped: %s)" % ex)
    write_level_data(embedded)
    if errors:
        print("\nERRORS:")
        for e in errors:
            print("  " + e)
        sys.exit(1)
    print("\nAll levels OK.")


if __name__ == "__main__":
    main()
