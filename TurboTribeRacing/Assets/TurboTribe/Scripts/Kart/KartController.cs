using System;
using UnityEngine;

namespace TurboTribe
{
    public struct KartInput
    {
        public float Steer;        // -1..1
        public bool Gas, Brake;
        public bool HopHeld;       // R1 equivalent (hop / power-slide)
        public bool HopPressed;    // edge
        public bool BoostPressed;  // L1 equivalent (slide turbo timing)
        public bool ItemPressed;
    }

    /// <summary>
    /// Arcade kart physics tuned after Crash Team Racing (v3):
    ///  - hop + hold to power-slide along a wide, obtuse arc; the kart body only angles ~10-20 degrees
    ///    (steer into the slide = tighter arc, counter-steer = wider arc)
    ///  - slide turbo gauge with ONE narrow window per boost (narrower for each of the 3 boosts); a miss backfires
    ///  - LIP JUMP: a ground-following predictor finds where the road falls away (crests, ramps, humps, ledges, gaps).
    ///    Pressing HOP shortly before that takeoff loads the jump and fires it at the lip - the later (closer to the
    ///    takeoff) the press, the higher the launch. Big crests also launch the kart on their own.
    ///  - AIR TURBO: every landing after real hang time gives a turbo; longer air = longer turbo
    ///  - turbo reserves stack and keep you above top speed while on the gas; fruit, pads, start turbo
    ///  - weight: yaw inertia, high lateral grip, strong ground snap, heavier falling gravity
    ///  - multi-road aware: shortcuts / alternate routes with open sides and junctions
    ///  - solid world: walls block from both sides (no tunnelling into a walled road from outside), walls of
    ///    neighbouring roads and scenery solids also block, low walls can be jumped with a good launch
    /// Custom kinematic integration (no Rigidbody) with ground ray probes and analytic walls per road.
    /// </summary>
    public class KartController : MonoBehaviour
    {
        // ---------------------------------------------------------------- setup
        public CharacterDef Character;
        public KartStats Stats;
        public TrackInstance Track;
        public bool IsPlayer;
        public string RacerName;
        public KartInput Input;
        public bool ControlsEnabled;
        public float SpeedMultiplier = 1f; // AI rubber-band / difficulty

        // ---------------------------------------------------------------- tuning
        public const float Gravity = 31f;
        const float FallGravityMul = 1.2f;   // heavier on the way down = weighty arcs
        const float HopSpeed = 4.6f;
        const float GaugeFillTime = 0.9f;
        // slide turbo: ONE window per boost, centred late in the gauge and narrower for each successive boost
        public const float ZoneCentre = 0.79f;
        static readonly float[] ZoneWidths = { 0.17f, 0.145f, 0.12f };
        const float BackfireTime = 0.35f;    // a mistimed press chokes the engine briefly
        public const float KartRadius = 0.9f;
        const float MaxReserve = 3.4f;
        const float YawAccel = 420f;         // deg/s^2 : yaw inertia (weight)
        const float SlideYawAccel = 260f;
        // lip jump (timed pre-takeoff hop) - mirrored in Tools/trackgen/jumpsim.py
        public const float LipWindow = 0.32f;   // a press up to this long before the takeoff is held until the lip
        const float LipBonusMax = 6.6f;         // extra vertical speed for a last-moment press (quality 1)
        public const float LipPerfect = 0.8f;   // quality >= this = perfect launch (pressed within ~65 ms)
        const float LipMinSep = 0.35f;          // the road must fall at least this far below the launch arc
        const float NaturalSep = 0.5f;          // big crests launch the kart on their own
        const float ProbeDt = 0.045f;           // predictor node spacing (seconds of travel)
        const int ProbeN = 8;                   // predictor horizon = ProbeN * ProbeDt
        // air turbo
        const float AirTurboMin = 0.42f;        // a plain hop (~0.28 s) never qualifies
        // world bounds
        const float OpenBound = 16f;            // how far past an open shoulder the kart may roam

        // ---------------------------------------------------------------- state
        public Vector3 Velocity;
        public Vector3 Fwd = Vector3.forward;
        public Vector3 Up = Vector3.up;
        public bool Grounded;
        public float AirTime;
        public SurfaceType Surface;
        public float ForwardSpeed { get; private set; }
        public float MaxSpeedNow { get; private set; }
        public float YawRate { get; private set; }        // deg/s actual
        public float LongAccel { get; private set; }      // m/s^2 (for suspension visuals)
        public float LatAccel { get; private set; }
        public float SlipSpeed { get; private set; }      // sideways speed (skid intensity)
        public float LandImpact { get; private set; }

        public bool Sliding { get; private set; }
        public int SlideDir { get; private set; }
        public float SlideGauge { get; private set; }
        public int SlideBoosts { get; private set; }
        public float SlideTime { get; private set; }
        public float SlideYaw;          // visual yaw offset in degrees
        public bool Backfiring { get { return backfireTimer > 0f; } }
        public bool LastFailLate { get; private set; }   // last slide miss was an overheat (too late) rather than too soon
        /// <summary>Turbo window of the NEXT slide boost (gauge units 0..1).</summary>
        public float ZoneMin { get { return ZoneCentre - ZoneWidths[Mathf.Clamp(SlideBoosts, 0, 2)] * 0.5f; } }
        public float ZoneMax { get { return ZoneCentre + ZoneWidths[Mathf.Clamp(SlideBoosts, 0, 2)] * 0.5f; } }
        public bool InTurboZone { get { return Sliding && SlideBoosts < 3 && backfireTimer <= 0f && SlideGauge >= ZoneMin && SlideGauge <= ZoneMax; } }

