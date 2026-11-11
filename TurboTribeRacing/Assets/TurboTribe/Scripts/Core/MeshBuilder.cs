using System.Collections.Generic;
using UnityEngine;
using UnityEngine.Rendering;

namespace TurboTribe
{
    /// <summary>
    /// Procedural mesh helper. Everything in the game (track, karts, props) is built from these primitives
    /// with vertex colours, which keeps draw calls low and gives the chunky, saturated CTR-like look.
    /// </summary>
    public class MeshBuilder
    {
        public readonly List<Vector3> V = new List<Vector3>(1024);
        public readonly List<Vector3> N = new List<Vector3>(1024);
        public readonly List<Color32> C = new List<Color32>(1024);
        public readonly List<Vector2> U = new List<Vector2>(1024);
        public readonly List<int> T = new List<int>(2048);

        public int VertexCount { get { return V.Count; } }

        public void Clear() { V.Clear(); N.Clear(); C.Clear(); U.Clear(); T.Clear(); }

        public int AddVertex(Vector3 p, Vector3 n, Color c, Vector2 uv)
        {
            V.Add(p); N.Add(n); C.Add(c); U.Add(uv);
            return V.Count - 1;
        }

        public void AddTriangle(int a, int b, int c) { T.Add(a); T.Add(b); T.Add(c); }

        /// <summary>Quad a-b-c-d in clockwise order when viewed from the front (Unity winding).</summary>
        public void AddQuad(Vector3 a, Vector3 b, Vector3 c, Vector3 d, Color col, Vector2 uva, Vector2 uvb, Vector2 uvc, Vector2 uvd)
        {
            Vector3 n = Vector3.Cross(b - a, d - a).normalized;
            int i = AddVertex(a, n, col, uva);
            AddVertex(b, n, col, uvb);
            AddVertex(c, n, col, uvc);
            AddVertex(d, n, col, uvd);
            T.Add(i); T.Add(i + 1); T.Add(i + 2);
            T.Add(i); T.Add(i + 2); T.Add(i + 3);
        }

        public void AddQuad(Vector3 a, Vector3 b, Vector3 c, Vector3 d, Color col)
        {
            AddQuad(a, b, c, d, col, new Vector2(0, 0), new Vector2(0, 1), new Vector2(1, 1), new Vector2(1, 0));
        }

        public void AddTri(Vector3 a, Vector3 b, Vector3 c, Color col)
        {
            Vector3 n = Vector3.Cross(b - a, c - a).normalized;
            int i = AddVertex(a, n, col, Vector2.zero);
            AddVertex(b, n, col, Vector2.up);
            AddVertex(c, n, col, Vector2.one);
            T.Add(i); T.Add(i + 1); T.Add(i + 2);
        }

        /// <summary>Axis-aligned box in the local space of m (unit cube scaled by size, centred).</summary>
        public void AddBox(Matrix4x4 m, Vector3 size, Color col, float uvScale = 1f)
        {
            Vector3 h = size * 0.5f;
            Vector3[] p =
            {
                new Vector3(-h.x, -h.y, -h.z), new Vector3(h.x, -h.y, -h.z), new Vector3(h.x, h.y, -h.z), new Vector3(-h.x, h.y, -h.z),
                new Vector3(-h.x, -h.y, h.z), new Vector3(h.x, -h.y, h.z), new Vector3(h.x, h.y, h.z), new Vector3(-h.x, h.y, h.z)
            };
            for (int i = 0; i < 8; i++) p[i] = m.MultiplyPoint3x4(p[i]);
            Vector2 s = new Vector2(uvScale, uvScale);
            // front (-z), back (+z), left, right, top, bottom
            Face(p[0], p[3], p[2], p[1], col, s);
            Face(p[5], p[6], p[7], p[4], col, s);
            Face(p[4], p[7], p[3], p[0], col, s);
            Face(p[1], p[2], p[6], p[5], col, s);
            Face(p[3], p[7], p[6], p[2], col * 1.0f, s);
            Face(p[4], p[0], p[1], p[5], col * 0.8f, s);
        }

