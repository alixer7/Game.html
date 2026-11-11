// Builds every track with the real TrackBuilder code (on the UnityShim) and writes OBJ files with vertex colours.
using System.Globalization;
using System.IO;
using System.Text;
using UnityEngine;

namespace TurboTribe.Headless
{
    public static class ExportTracks
    {
        public static string Run(string trackDir, string outDir)
        {
            Resources.TrackDir = trackDir;
            var sb = new StringBuilder();
            foreach (var id in TrackDatabase.Ids)
            {
                GameObject.All.Clear();
                var root = new GameObject("root");
                var t0 = System.Diagnostics.Stopwatch.StartNew();
                var ti = TrackBuilder.Build(TrackDatabase.Load(id), root.transform);
                long ms = t0.ElapsedMilliseconds;
                var obj = new StringBuilder(); var fol = new StringBuilder();
                int baseIdx = 1, verts = 0, tris = 0, fbase = 1;
                Texture2D atlas = null;
                foreach (var go in GameObject.All)
                {
                    var mf = go.GetComponent<MeshFilter>();
                    if (mf == null || mf.sharedMesh == null) continue;
                    if (go.name == "SkyDome" || go.name == "Clouds") continue;
                    var m = mf.sharedMesh;
                    var mr = go.GetComponent<MeshRenderer>();
                    if (mr != null && mr.sharedMaterial != null && mr.sharedMaterial.renderQueue == 2450)
                    {
                        // alpha-cutout foliage cards: separate file with UVs (rendered with the atlas)
                        atlas = mr.sharedMaterial.MainTex;
                        for (int i = 0; i < m.Vertices.Count; i++)
                        {
                            var v = m.Vertices[i]; Color c = m.Colors.Count > i ? (Color)m.Colors[i] : Color.white; var uv = m.UV.Count > i ? m.UV[i] : Vector2.zero;
                            fol.AppendFormat(CultureInfo.InvariantCulture, "v {0:F2} {1:F2} {2:F2} {3:F3} {4:F3} {5:F3}\nvt {6:F4} {7:F4}\n", v.x, v.y, v.z, c.r, c.g, c.b, uv.x, uv.y);
                        }
                        for (int i = 0; i < m.Triangles.Count; i += 3)
                            fol.Append("f ").Append(m.Triangles[i] + fbase).Append(' ').Append(m.Triangles[i + 1] + fbase).Append(' ').Append(m.Triangles[i + 2] + fbase).Append('\n');
                        fbase += m.Vertices.Count;
                        continue;
                    }
                    obj.Append("o ").Append(go.name).Append('\n');
                    for (int i = 0; i < m.Vertices.Count; i++)
                    {
                        var v = m.Vertices[i]; Color c = m.Colors.Count > i ? (Color)m.Colors[i] : Color.white;
                        if (go.name == "Water") c = new Color(0.2f, 0.5f, 0.9f);
                        var nn = m.Normals.Count > i ? m.Normals[i] : Vector3.zero;
                        obj.AppendFormat(CultureInfo.InvariantCulture, "v {0:F2} {1:F2} {2:F2} {3:F3} {4:F3} {5:F3} {6:F3} {7:F3} {8:F3}\n", v.x, v.y, v.z, c.r, c.g, c.b, nn.x, nn.y, nn.z);
                    }
                    for (int i = 0; i < m.Triangles.Count; i += 3)
                        obj.Append("f ").Append(m.Triangles[i] + baseIdx).Append(' ').Append(m.Triangles[i + 1] + baseIdx).Append(' ').Append(m.Triangles[i + 2] + baseIdx).Append('\n');
                    baseIdx += m.Vertices.Count; verts += m.Vertices.Count; tris += m.Triangles.Count / 3;
                }
                File.WriteAllText(Path.Combine(outDir, id + ".obj"), obj.ToString());
                File.WriteAllText(Path.Combine(outDir, id + "_foliage.obj"), fol.ToString());
                if (atlas != null && atlas.Px != null)
                {
                    var raw = new byte[atlas.Px.Length * 4];
                    for (int i = 0; i < atlas.Px.Length; i++) { raw[i * 4] = atlas.Px[i].r; raw[i * 4 + 1] = atlas.Px[i].g; raw[i * 4 + 2] = atlas.Px[i].b; raw[i * 4 + 3] = atlas.Px[i].a; }
                    File.WriteAllBytes(Path.Combine(outDir, "foliage_" + atlas.width + "x" + atlas.height + ".rgba"), raw);
                }
                sb.AppendLine($"{id}: built in {ms} ms, {verts} verts, {tris} tris, samples {ti.Spline.Count}, crates {ti.CrateSpots.Count}, fruit {ti.FruitSpots.Count}, pads {ti.Pads.Count}");
            }
            return sb.ToString();
        }
    }
}