        // lip jump / air
        public float TakeoffIn { get; private set; }     // predicted seconds until the road falls away (-1 = none ahead)
        public float TakeoffDrop { get; private set; }   // how far the road falls below the launch arc (m)
        public bool LipLoaded { get; private set; }      // hop pressed, waiting for the lip
        public float LastLaunchQuality { get; private set; }
        public float LastAirTime { get; private set; }
        float lipTimer;
        float backfireTimer;

        public float BoostTimer;        // reserves (seconds)
        public float BoostBonus;        // m/s above max while boosting
        public int Fruit;
        public float StunTimer;
        public float ShieldTimer;
        public float StarTimer;
        public float InvulnTimer;
        public bool Respawning;
        float respawnTimer;
        float noSnapTimer;
        bool hopInAir;
        float bonkCooldown;
        float steerSmoothed;
        float prevFwdSpeed;
        int outsideSide;                // 0 = within the current road's walls, -1/+1 = legitimately outside that side
        int respawnMain = -1;           // main sample to respawn at (falls from a branch go back before its junction)
        readonly float[] probeY = new float[ProbeN + 3];

        // road + race progress
        public Road Road;
        public int TrackIndex;          // index on the current road
        public float Progress;          // main-loop samples travelled from the start line (negative on the grid)
        public int Lap;
        public bool Finished;
        public float FinishTime;
        public int Place = 1;
        public float WrongWayTimer;
        public bool OffRoad;            // outside the current road's width (shoulder / terrain)

        // ---------------------------------------------------------------- events
        public event Action OnHop;
        public event Action<float> OnLand;
        public event Action<int, bool> OnSlideBoost;   // level, perfect (= the 3rd, hardest window)
        public event Action OnSlideFail;
        public event Action<float> OnLaunch;           // timed lip jump fired: quality 0..1
        public event Action<float, float> OnAirBoost;  // landed after hang time: air seconds, turbo seconds
        public event Action OnBoost;
        public event Action<float> OnBonk;
        public event Action OnHitTaken;
        public event Action OnShieldPop;
        public event Action OnFall;
        public event Action OnRespawned;

        public bool Stunned { get { return StunTimer > 0f; } }
        public bool Boosting { get { return BoostTimer > 0f; } }
        public bool Invincible { get { return StarTimer > 0f || InvulnTimer > 0f; } }
        public float MainIndex { get { return Road != null ? Road.MainIdx[TrackIndex] : 0f; } }

        public void Init(CharacterDef ch, TrackInstance track, Vector3 pos, Quaternion rot, bool player, string name)
        {
            Character = ch; Stats = ch.Stats; Track = track; IsPlayer = player; RacerName = name;
            transform.SetPositionAndRotation(pos, rot);
            Fwd = rot * Vector3.forward; Up = rot * Vector3.up;
            Velocity = Vector3.zero;
            Road = track.Main;
            TrackIndex = Road.S.NearestGlobal(pos);
            int n = Road.Count;
            Progress = TrackIndex > n / 2 ? TrackIndex - n : TrackIndex;
            Lap = 0;
            TakeoffIn = -1f;
            outsideSide = 0;
            gameObject.layer = Layers.Kart;
        }

        // ---------------------------------------------------------------- public API
        /// <summary>Adds turbo reserves. Bonus is the extra speed above max; reserves stack (capped).</summary>
        public void Boost(float bonus, float duration)
        {
            if (BoostTimer <= 0f) BoostBonus = bonus;
            else BoostBonus = Mathf.Max(BoostBonus, bonus);
            BoostTimer = Mathf.Min(BoostTimer + duration, MaxReserve);
            float spd = Vector3.Dot(Velocity, Fwd);
            float kick = MaxSpeedNow + bonus * 0.55f;
            if (spd < kick) Velocity += Fwd * (kick - spd) * (Grounded ? 0.65f : 0.25f);
            if (OnBoost != null) OnBoost();
        }

        public void AddFruit(int n) { Fruit = Mathf.Clamp(Fruit + n, 0, 10); }

        public void NotifyBonk(float impact)
        {
            if (bonkCooldown > 0f) return;
            bonkCooldown = 0.35f;
            if (impact > 0.5f) { BoostTimer = 0f; EndSlide(); }
            if (OnBonk != null) OnBonk(impact);
        }

