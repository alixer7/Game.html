using System.Collections.Generic;
using UnityEngine;
using UnityEngine.UI;

namespace TurboTribe
{
    /// <summary>In-race HUD: lap/time, position, item roulette, fruit, minimap, slide turbo gauge, pop-up messages.</summary>
    public class RaceHUD : MonoBehaviour
    {
        RaceManager race;
        RectTransform root;
        Text lapText, timeText, placeText, placeSuffix, fruitText, itemName, titleText, titleSub, fpsText;
        Image itemIcon, itemBox, fruitIcon, juicedGlow;
        RectTransform placeRT, itemRT, fruitRT, titleRT;
        RawImage minimap;
        readonly List<Image> mapDots = new List<Image>();
        // slide gauge
        CanvasGroup gaugeGroup;
        RectTransform gaugeFill, gaugeMarker, zoneRT;
        Image zoneImg, gaugeBg;
        Image[] pips = new Image[3];
        // messages
        Text msgText; RectTransform msgRT; float msgTimer, msgDur;
        Text countText; RectTransform countRT; float countTimer;
        int lastPlace;
        float placeBounce, itemBounce, fruitBounce;
        float fpsAcc; int fpsFrames;

        public static RaceHUD Create(RectTransform safe, RaceManager race)
        {
            var rt = UIFactory.Stretch("HUD", safe);
            var hud = rt.gameObject.AddComponent<RaceHUD>();
            hud.race = race; hud.root = rt;
            hud.Build();
            return hud;
        }

