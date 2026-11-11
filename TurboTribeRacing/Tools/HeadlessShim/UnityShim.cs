// Minimal UnityEngine stand-in so the procedural track generator can run headless in plain .NET
// (used only by Tools/HeadlessShim to export track meshes for visual verification - never shipped).
using System;
using System.Collections.Generic;

namespace UnityEngine.Rendering
{
    public enum IndexFormat { UInt16, UInt32 }
    public enum ShadowCastingMode { Off, On }
    public enum BlendMode { Zero = 0, One = 1, SrcAlpha = 5, OneMinusSrcAlpha = 10 }
    public enum AmbientMode { Skybox, Trilight, Flat }
}

namespace UnityEngine
{
    public class DefaultExecutionOrder : System.Attribute { public DefaultExecutionOrder(int order) { } }
    public struct Vector2
    {
        public float x, y;
        public Vector2(float x, float y) { this.x = x; this.y = y; }
        public static Vector2 zero => new Vector2(0, 0); public static Vector2 one => new Vector2(1, 1); public static Vector2 up => new Vector2(0, 1);
        public static Vector2 operator +(Vector2 a, Vector2 b) => new Vector2(a.x + b.x, a.y + b.y);
        public static Vector2 operator -(Vector2 a, Vector2 b) => new Vector2(a.x - b.x, a.y - b.y);
        public static Vector2 operator *(Vector2 a, float d) => new Vector2(a.x * d, a.y * d);
        public static Vector2 operator *(float d, Vector2 a) => new Vector2(a.x * d, a.y * d);
        public static Vector2 operator /(Vector2 a, float d) => new Vector2(a.x / d, a.y / d);
        public static Vector2 Min(Vector2 a, Vector2 b) => new Vector2(Math.Min(a.x, b.x), Math.Min(a.y, b.y));
        public static Vector2 Max(Vector2 a, Vector2 b) => new Vector2(Math.Max(a.x, b.x), Math.Max(a.y, b.y));
        public static float Distance(Vector2 a, Vector2 b) => (a - b).magnitude;
        public static float Dot(Vector2 a, Vector2 b) => a.x * b.x + a.y * b.y;
        public float magnitude => (float)Math.Sqrt(x * x + y * y);
        public float sqrMagnitude => x * x + y * y;
    }

    public struct Vector3
    {
        public float x, y, z;
        public Vector3(float x, float y, float z) { this.x = x; this.y = y; this.z = z; }
        public static Vector3 zero => new Vector3(0, 0, 0); public static Vector3 one => new Vector3(1, 1, 1);
        public static Vector3 up => new Vector3(0, 1, 0); public static Vector3 down => new Vector3(0, -1, 0);
        public static Vector3 forward => new Vector3(0, 0, 1); public static Vector3 right => new Vector3(1, 0, 0); public static Vector3 back => new Vector3(0, 0, -1); public static Vector3 left => new Vector3(-1, 0, 0);
        public static Vector3 operator +(Vector3 a, Vector3 b) => new Vector3(a.x + b.x, a.y + b.y, a.z + b.z);
        public static Vector3 operator -(Vector3 a, Vector3 b) => new Vector3(a.x - b.x, a.y - b.y, a.z - b.z);
        public static Vector3 operator -(Vector3 a) => new Vector3(-a.x, -a.y, -a.z);
        public static Vector3 operator *(Vector3 a, float d) => new Vector3(a.x * d, a.y * d, a.z * d);
        public static Vector3 operator *(float d, Vector3 a) => new Vector3(a.x * d, a.y * d, a.z * d);
        public static Vector3 operator /(Vector3 a, float d) => new Vector3(a.x / d, a.y / d, a.z / d);
        public static float Dot(Vector3 a, Vector3 b) => a.x * b.x + a.y * b.y + a.z * b.z;
        public static Vector3 Cross(Vector3 a, Vector3 b) => new Vector3(a.y * b.z - a.z * b.y, a.z * b.x - a.x * b.z, a.x * b.y - a.y * b.x);
        public float magnitude => (float)Math.Sqrt(x * x + y * y + z * z);
        public float sqrMagnitude => x * x + y * y + z * z;
        public Vector3 normalized { get { float m = magnitude; return m > 1e-5f ? this / m : zero; } }
        public static float Distance(Vector3 a, Vector3 b) => (a - b).magnitude;
        public static Vector3 Lerp(Vector3 a, Vector3 b, float t) { t = Mathf.Clamp01(t); return a + (b - a) * t; }
        public static Vector3 LerpUnclamped(Vector3 a, Vector3 b, float t) => a + (b - a) * t;
        public static Vector3 ProjectOnPlane(Vector3 v, Vector3 n) { float sq = Dot(n, n); return sq < 1e-12f ? v : v - n * (Dot(v, n) / sq); }
        public static float Angle(Vector3 a, Vector3 b) { float d = (float)Math.Sqrt(a.sqrMagnitude * b.sqrMagnitude); if (d < 1e-15f) return 0; return (float)(Math.Acos(Mathf.Clamp(Dot(a, b) / d, -1, 1)) * 57.29578); }
        public static float SignedAngle(Vector3 a, Vector3 b, Vector3 axis) { float ang = Angle(a, b); return Dot(axis, Cross(a, b)) < 0 ? -ang : ang; }
        public static Vector3 Slerp(Vector3 a, Vector3 b, float t) => Lerp(a, b, t).normalized * Mathf.Lerp(a.magnitude, b.magnitude, t);
        public static Vector3 Min(Vector3 a, Vector3 b) => new Vector3(Math.Min(a.x, b.x), Math.Min(a.y, b.y), Math.Min(a.z, b.z));
        public static Vector3 Max(Vector3 a, Vector3 b) => new Vector3(Math.Max(a.x, b.x), Math.Max(a.y, b.y), Math.Max(a.z, b.z));
        public override string ToString() => $"({x:F2},{y:F2},{z:F2})";
    }

