using System.Collections.Generic;
using UnityEngine;

namespace TurboTribe
{
    /// <summary>Vertical road-profile modifier (bump / dip / rumble strip) applied after sampling.</summary>
    public struct HeightMod
    {
        public float T, H, Len; public int Count;
        public HeightMod(float t, float h, float len, int count = 1) { T = t; H = h; Len = len; Count = Mathf.Max(1, count); }
    }

    /// <summary>
    /// Centripetal Catmull-Rom spline (closed loop or open branch) resampled every ~1 m.
    /// Provides the road frame (forward/right/up with auto banking), widths, curvature and
    /// windowed nearest-sample queries used by lap tracking, AI and items.
    /// </summary>
    public class TrackSpline
    {
        public Vector3[] Pos;
        public Vector3[] Fwd;
        public Vector3[] Right;
        public Vector3[] Up;
        public float[] HalfWidth;
        public float[] Param;     // control-point parameter (index + t)
        public float[] Curv;      // signed curvature (1/m), + = turning right
        public float[] Bank;      // degrees
        public int Count;
        public float Length;
        public float Step;
        public int PointCount;
        public bool Closed = true;

        static Vector3 CR(Vector3 p0, Vector3 p1, Vector3 p2, Vector3 p3, float t)
        {
            float t0 = 0f;
            float t1 = t0 + Mathf.Pow(Mathf.Max(Flat(p1 - p0), 1e-3f), 0.5f);
            float t2 = t1 + Mathf.Pow(Mathf.Max(Flat(p2 - p1), 1e-3f), 0.5f);
            float t3 = t2 + Mathf.Pow(Mathf.Max(Flat(p3 - p2), 1e-3f), 0.5f);
            float tt = Mathf.Lerp(t1, t2, t);
            Vector3 a1 = (t1 - tt) / (t1 - t0) * p0 + (tt - t0) / (t1 - t0) * p1;
            Vector3 a2 = (t2 - tt) / (t2 - t1) * p1 + (tt - t1) / (t2 - t1) * p2;
            Vector3 a3 = (t3 - tt) / (t3 - t2) * p2 + (tt - t2) / (t3 - t2) * p3;
            Vector3 b1 = (t2 - tt) / (t2 - t0) * a1 + (tt - t0) / (t2 - t0) * a2;
            Vector3 b2 = (t3 - tt) / (t3 - t1) * a2 + (tt - t1) / (t3 - t1) * a3;
            return (t2 - tt) / (t2 - t1) * b1 + (tt - t1) / (t2 - t1) * b2;
        }

        static float Flat(Vector3 v) { return Mathf.Sqrt(v.x * v.x + v.z * v.z); }

