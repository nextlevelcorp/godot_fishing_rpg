## Shore fishing at a real spot picked on the Turkey map (see fishing_spots.gd).
##
## Flow:  AIM (steer < >) -> hold CAST to charge, release to throw -> WAIT for a fish
##        -> NIBBLES (light taps) -> BITE (short window: press REEL) -> FIGHT -> caught / lost.
##
## The camera starts wide so you see the coast, follows the bobber while you wait, and closes in as
## the fight goes on. The fight itself is FishingController (spring-mass line, clutch, fatigue).
## Everything is built in code so the .tscn is just this script on a Node2D.
##
## Controls: steer_left / steer_right  aim     cast  hold = power, release = throw, tap while waiting = reel in
##           reel_in  set the hook on a bite, then hold to reel     drag_up / drag_down  clutch (fight)
class_name ShoreFishing
extends Node2D

enum State { AIM, CHARGE, FLY, WAIT, BITE, FIGHT, RESULT }

const PX_PER_M := 10.0
const RIG_ID := "shore_spinning_rig"
const MIN_CAST_M := 8.0
const MAX_CAST_M := 70.0
const ROD_LEN := 90.0
const ROD_BEND_PX := 20.0
const HAND := Vector2(0.0, 46.0)
const HALF_WIDTH := 1800.0
const MAP_SCENE := "res://turkey_map.tscn"

var _rng := RandomNumberGenerator.new()
var _spot: Dictionary = {}
var _state := State.AIM
var _time := 0.0

var _aim := 0.0
var _power := 0.0
var _power_dir := 1.0
var _cast_dist_m := 0.0
var _fly_t := 0.0
var _bobber_start := Vector2.ZERO
var _bobber_target := Vector2.ZERO
var _bobber_pos := Vector2.ZERO
var _bobber_height := 0.0
var _dip := 0.0

var _wait_t := 0.0
var _fish_id := ""
var _prof: Dictionary = {}
var _nib_left := 0
var _event_t := 0.0
var _fish_time := 0.0
var _bite_t := 0.0
var _weight_kg := 0.0
var _result_t := 0.0

var _tension_ratio := 0.0
var _rod_bend := 0.0
var _rod_bend_target := 0.0
var _shake := 0.0

var _ripples: Array[Dictionary] = []
var _drops: Array[Dictionary] = []
var _ripple_clock := 0.0

var _rocks: Array[Dictionary] = []
var _edge_pts := PackedVector2Array()
var _crowd: Array[Dictionary] = []      # bridge: other anglers along the rail {x, len, phase}
var _pebbles: Array[Vector3] = []       # beach: x, y, radius
var _sparkles: Array[Vector3] = []      # sun glints on the water: x, y, phase
var _kick := 0.0                        # camera punch when the hook is set
var _fight_hint := ""

var _water: WaterSurface
var _cam: Camera2D
var _fishing: FishingController

var _status: Label
var _spot_label: Label
var _coins_label: Label
var _result_label: Label
var _tension_label: Label
var _power_bar: ProgressBar
var _tension_bar: ProgressBar
var _stamina_bar: ProgressBar
var _tension_fill: StyleBoxFlat


