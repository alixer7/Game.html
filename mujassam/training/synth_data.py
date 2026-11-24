"""Self-supervised training data for the Mujassam brain — no human labelling needed.

Procedural generators produce thousands of random but well-formed models (furniture, buildings,
plants, vehicles, vessels, characters, creatures, props), each with captions in English and
Arabic. Every model is built and rendered in Blender, then turned into supervised examples
for every brain task, using exactly the same prompts as inference:

  router   caption              -> route JSON
  planner  caption              -> spec            (text -> 3D)
  planner  render (as 'photo')  -> spec            (image -> 3D)
  analyst  render               -> analysis JSON
  critic   corrupted render     -> scores + issues + the patch that undoes the corruption

The critic examples are the key trick: we break a good model in a known way (move a part so it
floats, delete a part, recolour, distort a scale), render it, and the target is the exact edit
that repairs it. This teaches the brain to *see* its mistakes and fix them with small patches.

usage:  python training/synth_data.py --out data/synth --n 2000 [--res 256] [--seed 0]
"""
from __future__ import annotations

import argparse
import copy
import json
import math
import random
import sys
from pathlib import Path
from typing import Any, Callable

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from mujassam.blender.runner import BlenderRunner  # noqa: E402
from mujassam.brain import prompts as P  # noqa: E402
from mujassam.critic.critic import technical_checks  # noqa: E402
from mujassam.dsl.schema import compact_spec, normalize_spec  # noqa: E402

PALETTE = {
    "red": ("#c0392b", "أحمر"), "blue": ("#2e6db4", "أزرق"), "green": ("#3a8f3e", "أخضر"),
    "yellow": ("#e8c22e", "أصفر"), "white": ("#eeeeee", "أبيض"), "black": ("#1c1c1c", "أسود"),
    "orange": ("#e67e22", "برتقالي"), "purple": ("#7d3c98", "بنفسجي"), "pink": ("#e88aa9", "وردي"),
    "gray": ("#7f8c8d", "رمادي"), "brown": ("#7b4a24", "بني"), "teal": ("#1a8a8a", "فيروزي"),
}
WOODS = [("#a8743f", "oak", "بلوط"), ("#6b3f1f", "walnut", "جوز"), ("#d9b98a", "pine", "صنوبر")]


def U(a: float, b: float) -> float:
    return round(random.uniform(a, b), 3)


def color() -> tuple[str, str, str]:
    name = random.choice(list(PALETTE))
    return name, PALETTE[name][0], PALETTE[name][1]


# --------------------------------------------------------------------------- generators
# each returns (spec, caption_en, caption_ar, meta)

def gen_chair():
    h, w, d = U(0.42, 0.5), U(0.4, 0.52), U(0.4, 0.5)
    th = U(0.03, 0.05)
    wood, wname, war = random.choice(WOODS)
    cname, chex, car = color()
    back_h = U(0.35, 0.55)
    leg = U(0.018, 0.03)
    slats = random.randint(2, 5)
    round_legs = random.random() < 0.5
    has_cushion = random.random() < 0.6
    parts = [
        {"id": "seat", "type": "box", "size": [w, d, th], "location": [0, 0, h - th / 2], "material": "wood", "bevel": 0.006},
    ]
    lx, ly = w / 2 - leg * 1.4, d / 2 - leg * 1.4
    if round_legs:
        parts += [{"id": "leg_front", "type": "cylinder", "radius": leg, "depth": h - th, "location": [lx, -ly, (h - th) / 2], "material": "wood", "mirror": ["x"]},
                  {"id": "leg_back", "type": "cylinder", "radius": leg, "depth": h - th + back_h, "location": [lx, ly, (h - th + back_h) / 2], "material": "wood", "mirror": ["x"]}]
    else:
        parts += [{"id": "leg_front", "type": "box", "size": [2 * leg, 2 * leg, h - th], "location": [lx, -ly, (h - th) / 2], "material": "wood", "mirror": ["x"]},
                  {"id": "leg_back", "type": "box", "size": [2 * leg, 2 * leg, h - th + back_h], "location": [lx, ly, (h - th + back_h) / 2], "material": "wood", "mirror": ["x"]}]
    top = h + back_h - th
    parts.append({"id": "back_rail", "type": "box", "size": [2 * lx, 0.025, 0.07], "location": [0, ly, top - 0.035], "material": "wood", "bevel": 0.005})
    span = 2 * lx - 0.06
    step = span / (slats + 1)
    parts.append({"id": "back_slat", "type": "box", "size": [0.025, 0.018, back_h - 0.1], "location": [-span / 2 + step, ly, h + (back_h - 0.1) / 2 - 0.005],
                  "material": "wood", "array": {"count": slats, "offset": [step, 0, 0]}})
    mats = {"wood": {"color": wood, "roughness": 0.6}}
    if has_cushion:
        mats["fabric"] = {"color": chex, "roughness": 0.9}
        parts.append({"id": "cushion", "type": "box", "size": [w - 0.04, d - 0.04, 0.05], "location": [0, 0, h + 0.025], "material": "fabric", "bevel": 0.018, "bevel_segments": 3})
    legs = "round" if round_legs else "square"
    en = f"A {wname} wooden chair with {legs} legs and {slats} back slats" + (f" and a {cname} cushion" if has_cushion else "")
    ar = f"كرسي من خشب ال{war} بأرجل {'دائرية' if round_legs else 'مربعة'} و{slats} ألواح في الظهر" + (f" مع وسادة لونها {car}" if has_cushion else "")
    check = [f"{legs} legs", f"{slats} back slats"] + ([f"{cname} cushion"] if has_cushion else [])
    return {"name": "chair", "style": "realistic furniture", "materials": mats, "parts": parts}, en, ar, \
        {"category": "furniture", "organic": 0.05, "height": top, "checklist": check}


