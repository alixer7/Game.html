using System.Collections.Generic;
using UnityEngine;
using UnityEngine.UI;

namespace TurboTribe
{
    /// <summary>
    /// Multi-touch racing controls built for thumbs.
    /// Left thumb: floating horizontal steer slider (or arrow buttons / tilt).
    /// Right thumb: big HOP button (hold = power-slide). While holding, ROLL the same thumb onto
    /// the BOOST button to fire a slide turbo (each roll-in = one L1 press), or tap BOOST with
    /// another finger. The BOOST button lights up when the turbo window is open.
    /// Raw touches are used (not EventSystem) so several fingers work reliably.
    /// </summary>
    [DefaultExecutionOrder(-60)]
    public class TouchControls : MonoBehaviour
    {
        // outputs (read by PlayerKartInput)
        public float Steer;
        public bool HopHeld, Gas, Brake;
        public bool HopPressed, BoostPressed, ItemPressed;   // edges, cleared by the reader

        public KartController Kart;   // for the boost-window glow
        public KartItems Items;

        enum Role { None, Steer, SteerLeft, SteerRight, Hop, Boost, Item, Brake, Gas }
        class Finger { public Role Role; public Vector2 Origin; public bool InBoost; public bool InHop; }
        readonly Dictionary<int, Finger> fingers = new Dictionary<int, Finger>();

        RectTransform root;
        Canvas canvas;
        RectTransform hopBtn, boostBtn, itemBtn, brakeBtn, gasBtn, leftBtn, rightBtn;
        Image hopImg, boostImg, itemImg, brakeImg, gasImg, leftImg, rightImg, boostGlow, itemIcon;
        RectTransform stickBase, stickKnob;
        CanvasGroup stickGroup;
        Text tiltHint;
        float stickRange = 125f;
        SteerMode mode;
        bool autoGas;

        static readonly Color HopCol = UIFactory.Hex("#FF8A1F");
        static readonly Color BoostCol = UIFactory.Hex("#E8302A");
        static readonly Color ItemCol = UIFactory.Hex("#8A4FFF");
        static readonly Color BrakeCol = UIFactory.Hex("#5A6B8C");
        static readonly Color GasCol = UIFactory.Hex("#3CC45A");
        static readonly Color SteerCol = UIFactory.Hex("#2E8BEF");

        public static TouchControls Create(RectTransform safe, Canvas canvas)
        {
            var rt = UIFactory.Stretch("TouchControls", safe);
            var tc = rt.gameObject.AddComponent<TouchControls>();
            tc.root = rt; tc.canvas = canvas;
            tc.Build();
            return tc;
        }

