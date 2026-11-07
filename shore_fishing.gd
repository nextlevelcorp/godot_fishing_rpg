## Shore fishing at a real spot picked on the Turkey map (see fishing_spots.gd).
##
## Flow:  walk the shore and the pier with the stick -> at the water's edge hold CAST to charge,
##        aim with the stick, release to throw -> WAIT for a fish -> NIBBLES -> BITE (short window:
##        press REEL) -> FIGHT (side view) -> result.
##
## Realism: the bottom drops away from the shore at the spot's slope (steep rocks, shallow sand);
## the float holds the bait at a set depth (DEEP / SHAL), and a species only bites near its own
## depth range and at its own feeding time (BiomeDB.activity_factor). Fish are not drawn from
## above: you read the water (rings, shoals breaking the surface) and the float.
##
## Everything that moves follows Nature of Code rules (noc.gd):
##   the cast is a projectile under gravity, air drag and wind; the float is a damped spring;
##   fish are steering agents (arrive, wander, flee); small fish shoal with boids; splashes are
##   particles; the line is a Verlet rope pushed by the current. The fight itself is
##   FishingController (spring-mass line, clutch, fatigue). The town behind is ShoreWorld.
##
## Controls: stick (steer_left/right, boat_forward/back)  walk, and aim while charging
##           bait_deeper / bait_shallower  float depth     cast  hold = power, release = throw, tap while waiting = reel in
##           reel_in  set the hook on a bite, then hold to reel     drag_up / drag_down  clutch (fight)
class_name ShoreFishing
extends Node2D

## Night, on the pier: the lamp draws baitfish, so fish activity rises by this fraction (game-design fill).
const LAMP_PIER_BONUS := 0.15

const ANGLER_LOOK := {"shirt": Color(0.18, 0.36, 0.30), "pants": Color(0.22, 0.24, 0.30), "skin": Color(0.92, 0.74, 0.58),
	"hair": Color(0.20, 0.14, 0.10), "hat": Color(0.85, 0.30, 0.20)}

enum State { AIM, CHARGE, FLY, WAIT, BITE, FIGHT, RESULT }

const PX_PER_M := 10.0
const ROD_LEN := 90.0
const ROD_BEND_PX := 20.0
const ROD_TIP_HEIGHT := 70.0      ## px above the water the bait starts its flight from
const HALF_WIDTH := 4000.0
const MAP_SCENE := "res://turkey_map.tscn"
const GRAVITY_Z := 520.0          ## px/s^2 pulling the flying bait down
const AIR_DRAG := 0.35            ## 1/s horizontal drag on the flying bait
const WATER_EDGE := -12.0         ## bait landing below this y hits water, above it hits the shore
const SHOAL_BOUNDS := Rect2(-3700.0, -900.0, 7400.0, 840.0)
const ROPE_POINTS := 16
const RETRIEVE_SPEED := 55.0         ## px/s the bait travels while REEL is held (about 5.5 m/s)
const WALK_SPEED := 150.0          ## px/s, about 1.5 m/s
const PIER_LEN := 420.0            ## the pier reaches 42 m out
const PIER_HALF := 26.0
const LOCAL_EARSHOT := 450.0       ## the local calls out about fish you land this close
const CEPHALOPODS: Array[String] = ["european_squid", "common_cuttlefish", "common_octopus"]   ## come to the lamp on dark nights (Moon)
const TALK_RADIUS := 130.0         ## walk this close to the named local to see TALK
const TIP_RADIUS := 100.0          ## walk this close to another angler to hear their tip

var _rng := RandomNumberGenerator.new()
var _spot: Dictionary = {}
var _state := State.AIM

# the player
var _hand := Vector2(0.0, 46.0)    ## where the angler stands (hand height in the top-down view)
var _facing := Vector2.UP
var _moving := false
var _walk_phase := 0.0
var _walk_rects: Array[Rect2] = []
var _has_pier := true
var _pier_x := 900.0
var _bait_depth := 2.0             ## float setting, metres below the surface
var _tip_text := ""
var _toast_text := ""
var _toast_t := 0.0
var _toast_label: Label
var _quiet_t := 0.0
var _level_label: Label
var _xp_bar: ProgressBar
var _goal_labels: Array[Label] = []
var _summary: PanelContainer
var _hud_root: Control
var _local_idx := -1                 ## index in _crowd of the spot's named local angler (locals.gd), -1 none
var _talk_btn: Button
var _talk_panel: PanelContainer
## Weekly tournament while it runs: {t: seconds left, me: kg, rivals: [{idx, name, best}], over: bool}.
var _tourney: Dictionary = {}
var _tourney_btn: Button
var _tourney_label: Label
var _weather: WeatherFx
var _pov_on := false
## Boat outing: the angler sits in a rowing boat out on the water instead of walking the shore.
var _boat_mode := false
var _boat_vel := Vector2.ZERO
var _anchored := false
const ROW_FORCE := 120.0          ## px/s^2 from the oars
const BOAT_DRAG := 0.9            ## 1/s water drag on the hull
const BOAT_START_Y := -650.0      ## about 65 m out
var _bait_on := true               ## false once small fish have stripped the hook
var _empty_t := 0.0
var _escape_reason := ""
var _overhook_t := 0.0
var _was_shaking := false
var _test_fish := false           ## a fish hooked from the TEST panel: no rewards
var _forced_kg := 0.0
var _test_panel: PanelContainer
var _test_bar: HBoxContainer
var _test_size := 0.4
var _anchor_seen := 0
var _step_half := 0
var _stroke_n := 0
var _lap_t := 3.0
var _horn_t := 40.0
var _tackle_panel: PanelContainer
var _build_label: Label
var _fps_t := 0.0
var _lamp_noise := FastNoiseLite.new()
var _weather_kind := "clear"
var _tip_pos := Vector2.ZERO
var _time := 0.0

# input edges, robust to quick taps (see TouchControls.presses)
var _cast_was := false
var _reel_was := false
var _cast_seen := 0
var _reel_seen := 0
var _cast_edge := false
var _reel_edge := false

# environment forces
var _wind := Vector2.ZERO          ## air, px/s^2 on the flying bait
var _current := Vector2.ZERO       ## water, px/s drift for the float and the slack line

# cast and float
var _aim := 0.0
var _power := 0.0
var _power_dir := 1.0
var _cast_dist_m := 0.0
var _bobber_pos := Vector2.ZERO
var _b_vel := Vector2.ZERO
var _b_z := 0.0
var _b_vz := 0.0
var _float_x := 0.0                ## 0 = floating, 1 = pulled under
var _float_v := 0.0
var _float_pull := 0.0
var _pred_path := PackedVector2Array()
var _pred_landing := Vector2.ZERO

# the fish
var _wait_t := 0.0
var _fish_id := ""
var _prof: Dictionary = {}
var _nib_left := 0
var _event_t := 0.0
var _fish_time := 0.0
var _bite_t := 0.0
var _weight_kg := 0.0
var _result_t := 0.0
var _fish_agent: Noc.Vehicle
var _fish_mode := ""               ## approach, nibble, bite, leave
var _fight_agent: Noc.Vehicle

# fight feedback
var _tension_ratio := 0.0
var _rod_bend := 0.0
var _rod_bend_target := 0.0
var _shake := 0.0
var _kick := 0.0
var _fight_hint := ""

# life and effects
var _rope: Noc.Rope
var _shoals: Array = []
var _particles: Array = []
var _ripples: Array[Dictionary] = []
var _ripple_clock := 0.0
var _spray_clock := 0.0
var _splash_pos := Vector2.ZERO
var _splash_age := 99.0

# shore art
var _rocks: Array[Dictionary] = []
var _edge_pts := PackedVector2Array()
var _crowd: Array[Dictionary] = []
var _pebbles: Array[Vector3] = []
var _sparkles: Array[Vector3] = []

# boats on a sea lane (path following) and the other anglers on the shore
var _boats: Array = []
var _boat_lane := PackedVector2Array()
var _neighbor_clock := 8.0
var _reel_click := 0.0

# nodes
var _amb: Ambience
var _fight_view: PovView
var _water: WaterSurface
var _cam: Camera2D
var _tint: CanvasModulate
var _world: ShoreWorld
var _fishing: FishingController
var _status: Label
var _spot_label: Label
var _clock_label: Label
var _coins_label: Label
var _result_label: Label
var _tension_label: Label
var _power_bar: ProgressBar
var _tension_bar: ProgressBar
var _stamina_bar: ProgressBar
var _tension_fill: StyleBoxFlat
var _depth_label: Label


func _ready() -> void:
	_rng.randomize()
	_lamp_noise.noise_type = FastNoiseLite.TYPE_PERLIN
	InputDefaults.ensure_all()
	GameSession.load_once()
	if FishingSpots.get_spot(GameSession.spot_id).is_empty():
		GameSession.spot_id = "galata_bridge"       # opened directly, not from the map
	_spot = FishingSpots.get_spot(GameSession.spot_id)
	GameSession.start_outing(_make_goals())
	_boat_mode = GameSession.mode == "boat"
	if _boat_mode:
		_hand = Vector2(0.0, BOAT_START_Y)
	_has_pier = _spot["kind"] != "bridge"
	_pier_x = 900.0 if hash(GameSession.spot_id) % 2 == 0 else -900.0
	_build_walkable()
	_weather_kind = WeatherFx.roll(_rng)
	_wind = Vector2(_rng.randf_range(-60.0, 60.0), _rng.randf_range(-15.0, 15.0)) * float(WeatherFx.KINDS[_weather_kind]["wind"])
	# The spot's surface current, along the shore (fishing_spots.gd current_ms), varying a little.
	var cur_ms := float(_spot.get("current_ms", 0.15)) * _rng.randf_range(0.8, 1.2)
	_current = Vector2((1.0 if _rng.randf() < 0.5 else -1.0) * cur_ms * PX_PER_M, _rng.randf_range(-0.1, 0.1) * cur_ms * PX_PER_M)
	_cast_seen = int(TouchControls.presses.get(&"cast", 0))
	_reel_seen = int(TouchControls.presses.get(&"reel_in", 0))
	_anchor_seen = int(TouchControls.presses.get(&"anchor", 0))

	_cam = Camera2D.new()
	_cam.position = Vector2(0.0, 40.0)
	_cam.zoom = Vector2.ONE * 1.1
	add_child(_cam)
	_cam.make_current()

	_tint = CanvasModulate.new()
	add_child(_tint)

	_water = WaterSurface.new()
	_water.camera = _cam
	add_child(_water)
	_apply_water_palette()

	_world = ShoreWorld.new()
	_world.setup(_spot, hash(GameSession.spot_id))
	_world.time_of_day = GameSession.start_time()       # picked on the map
	_world.z_index = 1
	add_child(_world)

	_fishing = FishingController.new()
	_fishing.name = "FishingController"
	add_child(_fishing)
	_fishing.apply_rig(BiomeDB.get_rig(GameSession.rig_id))
	_fishing.reel_speed_m_s = 3.2             # shore spinning reel: faster retrieve than the boat rig
	_fishing.fish_caught.connect(_on_caught)
	_fishing.fish_surfaced.connect(func(kind: String) -> void: _fight_view.surface(kind))
	_fishing.fish_surged.connect(func() -> void:
		_flash("Not tired yet! It saw you and ran. Tire it out before you land it")
		_amb.play("drag", 0.8)
		_buzz(80))
	_fishing.line_snapped.connect(_on_snapped)
	_fishing.fish_escaped.connect(_on_escaped)
	_fishing.tension_updated.connect(_on_tension)

	_rope = Noc.Rope.new(ROPE_POINTS, _hand, _hand)
	_build_land()
	_spawn_shoals()
	_spawn_boats()
	_amb = Ambience.new()
	_amb.surf_level = 0.75 if _spot["kind"] == "rocky" else 0.55
	add_child(_amb)
	_fight_view = PovView.new()
	_fight_view.fishing = _fishing
	_fight_view.spot = _spot
	_fight_view.kind = String(_spot["kind"])
	_fight_view.sfx.connect(func(k: String, v: float) -> void: _amb.play(k, v))
	add_child(_fight_view)
	_build_vignette()
	_build_hud()
	var touch := TouchControls.new()
	touch.enabled_actions.assign([&"cast", &"reel_in", &"drag_up", &"drag_down", &"bait_deeper", &"bait_shallower"])
	if _boat_mode:
		touch.enabled_actions.append(&"anchor")
	touch.joystick = true
	add_child(touch)
	add_child(DeviceGuard.new())
	_set_status("Walk with the stick. At the water's edge, hold CAST to throw")


# ---------------------------------------------------------------- setup
func _apply_water_palette() -> void:
	var mat := _water.material as ShaderMaterial
	if mat == null:
		return
	var w: Dictionary = _spot["water"]
	mat.set_shader_parameter("shallow_color", w["shallow"])
	mat.set_shader_parameter("mid_color", w["mid"])
	mat.set_shader_parameter("deep_color", w["deep"])


func _build_land() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(GameSession.spot_id)
	var base: Color = _spot["shore_color"]
	var kind: String = _spot["kind"]
	if kind == "rocky":
		var x := -HALF_WIDTH
		while x < HALF_WIDTH:
			var r := rng.randf_range(38.0, 80.0)
			var c := Vector2(x, rng.randf_range(-6.0, 34.0))
			var pts := PackedVector2Array()
			for i in 9:
				var a := TAU * float(i) / 9.0
				pts.append(c + Vector2(cos(a) * r * rng.randf_range(0.75, 1.1), sin(a) * r * rng.randf_range(0.6, 0.95)))
			var shade := rng.randf_range(0.85, 1.15)
			_rocks.append({"pts": pts, "color": Color(base.r * shade, base.g * shade, base.b * shade), "c": c, "r": r})
			x += rng.randf_range(46.0, 80.0)
	elif kind == "beach":
		var x2 := -HALF_WIDTH
		while x2 <= HALF_WIDTH:
			_edge_pts.append(Vector2(x2, sin(x2 * 0.012 + 1.3) * 9.0 + sin(x2 * 0.031) * 4.0))
			x2 += 40.0
		for i in 140:
			_pebbles.append(Vector3(rng.randf_range(-1400.0, 1400.0), rng.randf_range(30.0, 230.0), rng.randf_range(1.5, 4.0)))
	# Other anglers along the shore. The Galata survey counted about 200 a day on the bridge, so
	# the rail is lined with them; elsewhere a few locals fish the same water.
	var crowd_y: float = {"bridge": 20.0, "harbor": 20.0, "beach": 34.0}.get(kind, 12.0)
	var gap := Vector2(60.0, 130.0) if kind == "bridge" else Vector2(150.0, 320.0)
	var cx := -HALF_WIDTH + 200.0
	while cx < HALF_WIDTH - 200.0:
		if absf(cx) > 140.0 and absf(cx - _pier_x) > 70.0:
			_crowd.append({"x": cx, "y": crowd_y, "len": rng.randf_range(90.0, 260.0), "phase": rng.randf() * TAU,
				"state": "wait", "t": rng.randf_range(4.0, 40.0), "shirt": Color(rng.randf_range(0.2, 0.7), rng.randf_range(0.2, 0.5), rng.randf_range(0.25, 0.6)),
				"hat": rng.randf() < 0.5, "kg": 0.3, "sp": ""})
		cx += rng.randf_range(gap.x, gap.y)
	_pick_local()
	for i in 140:
		_sparkles.append(Vector3(rng.randf_range(-HALF_WIDTH, HALF_WIDTH), rng.randf_range(-1100.0, -40.0), rng.randf() * TAU))


