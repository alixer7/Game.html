"""Level 3 (Gravity Foundry), level 4 (Ice Comet - new) and level 5 (Galaxy Core + boss). See build_levels.py."""
import math

from leveldsl import Level, Cur


def up(p, dy):
    return (p[0], p[1] + dy, p[2])


# ============================================================ LEVEL 3 - GRAVITY FOUNDRY
# Signature ideas: conveyors and saws, hydraulic crushers you time AND ride, laser gates, a push-block
# puzzle, zero-g, flame jets, an electrified floor, sweeping lasers and a crusher staircase finale.
def level3():
    L = Level(3, "مصنع الجاذبية", "foundry", par=420)
    cur = Cur(0, 0, 0, 0)
    L.disc(cur, 5.5, c=0, name="spawn")
    L.spawn = (0.0, 0.6, -5.5)
    L.hint((0, 0, -8.0), 4.0, "السيور تدفعك للخلف! لا تلمس المناشير")

    # 1. reverse conveyor + saws -----------------------------------------------------------
    L.section("1 conveyor + saws")
    L.hop(cur, 2.4, 0, "jump")
    a = L.plat(cur, 5, 5, c=0, name="A")
    L.hop(cur, 2.4, 0, "jump")
    cv = L.conveyor(cur, 24, 4.4, 4.0, reverse=True, c=1, name="CV1")
    for k, al in enumerate([-6.0, 1.0, 7.5]):
        x, y, z = cv.point(al, -2.0)
        L.saw((x, y + 0.8, z), L.rel(cv.heading, 4.0), per=3.0, ph=0.3 * k, r=0.8)
    L.coin_line(cv, 6, height=1.1, along0=-10.0, along1=10.0)
    L.hop(cur, 2.4, 0, "jump")
    b = L.plat(cur, 8, 7, c=2, name="B")
    L.check(b.point(-2.0, 2.4), b.heading)
    L.crate(b.point(2.0, -2.4), 5)

    # 2. crusher corridor (ride a crusher to the battery ledge) --------------------------------
    L.section("2 crusher corridor")
    L.hint(b.point(2.5, 1.0), 2.2, "المكابس تسحق كل ما تحتها! مرّ بعد أن ترتفع... أو اركبها")
    L.hop(cur, 2.4, 0, "jump")
    cc = L.plat(cur, 28, 5.0, c=0, name="CRUSH")
    for k, al in enumerate([-9.0, -3.0, 3.0, 9.0]):
        L.crusher(cc, al, 0.0, (3.6, 2.0, 3.4), h=3.6, per=3.2, ph=0.22 * k)
    L.coin_line(cc, 8, height=1.1, along0=-12.0, along1=12.0)
    x, y, z = cc.point(9.0, 0.0)
    s_b = L.side_cur(cc, +1, along=9.0, y=y + 6.0, side=True)
    s_b.last = None
    s_b.fwd(0.4)
    led = L.plat(s_b, 4.0, 4.0, c=3, name="BATL")
    L.hint(cc.point(9.0, -1.6), 1.4, "اركب سطح المكبس وهو يرتفع لتصل إلى البطارية")
    L.battery(led.point(0, 0))
    L.hop(cur, 2.4, 0, "jump")
    c0 = L.plat(cur, 8, 8, c=1, name="C0")
    L.check(c0.point(-2.0, 2.5), c0.heading)

    # 2b. furnace elevator: a slow lift while drones attack, landing between flame jets ---------------
    L.section("2b furnace elevator")
    L.hop(cur, 2.2, 0, "jump")
    L.lift(cur, 5, 5, (0, 10.0, 6.0), dur=4.5, c=3, name="FLIFT")
    fl = L.surfs[-1]
    L.drone(up(fl.point(0.0, 0.0), 6.0), L.rel(cur.h, 6.0), 3.2, leash=4.0)
    L.drone(up(fl.point(4.0, 0.0), 9.0), L.rel(cur.h, -6.0), 3.6, 0.5, leash=4.0)
    L.hop(cur, 2.6, 0, "jump")
    fx = L.plat(cur, 12, 5, c=0, name="FURN")
    L.geyser(fx.point(-2.5, 0.0), h=4.5, power=0.0, per=2.4, dur=0.9, ph=0.0, kind="flame")
    L.geyser(fx.point(2.0, 0.0), h=4.5, power=0.0, per=2.4, dur=0.9, ph=0.5, kind="flame")
    L.hop(cur, 2.6, -1.0, "jump")
    c_ = L.plat(cur, 8, 8, c=1, name="C")
    L.check(c_.point(-2.0, 2.5), c_.heading)

    # 3. updraft + laser corridor + friend 1 -----------------------------------------------------
    L.section("3 updraft + lasers")
    L.hint(c_.point(-0.5), 2.4, "ادخل عمود الهواء لترتفع")
    L.updraft(c_.point(1.5, 0), 2.2, 10.0, 14.0, 0)
    L.coin_ring(c_.point(1.5, 0), 1.4, 8, y_off=4.5)
    L.hop(cur, 3.2, 9.0, "updraft:10", coins=3, coin_h=1.5)
    u1 = L.plat(cur, 28, 5.2, c=3, name="U1")
    hw = u1.hw + 0.6
    for k, al in enumerate([-9.0, -3.0, 3.0, 9.0]):
        ax, ay, az = u1.point(al, -hw)
        bx, by, bz = u1.point(al, hw)
        L.laser((ax, ay + 0.5, az), (bx, by + 0.5, bz), on=1.5, off=1.6, ph=0.25 * k)
    L.coin_line(u1, 8, height=1.2, along0=-11.0, along1=11.0)
    L.check(u1.point(12.0, 1.5), u1.heading)
    sl = L.side_cur(u1, +1, along=-3.0, side=True)
    L.hop(sl, 2.6, 0, "jump", coins=2)
    lb = L.plat(sl, 14, 4.6, c=1, name="LB")
    for k, al in enumerate([-3.5, 0.5, 4.0]):
        ax, ay, az = lb.point(al, -lb.hw - 0.6)
        bx, by, bz = lb.point(al, lb.hw + 0.6)
        L.laser((ax, ay + 0.5, az), (bx, by + 0.5, bz), on=1.2, off=1.4, ph=0.33 * k, side=True)
    L.bot(lb.point(5.6, 0), 0)

    # 3b. gear bridge: spinning gears, the middle one swept by a laser ----------------------------------
    L.section("3b gear bridge")
    cur = L.side_cur(u1, -1, along=11.0)
    L.hop(cur, 2.6, 0, "jump")
    L.turn(cur, 3.6, 1.0, c=1, name="GR1", spokes=8)
    L.hop(cur, 2.4, 0, "jump")
    g2 = L.turn(cur, 4.4, -0.8, c=3, name="GR2", spokes=8)
    gx, gy, gz = g2.at(0)
    L.sweep((gx, gy, gz), 4.2, 0.55, 2.0, 1, 0.0)
    L.hop(cur, 2.4, 0, "jump")
    L.turn(cur, 3.6, 1.2, c=1, name="GR3", spokes=8)
    L.hop(cur, 2.6, 0, "jump", coins=2)
    gb = L.plat(cur, 7, 7, c=2, name="GB")
    L.check(gb.point(-2.0, 2.0), gb.heading)
    sgb = L.side_cur(gb, +1, along=0.0, side=True)
    L.hop(sgb, 3.0, 0, "jump")
    L.mover(sgb, 3.4, 3.4, (0, 0, 7), per=2.8, c=3, name="GBM")
    L.hop(sgb, 6.2, 1.0, "double", coins=3, coin_h=3.0)
    gbb = L.disc(sgb, 2.0, c=1, name="BAT3")
    L.battery(gbb.point(0, 0))

    # 4. push-block puzzle -------------------------------------------------------------------------------
    L.section("4 push-block puzzle")
    L.hop(cur, 3.0, 0, "jump")
    pz = L.plat(cur, 16, 14, c=2, name="PUZZLE")
    L.hint(pz.point(-6.0, 0.0), 3.0, "الكم الصندوق الثقيل وادفعه فوق اللوح لفتح البوابة")
    L.block(pz.point(-3.0, -4.0))
    L.plate(pz.point(3.0, 2.0), "BLK")
    L.gate(pz.point(7.6), pz.heading, "BLK", w=13.0, h=4.0)
    L.tm(False, 25.0)
    L.check(pz.point(-6.5, 5.0), pz.heading)
    L.coin_ring(pz.point(0.0, 0.0), 4.0, 10)

    # 5. zero-g crossing with friend 2 -----------------------------------------------------------
    L.section("5 zero-g")
    L.hop(cur, 2.0, 0, "jump")
    zp = L.plat(cur, 5, 6, c=0, name="ZP")
    L.hint(zp.point(0.0), 3.0, "فقاعة انعدام الجاذبية! اقفز بعيداً")
    gap_start = cur.p
    L.hop(cur, 16.0, 0, "zerog")
    dx, dz = math.sin(math.radians(cur.h)), -math.cos(math.radians(cur.h))
    zc = (gap_start[0] + dx * 8.0, gap_start[1] + 3.0, gap_start[2] + dz * 8.0)
    L.zerog(zc, 11.0, 3)
    L.coin_ring(zc, 6.0, 10, y_off=0.5)
    L.bot((zc[0], zc[1] + 2.5, zc[2]), 1)
    z1 = L.plat(cur, 9, 8, c=0, name="Z1")
    L.check(z1.point(-2.0, 2.5), z1.heading)

    # 6. turret gallery with shield bots and flame jets ----------------------------------------
    L.section("6 turret gallery")
    L.hint(z1.point(2.5), 2.6, "المدافع تطلق النار! أعد قذائفها إليها باللكمة")
    L.hop(cur, 2.4, 0, "jump")
    tg = L.plat(cur, 32, 5.0, c=2, name="GAL")
    for k, (al, sg) in enumerate([(-10.0, +1), (0.0, -1), (10.0, +1)]):
        sc = L.side_cur(tg, sg, along=al)
        L.hop(sc, 2.4, 1.4, "jump", coins=1, coin_h=1.4)
        ped = L.plat(sc, 3.4, 3.4, c=3, name="PED%d" % k)
        L.turret(ped.point(0, 0), 24.0, 2.3, 0.3 * k)
    for k, al in enumerate([-5.0, 5.0, 13.0]):
        L.geyser(tg.point(al, 0.0), h=4.5, power=0.0, per=2.6, dur=0.9, ph=0.35 * k, kind="flame")
    L.shield(tg.point(-13.0, 0.0), tg.point(-6.5, 0.0))
    L.coin_line(tg, 8, height=1.1, along0=-14.0, along1=14.0, across=1.6)
    L.check(tg.point(15.0, 0), tg.heading)

    # 6b. conveyor duel: alternating belts with a laser carousel at the junction ------------------------
    L.section("6b conveyor duel")
    L.hop(cur, 2.4, 0, "jump")
    cd1 = L.conveyor(cur, 14, 4.4, 5.0, reverse=True, c=1, name="CD1")
    x, y, z = cd1.point(2.0, -1.6)
    L.saw((x, y + 0.8, z), L.rel(cd1.heading, 3.2), per=2.0, r=0.8)
    L.hop(cur, 2.0, 0, "jump")
    jn = L.disc(cur, 5.0, c=2, name="JUNC")
    jx, jy, jz = jn.at(0)
    L.sweep((jx, jy, jz), 4.8, 0.55, 1.8, 2, 0.1)
    L.hop(cur, 2.0, 0, "jump")
    cd2 = L.conveyor(cur, 14, 4.4, 5.5, reverse=True, c=3, name="CD2")
    for k, al in enumerate([-3.0, 3.5]):
        L.crusher(cd2, al, 0.0, (3.6, 1.6, 3.4), h=3.4, per=2.4, ph=0.4 * k)
    L.hop(cur, 2.2, 0, "jump")
    c6 = L.plat(cur, 8, 8, c=0, name="C6")
    L.check(c6.point(-2.0, 2.5), c6.heading)

    # 6c. sky-lift under fire: a horizontal lift across the void, flame jets guard the landing -----------
    L.section("6c sky-lift")
    L.hop(cur, 2.4, 0, "jump")
    L.lift(cur, 5, 5, (0, 2.0, 16.0), dur=5.5, c=3, name="SKY")
    sk = L.surfs[-1]
    L.turret(c6.point(2.5, 3.0), 30.0, 2.0, 0.2, lead=0.7)
    L.hop(cur, 2.4, 0, "jump")
    sl2 = L.plat(cur, 12, 5, c=1, name="SKYL")
    L.geyser(sl2.point(-2.0, 0.0), h=4.5, power=0.0, per=2.0, dur=0.8, ph=0.0, kind="flame")
    L.geyser(sl2.point(2.0, 0.0), h=4.5, power=0.0, per=2.0, dur=0.8, ph=0.5, kind="flame")
    L.hop(cur, 2.4, -2.0, "jump")
    c6b = L.plat(cur, 8, 8, c=0, name="C6b")
    L.check(c6b.point(-2.0, 2.5), c6b.heading)

    # 7. electric floor, then the laser carousel --------------------------------------------------
    L.section("7 electric floor + carousel")
    L.hop(cur, 2.6, 0, "jump")
    ef = L.plat(cur, 14, 12, c=0, name="ELEC")
    L.elec(ef, 12.0, 10.0, cell=2.0, per=1.1, pattern="checker")
    L.hint(ef.point(-6.2), 2.0, "البلاطات المكهربة تتبدل! قف على البلاطات المطفأة")
    L.hop(cur, 2.6, 0, "jump")
    car = L.disc(cur, 7.5, c=1, name="CAROUSEL")
    cxx, cyy, czz = car.at(0)
    L.sweep((cxx, cyy, czz), 7.2, 0.55, 1.35, 2, 0.0)
    L.coin_ring((cxx, cyy, czz), 4.5, 10, y_off=1.2)
    L.hop(cur, 2.6, 0, "jump")
    c7 = L.plat(cur, 8, 8, c=3, name="C7")
    L.check(c7.point(-2.0, 2.5), c7.heading)

    # 8. conveyor under crushers (route turns east) ----------------------------------------------
    L.section("8 conveyor + crushers")
    cur = L.side_cur(c7, +1, along=1.5)
    L.hop(cur, 2.4, 0, "jump")
    c8 = L.conveyor(cur, 26, 4.6, 5.0, reverse=False, c=3, name="CV2")
    for k, al in enumerate([-7.0, 0.0, 7.0]):
        L.crusher(c8, al, 0.0, (3.8, 2.0, 3.6), h=3.6, per=2.6, ph=0.3 * k)
    L.coin_line(c8, 6, height=1.1, along0=-11.0, along1=11.0)
    L.hop(cur, 2.4, 0, "jump")
    c9 = L.plat(cur, 8, 8, c=0, name="C9")
    L.check(c9.point(-2.0, 2.5), c9.heading)
    L.shield(c9.point(1.0, -2.5), c9.point(1.0, 2.5))

    # 9. saw shaft: updraft through patrolling saws, battery 2 --------------------------------------
    L.section("9 saw shaft")
    L.updraft(c9.point(2.0, 0), 2.2, 12.0, 13.0, 0)
    x, y, z = c9.point(2.0, 0)
    L.saw((x, y + 5.0, z), L.rel(c9.heading, 4.0), per=2.4, r=0.9)
    L.saw((x, y + 8.5, z), L.rel(c9.heading, -4.0), per=2.0, ph=0.5, r=0.9)
    L.hop(cur, 3.2, 11.0, "updraft:12", coins=3, coin_h=1.5)
    hi = L.plat(cur, 10, 8, c=2, name="HIGH")
    L.check(hi.point(-2.5, 2.5), hi.heading)
    sbt = L.side_cur(hi, -1, along=0.0, side=True)
    L.hop(sbt, 9.2, 0.0, "hover", coins=4, coin_h=3.0)
    bt2 = L.disc(sbt, 2.2, c=1, name="BAT2")
    L.battery(bt2.point(0, 0))

    # 9b. saw bubble: a zero-g crossing with saws patrolling inside ----------------------------------
    L.section("9b saw bubble")
    L.hop(cur, 2.4, 0, "jump")
    zb = L.plat(cur, 5, 5, c=0, name="ZB")
    gs = cur.p
    L.hop(cur, 15.0, 0, "zerog")
    dx, dz = math.sin(math.radians(cur.h)), -math.cos(math.radians(cur.h))
    zc = (gs[0] + dx * 7.5, gs[1] + 3.0, gs[2] + dz * 7.5)
    L.zerog(zc, 10.0, 3)
    L.saw((zc[0] - dz * 4.0, zc[1], zc[2] + dx * 4.0), (dz * 8.0, 0.0, -dx * 8.0), per=3.2, r=1.0)
    L.saw((zc[0] + dz * 4.0, zc[1] + 3.0, zc[2] - dx * 4.0), (-dz * 8.0, 0.0, dx * 8.0), per=2.6, ph=0.5, r=1.0)
    L.coin_ring(zc, 5.0, 10)
    L.plat(cur, 8, 8, c=1, name="ZB2")
    L.check(L.surfs[-1].point(-2.0, 2.5), cur.h)

    # 10. flame-jet bridge with spinning saws --------------------------------------------------
    L.section("10 flame bridge")
    L.hop(cur, 2.4, 0, "jump")
    fb = L.plat(cur, 22, 3.6, c=1, name="FLAME")
    for k, al in enumerate([-7.0, -2.5, 2.0, 6.5]):
        L.geyser(fb.point(al, 0.0), h=5.0, power=0.0, per=2.2, dur=0.8, ph=0.25 * k, kind="flame")
    L.coin_line(fb, 6, height=1.1, along0=-9.5, along1=9.5)
    L.hop(cur, 2.4, 0, "jump")
    c10a = L.plat(cur, 8, 8, c=3, name="C10a")
    L.check(c10a.point(-2.0, 2.5), c10a.heading)

    # 10b. charged floor on a moving belt + turret crossfire --------------------------------------------
    L.section("10b charged belt")
    L.hop(cur, 2.4, 0, "jump")
    eb = L.conveyor(cur, 20, 6.0, 3.0, reverse=True, c=2, name="EBELT")
    L.elec(eb, 18.0, 5.0, cell=2.0, per=1.0, pattern="stripes")
    sp1 = L.side_cur(eb, +1, along=6.0)
    L.hop(sp1, 2.4, 1.4, "jump")
    pd1 = L.plat(sp1, 3.4, 3.4, c=3, name="EPED")
    L.turret(pd1.point(0, 0), 22.0, 2.2, 0.2, lead=0.6)
    L.hop(cur, 2.4, 0, "jump")
    c10 = L.plat(cur, 8, 8, c=3, name="C10")
    L.check(c10.point(-2.0, 2.5), c10.heading)
    L.shield(c10.point(1.0, -2.5), c10.point(1.0, 2.5))

    # 11. crusher staircase finale + friend 3 ------------------------------------------------------
    L.section("11 crusher stairs finale")
    L.hint(c10.point(2.0), 2.4, "اركب أسطح المكابس وهي ترتفع لتصل إلى الأعلى")
    L.hop(cur, 2.0, 0, "jump")
    for k in range(3):
        L.crusher_step(cur, 7.0, 5.0, (3.4, 1.4, 3.4), 4.2, 3.6, 0.3 * k, along_c=1.0, c=k % 4, name="ST%d" % k)
        L.hop(cur, 2.0, 4.6, "jump", coins=2)
    top = L.plat(cur, 12, 10, c=2, name="FIN")
    L.goal(top.point(2.5), False)
    L.coin_ring(top.point(2.5), 3.8, 10)
    sf = L.side_cur(top, +1, along=-3.0, side=True)
    L.hop(sf, 6.4, 1.0, "double", coins=3, coin_h=3.0)
    fb3 = L.disc(sf, 2.2, c=3, name="BOT3")
    L.bot(fb3.point(0, 0), 2)
    return L


