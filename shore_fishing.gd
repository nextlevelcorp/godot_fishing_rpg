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
const WALK_SPEED := 150.0          ## px/s, about 1.5 m/s
const PIER_LEN := 420.0            ## the pier reaches 42 m out
const PIER_HALF := 26.0
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
var _fight_view: FightView
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
	InputDefaults.ensure_all()
	GameSession.load_once()
	if FishingSpots.get_spot(GameSession.spot_id).is_empty():
		GameSession.spot_id = "galata_bridge"       # opened directly, not from the map
	_spot = FishingSpots.get_spot(GameSession.spot_id)
	_has_pier = _spot["kind"] != "bridge"
	_pier_x = 900.0 if hash(GameSession.spot_id) % 2 == 0 else -900.0
	_build_walkable()
	_wind = Vector2(_rng.randf_range(-60.0, 60.0), _rng.randf_range(-15.0, 15.0))
	_current = Vector2(_rng.randf_range(-14.0, 14.0), _rng.randf_range(-4.0, 4.0))
	_cast_seen = int(TouchControls.presses.get(&"cast", 0))
	_reel_seen = int(TouchControls.presses.get(&"reel_in", 0))

	_cam = Camera2D.new()
	_cam.position = Vector2(0.0, 40.0)
	_cam.zoom = Vector2.ONE * 0.72
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
	_world.z_index = 1
	add_child(_world)

	_fishing = FishingController.new()
	_fishing.name = "FishingController"
	add_child(_fishing)
	_fishing.apply_rig(BiomeDB.get_rig(GameSession.rig_id))
	_fishing.reel_speed_m_s = 3.2             # shore spinning reel: faster retrieve than the boat rig
	_fishing.fish_caught.connect(_on_caught)
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
	_fight_view = FightView.new()
	_fight_view.fishing = _fishing
	_fight_view.spot = _spot
	add_child(_fight_view)
	_build_vignette()
	_build_hud()
	var touch := TouchControls.new()
	touch.enabled_actions.assign([&"cast", &"reel_in", &"drag_up", &"drag_down", &"bait_deeper", &"bait_shallower"])
	touch.joystick = true
	add_child(touch)
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
	var gap := Vector2(60.0, 130.0) if kind == "bridge" else Vector2(260.0, 520.0)
	var cx := -HALF_WIDTH + 200.0
	while cx < HALF_WIDTH - 200.0:
		if absf(cx) > 140.0 and absf(cx - _pier_x) > 70.0:
			_crowd.append({"x": cx, "y": crowd_y, "len": rng.randf_range(90.0, 260.0), "phase": rng.randf() * TAU})
		cx += rng.randf_range(gap.x, gap.y)
	for i in 140:
		_sparkles.append(Vector3(rng.randf_range(-HALF_WIDTH, HALF_WIDTH), rng.randf_range(-1100.0, -40.0), rng.randf() * TAU))


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
	map_btn.pressed.connect(func() -> void: get_tree().change_scene_to_file(MAP_SCENE))
	ui.add_child(map_btn)

	_power_bar = ProgressBar.new()
	_power_bar.min_value = 0.0
	_power_bar.max_value = 1.0
	_power_bar.step = 0.001
	_power_bar.show_percentage = false
	_power_bar.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	_power_bar.offset_left = -260.0
	_power_bar.offset_right = 260.0
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
	match _state:
		State.AIM:
			_walk(delta)
			_adjust_bait_depth(delta)
			if _cast_edge:
				if _can_cast():
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
				_set_status("Walk with the stick. At the water's edge, hold CAST to throw")
	_update_float(delta)
	_update_fish_agent(delta)
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
	_walk_phase += step.length() * 0.12
	_check_tip()


func _adjust_bait_depth(delta: float) -> void:
	var ax := Input.get_axis(&"bait_shallower", &"bait_deeper")
	if absf(ax) > 0.0:
		_bait_depth = clampf(_bait_depth + ax * 3.0 * delta, 0.5, 30.0)


func _pier_rect() -> Rect2:
	return Rect2(_pier_x - PIER_HALF, -PIER_LEN, PIER_HALF * 2.0, PIER_LEN + 20.0)


func _on_pier() -> bool:
	return _has_pier and _hand.y < 0.0 and _pier_rect().has_point(_hand)