## The angler nearest the start becomes the spot's named local (locals.gd): drawn in their own
## clothes with a name tag, and the TALK button shows when you walk up to them.
func _pick_local() -> void:
	var p := Locals.person(GameSession.spot_id)
	if p.is_empty() or _crowd.is_empty():
		return
	var best := INF
	for i in _crowd.size():
		var d := absf(float(_crowd[i]["x"]) - 260.0)
		if d < best:
			best = d
			_local_idx = i
	_crowd[_local_idx]["shirt"] = p["shirt"]
	_crowd[_local_idx]["hat"] = p["hat"]


## The local's call when you land a fish within earshot (LOCAL_EARSHOT px), for the catch card.
func _local_says(species: String, kg: float, released: bool) -> String:
	if _local_idx < 0 or _boat_mode or _crowd_pos(_crowd[_local_idx]).distance_to(_hand) > LOCAL_EARSHOT:
		return ""
	return "%s: \"%s\"" % [String(Locals.person(GameSession.spot_id)["name"]), Locals.react(species, kg, released)]


func _near_local() -> bool:
	if _local_idx < 0 or _boat_mode:
		return false
	return _crowd_pos(_crowd[_local_idx]).distance_to(_hand) < TALK_RADIUS


func _update_talk_button() -> void:
	if _talk_btn == null:
		return
	var near := _state == State.AIM and _near_local()
	_talk_btn.visible = near
	if near:
		var p := Locals.person(GameSession.spot_id)
		_talk_btn.text = ("TALK  %s%s" % [String(p["name"]), "  !" if Locals.can_turn_in(GameSession.spot_id) else ""])


func _open_talk_panel() -> void:
	if _talk_panel != null and is_instance_valid(_talk_panel):
		_talk_panel.queue_free()
	var sid := GameSession.spot_id
	var p := Locals.person(sid)
	if p.is_empty():
		return
	var panel := PanelContainer.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	panel.offset_left = -440.0
	panel.offset_right = 440.0
	panel.offset_top = -230.0
	panel.offset_bottom = 230.0
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.02, 0.10, 0.18, 0.95)
	style.set_corner_radius_all(18)
	style.set_content_margin_all(20)
	panel.add_theme_stylebox_override("panel", style)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	panel.add_child(box)
	_plain_label(box, 28, Color(1.0, 0.92, 0.6)).text = String(p["name"])
	_plain_label(box, 16, Color(0.75, 0.85, 0.95)).text = "%s  -  %s  (%d)" % [String(p["role"]), Locals.tier_name(sid), Locals.friendship(sid)]
	for line in Locals.talk_lines(sid):
		_plain_label(box, 19, Color.WHITE).text = line
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	box.add_child(row)
	if Locals.can_turn_in(sid):
		var give := _tackle_button("GIVE  (+%d coins)" % Locals.reward_coins(sid), false, Vector2(300.0, 60.0))
		give.pressed.connect(func() -> void:
			var res := Locals.turn_in(sid)
			_update_coins()
			_update_progress_ui()
			_amb.play("bell", 0.4)
			_buzz(120)
			if bool(res.get("tier_up", false)):
				_flash("%s now calls you: %s" % [String(p["name"]), String(res["tier"])])
			else:
				_flash("+%d coins, +%d XP" % [int(res.get("coins", 0)), int(res.get("xp", 0))])
			_open_talk_panel())
		row.add_child(give)
	var bye := _tackle_button("BYE", false, Vector2(160.0, 60.0))
	bye.pressed.connect(func() -> void: panel.queue_free())
	row.add_child(bye)
	_talk_panel = panel
	_hud_root.add_child(panel)


# ---------------------------------------------------------------- weekly tournament
func _open_tourney_panel() -> void:
	if _talk_panel != null and is_instance_valid(_talk_panel):
		_talk_panel.queue_free()
	var panel := _tourney_card("Weekly shore tournament")
	var box: VBoxContainer = panel.get_child(0)
	if not _tourney.is_empty() and not bool(_tourney.get("over", false)):
		_plain_label(box, 19, Color.WHITE).text = "Running.  %s" % _tourney_text()
	else:
		_plain_label(box, 19, Color.WHITE).text = "Five minutes. The heaviest single fish wins, and it must be of legal size. You fish against the three anglers nearest you."
		_plain_label(box, 18, Color(0.8, 0.9, 1.0)).text = "Entry %d coins.  Prizes %d / %d / %d coins.%s" % [Tournament.ENTRY, Tournament.PRIZES[0], Tournament.PRIZES[1], Tournament.PRIZES[2],
			"" if Tournament.prize_open() else "  This week's prize is already yours: this one is for fun."]
		if _state != State.AIM:
			_plain_label(box, 18, Color(1.0, 0.6, 0.5)).text = "Reel in first."
		else:
			var enter := _tackle_button("ENTER  (-%d coins)" % Tournament.ENTRY, false, Vector2(300.0, 60.0))
			enter.disabled = GameSession.coins < Tournament.ENTRY
			enter.pressed.connect(func() -> void:
				panel.queue_free()
				_start_tourney())
			box.add_child(enter)
	var close := _tackle_button("CLOSE", false, Vector2(160.0, 60.0))
	close.pressed.connect(func() -> void: panel.queue_free())
	box.add_child(close)
	_talk_panel = panel
	_hud_root.add_child(panel)


func _tourney_card(title: String) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	panel.offset_left = -440.0
	panel.offset_right = 440.0
	panel.offset_top = -240.0
	panel.offset_bottom = 240.0
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.02, 0.10, 0.18, 0.95)
	style.set_corner_radius_all(18)
	style.set_content_margin_all(20)
	panel.add_theme_stylebox_override("panel", style)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	panel.add_child(box)
	_plain_label(box, 28, Color(1.0, 0.92, 0.6)).text = title
	return panel


## Pays the entry and picks the three anglers nearest you (the local counts) as rivals.
func _start_tourney() -> void:
	if GameSession.coins < Tournament.ENTRY:
		return
	GameSession.coins -= Tournament.ENTRY
	GameSession.save()
	_update_coins()
	var order: Array[int] = []
	for i in _crowd.size():
		order.append(i)
	order.sort_custom(func(a: int, b: int) -> bool:
		return absf(float(_crowd[a]["x"]) - _hand.x) < absf(float(_crowd[b]["x"]) - _hand.x))
	var rivals: Array[Dictionary] = []
	var names := Tournament.NAMES.duplicate()
	for k in mini(Tournament.RIVALS, order.size()):
		var idx := order[k]
		var nm := String(Locals.person(GameSession.spot_id)["name"]) if idx == _local_idx else String(names.pop_at(_rng.randi() % names.size()))
		rivals.append({"idx": idx, "name": nm, "best": 0.0})
	_tourney = {"t": Tournament.DURATION_S, "me": 0.0, "rivals": rivals, "over": false}
	_tourney_label.visible = true
	_amb.play("horn", 0.7)
	_flash("Tournament on! Five minutes, heaviest legal fish wins")


func _tourney_running() -> bool:
	return not _tourney.is_empty() and not bool(_tourney.get("over", false))


func _tourney_rival_landed(a: Dictionary) -> void:
	if not _tourney_running():
		return
	var sp := String(a["sp"])
	if sp == "":
		return
	var legal := Regulations.min_cm(sp)
	if legal > 0.0 and Regulations.length_cm(sp, float(a["kg"])) < legal:
		return                                    # they put it back, like you would
	for r: Dictionary in _tourney["rivals"]:
		if int(r["idx"]) == _crowd.find(a):
			r["best"] = maxf(float(r["best"]), float(a["kg"]))


## A kept fish of yours. Returns a line for the catch card, or "" when no tournament runs.
func _tourney_player_landed(kg: float) -> String:
	if not _tourney_running():
		return ""
	if kg > float(_tourney["me"]):
		_tourney["me"] = kg
		return "TOURNAMENT: new best %.2f kg  (%s)" % [kg, Tournament.ordinal(_tourney_place())]
	return "TOURNAMENT: your best is still %.2f kg" % float(_tourney["me"])


## Your place now, 0 = first. Ties go to whoever got there first: the rival.
func _tourney_place() -> int:
	var place := 0
	for r: Dictionary in _tourney["rivals"]:
		if float(r["best"]) >= float(_tourney["me"]) and float(r["best"]) > 0.0:
			place += 1
	return place


func _tourney_text() -> String:
	var t := maxf(float(_tourney["t"]), 0.0)
	var lead_name := "you"
	var lead := float(_tourney["me"])
	for r: Dictionary in _tourney["rivals"]:
		if float(r["best"]) > lead:
			lead = float(r["best"])
			lead_name = String(r["name"])
	return "%d:%02d   You %.2f kg (%s)   Leader: %s %.2f kg" % [int(t) / 60, int(t) % 60, float(_tourney["me"]), Tournament.ordinal(_tourney_place()), lead_name, lead]


## Counts down; at the horn a fish already on the line still counts, so it waits for the fight.
func _tick_tourney(delta: float) -> void:
	if not _tourney_running():
		return
	_tourney["t"] = float(_tourney["t"]) - delta
	_tourney_label.text = "TOURNAMENT  " + _tourney_text()
	if float(_tourney["t"]) > 0.0 or _state == State.FIGHT or _state == State.BITE:
		return
	_tourney["over"] = true
	_tourney_label.visible = false
	_amb.play("horn", 0.8)
	var place := _tourney_place()
	if float(_tourney["me"]) <= 0.0:
		place = Tournament.RIVALS
	var prize := Tournament.pay(place)
	if place == 0 and not prize.is_empty():
		_buzz(250)
	_update_coins()
	_update_progress_ui()
	if _talk_panel != null and is_instance_valid(_talk_panel):
		_talk_panel.queue_free()
	var panel := _tourney_card("Tournament over:  you are %s" % Tournament.ordinal(place))
	var box: VBoxContainer = panel.get_child(0)
	var rows: Array[Array] = [["You", float(_tourney["me"])]]
	for r: Dictionary in _tourney["rivals"]:
		rows.append([String(r["name"]), float(r["best"])])
	rows.sort_custom(func(x: Array, y: Array) -> bool: return float(x[1]) > float(y[1]))
	for i in rows.size():
		_plain_label(box, 20, Color(1.0, 0.92, 0.6) if String(rows[i][0]) == "You" else Color.WHITE).text = \
			"%s   %s   %.2f kg" % [Tournament.ordinal(i), String(rows[i][0]), float(rows[i][1])]
	if not prize.is_empty():
		_plain_label(box, 20, Color(0.6, 1.0, 0.6)).text = "Prize: +%d coins, +%d XP" % [int(prize["coins"]), int(prize["xp"])]
	elif place < Tournament.PRIZES.size():
		_plain_label(box, 18, Color(0.8, 0.9, 1.0)).text = "This week's prize was already paid. Come back next week."
	var ok := _tackle_button("OK", false, Vector2(160.0, 60.0))
	ok.pressed.connect(func() -> void: panel.queue_free())
	box.add_child(ok)
	_talk_panel = panel
	_hud_root.add_child(panel)


## Two shoals of small fish that school (boids) in the shallows.
func _spawn_shoals() -> void:
	for g in 6:
		var center := Vector2(_rng.randf_range(-3400.0, 3400.0), _rng.randf_range(-700.0, -150.0))
		var group: Array = []
		for i in 10:
			var v := Noc.Vehicle.new(center + Vector2(_rng.randf_range(-40.0, 40.0), _rng.randf_range(-40.0, 40.0)), 70.0, 90.0)
			v.data = {"len": _rng.randf_range(9.0, 14.0)}
			group.append(v)
		_shoals.append(group)


## Fishing boats (and a ferry on the Istanbul spot) sailing a loop out at sea.
func _spawn_boats() -> void:
	_boat_lane = PackedVector2Array([Vector2(-4600.0, -780.0), Vector2(4600.0, -840.0), Vector2(4600.0, -1080.0), Vector2(-4600.0, -1020.0)])
	var count := 3
	for i in count:
		var ferry: bool = _spot["region"].contains("Istanbul") and i == 0
		var speed := 55.0 if ferry else _rng.randf_range(35.0, 60.0)
		var b := Noc.Vehicle.new(_boat_lane[i % 4] + Vector2(float(i) * 500.0, 0.0), speed, 25.0)
		b.data = {"ferry": ferry, "trail": 0.0, "color": [Color(0.85, 0.3, 0.25), Color(0.2, 0.5, 0.75), Color(0.95, 0.75, 0.25)][i % 3]}
		_boats.append(b)


## Soft dark corners: keeps the eye on the middle of the screen.
func _build_vignette() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 4
	add_child(layer)
	var grad := Gradient.new()
	grad.set_color(0, Color(0.0, 0.0, 0.0, 0.0))
	grad.set_color(1, Color(0.0, 0.02, 0.06, 0.5))
	grad.add_point(0.62, Color(0.0, 0.0, 0.0, 0.0))
	var tex := GradientTexture2D.new()
	tex.gradient = grad
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.0, 1.0)
	tex.width = 256
	tex.height = 256
	var rect := TextureRect.new()
	rect.texture = tex
	rect.stretch_mode = TextureRect.STRETCH_SCALE
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(rect)


