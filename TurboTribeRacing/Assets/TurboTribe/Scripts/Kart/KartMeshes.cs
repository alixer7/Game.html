using System.Collections.Generic;
using UnityEngine;

namespace TurboTribe
{
    /// <summary>
    /// Pure geometry for karts and drivers (kept separate so it can be previewed headless).
    /// v2: sculpted lofted monocoque, sidepods with intakes, suspension arms + coil springs, finned engine,
    /// curved exhausts, airfoil wings, detailed wheels (treaded tyre, spoked rim, brake disc) and
    /// stylised-anatomy drivers (lofted torso, jointed arms, gloved fingers wrapped round the wheel,
    /// layered eyes with iris/pupil/highlight/eyelids, brows, mouth + teeth, species ears, tails, scarf, goggles).
    /// Pivot at the ground contact, +Z forward, +X right.
    /// </summary>
    public static class KartMeshes
    {
        static Matrix4x4 M(Vector3 p, Vector3 e, Vector3 s) { return Matrix4x4.TRS(p, Quaternion.Euler(e), s); }
        static Matrix4x4 M(Vector3 p) { return Matrix4x4.TRS(p, Quaternion.identity, Vector3.one); }
        static Color H(string hex) { Color c; ColorUtility.TryParseHtmlString(hex, out c); return c; }
        static Color Mul(Color c, float k) { return new Color(c.r * k, c.g * k, c.b * k, 1f); }

        /// <summary>Low-detail mode for the distant LOD: halves tessellation and skips small parts.</summary>
        public static bool Lo;
        static int Rs(int n) { return Lo ? Mathf.Max(4, n / 2) : n; }

        // wheel layout shared with KartModel
        public static readonly Vector3[] WheelPos = { new Vector3(-0.74f, 0.36f, 0.66f), new Vector3(0.74f, 0.36f, 0.66f), new Vector3(-0.78f, 0.4f, -0.68f), new Vector3(0.78f, 0.4f, -0.68f) };
        public static readonly float[] WheelScale = { 1f, 1f, 1.12f, 1.12f };
        public static readonly Vector3[] ExhaustTips = { new Vector3(-0.34f, 0.8f, -1.36f), new Vector3(0.34f, 0.8f, -1.36f) };

        static readonly Color Rubber = new Color(0.12f, 0.12f, 0.14f), Carbon = new Color(0.17f, 0.17f, 0.2f), Chrome = new Color(0.82f, 0.84f, 0.9f),
                              Steel = new Color(0.52f, 0.54f, 0.6f), Glass = new Color(0.25f, 0.55f, 0.65f), Black = new Color(0.07f, 0.07f, 0.09f);

        // ================================================================== helpers
        static void Ellipsoid(MeshBuilder mb, Vector3 c, Vector3 r, Quaternion q, Color col, int lat = 10, int lon = 16, Color? bottom = null)
        {
            mb.AddSphere(Matrix4x4.TRS(c, q, r), 1f, Rs(lat), Rs(lon), col, bottom);
        }
        static void Ellipsoid(MeshBuilder mb, Vector3 c, Vector3 r, Color col, int lat = 10, int lon = 16, Color? bottom = null)
        {
            mb.AddSphere(Matrix4x4.TRS(c, Quaternion.identity, r), 1f, Rs(lat), Rs(lon), col, bottom);
        }

        static Vector3[] Bezier(Vector3 a, Vector3 b, Vector3 c, int n)
        {
            var p = new Vector3[n];
            for (int i = 0; i < n; i++)
            {
                float t = i / (float)(n - 1);
                p[i] = (1 - t) * (1 - t) * a + 2 * (1 - t) * t * b + t * t * c;
            }
            return p;
        }

        static float[] Radii(int n, params float[] keys)
        {
            var r = new float[n];
            for (int i = 0; i < n; i++)
            {
                float t = i / (float)(n - 1) * (keys.Length - 1);
                int k = Mathf.Min(Mathf.FloorToInt(t), keys.Length - 2);
                r[i] = Mathf.Lerp(keys[k], keys[k + 1], t - k);
            }
            return r;
        }

        static void Tube(MeshBuilder mb, Vector3 a, Vector3 b, float r, Color col, int sides = 8)
        {
            mb.AddTube(new[] { a, b }, new[] { r, r }, Rs(sides), col);
        }

        /// <summary>Loft along an arbitrary axis: frame maps loft-local Z onto 'dir' (sections: W across 'side', H across up).</summary>
        static void LoftAlong(MeshBuilder mb, Vector3 origin, Vector3 dir, Vector3 upHint, MeshBuilder.LoftSection[] secs, int around, bool caps = true)
        {
            var q = Quaternion.LookRotation(dir.normalized, upHint);
            mb.AddLoft(Matrix4x4.TRS(origin, q, Vector3.one), secs, Rs(around), caps);
        }

        static MeshBuilder.LoftSection S(float z, float w, float h, float y, Color c, float p = 3f, float x = 0f) { return new MeshBuilder.LoftSection(z, w, h, y, c, p, x); }

        /// <summary>AddLoft builds outward-facing quads only for sections in ascending Z: sort first.</summary>
        static void Loft(MeshBuilder mb, Matrix4x4 m, MeshBuilder.LoftSection[] secs, int around, bool caps = true)
        {
            var a = (MeshBuilder.LoftSection[])secs.Clone();
            System.Array.Sort(a, (x, y) => x.Z.CompareTo(y.Z));
            mb.AddLoft(m, a, Rs(around), caps);
        }

        // ================================================================== wheel
        static readonly Dictionary<int, Mesh> wheelCache = new Dictionary<int, Mesh>();

        public static Mesh BuildWheelMesh() { return BuildWheelMesh(Chrome); }

        /// <summary>Tyre (rounded sidewalls + tread blocks), dished spoked rim, hub cap, brake disc. Axle along X, outer face +X.</summary>
        public static Mesh BuildWheelMesh(Color rim)
        {
            int key = ((int)(rim.r * 255) << 16) | ((int)(rim.g * 255) << 8) | (int)(rim.b * 255) | (Lo ? 1 << 24 : 0);
            Mesh cached;
            if (wheelCache.TryGetValue(key, out cached) && cached != null) return cached;
            var mb = new MeshBuilder();
            BuildWheel(mb, rim);
            var m = mb.ToMesh(Lo ? "WheelLOD1" : "Wheel");
            wheelCache[key] = m;
            return m;
        }

