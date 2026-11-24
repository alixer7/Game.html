"""MujassamModel — the hybrid neural model as one object you can load, count, save and run.

Default profile ``mujassam-4.9b`` (inside the requested 4-5 B parameter budget):

  component            role                                   params    license
  -------------------  -------------------------------------  --------  ----------
  Qwen3-VL-4B-Instruct brain: router, planner, analyst,        ~4.44 B   Apache-2.0
                       critic (sees its own renders)
  TripoSR              image -> 3D mesh reconstruction         ~0.42 B   MIT
  U2-Net (rembg)       background removal for image inputs     ~0.04 B   Apache-2.0
  -------------------  -------------------------------------  --------
  total                                                        ~4.90 B

Exact counts are measured at load time (``num_parameters()``) and checked against the budget.
"""
from __future__ import annotations

import json
import os
import shutil
from dataclasses import asdict, dataclass, field
from pathlib import Path
from typing import Any

from .blender.runner import BlenderRunner
from .brain.base import Brain
from .pipeline import GenerationConfig, GenerationResult, MujassamPipeline
from .recon.reconstruct import Reconstructor

CONFIG_NAME = "mujassam_config.json"

# Nominal sizes (from the model cards) used for planning before weights are downloaded.
NOMINAL_PARAMS = {
    "Qwen/Qwen3-VL-4B-Instruct": 4.44e9,
    "Qwen/Qwen3-VL-2B-Instruct": 2.13e9,
    "Qwen/Qwen3-VL-8B-Instruct": 8.77e9,
    "stabilityai/TripoSR": 0.42e9,
    "microsoft/TRELLIS.2-4B": 4.0e9,
    "rembg:u2net": 0.044e9,
}

PROFILES: dict[str, dict[str, Any]] = {
    # the one you asked for: 4-5 B parameters
    "mujassam-4.9b": {"brain_model": "Qwen/Qwen3-VL-4B-Instruct", "recon_backend": "triposr",
                      "recon_model": "stabilityai/TripoSR"},
    # for small GPUs (6-8 GB) / faster turnaround
    "mujassam-lite-2.6b": {"brain_model": "Qwen/Qwen3-VL-2B-Instruct", "recon_backend": "triposr",
                           "recon_model": "stabilityai/TripoSR"},
    # best image->3D quality, needs a 24 GB+ GPU; ~8.4 B, outside the 4-5 B budget
    "mujassam-pro-8.4b": {"brain_model": "Qwen/Qwen3-VL-4B-Instruct", "recon_backend": "trellis2",
                          "recon_model": "microsoft/TRELLIS.2-4B", "param_budget": [4e9, 9e9]},
}


@dataclass
class MujassamConfig:
    profile: str = "mujassam-4.9b"
    brain_backend: str = "transformers"          # transformers | openai | scripted
    brain_model: str = "Qwen/Qwen3-VL-4B-Instruct"
    brain_quantization: str = "nf4"              # nf4 | int8 | none
    brain_lora: str | None = None                # path to a Mujassam LoRA adapter (training/)
    openai_base_url: str = "http://127.0.0.1:8080/v1"
    openai_model: str = "mujassam-brain"
    recon_backend: str = "triposr"               # triposr | trellis2 | none
    recon_model: str = "stabilityai/TripoSR"
    triposr_repo: str | None = None
    trellis2_repo: str | None = None
    rembg_model: str = "u2net"
    blender: str | None = None
    preset: str = "balanced"
    param_budget: list[float] = field(default_factory=lambda: [4.0e9, 5.0e9])

    @classmethod
    def from_profile(cls, profile: str = "mujassam-4.9b", **overrides: Any) -> "MujassamConfig":
        if profile not in PROFILES:
            raise KeyError(f"unknown profile {profile!r}; choose from {sorted(PROFILES)}")
        kw = dict(PROFILES[profile])
        kw.update({k: v for k, v in overrides.items() if v is not None})
        return cls(profile=profile, **kw)

    def nominal_parameters(self) -> dict[str, float]:
        out = {"brain": NOMINAL_PARAMS.get(self.brain_model, 0.0)}
        if self.recon_backend != "none":
            out["recon"] = NOMINAL_PARAMS.get(self.recon_model, 0.0)
            if self.recon_backend == "triposr":
                out["bg_removal"] = NOMINAL_PARAMS["rembg:u2net"]
        out["total"] = sum(out.values())
        return out

    def save(self, path: str | Path) -> None:
        Path(path).write_text(json.dumps(asdict(self), indent=2), encoding="utf-8")

    @classmethod
    def load(cls, path: str | Path) -> "MujassamConfig":
        data = json.loads(Path(path).read_text(encoding="utf-8"))
        known = {f for f in cls.__dataclass_fields__}
        return cls(**{k: v for k, v in data.items() if k in known})


