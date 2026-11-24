"""Image -> 3D mesh reconstruction backends.

* TripoSR (MIT, ~0.42 B params, ~0.5 s on an A100, ~6 GB VRAM, also runs on CPU) — default.
* TRELLIS.2-4B (MIT, ~4 B params, 24 GB+ GPU) — optional 'pro' backend; exceeds the 4-5 B budget
  when combined with the 4 B brain, so it is never part of the default profile.

Both return a mesh file that the Blender layer imports, cleans (merge, floater removal,
decimation), normalises (centre, ground, real-world size) and that the critic can then
re-orient / re-scale / extend with procedural parts.
"""
from __future__ import annotations

import os
import sys
import time
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any

from ..brain.base import load_image


@dataclass
class ReconResult:
    mesh_path: Path
    rotation_fix: list[float] = field(default_factory=lambda: [0.0, 0.0, 0.0])
    seconds: float = 0.0
    preprocessed: Path | None = None
    backend: str = ""


class Reconstructor:
    name = "none"

    def reconstruct(self, image: Any, out_dir: str | Path) -> ReconResult:
        raise NotImplementedError

    def num_parameters(self) -> int:
        return 0


def _count(module) -> int:
    return sum(p.numel() for p in module.parameters())


class TripoSRReconstructor(Reconstructor):
    """Wraps https://github.com/VAST-AI-Research/TripoSR (clone it and pass repo_path)."""
    name = "triposr"
    # TripoSR's camera looks from +X with Z up, so the object's front faces +X.
    # Mujassam's convention is front = -Y  ->  rotate -90 deg about Z.
    ROTATION_FIX = [0.0, 0.0, -90.0]

    def __init__(self, model_id_or_dir: str = "stabilityai/TripoSR", repo_path: str | None = None,
                 device: str | None = None, chunk_size: int = 8192, mc_resolution: int = 256,
                 foreground_ratio: float = 0.85, rembg_model: str = "u2net"):
        import torch
        repo_path = repo_path or os.environ.get("TRIPOSR_PATH")
        if repo_path and repo_path not in sys.path:
            sys.path.insert(0, repo_path)
        from tsr.system import TSR  # noqa: E402  (from the TripoSR repo)

        self.torch = torch
        self.device = device or ("cuda:0" if torch.cuda.is_available() else "cpu")
        self.model = TSR.from_pretrained(model_id_or_dir, config_name="config.yaml", weight_name="model.ckpt")
        self.model.renderer.set_chunk_size(chunk_size)
        self.model.to(self.device)
        self.model.eval()
        self.mc_resolution = mc_resolution
        self.foreground_ratio = foreground_ratio
        self.rembg_model = rembg_model
        self._rembg = None

    def num_parameters(self) -> int:
        return _count(self.model)

    def _session(self):
        if self._rembg is None:
            import rembg
            self._rembg = rembg.new_session(self.rembg_model)
        return self._rembg

    def preprocess(self, image: Any):
        import numpy as np
        from PIL import Image
        from tsr.utils import remove_background, resize_foreground

        img = image if hasattr(image, "mode") else Image.open(image)
        img = remove_background(img, self._session())
        img = resize_foreground(img, self.foreground_ratio)
        arr = np.array(img).astype(np.float32) / 255.0
        arr = arr[:, :, :3] * arr[:, :, 3:4] + (1 - arr[:, :, 3:4]) * 0.5
        return Image.fromarray((arr * 255.0).astype(np.uint8))

    def reconstruct(self, image: Any, out_dir: str | Path) -> ReconResult:
        out = Path(out_dir)
        out.mkdir(parents=True, exist_ok=True)
        t0 = time.time()
        img = self.preprocess(image)
        pre = out / "recon_input.png"
        img.save(pre)
        with self.torch.no_grad():
            codes = self.model([img], device=self.device)
            meshes = self.model.extract_mesh(codes, True, resolution=self.mc_resolution)
        path = out / "recon.ply"
        meshes[0].export(str(path))
        return ReconResult(mesh_path=path, rotation_fix=list(self.ROTATION_FIX), seconds=time.time() - t0,
                           preprocessed=pre, backend=self.name)


class Trellis2Reconstructor(Reconstructor):
    """Wraps https://github.com/microsoft/TRELLIS.2 (needs its CUDA extensions, 24 GB GPU)."""
    name = "trellis2"

    def __init__(self, model_id_or_dir: str = "microsoft/TRELLIS.2-4B", repo_path: str | None = None,
                 decimation_target: int = 200_000, texture_size: int = 2048):
        os.environ.setdefault("PYTORCH_CUDA_ALLOC_CONF", "expandable_segments:True")
        repo_path = repo_path or os.environ.get("TRELLIS2_PATH")
        if repo_path and repo_path not in sys.path:
            sys.path.insert(0, repo_path)
        from trellis2.pipelines import Trellis2ImageTo3DPipeline  # noqa: E402

        self.pipeline = Trellis2ImageTo3DPipeline.from_pretrained(model_id_or_dir)
        self.pipeline.cuda()
        self.decimation_target = decimation_target
        self.texture_size = texture_size

    def num_parameters(self) -> int:
        total = 0
        for m in getattr(self.pipeline, "models", {}).values():
            if hasattr(m, "parameters"):
                total += _count(m)
        return total

    def reconstruct(self, image: Any, out_dir: str | Path) -> ReconResult:
        import o_voxel  # from the TRELLIS.2 repo

        out = Path(out_dir)
        out.mkdir(parents=True, exist_ok=True)
        t0 = time.time()
        mesh = self.pipeline.run(load_image(image))[0]
        mesh.simplify(16777216)
        glb = o_voxel.postprocess.to_glb(
            vertices=mesh.vertices, faces=mesh.faces, attr_volume=mesh.attrs, coords=mesh.coords,
            attr_layout=mesh.layout, voxel_size=mesh.voxel_size, aabb=[[-0.5, -0.5, -0.5], [0.5, 0.5, 0.5]],
            decimation_target=self.decimation_target, texture_size=self.texture_size,
            remesh=True, remesh_band=1, remesh_project=0, verbose=False)
        path = out / "recon.glb"
        glb.export(str(path))
        # glTF is Y-up; Blender's importer converts it to Z-up for us.
        return ReconResult(mesh_path=path, rotation_fix=[0.0, 0.0, 0.0], seconds=time.time() - t0, backend=self.name)


class MeshFileReconstructor(Reconstructor):
    """Test/offline backend: 'reconstructs' by returning an existing mesh file."""
    name = "file"

    def __init__(self, mesh_path: str | Path, rotation_fix: list[float] | None = None):
        self.mesh_path = Path(mesh_path)
        self.rotation_fix = rotation_fix or [0.0, 0.0, 0.0]

    def reconstruct(self, image: Any, out_dir: str | Path) -> ReconResult:
        return ReconResult(mesh_path=self.mesh_path, rotation_fix=list(self.rotation_fix), backend=self.name)


def mesh_spec(recon: ReconResult, name: str, height_m: float | None, material: str | None = None) -> dict[str, Any]:
    """Wrap a reconstructed mesh as a one-part scene spec (so the critic can edit it like any other)."""
    part: dict[str, Any] = {"id": "recon", "type": "mesh_file", "path": str(recon.mesh_path),
                            "rotation_fix": recon.rotation_fix, "location": [0, 0, 0]}
    if height_m:
        part["target_size"] = float(height_m)
        part["size_axis"] = "z"
    if material:
        part["material"] = material
    return {"name": name, "style": "reconstructed", "materials": {}, "parts": [part]}