        public static void BuildWheel(MeshBuilder mb, Color rim)
        {
            // lathe around local Y, then rotate Y -> X (outer side = +X)
            var rot = Quaternion.Euler(0, 0, -90);
            var tm = Matrix4x4.TRS(Vector3.zero, rot, Vector3.one);
            Vector2[] tyre =
            {
                new Vector2(0.22f, -0.165f), new Vector2(0.30f, -0.185f), new Vector2(0.345f, -0.17f), new Vector2(0.362f, -0.13f),
                new Vector2(0.366f, 0f), new Vector2(0.362f, 0.13f), new Vector2(0.345f, 0.17f), new Vector2(0.30f, 0.185f), new Vector2(0.22f, 0.165f)
            };
            var tc = new Color[tyre.Length];
            for (int i = 0; i < tc.Length; i++) tc[i] = (i == 0 || i == tyre.Length - 1) ? Mul(Rubber, 0.8f) : (i == 4 ? Mul(Rubber, 1.05f) : Rubber);
            mb.AddLathe(tm, tyre, Lo ? 12 : 28, tc);
            // tread blocks (chevrons)
            int blocks = Lo ? 0 : 18;
            for (int k = 0; k < blocks; k++)
            {
                float a = k * 360f / blocks + (k % 2) * 4f;
                var q = Quaternion.Euler(a, 0, 0);
                for (int s = -1; s <= 1; s += 2)
                {
                    Vector3 c = q * new Vector3(s * 0.075f, 0.364f, 0f);
                    var bq = q * Quaternion.Euler(0, s * 22f, 0);
                    mb.AddBox(Matrix4x4.TRS(c, bq, Vector3.one), new Vector3(0.11f, 0.03f, 0.055f), Mul(Rubber, 0.88f));
                }
            }
            // rim: dished barrel + face (lathe), slightly recessed
            Vector2[] barrel = { new Vector2(0.2f, -0.15f), new Vector2(0.222f, -0.15f), new Vector2(0.222f, 0.13f), new Vector2(0.205f, 0.145f), new Vector2(0.17f, 0.11f), new Vector2(0.07f, 0.09f), new Vector2(0.0f, 0.1f) };
            var rc = new[] { Mul(rim, 0.6f), rim, rim, Mul(rim, 1.1f), Mul(rim, 0.8f), Mul(rim, 0.75f), Mul(rim, 0.9f) };
            mb.AddLathe(tm, barrel, Lo ? 10 : 24, rc);
            if (Lo) return;
            // spokes (5) from hub to rim lip
            for (int k = 0; k < 5; k++)
            {
                var q = Quaternion.Euler(k * 72f + 10f, 0, 0);
                Vector3 c = q * new Vector3(0.11f, 0.12f, 0f);
                mb.AddRoundedBox(Matrix4x4.TRS(c, q, Vector3.one), new Vector3(0.035f, 0.13f, 0.045f), 0.015f, Mul(rim, 1.05f), 1);
            }
            // hub cap + lug nuts
            Ellipsoid(mb, new Vector3(0.115f, 0, 0), new Vector3(0.035f, 0.055f, 0.055f), Mul(rim, 1.15f), 6, 12);
            for (int k = 0; k < 5; k++)
            {
                var q = Quaternion.Euler(k * 72f + 46f, 0, 0);
                mb.AddCylinder(Matrix4x4.TRS(q * new Vector3(0.1f, 0.07f, 0f), q * Quaternion.Euler(0, 0, -90), Vector3.one), 0.012f, 0.012f, 0.02f, 6, Steel);
            }
            // brake disc behind the spokes
            mb.AddCylinder(Matrix4x4.TRS(new Vector3(-0.06f, 0, 0), rot, Vector3.one), 0.17f, 0.17f, 0.02f, 20, Steel, true, true, Mul(Steel, 1.2f));
        }

        // ================================================================== chassis
        struct Shape
        {
            public float NoseLen, NoseLift, PodW, PodH, WingW, WingH, Bulk;
            public bool Supercharger, Fenders, Fins;
        }

        static Shape ShapeFor(KartClass c)
        {
            switch (c)
            {
                case KartClass.Speed: return new Shape { NoseLen = 1.38f, NoseLift = 0f, PodW = 0.2f, PodH = 0.15f, WingW = 1.62f, WingH = 1.18f, Bulk = 0.95f, Fins = true };
                case KartClass.Acceleration: return new Shape { NoseLen = 1.22f, NoseLift = 0.04f, PodW = 0.22f, PodH = 0.19f, WingW = 1.36f, WingH = 1.06f, Bulk = 1.05f, Supercharger = true };
                case KartClass.Turning: return new Shape { NoseLen = 1.26f, NoseLift = 0.02f, PodW = 0.24f, PodH = 0.17f, WingW = 1.5f, WingH = 1.1f, Bulk = 1f, Fenders = true };
                default: return new Shape { NoseLen = 1.3f, NoseLift = 0.02f, PodW = 0.22f, PodH = 0.17f, WingW = 1.5f, WingH = 1.12f, Bulk = 1f };
            }
        }

