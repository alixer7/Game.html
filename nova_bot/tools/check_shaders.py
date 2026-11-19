#!/usr/bin/env python3
"""Cross-checks set_shader_parameter("name", ...) calls in the scripts against the uniforms of the shaders
loaded in the same file, and lists uniforms that no script ever sets (informational)."""
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
uni_re = re.compile(r"^\s*uniform\s+\w+\s+(\w+)", re.M)
shaders = {}
for fn in os.listdir(os.path.join(ROOT, "shaders")):
    if fn.endswith(".gdshader"):
        shaders["res://shaders/" + fn] = set(uni_re.findall(open(os.path.join(ROOT, "shaders", fn), encoding="utf-8").read()))
setters = {k: set() for k in shaders}
errors = 0
for dp, _, fns in os.walk(os.path.join(ROOT, "scripts")):
    for fn in fns:
        if not fn.endswith(".gd"):
            continue
        path = os.path.join(dp, fn)
        text = open(path, encoding="utf-8").read()
        used = [s for s in shaders if s in text]
        allowed = set()
        for s in used:
            allowed |= shaders[s]
        for m in re.finditer(r'set_shader_parameter\(\s*"(\w+)"', text):
            name = m.group(1)
            line = text[:m.start()].count("\n") + 1
            for s in used:
                if name in shaders[s]:
                    setters[s].add(name)
            if name not in allowed and any(name in u for u in shaders.values()):
                continue  # material built through Mats.* (the shader is not loaded in this file)
            if name not in allowed:
                print("ERROR %s:%d: shader parameter %r is not a uniform of %s" % (os.path.relpath(path, ROOT), line, name, ", ".join(sorted(os.path.basename(u) for u in used)) or "(no shader loaded in this file)"))
                errors += 1
if "--unused" in sys.argv:
    for s, u in sorted(shaders.items()):
        miss = sorted(u - setters[s])
        if miss:
            print("%s never sets: %s" % (os.path.basename(s), ", ".join(miss)))
print("%d shader parameter errors" % errors)
sys.exit(1 if errors else 0)
