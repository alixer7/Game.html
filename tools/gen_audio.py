#!/usr/bin/env python3
"""Synthesizes all game audio (original, deterministic): python3 tools/gen_audio.py
Writes WAV effects and an OGG music loop into audio/ (ffmpeg needed for OGG)."""
import os
import subprocess
import wave
import numpy as np

SR = 44100
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "audio")
os.makedirs(OUT, exist_ok=True)
rng = np.random.default_rng(42)


def t_(d):
    return np.arange(int(SR * d)) / SR


def env(n, a=0.005, r=0.2, shape=2.0):
    e = np.ones(n)
    na = max(1, int(a * SR))
    e[:na] = np.linspace(0, 1, na)
    tail = np.linspace(1, 0, n - na) ** shape
    e[na:] = tail
    return e


def write(name, x, stereo=False):
    x = np.clip(x, -1, 1)
    data = (x * 32000).astype(np.int16)
    path = os.path.join(OUT, name + ".wav")
    with wave.open(path, "wb") as w:
        w.setnchannels(2 if stereo else 1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(data.tobytes())
    print("wrote", name)
    return path


def mx(*parts):
    """Sum signals of different lengths (zero-padded)."""
    n = max(len(p) for p in parts)
    out = np.zeros(n)
    for p in parts:
        out[: len(p)] += p
    return out


def saw(f, t):
    return 2.0 * ((f * t) % 1.0) - 1.0


def sq(f, t, duty=0.5):
    return np.where((f * t) % 1.0 < duty, 1.0, -1.0)


def noise(n):
    return rng.uniform(-1, 1, n)


def lowpass(x, a):
    y = np.zeros_like(x)
    acc = 0.0
    for i in range(len(x)):
        acc += a * (x[i] - acc)
        y[i] = acc
    return y


def engine():
    d = 1.0
    t = t_(d)
    f = 60.0  # 60 whole cycles in 1 s -> seamless loop
    x = 0.55 * saw(f, t) + 0.3 * np.sin(2 * np.pi * f * 2 * t) + 0.18 * sq(f * 0.5, t, 0.3)
    putt = 0.5 + 0.5 * np.sin(2 * np.pi * 15 * t)   # 15 Hz chug, also whole cycles
    x = x * (0.65 + 0.35 * putt)
    x = lowpass(x, 0.22) * 0.75
    write("engine_loop", x)


def chime(freqs, d=0.35, bright=1.0):
    t = t_(d)
    x = np.zeros_like(t)
    for i, f in enumerate(freqs):
        x += np.sin(2 * np.pi * f * t) * (0.6 / (i + 1)) * bright
        x += 0.15 * np.sin(2 * np.pi * f * 2.01 * t)
    return x * env(len(t), 0.003, d, 3.0)


def whoosh(d=0.6, up=True):
    n = int(SR * d)
    x = noise(n)
    sweep = np.linspace(0.02, 0.35, n) if up else np.linspace(0.35, 0.02, n)
    y = np.zeros(n)
    acc = 0.0
    for i in range(n):
        acc += sweep[i] * (x[i] - acc)
        y[i] = acc
    return y * env(n, 0.05, d, 1.5) * 1.6


def thud(d=0.3, f0=110):
    t = t_(d)
    f = f0 * np.exp(-t * 9)
    ph = np.cumsum(2 * np.pi * f / SR)
    x = np.sin(ph) * env(len(t), 0.002, d, 2.5)
    x = mx(x, lowpass(noise(len(t)), 0.08) * env(len(t), 0.001, 0.08, 2.0) * 0.8)
    return x


def main():
    engine()
    write("spark1", chime([880, 1320]))
    write("spark2", chime([1046, 1568]))
    write("spark3", chime([1318, 1975, 2637]))
    write("spark_perfect", chime([1568, 2093, 2637, 3136], 0.5, 1.2))
    t = t_(0.25)
    write("fizzle", lowpass(noise(len(t)), 0.3) * env(len(t), 0.002, 0.25, 1.2) * 0.6)
    t = t_(0.4)
    bf = mx(thud(0.4, 70) * 0.8, lowpass(noise(len(t)), 0.15) * env(len(t), 0.001, 0.3) * 0.6)
    write("backfire", bf)
    write("boost", whoosh(0.7) * 0.8)
    write("pad", mx(whoosh(0.5) * 0.7, chime([660, 990], 0.5) * 0.4))
    write("pad_overdrive", mx(whoosh(0.8) * 0.8, chime([523, 784, 1046, 1568], 0.8) * 0.5))
    write("overdrive", chime([392, 523, 659, 784, 1046], 0.9) * 0.7)
    write("hop", thud(0.12, 220) * 0.5)
    write("land", thud(0.3, 90) * 0.9)
    write("thud", thud(0.35, 80))
    t = t_(0.5)
    scrape = lowpass(noise(len(t)), 0.5) * (0.5 + 0.5 * np.sin(2 * np.pi * 37 * t)) * env(len(t), 0.01, 0.5, 1.0)
    write("scrape", scrape * 0.5)
    t = t_(0.6)
    splash = lowpass(noise(len(t)), 0.25) * env(len(t), 0.005, 0.6, 2.0)
    write("splash", splash * 0.8)
    write("crate", chime([784, 988, 1175, 1568], 0.45) * 0.8)
    write("amber", chime([1760, 2349], 0.2) * 0.6)
    t = t_(0.18)
    write("beep_low", np.sin(2 * np.pi * 660 * t) * env(len(t), 0.003, 0.18, 1.0) * 0.6)
    t = t_(0.5)
    write("beep_high", np.sin(2 * np.pi * 1320 * t) * env(len(t), 0.003, 0.5, 1.5) * 0.6)
    write("fire", mx(whoosh(0.35, False) * 0.6, thud(0.15, 300) * 0.3))
    t = t_(0.9)
    boom = mx(thud(0.9, 60), lowpass(noise(len(t)), 0.12) * env(len(t), 0.002, 0.9, 1.8))
    write("explode", boom * 0.8)
    write("shield", chime([523, 659, 784], 0.6) * 0.6)
    write("hit", mx(thud(0.4, 140) * 0.8, chime([300, 280], 0.4) * 0.3))
    write("snap", mx(thud(0.2, 250), lowpass(noise(int(SR * 0.2)), 0.6) * env(int(SR * 0.2), 0.001, 0.1) * 0.6))
    t = t_(0.7)
    write("crash_wood", mx(thud(0.7, 120) * 0.6, lowpass(noise(len(t)), 0.4) * env(len(t), 0.001, 0.5, 2.0) * 0.7))
    write("click", chime([1200], 0.06) * 0.5)
    write("lap", chime([784, 988, 1175], 0.5) * 0.7)
    write("final_lap", chime([523, 659, 784, 1046, 1318], 1.0) * 0.7)
    write("item_roll", chime([1046, 1318], 0.08) * 0.4)
    fan = np.concatenate([chime([523, 659, 784], 0.25), chime([587, 740, 880], 0.25), chime([659, 784, 988, 1318], 1.2)])
    write("finish", fan * 0.8)
    music()


def music():
    bpm = 138.0
    beat = 60.0 / bpm
    bars = 16
    total = bars * 4 * beat
    n = int(total * SR)
    L = np.zeros(n)
    R = np.zeros(n)

    def add(buf, start, x, gain=1.0):
        i = int(start * SR)
        j = min(n, i + len(x))
        buf[i:j] += x[: j - i] * gain

    kick = thud(0.25, 120)
    snare_t = t_(0.2)
    snare = lowpass(noise(len(snare_t)), 0.6) * env(len(snare_t), 0.001, 0.2, 2.2) * 0.7 + np.sin(2 * np.pi * 190 * snare_t) * env(len(snare_t), 0.001, 0.1) * 0.4
    hat_t = t_(0.05)
    hat = (noise(len(hat_t)) - lowpass(noise(len(hat_t)), 0.5)) * env(len(hat_t), 0.001, 0.05, 2.0) * 0.35
    # original progression: I - vi - IV - V in G with a lift to the relative minor
    roots = [196.0, 164.81, 130.81, 146.83] * 4
    chords = {196.0: [392, 494, 587], 164.81: [330, 392, 494], 130.81: [262, 330, 392], 146.83: [294, 370, 440]}
    melody = [7, 9, 11, 9, 7, 4, 2, 4, 7, 11, 12, 11, 9, 7, 9, 11,
              12, 11, 9, 7, 9, 7, 4, 2, 4, 7, 9, 7, 4, 2, 4, 0]
    scale = {0: 392, 2: 440, 4: 494, 7: 587, 9: 659, 11: 740, 12: 784}
    for bar in range(bars):
        t0 = bar * 4 * beat
        root = roots[bar]
        for b in range(4):
            add(L, t0 + b * beat, kick, 0.9)
            add(R, t0 + b * beat, kick, 0.9)
            if b % 2 == 1:
                add(L, t0 + b * beat, snare, 0.6)
                add(R, t0 + b * beat, snare, 0.6)
            for h in range(2):
                add(L, t0 + (b + h * 0.5) * beat, hat, 0.5)
                add(R, t0 + (b + h * 0.5 + 0.02) * beat, hat, 0.4)
            # bass: root with octave bounce
            bt = t_(beat * 0.45)
            f = root / 2.0 if b % 2 == 0 else root
            bass = (0.6 * saw(f, bt) + 0.4 * np.sin(2 * np.pi * f * bt)) * env(len(bt), 0.005, beat * 0.45, 1.3)
            add(L, t0 + b * beat, lowpass(bass, 0.12), 0.5)
            add(R, t0 + b * beat, lowpass(bass, 0.12), 0.5)
        # pad chord
        ct = t_(4 * beat)
        pad = np.zeros(len(ct))
        for cf in chords[root]:
            pad += sq(cf, ct, 0.25) * 0.15 + np.sin(2 * np.pi * cf * 1.003 * ct) * 0.2
        pad *= env(len(ct), 0.08, 4 * beat, 0.8)
        add(L, t0, lowpass(pad, 0.1), 0.35)
        add(R, t0, lowpass(pad, 0.12), 0.35)
        # lead (bars 4..15)
        if bar >= 4:
            for s in range(2):
                note = melody[((bar - 4) * 2 + s) % len(melody)]
                lt = t_(beat * 1.8)
                f = scale[note]
                vib = 1.0 + 0.006 * np.sin(2 * np.pi * 5.5 * lt)
                ph = np.cumsum(2 * np.pi * f * vib / SR)
                lead = (np.sin(ph) * 0.6 + np.sign(np.sin(ph)) * 0.15) * env(len(lt), 0.01, beat * 1.8, 1.2)
                add(L, t0 + s * 2 * beat, lead, 0.32)
                add(R, t0 + s * 2 * beat + 0.012, lead, 0.28)
    mix = np.stack([L, R], -1)
    mix /= max(1e-6, np.abs(mix).max()) / 0.85
    wav = write("music_race", mix.reshape(-1), stereo=True)
    ogg = os.path.join(OUT, "music_race.ogg")
    try:
        subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", wav, "-c:a", "libvorbis", "-q:a", "4", ogg], check=True)
        os.remove(wav)
        print("wrote music_race.ogg")
    except Exception as e:  # keep the WAV if ffmpeg is missing
        print("ffmpeg failed, keeping wav:", e)


if __name__ == "__main__":
    main()
