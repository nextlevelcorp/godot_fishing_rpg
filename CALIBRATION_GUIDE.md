# Nibble, Bite and Sonar: Telemetry and Calibration Guide

## 1. How a bite works

```
cast -> WANDERING -> APPROACHING -> NIBBLING -> BITING -> HOOKED (spring-mass fight)
              ^            |            |           |
              +------------+------ SPOOKED <--------+   (reeled early / bait stolen)
```

1. **Interest** per fish (computed every physics tick from the school arrays, no Area2D):
   `interest = bait_bonus * closeness^2 * depth_match * lerp(0.6, 1, hunger) * appetite`
   * `closeness = 1 - distance_to(bait) / attract_radius_px`
   * `depth_match = 1 - |fish_depth - bait_depth| / depth_tolerance_m` (clamped to 0..1)
   * `hunger` is slow Perlin noise per fish.
   The best fish above `engage_threshold` becomes the single engaged fish. Fish inside the attract radius are flagged `approaching` and steer toward the bait with arrival slowdown.
2. **Nibbling** (cautious species): `s(t) = perlin1d(t * noise_hz + offset)` mapped to 0..1. Each upward crossing of `nibble_threshold` is one light nibble. The rod tension is `max(s - threshold, 0) / (1 - threshold) * nibble_force_n`, so the shake follows the same curve you feel.
3. **Commit**: once `nibbles_done >= nibbles_needed`, the fish's current caution is
   `caution_now = caution + 0.3 * wobble(t) - pressure_per_s * time_since_last_nibble`
   and the fish commits to the bite when `caution_now < commit_level`. Cautious fish take longer; waiting always works eventually, but `max_nibble_s` makes them lose interest.
4. **Solid bite**: tension jumps to `strike_force_n` and a `bite_window_s` timer starts. Press `reel_in` inside the window and `FishingController` takes over. Miss it and the bait is stolen, or an aggressive fish may hook itself (`self_hook_chance`).
5. **Reeling too early**: pressing `reel_in` during a nibble spooks the fish with probability `spook_chance`; otherwise the press is ignored. While WANDERING or APPROACHING it just retrieves the bait.

## 2. Bite profile fields (`BiomeDB.BITE_PROFILES`)

| Field | Effect | Raise it to... |
|---|---|---|
| `caution` | Hesitation before committing | make the fish wait longer, more patience needed |
| `noise_hz` | Perlin speed. Pulses per second are about 0.4 x `noise_hz` | make nibbles faster and twitchier |
| `nibble_force_n` | Tension of a light nibble | make nibbles easier to feel |
| `nibbles` (min, max) | Light nibbles before commit; (0, 0) strikes at once | make the fish tease more |
| `strike_force_n` | Tension of the solid bite | make the bite obvious and violent |
| `bite_window_s` | Time to set the hook | make it more forgiving |
| `spook_chance` | Chance an early reel scares the fish off | punish impatience |
| `self_hook_chance` | Chance the fish hooks itself if you miss the window | make aggressive fish forgiving |
| `max_nibble_s` | Time before the fish gives up | make it stubborn |
| `appetite` | Multiplier on interest | attract the fish from further away |

### Archetypes

| Archetype | caution | noise_hz | nibbles | strike_force_n | window_s | spook | Species now |
|---|---|---|---|---|---|---|---|
| Cautious, patient | 0.7-0.8 | 1.0-1.2 | 3-6 | 7-10 | 0.9 | 0.95-1.0 | Gilthead Seabream, Red Seabream |
| Balanced predator | 0.4-0.55 | 1.2-1.6 | 1-3 | 12-26 | 0.7-0.8 | 0.5-0.8 | European/Japanese Seabass, Coral Trout |
| Twitchy small fry | 0.25-0.4 | 2.0-3.0 | 1-5 | 3-4 | 1.0 | 0.2-0.5 | Red Mullet, Horse Mackerel |
| Slow giant | 0.35-0.45 | 0.4-0.5 | 1-3 | 30-40 | 1.3-1.5 | 0.4-0.5 | Arapaima, Halibut, Red-tailed Catfish |
| Aggressive striker | 0.05-0.15 | 2.6-3.5 | 0 | 28-55 | 0.5-0.6 | 0.05-0.2 | Bluefish, Giant Trevally, Spanish Mackerel, Peacock Bass |

To add a world species, copy the closest archetype row into `BITE_PROFILES`; `validate()` warns when a species has no profile (it then uses `BITE_DEFAULT`).

## 3. Sonar tiers (`ProgressionManager.UPGRADES["sonar"]`)

| Tier | Range px | detail | Detect | Pos error px | Ghosts | Ping s |
|---|---|---|---|---|---|---|
| Basic Fishfinder | 220 | 0 blips | 70% | 14 | 30% | 2.4 |
| Coastal Fishfinder | 300 | 0 blips | 82% | 9 | 20% | 2.0 |
| Advanced Chrono-Sonar | 380 | 1 + size class | 90% | 5 | 10% | 1.6 |
| Chrono-Sonar Pro | 480 | 2 + exact depth | 95% | 2.5 | 4% | 1.2 |
| Chrono-Sonar Elite | 620 | 2 + exact depth | 99% | 1 | 0% | 0.9 |

* Detection probability per fish per ping: `detect * (1 - 0.35 * d / range) * lerp(0.7, 1, size01) * (1 - 0.2 * boat_speed01)`. Big fish, close fish and a slow boat are seen more often.
* **Ping efficiency %** = real fish detected / real fish inside the range during that ping. The overlay also shows the average of the last 10 pings. Ghost echoes are not counted as hits.
* Size classes: Small below 0.35 of the species' weight range, Medium 0.35 to the trophy cut-off (0.80), Trophy above it, which matches the Trophy grade in `ProgressionManager.GRADES`.
* To make better sonar matter more, raise the basic tier's `ghost_rate` or lower its `detect_prob`.

## 4. Telemetry

* **On screen**: the F3 `DebugOverlay` shows `Active Fish Interest Score`, `Current State` (Wandering, Approaching, Nibbling, BITING, Spooked, Hooked), the species, the nibble count, current caution, rod tension and bite window while a fish is engaged, plus `Sonar Ping Efficiency`, tier, contacts and ghosts.
* **Logs**: set `print_telemetry = true` on `FishInteractionAI` (prints twice a second while bait is out) and on `SonarSystem` (once a second).
* **Signals** for UI and audio: `nibble_felt(strength, index, needed)`, `solid_bite(window_s)`, `rod_pulse(tension)` every frame, `hook_set`, `bait_stolen`, `fish_spooked`, `state_changed`, and on the sonar `ping_started` / `ping_finished(efficiency, detected, in_range)`.

## 5. Tuning recipes

* **Nibbles too hard to read**: raise `nibble_force_n` or lower `noise_hz` (slower pulses).
* **Fish never commit**: lower `caution` or raise `pressure_per_s` on the AI node; check `max_nibble_s`.
* **Fish commit instantly**: raise `caution` or `nibbles`; lower `commit_level`.
* **Players get nothing for waiting**: raise `appetite`, `attract_radius_px`, or lower `engage_threshold`.
* **Bites feel unfair**: lengthen `bite_window_s`, add `self_hook_chance`.
* **Calibrating a new species**: print telemetry, cast ten times, and note the average time from first nibble to bite. The target is about 4-8 s for cautious fish and under 2 s for aggressive ones.
