#!/usr/bin/env python3
"""Nova Bot - procedural audio generator.

Synthesises every sound effect and music loop with numpy/scipy and writes
16-bit mono WAV files into ../assets/audio. No samples, no external assets.

    python3 tools/make_audio.py
"""
import os
import wave

import numpy as np
from scipy import signal

SR = 32000   # sound effects
MR = 22050   # music
HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.normpath(os.path.join(HERE, "..", "assets", "audio"))
os.makedirs(OUT, exist_ok=True)
rng = np.random.default_rng(1234)


# ----------------------------------------------------------------- helpers
def T(dur, sr=SR):
    return np.arange(int(dur * sr)) / sr


def osc(kind, f, n, sr=SR):
    f = np.broadcast_to(np.asarray(f, dtype=np.float64), (n,))
    p = np.cumsum(f) / sr
    if kind == "sine":
        return np.sin(2 * np.pi * p)
    if kind == "tri":
        return 2 * np.abs(2 * (p - np.floor(p + 0.5))) - 1
    if kind == "saw":
        return 2 * (p - np.floor(p + 0.5))
    if kind == "sq":
        return np.where((p % 1.0) < 0.5, 1.0, -1.0)
    raise ValueError(kind)


def sweep(f0, f1, n):
    return f0 * (f1 / f0) ** (np.arange(n) / max(1, n - 1))


def ex(n, k, sr=SR):
    return np.exp(-np.arange(n) / sr * k)


def atk(n, a, sr=SR):
    return np.minimum(1.0, np.arange(n) / max(1.0, a * sr))


def lp(x, fc, sr=SR, order=2):
    sos = signal.butter(order, min(fc, sr * 0.45) / (sr / 2), "low", output="sos")
    return signal.sosfilt(sos, x)


def hp(x, fc, sr=SR, order=2):
    sos = signal.butter(order, min(fc, sr * 0.45) / (sr / 2), "high", output="sos")
    return signal.sosfilt(sos, x)


def bp(x, lo, hi, sr=SR, order=2):
    sos = signal.butter(order, [lo / (sr / 2), min(hi, sr * 0.45) / (sr / 2)], "band", output="sos")
    return signal.sosfilt(sos, x)


def noise(n):
    return rng.standard_normal(n)


def swept_noise(dur, f0, f1, bw=0.7, sr=SR):
    n = int(dur * sr)
    src = noise(n)
    hop = 512
    win = np.hanning(2 * hop)
    out = np.zeros(n + 2 * hop)
    for i in range(0, n, hop):
        fc = f0 * (f1 / f0) ** (i / max(1, n))
        lo = max(60.0, fc * (1 - bw / 2))
        hi = min(sr * 0.45, fc * (1 + bw / 2))
        sos = signal.butter(2, [lo / (sr / 2), hi / (sr / 2)], "band", output="sos")
        seg = np.zeros(2 * hop)
        chunk = src[i:i + 2 * hop]
        seg[:len(chunk)] = chunk
        out[i:i + 2 * hop] += signal.sosfilt(sos, seg) * win
    return out[:n] * 2.0


def pad_to(x, n):
    y = np.zeros(n)
    y[:min(n, len(x))] = x[:n]
    return y


def mix_at(dst, src, start):
    start = int(start)
    if start >= len(dst):
        return
    end = min(len(dst), start + len(src))
    dst[start:end] += src[:end - start]


def declick(x, ms=3, sr=SR):
    k = max(1, int(ms * 0.001 * sr))
    x = x.copy()
    r = np.linspace(0, 1, k)
    x[:k] *= r
    x[-k:] *= r[::-1]
    return x


def echo(x, delay, fb, mix, sr, taps=6):
    y = x.copy()
    for k in range(1, taps + 1):
        y += mix * (fb ** (k - 1)) * np.roll(x, int(delay * sr * k))
    return y


def reverb(x, sr, decay=3.0, length=1.6, wet=0.2):
    n = len(x)
    m = int(length * sr)
    ir = noise(m) * np.exp(-np.arange(m) / sr * decay)
    ir = lp(ir, 5500, sr)
    ir /= np.sqrt(np.sum(ir ** 2)) + 1e-9
    irp = np.zeros(n)
    irp[:min(n, m)] = ir[:n]
    wetsig = np.fft.irfft(np.fft.rfft(x) * np.fft.rfft(irp), n)
    return x * (1 - wet) + wetsig * wet * 2.2


def save(name, x, sr=SR, peak=0.85):
    x = np.asarray(x, dtype=np.float64)
    m = np.max(np.abs(x)) + 1e-9
    x = x / m * peak
    data = (np.clip(x, -1, 1) * 32767).astype("<i2")
    path = os.path.join(OUT, name + ".wav")
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(sr)
        w.writeframes(data.tobytes())
    return path, len(x) / sr, float(np.max(np.abs(x)))


def bell(f, dur, k=9.0, sr=SR):
    n = int(dur * sr)
    t = np.arange(n) / sr
    return (np.sin(2 * np.pi * f * t) * np.exp(-t * k)
            + 0.35 * np.sin(2 * np.pi * f * 2.76 * t) * np.exp(-t * k * 1.8)
            + 0.18 * np.sin(2 * np.pi * f * 5.4 * t) * np.exp(-t * k * 2.6))


def midi(m):
    return 440.0 * 2 ** ((np.asarray(m, dtype=np.float64) - 69) / 12)


# ------------------------------------------------------------------- SFX
def sfx_ui_click():
    n = int(0.07 * SR); t = np.arange(n) / SR
    f = np.linspace(1100, 1500, n)
    return (osc("sine", f, n) * np.exp(-t * 45) + 0.3 * osc("sine", f * 2, n) * np.exp(-t * 70))


