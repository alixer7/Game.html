#!/usr/bin/env python3
"""بناء أجسام اللاعبين والجمهور من شبكة MakeHuman (رخصة CC0).

الاستخدام:
    python3 tools/build_humans.py <مسار makehuman/data>

المخرجات (assets/characters/):
    body_<id>.glb   لاعب كامل: جسم + قميص + شورت + حذاء + شعر + عينان، هيكل عظمي من 55 عظمة
    crowd_m.glb / crowd_f.glb   متفرج جالس منخفض الدقة (MultiMesh)

الإحداثيات النهائية: متر، Y للأعلى، الشخصية تنظر إلى -Z، اليمين = +X، القدمان (مع الحذاء) على y=0.
"""
import json, os, sys, struct
import numpy as np

MH = sys.argv[1] if len(sys.argv) > 1 else "/home/claude/makehumancommunity/makehuman/makehuman/data"
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "assets", "characters")
os.makedirs(OUT, exist_ok=True)

# ------------------------------------------------------------------ تحميل الشبكة
def load_obj():
    V, VT, F, FT, G = [], [], [], [], []
    g = "?"
    for ln in open(os.path.join(MH, "3dobjs/base.obj")):
        if ln.startswith("v "):
            V.append([float(x) for x in ln.split()[1:4]])
        elif ln.startswith("vt "):
            VT.append([float(x) for x in ln.split()[1:3]])
        elif ln.startswith("g "):
            g = ln.split()[1]
        elif ln.startswith("f "):
            parts = ln.split()[1:]
            F.append([int(p.split("/")[0]) - 1 for p in parts])
            FT.append([int(p.split("/")[1]) - 1 if "/" in p and p.split("/")[1] else -1 for p in parts])
            G.append(g)
    return np.array(V), np.array(VT), F, FT, G


BASE_V, BASE_VT, FACES, FACES_T, FGROUP = load_obj()
SKEL = json.load(open(os.path.join(MH, "rigs/default.mhskel")))
WEIGHTS = json.load(open(os.path.join(MH, "rigs/default_weights.mhw")))["weights"]
_tcache = {}


def target(rel):
    if rel not in _tcache:
        p = os.path.join(MH, "targets", rel)
        idx, d = [], []
        for ln in open(p):
            if ln.startswith("#") or not ln.strip():
                continue
            a = ln.split()
            idx.append(int(a[0]))
            d.append([float(a[1]), float(a[2]), float(a[3])])
        _tcache[rel] = (np.array(idx, dtype=np.int64), np.array(d, dtype=np.float64).reshape(-1, 3))
    return _tcache[rel]


def tri_weights(v):
    """قيمة 0..1 (0.5 متوسط) ← أوزان min/average/max"""
    if v < 0.5:
        return {"min": 1.0 - v / 0.5, "average": v / 0.5, "max": 0.0}
    return {"min": 0.0, "average": 1.0 - (v - 0.5) / 0.5, "max": (v - 0.5) / 0.5}


def morph(gender=1.0, muscle=0.5, weight=0.5, height=0.5, prop=0.5, race=(1.0, 0.0, 0.0), details=None):
    V = BASE_V.copy()
    sexes = [("male", gender), ("female", 1.0 - gender)]
    mw = tri_weights(muscle)
    ww = tri_weights(weight)
    for sex, sw in sexes:
        if sw <= 0:
            continue
        for mk, mv in mw.items():
            for wk, wv in ww.items():
                k = sw * mv * wv
                if k <= 1e-4:
                    continue
                i, d = target(f"macrodetails/universal-{sex}-young-{mk}muscle-{wk}weight.target")
                V[i] += d * k
                if height != 0.5:
                    hk = "maxheight" if height > 0.5 else "minheight"
                    i, d = target(f"macrodetails/height/{sex}-young-{mk}muscle-{wk}weight-{hk}.target")
                    V[i] += d * k * abs(height - 0.5) * 2.0
                if prop != 0.5:
                    pk = "idealproportions" if prop > 0.5 else "uncommonproportions"
                    i, d = target(f"macrodetails/proportions/{sex}-young-{mk}muscle-{wk}weight-{pk}.target")
                    V[i] += d * k * abs(prop - 0.5) * 2.0
        for rname, rw in zip(("caucasian", "african", "asian"), race):
            if rw * sw > 1e-4:
                i, d = target(f"macrodetails/{rname}-{sex}-young.target")
                V[i] += d * rw * sw
    # تفاصيل إضافية: تحديد العضلات وملامح الوجه
    for rel, w in (details or {}).items():
        i, d = target(rel + ".target")
        if len(i):
            V[i] += d * w
    return V


def joint_pos(V, name):
    return V[SKEL["joints"][name]].mean(axis=0)


# ------------------------------------------------------------------ الهيكل المختصر
SIDES = ("L", "R")
FINGERS = [("Thumb", 1), ("Index", 2), ("Middle", 3), ("Ring", 4), ("Pinky", 5)]


def reduced_map():
    """عظام MakeHuman ← عظامنا"""
    m = {}
    for b in SKEL["bones"]:
        t = None
        if b in ("root", "spine05", "pelvis.L", "pelvis.R"):
            t = "Hips"
        elif b in ("spine04", "spine03"):
            t = "Spine"
        elif b in ("spine02", "spine01", "breast.L", "breast.R"):
            t = "Chest"
        elif b.startswith("neck"):
            t = "Neck"
        else:
            side = b[-1] if b[-2:] in (".L", ".R") else None
            base = b[:-2] if side else b
            if side:
                if base in ("clavicle", "shoulder01"):
                    t = "Clavicle." + side
                elif base == "upperarm01":
                    t = "UpperArm." + side
                elif base == "upperarm02":
                    t = "UpperArmTwist." + side
                elif base == "lowerarm01":
                    t = "ForeArm." + side
                elif base == "lowerarm02":
                    t = "ForeArmTwist." + side
                elif base == "wrist" or base.startswith("metacarpal"):
                    t = "Hand." + side
                elif base.startswith("finger"):
                    n, k = base[6:].split("-")
                    t = f"{FINGERS[int(n) - 1][0]}{k}.{side}"
                elif base in ("upperleg01", "upperleg02"):
                    t = "UpLeg." + side
                elif base in ("lowerleg01", "lowerleg02"):
                    t = "Leg." + side
                elif base == "foot":
                    t = "Foot." + side
                elif base.startswith("toe"):
                    t = "Toes." + side
            if t is None:
                t = "Head"     # الوجه والعينان والفك…
        m[b] = t
    return m


BMAP = reduced_map()


