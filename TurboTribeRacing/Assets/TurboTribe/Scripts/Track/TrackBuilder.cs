using System.Collections.Generic;
using UnityEngine;

namespace TurboTribe
{
    /// <summary>
    /// Builds a complete multi-road race track from TrackData (v3):
    /// main loop + branches (shortcuts / alternate routes, hidden skill shortcuts that start beside the road or
    /// cross a gap), variable width, walled / low-walled / open (shoulder) / cliff sides, bumps, dips, rumble strips,
    /// half-road humps, hanging curtains, environment zones, kickers, pads, mud, tunnels, bridges, start arch,
    /// minimap, and the solid-scenery list karts collide with. Terrain, water and decoration live in TrackTerrain.cs.
    /// </summary>
    public static partial class TrackBuilder
    {
        public const float CurbW = 0.9f;
        public const float WallThick = 0.7f;
        public const float ShoulderW = 4f;

        public static TrackInstance Build(TrackData data, Transform parent)
        {
            var root = new GameObject("Track_" + data.id);
            root.transform.SetParent(parent, false);
            var ti = root.AddComponent<TrackInstance>();
            ti.Data = data;
            ti.Theme = TrackTheme.Get(data.theme);
            ti.WaterLevel = data.waterLevel;
            int seed = StableHash(data.id);

            // zones -------------------------------------------------------
            var zoneIds = new List<string>();
            foreach (var z in data.zones) if (!zoneIds.Contains(z.style)) zoneIds.Add(z.style);
            if (zoneIds.Count == 0) zoneIds.Add(data.theme == "canyon" ? "desert" : data.theme == "snow" ? "alpine" : "beach");
            foreach (var id in zoneIds) ti.Zones.Add(ZoneStyle.Get(id));

            // roads -------------------------------------------------------
            for (int r = 0; r < data.roads.Count; r++)
            {
                var rd = data.roads[r];
                Road road = r == 0 ? BuildMainRoad(data, rd, ti) : BuildBranchRoad(data, rd, r, ti);
                if (road != null) ti.Roads.Add(road);
            }
            foreach (var road in ti.Roads) AssignFlags(data, road, ti, zoneIds);
            OpenJunctions(ti);
            ti.BuildHash();

            // geometry ----------------------------------------------------
            foreach (var road in ti.Roads)
            {
                BuildRoadSurface(ti, road, root.transform);
                BuildWalls(ti, road, root.transform);
            }
            BuildEvents(ti, root.transform);
            BuildTerrain(ti, root.transform, seed);
            BuildWater(ti, root.transform);
            BuildLandmarks(ti, root.transform, seed);
            foreach (var road in ti.Roads) BuildTunnels(ti, road, root.transform, seed);
            BuildPillars(ti, root.transform);
            BuildStartArch(ti, root.transform);
            BuildCurtains(ti, root.transform);
            BuildGateways(ti, root.transform);
            BuildSigns(ti, root.transform);
            BuildDecorations(ti, root.transform, seed);
            BuildFruit(ti);
            BuildMinimap(ti);
            Vector3 center = Vector3.zero;
            var ms = ti.Spline;
            for (int i = 0; i < ms.Count; i += 10) center += ms.Pos[i];
            center /= Mathf.Ceil(ms.Count / 10f);
            EnvironmentBuilder.Build(ti.Theme, root.transform, center, seed);
            return ti;
        }

        /// <summary>Registers a solid scenery cylinder unless it would stand on a drivable surface
        /// (a solid must never block a road - roads are bounded by walls, not by props).</summary>
        public static bool SolidAt(TrackInstance ti, Vector3 c, float radius, float height)
        {
            if (!ClearOfRoadSurfaces(ti, c, radius, height)) return false;
            ti.AddSolid(c, radius, height);
            return true;
        }

        static bool ClearOfRoadSurfaces(TrackInstance ti, Vector3 c, float radius, float height)
        {
            float y0 = c.y - 2f, y1 = c.y + Mathf.Max(1f, height);
            foreach (var r in ti.Roads)
            {
                var s = r.S;
                for (int i = 0; i < s.Count; i += 2)
                {
                    Vector3 p = s.Pos[i];
                    if (p.y < y0 - 1f || p.y > y1 + 0.5f) continue;
                    float dx = p.x - c.x, dz = p.z - c.z, lim = s.HalfWidth[i] + radius + 0.3f;
                    if (dx * dx + dz * dz < lim * lim) return false;
                }
            }
            return true;
        }

        public static int StableHash(string s)
        {
            unchecked { int h = 23; foreach (char c in s) h = h * 31 + c; return h & 0xFFFF; }
        }

        // ------------------------------------------------------------------ roads
        static List<HeightMod> ModsFor(TrackData data, string road)
        {
            var mods = new List<HeightMod>();
            foreach (var e in data.events)
            {
                if (e.road != road) continue;
                if (e.type == "bump") mods.Add(new HeightMod(e.t, e.h, e.len));
                else if (e.type == "dip") mods.Add(new HeightMod(e.t, -Mathf.Abs(e.h), e.len));
                else if (e.type == "rumble") mods.Add(new HeightMod(e.t, e.h, e.len, e.count));
            }
            return mods;
        }

        static Road NewRoad(int id, string name, TrackSpline s)
        {
            int n = s.Count;
            var r = new Road
            {
                Id = id, Name = name, S = s, IsMain = id == 0,
                Gap = new bool[n], Ice = new bool[n], Tunnel = new bool[n], WallL = new bool[n], WallR = new bool[n],
                CliffL = new bool[n], CliffR = new bool[n], ShoulderL = new bool[n], ShoulderR = new bool[n],
                LowL = new bool[n], LowR = new bool[n], Trail = new bool[n],
                MainIdx = new float[n], AiLane = new float[n], HumpLane = new float[n], SecretLane = new float[n], Zone = new int[n]
            };
            for (int i = 0; i < n; i++) { r.WallL[i] = r.WallR[i] = true; r.AiLane[i] = float.NaN; r.HumpLane[i] = float.NaN; r.SecretLane[i] = float.NaN; }
            return r;
        }

        static Road BuildMainRoad(TrackData data, RoadData rd, TrackInstance ti)
        {
            var s = TrackSpline.Build(rd.points, 1f, true, ModsFor(data, rd.id));
            var r = NewRoad(0, rd.id, s);
            r.Kind = "main";
            r.StartIdx = 0; r.EndIdx = s.Count - 1;
            for (int i = 0; i < s.Count; i++) r.MainIdx[i] = i;
            return r;
        }

        static Road BuildBranchRoad(TrackData data, RoadData rd, int id, TrackInstance ti)
        {
            var main = ti.Roads[0].S;
            if (rd.from == null || rd.to == null || rd.points == null) return null;
            int ia = main.IndexOfParam(rd.from.t), ib = main.IndexOfParam(rd.to.t);
            float w = rd.points.Count > 0 ? rd.points[0].w : 14f;
            float w2 = rd.points.Count > 0 ? rd.points[rd.points.Count - 1].w : w;
            var pts = new List<TrackPointData>();
            System.Action<int, float> addMain = (idx, width) =>
            {
                Vector3 p = main.Pos[main.Wrap(idx)];
                pts.Add(new TrackPointData { x = p.x, y = p.y, z = p.z, w = width });
            };
            // an attached end overlaps the main road (a normal fork); a detached end sits beside / above it and is
            // reached with a jump (over a low wall, off a ledge)
            if (!rd.detachStart) { addMain(ia - 12, w); addMain(ia, w); }
            pts.AddRange(rd.points);
            if (!rd.detachEnd) { addMain(ib, w2); addMain(ib + 12, w2); }
            if (pts.Count < 2) return null;
            var s = TrackSpline.Build(pts, 1f, false, ModsFor(data, rd.id));
            var r = NewRoad(id, rd.id, s);
            r.Kind = rd.kind;
            r.Hidden = rd.hidden;
            r.DetachStart = rd.detachStart; r.DetachEnd = rd.detachEnd;
            r.FromMain = ia; r.ToMain = ib;
            int first = rd.detachStart ? 0 : s.IndexOfParam(1f);
            int last = rd.detachEnd ? s.Count - 1 : s.IndexOfParam(pts.Count - 2);
            r.StartIdx = first; r.EndIdx = last;
            // progress mapping onto the main loop
            int N = main.Count;
            float ibu = ib < ia ? ib + N : ib;
            int hint = ia;
            for (int i = 0; i < s.Count; i++)
            {
                if (i <= first) { hint = main.Nearest(s.Pos[i], hint, 30); r.MainIdx[i] = hint; }
                else if (i >= last) { hint = main.Nearest(s.Pos[i], i == last ? ib : hint, 30); r.MainIdx[i] = hint; }
                else r.MainIdx[i] = Mathf.Repeat(Mathf.Lerp(ia, ibu, (i - first) / (float)Mathf.Max(1, last - first)), N);
            }
            return r;
        }

