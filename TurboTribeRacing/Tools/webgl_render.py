#!/usr/bin/env python3
"""Accurate z-buffered preview of exported track OBJs using WebGL in headless Chromium (Playwright).
Mimics the game's ToonVC shader (wrap lighting + soft band + custom fog) and Unity's clockwise
front faces with back-face culling, so wrong winding shows up as missing surfaces.
Usage: python3 webgl_render.py <obj> <track.json> <out_prefix> [views: d@back@height@ahead,...]
Foliage cards are read from <obj without .obj>_foliage.obj + foliage_WxH.rgba next to it (alpha-tested).
"""
import base64, json, math, sys
import numpy as np
sys.path.insert(0, __file__.rsplit('/', 1)[0])
sys.path.insert(0, __file__.rsplit('/', 1)[0] + '/trackgen')
from preview import build as build_spline, mods_for
from render_obj import load
import os, glob

THEMES = {
    'beach': dict(sky=[0.18, 0.55, 0.94], hor=[0.66, 0.89, 1.0], fog=[0.75, 0.92, 1.0], fs=90, fe=420, sun=[0.45, 0.75, 0.48], amb=[0.5, 0.66, 0.79], ambg=[0.55, 0.48, 0.37]),
    'canyon': dict(sky=[0.23, 0.48, 0.85], hor=[1.0, 0.83, 0.63], fog=[0.95, 0.79, 0.63], fs=110, fe=480, sun=[-0.6, 0.64, 0.42], amb=[0.62, 0.65, 0.77], ambg=[0.63, 0.35, 0.23]),
    'snow': dict(sky=[0.24, 0.37, 0.72], hor=[0.81, 0.89, 1.0], fog=[0.86, 0.92, 1.0], fs=70, fe=380, sun=[-0.42, 0.53, -0.73], amb=[0.65, 0.72, 0.88], ambg=[0.5, 0.56, 0.69]),
}