func _build_hud() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 5
	add_child(layer)
	var ui := Control.new()
	ui.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(ui)
	_hud_root = ui
	_weather = WeatherFx.new()
	_weather.setup(_weather_kind)
	ui.add_child(_weather)

	_spot_label = _make_label(ui, 22, Color.WHITE)
	_spot_label.position = Vector2(20.0, 10.0)
	_spot_label.text = "%s  -  %s   |   %s" % [_spot["name"], _spot["region"], BiomeDB.get_rig(GameSession.rig_id).get("name", "")]
	_clock_label = _make_label(ui, 18, Color(0.85, 0.92, 1.0))
	_clock_label.position = Vector2(20.0, 40.0)
	_depth_label = _make_label(ui, 18, Color(0.75, 0.95, 1.0))
	_depth_label.position = Vector2(20.0, 64.0)
	var build := _make_label(ui, 14, Color(1.0, 1.0, 1.0, 0.6))
	build.position = Vector2(20.0, 694.0)
	build.text = GameSession.BUILD
	_build_label = build

	_status = _make_label(ui, 30, Color.WHITE)
	_status.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	_status.offset_top = 66.0
	_status.offset_bottom = 110.0
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

	_result_label = _make_label(ui, 42, Color(1.0, 0.95, 0.6))
	_result_label.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	_result_label.offset_top = 200.0
	_result_label.offset_bottom = 310.0
	_result_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_result_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

	_toast_label = _make_label(ui, 34, Color(0.8, 1.0, 1.0))
	_toast_label.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	_toast_label.offset_top = 330.0
	_toast_label.offset_bottom = 380.0
	_toast_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

	_coins_label = _make_label(ui, 22, Color(1.0, 0.9, 0.5))
	_coins_label.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	_coins_label.offset_left = -300.0
	_coins_label.offset_right = -20.0
	_coins_label.offset_top = 76.0
	_coins_label.offset_bottom = 110.0
	_coins_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_update_coins()

	var map_btn := Button.new()
	map_btn.text = "MAP"
	map_btn.add_theme_font_size_override("font_size", 24)
	map_btn.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	map_btn.offset_left = -150.0
	map_btn.offset_right = -20.0
	map_btn.offset_top = 10.0
	map_btn.offset_bottom = 66.0
	map_btn.pressed.connect(_on_map_pressed)
	ui.add_child(map_btn)

	# Squid, octopus and cuttlefish feed at night; this skips the clock forward an hour.
	var hour_btn := Button.new()
	hour_btn.text = "+1 hour"
	hour_btn.add_theme_font_size_override("font_size", 20)
	hour_btn.position = Vector2(20.0, 96.0)
	hour_btn.size = Vector2(130.0, 48.0)
	hour_btn.focus_mode = Control.FOCUS_NONE
	hour_btn.pressed.connect(func() -> void:
		_world.time_of_day = fmod(_world.time_of_day + 1.0 / 24.0, 1.0)
		_flash("Time %s" % _world.clock_text()))
	ui.add_child(hour_btn)

	_talk_btn = Button.new()
	_talk_btn.add_theme_font_size_override("font_size", 22)
	_talk_btn.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	_talk_btn.offset_left = -360.0
	_talk_btn.offset_right = -20.0
	_talk_btn.offset_top = 118.0
	_talk_btn.offset_bottom = 174.0
	_talk_btn.focus_mode = Control.FOCUS_NONE
	_talk_btn.visible = false
	_talk_btn.pressed.connect(_open_talk_panel)
	ui.add_child(_talk_btn)

	_tourney_btn = Button.new()
	_tourney_btn.text = "TOURNAMENT"
	_tourney_btn.add_theme_font_size_override("font_size", 22)
	_tourney_btn.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	_tourney_btn.offset_left = -360.0
	_tourney_btn.offset_right = -20.0
	_tourney_btn.offset_top = 180.0
	_tourney_btn.offset_bottom = 236.0
	_tourney_btn.focus_mode = Control.FOCUS_NONE
	_tourney_btn.visible = not _boat_mode and Tournament.spot_this_week() == GameSession.spot_id
	_tourney_btn.pressed.connect(_open_tourney_panel)
	ui.add_child(_tourney_btn)
	_tourney_label = _plain_label(ui, 20, Color(1.0, 0.9, 0.5))
	_tourney_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	_tourney_label.position = Vector2(20.0, 286.0)
	_tourney_label.add_theme_constant_override("outline_size", 6)
	_tourney_label.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 0.8))
	_tourney_label.visible = false

	var bait_btn := Button.new()
	bait_btn.text = "BAIT / HOOK"
	bait_btn.add_theme_font_size_override("font_size", 20)
	bait_btn.position = Vector2(160.0, 96.0)
	bait_btn.size = Vector2(170.0, 48.0)
	bait_btn.focus_mode = Control.FOCUS_NONE
	bait_btn.pressed.connect(_open_tackle_panel)
	ui.add_child(bait_btn)

	if GameSession.test_tools:
		var test_btn := Button.new()
		test_btn.text = "TEST"
		test_btn.add_theme_font_size_override("font_size", 20)
		test_btn.position = Vector2(340.0, 96.0)
		test_btn.size = Vector2(110.0, 48.0)
		test_btn.focus_mode = Control.FOCUS_NONE
		test_btn.pressed.connect(_open_test_panel)
		ui.add_child(test_btn)
		_test_bar = HBoxContainer.new()
		_test_bar.position = Vector2(470.0, 96.0)
		_test_bar.add_theme_constant_override("separation", 8)
		for entry: Array in [["JUMP", "jump"], ["THRASH", "thrash"], ["ROLL", "roll"], ["LAND", "land"]]:
			var b := Button.new()
			b.text = String(entry[0])
			b.custom_minimum_size = Vector2(110.0, 48.0)
			b.add_theme_font_size_override("font_size", 18)
			b.focus_mode = Control.FOCUS_NONE
			var what := String(entry[1])
			b.pressed.connect(func() -> void: _test_action(what))
			_test_bar.add_child(b)
		_test_bar.visible = false
		ui.add_child(_test_bar)

	var star := TextureRect.new()
	star.texture = load("res://assets/kenney_game_icons/star.png") as Texture2D
	star.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	star.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	star.position = Vector2(20.0, 152.0)
	star.size = Vector2(22.0, 22.0)
	star.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(star)
	_level_label = _make_label(ui, 18, Color(1.0, 0.93, 0.6))
	_level_label.position = Vector2(48.0, 148.0)
	_xp_bar = ProgressBar.new()
	_xp_bar.min_value = 0.0
	_xp_bar.max_value = 1.0
	_xp_bar.step = 0.001
	_xp_bar.show_percentage = false
	_xp_bar.position = Vector2(20.0, 178.0)
	_xp_bar.size = Vector2(250.0, 10.0)
	_xp_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(_xp_bar)
	var target := TextureRect.new()
	target.texture = load("res://assets/kenney_game_icons/target.png") as Texture2D
	target.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	target.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	target.position = Vector2(20.0, 196.0)
	target.size = Vector2(20.0, 20.0)
	target.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(target)
	for i in 3:
		var gl := _make_label(ui, 16, Color(0.9, 0.97, 1.0))
		gl.position = Vector2(46.0, 194.0 + float(i) * 24.0)
		_goal_labels.append(gl)
	_update_progress_ui()
	if not GameSession.tutorial_done:
		_show_tutorial()

	_power_bar = ProgressBar.new()
	_power_bar.min_value = 0.0
	_power_bar.max_value = 1.0
	_power_bar.step = 0.001
	_power_bar.show_percentage = false
	_power_bar.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	_power_bar.offset_left = -200.0
	_power_bar.offset_right = 200.0
	_power_bar.offset_top = -64.0
	_power_bar.offset_bottom = -34.0
	_power_bar.visible = false
	ui.add_child(_power_bar)

	_tension_bar = _make_bar(ui, 116.0, 142.0)
	_tension_fill = StyleBoxFlat.new()
	_tension_fill.bg_color = Color(0.3, 0.85, 0.4)
	_tension_bar.add_theme_stylebox_override("fill", _tension_fill)
	_stamina_bar = _make_bar(ui, 150.0, 164.0)
	_tension_label = _make_label(ui, 18, Color.WHITE)
	_tension_label.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	_tension_label.offset_top = 168.0
	_tension_label.offset_bottom = 194.0
	_tension_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_show_fight_ui(false)


func _make_bar(parent: Control, top: float, bottom: float) -> ProgressBar:
	var b := ProgressBar.new()
	b.min_value = 0.0
	b.max_value = 1.0
	b.step = 0.001
	b.show_percentage = false
	b.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	b.offset_left = 300.0
	b.offset_right = -300.0
	b.offset_top = top
	b.offset_bottom = bottom
	parent.add_child(b)
	return b


func _make_label(parent: Control, size: int, color: Color) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", Color(0.0, 0.08, 0.16, 0.9))
	l.add_theme_constant_override("outline_size", 6)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(l)
	return l


func _show_fight_ui(on: bool) -> void:
	_tension_bar.visible = on
	_stamina_bar.visible = on
	_tension_label.visible = on
	if _test_bar != null:
		_test_bar.visible = on and _test_fish


# ---------------------------------------------------------------- helpers
func _aim_dir() -> Vector2:
	return Vector2(sin(_aim), -cos(_aim))


func _rod_tip() -> Vector2:
	var d := _aim_dir()
	return _hand + d * ROD_LEN + d.orthogonal() * _rod_bend * ROD_BEND_PX


func _set_status(text: String) -> void:
	_status.text = text


## Short vibration on phones that support it (Android browsers). iOS Safari ignores it.
func _buzz(ms: int) -> void:
	if GameSession.vibration_on:
		Input.vibrate_handheld(ms)


## Daytime colour grade per sea: grey-blue Black Sea, bright Aegean, warm Mediterranean.
func _region_tint() -> Color:
	var region: String = _spot["region"]
	if region.contains("Black Sea"):
		return Color(0.86, 0.90, 0.95)
	if region.contains("Mediterranean"):
		return Color(1.0, 0.97, 0.90)
	if region.contains("Istanbul"):
		return Color(0.95, 0.95, 1.0)
	return Color(1.0, 1.0, 0.98)


func _update_coins() -> void:
	_coins_label.text = "Coins: %d   Fish: %d" % [GameSession.coins, GameSession.catches.size()]


func _add_ripple(pos: Vector2, big := false) -> void:
	_ripples.append({"pos": pos, "age": 0.0, "big": big})


## Splash: a ring plus droplets thrown up and out that fall back under gravity (particles).
func _splash(pos: Vector2, strength: float = 1.0) -> void:
	_add_ripple(pos, true)
	_splash_pos = pos
	_splash_age = 0.0
	for i in int(8.0 + 10.0 * strength):
		var v := Vector2.from_angle(_rng.randf() * TAU) * _rng.randf_range(20.0, 90.0) * strength
		_particles.append(Noc.Particle.new(pos, v, 0.0, _rng.randf_range(80.0, 220.0) * strength, 1.4, _rng.randf_range(1.5, 3.5), Color(1.0, 1.0, 1.0, 0.9)))


func _roll_species() -> String:
	var ids: Array = _spot["species"]
	var weights: Array[float] = []
	var total := 0.0
	for id: String in ids:
		var w := _species_weight(id)
		weights.append(w)
		total += w
	var pick := _rng.randf() * total
	for i in ids.size():
		pick -= weights[i]
		if pick <= 0.0:
			return ids[i]
	return ids[ids.size() - 1]


## Simulates the throw with the same forces as the real flight, for the aiming arc.
func _predict() -> void:
	var p := _rod_tip()
	var v := _aim_dir() * lerpf(170.0, 560.0, _power)
	var z := ROD_TIP_HEIGHT
	var vz := lerpf(150.0, 330.0, _power)
	var dt := 1.0 / 30.0
	_pred_path.clear()
	for i in 120:
		v += _wind * dt
		v *= maxf(0.0, 1.0 - AIR_DRAG * dt)
		p += v * dt
		vz -= GRAVITY_Z * dt
		z += vz * dt
		_pred_path.append(p - Vector2(0.0, maxf(z, 0.0)))
		if z <= 0.0:
			break
	_pred_landing = p


# ---------------------------------------------------------------- state machine
func _physics_process(delta: float) -> void:
	_time += delta
	_read_buttons()
	if _state != State.FIGHT:
		_adjust_clutch(delta)
	match _state:
		State.AIM:
			_walk(delta)
			_adjust_bait_depth(delta)
			if _cast_edge:
				if GameSession.stock(GameSession.bait_id) == 0:
					_flash("No live bait. Catch istavrit on a capari, or buy some at the map's tackle shop" if GameSession.bait_id == "live_fish" \
						else "No %s left. Buy a pack at the map's tackle shop, or pick another bait" % String(Tackle.BAITS[GameSession.bait_id]["name"]).to_lower())
				elif _can_cast():
					var lim := _aim_limit()
					_aim = clampf(atan2(_facing.x, -_facing.y), -lim, lim)
					_power = 0.0
					_power_dir = 1.0
					_state = State.CHARGE
					_set_status("Aim with the stick, release CAST to throw")
				else:
					_set_status("Walk to the water's edge, or out on the pier, to cast")
		State.CHARGE:
			_steer(delta)
			_power += _power_dir * delta / 1.1
			if _power >= 1.0:
				_power = 1.0
				_power_dir = -1.0
			elif _power <= 0.0:
				_power = 0.0
				_power_dir = 1.0
			_predict()
			if not Input.is_action_pressed(&"cast"):
				_do_cast()
		State.FLY:
			_tick_fly(delta)
		State.WAIT:
			_tick_wait(delta)
		State.BITE:
			_tick_bite(delta)
		State.FIGHT:
			_tick_fight(delta)
		State.RESULT:
			_result_t -= delta
			if _result_t <= 0.0:
				_result_label.text = ""
				_state = State.AIM
				_fight_view.end()
				_set_status("Walk with the stick. At the water's edge, hold CAST to throw")
	_update_boat(delta)
	_update_float(delta)
	_update_fish_agent(delta)
	_update_pov()
	_update_rope(delta)
	_update_shoals(delta)
	_update_particles(delta)
	_update_boats(delta)
	_update_neighbors(delta)


## A press counts once whether it came from a key (pressed now, not last frame) or a touch
## button (its press counter moved), so a tap shorter than a frame is not lost.
func _read_buttons() -> void:
	var cast_down := Input.is_action_pressed(&"cast")
	var reel_down := Input.is_action_pressed(&"reel_in")
	var cast_count := int(TouchControls.presses.get(&"cast", 0))
	var reel_count := int(TouchControls.presses.get(&"reel_in", 0))
	_cast_edge = (cast_down and not _cast_was) or cast_count != _cast_seen
	_reel_edge = (reel_down and not _reel_was) or reel_count != _reel_seen
	_cast_was = cast_down
	_reel_was = reel_down
	_cast_seen = cast_count
	_reel_seen = reel_count


func _steer(delta: float) -> void:
	var axis := Input.get_axis(&"steer_left", &"steer_right")
	var lim := _aim_limit()
	_aim = clampf(_aim + axis * 0.9 * delta, -lim, lim)


## On the pier you can throw to the sides as well; from the bank only out to sea.
func _aim_limit() -> float:
	if _boat_mode:
		return PI
	return 1.45 if _on_pier() else 0.9


# ---------------------------------------------------------------- walking, depth, tips
func _build_walkable() -> void:
	var bottom := 105.0 if _spot["kind"] == "bridge" else 132.0
	_walk_rects.append(Rect2(-HALF_WIDTH + 80.0, 14.0, HALF_WIDTH * 2.0 - 160.0, bottom - 14.0))
	if _has_pier:
		_walk_rects.append(Rect2(_pier_x - PIER_HALF + 8.0, -PIER_LEN + 12.0, (PIER_HALF - 8.0) * 2.0, PIER_LEN + 40.0))


func _walkable(p: Vector2) -> bool:
	for r in _walk_rects:
		if r.has_point(p):
			return true
	return false


## The stick walks the angler; each axis is tried on its own so you slide along edges.
func _walk(delta: float) -> void:
	if _boat_mode:
		return                            # rowing is handled every frame in _update_boat
	var mv := Input.get_vector(&"steer_left", &"steer_right", &"boat_forward", &"boat_back", 0.1)
	_moving = mv.length() > 0.05
	if not _moving:
		return
	_facing = mv.normalized()
	_aim = atan2(_facing.x, -_facing.y)
	var step := mv * WALK_SPEED * delta
	var nx := _hand + Vector2(step.x, 0.0)
	if _walkable(nx):
		_hand = nx
	var ny := _hand + Vector2(0.0, step.y)
	if _walkable(ny):
		_hand = ny
	_walk_phase += step.length() * 0.05          # about 2.4 steps a second at full speed
	var half := int(floor(_walk_phase / PI))
	if half != _step_half:
		_step_half = half
		_amb.play(_step_kind(), randf_range(0.28, 0.4))
	_check_tip()


## What the ground sounds like under the angler's feet.
func _step_kind() -> String:
	if _on_pier():
		return "step_wood"
	match String(_spot["kind"]):
		"beach":
			return "step_sand"
		"rocky":
			return "step_gravel"
	return "step_stone"


func _adjust_bait_depth(delta: float) -> void:
	var ax := Input.get_axis(&"bait_shallower", &"bait_deeper")
	if absf(ax) > 0.0 and _bottom_rig():
		_flash("Bottom rig: the bait lies on the bottom")
		return
	if absf(ax) > 0.0:
		_bait_depth = clampf(_bait_depth + ax * 3.0 * delta, 0.5, 30.0)
		_flash("Float depth %.1f m" % _bait_depth)