        /// <summary>Hit by a weapon / trap / hazard. Returns true if it actually affected the kart.</summary>
        public bool Hit(bool big = true)
        {
            if (Invincible || Respawning) return false;
            if (ShieldTimer > 0f)
            {
                ShieldTimer = 0f;
                InvulnTimer = 0.5f;
                if (OnShieldPop != null) OnShieldPop();
                return false;
            }
            StunTimer = big ? 1.35f : 0.9f;
            InvulnTimer = StunTimer + 0.6f;
            EndSlide();
            LipLoaded = false;
            BoostTimer = 0f;
            Vector3 planar = Vector3.ProjectOnPlane(Velocity, Up);
            Velocity = planar * 0.2f + Vector3.up * (big ? 8.5f : 5f);
            Grounded = false; noSnapTimer = 0.15f;
            AddFruit(-3);
            if (OnHitTaken != null) OnHitTaken();
            return true;
        }

        public void ForceRespawn()
        {
            if (Respawning) return;
            Respawning = true;
            respawnTimer = 1.1f;
            EndSlide();
            LipLoaded = false;
            BoostTimer = 0;
            // a failed shortcut (fell off a branch) puts you back on the main road BEFORE its junction, like CTR
            respawnMain = (Road != null && !Road.IsMain && Road.FromMain >= 0) ? Track.Main.S.Wrap(Road.FromMain - 10) : -1;
            if (OnFall != null) OnFall();
        }

        // ---------------------------------------------------------------- loop
        void Update()
        {
            float dt = Mathf.Min(Time.deltaTime, 1f / 20f);
            if (dt <= 0f) return;
            int steps = Mathf.CeilToInt(dt / (1f / 90f));
            float h = dt / steps;
            for (int i = 0; i < steps; i++) Step(h, i == 0);
            transform.SetPositionAndRotation(transform.position, Quaternion.LookRotation(Fwd, Up));
            // consume edge-triggered inputs once per frame
            Input.HopPressed = false; Input.BoostPressed = false; Input.ItemPressed = false;
        }

