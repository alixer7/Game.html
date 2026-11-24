"""Mujassam Scene Spec (MSS) — the structured 3D language the brain speaks.

A spec is plain JSON. The brain (vision-language model) writes it, the critic patches it,
and the Blender compiler turns it into geometry. Keeping the model's output in a compact,
validated language (instead of raw bpy code) is what makes a ~4B model reliable:
fewer tokens, no API hallucinations, and every mistake is a small, fixable JSON edit.

Conventions (also taught to the brain in its system prompt):
  * units are metres, Z is up, the ground is z = 0, the model's FRONT faces -Y
  * ``location`` is the centre of the part (lathe/skin/tube/extrude: their local origin)
  * ``rotation`` is XYZ Euler in degrees
"""
from __future__ import annotations

import copy
import math
import re
from dataclasses import dataclass, field
from typing import Any

PART_TYPES = {
    "box": {"size"},
    "cube": {"size"},
    "plane": {"size"},
    "sphere": {"radius"},
    "cylinder": {"radius", "depth"},
    "cone": {"radius", "depth"},
    "torus": {"major_radius", "minor_radius"},
    "capsule": {"radius", "depth"},
    "lathe": {"profile"},
    "extrude": {"polygon"},
    "tube": {"path"},
    "skin": {"nodes"},
    "text": {"body"},
    "mesh_file": {"path"},
}

COMMON_KEYS = {
    "id", "type", "location", "rotation", "scale", "material", "parent", "mirror", "array",
    "bevel", "bevel_segments", "subdiv", "smooth", "solidify", "cutter", "cutters", "note",
}

TYPE_KEYS = {
    "box": {"size"}, "cube": {"size"}, "plane": {"size"},
    "sphere": {"radius", "segments", "rings"},
    "cylinder": {"radius", "depth", "segments", "radius_top"},
    "cone": {"radius", "depth", "segments", "radius_top"},
    "torus": {"major_radius", "minor_radius", "major_segments", "minor_segments"},
    "capsule": {"radius", "depth", "segments"},
    "lathe": {"profile", "segments", "angle"},
    "extrude": {"polygon", "depth"},
    "tube": {"path", "radius", "radius_end", "segments", "smooth_path"},
    "skin": {"nodes", "edges", "subdiv"},
    "text": {"body", "size", "depth"},
    "mesh_file": {"path", "target_size", "size_axis", "max_faces", "rotation_fix"},
}

MATERIAL_KEYS = {"color", "roughness", "metallic", "emission", "emission_strength", "alpha", "transmission"}

LIMITS = {
    "max_parts": 256,
    "max_segments": 128,
    "max_array": 64,
    "max_subdiv": 3,
    "max_points": 512,
    "max_extent": 500.0,   # metres
}

_ID_RE = re.compile(r"[^a-zA-Z0-9_]+")


class SpecError(ValueError):
    """Raised when a spec cannot be repaired automatically."""


@dataclass
class ValidationReport:
    warnings: list[str] = field(default_factory=list)
    fixed: int = 0

    def warn(self, msg: str) -> None:
        self.warnings.append(msg)
        self.fixed += 1


def _num(v: Any, default: float | None = None) -> float | None:
    try:
        f = float(v)
    except (TypeError, ValueError):
        return default
    if not math.isfinite(f):
        return default
    return f


def _vec(v: Any, n: int, default: list[float], rep: ValidationReport, ctx: str) -> list[float]:
    if isinstance(v, (int, float)) and n > 1:
        f = _num(v)
        if f is not None:
            return [f] * n
    if not isinstance(v, (list, tuple)):
        if v is not None:
            rep.warn(f"{ctx}: expected list of {n} numbers, got {type(v).__name__}; using default")
        return list(default)
    out = [_num(x) for x in list(v)[:n]]
    if len(out) < n or any(x is None for x in out):
        rep.warn(f"{ctx}: malformed vector {v!r}; using default for bad entries")
        out = [(out[i] if i < len(out) and out[i] is not None else default[i]) for i in range(n)]
    lim = LIMITS["max_extent"]
    return [max(-lim, min(lim, x)) for x in out]


def _pos(v: Any, default: float, ctx: str, rep: ValidationReport, lo: float = 1e-4) -> float:
    f = _num(v)
    if f is None:
        if v is not None:
            rep.warn(f"{ctx}: not a number ({v!r}); using {default}")
        return default
    if f < lo:
        rep.warn(f"{ctx}: {f} too small; clamped to {lo}")
        return lo
    return min(f, LIMITS["max_extent"])


