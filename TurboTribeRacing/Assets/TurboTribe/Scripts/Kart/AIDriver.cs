using UnityEngine;

namespace TurboTribe
{
    /// <summary>
    /// CPU racer (v3): yaw-rate controller on a curvature-biased racing line, power-slides through bends
    /// (wide obtuse arcs), skill-based turbo timing inside the single slide window, timed lip jumps off crests /
    /// ramps / humps, shortcut / alternate-route decisions (only the best drivers know the hidden shortcuts and
    /// they can still blow the jump), lines up pads, ramps and humps, sidesteps obstacles. Rubber-banding is
    /// applied by the RaceManager.
    /// </summary>
    [DefaultExecutionOrder(-50)]
    public class AIDriver : MonoBehaviour
    {
        public KartController Kart;
        public float Skill = 0.6f;       // 0..1
        public static ObstacleManager Obstacles;
        /// <summary>Route override (time trial ghosts / tooling): always take this branch, or never take any.</summary>
        public string ForceBranch;
        public bool NeverBranch;
        /// <summary>Lip-jump lead time override in seconds (&lt; 0 = skill based; 9 = never press).</summary>
        public float LipLeadOverride = -1f;
        int failedBranch = -1;   // the branch we just fell off: not retried until the next lap
        float failedLap = -1f;
        float laneOffset, laneTarget, laneTimer;
        float boostAt = 0.7f;
        int lastBoostCount;
        float slideCooldown;
        float hopSteerTimer;
        int hopDir;
        float stuckTimer, reverseTimer;
        float boostMissChance;
        float fightTimer;
        bool airHop;
        Road planned;            // branch we intend to take
        int decidedFor = -1;     // branch id already decided on this approach
        float avoid;             // lateral obstacle avoidance offset (metres)
        bool lipTried;           // already pressed for the coming lip
        float lipPressAt;        // press this many seconds before the predicted takeoff
        float lipEta = -1f;      // own countdown to the predicted takeoff (smooths the predictor's 45 ms steps)
        bool likesHumps;         // bold drivers aim for the half-road humps

        void Start()
        {
            if (Kart != null) Kart.OnFall += () =>
            {
                if (Kart.Road != null && !Kart.Road.IsMain) { failedBranch = Kart.Road.Id; failedLap = Kart.Progress; }
                decidedFor = -1; planned = null;
            };
            laneTarget = Random.Range(-0.35f, 0.35f);
            likesHumps = Random.value < Skill * 0.85f;
            PickBoostPoint();
            PickLipTiming();
        }

        /// <summary>Where in the gauge to press: aimed at the centre of the current (single) window, with a
        /// skill-based spread - weak drivers often press outside it and backfire.</summary>
        void PickBoostPoint()
        {
            var k = Kart;
            float zMin = k != null ? k.ZoneMin : 0.7f, zMax = k != null ? k.ZoneMax : 0.88f;
            float centre = (zMin + zMax) * 0.5f;
            float half = (zMax - zMin) * 0.5f;
            float spread = half * Mathf.Lerp(2.1f, 0.65f, Skill);
            boostAt = Mathf.Clamp(centre + Random.Range(-spread, spread), 0.3f, 0.99f);
            boostMissChance = Mathf.Lerp(0.3f, 0.04f, Skill);
        }

        void PickLipTiming()
        {
            if (LipLeadOverride >= 0f) { lipPressAt = LipLeadOverride; return; }
            // good drivers press in the last few frames before the lip (high launch); weak ones press early or not at all
            lipPressAt = Mathf.Clamp(Mathf.Lerp(0.27f, 0.05f, Skill) + Random.Range(-0.02f, 0.06f) * (1.2f - Skill), 0.045f, 0.3f);
        }

        void Update() { Tick(Time.deltaTime); }