def gen_table():
    h, w, d = U(0.45, 0.78), U(0.6, 1.6), U(0.5, 0.9)
    wood, wname, war = random.choice(WOODS)
    round_top = random.random() < 0.35
    parts = []
    if round_top:
        r = min(w, d) / 2
        parts.append({"id": "top", "type": "cylinder", "radius": r, "depth": 0.04, "location": [0, 0, h - 0.02], "material": "wood", "segments": 48, "bevel": 0.005})
        parts.append({"id": "pedestal", "type": "lathe", "profile": [[0, 0], [r * 0.6, 0], [r * 0.6, 0.03], [0.05, 0.08], [0.04, h - 0.1], [0.08, h - 0.04], [0, h - 0.04]], "location": [0, 0, 0], "material": "wood"})
        en, ar, chk = f"A round {wname} pedestal table", f"طاولة دائرية من خشب ال{war} بقاعدة واحدة", ["round top", "single pedestal"]
    else:
        parts.append({"id": "top", "type": "box", "size": [w, d, 0.04], "location": [0, 0, h - 0.02], "material": "wood", "bevel": 0.006})
        lx, ly = w / 2 - 0.05, d / 2 - 0.05
        parts.append({"id": "leg_front", "type": "box", "size": [0.05, 0.05, h - 0.04], "location": [lx, -ly, (h - 0.04) / 2], "material": "wood", "mirror": ["x"]})
        parts.append({"id": "leg_back", "type": "box", "size": [0.05, 0.05, h - 0.04], "location": [lx, ly, (h - 0.04) / 2], "material": "wood", "mirror": ["x"]})
        en, ar, chk = f"A rectangular {wname} table with four legs", f"طاولة مستطيلة من خشب ال{war} بأربع أرجل", ["rectangular top", "four legs"]
    return {"name": "table", "style": "realistic furniture", "materials": {"wood": {"color": wood, "roughness": 0.55}}, "parts": parts}, en, ar, \
        {"category": "furniture", "organic": 0.05, "height": h, "checklist": chk}


