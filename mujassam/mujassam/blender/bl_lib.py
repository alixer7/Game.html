# -----------------------------------------------------------------------------
# Mujassam Blender helper library.
#
# This file runs INSIDE Blender (bpy). It is read as text by the host side and
# prepended to every generated build script, so the scripts are self-contained:
# you can paste any generated script into Blender's Text Editor and run it.
#
# Only the standard library + bpy/bmesh/mathutils may be imported here.
# Tested against Blender 4.2 LTS .. 5.x.
# -----------------------------------------------------------------------------
import bpy
import bmesh
import json
import math
import os
import sys
import traceback
from mathutils import Vector, Euler, Matrix

MJ_VERSION = "1.0"

_STATE = {
    "materials": {},
    "objects": {},      # id -> object
    "errors": [],       # [{"id":..., "error":...}]
    "root": None,
    "origin": None,
}

NAMED_COLORS = {
    "white": (1.0, 1.0, 1.0), "black": (0.02, 0.02, 0.02), "gray": (0.5, 0.5, 0.5),
    "grey": (0.5, 0.5, 0.5), "light_gray": (0.8, 0.8, 0.8), "dark_gray": (0.2, 0.2, 0.2),
    "red": (0.85, 0.1, 0.1), "dark_red": (0.45, 0.05, 0.05), "green": (0.15, 0.65, 0.2),
    "dark_green": (0.05, 0.3, 0.08), "blue": (0.1, 0.3, 0.85), "navy": (0.05, 0.08, 0.35),
    "sky_blue": (0.45, 0.7, 0.95), "yellow": (0.95, 0.85, 0.1), "gold": (0.83, 0.65, 0.2),
    "orange": (0.95, 0.5, 0.1), "brown": (0.45, 0.28, 0.12), "dark_brown": (0.25, 0.14, 0.06),
    "wood": (0.55, 0.36, 0.2), "beige": (0.9, 0.82, 0.65), "cream": (0.98, 0.94, 0.82),
    "pink": (0.95, 0.55, 0.7), "purple": (0.5, 0.2, 0.7), "violet": (0.6, 0.35, 0.85),
    "cyan": (0.1, 0.8, 0.85), "teal": (0.05, 0.5, 0.5), "silver": (0.75, 0.75, 0.78),
    "skin": (0.92, 0.72, 0.6), "tan": (0.82, 0.68, 0.5), "olive": (0.5, 0.5, 0.15),
}


# ----------------------------------------------------------------------------- utils
def _srgb_to_linear(c):
    return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4


def parse_color(value, default=(0.8, 0.8, 0.8)):
    """'#RRGGBB' | 'name' | [r,g,b] (0..1, sRGB) -> linear RGB tuple."""
    rgb = default
    try:
        if isinstance(value, str):
            v = value.strip().lower()
            if v.startswith("#") and len(v) in (4, 7):
                if len(v) == 4:
                    v = "#" + "".join(ch * 2 for ch in v[1:])
                rgb = tuple(int(v[i:i + 2], 16) / 255.0 for i in (1, 3, 5))
            elif v.replace(" ", "_") in NAMED_COLORS:
                rgb = NAMED_COLORS[v.replace(" ", "_")]
        elif isinstance(value, (list, tuple)) and len(value) >= 3:
            rgb = tuple(max(0.0, min(1.0, float(x))) for x in value[:3])
    except Exception:
        rgb = default
    return tuple(_srgb_to_linear(c) for c in rgb)


def _set_input(node, names, value):
    for n in names:
        if n in node.inputs:
            try:
                node.inputs[n].default_value = value
                return True
            except Exception:
                pass
    return False


def _link(obj, collection=None):
    (collection or bpy.context.scene.collection).objects.link(obj)
    return obj


def _mesh_object(name, bm):
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    me.update()
    return _link(bpy.data.objects.new(name, me))


def _set_smooth(obj, smooth=True):
    if obj.type != "MESH":
        return
    me = obj.data
    vals = [bool(smooth)] * len(me.polygons)
    if vals:
        me.polygons.foreach_set("use_smooth", vals)
    me.update()


# ----------------------------------------------------------------------------- scene
def reset_scene():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    _STATE["materials"].clear()
    _STATE["objects"].clear()
    _STATE["errors"].clear()
    root = bpy.data.objects.new("MJ_Root", None)
    _link(root)
    origin = bpy.data.objects.new("MJ_MirrorOrigin", None)
    _link(origin)
    origin.parent = root
    _STATE["root"] = root
    _STATE["origin"] = origin
    sc = bpy.context.scene
    sc.unit_settings.system = "METRIC"
    sc.unit_settings.scale_length = 1.0


