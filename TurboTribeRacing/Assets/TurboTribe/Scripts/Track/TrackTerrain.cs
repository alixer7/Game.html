using System.Collections.Generic;
using UnityEngine;

namespace TurboTribe
{
    public static partial class TrackBuilder
    {
        // ------------------------------------------------------------------ terrain
        static float IslandH(float x, float z, float d, float water, float roadY, int seed)
        {
            // low roads sit on beach/sea-level ground; raised roads (jungle, temple terraces) get a plateau under them
            float lift = Mathf.Clamp01((roadY - water - 3f) / 5f);
            float baseH = Mathf.Lerp(water + 0.9f, roadY - 1.4f, lift);
            float h = baseH + Noise.Fbm(x / 40f, z / 40f, 3, seed) * 2.5f;
            float hills = Mathf.Max(0, Noise.Fbm(x / 110f, z / 110f, 3, seed + 7) - 0.48f) * 46f;
            h += hills * Mathf.Clamp01((d - 14f) / 30f);
            h -= Mathf.Max(0, d - 80f) * 0.1f; // slope into the sea
            return h;
        }

        static float CanyonH(float x, float z, float d, float roadY, int seed)
        {
            float r = Noise.Ridged(x / 85f, z / 85f, 3, seed);
            float mesa = Mathf.Clamp01((Noise.Fbm(x / 140f, z / 140f, 3, seed + 5) - 0.42f) * 3f);
            float h = roadY * 0.5f + 3f + r * 10f + mesa * 22f;
            h += Mathf.Clamp01((d - 20f) / 60f) * 14f;
            float step = 3f;
            float terr = Mathf.Floor(h / step) * step;
            return Mathf.Lerp(h, terr + Mathx.SmoothStep01(0.6f, 1f, (h - terr) / step) * step, 0.7f);
        }

        static float MountainH(float x, float z, float d, float roadY, int seed)
        {
            float h = roadY * 0.65f + 2f + Noise.Fbm(x / 60f, z / 60f, 4, seed) * 10f;
            h += Mathf.Max(0, d - 18f) * 0.5f + Noise.Ridged(x / 50f, z / 50f, 3, seed + 3) * Mathf.Clamp01(d / 60f) * 34f;
            return h;
        }

