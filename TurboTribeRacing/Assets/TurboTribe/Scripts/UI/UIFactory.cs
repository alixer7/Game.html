using System.Collections.Generic;
using UnityEngine;
using UnityEngine.EventSystems;
using UnityEngine.UI;

namespace TurboTribe
{
    /// <summary>
    /// Builds the chunky cartoon UI (thick outlines, glossy gradients, bold font) entirely from code.
    /// </summary>
    public static class UIFactory
    {
        static Font font;
        static Sprite rounded, circle, glow, panelSprite, bar;
        static readonly Dictionary<string, Sprite> icons = new Dictionary<string, Sprite>();

        public static readonly Color Orange = Hex("#FF8A1F");
        public static readonly Color Yellow = Hex("#FFD23F");
        public static readonly Color Red = Hex("#F2382B");
        public static readonly Color Blue = Hex("#2E8BEF");
        public static readonly Color Green = Hex("#3CC45A");
        public static readonly Color Purple = Hex("#8A4FFF");
        public static readonly Color Dark = Hex("#1B1530");
        public static readonly Color Cream = Hex("#FFF4DC");

        public static Color Hex(string h) { Color c; ColorUtility.TryParseHtmlString(h, out c); return c; }

        public static Font Font
        {
            get
            {
                if (font == null) font = Resources.Load<Font>("TurboTribe/Fonts/LuckiestGuy");
                if (font == null) font = Resources.GetBuiltinResource<Font>("LegacyRuntime.ttf");
                return font;
            }
        }

        // ------------------------------------------------------------ sprites
        public static Sprite Rounded
        {
            get
            {
                if (rounded != null) return rounded;
                int s = 128; float r = 40, ow = 7;
                var p = new Painter(s, s);
                Color outline = new Color(0.08f, 0.06f, 0.14f, 1f);
                p.Fill((x, y) => Painter.SdRoundBox(x, y, s / 2f, s / 2f, s / 2f - 1, s / 2f - 1, r), outline);
                p.Fill((x, y) => Painter.SdRoundBox(x, y, s / 2f, s / 2f, s / 2f - 1 - ow, s / 2f - 1 - ow, r - ow),
                    (x, y) => { float t = y / s; float v = Mathf.Lerp(0.78f, 1f, t); return new Color(v, v, v, 1); });
                // glossy highlight on the upper half
                p.Fill((x, y) => Painter.SdRoundBox(x, y, s / 2f, s * 0.74f, s / 2f - ow - 8, s * 0.12f, 16), new Color(1, 1, 1, 0.35f));
                rounded = p.ToSprite("rounded", new Vector4(48, 48, 48, 48));
                return rounded;
            }
        }

        public static Sprite Panel
        {
            get
            {
                if (panelSprite != null) return panelSprite;
                int s = 128; float r = 36, ow = 6;
                var p = new Painter(s, s);
                p.Fill((x, y) => Painter.SdRoundBox(x, y, s / 2f, s / 2f, s / 2f - 1, s / 2f - 1, r), new Color(0.08f, 0.06f, 0.14f, 1f));
                p.Fill((x, y) => Painter.SdRoundBox(x, y, s / 2f, s / 2f, s / 2f - 1 - ow, s / 2f - 1 - ow, r - ow), Color.white);
                panelSprite = p.ToSprite("panel", new Vector4(44, 44, 44, 44));
                return panelSprite;
            }
        }

        public static Sprite Circle
        {
            get
            {
                if (circle != null) return circle;
                int s = 160; float ow = 8;
                var p = new Painter(s, s);
                p.Fill((x, y) => Painter.SdCircle(x, y, s / 2f, s / 2f, s / 2f - 1), new Color(0.08f, 0.06f, 0.14f, 1f));
                p.Fill((x, y) => Painter.SdCircle(x, y, s / 2f, s / 2f, s / 2f - 1 - ow),
                    (x, y) => { float t = y / s; float v = Mathf.Lerp(0.74f, 1f, t); return new Color(v, v, v, 1); });
                p.Fill((x, y) => Painter.SdRoundBox(x, y, s / 2f, s * 0.7f, s * 0.26f, s * 0.1f, 14), new Color(1, 1, 1, 0.35f));
                circle = p.ToSprite("circle", Vector4.zero);
                return circle;
            }
        }

