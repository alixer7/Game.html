using System.Collections.Generic;
using UnityEngine;

namespace TurboTribe
{
    /// <summary>
    /// Central place for procedurally generated textures and shared materials.
    /// Nothing here depends on imported art assets.
    /// </summary>
    public static class Art
    {
        static Shader toon, sky, particle, water, foliage;
        static readonly Dictionary<string, Material> mats = new Dictionary<string, Material>();
        static readonly Dictionary<string, Texture2D> texs = new Dictionary<string, Texture2D>();

        public static Shader ToonShader { get { if (toon == null) toon = LoadShader("ToonVC", "TurboTribe/ToonVC"); return toon; } }

        static Shader LoadShader(string file, string name)
        {
            var s = Resources.Load<Shader>("TurboTribe/Shaders/" + file);
            if (s == null) s = Shader.Find(name);
            if (s == null) s = Shader.Find("Mobile/VertexLit");
            if (s == null) s = Shader.Find("Unlit/Texture");
            return s;
        }

        public static void ClearCache()
        {
            foreach (var m in mats.Values) if (m != null) Object.Destroy(m);
            mats.Clear();
        }

        // ---------------------------------------------------------------- materials
        public static Material Toon(string key, Texture2D tex = null, float emission = 0f, Vector2 scroll = default(Vector2), bool worldUV = false, float worldScale = 0.1f, float rim = 0.25f, float gloss = 0f)
        {
            Material m;
            if (mats.TryGetValue(key, out m) && m != null) return m;
            m = new Material(ToonShader) { name = key };
            if (tex != null) m.SetTexture("_MainTex", tex);
            m.SetFloat("_Emission", emission);
            m.SetVector("_Scroll", new Vector4(scroll.x, scroll.y, 0, 0));
            m.SetFloat("_UseWorldUV", worldUV ? 1f : 0f);
            m.SetFloat("_WorldUVScale", worldScale);
            m.SetFloat("_RimPower", rim);
            m.SetFloat("_Gloss", gloss);
            mats[key] = m;
            return m;
        }

        /// <summary>Alpha-cutout double-sided foliage material using the procedural leaf atlas.</summary>
        public static Material Foliage()
        {
            Material m;
            if (mats.TryGetValue("foliage", out m) && m != null) return m;
            if (foliage == null) foliage = LoadShader("Foliage", "TurboTribe/Foliage");
            m = new Material(foliage) { name = "foliage" };
            m.SetTexture("_MainTex", Tex("foliageAtlas", FoliageAtlas));
            m.SetFloat("_Cutoff", 0.45f);
            m.renderQueue = 2450;
            mats["foliage"] = m;
            return m;
        }

        /// <summary>Dark, soft-edged tyre mark material (alpha blended).</summary>
        public static Material Skid()
        {
            Material m;
            if (mats.TryGetValue("skid", out m) && m != null) return m;
            if (particle == null) particle = LoadShader("Particle", "TurboTribe/Particle");
            m = new Material(particle) { name = "skid" };
            m.SetTexture("_MainTex", Tex("skidtex", SkidTexture));
            m.SetFloat("_SrcBlend", (float)UnityEngine.Rendering.BlendMode.SrcAlpha);
            m.SetFloat("_DstBlend", (float)UnityEngine.Rendering.BlendMode.OneMinusSrcAlpha);
            m.renderQueue = 2460;
            mats["skid"] = m;
            return m;
        }

        public static Material Plain { get { return Toon("plain", Tex("grain", () => GrainTexture(64, 0.10f, 11))); } }
        public static Material Glow { get { return Toon("glow", null, 0.9f); } }

        public static Material Sky()
        {
            Material m;
            if (mats.TryGetValue("sky", out m) && m != null) return m;
            if (sky == null) sky = LoadShader("Sky", "TurboTribe/Sky");
            m = new Material(sky) { name = "sky" };
            mats["sky"] = m; return m;
        }

        public static Material Water(Color shallow, Color deep, Color? sky = null)
        {
            if (water == null) water = LoadShader("Water", "TurboTribe/Water");
            var m = new Material(water) { name = "water" };
            m.SetTexture("_MainTex", Tex("waternoise", () => NoiseTexture(128, 6, 77)));
            m.SetColor("_Shallow", shallow);
            m.SetColor("_Deep", deep);
            if (sky.HasValue) m.SetColor("_Sky", sky.Value);
            return m;
        }