        void Face(Vector3 a, Vector3 b, Vector3 c, Vector3 d, Color col, Vector2 s)
        {
            col.a = 1f;
            AddQuad(a, b, c, d, col, new Vector2(0, 0), new Vector2(0, s.y), new Vector2(s.x, s.y), new Vector2(s.x, 0));
        }

        public void AddBox(Vector3 center, Vector3 size, Quaternion rot, Color col)
        {
            AddBox(Matrix4x4.TRS(center, rot, Vector3.one), size, col);
        }

        /// <summary>Cylinder / frustum along local +Y from y=0 to y=height.</summary>
        public void AddCylinder(Matrix4x4 m, float rBottom, float rTop, float height, int seg, Color col, bool caps = true, bool smooth = true, Color? topCol = null)
        {
            Color tc = topCol ?? col;
            int start = V.Count;
            for (int i = 0; i <= seg; i++)
            {
                float a = i / (float)seg * Mathf.PI * 2f;
                float cs = Mathf.Cos(a), sn = Mathf.Sin(a);
                Vector3 nrm = new Vector3(cs, (rBottom - rTop) / Mathf.Max(height, 0.001f), sn).normalized;
                Vector3 nW = m.MultiplyVector(nrm).normalized;
                AddVertex(m.MultiplyPoint3x4(new Vector3(cs * rBottom, 0, sn * rBottom)), nW, col, new Vector2(i / (float)seg, 0));
                AddVertex(m.MultiplyPoint3x4(new Vector3(cs * rTop, height, sn * rTop)), nW, tc, new Vector2(i / (float)seg, 1));
            }
            for (int i = 0; i < seg; i++)
            {
                int a = start + i * 2;
                T.Add(a); T.Add(a + 1); T.Add(a + 3);
                T.Add(a); T.Add(a + 3); T.Add(a + 2);
            }
            if (!smooth) { /* smooth normals are fine for the low-poly look */ }
            if (caps)
            {
                if (rTop > 0.001f) Disc(m, height, rTop, seg, tc, true);
                if (rBottom > 0.001f) Disc(m, 0, rBottom, seg, col * 0.8f, false);
            }
        }

        void Disc(Matrix4x4 m, float y, float r, int seg, Color col, bool up)
        {
            Vector3 n = m.MultiplyVector(up ? Vector3.up : Vector3.down).normalized;
            int c = AddVertex(m.MultiplyPoint3x4(new Vector3(0, y, 0)), n, col, new Vector2(0.5f, 0.5f));
            for (int i = 0; i <= seg; i++)
            {
                float a = i / (float)seg * Mathf.PI * 2f;
                AddVertex(m.MultiplyPoint3x4(new Vector3(Mathf.Cos(a) * r, y, Mathf.Sin(a) * r)), n, col,
                    new Vector2(0.5f + Mathf.Cos(a) * 0.5f, 0.5f + Mathf.Sin(a) * 0.5f));
            }
            for (int i = 0; i < seg; i++)
            {
                if (up) { T.Add(c); T.Add(c + i + 2); T.Add(c + i + 1); }
                else { T.Add(c); T.Add(c + i + 1); T.Add(c + i + 2); }
            }
        }

        public void AddCone(Matrix4x4 m, float r, float h, int seg, Color col, Color tipCol)
        {
            AddCylinder(m, r, 0.0001f, h, seg, col, true, true, tipCol);
        }

