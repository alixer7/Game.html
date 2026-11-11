using System.Collections.Generic;
using UnityEngine;

namespace TurboTribe
{
    public enum RaceState { Intro, Countdown, Racing, Done }

    public class ResultRow
    {
        public string Name; public CharacterDef Character; public float Time; public bool IsPlayer; public bool Estimated; public int Place;
    }

    /// <summary>
    /// Runs a race: builds the track, spawns 8 racers on the grid, intro fly-around, countdown with
    /// start-line turbo, lap/position tracking, rubber-banding, kart bumping, item events and results.
    /// </summary>
    [DefaultExecutionOrder(-20)]
    public class RaceManager : MonoBehaviour
    {
        public static RaceManager Instance;
        public TrackInstance Track;
        public readonly List<KartController> Karts = new List<KartController>();
        public KartController Player;
        public CameraRig Rig;
        public ItemManager Items;
        public ObstacleManager Obstacles;
        public SkidMarks Skids;
        public RaceHUD Hud;
        public TouchControls Touch;
        public int Laps = 3;
        public int Difficulty = 1;
        public RaceState State;
        public float RaceTime;
        public readonly List<KartController> FinishOrder = new List<KartController>();
        public readonly List<float> PlayerLapTimes = new List<float>();
        public System.Action<List<ResultRow>> OnComplete;

        PlayerKartInput playerInput;
        float stateTimer;
        int countdown;
        float gasDownAt = -99f, boostTapAt = -99f;
        bool prevGas;
        float goTime;
        bool startBoostChecked;
        float lapStartTime;
        readonly Dictionary<KartController, AudioSource> engines = new Dictionary<KartController, AudioSource>();
        readonly Dictionary<KartController, AIDriver> ais = new Dictionary<KartController, AIDriver>();
        readonly Dictionary<KartController, float> baseMult = new Dictionary<KartController, float>();
        bool finalLapShown;
        float wrongWayCooldown;

        public static RaceManager Create(Transform parent, string trackId, int charIdx, int laps, int difficulty, Canvas canvas, RectTransform safe)
        {
            var go = new GameObject("Race");
            go.transform.SetParent(parent, false);
            var rm = go.AddComponent<RaceManager>();
            Instance = rm;
            rm.Laps = laps; rm.Difficulty = difficulty;
            rm.Setup(TrackDatabase.Load(trackId), charIdx, canvas, safe);
            return rm;
        }