        static void BuildTerrain(TrackInstance ti, Transform parent, int seed)
        {
            Vector2 min = new Vector2(float.MaxValue, float.MaxValue), max = new Vector2(float.MinValue, float.MinValue);
            foreach (var r in ti.Roads)
                for (int i = 0; i < r.Count; i++)
                {
                    min = Vector2.Min(min, new Vector2(r.S.Pos[i].x, r.S.Pos[i].z));
                    max = Vector2.Max(max, new Vector2(r.S.Pos[i].x, r.S.Pos[i].z));
                }
            float margin = 200f;
            min -= Vector2.one * margin; max += Vector2.one * margin;
            float cell = 4f;
            int nx = Mathf.CeilToInt((max.x - min.x) / cell) + 1, nz = Mathf.CeilToInt((max.y - min.y) / cell) + 1;
            ti.TerrainMin = min; ti.TerrainCell = cell; ti.TerrainNX = nx; ti.TerrainNZ = nz;
            var H = new float[nx, nz];
            var DT = new float[nx, nz]; var YN = new float[nx, nz]; var BT = new float[nx, nz]; var BH = new float[nx, nz];
            var ZN = new int[nx, nz];

            // spatial hash of samples (road, index)
            float hashCell = 10f;
            var grid = new Dictionary<long, List<int>>();
            foreach (var r in ti.Roads)
                for (int i = 0; i < r.Count; i++)
                {
                    long key = Key(Mathf.FloorToInt(r.S.Pos[i].x / hashCell), Mathf.FloorToInt(r.S.Pos[i].z / hashCell));
                    List<int> l;
                    if (!grid.TryGetValue(key, out l)) { l = new List<int>(); grid[key] = l; }
                    l.Add(r.Id * 100000 + i);
                }
            const float inner = 6.5f, blend = 10f;
            float reach = 13f + inner + blend + 2f;
            int rc = Mathf.CeilToInt(reach / hashCell);
            float floorY = ti.WaterLevel - 3.5f;
            for (int x = 0; x < nx; x++)
                for (int z = 0; z < nz; z++)
                {
                    float wx = min.x + x * cell, wz = min.y + z * cell;
                    int cx = Mathf.FloorToInt(wx / hashCell), cz = Mathf.FloorToInt(wz / hashCell);
                    float bestT = float.MaxValue, bestH = 0; float dNear = float.MaxValue; float yNear = 0; int zNear = 0;
                    for (int gx = cx - rc; gx <= cx + rc; gx++)
                        for (int gz = cz - rc; gz <= cz + rc; gz++)
                        {
                            List<int> l;
                            if (!grid.TryGetValue(Key(gx, gz), out l)) continue;
                            for (int k = 0; k < l.Count; k++)
                            {
                                var road = ti.Roads[l[k] / 100000]; int i = l[k] % 100000;
                                var s = road.S;
                                float dx = s.Pos[i].x - wx, dz = s.Pos[i].z - wz;
                                float d = Mathf.Sqrt(dx * dx + dz * dz);
                                if (d < dNear) { dNear = d; yNear = s.Pos[i].y; zNear = road.Zone[i]; }
                                float hw = s.HalfWidth[i];
                                if (d > hw + inner + blend + 4f) continue;
                                Vector3 rel = new Vector3(wx, s.Pos[i].y, wz) - s.Pos[i];
                                float lat = Vector3.Dot(rel, s.Right[i]);
                                int side = lat < 0 ? -1 : 1;
                                bool cliff = side < 0 ? road.CliffL[i] : road.CliffR[i];
                                bool shoulder = side < 0 ? road.ShoulderL[i] : road.ShoulderR[i];
                                float target;
                                float t;
                                if (road.Gap[i]) { target = floorY; t = Mathx.SmoothStep01(hw + inner, hw + inner + blend, d); }
                                else if (Mathf.Abs(lat) <= hw + 0.6f) { target = s.Pos[i].y - 0.65f; t = 0f; }
                                else if (cliff) { target = Mathf.Min(floorY, s.Pos[i].y - 14f); t = Mathx.SmoothStep01(hw + inner + 4f, hw + inner + blend + 4f, d); }
                                else if (shoulder)
                                {
                                    target = s.Pos[i].y - 0.25f - Mathf.Max(0f, Mathf.Abs(lat) - hw - ShoulderW) * 0.06f;
                                    t = Mathx.SmoothStep01(hw + inner, hw + inner + blend, d);
                                }
                                else { target = s.Pos[i].y - 0.65f; t = Mathx.SmoothStep01(hw + inner, hw + inner + blend, d); }
                                if (t < bestT - 0.001f || (Mathf.Abs(t - bestT) <= 0.001f && target < bestH)) { bestT = t; bestH = target; }
                            }
                        }
                    DT[x, z] = dNear; YN[x, z] = yNear; BT[x, z] = bestT; BH[x, z] = bestH; ZN[x, z] = zNear;
                }
            // distance beyond the search radius: chamfer distance transform (keeps terrain smooth everywhere)
            float diag = cell * 1.41421f;
            for (int pass = 0; pass < 2; pass++)
            {
                for (int z = 0; z < nz; z++)
                    for (int x = 0; x < nx; x++)
                    {
                        if (x > 0) Relax(DT, YN, ZN, x, z, x - 1, z, cell);
                        if (z > 0) Relax(DT, YN, ZN, x, z, x, z - 1, cell);
                        if (x > 0 && z > 0) Relax(DT, YN, ZN, x, z, x - 1, z - 1, diag);
                        if (x < nx - 1 && z > 0) Relax(DT, YN, ZN, x, z, x + 1, z - 1, diag);
                    }
                for (int z = nz - 1; z >= 0; z--)
                    for (int x = nx - 1; x >= 0; x--)
                    {
                        if (x < nx - 1) Relax(DT, YN, ZN, x, z, x + 1, z, cell);
                        if (z < nz - 1) Relax(DT, YN, ZN, x, z, x, z + 1, cell);
                        if (x < nx - 1 && z < nz - 1) Relax(DT, YN, ZN, x, z, x + 1, z + 1, diag);
                        if (x > 0 && z < nz - 1) Relax(DT, YN, ZN, x, z, x - 1, z + 1, diag);
                    }
            }
            // terrain character per zone, blurred so environments blend
            var NT = new float[nx, nz];
            for (int x = 0; x < nx; x++) for (int z = 0; z < nz; z++) NT[x, z] = ti.Zones[ZN[x, z]].Natural;
            Blur(NT, nx, nz, 6, 3);
            // nearest-road height jumps across Voronoi borders (e.g. a high volcano road next to the beach):
            // smooth it so far terrain never forms straight vertical walls
            var YS = new float[nx, nz];
            for (int x = 0; x < nx; x++) for (int z = 0; z < nz; z++) YS[x, z] = YN[x, z];
            Blur(YS, nx, nz, 8, 3);
            for (int x = 0; x < nx; x++)
                for (int z = 0; z < nz; z++)
                {
                    // close to a road keep its true height, far away use the smoothed field
                    float k = Mathx.SmoothStep01(10f, 45f, DT[x, z]);
                    YS[x, z] = Mathf.Lerp(YN[x, z], YS[x, z], k);
                }
            for (int x = 0; x < nx; x++)
                for (int z = 0; z < nz; z++)
                {
                    float wx = min.x + x * cell, wz = min.y + z * cell;
                    float t = NT[x, z];
                    float nat;
                    if (t <= 1f) nat = Mathf.Lerp(IslandH(wx, wz, DT[x, z], ti.WaterLevel, YS[x, z], seed), CanyonH(wx, wz, DT[x, z], YS[x, z], seed), t);
                    else nat = Mathf.Lerp(CanyonH(wx, wz, DT[x, z], YS[x, z], seed), MountainH(wx, wz, DT[x, z], YS[x, z], seed), t - 1f);
                    H[x, z] = BT[x, z] <= 1f ? Mathf.Lerp(BH[x, z], nat, BT[x, z]) : nat;
                }
            // designer basins: lagoons dip below the sea, lava pools below their lava surface (never under a road)
            foreach (var lm in ti.Data.landmarks)
            {
                if (lm.type != "lagoon" && lm.type != "lava" && lm.type != "ice") continue;
                float floor = lm.type == "lagoon" ? ti.WaterLevel - 2.6f : lm.type == "ice" ? lm.y - 0.8f : lm.y - 2.5f;
                for (int x = 0; x < nx; x++)
                    for (int z = 0; z < nz; z++)
                    {
                        float wx = min.x + x * cell, wz = min.y + z * cell;
                        float d = Mathf.Sqrt((wx - lm.x) * (wx - lm.x) + (wz - lm.z) * (wz - lm.z));
                        if (d > lm.r + 14f) continue;
                        float f = 1f - Mathx.SmoothStep01(lm.r - 4f, lm.r + 14f, d);
                        f *= Mathf.Clamp01(BT[x, z] * 4f);     // keep road embankments intact
                        H[x, z] = Mathf.Lerp(H[x, z], Mathf.Min(H[x, z], floor), f);
                    }
            }
            ti.TerrainH = H;

            // colours (blurred for soft zone transitions)
            var CR = new float[nx, nz]; var CG = new float[nx, nz]; var CB = new float[nx, nz];
            for (int z = 0; z < nz; z++)
                for (int x = 0; x < nx; x++)
                {
                    float h = H[x, z];
                    float hl = H[Mathf.Max(0, x - 1), z], hr = H[Mathf.Min(nx - 1, x + 1), z];
                    float hd = H[x, Mathf.Max(0, z - 1)], hu = H[x, Mathf.Min(nz - 1, z + 1)];
                    Vector3 nrm = new Vector3(hl - hr, 2f * cell, hd - hu).normalized;
                    Color c = TerrainColor(ti.Zones[ZN[x, z]], NT[x, z], h, 1f - nrm.y, ti.WaterLevel, min.x + x * cell, min.y + z * cell, seed);
                    CR[x, z] = c.r; CG[x, z] = c.g; CB[x, z] = c.b;
                }
            Blur(CR, nx, nz, 1, 2); Blur(CG, nx, nz, 1, 2); Blur(CB, nx, nz, 1, 2);
            var mb = new MeshBuilder();
            for (int z = 0; z < nz; z++)
                for (int x = 0; x < nx; x++)
                {
                    float h = H[x, z];
                    float hl = H[Mathf.Max(0, x - 1), z], hr = H[Mathf.Min(nx - 1, x + 1), z];
                    float hd = H[x, Mathf.Max(0, z - 1)], hu = H[x, Mathf.Min(nz - 1, z + 1)];
                    Vector3 nrm = new Vector3(hl - hr, 2f * cell, hd - hu).normalized;
                    mb.AddVertex(new Vector3(min.x + x * cell, h, min.y + z * cell), nrm, new Color(CR[x, z], CG[x, z], CB[x, z], 1f), new Vector2(x * cell / 8f, z * cell / 8f));
                }
            for (int z = 0; z < nz - 1; z++)
                for (int x = 0; x < nx - 1; x++)
                {
                    int a = z * nx + x;
                    mb.AddTriangle(a, a + nx, a + nx + 1);
                    mb.AddTriangle(a, a + nx + 1, a + 1);
                }
            var go = mb.ToObject("Terrain", parent, Art.Toon("terrain", Art.Tex("tdetail", () => Art.GrainTexture(64, 0.2f, 5)), 0, default(Vector2), true, 0.12f, 0.08f), Layers.Ground);
            ti.Surfaces[go.GetComponent<Collider>()] = SurfaceType.Offroad;
            Shadows(go, false, true);
        }