        public static Material Particle(bool additive)
        {
            string key = additive ? "pAdd" : "pAlpha";
            Material m;
            if (mats.TryGetValue(key, out m) && m != null) return m;
            if (particle == null) particle = LoadShader("Particle", "TurboTribe/Particle");
            m = new Material(particle) { name = key };
            m.SetTexture("_MainTex", Tex("softdot", () => SoftDot(64)));
            m.SetFloat("_SrcBlend", (float)UnityEngine.Rendering.BlendMode.SrcAlpha);
            m.SetFloat("_DstBlend", additive ? (float)UnityEngine.Rendering.BlendMode.One : (float)UnityEngine.Rendering.BlendMode.OneMinusSrcAlpha);
            m.renderQueue = 3000;
            mats[key] = m;
            return m;
        }

        public static void SetFog(Color c, float start, float end)
        {
            Shader.SetGlobalVector("_TT_FogColor", c);
            Shader.SetGlobalVector("_TT_FogParams", new Vector4(start, end, 0, 1));
        }

        public static void SetAmbient(Color sky, Color ground)
        {
            Shader.SetGlobalVector("_TT_AmbientSky", sky);
            Shader.SetGlobalVector("_TT_AmbientGround", ground);
        }

        // ---------------------------------------------------------------- textures
        public static Texture2D Tex(string key, System.Func<Texture2D> make)
        {
            Texture2D t;
            if (texs.TryGetValue(key, out t) && t != null) return t;
            t = make(); t.name = key; texs[key] = t; return t;
        }

        static Texture2D NewTex(int w, int h, bool repeat = true, bool mips = true)
        {
            var t = new Texture2D(w, h, TextureFormat.RGBA32, mips);
            t.wrapMode = repeat ? TextureWrapMode.Repeat : TextureWrapMode.Clamp;
            t.filterMode = FilterMode.Bilinear;
            t.anisoLevel = 2;
            return t;
        }

        /// <summary>Mostly-white texture with subtle grain; multiplied by vertex colours.</summary>
        public static Texture2D GrainTexture(int size, float strength, int seed)
        {
            var t = NewTex(size, size);
            var px = new Color32[size * size];
            for (int y = 0; y < size; y++)
                for (int x = 0; x < size; x++)
                {
                    float n = Noise.Fbm(x / 8f, y / 8f, 3, seed, size / 8) * 0.6f + Noise.Value(x, y, seed + 5, size) * 0.4f;
                    float v = 1f - strength + n * strength;
                    byte b = (byte)(Mathf.Clamp01(v) * 255);
                    px[y * size + x] = new Color32(b, b, b, 255);
                }
            t.SetPixels32(px); t.Apply(true); return t;
        }

        public static Texture2D NoiseTexture(int size, int scale, int seed)
        {
            var t = NewTex(size, size);
            var px = new Color32[size * size];
            for (int y = 0; y < size; y++)
                for (int x = 0; x < size; x++)
                {
                    float n = Noise.Fbm(x / (float)size * scale, y / (float)size * scale, 4, seed, scale);
                    byte b = (byte)(n * 255);
                    px[y * size + x] = new Color32(b, b, b, 255);
                }
            t.SetPixels32(px); t.Apply(true); return t;
        }

        /// <summary>Road surface: speckled dirt/stone, tileable, white-based so vertex colour sets the hue.</summary>
        public static Texture2D RoadTexture(int seed)
        {
            int s = 128;
            var t = NewTex(s, s);
            var px = new Color32[s * s];
            for (int y = 0; y < s; y++)
                for (int x = 0; x < s; x++)
                {
                    float n = Noise.Fbm(x / 16f, y / 16f, 4, seed, 8);
                    float speck = Noise.Value(x * 0.9f, y * 0.9f, seed + 3, 115);
                    float pebble = Noise.Value(x / 4f, y / 4f, seed + 9, 32);
                    float v = 0.78f + n * 0.22f;
                    if (speck > 0.86f) v -= 0.18f;
                    if (pebble > 0.8f) v += 0.08f;
                    byte b = (byte)(Mathf.Clamp01(v) * 255);
                    px[y * s + x] = new Color32(b, b, b, 255);
                }
            t.SetPixels32(px); t.Apply(true); return t;
        }

