## Marine HUD controller. Caveman style: every frame, read a few numbers from the backend and write them
## into labels and bars. No logic lives here; the physics scripts stay the single source of truth.
##
##   top-left      level, XP, coins, cargo weight bar            <- ProgressionManager (cargo.total_kg / capacity_kg)
##   top-right     weather state, wind knots, wind vane, waves   <- WeatherManager (wind_knots, wind_dir, sea_hs_m)
##   bottom-centre line tension bar (Hooke spring)               <- FishingController (tension_n / line_break_force_n)
##   bottom-left   sonar scope                                   <- SonarSystem contacts (SonarDisplay widget)
## Call setup() once from the scene script, or assign the exports in the editor.
class_name FishingHud
extends Control

const GREEN := Color(0.35, 0.90, 0.50)
const YELLOW := Color(1.0, 0.85, 0.30)
const RED := Color(1.0, 0.30, 0.30)
const CYAN := Color(0.35, 0.85, 1.0)
const WHITE := Color(1.0, 1.0, 1.0)

@export var boat: Boat
@export var progression: ProgressionManager
@export var weather: WeatherManager
@export var fishing: FishingController       ## the spring-mass fishing line
@export var fish_ai: FishInteractionAI
@export var sonar: SonarSystem
@export var wave_physics: BoatWavePhysics

@export_group("Tension colours")
@export var safe_below := 0.60               ## tension / break force below this is green
@export var warn_below := 0.85               ## yellow up to here, then red (this is where line fatigue starts)
@export var idle_hint := "C cast   |   X anchor   |   Q / E bait depth"

@onready var zone_label: Label = %ZoneLabel
@onready var level_label: Label = %LevelLabel
@onready var coins_label: Label = %CoinsLabel
@onready var xp_bar: ProgressBar = %XpBar
@onready var xp_label: Label = %XpLabel
@onready var cargo_label: Label = %CargoLabel
@onready var cargo_bar: ProgressBar = %CargoBar
@onready var cargo_note: Label = %CargoNote
@onready var state_label: Label = %StateLabel
@onready var wind_vane: Control = %WindVane
@onready var wind_label: Label = %WindLabel
@onready var heading_label: Label = %HeadingLabel
@onready var sea_label: Label = %SeaLabel
@onready var baro_label: Label = %BaroLabel
@onready var anchor_label: Label = %AnchorLabel
@onready var tension_title: Label = %TensionTitle
@onready var tension_value: Label = %TensionValue
@onready var tension_bar: ProgressBar = %TensionBar
@onready var info_label: Label = %InfoLabel
@onready var stamina_row: Control = %StaminaRow
@onready var stamina_bar: ProgressBar = %StaminaBar
@onready var bite_label: Label = %BiteLabel
@onready var toast_label: Label = %ToastLabel
@onready var sonar_display: SonarDisplay = %SonarDisplay

var _time := 0.0
var _toast_s := 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	wind_vane.draw.connect(_draw_wind_vane)
	toast_label.modulate.a = 0.0
	bite_label.visible = false
	cargo_note.text = ""
	_push_refs()
	_connect_events()


## One call wires everything (used by the sandbox scene script).
func setup(p_boat: Boat, p_progression: ProgressionManager, p_weather: WeatherManager,
		p_fishing: FishingController, p_fish_ai: FishInteractionAI, p_sonar: SonarSystem,
		p_wave_physics: BoatWavePhysics) -> void:
	boat = p_boat
	progression = p_progression
	weather = p_weather
	fishing = p_fishing
	fish_ai = p_fish_ai
	sonar = p_sonar
	wave_physics = p_wave_physics
	_push_refs()
	_connect_events()


func show_toast(text: String, color := WHITE) -> void:
	toast_label.text = text
	toast_label.add_theme_color_override(&"font_color", color)
	_toast_s = 3.5


func _push_refs() -> void:
	sonar_display.sonar = sonar
	sonar_display.boat = boat
	sonar_display.fish_ai = fish_ai


func _connect_events() -> void:
	if fishing:
		_link(fishing.fish_caught, _on_caught)
		_link(fishing.line_snapped, _on_snapped)
		_link(fishing.fish_escaped, _on_escaped)
	if progression:
		_link(progression.leveled_up, _on_level_up)
		_link(progression.cargo_rejected, _on_cargo_rejected)
		_link(progression.fish_sold, _on_sold)
		_link(progression.gear_upgraded, _on_gear_upgraded)
	if fish_ai:
		_link(fish_ai.bait_stolen, _on_bait_stolen)
		_link(fish_ai.fish_spooked, _on_spooked)
	if weather:
		_link(weather.state_changed, _on_weather_changed)


func _link(sig: Signal, handler: Callable) -> void:
	if not sig.is_connected(handler):
		sig.connect(handler)