        /// <summary>UV sphere (ellipsoid via matrix scale). Optional vertical colour gradient.</summary>
        public void AddSphere(Matrix4x4 m, float r, int lat, int lon, Color col, Color? bottomCol = null)
        {
            Color bc = bottomCol ?? col;
            int start = V.Count;
            for (int y = 0; y <= lat; y++)
            {
                float v = y / (float)lat;
                float phi = v * Mathf.PI;
                for (int x = 0; x <= lon; x++)
                {
                    float u = x / (float)lon;
                    float th = u * Mathf.PI * 2f;
                    Vector3 n = new Vector3(Mathf.Sin(phi) * Mathf.Cos(th), Mathf.Cos(phi), Mathf.Sin(phi) * Mathf.Sin(th));
                    Color c = Color.Lerp(col, bc, v);
                    AddVertex(m.MultiplyPoint3x4(n * r), m.MultiplyVector(n).normalized, c, new Vector2(u, 1 - v));
                }
            }
            int row = lon + 1;
            for (int y = 0; y < lat; y++)
                for (int x = 0; x < lon; x++)
                {
                    int a = start + y * row + x;
                    T.Add(a); T.Add(a + 1); T.Add(a + row + 1);
                    T.Add(a); T.Add(a + row + 1); T.Add(a + row);
                }
        }

        /// <summary>Low-poly faceted rock: a sphere with jittered vertices and flat shading.</summary>
        public void AddRock(Matrix4x4 m, float r, Color col, Rng rng, int lat = 4, int lon = 6)
        {
            var pts = new Vector3[(lat + 1) * (lon + 1)];
            for (int y = 0; y <= lat; y++)
                for (int x = 0; x <= lon; x++)
                {
                    float phi = y / (float)lat * Mathf.PI, th = (x % lon) / (float)lon * Mathf.PI * 2f;
                    Vector3 n = new Vector3(Mathf.Sin(phi) * Mathf.Cos(th), Mathf.Cos(phi), Mathf.Sin(phi) * Mathf.Sin(th));
                    float j = (y == 0 || y == lat) ? 1f : rng.Range(0.75f, 1.15f);
                    pts[y * (lon + 1) + x] = n * r * j;
                }
            for (int y = 0; y <= lat; y++) pts[y * (lon + 1) + lon] = pts[y * (lon + 1)];
            for (int y = 0; y < lat; y++)
                for (int x = 0; x < lon; x++)
                {
                    Vector3 a = m.MultiplyPoint3x4(pts[y * (lon + 1) + x]);
                    Vector3 b = m.MultiplyPoint3x4(pts[y * (lon + 1) + x + 1]);
                    Vector3 c = m.MultiplyPoint3x4(pts[(y + 1) * (lon + 1) + x + 1]);
                    Vector3 d = m.MultiplyPoint3x4(pts[(y + 1) * (lon + 1) + x]);
                    Color cc = rng.Jitter(col, 0.05f);
                    AddTri(a, b, c, cc);
                    AddTri(a, c, d, cc);
                }
        }

        // ================================================================ smooth primitives (v2)

        /// <summary>Area-weighted smooth normals for a vertex/triangle range (shared vertices within the range).</summary>
        public void SmoothNormals(int v0, int t0)
        {
            int vc = V.Count - v0;
            var acc = new Vector3[vc];
            for (int t = t0; t < T.Count; t += 3)
            {
                int a = T[t], b = T[t + 1], c = T[t + 2];
                if (a < v0 || b < v0 || c < v0) continue;
                Vector3 n = Vector3.Cross(V[b] - V[a], V[c] - V[a]);
                acc[a - v0] += n; acc[b - v0] += n; acc[c - v0] += n;
            }
            for (int i = 0; i < vc; i++) { Vector3 n = acc[i]; N[v0 + i] = n.sqrMagnitude > 1e-12f ? n.normalized : Vector3.up; }
        }

        /// <summary>Grid of (rows x cols) vertices -> quads; vertices must already be added row-major starting at 'start'.</summary>
        void GridTris(int start, int rows, int cols, bool flip = false)
        {
            for (int r = 0; r < rows - 1; r++)
                for (int c = 0; c < cols - 1; c++)
                {
                    int a = start + r * cols + c, b = a + cols, cc = b + 1, d = a + 1;
                    if (!flip) { T.Add(a); T.Add(b); T.Add(cc); T.Add(a); T.Add(cc); T.Add(d); }
                    else { T.Add(a); T.Add(cc); T.Add(b); T.Add(a); T.Add(d); T.Add(cc); }
                }
        }

