# Global Fishing RPG: Architecture and Math (Godot 4, GDScript)

All text, IDs, data and UI strings are English. Files are flat here; move them into `res://scripts/...` as you like. Scripts use `class_name`, so paths do not matter. Only `BiomeDB` needs registering as an autoload.

## 1. Global RPG Biome and Data Architecture

| File | Role |
|---|---|
| `biome_database.gd` (autoload `BiomeDB`) | Zones, species, rigs, baits, lookups, rarity/weight rolls, startup `validate()` |
| `ocean_current_field.gd` | Perlin current, wind and thermal fields |
| `boat.gd` | Boat with thrust, keel/fluid drag, skid, wind and cargo penalties (replaces the old `boat_drift.gd`) |
| `cargo_hold.gd` | Weight-limited fish hold |
| `progression_manager.gd` | Money, XP, levels, gear upgrades, market, selling |
| `debug_overlay.gd` | F3 telemetry overlay |
| `fish_interaction_ai.gd` | Nibble and bite state machine (Perlin pulses, bite window, hand-off to the fight) |
| `sonar_system.gd` + `sonar_display.gd` | Ping pulses, tiered contacts, radar widget |
| `fish_school.gd` | Boids + predator/prey + habitat comfort |
| `fishing_controller.gd` | Spring-mass fight, clutch, line fatigue, telemetry |
| `nightshoal_water.gdshader` + `water_surface.gd` | Water, caustics, wake |
| `day_night_cycle.gd` | CanvasModulate + sun + shader daylight |
| `input_defaults.gd` | Default key bindings (W/S/A/D, Space, Up/Down) |

### Schemas (all data, no logic)

```
ZONE    { name, region, lat_lon, level_range: Vector2i, water_temp_c: Vector2, max_depth_m,
          current_px_s, wind_px_s, baits[], rigs[], species[], description }
SPECIES { name, scientific, role: prey|predator, weight_kg: Vector2, thermal_band: Vector2 (0..1),
          depth_m: Vector2, schooling, base_price,
          fight { pull_n, stamina_drain, burst_every_s, burst_mult, burst_len_s, rest_recovery } }
RIG     { name, rod_stiffness, line_stiffness, line_break_force_n, drag_max_n, spool_m, min_level }
BAIT    { name, kind: live|natural|lure, bite_bonus }
```

### Zone progression

| Zone | Levels | Target species | Baits | Rig |
|---|---|---|---|---|
| Aegean Sea (Cesme / Izmir) | 1-5 | Gilthead Seabream, European Seabass, Red Mullet | Live Sand-worm, Cut Squid | Light Bottom Rig |
| Tokyo Bay | 6-14 | Japanese Seabass, Red Seabream, Japanese Horse Mackerel | Live Shrimp, Soft Plastic Shad | Light Spinning Rig |
| Amazon River | 10-20 | Peacock Bass, Red-tailed Catfish, Arapaima | Live Baitfish, Crankbait | Light Spinning, Heavy River Baitcaster |
| North Sea (Norway Fjords) | 15-25 | Atlantic Cod, Haddock, Atlantic Halibut | Heavy Jig, Cut Squid | Deep Sea Boat Rig |
| Great Barrier Reef | 20-30 | Giant Trevally, Coral Trout, Spanish Mackerel | Surface Popper, Sinking Stickbait, Heavy Jig | Heavy Saltwater Spinning |

Balance rule baked into the data: **drag_max_n < line_break_force_n < peak burst force of the top fish in the zone**. The player cannot out-muscle a trophy; they must manage the clutch. Adding a zone is one dictionary entry, and `validate()` reports any dangling reference.

## 2. Vector and Force Mathematical Analysis

### 2.1 Perlin current and wind (Nature of Code flow field)

