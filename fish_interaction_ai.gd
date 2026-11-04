## Nibble & Bite engine. Runs the whole "bait in the water" phase until a fish is hooked.
##
## Flow:  IDLE -> WANDERING -> APPROACHING -> NIBBLING -> BITING -> HOOKED (spring-mass fight)
##                                   \-> BITING directly for aggressive species (0 nibbles)
##        SPOOKED = fish bolted or stole the bait; short cooldown, then WANDERING again.
##
## Caveman rules:
##  * No Area2D. Every tick we loop over the school arrays and use distance_to() against the bait.
##  * Only ONE fish at a time runs the nibble state machine (the most interested one). Others just crowd.
##  * 1D Perlin noise (FastNoiseLite.get_noise_1d) drives nibble pulses and the fish's moment of nerve.
##
## Player verbs (all on the reel_in action, Space by default):
##  * press while WANDERING/APPROACHING -> retrieve the bait
##  * press during a NIBBLE   -> too early: the fish may be spooked (species spook_chance)
##  * press during the BITE window -> hook set, FishingController takes over
class_name FishInteractionAI
extends Node

enum State { IDLE, WANDERING, APPROACHING, NIBBLING, BITING, SPOOKED, HOOKED }

signal state_changed(new_state: int, old_state: int)
signal rod_pulse(tension_n: float)                          ## every physics frame while bait is out: drive rod shake / UI
signal nibble_felt(strength_n: float, nibble_index: int, nibbles_needed: int)
signal solid_bite(window_s: float)
signal hook_set(fish_id: String, weight_kg: float)
signal bait_stolen(fish_id: String)
signal fish_spooked(fish_id: String)

@export_group("Wiring")
@export var schools: Array[FishSchool] = []
@export var current_field: OceanCurrentField
@export var boat: Boat
@export var fishing: FishingController
@export var progression: ProgressionManager
@export var weather: WeatherManager             ## optional: wind shortens casts, moves the bait, gates species
@export var lock_boat_while_cast := true        ## no engine while bait is out: you drift on the current

@export_group("Bait Attraction")
@export var attract_radius_px := 160.0
@export var touch_radius_px := 16.0
@export var depth_tolerance_m := 8.0            ## bait this far above/below a fish gives zero interest
@export var engage_threshold := 0.25
@export var approach_timeout_s := 14.0
@export var bait_drift_gain := 0.4              ## bait is pushed by the current
@export var px_per_m := 10.0
@export var bait_wind_gain := 0.15              ## wind pushes the floating bait
@export var bait_depth_speed := 5.0             ## Q / E move the bait up and down, metres per second
@export var bait_depth_max := 120.0                    ## converts bait distance to fight start distance

@export_group("Nibble Noise")
@export var nibble_threshold := 0.62            ## pulse is felt while noise01 is above this
@export var nibble_hysteresis := 0.06
@export var commit_level := 0.5                 ## fish commits when its current caution drops below this
@export var pressure_per_s := 0.04              ## caution melts by this much per second after the last nibble
@export var spook_cooldown_s := 6.0

@export var print_telemetry := false

var state := State.IDLE
var bait_id := ""
var rig_id := ""
var bait_pos := Vector2.ZERO
var bait_depth_m := 8.0
var rod_tension_n := 0.0
var interest_score := 0.0
var cast_range_mult := 1.0                      ## last cast: 1.0 = no wind effect, below 1 = headwind
var telemetry := {}

var _school: FishSchool
var _idx := -1
var _profile := {}
var _profiles := {}
var _gate_cache := {}
var _best_school: FishSchool
var _best_idx := -1
var _best_score := 0.0
var _bait_bonus := 1.0
var _time := 0.0
var _state_time := 0.0
var _cooldown := 0.0
var _lost_s := 0.0
var _nibbles_needed := 0
var _nibbles_done := 0
var _above := false
var _since_done := 0.0
var _caution_now := 0.0
var _bite_timer := 0.0
var _nib_off := 0.0
var _caution_off := 0.0
var _nib_noise := FastNoiseLite.new()
var _caution_noise := FastNoiseLite.new()
var _hunger_noise := FastNoiseLite.new()
var _rng := RandomNumberGenerator.new()
var _log_clock := 0.0


func _ready() -> void:
	_rng.randomize()
	for n: FastNoiseLite in [_nib_noise, _caution_noise, _hunger_noise]:
		n.noise_type = FastNoiseLite.TYPE_PERLIN
		n.fractal_type = FastNoiseLite.FRACTAL_FBM
		n.fractal_octaves = 2
		n.frequency = 1.0
		n.seed = _rng.randi()
	InputDefaults.ensure_all()
	if fishing:
		bind_fishing(fishing)