def make_material(name, color="#cccccc", roughness=0.5, metallic=0.0, emission=None,
                  emission_strength=0.0, alpha=1.0, transmission=0.0, vertex_color=False):
    mat = bpy.data.materials.new(name)
    try:
        mat.use_nodes = True
    except Exception:
        pass
    rgb = parse_color(color)
    mat.diffuse_color = (rgb[0], rgb[1], rgb[2], float(alpha))
    nt = mat.node_tree
    bsdf = None
    for n in nt.nodes:
        if n.type == "BSDF_PRINCIPLED":
            bsdf = n
            break
    if bsdf is None:
        bsdf = nt.nodes.new("ShaderNodeBsdfPrincipled")
        out = next((n for n in nt.nodes if n.type == "OUTPUT_MATERIAL"), None) or \
            nt.nodes.new("ShaderNodeOutputMaterial")
        nt.links.new(bsdf.outputs[0], out.inputs[0])
    _set_input(bsdf, ["Base Color"], (rgb[0], rgb[1], rgb[2], 1.0))
    _set_input(bsdf, ["Roughness"], float(roughness))
    _set_input(bsdf, ["Metallic"], float(metallic))
    _set_input(bsdf, ["Alpha"], float(alpha))
    _set_input(bsdf, ["Transmission Weight", "Transmission"], float(transmission))
    if emission is not None and emission_strength > 0:
        e = parse_color(emission)
        _set_input(bsdf, ["Emission Color", "Emission"], (e[0], e[1], e[2], 1.0))
        _set_input(bsdf, ["Emission Strength"], float(emission_strength))
    if alpha < 1.0 or transmission > 0:
        for attr, val in (("surface_render_method", "BLENDED"), ("blend_method", "BLEND")):
            try:
                setattr(mat, attr, val)
            except Exception:
                pass
    if vertex_color:
        try:
            ca = nt.nodes.new("ShaderNodeVertexColor")
            ca.layer_name = ""
            nt.links.new(ca.outputs["Color"], bsdf.inputs["Base Color"])
        except Exception:
            pass
    _STATE["materials"][name] = mat
    return mat


def get_material(name):
    if not name:
        return None
    if name not in _STATE["materials"]:
        make_material(name, color=name if name.lower() in NAMED_COLORS else "#bfbfbf")
    return _STATE["materials"][name]


def assign_material(obj, mat):
    if mat is None or obj.type not in ("MESH", "CURVE", "FONT"):
        return
    obj.data.materials.clear()
    obj.data.materials.append(mat)


# ----------------------------------------------------------------------------- primitives
def box(name, size=(1, 1, 1)):
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    sx, sy, sz = [max(1e-5, float(s)) for s in size]
    for v in bm.verts:
        v.co = Vector((v.co.x * sx, v.co.y * sy, v.co.z * sz))
    return _mesh_object(name, bm)


def plane(name, size=(1, 1)):
    bm = bmesh.new()
    sx, sy = float(size[0]) / 2, float(size[1]) / 2
    vs = [bm.verts.new(p) for p in ((-sx, -sy, 0), (sx, -sy, 0), (sx, sy, 0), (-sx, sy, 0))]
    bm.faces.new(vs)
    return _mesh_object(name, bm)


def sphere(name, radius=0.5, segments=32, rings=16):
    bm = bmesh.new()
    bmesh.ops.create_uvsphere(bm, u_segments=int(segments), v_segments=int(rings), radius=float(radius))
    obj = _mesh_object(name, bm)
    _set_smooth(obj, True)
    return obj


def cylinder(name, radius=0.5, depth=1.0, segments=32, radius_top=None):
    bm = bmesh.new()
    r2 = float(radius if radius_top is None else radius_top)
    bmesh.ops.create_cone(bm, cap_ends=True, cap_tris=False, segments=int(segments),
                          radius1=float(radius), radius2=max(0.0, r2), depth=float(depth))
    return _mesh_object(name, bm)


def cone(name, radius=0.5, depth=1.0, segments=32, radius_top=0.0):
    return cylinder(name, radius=radius, depth=depth, segments=segments, radius_top=radius_top)


def torus(name, major_radius=0.5, minor_radius=0.15, major_segments=48, minor_segments=16):
    bm = bmesh.new()
    R, r = float(major_radius), float(minor_radius)
    M, m = int(major_segments), int(minor_segments)
    rows = []
    for i in range(M):
        a = 2 * math.pi * i / M
        ring = []
        for j in range(m):
            b = 2 * math.pi * j / m
            x = (R + r * math.cos(b)) * math.cos(a)
            y = (R + r * math.cos(b)) * math.sin(a)
            z = r * math.sin(b)
            ring.append(bm.verts.new((x, y, z)))
        rows.append(ring)
    for i in range(M):
        for j in range(m):
            a, b = rows[i][j], rows[(i + 1) % M][j]
            c, d = rows[(i + 1) % M][(j + 1) % m], rows[i][(j + 1) % m]
            bm.faces.new((a, b, c, d))
    obj = _mesh_object(name, bm)
    _set_smooth(obj, True)
    return obj


