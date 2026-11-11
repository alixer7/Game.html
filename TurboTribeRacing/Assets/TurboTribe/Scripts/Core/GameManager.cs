using System.Collections;
using System.Collections.Generic;
using UnityEngine;
using UnityEngine.UI;

namespace TurboTribe
{
    /// <summary>
    /// Entry point and screen flow. Boots automatically in ANY scene (RuntimeInitializeOnLoadMethod),
    /// so the project needs no hand-made scenes or prefabs.
    /// Flow: Main menu -> Character select -> Track select -> Race -> Results.
    /// </summary>
    public class GameManager : MonoBehaviour
    {
        public static GameManager I;
        public const string Version = "0.1.0";

        Canvas canvas;
        RectTransform safe;
        RectTransform screen;     // current full-screen UI
        RectTransform overlay;    // pause / settings / results (safe-area content)
        RectTransform overlayRoot; // dimmed full-screen backdrop that owns 'overlay'
        GameObject world;
        Showroom showroom;
        RaceManager race;
        int charIdx, trackIdx;
        System.Action backAction;

        [RuntimeInitializeOnLoadMethod(RuntimeInitializeLoadType.AfterSceneLoad)]
        static void Boot()
        {
            if (I != null) return;
            var go = new GameObject("TurboTribe");
            go.AddComponent<GameManager>();
        }

        void Awake()
        {
            I = this;
            DontDestroyOnLoad(gameObject);
            Screen.sleepTimeout = SleepTimeout.NeverSleep;
            Screen.autorotateToPortrait = false;
            Screen.autorotateToPortraitUpsideDown = false;
            Screen.autorotateToLandscapeLeft = true;
            Screen.autorotateToLandscapeRight = true;
            Screen.orientation = ScreenOrientation.AutoRotation;
            Input.multiTouchEnabled = true;
            Settings.ApplyQuality();
            // disable any camera / light the host scene may contain (the game builds its own)
            foreach (var c in FindObjectsByType<Camera>(FindObjectsSortMode.None)) c.gameObject.SetActive(false);
            foreach (var l in FindObjectsByType<Light>(FindObjectsSortMode.None)) l.gameObject.SetActive(false);
            AudioManager.Create(transform);
            UIFactory.EnsureEventSystem();
            canvas = UIFactory.CreateCanvas("UI", 10, out safe);
            canvas.transform.SetParent(transform, false);
            charIdx = Mathf.Clamp(Settings.CharacterIndex, 0, CharacterDef.All.Length - 1);
            trackIdx = Mathf.Clamp(Settings.TrackIndex, 0, TrackDatabase.Ids.Length - 1);
        }

        void Start() { ShowMainMenu(); }

        void Update()
        {
            // Android back button
            if (Input.GetKeyDown(KeyCode.Escape))
            {
                if (race != null && race.State != RaceState.Done && overlay == null) Pause();
                else if (backAction != null) backAction();
            }
        }

        // ------------------------------------------------------------------ helpers
        void ClearScreen()
        {
            if (screen != null) Destroy(screen.gameObject);
            screen = UIFactory.Stretch("Screen", safe);
            CloseOverlay();
        }

        void CloseOverlay()
        {
            if (overlayRoot != null) Destroy(overlayRoot.gameObject);
            overlayRoot = null;
            overlay = null;
        }

        RectTransform OpenOverlay(float dim = 0.6f)
        {
            CloseOverlay();
            var o = UIFactory.Stretch("Overlay", canvas.transform);
            overlayRoot = o;
            var bg = o.gameObject.AddComponent<Image>();
            bg.color = new Color(0.05f, 0.03f, 0.12f, dim);
            overlay = UIFactory.Stretch("SafeArea", o);
            overlay.gameObject.AddComponent<SafeArea>();
            return overlay;
        }

        void EnsureShowroom()
        {
            if (showroom != null) return;
            if (world != null) Destroy(world);
            world = new GameObject("MenuWorld");
            Particles.InitPool(world.transform);
            showroom = Showroom.Create(world.transform);
            showroom.ShowCharacter(CharacterDef.All[charIdx]);
            if (AudioManager.I != null) { AudioManager.I.MusicPitch(1f); AudioManager.I.PlayMusic("menu", 7, 118, true); }
        }