        void Build()
        {
            Vector2 tl = new Vector2(0, 1), tr = new Vector2(1, 1), tc = new Vector2(0.5f, 1);
            // lap + time panel
            var lapPanel = UIFactory.PanelBox(root, new Color(0.1f, 0.08f, 0.2f, 0.72f), tl, new Vector2(190, -78), new Vector2(330, 128));
            lapText = UIFactory.Text(lapPanel.transform, "LAP 1/3", 58, UIFactory.Yellow, TextAnchor.MiddleLeft, new Vector2(0, 0.5f), new Vector2(26, 20), new Vector2(300, 70), 3.5f);
            ((RectTransform)lapText.transform).pivot = new Vector2(0, 0.5f);
            timeText = UIFactory.Text(lapPanel.transform, "0:00.00", 38, Color.white, TextAnchor.MiddleLeft, new Vector2(0, 0.5f), new Vector2(26, -32), new Vector2(300, 50), 2.5f);
            ((RectTransform)timeText.transform).pivot = new Vector2(0, 0.5f);

            // fruit counter
            fruitRT = UIFactory.Rect("Fruit", root, tl, tl, new Vector2(120, -200), new Vector2(200, 90));
            juicedGlow = UIFactory.Image(fruitRT, UIFactory.Glow, new Color(1f, 0.85f, 0.2f, 0f), new Vector2(0.5f, 0.5f), new Vector2(-30, 0), new Vector2(200, 200));
            fruitIcon = UIFactory.Image(fruitRT, UIFactory.Icon("fruit"), Color.white, new Vector2(0, 0.5f), new Vector2(40, 0), new Vector2(86, 86));
            fruitText = UIFactory.Text(fruitRT, "x 0", 54, Color.white, TextAnchor.MiddleLeft, new Vector2(0, 0.5f), new Vector2(170, 0), new Vector2(180, 70), 3.5f);

            // item slot
            itemRT = UIFactory.Rect("ItemSlot", root, tc, tc, new Vector2(0, -100), new Vector2(170, 170));
            itemBox = itemRT.gameObject.AddComponent<Image>();
            itemBox.sprite = UIFactory.Rounded; itemBox.type = Image.Type.Sliced; itemBox.color = new Color(0.25f, 0.2f, 0.45f, 0.85f);
            itemBox.raycastTarget = false;
            itemIcon = UIFactory.Image(itemRT, null, Color.white, new Vector2(0.5f, 0.5f), Vector2.zero, new Vector2(124, 124));
            itemIcon.preserveAspect = true; itemIcon.enabled = false;
            itemName = UIFactory.Text(itemRT, "", 30, Color.white, TextAnchor.UpperCenter, new Vector2(0.5f, 0f), new Vector2(0, -26), new Vector2(400, 40), 2.5f);

            // position
            placeRT = UIFactory.Rect("Place", root, tr, tr, new Vector2(-150, -100), new Vector2(240, 170));
            placeText = UIFactory.Text(placeRT, "1", 160, UIFactory.Yellow, TextAnchor.MiddleRight, new Vector2(0.5f, 0.5f), new Vector2(-10, 0), new Vector2(160, 170), 6f);
            placeSuffix = UIFactory.Text(placeRT, "ST", 56, UIFactory.Yellow, TextAnchor.UpperLeft, new Vector2(0.5f, 0.5f), new Vector2(110, 26), new Vector2(120, 70), 4f);

            // pause button
            var pause = UIFactory.Button(root, "", UIFactory.Hex("#5A6B8C"), tc, new Vector2(-170, -70), new Vector2(96, 96), () => { if (GameManager.I != null) GameManager.I.Pause(); }, 10, null);
            UIFactory.Image(pause.transform, UIFactory.Icon("pause"), Color.white, new Vector2(0.5f, 0.5f), Vector2.zero, new Vector2(60, 60));

            // minimap
            var mapRT = UIFactory.Rect("Minimap", root, new Vector2(1, 0.5f), new Vector2(1, 0.5f), new Vector2(-150, 120), new Vector2(250, 250));
            minimap = mapRT.gameObject.AddComponent<RawImage>();
            minimap.texture = race.Track.Minimap;
            minimap.color = new Color(1, 1, 1, 0.85f);
            minimap.raycastTarget = false;
            foreach (var k in race.Karts)
            {
                var dot = UIFactory.Image(mapRT, UIFactory.Circle, k.Character.Kart, new Vector2(0, 0), Vector2.zero, k == race.Player ? new Vector2(30, 30) : new Vector2(20, 20));
                mapDots.Add(dot);
            }
            if (mapDots.Count > 0) mapDots[race.Karts.IndexOf(race.Player)].transform.SetAsLastSibling();

            // slide gauge
            var g = UIFactory.Rect("SlideGauge", root, new Vector2(0.5f, 0), new Vector2(0.5f, 0), new Vector2(-40, 300), new Vector2(460, 64));
            gaugeGroup = g.gameObject.AddComponent<CanvasGroup>();
            gaugeGroup.alpha = 0f;
            var bg = g.gameObject.AddComponent<Image>(); bg.sprite = UIFactory.Rounded; bg.type = Image.Type.Sliced; bg.color = new Color(0.1f, 0.08f, 0.2f, 0.85f); bg.raycastTarget = false;
            gaugeBg = bg;
            var track = UIFactory.Rect("Track", g, new Vector2(0, 0.5f), new Vector2(0, 0.5f), new Vector2(20, 0), new Vector2(420, 26), new Vector2(0, 0.5f));
            // ONE turbo window (moves / narrows for each boost); everything else is dead grey
            Zone(track, 0f, 1f, new Color(0.38f, 0.38f, 0.48f));
            zoneImg = Zone(track, KartController.ZoneCentre - 0.085f, KartController.ZoneCentre + 0.085f, UIFactory.Green);
            zoneRT = zoneImg.rectTransform;
            gaugeFill = UIFactory.Rect("Fill", track, new Vector2(0, 0), new Vector2(0, 1), Vector2.zero, new Vector2(0, 0), new Vector2(0, 0.5f));
            var fimg = gaugeFill.gameObject.AddComponent<Image>(); fimg.color = new Color(1, 1, 1, 0.35f); fimg.raycastTarget = false;
            gaugeMarker = UIFactory.Image(track, UIFactory.Bar, Color.white, new Vector2(0, 0.5f), Vector2.zero, new Vector2(14, 52)).rectTransform;
            for (int i = 0; i < 3; i++)
                pips[i] = UIFactory.Image(g, UIFactory.Circle, new Color(0.3f, 0.3f, 0.4f), new Vector2(0.5f, 1f), new Vector2(-50 + i * 50, 30), new Vector2(40, 40));

            // centre messages
            msgRT = UIFactory.Rect("Msg", root, new Vector2(0.5f, 0.5f), new Vector2(0.5f, 0.5f), new Vector2(0, 170), new Vector2(1200, 160));
            msgText = UIFactory.Text(msgRT, "", 90, Color.white, TextAnchor.MiddleCenter, new Vector2(0.5f, 0.5f), Vector2.zero, new Vector2(1200, 160), 6f);
            countRT = UIFactory.Rect("Count", root, new Vector2(0.5f, 0.5f), new Vector2(0.5f, 0.5f), new Vector2(0, 60), new Vector2(600, 300));
            countText = UIFactory.Text(countRT, "", 230, UIFactory.Yellow, TextAnchor.MiddleCenter, new Vector2(0.5f, 0.5f), Vector2.zero, new Vector2(800, 300), 9f);

            // track title (intro)
            titleRT = UIFactory.Rect("Title", root, new Vector2(0.5f, 0.5f), new Vector2(0.5f, 0.5f), new Vector2(0, -260), new Vector2(1200, 220));
            titleText = UIFactory.Text(titleRT, "", 120, UIFactory.Yellow, TextAnchor.MiddleCenter, new Vector2(0.5f, 0.5f), new Vector2(0, 30), new Vector2(1400, 160), 7f);
            titleSub = UIFactory.Text(titleRT, "", 44, Color.white, TextAnchor.MiddleCenter, new Vector2(0.5f, 0.5f), new Vector2(0, -60), new Vector2(1400, 60), 3f);
            titleRT.gameObject.SetActive(false);

            fpsText = UIFactory.Text(root, "", 28, Color.white, TextAnchor.LowerLeft, new Vector2(0, 0), new Vector2(110, 30), new Vector2(200, 40), 2f, false);
            fpsText.gameObject.SetActive(Settings.ShowFps);
        }