func _ready() -> void:
	_rng.randomize()
	InputDefaults.ensure_all()
	if FishingSpots.get_spot(GameSession.spot_id).is_empty():
		GameSession.spot_id = "galata_bridge"       # opened directly, not from the map
	_spot = FishingSpots.get_spot(GameSession.spot_id)

	_cam = Camera2D.new()
	_cam.position = Vector2(0.0, -190.0)
	_cam.zoom = Vector2.ONE * 0.85
	add_child(_cam)
	_cam.make_current()

	var tint := CanvasModulate.new()
	tint.color = _region_tint()
	add_child(tint)

	_water = WaterSurface.new()
	_water.camera = _cam
	add_child(_water)
	_apply_water_palette()

	_fishing = FishingController.new()
	_fishing.name = "FishingController"
	add_child(_fishing)
	_fishing.apply_rig(BiomeDB.get_rig(RIG_ID))
	_fishing.reel_speed_m_s = 3.2             # shore spinning reel: faster retrieve than the boat rig
	_fishing.fish_caught.connect(_on_caught)
	_fishing.line_snapped.connect(_on_snapped)
	_fishing.fish_escaped.connect(_on_escaped)
	_fishing.tension_updated.connect(_on_tension)

	_build_land()
	_build_hud()
	var touch := TouchControls.new()
	touch.enabled_actions.assign([&"steer_left", &"steer_right", &"cast", &"reel_in", &"drag_up", &"drag_down"])
	add_child(touch)
	_set_status("Aim with < >, then hold CAST to power up the throw")


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
			_pebbles.append(Vector3(rng.randf_range(-1400.0, 1400.0), rng.randf_range(30.0, 420.0), rng.randf_range(1.5, 4.0)))
	elif kind == "bridge":
		# The Galata survey counted about 200 anglers a day on the bridge: line the rail with them.
		var cx := -1300.0
		while cx < 1300.0:
			if absf(cx) > 110.0:
				_crowd.append({"x": cx, "len": rng.randf_range(90.0, 260.0), "phase": rng.randf() * TAU})
			cx += rng.randf_range(60.0, 130.0)
	for i in 46:
		_sparkles.append(Vector3(rng.randf_range(-1300.0, 1300.0), rng.randf_range(-1100.0, -40.0), rng.randf() * TAU))


func _build_hud() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 5
	add_child(layer)
	var ui := Control.new()
	ui.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(ui)

	_spot_label = _make_label(ui, 22, Color.WHITE)
	_spot_label.position = Vector2(20.0, 12.0)
	_spot_label.text = "%s  -  %s" % [_spot["name"], _spot["region"]]

	_status = _make_label(ui, 30, Color.WHITE)
	_status.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	_status.offset_top = 52.0
	_status.offset_bottom = 100.0
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

	_result_label = _make_label(ui, 42, Color(1.0, 0.95, 0.6))
	_result_label.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	_result_label.offset_top = 190.0
	_result_label.offset_bottom = 300.0
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

	_tension_bar = _make_bar(ui, 112.0, 138.0)
	_tension_fill = StyleBoxFlat.new()
	_tension_fill.bg_color = Color(0.3, 0.85, 0.4)
	_tension_bar.add_theme_stylebox_override("fill", _tension_fill)
	_stamina_bar = _make_bar(ui, 146.0, 160.0)
	_tension_label = _make_label(ui, 18, Color.WHITE)
	_tension_label.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	_tension_label.offset_top = 164.0
	_tension_label.offset_bottom = 190.0
	_tension_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_tension_bar.visible = false
	_stamina_bar.visible = false
	_tension_label.visible = false


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


# ---------------------------------------------------------------- helpers
func _aim_dir() -> Vector2:
	return Vector2(sin(_aim), -cos(_aim))


func _rod_tip() -> Vector2:
	var d := _aim_dir()
	return HAND + d * ROD_LEN + d.orthogonal() * _rod_bend * ROD_BEND_PX


func _fish_pos() -> Vector2:
	var d := _aim_dir()
	var along := _rod_tip() + d * _fishing.fish_pos_m * PX_PER_M
	var side := d.orthogonal() * sin(_time * 2.3) * (6.0 + 30.0 * _fishing.stamina)
	return along + side


func _set_status(text: String) -> void:
	_status.text = text


## Short vibration on phones that support it (Android browsers). iOS Safari ignores it.
func _buzz(ms: int) -> void:
	Input.vibrate_handheld(ms)


## Light colour grade per sea: grey-blue Black Sea, bright Aegean, warm Mediterranean.
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


