## Global weather engine. One Node in the main scene; every other system reads it through an @export.
## (If you make it an autoload, name the autoload "Weather", NOT "WeatherManager": it would clash with class_name.)
##
## Chain of cause and effect, all driven by Perlin noise:
##   severity (0..1, very slow 1D noise)  ->  weather STATE (thresholds + hysteresis)
##   severity                              ->  wind knots   (+ fast gust noise)
##   wind heading                          ->  slow 1D noise, the wind wanders around a prevailing direction
##   wind speed                            ->  target significant wave height  Hs = gain * 0.0246 * U^2 (m, U in m/s)
##   Hs                                    ->  sea builds up slowly (a gale needs time to raise a sea) and dies down slower
##   4 overlapping travelling waves        ->  Gerstner-style height, slope, orbital offset, Stokes drift
## Directions: wind_from_deg is the compass bearing the wind blows FROM (marine convention, 0 = N, 90 = E).
##             wind_dir / wind_vector point where it blows TO. Godot 2D: +x east, -y north.
class_name WeatherManager
extends Node

enum State { CALM, OVERCAST, GALE, STORM }

signal state_changed(new_state: int, old_state: int)

const STATE_NAMES := ["Calm / Sunny", "Overcast / Rainy", "Heavy Gale", "Super Typhoon / Storm"]
const STATE_KEYS := ["calm", "overcast", "gale", "storm"]
const STATE_COLORS := [Color(0.45, 0.90, 0.55), Color(0.95, 0.85, 0.40), Color(1.0, 0.55, 0.25), Color(1.0, 0.25, 0.30)]
const STATE_MID_SEVERITY := [0.15, 0.47, 0.69, 0.92]       ## severity used when a state is forced
const BEAUFORT_KNOTS := [1.0, 4.0, 7.0, 11.0, 17.0, 22.0, 28.0, 34.0, 41.0, 48.0, 56.0, 64.0]
const COMPASS := ["N", "NNE", "NE", "ENE", "E", "ESE", "SE", "SSE", "S", "SSW", "SW", "WSW", "W", "WNW", "NW", "NNW"]
const BITE_X := [0.0, 0.36, 0.58, 0.80, 1.0]               ## severity breakpoints for the bite multiplier
const BITE_Y := [0.95, 1.20, 1.00, 0.60, 0.30]             ## overcast = pre-front feeding frenzy, storm = fish shut down
const KNOT_TO_MS := 0.514444
const GRAVITY := 9.81
const WAVE_COUNT := 4
const WAVE_SHARE := [0.50, 0.27, 0.15, 0.08]               ## share of the total amplitude per component
const WAVE_LENGTH := [1.0, 0.55, 0.32, 0.19]               ## wavelength relative to the main swell
const WAVE_SPREAD_DEG := [0.0, 22.0, -28.0, 48.0]          ## direction offset from the swell
const WAVE_PHASE := [0.0, 1.9, 4.1, 5.3]

@export_group("Evolution")
@export var weather_seed := 4242
@export var time_scale := 1.0                       ## 1 = real time. Use 10-30 to test storms quickly.
@export var severity_period_s := 420.0              ## one weather "front" passes about every 7 minutes
@export var start_calm := true
@export_enum("Auto:-1", "Calm:0", "Overcast:1", "Gale:2", "Storm:3") var forced_state := -1
@export var state_thresholds := Vector3(0.36, 0.58, 0.80)   ## severity for OVERCAST, GALE, STORM
@export var hysteresis := 0.03
@export var severity_smoothing_s := 4.0

@export_group("Wind")
@export var min_knots := 2.0
@export var max_knots := 62.0
@export var wind_curve := 2.0                       ## knots = lerp(min, max, severity ^ curve)
@export var gust_gain := 0.35
@export var gust_period_s := 9.0
@export var heading_period_s := 600.0
@export var heading_swing_deg := 140.0
@export var base_heading_from_deg := 300.0          ## prevailing wind comes from the north-west
@export var px_per_knot := 0.8
@export var local_variation := 0.15                 ## wind differs a little from place to place

@export_group("Sea State")
@export var sea_state_gain := 0.7                   ## scales the textbook Hs = 0.0246 U^2
@export var max_hs_m := 12.0
@export var sea_buildup_s := 45.0
@export var stokes_gain := 2.0                      ## strength of the steady wave drift on the surface
@export var px_per_m := 10.0

var state: int = State.CALM
var severity := 0.0
var wind_knots := 0.0
var wind_from_deg := 0.0
var wind_dir := Vector2.RIGHT
var wind_vector := Vector2.ZERO                     ## px/s, the way the air moves
var sea_hs_m := 0.1                                 ## significant wave height
var wave_amplitude_m := 0.05                        ## Hs / 2: what the dashboard calls amplitude
var turbulence01 := 0.0                             ## sea roughness 0..1, used by fish, sonar, shader
var cloud01 := 0.0
var swell_dir := Vector2.RIGHT
var pressure_hpa := 1020.0
var pressure_trend := "Steady"
var telemetry := {}

