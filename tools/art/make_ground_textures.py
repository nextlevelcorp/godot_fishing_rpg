#!/usr/bin/env python3
"""Paints the seamless ground textures for the top-down shore and town views. Same output every run.

    python3 tools/art/make_ground_textures.py [--out DIR] [--sheet PATH]

Writes seven 256x256 opaque RGBA PNGs to assets/art/ground/:
  sand.png      warm beach sand: soft dunes, fine grain, a few shell and pebble flecks
  pebbles.png   rounded grey/brown pebbles on darker grit, lit from the top-left
  rock.png      weathered rock: cracks, warm and cool lichen patches, low contrast
  cobble.png    harbour quay cobbles (Arnavut kaldirimi) with mortar gaps
  planks.png    weathered pier planks running horizontally, 6 per tile, nails, gaps
  concrete.png  bridge deck / quay concrete: mottling, faint expansion joints, stains
  grass.png     dry Mediterranean grass tufts on ochre earth (town ground)

Style: smooth and painted (docs/ART_BRIEF_AI.md: hand-painted, light from the top-left, NOT pixel
art). The tiles are mid-value and low-saturation on purpose: the game multiplies them by the spot's
colour (modulate), so they carry shape and light, and the spot carries the hue.

Seamless by construction: every noise is made on a torus (FFT spectral noise, FFT blur, wrapped
Voronoi distances, np.roll gradients, stamps with wrapped indices, strokes drawn at every wrap
offset). The script then measures it: for each tile, the mean difference between the wrapped edge
columns (rows) over the mean difference between interior neighbours. A real seam shows up as a ratio
well above 1; the script fails if any ratio is over 1.5.

Contact sheet: every tile repeated 2x2, written outside the project by default
(/tmp/ground_sheet/ground_sheet.png) so it is never committed by mistake. Look at it before
committing. Needs numpy and Pillow. Fixed seeds, runs in a few seconds.
"""
import argparse
import os
import sys
import time

import numpy as np
from PIL import Image, ImageDraw, ImageFont

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..")
OUT = os.path.join(ROOT, "assets", "art", "ground")
SHEET = "/tmp/ground_sheet/ground_sheet.png"

S = 256                                         # tile size in pixels
SEAM_MAX = 1.5                                  # wrapped-edge / interior neighbour difference
LIGHT = np.array([-1.0, -1.0, 1.6]) / np.linalg.norm([-1.0, -1.0, 1.6])   # top-left sun, y down
FLAT = LIGHT[2]                                 # n.L of a flat surface

YY, XX = np.mgrid[0:S, 0:S].astype(np.float64)


# ---------------------------------------------------------------- torus primitives
def wrap(d, n=S):
    """Shortest signed distance on a ring of length n."""
    return (d + n * 0.5) % n - n * 0.5


def noise(rng, lo, hi, beta=1.0, stretch=(1.0, 1.0), rotate=0.0, n=S):
    """Band-limited spectral noise on the torus (periodic by construction), mean 0, std 1.

    lo, hi: soft band edges in cycles per tile; beta: amplitude falls as f^-beta;
    stretch: frequency weights (a large x weight makes features long in x); rotate: radians.
    """
    white = rng.standard_normal((n, n))
    fy = np.fft.fftfreq(n)[:, None] * n
    fx = np.fft.fftfreq(n)[None, :] * n
    c, s = np.cos(rotate), np.sin(rotate)
    fu = (fx * c + fy * s) * stretch[0]
    fv = (-fx * s + fy * c) * stretch[1]
    f = np.hypot(fu, fv)
    amp = np.zeros_like(f)
    nz = f > 0
    amp[nz] = f[nz] ** (-beta)
    if lo > 0:
        amp *= 1.0 - np.exp(-(f / lo) ** 2)
    amp *= np.exp(-(f / hi) ** 2)
    out = np.real(np.fft.ifft2(np.fft.fft2(white) * amp))
    out -= out.mean()
    return out / (out.std() + 1e-12)


def blur(a, sigma):
    """Gaussian blur on the torus (FFT), for 2-D or H x W x C arrays of any square size."""
    if sigma <= 0:
        return a
    h, w = a.shape[:2]
    fy = np.fft.fftfreq(h)[:, None]
    fx = np.fft.fftfreq(w)[None, :]
    g = np.exp(-2.0 * (np.pi * sigma) ** 2 * (fx * fx + fy * fy))
    if a.ndim == 3:
        return np.real(np.fft.ifft2(np.fft.fft2(a, axes=(0, 1)) * g[..., None], axes=(0, 1)))
    return np.real(np.fft.ifft2(np.fft.fft2(a) * g))


def sample(field, x, y):
    """Bilinear lookup with wrapped indices (for domain warping)."""
    n = field.shape[0]
    x0 = np.floor(x)
    y0 = np.floor(y)
    tx = x - x0
    ty = y - y0
    x0 = x0.astype(np.int64) % n
    y0 = y0.astype(np.int64) % n
    x1 = (x0 + 1) % n
    y1 = (y0 + 1) % n
    return (field[y0, x0] * (1 - tx) * (1 - ty) + field[y0, x1] * tx * (1 - ty)
            + field[y1, x0] * (1 - tx) * ty + field[y1, x1] * tx * ty)