        public struct LoftSection
        {
            public float Z, W, H, Y, Power, X;
            public Color Col;
            public LoftSection(float z, float w, float h, float y, Color col, float power = 3f, float x = 0f) { Z = z; W = w; H = h; Y = y; Col = col; Power = power; X = x; }
        }

        /// <summary>
        /// Lofts superellipse cross-sections along +Z (local), giving smooth organic / car-body shapes.
        /// Power 2 = ellipse, 3-5 = rounded rectangle. Caps close the ends.
        /// </summary>
        public void AddLoft(Matrix4x4 m, LoftSection[] secs, int around, bool caps = true)
        {
            int v0 = V.Count, t0 = T.Count;
            int cols = around + 1;
            for (int si = 0; si < secs.Length; si++)
            {
                var sc = secs[si];
                for (int k = 0; k <= around; k++)
                {
                    float a = k / (float)around * Mathf.PI * 2f;
                    float c = Mathf.Cos(a), sn = Mathf.Sin(a);
                    float e = 2f / Mathf.Max(sc.Power, 0.5f);
                    float x = Mathf.Sign(c) * Mathf.Pow(Mathf.Abs(c), e) * sc.W + sc.X;
                    float y = Mathf.Sign(sn) * Mathf.Pow(Mathf.Abs(sn), e) * sc.H + sc.Y;
                    AddVertex(m.MultiplyPoint3x4(new Vector3(x, y, sc.Z)), Vector3.up, sc.Col, new Vector2(k / (float)around, si / (float)(secs.Length - 1)));
                }
            }
            // rings go counter-clockwise seen from +Z; quads (ring i -> i+1) face outward with this order
            for (int r = 0; r < secs.Length - 1; r++)
                for (int k = 0; k < around; k++)
                {
                    int a = v0 + r * cols + k, b = a + 1, c = a + cols + 1, d = a + cols;
                    T.Add(a); T.Add(b); T.Add(c); T.Add(a); T.Add(c); T.Add(d);
                }
            SmoothNormals(v0, t0);
            if (caps)
            {
                CapRing(m, secs[0], around, v0, false);
                CapRing(m, secs[secs.Length - 1], around, v0 + (secs.Length - 1) * cols, true);
            }
        }

        void CapRing(Matrix4x4 m, LoftSection sc, int around, int ringStart, bool front)
        {
            Vector3 n = m.MultiplyVector(front ? Vector3.forward : Vector3.back).normalized;
            int c = AddVertex(m.MultiplyPoint3x4(new Vector3(sc.X, sc.Y, sc.Z)), n, sc.Col * 0.92f, new Vector2(0.5f, 0.5f));
            int start = V.Count;
            for (int k = 0; k <= around; k++) AddVertex(V[ringStart + k], n, sc.Col * 0.92f, Vector2.zero);
            for (int k = 0; k < around; k++)
            {
                if (front) { T.Add(c); T.Add(start + k); T.Add(start + k + 1); }
                else { T.Add(c); T.Add(start + k + 1); T.Add(start + k); }
            }
        }