func _splash(pos: Vector2) -> void:
	_add_ripple(pos, true)
	for i in 10:
		var a := _rng.randf() * TAU
		var v := Vector2(cos(a), sin(a)) * _rng.randf_range(40.0, 120.0)
		_drops.append({"pos": pos, "vel": v, "age": 0.0})


func _roll_species() -> String:
	var ids: Array = _spot["species"]
	var weights: Array[float] = []
	var total := 0.0
	for id: String in ids:
		var w := 1.0 / sqrt(float(BiomeDB.get_species(id)["base_price"]))
		weights.append(w)
		total += w
	var pick := _rng.randf() * total
	for i in ids.size():
		pick -= weights[i]
		if pick <= 0.0:
			return ids[i]
	return ids[ids.size() - 1]


# ---------------------------------------------------------------- state machine
func _physics_process(delta: float) -> void:
	_time += delta
	match _state:
		State.AIM:
			_steer(delta)
			if Input.is_action_just_pressed(&"cast"):
				_power = 0.0
				_power_dir = 1.0
				_state = State.CHARGE
				_set_status("Release CAST to throw")
		State.CHARGE:
			_steer(delta)
			_power += _power_dir * delta / 1.1
			if _power >= 1.0:
				_power = 1.0
				_power_dir = -1.0
			elif _power <= 0.0:
				_power = 0.0
				_power_dir = 1.0
			if not Input.is_action_pressed(&"cast"):
				_do_cast()
		State.FLY:
			_tick_fly(delta)
		State.WAIT:
			_tick_wait(delta)
		State.BITE:
			_tick_bite(delta)
		State.FIGHT:
			pass
		State.RESULT:
			_result_t -= delta
			if _result_t <= 0.0:
				_result_label.text = ""
				_state = State.AIM
				_set_status("Aim with < >, then hold CAST to power up the throw")


func _steer(delta: float) -> void:
	var axis := Input.get_axis(&"steer_left", &"steer_right")
	_aim = clampf(_aim + axis * 0.9 * delta, -0.9, 0.9)


func _do_cast() -> void:
	_cast_dist_m = lerpf(MIN_CAST_M, MAX_CAST_M, _power)
	_bobber_start = _rod_tip()
	_bobber_target = _bobber_start + _aim_dir() * _cast_dist_m * PX_PER_M
	_bobber_pos = _bobber_start
	_fly_t = 0.0
	_fish_id = ""
	_state = State.FLY
	_set_status("")


func _tick_fly(delta: float) -> void:
	_fly_t = minf(_fly_t + delta / 0.8, 1.0)
	_bobber_pos = _bobber_start.lerp(_bobber_target, _fly_t)
	_bobber_height = sin(_fly_t * PI) * (40.0 + _cast_dist_m * 1.6)
	if _fly_t >= 1.0:
		_bobber_height = 0.0
		_splash(_bobber_pos)
		_state = State.WAIT
		_wait_t = _rng.randf_range(3.0, 9.0)
		_ripple_clock = 0.0
		_set_status("Waiting...   (tap CAST to reel in)")


func _tick_wait(delta: float) -> void:
	if Input.is_action_just_pressed(&"cast"):
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
	_fish_time += delta
	if Input.is_action_just_pressed(&"reel_in"):
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
	_fish_time = 0.0
	_event_t = _rng.randf_range(0.8, 1.6)
	_set_status("Something is near...")


func _fish_event() -> void:
	if _nib_left > 0:
		_nib_left -= 1
		_dip = 1.0
		_buzz(35)
		_add_ripple(_bobber_pos)
		_set_status("Nibble!  Wait for the real bite")
		var hz := maxf(float(_prof["noise_hz"]), 0.5)
		_event_t = _rng.randf_range(0.6, 1.4) * 2.5 / hz
	else:
		_state = State.BITE
		_bite_t = float(_prof["bite_window_s"])
		_dip = 2.0
		_buzz(90)
		_add_ripple(_bobber_pos, true)
		_set_status("BITE!  Press REEL now")