```
theta(x,y,t) = 1.6 * 2*pi * P1(f*x, f*y, s*t)                 flow direction
|c|          = c_max * (0.25 + 0.75 * clamp(P2 mapped to 0..1))  flow speed
c(x,y,t)     = |c| * (cos theta, sin theta)                    px/s
```
Perlin noise is smooth, so neighbouring water flows in similar directions (gyres, eddies and channels appear without simulation). Time is the third noise axis (`s` is small), so the field slowly evolves. The 1.6 factor compensates for Perlin rarely reaching +-1, so directions cover the full circle. Wind uses lower frequency and independent seeds.

### 2.2 Boat drift (fluid resistance)

```
v_rel  = v - c(x)
v_side = v_rel.slide(heading)                 sideways slip
v_fwd  = v_rel - v_side                       motion along the hull
F      = thrust*heading + k_wind*w(x)
         - (c1 + c2*|v_fwd|) * v_fwd * D      low hull drag
         - c_lat * v_side * D                 keel grip, bleeds sideways momentum
v     += F / m * dt                           m = hull + cargo, D = cargo drag multiplier
yaw   += (steer * torque * authority / I - damping * yaw) * dt     heading.rotate(yaw*dt)
```
Drag acts on velocity **relative to the water**. Turning rotates the heading only, so momentum keeps pointing the old way and the keel bleeds it off over about 1-2 s: that is the skid. With no thrust the boat relaxes toward `c + wind push / c1`. Cargo adds mass, extra drag `D = 1 + 0.25*load + 2.5*overload` and extra yaw inertia, so an overloaded boat is slow and lazy (about 60% top speed at 130% load). Rudder authority scales with through-water speed.

### 2.3 Autonomous fish (Reynolds steering)

Each fish applies `steer = clamp(desired_velocity - velocity, max_force)` for every behaviour, then sums with weights:

* **Separation** `-sum(offset / d^2)` for neighbours inside `separation_px` (stronger when close).
* **Alignment** toward the mean neighbour velocity. **Cohesion** toward the neighbour centroid.
* **Habitat comfort** is the gradient of `comfort(T)`. `T` is the thermal Perlin field and `comfort` is 1 inside the species' `thermal_band` and falls to 0 outside it, so schools slide toward their preferred water temperature and scatter as the field evolves.
* **Predator seek** toward the nearest prey fish. **Prey flee** from the nearest predator and from the boat inside `scare_radius_px`.
* **Home arena** `-p` once outside `arena_radius_px`, so schools do not wander off forever.

The water current pushes positions by `current_push * c(x)`. Depth limits are in the data (`depth_m`), ready for a seabed map; temperature is already live.

### 2.4 Reel struggle (1D spring-mass, Hooke's law)

Axis: distance from rod tip to fish. Rod and line are springs in series.

```
k_eff  = k_rod * k_line / (k_rod + k_line)       a soft rod lowers k_eff: it absorbs bursts
ext    = x_fish - L_out                          line stretch
T      = max(0, k_eff*ext + c_line*v_fish)       tension (N), zero when slack
m*a    = F_pull - T - c_water*v                  F_pull = pull_n * lerp(0.35, 1, stamina) * burst
dL_out = -reel_speed*dt   (reel held)  +  g*max(0, T - D)*dt     D = drag setting (clutch slip)
dstamina = -alpha*T*dt  (tension tires the fish)   +beta*dt when slack
```
* Rod bend shown on screen is `T / k_rod`, normalised.
* Damping ratio of the fight is `zeta = c_line / (2*sqrt(k_eff * m))`, about 0.5 for the Aegean defaults. That means about 16% overshoot, so a burst can briefly exceed its steady pull. This is the source of the "line sings" feeling.
* Drag setting `D` is the safety valve: above it the clutch releases line (`g*(T-D)`), capping tension near `D`. Too low and the fish takes the spool (`L_out >= spool_m` snaps); too high and bursts break the line.
* Line fatigue: above `overload_ratio` (85% of break force) damage accumulates and the line snaps at 100% fatigue or instantly at 125%.
* Slack for `slack_escape_s` lets the fish throw the hook.
* Reeling while a fish runs raises `ext` quickly and spikes tension. Good play is to release Space on bursts, pump and reel on rests.

