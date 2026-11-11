using System.Collections.Generic;
using UnityEngine;

namespace TurboTribe
{
    public enum Sfx { Hop, Land, Boost, BoostBig, Fail, Bonk, Crate, Fruit, ItemTick, ItemGet, Explosion, Beep, Go, Splash, Shield, Click, Confirm, Lap, Finish, Throw, Hit }

    /// <summary>
    /// All audio is synthesised at startup (no audio assets): sound effects, an engine loop and
    /// a looping tropical/tribal music track per theme.
    /// </summary>
    public class AudioManager : MonoBehaviour
    {
        public static AudioManager I;
        const int Rate = 22050;
        readonly Dictionary<Sfx, AudioClip> clips = new Dictionary<Sfx, AudioClip>();
        AudioSource[] pool;
        int poolIdx;
        AudioSource music;
        public AudioClip EngineClip;
        readonly Dictionary<string, AudioClip> musicCache = new Dictionary<string, AudioClip>();

        public static AudioManager Create(Transform parent)
        {
            var go = new GameObject("Audio");
            go.transform.SetParent(parent, false);
            var am = go.AddComponent<AudioManager>();
            I = am;
            am.Init();
            return am;
        }

        void Init()
        {
            pool = new AudioSource[14];
            for (int i = 0; i < pool.Length; i++)
            {
                pool[i] = gameObject.AddComponent<AudioSource>();
                pool[i].playOnAwake = false;
                pool[i].spatialBlend = 0f;
            }
            music = gameObject.AddComponent<AudioSource>();
            music.loop = true; music.playOnAwake = false;
            Generate();
        }

        public void Play(Sfx s, float vol = 1f, float pitch = 1f)
        {
            AudioClip c;
            if (!clips.TryGetValue(s, out c)) return;
            var src = pool[poolIdx = (poolIdx + 1) % pool.Length];
            src.pitch = pitch;
            src.volume = vol * Settings.SfxVolume;
            src.PlayOneShot(c);
        }

        /// <summary>Plays a sound attenuated by distance to the listener (cheap 2D panning).</summary>
        public void PlayAt(Sfx s, Vector3 pos, float vol = 1f, float pitch = 1f)
        {
            var cam = Camera.main;
            if (cam == null) { Play(s, vol, pitch); return; }
            float d = Vector3.Distance(cam.transform.position, pos);
            float att = Mathf.Clamp01(1f - (d - 8f) / 60f);
            if (att <= 0.01f) return;
            var src = pool[poolIdx = (poolIdx + 1) % pool.Length];
            src.pitch = pitch;
            src.volume = vol * att * Settings.SfxVolume;
            src.panStereo = Mathf.Clamp(Vector3.Dot(cam.transform.right, (pos - cam.transform.position).normalized), -0.8f, 0.8f);
            AudioClip c;
            if (clips.TryGetValue(s, out c)) src.PlayOneShot(c);
        }

        public void PlayMusic(string key, int seed, float tempo, bool tribal)
        {
            AudioClip c;
            if (!musicCache.TryGetValue(key, out c))
            {
                c = MusicSynth.Generate(key, seed, tempo, tribal, Rate);
                musicCache[key] = c;
            }
            if (music.clip == c && music.isPlaying) { music.volume = Settings.MusicVolume * 0.55f; return; }
            music.clip = c;
            music.volume = Settings.MusicVolume * 0.55f;
            music.Play();
        }

        public void SetMusicVolume() { music.volume = Settings.MusicVolume * 0.55f; }
        public void PauseMusic(bool p) { if (p) music.Pause(); else music.UnPause(); }
        public void MusicPitch(float p) { music.pitch = p; }

        // ------------------------------------------------------------------ synthesis
        static float[] Buf(float seconds) { return new float[Mathf.CeilToInt(seconds * Rate)]; }

        static AudioClip Make(string name, float[] d)
        {
            float peak = 0.0001f;
            for (int i = 0; i < d.Length; i++) peak = Mathf.Max(peak, Mathf.Abs(d[i]));
            float g = Mathf.Min(1f, 0.9f / peak);
            for (int i = 0; i < d.Length; i++) d[i] *= g;
            var c = AudioClip.Create(name, d.Length, 1, Rate, false);
            c.SetData(d, 0);
            return c;
        }

        static float Noise(ref uint s) { s ^= s << 13; s ^= s >> 17; s ^= s << 5; return (s & 0xFFFF) / 32768f - 1f; }