HTML = """<html><body style="margin:0;background:#000"><canvas id=c width=1280 height=720></canvas><script>
const gl = document.getElementById('c').getContext('webgl2', {antialias:true});
function b64(s, T){ const bin = atob(s); const u = new Uint8Array(bin.length); for(let i=0;i<bin.length;i++) u[i]=bin.charCodeAt(i); return new T(u.buffer); }
const P = b64('%POS%', Float32Array), C = b64('%COL%', Uint8Array), I = b64('%IDX%', Uint32Array), NN = b64('%NRM%', Float32Array);
const T = %THEME%;
const FP = b64('%FPOS%', Float32Array), FC = b64('%FCOL%', Uint8Array), FU = b64('%FUV%', Float32Array), FI = b64('%FIDX%', Uint32Array), TX = b64('%TEX%', Uint8Array);
const TW = %TW%, TH = %TH%;
const vs = `#version 300 es
in vec3 p; in vec3 c; in vec3 nn; uniform mat4 vp; out vec3 vc; out vec3 wp; out vec3 vn;
void main(){ vc=c; wp=p; vn=nn; gl_Position = vp*vec4(p,1.0); }`;
const fs = `#version 300 es
precision highp float; in vec3 vc; in vec3 wp; in vec3 vn; uniform vec3 cam, sun, fogc, amb, ambg; uniform vec2 fogr; out vec4 o;
void main(){ vec3 n = normalize(cross(dFdx(wp), dFdy(wp))); n = -n; // flat normal (Unity/left-handed screen)
 if (dot(n, cam-wp) < 0.0) n = -n;
 if (dot(vn, vn) > 0.25) { vec3 s = normalize(vn); if (dot(s, n) > -0.2) n = s; } // smooth vertex normal when exported
 float ndl = dot(n, normalize(sun)); float wrap = clamp(ndl*0.5+0.5,0.0,1.0); float band = smoothstep(0.42,0.58,wrap);
 float diff = mix(wrap*0.55, 0.75+wrap*0.25, band); vec3 a = mix(ambg, amb, n.y*0.5+0.5);
 vec3 col = vc*(vec3(1.0,0.97,0.9)*1.05*diff*0.82 + a*0.42);
 float f = clamp((distance(cam,wp)-fogr.x)/(fogr.y-fogr.x),0.0,1.0); col = mix(col, fogc, f*f*(3.0-2.0*f));
 o = vec4(col,1.0); }`;
const vs2 = `#version 300 es
in vec3 p; in vec3 c; in vec2 uv; uniform mat4 vp; out vec3 vc; out vec3 wp; out vec2 tc;
void main(){ vc=c; wp=p; tc=uv; gl_Position = vp*vec4(p,1.0); }`;
const fs2 = `#version 300 es
precision highp float; in vec3 vc; in vec3 wp; in vec2 tc; uniform sampler2D tex; uniform vec3 cam, sun, fogc, amb, ambg; uniform vec2 fogr; out vec4 o;
void main(){ vec4 t = texture(tex, tc); if (t.a < 0.45) discard;
 float wrap = 0.75; vec3 col = t.rgb*vc*(vec3(1.0,0.97,0.9)*1.05*wrap*0.82 + mix(ambg,amb,0.8)*0.42);
 float f = clamp((distance(cam,wp)-fogr.x)/(fogr.y-fogr.x),0.0,1.0); col = mix(col, fogc, f*f*(3.0-2.0*f));
 o = vec4(col,1.0); }`;
function sh(t,s){const x=gl.createShader(t);gl.shaderSource(x,s);gl.compileShader(x);if(!gl.getShaderParameter(x,gl.COMPILE_STATUS))throw gl.getShaderInfoLog(x);return x;}
const pr = gl.createProgram(); gl.attachShader(pr, sh(gl.VERTEX_SHADER,vs)); gl.attachShader(pr, sh(gl.FRAGMENT_SHADER,fs)); gl.linkProgram(pr); gl.useProgram(pr);
function buf(data, loc, n, type, norm){ const b=gl.createBuffer(); gl.bindBuffer(gl.ARRAY_BUFFER,b); gl.bufferData(gl.ARRAY_BUFFER,data,gl.STATIC_DRAW); const l=gl.getAttribLocation(pr,loc); gl.enableVertexAttribArray(l); gl.vertexAttribPointer(l,n,type,norm,0,0); }
const vao1 = gl.createVertexArray(); gl.bindVertexArray(vao1);
buf(P,'p',3,gl.FLOAT,false); buf(C,'c',3,gl.UNSIGNED_BYTE,true); buf(NN.length ? NN : new Float32Array(P.length),'nn',3,gl.FLOAT,false);
const ib=gl.createBuffer(); gl.bindBuffer(gl.ELEMENT_ARRAY_BUFFER,ib); gl.bufferData(gl.ELEMENT_ARRAY_BUFFER,I,gl.STATIC_DRAW);
const pr2 = gl.createProgram(); gl.attachShader(pr2, sh(gl.VERTEX_SHADER,vs2)); gl.attachShader(pr2, sh(gl.FRAGMENT_SHADER,fs2)); gl.linkProgram(pr2);
const vao2 = gl.createVertexArray(); gl.bindVertexArray(vao2);
function buf2(data, loc, n, type, norm){ const b=gl.createBuffer(); gl.bindBuffer(gl.ARRAY_BUFFER,b); gl.bufferData(gl.ARRAY_BUFFER,data,gl.STATIC_DRAW); const l=gl.getAttribLocation(pr2,loc); if(l<0) return; gl.enableVertexAttribArray(l); gl.vertexAttribPointer(l,n,type,norm,0,0); }
buf2(FP,'p',3,gl.FLOAT,false); buf2(FC,'c',3,gl.UNSIGNED_BYTE,true); buf2(FU,'uv',2,gl.FLOAT,false);
const ib2=gl.createBuffer(); gl.bindBuffer(gl.ELEMENT_ARRAY_BUFFER,ib2); gl.bufferData(gl.ELEMENT_ARRAY_BUFFER,FI,gl.STATIC_DRAW);
const tex = gl.createTexture(); gl.bindTexture(gl.TEXTURE_2D, tex);
if (TW > 0) { gl.texImage2D(gl.TEXTURE_2D,0,gl.RGBA,TW,TH,0,gl.RGBA,gl.UNSIGNED_BYTE,TX); gl.generateMipmap(gl.TEXTURE_2D); }
gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.LINEAR_MIPMAP_LINEAR);
gl.enable(gl.DEPTH_TEST); gl.enable(gl.CULL_FACE); gl.cullFace(gl.BACK); gl.frontFace(gl.CW);
function norm(v){const l=Math.hypot(...v);return v.map(x=>x/l);} function cross(a,b){return [a[1]*b[2]-a[2]*b[1],a[2]*b[0]-a[0]*b[2],a[0]*b[1]-a[1]*b[0]];}
function dot(a,b){return a[0]*b[0]+a[1]*b[1]+a[2]*b[2];}
window.draw = function(cam, tgt, fov, nofog){
  const f = norm([tgt[0]-cam[0],tgt[1]-cam[1],tgt[2]-cam[2]]); const r = norm(cross([0,1,0],f)); const u = cross(f,r);
  const near=0.3, far=6000, t=1/Math.tan(fov*Math.PI/360), asp=1280/720;
  // view: x=right, y=up, z=forward (left-handed, same as NDC); perspective with depth into +z
  const A=(far+near)/(far-near), B=-2*far*near/(far-near);
  const tx=-dot(r,cam), ty=-dot(u,cam), tz=-dot(f,cam);
  const m = [ r[0]*t/asp, u[0]*t, f[0]*A, f[0],  r[1]*t/asp, u[1]*t, f[1]*A, f[1],  r[2]*t/asp, u[2]*t, f[2]*A, f[2],  tx*t/asp, ty*t, tz*A+B, tz ];
  gl.viewport(0,0,1280,720); gl.clearColor(T.hor[0],T.hor[1],T.hor[2],1); gl.clear(gl.COLOR_BUFFER_BIT|gl.DEPTH_BUFFER_BIT);
  for (const [prog, vao, n, cull] of [[pr, vao1, I.length, true], [pr2, vao2, FI.length, false]]) {
    if (n == 0) continue;
    gl.useProgram(prog); gl.bindVertexArray(vao);
    if (cull) gl.enable(gl.CULL_FACE); else gl.disable(gl.CULL_FACE);
    gl.uniformMatrix4fv(gl.getUniformLocation(prog,'vp'),false,new Float32Array(m));
    gl.uniform3fv(gl.getUniformLocation(prog,'cam'),cam); gl.uniform3fv(gl.getUniformLocation(prog,'sun'),T.sun);
    gl.uniform3fv(gl.getUniformLocation(prog,'fogc'),T.fog); gl.uniform3fv(gl.getUniformLocation(prog,'amb'),T.amb); gl.uniform3fv(gl.getUniformLocation(prog,'ambg'),T.ambg);
    gl.uniform2fv(gl.getUniformLocation(prog,'fogr'), nofog ? [5000, 9000] : [T.fs,T.fe]);
    gl.drawElements(gl.TRIANGLES, n, gl.UNSIGNED_INT, 0);
  }
  gl.finish(); return 'ok';
};
</script></body></html>"""