def build_skeleton(V):
    J = lambda n: joint_pos(V, n)
    H = lambda b: J(SKEL["bones"][b]["head"])
    T = lambda b: J(SKEL["bones"][b]["tail"])
    bones = []   # (name, parent, head, tail, hint)
    back = np.array([0, 0, 1.0])
    up = np.array([0, 1.0, 0])
    fwd = np.array([0, 0, -1.0])
    bones.append(("Hips", None, H("spine05"), H("spine04"), back))
    bones.append(("Spine", "Hips", H("spine04"), T("spine03"), back))
    bones.append(("Chest", "Spine", H("spine02"), T("spine01"), back))
    bones.append(("Neck", "Chest", H("neck01"), T("neck03"), back))
    bones.append(("Head", "Neck", H("head"), T("head"), back))
    for s in SIDES:
        bones.append((f"Clavicle.{s}", "Chest", H(f"clavicle.{s}"), H(f"upperarm01.{s}"), back))
        sh, el, wr = H(f"upperarm01.{s}"), H(f"lowerarm01.{s}"), H(f"wrist.{s}")
        # اتجاه المرفق في وضع الراحة
        d = wr - sh
        d /= np.linalg.norm(d)
        e = el - sh
        e = e - d * e.dot(d)
        pole = e / np.linalg.norm(e) if np.linalg.norm(e) > 0.004 else back
        bones.append((f"UpperArm.{s}", f"Clavicle.{s}", sh, H(f"upperarm02.{s}"), pole))
        bones.append((f"UpperArmTwist.{s}", f"UpperArm.{s}", H(f"upperarm02.{s}"), el, pole))
        bones.append((f"ForeArm.{s}", f"UpperArmTwist.{s}", el, H(f"lowerarm02.{s}"), pole))
        bones.append((f"ForeArmTwist.{s}", f"ForeArm.{s}", H(f"lowerarm02.{s}"), wr, pole))
        mid = H(f"finger3-1.{s}")
        hy = mid - wr
        hy /= np.linalg.norm(hy)
        across = H(f"finger2-1.{s}") - H(f"finger5-1.{s}")
        dors = np.cross(across, hy)
        dors /= np.linalg.norm(dors)
        outward = np.array([1.0 if wr[0] > 0 else -1.0, 0, 0])
        if dors.dot(outward) < 0:
            dors = -dors
        bones.append((f"Hand.{s}", f"ForeArmTwist.{s}", wr, mid, dors))
        for fname, n in FINGERS:
            parent = f"Hand.{s}"
            for k in (1, 2, 3):
                b = f"finger{n}-{k}.{s}"
                bones.append((f"{fname}{k}.{s}", parent, H(b), T(b), dors))
                parent = f"{fname}{k}.{s}"
        hip, knee, ank = H(f"upperleg01.{s}"), H(f"lowerleg01.{s}"), H(f"foot.{s}")
        bones.append((f"UpLeg.{s}", "Hips", hip, knee, fwd))
        bones.append((f"Leg.{s}", f"UpLeg.{s}", knee, ank, fwd))
        ball = np.mean([H(f"toe{i}-1.{s}") for i in range(1, 6)], axis=0)
        tip = np.mean([T(f"toe1-2.{s}"), T(f"toe2-3.{s}"), T(f"toe3-3.{s}")], axis=0)
        bones.append((f"Foot.{s}", f"Leg.{s}", ank, ball, up))
        bones.append((f"Toes.{s}", f"Foot.{s}", ball, tip, up))
    return bones


def frame(head, tail, hint):
    y = tail - head
    y = y / np.linalg.norm(y)
    z = hint - y * hint.dot(y)
    if np.linalg.norm(z) < 1e-5:
        z = np.array([0, 0, 1.0]) - y * y[2]
    z /= np.linalg.norm(z)
    x = np.cross(y, z)
    return np.stack([x, y, z], axis=1)   # أعمدة = محاور


def bone_weights(nverts, names):
    idx = {n: i for i, n in enumerate(names)}
    acc = [dict() for _ in range(nverts)]
    for b, lst in WEIGHTS.items():
        t = idx[BMAP[b]]
        for vi, w in lst:
            if vi < nverts:
                acc[vi][t] = acc[vi].get(t, 0.0) + w
    J = np.zeros((nverts, 4), dtype=np.uint16)
    W = np.zeros((nverts, 4), dtype=np.float32)
    for vi, d in enumerate(acc):
        items = sorted(d.items(), key=lambda kv: -kv[1])[:4]
        if not items:
            items = [(idx["Hips"], 1.0)]
        s = sum(w for _, w in items)
        for k, (j, w) in enumerate(items):
            J[vi, k] = j
            W[vi, k] = w / s
    return J, W


# ------------------------------------------------------------------ أدوات الشبكة
def vertex_normals(V, tris):
    n = np.zeros_like(V)
    a, b, c = V[tris[:, 0]], V[tris[:, 1]], V[tris[:, 2]]
    fn = np.cross(b - a, c - a)
    for k in range(3):
        np.add.at(n, tris[:, k], fn)
    ln = np.linalg.norm(n, axis=1, keepdims=True)
    return n / np.maximum(ln, 1e-9)


def quads_to_tris(faces):
    out = []
    for f in faces:
        if len(f) == 4:
            out += [[f[0], f[1], f[2]], [f[0], f[2], f[3]]]
        else:
            out.append(list(f[:3]))
    return np.array(out, dtype=np.int64)


def neighbors(nv, faces):
    nb = [set() for _ in range(nv)]
    for f in faces:
        k = len(f)
        for i in range(k):
            a, b = f[i], f[(i + 1) % k]
            nb[a].add(b)
            nb[b].add(a)
    return nb


def laplacian(P, nb, verts, iters, lam=0.5, fixed=None):
    P = P.copy()
    vl = list(verts)
    for _ in range(iters):
        Q = P.copy()
        for v in vl:
            if fixed is not None and v in fixed:
                continue
            ns = [u for u in nb[v] if u in verts]
            if ns:
                Q[v] = P[v] + lam * (P[ns].mean(axis=0) - P[v])
        P = Q
    return P


def cavity(V, N, nb, verts):
    """تجويف تقريبي (بديل رخيص لـ AO): متوسط ميل الجيران نحو الداخل"""
    c = np.ones(len(V))
    for v in verts:
        ns = list(nb[v])
        if not ns:
            continue
        d = V[ns] - V[v]
        l = np.linalg.norm(d, axis=1)
        k = (d @ N[v]) / np.maximum(l, 1e-9)
        c[v] = np.clip(1.0 - np.mean(np.maximum(k, 0.0)) * 1.6, 0.35, 1.0)
    return c


# ------------------------------------------------------------------ كاتب glTF
class GLB:
    def __init__(self):
        self.bin = bytearray()
        self.views, self.accs = [], []

    def add(self, arr, ctype, typ, target=None, minmax=False):
        arr = np.ascontiguousarray(arr)
        while len(self.bin) % 4:
            self.bin += b"\0"
        off = len(self.bin)
        self.bin += arr.tobytes()
        v = {"buffer": 0, "byteOffset": off, "byteLength": arr.nbytes}
        if target:
            v["target"] = target
        self.views.append(v)
        acc = {"bufferView": len(self.views) - 1, "componentType": ctype, "count": int(arr.shape[0]), "type": typ}
        if minmax:
            acc["min"] = arr.min(axis=0).tolist()
            acc["max"] = arr.max(axis=0).tolist()
        self.accs.append(acc)
        return len(self.accs) - 1

    def write(self, path, js):
        js["buffers"] = [{"byteLength": len(self.bin)}]
        js["bufferViews"] = self.views
        js["accessors"] = self.accs
        j = json.dumps(js, separators=(",", ":")).encode()
        while len(j) % 4:
            j += b" "
        while len(self.bin) % 4:
            self.bin += b"\0"
        total = 12 + 8 + len(j) + 8 + len(self.bin)
        with open(path, "wb") as f:
            f.write(struct.pack("<III", 0x46546C67, 2, total))
            f.write(struct.pack("<II", len(j), 0x4E4F534A))
            f.write(j)
            f.write(struct.pack("<II", len(self.bin), 0x004E4942))
            f.write(self.bin)