        void Step(float dt, bool firstStep)
        {
            if (Respawning) { UpdateRespawn(dt); return; }

            if (StunTimer > 0) StunTimer -= dt;
            if (ShieldTimer > 0) ShieldTimer -= dt;
            if (StarTimer > 0) StarTimer -= dt;
            if (InvulnTimer > 0) InvulnTimer -= dt;
            if (noSnapTimer > 0) noSnapTimer -= dt;
            if (bonkCooldown > 0) bonkCooldown -= dt;

            bool canControl = ControlsEnabled && !Stunned;
            KartInput inp = canControl ? Input : default(KartInput);
            if (Finished && !IsPlayer) inp.Gas = true;
            if (!firstStep) { inp.HopPressed = false; inp.BoostPressed = false; }
            steerSmoothed = Mathf.MoveTowards(steerSmoothed, inp.Steer, dt * 7f);

            Vector3 pos = transform.position;

            // ------------------------------------------------ ground probe
            RaycastHit hit;
            bool hitGround = ProbeGround(pos, out hit);
            Vector3 groundN = Vector3.up;
            float gap = 999f;
            if (hitGround)
            {
                groundN = SampleNormal(pos, hit.normal);
                gap = Vector3.Dot(pos - hit.point, groundN);
            }
            float vAlong = Vector3.Dot(Velocity, groundN);
            bool wasGrounded = Grounded;
            // snap grows a little with speed: the heavy kart hugs crests, only real lips / big bumps launch it
            float spdAbs = Mathf.Abs(ForwardSpeed);
            float snap = wasGrounded ? 0.42f + spdAbs * 0.006f : 0.12f;
            Grounded = hitGround && noSnapTimer <= 0f && gap <= snap && gap > -1.0f && (wasGrounded || vAlong <= 0.5f);
            if (Grounded && groundN.y < 0.35f) Grounded = false;

            if (Grounded)
            {
                Surface = Track.SurfaceOf(hit.collider);
                pos = hit.point;
                if (!wasGrounded) LandImpact = Mathf.Max(0f, -vAlong);
                Velocity = Vector3.ProjectOnPlane(Velocity, groundN);
                Up = Vector3.Slerp(Up, groundN, Mathx.Damp(16f, dt));
                if (!wasGrounded) Land();
                AirTime = 0f;
            }
            else
            {
                if (wasGrounded && inp.HopHeld) hopInAir = true; // held hop off a ramp lip
                // left a lip (kicker edge, ledge) while a timed jump was loaded: fire it now
                if (wasGrounded && LipLoaded) LipLaunch(Mathf.Clamp01(1f - lipTimer / LipWindow));
                AirTime += dt;
                Up = Vector3.Slerp(Up, Vector3.up, Mathx.Damp(2.5f, dt));
                if (inp.HopPressed && AirTime > 0.05f) hopInAir = true;
            }
            Fwd = Vector3.ProjectOnPlane(Fwd, Up).normalized;
            if (Fwd.sqrMagnitude < 0.5f) Fwd = Vector3.ProjectOnPlane(transform.forward, Up).normalized;

            float spd = Vector3.Dot(Velocity, Fwd);
            ForwardSpeed = spd;

            // ------------------------------------------------ takeoff prediction (once per frame; decays between sub-steps)
            if (firstStep) PredictTakeoff(pos, spd);
            else if (TakeoffIn > 0f) TakeoffIn = Mathf.Max(0f, TakeoffIn - dt);
            if (!Grounded) { TakeoffIn = -1f; }

            // ------------------------------------------------ hop / lip jump / slide
            if (Grounded && inp.HopPressed && canControl)
            {
                // a lip is coming up: hold the jump and fire it at the takeoff (the later the press, the higher)
                if (TakeoffIn >= 0f && TakeoffIn <= LipWindow) { LipLoaded = true; lipTimer = 0f; }
                else DoHop();
            }
            if (Grounded && LipLoaded)
            {
                lipTimer += dt;
                bool imminent = TakeoffIn >= 0f && TakeoffIn <= 0.12f && LiftingOff(pos, dt);
                if (imminent) LipLaunch(Mathf.Clamp01(1f - lipTimer / LipWindow));
                else if (lipTimer > LipWindow + 0.15f || (TakeoffIn < 0f && lipTimer > 0.1f))
                {
                    // the lip never came (turned away / slowed down): an ordinary hop, so a press is never eaten
                    LipLoaded = false;
                    DoHop();
                }
            }
            else if (Grounded && TakeoffDrop >= NaturalSep && TakeoffIn >= 0f && TakeoffIn <= 0.12f && LiftingOff(pos, dt))
            {
                // a big crest falls away faster than gravity can bend the kart's path: it flies on its own
                Grounded = false;
                noSnapTimer = 0.08f;
                hopInAir = inp.HopHeld;
            }
            if (Sliding) UpdateSlide(dt, inp, spd);

            // ------------------------------------------------ steering with yaw inertia
            float targetRate;
            float speedRef = Mathf.Max(Stats.MaxSpeed, 1f);
            if (Sliding)
            {
                float rel = Mathf.Clamp(steerSmoothed * SlideDir, -1f, 1f);
                // obtuse arc: the slide always turns, but gently; rates scale a little with speed so the arc radius stays wide
                float rate = Mathf.Lerp(Stats.SlideMin, Stats.SlideMax, (rel + 1f) * 0.5f) * Mathf.Lerp(0.9f, 1.05f, Mathf.Clamp01(Mathf.Abs(spd) / speedRef));
                targetRate = SlideDir * rate;
                // modest body angle: 10..20 degrees
                float targetYaw = SlideDir * (13f + 6f * rel);
                SlideYaw = Mathf.Lerp(SlideYaw, targetYaw, Mathx.Damp(7f, dt));
            }
            else
            {
                float speedF = Mathf.Clamp01(Mathf.Abs(spd) / 7f);
                // at top speed normal steering is wide (~30 m radius): tight corners need a slide + line, like CTR
                float hi = Mathf.Lerp(1f, 0.5f, Mathf.Clamp01(Mathf.Abs(spd) / speedRef));
                targetRate = steerSmoothed * Stats.TurnRate * speedF * hi * (spd < -0.5f ? -1f : 1f);
                SlideYaw = Mathf.Lerp(SlideYaw, 0f, Mathx.Damp(9f, dt));
            }
            if (!Grounded) targetRate *= 0.55f;
            if (Grounded && Surface == SurfaceType.Ice) targetRate *= 0.85f;
            if (Stunned) targetRate = 0f;
            YawRate = Mathf.MoveTowards(YawRate, targetRate, (Sliding ? SlideYawAccel : YawAccel) * dt);
            Fwd = Quaternion.AngleAxis(YawRate * dt, Up) * Fwd;

            // ------------------------------------------------ speed
            float fruitBonus = 1f + Fruit * 0.011f;
            float maxSpd = Stats.MaxSpeed * fruitBonus * SpeedMultiplier;
            if (StarTimer > 0) maxSpd += 3.5f;
            if (Sliding) maxSpd *= 0.99f;
            bool offroad = Grounded && Surface == SurfaceType.Offroad;
            bool mud = Grounded && Surface == SurfaceType.Mud;
            if (offroad && BoostTimer <= 0f && StarTimer <= 0f) maxSpd *= 0.62f;
            if (mud && StarTimer <= 0f) maxSpd *= BoostTimer > 0f ? 0.85f : 0.68f;
            MaxSpeedNow = maxSpd;

            if (BoostTimer > 0f)
            {
                BoostTimer -= dt * (inp.Gas ? 1f : 4f);   // letting go of the gas kills reserves (CTR rule)
                if (BoostTimer <= 0f) { BoostTimer = 0f; BoostBonus = 0f; }
            }
            float target = maxSpd + (BoostTimer > 0f ? BoostBonus : 0f);

            if (Grounded)
            {
                float f = Vector3.Dot(Velocity, Fwd);
                Vector3 lat = Velocity - Fwd * f;
                float nf = f;
                if (inp.Brake)
                {
                    if (nf > 0.5f) nf = Mathf.Max(0f, nf - 36f * dt);
                    else nf = Mathf.Max(-9f, nf - 14f * dt);
                }
                else if (inp.Gas)
                {
                    if (nf < target)
                    {
                        float a = BoostTimer > 0f ? 58f : Stats.Accel * (nf < 0 ? 2.2f : Mathf.Lerp(1.3f, 0.4f, Mathf.Clamp01(nf / maxSpd)));
                        nf = Mathf.Min(nf + a * dt, target);
                    }
                    else nf = Mathf.Max(target, nf - ((offroad || mud) ? 30f : 7f) * dt);
                }
                else
                {
                    nf = Mathf.MoveTowards(nf, 0f, (offroad || mud ? 15f : 6.5f) * dt);
                    if (nf > target) nf = Mathf.Max(target, nf - 10f * dt);
                }
                // lateral grip: high (the kart feels planted); a slide keeps a little slip that shows as skid marks
                float grip = Sliding ? 12f : 17f;
                if (Surface == SurfaceType.Ice) grip = Sliding ? 2.5f : 3.2f;
                if (mud) grip *= 0.6f;
                if (Stunned) grip = 3f;
                float latMag = lat.magnitude;
                float decay = Mathf.Exp(-grip * dt);
                // return part of the scrubbed sideways kinetic energy to forward motion (never creates energy)
                if (nf > 0f && inp.Gas) nf = Mathf.Sqrt(nf * nf + latMag * latMag * (1f - decay * decay) * 0.6f);
                Velocity = Fwd * nf + lat * decay;
                SlipSpeed = latMag + (Sliding ? Mathf.Abs(spd) * Mathf.Abs(Mathf.Sin(SlideYaw * Mathf.Deg2Rad)) : 0f);
                LongAccel = Mathf.Lerp(LongAccel, (nf - prevFwdSpeed) / dt, Mathx.Damp(10f, dt));
                LatAccel = Mathf.Lerp(LatAccel, nf * YawRate * Mathf.Deg2Rad, Mathx.Damp(10f, dt));
                prevFwdSpeed = nf;
            }
            else
            {
                float g = Gravity * (Velocity.y < 0f ? FallGravityMul : 1f);
                Velocity += Vector3.down * g * dt;
                Vector3 hv = Mathx.Flat(Velocity);
                Vector3 hf = Mathx.Flat(Fwd).normalized;
                float hs = hv.magnitude;
                if (hs > 1f && Vector3.Dot(hv, hf) > 0f)
                {
                    Vector3 nhv = Vector3.Slerp(hv.normalized, hf, Mathx.Damp(3f, dt)) * hs;
                    Velocity = new Vector3(nhv.x, Velocity.y, nhv.z);
                }
                SlipSpeed = 0f;
                LongAccel = Mathf.Lerp(LongAccel, 0f, Mathx.Damp(4f, dt));
                LatAccel = Mathf.Lerp(LatAccel, 0f, Mathx.Damp(4f, dt));
            }

            // boost pads
            if (Grounded)
            {
                for (int i = 0; i < Track.Pads.Count; i++)
                    if (Track.Pads[i].Contains(pos))
                    {
                        if (BoostTimer < 0.6f || BoostBonus < 7f) Boost(7.8f, 1.0f);
                        else BoostTimer = Mathf.Max(BoostTimer, 1.0f);
                        break;
                    }
            }

            Vector3 before = pos;
            pos += Velocity * dt;
            pos = ResolveRoad(pos, before);
            if (Respawning) return;
            transform.position = pos;

            // wrong way detection (player HUD)
            var s = Road.S;
            float along = Vector3.Dot(Velocity, s.Fwd[TrackIndex]);
            if (along < -4f && ControlsEnabled) WrongWayTimer += dt; else WrongWayTimer = Mathf.Max(0, WrongWayTimer - dt * 2f);
        }

