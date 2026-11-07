# Painted sprites

Sprites made for this game from `docs/ART_BRIEF_AI.md`. Record for every batch: the tool used, the
date, and the plan or terms that allow commercial use. Until a file exists, the game draws that
object procedurally (for fish: `real_fish.gd`).

## Batches

| Files | Tool | Date | Notes |
|---|---|---|---|
| `fish/bluefish.png`, `fish/garfish.png` | ChatGPT image generation (made by the project owner) | 2026-11-05 | Trimmed and scaled to 1024 px wide. The garfish came with a checkerboard painted into the image (not real transparency); the background was cut out by flood fill from the edges. Made on the ChatGPT free plan. OpenAI's terms of use assign ownership of outputs to the user; re-check the current terms before a commercial release. |

| Files | Tool | Date | Notes |
|---|---|---|---|
| `fish/black_scorpionfish.png`, `blue_crab.png`, `common_cuttlefish.png`, `common_dentex.png`, `dusky_grouper.png`, `european_squid.png`, `greater_amberjack.png`, `leerfish.png`, `saddled_bream.png`, `striped_sea_bream.png`, `white_seabream.png`, `whiting.png` | ChatGPT image generation, free plan (made by the project owner) | 2026-11-07 | Three uploads came out empty (transparent) and are not used. Light backgrounds were removed by flood fill from the edges; two came with real transparency and were kept as they are. The crab is seen from above and the squid and cuttlefish from the side, as the brief asked; the catch code still draws cephalopods procedurally, so these images are used where a fish sprite is drawn (other anglers' catches). |