Telemetry: the `telemetry(frame)` signal emits every physics frame with distance, line out, tension, ratio, drag, stamina, fish speed, burst multiplier, fatigue and slack time. Set `print_telemetry = true` to log it every 0.25 s while tuning.

## 3. Scene wiring

```
Main (Node2D)
|- CanvasModulate                 <- DayNightCycle.canvas_modulate
|- WaterSurface (Sprite2D)        script water_surface.gd; assign boat, camera
|- OceanCurrentField (Node)       script ocean_current_field.gd
|- ProgressionManager (Node)      set current_zone; call bind_fishing(FishingController)
|- Boat (Boat)                    CharacterBody2D + sprite; assign current_field, progression
|- FishInteractionAI (Node)       assign schools[], current_field, boat, fishing, progression
|- SonarSystem (Node)             assign boat, schools[], progression
|- UI (CanvasLayer)
|   |- SonarDisplay (Control)     assign sonar, boat, fish_ai
|   `- DebugOverlay               assign boat, progression, fishing, fish_ai, sonar (F3 toggles)
|- FishSchool (x N)               assign current_field, scare_source = Boat, thermal_band from species
|- FishingController (Node)
|- DayNightCycle (Node)           assign canvas_modulate, water
`- Camera2D (follow Boat)
```

Fishing loop (call from your UI code):

```gdscript
var rng := RandomNumberGenerator.new()
var id := BiomeDB.roll_species("aegean_sea", rng)
var species := BiomeDB.get_species(id)
fishing.apply_rig(BiomeDB.get_rig("light_bottom_rig"))
boat.thrust_enabled = false                       # drift while fighting
fishing.hook_fish(id, species, BiomeDB.roll_weight_kg(id, rng))
fishing.fish_caught.connect(func(fid, kg): print("Caught %s %.1f kg" % [fid, kg]))
fishing.line_snapped.connect(func(fid): print("Line snapped!"))
```

Controls: W/S throttle, A/D steer, **hold Space** reel, **Up/Down** raise/lower the drag clutch.

## 4. Shader notes

* Depth tint comes from a procedural depth map (`depth_bias` per biome). Normals come from finite differences of two animated fBm layers. Sun glints and sky fresnel are scaled by `daylight`.
* Caustics are two warped ridged-noise layers multiplied together, visible only in shallow water and scaled by `daylight`.
* Wake has two parts. **Foam trail**: up to 32 recorded boat positions upload as uniform arrays (`trail_points`, `trail_ages`, `trail_power`). The shader measures distance to each segment, widens and fades foam by age, and breaks it up with noise, so turns leave curved trails. **Kelvin V arms**: analytic arms at 19.47 degrees behind the boat heading, with travelling crest ripples that also bend the water normals.
* Day/night: the shader writes plain `COLOR`, so Godot multiplies it by `CanvasModulate` and lights it with `Light2D`. `DayNightCycle` additionally sets `daylight` so glints and caustics die away at night instead of just darkening.
* Tuning knobs: `depth_bias`, `wave_frequency`, `normal_strength`, `wake_width_end`, `trail_lifetime`, `caustic_strength`.

Not run in Godot yet. First launch should show `[BiomeDB] 5 zones, 15 species, 5 rigs, 9 baits - OK` in the output. Please report any parse error with its line number so it can be fixed.

## 5. Nibble, bite and sonar (see CALIBRATION_GUIDE.md)

```gdscript
fish_ai.cast_from_boat("live_sandworm", "light_bottom_rig", 120.0, 8.0)   # bait out, boat drifts
# ...nibble_felt / solid_bite signals fire; the player presses reel_in inside the window
# fish_ai then calls progression.prepare_fight() + fishing.hook_fish() itself
fish_ai.retrieve()                                                         # reel the bait in
sonar.ping_now()                                                           # or leave auto_ping on
```

Every school must be in both `fish_ai.schools` and `sonar.schools`. Fish are plain arrays, so the bait scan and the sonar ping are single loops with `distance_to`, with no Area2D nodes.