        void Generate()
        {
            uint seed = 12345;
            // hop: quick rising blip
            {
                var d = Buf(0.12f); float ph = 0;
                for (int i = 0; i < d.Length; i++) { float t = i / (float)Rate; ph += (300 + t * 3000) / Rate; d[i] = Mathf.Sin(ph * 6.283f) * (1 - t / 0.12f) * 0.6f; }
                clips[Sfx.Hop] = Make("hop", d);
            }
            // land: soft thump + gravel
            {
                var d = Buf(0.18f); float ph = 0;
                for (int i = 0; i < d.Length; i++) { float t = i / (float)Rate; ph += (120 - t * 300) / Rate; d[i] = (Mathf.Sin(ph * 6.283f) * 0.8f + Noise(ref seed) * 0.3f) * Mathf.Exp(-t * 25f); }
                clips[Sfx.Land] = Make("land", d);
            }
            // boost: whoosh (filtered noise sweep) + rising tone
            clips[Sfx.Boost] = Make("boost", Whoosh(0.5f, 400f, 2400f, ref seed, 0.6f));
            clips[Sfx.BoostBig] = Make("boostbig", Whoosh(0.75f, 300f, 3200f, ref seed, 0.9f));
            // fail / backfire: two pops
            {
                var d = Buf(0.35f);
                for (int i = 0; i < d.Length; i++)
                {
                    float t = i / (float)Rate;
                    float p1 = Mathf.Exp(-t * 40f), p2 = t > 0.14f ? Mathf.Exp(-(t - 0.14f) * 40f) : 0;
                    d[i] = Noise(ref seed) * (p1 + p2) * 0.9f + Mathf.Sin(t * 6.283f * 90f) * (p1 + p2) * 0.5f;
                }
                clips[Sfx.Fail] = Make("fail", d);
            }
            // bonk
            {
                var d = Buf(0.25f); float ph = 0;
                for (int i = 0; i < d.Length; i++) { float t = i / (float)Rate; ph += (180 - t * 400) / Rate; d[i] = (Square(ph) * 0.4f + Noise(ref seed) * 0.4f) * Mathf.Exp(-t * 18f); }
                clips[Sfx.Bonk] = Make("bonk", d);
            }
            // crate: wood crack + sparkle
            {
                var d = Buf(0.4f); float ph = 0;
                for (int i = 0; i < d.Length; i++)
                {
                    float t = i / (float)Rate; ph += 880f / Rate;
                    d[i] = Noise(ref seed) * Mathf.Exp(-t * 30f) * 0.8f + Mathf.Sin(ph * 6.283f * (t > 0.08f ? 1.5f : 1f)) * Mathf.Exp(-t * 8f) * 0.35f;
                }
                clips[Sfx.Crate] = Make("crate", d);
            }
            // fruit: two-tone ding
            {
                var d = Buf(0.25f);
                for (int i = 0; i < d.Length; i++) { float t = i / (float)Rate; float f = t < 0.07f ? 1318f : 1760f; d[i] = Mathf.Sin(t * 6.283f * f) * Mathf.Exp(-t * 14f) * 0.6f; }
                clips[Sfx.Fruit] = Make("fruit", d);
            }
            // item roulette tick / item get
            {
                var d = Buf(0.04f);
                for (int i = 0; i < d.Length; i++) { float t = i / (float)Rate; d[i] = Square(t * 1500f) * Mathf.Exp(-t * 90f) * 0.35f; }
                clips[Sfx.ItemTick] = Make("tick", d);
                var g = Buf(0.35f);
                for (int i = 0; i < g.Length; i++) { float t = i / (float)Rate; float f = t < 0.1f ? 784f : t < 0.2f ? 988f : 1175f; g[i] = (Square(t * f) * 0.3f + Mathf.Sin(t * 6.283f * f * 2) * 0.2f) * Mathf.Exp(-(t % 0.1f) * 10f) * (1 - t / 0.35f); }
                clips[Sfx.ItemGet] = Make("itemget", g);
            }
            // explosion
            {
                var d = Buf(0.9f); float lp = 0; float ph = 0;
                for (int i = 0; i < d.Length; i++)
                {
                    float t = i / (float)Rate;
                    lp += (Noise(ref seed) - lp) * Mathf.Lerp(0.6f, 0.05f, t);
                    ph += (90f - t * 60f) / Rate;
                    d[i] = (lp * 1.2f + Mathf.Sin(ph * 6.283f) * 0.6f) * Mathf.Exp(-t * 4.5f);
                }
                clips[Sfx.Explosion] = Make("explosion", d);
            }
            // countdown beeps
            clips[Sfx.Beep] = Make("beep", Tone(0.22f, 660f, 0.5f));
            clips[Sfx.Go] = Make("go", Tone(0.55f, 1320f, 0.5f));
            // splash
            {
                var d = Buf(0.7f); float lp = 0;
                for (int i = 0; i < d.Length; i++) { float t = i / (float)Rate; lp += (Noise(ref seed) - lp) * 0.3f; d[i] = lp * Mathf.Exp(-t * 5f) * (1 + Mathf.Sin(t * 60f) * 0.3f); }
                clips[Sfx.Splash] = Make("splash", d);
            }
            // shield pop / chime
            {
                var d = Buf(0.4f);
                for (int i = 0; i < d.Length; i++) { float t = i / (float)Rate; d[i] = (Mathf.Sin(t * 6.283f * 1046f) + Mathf.Sin(t * 6.283f * 1567f) * 0.6f) * Mathf.Exp(-t * 8f) * 0.4f; }
                clips[Sfx.Shield] = Make("shield", d);
            }
            // UI
            {
                var d = Buf(0.06f);
                for (int i = 0; i < d.Length; i++) { float t = i / (float)Rate; d[i] = Mathf.Sin(t * 6.283f * 1200f) * Mathf.Exp(-t * 60f) * 0.5f; }
                clips[Sfx.Click] = Make("click", d);
                var c = Buf(0.25f);
                for (int i = 0; i < c.Length; i++) { float t = i / (float)Rate; float f = t < 0.08f ? 880f : 1320f; c[i] = (Square(t * f) * 0.25f + Mathf.Sin(t * 6.283f * f) * 0.3f) * Mathf.Exp(-(t % 0.08f) * 12f); }
                clips[Sfx.Confirm] = Make("confirm", c);
            }
            // lap fanfare + finish fanfare
            clips[Sfx.Lap] = Make("lap", Arp(new[] { 784f, 988f, 1175f, 1568f }, 0.09f));
            clips[Sfx.Finish] = Make("finish", Arp(new[] { 523f, 659f, 784f, 1046f, 784f, 1046f, 1318f }, 0.12f));
            clips[Sfx.Throw] = Make("throw", Whoosh(0.25f, 1500f, 500f, ref seed, 0.5f));
            {
                var d = Buf(0.5f); float ph = 0;
                for (int i = 0; i < d.Length; i++) { float t = i / (float)Rate; ph += (700 - t * 1000) / Rate; d[i] = (Square(ph) * 0.3f + Noise(ref seed) * 0.2f) * Mathf.Exp(-t * 5f); }
                clips[Sfx.Hit] = Make("hit", d);
            }
            // engine loop: buzzy two-stroke, exact loop length (period-aligned)
            {
                float f = 55f;
                int period = Mathf.RoundToInt(Rate / f);
                var d = new float[period * 40];
                for (int i = 0; i < d.Length; i++)
                {
                    float ph = (i % period) / (float)period;
                    float saw = ph * 2f - 1f;
                    float pulse = ph < 0.18f ? 1f : -0.2f;
                    float sub = Mathf.Sin(ph * 6.283f);
                    d[i] = saw * 0.35f + pulse * 0.35f + sub * 0.4f;
                }
                // gentle low-pass
                float lp2 = 0;
                for (int pass = 0; pass < 2; pass++) for (int i = 0; i < d.Length; i++) { lp2 += (d[i] - lp2) * 0.35f; d[i] = lp2; }
                EngineClip = Make("engine", d);
            }
        }