def grad(h):
    """Central differences with wrap-around."""
    hx = (np.roll(h, -1, axis=1) - np.roll(h, 1, axis=1)) * 0.5
    hy = (np.roll(h, -1, axis=0) - np.roll(h, 1, axis=0)) * 0.5
    return hx, hy


def lambert(h):
    """n.L - flat for a height field in pixel units: 0 on flat ground, + facing the top-left sun."""
    hx, hy = grad(h)
    nl = (-hx * LIGHT[0] - hy * LIGHT[1] + LIGHT[2]) / np.sqrt(hx * hx + hy * hy + 1.0)
    return nl - FLAT


def cast_shadow(h, steps=6, drop=1.0):
    """How far a point sits below the line to the sun (top-left), in height units, wrapped."""
    s = np.zeros_like(h)
    for t in range(1, steps + 1):
        s = np.maximum(s, np.roll(h, (t, t), axis=(0, 1)) - h - drop * t * 1.414)
    return s


def smoothstep(e0, e1, x):
    t = np.clip((x - e0) / (e1 - e0), 0.0, 1.0)
    return t * t * (3.0 - 2.0 * t)


def luminance(rgb):
    return rgb[..., 0] * 0.2126 + rgb[..., 1] * 0.7152 + rgb[..., 2] * 0.0722


def paint(img, r, q=6.0, sectors=8, eps=1e-5):
    """Painterly filter: generalized (sector) Kuwahara on the torus. Eight soft, overlapping
    Gaussian wedges around each pixel; the pixel takes the means of the calmest wedges. Grain
    turns into smooth brush patches and edges stay. FFT convolution, so it wraps exactly."""
    n = img.shape[0]
    g1 = np.arange(n, dtype=np.float64)
    dx = wrap(g1[None, :], n) + 0.0 * g1[:, None]
    dy = wrap(g1[:, None], n) + 0.0 * g1[None, :]
    rr = np.hypot(dx, dy)
    th = np.arctan2(dy, dx)
    gauss = np.exp(-rr ** 2 / (2.0 * (0.5 * r) ** 2)) * (rr <= r * 1.2)
    lum = luminance(img)
    f_img = np.fft.fft2(img, axes=(0, 1))
    f_l = np.fft.fft2(lum)
    f_l2 = np.fft.fft2(lum * lum)
    means = []
    logw = []
    for i in range(sectors):
        wedge = np.clip(np.cos(th - 2.0 * np.pi * i / sectors), 0.0, 1.0) ** 4
        wedge[0, 0] = 1.0
        k = gauss * wedge
        kf = np.fft.fft2(k / k.sum())
        m = np.real(np.fft.ifft2(f_img * kf[..., None], axes=(0, 1)))
        ml = np.real(np.fft.ifft2(f_l * kf))
        var = np.maximum(np.real(np.fft.ifft2(f_l2 * kf)) - ml * ml, 0.0)
        means.append(m)
        logw.append(-0.5 * q * np.log(eps + var))
    logw = np.array(logw)
    w = np.exp(logw - logw.max(axis=0))
    return np.einsum("shw,shwc->hwc", w, np.array(means)) / w.sum(axis=0)[..., None]


def posterize(x, step, soft=0.4):
    """Soft staircase: smooth values settle into painted bands of height step."""
    q = x / step
    base = np.floor(q)
    return (base + smoothstep(0.5 - soft * 0.5, 0.5 + soft * 0.5, q - base)) * step


def mix(a, b, t):
    t = np.asarray(t)
    if t.ndim == 2:
        t = t[..., None]
    return a + (b - a) * t


def col(r, g, b):
    return np.array([r, g, b], dtype=np.float64)


def fill(c):
    return np.broadcast_to(c, (S, S, 3)).copy()


# ---------------------------------------------------------------- Voronoi on the torus
def voronoi(pts, x, y):
    """Nearest seed index and the wrapped offset from that seed, for every pixel."""
    best = np.full(x.shape, np.inf)
    idx = np.zeros(x.shape, np.int64)
    for i, (px, py) in enumerate(pts):
        d2 = wrap(x - px) ** 2 + wrap(y - py) ** 2
        m = d2 < best
        best[m] = d2[m]
        idx[m] = i
    ax = wrap(x - pts[idx, 0])
    ay = wrap(y - pts[idx, 1])
    return idx, ax, ay


def border(pts, x, y, idx, ax, ay, soft=0.0):
    """Distance to the own cell's border (exact bisector distance); soft > 0 rounds the corners."""
    a2 = ax * ax + ay * ay
    acc = np.zeros(x.shape) if soft else np.full(x.shape, np.inf)
    for j, (px, py) in enumerate(pts):
        bx = wrap(x - px)
        by = wrap(y - py)
        den = 2.0 * np.sqrt((ax - bx) ** 2 + (ay - by) ** 2)
        d = (bx * bx + by * by - a2) / np.maximum(den, 1e-6)
        d = np.where(idx == j, np.inf, d)
        if soft:
            acc += np.exp(-d / soft)
        else:
            acc = np.minimum(acc, d)
    if soft:
        return -soft * np.log(np.maximum(acc, 1e-300))
    return acc