        /// <summary>Box with rounded edges/corners (radius r), smooth shaded.</summary>
        public void AddRoundedBox(Matrix4x4 m, Vector3 size, float r, Color col, int seg = 3, Color? topCol = null)
        {
            Vector3 h = size * 0.5f;
            r = Mathf.Min(r, Mathf.Min(h.x, Mathf.Min(h.y, h.z)) * 0.98f);
            Vector3 inner = h - Vector3.one * r;
            int n = seg * 2 + 1;
            Vector3[] faceN = { Vector3.right, Vector3.left, Vector3.up, Vector3.down, Vector3.forward, Vector3.back };
            for (int f = 0; f < 6; f++)
            {
                Vector3 fn = faceN[f];
                Vector3 u = Mathf.Abs(fn.y) > 0.5f ? Vector3.right : Vector3.up;
                Vector3 v = Vector3.Cross(fn, u);
                int start = V.Count;
                for (int i = 0; i < n; i++)
                    for (int j = 0; j < n; j++)
                    {
                        float a = i / (float)(n - 1) * 2f - 1f, b = j / (float)(n - 1) * 2f - 1f;
                        // concentrate vertices near the edges where the rounding happens
                        a = Mathf.Sign(a) * Mathf.Pow(Mathf.Abs(a), 0.6f); b = Mathf.Sign(b) * Mathf.Pow(Mathf.Abs(b), 0.6f);
                        Vector3 q = fn + u * a + v * b;              // point on unit cube surface
                        Vector3 p = new Vector3(q.x * h.x, q.y * h.y, q.z * h.z);
                        Vector3 cl = new Vector3(Mathf.Clamp(p.x, -inner.x, inner.x), Mathf.Clamp(p.y, -inner.y, inner.y), Mathf.Clamp(p.z, -inner.z, inner.z));
                        Vector3 dir = p - cl;
                        Vector3 nn = dir.sqrMagnitude > 1e-8f ? dir.normalized : fn;
                        Vector3 pos = cl + nn * r;
                        Color c = (topCol.HasValue && nn.y > 0.5f) ? topCol.Value : col;
                        if (nn.y < -0.3f) c *= 0.85f;
                        c.a = 1f;
                        AddVertex(m.MultiplyPoint3x4(pos), m.MultiplyVector(nn).normalized, c, new Vector2(a, b));
                    }
                // orientation: u x v = fn ; grid rows along u -> pick winding so the face points outward
                for (int i = 0; i < n - 1; i++)
                    for (int j = 0; j < n - 1; j++)
                    {
                        int a0 = start + i * n + j, a1 = a0 + n, a2 = a1 + 1, a3 = a0 + 1;
                        T.Add(a0); T.Add(a2); T.Add(a3); T.Add(a0); T.Add(a1); T.Add(a2);
                    }
            }
        }

        /// <summary>Surface of revolution around local +Y from a (radius, height) profile (bottom to top).</summary>
        public void AddLathe(Matrix4x4 m, Vector2[] profile, int seg, Color[] cols, bool smooth = true)
        {
            int v0 = V.Count, t0 = T.Count;
            int cols2 = seg + 1;
            for (int i = 0; i < profile.Length; i++)
                for (int k = 0; k <= seg; k++)
                {
                    float a = k / (float)seg * Mathf.PI * 2f;
                    Vector3 p = new Vector3(Mathf.Cos(a) * profile[i].x, profile[i].y, Mathf.Sin(a) * profile[i].x);
                    Color c = cols[Mathf.Min(i, cols.Length - 1)]; c.a = 1f;
                    AddVertex(m.MultiplyPoint3x4(p), Vector3.up, c, new Vector2(k / (float)seg, i / (float)(profile.Length - 1)));
                }
            for (int i = 0; i < profile.Length - 1; i++)
                for (int k = 0; k < seg; k++)
                {
                    int a = v0 + i * cols2 + k, b = a + cols2, c = b + 1, d = a + 1;
                    T.Add(a); T.Add(b); T.Add(c); T.Add(a); T.Add(c); T.Add(d);
                }
            SmoothNormals(v0, t0);
        }

