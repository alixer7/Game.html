"""Package the Godot project into independent zip parts (each < LIMIT MB) - extract all parts into ONE folder.
python3 tools/package_parts.py <out_dir> [limit_mb]
"""
import os
import sys
import zipfile

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
SKIP_DIRS = {".godot", "__pycache__", "results", "export", ".import"}


def main(out_dir, limit_mb=9.0):
    limit = limit_mb * 1024 * 1024
    files = []
    for dp, dns, fns in os.walk(ROOT):
        dns[:] = [d for d in dns if d not in SKIP_DIRS and not d.startswith(".git")]
        for fn in fns:
            p = os.path.join(dp, fn)
            files.append((os.path.relpath(p, ROOT), os.path.getsize(p)))
    files.sort(key=lambda f: f[0])
    os.makedirs(out_dir, exist_ok=True)
    parts, cur, cur_size = [], [], 0
    for rel, size in files:
        if cur and cur_size + size > limit:
            parts.append(cur)
            cur, cur_size = [], 0
        cur.append(rel)
        cur_size += size
    if cur:
        parts.append(cur)
    names = []
    for k, part in enumerate(parts, 1):
        name = os.path.join(out_dir, f"NitroFuryRacing_v8_part{k}_of_{len(parts)}.zip")
        with zipfile.ZipFile(name, "w", zipfile.ZIP_DEFLATED, compresslevel=9) as z:
            for rel in part:
                z.write(os.path.join(ROOT, rel), rel)
        names.append((name, os.path.getsize(name), len(part)))
    for n, s, c in names:
        print(f"{os.path.basename(n)}  {s / 1e6:.2f} MB  {c} files")


if __name__ == "__main__":
    main(sys.argv[1], float(sys.argv[2]) if len(sys.argv) > 2 else 9.0)