func _can_cast() -> bool:
	return _hand.y < 48.0 or _on_pier()


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
	return clampf(_bait_depth, 0.3, maxf(_water_depth(_bobber_pos) - 0.2, 0.3))


## How likely a species is to take the bait right now: rarity, depth match, feeding time.
func _species_weight(id: String) -> float:
	var sp := BiomeDB.get_species(id)
	var w := 1.0 / sqrt(float(sp["base_price"]))
	var dr: Vector2 = sp["depth_m"]
	var d := _eff_depth()
	var miss := maxf(dr.x - d, 0.0) + maxf(d - dr.y, 0.0)
	w *= exp(-miss / 2.5)
	w *= BiomeDB.activity_factor(id, _world.time_of_day)
	return w


## 1 = a normal amount of feeding at this depth and hour; lower means a longer wait.
func _activity() -> float:
	var base := 0.0
	var now := 0.0
	for id: String in _spot["species"]:
		base += 1.0 / sqrt(float(BiomeDB.get_species(id)["base_price"]))
		now += _species_weight(id)
	return clampf(now / maxf(base, 0.0001), 0.15, 2.0)


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
	_b_vel = _aim_dir() * lerpf(170.0, 560.0, _power)
	_b_z = ROD_TIP_HEIGHT
	_b_vz = lerpf(150.0, 330.0, _power)
	_fish_id = ""
	_state = State.FLY
	_set_status("")


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
	_set_status("%.0f m out, bait at %.1f m. Waiting...   (tap CAST to reel in)" % [_cast_dist_m, _eff_depth()])


func _tick_wait(delta: float) -> void:
	_adjust_bait_depth(delta)
	if _cast_edge:
		_retrieve("Reeled in")
		return
	_ripple_clock += delta
	if _ripple_clock > 1.9:
		_ripple_clock = 0.0
		_add_ripple(_bobber_pos)
	if _fish_id == "":
		_wait_t -= delta
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
		_amb.play("plop", 0.35)
		_add_ripple(_bobber_pos)
		if _fish_agent != null:
			_fish_agent.vel += (_bobber_pos - _fish_agent.pos).normalized() * 60.0
		_set_status("Nibble!  Wait for the real bite")
		var hz := maxf(float(_prof["noise_hz"]), 0.5)
		_event_t = _rng.randf_range(0.6, 1.4) * 2.5 / hz
	else:
		_state = State.BITE
		_fish_mode = "bite"
		_bite_t = float(_prof["bite_window_s"])
		_float_pull = 1.3
		_float_v += 10.0
		_buzz(90)
		_amb.play("plop", 0.9)
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
	_set_status(message + ".   Aim and throw again")


func _hook_fish() -> void:
	var species := BiomeDB.get_species(_fish_id)
	_weight_kg = BiomeDB.roll_weight_kg(_fish_id, _rng)
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
	_amb.play("splash", 1.0)
	_splash(_bobber_pos, 1.2)
	_show_fight_ui(true)
	_fight_view.begin(_fish_id, _weight_kg, _cast_dist_m)


## The FishingController decides how far out the fish is; the visible fish is an agent that
## arrives on that point and wanders sideways, so it zigzags like a real fish on the line.
func _tick_fight(delta: float) -> void:
	if _fight_agent == null:
		return
	var target := _rod_tip() + _aim_dir() * _fishing.fish_pos_m * PX_PER_M
	var f := _fight_agent
	f.apply_force(f.arrive(target, 80.0) * 2.0)
	f.apply_force(f.wander(delta, 40.0, 30.0, 6.0) * (0.3 + _fishing.stamina))
	f.update(delta)
	if _fishing._burst_mult > 1.0 and _rng.randf() < delta * 2.5:
		_splash(f.pos, 0.8)
		_buzz(25)
		_amb.play("splash", 0.5)


# ---------------------------------------------------------------- Nature of Code updates
## The float is a damped spring around its rest depth; nibbles kick it, a bite holds it under.
func _update_float(delta: float) -> void:
	if _state != State.WAIT and _state != State.BITE:
		return
	var rest := _float_pull + sin(_time * 1.7) * 0.08
	var r := Noc.spring_step(_float_x, _float_v, rest, 70.0, 7.0, delta)
	_float_x = r.x
	_float_v = r.y
	_bobber_pos += _current * delta * 0.25


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
	return Vector2(x + sin(_time * 0.4 + ph) * 14.0 + sin(ph) * 30.0, float(a["y"]) - 30.0 - float(a["len"]) + sin(_time * 1.7 + ph) * 2.0)