        public static TrackSpline Build(List<TrackPointData> pts, float step = 1f, bool closed = true, List<HeightMod> mods = null)
        {
            int n = pts.Count;
            const int sub = 48;
            var P = new Vector3[n]; var W = new float[n]; var B = new float[n];
            for (int i = 0; i < n; i++) { P[i] = new Vector3(pts[i].x, pts[i].y, pts[i].z); W[i] = pts[i].w; B[i] = Mathf.Abs(pts[i].bank); }
            System.Func<int, Vector3> get = k =>
            {
                if (closed) return P[Mathx.Wrap(k, n)];
                if (k < 0) return P[0] * 2f - P[1];
                if (k >= n) return P[n - 1] * 2f - P[n - 2];
                return P[k];
            };
            int segs = closed ? n : n - 1;
            var dense = new List<Vector3>(segs * sub + 1);
            var dW = new List<float>(); var dB = new List<float>(); var dP = new List<float>();
            for (int i = 0; i < segs; i++)
            {
                int j = closed ? (i + 1) % n : i + 1;
                for (int k = 0; k < sub; k++)
                {
                    float t = k / (float)sub;
                    dense.Add(CR(get(i - 1), get(i), get(i + 1), get(i + 2), t));
                    float st = t * t * (3 - 2 * t);
                    dW.Add(Mathf.Lerp(W[i], W[j], st));
                    dB.Add(Mathf.Lerp(B[i], B[j], st));
                    dP.Add(i + t);
                }
            }
            if (!closed) { dense.Add(P[n - 1]); dW.Add(W[n - 1]); dB.Add(B[n - 1]); dP.Add(n - 1); }
            int m = dense.Count;
            int segCount = closed ? m : m - 1;
            var cum = new float[m + 1];
            for (int i = 0; i < segCount; i++) cum[i + 1] = cum[i] + Vector3.Distance(dense[i], dense[(i + 1) % m]);
            if (!closed) cum[m] = cum[m - 1];
            float total = cum[segCount];
            int count = Mathf.Max(8, Mathf.RoundToInt(total / step));
            if (!closed) count += 1; // include the end point
            var s = new TrackSpline
            {
                Count = count, Length = total, PointCount = n, Closed = closed,
                Step = closed ? total / count : total / (count - 1),
                Pos = new Vector3[count], Fwd = new Vector3[count], Right = new Vector3[count], Up = new Vector3[count],
                HalfWidth = new float[count], Param = new float[count], Curv = new float[count], Bank = new float[count]
            };
            var extraBank = new float[count];
            int jx = 0;
            for (int i = 0; i < count; i++)
            {
                float dist = Mathf.Min(i * s.Step, total);
                while (jx < segCount - 1 && cum[jx + 1] < dist) jx++;
                float f = (dist - cum[jx]) / Mathf.Max(cum[jx + 1] - cum[jx], 1e-5f);
                f = Mathf.Clamp01(f);
                int jn = closed ? (jx + 1) % m : Mathf.Min(jx + 1, m - 1);
                s.Pos[i] = Vector3.Lerp(dense[jx], dense[jn], f);
                s.HalfWidth[i] = Mathf.Lerp(dW[jx], dW[jn], f) * 0.5f;
                extraBank[i] = Mathf.Lerp(dB[jx], dB[jn], f);
                float pa = dP[jx], pb = (closed && jn == 0) ? n : dP[jn];
                s.Param[i] = Mathf.Lerp(pa, pb, f);
            }
            // vertical profile features (bumps, dips, rumble strips)
            if (mods != null)
                foreach (var hm in mods)
                {
                    int c = s.IndexOfParam(hm.T);
                    int len = Mathf.Max(2, Mathf.RoundToInt(hm.Len / s.Step));
                    for (int rep = 0; rep < hm.Count; rep++)
                        for (int k = 0; k <= len; k++)
                        {
                            int idx = s.Wrap(c + rep * len + k - (hm.Count * len) / 2);
                            float u = k / (float)len;
                            s.Pos[idx].y += hm.H * (0.5f - 0.5f * Mathf.Cos(u * Mathf.PI * 2f));
                        }
                }
            // forward + curvature
            for (int i = 0; i < count; i++)
            {
                Vector3 prev = s.Pos[s.Wrap(i - 1)], next = s.Pos[s.Wrap(i + 1)];
                Vector3 d = next - prev;
                s.Fwd[i] = d.sqrMagnitude > 1e-6f ? d.normalized : Vector3.forward;
            }
            const int cw = 6;
            for (int i = 0; i < count; i++)
            {
                Vector3 a = Mathx.Flat(s.Fwd[s.Wrap(i - cw)]).normalized;
                Vector3 b = Mathx.Flat(s.Fwd[s.Wrap(i + cw)]).normalized;
                float ang = Vector3.SignedAngle(a, b, Vector3.up) * Mathf.Deg2Rad;
                int span = s.Wrap(i + cw) - s.Wrap(i - cw);
                if (closed) span = 2 * cw;
                s.Curv[i] = span > 0 ? ang / (span * s.Step) : 0f;
            }
            var tmp = new float[count];
            for (int pass = 0; pass < 3; pass++)
            {
                for (int i = 0; i < count; i++)
                    tmp[i] = (s.Curv[s.Wrap(i - 2)] + s.Curv[s.Wrap(i - 1)] + s.Curv[i] + s.Curv[s.Wrap(i + 1)] + s.Curv[s.Wrap(i + 2)]) / 5f;
                System.Array.Copy(tmp, s.Curv, count);
            }
            // banking: raise the outside of the turn. Positive curvature = right turn -> left side up.
            for (int i = 0; i < count; i++)
            {
                float auto = Mathf.Clamp(s.Curv[i] * 130f, -6f, 6f);
                float extra = extraBank[i] * 0.6f * Mathf.Sign(s.Curv[i]) * Mathf.Clamp01(Mathf.Abs(s.Curv[i]) * 40f);
                s.Bank[i] = Mathf.Clamp(auto + extra, -10f, 10f);
            }
            for (int pass = 0; pass < 4; pass++)
            {
                for (int i = 0; i < count; i++)
                    tmp[i] = (s.Bank[s.Wrap(i - 3)] + s.Bank[s.Wrap(i - 1)] + s.Bank[i] + s.Bank[s.Wrap(i + 1)] + s.Bank[s.Wrap(i + 3)]) / 5f;
                System.Array.Copy(tmp, s.Bank, count);
            }
            if (!closed)
            {
                // branches meet the main road flat
                for (int i = 0; i < count; i++)
                {
                    float e = Mathf.Min(i, count - 1 - i) / 12f;
                    s.Bank[i] *= Mathf.Clamp01(e);
                }
            }
            for (int i = 0; i < count; i++)
            {
                Vector3 flatRight = Vector3.Cross(Vector3.up, s.Fwd[i]).normalized;
                // AngleAxis(+a, fwd) lifts the right edge in Unity, so negate: right turns (bank > 0) lift the left/outside edge
                Quaternion q = Quaternion.AngleAxis(-s.Bank[i], s.Fwd[i]);
                Vector3 r = q * flatRight;
                s.Right[i] = r;
                s.Up[i] = Vector3.Cross(s.Fwd[i], r).normalized;
            }
            return s;
        }