        public void AddTorus(Matrix4x4 m, float R, float r, int segR, int segr, Color col)
        {
            int v0 = V.Count, t0 = T.Count;
            for (int i = 0; i <= segR; i++)
            {
                float a = i / (float)segR * Mathf.PI * 2f;
                Vector3 c = new Vector3(Mathf.Cos(a), 0, Mathf.Sin(a));
                for (int j = 0; j <= segr; j++)
                {
                    float b = j / (float)segr * Mathf.PI * 2f;
                    Vector3 nrm = c * Mathf.Cos(b) + Vector3.up * Mathf.Sin(b);
                    AddVertex(m.MultiplyPoint3x4(c * R + nrm * r), m.MultiplyVector(nrm).normalized, col, Vector2.zero);
                }
            }
            for (int i = 0; i < segR; i++)
                for (int j = 0; j < segr; j++)
                {
                    int a = v0 + i * (segr + 1) + j, b = a + segr + 1, c2 = b + 1, d = a + 1;
                    T.Add(a); T.Add(c2); T.Add(b); T.Add(a); T.Add(d); T.Add(c2);
                }
        }

        /// <summary>Circular tube swept along a polyline (trunks, arms, pipes, vines). Radius per point.</summary>
        public void AddTube(Vector3[] path, float[] radius, int sides, Color col, Color? endCol = null, bool capEnd = true)
        {
            int v0 = V.Count, t0 = T.Count;
            int n = path.Length;
            Vector3 prevN = Vector3.zero;
            for (int i = 0; i < n; i++)
            {
                Vector3 t = (path[Mathf.Min(i + 1, n - 1)] - path[Mathf.Max(i - 1, 0)]).normalized;
                Vector3 nn;
                if (i == 0) { nn = Vector3.Cross(t, Mathf.Abs(t.y) < 0.9f ? Vector3.up : Vector3.right).normalized; }
                else { nn = (prevN - t * Vector3.Dot(prevN, t)).normalized; } // parallel transport
                prevN = nn;
                Vector3 bn = Vector3.Cross(t, nn);
                Color c = endCol.HasValue ? Color.Lerp(col, endCol.Value, i / (float)(n - 1)) : col;
                c.a = 1f;
                for (int k = 0; k <= sides; k++)
                {
                    float a = k / (float)sides * Mathf.PI * 2f;
                    Vector3 d = nn * Mathf.Cos(a) + bn * Mathf.Sin(a);
                    AddVertex(path[i] + d * radius[i], d, c, new Vector2(k / (float)sides, i / (float)(n - 1)));
                }
            }
            for (int i = 0; i < n - 1; i++)
                for (int k = 0; k < sides; k++)
                {
                    int a = v0 + i * (sides + 1) + k, b = a + 1, c2 = a + sides + 2, d = a + sides + 1;
                    T.Add(a); T.Add(b); T.Add(c2); T.Add(a); T.Add(c2); T.Add(d);
                }
            SmoothNormals(v0, t0);
            if (capEnd && radius[n - 1] > 0.001f)
            {
                Vector3 t = (path[n - 1] - path[n - 2]).normalized;
                int c = AddVertex(path[n - 1] + t * radius[n - 1] * 0.3f, t, endCol ?? col, Vector2.zero);
                int ring = v0 + (n - 1) * (sides + 1);
                for (int k = 0; k < sides; k++) { T.Add(c); T.Add(ring + k); T.Add(ring + k + 1); }
            }
        }

        static readonly Vector3[] icoV =
        {
            new Vector3(-1, 1.618f, 0), new Vector3(1, 1.618f, 0), new Vector3(-1, -1.618f, 0), new Vector3(1, -1.618f, 0),
            new Vector3(0, -1, 1.618f), new Vector3(0, 1, 1.618f), new Vector3(0, -1, -1.618f), new Vector3(0, 1, -1.618f),
            new Vector3(1.618f, 0, -1), new Vector3(1.618f, 0, 1), new Vector3(-1.618f, 0, -1), new Vector3(-1.618f, 0, 1)
        };
        static readonly int[] icoT =
        {
            0, 11, 5, 0, 5, 1, 0, 1, 7, 0, 7, 10, 0, 10, 11, 1, 5, 9, 5, 11, 4, 11, 10, 2, 10, 7, 6, 7, 1, 8,
            3, 9, 4, 3, 4, 2, 3, 2, 6, 3, 6, 8, 3, 8, 9, 4, 9, 5, 2, 4, 11, 6, 2, 10, 8, 6, 7, 9, 8, 1
        };

