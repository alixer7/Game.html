"""Integration tests with real Blender and a scripted brain (no neural weights needed)."""
import copy
import json

import pytest

from conftest import ROOT, needs_blender
from mujassam.blender.runner import BlenderRunner
from mujassam.brain.mock import ScriptedBrain
from mujassam.critic.critic import technical_checks
from mujassam.dsl.schema import normalize_spec
from mujassam.pipeline import GenerationConfig, MujassamPipeline
from mujassam.recon.reconstruct import MeshFileReconstructor

pytestmark = needs_blender

FAST = dict(res=160, samples=4)


@pytest.fixture(scope="module")
def runner():
    return BlenderRunner(**FAST)


def test_build_showcase_all_part_types(runner, tmp_path):
    spec, rep = normalize_spec(json.loads((ROOT / "examples/specs/showcase.json").read_text()))
    res = runner.build(spec, tmp_path, name="showcase")
    assert res.ok, res.error
    assert res.stats["errors"] == []
    assert res.glb.stat().st_size > 10_000
    assert res.blend.exists() and len(res.renders) == 4 and res.grid.exists()
    assert res.stats["bbox_min"][2] == pytest.approx(0.0, abs=1e-3)       # auto-grounded
    assert res.stats["parts"]["hole"]["cutter"] is True
    tech = technical_checks(res.stats)
    assert tech.score >= 9, tech.issues


def test_part_errors_are_reported_not_fatal(runner, tmp_path):
    spec, _ = normalize_spec({"parts": [{"id": "ok", "type": "box"},
                                        {"id": "broken", "type": "mesh_file", "path": "/nonexistent.glb"}]})
    res = runner.build(spec, tmp_path, render=False, save_blend=False)
    assert res.ok
    assert res.stats["errors"][0]["id"] == "broken"
    assert "failed to build" in technical_checks(res.stats).issues[0]


def test_freeform_code(runner, tmp_path):
    code = ("import math\nmat = make_material('steel', '#888888', 0.3, 1.0)\n"
            "for i in range(6):\n"
            "    a = 2 * math.pi * i / 6\n"
            "    o = cylinder('spoke%d' % i, 0.01, 0.3)\n"
            "    o.location = (0.15 * math.cos(a), 0.15 * math.sin(a), 0.3)\n"
            "    assign_material(o, mat)\n    register(o)\n")
    res = runner.build(None, tmp_path, code=code, render=False)
    assert res.ok, res.error
    assert len(res.stats["parts"]) == 6
    assert res.stats["bbox_min"][2] == pytest.approx(0.0, abs=1e-3)


def test_floating_detection(runner, tmp_path):
    spec, _ = normalize_spec({"parts": [{"id": "base", "type": "box", "size": [1, 1, 0.2], "location": [0, 0, 0.1]},
                                        {"id": "ufo", "type": "sphere", "radius": 0.1, "location": [0, 0, 2]}]})
    res = runner.build(spec, tmp_path, render=False, save_blend=False)
    tech = technical_checks(res.stats)
    assert tech.floating == ["ufo"]


ROUTE = {"subject": "wooden chair", "category": "furniture", "organic": 0.05, "complexity": "medium",
         "style": "modern", "target_height_m": 0.9, "route": "procedural",
         "checklist": ["wooden chair", "blue cushion"]}


def _good_critique(score=9.3):
    return {"scores": {k: score for k in ("adherence", "proportions", "completeness", "aesthetics", "technical")},
            "overall": score, "issues": [], "patch": [], "done": True}