def lloyd(pts, iters):
    for _ in range(iters):
        idx, ax, ay = voronoi(pts, XX, YY)
        for i in range(len(pts)):
            m = idx == i
            if m.any():
                pts[i, 0] += ax[m].mean()
                pts[i, 1] += ay[m].mean()
        pts %= S
    return pts


def scatter(rng, radii, gap=1.0, tries=60, accept=None):
    """Dart throwing on the torus: places discs (largest first) that do not overlap more than gap
    allows (gap < 1 lets them touch and overlap a little). Returns (x, y, r) rows."""
    placed = []
    for r in sorted(radii, reverse=True):
        for _ in range(tries):
            x, y = rng.uniform(0, S, 2)
            if accept is not None and not accept(x, y):
                continue
            ok = True
            for (px, py, pr) in placed:
                if wrap(x - px) ** 2 + wrap(y - py) ** 2 < ((r + pr) * gap) ** 2:
                    ok = False
                    break
            if ok:
                placed.append((x, y, r))
                break
    return np.array(placed)


# ---------------------------------------------------------------- stamped stones
def stamp_stone(canvas, cx, cy, a, b, ang, albedo, rng, *, dome=0.45, shadow=0.45, spec=0.10,
                wobble=0.07, tex=None, tex_amp=0.0, vein=False):
    """Paints one rounded stone (an irregular ellipse, domed, lit from the top-left) with a soft
    contact shadow toward the bottom-right, into canvas (S x S x 3) with wrapped indices."""
    rmax = max(a, b)
    rmin = min(a, b)
    rad = int(np.ceil(rmax * 1.5 + 4))
    off = np.arange(-rad, rad + 1)
    ix = int(np.floor(cx))
    iy = int(np.floor(cy))
    ys = (iy + off) % S
    xs = (ix + off) % S
    dy = (iy + off - cy)[:, None].astype(np.float64)
    dx = (ix + off - cx)[None, :].astype(np.float64)
    c, s = np.cos(ang), np.sin(ang)
    harm = [(k, rng.uniform(0.0, wobble) / (k - 1), rng.uniform(0, 2 * np.pi)) for k in (2, 3, 4, 5)]

    def ell(ox, oy):
        u = (dx - ox) * c + (dy - oy) * s
        v = -(dx - ox) * s + (dy - oy) * c
        phi = np.arctan2(v / b, u / a)
        rr = 1.0 + sum(w * np.cos(k * phi + p) for k, w, p in harm)
        return np.sqrt((u / a) ** 2 + (v / b) ** 2) / rr

    d = ell(0.0, 0.0)
    cov = np.clip((1.0 - d) * rmin + 0.5, 0.0, 1.0)
    win = np.ix_(ys, xs)
    region = canvas[win]
    if shadow > 0:
        sd = ell(0.18 * rmin + 0.8, 0.26 * rmin + 1.0)
        sh = smoothstep(1.25, 0.75, sd) * shadow
        region *= (1.0 - sh)[..., None]
    h = dome * rmin * np.clip(1.0 - d * d, 0.0, 1.0) ** 0.65
    hy, hx = np.gradient(h)
    nl = (-hx * LIGHT[0] - hy * LIGHT[1] + LIGHT[2]) / np.sqrt(hx * hx + hy * hy + 1.0)
    nl = np.clip(nl, 0.0, 1.0)
    alb = np.broadcast_to(albedo, region.shape).copy()
    if tex is not None:
        alb *= (1.0 + tex_amp * tex[win])[..., None]
    if vein:
        va = rng.uniform(0, np.pi)
        vo = rng.uniform(-0.4, 0.4) * rmin
        dv = np.abs(dx * np.sin(va) - dy * np.cos(va) - vo)
        alb = mix(alb, np.minimum(alb * 1.25 + 0.06, 1.0), smoothstep(1.3, 0.3, dv) * 0.8)
    lit = alb * (0.62 + 0.52 * nl)[..., None] + (spec * nl ** 14)[..., None]
    region = region * (1.0 - cov[..., None]) + lit * cov[..., None]
    canvas[win] = region


# ---------------------------------------------------------------- textures
def make_sand(rng):
    low = noise(rng, 1.5, 5, 1.0)
    mid = noise(rng, 4, 14, 1.0)
    patch = noise(rng, 1.5, 6, 1.2)
    warp = noise(rng, 1, 5, 1.0)
    ripple_mask = smoothstep(0.2, 1.6, noise(rng, 1.5, 4, 1.0))
    phase = 2 * np.pi * (7 * XX + 3 * YY) / S + 1.6 * warp          # integer wave numbers: tiles
    ripple = (np.sin(phase) + 0.35 * np.sin(2 * phase)) * ripple_mask
    value = posterize(0.8 * low + 0.35 * mid, 0.55, 0.45)
    rgb = mix(fill(col(0.80, 0.73, 0.62)), fill(col(0.75, 0.72, 0.66)), smoothstep(-1.2, 1.4, patch) * 0.6)
    rgb *= (1.0 + 0.035 * value)[..., None]
    rgb *= (1.0 + 1.2 * lambert(0.45 * ripple))[..., None]
    rgb = paint(rgb, 4)
    grain = blur(rng.standard_normal((S, S)), 0.55)
    rgb *= (1.0 + 0.015 * grain / grain.std())[..., None]
    specks = blur((rng.random((S, S)) > 0.996).astype(float), 0.5)
    rgb *= (1.0 - 0.6 * specks)[..., None]
    sparkle = blur((rng.random((S, S)) > 0.997).astype(float), 0.5)
    rgb += 0.35 * sparkle[..., None]
    tex = noise(rng, 2, 40, 0.5)
    for _ in range(11):        # shell fragments
        a = rng.uniform(1.3, 2.6)
        stamp_stone(rgb, *rng.uniform(0, S, 2), a, a * rng.uniform(0.55, 0.85), rng.uniform(0, np.pi),
                    col(0.95, 0.90, 0.84) * rng.uniform(0.92, 1.04), rng, dome=0.35, shadow=0.30,
                    spec=0.08, wobble=0.15, tex=tex, tex_amp=0.05)
    for _ in range(14):        # small pebbles
        a = rng.uniform(1.0, 2.3)
        base = [col(0.58, 0.55, 0.51), col(0.64, 0.58, 0.50), col(0.52, 0.51, 0.49)][rng.integers(3)]
        stamp_stone(rgb, *rng.uniform(0, S, 2), a, a * rng.uniform(0.65, 0.95), rng.uniform(0, np.pi),
                    base, rng, dome=0.5, shadow=0.30, spec=0.04, wobble=0.10)
    return rgb