        static long Key(int x, int z) { return ((long)x << 32) ^ (uint)z; }

        static void Relax(float[,] d, float[,] y, int[,] zn, int x, int z, int nx2, int nz2, float cost)
        {
            float c = d[nx2, nz2] + cost;
            if (c < d[x, z]) { d[x, z] = c; y[x, z] = y[nx2, nz2]; zn[x, z] = zn[nx2, nz2]; }
        }

        static void Blur(float[,] a, int nx, int nz, int radius, int passes)
        {
            var tmp = new float[nx, nz];
            for (int p = 0; p < passes; p++)
            {
                for (int z = 0; z < nz; z++)
                {
                    float acc = 0; int cnt = 0;
                    for (int x = -radius; x < nx + radius; x++)
                    {
                        int add = x + radius, rem = x - radius - 1;
                        if (add < nx && add >= 0) { acc += a[add, z]; cnt++; }
                        if (rem >= 0 && rem < nx) { acc -= a[rem, z]; cnt--; }
                        if (x >= 0 && x < nx) tmp[x, z] = acc / Mathf.Max(1, cnt);
                    }
                }
                for (int x = 0; x < nx; x++)
                {
                    float acc = 0; int cnt = 0;
                    for (int z = -radius; z < nz + radius; z++)
                    {
                        int add = z + radius, rem = z - radius - 1;
                        if (add < nz && add >= 0) { acc += tmp[x, add]; cnt++; }
                        if (rem >= 0 && rem < nz) { acc -= tmp[x, rem]; cnt--; }
                        if (z >= 0 && z < nz) a[x, z] = acc / Mathf.Max(1, cnt);
                    }
                }
            }
        }

