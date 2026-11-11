using System.Collections.Generic;
using UnityEngine;

namespace TurboTribe
{
    /// <summary>Builds the low-poly kart + driver for a character. Pivot at the ground contact, +Z forward.</summary>
    public static class KartModel
    {
        static Mesh flameMesh, bubbleMesh;

        static Matrix4x4 M(Vector3 p, Vector3 e, Vector3 s) { return Matrix4x4.TRS(p, Quaternion.Euler(e), s); }
        static Matrix4x4 M(Vector3 p) { return Matrix4x4.TRS(p, Quaternion.identity, Vector3.one); }
        static Color H(string hex) { Color c; ColorUtility.TryParseHtmlString(hex, out c); return c; }

        static readonly Dictionary<string, Mesh> bodyCache = new Dictionary<string, Mesh>();

        /// <summary>Chassis + sculpted driver for a character (cached: the raymarched heads are built only once).</summary>
        static Mesh BodyMesh(CharacterDef ch, bool lo)
        {
            string key = ch.Name + (lo ? "#lo" : "#hi");
            Mesh m;
            if (bodyCache.TryGetValue(key, out m) && m != null) return m;
            var mb = new MeshBuilder();
            KartMeshes.Lo = lo;
            KartMeshes.BuildChassis(mb, ch);
            KartMeshes.BuildDriver(mb, ch);
            KartMeshes.Lo = false;
            m = mb.ToMesh(lo ? "KartMeshLOD1" : "KartMesh");
            bodyCache[key] = m;
            return m;
        }

        static GameObject MeshObject(string name, Mesh mesh, Transform parent, Material mat)
        {
            var go = new GameObject(name);
            go.transform.SetParent(parent, false);
            go.AddComponent<MeshFilter>().sharedMesh = mesh;
            var mr = go.AddComponent<MeshRenderer>();
            mr.sharedMaterial = mat;
            mr.shadowCastingMode = UnityEngine.Rendering.ShadowCastingMode.Off;
            mr.receiveShadows = false;
            return go;
        }