func _tick_bite(delta: float) -> void:
	_bite_t -= delta
	if Input.is_action_just_pressed(&"reel_in"):
		_hook_fish()
		return
	if _bite_t <= 0.0:
		if _rng.randf() < float(_prof["self_hook_chance"]):
			_hook_fish()
		else:
			_fish_leaves("Too slow. It got away with the bait")


func _fish_leaves(message: String) -> void:
	_fish_id = ""
	_state = State.WAIT
	_wait_t = _rng.randf_range(4.0, 10.0)
	_set_status(message)


func _retrieve(message: String) -> void:
	_fish_id = ""
	_dip = 0.0
	_state = State.AIM
	_set_status(message + ".   Aim and throw again")


func _hook_fish() -> void:
	var species := BiomeDB.get_species(_fish_id)
	_weight_kg = BiomeDB.roll_weight_kg(_fish_id, _rng)
	_fishing.apply_rig(BiomeDB.get_rig(RIG_ID))
	_fishing.hook_fish(_fish_id, species, _weight_kg, _cast_dist_m)
	_state = State.FIGHT
	_dip = 0.0
	_kick = 0.18
	_fight_hint = ""
	_buzz(120)
	_splash(_bobber_pos)
	_tension_bar.visible = true
	_stamina_bar.visible = true
	_tension_label.visible = true
	_set_status("FISH ON!  Hold REEL.  Ease off when the line is tight")


# ---------------------------------------------------------------- fight results
func _on_tension(tension_n: float, ratio: float, bend: float) -> void:
	_tension_ratio = ratio
	_rod_bend_target = bend
	_shake = ratio * ratio


func _end_fight() -> void:
	_tension_bar.visible = false
	_stamina_bar.visible = false
	_tension_label.visible = false
	_fish_id = ""
	_rod_bend_target = 0.0
	_shake = 0.0
	_state = State.RESULT
	_result_t = 3.6


func _on_caught(id: String, weight_kg: float) -> void:
	var sp := BiomeDB.get_species(id)
	var value := int(round(float(sp["base_price"]) * pow(maxf(weight_kg, 0.05), 0.8)))
	GameSession.coins += value
	GameSession.catches.append({"fish_id": id, "name": sp["name"], "weight_kg": weight_kg, "value": value, "spot_id": GameSession.spot_id})
	_update_coins()
	_result_label.text = "CAUGHT!\n%s  %.2f kg   +%d" % [sp["name"], weight_kg, value]
	_set_status("Nice one")
	_end_fight()


func _on_snapped(_id: String) -> void:
	_buzz(300)
	_result_label.text = "Line snapped!"
	_set_status("Too much tension. Ease off the reel on the runs")
	_end_fight()


func _on_escaped(_id: String) -> void:
	_result_label.text = "It got away"
	_set_status("The line went slack for too long")
	_end_fight()


# ---------------------------------------------------------------- per-frame visuals
func _process(delta: float) -> void:
	_dip = maxf(0.0, _dip - delta * 2.5)
	_kick = maxf(0.0, _kick - delta * 0.6)
	if _state == State.WAIT or _state == State.BITE:
		_rod_bend_target = _dip * 0.25
	elif _state != State.FIGHT:
		_rod_bend_target = 0.0
	_rod_bend = lerpf(_rod_bend, _rod_bend_target, 1.0 - exp(-10.0 * delta))

	for r in _ripples:
		r["age"] = float(r["age"]) + delta
	_ripples.assign(_ripples.filter(func(r: Dictionary) -> bool: return float(r["age"]) < 1.6))
	for d in _drops:
		d["age"] = float(d["age"]) + delta
		d["pos"] = Vector2(d["pos"]) + Vector2(d["vel"]) * delta
		d["vel"] = Vector2(d["vel"]) * (1.0 - 2.5 * delta)
	_drops.assign(_drops.filter(func(d: Dictionary) -> bool: return float(d["age"]) < 0.7))

	_power_bar.visible = _state == State.CHARGE
	_power_bar.value = _power
	if _state == State.FIGHT:
		_fight_feedback(delta)
		_tension_bar.value = clampf(_tension_ratio, 0.0, 1.0)
		_stamina_bar.value = _fishing.stamina
		_tension_fill.bg_color = Color(0.3, 0.85, 0.4).lerp(Color(1.0, 0.25, 0.2), clampf((_tension_ratio - 0.4) / 0.5, 0.0, 1.0))
		_tension_label.text = "Line %.0f / %.0f N    Clutch %.0f N    Fish %.0f m away" % [_fishing.tension_n, _fishing.line_break_force_n, _fishing.drag_setting_n, _fishing.fish_pos_m]

	_update_camera(delta)
	queue_redraw()