        void Setup(TrackData data, int charIdx, Canvas canvas, RectTransform safe)
        {
            Track = TrackBuilder.Build(data, transform);
            Particles.InitPool(transform);
            var itemsGo = new GameObject("Items");
            itemsGo.transform.SetParent(transform, false);
            Items = itemsGo.AddComponent<ItemManager>();
            Items.Race = this;
            Items.Build(Track);
            var skGo = new GameObject("SkidMarks");
            skGo.transform.SetParent(transform, false);
            Skids = skGo.AddComponent<SkidMarks>();
            var obGo = new GameObject("Obstacles");
            obGo.transform.SetParent(transform, false);
            Obstacles = obGo.AddComponent<ObstacleManager>();
            Obstacles.Build(Track, TrackBuilder.StableHash(data.id));
            Obstacles.Karts = Karts;
            Obstacles.OnKartHit = (o, k) => OnObstacleHit(o, k);
            AIDriver.Obstacles = Obstacles;

            // roster: player + the other 7 characters
            var roster = new List<int> { charIdx };
            for (int i = 0; i < CharacterDef.All.Length; i++) if (i != charIdx) roster.Add(i);
            int playerSlot = 5;
            var s = Track.Spline;
            var order = new List<int>();
            for (int i = 1; i < roster.Count; i++) order.Add(roster[i]);
            // shuffle CPU order a little
            for (int i = 0; i < order.Count; i++) { int j = Random.Range(i, order.Count); int t = order[i]; order[i] = order[j]; order[j] = t; }
            order.Insert(Mathf.Min(playerSlot, order.Count), charIdx);

            for (int slot = 0; slot < order.Count; slot++)
            {
                int row = slot / 2, side = slot % 2 == 0 ? -1 : 1;
                int idx = s.Wrap(-7 - row * 8 - (side > 0 ? 4 : 0));
                Vector3 pos = s.PointAt(idx, side * s.HalfWidth[idx] * 0.36f, 0.2f);
                Quaternion rot = Quaternion.LookRotation(s.Fwd[idx], s.Up[idx]);
                var ch = CharacterDef.All[order[slot]];
                bool isPlayer = order[slot] == charIdx && Player == null;
                var kgo = new GameObject((isPlayer ? "Player_" : "CPU_") + ch.Name);
                kgo.transform.SetParent(transform, false);
                var k = kgo.AddComponent<KartController>();
                k.Init(ch, Track, pos, rot, isPlayer, ch.Name);
                var vis = KartModel.Build(ch, kgo.transform);
                vis.Kart = k;
                vis.Skids = Skids;
                var items = kgo.AddComponent<KartItems>();
                items.Kart = k; items.Manager = Items;
                if (isPlayer)
                {
                    Player = k;
                    playerInput = kgo.AddComponent<PlayerKartInput>();
                    playerInput.Kart = k;
                    k.SpeedMultiplier = 1f;
                }
                else
                {
                    var ai = kgo.AddComponent<AIDriver>();
                    ai.Kart = k;
                    float lo = Difficulty == 0 ? 0.2f : Difficulty == 1 ? 0.45f : 0.72f;
                    float hi = Difficulty == 0 ? 0.45f : Difficulty == 1 ? 0.72f : 0.97f;
                    ai.Skill = Mathf.Lerp(lo, hi, Random.value);
                    ais[k] = ai;
                    float bm = Difficulty == 0 ? 0.9f : Difficulty == 1 ? 0.955f : 0.99f;
                    baseMult[k] = bm + ai.Skill * 0.02f;
                    k.SpeedMultiplier = baseMult[k];
                }
                HookKart(k);
                // engine
                var src = kgo.AddComponent<AudioSource>();
                src.clip = AudioManager.I != null ? AudioManager.I.EngineClip : null;
                src.loop = true;
                src.spatialBlend = isPlayer ? 0f : 0.9f;
                src.rolloffMode = AudioRolloffMode.Linear;
                src.minDistance = 4f; src.maxDistance = 45f;
                src.volume = (isPlayer ? 0.32f : 0.22f) * Settings.SfxVolume;
                src.dopplerLevel = 0.3f;
                if (src.clip != null) src.Play();
                engines[k] = src;
                Karts.Add(k);
            }

            Rig = CameraRig.Create(transform);
            Rig.Target = Player;
            Rig.Orbit = true;
            Rig.transform.position = Player.transform.position + new Vector3(0, 6, -12);

            Hud = RaceHUD.Create(safe, this);
            Touch = TouchControls.Create(safe, canvas);
            Touch.Kart = Player;
            Touch.Items = Player.GetComponent<KartItems>();
            Touch.gameObject.SetActive(false);
            playerInput.Touch = Touch;
            Hud.transform.SetAsLastSibling();

            var th = Track.Theme;
            if (AudioManager.I != null) { AudioManager.I.MusicPitch(1f); AudioManager.I.PlayMusic("race_" + data.id, th.MusicSeed, th.MusicTempo, th.Kind != ThemeKind.Snow); }

            State = RaceState.Intro;
            stateTimer = 3.2f;
            Hud.ShowTitle(data.name, data.difficulty);
        }

