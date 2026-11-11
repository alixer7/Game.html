#!/usr/bin/env python3
"""Renders Tools/HeadlessShim ExportKarts output (karts.obj) with the same WebGL toon approximation.
usage: render_karts.py karts.obj out_prefix 'cam;target;fov|cam;target;fov...'   (cam/target as x,y,z)"""
import base64, json, os, sys
import numpy as np
sys.path.insert(0, __file__.rsplit('/', 1)[0])
from webgl_render import HTML, THEMES
from render_obj import load

def main():
    V, C, F, NV = load(sys.argv[1], normals=True)
    theme = dict(THEMES['beach']); theme['hor'] = [0.78, 0.86, 0.95]; theme['fs'] = 500; theme['fe'] = 900
    e = base64.b64encode(np.zeros(0, np.float32).tobytes()).decode()
    html = HTML.replace('%POS%', base64.b64encode(V.astype(np.float32).tobytes()).decode()) \
        .replace('%COL%', base64.b64encode((np.clip(C, 0, 1) * 255).astype(np.uint8).tobytes()).decode()) \
        .replace('%IDX%', base64.b64encode(F.astype(np.uint32).tobytes()).decode()) \
        .replace('%NRM%', base64.b64encode(NV.astype(np.float32).tobytes()).decode()) \
        .replace('%THEME%', json.dumps(theme)).replace('%FPOS%', e).replace('%FCOL%', e).replace('%FUV%', e).replace('%FIDX%', e) \
        .replace('%TEX%', '').replace('%TW%', '0').replace('%TH%', '0')
    out_html = os.path.join(os.path.dirname(os.path.abspath(sys.argv[2])), 'render_k.html')
    open(out_html, 'w').write(html)
    from playwright.sync_api import sync_playwright
    with sync_playwright() as p:
        b = p.chromium.launch(executable_path=os.environ.get('PW_CHROMIUM') or None, args=['--use-gl=angle', '--use-angle=swiftshader', '--enable-unsafe-swiftshader', '--ignore-gpu-blocklist'])
        pg = b.new_page(viewport={'width': 1280, 'height': 720})
        pg.goto('file://' + out_html)
        for k, spec in enumerate(sys.argv[3].split('|')):
            cam, tgt, fov = spec.split(';')
            cam = [float(x) for x in cam.split(',')]; tgt = [float(x) for x in tgt.split(',')]
            pg.evaluate(f"draw({json.dumps(cam)}, {json.dumps(tgt)}, {float(fov)}, false)")
            pg.screenshot(path=f"{sys.argv[2]}_{k}.png")
        b.close()

if __name__ == '__main__':
    main()