        static Color TerrainColor(ZoneStyle zs, float type, float h, float slope, float water, float x, float z, int seed)
        {
            float nz = Noise.Fbm(x / 23f, z / 23f, 2, seed + 13);
            float fine = Noise.Value(x * 0.35f, z * 0.35f, seed + 2);
            Color c;
            if (type >= 1.5f)
            {
                c = Color.Lerp(zs.TerrainLow, zs.TerrainMid, nz);
                c = Color.Lerp(c, zs.Cliff, Mathx.SmoothStep01(0.33f, 0.58f, slope + (fine - 0.5f) * 0.1f));
            }
            else if (type >= 0.5f)
            {
                float band = Mathf.Repeat(h / 3f, 1f);
                Color strata = Color.Lerp(zs.TerrainMid, zs.TerrainHigh, band > 0.5f ? 1f : 0.35f);
                c = Color.Lerp(zs.TerrainLow, strata, Mathx.SmoothStep01(0.12f, 0.35f, slope));
                c = Color.Lerp(c, zs.Cliff, Mathx.SmoothStep01(0.5f, 0.8f, slope) * 0.6f);
                c *= 0.92f + nz * 0.16f;
            }
            else
            {
                float sand = 1f - Mathx.SmoothStep01(water + 1.6f, water + 3.4f, h + (nz - 0.5f) * 1.6f);
                Color grass = Color.Lerp(zs.TerrainMid, zs.TerrainHigh, nz);
                c = Color.Lerp(grass, zs.TerrainLow, sand);
                if (h < water + 0.2f) c = Color.Lerp(c, zs.TerrainLow * 0.78f, 0.5f);
                c = Color.Lerp(c, zs.Cliff, Mathx.SmoothStep01(0.42f, 0.72f, slope));
            }
            c *= 0.95f + fine * 0.1f;
            c.a = 1f;
            return c;
        }