## Coaching line during the fight, plus splashes and a buzz when the fish makes a run.
func _fight_feedback(delta: float) -> void:
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
	if _fishing._burst_mult > 1.0 and _rng.randf() < delta * 2.5:
		_splash(_fish_pos())
		_buzz(25)


func _update_camera(delta: float) -> void:
	var target_pos := Vector2(0.0, -190.0)
	var target_zoom := 0.85
	match _state:
		State.FLY, State.WAIT, State.BITE:
			target_pos = HAND.lerp(_bobber_pos, 0.55)
			target_zoom = 1.2
		State.FIGHT:
			var fp := _fish_pos()
			target_pos = (HAND + fp) * 0.5
			var span := HAND.distance_to(fp) + 260.0
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
	_draw_fish_in_water()
	_draw_ripples()
	_draw_line_and_bobber()
	_draw_angler()
	_draw_gulls()


func _draw_sparkles() -> void:
	for s in _sparkles:
		var tw := sin(_time * 2.6 + s.z)
		if tw > 0.55:
			var k := (tw - 0.55) / 0.45
			var p := Vector2(s.x + sin(_time * 0.3 + s.z) * 20.0, s.y)
			var c := Color(1.0, 1.0, 1.0, 0.8 * k)
			draw_line(p - Vector2(6.0 * k, 0.0), p + Vector2(6.0 * k, 0.0), c, 2.0)
			draw_line(p - Vector2(0.0, 6.0 * k), p + Vector2(0.0, 6.0 * k), c, 2.0)


func _draw_gulls() -> void:
	for i in 3:
		var fi := float(i)
		var x := fmod(_time * (60.0 + fi * 18.0) + fi * 900.0, 3200.0) - 1600.0
		var p := Vector2(x, -520.0 + fi * 170.0 + sin(_time * 0.5 + fi) * 40.0)
		var flap := sin(_time * 7.0 + fi * 2.0) * 7.0
		var sh := p + Vector2(30.0, 60.0)
		draw_polyline(PackedVector2Array([sh + Vector2(-14.0, -flap * 0.5), sh, sh + Vector2(14.0, -flap * 0.5)]), Color(0.0, 0.0, 0.0, 0.18), 3.0)
		draw_polyline(PackedVector2Array([p + Vector2(-16.0, -flap), p + Vector2(0.0, 3.0), p + Vector2(16.0, -flap)]), Color(1.0, 1.0, 1.0, 0.95), 3.0)