        /// <summary>Lightweight splines (main + branches) for menus / previews, no meshes.</summary>
        public static List<TrackSpline> PreviewSplines(TrackData data, float step = 2f)
        {
            var list = new List<TrackSpline>();
            if (data.Main == null) return list;
            var main = TrackSpline.Build(data.Main.points, step, true);
            list.Add(main);
            for (int r = 1; r < data.roads.Count; r++)
            {
                var rd = data.roads[r];
                if (rd.from == null || rd.to == null || rd.points == null || rd.points.Count == 0 || rd.hidden) continue;
                int ia = main.IndexOfParam(rd.from.t), ib = main.IndexOfParam(rd.to.t);
                var pts = new List<TrackPointData>();
                System.Action<int> addMain = idx => { Vector3 p = main.Pos[main.Wrap(idx)]; pts.Add(new TrackPointData { x = p.x, y = p.y, z = p.z, w = 12f }); };
                if (!rd.detachStart) { addMain(ia - Mathf.RoundToInt(12 / step)); addMain(ia); }
                pts.AddRange(rd.points);
                if (!rd.detachEnd) { addMain(ib); addMain(ib + Mathf.RoundToInt(12 / step)); }
                if (pts.Count < 2) continue;
                list.Add(TrackSpline.Build(pts, step, false));
            }
            return list;
        }

        static void AssignFlags(TrackData data, Road r, TrackInstance ti, List<string> zoneIds)
        {
            var s = r.S;
            int N = ti.Roads[0].S.Count;
            var mainS = ti.Roads[0].S;
            for (int i = 0; i < s.Count; i++)
            {
                float p = s.Param[i];
                string nm = r.Name;
                r.Gap[i] = data.InRange(nm, "gap", p);
                r.Ice[i] = data.InRange(nm, "ice", p);
                r.Trail[i] = data.InRange(nm, "trail", p);
                r.Tunnel[i] = data.InRange(nm, "tunnel", p);
                bool open = data.InRange(nm, "open", p), cliff = data.InRange(nm, "cliff", p);
                if (open || data.InRange(nm, "openL", p)) { r.WallL[i] = false; r.ShoulderL[i] = true; }
                if (open || data.InRange(nm, "openR", p)) { r.WallR[i] = false; r.ShoulderR[i] = true; }
                if (cliff || data.InRange(nm, "cliffL", p)) { r.WallL[i] = false; r.CliffL[i] = true; r.ShoulderL[i] = false; }
                if (cliff || data.InRange(nm, "cliffR", p)) { r.WallR[i] = false; r.CliffR[i] = true; r.ShoulderR[i] = false; }
                bool low = data.InRange(nm, "low", p);
                if (low || data.InRange(nm, "lowL", p)) { r.WallL[i] = true; r.LowL[i] = true; r.ShoulderL[i] = r.CliffL[i] = false; }
                if (low || data.InRange(nm, "lowR", p)) { r.WallR[i] = true; r.LowR[i] = true; r.ShoulderR[i] = r.CliffR[i] = false; }
                // bare edge: no wall, no shoulder (a branch landing strip right beside a low wall)
                if (data.InRange(nm, "bareL", p)) { r.WallL[i] = r.ShoulderL[i] = r.CliffL[i] = r.LowL[i] = false; }
                if (data.InRange(nm, "bareR", p)) { r.WallR[i] = r.ShoulderR[i] = r.CliffR[i] = r.LowR[i] = false; }
                if (r.Tunnel[i]) { r.WallL[i] = r.WallR[i] = true; r.LowL[i] = r.LowR[i] = false; r.CliffL[i] = r.CliffR[i] = r.ShoulderL[i] = r.ShoulderR[i] = false; }
                if (r.Gap[i] || r.LowL[i] || r.LowR[i]) r.NeedsJump = r.NeedsJump || !r.IsMain;
                // zone from the main-road position
                float mp = mainS.Param[Mathx.Wrap(Mathf.RoundToInt(r.MainIdx[i]), N)];
                string style = null;
                foreach (var z in data.zones)
                {
                    bool inZ = z.a <= z.b ? (mp >= z.a && mp < z.b) : (mp >= z.a || mp < z.b);
                    if (inZ) { style = z.style; break; }
                }
                int zi = style != null ? zoneIds.IndexOf(style) : 0;
                r.Zone[i] = Mathf.Max(0, zi);
            }
            if (r.DetachStart || r.DetachEnd) r.NeedsJump = true;
            foreach (var e in data.events)
            {
                // only the "half-road" humps (lane +-1) are race-line material; a hump placed off-centre on purpose is a
                // secret's launcher towards a low wall - CPUs only use it when they go for that secret
                if (e.road != r.Name || e.type != "hump") continue;
                if (Mathf.Abs(e.lane) < 0.99f)
                {
                    // off-centre hump on a road = the launcher of a secret (towards a low wall / ledge)
                    int ci = s.IndexOfParam(e.t);
                    for (int k = -40; k <= 3; k++)
                    {
                        int j = ci + k;
                        if (!s.Closed && (j < 0 || j >= s.Count)) continue;
                        r.SecretLane[s.Wrap(j)] = e.lane;
                    }
                    continue;
                }
                int idx = s.IndexOfParam(e.t);
                float lane = HumpLaneFrac(e);
                for (int k = -40; k <= 2; k++)
                {
                    int j = idx + k;
                    if (!s.Closed && (j < 0 || j >= s.Count)) continue;
                    r.HumpLane[s.Wrap(j)] = lane;
                }
            }
            foreach (var e in data.events)
            {
                // a launcher on a branch (hidden shortcut dune / rock lip) is THE line: CPUs that go for it aim at its centre
                bool launcher = e.type == "hump" && !r.IsMain && Mathf.Abs(e.lane) < 0.99f;
                if (e.road != r.Name || (e.type != "pad" && e.type != "ramp" && !launcher)) continue;
                int idx = s.IndexOfParam(e.t);
                int from = e.type == "pad" ? -35 : -45, to = e.type == "pad" ? 4 : 1;
                for (int k = from; k <= to; k++)
                {
                    int j = idx + k;
                    if (!s.Closed && (j < 0 || j >= s.Count)) continue;
                    r.AiLane[s.Wrap(j)] = e.lane;
                }
            }
        }

        /// <summary>Opens walls where a branch overlaps the main road so karts can drive between them.
        /// Main's wall only opens where the branch surface actually reaches past main's edge; the branch's
        /// wall only on the side facing main. Once the surfaces separate, both keep their walls (a walled gore).</summary>
        static void OpenJunctions(TrackInstance ti)
        {
            var main = ti.Roads[0];
            var ms = main.S;
            for (int b = 1; b < ti.Roads.Count; b++)
            {
                var br = ti.Roads[b]; var bs = br.S;
                for (int k = 0; k < bs.Count; k++)
                {
                    if (br.DetachStart && k < bs.Count / 2) continue;
                    if (br.DetachEnd && k >= bs.Count / 2) continue;
                    int hint = ms.Nearest(bs.Pos[k], Mathf.RoundToInt(br.MainIdx[k]), 25);
                    Vector3 d = bs.Pos[k] - ms.Pos[hint];
                    if (Mathf.Abs(d.y) > 3f) continue;
                    float lat = ms.Lateral(bs.Pos[k], hint);
                    float hwM = ms.HalfWidth[hint], hwB = bs.HalfWidth[k];
                    if (Mathf.Abs(lat) >= hwM + hwB - 1.0f) continue;          // surfaces no longer overlap
                    int sideMain = lat >= 0 ? 1 : -1;
                    if (Mathf.Abs(lat) + hwB > hwM - 0.3f)
                        for (int q = -3; q <= 3; q++)
                        {
                            int j = ms.Wrap(hint + q);
                            if (sideMain < 0) { main.WallL[j] = false; main.CliffL[j] = false; }
                            else { main.WallR[j] = false; main.CliffR[j] = false; }
                        }
                    int sideBr = bs.Lateral(ms.Pos[hint], k) >= 0 ? 1 : -1;
                    if (sideBr < 0) { br.WallL[k] = false; br.ShoulderL[k] = false; br.CliffL[k] = false; }
                    else { br.WallR[k] = false; br.ShoulderR[k] = false; br.CliffR[k] = false; }
                    if (Mathf.Abs(lat) + hwB < hwM + 0.5f) { br.WallL[k] = br.WallR[k] = false; br.ShoulderL[k] = br.ShoulderR[k] = false; br.CliffL[k] = br.CliffR[k] = false; }
                }
            }
        }

        static bool SkipBranchSurface(TrackInstance ti, Road r, int i)
        {
            if (r.IsMain) return false;
            var ms = ti.Roads[0].S;
            int j = ms.Nearest(r.S.Pos[i], Mathf.RoundToInt(r.MainIdx[i]), 20);
            Vector3 d = r.S.Pos[i] - ms.Pos[j];
            if (Mathf.Abs(d.y) > 1.5f) return false;
            return Mathf.Sqrt(d.x * d.x + d.z * d.z) + r.S.HalfWidth[i] * 0.85f < ms.HalfWidth[j];
        }