def gen_vessel():
    kind = random.choice(["vase", "bottle", "mug", "bowl"])
    cname, chex, car = color()
    s = U(0.8, 1.3)
    if kind == "vase":
        prof = [[0, 0], [0.07, 0], [0.11, 0.06], [U(0.1, 0.14), 0.14], [0.06, 0.25], [0.045, 0.3], [0.06, 0.33]]
        ar_k = "مزهرية"
    elif kind == "bottle":
        prof = [[0, 0], [0.04, 0], [0.042, 0.16], [0.035, 0.2], [0.014, 0.24], [0.014, 0.29], [0, 0.29]]
        ar_k = "زجاجة"
    elif kind == "mug":
        prof = [[0, 0], [0.04, 0], [0.042, 0.1], [0.038, 0.1], [0.036, 0.008], [0, 0.008]]
        ar_k = "كوب"
    else:
        prof = [[0, 0], [0.04, 0], [0.09, 0.05], [0.1, 0.07], [0.094, 0.07], [0.085, 0.05], [0.035, 0.008], [0, 0.008]]
        ar_k = "وعاء"
    prof = [[round(r * s, 4), round(z * s, 4)] for r, z in prof]
    parts = [{"id": kind, "type": "lathe", "profile": prof, "segments": 40, "location": [0, 0, 0], "material": "glaze"}]
    if kind == "mug":
        parts.append({"id": "handle", "type": "torus", "major_radius": 0.03 * s, "minor_radius": 0.007 * s, "rotation": [90, 0, 0],
                      "location": [0.045 * s, 0, 0.05 * s], "material": "glaze"})
    mats = {"glaze": {"color": chex, "roughness": U(0.15, 0.5)}}
    if kind == "bottle":
        mats["glaze"].update({"alpha": 0.6, "transmission": 0.8, "roughness": 0.05})
    h = max(z for _, z in prof)
    return {"name": kind, "style": "ceramic product", "materials": mats, "parts": parts}, f"A {cname} {kind}", f"{ar_k} لونه {car}", \
        {"category": "prop", "organic": 0.2, "height": h, "checklist": [kind, f"{cname} colour"]}


def gen_house():
    w, d, h = U(4, 9), U(4, 8), U(2.6, 3.2)
    floors = random.randint(1, 2)
    wall_name, wall_hex, wall_ar = color()
    roof_hex = random.choice(["#8e2b1f", "#3b3b3b", "#5d4037", "#2e4a62"])
    H = h * floors
    parts = [{"id": "walls", "type": "box", "size": [w, d, H], "location": [0, 0, H / 2], "material": "wall", "cutters": []}]
    n_win = random.randint(2, 4)
    for f in range(floors):
        for i in range(n_win):
            x = -w / 2 + (i + 0.5) * w / n_win
            if f == 0 and abs(x) < 0.7:
                continue
            cid = f"win_{f}_{i}"
            parts.append({"id": cid, "type": "box", "size": [0.9, 0.6, 1.1], "location": [round(x, 3), -d / 2, f * h + 1.5], "cutter": True})
            parts[0]["cutters"].append(cid)
            parts.append({"id": cid + "_glass", "type": "box", "size": [0.9, 0.04, 1.1], "location": [round(x, 3), -d / 2 + 0.12, f * h + 1.5], "material": "glass"})
    parts.append({"id": "door", "type": "box", "size": [1.0, 0.08, 2.1], "location": [0, -d / 2 - 0.02, 1.05], "material": "door", "bevel": 0.01})
    roof_h = U(1.2, 2.4)
    parts.append({"id": "roof", "type": "extrude", "polygon": [[-w / 2 - 0.3, 0], [w / 2 + 0.3, 0], [0, roof_h]], "depth": d + 0.6,
                  "rotation": [90, 0, 0], "location": [0, 0, H], "material": "roof"})
    parts.append({"id": "chimney", "type": "box", "size": [0.5, 0.5, roof_h], "location": [w / 4, d / 5, H + roof_h / 2 + 0.3], "material": "wall"})
    mats = {"wall": {"color": wall_hex, "roughness": 0.85}, "roof": {"color": roof_hex, "roughness": 0.7},
            "glass": {"color": "#9ec9e8", "roughness": 0.05, "metallic": 0.2}, "door": {"color": "#5b3a1e", "roughness": 0.6}}
    en = f"A {floors}-storey {wall_name} house with a gabled roof, a chimney and a front door"
    ar = f"منزل {wall_ar} من {'طابق واحد' if floors == 1 else 'طابقين'} بسقف جملوني ومدخنة وباب أمامي"
    return {"name": "house", "style": "stylized architecture", "materials": mats, "parts": parts}, en, ar, \
        {"category": "architecture", "organic": 0.0, "height": H + roof_h, "checklist": [f"{floors} storeys", "gabled roof", "chimney", "front door", "windows"]}


