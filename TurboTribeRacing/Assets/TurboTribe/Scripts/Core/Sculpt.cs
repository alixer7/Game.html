using System;
using UnityEngine;

namespace TurboTribe
{
    /// <summary>
    /// Tiny signed-distance-field toolkit for sculpted, organic procedural meshes (character heads, bodies, rocks,
    /// trunks): primitives, smooth blends (so parts grow out of each other instead of intersecting like separate
    /// spheres), 3D value noise for fur / bark / stone texture, and a radial mesher that turns a star-shaped SDF into
    /// one continuous, smooth-shaded surface with SDF-gradient normals and a colour callback.
    /// </summary>
    public static class Sculpt
    {
        // ------------------------------------------------------------------ primitives (all approximate distances)
        /// <summary>Ellipsoid (Quilez' bound): good near the surface, which is all the mesher needs.</summary>
        public static float Ellipsoid(Vector3 p, Vector3 r)
        {
            float k0 = new Vector3(p.x / r.x, p.y / r.y, p.z / r.z).magnitude;
            float k1 = new Vector3(p.x / (r.x * r.x), p.y / (r.y * r.y), p.z / (r.z * r.z)).magnitude;
            return k1 > 1e-6f ? k0 * (k0 - 1f) / k1 : -Mathf.Min(r.x, Mathf.Min(r.y, r.z));
        }

        public static float Ellipsoid(Vector3 p, Vector3 c, Vector3 r) { return Ellipsoid(p - c, r); }

        /// <summary>Ellipsoid rotated by q (r in its local axes).</summary>
        public static float Ellipsoid(Vector3 p, Vector3 c, Vector3 r, Quaternion q) { return Ellipsoid(Quaternion.Inverse(q) * (p - c), r); }

        public static float Sphere(Vector3 p, Vector3 c, float r) { return (p - c).magnitude - r; }

        /// <summary>Capsule with radii tapering from ra (at a) to rb (at b) - limbs, horns, snouts, trunks.</summary>
        public static float Capsule(Vector3 p, Vector3 a, Vector3 b, float ra, float rb)
        {
            Vector3 ab = b - a, ap = p - a;
            float t = Mathf.Clamp01(Vector3.Dot(ap, ab) / Mathf.Max(ab.sqrMagnitude, 1e-8f));
            return (ap - ab * t).magnitude - Mathf.Lerp(ra, rb, t);
        }

        public static float Capsule(Vector3 p, Vector3 a, Vector3 b, float r) { return Capsule(p, a, b, r, r); }

        // ------------------------------------------------------------------ blends
        /// <summary>Polynomial smooth union: parts melt into each other over ~k metres.</summary>
        public static float SMin(float a, float b, float k)
        {
            if (k <= 0f) return Mathf.Min(a, b);
            float h = Mathf.Clamp01(0.5f + 0.5f * (b - a) / k);
            return Mathf.Lerp(b, a, h) - k * h * (1f - h);
        }

        /// <summary>Smooth subtraction of b from a (carving sockets, creases, nostrils).</summary>
        public static float SSub(float a, float b, float k) { return -SMin(-a, b, k); }

        /// <summary>Smooth intersection.</summary>
        public static float SMax(float a, float b, float k) { return -SMin(-a, -b, k); }

        // ------------------------------------------------------------------ noise
        static float Hash(int x, int y, int z, int seed)
        {
            unchecked
            {
                int h = x * 374761393 + y * 668265263 + z * 1274126177 + seed * 1442695041;
                h = (h ^ (h >> 13)) * 1274126177;
                return ((h ^ (h >> 16)) & 0xFFFFFF) / 16777215f;
            }
        }

        /// <summary>3D value noise in [0,1], smooth (quintic fade).</summary>
        public static float Noise3(Vector3 p, int seed = 0)
        {
            int x0 = Mathf.FloorToInt(p.x), y0 = Mathf.FloorToInt(p.y), z0 = Mathf.FloorToInt(p.z);
            float fx = p.x - x0, fy = p.y - y0, fz = p.z - z0;
            fx = fx * fx * fx * (fx * (fx * 6f - 15f) + 10f);
            fy = fy * fy * fy * (fy * (fy * 6f - 15f) + 10f);
            fz = fz * fz * fz * (fz * (fz * 6f - 15f) + 10f);
            float c000 = Hash(x0, y0, z0, seed), c100 = Hash(x0 + 1, y0, z0, seed), c010 = Hash(x0, y0 + 1, z0, seed), c110 = Hash(x0 + 1, y0 + 1, z0, seed);
            float c001 = Hash(x0, y0, z0 + 1, seed), c101 = Hash(x0 + 1, y0, z0 + 1, seed), c011 = Hash(x0, y0 + 1, z0 + 1, seed), c111 = Hash(x0 + 1, y0 + 1, z0 + 1, seed);
            float a = Mathf.Lerp(Mathf.Lerp(c000, c100, fx), Mathf.Lerp(c010, c110, fx), fy);
            float b = Mathf.Lerp(Mathf.Lerp(c001, c101, fx), Mathf.Lerp(c011, c111, fx), fy);
            return Mathf.Lerp(a, b, fz);
        }