        // ------------------------------------------------------------------ road surface
        static void BuildRoadSurface(TrackInstance ti, Road road, Transform parent)
        {
            var s = road.S; int n = s.Count;
            var mb = new MeshBuilder(); var ice = new MeshBuilder(); var under = new MeshBuilder(); var shoulder = new MeshBuilder(); var cliffs = new MeshBuilder();
            int segs = s.Closed ? n : n - 1;
            float lift = road.IsMain ? 0f : 0.03f;
            float vDist = 0f;
            for (int i = 0; i < segs; i++)
            {
                int j = s.Wrap(i + 1);
                vDist += s.Step;
                if (road.Gap[i] || road.Gap[j]) continue;
                bool skip = SkipBranchSurface(ti, road, i) && SkipBranchSurface(ti, road, j);
                var z = ti.ZoneAt(road, i);
                float hw0 = s.HalfWidth[i], hw1 = s.HalfWidth[j];
                float v0 = (vDist - s.Step) / 10f, v1 = vDist / 10f;
                if (!skip)
                {
                    bool isIce = road.Ice[i];
                    var target = isIce ? ice : mb;
                    float[] c0 = { -hw0, -hw0 + CurbW, hw0 - CurbW, hw0 };
                    float[] c1 = { -hw1, -hw1 + CurbW, hw1 - CurbW, hw1 };
                    bool block = ((i / 3) % 2) == 0;
                    // centre with edge darkening + subtle wear variation
                    float wear = 0.94f + Noise.Value(i * 0.13f, road.Id * 7.1f, 3) * 0.08f;
                    bool trail = road.Trail[i];
                    // a secret trail blends into the ground around it (sand / dirt / packed snow, no curbs)
                    Color trailCol = Color.Lerp(z.Shoulder, z.TerrainLow, 0.35f) * (0.97f + Noise.Value(i * 0.21f, road.Id, 9) * 0.06f);
                    Color mid = (isIce ? new Color(0.72f, 0.9f, 1f) : trail ? trailCol : z.Road) * wear; mid.a = 1;
                    AddRoadStrip(target, s.PointAt(i, c0[1], lift), s.PointAt(j, c1[1], lift), s.PointAt(j, c1[2], lift), s.PointAt(i, c0[2], lift),
                        mid, trail ? trailCol * 0.9f : z.RoadEdge, hw0, v0, v1);
                    for (int side = -1; side <= 1; side += 2)
                    {
                        bool cliff = side < 0 ? road.CliffL[i] : road.CliffR[i];
                        Color cc = block ? z.CurbA : z.CurbB;
                        if (trail) cc = trailCol * (block ? 0.92f : 0.86f);
                        if (cliff) cc = block ? new Color(1f, 0.85f, 0.1f) : new Color(0.12f, 0.12f, 0.14f); // hazard curbs at drops
                        int a = side < 0 ? 0 : 2;
                        // slightly raised outer lip gives curbs a 3D read
                        float li = lift + 0.02f, lo = lift + 0.07f;
                        Vector3 p0 = s.PointAt(i, c0[a], side < 0 ? lo : li), p1 = s.PointAt(j, c1[a], side < 0 ? lo : li);
                        Vector3 p2 = s.PointAt(j, c1[a + 1], side < 0 ? li : lo), p3 = s.PointAt(i, c0[a + 1], side < 0 ? li : lo);
                        target.AddQuad(p0, p1, p2, p3, cc, new Vector2(0, v0), new Vector2(0, v1), new Vector2(0.2f, v1), new Vector2(0.2f, v0));
                    }
                }
                // underside (bridges / overhangs)
                float ext0 = hw0 + WallThick, ext1 = hw1 + WallThick;
                under.AddQuad(s.PointAt(i, ext0, -1.6f), s.PointAt(j, ext1, -1.6f), s.PointAt(j, -ext1, -1.6f), s.PointAt(i, -ext0, -1.6f), z.Underside);
                // shoulders on open sides
                for (int side = -1; side <= 1; side += 2)
                {
                    bool sh0 = side < 0 ? road.ShoulderL[i] : road.ShoulderR[i];
                    bool sh1 = side < 0 ? road.ShoulderL[j] : road.ShoulderR[j];
                    if (sh0 && sh1)
                    {
                        Color sc = z.Shoulder * (0.95f + Noise.Value(i * 0.4f, side, 9) * 0.1f); sc.a = 1;
                        Vector3 a0 = s.PointAt(i, side * hw0, lift - 0.02f), a1 = s.PointAt(j, side * hw1, lift - 0.02f);
                        Vector3 b0 = s.PointAt(i, side * (hw0 + ShoulderW), lift - 0.2f), b1 = s.PointAt(j, side * (hw1 + ShoulderW), lift - 0.2f);
                        if (side < 0) shoulder.AddQuad(b0, b1, a1, a0, sc); else shoulder.AddQuad(a0, a1, b1, b0, sc);
                    }
                    bool cl0 = side < 0 ? road.CliffL[i] : road.CliffR[i];
                    if (cl0)
                    {
                        Vector3 t0 = s.PointAt(i, side * hw0, lift), t1 = s.PointAt(j, side * hw1, lift);
                        Vector3 b0 = t0 + Vector3.down * 9f, b1 = t1 + Vector3.down * 9f;
                        Color cc = z.Cliff * (0.85f + Noise.Value(i * 0.3f, 2, 4) * 0.2f); cc.a = 1;
                        if (side < 0) cliffs.AddQuad(b1, t1, t0, b0, cc); else cliffs.AddQuad(b0, t0, t1, b1, cc);
                    }
                }
            }
            var roadMat = Art.Toon("road", Art.Tex("road", () => Art.RoadTexture(7)), 0, default(Vector2), false, 0.1f, 0.15f);
            if (mb.VertexCount > 0)
            {
                var go = mb.ToObject("Road_" + road.Name, parent, roadMat, Layers.Ground);
                ti.Surfaces[go.GetComponent<Collider>()] = SurfaceType.Road;
                Shadows(go, false, true);
            }
            if (ice.VertexCount > 0)
            {
                var ig = ice.ToObject("Ice_" + road.Name, parent, Art.Toon("ice", Art.Tex("road_ice", () => Art.RoadTexture(31)), 0.2f, default(Vector2), false, 0.1f, 0.7f, 0.9f), Layers.Ground);
                ti.Surfaces[ig.GetComponent<Collider>()] = SurfaceType.Ice;
            }
            if (shoulder.VertexCount > 0)
            {
                var sg = shoulder.ToObject("Shoulder_" + road.Name, parent, Art.Toon("shoulder", Art.Tex("tgrain", () => Art.GrainTexture(64, 0.22f, 5)), 0, default(Vector2), true, 0.25f, 0.1f), Layers.Ground);
                ti.Surfaces[sg.GetComponent<Collider>()] = SurfaceType.Offroad;
                Shadows(sg, false, true);
            }
            if (cliffs.VertexCount > 0) cliffs.ToObject("Cliffs_" + road.Name, parent, Art.Plain);
            under.ToObject("Underside_" + road.Name, parent, Art.Plain);
        }

        public static void Shadows(GameObject go, bool cast, bool receive)
        {
            var mr = go.GetComponent<MeshRenderer>();
            if (mr == null) return;
            bool on = Settings.Quality >= 2;
            mr.shadowCastingMode = on && cast ? UnityEngine.Rendering.ShadowCastingMode.On : UnityEngine.Rendering.ShadowCastingMode.Off;
            mr.receiveShadows = on && receive;
        }

        static void AddRoadStrip(MeshBuilder mb, Vector3 a, Vector3 b, Vector3 c, Vector3 d, Color mid, Color edge, float hw, float v0, float v1)
        {
            const int parts = 6;
            for (int k = 0; k < parts; k++)
            {
                float t0 = k / (float)parts, t1 = (k + 1) / (float)parts;
                Vector3 pa = Vector3.Lerp(a, d, t0), pb = Vector3.Lerp(b, c, t0), pc = Vector3.Lerp(b, c, t1), pd = Vector3.Lerp(a, d, t1);
                float e0 = Mathf.Abs(t0 - 0.5f) * 2f, e1 = Mathf.Abs(t1 - 0.5f) * 2f;
                // tyre-worn racing grooves at ~30% from each edge
                float g0 = 1f - 0.05f * Mathf.Exp(-Mathf.Pow((Mathf.Abs(t0 - 0.5f) - 0.2f) * 9f, 2f));
                float g1 = 1f - 0.05f * Mathf.Exp(-Mathf.Pow((Mathf.Abs(t1 - 0.5f) - 0.2f) * 9f, 2f));
                Color c0 = Color.Lerp(mid, edge, e0 * e0 * 0.75f) * g0, c1 = Color.Lerp(mid, edge, e1 * e1 * 0.75f) * g1;
                c0.a = c1.a = 1;
                Vector3 nrm = Vector3.Cross(pb - pa, pd - pa).normalized;
                float u0 = t0 * hw / 4f, u1 = t1 * hw / 4f;
                int i0 = mb.AddVertex(pa, nrm, c0, new Vector2(u0, v0));
                mb.AddVertex(pb, nrm, c0, new Vector2(u0, v1));
                mb.AddVertex(pc, nrm, c1, new Vector2(u1, v1));
                mb.AddVertex(pd, nrm, c1, new Vector2(u1, v0));
                mb.AddTriangle(i0, i0 + 1, i0 + 2);
                mb.AddTriangle(i0, i0 + 2, i0 + 3);
            }
        }

        // ------------------------------------------------------------------ walls
        static void BuildWalls(TrackInstance ti, Road road, Transform parent)
        {
            var s = road.S; int n = s.Count;
            var mb = new MeshBuilder(); var caps = new MeshBuilder();
            int segs = s.Closed ? n : n - 1;
            float lift = road.IsMain ? 0f : 0.03f;
            for (int i = 0; i < segs; i++)
            {
                int j = s.Wrap(i + 1);
                if (road.Gap[i] || road.Gap[j])
                {
                    if (!road.Gap[i] && road.Gap[j]) EndCap(caps, s, i, true, ti.ZoneAt(road, i));
                    if (road.Gap[i] && !road.Gap[j]) EndCap(caps, s, j, false, ti.ZoneAt(road, j));
                    continue;
                }
                var z = ti.ZoneAt(road, i);
                for (int side = -1; side <= 1; side += 2)
                {
                    if (!road.HasWall(i, side) || !road.HasWall(j, side)) continue;
                    bool low = side < 0 ? (road.LowL[i] && road.LowL[j]) : (road.LowR[i] && road.LowR[j]);
                    WallSegment(mb, s, i, j, side, z, lift, low);
                }
            }
            if (mb.VertexCount > 0)
            {
                var go = mb.ToObject("Walls_" + road.Name, parent, Art.Toon("wall", Art.Tex("grain", () => Art.GrainTexture(64, 0.12f, 11)), 0, default(Vector2), false, 0.1f, 0.25f, 0.15f));
                Shadows(go, true, true);
            }
            if (caps.VertexCount > 0) caps.ToObject("GapCliffs_" + road.Name, parent, Art.Plain);
        }

