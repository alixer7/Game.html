import importlib.util
import shutil
import sys
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))

HAS_BLENDER = importlib.util.find_spec("bpy") is not None or shutil.which("blender") is not None
needs_blender = pytest.mark.skipif(not HAS_BLENDER, reason="Blender (bpy or binary) not available")


@pytest.fixture
def chair_spec():
    import json
    return json.loads((ROOT / "examples/specs/chair.json").read_text())