        void HookKart(KartController k)
        {
            var am = AudioManager.I;
            bool pl = k == Player;
            k.OnHop += () => { if (pl && am != null) am.Play(Sfx.Hop, 0.5f); };
            k.OnLand += air => { if (air > 0.45f && am != null) am.PlayAt(Sfx.Land, k.transform.position, 0.8f); if (pl && air > 0.6f) Rig.Shake(0.25f); };
            k.OnSlideBoost += (lvl, perfect) =>
            {
                if (!pl) return;
                if (am != null) am.Play(lvl >= 3 || perfect ? Sfx.BoostBig : Sfx.Boost, 0.9f, 1f + lvl * 0.06f);
                Hud.SlideBoost(lvl, perfect);
            };
            k.OnSlideFail += () => { if (pl) { if (am != null) am.Play(Sfx.Fail, 0.7f); Hud.Message(k.LastFailLate ? "TOO LATE!" : "TOO SOON!", UIFactory.Hex("#9AA3B8"), 70, 0.7f); } };
            k.OnLaunch += q => { if (pl) { Hud.Launch(q); if (am != null && q >= 0.45f) am.Play(Sfx.BoostBig, 0.55f, 1.25f); } };
            k.OnAirBoost += (air, dur) => { if (pl) { Hud.AirBoost(air, dur); if (am != null) am.Play(Sfx.Boost, 0.8f, 1.05f); } };
            k.OnBoost += () => { if (pl && am != null) am.Play(Sfx.Boost, 0.45f, 1.2f); };
            k.OnBonk += impact => { if (am != null) am.PlayAt(Sfx.Bonk, k.transform.position, Mathf.Clamp01(impact + 0.3f)); if (pl) Rig.Shake(0.5f * impact); };
            k.OnHitTaken += () => { if (am != null) am.PlayAt(Sfx.Hit, k.transform.position, 1f); if (pl) { Rig.Shake(0.9f); Hud.Message("OUCH!", UIFactory.Red, 90, 0.9f); } };
            k.OnShieldPop += () => { if (am != null) am.PlayAt(Sfx.Shield, k.transform.position); };
            k.OnFall += () => { if (am != null) am.PlayAt(Sfx.Splash, k.transform.position); };
            var items = k.GetComponent<KartItems>();
            if (items != null && pl)
            {
                items.OnRollTick += () => { if (am != null) am.Play(Sfx.ItemTick, 0.45f); };
                items.OnItemReady += t => { if (am != null) am.Play(Sfx.ItemGet, 0.7f); Hud.ItemReady(t); };
            }
        }

        void OnObstacleHit(Obstacle o, KartController k)
        {
            if (AudioManager.I != null) AudioManager.I.PlayAt(o.Type == "geyser" ? Sfx.Splash : Sfx.Hit, k.transform.position, 0.9f);
            if (o.Type == "geyser") Particles.Splash(o.Pos);
            if (k == Player)
            {
                Rig.Shake(0.7f);
                string msg = o.Type == "crab" ? "PINCHED!" : o.Type == "geyser" ? "SPLASH!" : o.Type == "penguin" ? "WADDLE WARNING!" : "BONK!";
                Hud.Message(msg, UIFactory.Red, 80, 0.9f);
            }
        }

        // ------------------------------------------------------------------ events from items
        public void OnFruit(KartController k, Vector3 p)
        {
            Particles.Sparkle(p);
            if (k == Player)
            {
                if (AudioManager.I != null) AudioManager.I.Play(Sfx.Fruit, 0.6f, 1f + k.Fruit * 0.03f);
                Hud.FruitBump();
                if (k.Fruit == 10) Hud.Message("JUICED UP!", UIFactory.Yellow, 80, 1.0f);
            }
        }

        public void OnCrate(KartController k, Vector3 p, bool got)
        {
            Particles.CrateBreak(p);
            if (AudioManager.I != null) AudioManager.I.PlayAt(Sfx.Crate, p, 0.8f);
        }

        public void OnExplosion(Vector3 p)
        {
            if (AudioManager.I != null) AudioManager.I.PlayAt(Sfx.Explosion, p, 1f);
            if (Player != null && Vector3.Distance(Player.transform.position, p) < 25f) Rig.Shake(0.6f);
        }

        public void OnKartHit(KartController victim, KartController attacker, ItemType kind)
        {
            if (attacker == Player && victim != Player) Hud.Message("GOTCHA!", UIFactory.Green, 80, 0.8f);
        }

        public void OnItemUsed(KartController k, ItemType t)
        {
            var am = AudioManager.I; if (am == null) return;
            switch (t)
            {
                case ItemType.Bomb: case ItemType.Missile: case ItemType.BoomCrate: am.PlayAt(Sfx.Throw, k.transform.position, 0.8f); break;
                case ItemType.Shield: case ItemType.Star: am.PlayAt(Sfx.Shield, k.transform.position, 0.8f); break;
            }
        }