## Now and then another angler hooks something: a splash at their float and a sound, quieter
## the further away they are.
func _update_neighbors(delta: float) -> void:
	if _crowd.is_empty():
		return
	_neighbor_clock -= delta
	if _neighbor_clock > 0.0:
		return
	_neighbor_clock = _rng.randf_range(10.0, 22.0)
	var a: Dictionary = _crowd[_rng.randi() % _crowd.size()]
	var p := _neighbor_float(a)
	_splash(p, 0.6)
	_amb.play("splash", clampf(1.0 - absf(p.x) / 1400.0, 0.15, 0.6))


# ---------------------------------------------------------------- fight results
func _on_tension(_tension_n: float, ratio: float, bend: float) -> void:
	_tension_ratio = ratio
	_rod_bend_target = bend
	_shake = ratio * ratio


## keep_view: leave the side view up (the catch card is showing and fades out on its own).
func _end_fight(keep_view: bool = false) -> void:
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
	var value := int(round(float(sp["base_price"]) * pow(maxf(weight_kg, 0.05), 0.8)))
	var first := not GameSession.counts.has(id)
	var record := not first and weight_kg > float(GameSession.best_kg.get(id, 0.0))
	GameSession.record_catch(id, sp["name"], weight_kg, value)
	_update_coins()
	var badge := "NEW SPECIES!  " if first else ("NEW RECORD!  " if record else "")
	var lines := PackedStringArray(["%.2f kg" % weight_kg, "+%d coins" % value, String(sp["scientific"])])
	_fight_view.show_catch(badge + String(sp["name"]), lines)
	_result_label.text = ""
	_set_status("Nice one")
	_amb.play("splash", 0.7)
	_end_fight(true)


func _on_snapped(_id: String) -> void:
	_buzz(300)
	_amb.play("snap", 1.0)
	_result_label.text = "Line snapped!"
	_set_status("Too much tension. Ease off the reel on the runs")
	_end_fight()


func _on_escaped(_id: String) -> void:
	_result_label.text = "It got away"
	_set_status("The line went slack for too long")
	_end_fight()


# ---------------------------------------------------------------- per-frame visuals
func _process(delta: float) -> void:
	_kick = maxf(0.0, _kick - delta * 0.6)
	if _state == State.WAIT or _state == State.BITE:
		_rod_bend_target = clampf(_float_x, 0.0, 1.5) * 0.25
	elif _state != State.FIGHT:
		_rod_bend_target = 0.0
	_rod_bend = lerpf(_rod_bend, _rod_bend_target, 1.0 - exp(-10.0 * delta))

	for r in _ripples:
		r["age"] = float(r["age"]) + delta
	_ripples.assign(_ripples.filter(func(r: Dictionary) -> bool: return float(r["age"]) < 1.6))

	_world.wind = _wind
	_amb.gull_rate = 0.02 + 0.08 * _world.daylight
	if _state == State.FIGHT and Input.is_action_pressed(&"reel_in"):
		_reel_click -= delta
		if _reel_click <= 0.0:
			_reel_click = 0.06
			_amb.play("click", 0.5)
	_tint.color = _world.tint(_region_tint())
	_fight_view.tint = _tint.color
	_fight_view.daylight = _world.daylight
	_water.set_daylight(_world.daylight)
	_clock_label.text = _world.clock_text()
	var probe := _bobber_pos if (_state == State.WAIT or _state == State.BITE) else (_pred_landing if _state == State.CHARGE else _hand + _facing * 60.0)
	var water := _water_depth(probe)
	_depth_label.text = "Float depth %.1f m   |   Water %s" % [_bait_depth, ("%.1f m" % water) if water > 0.0 else "-"]

	_power_bar.visible = _state == State.CHARGE
	_power_bar.value = _power
	if _state == State.FIGHT:
		_fight_feedback()
		_tension_bar.value = clampf(_tension_ratio, 0.0, 1.0)
		_stamina_bar.value = _fishing.stamina
		_tension_fill.bg_color = Color(0.3, 0.85, 0.4).lerp(Color(1.0, 0.25, 0.2), clampf((_tension_ratio - 0.4) / 0.5, 0.0, 1.0))
		_tension_label.text = "Line %.0f / %.0f N    Clutch %.0f N    Fish %.0f m away" % [_fishing.tension_n, _fishing.line_break_force_n, _fishing.drag_setting_n, _fishing.fish_pos_m]

	_update_camera(delta)
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
	var target_pos := _hand + Vector2(0.0, -90.0)
	var target_zoom := 0.8
	match _state:
		State.CHARGE:
			target_pos = _hand.lerp(_pred_landing, 0.45)
		State.FLY:
			target_pos = _hand.lerp(_bobber_pos, 0.6)
			target_zoom = 0.9
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
	_draw_boats()
	_draw_ripples()
	_draw_line_and_float()
	_draw_particles()
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