## Connects the fight outcomes. Call this if `fishing` is assigned after _ready (e.g. by a scene script).
func bind_fishing(fc: FishingController) -> void:
	fishing = fc
	if not fc.fish_caught.is_connected(_on_caught):
		fc.fish_caught.connect(_on_caught)
	if not fc.line_snapped.is_connected(_on_lost):
		fc.line_snapped.connect(_on_lost)
	if not fc.fish_escaped.is_connected(_on_lost):
		fc.fish_escaped.connect(_on_lost)


# ---------------------------------------------------------------- public API
func cast(p_bait_id: String, p_rig_id: String, global_pos: Vector2, depth_m: float) -> void:
	if state != State.IDLE:
		return
	bait_id = p_bait_id
	rig_id = p_rig_id
	bait_pos = global_pos
	bait_depth_m = depth_m
	_bait_bonus = float(BiomeDB.get_bait(bait_id).get("bite_bonus", 1.0))
	_clear_engagement()
	_cooldown = 0.0
	if boat and lock_boat_while_cast:
		boat.thrust_enabled = false
	_set_state(State.WANDERING)


## Convenience: drop the bait ahead of the boat.
## Wind matters: a headwind shortens the cast, a tailwind lengthens it, a crosswind bends it sideways.
func cast_from_boat(p_bait_id: String, p_rig_id: String, distance_px := 120.0, depth_m := 8.0) -> void:
	if boat == null:
		return
	var dir := boat.heading
	var dist := distance_px
	var offset := Vector2.ZERO
	cast_range_mult = 1.0
	if weather:
		cast_range_mult = weather.cast_range_multiplier(dir)
		dist *= cast_range_mult
		offset = weather.cast_wind_offset(dir, dist)
	cast(p_bait_id, p_rig_id, boat.global_position + dir * dist + offset, depth_m)


func retrieve() -> void:
	for school in schools:
		school.clear_bait()
	_clear_engagement()
	rod_tension_n = 0.0
	interest_score = 0.0
	if boat and lock_boat_while_cast:
		boat.thrust_enabled = true
	_set_state(State.IDLE)


# ---------------------------------------------------------------- main loop
func _physics_process(delta: float) -> void:
	if state == State.IDLE or state == State.HOOKED:
		rod_tension_n = 0.0
		_publish(delta)
		return
	_time += delta
	_state_time += delta
	_cooldown = maxf(_cooldown - delta, 0.0)
	_drift_bait(delta)
	_adjust_depth(delta)
	_scan()
	var reel_pressed := Input.is_action_just_pressed(&"reel_in")
	match state:
		State.WANDERING:
			_tick_wandering(reel_pressed)
		State.APPROACHING:
			_tick_approaching(delta, reel_pressed)
		State.NIBBLING:
			_tick_nibbling(delta, reel_pressed)
		State.BITING:
			_tick_biting(delta, reel_pressed)
		State.SPOOKED:
			_tick_spooked(reel_pressed)
	rod_pulse.emit(rod_tension_n)
	_publish(delta)


func _drift_bait(delta: float) -> void:
	var push := Vector2.ZERO
	if current_field:
		push += current_field.get_current(bait_pos) * bait_drift_gain
	if weather:
		push += weather.get_wind(bait_pos) * bait_wind_gain
	bait_pos += push * delta


## One pass over all fish: flag the ones close enough to care, score them, remember the best.
func _scan() -> void:
	_best_school = null
	_best_idx = -1
	_best_score = 0.0
	var engaged_score := 0.0
	for school in schools:
		if state == State.SPOOKED:
			school.set_bait(bait_pos, attract_radius_px)
			school.approaching.fill(0)
			continue
		school.set_bait(bait_pos, attract_radius_px)
		var prof := _get_profile(school.species_id)
		for i in school.positions.size():
			var d := school.fish_global(i).distance_to(bait_pos)
			if d > attract_radius_px:
				school.approaching[i] = 0
				continue
			school.approaching[i] = 1
			var score := _interest(school, i, d, prof)
			if school == _school and i == _idx:
				engaged_score = score
			if score > _best_score:
				_best_score = score
				_best_school = school
				_best_idx = i
	if state == State.SPOOKED:
		interest_score = 0.0
	else:
		interest_score = engaged_score if _school != null else _best_score