        public static void BuildChassis(MeshBuilder mb, CharacterDef ch)
        {
            Color body = ch.Kart, acc = ch.KartAccent, bodyDark = Mul(ch.Kart, 0.72f), bodyLight = Color.Lerp(ch.Kart, Color.white, 0.18f);
            var sh = ShapeFor(ch.Class);
            float L = sh.NoseLen, nl = sh.NoseLift, bk = sh.Bulk;

            // --- floor pan / undertray + skid plate
            mb.AddRoundedBox(M(new Vector3(0, 0.27f, -0.05f)), new Vector3(1.0f, 0.07f, 2.2f), 0.03f, Carbon, 2);
            mb.AddRoundedBox(M(new Vector3(0, 0.235f, 0.35f)), new Vector3(0.6f, 0.03f, 0.9f), 0.012f, Steel, 1);

            // --- monocoque: sculpted loft nose -> cockpit -> engine bay
            var mono = new[]
            {
                S(L, 0.10f, 0.06f, 0.37f + nl, bodyLight, 2.6f),
                S(L - 0.06f, 0.2f, 0.1f, 0.385f + nl, body, 2.8f),
                S(L - 0.22f, 0.33f, 0.14f, 0.41f + nl, body, 3.0f),
                S(0.78f, 0.42f * bk, 0.17f, 0.44f + nl * 0.5f, body, 3.2f),
                S(0.45f, 0.47f * bk, 0.2f, 0.46f, body, 3.4f),
                S(0.18f, 0.5f * bk, 0.21f, 0.47f, body, 3.6f),
                S(-0.18f, 0.5f * bk, 0.2f, 0.46f, body, 3.6f),
                S(-0.5f, 0.46f * bk, 0.2f, 0.47f, bodyDark, 3.4f),
                S(-0.86f, 0.42f * bk, 0.19f, 0.48f, bodyDark, 3.2f),
                S(-1.08f, 0.34f, 0.15f, 0.47f, bodyDark, 3f),
                S(-1.16f, 0.22f, 0.09f, 0.46f, Carbon, 2.6f),
            };
            Loft(mb, Matrix4x4.identity, mono, 28);
            // cockpit rim (dark lip around the driver's opening)
            mb.AddTorus(Matrix4x4.TRS(new Vector3(0, 0.66f, -0.18f), Quaternion.identity, new Vector3(1.05f, 1f, 1.5f)), 0.29f, 0.035f, 24, 6, Carbon);
            // nose cowl stripe + number roundel
            var stripe = new[]
            {
                S(L - 0.04f, 0.035f, 0.012f, 0.43f + nl, acc, 2f),
                S(L - 0.22f, 0.07f, 0.012f, 0.548f + nl, acc, 2f),
                S(0.78f, 0.09f, 0.012f, 0.612f + nl * 0.5f, acc, 2f),
                S(0.45f, 0.1f, 0.012f, 0.662f, acc, 2f),
                S(0.28f, 0.1f, 0.012f, 0.676f, acc, 2f),
            };
            Loft(mb, Matrix4x4.identity, stripe, 8);
            mb.AddCylinder(M(new Vector3(0, 0.6f + nl * 0.5f, 0.92f), new Vector3(-10, 0, 0), Vector3.one), 0.12f, 0.12f, 0.02f, 18, Color.white, true, true, Color.white);
            mb.AddTorus(M(new Vector3(0, 0.622f + nl * 0.5f, 0.922f), new Vector3(-10, 0, 0), Vector3.one), 0.12f, 0.012f, 18, 5, acc);
            // headlights
            if (!Lo)
            for (int s = -1; s <= 1; s += 2)
            {
                Ellipsoid(mb, new Vector3(s * 0.2f, 0.46f + nl, L - 0.2f), new Vector3(0.06f, 0.045f, 0.04f), H("#FFF6C8"), 6, 10);
                mb.AddTorus(Matrix4x4.TRS(new Vector3(s * 0.2f, 0.46f + nl, L - 0.215f), Quaternion.Euler(90, 0, 0), new Vector3(1f, 1f, 0.75f)), 0.06f, 0.012f, 12, 4, Chrome);
            }

            // --- front wing / bumper: airfoil plate + endplates
            var fw = new[]
            {
                S(-0.82f, 0.13f, 0.03f, 0f, acc, 2.4f),
                S(-0.7f, 0.15f, 0.035f, 0f, acc, 2.4f),
                S(0.7f, 0.15f, 0.035f, 0f, acc, 2.4f),
                S(0.82f, 0.13f, 0.03f, 0f, acc, 2.4f),
            };
            LoftAlong(mb, new Vector3(0, 0.3f, L - 0.02f), Vector3.right, Vector3.up, fw, 14);
            for (int s = -1; s <= 1; s += 2)
                mb.AddRoundedBox(M(new Vector3(s * 0.85f, 0.33f, L - 0.04f)), new Vector3(0.035f, 0.17f, 0.34f), 0.012f, body, 2, bodyLight);
            for (int s = -1; s <= 1; s += 2) Tube(mb, new Vector3(s * 0.16f, 0.35f + nl, L - 0.16f), new Vector3(s * 0.22f, 0.3f, L - 0.04f), 0.02f, Carbon, 6);

            // --- sidepods with intakes + accent flashes
            for (int s = -1; s <= 1; s += 2)
            {
                float pw = sh.PodW, ph = sh.PodH;
                var pod = new[]
                {
                    S(0.36f, pw * 0.55f, ph * 0.7f, 0.43f, body, 2.6f, s * 0.6f),
                    S(0.28f, pw * 0.95f, ph, 0.44f, body, 3.2f, s * 0.62f),
                    S(0.0f, pw, ph, 0.44f, body, 3.6f, s * 0.64f),
                    S(-0.28f, pw * 0.9f, ph * 0.95f, 0.45f, bodyDark, 3.4f, s * 0.6f),
                    S(-0.46f, pw * 0.55f, ph * 0.7f, 0.45f, bodyDark, 3f, s * 0.54f),
                };
                Loft(mb, Matrix4x4.identity, pod, 18);
                // intake mouth (dark recess + mesh bars)
                Ellipsoid(mb, new Vector3(s * 0.62f, 0.45f, 0.34f), new Vector3(pw * 0.7f, ph * 0.6f, 0.04f), Black, 6, 14);
                for (int k = -1; k <= 1 && !Lo; k++)
                    mb.AddBox(M(new Vector3(s * 0.62f, 0.45f + k * ph * 0.3f, 0.36f)), new Vector3(pw * 1.2f, 0.012f, 0.012f), Steel);
                // accent flash along the pod
                var flash = new[]
                {
                    S(0.24f, 0.012f, 0.03f, 0.47f, acc, 2f, s * (0.62f + pw * 0.98f)),
                    S(0.0f, 0.012f, 0.05f, 0.47f, acc, 2f, s * (0.64f + pw * 1.0f)),
                    S(-0.3f, 0.012f, 0.03f, 0.48f, acc, 2f, s * (0.6f + pw * 0.92f)),
                };
                Loft(mb, Matrix4x4.identity, flash, 6);
                // nerf bar between the wheels
                if (!Lo) mb.AddTube(Bezier(new Vector3(s * 0.62f, 0.3f, 0.4f), new Vector3(s * 0.86f, 0.31f, 0f), new Vector3(s * 0.62f, 0.32f, -0.42f), 8), Radii(8, 0.025f, 0.025f), 6, Chrome, null, false);
                if (sh.Fenders)
                {
                    // flared fenders over the front tyres
                    var fen = new[] { S(-0.32f, 0.2f, 0.03f, 0f, body, 2.2f), S(0f, 0.22f, 0.04f, 0.05f, bodyLight, 2.2f), S(0.32f, 0.2f, 0.03f, 0f, body, 2.2f) };
                    var q = Quaternion.Euler(0, 0, 0);
                    mb.AddLoft(Matrix4x4.TRS(WheelPos[s < 0 ? 0 : 1] + new Vector3(0, 0.36f, 0), q, Vector3.one), fen, 12);
                }
            }

            // --- suspension: A-arms, uprights, coil-over springs
            for (int w = 0; w < 4 && !Lo; w++)
            {
                Vector3 hub = WheelPos[w];
                int s = hub.x < 0 ? -1 : 1;
                float inner = w < 2 ? 0.3f : 0.36f;
                Vector3 hubIn = new Vector3(s * (Mathf.Abs(hub.x) - 0.2f), hub.y, hub.z);
                for (int arm = 0; arm < 2; arm++)
                {
                    float y = hub.y + (arm == 0 ? -0.06f : 0.07f);
                    Tube(mb, new Vector3(s * inner, y, hub.z + 0.14f), new Vector3(hubIn.x, y, hub.z), 0.018f, Steel, 6);
                    Tube(mb, new Vector3(s * inner, y, hub.z - 0.14f), new Vector3(hubIn.x, y, hub.z), 0.018f, Steel, 6);
                }
                mb.AddRoundedBox(M(hubIn), new Vector3(0.05f, 0.2f, 0.07f), 0.015f, Carbon, 1);
                // coil spring (helix) + damper
                Vector3 top = new Vector3(s * (inner + 0.02f), hub.y + 0.32f, hub.z + (w < 2 ? -0.08f : 0.1f));
                Vector3 bot = new Vector3(hubIn.x - s * 0.04f, hub.y + 0.04f, hub.z);
                Vector3 ax = (top - bot).normalized;
                Vector3 p1 = Vector3.Cross(ax, Vector3.forward).normalized, p2 = Vector3.Cross(ax, p1);
                int turns = 5, pts = turns * 8;
                var helix = new Vector3[pts];
                for (int k = 0; k < pts; k++)
                {
                    float t = k / (float)(pts - 1), a = t * turns * Mathf.PI * 2f;
                    helix[k] = Vector3.Lerp(bot, top, 0.1f + t * 0.8f) + (p1 * Mathf.Cos(a) + p2 * Mathf.Sin(a)) * 0.045f;
                }
                mb.AddTube(helix, Radii(pts, 0.01f, 0.01f), 3, acc, null, false);
                Tube(mb, bot, top, 0.016f, Chrome, 6);
            }

            // --- bucket seat + headrest + harness
            var seat = new[]
            {
                S(0f, 0.22f, 0.07f, 0f, Carbon, 2.4f),
                S(0.25f, 0.24f, 0.08f, 0.02f, Carbon, 2.6f),
                S(0.5f, 0.23f, 0.08f, 0.03f, Carbon, 2.6f),
                S(0.62f, 0.17f, 0.07f, 0.03f, Carbon, 2.4f),
            };
            LoftAlong(mb, new Vector3(0, 0.6f, -0.58f), new Vector3(0, 1f, -0.28f), Vector3.forward, seat, 16);
            for (int s = -1; s <= 1; s += 2)
                mb.AddRoundedBox(Matrix4x4.TRS(new Vector3(s * 0.23f, 0.82f, -0.62f), Quaternion.Euler(-16, s * 12, 0), Vector3.one), new Vector3(0.07f, 0.4f, 0.16f), 0.03f, Mul(acc, 0.8f), 2);
            mb.AddRoundedBox(Matrix4x4.TRS(new Vector3(0, 1.2f, -0.72f), Quaternion.Euler(-16, 0, 0), Vector3.one), new Vector3(0.3f, 0.2f, 0.1f), 0.045f, Mul(acc, 0.85f), 2);

            // --- steering column + wheel (torus rim, 3 spokes, hub badge)
            Vector3 swC = new Vector3(0, 0.84f, 0.2f);
            var swQ = Quaternion.Euler(-58, 0, 0);
            Tube(mb, new Vector3(0, 0.52f, 0.5f), swC + swQ * new Vector3(0, -0.03f, 0), 0.025f, Steel, 6);
            mb.AddTorus(Matrix4x4.TRS(swC, swQ, Vector3.one), 0.19f, 0.024f, 22, 6, Black);
            for (int k = 0; k < 3; k++)
            {
                var q = swQ * Quaternion.Euler(0, k * 120f + 90f, 0);
                mb.AddRoundedBox(Matrix4x4.TRS(swC + q * new Vector3(0.095f, 0, 0), q, Vector3.one), new Vector3(0.18f, 0.016f, 0.035f), 0.008f, Steel, 1);
            }
            mb.AddCylinder(Matrix4x4.TRS(swC, swQ, Vector3.one), 0.045f, 0.045f, 0.03f, 12, acc, true, true, acc);
            // dashboard gauge pod
            if (!Lo) mb.AddRoundedBox(Matrix4x4.TRS(new Vector3(0, 0.71f, 0.42f), Quaternion.Euler(-25, 0, 0), Vector3.one), new Vector3(0.36f, 0.08f, 0.14f), 0.03f, Carbon, 2);
            for (int s = -1; s <= 1 && !Lo; s += 2)
                mb.AddCylinder(Matrix4x4.TRS(new Vector3(s * 0.08f, 0.755f, 0.43f), Quaternion.Euler(-25, 0, 0), Vector3.one), 0.035f, 0.035f, 0.012f, 12, Color.white, true, true, H("#E8F4FF"));

            // --- engine: block, finned heads, intake trumpets or supercharger, belts
            Vector3 eng = new Vector3(0, 0.66f, -0.92f);
            mb.AddRoundedBox(M(eng), new Vector3(0.56f, 0.3f, 0.42f), 0.05f, H("#3A3B44"), 2);
            for (int s = -1; s <= 1; s += 2)
                for (int f = 0; f < (Lo ? 1 : 5); f++)
                    mb.AddBox(M(eng + new Vector3(s * 0.2f, 0.17f + f * 0.035f, 0)), new Vector3(0.2f, 0.014f, 0.38f - f * 0.03f), Steel);
            mb.AddRoundedBox(M(eng + new Vector3(0, 0.12f, 0.23f)), new Vector3(0.4f, 0.16f, 0.05f), 0.02f, Black, 1);
            if (sh.Supercharger)
            {
                mb.AddRoundedBox(M(eng + new Vector3(0, 0.36f, 0.02f)), new Vector3(0.3f, 0.16f, 0.36f), 0.05f, Chrome, 2);
                var scoop = new[] { S(0f, 0.12f, 0.06f, 0f, acc, 3f), S(0.14f, 0.13f, 0.08f, 0.01f, acc, 3f), S(0.22f, 0.1f, 0.06f, 0f, Black, 3f) };
                mb.AddLoft(M(eng + new Vector3(0, 0.5f, -0.08f)), scoop, 14);
                mb.AddTorus(Matrix4x4.TRS(eng + new Vector3(0, 0.2f, 0.25f), Quaternion.Euler(90, 0, 0), new Vector3(1f, 1f, 1.8f)), 0.09f, 0.012f, 16, 4, Black);
            }
            else
            {
                Vector2[] trumpet = { new Vector2(0.035f, 0f), new Vector2(0.032f, 0.08f), new Vector2(0.04f, 0.14f), new Vector2(0.06f, 0.17f), new Vector2(0.065f, 0.18f) };
                var tcol = new[] { Chrome, Chrome, Chrome, Chrome, Mul(Chrome, 0.7f) };
                for (int s = -1; s <= 1; s += 2)
                    for (int k = 0; k < 2; k++)
                        mb.AddLathe(M(eng + new Vector3(s * 0.09f, 0.16f, -0.08f + k * 0.16f)), trumpet, 12, tcol);
            }
            // radiator + fan grille at the back
            mb.AddRoundedBox(M(new Vector3(0, 0.56f, -1.18f)), new Vector3(0.5f, 0.18f, 0.04f), 0.015f, Carbon, 1);
            for (int k = 0; k < (Lo ? 0 : 6); k++)
                mb.AddBox(M(new Vector3(-0.2f + k * 0.08f, 0.56f, -1.2f)), new Vector3(0.012f, 0.15f, 0.01f), Steel);

            // --- exhausts: curved headers to flared chrome tips
            for (int s = -1; s <= 1; s += 2)
            {
                Vector3 tip = ExhaustTips[s < 0 ? 0 : 1];
                var path = Bezier(eng + new Vector3(s * 0.28f, 0.02f, -0.05f), eng + new Vector3(s * 0.46f, -0.02f, -0.32f), tip - new Vector3(0, 0, -0.06f), 10);
                mb.AddTube(path, Radii(10, 0.045f, 0.05f), 10, Chrome, Mul(Chrome, 0.75f), false);
                Vector2[] flare = { new Vector2(0.05f, 0f), new Vector2(0.06f, 0.06f), new Vector2(0.075f, 0.11f), new Vector2(0.05f, 0.115f), new Vector2(0.04f, 0.05f) };
                var fcol = new[] { Chrome, Chrome, Mul(Chrome, 1.1f), Black, Black };
                Vector3 d = (tip - path[7]).normalized;
                mb.AddLathe(Matrix4x4.TRS(tip - d * 0.06f, Quaternion.FromToRotation(Vector3.up, d), Vector3.one), flare, 14, fcol);
            }

            // --- rear wing: airfoil, endplates, swan-neck struts (+ fins on the speed kart)
            var wing = new[]
            {
                S(-sh.WingW * 0.5f, 0.17f, 0.03f, 0f, acc, 2.2f),
                S(-sh.WingW * 0.47f, 0.19f, 0.035f, 0f, acc, 2.2f),
                S(sh.WingW * 0.47f, 0.19f, 0.035f, 0f, acc, 2.2f),
                S(sh.WingW * 0.5f, 0.17f, 0.03f, 0f, acc, 2.2f),
            };
            Vector3 wc = new Vector3(0, sh.WingH, -1.08f);
            var wq = Quaternion.LookRotation(Vector3.right, Quaternion.Euler(-12, 0, 0) * Vector3.up);
            mb.AddLoft(Matrix4x4.TRS(wc, wq, Vector3.one), wing, 14);
            var flap = new[] { S(-sh.WingW * 0.46f, 0.07f, 0.015f, 0f, body, 2.2f), S(sh.WingW * 0.46f, 0.07f, 0.015f, 0f, body, 2.2f) };
            mb.AddLoft(Matrix4x4.TRS(wc + new Vector3(0, 0.07f, -0.17f), Quaternion.LookRotation(Vector3.right, Quaternion.Euler(-30, 0, 0) * Vector3.up), Vector3.one), flap, 10);
            for (int s = -1; s <= 1; s += 2)
            {
                mb.AddRoundedBox(M(wc + new Vector3(s * sh.WingW * 0.5f, -0.04f, -0.02f)), new Vector3(0.03f, 0.3f, 0.48f), 0.012f, body, 2, bodyLight);
                mb.AddTube(Bezier(eng + new Vector3(s * 0.16f, 0.12f, -0.12f), new Vector3(s * 0.2f, wc.y - 0.02f, eng.z - 0.05f), wc + new Vector3(s * 0.2f, 0.03f, 0.04f), 8), Radii(8, 0.022f, 0.018f), 6, Carbon, null, false);
                if (sh.Fins)
                    mb.AddRoundedBox(Matrix4x4.TRS(new Vector3(s * 0.22f, 0.78f, -0.98f), Quaternion.Euler(0, 0, s * 8), Vector3.one), new Vector3(0.02f, 0.2f, 0.38f), 0.008f, acc, 1);
            }
            // rear bumper bar
            mb.AddTube(Bezier(new Vector3(-0.5f, 0.33f, -1.12f), new Vector3(0, 0.3f, -1.42f), new Vector3(0.5f, 0.33f, -1.12f), 12), Radii(12, 0.03f, 0.03f), 8, Chrome, null, false);
            // axles
            Tube(mb, new Vector3(-0.58f, 0.4f, -0.68f), new Vector3(0.58f, 0.4f, -0.68f), 0.03f, Steel, 8);
            // tow hook / fuel cap
            mb.AddCylinder(M(new Vector3(0.24f, 0.655f, -0.45f)), 0.04f, 0.04f, 0.02f, 12, Chrome);
        }

