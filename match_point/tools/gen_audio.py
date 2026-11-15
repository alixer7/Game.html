#!/usr/bin/env python3
"""توليد أصوات اللعبة إجرائياً (بدون ملفات خارجية).
الاستخدام:  python3 tools/gen_audio.py   (يكتب إلى assets/audio/*.wav)
"""
import numpy as np, wave, os

SR = 32000
OUT = os.path.join(os.path.dirname(__file__), "..", "assets", "audio")
rng = np.random.default_rng(7)


def t(n):
    return np.arange(int(n * SR)) / SR


def bandpass(x, lo, hi, soft=0.25):
    X = np.fft.rfft(x)
    f = np.fft.rfftfreq(len(x), 1 / SR)
    w = np.ones_like(f)
    lo_w = max(lo * soft, 1.0)
    hi_w = max(hi * soft, 1.0)
    w *= np.clip((f - (lo - lo_w)) / lo_w, 0, 1)
    w *= np.clip(((hi + hi_w) - f) / hi_w, 0, 1)
    return np.fft.irfft(X * w, len(x))


def env(n, tau, attack=0.001):
    tt = t(n)
    return np.minimum(tt / attack, 1.0) * np.exp(-tt / tau)


def tone(n, f, tau, bend=0.0):
    tt = t(n)
    ph = 2 * np.pi * (f * tt + bend * f * tau * (1 - np.exp(-tt / tau)))
    return np.sin(ph) * np.exp(-tt / tau)


def noise(n):
    return rng.standard_normal(int(n * SR))


def save(name, x, peak=0.9):
    x = x / (np.max(np.abs(x)) + 1e-9) * peak
    # نعومة النهاية
    k = min(len(x) // 8, 400)
    if k > 0:
        x[-k:] *= np.linspace(1, 0, k)
    pcm = (np.clip(x, -1, 1) * 32767).astype(np.int16)
    with wave.open(os.path.join(OUT, name + ".wav"), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(pcm.tobytes())
    print(name, round(len(x) / SR, 2), "s")


def hit(f0, noise_tau, noise_band, body=1.0, bright=1.0, dur=0.22):
    x = tone(dur, f0, 0.020, 0.25) * 1.0 * body
    x += tone(dur, f0 * 2.15, 0.010) * 0.55 * bright
    x += tone(dur, 150, 0.030) * 0.6 * body
    x += bandpass(noise(dur), *noise_band) * env(dur, noise_tau) * 1.6 * bright
    return x


os.makedirs(OUT, exist_ok=True)
save("hit_flat", hit(540, 0.007, (1500, 6000)))
save("hit_topspin", hit(500, 0.018, (2000, 7000), body=0.9, bright=1.1))
save("hit_slice", hit(430, 0.035, (1800, 6500), body=0.7, bright=0.9, dur=0.28), 0.75)
save("hit_serve", hit(620, 0.006, (1800, 8000), body=1.2, bright=1.4, dur=0.3))
x = tone(0.3, 930, 0.03) + tone(0.3, 1720, 0.022) * 0.7 + tone(0.3, 2630, 0.012) * 0.4 + bandpass(noise(0.3), 800, 3000) * env(0.3, 0.02) * 0.6
save("hit_frame", x, 0.7)

x = tone(0.2, 230, 0.016, 0.3) + tone(0.2, 470, 0.010) * 0.6 + bandpass(noise(0.2), 300, 2500) * env(0.2, 0.008) * 0.9
save("bounce_hard", x, 0.85)
x = bandpass(noise(0.25), 200, 1800) * env(0.25, 0.030, 0.003) * 1.2 + tone(0.25, 150, 0.03) * 0.8
save("bounce_clay", x, 0.7)
x = tone(0.25, 125, 0.032) + bandpass(noise(0.25), 150, 1200) * env(0.25, 0.02, 0.003) * 0.5
save("bounce_grass", x, 0.7)
x = bandpass(noise(0.45), 80, 900) * env(0.45, 0.08, 0.004) + tone(0.45, 95, 0.07) * 0.8
x += bandpass(noise(0.45), 1500, 5000) * env(0.45, 0.05, 0.01) * 0.25
save("net", x, 0.8)
tt = t(0.22)
x = (np.sin(2 * np.pi * 760 * tt) + 0.4 * np.sin(2 * np.pi * 1520 * tt)) * np.minimum(tt / 0.008, 1) * np.minimum((0.22 - tt) / 0.03, 1)
save("call_out", x, 0.45)


def applause(dur, density, roar=0.0):
    n = int(dur * SR)
    x = np.zeros(n)
    # كل مصفّق له إيقاعه ونغمته
    people = int(density)
    for _ in range(people):
        rate = rng.uniform(3.2, 5.2)
        phase = rng.uniform(0, 1 / rate)
        fc = rng.uniform(900, 2600)
        amp = rng.uniform(0.3, 1.0)
        clap_len = int(0.03 * SR)
        clap = bandpass(rng.standard_normal(clap_len), fc * 0.6, fc * 1.9) * np.exp(-np.arange(clap_len) / (SR * rng.uniform(0.004, 0.009)))
        tcur = phase
        while tcur < dur:
            i = int(tcur * SR)
            j = min(i + clap_len, n)
            x[i:j] += clap[: j - i] * amp
            tcur += 1 / rate * rng.uniform(0.9, 1.1)
    tt = np.arange(n) / SR
    e = np.minimum(tt / 0.35, 1.0) * np.clip((dur - tt) / (dur * 0.55), 0, 1) ** 1.3
    x *= e
    if roar > 0:
        r = bandpass(rng.standard_normal(n), 350, 1500) * (0.6 + 0.4 * np.sin(2 * np.pi * 0.7 * tt + 1.0))
        r *= np.minimum(tt / 0.2, 1.0) * np.clip((dur * 0.8 - tt) / (dur * 0.6), 0, 1)
        x = x / (np.max(np.abs(x)) + 1e-9) + r / (np.max(np.abs(r)) + 1e-9) * roar
    return x


save("applause", applause(3.2, 110), 0.6)
save("applause_big", applause(5.0, 220, roar=0.5), 0.8)
n = 0.9
tt = t(n)
x = bandpass(noise(n), 250, 900) * np.minimum(tt / 0.12, 1) * np.exp(-tt / 0.35)
x += bandpass(noise(n), 900, 2200) * np.minimum(tt / 0.1, 1) * np.exp(-tt / 0.2) * 0.3
save("ooh", x, 0.5)

# همهمة الجمهور (حلقة متصلة)
dur = 8.0
n = int(dur * SR)
x = bandpass(rng.standard_normal(n), 120, 700) + 0.35 * bandpass(rng.standard_normal(n), 700, 2500)
tt = np.arange(n) / SR
x *= 0.75 + 0.25 * np.sin(2 * np.pi * tt / dur * 2) * np.sin(2 * np.pi * tt / dur * 5 + 1.3)
k = int(0.5 * SR)
x[:k] = x[:k] * np.linspace(0, 1, k) + x[-k:] * np.linspace(1, 0, k)
x = x[: n - k]
x = x / np.max(np.abs(x)) * 0.5
pcm = (x * 32767).astype(np.int16)
with wave.open(os.path.join(OUT, "crowd_ambience.wav"), "wb") as w:
    w.setnchannels(1)
    w.setsampwidth(2)
    w.setframerate(SR)
    w.writeframes(pcm.tobytes())
print("crowd_ambience", round(len(x) / SR, 2), "s")