        static Text Title(Transform parent, string text, Vector2 pos, int size = 96)
        {
            return UIFactory.Text(parent, text, size, UIFactory.Yellow, TextAnchor.MiddleCenter, new Vector2(0.5f, 1f), pos, new Vector2(1400, 140), 6f);
        }

        // ------------------------------------------------------------------ main menu
        public void ShowMainMenu()
        {
            if (race != null) { Destroy(race.gameObject); race = null; }
            if (world != null && showroom == null) { Destroy(world); world = null; }
            EnsureShowroom();
            showroom.CamOffset = new Vector3(-2.6f, 2.2f, -7.0f);
            showroom.LookOffset = new Vector3(-2.3f, 0.9f, 0f);
            ClearScreen();
            backAction = null;

            var logo = UIFactory.Rect("Logo", screen, new Vector2(0, 1), new Vector2(0, 1), new Vector2(470, -230), new Vector2(820, 380));
            logo.gameObject.AddComponent<UIBob>();
            var ribbon = UIFactory.Image(logo, UIFactory.Rounded, UIFactory.Red, new Vector2(0.5f, 0.5f), new Vector2(10, -118), new Vector2(560, 110), true);
            ribbon.rectTransform.localRotation = Quaternion.Euler(0, 0, 3);
            UIFactory.Text(logo, "TURBO", 210, UIFactory.Yellow, TextAnchor.MiddleCenter, new Vector2(0.5f, 0.5f), new Vector2(-40, 110), new Vector2(900, 220), 9f).transform.localRotation = Quaternion.Euler(0, 0, 4);
            UIFactory.Text(logo, "TRIBE", 170, UIFactory.Orange, TextAnchor.MiddleCenter, new Vector2(0.5f, 0.5f), new Vector2(30, -8), new Vector2(900, 200), 9f).transform.localRotation = Quaternion.Euler(0, 0, 4);
            UIFactory.Text(logo, "RACING", 80, Color.white, TextAnchor.MiddleCenter, new Vector2(0.5f, 0.5f), new Vector2(10, -118), new Vector2(600, 100), 5f).transform.localRotation = Quaternion.Euler(0, 0, 3);

            Vector2 a = new Vector2(0, 0);
            UIFactory.Button(screen, "PLAY", UIFactory.Orange, a, new Vector2(400, 400), new Vector2(560, 160), ShowCharacterSelect, 84);
            UIFactory.Button(screen, "HOW TO PLAY", UIFactory.Purple, a, new Vector2(400, 245), new Vector2(560, 120), ShowHowTo, 52);
            UIFactory.Button(screen, "SETTINGS", UIFactory.Blue, a, new Vector2(400, 110), new Vector2(560, 120), () => ShowSettings(null), 52);
            UIFactory.Text(screen, "v" + Version + " PROTOTYPE", 28, new Color(1, 1, 1, 0.8f), TextAnchor.LowerRight, new Vector2(1, 0), new Vector2(-180, 30), new Vector2(400, 40), 2f, false);
            var ch = CharacterDef.All[charIdx];
            UIFactory.Text(screen, ch.Name, 64, Color.white, TextAnchor.MiddleCenter, new Vector2(0.72f, 0f), new Vector2(0, 120), new Vector2(600, 90), 4f);
        }

        void ShowHowTo()
        {
            var o = OpenOverlay(0.75f);
            UIFactory.PanelBox(o, UIFactory.Hex("#2A1F55"), new Vector2(0.5f, 0.5f), new Vector2(0, 10), new Vector2(1500, 900));
            Title(o, "HOW TO RACE", new Vector2(0, -150), 90);
            string[] lines =
            {
                "STEER  -  drag left/right anywhere on the left side",
                "POWER-SLIDE  -  hold HOP while steering into a turn",
                "TURBO  -  when the BOOST button glows, roll your thumb onto it (or tap it)",
                "Up to 3 turbos per slide. Hit the RED zone for a PERFECT turbo",
                "Steer INTO the slide to tighten it, AWAY to widen it",
                "HANG-TIME TURBO  -  hop off a ramp and land a big jump",
                "START TURBO  -  tap BOOST right as GO! appears",
                "Grab 10 FRUIT to go faster and JUICE UP your weapons",
                "Smash ? crates for items, then fire them with ITEM",
            };
            for (int i = 0; i < lines.Length; i++)
                UIFactory.Text(o, lines[i], 38, i % 2 == 0 ? Color.white : UIFactory.Cream, TextAnchor.MiddleLeft, new Vector2(0.5f, 0.5f), new Vector2(-660 + 660, 250 - i * 66), new Vector2(1320, 60), 2.5f, false).alignment = TextAnchor.MiddleCenter;
            UIFactory.Button(o, "GOT IT!", UIFactory.Orange, new Vector2(0.5f, 0.5f), new Vector2(0, -360), new Vector2(420, 120), CloseOverlay, 60);
            backAction = () => { CloseOverlay(); backAction = null; };
        }

