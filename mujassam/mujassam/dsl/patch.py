"""Small, targeted edits to a spec — what the critic emits instead of rewriting everything.

Patch ops (a JSON list):
  {"op": "update", "id": "leg_fl", "set": {"location": [0.2, -0.2, 0.22]}}
  {"op": "move",   "id": "lamp_head", "by": [0, 0, 0.1]}
  {"op": "rotate", "id": "door", "by": [0, 0, 15]}
  {"op": "scale",  "id": "roof", "factor": 1.2}          (or [fx, fy, fz])
  {"op": "add",    "part": {...full part...}}
  {"op": "remove", "id": "extra_leg"}
  {"op": "material", "name": "wood", "set": {"color": "#7a4a22"}}
  {"op": "assign", "id": "seat", "material": "fabric"}
  {"op": "replace_spec", "spec": {...}}
"""
from __future__ import annotations

import copy
from typing import Any

from .schema import normalize_spec, slug

_SIZE_FIELDS = ("size",)
_SCALAR_FIELDS = ("radius", "radius_top", "radius_end", "depth", "major_radius", "minor_radius", "target_size")


def _find(spec: dict[str, Any], pid: str) -> dict[str, Any] | None:
    pid = slug(pid)
    for p in spec.get("parts", []):
        if p.get("id") == pid:
            return p
    return None


def apply_patch(spec: dict[str, Any], ops: list[dict[str, Any]] | dict[str, Any]) -> tuple[dict[str, Any], list[str]]:
    """Apply ops to a copy of spec. Returns (new_spec, log). Never raises on a bad op."""
    if isinstance(ops, dict):
        ops = ops.get("ops") or ops.get("patch") or [ops]
    new = copy.deepcopy(spec)
    log: list[str] = []
    for i, op in enumerate(ops or []):
        if not isinstance(op, dict):
            log.append(f"#{i}: skipped (not an object)")
            continue
        kind = str(op.get("op", "")).lower()
        try:
            if kind == "replace_spec" and isinstance(op.get("spec"), dict):
                new = copy.deepcopy(op["spec"])
                log.append(f"#{i}: spec replaced")
                continue
            if kind == "add":
                part = op.get("part")
                if not isinstance(part, dict):
                    raise ValueError("add needs 'part'")
                new.setdefault("parts", []).append(copy.deepcopy(part))
                log.append(f"#{i}: added {part.get('id', part.get('type'))}")
                continue
            if kind == "material":
                name = str(op.get("name"))
                mats = new.setdefault("materials", {})
                mats.setdefault(name, {}).update(op.get("set") or {})
                log.append(f"#{i}: material {name} updated")
                continue
            if kind == "set_global":
                for k, v in (op.get("set") or {}).items():
                    if k in ("name", "style", "description", "auto_ground"):
                        new[k] = v
                log.append(f"#{i}: globals updated")
                continue
            part = _find(new, op.get("id", ""))
            if part is None:
                raise KeyError(f"no part with id {op.get('id')!r}")
            if kind == "update":
                for k, v in (op.get("set") or {}).items():
                    if k == "id":
                        continue
                    if v is None:
                        part.pop(k, None)
                    else:
                        part[k] = v
            elif kind == "move":
                by = op.get("by") or [0, 0, 0]
                loc = part.get("location", [0, 0, 0])
                part["location"] = [float(loc[j]) + float(by[j]) for j in range(3)]
            elif kind == "rotate":
                by = op.get("by") or [0, 0, 0]
                rot = part.get("rotation", [0, 0, 0])
                part["rotation"] = [float(rot[j]) + float(by[j]) for j in range(3)]
            elif kind == "scale":
                f = op.get("factor", 1.0)
                fv = [float(f)] * 3 if isinstance(f, (int, float)) else [float(x) for x in f][:3]
                if "size" in part and isinstance(part["size"], list):
                    part["size"] = [float(s) * fv[j] for j, s in enumerate(part["size"])]
                else:
                    uniform = sum(fv) / 3.0
                    touched = False
                    for k in _SCALAR_FIELDS:
                        if isinstance(part.get(k), (int, float)):
                            part[k] = float(part[k]) * uniform
                            touched = True
                    if not touched:
                        sc = part.get("scale", [1, 1, 1])
                        part["scale"] = [float(sc[j]) * fv[j] for j in range(3)]
            elif kind == "remove":
                new["parts"] = [p for p in new["parts"] if p is not part]
                for p in new["parts"]:
                    if p.get("parent") == part["id"]:
                        p.pop("parent")
                    if part["id"] in (p.get("cutters") or []):
                        p["cutters"] = [c for c in p["cutters"] if c != part["id"]]
            elif kind == "assign":
                part["material"] = str(op.get("material"))
            else:
                raise ValueError(f"unknown op {kind!r}")
            log.append(f"#{i}: {kind} {part['id']}")
        except Exception as e:  # noqa: BLE001 - patches come from a model, be forgiving
            log.append(f"#{i}: FAILED {kind}: {e}")
    return new, log


def apply_and_validate(spec: dict[str, Any], ops: Any) -> tuple[dict[str, Any], list[str]]:
    new, log = apply_patch(spec, ops)
    clean, rep = normalize_spec(new)
    return clean, log + [f"validator: {w}" for w in rep.warnings]