# ============================================================ LEVEL 4 - ICE COMET (new)
# Signature ideas: slippery ice, falling icicles, gusting wind on narrow bridges, rolling drums, snowball
# artillery, steam geysers that launch you, icy turntables and swinging ice blocks.
def level4():
    L = Level(4, "المذنّب الجليدي", "ice", par=420)
    cur = Cur(0, 0, 0, 0)
    sp = L.disc(cur, 5.5, c=0, name="spawn")
    L.spawn = (0.0, 0.6, -5.5)
    L.hint((0, 0, -5.5), 4.0, "مرحباً بك على المذنّب الجليدي!")

    # 1. ice-slide practice --------------------------------------------------------------------
    L.section("1 ice slides")
    L.hint(sp.point(4.0), 2.2, "الجليد زلق! خفّف سرعتك قبل الحافة")
    for k in range(3):
        L.hop(cur, 3.0 + 0.4 * k, 0.0, "jump", coins=2)
        L.plat(cur, 9 - k, 4.6 - 0.4 * k, c=0, name="ICE%d" % k, ice=True)
    L.hop(cur, 3.4, 0.5, "jump")
    p1 = L.plat(cur, 9, 9, c=1, name="P1")
    L.check(p1.point(-2.5, 2.5), p1.heading)
    L.hopper(p1.point(1.5, -2.0))

    # 2. icicle canyon -----------------------------------------------------------------------------
    L.section("2 icicle canyon")
    L.hint(p1.point(3.0), 2.4, "انتبه للرقاقات الجليدية فوقك! استمر بالحركة")
    L.hop(cur, 2.6, 0, "jump")
    can = L.plat(cur, 32, 6, c=0, name="CANYON")
    for k in range(8):
        al = -13.0 + k * 3.6
        ac = (-1.5 if k % 2 else 1.5)
        L.icicle(up(can.point(al, ac), 6.0), 1.6, 1.9)
    L.coin_line(can, 8, height=1.1, along0=-13.0, along1=13.0)
    L.crate(can.point(-6.0, -2.4), 5)
    L.hop(cur, 2.6, 0, "jump")
    p2 = L.plat(cur, 8, 8, c=2, name="P2")
    L.check(p2.point(-2.0, 2.5), p2.heading)

    # 3. wind bridge -------------------------------------------------------------------------------
    L.section("3 wind bridge")
    L.hint(p2.point(2.5), 2.4, "رياح عاصفة! توقف عندما تهبّ أو قاومها بالاتجاه المعاكس")
    L.hop(cur, 2.4, 0, "jump")
    wb = L.plat(cur, 28, 2.6, c=1, name="WINDB")
    x, y, z = wb.point(0, 0)
    L.wind((x, y, z), (6.0, 4.0, 30.0), wb.heading + 90, spd=6.5, on=1.8, off=2.2)
    L.coin_line(wb, 8, height=1.1, along0=-12.0, along1=12.0)
    L.hop(cur, 2.4, 0, "jump")
    p3a = L.plat(cur, 8, 8, c=3, name="P3a")
    L.check(p3a.point(-2.0, -2.5), p3a.heading)

    # 3b. snow-sniper causeway: snowbots lob from the far end while icicles drop -----------------------
    L.section("3b sniper causeway")
    L.hop(cur, 2.4, 0, "jump")
    cw = L.plat(cur, 30, 4.0, c=0, name="CAUSE", ice=True)
    for k in range(4):
        L.icicle(up(cw.point(-9.0 + k * 6.0, 0.0), 6.0), 1.5, 1.7)
    L.coin_line(cw, 8, height=1.1, along0=-13.0, along1=13.0)
    L.hop(cur, 2.4, 0.6, "jump")
    p3 = L.plat(cur, 10, 9, c=3, name="P3")
    L.snowbot(p3.point(3.0, -2.8), 34.0, 2.4)
    L.snowbot(p3.point(3.0, 2.8), 34.0, 2.6, 0.5)
    L.check(p3.point(-3.0, -3.0), p3.heading)

    # 4. rolling drums -------------------------------------------------------------------------------
    L.section("4 rolling drums")
    L.hint(p3.point(2.5), 2.4, "الأسطوانات تدور عكسك! اركض بسرعة فوقها")
    for k in range(5):
        L.hop(cur, 1.6 if k else 2.2, 0.0, "jump", coins=1)
        L.drum(cur, 5.0, 1.4, -2.6 - 0.3 * k, c=k % 4, name="DR%d" % k, ice=(k % 2 == 1))
    L.hop(cur, 1.8, 0, "jump")
    p4a = L.plat(cur, 7, 7, c=0, name="P4a")
    L.check(p4a.point(-2.0, 2.0), p4a.heading)

    # 4b. drums in a crosswind --------------------------------------------------------------------------
    L.section("4b drums in crosswind")
    for k in range(4):
        L.hop(cur, 1.8 if k else 2.2, 0.0, "jump", coins=1)
        dw = L.drum(cur, 4.6, 1.5, -2.4 - 0.4 * k, c=(k + 1) % 4, name="DW%d" % k, ice=(k % 2 == 0))
    x, y, z = L.surfs[-3].point(0.0, 0.0)
    L.wind((x, y - 1.0, z), (8.0, 6.0, 14.0), cur.h + 90, spd=3.5, on=1.6, off=2.0)
    L.hop(cur, 1.8, 0, "jump")
    p4 = L.plat(cur, 9, 9, c=0, name="P4")
    L.check(p4.point(-2.5, 2.5), p4.heading)

    # 5. snowbot hill + battery behind an ice wall (route turns east) ------------------------------
    L.section("5 snowball hill")
    cur = L.side_cur(p4, +1, along=1.0)
    L.hop(cur, 3.0, 0.5, "jump")
    hill = L.plat(cur, 20, 14, c=1, name="HILL")
    L.hint(hill.point(-8.0), 2.6, "أعد كرات الثلج إلى راميها باللكمة!")
    L.snowbot(hill.point(5.0, -4.5), 24.0, 2.6)
    L.snowbot(hill.point(7.5, 4.5), 24.0, 2.8, 0.5)
    L.hopper(hill.point(0.0, 0.0), ph=0.4)
    L.crate(hill.point(-3.0, 5.5), 6)
    L.coin_ring(hill.point(0.0, 0.0), 5.0, 12)
    L.check(hill.point(8.5, 0.0), hill.heading)
    sb = L.side_cur(hill, -1, along=-2.0, side=True)
    L.hop(sb, 2.8, 0, "jump")
    al = L.plat(sb, 7, 5.2, c=3, name="ALC")
    L.wall(al.point(-1.0), (4.6, 2.8, 0.8), al.heading, kind="ice", hp=2, side=True)
    L.battery(al.point(2.0))

    # 6. geyser cliff -----------------------------------------------------------------------------------
    L.section("6 geyser cliff")
    L.hint(hill.point(9.5, 3.0), 1.6, "قف فوق نافورة البخار لتقذفك إلى الأعلى")
    L.hop(cur, 2.6, 0, "jump")
    g0 = L.plat(cur, 6, 6, c=0, name="G0")
    for k in range(3):
        last = L.surfs[-1]
        L.geyser(last.point(1.2, 0.0), h=7.0, power=21.0, per=3.6, dur=1.3, ph=0.2 * k)
        L.hop(cur, 2.4, 4.6, "geyser:21:1.2", coins=3, coin_h=2.5)
        L.plat(cur, 6, 6, c=(k + 1) % 4, name="G%d" % (k + 1))
    gt = L.surfs[-1]
    L.check(gt.point(-1.5, 2.0), gt.heading)

    # 6b. icy pendulums ---------------------------------------------------------------------------------
    L.section("6b icy pendulums")
    L.hop(cur, 2.4, 0, "jump")
    L.disc(cur, 1.6, c=0, name="IP0")
    for k in range(3):
        L.hop(cur, 2.6, 0, "jump", coins=2)
        L.pend(cur, 3.2, 3.2, rope=7.5, amp=28.0, per=3.0, ph=0.3 * k, across=True, c=k % 4, name="IPD%d" % k, ice=True)
        L.hop(cur, 2.6, 0, "jump")
        L.disc(cur, 1.6, c=0, name="IP%d" % (k + 1))
    L.hop(cur, 2.6, 0, "jump")
    ipe = L.plat(cur, 8, 8, c=2, name="IPE")
    L.check(ipe.point(-2.0, 2.5), ipe.heading)

    # 7. icy turntables in the wind --------------------------------------------------------------------
    L.section("7 icy wheels + wind")
    L.hop(cur, 3.0, 0, "jump")
    t1 = L.turn(cur, 3.8, 0.7, c=1, name="IT1")
    L.hop(cur, 2.8, 0, "jump")
    t2 = L.turn(cur, 3.8, -0.9, c=2, name="IT2")
    L.hop(cur, 2.8, 0.4, "jump")
    t3 = L.turn(cur, 3.8, 1.1, c=3, name="IT3")
    x1, y1, z1 = t2.at(0)
    L.wind((x1, y1, z1), (12.0, 4.0, 24.0), cur.h + 90, spd=4.5, on=2.0, off=2.0)
    L.hop(cur, 3.0, 0, "jump", coins=2)
    p7 = L.plat(cur, 8, 8, c=0, name="P7")
    L.check(p7.point(-2.0, 2.5), p7.heading)

    # 8. swinging ice blocks over a narrow icy bridge ------------------------------------------------
    L.section("8 ice block swings")
    L.hop(cur, 2.4, 0, "jump")
    ib = L.plat(cur, 26, 3.0, c=1, name="ICEBR", ice=True)
    for k, alg in enumerate([-8.0, -2.5, 3.0, 8.5]):
        x, y, z = ib.point(alg, 0)
        L.swing((x, y + 7.2, z), 6.0, 60.0, 2.5, 0.22 * k, ib.heading + 90, "ice", 1.0)
    L.coin_line(ib, 7, height=1.1, along0=-11.0, along1=11.0)
    L.hop(cur, 2.4, 0, "jump")
    p8 = L.plat(cur, 8, 8, c=2, name="P8")
    L.check(p8.point(-2.0, -2.5), p8.heading)

    # 9. slippery hopper rink + friend 2 behind ice (route turns north) ---------------------------------
    L.section("9 hopper rink")
    cur = L.side_cur(p8, -1, along=1.0)
    L.hop(cur, 3.0, 0, "jump")
    rink = L.disc(cur, 9.0, c=3, name="RINK", ice=True)
    rx, ry, rz = rink.at(0)
    for k in range(3):
        a = math.radians(30 + 120 * k)
        L.hopper((rx + 4.5 * math.cos(a), ry, rz + 4.5 * math.sin(a)), 10.0, 5.0, ph=0.3 * k)
    L.spider((rx, ry, rz), 3.0)
    L.coin_ring((rx, ry, rz), 7.0, 14)
    sr = L.exit_circle(rink, cur.h + 90, side=True)
    L.hop(sr, 3.0, 0, "jump")
    ral = L.plat(sr, 7, 5, c=2, name="BOT2")
    L.wall(ral.point(-1.0), (4.4, 2.8, 0.8), ral.heading, kind="ice", hp=3, side=True)
    L.bot(ral.point(2.0), 1)
    L.hop(cur, 3.0, 0, "jump")
    p9 = L.plat(cur, 8, 8, c=0, name="P9")
    L.check(p9.point(-2.0, 2.5), p9.heading)

    # 9b. vent tower: steam launches up a shaft while gusts push you off ---------------------------------
    L.section("9b vent tower")
    L.hop(cur, 2.4, 0, "jump")
    v0 = L.plat(cur, 6, 6, c=2, name="V0")
    for k in range(2):
        last = L.surfs[-1]
        L.geyser(last.point(1.0, 0.0), h=7.5, power=22.0, per=3.0, dur=1.2, ph=0.4 * k)
        L.hop(cur, 2.6, 4.6, "geyser:22:1.4", coins=3, coin_h=2.5)
        vk = L.plat(cur, 5.5, 5.5, c=(k + 3) % 4, name="V%d" % (k + 1))
        x, y, z = vk.point(0.0, 0.0)
        L.wind((x, y, z), (5.5, 5.0, 6.0), cur.h + (90 if k % 2 == 0 else -90), spd=4.5, on=1.4, off=2.2, ph=0.25 * k)
    L.hop(cur, 2.6, -1.0, "jump")
    L.plat(cur, 8, 8, c=0, name="VT")
    vt = L.surfs[-1]
    L.check(vt.point(-2.0, 2.5), cur.h)
    L.snowbot(vt.point(2.0, -2.5), 22.0, 2.6)
    svt = L.side_cur(vt, -1, along=0.0, side=True)
    L.hop(svt, 6.0, 1.2, "double", coins=3, coin_h=3.0)
    vb = L.disc(svt, 2.0, c=1, name="BAT3")
    L.battery(vb.point(0, 0))

    # 10. drums under icicles + battery 2 -------------------------------------------------------------
    L.section("10 drums + icicles")
    for k in range(4):
        L.hop(cur, 1.7 if k else 2.2, 0.0, "jump", coins=1)
        d = L.drum(cur, 5.0, 1.5, -3.2 - 0.2 * k, c=k % 4, name="DI%d" % k, ice=(k % 2 == 0))
        L.icicle(up(d.point(0.0, 1.0), 6.5), 1.4, 1.6)
    L.hop(cur, 1.8, 0, "jump")
    p10a = L.plat(cur, 8, 8, c=1, name="P10a")
    L.check(p10a.point(-2.5, -2.5), p10a.heading)

    # 10b. frozen lake: an icy plaza of breakable ice pillars, hoppers and a snowbot ------------------
    L.section("10b frozen lake")
    L.hop(cur, 2.6, 0, "jump")
    lake = L.plat(cur, 22, 16, c=3, name="LAKE", ice=True)
    for k, (al, ac) in enumerate([(-6.0, -3.0), (-1.0, 3.5), (4.0, -2.0), (8.0, 4.0)]):
        L.wall(lake.point(al, ac), (2.4, 2.6, 2.4), lake.heading, kind="ice", hp=1)
    L.hopper(lake.point(-3.0, 0.5), 10.0, 6.0)
    L.hopper(lake.point(5.0, 1.0), 10.0, 6.0, ph=0.5)
    L.snowbot(lake.point(9.5, -5.5), 26.0, 2.8)
    L.coin_ring(lake.point(0.0, 0.0), 6.0, 12)
    L.hop(cur, 2.6, 0, "jump")
    p10 = L.plat(cur, 9, 8, c=1, name="P10")
    L.check(p10.point(-2.5, -2.5), p10.heading)
    sbt = L.side_cur(p10, +1, along=1.5, side=True)
    L.hop(sbt, 9.0, 0.0, "hover", coins=4, coin_h=3.0)
    bt2 = L.disc(sbt, 2.2, c=3, name="BAT2")
    L.battery(bt2.point(0, 0))

    # 11. storm finale: geyser chain in the wind, snowbot overwatch -----------------------------------
    L.section("11 storm finale")
    L.hop(cur, 2.6, 0, "jump")
    s0 = L.plat(cur, 6, 6, c=2, name="S0")
    L.snowbot(s0.point(-1.5, 2.0), 30.0, 3.2)
    for k in range(3):
        last = L.surfs[-1]
        L.geyser(last.point(1.0, -0.5), h=7.0, power=22.0, per=3.2, dur=1.2, ph=0.3 * k)
        L.hop(cur, 3.0, 4.2, "geyser:22:1.6", coins=3, coin_h=2.5)
        L.plat(cur, 6, 6, c=k % 4, name="S%d" % (k + 1), ice=(k == 1))
        lw = L.surfs[-1]
        x, y, z = lw.point(0.0, 0.0)
        L.wind((x, y, z), (6.0, 6.0, 8.0), cur.h - 90, spd=4.0, on=1.5, off=2.5, ph=0.3 * k)
    L.check(L.surfs[-1].point(-1.5, 1.5), cur.h)
    L.hop(cur, 9.0, 0.0, "hover", coins=4, coin_h=3.0)
    L.disc(cur, 2.4, c=1, name="HF")
    L.hop(cur, 3.4, 0.0, "jump")
    fin = L.plat(cur, 13, 11, c=3, name="FIN")
    L.goal(fin.point(2.5), False)
    L.coin_ring(fin.point(2.5), 3.8, 10)
    sf = L.side_cur(fin, -1, along=-2.5, side=True)
    for k in range(2):
        L.hop(sf, 1.8 if k else 2.4, 0.0, "jump")
        L.drum(sf, 4.4, 1.4, -4.2, c=2, name="FD%d" % k, ice=True)
    L.hop(sf, 6.0, 1.0, "double", coins=3, coin_h=3.0)
    b3 = L.disc(sf, 2.2, c=1, name="BOT3")
    L.bot(b3.point(0, 0), 2)
    sb1 = L.side_cur(p2, +1, along=0.0, side=True)
    L.hop(sb1, 6.4, 1.0, "double", coins=3, coin_h=3.0)
    b1 = L.disc(sb1, 2.2, c=2, name="BOT1")
    L.bot(b1.point(0, 0), 0)
    return L


