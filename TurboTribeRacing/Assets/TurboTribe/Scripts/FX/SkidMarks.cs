using System.Collections.Generic;
using UnityEngine;

namespace TurboTribe
{
    /// <summary>
    /// Ring-buffer tyre-mark mesh shared by all karts. Each wheel streams connected quads while it scrubs;
    /// the oldest marks are recycled. One draw call.
    /// </summary>
    public class SkidMarks : MonoBehaviour
    {
        const int MaxSegs = 1800;
        const float MinSegment = 0.4f;
        Mesh mesh;
        Vector3[] v; Color32[] c; Vector2[] uv; Vector3[] n;
        int next;
        bool dirty;
        struct Last { public Vector3 Pos, Right; public byte Alpha; public float U; public bool Valid; }
        readonly Dictionary<int, Last> last = new Dictionary<int, Last>();

        void Awake()
        {
            mesh = new Mesh { name = "SkidMarks" };
            v = new Vector3[MaxSegs * 4]; c = new Color32[MaxSegs * 4]; uv = new Vector2[MaxSegs * 4]; n = new Vector3[MaxSegs * 4];
            var tris = new int[MaxSegs * 6];
            for (int i = 0; i < MaxSegs; i++)
            {
                int a = i * 4, t = i * 6;
                tris[t] = a; tris[t + 1] = a + 1; tris[t + 2] = a + 2; tris[t + 3] = a; tris[t + 4] = a + 2; tris[t + 5] = a + 3;
                n[a] = n[a + 1] = n[a + 2] = n[a + 3] = Vector3.up;
            }
            mesh.vertices = v; mesh.normals = n; mesh.colors32 = c; mesh.uv = uv; mesh.triangles = tris;
            mesh.bounds = new Bounds(Vector3.zero, Vector3.one * 100000f);
            mesh.MarkDynamic();
            gameObject.AddComponent<MeshFilter>().sharedMesh = mesh;
            var mr = gameObject.AddComponent<MeshRenderer>();
            mr.sharedMaterial = Art.Skid();
            mr.shadowCastingMode = UnityEngine.Rendering.ShadowCastingMode.Off;
            mr.receiveShadows = false;
        }

        public void Add(int id, Vector3 p, Vector3 normal, Vector3 travel, float width, float alpha)
        {
            p += normal * 0.03f;
            Vector3 right = Vector3.Cross(normal, travel).normalized * (width * 0.5f);
            byte a = (byte)(Mathf.Clamp01(alpha) * 200);
            Last l;
            if (!last.TryGetValue(id, out l) || !l.Valid)
            {
                last[id] = new Last { Pos = p, Right = right, Alpha = a, U = 0f, Valid = true };
                return;
            }
            float d = Vector3.Distance(p, l.Pos);
            if (d < MinSegment) return;
            if (d > 4f) { last[id] = new Last { Pos = p, Right = right, Alpha = a, U = 0f, Valid = true }; return; }
            int i = next * 4;
            next = (next + 1) % MaxSegs;
            float u1 = l.U + d / 2f;
            v[i] = l.Pos - l.Right; v[i + 1] = p - right; v[i + 2] = p + right; v[i + 3] = l.Pos + l.Right;
            c[i] = c[i + 3] = new Color32(255, 255, 255, l.Alpha);
            c[i + 1] = c[i + 2] = new Color32(255, 255, 255, a);
            uv[i] = new Vector2(0, l.U); uv[i + 1] = new Vector2(0, u1); uv[i + 2] = new Vector2(1, u1); uv[i + 3] = new Vector2(1, l.U);
            last[id] = new Last { Pos = p, Right = right, Alpha = a, U = u1, Valid = true };
            dirty = true;
        }

        public void Break(int id)
        {
            Last l;
            if (last.TryGetValue(id, out l) && l.Valid) { l.Valid = false; last[id] = l; }
        }

        void LateUpdate()
        {
            if (!dirty) return;
            dirty = false;
            mesh.vertices = v;
            mesh.colors32 = c;
            mesh.uv = uv;
        }
    }
}