        // ------------------------------------------------------------------ character select
        public void ShowCharacterSelect()
        {
            EnsureShowroom();
            showroom.CamOffset = new Vector3(2.4f, 2.1f, -6.6f);
            showroom.LookOffset = new Vector3(2.0f, 0.8f, 0f);
            ClearScreen();
            backAction = ShowMainMenu;
            Title(screen, "CHOOSE YOUR RACER", new Vector2(0, -80));

            var info = UIFactory.PanelBox(screen, new Color(0.12f, 0.09f, 0.26f, 0.82f), new Vector2(1, 0.5f), new Vector2(-330, 40), new Vector2(560, 560));
            var nameT = UIFactory.Text(info.transform, "", 80, UIFactory.Yellow, TextAnchor.MiddleCenter, new Vector2(0.5f, 1), new Vector2(0, -70), new Vector2(540, 100), 5f);
            var tagT = UIFactory.Text(info.transform, "", 30, Color.white, TextAnchor.MiddleCenter, new Vector2(0.5f, 1), new Vector2(0, -135), new Vector2(520, 50), 2f, false);
            var classT = UIFactory.Text(info.transform, "", 40, UIFactory.Orange, TextAnchor.MiddleCenter, new Vector2(0.5f, 1), new Vector2(0, -190), new Vector2(520, 60), 3f);
            var bars = new RectTransform[3];
            string[] labels = { "SPEED", "ACCEL", "TURN" };
            Color[] cols = { UIFactory.Red, UIFactory.Green, UIFactory.Blue };
            for (int i = 0; i < 3; i++)
            {
                UIFactory.Text(info.transform, labels[i], 36, Color.white, TextAnchor.MiddleLeft, new Vector2(0, 1), new Vector2(130, -275 - i * 85), new Vector2(200, 50), 2.5f);
                var bg = UIFactory.Image(info.transform, UIFactory.Bar, new Color(0, 0, 0, 0.45f), new Vector2(0, 1), new Vector2(370, -275 - i * 85), new Vector2(300, 38), true);
                var fill = UIFactory.Image(bg.transform, UIFactory.Bar, cols[i], new Vector2(0, 0.5f), Vector2.zero, new Vector2(300, 38), true);
                fill.rectTransform.pivot = new Vector2(0, 0.5f);
                bars[i] = fill.rectTransform;
            }
            System.Action refresh = () =>
            {
                var ch = CharacterDef.All[charIdx];
                nameT.text = ch.Name; tagT.text = ch.Tagline.ToUpper(); classT.text = CharacterDef.ClassName(ch.Class) + " CLASS";
                var st = ch.Stats;
                float[] v = { st.SpeedRating, st.AccelRating, st.TurnRating };
                for (int i = 0; i < 3; i++) bars[i].sizeDelta = new Vector2(Mathf.Lerp(40, 300, v[i]), 38);
            };

            var cards = new List<Image>();
            for (int i = 0; i < CharacterDef.All.Length; i++)
            {
                int idx = i;
                var ch = CharacterDef.All[i];
                int col = i % 4, row = i / 4;
                var b = UIFactory.Button(screen, "", ch.Kart, new Vector2(0, 0.5f), new Vector2(170 + col * 205, 120 - row * 215), new Vector2(190, 200), () =>
                {
                    charIdx = idx; Settings.CharacterIndex = idx;
                    showroom.ShowCharacter(CharacterDef.All[idx]);
                    refresh();
                    for (int c = 0; c < cards.Count; c++) cards[c].transform.localScale = Vector3.one;
                    if (AudioManager.I != null) AudioManager.I.Play(Sfx.Confirm, 0.6f);
                });
                var face = UIFactory.Image(b.transform, UIFactory.Circle, ch.Fur, new Vector2(0.5f, 0.5f), new Vector2(0, 22), new Vector2(110, 110));
                UIFactory.Image(face.transform, UIFactory.Circle, ch.FurLight, new Vector2(0.5f, 0.5f), new Vector2(0, -16), new Vector2(54, 44));
                UIFactory.Text(b.transform, ch.Name, 34, Color.white, TextAnchor.MiddleCenter, new Vector2(0.5f, 0), new Vector2(0, 30), new Vector2(190, 50), 3f);
                cards.Add(b.GetComponent<Image>());
            }
            var sel = UIFactory.Rect("Selector", screen, new Vector2(0, 0.5f), new Vector2(0, 0.5f), Vector2.zero, new Vector2(230, 240));
            var selImg = sel.gameObject.AddComponent<Image>();
            selImg.sprite = UIFactory.Panel; selImg.type = Image.Type.Sliced; selImg.color = UIFactory.Yellow; selImg.raycastTarget = false;
            sel.SetAsFirstSibling();
            var follower = sel.gameObject.AddComponent<UISelector>();
            follower.Get = () => new Vector2(170 + (charIdx % 4) * 205, 120 - (charIdx / 4) * 215);
            refresh();

            UIFactory.Button(screen, "BACK", UIFactory.Hex("#5A6B8C"), new Vector2(0, 0), new Vector2(200, 90), new Vector2(300, 120), ShowMainMenu, 50);
            UIFactory.Button(screen, "NEXT", UIFactory.Orange, new Vector2(1, 0), new Vector2(-230, 90), new Vector2(380, 130), ShowTrackSelect, 64);
        }