        static void WallSegment(MeshBuilder mb, TrackSpline s, int i, int j, int side, ZoneStyle z, float lift, bool low = false)
        {
            float hi = s.HalfWidth[i], hj = s.HalfWidth[j];
            float wh = z.WallHeight;
            Vector3 upI = s.Up[i], upJ = s.Up[j];
            System.Func<int, float, float, Vector3> P = (k, lat, h) => s.PointAt(k, side * lat, h + lift);
            bool blk = ((i / 2) % 2) == 0;
            Color face = blk ? z.WallA : z.WallB;
            if (low)
            {
                // low lip (knee-high stone / log / snow ledge): looks like the rest of the wall, but a good launch clears it
                const float lh = 0.6f;
                Color f2 = face * (0.9f + Noise.Value(i * 0.7f, side * 5, 31) * 0.1f); f2.a = 1;
                Panel(mb, P(i, hi, 0), P(i, hi, lh * 0.85f), P(j, hj, lh * 0.85f), P(j, hj, 0), side, f2);
                Panel(mb, P(i, hi, lh * 0.85f), P(i, hi + 0.12f, lh), P(j, hj + 0.12f, lh), P(j, hj, lh * 0.85f), side, z.WallTop * 0.92f);
                TopCap(mb, P(i, hi + 0.12f, lh), P(j, hj + 0.12f, lh), P(j, hj + WallThick, lh), P(i, hi + WallThick, lh), side, z.WallTop);
                Panel(mb, P(i, hi + WallThick, -2f), P(i, hi + WallThick, lh), P(j, hj + WallThick, lh), P(j, hj + WallThick, -2f), -side, f2 * 0.8f);
                return;
            }
            switch (z.Wall)
            {
                case WallKind.Snowbank:
                    {
                        // rounded snow mound: 5-point arc profile
                        float[] lx = { 0f, 0.25f, 0.7f, 1.25f, 1.9f };
                        float[] ly = { 0f, 0.75f, 1.05f, 0.8f, -0.4f };
                        for (int k = 0; k < lx.Length - 1; k++)
                        {
                            Color c = Color.Lerp(z.WallA, z.WallTop, ly[k] / 1.05f) * (0.97f + Noise.Value(i * 0.5f, k + side * 3, 21) * 0.06f); c.a = 1;
                            Vector3 a0 = P(i, hi + lx[k], ly[k]), a1 = P(j, hj + lx[k], ly[k]), b0 = P(i, hi + lx[k + 1], ly[k + 1]), b1 = P(j, hj + lx[k + 1], ly[k + 1]);
                            if (side < 0) mb.AddQuad(b0, b1, a1, a0, c); else mb.AddQuad(a0, a1, b1, b0, c);
                        }
                        return;
                    }
                case WallKind.Fence:
                case WallKind.Timber:
                    {
                        // low plank wall + chunky posts + top rail
                        float ph = wh * 0.75f;
                        Panel(mb, P(i, hi, 0), P(i, hi, ph), P(j, hj, ph), P(j, hj, 0), side, face);
                        Panel(mb, P(i, hi + WallThick, 0), P(i, hi + WallThick, ph), P(j, hj + WallThick, ph), P(j, hj + WallThick, 0), -side, face * 0.8f);
                        TopCap(mb, P(i, hi, ph), P(j, hj, ph), P(j, hj + WallThick, ph), P(i, hi + WallThick, ph), side, z.WallTop);
                        if (i % 3 == 0)
                        {
                            Vector3 c = P(i, hi + WallThick * 0.5f, wh * 0.5f);
                            mb.AddRoundedBox(Matrix4x4.TRS(c, Quaternion.LookRotation(s.Fwd[i], upI), Vector3.one), new Vector3(WallThick + 0.25f, wh + 0.25f, 0.42f), 0.08f, z.WallTop * 0.85f, 1);
                        }
                        return;
                    }
                case WallKind.Rail:
                    {
                        // steel guard-rail on timber posts
                        Vector3 r0 = P(i, hi + 0.15f, 0.55f), r1 = P(j, hj + 0.15f, 0.55f), r2 = P(j, hj + 0.15f, 1.0f), r3 = P(i, hi + 0.15f, 1.0f);
                        Color steel = new Color(0.72f, 0.74f, 0.78f);
                        Panel(mb, r0, r3, r2, r1, side, steel);
                        Panel(mb, P(i, hi + 0.3f, 0.55f), P(i, hi + 0.3f, 1.0f), P(j, hj + 0.3f, 1.0f), P(j, hj + 0.3f, 0.55f), -side, steel * 0.7f);
                        Panel(mb, P(i, hi + 0.1f, 0f), P(i, hi + 0.1f, 0.5f), P(j, hj + 0.1f, 0.5f), P(j, hj + 0.1f, 0f), side, face * 0.6f);
                        if (i % 3 == 0)
                            mb.AddRoundedBox(Matrix4x4.TRS(P(i, hi + 0.45f, 0.6f), Quaternion.LookRotation(s.Fwd[i], upI), Vector3.one), new Vector3(0.3f, 1.3f, 0.3f), 0.05f, z.WallA, 1);
                        return;
                    }
                case WallKind.Bamboo:
                    {
                        Panel(mb, P(i, hi, 0), P(i, hi, wh), P(j, hj, wh), P(j, hj, 0), side, face);
                        Panel(mb, P(i, hi + WallThick, 0), P(i, hi + WallThick, wh), P(j, hj + WallThick, wh), P(j, hj + WallThick, 0), -side, face * 0.8f);
                        TopCap(mb, P(i, hi, wh), P(j, hj, wh), P(j, hj + WallThick, wh), P(i, hi + WallThick, wh), side, z.WallTop);
                        if (i % 2 == 0)
                        {
                            Vector3 b = P(i, hi + 0.12f, -0.2f);
                            mb.AddCylinder(Matrix4x4.TRS(b, Quaternion.FromToRotation(Vector3.up, upI), Vector3.one), 0.13f, 0.12f, wh + 0.55f, 6, z.WallTop * 0.9f, true, true, z.WallTop);
                            mb.AddTorus(Matrix4x4.TRS(b + upI * (wh * 0.55f), Quaternion.FromToRotation(Vector3.up, upI), Vector3.one), 0.14f, 0.035f, 6, 3, z.WallB * 0.7f);
                        }
                        return;
                    }
                case WallKind.Ice:
                case WallKind.Stone:
                default:
                    {
                        // chunky blocks with bevelled tops
                        Color f2 = face * (0.95f + Noise.Value(i * 0.7f, side * 5, 31) * 0.1f); f2.a = 1;
                        Panel(mb, P(i, hi, 0), P(i, hi, wh * 0.88f), P(j, hj, wh * 0.88f), P(j, hj, 0), side, f2);
                        Panel(mb, P(i, hi, wh * 0.88f), P(i, hi + 0.12f, wh), P(j, hj + 0.12f, wh), P(j, hj, wh * 0.88f), side, z.WallTop * 0.92f);
                        TopCap(mb, P(i, hi + 0.12f, wh), P(j, hj + 0.12f, wh), P(j, hj + WallThick, wh), P(i, hi + WallThick, wh), side, z.WallTop);
                        Panel(mb, P(i, hi + WallThick, -2f), P(i, hi + WallThick, wh), P(j, hj + WallThick, wh), P(j, hj + WallThick, -2f), -side, f2 * 0.8f);
                        return;
                    }
            }
        }

        /// <summary>Vertical panel facing the road (side=-1 left wall faces +right).</summary>
        static void Panel(MeshBuilder mb, Vector3 b0, Vector3 t0, Vector3 t1, Vector3 b1, int side, Color c)
        {
            c.a = 1;
            if (side < 0) mb.AddQuad(b0, t0, t1, b1, c); else mb.AddQuad(b1, t1, t0, b0, c);
        }

        static void TopCap(MeshBuilder mb, Vector3 inI, Vector3 inJ, Vector3 outJ, Vector3 outI, int side, Color c)
        {
            c.a = 1;
            if (side < 0) mb.AddQuad(outI, outJ, inJ, inI, c); else mb.AddQuad(inI, inJ, outJ, outI, c);
        }

        static void EndCap(MeshBuilder mb, TrackSpline s, int i, bool facesForward, ZoneStyle z)
        {
            float hw = s.HalfWidth[i] + WallThick;
            Vector3 lt = s.PointAt(i, -hw), rt = s.PointAt(i, hw);
            Vector3 lb = lt + Vector3.down * 12f, rb = rt + Vector3.down * 12f;
            if (facesForward) mb.AddQuad(rb, rt, lt, lb, z.Cliff); else mb.AddQuad(lb, lt, rt, rb, z.Cliff);
        }