        static Image Zone(RectTransform parent, float a, float b, Color c)
        {
            var z = UIFactory.Rect("Zone", parent, new Vector2(a, 0), new Vector2(b, 1), Vector2.zero, Vector2.zero);
            var img = z.gameObject.AddComponent<Image>(); img.color = c; img.raycastTarget = false;
            z.offsetMin = new Vector2(1, 0); z.offsetMax = new Vector2(-1, 0);
            return img;
        }

        // ------------------------------------------------------------------ API
        public void ShowTitle(string name, int difficulty)
        {
            titleRT.gameObject.SetActive(true);
            titleText.text = name;
            titleSub.text = (difficulty == 1 ? "EASY" : difficulty == 2 ? "MEDIUM" : "HARD") + "  -  " + race.Laps + " LAPS";
        }
        public void HideTitle() { titleRT.gameObject.SetActive(false); }

        public void Countdown(int n)
        {
            countTimer = 0.95f;
            countText.text = n > 0 ? n.ToString() : "GO!";
            countText.color = n == 3 ? UIFactory.Red : n == 2 ? UIFactory.Orange : n == 1 ? UIFactory.Yellow : UIFactory.Green;
        }

        public void Message(string text, Color c, int size, float dur)
        {
            msgText.text = text; msgText.color = c; msgText.fontSize = size;
            msgTimer = dur; msgDur = dur;
        }

        public void SlideBoost(int lvl, bool perfect)
        {
            string t = lvl >= 3 ? "ULTRA TURBO!" : lvl == 2 ? "TURBO x2!" : "TURBO!";
            Message(t, lvl >= 3 ? UIFactory.Orange : UIFactory.Yellow, lvl >= 3 ? 86 : 72, 0.7f);
        }

