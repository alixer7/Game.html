"""Design-review plots: top-down map (elevation coloured, edges, gaps, shortcuts, pads, hazards) + profiles."""
import math
import numpy as np
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
from matplotlib.collections import PolyCollection
from matplotlib import cm

SURF_COL = {"stone": "#b89a6a", "dirt": "#9a6b3c", "wood": "#7a4a22", "metal": "#7c8a96", "asphalt": "#3a3550",
            "ice": "#a8e4ff", "snow": "#e8f2ff", "basalt": "#5a3020", "wet_stone": "#6d7a70", "grating": "#5f7f7a",
            "sand": "#e2c486", "neon": "#5a2a8a", "glass": "#7fe0ff", "mud": "#5a3f22", "cobble": "#a08060"}


def plot_track(T, out, terrain=None, scatter=None, title=None):
    S = T.S
    n = len(S["d"])
    fig = plt.figure(figsize=(20, 11))
    ax = fig.add_axes([0.03, 0.05, 0.55, 0.9])
    if terrain is not None:
        H, ox, oz, cell = terrain
        ext = [ox, ox + H.shape[1] * cell, -(oz + H.shape[0] * cell), -oz]
        ax.imshow(H, extent=ext, cmap="terrain", alpha=0.55, origin="upper")
    polys, cols, order = [], [], np.argsort(S["y"])
    ymin, ymax = S["y"].min(), S["y"].max()
    for i in order:
        a = S["attrs"][i]
        if a["gap"]:
            continue
        j = (i + 1) % n
        hw_i, hw_j = S["w"][i] / 2, S["w"][j] / 2
        pi, pj, ri, rj = S["pos"][i], S["pos"][j], S["right"][i], S["right"][j]
        q = [(pi[0] - ri[0] * hw_i, -(pi[2] - ri[2] * hw_i)), (pi[0] + ri[0] * hw_i, -(pi[2] + ri[2] * hw_i)),
             (pj[0] + rj[0] * hw_j, -(pj[2] + rj[2] * hw_j)), (pj[0] - rj[0] * hw_j, -(pj[2] - rj[2] * hw_j))]
        polys.append(q)
        c = np.array(matplotlib.colors.to_rgb(SURF_COL.get(a["surf"], "#999999")))
        shade = 0.55 + 0.45 * (S["y"][i] - ymin) / max(1e-6, ymax - ymin)
        cols.append(np.clip(c * shade, 0, 1))
    ax.add_collection(PolyCollection(polys, facecolors=cols, edgecolors="none", zorder=2))
    # edges
    for i in range(0, n, 2):
        a = S["attrs"][i]
        if a["gap"]:
            continue
        for side, key in ((-1, "edge_l"), (1, "edge_r")):
            et = a[key]
            p = S["pos"][i] + S["right"][i] * side * S["w"][i] / 2
            col = {"wall": "k", "fence": "#7a4a22", "rail": "#888888", "open": "r", "shoulder": "g", "halfpipe": "b",
                   "cliff": "#553311", "none": None}.get(et)
            if col:
                ax.plot(p[0], -p[2], ".", ms=1.6, color=col, zorder=3)
        if a["ceil"] > 0:
            ax.plot(S["pos"][i][0], -S["pos"][i][2], "s", ms=2.2, color="#222222", alpha=0.35, zorder=3)
    ax.plot(S["x"], -S["z"], "-", lw=0.3, color="k", zorder=4)
    for k in range(0, n, max(1, int(100 / T.step))):
        ax.text(S["x"][k], -S["z"][k], f"{S['d'][k]:.0f}", fontsize=6, color="navy", zorder=6)
    for sc in T.shortcuts_world:
        ax.annotate("", xy=(sc["tx"], -sc["tz"]), xytext=(sc["lx"], -sc["lz"]),
                    arrowprops=dict(arrowstyle="->", color="red", lw=2.2), zorder=7)
        ax.text(sc["lx"], -sc["lz"], sc["id"], fontsize=7, color="red", zorder=8)
        for pl in sc["plats"]:
            ax.add_patch(plt.Circle((pl["x"], -pl["z"]), pl["r"], color="orange", alpha=0.7, zorder=7))
    for pd in T.feat["pads"]:
        p, *_ = T.frame_at(pd["d"], pd["lat"])
        ax.plot(p[0], -p[2], "o", ms=6, color="cyan" if pd["super"] else "orange", mec="k", zorder=8)
    for hz in T.feat["hazards"]:
        p, *_ = T.frame_at(hz["d"], hz["lat"])
        ax.plot(p[0], -p[2], "x", ms=8, mew=2, color="magenta", zorder=8)
    for ob in T.feat["obstacles"]:
        p, *_ = T.frame_at(ob["d"], ob["lat"])
        ax.plot(p[0], -p[2], "^", ms=5, color="purple", zorder=8)
    if scatter:
        for kind, pts in scatter.items():
            if not pts:
                continue
            arr = np.array([[p[0], p[2]] for p in pts])
            ax.plot(arr[:, 0], -arr[:, 1], ".", ms=1.0, alpha=0.5, zorder=1)
    ax.plot(S["x"][0], -S["z"][0], "g*", ms=20, zorder=9)
    ax.set_aspect("equal")
    ax.autoscale()
    ax.grid(alpha=0.25)
    v = T.validation
    ax.set_title(title or f"{T.name_en}  L={v['length']} m  rmin={v['min_radius']}  y={v['y_range']}  w={v['width_range']}  overlaps={v['overlaps']}")
    # profiles
    ax2 = fig.add_axes([0.62, 0.55, 0.36, 0.4])
    ax2.plot(S["d"], S["y"], "k-", lw=1.2, label="elevation")
    gaps = np.array([a["gap"] for a in S["attrs"]])
    ax2.plot(S["d"][gaps], S["y"][gaps], "r.", ms=3, label="gap")
    ceil = np.array([a["ceil"] for a in S["attrs"]])
    ax2.fill_between(S["d"], S["y"], S["y"] + ceil, where=ceil > 0, color="gray", alpha=0.3, label="indoor")
    prev = None
    for i, a in enumerate(S["attrs"]):
        if a["zone"] != prev:
            ax2.axvline(S["d"][i], color="gray", lw=0.4)
            ax2.text(S["d"][i], ax2.get_ylim()[1], a["zone"][:22], rotation=90, fontsize=6, va="top")
            prev = a["zone"]
    ax2.legend(fontsize=7)
    ax2.grid(alpha=0.3)
    ax3 = fig.add_axes([0.62, 0.07, 0.36, 0.4])
    ax3.plot(S["d"], S["w"], "b-", label="width")
    ax3.plot(S["d"], S["bank"], "g-", label="bank")
    r = np.where(np.abs(S["curv"]) > 1e-4, 1.0 / np.abs(S["curv"]), np.nan)
    ax3.plot(S["d"], np.clip(r, 0, 120) / 2, "r-", lw=0.6, label="radius/2 (<=120)")
    ax3.legend(fontsize=7)
    ax3.grid(alpha=0.3)
    fig.savefig(out, dpi=72)
    plt.close(fig)
    return out