        // ------------------------------------------------------------------ water
        static void BuildWater(TrackInstance ti, Transform parent)
        {
            if (!ti.Theme.HasWater) return;
            var mb = new MeshBuilder();
            float cell = 14f;
            Vector2 min = ti.TerrainMin - Vector2.one * 350f;
            float sizeX = (ti.TerrainNX - 1) * ti.TerrainCell + 700f, sizeZ = (ti.TerrainNZ - 1) * ti.TerrainCell + 700f;
            int nx = Mathf.CeilToInt(sizeX / cell) + 1, nz = Mathf.CeilToInt(sizeZ / cell) + 1;
            float wl = ti.WaterLevel;
            for (int z = 0; z < nz; z++)
                for (int x = 0; x < nx; x++)
                {
                    float wx = min.x + x * cell, wz = min.y + z * cell;
                    bool inside = wx > ti.TerrainMin.x && wz > ti.TerrainMin.y &&
                                  wx < ti.TerrainMin.x + (ti.TerrainNX - 1) * ti.TerrainCell && wz < ti.TerrainMin.y + (ti.TerrainNZ - 1) * ti.TerrainCell;
                    float depth = inside ? wl - ti.TerrainHeight(wx, wz) : 12f;
                    float shallow = Mathf.Clamp01(1f - depth / 3.5f);
                    mb.AddVertex(new Vector3(wx, wl, wz), Vector3.up, new Color(shallow, 0, 0, 1), Vector2.zero);
                }
            for (int z = 0; z < nz - 1; z++)
                for (int x = 0; x < nx - 1; x++)
                {
                    int a = z * nx + x;
                    mb.AddTriangle(a, a + nx, a + nx + 1);
                    mb.AddTriangle(a, a + nx + 1, a + 1);
                }
            mb.ToObject("Water", parent, Art.Water(ti.Theme.WaterShallow, ti.Theme.WaterDeep));
        }

