import pytest

from mujassam.blender.sandbox import UnsafeCodeError, check_code
from mujassam.brain.base import extract_json
from mujassam.dsl.patch import apply_and_validate, apply_patch
from mujassam.dsl.schema import normalize_spec


def test_patch_ops(chair_spec):
    spec, _ = normalize_spec(chair_spec)
    ops = [
        {"op": "move", "id": "seat", "by": [0, 0, 0.01]},
        {"op": "rotate", "id": "cushion", "by": [0, 0, 10]},
        {"op": "scale", "id": "leg_front", "factor": 2},
        {"op": "scale", "id": "back_rail", "factor": [1, 2, 1]},
        {"op": "update", "id": "seat", "set": {"bevel": 0.02}},
        {"op": "add", "part": {"id": "stretcher", "type": "box", "size": [0.4, 0.02, 0.02], "location": [0, 0, 0.15]}},
        {"op": "remove", "id": "back_slat"},
        {"op": "material", "name": "oak", "set": {"color": "#000000"}},
        {"op": "assign", "id": "cushion", "material": "oak"},
        {"op": "update", "id": "does_not_exist", "set": {}},
        {"op": "teleport", "id": "seat"},
    ]
    new, log = apply_and_validate(spec, ops)
    by = {p["id"]: p for p in new["parts"]}
    assert by["seat"]["location"][2] == pytest.approx(0.46)
    assert by["cushion"]["rotation"][2] == 10
    assert by["leg_front"]["radius"] == pytest.approx(0.04)
    assert by["back_rail"]["size"][1] == pytest.approx(0.05)
    assert by["seat"]["bevel"] == 0.02
    assert "stretcher" in by and "back_slat" not in by
    assert new["materials"]["oak"]["color"] == "#000000"
    assert by["cushion"]["material"] == "oak"
    assert sum("FAILED" in l for l in log) == 2
    assert spec["parts"][0]["location"][2] == pytest.approx(0.45)  # original untouched


def test_replace_spec():
    new, log = apply_patch({"parts": [{"id": "a", "type": "box"}]},
                           [{"op": "replace_spec", "spec": {"parts": [{"id": "b", "type": "sphere"}]}}])
    assert new["parts"][0]["id"] == "b"


@pytest.mark.parametrize("text,expected", [
    ('{"a": 1}', {"a": 1}),
    ('Sure! ```json\n{"a": [1, 2,],}\n``` hope it helps', {"a": [1, 2]}),
    ('<think>{"no": 1}</think> result: {"ok": True, "v": None}', {"ok": True, "v": None}),
    ('[{"op": "move"}]', [{"op": "move"}]),
    ('{"s": "brace } inside string", "n": 2}', {"s": "brace } inside string", "n": 2}),
])
def test_extract_json(text, expected):
    assert extract_json(text) == expected


def test_extract_json_fails():
    with pytest.raises(ValueError):
        extract_json("no json here")


def test_sandbox_allows_modelling_code():
    check_code("import bpy, math\nfrom mathutils import Vector\nfor i in range(4):\n"
               "    o = cylinder('leg%d' % i, 0.02, 0.4)\n    o.location = Vector((i, 0, 0.2))\n    register(o)\n")


@pytest.mark.parametrize("code", [
    "import os", "from subprocess import run", "open('/etc/passwd')", "__import__('os')",
    "bpy.ops.wm.save_as_mainfile(filepath='x')", "().__class__.__bases__", "while True: pass",
    "eval('1')", "import bpy\nbpy.app.handlers.load_post.append(1)", "def f(:",
])
def test_sandbox_blocks(code):
    with pytest.raises(UnsafeCodeError):
        check_code(code)
