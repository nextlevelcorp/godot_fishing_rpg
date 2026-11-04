## Autonomous fish school: Reynolds steering (separation, alignment, cohesion) + habitat comfort,
## predator seek, prey/boat flee, bait attraction and a soft home arena.
## Arrays of vectors, no per-fish nodes and no Area2D. O(n^2) is fine for ~40 fish per school.
## Every fish also carries a depth (metres, wandering on 1D Perlin noise inside the species band)
## and a weight (kg), so sonar can show size/depth and a hooked fish is the one you saw.
## Assumes schools are not rotated or scaled.
class_name FishSchool
extends Node2D

@export var species_id := ""
@export var current_field: OceanCurrentField
@export var count := 36
@export var is_predator := false
@export var prey_school: FishSchool         ## predators seek this
@export var predator_school: FishSchool     ## prey flee this
@export var weather: WeatherManager         ## storms push schools deeper, gated species follow the weather state
@export var scare_source: Node2D            ## usually the boat
@export var thermal_band := Vector2(0.35, 0.65)   ## comfortable 0..1 temperature (overridden by species data)
@export var max_speed := 55.0
@export var max_force := 140.0
@export var perception_px := 80.0
@export var separation_px := 22.0
@export var scare_radius_px := 140.0
@export var arena_radius_px := 450.0
@export var current_push := 0.5
@export var w_separation := 1.8
@export var w_alignment := 1.0
@export var w_cohesion := 0.9
@export var w_comfort := 1.4
@export var w_seek := 2.0
@export var w_flee := 3.0
@export var w_home := 1.2
@export var w_bait := 2.2                   ## pull toward the bait for fish flagged in `approaching`
@export var bait_arrive_px := 45.0          ## fish slow down inside this radius and hover at the bait
@export var depth_speed_m_s := 6.0          ## how fast fish change layer when the weather moves their band
@export var draw_scale := 1.0               ## debug triangle size
@export var depth_wander_hz := 0.04         ## how fast fish change depth
@export var debug_draw := true

var positions := PackedVector2Array()
var velocities := PackedVector2Array()
var depths_m := PackedFloat32Array()
var weights_kg := PackedFloat32Array()
var approaching := PackedByteArray()        ## 1 = this fish is interested in the bait
var bait_global := Vector2.INF
var bait_radius_px := 160.0

var _depth_range := Vector2(2.0, 40.0)
var _weight_range := Vector2(0.5, 5.0)
var _traits := {}
var _depth_noise := FastNoiseLite.new()
var _time := 0.0
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.randomize()
	_depth_noise.noise_type = FastNoiseLite.TYPE_PERLIN
	_depth_noise.frequency = 1.0
	_depth_noise.seed = _rng.randi()
	var known := false
	if species_id != "":
		var sp := BiomeDB.get_species(species_id)
		if not sp.is_empty():
			known = true
			_depth_range = sp["depth_m"]
			_weight_range = sp["weight_kg"]
			thermal_band = sp["thermal_band"]
			_traits = BiomeDB.get_weather_traits(species_id)
	for i in count:
		positions.append(Vector2.from_angle(_rng.randf() * TAU) * _rng.randf() * arena_radius_px * 0.4)
		velocities.append(Vector2.from_angle(_rng.randf() * TAU) * max_speed * 0.5)
		weights_kg.append(BiomeDB.roll_weight_kg(species_id, _rng) if known else lerpf(_weight_range.x, _weight_range.y, _rng.randf()))
		depths_m.append(0.0)
		approaching.append(0)
	for i in count:
		depths_m[i] = _depth_at(i)


func _physics_process(delta: float) -> void:
	_time += delta
	var n := positions.size()
	var new_vel := velocities.duplicate()
	for i in n:
		var p := positions[i]
		var v := velocities[i]
		var sep := Vector2.ZERO
		var ali := Vector2.ZERO
		var coh := Vector2.ZERO
		var neighbours := 0
		for j in n:
			if j == i:
				continue
			var offset := positions[j] - p
			var d := offset.length()
			if d > perception_px or d < 0.001:
				continue
			neighbours += 1
			ali += velocities[j]
			coh += positions[j]
			if d < separation_px:
				sep -= offset / (d * d)       # push away, stronger when closer

		var steer := Vector2.ZERO
		if neighbours > 0:
			steer += w_alignment * _steer_to(v, ali / neighbours)
			steer += w_cohesion * _steer_to(v, coh / neighbours - p)
			steer += w_separation * _steer_to(v, sep)

		steer += w_comfort * _steer_to(v, _comfort_gradient(to_global(p)))

		if is_predator and prey_school:
			var target := prey_school._nearest_global(to_global(p), perception_px * 3.0)
			if target != Vector2.INF:
				steer += w_seek * _steer_to(v, target - to_global(p))
		if predator_school:
			var threat := predator_school._nearest_global(to_global(p), perception_px * 2.0)
			if threat != Vector2.INF:
				steer += w_flee * _steer_to(v, to_global(p) - threat)
		if scare_source:
			var away := to_global(p) - scare_source.global_position
			if away.length() < scare_radius_px:
				steer += w_flee * _steer_to(v, away)

		# bait attraction: the closer the bait, the stronger the pull, and fish slow down on arrival
		if bait_global != Vector2.INF and approaching[i] == 1:
			var to_bait := bait_global - to_global(p)
			var falloff := clampf(1.0 - to_bait.length() / bait_radius_px, 0.15, 1.0)
			steer += w_bait * falloff * _arrive(v, to_bait, bait_arrive_px)

		if p.length() > arena_radius_px:
			steer += w_home * _steer_to(v, -p)

		new_vel[i] = (v + steer * delta).limit_length(max_speed)

	var drift := Vector2.ZERO
	if current_field:
		drift = current_field.get_current(global_position) * current_push
	for i in n:
		velocities[i] = new_vel[i]
		positions[i] += (new_vel[i] + drift) * delta
		depths_m[i] = move_toward(depths_m[i], _depth_at(i), depth_speed_m_s * delta)
	if debug_draw:
		queue_redraw()