        /// <summary>Fractal 3D noise in roughly [0,1].</summary>
        public static float Fbm3(Vector3 p, int octaves, int seed = 0)
        {
            float sum = 0f, amp = 0.5f, norm = 0f;
            for (int o = 0; o < octaves; o++) { sum += Noise3(p, seed + o * 31) * amp; norm += amp; p = p * 2.03f + new Vector3(17.1f, 3.7f, 9.3f); amp *= 0.5f; }
            return sum / norm;
        }

        // ------------------------------------------------------------------ radial mesher
        /// <summary>
        /// Meshes a star-shaped SDF (every ray from 'centre' crosses the surface once) as one continuous lat/long
        /// surface: rows x cols rays, the crossing found by marching + bisection, normals from the SDF gradient
        /// (smooth shading with no seams), colours from 'color(localPoint, normal)'. 'm' places the result.
        /// Returns the first vertex index.
        /// </summary>
        public static int Radial(MeshBuilder mb, Matrix4x4 m, Func<Vector3, float> sdf, Func<Vector3, Vector3, Color> color,
                                 float maxR, int rows, int cols, Vector3 centre = default(Vector3))
        {
            int v0 = mb.VertexCount;
            float step = maxR / 48f;
            var pts = new Vector3[(rows + 1) * (cols + 1)];
            for (int r = 0; r <= rows; r++)
            {
                float lat = Mathf.PI * r / rows;               // 0 = top (+Y), PI = bottom
                float sy = Mathf.Cos(lat), sr = Mathf.Sin(lat);
                for (int c = 0; c <= cols; c++)
                {
                    float lon = 2f * Mathf.PI * (c % cols) / cols;
                    Vector3 d = new Vector3(Mathf.Cos(lon) * sr, sy, Mathf.Sin(lon) * sr);   // same parametrisation + winding as AddSphere
                    // march outwards from inside until the field turns positive, then bisect
                    float t0 = 0f, t1 = step;
                    float f1 = sdf(centre + d * t1);
                    int guard = 0;
                    while (f1 < 0f && t1 < maxR && guard++ < 200) { t0 = t1; t1 += Mathf.Max(step * 0.35f, Mathf.Min(step, -f1)); f1 = sdf(centre + d * t1); }
                    for (int k = 0; k < 10; k++)
                    {
                        float tm = (t0 + t1) * 0.5f;
                        if (sdf(centre + d * tm) < 0f) t0 = tm; else t1 = tm;
                    }
                    pts[r * (cols + 1) + c] = centre + d * ((t0 + t1) * 0.5f);
                }
            }
            const float e = 0.0025f;
            for (int i = 0; i < pts.Length; i++)
            {
                Vector3 p = pts[i];
                Vector3 n = new Vector3(sdf(p + new Vector3(e, 0, 0)) - sdf(p - new Vector3(e, 0, 0)),
                                        sdf(p + new Vector3(0, e, 0)) - sdf(p - new Vector3(0, e, 0)),
                                        sdf(p + new Vector3(0, 0, e)) - sdf(p - new Vector3(0, 0, e)));
                n = n.sqrMagnitude > 1e-12f ? n.normalized : (p - centre).normalized;
                Color col = color(p, n); col.a = 1f;
                mb.AddVertex(m.MultiplyPoint3x4(p), m.MultiplyVector(n).normalized, col, new Vector2(i % (cols + 1) / (float)cols, i / (cols + 1) / (float)rows));
            }
            for (int r = 0; r < rows; r++)
                for (int c = 0; c < cols; c++)
                {
                    int a = v0 + r * (cols + 1) + c, b = a + cols + 1;
                    mb.AddTriangle(a, a + 1, b + 1);
                    mb.AddTriangle(a, b + 1, b);
                }
            return v0;
        }

        /// <summary>Point on the surface along a ray from 'from' in direction 'dir' (local coordinates).</summary>
        public static Vector3 Hit(Func<Vector3, float> sdf, Vector3 from, Vector3 dir, float maxT)
        {
            dir = dir.normalized;
            float t0 = 0f, t1 = 0f, step = maxT / 64f;
            if (sdf(from) >= 0f) return from;
            while (t1 < maxT) { t0 = t1; t1 += step; if (sdf(from + dir * t1) >= 0f) break; }
            for (int k = 0; k < 12; k++) { float tm = (t0 + t1) * 0.5f; if (sdf(from + dir * tm) < 0f) t0 = tm; else t1 = tm; }
            return from + dir * ((t0 + t1) * 0.5f);
        }
    }
}
