using UnityEngine;

namespace TurboTribe
{
    /// <summary>
    /// Sculpted (signed-distance) scenery: one continuous, smooth-shaded surface per canopy / rock / pine tier / cactus
    /// limb instead of stacks of primitive spheres, cones and cylinders. Lobes melt into each other, noise breaks up
    /// silhouettes (leaf masses, chiselled stone, ragged branch tips, ribbed cactus skin) and colour follows the form
    /// (lit tops, shaded undersides, crevice occlusion, strata, moss / snow / sand caps). Vertex budgets are similar
    /// to the primitives they replace.
    /// </summary>
    public static class OrganicProps
    {
        static int Res(int full) { return Settings.Quality <= 0 ? Mathf.Max(6, full * 2 / 3) : full; }

        // ------------------------------------------------------------------ leafy canopy (several lobes, one skin)
        /// <summary>Canopy: lobes around 'centre' (offsets + radii) blended into one lumpy leaf mass.</summary>
        public static void Canopy(MeshBuilder mb, Vector3 centre, Vector3[] lobes, float[] radii, Color leaf, int seed, float squash = 0.78f)
        {
            float maxR = 0f;
            for (int i = 0; i < lobes.Length; i++) maxR = Mathf.Max(maxR, lobes[i].magnitude + radii[i] * 1.25f);
            float k = 0f; foreach (var r in radii) k += r; k = k / radii.Length * 0.55f;
            System.Func<Vector3, float> sdf = q =>
            {
                float d = 1e9f;
                for (int i = 0; i < lobes.Length; i++)
                    d = Sculpt.SMin(d, Sculpt.Ellipsoid(q - lobes[i], new Vector3(radii[i], radii[i] * squash, radii[i])), k);
                float s = radii[0];
                d += (Sculpt.Fbm3(q * (1.1f / s), 2, seed) - 0.5f) * 0.55f * s;      // leaf masses
                d += (Sculpt.Noise3(q * (4.5f / s), seed + 7) - 0.5f) * 0.12f * s;    // leaf clusters
                return d;
            };
            Color hi = Color.Lerp(leaf, new Color(0.85f, 1f, 0.5f), 0.22f), lo = leaf * 0.5f;
            System.Func<Vector3, Vector3, Color> col = (q, n) =>
            {
                float up = n.y * 0.5f + 0.5f;
                Color c = Color.Lerp(lo, hi, up * up);
                c *= 0.88f + 0.24f * Sculpt.Noise3(q * 1.7f, seed + 3);
                return c;
            };
            Sculpt.Radial(mb, Matrix4x4.TRS(centre, Quaternion.identity, Vector3.one), sdf, col, maxR + 0.5f, Res(12), Res(20));
        }

        // ------------------------------------------------------------------ rocks
        /// <summary>Chiselled boulder: noisy ellipsoid with flattened facets, strata bands and a capped top.</summary>
        public static void Rock(MeshBuilder mb, Matrix4x4 m, float size, Color col, Color top, int seed)
        {
            var rnd = new System.Random(seed);
            System.Func<float> rv = () => (float)rnd.NextDouble();
            // two or three random cutting planes give the stone flat, fractured faces
            int cuts = 2 + rnd.Next(2);
            var pn = new Vector3[cuts]; var pd = new float[cuts];
            for (int i = 0; i < cuts; i++)
            {
                float a = rv() * Mathf.PI * 2f, e = Mathf.Lerp(-0.2f, 0.8f, rv());
                pn[i] = new Vector3(Mathf.Cos(a) * Mathf.Cos(e), Mathf.Sin(e), Mathf.Sin(a) * Mathf.Cos(e));
                pd[i] = size * Mathf.Lerp(0.55f, 0.85f, rv());
            }
            float strata = Mathf.Lerp(3.5f, 6f, rv()) / size;
            System.Func<Vector3, float> sdf = q =>
            {
                float d = Sculpt.Ellipsoid(q, new Vector3(size, size * 0.78f, size * 0.95f));
                for (int i = 0; i < cuts; i++) d = Sculpt.SMax(d, Vector3.Dot(q, pn[i]) - pd[i], size * 0.12f);
                d = Sculpt.SMax(d, -q.y - size * 0.7f, size * 0.1f);                               // base reaches into the ground (never floats on a slope)
                d += (Sculpt.Fbm3(q * (1.6f / size), 3, seed) - 0.5f) * 0.32f * size;
                d += Mathf.Abs(Mathf.Sin(q.y * strata * 6.28f)) * 0.025f * size;                     // weathered layers
                return d;
            };
            System.Func<Vector3, Vector3, Color> colf = (q, n) =>
            {
                Color c = col * (0.84f + 0.24f * Sculpt.Noise3(q * (2.2f / size), seed + 5));
                float band = Mathf.Sin(q.y * strata * 6.28f + Sculpt.Noise3(q * 0.6f, seed) * 3f);
                c = Color.Lerp(c, c * 0.82f, Mathx.SmoothStep01(0.3f, 0.8f, band));
                float cap = Mathx.SmoothStep01(0.55f, 0.85f, n.y + (Sculpt.Noise3(q * (3f / size), seed + 9) - 0.5f) * 0.3f);
                c = Color.Lerp(c, top, cap);
                if (n.y < -0.2f) c *= 0.8f;
                return c;
            };
            int rows = size > 3f ? 12 : size > 1.5f ? 10 : 8;
            Sculpt.Radial(mb, m, sdf, colf, size * 1.6f, Res(rows), Res(rows * 3 / 2 + 2));
        }