        public static Sprite Glow
        {
            get
            {
                if (glow != null) return glow;
                int s = 64;
                var p = new Painter(s, s);
                for (int y = 0; y < s; y++)
                    for (int x = 0; x < s; x++)
                    {
                        float d = Vector2.Distance(new Vector2(x + 0.5f, y + 0.5f), new Vector2(s / 2f, s / 2f)) / (s / 2f);
                        float a = Mathf.Clamp01(1 - d); a *= a;
                        p.Px[y * s + x] = new Color(1, 1, 1, a);
                    }
                glow = p.ToSprite("glow", Vector4.zero);
                return glow;
            }
        }

        public static Sprite Bar
        {
            get
            {
                if (bar != null) return bar;
                int w = 64, h = 32;
                var p = new Painter(w, h);
                p.Fill((x, y) => Painter.SdRoundBox(x, y, w / 2f, h / 2f, w / 2f - 1, h / 2f - 1, 14), Color.white);
                bar = p.ToSprite("bar", new Vector4(16, 15, 16, 15));
                return bar;
            }
        }

        // ------------------------------------------------------------ icons
        public static Sprite Icon(string name)
        {
            Sprite sp;
            if (icons.TryGetValue(name, out sp)) return sp;
            int s = 128;
            var p = new Painter(s, s);
            Color w = Color.white, k = new Color(0.08f, 0.06f, 0.14f, 1);
            switch (name)
            {
                case "left":
                case "right":
                    {
                        float dir = name == "left" ? -1 : 1;
                        var tri = new[] { new Vector2(64 + dir * 40, 64), new Vector2(64 - dir * 26, 104), new Vector2(64 - dir * 26, 24) };
                        p.Fill((x, y) => Painter.SdPoly(x, y, tri) - 8, k);
                        p.Fill((x, y) => Painter.SdPoly(x, y, tri) - 2, w);
                        break;
                    }
                case "hop":
                    {
                        // drift icon: two curved speed lines + a jump arrow
                        var tri = new[] { new Vector2(64, 108), new Vector2(98, 66), new Vector2(30, 66) };
                        p.Fill((x, y) => Mathf.Min(Painter.SdPoly(x, y, tri), Painter.SdRoundBox(x, y, 64, 46, 14, 22, 6)) - 7, k);
                        p.Fill((x, y) => Mathf.Min(Painter.SdPoly(x, y, tri), Painter.SdRoundBox(x, y, 64, 46, 14, 22, 6)) - 1, w);
                        p.Fill((x, y) => Painter.SdRoundBox(x, y, 64, 16, 44, 7, 7), w);
                        break;
                    }
                case "boost":
                    {
                        // flame
                        System.Func<float, float, float> flame = (x, y) =>
                            Mathf.Min(Painter.SdCircle(x, y, 64, 48, 30), Painter.SdPoly(x, y, new[] { new Vector2(64, 118), new Vector2(92, 52), new Vector2(36, 52) }));
                        p.Fill((x, y) => flame(x, y) - 7, k);
                        p.Fill((x, y) => flame(x, y), w);
                        p.Fill((x, y) => Mathf.Min(Painter.SdCircle(x, y, 64, 44, 14), Painter.SdPoly(x, y, new[] { new Vector2(64, 82), new Vector2(76, 46), new Vector2(52, 46) })), new Color(1, 0.8f, 0.3f, 1));
                        break;
                    }
                case "item":
                    p.Fill((x, y) => Painter.SdRoundBox(x, y, 64, 64, 42, 42, 10) - 6, k);
                    p.Fill((x, y) => Painter.SdRoundBox(x, y, 64, 64, 40, 40, 8), w);
                    DrawQuestion(p, k);
                    break;
                case "brake":
                    {
                        var tri = new[] { new Vector2(64, 22), new Vector2(104, 72), new Vector2(24, 72) };
                        p.Fill((x, y) => Mathf.Min(Painter.SdPoly(x, y, tri), Painter.SdRoundBox(x, y, 64, 90, 16, 18, 4)) - 7, k);
                        p.Fill((x, y) => Mathf.Min(Painter.SdPoly(x, y, tri), Painter.SdRoundBox(x, y, 64, 90, 16, 18, 4)) - 1, w);
                        break;
                    }
                case "gas":
                    for (int i = 0; i < 2; i++)
                    {
                        float oy = i * 30;
                        var chev = new[] { new Vector2(64, 92 + oy - 30), new Vector2(104, 52 + oy - 30), new Vector2(104, 30 + oy - 30), new Vector2(64, 70 + oy - 30), new Vector2(24, 30 + oy - 30), new Vector2(24, 52 + oy - 30) };
                        p.Fill((x, y) => Painter.SdPoly(x, y, chev) - 6, k);
                        p.Fill((x, y) => Painter.SdPoly(x, y, chev), w);
                    }
                    break;
                case "pause":
                    p.Fill((x, y) => Mathf.Min(Painter.SdRoundBox(x, y, 44, 64, 14, 40, 5), Painter.SdRoundBox(x, y, 84, 64, 14, 40, 5)) - 6, k);
                    p.Fill((x, y) => Mathf.Min(Painter.SdRoundBox(x, y, 44, 64, 14, 40, 5), Painter.SdRoundBox(x, y, 84, 64, 14, 40, 5)), w);
                    break;
                case "fruit":
                    p.Fill((x, y) => Painter.SdCircle(x, y, 64, 56, 44), k);
                    p.Fill((x, y) => Painter.SdCircle(x, y, 64, 56, 38), (x, y) => Color.Lerp(Hex("#FF4A1A"), Hex("#FFC23A"), y / 100f));
                    p.Fill((x, y) => Painter.SdCircle(x, y, 50, 72, 10), new Color(1, 1, 1, 0.55f));
                    p.Fill((x, y) => Painter.SdSegment(x, y, 64, 96, 70, 114, 5), Hex("#5A3A1E"));
                    p.Fill((x, y) => Painter.SdRoundBox(x, y, 86, 108, 16, 7, 7), Hex("#3FBF3A"));
                    break;
                case "Turbo":
                    {
                        System.Func<float, float, float> flame = (x, y) =>
                            Mathf.Min(Painter.SdCircle(x, y, 64, 46, 32), Painter.SdPoly(x, y, new[] { new Vector2(64, 122), new Vector2(96, 50), new Vector2(32, 50) }));
                        p.Fill((x, y) => flame(x, y) - 6, k);
                        p.Fill((x, y) => flame(x, y), (x, y) => Color.Lerp(Hex("#FF3D1A"), Hex("#FFB21A"), y / 110f));
                        p.Fill((x, y) => Mathf.Min(Painter.SdCircle(x, y, 64, 42, 16), Painter.SdPoly(x, y, new[] { new Vector2(64, 86), new Vector2(80, 44), new Vector2(48, 44) })), Hex("#FFF27A"));
                        break;
                    }
                case "Bomb":
                    p.Fill((x, y) => Painter.SdCircle(x, y, 60, 54, 42), k);
                    p.Fill((x, y) => Painter.SdCircle(x, y, 60, 54, 36), (x, y) => Color.Lerp(Hex("#1A1A24"), Hex("#4A4A5E"), y / 100f));
                    p.Fill((x, y) => Painter.SdCircle(x, y, 46, 68, 9), new Color(1, 1, 1, 0.5f));
                    p.Fill((x, y) => Painter.SdRoundBox(x, y, 82, 92, 10, 8, 3), Hex("#9A9AA8"));
                    p.Fill((x, y) => Painter.SdSegment(x, y, 86, 100, 98, 114, 4), Hex("#C9A06A"));
                    p.Fill((x, y) => Painter.SdCircle(x, y, 100, 116, 9), Hex("#FFD23F"));
                    break;
                case "Missile":
                    {
                        p.Fill((x, y) => Painter.SdSegment(x, y, 30, 30, 92, 92, 16) - 5, k);
                        p.Fill((x, y) => Painter.SdSegment(x, y, 30, 30, 92, 92, 16), Hex("#E8302A"));
                        p.Fill((x, y) => Painter.SdPoly(x, y, new[] { new Vector2(84, 100), new Vector2(112, 112), new Vector2(100, 84) }), Hex("#F2F2F2"));
                        p.Fill((x, y) => Painter.SdPoly(x, y, new[] { new Vector2(18, 50), new Vector2(40, 40), new Vector2(30, 20) }), Hex("#FFD23F"));
                        p.Fill((x, y) => Painter.SdPoly(x, y, new[] { new Vector2(50, 18), new Vector2(40, 40), new Vector2(20, 30) }), Hex("#FFD23F"));
                        p.Fill((x, y) => Painter.SdCircle(x, y, 60, 62, 7), Hex("#9EE7FF"));
                        break;
                    }
                case "BoomCrate":
                    p.Fill((x, y) => Painter.SdRoundBox(x, y, 64, 60, 44, 44, 8) - 5, k);
                    p.Fill((x, y) => Painter.SdRoundBox(x, y, 64, 60, 42, 42, 6), (x, y) => Color.Lerp(Hex("#B81E14"), Hex("#F2382B"), y / 110f));
                    p.Fill((x, y) => Painter.SdSegment(x, y, 30, 26, 98, 94, 6), new Color(0, 0, 0, 0.55f));
                    p.Fill((x, y) => Painter.SdSegment(x, y, 30, 94, 98, 26, 6), new Color(0, 0, 0, 0.55f));
                    p.Fill((x, y) => Painter.SdRoundBox(x, y, 64, 60, 14, 14, 4), Hex("#FFD23F"));
                    break;
                case "Shield":
                    p.Fill((x, y) => Painter.SdCircle(x, y, 64, 64, 50), k);
                    p.Fill((x, y) => Painter.SdCircle(x, y, 64, 64, 44), (x, y) => Color.Lerp(Hex("#1E7BFF"), Hex("#8FF3FF"), y / 120f));
                    p.Fill((x, y) => Painter.SdCircle(x, y, 48, 82, 12), new Color(1, 1, 1, 0.7f));
                    break;
                case "Star":
                    {
                        var pts = new Vector2[10];
                        for (int i = 0; i < 10; i++)
                        {
                            float a = Mathf.PI / 2 + i * Mathf.PI / 5;
                            float r = i % 2 == 0 ? 54 : 24;
                            pts[i] = new Vector2(64 + Mathf.Cos(a) * r, 62 + Mathf.Sin(a) * r);
                        }
                        p.Fill((x, y) => Painter.SdPoly(x, y, pts) - 6, k);
                        p.Fill((x, y) => Painter.SdPoly(x, y, pts), (x, y) => Color.Lerp(Hex("#FF9A1A"), Hex("#FFE95A"), y / 110f));
                        p.Fill((x, y) => Painter.SdCircle(x, y, 54, 72, 7), new Color(1, 1, 1, 0.7f));
                        break;
                    }
                case "trophy":
                    p.Fill((x, y) => Mathf.Min(Painter.SdRoundBox(x, y, 64, 78, 34, 30, 14), Mathf.Min(Painter.SdRoundBox(x, y, 64, 24, 30, 8, 4), Painter.SdRoundBox(x, y, 64, 42, 8, 14, 2))) - 5, k);
                    p.Fill((x, y) => Mathf.Min(Painter.SdRoundBox(x, y, 64, 78, 34, 30, 14), Mathf.Min(Painter.SdRoundBox(x, y, 64, 24, 30, 8, 4), Painter.SdRoundBox(x, y, 64, 42, 8, 14, 2))), Hex("#FFC93A"));
                    break;
                case "lock":
                    p.Fill((x, y) => Painter.SdRoundBox(x, y, 64, 50, 34, 28, 6), w);
                    p.Fill((x, y) => Mathf.Abs(Painter.SdCircle(x, y, 64, 82, 22)) - 7, w);
                    break;
                default:
                    p.Fill((x, y) => Painter.SdCircle(x, y, 64, 64, 40), w);
                    break;
            }
            sp = p.ToSprite("icon_" + name, Vector4.zero);
            icons[name] = sp;
            return sp;
        }

