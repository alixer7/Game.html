"""Self-evaluation: deterministic geometry checks + the brain looking at its own renders."""
from __future__ import annotations

import json
from dataclasses import dataclass, field
from typing import Any

from ..brain.base import Brain
from ..brain.prompts import critic_messages
from ..dsl.schema import compact_spec

WEIGHTS = {"adherence": 2.0, "proportions": 1.0, "completeness": 1.0, "aesthetics": 1.0, "technical": 1.0}


# --------------------------------------------------------------------------- technical checks
@dataclass
class TechReport:
    score: float
    issues: list[str] = field(default_factory=list)
    floating: list[str] = field(default_factory=list)

    def text(self, stats: dict[str, Any]) -> str:
        dims = stats.get("dimensions", [0, 0, 0])
        lines = [f"faces={stats.get('faces', 0)}  size(m) x={dims[0]:.3f} y={dims[1]:.3f} z={dims[2]:.3f}"
                 f"  tech_score={self.score:.1f}/10"]
        lines += [f"! {i}" for i in self.issues] or ["no technical problems detected"]
        return "\n".join(lines)


def _touch(a_lo, a_hi, b_lo, b_hi, tol: float) -> bool:
    return all(a_lo[i] - tol <= b_hi[i] and b_lo[i] - tol <= a_hi[i] for i in range(3))


def technical_checks(stats: dict[str, Any], *, face_budget: int = 100_000,
                     target_height: float | None = None) -> TechReport:
    issues: list[str] = []
    score = 10.0
    if not stats or stats.get("fatal"):
        return TechReport(0.0, [f"build failed: {stats.get('fatal') if stats else 'no stats'}"])
    errs = stats.get("errors") or []
    for e in errs:
        issues.append(f"part '{e.get('id')}' failed to build: {e.get('error')}")
    score -= min(6.0, 3.0 * len(errs))
    parts = {k: v for k, v in (stats.get("parts") or {}).items() if not v.get("cutter")}
    if not parts:
        return TechReport(0.0, issues + ["model is empty"])
    dims = stats.get("dimensions", [0, 0, 0])
    size = max(max(dims), 1e-3)
    tol = 0.01 * size + 0.002
    floating = []
    if len(parts) > 1:
        for pid, p in parts.items():
            if p["bbox_min"][2] <= tol:
                continue  # touches the ground
            if not any(_touch(p["bbox_min"], p["bbox_max"], q["bbox_min"], q["bbox_max"], tol)
                       for qid, q in parts.items() if qid != pid):
                floating.append(pid)
    if floating:
        issues.append("floating parts (touch nothing): " + ", ".join(floating[:12]))
        score -= min(4.5, 1.5 * len(floating))
    tiny = [pid for pid, p in parts.items()
            if max(p["bbox_max"][i] - p["bbox_min"][i] for i in range(3)) < 0.004 * size]
    if tiny:
        issues.append("parts too small to see: " + ", ".join(tiny[:8]))
        score -= min(1.5, 0.5 * len(tiny))
    faces = int(stats.get("faces", 0))
    if faces > face_budget:
        issues.append(f"too many faces ({faces} > budget {face_budget}) — reduce segments/subdiv")
        score -= 2.0
    if faces < 12:
        issues.append("almost no geometry")
        score -= 3.0
    if target_height and dims[2] > 0:
        ratio = dims[2] / target_height
        if ratio > 1.7 or ratio < 1 / 1.7:
            issues.append(f"height is {dims[2]:.2f} m but about {target_height:.2f} m was expected")
            score -= 1.5
    return TechReport(max(0.0, round(score, 2)), issues, floating)


# --------------------------------------------------------------------------- neural critique
@dataclass
class Critique:
    scores: dict[str, float]
    overall: float
    issues: list[str]
    patch: list[dict[str, Any]]
    done: bool
    raw: Any = None

    @classmethod
    def failed(cls, reason: str) -> "Critique":
        return cls({k: 0.0 for k in WEIGHTS}, 0.0, [reason], [], False)


def _clamp(x: Any, default: float = 5.0) -> float:
    try:
        return max(0.0, min(10.0, float(x)))
    except (TypeError, ValueError):
        return default


def parse_critique(obj: Any) -> Critique:
    if not isinstance(obj, dict):
        return Critique.failed("critic returned no object")
    sc = obj.get("scores") or {}
    scores = {k: _clamp(sc.get(k)) for k in WEIGHTS}
    weighted = sum(scores[k] * w for k, w in WEIGHTS.items()) / sum(WEIGHTS.values())
    overall = _clamp(obj.get("overall"), weighted)
    # trust but verify: the stated overall may not drift far from the rubric
    overall = round(0.5 * overall + 0.5 * weighted, 2)
    issues = [str(i) for i in (obj.get("issues") or [])][:12]
    patch = obj.get("patch") or []
    if isinstance(patch, dict):
        patch = [patch]
    patch = [p for p in patch if isinstance(p, dict)][:40]
    return Critique(scores, overall, issues, patch, bool(obj.get("done", False)), raw=obj)


class Critic:
    def __init__(self, brain: Brain, temperature: float = 0.1, max_new_tokens: int = 3072,
                 tech_weight: float = 0.2):
        self.brain = brain
        self.temperature = temperature
        self.max_new_tokens = max_new_tokens
        self.tech_weight = tech_weight

    def review(self, request: str, grid_image: Any, spec: dict[str, Any], stats: dict[str, Any],
               tech: TechReport, checklist: list[str] | None = None, reference: Any = None,
               history: list[str] | None = None) -> tuple[Critique, float]:
        """Returns (critique, final_score) where final mixes the critic with the hard checks."""
        if grid_image is None:
            c = Critique.failed("model did not render: " + "; ".join(tech.issues))
            return c, 0.0
        spec_json = json.dumps(compact_spec(spec), separators=(",", ":"), ensure_ascii=False)
        if len(spec_json) > 24_000:
            spec_json = spec_json[:24_000] + "...(truncated)"
        msgs = critic_messages(request, grid_image, spec_json, tech.text(stats), checklist, reference, history)
        try:
            obj = self.brain.chat_json(msgs, temperature=self.temperature, max_new_tokens=self.max_new_tokens)
            c = parse_critique(obj)
        except Exception as e:  # noqa: BLE001
            c = Critique.failed(f"critic error: {e}")
            c.overall = 5.0
        final = round((1 - self.tech_weight) * c.overall + self.tech_weight * tech.score, 3)
        if tech.issues:
            c.issues = c.issues + [f"[tech] {i}" for i in tech.issues if i not in c.issues]
        return c, final