var _t := 0.0
var _main_len_m := 20.0
var _trend_clock := 0.0
var _sev_ref := 0.0
var _k := PackedFloat32Array()
var _w := PackedFloat32Array()
var _amp := PackedFloat32Array()
var _theta := PackedFloat32Array()
var _dir := PackedVector2Array()
var _sev_noise := FastNoiseLite.new()
var _dir_noise := FastNoiseLite.new()
var _gust_noise := FastNoiseLite.new()
var _local_noise := FastNoiseLite.new()


func _ready() -> void:
	process_physics_priority = -10                  # update before the boat reads us
	var i := 0
	for n: FastNoiseLite in [_sev_noise, _dir_noise, _gust_noise, _local_noise]:
		n.noise_type = FastNoiseLite.TYPE_PERLIN
		n.fractal_type = FastNoiseLite.FRACTAL_FBM
		n.fractal_octaves = 2
		n.frequency = 1.0
		n.seed = weather_seed + i * 977
		i += 1
	for arr: PackedFloat32Array in [_k, _w, _amp, _theta]:
		arr.resize(WAVE_COUNT)
	_dir.resize(WAVE_COUNT)

	_t = _find_start_time()
	severity = _severity_target()
	for step in 4:
		_update_state()
	_sev_ref = severity
	_update_wind()
	sea_hs_m = _target_hs()
	swell_dir = wind_dir
	_main_len_m = _target_len()
	_update_waves(0.0)
	_update_derived()
	_publish()


func _physics_process(delta: float) -> void:
	var dt := delta * time_scale
	_t += dt
	var target := _severity_target()
	severity += (target - severity) * (1.0 - exp(-dt / maxf(severity_smoothing_s, 0.01)))
	_update_state()
	_update_wind()
	_update_sea(dt)
	_update_waves(delta)
	_update_derived()

	_trend_clock += dt
	if _trend_clock >= 25.0:
		var d := severity - _sev_ref
		pressure_trend = "Falling" if d > 0.008 else ("Rising" if d < -0.008 else "Steady")
		_sev_ref = severity
		_trend_clock = 0.0
	_publish()


# ---------------------------------------------------------------- weather evolution
func _sev_at(t: float) -> float:
	return clampf(0.5 + 0.75 * _sev_noise.get_noise_2d(t / severity_period_s, 11.0), 0.0, 1.0)


func _severity_target() -> float:
	if forced_state >= 0:
		return float(STATE_MID_SEVERITY[clampi(forced_state, 0, 3)])
	return _sev_at(_t)


## First moment (searching forward) where the sea is calm, so a new game starts in sunshine.
func _find_start_time() -> float:
	if not start_calm or forced_state >= 0:
		return 0.0
	for k in 600:
		var t := float(k) * 0.05 * severity_period_s
		if _sev_at(t) < 0.26:
			return t
	return 0.0


func _update_state() -> void:
	var thr := [state_thresholds.x, state_thresholds.y, state_thresholds.z]
	var s: int = state
	if s < State.STORM and severity > float(thr[s]) + hysteresis:
		s += 1
	elif s > State.CALM and severity < float(thr[s - 1]) - hysteresis:
		s -= 1
	if s != state:
		var old := state
		state = s
		state_changed.emit(state, old)


func _update_wind() -> void:
	var base_knots := lerpf(min_knots, max_knots, pow(severity, wind_curve))
	var gust_raw := _gust_noise.get_noise_2d(_t / gust_period_s, 33.0)
	wind_knots = maxf(base_knots * (1.0 + gust_gain * severity * gust_raw * 1.5), 0.0)
	var h_raw := _dir_noise.get_noise_2d(_t / heading_period_s, 77.0)
	wind_from_deg = fposmod(base_heading_from_deg + heading_swing_deg * h_raw * 1.4, 360.0)
	wind_dir = Vector2.UP.rotated(deg_to_rad(wind_from_deg + 180.0))
	wind_vector = wind_dir * wind_knots * px_per_knot


# ---------------------------------------------------------------- sea state and waves
func _target_hs() -> float:
	var u := wind_knots * KNOT_TO_MS
	return clampf(sea_state_gain * 0.0246 * u * u, 0.05, max_hs_m)


func _target_len() -> float:
	var u := wind_knots * KNOT_TO_MS
	return clampf(0.2 * u * u, 12.0, 110.0)


func _update_sea(dt: float) -> void:
	var target := _target_hs()
	var tau := sea_buildup_s if target > sea_hs_m else sea_buildup_s * 1.6
	sea_hs_m += (target - sea_hs_m) * (1.0 - exp(-dt / tau))