        // ------------------------------------------------------------------ designer landmarks + lava
        static void BuildLandmarks(TrackInstance ti, Transform parent, int seed)
        {
            var rng = new Rng(seed + 31);
            var mb = new MeshBuilder(); var fol = new MeshBuilder(); var glow = new MeshBuilder(); var lava = new MeshBuilder(); var ice = new MeshBuilder();
            foreach (var lm in ti.Data.landmarks)
            {
                float ty = ti.TerrainHeight(lm.x, lm.z);
                Vector3 p = new Vector3(lm.x, lm.y > -900f ? lm.y : ty, lm.z);
                int ri = ti.Main.S.NearestGlobal(p);
                var z = ti.ZoneAt(ti.Main, ri);
                switch (lm.type)
                {
                    case "ice":
                    case "lava":
                        {
                            // lava: glowing pool, hot core, crust towards the rim. ice: frozen lake sheet, deep blue core
                            bool isIce = lm.type == "ice";
                            var target = isIce ? ice : lava;
                            int rings = 7, seg = 36;
                            int b0 = target.VertexCount;
                            for (int r = 0; r <= rings; r++)
                            {
                                float rr = (lm.r + 10f) * r / rings;
                                float heat = 1f - r / (float)rings;
                                Color c = isIce ? Color.Lerp(new Color(0.86f, 0.95f, 1f), new Color(0.55f, 0.78f, 0.95f), Mathf.Pow(heat, 0.8f) * (0.85f + rng.Range(0f, 0.15f)))
                                                : Color.Lerp(new Color(0.55f, 0.08f, 0.02f), new Color(1f, 0.62f, 0.12f), Mathf.Pow(heat, 0.7f));
                                for (int k = 0; k < seg; k++)
                                {
                                    float a = k * Mathf.PI * 2f / seg;
                                    float wob = r == 0 ? 0f : rng.Range(-1.2f, 1.2f);
                                    target.AddVertex(new Vector3(lm.x + Mathf.Cos(a) * (rr + wob), lm.y + (isIce ? 0f : rng.Range(-0.05f, 0.05f)), lm.z + Mathf.Sin(a) * (rr + wob)), Vector3.up, c,
                                        new Vector2((lm.x + Mathf.Cos(a) * rr) * 0.05f, (lm.z + Mathf.Sin(a) * rr) * 0.05f));
                                }
                            }
                            for (int r = 0; r < rings; r++)
                                for (int k = 0; k < seg; k++)
                                {
                                    int a0 = b0 + r * seg + k, a1 = b0 + r * seg + (k + 1) % seg, c0 = a0 + seg, c1 = a1 + seg;
                                    target.AddTriangle(a0, a1, c1); target.AddTriangle(a0, c1, c0);
                                }
                            if (!isIce)
                            for (int k = 0; k < Mathf.RoundToInt(lm.r * 0.6f); k++)
                            {
                                float a = rng.Range(0f, Mathf.PI * 2f), d = rng.Range(0.2f, 0.9f) * lm.r;
                                PropFactory.Obsidian(mb, new Vector3(lm.x + Mathf.Cos(a) * d, lm.y + 0.1f, lm.z + Mathf.Sin(a) * d), rng.Range(0.6f, 1.6f), rng);
                            }
                            break;
                        }
                    case "lagoon":
                        for (int k = 0; k < Mathf.RoundToInt(lm.r * 0.5f); k++)
                        {
                            float a = rng.Range(0f, Mathf.PI * 2f), d = lm.r * rng.Range(0.85f, 1.25f);
                            Vector3 q = new Vector3(lm.x + Mathf.Cos(a) * d, 0, lm.z + Mathf.Sin(a) * d);
                            q.y = ti.TerrainHeight(q.x, q.z) - 0.05f;
                            if (q.y < ti.WaterLevel - 0.3f || !ClearOfRoads(ti, q, 0.5f)) continue;
                            if (rng.Chance(0.6f)) PropFactory.Reeds(fol, q, rng); else PropFactory.Rock(mb, q, rng.Range(0.8f, 1.8f), H("#9A9A8A"), H("#B8B48E"), rng);
                        }
                        break;
                    case "volcano": PropFactory.VolcanoCone(mb, glow, p, lm.r, ZoneStyle.Get("volcano"), rng); SolidAt(ti, p, lm.r * 0.95f, lm.r); break;
                    case "pyramid": PropFactory.Pyramid(mb, fol, p, lm.r, z, rng); SolidAt(ti, p, lm.r * 0.5f, 14f); break;
                    case "stonehead": PropFactory.StoneHead(mb, fol, p, lm.yaw, lm.r, z); SolidAt(ti, p, lm.r * 1.3f, lm.r * 3f); break;
                    case "mesa": PropFactory.Mesa(mb, p, lm.r, lm.y > -900f ? lm.y - ty : lm.r * 2f, z, rng); SolidAt(ti, p, lm.r, 40f); break;
                    case "crystal": PropFactory.IceCrystal(mb, glow, p, lm.r, rng); SolidAt(ti, p, lm.r * 0.9f, lm.r * 3f); break;
                    case "rock": PropFactory.Rock(mb, p, lm.r, z.Cliff, z.TerrainHigh, rng); SolidAt(ti, p, lm.r * 0.85f, lm.r * 1.5f); break;
                }
            }
            var mat = Art.Toon("props", Art.Tex("grain", () => Art.GrainTexture(64, 0.12f, 11)), 0, default(Vector2), false, 0.1f, 0.28f, 0.2f);
            if (mb.VertexCount > 0) Shadows(mb.ToObject("Landmarks", parent, mat), true, true);
            if (fol.VertexCount > 0) fol.ToObject("LandmarkFoliage", parent, Art.Foliage());
            if (glow.VertexCount > 0) glow.ToObject("LandmarkGlow", parent, Art.Glow);
            if (ice.VertexCount > 0)
                Shadows(ice.ToObject("FrozenLake", parent, Art.Toon("frozenlake", Art.Tex("tdetail", () => Art.GrainTexture(64, 0.2f, 5)), 0.05f, default(Vector2), true, 0.05f, 0.35f, 0.75f)), false, true);
            if (lava.VertexCount > 0)
                lava.ToObject("Lava", parent, Art.Toon("lava", Art.Tex("lavanoise", () => Art.NoiseTexture(128, 6, 77)), 0.95f, new Vector2(0.012f, 0.008f), false, 0.1f, 0f, 0.3f));
        }

        static bool InBasin(TrackInstance ti, Vector3 p, float margin)
        {
            foreach (var lm in ti.Data.landmarks)
            {
                float r = lm.type == "lagoon" || lm.type == "lava" || lm.type == "ice" ? lm.r + margin : lm.type == "volcano" ? lm.r * 1.05f : lm.type == "pyramid" || lm.type == "mesa" ? lm.r + 3f : 0f;
                if (r <= 0f) continue;
                float dx = p.x - lm.x, dz = p.z - lm.z;
                if (dx * dx + dz * dz < r * r) return true;
            }
            return false;
        }