        // ------------------------------------------------------------------ kickers, pads, crates, mud, start line
        static void BuildEvents(TrackInstance ti, Transform parent)
        {
            var kick = new MeshBuilder(); var pads = new MeshBuilder(); var lines = new MeshBuilder(); var mud = new MeshBuilder(); var humps = new MeshBuilder();
            foreach (var e in ti.Data.events)
            {
                Road road = null;
                foreach (var r in ti.Roads) if (r.Name == e.road) road = r;
                if (road == null) continue;
                var s = road.S;
                int idx = s.IndexOfParam(e.t);
                float lift = road.IsMain ? 0f : 0.03f;
                switch (e.type)
                {
                    case "ramp": AddKicker(kick, s, idx, e, ti.ZoneAt(road, idx), lift); break;
                    case "hump": AddHump(humps, s, idx, e, ti.ZoneAt(road, idx), lift); break;
                    case "pad": AddPad(ti, pads, s, idx, e.lane, lift); break;
                    case "mud": AddMud(mud, s, idx, e, lift); break;
                    case "crates":
                        {
                            int cnt = Mathf.Max(1, e.count);
                            float hw = s.HalfWidth[idx] * 0.8f;
                            for (int c = 0; c < cnt; c++)
                            {
                                float lat = Mathf.Lerp(-hw, hw, cnt == 1 ? 0.5f : c / (float)(cnt - 1)) * (1f - Mathf.Abs(e.lane)) + e.lane * s.HalfWidth[idx];
                                ti.CrateSpots.Add(s.PointAt(idx, lat, 1.15f + lift));
                            }
                            break;
                        }
                }
            }
            if (kick.VertexCount > 0)
            {
                var g = kick.ToObject("Kickers", parent, Art.Toon("kicker", Art.Tex("grain", () => Art.GrainTexture(64, 0.12f, 11)), 0, default(Vector2), false, 0.1f, 0.2f), Layers.Ground);
                ti.Surfaces[g.GetComponent<Collider>()] = SurfaceType.Kicker;
                Shadows(g, true, true);
            }
            if (humps.VertexCount > 0)
            {
                var hg = humps.ToObject("Humps", parent, Art.Toon("hump", Art.Tex("grain", () => Art.GrainTexture(64, 0.12f, 11)), 0, default(Vector2), false, 0.1f, 0.2f), Layers.Ground);
                ti.Surfaces[hg.GetComponent<Collider>()] = SurfaceType.Road;
                Shadows(hg, true, true);
            }
            if (pads.VertexCount > 0)
                pads.ToObject("BoostPads", parent, Art.Toon("pad", Art.Tex("chevron", Art.ChevronTexture), 0.85f, new Vector2(0, -2.4f)));
            if (mud.VertexCount > 0)
            {
                var mg = mud.ToObject("Mud", parent, Art.Toon("mud", Art.Tex("mudtex", () => Art.NoiseTexture(64, 8, 41)), 0, default(Vector2), true, 0.2f, 0.45f, 0.8f), Layers.Ground);
                ti.Surfaces[mg.GetComponent<Collider>()] = SurfaceType.Mud;
            }
            // start/finish checker line + grid slots on the main road
            {
                var s = ti.Spline;
                var chk = new MeshBuilder();
                float hw = s.HalfWidth[0] - 0.2f;
                chk.AddQuad(s.PointAt(-1, -hw, 0.03f), s.PointAt(1, -hw, 0.03f), s.PointAt(1, hw, 0.03f), s.PointAt(-1, hw, 0.03f), Color.white,
                    new Vector2(0, 0), new Vector2(0, 1), new Vector2(hw, 1), new Vector2(hw, 0));
                for (int r = 0; r < 4; r++)
                    for (int side = -1; side <= 1; side += 2)
                    {
                        int gi = s.Wrap(-7 - r * 8 - (side > 0 ? 4 : 0));
                        float lat = side * s.HalfWidth[gi] * 0.36f;
                        lines.AddQuad(s.PointAt(gi, lat - 1.7f, 0.03f), s.PointAt(gi + 1, lat - 1.7f, 0.03f), s.PointAt(gi + 1, lat + 1.7f, 0.03f), s.PointAt(gi, lat + 1.7f, 0.03f), new Color(0.95f, 0.95f, 0.95f));
                    }
                var cm = Art.Toon("checkerline", Art.Tex("checker", () => Art.CheckerTexture(8)));
                cm.SetTextureScale("_MainTex", new Vector2(0.5f, 1f));
                chk.ToObject("StartLine", parent, cm);
                lines.ToObject("GridMarks", parent, Art.Plain);
            }
        }

        static void AddMud(MeshBuilder mb, TrackSpline s, int c, TrackEventData e, float lift)
        {
            int len = Mathf.Max(3, Mathf.RoundToInt(e.len / s.Step));
            float lane = e.lane * s.HalfWidth[c];
            float hwid = e.width * 0.5f;
            Color mc = new Color(0.42f, 0.3f, 0.18f);
            for (int k = 0; k < len; k++)
            {
                int i0 = s.Wrap(c - len / 2 + k), i1 = s.Wrap(c - len / 2 + k + 1);
                float t0 = k / (float)len, t1 = (k + 1) / (float)len;
                // rounded puddle outline
                float w0 = hwid * Mathf.Sqrt(Mathf.Max(0.05f, 1f - Mathf.Pow(t0 * 2f - 1f, 2f)));
                float w1 = hwid * Mathf.Sqrt(Mathf.Max(0.05f, 1f - Mathf.Pow(t1 * 2f - 1f, 2f)));
                mb.AddQuad(s.PointAt(i0, lane - w0, lift + 0.05f), s.PointAt(i1, lane - w1, lift + 0.05f), s.PointAt(i1, lane + w1, lift + 0.05f), s.PointAt(i0, lane + w0, lift + 0.05f), mc);
            }
        }

        static void AddKicker(MeshBuilder mb, TrackSpline s, int lip, TrackEventData e, ZoneStyle z, float lift)
        {
            int len = Mathf.Max(3, Mathf.RoundToInt(e.len / s.Step));
            float hwk = s.HalfWidth[lip] * 0.8f;
            float lane = e.lane * s.HalfWidth[lip];
            bool cold = z.Decor == DecorSet.Alpine || z.Decor == DecorSet.IceCave || z.Decor == DecorSet.Lake || z.Decor == DecorSet.Village;
            Color top = cold ? new Color(0.75f, 0.9f, 1f) : new Color(0.86f, 0.58f, 0.3f);
            Color stripe = cold ? new Color(0.25f, 0.5f, 1f) : new Color(1f, 0.82f, 0.2f);
            Color side = top * 0.7f;
            for (int k = 0; k < len; k++)
            {
                int i0 = s.Wrap(lip - len + k), i1 = s.Wrap(lip - len + k + 1);
                float t0 = k / (float)len, t1 = (k + 1) / (float)len;
                // curved kicker: steepest at the lip so it actually launches the kart
                float h0 = Mathf.Max(0.05f, e.h * (1f - Mathf.Cos(t0 * Mathf.PI * 0.5f))) + lift, h1 = Mathf.Max(0.05f, e.h * (1f - Mathf.Cos(t1 * Mathf.PI * 0.5f))) + lift;
                Vector3 l0 = s.PointAt(i0, lane - hwk, h0), l1 = s.PointAt(i1, lane - hwk, h1);
                Vector3 r0 = s.PointAt(i0, lane + hwk, h0), r1 = s.PointAt(i1, lane + hwk, h1);
                Vector3 lb0 = s.PointAt(i0, lane - hwk, -0.1f), lb1 = s.PointAt(i1, lane - hwk, -0.1f);
                Vector3 rb0 = s.PointAt(i0, lane + hwk, -0.1f), rb1 = s.PointAt(i1, lane + hwk, -0.1f);
                Color c = (k % 2 == 0) ? top : top * 0.88f; c.a = 1;
                Vector3 lm0 = Vector3.Lerp(l0, r0, 0.12f), lm1 = Vector3.Lerp(l1, r1, 0.12f), rm0 = Vector3.Lerp(l0, r0, 0.88f), rm1 = Vector3.Lerp(l1, r1, 0.88f);
                mb.AddQuad(l0, l1, lm1, lm0, stripe);
                mb.AddQuad(lm0, lm1, rm1, rm0, c);
                mb.AddQuad(rm0, rm1, r1, r0, stripe);
                mb.AddQuad(lb1, l1, l0, lb0, side);
                mb.AddQuad(rb0, r0, r1, rb1, side);
            }
            Vector3 l = s.PointAt(lip, lane - hwk, e.h + lift), r = s.PointAt(lip, lane + hwk, e.h + lift);
            mb.AddQuad(s.PointAt(lip, lane + hwk, -4f), r, l, s.PointAt(lip, lane - hwk, -4f), side * 0.8f);
        }

        /// <summary>Lateral fraction of a hump's centre: lane +-1 means "the right / left half of the road".</summary>
        public static float HumpLaneFrac(TrackEventData e)
        {
            return Mathf.Abs(e.lane) >= 0.99f ? Mathf.Sign(e.lane) * 0.5f : e.lane;
        }

        /// <summary>Point on the spline at a fractional sample index (smooth geometry finer than the 1 m samples).</summary>
        static Vector3 PointAtF(TrackSpline s, float fi, float lat, float lift)
        {
            int i0 = Mathf.FloorToInt(fi);
            float f = fi - i0;
            return Vector3.Lerp(s.PointAt(i0, lat, lift), s.PointAt(i0 + 1, lat, lift), f);
        }