        static float Square(float ph) { return Mathf.Repeat(ph, 1f) < 0.5f ? 1f : -1f; }

        static float[] Tone(float len, float f, float vol)
        {
            var d = Buf(len);
            for (int i = 0; i < d.Length; i++) { float t = i / (float)Rate; d[i] = (Square(t * f) * 0.5f + Mathf.Sin(t * 6.283f * f) * 0.5f) * vol * Mathf.Min(1, (len - t) * 30f); }
            return d;
        }

        static float[] Arp(float[] notes, float step)
        {
            var d = Buf(step * notes.Length + 0.3f);
            for (int i = 0; i < d.Length; i++)
            {
                float t = i / (float)Rate;
                int n = Mathf.Min(notes.Length - 1, (int)(t / step));
                float lt = t - n * step;
                float f = notes[n];
                d[i] = (Square(t * f) * 0.25f + Mathf.Sin(t * 6.283f * f) * 0.35f) * Mathf.Exp(-lt * (n == notes.Length - 1 ? 4f : 10f));
            }
            return d;
        }

        static float[] Whoosh(float len, float f0, float f1, ref uint seed, float vol)
        {
            var d = Buf(len); float lp = 0, bp = 0;
            for (int i = 0; i < d.Length; i++)
            {
                float t = i / (float)Rate, u = t / len;
                float fc = Mathf.Lerp(f0, f1, u);
                float k = Mathf.Clamp01(fc / Rate * 6.283f);
                float n = Noise(ref seed);
                lp += (n - lp) * k; bp += (lp - bp) * k;
                float env = Mathf.Sin(u * Mathf.PI) * (1 - u * 0.5f);
                d[i] = ((lp - bp) * 2f + Mathf.Sin(t * 6.283f * fc * 0.5f) * 0.15f) * env * vol;
            }
            return d;
        }
    }