def make_pebbles(rng):
    grit_n = noise(rng, 1.5, 8, 1.0)
    grit_f = blur(rng.standard_normal((S, S)), 0.7)
    rgb = mix(fill(col(0.45, 0.42, 0.39)), fill(col(0.50, 0.46, 0.41)), smoothstep(-1, 1, grit_n))
    rgb *= (1.0 + 0.06 * grit_f / grit_f.std())[..., None]
    rgb = paint(rgb, 2)
    for _ in range(700):       # gravel in the grit
        a = rng.uniform(0.9, 2.2)
        g = rng.uniform(0.46, 0.64)
        stamp_stone(rgb, *rng.uniform(0, S, 2), a, a * rng.uniform(0.6, 0.95), rng.uniform(0, np.pi),
                    col(g * 1.04, g, g * 0.95), rng, dome=0.45, shadow=0.25, spec=0.0, wobble=0.12)
    palette = [col(0.74, 0.72, 0.68), col(0.64, 0.62, 0.59), col(0.79, 0.76, 0.71), col(0.68, 0.61, 0.54),
               col(0.58, 0.54, 0.49), col(0.81, 0.78, 0.73), col(0.71, 0.66, 0.59), col(0.56, 0.56, 0.55),
               col(0.69, 0.63, 0.57)]
    radii = np.concatenate([rng.uniform(10, 17, 34), rng.uniform(6, 10, 80), rng.uniform(3.5, 6, 160)])
    stones = scatter(rng, radii, gap=0.9)
    tex = noise(rng, 3, 30, 0.7)
    fine = blur(rng.standard_normal((S, S)), 0.6)
    fine /= fine.std()
    for i in rng.permutation(len(stones)):
        x, y, r = stones[i]
        alb = palette[rng.integers(len(palette))] * rng.uniform(0.94, 1.05)
        alb = alb * (1.0 + rng.uniform(-0.025, 0.025, 3))
        granite = rng.random() < 0.3
        stamp_stone(rgb, x, y, r * rng.uniform(1.0, 1.12), r * rng.uniform(0.68, 0.92), rng.uniform(0, np.pi),
                    alb, rng, dome=0.42, shadow=0.5, spec=0.06, wobble=0.07,
                    tex=fine if granite else tex, tex_amp=0.05 if granite else 0.06,
                    vein=rng.random() < 0.12)
    return paint(rgb, 2.5)


def make_rock(rng):
    wx = 7.0 * noise(rng, 1, 6, 1.0)
    wy = 7.0 * noise(rng, 1, 6, 1.0)
    x = XX + wx
    y = YY + wy
    big = lloyd(rng.uniform(0, S, (9, 2)), 1)
    idx, ax, ay = voronoi(big, x, y)
    d1 = border(big, x, y, idx, ax, ay)
    small = rng.uniform(0, S, (30, 2))
    x2 = XX + 0.6 * wy + 3.0 * noise(rng, 2, 14, 1.0)
    y2 = YY + 0.6 * wx + 3.0 * noise(rng, 2, 14, 1.0)
    idx2, ax2, ay2 = voronoi(small, x2, y2)
    d2 = border(small, x2, y2, idx2, ax2, ay2)
    keep1 = smoothstep(-0.9, 0.2, noise(rng, 1, 5, 1.0))
    keep2 = smoothstep(0.1, 1.0, noise(rng, 1.5, 6, 1.0))
    crack1 = np.exp(-(d1 / 1.2) ** 2) * keep1
    crack2 = np.exp(-(d2 / 0.8) ** 2) * keep2
    step = rng.uniform(-1.0, 1.0, len(big))[idx]
    hlow = noise(rng, 1.5, 5, 1.2)
    hmid = noise(rng, 3, 20, 1.0)
    hfine = noise(rng, 14, 70, 0.8)
    height = 3.2 * hlow + 1.4 * hmid + 0.25 * hfine + 0.9 * step - 2.6 * crack1 - 1.1 * crack2
    tone = noise(rng, 1.5, 5, 1.2)
    rgb = mix(fill(col(0.69, 0.64, 0.58)), fill(col(0.63, 0.64, 0.63)), smoothstep(-1.2, 1.2, tone))
    rgb *= (1.0 + 0.035 * posterize(hmid, 0.6) + 0.03 * step)[..., None]
    rgb *= (1.0 + 1.0 * lambert(height))[..., None]
    rgb *= (1.0 - 0.30 * crack1 - 0.18 * crack2)[..., None]
    lich = noise(rng, 1.5, 6, 1.0) + 0.55 * noise(rng, 5, 24, 0.9) + 0.25 * noise(rng, 20, 60, 0.6)
    warm = smoothstep(1.0, 1.35, lich)
    lich2 = noise(rng, 1.5, 6, 1.0) + 0.55 * noise(rng, 5, 24, 0.9) + 0.25 * noise(rng, 20, 60, 0.6)
    cool = smoothstep(1.05, 1.4, lich2) * (1.0 - warm)
    rgb = mix(rgb, rgb * col(1.08, 1.00, 0.82) + col(0.03, 0.02, 0.0), warm * 0.45)
    rgb = mix(rgb, rgb * col(0.96, 1.02, 0.97) + col(0.02, 0.03, 0.02), cool * 0.5)
    rgb = paint(rgb, 3)
    m = rgb.mean(axis=(0, 1))
    return m + (rgb - m) * 0.85                     # keep it low-contrast


