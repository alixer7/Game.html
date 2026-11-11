// Runs the REAL KartController + AIDriver + ObstacleManager code on a REAL generated track, headless.
// Reports per-kart lap times, wall bonks, falls, hazard hits, turbos, shortcut usage, off-road time and air time,
// and writes a CSV trace of every kart for plotting over the layout.
using System.Collections.Generic;
using System.Globalization;
using System.Reflection;
using System.Text;
using UnityEngine;

namespace TurboTribe.Headless
{
    public static class SimRunner
    {
        class Stat
        {
            public int Bonks, BigBonks, Falls, Hits, Turbos, Perfect, Fails, JumpBoosts, Launches, PerfectLaunches;
            public float OffRoad, Air, MaxAir, BranchTime, MaxSpeed, SpeedSum; public int Frames;
            public List<float> Laps = new List<float>();
            public HashSet<string> Branches = new HashSet<string>();
        }

        public static StringBuilder Log = new StringBuilder();
        public static string Run(string trackDir, string id, int laps, string skillsCsv, int seed, bool obstacles, string tracePath)
        {
            Resources.TrackDir = trackDir; Log.Clear();
            UnityEngine.Random.R = new System.Random(seed);
            GameObject.All.Clear();
            var root = new GameObject("root");
            var t0 = System.Diagnostics.Stopwatch.StartNew();
            var track = TrackBuilder.Build(TrackDatabase.Load(id), root.transform);
            long buildMs = t0.ElapsedMilliseconds;
            Physics.Build();
            var sb = new StringBuilder();
            sb.AppendLine($"{track.Data.name}: build {buildMs} ms, main {track.Main.S.Length:F0} m ({track.Main.Count} samples), roads {track.Roads.Count}, pads {track.Pads.Count}, crates {track.CrateSpots.Count}, fruit {track.FruitSpots.Count}, obstacles {track.Data.obstacles.Count}");
            foreach (var r in track.Roads)
                if (!r.IsMain) sb.AppendLine($"   branch {r.Name} ({r.Kind}): {r.S.Length:F0} m, main {r.FromMain}->{r.ToMain} (main span {((r.ToMain - r.FromMain + track.MainCount) % track.MainCount) * track.Main.S.Step:F0} m)");

            var skills = new List<float>();
            foreach (var sk in skillsCsv.Split(',')) skills.Add(float.Parse(sk, CultureInfo.InvariantCulture));
            var karts = new List<KartController>(); var ais = new List<AIDriver>(); var stats = new List<Stat>();
            var s = track.Spline;
            var classes = new[] { 0, 1, 2, 3, 4, 5, 6, 7 };
            for (int k = 0; k < skills.Count; k++)
            {
                int row = k / 2, side = k % 2 == 0 ? -1 : 1;
                int idx = s.Wrap(-7 - row * 8 - (side > 0 ? 4 : 0));
                Vector3 pos = s.PointAt(idx, side * s.HalfWidth[idx] * 0.36f, 0.2f);
                var go = new GameObject("kart" + k);
                var kc = go.AddComponent<KartController>();
                var ch = CharacterDef.All[classes[k % 8]];
                kc.Init(ch, track, pos, Quaternion.LookRotation(s.Fwd[idx], s.Up[idx]), false, ch.Name);
                var ai = go.AddComponent<AIDriver>();
                ai.Kart = kc; ai.Skill = skills[k];
                CallStart(ai);
                var st = new Stat();
                int kk = k;
                kc.OnBonk += imp => { st.Bonks++; if (imp > 0.5f) st.BigBonks++; Log.AppendLine($"bonk k{kk} imp {imp:F2} road {kc.Road.Name} idx {kc.TrackIndex} main {kc.MainIndex:F0} t {Time.time:F1}"); };
                kc.OnFall += () => { st.Falls++; Log.AppendLine($"fall k{kk} road {kc.Road.Name} idx {kc.TrackIndex} main {kc.MainIndex:F0} pos {kc.transform.position} t {Time.time:F1}"); };
                kc.OnHitTaken += () => { st.Hits++; Log.AppendLine($"hit k{kk} road {kc.Road.Name} main {kc.MainIndex:F0} t {Time.time:F1}"); };
                kc.OnSlideFail += () => st.Fails++;
                kc.OnSlideBoost += (lvl, perfect) => { st.Turbos++; if (perfect) st.Perfect++; };
                kc.OnAirBoost += (air, dur) => { st.JumpBoosts++; };
                kc.OnLaunch += q => { st.Launches++; if (q >= KartController.LipPerfect) st.PerfectLaunches++; };
                karts.Add(kc); ais.Add(ai); stats.Add(st);
            }
            ObstacleManager om = null;
            if (obstacles)
            {
                var og = new GameObject("obs");
                om = og.AddComponent<ObstacleManager>();
                om.BuildVisuals = false;
                om.Build(track, TrackBuilder.StableHash(id));
                om.Karts = karts;
                AIDriver.Obstacles = om;
            }
            else AIDriver.Obstacles = null;

            var plannedF = typeof(AIDriver).GetField("planned", BindingFlags.Instance | BindingFlags.NonPublic);
            var lastPlan = new string[karts.Count];
            var upd = typeof(KartController).GetMethod("Update", BindingFlags.Instance | BindingFlags.NonPublic);
            float dt = 1f / 60f; Time.deltaTime = dt;
            float time = 0f; int n = track.MainCount;
            var lapStart = new float[karts.Count]; var lastLap = new int[karts.Count];
            var trace = tracePath != null ? new StringBuilder("t,kart,x,y,z,road,slide,speed,ground,main\n") : null;
            int frame = 0;
            float maxTime = 75f * laps + 20f;
            while (time < maxTime)
            {
                if (time > 1f) foreach (var k in karts) k.ControlsEnabled = true;
                for (int k = 0; k < karts.Count; k++) ais[k].Tick(dt);
                for (int k = 0; k < karts.Count; k++) upd.Invoke(karts[k], null);
                for (int k = 0; k < karts.Count; k++)
                {
                    var pl = plannedF.GetValue(ais[k]) as Road; string nm = pl != null ? pl.Name : "-";
                    if (nm != lastPlan[k]) { Log.AppendLine($"plan k{k} -> {nm} at main {karts[k].MainIndex:F0} road {karts[k].Road.Name} t {time:F1}"); lastPlan[k] = nm; }
                }
                if (om != null) om.Step(dt);
                time += dt; Time.time = time; frame++;
                bool allDone = true;
                for (int k = 0; k < karts.Count; k++)
                {
                    var kc = karts[k]; var st = stats[k];
                    int lap = Mathf.FloorToInt(kc.Progress / n) + 1;
                    if (lap > lastLap[k])
                    {
                        if (lastLap[k] >= 1) st.Laps.Add(time - lapStart[k]);
                        lastLap[k] = lap; lapStart[k] = time;
                    }
                    if (st.Laps.Count < laps) allDone = false;
                    if (!kc.Grounded) { st.Air += dt; st.MaxAir = Mathf.Max(st.MaxAir, kc.AirTime); }
                    if (kc.Grounded && kc.Surface == SurfaceType.Offroad) st.OffRoad += dt;
                    if (!kc.Road.IsMain) { st.BranchTime += dt; st.Branches.Add(kc.Road.Name); }
                    st.MaxSpeed = Mathf.Max(st.MaxSpeed, kc.ForwardSpeed); st.SpeedSum += kc.ForwardSpeed; st.Frames++;
                    if (trace != null && frame % 3 == 0)
                        trace.AppendFormat(CultureInfo.InvariantCulture, "{0:F2},{1},{2:F1},{3:F1},{4:F1},{5},{6},{7:F1},{8},{9:F0}\n", time, k, kc.transform.position.x, kc.transform.position.y, kc.transform.position.z, kc.Road.Id, kc.Sliding ? 1 : 0, kc.ForwardSpeed, kc.Grounded ? 1 : 0, kc.MainIndex);
                }
                if (allDone) break;
            }
            for (int k = 0; k < karts.Count; k++)
            {
                var st = stats[k];
                var lapsTxt = new StringBuilder();
                foreach (var l in st.Laps) lapsTxt.Append(l.ToString("F1", CultureInfo.InvariantCulture)).Append(' ');
                sb.AppendLine($"  kart{k} skill {skills[k]:F2} {karts[k].Character.Class,-12} laps [{lapsTxt}] bonks {st.Bonks} (big {st.BigBonks}) falls {st.Falls} hits {st.Hits} " +
                              $"turbos {st.Turbos} (x3 {st.Perfect}, fail {st.Fails}) airTurbo {st.JumpBoosts} launches {st.Launches} (perfect {st.PerfectLaunches}) offroad {st.OffRoad:F1}s air {st.Air:F1}s (max {st.MaxAir:F2}) " +
                              $"branches {string.Join("/", st.Branches)} {st.BranchTime:F1}s avg {st.SpeedSum / Mathf.Max(1, st.Frames):F1} max {st.MaxSpeed:F1}");
            }
            sb.AppendLine($"  rays {Physics.RayCount}, sim time {time:F1}s");
            sb.Append(Log.ToString());
            if (trace != null) System.IO.File.WriteAllText(tracePath, trace.ToString());
            return sb.ToString();
        }

