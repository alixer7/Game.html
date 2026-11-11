using System.Collections.Generic;
using UnityEngine;

namespace TurboTribe
{
    public enum SurfaceType { Road, Offroad, Ice, Kicker, Mud }

    public class BoostPad
    {
        public Vector3 Center, Fwd, Right, Up;
        public float HalfLen, HalfWidth;
        public bool Contains(Vector3 p)
        {
            Vector3 d = p - Center;
            return Mathf.Abs(Vector3.Dot(d, Fwd)) < HalfLen && Mathf.Abs(Vector3.Dot(d, Right)) < HalfWidth && Mathf.Abs(Vector3.Dot(d, Up)) < 2.5f;
        }
    }

    /// <summary>One drivable road (main loop or branch) with per-sample flags.</summary>
    public class Road
    {
        public int Id;
        public string Name;
        public bool IsMain;
        public string Kind;
        public TrackSpline S;
        public bool[] Gap, Ice, Tunnel, WallL, WallR, CliffL, CliffR, ShoulderL, ShoulderR;
        public bool[] LowL, LowR;    // low (jumpable) walls: a good launch clears them
        public bool[] Trail;         // secret trail: drawn like sand / dirt / packed snow instead of a paved road
        public float[] MainIdx;      // where this sample sits along the main loop (lap progress)
        public float[] AiLane;       // preferred lateral fraction for CPUs (NaN = free)
        public float[] HumpLane;     // lane of a half-road hump just ahead (NaN = none) - bold CPUs aim for it
        public int[] Zone;           // index into TrackInstance.Zones
        public int FromMain = -1, ToMain = -1;
        public int StartIdx, EndIdx;   // branch samples sitting on the main-road junction anchors
        public bool Hidden;          // secret shortcut: not on the minimap, no arrow signs, CPUs rarely know it
        public bool NeedsJump;       // the branch can only be reached / crossed with a launch (gap, low wall)
        public bool DetachStart, DetachEnd;   // branch end that does not overlap the main road (reached by a jump)
        public int Count { get { return S.Count; } }
        public bool HasWall(int i, int side) { return side < 0 ? WallL[i] : WallR[i]; }
    }

    /// <summary>Vertical cylinder that karts cannot drive through (trunks, rocks, landmarks, gate posts, pillars).</summary>
    public struct Solid
    {
        public float X, Z, R, Y0, Y1;
    }

    /// <summary>Runtime data of a built track, used by karts, AI, items, obstacles and the HUD.</summary>
    public class TrackInstance : MonoBehaviour
    {
        public TrackData Data;
        public TrackTheme Theme;
        public readonly List<Road> Roads = new List<Road>();
        public readonly List<ZoneStyle> Zones = new List<ZoneStyle>();
        public readonly List<BoostPad> Pads = new List<BoostPad>();
        public readonly List<Vector3> CrateSpots = new List<Vector3>();
        public readonly List<Vector3> FruitSpots = new List<Vector3>();
        public readonly Dictionary<Collider, SurfaceType> Surfaces = new Dictionary<Collider, SurfaceType>();
        public float WaterLevel;

        // terrain height field for prop placement / water shading
        public float[,] TerrainH;
        public Vector2 TerrainMin;
        public float TerrainCell;
        public int TerrainNX, TerrainNZ;

        // minimap
        public Texture2D Minimap;
        public Vector2 MapMin, MapMax;

        // spatial hash of all road samples (road id, index)
        readonly Dictionary<long, List<int>> hash = new Dictionary<long, List<int>>();
        const float HashCell = 12f;

        public Road Main { get { return Roads[0]; } }
        public TrackSpline Spline { get { return Roads[0].S; } }
        public int MainCount { get { return Roads[0].S.Count; } }

        public SurfaceType SurfaceOf(Collider c)
        {
            SurfaceType s;
            return c != null && Surfaces.TryGetValue(c, out s) ? s : SurfaceType.Offroad;
        }

        public float WallHeightAt(Road r, int i) { return Zones.Count > 0 ? Zones[r.Zone[i]].WallHeight : 1.3f; }
        public ZoneStyle ZoneAt(Road r, int i) { return Zones[r.Zone[i]]; }

        /// <summary>Kart-bottom height above the road below which a wall on 'side' blocks (0 = no wall).
        /// Full walls are effectively unclimbable; low walls are cleared by a good launch.</summary>
        public const float LowWallBlock = 1.15f;
        public float WallBlockHeight(Road r, int i, int side)
        {
            if (!r.HasWall(i, side)) return 0f;
            if (side < 0 ? r.LowL[i] : r.LowR[i]) return LowWallBlock;
            return WallHeightAt(r, i) + 7f;
        }

        // scenery solids (spatial hash)
        public readonly List<Solid> Solids = new List<Solid>();
        readonly Dictionary<long, List<int>> solidHash = new Dictionary<long, List<int>>();
        const float SolidCell = 16f;