def make_cobble(rng):
    pts = lloyd(rng.uniform(0, S, (40, 2)), 3)
    x = XX + 2.6 * noise(rng, 1.5, 8, 1.0)
    y = YY + 2.6 * noise(rng, 1.5, 8, 1.0)
    idx, ax, ay = voronoi(pts, x, y)
    d = border(pts, x, y, idx, ax, ay, soft=2.0)
    gap = 2.2
    t = np.clip((d - gap) / 8.0, 0.0, 1.0)
    bump = noise(rng, 4, 14, 1.0)
    height = 5.0 * (1.0 - (1.0 - t) ** 2.2) + 0.3 * bump * t
    stone = smoothstep(gap - 0.8, gap + 0.8, d)
    palette = [col(0.70, 0.68, 0.64), col(0.65, 0.62, 0.58), col(0.73, 0.69, 0.63), col(0.60, 0.59, 0.58),
               col(0.69, 0.64, 0.58), col(0.65, 0.65, 0.63), col(0.72, 0.67, 0.61)]
    tints = np.array([palette[rng.integers(len(palette))] * rng.uniform(0.93, 1.06) for _ in pts])
    inner = noise(rng, 3, 20, 0.9)
    alb = tints[idx] * (1.0 + 0.04 * posterize(inner, 0.7))[..., None]
    alb = alb * (1.0 + 0.03 * (height / 5.0))[..., None]         # worn, polished tops
    mortar_n = blur(rng.standard_normal((S, S)), 0.7)
    mortar = col(0.50, 0.47, 0.42) * (1.0 + 0.08 * mortar_n / mortar_n.std())[..., None]
    rgb = mix(mortar, alb, stone)
    rgb *= (1.0 + 0.9 * lambert(height))[..., None]
    sh = cast_shadow(height, steps=5, drop=1.0)
    rgb *= (1.0 - 0.35 * smoothstep(0.0, 3.0, sh))[..., None]
    ao = 1.0 - 0.25 * np.exp(-np.maximum(d, 0.0) / 2.2) * (1.0 - stone * 0.5)
    rgb *= ao[..., None]
    return paint(rgb, 2)