        public void Tick(float dt)
        {
            var k = Kart;
            if (k == null || k.Track == null) return;
            if (!k.ControlsEnabled || k.Respawning)
            {
                k.Input.Gas = false; k.Input.HopHeld = false; k.Input.Steer = 0;
                return;
            }
            var road = k.Road; var s = road.S;
            int i = k.TrackIndex;
            float spd = Mathf.Max(k.ForwardSpeed, 4f);

            laneTimer -= dt;
            if (laneTimer <= 0f) { laneTimer = Random.Range(2f, 5f); laneTarget = Random.Range(-0.4f, 0.4f); }
            laneOffset = Mathf.MoveTowards(laneOffset, laneTarget, dt * 0.3f);

            float look = 6f + spd * 0.42f;
            int lookSamples = Mathf.RoundToInt(look / s.Step);

            // ---------------------------------------------------------- route choice
            Road follow = road; int fi = i;
            if (road.IsMain) PlanBranches(k, i);
            if (road.IsMain && planned != null)
            {
                int n = s.Count;
                int dist = (planned.FromMain - i + n) % n;      // samples until the junction
                int past = (i - planned.FromMain + n) % n;      // samples since the junction
                if (planned.DetachStart && past > 25 && past < n / 2) planned = null;   // missed the jump over the wall: carry on
                else if (past <= 90 && past < n / 2)
                {
                    // the branch still overlaps / runs beside the main road: keep steering onto it
                    follow = planned;
                    fi = planned.S.Nearest(k.transform.position, Mathf.Clamp(planned.StartIdx + past, 0, planned.Count - 1), 24);
                }
                else if (dist > n / 2) { planned = null; }
                else if (dist < lookSamples + (planned.NeedsJump ? 45 : 6))     // jump shortcuts: line up early
                {
                    follow = planned;
                    fi = Mathf.Clamp(planned.StartIdx - dist, 0, planned.Count - 1);
                }
            }
            if (!road.IsMain) planned = null;
            var fs = follow.S;
            int ahead = fs.Wrap(fi + lookSamples);
            float c = fs.CurvatureAhead(fi, look * 0.4f, 16f);
            float hw = fs.HalfWidth[ahead];
            float line = Mathf.Clamp(c * 260f, -0.6f, 0.6f) + laneOffset * (1f - Mathf.Clamp01(Mathf.Abs(c) * 40f));
            float aiLane = follow.AiLane[fs.Wrap(fi + Mathf.RoundToInt(look * 0.5f / fs.Step))];
            if (!float.IsNaN(aiLane)) line = aiLane;
            float humpLane = follow.HumpLane[fs.Wrap(fi + Mathf.RoundToInt(look * 0.5f / fs.Step))];
            if (likesHumps && !float.IsNaN(humpLane) && float.IsNaN(aiLane)) line = humpLane;
            // a secret's launcher (off-centre hump) that we are NOT going for: keep off it, it throws you at a wall
            float secret = follow.SecretLane[fs.Wrap(fi + Mathf.RoundToInt(look * 0.5f / fs.Step))];
            if (!float.IsNaN(secret) && follow == road)
            {
                float away = secret >= 0f ? secret - 0.42f : secret + 0.42f;
                if (secret >= 0f ? line > away : line < away) line = away;
            }
            // keep off open edges (cliffs / shoulders) unless the line demands it
            if (follow.CliffL[ahead] || follow.ShoulderL[ahead]) line = Mathf.Max(line, -0.45f);
            if (follow.CliffR[ahead] || follow.ShoulderR[ahead]) line = Mathf.Min(line, 0.45f);
            UpdateAvoidance(k, follow, fi, lookSamples, line * (hw - 1.2f), dt);
            Vector3 target = fs.PointAt(ahead, Mathf.Clamp(line * (hw - 1.2f) + avoid, -(hw - 1.2f), hw - 1.2f));
            Vector3 to = target - k.transform.position;
            float ang = Mathx.SignedAngleOnPlane(k.Fwd, to, k.Up);

            // ---------------------------------------------------------- yaw-rate controller
            float cPath = fs.CurvatureAhead(fi, 2f + spd * 0.15f, 8f);
            float desired = cPath * spd * Mathf.Rad2Deg + ang * 2.6f;
            float speedF = Mathf.Clamp01(Mathf.Abs(spd) / 7f);
            float normalMax = k.Stats.TurnRate * speedF * Mathf.Lerp(1f, 0.5f, Mathf.Clamp01(spd / k.Stats.MaxSpeed));
            float steer;

            float peak = 0f;
            for (int g = 4; g <= 20; g += 2)
            {
                float cv = fs.CurvatureAhead(fi, g, 4f) * spd * Mathf.Rad2Deg;
                if (Mathf.Abs(cv) > Mathf.Abs(peak)) peak = cv;
            }
            bool gapAhead = false;
            for (int g = 0; g < 30; g += 3) if (follow.Gap[fs.Wrap(fi + g)]) { gapAhead = true; break; }
            slideCooldown -= dt;
            float nowRate = cPath * spd * Mathf.Rad2Deg;
            bool lipSoon = k.TakeoffIn >= 0f && k.TakeoffIn < 0.45f;
            // lining up a jump shortcut: no slide-hops (a hop pressed near a lip would load a weak launch)
            bool jumpRun = follow.NeedsJump && (!road.IsMain || follow != road);
            bool wantSlide = spd > 14f && !gapAhead && !lipSoon && !jumpRun && (Mathf.Abs(peak) > normalMax * 0.85f || Mathf.Abs(peak) > k.Stats.SlideMin * 0.9f)
                             && (Mathf.Sign(nowRate) == Mathf.Sign(peak) || Mathf.Abs(nowRate) < 12f);

            if (!k.Sliding)
            {
                steer = Mathf.Clamp(desired / Mathf.Max(normalMax, 1f), -1f, 1f);
                if (hopSteerTimer > 0f)
                {
                    hopSteerTimer -= dt;
                    steer = Mathf.Sign(steer) == hopDir ? hopDir * Mathf.Max(0.4f, Mathf.Abs(steer)) : hopDir * 0.4f;
                    k.Input.HopHeld = true;
                }
                else if (wantSlide && k.Grounded && slideCooldown <= 0f && Random.value < 0.4f + Skill * 0.6f)
                {
                    hopDir = peak > 0 ? 1 : -1;
                    hopSteerTimer = 0.34f;
                    k.Input.HopPressed = true;
                    k.Input.HopHeld = true;
                    slideCooldown = 0.3f;
                    PickBoostPoint();
                    lastBoostCount = 0;
                }
                else k.Input.HopHeld = false;
            }
            else
            {
                hopSteerTimer = 0f;
                float rate = desired * k.SlideDir;
                float rel = (rate - k.Stats.SlideMin) / Mathf.Max(k.Stats.SlideMax - k.Stats.SlideMin, 1f) * 2f - 1f;
                steer = Mathf.Clamp(rel, -1f, 1f) * k.SlideDir;
                bool keep = rate > k.Stats.SlideMin * 0.55f && !gapAhead && !jumpRun;
                if (k.SlideBoosts < 3 && k.SlideTime < 0.6f + Skill * 0.6f && rate > k.Stats.SlideMin * 0.25f && !gapAhead && !jumpRun) keep = true;
                fightTimer = rate < k.Stats.SlideMin * 0.4f ? fightTimer + dt : 0f;
                if (fightTimer > 0.18f || Mathf.Abs(ang) > 70f) keep = false;
                k.Input.HopHeld = keep;
                if (k.SlideBoosts != lastBoostCount) { lastBoostCount = k.SlideBoosts; PickBoostPoint(); }
                if (k.SlideBoosts < 3 && k.SlideGauge >= boostAt)
                {
                    if (Random.value > boostMissChance) k.Input.BoostPressed = true;
                    PickBoostPoint();
                }
            }

            // timed lip jump: press just before the road falls away (crest / kicker / hump / gap); the later, the higher.
            // The predictor reports the takeoff in coarse steps (one node = 45 ms of travel), so the CPU keeps its own
            // countdown to the predicted takeoff and presses on the frame that reaches its chosen lead time.
            if (k.Grounded && !k.LipLoaded && k.TakeoffIn >= 0f)
            {
                float eta = k.TakeoffIn;
                if (lipEta >= 0f && k.TakeoffIn < lipEta + 0.1f) eta = Mathf.Min(eta, Mathf.Max(0f, lipEta - dt));   // continuous between predictor updates
                lipEta = eta;
                bool must = follow.NeedsJump || gapAhead;          // shortcuts that need the big launch
                if (!lipTried && !k.Sliding && eta - dt * 0.5f <= lipPressAt)
                {
                    bool never = LipLeadOverride > 5f;
                    if (!never && (must || Random.value < 0.25f + Skill * 0.7f)) k.Input.HopPressed = true;
                    lipTried = true;
                }
            }
            else if (!k.Grounded) lipEta = -1f;
            else if (k.TakeoffIn < 0f)
            {
                lipEta = -1f;
                if (lipTried) { lipTried = false; PickLipTiming(); }
            }
            // hang-time trick: hop again in the air off big jumps
            if (k.Grounded) airHop = false;
            else if (!airHop && k.AirTime > 0.12f)
            {
                airHop = true;
                if (LipLeadOverride <= 5f && Random.value < 0.3f + Skill * 0.6f) k.Input.HopPressed = true;
            }

            // stuck recovery
            if (k.ForwardSpeed < 1.5f && k.Grounded && !k.Stunned) stuckTimer += dt; else stuckTimer = 0f;
            if (stuckTimer > 1.5f) { reverseTimer = 1.0f; stuckTimer = 0f; }
            if (reverseTimer > 0f)
            {
                reverseTimer -= dt;
                k.Input.Gas = false; k.Input.Brake = true; k.Input.Steer = -Mathf.Sign(ang);
                return;
            }

            // corner speed: if we can't (or won't) slide, ease off when the road demands more than normal steering
            bool gas = true, brake = false;
            if (!k.Sliding && hopSteerTimer <= 0f && k.Grounded && (gapAhead || !wantSlide || slideCooldown > 0f))
            {
                float need = Mathf.Abs(peak);
                if (need > normalMax * 1.05f) gas = false;
                if (need > normalMax * 1.45f && spd > 12f) brake = true;
            }
            if (k.Sliding && Mathf.Abs(desired) > k.Stats.SlideMax * 1.35f && spd > 16f) gas = false; // too hot even for the tightest arc
            // corner speed planner: never arrive faster than the tightest arc ahead allows (the kart's best yaw rate,
            // a little less for weaker drivers), with room to scrub the speed before it. Flicks (left -> right while
            // still turning) cost extra because the yaw has to swing through zero first.
            if (k.Grounded && !jumpRun)
            {
                float hiF = Mathf.Lerp(1f, 0.5f, Mathf.Clamp01(spd / k.Stats.MaxSpeed));
                float bestRate = Mathf.Max(k.Stats.TurnRate * hiF, k.Stats.SlideMax) * Mathf.Deg2Rad * Mathf.Lerp(0.82f, 0.95f, Skill);
                float horizon = 8f + spd * 1.25f;
                for (float g = 2f; g < horizon; g += 2f)
                {
                    float cv = fs.CurvatureAhead(fi, g, 4f);
                    float ac = Mathf.Abs(cv);
                    if (ac < 0.006f) continue;
                    float rate = bestRate;
                    if (Mathf.Abs(k.YawRate) > 20f && Mathf.Sign(cv) != Mathf.Sign(k.YawRate)) rate *= 0.88f;
                    float vmax = rate / ac;
                    float allowed = Mathf.Sqrt(vmax * vmax + 2f * 11f * Mathf.Max(0f, g - 4f));
                    if (spd > allowed + 2.5f) { gas = false; brake = spd > 12f; break; }
                    if (spd > allowed) gas = false;
                }
            }
            if (follow.NeedsJump && !k.Sliding) { gas = true; brake = false; }                       // commit to the jump
            k.Input.Steer = steer;
            k.Input.Gas = gas;
            k.Input.Brake = brake;
        }