        /// <summary>Animated chevron arrows for boost pads.</summary>
        public static Texture2D ChevronTexture()
        {
            int w = 64, h = 64;
            var t = NewTex(w, h);
            var px = new Color32[w * h];
            for (int y = 0; y < h; y++)
                for (int x = 0; x < w; x++)
                {
                    float u = x / (float)w, v = y / (float)h;
                    float c = Mathf.Repeat(v * 2f + Mathf.Abs(u - 0.5f) * 1.4f, 1f);
                    bool on = c < 0.45f;
                    px[y * w + x] = on ? new Color32(255, 250, 220, 255) : new Color32(255, 140, 20, 255);
                }
            t.SetPixels32(px); t.Apply(true); return t;
        }

        public static Texture2D CheckerTexture(int cells)
        {
            int s = 64;
            var t = NewTex(s, s);
            t.filterMode = FilterMode.Point;
            var px = new Color32[s * s];
            for (int y = 0; y < s; y++)
                for (int x = 0; x < s; x++)
                {
                    bool w = ((x * cells / s) + (y * cells / s)) % 2 == 0;
                    px[y * s + x] = w ? new Color32(250, 250, 250, 255) : new Color32(25, 25, 30, 255);
                }
            t.SetPixels32(px); t.Apply(true); return t;
        }

        public static Texture2D SoftDot(int s)
        {
            var t = NewTex(s, s, false);
            var px = new Color32[s * s];
            for (int y = 0; y < s; y++)
                for (int x = 0; x < s; x++)
                {
                    float dx = (x + 0.5f) / s * 2 - 1, dy = (y + 0.5f) / s * 2 - 1;
                    float d = Mathf.Sqrt(dx * dx + dy * dy);
                    float a = Mathf.Clamp01(1 - d);
                    a = a * a * (3 - 2 * a);
                    px[y * s + x] = new Color32(255, 255, 255, (byte)(a * 255));
                }
            t.SetPixels32(px); t.Apply(true); return t;
        }

        /// <summary>Tyre-mark strip: dark centre, soft edges, slight grain along the length.</summary>
        public static Texture2D SkidTexture()
        {
            int w = 32, h = 64;
            var t = NewTex(w, h);
            t.wrapMode = TextureWrapMode.Repeat;
            var px = new Color32[w * h];
            for (int y = 0; y < h; y++)
                for (int x = 0; x < w; x++)
                {
                    float u = (x + 0.5f) / w;
                    float edge = Mathf.Clamp01(1f - Mathf.Abs(u - 0.5f) * 2.2f);
                    float tread = 0.75f + 0.25f * Mathf.Sin(u * 40f) * 0.5f + Noise.Value(x * 0.7f, y * 0.4f, 5, 0) * 0.2f;
                    byte a = (byte)(Mathf.Clamp01(Mathf.Pow(edge, 0.6f) * tread) * 255);
                    px[y * w + x] = new Color32(18, 16, 14, a);
                }
            t.SetPixels32(px); t.Apply(true); return t;
        }