        // ================================================================== driver
        static Color EyeColor(HeadStyle s)
        {
            switch (s)
            {
                case HeadStyle.Fox: return H("#F5A623");
                case HeadStyle.Bear: return H("#7A4A22");
                case HeadStyle.Rabbit: return H("#B05CFF");
                case HeadStyle.Croc: return H("#C9E032");
                case HeadStyle.Penguin: return H("#2F8CFF");
                case HeadStyle.Raccoon: return H("#5A3A22");
                case HeadStyle.Tiger: return H("#3FBF5A");
                default: return H("#4FC3FF");
            }
        }

        public static void BuildDriver(MeshBuilder mb, CharacterDef ch)
        {
            Color fur = ch.Fur, light = ch.FurLight, shirt = ch.Shirt, shirtDark = Mul(ch.Shirt, 0.72f);
            Color glove = ch.Style == HeadStyle.Penguin ? H("#FF9A1E") : Color.Lerp(ch.KartAccent, Color.white, 0.15f);
            Color pants = H("#2C3040");
            if (ch.Style == HeadStyle.Penguin) { fur = H("#23253A"); }

            // ---------------- torso (lofted, leaning forward) -------------
            Vector3 hip = new Vector3(0, 0.6f, -0.36f);
            float lean = 14f;
            var torsoQ = Quaternion.Euler(-90 + lean, 0, 0);       // loft Z -> up (leaning forward)
            var torso = new[]
            {
                S(0f, 0.25f, 0.17f, 0f, pants, 2.4f),
                S(0.1f, 0.24f, 0.17f, 0f, shirtDark, 2.4f),
                S(0.24f, 0.225f, 0.16f, -0.01f, shirt, 2.3f),
                S(0.4f, 0.26f, 0.18f, -0.02f, shirt, 2.4f),
                S(0.52f, 0.29f, 0.17f, -0.02f, shirt, 2.6f),
                S(0.6f, 0.25f, 0.14f, -0.01f, shirt, 2.4f),
                S(0.66f, 0.12f, 0.1f, 0f, shirtDark, 2.2f),
            };
            mb.AddLoft(Matrix4x4.TRS(hip, torsoQ, Vector3.one), torso, 22);
            Vector3 up = torsoQ * Vector3.forward, back = torsoQ * Vector3.up; // loft H axis points backwards
            Vector3 chestFront = hip + up * 0.42f - back * 0.17f;
            // jacket details: zip, collar, chest badge, shoulder pads
            if (!Lo) mb.AddTube(new[] { hip + up * 0.12f - back * 0.168f, hip + up * 0.3f - back * 0.165f, hip + up * 0.46f - back * 0.178f, hip + up * 0.62f - back * 0.13f }, Radii(4, 0.008f, 0.008f), 4, Chrome, null, false);
            mb.AddTorus(Matrix4x4.TRS(hip + up * 0.64f, torsoQ * Quaternion.Euler(90, 0, 0), new Vector3(1.15f, 1f, 0.9f)), 0.1f, 0.03f, 16, 6, shirtDark);
            mb.AddCylinder(Matrix4x4.TRS(chestFront + new Vector3(0.1f, 0, 0) - back * 0.01f, Quaternion.LookRotation(up, -back) * Quaternion.Euler(90, 0, 0), Vector3.one), 0.045f, 0.045f, 0.012f, 12, ch.KartAccent, true, true, ch.KartAccent);
            if (ch.Style == HeadStyle.Penguin || ch.Style == HeadStyle.Yeti || ch.Style == HeadStyle.Bear)
                Ellipsoid(mb, chestFront + up * 0.02f - back * 0.012f, new Vector3(0.12f, 0.15f, 0.04f), Quaternion.LookRotation(-back, up), light, 8, 12); // fluffy chest
            // belt + buckle
            mb.AddTorus(Matrix4x4.TRS(hip + up * 0.1f, torsoQ * Quaternion.Euler(90, 0, 0), new Vector3(1.0f, 1f, 0.7f)), 0.24f, 0.022f, 20, 5, Black);
            mb.AddRoundedBox(Matrix4x4.TRS(hip + up * 0.1f - back * 0.175f, Quaternion.LookRotation(-back, up), Vector3.one), new Vector3(0.07f, 0.05f, 0.02f), 0.008f, Chrome, 1);

            // ---------------- legs (thighs into the footwell, knees up) -------------
            for (int s = -1; s <= 1; s += 2)
            {
                Vector3 h0 = hip + new Vector3(s * 0.12f, 0.02f, 0.06f);
                Vector3 knee = new Vector3(s * 0.17f, 0.76f, 0.18f);
                Vector3 foot = new Vector3(s * 0.15f, 0.45f, 0.62f);
                mb.AddTube(Bezier(h0, (h0 + knee) * 0.5f + Vector3.up * 0.03f, knee, 6), Radii(6, 0.1f, 0.095f, 0.075f), 10, pants);
                Ellipsoid(mb, knee, Vector3.one * 0.078f, Mul(pants, 1.1f), 6, 10);
                mb.AddTube(Bezier(knee, (knee + foot) * 0.5f, foot, 5), Radii(5, 0.07f, 0.06f), 8, pants);
            }

            // ---------------- arms (shoulder -> elbow -> wrist) + gloves wrapped on the wheel -------------
            Vector3 swC = new Vector3(0, 0.84f, 0.2f);
            var swQ = Quaternion.Euler(-58, 0, 0);
            for (int s = -1; s <= 1; s += 2)
            {
                Vector3 shoulder = hip + up * 0.55f + new Vector3(s * 0.27f, 0, 0) - back * 0.01f;
                Vector3 grip = swC + swQ * new Vector3(s * 0.17f, 0, 0.07f);          // 10/2 o'clock on the rim
                Vector3 elbow = Vector3.Lerp(shoulder, grip, 0.5f) + new Vector3(s * 0.12f, -0.1f, -0.02f);
                Ellipsoid(mb, shoulder, new Vector3(0.105f, 0.1f, 0.11f), shirt, 8, 12);       // deltoid / shoulder pad
                mb.AddTube(Bezier(shoulder, Vector3.Lerp(shoulder, elbow, 0.5f) + new Vector3(s * 0.015f, 0, 0), elbow, 6), Radii(6, 0.085f, 0.088f, 0.072f), 10, shirt);
                mb.AddTorus(Matrix4x4.TRS(Vector3.Lerp(shoulder, elbow, 0.82f), Quaternion.FromToRotation(Vector3.up, elbow - shoulder), Vector3.one), 0.074f, 0.016f, 14, 4, shirtDark); // sleeve cuff
                Ellipsoid(mb, elbow, Vector3.one * 0.07f, fur, 6, 10);
                Vector3 wrist = grip + (elbow - grip).normalized * 0.09f;
                mb.AddTube(Bezier(elbow, Vector3.Lerp(elbow, wrist, 0.45f) + Vector3.up * 0.012f, wrist, 6), Radii(6, 0.066f, 0.07f, 0.052f), 10, fur);
                // glove: cuff, palm, four curled fingers, thumb over the top
                Vector3 fwdHand = (grip - wrist).normalized;
                mb.AddCylinder(Matrix4x4.TRS(wrist - fwdHand * 0.02f, Quaternion.FromToRotation(Vector3.up, fwdHand), Vector3.one), 0.064f, 0.058f, 0.06f, 12, glove, false);
                Ellipsoid(mb, grip - fwdHand * 0.02f, new Vector3(0.06f, 0.045f, 0.065f), Quaternion.LookRotation(fwdHand, swQ * Vector3.up), glove, 8, 12);
                Vector3 rimTan = swQ * new Vector3(0, 0, 1);                          // along the rim at the grip point
                Vector3 rimOut = (grip - swC).normalized;
                Vector3 rimNrm = swQ * Vector3.up;                                     // wheel face normal (towards driver/up)
                for (int f = 0; f < (Lo ? 0 : 4); f++)
                {
                    Vector3 kn = grip + rimTan * (-0.045f + f * 0.03f) + rimNrm * 0.03f;
                    var path = new[] { kn, kn + rimOut * 0.035f + rimNrm * 0.005f, kn + rimOut * 0.04f - rimNrm * 0.045f, kn + rimOut * 0.005f - rimNrm * 0.06f };
                    mb.AddTube(path, Radii(4, 0.016f, 0.015f, 0.013f), 5, glove);
                }
                Vector3 th = grip - rimTan * 0.055f + rimNrm * 0.035f;
                if (!Lo) mb.AddTube(new[] { th - rimOut * 0.03f, th, th + rimOut * 0.02f + rimNrm * 0.015f }, Radii(3, 0.019f, 0.016f), 6, glove);
            }

            // ---------------- neck + head -------------
            Vector3 neckBase = hip + up * 0.62f;
            Vector3 head = new Vector3(0, 1.5f, -0.06f);
            mb.AddTube(new[] { neckBase, Vector3.Lerp(neckBase, head, 0.6f) }, new[] { 0.085f, 0.08f }, 10, fur, null, false);
            BuildHead(mb, ch, head, fur, light);

            // ---------------- scarf (two flowing tails) -------------
            Color scarf = ch.KartAccent;
            mb.AddTorus(Matrix4x4.TRS(neckBase + up * 0.03f, torsoQ * Quaternion.Euler(90, 0, 0), new Vector3(1.1f, 1f, 1f)), 0.1f, 0.04f, 16, 6, scarf);
            for (int s = -1; s <= 1 && !Lo; s += 2)
            {
                Vector3 a = neckBase + up * 0.02f + back * 0.09f + new Vector3(s * 0.05f, 0, 0);
                var tail = Bezier(a, a + back * 0.2f + Vector3.up * 0.05f + new Vector3(s * 0.08f, 0, 0), a + back * 0.45f + new Vector3(s * 0.12f, -0.12f, 0) + Vector3.up * (s > 0 ? 0.08f : -0.02f), 7);
                mb.AddTube(tail, Radii(7, 0.045f, 0.04f, 0.03f), 6, scarf, Mul(scarf, 0.8f));
            }

            // ---------------- tail behind the seat -------------
            BuildTail(mb, ch, fur, light);
        }