        /// <summary>
        /// Half-road hump: a mound on ONE side of the road (the event marks its crest). The front steepens like a
        /// kicker up to a crest at 62 % of its length, then the back rolls off - a natural launcher for anyone who
        /// takes that side, and a big-air spot for a timed lip jump. Edges taper so it never forms a side wall.
        /// </summary>
        static void AddHump(MeshBuilder mb, TrackSpline s, int crest, TrackEventData e, ZoneStyle z, float lift)
        {
            float hw = s.HalfWidth[crest];
            float centre = HumpLaneFrac(e) * hw;
            float halfW = (e.width > 0.5f ? e.width : hw) * 0.5f;
            centre = Mathf.Clamp(centre, -hw + halfW, hw - halfW);
            float L = Mathf.Max(4f, e.len), H = Mathf.Max(0.3f, e.h);
            float startI = crest - 0.62f * L / s.Step;
            int along = Mathf.Max(8, Mathf.RoundToInt(L * 2f)), across = 10;
            Color dirt = Color.Lerp(z.Road, z.Shoulder, 0.55f) * 0.95f; dirt.a = 1;
            Color top = Color.Lerp(dirt, Color.white, 0.18f); top.a = 1;
            Color crestCol = z.CurbA * 0.95f; crestCol.a = 1;
            var grid = new Vector3[(along + 1) * (across + 1)];
            var cols = new Color[grid.Length];
            for (int a = 0; a <= along; a++)
            {
                float u = a / (float)along;
                float hu = u < 0.62f ? 1f - Mathf.Cos(u / 0.62f * Mathf.PI * 0.5f) : 0.5f + 0.5f * Mathf.Cos((u - 0.62f) / 0.38f * Mathf.PI);
                float fi = startI + u * L / s.Step;
                bool crestRow = Mathf.Abs(u - 0.62f) < 0.6f / along;
                for (int c = 0; c <= across; c++)
                {
                    float v = c / (float)across * 2f - 1f;
                    float taper = 1f - Mathx.SmoothStep01(0.62f, 1f, Mathf.Abs(v));
                    float h = H * hu * taper;
                    grid[a * (across + 1) + c] = PointAtF(s, fi, centre + v * halfW, lift + 0.02f + h);
                    Color cc = crestRow && taper > 0.5f ? crestCol : Color.Lerp(dirt, top, hu * taper);
                    cc.a = 1;
                    cols[a * (across + 1) + c] = cc;
                }
            }
            for (int a = 0; a < along; a++)
                for (int c = 0; c < across; c++)
                {
                    int i00 = a * (across + 1) + c, i01 = i00 + 1, i10 = i00 + across + 1, i11 = i10 + 1;
                    mb.AddQuad(grid[i00], grid[i10], grid[i11], grid[i01], cols[i00]);
                }
        }

        static void AddPad(TrackInstance ti, MeshBuilder mb, TrackSpline s, int idx, float laneFrac, float lift)
        {
            float halfLen = 3.2f, halfW = 2.4f;
            float lane = laneFrac * s.HalfWidth[idx];
            int a = s.Wrap(idx - 3), b = s.Wrap(idx + 3);
            float y = lift + 0.045f;
            Vector3 p0 = s.PointAt(a, lane - halfW, y), p1 = s.PointAt(b, lane - halfW, y), p2 = s.PointAt(b, lane + halfW, y), p3 = s.PointAt(a, lane + halfW, y);
            mb.AddQuad(p0, p1, p2, p3, Color.white, new Vector2(0, 0), new Vector2(0, 1.5f), new Vector2(1, 1.5f), new Vector2(1, 0));
            Color fr = new Color(0.15f, 0.15f, 0.2f);
            Vector3 q0 = s.PointAt(a, lane - halfW - 0.3f, y - 0.005f), q1 = s.PointAt(b, lane - halfW - 0.3f, y - 0.005f);
            Vector3 q2 = s.PointAt(b, lane + halfW + 0.3f, y - 0.005f), q3 = s.PointAt(a, lane + halfW + 0.3f, y - 0.005f);
            mb.AddQuad(q0, q1, p1, p0, fr, Vector2.zero, Vector2.zero, Vector2.zero, Vector2.zero);
            mb.AddQuad(p3, p2, q2, q3, fr, Vector2.zero, Vector2.zero, Vector2.zero, Vector2.zero);
            ti.Pads.Add(new BoostPad { Center = s.PointAt(idx, lane, lift), Fwd = s.Fwd[idx], Right = s.Right[idx], Up = s.Up[idx], HalfLen = halfLen, HalfWidth = halfW + 0.4f });
        }

        // ------------------------------------------------------------------ tunnels (with a rock mass on top)
        static void BuildTunnels(TrackInstance ti, Road road, Transform parent, int seed)
        {
            var s = road.S; int n = s.Count;
            var mb = new MeshBuilder();
            var rocks = new MeshBuilder();
            var rng = new Rng(seed + road.Id * 13 + 5);
            const int segs = 12;
            int segCount = s.Closed ? n : n - 1;
            for (int i = 0; i < segCount; i++)
            {
                int j = s.Wrap(i + 1);
                if (!road.Tunnel[i] || !road.Tunnel[j]) continue;
                var z = ti.ZoneAt(road, i);
                float wh = z.WallHeight;
                float ri = s.HalfWidth[i] + WallThick, rj = s.HalfWidth[j] + WallThick;
                for (int k = 0; k < segs; k++)
                {
                    float a0 = Mathf.PI * (1f - k / (float)segs), a1 = Mathf.PI * (1f - (k + 1) / (float)segs);
                    Vector3 p00 = s.PointAt(i, Mathf.Cos(a0) * ri, wh + Mathf.Sin(a0) * ri * 0.62f);
                    Vector3 p01 = s.PointAt(i, Mathf.Cos(a1) * ri, wh + Mathf.Sin(a1) * ri * 0.62f);
                    Vector3 p10 = s.PointAt(j, Mathf.Cos(a0) * rj, wh + Mathf.Sin(a0) * rj * 0.62f);
                    Vector3 p11 = s.PointAt(j, Mathf.Cos(a1) * rj, wh + Mathf.Sin(a1) * rj * 0.62f);
                    float nz = Noise.Value(i * 0.35f, k * 0.9f, 77);
                    Color inner = z.Cliff * (0.55f + nz * 0.2f); inner.a = 1;
                    mb.AddQuad(p01, p11, p10, p00, inner);
                    Vector3 ci = s.PointAt(i, 0, wh), cj = s.PointAt(j, 0, wh);
                    mb.AddQuad(p00 + (p00 - ci).normalized * 1.5f, p10 + (p10 - cj).normalized * 1.5f, p11 + (p11 - cj).normalized * 1.5f, p01 + (p01 - ci).normalized * 1.5f, z.Cliff);
                }
                if (i % 9 == 0)
                {
                    mb.AddSphere(Matrix4x4.TRS(s.PointAt(i, -ri * 0.55f, wh + ri * 0.45f), Quaternion.identity, Vector3.one), 0.32f, 4, 6, new Color(1f, 0.85f, 0.45f));
                    mb.AddSphere(Matrix4x4.TRS(s.PointAt(i, ri * 0.55f, wh + ri * 0.45f), Quaternion.identity, Vector3.one), 0.32f, 4, 6, new Color(1f, 0.85f, 0.45f));
                }
                // rock mass so the tunnel reads as going through a hill / cave
                if (i % 7 == 0)
                {
                    float rr = rng.Range(7f, 11f);
                    Vector3 top = s.PointAt(i, rng.Range(-2f, 2f), wh + ri * 0.62f + rr * 0.55f + 1.5f);
                    rocks.AddNaturalRock(Matrix4x4.TRS(top, Quaternion.Euler(0, rng.Range(0, 360f), 0), new Vector3(1.4f, 0.8f, 1.2f)), rr, z.Cliff, z.TerrainMid, rng, 1, 0.25f);
                    for (int side = -1; side <= 1; side += 2)
                    {
                        float sr = rng.Range(5f, 8f);
                        Vector3 sp = s.PointAt(i, side * (ri + 1.5f + sr * 1.25f), sr * 0.4f);
                        SolidAt(ti, sp - Vector3.up * sr * 0.4f, sr * 0.95f, sr * 1.4f);
                        rocks.AddNaturalRock(Matrix4x4.TRS(sp, Quaternion.Euler(0, rng.Range(0, 360f), 0), new Vector3(1f, 1.3f, 1.1f)), sr, z.Cliff, z.TerrainMid, rng, 1, 0.25f);
                    }
                }
            }
            // portals
            for (int i = 0; i < segCount; i++)
            {
                int j = s.Wrap(i + 1);
                bool enter = !road.Tunnel[i] && road.Tunnel[j], exit = road.Tunnel[i] && !road.Tunnel[j];
                if (!enter && !exit) continue;
                int k = enter ? j : i;
                var z = ti.ZoneAt(road, k);
                float r = s.HalfWidth[k] + WallThick;
                Quaternion q = Quaternion.LookRotation(s.Fwd[k], s.Up[k]);
                for (int side = -1; side <= 1; side += 2)
                {
                    mb.AddRoundedBox(Matrix4x4.TRS(s.PointAt(k, side * (r + 1f), z.WallHeight + 2f), q, Vector3.one), new Vector3(2.4f, z.WallHeight * 2 + 4.5f, 2.4f), 0.35f, z.Cliff * 0.95f, 2);
                    SolidAt(ti, s.PointAt(k, side * (r + 1f), 0f), 1.3f, z.WallHeight * 2 + 4f);
                }
                mb.AddRoundedBox(Matrix4x4.TRS(s.PointAt(k, 0, z.WallHeight + r * 0.62f + 1.4f), q, Vector3.one), new Vector3(r * 2f + 4.8f, 2.6f, 2.6f), 0.4f, z.Cliff, 2);
            }
            if (mb.VertexCount > 0) Shadows(mb.ToObject("Tunnels_" + road.Name, parent, Art.Plain), true, true);
            if (rocks.VertexCount > 0) Shadows(rocks.ToObject("TunnelRocks_" + road.Name, parent, Art.Toon("rock", Art.Tex("tgrain", () => Art.GrainTexture(64, 0.22f, 5)), 0, default(Vector2), true, 0.15f, 0.15f)), true, true);
        }