        public void AddSolid(Vector3 c, float radius, float height)
        {
            if (radius <= 0.05f) return;
            int id = Solids.Count;
            Solids.Add(new Solid { X = c.x, Z = c.z, R = radius, Y0 = c.y - 2f, Y1 = c.y + Mathf.Max(1f, height) });
            int x0 = Mathf.FloorToInt((c.x - radius) / SolidCell), x1 = Mathf.FloorToInt((c.x + radius) / SolidCell);
            int z0 = Mathf.FloorToInt((c.z - radius) / SolidCell), z1 = Mathf.FloorToInt((c.z + radius) / SolidCell);
            for (int x = x0; x <= x1; x++)
                for (int z = z0; z <= z1; z++)
                {
                    List<int> l;
                    long k = Key(x, z);
                    if (!solidHash.TryGetValue(k, out l)) { l = new List<int>(); solidHash[k] = l; }
                    l.Add(id);
                }
        }

        /// <summary>Deepest solid overlapping a kart of 'radius' at p: outward normal + penetration.</summary>
        public bool FindSolid(Vector3 p, float radius, out Vector3 normal, out float pen)
        {
            normal = Vector3.zero; pen = 0f;
            List<int> l;
            if (!solidHash.TryGetValue(Key(Mathf.FloorToInt(p.x / SolidCell), Mathf.FloorToInt(p.z / SolidCell)), out l)) return false;
            for (int k = 0; k < l.Count; k++)
            {
                var so = Solids[l[k]];
                if (p.y < so.Y0 || p.y > so.Y1) continue;
                float dx = p.x - so.X, dz = p.z - so.Z;
                float d2 = dx * dx + dz * dz, rr = so.R + radius;
                if (d2 >= rr * rr) continue;
                float d = Mathf.Sqrt(d2);
                float pp = rr - d;
                if (pp > pen)
                {
                    pen = pp;
                    normal = d > 1e-3f ? new Vector3(dx / d, 0f, dz / d) : Vector3.forward;
                }
            }
            return pen > 0f;
        }

        float[] nearD; int[] nearI;

        /// <summary>
        /// Walls of roads OTHER than 'current' that a kart arriving from outside them would cross (two-sided walls:
        /// a closed road can never be entered through its wall). Returns the outward normal and penetration.
        /// </summary>
        public bool FindForeignWall(Road current, Vector3 p, Vector3 prev, float radius, out Vector3 normal, out float pen)
        {
            normal = Vector3.zero; pen = 0f;
            if (nearD == null || nearD.Length != Roads.Count) { nearD = new float[Roads.Count]; nearI = new int[Roads.Count]; }
            for (int r = 0; r < Roads.Count; r++) { nearD[r] = float.MaxValue; nearI[r] = -1; }
            int cx = Mathf.FloorToInt(p.x / HashCell), cz = Mathf.FloorToInt(p.z / HashCell);
            for (int gx = cx - 2; gx <= cx + 2; gx++)
                for (int gz = cz - 2; gz <= cz + 2; gz++)
                {
                    List<int> l;
                    if (!hash.TryGetValue(Key(gx, gz), out l)) continue;
                    for (int k = 0; k < l.Count; k++)
                    {
                        int rid = l[k] / 100000;
                        Road r = Roads[rid];
                        if (r == current) continue;
                        int i = l[k] % 100000;
                        Vector3 d = r.S.Pos[i] - p;
                        if (Mathf.Abs(d.y) > 10f) continue;
                        float dd = d.x * d.x + d.z * d.z;
                        if (dd < nearD[rid]) { nearD[rid] = dd; nearI[rid] = i; }
                    }
                }
            for (int rid = 0; rid < Roads.Count; rid++)
            {
                if (nearI[rid] < 0) continue;
                Road r = Roads[rid]; var s = r.S;
                int j = s.Nearest(p, nearI[rid], 4);
                if (r.Gap[j]) continue;
                Vector3 rel = p - s.Pos[j];
                float lat = Vector3.Dot(rel, s.Right[j]);
                float h = Vector3.Dot(rel, s.Up[j]);
                float a = Mathf.Abs(lat);
                float hw = s.HalfWidth[j], outer = hw + TrackBuilder.WallThick;
                if (a < hw - radius || a > outer + radius) continue;        // not touching this road's wall band
                int side = lat < 0f ? -1 : 1;
                // a neighbouring road's wall only blocks up to its visible top (+ a margin): bridges and karts
                // flying high over it are never stopped by it
                float blk = Mathf.Min(WallBlockHeight(r, j, side), WallHeightAt(r, j) + 1.5f);
                if (blk <= 0f || h < -3f || h > blk) continue;
                // only crossings from OUTSIDE: a kart already on this road's surface is handled by its road logic
                float prevLat = Vector3.Dot(prev - s.Pos[j], s.Right[j]);
                if (Mathf.Abs(prevLat) < hw - 0.05f || (prevLat < 0f) != (lat < 0f)) continue;
                float pp = outer + radius - a;
                if (pp > pen) { pen = pp; normal = s.Right[j] * side; }
            }
            return pen > 0f;
        }