func _draw_crowd() -> void:
	for a in _crowd:
		var x := float(a["x"])
		var ph := float(a["phase"])
		var tip := Vector2(x + sin(ph) * 20.0, -30.0)
		var end := Vector2(x + sin(_time * 0.4 + ph) * 14.0 + sin(ph) * 30.0, -float(a["len"]))
		draw_line(Vector2(x, 20.0), tip, Color(0.2, 0.13, 0.08), 3.0)
		draw_line(tip, end, Color(1.0, 1.0, 1.0, 0.35), 1.0)
		draw_circle(end, 3.0, Color(0.95, 0.3, 0.2, 0.9))
		draw_circle(Vector2(x, 26.0), 11.0, Color(0.25 + 0.3 * absf(sin(ph)), 0.25, 0.35))
		draw_circle(Vector2(x, 24.0), 6.0, Color(0.9, 0.75, 0.6))


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
		var lx := -1200.0
		while lx <= 1200.0:
			draw_circle(Vector2(lx, 62.0), 80.0, Color(1.0, 0.85, 0.5, 0.10))
			draw_circle(Vector2(lx, 62.0), 7.0, Color(1.0, 0.95, 0.7))
			lx += 240.0
		_draw_crowd()
	elif kind == "harbor":
		draw_rect(Rect2(-w, 0.0, w * 2.0, 150.0), base)
		draw_rect(Rect2(-w, 0.0, w * 2.0, 8.0), base.darkened(0.4))
		var bx := -1200.0
		while bx <= 1200.0:
			draw_circle(Vector2(bx, 26.0), 9.0, base.darkened(0.5))
			bx += 160.0
		var hx := -1120.0
		while hx <= 1120.0:
			draw_circle(Vector2(hx, 110.0), 70.0, Color(1.0, 0.85, 0.5, 0.08))
			draw_circle(Vector2(hx, 110.0), 6.0, Color(1.0, 0.95, 0.7))
			hx += 320.0
		for side in [-1.0, 1.0]:
			_draw_moored_boat(Vector2(430.0 * side, -58.0))
	elif kind == "beach":
		var poly := _edge_pts.duplicate()
		poly.append(Vector2(w, 900.0))
		poly.append(Vector2(-w, 900.0))
		draw_colored_polygon(poly, base)
		var wet := PackedVector2Array()
		for p in _edge_pts:
			wet.append(p + Vector2(0.0, 12.0))
		draw_polyline(wet, base.darkened(0.14), 16.0)
		for pb in _pebbles:
			draw_circle(Vector2(pb.x, pb.y), pb.z, base.darkened(0.25))
		_draw_foam()
	else:
		draw_rect(Rect2(-w, 40.0, w * 2.0, 900.0), base.darkened(0.2))
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


func _draw_foam() -> void:
	for layer in 2:
		var pts := PackedVector2Array()
		var x := -1400.0
		while x <= 1400.0:
			pts.append(Vector2(x, -4.0 - float(layer) * 9.0 + sin(x * 0.02 + _time * 1.4 + float(layer)) * 5.0))
			x += 50.0
		draw_polyline(pts, Color(1.0, 1.0, 1.0, 0.55 - float(layer) * 0.2), 3.0)


func _draw_moored_boat(pos: Vector2) -> void:
	var bob := sin(_time * 1.3 + pos.x) * 3.0
	var p := pos + Vector2(0.0, bob)
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


func _draw_fish_in_water() -> void:
	if _state == State.FIGHT:
		var fp := _fish_pos()
		var heading := (HAND - fp)
		var length := 28.0 + sqrt(_weight_kg) * 16.0
		draw_circle(fp, length * 0.7, Color(1.0, 1.0, 1.0, 0.10 + 0.25 * _tension_ratio))
		_draw_fish_shape(fp, heading, length, Color(0.04, 0.16, 0.22, 0.8))
	elif (_state == State.WAIT or _state == State.BITE) and _fish_id != "":
		var a := _time * 1.2
		var orbit := 44.0 if _state == State.WAIT else 14.0
		var fp2 := _bobber_pos + Vector2(cos(a), sin(a)) * orbit
		var tangent := Vector2(-sin(a), cos(a))
		var wt: Vector2 = BiomeDB.get_species(_fish_id)["weight_kg"]
		_draw_fish_shape(fp2, tangent, 24.0 + sqrt(wt.y) * 5.0, Color(0.04, 0.16, 0.22, 0.4))