func _process(delta: float) -> void:
	_time += delta
	_update_player()
	_update_weather()
	_update_tension()
	_toast_s = maxf(_toast_s - delta, 0.0)
	toast_label.modulate.a = clampf(_toast_s, 0.0, 1.0)
	wind_vane.queue_redraw()


# ---------------------------------------------------------------- top-left: level, XP, cargo
func _update_player() -> void:
	if progression == null:
		return
	var zone := BiomeDB.get_zone(progression.current_zone)
	zone_label.text = String(zone.get("name", progression.current_zone)).to_upper()
	level_label.text = "LEVEL %d" % progression.level
	coins_label.text = "%d coins" % progression.money
	var need := progression.xp_needed()
	xp_bar.max_value = need
	xp_bar.value = progression.xp
	xp_label.text = "XP %d / %d" % [progression.xp, need]

	var cargo := progression.cargo
	var ratio := cargo.ratio()
	cargo_bar.max_value = cargo.hard_limit_ratio * 100.0
	cargo_bar.value = ratio * 100.0
	cargo_label.text = "CARGO %.1f / %.0f kg  (%d%%)" % [cargo.total_kg, cargo.capacity_kg, roundi(ratio * 100.0)]
	_set_fill(cargo_bar, GREEN if ratio < 0.8 else (YELLOW if ratio <= 1.0 else RED))
	cargo_note.text = "OVERLOADED: boat is slow and sluggish" if ratio > 1.0 else ""


# ---------------------------------------------------------------- top-right: weather and wind
func _update_weather() -> void:
	if weather == null:
		return
	state_label.text = weather.state_name().to_upper()
	state_label.add_theme_color_override(&"font_color", weather.state_color())
	wind_label.text = "WIND  %.1f kn" % weather.wind_knots
	heading_label.text = "FROM  %03.0f°  %s    Bft %d" % [weather.wind_from_deg, weather.wind_from_cardinal(), weather.beaufort()]
	sea_label.text = "WAVES  Hs %.1f m   amp %.1f m" % [weather.sea_hs_m, weather.wave_amplitude_m]
	baro_label.text = "%.0f hPa  %s" % [weather.pressure_hpa, weather.pressure_trend]
	if wave_physics and wave_physics.anchored:
		anchor_label.text = "ANCHOR DOWN   %.0f / %.0f N" % [wave_physics.anchor_tension_n, wave_physics.anchor_hold_n]
	else:
		anchor_label.text = "ANCHOR UP   (X to drop)"


## Wind vane: the arrow points where the wind is BLOWING TO. Longer arrow = stronger wind.
func _draw_wind_vane() -> void:
	var v := wind_vane
	var c := v.size * 0.5
	var r := minf(v.size.x, v.size.y) * 0.5 - 4.0
	var ring := Color(0.4, 0.78, 0.9, 0.9)
	v.draw_circle(c, r, Color(0.03, 0.1, 0.16, 0.9))
	v.draw_arc(c, r, 0.0, TAU, 48, ring, 2.0)
	for k in 8:
		var d := Vector2.UP.rotated(float(k) * TAU / 8.0)
		v.draw_line(c + d * (r - 5.0), c + d * r, ring, 1.0)
	var font := ThemeDB.fallback_font
	v.draw_string(font, c + Vector2(-4.0, -r + 16.0), "N", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.85, 0.95, 1.0))
	if weather == null:
		return
	var col := weather.state_color()
	var dir := weather.wind_dir
	var side := Vector2(-dir.y, dir.x)
	var arrow := r * (0.4 + 0.5 * weather.wind_strength01())
	var head := c + dir * arrow
	v.draw_line(c - dir * arrow, head, col, 3.0)
	v.draw_colored_polygon(PackedVector2Array([head + dir * 9.0, head - dir * 5.0 + side * 6.0, head - dir * 5.0 - side * 6.0]), col)
	v.draw_circle(c, 3.0, Color.WHITE)


