#!/usr/bin/env python3
"""Renders the game's sound effects offline to assets/audio/*.wav (mono, 16-bit, 32 kHz).

Everything is synthesised from physical models, no recordings, so there is nothing to license:
  - water: an impact (filtered noise burst) plus many Minnaert bubbles. A bubble of radius r rings
    near f = 3.26 / r Hz (r in m) and its pitch rises as it nears the surface: f(t) = f0 (1 + s t).
    (van den Doel, "Physically based models for liquid sounds", ACM TAP 2005.)
  - swish: air noise through a band-pass whose centre sweeps with the rod tip speed.
  - reel and clutch: trains of metallic clicks, each a sum of damped inharmonic partials.
  - gulls: a harmonic glide shaped by two formant band-passes.
  - surf: pink noise under slow wave envelopes, each wave a low roar then a hissing wash; the loop
    is cross-faded so it repeats without a seam.
A small Schroeder reverb puts every sound in the same open-air space.

Run:  python3 tools/audio/render_sfx.py   (needs numpy). Deterministic: fixed seeds.
"""
import math
import os
import struct
import wave

import numpy as np

SR = 32000
OUT = os.path.join(os.path.dirname(__file__), "..", "..", "assets", "audio")
rng = np.random.default_rng(1234)


# ---------------------------------------------------------------- building blocks
def t_axis(dur):
    return np.arange(int(dur * SR)) / SR


def biquad(x, b0, b1, b2, a1, a2):
    y = np.zeros_like(x)
    x1 = x2 = y1 = y2 = 0.0
    for i in range(len(x)):
        xi = x[i]
        yi = b0 * xi + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2
        x2, x1, y2, y1 = x1, xi, y1, yi
        y[i] = yi
    return y


def bandpass(x, fc, q):
    w = 2 * math.pi * fc / SR
    alpha = math.sin(w) / (2 * q)
    a0 = 1 + alpha
    return biquad(x, alpha / a0, 0.0, -alpha / a0, -2 * math.cos(w) / a0, (1 - alpha) / a0)


def lowpass(x, fc, q=0.707):
    w = 2 * math.pi * fc / SR
    alpha = math.sin(w) / (2 * q)
    c = math.cos(w)
    a0 = 1 + alpha
    return biquad(x, (1 - c) / 2 / a0, (1 - c) / a0, (1 - c) / 2 / a0, -2 * c / a0, (1 - alpha) / a0)


def highpass(x, fc, q=0.707):
    w = 2 * math.pi * fc / SR
    alpha = math.sin(w) / (2 * q)
    c = math.cos(w)
    a0 = 1 + alpha
    return biquad(x, (1 + c) / 2 / a0, -(1 + c) / a0, (1 + c) / 2 / a0, -2 * c / a0, (1 - alpha) / a0)


def swept_bandpass(x, fc_curve, q):
    """State-variable band-pass with a centre frequency that changes per sample."""
    y = np.zeros_like(x)
    lp = bp = 0.0
    for i in range(len(x)):
        f = 2 * math.sin(math.pi * min(fc_curve[i], SR * 0.22) / SR)
        lp += f * bp
        hp = x[i] - lp - bp / q
        bp += f * hp
        y[i] = bp
    return y