# ---------------------------------------------------------------- public API
func set_bait(global_pos: Vector2, radius_px: float) -> void:
	bait_global = global_pos
	bait_radius_px = radius_px


func clear_bait() -> void:
	bait_global = Vector2.INF
	approaching.fill(0)


func fish_global(i: int) -> Vector2:
	return to_global(positions[i])


## 0 = smallest possible fish of this species, 1 = largest.
func size01(i: int) -> float:
	return clampf(inverse_lerp(_weight_range.x, _weight_range.y, weights_kg[i]), 0.0, 1.0)


## Scare one fish: it bolts away from a point and loses interest in the bait.
func kick_fish(i: int, from_global: Vector2) -> void:
	var dir := fish_global(i) - from_global
	if dir.length_squared() < 0.0001:
		dir = Vector2.from_angle(_rng.randf() * TAU)
	velocities[i] = dir.normalized() * max_speed
	approaching[i] = 0


func remove_fish(i: int) -> void:
	positions.remove_at(i)
	velocities.remove_at(i)
	depths_m.remove_at(i)
	weights_kg.remove_at(i)
	approaching.remove_at(i)


## For bite logic: distance from a world point (the lure) to the closest fish.
func nearest_fish_distance(world_pos: Vector2) -> float:
	var g := _nearest_global(world_pos, INF)
	return INF if g == Vector2.INF else g.distance_to(world_pos)


# ---------------------------------------------------------------- steering helpers
## Reynolds steering: desired velocity minus current velocity, clamped to max_force.
func _steer_to(v: Vector2, desired_dir: Vector2) -> Vector2:
	if desired_dir.length_squared() < 0.000001:
		return Vector2.ZERO
	return (desired_dir.normalized() * max_speed - v).limit_length(max_force)


## Like _steer_to but the desired speed shrinks to ~10% as the target gets close (hover at the bait).
func _arrive(v: Vector2, to_target: Vector2, slow_radius: float) -> Vector2:
	var d := to_target.length()
	if d < 0.001:
		return Vector2.ZERO
	var speed := max_speed * clampf(d / slow_radius, 0.1, 1.0)
	return (to_target / d * speed - v).limit_length(max_force)


## Depth wanders on 1D Perlin noise inside the species' preferred band. Weather moves the band:
##  * rough sea pushes the school deeper by storm_dive_m * turbulence (predators follow their prey's dive)
##  * gated species (Swordfish) stay deep and only rise to open_depth_m while the weather state allows it
func _depth_at(i: int) -> float:
	var band := _depth_range
	var dive := 0.0
	if weather:
		if _traits.has("gate_states") and (_traits["gate_states"] as Array).has(weather.state_key()):
			band = _traits.get("open_depth_m", _depth_range)
		dive = current_dive_m()
		if is_predator and prey_school != null:
			dive = maxf(dive, prey_school.current_dive_m() * 0.9)
	var n01 := clampf(_depth_noise.get_noise_1d(_time * depth_wander_hz + float(i) * 17.3) * 1.4 * 0.5 + 0.5, 0.0, 1.0)
	return lerpf(band.x, band.y, n01) + dive


## How many metres this school is currently pushed down by rough weather.
func current_dive_m() -> float:
	if weather == null:
		return 0.0
	return weather.turbulence01 * float(_traits.get("storm_dive_m", 0.0))


## 1 inside the thermal band, falling to 0 outside it.
func _comfort(world_pos: Vector2) -> float:
	if current_field == null:
		return 1.0
	var t := current_field.get_temperature_norm(world_pos)
	var center := (thermal_band.x + thermal_band.y) * 0.5
	var half := maxf((thermal_band.y - thermal_band.x) * 0.5, 0.01)
	return clampf(1.0 - maxf(absf(t - center) - half, 0.0) / 0.25, 0.0, 1.0)


func _comfort_gradient(world_pos: Vector2) -> Vector2:
	var e := 40.0
	return Vector2(
		_comfort(world_pos + Vector2(e, 0.0)) - _comfort(world_pos - Vector2(e, 0.0)),
		_comfort(world_pos + Vector2(0.0, e)) - _comfort(world_pos - Vector2(0.0, e)))


## Global position of the closest fish within max_dist, or Vector2.INF.
func _nearest_global(world_pos: Vector2, max_dist: float) -> Vector2:
	var best := Vector2.INF
	var best_d := max_dist
	for q in positions:
		var g := to_global(q)
		var d := g.distance_to(world_pos)
		if d < best_d:
			best_d = d
			best = g
	return best


func _draw() -> void:
	var base := Color(1.0, 0.45, 0.35) if is_predator else Color(0.9, 0.95, 1.0)
	for i in positions.size():
		var col := Color(1.0, 0.9, 0.3) if approaching[i] == 1 else base
		var dir := velocities[i].normalized()
		var side := Vector2(-dir.y, dir.x)
		var p := positions[i]
		var s := draw_scale
		draw_colored_polygon(PackedVector2Array([p + dir * 7.0 * s, p - dir * 4.0 * s + side * 3.0 * s, p - dir * 4.0 * s - side * 3.0 * s]), col)