def lathe(name, profile, segments=32, angle=360.0):
    """Revolve a 2D profile [[radius, z], ...] around the local Z axis (vases, bottles, columns)."""
    pts = [(max(0.0, float(p[0])), float(p[1])) for p in profile]
    if len(pts) < 2:
        raise ValueError("lathe profile needs >= 2 points")
    segs = int(segments)
    full = abs(float(angle) - 360.0) < 1e-6
    n_cols = segs if full else segs + 1
    bm = bmesh.new()
    eps = 1e-6
    cols = []
    for k, (r, z) in enumerate(pts):
        if r < eps:
            cols.append([bm.verts.new((0.0, 0.0, z))] * n_cols)
            continue
        ring = []
        for i in range(n_cols):
            a = math.radians(float(angle)) * i / segs
            ring.append(bm.verts.new((r * math.cos(a), r * math.sin(a), z)))
        cols.append(ring)
    for k in range(len(pts) - 1):
        A, B = cols[k], cols[k + 1]
        rng = segs if full else segs
        for i in range(rng):
            i2 = (i + 1) % n_cols if full else i + 1
            quad = [A[i], A[i2], B[i2], B[i]]
            uniq = []
            for v in quad:
                if v not in uniq:
                    uniq.append(v)
            if len(uniq) >= 3:
                try:
                    bm.faces.new(uniq)
                except ValueError:
                    pass
    if full:
        for k in (0, len(pts) - 1):
            if pts[k][0] >= eps:
                ring = cols[k] if k == 0 else list(reversed(cols[k]))
                try:
                    bm.faces.new(ring)
                except ValueError:
                    pass
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
    obj = _mesh_object(name, bm)
    _set_smooth(obj, True)
    return obj


def capsule(name, radius=0.25, depth=1.0, segments=24):
    r, h = float(radius), max(0.0, float(depth) - 2 * float(radius))
    prof = [(0.0, -h / 2 - r)]
    steps = 8
    for i in range(1, steps + 1):
        a = -math.pi / 2 + (math.pi / 2) * i / steps
        prof.append((r * math.cos(a), -h / 2 + r * math.sin(a)))
    for i in range(0, steps):
        a = (math.pi / 2) * i / steps
        prof.append((r * math.cos(a), h / 2 + r * math.sin(a)))
    prof.append((0.0, h / 2 + r))
    return lathe(name, prof, segments=segments)


def extrude(name, polygon, depth=0.1):
    """Extrude a closed 2D polygon [[x, y], ...] along local Z, centered on z=0."""
    pts = [(float(p[0]), float(p[1])) for p in polygon]
    if len(pts) < 3:
        raise ValueError("extrude polygon needs >= 3 points")
    area = sum(pts[i][0] * pts[(i + 1) % len(pts)][1] - pts[(i + 1) % len(pts)][0] * pts[i][1]
               for i in range(len(pts)))
    if area < 0:
        pts = list(reversed(pts))
    d = float(depth) / 2
    bm = bmesh.new()
    bot = [bm.verts.new((x, y, -d)) for x, y in pts]
    top = [bm.verts.new((x, y, d)) for x, y in pts]
    bm.faces.new(list(reversed(bot)))
    bm.faces.new(top)
    n = len(pts)
    for i in range(n):
        j = (i + 1) % n
        bm.faces.new((bot[i], bot[j], top[j], top[i]))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
    return _mesh_object(name, bm)


def _curve_to_mesh_object(name, curve_obj):
    deps = bpy.context.evaluated_depsgraph_get()
    ev = curve_obj.evaluated_get(deps)
    me = bpy.data.meshes.new_from_object(ev)
    me.name = name
    mats = list(curve_obj.data.materials)
    bpy.data.objects.remove(curve_obj, do_unlink=True)
    obj = _link(bpy.data.objects.new(name, me))
    for m in mats:
        obj.data.materials.append(m)
    return obj