def gen_tree():
    h = U(2.5, 6)
    kind = random.choice(["round", "pine", "palm"])
    parts = []
    lean = U(-0.4, 0.4)
    trunk_h = h * (0.45 if kind != "palm" else 0.9)
    path = [[0, 0, 0], [lean * 0.3, 0, trunk_h * 0.4], [lean * 0.7, 0.05, trunk_h * 0.75], [lean, 0, trunk_h]]
    parts.append({"id": "trunk", "type": "tube", "path": path, "radius": h * 0.04, "radius_end": h * 0.02, "material": "bark", "location": [0, 0, 0]})
    if kind == "round":
        for i in range(random.randint(3, 5)):
            parts.append({"id": f"foliage_{i}", "type": "sphere", "radius": U(h * 0.18, h * 0.26), "segments": 16, "rings": 10,
                          "location": [round(lean + U(-h * 0.15, h * 0.15), 3), U(-h * 0.1, h * 0.1), round(trunk_h + U(0, h * 0.25), 3)], "material": "leaves"})
        en, ar = "A low-poly round deciduous tree", "شجرة ذات تاج دائري بأسلوب لو بولي"
    elif kind == "pine":
        for i in range(3):
            parts.append({"id": f"cone_{i}", "type": "cone", "radius": h * (0.3 - i * 0.07), "depth": h * 0.35, "segments": 10,
                          "location": [lean, 0, trunk_h * 0.6 + i * h * 0.2 + h * 0.17], "material": "leaves"})
        en, ar = "A low-poly pine tree with three layers", "شجرة صنوبر بثلاث طبقات بأسلوب لو بولي"
    else:
        for i in range(6):
            a = 2 * math.pi * i / 6
            tip = [round(math.cos(a) * h * 0.35, 3), round(math.sin(a) * h * 0.35, 3), round(-h * 0.12, 3)]
            parts.append({"id": f"frond_{i}", "type": "tube", "path": [[0, 0, 0], [tip[0] * 0.5, tip[1] * 0.5, h * 0.06], tip],
                          "radius": h * 0.025, "radius_end": h * 0.004, "location": [lean, 0, trunk_h], "material": "leaves"})
        en, ar = "A palm tree with six fronds", "نخلة بستة سعف"
    mats = {"bark": {"color": "#6d4c2f", "roughness": 0.9}, "leaves": {"color": random.choice(["#3f8f3a", "#2d6b2a", "#5fa83a"]), "roughness": 0.8}}
    return {"name": "tree", "style": "low-poly nature", "materials": mats, "parts": parts}, en, ar, \
        {"category": "plant", "organic": 0.7, "height": h, "checklist": [kind + " tree"]}


def gen_car():
    L, W = U(3.8, 4.8), U(1.7, 1.95)
    cname, chex, car = color()
    body_h = U(0.55, 0.7)
    clear = 0.25
    parts = [
        {"id": "body", "type": "box", "size": [W, L, body_h], "location": [0, 0, clear + body_h / 2], "material": "paint", "bevel": 0.08, "bevel_segments": 3},
        {"id": "cabin", "type": "box", "size": [W * 0.86, L * 0.5, 0.5], "location": [0, L * 0.05, clear + body_h + 0.25], "material": "paint", "bevel": 0.12, "bevel_segments": 3},
        {"id": "windshield", "type": "box", "size": [W * 0.8, 0.05, 0.42], "location": [0, -L * 0.2 + 0.02, clear + body_h + 0.24], "rotation": [-25, 0, 0], "material": "glass"},
        {"id": "wheel_front", "type": "cylinder", "radius": 0.33, "depth": 0.24, "rotation": [0, 90, 0], "location": [W / 2 - 0.1, -L * 0.32, 0.33], "material": "tire", "mirror": ["x"]},
        {"id": "wheel_back", "type": "cylinder", "radius": 0.33, "depth": 0.24, "rotation": [0, 90, 0], "location": [W / 2 - 0.1, L * 0.32, 0.33], "material": "tire", "mirror": ["x"]},
        {"id": "headlight", "type": "sphere", "radius": 0.09, "scale": [1.4, 0.4, 0.8], "location": [W / 2 - 0.3, -L / 2 + 0.02, clear + body_h * 0.65], "material": "light", "mirror": ["x"]},
    ]
    mats = {"paint": {"color": chex, "roughness": 0.25, "metallic": 0.6}, "glass": {"color": "#1f2b38", "roughness": 0.05},
            "tire": {"color": "#151515", "roughness": 0.9}, "light": {"color": "#ffffff", "emission": "#fff4d6", "emission_strength": 3}}
    return {"name": "car", "style": "stylized vehicle", "materials": mats, "parts": parts}, f"A {cname} compact car", f"سيارة صغيرة لونها {car}", \
        {"category": "vehicle", "organic": 0.1, "height": clear + body_h + 0.5, "checklist": [f"{cname} body", "four wheels", "headlights"]}


