## 1D spring-mass fishing fight (Hooke's law). Axis x = distance from rod tip to fish (metres).
##
##   k_eff = k_rod * k_line / (k_rod + k_line)          rod and line are springs in series
##   ext   = x_fish - L_out                              how far the line is stretched
##   T     = max(0, k_eff * ext + c_line * v_fish)       line tension (N), 0 when slack
##   m a   = F_pull(stamina, burst) - T - c_water * v    fish dynamics
##   L_out' = -reel_speed (reel held)  +  g * max(0, T - drag)   (clutch slips above drag setting)
##
## Player verbs:  hold reel_in (Space) | drag_up / drag_down (Up / Down) to set the clutch.
## Win: bring the fish within landing_distance_m.  Lose: line snaps, spool empties, or fish shakes the hook.
class_name FishingController
extends Node

enum State { IDLE, HOOKED, LANDED, SNAPPED, ESCAPED }

signal hooked(fish_id: String, weight_kg: float)
signal tension_updated(tension_n: float, ratio: float, rod_bend: float)
signal line_snapped(fish_id: String)
signal fish_caught(fish_id: String, weight_kg: float)
signal fish_escaped(fish_id: String)
signal telemetry(frame: Dictionary)

@export_group("Rod and Line")
@export var rod_stiffness_n_per_m := 90.0
@export var line_stiffness_n_per_m := 900.0
@export var line_damping := 18.0            ## N*s/m acting on fish velocity
@export var line_break_force_n := 35.0
@export var rod_max_bend_m := 0.6           ## only normalises the visual bend value
@export var spool_capacity_m := 90.0

@export_group("Reel")
@export var reel_speed_m_s := 2.4
@export var drag_min_n := 3.0
@export var drag_max_n := 22.0
@export var drag_adjust_n_s := 10.0
@export var drag_slip_m_s_per_n := 0.12     ## line paid out per second per newton above the drag setting
@export var landing_distance_m := 1.5

@export_group("Rules")
@export var overload_ratio := 0.85          ## above this fraction of break force, line fatigue builds
@export var hard_break_ratio := 1.25        ## instant snap
@export var fatigue_rate := 1.6
@export var slack_tension_ratio := 0.04
@export var slack_escape_s := 2.5
@export var substeps := 4
@export var heave_to_line := 0.1            ## metres of line stretch per metre of boat heave (waves shake the rod)
@export var print_telemetry := false

var state := State.IDLE
var drag_setting_n := 10.0
var tension_n := 0.0
var stamina := 1.0
var fish_pos_m := 0.0
var fish_vel_m_s := 0.0
var line_out_m := 0.0
var fatigue := 0.0
var slack_time := 0.0
var fish_id := ""
var fish_weight_kg := 0.0
var rod_heave_m := 0.0                       ## set by BoatWavePhysics every frame

var _fish_mass := 1.0
var _fish_pull_n := 10.0
var _fish_water_drag := 6.0
var _stamina_drain := 0.003
var _rest_recovery := 0.02
var _burst_every := Vector2(3.0, 6.0)
var _burst_mult_range := Vector2(1.5, 2.1)
var _burst_len := Vector2(0.5, 1.4)
var _burst_left := 0.0
var _burst_cooldown := 2.0
var _burst_mult := 1.0
var _rng := RandomNumberGenerator.new()
var _telemetry_clock := 0.0


func _ready() -> void:
	_rng.randomize()
	InputDefaults.ensure_all()


## Copy a BiomeDB rig dictionary onto this controller.
func apply_rig(rig: Dictionary) -> void:
	rod_stiffness_n_per_m = rig.get("rod_stiffness", rod_stiffness_n_per_m)
	line_stiffness_n_per_m = rig.get("line_stiffness", line_stiffness_n_per_m)
	line_break_force_n = rig.get("line_break_force_n", line_break_force_n)
	drag_max_n = rig.get("drag_max_n", drag_max_n)
	spool_capacity_m = rig.get("spool_m", spool_capacity_m)
	drag_setting_n = clampf(drag_setting_n, drag_min_n, drag_max_n)


## Start a fight. species = BiomeDB.get_species(id), weight_kg = BiomeDB.roll_weight_kg(...).
func hook_fish(id: String, species: Dictionary, weight_kg: float, start_distance_m := 20.0) -> void:
	var fight: Dictionary = species["fight"]
	var wr: Vector2 = species["weight_kg"]
	var size01 := clampf(inverse_lerp(wr.x, wr.y, weight_kg), 0.0, 1.0)
	fish_id = id
	fish_weight_kg = weight_kg
	_fish_mass = maxf(weight_kg, 1.0)
	_fish_pull_n = float(fight["pull_n"]) * lerpf(0.7, 1.0, size01)
	_fish_water_drag = 6.0 + 0.5 * _fish_mass
	_stamina_drain = fight["stamina_drain"]
	_rest_recovery = fight["rest_recovery"]
	_burst_every = fight["burst_every_s"]
	_burst_mult_range = fight["burst_mult"]
	_burst_len = fight["burst_len_s"]

	stamina = 1.0
	tension_n = 0.0
	fatigue = 0.0
	slack_time = 0.0
	fish_pos_m = start_distance_m
	fish_vel_m_s = 0.0
	line_out_m = start_distance_m - 0.5
	_burst_left = 0.0
	_burst_mult = 1.0
	_burst_cooldown = _rng.randf_range(_burst_every.x, _burst_every.y) * 0.5
	drag_setting_n = clampf(drag_setting_n, drag_min_n, minf(drag_max_n, line_break_force_n * 0.95))
	state = State.HOOKED
	hooked.emit(fish_id, fish_weight_kg)


