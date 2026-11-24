"""Turn a spec (or sandboxed freeform bpy code) into a self-contained Blender script."""
from __future__ import annotations

import json
from functools import lru_cache
from pathlib import Path
from typing import Any

from .sandbox import check_code

_LIB = Path(__file__).with_name("bl_lib.py")


@lru_cache(maxsize=1)
def blender_library() -> str:
    return _LIB.read_text(encoding="utf-8")


def _header(title: str) -> str:
    return (
        "# " + "=" * 76 + "\n"
        f"# Mujassam generated script — {title}\n"
        "# Run in Blender:  blender -b --python this_file.py   (or paste into the Text Editor)\n"
        "# " + "=" * 76 + "\n"
    )


def compile_spec(spec: dict[str, Any], out: dict[str, Any] | None = None) -> str:
    """Spec -> Blender script. ``out`` selects what the script writes (glb/blend/renders/stats).

    With ``out=None`` the script only builds the model (handy for pasting into Blender).
    """
    body = [_header(spec.get("name", "model")), blender_library(), "", "# ---- job " + "-" * 66]
    body.append("SPEC = json.loads(%r)" % json.dumps(spec, ensure_ascii=False))
    if out is None:
        body.append("build_spec(SPEC)")
    else:
        body.append("OUT = json.loads(%r)" % json.dumps(out))
        body.append("_status = run_job(SPEC, OUT)")
        body.append("if not _status.get('ok'):\n    print(_status.get('traceback', _status))\n    sys.exit(1)")
    return "\n".join(body) + "\n"


def compile_freeform(code: str, out: dict[str, Any] | None = None, title: str = "freeform") -> str:
    """Wrap model-written bpy code (after a safety check) with the helper library + job tail."""
    check_code(code)
    body = [_header(title), blender_library(), "", "begin_freeform()", "# ---- generated code " + "-" * 55,
            code, "# ---- job " + "-" * 66]
    if out is None:
        body.append("finish_freeform()")
    else:
        body.append("OUT = json.loads(%r)" % json.dumps(out))
        body.append("_status = run_job(None, OUT)")
        body.append("if not _status.get('ok'):\n    print(_status.get('traceback', _status))\n    sys.exit(1)")
    return "\n".join(body) + "\n"