    public struct Vector4
    {
        public float x, y, z, w;
        public Vector4(float x, float y, float z, float w) { this.x = x; this.y = y; this.z = z; this.w = w; }
        public static Vector4 zero => new Vector4(0, 0, 0, 0);
        public static implicit operator Vector4(Vector3 v) => new Vector4(v.x, v.y, v.z, 0);
        public static implicit operator Vector4(Color c) => new Vector4(c.r, c.g, c.b, c.a);
    }

    public struct Quaternion
    {
        public float x, y, z, w;
        public Quaternion(float x, float y, float z, float w) { this.x = x; this.y = y; this.z = z; this.w = w; }
        public static Quaternion identity => new Quaternion(0, 0, 0, 1);
        public static Quaternion AngleAxis(float deg, Vector3 axis)
        {
            axis = axis.normalized; float h = deg * Mathf.Deg2Rad * 0.5f; float s = (float)Math.Sin(h);
            return new Quaternion(axis.x * s, axis.y * s, axis.z * s, (float)Math.Cos(h));
        }
        public static Quaternion operator *(Quaternion a, Quaternion b) => new Quaternion(
            a.w * b.x + a.x * b.w + a.y * b.z - a.z * b.y,
            a.w * b.y + a.y * b.w + a.z * b.x - a.x * b.z,
            a.w * b.z + a.z * b.w + a.x * b.y - a.y * b.x,
            a.w * b.w - a.x * b.x - a.y * b.y - a.z * b.z);
        public static Vector3 operator *(Quaternion q, Vector3 v)
        {
            Vector3 u = new Vector3(q.x, q.y, q.z);
            Vector3 t = 2f * Vector3.Cross(u, v);
            return v + q.w * t + Vector3.Cross(u, t);
        }
        // Unity applies Z, then X, then Y
        public static Quaternion Euler(float x, float y, float z) => AngleAxis(y, Vector3.up) * AngleAxis(x, Vector3.right) * AngleAxis(z, Vector3.forward);
        public static Quaternion Euler(Vector3 e) => Euler(e.x, e.y, e.z);
        public static Quaternion LookRotation(Vector3 fwd) => LookRotation(fwd, Vector3.up);
        public static Quaternion LookRotation(Vector3 fwd, Vector3 up)
        {
            Vector3 f = fwd.normalized; Vector3 r = Vector3.Cross(up, f).normalized; if (r.sqrMagnitude < 1e-6f) r = Vector3.right;
            Vector3 u = Vector3.Cross(f, r);
            float m00 = r.x, m01 = u.x, m02 = f.x, m10 = r.y, m11 = u.y, m12 = f.y, m20 = r.z, m21 = u.z, m22 = f.z;
            float tr = m00 + m11 + m22; Quaternion q;
            if (tr > 0) { float s = (float)Math.Sqrt(tr + 1) * 2; q = new Quaternion((m21 - m12) / s, (m02 - m20) / s, (m10 - m01) / s, 0.25f * s); }
            else if (m00 > m11 && m00 > m22) { float s = (float)Math.Sqrt(1 + m00 - m11 - m22) * 2; q = new Quaternion(0.25f * s, (m01 + m10) / s, (m02 + m20) / s, (m21 - m12) / s); }
            else if (m11 > m22) { float s = (float)Math.Sqrt(1 + m11 - m00 - m22) * 2; q = new Quaternion((m01 + m10) / s, 0.25f * s, (m12 + m21) / s, (m02 - m20) / s); }
            else { float s = (float)Math.Sqrt(1 + m22 - m00 - m11) * 2; q = new Quaternion((m02 + m20) / s, (m12 + m21) / s, 0.25f * s, (m10 - m01) / s); }
            return q;
        }
        public static Quaternion FromToRotation(Vector3 a, Vector3 b)
        {
            a = a.normalized; b = b.normalized; float d = Vector3.Dot(a, b);
            if (d > 0.99999f) return identity;
            if (d < -0.99999f) { Vector3 ax = Vector3.Cross(Vector3.right, a); if (ax.sqrMagnitude < 1e-6f) ax = Vector3.Cross(Vector3.up, a); return AngleAxis(180, ax); }
            Vector3 c = Vector3.Cross(a, b);
            return AngleAxis((float)(Math.Acos(d) * 57.29578), c);
        }
    }

