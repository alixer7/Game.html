"""Command line:  python -m mujassam.cli text "..."  |  image photo.jpg  |  build spec.json  |  info"""
from __future__ import annotations

import argparse
import json
import logging
import sys
from pathlib import Path


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(prog="mujassam", description="Mujassam hybrid 3D modelling model")
    ap.add_argument("--model", default="mujassam-4.9b", help="package folder or profile name")
    ap.add_argument("--preset", default=None, choices=["fast", "balanced", "quality"])
    ap.add_argument("--out", default="mujassam_out")
    ap.add_argument("--brain-backend", default=None, choices=["transformers", "openai"])
    ap.add_argument("--openai-url", default=None, help="llama.cpp / vLLM server, e.g. http://127.0.0.1:8080/v1")
    ap.add_argument("--quant", default=None, choices=["nf4", "int8", "none"])
    ap.add_argument("--lora", default=None)
    ap.add_argument("--blender", default=None, help="path to blender executable (default: bpy module or PATH)")
    ap.add_argument("-v", "--verbose", action="store_true")
    sub = ap.add_subparsers(dest="cmd", required=True)
    t = sub.add_parser("text", help="text -> 3D")
    t.add_argument("prompt")
    i = sub.add_parser("image", help="image -> 3D")
    i.add_argument("image")
    i.add_argument("--prompt", default="")
    b = sub.add_parser("build", help="build a spec JSON with Blender (no neural model needed)")
    b.add_argument("spec")
    sub.add_parser("info", help="show profiles and parameter budgets")
    args = ap.parse_args(argv)
    logging.basicConfig(level=logging.INFO if args.verbose else logging.WARNING, format="%(message)s")

    if args.cmd == "info":
        from .model import PROFILES, MujassamConfig
        for name in PROFILES:
            n = MujassamConfig.from_profile(name).nominal_parameters()
            print(f"{name:22s} " + "  ".join(f"{k}={v / 1e9:.2f}B" for k, v in n.items()))
        return 0
    if args.cmd == "build":
        from .blender.runner import BlenderRunner
        from .dsl.schema import normalize_spec
        spec, rep = normalize_spec(json.loads(Path(args.spec).read_text(encoding="utf-8")))
        for w in rep.warnings:
            print("warning:", w)
        res = BlenderRunner(args.blender).build(spec, args.out, name=spec["name"])
        print(json.dumps({"ok": res.ok, "glb": str(res.glb), "blend": str(res.blend), "preview": str(res.grid),
                          "faces": res.stats.get("faces"), "errors": res.stats.get("errors"),
                          "fatal": res.stats.get("fatal")}, indent=1))
        return 0 if res.ok else 1

    from .model import MujassamModel
    ov = {"brain_backend": args.brain_backend, "openai_base_url": args.openai_url,
          "brain_quantization": args.quant, "brain_lora": args.lora, "blender": args.blender}
    model = MujassamModel.from_pretrained(args.model, load_recon=(args.cmd == "image"), **ov)
    print(model.check_budget()[1], file=sys.stderr)
    events = (lambda e: print(json.dumps({k: v for k, v in e.items() if k not in ("route", "analysis", "spec")},
                                         ensure_ascii=False, default=str), file=sys.stderr))
    if args.cmd == "text":
        res = model.generate_from_text(args.prompt, args.out, args.preset, on_event=events)
    else:
        res = model.generate_from_image(args.image, args.prompt, args.out, args.preset, on_event=events)
    print(json.dumps({"score": res.score, "seconds": round(res.seconds, 1), **res.files}, indent=1, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    sys.exit(main())