def sfx_ui_back():
    n = int(0.11 * SR); t = np.arange(n) / SR
    f = np.linspace(820, 470, n)
    return osc("sine", f, n) * np.exp(-t * 28)


def sfx_ui_confirm():
    a = int(0.08 * SR); b = int(0.2 * SR)
    x = np.zeros(a + b)
    ta = np.arange(a) / SR; tb = np.arange(b) / SR
    x[:a] += osc("sine", np.linspace(660, 990, a), a) * np.exp(-ta * 18)
    x[a - 400:a - 400 + b] += osc("sine", np.linspace(990, 1580, b), b) * np.exp(-tb * 12) * 1.1
    x[a - 400:a - 400 + b] += 0.25 * osc("sine", np.linspace(1980, 3160, b), b) * np.exp(-tb * 16)
    return x[:a + b - 400]


def sfx_jump():
    n = int(0.22 * SR); t = np.arange(n) / SR
    f = sweep(250, 680, n)
    return (osc("tri", f, n) * ex(n, 9) * atk(n, 0.004) + 0.25 * osc("sine", f * 2, n) * ex(n, 14))


def sfx_double_jump():
    n = int(0.3 * SR); t = np.arange(n) / SR
    f = sweep(420, 1250, n)
    x = osc("sine", f, n) * ex(n, 8) + 0.4 * osc("sine", f * 1.5, n) * ex(n, 11)
    x += 0.3 * hp(noise(n), 4000) * ex(n, 22) * 0.4
    return x * atk(n, 0.003)


def sfx_land():
    n = int(0.16 * SR)
    thump = osc("sine", sweep(160, 48, n), n) * ex(n, 26)
    puff = lp(noise(n), 1100) * ex(n, 38) * 0.7
    return thump + puff


def sfx_step():
    n = int(0.05 * SR)
    return hp(noise(n), 900) * ex(n, 90) * 0.6 + osc("sine", 190, n) * ex(n, 80) * 0.5


