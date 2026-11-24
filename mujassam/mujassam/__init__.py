"""Mujassam (مُجسَّم) — a hybrid neural 3D-modelling model for Blender.

Text or image in, editable Blender model (.blend / .glb / build script) out. The brain sees its
own renders and keeps improving the model until it passes its own review.
"""
from .dsl.schema import normalize_spec, SpecError
from .dsl.patch import apply_patch, apply_and_validate
from .blender.runner import BlenderRunner, BuildResult
from .pipeline import GenerationConfig, GenerationResult, MujassamPipeline, PRESETS
from .model import MujassamConfig, MujassamModel, PROFILES

__version__ = "1.0.0"
__all__ = [
    "normalize_spec", "SpecError", "apply_patch", "apply_and_validate", "BlenderRunner", "BuildResult",
    "GenerationConfig", "GenerationResult", "MujassamPipeline", "PRESETS", "MujassamConfig",
    "MujassamModel", "PROFILES", "__version__",
]