func _physics_process(delta: float) -> void:
	if state != State.HOOKED:
		return
	var upper := minf(drag_max_n, line_break_force_n * 0.95)
	drag_setting_n = clampf(drag_setting_n + Input.get_axis(&"drag_down", &"drag_up") * drag_adjust_n_s * delta, drag_min_n, upper)

	var h := delta / float(substeps)
	for i in substeps:
		_update_fish_behaviour(h)
		_integrate(h)
		if state != State.HOOKED:
			break
	_report(delta)


func _update_fish_behaviour(h: float) -> void:
	if _burst_left > 0.0:
		_burst_left -= h
		if _burst_left <= 0.0:
			_burst_mult = 1.0
			_burst_cooldown = _rng.randf_range(_burst_every.x, _burst_every.y)
	else:
		_burst_cooldown -= h
		if _burst_cooldown <= 0.0 and stamina > 0.25:
			_burst_left = _rng.randf_range(_burst_len.x, _burst_len.y)
			_burst_mult = _rng.randf_range(_burst_mult_range.x, _burst_mult_range.y)
		elif _burst_cooldown <= 0.0:
			_burst_cooldown = 1.0                  # too tired to run


func _integrate(h: float) -> void:
	var k_eff := (rod_stiffness_n_per_m * line_stiffness_n_per_m) / (rod_stiffness_n_per_m + line_stiffness_n_per_m)

	# 1. line tension from the spring + damper
	var ext := fish_pos_m - line_out_m + rod_heave_m * heave_to_line
	var t := 0.0
	if ext > 0.0:
		t = maxf(0.0, k_eff * ext + line_damping * fish_vel_m_s)

	# 2. reel and clutch change how much line is out
	if Input.is_action_pressed(&"reel_in"):
		line_out_m -= reel_speed_m_s * h
	if t > drag_setting_n:
		line_out_m += (t - drag_setting_n) * drag_slip_m_s_per_n * h
	line_out_m = clampf(line_out_m, 0.0, spool_capacity_m + 1.0)

	# 3. fish dynamics (semi-implicit Euler)
	var pull := _fish_pull_n * lerpf(0.35, 1.0, stamina) * _burst_mult
	var acc := (pull - t - _fish_water_drag * fish_vel_m_s) / _fish_mass
	fish_vel_m_s += acc * h
	fish_pos_m += fish_vel_m_s * h
	if fish_pos_m < 0.0:
		fish_pos_m = 0.0
		fish_vel_m_s = maxf(fish_vel_m_s, 0.0)

	# 4. stamina: tension tires the fish, a slack line lets it rest
	var ratio := t / line_break_force_n
	stamina -= _stamina_drain * t * h
	if ratio < slack_tension_ratio:
		stamina += _rest_recovery * h
	stamina = clampf(stamina, 0.0, 1.0)
	tension_n = t

	# 5. outcomes
	if ratio > overload_ratio:
		fatigue += (ratio - overload_ratio) / (1.0 - overload_ratio) * fatigue_rate * h
	else:
		fatigue = maxf(0.0, fatigue - 0.5 * h)
	if ratio >= hard_break_ratio or fatigue >= 1.0 or line_out_m >= spool_capacity_m:
		_finish(State.SNAPPED)
		return

	if ratio < slack_tension_ratio:
		slack_time += h
	else:
		slack_time = maxf(0.0, slack_time - 2.0 * h)
	if slack_time >= slack_escape_s:
		_finish(State.ESCAPED)
		return

	if fish_pos_m <= landing_distance_m:
		_finish(State.LANDED)


func _finish(new_state: State) -> void:
	state = new_state
	tension_n = 0.0
	match new_state:
		State.SNAPPED:
			line_snapped.emit(fish_id)
		State.ESCAPED:
			fish_escaped.emit(fish_id)
		State.LANDED:
			fish_caught.emit(fish_id, fish_weight_kg)


func _report(delta: float) -> void:
	var ratio := tension_n / line_break_force_n
	var bend := clampf(tension_n / rod_stiffness_n_per_m / rod_max_bend_m, 0.0, 1.0)
	tension_updated.emit(tension_n, ratio, bend)
	var frame := {
		"distance_m": snappedf(fish_pos_m, 0.01),
		"line_out_m": snappedf(line_out_m, 0.01),
		"tension_n": snappedf(tension_n, 0.01),
		"tension_ratio": snappedf(ratio, 0.001),
		"drag_n": snappedf(drag_setting_n, 0.01),
		"stamina": snappedf(stamina, 0.001),
		"fish_speed": snappedf(fish_vel_m_s, 0.01),
		"burst": _burst_mult,
		"fatigue": snappedf(fatigue, 0.001),
		"slack_s": snappedf(slack_time, 0.01),
		"state": State.keys()[state],
	}
	telemetry.emit(frame)
	if print_telemetry:
		_telemetry_clock += delta
		if _telemetry_clock >= 0.25:
			_telemetry_clock = 0.0
			print("[fight] ", frame)