def export_glb(path, bones, rest_global, parts):
    """parts: [(name, material, P, N, UV, COL, J, W, tris)]"""
    g = GLB()
    names = [b[0] for b in bones]
    nodes, meshes, materials = [], [], []
    mat_idx = {}
    for i, b in enumerate(bones):
        R = rest_global[i]
        if b[1] is None:
            L = R
        else:
            L = np.linalg.inv(rest_global[names.index(b[1])]) @ R
        q = mat_to_quat(L[:3, :3])
        nodes.append({"name": b[0], "translation": L[:3, 3].tolist(), "rotation": q})
    for i, b in enumerate(bones):
        ch = [k for k, c in enumerate(bones) if c[1] == b[0]]
        if ch:
            nodes[i]["children"] = ch
    ibm = np.stack([np.linalg.inv(R).T for R in rest_global]).astype(np.float32).reshape(-1, 16)
    ibm_acc = g.add(ibm, 5126, "MAT4")
    skin = {"joints": list(range(len(bones))), "inverseBindMatrices": ibm_acc, "skeleton": 0}
    mesh_nodes = []
    for (pname, mname, P, N, UV, COL, J, W, tris) in parts:
        if mname not in mat_idx:
            mat_idx[mname] = len(materials)
            materials.append({"name": mname, "pbrMetallicRoughness": {"baseColorFactor": [0.8, 0.8, 0.8, 1], "metallicFactor": 0, "roughnessFactor": 0.8}})
        attrs = {
            "POSITION": g.add(P.astype(np.float32), 5126, "VEC3", 34962, True),
            "NORMAL": g.add(N.astype(np.float32), 5126, "VEC3", 34962),
            "JOINTS_0": g.add(J.astype(np.uint16), 5123, "VEC4", 34962),
            "WEIGHTS_0": g.add(W.astype(np.float32), 5126, "VEC4", 34962),
        }
        if UV is not None:
            attrs["TEXCOORD_0"] = g.add(UV.astype(np.float32), 5126, "VEC2", 34962)
        if COL is not None:
            attrs["COLOR_0"] = g.add(COL.astype(np.float32), 5126, "VEC4", 34962)
        ind = g.add(tris.astype(np.uint32).reshape(-1), 5125, "SCALAR", 34963)
        meshes.append({"name": pname, "primitives": [{"attributes": attrs, "indices": ind, "material": mat_idx[mname]}]})
        mesh_nodes.append({"name": pname, "mesh": len(meshes) - 1, "skin": 0})
    base = len(nodes)
    nodes += mesh_nodes
    nodes.append({"name": "Human", "children": [0] + list(range(base, base + len(mesh_nodes)))})
    js = {"asset": {"version": "2.0", "generator": "match_point build_humans.py (MakeHuman CC0 data)"},
          "scene": 0, "scenes": [{"nodes": [len(nodes) - 1]}], "nodes": nodes, "meshes": meshes,
          "materials": materials, "skins": [skin]}
    g.write(path, js)


def mat_to_quat(m):
    t = np.trace(m)
    if t > 0:
        s = np.sqrt(t + 1.0) * 2
        w = 0.25 * s
        x = (m[2, 1] - m[1, 2]) / s
        y = (m[0, 2] - m[2, 0]) / s
        z = (m[1, 0] - m[0, 1]) / s
    elif m[0, 0] > m[1, 1] and m[0, 0] > m[2, 2]:
        s = np.sqrt(1.0 + m[0, 0] - m[1, 1] - m[2, 2]) * 2
        w = (m[2, 1] - m[1, 2]) / s
        x = 0.25 * s
        y = (m[0, 1] + m[1, 0]) / s
        z = (m[0, 2] + m[2, 0]) / s
    elif m[1, 1] > m[2, 2]:
        s = np.sqrt(1.0 + m[1, 1] - m[0, 0] - m[2, 2]) * 2
        w = (m[0, 2] - m[2, 0]) / s
        x = (m[0, 1] + m[1, 0]) / s
        y = 0.25 * s
        z = (m[1, 2] + m[2, 1]) / s
    else:
        s = np.sqrt(1.0 + m[2, 2] - m[0, 0] - m[1, 1]) * 2
        w = (m[1, 0] - m[0, 1]) / s
        x = (m[0, 2] + m[2, 0]) / s
        y = (m[1, 2] + m[2, 1]) / s
        z = 0.25 * s
    q = np.array([x, y, z, w])
    return (q / np.linalg.norm(q)).tolist()


# ------------------------------------------------------------------ تجهيز إنسان
BODY_FACES = [i for i, g in enumerate(FGROUP) if g == "body"]
EYE_FACES = {s: [i for i, g in enumerate(FGROUP) if g == f"helper-{s.lower()}-eye"] for s in ("L", "R")}


def prepare(height_m, **mkw):
    V = morph(**mkw)
    body_vid = sorted(set(v for i in BODY_FACES for v in FACES[i]))
    ymin = V[body_vid, 1].min()
    ymax = V[body_vid, 1].max()
    s = height_m / (ymax - ymin)
    V = (V - np.array([0, ymin, 0])) * s
    V[:, 0] *= -1.0      # تدوير 180° حول Y: الوجه نحو -Z
    V[:, 2] *= -1.0
    bones = build_skeleton(V)
    # الأسماء: MakeHuman ".L" = يسار الشخصية = -X بعد التدوير ✓
    return V, bones


def rest_globals(bones):
    out = []
    for b in bones:
        M = np.eye(4)
        M[:3, :3] = frame(b[2], b[3], b[4])
        M[:3, 3] = b[2]
        out.append(M)
    return out


def dominant(J, W, names, groups):
    """مجموع أوزان مجموعة عظام لكل رأس"""
    ids = [i for i, n in enumerate(names) if any(n.startswith(g) for g in groups)]
    m = np.isin(J, ids)
    return (W * m).sum(axis=1)