        // ------------------------------------------------------------------ track select
        public void ShowTrackSelect()
        {
            EnsureShowroom();
            showroom.CamOffset = new Vector3(0f, 6f, -10f);
            showroom.LookOffset = new Vector3(0f, 4.5f, 6f);
            ClearScreen();
            backAction = ShowCharacterSelect;
            Title(screen, "CHOOSE A TRACK", new Vector2(0, -80));
            var cards = new List<RectTransform>();
            for (int i = 0; i < TrackDatabase.Ids.Length; i++)
            {
                int idx = i;
                var data = TrackDatabase.Load(TrackDatabase.Ids[i]);
                var th = TrackTheme.Get(data.theme);
                float x = (i - (TrackDatabase.Ids.Length - 1) * 0.5f) * 540f;
                var b = UIFactory.Button(screen, "", th.SkyTop, new Vector2(0.5f, 0.5f), new Vector2(x, 40), new Vector2(500, 560), () =>
                {
                    trackIdx = idx; Settings.TrackIndex = idx;
                    if (AudioManager.I != null) AudioManager.I.Play(Sfx.Confirm, 0.6f);
                });
                var splines = TrackBuilder.PreviewSplines(data, 2f);
                Vector2 mn, mx;
                var tex = TrackBuilder.MinimapFor(splines, out mn, out mx, 200);
                var map = UIFactory.Rect("Map", b.transform, new Vector2(0.5f, 1), new Vector2(0.5f, 1), new Vector2(0, -170), new Vector2(270, 270));
                var raw = map.gameObject.AddComponent<RawImage>(); raw.texture = tex; raw.raycastTarget = false;
                UIFactory.Text(b.transform, data.name, 50, Color.white, TextAnchor.MiddleCenter, new Vector2(0.5f, 0), new Vector2(0, 175), new Vector2(480, 70), 4f);
                float km = splines.Count > 0 ? splines[0].Length / 1000f : 0f;
                int secrets = 0;
                foreach (var rd in data.roads) if (rd.hidden) secrets++;
                UIFactory.Text(b.transform, (data.subtitle ?? "") + "\n" + km.ToString("0.0") + " KM" + (splines.Count > 1 ? "  -  " + (splines.Count - 1) + " ROUTES" : "") + (secrets > 0 ? "  -  " + secrets + " SECRET SHORTCUTS" : ""), 22, UIFactory.Cream, TextAnchor.MiddleCenter, new Vector2(0.5f, 0), new Vector2(0, 232), new Vector2(480, 56), 2f, false);
                for (int sIdx = 0; sIdx < 3; sIdx++)
                    UIFactory.Image(b.transform, UIFactory.Icon("Star"), sIdx < data.difficulty ? Color.white : new Color(0, 0, 0, 0.35f), new Vector2(0.5f, 0), new Vector2(-60 + sIdx * 60, 115), new Vector2(54, 54));
                float best = Settings.BestLap(data.id);
                int trophy = Settings.Trophy(data.id);
                string info = (best > 0 ? "BEST LAP " + RaceHUD.FormatTime(best) : "NEW TRACK") + (trophy > 0 ? "   BEST " + trophy + RaceHUD.Suffix(trophy) : "");
                UIFactory.Text(b.transform, info, 28, UIFactory.Cream, TextAnchor.MiddleCenter, new Vector2(0.5f, 0), new Vector2(0, 55), new Vector2(480, 40), 2f, false);
                cards.Add((RectTransform)b.transform);
            }
            var sel = UIFactory.Rect("Selector", screen, new Vector2(0.5f, 0.5f), new Vector2(0.5f, 0.5f), Vector2.zero, new Vector2(540, 600));
            var selImg = sel.gameObject.AddComponent<Image>();
            selImg.sprite = UIFactory.Panel; selImg.type = Image.Type.Sliced; selImg.color = UIFactory.Yellow; selImg.raycastTarget = false;
            sel.SetAsFirstSibling();
            var follower = sel.gameObject.AddComponent<UISelector>();
            follower.Get = () => new Vector2((trackIdx - (TrackDatabase.Ids.Length - 1) * 0.5f) * 540f, 40);

            // options: laps + CPU difficulty
            var lapsT = UIFactory.Text(screen, "", 46, Color.white, TextAnchor.MiddleCenter, new Vector2(0.5f, 0), new Vector2(-420, 100), new Vector2(300, 70), 3f);
            System.Action refreshLaps = () => lapsT.text = Settings.Laps + " LAPS";
            UIFactory.Button(screen, "-", UIFactory.Blue, new Vector2(0.5f, 0), new Vector2(-610, 100), new Vector2(100, 100), () => { Settings.Laps = Settings.Laps - 1; refreshLaps(); }, 60);
            UIFactory.Button(screen, "+", UIFactory.Blue, new Vector2(0.5f, 0), new Vector2(-230, 100), new Vector2(100, 100), () => { Settings.Laps = Settings.Laps + 1; refreshLaps(); }, 60);
            refreshLaps();
            var diffT = UIFactory.Text(screen, "", 46, Color.white, TextAnchor.MiddleCenter, new Vector2(0.5f, 0), new Vector2(150, 100), new Vector2(400, 70), 3f);
            System.Action refreshDiff = () => diffT.text = "CPU: " + Settings.DifficultyName(Settings.Difficulty);
            UIFactory.Button(screen, "<", UIFactory.Purple, new Vector2(0.5f, 0), new Vector2(-80, 100), new Vector2(100, 100), () => { Settings.Difficulty = (Settings.Difficulty + 2) % 3; refreshDiff(); }, 60);
            UIFactory.Button(screen, ">", UIFactory.Purple, new Vector2(0.5f, 0), new Vector2(380, 100), new Vector2(100, 100), () => { Settings.Difficulty = (Settings.Difficulty + 1) % 3; refreshDiff(); }, 60);
            refreshDiff();

            UIFactory.Button(screen, "BACK", UIFactory.Hex("#5A6B8C"), new Vector2(0, 0), new Vector2(200, 90), new Vector2(300, 120), ShowCharacterSelect, 50);
            UIFactory.Button(screen, "RACE!", UIFactory.Red, new Vector2(1, 0), new Vector2(-230, 90), new Vector2(380, 130), StartRace, 70);
        }