        /// <summary>
        /// Road tracking, junction switching and fall detection, plus the solid world:
        ///  - this road's walls block from BOTH sides: a kart that got outside (open shoulder, over a low wall) can
        ///    never slip back in through a wall further on - it must come back through an opening
        ///  - walls of neighbouring roads block karts arriving from outside them (no clipping into a closed road)
        ///  - scenery solids (landmarks, trunks, rocks, pillars, gate posts) and a soft bound past open shoulders
        /// </summary>
        Vector3 ResolveRoad(Vector3 pos, Vector3 prev)
        {
            var road = Road; var s = road.S;
            SetTrackIndex(road, s.Nearest(pos, TrackIndex, 14));
            int ti = TrackIndex;
            Vector3 rel3 = pos - s.Pos[ti];
            float lateral = Vector3.Dot(rel3, s.Right[ti]);
            float height = Vector3.Dot(rel3, s.Up[ti]);
            float along = Vector3.Dot(rel3, s.Fwd[ti]);
            float hw = s.HalfWidth[ti];
            float limit = hw - KartRadius;
            float outer = hw + TrackBuilder.WallThick;
            int side = lateral < 0f ? -1 : 1;
            float absLat = Mathf.Abs(lateral);
            float block = road.Gap[ti] ? 0f : Track.WallBlockHeight(road, ti, side);
            bool wallHere = block > 0f && height > -3f && height < block;

            // ---- this road's walls (two-sided)
            if (outsideSide != 0 && absLat < limit - 0.3f) outsideSide = 0;                 // came back in through an opening
            if (outsideSide == 0 && absLat > outer + 0.2f && (!wallHere || absLat - limit > 4f)) outsideSide = side; // left through an opening / over a low wall
            if (wallHere && absLat > limit)
            {
                if (outsideSide != side)
                {
                    float pen = absLat - limit;
                    if (pen < 4f)
                    {
                        Vector3 wn = -s.Right[ti] * side;
                        pos += wn * pen;
                        WallBounce(wn);
                        absLat = limit;
                    }
                }
                else if (absLat < outer + KartRadius)
                {
                    Vector3 wn = s.Right[ti] * side;
                    pos += wn * (outer + KartRadius - absLat);
                    WallBounce(wn);
                    absLat = outer + KartRadius;
                }
            }

            // ---- leaving through an opening: junctions, branch ends, open sides, drops onto a road below
            bool pastEnd = !s.Closed && ((ti >= s.Count - 2 && along > 0f) || (ti <= 1 && along < 0f));
            bool outside = absLat > limit || pastEnd;
            if (outside || !road.IsMain)
            {
                Road other; int oi;
                // airborne and clearly off this road: catch a road below early (ledge drops onto a lower level)
                float reach = (!Grounded && Velocity.y < 0f && (absLat > hw + 2f || pastEnd)) ? 12f : 3.5f;
                if (Track.FindRoadContaining(pos, road, reach, out other, out oi))
                {
                    // prefer staying on the current road unless we are really leaving it
                    bool insideCurrent = absLat <= hw && !pastEnd && height > -1.5f && height < 3.5f;
                    if (!insideCurrent || (!road.IsMain && ti > s.Count * 0.6f && other.IsMain))
                    {
                        SetRoad(other, oi);
                        OffRoad = false;
                        return pos;
                    }
                }
            }

            // ---- neighbouring roads' walls and scenery solids
            Vector3 n; float pn;
            if ((absLat > limit - 1.2f || outsideSide != 0 || !road.IsMain) && Track.FindForeignWall(road, pos, prev, KartRadius, out n, out pn))
            {
                pos += n * pn;
                WallBounce(n);
            }
            if (Track.FindSolid(pos, KartRadius, out n, out pn))
            {
                pos += n * pn;
                WallBounce(n);
            }

            OffRoad = absLat > hw;
            // ---- soft world bound past open shoulders (cliff sides stay open: you fall and respawn)
            if (outsideSide != 0)
            {
                bool cliffSide = outsideSide < 0 ? road.CliffL[ti] : road.CliffR[ti];
                float bound = hw + TrackBuilder.ShoulderW + OpenBound;
                if (!cliffSide && absLat > bound && height > -6f)
                {
                    Vector3 wn = -s.Right[ti] * outsideSide;
                    pos += wn * (absLat - bound);
                    float vn = Vector3.Dot(Velocity, wn);
                    if (vn < 0f) Velocity -= wn * vn;
                }
            }
            // far off the side of an open road with no ground: lost
            if (absLat > hw + 45f) { transform.position = pos; ForceRespawn(); return pos; }

            float roadY = s.Pos[ti].y;
            bool inWater = Track.Theme.HasWater && pos.y < Track.WaterLevel + 0.25f && !(Grounded && Surface != SurfaceType.Offroad);
            if (inWater || pos.y < roadY - 9f) { transform.position = pos; ForceRespawn(); }
            return pos;
        }