        /// <summary>Natural rock: subdivided icosphere with noise displacement, flattened base, top-lit colour (moss/snow cap).</summary>
        public void AddNaturalRock(Matrix4x4 m, float radius, Color col, Color topCol, Rng rng, int subdiv = 2, float rough = 0.22f, bool smooth = false)
        {
            var verts = new List<Vector3>(); var tris = new List<int>();
            foreach (var v in icoV) verts.Add(v.normalized);
            tris.AddRange(icoT);
            var cache = new Dictionary<long, int>();
            for (int s = 0; s < subdiv; s++)
            {
                var nt = new List<int>(tris.Count * 4);
                cache.Clear();
                System.Func<int, int, int> mid = (a, b) =>
                {
                    long key = a < b ? ((long)a << 32) | (uint)b : ((long)b << 32) | (uint)a;
                    int idx;
                    if (cache.TryGetValue(key, out idx)) return idx;
                    verts.Add(((verts[a] + verts[b]) * 0.5f).normalized);
                    cache[key] = verts.Count - 1;
                    return verts.Count - 1;
                };
                for (int t = 0; t < tris.Count; t += 3)
                {
                    int a = tris[t], b = tris[t + 1], c = tris[t + 2];
                    int ab = mid(a, b), bc = mid(b, c), ca = mid(c, a);
                    nt.AddRange(new[] { a, ab, ca, b, bc, ab, c, ca, bc, ab, bc, ca });
                }
                tris = nt;
            }
            int seed = rng.Range(0, 10000);
            var pts = new Vector3[verts.Count];
            for (int i = 0; i < verts.Count; i++)
            {
                Vector3 v = verts[i];
                float nz = Noise.Fbm(v.x * 1.7f + seed, v.z * 1.7f + v.y * 0.9f, 3, seed) - 0.5f;
                float r = 1f + nz * rough * 2f + Mathf.Abs(Noise.Value(v.x * 4f + seed, v.y * 4f + v.z * 2f, seed + 3) - 0.5f) * rough * 0.6f;
                Vector3 p = v * r;
                if (p.y < -0.35f) p.y = -0.35f + (p.y + 0.35f) * 0.2f; // flat-ish base so rocks sit on the ground
                pts[i] = p * radius;
            }
            if (smooth)
            {
                int v0 = V.Count, t0 = T.Count;
                for (int i = 0; i < pts.Length; i++)
                {
                    float up = Mathf.Clamp01(verts[i].y * 1.4f - 0.2f);
                    Color c = Color.Lerp(rng.Jitter(col, 0.03f), topCol, up * up); c.a = 1;
                    AddVertex(m.MultiplyPoint3x4(pts[i]), Vector3.up, c, Vector2.zero);
                }
                for (int t = 0; t < tris.Count; t += 3) { T.Add(v0 + tris[t]); T.Add(v0 + tris[t + 1]); T.Add(v0 + tris[t + 2]); }
                SmoothNormals(v0, t0);
            }
            else
            {
                for (int t = 0; t < tris.Count; t += 3)
                {
                    Vector3 a = m.MultiplyPoint3x4(pts[tris[t]]), b = m.MultiplyPoint3x4(pts[tris[t + 1]]), c = m.MultiplyPoint3x4(pts[tris[t + 2]]);
                    float up = Mathf.Clamp01((verts[tris[t]].y + verts[tris[t + 1]].y + verts[tris[t + 2]].y) / 3f * 1.4f - 0.15f);
                    Color cc = Color.Lerp(col, topCol, up * up) * (0.94f + Noise.Value(a.x, a.z, seed) * 0.12f);
                    cc.a = 1;
                    AddTri(a, b, c, cc);
                }
            }
        }

