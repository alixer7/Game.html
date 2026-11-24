import json

import pytest

from mujassam.dsl.schema import SpecError, normalize_spec


def test_chair_is_clean(chair_spec):
    spec, rep = normalize_spec(chair_spec)
    assert rep.warnings == []
    assert [p["id"] for p in spec["parts"]][:2] == ["seat", "cushion"]
    assert spec["parts"][2]["mirror"] == ["x"]


def test_repairs_common_model_mistakes():
    raw = {"name": "Big Thing!", "parts": [
        {"id": "a", "type": "cuboid", "dimensions": [1, 2, 3], "location": [0, 0, "x"]},
        {"id": "a", "type": "ball", "radius": -1, "material": "red"},
        {"id": "c", "type": "cylinder", "height": 2, "parent": "ghost", "material": {"color": "#00ff00"}},
        {"id": "d", "type": "wormhole"},
        "garbage",
    ]}
    spec, rep = normalize_spec(raw)
    ids = [p["id"] for p in spec["parts"]]
    assert spec["name"] == "big_thing"
    assert ids == ["a", "a_2", "c", "d"]
    assert spec["parts"][0]["type"] == "box" and spec["parts"][0]["size"] == [1, 2, 3]
    assert spec["parts"][0]["location"] == [0, 0, 0]
    assert spec["parts"][1]["radius"] > 0
    assert "parent" not in spec["parts"][2]
    assert spec["parts"][2]["depth"] == 2
    assert spec["parts"][2]["material"] in spec["materials"]
    assert "red" in spec["materials"]
    assert spec["parts"][3]["type"] == "box"
    assert rep.warnings


def test_parent_cycles_are_broken():
    spec, rep = normalize_spec({"parts": [
        {"id": "a", "type": "box", "parent": "b"}, {"id": "b", "type": "box", "parent": "a"}]})
    assert not ("parent" in spec["parts"][0] and "parent" in spec["parts"][1])


def test_cutters_marked():
    spec, _ = normalize_spec({"parts": [
        {"id": "wall", "type": "box", "cutters": ["win", "nope"]}, {"id": "win", "type": "box"}]})
    assert spec["parts"][0]["cutters"] == ["win"]
    assert spec["parts"][1]["cutter"] is True


@pytest.mark.parametrize("bad", [None, {}, {"parts": []}, {"parts": [{"type": "lathe", "profile": [[1, 0]]}]},
                                 {"parts": [{"id": "x", "type": "box", "cutter": True}]}])
def test_hopeless_specs_raise(bad):
    with pytest.raises(SpecError):
        normalize_spec(bad)


def test_limits_clamp():
    spec, _ = normalize_spec({"parts": [{"type": "sphere", "segments": 10_000, "radius": 1e9},
                                        {"type": "box", "array": {"count": 999}}]})
    assert spec["parts"][0]["segments"] <= 128
    assert spec["parts"][0]["radius"] <= 500
    assert spec["parts"][1]["array"]["count"] <= 64


def test_compact_roundtrip(chair_spec):
    from mujassam.dsl.schema import compact_spec
    spec, _ = normalize_spec(chair_spec)
    c = compact_spec(spec)
    assert "rotation" not in c["parts"][0] and "metallic" not in c["materials"]["oak"]
    again, rep = normalize_spec(c)
    assert again == spec and rep.warnings == []
    assert len(json.dumps(c)) < 0.8 * len(json.dumps(spec))


def test_floats_are_rounded():
    spec, _ = normalize_spec({"parts": [{"type": "box", "location": [0.1 + 0.2, 1 / 3, -1e-9]}]})
    assert spec["parts"][0]["location"] == [0.3, 0.3333, 0.0]