        /// <summary>
        /// 8-cell (64x128 each) foliage atlas painted procedurally: grass, fern, palm frond, broad leaves,
        /// flowers, reeds, pine branch, vine. White-ish albedo (tinted by vertex colour) + alpha mask.
        /// </summary>
        public static Texture2D FoliageAtlas()
        {
            int cw = 64, ch = 128, W = cw * 8;
            var atlas = new Color[W * ch];
            var rng = new Rng(1234);
            System.Func<float, Color> shade = y => { float v = Mathf.Lerp(0.62f, 1f, Mathf.Clamp01(y / ch)); return new Color(v, v, v, 1); };
            for (int cell = 0; cell < 8; cell++)
            {
                var p = new Painter(cw, ch);
                switch (cell)
                {
                    case 0: // grass blades
                        for (int b2 = 0; b2 < 22; b2++)
                        {
                            float x0 = rng.Range(6f, cw - 6f), h = rng.Range(55f, 122f), lean = rng.Range(-14f, 14f), wd = rng.Range(2.2f, 4f);
                            float tone = rng.Range(0.88f, 1f);
                            var poly = new[] { new Vector2(x0 - wd, 0), new Vector2(x0 + wd, 0), new Vector2(x0 + lean + 0.5f, h) };
                            p.Fill((x, y) => Painter.SdPoly(x, y, poly), (x, y) => shade(y) * tone);
                        }
                        break;
                    case 1: // fern frond
                        for (int k = 0; k < 16; k++)
                        {
                            float y0 = 8 + k * 7.2f, len = Mathf.Lerp(26f, 6f, k / 16f);
                            for (int sd = -1; sd <= 1; sd += 2)
                            {
                                float cx = 32 + sd * len * 0.55f, cy = y0 + 3, rx = len * 0.55f, ry = 3.4f;
                                p.Fill((x, yy) => (Mathf.Pow((x - cx) / rx, 2f) + Mathf.Pow((yy - cy) / ry, 2f) - 1f) * Mathf.Min(rx, ry) * 0.5f, (x, yy) => shade(yy));
                            }
                        }
                        p.Fill((x, y) => Painter.SdSegment(x, y, 32, 0, 32, 124, 1.6f), new Color(0.7f, 0.7f, 0.6f, 1));
                        break;
                    case 2: // palm frond
                        for (int k = 0; k < 22; k++)
                        {
                            float y0 = 6 + k * 5.4f, len = Mathf.Lerp(30f, 8f, k / 22f);
                            for (int sd = -1; sd <= 1; sd += 2)
                            {
                                float x1 = 32 + sd * len, y1 = y0 + len * 0.55f;
                                p.Fill((x, yy) => Painter.SdSegment(x, yy, 32, y0, x1, y1, 1.9f), (x, yy) => shade(yy) * 0.97f);
                            }
                        }
                        p.Fill((x, y) => Painter.SdSegment(x, y, 32, 0, 32, 126, 1.8f), new Color(0.78f, 0.74f, 0.55f, 1));
                        break;
                    case 3: // broad leaves
                        for (int k = 0; k < 9; k++)
                        {
                            float cx = rng.Range(16f, 48f), cy = rng.Range(18f, 112f), a = rng.Range(-0.8f, 0.8f);
                            float rx = rng.Range(10f, 16f), ry = rng.Range(18f, 26f), tone = rng.Range(0.85f, 1f);
                            float ca = Mathf.Cos(a), sa = Mathf.Sin(a);
                            p.Fill((x, y) =>
                            {
                                float dx = x - cx, dy = y - cy;
                                float u = dx * ca - dy * sa, v = dx * sa + dy * ca;
                                return (Mathf.Pow(u / rx, 2f) + Mathf.Pow(v / ry, 2f) - 1f) * rx * 0.5f;
                            }, (x, y) => shade(y) * tone);
                        }
                        break;
                    case 4: // flowers
                        for (int k = 0; k < 7; k++)
                        {
                            float cx = rng.Range(10f, 54f), top = rng.Range(60f, 118f);
                            p.Fill((x, y) => Painter.SdSegment(x, y, cx, 0, cx, top, 1.3f), new Color(0.35f, 0.62f, 0.3f, 1));
                            for (int pt = 0; pt < 5; pt++)
                            {
                                float a = pt / 5f * Mathf.PI * 2f;
                                float px2 = cx + Mathf.Cos(a) * 4.5f, py2 = top + Mathf.Sin(a) * 4.5f;
                                p.Fill((x, y) => Painter.SdCircle(x, y, px2, py2, 3.6f), Color.white);
                            }
                            p.Fill((x, y) => Painter.SdCircle(x, y, cx, top, 2.4f), new Color(1f, 0.85f, 0.3f, 1));
                        }
                        break;
                    case 5: // reeds
                        for (int b2 = 0; b2 < 14; b2++)
                        {
                            float x0 = rng.Range(6f, 58f), h = rng.Range(70f, 124f), lean = rng.Range(-10f, 10f);
                            var poly = new[] { new Vector2(x0 - 1.6f, 0), new Vector2(x0 + 1.6f, 0), new Vector2(x0 + lean, h) };
                            p.Fill((x, y) => Painter.SdPoly(x, y, poly), (x, y) => shade(y));
                            if (b2 % 4 == 0) p.Fill((x, y) => Painter.SdRoundBox(x, y, x0 + lean * 0.8f, h * 0.82f, 2.6f, 9f, 2.5f), new Color(0.55f, 0.38f, 0.25f, 1));
                        }
                        break;
                    case 6: // pine branch
                        for (int k = 0; k < 30; k++)
                        {
                            float y0 = 4 + k * 4f, len = Mathf.Lerp(26f, 10f, k / 30f);
                            for (int sd = -1; sd <= 1; sd += 2)
                                p.Fill((x, yy) => Painter.SdSegment(x, yy, 32, y0, 32 + sd * len, y0 + 6f, 1.2f), (x, yy) => shade(yy) * 0.95f);
                        }
                        p.Fill((x, y) => Painter.SdSegment(x, y, 32, 0, 32, 124, 2f), new Color(0.55f, 0.45f, 0.4f, 1));
                        break;
                    default: // vine
                        for (int k = 0; k < 12; k++)
                        {
                            float y0 = 6 + k * 10f;
                            float cx = 32 + Mathf.Sin(k * 1.3f) * 8f + (k % 2 == 0 ? 7 : -7);
                            p.Fill((x, yy) => Painter.SdCircle(x, yy, cx, y0, 6.5f), (x, yy) => shade(yy));
                        }
                        p.Fill((x, y) => Painter.SdSegment(x, y, 32, 0, 32, 126, 1.6f), new Color(0.6f, 0.6f, 0.45f, 1));
                        break;
                }
                for (int y = 0; y < ch; y++)
                    for (int x = 0; x < cw; x++)
                    {
                        Color c = p.Px[y * cw + x];
                        if (c.a < 0.01f) c = new Color(0.8f, 0.8f, 0.8f, 0f); // bleed colour so mips don't darken edges
                        atlas[y * W + cell * cw + x] = c;
                    }
            }
            var t = new Texture2D(W, ch, TextureFormat.RGBA32, true) { wrapMode = TextureWrapMode.Clamp, filterMode = FilterMode.Bilinear, anisoLevel = 2 };
            t.SetPixels(atlas);
            t.Apply(true);
            return t;
        }