        // ------------------------------------------------------------------ race
        public void StartRace() { StartCoroutine(LoadRace()); }

        IEnumerator LoadRace()
        {
            ClearScreen();
            backAction = null;
            var bg = UIFactory.Stretch("Loading", screen);
            bg.offsetMin = new Vector2(-400, -400); bg.offsetMax = new Vector2(400, 400);
            bg.gameObject.AddComponent<Image>().color = UIFactory.Hex("#1B1530");
            var data = TrackDatabase.Load(TrackDatabase.Ids[trackIdx]);
            Title(screen, data.name, new Vector2(0, -420), 120).color = UIFactory.Yellow;
            UIFactory.Text(screen, "LOADING...", 60, Color.white, TextAnchor.MiddleCenter, new Vector2(0.5f, 0.5f), new Vector2(0, -60), new Vector2(800, 80), 4f);
            string[] tips =
            {
                "TIP: The exhaust smoke turns BLACK when your turbo is ready!",
                "TIP: Chain 3 turbos in one slide to keep your boost reserves!",
                "TIP: Letting go of the gas drains your turbo reserves.",
                "TIP: 10 fruit = higher top speed and JUICED weapons.",
                "TIP: Hop off ramp lips for a hang-time turbo on landing.",
            };
            UIFactory.Text(screen, tips[Random.Range(0, tips.Length)], 38, UIFactory.Cream, TextAnchor.MiddleCenter, new Vector2(0.5f, 0.5f), new Vector2(0, -180), new Vector2(1600, 60), 2.5f, false);
            yield return null;
            yield return null;
            if (world != null) Destroy(world);
            showroom = null;
            yield return null;
            Art.ClearCache();
            world = new GameObject("RaceWorld");
            ClearScreen();
            race = RaceManager.Create(world.transform, TrackDatabase.Ids[trackIdx], charIdx, Settings.Laps, Settings.Difficulty, canvas, screen);
            race.OnComplete = ShowResults;
            Physics.SyncTransforms();
        }