        static readonly string[] QGlyph = { ".###.", "#...#", "....#", "...#.", "..#..", ".....", "..#.." };
        static void DrawQuestion(Painter p, Color c)
        {
            for (int gy = 0; gy < 7; gy++)
                for (int gx = 0; gx < 5; gx++)
                    if (QGlyph[gy][gx] == '#')
                    {
                        float cx = 34 + gx * 15 + 7, cy = 104 - gy * 12 - 6;
                        p.Fill((x, y) => Painter.SdRoundBox(x, y, cx, cy, 7.5f, 6.5f, 2), c);
                    }
        }

        public static Sprite ItemIcon(ItemType t) { return t == ItemType.None ? null : Icon(t.ToString()); }

        // ------------------------------------------------------------ elements
        public static RectTransform Rect(string name, Transform parent, Vector2 anchorMin, Vector2 anchorMax, Vector2 pos, Vector2 size, Vector2? pivot = null)
        {
            var go = new GameObject(name, typeof(RectTransform));
            go.layer = 5;
            var rt = (RectTransform)go.transform;
            rt.SetParent(parent, false);
            rt.anchorMin = anchorMin; rt.anchorMax = anchorMax;
            rt.pivot = pivot ?? new Vector2(0.5f, 0.5f);
            rt.anchoredPosition = pos;
            rt.sizeDelta = size;
            return rt;
        }