def gen_snowman():
    r1 = U(0.3, 0.45)
    r2, r3 = r1 * 0.72, r1 * 0.5
    z1, z2 = r1 * 0.92, r1 * 0.92 * 2 + r2 * 0.75
    z3 = z2 + r2 * 0.8 + r3 * 0.8
    hat = random.random() < 0.7
    sname, shex, sar = color()
    parts = [
        {"id": "base", "type": "sphere", "radius": r1, "location": [0, 0, z1], "material": "snow"},
        {"id": "middle", "type": "sphere", "radius": r2, "location": [0, 0, z2], "material": "snow"},
        {"id": "head", "type": "sphere", "radius": r3, "location": [0, 0, z3], "material": "snow"},
        {"id": "nose", "type": "cone", "radius": r3 * 0.12, "depth": r3 * 0.6, "rotation": [90, 0, 0], "location": [0, -r3 * 1.15, z3], "material": "carrot"},
        {"id": "eye", "type": "sphere", "radius": r3 * 0.08, "location": [r3 * 0.32, -r3 * 0.88, z3 + r3 * 0.3], "material": "coal", "mirror": ["x"]},
        {"id": "scarf", "type": "torus", "major_radius": r3 * 0.95, "minor_radius": r3 * 0.18, "location": [0, 0, z3 - r3 * 0.75], "material": "scarf"},
        {"id": "arm", "type": "tube", "path": [[0, 0, 0], [r2 * 0.9, 0, r2 * 0.3], [r2 * 1.6, 0, r2 * 0.8]], "radius": 0.02, "radius_end": 0.008, "location": [r2 * 0.75, 0, z2], "material": "bark", "mirror": ["x"]},
    ]
    if hat:
        parts += [{"id": "hat_brim", "type": "cylinder", "radius": r3 * 0.9, "depth": 0.03, "location": [0, 0, z3 + r3 * 0.85], "material": "coal"},
                  {"id": "hat_top", "type": "cylinder", "radius": r3 * 0.6, "depth": r3 * 0.9, "location": [0, 0, z3 + r3 * 0.85 + r3 * 0.45], "material": "coal"}]
    mats = {"snow": {"color": "#f4f8fb", "roughness": 0.7}, "carrot": {"color": "#e67e22"}, "coal": {"color": "#111111", "roughness": 0.6},
            "scarf": {"color": shex, "roughness": 0.9}, "bark": {"color": "#5b3a1e"}}
    en = f"A cute snowman with a {sname} scarf" + (" and a black top hat" if hat else "")
    ar = f"رجل ثلج لطيف بوشاح {sar}" + (" وقبعة سوداء" if hat else "")
    return {"name": "snowman", "style": "cartoon", "materials": mats, "parts": parts}, en, ar, \
        {"category": "character", "organic": 0.4, "height": z3 + r3 * (2.2 if hat else 1), "checklist": ["three snow balls", "carrot nose", f"{sname} scarf"] + (["top hat"] if hat else [])}


def gen_creature():
    kind = random.choice(["cat", "dog", "dino"])
    cname, chex, car = color()
    s = U(0.8, 1.4)
    if kind == "dino":
        nodes = [[0, 0.5, 0.45, 0.06], [0, 0.25, 0.5, 0.16], [0, 0, 0.55, 0.22], [0, -0.25, 0.6, 0.18], [0, -0.4, 0.85, 0.1],
                 [0, -0.5, 1.05, 0.12], [0, -0.68, 1.02, 0.08], [0.14, 0.05, 0.2, 0.08], [0.14, 0.05, 0.03, 0.06], [-0.14, 0.05, 0.2, 0.08],
                 [-0.14, 0.05, 0.03, 0.06], [0.12, -0.3, 0.45, 0.04], [-0.12, -0.3, 0.45, 0.04], [0, 0.85, 0.3, 0.03]]
        edges = [[0, 1], [1, 2], [2, 3], [3, 4], [4, 5], [5, 6], [2, 7], [7, 8], [2, 9], [9, 10], [3, 11], [3, 12], [0, 13]]
        ar_k = "ديناصور"
    else:
        tall = 1.0 if kind == "cat" else 1.25
        nodes = [[0, 0.22, 0.28 * tall, 0.1], [0, 0, 0.3 * tall, 0.12], [0, -0.2, 0.3 * tall, 0.11], [0, -0.3, 0.45 * tall, 0.11],
                 [0.08, 0.2, 0.03, 0.04], [-0.08, 0.2, 0.03, 0.04], [0.08, -0.2, 0.03, 0.04], [-0.08, -0.2, 0.03, 0.04],
                 [0, 0.42, 0.5 * tall, 0.03], [0.06, -0.3, 0.58 * tall, 0.035], [-0.06, -0.3, 0.58 * tall, 0.035]]
        edges = [[0, 1], [1, 2], [2, 3], [0, 4], [0, 5], [2, 6], [2, 7], [0, 8], [3, 9], [3, 10]]
        ar_k = "قطة" if kind == "cat" else "كلب"
    nodes = [[round(x * s, 4), round(y * s, 4), round(z * s, 4), round(r * s, 4)] for x, y, z, r in nodes]
    zmin = min(n[2] - n[3] for n in nodes)
    parts = [{"id": "body", "type": "skin", "nodes": nodes, "edges": edges, "location": [0, 0, round(-zmin, 4)], "material": "skin"}]
    head = nodes[5] if kind == "dino" else nodes[3]
    parts.append({"id": "eye", "type": "sphere", "radius": head[3] * 0.18, "location": [round(head[3] * 0.4, 4), round(head[1] - head[3] * 0.62, 4), round(head[2] - zmin + head[3] * 0.2, 4)],
                  "material": "eye", "mirror": ["x"]})
    mats = {"skin": {"color": chex, "roughness": 0.75}, "eye": {"color": "#101010", "roughness": 0.2}}
    return {"name": kind, "style": "stylized cartoon", "materials": mats, "parts": parts}, f"A stylized {cname} {kind}", f"{ar_k} {car} بأسلوب كرتوني", \
        {"category": "creature", "organic": 0.9, "height": max(n[2] + n[3] for n in nodes) - zmin, "checklist": [kind, f"{cname} colour"]}