        /// <summary>Timed lip jump feedback (quality = how close to the takeoff the jump was pressed).</summary>
        public void Launch(float q)
        {
            if (q >= KartController.LipPerfect) Message("PERFECT LAUNCH!", UIFactory.Orange, 84, 0.8f);
            else if (q >= 0.45f) Message("BIG AIR!", UIFactory.Yellow, 74, 0.7f);
        }

        /// <summary>Hang-time turbo on landing.</summary>
        public void AirBoost(float air, float dur)
        {
            if (dur < 0.45f) return;            // small crest hops pay a short turbo silently (the exhaust flame shows it)
            string t = air >= 1.0f ? "HANG TIME!" : "AIR TURBO";
            Message(t + "  +" + dur.ToString("0.0") + "s", air >= 1.0f ? UIFactory.Orange : UIFactory.Yellow, air >= 1.0f ? 80 : 66, 0.8f);
        }

        public void ItemReady(ItemType t) { itemBounce = 1f; itemName.text = ItemInfo.Name(t); }
        public void FruitBump() { fruitBounce = 1f; }

        public void Finish(int place)
        {
            countTimer = 3.5f;
            countText.text = "FINISH!";
            countText.color = place == 1 ? UIFactory.Yellow : Color.white;
            Message(place + Suffix(place) + " PLACE", place <= 3 ? UIFactory.Yellow : Color.white, 96, 4f);
            msgRT.anchoredPosition = new Vector2(0, -120);
        }

        public static string Suffix(int p) { return p == 1 ? "ST" : p == 2 ? "ND" : p == 3 ? "RD" : "TH"; }

        public static string FormatTime(float t)
        {
            int m = (int)(t / 60f); float s = t - m * 60;
            return m + ":" + s.ToString("00.00");
        }

