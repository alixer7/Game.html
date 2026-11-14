#!/usr/bin/env python3
"""Procedurally synthesises every sound effect and the menu music loop.

Usage:  python3 tools/gen_sfx.py   (writes assets/sfx/*.wav)
Only numpy is required. Output is deterministic (fixed random seed).
"""
import os
import wave
import numpy as np

SR = 32000
OUT = os.path.join(os.path.dirname(__file__), "..", "assets", "sfx")
rng = np.random.default_rng(1234)


def t_axis(dur, sr=SR):
    return np.arange(int(dur * sr)) / sr


def write(name, x, sr=SR, peak=0.9):
    x = np.asarray(x, dtype=np.float64)
    m = np.max(np.abs(x)) + 1e-9
    x = x / m * peak
    pcm = (np.clip(x, -1, 1) * 32767).astype(np.int16)
    os.makedirs(OUT, exist_ok=True)
    with wave.open(os.path.join(OUT, name + ".wav"), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(sr)
        w.writeframes(pcm.tobytes())
    print("wrote", name, len(x) / sr, "s")


def env_exp(t, decay):
    return np.exp(-t / decay)


def attack(t, a):
    return np.clip(t / max(a, 1e-6), 0, 1)


def fft_filter(x, lo=0.0, hi=None, sr=SR, tilt=0.0):
    """Zero-phase band-pass by FFT masking (circular -> loops stay seamless)."""
    n = len(x)
    X = np.fft.rfft(x)
    f = np.fft.rfftfreq(n, 1 / sr)
    hi = hi or sr / 2
    mask = 1 / (1 + (lo / np.maximum(f, 1e-3)) ** 4) / (1 + (f / hi) ** 4)
    if tilt:
        mask = mask * np.power(np.maximum(f, 20) / 1000.0, tilt)
    return np.fft.irfft(X * mask, n)


def lowpass(x, cutoff, sr=SR):
    a = np.exp(-2 * np.pi * cutoff / sr)
    y = np.zeros_like(x)
    acc = 0.0
    for i in range(len(x)):
        acc = (1 - a) * x[i] + a * acc
        y[i] = acc
    return y


def sweep(t, f0, f1, curve=1.0):
    dur = t[-1] if len(t) else 1
    f = f0 + (f1 - f0) * (t / dur) ** curve
    return np.sin(2 * np.pi * np.cumsum(f) / SR)


def noise(n):
    return rng.standard_normal(n)


def saw(phase):
    return 2.0 * (phase % 1.0) - 1.0


# ------------------------------------------------------------------ effects

def hit(hard):
    dur = 0.55 if hard else 0.3
    t = t_axis(dur)
    thump = sweep(t, 150 if hard else 190, 42 if hard else 70, 0.5) * env_exp(t, 0.09 if hard else 0.06)
    click = fft_filter(noise(len(t)), 800, 7000) * env_exp(t, 0.012)
    ring = (np.sin(2 * np.pi * 620 * t) * 0.5 + np.sin(2 * np.pi * 1530 * t) * 0.3
            + np.sin(2 * np.pi * 2710 * t) * 0.15) * env_exp(t, 0.12 if hard else 0.07)
    x = thump * 1.2 + click * (0.9 if hard else 0.5) + ring * (0.45 if hard else 0.25)
    if hard:
        x = np.tanh(x * 2.2)
    return x


def bounce():
    t = t_axis(0.32)
    x = sweep(t, 160, 85, 0.6) * env_exp(t, 0.07)
    x += fft_filter(noise(len(t)), 100, 1200) * env_exp(t, 0.02) * 0.4
    return x


def whoosh(dur, f0, f1, decay=None):
    t = t_axis(dur)
    n = noise(len(t))
    out = np.zeros_like(t)
    seg = 8
    edges = np.linspace(0, len(t), seg + 1).astype(int)
    for i in range(seg):
        fc = f0 + (f1 - f0) * (i + 0.5) / seg
        part = fft_filter(n, fc * 0.6, fc * 1.6)
        w = np.zeros_like(t)
        a, b = edges[i], edges[i + 1]
        pad = (b - a) // 2
        lo, hi = max(0, a - pad), min(len(t), b + pad)
        w[lo:hi] = np.hanning(hi - lo)
        out += part * w
    e = np.sin(np.pi * np.clip(t / dur, 0, 1)) ** 1.5
    if decay:
        e *= env_exp(t, decay)
    return out * e


def jump():
    t = t_axis(0.28)
    return whoosh(0.28, 400, 2400) * 0.8 + sweep(t, 90, 160) * env_exp(t, 0.05) * 0.8


def land():
    t = t_axis(0.25)
    x = sweep(t, 110, 50) * env_exp(t, 0.05)
    x += fft_filter(noise(len(t)), 200, 3000) * env_exp(t, 0.03) * 0.5
    rattle = np.sin(2 * np.pi * 37 * t) * fft_filter(noise(len(t)), 1500, 5000) * env_exp(t, 0.08) * 0.3
    return x + rattle


def boost_loop():
    dur = 2.0
    t = t_axis(dur)
    n = noise(len(t))
    rumble = fft_filter(n, 30, 350) * 2.2
    roar = fft_filter(noise(len(t)), 300, 2400) * 0.9
    hiss = fft_filter(noise(len(t)), 3000, 9000) * 0.35
    flutter = 1 + 0.25 * np.sin(2 * np.pi * 24 * t) + 0.15 * np.sin(2 * np.pi * 61 * t)
    return np.tanh((rumble + roar + hiss) * flutter * 0.8)


def engine_loop():
    dur = 1.0
    t = t_axis(dur)
    base = 52.0
    x = np.zeros_like(t)
    for h, a in [(1, 1.0), (2, 0.6), (3, 0.42), (4, 0.25), (6, 0.15), (8, 0.08)]:
        x += a * np.sin(2 * np.pi * base * h * t + h * 0.7)
    x *= 1 + 0.35 * np.sin(2 * np.pi * 26 * t)
    x += fft_filter(noise(len(t)), 80, 900) * 0.25
    return np.tanh(x * 0.9)


def blip(f0, f1, dur, decay):
    t = t_axis(dur)
    return (sweep(t, f0, f1) + 0.3 * sweep(t, f0 * 2, f1 * 2)) * env_exp(t, decay) * attack(t, 0.003)


def pad_big():
    t = t_axis(0.7)
    x = np.zeros_like(t)
    for i, f in enumerate([523.25, 659.25, 783.99, 1046.5]):
        st = i * 0.06
        tt = np.clip(t - st, 0, None)
        x += np.sin(2 * np.pi * f * tt) * env_exp(tt, 0.18) * (t >= st)
    x += whoosh(0.7, 800, 4000) * 0.35
    return x


def explosion(dur, low, size):
    t = t_axis(dur)
    boom = sweep(t, low * 2.2, low * 0.5, 0.4) * env_exp(t, 0.35 * size)
    body = fft_filter(noise(len(t)), 40, 2500) * env_exp(t, 0.25 * size)
    crackle = fft_filter(noise(len(t)), 2000, 9000) * env_exp(t, 0.12 * size) * (rng.random(len(t)) > 0.97) * 3
    tail = fft_filter(noise(len(t)), 30, 300) * env_exp(t, 0.9 * size) * 0.6
    return np.tanh((boom * 1.6 + body + crackle * 0.4 + tail) * 1.6)


def bump():
    t = t_axis(0.3)
    x = sweep(t, 220, 90) * env_exp(t, 0.05)
    clank = sum(np.sin(2 * np.pi * f * t) * a for f, a in [(480, 0.5), (1210, 0.35), (2330, 0.2)])
    x += clank * env_exp(t, 0.07)
    x += fft_filter(noise(len(t)), 600, 6000) * env_exp(t, 0.015) * 0.6
    return x


def beep(freqs, dur):
    t = t_axis(dur)
    x = sum(np.sin(2 * np.pi * f * t) + 0.25 * np.sin(4 * np.pi * f * t) for f in freqs)
    return x * attack(t, 0.005) * np.clip((dur - t) / 0.08, 0, 1)


def crowd_loop():
    dur = 6.0
    t = t_axis(dur)
    x = np.zeros_like(t)
    # many band-limited "voices" with slow swells; FFT filtering keeps it periodic
    for i in range(10):
        lo = rng.uniform(250, 700)
        v = fft_filter(noise(len(t)), lo, lo * rng.uniform(2.5, 5.0))
        swell = 0.6 + 0.4 * np.sin(2 * np.pi * (i % 3 + 1) / dur * t + rng.uniform(0, 6.28))
        x += v * swell
    x += fft_filter(noise(len(t)), 60, 400) * 0.6
    return x


def cheer():
    dur = 3.2
    t = t_axis(dur)
    x = crowd_loop()[: len(t)] if False else np.zeros_like(t)
    for i in range(14):
        lo = rng.uniform(300, 900)
        x += fft_filter(noise(len(t)), lo, lo * 3.5)
    e = attack(t, 0.25) * np.clip((dur - t) / 1.6, 0, 1)
    whistle = np.zeros_like(t)
    for k in range(3):
        st = rng.uniform(0.2, 1.6)
        f = rng.uniform(1800, 2600)
        tt = np.clip(t - st, 0, None)
        whistle += np.sin(2 * np.pi * (f + 120 * np.sin(2 * np.pi * 5 * tt)) * tt) * (t > st) * env_exp(tt, 0.35)
    return x * e + whistle * 0.25 * np.max(np.abs(x * e))


def horn():
    dur = 1.6
    t = t_axis(dur)
    vib = 1 + 0.006 * np.sin(2 * np.pi * 5.5 * t)
    x = sum(saw(f * t * vib) * a for f, a in [(220, 1.0), (277.2, 0.7), (329.6, 0.6), (110, 0.6)])
    x = lowpass(x, 1800)
    return x * attack(t, 0.04) * np.clip((dur - t) / 0.25, 0, 1)


def click():
    t = t_axis(0.06)
    return np.sin(2 * np.pi * 1900 * t) * env_exp(t, 0.008) + fft_filter(noise(len(t)), 2000, 8000) * env_exp(t, 0.004) * 0.4


# ------------------------------------------------------------------ music

def note_freq(n):
    return 440.0 * 2 ** ((n - 69) / 12)


def music_loop():
    bpm = 118
    beat = 60 / bpm
    bars = 8
    dur = bars * 4 * beat
    t = t_axis(dur)
    n = len(t)
    out = np.zeros(n)
    # i - VI - III - VII in A minor
    chords = [[57, 60, 64], [53, 57, 60], [48, 52, 55], [55, 59, 62]]
    roots = [45, 41, 48, 43]

    def place(sig, start):
        s = int(start * SR)
        e = min(n, s + len(sig))
        if s < n:
            out[s:e] += sig[: e - s]
            if s + len(sig) > n:  # wrap around for seamless loop
                rem = sig[e - s:]
                out[: len(rem)] += rem

    # pads
    for bar in range(bars):
        ch = chords[(bar // 2) % 4]
        seg_t = t_axis(beat * 4 + 0.3)
        pad = np.zeros_like(seg_t)
        for note in ch + [ch[0] + 12]:
            f = note_freq(note)
            for det in (-0.12, 0.0, 0.12):
                pad += saw(seg_t * f * 2 ** (det / 12)) * 0.12
        pad = lowpass(pad, 1400)
        pad *= attack(seg_t, 0.25) * np.clip((len(seg_t) / SR - seg_t) / 0.3, 0, 1)
        place(pad * 0.55, bar * 4 * beat)
    # bass (eighths)
    for bar in range(bars):
        r = roots[(bar // 2) % 4]
        for k in range(8):
            st = (bar * 4 + k * 0.5) * beat
            seg_t = t_axis(beat * 0.48)
            f = note_freq(r + (12 if k % 2 else 0))
            b = (saw(seg_t * f) * 0.6 + np.sin(2 * np.pi * f * seg_t)) * env_exp(seg_t, 0.16)
            place(lowpass(b, 700) * 0.6, st)
    # arpeggio (sixteenths)
    for bar in range(bars):
        ch = chords[(bar // 2) % 4]
        pattern = [0, 1, 2, 3, 2, 1, 0, 2]
        for k in range(16):
            st = (bar * 4 + k * 0.25) * beat
            seg_t = t_axis(beat * 0.3)
            notes = ch + [ch[0] + 12]
            f = note_freq(notes[pattern[k % 8]] + 12)
            a = (np.sign(np.sin(2 * np.pi * f * seg_t)) * 0.3 + np.sin(2 * np.pi * f * seg_t)) * env_exp(seg_t, 0.07)
            place(a * (0.16 if bar >= 2 else 0.0), st)
    # drums
    kick_t = t_axis(0.35)
    kick = sweep(kick_t, 140, 42, 0.35) * env_exp(kick_t, 0.12)
    snare_t = t_axis(0.25)
    snare = fft_filter(noise(len(snare_t)), 900, 8000) * env_exp(snare_t, 0.06) + np.sin(2 * np.pi * 190 * snare_t) * env_exp(snare_t, 0.04) * 0.6
    hat_t = t_axis(0.08)
    hat = fft_filter(noise(len(hat_t)), 6000, 14000) * env_exp(hat_t, 0.015)
    for bar in range(bars):
        for b in range(4):
            st = (bar * 4 + b) * beat
            place(kick * 1.1, st)
            if b in (1, 3):
                place(snare * 0.55, st)
            place(hat * 0.35, st + beat * 0.5)
            if bar >= 4:
                place(hat * 0.2, st + beat * 0.25)
                place(hat * 0.2, st + beat * 0.75)
    return np.tanh(out * 0.9)


def main():
    write("hit_soft", hit(False))
    write("hit_hard", hit(True))
    write("bounce", bounce())
    write("jump", jump())
    write("flip", whoosh(0.38, 300, 1800, 0.3))
    write("land", land())
    write("boost_loop", boost_loop(), peak=0.7)
    write("engine_loop", engine_loop(), peak=0.6)
    write("pad_small", blip(900, 1500, 0.16, 0.05), peak=0.5)
    write("pad_big", pad_big(), peak=0.6)
    write("goal", explosion(2.6, 55, 1.0))
    write("demo", explosion(1.2, 80, 0.5))
    write("bump", bump())
    write("beep", beep([660], 0.22), peak=0.5)
    write("beep_go", beep([990, 1320], 0.6), peak=0.55)
    write("crowd_loop", crowd_loop(), peak=0.5)
    write("cheer", cheer(), peak=0.8)
    write("horn", horn(), peak=0.7)
    write("click", click(), peak=0.4)
    write("whoosh", whoosh(0.5, 500, 3000), peak=0.6)
    write("supersonic", whoosh(0.6, 1500, 6000, 0.4), peak=0.5)
    write("music_loop", music_loop(), sr=SR, peak=0.75)


if __name__ == "__main__":
    main()