def gen_lamp():
    h = U(0.35, 0.6)
    cname, chex, car = color()
    parts = [
        {"id": "base", "type": "cylinder", "radius": U(0.07, 0.1), "depth": 0.025, "location": [0, 0, 0.0125], "material": "metal", "bevel": 0.004},
        {"id": "stem", "type": "cylinder", "radius": 0.01, "depth": h, "location": [0, 0, h / 2 + 0.02], "material": "metal"},
        {"id": "shade", "type": "lathe", "profile": [[0.06, 0], [0.13, -0.14], [0.125, -0.14], [0.055, 0]], "location": [0, 0, h + 0.1], "material": "shade"},
        {"id": "bulb", "type": "sphere", "radius": 0.035, "location": [0, 0, h + 0.03], "material": "bulb"},
    ]
    mats = {"metal": {"color": "#b8b8b8", "metallic": 1.0, "roughness": 0.25}, "shade": {"color": chex, "roughness": 0.8},
            "bulb": {"color": "#fff7e0", "emission": "#ffe9b0", "emission_strength": 5}}
    return {"name": "lamp", "style": "modern product", "materials": mats, "parts": parts}, f"A desk lamp with a {cname} lampshade", f"مصباح مكتب بغطاء لونه {car}", \
        {"category": "prop", "organic": 0.1, "height": h + 0.1, "checklist": ["round base", f"{cname} lampshade", "glowing bulb"]}


def gen_rocket():
    h = U(2, 5)
    cname, chex, car = color()
    r = h * 0.09
    parts = [
        {"id": "hull", "type": "lathe", "profile": [[0, 0.15 * h], [r, 0.15 * h], [r * 1.05, 0.55 * h], [r * 0.7, 0.8 * h], [r * 0.25, 0.92 * h], [0, 0.95 * h]], "location": [0, 0, 0], "material": "hull"},
        {"id": "nozzle", "type": "cone", "radius": r * 0.8, "radius_top": r * 0.5, "depth": 0.15 * h, "location": [0, 0, 0.075 * h], "material": "metal"},
        {"id": "window", "type": "torus", "major_radius": r * 0.35, "minor_radius": r * 0.07, "rotation": [90, 0, 0], "location": [0, -r * 1.02, 0.6 * h], "material": "metal"},
        {"id": "glass", "type": "sphere", "radius": r * 0.33, "scale": [1, 0.3, 1], "location": [0, -r * 0.97, 0.6 * h], "material": "glass"},
    ]
    for i in range(3):
        a = 2 * math.pi * i / 3
        parts.append({"id": f"fin_{i}", "type": "extrude", "polygon": [[0, 0], [r * 1.1, -0.05 * h], [r * 1.1, 0.12 * h], [0, 0.3 * h]], "depth": r * 0.12,
                      "rotation": [90, 0, round(math.degrees(a), 2)], "location": [round(math.cos(a) * r * 0.9, 4), round(math.sin(a) * r * 0.9, 4), 0.15 * h], "material": "fins"})
    mats = {"hull": {"color": "#ececec", "roughness": 0.35, "metallic": 0.3}, "fins": {"color": chex}, "metal": {"color": "#8a8f96", "metallic": 1, "roughness": 0.3},
            "glass": {"color": "#5fb4ff", "roughness": 0.05}}
    return {"name": "rocket", "style": "cartoon sci-fi", "materials": mats, "parts": parts}, f"A cartoon rocket with three {cname} fins and a round window", f"صاروخ كرتوني بثلاث زعانف لونها {car} ونافذة دائرية", \
        {"category": "vehicle", "organic": 0.1, "height": 0.95 * h, "checklist": [f"three {cname} fins", "round window", "nozzle"]}


