using UnityEngine;

namespace TurboTribe
{
    /// <summary>Physics layers used by the game (indices only; no TagManager edits required).</summary>
    public static class Layers
    {
        public const int Ground = 8;
        public const int Wall = 9;
        public const int Kart = 10;
        public const int GroundMask = 1 << Ground;
        public const int WallMask = 1 << Wall;
        public const int WorldMask = GroundMask | WallMask;
    }

    public static class Mathx
    {
        public static float SmoothStep01(float e0, float e1, float x)
        {
            float t = Mathf.Clamp01((x - e0) / (e1 - e0));
            return t * t * (3f - 2f * t);
        }

        /// <summary>Frame-rate independent exponential smoothing factor.</summary>
        public static float Damp(float sharpness, float dt) { return 1f - Mathf.Exp(-sharpness * dt); }

        public static int Wrap(int i, int n) { i %= n; return i < 0 ? i + n : i; }

        public static float MoveTowards(float cur, float target, float maxDelta) { return Mathf.MoveTowards(cur, target, maxDelta); }

        public static Vector3 Flat(Vector3 v) { v.y = 0f; return v; }

        public static float SignedAngleOnPlane(Vector3 from, Vector3 to, Vector3 axis)
        {
            from = Vector3.ProjectOnPlane(from, axis);
            to = Vector3.ProjectOnPlane(to, axis);
            return Vector3.SignedAngle(from, to, axis);
        }
    }

    /// <summary>Deterministic hash-based value noise (tileable optional).</summary>
    public static class Noise
    {
        static float Hash(int x, int y, int seed)
        {
            unchecked
            {
                uint h = (uint)(x * 374761393 + y * 668265263 + seed * 1442695041);
                h = (h ^ (h >> 13)) * 1274126177u;
                h ^= h >> 16;
                return (h & 0xFFFFFF) / 16777215f;
            }
        }

        public static float Value(float x, float y, int seed = 0, int period = 0)
        {
            int xi = Mathf.FloorToInt(x), yi = Mathf.FloorToInt(y);
            float xf = x - xi, yf = y - yi;
            int x1 = xi + 1, y1 = yi + 1;
            if (period > 0)
            {
                xi = Mathx.Wrap(xi, period); yi = Mathx.Wrap(yi, period);
                x1 = Mathx.Wrap(x1, period); y1 = Mathx.Wrap(y1, period);
            }
            float a = Hash(xi, yi, seed), b = Hash(x1, yi, seed), c = Hash(xi, y1, seed), d = Hash(x1, y1, seed);
            float u = xf * xf * (3 - 2 * xf), v = yf * yf * (3 - 2 * yf);
            return Mathf.Lerp(Mathf.Lerp(a, b, u), Mathf.Lerp(c, d, u), v);
        }

        public static float Fbm(float x, float y, int octaves, int seed = 0, int period = 0)
        {
            float sum = 0, amp = 0.5f, norm = 0, f = 1;
            for (int i = 0; i < octaves; i++)
            {
                sum += Value(x * f, y * f, seed + i * 17, period > 0 ? period * (int)f : 0) * amp;
                norm += amp; amp *= 0.5f; f *= 2f;
            }
            return sum / norm;
        }

        public static float Ridged(float x, float y, int octaves, int seed = 0)
        {
            float sum = 0, amp = 0.5f, norm = 0, f = 1;
            for (int i = 0; i < octaves; i++)
            {
                float n = 1f - Mathf.Abs(Value(x * f, y * f, seed + i * 31) * 2f - 1f);
                sum += n * n * amp; norm += amp; amp *= 0.5f; f *= 2f;
            }
            return sum / norm;
        }
    }

    /// <summary>Small deterministic RNG so tracks decorate identically every time.</summary>
    public class Rng
    {
        System.Random r;
        public Rng(int seed) { r = new System.Random(seed); }
        public float Value() { return (float)r.NextDouble(); }
        public float Range(float a, float b) { return a + (b - a) * (float)r.NextDouble(); }
        public int Range(int a, int b) { return r.Next(a, b); }
        public bool Chance(float p) { return r.NextDouble() < p; }
        public Color Jitter(Color c, float amount)
        {
            float j = Range(-amount, amount);
            return new Color(Mathf.Clamp01(c.r + j), Mathf.Clamp01(c.g + j), Mathf.Clamp01(c.b + j), c.a);
        }
    }
}
