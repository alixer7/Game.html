using UnityEngine;

namespace TurboTribe
{
    /// <summary>Sky dome, sun, ambient and fog for a theme.</summary>
    public static class EnvironmentBuilder
    {
        public static GameObject Build(TrackTheme th, Transform parent, Vector3 center, int seed)
        {
            var root = new GameObject("Environment");
            root.transform.SetParent(parent, false);

            // sun
            var sunGo = new GameObject("Sun");
            sunGo.transform.SetParent(root.transform, false);
            sunGo.transform.rotation = Quaternion.Euler(th.SunEuler);
            var sun = sunGo.AddComponent<Light>();
            sun.type = LightType.Directional;
            sun.color = th.Sun;
            sun.intensity = 1.05f;
            sun.shadows = LightShadows.None;
            RenderSettings.sun = sun;

            RenderSettings.ambientMode = UnityEngine.Rendering.AmbientMode.Flat;
            RenderSettings.ambientLight = th.AmbSky;
            RenderSettings.fog = false; // custom fog in shaders
            Art.SetFog(th.Fog, th.FogStart, th.FogEnd);
            Art.SetAmbient(th.AmbSky, th.AmbGround);

            // sky dome (follows camera via SkyFollow)
            var mb = new MeshBuilder();
            int lat = 16, lon = 24;
            for (int y = 0; y <= lat; y++)
            {
                float v = y / (float)lat; // 0 top -> 1 bottom
                float phi = v * Mathf.PI;
                float h = Mathf.Cos(phi);
                Color c = h > 0 ? Color.Lerp(th.SkyHorizon, th.SkyTop, Mathf.Pow(h, 0.6f)) : Color.Lerp(th.SkyHorizon, th.SkyBottom, Mathf.Clamp01(-h * 3f));
                for (int x = 0; x <= lon; x++)
                {
                    float th2 = x / (float)lon * Mathf.PI * 2f;
                    Vector3 n = new Vector3(Mathf.Sin(phi) * Mathf.Cos(th2), h, Mathf.Sin(phi) * Mathf.Sin(th2));
                    mb.AddVertex(n * 900f, -n, c, Vector2.zero);
                }
            }
            int row = lon + 1;
            for (int y = 0; y < lat; y++)
                for (int x = 0; x < lon; x++)
                {
                    int a = y * row + x;
                    mb.AddTriangle(a, a + 1, a + row + 1);
                    mb.AddTriangle(a, a + row + 1, a + row);
                }
            var sky = mb.ToObject("SkyDome", root.transform, Art.Sky());
            var skyMat = Art.Sky();
            skyMat.SetVector("_SunDir", -sunGo.transform.forward);
            skyMat.SetColor("_SunColor", th.Sun);
            sky.AddComponent<SkyFollow>();

            // clouds ring
            var cmb = new MeshBuilder();
            var rng = new Rng(seed + 99);
            int clouds = th.Kind == ThemeKind.Canyon ? 7 : 12;
            for (int i = 0; i < clouds; i++)
            {
                float a = rng.Range(0, Mathf.PI * 2f);
                float d = rng.Range(380f, 520f);
                Vector3 p = center + new Vector3(Mathf.Cos(a) * d, rng.Range(90f, 150f), Mathf.Sin(a) * d);
                PropFactory.Cloud(cmb, p, rng.Range(14f, 26f), rng);
            }
            var cloudMat = Art.Toon("cloud", null, 0.35f);
            cmb.ToObject("Clouds", root.transform, cloudMat);
            return root;
        }
    }

    /// <summary>Keeps the sky dome centred on the active camera.</summary>
    public class SkyFollow : MonoBehaviour
    {
        void LateUpdate()
        {
            var cam = Camera.main;
            if (cam != null) transform.position = cam.transform.position;
        }
    }
}