def build_player(pid, height_m, hair_style, sleeve=0.55, short_len=0.30, **mkw):
    V, bones = prepare(height_m, **mkw)
    names = [b[0] for b in bones]
    RG = rest_globals(bones)
    J, W = bone_weights(len(V), names)
    bpos = {b[0]: b[2] for b in bones}
    btail = {b[0]: b[3] for b in bones}

    faces = [FACES[i] for i in BODY_FACES]
    tfaces = [FACES_T[i] for i in BODY_FACES]
    nb = neighbors(len(V), faces)
    body_v = set(v for f in faces for v in f)
    tris_all = quads_to_tris(faces)
    N = vertex_normals(V, tris_all)

    w_arm = dominant(J, W, names, ["UpperArm", "ForeArm", "Hand", "Thumb", "Index", "Middle", "Ring", "Pinky"])
    w_hand = dominant(J, W, names, ["Hand", "Thumb", "Index", "Middle", "Ring", "Pinky"])
    w_leg = dominant(J, W, names, ["UpLeg", "Leg", "Foot", "Toes"])
    w_foot = dominant(J, W, names, ["Foot", "Toes"])
    w_head = dominant(J, W, names, ["Head", "Neck"])
    w_headonly = dominant(J, W, names, ["Head"])

    hip_y = bpos["Hips"][1]
    knee_y = (bpos["Leg.L"][1] + bpos["Leg.R"][1]) * 0.5
    ank_y = (bpos["Foot.L"][1] + bpos["Foot.R"][1]) * 0.5
    neck_y = bpos["Neck"][1]
    Y = V[:, 1]

    # ---------- المناطق ----------
    def arm_param(v):
        """بُعد الرأس على امتداد العضد من الكتف (نسبة لطول العضد)"""
        s = "L" if V[v, 0] < 0 else "R"
        sh = bpos[f"UpperArm.{s}"]
        el = bpos[f"ForeArm.{s}"]
        d = el - sh
        L = np.linalg.norm(d)
        return (V[v] - sh).dot(d / L) / L

    shirt, shorts, shoes = set(), set(), set()
    shirt_core, shorts_core = set(), set()
    hem_y = hip_y - 0.07
    cut_y = knee_y + 0.125
    collar_shoe = ank_y + 0.042
    for v in body_v:
        if w_hand[v] > 0.2:
            continue
        if w_arm[v] > 0.45:
            if Y[v] > hip_y:
                t = arm_param(v)
                if t < sleeve + 0.12:
                    shirt.add(v)
                if t < sleeve - 0.05:
                    shirt_core.add(v)
            continue
        if Y[v] > hem_y - 0.05 and Y[v] < neck_y + 0.01 and w_head[v] < 0.45:
            shirt.add(v)
            if Y[v] > hem_y + 0.03:
                shirt_core.add(v)
        if hip_y + 0.03 > Y[v] > cut_y - 0.05 and w_arm[v] < 0.3:
            shorts.add(v)
            if Y[v] > cut_y + 0.03:
                shorts_core.add(v)
        if w_foot[v] > 0.3 and Y[v] < collar_shoe:
            shoes.add(v)
    # الشعر: فروة الرأس فوق خط الشعر
    hc = (bpos["Head"] + btail["Head"]) * 0.5
    eyes_c = {s: V[sorted(set(v for i in EYE_FACES[s] for v in FACES[i]))].mean(axis=0) for s in ("L", "R")}
    eye_y = (eyes_c["L"][1] + eyes_c["R"][1]) * 0.5
    hair = set()
    hair_lvl = {"short": 0.0, "buzz": 0.005, "medium": -0.012, "curly": -0.008}[hair_style]
    # المسافة الموقّعة عن خط الشعر التحليلي (موجبة = داخل الشعر): تُخزَّن في ألوان الرؤوس فيتبع
    # قناع فروة الرأس وحافة قشرة الشعر منحنى ناعماً بدل حواف المضلعات المسننة
    hair_sd = np.full(len(V), -1.0)
    for v in body_v:
        if w_headonly[v] < 0.5:
            continue
        d = V[v] - hc
        dl = np.linalg.norm(d[[0, 2]])
        f = -d[2] / max(dl, 1e-6)                # 1 أمام، -1 خلف
        side = abs(d[0]) / max(dl, 1e-6)
        if f > 0.0:
            # خط شعر طبيعي: أعلى في منتصف الجبهة مع انحسار خفيف عند الصدغين
            thr = eye_y + 0.022 + 0.046 * f ** 1.5 + 0.010 * np.exp(-((f - 0.70) / 0.13) ** 2)
        else:
            thr = eye_y + 0.022 + 0.085 * f     # نزولاً نحو القفا
        thr += hair_lvl
        # استبعاد الأذنين
        ear = side > 0.88 and eye_y - 0.045 < V[v, 1] < eye_y + 0.028 and f > -0.45
        sd = V[v, 1] - thr
        if ear:
            sd = min(sd, -0.012)
        hair_sd[v] = sd
        if sd > -0.009 and not ear and w_headonly[v] >= 0.85:
            hair.add(v)

    # ---------- قشرة الملابس ----------
    def shell(region, off_fn, smooth, min_off, double_hem=True, snap=None, taper=0, drape=None):
        rf = [f for f in faces if all(v in region for v in f)]
        rv = sorted(set(v for f in rf for v in f))
        P = V.copy()
        for v in rv:
            P[v] = V[v] + N[v] * off_fn(v)
        if drape is not None:      # القماش يتدلى باستقامة بدل الالتصاق بالجسم
            for v in rv:
                P[v] = drape(v, P[v])
        bnd = set()
        for v in rv:
            if any(u not in region for u in nb[v]):
                bnd.add(v)
        P = laplacian(P, nb, set(rv), smooth, 0.5)
        if taper > 0:     # سماكة تتلاشى نحو الحافة (شعر يندمج مع فروة الرأس)
            ring = set(bnd)
            dist = {v: 0 for v in bnd}
            for r in range(1, taper + 1):
                ring = set(u for v in ring for u in nb[v] if u in region and u not in dist)
                for u in ring:
                    dist[u] = r
            for v, r in dist.items():
                P[v] = V[v] + (P[v] - V[v]) * (0.25 + 0.75 * r / (taper + 1))
        for v in rv:   # لا اختراق للجسم بعد التنعيم
            d = P[v] - V[v]
            k = d.dot(N[v])
            if k < min_off:
                P[v] += N[v] * (min_off - k)
        if snap is not None:   # قصّ بمستوى: حاشية مستقيمة نظيفة
            for v in rv:
                P[v] = snap(v, P[v])
        remap = {v: i for i, v in enumerate(rv)}
        quads = [[remap[v] for v in f] for f in rf]
        Pn = P[rv]
        Jn, Wn = J[rv], W[rv]
        # حاشية داخلية تُظهر سماكة القماش
        if double_hem:
            edges = {}
            for f in quads:
                for i in range(len(f)):
                    a, b = f[i], f[(i + 1) % len(f)]
                    key = (min(a, b), max(a, b))
                    edges[key] = edges.get(key, 0) + 1
            border = [(a, b) for f in quads for a, b in zip(f, f[1:] + f[:1]) if edges[(min(a, b), max(a, b))] == 1]
            extra = {}
            Pl, Jl, Wl = list(Pn), list(Jn), list(Wn)
            for a, b in border:
                for x in (a, b):
                    if x not in extra:
                        src = rv[x]
                        extra[x] = len(Pl)
                        Pl.append(Pn[x] - N[src] * (off_fn(src) * 0.75))
                        Jl.append(Jn[x])
                        Wl.append(Wn[x])
                quads.append([b, a, extra[a], extra[b]])
            Pn, Jn, Wn = np.array(Pl), np.array(Jl), np.array(Wl)
        return Pn, Jn, Wn, quads, rv, bnd

    loose = {}

    def off_shirt(v):
        if w_arm[v] > 0.45:
            t = np.clip(arm_param(v) / sleeve, 0, 1)
            loose[v] = t * t
            return 0.009 + 0.024 * t * t
        low = np.clip((hip_y + 0.18 - Y[v]) / 0.25, 0, 1)
        return 0.011 + 0.016 * low

    # تدلّي القميص: تحت مستوى الصدر يأخذ القماش محيط الصدر تقريباً بدل تتبّع الخصر
    pec_y = neck_y - 0.21
    zc = bpos["Chest"][2]
    NB = 48
    Rb = np.zeros(NB)
    for v in body_v:
        if abs(Y[v] - pec_y) < 0.05 and w_arm[v] < 0.3:
            a = np.arctan2(V[v, 2] - zc, V[v, 0])
            b = int((a + np.pi) / (2 * np.pi) * NB) % NB
            Rb[b] = max(Rb[b], np.hypot(V[v, 0], V[v, 2] - zc))
    for _ in range(3):
        for b in range(NB):
            if Rb[b] == 0:
                Rb[b] = max(Rb[(b - 1) % NB], Rb[(b + 1) % NB])
    Rb = (np.roll(Rb, 1) + 2 * Rb + np.roll(Rb, -1)) / 4.0

    def drape_shirt(v, p):
        if w_arm[v] > 0.45 or Y[v] >= pec_y:
            return p
        f = np.clip((pec_y - Y[v]) / 0.20, 0, 1)
        f = f * f * (3 - 2 * f)
        loose[v] = f
        dx, dz = p[0], p[2] - zc
        r = np.hypot(dx, dz)
        a = (np.arctan2(dz, dx) + np.pi) / (2 * np.pi) * NB
        b0 = int(np.floor(a)) % NB
        fr = a - np.floor(a)
        rt = (Rb[b0] * (1 - fr) + Rb[(b0 + 1) % NB] * fr) * 0.97
        if rt > r:
            r2 = r + (rt - r) * f * 0.92
            return np.array([dx * r2 / r, p[1], zc + dz * r2 / r])
        return p

    def off_shorts(v):
        t = np.clip((hip_y - Y[v]) / (hip_y - knee_y), 0, 1)
        loose[v] = max(loose.get(v, 0.0), t) if v not in shirt else loose.get(v, 0.0)
        return 0.006 + 0.036 * t ** 1.5

    def off_shoes(v):
        return 0.009 if Y[v] > ank_y - 0.04 else 0.012

    def off_hair(v):
        top = np.clip((V[v, 1] - eye_y - 0.03) / 0.09, 0, 1)
        fr = np.clip(-(V[v, 2] - hc[2]) / 0.09, 0, 1)      # كثافة أكبر فوق الجبهة
        return {"short": 0.004 + 0.011 * top + 0.006 * top * fr, "buzz": 0.0025 + 0.002 * top,
                "medium": 0.006 + 0.020 * top + 0.008 * top * fr, "curly": 0.008 + 0.022 * top + 0.006 * fr}[hair_style]

    def snap_shirt(v, p):
        if w_arm[v] > 0.45:
            sd = "L" if V[v, 0] < 0 else "R"
            a, b = bpos[f"UpperArm.{sd}"], bpos[f"ForeArm.{sd}"]
            L = np.linalg.norm(b - a)
            d = (b - a) / L
            t = (p - a).dot(d) / L
            if t > sleeve:
                return p - d * (t - sleeve) * L
            return p
        if p[1] < hem_y:
            return np.array([p[0], hem_y, p[2]])
        return p

    def snap_shorts(v, p):
        if p[1] < cut_y:
            return np.array([p[0], cut_y, p[2]])
        return p

    sh = shell(shirt, off_shirt, 7, 0.006, True, snap_shirt, 0, drape_shirt)
    loose_shirt = dict(loose)
    loose.clear()
    so = shell(shorts, off_shorts, 5, 0.005, True, snap_shorts)
    loose_shorts = dict(loose)
    ha = shell(hair, off_hair, 3 if hair_style != "curly" else 2, 0.0015, False, None, 3)

    # ---------- الحذاء: مجسم مُشكَّل (loft) حول القدم ----------
    shoe_parts = []
    floor_y = None
    for sd in ("L", "R"):
        fv = [v for v in body_v if w_foot[v] > 0.5 and (V[v, 0] < 0) == (sd == "L")]
        A = bpos[f"Foot.{sd}"]
        B = bpos[f"Toes.{sd}"]
        f = B - A
        f[1] = 0
        f /= np.linalg.norm(f)
        up = np.array([0, 1.0, 0])
        lat = np.cross(f, up)            # يمين القدم
        rel = V[fv] - A
        along = rel @ f
        side_ = rel @ lat
        heel, tip = along.min() - 0.012, along.max() + 0.014
        fy = V[fv, 1].min() - 0.012
        floor_y = fy if floor_y is None else min(floor_y, fy)
        Ls = tip - heel
        mid_off = np.median(side_)
        nsec, nring = 18, 16
        P, C, Jl, Wl, quads = [], [], [], [], []
        foot_id, toe_id = names.index(f"Foot.{sd}"), names.index(f"Toes.{sd}")
        for i in range(nsec + 1):
            t = i / nsec
            x = heel + Ls * t
            band = np.abs(along - x) < Ls / nsec
            if band.sum() > 3:
                wl, wr = side_[band].min() - 0.010, side_[band].max() + 0.010
            else:
                wl, wr = mid_off - 0.04, mid_off + 0.04
            cen = (wl + wr) * 0.5
            hw = (wr - wl) * 0.5
            # تدوير مقدمة الحذاء والكعب
            cap = 1.0
            if t > 0.86:
                cap = np.sqrt(max(1 - ((t - 0.86) / 0.14) ** 2, 0.02))
            elif t < 0.08:
                cap = np.sqrt(max(1 - ((0.08 - t) / 0.08) ** 2, 0.15))
            hw *= cap
            top = collar_shoe if t < 0.30 else collar_shoe + (0.055 + fy - collar_shoe) * min((t - 0.30) / 0.45, 1.0)
            if t > 0.75:
                top = fy + 0.055 - 0.02 * (t - 0.75) / 0.25
            top = fy + (top - fy) * (cap if t > 0.86 else 1.0)
            ht = max(top - fy, 0.012)
            for j in range(nring):
                a = 2 * np.pi * j / nring
                cx, cy = np.cos(a), np.sin(a)
                ex = np.sign(cx) * abs(cx) ** 0.6
                ey = np.sign(cy) * abs(cy) ** (0.5 if cy < 0 else 0.9)
                pos = A + f * x + lat * (cen + ex * hw) + up * 0.0
                pos[1] = fy + (ey * 0.5 + 0.5) * ht
                P.append(pos)
                sole = 1.0 if pos[1] < fy + 0.022 else 0.0
                stripe = 1.0 if (abs(cx) > 0.6 and 0.28 < t < 0.72 and abs((pos[1] - fy) - 0.035 - 0.05 * (t - 0.28)) < 0.010) else 0.0
                C.append([sole, stripe, 0, 1])
                k = np.clip((t - 0.70) / 0.14, 0, 1)
                Jl.append([foot_id, toe_id, 0, 0])
                Wl.append([1 - k, k, 0, 0])
        for i in range(nsec):
            for j in range(nring):
                a = i * nring + j
                b = i * nring + (j + 1) % nring
                quads.append([a, b, b + nring, a + nring])
        # غطاء الكعب والمقدمة
        for i0, flip in ((0, True), (nsec, False)):
            cidx = len(P)
            P.append(np.mean(P[i0 * nring:(i0 + 1) * nring], axis=0))
            C.append([0, 0, 0, 1])
            Jl.append(Jl[i0 * nring])
            Wl.append(Wl[i0 * nring])
            for j in range(nring):
                a = i0 * nring + j
                b = i0 * nring + (j + 1) % nring
                quads.append([cidx, a, b] if flip else [cidx, b, a])
        shoe_parts.append((np.array(P), np.array(C), np.array(Jl, np.uint16), np.array(Wl, np.float32), quads))

    # ---------- الجسم: إزالة الأوجه المخفية تحت الملابس ----------
    def interior(region, rings=2):
        bnd = set(v for v in region if any(u not in region for u in nb[v]))
        keep = set(bnd)
        frontier = set(bnd)
        for _ in range(rings):
            nxt = set()
            for v in frontier:
                nxt |= set(u for u in nb[v] if u in region)
            keep |= nxt
            frontier = nxt
        return region - keep

    hidden = interior(shirt_core, 1) | interior(shorts_core, 1) | set(v for v in shoes if Y[v] < collar_shoe - 0.012)
    body_quads, body_tquads = [], []
    for f, ft in zip(faces, tfaces):
        if all(v in hidden for v in f):
            continue
        body_quads.append(f)
        body_tquads.append(ft)

    # ---------- ألوان رؤوس الجلد: r شفاه، g شعر/حاجب/لحية، b جورب، a تجويف ----------
    cav = cavity(V, N, nb, body_v)
    col = np.zeros((len(V), 4))
    col[:, 3] = cav
    for v in body_v:
        if hair_sd[v] > -0.5:
            col[v, 1] = float(np.clip(0.5 + hair_sd[v] / 0.024, 0.0, 1.0))
    for v in body_v:
        if w_leg[v] > 0.5 and ank_y - 0.01 < Y[v] < ank_y + 0.075:
            col[v, 2] = 1.0

    # ---------- تقسيم الرؤوس حسب UV ----------
    def split_uv(quads, tquads):
        keymap = {}
        P, UV, idx = [], [], []
        for f, ft in zip(quads, tquads):
            out = []
            for v, t in zip(f, ft):
                k = (v, t)
                if k not in keymap:
                    keymap[k] = len(P)
                    P.append(v)
                    UV.append(BASE_VT[t] if t >= 0 else [0, 0])
                out.append(keymap[k])
            idx.append(out)
        P = np.array(P)
        UV = np.array(UV)
        UV[:, 1] = 1.0 - UV[:, 1]
        return P, UV, idx

    src, UV, bquads = split_uv(body_quads, body_tquads)
    btris = quads_to_tris(bquads)
    parts = [("Body", "skin", V[src], N[src], UV, col[src], J[src], W[src], btris)]

    def shell_part(name, mat, s, colf=None):
        P, Js, Ws, quads, rv, _ = s
        t = quads_to_tris(quads)
        Nn = vertex_normals(P, t)
        C = np.zeros((len(P), 4))
        C[:, 3] = 1.0
        if colf is not None:
            for i in range(len(P)):
                C[i] = colf(P[i], i < len(rv) and i, rv[i] if i < len(rv) else None)
        UVs = np.stack([P[:, 0] + P[:, 2] * 0.7, P[:, 1]], axis=1) * 4.0
        return (name, mat, P, Nn, UVs, C, Js, Ws, t)

    collar_y = neck_y - 0.03

    def shirt_col(p, _i, src_v):
        c = [0, 0, 0, 1]
        if src_v is not None:
            if w_arm[src_v] > 0.45 and arm_param(src_v) > sleeve - 0.08:
                c[0] = 1.0                       # حافة الكم
            if p[1] > collar_y and w_arm[src_v] < 0.3:
                c[0] = 1.0                       # الياقة
            c[1] = 1.0 if p[2] > hc[2] - 0.0 else 0.0   # الظهر (للون ثانٍ)
            c[2] = loose_shirt.get(src_v, 0.0)           # مقدار ارتخاء القماش (للرفرفة)
        return c

    def shorts_col(p, _i, src_v):
        c = [0, 0, 0, 1]
        if src_v is not None:
            c[2] = loose_shorts.get(src_v, 0.0)
        if src_v is not None and Y[src_v] > hip_y + 0.045:
            c[0] = 1.0                           # حزام الخصر
        if src_v is not None and Y[src_v] < hip_y + 0.04:
            sd = "L" if V[src_v, 0] < 0 else "R"
            kx = bpos[f"UpLeg.{sd}"]
            outward = (V[src_v, 0] - kx[0]) * np.sign(V[src_v, 0])
            if outward > 0 and abs(V[src_v, 2] - kx[2]) < 0.0:
                c[1] = 1.0                       # (معطّل) شريط جانبي
        return c

    parts.append(shell_part("Shirt", "shirt", sh, shirt_col))
    parts.append(shell_part("Shorts", "shorts", so, shorts_col))
    for k, (P, C, Js, Ws, quads) in enumerate(shoe_parts):
        t = quads_to_tris(quads)
        UVs = np.stack([P[:, 0] + P[:, 2], P[:, 1]], axis=1) * 4.0
        parts.append((f"Shoe.{'LR'[k]}", "shoes", P, vertex_normals(P, t), UVs, C, Js, Ws, t))
    # الشعر: تلاشٍ تدريجي نحو خط الشعر (COLOR.r) يكسره شيدر الشعر إلى خصلات بدل حافة مسننة
    hP, hJ, hW, hquads, hrv, hbnd = ha
    hpart = shell_part("Hair", "hair", ha)
    hidx = {v: i for i, v in enumerate(hrv)}
    hdist = {v: 0 for v in hbnd}
    ring = set(hbnd)
    for r_ in range(1, 5):
        ring = set(u for v in ring for u in nb[v] if u in hair and u not in hdist)
        for u in ring:
            hdist[u] = r_
    hC = hpart[5].copy()
    for v, i in hidx.items():
        hC[i, 0] = float(np.clip((hair_sd[v] + 0.001) / 0.016, 0.0, 1.0)) * min(hdist.get(v, 5) / 1.0, 1.0)
    parts.append(hpart[:5] + (hC,) + hpart[6:])

    # ---------- العينان: كرتان ملساء ----------
    head_id = names.index("Head")
    for s in ("L", "R"):
        ev = sorted(set(v for i in EYE_FACES[s] for v in FACES[i]))
        c = V[ev].mean(axis=0)
        r = np.percentile(np.linalg.norm(V[ev] - c, axis=1), 80) * 1.03
        c = c + np.array([0, 0, -0.0015])
        P, Nn, C, quads = [], [], [], []
        ns, nr = 16, 10
        for i in range(nr + 1):
            th = np.pi * i / nr
            for j in range(ns):
                ph = 2 * np.pi * j / ns
                n = np.array([np.sin(th) * np.cos(ph), np.sin(th) * np.sin(ph), -np.cos(th)])  # i=0 للأمام (-Z)
                P.append(c + n * r)
                Nn.append(n)
                C.append([np.cos(th) * 0.5 + 0.5, 0, 0, 1])
        for i in range(nr):
            for j in range(ns):
                a, b = i * ns + j, i * ns + (j + 1) % ns
                quads.append([a, (i + 1) * ns + j, (i + 1) * ns + (j + 1) % ns, b])
        P = np.array(P)
        t = quads_to_tris(quads)
        Je = np.zeros((len(P), 4), np.uint16)
        Je[:, 0] = head_id
        We = np.zeros((len(P), 4), np.float32)
        We[:, 0] = 1
        # UV = اتجاه الكرة في وضع الراحة (x, y) ← القزحية والبؤبؤ يُرسمان دائماً نحو الأمام بدقة
        Nn_a = np.array(Nn)
        UVe = np.stack([Nn_a[:, 0] * 0.5 + 0.5, Nn_a[:, 1] * 0.5 + 0.5], axis=1)
        parts.append((f"Eye.{s}", "eye", P, Nn_a, UVe, np.array(C), Je, We, t))

    # رفع كل شيء بحيث يلامس النعل y=0
    lift = -floor_y
    for i, p in enumerate(parts):
        P = p[2].copy()
        P[:, 1] += lift
        parts[i] = (p[0], p[1], P) + p[3:]
    bones2 = [(b[0], b[1], b[2] + np.array([0, lift, 0]), b[3] + np.array([0, lift, 0]), b[4]) for b in bones]
    RG = rest_globals(bones2)
    path = os.path.join(OUT, f"body_{pid}.glb")
    export_glb(path, bones2, RG, parts)
    tri = sum(len(p[8]) for p in parts)
    vc = sum(len(p[2]) for p in parts)
    print(f"{pid}: {os.path.getsize(path) // 1024} KB, verts {vc}, tris {tri}, ankle {ank_y + lift:.3f}, height {height_m}")