        public void Pause()
        {
            if (race == null || race.State == RaceState.Done) return;
            race.SetPaused(true);
            var o = OpenOverlay(0.65f);
            UIFactory.PanelBox(o, UIFactory.Hex("#2A1F55"), new Vector2(0.5f, 0.5f), Vector2.zero, new Vector2(700, 820));
            Title(o, "PAUSED", new Vector2(0, -200), 100);
            UIFactory.Button(o, "RESUME", UIFactory.Green, new Vector2(0.5f, 0.5f), new Vector2(0, 170), new Vector2(520, 130), Resume, 64);
            UIFactory.Button(o, "RESTART", UIFactory.Orange, new Vector2(0.5f, 0.5f), new Vector2(0, 20), new Vector2(520, 120), () => { race.SetPaused(false); StartRace(); }, 56);
            UIFactory.Button(o, "SETTINGS", UIFactory.Blue, new Vector2(0.5f, 0.5f), new Vector2(0, -125), new Vector2(520, 120), () => ShowSettings(Pause), 56);
            UIFactory.Button(o, "QUIT", UIFactory.Red, new Vector2(0.5f, 0.5f), new Vector2(0, -270), new Vector2(520, 120), () => { race.SetPaused(false); ShowMainMenu(); }, 56);
            backAction = Resume;
        }

        void Resume()
        {
            CloseOverlay();
            if (race != null) race.SetPaused(false);
            backAction = null;
        }

