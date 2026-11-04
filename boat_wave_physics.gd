## Drop-in component for the Boat: turns weather into forces. Add it as a child Node of the Boat,
## assign `weather`, and set Boat.wave_physics to it. Boat calls step() once per physics frame and
## gets back plain vectors, so there are no rigidbodies and no extra collision shapes.
##
## What it computes (all deterministic math):
##   wind drag   F_w = k * |w_rel| * w_rel,   w_rel = wind - boat_velocity   (apparent wind, quadratic)
##   wave push   F_v = -wave_push * slope(pos, t)            the boat slides down the wave face
##   wave drift  Stokes drift is added to the water velocity the hull drags against
##   yaw kick    side-on slope turns the bow;  anchored boats weathervane into the wind
##   slamming    head seas add hull drag ~ Hs * how directly you face the swell
##   rocking     roll / pitch / heave drive a visual Node2D, heave also shakes the fishing rod
##   anchor      Hooke spring:  T = max(0, k * (dist - L_eff) + c * v_away),   L_eff = rope - lift * crest height
##               crests shorten the rope, so the anchor line jerks in waves; above hold force the anchor drags.
class_name BoatWavePhysics
extends Node

signal anchor_changed(is_down: bool)
signal anchor_dragging(tension_n: float)

@export var weather: WeatherManager
@export var boat: Boat                       ## used only for the rocking visual offset
@export var fishing: FishingController       ## optional: waves shake the rod tip
@export var visual: Node2D                   ## optional: the boat sprite root, it rocks and bobs

@export_group("Wind")
@export var wind_drag_k := 0.8               ## N per (px/s)^2. Storm (44 px/s) gives about 1500 N.
@export var windage := 1.0                   ## exposed area multiplier: big cabin 1.3, low skiff 0.8

@export_group("Waves")
@export var wave_push_n := 3500.0            ## N per unit slope
@export var wave_yaw_gain := 1.6             ## rad/s^2 per unit of side slope
@export var slam_drag_gain := 0.05           ## extra hull drag per metre of Hs in a head sea

@export_group("Rocking Visual")
@export var roll_deg_per_slope := 40.0
@export var pitch_scale_per_slope := 0.5
@export var heave_scale_per_m := 0.02

@export_group("Anchor")
@export var anchor_rope_px := 90.0
@export var anchor_k_n_per_px := 40.0
@export var anchor_damp_n_s_per_px := 35.0
@export var anchor_hold_n := 1800.0          ## above this tension the anchor starts dragging
@export var anchor_drag_px_s_per_n := 0.02
@export var anchor_lift_px_per_m := 6.0
@export var anchor_weathervane := 1.4

@export var print_telemetry := false

var anchored := false
var anchor_pos := Vector2.ZERO
var anchor_tension_n := 0.0
var heave_m := 0.0
var roll := 0.0
var pitch := 0.0
var wind_force := Vector2.ZERO
var wave_force := Vector2.ZERO
var telemetry := {}

var _orbit_px := Vector2.ZERO
var _log_clock := 0.0


func _ready() -> void:
	InputDefaults.ensure_all()


func toggle_anchor(pos: Vector2) -> void:
	if anchored:
		anchored = false
		anchor_tension_n = 0.0
	else:
		anchored = true
		anchor_pos = pos
	anchor_changed.emit(anchored)


## Returns {force: Vector2 (N), water_drift: Vector2 (px/s), yaw_accel: float, drag_add: float}.
func step(delta: float, pos: Vector2, vel: Vector2, heading: Vector2) -> Dictionary:
	var out := {"force": Vector2.ZERO, "water_drift": Vector2.ZERO, "yaw_accel": 0.0, "drag_add": 0.0}
	if weather == null:
		return out
	if Input.is_action_just_pressed(&"anchor"):
		toggle_anchor(pos)

	# 1. apparent-wind drag
	var w_rel := weather.get_wind(pos) - vel
	wind_force = w_rel * w_rel.length() * wind_drag_k * windage

	# 2. waves
	var s := weather.sample_waves(pos)
	var slope: Vector2 = s["slope"]
	heave_m = float(s["height_m"])
	_orbit_px = s["orbit_px"]
	var lateral := Vector2(-heading.y, heading.x)
	roll = slope.dot(lateral)
	pitch = slope.dot(heading)
	wave_force = -slope * wave_push_n

	var force := wind_force + wave_force
	var yaw := roll * wave_yaw_gain

	# 3. head seas slam the hull
	var head_sea := maxf(-heading.dot(weather.swell_dir), 0.0)
	out["drag_add"] = slam_drag_gain * weather.sea_hs_m * head_sea

	# 4. anchor line as a spring that only pulls
	anchor_tension_n = 0.0
	if anchored:
		var to_anchor := anchor_pos - pos
		var dist := to_anchor.length()
		var rope_eff := maxf(anchor_rope_px - maxf(heave_m, 0.0) * anchor_lift_px_per_m, 8.0)
		if dist > rope_eff and dist > 0.001:
			var dir := to_anchor / dist
			var away := -vel.dot(dir)                   # speed of moving away from the anchor
			anchor_tension_n = maxf(0.0, anchor_k_n_per_px * (dist - rope_eff) + anchor_damp_n_s_per_px * away)
			force += dir * anchor_tension_n
			if anchor_tension_n > anchor_hold_n:
				anchor_pos -= dir * (anchor_tension_n - anchor_hold_n) * anchor_drag_px_s_per_n * delta
				anchor_dragging.emit(anchor_tension_n)
		# a moored boat swings its bow into the wind
		var into_wind := -weather.wind_dir
		yaw += (heading.x * into_wind.y - heading.y * into_wind.x) * weather.wind_strength01() * anchor_weathervane

	if fishing:
		fishing.rod_heave_m = heave_m

	out["force"] = force
	out["water_drift"] = s["drift_px_s"]
	out["yaw_accel"] = yaw
	_publish(delta)
	return out


func _process(_delta: float) -> void:
	if visual == null:
		return
	visual.rotation = deg_to_rad(roll * roll_deg_per_slope)
	visual.scale = Vector2(1.0 + pitch * pitch_scale_per_slope, 1.0 + heave_m * heave_scale_per_m)
	if boat:
		visual.position = _orbit_px.rotated(-boat.rotation)


func _publish(delta: float) -> void:
	telemetry = {
		"heave_m": heave_m,
		"roll_deg": rad_to_deg(atan(roll)),
		"pitch_deg": rad_to_deg(atan(pitch)),
		"wind_force_n": wind_force.length(),
		"wave_force_n": wave_force.length(),
		"anchored": anchored,
		"anchor_tension_n": anchor_tension_n,
		"anchor_hold_n": anchor_hold_n,
	}
	if print_telemetry:
		_log_clock += delta
		if _log_clock >= 1.0:
			_log_clock = 0.0
			print("[waves] ", telemetry)