# ------------------------------------------------------------------ الجمهور
def build_crowd(cid, target_tris, stance="sit", **mkw):
    import fast_simplification
    V, bones = prepare(1.72 if mkw.get("gender", 1) > 0.5 else 1.63, **mkw)
    if "Crowd" in cid:
        pass
    names = [b[0] for b in bones]
    J, W = bone_weights(len(V), names)
    RG = rest_globals(bones)
    # وضعية الجلوس: دوران الفخذين للأمام 85° والركبتين للخلف 85°، الذراعان على الفخذين
    pose = {n: np.eye(4) for n in names}

    def rot(axis, ang):
        axis = np.array(axis, float)
        axis /= np.linalg.norm(axis)
        a = np.radians(ang)
        K = np.array([[0, -axis[2], axis[1]], [axis[2], 0, -axis[0]], [-axis[1], axis[0], 0]])
        R = np.eye(4)
        R[:3, :3] = np.eye(3) + np.sin(a) * K + (1 - np.cos(a)) * K @ K
        return R

    local_rot = {}
    for s, sg in (("L", -1), ("R", 1)):
        if stance == "stand":
            local_rot[f"UpperArm.{s}"] = rot([1, 0, 0], 10) @ rot([0, 0, 1], -sg * 40)
            local_rot[f"ForeArm.{s}"] = rot([1, 0, 0], 12)
            continue
        local_rot[f"UpLeg.{s}"] = rot([1, 0, 0], 85)
        local_rot[f"Leg.{s}"] = rot([1, 0, 0], -88)
        local_rot[f"Foot.{s}"] = rot([1, 0, 0], 5)
        local_rot[f"UpperArm.{s}"] = rot([1, 0, 0], 22) @ rot([0, 0, 1], -sg * 36)
        local_rot[f"ForeArm.{s}"] = rot([1, 0, 0], 68)
    G = {}
    for i, b in enumerate(bones):
        R = RG[i]
        if b[1] is None:
            M = R
        else:
            pi = names.index(b[1])
            Lr = np.linalg.inv(RG[pi]) @ R
            M = G[b[1]] @ Lr
        if b[0] in local_rot:
            # دوران حول محور عالمي عند رأس العظمة
            Rw = local_rot[b[0]]
            T = np.eye(4)
            T[:3, 3] = M[:3, 3]
            Ti = np.eye(4)
            Ti[:3, 3] = -M[:3, 3]
            M = T @ Rw @ Ti @ M
        G[b[0]] = M
    skin = [G[n] @ np.linalg.inv(RG[i]) for i, n in enumerate(names)]
    faces = [FACES[i] for i in BODY_FACES]
    vids = sorted(set(v for f in faces for v in f))
    P = np.zeros((len(V), 3))
    for v in vids:
        acc = np.zeros(3)
        for k in range(4):
            if W[v, k] > 0:
                acc += W[v, k] * (skin[J[v, k]] @ np.append(V[v], 1.0))[:3]
        P[v] = acc
    remap = {v: i for i, v in enumerate(vids)}
    tris = quads_to_tris([[remap[v] for v in f] for f in faces])
    Pv = P[vids]
    # منطقة اللون قبل التبسيط: 0 بشرة، 1 قميص، 2 بنطال، 3 شعر
    bpos = {b[0]: b[2] for b in bones}
    hip_y = bpos["Hips"][1]
    region = np.zeros(len(vids))
    w_arm = dominant(J, W, names, ["ForeArm", "Hand", "Thumb", "Index", "Middle", "Ring", "Pinky"])[vids]
    w_head = dominant(J, W, names, ["Head", "Neck"])[vids]
    w_leg = dominant(J, W, names, ["UpLeg", "Leg", "Foot", "Toes"])[vids]
    hc = bpos["Head"]
    for i, v in enumerate(vids):
        if w_head[i] > 0.6:
            region[i] = 3 if Pv[i, 1] > hc[1] + 0.09 or (Pv[i, 2] > hc[2] + 0.03 and Pv[i, 1] > hc[1] + 0.02) else 0
        elif w_leg[i] > 0.5 or V[v, 1] < hip_y + 0.06:
            region[i] = 2
        elif w_arm[i] > 0.5:
            region[i] = 0
        else:
            region[i] = 1
    Ps, Fs = fast_simplification.simplify(Pv.astype(np.float32), tris.astype(np.int32), target_reduction=1.0 - target_tris / len(tris))
    # نقل المنطقة لأقرب رأس أصلي
    from scipy.spatial import cKDTree
    kd = cKDTree(Pv)
    _, nn = kd.query(Ps)
    reg = region[nn]
    Ps = Ps.copy()
    Ps[:, 1] -= Ps[:, 1].min()
    # إزاحة: مستوى المقعد عند y=0 تقريباً (الحوض)
    seat = Ps[reg == 2][:, 1].min() if np.any(reg == 2) else 0
    Nn = vertex_normals(Ps, Fs)
    C = np.zeros((len(Ps), 4))
    C[:, 0] = reg / 3.0
    C[:, 3] = 1
    Jc = np.zeros((len(Ps), 4), np.uint16)
    Wc = np.zeros((len(Ps), 4), np.float32)
    Wc[:, 0] = 1
    # يُصدَّر كشبكة ثابتة بعظمة واحدة
    one = [("Root", None, np.zeros(3), np.array([0, 1.0, 0]), np.array([0, 0, 1.0]))]
    UVr = np.stack([reg / 3.0, np.zeros(len(reg))], axis=1)
    export_glb(os.path.join(OUT, f"crowd_{cid}.glb"), one, rest_globals(one),
               [(f"Crowd_{cid}", "crowd", Ps, Nn, UVr, C, Jc, Wc, Fs)])
    print(f"crowd {cid}: tris {len(Fs)}, height {Ps[:, 1].max():.2f}")