## Interest = bait quality * closeness^2 * depth match * hunger (slow Perlin per fish) * species appetite.
func _interest(school: FishSchool, i: int, d: float, prof: Dictionary) -> float:
	var closeness := 1.0 - d / attract_radius_px
	var depth_match := clampf(1.0 - absf(school.depths_m[i] - bait_depth_m) / depth_tolerance_m, 0.0, 1.0)
	var hunger := _n01(_hunger_noise, float(i) * 7.3, _time * 0.05 + float(school.get_index()) * 11.0)
	return _bait_bonus * closeness * closeness * depth_match * lerpf(0.6, 1.0, hunger) * float(prof["appetite"]) * _weather_factor(school.species_id)


# ---------------------------------------------------------------- state ticks
func _tick_wandering(reel_pressed: bool) -> void:
	if reel_pressed:
		retrieve()
		return
	if _best_school != null and _best_score >= engage_threshold and _cooldown <= 0.0:
		_school = _best_school
		_idx = _best_idx
		_profile = _get_profile(_school.species_id)
		_lost_s = 0.0
		_set_state(State.APPROACHING)


func _tick_approaching(delta: float, reel_pressed: bool) -> void:
	if reel_pressed:
		retrieve()
		return
	if not _engaged_valid():
		_disengage(2.0)
		return
	var d := _school.fish_global(_idx).distance_to(bait_pos)
	if d <= touch_radius_px:
		_begin_contact()
		return
	if interest_score < engage_threshold * 0.4:
		_lost_s += delta
	else:
		_lost_s = 0.0
	if _lost_s > 2.0 or _state_time > approach_timeout_s or d > attract_radius_px * 1.4:
		_disengage(2.0)


func _begin_contact() -> void:
	var nb: Vector2i = _profile["nibbles"]
	_nibbles_needed = _rng.randi_range(nb.x, nb.y)
	_nibbles_done = 0
	_above = false
	_since_done = 0.0
	_nib_off = _rng.randf() * 1000.0
	_caution_off = _rng.randf() * 1000.0
	if _nibbles_needed == 0:
		_enter_bite()
	else:
		_set_state(State.NIBBLING)


func _tick_nibbling(delta: float, reel_pressed: bool) -> void:
	if not _engaged_valid():
		_disengage(2.0)
		return
	if reel_pressed and _rng.randf() < float(_profile["spook_chance"]):
		_spook(true)                                  # reeled too early
		return

	# light nibbles: 1D Perlin pulse, a nibble is counted on each upward crossing of the threshold
	var hz := float(_profile["noise_hz"])
	var s01 := _n01(_nib_noise, _state_time * hz + _nib_off)
	var over := maxf(s01 - nibble_threshold, 0.0) / (1.0 - nibble_threshold)
	rod_tension_n = over * float(_profile["nibble_force_n"])
	if not _above and s01 >= nibble_threshold:
		_above = true
		_nibbles_done += 1
		nibble_felt.emit(float(_profile["nibble_force_n"]) * lerpf(0.5, 1.0, _rng.randf()), _nibbles_done, _nibbles_needed)
	elif _above and s01 < nibble_threshold - nibble_hysteresis:
		_above = false

	# moment of nerve: after enough nibbles, caution wobbles on slow noise and melts with time
	if _nibbles_done >= _nibbles_needed:
		_since_done += delta
		var wobble := _n01(_caution_noise, _state_time * hz * 0.25 + _caution_off) * 2.0 - 1.0
		_caution_now = clampf(float(_profile["caution"]) + 0.3 * wobble - pressure_per_s * _since_done, 0.0, 1.0)
		if _caution_now < commit_level:
			_enter_bite()
			return
	if _state_time > float(_profile["max_nibble_s"]):
		_disengage(3.0)                               # lost interest, no drama


func _enter_bite() -> void:
	_bite_timer = float(_profile["bite_window_s"])
	_set_state(State.BITING)
	solid_bite.emit(_bite_timer)


func _tick_biting(delta: float, reel_pressed: bool) -> void:
	if not _engaged_valid():
		_disengage(2.0)
		return
	_bite_timer -= delta
	var throb := _n01(_nib_noise, _state_time * 8.0 + _nib_off)
	rod_tension_n = float(_profile["strike_force_n"]) * lerpf(0.65, 1.0, throb)
	if reel_pressed:
		_set_hook()
		return
	if _bite_timer <= 0.0:
		if _rng.randf() < float(_profile["self_hook_chance"]):
			_set_hook()                               # aggressive fish hook themselves
		else:
			bait_stolen.emit(_school.species_id)
			_spook(false)


func _tick_spooked(reel_pressed: bool) -> void:
	if reel_pressed:
		retrieve()
		return
	if _cooldown <= 0.0:
		_clear_engagement()
		_set_state(State.WANDERING)