GENERATORS: dict[str, Callable[[], tuple]] = {
    "chair": gen_chair, "table": gen_table, "vessel": gen_vessel, "house": gen_house, "tree": gen_tree,
    "car": gen_car, "snowman": gen_snowman, "creature": gen_creature, "lamp": gen_lamp, "rocket": gen_rocket,
}


# --------------------------------------------------------------------------- corruptions
def corrupt(spec: dict[str, Any]) -> tuple[dict[str, Any], list[str], list[dict[str, Any]], dict[str, float]] | None:
    """Break a good spec in a known way. Returns (broken, issues, repairing_patch, scores)."""
    parts = [p for p in spec["parts"] if not p.get("cutter")]
    if len(parts) < 2:
        return None
    bad = copy.deepcopy(spec)
    p = random.choice(parts)
    q = next(x for x in bad["parts"] if x["id"] == p["id"])
    kind = random.choice(["float", "remove", "recolor", "scale", "shift"])
    size = max(1e-3, max(abs(c) for c in (spec["parts"][0].get("size") or [0.5])) if spec["parts"][0].get("size") else 0.5)
    if kind == "float":
        dz = round(random.uniform(0.3, 0.8) * size + 0.2, 3)
        q["location"] = [q["location"][0], q["location"][1], round(q["location"][2] + dz, 3)]
        return bad, [f"'{p['id']}' floats {dz:.2f} m above where it should attach"], \
            [{"op": "move", "id": p["id"], "by": [0, 0, -dz]}], {"adherence": 6, "proportions": 4, "completeness": 7, "aesthetics": 5, "technical": 3}
    if kind == "remove":
        bad["parts"] = [x for x in bad["parts"] if x["id"] != p["id"]]
        for x in bad["parts"]:
            if x.get("parent") == p["id"]:
                return None
        return bad, [f"missing part: {p['id']} ({p['type']})"], [{"op": "add", "part": compact_spec({"parts": [p]})["parts"][0]}], \
            {"adherence": 5, "proportions": 7, "completeness": 4, "aesthetics": 6, "technical": 8}
    if kind == "recolor" and p.get("material"):
        m = p["material"]
        old = spec["materials"][m]["color"]
        new = random.choice([v[0] for v in PALETTE.values() if v[0] != old])
        bad["materials"][m]["color"] = new
        return bad, [f"material '{m}' has the wrong colour ({new}); it should be {old}"], \
            [{"op": "material", "name": m, "set": {"color": old}}], {"adherence": 4, "proportions": 8, "completeness": 8, "aesthetics": 5, "technical": 9}
    if kind == "scale" and q.get("size"):
        f = random.choice([0.4, 0.5, 2.0, 2.5])
        q["size"] = [round(s * f, 4) for s in q["size"]]
        return bad, [f"'{p['id']}' is {'far too big' if f > 1 else 'far too small'} relative to the rest"], \
            [{"op": "update", "id": p["id"], "set": {"size": p["size"]}}], {"adherence": 6, "proportions": 3, "completeness": 7, "aesthetics": 4, "technical": 7}
    dx = round(random.choice([-1, 1]) * random.uniform(0.25, 0.6) * size, 3)
    q["location"] = [round(q["location"][0] + dx, 3), q["location"][1], q["location"][2]]
    return bad, [f"'{p['id']}' is shifted sideways by {abs(dx):.2f} m and no longer aligned"], \
        [{"op": "move", "id": p["id"], "by": [-dx, 0, 0]}], {"adherence": 6, "proportions": 4, "completeness": 7, "aesthetics": 5, "technical": 6}