        // ------------------------------------------------------------------ loop
        void Update()
        {
            float dt = Time.deltaTime;
            switch (State)
            {
                case RaceState.Intro:
                    stateTimer -= dt;
                    if (stateTimer <= 0f || (stateTimer < 2.4f && (Input.GetMouseButtonDown(0) || Input.touchCount > 0 && Input.GetTouch(0).phase == TouchPhase.Began)))
                    {
                        State = RaceState.Countdown;
                        Rig.Orbit = false;
                        Hud.HideTitle();
                        Touch.gameObject.SetActive(true);
                        countdown = 4; stateTimer = 0.9f;
                    }
                    break;
                case RaceState.Countdown:
                    TrackStartInputs();
                    stateTimer -= dt;
                    if (stateTimer <= 0f)
                    {
                        countdown--;
                        if (countdown > 0)
                        {
                            stateTimer = 1f;
                            Hud.Countdown(countdown);
                            if (AudioManager.I != null) AudioManager.I.Play(Sfx.Beep, 0.8f);
                        }
                        else Go();
                    }
                    break;
                case RaceState.Racing:
                    RaceTime += dt;
                    if (!startBoostChecked) { TrackStartInputs(); if (RaceTime > 0.25f) { startBoostChecked = true; ApplyPlayerStartBoost(true); } }
                    UpdateRace(dt);
                    break;
                case RaceState.Done:
                    RaceTime += dt;
                    UpdateRace(dt);
                    stateTimer -= dt;
                    if (stateTimer <= 0f && OnComplete != null) { var cb = OnComplete; OnComplete = null; cb(BuildResults()); }
                    break;
            }
            UpdateEngines();
        }

        void TrackStartInputs()
        {
            if (Player == null) return;
            float now = Time.time;
            bool gas = Player.Input.Gas && !Settings.AutoGas;
            if (gas && !prevGas) gasDownAt = now;
            prevGas = gas;
            if (Player.Input.BoostPressed || Player.Input.HopPressed) boostTapAt = now;
        }

        void Go()
        {
            State = RaceState.Racing;
            RaceTime = 0f;
            goTime = Time.time;
            lapStartTime = 0f;
            Hud.Countdown(0);
            if (AudioManager.I != null) AudioManager.I.Play(Sfx.Go, 0.9f);
            foreach (var k in Karts)
            {
                k.ControlsEnabled = true;
                if (k != Player && ais.ContainsKey(k) && Random.value < 0.25f + ais[k].Skill * 0.55f)
                    k.Boost(5.5f, 0.9f);
            }
            ApplyPlayerStartBoost(false);
        }

        /// <summary>CTR-style start: hit the gas (or tap BOOST with auto-gas) right as GO appears.</summary>
        void ApplyPlayerStartBoost(bool late)
        {
            if (Player == null) return;
            if (Settings.AutoGas)
            {
                float d = boostTapAt - goTime;
                if (d > -0.45f && d < 0.25f && !startBoostGiven) { GiveStartBoost(); }
                return;
            }
            if (late) return;
            if (prevGas)
            {
                float held = goTime - gasDownAt;
                if (held <= 0.55f) GiveStartBoost();
                else if (held > 1.3f)
                {
                    // revved too early: stall
                    Player.ControlsEnabled = false;
                    Invoke("UnstallPlayer", 0.8f);
                    Particles.Smoke(Player.transform.position + Vector3.up, 10);
                    Hud.Message("STALLED!", UIFactory.Hex("#9AA3B8"), 80, 0.9f);
                }
            }
        }

        bool startBoostGiven;
        void GiveStartBoost()
        {
            startBoostGiven = true;
            Player.Boost(6.5f, 1.1f);
            Hud.Message("START BOOST!", UIFactory.Orange, 86, 1.0f);
            if (AudioManager.I != null) AudioManager.I.Play(Sfx.BoostBig, 0.9f);
        }

        void UnstallPlayer() { if (Player != null && State != RaceState.Done) Player.ControlsEnabled = true; }