        // ------------------------------------------------------------------ decorations
        static bool ClearOfRoads(TrackInstance ti, Vector3 p, float margin)
        {
            foreach (var r in ti.Roads)
            {
                var s = r.S;
                for (int i = 0; i < s.Count; i += 3)
                {
                    float dx = s.Pos[i].x - p.x, dz = s.Pos[i].z - p.z;
                    if (Mathf.Abs(dx) > 60f || Mathf.Abs(dz) > 60f) continue;
                    float lim = s.HalfWidth[i] + WallThick + margin + ((r.ShoulderL[i] || r.ShoulderR[i]) ? ShoulderW : 0f);
                    if (dx * dx + dz * dz < lim * lim) return false;
                }
            }
            return true;
        }

        static Color H(string hex) { Color c; ColorUtility.TryParseHtmlString(hex, out c); return c; }

        class Chunk { public MeshBuilder Solid = new MeshBuilder(); public MeshBuilder Foliage = new MeshBuilder(); public MeshBuilder Glow = new MeshBuilder(); }

        static void BuildDecorations(TrackInstance ti, Transform parent, int seed)
        {
            var rng = new Rng(seed + 7);
            var keepRng = new Rng(seed + 8);
            // scenery density by quality setting (LOW 45%, MEDIUM 75%, PRETTY 100%)
            float keep = Settings.Quality >= 2 ? 1f : Settings.Quality == 1 ? 0.75f : 0.45f;
            var chunks = new Dictionary<long, Chunk>();
            float chunkSize = 100f;
            System.Func<Vector3, Chunk> chunkOf = p =>
            {
                long key = Key(Mathf.FloorToInt(p.x / chunkSize), Mathf.FloorToInt(p.z / chunkSize));
                Chunk c;
                if (!chunks.TryGetValue(key, out c)) { c = new Chunk(); chunks[key] = c; }
                return c;
            };
            foreach (var road in ti.Roads)
            {
                var s = road.S; int n = s.Count;
                int i = 0, guard = 0;
                while (i < n && guard++ < 20000)
                {
                    var z = ti.ZoneAt(road, i);
                    i += Mathf.Max(2, Mathf.RoundToInt(rng.Range(4, 10) / z.DecorDensity));
                    if (i >= n) break;
                    if (road.Tunnel[i]) continue;
                    for (int side = -1; side <= 1; side += 2)
                    {
                        if (rng.Chance(0.22f)) continue;
                        float extra = (side < 0 ? road.ShoulderL[i] : road.ShoulderR[i]) ? ShoulderW : 0f;
                        float dist = s.HalfWidth[i] + WallThick + extra + rng.Range(4f, 24f) * (rng.Chance(0.3f) ? 2.2f : 1f);
                        Vector3 p = s.Pos[i] + Mathx.Flat(s.Right[i]).normalized * side * dist;
                        if (!ClearOfRoads(ti, p, 4.5f) || InBasin(ti, p, 3f)) continue;
                        p.y = ti.TerrainHeight(p.x, p.z) - 0.1f;
                        if (p.y < ti.WaterLevel - 0.3f && z.Decor != DecorSet.Beach) continue;
                        if (p.y < ti.WaterLevel - 1.2f) continue;
                        if (!keepRng.Chance(keep)) continue;
                        var ch = chunkOf(p);
                        float cr = PropFactory.Place(ch.Solid, ch.Foliage, ch.Glow, z, p, rng, ti.WaterLevel);
                        if (cr > 0f) SolidAt(ti, p, cr, 4f);
                    }
                    // ground cover: grass / ferns / flowers / reeds hugging the roadside
                    if (PropFactory.HasGroundCover(z.Decor))
                    {
                        int tufts = Mathf.RoundToInt(3 * z.DecorDensity * keep);
                        for (int t = 0; t < tufts; t++)
                        {
                            int side = rng.Chance(0.5f) ? -1 : 1;
                            float extra = (side < 0 ? road.ShoulderL[i] : road.ShoulderR[i]) ? ShoulderW * 0.6f : 0f;
                            float dist = s.HalfWidth[i] + WallThick + extra + rng.Range(0.6f, 16f);
                            Vector3 p = s.Pos[s.Wrap(i + rng.Range(-3, 3))] + Mathx.Flat(s.Right[i]).normalized * side * dist;
                            if (!ClearOfRoads(ti, p, 0.4f) || InBasin(ti, p, 1f)) continue;
                            p.y = ti.TerrainHeight(p.x, p.z) - 0.05f;
                            if (p.y < ti.WaterLevel + 0.2f) continue;
                            PropFactory.GroundCover(chunkOf(p).Foliage, z, p, rng);
                        }
                    }
                }
            }
            // landmarks further out
            var main = ti.Main.S;
            for (int k = 0; k < 26; k++)
            {
                int idx = rng.Range(0, main.Count);
                var z = ti.ZoneAt(ti.Main, idx);
                int side = rng.Chance(0.5f) ? 1 : -1;
                Vector3 p = main.Pos[idx] + Mathx.Flat(main.Right[idx]).normalized * side * rng.Range(50f, 110f);
                if (!ClearOfRoads(ti, p, 16f) || InBasin(ti, p, 10f)) continue;
                if (z.Decor == DecorSet.Volcano)
                {
                    var c3 = chunkOf(p); p.y = ti.TerrainHeight(p.x, p.z) - 0.5f;
                    float lr = rng.Range(4f, 7f);
                    PropFactory.LavaRock(c3.Solid, c3.Glow, p, lr, z, rng);
                    SolidAt(ti, p, lr * 0.85f, lr);
                    continue;
                }
                p.y = ti.TerrainHeight(p.x, p.z) - 0.5f;
                if (p.y < ti.WaterLevel - 2f && z.Decor != DecorSet.Beach) continue;
                var ch = chunkOf(p);
                float lmr = PropFactory.Landmark(ch.Solid, ch.Foliage, ch.Glow, z, p, rng, ti.WaterLevel);
                SolidAt(ti, p, lmr, 12f);
            }
            var mat = Art.Toon("props", Art.Tex("grain", () => Art.GrainTexture(64, 0.12f, 11)), 0, default(Vector2), false, 0.1f, 0.28f, 0.2f);
            var fol = Art.Foliage();
            int c2 = 0;
            foreach (var kv in chunks)
            {
                if (kv.Value.Solid.VertexCount > 0) Shadows(kv.Value.Solid.ToObject("Props_" + c2, parent, mat), true, true);
                if (kv.Value.Foliage.VertexCount > 0) Shadows(kv.Value.Foliage.ToObject("Foliage_" + c2, parent, fol), true, false);
                if (kv.Value.Glow.VertexCount > 0) kv.Value.Glow.ToObject("Glow_" + c2, parent, Art.Glow);
                c2++;
            }
        }