    public struct Matrix4x4
    {
        Quaternion r; Vector3 t, s;
        public static Matrix4x4 identity => TRS(Vector3.zero, Quaternion.identity, Vector3.one);
        public static Matrix4x4 TRS(Vector3 p, Quaternion q, Vector3 sc) => new Matrix4x4 { t = p, r = q, s = sc };
        public Vector3 MultiplyPoint3x4(Vector3 v) => r * new Vector3(v.x * s.x, v.y * s.y, v.z * s.z) + t;
        public Vector3 MultiplyVector(Vector3 v) => r * new Vector3(v.x * s.x, v.y * s.y, v.z * s.z);
    }

    public static class Mathf
    {
        public const float PI = (float)Math.PI, Deg2Rad = PI / 180f, Rad2Deg = 180f / PI;
        public static float Sin(float f) => (float)Math.Sin(f); public static float Cos(float f) => (float)Math.Cos(f);
        public static float Sqrt(float f) => (float)Math.Sqrt(f); public static float Abs(float f) => Math.Abs(f); public static int Abs(int f) => Math.Abs(f);
        public static float Pow(float a, float b) => (float)Math.Pow(a, b); public static float Exp(float a) => (float)Math.Exp(a);
        public static float Atan2(float y, float x) => (float)Math.Atan2(y, x);
        public static float Min(float a, float b) => Math.Min(a, b); public static float Max(float a, float b) => Math.Max(a, b);
        public static int Min(int a, int b) => Math.Min(a, b); public static int Max(int a, int b) => Math.Max(a, b);
        public static float Clamp(float v, float a, float b) => v < a ? a : v > b ? b : v; public static int Clamp(int v, int a, int b) => v < a ? a : v > b ? b : v;
        public static float Clamp01(float v) => Clamp(v, 0, 1);
        public static float Lerp(float a, float b, float t) => a + (b - a) * Clamp01(t);
        public static float InverseLerp(float a, float b, float v) => a != b ? Clamp01((v - a) / (b - a)) : 0;
        public static int FloorToInt(float f) => (int)Math.Floor(f); public static int CeilToInt(float f) => (int)Math.Ceiling(f); public static int RoundToInt(float f) => (int)Math.Round(f);
        public static float Floor(float f) => (float)Math.Floor(f); public static float Ceil(float f) => (float)Math.Ceiling(f);
        public static float Repeat(float t, float l) => Clamp(t - Floor(t / l) * l, 0, l);
        public static float Sign(float f) => f >= 0 ? 1 : -1;
        public static float MoveTowards(float c, float t, float d) => Math.Abs(t - c) <= d ? t : c + Sign(t - c) * d;
        public static float PerlinNoise(float x, float y) => 0.5f;
        public static float PingPong(float t, float l) { t = Repeat(t, l * 2f); return l - Math.Abs(t - l); }
        public static float SmoothStep(float a, float b, float t) { t = Clamp01(t); t = t * t * (3 - 2 * t); return a + (b - a) * t; }
        public static float DeltaAngle(float a, float b) { float d = Repeat(b - a, 360f); if (d > 180f) d -= 360f; return d; }
    }