        static long Key(int x, int z) { return ((long)x << 32) ^ (uint)z; }

        public void BuildHash()
        {
            hash.Clear();
            foreach (var r in Roads)
                for (int i = 0; i < r.Count; i += 2)
                {
                    long k = Key(Mathf.FloorToInt(r.S.Pos[i].x / HashCell), Mathf.FloorToInt(r.S.Pos[i].z / HashCell));
                    List<int> l;
                    if (!hash.TryGetValue(k, out l)) { l = new List<int>(); hash[k] = l; }
                    l.Add(r.Id * 100000 + i);
                }
        }

        public bool FindRoadContaining(Vector3 p, Road exclude, out Road road, out int index)
        {
            return FindRoadContaining(p, exclude, 3.5f, out road, out index);
        }

        /// <summary>
        /// Finds a road (other than 'exclude') whose surface contains p (inside its width, from 1.5 m below to
        /// 'reach' above its surface). Used when a kart leaves its current road through an open side, a junction,
        /// or flies off a ledge towards a road below.
        /// </summary>
        public bool FindRoadContaining(Vector3 p, Road exclude, float reach, out Road road, out int index)
        {
            road = null; index = 0;
            int cx = Mathf.FloorToInt(p.x / HashCell), cz = Mathf.FloorToInt(p.z / HashCell);
            float bestH = float.MaxValue;
            for (int gx = cx - 2; gx <= cx + 2; gx++)
                for (int gz = cz - 2; gz <= cz + 2; gz++)
                {
                    List<int> l;
                    if (!hash.TryGetValue(Key(gx, gz), out l)) continue;
                    for (int k = 0; k < l.Count; k++)
                    {
                        Road r = Roads[l[k] / 100000];
                        if (r == exclude) continue;
                        int i = l[k] % 100000;
                        Vector3 d = r.S.Pos[i] - p;
                        if (d.x * d.x + d.z * d.z > 26f * 26f || d.y > 6f || d.y < -(reach + 2.5f)) continue;
                        int j = r.S.Nearest(p, i, 4);
                        if (r.Gap[j]) continue;
                        Vector3 rel = p - r.S.Pos[j];
                        float lat = Vector3.Dot(rel, r.S.Right[j]);
                        float h = Vector3.Dot(rel, r.S.Up[j]);
                        float along = Vector3.Dot(rel, r.S.Fwd[j]);
                        if (!r.S.Closed && ((j == 0 && along < -0.5f) || (j == r.Count - 1 && along > 0.5f))) continue;
                        if (Mathf.Abs(lat) <= r.S.HalfWidth[j] + 0.2f && h > -1.5f && h < reach && Mathf.Abs(h) < bestH)
                        {
                            bestH = Mathf.Abs(h); road = r; index = j;
                        }
                    }
                }
            return road != null;
        }

        public float TerrainHeight(float x, float z)
        {
            if (TerrainH == null) return 0;
            float fx = (x - TerrainMin.x) / TerrainCell, fz = (z - TerrainMin.y) / TerrainCell;
            int ix = Mathf.Clamp(Mathf.FloorToInt(fx), 0, TerrainNX - 2), iz = Mathf.Clamp(Mathf.FloorToInt(fz), 0, TerrainNZ - 2);
            float tx = Mathf.Clamp01(fx - ix), tz = Mathf.Clamp01(fz - iz);
            float a = Mathf.Lerp(TerrainH[ix, iz], TerrainH[ix + 1, iz], tx);
            float b = Mathf.Lerp(TerrainH[ix, iz + 1], TerrainH[ix + 1, iz + 1], tx);
            return Mathf.Lerp(a, b, tz);
        }

        public Vector2 MapUV(Vector3 p)
        {
            return new Vector2(Mathf.InverseLerp(MapMin.x, MapMax.x, p.x), Mathf.InverseLerp(MapMin.y, MapMax.y, p.z));
        }

        /// <summary>
        /// Safe respawn pose on the main road near main-sample 'mainIdx' (CTR style: inside a gap you are placed past the landing).
        /// </summary>
        public void RespawnPose(float mainIdx, out Vector3 pos, out Quaternion rot, out int index)
        {
            var r = Main; var s = r.S;
            int k = s.Wrap(Mathf.RoundToInt(mainIdx));
            bool wasGap = r.Gap[k] || r.Gap[s.Wrap(k + 6)];
            if (wasGap)
            {
                for (int n = 0; n < 80 && !r.Gap[s.Wrap(k)]; n++) k++;
                for (int n = 0; n < s.Count && r.Gap[s.Wrap(k)]; n++) k++;
                k += 4;
            }
            k = s.Wrap(k);
            index = k;
            pos = s.Pos[k] + s.Up[k] * 1.2f;
            rot = Quaternion.LookRotation(s.Fwd[k], s.Up[k]);
        }
    }
}