        static void CallStart(object o)
        {
            var m = o.GetType().GetMethod("Start", BindingFlags.Instance | BindingFlags.NonPublic | BindingFlags.Public);
            if (m != null) m.Invoke(o, null);
        }

        /// <summary>
        /// Drives every branch with the REAL kart + AI code: a skill-1 CPU forced onto the branch with different lip-jump
        /// lead times (never / early / medium / late / last moment), with and without a turbo, plus the main-road
        /// baseline. Reports success (stayed on the branch and rejoined without falling) and the time from a point
        /// 140 m before the junction to a point 60 m past the rejoin, versus the main road.
        /// </summary>
        public static string ShortcutTest(string trackDir, string id, bool obstacles)
        {
            Resources.TrackDir = trackDir; Log.Clear();
            GameObject.All.Clear();
            var root = new GameObject("root");
            var track = TrackBuilder.Build(TrackDatabase.Load(id), root.transform);
            Physics.Build();
            ObstacleManager om = null;
            if (obstacles)
            {
                var og = new GameObject("obs");
                om = og.AddComponent<ObstacleManager>();
                om.BuildVisuals = false;
                om.Build(track, TrackBuilder.StableHash(id));
                om.Karts = new List<KartController>();
                AIDriver.Obstacles = om;
            }
            else AIDriver.Obstacles = null;
            var upd = typeof(KartController).GetMethod("Update", BindingFlags.Instance | BindingFlags.NonPublic);
            var sb = new StringBuilder();
            string trace = System.Environment.GetEnvironmentVariable("TT_TRACE");
            var ms = track.Main.S; int n = ms.Count;
            float dt = 1f / 60f; Time.deltaTime = dt;
            float[] leads = { 9f, 0.28f, 0.2f, 0.14f, 0.09f, 0.05f, 0.02f };
            foreach (var b in track.Roads)
            {
                if (b.IsMain) continue;
                int startIdx = ms.Wrap(b.FromMain - 140);
                float span = (b.ToMain - b.FromMain + n) % n;
                float goal = 140 + span + 60;
                sb.AppendLine($"{b.Name}{(b.Hidden ? " (hidden)" : "")}: branch {b.S.Length:F0} m vs main {span * ms.Step:F0} m");
                for (int cls = 0; cls < 2; cls++)
                    for (int turbo = 0; turbo < 2; turbo++)
                    {
                        var line = new StringBuilder();
                        line.Append($"   {(cls == 0 ? "BAL" : "SPD")} {(turbo == 1 ? "turbo" : "plain")}: ");
                        for (int li = -1; li < leads.Length; li++)
                        {
                            int ok = 0, seeds = li < 0 ? 1 : 3; float tsum = 0f; string lastRes = "";
                            for (int seed = 0; seed < seeds; seed++)
                            {
                                UnityEngine.Random.R = new System.Random(7 + li * 31 + seed * 1009);
                                var go = new GameObject("tk");
                                var kc = go.AddComponent<KartController>();
                                KartClass want = cls == 0 ? KartClass.Balanced : KartClass.Speed;
                                var ch = CharacterDef.All[0];
                                for (int q = 0; q < CharacterDef.All.Length; q++) if (CharacterDef.All[q].Class == want) { ch = CharacterDef.All[q]; break; }
                                Vector3 pos = ms.PointAt(startIdx, (seed - 1) * 2.5f, 0.3f);
                                kc.Init(ch, track, pos, Quaternion.LookRotation(ms.Fwd[startIdx], ms.Up[startIdx]), false, "t");
                                kc.Velocity = ms.Fwd[startIdx] * kc.Stats.MaxSpeed;
                                kc.ControlsEnabled = true;
                                var ai = go.AddComponent<AIDriver>();
                                ai.Kart = kc; ai.Skill = 1f;
                                if (li < 0) { ai.NeverBranch = true; ai.LipLeadOverride = 0.05f; }
                                else { ai.ForceBranch = b.Name; ai.LipLeadOverride = leads[li]; }
                                CallStart(ai);
                                if (om != null) om.Karts = new List<KartController> { kc };
                                float p0 = kc.Progress, t = 0f; bool fell = false, used = false;
                                kc.OnFall += () => fell = true;
                                kc.OnLaunch += qq => { if (trace != null && trace == $"{b.Name}:{cls}:{turbo}:{li}:{seed}") sb.AppendLine($"      LAUNCH q {qq:F2} at t {t:F2}"); };
                                int frames = 0; bool boosted = false;
                                while (t < 30f)
                                {
                                    // "turbo": a slide turbo / reserves picked up ~60 m before the junction
                                    if (turbo == 1 && !boosted && kc.Progress - p0 >= 80f) { kc.Boost(6.5f, 2.2f); boosted = true; }
                                    ai.Tick(dt); upd.Invoke(kc, null);
                                    if (om != null) om.Step(dt);
                                    t += dt; frames++; Time.time += dt;
                                    if (kc.Road == b) used = true;
                                    if (trace != null && trace == $"{b.Name}:{cls}:{turbo}:{li}:{seed}" && frames % 2 == 0)
                                    {
                                        var rr = kc.Road.S; int ix = kc.TrackIndex;
                                        float lat = rr.Lateral(kc.transform.position, ix);
                                        sb.AppendLine(string.Format(CultureInfo.InvariantCulture, "      t {0:F2} road {1} idx {2} lat {3:F1}/{4:F1} y {5:F2} spd {6:F1} gr {7} sl {8} tko {9:F2} lip {10} air {11:F2} gap {12} steer {13:F2} hop {14}",
                                            t, kc.Road.Name, ix, lat, rr.HalfWidth[ix], kc.transform.position.y, kc.ForwardSpeed, kc.Grounded ? 1 : 0, kc.Sliding ? 1 : 0, kc.TakeoffIn, kc.LipLoaded ? 1 : 0, kc.AirTime, kc.Road.Gap[ix] ? 1 : 0, kc.Input.Steer, kc.Input.HopHeld ? 1 : 0));
                                    }
                                    if (fell) break;
                                    if (kc.Progress - p0 >= goal) break;
                                }
                                if (!fell && t < 30f && (used || li < 0)) { ok++; tsum += t; }
                                lastRes = fell ? (used ? "FALL" : "fall(main)") : t >= 30f ? "STUCK" : used ? "" : "main";
                                GameObject.All.Remove(go);
                            }
                            string cell = ok > 0 ? $"{ok}/{seeds} {(tsum / ok).ToString("F2", CultureInfo.InvariantCulture)}" : $"0/{seeds} {lastRes}";
                            line.Append(li < 0 ? $"[main {cell}] " : $"{(leads[li] > 5 ? "none" : leads[li].ToString("F2", CultureInfo.InvariantCulture))}:{cell}  ");
                        }
                        sb.AppendLine(line.ToString());
                    }
            }
            return sb.ToString();
        }
    }
}
