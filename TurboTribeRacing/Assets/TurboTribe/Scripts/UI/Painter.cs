using UnityEngine;

namespace TurboTribe
{
    /// <summary>Anti-aliased 2D painter used to generate UI sprites and icons at runtime.</summary>
    public class Painter
    {
        public readonly int W, H;
        public readonly Color[] Px;

        public Painter(int w, int h) { W = w; H = h; Px = new Color[w * h]; }

        void Blend(int x, int y, Color c, float cov)
        {
            if (cov <= 0f || x < 0 || y < 0 || x >= W || y >= H) return;
            int i = y * W + x;
            float a = c.a * Mathf.Clamp01(cov);
            Color d = Px[i];
            float outA = a + d.a * (1 - a);
            if (outA < 1e-5f) { Px[i] = new Color(0, 0, 0, 0); return; }
            Px[i] = new Color((c.r * a + d.r * d.a * (1 - a)) / outA, (c.g * a + d.g * d.a * (1 - a)) / outA, (c.b * a + d.b * d.a * (1 - a)) / outA, outA);
        }

        public delegate float Sdf(float x, float y);
        public delegate Color Shade(float x, float y);

        public void Fill(Sdf sdf, Shade shade)
        {
            for (int y = 0; y < H; y++)
                for (int x = 0; x < W; x++)
                {
                    float px = x + 0.5f, py = y + 0.5f;
                    float d = sdf(px, py);
                    if (d > 1f) continue;
                    Blend(x, y, shade(px, py), 0.5f - d);
                }
        }

        public void Fill(Sdf sdf, Color c) { Fill(sdf, (x, y) => c); }

        // --- SDF primitives (pixel units; negative inside)
        public static float SdCircle(float x, float y, float cx, float cy, float r) { return Mathf.Sqrt((x - cx) * (x - cx) + (y - cy) * (y - cy)) - r; }

        public static float SdRoundBox(float x, float y, float cx, float cy, float hx, float hy, float r)
        {
            float qx = Mathf.Abs(x - cx) - hx + r, qy = Mathf.Abs(y - cy) - hy + r;
            float ox = Mathf.Max(qx, 0), oy = Mathf.Max(qy, 0);
            return Mathf.Sqrt(ox * ox + oy * oy) + Mathf.Min(Mathf.Max(qx, qy), 0) - r;
        }

        public static float SdSegment(float x, float y, float ax, float ay, float bx, float by, float r)
        {
            float pax = x - ax, pay = y - ay, bax = bx - ax, bay = by - ay;
            float h = Mathf.Clamp01((pax * bax + pay * bay) / (bax * bax + bay * bay));
            float dx = pax - bax * h, dy = pay - bay * h;
            return Mathf.Sqrt(dx * dx + dy * dy) - r;
        }

        /// <summary>Convex/concave polygon SDF (even-odd), points in pixel coords.</summary>
        public static float SdPoly(float x, float y, Vector2[] v)
        {
            float d = float.MaxValue; float s = 1f;
            for (int i = 0, j = v.Length - 1; i < v.Length; j = i, i++)
            {
                Vector2 e = v[j] - v[i]; Vector2 w = new Vector2(x, y) - v[i];
                Vector2 b = w - e * Mathf.Clamp01(Vector2.Dot(w, e) / Vector2.Dot(e, e));
                d = Mathf.Min(d, b.sqrMagnitude);
                bool c1 = y >= v[i].y, c2 = y < v[j].y, c3 = e.x * w.y > e.y * w.x;
                if ((c1 && c2 && c3) || (!c1 && !c2 && !c3)) s = -s;
            }
            return s * Mathf.Sqrt(d);
        }

        public Texture2D ToTexture(string name)
        {
            var t = new Texture2D(W, H, TextureFormat.RGBA32, false) { name = name, wrapMode = TextureWrapMode.Clamp, filterMode = FilterMode.Bilinear };
            t.SetPixels(Px);
            t.Apply();
            return t;
        }

        public Sprite ToSprite(string name, Vector4 border)
        {
            var t = ToTexture(name);
            return Sprite.Create(t, new Rect(0, 0, W, H), new Vector2(0.5f, 0.5f), 100f, 0, SpriteMeshType.FullRect, border);
        }
    }
}
