## Player boat.
## Caveman physics, all in water-relative terms:
##   v_rel  = velocity - current
##   v_side = v_rel.slide(heading)        sideways slip (what the keel resists)
##   v_fwd  = v_rel - v_side              motion along the hull (slender, low drag)
##   F      = thrust + wind - fwd_drag(v_fwd) - lat_drag(v_side)      (all scaled by cargo drag)
## Turning rotates `heading` only. Momentum keeps pointing the old way, the keel bleeds it off
## slowly, so the boat skids across the water and the current keeps pushing it sideways.
class_name Boat
extends CharacterBody2D

@export var current_field: OceanCurrentField
@export var progression: ProgressionManager
@export var wave_physics: BoatWavePhysics    ## optional: wind drag, wave push, rocking, anchor

@export_group("Engine")
@export var base_thrust_n := 2600.0          ## used when no ProgressionManager is assigned
@export var reverse_thrust_ratio := 0.4

@export_group("Hull and Water")
@export var hull_mass := 60.0
@export var mass_per_cargo_kg := 0.8
@export var fwd_drag_lin := 6.0              ## slender hull: low
@export var fwd_drag_quad := 0.04
@export var lat_drag := 28.0                 ## keel grip. Low = long skids, high = car-like grip
@export var wind_exposure := 6.0
@export var max_speed_ref := 200.0           ## only normalises speed for the wake and HUD

@export_group("Steering")
@export var yaw_torque := 5.0                ## rad/s^2 at full rudder and full authority
@export var yaw_damping := 3.0               ## steady yaw rate = torque / damping, about 1.7 rad/s
@export var rudder_speed_ref := 60.0         ## through-water speed at which the rudder bites fully
@export var prop_wash_authority := 0.25      ## minimum rudder bite while throttle is on

@export_group("Cargo Penalties")
@export var load_drag_gain := 0.25           ## extra drag at 100% cargo
@export var overload_drag_gain := 2.5        ## extra drag per 100% over capacity
@export var load_turn_gain := 0.5            ## extra yaw inertia at 100% cargo
@export var overload_turn_gain := 3.0

@export var print_telemetry := false

var heading := Vector2.RIGHT
var yaw_rate := 0.0
var speed01 := 0.0
var thrust_enabled := true                   ## set false while fighting a fish to simply drift
var telemetry := {}
var _log_clock := 0.0


func _ready() -> void:
	motion_mode = CharacterBody2D.MOTION_MODE_FLOATING
	InputDefaults.ensure_all()


func get_thrust_n() -> float:
	return progression.stat("engine") if progression else base_thrust_n


func get_cargo_ratio() -> float:
	return progression.cargo_ratio() if progression else 0.0


func _physics_process(delta: float) -> void:
	var throttle := 0.0
	var steer := 0.0
	if thrust_enabled:
		throttle = Input.get_axis(&"boat_back", &"boat_forward")
		steer = Input.get_axis(&"steer_left", &"steer_right")

	# --- cargo penalties: heavier = more mass, more drag, lazier rudder ---
	var cargo_ratio := get_cargo_ratio()
	var over := maxf(cargo_ratio - 1.0, 0.0)
	var drag_mult := 1.0 + load_drag_gain * minf(cargo_ratio, 1.0) + overload_drag_gain * over
	var turn_inertia := 1.0 + load_turn_gain * minf(cargo_ratio, 1.0) + overload_turn_gain * over
	var cargo_kg := progression.cargo.total_kg if progression else 0.0
	var mass := hull_mass + cargo_kg * mass_per_cargo_kg

	# --- water and wind ---
	var current := Vector2.ZERO
	var wind := Vector2.ZERO
	if current_field:
		current = current_field.get_current(global_position)
		wind = current_field.get_wind(global_position)

	# --- weather component: wind drag, wave push, Stokes drift, head-sea slamming, anchor ---
	var wave := {}
	var wave_force := Vector2.ZERO
	var wave_yaw := 0.0
	var water_vel := current
	if wave_physics:
		wave = wave_physics.step(delta, global_position, velocity, heading)
		wave_force = wave["force"]
		wave_yaw = wave["yaw_accel"]
		var wave_drift: Vector2 = wave["water_drift"]
		water_vel += wave_drift
		drag_mult += float(wave["drag_add"])

	var v_rel := velocity - water_vel
	var v_side := v_rel.slide(heading)
	var v_fwd := v_rel - v_side
	var thrust := get_thrust_n() * (1.0 if throttle >= 0.0 else reverse_thrust_ratio)

	var force := heading * throttle * thrust
	if wave_physics:
		force += wave_force
	else:
		force += wind * wind_exposure
	force -= v_fwd * (fwd_drag_lin + fwd_drag_quad * v_fwd.length()) * drag_mult
	force -= v_side * lat_drag * drag_mult
	velocity += force / mass * delta

	# --- steering: torque on heading, damped, scaled by how fast water flows past the rudder ---
	var fwd_speed := v_fwd.dot(heading)
	var authority := clampf(fwd_speed / rudder_speed_ref, -1.0, 1.0)
	if throttle > 0.0:
		authority = maxf(authority, prop_wash_authority)
	yaw_rate += (steer * yaw_torque * authority / turn_inertia + wave_yaw - yaw_damping * yaw_rate) * delta
	heading = heading.rotated(yaw_rate * delta).normalized()

	move_and_slide()
	rotation = heading.angle()
	speed01 = clampf(velocity.length() / max_speed_ref, 0.0, 1.0)

	telemetry = {
		"speed_px_s": velocity.length(),
		"speed_pct": speed01 * 100.0,
		"drift_vec": current,
		"drift_px_s": current.length(),
		"slip_px_s": v_side.length(),
		"cargo_pct": cargo_ratio * 100.0,
		"drag_mult": drag_mult,
		"yaw_rate": yaw_rate,
		"wave_drift_px_s": (water_vel - current).length(),
		"thrust_n": get_thrust_n(),
	}
	if print_telemetry:
		_log_clock += delta
		if _log_clock >= 0.5:
			_log_clock = 0.0
			print("[boat] speed %.0f (%.0f%%) | current %.0f px/s | slip %.0f | cargo %.0f%% | drag x%.2f" % [
				telemetry["speed_px_s"], telemetry["speed_pct"], telemetry["drift_px_s"],
				telemetry["slip_px_s"], telemetry["cargo_pct"], telemetry["drag_mult"]])
