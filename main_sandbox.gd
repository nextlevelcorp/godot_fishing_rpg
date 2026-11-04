## Glue for the sandbox scene: connects every system to the others, draws the fishing line and bait,
## and adds a few test keys. All the real work stays in the scripts on the child nodes.
##
## Controls:  W/S throttle   A/D steer   X anchor   C cast   SPACE reel / retrieve / set the hook
##            UP/DOWN drag   Q/E bait depth   F3 debug text
## Test keys: F = hook a test seabream (see the tension bar at once)   1-4 force weather, 0 = automatic
##            T = weather x20 speed   ENTER = sell the hold   G = +1000 coins   U = buy the next upgrade
extends Node2D

@export var start_zone := "aegean_sea"
@export var bait_id := "live_sandworm"
@export var rig_id := "light_bottom_rig"

const TRACKS := ["engine", "hull", "reel", "rod", "sonar"]

@onready var field: OceanCurrentField = $OceanCurrentField
@onready var weather: WeatherManager = $WeatherManager
@onready var progression: ProgressionManager = $ProgressionManager
@onready var water: WaterSurface = $WaterSurface
@onready var anchovy: FishSchool = $Schools/AnchovySchool
@onready var bluefish: FishSchool = $Schools/BluefishSchool
@onready var seabream: FishSchool = $Schools/SeabreamSchool
@onready var boat: Boat = $Boat
@onready var wave_physics: BoatWavePhysics = $Boat/WavePhysics
@onready var camera: Camera2D = $Boat/Camera2D
@onready var fishing: FishingController = $FishingController
@onready var fish_ai: FishInteractionAI = $FishInteractionAI
@onready var sonar: SonarSystem = $SonarSystem
@onready var day_night: DayNightCycle = $DayNightCycle
@onready var hud: FishingHud = $HudLayer/FishingHud
@onready var overlay: DebugOverlay = $DebugOverlay

var _rng := RandomNumberGenerator.new()
var _upgrade_index := 0


func _ready() -> void:
	_rng.randomize()
	InputDefaults.ensure_all()
	var schools: Array[FishSchool] = [anchovy, bluefish, seabream]

	progression.current_zone = start_zone
	progression.bind_fishing(fishing)

	boat.current_field = field
	boat.progression = progression
	boat.wave_physics = wave_physics
	wave_physics.weather = weather
	wave_physics.boat = boat
	wave_physics.fishing = fishing
	wave_physics.visual = $Boat/Visual

	for school in schools:
		school.current_field = field
		school.weather = weather
		school.scare_source = boat
	bluefish.prey_school = anchovy              # bluefish hunt anchovy, anchovy flee bluefish
	anchovy.predator_school = bluefish

	fish_ai.schools.assign(schools)
	fish_ai.current_field = field
	fish_ai.boat = boat
	fish_ai.progression = progression
	fish_ai.weather = weather
	fish_ai.bind_fishing(fishing)

	sonar.boat = boat
	sonar.schools.assign(schools)
	sonar.progression = progression
	sonar.weather = weather

	water.boat = boat
	water.camera = camera
	water.weather = weather
	day_night.canvas_modulate = $CanvasModulate
	day_night.water = water
	day_night.weather = weather

	hud.setup(boat, progression, weather, fishing, fish_ai, sonar, wave_physics)
	overlay.boat = boat
	overlay.progression = progression
	overlay.fishing = fishing
	overlay.fish_ai = fish_ai
	overlay.sonar = sonar
	overlay.weather = weather
	overlay.wave_physics = wave_physics

	fishing.fish_caught.connect(_on_caught)
	fishing.line_snapped.connect(_on_fight_over)
	fishing.fish_escaped.connect(_on_fight_over)
	hud.show_toast("Welcome aboard. Press C to cast, F to test a fight.", Color(0.6, 0.9, 1.0))


func _process(_delta: float) -> void:
	queue_redraw()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"cast") and fish_ai.state == FishInteractionAI.State.IDLE and fishing.state != FishingController.State.HOOKED:
		fish_ai.cast_from_boat(bait_id, rig_id, 120.0, 8.0)
		return
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	match event.keycode:
		KEY_0:
			weather.forced_state = -1
		KEY_1, KEY_2, KEY_3, KEY_4:
			weather.forced_state = int(event.keycode - KEY_1)
			hud.show_toast("Weather forced: " + String(WeatherManager.STATE_NAMES[weather.forced_state]), WeatherManager.STATE_COLORS[weather.forced_state])
		KEY_T:
			weather.time_scale = 20.0 if weather.time_scale < 5.0 else 1.0
		KEY_F:
			_test_hook()
		KEY_ENTER, KEY_KP_ENTER:
			progression.sell_all(progression.current_zone)
		KEY_G:
			progression.money += 1000
			progression.money_changed.emit(progression.money)
		KEY_U:
			var res := progression.try_upgrade(TRACKS[_upgrade_index % TRACKS.size()])
			if res["ok"]:
				_upgrade_index += 1
			else:
				hud.show_toast(String(res["reason"]), Color(1.0, 0.85, 0.3))


## Skip the bite phase and start a fight straight away.
func _test_hook() -> void:
	if fishing.state == FishingController.State.HOOKED:
		return
	var id := "gilthead_seabream"
	fish_ai.retrieve()
	boat.thrust_enabled = false
	progression.prepare_fight(fishing, rig_id)
	fishing.hook_fish(id, BiomeDB.get_species(id), BiomeDB.roll_weight_kg(id, _rng), 16.0)


func _on_caught(_fish_id: String, _kg: float) -> void:
	_release_boat()


func _on_fight_over(_fish_id: String) -> void:
	_release_boat()


func _release_boat() -> void:
	if fish_ai.state == FishInteractionAI.State.IDLE:
		boat.thrust_enabled = true


## Fishing line from the boat to the bait, the bait itself and the anchor.
func _draw() -> void:
	if fish_ai == null or boat == null:
		return
	var active := fish_ai.state != FishInteractionAI.State.IDLE
	if active:
		var col := Color(1.0, 1.0, 1.0, 0.9)
		match fish_ai.state:
			FishInteractionAI.State.NIBBLING:
				col = Color(1.0, 0.9, 0.3)
			FishInteractionAI.State.BITING:
				col = Color(1.0, 0.3, 0.3)
			FishInteractionAI.State.HOOKED:
				col = Color(0.4, 1.0, 0.5)
		draw_line(boat.global_position, fish_ai.bait_pos, Color(1.0, 1.0, 1.0, 0.4), 1.0)
		draw_circle(fish_ai.bait_pos, 5.0, col)
		draw_arc(fish_ai.bait_pos, fish_ai.attract_radius_px, 0.0, TAU, 48, Color(1.0, 1.0, 1.0, 0.12), 1.0)
	if wave_physics and wave_physics.anchored:
		draw_line(boat.global_position, wave_physics.anchor_pos, Color(0.9, 0.8, 0.5, 0.7), 2.0)
		draw_circle(wave_physics.anchor_pos, 6.0, Color(0.9, 0.8, 0.5))