# --------------------------------------------------------------------------- dataset writer
def _example(task: str, msgs: list[dict[str, Any]], answer: Any) -> dict[str, Any]:
    def ser(m):
        c = m["content"]
        if isinstance(c, str):
            return {"role": m["role"], "content": c}
        return {"role": m["role"], "content": [x if x["type"] == "text" else {"type": "image", "image": str(x["image"])} for x in c]}
    out = [ser(m) for m in msgs]
    text = answer if isinstance(answer, str) else json.dumps(answer, separators=(",", ":"), ensure_ascii=False)
    out.append({"role": "assistant", "content": text})
    return {"task": task, "messages": out}


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", default="data/synth")
    ap.add_argument("--n", type=int, default=200)
    ap.add_argument("--res", type=int, default=256)
    ap.add_argument("--samples", type=int, default=8)
    ap.add_argument("--seed", type=int, default=0)
    ap.add_argument("--blender", default=None)
    ap.add_argument("--critic-ratio", type=float, default=0.7, help="share of models that also get a critic example")
    a = ap.parse_args()
    random.seed(a.seed)
    out = Path(a.out)
    (out / "jobs").mkdir(parents=True, exist_ok=True)
    runner = BlenderRunner(a.blender, res=a.res, samples=a.samples)
    names = list(GENERATORS)
    n_ok = 0
    with open(out / "train.jsonl", "a", encoding="utf-8") as f:
        for i in range(a.n):
            cat = names[i % len(names)]
            spec_raw, en, ar, meta = GENERATORS[cat]()
            spec, _ = normalize_spec(spec_raw)
            job = out / "jobs" / f"{i:06d}_{cat}"
            res = runner.build(spec, job, name=cat, save_blend=False)
            if not res.ok or technical_checks(res.stats).floating:
                continue  # only clean models become targets
            caption = random.choice([en, ar])
            route = {"subject": spec["name"], "category": meta["category"], "organic": meta["organic"],
                     "complexity": "medium" if len(spec["parts"]) < 12 else "high", "style": spec["style"],
                     "target_height_m": round(meta["height"], 2), "route": "procedural", "checklist": meta["checklist"]}
            photo = job / "renders" / "top_front_right.png"
            rows = [
                _example("router", P.router_messages(caption), route),
                _example("planner", P.planner_messages(caption, route), compact_spec(spec)),
                _example("planner_image", P.planner_messages("", None, photo), compact_spec(spec)),
                _example("analyst", P.analyst_messages(photo, None), {
                    "subject": spec["name"], "category": meta["category"], "organic": meta["organic"], "style": spec["style"],
                    "view": "three_quarter", "approx_height_m": round(meta["height"], 2),
                    "palette": sorted({m["color"] for m in spec["materials"].values()})[:6],
                    "description": en, "checklist": meta["checklist"]}),
            ]
            if random.random() < a.critic_ratio:
                c = corrupt(spec)
                if c is not None:
                    bad, issues, patch, scores = c
                    bad, _ = normalize_spec(bad)
                    bres = runner.build(bad, job / "corrupt", name=cat, save_blend=False)
                    if bres.ok and bres.grid:
                        tech = technical_checks(bres.stats, target_height=meta["height"])
                        overall = round(sum(scores.values()) / len(scores), 1)
                        rows.append(_example("critic", P.critic_messages(caption, bres.grid, json.dumps(compact_spec(bad), separators=(",", ":")),
                                                                          tech.text(bres.stats), meta["checklist"]),
                                             {"scores": scores, "overall": overall, "issues": issues, "patch": patch, "done": False}))
                # a clean model -> high score, nothing to fix
                if res.grid and random.random() < 0.3:
                    tech = technical_checks(res.stats, target_height=meta["height"])
                    rows.append(_example("critic", P.critic_messages(caption, res.grid, json.dumps(compact_spec(spec), separators=(",", ":")),
                                                                      tech.text(res.stats), meta["checklist"]),
                                         {"scores": {k: 9 for k in ("adherence", "proportions", "completeness", "aesthetics", "technical")},
                                          "overall": 9, "issues": [], "patch": [], "done": True}))
            for r in rows:
                f.write(json.dumps(r, ensure_ascii=False) + "\n")
            n_ok += 1
            if n_ok % 10 == 0:
                print(f"{n_ok} models done ({i + 1} tried)", flush=True)
    print(f"finished: {n_ok} models -> {out / 'train.jsonl'}")


if __name__ == "__main__":
    main()