        /// <summary>Camera-facing-agnostic foliage card (two crossed quads) using an atlas cell (u0..u1).</summary>
        public void AddCrossCards(Vector3 basePos, float width, float height, float yaw, float u0, float u1, Color col, int cards = 2, float sway = 1f)
        {
            for (int c = 0; c < cards; c++)
            {
                float a = (yaw + c * 180f / cards) * Mathf.Deg2Rad;
                Vector3 r = new Vector3(Mathf.Cos(a), 0, Mathf.Sin(a)) * width * 0.5f;
                Vector3 up = Vector3.up * height;
                Color bot = col * 0.7f; bot.a = 0f;
                Color top = col; top.a = sway;
                int i = V.Count;
                Vector3 n = Vector3.up;
                AddVertex(basePos - r, n, bot, new Vector2(u0, 0));
                AddVertex(basePos - r + up, n, top, new Vector2(u0, 1));
                AddVertex(basePos + r + up, n, top, new Vector2(u1, 1));
                AddVertex(basePos + r, n, bot, new Vector2(u1, 0));
                T.Add(i); T.Add(i + 1); T.Add(i + 2); T.Add(i); T.Add(i + 2); T.Add(i + 3);
            }
        }

        /// <summary>Flat leaf / frond card between two points, bending down along its length (atlas cell u0..u1).</summary>
        public void AddFrond(Vector3 root, Vector3 dir, Vector3 side, float length, float width, float droop, float u0, float u1, Color col, int segs = 4)
        {
            int start = V.Count;
            for (int k = 0; k <= segs; k++)
            {
                float t = k / (float)segs;
                Vector3 p = root + dir * (t * length) + Vector3.down * (t * t * droop);
                Color c = Color.Lerp(col * 0.75f, col, t); c.a = Mathf.Clamp01(t * 1.5f);
                Vector3 n = Vector3.up;
                AddVertex(p - side * width * 0.5f, n, c, new Vector2(u0, t));
                AddVertex(p + side * width * 0.5f, n, c, new Vector2(u1, t));
            }
            for (int k = 0; k < segs; k++)
            {
                int a = start + k * 2;
                T.Add(a); T.Add(a + 2); T.Add(a + 3); T.Add(a); T.Add(a + 3); T.Add(a + 1);
            }
        }

        public void Append(MeshBuilder o, Matrix4x4 m)
        {
            int off = V.Count;
            for (int i = 0; i < o.V.Count; i++)
            {
                V.Add(m.MultiplyPoint3x4(o.V[i]));
                N.Add(m.MultiplyVector(o.N[i]).normalized);
                C.Add(o.C[i]); U.Add(o.U[i]);
            }
            for (int i = 0; i < o.T.Count; i++) T.Add(o.T[i] + off);
        }

        public Mesh ToMesh(string name = "Mesh", bool recalcNormals = false)
        {
            var mesh = new Mesh { name = name };
            if (V.Count > 65000) mesh.indexFormat = IndexFormat.UInt32;
            mesh.SetVertices(V);
            mesh.SetNormals(N);
            mesh.SetColors(C);
            mesh.SetUVs(0, U);
            mesh.SetTriangles(T, 0);
            if (recalcNormals) mesh.RecalculateNormals();
            mesh.RecalculateBounds();
            return mesh;
        }

        /// <summary>Creates a GameObject with MeshFilter + MeshRenderer, optionally a MeshCollider.</summary>
        public GameObject ToObject(string name, Transform parent, Material mat, int collisionLayer = -1)
        {
            var go = new GameObject(name);
            go.transform.SetParent(parent, false);
            var mesh = ToMesh(name);
            go.AddComponent<MeshFilter>().sharedMesh = mesh;
            var mr = go.AddComponent<MeshRenderer>();
            mr.sharedMaterial = mat;
            mr.shadowCastingMode = ShadowCastingMode.Off;
            mr.receiveShadows = false;
            if (collisionLayer >= 0)
            {
                go.layer = collisionLayer;
                var mc = go.AddComponent<MeshCollider>();
                mc.sharedMesh = mesh;
            }
            return go;
        }
    }
}