    public struct Color
    {
        public float r, g, b, a;
        public Color(float r, float g, float b, float a = 1) { this.r = r; this.g = g; this.b = b; this.a = a; }
        public static Color white => new Color(1, 1, 1, 1); public static Color black => new Color(0, 0, 0, 1);
        public static Color operator *(Color c, float f) => new Color(c.r * f, c.g * f, c.b * f, c.a * f);
        public static Color operator *(Color a, Color b) => new Color(a.r * b.r, a.g * b.g, a.b * b.b, a.a * b.a);
        public static Color operator +(Color a, Color b) => new Color(a.r + b.r, a.g + b.g, a.b + b.b, a.a + b.a);
        public static Color Lerp(Color a, Color b, float t) { t = Mathf.Clamp01(t); return new Color(a.r + (b.r - a.r) * t, a.g + (b.g - a.g) * t, a.b + (b.b - a.b) * t, a.a + (b.a - a.a) * t); }
        public static implicit operator Color32(Color c) => new Color32((byte)(Mathf.Clamp01(c.r) * 255), (byte)(Mathf.Clamp01(c.g) * 255), (byte)(Mathf.Clamp01(c.b) * 255), (byte)(Mathf.Clamp01(c.a) * 255));
    }

    public struct Color32
    {
        public byte r, g, b, a;
        public Color32(byte r, byte g, byte b, byte a) { this.r = r; this.g = g; this.b = b; this.a = a; }
        public static implicit operator Color(Color32 c) => new Color(c.r / 255f, c.g / 255f, c.b / 255f, c.a / 255f);
    }

    public static class ColorUtility
    {
        public static bool TryParseHtmlString(string h, out Color c)
        {
            h = h.TrimStart('#');
            c = new Color(Convert.ToInt32(h.Substring(0, 2), 16) / 255f, Convert.ToInt32(h.Substring(2, 2), 16) / 255f, Convert.ToInt32(h.Substring(4, 2), 16) / 255f, 1);
            return true;
        }
    }

    public class Object
    {
        public string name;
        public static void Destroy(Object o) { }
        public static implicit operator bool(Object o) => o != null;
    }

    public class Mesh : Object
    {
        public Rendering.IndexFormat indexFormat;
        public List<Vector3> Vertices = new List<Vector3>(); public List<Vector3> Normals = new List<Vector3>();
        public List<Color32> Colors = new List<Color32>(); public List<int> Triangles = new List<int>();
        public void SetVertices(List<Vector3> v) { Vertices = new List<Vector3>(v); }
        public void SetNormals(List<Vector3> v) { Normals = new List<Vector3>(v); }
        public void SetColors(List<Color32> v) { Colors = new List<Color32>(v); }
        public List<Vector2> UV = new List<Vector2>();
        public void SetUVs(int ch, List<Vector2> v) { if (ch == 0) UV = new List<Vector2>(v); }
        public void SetTriangles(List<int> t, int sub) { Triangles = new List<int>(t); }
        public void RecalculateNormals() { }
        public void RecalculateBounds() { }
    }