        /// <summary>Wall contact response along normal 'wn' (pointing away from the wall): glancing hits slide
        /// along it, square hits bonk and shed speed.</summary>
        void WallBounce(Vector3 wn)
        {
            float vn = Vector3.Dot(Velocity, wn);
            if (vn >= 0f) return;
            float sp = Velocity.magnitude;
            float impact = -vn / Mathf.Max(sp, 0.1f);
            Velocity -= wn * vn * 1.2f;
            if (impact > 0.5f && sp > 9f)
            {
                Velocity *= 0.55f;
                NotifyBonk(impact);
            }
            else
            {
                Velocity *= 1f - impact * 0.25f;
                Vector3 tangent = Vector3.ProjectOnPlane(Velocity, Up);
                if (tangent.sqrMagnitude > 1f) Fwd = Vector3.Slerp(Fwd, tangent.normalized, 0.25f);
                if (impact > 0.15f) NotifyBonk(impact * 0.5f);
            }
        }

        void SetRoad(Road r, int idx)
        {
            // progress continuity through the main-index mapping
            float oldM = MainIndex;
            Road = r; TrackIndex = idx;
            outsideSide = 0;
            // changing roads (junctions, landing a long shortcut jump, falling to a road below) carries the full
            // progress difference; walking along one road keeps the 90-sample continuity guard
            AddProgress(oldM, r.MainIdx[idx], Track.MainCount * 0.45f);
        }

        void SetTrackIndex(Road r, int idx)
        {
            float oldM = r.MainIdx[TrackIndex];
            TrackIndex = idx;
            AddProgress(oldM, r.MainIdx[idx], 90f);
        }

        void AddProgress(float oldM, float newM, float limit)
        {
            int n = Track.MainCount;
            float d = newM - oldM;
            if (d < -n * 0.5f) d += n;
            if (d > n * 0.5f) d -= n;
            if (Mathf.Abs(d) < limit) Progress += d;
        }