        // ------------------------------------------------------------------ fruit lines (main + branches: shortcuts pay out)
        static void BuildFruit(TrackInstance ti)
        {
            foreach (var road in ti.Roads)
            {
                var s = road.S; int n = s.Count;
                var blocked = new bool[n];
                foreach (var e in ti.Data.events)
                {
                    if (e.road != road.Name) continue;
                    if (e.type == "bump" || e.type == "dip" || e.type == "rumble") continue;
                    int idx = s.IndexOfParam(e.t);
                    for (int k = -14; k <= 14; k++) blocked[s.Wrap(idx + k)] = true;
                }
                for (int i = 0; i < n; i++) if (road.Gap[i]) for (int k = -10; k <= 10; k++) blocked[s.Wrap(i + k)] = true;
                if (road.IsMain) for (int k = -40; k <= 20; k++) blocked[s.Wrap(k)] = true; // keep the grid clear
                int pattern = 0;
                int startI = road.IsMain ? 40 : 18, stepI = road.IsMain ? 60 : 30;
                for (int i = startI; i < n - 16; i += stepI)
                {
                    bool ok = true;
                    for (int k = 0; k < 14; k++) if (blocked[s.Wrap(i + k)]) { ok = false; break; }
                    if (!ok) continue;
                    float lane = (pattern++ % 3 - 1) * 0.45f;
                    float c = s.CurvatureAhead(i, 0, 20);
                    if (Mathf.Abs(c) > 0.015f) lane = Mathf.Sign(c) * 0.5f; // reward the inside line
                    for (int k = 0; k < 5; k++)
                    {
                        int idx = s.Wrap(i + k * 3);
                        ti.FruitSpots.Add(s.PointAt(idx, lane * s.HalfWidth[idx], 1.0f + (road.IsMain ? 0f : 0.03f)));
                    }
                }
            }
        }
    }
}