    public enum TextureFormat { RGBA32 }
    public enum TextureWrapMode { Repeat, Clamp }
    public enum FilterMode { Point, Bilinear }
    public class Texture2D : Object
    {
        public TextureWrapMode wrapMode; public FilterMode filterMode; public int anisoLevel;
        public int width, height; public Color32[] Px;
        public Texture2D(int w, int h, TextureFormat f, bool m) { width = w; height = h; }
        public void SetPixels32(Color32[] p) { Px = (Color32[])p.Clone(); }
        public void SetPixels(Color[] p) { Px = new Color32[p.Length]; for (int i = 0; i < p.Length; i++) Px[i] = p[i]; }
        public void Apply(bool a = true) { }
    }
    public class Shader : Object
    {
        public static Shader Find(string n) => new Shader();
        public static void SetGlobalVector(string n, Vector4 v) { }
    }
    public class Material : Object
    {
        public int renderQueue;
        public Material(Shader s) { }
        public Texture2D MainTex;
        public void SetTexture(string n, Texture2D t) { if (n == "_MainTex") MainTex = t; } public void SetFloat(string n, float f) { } public void SetVector(string n, Vector4 v) { }
        public void SetColor(string n, Color c) { } public void SetTextureScale(string n, Vector2 v) { }
    }
    public class TextAsset : Object { public string text; }
    public static class Resources
    {
        public static string TrackDir;
        public static T Load<T>(string path) where T : class
        {
            if (typeof(T) == typeof(TextAsset))
            {
                string f = System.IO.Path.Combine(TrackDir, System.IO.Path.GetFileName(path) + ".json");
                return System.IO.File.Exists(f) ? new TextAsset { text = System.IO.File.ReadAllText(f) } as T : null;
            }
            return null;
        }
    }
    public static class JsonUtility
    {
        public static T FromJson<T>(string json) => System.Text.Json.JsonSerializer.Deserialize<T>(json, new System.Text.Json.JsonSerializerOptions { IncludeFields = true });
    }
    public static class Debug { public static void Log(object o) => Console.WriteLine(o); public static void LogWarning(object o) => Console.WriteLine("WARN " + o); public static void LogError(object o) => Console.WriteLine("ERROR " + o); }

    public class Component : Object { public GameObject gameObject; public Transform transform => gameObject.transform; public T GetComponent<T>() where T : Component => gameObject.GetComponent<T>(); }
    public class Behaviour : Component { public bool enabled = true; }
    public class MonoBehaviour : Behaviour { }
    public class Transform : Component
    {
        public Transform parent; public Vector3 position, localPosition, localScale = Vector3.one; public Quaternion rotation = Quaternion.identity, localRotation = Quaternion.identity;
        public Vector3 forward => rotation * Vector3.forward;
        public void SetParent(Transform p, bool w) { parent = p; }
        public void SetPositionAndRotation(Vector3 p, Quaternion r) { position = p; rotation = r; }
        public Vector3 up => rotation * Vector3.up;
        public Vector3 right => rotation * Vector3.right;
    }
    public class GameObject : Object
    {
        public static readonly List<GameObject> All = new List<GameObject>();
        public Transform transform; public int layer; readonly List<Component> comps = new List<Component>();
        public GameObject(string n) { name = n; transform = new Transform(); transform.gameObject = this; comps.Add(transform); All.Add(this); }
        public T AddComponent<T>() where T : Component, new() { var c = new T(); c.gameObject = this; comps.Add(c); return c; }
        public T GetComponent<T>() where T : Component { foreach (var c in comps) if (c is T t) return t; return null; }
        public void SetActive(bool a) { }
    }
    public class MeshFilter : Component { public Mesh sharedMesh; }
    public class Renderer : Component { public Material sharedMaterial; public Rendering.ShadowCastingMode shadowCastingMode; public bool receiveShadows; }
    public class MeshRenderer : Renderer { }
    public class Collider : Component { }
    public class MeshCollider : Collider { public Mesh sharedMesh; public int layerBits; }
    public enum LightType { Directional }
    public enum LightShadows { None }
    public class Light : Behaviour { public LightType type; public Color color; public float intensity; public LightShadows shadows; }
    public static class RenderSettings { public static Light sun; public static Rendering.AmbientMode ambientMode; public static Color ambientLight; public static bool fog; }
    public class Camera : Behaviour { public static Camera main; }

    public static class Time { public static float deltaTime = 1f / 60f; public static float time; public static float unscaledDeltaTime = 1f / 60f; }

    public static class Random
    {
        public static System.Random R = new System.Random(1);
        public static float value => (float)R.NextDouble();
        public static float Range(float a, float b) => a + (b - a) * (float)R.NextDouble();
        public static int Range(int a, int b) => R.Next(a, b);
    }

    public struct Rect { public float x, y, width, height; public Rect(float x, float y, float w, float h) { this.x = x; this.y = y; width = w; height = h; } }
    public enum SpriteMeshType { FullRect, Tight }
    public class Sprite : Object { public static Sprite Create(Texture2D t, Rect r, Vector2 pivot, float ppu, uint extrude, SpriteMeshType mt, Vector4 border) => new Sprite(); }

    public enum QueryTriggerInteraction { UseGlobal, Ignore, Collide }
    public struct RaycastHit { public Vector3 point; public Vector3 normal; public float distance; public Collider collider; }