        // ------------------------------------------------------------------ pine (ragged drooping skirts)
        public static void PineTier(MeshBuilder mb, Vector3 baseCentre, float r, float h, Color dark, Color mid, Color snow, int seed, bool snowy)
        {
            System.Func<Vector3, float> sdf = q =>
            {
                // drooping skirt: radius falls from r at the base to ~0 at the tip, the base edge curls down
                float y = q.y;
                float u = Mathf.Clamp01(y / h);
                float ang = Mathf.Atan2(q.z, q.x);
                float ragged = 1f + 0.16f * (Sculpt.Noise3(new Vector3(Mathf.Cos(ang) * 3f, Mathf.Sin(ang) * 3f, u * 2f), seed) - 0.5f) * 2f
                               + 0.08f * Mathf.Sin(ang * 9f + seed);
                float R = r * Mathf.Pow(1f - u, 1.15f) * ragged;
                float radial = new Vector2(q.x, q.z).magnitude;
                float side = (radial - R) * 0.8f;
                float bottom = -(y + 0.25f * h * Mathf.Clamp01(radial / r));                    // concave droop underneath
                return Mathf.Max(side, Mathf.Max(bottom, y - h));
            };
            System.Func<Vector3, Vector3, Color> col = (q, n) =>
            {
                float up = n.y * 0.5f + 0.5f;
                Color c = Color.Lerp(dark * 0.75f, mid, up);
                c *= 0.88f + 0.22f * Sculpt.Noise3(q * 2.3f, seed + 2);
                if (snowy) c = Color.Lerp(c, snow, Mathx.SmoothStep01(0.45f, 0.75f, n.y + (Sculpt.Noise3(q * 3f, seed) - 0.5f) * 0.35f));
                return c;
            };
            Sculpt.Radial(mb, Matrix4x4.TRS(baseCentre, Quaternion.identity, Vector3.one), sdf, col, Mathf.Max(r, h) * 1.4f, Res(9), Res(18), new Vector3(0, h * 0.28f, 0));
        }

        // ------------------------------------------------------------------ ribbed limb (cactus, bamboo)
        /// <summary>Tube along a path with ribs (radius modulated around the circumference) and rounded caps.</summary>
        public static void RibbedTube(MeshBuilder mb, Vector3[] path, float[] radius, int ribs, float ribDepth, Color col, Color tip, int sides = 14)
        {
            int n = path.Length;
            int start = mb.VertexCount;
            Vector3 prevSide = Vector3.zero;
            for (int i = 0; i < n; i++)
            {
                Vector3 t = (path[Mathf.Min(i + 1, n - 1)] - path[Mathf.Max(i - 1, 0)]).normalized;
                Vector3 side = i == 0 ? Vector3.Cross(t, Mathf.Abs(t.y) < 0.9f ? Vector3.up : Vector3.right).normalized
                                      : Vector3.ProjectOnPlane(prevSide, t).normalized;
                prevSide = side;
                Vector3 up = Vector3.Cross(side, t);
                float u = i / (float)(n - 1);
                for (int k = 0; k <= sides; k++)
                {
                    float a = k / (float)sides * Mathf.PI * 2f;
                    float rib = 1f - ribDepth * (0.5f - 0.5f * Mathf.Cos(a * ribs));
                    Vector3 dir = side * Mathf.Cos(a) + up * Mathf.Sin(a);
                    float r = radius[i] * rib;
                    Vector3 nrm = (dir - t * 0f).normalized;
                    Color c = Color.Lerp(col, tip, u * u) * (0.82f + 0.18f * rib);
                    mb.AddVertex(path[i] + dir * r, nrm, c, new Vector2(k / (float)sides, u));
                }
            }
            for (int i = 0; i < n - 1; i++)
                for (int k = 0; k < sides; k++)
                {
                    int a = start + i * (sides + 1) + k, b = a + sides + 1;
                    mb.AddTriangle(a, b, b + 1);
                    mb.AddTriangle(a, b + 1, a + 1);
                }
            // dome cap at the tip
            Vector3 te = (path[n - 1] - path[n - 2]).normalized;
            mb.AddSphere(Matrix4x4.TRS(path[n - 1], Quaternion.FromToRotation(Vector3.up, te), new Vector3(1f, 0.7f, 1f)), radius[n - 1] * (1f - ribDepth * 0.5f), 4, sides, tip);
        }