def _int(v: Any, default: int, lo: int, hi: int) -> int:
    f = _num(v)
    if f is None:
        return default
    return int(max(lo, min(hi, round(f))))


def slug(s: Any, fallback: str = "part") -> str:
    s = _ID_RE.sub("_", str(s or "")).strip("_").lower()
    return s or fallback


def normalize_spec(raw: dict[str, Any]) -> tuple[dict[str, Any], ValidationReport]:
    """Validate + repair a spec. Returns (clean_spec, report). Raises SpecError if hopeless."""
    if not isinstance(raw, dict):
        raise SpecError("spec must be a JSON object")
    rep = ValidationReport()
    spec = copy.deepcopy(raw)
    parts_in = spec.get("parts")
    if not isinstance(parts_in, list) or not parts_in:
        raise SpecError("spec.parts must be a non-empty list")
    if len(parts_in) > LIMITS["max_parts"]:
        rep.warn(f"too many parts ({len(parts_in)}); truncated to {LIMITS['max_parts']}")
        parts_in = parts_in[: LIMITS["max_parts"]]

    out: dict[str, Any] = {
        "name": slug(spec.get("name"), "model"),
        "style": str(spec.get("style") or "")[:200],
        "description": str(spec.get("description") or "")[:1000],
        "auto_ground": bool(spec.get("auto_ground", True)),
    }

    # materials
    mats_in = spec.get("materials") or {}
    if isinstance(mats_in, list):  # tolerate [{"name":..., ...}]
        mats_in = {m.get("name", f"mat{i}"): m for i, m in enumerate(mats_in) if isinstance(m, dict)}
    mats: dict[str, dict[str, Any]] = {}
    for name, m in mats_in.items():
        if not isinstance(m, dict):
            if isinstance(m, str):
                m = {"color": m}
            else:
                rep.warn(f"material {name!r} ignored (not an object)")
                continue
        mm = {"color": m.get("color", "#cccccc")}
        mm["roughness"] = max(0.0, min(1.0, _num(m.get("roughness"), 0.5)))
        mm["metallic"] = max(0.0, min(1.0, _num(m.get("metallic"), 0.0)))
        mm["alpha"] = max(0.0, min(1.0, _num(m.get("alpha"), 1.0)))
        mm["transmission"] = max(0.0, min(1.0, _num(m.get("transmission"), 0.0)))
        if m.get("emission") is not None:
            mm["emission"] = m["emission"]
            mm["emission_strength"] = max(0.0, min(100.0, _num(m.get("emission_strength"), 1.0)))
        unknown = set(m) - MATERIAL_KEYS - {"name"}
        if unknown:
            rep.warn(f"material {name!r}: ignored keys {sorted(unknown)}")
        mats[str(name)] = mm

    parts: list[dict[str, Any]] = []
    seen: set[str] = set()
    for i, p in enumerate(parts_in):
        if not isinstance(p, dict):
            rep.warn(f"parts[{i}] ignored (not an object)")
            continue
        t = str(p.get("type", "box")).lower().strip()
        if t not in PART_TYPES:
            alias = {"cuboid": "box", "ball": "sphere", "tube_path": "tube", "revolve": "lathe",
                     "prism": "extrude", "pill": "capsule", "ring": "torus", "donut": "torus"}.get(t)
            if alias is None:
                rep.warn(f"parts[{i}]: unknown type {t!r}; replaced by box")
                t = "box"
            else:
                t = alias
        pid = slug(p.get("id") or p.get("name") or f"{t}_{i}", f"{t}_{i}")
        base = pid
        k = 2
        while pid in seen:
            pid = f"{base}_{k}"
            k += 1
        if pid != slug(p.get("id") or "", ""):
            if p.get("id"):
                rep.warn(f"parts[{i}]: id {p.get('id')!r} renamed to {pid!r}")
        seen.add(pid)
        q: dict[str, Any] = {"id": pid, "type": t}
        ctx = f"part {pid}"
        q["location"] = _vec(p.get("location"), 3, [0.0, 0.0, 0.0], rep, ctx + ".location")
        q["rotation"] = _vec(p.get("rotation"), 3, [0.0, 0.0, 0.0], rep, ctx + ".rotation")
        if p.get("scale") is not None:
            sc = _vec(p.get("scale"), 3, [1.0, 1.0, 1.0], rep, ctx + ".scale")
            q["scale"] = [x if abs(x) > 1e-4 else 1e-4 for x in sc]

        # type specific
        if t in ("box", "cube"):
            q["type"] = "box"
            q["size"] = [max(1e-4, abs(x)) for x in _vec(p.get("size", p.get("dimensions")), 3, [1, 1, 1], rep, ctx + ".size")]
        elif t == "plane":
            q["size"] = [max(1e-4, abs(x)) for x in _vec(p.get("size"), 2, [1, 1], rep, ctx + ".size")]
        elif t == "sphere":
            q["radius"] = _pos(p.get("radius"), 0.5, ctx + ".radius", rep)
            q["segments"] = _int(p.get("segments"), 32, 6, LIMITS["max_segments"])
            q["rings"] = _int(p.get("rings"), max(4, q["segments"] // 2), 3, LIMITS["max_segments"])
        elif t in ("cylinder", "cone"):
            q["radius"] = _pos(p.get("radius"), 0.5, ctx + ".radius", rep)
            q["depth"] = _pos(p.get("depth", p.get("height")), 1.0, ctx + ".depth", rep)
            q["segments"] = _int(p.get("segments"), 32, 3, LIMITS["max_segments"])
            rt = p.get("radius_top")
            if rt is None and t == "cone":
                rt = 0.0
            if rt is not None:
                q["radius_top"] = max(0.0, _num(rt, 0.0))
        elif t == "torus":
            q["major_radius"] = _pos(p.get("major_radius"), 0.5, ctx + ".major_radius", rep)
            q["minor_radius"] = _pos(p.get("minor_radius"), 0.1, ctx + ".minor_radius", rep)
            q["major_segments"] = _int(p.get("major_segments"), 48, 6, LIMITS["max_segments"])
            q["minor_segments"] = _int(p.get("minor_segments"), 16, 3, LIMITS["max_segments"])
        elif t == "capsule":
            q["radius"] = _pos(p.get("radius"), 0.25, ctx + ".radius", rep)
            q["depth"] = max(2 * q["radius"], _pos(p.get("depth", p.get("height")), 1.0, ctx + ".depth", rep))
            q["segments"] = _int(p.get("segments"), 24, 6, LIMITS["max_segments"])
        elif t == "lathe":
            prof = p.get("profile")
            pts = _points(prof, 2, rep, ctx + ".profile")
            if len(pts) < 2:
                raise SpecError(f"{ctx}: lathe needs a profile of >= 2 [radius, z] points")
            q["profile"] = [[max(0.0, a), b] for a, b in pts]
            q["segments"] = _int(p.get("segments"), 32, 3, LIMITS["max_segments"])
            q["angle"] = max(1.0, min(360.0, _num(p.get("angle"), 360.0)))
        elif t == "extrude":
            pts = _points(p.get("polygon"), 2, rep, ctx + ".polygon")
            if len(pts) < 3:
                raise SpecError(f"{ctx}: extrude needs a polygon of >= 3 [x, y] points")
            q["polygon"] = pts
            q["depth"] = _pos(p.get("depth"), 0.1, ctx + ".depth", rep)
        elif t == "tube":
            pts = _points(p.get("path"), 3, rep, ctx + ".path")
            if len(pts) < 2:
                raise SpecError(f"{ctx}: tube needs a path of >= 2 [x, y, z] points")
            q["path"] = pts
            q["radius"] = _pos(p.get("radius"), 0.05, ctx + ".radius", rep)
            if p.get("radius_end") is not None:
                q["radius_end"] = _pos(p.get("radius_end"), q["radius"], ctx + ".radius_end", rep)
            q["segments"] = _int(p.get("segments"), 12, 4, 64)
            q["smooth_path"] = bool(p.get("smooth_path", True))
        elif t == "skin":
            nodes = _points(p.get("nodes"), 4, rep, ctx + ".nodes", pad=0.1)
            if len(nodes) < 2:
                raise SpecError(f"{ctx}: skin needs >= 2 nodes [x, y, z, radius]")
            q["nodes"] = [[a, b, c, max(1e-3, abs(r))] for a, b, c, r in nodes]
            edges = p.get("edges")
            if edges:
                ok = []
                for e in edges:
                    if (isinstance(e, (list, tuple)) and len(e) == 2
                            and all(isinstance(x, (int, float)) for x in e)):
                        a, b = int(e[0]), int(e[1])
                        if 0 <= a < len(nodes) and 0 <= b < len(nodes) and a != b:
                            ok.append([a, b])
                            continue
                    rep.warn(f"{ctx}: bad skin edge {e!r} dropped")
                if ok:
                    q["edges"] = ok
            q["subdiv"] = _int(p.get("subdiv"), 2, 0, LIMITS["max_subdiv"])
        elif t == "text":
            q["body"] = str(p.get("body", "Text"))[:200]
            q["size"] = _pos(p.get("size"), 0.3, ctx + ".size", rep)
            q["depth"] = _pos(p.get("depth"), 0.05, ctx + ".depth", rep)
        elif t == "mesh_file":
            q["path"] = str(p.get("path"))
            if p.get("target_size") is not None:
                q["target_size"] = _pos(p.get("target_size"), 1.0, ctx + ".target_size", rep)
            q["size_axis"] = str(p.get("size_axis", "max"))
            q["max_faces"] = _int(p.get("max_faces"), 60000, 500, 1_000_000)
            q["rotation_fix"] = _vec(p.get("rotation_fix"), 3, [0.0, 0.0, 0.0], rep, ctx + ".rotation_fix")

        # common optional
        mat = p.get("material")
        if isinstance(mat, dict):  # inline material -> hoist
            mname = f"{pid}_mat"
            mats[mname] = normalize_spec({"parts": [{"type": "box"}], "materials": {mname: mat}})[0]["materials"][mname]
            mat = mname
        if mat:
            mat = str(mat)
            if mat not in mats:
                mats[mat] = {"color": mat if mat.replace(" ", "_").lower() in _NAMED else "#bfbfbf",
                             "roughness": 0.5, "metallic": 0.0, "alpha": 1.0, "transmission": 0.0}
                rep.warn(f"{ctx}: material {mat!r} was not defined; created a default one")
            q["material"] = mat
        if p.get("parent"):
            q["parent"] = slug(p["parent"])
        if p.get("mirror"):
            m = p["mirror"]
            axes = [a for a in (m if isinstance(m, (list, tuple)) else [m]) if str(a).lower() in ("x", "y", "z")]
            if axes:
                q["mirror"] = [str(a).lower() for a in axes]
            elif m is True:
                q["mirror"] = ["x"]
        if isinstance(p.get("array"), dict):
            a = p["array"]
            q["array"] = {"count": _int(a.get("count"), 2, 1, LIMITS["max_array"]),
                          "offset": _vec(a.get("offset"), 3, [1.0, 0.0, 0.0], rep, ctx + ".array.offset")}
        if p.get("bevel"):
            b = _num(p.get("bevel"), 0.0) or 0.0
            if b > 0:
                q["bevel"] = min(b, 10.0)
                q["bevel_segments"] = _int(p.get("bevel_segments"), 2, 1, 8)
        if p.get("subdiv") and t != "skin":
            q["subdiv"] = _int(p.get("subdiv"), 1, 0, LIMITS["max_subdiv"])
        if "smooth" in p:
            q["smooth"] = bool(p["smooth"])
        if p.get("solidify"):
            s = _num(p.get("solidify"), 0.0) or 0.0
            if s:
                q["solidify"] = s
        if p.get("cutter"):
            q["cutter"] = True
        if p.get("cutters"):
            cs = p["cutters"] if isinstance(p["cutters"], list) else [p["cutters"]]
            q["cutters"] = [slug(c) for c in cs]
        if p.get("note"):
            q["note"] = str(p["note"])[:200]
        unknown = set(p) - COMMON_KEYS - TYPE_KEYS.get(t, set()) - {"name", "height", "dimensions"}
        if unknown:
            rep.warn(f"{ctx}: ignored keys {sorted(unknown)}")
        parts.append(q)

    # referential checks
    ids = {q["id"] for q in parts}
    for q in parts:
        if q.get("parent") and q["parent"] not in ids:
            rep.warn(f"part {q['id']}: parent {q['parent']!r} does not exist; removed")
            q.pop("parent")
        if q.get("parent") == q["id"]:
            q.pop("parent")
        if q.get("cutters"):
            good = [c for c in q["cutters"] if c in ids and c != q["id"]]
            if len(good) != len(q["cutters"]):
                rep.warn(f"part {q['id']}: unknown cutters removed")
            q["cutters"] = good
            for c in good:
                next(x for x in parts if x["id"] == c)["cutter"] = True
            if not good:
                q.pop("cutters")
    _break_parent_cycles(parts, rep)
    if not any(not q.get("cutter") for q in parts):
        raise SpecError("spec has no visible parts")
    out["materials"] = mats
    out["parts"] = parts
    return _round(out), rep


def _round(v: Any, nd: int = 4) -> Any:
    if isinstance(v, float):
        r = round(v, nd)
        return 0.0 if r == 0 else r
    if isinstance(v, list):
        return [_round(x, nd) for x in v]
    if isinstance(v, dict):
        return {k: _round(x, nd) for k, x in v.items()}
    return v


_PART_DEFAULTS = {"rotation": [0.0, 0.0, 0.0], "bevel_segments": 2, "smooth_path": True, "size_axis": "max",
                  "max_faces": 60000, "rotation_fix": [0.0, 0.0, 0.0]}
_MAT_DEFAULTS = {"roughness": 0.5, "metallic": 0.0, "alpha": 1.0, "transmission": 0.0}


def compact_spec(spec: dict[str, Any]) -> dict[str, Any]:
    """Drop fields that equal their defaults -> fewer tokens for the brain (prompts + training targets)."""
    out = {k: v for k, v in spec.items() if k not in ("parts", "materials")
           and not (k == "description" and not v) and not (k == "auto_ground" and v is True)
           and not (k == "style" and not v)}
    out["materials"] = {n: {k: v for k, v in m.items() if _MAT_DEFAULTS.get(k, object()) != v}
                        for n, m in (spec.get("materials") or {}).items()}
    parts = []
    for p in spec.get("parts") or []:
        q = {k: v for k, v in p.items() if _PART_DEFAULTS.get(k, object()) != v}
        if q.get("type") == "sphere" and q.get("rings") == max(4, q.get("segments", 32) // 2):
            q.pop("rings")
        for k, d in (("segments", 32),):
            if q.get(k) == d and q.get("type") in ("sphere", "cylinder", "cone", "lathe"):
                q.pop(k)
        parts.append(q)
    out["parts"] = parts
    return out


_NAMED = {
    "white", "black", "gray", "grey", "light_gray", "dark_gray", "red", "dark_red", "green",
    "dark_green", "blue", "navy", "sky_blue", "yellow", "gold", "orange", "brown", "dark_brown",
    "wood", "beige", "cream", "pink", "purple", "violet", "cyan", "teal", "silver", "skin", "tan", "olive",
}


def _points(v: Any, dim: int, rep: ValidationReport, ctx: str, pad: float | None = None) -> list[list[float]]:
    if not isinstance(v, (list, tuple)):
        return []
    out = []
    for i, p in enumerate(v[: LIMITS["max_points"]]):
        if not isinstance(p, (list, tuple)):
            rep.warn(f"{ctx}[{i}] dropped (not a list)")
            continue
        vals = [_num(x) for x in p[:dim]]
        if len(vals) == dim - 1 and pad is not None:
            vals.append(pad)
        if len(vals) != dim or any(x is None for x in vals):
            rep.warn(f"{ctx}[{i}] dropped (needs {dim} numbers)")
            continue
        out.append(vals)
    return out


def _break_parent_cycles(parts: list[dict[str, Any]], rep: ValidationReport) -> None:
    by_id = {q["id"]: q for q in parts}
    for q in parts:
        seen = {q["id"]}
        cur = q
        while cur.get("parent"):
            nxt = by_id.get(cur["parent"])
            if nxt is None:
                break
            if nxt["id"] in seen:
                rep.warn(f"parent cycle through {cur['id']!r} broken")
                cur.pop("parent")
                break
            seen.add(nxt["id"])
            cur = nxt


def summarize_spec(spec: dict[str, Any]) -> str:
    """Short human/LLM readable outline of a spec (used in prompts)."""
    lines = [f"model '{spec.get('name')}' — {len(spec.get('parts', []))} parts"]
    for p in spec.get("parts", []):
        loc = ",".join(f"{x:.2f}" for x in p.get("location", [0, 0, 0]))
        lines.append(f"- {p['id']} ({p['type']}) at [{loc}] mat={p.get('material', '-')}")
    return "\n".join(lines)
