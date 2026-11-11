#!/usr/bin/env python3
"""Scene QA on the exported track OBJ (Tools/HeadlessShim export): finds props that FLOAT above the terrain and
props that INTRUDE into a drivable road corridor.

Every prop / landmark / tunnel-rock mesh is split into connected pieces (shared vertices); for each piece:
  floating  - its lowest point is more than 0.6 m above the terrain under it (and it is not standing on a road,
              a bridge deck or another piece - roofs, canopies, crests and lamps on posts are part of one piece)
  intrusion - any vertex lies inside a road's corridor (within the half-width, from the surface up to 4 m)
usage: check_scene.py track.obj track.json   ->  prints a report, exit code 1 if anything was found
"""
import json, sys
import numpy as np
sys.path.insert(0, __file__.rsplit('/', 1)[0] + '/trackgen')
from preview import build, mods_for


def load_objects(path):
    objs = {}; cur = None; V = []; C = []
    for line in open(path):
        if line.startswith('o '):
            cur = line.split()[1]; objs[cur] = []
        elif line.startswith('v '):
            p = line.split(); V.append((float(p[1]), float(p[2]), float(p[3])))
        elif line.startswith('f '):
            p = line.split(); objs[cur].append((int(p[1]) - 1, int(p[2]) - 1, int(p[3]) - 1))
    return np.array(V), objs


def components(faces):
    parent = {}
    def find(a):
        while parent.setdefault(a, a) != a:
            parent[a] = parent[parent[a]]; a = parent[a]
        return a
    for a, b, c in faces:
        ra, rb, rc = find(a), find(b), find(c)
        parent[rb] = ra; parent[find(rc)] = ra
    groups = {}
    for v in parent: groups.setdefault(find(v), []).append(v)
    return list(groups.values())


def main():
    V, objs = load_objects(sys.argv[1])
    tr = json.load(open(sys.argv[2]))
    # terrain height field from the Terrain mesh (a regular grid)
    tv = np.unique(np.array([i for f in objs['Terrain'] for i in f]))
    T = V[tv]
    xs = np.unique(np.round(T[:, 0], 2)); zs = np.unique(np.round(T[:, 2], 2))
    H = np.full((len(xs), len(zs)), np.nan)
    ix = np.searchsorted(xs, np.round(T[:, 0], 2)); iz = np.searchsorted(zs, np.round(T[:, 2], 2))
    H[ix, iz] = T[:, 1]

    def terrain(x, z):
        fx = np.interp(x, xs, np.arange(len(xs))); fz = np.interp(z, zs, np.arange(len(zs)))
        i0 = np.clip(np.floor(fx).astype(int), 0, len(xs) - 2); j0 = np.clip(np.floor(fz).astype(int), 0, len(zs) - 2)
        tx = fx - i0; tz = fz - j0
        a = H[i0, j0] * (1 - tx) + H[i0 + 1, j0] * tx; b = H[i0, j0 + 1] * (1 - tx) + H[i0 + 1, j0 + 1] * tx
        return a * (1 - tz) + b * tz

    # road corridors (main + branches), 1 m samples
    roads = []
    main = build(tr['roads'][0]['points'], True, 1.0, mods=mods_for(tr, 'main'))
    roads.append(('main', main.pos, main.hw))
    for r in tr['roads'][1:]:
        s = build(r['points'], False, 1.0)
        roads.append((r['id'], s.pos, s.hw))
    allP = np.vstack([p for _, p, _ in roads]); allW = np.concatenate([w for _, _, w in roads])
    allN = np.concatenate([[n] * len(p) for n, p, _ in roads])
    gaps = set()
    for rg in tr['ranges']:
        if rg['type'] == 'gap': gaps.add(rg['road'])

    floating, intrude = [], []
    checked = 0
    # pieces of one prop touch each other (roof on walls, steps of a pyramid, leaves on a branch): merge pieces whose
    # bounding boxes overlap into assemblies, then judge each assembly as a whole
    pieces = []
    for name, faces in objs.items():
        if not (name.startswith('Props') or name.startswith('Landmarks') or name.startswith('TunnelRocks') or name.startswith('Glow')):
            continue
        for comp in components(faces):
            if len(comp) >= 4: pieces.append((name, np.array(comp)))
    boxes = np.array([np.concatenate([V[c].min(0) - 0.3, V[c].max(0) + 0.3]) for _, c in pieces])
    parent = list(range(len(pieces)))
    def find(a):
        while parent[a] != a:
            parent[a] = parent[parent[a]]; a = parent[a]
        return a
    cell = 8.0; grid = {}
    for i, b in enumerate(boxes):
        for gx in range(int(b[0] // cell), int(b[3] // cell) + 1):
            for gz in range(int(b[2] // cell), int(b[5] // cell) + 1):
                grid.setdefault((gx, gz), []).append(i)
    for lst in grid.values():
        for a in range(len(lst)):
            for b2 in range(a + 1, len(lst)):
                i, j = lst[a], lst[b2]
                bi, bj = boxes[i], boxes[j]
                if (bi[:3] <= bj[3:]).all() and (bj[:3] <= bi[3:]).all():
                    parent[find(i)] = find(j)
    assemblies = {}
    for i in range(len(pieces)): assemblies.setdefault(find(i), []).append(i)
    for members in assemblies.values():
        if True:
            name = pieces[members[0]][0]
            P = V[np.concatenate([pieces[m][1] for m in members])]
            checked += 1
            lo = P[np.argmin(P[:, 1])]
            # distance of every vertex to the nearest road sample (xz) - vectorised in chunks
            sub = P[:: max(1, len(P) // 400)]
            d2 = ((sub[:, None, 0] - allP[None, :, 0]) ** 2 + (sub[:, None, 2] - allP[None, :, 2]) ** 2)
            j = np.argmin(d2, axis=1)
            dist = np.sqrt(d2[np.arange(len(sub)), j])
            inside = (dist < allW[j] - 0.3) & (sub[:, 1] > allP[j, 1] - 0.5) & (sub[:, 1] < allP[j, 1] + 4.0)
            if inside.any():
                k = int(np.argmax(inside))
                intrude.append((name, sub[k].round(1).tolist(), allN[j[k]], round(float(allW[j[k]] - dist[k]), 1)))
            # floating: lowest point vs terrain and nearby road decks
            ground = float(terrain(lo[0], lo[2]))
            dl = ((allP[:, 0] - lo[0]) ** 2 + (allP[:, 2] - lo[2]) ** 2)
            jn = int(np.argmin(dl))
            on_road = np.sqrt(dl[jn]) < allW[jn] + 3.0 and abs(lo[1] - allP[jn, 1]) < 2.0
            if lo[1] - ground > 0.6 and not on_road:
                floating.append((name, lo.round(1).tolist(), round(lo[1] - ground, 1), len(P)))
    print(f"{tr['id']}: {checked} prop assemblies ({len(pieces)} pieces) checked, {len(floating)} floating, {len(intrude)} intruding into a road")
    for f in floating[:25]: print('  FLOAT', f)
    for f in intrude[:25]: print('  ROAD ', f)
    sys.exit(1 if floating or intrude else 0)


if __name__ == '__main__':
    main()
