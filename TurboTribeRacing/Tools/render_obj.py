#!/usr/bin/env python3
"""OBJ loader for the exporter's 'v x y z r g b [nx ny nz]' + 'f a b c' files (used by webgl_render.py / render_karts.py)."""
import numpy as np

def load(path, normals=False):
    V = []; C = []; N = []; F = []
    with open(path) as f:
        for line in f:
            if line.startswith('v '):
                p = line.split(); V.append([float(p[1]), float(p[2]), float(p[3])]); C.append([float(p[4]), float(p[5]), float(p[6])])
                N.append([float(p[7]), float(p[8]), float(p[9])] if len(p) >= 10 else [0.0, 0.0, 0.0])
            elif line.startswith('f '):
                p = line.split(); F.append([int(p[1]) - 1, int(p[2]) - 1, int(p[3]) - 1])
    if normals: return np.array(V), np.array(C), np.array(F), np.array(N)
    return np.array(V), np.array(C), np.array(F)
