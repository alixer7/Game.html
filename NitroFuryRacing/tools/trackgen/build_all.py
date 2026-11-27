"""Build every track: python3 build_all.py [names...]  -> res://data/tracks/<id>.json (+ terrain/scatter)."""
import os
import sys
import importlib
import warnings

warnings.filterwarnings("ignore")
HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
OUT = os.path.join(ROOT, "data", "tracks")
DOCS = os.path.join(ROOT, "docs", "tracks")

TRACKS = ["emerald", "biolab", "cosmic"]


def main(names):
    os.makedirs(OUT, exist_ok=True)
    os.makedirs(DOCS, exist_ok=True)
    from plot import plot_track
    try:
        import world
    except ImportError:
        world = None
    for name in names:
        try:
            mod = importlib.import_module("track_" + name)
        except ModuleNotFoundError:
            print("skip", name)
            continue
        T = mod.build()
        T.validate()
        extra = {}
        terrain = scatter = None
        if world is not None:
            extra, terrain, scatter = world.build_world(T, OUT)
        T.export(os.path.join(OUT, T.tid + ".json"), extra)
        plot_track(T, os.path.join(DOCS, T.tid + "_map.png"), terrain=terrain, scatter=scatter)
        print("exported", T.tid)


if __name__ == "__main__":
    sys.path.insert(0, HERE)
    main(sys.argv[1:] or TRACKS)
