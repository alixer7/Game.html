"""The generate -> look -> criticise -> fix loop that makes Mujassam's outputs good.

text  ─► router ─► planner ×N ─► Blender build ─► 4-view render ─► critic ─► patch/replan ─► … ─► best
image ─► analyst ─► (TripoSR mesh) + (planner from image) ─► same loop, critic compares to the reference
"""
from __future__ import annotations

import json
import logging
import shutil
import time
from dataclasses import asdict, dataclass, field
from pathlib import Path
from typing import Any, Callable

from .blender.runner import BlenderRunner, BuildResult
from .brain.base import Brain
from .brain.prompts import analyst_messages, planner_messages, router_messages
from .critic.critic import Critic, Critique, TechReport, technical_checks
from .dsl.patch import apply_and_validate
from .dsl.schema import SpecError, normalize_spec, slug
from .recon.reconstruct import Reconstructor, mesh_spec

log = logging.getLogger("mujassam")

PRESETS: dict[str, dict[str, Any]] = {
    "fast": {"num_candidates": 1, "max_rounds": 1, "render_res": 320, "render_samples": 8},
    "balanced": {"num_candidates": 2, "max_rounds": 3, "render_res": 384, "render_samples": 16},
    "quality": {"num_candidates": 4, "max_rounds": 6, "render_res": 512, "render_samples": 24,
                "target_score": 9.0},
}


@dataclass
class GenerationConfig:
    preset: str = "balanced"
    num_candidates: int = 2
    max_rounds: int = 3
    target_score: float = 8.6
    plan_temperature: float = 0.7
    critic_temperature: float = 0.1
    plan_max_tokens: int = 6144
    face_budget: int = 100_000
    max_stall: int = 2
    render_res: int = 384
    render_samples: int = 16
    use_reconstruction: bool = True
    seed: int = 0

    @classmethod
    def from_preset(cls, preset: str = "balanced", **overrides: Any) -> "GenerationConfig":
        base = dict(PRESETS.get(preset, PRESETS["balanced"]))
        base.update({k: v for k, v in overrides.items() if v is not None})
        return cls(preset=preset, **base)


@dataclass
class Attempt:
    index: int
    round: int
    source: str
    spec: dict[str, Any]
    build: BuildResult
    tech: TechReport
    critique: Critique
    score: float
    notes: list[str] = field(default_factory=list)

    def summary(self) -> dict[str, Any]:
        return {"index": self.index, "round": self.round, "source": self.source, "score": self.score,
                "critic_overall": self.critique.overall, "scores": self.critique.scores,
                "tech_score": self.tech.score, "issues": self.critique.issues, "patch": self.critique.patch,
                "build_ok": self.build.ok, "build_seconds": round(self.build.seconds, 2),
                "faces": self.build.stats.get("faces"), "notes": self.notes, "job_dir": str(self.build.job_dir)}


@dataclass
class GenerationResult:
    request: str
    out_dir: Path
    best: Attempt | None
    attempts: list[Attempt]
    route: dict[str, Any]
    analysis: dict[str, Any] | None
    seconds: float
    files: dict[str, str] = field(default_factory=dict)

    @property
    def score(self) -> float:
        return self.best.score if self.best else 0.0

    @property
    def glb(self) -> Path | None:
        return Path(self.files["glb"]) if "glb" in self.files else None


DEFAULT_ROUTE = {"subject": "", "category": "other", "organic": 0.3, "complexity": "medium", "style": "",
                 "target_height_m": None, "route": "procedural", "checklist": []}


