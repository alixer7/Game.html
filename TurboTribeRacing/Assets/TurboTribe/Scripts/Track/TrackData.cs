using System;
using System.Collections.Generic;
using UnityEngine;

namespace TurboTribe
{
    // ------------------------------------------------------------------ JSON schema (v2)
    [Serializable] public class TrackPointData { public float x; public float y; public float z; public float w = 18f; public float bank; }

    [Serializable] public class RoadAnchor { public string road = "main"; public float t; }

    /// <summary>A road: the closed main loop, or an open branch (shortcut / alternate route) joining the main road.</summary>
    [Serializable]
    public class RoadData
    {
        public string id = "main";
        public bool closed = true;
        public List<TrackPointData> points = new List<TrackPointData>();
        public RoadAnchor from;   // branches only
        public RoadAnchor to;     // branches only
        public string kind = "shortcut"; // shortcut | route
        public bool hidden;       // secret shortcut: no minimap line, no arrow signs (CTR style - find it yourself)
        public bool detachStart;  // the branch starts BESIDE the main road (beyond a low wall / ledge): reached by a jump
        public bool detachEnd;    // the branch ends in the air above the main road (drops back onto it)
    }

    /// <summary>
    /// Parameter range on a road (in control-point units, e.g. 5.5 = halfway between CP5 and CP6).
    /// types: gap, tunnel, ice, openL, openR, open, cliffL, cliffR, cliff, lowL, lowR, low (low jumpable walls),
    /// bareL, bareR (no wall / shoulder), trail (secret path drawn like the ground)
    /// </summary>
    [Serializable] public class TrackRangeData { public string road = "main"; public string type; public float a; public float b; }

    /// <summary>
    /// Point features. types: ramp(h,len,lane), pad(lane), crates(count,lane), bump(h,len), dip(h,len),
    /// rumble(h,len,count), mud(lane,len,width),
    /// hump(lane = side -1/+1 or a lateral fraction, h, len, width = metres, 0 = half the road): a mound on ONE side of
    /// the road that launches whoever drives over it (time a lip jump on it for big air),
    /// curtain(width, h): hanging vines / icicles / ropes across a (hidden) branch entrance - see-through, not solid
    /// </summary>
    [Serializable]
    public class TrackEventData
    {
        public string road = "main";
        public string type; public float t; public float lane; public int count = 4;
        public float h = 1.5f; public float len = 8f; public float width = 6f;
    }

    /// <summary>Environment zone along the main road (branches inherit through their mapping).</summary>
    [Serializable] public class ZoneData { public float a; public float b; public string style; }

    /// <summary>Obstacles. types: pillar, crab, boulder, pendulum, geyser, penguin, pusher, totem</summary>
    [Serializable]
    public class ObstacleData
    {
        public string road = "main";
        public string type; public float t; public float lane; public float size = 1f;
        public float period = 4f; public float phase; public int count = 1; public float spread = 6f;
    }

    /// <summary>Designer-placed scenery. types: lagoon (water basin), lava (lava pool at y), volcano, pyramid,
    /// stonehead, mesa, crystal, rock. y &lt; -900 means "auto" (terrain height / road height).</summary>
    [Serializable]
    public class LandmarkData
    {
        public string type; public float x; public float z; public float r = 20f; public float y = -999f; public float yaw;
    }

    [Serializable]
    public class TrackData
    {
        public string id;
        public string name;
        public string theme;          // sky / light / water palette
        public string subtitle;
        public int difficulty = 1;
        public float waterLevel;
        public List<RoadData> roads = new List<RoadData>();
        public List<ZoneData> zones = new List<ZoneData>();
        public List<TrackRangeData> ranges = new List<TrackRangeData>();
        public List<TrackEventData> events = new List<TrackEventData>();
        public List<ObstacleData> obstacles = new List<ObstacleData>();
        public List<LandmarkData> landmarks = new List<LandmarkData>();

        public RoadData Main { get { return roads.Count > 0 ? roads[0] : null; } }

        public bool InRange(string road, string type, float param)
        {
            for (int i = 0; i < ranges.Count; i++)
            {
                var r = ranges[i];
                if (r.type != type || r.road != road) continue;
                if (r.a <= r.b) { if (param >= r.a && param <= r.b) return true; }
                else if (param >= r.a || param <= r.b) return true; // wraps past the start line
            }
            return false;
        }
    }

    public static class TrackDatabase
    {
        public static readonly string[] Ids = { "tiki_island", "dustbowl_canyon", "glacier_peak" };
        static readonly Dictionary<string, TrackData> cache = new Dictionary<string, TrackData>();

        public static TrackData Load(string id)
        {
            TrackData d;
            if (cache.TryGetValue(id, out d)) return d;
            var ta = Resources.Load<TextAsset>("TurboTribe/Tracks/" + id);
            if (ta == null) { Debug.LogError("Track not found: " + id); return null; }
            d = JsonUtility.FromJson<TrackData>(ta.text);
            cache[id] = d;
            return d;
        }
    }
}