        void Build()
        {
            mode = Settings.Steering;
            autoGas = Settings.AutoGas;
            bool lefty = Settings.LeftHanded;
            Vector2 br = lefty ? new Vector2(0, 0) : new Vector2(1, 0);
            Vector2 bl = lefty ? new Vector2(1, 0) : new Vector2(0, 0);
            float sx = lefty ? -1f : 1f; // mirror x offsets for left-handed layout

            if (autoGas)
            {
                hopBtn = RoundButton("HOP", br, new Vector2(-215 * sx, 205), 260, HopCol, "hop", out hopImg);
                boostBtn = RoundButton("BOOST", br, new Vector2(-485 * sx, 150), 200, BoostCol, "boost", out boostImg);
                itemBtn = RoundButton("ITEM", br, new Vector2(-250 * sx, 470), 180, ItemCol, "item", out itemImg);
                brakeBtn = RoundButton("BRAKE", br, new Vector2(-470 * sx, 390), 130, BrakeCol, "brake", out brakeImg);
            }
            else
            {
                gasBtn = RoundButton("GAS", br, new Vector2(-165 * sx, 185), 240, GasCol, "gas", out gasImg);
                hopBtn = RoundButton("HOP", br, new Vector2(-420 * sx, 160), 220, HopCol, "hop", out hopImg);
                boostBtn = RoundButton("BOOST", br, new Vector2(-640 * sx, 135), 180, BoostCol, "boost", out boostImg);
                itemBtn = RoundButton("ITEM", br, new Vector2(-300 * sx, 420), 170, ItemCol, "item", out itemImg);
                brakeBtn = RoundButton("BRAKE", br, new Vector2(-110 * sx, 420), 130, BrakeCol, "brake", out brakeImg);
            }
            boostGlow = UIFactory.Image(boostBtn, UIFactory.Glow, new Color(1f, 0.85f, 0.2f, 0f), new Vector2(0.5f, 0.5f), Vector2.zero, boostBtn.sizeDelta * 1.9f);
            boostGlow.transform.SetAsFirstSibling();
            itemIcon = UIFactory.Image(itemBtn, null, Color.white, new Vector2(0.5f, 0.5f), new Vector2(0, 6), itemBtn.sizeDelta * 0.62f);
            itemIcon.preserveAspect = true;
            itemIcon.enabled = false;

            if (mode == SteerMode.Buttons)
            {
                leftBtn = RoundButton("", bl, new Vector2(175 * sx, 185), 230, SteerCol, "left", out leftImg);
                rightBtn = RoundButton("", bl, new Vector2(440 * sx, 185), 230, SteerCol, "right", out rightImg);
            }
            else if (mode == SteerMode.Stick)
            {
                var g = UIFactory.Rect("Stick", root, bl, bl, new Vector2(300 * sx, 190), new Vector2(360, 120));
                stickGroup = g.gameObject.AddComponent<CanvasGroup>();
                stickGroup.blocksRaycasts = false; stickGroup.interactable = false;
                stickBase = g;
                var bimg = g.gameObject.AddComponent<Image>();
                bimg.sprite = UIFactory.Rounded; bimg.type = Image.Type.Sliced; bimg.color = new Color(0.1f, 0.12f, 0.25f, 0.55f);
                bimg.raycastTarget = false;
                UIFactory.Image(g, UIFactory.Icon("left"), new Color(1, 1, 1, 0.45f), new Vector2(0, 0.5f), new Vector2(42, 0), new Vector2(54, 54));
                UIFactory.Image(g, UIFactory.Icon("right"), new Color(1, 1, 1, 0.45f), new Vector2(1, 0.5f), new Vector2(-42, 0), new Vector2(54, 54));
                stickKnob = UIFactory.Image(g, UIFactory.Circle, SteerCol, new Vector2(0.5f, 0.5f), Vector2.zero, new Vector2(140, 140)).rectTransform;
                stickGroup.alpha = 0.55f;
            }
            else
            {
                tiltHint = UIFactory.Text(root, "TILT TO STEER", 34, new Color(1, 1, 1, 0.6f), TextAnchor.MiddleCenter, bl, new Vector2(260 * sx, 120), new Vector2(400, 60), 2f);
            }
        }

        RectTransform RoundButton(string label, Vector2 anchor, Vector2 pos, float size, Color col, string icon, out Image img)
        {
            img = UIFactory.Image(root, UIFactory.Circle, col, anchor, pos, new Vector2(size, size));
            var ic = UIFactory.Image(img.transform, UIFactory.Icon(icon), Color.white, new Vector2(0.5f, 0.5f), new Vector2(0, string.IsNullOrEmpty(label) ? 0 : 12), new Vector2(size * 0.5f, size * 0.5f));
            ic.preserveAspect = true;
            if (!string.IsNullOrEmpty(label))
                UIFactory.Text(img.transform, label, Mathf.RoundToInt(size * 0.15f), Color.white, TextAnchor.MiddleCenter, new Vector2(0.5f, 0f), new Vector2(0, size * 0.2f), new Vector2(size, 40), 2.5f, false);
            img.color = new Color(col.r, col.g, col.b, 0.9f);
            return img.rectTransform;
        }