def pink(n):
    """Voss-McCartney-ish pink noise from summed octave-held white noise."""
    out = np.zeros(n)
    for k in range(8):
        step = 2 ** k
        vals = rng.uniform(-1, 1, n // step + 2)
        out += np.repeat(vals, step)[:n]
    return out / 8


def bubble(dur, f0, rise, decay, amp):
    t = t_axis(dur)
    f = f0 * (1 + rise * t)
    ph = 2 * math.pi * np.cumsum(f) / SR
    env = np.exp(-decay * t) * (1 - np.exp(-t * 4000))
    return amp * np.sin(ph) * env


def place(buf, snd, at):
    i = int(at * SR)
    if i >= len(buf):
        return
    n = min(len(snd), len(buf) - i)
    buf[i:i + n] += snd[:n]


def bubbles(buf, count, t0, t1, fmin, fmax, amp):
    for _ in range(count):
        r_f = math.exp(rng.uniform(math.log(fmin), math.log(fmax)))
        d = rng.uniform(0.03, 0.09) * (1200 / r_f) ** 0.5
        place(buf, bubble(d, r_f, rng.uniform(0.5, 3.0) / d, rng.uniform(25, 60) * (r_f / 1000) ** 0.4,
                          amp * rng.uniform(0.3, 1.0) * (1000 / r_f) ** 0.3), rng.uniform(t0, t1))


def reverb(x, wet=0.18, room=0.78):
    """Schroeder: four combs in parallel, two all-passes in series. Open air: short and light."""
    combs = [1116, 1188, 1277, 1356]
    scale = SR / 44100
    out = np.zeros(len(x) + int(0.6 * SR))
    xin = np.concatenate([x, np.zeros(int(0.6 * SR))])
    for d in combs:
        d = int(d * scale)
        buf = np.zeros(len(xin))
        for i in range(len(xin)):
            buf[i] = xin[i] + (room * buf[i - d] if i >= d else 0.0)
        out += buf
    out /= len(combs)
    for d in (556, 441):
        d = int(d * scale)
        y = np.zeros(len(out))
        for i in range(len(out)):
            delayed = out[i - d] if i >= d else 0.0
            yd = y[i - d] if i >= d else 0.0
            y[i] = -0.5 * out[i] + delayed + 0.5 * yd
        out = y
    res = xin * (1 - wet) + out * wet
    # trim the silent tail
    thresh = 1e-4 * np.max(np.abs(res))
    nz = np.nonzero(np.abs(res) > thresh)[0]
    return res[: nz[-1] + 1] if len(nz) else res


def fade(x, fin=0.002, fout=0.02):
    n_in = max(1, int(fin * SR))
    n_out = max(1, int(fout * SR))
    x[:n_in] *= np.linspace(0, 1, n_in)
    x[-n_out:] *= np.linspace(1, 0, n_out)
    return x


def save(name, x, peak=0.89):
    x = np.asarray(x, dtype=float)
    m = np.max(np.abs(x))
    if m > 0:
        x = x / m * peak
    os.makedirs(OUT, exist_ok=True)
    path = os.path.join(OUT, name + ".wav")
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(b"".join(struct.pack("<h", int(max(-1, min(1, v)) * 32767)) for v in x))
    print(f"{name}.wav  {len(x) / SR:.2f} s")


def metal_click(dur=0.025, base=3100.0, amp=1.0):
    t = t_axis(dur)
    s = np.zeros_like(t)
    for ratio, a, dec in ((1.0, 1.0, 260), (1.52, 0.6, 330), (2.11, 0.35, 420), (2.93, 0.2, 520)):
        s += a * np.sin(2 * math.pi * base * ratio * t) * np.exp(-dec * t)
    s += rng.uniform(-1, 1, len(t)) * np.exp(-t * 900) * 0.6
    return s * amp


# ---------------------------------------------------------------- sounds
def splash(dur, impact_fc, body_len, n_bub, fmin, fmax, thump):
    buf = np.zeros(int(dur * SR))
    n = len(buf)
    t = t_axis(dur)
    noise = rng.uniform(-1, 1, n)
    # impact: a short broadband crack
    crack = highpass(noise, 1500) * np.exp(-t * 90)
    # body: water sheet, band-passed noise falling in pitch
    fc = impact_fc * np.exp(-t * 3.0) + 350
    body = swept_bandpass(noise, fc, 1.3) * np.exp(-t / body_len) * (1 - np.exp(-t * 400))
    buf += lowpass(crack, 7000) * 0.5 + lowpass(body, 4500) * 1.4
    if thump > 0:
        buf += thump * np.sin(2 * math.pi * (95 - 30 * t) * t) * np.exp(-t * 18)
    bubbles(buf, n_bub, 0.01, dur * 0.6, fmin, fmax, 0.35)
    return fade(reverb(buf, 0.12), 0.001, 0.05)


def drips(dur, count):
    buf = np.zeros(int(dur * SR))
    bubbles(buf, count, 0.0, dur * 0.8, 1800, 4500, 0.4)
    return fade(reverb(buf, 0.1))


def bloop():
    buf = np.zeros(int(0.35 * SR))
    place(buf, bubble(0.16, 330, 4.5, 24, 1.0), 0.0)
    place(buf, bubble(0.08, 620, 6.0, 40, 0.35), 0.05)
    t = t_axis(0.35)
    buf += lowpass(rng.uniform(-1, 1, len(buf)), 500) * np.exp(-t * 35) * 0.5
    return fade(reverb(buf, 0.1))


def nibble():
    buf = np.zeros(int(0.15 * SR))
    place(buf, bubble(0.05, 900, 5.0, 70, 0.8), 0.0)
    return fade(buf)


def swish(dur, f_lo, f_hi, peak_at, line_hiss):
    t = t_axis(dur)
    k = t / dur
    shape = np.where(k < peak_at, (k / peak_at) ** 2, np.exp(-(k - peak_at) * 9))
    fc = f_lo + (f_hi - f_lo) * shape
    noise = rng.uniform(-1, 1, len(t))
    s = lowpass(swept_bandpass(noise, fc, 1.6), f_hi * 1.4) * shape
    if line_hiss > 0:
        hiss = highpass(rng.uniform(-1, 1, len(t)), 5000) * np.clip((k - peak_at) * 3, 0, 1) * np.exp(-(k - peak_at).clip(0) * 4)
        flutter = 1 + 0.3 * np.sin(2 * math.pi * 55 * t)
        s += lowpass(hiss, 9000) * flutter * line_hiss
    return fade(reverb(s, 0.08), 0.005, 0.05)


def reel_loop(dur=0.8, turns_per_s=2.5):
    """Spinning reel cranked: a soft gear whir with a click per gear tooth and a rotor rhythm."""
    t = t_axis(dur)
    buf = np.zeros(len(t))
    teeth = 12
    rate = turns_per_s * teeth
    n_clicks = int(dur * rate)
    for i in range(n_clicks):
        place(buf, metal_click(0.012, 2400 + rng.uniform(-80, 80), 0.25), i / rate)
    whir = bandpass(rng.uniform(-1, 1, len(t)), 900, 2.0) * 0.6
    rotor = 0.75 + 0.25 * np.sin(2 * math.pi * turns_per_s * t)
    hum = 0.25 * np.sin(2 * math.pi * 140 * t) + 0.12 * np.sin(2 * math.pi * 280 * t)
    s = (buf + whir + hum * 0.4) * rotor
    return s  # looped: no fade


def drag_loop(dur=0.6, rate=42.0):
    """Clutch giving line: a fast ratchet of bright metallic clicks over a spool whine."""
    t = t_axis(dur)
    buf = np.zeros(len(t))
    for i in range(int(dur * rate)):
        place(buf, metal_click(0.02, 2700 + rng.uniform(-150, 150), rng.uniform(0.7, 1.0)), i / rate + rng.uniform(0, 0.002))
    whine = 0.15 * np.sin(2 * math.pi * 1650 * t) * (0.8 + 0.2 * np.sin(2 * math.pi * 7 * t))
    return buf + whine


def snap():
    dur = 0.9
    t = t_axis(dur)
    crack = highpass(rng.uniform(-1, 1, len(t)), 2500) * np.exp(-t * 120)
    f = 260 * (1 - 0.35 * np.minimum(t * 3, 1))
    ph = 2 * math.pi * np.cumsum(f) / SR
    twang = (np.sin(ph) + 0.5 * np.sin(2 * ph) + 0.25 * np.sin(3 * ph)) * np.exp(-t * 7)
    return fade(reverb(crack * 1.2 + twang * 0.35, 0.15))


def gull(seed):
    r = np.random.default_rng(seed)
    calls = r.integers(1, 4)
    out = np.zeros(int(1.6 * SR))
    at = 0.0
    for _ in range(calls):
        d = r.uniform(0.28, 0.45)
        t = t_axis(d)
        k = t / d
        f0 = r.uniform(1100, 1400) * (1 + 0.25 * np.sin(np.pi * np.minimum(k * 1.4, 1)))
        f0 *= 1 - 0.3 * k
        ph = 2 * math.pi * np.cumsum(f0) / SR
        src = np.zeros_like(t)
        for h in range(1, 9):
            src += np.sin(h * ph) / h
        src += 0.15 * r.uniform(-1, 1, len(t))
        voice = bandpass(src, 2600, 3.0) * 1.0 + bandpass(src, 4200, 4.0) * 0.6
        env = np.sin(np.pi * k) ** 0.6
        place(out, voice * env, at)
        at += d + r.uniform(0.06, 0.18)
    return fade(reverb(out[: int((at + 0.1) * SR)], 0.3, 0.84))


def surf_loop(dur=16.0):
    n = int(dur * SR)
    t = t_axis(dur)
    base = lowpass(pink(n), 700) * 0.5
    roar = np.zeros(n)
    hiss_env = np.zeros(n)
    at = 0.0
    while at < dur:
        period = rng.uniform(3.5, 5.5)
        wt = t - at
        swell = np.where((wt > 0) & (wt < period), np.sin(np.pi * np.clip(wt / 1.6, 0, 1)) ** 2, 0.0)
        wash = np.where(wt > 1.2, np.exp(-(wt - 1.2) * 1.3), 0.0) * (wt < period + 2)
        roar += swell * rng.uniform(0.6, 1.0)
        hiss_env += wash * rng.uniform(0.5, 0.9)
        at += period
    low = lowpass(pink(n), 400) * (0.35 + 0.65 * roar)
    hiss = bandpass(rng.uniform(-1, 1, n), 3500, 0.7) * hiss_env * 0.35
    lap = np.zeros(n)
    bubbles(lap, int(dur * 6), 0, dur, 600, 3000, 0.05)
    s = base * 0.4 + low + hiss + lap
    # seamless loop: drop the first second and cross-fade it into the end, so the last sample
    # leads straight into the first one.
    x = int(1.0 * SR)
    ramp = np.linspace(0, 1, x)
    out = s[x:].copy()
    out[-x:] = s[-x:] * (1 - ramp) + s[:x] * ramp
    return out


def main():
    save("splash_small", splash(0.9, 2200, 0.08, 14, 900, 3000, 0.0))      # float or bait lands
    save("splash_big", splash(1.4, 1800, 0.22, 45, 350, 2600, 0.6))       # fish crashes back, hook set
    save("splash_exit", swish(0.35, 900, 3200, 0.3, 0.0) * 0.6)          # fish tears out of the water
    save("drips", drips(0.8, 22))                                       # water off a jumping or lifted fish
    save("bloop", bloop())                                              # float pulled under
    save("nibble", nibble())                                            # float twitches
    save("cast", swish(0.75, 220, 1900, 0.25, 0.12))                     # rod swish + line off the spool
    save("strike", swish(0.3, 300, 1800, 0.35, 0.0))                    # sweep to set the hook
    save("reel_loop", reel_loop(), 0.6)
    save("drag_loop", drag_loop(), 0.75)
    save("snap", snap())
    for i in range(3):
        save(f"gull_{i}", gull(40 + i), 0.7)
    save("surf_loop", surf_loop(), 0.7)


if __name__ == "__main__":
    main()