        // ------------------------------------------------------------------ hanging curtains (hidden entrances)
        /// <summary>Vines / icicles / ropes hanging from a beam across a road: they half-hide a secret entrance but
        /// are see-through and never solid (unlike walls, which always are).</summary>
        static void BuildCurtains(TrackInstance ti, Transform parent)
        {
            var fol = new MeshBuilder(); var beams = new MeshBuilder();
            var rng = new Rng(StableHash(ti.Data.id) + 77);
            foreach (var e in ti.Data.events)
            {
                if (e.type != "curtain") continue;
                Road road = null;
                foreach (var r in ti.Roads) if (r.Name == e.road) road = r;
                if (road == null) continue;
                var s = road.S;
                int idx = s.IndexOfParam(e.t);
                var z = ti.ZoneAt(road, idx);
                float hw = e.width > 0.5f ? e.width * 0.5f : s.HalfWidth[idx];
                float top = Mathf.Max(4.5f, e.h);
                bool cold = z.Decor == DecorSet.IceCave || z.Decor == DecorSet.Lake || z.Decor == DecorSet.Alpine || z.Decor == DecorSet.Village;
                bool rope = z.Decor == DecorSet.Mine || z.Decor == DecorSet.Desert || z.Decor == DecorSet.Mesa || z.Decor == DecorSet.River;
                Color col = cold ? new Color(0.85f, 0.95f, 1f) : rope ? new Color(0.72f, 0.55f, 0.32f) : new Color(0.3f, 0.62f, 0.25f);
                Quaternion q = Quaternion.LookRotation(s.Fwd[idx], s.Up[idx]);
                // never draw a post that would stand on a road (it could not be solid there): skip such a curtain
                Vector3 postL = s.PointAt(idx, -(hw + 1.2f), 0f), postR = s.PointAt(idx, hw + 1.2f, 0f);
                if (!ClearOfRoadSurfaces(ti, postL, 0.6f, top) || !ClearOfRoadSurfaces(ti, postR, 0.6f, top))
                {
                    Debug.LogWarning("Curtain on " + e.road + " skipped: a post would stand on a road");
                    continue;
                }
                beams.AddRoundedBox(Matrix4x4.TRS(s.PointAt(idx, 0f, top + 0.3f), q, Vector3.one), new Vector3(hw * 2f + 3f, 0.6f, 0.7f), 0.2f, z.Cliff, 2, z.WallTop);
                for (int side = -1; side <= 1; side += 2)
                {
                    Vector3 post = side < 0 ? postL : postR;
                    beams.AddRoundedBox(Matrix4x4.TRS(post + s.Up[idx] * (top * 0.5f), q, Vector3.one), new Vector3(0.9f, top + 1.2f, 0.9f), 0.2f, z.Cliff * 0.9f, 2);
                    SolidAt(ti, post, 0.6f, top);
                }
                for (float x = -hw + 0.3f; x <= hw - 0.3f; x += rng.Range(0.45f, 0.8f))
                {
                    float len = rng.Range(top * 0.45f, top * 0.8f);
                    Vector3 root = s.PointAt(idx, x, top) + s.Fwd[idx] * rng.Range(-0.25f, 0.25f);
                    PropFactory.HangingStrand(fol, root, s.Right[idx], len, rng.Jitter(col, 0.06f), cold);
                }
            }
            if (fol.VertexCount > 0) fol.ToObject("Curtains", parent, Art.Foliage());
            if (beams.VertexCount > 0) Shadows(beams.ToObject("CurtainBeams", parent, Art.Plain), true, false);
        }

        // ------------------------------------------------------------------ bridge pillars
        static void BuildPillars(TrackInstance ti, Transform parent)
        {
            var mb = new MeshBuilder();
            foreach (var road in ti.Roads)
            {
                var s = road.S;
                for (int i = 0; i < s.Count; i += 9)
                {
                    if (road.Gap[i] || road.Tunnel[i]) continue;
                    Vector3 p = s.Pos[i];
                    float ground = ti.TerrainHeight(p.x, p.z);
                    if (p.y - ground < 3.5f) continue;
                    float h = p.y - 1.6f - ground + 1f;
                    var z = ti.ZoneAt(road, i);
                    for (int side = -1; side <= 1; side += 2)
                    {
                        Vector3 b = s.PointAt(i, side * s.HalfWidth[i] * 0.55f, 0);
                        if (OverOtherRoad(ti, road, i, b)) continue;
                        b.y = ground - 1f;
                        SolidAt(ti, b, 1.2f, h + 1f);
                        mb.AddLathe(Matrix4x4.TRS(b, Quaternion.identity, Vector3.one),
                            new[] { new Vector2(1.3f, 0), new Vector2(1.0f, 0.6f), new Vector2(0.85f, h * 0.5f), new Vector2(0.9f, h - 0.6f), new Vector2(1.2f, h) }, 10,
                            new[] { z.Underside, z.Underside, z.WallB, z.WallB, z.WallTop });
                    }
                }
            }
            if (mb.VertexCount > 0) Shadows(mb.ToObject("Pillars", parent, Art.Plain), true, true);
        }

        static bool OverOtherRoad(TrackInstance ti, Road self, int selfIdx, Vector3 p)
        {
            foreach (var r in ti.Roads)
            {
                var s = r.S;
                for (int k = 0; k < s.Count; k += 2)
                {
                    if (r == self)
                    {
                        int d = Mathf.Abs(k - selfIdx); if (s.Closed) d = Mathf.Min(d, s.Count - d);
                        if (d < 30) continue;
                    }
                    float dx = s.Pos[k].x - p.x, dz = s.Pos[k].z - p.z;
                    float lim = s.HalfWidth[k] + WallThick + 2.5f;
                    if (dx * dx + dz * dz < lim * lim && s.Pos[k].y < p.y - 2f) return true;
                }
            }
            return false;
        }

        // ------------------------------------------------------------------ start arch
        static void BuildStartArch(TrackInstance ti, Transform parent)
        {
            var s = ti.Spline;
            var z = ti.ZoneAt(ti.Main, 0);
            var mb = new MeshBuilder(); var banner = new MeshBuilder();
            float hw = s.HalfWidth[0] + WallThick + 1f;
            Quaternion q = Quaternion.LookRotation(s.Fwd[0], s.Up[0]);
            Color pole = new Color(0.85f, 0.22f, 0.14f);
            for (int side = -1; side <= 1; side += 2)
            {
                Vector3 b = s.PointAt(0, side * hw, -1f);
                SolidAt(ti, b, 0.8f, 11f);
                mb.AddLathe(Matrix4x4.TRS(b, q, Vector3.one), new[] { new Vector2(0.9f, 0), new Vector2(0.75f, 0.5f), new Vector2(0.55f, 1f), new Vector2(0.5f, 9.5f), new Vector2(0.75f, 10f), new Vector2(0.01f, 10.6f) }, 12,
                    new[] { z.WallB, z.WallB, pole, pole * 1.15f, new Color(1f, 0.85f, 0.2f), new Color(1f, 0.85f, 0.2f) });
                mb.AddSphere(Matrix4x4.TRS(b + s.Up[0] * 10.8f, q, Vector3.one), 0.7f, 8, 12, new Color(1f, 0.85f, 0.2f), new Color(1f, 0.6f, 0.1f));
            }
            Vector3 c = s.PointAt(0, 0, 7.6f);
            Vector3 r = s.Right[0] * hw, u = s.Up[0] * 1.4f, f = s.Fwd[0] * 0.2f;
            banner.AddQuad(c - r - u - f, c - r + u - f, c + r + u - f, c + r - u - f, Color.white, new Vector2(0, 0), new Vector2(0, 1), new Vector2(hw / 1.4f, 1), new Vector2(hw / 1.4f, 0));
            banner.AddQuad(c + r - u + f, c + r + u + f, c - r + u + f, c - r - u + f, Color.white, new Vector2(0, 0), new Vector2(0, 1), new Vector2(hw / 1.4f, 1), new Vector2(hw / 1.4f, 0));
            mb.AddRoundedBox(Matrix4x4.TRS(c + u + s.Up[0] * 0.25f, q, Vector3.one), new Vector3(hw * 2f + 0.4f, 0.5f, 0.6f), 0.2f, pole, 2);
            mb.AddRoundedBox(Matrix4x4.TRS(c - u - s.Up[0] * 0.25f, q, Vector3.one), new Vector3(hw * 2f + 0.4f, 0.5f, 0.6f), 0.2f, pole, 2);
            Shadows(mb.ToObject("StartArch", parent, Art.Plain), true, false);
            banner.ToObject("StartBanner", parent, Art.Toon("checker", Art.Tex("checker", () => Art.CheckerTexture(8)), 0.15f));
        }