## The clutch (drag) is set before the fight, like on a real reel; during the fight
## FishingController adjusts it itself from the same actions.
func _adjust_clutch(delta: float) -> void:
	var ax := Input.get_axis(&"drag_down", &"drag_up")
	if absf(ax) > 0.0:
		var upper := minf(_fishing.drag_max_n, _fishing.line_break_force_n * 0.95)
		_fishing.drag_setting_n = clampf(_fishing.drag_setting_n + ax * _fishing.drag_adjust_n_s * delta, _fishing.drag_min_n, upper)
		_flash("Clutch %.0f N" % _fishing.drag_setting_n)


## A short on-screen readout of a setting that was just changed.
func _flash(text: String) -> void:
	_toast_text = text
	_toast_t = 1.1


func _pier_rect() -> Rect2:
	return Rect2(_pier_x - PIER_HALF, -PIER_LEN, PIER_HALF * 2.0, PIER_LEN + 20.0)


func _on_pier() -> bool:
	return _has_pier and _hand.y < 0.0 and _pier_rect().has_point(_hand)


func _can_cast() -> bool:
	return _boat_mode or _hand.y < 48.0 or _on_pier()


## The boat: oars push it while you are not fishing; wind and current drift it unless anchored.
## A body with forces and drag, as in Nature of Code chapter 2.
func _update_boat(delta: float) -> void:
	if not _boat_mode:
		return
	if Input.is_action_just_pressed(&"anchor") or int(TouchControls.presses.get(&"anchor", 0)) != _anchor_seen:
		_anchor_seen = int(TouchControls.presses.get(&"anchor", 0))
		_anchored = not _anchored
		_flash("Anchor down" if _anchored else "Anchor up: the boat drifts")
	var force := Vector2.ZERO
	var mv := Vector2.ZERO
	if _state == State.AIM:
		mv = Input.get_vector(&"steer_left", &"steer_right", &"boat_forward", &"boat_back", 0.1)
		force += mv * ROW_FORCE
		if mv.length() > 0.05:
			_anchored = false
			_facing = mv.normalized()
			_aim = atan2(_facing.x, -_facing.y)
	if not _anchored:
		force += _current * 0.6 + _wind * 0.05
	_boat_vel += force * delta
	_boat_vel *= maxf(0.0, 1.0 - BOAT_DRAG * delta)
	if _anchored:
		_boat_vel *= maxf(0.0, 1.0 - 6.0 * delta)
	var nxt := _hand + _boat_vel * delta
	nxt.x = clampf(nxt.x, -HALF_WIDTH + 200.0, HALF_WIDTH - 200.0)
	nxt.y = clampf(nxt.y, -1500.0, -160.0)          # stay off the rocks and in sight of the town
	_hand = nxt
	_moving = mv.length() > 0.05
	if _moving:
		_walk_phase += delta * 2.6               # a stroke every 2.4 s, a leisurely row
		var stroke := int(floor(_walk_phase / TAU))
		if stroke != _stroke_n:
			_stroke_n = stroke
			_amb.play("oar", 0.5)


func _is_land(p: Vector2) -> bool:
	return p.y > WATER_EDGE or (_has_pier and _pier_rect().has_point(p))


## Water depth under a point: the bottom drops at the spot's slope from the shoreline (y = 0).
func _water_depth(p: Vector2) -> float:
	if _is_land(p):
		return 0.0
	var slope := float(_spot.get("slope", 0.25))
	var maxd := float(_spot.get("max_depth_m", 15.0))
	return clampf(maxf(-p.y, 0.0) / PX_PER_M * slope + 0.4, 0.4, maxd)


## Where the bait actually hangs: the float setting, or just off the bottom in shallow water.
func _eff_depth() -> float:
	if _bottom_rig():
		return maxf(_water_depth(_bobber_pos) - 0.1, 0.3)       # the sinker holds it on the bottom
	return clampf(_bait_depth, 0.3, maxf(_water_depth(_bobber_pos) - 0.2, 0.3))


## A bottom rig only matters for natural baits; lures are always worked through the water.
func _bottom_rig() -> bool:
	return GameSession.rig_mode == "bottom" and not Tackle.is_lure(GameSession.bait_id)


## How likely a species is to take the bait right now: rarity, depth match, feeding time.
func _species_weight(id: String) -> float:
	var sp := BiomeDB.get_species(id)
	var w := 1.0 / sqrt(float(sp["base_price"]))
	var dr: Vector2 = sp["depth_m"]
	var d := _eff_depth()
	var miss := maxf(dr.x - d, 0.0) + maxf(d - dr.y, 0.0)
	w *= exp(-miss / 2.5)
	w *= BiomeDB.activity_factor(id, _world.time_of_day)
	w *= Tackle.bite_factor(id, GameSession.bait_id, GameSession.hook_id)
	w *= Season.factor(id)
	if BiomeDB.activity_kind(id) == "night":
		w *= Moon.night_factor(CEPHALOPODS.has(id), 1.0 - _world.daylight)
	return w


## 1 = a normal amount of feeding at this depth and hour; lower means a longer wait.
func _activity() -> float:
	var base := 0.0
	var now := 0.0
	for id: String in _spot["species"]:
		base += 1.0 / sqrt(float(BiomeDB.get_species(id)["base_price"]))
		now += _species_weight(id)
	var lamp := 1.0 + LAMP_PIER_BONUS * (1.0 - _world.daylight) if _on_pier() else 1.0
	return clampf(now / maxf(base, 0.0001) * float(WeatherFx.KINDS[_weather_kind]["activity"]) * lamp, 0.15, 2.0)


func _crowd_pos(a: Dictionary) -> Vector2:
	return Vector2(float(a["x"]), float(a["y"]) + 6.0)


## The nearest other angler within reach shares a tip about this spot.
func _check_tip() -> void:
	_tip_text = ""
	var tips: Array = _spot.get("tips", [])
	if tips.is_empty():
		return
	var best := TIP_RADIUS
	for i in _crowd.size():
		var cp := _crowd_pos(_crowd[i])
		var d := cp.distance_to(_hand)
		if d < best:
			best = d
			_tip_text = String(tips[i % tips.size()])
			_tip_pos = cp


func _do_cast() -> void:
	_bobber_pos = _rod_tip()
	_b_vel = _aim_dir() * lerpf(170.0, 560.0, _power) * (1.15 if _bottom_rig() else 1.0)   # a lead sinker flies farther
	_b_z = ROD_TIP_HEIGHT
	_b_vz = lerpf(150.0, 330.0, _power)
	_fish_id = ""
	_state = State.FLY
	_bait_on = true
	_empty_t = 0.0
	_set_status("")
	_fight_view.begin_cast()
	_amb.play("cast", 0.9)


## Projectile: wind and air drag on the ground velocity, gravity on the height.
func _tick_fly(delta: float) -> void:
	_b_vel += _wind * delta
	_b_vel *= maxf(0.0, 1.0 - AIR_DRAG * delta)
	_bobber_pos += _b_vel * delta
	_b_vz -= GRAVITY_Z * delta
	_b_z += _b_vz * delta
	if _b_z > 0.0:
		return
	_b_z = 0.0
	if _is_land(_bobber_pos):
		_retrieve("That landed on dry ground")
		return
	_cast_dist_m = _rod_tip().distance_to(_bobber_pos) / PX_PER_M
	_splash(_bobber_pos, 1.0)
	_amb.play("splash", 0.8)
	_float_x = 0.8
	_float_v = 0.0
	_float_pull = 0.0
	_state = State.WAIT
	_wait_t = _rng.randf_range(4.0, 10.0) / _activity()
	_ripple_clock = 0.0
	_set_status("%.0f m out, bait at %.1f m. Waiting...   Hold REEL to bring the bait in" % [_cast_dist_m, _eff_depth()])


func _tick_wait(delta: float) -> void:
	_adjust_bait_depth(delta)
	if _cast_edge:
		_retrieve("Reeled in")
		return
	# Holding REEL winds the bait in: the float travels back toward the rod at RETRIEVE_SPEED.
	# A tap while a fish is nibbling still counts as a strike attempt (handled below).
	if Input.is_action_pressed(&"reel_in") and not _reel_edge:
		var tip := _rod_tip()
		var to_rod := tip - _bobber_pos
		if to_rod.length() < 40.0:
			_retrieve("Bait is back")
			return
		_bobber_pos += to_rod.normalized() * RETRIEVE_SPEED * delta
		_float_x = lerpf(_float_x, 0.3, delta * 4.0)
		_ripple_clock += delta * 2.0
	_ripple_clock += delta
	if _ripple_clock > 1.9:
		_ripple_clock = 0.0
		_add_ripple(_bobber_pos)
	if _fish_id == "":
		if not _bait_on:
			# Bare hook: nothing will come. A real angler notices the float has gone dead.
			_empty_t += delta
			if _empty_t > 20.0:
				_empty_t = 0.0
				_flash("Nothing for a while. Is the bait still on? Reel in to check")
			return
		if Tackle.is_lure(GameSession.bait_id):
			# A lure only fishes while it moves.
			_wait_t -= delta * (1.6 if Input.is_action_pressed(&"reel_in") else 0.08)
		else:
			_wait_t -= delta
		_quiet_t += delta
		if _quiet_t > 12.0:
			_quiet_t = 0.0
			if _activity() < 0.5:
				_flash("Quiet water: little feeds at this depth and hour")
		if _wait_t <= 0.0:
			_fish_arrives()
		return
	if _fish_mode == "approach":
		if _fish_agent != null and _fish_agent.pos.distance_to(_bobber_pos) < 30.0:
			_fish_mode = "nibble"
			_event_t = _rng.randf_range(0.4, 1.0)
			_fish_time = 0.0
		return
	_fish_time += delta
	if _reel_edge:
		if _rng.randf() < float(_prof["spook_chance"]):
			_fish_leaves("Too early! The fish got spooked")
		return
	if _fish_time > float(_prof["max_nibble_s"]):
		_fish_leaves("The fish lost interest")
		return
	_event_t -= delta
	if _event_t <= 0.0:
		_fish_event()


func _fish_arrives() -> void:
	_fish_id = _roll_species()
	_prof = BiomeDB.get_bite_profile(_fish_id)
	var nr: Vector2i = _prof["nibbles"]
	_nib_left = _rng.randi_range(nr.x, nr.y)
	if Tackle.is_lure(GameSession.bait_id):
		_nib_left = 0                     # a predator hits a moving lure at once
	var sp := BiomeDB.get_species(_fish_id)
	var fight: Dictionary = sp["fight"]
	var wt: Vector2 = sp["weight_kg"]
	var spd := clampf(40.0 + float(fight["pull_n"]) * 1.5, 45.0, 170.0)
	var start := _bobber_pos + Vector2.from_angle(_rng.randf() * TAU) * 300.0
	_fish_agent = Noc.Vehicle.new(start, spd, spd * 2.2)
	_fish_agent.data = {"len": 22.0 + sqrt(wt.y) * 5.0}
	_fish_mode = "approach"
	_set_status("Something is coming...")


func _fish_event() -> void:
	if _nib_left > 0:
		_nib_left -= 1
		_float_v += 6.0
		_buzz(35)
		_amb.play("bell" if _bottom_rig() else "plop", 0.3 if _bottom_rig() else 0.35)
		_add_ripple(_bobber_pos)
		if _fish_agent != null:
			_fish_agent.vel += (_bobber_pos - _fish_agent.pos).normalized() * 60.0
		_set_status("Nibble!  Wait for the real bite")
		if _rng.randf() < Tackle.steal_chance(GameSession.bait_id):
			_bait_on = false
			GameSession.use_bait(GameSession.bait_id)
			_fish_leaves("The float went still")
			return
		var hz := maxf(float(_prof["noise_hz"]), 0.5)
		_event_t = _rng.randf_range(0.6, 1.4) * 2.5 / hz
	else:
		_state = State.BITE
		_fish_mode = "bite"
		_bite_t = float(_prof["bite_window_s"])
		_float_pull = 1.3
		_float_v += 10.0
		_buzz(90)
		_amb.play("bell" if _bottom_rig() else "plop", 0.9)
		_add_ripple(_bobber_pos, true)
		_set_status("BITE!  Press REEL now")


func _tick_bite(delta: float) -> void:
	_bite_t -= delta
	if _reel_edge:
		_hook_fish()
		return
	if _bite_t <= 0.0:
		if _rng.randf() < float(_prof["self_hook_chance"]):
			_hook_fish()
		else:
			_fish_leaves("Too slow. It got away with the bait")


func _fish_leaves(message: String) -> void:
	_fish_id = ""
	_fish_mode = "leave"
	_float_pull = 0.0
	_state = State.WAIT
	_wait_t = _rng.randf_range(5.0, 12.0) / _activity()
	_set_status(message)


func _retrieve(message: String) -> void:
	_fish_id = ""
	if _fish_agent != null:
		_fish_mode = "leave"
	_float_pull = 0.0
	_state = State.AIM
	_fight_view.end()
	if not _bait_on:
		message = "The bait was gone, picked off by small fish. You bait up again"
		_bait_on = true
	_set_status(message + ".   Aim and throw again")


func _hook_fish(force: bool = false) -> void:
	# Does the strike set the hook? Depends on the hook size against this fish's mouth.
	if not force and _rng.randf() > Tackle.hookup_chance(_fish_id, GameSession.hook_id, GameSession.bait_id):
		var mis := Tackle.hook_misfit(_fish_id, GameSession.hook_id, GameSession.bait_id)
		var why := "  (hook too big for its mouth)" if mis > 0 else ("  (hook too small to hold)" if mis < 0 else "")
		_fish_leaves("Missed! The hook did not set" + why)
		return
	if not force:
		GameSession.use_bait(GameSession.bait_id)          # the fish has taken it
	var species := BiomeDB.get_species(_fish_id)
	_weight_kg = _forced_kg if _forced_kg > 0.0 else BiomeDB.roll_weight_kg(_fish_id, _rng)
	_forced_kg = 0.0
	_fishing.apply_rig(BiomeDB.get_rig(GameSession.rig_id))
	_fishing.hook_fish(_fish_id, species, _weight_kg, _cast_dist_m)
	var start := _bobber_pos if _fish_agent == null else _fish_agent.pos
	_fight_agent = Noc.Vehicle.new(start, 220.0, 600.0)
	_fish_agent = null
	_fish_mode = ""
	_float_pull = 0.0
	_state = State.FIGHT
	_kick = 0.18
	_fight_hint = ""
	_buzz(120)
	_amb.play("strike", 1.0)
	_amb.play("splash_big", 0.6)
	_splash(_bobber_pos, 1.2)
	_show_fight_ui(true)
	_fight_view.begin(_fish_id, _weight_kg, _cast_dist_m)


## The FishingController decides how far out the fish is; the visible fish is an agent that
## arrives on that point and wanders sideways, so it zigzags like a real fish on the line.
func _tick_fight(delta: float) -> void:
	if _fight_agent == null:
		return
	var shaking := _fishing.head_shake > 0.0
	if shaking and not _was_shaking:
		_flash("Head shakes! Keep the line tight")
		_buzz(60)
	_was_shaking = shaking
	# A hook pulled harder than its wire can take opens up and the fish is gone.
	if _fishing.tension_n > Tackle.hook_strength(GameSession.hook_id, GameSession.bait_id):
		_overhook_t += delta
		if _overhook_t > 0.35:
			_overhook_t = 0.0
			_escape_reason = "The hook opened up: %s is too light for this fish" % Tackle.hook_name(GameSession.hook_id)
			_fishing._finish(FishingController.State.ESCAPED)
			return
	else:
		_overhook_t = maxf(0.0, _overhook_t - delta)
	var target := _rod_tip() + _aim_dir() * _fishing.fish_pos_m * PX_PER_M
	var f := _fight_agent
	f.apply_force(f.arrive(target, 80.0) * 2.0)
	f.apply_force(f.wander(delta, 40.0, 30.0, 6.0) * (0.3 + _fishing.stamina))
	f.update(delta)
	if _fishing._burst_mult > 1.0 and _rng.randf() < delta * 2.5:
		_splash(f.pos, 0.8)
		_buzz(25)
		_amb.play("drag", 0.7)


