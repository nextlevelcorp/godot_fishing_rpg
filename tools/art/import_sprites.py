#!/usr/bin/env python3
"""Turns the owner's AI-generated pictures into game sprites. One command, the same steps every time.

    python3 tools/art/import_sprites.py [--sheet DIR] species_id=picture.png [species_id=picture.png ...]

For each picture:
  1. Empty check: a picture that is fully transparent (or all one colour) is skipped and reported.
  2. Background: a picture with real transparency is kept as it is. Otherwise the light background
     (white, off-white, light grey, a painted checkerboard) is flooded away from the edges: only pixels
     that touch the border and are bright with low colour count as background, so white highlights
     inside the animal stay. The largest piece is kept (specks drop out) and the edge is softened 1 px.
  3. Trim to the subject, scale down to at most 768 px wide (never up), save as
     assets/art/fish/<species_id>.png. The game finds the sprite by that exact name.
  4. Contact sheet: all results on a sea-blue background, written outside the project (default
     /tmp/sprite_sheet/sheet.png) so it is never committed by mistake. Look at it before committing.

species_id is the key used in biome_database.gd (for example whiting, dusky_grouper). The sprite must
face right (snout to the right); the game flips it for the other direction.

Needs numpy and Pillow. Record each batch in assets/art/SOURCE.md.
"""
import argparse
import os
import sys
from collections import deque

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..")
OUT = os.path.join(ROOT, "assets", "art", "fish")
MAX_W = 768                     # the catch close-up is at most ~330 design px (~650 device px)


def largest_component(mask):
    h, w = mask.shape
    lab = np.zeros((h, w), np.int32)
    cur = 0
    best = (0, 0)
    for y0 in range(h):
        for x0 in range(w):
            if mask[y0, x0] and lab[y0, x0] == 0:
                cur += 1
                q = deque([(y0, x0)])
                lab[y0, x0] = cur
                n = 0
                while q:
                    y, x = q.popleft()
                    n += 1
                    for dy, dx in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                        ny, nx = y + dy, x + dx
                        if 0 <= ny < h and 0 <= nx < w and mask[ny, nx] and lab[ny, nx] == 0:
                            lab[ny, nx] = cur
                            q.append((ny, nx))
                if n > best[1]:
                    best = (cur, n)
    return lab == best[0]


def cut_light_background(rgb):
    h, w, _ = rgb.shape
    g = rgb.astype(int)
    mx = g.max(2)
    sat = mx - g.min(2)
    bg = (sat <= 14) & (mx >= 196)
    seen = np.zeros((h, w), bool)
    q = deque()
    for x in range(w):
        for y in (0, h - 1):
            if bg[y, x] and not seen[y, x]:
                seen[y, x] = True
                q.append((y, x))
    for y in range(h):
        for x in (0, w - 1):
            if bg[y, x] and not seen[y, x]:
                seen[y, x] = True
                q.append((y, x))
    while q:
        y, x = q.popleft()
        for dy, dx in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            ny, nx = y + dy, x + dx
            if 0 <= ny < h and 0 <= nx < w and not seen[ny, nx] and bg[ny, nx]:
                seen[ny, nx] = True
                q.append((ny, nx))
    keep = largest_component(~seen)
    mask = Image.fromarray((keep * 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(1.0))
    return np.dstack([rgb, np.array(mask)])


def import_one(species, path):
    im = Image.open(path).convert("RGBA")
    a = np.array(im)
    alpha = a[:, :, 3]
    if alpha.max() == 0:
        return None, "EMPTY (fully transparent): skipped"
    if alpha.min() < 250 and (alpha < 250).mean() > 0.08:
        how = "kept real transparency"
        out = a
    else:
        rgb = a[:, :, :3]
        if rgb.std() < 3.0:
            return None, "EMPTY (one flat colour): skipped"
        out = cut_light_background(rgb)
        how = "removed the light background"
    al = out[:, :, 3]
    al[al >= 240] = 255
    al[al < 8] = 0
    out[:, :, 3] = al
    img = Image.fromarray(out.astype(np.uint8), "RGBA")
    bbox = img.getbbox()
    if bbox is None:
        return None, "EMPTY after the cut: skipped"
    img = img.crop(bbox)
    if img.width > MAX_W:
        img = img.resize((MAX_W, round(img.height * MAX_W / img.width)), Image.LANCZOS)
    os.makedirs(OUT, exist_ok=True)
    dest = os.path.join(OUT, species + ".png")
    img.save(dest, optimize=True)
    return img, "%s, %dx%d -> assets/art/fish/%s.png" % (how, img.width, img.height, species)


def contact_sheet(items, path):
    w = 360
    cells = []
    for name, img in items:
        t = img.copy()
        t.thumbnail((w - 20, 160))
        cell = Image.new("RGBA", (w, 190), (60, 110, 140, 255))
        cell.paste(t, ((w - t.width) // 2, 10), t)
        ImageDraw.Draw(cell).text((8, 172), name, fill=(255, 255, 0, 255))
        cells.append(cell)
    cols = 3
    rows = (len(cells) + cols - 1) // cols
    sheet = Image.new("RGBA", (w * cols, 190 * rows), (0, 0, 0, 255))
    for i, c in enumerate(cells):
        sheet.paste(c, ((i % cols) * w, (i // cols) * 190))
    os.makedirs(os.path.dirname(path), exist_ok=True)
    sheet.convert("RGB").save(path)


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("pairs", nargs="+", help="species_id=picture.png")
    ap.add_argument("--sheet", default="/tmp/sprite_sheet", help="folder for the contact sheet (outside the project)")
    args = ap.parse_args()
    done = []
    for pair in args.pairs:
        if "=" not in pair:
            print("skip %r: write it as species_id=picture.png" % pair)
            continue
        species, path = pair.split("=", 1)
        if not os.path.exists(path):
            print("%-24s picture not found: %s" % (species, path))
            continue
        img, msg = import_one(species, path)
        print("%-24s %s" % (species, msg))
        if img is not None:
            done.append((species, img))
    if done:
        sheet = os.path.join(args.sheet, "sheet.png")
        contact_sheet(done, sheet)
        print("contact sheet: %s (look at it before committing)" % sheet)
    return 0


if __name__ == "__main__":
    sys.exit(main())