        static void BuildTail(MeshBuilder mb, CharacterDef ch, Color fur, Color light)
        {
            Vector3 root = new Vector3(0, 0.74f, -0.66f);
            switch (ch.Style)
            {
                case HeadStyle.Fox:
                    {
                        var p = Bezier(root, root + new Vector3(0.2f, 0.12f, -0.3f), root + new Vector3(0.36f, 0.42f, -0.42f), 10);
                        mb.AddTube(p, Radii(10, 0.05f, 0.12f, 0.14f, 0.1f, 0.02f), 12, fur, light);
                        break;
                    }
                case HeadStyle.Raccoon:
                    {
                        var p = Bezier(root, root + new Vector3(0.24f, 0.08f, -0.26f), root + new Vector3(0.34f, 0.36f, -0.38f), 12);
                        var r = Radii(12, 0.05f, 0.1f, 0.11f, 0.09f, 0.03f);
                        for (int k = 0; k < 11; k++)
                            mb.AddTube(new[] { p[k], p[k + 1] }, new[] { r[k], r[k + 1] }, 10, k % 2 == 0 ? fur : H("#2A2A33"), null, k == 10);
                        break;
                    }
                case HeadStyle.Tiger:
                    {
                        var p = Bezier(root, root + new Vector3(0.3f, -0.02f, -0.3f), root + new Vector3(0.4f, 0.36f, -0.3f), 12);
                        var r = Radii(12, 0.045f, 0.04f, 0.035f);
                        for (int k = 0; k < 11; k++)
                            mb.AddTube(new[] { p[k], p[k + 1] }, new[] { r[k], r[k + 1] }, 8, k % 3 == 1 ? H("#1A1A1A") : fur, null, k == 10);
                        break;
                    }
                case HeadStyle.Croc:
                    {
                        var p = Bezier(root + new Vector3(0, -0.06f, 0), root + new Vector3(0.1f, -0.1f, -0.35f), root + new Vector3(0.3f, -0.08f, -0.55f), 10);
                        mb.AddTube(p, Radii(10, 0.11f, 0.08f, 0.02f), 10, fur, light);
                        for (int k = 1; k < 8; k++)
                            mb.AddCone(Matrix4x4.TRS(p[k] + Vector3.up * Radii(10, 0.11f, 0.08f, 0.02f)[k] * 0.8f, Quaternion.identity, Vector3.one), 0.02f, 0.05f, 4, Mul(fur, 0.8f), Mul(fur, 0.8f));
                        break;
                    }
                case HeadStyle.Rabbit:
                    Ellipsoid(mb, root + new Vector3(0, 0.02f, -0.06f), Vector3.one * 0.09f, Color.white, 8, 12);
                    break;
                case HeadStyle.Bear:
                    Ellipsoid(mb, root + new Vector3(0, 0.0f, -0.05f), Vector3.one * 0.06f, fur, 6, 10);
                    break;
                case HeadStyle.Yeti:
                    {
                        var p = Bezier(root, root + new Vector3(0.12f, 0.1f, -0.22f), root + new Vector3(0.2f, 0.28f, -0.3f), 8);
                        mb.AddTube(p, Radii(8, 0.06f, 0.1f, 0.07f, 0.02f), 10, fur, light);
                        break;
                    }
            }
        }

