"""Level 1 (Launch Station) and level 2 (Crystal Gardens). See build_levels.py."""
import math

from leveldsl import Level, Cur


def up(p, dy):
    return (p[0], p[1] + dy, p[2])


# ============================================================ LEVEL 1 - LAUNCH STATION
# Signature ideas: rotating turntables, sliding bridges, a bounce-pad tower, the first hover gaps, a timed
# target puzzle that opens the launch gate and a rocket-gantry elevator finale. Difficulty climbs steadily.
def level1():
    L = Level(1, "محطة الإطلاق", "launch", par=330)
    cur = Cur(0, 0, 0, 0)
    sp = L.disc(cur, 6.0, c=0, name="spawn")
    L.spawn = (0.0, 0.6, -6.0)
    L.hint((0, 0, -6.0), 5.0, "حرّك العصا اليسرى للمشي، وزر القفز للقفز")
    L.coin_ring((0, 0, -6.0), 3.6, 8)
    L.crate(sp.point(3.6, -3.2), 4)
    L.crate(sp.point(3.6, 3.2), 4)
    L.hint(sp.point(4.6, 0.0), 2.2, "زر الهجوم = لكمة (اضغط 3 مرات لسلسلة). اضغط مطولاً لدوران مشحون")

    # 1. first hops -------------------------------------------------------------
    L.section("1 first hops")
    L.hop(cur, 2.8, 0, "jump", coins=3)
    a = L.plat(cur, 7, 6, c=0, name="A")
    L.coin_line(a, 4)
    L.hop(cur, 3.4, 0.6, "jump", coins=3)
    b = L.plat(cur, 6, 5, c=1, name="B")
    L.hop(cur, 3.8, 0.0, "jump", coins=3)
    c1 = L.plat(cur, 11, 9, c=0, name="C1")
    L.hint(c1.point(-3.8), 3.5, "اضرب الأعداء باللكمة أو اقفز فوق رؤوسهم")
    L.hopper(c1.point(1.8, 2.2))
    L.crate(c1.point(4.0, -3.3), 5)
    L.check(c1.point(-3.0, -3.0), c1.heading)

    # 2. double jump + a friend behind a wall ------------------------------------
    L.section("2 double jump")
    L.hint(c1.point(4.4, 1.0), 2.6, "اضغط القفز مرتين للقفزة المزدوجة")
    L.hop(cur, 6.0, 1.6, "double", coins=5, coin_h=3.0)
    d = L.plat(cur, 9, 8, c=3, name="D")
    L.crate(d.point(1.0, 2.6), 5)
    s1 = L.side_cur(d, -1, along=0.5, side=True)
    L.hop(s1, 3.0, 0.0, "jump", coins=2)
    bl = L.plat(s1, 7, 5.4, c=2, name="BOT1")
    L.wall(bl.point(-0.6), (4.8, 2.6, 0.7), bl.heading, kind="metal", hp=2, side=True)
    L.hint(bl.point(-2.6), 2.0, "الجدار المتشقق ينكسر بالضربات القوية")
    L.bot(bl.point(2.0), 0)

    # 3. moving platforms ------------------------------------------------------------
    L.section("3 movers")
    L.hop(cur, 3.6, 0, "jump")
    L.mover(cur, 4, 4, (0, 0, 8), per=5.5, c=2, name="M1")
    L.hop(cur, 3.6, 0, "jump")
    e0 = L.plat(cur, 4.5, 4.5, c=0, name="E0")
    L.coin_line(e0, 2)
    L.hop(cur, 3.4, 0, "jump")
    L.mover(cur, 4, 4, (8, 0, 0), per=5.0, shift=-4.0, c=1, name="M2")
    L.hop(cur, 3.4, 0, "jump")
    L.mover(cur, 4, 4, (-8, 0, 0), per=5.0, shift=4.0, ph=0.5, c=3, name="M3")
    L.hop(cur, 3.4, 0, "jump")
    L.mover(cur, 4, 4, (0, 3.2, 0), per=4.5, c=2, name="M4")
    L.hop(cur, 3.4, 0, "jump", coins=3)
    e = L.plat(cur, 11, 9, c=1, name="E")
    L.check(e.point(-3.5, -3.0), e.heading)
    L.battery(e.point(3.2, 2.8), side=False)
    L.hint(e.point(-1.0, 2.0), 2.4, "البطارية تفرغ مع المشي والضربات، والطيران يستهلكها أكثر! البطاريات الاحتياطية تعيد شحنك")

    # 3b. hopper pit: a sunken yard of hoppers and crates, bounce out ------------------------------------
    L.section("3b hopper pit")
    cur = L.side_cur(e, -1, along=-2.0)
    L.hop(cur, 2.4, -2.0, "jump")
    pit = L.plat(cur, 14, 12, c=2, name="PIT")
    L.hopper(pit.point(-2.0, -3.0), 10.0, 6.0)
    L.hopper(pit.point(2.5, 3.0), 10.0, 6.0, ph=0.5)
    L.hopper(pit.point(4.5, -2.0), 10.0, 6.0, ph=0.8)
    L.crate(pit.point(-5.0, 4.0), 5)
    L.crate(pit.point(5.5, 4.5), 5)
    L.coin_ring(pit.point(0.0, 0.0), 3.5, 8)
    L.bounce(pit.point(5.6, 0.0), 22, 1.2, 1)
    L.hop(cur, 3.0, 3.6, "bounce:22:1.0", coins=3, coin_h=2.5)
    e2 = L.plat(cur, 9, 9, c=1, name="E2")
    L.check(e2.point(-2.5, -3.0), e2.heading)
    e = e2

    # 4. turntables (route turns east) ----------------------------------------------
    L.section("4 turntables")
    cur = L.side_cur(e, +1, along=2.0)
    L.hop(cur, 3.0, 0, "jump", coins=2)
    L.turn(cur, 4.0, 0.6, c=1, name="T1")
    L.hop(cur, 3.0, 0, "jump", coins=2)
    L.turn(cur, 3.5, -0.85, c=2, name="T2")
    L.hop(cur, 3.0, 0.5, "jump", coins=2)
    t3 = L.turn(cur, 4.0, 1.05, c=3, name="T3", spokes=6)
    s2 = L.exit_circle(t3, cur.h - 90, side=True)
    L.hop(s2, 6.4, 1.0, "double", coins=4, coin_h=3.0)
    b2 = L.disc(s2, 2.2, c=2, name="BOT2")
    L.bot(b2.point(0, 0), 1)
    L.hop(cur, 3.2, 0, "jump")
    f = L.plat(cur, 9, 8, c=0, name="F")
    L.check(f.point(-2.5, 2.6), f.heading)
    L.coin_line(f, 4, across=-2.5)

    # 5. arena: shield bot + drones -------------------------------------------------
    L.section("5 shield arena")
    L.hint(f.point(3.0), 3.0, "اضغط الاندفاع في الهواء لتطير أبعد")
    L.hop(cur, 7.6, 0, "dash", coins=5, coin_h=2.6)
    g = L.plat(cur, 18, 13, c=1, name="ARENA1")
    L.hint(g.point(-7.0), 3.0, "حامل الدرع يصدّ اللكمات من الأمام: التفّ خلفه أو اضربه بالدوران")
    L.shield(g.point(-1.0, -3.5), g.point(-1.0, 3.5))
    L.drone(up(g.point(3.0, -4.0), 1.2), L.rel(g.heading, 8.0), 4.5)
    L.drone(up(g.point(6.0, 4.0), 1.2), L.rel(g.heading, -8.0), 4.5, 0.5)
    L.crate(g.point(-5.5, 5.2), 5)
    L.crate(g.point(7.5, -5.2), 5)
    L.coin_ring(g.point(1.0, 0.0), 4.5, 10)
    L.check(g.point(7.5, 4.8), g.heading)

    # 5b. mover lattice: crossing movers at different speeds, then a tall hopper perch ----------------
    L.section("5b mover lattice")
    L.hop(cur, 3.4, 0, "jump")
    L.mover(cur, 3.6, 3.6, (9, 0, 0), per=3.4, shift=-4.5, c=1, name="ML1")
    L.hop(cur, 3.2, 0, "jump")
    L.mover(cur, 3.6, 3.6, (-9, 0, 0), per=3.0, shift=4.5, ph=0.3, c=3, name="ML2")
    L.hop(cur, 3.2, 0, "jump")
    L.mover(cur, 3.6, 3.6, (9, 0, 0), per=2.7, shift=-4.5, ph=0.6, c=1, name="ML3")
    L.hop(cur, 3.2, 0.8, "jump", coins=3)
    gm = L.plat(cur, 8, 8, c=0, name="GM")
    L.hopper(gm.point(0.5, 0.0), ph=0.6)
    L.check(gm.point(-2.5, 2.5), gm.heading)
    sbx = L.side_cur(gm, -1, along=1.0, side=True)
    L.hop(sbx, 3.2, 0, "jump")
    L.mover(sbx, 3.4, 3.4, (0, 4.5, 0), per=3.2, c=2, name="BXV")
    L.hop(sbx, 6.4, 0.8, "double", coins=3, coin_h=3.0)
    bx = L.disc(sbx, 2.0, c=3, name="BAT3")
    L.battery(bx.point(0, 0))

    # 6. sliding bridges ---------------------------------------------------------------
    L.section("6 sliding bridges")
    L.hint(g.point(8.2), 2.2, "الجسور تنزلق جانباً! الضوء الأحمر يعني أنها ستختفي")
    L.hop(cur, 2.4, 0, "jump")
    for k in range(5):
        if k:
            L.hop(cur, 1.6, 0, "jump")
        L.retract(cur, 3.6, 3.2, on=2.2, off=1.4, ph=0.2 * k, c=2, name="R%d" % k, side=1 if k % 2 == 0 else -1)
        L.coins([up(L.surfs[-1].point(0, 0), 1.2)])
    L.hop(cur, 2.0, 0, "jump")
    h0 = L.plat(cur, 8, 8, c=3, name="H0")
    L.check(h0.point(-2.5, -3.0), h0.heading)

    # 6b. satellite hop: small discs with drones, then two counter-rotating turntables ------------
    L.section("6b satellite hop")
    for kk in range(4):
        L.hop(cur, 3.6 + 0.3 * kk, 0.6 if kk % 2 else -0.3, "jump", coins=2)
        L.disc(cur, 1.9 - 0.1 * kk, c=kk % 4, name="SAT%d" % kk)
    d0 = L.surfs[-1]
    L.drone(up(d0.point(0.0, 0.0), 1.6), L.rel(cur.h, 0, 0, -9.0), 3.6, leash=3.0)
    L.hop(cur, 3.0, 0, "jump")
    L.turn(cur, 3.6, 1.1, c=2, name="TT1")
    L.hop(cur, 2.4, 0, "jump")
    L.turn(cur, 3.6, -1.25, c=1, name="TT2")
    L.hop(cur, 3.0, 0, "jump", coins=3)
    h = L.plat(cur, 9, 9, c=3, name="H")
    L.check(h.point(-2.5, -3.0), h.heading)
    L.hopper(h.point(1.5, 2.0))

    # 7. bounce tower -------------------------------------------------------------------
    L.section("7 bounce tower")
    L.bounce(h.point(2.6), 22, 1.2, 1)
    L.hop(cur, 3.0, 4.2, "bounce:22:1.0", coins=4, coin_h=3.0)
    i1 = L.plat(cur, 7, 7, c=0, name="I1")
    L.hopper(i1.point(0.5, 0.0))
    L.hop(cur, 3.0, 0, "jump")
    L.mover(cur, 4, 4, (0, 4.0, 0), per=4.0, c=2, name="V1")
    L.hop(cur, 3.0, 0.0, "jump")
    i2 = L.plat(cur, 7, 7, c=1, name="I2")
    L.hopper(i2.point(-1.0, 1.5), ph=0.5)
    L.bounce(i2.point(2.2), 24, 1.2, 1)
    L.hop(cur, 3.0, 4.6, "bounce:24:1.6", coins=4, coin_h=3.0)
    i3 = L.plat(cur, 11, 9, c=3, name="I3")
    L.check(i3.point(-3.5, -3.2), i3.heading)
    sb = L.side_cur(i3, -1, along=-2.0, side=True)
    L.hop(sb, 9.0, 0.3, "hover", coins=4, coin_h=3.0)
    bt = L.disc(sb, 2.2, c=2, name="BAT2")
    L.battery(bt.point(0, 0))

    # 8. speed pad + hover gaps -----------------------------------------------------------
    L.section("8 speed + hover")
    L.spad(i3.point(-1.0), i3.heading, 4.0, 3.0, 22.0, 3)
    L.hop(cur, 11.0, -1.5, "pad:22", coins=6, coin_h=3.5)
    j = L.plat(cur, 6, 5, c=0, name="J")
    L.hint(j.point(0.0), 3.0, "بعد القفزة المزدوجة اضغط القفز مطولاً لتحلّق (يستهلك البطارية!)")
    L.hop(cur, 9.0, 0.5, "hover", coins=4, coin_h=3.5)
    L.disc(cur, 2.6, c=1, name="J2")
    L.hop(cur, 9.5, 0.0, "hover", coins=4, coin_h=3.5)
    k0 = L.plat(cur, 8, 7, c=2, name="K0")
    L.check(k0.point(-2.0, 2.4), k0.heading)

    # 8b. long ride: a slow mover across the void while drones intercept ----------------------------
    L.section("8b drone ride")
    L.hop(cur, 3.0, 0, "jump")
    L.mover(cur, 5, 5, (0, 0, 16), per=9.0, c=1, name="RIDE")
    rd = L.surfs[-1]
    L.drone(up(rd.point(6.0, -4.0), 1.4), L.rel(cur.h, 8.0, 0, 0), 3.0, leash=4.5)
    L.drone(up(rd.point(13.0, 4.0), 1.4), L.rel(cur.h, -8.0, 0, 0), 3.4, 0.5, leash=4.5)
    L.hop(cur, 3.0, 0.8, "jump")
    L.disc(cur, 2.4, c=3, name="RDE")
    L.hop(cur, 3.2, 0.0, "jump", coins=3)
    L.mover(cur, 4, 4, (0, 3.5, 0), per=4.0, ph=0.25, c=2, name="RV")
    L.hop(cur, 3.2, 0.0, "jump")
    k = L.plat(cur, 10, 8, c=2, name="K")
    L.check(k.point(-2.0, 2.6), k.heading)

    # 9. turret walkway (route turns north-west) ----------------------------------------
    L.section("9 turret walk")
    cur = L.side_cur(k, -1, along=2.5)
    L.hint(k.point(2.5, -1.5), 2.6, "اضرب قذيفة المدفع لترتد عليه وتدمره!")
    L.hop(cur, 3.5, 0, "jump")
    L.mover(cur, 4, 4, (0, 0, 9), per=5.0, c=3, name="M5")
    L.hop(cur, 3.5, 0, "jump")
    l1 = L.plat(cur, 18, 6, c=1, name="L1")
    L.turret(l1.point(7.8, 0.0), 22.0, 2.2)
    L.shield(l1.point(-2.0, -1.5), l1.point(3.0, 1.5))
    L.coin_line(l1, 6, across=2.2)
    L.crate(l1.point(-7.5, -2.0), 5)

    # 9b. bridge-and-wheel combo: sliding bridges feeding fast turntables -------------------------
    L.section("9b bridges + wheels")
    L.hop(cur, 2.2, 0, "jump")
    L.retract(cur, 3.4, 3.0, on=1.9, off=1.3, ph=0.0, c=2, name="RW0", side=1)
    L.hop(cur, 2.2, 0.4, "jump")
    L.turn(cur, 3.2, 1.3, c=3, name="TW0")
    L.hop(cur, 2.2, 0.0, "jump")
    L.retract(cur, 3.4, 3.0, on=1.9, off=1.3, ph=0.5, c=2, name="RW1", side=-1)
    L.hop(cur, 2.2, 0.4, "jump")
    L.turn(cur, 3.2, -1.4, c=1, name="TW1")
    L.hop(cur, 2.4, 0.0, "jump")
    L.retract(cur, 3.4, 3.0, on=1.7, off=1.3, ph=0.25, c=2, name="RW2", side=1)
    L.hop(cur, 2.2, 0.0, "jump", coins=2)
    l2 = L.plat(cur, 8, 8, c=0, name="L2")
    L.check(l2.point(-2.0, 2.5), l2.heading)
    L.hopper(l2.point(1.5, -2.0), ph=0.3)

    # 10. target puzzle opens the launch gate ---------------------------------------------
    L.section("10 targets + gate")
    L.hop(cur, 3.0, 0, "jump")
    m = L.plat(cur, 15, 13, c=0, name="LAUNCHPAD")
    L.check(m.point(-5.5, 4.5), m.heading)
    L.hint(m.point(-4.0, 0.0), 3.0, "اضرب الأهداف الأربعة قبل انتهاء الوقت لفتح بوابة الإطلاق")
    L.targets([m.point(-2.0, -5.2), m.point(2.5, 5.2), m.point(5.0, -5.2), m.point(-4.5, 5.6)], "T1", time=7.0)
    L.gate(m.point(6.9), m.heading, "T1", w=12.0, h=4.0)
    L.coin_ring(m.point(0.0, 0.0), 3.0, 8)
    # friend 3: fast sliding bridges + hover on the right
    s3 = L.side_cur(m, +1, along=1.0, side=True)
    L.hop(s3, 2.0, 0, "jump")
    for kk in range(3):
        if kk:
            L.hop(s3, 1.4, 0, "jump")
        L.retract(s3, 3.0, 2.8, on=1.4, off=1.2, ph=0.25 * kk, c=3, name="RB%d" % kk, side=-1)
    L.hop(s3, 9.5, 0.0, "hover", coins=4, coin_h=3.0)
    b3 = L.disc(s3, 2.2, c=1, name="BOT3")
    L.bot(b3.point(0, 0), 2)

    # 11. rocket gantry elevator + final run ---------------------------------------------
    L.section("11 rocket elevator finale")
    L.hop(cur, 2.2, 0, "jump")
    L.lift(cur, 5, 5, (0, 14.0, 0), dur=5.0, c=3, name="LIFT")
    lt = L.surfs[-1]
    L.drone(up(lt.point(0.0, 0.0), 9.0), L.rel(cur.h, 6.0), 3.8, leash=4.0)
    L.coin_arc(up(lt.point(0, 3.4), 2.0), up(lt.point(0, 3.4), 14.0), 6, 0.6)
    L.hop(cur, 3.0, 0, "jump")
    n1 = L.plat(cur, 6, 5, c=2, name="N1")
    L.check(n1.point(0.0, 0.0), n1.heading)
    L.hop(cur, 2.0, 0, "jump")
    for kk in range(3):
        if kk:
            L.hop(cur, 1.5, 0, "jump")
        L.retract(cur, 3.2, 3.0, on=1.8, off=1.3, ph=0.22 * kk, c=1, name="RF%d" % kk, side=1 if kk % 2 else -1)
    L.hop(cur, 2.4, 0.5, "jump")
    L.turn(cur, 3.5, 1.5, c=3, name="TF")
    L.hop(cur, 3.2, 0.5, "jump", coins=3)
    L.mover(cur, 4, 4, (7, 0, 0), per=3.6, shift=-3.5, c=2, name="MF")
    L.hop(cur, 3.4, 0, "jump")
    n2 = L.plat(cur, 7, 7, c=1, name="N2")
    L.check(n2.point(-1.5, 2.0), n2.heading)
    L.shield(n2.point(1.0, -2.2), n2.point(1.0, 2.2))
    # last stretch: hover chain between rocket fins with a drone escort
    L.hop(cur, 8.8, 0.3, "hover", coins=4, coin_h=3.0)
    L.disc(cur, 2.0, c=2, name="HV1")
    L.drone(up(L.surfs[-1].point(0, 0), 2.5), L.rel(cur.h, 5.0), 3.0, leash=3.0)
    L.hop(cur, 6.2, 1.2, "double", coins=4, coin_h=3.0)
    L.disc(cur, 2.0, c=3, name="HV2")
    L.hop(cur, 9.0, 0.0, "hover", coins=4, coin_h=3.0)
    fin = L.plat(cur, 13, 11, c=3, name="FIN")
    L.goal(fin.point(2.5), False)
    L.coin_ring(fin.point(2.5), 3.8, 10)
    return L