def sfx_spin():
    d = 0.42
    n = int(d * SR)
    w = swept_noise(d, 500, 2600, 0.9)
    env = np.sin(np.pi * np.arange(n) / n) ** 1.4
    tone = osc("sine", np.concatenate([sweep(320, 980, n // 2), sweep(980, 420, n - n // 2)]), n) * 0.25
    return (w * 0.9 + tone) * env


def sfx_dash():
    d = 0.28
    n = int(d * SR)
    w = swept_noise(d, 5200, 700, 1.0) * ex(n, 5) * atk(n, 0.01)
    s = osc("saw", sweep(520, 160, n), n)
    s = lp(s, 1600) * 0.35 * ex(n, 7)
    return w + s


def sfx_hover_loop():
    d = 0.9
    xf = int(0.12 * SR)
    n = int(d * SR) + xf
    base = lp(noise(n), 650) * 0.9 + bp(noise(n), 1400, 3800) * 0.28
    t = np.arange(n) / SR
    base += 0.25 * np.sin(2 * np.pi * 92 * t)
    base *= 0.85 + 0.15 * np.sin(2 * np.pi * 7 * t)
    body = base[:-xf].copy()
    tail = base[-xf:]
    w = np.linspace(0, 1, xf)
    body[:xf] = body[:xf] * w + tail * (1 - w)
    return body


def sfx_coin():
    n = int(0.34 * SR)
    x = np.zeros(n)
    mix_at(x, bell(1318.5, 0.34, 13), 0)
    mix_at(x, bell(1975.5, 0.3, 10) * 1.1, int(0.055 * SR))
    return x


def sfx_bot_rescue():
    d = 1.5
    n = int(d * SR)
    x = np.zeros(n)
    notes = [72, 76, 79, 84, 88]
    for i, m in enumerate(notes):
        mix_at(x, bell(midi(m), 0.9, 6) * (0.7 + 0.1 * i), int(i * 0.085 * SR))
    mix_at(x, bell(midi(84), 1.1, 3.5) * 0.6, int(0.45 * SR))
    mix_at(x, swept_noise(0.7, 3000, 9000, 0.9) * 0.15 * ex(int(0.7 * SR), 4), int(0.2 * SR))
    return x


def sfx_hurt():
    n = int(0.38 * SR); t = np.arange(n) / SR
    f = sweep(560, 105, n)
    s = lp(osc("saw", f, n), 2200) * (0.7 + 0.3 * np.sin(2 * np.pi * 28 * t))
    return s * ex(n, 6) * atk(n, 0.003) + hp(noise(n), 2500) * ex(n, 30) * 0.4


def sfx_die():
    n = int(0.95 * SR); t = np.arange(n) / SR
    f = sweep(480, 52, n)
    s = lp(osc("saw", f, n), 1800) * ex(n, 3.2) * 0.8 + osc("sine", f * 0.5, n) * ex(n, 3) * 0.6
    s += lp(noise(n), 1400) * ex(n, 14) * 0.7
    return s * atk(n, 0.004)


def sfx_enemy_pop():
    n = int(0.3 * SR)
    x = hp(noise(n), 1500) * ex(n, 28) * 0.8
    x += osc("sine", sweep(780, 190, n), n) * ex(n, 16)
    m = np.zeros(n)
    mix_at(m, bell(1050, 0.25, 18) * 0.4, int(0.02 * SR))
    return x + m


def sfx_crate():
    n = int(0.36 * SR)
    x = bp(noise(n), 350, 3200) * ex(n, 15) * 1.1
    x += osc("sine", sweep(210, 80, n), n) * ex(n, 20) * 0.8
    for k in range(5):
        c = int(rng.uniform(0.02, 0.2) * SR)
        mix_at(x, hp(noise(900), 1800) * ex(900, 60) * 0.5, c)
    return x


def sfx_bounce():
    n = int(0.5 * SR); t = np.arange(n) / SR
    f = 190 * (1 + 2.6 * np.exp(-t * 7)) * (1 + 0.03 * np.sin(2 * np.pi * 26 * t))
    s = osc("tri", f, n) * ex(n, 5.5) + 0.4 * osc("sine", f * 2, n) * ex(n, 9)
    return s * atk(n, 0.004)


def sfx_checkpoint():
    n = int(1.1 * SR)
    x = np.zeros(n)
    for i, m in enumerate([69, 73, 76, 81]):
        mix_at(x, bell(midi(m), 0.9, 5.5) * 0.8, int(i * 0.07 * SR))
    return x


def sfx_goal():
    d = 1.7
    n = int(d * SR); t = np.arange(n) / SR
    f = sweep(180, 1700, n)
    s = osc("sine", f, n) * (np.sin(np.pi * t / d) ** 1.5) * 0.7
    s += 0.35 * osc("tri", f * 2.01, n) * (np.sin(np.pi * t / d) ** 2)
    sp = np.zeros(n)
    for i in range(14):
        mix_at(sp, bell(rng.uniform(1800, 4200), 0.3, 14) * 0.25, int(rng.uniform(0.2, 1.4) * SR))
    return s + sp


def sfx_fanfare():
    d = 3.2
    n = int(d * SR)
    x = np.zeros(n)
    seq = [(0.0, 72, 0.16), (0.18, 72, 0.16), (0.36, 72, 0.16), (0.54, 76, 0.28), (0.9, 79, 0.28), (1.26, 84, 1.3)]
    for st, m, ln in seq:
        k = int(ln * SR)
        tt = np.arange(k) / SR
        f = midi(m)
        v = lp(osc("saw", f, k), 2600) * 0.5 + 0.4 * osc("sq", f, k) * 0.4
        v *= atk(k, 0.01) * np.exp(-tt * 1.6)
        mix_at(x, v, int(st * SR))
        mix_at(x, bell(f * 2, ln + 0.4, 4.5) * 0.35, int(st * SR))
    for st, m in [(1.26, 76), (1.26, 79), (1.26, 72)]:
        k = int(1.6 * SR)
        tt = np.arange(k) / SR
        mix_at(x, lp(osc("saw", midi(m - 12), k), 1500) * atk(k, 0.03) * np.exp(-tt * 1.4) * 0.35, int(st * SR))
    return reverb(x, SR, 3.0, 1.2, 0.18)


def sfx_shoot():
    n = int(0.24 * SR)
    return osc("sine", sweep(1100, 170, n), n) * ex(n, 11) + hp(noise(n), 3000) * ex(n, 40) * 0.25


def sfx_zap():
    n = int(0.28 * SR); t = np.arange(n) / SR
    buzz = lp(osc("saw", 118, n), 2200)
    gate = (np.sin(2 * np.pi * 45 * t) > -0.2).astype(float)
    return (buzz * 0.7 + bp(noise(n), 2000, 6000) * 0.6) * gate * ex(n, 7) * atk(n, 0.004)


def sfx_boss_hit():
    n = int(0.8 * SR)
    x = osc("sine", sweep(140, 38, n), n) * ex(n, 5) * 1.2
    x += lp(noise(n), 900) * ex(n, 14) * 0.9
    for f, a in [(523, 0.3), (1318, 0.22), (2093, 0.12)]:
        x += a * osc("sine", f, n) * ex(n, 8)
    return x * atk(n, 0.002)


def sfx_boss_slam():
    n = int(1.3 * SR)
    x = osc("sine", sweep(95, 28, n), n) * ex(n, 3.2) * 1.2
    x += lp(noise(n), 500) * ex(n, 4.5) * 0.9
    x += hp(noise(n), 2500) * ex(n, 30) * 0.3
    return x * atk(n, 0.002)


def sfx_boss_roar():
    n = int(1.2 * SR); t = np.arange(n) / SR
    f = 66 + 10 * np.sin(2 * np.pi * 4 * t) - 14 * t
    s = osc("saw", f, n) * (0.6 + 0.4 * np.sin(2 * np.pi * 23 * t))
    s = bp(s, 180, 1100) * 2.0 + osc("sine", f * 0.5, n) * 0.5
    return s * np.sin(np.pi * np.minimum(1, t / 1.2)) ** 0.6 * atk(n, 0.05)


def sfx_crumble():
    n = int(0.55 * SR)
    x = lp(noise(n), 700) * 0.5 * ex(n, 3)
    for k in range(18):
        c = int(rng.uniform(0.0, 0.45) * SR)
        mix_at(x, bp(noise(700), 400, 2600) * ex(700, 70) * rng.uniform(0.3, 0.9), c)
    return x


def sfx_whoosh():
    d = 0.34
    n = int(d * SR)
    return swept_noise(d, 350, 3600, 1.0) * (np.sin(np.pi * np.arange(n) / n) ** 1.2)


def sfx_switch():
    n = int(0.3 * SR)
    x = np.zeros(n)
    for i, f in enumerate([880, 1320]):
        k = int(0.09 * SR)
        tt = np.arange(k) / SR
        mix_at(x, lp(osc("sq", f, k), 3200) * np.exp(-tt * 28) * 0.7, int(i * 0.08 * SR))
    mix_at(x, bell(1760, 0.25, 12) * 0.5, int(0.08 * SR))
    return x


def sfx_warp():
    d = 0.65
    n = int(d * SR); t = np.arange(n) / SR
    f = sweep(140, 1400, n)
    s = osc("sine", f, n) * np.sin(np.pi * t / d) + 0.3 * osc("tri", f * 1.5, n) * np.sin(np.pi * t / d)
    return s + swept_noise(d, 1000, 6000, 0.9) * 0.15 * np.sin(np.pi * t / d)


def sfx_powerup():
    n = int(0.6 * SR)
    x = np.zeros(n)
    for i, m in enumerate([60, 64, 67, 72, 76]):
        mix_at(x, bell(midi(m), 0.4, 8) * 0.8, int(i * 0.055 * SR))
    return x


SFX = [
    ("ui_click", sfx_ui_click, 0.7), ("ui_back", sfx_ui_back, 0.7), ("ui_confirm", sfx_ui_confirm, 0.75),
    ("jump", sfx_jump, 0.65), ("double_jump", sfx_double_jump, 0.65), ("land", sfx_land, 0.7),
    ("step", sfx_step, 0.4), ("spin", sfx_spin, 0.75), ("dash", sfx_dash, 0.75), ("hover", sfx_hover_loop, 0.5),
    ("coin", sfx_coin, 0.7), ("bot_rescue", sfx_bot_rescue, 0.85), ("hurt", sfx_hurt, 0.85), ("die", sfx_die, 0.9),
    ("enemy_pop", sfx_enemy_pop, 0.85), ("crate", sfx_crate, 0.85), ("bounce", sfx_bounce, 0.8),
    ("checkpoint", sfx_checkpoint, 0.75), ("goal", sfx_goal, 0.85), ("fanfare", sfx_fanfare, 0.9),
    ("shoot", sfx_shoot, 0.6), ("zap", sfx_zap, 0.7), ("boss_hit", sfx_boss_hit, 0.95),
    ("boss_slam", sfx_boss_slam, 0.95), ("boss_roar", sfx_boss_roar, 0.9), ("crumble", sfx_crumble, 0.7),
    ("whoosh", sfx_whoosh, 0.55), ("switch", sfx_switch, 0.7), ("warp", sfx_warp, 0.75), ("powerup", sfx_powerup, 0.7),
]


# ------------------------------------------------------------- new SFX (v0.2)
def _tone(f0, f1, dur, kind="sine", k=8.0, a=0.003):
    n = int(dur * SR)
    return osc(kind, sweep(f0, f1, n), n) * ex(n, k) * atk(n, a)


def sfx_punch_swing():
    d = 0.16
    n = int(d * SR)
    return swept_noise(d, 900, 3800, 0.9) * np.sin(np.pi * np.arange(n) / n) ** 1.2 * 0.9


def sfx_punch_hit():
    n = int(0.2 * SR)
    thump = osc("sine", sweep(180, 55, n), n) * ex(n, 22) * 1.2
    crack = hp(noise(n), 1800) * ex(n, 45) * 0.8
    ring = osc("sq", 620, n) * ex(n, 40) * 0.12
    return thump + crack + ring


def sfx_charge():
    d = 0.75
    n = int(d * SR)
    t = np.arange(n) / SR
    f = sweep(220, 880, n)
    x = osc("saw", f, n) * 0.25 + osc("sine", f * 2, n) * 0.3
    x = lp(x, 2400) * (0.3 + 0.7 * t / d) * (1 + 0.3 * np.sin(2 * np.pi * 18 * t))
    return x


def sfx_battery_low():
    a = _tone(880, 880, 0.09, "sq", 18) * 0.5
    b = _tone(660, 660, 0.12, "sq", 14) * 0.5
    x = np.zeros(int(0.26 * SR))
    mix_at(x, lp(a, 3000), 0)
    mix_at(x, lp(b, 3000), int(0.11 * SR))
    return x


def sfx_power_down():
    d = 0.8
    n = int(d * SR)
    x = osc("saw", sweep(700, 60, n), n) * ex(n, 2.5)
    return lp(x, 1800) * 0.8


def sfx_shutdown():
    d = 1.4
    n = int(d * SR)
    t = np.arange(n) / SR
    x = osc("sine", sweep(520, 40, n), n) * ex(n, 1.6) + 0.4 * osc("sq", sweep(260, 20, n), n) * ex(n, 2.5)
    x *= 1 - 0.5 * (np.sin(2 * np.pi * 9 * t) > 0.6)
    return lp(x, 2200)


def sfx_battery_grab():
    x = np.zeros(int(0.45 * SR))
    for i, m in enumerate([76, 79, 83, 88]):
        mix_at(x, bell(midi(m), 0.3, 10) * 0.6, int(i * 0.06 * SR))
    return x


def sfx_battery_insert():
    n = int(0.25 * SR)
    clack = hp(noise(n), 2500) * ex(n, 60) + osc("sine", sweep(900, 300, n), n) * ex(n, 40) * 0.6
    thud = osc("sine", 120, n) * ex(n, 25) * 0.7
    return clack + thud


def sfx_battery_eject():
    d = 0.4
    n = int(d * SR)
    pop = osc("sine", sweep(200, 900, n), n) * ex(n, 14) * 0.6
    hiss = bp(noise(n), 2000, 7000) * ex(n, 7) * 0.5
    return pop + hiss + osc("sine", 90, n) * ex(n, 30) * 0.6


def sfx_hatch():
    d = 0.32
    n = int(d * SR)
    return bp(noise(n), 800, 3500) * ex(n, 8) * 0.6 + osc("sq", sweep(300, 500, n), n) * ex(n, 18) * 0.15


def sfx_clamp():
    n = int(0.18 * SR)
    return hp(noise(n), 3000) * ex(n, 55) * 0.9 + osc("sine", 420, n) * ex(n, 35) * 0.4


def sfx_charge_up():
    d = 0.9
    n = int(d * SR)
    t = np.arange(n) / SR
    f = sweep(300, 1600, n)
    x = osc("saw", f, n) * 0.3 + osc("sine", f * 1.5, n) * 0.4
    x = lp(x, 4000) * np.minimum(1, t / 0.05) * np.minimum(1, (d - t) / 0.15)
    sp = np.zeros(n)
    for i, m in enumerate([72, 76, 79, 84, 88]):
        mix_at(sp, bell(midi(m), 0.4, 9) * 0.4, int((0.1 + i * 0.12) * SR))
    return x + sp


def sfx_energy():
    a = bell(midi(88), 0.22, 14) * 0.7
    b = pad_to(bell(midi(95), 0.18, 18) * 0.3, len(a))
    return a + b


def sfx_explode():
    d = 0.9
    n = int(d * SR)
    boom = osc("sine", sweep(110, 32, n), n) * ex(n, 5.0) * 1.4
    crack = lp(noise(n), 2400) * ex(n, 6.0)
    debris = hp(noise(n), 3000) * ex(n, 10) * 0.4
    return boom + crack + debris


def sfx_deflect():
    n = int(0.3 * SR)
    return osc("sine", sweep(900, 2200, n), n) * ex(n, 12) * 0.6 + pad_to(bell(1400, 0.3, 12), n) * 0.5


def sfx_clang():
    n = int(0.5 * SR)
    t = np.arange(n) / SR
    x = np.zeros(n)
    for f, k in ((520, 7), (1310, 9), (2240, 12), (3170, 16)):
        x += np.sin(2 * np.pi * f * t) * np.exp(-t * k)
    return x * 0.5 + hp(noise(n), 2000) * ex(n, 60) * 0.6


def sfx_shatter():
    d = 0.7
    n = int(d * SR)
    x = hp(noise(n), 3500) * ex(n, 7) * 0.7
    t = np.arange(n) / SR
    for i in range(14):
        st = int(rng.uniform(0, 0.35) * SR)
        f = rng.uniform(2500, 7000)
        mix_at(x, np.sin(2 * np.pi * f * t[:int(0.12 * SR)]) * np.exp(-t[:int(0.12 * SR)] * 40) * 0.35, st)
    return x


def sfx_hopper_charge():
    d = 0.5
    n = int(d * SR)
    return osc("sq", sweep(120, 340, n), n) * ex(n, 3) * 0.3 + osc("sine", sweep(240, 680, n), n) * 0.3


def sfx_spider_hiss():
    d = 0.35
    n = int(d * SR)
    return bp(noise(n), 3000, 9000) * np.sin(np.pi * np.arange(n) / n) * 0.8


def sfx_throw():
    return sfx_punch_swing() * 0.8


def sfx_snow_hit():
    d = 0.3
    n = int(d * SR)
    return lp(noise(n), 1600) * ex(n, 16) + hp(noise(n), 4000) * ex(n, 30) * 0.4


def sfx_retract():
    d = 0.45
    n = int(d * SR)
    return lp(osc("saw", sweep(140, 90, n), n), 900) * np.sin(np.pi * np.arange(n) / n) * 0.6 + bp(noise(n), 400, 1500) * ex(n, 5) * 0.3


def sfx_lift():
    d = 0.6
    n = int(d * SR)
    return osc("sine", sweep(200, 420, n), n) * ex(n, 3) * 0.5


def sfx_crusher():
    d = 0.6
    n = int(d * SR)
    boom = osc("sine", sweep(90, 35, n), n) * ex(n, 7) * 1.4
    metal = pad_to(sfx_clang(), n) * 0.4
    return boom + metal + lp(noise(n), 900) * ex(n, 10) * 0.6


def sfx_crusher_warn():
    d = 0.5
    n = int(d * SR)
    t = np.arange(n) / SR
    return lp(noise(n), 500) * (0.5 + 0.5 * np.sin(2 * np.pi * 22 * t)) * 0.6 + osc("saw", 70, n) * 0.2


def sfx_toggle():
    return _tone(1200, 1600, 0.08, "sine", 30) * 0.5


def sfx_ice_crack():
    d = 0.4
    n = int(d * SR)
    x = np.zeros(n)
    for i in range(6):
        mix_at(x, hp(noise(int(0.03 * SR)), 2500) * rng.uniform(0.4, 1.0), int(rng.uniform(0, 0.3) * SR))
    return x + osc("sine", sweep(900, 300, n), n) * ex(n, 14) * 0.3


def sfx_wind():
    d = 1.4
    n = int(d * SR)
    x = swept_noise(d, 300, 1100, 1.2)
    return x * np.sin(np.pi * np.arange(n) / n) ** 0.8 * 0.8


def sfx_geyser():
    d = 1.0
    n = int(d * SR)
    x = bp(noise(n), 1200, 8000) * np.minimum(1, np.arange(n) / (0.04 * SR)) * ex(n, 2.0)
    return x + lp(noise(n), 300) * ex(n, 3) * 0.6


def sfx_flame():
    d = 0.8
    n = int(d * SR)
    x = lp(noise(n), 900) * np.minimum(1, np.arange(n) / (0.03 * SR)) * ex(n, 2.5)
    return x + bp(noise(n), 2000, 5000) * ex(n, 4) * 0.25


def sfx_meteor_fall():
    d = 1.1
    return swept_noise(d, 3000, 400, 0.8) * 0.8


def sfx_pylon():
    return bell(midi(76), 0.5, 6) * 0.8


def sfx_wrong():
    a = _tone(300, 280, 0.18, "sq", 8)
    b = _tone(220, 200, 0.28, "sq", 6)
    x = np.zeros(int(0.5 * SR))
    mix_at(x, lp(a, 1800), 0)
    mix_at(x, lp(b, 1800), int(0.2 * SR))
    return x


def sfx_puzzle_solved():
    x = np.zeros(int(1.2 * SR))
    for i, m in enumerate([72, 76, 79, 84, 79, 84, 88]):
        mix_at(x, bell(midi(m), 0.6, 6) * 0.6, int(i * 0.09 * SR))
    return x


def sfx_block_push():
    d = 0.35
    n = int(d * SR)
    return lp(noise(n), 700) * ex(n, 8) * 0.9 + osc("sine", 70, n) * ex(n, 14) * 0.6


def sfx_gate():
    d = 0.7
    n = int(d * SR)
    return osc("saw", sweep(180, 520, n), n) * ex(n, 3) * 0.25 + bp(noise(n), 800, 3000) * ex(n, 4) * 0.3


def sfx_target():
    a = bell(midi(84), 0.35, 10) * 0.6
    return a + pad_to(sfx_punch_hit(), len(a)) * 0.5


SFX += [
    ("punch_swing", sfx_punch_swing, 0.6), ("punch_hit", sfx_punch_hit, 0.85), ("charge", sfx_charge, 0.55),
    ("battery_low", sfx_battery_low, 0.6), ("power_down", sfx_power_down, 0.75), ("shutdown", sfx_shutdown, 0.8),
    ("battery_grab", sfx_battery_grab, 0.7), ("battery_insert", sfx_battery_insert, 0.8), ("battery_eject", sfx_battery_eject, 0.75),
    ("hatch", sfx_hatch, 0.6), ("clamp", sfx_clamp, 0.7), ("charge_up", sfx_charge_up, 0.75), ("energy", sfx_energy, 0.6),
    ("explode", sfx_explode, 0.9), ("deflect", sfx_deflect, 0.7), ("clang", sfx_clang, 0.7), ("shatter", sfx_shatter, 0.75),
    ("hopper_charge", sfx_hopper_charge, 0.5), ("spider_hiss", sfx_spider_hiss, 0.55), ("throw", sfx_throw, 0.55),
    ("snow_hit", sfx_snow_hit, 0.7), ("retract", sfx_retract, 0.55), ("lift", sfx_lift, 0.5), ("crusher", sfx_crusher, 0.9),
    ("crusher_warn", sfx_crusher_warn, 0.5), ("toggle", sfx_toggle, 0.45), ("ice_crack", sfx_ice_crack, 0.65),
    ("wind", sfx_wind, 0.6), ("geyser", sfx_geyser, 0.7), ("flame", sfx_flame, 0.7), ("meteor_fall", sfx_meteor_fall, 0.6),
    ("pylon", sfx_pylon, 0.7), ("wrong", sfx_wrong, 0.7), ("puzzle_solved", sfx_puzzle_solved, 0.8),
    ("block_push", sfx_block_push, 0.75), ("gate", sfx_gate, 0.6), ("target", sfx_target, 0.75),
]

# ----------------------------------------------------------------- music
CHORD = {"m": [0, 3, 7], "M": [0, 4, 7], "m7": [0, 3, 7, 10], "M7": [0, 4, 7, 11], "sus": [0, 5, 7]}


def v_pad(notes, dur, sr):
    n = int(dur * sr)
    t = np.arange(n) / sr
    x = np.zeros(n)
    for m in notes:
        f = midi(m)
        for det in (-0.07, 0.0, 0.08):
            x += osc("saw", f * 2 ** (det / 12), n, sr)
    x = lp(x, 1500, sr) / (len(notes) * 3)
    env = np.minimum(1, t / 0.45) * np.minimum(1, (dur - t) / 0.5)
    return x * np.clip(env, 0, 1)


def v_bass(m, dur, sr, bright=900):
    n = int(dur * sr)
    f = midi(m)
    x = osc("saw", f, n, sr) * 0.6 + osc("sine", f, n, sr) * 0.7
    x = lp(x, bright, sr)
    return x * ex(n, 5.0, sr) * atk(n, 0.004, sr) * np.minimum(1, (dur - np.arange(n) / sr) / 0.03)


def v_arp(m, dur, sr, k=7.0):
    return bell(midi(m), dur, k, sr)[:int(dur * sr)] * 0.8


def v_lead(m, dur, sr, bright=3200):
    n = int(dur * sr)
    t = np.arange(n) / sr
    f = midi(m) * (1 + 0.004 * np.sin(2 * np.pi * 5.2 * t) * np.minimum(1, t / 0.2))
    x = osc("saw", f, n, sr) * 0.55 + osc("sq", f, n, sr) * 0.25 + osc("sine", f, n, sr) * 0.5
    x = lp(x, bright, sr)
    env = atk(n, 0.012, sr) * (0.55 + 0.45 * np.exp(-t * 4.0)) * np.minimum(1, (dur - t) / 0.12)
    return x * np.clip(env, 0, 1)


def d_kick(sr):
    n = int(0.28 * sr)
    t = np.arange(n) / sr
    f = 48 + 120 * np.exp(-t * 28)
    return np.sin(2 * np.pi * np.cumsum(f) / sr) * np.exp(-t * 11) * 1.2


def d_snare(sr):
    n = int(0.22 * sr)
    t = np.arange(n) / sr
    return bp(noise(n), 1200, 7500, sr) * np.exp(-t * 20) * 0.9 + np.sin(2 * np.pi * 190 * t) * np.exp(-t * 28) * 0.5


def d_hat(sr, open_=False):
    n = int((0.22 if open_ else 0.05) * sr)
    t = np.arange(n) / sr
    return hp(noise(n), 7000, sr) * np.exp(-t * (14 if open_ else 70)) * 0.5


def render_music(name, bpm, bars, chords, lead, opts):
    sr = MR
    spb = 60.0 / bpm
    step = spb / 4.0
    L = int(round(bars * 4 * spb * sr))
    tail = int(4.0 * sr)
    buf = np.zeros(L + tail)
    root_shift = opts.get("shift", 0)
    st = lambda s: int(round(s * step * sr))

    for b in range(bars):
        root, q = chords[b % len(chords)]
        root += root_shift
        tones = [root + i for i in CHORD[q]]
        t0 = b * 16
        if opts.get("pad", True):
            mix_at(buf, v_pad([n + 12 for n in tones], 4 * spb, sr) * opts.get("pad_gain", 0.55), st(t0))
        bpat = opts.get("bass", "8th")
        if bpat == "8th":
            for s in range(0, 16, 2):
                note = root - 12 + (12 if (s % 8 == 6) else 0)
                mix_at(buf, v_bass(note, step * 1.8, sr, opts.get("bright", 900)) * 0.55, st(t0 + s))
        elif bpat == "driving":
            for s in range(16):
                note = root - 12 + (7 if s in (6, 14) else 0)
                mix_at(buf, v_bass(note, step * 0.9, sr, opts.get("bright", 1100)) * 0.5, st(t0 + s))
        elif bpat == "whole":
            mix_at(buf, v_bass(root - 12, 4 * spb * 0.97, sr, 500) * 0.55, st(t0))
        apat = opts.get("arp", "up")
        if apat != "off":
            span = tones + [n + 12 for n in tones] + [tones[0] + 24]
            pattern = {"up": [0, 1, 2, 3, 2, 1, 2, 4, 0, 1, 2, 3, 4, 3, 2, 1],
                       "sparse": [0, -1, 2, -1, 3, -1, 2, -1, 1, -1, 2, -1, 4, -1, 3, -1],
                       "swing": [0, -1, 2, 3, -1, 2, 1, -1, 0, -1, 2, 3, -1, 4, 3, -1]}[apat]
            for s, idx in enumerate(pattern):
                if idx < 0:
                    continue
                mix_at(buf, v_arp(span[idx % len(span)] + 12, step * 3.2, sr, opts.get("arp_k", 6.5)) * opts.get("arp_gain", 0.3), st(t0 + s))
        dr = opts.get("drums", "none")
        if dr != "none":
            kick_steps = {"soft": [0, 8], "four": [0, 4, 8, 12], "boss": [0, 3, 6, 8, 11, 14], "half": [0, 10]}[dr]
            for s in kick_steps:
                mix_at(buf, d_kick(sr) * opts.get("kick_gain", 0.55), st(t0 + s))
            if dr in ("four", "boss", "half"):
                for s in (4, 12):
                    mix_at(buf, d_snare(sr) * 0.55, st(t0 + s))
            hat_every = 2 if dr != "soft" else 4
            for s in range(0, 16, hat_every):
                mix_at(buf, d_hat(sr, s == 14 and dr != "soft") * 0.55, st(t0 + s))
    # lead phrases: (bar, beat, midi, beats)
    for (bar, beat, m, ln) in lead:
        if bar < bars:
            mix_at(buf, v_lead(m + root_shift, ln * spb * 0.96, sr, opts.get("lead_bright", 3200)) * opts.get("lead_gain", 0.4),
                   int(round((bar * 4 + beat) * spb * sr)))
    loop = buf[:L].copy()
    fold = min(tail, len(buf) - L)
    loop[:fold] += buf[L:L + fold]
    # effects (circular so the loop stays seamless)
    wet = echo(loop, step * 3, 0.45, 0.28, sr, 5)
    wet = reverb(wet, sr, opts.get("rev_decay", 3.2), 1.8, opts.get("rev", 0.2))
    wet = np.tanh(wet * 1.25) / np.tanh(1.25)
    return wet, sr


# Melodies are written for an A-minor world (Am F C G) and transposed with "shift".
MEL_A = []
for rep in range(2):
    base = rep * 4
    MEL_A += [
        (base + 0, 0.0, 76, 1.0), (base + 0, 1.0, 72, 0.5), (base + 0, 1.5, 74, 0.5), (base + 0, 2.0, 76, 1.0), (base + 0, 3.0, 79, 1.0),
        (base + 1, 0.0, 77, 1.5), (base + 1, 1.5, 76, 0.5), (base + 1, 2.0, 72, 1.0), (base + 1, 3.0, 69, 1.0),
        (base + 2, 0.0, 72, 1.0), (base + 2, 1.0, 76, 1.0), (base + 2, 2.0, 79, 1.5), (base + 2, 3.5, 76, 0.5),
        (base + 3, 0.0, 74, 1.5), (base + 3, 1.5, 71, 0.5), (base + 3, 2.0, 67 + (12 if rep else 0), 2.0),
    ]
MEL_A += [(8 + 0, 0.0, 81, 2.0), (8 + 0, 2.0, 79, 1.0), (8 + 0, 3.0, 76, 1.0),
          (8 + 1, 0.0, 77, 1.0), (8 + 1, 1.0, 81, 1.0), (8 + 1, 2.0, 84, 2.0),
          (8 + 2, 0.0, 83, 1.0), (8 + 2, 1.0, 79, 1.0), (8 + 2, 2.0, 76, 2.0),
          (8 + 3, 0.0, 74, 1.0), (8 + 3, 1.0, 79, 1.0), (8 + 3, 2.0, 83, 2.0)]

MEL_MENU = [(0, 0.0, 76, 3.0), (1, 0.0, 77, 3.0), (2, 0.0, 79, 3.0), (3, 0.0, 74, 3.0),
            (4, 0.0, 81, 3.0), (5, 0.0, 77, 2.0), (5, 2.0, 76, 2.0), (6, 0.0, 72, 2.0), (6, 2.0, 79, 2.0), (7, 0.0, 83, 4.0),
            (8, 0.0, 76, 3.0), (9, 0.0, 72, 3.0), (10, 0.0, 74, 3.0), (11, 0.0, 71, 3.0),
            (12, 0.0, 69, 2.0), (12, 2.0, 76, 2.0), (13, 0.0, 77, 2.0), (13, 2.0, 81, 2.0), (14, 0.0, 79, 2.0), (14, 2.0, 74, 2.0), (15, 0.0, 76, 4.0)]

MEL_BOSS = []
for rep in range(2):
    b = rep * 4
    MEL_BOSS += [(b, 0.0, 69, 0.5), (b, 0.5, 69, 0.5), (b, 1.0, 72, 0.5), (b, 1.5, 69, 0.5), (b, 2.0, 76, 1.0), (b, 3.0, 75, 1.0),
                 (b + 1, 0.0, 65, 0.5), (b + 1, 0.5, 65, 0.5), (b + 1, 1.0, 69, 0.5), (b + 1, 1.5, 65, 0.5), (b + 1, 2.0, 72, 1.0), (b + 1, 3.0, 71, 1.0),
                 (b + 2, 0.0, 62, 0.5), (b + 2, 0.5, 62, 0.5), (b + 2, 1.0, 65, 0.5), (b + 2, 1.5, 62, 0.5), (b + 2, 2.0, 69, 1.0), (b + 2, 3.0, 67, 1.0),
                 (b + 3, 0.0, 64, 1.0), (b + 3, 1.0, 68, 1.0), (b + 3, 2.0, 71, 1.0), (b + 3, 3.0, 68, 1.0)]

PROG_A = [(57, "m"), (53, "M"), (48, "M"), (55, "M")]          # Am F C G
PROG_BOSS = [(57, "m"), (53, "M"), (50, "m"), (52, "M")]       # Am F Dm E

MUSIC = [
    ("music_menu", 84, 16, PROG_A, MEL_MENU,
     dict(pad=True, pad_gain=0.7, bass="whole", arp="sparse", arp_gain=0.35, arp_k=4.5, drums="none", lead_gain=0.32, rev=0.3, lead_bright=2400)),
    ("music_world1", 118, 12, PROG_A, MEL_A,
     dict(shift=3, pad_gain=0.45, bass="8th", arp="up", arp_gain=0.26, drums="four", lead_gain=0.4, kick_gain=0.5)),
    ("music_world2", 106, 12, PROG_A, MEL_A,
     dict(shift=-2, pad_gain=0.6, bass="8th", arp="swing", arp_gain=0.34, arp_k=5.0, drums="half", lead_gain=0.38, lead_bright=2600, rev=0.26)),
    ("music_world3", 126, 12, PROG_A, MEL_A,
     dict(shift=-5, pad_gain=0.4, bass="driving", bright=1300, arp="sparse", arp_gain=0.3, drums="four", lead_gain=0.36, kick_gain=0.6, lead_bright=4200)),
    ("music_world4", 96, 12, PROG_A, MEL_MENU,
     dict(shift=2, pad=True, pad_gain=0.65, bass="whole", arp="up", arp_gain=0.34, arp_k=4.0, drums="soft", lead_gain=0.3, rev=0.34, lead_bright=2200)),
    ("music_world5", 128, 12, PROG_BOSS, MEL_A,
     dict(shift=0, pad_gain=0.45, bass="driving", bright=1200, arp="swing", arp_gain=0.28, drums="four", lead_gain=0.38, kick_gain=0.62, lead_bright=3800, rev=0.2)),
    ("music_boss", 142, 12, PROG_BOSS, MEL_BOSS,
     dict(shift=-2, pad_gain=0.35, bass="driving", bright=1500, arp="up", arp_gain=0.25, drums="boss", lead_gain=0.45, kick_gain=0.7, rev=0.14, lead_bright=4600)),
]


def main():
    import sys
    only = None
    for a in sys.argv[1:]:
        if a.startswith("--only="):
            only = set(a[7:].split(","))
    print("writing to", OUT)
    total = 0
    for name, fn, gain in SFX:
        if only is not None and name not in only:
            continue
        x = fn()
        x = declick(x)
        path, dur, pk = save(name, x, SR, gain)
        total += os.path.getsize(path)
        print(f"  sfx   {name:14s} {dur:5.2f}s peak {pk:.2f}")
    for name, bpm, bars, prog, lead, opts in MUSIC:
        if only is not None and name not in only:
            continue
        x, sr = render_music(name, bpm, bars, prog, lead, opts)
        path, dur, pk = save(name, x, sr, 0.72)
        total += os.path.getsize(path)
        print(f"  music {name:14s} {dur:6.2f}s peak {pk:.2f}  seam jump {abs(x[0]-x[-1]):.4f}")
    print("total KB:", total // 1024)


if __name__ == "__main__":
    main()