        void ShowResults(List<ResultRow> rows)
        {
            var o = OpenOverlay(0.55f);
            UIFactory.PanelBox(o, UIFactory.Hex("#2A1F55"), new Vector2(0.5f, 0.5f), new Vector2(-180, 20), new Vector2(1120, 930));
            Title(o, "RESULTS", new Vector2(-180, -110), 100);
            for (int i = 0; i < rows.Count; i++)
            {
                var r = rows[i];
                float y = 290 - i * 84;
                var rowBg = UIFactory.Image(o, UIFactory.Rounded, r.IsPlayer ? UIFactory.Orange : new Color(1, 1, 1, 0.12f), new Vector2(0.5f, 0.5f), new Vector2(-180, y), new Vector2(1000, 74), true);
                rowBg.gameObject.AddComponent<UISlideIn>().Delay = i * 0.07f;
                UIFactory.Text(rowBg.transform, (i + 1) + RaceHUD.Suffix(i + 1), 46, i == 0 ? UIFactory.Yellow : Color.white, TextAnchor.MiddleLeft, new Vector2(0, 0.5f), new Vector2(110, 0), new Vector2(160, 60), 3f);
                UIFactory.Image(rowBg.transform, UIFactory.Circle, r.Character.Kart, new Vector2(0, 0.5f), new Vector2(230, 0), new Vector2(52, 52));
                UIFactory.Text(rowBg.transform, r.Name + (r.IsPlayer ? "  (YOU)" : ""), 44, Color.white, TextAnchor.MiddleLeft, new Vector2(0, 0.5f), new Vector2(480, 0), new Vector2(440, 60), 3f);
                UIFactory.Text(rowBg.transform, (r.Estimated ? "~" : "") + RaceHUD.FormatTime(r.Time), 44, Color.white, TextAnchor.MiddleRight, new Vector2(1, 0.5f), new Vector2(-150, 0), new Vector2(260, 60), 3f);
            }
            int place = 1;
            foreach (var r in rows) if (r.IsPlayer) place = r.Place;
            var side = UIFactory.Rect("Side", o, new Vector2(1, 0.5f), new Vector2(1, 0.5f), new Vector2(-250, 120), new Vector2(420, 500));
            if (place <= 3)
            {
                var tr = UIFactory.Image(side, UIFactory.Icon("trophy"), place == 1 ? Color.white : place == 2 ? UIFactory.Hex("#DDE6F2") : UIFactory.Hex("#E8A15A"), new Vector2(0.5f, 0.5f), new Vector2(0, 110), new Vector2(240, 240));
                tr.gameObject.AddComponent<UIBob>();
            }
            UIFactory.Text(side, place + RaceHUD.Suffix(place) + " PLACE", 70, place <= 3 ? UIFactory.Yellow : Color.white, TextAnchor.MiddleCenter, new Vector2(0.5f, 0.5f), new Vector2(0, -50), new Vector2(420, 90), 5f);
            float bestLap = 0f;
            if (race != null) foreach (var t in race.PlayerLapTimes) if (bestLap <= 0f || t < bestLap) bestLap = t;
            if (bestLap > 0f)
                UIFactory.Text(side, "BEST LAP " + RaceHUD.FormatTime(bestLap), 38, UIFactory.Cream, TextAnchor.MiddleCenter, new Vector2(0.5f, 0.5f), new Vector2(0, -130), new Vector2(420, 60), 3f);

            UIFactory.Button(o, "RETRY", UIFactory.Orange, new Vector2(1, 0), new Vector2(-250, 380), new Vector2(400, 120), StartRace, 60);
            UIFactory.Button(o, "NEXT TRACK", UIFactory.Green, new Vector2(1, 0), new Vector2(-250, 240), new Vector2(400, 120), () =>
            {
                trackIdx = (trackIdx + 1) % TrackDatabase.Ids.Length; Settings.TrackIndex = trackIdx; StartRace();
            }, 48);
            UIFactory.Button(o, "MENU", UIFactory.Hex("#5A6B8C"), new Vector2(1, 0), new Vector2(-250, 100), new Vector2(400, 120), ShowMainMenu, 56);
            backAction = ShowMainMenu;
        }

        // ------------------------------------------------------------------ settings
        public void ShowSettings(System.Action onClose)
        {
            var o = OpenOverlay(0.7f);
            UIFactory.PanelBox(o, UIFactory.Hex("#2A1F55"), new Vector2(0.5f, 0.5f), Vector2.zero, new Vector2(1500, 960));
            Title(o, "SETTINGS", new Vector2(0, -95), 90);
            float y = 300;
            OptionRow(o, "AUTO GAS", new[] { "ON", "OFF" }, () => Settings.AutoGas ? 0 : 1, i => Settings.AutoGas = i == 0, ref y);
            OptionRow(o, "STEERING", new[] { "STICK", "BUTTONS", "TILT" }, () => (int)Settings.Steering, i => Settings.Steering = (SteerMode)i, ref y);
            OptionRow(o, "LAYOUT", new[] { "RIGHT HAND", "LEFT HAND" }, () => Settings.LeftHanded ? 1 : 0, i => Settings.LeftHanded = i == 1, ref y);
            OptionRow(o, "SENSITIVITY", new[] { "LOW", "NORMAL", "HIGH" }, () => Settings.Sensitivity < 0.85f ? 0 : Settings.Sensitivity > 1.15f ? 2 : 1,
                i => Settings.Sensitivity = i == 0 ? 0.75f : i == 2 ? 1.3f : 1f, ref y);
            OptionRow(o, "MUSIC", new[] { "OFF", "LOW", "HIGH" }, () => Settings.MusicVolume < 0.05f ? 0 : Settings.MusicVolume < 0.5f ? 1 : 2,
                i => { Settings.MusicVolume = i == 0 ? 0f : i == 1 ? 0.35f : 0.75f; if (AudioManager.I != null) AudioManager.I.SetMusicVolume(); }, ref y);
            OptionRow(o, "SOUND FX", new[] { "OFF", "LOW", "HIGH" }, () => Settings.SfxVolume < 0.05f ? 0 : Settings.SfxVolume < 0.6f ? 1 : 2,
                i => Settings.SfxVolume = i == 0 ? 0f : i == 1 ? 0.45f : 0.9f, ref y);
            OptionRow(o, "GRAPHICS", new[] { "FAST", "BALANCED", "PRETTY" }, () => Settings.Quality, i => { Settings.Quality = i; Settings.ApplyQuality(); }, ref y);
            OptionRow(o, "SHOW FPS", new[] { "OFF", "ON" }, () => Settings.ShowFps ? 1 : 0, i => Settings.ShowFps = i == 1, ref y);
            System.Action close = () =>
            {
                if (race != null) race.RebuildTouch();
                if (onClose != null) onClose(); else { CloseOverlay(); backAction = null; }
            };
            UIFactory.Button(o, "DONE", UIFactory.Orange, new Vector2(0.5f, 0.5f), new Vector2(0, -400), new Vector2(400, 110), close, 56);
            backAction = close;
        }

