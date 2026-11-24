import os
import time

import pytest

pytest.importorskip("fastapi")
os.environ["MUJASSAM_SERVER_AUTOSTART"] = "0"

from fastapi.testclient import TestClient  # noqa: E402

from conftest import needs_blender  # noqa: E402
from mujassam.brain.mock import ScriptedBrain  # noqa: E402
from mujassam.model import MujassamConfig, MujassamModel  # noqa: E402
from mujassam.server import create_app  # noqa: E402

pytestmark = needs_blender


def _wait(client, jid, timeout=120):
    t = time.time()
    while time.time() - t < timeout:
        j = client.get(f"/v1/jobs/{jid}").json()
        if j["status"] in ("done", "failed"):
            return j
        time.sleep(0.3)
    raise TimeoutError


def test_text_job_end_to_end(chair_spec, tmp_path, monkeypatch):
    monkeypatch.setattr("mujassam.server.WORK", tmp_path)
    brain = ScriptedBrain({"router": [{"subject": "chair", "checklist": []}], "planner": [chair_spec],
                           "critic": [{"scores": {k: 9.5 for k in ("adherence", "proportions", "completeness",
                                                                   "aesthetics", "technical")},
                                       "overall": 9.5, "issues": [], "patch": [], "done": True}]})
    model = MujassamModel(MujassamConfig(), brain)
    client = TestClient(create_app(model))
    r = client.post("/v1/text-to-3d", json={"prompt": "كرسي", "preset": "fast"})
    assert r.status_code == 200
    job = _wait(client, r.json()["id"])
    assert job["status"] == "done", job
    assert job["score"] > 9
    glb = client.get(job["files"]["glb"])
    assert glb.status_code == 200 and glb.content[:4] == b"glTF"
    assert client.get(f"/v1/jobs/{job['id']}/files/../../etc/passwd").status_code == 404


def test_build_job_and_validation(chair_spec, tmp_path, monkeypatch):
    monkeypatch.setattr("mujassam.server.WORK", tmp_path)
    client = TestClient(create_app(object()))
    job = _wait(client, client.post("/v1/build", json={"spec": chair_spec}).json()["id"])
    assert job["status"] == "done" and job["stats"]["faces"] > 100
    bad = _wait(client, client.post("/v1/build", json={"spec": {"parts": []}}).json()["id"])
    assert bad["status"] == "failed" and "SpecError" in bad["error"]
    assert client.post("/v1/text-to-3d", json={"prompt": "  "}).status_code == 400