func _draw_sparkles() -> void:
	var day := _world.daylight
	for s in _sparkles:
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
			draw_circle(Vector2(lx, 62.0), 7.0, Color(1.0, 0.95, 0.7))
			lx += 240.0
		_draw_crowd()
	elif kind == "harbor":
		draw_rect(Rect2(-w, 0.0, w * 2.0, 150.0), base)
		draw_rect(Rect2(-w, 0.0, w * 2.0, 8.0), base.darkened(0.4))
		var bx := -HALF_WIDTH + 200.0
		while bx <= HALF_WIDTH - 200.0:
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
			draw_circle(Vector2(pb.x, pb.y), pb.z, base.darkened(0.25))
		_draw_foam()
	else:
		draw_rect(Rect2(-w, 40.0, w * 2.0, 260.0), base.darkened(0.2))
		for rock: Dictionary in _rocks:
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
	for a in _crowd:
		var x := float(a["x"])
		var ph := float(a["phase"])
		var y := float(a["y"])
		var tip := Vector2(x + sin(ph) * 20.0, y - 50.0)
		var end := _neighbor_float(a)
		draw_line(Vector2(x, y), tip, Color(0.2, 0.13, 0.08), 3.0)
		draw_line(tip, end, Color(1.0, 1.0, 1.0, 0.35), 1.0)
		draw_circle(end, 3.0, Color(0.95, 0.3, 0.2, 0.9))
		draw_circle(Vector2(x + 4.0, y + 9.0), 12.0, Color(0.0, 0.0, 0.0, 0.2))
		draw_circle(Vector2(x, y + 6.0), 11.0, Color(0.25 + 0.3 * absf(sin(ph)), 0.25, 0.35))
		draw_circle(Vector2(x, y + 4.0), 6.0, Color(0.9, 0.75, 0.6))


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


func _draw_angler() -> void:
	var d := _aim_dir()
	draw_circle(_hand + Vector2(7.0, 14.0), 21.0, Color(0.0, 0.0, 0.0, 0.25))
	if _moving and _state == State.AIM:
		var side := _facing.orthogonal() * 8.0
		var swing := _facing * sin(_walk_phase) * 7.0
		draw_circle(_hand + Vector2(0.0, 12.0) + side + swing, 6.0, Color(0.18, 0.16, 0.14))
		draw_circle(_hand + Vector2(0.0, 12.0) - side - swing, 6.0, Color(0.18, 0.16, 0.14))
	draw_circle(_hand + Vector2(0.0, 10.0), 18.0, Color(0.15, 0.30, 0.55))
	draw_circle(_hand + Vector2(0.0, 10.0), 10.0, Color(0.93, 0.75, 0.6))
	draw_circle(_hand + Vector2(0.0, 7.0), 8.0, Color(0.9, 0.3, 0.2))
	var ctrl := _hand + d * ROD_LEN * 0.55 + d.orthogonal() * _rod_bend * ROD_BEND_PX * 0.35
	var rod := PackedVector2Array()
	var tip := _rod_tip()
	for i in 11:
		var t := float(i) / 10.0
		rod.append(_hand.lerp(ctrl, t).lerp(ctrl.lerp(tip, t), t))
	draw_polyline(rod, Color(0.20, 0.13, 0.08), 5.0)
	draw_polyline(rod, Color(0.55, 0.40, 0.25), 2.0)