        public static RectTransform Stretch(string name, Transform parent, float inset = 0)
        {
            var rt = Rect(name, parent, Vector2.zero, Vector2.one, Vector2.zero, Vector2.zero);
            rt.offsetMin = new Vector2(inset, inset); rt.offsetMax = new Vector2(-inset, -inset);
            return rt;
        }

        public static Image Image(Transform parent, Sprite sprite, Color color, Vector2 anchor, Vector2 pos, Vector2 size, bool sliced = false)
        {
            var rt = Rect("Image", parent, anchor, anchor, pos, size);
            var img = rt.gameObject.AddComponent<Image>();
            img.sprite = sprite; img.color = color;
            img.type = sliced ? UnityEngine.UI.Image.Type.Sliced : UnityEngine.UI.Image.Type.Simple;
            img.raycastTarget = false;
            return img;
        }

        public static Text Text(Transform parent, string text, int size, Color color, TextAnchor align, Vector2 anchor, Vector2 pos, Vector2 boxSize, float outline = 3f, bool shadow = true)
        {
            var rt = Rect("Text", parent, anchor, anchor, pos, boxSize);
            var t = rt.gameObject.AddComponent<Text>();
            t.font = Font; t.text = text; t.fontSize = size; t.color = color; t.alignment = align;
            t.horizontalOverflow = HorizontalWrapMode.Overflow; t.verticalOverflow = VerticalWrapMode.Overflow;
            t.raycastTarget = false;
            if (outline > 0)
            {
                var o = rt.gameObject.AddComponent<Outline>();
                o.effectColor = new Color(0.08f, 0.05f, 0.14f, 1f);
                o.effectDistance = new Vector2(outline, -outline);
            }
            if (shadow)
            {
                var sh = rt.gameObject.AddComponent<Shadow>();
                sh.effectColor = new Color(0.08f, 0.05f, 0.14f, 0.9f);
                sh.effectDistance = new Vector2(outline * 0.6f, -outline * 1.8f);
            }
            return t;
        }