    /// <summary>Tiny procedural music generator: drums, bass, marimba chords and a pentatonic lead.</summary>
    public static class MusicSynth
    {
        public static AudioClip Generate(string name, int seed, float tempo, bool tribal, int rate)
        {
            var rng = new System.Random(seed);
            float beat = 60f / tempo;
            int bars = 8;
            float len = bars * 4 * beat;
            int n = Mathf.CeilToInt(len * rate);
            var d = new float[n];
            int root = 48 + rng.Next(0, 7); // MIDI note
            int[][] progs = { new[] { 0, 7, 9, 5 }, new[] { 0, 5, 7, 5 }, new[] { 9, 5, 0, 7 }, new[] { 0, 9, 5, 7 } };
            int[] prog = progs[rng.Next(progs.Length)];
            int[] penta = { 0, 2, 4, 7, 9, 12, 14, 16 };
            uint ns = (uint)(seed * 7919 + 1);

            // drums
            for (int b = 0; b < bars * 4; b++)
            {
                float t0 = b * beat;
                AddKick(d, t0, rate);
                if (b % 2 == 1) AddSnare(d, t0, rate, ref ns);
                for (int h = 0; h < 2; h++) AddHat(d, t0 + h * beat * 0.5f, rate, ref ns, h == 1 ? 0.18f : 0.1f);
                if (tribal && b % 4 == 3) { AddTom(d, t0 + beat * 0.5f, rate, 180f); AddTom(d, t0 + beat * 0.75f, rate, 140f); }
            }
            // harmony
            for (int bar = 0; bar < bars; bar++)
            {
                int chordRoot = root + prog[bar % 4];
                bool minor = prog[bar % 4] == 9;
                int[] chord = { 0, minor ? 3 : 4, 7 };
                float tb = bar * 4 * beat;
                // bass: root on 1, fifth on "and" of 2, octave pops
                int[] bassPat = { 0, -1, 0, 7, 0, -1, 12, 7 };
                for (int k = 0; k < 8; k++)
                {
                    if (bassPat[k] < 0) continue;
                    AddNote(d, tb + k * beat * 0.5f, beat * 0.45f, Midi(chordRoot - 12 + bassPat[k]), rate, 0.32f, 1);
                }
                // marimba chord stabs on off-beats
                for (int k = 0; k < 8; k++)
                {
                    if (k % 2 == 0 && k != 0) continue;
                    foreach (int c in chord) AddNote(d, tb + k * beat * 0.5f, beat * 0.4f, Midi(chordRoot + 12 + c), rate, 0.09f, 2);
                }
            }
            // lead melody: 2-bar motif repeated with variation
            var motif = new List<KeyValuePair<float, int>>();
            float pos = 0;
            while (pos < 8f)
            {
                float durB = rng.NextDouble() < 0.6 ? 0.5f : (rng.NextDouble() < 0.5 ? 1f : 0.25f);
                if (rng.NextDouble() < 0.82) motif.Add(new KeyValuePair<float, int>(pos, penta[rng.Next(penta.Length)]));
                pos += durB;
            }
            for (int rep = 0; rep < bars / 2; rep++)
            {
                if (rep == 1 || rep == 3) { }
                for (int m = 0; m < motif.Count; m++)
                {
                    float tb = (rep * 8f + motif[m].Key) * beat;
                    int note = root + 24 + motif[m].Value + (rep == 2 ? 2 : 0);
                    float nd = (m + 1 < motif.Count ? motif[m + 1].Key - motif[m].Key : 8f - motif[m].Key) * beat * 0.9f;
                    AddNote(d, tb, Mathf.Min(nd, beat * 1.5f), Midi(note), rate, 0.11f, 3);
                }
            }
            // soft clip + normalise
            float peak = 0.001f;
            for (int i = 0; i < n; i++) { d[i] = (float)System.Math.Tanh(d[i] * 1.4f); peak = Mathf.Max(peak, Mathf.Abs(d[i])); }
            for (int i = 0; i < n; i++) d[i] *= 0.85f / peak;
            var clip = AudioClip.Create(name, n, 1, rate, false);
            clip.SetData(d, 0);
            return clip;
        }