        void UpdateRace(float dt)
        {
            int n = Track.Spline.Count;
            // laps + finishing
            foreach (var k in Karts)
            {
                int lap = Mathf.FloorToInt(k.Progress / n) + 1;
                if (lap > k.Lap)
                {
                    k.Lap = lap;
                    if (k.Lap > Laps && !k.Finished) Finish(k);
                    else if (k == Player && k.Lap >= 2)
                    {
                        float lt = RaceTime - lapStartTime;
                        PlayerLapTimes.Add(lt);
                        lapStartTime = RaceTime;
                        if (k.Lap == Laps && !finalLapShown)
                        {
                            finalLapShown = true;
                            Hud.Message("FINAL LAP!", UIFactory.Red, 110, 1.6f);
                            if (AudioManager.I != null) { AudioManager.I.Play(Sfx.Lap, 0.9f); AudioManager.I.MusicPitch(1.06f); }
                        }
                        else
                        {
                            Hud.Message("LAP " + k.Lap, UIFactory.Yellow, 100, 1.2f);
                            if (AudioManager.I != null) AudioManager.I.Play(Sfx.Lap, 0.8f);
                        }
                    }
                    else if (k == Player && k.Lap == 1) lapStartTime = RaceTime;
                }
            }
            // places
            var sorted = new List<KartController>(Karts);
            sorted.Sort((a, b) =>
            {
                if (a.Finished && b.Finished) return FinishOrder.IndexOf(a).CompareTo(FinishOrder.IndexOf(b));
                if (a.Finished) return -1;
                if (b.Finished) return 1;
                return b.Progress.CompareTo(a.Progress);
            });
            for (int i = 0; i < sorted.Count; i++) sorted[i].Place = i + 1;

            // rubber-banding (CTR AI is famously persistent)
            if (Player != null)
            {
                foreach (var k in Karts)
                {
                    if (k == Player || k.Finished) continue;
                    float gap = Player.Progress - k.Progress; // + = AI behind
                    float m = baseMult[k];
                    if (gap > 0) m += Mathf.Clamp01(gap / 160f) * (Difficulty == 0 ? 0.05f : 0.09f);
                    else m -= Mathf.Clamp01(-gap / 220f) * (Difficulty == 2 ? 0.04f : 0.08f);
                    if (State == RaceState.Done) m = 0.97f;
                    k.SpeedMultiplier = Mathf.MoveTowards(k.SpeedMultiplier, m, dt * 0.2f);
                }
            }

            KartCollisions();

            // wrong way
            if (Player != null && State == RaceState.Racing)
            {
                wrongWayCooldown -= dt;
                if (Player.WrongWayTimer > 1.2f && wrongWayCooldown <= 0f) { Hud.Message("WRONG WAY!", UIFactory.Red, 90, 1.0f); wrongWayCooldown = 2f; }
            }
        }

        void KartCollisions()
        {
            for (int i = 0; i < Karts.Count; i++)
                for (int j = i + 1; j < Karts.Count; j++)
                {
                    var a = Karts[i]; var b = Karts[j];
                    if (a.Respawning || b.Respawning) continue;
                    Vector3 d = b.transform.position - a.transform.position;
                    if (Mathf.Abs(d.y) > 1.6f) continue;
                    d.y = 0;
                    float dist = d.magnitude;
                    const float minD = 1.85f;
                    if (dist >= minD || dist < 1e-4f) continue;
                    Vector3 nrm = d / dist;
                    // star power flattens whoever it touches
                    if (a.StarTimer > 0f && b.StarTimer <= 0f) { if (b.Hit(false)) OnKartHit(b, a, ItemType.Star); }
                    else if (b.StarTimer > 0f && a.StarTimer <= 0f) { if (a.Hit(false)) OnKartHit(a, b, ItemType.Star); }
                    float push = (minD - dist) * 0.5f;
                    a.transform.position -= nrm * push;
                    b.transform.position += nrm * push;
                    float va = Vector3.Dot(a.Velocity, nrm), vb = Vector3.Dot(b.Velocity, nrm);
                    float rel = va - vb;
                    if (rel > 0f)
                    {
                        float imp = rel * 0.75f;
                        a.Velocity -= nrm * imp;
                        b.Velocity += nrm * imp;
                        if (rel > 4f && AudioManager.I != null && (a == Player || b == Player)) AudioManager.I.Play(Sfx.Bonk, 0.4f, 1.3f);
                    }
                }
        }