# ------------------------------------------------------------------ خريطة تفاصيل الجلد (UV)
def bake_skin_detail(size=1024):
    """تخبز خريطة واحدة مشتركة لكل الأجسام (نفس إحداثيات UV):
    R الشفاه، G الحاجبان وخط الرموش، B ظل اللحية، A احمرار (خدود/أنف/أذنان/مفاصل)."""
    from scipy import ndimage
    from PIL import Image
    V = BASE_V
    lipw = np.zeros(len(V))
    for rel in ("mouth/mouth-lowerlip-volume-incr.target", "mouth/mouth-upperlip-volume-incr.target"):
        i, d = target(rel)
        m = np.linalg.norm(d, axis=1)
        lipw[i] = np.maximum(lipw[i], m / m.max())
    pos = np.zeros((size, size, 3), np.float32)
    lip = np.zeros((size, size), np.float32)
    cover = np.zeros((size, size), bool)
    for fi in BODY_FACES:
        f, ft = FACES[fi], FACES_T[fi]
        for tri in ((0, 1, 2), (0, 2, 3)) if len(f) == 4 else ((0, 1, 2),):
            vi = [f[k] for k in tri]
            uv = BASE_VT[[ft[k] for k in tri]] * size
            uv[:, 1] = size - uv[:, 1]
            x0, y0 = np.floor(uv.min(0)).astype(int)
            x1, y1 = np.ceil(uv.max(0)).astype(int)
            x0, y0, x1, y1 = max(x0, 0), max(y0, 0), min(x1, size - 1), min(y1, size - 1)
            if x1 < x0 or y1 < y0:
                continue
            xs, ys = np.meshgrid(np.arange(x0, x1 + 1) + 0.5, np.arange(y0, y1 + 1) + 0.5)
            (ax, ay), (bx, by), (cx, cy) = uv
            den = (by - cy) * (ax - cx) + (cx - bx) * (ay - cy)
            if abs(den) < 1e-9:
                continue
            w0 = ((by - cy) * (xs - cx) + (cx - bx) * (ys - cy)) / den
            w1 = ((cy - ay) * (xs - cx) + (ax - cx) * (ys - cy)) / den
            w2 = 1 - w0 - w1
            ins = (w0 >= -0.02) & (w1 >= -0.02) & (w2 >= -0.02)
            if not ins.any():
                continue
            yy, xx = np.nonzero(ins)
            a0, a1, a2 = w0[ins][:, None], w1[ins][:, None], w2[ins][:, None]
            pos[yy + y0, xx + x0] = a0 * V[vi[0]] + a1 * V[vi[1]] + a2 * V[vi[2]]
            lip[yy + y0, xx + x0] = (a0[:, 0] * lipw[vi[0]] + a1[:, 0] * lipw[vi[1]] + a2[:, 0] * lipw[vi[2]])
            cover[yy + y0, xx + x0] = True
    idx = ndimage.distance_transform_edt(~cover, return_distances=False, return_indices=True)
    pos = pos[idx[0], idx[1]]
    lip = lip[idx[0], idx[1]]
    X, Yp, Z = pos[..., 0], pos[..., 1], pos[..., 2]
    sm = lambda a, b, x: np.clip((x - a) / (b - a), 0, 1) ** 2 * (3 - 2 * np.clip((x - a) / (b - a), 0, 1))
    rng = np.random.default_rng(5)
    # --- الشفاه
    R = sm(0.32, 0.62, lip)
    # --- الحاجبان + خط الرموش
    G = np.zeros((size, size), np.float32)
    streak = ndimage.gaussian_filter(rng.standard_normal((size, size)), (0.7, 2.6))
    streak = np.clip(0.55 + streak / streak.std() * 0.5, 0, 1)
    eyes = {}
    for sd in ("L", "R"):
        ev = sorted(set(v for i in EYE_FACES[sd] for v in FACES[i]))
        c = V[ev].mean(0)
        r = np.percentile(np.linalg.norm(V[ev] - c, axis=1), 80)
        eyes[sd] = (c, r)
        sgn = 1.0 if c[0] > 0 else -1.0
        dx = (X - c[0]) * sgn                     # موجب = نحو الخارج
        t = (dx - 0.07) / 0.25
        tc = np.clip(t, -1, 1)
        arc = c[1] + 0.165 + 0.030 * (1 - tc * tc) + 0.022 * tc - 0.05 * np.clip(t, 0, 1) ** 2
        thick = 0.046 * (1.0 - 0.6 * np.clip(t, 0, 1) ** 2) * (1.0 - 0.25 * np.clip(-t, 0, 1) ** 2)
        brow = (1 - sm(0.15, 1.0, np.abs(Yp - arc) / thick)) * (1 - sm(0.8, 1.0, np.abs(t))) * (Z > c[2] - 0.25)
        G = np.maximum(G, brow * (0.72 + 0.28 * streak))
        dist = np.linalg.norm(pos - c, axis=2)
        lash = (1 - sm(r * 1.0, r * 1.09, dist)) * (Z > c[2] + 0.02) * (Yp > c[1] - r * 0.1)
        G = np.maximum(G, lash * 0.7)
    # --- ظل اللحية
    mc_y, mc_z = 6.6, 1.5
    front = sm(0.45, 0.85, Z)
    jaw = sm(5.72, 5.9, Yp) * (1 - sm(6.5, 6.72, Yp))
    mous = (1 - sm(6.86, 6.96, Yp)) * sm(6.5, 6.6, Yp) * (1 - sm(0.3, 0.42, np.abs(X))) * sm(1.2, 1.35, Z)
    reg = np.maximum(jaw * front * (1 - sm(0.62, 0.8, np.abs(X))), mous) * (1 - R)
    dots = ndimage.gaussian_filter(rng.standard_normal((size, size)), 0.6)
    dots = np.clip(0.5 + dots / dots.std() * 0.55, 0, 1)
    B = reg * (0.5 + 0.5 * dots)
    # --- الاحمرار
    A = np.zeros((size, size), np.float32)
    def blob(c, rad, w):
        d = np.linalg.norm(pos - np.array(c, np.float32), axis=2)
        return w * (1 - sm(rad * 0.35, rad, d))
    for sx in (-1, 1):
        A = np.maximum(A, blob([0.47 * sx, 6.95, 1.2], 0.42, 0.75))
        A = np.maximum(A, blob([0.8 * sx, 7.2, 0.25], 0.3, 0.6))
    A = np.maximum(A, blob([0.0, 6.98, 1.7], 0.2, 0.7))
    for b_, rad, w in (("lowerarm01", 0.5, 0.5), ("lowerleg01", 0.6, 0.45), ("wrist", 0.45, 0.3), ("finger3-1", 0.35, 0.45)):
        for sd in ("L", "R"):
            A = np.maximum(A, blob(joint_pos(V, SKEL["bones"][f"{b_}.{sd}"]["head"]), rad, w))
    out = np.stack([R, G, B, A], axis=2)
    Image.fromarray((np.clip(out, 0, 1) * 255).astype(np.uint8), "RGBA").save(os.path.join(OUT, "skin_detail.png"))
    print("skin_detail.png baked", size)