class MujassamModel:
    """Brain + reconstructor + Blender, behind generate_from_text / generate_from_image."""

    def __init__(self, config: MujassamConfig, brain: Brain, reconstructor: Reconstructor | None = None,
                 runner: BlenderRunner | None = None):
        self.config = config
        self.brain = brain
        self.reconstructor = reconstructor
        self.runner = runner

    # ------------------------------------------------------------------ loading
    @classmethod
    def from_pretrained(cls, path_or_profile: str = "mujassam-4.9b", *, load_recon: bool = True,
                        **overrides: Any) -> "MujassamModel":
        """Load from a saved package directory (see save_pretrained) or a profile name."""
        p = Path(path_or_profile)
        if p.is_dir() and (p / CONFIG_NAME).exists():
            cfg = MujassamConfig.load(p / CONFIG_NAME)
            for k, v in overrides.items():
                if v is not None and hasattr(cfg, k):
                    setattr(cfg, k, v)
            # components saved inside the package
            if (p / "brain").is_dir():
                cfg.brain_model = str(p / "brain")
            if (p / "brain_lora").is_dir() and not overrides.get("brain_lora"):
                cfg.brain_lora = str(p / "brain_lora")
            if (p / "recon").is_dir():
                cfg.recon_model = str(p / "recon")
            if (p / "recon" / f"{cfg.rembg_model}.onnx").exists():
                os.environ.setdefault("U2NET_HOME", str(p / "recon"))
        else:
            cfg = MujassamConfig.from_profile(path_or_profile, **overrides)
        brain = cls._load_brain(cfg)
        recon = cls._load_recon(cfg) if load_recon else None
        return cls(cfg, brain, recon, BlenderRunner(cfg.blender))

    @staticmethod
    def _load_brain(cfg: MujassamConfig) -> Brain:
        if cfg.brain_backend == "transformers":
            from .brain.qwen_vl import QwenVLBrain
            return QwenVLBrain(cfg.brain_model, quantization=cfg.brain_quantization, lora=cfg.brain_lora)
        if cfg.brain_backend == "openai":
            from .brain.qwen_vl import OpenAICompatBrain
            return OpenAICompatBrain(cfg.openai_base_url, cfg.openai_model,
                                     param_count=int(NOMINAL_PARAMS.get(cfg.brain_model, 0)))
        raise ValueError(f"brain_backend {cfg.brain_backend!r} cannot be loaded automatically")

    @staticmethod
    def _load_recon(cfg: MujassamConfig) -> Reconstructor | None:
        if cfg.recon_backend == "triposr":
            from .recon.reconstruct import TripoSRReconstructor
            return TripoSRReconstructor(cfg.recon_model, repo_path=cfg.triposr_repo, rembg_model=cfg.rembg_model)
        if cfg.recon_backend == "trellis2":
            from .recon.reconstruct import Trellis2Reconstructor
            return Trellis2Reconstructor(cfg.recon_model, repo_path=cfg.trellis2_repo)
        return None

    # ------------------------------------------------------------------ size
    def num_parameters(self) -> dict[str, int]:
        out = {"brain": int(self.brain.num_parameters())}
        if self.reconstructor is not None:
            out["recon"] = int(self.reconstructor.num_parameters())
            if self.config.recon_backend == "triposr":
                out["bg_removal"] = int(NOMINAL_PARAMS["rembg:u2net"])
        out["total"] = sum(v for k, v in out.items())
        return out

    def check_budget(self) -> tuple[bool, str]:
        n = self.num_parameters()["total"]
        lo, hi = self.config.param_budget
        ok = lo <= n <= hi
        return ok, f"{n / 1e9:.2f} B parameters ({'within' if ok else 'OUTSIDE'} budget {lo / 1e9:.1f}-{hi / 1e9:.1f} B)"

    # ------------------------------------------------------------------ inference
    def pipeline(self, preset: str | None = None, on_event=None, **gen_overrides: Any) -> MujassamPipeline:
        gcfg = GenerationConfig.from_preset(preset or self.config.preset, **gen_overrides)
        runner = self.runner or BlenderRunner(self.config.blender)
        runner.res, runner.samples = gcfg.render_res, gcfg.render_samples
        return MujassamPipeline(self.brain, runner, self.reconstructor, gcfg, on_event=on_event)

    def generate_from_text(self, prompt: str, out_dir: str | Path = "mujassam_out", preset: str | None = None,
                           **kw: Any) -> GenerationResult:
        return self.pipeline(preset, **kw).generate(prompt, None, out_dir)

    def generate_from_image(self, image: Any, prompt: str = "", out_dir: str | Path = "mujassam_out",
                            preset: str | None = None, **kw: Any) -> GenerationResult:
        return self.pipeline(preset, **kw).generate(prompt, image, out_dir)

    # ------------------------------------------------------------------ packaging
    def save_pretrained(self, out_dir: str | Path, *, merge_lora: bool = False) -> Path:
        """Write a self-contained package: brain weights (quantized if loaded quantized),
        reconstructor weights, background-removal weights and the config.

        The result is what gets copied to Google Drive / served on a GPU box.
        """
        out = Path(out_dir)
        out.mkdir(parents=True, exist_ok=True)
        cfg = MujassamConfig(**asdict(self.config))
        brain = self.brain
        if hasattr(brain, "model") and hasattr(brain, "processor"):
            model = brain.model
            if cfg.brain_lora and hasattr(model, "save_pretrained") and not merge_lora:
                model.save_pretrained(out / "brain_lora")       # adapter only
                base = model.get_base_model() if hasattr(model, "get_base_model") else model
                base.save_pretrained(out / "brain", safe_serialization=True)
            else:
                if merge_lora and hasattr(model, "merge_and_unload"):
                    model = model.merge_and_unload()
                model.save_pretrained(out / "brain", safe_serialization=True)
                cfg.brain_lora = None
            brain.processor.save_pretrained(out / "brain")
        rec = self.reconstructor
        if rec is not None and cfg.recon_backend == "triposr":
            (out / "recon").mkdir(exist_ok=True)
            src = Path(cfg.recon_model)
            if src.is_dir():
                files = [src / "config.yaml", src / "model.ckpt"]
            else:
                from huggingface_hub import hf_hub_download
                files = [Path(hf_hub_download(cfg.recon_model, f)) for f in ("config.yaml", "model.ckpt")]
            for f in files:
                shutil.copy2(f, out / "recon" / f.name)
            u2 = Path(os.environ.get("U2NET_HOME", Path.home() / ".u2net")) / f"{cfg.rembg_model}.onnx"
            if u2.exists():
                shutil.copy2(u2, out / "recon" / u2.name)
        cfg.save(out / CONFIG_NAME)
        try:
            counts = self.num_parameters()
        except Exception:  # noqa: BLE001
            counts = {}
        (out / "MODEL_CARD.md").write_text(_model_card(cfg, counts), encoding="utf-8")
        return out


def _model_card(cfg: MujassamConfig, counts: dict[str, int]) -> str:
    rows = "\n".join(f"| {k} | {v / 1e9:.3f} B |" for k, v in counts.items()) or "| (not measured) | |"
    return f"""# Mujassam ({cfg.profile})

Hybrid neural 3D-modelling model for Blender: a vision-language brain that plans models in the
Mujassam Scene Spec, sees its own renders and fixes them, plus a neural image-to-3D reconstructor.

| component | parameters |
|---|---|
{rows}

* brain: `{cfg.brain_model}` (quantization: {cfg.brain_quantization}, LoRA: {cfg.brain_lora or 'none'})
* reconstruction: `{cfg.recon_backend}` / `{cfg.recon_model}`

Licenses of the bundled weights: Qwen3-VL (Apache-2.0), TripoSR (MIT), U2-Net (Apache-2.0).
Keep this file and the upstream licenses when you share the package.

```python
from mujassam import MujassamModel
m = MujassamModel.from_pretrained("/path/to/this/folder")
m.generate_from_text("كرسي خشبي بتصميم حديث مع وسادة زرقاء", out_dir="out")
```
"""