        /// <summary>Decide once per approach whether to take an upcoming branch (shortcut / alternate route).</summary>
        void PlanBranches(KartController k, int i)
        {
            var roads = k.Track.Roads;
            int n = k.Road.Count;
            for (int r = 1; r < roads.Count; r++)
            {
                var b = roads[r];
                int dist = (b.FromMain - i + n) % n;
                if (dist > 120 || dist < 10) { if (decidedFor == b.Id && dist > 120) decidedFor = -1; continue; }
                if (decidedFor == b.Id) continue;
                decidedFor = b.Id;
                if (NeverBranch) { planned = null; continue; }
                if (!string.IsNullOrEmpty(ForceBranch)) { planned = b.Name == ForceBranch ? b : null; if (planned != null) return; continue; }
                // a shortcut we just fell off is not retried on the same lap (CTR CPUs learn too)
                if (b.Id == failedBranch && k.Progress < failedLap + k.Track.MainCount) { planned = null; continue; }
                // gap / ramp shortcuts need speed: only confident drivers commit
                bool risky = b.NeedsJump;
                float chance = b.Kind == "route" ? 0.45f : Mathf.Lerp(0.15f, 0.85f, Skill);
                if (risky) chance *= Mathf.Lerp(0.4f, 1f, Skill);
                // hidden shortcuts are secrets: only the best CPUs know them (and still have to land the jump)
                if (b.Hidden) chance = Skill < 0.75f ? 0f : Mathf.Lerp(0.3f, 0.8f, (Skill - 0.75f) / 0.25f);
                planned = Random.value < chance ? b : null;
            }
        }

