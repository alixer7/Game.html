"""Quick design preview: python3 preview.py emerald [out.png]"""
import sys
import importlib
from plot import plot_track

name = sys.argv[1]
mod = importlib.import_module("track_" + name)
T = mod.build()
T.validate()
out = sys.argv[2] if len(sys.argv) > 2 else f"/tmp/preview_{name}.png"
plot_track(T, out)
print("closing len", round(T.closing_len,1), "turn", round(T.closing_turn,1), "open end (x,z,yaw,d)", T.open_end)
print(out)