# ---------------------------------------------------------------- transitions
func _spook(announce: bool) -> void:
	var id := _school.species_id if _school else ""
	if _engaged_valid():
		_school.kick_fish(_idx, bait_pos)
	if announce:
		fish_spooked.emit(id)
	_cooldown = spook_cooldown_s
	rod_tension_n = 0.0
	_set_state(State.SPOOKED)


func _disengage(cooldown_s: float) -> void:
	_clear_engagement()
	_cooldown = cooldown_s
	rod_tension_n = 0.0
	_set_state(State.WANDERING)


## Hands the fish to the spring-mass fight in FishingController.
func _set_hook() -> void:
	if not _engaged_valid() or fishing == null:
		push_warning("[FishInteractionAI] hook set without an engaged fish or a FishingController")
		retrieve()
		return
	var id := _school.species_id
	var species := BiomeDB.get_species(id)
	var kg := _school.weights_kg[_idx]
	if progression:
		progression.prepare_fight(fishing, rig_id)
	else:
		fishing.apply_rig(BiomeDB.get_rig(rig_id))
	var dist_m := 14.0
	if boat:
		dist_m = clampf(boat.global_position.distance_to(bait_pos) / px_per_m, 6.0, 40.0)
	rod_tension_n = 0.0
	_set_state(State.HOOKED)
	hook_set.emit(id, kg)
	fishing.hook_fish(id, species, kg, dist_m)


func _on_caught(_fish_id: String, _kg: float) -> void:
	if state != State.HOOKED:
		return
	if _engaged_valid():
		_school.remove_fish(_idx)
	retrieve()


func _on_lost(_fish_id: String) -> void:
	if state != State.HOOKED:
		return
	if _engaged_valid():
		_school.kick_fish(_idx, bait_pos)
	retrieve()


func _set_state(new_state: State) -> void:
	var old := state
	state = new_state
	_state_time = 0.0
	if old != new_state:
		state_changed.emit(new_state, old)


# ---------------------------------------------------------------- helpers
func _engaged_valid() -> bool:
	return _school != null and _idx >= 0 and _idx < _school.positions.size()


func _clear_engagement() -> void:
	_school = null
	_idx = -1
	_profile = {}
	_nibbles_needed = 0
	_nibbles_done = 0
	_caution_now = 0.0
	_bite_timer = 0.0


## Weather gate and appetite: gated species (Swordfish) ignore the bait outside their weather state.
func _weather_factor(species_id: String) -> float:
	if weather == null:
		return 1.0
	if not _gate_cache.has(species_id):
		_gate_cache[species_id] = BiomeDB.get_weather_traits(species_id).get("gate_states", [])
	var gates: Array = _gate_cache[species_id]
	if not gates.is_empty() and not gates.has(weather.state_key()):
		return 0.0
	return weather.bite_multiplier()


## Q / E move the bait up and down while it is in the water.
func _adjust_depth(delta: float) -> void:
	var axis := Input.get_axis(&"bait_shallower", &"bait_deeper")
	bait_depth_m = clampf(bait_depth_m + axis * bait_depth_speed * delta, 1.0, bait_depth_max)


func _get_profile(species_id: String) -> Dictionary:
	if not _profiles.has(species_id):
		_profiles[species_id] = BiomeDB.get_bite_profile(species_id)
	return _profiles[species_id]


## Noise remapped to 0..1 (Perlin rarely reaches +-1, so it is stretched a little).
func _n01(noise: FastNoiseLite, x: float, y := INF) -> float:
	var raw := noise.get_noise_1d(x) if y == INF else noise.get_noise_2d(x, y)
	return clampf(raw * 1.4 * 0.5 + 0.5, 0.0, 1.0)


func _publish(delta: float) -> void:
	var species_name := ""
	if _engaged_valid():
		species_name = String(BiomeDB.get_species(_school.species_id).get("name", ""))
	telemetry = {
		"state": State.keys()[state],
		"species": species_name,
		"interest": interest_score,
		"nibbles": "%d/%d" % [_nibbles_done, _nibbles_needed],
		"caution_now": _caution_now,
		"bite_timer_s": maxf(_bite_timer, 0.0) if state == State.BITING else 0.0,
		"rod_tension_n": rod_tension_n,
		"bait_depth_m": bait_depth_m,
		"cast_range_pct": cast_range_mult * 100.0,
	}
	if print_telemetry and state != State.IDLE:
		_log_clock += delta
		if _log_clock >= 0.5:
			_log_clock = 0.0
			print("[fish-ai] ", telemetry)
