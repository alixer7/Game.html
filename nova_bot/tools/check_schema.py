#!/usr/bin/env python3
"""Compares the keys the level JSON files use for every object type with the keys the GDScript classes read
in their setup(o) methods (a typo on either side would silently fall back to a default)."""
import json
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
loader = open(os.path.join(ROOT, "scripts/game/level_loader.gd"), encoding="utf-8").read()
pairs = re.findall(r'((?:t == "\w+"(?: or )?)+):\n\t\treturn ([\w\.]+)\.new\(\)', loader)
cls_of = {}
for conds, cls in pairs:
    for t in re.findall(r't == "(\w+)"', conds):
        cls_of[t] = cls


def class_source(qual):
    """source text of the class body for Outer.Inner (or a whole file for class_name classes)"""
    parts = qual.split(".")
    for dp, _, fns in os.walk(os.path.join(ROOT, "scripts")):
        for fn in fns:
            if not fn.endswith(".gd"):
                continue
            text = open(os.path.join(dp, fn), encoding="utf-8").read()
            if re.search(r"^class_name %s\b" % parts[0], text, re.M):
                if len(parts) == 1:
                    return text
                m = re.search(r"^class %s\b.*?:\n(.*?)(?=^class |\Z)" % parts[1], text, re.M | re.S)
                if m:
                    return m.group(1)
    return ""


used = {}
for i in range(1, 5):
    d = json.load(open(os.path.join(ROOT, "levels", "level_%d.json" % i), encoding="utf-8"))
    for o in d["objects"]:
        used.setdefault(o["t"], set()).update(k for k in o if k != "t")
bad = 0
for t, keys in sorted(used.items()):
    if t == "coins":
        continue  # read by LevelLoader itself (one shared MultiMesh)
    cls = cls_of.get(t)
    if not cls:
        print("ERROR no class for type", t)
        bad += 1
        continue
    src = class_source(cls)
    read = set(re.findall(r'\bo\.get\("(\w+)"', src)) | set(re.findall(r'\bo\["(\w+)"\]', src)) | set(re.findall(r'\bo\.has\("(\w+)"\)', src))
    # LevelLoader reads p / a / b / off itself for the bounding box; "pts" for coins
    missing = sorted(k for k in keys if k not in read)
    if missing:
        print("ERROR %-8s (%s): JSON keys never read by the class: %s" % (t, cls, ", ".join(missing)))
        bad += 1
print("%d schema problems" % bad)
sys.exit(1 if bad else 0)
