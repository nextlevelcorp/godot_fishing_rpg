# Ground textures

`sand.png`, `pebbles.png`, `rock.png`, `cobble.png`, `planks.png`, `concrete.png` and `grass.png` are
generated procedurally by `tools/art/make_ground_textures.py` (Python, numpy and Pillow only). No
third-party art, photos or AI images are used, so there are no licence terms to track.

| Files | Tool | Date | Notes |
|---|---|---|---|
| all seven `*.png` | `tools/art/make_ground_textures.py` (fixed seeds) | 2026-11-08 | 256x256 opaque RGBA, seamless (built on a torus; the script measures the wrapped edges). Mid-value and low saturation (mean luminance 0.62-0.67) so the game can tint them with the spot colour via `modulate`. |

## Regenerate

```
python3 tools/art/make_ground_textures.py
```

It writes the seven PNGs here, prints the seam ratios, mean luminance and saturation for each, and
fails if a wrapped edge differs more than 1.5x from interior neighbours. It also writes a contact
sheet (every tile 2x2) to `/tmp/ground_sheet/ground_sheet.png` (`--sheet PATH` to change); look at it
before committing. The output is the same on every run; change a seed in `TEXTURES` to get a variant.