        bool ProbeGround(Vector3 pos, out RaycastHit hit)
        {
            Vector3 dir = Grounded ? -Up : Vector3.down;
            Vector3 origin = pos - dir * 1.4f;
            float len = 1.4f + (Grounded ? 1.0f : Mathf.Max(0.4f, -Velocity.y * 0.03f));
            return Physics.Raycast(origin, dir, out hit, len, Layers.GroundMask, QueryTriggerInteraction.Ignore);
        }

        /// <summary>Plane fit of 4 corner rays for a stable normal (mesh face normals are faceted).</summary>
        Vector3 SampleNormal(Vector3 pos, Vector3 fallback)
        {
            Vector3 right = Vector3.Cross(Up, Fwd).normalized;
            Vector3 f = Fwd * 0.95f, r = right * 0.75f;
            Vector3 dir = -Up;
            Vector3 pFL, pFR, pBL, pBR;
            if (!Corner(pos + f - r, dir, out pFL) || !Corner(pos + f + r, dir, out pFR) ||
                !Corner(pos - f - r, dir, out pBL) || !Corner(pos - f + r, dir, out pBR)) return fallback;
            Vector3 n = Vector3.Cross((pFL + pFR) * 0.5f - (pBL + pBR) * 0.5f, (pFR + pBR) * 0.5f - (pFL + pBL) * 0.5f);
            n = -n.normalized;
            if (Vector3.Dot(n, fallback) < 0f) n = -n;
            if (Vector3.Dot(n, fallback) < 0.6f) return fallback; // straddling an edge (e.g. kicker lip)
            return n;
        }

        bool Corner(Vector3 p, Vector3 dir, out Vector3 point)
        {
            RaycastHit h;
            if (Physics.Raycast(p - dir * 1.4f, dir, out h, 2.6f, Layers.GroundMask, QueryTriggerInteraction.Ignore)) { point = h.point; return true; }
            point = p; return false;
        }

        void Land()
        {
            float air = AirTime;
            LastAirTime = air;
            float spd = Vector3.Dot(Velocity, Fwd);
            if (!Sliding && ControlsEnabled && !Stunned && Input.HopHeld && Mathf.Abs(Input.Steer) > 0.3f && spd > 10f && Surface != SurfaceType.Offroad)
                StartSlide(Input.Steer > 0 ? 1 : -1);
            // AIR TURBO: every landing after real hang time pays out; the longer the air, the longer the turbo.
            // Hopping in the air (or holding a launch) is the CTR trick that adds a little more.
            if (air >= AirTurboMin && ControlsEnabled && !Stunned && spd > 4f)
            {
                float dur = Mathf.Clamp((air - 0.22f) * 1.05f, 0.25f, 2.4f) * (hopInAir ? 1.2f : 1f);
                float bonus = 4.8f + Mathf.Clamp01((air - 0.4f) / 1.2f) * 3.4f;
                Boost(bonus, dur);
                if (OnAirBoost != null) OnAirBoost(air, dur);
            }
            hopInAir = false;
            if (OnLand != null) OnLand(air);
        }

        void DoHop()
        {
            Velocity += Up * HopSpeed;
            Grounded = false;
            noSnapTimer = 0.12f;
            hopInAir = false;
            if (OnHop != null) OnHop();
        }

        /// <summary>Fires a loaded lip jump. q = 1 - (time between the press and the takeoff) / LipWindow.</summary>
        void LipLaunch(float q)
        {
            LipLoaded = false;
            float up = HopSpeed + LipBonusMax * q * q;
            Velocity += Vector3.up * up;        // straight up: a launch never costs forward speed
            Grounded = false;
            noSnapTimer = 0.15f;
            hopInAir = true;
            LastLaunchQuality = q;
            if (OnHop != null) OnHop();
            if (OnLaunch != null) OnLaunch(q);
        }

        /// <summary>Precise lift-off test (one ray, every sub-step while a takeoff is imminent): does the road fall
        /// away from the kart's own ballistic arc over the next two sub-steps?</summary>
        bool LiftingOff(Vector3 pos, float dt)
        {
            float tau = 2f * dt;
            Vector3 b = pos + Velocity * tau + Vector3.down * (0.5f * Gravity * tau * tau);
            RaycastHit h;
            if (!Physics.Raycast(b + Vector3.up * 1.5f, Vector3.down, out h, 4f, Layers.GroundMask, QueryTriggerInteraction.Ignore)) return true;
            return b.y - h.point.y > 0.01f;
        }