        public static KartVisual Build(CharacterDef ch, Transform parent)
        {
            var root = new GameObject("Visual");
            root.transform.SetParent(parent, false);
            var vis = root.AddComponent<KartVisual>();

            var bodyPivot = new GameObject("Body").transform;
            bodyPivot.SetParent(root.transform, false);
            vis.Body = bodyPivot;

            var kartMat = Art.Toon("kart", Art.Tex("grain", () => Art.GrainTexture(64, 0.10f, 11)), 0, default(Vector2), false, 0.1f, 0.35f, 0.35f);
            // the sculpted driver + chassis are built once per character and LOD, then shared (menus, every race)
            var bodyGo = MeshObject("KartMesh", BodyMesh(ch, false), bodyPivot, kartMat);
            bodyGo.transform.localPosition = Vector3.zero;
            // distant LOD: same silhouette, half the tessellation, no small parts
            KartMeshes.Lo = true;
            var wheelLo = KartMeshes.BuildWheelMesh(Color.Lerp(ch.KartAccent, new Color(0.85f, 0.86f, 0.9f), 0.35f));
            KartMeshes.Lo = false;
            var bodyLo = MeshObject("KartMeshLOD1", BodyMesh(ch, true), bodyPivot, kartMat);
            var lod0 = new List<Renderer> { bodyGo.GetComponent<Renderer>() };
            var lod1 = new List<Renderer> { bodyLo.GetComponent<Renderer>() };

            // wheels
            var wheelMesh = KartMeshes.BuildWheelMesh(Color.Lerp(ch.KartAccent, new Color(0.85f, 0.86f, 0.9f), 0.35f));
            Vector3[] wp = KartMeshes.WheelPos;
            float[] ws = KartMeshes.WheelScale;
            vis.Wheels = new Transform[4];
            vis.WheelPivots = new Transform[4];
            for (int i = 0; i < 4; i++)
            {
                var pivot = new GameObject("WheelPivot" + i).transform;
                pivot.SetParent(root.transform, false);
                pivot.localPosition = wp[i];
                var w = new GameObject("Wheel" + i);
                w.transform.SetParent(pivot, false);
                w.transform.localScale = new Vector3(i % 2 == 0 ? -ws[i] : ws[i], ws[i], ws[i]);
                w.AddComponent<MeshFilter>().sharedMesh = wheelMesh;
                var mr = w.AddComponent<MeshRenderer>();
                mr.sharedMaterial = kartMat;
                mr.shadowCastingMode = UnityEngine.Rendering.ShadowCastingMode.Off;
                lod0.Add(mr);
                var wl = new GameObject("WheelLOD1");
                wl.transform.SetParent(w.transform, false);
                wl.AddComponent<MeshFilter>().sharedMesh = wheelLo;
                var mrl = wl.AddComponent<MeshRenderer>();
                mrl.sharedMaterial = kartMat;
                mrl.shadowCastingMode = UnityEngine.Rendering.ShadowCastingMode.Off;
                lod1.Add(mrl);
                vis.Wheels[i] = w.transform;
                vis.WheelPivots[i] = pivot;
            }

            var lg = root.AddComponent<LODGroup>();
            lg.SetLODs(new[] { new LOD(0.12f, lod0.ToArray()), new LOD(0.01f, lod1.ToArray()) });
            lg.RecalculateBounds();

            // exhausts + flames
            vis.Exhausts = new Transform[2];
            vis.Flames = new Transform[2];
            if (flameMesh == null)
            {
                var fm = new MeshBuilder();
                fm.AddCone(M(Vector3.zero, new Vector3(-90, 0, 0), Vector3.one), 0.16f, 0.9f, 7, H("#FFE36A"), H("#FF5A1A"));
                flameMesh = fm.ToMesh("Flame");
            }
            for (int i = 0; i < 2; i++)
            {
                var ex = new GameObject("Exhaust" + i).transform;
                ex.SetParent(bodyPivot, false);
                ex.localPosition = KartMeshes.ExhaustTips[i] + new Vector3(0, 0, -0.04f);
                vis.Exhausts[i] = ex;
                var fl = new GameObject("Flame" + i);
                fl.transform.SetParent(ex, false);
                fl.AddComponent<MeshFilter>().sharedMesh = flameMesh;
                var mr = fl.AddComponent<MeshRenderer>();
                mr.sharedMaterial = Art.Glow;
                fl.transform.localScale = Vector3.zero;
                vis.Flames[i] = fl.transform;
            }

            // shield bubble
            if (bubbleMesh == null)
            {
                var bm = new MeshBuilder();
                bm.AddSphere(Matrix4x4.identity, 1.6f, 10, 16, new Color(0.4f, 0.9f, 1f, 0.35f), new Color(0.2f, 0.6f, 1f, 0.5f));
                bubbleMesh = bm.ToMesh("Bubble");
            }
            var bubble = new GameObject("Shield");
            bubble.transform.SetParent(root.transform, false);
            bubble.transform.localPosition = new Vector3(0, 0.8f, 0);
            bubble.AddComponent<MeshFilter>().sharedMesh = bubbleMesh;
            bubble.AddComponent<MeshRenderer>().sharedMaterial = Art.Particle(true);
            bubble.SetActive(false);
            vis.Shield = bubble;

            // star aura (reuses bubble, golden)
            var aura = new GameObject("StarAura");
            aura.transform.SetParent(root.transform, false);
            aura.transform.localPosition = new Vector3(0, 0.8f, 0);
            aura.transform.localScale = Vector3.one * 1.1f;
            var am = new MeshBuilder();
            am.AddSphere(Matrix4x4.identity, 1.5f, 8, 12, new Color(1f, 0.9f, 0.3f, 0.35f), new Color(1f, 0.5f, 0.1f, 0.25f));
            aura.AddComponent<MeshFilter>().sharedMesh = am.ToMesh("Aura");
            aura.AddComponent<MeshRenderer>().sharedMaterial = Art.Particle(true);
            aura.SetActive(false);
            vis.Aura = aura;

            // blob shadow (positioned on the ground by KartVisual)
            var sh = new GameObject("BlobShadow");
            sh.transform.SetParent(parent, false);
            var smb = new MeshBuilder();
            smb.AddQuad(new Vector3(-1.1f, 0, -1.4f), new Vector3(-1.1f, 0, 1.4f), new Vector3(1.1f, 0, 1.4f), new Vector3(1.1f, 0, -1.4f),
                new Color(0, 0, 0, 0.55f), new Vector2(0, 0), new Vector2(0, 1), new Vector2(1, 1), new Vector2(1, 0));
            sh.AddComponent<MeshFilter>().sharedMesh = smb.ToMesh("Shadow");
            sh.AddComponent<MeshRenderer>().sharedMaterial = Art.Particle(false);
            vis.ShadowT = sh.transform;
            return vis;
        }

    }
}