class MujassamPipeline:
    def __init__(self, brain: Brain, runner: BlenderRunner | None = None,
                 reconstructor: Reconstructor | None = None, config: GenerationConfig | None = None,
                 on_event: Callable[[dict[str, Any]], None] | None = None):
        self.brain = brain
        self.cfg = config or GenerationConfig()
        self.runner = runner or BlenderRunner(res=self.cfg.render_res, samples=self.cfg.render_samples)
        self.recon = reconstructor
        self.critic = Critic(brain, temperature=self.cfg.critic_temperature)
        self.on_event = on_event

    # ------------------------------------------------------------------ helpers
    def _emit(self, kind: str, **data: Any) -> None:
        log.info("%s %s", kind, {k: v for k, v in data.items() if k != "spec"})
        if self.on_event:
            try:
                self.on_event({"event": kind, **data})
            except Exception:  # noqa: BLE001
                pass

    def _route(self, request: str, image: Any) -> dict[str, Any]:
        try:
            r = self.brain.chat_json(router_messages(request, image), temperature=0.0, max_new_tokens=768)
            route = dict(DEFAULT_ROUTE)
            route.update({k: v for k, v in r.items() if v is not None} if isinstance(r, dict) else {})
            if not isinstance(route.get("checklist"), list):
                route["checklist"] = []
            try:
                route["target_height_m"] = float(route["target_height_m"]) if route.get("target_height_m") else None
            except (TypeError, ValueError):
                route["target_height_m"] = None
            return route
        except Exception as e:  # noqa: BLE001
            log.warning("router failed (%s); using defaults", e)
            return dict(DEFAULT_ROUTE)

    def _plan(self, request: str, route: dict[str, Any], image: Any = None, analysis: dict[str, Any] | None = None,
              feedback: list[str] | None = None, previous: dict[str, Any] | None = None,
              seed: int | None = None) -> tuple[dict[str, Any] | None, list[str]]:
        msgs = planner_messages(request, route, image, analysis, feedback, previous)
        notes: list[str] = []
        for attempt in range(2):
            try:
                raw = self.brain.chat_json(msgs, temperature=self.cfg.plan_temperature,
                                           max_new_tokens=self.cfg.plan_max_tokens, seed=seed)
                spec, rep = normalize_spec(raw)
                return spec, notes + rep.warnings
            except SpecError as e:
                notes.append(f"invalid spec: {e}")
                msgs = msgs + [{"role": "user", "content": f"That spec is invalid: {e}. Return a corrected full spec."}]
            except Exception as e:  # noqa: BLE001
                notes.append(f"planner error: {e}")
                break
        return None, notes

    def _evaluate(self, idx: int, rnd: int, source: str, spec: dict[str, Any], request: str,
                  route: dict[str, Any], reference: Any, work: Path, history: list[str],
                  notes: list[str] | None = None) -> Attempt:
        job = work / f"attempt_{idx:02d}"
        self._emit("build", attempt=idx, round=rnd, source=source, parts=len(spec.get("parts", [])))
        build = self.runner.build(spec, job, name=slug(spec.get("name"), "model"))
        tech = technical_checks(build.stats, face_budget=self.cfg.face_budget,
                                target_height=route.get("target_height_m"))
        self._emit("critique", attempt=idx, build_ok=build.ok, tech=tech.score)
        crit, score = self.critic.review(request, build.grid, spec, build.stats, tech,
                                         route.get("checklist"), reference, history)
        if not build.ok:
            score = 0.0
        a = Attempt(idx, rnd, source, spec, build, tech, crit, score, notes or [])
        (job / "critique.json").write_text(json.dumps(a.summary(), indent=1, ensure_ascii=False), encoding="utf-8")
        self._emit("scored", attempt=idx, round=rnd, score=score, issues=crit.issues[:3])
        return a

    # ------------------------------------------------------------------ main entry
    def generate(self, request: str = "", image: Any = None, out_dir: str | Path = "mujassam_out",
                 name: str | None = None) -> GenerationResult:
        t0 = time.time()
        cfg = self.cfg
        out = Path(out_dir)
        work = out / "work"
        work.mkdir(parents=True, exist_ok=True)
        ref_path = None
        if image is not None:
            from .brain.base import load_image
            ref_path = out / "reference.png"
            load_image(image).save(ref_path)
            image = ref_path

        route = self._route(request, image)
        self._emit("route", route=route)
        analysis = None
        if image is not None:
            try:
                analysis = self.brain.chat_json(analyst_messages(image, request), temperature=0.0, max_new_tokens=1536)
                if isinstance(analysis, dict):
                    route["checklist"] = list(route.get("checklist") or []) + \
                        [c for c in (analysis.get("checklist") or []) if c not in (route.get("checklist") or [])]
                    if not route.get("target_height_m") and analysis.get("approx_height_m"):
                        try:
                            route["target_height_m"] = float(analysis["approx_height_m"])
                        except (TypeError, ValueError):
                            pass
                self._emit("analysis", analysis=analysis)
            except Exception as e:  # noqa: BLE001
                log.warning("image analysis failed: %s", e)
        model_name = slug(name or route.get("subject") or "model", "model")

        attempts: list[Attempt] = []
        history: list[str] = []
        idx = 0

        # ---- candidates
        organic = float(route.get("organic") or 0) if not analysis else \
            max(float(route.get("organic") or 0), float(analysis.get("organic") or 0))
        want_recon = (image is not None and self.recon is not None and cfg.use_reconstruction
                      and (route.get("route") in ("reconstruct", "hybrid") or organic >= 0.5))
        n_proc = cfg.num_candidates
        if want_recon and route.get("route") == "reconstruct" and organic >= 0.7:
            n_proc = max(0, cfg.num_candidates - 1)
        if want_recon:
            try:
                rr = self.recon.reconstruct(image, work / "recon")
                spec = mesh_spec(rr, model_name, route.get("target_height_m"))
                spec, rep = normalize_spec(spec)
                attempts.append(self._evaluate(idx, 0, f"recon:{rr.backend}", spec, request, route, image, work,
                                               history, rep.warnings))
                idx += 1
            except Exception as e:  # noqa: BLE001
                log.warning("reconstruction failed: %s", e)
                n_proc = max(1, n_proc)
        for c in range(max(n_proc, 0 if attempts else 1)):
            spec, notes = self._plan(request, route, image, analysis, seed=cfg.seed + c)
            if spec is None:
                continue
            spec["name"] = model_name
            attempts.append(self._evaluate(idx, 0, "plan", spec, request, route, image, work, history, notes))
            idx += 1
        if not attempts:
            raise RuntimeError("no candidate could be produced (planner and reconstruction failed)")

        best = max(attempts, key=lambda a: a.score)
        self._emit("best_candidate", attempt=best.index, score=best.score)

        # ---- refinement
        stall = 0
        replanned = False
        for rnd in range(1, cfg.max_rounds + 1):
            if best.score >= cfg.target_score or (best.critique.done and best.score >= cfg.target_score - 1.0):
                break
            history.append(f"round {rnd - 1}: score {best.score:.2f}; issues: " + "; ".join(best.critique.issues[:3]))
            source = "patch"
            new_spec = None
            notes: list[str] = []
            if best.critique.patch and stall == 0:
                try:
                    new_spec, notes = apply_and_validate(best.spec, best.critique.patch)
                except SpecError as e:
                    notes = [f"patch produced invalid spec: {e}"]
            if new_spec is None or new_spec == best.spec:
                if replanned and stall >= cfg.max_stall:
                    break
                source = "replan"
                replanned = True
                new_spec, notes2 = self._plan(request, route, image, analysis, feedback=best.critique.issues or
                                              ["improve detail and accuracy"], previous=best.spec,
                                              seed=cfg.seed + 100 + rnd)
                notes += notes2
                if new_spec is None:
                    break
                new_spec["name"] = model_name
            att = self._evaluate(idx, rnd, source, new_spec, request, route, image, work, history, notes)
            idx += 1
            attempts.append(att)
            if att.score > best.score + 1e-6:
                best, stall = att, 0
            else:
                stall += 1
                history.append(f"round {rnd} ({source}) did not help (score {att.score:.2f})")
                if stall > cfg.max_stall:
                    break

        res = GenerationResult(request, out, best, attempts, route, analysis, time.time() - t0)
        self._finalize(res, model_name)
        self._emit("done", score=best.score, seconds=round(res.seconds, 1), files=res.files)
        return res

    # ------------------------------------------------------------------ outputs
    def _finalize(self, res: GenerationResult, name: str) -> None:
        best = res.best
        assert best is not None
        out = res.out_dir
        files: dict[str, str] = {}
        b = best.build
        for key, src, dst in (("glb", b.glb, f"{name}.glb"), ("blend", b.blend, f"{name}.blend"),
                              ("script", b.script, f"{name}_build.py"), ("preview", b.grid, f"{name}_preview.png")):
            if src and Path(src).exists():
                shutil.copy2(src, out / dst)
                files[key] = str(out / dst)
        (out / f"{name}_spec.json").write_text(json.dumps(best.spec, indent=1, ensure_ascii=False), encoding="utf-8")
        files["spec"] = str(out / f"{name}_spec.json")
        report = {"request": res.request, "seconds": round(res.seconds, 2), "best": best.summary(),
                  "route": res.route, "analysis": res.analysis,
                  "attempts": [a.summary() for a in res.attempts],
                  "config": asdict(self.cfg)}
        (out / "report.json").write_text(json.dumps(report, indent=1, ensure_ascii=False, default=str), encoding="utf-8")
        files["report"] = str(out / "report.json")
        res.files = files