        // ------------------------------------------------------------------ hit testing
        bool InCircle(RectTransform rt, Vector2 screen, float grow = 1.12f)
        {
            if (rt == null || !rt.gameObject.activeInHierarchy) return false;
            Vector2 local;
            if (!RectTransformUtility.ScreenPointToLocalPointInRectangle(rt, screen, null, out local)) return false;
            float r = rt.rect.width * 0.5f * grow;
            return local.sqrMagnitude <= r * r;
        }

        float CanvasScale { get { return canvas != null ? canvas.scaleFactor : 1f; } }

        Role Classify(Vector2 p)
        {
            if (InCircle(boostBtn, p, 1.05f)) return Role.Boost;
            if (InCircle(hopBtn, p, 1.12f)) return Role.Hop;
            if (InCircle(itemBtn, p, 1.1f)) return Role.Item;
            if (InCircle(brakeBtn, p, 1.15f)) return Role.Brake;
            if (gasBtn != null && InCircle(gasBtn, p, 1.12f)) return Role.Gas;
            if (mode == SteerMode.Buttons)
            {
                if (InCircle(leftBtn, p, 1.2f)) return Role.SteerLeft;
                if (InCircle(rightBtn, p, 1.2f)) return Role.SteerRight;
                return Role.None;
            }
            bool leftSide = Settings.LeftHanded ? p.x > Screen.width * 0.55f : p.x < Screen.width * 0.45f;
            if (mode == SteerMode.Stick && leftSide && p.y < Screen.height * 0.78f) return Role.Steer;
            return Role.None;
        }

        void Update()
        {
            float dt = Time.unscaledDeltaTime;
            float steer = 0f; bool hop = false, gas = autoGas, brake = false;
            bool steerTouch = false, leftDown = false, rightDown = false;

            // gather pointers (touches + mouse for the editor)
            int count = Input.touchCount;
            for (int i = 0; i < count; i++)
            {
                var t = Input.GetTouch(i);
                Process(t.fingerId, t.position, t.phase == TouchPhase.Began, t.phase == TouchPhase.Ended || t.phase == TouchPhase.Canceled,
                    ref steer, ref hop, ref gas, ref brake, ref steerTouch, ref leftDown, ref rightDown);
            }
            if (count == 0 && Input.mousePresent)
            {
                bool down = Input.GetMouseButtonDown(0), held = Input.GetMouseButton(0), up = Input.GetMouseButtonUp(0);
                if (down || held || up)
                    Process(-1, Input.mousePosition, down, up, ref steer, ref hop, ref gas, ref brake, ref steerTouch, ref leftDown, ref rightDown);
            }

            if (mode == SteerMode.Buttons) steer = (rightDown ? 1f : 0f) - (leftDown ? 1f : 0f);
            else if (mode == SteerMode.Tilt)
            {
                float a = Input.acceleration.x * 2.4f * Settings.Sensitivity;
                if (Mathf.Abs(a) < 0.06f) a = 0;
                steer = Mathf.Clamp(a, -1f, 1f);
            }
            Steer = steer; HopHeld = hop; Gas = gas || hop; Brake = brake;

            // stick visuals idle state
            if (stickGroup != null && !steerTouch)
            {
                stickGroup.alpha = Mathf.MoveTowards(stickGroup.alpha, 0.45f, dt * 3f);
                stickKnob.anchoredPosition = Vector2.Lerp(stickKnob.anchoredPosition, Vector2.zero, dt * 18f);
            }
            UpdateVisuals(dt);
        }