def main():
    V, C, F, NV = load(sys.argv[1], normals=True)
    tr = json.load(open(sys.argv[2]))
    prefix = sys.argv[3]
    theme = THEMES[tr.get('theme', 'beach')]
    ms = build_spline(tr['roads'][0]['points'], True, 1.0, mods=mods_for(tr, 'main'))
    pts = ms.pos; N = len(pts)
    base = sys.argv[1][:-4]
    FV = np.zeros((0, 3)); FCc = np.zeros((0, 3)); FUv = np.zeros((0, 2)); FF = np.zeros((0,), np.uint32); tw = th = 0; texb = b''
    if os.path.exists(base + '_foliage.obj'):
        vv, vt, ff = [], [], []
        for line in open(base + '_foliage.obj'):
            if line.startswith('v '): vv.append([float(x) for x in line.split()[1:7]])
            elif line.startswith('vt '): vt.append([float(x) for x in line.split()[1:3]])
            elif line.startswith('f '): ff.extend(int(x) - 1 for x in line.split()[1:4])
        if vv:
            vv = np.array(vv); FV = vv[:, :3]; FCc = vv[:, 3:6]; FUv = np.array(vt); FF = np.array(ff, np.uint32)
        atl = glob.glob(os.path.dirname(base) + '/foliage_*.rgba')
        if atl:
            tw, th = [int(x) for x in atl[0].rsplit('_', 1)[1][:-5].split('x')]
            texb = open(atl[0], 'rb').read()
    html = HTML.replace('%POS%', base64.b64encode(V.astype(np.float32).tobytes()).decode()) \
               .replace('%COL%', base64.b64encode((np.clip(C, 0, 1) * 255).astype(np.uint8).tobytes()).decode()) \
               .replace('%IDX%', base64.b64encode(F.astype(np.uint32).tobytes()).decode()) \
               .replace('%NRM%', base64.b64encode(NV.astype(np.float32).tobytes()).decode()) \
               .replace('%THEME%', json.dumps(theme)) \
               .replace('%FPOS%', base64.b64encode(FV.astype(np.float32).tobytes()).decode()) \
               .replace('%FCOL%', base64.b64encode((np.clip(FCc, 0, 1) * 255).astype(np.uint8).tobytes()).decode()) \
               .replace('%FUV%', base64.b64encode(FUv.astype(np.float32).tobytes()).decode()) \
               .replace('%FIDX%', base64.b64encode(FF.astype(np.uint32).tobytes()).decode()) \
               .replace('%TEX%', base64.b64encode(texb).decode()).replace('%TW%', str(tw)).replace('%TH%', str(th))
    open('/tmp/render.html', 'w').write(html)
    # views: comma list of "t" or "t@back@height@ahead" (control-point parameter, metres)
    specs = [[float(y) for y in x.split('@')] for x in sys.argv[4].split(',')] if len(sys.argv) > 4 else None
    views = [sp[0] for sp in specs] if specs else None
    from playwright.sync_api import sync_playwright
    with sync_playwright() as p:
        b = p.chromium.launch(executable_path=os.environ.get('PW_CHROMIUM') or None, args=['--use-gl=angle', '--use-angle=swiftshader', '--enable-unsafe-swiftshader', '--ignore-gpu-blocklist'])
        pg = b.new_page(viewport={'width': 1280, 'height': 720})
        pg.goto('file:///tmp/render.html')
        cams = []
        idxs = [N - 16, N // 5, 2 * N // 5, 3 * N // 5, 4 * N // 5] if views is None else [int(round(v / ms.step)) for v in views]
        for vi, i in enumerate(idxs):
            i %= N
            back, height, ahead = 6.2, 2.6, 16
            if specs and len(specs[vi]) > 1: back = specs[vi][1]
            if specs and len(specs[vi]) > 2: height = specs[vi][2]
            if specs and len(specs[vi]) > 3: ahead = int(specs[vi][3])
            a = pts[i, :3]; q = pts[(i + ahead) % N, :3]
            d = q - a; d[1] = 0; d /= np.linalg.norm(d)
            cams.append(((a - d * back + np.array([0, height, 0])).tolist(), (q + np.array([0, 1.0, 0])).tolist(), 62))
        c = (pts[:, :3].min(axis=0) + pts[:, :3].max(axis=0)) / 2; span = np.ptp(pts[:, [0, 2]], axis=0).max()
        cams.append(((c + np.array([span * 0.05, span * 0.95, -span * 0.55])).tolist(), c.tolist(), 52))
        for k, (cam, tgt, fov) in enumerate(cams):
            pg.evaluate(f"draw({json.dumps(cam)}, {json.dumps(tgt)}, {fov}, {'true' if k == len(cams) - 1 else 'false'})")
            pg.screenshot(path=f"{prefix}_{k}.png")
        b.close()

if __name__ == '__main__':
    main()
