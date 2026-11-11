using UnityEngine;

namespace TurboTribe
{
    /// <summary>3D menu backdrop: a little tropical island with the selected kart on a turntable.</summary>
    public class Showroom : MonoBehaviour
    {
        Transform turntable;
        GameObject kart;
        Camera cam;
        float t;
        public Vector3 CamOffset = new Vector3(-2.2f, 2.3f, -6.4f);
        public Vector3 LookOffset = new Vector3(-1.6f, 0.9f, 0f);

        public static Showroom Create(Transform parent)
        {
            var go = new GameObject("Showroom");
            go.transform.SetParent(parent, false);
            var s = go.AddComponent<Showroom>();
            s.Build();
            return s;
        }

        void Build()
        {
            var th = TrackTheme.Beach();
            EnvironmentBuilder.Build(th, transform, Vector3.zero, 5);
            var rng = new Rng(42);
            var mb = new MeshBuilder();
            var fol = new MeshBuilder();
            var glow = new MeshBuilder();
            // sand island
            mb.AddCylinder(Matrix4x4.TRS(new Vector3(0, -3f, 0), Quaternion.identity, Vector3.one), 40f, 30f, 3f, 28, th.TerrainLow * 0.9f, true, true, th.TerrainLow);
            mb.AddCylinder(Matrix4x4.TRS(new Vector3(0, -0.6f, 0), Quaternion.identity, Vector3.one), 30f, 22f, 0.6f, 28, th.TerrainMid, true, true, th.TerrainMid);
            // turntable base
            mb.AddCylinder(Matrix4x4.TRS(new Vector3(0, -0.05f, 0), Quaternion.identity, Vector3.one), 3.6f, 3.4f, 0.35f, 32, UIFactory.Hex("#7A4E2A"), true, true, UIFactory.Hex("#C98A45"));
            for (int i = 0; i < 9; i++)
            {
                float a = i / 9f * Mathf.PI * 2f + 0.3f;
                float d = rng.Range(9f, 18f);
                Vector3 p = new Vector3(Mathf.Cos(a) * d, -0.1f, Mathf.Sin(a) * d + 6f);
                if (p.z < -2f && Mathf.Abs(p.x) < 8f) continue; // keep the camera view clear
                PropFactory.PalmTree(mb, fol, p, rng.Range(1.0f, 1.4f), rng);
            }
            for (int i = 0; i < 6; i++)
                PropFactory.Rock(mb, new Vector3(rng.Range(-20f, 20f), -0.3f, rng.Range(8f, 22f)), rng.Range(1f, 2.5f), th.Cliff, th.TerrainHigh, rng);
            PropFactory.TikiHut(mb, fol, new Vector3(9f, -0.1f, 12f), 200f, 1.3f);
            PropFactory.Torch(mb, glow, new Vector3(-4.5f, 0f, 2.5f), 1f);
            PropFactory.Torch(mb, glow, new Vector3(4.5f, 0f, 2.5f), 1f);
            var rngG = new Rng(77);
            for (int g = 0; g < 160; g++)
            {
                float a = rngG.Range(0, Mathf.PI * 2f), d = rngG.Range(4.5f, 26f);
                Vector3 gp = new Vector3(Mathf.Cos(a) * d, -0.05f, Mathf.Sin(a) * d);
                if (gp.z < 0f && Mathf.Abs(gp.x) < 5f) continue;
                if (g % 5 == 0) PropFactory.Flowers(fol, gp, rngG); else PropFactory.Grass(fol, gp, rngG.Range(0.7f, 1.1f), th.TerrainMid * 1.2f, rngG);
            }
            mb.ToObject("Island", transform, Art.Toon("props", Art.Tex("grain", () => Art.GrainTexture(64, 0.12f, 11)), 0, default(Vector2), false, 0.1f, 0.28f, 0.2f));
            fol.ToObject("IslandFoliage", transform, Art.Foliage());
            glow.ToObject("IslandGlow", transform, Art.Glow);
            // sea
            var wmb = new MeshBuilder();
            int n = 30; float cell = 20f;
            for (int z = 0; z <= n; z++)
                for (int x = 0; x <= n; x++)
                {
                    Vector3 p = new Vector3((x - n / 2) * cell, -0.9f, (z - n / 2) * cell);
                    float d = new Vector2(p.x, p.z).magnitude;
                    wmb.AddVertex(p, Vector3.up, new Color(Mathf.Clamp01(1f - (d - 30f) / 25f), 0, 0, 1), Vector2.zero);
                }
            for (int z = 0; z < n; z++)
                for (int x = 0; x < n; x++)
                {
                    int a = z * (n + 1) + x;
                    wmb.AddTriangle(a, a + n + 1, a + n + 2);
                    wmb.AddTriangle(a, a + n + 2, a + 1);
                }
            wmb.ToObject("Sea", transform, Art.Water(th.WaterShallow, th.WaterDeep));

            turntable = new GameObject("Turntable").transform;
            turntable.SetParent(transform, false);
            turntable.localPosition = new Vector3(0, 0.3f, 0);

            var camGo = new GameObject("MenuCamera");
            camGo.transform.SetParent(transform, false);
            cam = camGo.AddComponent<Camera>();
            cam.fieldOfView = 40f;
            cam.nearClipPlane = 0.2f; cam.farClipPlane = 1500f;
            cam.clearFlags = CameraClearFlags.SolidColor;
            cam.backgroundColor = th.SkyHorizon;
            camGo.tag = "MainCamera";
            camGo.AddComponent<AudioListener>();
        }

        public void ShowCharacter(CharacterDef ch)
        {
            if (kart != null) Destroy(kart);
            kart = new GameObject("Kart");
            kart.transform.SetParent(turntable, false);
            var vis = KartModel.Build(ch, kart.transform);
            vis.ShadowT.localPosition = new Vector3(0, 0.02f, 0);
            Particles.Sparkle(turntable.position + Vector3.up);
            t = 0f;
        }

        void Update()
        {
            t += Time.deltaTime;
            if (turntable != null) turntable.localRotation = Quaternion.Euler(0, 150f + Time.time * 22f, 0);
            if (kart != null)
            {
                float pop = Mathf.Clamp01(t * 3f);
                kart.transform.localScale = Vector3.one * (pop < 1f ? Mathf.Lerp(0.6f, 1.08f, pop) : Mathf.Lerp(1.08f, 1f, Mathf.Clamp01((t - 0.33f) * 4f)));
                kart.transform.localPosition = new Vector3(0, Mathf.Abs(Mathf.Sin(Time.time * 2f)) * 0.06f, 0);
            }
            if (cam != null)
            {
                float sway = Mathf.Sin(Time.time * 0.4f) * 0.4f;
                cam.transform.position = transform.position + CamOffset + new Vector3(sway, 0, 0);
                cam.transform.LookAt(transform.position + LookOffset);
            }
        }
    }
}