MUSCLE = {"eyes/l-eye-height2-incr": 0.55, "eyes/r-eye-height2-incr": 0.55,
          "armslegs/l-upperarm-muscle-incr": 0.68, "armslegs/r-upperarm-muscle-incr": 0.68,
          "armslegs/l-lowerarm-muscle-incr": 0.72, "armslegs/r-lowerarm-muscle-incr": 0.72,
          "armslegs/l-upperleg-muscle-incr": 0.62, "armslegs/r-upperleg-muscle-incr": 0.62,
          "armslegs/l-lowerleg-muscle-incr": 0.78, "armslegs/r-lowerleg-muscle-incr": 0.78,
          "torso/torso-vshape-incr": 0.4, "torso/torso-muscle-pectoral-incr": 0.38, "torso/torso-muscle-dorsi-incr": 0.36}


def D(**face):
    d = dict(MUSCLE)
    d.update({k.replace("__", "/").replace("_", "-"): v for k, v in face.items()})
    return d


if __name__ == "__main__":
    bake_skin_detail(2048)
    build_player("athlete", 1.88, "short", muscle=0.9, weight=0.42, height=0.72, prop=0.85, race=(0.75, 0.05, 0.20),
                 details=D(head__head_oval=0.5, chin__chin_prominent_incr=0.3, nose__nose_hump_incr=0.25))
    build_player("power", 1.86, "buzz", muscle=0.97, weight=0.58, height=0.62, prop=0.8, race=(0.10, 0.85, 0.05),
                 details=D(head__head_square=0.6, chin__chin_width_incr=0.5, nose__nose_flaring_incr=0.3))
    build_player("lean", 1.79, "medium", muscle=0.8, weight=0.36, height=0.42, prop=0.75, race=(0.55, 0.05, 0.40),
                 details=D(head__head_triangular=0.35, chin__chin_height_incr=0.3))
    build_player("classic", 1.83, "curly", muscle=0.86, weight=0.48, height=0.55, prop=0.8, race=(0.62, 0.28, 0.10),
                 details=D(head__head_rectangular=0.5, nose__nose_greek_incr=0.4, chin__chin_cleft_incr=0.6))
    if "--crowd" not in sys.argv:
        sys.exit(0)   # الجمهور لا يُعاد بناؤه افتراضياً (يبقى بشكله الحالي الخفيف)
    build_crowd("m", 700, gender=1.0, muscle=0.5, weight=0.55)
    build_crowd("f", 700, gender=0.0, muscle=0.45, weight=0.5)
    build_crowd("m_lo", 240, gender=1.0, muscle=0.5, weight=0.55)
    build_crowd("f_lo", 240, gender=0.0, muscle=0.45, weight=0.5)
    build_crowd("staff", 1100, stance="stand", gender=1.0, muscle=0.55, weight=0.5)