        /// <summary>Glossy cartoon button with press bounce + click sound.</summary>
        public static Button Button(Transform parent, string label, Color color, Vector2 anchor, Vector2 pos, Vector2 size, System.Action onClick, int fontSize = 46, Sprite icon = null)
        {
            var rt = Rect("Button_" + label, parent, anchor, anchor, pos, size);
            var img = rt.gameObject.AddComponent<Image>();
            img.sprite = Rounded; img.type = UnityEngine.UI.Image.Type.Sliced; img.color = color;
            var b = rt.gameObject.AddComponent<Button>();
            b.transition = Selectable.Transition.None;
            b.onClick.AddListener(() => { if (AudioManager.I != null) AudioManager.I.Play(Sfx.Click); if (onClick != null) onClick(); });
            rt.gameObject.AddComponent<UIPressFX>();
            if (icon != null)
            {
                var ic = Image(rt, icon, Color.white, new Vector2(0, 0.5f), new Vector2(size.y * 0.55f, 4), new Vector2(size.y * 0.62f, size.y * 0.62f));
                ic.preserveAspect = true;
                Text(rt, label, fontSize, Color.white, TextAnchor.MiddleCenter, new Vector2(0.5f, 0.5f), new Vector2(size.y * 0.25f, 2), size, 3f);
            }
            else if (!string.IsNullOrEmpty(label)) Text(rt, label, fontSize, Color.white, TextAnchor.MiddleCenter, new Vector2(0.5f, 0.5f), new Vector2(0, 2), size, 3f);
            return b;
        }