        public int Wrap(int i) { return Closed ? Mathx.Wrap(i, Count) : Mathf.Clamp(i, 0, Count - 1); }

        /// <summary>Sample index of a control-point parameter (e.g. 5.45).</summary>
        public int IndexOfParam(float p)
        {
            p = Closed ? Mathf.Repeat(p, PointCount) : Mathf.Clamp(p, 0, PointCount - 1);
            int lo = 0, hi = Count - 1;
            while (lo < hi)
            {
                int mid = (lo + hi) / 2;
                if (Param[mid] < p) lo = mid + 1; else hi = mid;
            }
            return lo;
        }

        /// <summary>Nearest sample searching a window around a hint (vertical distance weighted, so overpasses stay apart).</summary>
        public int Nearest(Vector3 p, int hint, int window)
        {
            int best = Wrap(hint); float bd = float.MaxValue;
            for (int k = -window; k <= window; k++)
            {
                int i = hint + k;
                if (!Closed && (i < 0 || i >= Count)) continue;
                i = Wrap(i);
                Vector3 d = Pos[i] - p;
                float dd = d.x * d.x + d.z * d.z + d.y * d.y * 4f;
                if (dd < bd) { bd = dd; best = i; }
            }
            return best;
        }

        public int NearestGlobal(Vector3 p)
        {
            int best = 0; float bd = float.MaxValue;
            for (int i = 0; i < Count; i += 2)
            {
                Vector3 d = Pos[i] - p;
                float dd = d.x * d.x + d.z * d.z + d.y * d.y * 4f;
                if (dd < bd) { bd = dd; best = i; }
            }
            return Nearest(p, best, 3);
        }

        public float Lateral(Vector3 p, int i) { return Vector3.Dot(p - Pos[i], Right[i]); }

        /// <summary>Average signed curvature over [startM, startM+meters] ahead of sample i.</summary>
        public float CurvatureAhead(int i, float startM, float meters)
        {
            int a = Mathf.RoundToInt(startM / Step), b = Mathf.RoundToInt((startM + meters) / Step);
            float sum = 0; int c = 0;
            for (int k = a; k <= b; k++) { sum += Curv[Wrap(i + k)]; c++; }
            return c > 0 ? sum / c : 0f;
        }

        public Vector3 PointAt(int i, float lateral, float lift = 0f)
        {
            i = Wrap(i);
            return Pos[i] + Right[i] * lateral + Up[i] * lift;
        }
    }
}