def make_planks(rng):
    n = 6
    ph = S / n
    v = (YY + ph * 0.5) % ph                                       # 0 at the top edge of a plank
    plank = (np.floor((YY + ph * 0.5) / ph).astype(np.int64)) % n
    edge = np.minimum(v, ph - v)
    gap = 1.0 - smoothstep(1.0, 2.3, edge)
    tones = [col(0.70, 0.62, 0.52), col(0.66, 0.62, 0.56), col(0.72, 0.64, 0.53), col(0.64, 0.58, 0.50),
             col(0.69, 0.65, 0.58), col(0.67, 0.60, 0.50)]
    rgb = np.zeros((S, S, 3))
    grain_base = noise(rng, 0, 60, 0.7, stretch=(12.0, 1.0))
    wave = noise(rng, 0, 6, 1.0, stretch=(4.0, 1.0))
    weather = noise(rng, 0, 6, 1.2)
    for p in range(n):
        rows = plank == p
        shift = int(rng.integers(0, S))
        g = np.roll(grain_base, (int(rng.integers(0, S)), shift), axis=(0, 1))
        w = np.roll(wave, (int(rng.integers(0, S)), int(rng.integers(0, S))), axis=(0, 1))
        lines = np.sin(2 * np.pi * (v / ph) * rng.uniform(5.0, 8.0) + 2.6 * w + rng.uniform(0, 6.3))
        dark = smoothstep(0.80, 0.98, lines) * 0.10 + smoothstep(0.5, 1.0, -lines) * 0.025
        base = tones[p] * rng.uniform(0.95, 1.04)
        pr = base * (1.0 + 0.045 * g - dark)[..., None]
        rgb[rows] = pr[rows]
    rgb = mix(rgb, rgb * col(0.97, 1.0, 1.04) + 0.035, smoothstep(0.0, 1.5, weather) * 0.6)
    rim_top = np.exp(-((v - 2.6) / 1.4) ** 2)
    rim_bot = np.exp(-((ph - v - 2.6) / 1.6) ** 2)
    rgb *= (1.0 + 0.10 * rim_top - 0.12 * rim_bot)[..., None]
    rgb = paint(rgb, 2)
    # butt joints and nails: drawn per plank with wrapped indices
    nails = []
    joist = rng.uniform(0, S)
    for p in range(n):
        top = p * ph - ph * 0.5
        for frac in (0.28, 0.72):
            nails.append((wrap(joist + rng.normal(0, 0.8)) % S, top + ph * frac + rng.normal(0, 0.6)))
        if p in (0, 2, 3, 5):
            jx = (joist + rng.uniform(70, 180)) % S
            jw = 1.0 - smoothstep(0.3, 1.3, np.abs(wrap(XX - jx)))
            m = (plank == p) * jw
            rgb *= (1.0 - 0.55 * m)[..., None]
            rgb *= (1.0 + 0.06 * ((plank == p) * np.exp(-((wrap(XX - jx) - 2.0) / 1.2) ** 2)))[..., None]
            for side in (-5.0, 5.0):
                for frac in (0.3, 0.7):
                    nails.append(((jx + side) % S, top + ph * frac + rng.normal(0, 0.5)))
    for (nx, ny) in nails:
        ny %= S
        dd = np.sqrt(wrap(XX - nx) ** 2 + wrap(YY - ny) ** 2)
        rust = smoothstep(4.0, 0.0, dd) * 0.10
        rgb = mix(rgb, rgb * col(0.85, 0.72, 0.60), rust)
        head = smoothstep(1.7, 0.9, dd)
        rgb = mix(rgb, fill(col(0.30, 0.27, 0.25)), head)
        hl = smoothstep(1.0, 0.0, np.sqrt(wrap(XX - nx + 0.6) ** 2 + wrap(YY - ny + 0.6) ** 2))
        rgb = mix(rgb, fill(col(0.62, 0.60, 0.58)), hl * 0.7)
    for _ in range(3):        # knots
        kx, ky = rng.uniform(0, S, 2)
        kd = np.sqrt((wrap(XX - kx) / 3.6) ** 2 + (wrap(YY - ky) / 1.9) ** 2)
        valid = edge > 6
        ring = np.exp(-((kd - 1.6) / 0.35) ** 2) * 0.08
        rgb *= (1.0 - (smoothstep(1.2, 0.5, kd) * 0.30 + ring) * valid)[..., None]
    gap_col = col(0.20, 0.17, 0.14)
    rgb = mix(rgb, fill(gap_col), gap)
    return rgb


def make_concrete(rng):
    m1 = noise(rng, 0, 6, 1.2)
    m2 = noise(rng, 5, 28, 1.0)
    hue = noise(rng, 0, 4, 1.2)
    rgb = mix(fill(col(0.70, 0.68, 0.64)), fill(col(0.67, 0.67, 0.66)), smoothstep(-1.2, 1.2, hue))
    rgb *= (1.0 + 0.045 * m1 + 0.025 * m2)[..., None]
    brush = noise(rng, 8, 60, 0.4, stretch=(5.0, 1.0), rotate=0.5)
    rgb *= (1.0 + 0.012 * brush)[..., None]
    # faint expansion joints: one across and one along the deck, slightly wobbly, sawn grooves
    jx = 150.0 + 0.5 * noise(rng, 0, 6, 1.0)
    jy = 92.0 + 0.5 * noise(rng, 0, 6, 1.0)
    dxj = np.abs(wrap(XX - jx))
    dyj = np.abs(wrap(YY - jy))
    fade = smoothstep(-1.2, 0.0, noise(rng, 0, 8, 1.0))
    groove = np.maximum(np.exp(-(dxj / 0.9) ** 2), 0.7 * np.exp(-(dyj / 0.8) ** 2)) * (0.6 + 0.4 * fade)
    rgb *= (1.0 + 2.2 * lambert(-1.6 * groove) - 0.18 * groove)[..., None]
    # stains: soft, rounded, with a faint darker tide line
    sn = noise(rng, 1.5, 10, 1.0)
    for kind, r0, r1 in (("water", 22, 36), ("rust", 7, 11), ("oil", 18, 28), ("water", 22, 36)):
        sx, sy = rng.uniform(0, S, 2)
        rad = rng.uniform(r0, r1)
        dd = np.sqrt(wrap(XX - sx) ** 2 + (wrap(YY - sy) * rng.uniform(0.75, 1.25)) ** 2) / rad
        body = smoothstep(1.0, 0.35, dd + 0.22 * sn)
        tide = np.exp(-((dd + 0.22 * sn - 0.85) / 0.08) ** 2)
        tint, k = {"water": (col(0.91, 0.91, 0.91), 0.8), "rust": (col(0.95, 0.86, 0.76), 0.7),
                   "oil": (col(0.85, 0.85, 0.87), 0.8)}[kind]
        rgb = mix(rgb, rgb * tint, body * k)
        rgb *= (1.0 - 0.03 * tide)[..., None]
    rgb = paint(rgb, 3)
    pores = blur((rng.random((S, S)) > 0.985).astype(float), 0.55)
    rgb *= (1.0 - 0.45 * pores)[..., None]
    agg = blur((rng.random((S, S)) > 0.99).astype(float), 0.6)
    rgb *= (1.0 + 0.35 * agg)[..., None]
    return rgb


