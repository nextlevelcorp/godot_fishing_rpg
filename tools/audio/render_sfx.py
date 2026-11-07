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

Run:  python3 tools/audio/render_sfx.py   (needs numpy). Deterministic: one fixed seed per sound.
"""
import math
import os
import struct
import wave
import zlib

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


def place_wrap(buf, snd, at):
    """Like place(), but what runs past the end wraps to the start: for seamless loops."""
    i = int(at * SR) % len(buf)
    n = len(snd)
    end = min(i + n, len(buf))
    buf[i:end] += snd[:end - i]
    if end - i < n:
        buf[:n - (end - i)] += snd[end - i:]


def make_loop(x, xf=0.03):
    """Makes x repeat without a click: the last `xf` seconds are cross-faded (equal power) into the
    start. The result is `xf` seconds shorter, so generate dur + xf and ask for dur."""
    n = int(round(xf * SR))
    ramp = np.linspace(0.0, 1.0, n)
    out = x[:-n].copy()
    out[:n] = x[:n] * np.sqrt(ramp) + x[-n:] * np.sqrt(1.0 - ramp)
    return out


def seed_for(name):
    """Every sound gets its own random stream, so changing one never changes another."""
    global rng
    rng = np.random.default_rng(zlib.crc32(name.encode()))


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
    buf = np.zeros(int(0.2 * SR))
    place(buf, bubble(0.12, 900, 5.0, 40, 0.8), 0.0)      # decays to nothing before it ends: no click
    return fade(buf, 0.002, 0.04)


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
    s *= np.clip((dur - t) / 0.06, 0.0, 1.0)             # the line hiss ends smoothly
    return fade(reverb(s, 0.08), 0.005, 0.05)


def reel_loop(dur=0.8, turns_per_s=2.5):
    """Spinning reel cranked: a soft gear whir with a click per gear tooth and a rotor rhythm.
    Periodic parts have a whole number of cycles in `dur` and wrap; the noise is cross-faded."""
    t = t_axis(dur)
    teeth = 12
    n_clicks = int(round(dur * turns_per_s * teeth))
    buf = np.zeros(len(t))
    for i in range(n_clicks):
        place_wrap(buf, metal_click(0.012, 2400 + rng.uniform(-80, 80), rng.uniform(0.18, 0.3)), i / n_clicks * dur)
    whir = make_loop(bandpass(rng.uniform(-1, 1, int(round((dur + 0.03) * SR))), 900, 2.0)) * 0.6
    rotor = 0.75 + 0.25 * np.sin(2 * math.pi * turns_per_s * t)
    hum = 0.25 * np.sin(2 * math.pi * 140 * t) + 0.12 * np.sin(2 * math.pi * 280 * t)
    return (buf + whir + hum * 0.4) * rotor


def drag_loop(dur=0.6, rate=42.0):
    """Clutch giving line: a ratchet of bright metallic clicks over a faint spool whine. The clicks
    are uneven in time and strength, as real pawls are, so it does not fuse into a steady buzz."""
    t = t_axis(dur)
    buf = np.zeros(len(t))
    n = int(round(dur * rate))
    for i in range(n):
        at = (i + rng.uniform(-0.3, 0.3)) / n * dur
        place_wrap(buf, metal_click(0.02, 2700 + rng.uniform(-250, 250), rng.uniform(0.4, 1.0)), at)
    whine = 0.07 * np.sin(2 * math.pi * 1650 * t) * (0.8 + 0.2 * np.sin(2 * math.pi * 5 * t))
    return buf + whine


def bell():
    """Small brass bite bell clipped to the rod tip: a few inharmonic partials, a short ring."""
    dur = 1.2
    t = t_axis(dur)
    s = np.zeros_like(t)
    for ratio, a, dec in ((1.0, 1.0, 5.0), (2.76, 0.5, 8.0), (5.40, 0.25, 12.0), (8.93, 0.12, 18.0)):
        s += a * np.sin(2 * math.pi * 2350 * ratio * t) * np.exp(-dec * t)
    s *= 1 - np.exp(-t * 3000)
    return fade(reverb(s, 0.1))


def snap():
    """The line parting: a sharp crack, a short whip of falling tone, almost no room tail."""
    dur = 0.7
    t = t_axis(dur)
    crack = highpass(rng.uniform(-1, 1, len(t)), 2500) * np.exp(-t * 160)
    f = 260 * (1 - 0.35 * np.minimum(t * 3, 1))
    ph = 2 * math.pi * np.cumsum(f) / SR
    twang = (np.sin(ph) + 0.5 * np.sin(2 * ph) + 0.25 * np.sin(3 * ph)) * np.exp(-t * 9)
    return fade(reverb(crack * 1.2 + twang * 0.3, 0.05), 0.0005, 0.05)


def gull(seed):
    """A herring gull's call: a quick rise then a long fall (kee-ow), an irregular pitch wobble, a
    rough amplitude grating around 70 Hz, a breathy noise part, and a harsh throat formant."""
    r = np.random.default_rng(seed)
    calls = int(r.integers(1, 4))
    out = np.zeros(int(2.0 * SR))
    at = 0.0
    scale = r.uniform(0.92, 1.12)
    for c in range(calls):
        d = r.uniform(0.32, 0.55)
        t = t_axis(d)
        k = t / d
        contour = 1000.0 + 1100.0 * np.exp(-(((k - 0.12) / 0.12) ** 2))
        f0 = contour * (1.0 - 0.45 * np.clip(k - 0.2, 0.0, 1.0)) * scale * (1.0 - 0.06 * c)
        wob = lowpass(r.normal(0.0, 1.0, len(t)), 45)
        f0 = f0 * (1.0 + 0.018 * wob / (np.std(wob) + 1e-9))
        ph = 2 * math.pi * np.cumsum(f0) / SR
        src = np.zeros_like(t)
        for h in range(1, 11):
            src += np.sin(h * ph + r.uniform(0, 6.28)) / h ** 1.1
        src *= 1.0 + 0.5 * np.sin(2 * math.pi * r.uniform(60, 80) * t)
        src += 0.3 * bandpass(r.uniform(-1, 1, len(t)), 3000, 1.0)
        voice = bandpass(src, 2000, 2.5) + 0.5 * bandpass(src, 3600, 3.0)
        env = np.sin(np.pi * k) ** 0.5 * np.clip(t / 0.02, 0.0, 1.0)
        place(out, voice * env * (1.0 - 0.12 * c), at)
        at += d + r.uniform(0.05, 0.15)
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


def engine_loop(dur=2.0, rate=5.5):
    """Single-cylinder diesel of a wooden fishing boat: the tak-tak of each firing, uneven as a
    slow engine is, over a hull hum. A whole number of firings wrap round, so it loops cleanly."""
    n = int(round(dur * rate))
    buf = np.zeros(int(dur * SR))
    for i in range(n):
        tt = t_axis(0.12)
        a = rng.uniform(0.75, 1.0)
        thump = (np.sin(2 * math.pi * 55 * tt) + 0.5 * np.sin(2 * math.pi * 110 * tt)) * np.exp(-tt * 40)
        knock = bandpass(rng.uniform(-1, 1, len(tt)), 700, 2.0) * np.exp(-tt * 70) * 0.6
        place_wrap(buf, (thump + knock) * a, (i + rng.uniform(-0.08, 0.08)) / n * dur)
    hum = make_loop(lowpass(rng.uniform(-1, 1, int(round((dur + 0.03) * SR))), 180)) * 0.6
    return buf + hum


def cicada_loop(dur=3.0):
    """Two cicadas, a little out of tune with each other, each a 5 kHz buzz pulsing about 25 times
    a second and swelling and fading. Every period holds whole cycles, so it loops cleanly."""
    t = t_axis(dur)
    out = np.zeros_like(t)
    for f0, mod, ph0, amp, swells in ((5200, 26, 0.0, 1.0, 1), (4850, 22, 1.3, 0.7, 2)):
        carrier = make_loop(bandpass(rng.uniform(-1, 1, int(round((dur + 0.03) * SR))), f0, 6.0)) + 0.6 * np.sin(2 * math.pi * f0 * t + ph0)
        pulse = (0.5 + 0.5 * np.sin(2 * math.pi * mod * t + ph0)) ** 2
        swell = 0.55 + 0.45 * np.sin(2 * math.pi * swells * t / dur + ph0)
        out += amp * carrier * pulse * swell
    return out


def cricket_loop(dur=2.0):
    """Night crickets: short 4.6 kHz chirps in pairs and threes."""
    t = t_axis(dur)
    buf = np.zeros(len(t))
    at = 0.05
    while at < dur - 0.2:
        for k in range(rng.integers(2, 4)):
            tt = t_axis(0.035)
            chirp = np.sin(2 * math.pi * 4600 * tt) * np.sin(math.pi * tt / 0.035)
            place(buf, chirp * rng.uniform(0.6, 1.0), at + k * 0.06)
        at += rng.uniform(0.35, 0.6)
    return buf


def lap():
    """A wavelet slapping a rock or a pier post: a soft low splash with a few bubbles."""
    buf = np.zeros(int(0.7 * SR))
    t = t_axis(0.7)
    buf += lowpass(rng.uniform(-1, 1, len(t)), 900) * np.exp(-t * 9) * (1 - np.exp(-t * 200))
    bubbles(buf, 6, 0.02, 0.3, 500, 1500, 0.25)
    return fade(reverb(buf, 0.15))


def horn():
    """Distant ferry horn: two low reed tones with harmonics, a slight vibrato, a puff of air at the
    start, a long fade to nothing (no step at the end), lots of air around it."""
    dur = 3.4
    t = t_axis(dur)
    vib = 1.0 + 0.004 * np.sin(2 * math.pi * 5.2 * t)
    s = np.zeros_like(t)
    for f, a in ((147.0, 1.0), (185.0, 0.7)):
        ph = 2 * math.pi * np.cumsum(f * vib) / SR
        for h in range(1, 7):
            s += a / h * np.sin(h * ph)
    breath = bandpass(rng.uniform(-1, 1, len(t)), 900, 1.2) * np.exp(-t * 6)
    env = np.minimum(t / 0.25, 1.0) * np.where(t > 1.8, np.exp(-(t - 1.8) * 3.2), 1.0) * np.clip((dur - t) / 0.4, 0.0, 1.0)
    return fade(reverb(lowpass(s, 1200) * env + breath * 0.3, 0.45, 0.86))


def rain_loop(dur=4.0):
    """Rain on water: about 900 drops a second, each a tiny ringing tick, a few big ones with a low
    thud, over a hiss of the finest drops. Drops are placed on a ring and convolved on a ring."""
    n = int(dur * SR)
    t = t_axis(dur)
    out = np.zeros(n)
    for count, fc, dec, amp in ((int(dur * 900), 3500.0, 900.0, 0.5), (int(dur * 120), 900.0, 350.0, 0.5)):
        imp = np.zeros(n)
        np.add.at(imp, rng.integers(0, n, count), rng.exponential(1.0, count))
        k = np.arange(int(0.02 * SR)) / SR
        kernel = np.sin(2 * math.pi * fc * k) * np.exp(-k * dec)
        out += np.real(np.fft.ifft(np.fft.fft(imp) * np.fft.fft(kernel, n))) * amp
    hiss = make_loop(highpass(lowpass(rng.uniform(-1, 1, int(round((dur + 0.03) * SR))), 9000), 2500)) * 0.6
    return (out + hiss) * (0.85 + 0.15 * np.sin(2 * math.pi * 2 * t / dur))


def wind_loop(dur=6.0):
    """Wind over the sea: pink noise through a band that rises in the gusts, a faint whistle in the
    strongest, gusts of whole periods so the loop is seamless."""
    t = t_axis(dur)
    base = make_loop(pink(int(round((dur + 0.03) * SR))))
    gust = 0.45 + 0.35 * np.sin(2 * math.pi * t / dur + 0.7) ** 2 + 0.2 * np.sin(2 * math.pi * 3 * t / dur) ** 2
    body = swept_bandpass(base, 350 + 650 * gust, 0.9) * gust
    whistle = bandpass(make_loop(rng.uniform(-1, 1, int(round((dur + 0.03) * SR)))), 820, 25.0) * 3.0 * np.clip(gust - 0.5, 0.0, 1.0)
    return body + whistle * 0.5


def step_wood():
    """A foot on pier planks: a low knock of the board, two plank resonances, a touch of heel."""
    t = t_axis(0.22)
    f = rng.uniform(85, 115)
    thump = np.sin(2 * math.pi * f * t) * np.exp(-t * 45)
    plank = (bandpass(rng.uniform(-1, 1, len(t)), rng.uniform(380, 480), 9.0) * 2.0
             + bandpass(rng.uniform(-1, 1, len(t)), rng.uniform(1000, 1250), 12.0)) * np.exp(-t * 28)
    heel = highpass(rng.uniform(-1, 1, len(t)), 1500) * np.exp(-t * 250) * 0.5
    return fade(reverb(thump * 0.8 + plank * 0.6 + heel, 0.08), 0.0005, 0.05)


def step_grit(soft):
    """A foot on gravel (soft = False) or sand (soft = True): a crunch of many grains and a thud."""
    d = 0.22
    s = np.zeros(int(d * SR))
    for _ in range(int(rng.integers(20, 32))):
        g = t_axis(0.004)
        place(s, rng.uniform(-1, 1, len(g)) * np.exp(-g * 900) * rng.uniform(0.3, 1.0), rng.uniform(0.0, 0.09))
    t = t_axis(d)
    thud = np.sin(2 * math.pi * 70 * t) * np.exp(-t * 60) * 0.6
    s = lowpass(s, 2500 if soft else 5000) + thud
    return fade(reverb(s, 0.06), 0.0005, 0.05)


def step_stone():
    """A foot on a stone quay: a hard tap with a short ring."""
    t = t_axis(0.2)
    tap = highpass(rng.uniform(-1, 1, len(t)), 1800) * np.exp(-t * 220)
    ring = bandpass(rng.uniform(-1, 1, len(t)), rng.uniform(1200, 1500), 8.0) * np.exp(-t * 40) * 1.5
    thud = np.sin(2 * math.pi * 90 * t) * np.exp(-t * 70) * 0.5
    return fade(reverb(tap * 0.6 + ring + thud, 0.08), 0.0005, 0.05)


def oar_stroke():
    """One stroke of a rowing boat: the rowlock creaks (stick-slip friction), the blade dips with a
    soft splash, pulls with a gurgle, and drips off when it lifts."""
    n = int(1.1 * SR)
    ct = t_axis(0.35)
    f = 340 + 120 * np.sin(math.pi * ct / 0.35) + 25 * np.sin(2 * math.pi * 31 * ct)
    ph = 2 * math.pi * np.cumsum(f) / SR
    saw = np.mod(ph / (2 * math.pi), 1.0) * 2 - 1
    creak = bandpass(saw + 0.5 * rng.uniform(-1, 1, len(ct)), 700, 3.0) * np.sin(math.pi * ct / 0.35) ** 1.5 * 0.5
    buf = np.zeros(n)
    place(buf, creak, 0.0)
    place(buf, splash(0.5, 1500, 0.06, 6, 700, 2200, 0.0) * 0.7, 0.32)
    place(buf, drips(0.4, 8) * 0.4, 0.78)
    return fade(buf, 0.002, 0.05)


def flop():
    """A landed fish flapping on wet planks or stone: six slaps, slower and weaker each time."""
    buf = np.zeros(int(1.6 * SR))
    at = 0.0
    amp = 1.0
    for i in range(6):
        t = t_axis(0.12)
        slap = (lowpass(rng.uniform(-1, 1, len(t)), 1400) * np.exp(-t * 55)
                + np.sin(2 * math.pi * 160 * t) * np.exp(-t * 50) * 0.7
                + highpass(rng.uniform(-1, 1, len(t)), 2500) * np.exp(-t * 180) * 0.4)
        place(buf, slap * amp, at)
        at += rng.uniform(0.12, 0.28) * (1 + 0.25 * i)
        amp *= 0.75
    return fade(reverb(buf, 0.1), 0.001, 0.05)


def main():
    seed_for("splash_small")
    save("splash_small", splash(0.9, 2200, 0.08, 14, 900, 3000, 0.0))      # float or bait lands
    seed_for("splash_big")
    save("splash_big", splash(1.4, 1800, 0.22, 45, 350, 2600, 0.6))       # fish crashes back, hook set
    seed_for("splash_exit")
    save("splash_exit", swish(0.35, 900, 3200, 0.3, 0.0) * 0.6)          # fish tears out of the water
    seed_for("drips")
    save("drips", drips(0.8, 22))                                       # water off a jumping or lifted fish
    seed_for("bloop")
    save("bloop", bloop())                                              # float pulled under
    seed_for("nibble")
    save("nibble", nibble())                                            # float twitches
    seed_for("cast")
    save("cast", swish(0.75, 220, 1900, 0.25, 0.12))                     # rod swish + line off the spool
    seed_for("strike")
    save("strike", swish(0.3, 300, 1800, 0.35, 0.0))                    # sweep to set the hook
    seed_for("reel_loop")
    save("reel_loop", reel_loop(), 0.6)
    seed_for("drag_loop")
    save("drag_loop", drag_loop(), 0.75)
    seed_for("snap")
    save("snap", snap())
    seed_for("bell")
    save("bell", bell(), 0.6)
    for i in range(3):
        save(f"gull_{i}", gull(40 + i), 0.7)
    seed_for("surf_loop")
    save("surf_loop", surf_loop(), 0.7)
    # every sound has its own seed (seed_for), so editing one never changes another
    seed_for("engine_loop")
    save("engine_loop", engine_loop(), 0.6)
    seed_for("cicada_loop")
    save("cicada_loop", cicada_loop(), 0.5)
    seed_for("cricket_loop")
    save("cricket_loop", cricket_loop(), 0.5)
    seed_for("lap")
    save("lap", lap(), 0.6)
    seed_for("horn")
    save("horn", horn(), 0.7)
    for v in range(3):
        seed_for("step_wood_%d" % v)
        save("step_wood_%d" % v, step_wood(), 0.7)
        seed_for("step_gravel_%d" % v)
        save("step_gravel_%d" % v, step_grit(False), 0.7)
        seed_for("step_sand_%d" % v)
        save("step_sand_%d" % v, step_grit(True), 0.6)
        seed_for("step_stone_%d" % v)
        save("step_stone_%d" % v, step_stone(), 0.7)
    seed_for("oar")
    save("oar", oar_stroke(), 0.7)
    seed_for("flop")
    save("flop", flop(), 0.75)
    seed_for("rain_loop")
    save("rain_loop", rain_loop(), 0.5)
    seed_for("wind_loop")
    save("wind_loop", wind_loop(), 0.6)


if __name__ == "__main__":
    main()