    /// <summary>Ray vs. MeshCollider triangles (front faces only, like Unity's default), uniform XZ grid.</summary>
    public static class Physics
    {
        struct Tri { public Vector3 a, b, c, n; public Collider col; }
        static readonly List<Tri> tris = new List<Tri>();
        static readonly Dictionary<long, List<int>> grid = new Dictionary<long, List<int>>();
        const float Cell = 4f;
        public static int RayCount;
        static long Key(int x, int z) => ((long)x << 32) ^ (uint)z;

        public static void Build()
        {
            tris.Clear(); grid.Clear();
            foreach (var go in GameObject.All)
            {
                var mc = go.GetComponent<MeshCollider>();
                if (mc == null || mc.sharedMesh == null) continue;
                int layerBit = 1 << go.layer;
                var m = mc.sharedMesh;
                for (int i = 0; i < m.Triangles.Count; i += 3)
                {
                    Vector3 a = m.Vertices[m.Triangles[i]], b = m.Vertices[m.Triangles[i + 1]], c = m.Vertices[m.Triangles[i + 2]];
                    Vector3 n = Vector3.Cross(b - a, c - a);
                    if (n.sqrMagnitude < 1e-12f) continue;
                    var t = new Tri { a = a, b = b, c = c, n = n.normalized, col = mc };
                    mc.layerBits = layerBit;
                    int idx = tris.Count; tris.Add(t);
                    int x0 = (int)Math.Floor(Math.Min(a.x, Math.Min(b.x, c.x)) / Cell), x1 = (int)Math.Floor(Math.Max(a.x, Math.Max(b.x, c.x)) / Cell);
                    int z0 = (int)Math.Floor(Math.Min(a.z, Math.Min(b.z, c.z)) / Cell), z1 = (int)Math.Floor(Math.Max(a.z, Math.Max(b.z, c.z)) / Cell);
                    for (int x = x0; x <= x1; x++)
                        for (int z = z0; z <= z1; z++)
                        {
                            List<int> l; long k = Key(x, z);
                            if (!grid.TryGetValue(k, out l)) { l = new List<int>(); grid[k] = l; }
                            l.Add(idx);
                        }
                }
            }
        }

        public static bool Raycast(Vector3 o, Vector3 d, out RaycastHit hit, float maxDist, int mask, QueryTriggerInteraction q) => Raycast(o, d, out hit, maxDist, mask);
        public static bool Raycast(Vector3 o, Vector3 d, out RaycastHit hit, float maxDist, int mask)
        {
            RayCount++;
            hit = new RaycastHit(); bool found = false; float best = maxDist;
            d = d.normalized;
            Vector3 e = o + d * maxDist;
            int x0 = (int)Math.Floor(Math.Min(o.x, e.x) / Cell), x1 = (int)Math.Floor(Math.Max(o.x, e.x) / Cell);
            int z0 = (int)Math.Floor(Math.Min(o.z, e.z) / Cell), z1 = (int)Math.Floor(Math.Max(o.z, e.z) / Cell);
            for (int x = x0; x <= x1; x++)
                for (int z = z0; z <= z1; z++)
                {
                    List<int> l;
                    if (!grid.TryGetValue(Key(x, z), out l)) continue;
                    foreach (int i in l)
                    {
                        var t = tris[i];
                        if ((((MeshCollider)t.col).layerBits & mask) == 0) continue;
                        if (Vector3.Dot(d, t.n) >= 0f) continue; // back face
                        Vector3 e1 = t.b - t.a, e2 = t.c - t.a, pv = Vector3.Cross(d, e2);
                        float det = Vector3.Dot(e1, pv);
                        if (Math.Abs(det) < 1e-9f) continue;
                        float inv = 1f / det; Vector3 tv = o - t.a;
                        float u = Vector3.Dot(tv, pv) * inv; if (u < 0 || u > 1) continue;
                        Vector3 qv = Vector3.Cross(tv, e1);
                        float v = Vector3.Dot(d, qv) * inv; if (v < 0 || u + v > 1) continue;
                        float dist = Vector3.Dot(e2, qv) * inv;
                        if (dist >= 0 && dist < best) { best = dist; found = true; hit.distance = dist; hit.point = o + d * dist; hit.normal = t.n; hit.collider = t.col; }
                    }
                }
            return found;
        }
    }
}