        void Process(int id, Vector2 pos, bool began, bool ended, ref float steer, ref bool hop, ref bool gas, ref bool brake, ref bool steerTouch, ref bool leftDown, ref bool rightDown)
        {
            Finger f;
            if (began || !fingers.TryGetValue(id, out f))
            {
                if (!began) return; // touch that started on another UI element (e.g. pause)
                f = new Finger { Role = Classify(pos), Origin = pos };
                fingers[id] = f;
                switch (f.Role)
                {
                    case Role.Hop: HopPressed = true; f.InHop = true; break;
                    case Role.Boost: BoostPressed = true; f.InBoost = true; break;
                    case Role.Item: ItemPressed = true; break;
                    case Role.Steer:
                        if (stickBase != null)
                        {
                            Vector2 local;
                            RectTransformUtility.ScreenPointToLocalPointInRectangle((RectTransform)stickBase.parent, pos, null, out local);
                            stickBase.localPosition = local;
                        }
                        break;
                }
            }
            if (ended) { fingers.Remove(id); return; }

            switch (f.Role)
            {
                case Role.Steer:
                    {
                        steerTouch = true;
                        float scale = CanvasScale;
                        float dx = (pos.x - f.Origin.x) / scale;
                        float range = stickRange;
                        // drag the base along if the thumb runs past the edge
                        if (Mathf.Abs(dx) > range * 1.35f)
                        {
                            float excess = dx - Mathf.Sign(dx) * range * 1.35f;
                            f.Origin.x += excess * scale;
                            dx -= excess;
                            if (stickBase != null) stickBase.localPosition += new Vector3(excess, 0, 0);
                        }
                        float x = Mathf.Clamp(dx / range, -1f, 1f);
                        float dead = 0.06f;
                        x = Mathf.Abs(x) < dead ? 0f : Mathf.Sign(x) * (Mathf.Abs(x) - dead) / (1f - dead);
                        x = x * (0.65f + 0.35f * Mathf.Abs(x)) * Settings.Sensitivity; // fine control near the centre
                        steer = Mathf.Clamp(x, -1f, 1f);
                        if (stickKnob != null)
                        {
                            stickKnob.anchoredPosition = new Vector2(Mathf.Clamp(dx, -range, range), 0);
                            stickGroup.alpha = 1f;
                        }
                        break;
                    }
                case Role.SteerLeft: leftDown = true; break;
                case Role.SteerRight: rightDown = true; break;
                case Role.Gas:
                    gas = true;
                    // rolling from GAS onto HOP starts a hop (manual-gas layout)
                    if (InCircle(hopBtn, pos, 1.0f)) { f.Role = Role.Hop; HopPressed = true; f.InHop = true; hop = true; }
                    break;
                case Role.Hop:
                    {
                        hop = true;
                        // roll the held thumb onto BOOST = turbo press
                        bool inBoost = InCircle(boostBtn, pos, 1.2f);
                        if (inBoost && !f.InBoost) BoostPressed = true;
                        f.InBoost = inBoost;
                        break;
                    }
                case Role.Boost:
                    {
                        // a finger that started on BOOST and slides onto HOP becomes a hop finger
                        bool inHop = InCircle(hopBtn, pos, 1.0f);
                        if (inHop && !f.InHop) { f.Role = Role.Hop; HopPressed = true; hop = true; f.InBoost = false; }
                        f.InHop = inHop;
                        break;
                    }
                case Role.Brake: brake = true; break;
            }
        }

        void UpdateVisuals(float dt)
        {
            Press(hopImg, HopHeld);
            bool boosting = false;
            foreach (var kv in fingers) if (kv.Value.InBoost) boosting = true;
            Press(boostImg, boosting);
            Press(brakeImg, Brake);
            if (gasImg != null) Press(gasImg, Gas);
            if (leftImg != null) Press(leftImg, Steer < -0.1f);
            if (rightImg != null) Press(rightImg, Steer > 0.1f);

            // boost window cue: glow ramps up through the good zone, pulses in the perfect zone
            float glowA = 0f; Color gc = new Color(1f, 0.85f, 0.2f);
            if (Kart != null && Kart.Sliding && Kart.SlideBoosts < 3 && !Kart.Backfiring)
            {
                // the button only lights up INSIDE the single turbo window (a faint build-up just before it)
                float g = Kart.SlideGauge;
                if (Kart.InTurboZone) { gc = new Color(1f, 0.35f, 0.15f); glowA = 0.8f + Mathf.Sin(Time.unscaledTime * 40f) * 0.2f; }
                else if (g < Kart.ZoneMin && g > Kart.ZoneMin - 0.15f) glowA = (g - (Kart.ZoneMin - 0.15f)) / 0.15f * 0.3f;
            }
            boostGlow.color = new Color(gc.r, gc.g, gc.b, Mathf.MoveTowards(boostGlow.color.a, glowA, dt * 8f));
            boostGlow.rectTransform.localScale = Vector3.one * (0.9f + glowA * 0.25f);

            if (Items != null)
            {
                ItemType t = Items.Rolling ? Items.RollShow : Items.Held;
                itemIcon.enabled = t != ItemType.None;
                if (itemIcon.enabled) itemIcon.sprite = UIFactory.ItemIcon(t);
                itemImg.color = new Color(ItemCol.r, ItemCol.g, ItemCol.b, Items.Held != ItemType.None && !Items.Rolling ? 0.95f : 0.45f);
            }
        }