        // 5x7 pixel glyph for '?', drawn on crates.
        static readonly string[] QGlyph = { ".###.", "#...#", "....#", "...#.", "..#..", ".....", "..#.." };

        /// <summary>Wooden crate face with a bold '?' (item crate) or a plain wood face.</summary>
        public static Texture2D CrateTexture(bool question, Color wood, Color mark)
        {
            int s = 64;
            var t = NewTex(s, s, false);
            var px = new Color32[s * s];
            for (int y = 0; y < s; y++)
                for (int x = 0; x < s; x++)
                {
                    float grain = Noise.Value(x * 0.15f, y * 1.2f, 41) * 0.15f;
                    Color c = wood * (0.9f + grain);
                    bool border = x < 6 || y < 6 || x >= s - 6 || y >= s - 6;
                    bool diag = Mathf.Abs(x - y) < 4 || Mathf.Abs(x - (s - 1 - y)) < 4;
                    if (border) c = wood * 0.65f;
                    else if (!question && diag) c = wood * 0.78f;
                    if (question)
                    {
                        int gx = (x - 12) / 8, gy = 6 - (y - 4) / 8;
                        if (x >= 12 && gx < 5 && y >= 4 && gy >= 0 && gy < 7 && QGlyph[gy][gx] == '#') c = mark;
                    }
                    c.a = 1;
                    px[y * s + x] = c;
                }
            t.SetPixels32(px); t.Apply(true); return t;
        }

        /// <summary>Yellow/black arrow board used on corner signs.</summary>
        public static Texture2D ArrowSignTexture()
        {
            int s = 64;
            var t = NewTex(s, s, false);
            var px = new Color32[s * s];
            for (int y = 0; y < s; y++)
                for (int x = 0; x < s; x++)
                {
                    float u = x / (float)s, v = y / (float)s;
                    float chev = Mathf.Repeat(u * 2.5f + Mathf.Abs(v - 0.5f) * 1.6f, 1f);
                    bool dark = chev < 0.45f;
                    bool frame = u < 0.06f || u > 0.94f || v < 0.08f || v > 0.92f;
                    Color32 c = frame ? new Color32(30, 30, 30, 255) : dark ? new Color32(30, 30, 35, 255) : new Color32(255, 214, 40, 255);
                    px[y * s + x] = c;
                }
            t.SetPixels32(px); t.Apply(true); return t;
        }
    }
}
