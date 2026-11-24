"""Run Blender jobs in an isolated subprocess and collect results.

Works with either
  * the ``bpy`` pip wheel (Blender as a Python module), or
  * a Blender executable (``blender -b --python script.py``), e.g. on Colab / servers.
"""
from __future__ import annotations

import importlib.util
import json
import os
import shutil
import subprocess
import sys
import time
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any

from .compile import compile_freeform, compile_spec


@dataclass
class BuildResult:
    ok: bool
    job_dir: Path
    stats: dict[str, Any] = field(default_factory=dict)
    glb: Path | None = None
    blend: Path | None = None
    script: Path | None = None
    renders: list[Path] = field(default_factory=list)
    grid: Path | None = None
    log: str = ""
    seconds: float = 0.0

    @property
    def error(self) -> str | None:
        if self.ok:
            return None
        return self.stats.get("fatal") or self.log[-2000:] or "unknown Blender failure"


def find_blender(explicit: str | None = None) -> list[str]:
    """Return the command prefix used to run a script."""
    cand = explicit or os.environ.get("MUJASSAM_BLENDER")
    if cand:
        if cand.endswith(".py") or cand == "bpy":
            return [sys.executable]
        return [cand, "-b", "--factory-startup", "--python-exit-code", "1", "--python"]
    if importlib.util.find_spec("bpy") is not None:
        return [sys.executable]
    exe = shutil.which("blender")
    if exe:
        return [exe, "-b", "--factory-startup", "--python-exit-code", "1", "--python"]
    raise RuntimeError(
        "Blender not found. Install the bpy wheel (pip install bpy) or a Blender binary and set "
        "MUJASSAM_BLENDER=/path/to/blender"
    )


class BlenderRunner:
    def __init__(self, blender: str | None = None, timeout: float = 600, res: int = 384,
                 samples: int = 16, engine: str = "CYCLES"):
        self.cmd = find_blender(blender)
        self.timeout = timeout
        self.res = res
        self.samples = samples
        self.engine = engine

    # ------------------------------------------------------------------ public
    def build(self, spec: dict[str, Any] | None, job_dir: str | Path, *, code: str | None = None,
              render: bool = True, save_blend: bool = True, name: str = "model") -> BuildResult:
        job = Path(job_dir)
        job.mkdir(parents=True, exist_ok=True)
        out = {
            "glb": str(job / f"{name}.glb"),
            "blend": str(job / f"{name}.blend") if save_blend else None,
            "renders_dir": str(job / "renders") if render else None,
            "stats": str(job / "stats.json"),
            "res": self.res,
            "samples": self.samples,
            "engine": self.engine,
        }
        if spec is not None:
            script = compile_spec(spec, out)
            (job / "spec.json").write_text(json.dumps(spec, indent=1, ensure_ascii=False), encoding="utf-8")
            # a clean, job-free version for the user to open in Blender / their app
            (job / f"{name}_build.py").write_text(compile_spec(spec, None), encoding="utf-8")
        else:
            assert code is not None, "either spec or code is required"
            script = compile_freeform(code, out, title=name)
            (job / f"{name}_code.py").write_text(code, encoding="utf-8")
        sp = job / "_job.py"
        sp.write_text(script, encoding="utf-8")
        t0 = time.time()
        log = self._run(sp)
        res = self._collect(job, out, log, time.time() - t0)
        res.script = job / (f"{name}_build.py" if spec is not None else f"{name}_code.py")
        return res

    # ------------------------------------------------------------------ internals
    def _run(self, script: Path) -> str:
        cmd = self.cmd + [str(script)]
        env = dict(os.environ)
        env.setdefault("PYTHONNOUSERSITE", "1")
        try:
            p = subprocess.run(cmd, capture_output=True, text=True, timeout=self.timeout, env=env,
                               cwd=str(script.parent))
            return (p.stdout or "") + (p.stderr or "")
        except subprocess.TimeoutExpired as e:
            return f"TIMEOUT after {self.timeout}s\n{e.stdout or ''}{e.stderr or ''}"

    def _collect(self, job: Path, out: dict[str, Any], log: str, secs: float) -> BuildResult:
        stats: dict[str, Any] = {}
        sp = Path(out["stats"])
        if sp.exists():
            try:
                stats = json.loads(sp.read_text())
            except json.JSONDecodeError:
                stats = {"fatal": "stats.json unreadable"}
        else:
            stats = {"fatal": "Blender produced no stats (crash or timeout)"}
        ok = bool(stats.get("ok"))
        glb = Path(out["glb"]) if out.get("glb") and Path(out["glb"]).exists() else None
        blend = Path(out["blend"]) if out.get("blend") and Path(out["blend"]).exists() else None
        renders = [Path(p) for p in stats.get("renders", []) if Path(p).exists()]
        grid = make_grid(renders, job / "grid.png") if renders else None
        return BuildResult(ok=ok and glb is not None, job_dir=job, stats=stats, glb=glb, blend=blend,
                           renders=renders, grid=grid, log=log, seconds=secs)


def make_grid(paths: list[Path], out: Path, label: bool = True) -> Path | None:
    """Tile the multi-view renders into one image (one image = fewer vision tokens)."""
    try:
        from PIL import Image, ImageDraw
    except ImportError:
        return None
    ims = [Image.open(p).convert("RGB") for p in paths]
    if not ims:
        return None
    w, h = ims[0].size
    cols = 2 if len(ims) > 1 else 1
    rows = (len(ims) + cols - 1) // cols
    grid = Image.new("RGB", (w * cols, h * rows), (255, 255, 255))
    for i, (im, p) in enumerate(zip(ims, paths)):
        x, y = (i % cols) * w, (i // cols) * h
        grid.paste(im.resize((w, h)), (x, y))
        if label:
            d = ImageDraw.Draw(grid)
            txt = p.stem.upper().replace("_", " ")
            d.rectangle([x, y, x + 8 * len(txt) + 10, y + 18], fill=(0, 0, 0))
            d.text((x + 5, y + 3), txt, fill=(255, 255, 255))
    grid.save(out)
    return out