        static void Press(Image img, bool on)
        {
            if (img == null) return;
            var t = img.rectTransform;
            float target = on ? 0.88f : 1f;
            t.localScale = Vector3.one * Mathf.Lerp(t.localScale.x, target, 0.4f);
            var c = img.color; c.a = on ? 1f : 0.82f; img.color = c;
        }

        public void ClearEdges() { HopPressed = BoostPressed = ItemPressed = false; }

        void OnDisable() { fingers.Clear(); Steer = 0; HopHeld = Gas = Brake = false; ClearEdges(); }
    }

    /// <summary>Feeds touch + keyboard/gamepad into the player's kart.</summary>
    [DefaultExecutionOrder(-50)]
    public class PlayerKartInput : MonoBehaviour
    {
        public KartController Kart;
        public TouchControls Touch;
        public bool Autopilot;  // after finishing, the AI drives

        void Update()
        {
            if (Kart == null || Autopilot) return;
            float steer = 0f; bool gas = Settings.AutoGas, brake = false, hop = false;
            bool hopP = false, boostP = false, itemP = false;
            if (Touch != null && Touch.isActiveAndEnabled)
            {
                steer = Touch.Steer; gas |= Touch.Gas; brake = Touch.Brake; hop = Touch.HopHeld;
                hopP = Touch.HopPressed; boostP = Touch.BoostPressed; itemP = Touch.ItemPressed;
                Touch.ClearEdges();
            }
            // keyboard (editor / Chromebook / Bluetooth keyboards)
            float kb = 0f;
            if (Input.GetKey(KeyCode.LeftArrow) || Input.GetKey(KeyCode.A)) kb -= 1f;
            if (Input.GetKey(KeyCode.RightArrow) || Input.GetKey(KeyCode.D)) kb += 1f;
            if (kb != 0f) steer = kb;
            if (Input.GetKey(KeyCode.UpArrow) || Input.GetKey(KeyCode.W)) gas = true;
            if (Input.GetKey(KeyCode.DownArrow) || Input.GetKey(KeyCode.S)) brake = true;
            if (Input.GetKey(KeyCode.Space) || Input.GetKey(KeyCode.J)) hop = true;
            if (Input.GetKeyDown(KeyCode.Space) || Input.GetKeyDown(KeyCode.J)) hopP = true;
            if (Input.GetKeyDown(KeyCode.LeftShift) || Input.GetKeyDown(KeyCode.K) || Input.GetKeyDown(KeyCode.E)) boostP = true;
            if (Input.GetKeyDown(KeyCode.LeftControl) || Input.GetKeyDown(KeyCode.L) || Input.GetKeyDown(KeyCode.Q)) itemP = true;

            Kart.Input.Steer = steer;
            Kart.Input.Gas = gas || hop;
            Kart.Input.Brake = brake;
            Kart.Input.HopHeld = hop;
            if (hopP) Kart.Input.HopPressed = true;
            if (boostP) Kart.Input.BoostPressed = true;
            if (itemP) Kart.Input.ItemPressed = true;
        }
    }
}