def make_grass(rng):
    up = 4
    big = S * up
    earth_n = noise(rng, 1.5, 8, 1.1)
    earth = mix(fill(col(0.64, 0.57, 0.47)), fill(col(0.60, 0.56, 0.49)), smoothstep(-1, 1, earth_n))
    fine = blur(rng.standard_normal((S, S)), 0.6)
    earth *= (1.0 + 0.05 * fine / fine.std())[..., None]
    cover = smoothstep(-0.5, 0.5, noise(rng, 1.5, 6, 1.1) + 0.45 * noise(rng, 5, 16, 1.0))
    under = mix(fill(col(0.66, 0.63, 0.48)), fill(col(0.63, 0.63, 0.50)), smoothstep(-1, 1, noise(rng, 1.5, 6, 1.0)))
    rgb = mix(earth, under, cover * 0.85)
    rgb = paint(rgb, 3)
    for _ in range(18):     # small stones in the earth
        a = rng.uniform(1.2, 2.8)
        g = rng.uniform(0.60, 0.74)
        stamp_stone(rgb, *rng.uniform(0, S, 2), a, a * rng.uniform(0.6, 0.9), rng.uniform(0, np.pi),
                    col(g * 1.04, g, g * 0.93), rng, dome=0.45, shadow=0.35, wobble=0.12)
    # tuft shadows and blades, supersampled 4x, every stroke drawn at each wrap offset it touches
    tufts = []
    while len(tufts) < 420:
        x, y = rng.uniform(0, S, 2)
        if rng.random() < float(sample(cover, np.array([x]), np.array([y]))[0]) * 0.95 + 0.03:
            tufts.append((x, y))
    shadow_img = Image.new("L", (big, big), 0)
    sdraw = ImageDraw.Draw(shadow_img)
    offsets = [(ox, oy) for ox in (-big, 0, big) for oy in (-big, 0, big)]
    sizes = rng.uniform(0.6, 1.15, len(tufts))
    for (x, y), k in zip(tufts, sizes):
        cx, cy = (x + 2.5 * k) * up, (y + 2.2 * k) * up
        rx, ry = 7.0 * k * up, 4.0 * k * up
        for ox, oy in offsets:
            sdraw.ellipse([cx - rx + ox, cy - ry + oy, cx + rx + ox, cy + ry + oy], fill=150)
    shadow = blur(np.asarray(shadow_img, dtype=np.float64) / 255.0, 3.0 * up)
    canvas = np.repeat(np.repeat(rgb, up, axis=0), up, axis=1)
    canvas *= (1.0 - 0.38 * shadow)[..., None]
    img = Image.fromarray(np.clip(canvas * 255.0, 0, 255).astype(np.uint8), "RGB")
    draw = ImageDraw.Draw(img)
    palette = [col(0.58, 0.58, 0.42), col(0.64, 0.64, 0.50), col(0.74, 0.68, 0.50), col(0.70, 0.64, 0.48),
               col(0.66, 0.65, 0.48)]
    for (x, y), k in zip(tufts, sizes):
        base = palette[rng.integers(len(palette))] * rng.uniform(0.94, 1.05)
        blades = []
        for _ in range(int(rng.integers(8, 15))):
            ang = -np.pi / 2 + rng.normal(0, 0.75)
            length = rng.uniform(5.0, 11.0) * k
            bend = rng.normal(0, 0.35)
            blades.append((ang, length, bend))
        blades.sort(key=lambda b: np.cos(b[0]))        # right-leaning (shaded) first, lit ones on top
        for ang, length, bend in blades:
            lit = -np.cos(ang) * 0.10 - np.sin(ang) * 0.04
            pts = []
            for t in np.linspace(0, 1, 5):
                a = ang + bend * t
                pts.append(((x + np.cos(a) * length * t) * up, (y + np.sin(a) * length * t) * up))
            for seg in range(4):
                tt = (seg + 0.5) / 4
                shade = base * (0.80 + 0.32 * tt + lit)
                c = tuple(int(v) for v in np.clip(shade * 255, 0, 255))
                width = int(round((1.9 - 1.1 * tt) * up))
                (x0, y0), (x1, y1) = pts[seg], pts[seg + 1]
                for ox, oy in offsets:
                    if -60 < x0 + ox < big + 60 and -60 < y0 + oy < big + 60:
                        draw.line([(x0 + ox, y0 + oy), (x1 + ox, y1 + oy)], fill=c, width=max(width, 1))
    hi = np.asarray(img, dtype=np.float64) / 255.0
    return hi.reshape(S, up, S, up, 3).mean(axis=(1, 3))


TEXTURES = [
    # name, maker, seed, target mean luminance
    ("sand", make_sand, 11, 0.67),
    ("pebbles", make_pebbles, 23, 0.62),
    ("rock", make_rock, 37, 0.63),
    ("cobble", make_cobble, 41, 0.63),
    ("planks", make_planks, 53, 0.62),
    ("concrete", make_concrete, 67, 0.66),
    ("grass", make_grass, 79, 0.63),
]