        public static Image PanelBox(Transform parent, Color color, Vector2 anchor, Vector2 pos, Vector2 size)
        {
            var img = Image(parent, Panel, color, anchor, pos, size, true);
            return img;
        }

        /// <summary>Full-screen canvas with a safe-area child.</summary>
        public static Canvas CreateCanvas(string name, int order, out RectTransform safe)
        {
            var go = new GameObject(name, typeof(RectTransform));
            go.layer = 5;
            var c = go.AddComponent<Canvas>();
            c.renderMode = RenderMode.ScreenSpaceOverlay;
            c.sortingOrder = order;
            var cs = go.AddComponent<CanvasScaler>();
            cs.uiScaleMode = CanvasScaler.ScaleMode.ScaleWithScreenSize;
            cs.referenceResolution = new Vector2(1920, 1080);
            cs.screenMatchMode = CanvasScaler.ScreenMatchMode.MatchWidthOrHeight;
            cs.matchWidthOrHeight = 1f;
            go.AddComponent<GraphicRaycaster>();
            safe = Stretch("SafeArea", go.transform);
            safe.gameObject.AddComponent<SafeArea>();
            return c;
        }

        public static void EnsureEventSystem()
        {
            if (Object.FindFirstObjectByType<EventSystem>() != null) return;
            var es = new GameObject("EventSystem");
            es.AddComponent<EventSystem>();
            es.AddComponent<StandaloneInputModule>();
            Object.DontDestroyOnLoad(es);
        }
    }

    /// <summary>Keeps UI inside the device safe area (notches / rounded corners).</summary>
    public class SafeArea : MonoBehaviour
    {
        Rect last;
        void Update()
        {
            Rect sa = Screen.safeArea;
            if (sa == last || Screen.width <= 0) return;
            last = sa;
            var rt = (RectTransform)transform;
            Vector2 min = sa.position, max = sa.position + sa.size;
            min.x /= Screen.width; min.y /= Screen.height; max.x /= Screen.width; max.y /= Screen.height;
            rt.anchorMin = min; rt.anchorMax = max;
            rt.offsetMin = rt.offsetMax = Vector2.zero;
        }
    }

    /// <summary>Squishy press animation for buttons.</summary>
    public class UIPressFX : MonoBehaviour, IPointerDownHandler, IPointerUpHandler, IPointerExitHandler
    {
        float target = 1f, scale = 1f, vel;
        public void OnPointerDown(PointerEventData e) { target = 0.9f; }
        public void OnPointerUp(PointerEventData e) { target = 1f; vel += 4f; }
        public void OnPointerExit(PointerEventData e) { target = 1f; }
        void OnEnable() { scale = 1f; vel = 0; target = 1f; transform.localScale = Vector3.one; }
        void Update()
        {
            float dt = Time.unscaledDeltaTime;
            vel += ((target - scale) * 300f - vel * 18f) * dt;
            scale += vel * dt;
            transform.localScale = Vector3.one * scale;
        }
    }
}