func _draw_ripples() -> void:
	for r in _ripples:
		var age := float(r["age"])
		var k := age / 1.6
		var radius := 8.0 + age * (55.0 if bool(r["big"]) else 32.0)
		draw_arc(Vector2(r["pos"]), radius, 0.0, TAU, 32, Color(1.0, 1.0, 1.0, 0.7 * (1.0 - k)), 2.5)
	for d in _drops:
		var k2 := float(d["age"]) / 0.7
		draw_circle(Vector2(d["pos"]), 3.0 * (1.0 - k2) + 1.0, Color(1.0, 1.0, 1.0, 0.8 * (1.0 - k2)))


func _line_points(a: Vector2, b: Vector2, sag: float) -> PackedVector2Array:
	var mid := (a + b) * 0.5 + (b - a).orthogonal().normalized() * sag
	var pts := PackedVector2Array()
	for i in 13:
		var t := float(i) / 12.0
		pts.append(a.lerp(mid, t).lerp(mid.lerp(b, t), t))
	return pts


func _draw_line_and_bobber() -> void:
	var tip := _rod_tip()
	var line_col := Color(1.0, 1.0, 1.0, 0.85)
	match _state:
		State.CHARGE:
			var landing := tip + _aim_dir() * lerpf(MIN_CAST_M, MAX_CAST_M, _power) * PX_PER_M
			var steps := 18
			for i in steps:
				if i % 2 == 0:
					var p0 := tip.lerp(landing, float(i) / float(steps))
					var p1 := tip.lerp(landing, float(i + 1) / float(steps))
					draw_line(p0, p1, Color(1.0, 1.0, 1.0, 0.5), 3.0)
			draw_arc(landing, 16.0 + sin(_time * 6.0) * 3.0, 0.0, TAU, 28, Color(1.0, 0.9, 0.4, 0.9), 3.0)
		State.FLY:
			draw_polyline(_line_points(tip, _bobber_pos + Vector2(0.0, -_bobber_height), 0.0), line_col, 1.5)
			draw_circle(_bobber_pos + Vector2(5.0, 7.0), 6.0, Color(0.0, 0.0, 0.0, 0.25))
			_draw_bobber(_bobber_pos + Vector2(0.0, -_bobber_height))
		State.WAIT, State.BITE:
			draw_polyline(_line_points(tip, _bobber_pos, 16.0), line_col, 1.5)
			_draw_bobber(_bobber_pos + Vector2(0.0, _dip * 6.0))
		State.FIGHT:
			var slack := 1.0 - clampf(_tension_ratio * 2.0, 0.0, 1.0)
			draw_polyline(_line_points(tip, _fish_pos(), slack * 40.0), line_col, 1.5 + _tension_ratio * 1.5)
		_:
			pass


func _draw_bobber(pos: Vector2) -> void:
	draw_circle(pos, 8.0, Color(0.95, 0.95, 0.95))
	draw_circle(pos + Vector2(0.0, -3.0), 6.0, Color(0.95, 0.25, 0.2))


func _draw_angler() -> void:
	var d := _aim_dir()
	draw_circle(HAND + Vector2(7.0, 14.0), 21.0, Color(0.0, 0.0, 0.0, 0.25))
	draw_circle(HAND + Vector2(0.0, 10.0), 18.0, Color(0.15, 0.30, 0.55))
	draw_circle(HAND + Vector2(0.0, 10.0), 10.0, Color(0.93, 0.75, 0.6))
	draw_circle(HAND + Vector2(0.0, 7.0), 8.0, Color(0.9, 0.3, 0.2))
	var ctrl := HAND + d * ROD_LEN * 0.55 + d.orthogonal() * _rod_bend * ROD_BEND_PX * 0.35
	var rod := PackedVector2Array()
	var tip := _rod_tip()
	for i in 11:
		var t := float(i) / 10.0
		rod.append(HAND.lerp(ctrl, t).lerp(ctrl.lerp(tip, t), t))
	draw_polyline(rod, Color(0.20, 0.13, 0.08), 5.0)
	draw_polyline(rod, Color(0.55, 0.40, 0.25), 2.0)