        // ================================================================== head
        static void BuildHead(MeshBuilder mb, CharacterDef ch, Vector3 head, Color fur, Color light)
        {
            var st = ch.Style;
            Color nose = H("#1C1A20"), mouthCol = H("#5A1E2A"), tongue = H("#E5646E"), teeth = H("#FFFDF4"), brow = Mul(fur, 0.55f);
            Color eyeWhite = H("#FBFCFF"), iris = EyeColor(st), pupil = H("#0D0D12");
            Color headCol = fur;
            float hr = 0.34f;
            Vector3 hs = new Vector3(1.06f, 0.98f, 1.0f);
            if (st == HeadStyle.Bear || st == HeadStyle.Yeti) hs = new Vector3(1.12f, 1.0f, 1.0f);
            if (st == HeadStyle.Croc) hs = new Vector3(0.96f, 0.86f, 1.05f);

            // cranium + cheeks (fuller lower face)
            Ellipsoid(mb, head, hs * hr, headCol, 14, 22, Mul(headCol, 0.88f));
            for (int s = -1; s <= 1; s += 2)
                Ellipsoid(mb, head + new Vector3(s * 0.16f, -0.12f, 0.12f), new Vector3(0.15f, 0.13f, 0.14f), Color.Lerp(headCol, light, st == HeadStyle.Fox || st == HeadStyle.Raccoon || st == HeadStyle.Tiger ? 0.85f : 0.2f), 10, 14);

            // muzzle / snout
            Vector3 muzzle = head + new Vector3(0, -0.1f, 0.27f);
            Vector3 noseTip;
            switch (st)
            {
                case HeadStyle.Fox:
                    Ellipsoid(mb, muzzle + new Vector3(0, 0.0f, 0.06f), new Vector3(0.12f, 0.1f, 0.2f), Quaternion.Euler(-8, 0, 0), light, 12, 16);
                    noseTip = muzzle + new Vector3(0, 0.04f, 0.26f);
                    break;
                case HeadStyle.Croc:
                    // long snout: upper jaw + lower jaw with a toothy grin
                    var upper = new[] { S(0f, 0.2f, 0.11f, 0f, fur, 2.4f), S(0.18f, 0.16f, 0.09f, 0.0f, fur, 2.6f), S(0.36f, 0.13f, 0.07f, -0.01f, fur, 2.6f), S(0.46f, 0.1f, 0.05f, -0.02f, light, 2.4f) };
                    mb.AddLoft(M(head + new Vector3(0, -0.04f, 0.16f)), upper, 18);
                    var lower = new[] { S(0f, 0.17f, 0.06f, 0f, light, 2.4f), S(0.3f, 0.12f, 0.045f, 0f, light, 2.6f), S(0.42f, 0.08f, 0.03f, 0f, light, 2.4f) };
                    mb.AddLoft(M(head + new Vector3(0, -0.17f, 0.16f)), lower, 16);
                    for (int s = -1; s <= 1; s += 2)
                        for (int k = 0; k < 6; k++)
                        {
                            float z = 0.2f + k * 0.055f;
                            float x = s * (0.15f - k * 0.012f);
                            mb.AddCone(Matrix4x4.TRS(head + new Vector3(x, -0.12f, z), Quaternion.Euler(180, 0, 0), Vector3.one), 0.016f, 0.045f, 4, teeth, teeth);
                        }
                    noseTip = head + new Vector3(0, 0.02f, 0.6f);
                    for (int s = -1; s <= 1; s += 2) Ellipsoid(mb, noseTip + new Vector3(s * 0.045f, 0.01f, -0.02f), new Vector3(0.022f, 0.02f, 0.025f), nose, 5, 8);
                    break;
                case HeadStyle.Penguin:
                    // white face mask + two-part beak
                    Ellipsoid(mb, head + new Vector3(0, -0.03f, 0.12f), new Vector3(0.27f, 0.26f, 0.24f), light, 12, 18);
                    var beakU = new[] { S(0f, 0.09f, 0.04f, 0f, H("#FF9A1E"), 2.4f), S(0.12f, 0.05f, 0.03f, -0.01f, H("#FFB74D"), 2.4f), S(0.2f, 0.012f, 0.012f, -0.03f, H("#FFB74D"), 2f) };
                    mb.AddLoft(M(head + new Vector3(0, -0.06f, 0.33f)), beakU, 14);
                    var beakL = new[] { S(0f, 0.07f, 0.025f, 0f, H("#E07B12"), 2.4f), S(0.13f, 0.03f, 0.015f, 0f, H("#E07B12"), 2.4f) };
                    mb.AddLoft(M(head + new Vector3(0, -0.11f, 0.33f)), beakL, 12);
                    noseTip = head + new Vector3(0, -0.05f, 0.53f);
                    break;
                default:
                    Ellipsoid(mb, muzzle, new Vector3(st == HeadStyle.Bear ? 0.17f : 0.14f, 0.11f, 0.13f), light, 12, 16);
                    noseTip = muzzle + new Vector3(0, 0.05f, 0.12f);
                    break;
            }
            if (st != HeadStyle.Penguin && st != HeadStyle.Croc)
            {
                Color nc = st == HeadStyle.Rabbit ? H("#FF7FA8") : st == HeadStyle.Tiger ? H("#D96A6A") : st == HeadStyle.Yeti ? H("#3B5B8C") : nose;
                Ellipsoid(mb, noseTip, new Vector3(0.055f, 0.04f, 0.04f), nc, 8, 12);
                Ellipsoid(mb, noseTip + new Vector3(-0.015f, 0.018f, 0.025f), Vector3.one * 0.012f, Color.white, 3, 6);   // wet-nose highlight
                // philtrum + smiling mouth with tongue
                Vector3 mo = noseTip + new Vector3(0, -0.075f, -0.03f);
                Tube(mb, noseTip + new Vector3(0, -0.03f, 0), mo, 0.008f, Mul(mouthCol, 0.8f), 4);
                for (int s = -1; s <= 1; s += 2)
                    mb.AddTube(Bezier(mo, mo + new Vector3(s * 0.06f, -0.02f, -0.01f), mo + new Vector3(s * 0.11f, 0.03f, -0.06f), 6), Radii(6, 0.012f, 0.01f), 5, mouthCol);
                Ellipsoid(mb, mo + new Vector3(0, -0.025f, -0.015f), new Vector3(0.055f, 0.03f, 0.025f), mouthCol, 6, 10);
                Ellipsoid(mb, mo + new Vector3(0, -0.035f, -0.005f), new Vector3(0.035f, 0.015f, 0.02f), tongue, 5, 8);
                if (st == HeadStyle.Rabbit)
                    for (int s = -1; s <= 1; s += 2)
                        mb.AddRoundedBox(M(mo + new Vector3(s * 0.016f, -0.022f, 0.012f)), new Vector3(0.028f, 0.042f, 0.012f), 0.006f, teeth, 1);
                if (st == HeadStyle.Tiger || st == HeadStyle.Bear || st == HeadStyle.Yeti || st == HeadStyle.Fox)
                    for (int s = -1; s <= 1; s += 2)
                        mb.AddCone(Matrix4x4.TRS(mo + new Vector3(s * 0.04f, -0.008f, 0.008f), Quaternion.Euler(180, 0, 0), Vector3.one), 0.011f, st == HeadStyle.Tiger ? 0.04f : 0.025f, 5, teeth, teeth);
                // whiskers
                if (!Lo && (st == HeadStyle.Tiger || st == HeadStyle.Fox || st == HeadStyle.Raccoon || st == HeadStyle.Rabbit))
                    for (int s = -1; s <= 1; s += 2)
                        for (int k = 0; k < 3; k++)
                        {
                            Vector3 a = noseTip + new Vector3(s * 0.07f, -0.03f - k * 0.015f, -0.05f);
                            mb.AddTube(Bezier(a, a + new Vector3(s * 0.1f, 0.01f - k * 0.01f, 0.0f), a + new Vector3(s * 0.2f, -0.01f - k * 0.025f, -0.03f), 4), Radii(4, 0.005f, 0.002f), 3, H("#F4F4F4"), null, false);
                        }
            }

            // eyes: sclera, iris, pupil, two highlights, upper lids (determined look) + lower lid line
            float eyeY = 0.065f, eyeZ = 0.245f, eyeX = 0.13f, eyeR = 0.118f;
            if (st == HeadStyle.Croc) { eyeY = 0.2f; eyeZ = 0.14f; eyeX = 0.14f; }
            if (st == HeadStyle.Penguin) { eyeY = 0.07f; eyeZ = 0.3f; eyeX = 0.11f; eyeR = 0.09f; }
            for (int s = -1; s <= 1; s += 2)
            {
                Vector3 e = head + new Vector3(s * eyeX, eyeY, eyeZ);
                var eq = Quaternion.Euler(-4, s * 14f, 0);
                if (st == HeadStyle.Croc) Ellipsoid(mb, e + new Vector3(0, -0.02f, -0.02f), new Vector3(0.12f, 0.1f, 0.11f), fur, 8, 12);   // croc eye bump
                if (st == HeadStyle.Raccoon) Ellipsoid(mb, e + new Vector3(s * 0.01f, 0, -0.04f), new Vector3(0.15f, 0.11f, 0.09f), H("#2A2A33"), 8, 12);  // bandit mask
                Ellipsoid(mb, e, new Vector3(eyeR * 0.85f, eyeR * 1.1f, eyeR * 0.6f), eq, eyeWhite, 10, 14);
                Vector3 front = eq * Vector3.forward;
                Vector3 irisC = e + front * eyeR * 0.5f + new Vector3(-s * 0.008f, -0.006f, 0);
                Ellipsoid(mb, irisC, new Vector3(eyeR * 0.55f, eyeR * 0.68f, eyeR * 0.14f), eq, iris, 8, 12, Mul(iris, 0.62f));
                Ellipsoid(mb, irisC + front * eyeR * 0.06f, new Vector3(eyeR * 0.3f, eyeR * 0.4f, eyeR * 0.1f), eq, pupil, 6, 10);
                Ellipsoid(mb, irisC + front * eyeR * 0.13f + new Vector3(s * 0.012f, 0.022f, 0), Vector3.one * eyeR * 0.13f, Color.white, 4, 8);
                if (!Lo) Ellipsoid(mb, irisC + front * eyeR * 0.12f + new Vector3(-s * 0.012f, -0.018f, 0), Vector3.one * eyeR * 0.06f, Color.white, 3, 6);
                // upper lid: a slightly bigger shell tilted down toward the nose
                Ellipsoid(mb, e + new Vector3(0, eyeR * 0.78f, -eyeR * 0.1f), new Vector3(eyeR * 0.98f, eyeR * 0.42f, eyeR * 0.68f), Quaternion.Euler(-10, s * 14f, s * -12f), st == HeadStyle.Penguin ? light : Mul(headCol, 0.95f), 6, 12);
                // brow (angled, determined)
                Vector3 b0 = e + new Vector3(s * 0.08f, eyeR * 1.42f, -0.02f), b1 = e + new Vector3(-s * 0.06f, eyeR * 1.2f, 0.04f);
                mb.AddTube(Bezier(b0, (b0 + b1) * 0.5f + new Vector3(0, 0.02f, 0.01f), b1, 5), Radii(5, 0.012f, 0.022f, 0.014f), 6, st == HeadStyle.Penguin ? Mul(light, 0.7f) : brow);
            }

            // ears / horns / crests
            switch (st)
            {
                case HeadStyle.Fox:
                    for (int s = -1; s <= 1; s += 2) Ear(mb, head + new Vector3(s * 0.2f, 0.22f, -0.04f), new Vector3(s * 0.45f, 1f, -0.1f), 0.34f, 0.15f, fur, H("#FFE4C4"), H("#2A1A10"));
                    // cheek fur tufts
                    for (int s = -1; s <= 1; s += 2)
                        for (int k = 0; k < 3; k++)
                            mb.AddCone(Matrix4x4.TRS(head + new Vector3(s * 0.27f, -0.12f - k * 0.04f, 0.05f), Quaternion.Euler(0, 0, s * (70 + k * 15)), Vector3.one), 0.045f, 0.11f, 5, light, light);
                    break;
                case HeadStyle.Bear:
                    for (int s = -1; s <= 1; s += 2)
                    {
                        Ellipsoid(mb, head + new Vector3(s * 0.27f, 0.25f, -0.02f), new Vector3(0.11f, 0.11f, 0.06f), fur, 8, 12);
                        Ellipsoid(mb, head + new Vector3(s * 0.27f, 0.25f, 0.02f), new Vector3(0.065f, 0.065f, 0.035f), light, 6, 10);
                    }
                    break;
                case HeadStyle.Rabbit:
                    for (int s = -1; s <= 1; s += 2) Ear(mb, head + new Vector3(s * 0.11f, 0.26f, -0.06f), new Vector3(s * 0.18f, 1f, -0.2f), 0.55f, 0.11f, fur, light, fur);
                    break;
                case HeadStyle.Croc:
                    for (int k = 0; k < 4; k++)
                        mb.AddCone(Matrix4x4.TRS(head + new Vector3(0, 0.27f - k * 0.04f, -0.06f - k * 0.1f), Quaternion.Euler(-30 - k * 12, 0, 0), Vector3.one), 0.05f, 0.12f, 5, Mul(fur, 0.8f), Mul(fur, 0.65f));
                    break;
                case HeadStyle.Penguin:
                    for (int k = 0; k < 4; k++)
                        mb.AddCone(Matrix4x4.TRS(head + new Vector3(-0.03f + k * 0.02f, 0.3f, -0.02f - k * 0.03f), Quaternion.Euler(-20 - k * 10, 0, (k - 1.5f) * 12), Vector3.one), 0.025f, 0.12f, 4, H("#FFD23F"), H("#FF9A1E"));
                    break;
                case HeadStyle.Raccoon:
                    for (int s = -1; s <= 1; s += 2) Ear(mb, head + new Vector3(s * 0.21f, 0.23f, -0.04f), new Vector3(s * 0.55f, 1f, 0f), 0.2f, 0.12f, fur, H("#E9EAF0"), H("#2A2A33"));
                    break;
                case HeadStyle.Tiger:
                    for (int s = -1; s <= 1; s += 2)
                    {
                        Ellipsoid(mb, head + new Vector3(s * 0.25f, 0.25f, -0.03f), new Vector3(0.1f, 0.1f, 0.05f), fur, 8, 12);
                        Ellipsoid(mb, head + new Vector3(s * 0.25f, 0.25f, 0.01f), new Vector3(0.06f, 0.06f, 0.03f), light, 6, 10);
                        // stripes on the cranium + cheeks
                        for (int k = 0; k < 3; k++)
                        {
                            Vector3 a = head + new Vector3(s * (0.3f + k * 0.01f), 0.1f - k * 0.08f, 0.02f + k * 0.03f);
                            mb.AddTube(Bezier(a, a + new Vector3(-s * 0.06f, 0.02f, 0.05f), a + new Vector3(-s * 0.1f, 0.0f, 0.1f), 4), Radii(4, 0.018f, 0.004f), 4, H("#1A1A1A"), null, false);
                        }
                    }
                    for (int k = 0; k < 3; k++)
                    {
                        Vector3 a = head + new Vector3(-0.08f + k * 0.08f, 0.33f, 0.04f);
                        mb.AddTube(Bezier(a, a + new Vector3(0, 0.0f, 0.08f), a + new Vector3(0, -0.06f, 0.14f), 4), Radii(4, 0.02f, 0.004f), 4, H("#1A1A1A"), null, false);
                    }
                    break;
                case HeadStyle.Yeti:
                    for (int s = -1; s <= 1; s += 2)
                        mb.AddTube(Bezier(head + new Vector3(s * 0.24f, 0.2f, -0.04f), head + new Vector3(s * 0.42f, 0.3f, -0.06f), head + new Vector3(s * 0.4f, 0.48f, 0.02f), 7), Radii(7, 0.06f, 0.035f, 0.01f), 8, H("#E6E2D3"), H("#B8AE90"));
                    for (int k = 0; k < 9; k++)
                    {
                        float a = k / 8f * Mathf.PI;
                        mb.AddCone(Matrix4x4.TRS(head + new Vector3(Mathf.Cos(a) * 0.22f, 0.27f + Mathf.Sin(a) * 0.06f, 0.06f + Mathf.Sin(a) * 0.05f), Quaternion.Euler(-20, 0, (k - 4) * -16f), Vector3.one), 0.05f, 0.13f, 5, fur, light);
                    }
                    break;
            }

            // racing goggles pushed up on the forehead (not for croc / penguin crest)
            if (st != HeadStyle.Croc && st != HeadStyle.Penguin)
            {
                mb.AddTorus(Matrix4x4.TRS(head + new Vector3(0, 0.17f, -0.02f), Quaternion.Euler(-16, 0, 0), new Vector3(hs.x * 0.93f, 1f, 0.92f)), hr, 0.017f, 26, 5, H("#26262E"));
                for (int s = -1; s <= 1; s += 2)
                {
                    Vector3 g = head + new Vector3(s * 0.1f, 0.24f, 0.24f);
                    var gq = Quaternion.Euler(-60, s * 16f, 0);
                    mb.AddTorus(Matrix4x4.TRS(g, gq, Vector3.one), 0.07f, 0.02f, 16, 5, ch.KartAccent);
                    Ellipsoid(mb, g + gq * new Vector3(0, 0.005f, 0), new Vector3(0.07f, 0.02f, 0.07f), gq, Glass, 6, 12, Mul(Glass, 0.6f));
                    Ellipsoid(mb, g + gq * new Vector3(0.02f, 0.022f, 0.02f), Vector3.one * 0.012f, Color.white, 3, 6);
                }
            }
        }