        // ------------------------------------------------------------------ desert butte / mesa
        /// <summary>Eroded butte: wavy, ledged sides narrowing upward, a rounded caprock rim, strata colours.</summary>
        public static void Butte(MeshBuilder mb, Vector3 pos, float radius, float height, Color rock, Color band, Color cap, float stretch, int seed)
        {
            float bands = Mathf.Max(3f, height / 3.2f);
            System.Func<Vector3, float> sdf = q =>
            {
                Vector3 e = new Vector3(q.x, q.y, q.z / stretch);
                float u = Mathf.Clamp01(e.y / height);
                float ang = Mathf.Atan2(e.z, e.x);
                float n = Sculpt.Noise3(new Vector3(Mathf.Cos(ang) * 2.2f, Mathf.Sin(ang) * 2.2f, u * 3f), seed) - 0.5f;
                float ledge = 0.035f * Mathf.Floor(Mathf.Repeat(u * bands, 1f) * 2f);         // stepped strata ledges
                float R = radius / 1.22f * (1f - 0.18f * u) * (1f + 0.22f * n + ledge) * (1f + 0.05f * Mathf.Sin(ang * 5f + seed));   // never wider than 'radius'
                float side = (new Vector2(e.x, e.z).magnitude - R) * 0.75f;
                float top = e.y - height - (Sculpt.Noise3(e * (1.5f / radius), seed + 4) - 0.5f) * 0.12f * radius;
                return Sculpt.SMax(Sculpt.SMax(side, top, radius * 0.12f), -e.y - 3f, 0.5f);
            };
            System.Func<Vector3, Vector3, Color> col = (q, n) =>
            {
                float u = q.y / height;
                float b = Mathf.Repeat(u * bands + Sculpt.Noise3(q * (0.8f / radius), seed) * 0.6f, 1f);
                Color c = b < 0.5f ? rock : band;
                c *= 0.86f + 0.22f * Sculpt.Noise3(q * (2.5f / radius), seed + 2);
                c = Color.Lerp(c, cap, Mathx.SmoothStep01(0.6f, 0.85f, n.y));
                if (n.y < -0.1f) c *= 0.78f;
                return c;
            };
            Sculpt.Radial(mb, Matrix4x4.TRS(pos, Quaternion.Euler(0, seed % 360, 0), Vector3.one), sdf, col, Mathf.Max(radius * stretch, height) * 1.5f + 3f,
                          Res(height > 12f ? 18 : 12), Res(height > 12f ? 30 : 20), new Vector3(0, height * 0.4f, 0));
        }

        // ------------------------------------------------------------------ volcano
        /// <summary>Volcano: concave cone with radial gullies and lumpy flanks, a sunken crater.</summary>
        public static System.Func<Vector3, float> Volcano(MeshBuilder mb, Vector3 pos, float r, float h, Color low, Color mid, Color cliff, Color crater, int seed)
        {
            System.Func<Vector3, float> sdf = q =>
            {
                float u = Mathf.Clamp01((q.y + 2f) / (h + 2f));
                float ang = Mathf.Atan2(q.z, q.x);
                float R = Mathf.Lerp(r * 1.0f, r * 0.36f, Mathf.Pow(u, 0.9f));               // footprint stays inside r: steep cone with a wide crater rim
                R *= 1f + 0.07f * Mathf.Sin(ang * 7f + Sculpt.Noise3(q * (0.15f / r * 10f), seed) * 2f) * (0.4f + u);   // gullies
                R *= 1f + 0.12f * (Sculpt.Fbm3(q * (1.2f / r), 2, seed + 1) - 0.5f);
                float side = (new Vector2(q.x, q.z).magnitude - R) * 0.7f;
                float d = Mathf.Max(side, Mathf.Max(q.y - h, -q.y - 6f));
                float craterR = r * 0.2f;
                d = Sculpt.SMax(d, -(Mathf.Max(craterR - new Vector2(q.x, q.z).magnitude, q.y - (h - r * 0.12f))) , r * 0.04f);
                return d;
            };
            System.Func<Vector3, Vector3, Color> col = (q, n) =>
            {
                float u = Mathf.Clamp01(q.y / h);
                Color c = u < 0.25f ? Color.Lerp(low, mid, u / 0.25f) : Color.Lerp(mid, cliff, Mathx.SmoothStep01(0.25f, 0.7f, u));
                c *= 0.85f + 0.25f * Sculpt.Noise3(q * (2f / r * 3f), seed + 3);
                if (new Vector2(q.x, q.z).magnitude < r * 0.24f && u > 0.85f) c = crater;
                return c;
            };
            Sculpt.Radial(mb, Matrix4x4.TRS(pos, Quaternion.identity, Vector3.one), sdf, col, Mathf.Max(r * 1.4f, h * 1.1f), Res(24), Res(40), new Vector3(0, h * 0.35f, 0));
            return sdf;
        }
    }
}