        /// <summary>
        /// Ground-following takeoff predictor: samples the road ahead (every ProbeDt seconds of travel, ProbeN nodes),
        /// finds the first node where the road falls away faster than gravity can bend the kart's path (crest, kicker
        /// lip, hump, ledge, gap) and measures how far the road drops below the launch arc. Probes that leave the
        /// current road's surface sideways are ignored (a corner on a cliff edge is not a ramp).
        /// </summary>
        void PredictTakeoff(Vector3 pos, float spd)
        {
            TakeoffIn = -1f; TakeoffDrop = 0f;
            if (!Grounded || spd < 9f) return;
            Vector3 dir = Mathx.Flat(Fwd);
            if (dir.sqrMagnitude < 0.01f) return;
            dir = dir.normalized;
            float d = Mathf.Max(0.8f, spd * ProbeDt);
            var s = Road.S;
            int hint = TrackIndex;
            int cnt = 1;
            probeY[0] = pos.y;
            for (int k = 1; k < probeY.Length; k++)
            {
                Vector3 p = pos + dir * (d * k);
                hint = s.Nearest(p, hint + Mathf.RoundToInt(d / s.Step), 6);
                if (Mathf.Abs(s.Lateral(p, hint)) > s.HalfWidth[hint] + 0.5f && !Road.Gap[hint]) break;
                RaycastHit h;
                probeY[k] = Physics.Raycast(p + Vector3.up * 6f, Vector3.down, out h, 40f, Layers.GroundMask, QueryTriggerInteraction.Ignore) ? h.point.y : p.y - 30f;
                cnt = k + 1;
            }
            float snapRef = 0.42f + spd * 0.006f;
            for (int k = 1; k <= ProbeN && k + 1 < cnt; k++)
            {
                float mPrev = (probeY[k] - probeY[k - 1]) / d;
                float mNext = (probeY[k + 1] - probeY[k]) / d;
                bool edge = probeY[k + 1] < probeY[k] + mPrev * d - snapRef;
                if (spd * spd * (mPrev - mNext) / d <= Gravity && !edge) continue;
                float best = 0f;
                for (int j = k + 1; j < cnt; j++)
                {
                    float tt = (j - k) * d / spd;
                    float arc = probeY[k] + mPrev * (j - k) * d - 0.5f * Gravity * tt * tt;
                    float sep = arc - probeY[j];
                    if (sep < -0.05f) break;       // the road comes back up to meet the arc: only a kink, not a lip
                    best = Mathf.Max(best, sep);
                }
                if (best >= LipMinSep) { TakeoffIn = k * d / spd; TakeoffDrop = best; return; }
            }
        }

        void StartSlide(int dir)
        {
            Sliding = true; SlideDir = dir; SlideGauge = 0f; SlideBoosts = 0; SlideTime = 0f; backfireTimer = 0f;
            // the tail kicks out a touch: a little sideways velocity that the grip scrubs into tyre marks
            Velocity -= Vector3.Cross(Up, Fwd).normalized * dir * 1.2f;
        }

        public void EndSlide()
        {
            Sliding = false; SlideGauge = 0f; SlideBoosts = 0; backfireTimer = 0f;
        }

        /// <summary>
        /// Slide turbo: the gauge sweeps 0..1 in GaugeFillTime; BOOST must be pressed while the needle is inside
        /// the single window [ZoneMin, ZoneMax] (narrower for each of the 3 boosts). Too soon or too late
        /// backfires: the gauge restarts after a short choke.
        /// </summary>
        void UpdateSlide(float dt, KartInput inp, float spd)
        {
            SlideTime += dt;
            if (!inp.HopHeld || spd < 7f || Stunned) { EndSlide(); return; }
            if (SlideBoosts >= 3) return;
            if (backfireTimer > 0f)
            {
                backfireTimer -= dt;
                SlideGauge = 0f;
                return;
            }
            SlideGauge += dt / GaugeFillTime;
            if (SlideGauge >= 1f)
            {
                Miss(true); // waited too long: the engine chokes
                return;
            }
            if (inp.BoostPressed)
            {
                if (SlideGauge >= ZoneMin && SlideGauge <= ZoneMax)
                {
                    SlideBoosts++;
                    float bonus = 5.2f + SlideBoosts * 1.15f;
                    float dur = 0.6f + SlideBoosts * 0.16f;
                    Boost(bonus, dur);
                    SlideGauge = 0f;
                    if (OnSlideBoost != null) OnSlideBoost(SlideBoosts, SlideBoosts >= 3);
                }
                else Miss(SlideGauge > ZoneMax);
            }
        }

        void Miss(bool late)
        {
            LastFailLate = late;
            SlideGauge = 0f;
            backfireTimer = BackfireTime;
            if (OnSlideFail != null) OnSlideFail();
        }

        void UpdateRespawn(float dt)
        {
            respawnTimer -= dt;
            Velocity = Vector3.zero;
            YawRate = 0f;
            if (respawnTimer > 0f) return;
            Vector3 p; Quaternion r; int idx;
            float oldM = MainIndex;
            Track.RespawnPose(respawnMain >= 0 ? respawnMain : oldM, out p, out r, out idx);
            transform.SetPositionAndRotation(p, r);
            Fwd = r * Vector3.forward; Up = r * Vector3.up;
            Road = Track.Main; TrackIndex = idx;
            // progress follows the respawn point exactly (a failed shortcut is sent back before its junction)
            int n = Track.MainCount;
            float dp = idx - oldM;
            if (dp < -n * 0.5f) dp += n;
            if (dp > n * 0.5f) dp -= n;
            Progress += dp;
            respawnMain = -1;
            outsideSide = 0;
            Respawning = false;
            Grounded = false;
            AirTime = 0f;               // the fall never pays an air turbo
            LipLoaded = false;
            TakeoffIn = -1f;
            InvulnTimer = 1.5f;
            if (OnRespawned != null) OnRespawned();
        }
    }
}