        void OptionRow(Transform parent, string label, string[] options, System.Func<int> get, System.Action<int> set, ref float y)
        {
            UIFactory.Text(parent, label, 44, Color.white, TextAnchor.MiddleLeft, new Vector2(0.5f, 0.5f), new Vector2(-470, y), new Vector2(420, 60), 3f).alignment = TextAnchor.MiddleLeft;
            var buttons = new List<Image>();
            float w = 260f, gap = 14f;
            float start = 160f - (options.Length - 1) * (w + gap) * 0.5f + 120f;
            for (int i = 0; i < options.Length; i++)
            {
                int idx = i;
                var b = UIFactory.Button(parent, options[i], UIFactory.Blue, new Vector2(0.5f, 0.5f), new Vector2(start + i * (w + gap), y), new Vector2(w, 76), null, 34);
                var img = b.GetComponent<Image>();
                buttons.Add(img);
                b.onClick.AddListener(() =>
                {
                    set(idx);
                    for (int k = 0; k < buttons.Count; k++) buttons[k].color = k == get() ? UIFactory.Orange : new Color(0.3f, 0.32f, 0.5f);
                });
            }
            for (int k = 0; k < buttons.Count; k++) buttons[k].color = k == get() ? UIFactory.Orange : new Color(0.3f, 0.32f, 0.5f);
            y -= 88f;
        }
    }

    // ---------------------------------------------------------------------- small UI animators
    public class UIBob : MonoBehaviour
    {
        Vector3 basePos; float phase;
        void Start() { basePos = transform.localPosition; phase = Random.value * 6f; }
        void Update()
        {
            float t = Time.unscaledTime + phase;
            transform.localPosition = basePos + new Vector3(0, Mathf.Sin(t * 1.6f) * 8f, 0);
            transform.localRotation = Quaternion.Euler(0, 0, Mathf.Sin(t * 1.1f) * 1.5f);
        }
    }

    public class UISelector : MonoBehaviour
    {
        public System.Func<Vector2> Get;
        void Update()
        {
            if (Get == null) return;
            var rt = (RectTransform)transform;
            rt.anchoredPosition = Vector2.Lerp(rt.anchoredPosition, Get(), Mathf.Clamp01(Time.unscaledDeltaTime * 14f));
            float p = 1f + Mathf.Sin(Time.unscaledTime * 5f) * 0.02f;
            rt.localScale = Vector3.one * p;
        }
    }

    public class UISlideIn : MonoBehaviour
    {
        public float Delay;
        float t; Vector2 target;
        void Start() { var rt = (RectTransform)transform; target = rt.anchoredPosition; rt.anchoredPosition = target + new Vector2(-1400, 0); }
        void Update()
        {
            t += Time.unscaledDeltaTime;
            var rt = (RectTransform)transform;
            float u = Mathf.Clamp01((t - Delay) / 0.35f);
            float e = 1f - Mathf.Pow(1f - u, 3f);
            rt.anchoredPosition = Vector2.LerpUnclamped(target + new Vector2(-1400, 0), target, e);
            if (u >= 1f) enabled = false;
        }
    }
}