        /// <summary>Lofted ear: flattened cone with an inner panel and an optional dark tip.</summary>
        static void Ear(MeshBuilder mb, Vector3 root, Vector3 dir, float len, float width, Color outer, Color inner, Color tip)
        {
            Vector3 d = dir.normalized;
            Vector3 faceUp = Vector3.Cross(d, Vector3.right).sqrMagnitude > 0.01f ? Vector3.Cross(Vector3.right, d) : Vector3.forward;
            if (Vector3.Dot(faceUp, Vector3.back) > 0) faceUp = -faceUp;
            // loft local: Z along the ear, H along faceUp (thin), W across
            var secs = new[]
            {
                S(0f, width, width * 0.4f, 0f, outer, 2.2f),
                S(len * 0.35f, width * 0.95f, width * 0.36f, 0f, outer, 2.2f),
                S(len * 0.7f, width * 0.6f, width * 0.28f, 0f, outer, 2.2f),
                S(len * 0.9f, width * 0.28f, width * 0.18f, 0f, tip, 2.2f),
                S(len, width * 0.06f, width * 0.06f, 0f, tip, 2.2f),
            };
            LoftAlong(mb, root, d, faceUp, secs, 14);
            var innerSecs = new[]
            {
                S(len * 0.08f, width * 0.6f, width * 0.12f, 0f, inner, 2.2f),
                S(len * 0.45f, width * 0.55f, width * 0.12f, 0f, inner, 2.2f),
                S(len * 0.78f, width * 0.22f, width * 0.08f, 0f, inner, 2.2f),
            };
            // inner panel sits on the front face of the ear
            LoftAlong(mb, root + Vector3.forward * width * 0.32f, d, faceUp, innerSecs, 10);
        }
    }
}