def test_text_pipeline_self_corrects(tmp_path, chair_spec):
    bad = copy.deepcopy(chair_spec)
    bad["parts"] = [p for p in bad["parts"] if p["id"] != "cushion"]
    for p in bad["parts"]:
        if p["id"] == "back_rail":
            p["location"] = [0, 0.19, 1.4]          # floating
    fix = [{"op": "update", "id": "back_rail", "set": {"location": [0, 0.19, 0.84]}},
           {"op": "add", "part": next(p for p in chair_spec["parts"] if p["id"] == "cushion")}]
    brain = ScriptedBrain({
        "router": [ROUTE],
        "planner": [bad],
        "critic": [{"scores": {"adherence": 4, "proportions": 5, "completeness": 6, "aesthetics": 6, "technical": 4},
                    "overall": 4.5, "issues": ["no blue cushion", "back_rail floats above the legs"],
                    "patch": fix, "done": False},
                   _good_critique()],
    })
    cfg = GenerationConfig.from_preset("fast", max_rounds=3, render_res=160, render_samples=4)
    events = []
    pipe = MujassamPipeline(brain, config=cfg, on_event=events.append)
    res = pipe.generate("كرسي خشبي مع وسادة زرقاء", out_dir=tmp_path)
    assert len(res.attempts) == 2
    first, second = res.attempts
    assert "back_rail" in first.tech.floating
    assert second.source == "patch" and second.tech.floating == []
    assert res.best is second and res.score > 8.5 > first.score
    for k in ("glb", "blend", "script", "preview", "spec", "report"):
        assert (tmp_path / res.files[k].split("/")[-1]).exists(), k
    # the critic saw the renders and the floating-part warning
    critic_calls = [m for t, m in brain.calls if t == "critic"]
    first_user = critic_calls[0][1]["content"]
    assert any(c.get("type") == "image" for c in first_user)
    assert "floating parts" in first_user[-1]["text"]
    assert [e["event"] for e in events][-1] == "done"


def test_bad_patch_falls_back_to_replan(tmp_path, chair_spec):
    brain = ScriptedBrain({
        "router": [ROUTE],
        "planner": [chair_spec, chair_spec],
        "critic": [{"scores": {"adherence": 6}, "overall": 6, "issues": ["needs armrests"],
                    "patch": [{"op": "update", "id": "nope", "set": {}}], "done": False},
                   _good_critique(9.0)],
    })
    cfg = GenerationConfig.from_preset("fast", max_rounds=2, render_res=128, render_samples=2)
    res = MujassamPipeline(brain, config=cfg).generate("chair with armrests", out_dir=tmp_path)
    assert [a.source for a in res.attempts] == ["plan", "replan"]
    replan_msgs = [m for t, m in brain.calls if t == "planner"][-1]
    assert "needs armrests" in replan_msgs[-1]["content"][-1]["text"]


def test_image_pipeline_with_reconstruction(tmp_path, runner, chair_spec):
    # make a 'reconstructed' mesh + a 'photo' by building the chair once
    spec, _ = normalize_spec(chair_spec)
    pre = runner.build(spec, tmp_path / "src", name="chair")
    photo = pre.renders[0]
    recon = MeshFileReconstructor(pre.glb)
    brain = ScriptedBrain({
        "router": [dict(ROUTE, route="hybrid", organic=0.6, checklist=[], target_height_m=None)],
        "analyst": [{"subject": "chair", "organic": 0.6, "approx_height_m": 1.8, "checklist": ["slatted back"]}],
        "planner": [chair_spec],
        "critic": [{"scores": {"adherence": 7, "proportions": 4}, "overall": 6, "issues": ["twice too big"],
                    "patch": [{"op": "update", "id": "recon", "set": {"target_size": 0.9}}], "done": False},
                   {"scores": {"adherence": 5, "proportions": 5}, "overall": 5, "issues": ["blocky"], "patch": []},
                   _good_critique(9.4)],
    })
    cfg = GenerationConfig.from_preset("fast", num_candidates=1, max_rounds=2, render_res=128, render_samples=2)
    res = MujassamPipeline(brain, reconstructor=recon, config=cfg).generate("", image=photo, out_dir=tmp_path / "out")
    sources = [a.source for a in res.attempts]
    assert sources[0] == "recon:file" and "plan" in sources
    assert res.route["target_height_m"] == pytest.approx(1.8)    # router had none -> analyst estimate
    assert "slatted back" in res.route["checklist"]
    # the reconstructed mesh got normalised to the requested size by Blender
    dims = res.attempts[0].build.stats["dimensions"]
    assert dims[2] == pytest.approx(1.8, rel=0.02)
    patched = [a for a in res.attempts if a.source == "patch"]
    assert sources == ["recon:file", "plan", "patch"]
    assert patched[0].build.stats["dimensions"][2] == pytest.approx(0.9, rel=0.02)
    assert res.best is patched[0] and res.best.score >= 9
    # the critic compared against the reference photo
    critic_user = [m for t, m in brain.calls if t == "critic"][0][1]["content"]
    assert sum(c.get("type") == "image" for c in critic_user) == 2