        // ------------------------------------------------------------------ zone gateways (environment transitions)
        static void BuildGateways(TrackInstance ti, Transform parent)
        {
            var road = ti.Main; var s = road.S;
            var mb = new MeshBuilder();
            for (int i = 1; i < s.Count; i++)
            {
                if (road.Zone[i] == road.Zone[i - 1] || road.Tunnel[i] || road.Gap[i] || i < 40) continue;
                var z = ti.Zones[road.Zone[i]];
                float hw = s.HalfWidth[i] + WallThick + 0.8f;
                Quaternion q = Quaternion.LookRotation(Mathx.Flat(s.Fwd[i]).normalized, Vector3.up);
                float h = 8.5f;
                Color post = z.WallB, beam = z.WallTop;
                switch (z.Decor)
                {
                    case DecorSet.Temple:
                    case DecorSet.Volcano:
                        post = z.WallA; beam = z.WallB; h = 10f; break;
                    case DecorSet.Mine:
                        post = new Color(0.5f, 0.36f, 0.22f); beam = post * 0.85f; h = 9f; break;
                    case DecorSet.IceCave:
                    case DecorSet.Lake:
                    case DecorSet.Alpine:
                        post = new Color(0.78f, 0.92f, 1f); beam = Color.white; break;
                    case DecorSet.Village:
                        post = new Color(0.55f, 0.38f, 0.24f); beam = new Color(0.9f, 0.25f, 0.2f); break;
                }
                for (int side = -1; side <= 1; side += 2)
                {
                    Vector3 b = s.PointAt(i, side * hw, -0.6f);
                    SolidAt(ti, b, 0.95f, h + 1f);
                    mb.AddRoundedBox(Matrix4x4.TRS(b + Vector3.up * h * 0.5f, q, Vector3.one), new Vector3(1.6f, h + 1.2f, 1.6f), 0.25f, post, 2, post * 1.1f);
                    mb.AddRoundedBox(Matrix4x4.TRS(b + Vector3.up * (h + 0.9f), q, Vector3.one), new Vector3(2.2f, 0.7f, 2.2f), 0.2f, beam, 2);
                }
                Vector3 c = s.PointAt(i, 0, h + 0.4f);
                mb.AddRoundedBox(Matrix4x4.TRS(c, q, Vector3.one), new Vector3(hw * 2f + 3f, 1.2f, 1.3f), 0.3f, beam, 2);
                mb.AddRoundedBox(Matrix4x4.TRS(c - Vector3.up * 1.1f, q, Vector3.one), new Vector3(hw * 2f + 0.6f, 0.45f, 0.9f), 0.15f, post, 1);
                i += 30;
            }
            if (mb.VertexCount > 0) Shadows(mb.ToObject("Gateways", parent, Art.Plain), true, false);
        }

        // ------------------------------------------------------------------ corner signs
        static void BuildSigns(TrackInstance ti, Transform parent)
        {
            var mb = new MeshBuilder();
            foreach (var road in ti.Roads)
            {
                if (road.Hidden) continue;
                var s = road.S;
                for (int i = 2; i < s.Count - 2; i += 7)
                {
                    float k = s.Curv[i];
                    if (Mathf.Abs(k) < 1f / 30f || road.Gap[i] || road.Tunnel[i]) continue;
                    int side = k > 0 ? -1 : 1; // outside of the turn
                    if (!road.HasWall(i, side)) continue;
                    var z = ti.ZoneAt(road, i);
                    float lat = side * (s.HalfWidth[i] + WallThick * 0.5f);
                    Vector3 baseP = s.PointAt(i, lat, z.WallHeight);
                    Vector3 facing = -s.Right[i] * side;
                    Vector3 along = Vector3.Cross(s.Up[i], facing).normalized;
                    Vector3 up = s.Up[i];
                    float w = 1.7f, h = 1.25f;
                    Vector3 c = baseP + up * (h * 0.5f + 0.15f);
                    Vector3 a = c - along * w * 0.5f - up * h * 0.5f, b = c - along * w * 0.5f + up * h * 0.5f;
                    Vector3 cc = c + along * w * 0.5f + up * h * 0.5f, d = c + along * w * 0.5f - up * h * 0.5f;
                    bool flip = k > 0;
                    Vector2 u0 = flip ? new Vector2(1, 0) : new Vector2(0, 0), u1 = flip ? new Vector2(1, 1) : new Vector2(0, 1);
                    Vector2 u2 = flip ? new Vector2(0, 1) : new Vector2(1, 1), u3 = flip ? new Vector2(0, 0) : new Vector2(1, 0);
                    mb.AddQuad(d, cc, b, a, Color.white, u3, u2, u1, u0);
                    mb.AddQuad(a, b, cc, d, Color.white * 0.6f, Vector2.zero, Vector2.zero, Vector2.zero, Vector2.zero);
                }
            }
            if (mb.VertexCount > 0) mb.ToObject("CornerSigns", parent, Art.Toon("arrowsign", Art.Tex("arrowsign", Art.ArrowSignTexture), 0.3f));
        }

        // ------------------------------------------------------------------ minimap
        static void BuildMinimap(TrackInstance ti)
        {
            Vector2 min, max;
            ti.Minimap = MinimapFor(ti.Roads, out min, out max);
            ti.MapMin = min; ti.MapMax = max;
        }

        public static Texture2D MinimapFor(List<Road> roads, out Vector2 mapMin, out Vector2 mapMax, int res = 256)
        {
            var splines = new List<TrackSpline>();
            foreach (var r in roads) if (!r.Hidden) splines.Add(r.S);
            return MinimapFor(splines, out mapMin, out mapMax, res);
        }

        /// <summary>Renders road outlines (first = main loop, others thinner) into a texture with a red start marker.</summary>
        public static Texture2D MinimapFor(List<TrackSpline> splines, out Vector2 mapMin, out Vector2 mapMax, int res = 256)
        {
            Vector2 min = new Vector2(float.MaxValue, float.MaxValue), max = new Vector2(float.MinValue, float.MinValue);
            foreach (var s in splines)
                for (int i = 0; i < s.Count; i++)
                {
                    min = Vector2.Min(min, new Vector2(s.Pos[i].x, s.Pos[i].z));
                    max = Vector2.Max(max, new Vector2(s.Pos[i].x, s.Pos[i].z));
                }
            Vector2 size = max - min;
            float side = Mathf.Max(size.x, size.y) * 1.1f;
            Vector2 c = (min + max) * 0.5f;
            mapMin = c - Vector2.one * side * 0.5f;
            mapMax = c + Vector2.one * side * 0.5f;
            var tex = new Texture2D(res, res, TextureFormat.RGBA32, false) { wrapMode = TextureWrapMode.Clamp, filterMode = FilterMode.Bilinear };
            var px = new Color32[res * res];
            var dist = new float[res * res];
            var distB = new float[res * res];
            for (int k = 0; k < dist.Length; k++) { dist[k] = 99f; distB[k] = 99f; }
            float scale = res / 256f;
            int rr = Mathf.CeilToInt(7 * scale);
            for (int si = 0; si < splines.Count; si++)
            {
                var s = splines[si];
                var target = si == 0 ? dist : distB;
                for (int i = 0; i < s.Count; i++)
                {
                    Vector2 uv = new Vector2(Mathf.InverseLerp(mapMin.x, mapMax.x, s.Pos[i].x), Mathf.InverseLerp(mapMin.y, mapMax.y, s.Pos[i].z)) * res;
                    for (int y = (int)uv.y - rr; y <= (int)uv.y + rr; y++)
                        for (int x = (int)uv.x - rr; x <= (int)uv.x + rr; x++)
                        {
                            if (x < 0 || y < 0 || x >= res || y >= res) continue;
                            float d = Vector2.Distance(new Vector2(x + 0.5f, y + 0.5f), uv) / scale;
                            if (d < target[y * res + x]) target[y * res + x] = d;
                        }
                }
            }
            for (int k = 0; k < px.Length; k++)
            {
                float d = dist[k], db = distB[k] + 1.2f;
                float inner = 1f - Mathf.Clamp01(Mathf.Min(d - 3.2f, db - 3.2f));
                float outer = 1f - Mathf.Clamp01(Mathf.Min(d, db) - 5.4f);
                Color road = d <= db ? Color.white : new Color(1f, 0.92f, 0.55f);
                px[k] = Color.Lerp(new Color(0.08f, 0.08f, 0.12f, outer * 0.85f), road, inner);
            }
            var s0 = splines[0];
            Vector2 st = new Vector2(Mathf.InverseLerp(mapMin.x, mapMax.x, s0.Pos[0].x), Mathf.InverseLerp(mapMin.y, mapMax.y, s0.Pos[0].z)) * res;
            for (int y = (int)st.y - rr; y <= (int)st.y + rr; y++)
                for (int x = (int)st.x - rr; x <= (int)st.x + rr; x++)
                    if (x >= 0 && y >= 0 && x < res && y < res && Vector2.Distance(new Vector2(x, y), st) < 5f * scale) px[y * res + x] = new Color(1f, 0.25f, 0.2f, 1f);
            tex.SetPixels32(px);
            tex.Apply();
            return tex;
        }
    }
}