# ---------------------------------------------------------------- bottom-centre: tension meter
func _update_tension() -> void:
	var blink := fmod(_time * 6.0, 2.0) < 1.0
	var hooked := fishing != null and fishing.state == FishingController.State.HOOKED
	var feeling := false
	if fish_ai:
		feeling = fish_ai.state == FishInteractionAI.State.NIBBLING or fish_ai.state == FishInteractionAI.State.BITING
	bite_label.visible = false
	stamina_row.visible = hooked

	if hooked:
		# Hooke spring: green = safe, yellow = warning, red = the line is about to snap
		var ratio := fishing.tension_n / maxf(fishing.line_break_force_n, 0.001)
		tension_bar.max_value = 125.0
		tension_bar.value = ratio * 100.0
		_set_fill(tension_bar, GREEN if ratio < safe_below else (YELLOW if ratio < warn_below else RED))
		tension_title.text = "LINE TENSION"
		_set_color(tension_title, WHITE)
		if ratio >= warn_below:
			tension_title.text = "SNAPPING RISK!  EASE OFF" if blink else "SNAPPING RISK!"
			_set_color(tension_title, RED)
		elif fishing.fatigue > 0.25:
			tension_title.text = "LINE FATIGUE  %d%%" % roundi(fishing.fatigue * 100.0)
			_set_color(tension_title, YELLOW)
		tension_value.text = "%.1f / %.1f N" % [fishing.tension_n, fishing.line_break_force_n]
		stamina_bar.value = fishing.stamina * 100.0
		info_label.text = "Drag %.0f N   |   Fish %.1f m   |   Line out %.0f / %.0f m   |   SPACE reel   UP / DOWN drag" % [
			fishing.drag_setting_n, fishing.fish_pos_m, fishing.line_out_m, fishing.spool_capacity_m]
	elif feeling:
		# before the hook is set the bar shows what the rod tip feels
		var feel := fish_ai.rod_tension_n
		tension_bar.max_value = 40.0
		tension_bar.value = feel
		_set_fill(tension_bar, CYAN)
		tension_title.text = "ROD FEEL"
		_set_color(tension_title, CYAN)
		tension_value.text = "%.1f N" % feel
		bite_label.visible = true
		if fish_ai.state == FishInteractionAI.State.BITING:
			bite_label.text = "BITE!  PRESS SPACE"
			_set_color(bite_label, RED if blink else YELLOW)
		else:
			bite_label.text = "nibbling... hold still"
			_set_color(bite_label, YELLOW)
		var t := fish_ai.telemetry
		info_label.text = "%s   |   Nibbles %s   |   Bite window %.1f s" % [t.get("species", ""), t.get("nibbles", "0/0"), float(t.get("bite_timer_s", 0.0))]
	else:
		tension_bar.max_value = 125.0
		tension_bar.value = 0.0
		_set_fill(tension_bar, GREEN)
		tension_title.text = "LINE TENSION"
		_set_color(tension_title, WHITE)
		tension_value.text = "--"
		if fish_ai and fish_ai.state != FishInteractionAI.State.IDLE and fish_ai.state != FishInteractionAI.State.HOOKED:
			info_label.text = "Bait out, waiting...   Bait depth %.0f m   |   SPACE retrieve   |   Q / E depth" % fish_ai.bait_depth_m
		else:
			info_label.text = idle_hint


# ---------------------------------------------------------------- helpers and events
func _set_fill(bar: ProgressBar, color: Color) -> void:
	var sb := bar.get_theme_stylebox(&"fill") as StyleBoxFlat
	if sb:
		sb.bg_color = color


func _set_color(label: Label, color: Color) -> void:
	label.add_theme_color_override(&"font_color", color)


func _on_caught(fish_id: String, kg: float) -> void:
	var grade := "normal"
	if progression:
		grade = progression.grade_for(fish_id, kg)
	var col := GREEN if grade == "normal" else (YELLOW if grade == "rare" else Color(1.0, 0.6, 0.2))
	var fish_name: String = BiomeDB.get_species(fish_id).get("name", fish_id)
	show_toast("Caught %s  %.1f kg  [%s]" % [fish_name, kg, ProgressionManager.GRADES[grade]["name"]], col)


func _on_snapped(_fish_id: String) -> void:
	show_toast("LINE SNAPPED! The fish got away.", RED)


func _on_escaped(_fish_id: String) -> void:
	show_toast("The fish shook the hook (line was slack).", YELLOW)


func _on_level_up(new_level: int) -> void:
	show_toast("LEVEL UP!  You are now level %d" % new_level, CYAN)


func _on_cargo_rejected(_item: Dictionary, reason: String) -> void:
	show_toast(reason, RED)


func _on_sold(summary: Dictionary) -> void:
	show_toast("Sold %d fish for %d coins" % [summary["count"], summary["total"]], YELLOW)


func _on_gear_upgraded(track: String, new_level: int) -> void:
	show_toast("Upgraded: %s" % String(progression.UPGRADES[track]["levels"][new_level]["name"]), CYAN)


func _on_bait_stolen(_fish_id: String) -> void:
	show_toast("Too slow! The fish stole the bait.", YELLOW)


func _on_spooked(_fish_id: String) -> void:
	show_toast("You reeled too early: the fish was spooked.", YELLOW)


func _on_weather_changed(new_state: int, old_state: int) -> void:
	var worse := new_state > old_state
	show_toast(("WEATHER WARNING: " if worse else "Weather easing: ") + String(WeatherManager.STATE_NAMES[new_state]), WeatherManager.STATE_COLORS[new_state])