        static float Midi(int m) { return 440f * Mathf.Pow(2f, (m - 69) / 12f); }

        static void AddNote(float[] d, float t0, float dur, float f, int rate, float vol, int timbre)
        {
            int s0 = (int)(t0 * rate), len = (int)((dur + 0.15f) * rate);
            for (int i = 0; i < len; i++)
            {
                int idx = s0 + i; if (idx >= d.Length) break;
                float t = i / (float)rate;
                float env;
                float v;
                switch (timbre)
                {
                    case 1: // bass: triangle-ish
                        env = Mathf.Min(1, t * 200f) * (t < dur ? 1f : Mathf.Exp(-(t - dur) * 30f)) * Mathf.Exp(-t * 2f);
                        v = Mathf.Asin(Mathf.Sin(t * f * 6.283f)) * 0.9f + Mathf.Sin(t * f * 6.283f) * 0.4f;
                        break;
                    case 2: // marimba: sine + 4th harmonic, fast decay
                        env = Mathf.Exp(-t * 9f) * Mathf.Min(1, t * 400f);
                        v = Mathf.Sin(t * f * 6.283f) + Mathf.Sin(t * f * 4f * 6.283f) * 0.25f * Mathf.Exp(-t * 30f);
                        break;
                    default: // lead: pulse with vibrato
                        env = Mathf.Min(1, t * 80f) * (t < dur ? 1f : Mathf.Exp(-(t - dur) * 20f));
                        float vib = 1f + Mathf.Sin(t * 6.283f * 5.5f) * 0.006f * Mathf.Clamp01(t * 4f);
                        float ph = Mathf.Repeat(t * f * vib, 1f);
                        v = (ph < 0.3f ? 0.8f : -0.35f) * 0.6f + Mathf.Sin(t * f * vib * 6.283f) * 0.5f;
                        break;
                }
                d[idx] += v * env * vol;
            }
        }

        static void AddKick(float[] d, float t0, int rate)
        {
            int s0 = (int)(t0 * rate); float ph = 0;
            for (int i = 0; i < rate * 0.25f; i++)
            {
                int idx = s0 + i; if (idx >= d.Length) break;
                float t = i / (float)rate;
                ph += (50f + 120f * Mathf.Exp(-t * 30f)) / rate;
                d[idx] += Mathf.Sin(ph * 6.283f) * Mathf.Exp(-t * 14f) * 0.55f;
            }
        }

        static float Nz(ref uint s) { s ^= s << 13; s ^= s >> 17; s ^= s << 5; return (s & 0xFFFF) / 32768f - 1f; }

        static void AddSnare(float[] d, float t0, int rate, ref uint ns)
        {
            int s0 = (int)(t0 * rate);
            for (int i = 0; i < rate * 0.18f; i++)
            {
                int idx = s0 + i; if (idx >= d.Length) break;
                float t = i / (float)rate;
                d[idx] += (Nz(ref ns) * 0.35f + Mathf.Sin(t * 6.283f * 190f) * 0.25f) * Mathf.Exp(-t * 20f);
            }
        }

        static void AddHat(float[] d, float t0, int rate, ref uint ns, float vol)
        {
            int s0 = (int)(t0 * rate); float prev = 0;
            for (int i = 0; i < rate * 0.05f; i++)
            {
                int idx = s0 + i; if (idx >= d.Length) break;
                float t = i / (float)rate;
                float n = Nz(ref ns); float hp = n - prev; prev = n;
                d[idx] += hp * Mathf.Exp(-t * 70f) * vol;
            }
        }

        static void AddTom(float[] d, float t0, int rate, float f)
        {
            int s0 = (int)(t0 * rate); float ph = 0;
            for (int i = 0; i < rate * 0.3f; i++)
            {
                int idx = s0 + i; if (idx >= d.Length) break;
                float t = i / (float)rate;
                ph += (f * (1 + Mathf.Exp(-t * 20f) * 0.5f)) / rate;
                d[idx] += Mathf.Sin(ph * 6.283f) * Mathf.Exp(-t * 9f) * 0.35f;
            }
        }
    }
}