# ---------------------------------------------------------------- soundscape
## Background life by season, hour and place: cicadas on summer days, crickets on warm nights,
## the tak-tak of a fishing boat's diesel as one passes close, waves lapping the rocks or posts,
## and now and then a ferry's horn at Istanbul and the harbours.
func _update_soundscape(delta: float) -> void:
	var m := Season.month()
	var day := _world.daylight
	var summer := m >= 6 and m <= 9
	var warm := m >= 5 and m <= 10
	_amb.set_bed("cicada", (0.35 * clampf((day - 0.55) * 3.0, 0.0, 1.0)) if summer else 0.0)
	_amb.set_bed("cricket", (0.3 * clampf((0.35 - day) * 4.0, 0.0, 1.0)) if warm else 0.0)
	var near := 99999.0
	for b in _boats:
		near = minf(near, (b.pos as Vector2).distance_to(_hand))
	_amb.set_bed("engine", clampf(1.0 - near / 900.0, 0.0, 1.0) * 0.6)
	_amb.set_bed("rain", 0.6 if _weather_kind == "drizzle" else 0.0)
	_amb.set_bed("wind", clampf(_wind.length() / 150.0, 0.0, 1.0) * 0.8)
	_lap_t -= delta
	if _lap_t <= 0.0:
		_lap_t = _rng.randf_range(2.5, 6.0)
		if _hand.y > -60.0 or _on_pier():
			_amb.play("lap", _rng.randf_range(0.15, 0.35))
	var kind := String(_spot["kind"])
	if kind == "bridge" or kind == "harbor":
		_horn_t -= delta
		if _horn_t <= 0.0:
			_horn_t = _rng.randf_range(70.0, 150.0)
			_amb.play_at("horn", 1.0, 120.0)          # a ferry across the water: dull and a third of a second late


# ---------------------------------------------------------------- first-person view
## Feeds the first-person view: where the bait, float or fish is, in metres right of and ahead of
## the rod tip along the aim line, and hides the top-down world while the view covers it.
func _update_pov() -> void:
	var v := _fight_view
	var right := Vector2(cos(_aim), sin(_aim))
	var fwd := _aim_dir()
	var tip := _rod_tip()
	match _state:
		State.FLY:
			var rel := _bobber_pos - tip
			v.phase = "fly"
			v.target_x = rel.dot(right) / PX_PER_M
			v.target_z = maxf(rel.dot(fwd) / PX_PER_M, 1.0)
			v.target_h = _b_z / PX_PER_M * 0.5
		State.WAIT, State.BITE:
			var rel2 := _bobber_pos - tip
			v.phase = "float"
			v.target_x = rel2.dot(right) / PX_PER_M
			v.target_z = maxf(rel2.dot(fwd) / PX_PER_M, 1.0)
			v.target_h = 0.0
			v.float_dip = _float_x
		State.FIGHT:
			v.phase = "fight"
			if _fight_agent != null:
				v.target_x = clampf((_fight_agent.pos - tip).dot(right) / PX_PER_M, -12.0, 12.0)
			v.target_z = maxf(_fishing.fish_pos_m, 1.0)
			v.target_h = 0.0
	v.tension = _tension_ratio if _state == State.FIGHT else 0.0
	v.lure = Tackle.is_lure(GameSession.bait_id)
	v.bottom = _bottom_rig()
	v.reeling = Input.is_action_pressed(&"reel_in")
	v.time_of_day = _world.time_of_day
	v.wind_x = _wind.x
	v.wave_amp = float(WeatherFx.KINDS[_weather_kind]["wind"])
	v.on_pier = _on_pier()
	v.eye_h = 8.0 if v.kind == "bridge" else (4.5 if v.on_pier else 2.6)
	if _boat_mode:
		v.kind = "boat"
		v.on_pier = false
		v.eye_h = 1.4
	var pov := v.is_open()
	_world.visible = not pov
	_water.visible = not pov
	_pov_on = pov


# ---------------------------------------------------------------- Nature of Code updates
## The float is a damped spring around its rest depth; nibbles kick it, a bite holds it under.
func _update_float(delta: float) -> void:
	if _state != State.WAIT and _state != State.BITE:
		return
	var rest := _float_pull + sin(_time * 1.7) * 0.08
	var r := Noc.spring_step(_float_x, _float_v, rest, 70.0, 7.0, delta)
	_float_x = r.x
	_float_v = r.y
	# A float rides the current; a bottom lead holds, but rolls along when the current is strong.
	var hold := 0.6
	if _bottom_rig():
		hold = 0.15 if _current.length() > 0.7 * PX_PER_M else 0.02
	var drifted := _bobber_pos + _current * delta * hold
	if not _is_land(drifted):          # the current never pushes the float onto the planks or the shore
		_bobber_pos = drifted


func _update_fish_agent(delta: float) -> void:
	if _fish_agent == null:
		return
	var f := _fish_agent
	match _fish_mode:
		"approach":
			f.apply_force(f.arrive(_bobber_pos, 120.0))
			f.apply_force(f.wander(delta, 30.0, 14.0, 4.0) * 0.4)
			if f.pos.distance_to(_bobber_pos) < 90.0 and _rng.randf() < delta * 0.8:
				_add_ripple(f.pos)            # nervous water: something moving near the float
		"nibble":
			f.apply_force(f.arrive(_bobber_pos + Vector2.from_angle(_time * 0.7) * 18.0, 60.0))
		"bite":
			var away := (_bobber_pos - _hand).normalized()
			f.apply_force(f.seek(_bobber_pos + away * 60.0) * 1.5)
		"leave":
			f.apply_force(f.flee(_bobber_pos, 5000.0))
			if f.pos.distance_to(_bobber_pos) > 450.0:
				_fish_agent = null
				return
	f.update(delta)


func _update_rope(delta: float) -> void:
	var tip := _rod_tip()
	var end := tip
	var slack := 0.0
	match _state:
		State.FLY:
			end = _bobber_pos - Vector2(0.0, _b_z)
			slack = 0.03
		State.WAIT, State.BITE:
			end = _bobber_pos
			slack = 0.07
		State.FIGHT:
			if _fight_agent != null:
				end = _fight_agent.pos
			slack = (1.0 - clampf(_tension_ratio * 2.0, 0.0, 1.0)) * 0.08
		_:
			_rope.reset(ROPE_POINTS, tip, tip)
			return
	var length := tip.distance_to(end) * (1.0 + slack)
	_rope.step(tip, end, length, _current * 3.0 + _wind * 0.4, delta)


func _update_shoals(delta: float) -> void:
	_splash_age += delta
	for group in _shoals:
		Noc.flock(group, 16.0, 70.0, 1.6, 1.0, 0.9)
		for f in group:
			f.apply_force(f.wander(delta, 30.0, 12.0, 3.0) * 0.5)
			f.apply_force(f.contain(SHOAL_BOUNDS, 80.0))
			if _splash_age < 2.5:
				f.apply_force(f.flee(_splash_pos, 220.0) * 3.0)
			if _fight_agent != null and _state == State.FIGHT:
				f.apply_force(f.flee(_fight_agent.pos, 160.0) * 2.5)
			if _fish_agent != null:
				f.apply_force(f.flee(_fish_agent.pos, 90.0) * 1.5)
			f.update(delta)
		if _rng.randf() < delta * 0.5:
			var g: Noc.Vehicle = group[_rng.randi() % group.size()]
			_add_ripple(g.pos)               # a shoal dimpling the surface


func _update_particles(delta: float) -> void:
	for p in _particles:
		p.update(delta, 520.0, 1.5)
	var alive: Array = []
	for p in _particles:
		if p.dead() or (p.z <= 0.0 and p.vz < 0.0 and p.age > 0.15):
			if _rng.randf() < 0.25:
				_add_ripple(p.pos)
		else:
			alive.append(p)
	_particles = alive
	if _spot["kind"] == "rocky" and not _rocks.is_empty():
		_spray_clock += delta
		if _spray_clock > 0.7:
			_spray_clock = 0.0
			var rock: Dictionary = _rocks[_rng.randi() % _rocks.size()]
			var rc: Vector2 = rock["c"]
			if rc.y < 25.0:
				var rr: float = rock["r"]
				for i in 6:
					var v := Vector2(_rng.randf_range(-30.0, 30.0), _rng.randf_range(-30.0, -5.0))
					_particles.append(Noc.Particle.new(rc - Vector2(0.0, rr * 0.7), v, 0.0, _rng.randf_range(60.0, 140.0), 1.0, _rng.randf_range(1.5, 3.0), Color(1.0, 1.0, 1.0, 0.8)))


## Boats follow the sea lane (Reynolds path following) and leave a wake of ripples.
func _update_boats(delta: float) -> void:
	for b in _boats:
		b.apply_force(b.follow_path(_boat_lane, 30.0))
		b.update(delta)
		b.data["trail"] = float(b.data["trail"]) - delta
		if float(b.data["trail"]) <= 0.0:
			b.data["trail"] = 0.35
			_add_ripple(b.pos - b.heading() * 40.0, true)


## Where a neighbour's float sits: at the end of their line, bobbing on a slow wave.
func _neighbor_float(a: Dictionary) -> Vector2:
	var x := float(a["x"])
	var ph := float(a["phase"])
	var out := Vector2(x + sin(_time * 0.4 + ph) * 14.0 + sin(ph) * 30.0, float(a["y"]) - 30.0 - float(a["len"]) + sin(_time * 1.7 + ph) * 2.0)
	match String(a.get("state", "wait")):
		"fight":
			# the fish pulls the float under and drags it about, and it comes closer as they reel
			var k := clampf(float(a["t"]) / 7.0, 0.15, 1.0)
			out = _neighbor_tip(a).lerp(out, k) + Vector2(sin(_time * 3.1 + ph) * 22.0, cos(_time * 2.3 + ph) * 8.0)
		"land", "cast":
			out = _neighbor_tip(a) + Vector2(0.0, 26.0)
	return out


## Rod tip of another angler: the rod rises from their hands toward the water and bends on a fish.
func _neighbor_tip(a: Dictionary) -> Vector2:
	var hold := _neighbor_hold(a)
	var ph := float(a["phase"])
	var st := String(a.get("state", "wait"))
	var lean := sin(ph) * 22.0
	if st == "fight":
		return hold + Vector2(lean + sin(_time * 4.0 + ph) * 10.0, -48.0)
	if st == "land":
		return hold + Vector2(lean * 0.3, -82.0)
	if st == "cast":
		var k := clampf(float(a["t"]) / 0.8, 0.0, 1.0)
		return hold + Vector2(lean, -80.0).rotated(k * 1.6)
	return hold + Vector2(lean, -78.0 + sin(_time * 1.2 + ph) * 2.0)


func _neighbor_hold(a: Dictionary) -> Vector2:
	return Vector2(float(a["x"]), float(a["y"]) + 18.0) + Vector2(5.0, -36.0)


## Now and then another angler hooks something: a splash at their float and a sound, quieter
## the further away they are.
func _update_neighbors(delta: float) -> void:
	# Each other angler runs the same loop as you: wait, bite and fight, land the fish, cast again.
	# Bites come faster when the fish are feeding (same activity as yours).
	var species: Array = _spot["species"]
	for a in _crowd:
		var t := float(a["t"]) - delta
		var st := String(a["state"])
		if t <= 0.0:
			var near := absf(float(a["x"]) - _cam.position.x) < 1300.0 and not _pov_on
			match st:
				"wait":
					st = "fight"
					t = _rng.randf_range(4.0, 9.0)
					a["sp"] = String(species[_rng.randi() % species.size()]) if not species.is_empty() else ""
					a["kg"] = BiomeDB.roll_weight_kg(String(a["sp"]), _rng) if String(a["sp"]) != "" else 0.4
					if near:
						_splash(_neighbor_float(a), 0.7)
						_amb.play_at("splash", 0.9, absf(float(a["x"]) - _hand.x) / PX_PER_M)
				"fight":
					if _rng.randf() < 0.25:
						st = "cast"                                  # it got away
						t = 0.8
					else:
						st = "land"
						t = 2.4
						_tourney_rival_landed(a)
						if near:
							_amb.play_at("drips", 0.7, absf(float(a["x"]) - _hand.x) / PX_PER_M)
				"land":
					st = "cast"
					t = 0.8
				_:
					st = "wait"
					t = _rng.randf_range(12.0, 45.0) / maxf(_activity(), 0.3)
					if near:
						_amb.play_at("cast", 0.8, absf(float(a["x"]) - _hand.x) / PX_PER_M)
		a["t"] = t
		a["state"] = st


# ---------------------------------------------------------------- fight results
func _on_tension(_tension_n: float, ratio: float, bend: float) -> void:
	_tension_ratio = ratio
	_rod_bend_target = bend
	_shake = ratio * ratio


## keep_view: leave the side view up (the catch card is showing and fades out on its own).
func _end_fight(keep_view: bool = false) -> void:
	_test_fish = false
	_show_fight_ui(false)
	if not keep_view:
		_fight_view.end()
	_fish_id = ""
	_fight_agent = null
	_rod_bend_target = 0.0
	_shake = 0.0
	_state = State.RESULT
	_result_t = 3.6