func _update_waves(delta: float) -> void:
	swell_dir = swell_dir.lerp(wind_dir, 1.0 - exp(-delta / sea_buildup_s))
	if swell_dir.length_squared() < 0.01:
		swell_dir = wind_dir
	swell_dir = swell_dir.normalized()
	_main_len_m += (_target_len() - _main_len_m) * (1.0 - exp(-delta / 60.0))
	wave_amplitude_m = sea_hs_m * 0.5
	for i in WAVE_COUNT:
		var wl := _main_len_m * float(WAVE_LENGTH[i])
		_k[i] = TAU / wl
		_w[i] = sqrt(GRAVITY * _k[i])                 # deep-water dispersion: w^2 = g k
		_theta[i] += _w[i] * delta
		_amp[i] = wave_amplitude_m * float(WAVE_SHARE[i])
		_dir[i] = swell_dir.rotated(deg_to_rad(float(WAVE_SPREAD_DEG[i])))


func _update_derived() -> void:
	turbulence01 = clampf(sea_hs_m / max_hs_m, 0.0, 1.0)
	cloud01 = smoothstep(0.25, 0.65, severity)
	pressure_hpa = 1022.0 - 46.0 * severity


## Gerstner-style sample at a world position (px). Cheap: 4 sin/cos pairs.
##   height_m   water surface height
##   slope      gradient of the height (unitless, along the world axes)
##   drift_px_s steady Stokes drift of the surface water
##   orbit_px   horizontal orbital offset, for visual bobbing
func sample_waves(pos: Vector2) -> Dictionary:
	var out := {"height_m": 0.0, "slope": Vector2.ZERO, "drift_px_s": Vector2.ZERO, "orbit_px": Vector2.ZERO}
	if _k.size() < WAVE_COUNT:
		return out
	var x := pos / px_per_m
	var h := 0.0
	var slope := Vector2.ZERO
	var drift := Vector2.ZERO
	var orbit := Vector2.ZERO
	for i in WAVE_COUNT:
		var a := _amp[i]
		var phase := _k[i] * _dir[i].dot(x) - _theta[i] + float(WAVE_PHASE[i])
		var c := cos(phase)
		var s := sin(phase)
		h += a * c
		slope += _dir[i] * (-a * _k[i] * s)
		drift += _dir[i] * (_w[i] * _k[i] * a * a)
		orbit += _dir[i] * (a * s)
	out["height_m"] = h
	out["slope"] = slope
	out["drift_px_s"] = drift * px_per_m * stokes_gain
	out["orbit_px"] = orbit * px_per_m * 0.4
	return out


func wave_height_m(pos: Vector2) -> float:
	if _k.size() < WAVE_COUNT:
		return 0.0
	var x := pos / px_per_m
	var h := 0.0
	for i in WAVE_COUNT:
		h += _amp[i] * cos(_k[i] * _dir[i].dot(x) - _theta[i] + float(WAVE_PHASE[i]))
	return h


## Wind (px/s) at a place: the global vector with a little Perlin variation between locations.
func get_wind(pos: Vector2) -> Vector2:
	var v := _local_noise.get_noise_3d(pos.x * 0.0008, pos.y * 0.0008, _t * 0.05)
	return wind_vector * (1.0 + local_variation * v * 1.5)


# ---------------------------------------------------------------- helpers for other systems
func state_key() -> String:
	return STATE_KEYS[state]


func state_name() -> String:
	return STATE_NAMES[state]


func state_color() -> Color:
	return STATE_COLORS[state]


func wind_strength01() -> float:
	return clampf(wind_knots / max_knots, 0.0, 1.0)


func beaufort() -> int:
	var n := 0
	for limit in BEAUFORT_KNOTS:
		if wind_knots >= float(limit):
			n += 1
	return n


func wind_from_cardinal() -> String:
	return COMPASS[int(round(wind_from_deg / 22.5)) % 16]


## Casting along `dir`: tailwind carries the lure further, headwind shortens the cast.
func cast_range_multiplier(dir: Vector2) -> float:
	var a := dir.normalized().dot(wind_dir) * wind_strength01()       # +tailwind, -headwind
	return clampf(1.0 + (0.3 * a if a > 0.0 else 0.55 * a), 0.25, 1.3)


## Crosswind pushes the line sideways while it flies.
func cast_wind_offset(dir: Vector2, dist_px: float) -> Vector2:
	var d := dir.normalized()
	var side := wind_dir - d * wind_dir.dot(d)
	return side * wind_strength01() * 0.25 * dist_px


## How hungry fish are: pre-front frenzy under overcast skies, shut down in a storm.
func bite_multiplier() -> float:
	for i in BITE_X.size() - 1:
		if severity <= float(BITE_X[i + 1]):
			return remap(severity, float(BITE_X[i]), float(BITE_X[i + 1]), float(BITE_Y[i]), float(BITE_Y[i + 1]))
	return float(BITE_Y[BITE_Y.size() - 1])


func _publish() -> void:
	telemetry = {
		"state": state_name(),
		"wind_knots": wind_knots,
		"wind_from_deg": wind_from_deg,
		"wind_from": wind_from_cardinal(),
		"beaufort": beaufort(),
		"hs_m": sea_hs_m,
		"amplitude_m": wave_amplitude_m,
		"turbulence": turbulence01,
		"pressure_hpa": pressure_hpa,
		"trend": pressure_trend,
		"severity": severity,
		"bite_mult": bite_multiplier(),
	}