def tube(name, path, radius=0.05, radius_end=None, segments=12, smooth_path=True, caps=True):
    """Sweep a circle along a 3D path [[x,y,z], ...] (branches, pipes, handles, tails, cables)."""
    pts = [Vector([float(c) for c in p[:3]]) for p in path]
    if len(pts) < 2:
        raise ValueError("tube path needs >= 2 points")
    cu = bpy.data.curves.new(name + "_curve", type="CURVE")
    cu.dimensions = "3D"
    cu.bevel_depth = float(radius)
    cu.bevel_resolution = max(1, int(segments) // 4)
    cu.resolution_u = 8 if smooth_path else 1
    try:
        cu.use_fill_caps = bool(caps)
    except Exception:
        pass
    r_end = float(radius if radius_end is None else radius_end) / max(1e-6, float(radius))
    n = len(pts)
    if smooth_path and n > 2:
        sp = cu.splines.new("BEZIER")
        sp.bezier_points.add(n - 1)
        for i, p in enumerate(pts):
            bp = sp.bezier_points[i]
            bp.co = p
            bp.handle_left_type = bp.handle_right_type = "AUTO"
            bp.radius = 1.0 + (r_end - 1.0) * i / (n - 1)
    else:
        sp = cu.splines.new("POLY")
        sp.points.add(n - 1)
        for i, p in enumerate(pts):
            sp.points[i].co = (p.x, p.y, p.z, 1.0)
            sp.points[i].radius = 1.0 + (r_end - 1.0) * i / (n - 1)
    cobj = _link(bpy.data.objects.new(name + "_c", cu))
    obj = _curve_to_mesh_object(name, cobj)
    _set_smooth(obj, True)
    return obj


def skin(name, nodes, edges=None, subdiv=2, smooth=True):
    """Organic shape from a skeleton: nodes [[x,y,z,radius], ...], edges [[i,j], ...].

    Great for creatures, characters, limbs, tree trunks, roots, blobs.
    If edges are omitted the nodes are connected as a chain.
    """
    nodes = [[float(c) for c in n] for n in nodes]
    if len(nodes) < 2:
        raise ValueError("skin needs >= 2 nodes")
    if not edges:
        edges = [[i, i + 1] for i in range(len(nodes) - 1)]
    me = bpy.data.meshes.new(name)
    me.from_pydata([tuple(n[:3]) for n in nodes], [tuple(int(i) for i in e) for e in edges], [])
    me.update()
    obj = _link(bpy.data.objects.new(name, me))
    mod = obj.modifiers.new("Skin", "SKIN")
    try:
        mod.use_smooth_shade = bool(smooth)
    except Exception:
        pass
    if len(me.skin_vertices) == 0:
        me.skin_vertices.new()
    layer = me.skin_vertices[0].data
    for i, n in enumerate(nodes):
        r = max(1e-4, n[3] if len(n) > 3 else 0.1)
        layer[i].radius = (r, r)
        layer[i].use_root = (i == 0)
    if subdiv and int(subdiv) > 0:
        ss = obj.modifiers.new("SkinSubdiv", "SUBSURF")
        ss.levels = int(subdiv)
        ss.render_levels = int(subdiv)
    return obj


def text3d(name, body="Text", size=0.3, depth=0.05, align="CENTER"):
    cu = bpy.data.curves.new(name + "_font", type="FONT")
    cu.body = str(body)
    cu.size = float(size)
    cu.extrude = float(depth) / 2
    try:
        cu.align_x = align
        cu.align_y = "CENTER"
    except Exception:
        pass
    cobj = _link(bpy.data.objects.new(name + "_c", cu))
    return _curve_to_mesh_object(name, cobj)


def import_mesh_file(name, path, target_size=None, size_axis="max", keep_largest=0.02,
                     merge_distance=0.0005, max_faces=60000, rotation_fix=(0, 0, 0)):
    """Import a reconstructed mesh (glb/gltf/obj/ply/stl), clean it up, normalise it.

    Cleanup: merge by distance, drop tiny floating islands (< keep_largest of the face
    count), decimate to max_faces, center on XY, put on the ground (z=0) and scale so the
    chosen dimension equals target_size (metres).
    """
    before = set(bpy.data.objects)
    ext = os.path.splitext(path)[1].lower()
    if ext in (".glb", ".gltf"):
        bpy.ops.import_scene.gltf(filepath=path)
    elif ext == ".obj":
        bpy.ops.wm.obj_import(filepath=path)
    elif ext == ".ply":
        bpy.ops.wm.ply_import(filepath=path)
    elif ext == ".stl":
        bpy.ops.wm.stl_import(filepath=path)
    else:
        raise ValueError("unsupported mesh format: " + ext)
    new = [o for o in bpy.data.objects if o not in before]
    meshes = [o for o in new if o.type == "MESH"]
    if not meshes:
        raise ValueError("no mesh found in " + path)
    bm = bmesh.new()
    for o in meshes:
        tmp = o.data.copy()
        tmp.transform(o.matrix_world)
        bm.from_mesh(tmp)
        bpy.data.meshes.remove(tmp)
    rf = Euler([math.radians(float(a)) for a in rotation_fix], "XYZ").to_matrix().to_4x4()
    bmesh.ops.transform(bm, matrix=rf, verts=bm.verts[:])
    if merge_distance:
        bmesh.ops.remove_doubles(bm, verts=bm.verts[:], dist=float(merge_distance))
    # remove small islands (floaters)
    bm.faces.ensure_lookup_table()
    seen, islands = set(), []
    for f in bm.faces:
        if f.index in seen:
            continue
        stack, isl = [f], []
        seen.add(f.index)
        while stack:
            cur = stack.pop()
            isl.append(cur)
            for e in cur.edges:
                for nf in e.link_faces:
                    if nf.index not in seen:
                        seen.add(nf.index)
                        stack.append(nf)
        islands.append(isl)
    if islands:
        biggest = max(len(i) for i in islands)
        kill = [f for isl in islands if len(isl) < keep_largest * biggest for f in isl]
        if kill:
            bmesh.ops.delete(bm, geom=kill, context="FACES")
    loose = [v for v in bm.verts if not v.link_faces]
    if loose:
        bmesh.ops.delete(bm, geom=loose, context="VERTS")
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    # carry vertex colours across if the first mesh had them
    src = meshes[0].data
    for o in new:
        bpy.data.objects.remove(o, do_unlink=True)
    obj = _link(bpy.data.objects.new(name, me))
    if len(me.polygons) > max_faces:
        dec = obj.modifiers.new("Decimate", "DECIMATE")
        dec.ratio = max(0.01, float(max_faces) / len(me.polygons))
        _apply_all_modifiers(obj)
    # normalise
    xs = [v.co.x for v in me.vertices]; ys = [v.co.y for v in me.vertices]; zs = [v.co.z for v in me.vertices]
    cx, cy, mz = (min(xs) + max(xs)) / 2, (min(ys) + max(ys)) / 2, min(zs)
    dims = (max(xs) - min(xs), max(ys) - min(ys), max(zs) - min(zs))
    ref = {"x": dims[0], "y": dims[1], "z": dims[2], "height": dims[2]}.get(size_axis, max(dims))
    s = float(target_size) / ref if (target_size and ref > 1e-9) else 1.0
    me.transform(Matrix.Diagonal((s, s, s, 1.0)) @ Matrix.Translation((-cx, -cy, -mz)))
    me.update()
    _set_smooth(obj, True)
    has_colors = bool(getattr(me, "color_attributes", None)) and len(me.color_attributes) > 0
    obj["mj_has_vertex_colors"] = has_colors
    return obj


def _apply_all_modifiers(obj):
    deps = bpy.context.evaluated_depsgraph_get()
    ev = obj.evaluated_get(deps)
    me = bpy.data.meshes.new_from_object(ev)
    old = obj.data
    obj.modifiers.clear()
    obj.data = me
    if old.users == 0:
        bpy.data.meshes.remove(old)


# ----------------------------------------------------------------------------- modifiers
def add_bevel(obj, width=0.01, segments=2):
    m = obj.modifiers.new("Bevel", "BEVEL")
    m.width = float(width)
    m.segments = int(segments)
    m.limit_method = "ANGLE"
    try:
        m.harden_normals = False
    except Exception:
        pass
    return m


def add_mirror(obj, axes="x"):
    m = obj.modifiers.new("Mirror", "MIRROR")
    axes = axes if isinstance(axes, (list, tuple)) else [axes]
    axes = [str(a).lower() for a in axes]
    m.use_axis[0] = "x" in axes
    m.use_axis[1] = "y" in axes
    m.use_axis[2] = "z" in axes
    m.mirror_object = _STATE["origin"]
    m.use_clip = False
    m.use_mirror_merge = True
    return m


def add_array(obj, count=2, offset=(1, 0, 0)):
    m = obj.modifiers.new("Array", "ARRAY")
    m.count = int(count)
    m.use_relative_offset = False
    m.use_constant_offset = True
    m.constant_offset_displace = [float(c) for c in offset]
    return m


def add_subdivision(obj, levels=1):
    m = obj.modifiers.new("Subdivision", "SUBSURF")
    m.levels = int(levels)
    m.render_levels = int(levels)
    return m


def add_solidify(obj, thickness=0.01):
    m = obj.modifiers.new("Solidify", "SOLIDIFY")
    m.thickness = float(thickness)
    return m


def add_boolean(obj, cutter, op="DIFFERENCE"):
    m = obj.modifiers.new("Bool_" + cutter.name, "BOOLEAN")
    m.operation = op
    m.object = cutter
    try:
        m.solver = "EXACT"
    except Exception:
        pass
    return m


# ----------------------------------------------------------------------------- spec builder
_BUILDERS = {
    "box": lambda pid, p: box(pid, p.get("size", (1, 1, 1))),
    "cube": lambda pid, p: box(pid, p.get("size", (1, 1, 1))),
    "plane": lambda pid, p: plane(pid, p.get("size", (1, 1))),
    "sphere": lambda pid, p: sphere(pid, p.get("radius", 0.5), p.get("segments", 32), p.get("rings", 16)),
    "cylinder": lambda pid, p: cylinder(pid, p.get("radius", 0.5), p.get("depth", 1.0),
                                        p.get("segments", 32), p.get("radius_top")),
    "cone": lambda pid, p: cone(pid, p.get("radius", 0.5), p.get("depth", 1.0),
                                p.get("segments", 32), p.get("radius_top", 0.0)),
    "torus": lambda pid, p: torus(pid, p.get("major_radius", 0.5), p.get("minor_radius", 0.15),
                                  p.get("major_segments", 48), p.get("minor_segments", 16)),
    "capsule": lambda pid, p: capsule(pid, p.get("radius", 0.25), p.get("depth", 1.0), p.get("segments", 24)),
    "lathe": lambda pid, p: lathe(pid, p["profile"], p.get("segments", 32), p.get("angle", 360.0)),
    "extrude": lambda pid, p: extrude(pid, p["polygon"], p.get("depth", 0.1)),
    "tube": lambda pid, p: tube(pid, p["path"], p.get("radius", 0.05), p.get("radius_end"),
                                p.get("segments", 12), p.get("smooth_path", True)),
    "skin": lambda pid, p: skin(pid, p["nodes"], p.get("edges"), p.get("subdiv", 2)),
    "text": lambda pid, p: text3d(pid, p.get("body", "Text"), p.get("size", 0.3), p.get("depth", 0.05)),
    "mesh_file": lambda pid, p: import_mesh_file(pid, p["path"], p.get("target_size"),
                                                 p.get("size_axis", "max"), max_faces=p.get("max_faces", 60000),
                                                 rotation_fix=p.get("rotation_fix", (0, 0, 0))),
}


def _toposort(parts):
    ids = {p["id"] for p in parts}
    done, order, temp = set(), [], set()
    by_id = {p["id"]: p for p in parts}

    def visit(pid):
        if pid in done:
            return
        if pid in temp:
            raise ValueError("parent cycle at " + pid)
        temp.add(pid)
        par = by_id[pid].get("parent")
        if par and par in ids:
            visit(par)
        temp.discard(pid)
        done.add(pid)
        order.append(by_id[pid])

    for p in parts:
        visit(p["id"])
    return order


def build_part(p):
    pid = p["id"]
    t = p.get("type", "box")
    if t not in _BUILDERS:
        raise ValueError("unknown part type '%s'" % t)
    obj = _BUILDERS[t](pid, p)
    obj.name = pid
    obj["mj_type"] = t
    if p.get("cutter"):
        obj["mj_cutter"] = True
    sc = p.get("scale")
    if sc is not None:
        obj.scale = Vector([float(s) for s in sc])
    obj.rotation_euler = Euler([math.radians(float(a)) for a in p.get("rotation", (0, 0, 0))], "XYZ")
    obj.location = Vector([float(c) for c in p.get("location", (0, 0, 0))])
    # material
    if t == "mesh_file" and obj.get("mj_has_vertex_colors") and not p.get("material"):
        assign_material(obj, make_material(pid + "_vcol", vertex_color=True, roughness=0.7))
    else:
        assign_material(obj, get_material(p.get("material")))
    # modifiers (order matters)
    if p.get("bevel"):
        add_bevel(obj, p["bevel"], p.get("bevel_segments", 2))
    if p.get("solidify"):
        add_solidify(obj, p["solidify"])
    if p.get("mirror"):
        add_mirror(obj, p["mirror"])
    arr = p.get("array")
    if arr:
        add_array(obj, arr.get("count", 2), arr.get("offset", (1, 0, 0)))
    if p.get("subdiv"):
        if t != "skin":
            add_subdivision(obj, p["subdiv"])
    if "smooth" in p and obj.type == "MESH":
        _set_smooth(obj, bool(p["smooth"]))
    return obj


def build_spec(spec):
    reset_scene()
    for name, m in (spec.get("materials") or {}).items():
        make_material(name, color=m.get("color", "#cccccc"), roughness=m.get("roughness", 0.5),
                      metallic=m.get("metallic", 0.0), emission=m.get("emission"),
                      emission_strength=m.get("emission_strength", 0.0), alpha=m.get("alpha", 1.0),
                      transmission=m.get("transmission", 0.0))
    parts = _toposort(list(spec.get("parts") or []))
    objs = _STATE["objects"]
    for p in parts:
        try:
            obj = build_part(p)
            objs[p["id"]] = obj
        except Exception as e:  # keep going: the critic gets the error message
            _STATE["errors"].append({"id": p.get("id"), "error": "%s: %s" % (type(e).__name__, e)})
    # parenting (location of a child is relative to its parent)
    for p in parts:
        obj = objs.get(p["id"])
        if obj is None:
            continue
        par = objs.get(p.get("parent")) if p.get("parent") else None
        obj.parent = par if par is not None else _STATE["root"]
    # booleans
    for p in parts:
        obj = objs.get(p["id"])
        for cid in (p.get("cutters") or []):
            cut = objs.get(cid)
            if obj is not None and cut is not None:
                add_boolean(obj, cut, "DIFFERENCE")
    for o in objs.values():
        if o.get("mj_cutter"):
            o.hide_render = True
            o.hide_set(True)
            o.display_type = "WIRE"
    bpy.context.view_layer.update()
    if spec.get("auto_ground", True):
        ground_model()
    return objs


def export_objects():
    return [o for o in _STATE["objects"].values() if o.type == "MESH" and not o.get("mj_cutter")]


def model_bounds(objs=None):
    objs = export_objects() if objs is None else objs
    deps = bpy.context.evaluated_depsgraph_get()
    lo = Vector((1e18, 1e18, 1e18)); hi = Vector((-1e18, -1e18, -1e18))
    any_v = False
    for o in objs:
        ev = o.evaluated_get(deps)
        me = ev.to_mesh()
        mw = ev.matrix_world
        for v in me.vertices:
            w = mw @ v.co
            lo = Vector((min(lo.x, w.x), min(lo.y, w.y), min(lo.z, w.z)))
            hi = Vector((max(hi.x, w.x), max(hi.y, w.y), max(hi.z, w.z)))
            any_v = True
        ev.to_mesh_clear()
    if not any_v:
        return Vector((0, 0, 0)), Vector((0, 0, 0))
    return lo, hi


def ground_model():
    lo, hi = model_bounds()
    if hi.x < lo.x:
        return
    root = _STATE["root"]
    root.location.z -= lo.z
    bpy.context.view_layer.update()


# ----------------------------------------------------------------------------- stats
def _mesh_stats(me):
    bm = bmesh.new()
    bm.from_mesh(me)
    non_manifold = sum(1 for e in bm.edges if not e.is_manifold)
    bm.free()
    return non_manifold


def collect_stats():
    deps = bpy.context.evaluated_depsgraph_get()
    parts, total_f, total_v = {}, 0, 0
    for pid, o in _STATE["objects"].items():
        if o.type != "MESH":
            continue
        ev = o.evaluated_get(deps)
        me = ev.to_mesh()
        mw = ev.matrix_world
        if len(me.vertices):
            ws = [mw @ v.co for v in me.vertices]
            lo = [min(w[i] for w in ws) for i in range(3)]
            hi = [max(w[i] for w in ws) for i in range(3)]
        else:
            lo = hi = [0.0, 0.0, 0.0]
        nf, nv = len(me.polygons), len(me.vertices)
        nm = _mesh_stats(me) if nf < 200000 else -1
        ev.to_mesh_clear()
        cutter = bool(o.get("mj_cutter"))
        parts[pid] = {"type": o.get("mj_type", "?"), "faces": nf, "verts": nv,
                      "bbox_min": [round(x, 4) for x in lo], "bbox_max": [round(x, 4) for x in hi],
                      "non_manifold_edges": nm, "cutter": cutter}
        if not cutter:
            total_f += nf
            total_v += nv
    lo, hi = model_bounds()
    return {"version": MJ_VERSION, "blender": bpy.app.version_string,
            "faces": total_f, "verts": total_v, "parts": parts, "errors": list(_STATE["errors"]),
            "bbox_min": [round(x, 4) for x in lo], "bbox_max": [round(x, 4) for x in hi],
            "dimensions": [round(hi[i] - lo[i], 4) for i in range(3)]}


# ----------------------------------------------------------------------------- export & render
def export_glb(path):
    os.makedirs(os.path.dirname(os.path.abspath(path)), exist_ok=True)
    bpy.ops.object.select_all(action="DESELECT")
    objs = export_objects()
    for o in objs:
        o.hide_set(False)
        o.select_set(True)
    if not objs:
        raise RuntimeError("nothing to export")
    bpy.context.view_layer.objects.active = objs[0]
    kw = dict(filepath=path, export_format="GLB", use_selection=True, export_apply=True)
    try:
        bpy.ops.export_scene.gltf(**kw)
    except TypeError:
        kw.pop("use_selection")
        bpy.ops.export_scene.gltf(**kw)


def save_blend(path):
    os.makedirs(os.path.dirname(os.path.abspath(path)), exist_ok=True)
    bpy.ops.wm.save_as_mainfile(filepath=os.path.abspath(path), check_existing=False)


VIEWS = [("front", 0.0, 12.0), ("right", 90.0, 12.0), ("back_left", 225.0, 25.0), ("top_front_right", 45.0, 45.0)]


def _setup_render(res, samples, engine):
    sc = bpy.context.scene
    sc.render.resolution_x = sc.render.resolution_y = int(res)
    sc.render.resolution_percentage = 100
    sc.render.image_settings.file_format = "PNG"
    sc.render.film_transparent = False
    try:
        sc.view_settings.view_transform = "Standard"
    except Exception:
        pass
    sc.render.engine = engine
    if engine == "CYCLES":
        sc.cycles.device = "CPU"
        sc.cycles.samples = int(samples)
        sc.cycles.use_adaptive_sampling = True
        sc.cycles.max_bounces = 4
        try:
            sc.cycles.use_denoising = True
        except Exception:
            pass
    world = bpy.data.worlds.new("MJ_World")
    sc.world = world
    try:
        world.use_nodes = True
        bg = world.node_tree.nodes.get("Background")
        bg.inputs[0].default_value = (0.78, 0.8, 0.84, 1.0)
        bg.inputs[1].default_value = 0.9
    except Exception:
        world.color = (0.78, 0.8, 0.84)
    sun = bpy.data.objects.new("MJ_Sun", bpy.data.lights.new("MJ_Sun", "SUN"))
    sun.data.energy = 3.0
    try:
        sun.data.angle = math.radians(8)
    except Exception:
        pass
    sun.rotation_euler = Euler((math.radians(50), math.radians(10), math.radians(-35)), "XYZ")
    _link(sun)


def _add_floor(lo, hi):
    size = max(hi.x - lo.x, hi.y - lo.y, hi.z - lo.z, 0.1) * 8
    fl = plane("MJ_Floor", (size, size))
    fl.location = Vector(((lo.x + hi.x) / 2, (lo.y + hi.y) / 2, lo.z - 1e-4))
    assign_material(fl, make_material("MJ_FloorMat", color=(0.66, 0.67, 0.7), roughness=0.9))
    return fl


def render_views(out_dir, res=384, samples=16, engine="CYCLES", views=None, floor=True):
    os.makedirs(out_dir, exist_ok=True)
    _setup_render(res, samples, engine)
    lo, hi = model_bounds()
    center = (lo + hi) / 2
    radius = max((hi - lo).length / 2, 1e-3)
    if floor:
        _add_floor(lo, hi)
    cam_data = bpy.data.cameras.new("MJ_Cam")
    cam_data.lens = 50
    cam = _link(bpy.data.objects.new("MJ_Cam", cam_data))
    cam_data.clip_start = radius * 0.01
    cam_data.clip_end = radius * 100
    bpy.context.scene.camera = cam
    fov = 2 * math.atan(cam_data.sensor_width / (2 * cam_data.lens))
    dist = radius / math.sin(fov / 2) * 1.08
    paths = []
    for name, az, el in (views or VIEWS):
        a, e = math.radians(az), math.radians(el)
        offs = Vector((math.sin(a) * math.cos(e), -math.cos(a) * math.cos(e), math.sin(e))) * dist
        cam.location = center + offs
        cam.rotation_euler = (center - cam.location).to_track_quat("-Z", "Y").to_euler()
        p = os.path.join(out_dir, "%s.png" % name)
        bpy.context.scene.render.filepath = p
        bpy.ops.render.render(write_still=True)
        paths.append(p)
    return paths


def run_job(spec, out):
    """Full job used by the host: build -> stats -> export -> (blend) -> render."""
    status = {"ok": False}
    try:
        if spec is not None:
            build_spec(spec)
        else:
            finish_freeform()
        stats = collect_stats()
        status.update(stats)
        if out.get("glb"):
            export_glb(out["glb"])
        if out.get("blend"):
            save_blend(out["blend"])
        if out.get("renders_dir"):
            status["renders"] = render_views(out["renders_dir"], out.get("res", 384), out.get("samples", 16),
                                             out.get("engine", "CYCLES"), floor=out.get("floor", True))
        status["ok"] = True
    except Exception as e:
        status["fatal"] = "%s: %s" % (type(e).__name__, e)
        status["traceback"] = traceback.format_exc()
    if out.get("stats"):
        with open(out["stats"], "w") as f:
            json.dump(status, f, indent=1)
    return status


# ----------------------------------------------------------------------------- freeform API
def begin_freeform():
    reset_scene()


def register(obj, pid=None):
    """Freeform scripts call register(obj) for every object that belongs to the model."""
    pid = pid or obj.name
    _STATE["objects"][pid] = obj
    if obj.parent is None:
        obj.parent = _STATE["root"]
    return obj


def finish_freeform():
    # pick up any mesh objects the script created but did not register
    for o in bpy.data.objects:
        if o.type == "MESH" and o.name not in _STATE["objects"] and not o.name.startswith("MJ_"):
            _STATE["objects"][o.name] = o
            if o.parent is None:
                o.parent = _STATE["root"]
    bpy.context.view_layer.update()
    ground_model()