namespace TurboTribe.Headless
{
    public static class ExportKarts
    {
        public static System.Text.StringBuilder Stats = new System.Text.StringBuilder();
        public static string Run(string outDir)
        {
            var mb = new MeshBuilder();
            for (int i = 0; i < CharacterDef.All.Length; i++)
            {
                var wheel = KartMeshes.BuildWheelMesh(Color.Lerp(CharacterDef.All[i].KartAccent, new Color(0.85f, 0.86f, 0.9f), 0.35f));
                var body = new MeshBuilder();
                KartMeshes.BuildChassis(body, CharacterDef.All[i]);
                int chassisV = body.VertexCount;
                KartMeshes.BuildDriver(body, CharacterDef.All[i]);
                Stats.AppendLine($"{CharacterDef.All[i].Name}: chassis {chassisV} driver {body.VertexCount - chassisV} wheel {wheel.Vertices.Count}");
                var m = Matrix4x4.TRS(new Vector3((i % 4) * 3.2f, 0, (i / 4) * -4.2f), Quaternion.Euler(0, 200, 0), Vector3.one);
                mb.Append(body, m);
                Vector3[] wp = KartMeshes.WheelPos;
                for (int w = 0; w < 4; w++)
                {
                    var wb = new MeshBuilder();
                    for (int k = 0; k < wheel.Vertices.Count; k++)
                    {
                        var v = wheel.Vertices[k]; if (w % 2 == 0) v.x = -v.x;
                        var wn = wheel.Normals.Count > k ? wheel.Normals[k] : Vector3.up; if (w % 2 == 0) wn.x = -wn.x;
                        wb.AddVertex(v, wn, wheel.Colors[k], Vector2.zero);
                    }
                    for (int k = 0; k < wheel.Triangles.Count; k += 3)
                        if (w % 2 == 0) wb.AddTriangle(wheel.Triangles[k], wheel.Triangles[k + 2], wheel.Triangles[k + 1]);
                        else wb.AddTriangle(wheel.Triangles[k], wheel.Triangles[k + 1], wheel.Triangles[k + 2]);
                    mb.Append(wb, Matrix4x4.TRS(m.MultiplyPoint3x4(wp[w]), Quaternion.Euler(0, 200, 0), Vector3.one * (w < 2 ? 1f : 1.12f)));
                }
            }
            var sb = new System.Text.StringBuilder();
            for (int i = 0; i < mb.V.Count; i++) { Color c = mb.C[i]; var nn = mb.N[i]; sb.AppendFormat(System.Globalization.CultureInfo.InvariantCulture, "v {0:F3} {1:F3} {2:F3} {3:F3} {4:F3} {5:F3} {6:F3} {7:F3} {8:F3}\n", mb.V[i].x, mb.V[i].y, mb.V[i].z, c.r, c.g, c.b, nn.x, nn.y, nn.z); }
            for (int i = 0; i < mb.T.Count; i += 3) sb.Append("f ").Append(mb.T[i] + 1).Append(' ').Append(mb.T[i + 1] + 1).Append(' ').Append(mb.T[i + 2] + 1).Append('\n');
            System.IO.File.WriteAllText(System.IO.Path.Combine(outDir, "karts.obj"), sb.ToString());
            return Stats.ToString() + "karts: " + mb.V.Count + " verts";
        }
    }
}