func _on_caught(id: String, weight_kg: float) -> void:
	var sp := BiomeDB.get_species(id)
	if _test_fish:
		_test_fish = false
		var tcm := Regulations.length_cm(id, weight_kg)
		_fight_view.show_catch("TEST: " + String(sp["name"]), PackedStringArray(["%.2f kg, %.0f cm" % [weight_kg, tcm], String(sp["scientific"]), "Test catch: no coins, no XP, not in the journal"]))
		_result_label.text = ""
		_set_status("Test catch")
		_amb.play("splash", 0.7)
		_amb.play("drips", 0.8)
		_end_fight(true)
		return
	# From a pier, quay or bridge the fish has to come up through the air. Lifted on the line, its
	# weight plus the jerk of the lift (about twice its weight) can part the line; a net takes it.
	var high := not _boat_mode and (_on_pier() or String(_spot["kind"]) == "bridge" or String(_spot["kind"]) == "harbor")
	if high and not GameSession.has_net and weight_kg * 9.81 * 2.0 > _fishing.line_break_force_n:
		_buzz(250)
		_amb.play("snap", 0.8)
		_amb.play("splash", 1.0)
		_result_label.text = "Lost it at the last moment!"
		_set_status("Too heavy to lift on the line from up here. A landing net (kepce) would have saved it")
		_end_fight()
		return
	# Turkish amateur rules (Regulations): under-size fish, a second turbot, or fish past the daily
	# 5 kg go back into the sea. You still learn from it: a few XP, no coins, no journal entry.
	var cm := Regulations.length_cm(id, weight_kg)
	var why_release := ""
	var legal := Regulations.min_cm(id)
	var kept: Dictionary = GameSession.outing.get("kept", {})
	if legal > 0.0 and cm < legal:
		why_release = "Under the legal size: %.0f cm, minimum %.0f cm" % [cm, legal]
	elif Regulations.COUNT_LIMIT.has(id) and int(kept.get(id, 0)) >= int(Regulations.COUNT_LIMIT[id]):
		why_release = "Limit is %d per day for this species" % int(Regulations.COUNT_LIMIT[id])
	elif float(GameSession.outing.get("kept_kg", 0.0)) + weight_kg > Regulations.DAILY_KG:
		why_release = "Daily limit of %.0f kg reached" % Regulations.DAILY_KG
	if why_release != "":
		GameSession.xp += 3
		GameSession.save()
		_update_progress_ui()
		var rel_lines := PackedStringArray(["%.2f kg, %.0f cm" % [weight_kg, cm], why_release, "+3 XP for doing it right"])
		var nod := _local_says(id, weight_kg, true)
		if nod != "":
			rel_lines.append(nod)
		_fight_view.show_catch("Released: " + String(sp["name"]), rel_lines)
		_result_label.text = ""
		_set_status("Released. Good practice keeps the fish coming")
		_amb.play("splash", 0.5)
		_end_fight(true)
		return
	if not GameSession.outing.is_empty():
		kept[id] = int(kept.get(id, 0)) + 1
		GameSession.outing["kept"] = kept
		GameSession.outing["kept_kg"] = float(GameSession.outing.get("kept_kg", 0.0)) + weight_kg
	var for_local := Locals.on_kept(GameSession.spot_id, id)
	var tourney_line := _tourney_player_landed(weight_kg)
	var value := int(round(float(sp["base_price"]) * pow(maxf(weight_kg, 0.05), 0.8)))
	var res := GameSession.record_catch(id, String(sp["name"]), weight_kg, value, int(sp["base_price"]))
	_update_coins()
	_update_progress_ui()
	var badge := "NEW SPECIES!  " if bool(res["first"]) else ("NEW RECORD!  " if bool(res["record"]) else "")
	var lines := PackedStringArray(["%.2f kg, %.0f cm   +%d coins   +%d XP" % [weight_kg, cm, value, int(res["xp"])], String(sp["scientific"]),
		"On %s, hook %s" % [String(Tackle.BAITS[GameSession.bait_id]["name"]).to_lower(), Tackle.hook_name(GameSession.hook_id)]])
	if GameSession.LIVE_BAIT_SPECIES.has(id) and weight_kg < 0.4 and GameSession.live_bait < GameSession.LIVE_BAIT_MAX:
		lines.append("Into the bucket as live bait  (%d)" % GameSession.add_live_bait(1))
	if tourney_line != "":
		lines.append(tourney_line)
	var shout := _local_says(id, weight_kg, false)
	if shout != "":
		lines.append(shout)
	if for_local:
		var lr := Locals.request(GameSession.spot_id)
		lines.append("For %s: %d / %d%s" % [String(Locals.person(GameSession.spot_id)["name"]), int(lr["have"]), int(lr["need"]),
			"  -  go and give them!" if Locals.can_turn_in(GameSession.spot_id) else ""])
	var daily := Daily.try_complete(GameSession.spot_id, id, weight_kg)
	if daily > 0:
		lines.append("DAILY CHALLENGE DONE!  +%d coins, +%d XP" % [daily, Daily.XP])
		_buzz(150)
	var done: Array = res["goals_done"]
	for g: Dictionary in done:
		lines.append("Goal done: %s  (+%d coins)" % [g["text"], int(g["coins"])])
	if bool(res["level_up"]):
		lines.append("LEVEL UP!  Level %d%s" % [int(res["level"]), _unlock_text(int(res["level"]))])
		_buzz(200)
	_fight_view.show_catch(badge + String(sp["name"]), lines)
	_result_label.text = ""
	_set_status("Nice one")
	_amb.play("splash", 0.7)
	_amb.play("drips", 0.8)
	_amb.play_later("flop", 0.5, 0.9)            # it lands on the planks or the rocks and thrashes
	_end_fight(true)


## Names of the spots that open at this level, for the level-up line: "  -  Unlocked: Galata Bridge".
func _unlock_text(lv: int) -> String:
	var names: PackedStringArray = []
	for id: String in FishingSpots.ids():
		var sp := FishingSpots.get_spot(id)
		if int(sp.get("unlock_level", 1)) == lv:
			names.append(String(sp["name"]))
	return "" if names.is_empty() else "  -  Unlocked: " + ", ".join(names)


## Three goals for this outing, built from the spot's own data (see GAME_DESIGN.md, Progression):
## catch 3 fish; log a new species (or 2 different ones when everything here is logged); land one
## fish of a reachable weight. Reward numbers are tuning knobs.
func _make_goals() -> Array[Dictionary]:
	var goals: Array[Dictionary] = []
	goals.append({"kind": "count", "text": "Catch 3 fish", "target": 3, "progress": 0, "coins": 40, "xp": 0, "done": false})
	var ids: Array = _spot["species"]
	var unlogged := 0
	for id: String in ids:
		if not GameSession.counts.has(id):
			unlogged += 1
	if unlogged > 0:
		goals.append({"kind": "new", "text": "Log a new species", "target": 1, "progress": 0, "coins": 60, "xp": 15, "done": false})
	else:
		goals.append({"kind": "distinct", "text": "Catch 2 different species", "target": 2, "progress": 0, "coins": 60, "xp": 15, "done": false})
	var best_max := 0.0
	for id: String in ids:
		var wr: Vector2 = BiomeDB.get_species(id)["weight_kg"]
		if wr.y <= 12.0 and wr.y > best_max:
			best_max = wr.y
	if best_max > 0.0:
		var kg := snappedf(best_max * 0.45, 0.1)
		goals.append({"kind": "weight", "text": "Land a fish of %.1f kg or more" % kg, "target": kg, "progress": 0, "coins": 80, "xp": 0, "done": false})
	return goals


func _update_progress_ui() -> void:
	var lv := GameSession.level()
	var pr := GameSession.level_progress()
	_level_label.text = "Level %d   %d / %d XP" % [lv, int(pr.x), int(pr.y)] if lv < GameSession.MAX_LEVEL else "Level %d (max)" % lv
	_xp_bar.value = pr.x / maxf(pr.y, 1.0)
	var goals: Array = GameSession.outing.get("goals", [])
	for i in _goal_labels.size():
		if i < goals.size():
			var g: Dictionary = goals[i]
			_goal_labels[i].text = GameSession.goal_line(g)
			_goal_labels[i].modulate = Color(0.6, 1.0, 0.7) if bool(g["done"]) else Color.WHITE
		else:
			_goal_labels[i].text = ""


## MAP: not in the middle of a fight; with something to report, show the outing summary first.
func _on_map_pressed() -> void:
	if _state == State.FIGHT:
		_flash("Finish the fight first")
		return
	var out := GameSession.outing
	var goals: Array = out.get("goals", [])
	var any_goal := false
	for g: Dictionary in goals:
		if int(g["progress"]) > 0:
			any_goal = true
	if int(out.get("catches", 0)) == 0 and not any_goal:
		get_tree().change_scene_to_file(MAP_SCENE)
		return
	_show_summary()


func _show_summary() -> void:
	if _summary != null and is_instance_valid(_summary):
		_summary.queue_free()
	var out := GameSession.outing
	_summary = PanelContainer.new()
	_summary.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_summary.offset_left = -330.0
	_summary.offset_right = 330.0
	_summary.offset_top = -250.0
	_summary.offset_bottom = 250.0
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.02, 0.10, 0.18, 0.96)
	style.set_corner_radius_all(18)
	style.set_content_margin_all(20)
	style.set_border_width_all(2)
	style.border_color = Color(1.0, 0.85, 0.4, 0.8)
	_summary.add_theme_stylebox_override("panel", style)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	_summary.add_child(box)
	var title := _plain_label(box, 30, Color(1.0, 0.92, 0.6))
	title.text = "Outing summary  -  %s" % _spot["name"]
	var lines: PackedStringArray = []
	lines.append("Fish landed: %d" % int(out.get("catches", 0)))
	lines.append("XP earned: %d     Coins earned: %d" % [int(out.get("xp", 0)), int(out.get("coins", 0))])
	var fresh: Array = out.get("new_species", [])
	lines.append("New species: " + (", ".join(PackedStringArray(fresh)) if not fresh.is_empty() else "none"))
	var recs: Array = out.get("records", [])
	lines.append("Records: " + (", ".join(PackedStringArray(recs)) if not recs.is_empty() else "none"))
	var lv := GameSession.level()
	lines.append("Level %d%s" % [lv, "   (was %d)" % int(out.get("start_level", lv)) if lv > int(out.get("start_level", lv)) else ""])
	for ln in lines:
		_plain_label(box, 22, Color.WHITE).text = ln
	var goals: Array = out.get("goals", [])
	var gh := _plain_label(box, 22, Color(0.8, 0.95, 1.0))
	gh.text = "Goals"
	for g: Dictionary in goals:
		var gl := _plain_label(box, 20, Color(0.6, 1.0, 0.7) if bool(g["done"]) else Color(0.85, 0.9, 0.95))
		gl.text = "  " + GameSession.goal_line(g)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	box.add_child(row)
	var back := Button.new()
	back.text = "BACK TO MAP"
	back.custom_minimum_size = Vector2(260.0, 60.0)
	back.add_theme_font_size_override("font_size", 24)
	back.pressed.connect(func() -> void: get_tree().change_scene_to_file(MAP_SCENE))
	row.add_child(back)
	var keep := Button.new()
	keep.text = "KEEP FISHING"
	keep.custom_minimum_size = Vector2(260.0, 60.0)
	keep.add_theme_font_size_override("font_size", 24)
	keep.pressed.connect(func() -> void: _summary.queue_free())
	row.add_child(keep)
	_hud_root.add_child(_summary)


## TEST tools (GameSession.test_tools): hook any species at once to check its picture and fight.
func _open_test_panel() -> void:
	if _state != State.AIM:
		_flash("Reel in first")
		return
	if _test_panel != null and is_instance_valid(_test_panel):
		_test_panel.queue_free()
	var panel := PanelContainer.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	panel.offset_left = -470.0
	panel.offset_right = 470.0
	panel.offset_top = -330.0
	panel.offset_bottom = 330.0
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.02, 0.10, 0.18, 0.96)
	style.set_corner_radius_all(18)
	style.set_content_margin_all(16)
	panel.add_theme_stylebox_override("panel", style)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	panel.add_child(box)
	_plain_label(box, 26, Color(1.0, 0.92, 0.6)).text = "Test: hook a species now"
	var sizes := HBoxContainer.new()
	sizes.add_theme_constant_override("separation", 8)
	box.add_child(sizes)
	_plain_label(sizes, 18, Color.WHITE).text = "Size:"
	for entry: Array in [["SMALL", 0.05], ["MEDIUM", 0.4], ["LARGE", 0.95]]:
		var sb := _tackle_button(String(entry[0]), absf(_test_size - float(entry[1])) < 0.01, Vector2(150.0, 46.0))
		var v := float(entry[1])
		sb.pressed.connect(func() -> void:
			_test_size = v
			_open_test_panel())
		sizes.add_child(sb)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	box.add_child(scroll)
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	scroll.add_child(grid)
	var ids: Array[String] = []
	for sid: String in BiomeDB.fish.keys():
		ids.append(sid)
	ids.sort()
	for sid: String in ids:
		var mark := "* " if RealFish.sprite(sid) != null else ""
		var tb := _tackle_button(mark + String(BiomeDB.get_species(sid)["name"]), false, Vector2(290.0, 46.0))
		tb.pressed.connect(func() -> void:
			panel.queue_free()
			_test_hook(sid, _test_size))
		grid.add_child(tb)
	_plain_label(box, 15, Color(0.8, 0.9, 1.0)).text = "* = has a painted picture. After hooking, use JUMP, THRASH, ROLL and LAND at the top. Test catches give no coins or XP."
	var close := _tackle_button("CLOSE", false, Vector2(200.0, 52.0))
	close.pressed.connect(func() -> void: panel.queue_free())
	box.add_child(close)
	_test_panel = panel
	_hud_root.add_child(panel)


## Hooks `id` at once, 25 m out in front of you, at a size from 0 (smallest) to 1 (largest).
func _test_hook(id: String, size01: float) -> void:
	if _state != State.AIM:
		return
	_facing = Vector2.UP
	_aim = 0.0
	_cast_dist_m = 25.0
	_bobber_pos = _rod_tip() + _aim_dir() * _cast_dist_m * PX_PER_M
	_fight_view.begin_cast()
	_bait_on = true
	_fish_id = id
	_prof = BiomeDB.get_bite_profile(id)
	var wr: Vector2 = BiomeDB.get_species(id)["weight_kg"]
	_forced_kg = lerpf(wr.x, wr.y, size01)
	_test_fish = true
	_hook_fish(true)


## The buttons at the top while a test fish is on: force a surfacing, or land it now.
func _test_action(what: String) -> void:
	if _state != State.FIGHT:
		return
	if what == "land":
		_fishing.fish_pos_m = 0.5
		_fishing.stamina = 0.0
		_fishing._finish(FishingController.State.LANDED)
	else:
		_fight_view.surface(what)


## Bait and hook choice. Only while not fishing: you change tackle with the line in.
func _open_tackle_panel() -> void:
	if _state != State.AIM:
		_flash("Reel in first to change bait or hook")
		return
	if _tackle_panel != null and is_instance_valid(_tackle_panel):
		_tackle_panel.queue_free()
	var panel := PanelContainer.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	panel.offset_left = -470.0
	panel.offset_right = 470.0
	panel.offset_top = -340.0
	panel.offset_bottom = 340.0
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.02, 0.10, 0.18, 0.95)
	style.set_corner_radius_all(18)
	style.set_content_margin_all(18)
	panel.add_theme_stylebox_override("panel", style)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	panel.add_child(box)
	_plain_label(box, 26, Color(1.0, 0.92, 0.6)).text = "Bait"
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	box.add_child(grid)
	for id: String in Tackle.BAIT_ORDER:
		var label := Tackle.bait_name(id)
		if GameSession.stock(id) >= 0:
			label = "%s  x%d" % [String(Tackle.BAITS[id]["name"]), GameSession.stock(id)]
		var b := _tackle_button(label, id == GameSession.bait_id, Vector2(290.0, 50.0))
		b.pressed.connect(func() -> void:
			GameSession.set_tackle(id, GameSession.hook_id)
			_open_tackle_panel())
		grid.add_child(b)
	_plain_label(box, 26, Color(1.0, 0.92, 0.6)).text = "Rig"
	var rig_row := HBoxContainer.new()
	rig_row.add_theme_constant_override("separation", 8)
	box.add_child(rig_row)
	for mode: String in ["float", "bottom"]:
		var rb := _tackle_button("FLOAT (samandira)" if mode == "float" else "BOTTOM (dip, bell)", mode == GameSession.rig_mode, Vector2(290.0, 50.0))
		rb.pressed.connect(func() -> void:
			GameSession.rig_mode = mode
			GameSession.save()
			_open_tackle_panel())
		rig_row.add_child(rb)
	_plain_label(box, 26, Color(1.0, 0.92, 0.6)).text = "Hook size"
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	box.add_child(row)
	for hid: String in Tackle.HOOK_ORDER:
		var hb := _tackle_button(Tackle.hook_name(hid), hid == GameSession.hook_id, Vector2(140.0, 50.0))
		hb.pressed.connect(func() -> void:
			GameSession.set_tackle(GameSession.bait_id, hid)
			_open_tackle_panel())
		row.add_child(hb)
	var hint := _plain_label(box, 16, Color(0.8, 0.9, 1.0))
	hint.text = "Bottom rig: a sinker lays the bait on the bottom for bream, whiting, scorpionfish and turbot; watch the rod tip and listen for the bell. Float rig: set the depth with DEEP/SHAL. Bream like mussel and worm, mullet bread, bluefish and seabass live bait or a spoon, horse mackerel the çapari, squid and cuttlefish a squid jig at night. Small hooks for small mouths; a big hook scares them off. A small hook can open up on a big fish. Lures catch only while you reel. Soft baits get picked off by small fish."
	var done := _tackle_button("DONE", false, Vector2(200.0, 56.0))
	done.pressed.connect(func() -> void: panel.queue_free())
	box.add_child(done)
	_tackle_panel = panel
	_hud_root.add_child(panel)