        /// <summary>Shift the target sideways around obstacles that sit on (or will sweep) the planned line.</summary>
        void UpdateAvoidance(KartController k, Road road, int fi, int lookSamples, float lineLat, float dt)
        {
            float want = 0f;
            if (Obstacles != null)
            {
                var s = road.S;
                foreach (var o in Obstacles.Items)
                {
                    if (o.Road != road) continue;
                    int d = o.Index - fi;
                    if (s.Closed) { int n = s.Count; d = ((d % n) + n) % n; if (d > n / 2) d -= n; }
                    // keep clear until the hazard is well behind (otherwise the kart drifts back into it while alongside)
                    if (d < -Mathf.RoundToInt(6f / s.Step) || d > lookSamples + 25) continue;
                    float oLat = s.Lateral(o.Pos, o.Index);
                    float clear = o.Radius + (o.Solid ? 3.0f : 2.2f);
                    if (o.Type == "pusher")
                    {
                        // plan for the block's full stroke, not where it is right now
                        float side = o.Lane >= 0 ? 1f : -1f, hwo = s.HalfWidth[o.Index];
                        oLat = side * (hwo + 2f - hwo * 0.9f);
                    }
                    if (!o.Active && o.Type != "geyser") continue;
                    if (o.Type == "geyser" && o.Warn <= 0.05f && !o.Active) continue;
                    float diff = lineLat - oLat;
                    if (Mathf.Abs(diff) < clear)
                    {
                        float dir = diff >= 0f ? 1f : -1f;
                        // pass on the side with more room
                        float hw = s.HalfWidth[o.Index];
                        if (oLat + dir * clear > hw - 1.5f || oLat + dir * clear < -hw + 1.5f) dir = -dir;
                        want += dir * (clear - Mathf.Abs(diff)) * Mathf.Lerp(0.85f, 1.15f, Skill) * (o.Solid ? 1.35f : 1f);
                    }
                }
            }
            avoid = Mathf.MoveTowards(avoid, want, dt * 14f);
        }
    }
}