# The flat colours the game draws today (fishing_spots.gd shore_color, the pier brown, shore_world.gd
# ground), used only for the tinted preview strip on the contact sheet.
PREVIEW_TINT = {
    "sand": (0.90, 0.80, 0.58), "pebbles": (0.90, 0.80, 0.58), "rock": (0.40, 0.34, 0.28),
    "cobble": (0.62, 0.62, 0.60), "planks": (0.56, 0.41, 0.27), "concrete": (0.58, 0.56, 0.52),
    "grass": (0.78, 0.72, 0.56),
}


# ---------------------------------------------------------------- checks and output
def finalize(rgb, target):
    rgb = np.clip(rgb, 0.0, 1.0)
    for _ in range(3):                                   # scale toward the target, re-check after clipping
        rgb = np.clip(rgb * (target / luminance(rgb).mean()), 0.0, 1.0)
    return (np.round(rgb * 255.0)).astype(np.uint8)


def seam_ratios(img8):
    """Wrapped-edge neighbour difference over the mean interior neighbour difference, per axis, and
    where the wrapped pair ranks among the 255 interior column (row) pairs, in percent."""
    a = img8[..., :3].astype(np.float64)
    per_x = np.abs(np.diff(a, axis=1)).mean(axis=(0, 2))
    per_y = np.abs(np.diff(a, axis=0)).mean(axis=(1, 2))
    wrap_x = np.abs(a[:, 0] - a[:, -1]).mean()
    wrap_y = np.abs(a[0] - a[-1]).mean()
    return (wrap_x / per_x.mean(), wrap_y / per_y.mean(),
            100.0 * (per_x < wrap_x).mean(), 100.0 * (per_y < wrap_y).mean())


def stats(img8):
    a = img8[..., :3].astype(np.float64) / 255.0
    mx = a.max(axis=2)
    mn = a.min(axis=2)
    sat = np.where(mx > 0, (mx - mn) / np.maximum(mx, 1e-6), 0.0)
    return luminance(a).mean(), sat.mean()


def contact_sheet(results, path):
    cell = S * 2
    strip = 72
    label = 30
    pad = 16
    cols = 4
    rows = (len(results) + cols - 1) // cols
    w = cols * (cell + pad) + pad
    h = rows * (cell + label + strip + pad) + pad
    sheet = Image.new("RGB", (w, h), (36, 40, 46))
    draw = ImageDraw.Draw(sheet)
    try:
        font = ImageFont.load_default(size=22)
    except TypeError:
        font = ImageFont.load_default()
    for i, (name, img8) in enumerate(results):
        cx = pad + (i % cols) * (cell + pad)
        cy = pad + (i // cols) * (cell + label + strip + pad)
        tile = Image.fromarray(img8, "RGBA").convert("RGB")
        for ty in range(2):
            for tx in range(2):
                sheet.paste(tile, (cx + tx * S, cy + label + ty * S))
        tint = np.array(PREVIEW_TINT[name]) / stats(img8)[0]
        tinted = np.clip(img8[..., :3].astype(np.float64) / 255.0 * tint, 0, 1)
        tinted = Image.fromarray((tinted * 255).astype(np.uint8), "RGB")
        for tx in range(2):
            sheet.paste(tinted.crop((0, 0, S, strip)), (cx + tx * S, cy + label + cell))
        draw.text((cx, cy + 2), f"{name}  (2x2; strip: x spot colour)", fill=(230, 230, 225), font=font)
    os.makedirs(os.path.dirname(os.path.abspath(path)), exist_ok=True)
    sheet.save(path)


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--out", default=OUT, help="output folder (default assets/art/ground)")
    ap.add_argument("--sheet", default=SHEET, help="contact sheet path (default %(default)s)")
    args = ap.parse_args()
    os.makedirs(args.out, exist_ok=True)
    t0 = time.time()
    results = []
    failed = False
    print(f"{'texture':<10} {'seam L/R':>9} {'seam T/B':>9} {'pctl L/R':>9} {'pctl T/B':>9} {'lum':>6} {'sat':>6} {'secs':>6}")
    for name, maker, seed, target in TEXTURES:
        t1 = time.time()
        rgb = maker(np.random.default_rng(seed))
        img8 = np.dstack([finalize(rgb, target), np.full((S, S), 255, np.uint8)])
        rx, ry, px, py = seam_ratios(img8)
        lum, sat = stats(img8)
        bad = rx > SEAM_MAX or ry > SEAM_MAX
        failed |= bad
        print(f"{name:<10} {rx:9.3f} {ry:9.3f} {px:8.0f}% {py:8.0f}% {lum:6.3f} {sat:6.3f} {time.time() - t1:6.2f}"
              + ("  SEAM OVER LIMIT" if bad else ""))
        Image.fromarray(img8, "RGBA").save(os.path.join(args.out, name + ".png"), optimize=True)
        results.append((name, img8))
    contact_sheet(results, args.sheet)
    print(f"wrote {len(results)} textures to {os.path.abspath(args.out)}")
    print(f"contact sheet: {args.sheet}   total {time.time() - t0:.1f} s")
    if failed:
        print(f"seam ratio over {SEAM_MAX}: see above", file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