        void Update()
        {
            float dt = Time.unscaledDeltaTime;
            var p = race.Player;
            if (p == null) return;
            int lap = Mathf.Clamp(p.Lap, 1, race.Laps);
            lapText.text = "LAP " + lap + "/" + race.Laps;
            timeText.text = FormatTime(race.State == RaceState.Intro || race.State == RaceState.Countdown ? 0f : (p.Finished ? p.FinishTime : race.RaceTime));

            // place
            if (p.Place != lastPlace) { placeBounce = 1f; lastPlace = p.Place; }
            placeText.text = p.Place.ToString();
            placeSuffix.text = Suffix(p.Place);
            Color pc = p.Place == 1 ? UIFactory.Yellow : p.Place == 2 ? UIFactory.Hex("#DDE6F2") : p.Place == 3 ? UIFactory.Hex("#E8A15A") : Color.white;
            placeText.color = pc; placeSuffix.color = pc;
            placeBounce = Mathf.MoveTowards(placeBounce, 0f, dt * 3f);
            placeRT.localScale = Vector3.one * (1f + Mathf.Sin(placeBounce * Mathf.PI) * 0.25f);

            // fruit
            fruitText.text = "x " + p.Fruit;
            fruitText.color = p.Fruit >= 10 ? UIFactory.Yellow : Color.white;
            fruitBounce = Mathf.MoveTowards(fruitBounce, 0f, dt * 4f);
            fruitIcon.rectTransform.localScale = Vector3.one * (1f + Mathf.Sin(fruitBounce * Mathf.PI) * 0.3f);
            juicedGlow.color = new Color(1f, 0.85f, 0.2f, p.Fruit >= 10 ? 0.55f + Mathf.Sin(Time.unscaledTime * 6f) * 0.2f : 0f);

            // item
            var items = p.GetComponent<KartItems>();
            if (items != null)
            {
                ItemType t = items.Rolling ? items.RollShow : items.Held;
                itemIcon.enabled = t != ItemType.None;
                if (t != ItemType.None) itemIcon.sprite = UIFactory.ItemIcon(t);
                if (items.Held == ItemType.None || items.Rolling) itemName.text = "";
                itemBox.color = items.Juiced && items.Held != ItemType.None ? UIFactory.Hex("#FFB21A") : new Color(0.25f, 0.2f, 0.45f, 0.85f);
            }
            itemBounce = Mathf.MoveTowards(itemBounce, 0f, dt * 3f);
            itemRT.localScale = Vector3.one * (1f + Mathf.Sin(itemBounce * Mathf.PI) * 0.3f);

            // minimap dots
            for (int i = 0; i < race.Karts.Count && i < mapDots.Count; i++)
            {
                var k = race.Karts[i];
                Vector2 uv = race.Track.MapUV(k.transform.position);
                var rt = mapDots[i].rectTransform;
                rt.anchorMin = rt.anchorMax = uv;
                rt.anchoredPosition = Vector2.zero;
            }

            // slide gauge: a single window per boost (narrower each time); stop the needle inside it
            bool show = p.Sliding && p.SlideBoosts < 3;
            gaugeGroup.alpha = Mathf.MoveTowards(gaugeGroup.alpha, p.Sliding ? 1f : 0f, dt * 6f);
            float gv = Mathf.Clamp01(p.SlideGauge);
            gaugeFill.anchorMax = new Vector2(gv, 1);
            gaugeFill.sizeDelta = Vector2.zero;
            gaugeMarker.anchorMin = gaugeMarker.anchorMax = new Vector2(gv, 0.5f);
            gaugeMarker.anchoredPosition = Vector2.zero;
            bool inZone = p.InTurboZone;
            gaugeMarker.localScale = Vector3.one * (inZone ? 1.25f + Mathf.Sin(Time.unscaledTime * 40f) * 0.1f : 1f);
            zoneRT.anchorMin = new Vector2(p.ZoneMin, 0); zoneRT.anchorMax = new Vector2(p.ZoneMax, 1);
            zoneRT.offsetMin = new Vector2(1, 0); zoneRT.offsetMax = new Vector2(-1, 0);
            zoneImg.color = p.Backfiring ? new Color(0.35f, 0.3f, 0.3f) : inZone ? Color.white : (p.SlideBoosts >= 2 ? UIFactory.Red : p.SlideBoosts == 1 ? UIFactory.Orange : UIFactory.Green);
            gaugeBg.color = p.Backfiring ? new Color(0.35f, 0.08f, 0.06f, 0.9f) : new Color(0.1f, 0.08f, 0.2f, 0.85f);
            for (int i = 0; i < 3; i++)
                pips[i].color = i < p.SlideBoosts ? (i == 2 ? UIFactory.Red : UIFactory.Orange) : new Color(0.3f, 0.3f, 0.4f);

            // messages
            if (msgTimer > 0f)
            {
                msgTimer -= dt;
                float u = 1f - msgTimer / msgDur;
                float sc = u < 0.15f ? Mathf.Lerp(0.3f, 1.15f, u / 0.15f) : u < 0.25f ? Mathf.Lerp(1.15f, 1f, (u - 0.15f) / 0.1f) : 1f;
                msgRT.localScale = Vector3.one * sc;
                var c = msgText.color; c.a = Mathf.Clamp01(msgTimer * 4f); msgText.color = c;
            }
            else msgText.text = "";
            if (countTimer > 0f)
            {
                countTimer -= dt;
                float u = Mathf.Clamp01(1f - countTimer / 0.95f);
                countRT.localScale = Vector3.one * (u < 0.2f ? Mathf.Lerp(2f, 1f, u / 0.2f) : 1f);
                var c = countText.color; c.a = Mathf.Clamp01(countTimer * 3f); countText.color = c;
            }
            else countText.text = "";

            if (Settings.ShowFps)
            {
                fpsAcc += dt; fpsFrames++;
                if (fpsAcc >= 0.5f) { fpsText.text = Mathf.RoundToInt(fpsFrames / fpsAcc) + " FPS"; fpsAcc = 0; fpsFrames = 0; }
            }
        }
    }
}