func _tackle_button(text: String, selected: bool, min_size: Vector2) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = min_size
	b.add_theme_font_size_override("font_size", 18)
	b.focus_mode = Control.FOCUS_NONE
	if selected:
		b.add_theme_color_override("font_color", Color(1.0, 0.85, 0.3))
		b.text = "> " + text
	return b


## First-visit coach card: the loop in five lines. Shown once, saved when dismissed.
func _show_tutorial() -> void:
	var card := PanelContainer.new()
	card.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	card.offset_left = -330.0
	card.offset_right = 330.0
	card.offset_top = -220.0
	card.offset_bottom = 160.0
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.02, 0.10, 0.18, 0.94)
	style.set_corner_radius_all(18)
	style.set_content_margin_all(20)
	card.add_theme_stylebox_override("panel", style)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	card.add_child(box)
	_plain_label(box, 30, Color(1.0, 0.92, 0.6)).text = "How to fish"
	var lines := [
		"1. Walk to the water's edge or out on the pier with the stick.",
		"2. Hold CAST, aim with the stick, release to throw. Farther is deeper.",
		"3. Set the bait depth with DEEP / SHAL. Fish feed at different depths and hours.",
		"4. Wait. A nibble is not a bite. When the float dives (BITE!), tap REEL.",
		"5. In the fight, hold REEL to pull, ease off when the line is red, use CLUTCH+/-.",
	]
	for ln: String in lines:
		_plain_label(box, 19, Color(0.9, 0.96, 1.0)).text = ln
	var ok := Button.new()
	ok.text = "GOT IT"
	ok.custom_minimum_size = Vector2(260.0, 60.0)
	ok.add_theme_font_size_override("font_size", 24)
	ok.focus_mode = Control.FOCUS_NONE
	ok.pressed.connect(func() -> void:
		GameSession.set_tutorial_done()
		card.queue_free())
	box.add_child(ok)
	_hud_root.add_child(card)


func _plain_label(parent: Control, size: int, color: Color) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(l)
	return l


func _on_snapped(_id: String) -> void:
	_buzz(300)
	_amb.play("snap", 1.0)
	_result_label.text = "Line snapped!"
	_set_status("Too much tension. Ease off the reel on the runs")
	_end_fight()


func _on_escaped(_id: String) -> void:
	_result_label.text = "It got away"
	var why := _escape_reason if _escape_reason != "" else _fishing.escape_reason
	_set_status(why if why != "" else "The line went slack for too long")
	_escape_reason = ""
	_end_fight()


# ---------------------------------------------------------------- per-frame visuals
func _process(delta: float) -> void:
	_kick = maxf(0.0, _kick - delta * 0.6)
	_fps_t += delta
	if _fps_t >= 0.5:
		_fps_t = 0.0
		_build_label.text = "%s   %d fps" % [GameSession.BUILD, Engine.get_frames_per_second()]
	if _state == State.WAIT or _state == State.BITE:
		_rod_bend_target = clampf(_float_x, 0.0, 1.5) * 0.25
	elif _state != State.FIGHT:
		_rod_bend_target = 0.0
	_rod_bend = lerpf(_rod_bend, _rod_bend_target, 1.0 - exp(-10.0 * delta))
	_update_talk_button()
	_tick_tourney(delta)

	for r in _ripples:
		r["age"] = float(r["age"]) + delta
	_ripples.assign(_ripples.filter(func(r: Dictionary) -> bool: return float(r["age"]) < 1.6))

	_world.wind = _wind
	_world.view_x = _cam.position.x
	_amb.gull_rate = 0.02 + 0.08 * _world.daylight
	_update_soundscape(delta)
	var cranking := Input.is_action_pressed(&"reel_in") and (_state == State.FIGHT or _state == State.WAIT)
	_amb.set_loop("reel", cranking, 0.45 + 0.4 * clampf(_tension_ratio, 0.0, 1.0) if _state == State.FIGHT else 0.35)
	_tint.color = _world.tint(_region_tint())
	_fight_view.tint = _tint.color
	_fight_view.daylight = _world.daylight
	_water.set_daylight(_world.daylight)
	_clock_label.text = "%s %s   |   %s   |   %s" % [Season.month_name(), _world.clock_text(), _weather.label(), Moon.phase_name()]
	var probe := _bobber_pos if (_state == State.WAIT or _state == State.BITE) else (_pred_landing if _state == State.CHARGE else _hand + _facing * 60.0)
	var water := _water_depth(probe)
	_depth_label.text = ("Bottom rig" if _bottom_rig() else "Float %.1f m" % _bait_depth) + "  |  Water %s  |  Clutch %.0f N  |  %s, hook %s" % [("%.1f m" % water) if water > 0.0 else "-",
		_fishing.drag_setting_n, String(Tackle.BAITS[GameSession.bait_id]["name"]), Tackle.hook_name(GameSession.hook_id)] + "  |  Current %.1f m/s" % (_current.length() / PX_PER_M)
	_toast_t = maxf(0.0, _toast_t - delta)
	_toast_label.text = _toast_text if _toast_t > 0.0 else ""

	_power_bar.visible = _state == State.CHARGE
	_power_bar.value = _power
	if _state == State.FIGHT:
		_fight_feedback()
		_tension_bar.value = clampf(_tension_ratio, 0.0, 1.0)
		_stamina_bar.value = _fishing.stamina
		_tension_fill.bg_color = Color(0.3, 0.85, 0.4).lerp(Color(1.0, 0.25, 0.2), clampf((_tension_ratio - 0.4) / 0.5, 0.0, 1.0))
		_tension_label.text = "Line %.0f / %.0f N    Clutch %.0f N    Fish %.0f m away" % [_fishing.tension_n, _fishing.line_break_force_n, _fishing.drag_setting_n, _fishing.fish_pos_m]

	_update_camera(delta)
	if not _pov_on:
		queue_redraw()


## Coaching line during the fight.
func _fight_feedback() -> void:
	var hint := "FISH ON!  Hold REEL.  Ease off when the line is tight"
	if _tension_ratio > 0.85:
		hint = "TOO TIGHT!  Let go of REEL or lower the clutch (DRAG-)"
	elif _fishing.slack_time > 0.8:
		hint = "Slack line!  Reel in or the hook falls out"
	elif _fishing.stamina < 0.25:
		hint = "The fish is tired.  Bring it in"
	if hint != _fight_hint:
		_fight_hint = hint
		_set_status(hint)


## Wide on the town while aiming, follows the throw, closes in on the float, and frames angler
## and fish together in the fight, getting closer as the fish comes in.
func _update_camera(delta: float) -> void:
	var target_pos := _hand + Vector2(0.0, -60.0)
	var target_zoom := 1.15                    # close in, like a farm-sim view, not a map
	match _state:
		State.CHARGE:
			target_pos = _hand.lerp(_pred_landing, 0.45)
		State.FLY:
			target_pos = _hand.lerp(_bobber_pos, 0.6)
			target_zoom = 1.0
		State.WAIT, State.BITE:
			target_pos = _hand.lerp(_bobber_pos, 0.6)
			target_zoom = 1.25
		State.FIGHT:
			if _fight_agent != null:
				var fp := _fight_agent.pos
				target_pos = (_hand + fp) * 0.5
				var span := _hand.distance_to(fp) + 260.0
				target_zoom = clampf(get_viewport_rect().size.y * 0.9 / span, 0.7, 1.9)
		State.RESULT:
			target_zoom = 1.0
	_cam.position = _cam.position.lerp(target_pos, 1.0 - exp(-3.0 * delta))
	_cam.zoom = Vector2.ONE * lerpf(_cam.zoom.x, target_zoom * (1.0 + _kick), 1.0 - exp(-2.5 * delta))
	_cam.offset = Vector2(_rng.randf_range(-1.0, 1.0), _rng.randf_range(-1.0, 1.0)) * _shake * 6.0


# ---------------------------------------------------------------- drawing
func _draw() -> void:
	_draw_sparkles()
	_draw_shore()
	if _has_pier:
		_draw_pier()
	_draw_crowd()
	_draw_boats()
	_draw_ripples()
	_draw_line_and_float()
	_draw_particles()
	_draw_lamp()
	_draw_angler()
	_draw_tip()


## A timber pier out over the water: planks, posts and a rail on each side.
func _draw_pier() -> void:
	var r := _pier_rect()
	draw_rect(Rect2(r.position + Vector2(8.0, 10.0), r.size), Color(0.0, 0.05, 0.1, 0.25))
	draw_rect(r, Color(0.56, 0.41, 0.27))
	var y := r.position.y
	while y < r.end.y:
		draw_line(Vector2(r.position.x, y), Vector2(r.end.x, y), Color(0.42, 0.30, 0.19), 2.0)
		y += 16.0
	y = r.position.y + 6.0
	while y < -10.0:
		for px in [r.position.x - 3.0, r.end.x + 3.0]:
			draw_circle(Vector2(px, y), 6.0, Color(0.30, 0.21, 0.13))
		y += 60.0
	draw_line(Vector2(r.position.x + 3.0, r.position.y), Vector2(r.position.x + 3.0, 0.0), Color(0.70, 0.55, 0.38), 3.0)
	draw_line(Vector2(r.end.x - 3.0, r.position.y), Vector2(r.end.x - 3.0, 0.0), Color(0.70, 0.55, 0.38), 3.0)


## Speech bubble over the angler you are standing next to.
func _draw_tip() -> void:
	if _tip_text == "" or _state != State.AIM:
		return
	var font := ThemeDB.fallback_font
	var width := 300.0
	var box := Rect2(_tip_pos + Vector2(-width * 0.5, -150.0), Vector2(width, 96.0))
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(1.0, 0.98, 0.92, 0.95)
	sb.set_corner_radius_all(14)
	sb.draw(get_canvas_item(), box)
	draw_colored_polygon(PackedVector2Array([box.position + Vector2(width * 0.5 - 10.0, box.size.y),
		box.position + Vector2(width * 0.5 + 10.0, box.size.y), _tip_pos + Vector2(0.0, -40.0)]), Color(1.0, 0.98, 0.92, 0.95))
	draw_multiline_string(font, box.position + Vector2(14.0, 26.0), _tip_text, HORIZONTAL_ALIGNMENT_LEFT, width - 28.0, 17, 4, Color(0.10, 0.14, 0.20))


## Half the width of world the camera shows, plus a margin: things farther from the camera's x than
## this are off screen and are not drawn (the world is 8000 px wide, the screen about 1200).
func _view_half() -> float:
	return get_viewport_rect().size.x * 0.5 / maxf(_cam.zoom.x, 0.1) + 100.0


func _draw_sparkles() -> void:
	var day := _world.daylight
	var cx := _cam.position.x
	var half := _view_half()
	for s in _sparkles:
		if absf(s.x - cx) > half:
			continue
		var tw := sin(_time * 2.6 + s.z)
		if tw > 0.55:
			var k := (tw - 0.55) / 0.45 * (0.35 + 0.65 * day)
			var p := Vector2(s.x + sin(_time * 0.3 + s.z) * 20.0, s.y)
			var c := Color(1.0, 1.0, 1.0, 0.8 * k)
			draw_line(p - Vector2(6.0 * k, 0.0), p + Vector2(6.0 * k, 0.0), c, 2.0)
			draw_line(p - Vector2(0.0, 6.0 * k), p + Vector2(0.0, 6.0 * k), c, 2.0)


func _draw_shore() -> void:
	var kind: String = _spot["kind"]
	var base: Color = _spot["shore_color"]
	var shallow: Color = _spot["water"]["shallow"]
	var w := HALF_WIDTH
	var cx := _cam.position.x
	var half := _view_half()
	for i in 7:
		var a := 0.30 - float(i) * 0.04
		draw_rect(Rect2(-w, -float(i + 1) * 20.0, w * 2.0, 20.0), Color(shallow.r, shallow.g, shallow.b, a))

	if kind == "bridge":
		draw_rect(Rect2(-w, 0.0, w * 2.0, 120.0), base)
		draw_rect(Rect2(-w, 0.0, w * 2.0, 10.0), base.darkened(0.35))
		draw_rect(Rect2(-w, 112.0, w * 2.0, 8.0), base.lightened(0.18))
		draw_rect(Rect2(-w, 40.0, w * 2.0, 4.0), base.lightened(0.08))
		draw_rect(Rect2(-w, 80.0, w * 2.0, 4.0), base.lightened(0.08))
		var lx := -HALF_WIDTH + 200.0
		while lx <= HALF_WIDTH - 200.0:
			if absf(lx - cx) < half:
				draw_circle(Vector2(lx, 62.0), 7.0, Color(1.0, 0.95, 0.7))
			lx += 240.0
	elif kind == "harbor":
		draw_rect(Rect2(-w, 0.0, w * 2.0, 150.0), base)
		draw_rect(Rect2(-w, 0.0, w * 2.0, 8.0), base.darkened(0.4))
		var bx := -HALF_WIDTH + 200.0
		while bx <= HALF_WIDTH - 200.0:
			if absf(bx - cx) > half:
				bx += 160.0
				continue
			draw_circle(Vector2(bx, 26.0), 9.0, base.darkened(0.5))
			draw_rect(Rect2(bx + 40.0, 60.0, 34.0, 26.0), Color(0.45, 0.32, 0.20))
			draw_rect(Rect2(bx + 40.0, 60.0, 34.0, 26.0), Color(0.30, 0.20, 0.12), false, 2.0)
			bx += 160.0
		for side in [-1.0, 1.0, -3.0, 3.0]:
			_draw_moored_boat(Vector2(430.0 * side, -58.0))
	elif kind == "beach":
		var poly := _edge_pts.duplicate()
		poly.append(Vector2(w, 300.0))
		poly.append(Vector2(-w, 300.0))
		draw_colored_polygon(poly, base)
		var wet := PackedVector2Array()
		for p in _edge_pts:
			wet.append(p + Vector2(0.0, 12.0))
		draw_polyline(wet, base.darkened(0.14), 16.0)
		for pb in _pebbles:
			if absf(pb.x - cx) < half:
				draw_circle(Vector2(pb.x, pb.y), pb.z, base.darkened(0.25))
		_draw_foam()
	else:
		draw_rect(Rect2(-w, 40.0, w * 2.0, 260.0), base.darkened(0.2))
		for rock: Dictionary in _rocks:
			var rc0: Vector2 = rock["c"]
			if absf(rc0.x - cx) > half + float(rock["r"]):
				continue
			var pts: PackedVector2Array = rock["pts"]
			var col: Color = rock["color"]
			draw_colored_polygon(pts, col)
			var edge := pts.duplicate()
			edge.append(pts[0])
			draw_polyline(edge, col.lightened(0.18), 2.0)
			var rc: Vector2 = rock["c"]
			if rc.y < 25.0:
				var rr: float = rock["r"]
				var swell := sin(_time * 2.0 + rc.x * 0.05) * 3.0
				draw_arc(rc, rr * 0.95 + 6.0 + swell, PI, TAU, 20, Color(1.0, 1.0, 1.0, 0.35), 2.5)
		_draw_foam()