        void Finish(KartController k)
        {
            k.Finished = true;
            k.FinishTime = RaceTime;
            FinishOrder.Add(k);
            if (k != Player) return;
            float lt = RaceTime - lapStartTime;
            PlayerLapTimes.Add(lt);
            State = RaceState.Done;
            stateTimer = 4.5f;
            // the CPU takes over the player's kart for the victory lap
            playerInput.Autopilot = true;
            var ai = Player.gameObject.AddComponent<AIDriver>();
            ai.Kart = Player; ai.Skill = 0.6f;
            Touch.gameObject.SetActive(false);
            Rig.Orbit = true;
            int place = FinishOrder.Count;
            Hud.Finish(place);
            Particles.Confetti(Player.transform.position + Vector3.up * 3f);
            if (AudioManager.I != null) { AudioManager.I.Play(Sfx.Finish, 1f); AudioManager.I.MusicPitch(1f); }
            Settings.SetTrophy(Track.Data.id, place);
            float best = Settings.BestLap(Track.Data.id);
            foreach (var t in PlayerLapTimes) if (best <= 0f || t < best) best = t;
            Settings.SetBestLap(Track.Data.id, best);
        }

        List<ResultRow> BuildResults()
        {
            var rows = new List<ResultRow>();
            int n = Track.Spline.Count;
            var sorted = new List<KartController>(Karts);
            sorted.Sort((a, b) => a.Place.CompareTo(b.Place));
            float lastTime = 0f;
            foreach (var k in sorted)
            {
                float t = k.FinishTime;
                bool est = false;
                if (!k.Finished)
                {
                    float remaining = Mathf.Max(0f, Laps * n - k.Progress) * Track.Spline.Step;
                    t = RaceTime + remaining / 24f;
                    est = true;
                }
                t = Mathf.Max(t, lastTime + 0.05f);
                lastTime = t;
                rows.Add(new ResultRow { Name = k.RacerName, Character = k.Character, Time = t, IsPlayer = k == Player, Estimated = est, Place = k.Place });
            }
            return rows;
        }

        void UpdateEngines()
        {
            foreach (var kv in engines)
            {
                var k = kv.Key; var src = kv.Value;
                if (src == null) continue;
                float sp = Mathf.Abs(k.ForwardSpeed) / Mathf.Max(k.Stats.MaxSpeed, 1f);
                float target = 0.55f + sp * 1.05f + (k.Boosting ? 0.18f : 0f) + (k.Grounded ? 0f : 0.12f);
                if (State == RaceState.Countdown && k == Player && k.Input.Gas) target = 1.1f + Mathf.PingPong(Time.time * 2f, 0.4f);
                src.pitch = Mathf.Lerp(src.pitch, target, Time.deltaTime * 8f);
                src.mute = k.Respawning || Time.timeScale == 0f;
            }
        }

        /// <summary>Recreates the touch layout after settings changed (steering mode, handedness, auto-gas).</summary>
        public void RebuildTouch()
        {
            if (Touch == null) return;
            bool active = Touch.gameObject.activeSelf;
            var parent = (RectTransform)Touch.transform.parent;
            var canvas = Touch.GetComponentInParent<Canvas>();
            Destroy(Touch.gameObject);
            Touch = TouchControls.Create(parent, canvas);
            Touch.Kart = Player;
            Touch.Items = Player.GetComponent<KartItems>();
            Touch.gameObject.SetActive(active);
            playerInput.Touch = Touch;
            Hud.transform.SetAsLastSibling();
        }

        public void SetPaused(bool p)
        {
            Time.timeScale = p ? 0f : 1f;
            AudioListener.pause = p;
            if (Touch != null) Touch.enabled = !p; // OnDisable clears held fingers + pending presses
        }

        void OnDestroy()
        {
            Time.timeScale = 1f;
            AudioListener.pause = false;
            if (Instance == this) Instance = null;
        }
    }
}
