"""HTTP API so the phone app can use Mujassam running on a GPU machine / Colab.

  POST /v1/text-to-3d    {"prompt": "...", "preset": "fast|balanced|quality"}
  POST /v1/image-to-3d   multipart: image=<file>, prompt=<text>, preset=<...>
  POST /v1/build         {"spec": {...}}           (no neural model: spec -> Blender)
  GET  /v1/jobs/{id}                               status / result
  GET  /v1/jobs/{id}/files/{name}                  download model.glb / model.blend / preview.png ...
  GET  /health

Jobs run one at a time on a background worker (one GPU); poll /v1/jobs/{id}.
Start:  MUJASSAM_MODEL=/path/to/package uvicorn mujassam.server:app --host 0.0.0.0 --port 8000
Set MUJASSAM_API_KEY to require the header  Authorization: Bearer <key>.
"""
from __future__ import annotations

import json
import os
import queue
import threading
import time
import uuid
from pathlib import Path
from typing import Any

from fastapi import Depends, FastAPI, File, Form, Header, HTTPException, UploadFile
from fastapi.responses import FileResponse
from pydantic import BaseModel

WORK = Path(os.environ.get("MUJASSAM_WORKDIR", "mujassam_jobs")).resolve()
API_KEY = os.environ.get("MUJASSAM_API_KEY")


class TextReq(BaseModel):
    prompt: str
    preset: str = "balanced"


class SpecReq(BaseModel):
    spec: dict[str, Any]


class Service:
    def __init__(self, model=None):
        self.model = model
        self.jobs: dict[str, dict[str, Any]] = {}
        self.q: queue.Queue = queue.Queue()
        self.lock = threading.Lock()
        threading.Thread(target=self._worker, daemon=True).start()

    def get_model(self):
        if self.model is None:
            from .model import MujassamModel
            self.model = MujassamModel.from_pretrained(os.environ.get("MUJASSAM_MODEL", "mujassam-4.9b"))
        return self.model

    def submit(self, kind: str, payload: dict[str, Any]) -> str:
        jid = uuid.uuid4().hex[:12]
        self.jobs[jid] = {"id": jid, "kind": kind, "status": "queued", "created": time.time(), "events": []}
        self.q.put((jid, kind, payload))
        return jid

    def _worker(self) -> None:
        while True:
            jid, kind, payload = self.q.get()
            job = self.jobs[jid]
            job["status"] = "running"
            out = WORK / jid
            try:
                if kind == "build":
                    from .blender.runner import BlenderRunner
                    from .dsl.schema import normalize_spec
                    spec, rep = normalize_spec(payload["spec"])
                    r = BlenderRunner().build(spec, out, name=spec["name"])
                    files = {k: str(v) for k, v in (("glb", r.glb), ("blend", r.blend), ("preview", r.grid),
                                                    ("script", r.script)) if v}
                    job.update(status="done" if r.ok else "failed", files=files, warnings=rep.warnings,
                               error=r.error, stats={"faces": r.stats.get("faces"), "errors": r.stats.get("errors")})
                else:
                    m = self.get_model()
                    on_event = (lambda e: job["events"].append({k: v for k, v in e.items()
                                                                if k in ("event", "attempt", "round", "score")}))
                    if kind == "text":
                        res = m.generate_from_text(payload["prompt"], out, payload.get("preset"), on_event=on_event)
                    else:
                        res = m.generate_from_image(payload["image"], payload.get("prompt", ""), out,
                                                    payload.get("preset"), on_event=on_event)
                    job.update(status="done", score=res.score, seconds=round(res.seconds, 1), files=res.files,
                               attempts=len(res.attempts))
            except Exception as e:  # noqa: BLE001
                job.update(status="failed", error=f"{type(e).__name__}: {e}")
            job["finished"] = time.time()

    def public(self, jid: str) -> dict[str, Any]:
        job = self.jobs.get(jid)
        if job is None:
            raise HTTPException(404, "no such job")
        pub = {k: v for k, v in job.items() if k != "files"}
        pub["files"] = {k: f"/v1/jobs/{jid}/files/{Path(v).name}" for k, v in (job.get("files") or {}).items()}
        return pub


def create_app(model=None) -> FastAPI:
    svc = Service(model)
    app = FastAPI(title="Mujassam", version="1.0")
    app.state.svc = svc

    def auth(authorization: str | None = Header(default=None)) -> None:
        if API_KEY and authorization != f"Bearer {API_KEY}":
            raise HTTPException(401, "bad or missing API key")

    @app.get("/health")
    def health():
        info: dict[str, Any] = {"ok": True, "jobs": len(svc.jobs)}
        if svc.model is not None:
            try:
                info["parameters"] = svc.model.num_parameters()
                info["profile"] = svc.model.config.profile
            except Exception:  # noqa: BLE001
                pass
        return info

    @app.post("/v1/text-to-3d", dependencies=[Depends(auth)])
    def text_to_3d(req: TextReq):
        if not req.prompt.strip():
            raise HTTPException(400, "empty prompt")
        return svc.public(svc.submit("text", req.model_dump()))

    @app.post("/v1/image-to-3d", dependencies=[Depends(auth)])
    async def image_to_3d(image: UploadFile = File(...), prompt: str = Form(""), preset: str = Form("balanced")):
        from io import BytesIO

        from PIL import Image
        data = await image.read()
        if len(data) > 20 * 1024 * 1024:
            raise HTTPException(413, "image too large (max 20 MB)")
        try:
            img = Image.open(BytesIO(data)).convert("RGBA")
        except Exception as e:  # noqa: BLE001
            raise HTTPException(400, f"not an image: {e}") from e
        return svc.public(svc.submit("image", {"image": img, "prompt": prompt, "preset": preset}))

    @app.post("/v1/build", dependencies=[Depends(auth)])
    def build(req: SpecReq):
        return svc.public(svc.submit("build", {"spec": req.spec}))

    @app.get("/v1/jobs/{jid}", dependencies=[Depends(auth)])
    def job(jid: str):
        return svc.public(jid)

    @app.get("/v1/jobs/{jid}/files/{name}", dependencies=[Depends(auth)])
    def file(jid: str, name: str):
        job = svc.jobs.get(jid)
        if job is None:
            raise HTTPException(404, "no such job")
        for p in (job.get("files") or {}).values():
            if Path(p).name == name and Path(p).exists():
                return FileResponse(p, filename=name)
        raise HTTPException(404, "no such file")

    return app


app = create_app() if os.environ.get("MUJASSAM_SERVER_AUTOSTART", "1") == "1" else None
