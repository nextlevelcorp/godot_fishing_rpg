## Minimal on-screen telemetry. Add as a node, assign boat / progression / fishing. F3 toggles it.
class_name DebugOverlay
extends CanvasLayer

@export var boat: Boat
@export var progression: ProgressionManager
@export var fishing: FishingController
@export var fish_ai: FishInteractionAI
@export var sonar: SonarSystem
@export var weather: WeatherManager
@export var wave_physics: BoatWavePhysics
@export var origin_px := Vector2(12.0, 10.0)
@export var start_visible := true

var _label := Label.new()


func _ready() -> void:
	layer = 100
	_label.position = origin_px
	_label.visible = start_visible
	_label.add_theme_font_size_override("font_size", 14)
	_label.add_theme_color_override("font_color", Color(0.92, 1.0, 0.95))
	_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_label.add_theme_constant_override("outline_size", 5)
	add_child(_label)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F3:
		_label.visible = not _label.visible


func _process(_delta: float) -> void:
	if not _label.visible:
		return
	var lines: PackedStringArray = []
	if boat and not boat.telemetry.is_empty():
		var t := boat.telemetry
		var drift: Vector2 = t["drift_vec"]
		lines.append("Current Speed:    %5.0f px/s  (%3.0f%%)" % [t["speed_px_s"], t["speed_pct"]])
		lines.append("Active Fluid Drift: %4.0f px/s @ %4.0f deg   slip %3.0f" % [t["drift_px_s"], rad_to_deg(drift.angle()), t["slip_px_s"]])
		lines.append("Cargo Weight:     %5.0f%%   (drag x%.2f)" % [t["cargo_pct"], t["drag_mult"]])
	if progression:
		var tier := progression.tier_name("reel")
		var base := progression.stat("reel")
		var line := "Line Strength:    Lv %d  %s  (+%.0f N)" % [progression.gear["reel"] + 1, tier, base]
		if fishing and fishing.state == FishingController.State.HOOKED:
			line += "  | tension %.0f / %.0f N" % [fishing.tension_n, fishing.line_break_force_n]
		lines.append(line)
		lines.append(progression.telemetry_line())
	if fish_ai and not fish_ai.telemetry.is_empty():
		var a := fish_ai.telemetry
		var state_name: String = a["state"]
		var shown := {"IDLE": "Idle", "WANDERING": "Wandering", "APPROACHING": "Approaching", "NIBBLING": "Nibbling", "BITING": "BITING", "SPOOKED": "Spooked", "HOOKED": "Hooked"}
		lines.append("Active Fish Interest Score: %.2f   Current State: %s   %s" % [a["interest"], shown.get(state_name, state_name), a["species"]])
		if state_name == "NIBBLING" or state_name == "BITING":
			lines.append("  nibbles %s | caution %.2f | rod %.1f N | bite window %.2f s" % [a["nibbles"], a["caution_now"], a["rod_tension_n"], a["bite_timer_s"]])
	if sonar and not sonar.telemetry.is_empty():
		var s := sonar.telemetry
		var eff: float = s["efficiency_pct"]
		var avg: float = s["avg_efficiency_pct"]
		lines.append("Sonar Ping Efficiency: %s (avg %s) | %s | contacts %d (ghosts %d) | range %.0f px" % [
			"--" if eff < 0.0 else "%.0f%%" % eff, "--" if avg < 0.0 else "%.0f%%" % avg, s["tier"], s["contacts"], s["ghosts"], s["range_px"]])
	if weather:
		lines.append("Wind Speed (Knots): %.1f   Wind Heading: %.0f deg (%s)   Wave Amplitude: %.2f m (Hs %.1f m)   Weather State: %s" % [
			weather.wind_knots, weather.wind_from_deg, weather.wind_from_cardinal(), weather.wave_amplitude_m, weather.sea_hs_m, weather.state_name()])
	if wave_physics and not wave_physics.telemetry.is_empty():
		var w := wave_physics.telemetry
		lines.append("Heave %+.1f m | roll %.0f deg | wind %.0f N | waves %.0f N | anchor %s %.0f/%.0f N" % [
			w["heave_m"], w["roll_deg"], w["wind_force_n"], w["wave_force_n"], "DOWN" if w["anchored"] else "up", w["anchor_tension_n"], w["anchor_hold_n"]])
	_label.text = "\n".join(lines)