# ============================================================ LEVEL 2 - CRYSTAL GARDENS
# Signature ideas: crumbling crystals, breakable crystal walls, swinging crystal pendulums, crystal-spider
# nests, two pylon memory puzzles, a spiral tower and a timed switch race. Harder rhythm than level 1.
def level2():
    L = Level(2, "حدائق الكريستال", "crystal", par=420)
    cur = Cur(0, 0, 0, 0)
    L.disc(cur, 5.5, c=0, name="spawn")
    L.spawn = (0.0, 0.6, -5.5)
    L.hint((0, 0, -8.0), 4.0, "الكريستالات المتوهجة تنهار تحت قدميك! لا تتوقف")

    # 1. crumbling road --------------------------------------------------------------------
    L.section("1 crumble road")
    first = None
    for k in range(7):
        L.hop(cur, 2.4 if k == 0 else 1.8, 0, "jump")
        t = L.crumble(cur, 3.2, 3.6, delay=0.55, respawn=3.5, c=3, name="CR%d" % k)
        L.coins([up(t.point(0, 0), 1.1)])
        first = first or t
    L.hop(cur, 2.0, 0, "jump")
    p1 = L.plat(cur, 10, 10, c=0, name="P1")
    L.check(p1.point(-3.0, 3.0), p1.heading)
    L.spider(p1.point(1.0, -1.5), 3.0)
    L.crate(p1.point(-3.5, -3.6), 5)
    # battery 1: crumble side path to a walled alcove
    sb = L.side_cur(p1, -1, along=-1.0, side=True)
    for k in range(2):
        L.hop(sb, 2.0 if k == 0 else 1.6, 0, "jump")
        L.crumble(sb, 3.0, 3.2, delay=0.5, respawn=3.0, c=3, name="BC%d" % k)
    L.hop(sb, 2.0, 0, "jump")
    al = L.plat(sb, 6, 5, c=2, name="ALC1")
    L.wall(al.point(-0.8), (4.4, 2.6, 0.7), al.heading, kind="crystal", hp=2, side=True)
    L.battery(al.point(1.6))

    # 2. crystal wall + phase rhythm -------------------------------------------------------
    L.section("2 wall + phase rhythm")
    L.wall(p1.point(4.4), (9.4, 3.0, 0.8), p1.heading, kind="crystal", hp=3)
    L.hint(p1.point(2.2, 2.5), 2.0, "حطّم جدار الكريستال بثلاث ضربات (الضربة الثالثة أقوى)")
    for k in range(6):
        L.hop(cur, 3.3 if k else 2.6, 0.0, "jump", coins=2)
        L.ghost(cur, 3.3, 3.3, on=1.9, off=1.3, ph=0.15 * k, c=2, name="GH%d" % k)
    L.hop(cur, 3.3, 0, "jump")
    p2 = L.plat(cur, 9, 9, c=1, name="P2")
    L.check(p2.point(-2.5, -3.0), p2.heading)

    # 3. swinging crystal pendulums (route turns east) ---------------------------------------
    L.section("3 pendulums")
    cur = L.side_cur(p2, +1, along=1.5)
    L.hint(p2.point(1.5, 3.2), 2.0, "اقفز على المنصات المتأرجحة في اللحظة المناسبة")
    L.hop(cur, 2.4, 0, "jump")
    L.disc(cur, 1.6, c=0, name="PL0")
    for k in range(3):
        L.hop(cur, 2.6, 0, "jump", coins=2)
        L.pend(cur, 3.2, 3.2, rope=7.5, amp=26.0, per=3.1, ph=0.33 * k, across=True, c=k % 4, name="PD%d" % k)
        L.hop(cur, 2.6, 0, "jump")
        L.disc(cur, 1.6, c=0, name="PL%d" % (k + 1))
    L.hop(cur, 2.6, 0, "jump")
    p3a = L.plat(cur, 7, 7, c=3, name="P3a")
    L.check(p3a.point(-2.0, 2.5), p3a.heading)

    # 3b. phase + crumble braid --------------------------------------------------------------
    L.section("3b phase/crumble braid")
    for kk in range(6):
        L.hop(cur, 2.4 if kk % 2 else 3.0, 0.3 if kk % 3 == 1 else 0.0, "jump", coins=1)
        if kk % 2 == 0:
            L.ghost(cur, 3.0, 3.2, on=1.6, off=1.2, ph=0.17 * kk, c=2, name="BG%d" % kk)
        else:
            L.crumble(cur, 3.0, 3.2, delay=0.45, respawn=2.6, c=3, name="BCR%d" % kk)
    L.hop(cur, 2.6, 0, "jump")
    p3 = L.plat(cur, 8, 8, c=3, name="P3")
    L.check(p3.point(-2.0, 2.5), p3.heading)
    L.crate(p3.point(2.0, -2.5), 5)

    # 4. spider nest arena + friend 1 --------------------------------------------------------
    L.section("4 spider nest")
    L.hop(cur, 3.4, -0.5, "jump", coins=3)
    arena = L.disc(cur, 8.5, c=1, name="NEST")
    cx, cy, cz = arena.at(0)
    for kk in range(3):
        a = math.radians(90 + 120 * kk)
        L.bumper((cx + 4.5 * math.cos(a), cy, cz + 4.5 * math.sin(a)), 0.9, 15, 2)
        L.spider((cx + 3.0 * math.cos(a + 1.0), cy, cz + 3.0 * math.sin(a + 1.0)), 3.5)
    L.coin_ring((cx, cy, cz), 6.5, 12)
    L.crate(arena.point(-6.5, 0.0), 6)
    sg = L.exit_circle(arena, cur.h - 90, side=True)
    for kk in range(3):
        L.hop(sg, 3.4, 1.5, "jump", coins=1, coin_h=1.4)
        L.ghost(sg, 3.3, 3.3, on=2.2, off=1.2, ph=0.2 * kk, c=3, name="GS%d" % kk)
    L.hop(sg, 3.6, 1.5, "jump", coins=2)
    alc = L.plat(sg, 5.0, 5.0, c=2, name="BOT1")
    L.bot(alc.point(0, 0), 0)

    # 4b. pinball run: a narrow crystal track lined with bumpers -------------------------------------
    L.section("4b pinball run")
    L.hop(cur, 3.0, 0, "jump")
    pr = L.plat(cur, 24, 5.0, c=2, name="PINBALL")
    for k in range(5):
        L.bumper(pr.point(-9.0 + k * 4.5, 1.6 if k % 2 else -1.6), 0.8, 13, k % 3)
    L.spider(pr.point(2.0, 0.0), 1.6)
    L.coin_line(pr, 7, height=1.1, along0=-10.5, along1=10.5)
    L.hop(cur, 2.6, 0, "jump")
    p4a = L.plat(cur, 7, 7, c=1, name="P4a")
    L.check(p4a.point(-2.0, 2.0), p4a.heading)

    # 5. pylon memory puzzle raises a bridge ------------------------------------------------
    L.section("5 pylons I")
    L.hop(cur, 3.4, 0.5, "jump")
    p4 = L.plat(cur, 13, 13, c=0, name="P4")
    L.check(p4.point(-5.0, -5.0), p4.heading)
    pts = [p4.point(1.0, -4.5), p4.point(4.0, 0.0), p4.point(1.0, 4.5)]
    L.pylons(p4.point(-1.0, 0.0), pts, [1, 0, 2], "PY1", r=7.0)
    L.hop(cur, 2.0, 0, "jump")
    for kk in range(4):
        if kk:
            L.hop(cur, 1.6, 0, "jump")
        L.ghost(cur, 3.4, 3.4, mode="switch", sid="PY1", c=0, name="BR%d" % kk)
        L.coins([up(L.surfs[-1].point(0, 0), 1.2)])
    L.hop(cur, 2.0, 0, "jump")
    p5a = L.plat(cur, 8, 8, c=1, name="P5a")
    L.check(p5a.point(-2.5, -3.0), p5a.heading)

    # 5b. swing-to-phase: leap from swinging crystals onto blinking holograms -------------------
    L.section("5b swing to phase")
    for kk in range(3):
        L.hop(cur, 2.6, 0, "jump", coins=1)
        L.pend(cur, 3.2, 3.2, rope=7.0, amp=24.0, per=2.9, ph=0.3 * kk, across=True, c=1, name="SW%d" % kk)
        L.hop(cur, 2.6, 0.3, "jump", coins=1)
        L.ghost(cur, 3.0, 3.0, on=1.5, off=1.1, ph=0.3 * kk + 0.1, c=2, name="SG%d" % kk)
    L.hop(cur, 2.6, 0, "jump")
    p5 = L.plat(cur, 9, 9, c=1, name="P5")
    L.check(p5.point(-2.5, -3.0), p5.heading)
    sb3 = L.side_cur(p5, -1, along=2.0, side=True)
    for kk in range(2):
        L.hop(sb3, 3.0, 1.0, "jump")
        L.ghost(sb3, 2.8, 2.8, on=1.2, off=1.2, ph=0.5 * kk, c=3, name="B3G%d" % kk)
    L.hop(sb3, 6.0, 1.0, "double", coins=3, coin_h=3.0)
    b3x = L.disc(sb3, 2.0, c=2, name="BAT3")
    L.battery(b3x.point(0, 0))

    # 6. spiral tower with crumbling steps ------------------------------------------------------
    L.section("6 spiral tower")
    L.hint(p5.point(2.5), 2.6, "اصعد البرج الحلزوني... بعض الدرجات تنهار!")
    for kk in range(9):
        L.hop(cur, 3.2, 1.25, "jump", coins=1, coin_h=1.4)
        if kk in (2, 5, 7):
            L.crumble(cur, 3.4, 3.4, delay=0.45, respawn=2.5, c=3, name="SP%d" % kk)
        else:
            L.plat(cur, 3.4, 3.4, c=kk % 4, name="SP%d" % kk)
        cur.turn(40)
    L.hop(cur, 3.4, 1.2, "jump", coins=2)
    top = L.plat(cur, 12, 9, c=2, name="TOP")
    L.sweeper(top, 7.5, 1.2, along=-2.0, height=0.55, c=2)
    L.spider(top.point(3.5, 2.0), 2.5)
    L.check(top.point(4.5, -3.0), top.heading)
    sbt = L.side_cur(top, +1, along=3.0, side=True)
    L.hop(sbt, 6.4, 1.2, "double", coins=4, coin_h=3.0)
    bt2 = L.disc(sbt, 2.2, c=1, name="BAT2")
    L.battery(bt2.point(0, 0))

    # 7. spike corridor with swinging maces (route turns west) ---------------------------------
    L.section("7 spikes + maces")
    cur = L.side_cur(top, -1, along=0.5)
    L.hop(cur, 4.0, -0.5, "jump", coins=3)
    sc = L.plat(cur, 26, 4.6, c=0, name="SPIKES")
    for kk, al in enumerate([-8.0, -1.5, 5.0]):
        L.spikes(sc.point(al, 0), 4.2, 3.6, per=2.8, ph=0.3 * kk, out=0.5, ry=-sc.heading)
    for kk, al in enumerate([-4.8, 1.8, 8.5]):
        x, y, z = sc.point(al, 0)
        L.swing((x, y + 7.5, z), 6.2, 50.0, 2.4, 0.25 * kk, sc.heading + 90, "mace", 0.9)
    L.coin_line(sc, 6, height=1.1, along0=-11.0, along1=11.0)
    # friend 2: dead-end crumbles with a hover finish
    sf = L.side_cur(sc, +1, along=3.0, side=True)
    for kk in range(3):
        L.hop(sf, 1.6 if kk else 2.2, 0, "jump")
        L.crumble(sf, 3.0, 3.2, delay=0.5, respawn=3.0, c=3, name="FC%d" % kk)
    L.hop(sf, 9.0, 0.0, "hover", coins=3, coin_h=3.0)
    fb = L.disc(sf, 2.2, c=1, name="BOT2")
    L.bot(fb.point(0, 0), 1)
    L.hop(cur, 2.4, 0, "jump")
    p7a = L.plat(cur, 7, 7, c=3, name="P7a")
    L.check(p7a.point(-2.0, 2.5), p7a.heading)

    # 7b. narrow crystal bridge: spiders chase you while walls block the way ----------------------
    L.section("7b spider bridge")
    L.hop(cur, 2.6, 0, "jump")
    nb = L.plat(cur, 24, 3.2, c=1, name="NARROW")
    L.wall(nb.point(-4.0), (3.0, 2.6, 0.7), nb.heading, kind="crystal", hp=2)
    L.wall(nb.point(5.0), (3.0, 2.6, 0.7), nb.heading, kind="crystal", hp=2)
    L.spider(nb.point(0.5, 0.0), 1.2)
    L.spider(nb.point(9.0, 0.0), 1.2)
    L.coin_line(nb, 7, height=1.1, along0=-10.5, along1=10.5)
    L.hop(cur, 2.6, 0, "jump")
    p7 = L.plat(cur, 8, 8, c=3, name="P7")
    L.check(p7.point(-2.0, 2.5), p7.heading)

    # 8. swinging chain along the path ------------------------------------------------------
    L.section("8 pendulum chain")
    for kk in range(3):
        L.hop(cur, 4.0, 0.0, "jump", coins=2)
        L.pend(cur, 3.4, 3.4, rope=8.0, amp=18.0, per=2.6, ph=0.4 * kk, across=False, c=1 + kk % 3, name="PC%d" % kk)
        L.hop(cur, 4.0, 0.0, "jump")
        if kk < 2:
            L.disc(cur, 1.7, c=0, name="PCP%d" % kk)
    p8 = L.plat(cur, 14, 14, c=2, name="P8")
    L.check(p8.point(-5.5, -5.5), p8.heading)

    # 9. pylons II (longer sequence) opens the gate -----------------------------------------
    L.section("9 pylons II + gate")
    pts2 = [p8.point(-2.0, -5.0), p8.point(2.5, -4.0), p8.point(4.0, 1.0), p8.point(0.5, 5.0)]
    L.pylons(p8.point(-2.0, 1.0), pts2, [2, 0, 3, 1, 0], "PY2", r=8.0)
    L.gate(p8.point(6.9), p8.heading, "PY2", w=13.0, h=4.0)
    L.spider(p8.point(3.0, 4.0), 2.5)

    # 10. switch race: hit the switch, cross the phase bridge before it fades ---------------
    L.section("10 switch race")
    L.hop(cur, 2.6, 0, "jump")
    q = L.plat(cur, 6, 6, c=1, name="Q")
    L.switch(q.point(-0.5), "RACE", 9.0, 2)
    L.hint(q.point(-2.0), 2.0, "دُس على المفتاح ثم اركض! الجسر يختفي بعد 9 ثوانٍ")
    L.hop(cur, 2.0, 0, "jump")
    for kk in range(6):
        if kk:
            L.hop(cur, 1.8 if kk % 2 else 2.6, 0.4 if kk % 3 == 2 else 0.0, "jump")
        L.ghost(cur, 3.2, 3.2, mode="switch", sid="RACE", c=0, name="RC%d" % kk)
        L.coins([up(L.surfs[-1].point(0, 0), 1.2)])
    L.hop(cur, 2.2, 0, "jump")
    p9a = L.plat(cur, 8, 8, c=3, name="P9a")
    L.check(p9a.point(-2.5, 3.0), p9a.heading)

    # 10b. mace gauntlet over crumbling crystals ---------------------------------------------
    L.section("10b mace gauntlet")
    for kk in range(5):
        L.hop(cur, 2.0 if kk else 2.4, 0.0, "jump")
        cr = L.crumble(cur, 3.4, 3.6, delay=0.6, respawn=3.0, c=3, name="MG%d" % kk)
        x, y, z = cr.point(0, 0)
        if kk % 2 == 0:
            L.swing((x, y + 7.0, z), 6.0, 55.0, 2.2, 0.27 * kk, cr.heading + 90, "mace", 0.85)
        L.coins([up(cr.point(0, 0), 1.2)])
    L.hop(cur, 2.4, 0, "jump")
    p9 = L.plat(cur, 9, 9, c=3, name="P9")
    L.check(p9.point(-2.5, 3.0), p9.heading)
    L.spider(p9.point(1.0, -2.0), 2.5)

    # 11. bounce-flower islands to the goal + friend 3 ---------------------------------------
    L.section("11 bounce flowers finale")
    L.bounce(p9.point(3.0), 24, 1.2, 1)
    L.hop(cur, 5.0, 3.0, "bounce:24:1.6", coins=4, coin_h=3.5)
    i1 = L.disc(cur, 3.0, c=1, name="I1")
    L.bounce(i1.point(0, 0), 24, 1.2, 1)
    L.hop(cur, 5.0, 2.5, "bounce:24:3.0", coins=4, coin_h=3.5)
    i2 = L.disc(cur, 3.0, c=2, name="I2")
    L.bounce(i2.point(0, 0), 25, 1.2, 1)
    s3 = L.exit_circle(i2, cur.h + 90, side=True)
    L.hop(s3, 5.0, 2.0, "bounce:25:3.0", coins=3, coin_h=3.0)
    b3 = L.disc(s3, 2.4, c=3, name="BOT3")
    L.bot(b3.point(0, 0), 2)
    L.hop(cur, 5.0, 2.5, "bounce:25:3.0", coins=4, coin_h=3.5)
    for kk in range(3):
        L.crumble(cur, 3.2, 3.6, delay=0.4, respawn=3.0, c=3, name="FCR%d" % kk)
        L.hop(cur, 1.8, 0, "jump")
    fin = L.plat(cur, 13, 11, c=3, name="FIN")
    L.goal(fin.point(2.5), False)
    L.coin_ring(fin.point(2.5), 3.8, 10)
    return L
