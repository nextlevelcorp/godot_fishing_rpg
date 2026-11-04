## Active sonar. Sends an expanding ping ring from the boat. Each fish the ring passes may produce
## a contact (blip). What the contact carries depends on the sonar tier (ProgressionManager "sonar" track):
##   detail 0  raw blips only              detail 1  + size class (Small / Medium / Trophy)
##   detail 2  + exact depth (metres)
## Accuracy scales with the tier: detection chance, position error, false echoes ("ghosts"), range.
## Efficiency % of a ping = real fish detected / real fish that were inside the range.
## No Area2D: one loop over the school arrays while a ping is travelling.
class_name SonarSystem
extends Node

signal ping_started(range_px: float)
signal ping_finished(efficiency_pct: float, detected: int, in_range: int)

const BASIC := {
	"name": "Basic Fishfinder", "value": 220.0, "detail": 0, "detect_prob": 0.7,
	"pos_error_px": 14.0, "ghost_rate": 0.3, "ping_interval_s": 2.4,
}

@export var boat: Boat
@export var schools: Array[FishSchool] = []
@export var progression: ProgressionManager
@export var weather: WeatherManager          ## optional: rough sea hides fish and adds false echoes
@export var auto_ping := true
@export var pulse_speed_px_s := 700.0
@export var contact_life_s := 7.0
@export var print_telemetry := false

var contacts: Array[Dictionary] = []     ## {pos, age, size (0..2), depth, ghost}
var pulse_active := false
var pulse_radius := 0.0
var range_px := 220.0
var detail := 0
var tier_name := "Basic Fishfinder"
var last_efficiency_pct := -1.0          ## -1 = nothing was in range
var avg_efficiency_pct := -1.0
var telemetry := {}

var _profile: Dictionary = BASIC
var _prev_radius := 0.0
var _in_range := 0
var _hits := 0
var _ping_cd := 0.5
var _time := 0.0
var _eff_history: Array[float] = []
var _clutch_noise := FastNoiseLite.new()
var _rng := RandomNumberGenerator.new()
var _log_clock := 0.0


func _ready() -> void:
	_rng.randomize()
	_clutch_noise.noise_type = FastNoiseLite.TYPE_PERLIN
	_clutch_noise.frequency = 1.0
	_clutch_noise.seed = _rng.randi()


func _physics_process(delta: float) -> void:
	_time += delta
	_age_contacts(delta)
	if pulse_active:
		_advance_pulse(delta)
	elif auto_ping:
		_ping_cd -= delta
		if _ping_cd <= 0.0:
			ping_now()
	_publish(delta)


## Starts a ping (does nothing while one is still travelling).
func ping_now() -> void:
	if pulse_active:
		return
	_profile = progression.sonar_profile() if progression else BASIC
	range_px = float(_profile["value"])
	detail = int(_profile["detail"])
	tier_name = String(_profile["name"])
	var origin := _origin()
	_in_range = 0
	_hits = 0
	for school in schools:
		for i in school.positions.size():
			if school.fish_global(i).distance_to(origin) <= range_px:
				_in_range += 1
	pulse_radius = 0.0
	_prev_radius = 0.0
	pulse_active = true
	ping_started.emit(range_px)


func _advance_pulse(delta: float) -> void:
	_prev_radius = pulse_radius
	pulse_radius = minf(pulse_radius + pulse_speed_px_s * delta, range_px)
	var origin := _origin()
	var detect := float(_profile["detect_prob"])
	var err := float(_profile["pos_error_px"])
	var engine_noise := 1.0 - 0.2 * (boat.speed01 if boat else 0.0)   # a fast boat hears less
	engine_noise *= 1.0 - 0.3 * (weather.turbulence01 if weather else 0.0)   # a rough sea hides fish
	var trophy_min := float(ProgressionManager.GRADES["trophy"]["min_size01"])

	for school in schools:
		for i in school.positions.size():
			var g := school.fish_global(i)
			var d := g.distance_to(origin)
			if d > pulse_radius or (d <= _prev_radius and _prev_radius > 0.0):
				continue                                   # the ring is not passing this fish right now
			var size01 := school.size01(i)
			var p := detect * (1.0 - 0.35 * d / range_px) * lerpf(0.7, 1.0, size01) * engine_noise
			if _rng.randf() > p:
				continue
			_hits += 1
			contacts.append({
				"pos": g + Vector2.from_angle(_rng.randf() * TAU) * _rng.randf() * err,
				"age": 0.0,
				"size": 2 if size01 >= trophy_min else (1 if size01 >= 0.35 else 0),
				"depth": school.depths_m[i],
				"ghost": false,
			})
	if pulse_radius >= range_px:
		_finish_ping(origin)


func _finish_ping(origin: Vector2) -> void:
	pulse_active = false
	# false echoes: more of them when sea clutter (slow Perlin) is high and the sonar is cheap
	var clutch := clampf(_clutch_noise.get_noise_1d(_time * 0.3) * 1.4 * 0.5 + 0.5, 0.0, 1.0)
	var sea_clutter := 1.0 + 2.0 * (weather.turbulence01 if weather else 0.0)
	if _rng.randf() < float(_profile["ghost_rate"]) * lerpf(0.4, 1.0, clutch) * sea_clutter:
		contacts.append({
			"pos": origin + Vector2.from_angle(_rng.randf() * TAU) * range_px * sqrt(_rng.randf()),
			"age": 0.0,
			"size": _rng.randi_range(0, 1),
			"depth": _rng.randf_range(3.0, 30.0),
			"ghost": true,
		})
	last_efficiency_pct = -1.0 if _in_range == 0 else clampf(100.0 * float(_hits) / float(_in_range), 0.0, 100.0)
	if last_efficiency_pct >= 0.0:
		_eff_history.append(last_efficiency_pct)
		if _eff_history.size() > 10:
			_eff_history.pop_front()
		var total := 0.0
		for e in _eff_history:
			total += e
		avg_efficiency_pct = total / float(_eff_history.size())
	_ping_cd = float(_profile["ping_interval_s"])
	ping_finished.emit(last_efficiency_pct, _hits, _in_range)


func _age_contacts(delta: float) -> void:
	var i := contacts.size() - 1
	while i >= 0:
		contacts[i]["age"] = float(contacts[i]["age"]) + delta
		if float(contacts[i]["age"]) > contact_life_s:
			contacts.remove_at(i)
		i -= 1


func _origin() -> Vector2:
	return boat.global_position if boat else Vector2.ZERO


func _publish(delta: float) -> void:
	var ghosts := 0
	for c in contacts:
		if c["ghost"]:
			ghosts += 1
	telemetry = {
		"efficiency_pct": last_efficiency_pct,
		"avg_efficiency_pct": avg_efficiency_pct,
		"contacts": contacts.size(),
		"ghosts": ghosts,
		"tier": tier_name,
		"range_px": range_px,
		"detail": detail,
	}
	if print_telemetry:
		_log_clock += delta
		if _log_clock >= 1.0:
			_log_clock = 0.0
			print("[sonar] ", telemetry)