func _draw_crowd() -> void:
	for ci in _crowd.size():
		var a: Dictionary = _crowd[ci]
		var x := float(a["x"])
		if absf(x - _cam.position.x) > 1500.0:
			continue
		if ci == _local_idx:
			_draw_local_tag(Vector2(x, float(a["y"]) - 46.0))
		var y := float(a["y"])
		var hold := _neighbor_hold(a)
		var tip := _neighbor_tip(a)
		var end := _neighbor_float(a)
		var st := String(a["state"])
		var look := {"shirt": a["shirt"], "hat": Color(0.80, 0.75, 0.60) if bool(a["hat"]) else null}
		Figure.draw_person(self, Vector2(x, y + 18.0), Vector2.UP, 0.0, false, look, 1.3, hold)
		# rod: bends toward the fish in a fight
		var bend := 18.0 if st == "fight" else 4.0
		var ctrl := hold.lerp(tip, 0.5) + (tip - hold).orthogonal().normalized() * bend
		var rod := PackedVector2Array()
		for i in 7:
			var k := float(i) / 6.0
			rod.append(hold.lerp(ctrl, k).lerp(ctrl.lerp(tip, k), k))
		draw_polyline(rod, Color(0.18, 0.13, 0.09), 2.5)
		if st == "land" and String(a["sp"]) != "":
			# the catch swings on the line under the tip, flapping
			var fish_at := tip + Vector2(sin(_time * 5.0) * 4.0, 30.0)
			draw_line(tip, fish_at, Color(1.0, 1.0, 1.0, 0.5), 1.0)
			RealFish.draw(self, String(a["sp"]), fish_at + Vector2(0.0, 10.0), clampf(18.0 + float(a["kg"]) * 6.0, 18.0, 46.0),
				PI * 0.5 + sin(_time * 9.0) * 0.4, 1.0, _time * 18.0, 0.8, _world.daylight, 1.0)
		else:
			draw_line(tip, end, Color(1.0, 1.0, 1.0, 0.45 if st == "fight" else 0.3), 1.0)
			if st != "fight":
				draw_circle(end, 3.0, Color(0.95, 0.3, 0.2, 0.9))
			else:
				draw_arc(end, 6.0 + sin(_time * 6.0) * 2.0, 0.0, TAU, 10, Color(1.0, 1.0, 1.0, 0.6), 1.5)


## Name over the local's head; a yellow "!" when the fish they asked for are ready to hand over.
func _draw_local_tag(at: Vector2) -> void:
	var p := Locals.person(GameSession.spot_id)
	var font := ThemeDB.fallback_font
	var nm := String(p["name"])
	var w := font.get_string_size(nm, HORIZONTAL_ALIGNMENT_LEFT, -1, 16).x
	draw_rect(Rect2(at + Vector2(-w * 0.5 - 6.0, -16.0), Vector2(w + 12.0, 22.0)), Color(0.0, 0.0, 0.0, 0.45))
	draw_string(font, at + Vector2(-w * 0.5, 0.0), nm, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(1.0, 0.95, 0.8))
	if Locals.can_turn_in(GameSession.spot_id):
		var bob := sin(_time * 4.0) * 3.0
		draw_string(font, at + Vector2(-5.0, -22.0 + bob), "!", HORIZONTAL_ALIGNMENT_LEFT, -1, 26, Color(1.0, 0.85, 0.2))


func _draw_foam() -> void:
	for layer in 2:
		var pts := PackedVector2Array()
		var x := _cam.position.x - 1500.0
		while x <= _cam.position.x + 1500.0:
			pts.append(Vector2(x, -4.0 - float(layer) * 9.0 + sin(x * 0.02 + _time * 1.4 + float(layer)) * 5.0))
			x += 50.0
		draw_polyline(pts, Color(1.0, 1.0, 1.0, 0.55 - float(layer) * 0.2), 3.0)


func _draw_moored_boat(pos: Vector2) -> void:
	var bob := sin(_time * 1.3 + pos.x) * 3.0
	var p := pos + Vector2(0.0, bob)
	draw_colored_polygon(PackedVector2Array([p + Vector2(-66, -8), p + Vector2(60, -12), p + Vector2(92, 4), p + Vector2(60, 20), p + Vector2(-66, 16)]), Color(0.0, 0.0, 0.0, 0.2))
	var hull := PackedVector2Array([p + Vector2(-70, -12), p + Vector2(55, -16), p + Vector2(86, 0), p + Vector2(55, 16), p + Vector2(-70, 12)])
	draw_colored_polygon(hull, Color(0.92, 0.92, 0.9))
	draw_colored_polygon(PackedVector2Array([p + Vector2(-40, -8), p + Vector2(20, -9), p + Vector2(20, 9), p + Vector2(-40, 8)]), Color(0.2, 0.45, 0.7))


func _draw_fish_shape(pos: Vector2, heading: Vector2, length: float, color: Color) -> void:
	var f := heading.normalized()
	var s := f.orthogonal()
	var wag := sin(_time * 9.0) * length * 0.12
	draw_colored_polygon(PackedVector2Array([
		pos + f * length * 0.5,
		pos + f * length * 0.1 + s * length * 0.17,
		pos - f * length * 0.42 + s * wag * 0.5,
		pos + f * length * 0.1 - s * length * 0.17,
	]), color)
	draw_colored_polygon(PackedVector2Array([
		pos - f * length * 0.38 + s * wag * 0.5,
		pos - f * length * 0.64 + s * (wag + length * 0.16),
		pos - f * length * 0.64 + s * (wag - length * 0.16),
	]), color)


func _draw_shoals() -> void:
	for group in _shoals:
		for f in group:
			var p: Vector2 = f.pos
			var h: Vector2 = f.heading()
			_draw_fish_shape(p, h, float(f.data["len"]), Color(0.05, 0.18, 0.24, 0.35))


func _draw_boats() -> void:
	for b in _boats:
		var p: Vector2 = b.pos
		var f: Vector2 = b.heading()
		var s := f.orthogonal()
		var ferry: bool = b.data["ferry"]
		var l := 120.0 if ferry else 70.0
		var w := 30.0 if ferry else 18.0
		var hull := PackedVector2Array([p + f * l * 0.55, p + f * l * 0.25 + s * w, p - f * l * 0.45 + s * w, p - f * l * 0.45 - s * w, p + f * l * 0.25 - s * w])
		var shadow := PackedVector2Array()
		for q in hull:
			shadow.append(q + Vector2(8.0, 12.0))
		draw_colored_polygon(shadow, Color(0.0, 0.05, 0.1, 0.25))
		draw_colored_polygon(hull, Color(0.95, 0.95, 0.93))
		if ferry:
			draw_rect(Rect2(p - Vector2(30.0, 14.0), Vector2(60.0, 28.0)), Color(0.85, 0.85, 0.82))
			draw_circle(p - f * 10.0, 8.0, Color(0.85, 0.2, 0.15))
			draw_circle(p - f * 10.0, 5.0, Color(0.15, 0.15, 0.15))
		else:
			var col: Color = b.data["color"]
			draw_colored_polygon(PackedVector2Array([p + f * 8.0 + s * 9.0, p - f * 18.0 + s * 9.0, p - f * 18.0 - s * 9.0, p + f * 8.0 - s * 9.0]), col)
		draw_line(p - f * l * 0.45 + s * w * 0.6, p - f * (l * 0.45 + 50.0) + s * w * 1.6, Color(1.0, 1.0, 1.0, 0.35), 2.0)
		draw_line(p - f * l * 0.45 - s * w * 0.6, p - f * (l * 0.45 + 50.0) - s * w * 1.6, Color(1.0, 1.0, 1.0, 0.35), 2.0)


func _draw_fish() -> void:
	if _state == State.FIGHT and _fight_agent != null:
		var fp := _fight_agent.pos
		var length := 28.0 + sqrt(_weight_kg) * 16.0
		draw_circle(fp, length * 0.7, Color(1.0, 1.0, 1.0, 0.10 + 0.25 * _tension_ratio))
		_draw_fish_shape(fp, _fight_agent.heading(), length, Color(0.04, 0.16, 0.22, 0.85))
	elif _fish_agent != null:
		var alpha := 0.25 if _fish_mode == "leave" else 0.45
		_draw_fish_shape(_fish_agent.pos, _fish_agent.heading(), float(_fish_agent.data["len"]), Color(0.04, 0.16, 0.22, alpha))


func _draw_ripples() -> void:
	for r in _ripples:
		var age := float(r["age"])
		var k := age / 1.6
		var radius := 8.0 + age * (55.0 if bool(r["big"]) else 32.0)
		draw_arc(Vector2(r["pos"]), radius, 0.0, TAU, 32, Color(1.0, 1.0, 1.0, 0.7 * (1.0 - k)), 2.5)


func _draw_particles() -> void:
	for p in _particles:
		var pos: Vector2 = p.pos
		var z: float = p.z
		var size: float = p.size
		var col: Color = p.color
		var fade := 1.0 - clampf(float(p.age) / float(p.life), 0.0, 1.0)
		if z > 1.0:
			draw_circle(pos, size * 0.8, Color(0.0, 0.0, 0.0, 0.12 * fade))
		draw_circle(pos - Vector2(0.0, z), size, Color(col.r, col.g, col.b, col.a * fade))


func _draw_line_and_float() -> void:
	var tip := _rod_tip()
	var line_col := Color(1.0, 1.0, 1.0, 0.85)
	match _state:
		State.CHARGE:
			for i in _pred_path.size():
				if i % 3 == 0:
					draw_circle(_pred_path[i], 3.0, Color(1.0, 1.0, 1.0, 0.6))
			draw_arc(_pred_landing, 16.0 + sin(_time * 6.0) * 3.0, 0.0, TAU, 28, Color(1.0, 0.9, 0.4, 0.9), 3.0)
		State.FLY:
			draw_polyline(_rope.pts, line_col, 1.5)
			draw_circle(_bobber_pos + Vector2(5.0, 7.0), 6.0, Color(0.0, 0.0, 0.0, 0.25))
			_draw_float(_bobber_pos - Vector2(0.0, _b_z), 0.0)
		State.WAIT, State.BITE:
			draw_polyline(_rope.pts, line_col, 1.5)
			_draw_float(_bobber_pos, _float_x)
		State.FIGHT:
			draw_polyline(_rope.pts, line_col, 1.5 + _tension_ratio * 1.5)
		_:
			pass


## sink 0 = floating high, 1 = mostly under: the float drops, shrinks and fades as it goes down.
func _draw_float(pos: Vector2, sink: float) -> void:
	var s := clampf(sink, -0.3, 1.6)
	var under := clampf((s - 0.5) / 1.0, 0.0, 0.85)
	var p := pos + Vector2(0.0, s * 5.0)
	var radius := 8.0 * (1.0 - under * 0.5)
	draw_circle(p, radius, Color(0.95, 0.95, 0.95, 1.0 - under))
	draw_circle(p + Vector2(0.0, -3.0), radius * 0.75, Color(0.95, 0.25, 0.2, 1.0 - under))


## The rented kayık: a white and blue wooden rowing boat with oars that dip as you row.
func _draw_rowing_boat(dir: Vector2) -> void:
	var f := dir.normalized() if dir.length() > 0.1 else Vector2.UP
	var s := f.orthogonal()
	var c := _hand + Vector2(0.0, 30.0)
	var l := 95.0
	var w := 26.0
	var hull := PackedVector2Array([c + f * l * 0.55, c + f * l * 0.25 + s * w, c - f * l * 0.45 + s * w * 0.8,
		c - f * l * 0.5, c - f * l * 0.45 - s * w * 0.8, c + f * l * 0.25 - s * w])
	var shadow := PackedVector2Array()
	for q in hull:
		shadow.append(q + Vector2(6.0, 10.0))
	draw_colored_polygon(shadow, Color(0.0, 0.05, 0.1, 0.25))
	draw_colored_polygon(hull, Color(0.93, 0.93, 0.90))
	var inner := PackedVector2Array()
	for q in hull:
		inner.append(c + (q - c) * 0.82)
	draw_colored_polygon(inner, Color(0.55, 0.38, 0.22))
	draw_polyline(hull + PackedVector2Array([hull[0]]), Color(0.15, 0.35, 0.65), 4.0)
	for k: float in [-0.15, 0.2]:
		draw_line(c + f * l * k - s * w * 0.8, c + f * l * k + s * w * 0.8, Color(0.42, 0.29, 0.17), 5.0)
	var dip := sin(_walk_phase) * 10.0 if _moving else 0.0
	for side: float in [-1.0, 1.0]:
		var lock := c + s * w * side * 0.9 + f * 6.0
		draw_line(lock, lock + s * side * 55.0 - f * dip, Color(0.50, 0.36, 0.22), 3.0)
	# wake while moving
	if _boat_vel.length() > 8.0:
		var back := c - _boat_vel.normalized() * l * 0.5
		draw_line(back, back - _boat_vel.normalized() * 50.0 + s * 18.0, Color(1, 1, 1, 0.4), 2.0)
		draw_line(back, back - _boat_vel.normalized() * 50.0 - s * 18.0, Color(1, 1, 1, 0.4), 2.0)


## At night the angler carries a lamp: a warm pool of light that flickers (two out-of-phase
## oscillators plus Perlin noise). On the pier it also draws baitfish, see LAMP_PIER_BONUS in _activity().
func _draw_lamp() -> void:
	var night := 1.0 - _world.daylight
	if night < 0.05:
		return
	var flicker := 1.0 + 0.04 * sin(_time * 9.0) + 0.03 * sin(_time * 5.3 + 1.0) + 0.05 * _lamp_noise.get_noise_1d(_time * 3.0)
	for i in 6:
		var k := float(i) / 5.0
		var rad := (150.0 - 110.0 * k) * flicker
		draw_circle(_hand + Vector2(0.0, 10.0), rad, Color(1.0, 0.82, 0.45, 0.05 * night))


func _draw_angler() -> void:
	var d := _aim_dir()
	# Three-quarter view: the angler stands with the rod hand at chest height (see Figure).
	var look_dir := _facing if _state == State.AIM else d
	if _boat_mode:
		_draw_rowing_boat(look_dir)
	# Feet sit behind and below the rod hand, so both hands grip the rod in front of the chest.
	var feet := _hand - look_dir.normalized() * 10.0 + Vector2(0.0, 40.0)
	Figure.draw_person(self, feet, look_dir, _walk_phase, _moving and _state == State.AIM, ANGLER_LOOK, 1.5, _hand)
	var ctrl := _hand + d * ROD_LEN * 0.55 + d.orthogonal() * _rod_bend * ROD_BEND_PX * 0.35
	var rod := PackedVector2Array()
	var tip := _rod_tip()
	for i in 11:
		var t := float(i) / 10.0
		rod.append(_hand.lerp(ctrl, t).lerp(ctrl.lerp(tip, t), t))
	draw_polyline(rod, Color(0.20, 0.13, 0.08), 5.0)
	draw_polyline(rod, Color(0.55, 0.40, 0.25), 2.0)