# ============================================================ LEVEL 5 - GALAXY CORE (boss)
# Signature ideas: jump-switch platforms (they swap on every jump), meteor showers, sweeping lasers,
# predictive turrets, a 4-pylon puzzle, chained zero-g bubbles, an electric wave floor and the Guardian.
def level5():
    L = Level(5, "قلب المجرة", "core", par=480)
    L.cam = {"dist": 8.6, "pitch": 0.48}
    cur = Cur(0, 0, 0, 0)
    L.disc(cur, 5.5, c=0, name="spawn")
    L.spawn = (0.0, 0.6, -5.5)
    L.hint((0, 0, -5.5), 4.0, "الحارس ينتظرك في قلب المجرة")

    # 1. jump-switch platforms -----------------------------------------------------------------------
    L.section("1 jump-switch")
    L.hint((0, 0, -10.0), 2.0, "المنصات الوردية والزرقاء تتبادل مع كل قفزة! إن كانت التالية مطفأة فاقفز في مكانك")
    for k in range(7):
        L.hop(cur, 2.6 if k else 2.4, 0.0, "jump", coins=1)
        L.toggle(cur, 3.2, 3.2, (k + 1) % 2, name="TG%d" % k)
    L.hop(cur, 2.6, 0, "jump")
    p1 = L.plat(cur, 9, 9, c=1, name="P1")
    L.check(p1.point(-2.5, 2.5), p1.heading)

    # 2. meteor field ----------------------------------------------------------------------------------
    L.section("2 meteor field")
    L.hint(p1.point(3.0), 2.4, "زخات النيازك! راقب الدوائر الحمراء على الأرض")
    L.hop(cur, 2.6, 0, "jump")
    mf = L.plat(cur, 34, 12, c=0, name="METEOR")
    L.meteors(mf.point(0, 0), 13.0, 1.0, 0.65)
    L.crate(mf.point(-8.0, 4.0), 5)
    L.crate(mf.point(6.0, -4.0), 5)
    L.coin_line(mf, 9, height=1.1, along0=-15.0, along1=15.0)
    L.tm(False, 6.0)
    L.hop(cur, 2.6, 0, "jump")
    p2 = L.plat(cur, 8, 8, c=2, name="P2")
    L.check(p2.point(-2.0, 2.5), p2.heading)

    # 3. sweeping laser discs ------------------------------------------------------------------------
    L.section("3 laser discs")
    for k in range(3):
        L.hop(cur, 2.8, 0.4 if k else 0.0, "jump", coins=2)
        dsc = L.disc(cur, 5.0, c=k % 4, name="LD%d" % k)
        cx, cy, cz = dsc.at(0)
        L.sweep((cx, cy, cz), 4.8, 0.55, 1.4 + 0.3 * k, 1 + k, 0.2 * k)
    L.hop(cur, 2.8, 0, "jump")
    p3a = L.plat(cur, 7, 7, c=3, name="P3a")
    L.check(p3a.point(-2.0, 2.0), p3a.heading)

    # 3b. orbit of switches: jump-switch tiles circling a laser pylon ------------------------------------
    L.section("3b switch orbit")
    for k in range(5):
        L.hop(cur, 2.6, 0.0, "jump", coins=1)
        L.toggle(cur, 3.0, 3.0, k % 2, name="TO%d" % k)
        cur.turn(-22)
    L.hop(cur, 2.8, 0, "jump")
    p3 = L.plat(cur, 8, 8, c=3, name="P3")
    L.check(p3.point(-2.0, 2.5), p3.heading)

    # 4. predictive turrets over movers (route turns east) --------------------------------------------
    L.section("4 predictive turrets")
    cur = L.side_cur(p3, +1, along=1.0)
    L.hint(p3.point(2.0, 3.0), 1.8, "هذه المدافع تتوقع حركتك! غيّر اتجاهك فجأة")
    L.hop(cur, 3.4, 0, "jump")
    L.mover(cur, 4, 4, (0, 0, 9), per=4.6, c=1, name="TM1")
    L.hop(cur, 3.4, 0, "jump")
    t4 = L.plat(cur, 6, 6, c=0, name="T4")
    L.turret(t4.point(0.0, 2.2), 26.0, 2.0, lead=1.0, burst=2)
    L.hop(cur, 3.4, 0, "jump")
    L.mover(cur, 4, 4, (8, 0, 0), per=4.2, shift=-4.0, c=2, name="TM2")
    L.hop(cur, 3.4, 0, "jump")
    L.mover(cur, 4, 4, (0, 3.4, 0), per=4.0, c=3, name="TM3")
    L.hop(cur, 3.4, 0, "jump")
    p4 = L.plat(cur, 9, 9, c=1, name="P4")
    L.turret(p4.point(3.5, -3.5), 26.0, 2.2, 0.5, lead=1.0, burst=3)
    L.check(p4.point(-2.5, 2.5), p4.heading)

    # 4b. laser elevator: ride a lift while a laser arm sweeps across it ---------------------------------
    L.section("4b laser elevator")
    L.hop(cur, 2.4, 0, "jump")
    L.lift(cur, 5, 5, (0, 9.0, 0), dur=6.0, c=3, name="LLIFT")
    lf = L.surfs[-1]
    lx, ly, lz = lf.point(0.0, 3.2)
    L.sweep((lx, ly + 2.2, lz), 6.0, 2.6, 1.1, 1, 0.0)
    L.sweep((lx, ly + 5.6, lz), 6.0, 2.6, -1.3, 1, 0.5)
    L.hop(cur, 2.8, 0, "jump")
    p4b = L.plat(cur, 8, 8, c=1, name="P4b")
    L.check(p4b.point(-2.0, 2.5), p4b.heading)

    # 5. toggles + sliding bridges braid ---------------------------------------------------------------
    L.section("5 toggle braid")
    for k in range(6):
        L.hop(cur, 2.4, 0.0, "jump", coins=1)
        if k % 2 == 0:
            L.toggle(cur, 3.0, 3.0, 0, name="TB%d" % k)
        else:
            L.retract(cur, 3.0, 3.0, on=1.8, off=1.2, ph=0.2 * k, c=2, name="RB%d" % k, side=1 if k % 4 == 1 else -1)
    L.hop(cur, 2.6, 0, "jump")
    p5 = L.plat(cur, 13, 13, c=2, name="P5")
    L.check(p5.point(-5.0, 5.0), p5.heading)

    # 6. four-pylon memory puzzle + battery -----------------------------------------------------------
    L.section("6 pylons")
    pts = [p5.point(-2.0, -5.0), p5.point(3.0, -4.0), p5.point(4.0, 2.5), p5.point(-1.0, 5.0)]
    L.pylons(p5.point(-2.0, 0.5), pts, [3, 1, 0, 2, 1], "PYC", r=8.0)
    L.battery(p5.point(-5.0, -5.0), side=False)
    L.hop(cur, 2.0, 0, "jump")
    for k in range(4):
        if k:
            L.hop(cur, 1.6, 0.3, "jump")
        L.ghost(cur, 3.4, 3.4, mode="switch", sid="PYC", c=3, name="PB%d" % k)
        L.coins([up(L.surfs[-1].point(0, 0), 1.2)])
    L.hop(cur, 2.0, 0, "jump")
    p6 = L.plat(cur, 8, 8, c=3, name="P6")
    L.check(p6.point(-2.0, 2.5), p6.heading)

    # 7. chained zero-g bubbles with friend 1 ---------------------------------------------------------
    L.section("7 bubble chain")
    L.hint(p6.point(2.5), 2.4, "فقاعتان متتاليتان! تحرك بحذر في انعدام الجاذبية")
    gs = cur.p
    L.hop(cur, 15.0, 1.0, "zerog")
    dx, dz = math.sin(math.radians(cur.h)), -math.cos(math.radians(cur.h))
    zc1 = (gs[0] + dx * 7.5, gs[1] + 3.0, gs[2] + dz * 7.5)
    L.zerog(zc1, 10.0, 1)
    L.bot((zc1[0], zc1[1] + 3.0, zc1[2]), 0)
    zp = L.disc(cur, 2.2, c=2, name="ZMID")
    L.drone(up(zp.point(0, 0), 2.0), L.rel(cur.h, 4.0), 3.0, leash=2.0)
    gs2 = cur.p
    L.hop(cur, 15.0, 1.0, "zerog")
    zc2 = (gs2[0] + dx * 7.5, gs2[1] + 3.0, gs2[2] + dz * 7.5)
    L.zerog(zc2, 10.0, 3)
    L.coin_ring(zc2, 5.0, 10)
    p7 = L.plat(cur, 9, 9, c=1, name="P7")
    L.check(p7.point(-2.5, 2.5), p7.heading)

    # 8. electric wave hall with shield bots + friend 2 (route turns west) ------------------------------
    L.section("8 wave hall")
    cur = L.side_cur(p7, -1, along=1.0)
    L.hop(cur, 2.6, 0, "jump")
    wh = L.plat(cur, 22, 12, c=0, name="WAVE")
    L.elec(wh, 20.0, 10.0, cell=2.0, per=0.9, pattern="wave")
    L.shield(wh.point(-3.0, -3.0), wh.point(-3.0, 3.0))
    L.shield(wh.point(5.0, 3.0), wh.point(5.0, -3.0))
    L.coin_line(wh, 8, height=1.1, along0=-9.0, along1=9.0)
    L.check(wh.point(10.0, 4.6), wh.heading)
    sw = L.side_cur(wh, +1, along=6.0, side=True)
    for k in range(4):
        L.hop(sw, 2.4, 0.5, "jump")
        L.toggle(sw, 2.8, 2.8, (k + 1) % 2, name="BT%d" % k)
    L.hop(sw, 3.0, 0.0, "jump")
    b2 = L.disc(sw, 2.2, c=1, name="BOT2")
    L.bot(b2.point(0, 0), 1)

    # 8b. turret ring: three predictive turrets around a disc of blinking holograms ---------------------
    L.section("8b turret ring")
    L.hop(cur, 2.6, 0, "jump")
    ring = L.disc(cur, 8.0, c=2, name="TRING")
    rx, ry, rz = ring.at(0)
    for k in range(3):
        a = math.radians(60 + 120 * k)
        L.turret((rx + 6.2 * math.cos(a), ry, rz + 6.2 * math.sin(a)), 20.0, 2.6, 0.3 * k, lead=0.8)
    L.coin_ring((rx, ry, rz), 3.0, 8)
    srb = L.exit_circle(ring, cur.h + 90, side=True)
    L.hop(srb, 9.0, 0.5, "hover", coins=3, coin_h=3.0)
    rbb = L.disc(srb, 2.0, c=1, name="BAT3")
    L.battery(rbb.point(0, 0))
    L.hop(cur, 2.8, 0, "jump")
    for k in range(3):
        if k:
            L.hop(cur, 2.4, 0.4, "jump")
        L.ghost(cur, 3.0, 3.0, on=1.4, off=1.0, ph=0.25 * k, c=3, name="RG%d" % k)
    L.hop(cur, 2.6, 0, "jump")
    p8b = L.plat(cur, 8, 8, c=0, name="P8b")
    L.check(p8b.point(-2.0, 2.5), p8b.heading)

    # 9. final gauntlet: toggles over the void under a meteor storm ----------------------------------
    L.section("9 final gauntlet")
    L.hop(cur, 2.6, 0, "jump")
    g0 = L.plat(cur, 6, 6, c=2, name="G0")
    x, y, z = g0.point(0, 0)
    for k in range(6):
        L.hop(cur, 2.8, 0.3 if k % 2 else 0.0, "jump", coins=1)
        L.toggle(cur, 3.2, 3.2, (k + 1) % 2, name="TF%d" % k)
    L.meteors(L.surfs[-3].point(0, 0), 9.0, 1.3, 0.8)
    L.hop(cur, 2.6, 0, "jump")
    g1 = L.plat(cur, 8, 8, c=3, name="G1")
    L.check(g1.point(-2.0, 2.5), g1.heading)
    sb = L.side_cur(g1, +1, along=0.0, side=True)
    L.hop(sb, 9.2, 0.5, "hover", coins=4, coin_h=3.0)
    bt = L.disc(sb, 2.2, c=1, name="BAT2")
    L.battery(bt.point(0, 0))
    L.hop(cur, 3.0, 0, "jump")
    br = L.plat(cur, 16, 4.6, c=3, name="BRIDGE")
    L.hint(br.point(-5.0), 2.6, "اهزم الحارس: اضرب نواته المتوهجة بعد أن يهبط")
    L.check(br.point(2.0, 0), br.heading)
    L.coin_line(br, 5)

    # 10. arena -------------------------------------------------------------------------------------------
    L.section("10 guardian")
    L.hop(cur, 0.3, 0, "walk")
    R = 17.0
    arena = L.disc(cur, R, th=1.2, c=1, name="ARENA")
    ax, ay, az = arena.at(0)
    L.boss((ax, ay, az), R)
    L.goal((ax, ay, az - 13.0), True)
    el = L.exit_circle(arena, cur.h - 90 + 25, side=True)
    L.hop(el, 4.6, 1.5, "double", coins=3, coin_h=3.0)
    d3 = L.disc(el, 2.4, c=2, name="BOT3")
    L.bot(d3.point(0, 0), 2)
    L.coin_ring((ax, ay, az), 11.0, 16, y_off=1.0)
    return L
